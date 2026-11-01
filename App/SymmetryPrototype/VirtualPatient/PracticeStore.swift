import Combine
import Foundation
import SymmetryCore
import SymmetryModels

/// The virtual patient's own storage: a separate `SessionRepository` under
/// Application Support/Practice, never the study repository, plus a sidecar that records
/// which bundled render every practice capture came from.
///
/// Sidecar: `<root>/demo-keys.json`, `[captureUUIDString: DemoAssetKey]`, written atomically.
/// `SessionRepository.loadAll` ignores it (it is not a session directory) and
/// `SessionRepository.deleteAll` removes it with everything else under the root.
@MainActor
final class PracticeStore: ObservableObject {
    enum PracticeError: Error {
        case patientUnavailable
        case missingStage(Int)
        case missingAsset(String)
        case unreadableImage(String)
        case saveFailed(String?)
    }

    static let studyID = "DEMO-VP1"
    /// The seed `seed()` uses by default. Change it here if the designed sign pattern of
    /// sets 1 and 2 ever breaks under jitter.
    static let defaultRNGSeed: UInt64 = 7
    /// Point jitter sd, as a multiple of sigma times L.
    static let pointJitterFactor = 0.3
    /// Outline jitter sd, as a multiple of sigma times L.
    static let outlineJitterFactor = 0.2

    private static let sidecarName = "demo-keys.json"

