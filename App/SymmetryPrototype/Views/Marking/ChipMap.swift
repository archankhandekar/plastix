import SwiftUI
import SymmetryCore

/// The six points laid out the way they sit on a frontal photo: patient right in the
/// screen-left column, the midline in the centre (Field wash and the axis) and patient left
/// in the screen-right column. Tapping a cell selects that point for placing or moving.
///
/// At accessibility text sizes the three columns would break words, so the cells stack in
/// one column (still reading patient right, midline, patient left in each row) and each
/// cell carries its own column header.
struct ChipMap: View {
    private let landmarks: LandmarkSet?
    private let selected: LandmarkType?
    private let onSelect: (LandmarkType) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(landmarks: LandmarkSet?, selected: LandmarkType?, onSelect: @escaping (LandmarkType) -> Void) {
        self.landmarks = landmarks
        self.selected = selected
        self.onSelect = onSelect
    }

    /// Rows top to bottom; within a row, patient right, midline, patient left.
    static let rows: [[LandmarkType]] = [
        [.rightNipple, .sternalNotch, .leftNipple],
        [.rightIMF, .midlineBottom, .leftIMF],
    ]

    enum Column: Int, CaseIterable {
        case patientRight, midline, patientLeft

        var header: String {
            switch self {
            case .patientRight: return "Patient right"
            case .midline: return "Midline"
            case .patientLeft: return "Patient left"
            }
        }

        var alignment: Alignment {
            switch self {
            case .patientRight: return .leading
            case .midline: return .center
            case .patientLeft: return .trailing
            }
        }

        var textAlignment: TextAlignment {
            switch self {
            case .patientRight: return .leading
            case .midline: return .center
            case .patientLeft: return .trailing
            }
        }
    }

    enum CellState: Equatable {
        case placed, next, notPlaced

        /// The visible state line. A point that is neither placed nor next shows no words,
        /// only the dashed-circle glyph.
        var line: String {
            switch self {
            case .placed: return "placed"
            case .next: return "next"
            case .notPlaced: return ""
            }
        }

        var accessibilityValue: String {
            switch self {
            case .placed: return "placed"
            case .next: return "next"
            case .notPlaced: return "not placed"
            }
        }
    }

    static func state(of type: LandmarkType, landmarks: LandmarkSet?, selected: LandmarkType?) -> CellState {
        if landmarks?[type] != nil { return .placed }
        return type == selected ? .next : .notPlaced
    }

    private let spacing = Theme.Spacing.s

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            stacked
        } else {
            grid
        }
    }

    // MARK: - Layouts

    private var grid: some View {
        VStack(spacing: spacing) {
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Column.allCases, id: \.self) { column in
                    Text(column.header)
                        .font(.sideLabel)
                        .foregroundStyle(Theme.Colors.ink)
                        .multilineTextAlignment(column.textAlignment)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .frame(maxWidth: .infinity, alignment: column.alignment)
                        .background(column == .midline ? Theme.Colors.fieldWash : Color.clear)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            ForEach(Self.rows.indices, id: \.self) { r in
                HStack(spacing: spacing) {
                    ForEach(Column.allCases, id: \.self) { column in
                        cell(Self.rows[r][column.rawValue], column: column, showsHeader: false)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Theme.Spacing.s)
        .background { centreColumn }
    }

    private var stacked: some View {
        VStack(spacing: spacing) {
            ForEach(Self.rows.indices, id: \.self) { r in
                ForEach(Column.allCases, id: \.self) { column in
                    cell(Self.rows[r][column.rawValue], column: column, showsHeader: true)
                }
            }
        }
    }

    /// The centre column's Field wash, with the patient midline axis down its middle. The
    /// three equal columns put the axis at exactly 50 percent of the width.
    private var centreColumn: some View {
        HStack(spacing: spacing) {
            Color.clear
            ZStack {
                RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.Colors.fieldWash)
                AxisRule()
            }
            Color.clear
        }
        .accessibilityHidden(true)
    }

    // MARK: - Cells

    private func cell(_ type: LandmarkType, column: Column, showsHeader: Bool) -> some View {
        let state = Self.state(of: type, landmarks: landmarks, selected: selected)
        let isSelected = type == selected
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius)
        let isMidline = column == .midline
        return Button {
            onSelect(type)
        } label: {
            VStack(alignment: showsHeader ? .leading : column.horizontal, spacing: Theme.Spacing.xs) {
                if showsHeader {
                    Text(column.header)
                        .font(.sideLabel)
                        .foregroundStyle(Theme.Colors.graduation)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(LandmarkHints.chipLabel(type))
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(Theme.Colors.ink)
                    .multilineTextAlignment(showsHeader ? .leading : column.textAlignment)
                    .fixedSize(horizontal: false, vertical: true)
                stateLine(state)
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.s)
            // In the grid the axis runs down the centre column and passes behind the midline
            // labels, which sit on a Field wash backing so they stay readable.
            .background {
                if isMidline && !showsHeader {
                    shape.fill(Theme.Colors.fieldWash)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Theme.tapTarget, maxHeight: .infinity,
                   alignment: showsHeader ? .leading : column.alignment)
            .background {
                // Stacked, the midline cells keep the centre column's Field wash.
                if isMidline && showsHeader {
                    shape.fill(Theme.Colors.fieldWash)
                }
            }
            .overlay {
                shape.strokeBorder(isSelected ? Theme.Colors.marker : Theme.Colors.graduation,
                                   lineWidth: isSelected ? 2 : 1.5)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LandmarkHints.chipLabel(type))
        .accessibilityValue(state.accessibilityValue)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }

    @ViewBuilder
    private func stateLine(_ state: CellState) -> some View {
        switch state {
        case .placed:
            // Never breaks the word: drops the swatch, then the word, when the cell is narrow.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.xs) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.Colors.marker)
                        .frame(width: 12, height: 12)
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.Colors.marker)
                    Text(state.line)
                        .foregroundStyle(Theme.Colors.ink)
                }
                .fixedSize()
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.Colors.marker)
                    Text(state.line)
                        .foregroundStyle(Theme.Colors.ink)
                }
                .fixedSize()
                Image(systemName: "checkmark")
                    .foregroundStyle(Theme.Colors.marker)
            }
            .font(.support)
        case .next:
            Text(state.line)
                .font(.support.weight(.semibold))
                .foregroundStyle(Theme.Colors.marker)
        case .notPlaced:
            Image(systemName: "circle.dashed")
                .font(.support)
                .foregroundStyle(Theme.Colors.graduation)
        }
    }
}

private extension ChipMap.Column {
    var horizontal: HorizontalAlignment {
        switch self {
        case .patientRight: return .leading
        case .midline: return .center
        case .patientLeft: return .trailing
        }
    }
}
