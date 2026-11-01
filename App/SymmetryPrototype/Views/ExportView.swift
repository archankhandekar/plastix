import SwiftUI
import SymmetryCore
import SymmetryModels
import UIKit

/// Export. A study session builds a de-identified report and hands it to the system share
/// sheet; nothing leaves the phone any other way. A practice session (or any DEMO- code) is
/// refused first, by `ExportEligibility`, and only gets a preview of what a report holds:
/// it has no prepare button and no share link.
struct ExportView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var navigator: AppNavigator
    @Environment(\.sessionKind) private var kind
    let sessionID: UUID

    @State private var includeImages = false
    @State private var exportURLs: [URL] = []
    @State private var errorText: String?
    @State private var isWorking = false
    @State private var previewExpanded = false

    private var session: StudySession? { store.session(id: sessionID) }

    private func eligibility(_ session: StudySession) -> ExportEligibility {
        ExportEligibility.check(kind: kind, studyID: session.studyID)
    }

    var body: some View {
        if let session {
            // The guard comes first: nothing below the refusal can reach the share path.
            switch eligibility(session) {
            case .practiceRefused:
                refusal(session: session)
            case .allowed:
                studyForm(session: session)
            }
        } else {
            ContentUnavailableView("Session not found", systemImage: "questionmark.folder")
        }
    }

    // MARK: - Practice: refusal and preview

    private func refusal(session: StudySession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Export")
                        .font(.screenTitle)
                        .foregroundStyle(Theme.Colors.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(ExportEligibility.refusalMessage)
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                DisclosureGroup(isExpanded: $previewExpanded) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        summary(session: session, preview: true)
                        Button("What the numbers mean") {
                            navigator.push(.explainer)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(.top, Theme.Spacing.s)
                } label: {
                    Text("Preview what a report contains")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.Colors.ink)
                        .tapTarget()
                }
                .tint(Theme.Colors.drape)

                ResearchNoticeBanner(showsExplainerLink: false)
            }
            .padding(Theme.Spacing.margin)
        }
        .background(Theme.Colors.tray)
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        // Refused data is always the virtual patient, whichever store it came from.
        .practiceBand(true)
    }

    // MARK: - Study: the three-step form

    private func studyForm(session: StudySession) -> some View {
        let photoCount = session.orderedCaptureSets.reduce(0) { $0 + $1.orderedCaptures.count }
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                summary(session: session, preview: false)
                steps(photoCount: photoCount)
                if !exportURLs.isEmpty {
                    shareSection
                }
                if let errorText {
                    GuidanceCard(kind: .unreliable, title: "Could not prepare the files", body: errorText)
                }
                ResearchNoticeBanner(showsExplainerLink: false)
            }
            .padding(Theme.Spacing.margin)
        }
        .background(Theme.Colors.tray)
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Summary (shared by the form and the preview)

    @ViewBuilder
    private func summary(session: StudySession, preview: Bool) -> some View {
        let report = ReportBuilder.report(for: session, settings: settings.reportSettings)
        let wizard = SessionWizard(session: session, settings: settings.reportSettings, kind: kind)
        let sets = report.captureSets.count
        let measured = wizard.measuredSets.count
        // The headline counts only comparisons between two measured sets, so it agrees with
        // the measured count and with session home. Comparisons that involve a set without
        // a measured frontal photo are still in the report, with blanks.
        let measuredIDs = Set(wizard.measuredSets.map(\.id))
        let blankComparisons = report.comparisons.filter {
            !measuredIDs.contains($0.baselineSetID) || !measuredIDs.contains($0.currentSetID)
        }
        let comparisons = report.comparisons.count - blankComparisons.count
        let orderedIDs = session.orderedCaptureSets.map(\.id)
        let unmeasuredIndices = Set(blankComparisons
            .flatMap { [$0.baselineSetID, $0.currentSetID] }
            .filter { !measuredIDs.contains($0) }
            .compactMap { id in orderedIDs.firstIndex(of: id).map { $0 + 1 } }).sorted()
        let sigma = settings.landmarkSigmaRatio
        let gapLines = session.orderedCaptureSets.enumerated().flatMap { offset, set in
            SetStatus(set: set, index: offset + 1, sigma: sigma).gapLines
        }
        let counts = "\(sets) photo set\(sets == 1 ? "" : "s"), \(measured) measured set\(measured == 1 ? "" : "s"), \(comparisons) comparison\(comparisons == 1 ? "" : "s")."
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(preview
                 ? "A report from this session would contain: \(counts) No names. Photos are left out unless they are included."
                 : "This report will contain: \(counts) No names.")
                .font(.body)
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !blankComparisons.isEmpty {
                cautionLine(blankComparisonsLine(count: blankComparisons.count, setIndices: unmeasuredIndices))
            }
            if wizard.measuredSets.isEmpty {
                GuidanceCard(kind: .caution,
                             body: preview
                                 ? "This session has no measured set yet, so a report would hold no measurements."
                                 : "This session has no measured set yet. You can still export, but the report will hold no measurements.")
            }
            if !gapLines.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    ForEach(gapLines, id: \.self) { line in
                        cautionLine(line)
                    }
                }
            }
        }
    }

    private func cautionLine(_ text: String) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
                .accessibilityHidden(true)
        }
        .font(.body)
        .foregroundStyle(Theme.Colors.caution)
    }

    /// "1 comparison has blanks because set 3 is not measured." /
    /// "3 comparisons have blanks because sets 2 and 3 are not measured."
    private func blankComparisonsLine(count: Int, setIndices: [Int]) -> String {
        let comparisons = count == 1 ? "1 comparison has blanks" : "\(count) comparisons have blanks"
        let names = setIndices.map(String.init)
        let sets: String
        switch names.count {
        case 0: sets = "a set is not measured"
        case 1: sets = "set \(names[0]) is not measured"
        default: sets = "sets \(names.dropLast().joined(separator: ", ")) and \(names[names.count - 1]) are not measured"
        }
        return "\(comparisons) because \(sets)."
    }

    // MARK: - Steps

    private func steps(photoCount: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Toggle(isOn: $settings.exportPrivacyAcknowledged) {
                    Text("1  Confirm the ethics (IRB) review covers moving data off this phone")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(Theme.Colors.drape)
                .frame(minHeight: Theme.tapTarget)
                Text("Export is available only after the study's privacy, security and ethics review covers moving data off this device. This is recorded on the phone, not in the report.")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.graduation)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Toggle(isOn: $includeImages) {
                    Text("2  Include photos with the points drawn on them (optional, \(photoCount) photo\(photoCount == 1 ? "" : "s"))")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(Theme.Colors.drape)
                .frame(minHeight: Theme.tapTarget)
                Text("The report holds the study code, stage labels, point positions, photo checks and measurements. Photos may be identifying, so they are left out unless you turn this on.")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.graduation)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Step 3 holds its own action, in the scroll content beside the switch that
            // unblocks it, rather than in a bar pinned far below.
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("3  Prepare and share")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                prepareAction
            }
        }
    }

    private var shareTitle: String {
        let n = exportURLs.count
        let p = n - 2
        return n == 2 ? "Share 2 files (report and definitions)" : "Share \(n) files (report, definitions and \(p) photo\(p == 1 ? "" : "s"))"
    }

    @ViewBuilder
    private var shareSection: some View {
        // Reached only from the study form, which `body` shows only when export is allowed.
        if let session, eligibility(session) == .allowed {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ShareLink(items: exportURLs) {
                    Text(shareTitle)
                }
                .buttonStyle(SecondaryButtonStyle())
                Text("The share sheet is the only way data leaves this phone. The files are replaced the next time you prepare an export.")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.graduation)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Done. You can go back to Sessions.")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The one primary action. While it cannot run it is drawn as a legible outline (with a
    /// lock until step 1 is confirmed), never as a faded fill.
    @ViewBuilder
    private var prepareAction: some View {
        let acknowledged = settings.exportPrivacyAcknowledged
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if !acknowledged {
                Label {
                    Text("Confirm step 1 first")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .accessibilityHidden(true)
                }
                .font(.body)
                .foregroundStyle(Theme.Colors.caution)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if acknowledged && !isWorking {
                Button("Prepare the files", action: prepare)
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button(isWorking ? "Preparing…" : "Prepare the files", action: prepare)
                    .buttonStyle(BlockedPrimaryButtonStyle(showsLock: !acknowledged))
                    .disabled(true)
            }
        }
    }

    // MARK: - Preparing the files

    private func prepare() {
        guard let session = store.session(id: sessionID) else { return }
        // Practice data is never written out, whatever called this.
        guard eligibility(session) == .allowed else { return }
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

/// The primary action while it cannot run: the same 64pt shape with a clear fill, a 1.5pt
/// Graduation outline and a Graduation label, which stays legible on the tray in light and
/// dark (a faded Drape fill does not). An optional lock says the action waits on a step.
private struct BlockedPrimaryButtonStyle: ButtonStyle {
    let showsLock: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            if showsLock {
                Image(systemName: "lock")
                    .accessibilityHidden(true)
            }
            configuration.label
        }
        .font(.actionLabel)
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.Colors.graduation)
        .padding(.horizontal, Theme.Spacing.m)
        .frame(maxWidth: .infinity, minHeight: Theme.primaryHeight)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius)
            .strokeBorder(Theme.Colors.graduation, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}