    /// Application Support/Practice, created. A sibling of `SessionRepository.defaultRoot()`.
    static func defaultRoot() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let root = support.appendingPathComponent("Practice", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    let store: SessionStore
    let patient: DemoPatient?
    let root: URL

    private let imageData: (String) -> Data?
    private var keys: [String: DemoAssetKey]
    private var forward: AnyCancellable?

    init(root: URL, patient: DemoPatient?, imageData: @escaping (String) -> Data? = { DemoPatient.imageData(named: $0) }) {
        let repository: SessionRepository
        do {
            repository = try SessionRepository(root: root)
        } catch {
            // Fall back to a temporary directory rather than crash, as SessionStore does.
            repository = try! SessionRepository(root: FileManager.default.temporaryDirectory
                .appendingPathComponent("Practice", isDirectory: true))
        }
        self.root = repository.root
        self.store = SessionStore(repository: repository)
        self.patient = patient
        self.imageData = imageData
        self.keys = PracticeStore.loadKeys(at: repository.root.appendingPathComponent(PracticeStore.sidecarName))
        self.forward = store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    convenience init() {
        let root = (try? PracticeStore.defaultRoot())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Practice", isDirectory: true)
        self.init(root: root, patient: DemoPatient.loadBundled())
    }

    /// The virtual patient session, when it has been seeded.
    var session: StudySession? {
        store.sessions.first { $0.studyID == PracticeStore.studyID }
    }

    var isAvailable: Bool { patient != nil }

    // MARK: - Seeding

    /// Deletes all practice data, then builds DEMO-VP1: sets 1 and 2 with three photos and
    /// jittered frontal points and outlines, set 3 with three photos and no points, no set 4.
    /// Set 1 is at `now` minus 160 minutes and later sets follow 40 minutes apart.
    @discardableResult
    func seed(now: Date = Date(), rngSeed: UInt64 = PracticeStore.defaultRNGSeed) throws -> StudySession {
        deleteAll()
        guard let patient else { throw PracticeError.patientUnavailable }

        let start = now.addingTimeInterval(-160 * 60)
        var session = StudySession(studyID: PracticeStore.studyID, createdAt: start)
        for stageIndex in 1...3 {
            guard let stage = patient.stage(stageIndex) else { throw PracticeError.missingStage(stageIndex) }
            let createdAt = start.addingTimeInterval(Double(stageIndex - 1) * 40 * 60)
            var set = CaptureSet(stage: stage.operativeStage, positioning: stage.positioning, createdAt: createdAt)
            for (offset, angle) in ViewAngle.allCases.enumerated() where stage.views[angle] != nil {
                var capture = try makeCapture(stageIndex: stageIndex, angle: angle, variant: .sharp, in: session,
                                              tiltDegrees: 0.5, overridden: false,
                                              capturedAt: createdAt.addingTimeInterval(Double(offset) * 30))
                if stageIndex <= 2, angle == .frontal,
                   let truth = truthLandmarks(stageIndex: stageIndex, angle: .frontal,
                                              jitterSigmaRatio: PracticeStore.pointJitterFactor * patient.sigmaRatio,
                                              seed: PracticeStore.stageSeed(rngSeed, stageIndex)) {
                    capture.landmarks = PracticeStore.scaled(truth, to: capture.imageSize)
                }
                set.update(capture)
            }
            session.update(set)
            guard store.save(session) else { throw PracticeError.saveFailed(store.lastError) }
        }
        return session
    }

    /// Starts the virtual patient again from the beginning. Same as `seed()`.
    @discardableResult
    func reset() throws -> StudySession {
        try seed()
    }

    // MARK: - Captures

    /// Runs a bundled render through the unchanged `ImageBridge.process`, writes the JPEG into
    /// the practice session and records its asset key. The caller adds the capture to a set.
    func makeCapture(stageIndex: Int, angle: ViewAngle, variant: DemoAssetKey.Variant, in session: StudySession,
                     tiltDegrees: Double?, overridden: Bool) throws -> Capture {
        try makeCapture(stageIndex: stageIndex, angle: angle, variant: variant, in: session,
                        tiltDegrees: tiltDegrees, overridden: overridden, capturedAt: Date())
    }

    private func makeCapture(stageIndex: Int, angle: ViewAngle, variant: DemoAssetKey.Variant, in session: StudySession,
                             tiltDegrees: Double?, overridden: Bool, capturedAt: Date) throws -> Capture {
        guard let patient else { throw PracticeError.patientUnavailable }
        guard let view = patient.view(stage: stageIndex, angle: angle) else { throw PracticeError.missingStage(stageIndex) }
        // Only frontal renders have a blurred variant; anything else falls back to the sharp one.
        let usedVariant: DemoAssetKey.Variant = (variant == .blurred && view.blurredImage != nil) ? .blurred : .sharp
        let name = usedVariant == .blurred ? (view.blurredImage ?? view.image) : view.image
        guard let data = imageData(name) else { throw PracticeError.missingAsset(name) }
        guard let processed = ImageBridge.process(data, tiltDegrees: tiltDegrees, thresholds: QualityThresholds()) else {
            throw PracticeError.unreadableImage(name)
        }
        let filename = "\(angle.rawValue)-\(UUID().uuidString.prefix(8)).jpg"
        let capture = Capture(angle: angle, imageFilename: filename, pixelWidth: processed.width, pixelHeight: processed.height,
                              capturedAt: capturedAt, quality: processed.quality, tiltDegrees: tiltDegrees,
                              qualityOverridden: overridden)
        try store.writeImage(processed.jpeg, for: capture, in: session)
        recordAsset(DemoAssetKey(stageIndex: stageIndex, angle: angle, variant: usedVariant), forCaptureID: capture.id)
        return capture
    }

    /// The ground truth of one render, with seeded Gaussian jitter: points get an sd of
    /// `jitterSigmaRatio * L` per axis and outline points two thirds of that, where L is the
    /// truth notch to midline bottom distance in pixels. A ratio of 0 gives the exact truth.
    func truthLandmarks(stageIndex: Int, angle: ViewAngle, jitterSigmaRatio: Double, seed: UInt64) -> LandmarkSet? {
        guard let patient, var set = patient.truth(stage: stageIndex, angle: angle) else { return nil }
        guard jitterSigmaRatio > 0 else { return set }
        let reference = PracticeStore.referenceLength(set)
            ?? patient.truth(stage: stageIndex, angle: .frontal).flatMap(PracticeStore.referenceLength)
        guard let L = reference else { return set }
        let pointSD = jitterSigmaRatio * L
        let outlineSD = pointSD * PracticeStore.outlineJitterFactor / PracticeStore.pointJitterFactor
        var rng = SeededGaussian(seed: seed)
        for type in LandmarkType.allCases {
            guard let p = set[type] else { continue }
            set[type] = Point2D(x: p.x + rng.next() * pointSD, y: p.y + rng.next() * pointSD)
        }
        set.leftContour = set.leftContour.map { Point2D(x: $0.x + rng.next() * outlineSD, y: $0.y + rng.next() * outlineSD) }
        set.rightContour = set.rightContour.map { Point2D(x: $0.x + rng.next() * outlineSD, y: $0.y + rng.next() * outlineSD) }
        return set
    }

    // MARK: - Asset keys

    func assetKey(forCaptureID id: UUID) -> DemoAssetKey? {
        keys[id.uuidString]
    }

    func recordAsset(_ key: DemoAssetKey, forCaptureID id: UUID) {
        keys[id.uuidString] = key
        writeKeys()
    }

    /// Removes every practice session, image, asset key and the sessions' UI flags.
    func deleteAll() {
        for session in store.sessions { UIFlags.clear(session: session) }
        store.deleteAll()
        keys = [:]
        try? FileManager.default.removeItem(at: sidecarURL)
    }

    // MARK: - Private

    private var sidecarURL: URL { root.appendingPathComponent(PracticeStore.sidecarName) }

    private func writeKeys() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(keys) else { return }
        do {
            try data.write(to: sidecarURL, options: [.atomic])
        } catch {
            store.lastError = "Could not save the virtual patient photo list."
        }
    }

    private static func loadKeys(at url: URL) -> [String: DemoAssetKey] {
        guard let data = try? Data(contentsOf: url),
              let keys = try? JSONDecoder().decode([String: DemoAssetKey].self, from: data) else { return [:] }
        return keys
    }

    private static func referenceLength(_ set: LandmarkSet) -> Double? {
        guard let n = set[.sternalNotch], let b = set[.midlineBottom] else { return nil }
        let d = n.distance(to: b)
        return d > 0 ? d : nil
    }

    private static func stageSeed(_ seed: UInt64, _ stageIndex: Int) -> UInt64 {
        seed ^ (UInt64(stageIndex) &* 0x9E37_79B9_7F4A_7C15)
    }

    /// Rescales truth pixels when the processed photo has a different size from the render.
    private static func scaled(_ set: LandmarkSet, to size: Point2D) -> LandmarkSet {
        guard set.imageSize.x > 0, set.imageSize.y > 0, set.imageSize != size else { return set }
        let sx = size.x / set.imageSize.x, sy = size.y / set.imageSize.y
        func f(_ p: Point2D) -> Point2D { Point2D(x: p.x * sx, y: p.y * sy) }
        return LandmarkSet(points: set.points.mapValues(f), leftContour: set.leftContour.map(f),
                           rightContour: set.rightContour.map(f), imageSize: size)
    }
}

/// SplitMix64 with Box-Muller: deterministic standard normal draws for a given seed.
private struct SeededGaussian {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    private mutating func nextBits() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in (0, 1).
    private mutating func uniform() -> Double {
        (Double(nextBits() >> 11) + 0.5) / 9_007_199_254_740_992.0
    }

