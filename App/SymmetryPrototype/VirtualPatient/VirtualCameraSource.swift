import Foundation
import SymmetryCore
import UIKit

/// The camera of a practice session: serves the bundled render of the virtual patient for
/// one stage and angle as the viewfinder image, with a slow handheld drift, and returns the
/// bundled JPEG bytes as the "photo". The captured data then runs through the unchanged
/// `ImageBridge.process`, photo check, review and save, exactly like a camera photo.
///
/// It never touches AVFoundation or Core Motion: the drift roll stands in for the phone's
/// roll, which the simulator cannot report.
@MainActor
final class VirtualCameraSource: ObservableObject {
    enum SourceError: LocalizedError {
        case missingPhoto(String)

        var errorDescription: String? {
            switch self {
            case .missingPhoto:
                return "The virtual patient photo is missing from this build."
            }
        }
    }

    /// Tilt reported with the "Practise a retake" frontal, so the photo check offers Retake first.
    static let retakeTiltDegrees: Double = 9

    let patient: DemoPatient
    /// The 1-based set index this capture is for. It can be past the last rendered stage.
    let setIndex: Int

    /// Which view is in front of the virtual camera.
    @Published var angle: ViewAngle
    /// When on, the next frontal shot returns the blurred render with a 9-degree tilt, and
    /// the switch then turns itself off. Obliques ignore it.
    @Published var practiceRetake: Bool = false

    private let imageData: (String) -> Data?
    private var imageCache: [String: UIImage] = [:]

    init(patient: DemoPatient, setIndex: Int, angle: ViewAngle,
         imageData: @escaping (String) -> Data? = { DemoPatient.imageData(named: $0) }) {
        self.patient = patient
        self.setIndex = setIndex
        self.angle = angle
        self.imageData = imageData
    }

    /// The rendered stage whose photos this set uses: the set index clamped to the stages
    /// the virtual patient has.
    var stageIndex: Int {
        min(max(setIndex, 1), max(patient.stageCount, 1))
    }

    /// True when the set is past the last rendered stage, so it reuses the last stage's photos.
    var usesLastStage: Bool {
        setIndex > patient.stageCount
    }

    /// The sharp render for `stageIndex` and `angle`, decoded once and cached.
    var previewImage: UIImage? {
        guard let name = patient.view(stage: stageIndex, angle: angle)?.image else { return nil }
        if let cached = imageCache[name] { return cached }
        guard let data = imageData(name), let image = UIImage(data: data) else { return nil }
        imageCache[name] = image
        return image
    }

    /// The handheld drift at time `t` seconds: an offset of up to 6pt across and 4pt down, and
    /// a roll of up to 1.5 degrees, as slow sinusoids with periods of 7 s and 11 s. Zero when
    /// motion is static.
    nonisolated static func drift(at t: TimeInterval, staticMotion: Bool) -> (offset: CGSize, rollDegrees: Double) {
        guard !staticMotion else { return (.zero, 0) }
        let x = 6 * sin(2 * Double.pi * t / 7)
        let y = 4 * sin(2 * Double.pi * t / 11)
        let roll = 1.5 * sin(2 * Double.pi * t / 11 + 1)
        return (CGSize(width: x, height: y), roll)
    }

    /// Takes the "photo" at time `t`. With `practiceRetake` on and the frontal in front of the
    /// camera, this returns the blurred render with a 9-degree tilt once and turns the switch
    /// off. Otherwise it returns the sharp render with the current drift roll as the tilt.
    func capture(at t: TimeInterval, staticMotion: Bool) throws -> (data: Data, tiltDegrees: Double, key: DemoAssetKey) {
        let stage = stageIndex
        guard let view = patient.view(stage: stage, angle: angle) else {
            throw SourceError.missingPhoto("stage \(stage) \(angle.rawValue)")
        }
        if practiceRetake, angle == .frontal, let blurredName = view.blurredImage {
            guard let data = imageData(blurredName) else { throw SourceError.missingPhoto(blurredName) }
            practiceRetake = false
            return (data, VirtualCameraSource.retakeTiltDegrees,
                    DemoAssetKey(stageIndex: stage, angle: angle, variant: .blurred))
        }
        guard let data = imageData(view.image) else { throw SourceError.missingPhoto(view.image) }
        let roll = VirtualCameraSource.drift(at: t, staticMotion: staticMotion).rollDegrees
        return (data, roll, DemoAssetKey(stageIndex: stage, angle: angle, variant: .sharp))
    }
}
