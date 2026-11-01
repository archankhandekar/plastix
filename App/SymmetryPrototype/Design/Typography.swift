import SwiftUI

/// Plumb type scale. System families only: no bundled fonts, no serif, no Rounded, no
/// monospaced design, no all-caps and no tracking. Nothing is ever smaller than
/// `.subheadline` (`support`).
extension Font {
    /// The focused metric's MetricFormatter string under the plate. Only on the symmetry result.
    static let readoutHero = Font.system(.title, design: .default, weight: .semibold).width(.condensed).monospacedDigit()
    /// "Patient right" / "Patient left", in sentence case.
    static let sideLabel = Font.system(.headline, design: .default, weight: .semibold).width(.expanded)
    /// Screen titles inside content, for example "Set 3, after fat grafting".
    static let screenTitle = Font.system(.title2, design: .default, weight: .semibold)
    /// Section headings, for example "Left and right in this set".
    static let sectionTitle = Font.system(.title3, design: .default, weight: .semibold)
    /// MetricFormatter strings in gauges, stage lists and tables.
    static let readoutRow = Font.system(.body, design: .default, weight: .medium).monospacedDigit()
    /// The floor: taken-at lines, Not measured reasons, end labels. Nothing is smaller.
    static let support = Font.subheadline
    /// Ruler labels, gauge ends and chart axes. Charts axis labels must set this explicitly.
    static let scaleTick = Font.system(.subheadline, design: .default, weight: .regular).width(.condensed).monospacedDigit()
    /// Button labels.
    static let actionLabel = Font.system(.headline, design: .default, weight: .semibold)

    // MARK: Legacy aliases (screens not yet restyled keep compiling)

    static let metric = readoutRow
    static let metricLarge = readoutRow
    /// Raised to the floor.
    static let metricSmall = Font.subheadline
    static let stepTitle = sectionTitle
    static let readable = Font.body
    static let readableFloor = Font.subheadline
}
