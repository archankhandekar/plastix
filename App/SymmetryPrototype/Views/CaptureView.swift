import SwiftUI
import SymmetryCore
import SymmetryModels
import UIKit

/// The full-screen viewfinder, always on the dark Plate: "Photo N of 3: frontal", the
/// three-view checklist, the guides, the quality gate and retake.
///
/// A study session shows the rear camera (`LiveViewfinder`). A practice session shows the
/// rendered virtual patient (`VirtualViewfinder`) and never constructs the camera. Both
/// deliver encoded image data that goes through the same `ImageBridge.process`, photo
/// check and save. Capture logic (queue, save after every photo, ghost lookup, processing
/// and thresholds) is unchanged from the first prototype.
struct CaptureView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    /// Read only in practice sessions, for the virtual patient and its asset keys.
    @EnvironmentObject private var stores: SessionStores
    @Environment(\.sessionKind) private var kind
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss

    let sessionID: UUID
    /// 1-based position of this set in the session, for "Set N, <stage>".
    let setIndex: Int
    @State private var captureSet: CaptureSet
    @State private var queue: [ViewAngle]

    @StateObject private var viewfinder = ViewfinderLink()
    @State private var pending: PendingCapture?
    @State private var isCapturing = false
    @State private var errorMessage: String?
    @State private var confirmStop = false
    /// Practice only: the next frontal comes back blurred and tilted, so Retake is offered first.
    @State private var practiceRetake: Bool

    struct PendingCapture: Identifiable {
        let id = UUID()
        let angle: ViewAngle
        let processed: ImageBridge.Processed
        let tilt: Double?
        /// The bundled render a practice photo came from. Always nil for a camera photo.
        var assetKey: DemoAssetKey? = nil
    }

    init(sessionID: UUID, captureSet: CaptureSet, setIndex: Int, anglesToCapture: [ViewAngle],
         initialPracticeRetake: Bool = false) {
        self.sessionID = sessionID
        self.setIndex = setIndex
        _captureSet = State(initialValue: captureSet)
        _queue = State(initialValue: anglesToCapture)
        _practiceRetake = State(initialValue: initialPracticeRetake)
    }

    private var current: ViewAngle? { queue.first }

    private var isPractice: Bool { kind == .practice }

    /// The virtual patient, in a practice session only.
    private var practicePatient: DemoPatient? {
        isPractice ? stores.practice.patient : nil
    }

    /// "Photo 1 of 3" counts along the fixed order Frontal, Left oblique, Right oblique.
    private func photoNumber(for angle: ViewAngle) -> Int {
        ViewAngle.allCases.firstIndex(of: angle)! + 1
    }

    /// The other set whose photo of the current angle is used to match the pose: the
    /// nearest set created before this one, or, when none exists (retaking set 1 while a
    /// later set exists), the newest other set. `isEarlier` says which, so the hint can
    /// name the photo honestly.
    private var ghostSource: (capture: Capture, isEarlier: Bool)? {
        guard let angle = current, let session = store.session(id: sessionID) else { return nil }
        let others = session.orderedCaptureSets.filter { $0.id != captureSet.id && $0.captures[angle] != nil }
        if let earlier = others.last(where: { $0.createdAt < captureSet.createdAt }), let capture = earlier.captures[angle] {
            return (capture, true)
        }
        if let other = others.last, let capture = other.captures[angle] {
            return (capture, false)
        }
        return nil
    }

    /// True when another set in this session already holds a photo of the current angle,
    /// so there is a photo to match the pose against.
    private var hasPriorCapture: Bool { ghostSource != nil }

    /// The disabled state carries its reason in the visible title, not only in VoiceOver.
    private var matchPoseTitle: String {
        guard hasPriorCapture else { return "Match pose (needs an earlier set)" }
        return settings.ghostOverlayEnabled ? "Match pose: On" : "Match pose: Off"
    }

    private var matchPoseHint: String {
        guard let source = ghostSource else { return "Needs a photo of this view from an earlier set" }
        return source.isEarlier ? "Shows the earlier photo of this view faintly in the camera"
                                : "Shows this view from a later set faintly in the camera"
    }

    /// True when the last photo in this queue leads to marking the frontal: the frontal is
    /// being taken now, or it is already in the set without its 6 points.
    private var frontalNeedsPoints: Bool {
        if queue.contains(.frontal) { return true }
        guard let frontal = captureSet.frontal else { return false }
        return frontal.landmarks?.isComplete != true
    }

    /// The photo of the current angle from `ghostSource`, faded into the viewfinder.
    private var ghostImage: UIImage? {
        guard settings.ghostOverlayEnabled, let session = store.session(id: sessionID),
              let capture = ghostSource?.capture else { return nil }
        return store.image(for: capture, in: session)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Theme.Colors.plate.ignoresSafeArea()
            if dynamicTypeSize.isAccessibilitySize {
                // At the largest text sizes everything scrolls and the viewfinder keeps a usable height.
                ScrollView {
                    VStack(spacing: Theme.Spacing.s) {
                        topContent
                        viewfinderArea.frame(height: 420)
                        controls
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                VStack(spacing: Theme.Spacing.s) {
                    topContent
                    viewfinderArea.frame(maxWidth: .infinity, maxHeight: .infinity)
                    controls
                }
            }
        }
        .statusBarHidden()
        .onReceive(viewfinder.$errorMessage) { if let m = $0 { errorMessage = m } }
        .sheet(item: $pending) { p in
            CaptureReviewSheet(pending: p,
                               photoNumber: photoNumber(for: p.angle),
                               nextAngle: queue.dropFirst().first,
                               frontalNeedsPoints: frontalNeedsPoints,
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

    @ViewBuilder
    private var topContent: some View {
        if isPractice {
            PracticeBand(PracticeBand.photoText, style: .plate)
        }
        header
        checklist
        if isPractice {
            practiceLines
        }
    }

    // MARK: - Header

    /// "Photo 1 of 3: frontal" over "Set 1, preoperative marking", with Stop beside them.
    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let angle = current {
                    Text("Photo \(photoNumber(for: angle)) of 3: \(angle.displayName.lowercased())")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.Colors.plateInk)
                }
                Text(SessionWizard.title(index: setIndex, stage: captureSet.stage))
                    .font(.support)
                    .foregroundStyle(Theme.Colors.plateGraduation)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Button("Stop") { confirmStop = true }
                .buttonStyle(OutlinedCaptureButtonStyle())
                .accessibilityHint("Asks before closing the camera. Kept photos stay saved.")
        }
        .padding(.horizontal, Theme.Spacing.margin)
        .padding(.top, Theme.Spacing.s)
    }

    // MARK: - Checklist

    private var checklist: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(ViewAngle.allCases) { angle in
                        checklistCell(angle, stacked: false)
                    }
                }
            } else {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(ViewAngle.allCases) { angle in
                        checklistCell(angle, stacked: true)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.margin)
    }

    /// One view of the set: a checkmark when kept, the camera when it is next, a plain
    /// circle when it is still to come. Cells are at least 56pt tall.
    private func checklistCell(_ angle: ViewAngle, stacked: Bool) -> some View {
        let done = captureSet.captures[angle] != nil && !queue.contains(angle)
        let isCurrent = angle == current
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius)
        let symbol = Image(systemName: done ? "checkmark" : (isCurrent ? "camera.fill" : "circle"))
            .foregroundStyle(done ? Theme.Colors.drapeOnPlate : Theme.Colors.plateInk)
            .accessibilityHidden(true)
        let title = Text(angle.displayName)
            .multilineTextAlignment(stacked ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
        return Group {
            if stacked {
                VStack(spacing: Theme.Spacing.xs) { symbol; title }
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: Theme.Spacing.s) { symbol; title }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.subheadline.weight(isCurrent ? .semibold : .regular))
        .foregroundStyle(isCurrent ? Theme.Colors.plateInk : Theme.Colors.plateGraduation)
        .padding(.vertical, Theme.Spacing.s)
        .padding(.horizontal, Theme.Spacing.s)
        .frame(minHeight: Theme.tapTarget)
        .background(isCurrent ? Color.white.opacity(0.12) : .clear, in: shape)
        .overlay(shape.strokeBorder(isCurrent ? Theme.Colors.drapeOnPlate : Theme.Colors.plateGraduation.opacity(0.5),
                                    lineWidth: isCurrent ? 2 : 1))
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "taken" : (isCurrent ? "next" : "not taken"))
    }

    // MARK: - Practice lines

    private var practiceLines: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Showing the virtual patient instead of the camera.")
            if let patient = practicePatient, setIndex > patient.stageCount {
                Text("The virtual patient has photos for \(patient.stageCount) stages. This set uses the set \(patient.stageCount) photos.")
            }
        }
        .font(.support)
        .foregroundStyle(Theme.Colors.plateGraduation)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.margin)
    }

    // MARK: - Viewfinder

    private var viewfinderArea: some View {
        ZStack {
            viewfinderSource
            if !isPractice && !viewfinder.isRunning && errorMessage == nil {
                Text("Starting camera…")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.plateInk)
            }
            if let errorMessage {
                GuidanceCard(kind: .dark,
                             title: errorTitle,
                             body: errorMessage) {
                    if viewfinder.errorOpensSettings {
                        Button("Open Settings") {
                            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .background(Theme.Colors.plate.opacity(0.8), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                .padding(Theme.Spacing.m)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.photoRadius))
    }

    private var errorTitle: String {
        if viewfinder.errorOpensSettings { return "Camera is off" }
        return isPractice ? "Virtual camera problem" : "Camera problem"
    }

    /// Exactly one viewfinder: the virtual patient in practice, the camera in a study.
    @ViewBuilder
    private var viewfinderSource: some View {
        if isPractice {
            if let patient = practicePatient {
                VirtualViewfinder(patient: patient, setIndex: setIndex, angle: current,
                                  maxTiltDegrees: settings.maxTiltDegrees, ghost: ghostImage,
                                  practiceRetake: $practiceRetake, link: viewfinder)
            } else {
                Text("The virtual patient is not available in this build.")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.plateInk)
                    .multilineTextAlignment(.center)
                    .padding(Theme.Spacing.m)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            LiveViewfinder(link: viewfinder, angle: current,
                           maxTiltDegrees: settings.maxTiltDegrees, ghost: ghostImage)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Theme.Spacing.m) {
                    if isPractice { retakeChip.frame(maxWidth: .infinity) }
                    matchPoseButton.frame(maxWidth: .infinity)
                    shutter
                }
            } else {
                HStack(alignment: .center, spacing: Theme.Spacing.s) {
                    Group {
                        if isPractice { retakeChip }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    shutter
                    matchPoseButton
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.Spacing.margin)
        .padding(.bottom, Theme.Spacing.m)
    }

    private var retakeChip: some View {
        ToggleChip("Practise a retake", isOn: $practiceRetake, onPlate: true)
            .accessibilityHint("The next frontal photo comes back blurred and tilted, so you can practise a retake")
    }

    private var matchPoseButton: some View {
        Button(matchPoseTitle) { settings.ghostOverlayEnabled.toggle() }
            .buttonStyle(OutlinedCaptureButtonStyle())
            .multilineTextAlignment(.center)
            .disabled(!hasPriorCapture)
            .accessibilityHint(matchPoseHint)
    }

    /// The 80pt shutter.
    private var shutter: some View {
        Button(action: capture) {
            ZStack {
                Circle()
                    .stroke(Theme.Colors.plateInk, lineWidth: 4)
                    .frame(width: Theme.shutterSize - 4, height: Theme.shutterSize - 4)
                Circle()
                    .fill(isCapturing ? Theme.Colors.plateInk.opacity(0.4) : Theme.Colors.plateInk)
                    .frame(width: Theme.shutterSize - 16, height: Theme.shutterSize - 16)
            }
            .frame(width: Theme.shutterSize, height: Theme.shutterSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isCapturing || current == nil || !viewfinder.isRunning)
        .opacity(isCapturing || current == nil || !viewfinder.isRunning ? 0.5 : 1)
        .accessibilityLabel("Take \(current?.displayName.lowercased() ?? "") photo")
    }

    // MARK: - Capture

    private func capture() {
        guard let angle = current, !isCapturing, let shoot = viewfinder.capture else { return }
        isCapturing = true
        errorMessage = nil
        Haptics.shutter()
        let thresholds = settings.qualityThresholds
        let practice = isPractice
        Task {
            do {
                let shot = try await shoot(angle)
                let data = shot.data
                let tilt = shot.tiltDegrees
                let processed = await Task.detached(priority: .userInitiated) {
                    ImageBridge.process(data, tiltDegrees: tilt, thresholds: thresholds)
                }.value
                if let processed {
                    pending = PendingCapture(angle: angle, processed: processed, tilt: tilt,
                                             assetKey: practice ? shot.assetKey : nil)
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
        // A kept practice photo records which render it came from, in the practice sidecar only.
        if isPractice, let key = p.assetKey {
            stores.practice.recordAsset(key, forCaptureID: capture.id)
        }
        queue.removeFirst()
        pending = nil
        if queue.isEmpty { dismiss() }
    }
}

/// The photo check: the captured photo with its quality advice and the keep or retake
/// choice. The top button is always the recommended action (Retake first on a failed shot).
struct CaptureReviewSheet: View {
    @Environment(\.sessionKind) private var kind

    let pending: CaptureView.PendingCapture
    let photoNumber: Int
    /// The angle that comes next in the queue, or nil when this is the last photo.
    let nextAngle: ViewAngle?
    /// True when the frontal photo still needs its 6 points after this queue, so the
    /// last-photo footer says what really comes next.
    let frontalNeedsPoints: Bool
    let onRetake: () -> Void
    let onKeep: (Bool) -> Void

    init(pending: CaptureView.PendingCapture, photoNumber: Int, nextAngle: ViewAngle?,
         frontalNeedsPoints: Bool = true,
         onRetake: @escaping () -> Void, onKeep: @escaping (Bool) -> Void) {
        self.pending = pending
        self.photoNumber = photoNumber
        self.nextAngle = nextAngle
        self.frontalNeedsPoints = frontalNeedsPoints
        self.onRetake = onRetake
        self.onKeep = onKeep
    }

    private var passed: Bool { pending.processed.quality.passed }

    private var footer: String {
        if let nextAngle { return "After this: \(nextAngle.displayName)" }
        return frontalNeedsPoints
            ? "After this the camera closes and you mark 6 points on the frontal photo."
            : "After this the camera closes and you return to the set."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Photo \(photoNumber) of 3: \(pending.angle.displayName)")
                    .font(.sectionTitle)
                    .foregroundStyle(Theme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Check it, then keep it or retake it.")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                photo
                QualityAdviceList(report: pending.processed.quality, overridden: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if passed {
                    Button("Use this photo") { onKeep(false) }.buttonStyle(PrimaryButtonStyle())
                    Button("Retake", action: onRetake).buttonStyle(SecondaryButtonStyle())
                } else {
                    Button("Retake", action: onRetake).buttonStyle(PrimaryButtonStyle())
                    Button("Keep anyway") { onKeep(true) }.buttonStyle(SecondaryButtonStyle())
                    Label("If you keep it, this warning stays attached to every comparison that uses this photo.",
                          systemImage: "exclamationmark.triangle")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.caution)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(footer)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.margin)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.Colors.tray)
        .practiceBand(kind == .practice)
    }

    /// The photo as taken, fitted on Plate with the 4pt steel-tray corner.
    @ViewBuilder
    private var photo: some View {
        if let image = UIImage(data: pending.processed.jpeg) {
            ZStack {
                Theme.Colors.plate
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("\(pending.angle.displayName) photo just taken")
            }
            .frame(maxWidth: .infinity)
            .frame(height: 360)
            .clipShape(RoundedRectangle(cornerRadius: Theme.photoRadius))
        }
    }
}
