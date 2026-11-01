import SwiftUI

/// The single verb-first action every session-level screen ends with: a 64pt Drape button
/// on the flat tray. Callers place it in `.safeAreaInset(edge: .bottom)`.
///
/// It is pinned chrome, so it separates itself from the page: a Graduation hairline on its
/// top edge and a short tray fade above it, so content scrolling underneath dissolves
/// instead of being sliced through. Its type stops growing at `maxTypeSize` so the content
/// above keeps the screen; the large content viewer shows the label at bigger sizes.
struct NextActionBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale

    let title: String
    var detail: String? = nil
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    let action: () -> Void

    /// Pinned chrome stops growing here.
    static let maxTypeSize = DynamicTypeSize.accessibility1
    /// Height of the fade above the bar.
    private static let fadeHeight: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            // The inset cannot scroll, so at accessibility text sizes the detail line is dropped
            // and only the buttons stay. It is the caption of the action, so it is quiet.
            if let detail, !dynamicTypeSize.isAccessibilitySize {
                Text(detail)
                    .font(.support)
                    .foregroundStyle(Theme.Colors.graduation)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(title, action: action)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityShowsLargeContentViewer()
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityShowsLargeContentViewer()
            }
        }
        .dynamicTypeSize(...Self.maxTypeSize)
        .padding(.horizontal, Theme.Spacing.margin)
        .padding(.vertical, Theme.Spacing.m)
        .background(Theme.Colors.tray)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.Colors.graduation.opacity(0.3))
                .frame(height: 1 / max(displayScale, 1))
                .accessibilityHidden(true)
        }
        .background(alignment: .top) {
            // Drawn above the bar's own frame, over the scrolling content.
            LinearGradient(colors: [Theme.Colors.tray.opacity(0), Theme.Colors.tray],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: Self.fadeHeight)
                .offset(y: -Self.fadeHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
