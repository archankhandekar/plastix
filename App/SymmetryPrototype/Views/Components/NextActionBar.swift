import SwiftUI

/// The single verb-first action every session-level screen ends with: a 64pt Drape button
/// on the flat tray. Callers place it in `.safeAreaInset(edge: .bottom)`.
struct NextActionBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    var detail: String? = nil
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            // The inset cannot scroll, so at accessibility text sizes the detail line is dropped
            // and only the buttons stay.
            if let detail, !dynamicTypeSize.isAccessibilitySize {
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
        .padding(.horizontal, Theme.Spacing.margin)
        .padding(.vertical, Theme.Spacing.m)
        .background(Theme.Colors.tray)
    }
}
