import SwiftUI
import SymmetryCore
import SymmetryModels
import UIKit

/// Full-screen viewfinder for Screen 5: "Photo N of 3" header, the three-view checklist,
/// guides, the quality gate and retake. Capture logic (queue, save after every photo,
/// ghost lookup, processing and thresholds) is unchanged from the first prototype.
struct CaptureView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let sessionID: UUID
    /// 1-based position of this set in the session, for "Set N · <stage>".
    let setIndex: Int
    @State private var captureSet: CaptureSet
    @State private var queue: [ViewAngle]

    @StateObject private var camera = CameraService()
    @StateObject private var motion = MotionLevelService()
    @State private var pending: PendingCapture?
    @State private var isCapturing = false
    @State private var errorMessage: String?
    @State private var confirmStop = false

    struct PendingCapture: Identifiable {
        let id = UUID()
        let angle: ViewAngle
        let processed: ImageBridge.Processed
        let tilt: Double?
    }

    init(sessionID: UUID, captureSet: CaptureSet, setIndex: Int, anglesToCapture: [ViewAngle]) {
        self.sessionID = sessionID
        self.setIndex = setIndex
        _captureSet = State(initialValue: captureSet)
        _queue = State(initialValue: anglesToCapture)
    }

    private var current: ViewAngle? { queue.first }

    /// "Photo 1 of 3" counts along the fixed order Frontal, Left oblique, Right oblique.
    private func photoNumber(for angle: ViewAngle) -> Int {
        ViewAngle.allCases.firstIndex(of: angle)! + 1
    }

    /// True when another set in this session already holds a photo of the current angle,
    /// so there is an earlier photo to match the pose against.
    private var hasPriorCapture: Bool {
        guard let angle = current, let session = store.session(id: sessionID) else { return false }
        return session.orderedCaptureSets.contains { $0.id != captureSet.id && $0.captures[angle] != nil }
    }

    private var matchPoseTitle: String {
        guard hasPriorCapture else { return "Match pose (needs an earlier set)" }
        return settings.ghostOverlayEnabled ? "Match pose: On" : "Match pose: Off"
    }

    private var isNotAuthorized: Bool {
        errorMessage == CameraService.CameraError.notAuthorized.errorDescription
    }

    /// The most recent capture of the current angle from another set in this session.
    private var ghostImage: UIImage? {
        guard settings.ghostOverlayEnabled, let angle = current, let session = store.session(id: sessionID) else { return nil }
        let prior = session.orderedCaptureSets.reversed().first { $0.id != captureSet.id && $0.captures[angle] != nil }
        guard let capture = prior?.captures[angle] else { return nil }
        return store.image(for: capture, in: session)
    }

    var body: some View {
        ZStack {
            Theme.Colors.capture.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.s) {
                header
                checklist
                ZStack {
                    CameraPreviewView(session: camera.session)
                    if let angle = current {
                        GuideOverlayView(angle: angle, rollDegrees: motion.rollDegrees,
                                         maxTiltDegrees: settings.maxTiltDegrees, ghost: ghostImage)
                    }
                    if !camera.isRunning && camera.errorMessage == nil {
                        Text("Starting camera…")
                            .font(.body)
                            .foregroundStyle(.white)
                    }
                    if let errorMessage {
                        GuidanceCard(kind: .dark,
                                     title: isNotAuthorized ? "Camera is off" : "Camera problem",
                                     body: errorMessage) {
                            if isNotAuthorized {
                                Button("Open Settings") {
                                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                                }
                                .buttonStyle(PrimaryButtonStyle())
                            }
                        }
                        .padding(Theme.Spacing.m)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                controls
            }
        }
        .statusBarHidden()
        .onAppear { camera.start(); motion.start() }
        .onDisappear { camera.stop(); motion.stop() }
        .onReceive(camera.$errorMessage) { if let m = $0 { errorMessage = m } }
        .sheet(item: $pending) { p in
            CaptureReviewSheet(pending: p,
                               photoNumber: photoNumber(for: p.angle),
                               nextAngle: queue.dropFirst().first,
                               onRetake: { pending = nil },
                               onKeep: { overridden in keep(p, overridden: overridden) })
                .interactiveDismissDisabled()
        }
        .confirmationDialog("Stop taking photos? The photos you have kept are saved. You can take the rest later from the session screen.",
                            isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop", role: .destructive) { dismiss() }
            Button("Keep going", role: .cancel) {}
        }
    }

    /// "Photo 1 of 3 · Frontal" over "Set 1 · Preoperative marking".
    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let angle = current {
                Text("Photo \(photoNumber(for: angle)) of 3 · \(angle.displayName)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
            Text("Set \(setIndex) · \(captureSet.stage.label)")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.s)
    }

    private var checklist: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(ViewAngle.allCases) { angle in
                let done = captureSet.captures[angle] != nil && !queue.contains(angle)
                let isCurrent = angle == current
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: done ? "checkmark.circle.fill" : (isCurrent ? "camera.fill" : "circle"))
                    Text(angle.displayName)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(done ? Theme.Colors.guide : (isCurrent ? .white : .white.opacity(0.75)))
                .padding(.vertical, Theme.Spacing.s)
                .padding(.horizontal, Theme.Spacing.xs)
                .frame(maxWidth: .infinity)
                .background(isCurrent ? Color.white.opacity(0.12) : .clear, in: Capsule())
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
    }

    private var controls: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            Button("Stop") { confirmStop = true }
                .buttonStyle(OutlinedCaptureButtonStyle())
                .frame(width: 96)
            Spacer(minLength: Theme.Spacing.s)
            Button(action: capture) {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                    Circle().fill(isCapturing ? Color.white.opacity(0.4) : .white).frame(width: 64, height: 64)
                }
            }
            .disabled(isCapturing || current == nil || !camera.isRunning)
            .accessibilityLabel("Capture \(current?.displayName ?? "")")
            Spacer(minLength: Theme.Spacing.s)
            Button(matchPoseTitle) { settings.ghostOverlayEnabled.toggle() }
                .buttonStyle(OutlinedCaptureButtonStyle())
                .multilineTextAlignment(.center)
                .frame(maxWidth: 150)
                .disabled(!hasPriorCapture)
                .accessibilityHint("Shows the earlier photo of this view faintly in the camera")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.m)
    }

    private func capture() {
        guard let angle = current, !isCapturing else { return }
        isCapturing = true
        errorMessage = nil
        let tilt = motion.rollDegrees
        let thresholds = settings.qualityThresholds
        Task {
            do {
                let data = try await camera.capturePhoto()
                let processed = await Task.detached(priority: .userInitiated) {
                    ImageBridge.process(data, tiltDegrees: tilt, thresholds: thresholds)
                }.value
                if let processed {
                    pending = PendingCapture(angle: angle, processed: processed, tilt: tilt)
                } else {
                    errorMessage = "The photo could not be processed. Try again."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isCapturing = false
        }
    }

    private func keep(_ p: PendingCapture, overridden: Bool) {
        guard var session = store.session(id: sessionID) else { return }
        let filename = "\(p.angle.rawValue)-\(UUID().uuidString.prefix(8)).jpg"
        let capture = Capture(angle: p.angle, imageFilename: filename, pixelWidth: p.processed.width, pixelHeight: p.processed.height,
                              quality: p.processed.quality, tiltDegrees: p.tilt, qualityOverridden: overridden)
        do {
            try store.writeImage(p.processed.jpeg, for: capture, in: session)
        } catch {
            errorMessage = "Could not store the image: \(error.localizedDescription)"
            pending = nil
            return
        }
        let replaced = captureSet.captures[p.angle]
        captureSet.captures[p.angle] = capture
        session.update(captureSet)
        // Saved after every view so an interruption keeps what was captured.
        guard store.save(session) else {
            captureSet.captures[p.angle] = replaced
            store.deleteImage(for: capture, in: session)
            errorMessage = store.lastError ?? "Could not save the session."
            pending = nil
            return
        }
        if let replaced { store.deleteImage(for: replaced, in: session) }
        queue.removeFirst()
        pending = nil
        if queue.isEmpty { dismiss() }
    }
}

/// Screen 6: the captured photo with its quality advice and the keep or retake choice.
/// The top button is always the recommended action (Retake first on a failed shot).
struct CaptureReviewSheet: View {
    let pending: CaptureView.PendingCapture
    let photoNumber: Int
    /// The angle that comes next in the queue, or nil when this is the last photo.
    let nextAngle: ViewAngle?
    let onRetake: () -> Void
    let onKeep: (Bool) -> Void

    init(pending: CaptureView.PendingCapture, photoNumber: Int, nextAngle: ViewAngle?,
         onRetake: @escaping () -> Void, onKeep: @escaping (Bool) -> Void) {
        self.pending = pending
        self.photoNumber = photoNumber
        self.nextAngle = nextAngle
        self.onRetake = onRetake
        self.onKeep = onKeep
    }

    private var passed: Bool { pending.processed.quality.passed }

    private var footer: String {
        nextAngle.map { "After this: \($0.displayName)" }
            ?? "After this the camera closes and you mark 6 points on the frontal photo."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Photo \(photoNumber) of 3: \(pending.angle.displayName)")
                    .font(.stepTitle)
                    .foregroundStyle(Theme.Colors.ink)
                Text("Check it, then keep it or retake it.")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                if let image = UIImage(data: pending.processed.jpeg) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                }
                QualityAdviceList(report: pending.processed.quality, overridden: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if passed {
                    Button("Use this photo") { onKeep(false) }.buttonStyle(PrimaryButtonStyle())
                    Button("Retake", action: onRetake).buttonStyle(SecondaryButtonStyle())
                } else {
                    Button("Retake", action: onRetake).buttonStyle(PrimaryButtonStyle())
                    Button("Keep anyway") { onKeep(true) }.buttonStyle(SecondaryButtonStyle())
                    Text("If you keep it, this warning stays attached to every comparison that uses this photo.")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.caution)
                }
                Text(footer)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.Colors.paper)
    }
}
