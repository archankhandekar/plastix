import SwiftUI
import SymmetryCore
import SymmetryModels
import UIKit

/// Full-screen viewfinder with the three-view checklist, guides, quality gate and retake.
struct CaptureView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let sessionID: UUID
    @State private var captureSet: CaptureSet
    @State private var queue: [ViewAngle]

    @StateObject private var camera = CameraService()
    @StateObject private var motion = MotionLevelService()
    @State private var pending: PendingCapture?
    @State private var isCapturing = false
    @State private var errorMessage: String?

    struct PendingCapture: Identifiable {
        let id = UUID()
        let angle: ViewAngle
        let processed: ImageBridge.Processed
        let tilt: Double?
    }

    init(sessionID: UUID, captureSet: CaptureSet, anglesToCapture: [ViewAngle]) {
        self.sessionID = sessionID
        _captureSet = State(initialValue: captureSet)
        _queue = State(initialValue: anglesToCapture)
    }

    private var current: ViewAngle? { queue.first }

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
                checklist
                ZStack {
                    CameraPreviewView(session: camera.session)
                    if let angle = current {
                        GuideOverlayView(angle: angle, rollDegrees: motion.rollDegrees, pitchDegrees: motion.pitchDegrees,
                                         maxTiltDegrees: settings.maxTiltDegrees, ghost: ghostImage)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.white)
                            .padding()
                            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
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
            CaptureReviewSheet(pending: p, onRetake: { pending = nil }, onKeep: { overridden in keep(p, overridden: overridden) })
                .interactiveDismissDisabled()
        }
    }

    private var checklist: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(ViewAngle.allCases) { angle in
                let done = captureSet.captures[angle] != nil && !queue.contains(angle)
                let isCurrent = angle == current
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: done ? "checkmark.circle.fill" : (isCurrent ? "camera.fill" : "circle"))
                    Text(angle.displayName).lineLimit(1).minimumScaleFactor(0.8)
                }
                .font(.footnote.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(done ? Theme.Colors.guide : (isCurrent ? .white : .white.opacity(0.6)))
                .padding(.vertical, Theme.Spacing.s)
                .frame(maxWidth: .infinity)
                .background(isCurrent ? Color.white.opacity(0.12) : .clear, in: Capsule())
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, Theme.Spacing.s)
    }

    private var controls: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .foregroundStyle(.white)
                .frame(width: 80, height: Theme.tapTarget)
            Spacer()
            Button(action: capture) {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                    Circle().fill(isCapturing ? Color.white.opacity(0.4) : .white).frame(width: 64, height: 64)
                }
            }
            .disabled(isCapturing || current == nil || !camera.isRunning)
            .accessibilityLabel("Capture \(current?.displayName ?? "")")
            Spacer()
            Toggle(isOn: $settings.ghostOverlayEnabled) { Image(systemName: "person.crop.rectangle") }
                .toggleStyle(.button)
                .tint(Theme.Colors.guide)
                .frame(width: 80, height: Theme.tapTarget)
                .accessibilityLabel("Ghost overlay of the prior capture")
        }
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
        captureSet.captures[p.angle] = capture
        session.update(captureSet)
        store.save(session) // saved after every view so an interruption keeps what was captured
        queue.removeFirst()
        pending = nil
        if queue.isEmpty { dismiss() }
    }
}

/// Shows the captured image with its quality result and the keep or retake choice.
struct CaptureReviewSheet: View {
    let pending: CaptureView.PendingCapture
    let onRetake: () -> Void
    let onKeep: (Bool) -> Void

    private var passed: Bool { pending.processed.quality.passed }

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Text(pending.angle.displayName).font(.headline)
            if let image = UIImage(data: pending.processed.jpeg) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
            QualityFailureList(report: pending.processed.quality, overridden: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            if passed {
                Button("Use photo") { onKeep(false) }.buttonStyle(PrimaryButtonStyle())
                Button("Retake", action: onRetake).buttonStyle(SecondaryButtonStyle())
            } else {
                Button("Retake", action: onRetake).buttonStyle(PrimaryButtonStyle())
                Button("Keep anyway") { onKeep(true) }.buttonStyle(SecondaryButtonStyle())
                Text("Kept images carry the warning into every comparison that uses them.")
                    .font(.footnote).foregroundStyle(Theme.Colors.slate)
            }
        }
        .padding(Theme.Spacing.l)
        .background(Theme.Colors.paper)
    }
}
