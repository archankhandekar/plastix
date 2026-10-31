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

    @State private var retakeAngle: ViewAngle?
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
                        viewCard(angle: angle, set: set, session: session)
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
            .fullScreenCover(item: $retakeAngle) { angle in
                CaptureView(sessionID: sessionID, captureSet: set, setIndex: status.index, anglesToCapture: [angle])
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
                    Button(title) { retakeAngle = angles.first }
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

    private func viewCard(angle: ViewAngle, set: CaptureSet, session: StudySession) -> some View {
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
                Button("Retake this photo") { retakeAngle = angle }
                    .buttonStyle(SecondaryButtonStyle())
            } else {
                Text("Not taken yet")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                Button("Take this photo") { retakeAngle = angle }
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

    // MARK: - Actions

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
