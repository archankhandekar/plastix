#if DEBUG
import SwiftUI
import SymmetryCore
import SymmetryModels

/// DEBUG-only route harness: opens any screen straight from launch arguments (see
/// `LaunchRoute`) over freshly seeded temporary data, for screenshots and manual checks.
///
/// Safeguards:
/// - every launch gets new roots NSTemporaryDirectory()/RouteHarness-<uuid>/Study and /Practice;
/// - settings and UI flags live in the UserDefaults suite "RouteHarness", wiped at launch;
/// - there is no argument that points it at real data.
/// Release builds contain none of this file.
@MainActor
enum RouteHarness {
    static let suiteName = "RouteHarness"
    static let studyHarnessID = "S-HARNESS"

    /// What the app root needs from a harness launch.
    struct Launch {
        let route: LaunchRoute
        let settings: AppSettings
        let navigator: AppNavigator
        let stores: SessionStores
        /// The sheet or cover the route opens over its path, if any.
        let presentation: Presentation?
        let studyRoot: URL
        let practiceRoot: URL
    }

    /// Covers and sheets a route can open.
    enum Presentation {
        case capture(CaptureTarget)
        case photocheck(CaptureView.PendingCapture, kind: SessionKind)
        case newSession(studyID: String, showValidation: Bool)
        case newSet(NewSet)
        case gallery

        struct CaptureTarget {
            let ref: SessionRef
            let set: CaptureSet
            let index: Int
            let angles: [ViewAngle]
            let practiceRetake: Bool
        }

        struct NewSet {
            let ref: SessionRef
            let suggestedStage: OperativeStage
            let previousPositioning: Positioning?
            let previousSetIndex: Int?
            let previousStage: OperativeStage?
            let nextIndex: Int
        }
    }

    // MARK: - Environment

    /// Builds the stores, settings, navigator path and presentation for one harness launch.
    static func makeEnvironment(_ route: LaunchRoute) -> Launch {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        // Older harness roots are only ever temporary; clear them so launches do not pile up.
        if let old = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            for url in old where url.lastPathComponent.hasPrefix("RouteHarness-") { try? fm.removeItem(at: url) }
        }
        let base = tmp.appendingPathComponent("RouteHarness-\(UUID().uuidString)", isDirectory: true)
        let studyRoot = base.appendingPathComponent("Study", isDirectory: true)
        let practiceRoot = base.appendingPathComponent("Practice", isDirectory: true)
        try? fm.createDirectory(at: studyRoot, withIntermediateDirectories: true)
        try? fm.createDirectory(at: practiceRoot, withIntermediateDirectories: true)

        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        UIFlags.defaults = defaults
        let settings = AppSettings(defaults: defaults)
        settings.researchNoticeAccepted = route.skipNotice

        let patient = DemoPatient.loadBundled()
        let practice = PracticeStore(root: practiceRoot, patient: patient)
        if route.demo { _ = try? practice.seed() }

        // The study session S-HARNESS: the same seeding, written by a second PracticeStore
        // over the temporary study root, then renamed. Its store becomes the study store.
        let studyStore: SessionStore
        var studyWriter: PracticeStore?
        if route.seedStudy {
            let writer = PracticeStore(root: studyRoot, patient: patient)
            if var session = try? writer.seed() {
                session.studyID = studyHarnessID
                writer.store.save(session)
            }
            studyStore = writer.store
            studyWriter = writer
        } else if let repository = try? SessionRepository(root: studyRoot) {
            studyStore = SessionStore(repository: repository)
        } else {
            studyStore = PracticeStore(root: studyRoot, patient: nil).store
        }

        let stores = SessionStores(study: studyStore, practice: practice)
        let navigator = AppNavigator()

        // The session the route opens, with the PracticeStore that can write into it.
        var target: (ref: SessionRef, writer: PracticeStore)?
        if route.targetsStudy, let writer = studyWriter,
           let session = writer.store.sessions.first(where: { $0.studyID == studyHarnessID }) {
            target = (SessionRef(id: session.id, kind: .study), writer)
        } else if let session = practice.session {
            target = (SessionRef(id: session.id, kind: .practice), practice)
        }

