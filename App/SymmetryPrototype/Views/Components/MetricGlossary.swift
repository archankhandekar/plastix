import SwiftUI
import SymmetryCore

/// Plain-English meanings for the six frontal metrics and the shared glossary lines.
/// Text only: it never judges a value.
enum MetricGlossary {
    static let referenceLengthLine = "L is the distance from the sternal notch to the midline bottom in each photo. Every value is a share of L, so the two photos can be compared even if the camera was closer or further away."
    static let uncertaintyLine = "The ± is the wobble from placing points by hand. A value or change smaller than its ± cannot be told apart from zero."
    static let signLine = "A plus sign means the patient's left sits lower, or farther from the midline, than the right. A minus sign means the opposite."
    static let changeLine = "Change = later set minus earlier set, with both uncertainties combined."
    /// The change line for a specific pair, naming the sets as they appear in the row titles.
    static func changeLine(earlier i: Int, later j: Int) -> String {
        "Change = set \(j) minus set \(i), with both uncertainties combined."
    }
    static let withinUncertaintyLine = "The change is smaller than its ±, so it cannot be told apart from zero."
    /// The provenance colour grammar, in one sentence.
    static let provenanceLine = "Violet is what you marked. Blue is what the app drew from your marks."
    /// How sides sit on screen: the same as a frontal photo.
    static let sidesLine = "Left and right are the patient's. Patient left is on the right of the photo."

    /// Metric names in `FrontalMetrics.namedMetrics` order.
    static let metricNames: [String] = [
        "Vertical nipple difference",
        "Patient left nipple to midline",
        "Patient right nipple to midline",
        "Nipple to midline difference",
        "Inframammary fold height difference",
        "Contour overlap",
    ]

    /// One-line meaning keyed on the six `FrontalMetrics.namedMetrics` names. Unknown names return "".
    static func meaning(for metricName: String) -> String {
        switch metricName {
        case "Vertical nipple difference":
            return "How much lower the patient's left nipple sits than the right, as a share of L. Plus means left is lower, minus means right is lower."
        case "Patient left nipple to midline":
            return "How far the patient's left nipple sits from the midline, as a share of L."
        case "Patient right nipple to midline":
            return "How far the patient's right nipple sits from the midline, as a share of L."
        case "Nipple to midline difference":
            return "Left distance minus right distance. Plus means the left nipple sits farther from the midline than the right."
        case "Inframammary fold height difference":
            return "How much lower the patient's left fold sits than the right, as a share of L. Plus means left is lower."
        case "Contour overlap":
            return "How closely the two breast outlines coincide when one is mirrored across the midline. 1.00 means they coincide exactly, 0 means no overlap. Its ± comes from the drawing grid, not from point placement."
        default:
            return ""
        }
    }

    /// The point landmarks a metric needs. The two midline points are always needed.
    static func landmarksUsed(by metricName: String) -> [LandmarkType] {
        switch metricName {
        case "Vertical nipple difference", "Nipple to midline difference":
            return [.sternalNotch, .midlineBottom, .leftNipple, .rightNipple]
        case "Patient left nipple to midline":
            return [.sternalNotch, .midlineBottom, .leftNipple]
        case "Patient right nipple to midline":
            return [.sternalNotch, .midlineBottom, .rightNipple]
        case "Inframammary fold height difference":
            return [.sternalNotch, .midlineBottom, .leftIMF, .rightIMF]
        case "Contour overlap":
            return [.sternalNotch, .midlineBottom]
        default:
            return []
        }
    }

    /// Why a metric reads "Not measured", in one line, or nil when there is no reason to give.
    static func reason(flags: [ReliabilityFlag], missing: [LandmarkType], hasContours: Bool, metricName: String) -> String? {
        let midlinePresent = !missing.contains(.sternalNotch) && !missing.contains(.midlineBottom)
        if flags.contains(.degenerateMidline), midlinePresent {
            return "The notch and midline bottom are on the same spot, so nothing can be scaled."
        }
        let used = landmarksUsed(by: metricName)
        if used.contains(where: { missing.contains($0) }) {
            let names = LandmarkType.allCases
                .filter { missing.contains($0) }
                .map(pointName)
                .joined(separator: ", ")
            return "Mark the missing points: \(names)."
        }
        if metricName == "Contour overlap" {
            if flags.contains(.contourTooSparse) { return "Both outlines need at least 8 points." }
            if !hasContours { return "Outlines were not drawn. This one is optional." }
        }
        return nil
    }

    /// Short point name without the "Patient " prefix, as used in the editor chips.
    static func pointName(_ type: LandmarkType) -> String {
        switch type {
        case .sternalNotch: return "Sternal notch"
        case .midlineBottom: return "Midline bottom"
        case .leftNipple: return "Left nipple"
        case .rightNipple: return "Right nipple"
        case .leftIMF: return "Left fold"
        case .rightIMF: return "Right fold"
        }
    }
}

/// Collapsible "How to read these numbers" card. Open the first time; the state is remembered.
struct HowToReadCard: View {
    @AppStorage("howToReadCollapsed") private var collapsed = false

    var body: some View {
        GuidanceCard(kind: .info,
                     title: "How to read these numbers",
                     lines: [MetricGlossary.referenceLengthLine,
                             MetricGlossary.uncertaintyLine,
                             MetricGlossary.signLine],
                     collapsible: true,
                     isExpanded: Binding(get: { !collapsed }, set: { collapsed = !$0 }))
    }
}

/// "What the numbers mean": the glossary lines, the six metrics, and a link to the definitions.
/// Flat sections separated by space, on the tray.
struct MetricExplainerSheet: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("What the numbers mean")
                    .font(.screenTitle)
                    .foregroundStyle(Theme.Colors.ink)

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    glossaryLine(MetricGlossary.referenceLengthLine)
                    glossaryLine(MetricGlossary.uncertaintyLine)
                    glossaryLine(MetricGlossary.signLine)
                    glossaryLine(MetricGlossary.sidesLine)
                    glossaryLine(MetricGlossary.provenanceLine)
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    ForEach(MetricGlossary.metricNames, id: \.self) { name in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(name)
                                .font(.sectionTitle)
                                .foregroundStyle(Theme.Colors.ink)
                            Text(MetricGlossary.meaning(for: name))
                                .font(.body)
                                .foregroundStyle(Theme.Colors.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .cardStyle()

                NavigationLink {
                    DefinitionsView()
                } label: {
                    HStack {
                        Text("Measurement definitions and limitations")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.graduation)
                            .accessibilityHidden(true)
                    }
                    .tapTarget()
                }
                .cardStyle()
            }
            .padding(Theme.Spacing.margin)
        }
        .background(Theme.Colors.tray)
        .navigationTitle("What the numbers mean")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func glossaryLine(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(Theme.Colors.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The exported measurement definitions, rendered in the app.
struct DefinitionsView: View {
    var body: some View {
        ScrollView {
            Text(definitionsText)
                .font(.body)
                .foregroundStyle(Theme.Colors.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.margin)
        }
        .background(Theme.Colors.tray)
        .navigationTitle("Definitions")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var definitionsText: AttributedString {
        (try? AttributedString(markdown: MeasurementDefinitions.markdown,
                               options: .init(interpretedSyntax: .full)))
            ?? AttributedString(MeasurementDefinitions.markdown)
    }
}
