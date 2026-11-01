import SwiftUI
import SymmetryModels

/// Every photo set of the session in order, as flat 56pt rows: the set number and its
/// stage, then a short line of what it holds. A measured set opens its left and right
/// result; any other set opens its photos. The caller provides the section heading.
struct AllSetsList: View {
    let session: StudySession
    let sigma: Double
    /// The set, its status, and whether it is measured.
    let onOpen: (CaptureSet, SetStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(session.orderedCaptureSets.enumerated()), id: \.element.id) { offset, set in
                let status = SetStatus(set: set, index: offset + 1, sigma: sigma)
                row(set: set, status: status)
            }
        }
    }

    private func row(set: CaptureSet, status: SetStatus) -> some View {
        Button {
            onOpen(set, status)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                Text(String(status.index))
                    .font(.readoutRow)
                    .foregroundStyle(Theme.Colors.ink)
                    .frame(minWidth: 24, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(set.stage.label)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(status.shortLine)
                        .font(.support)
                        .foregroundStyle(Theme.Colors.graduation)
                        .fixedSize(horizontal: false, vertical: true)
                    if let warning = Self.warningLine(status.warningCount) {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                            Image(systemName: "exclamationmark.triangle")
                                .accessibilityHidden(true)
                            Text(warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.support)
                        .foregroundStyle(Theme.Colors.caution)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Theme.Spacing.s)
            .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(set: set, status: status))
        .accessibilityHint(status.isMeasured ? "Opens left and right for this set." : "Opens the photos of this set.")
        .accessibilityAddTraits(.isButton)
    }

    private func accessibilityText(set: CaptureSet, status: SetStatus) -> String {
        var parts = ["Set \(status.index), \(set.stage.label).", status.shortLine + "."]
        if let warning = Self.warningLine(status.warningCount) { parts.append(warning) }
        return parts.joined(separator: " ")
    }

    /// "Warning: 1 photo did not pass the photo check." Nil when every photo passed.
    static func warningLine(_ count: Int) -> String? {
        switch count {
        case ..<1: return nil
        case 1: return "Warning: 1 photo did not pass the photo check."
        default: return "Warning: \(count) photos did not pass the photo check."
        }
    }
}
