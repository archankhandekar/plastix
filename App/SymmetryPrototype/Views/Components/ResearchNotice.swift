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

    private let steps = [
        "Take 3 photos of the patient at one stage of the operation",
        "Mark 6 points on the frontal photo",
        "Repeat at a later stage and compare the two",
        "Export a report for the study",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("Research use only")
                    .font(.screenTitle)

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
                        .font(.stepTitle)
                    StepListView(staticTitles: steps)
                }

                Text("Left and right always mean the patient's left and right.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.Colors.paper)
        .foregroundStyle(Theme.Colors.ink)
        .safeAreaInset(edge: .bottom) {
            Button("I understand, start") { settings.researchNoticeAccepted = true }
                .buttonStyle(PrimaryButtonStyle())
                .padding(Theme.Spacing.m)
                .background(.bar)
        }
    }
}

/// Compact banner for screens that show numbers, with a link to the explainer.
struct ResearchNoticeBanner: View {
    var showsExplainerLink: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                Image(systemName: "info.circle")
                Text("Research prototype. Not clinically validated. Values are image geometry, not physical measurements.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.Colors.slate)
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
