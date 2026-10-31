import SwiftUI
import SymmetryCore

/// Analysis settings. Nothing here needs changing to use the app; every row says what
/// it does in plain words and shows when it sits at its default.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: SessionStore
    @State private var confirmDeleteAll = false
    @State private var restored = false
    @State private var restoreCount = 0

    private let qualityDefaults = QualityThresholds()

    var body: some View {
        Form {
            Section {
                GuidanceCard(kind: .info, body: "You do not need to change anything here to use the app.")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                slider("Point placement wobble", value: $settings.landmarkSigmaRatio, range: 0.005...0.05, step: 0.005,
                       format: "%.3f L", defaultValue: FrontalMetricsCalculator.defaultLandmarkSigmaRatio)
            } header: {
                header("Uncertainty")
            } footer: {
                footer("How much a hand-placed point is assumed to wobble, as a share of L. This drives the ± on every point-based value; Contour overlap uses a fixed grid ±.")
            }

            Section {
                slider("Minimum sharpness", value: $settings.minBlurScore, range: 0...400, step: 10,
                       format: "%.0f", defaultValue: qualityDefaults.minBlurScore)
                slider("Maximum too-bright or too-dark share", value: $settings.maxClippedFraction, range: 0...0.3, step: 0.01,
                       format: "%.2f", defaultValue: qualityDefaults.maxClippedFraction)
                slider("Maximum phone tilt", value: $settings.maxTiltDegrees, range: 0...30, step: 1,
                       format: "%.0f°", defaultValue: qualityDefaults.maxTiltDegrees)
            } header: {
                header("Quality gate")
            } footer: {
                footer("Starting guesses. Tune them on the first real captures.")
            }

            Section {
                slider("Maximum alignment mismatch", value: $settings.maxResidualRatio, range: 0.01...0.2, step: 0.01,
                       format: "%.2f L", defaultValue: Registration.defaultMaxResidualRatio)
                Toggle(isOn: $settings.ghostOverlayEnabled) {
                    Text("Match pose: show the earlier photo faintly in the camera")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(Theme.Colors.accent)
                .frame(minHeight: Theme.tapTarget)
            } header: {
                header("Comparison and capture")
            }

            Section {
                Button {
                    settings.restoreDefaults()
                    restored = true
                    restoreCount += 1
                } label: {
                    Text("Restore defaults")
                        .font(.body)
                        .frame(maxWidth: .infinity, minHeight: Theme.tapTarget, alignment: .leading)
                }
                if restored {
                    Text("Defaults restored")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.accent)
                        .task(id: restoreCount) {
                            try? await Task.sleep(for: .seconds(2))
                            restored = false
                        }
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmDeleteAll = true
                } label: {
                    Text("Delete all sessions and images")
                        .font(.body)
                        .frame(maxWidth: .infinity, minHeight: Theme.tapTarget, alignment: .leading)
                }
            } header: {
                header("Data")
            } footer: {
                footer("Sessions are stored only on this device, under iOS complete file protection, and are excluded from backups.")
            }

            Section {
                NavigationLink {
                    MetricExplainerSheet()
                } label: {
                    Text("What the numbers mean")
                        .font(.body)
                        .frame(maxWidth: .infinity, minHeight: Theme.tapTarget, alignment: .leading)
                }
                NavigationLink {
                    DefinitionsView()
                } label: {
                    Text("Measurement definitions and limitations")
                        .font(.body)
                        .frame(maxWidth: .infinity, minHeight: Theme.tapTarget, alignment: .leading)
                }
            } header: {
                header("About")
            } footer: {
                footer("Research prototype, version 0.1. No network access. Not a medical device.")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Delete every session and photo on this phone?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { store.deleteAll() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Pieces

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(Theme.Colors.slate)
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(Theme.Colors.slate)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                        format: String, defaultValue: Double) -> some View {
        let isDefault = abs(value.wrappedValue - defaultValue) < 1e-9
        let valueText = String(format: format, value.wrappedValue) + (isDefault ? " (default)" : "")
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(valueText)
                    .font(.metric)
                    .foregroundStyle(Theme.Colors.slate)
            }
            Slider(value: value, in: range, step: step) { Text(title) }
                .tint(Theme.Colors.accent)
        }
        .frame(minHeight: Theme.tapTarget)
    }
}
