import SwiftUI
import SymmetryCore
import SymmetryModels

/// Screen 8: one photo set. A card per view with its check result, points line and 56pt
/// actions; measurements folded away until the frontal photo has all six points.
struct ReviewView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
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

    var body: some View {
        if let session, let set {
            let status = CaptureSetStatus(set: set,
                                          index: SessionProgress.index(of: set, in: session),
                                          sigma: settings.landmarkSigmaRatio)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    headerCard(set: set, status: status)
                    ForEach(ViewAngle.allCases) { angle in
                        viewCard(angle: angle, set: set, session: session, index: status.index)
                        if angle == .frontal {
                            measurementsCard(set: set)
                        }
                    }
                    fixLabelsCard(set: set, session: session)
                    deleteCard
                    ResearchNoticeBanner()
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Colors.paper)
            .navigationTitle("Set \(status.index)")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $captureTarget) { target in
                CaptureView(sessionID: sessionID, captureSet: target.set, setIndex: target.index, anglesToCapture: target.angles)
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
        }
    }

    // MARK: - Cards

    private func headerCard(set: CaptureSet, status: CaptureSetStatus) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(set.stage.label)
                .font(.stepTitle)
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(status.positioningLine(set.positioning))
                .font(.body)
                .foregroundStyle(Theme.Colors.slate)
                .fixedSize(horizontal: false, vertical: true)
            if let next = status.nextAction {
                switch next {
                case .captureMissing(_, _, let angles, let title, _):
                    Button(title) { openCamera(for: angles, set: set, index: status.index) }
                        .buttonStyle(PrimaryButtonStyle())
                case .markPoints(_, _, let capture, let title, _):
                    NavigationLink {
                        LandmarkEditorView(sessionID: sessionID, setID: setID, captureID: capture.id)
                    } label: {
                        Text(title)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                default:
                    EmptyView()
                }
            }
        }
        .cardStyle()
    }

    private func viewCard(angle: ViewAngle, set: CaptureSet, session: StudySession, index: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(heading(for: angle))
                .font(.stepTitle)
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let capture = set.captures[angle] {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    if let image = store.image(for: capture, in: session) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: 128, height: 170)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        let hasWarning = capture.quality.map { !$0.passed } ?? false
                        Text(QualityAdvice.headline(report: capture.quality, overridden: capture.qualityOverridden))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(hasWarning ? Theme.Colors.caution : Theme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if capture.qualityOverridden {
                            Text("Kept with a warning")
                                .font(.body)
                                .foregroundStyle(Theme.Colors.slate)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(pointsLine(for: capture))
                            .font(.body)
                            .foregroundStyle(Theme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                NavigationLink {
                    LandmarkEditorView(sessionID: sessionID, setID: setID, captureID: capture.id)
                } label: {
                    Text(capture.landmarks == nil ? "Mark points" : "Edit points")
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Retake this photo") { requestRetake(of: capture, set: set, index: index) }
                    .buttonStyle(SecondaryButtonStyle())
            } else {
                Text("Not taken yet")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                Button("Take this photo") { openCamera(for: [angle], set: set, index: index) }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .cardStyle()
    }

    /// Shown under the frontal card only once every point is placed and metrics exist.
    @ViewBuilder
    private func measurementsCard(set: CaptureSet) -> some View {
        if let frontal = set.frontal, let landmarks = frontal.landmarks, landmarks.isComplete,
           let metrics = frontal.frontalMetrics(sigma: settings.landmarkSigmaRatio) {
            let hasContours = !landmarks.leftContour.isEmpty || !landmarks.rightContour.isEmpty
            DisclosureGroup(isExpanded: $showMeasurements) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
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
            .cardStyle()
        }
    }

    private func fixLabelsCard(set: CaptureSet, session: StudySession) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Fix labels")
                .font(.stepTitle)
                .foregroundStyle(Theme.Colors.ink)
            Text("The left oblique shows the patient's left side. If the two oblique photos are the wrong way round, swap them.")
                .font(.body)
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button("Swap the two oblique labels") { swapObliques(set, in: session) }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(set.captures[.leftOblique] == nil && set.captures[.rightOblique] == nil)
        }
        .cardStyle()
    }

    private var deleteCard: some View {
        Button("Delete this photo set") { confirmDelete = true }
            .buttonStyle(PrimaryButtonStyle(isDestructive: true))
            .cardStyle()
    }

    // MARK: - Copy

    private func heading(for angle: ViewAngle) -> String {
        angle == .frontal ? "Frontal (required for measurements)" : angle.displayName
    }

    /// "Points: 6 of 6 marked" / "Points: not yet marked" / "Points optional on this view".
    private func pointsLine(for capture: Capture) -> String {
        let marked = SessionProgress.pointsMarked(on: capture)
        if marked > 0 { return "Points: \(marked) of \(LandmarkType.allCases.count) marked" }
        return capture.angle == .frontal ? "Points: not yet marked" : "Points optional on this view"
    }

    /// Dialog title shown before a retake that would remove marked points or outlines.
    private func retakeWarning(for capture: Capture) -> String {
        let marked = SessionProgress.pointsMarked(on: capture)
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

    private func openCamera(for angles: [ViewAngle], set: CaptureSet, index: Int) {
        captureTarget = SessionView.CaptureTarget(set: set, index: index, angles: angles)
    }

    /// Asks first when the photo has any points or outlines, since a new photo replaces them.
    private func requestRetake(of capture: Capture, set: CaptureSet, index: Int) {
        if SessionProgress.pointsMarked(on: capture) > 0 || hasContours(capture) {
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

    private func delete(_ set: CaptureSet, in session: StudySession) {
        var s = session
        s.captureSets.removeAll { $0.id == set.id }
        guard store.save(s) else { return }
        for capture in set.orderedCaptures { store.deleteImage(for: capture, in: session) }
        dismiss()
    }
}
