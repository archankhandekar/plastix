import SwiftUI
import SymmetryCore
import SymmetryModels

/// Set N photos: one flat section per view with its photo on the Plate, its photo check and
/// its points, plus 56pt actions (mark, retake, swap the oblique labels, delete the set).
/// Measurements stay folded away until the frontal photo has all six points.
struct ReviewView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var navigator: AppNavigator
    @Environment(\.sessionKind) private var kind
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let sessionID: UUID
    let setID: UUID

    /// Camera target; carries every angle to capture so "Take the missing photos" queues them all.
    @State private var captureTarget: SessionView.CaptureTarget?
    /// Capture waiting on the "retake removes points" confirmation.
    @State private var retakeCandidate: Capture?
    @State private var confirmRetake = false
    @State private var confirmDelete = false
    @State private var showMeasurements = false

    private var session: StudySession? { store.session(id: sessionID) }
    private var set: CaptureSet? { session?.captureSet(id: setID) }
    private var ref: SessionRef { SessionRef(id: sessionID, kind: kind) }

    var body: some View {
        if let session, let set {
            let status = SetStatus(set: set,
                                   index: SessionWizard.index(of: set, in: session),
                                   sigma: settings.landmarkSigmaRatio)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    header(set: set, status: status)
                    ForEach(ViewAngle.allCases) { angle in
                        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                            viewSection(angle: angle, set: set, session: session, index: status.index)
                            if angle == .frontal {
                                measurements(set: set)
                            }
                        }
                    }
                    fixLabels(set: set, session: session)
                    Button("Delete this photo set") { confirmDelete = true }
                        .buttonStyle(PrimaryButtonStyle(isDestructive: true))
                    ResearchNoticeBanner()
                }
                .padding(.horizontal, Theme.Spacing.margin)
                .padding(.vertical, Theme.Spacing.l)
            }
            .background(Theme.Colors.tray)
            .practiceBand(kind == .practice)
            .navigationTitle("Set \(status.index)")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $captureTarget) { target in
                CaptureView(sessionID: sessionID, captureSet: target.set, setIndex: target.index, anglesToCapture: target.angles)
                    .sessionScope(kind)
            }
            .confirmationDialog(retakeCandidate.map(retakeWarning) ?? "",
                                isPresented: $confirmRetake, titleVisibility: .visible) {
                Button("Retake and remove points", role: .destructive) {
                    if let candidate = retakeCandidate { openCamera(for: [candidate.angle], set: set, index: status.index) }
                    retakeCandidate = nil
                }
                Button("Keep this photo", role: .cancel) { retakeCandidate = nil }
            }
            .confirmationDialog("Delete this photo set and its three photos?",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete photo set", role: .destructive) { delete(set, in: session) }
                Button("Cancel", role: .cancel) {}
            }
        } else {
            ContentUnavailableView("Photo set not found", systemImage: "questionmark.folder")
                .practiceBand(kind == .practice)
        }
    }

    // MARK: - Sections

    private func header(set: CaptureSet, status: SetStatus) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(status.title)
                .font(.screenTitle)
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(status.takenLine)
                .font(.support)
                .foregroundStyle(Theme.Colors.graduation)
                .fixedSize(horizontal: false, vertical: true)
            Text(status.positioningLine(set.positioning) + ".")
                .font(.support)
                .foregroundStyle(Theme.Colors.graduation)
                .fixedSize(horizontal: false, vertical: true)
            if let next = status.nextAction {
                switch next {
                case .captureMissing(_, _, let angles, let title, _):
                    Button(title) { openCamera(for: angles, set: set, index: status.index) }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top, Theme.Spacing.s)
                case .markPoints(_, _, let capture, let title, _):
                    Button(title) { markPoints(capture) }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top, Theme.Spacing.s)
                default:
                    EmptyView()
                }
            }
        }
    }

    private func viewSection(angle: ViewAngle, set: CaptureSet, session: StudySession, index: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(heading(for: angle))
                .font(.sectionTitle)
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let capture = set.captures[angle] {
                photoLayout {
                    photo(store.image(for: capture, in: session), angle: angle)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        checkLine(for: capture)
                        if capture.qualityOverridden {
                            Text("Kept with a warning.")
                                .font(.body)
                                .foregroundStyle(Theme.Colors.graduation)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(pointsLine(for: capture))
                            .font(.body)
                            .foregroundStyle(Theme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(capture.landmarks == nil ? "Mark points" : "Edit points") { markPoints(capture) }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Retake this photo") { requestRetake(of: capture, set: set, index: index) }
                    .buttonStyle(SecondaryButtonStyle())
            } else {
                Text("Not taken: \(angle.displayName.lowercased()).")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Take this photo") { openCamera(for: [angle], set: set, index: index) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    /// Photo beside its lines; stacked at accessibility text sizes so the lines have room.
    private var photoLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.m))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.m))
    }

    /// The photo as taken, whole, on the Plate with 4pt corners.
    private func photo(_ image: UIImage?, angle: ViewAngle) -> some View {
        ZStack {
            Theme.Colors.plate
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text("Photo file missing.")
                    .font(.support)
                    .foregroundStyle(Theme.Colors.plateInk)
                    .multilineTextAlignment(.center)
                    .padding(Theme.Spacing.s)
            }
        }
        .frame(width: 132, height: 176)
        .clipShape(RoundedRectangle(cornerRadius: Theme.photoRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(angle.displayName) photo")
    }

    @ViewBuilder
    private func checkLine(for capture: Capture) -> some View {
        let hasWarning = capture.quality.map { !$0.passed } ?? false
        let headline = QualityAdvice.headline(report: capture.quality, overridden: capture.qualityOverridden)
        if hasWarning {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Image(systemName: "exclamationmark.triangle")
                    .accessibilityHidden(true)
                Text(headline + ".")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.Colors.caution)
            .accessibilityElement(children: .combine)
        } else {
            Text(headline + ".")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Shown under the frontal photo only once every point is placed and metrics exist.
    @ViewBuilder
    private func measurements(set: CaptureSet) -> some View {
        if let frontal = set.frontal, let landmarks = frontal.landmarks, landmarks.isComplete,
           let metrics = frontal.frontalMetrics(sigma: settings.landmarkSigmaRatio) {
            let hasContours = !landmarks.leftContour.isEmpty || !landmarks.rightContour.isEmpty
            DisclosureGroup(isExpanded: $showMeasurements) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    ForEach(metrics.namedMetrics, id: \.name) { item in
                        MetricRow(name: item.name,
                                  measurement: item.measurement,
                                  explanation: MetricGlossary.meaning(for: item.name),
                                  reason: MetricGlossary.reason(flags: metrics.flags,
                                                                missing: landmarks.missing,
                                                                hasContours: hasContours,
                                                                metricName: item.name))
                    }
                    FlagList(flags: metrics.flags)
                }
                .padding(.top, Theme.Spacing.s)
            } label: {
                Text(showMeasurements ? "Hide measurements" : "Show measurements")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                    .frame(maxWidth: .infinity, minHeight: Theme.tapTarget, alignment: .leading)
            }
            .tint(Theme.Colors.ink)
        }
    }

    private func fixLabels(set: CaptureSet, session: StudySession) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Fix labels")
                .font(.sectionTitle)
                .foregroundStyle(Theme.Colors.ink)
                .accessibilityAddTraits(.isHeader)
            Text("The left oblique shows the patient's left side. If the two oblique photos are the wrong way round, swap them.")
                .font(.body)
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button("Swap the two oblique labels") { swapObliques(set, in: session) }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(set.captures[.leftOblique] == nil && set.captures[.rightOblique] == nil)
        }
    }

    // MARK: - Copy

    private func heading(for angle: ViewAngle) -> String {
        angle == .frontal ? "Frontal (required for measurements)" : angle.displayName
    }

    /// "6 of 6 points placed." / "Points not yet placed." / "Points are optional on this view."
    private func pointsLine(for capture: Capture) -> String {
        let marked = SessionWizard.pointsMarked(on: capture)
        if marked > 0 { return "\(marked) of \(LandmarkType.allCases.count) points placed." }
        return capture.angle == .frontal ? "Points not yet placed." : "Points are optional on this view."
    }

    /// Dialog title shown before a retake that would remove marked points or outlines.
    private func retakeWarning(for capture: Capture) -> String {
        let marked = SessionWizard.pointsMarked(on: capture)
        let points = marked == 1 ? "the point" : "the \(marked) points"
        let what: String
        if marked > 0 && hasContours(capture) {
            what = "\(points) and the outlines"
        } else if marked > 0 {
            what = points
        } else {
            what = "the outlines"
        }
        return "Retaking this photo removes \(what) marked on it. You will need to mark again."
    }

    private func hasContours(_ capture: Capture) -> Bool {
        guard let landmarks = capture.landmarks else { return false }
        return !landmarks.leftContour.isEmpty || !landmarks.rightContour.isEmpty
    }

    // MARK: - Actions

    private func markPoints(_ capture: Capture) {
        navigator.push(.markPoints(ref, setID: setID, captureID: capture.id))
    }

    private func openCamera(for angles: [ViewAngle], set: CaptureSet, index: Int) {
        captureTarget = SessionView.CaptureTarget(set: set, index: index, angles: angles)
    }

    /// Asks first when the photo has any points or outlines, since a new photo replaces them.
    private func requestRetake(of capture: Capture, set: CaptureSet, index: Int) {
        if SessionWizard.pointsMarked(on: capture) > 0 || hasContours(capture) {
            retakeCandidate = capture
            confirmRetake = true
        } else {
            openCamera(for: [capture.angle], set: set, index: index)
        }
    }

    private func swapObliques(_ set: CaptureSet, in session: StudySession) {
        var s = session
        var updated = set
        updated.swapObliqueLabels()
        s.update(updated)
        store.save(s)
    }

    /// Removes the set and its photos, then returns to session home (any screen of this set
    /// further up the path no longer has a set to show).
    private func delete(_ set: CaptureSet, in session: StudySession) {
        var s = session
        s.captureSets.removeAll { $0.id == set.id }
        guard store.save(s) else { return }
        for capture in set.orderedCaptures { store.deleteImage(for: capture, in: session) }
        navigator.popToSession(ref)
    }
}
