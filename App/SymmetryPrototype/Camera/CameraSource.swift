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

/// The earlier set's pose in a practice viewfinder: the ground truth of the matching bundled
/// render (same size and framing as the live render), drawn as thin lines, never as a faded
/// photo. A faded photo of a different stage reads as a double exposure (two areolae per
/// side), and the virtual camera cannot be moved to line it up.
struct VirtualGhost {
    /// The earlier render's ground truth, in that render's pixels.
    let truth: LandmarkSet
}

/// The practice viewfinder: the virtual patient's render for this set and view, fitted on
/// Plate exactly as the photo will be (the photo check shows the same framing), with a slow
/// handheld drift. The level line follows the render's own roll plus the drift, in place of
/// the motion sensors, which the simulator does not have. With `staticMotion` it holds still.
struct VirtualViewfinder: View {
    let link: ViewfinderLink
    let angle: ViewAngle?
    let maxTiltDegrees: Double
    let ghost: VirtualGhost?
    @Binding var practiceRetake: Bool

    @StateObject private var source: VirtualCameraSource
    @Environment(\.staticMotion) private var staticMotion
    @State private var start = Date()

    init(patient: DemoPatient, setIndex: Int, angle: ViewAngle?, maxTiltDegrees: Double, ghost: VirtualGhost?,
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
            let t = context.date.timeIntervalSince(start)
            let drift = VirtualCameraSource.drift(at: t, staticMotion: staticMotion)
            GeometryReader { geo in
                ZStack {
                    Theme.Colors.plate
                    if let image = source.previewImage {
                        // Fitted, not filled: what is framed here is what the photo holds.
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .rotationEffect(.degrees(-drift.rollDegrees))
                            .offset(drift.offset)
                            .accessibilityLabel(imageLabel)
                        if let ghost {
                            // The earlier pose stays still while the view drifts, as on a real camera.
                            GhostOutline(truth: ghost.truth, fit: Self.fitRect(image.size, in: geo.size))
                        }
                    }
                    if let angle {
                        GuideOverlayView(angle: angle, rollDegrees: source.tiltDegrees(at: t, staticMotion: staticMotion),
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

    /// Where an image of `imageSize` sits when fitted into `size`.
    static func fitRect(_ imageSize: CGSize, in size: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGRect(origin: .zero, size: size) }
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func connect() {
        let source = source, start = start, staticMotion = staticMotion
        let retake = $practiceRetake
        if let angle { source.angle = angle }
        link.currentRoll = {
            source.tiltDegrees(at: Date().timeIntervalSince(start), staticMotion: staticMotion)
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

/// The earlier pose as thin Plate-ink lines: both breast outlines, a small ring at each
/// nipple, and the notch to midline bottom line. Quiet steel, not violet (nobody placed these
/// here) and not blue (nothing is derived from them).
struct GhostOutline: View {
    let truth: LandmarkSet
    /// Where the render sits in the viewfinder.
    let fit: CGRect

    var body: some View {
        Canvas { ctx, _ in
            let w = truth.imageSize.x, h = truth.imageSize.y
            guard w > 0, h > 0 else { return }
            let sx = fit.width / CGFloat(w), sy = fit.height / CGFloat(h)
            func v(_ p: Point2D) -> CGPoint { CGPoint(x: fit.minX + CGFloat(p.x) * sx, y: fit.minY + CGFloat(p.y) * sy) }
            var path = Path()
            for contour in [truth.leftContour, truth.rightContour] where contour.count > 1 {
                path.move(to: v(contour[0]))
                for p in contour.dropFirst() { path.addLine(to: v(p)) }
            }
            if let n = truth[.sternalNotch], let b = truth[.midlineBottom] {
                path.move(to: v(n))
                path.addLine(to: v(b))
            }
            for type in [LandmarkType.leftNipple, .rightNipple] {
                guard let p = truth[type] else { continue }
                let c = v(p)
                path.addEllipse(in: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12))
            }
            ctx.stroke(path, with: .color(Theme.Colors.plate.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .color(Theme.Colors.plateInk.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
