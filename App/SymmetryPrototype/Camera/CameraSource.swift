import Combine
import SwiftUI
import SymmetryCore
import UIKit

/// One frame taken by whichever viewfinder is on screen.
struct ViewfinderShot {
    /// The encoded image, as a camera would deliver it. `ImageBridge.process` reads it.
    let data: Data
    /// The roll at the moment of capture, or nil when the phone pointed down.
    let tiltDegrees: Double?
    /// Which bundled render a practice shot came from; nil for a camera photo.
    let assetKey: DemoAssetKey?
}

/// The link between `CaptureView` and the viewfinder it shows. The viewfinder fills it in;
/// the capture screen reads its state and calls `capture`. `CaptureView` never knows which
/// kind of viewfinder is behind it, so a practice session never has to construct the camera.
@MainActor
final class ViewfinderLink: ObservableObject {
    /// True once the viewfinder can take a photo.
    @Published var isRunning = false
    /// A problem the viewfinder reports, in words.
    @Published var errorMessage: String?
    /// True when the problem is that camera access is off, so the screen offers Settings.
    @Published var errorOpensSettings = false

    /// Takes one photo of the given view. Nil until a viewfinder is on screen.
    var capture: (@MainActor (ViewAngle) async throws -> ViewfinderShot)?
    /// Reads the current roll. Not published, so a drifting viewfinder does not redraw the
    /// whole capture screen on every frame.
    var currentRoll: (@MainActor () -> Double?)?

    /// The roll right now, in degrees, or nil when it is not known.
    var rollDegrees: Double? { currentRoll?() }
}

// MARK: - Study: the real camera

/// The rear camera with the alignment guides. It owns the AVFoundation session and the
/// motion sensors, and is the only view that constructs them, so practice sessions never
/// start AVFoundation.
struct LiveViewfinder: View {
    let link: ViewfinderLink
    let angle: ViewAngle?
    let maxTiltDegrees: Double
    let ghost: UIImage?

    @StateObject private var camera = CameraService()
    @StateObject private var motion = MotionLevelService()

    var body: some View {
        ZStack {
            CameraPreviewView(session: camera.session)
            if let angle {
                GuideOverlayView(angle: angle, rollDegrees: motion.rollDegrees,
                                 maxTiltDegrees: maxTiltDegrees, ghost: ghost)
            }
        }
        .onAppear {
            let camera = camera, motion = motion
            link.currentRoll = { motion.rollDegrees }
            link.capture = { _ in
                // The roll is read before the shutter, as the phone is held at the press.
                let tilt = motion.rollDegrees
                let data = try await camera.capturePhoto()
                return ViewfinderShot(data: data, tiltDegrees: tilt, assetKey: nil)
            }
            camera.start()
            motion.start()
        }
        .onDisappear {
            camera.stop()
            motion.stop()
            link.capture = nil
            link.currentRoll = nil
            link.isRunning = false
        }
        .onReceive(camera.$isRunning) { link.isRunning = $0 }
        .onReceive(camera.$errorMessage) { message in
            link.errorOpensSettings = message != nil && message == CameraService.CameraError.notAuthorized.errorDescription
            link.errorMessage = message
        }
    }
}

// MARK: - Practice: the virtual patient

/// The practice viewfinder: the virtual patient's render for this set and view, aspect-fill
/// on Plate, with a slow handheld drift. The drift roll drives the level line in place of the
/// motion sensors, which the simulator does not have. With `staticMotion` it holds still.
struct VirtualViewfinder: View {
    let link: ViewfinderLink
    let angle: ViewAngle?
    let maxTiltDegrees: Double
    let ghost: UIImage?
    @Binding var practiceRetake: Bool

    @StateObject private var source: VirtualCameraSource
    @Environment(\.staticMotion) private var staticMotion
    @State private var start = Date()

    init(patient: DemoPatient, setIndex: Int, angle: ViewAngle?, maxTiltDegrees: Double, ghost: UIImage?,
         practiceRetake: Binding<Bool>, link: ViewfinderLink) {
        self.link = link
        self.angle = angle
        self.maxTiltDegrees = maxTiltDegrees
        self.ghost = ghost
        self._practiceRetake = practiceRetake
        _source = StateObject(wrappedValue: VirtualCameraSource(patient: patient, setIndex: setIndex, angle: angle ?? .frontal))
    }

    var body: some View {
        // Qualified: the app has its own TimelineView screen.
        SwiftUI.TimelineView(.animation(minimumInterval: nil, paused: staticMotion)) { context in
            let drift = VirtualCameraSource.drift(at: context.date.timeIntervalSince(start), staticMotion: staticMotion)
            GeometryReader { geo in
                ZStack {
                    Theme.Colors.plate
                    if let image = source.previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            // A little larger than the frame, so the drift never shows an edge.
                            .scaleEffect(1.05)
                            .rotationEffect(.degrees(-drift.rollDegrees))
                            .offset(drift.offset)
                            .accessibilityLabel(imageLabel)
                    }
                    if let ghost {
                        // The earlier photo stays still while the view drifts, as on a real camera.
                        Image(uiImage: ghost)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(1.05)
                            .opacity(0.35)
                            .accessibilityHidden(true)
                    }
                    if let angle {
                        GuideOverlayView(angle: angle, rollDegrees: drift.rollDegrees,
                                         maxTiltDegrees: maxTiltDegrees, ghost: nil)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            }
        }
        .onAppear(perform: connect)
        .onChange(of: angle) { _, newValue in
            if let newValue { source.angle = newValue }
        }
        .onDisappear {
            link.capture = nil
            link.currentRoll = nil
            link.isRunning = false
        }
    }

    private var imageLabel: String {
        "Virtual patient, \((angle ?? source.angle).displayName.lowercased()) view"
    }

    private func connect() {
        let source = source, start = start, staticMotion = staticMotion
        let retake = $practiceRetake
        if let angle { source.angle = angle }
        link.currentRoll = {
            VirtualCameraSource.drift(at: Date().timeIntervalSince(start), staticMotion: staticMotion).rollDegrees
        }
        link.capture = { angle in
            source.angle = angle
            source.practiceRetake = retake.wrappedValue
            let shot = try source.capture(at: Date().timeIntervalSince(start), staticMotion: staticMotion)
            // The switch turns itself off after the blurred frontal.
            retake.wrappedValue = source.practiceRetake
            return ViewfinderShot(data: shot.data, tiltDegrees: shot.tiltDegrees, assetKey: shot.key)
        }
        if source.previewImage != nil {
            link.errorMessage = nil
            link.errorOpensSettings = false
            link.isRunning = true
        } else {
            link.isRunning = false
            link.errorOpensSettings = false
            link.errorMessage = VirtualCameraSource.SourceError.missingPhoto(source.angle.rawValue).errorDescription
        }
    }
}
