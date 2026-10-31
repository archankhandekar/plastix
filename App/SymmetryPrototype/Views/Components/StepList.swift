import SwiftUI

/// One numbered step: a 36pt circle, a title and an optional status line.
/// Done = filled accent circle with a tick; current = accent ring and accent number;
/// upcoming or static = hairline ring and slate number.
struct StepRow: View {
    struct Model: Identifiable {
        let id: Int
        let number: Int
        let title: String
        let status: String?
        let state: SessionProgress.StepState?
        let step: SessionProgress.Step?
    }

    let model: Model
    var onTap: (() -> Void)? = nil

    var body: some View {
        if let onTap {
            Button(action: onTap) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            circle
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(model.title)
                    .font(.stepTitle)
                    .foregroundStyle(isUpcoming ? Theme.Colors.slate : Theme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let status = model.status {
                    Text(status)
                        .font(.body)
                        .foregroundStyle(isCurrent ? Theme.Colors.ink : Theme.Colors.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.s)
        .tapTarget()
        .accessibilityElement(children: .combine)
    }

    private var circle: some View {
        ZStack {
            switch model.state {
            case .done:
                Circle().fill(Theme.Colors.done)
                Image(systemName: "checkmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
            case .current:
                Circle().stroke(Theme.Colors.accent, lineWidth: 2)
                Text(String(model.number))
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.Colors.accent)
            case .upcoming, nil:
                Circle().stroke(Theme.Colors.hairline, lineWidth: 1)
                Text(String(model.number))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(Theme.Colors.slate)
            }
        }
        .frame(width: 36, height: 36)
        .accessibilityLabel(accessibilityCircleLabel)
    }

    private var isCurrent: Bool {
        if case .current = model.state { return true }
        return false
    }

    private var isUpcoming: Bool {
        if case .upcoming = model.state { return true }
        return false
    }

    private var accessibilityCircleLabel: String {
        switch model.state {
        case .done: return "Step \(model.number), done"
        case .current: return "Step \(model.number), current"
        case .upcoming, nil: return "Step \(model.number)"
        }
    }
}

/// The numbered step list. Built from a `SessionProgress` (live states, tappable where
/// the step is actionable) or from static titles (the research notice).
struct StepListView: View {
    let rows: [StepRow.Model]
    var onTap: ((SessionProgress.Step) -> Void)? = nil

    private let actionableSteps: Set<SessionProgress.Step>

    /// Rows from `progress.states` in `Step.allCases` order. `onTap` is wired only for
    /// steps where `progress.isActionable(step)` is true.
    init(progress: SessionProgress, onTap: ((SessionProgress.Step) -> Void)? = nil) {
        rows = SessionProgress.Step.allCases.map { step in
            StepRow.Model(id: step.rawValue,
                          number: step.rawValue,
                          title: step.title,
                          status: progress.states[step]?.status,
                          state: progress.states[step],
                          step: step)
        }
        self.onTap = onTap
        actionableSteps = Set(SessionProgress.Step.allCases.filter { progress.isActionable($0) })
    }

    /// Rows numbered 1...n with no status and no state.
    init(staticTitles: [String]) {
        rows = staticTitles.enumerated().map { offset, title in
            StepRow.Model(id: offset + 1, number: offset + 1, title: title, status: nil, state: nil, step: nil)
        }
        onTap = nil
        actionableSteps = []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                StepRow(model: row, onTap: tapHandler(for: row))
            }
        }
    }

    private func tapHandler(for row: StepRow.Model) -> (() -> Void)? {
        guard let onTap, let step = row.step, actionableSteps.contains(step) else { return nil }
        return { onTap(step) }
    }
}