        var presentation: Presentation?
        if let target, let patient {
            let seeder = Seeder(writer: target.writer, sessionID: target.ref.id, patient: patient)
            presentation = build(route, seeder: seeder, ref: target.ref, navigator: navigator, settings: settings)
        } else {
            presentation = buildWithoutSession(route, navigator: navigator)
        }

        // The study writer's asset-key sidecar is not needed by the study store; remove it so
        // no DemoAssetKey sits next to a study photo.
        if studyWriter != nil {
            try? fm.removeItem(at: studyRoot.appendingPathComponent("demo-keys.json"))
        }

        print("RouteHarness: route=\(route.route.rawValue) study root=\(studyRoot.path) practice root=\(practiceRoot.path) suite=\(suiteName)")
        fflush(stdout)

        return Launch(route: route, settings: settings, navigator: navigator, stores: stores,
                      presentation: presentation, studyRoot: studyRoot, practiceRoot: practiceRoot)
    }

    /// Path and presentation when no session could be seeded (for example -UIDemo 0 alone).
    private static func buildWithoutSession(_ route: LaunchRoute, navigator: AppNavigator) -> Presentation? {
        switch route.route {
        case .settings: navigator.path = [.settings]
        case .explainer: navigator.path = [.explainer]
        default: navigator.path = []
        }
        switch route.route {
        case .newSession: return .newSession(studyID: route.studyCode ?? "", showValidation: route.studyCode != nil)
        case .gallery: return .gallery
        default: return nil
        }
    }

    /// Applies -UIState, then sets the navigator path exactly as the route table lists it.
    private static func build(_ route: LaunchRoute, seeder: Seeder, ref: SessionRef,
                              navigator: AppNavigator, settings: AppSettings) -> Presentation? {
        let stage = route.resolvedStage
        var state = route.state
        if route.route == .stages, state == nil { state = .complete }

        // Routes that open an existing set need it to exist.
        switch route.route {
        case .symmetry, .obliques, .review:
            seeder.ensureSets(upTo: stage, marked: true)
        case .mark:
            seeder.ensureSets(upTo: stage, marked: false)
        default:
            break
        }
        if let state { seeder.apply(state, stage: stage) }

        let home = AppRoute.session(ref)
        switch route.route {
        case .notice, .sessions:
            navigator.path = []
        case .home, .tour:
            navigator.path = [home]
        case .symmetry, .obliques:
            if let set = seeder.set(stage) {
                navigator.path = [home, .symmetry(ref, setID: set.id, tab: route.route == .obliques ? .obliques : .frontal,
                                                  focus: route.focus, obliqueMode: route.obliqueMode)]
            } else {
                navigator.path = [home]
            }
        case .stages:
            navigator.path = [home, .acrossStages(ref)]
        case .compare:
            navigator.path = [home, .acrossStages(ref),
                              .compare(ref, earlierID: seeder.set(1)?.id, laterID: seeder.set(2)?.id)]
        case .review:
            navigator.path = seeder.set(stage).map { [home, .review(ref, setID: $0.id)] } ?? [home]
        case .mark:
            if let set = seeder.set(stage), let frontal = set.frontal {
                navigator.path = [home, .markPoints(ref, setID: set.id, captureID: frontal.id, showTruth: route.showTruth)]
            } else {
                navigator.path = [home]
            }
        case .export:
            navigator.path = [home, .export(ref)]
        case .settings:
            navigator.path = [.settings]
        case .explainer:
            navigator.path = [.explainer]
        case .capture:
            navigator.path = [home]
            return seeder.captureTarget(stage: stage, ref: ref, first: route.captureAngle ?? .frontal,
                                        practiceRetake: route.practiceRetake).map(Presentation.capture)
        case .photocheck:
            navigator.path = [home]
            return seeder.pendingFrontal(stage: stage, retake: route.practiceRetake, thresholds: settings.qualityThresholds)
                .map { .photocheck($0, kind: ref.kind) }
        case .newSession:
            navigator.path = []
            return .newSession(studyID: route.studyCode ?? "", showValidation: route.studyCode != nil)
        case .newSet:
            navigator.path = [home]
            return .newSet(seeder.newSetContext(ref: ref))
        case .gallery:
            navigator.path = []
            return .gallery
        }
        return nil
    }

    // MARK: - Seeding

    /// Writes into one seeded session through the PracticeStore that owns its root. Set N
    /// always uses the virtual patient's stage N renders, as `PracticeStore.seed()` does.
    @MainActor
    struct Seeder {
        let writer: PracticeStore
        let sessionID: UUID
        let patient: DemoPatient

        private var store: SessionStore { writer.store }
        private var session: StudySession? { store.session(id: sessionID) }
        private var maxStage: Int { (1...8).last { patient.stage($0) != nil } ?? 0 }

        func set(_ stage: Int) -> CaptureSet? {
            guard let ordered = session?.orderedCaptureSets, stage >= 1, stage <= ordered.count else { return nil }
            return ordered[stage - 1]
        }

        /// The ground truth of a stage's frontal, jittered like the seed and scaled to the photo.
        private func markedFromTruth(_ stage: Int, size: Point2D) -> LandmarkSet? {
            let seed = PracticeStore.defaultRNGSeed &+ UInt64(stage) &* 0x5851_F42D_4C95_7F2D
            guard let truth = writer.truthLandmarks(stageIndex: stage, angle: .frontal,
                                                    jitterSigmaRatio: PracticeStore.pointJitterFactor * patient.sigmaRatio,
                                                    seed: seed) else { return nil }
            return TeachingCheck.scaled(truth, to: size)
        }

        /// Adds sets until the session has `count` of them (at most one per bundled stage).
        func ensureSets(upTo count: Int, marked: Bool) {
            guard var session else { return }
            let target = min(count, maxStage)
            while session.captureSets.count < target {
                let index = session.captureSets.count + 1
                guard let stage = patient.stage(index) else { return }
                let createdAt = (session.orderedCaptureSets.last?.createdAt ?? Date().addingTimeInterval(-160 * 60))
                    .addingTimeInterval(40 * 60)
                var set = CaptureSet(stage: stage.operativeStage, positioning: stage.positioning, createdAt: createdAt)
                for angle in ViewAngle.allCases where stage.views[angle] != nil {
                    guard var capture = try? writer.makeCapture(stageIndex: index, angle: angle, variant: .sharp, in: session,
                                                                tiltDegrees: 0.5, overridden: false) else { continue }
                    if marked, angle == .frontal { capture.landmarks = markedFromTruth(index, size: capture.imageSize) }
                    set.update(capture)
                }
                session.update(set)
                guard store.save(session) else { return }
            }
        }

        /// Applies one -UIState to the session.
        func apply(_ state: LaunchRoute.SeedState, stage: Int) {
            if state == .complete {
                ensureSets(upTo: 4, marked: true)
                for index in 1...4 { mutateFrontal(index) { capture in
                    if capture.landmarks?.isComplete != true { capture.landmarks = markedFromTruth(index, size: capture.imageSize) }
                } }
                return
            }
            ensureSets(upTo: stage, marked: true)
            switch state {
            case .complete:
                break
            case .unmarked:
                mutateFrontal(stage) { $0.landmarks = nil }
            case .missingFold:
                mutateFrontal(stage) { capture in
                    if capture.landmarks == nil { capture.landmarks = markedFromTruth(stage, size: capture.imageSize) }
                    capture.landmarks?[.leftIMF] = nil
                }
            case .noOutlines:
                mutateFrontal(stage) { capture in
                    capture.landmarks?.leftContour = []
                    capture.landmarks?.rightContour = []
                }
            case .blurredKept:
                replaceWithBlurred(stage)
            }
        }

        private func mutateFrontal(_ stage: Int, _ change: (inout Capture) -> Void) {
            guard var session, var set = set(stage), var frontal = set.frontal else { return }
            change(&frontal)
            set.update(frontal)
            session.update(set)
            store.save(session)
        }

        private func replaceWithBlurred(_ stage: Int) {
            guard var session, var set = set(stage), let old = set.frontal,
                  var blurred = try? writer.makeCapture(stageIndex: stage, angle: .frontal, variant: .blurred, in: session,
                                                        tiltDegrees: 0.5, overridden: true) else { return }
            let kept = old.landmarks ?? markedFromTruth(stage, size: old.imageSize)
            blurred.landmarks = kept.map { TeachingCheck.scaled($0, to: blurred.imageSize) }
            store.deleteImage(for: old, in: session)
            set.update(blurred)
            session.update(set)
            store.save(session)
        }

        /// A new empty set at the stage preset, as set `stage`. Later sets are removed and
        /// missing earlier sets are added, so the camera shows that stage's renders.
        func captureTarget(stage: Int, ref: SessionRef, first: ViewAngle, practiceRetake: Bool) -> Presentation.CaptureTarget? {
            let index = max(1, min(stage, maxStage))
            ensureSets(upTo: index - 1, marked: true)
            guard var session else { return nil }
            let ordered = session.orderedCaptureSets
            if ordered.count >= index {
                for set in ordered[(index - 1)...] {
                    for capture in set.orderedCaptures { store.deleteImage(for: capture, in: session) }
                    session.captureSets.removeAll { $0.id == set.id }
                }
                store.save(session)
            }
            guard let preset = patient.stage(index) else { return nil }
            let set = CaptureSet(stage: preset.operativeStage, positioning: preset.positioning)
            let all = ViewAngle.allCases
            let start = all.firstIndex(of: first) ?? 0
            let angles = Array(all[start...] + all[..<start])
            return Presentation.CaptureTarget(ref: ref, set: set, index: index, angles: angles, practiceRetake: practiceRetake)
        }

        /// The stage's frontal render through ImageBridge.process, as the camera would hand it
        /// to the photo check. With `retake`, the blurred render.
        func pendingFrontal(stage: Int, retake: Bool, thresholds: QualityThresholds) -> CaptureView.PendingCapture? {
            guard let view = patient.view(stage: max(1, min(stage, maxStage)), angle: .frontal) else { return nil }
            let useBlurred = retake && view.blurredImage != nil
            let name = useBlurred ? (view.blurredImage ?? view.image) : view.image
            // The rendered roll plus the virtual camera's (static) drift: the same value the
            // practice camera reports, so the photo check never claims a tilt that is not there.
            let tilt = VirtualCameraSource(patient: patient, setIndex: max(1, min(stage, maxStage)), angle: .frontal)
                .tiltDegrees(at: 0, staticMotion: true)
            guard let data = DemoPatient.imageData(named: name),
                  let processed = ImageBridge.process(data, tiltDegrees: tilt, thresholds: thresholds) else { return nil }
            let key = DemoAssetKey(stageIndex: max(1, min(stage, maxStage)), angle: .frontal,
                                   variant: useBlurred ? .blurred : .sharp)
            return CaptureView.PendingCapture(angle: .frontal, processed: processed, tilt: tilt, assetKey: key)
        }

        /// What the New photo set sheet is pre-filled with after the last set.
        func newSetContext(ref: SessionRef) -> Presentation.NewSet {
            let ordered = session?.orderedCaptureSets ?? []
            let next = ordered.count + 1
            let presets = OperativeStage.presets
            let suggested = patient.stage(next)?.operativeStage ?? presets[min(ordered.count, presets.count - 1)]
            return Presentation.NewSet(ref: ref, suggestedStage: suggested,
                                       previousPositioning: ordered.last?.positioning,
                                       previousSetIndex: ordered.isEmpty ? nil : ordered.count,
                                       previousStage: ordered.last?.stage, nextIndex: next)
        }
    }
}

