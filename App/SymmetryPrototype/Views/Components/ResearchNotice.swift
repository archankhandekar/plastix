import SwiftUI

/// Full-screen notice shown once at first launch.
struct ResearchNoticeView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Spacer()
            Text("Research use only")
                .font(.largeTitle.weight(.semibold))
            Text("This prototype photographs and measures breast symmetry for a research study. It is not a medical device and is not clinically validated.")
            Text("It reports normalized image geometry with uncertainty. It does not score symmetry, label results better or worse, or suggest any surgical action.")
            Text("Images and measurements stay on this device under iOS data protection. Use only a non-identifying study ID. Obtain consent and institutional review before use.")
            Spacer()
            Button("I understand") { settings.researchNoticeAccepted = true }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Theme.Spacing.l)
        .background(Theme.Colors.paper)
        .foregroundStyle(Theme.Colors.ink)
    }
}

/// Compact banner for screens that show numbers.
struct ResearchNoticeBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: "info.circle")
            Text("Research prototype. Not clinically validated. Values are normalized image geometry, not physical measurements.")
        }
        .font(.footnote)
        .foregroundStyle(Theme.Colors.slate)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
