import SwiftUI

/// The numbered steps of a session (or the static steps on the research notice). Flat 56pt
/// rows: no cards and no rules between them. Only actionable rows are buttons.
struct StepRail: View {
    struct Item: Identifiable {
        let id: Int
        let number: Int
        let title: String
        let status: String?
        let state: State
        let isActionable: Bool

        init(id: Int, number: Int, title: String, status: String?, state: State, isActionable: Bool) {
            self.id = id
            self.number = number
            self.title = title
            self.status = status
            self.state = state
            self.isActionable = isActionable
        }
    }

    enum State {
        case done, current, upcoming, plain
    }

    private let items: [Item]
    private let compact: Bool
    private let onTap: ((Int) -> Void)?

    init(items: [Item], compact: Bool = false, onTap: ((Int) -> Void)? = nil) {
        self.items = items
        self.compact = compact
        self.onTap = onTap
    }

    /// Rows numbered 1...n with no status, in the plain state, not tappable.
    init(staticTitles: [String]) {
        self.items = staticTitles.enumerated().map { offset, title in
            Item(id: offset + 1, number: offset + 1, title: title, status: nil, state: .plain, isActionable: false)
        }
        self.compact = false
        self.onTap = nil
    }

    var body: some View {
        if compact {
            WrapLayout(spacing: Theme.Spacing.s) {
                ForEach(items) { item in
                    wrapIfActionable(item) { chip(item) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    wrapIfActionable(item) { row(item) }
                }
            }
        }
    }

    @ViewBuilder
    private func wrapIfActionable<Content: View>(_ item: Item, @ViewBuilder content: () -> Content) -> some View {
        if item.isActionable, let onTap {
            Button { onTap(item.id) } label: { content() }
                .buttonStyle(.plain)
        } else {
            content()
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            StepMark(number: item.number, state: item.state)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(item.state == .upcoming ? Theme.Colors.graduation : Theme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let status = item.status {
                    Text(status)
                        .font(.support)
                        .foregroundStyle(item.state == .current ? Theme.Colors.ink : Theme.Colors.graduation)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .tapTarget()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(item))
        .accessibilityAddTraits(item.state == .current ? [.isSelected] : [])
    }

    private func chip(_ item: Item) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            StepMark(number: item.number, state: item.state)
            Text(item.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(item.state == .upcoming ? Theme.Colors.graduation : Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .frame(minHeight: Theme.tapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(item))
        .accessibilityAddTraits(item.state == .current ? [.isSelected] : [])
    }

    private func accessibilityText(_ item: Item) -> String {
        var parts = ["Step \(item.number)", item.title]
        switch item.state {
        case .done: parts.append("done")
        case .current: parts.append("current")
        case .upcoming, .plain: break
        }
        if let status = item.status { parts.append(status) }
        return parts.joined(separator: ", ")
    }
}

/// The 28pt step circle. Done: Drape checkmark. Current: 2pt Drape ring on Field wash.
/// Upcoming and plain: a Graduation ring with the numeral.
private struct StepMark: View {
    let number: Int
    let state: StepRail.State

    var body: some View {
        ZStack {
            switch state {
            case .done:
                Circle().strokeBorder(Theme.Colors.drape, lineWidth: 2)
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.Colors.drape)
            case .current:
                Circle().fill(Theme.Colors.fieldWash)
                Circle().strokeBorder(Theme.Colors.drape, lineWidth: 2)
                Text(String(number))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.Colors.ink)
            case .upcoming:
                Circle().strokeBorder(Theme.Colors.graduation, lineWidth: 1.5)
                Text(String(number))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.Colors.graduation)
            case .plain:
                Circle().strokeBorder(Theme.Colors.graduation, lineWidth: 1.5)
                Text(String(number))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.Colors.ink)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}