// MARK: - Presentation at the root

extension View {
    /// Presents the harness route's cover or sheet and applies its appearance arguments
    /// (-UIScheme, -UITextSize, -UIStatic). Apply it inside the root's environment objects.
    func routeHarness(_ launch: RouteHarness.Launch) -> some View {
        modifier(RouteHarnessPresenter(launch: launch))
            .modifier(RouteHarnessAppearance(route: launch.route))
    }
}

/// -UIScheme, -UITextSize and -UIStatic. Also re-applied inside every harness sheet and cover.
struct RouteHarnessAppearance: ViewModifier {
    let route: LaunchRoute

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(route.scheme)
            .transformEnvironment(\.dynamicTypeSize) { size in
                if let t = route.textSize { size = t }
            }
            .environment(\.staticMotion, route.staticMotion)
    }
}

private struct RouteHarnessPresenter: ViewModifier {
    let launch: RouteHarness.Launch

    private struct SheetItem: Identifiable {
        let id = UUID()
        let presentation: RouteHarness.Presentation
    }

    private struct CoverItem: Identifiable {
        let id = UUID()
        let capture: RouteHarness.Presentation.CaptureTarget
    }

    @State private var sheet: SheetItem?
    @State private var cover: CoverItem?
    @State private var didPresent = false
    /// Set by the New study session sheet; pushed once the sheet has dismissed.
    @State private var pendingSession: UUID?
    /// Set by the New photo set sheet; the camera opens once the sheet has dismissed.
    @State private var pendingCapture: RouteHarness.Presentation.CaptureTarget?

