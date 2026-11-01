import SwiftUI

/// Flows its children left to right and onto more lines when they do not fit, so segmented
/// choices and chips wrap at large text sizes instead of shrinking.
struct WrapLayout: Layout {
    var spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    struct Cache {
        var sizes: [CGSize] = []
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(maxWidth: maxWidth, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let rows = arrange(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                                           anchor: .topLeading,
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > maxWidth {
                // Too wide for a line on its own: give it the full width and let it wrap its text.
                size = subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                size.width = min(size.width, maxWidth)
            }
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty, needed > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append((index, size))
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

/// A row of mutually exclusive choices. Cells are at least 56pt tall and wrap onto more
/// lines at large text sizes. The selected cell has a Field wash fill and a 2pt Drape outline.
struct SegmentedChoice<Value: Hashable>: View {
    private let options: [(value: Value, title: String)]
    @Binding private var selection: Value
    private let onPlate: Bool

    init(_ options: [(value: Value, title: String)], selection: Binding<Value>, onPlate: Bool = false) {
        self.options = options
        self._selection = selection
        self.onPlate = onPlate
    }

    var body: some View {
        WrapLayout(spacing: Theme.Spacing.s) {
            ForEach(options.indices, id: \.self) { index in
                cell(options[index].value, title: options[index].title)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cell(_ value: Value, title: String) -> some View {
        let isSelected = value == selection
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius)
        return Button {
            selection = value
        } label: {
            Text(title)
                .font(.body.weight(isSelected ? .semibold : .regular))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(onPlate ? Theme.Colors.plateInk : Theme.Colors.ink)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
                .frame(minWidth: Theme.tapTarget, minHeight: Theme.tapTarget)
                .background(fill(isSelected), in: shape)
                .overlay(shape.strokeBorder(stroke(isSelected), lineWidth: isSelected ? 2 : 1.5))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func fill(_ isSelected: Bool) -> Color {
        guard isSelected else { return .clear }
        return onPlate ? Color.white.opacity(0.12) : Theme.Colors.fieldWash
    }

    private func stroke(_ isSelected: Bool) -> Color {
        if isSelected { return onPlate ? Theme.Colors.drapeOnPlate : Theme.Colors.drape }
        return onPlate ? Theme.Colors.plateGraduation : Theme.Colors.graduation
    }
}

/// A 56pt on/off chip whose label says its state in words: "Flip: On" / "Flip: Off".
struct ToggleChip: View {
    private let title: String
    @Binding private var isOn: Bool
    private let onPlate: Bool

    init(_ title: String, isOn: Binding<Bool>, onPlate: Bool = false) {
        self.title = title
        self._isOn = isOn
        self.onPlate = onPlate
    }

    private var label: String {
        title + (isOn ? ": On" : ": Off")
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius)
        Button {
            isOn.toggle()
        } label: {
            Text(label)
                .font(.body.weight(isOn ? .semibold : .regular))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(onPlate ? Theme.Colors.plateInk : Theme.Colors.ink)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
                .frame(minWidth: Theme.tapTarget, minHeight: Theme.tapTarget)
                .background(fill, in: shape)
                .overlay(shape.strokeBorder(stroke, lineWidth: isOn ? 2 : 1.5))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private var fill: Color {
        guard isOn else { return .clear }
        return onPlate ? Color.white.opacity(0.12) : Theme.Colors.fieldWash
    }

    private var stroke: Color {
        if isOn { return onPlate ? Theme.Colors.drapeOnPlate : Theme.Colors.drape }
        return onPlate ? Theme.Colors.plateGraduation : Theme.Colors.graduation
    }
}
