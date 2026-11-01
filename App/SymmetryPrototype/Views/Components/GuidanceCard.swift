import SwiftUI

/// A short piece of guidance with an optional title and optional 56pt action(s).
/// Flat: no card, no background and no stroke; a leading glyph carries the kind.
/// `.info` is quiet, `.caution` needs attention but can proceed, `.unreliable` means the
/// numbers need care (shown as caution: there is no red), `.dark` sits on Plate with a
/// scrim. Colour never says a measurement is good or bad.
struct GuidanceCard<Action: View>: View {
    enum Kind { case info, caution, unreliable, dark }

    let kind: Kind
    var title: String? = nil
    let lines: [String]
    var collapsible: Bool = false
    var isExpanded: Binding<Bool>? = nil
    @ViewBuilder let action: () -> Action

    @State private var localExpanded = true

    init(kind: Kind = .info,
         title: String? = nil,
         lines: [String],
         collapsible: Bool = false,
         isExpanded: Binding<Bool>? = nil,
         @ViewBuilder action: @escaping () -> Action) {
        self.kind = kind
        self.title = title
        self.lines = lines
        self.collapsible = collapsible
        self.isExpanded = isExpanded
        self.action = action
    }

    init(kind: Kind = .info,
         title: String? = nil,
         body: String,
         collapsible: Bool = false,
         isExpanded: Binding<Bool>? = nil,
         @ViewBuilder action: @escaping () -> Action) {
        self.init(kind: kind, title: title, lines: [body], collapsible: collapsible,
                  isExpanded: isExpanded, action: action)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if collapsible {
                Button(action: toggle) { header }
                    .buttonStyle(.plain)
                    .tapTarget()
                    .accessibilityHint(expanded ? "Collapses the card" : "Expands the card")
            } else {
                header
            }
            if expanded {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    ForEach(Array(bodyLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    action()
                }
                .padding(.leading, iconColumnWidth)
            }
        }
        .padding(.vertical, Theme.Spacing.s)
        .padding(.horizontal, kind == .dark ? Theme.Spacing.m : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(textColor)
        .background(background, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    // MARK: - Pieces

    private let iconColumnWidth: CGFloat = 28

    /// Without a title the first line sits beside the symbol, so the body shows the rest.
    private var headerLeadsWithFirstLine: Bool { title == nil && !collapsible }

    private var bodyLines: [String] {
        headerLeadsWithFirstLine ? Array(lines.dropFirst()) : lines
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 0) {
            Image(systemName: symbolName)
                .font(title == nil ? .body : .sectionTitle)
                .foregroundStyle(iconColor)
                .frame(width: iconColumnWidth, alignment: .leading)
                .accessibilityHidden(true)
            if let title {
                Text(title)
                    .font(.sectionTitle)
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: false, vertical: true)
            } else if headerLeadsWithFirstLine, let first = lines.first {
                Text(first)
                    .font(.body)
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if collapsible {
                Spacer(minLength: Theme.Spacing.s)
                // Words, not a chevron: buttons carry no arrows.
                Text(expanded ? "Hide" : "Show")
                    .font(.support.weight(.semibold))
                    .foregroundStyle(kind == .dark ? Theme.Colors.plateInk : Theme.Colors.drape)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var expanded: Bool {
        guard collapsible else { return true }
        return isExpanded?.wrappedValue ?? localExpanded
    }

    private func toggle() {
        if let isExpanded {
            isExpanded.wrappedValue.toggle()
        } else {
            localExpanded.toggle()
        }
    }

    private var symbolName: String {
        switch kind {
        case .info, .dark: return "info.circle"
        case .caution, .unreliable: return "exclamationmark.triangle"
        }
    }

    private var iconColor: Color {
        switch kind {
        case .info: return Theme.Colors.graduation
        case .caution, .unreliable: return Theme.Colors.caution
        case .dark: return Theme.Colors.plateInk
        }
    }

    private var textColor: Color {
        kind == .dark ? Theme.Colors.plateInk : Theme.Colors.ink
    }

    /// Only the on-Plate kind has a backing: a black scrim so it reads over the viewfinder.
    private var background: Color {
        kind == .dark ? Color.black.opacity(0.75) : Color.clear
    }
}

extension GuidanceCard where Action == EmptyView {
    init(kind: Kind = .info,
         title: String? = nil,
         body: String,
         collapsible: Bool = false,
         isExpanded: Binding<Bool>? = nil) {
        self.init(kind: kind, title: title, lines: [body], collapsible: collapsible,
                  isExpanded: isExpanded, action: { EmptyView() })
    }

    init(kind: Kind = .info,
         title: String? = nil,
         lines: [String],
         collapsible: Bool = false,
         isExpanded: Binding<Bool>? = nil) {
        self.init(kind: kind, title: title, lines: lines, collapsible: collapsible,
                  isExpanded: isExpanded, action: { EmptyView() })
    }
}