    func body(content: Content) -> some View {
        content
            .sheet(item: $sheet, onDismiss: sheetDismissed) { item in
                scoped(sheetContent(item.presentation), kind: kind(of: item.presentation))
            }
            .fullScreenCover(item: $cover) { item in
                scoped(CaptureView(sessionID: item.capture.ref.id, captureSet: item.capture.set, setIndex: item.capture.index,
                                   anglesToCapture: item.capture.angles,
                                   initialPracticeRetake: item.capture.practiceRetake),
                       kind: item.capture.ref.kind)
            }
            .task {
                guard !didPresent, let presentation = launch.presentation else { return }
                didPresent = true
                // Let the NavigationStack settle on its path before presenting over it.
                try? await Task.sleep(nanoseconds: 600_000_000)
                if case .capture(let capture) = presentation {
                    cover = CoverItem(capture: capture)
                } else {
                    sheet = SheetItem(presentation: presentation)
                }
            }
    }

    private func kind(of presentation: RouteHarness.Presentation) -> SessionKind {
        switch presentation {
        case .capture(let c): return c.ref.kind
        case .photocheck(_, let kind): return kind
        case .newSet(let n): return n.ref.kind
        case .newSession, .gallery: return .study
        }
    }

    /// Sheets and covers get every environment object again, then the session scope.
    private func scoped<V: View>(_ view: V, kind: SessionKind) -> some View {
        view
            .sessionScope(kind)
            .environmentObject(launch.stores)
            .environmentObject(launch.navigator)
            .environmentObject(launch.settings)
            .modifier(RouteHarnessAppearance(route: launch.route))
            .tint(Theme.Colors.drape)
    }

