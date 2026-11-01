import SwiftUI

/// The virtual patient's tour on its session home, below the left-right result: one 56pt
/// summary row ("Practice tour: 2 of 5 done" and the next task) that folds open into the
/// five task rows. Each task row opens the task; ticks come from model state and UI flags
/// and say the task was opened or done, never how well. The mannequin caption sits inside
/// the open list. Resetting the virtual patient is not here; it is a quiet action at the
/// end of the page.
struct PracticeTourSection: View {
    /// Grows with Dynamic Type so the glyph never overflows its column at accessibility sizes.
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 24
    let tour: PracticeTour
    let onSelect: (PracticeTourTask) -> Void

    static let caption = "The virtual patient is a rendered mannequin. Its midline bottom point is the umbilicus."

    @State private var isExpanded = false

    private var doneCount: Int { tour.items.filter(\.isDone).count }

    private var summaryTitle: String {
        doneCount == tour.items.count
            ? "Practice tour: all \(tour.items.count) done"
            : "Practice tour: \(doneCount) of \(tour.items.count) done"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryRow

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tour.items) { item in
                        row(item)
                    }
                    Text(Self.caption)
                        .font(.support)
                        .foregroundStyle(Theme.Colors.graduation)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Theme.Spacing.s)
                }
                .padding(.leading, Theme.Spacing.s)
            }
        }
    }

    private var summaryRow: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { isExpanded.toggle() }
        } label: {
            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summaryTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !isExpanded, let next = tour.nextTask {
                        Text("Next: " + next.title)
                            .font(.support)
                            .foregroundStyle(Theme.Colors.graduation)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Colors.graduation)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Theme.Spacing.s)
            .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryTitle + (tour.nextTask.map { ". Next: " + $0.title } ?? "."))
        .accessibilityHint(isExpanded ? "Hides the five tasks." : "Shows the five tasks.")
        .accessibilityAddTraits(.isButton)
    }

    private func row(_ item: PracticeTour.Item) -> some View {
        Button {
            onSelect(item.task)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                Image(systemName: item.isDone ? "checkmark" : "circle.dashed")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(item.isDone ? Theme.Colors.drape : Theme.Colors.graduation)
                    .frame(width: iconWidth)
                    .accessibilityHidden(true)
                Text(item.task.title)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Theme.Spacing.s)
            .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((item.isDone ? "Done. " : "To do. ") + item.task.title)
        .accessibilityAddTraits(.isButton)
    }
}
