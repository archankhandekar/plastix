import SwiftUI

/// A quiet, rarely used action (Reset the virtual patient): a 56pt text row with a leading
/// glyph, no outline and no fill, in Graduation so it never competes with the content or
/// the one primary action.
struct QuietButtonStyle: ButtonStyle {
    var systemImage: String?

    init(systemImage: String? = nil) {
        self.systemImage = systemImage
    }

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            configuration.label
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.body)
        .foregroundStyle(Theme.Colors.graduation)
        .frame(maxWidth: .infinity, minHeight: Theme.tapTarget, alignment: .leading)
        .contentShape(Rectangle())
        .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.45)
    }
}