    @ViewBuilder
    private func sheetContent(_ presentation: RouteHarness.Presentation) -> some View {
        switch presentation {
        case .photocheck(let pending, _):
            CaptureReviewSheet(pending: pending, photoNumber: 1, nextAngle: .leftOblique,
                               onRetake: { sheet = nil }, onKeep: { _ in sheet = nil })
        case .newSession(let studyID, let showValidation):
            NewSessionSheet(initialStudyID: studyID, showValidation: showValidation,
                            onCreated: { created in pendingSession = created.id })
        case .newSet(let context):
            NewCaptureSetView(suggestedStage: context.suggestedStage,
                              previousPositioning: context.previousPositioning,
                              previousSetIndex: context.previousSetIndex,
                              previousStage: context.previousStage) { set in
                pendingCapture = RouteHarness.Presentation.CaptureTarget(ref: context.ref, set: set, index: context.nextIndex,
                                                                   angles: ViewAngle.allCases, practiceRetake: false)
                sheet = nil
            }
        case .gallery:
            NavigationStack { DesignGallery() }
        case .capture:
            EmptyView()
        }
    }

    private func sheetDismissed() {
        if let id = pendingSession {
            pendingSession = nil
            launch.navigator.push(.session(SessionRef(id: id, kind: .study)))
        }
        if let capture = pendingCapture {
            pendingCapture = nil
            cover = CoverItem(capture: capture)
        }
    }
}
#endif
