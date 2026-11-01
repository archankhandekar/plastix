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

                sidesCallout

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
            }
            .padding(Theme.Spacing.margin)
        }
        .background(Theme.Colors.tray)
        .foregroundStyle(Theme.Colors.ink)
        .safeAreaInset(edge: .bottom) {
            NextActionBar(title: "I understand, start") { settings.researchNoticeAccepted = true }
        }
    }

    /// The bilateral convention, the line that matters most in this app: the sentence, then
    /// the two sides drawn the way every screen shows them, either side of the midline.
    private var sidesCallout: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Left and right always mean the patient's left and right.")
                .font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            PatientSidesKey()
                .padding(.vertical, Theme.Spacing.xs)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The two sides drawn the way every screen shows them: patient right in the screen-left
/// half and patient left in the screen-right half, either side of the midline axis.
struct PatientSidesKey: View {
    var body: some View {
        FacingColumns {
            sideLabel("Patient right", place: "Left of the screen", alignment: .leading)
        } patientLeft: {
            sideLabel("Patient left", place: "Right of the screen", alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Patient right is on the left of the screen and patient left on the right, as in a frontal photo.")
    }

    private func sideLabel(_ side: String, place: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(side)
                .font(.sideLabel)
                .foregroundStyle(Theme.Colors.ink)
            Text(place)
                .font(.support)
                .foregroundStyle(Theme.Colors.graduation)
        }
        .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
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
