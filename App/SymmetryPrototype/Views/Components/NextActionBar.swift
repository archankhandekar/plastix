import SwiftUI

/// The single "Next: <verb>" button every session-level screen ends with. Callers place
/// it in `.safeAreaInset(edge: .bottom)`.
struct NextActionBar: View {
    let title: String
    var detail: String? = nil
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let detail {
                Text(detail)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(title, action: action)
                .buttonStyle(PrimaryButtonStyle())
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(Theme.Spacing.m)
        .background(.bar)
    }
}
