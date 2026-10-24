import SwiftUI
import SymmetryCore

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: SessionStore
    @State private var confirmDeleteAll = false

    var body: some View {
        Form {
            Section {
                slider("Landmark placement sigma", value: $settings.landmarkSigmaRatio, range: 0.005...0.05, step: 0.005, format: "%.3f L")
                Text("Assumed standard deviation of each hand-placed landmark, as a fraction of the reference length. Drives every ± value. Replace with the repeated-placement study result when available.")
                    .font(.footnote).foregroundStyle(Theme.Colors.slate)
            } header: { Text("Uncertainty") }

            Section {
                slider("Minimum blur score", value: $settings.minBlurScore, range: 0...400, step: 10, format: "%.0f")
                slider("Maximum clipped fraction", value: $settings.maxClippedFraction, range: 0...0.3, step: 0.01, format: "%.2f")
                slider("Maximum phone roll", value: $settings.maxTiltDegrees, range: 0...30, step: 1, format: "%.0f°")
                Text("Starting guesses. Tune them on the first real captures.")
                    .font(.footnote).foregroundStyle(Theme.Colors.slate)
            } header: { Text("Quality gate") }

            Section {
                slider("Maximum registration residual", value: $settings.maxResidualRatio, range: 0.01...0.2, step: 0.01, format: "%.2f L")
                Toggle("Ghost overlay of prior capture", isOn: $settings.ghostOverlayEnabled)
            } header: { Text("Comparison and capture") }

            Section {
                Button("Restore defaults") { settings.restoreDefaults() }
            }

            Section {
                Button("Delete all sessions and images", role: .destructive) { confirmDeleteAll = true }
                Text("Sessions are stored only on this device, under iOS complete file protection, and are excluded from backups.")
                    .font(.footnote).foregroundStyle(Theme.Colors.slate)
            } header: { Text("Data") }

            Section {
                NavigationLink("Measurement definitions and limitations") {
                    ScrollView {
                        Text(definitionsText)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.Spacing.m)
                    }
                    .navigationTitle("Definitions")
                    .navigationBarTitleDisplayMode(.inline)
                }
                Text("Research prototype, version 0.1. No network access. Not a medical device.")
                    .font(.footnote).foregroundStyle(Theme.Colors.slate)
            } header: { Text("About") }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Delete every session and image on this device?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { store.deleteAll() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var definitionsText: AttributedString {
        (try? AttributedString(markdown: MeasurementDefinitions.markdown,
                               options: .init(interpretedSyntax: .full)))
            ?? AttributedString(MeasurementDefinitions.markdown)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue)).font(.metric).foregroundStyle(Theme.Colors.slate)
            }
            Slider(value: value, in: range, step: step) { Text(title) }
        }
    }
}