    mutating func next() -> Double {
        let u1 = uniform(), u2 = uniform()
        return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
    }
}

/// Whether a session may be exported. Practice is refused by two independent markers: the
/// session kind and the reserved DEMO- study code.
enum ExportEligibility: Equatable {
    case allowed, practiceRefused

    static let refusalMessage = "Practice sessions are not exported. Start a study session to export."

    static func check(kind: SessionKind, studyID: String) -> ExportEligibility {
        if kind == .practice { return .practiceRefused }
        return StudyIDCheck.isReserved(studyID) ? .practiceRefused : .allowed
    }
}

/// App-side checks on a new study code, run before the unchanged `StudySession.validateStudyID`.
enum StudyIDCheck {
    static let reservedPrefix = "DEMO-"
    static let reservedMessage = "DEMO- is kept for the virtual patient. Choose another code."

    /// True for codes that start with DEMO- or are DEMO, in any case.
    static func isReserved(_ raw: String) -> Bool {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return code.hasPrefix(reservedPrefix) || code == "DEMO"
    }

    /// The trimmed code, or the message to show.
    static func validateNewStudyID(_ raw: String) -> Result<String, String> {
        if isReserved(raw) { return .failure(reservedMessage) }
        switch StudySession.validateStudyID(raw) {
        case .success(let code): return .success(code)
        case .failure(let error): return .failure(error.message)
        }
    }
}

/// Lets `StudyIDCheck.validateNewStudyID` return `Result<String, String>`, whose failure is
/// the message itself.
extension String: @retroactive Error {}
