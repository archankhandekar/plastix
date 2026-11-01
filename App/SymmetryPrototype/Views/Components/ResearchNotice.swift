import SwiftUI

/// Full-screen notice shown once at first launch: what the app is, what it is not, and
/// the four steps it walks through.
struct ResearchNoticeView: View {
    @EnvironmentObject private var settings: AppSettings

    private let bullets = [
        "Not a medical device and not clinically validated. For a research study only.",
        "It reports image geometry with its uncertainty. It never gives a single number for symmetry or suggests any surgical action.",
        "Everything stays on this phone. Use only the study code, never a name.",
    ]

    private let steps = ["Take photos", "Mark points", "See left and right", "Export"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("Research use only")
                    .font(.screenTitle)

                Text("Research prototype. Not a medical device.")
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    ForEach(bullets, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                            Text("\u{2022}")
                            Text(line)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.body)
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("How it works")
                        .font(.sectionTitle)
                    StepRail(staticTitles: steps)
                }

                Text("Left and right always mean the patient's left and right.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Spacing.margin)
        }
        .background(Theme.Colors.tray)
        .foregroundStyle(Theme.Colors.ink)
        .safeAreaInset(edge: .bottom) {
            Button("I understand, start") { settings.researchNoticeAccepted = true }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Theme.Spacing.margin)
                .padding(.vertical, Theme.Spacing.m)
                .background(Theme.Colors.tray)
        }
    }
}

/// Compact banner for screens that show numbers, with a link to the explainer.
struct ResearchNoticeBanner: View {
    var showsExplainerLink: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Image(systemName: "info.circle")
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Research prototype. Not a medical device.")
                        .fontWeight(.semibold)
                    Text("Not clinically validated. Values are image geometry, not physical measurements.")
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .font(.support)
            .foregroundStyle(Theme.Colors.graduation)
            .accessibilityElement(children: .combine)
            if showsExplainerLink {
                NavigationLink {
                    MetricExplainerSheet()
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("What the numbers mean")
                        Image(systemName: "chevron.right")
                    }
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                    .tapTarget()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
