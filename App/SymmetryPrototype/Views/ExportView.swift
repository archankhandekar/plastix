import SwiftUI
import SymmetryCore
import SymmetryModels
import UIKit

/// Builds a de-identified report and hands it to the system share sheet. Nothing leaves
/// the device any other way.
struct ExportView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    let sessionID: UUID

    @State private var includeImages = false
    @State private var exportURLs: [URL] = []
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        Form {
            Section {
                Toggle("Privacy and IRB review completed", isOn: $settings.exportPrivacyAcknowledged)
                Text("Export is available only after the study's privacy, security and ethics review covers moving data off this device. This acknowledgment is recorded on the device, not in the report.")
                    .font(.footnote).foregroundStyle(Theme.Colors.slate)
            } header: { Text("Before exporting") }

            Section {
                Toggle("Include annotated images", isOn: $includeImages)
                Text("The JSON report holds the study ID, stage labels, landmark coordinates, quality results and metrics. Images are intraoperative photographs and may be identifying; they are left out unless you turn this on.")
                    .font(.footnote).foregroundStyle(Theme.Colors.slate)
            } header: { Text("Contents") }

            Section {
                Button(isWorking ? "Preparing…" : "Prepare export", action: prepare)
                    .disabled(!settings.exportPrivacyAcknowledged || isWorking)
                if !exportURLs.isEmpty {
                    ShareLink(items: exportURLs) {
                        Label("Share \(exportURLs.count) file\(exportURLs.count == 1 ? "" : "s")", systemImage: "square.and.arrow.up")
                    }
                    Text("The share sheet is the only way data leaves the device. Files are removed from the export folder when you prepare the next export.")
                        .font(.footnote).foregroundStyle(Theme.Colors.slate)
                }
                if let message { Text(message).font(.footnote).foregroundStyle(Theme.Colors.unreliable) }
            }

            Section { ResearchNoticeBanner() }
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func prepare() {
        guard let session = store.session(id: sessionID) else { return }
        isWorking = true
        message = nil
        exportURLs = []
        let report = ReportBuilder.report(for: session, settings: settings.reportSettings)
        // Images are loaded on the main actor; encoding and annotation run off it.
        struct ImageJob { let name: String; let image: UIImage; let landmarks: LandmarkSet? }
        var jobs: [ImageJob] = []
        if includeImages {
            for (index, set) in session.orderedCaptureSets.enumerated() {
                for capture in set.orderedCaptures {
                    guard let image = store.image(for: capture, in: session) else { continue }
                    jobs.append(ImageJob(name: "\(session.studyID)-set\(index + 1)-\(capture.angle.rawValue).jpg",
                                         image: image, landmarks: capture.landmarks))
                }
            }
        }
        let studyID = session.studyID
        Task {
            do {
                let urls = try await Task.detached(priority: .userInitiated) { () throws -> [URL] in
                    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
                    if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let stamp = ISO8601DateFormatter().string(from: report.generatedAt).replacingOccurrences(of: ":", with: "-")
                    var urls: [URL] = []
                    let jsonURL = dir.appendingPathComponent("\(studyID)-report-\(stamp).json")
                    try report.jsonData().write(to: jsonURL, options: [.atomic, .completeFileProtection])
                    urls.append(jsonURL)
                    let defsURL = dir.appendingPathComponent("measurement-definitions.md")
                    try Data(MeasurementDefinitions.markdown.utf8).write(to: defsURL, options: [.atomic, .completeFileProtection])
                    urls.append(defsURL)
                    for job in jobs {
                        let rendered = job.landmarks.map { ImageBridge.annotated(job.image, landmarks: $0) } ?? job.image
                        guard let data = rendered.jpegData(compressionQuality: 0.9) else { continue }
                        let url = dir.appendingPathComponent(job.name)
                        try data.write(to: url, options: [.atomic, .completeFileProtection])
                        urls.append(url)
                    }
                    return urls
                }.value
                exportURLs = urls
            } catch {
                message = "Could not prepare the export: \(error.localizedDescription)"
            }
            isWorking = false
        }
    }
}
