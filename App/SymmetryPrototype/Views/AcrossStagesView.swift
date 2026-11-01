import SwiftUI
import SymmetryCore
import SymmetryModels

/// How each left-right difference changed across stages: one centre-zero chart per metric,
/// one row per set, every plotted value listed verbatim with its ± underneath. There is no
/// single "change" headline here; change with its ± lives only in Compare two sets in detail.
struct AcrossStagesView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var navigator: AppNavigator
    @Environment(\.sessionKind) private var kind

    let sessionID: UUID

    /// Bumped after the UI flag is written so the wizard's next action is read again.
    @State private var flagsVersion = 0

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    private var session: StudySession? { store.session(id: sessionID) }
    private var ref: SessionRef { SessionRef(id: sessionID, kind: kind) }

    static let title = "How each left-right difference changed across stages"
    static let intro = "Each row is one set. The bar is its ±. A hollow mark cannot be told apart from zero."
    /// The chart axes carry bare numbers; their unit is stated once, here.
    static let unitLine = "Values are shares of L, the length from the sternal notch to the midline bottom."
    static let needsTwoSets = "Mark the points on at least two sets to see how each left-right difference changed across stages."

    var body: some View {
        if let session {
            content(session: session)
        } else {
            ContentUnavailableView("Session not found", systemImage: "questionmark.folder")
        }
    }

    @ViewBuilder
    private func content(session: StudySession) -> some View {
        let series = StageSeries(session: session, sigma: settings.landmarkSigmaRatio)
        // Read the flags again after `markOpenedStages`, so Next never points back here.
        let _ = flagsVersion
        let wizard = SessionWizard(session: session, settings: settings.reportSettings, kind: kind)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text(Self.title)
                        .font(.screenTitle)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(Self.intro)
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Self.unitLine)
                        .font(.support)
                        .foregroundStyle(Theme.Colors.graduation)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if series.measuredCount < 2 {
                    Text(Self.needsTwoSets)
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(BilateralMetric.allCases) { metric in
                        metricSection(metric, series: series)
                    }
                }

                Button("Compare two sets in detail") {
                    navigator.push(.compare(ref, earlierID: nil, laterID: nil))
                }
                .buttonStyle(SecondaryButtonStyle())

                ResearchNoticeBanner(showsExplainerLink: false)
            }
            .padding(Theme.Spacing.margin)
        }
        .background(Theme.Colors.tray)
        .navigationTitle("Across stages")
        .navigationBarTitleDisplayMode(.inline)
        .practiceBand(kind == .practice)
        .safeAreaInset(edge: .bottom) {
            NextActionBar(title: wizard.next.title) {
                if let route = wizard.next.route(ref) {
                    navigator.push(route)
                } else {
                    navigator.popToSession(ref, performNext: true)
                }
            }
        }
        .onAppear {
            UIFlags.markOpenedStages(sessionID: sessionID)
            flagsVersion += 1
        }
    }

    // MARK: - One metric

    @ViewBuilder
    private func metricSection(_ metric: BilateralMetric, series: StageSeries) -> some View {
        // Each chart row is named with its stage ("Set 1, preoperative marking"), so the
        // chart can be read without the readout list below it.
        let rows = zip(series.entries, series.rows(for: metric)).map { entry, row in
            StageLeanChart.Row(id: row.id, label: entry.title, measurement: row.measurement)
        }
        let lines = Array(zip(series.entries, series.readoutLines(for: metric)))
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(metric.title)
                .font(.sectionTitle)
                .foregroundStyle(Theme.Colors.ink)
                .accessibilityAddTraits(.isHeader)

            StageLeanChart(kind: chartKind(metric), rows: rows)
                .padding(.vertical, Theme.Spacing.xs)

            Text(metric.zeroCaption)
                .font(.support)
                .foregroundStyle(Theme.Colors.graduation)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(lines, id: \.0.id) { entry, line in
                    let r = entry.reading.reading(metric)
                    if r.measurement != nil {
                        // Keeps the value and its ± together on one line where the width allows.
                        ReadoutLine(title: entry.title, readout: r.readout)
                    } else {
                        readoutLine(line, measured: false)
                    }
                }
            }
            .padding(.top, Theme.Spacing.xs)

            Text("In the export: " + metric.exportName)
                .font(.support)
                .foregroundStyle(Theme.Colors.graduation)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func readoutLine(_ line: String, measured: Bool) -> some View {
        if measured {
            Text(line)
                .font(.readoutRow)
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // A set that is not measured appears only here, with its reason.
            Label {
                Text(line)
                    .font(.readoutRow)
                    .foregroundStyle(Theme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Theme.Colors.caution)
                    .accessibilityHidden(true)
            }
        }
    }

    private func chartKind(_ metric: BilateralMetric) -> StageLeanChart.Kind {
        if let right = metric.patientRightEnd, let left = metric.patientLeftEnd {
            return .difference(patientRightEnd: right, patientLeftEnd: left)
        }
        return .overlap
    }
}
