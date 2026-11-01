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
    /// Practice only: the next frontal comes back blurred, so Retake is offered first.
    @State private var practiceRetake: Bool
    /// Practice only: Match pose, off by default. The virtual camera cannot move, so the
    /// earlier pose can only be compared, never lined up; it never touches the study setting.
    @State private var practiceMatchPose = false

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
    private var ghostSource: (capture: Capture, isEarlier: Bool, setNumber: Int)? {
        guard let angle = current, let session = store.session(id: sessionID) else { return nil }
        let ordered = session.orderedCaptureSets
        func number(_ set: CaptureSet) -> Int { (ordered.firstIndex { $0.id == set.id } ?? 0) + 1 }
        let others = ordered.filter { $0.id != captureSet.id && $0.captures[angle] != nil }
        if let earlier = others.last(where: { $0.createdAt < captureSet.createdAt }), let capture = earlier.captures[angle] {
            return (capture, true, number(earlier))
        }
        if let other = others.last, let capture = other.captures[angle] {
            return (capture, false, number(other))
        }
        return nil
    }

    /// True when another set in this session already holds a photo of the current angle,
    /// so there is a photo to match the pose against.
    private var hasPriorCapture: Bool { ghostSource != nil }

    /// Match pose is on: the session's own switch in practice, the Settings switch in a study.
    private var matchPoseOn: Bool {
        isPractice ? practiceMatchPose : settings.ghostOverlayEnabled
    }

    private var matchPoseBinding: Binding<Bool> {
        Binding(get: { matchPoseOn },
                set: { on in if isPractice { practiceMatchPose = on } else { settings.ghostOverlayEnabled = on } })
    }

    /// The disabled state carries its reason in the visible title, not only in VoiceOver.
    private var matchPoseTitle: String {
        guard hasPriorCapture else { return "Match pose (needs an earlier set)" }
        return matchPoseOn ? "Match pose: On" : "Match pose: Off"
    }

    private var matchPoseHint: String {
        guard let source = ghostSource else { return "Needs a photo of this view from an earlier set" }
        if isPractice { return "Shows the pose of an earlier set as thin lines in the camera" }
        return source.isEarlier ? "Shows the earlier photo of this view faintly in the camera"
                                : "Shows this view from a later set faintly in the camera"
    }

    /// Practice only, while Match pose is on: which set the lines come from, and why they
    /// may not line up.
    private var practiceGhostNote: String? {
        guard isPractice, practiceMatchPose, let source = ghostSource, practiceGhost != nil else { return nil }
        return "The thin lines show set \(source.setNumber). The virtual camera cannot move."
    }

    /// Practice only: the earlier pose as the ground truth of the bundled render it came from,
    /// so it registers with the live render. Never the processed photo.
    private var practiceGhost: VirtualGhost? {
        guard isPractice, practiceMatchPose, let angle = current, let patient = practicePatient,
              let source = ghostSource else { return nil }
        let stage = stores.practice.assetKey(forCaptureID: source.capture.id)?.stageIndex
            ?? min(max(source.setNumber, 1), max(patient.stageCount, 1))
        return patient.truth(stage: stage, angle: angle).map(VirtualGhost.init)
    }

    /// True when the last photo in this queue leads to marking the frontal: the frontal is
    /// being taken now, or it is already in the set without its 6 points.
    private var frontalNeedsPoints: Bool {
        if queue.contains(.frontal) { return true }
        guard let frontal = captureSet.frontal else { return false }
        return frontal.landmarks?.isComplete != true
    }

    /// Study only: the photo of the current angle from `ghostSource`, faded into the viewfinder.
    private var ghostImage: UIImage? {
        guard !isPractice, settings.ghostOverlayEnabled, let session = store.session(id: sessionID),
              let capture = ghostSource?.capture else { return nil }
        return store.image(for: capture, in: session)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Theme.Colors.plate.ignoresSafeArea()
            if dynamicTypeSize.isAccessibilitySize {
                // At the largest text sizes the viewfinder comes straight after the title and
                // keeps half the screen; the rest scrolls under a pinned shutter.
                ScrollView {
                    VStack(spacing: Theme.Spacing.s) {
                        if isPractice { PracticeBand(PracticeBand.photoText, style: .plate) }
                        header
                        viewfinderArea
                            .containerRelativeFrame(.vertical) { height, _ in height * 0.5 }
                            .padding(.horizontal, Theme.Spacing.s)
                        chromeLines
                        checklist
                        VStack(spacing: Theme.Spacing.m) {
                            if isPractice { retakeChip.frame(maxWidth: .infinity) }
                            matchPoseButton.frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, Theme.Spacing.margin)
                        .padding(.bottom, Theme.Spacing.m)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    shutter
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.s)
                        .background(Theme.Colors.plate)
                }
            } else {
                VStack(spacing: Theme.Spacing.s) {
                    if isPractice { PracticeBand(PracticeBand.photoText, style: .plate) }
                    header
                    checklist
                    chromeLines
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

    // MARK: - Header

    /// "Photo 1 of 3: frontal" over "Set 1, preoperative marking", with Stop beside them. At
    /// accessibility sizes the set line moves below the viewfinder, with the other lines.
    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                if let angle = current {
                    Text("Photo \(photoNumber(for: angle)) of 3: \(angle.displayName.lowercased())")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.Colors.plateInk)
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(SessionWizard.title(index: setIndex, stage: captureSet.stage))
                        .font(.support)
                        .foregroundStyle(Theme.Colors.plateGraduation)
                }
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
        .padding(.top, Theme.Spacing.xs)
    }

    // MARK: - Checklist

    /// A compact step rail: one line per view when the three fit across, otherwise the glyph
    /// over the name; one row per view at accessibility sizes.
    private var checklist: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(ViewAngle.allCases) { angle in
                        checklistCell(angle, stacked: false)
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(ViewAngle.allCases) { angle in
                            checklistCell(angle, stacked: false)
                        }
                    }
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(ViewAngle.allCases) { angle in
                            checklistCell(angle, stacked: true)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.margin)
    }

    /// One view of the set: a checkmark when kept, the camera when it is next, a plain
    /// circle when it is still to come. Status only, not a button, so 44pt is enough.
    private func checklistCell(_ angle: ViewAngle, stacked: Bool) -> some View {
        let done = captureSet.captures[angle] != nil && !queue.contains(angle)
        let isCurrent = angle == current
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius)
        let symbol = Image(systemName: done ? "checkmark" : (isCurrent ? "camera.fill" : "circle"))
            .foregroundStyle(done ? Theme.Colors.drapeOnPlate : Theme.Colors.plateInk)
            .accessibilityHidden(true)
        let title = Text(angle.displayName)
            .multilineTextAlignment(stacked ? .center : .leading)
        return Group {
            if stacked {
                VStack(spacing: 2) { symbol; title.fixedSize(horizontal: false, vertical: true) }
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: Theme.Spacing.xs) { symbol; title.fixedSize() }
                    .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center)
            }
        }
        .font(.subheadline.weight(isCurrent ? .semibold : .regular))
        .foregroundStyle(isCurrent ? Theme.Colors.plateInk : Theme.Colors.plateGraduation)
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.s)
        .frame(minHeight: 44)
        .background(isCurrent ? Color.white.opacity(0.12) : .clear, in: shape)
        .overlay(shape.strokeBorder(isCurrent ? Theme.Colors.drapeOnPlate : Theme.Colors.plateGraduation.opacity(0.5),
                                    lineWidth: isCurrent ? 2 : 1))
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "taken" : (isCurrent ? "next" : "not taken"))
    }

    // MARK: - Lines

    /// The angle's guidance, kept out of the viewfinder so it never covers the notch, then the
    /// practice notes that apply. The practice band already says this is the virtual patient.
    private var chromeLines: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if dynamicTypeSize.isAccessibilitySize {
                Text(SessionWizard.title(index: setIndex, stage: captureSet.stage))
                    .foregroundStyle(Theme.Colors.plateGraduation)
            }
            if let angle = current {
                Text(angle.guidanceText)
                    .foregroundStyle(Theme.Colors.plateInk)
            }
            if let patient = practicePatient, setIndex > patient.stageCount {
                Text("The virtual patient has photos for \(patient.stageCount) stages. This set uses the set \(patient.stageCount) photos.")
                    .foregroundStyle(Theme.Colors.plateGraduation)
            }
            if let note = practiceGhostNote {
                Text(note)
                    .foregroundStyle(Theme.Colors.plateGraduation)
            }
        }
        .font(.support)
        .multilineTextAlignment(.leading)
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
                                  maxTiltDegrees: settings.maxTiltDegrees, ghost: practiceGhost,
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

    /// The shutter with two small labelled toggles beside it, as on a camera.
    private var controls: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            Group {
                if isPractice {
                    CaptureOptionToggle(title: "Retake demo", systemImage: "arrow.counterclockwise",
                                        isOn: $practiceRetake)
                        .accessibilityHint(retakeHint)
                }
            }
            .frame(maxWidth: .infinity)
            shutter
            CaptureOptionToggle(title: "Match pose", systemImage: "figure.stand",
                                isOn: matchPoseBinding,
                                disabledTitle: hasPriorCapture ? nil : "Match pose: no earlier set")
                .accessibilityHint(matchPoseHint)
                .frame(maxWidth: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.Spacing.margin)
        .padding(.bottom, Theme.Spacing.s)
    }

    private var retakeHint: String {
        "The next frontal photo comes back blurred, so you can practise a retake"
    }

    private var retakeChip: some View {
        ToggleChip("Practise a retake", isOn: $practiceRetake, onPlate: true)
            .accessibilityHint(retakeHint)
    }

    private var matchPoseButton: some View {
        Button(matchPoseTitle) { matchPoseBinding.wrappedValue.toggle() }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                if !pinsPrimary {
                    Text("Check it, then keep it or retake it.")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                }
                photo
                QualityAdviceList(report: pending.processed.quality, overridden: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !pinsPrimary { primaryButton }
                if passed {
                    Button("Retake", action: onRetake).buttonStyle(SecondaryButtonStyle())
                } else {
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if pinsPrimary {
                primaryButton
                    .padding(.horizontal, Theme.Spacing.margin)
                    .padding(.vertical, Theme.Spacing.s)
                    .background(Theme.Colors.tray)
            }
        }
        .background(Theme.Colors.tray)
        .practiceBand(kind == .practice)
    }

    /// At accessibility sizes the recommended action is pinned under the scroll, so it is
    /// on the first screen with the photo and its first warning.
    private var pinsPrimary: Bool { dynamicTypeSize.isAccessibilitySize }

    /// The recommended action: keep a photo that passed, retake one that did not.
    @ViewBuilder
    private var primaryButton: some View {
        if passed {
            Button("Use this photo") { onKeep(false) }.buttonStyle(PrimaryButtonStyle())
        } else {
            Button("Retake", action: onRetake).buttonStyle(PrimaryButtonStyle())
        }
    }

    /// The photo as taken, fitted on Plate with the 4pt steel-tray corner. Shorter at
    /// accessibility sizes, so the advice and the recommended button stay on the first screen.
    /// When the tilt check fails, a level reference line crosses the photo so the lean shows.
    @ViewBuilder
    private var photo: some View {
        if let image = UIImage(data: pending.processed.jpeg) {
            ZStack {
                Theme.Colors.plate
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("\(pending.angle.displayName) photo just taken")
                if pending.processed.quality.failures.contains(.tilted) {
                    GeometryReader { geo in
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                            path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                        }
                        .stroke(Theme.Colors.plateInk.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 240 : 360)
            .clipShape(RoundedRectangle(cornerRadius: Theme.photoRadius))
        }
    }
}

/// A small on/off control beside the shutter: a 48pt glyph circle over a one-line label that
/// says its state in words ("Match pose: On"). The whole column is the tap target (56pt+).
struct CaptureOptionToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    /// When set, the control is disabled and shows this title instead, so the reason is visible.
    var disabledTitle: String? = nil

    private var label: String {
        disabledTitle ?? (title + (isOn ? ": On" : ": Off"))
    }

    var body: some View {
        let on = isOn && disabledTitle == nil
        Button {
            isOn.toggle()
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                ZStack {
                    Circle().fill(on ? Color.white.opacity(0.12) : Color.clear)
                    Circle().strokeBorder(on ? Theme.Colors.drapeOnPlate : Theme.Colors.plateGraduation,
                                          lineWidth: on ? 2 : 1.5)
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.Colors.plateInk)
                }
                .frame(width: 48, height: 48)
                Text(label)
                    .font(.subheadline.weight(on ? .semibold : .regular))
                    .foregroundStyle(Theme.Colors.plateInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: Theme.tapTarget, minHeight: Theme.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabledTitle != nil)
        .opacity(disabledTitle != nil ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(disabledTitle ?? title)
        .accessibilityValue(disabledTitle == nil ? (isOn ? "On" : "Off") : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}
