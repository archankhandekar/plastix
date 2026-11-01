import SwiftUI
import SymmetryCore

/// Analysis settings and the data actions. Nothing here needs changing to use the app; every
/// row says what it does in plain words and shows when it sits at its default. Flat rows on
/// the tray, separated by space, with Drape tint.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var stores: SessionStores
    @State private var confirmDeleteAll = false
    @State private var confirmResetPractice = false
    @State private var dataMessage: String?
    @State private var dataMessageCount = 0
    @State private var restored = false
    @State private var restoreCount = 0

    private let qualityDefaults = QualityThresholds()

    var body: some View {
        Form {
            Section {
                GuidanceCard(kind: .info, body: "You do not need to change anything here to use the app.")
                    .listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.margin, bottom: 0, trailing: Theme.Spacing.margin))
            }
            .flatRows()

            Section {
                slider("Point placement wobble", value: $settings.landmarkSigmaRatio, range: 0.005...0.05, step: 0.005,
                       format: "%.3f L", defaultValue: FrontalMetricsCalculator.defaultLandmarkSigmaRatio)
            } header: {
                header("Uncertainty")
            } footer: {
                footer("How much a hand-placed point is assumed to wobble, as a share of L. This drives the ± on every point-based value; Contour overlap uses a fixed grid ±.")
            }
            .flatRows()

            Section {
                slider("Minimum sharpness", value: $settings.minBlurScore, range: 0...400, step: 10,
                       format: "%.0f", defaultValue: qualityDefaults.minBlurScore)
                slider("Maximum too-bright or too-dark share", value: $settings.maxClippedFraction, range: 0...0.3, step: 0.01,
                       format: "%.2f", defaultValue: qualityDefaults.maxClippedFraction)
                slider("Maximum phone tilt", value: $settings.maxTiltDegrees, range: 0...30, step: 1,
                       format: "%.0f°", defaultValue: qualityDefaults.maxTiltDegrees)
            } header: {
                header("Photo checks")
            } footer: {
                footer("Starting guesses. Tune them on the first real photos.")
            }
            .flatRows()

            Section {
                slider("Maximum alignment mismatch", value: $settings.maxResidualRatio, range: 0.01...0.2, step: 0.01,
                       format: "%.2f L", defaultValue: Registration.defaultMaxResidualRatio)
                Toggle(isOn: $settings.ghostOverlayEnabled) {
                    Text("Match pose: show the earlier photo faintly in the camera")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(Theme.Colors.drape)
                .frame(minHeight: Theme.tapTarget)
            } header: {
                header("Comparison and camera")
            }
            .flatRows()

            Section {
                Button {
                    settings.restoreDefaults()
                    restored = true
                    restoreCount += 1
                } label: {
                    rowLabel("Restore defaults")
                }
                if restored {
                    Text("Defaults restored")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.drape)
                        .task(id: restoreCount) {
                            try? await Task.sleep(for: .seconds(2))
                            restored = false
                        }
                }
            }
            .flatRows()

            Section {
                Button {
                    confirmResetPractice = true
                } label: {
                    rowLabel("Reset the virtual patient")
                }
                Button {
                    confirmDeleteAll = true
                } label: {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "trash")
                            .accessibilityHidden(true)
                        Text("Delete all sessions and images")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                    .frame(maxWidth: .infinity, minHeight: Theme.tapTarget, alignment: .leading)
                    .contentShape(Rectangle())
                }
                if let dataMessage {
                    Text(dataMessage)
                        .font(.body)
                        .foregroundStyle(Theme.Colors.drape)
                        .fixedSize(horizontal: false, vertical: true)
                        .task(id: dataMessageCount) {
                            try? await Task.sleep(for: .seconds(3))
                            self.dataMessage = nil
                        }
                }
            } header: {
                header("Data")
            } footer: {
                footer("Sessions are stored only on this device, under iOS complete file protection, and are excluded from backups. The virtual patient is kept apart from study sessions.")
            }
            .flatRows()

            Section {
                NavigationLink {
                    MetricExplainerSheet()
                } label: {
                    rowLabel("What the numbers mean")
                }
                NavigationLink {
                    DefinitionsView()
                } label: {
                    rowLabel("Measurement definitions and limitations")
                }
            } header: {
                header("About")
            } footer: {
                footer("Research prototype, version 0.1. No network access. Not a medical device.")
            }
            .flatRows()
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.tray)
        .tint(Theme.Colors.drape)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Start the virtual patient again from the beginning?",
                            isPresented: $confirmResetPractice, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { resetPractice() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete every session and photo on this phone, including the virtual patient?",
                            isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                stores.deleteAllData()
                showDataMessage("Every session and photo was deleted.")
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Actions

    private func resetPractice() {
        do {
            try stores.practice.reset()
            showDataMessage("The virtual patient starts again from the beginning.")
        } catch {
            showDataMessage("Could not reset the virtual patient on this phone.")
        }
    }

    private func showDataMessage(_ text: String) {
        dataMessage = text
        dataMessageCount += 1
    }

    // MARK: - Pieces

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.support)
            .foregroundStyle(Theme.Colors.graduation)
            .textCase(nil)
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(.support)
            .foregroundStyle(Theme.Colors.graduation)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func rowLabel(_ title: String) -> some View {
        Text(title)
            .font(.body)
            .foregroundStyle(Theme.Colors.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: Theme.tapTarget, alignment: .leading)
            .contentShape(Rectangle())
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                        format: String, defaultValue: Double) -> some View {
        let isDefault = abs(value.wrappedValue - defaultValue) < 1e-9
        let valueText = String(format: format, value.wrappedValue) + (isDefault ? " (default)" : "")
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(valueText)
                    .font(.readoutRow)
                    .foregroundStyle(Theme.Colors.graduation)
            }
            Slider(value: value, in: range, step: step) { Text(title) }
                .tint(Theme.Colors.drape)
        }
        .frame(minHeight: Theme.tapTarget)
    }
}

private extension View {
    /// Settings rows sit straight on the tray: no grouped card behind them and no separators.
    func flatRows() -> some View {
        listRowBackground(Theme.Colors.tray)
            .listRowSeparator(.hidden)
    }
}
