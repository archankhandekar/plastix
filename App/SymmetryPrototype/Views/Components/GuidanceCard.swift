import SwiftUI

/// A short piece of guidance with an optional title and optional 56pt action(s).
/// `.info` is quiet, `.caution` needs attention but can proceed, `.unreliable` means the
/// numbers cannot be trusted, `.dark` is for the camera screen. Colour never says a
/// measurement is good or bad.
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
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(textColor)
        .background(background, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(strokeColor, lineWidth: 1))
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
                .font(.stepTitle)
                .foregroundStyle(iconColor)
                .frame(width: iconColumnWidth, alignment: .leading)
            if let title {
                Text(title)
                    .font(.stepTitle)
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
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(textColor)
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
        case .caution: return "exclamationmark.triangle.fill"
        case .unreliable: return "xmark.octagon.fill"
        }
    }

    private var iconColor: Color {
        switch kind {
        case .info: return Theme.Colors.slate
        case .caution: return Theme.Colors.caution
        case .unreliable: return Theme.Colors.unreliable
        case .dark: return .white
        }
    }

    private var textColor: Color {
        kind == .dark ? .white : Theme.Colors.ink
    }

    private var background: Color {
        kind == .dark ? Color.black.opacity(0.7) : Theme.Colors.cardBackground
    }

    private var strokeColor: Color {
        switch kind {
        case .info: return Theme.Colors.hairline
        case .caution: return Theme.Colors.caution
        case .unreliable: return Theme.Colors.unreliable
        case .dark: return .clear
        }
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
