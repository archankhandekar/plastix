import SwiftUI

/// The virtual patient's tour on its session home: five tasks, each a 56pt row that opens
/// the task, ticked from model state and UI flags. A tick says the task was opened or done,
/// never how well. Below it: what the mannequin is, and a way to start it again.
struct PracticeTourSection: View {
    let tour: PracticeTour
    let onSelect: (PracticeTourTask) -> Void
    let onReset: () -> Void

    static let caption = "The virtual patient is a rendered mannequin. Its midline bottom point is the umbilicus."

    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Practice tour")
                .font(.sectionTitle)
                .foregroundStyle(Theme.Colors.ink)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(tour.items) { item in
                    row(item)
                }
            }

            Text(Self.caption)
                .font(.support)
                .foregroundStyle(Theme.Colors.graduation)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Reset the virtual patient") { confirmReset = true }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, Theme.Spacing.s)
        }
        .confirmationDialog("Start the virtual patient again from the beginning?",
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { onReset() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func row(_ item: PracticeTour.Item) -> some View {
        Button {
            onSelect(item.task)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                Image(systemName: item.isDone ? "checkmark" : "circle.dashed")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(item.isDone ? Theme.Colors.drape : Theme.Colors.graduation)
                    .frame(width: 24)
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
