import SwiftUI
import SymmetryCore
import SymmetryModels
import UIKit

/// Step 4: builds a de-identified report and hands it to the system share sheet. Nothing
/// leaves the phone any other way.
struct ExportView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    let sessionID: UUID

    @State private var includeImages = false
    @State private var exportURLs: [URL] = []
    @State private var errorText: String?
    @State private var isWorking = false

    private var session: StudySession? { store.session(id: sessionID) }

    var body: some View {
        if let session {
            let report = ReportBuilder.report(for: session, settings: settings.reportSettings)
            let progress = SessionProgress(session: session, settings: settings.reportSettings,
                                           hasCompared: ComparedFlag.isSet(sessionID: sessionID))
            let photoCount = session.orderedCaptureSets.reduce(0) { $0 + $1.orderedCaptures.count }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    summaryCard(session: session, report: report, progress: progress)
                    stepsCard(photoCount: photoCount)
                    if !exportURLs.isEmpty {
                        shareCard
                    }
                    if let errorText {
                        GuidanceCard(kind: .unreliable, title: "Could not prepare the files", body: errorText)
                    }
                    ResearchNoticeBanner()
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Colors.paper)
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { bottomBar }
        } else {
            ContentUnavailableView("Session not found", systemImage: "questionmark.folder")
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private func summaryCard(session: StudySession, report: ResearchReport, progress: SessionProgress) -> some View {
        let sets = report.captureSets.count
        let measured = progress.measuredSets.count
        let comparisons = report.comparisons.count
        let sigma = settings.landmarkSigmaRatio
        let gapLines = session.orderedCaptureSets.enumerated().flatMap { offset, set in
            CaptureSetStatus(set: set, index: offset + 1, sigma: sigma).gapLines
        }
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("This report will contain: \(sets) photo set\(sets == 1 ? "" : "s"), \(measured) measured frontal photo\(measured == 1 ? "" : "s"), \(comparisons) comparison\(comparisons == 1 ? "" : "s"). No names. Photos are left out unless you include them.")
                .font(.body)
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
            if progress.measuredSets.isEmpty {
                GuidanceCard(kind: .caution,
                             body: "This session has no measured set yet. You can still export, but the report will hold no measurements.")
            }
            if !gapLines.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(gapLines, id: \.self) { line in
                        Text(line)
                            .font(.body)
                            .foregroundStyle(Theme.Colors.caution)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .cardStyle()
    }

    private func stepsCard(photoCount: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Toggle(isOn: $settings.exportPrivacyAcknowledged) {
                    Text("1  Confirm the ethics (IRB) review covers moving data off this phone")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(Theme.Colors.accent)
                .frame(minHeight: Theme.tapTarget)
                Text("Export is available only after the study's privacy, security and ethics review covers moving data off this device. This is recorded on the phone, not in the report.")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Toggle(isOn: $includeImages) {
                    Text("2  Include photos with the points drawn on them (optional, \(photoCount) photos)")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(Theme.Colors.accent)
                .frame(minHeight: Theme.tapTarget)
                Text("The report holds the study code, stage labels, point positions, photo checks and measurements. Photos may be identifying, so they are left out unless you turn this on.")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Text("3  Prepare and share")
                .font(.body)
                .foregroundStyle(Theme.Colors.ink)
                .frame(maxWidth: .infinity, minHeight: Theme.tapTarget, alignment: .leading)
        }
        .cardStyle()
    }

    private var shareTitle: String {
        let n = exportURLs.count
        return n == 2 ? "Share 2 files (report and definitions)" : "Share \(n) files (report, definitions and \(n - 2) photos)"
    }

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ShareLink(items: exportURLs) {
                Text(shareTitle)
            }
            .buttonStyle(SecondaryButtonStyle())
            Text("The share sheet is the only way data leaves this phone. The files are replaced the next time you prepare an export.")
                .font(.body)
                .foregroundStyle(Theme.Colors.slate)
                .fixedSize(horizontal: false, vertical: true)
            Text("Done. You can go back to Sessions.")
                .font(.body)
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private var bottomBar: some View {
        let blocked = !settings.exportPrivacyAcknowledged || isWorking
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if !settings.exportPrivacyAcknowledged {
                Text("Confirm step 1 first")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.caution)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(isWorking ? "Preparing…" : "Prepare the files", action: prepare)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(blocked)
                .opacity(blocked ? 0.5 : 1)
        }
        .padding(Theme.Spacing.m)
        .background(.bar)
    }

    // MARK: - Preparing the files

    private func prepare() {
        guard let session = store.session(id: sessionID) else { return }
        isWorking = true
        errorText = nil
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
                errorText = error.localizedDescription
            }
            isWorking = false
        }
    }
}
