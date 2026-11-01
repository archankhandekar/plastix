import SwiftUI
import SymmetryCore
import SymmetryModels
import UIKit

/// Step 3: an earlier set against a later one. The frontal photos get a registered point
/// overlay and stacked metric rows; oblique photos are shown side by side only.
/// All numbers come from `ReportBuilder.compareFrontal`, the same path the export uses.
struct ComparisonView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    let sessionID: UUID

    @State private var baselineID: UUID?
    @State private var currentID: UUID?
    @State private var route: CompareRoute?

    enum CompareRoute: Hashable, Identifiable {
        case export
        case markPoints(setID: UUID, captureID: UUID)

        var id: Self { self }
    }

    init(sessionID: UUID, earlierID: UUID? = nil, laterID: UUID? = nil) {
        self.sessionID = sessionID
        _baselineID = State(initialValue: earlierID)
        _currentID = State(initialValue: laterID)
    }

    private var session: StudySession? { store.session(id: sessionID) }
    private var candidates: [CaptureSet] { session?.orderedCaptureSets.filter { $0.frontal != nil } ?? [] }

    private func set(_ id: UUID?) -> CaptureSet? { id.flatMap { session?.captureSet(id: $0) } }

    private func index(_ set: CaptureSet, in session: StudySession) -> Int {
        SessionProgress.index(of: set, in: session)
    }

    private func label(_ set: CaptureSet, in session: StudySession) -> String {
        "Set \(index(set, in: session)) · \(set.stage.label)"
    }

    var body: some View {
        if let session {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    pickerCard(session: session)
                    content(session: session)
                    ResearchNoticeBanner()
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Colors.paper)
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let next = nextAction(session: session) {
                    NextActionBar(title: next.title) { route = next.route }
                }
            }
            .navigationDestination(item: $route) { route in
                switch route {
                case .export:
                    ExportView(sessionID: sessionID)
                case .markPoints(let setID, let captureID):
                    LandmarkEditorView(sessionID: sessionID, setID: setID, captureID: captureID)
                }
            }
            .onAppear { seedSelection(session: session) }
        } else {
            ContentUnavailableView("Session not found", systemImage: "questionmark.folder")
        }
    }

    /// Defaults to the first and last measured sets, then to the first and last sets with a
    /// frontal photo, and remembers that the Compare step was opened.
    private func seedSelection(session: StudySession) {
        let progress = SessionProgress(session: session, settings: settings.reportSettings,
                                       hasCompared: ComparedFlag.isSet(sessionID: sessionID))
        let measured = progress.measuredSets
        let needsSeed = baselineID == nil || currentID == nil
        if baselineID == nil { baselineID = measured.first?.id ?? candidates.first?.id }
        if currentID == nil { currentID = measured.last?.id ?? candidates.last?.id }
        if needsSeed, baselineID == currentID, candidates.count >= 2 {
            baselineID = candidates.first?.id
            currentID = candidates.last?.id
        }
        ComparedFlag.mark(sessionID: sessionID)
    }

    // MARK: - Set choice

    @ViewBuilder
    private func pickerCard(session: StudySession) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if let b = set(baselineID), let c = set(currentID) {
                Text("Comparing set \(index(b, in: session)) (\(b.stage.label)) with set \(index(c, in: session)) (\(c.stage.label)).")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            setMenu("Earlier set", selection: $baselineID, session: session)
            setMenu("Later set", selection: $currentID, session: session)
        }
        .cardStyle()
    }

    private func setMenu(_ title: String, selection: Binding<UUID?>, session: StudySession) -> some View {
        Menu {
            ForEach(candidates) { s in
                Button(label(s, in: session)) { selection.wrappedValue = s.id }
            }
        } label: {
            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.slate)
                    Text(set(selection.wrappedValue).map { label($0, in: session) } ?? "Choose a set")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.slate)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .frame(maxWidth: .infinity, minHeight: Theme.tapTarget, alignment: .leading)
            .contentShape(Rectangle())
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.Colors.hairline))
        }
        .accessibilityLabel(title)
        .accessibilityValue(set(selection.wrappedValue).map { label($0, in: session) } ?? "Choose a set")
    }

    // MARK: - Readiness

    /// The chosen pair when it is two different sets, else nil.
    private func chosenPair() -> (baseline: CaptureSet, current: CaptureSet)? {
        guard let b = set(baselineID), let c = set(currentID), b.id != c.id, candidates.count >= 2 else { return nil }
        return (b, c)
    }

    /// The comparison for the chosen pair when both frontal photos have all 6 points.
    private func readyComparison(baseline b: CaptureSet, current c: CaptureSet) -> CaptureComparison? {
        let bothMarked = (b.frontal?.landmarks?.isComplete ?? false) && (c.frontal?.landmarks?.isComplete ?? false)
        guard bothMarked else { return nil }
        return ReportBuilder.compareFrontal(baseline: b, current: c, settings: settings.reportSettings)
    }

    /// The first set of the chosen pair (later set first) whose frontal photo is short of
    /// 6 points, with its status: the single place to send the user when not ready.
    private func pointsTarget(session: StudySession, baseline b: CaptureSet, current c: CaptureSet)
        -> (status: CaptureSetStatus, set: CaptureSet, frontal: Capture)? {
        let sigma = settings.landmarkSigmaRatio
        let sets = [c, b]
        let statuses = sets.map { CaptureSetStatus(set: $0, index: index($0, in: session), sigma: sigma) }
        guard let position = statuses.firstIndex(where: { $0.pointsMarked < LandmarkType.allCases.count }),
              let frontal = sets[position].frontal else { return nil }
        return (statuses[position], sets[position], frontal)
    }

    /// What the sticky bar offers: export when the comparison is ready, marking points when
    /// one set of the pair is short of them, nothing when there is no single target.
    private func nextAction(session: StudySession) -> (title: String, route: CompareRoute)? {
        guard let pair = chosenPair() else { return nil }
        if readyComparison(baseline: pair.baseline, current: pair.current) != nil {
            return ("Next: Export the report", .export)
        }
        guard let target = pointsTarget(session: session, baseline: pair.baseline, current: pair.current) else { return nil }
        return ("Next: Mark points on set \(target.status.index)",
                .markPoints(setID: target.set.id, captureID: target.frontal.id))
    }

    @ViewBuilder
    private func content(session: StudySession) -> some View {
        if let pair = chosenPair() {
            if let comparison = readyComparison(baseline: pair.baseline, current: pair.current) {
                readyContent(session: session, baseline: pair.baseline, current: pair.current, comparison: comparison)
            } else {
                notReadyContent(session: session, baseline: pair.baseline, current: pair.current)
            }
        } else {
            GuidanceCard(kind: .caution,
                         body: "You need two different sets that both have a frontal photo with all 6 points marked.")
        }
    }

    @ViewBuilder
    private func notReadyContent(session: StudySession, baseline b: CaptureSet, current c: CaptureSet) -> some View {
        if let target = pointsTarget(session: session, baseline: b, current: c) {
            let status = target.status
            let text = status.pointsMarked == 0
                ? "Set \(status.index) has no points on its frontal photo yet."
                : "Set \(status.index) has \(status.pointsMarked) of 6 points on its frontal photo."
            GuidanceCard(kind: .caution, body: text) {
                Button("Mark points on set \(status.index)") {
                    route = .markPoints(setID: target.set.id, captureID: target.frontal.id)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        } else {
            GuidanceCard(kind: .caution,
                         body: "You need two different sets that both have a frontal photo with all 6 points marked.")
        }
    }

    // MARK: - Ready

    @ViewBuilder
    private func readyContent(session: StudySession, baseline b: CaptureSet, current c: CaptureSet,
                              comparison: CaptureComparison) -> some View {
        let i = index(b, in: session)
        let j = index(c, in: session)

        HowToReadCard()

        frontalCard(session: session, baseline: b, current: c, comparison: comparison, i: i, j: j)

        ForEach([ViewAngle.leftOblique, .rightOblique]) { angle in
            if b.captures[angle] != nil || c.captures[angle] != nil {
                ObliqueCompareCard(session: session, angle: angle,
                                   earlier: b.captures[angle], later: c.captures[angle], i: i, j: j)
            }
        }
    }

    @ViewBuilder
    private func frontalCard(session: StudySession, baseline b: CaptureSet, current c: CaptureSet,
                             comparison: CaptureComparison, i: Int, j: Int) -> some View {
        let reg = comparison.registration
        let dimmed = !(reg?.isReliable ?? false)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Frontal")
                .font(.stepTitle)
                .foregroundStyle(Theme.Colors.ink)

            if let reg {
                if reg.isReliable {
                    Text("The two frontal photos lined up: the average mismatch over \(reg.sharedLandmarkCount) points is within the limit.")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("The two frontal photos did not line up. The numbers below are shown faded. Re-check the sternal notch and midline bottom on both frontal photos, then come back.")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.unreliable)
                        .fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup {
                    Text("These are fit diagnostics, not measurements, so they have no ±.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.slate)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Spacing.s)
                    Text(String(format: "Average mismatch %.3f L over %d points (limit %.2f L). Scale %.2f, rotation %.1f°.",
                                reg.rmsResidualRatio, reg.sharedLandmarkCount, reg.maxResidualRatio,
                                reg.transform.scale, reg.transform.rotation * 180 / .pi))
                        .font(.metric)
                        .foregroundStyle(reg.isReliable ? Theme.Colors.slate : Theme.Colors.unreliable)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Spacing.s)
                } label: {
                    Text("Show alignment details")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .tapTarget()
                }
            } else {
                Text("The two frontal photos did not line up. The numbers below are shown faded. Re-check the sternal notch and midline bottom on both frontal photos, then come back.")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.unreliable)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let bf = b.frontal, let bl = bf.landmarks, let image = store.image(for: bf, in: session) {
                LandmarkOverlayImage(image: image, baseline: bl, current: c.frontal?.landmarks,
                                     transform: reg?.transform, dimmed: dimmed)
                    .frame(maxHeight: 360)
                Text("Filled grey = set \(i) points. Hollow teal = set \(j) points moved onto the set \(i) photo.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.slate)
                    .fixedSize(horizontal: false, vertical: true)
                if dimmed {
                    Text("Faded because the photos did not line up.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.unreliable)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            let differing = differingPositioningFields(b.positioning, c.positioning)
            if !differing.isEmpty {
                GuidanceCard(kind: .caution,
                             body: "Positioning differs between these sets (\(differing.joined(separator: ", "))). Differences may come from posture, not anatomy.")
            }

            let hasContours = [b.frontal?.landmarks, c.frontal?.landmarks].allSatisfy { set in
                guard let set else { return false }
                return !set.leftContour.isEmpty && !set.rightContour.isEmpty
            }
            let missing = LandmarkType.allCases.filter { type in
                (b.frontal?.landmarks?.missing.contains(type) ?? true) || (c.frontal?.landmarks?.missing.contains(type) ?? true)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(comparison.deltas, id: \.name) { delta in
                    MetricDeltaRow(delta: delta,
                                   columnTitles: ("Set \(i)", "Set \(j)", "Change"),
                                   explanation: MetricGlossary.meaning(for: delta.name),
                                   reason: deltaReason(delta, comparison: comparison, missing: missing, hasContours: hasContours),
                                   dimmed: dimmed)
                }
            }

            Text(MetricGlossary.changeLine(earlier: i, later: j))
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.slate)
                .fixedSize(horizontal: false, vertical: true)

            FlagList(flags: comparison.flags)
        }
        .cardStyle()
    }

    /// Why a change is "Not measured". Contour overlap gets its own reason when outlines
    /// exist on only one of the two sets, so the reason never contradicts a value above it.
    private func deltaReason(_ delta: MetricDelta, comparison: CaptureComparison,
                             missing: [LandmarkType], hasContours: Bool) -> String? {
        if delta.name == "Contour overlap", (delta.baseline == nil) != (delta.current == nil) {
            return "Outlines were drawn on only one set, so no change is defined. This one is optional."
        }
        return MetricGlossary.reason(flags: comparison.flags, missing: missing,
                                     hasContours: hasContours, metricName: delta.name)
    }

    /// Names of the positioning fields that differ, in field order.
    private func differingPositioningFields(_ a: Positioning, _ b: Positioning) -> [String] {
        var names: [String] = []
        if a.tableAngle != b.tableAngle { names.append("table angle") }
        if a.armPosition != b.armPosition { names.append("arm position") }
        if a.lighting != b.lighting { names.append("lighting") }
        if a.note != b.note { names.append("note") }
        return names
    }
}

/// One oblique angle, two photos side by side. Looking only: no number is defined because
/// both sides are never in one oblique photo.
struct ObliqueCompareCard: View {
    @EnvironmentObject private var store: SessionStore
    let session: StudySession
    let angle: ViewAngle
    let earlier: Capture?
    let later: Capture?
    let i: Int
    let j: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("\(angle.displayName) (look, no numbers)")
                .font(.stepTitle)
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                pane("Set \(i)", earlier)
                pane("Set \(j)", later)
            }
            Text("Oblique photos are for looking only. Both sides are never in one oblique photo, so no number is defined.")
                .font(.body)
                .foregroundStyle(Theme.Colors.slate)
                .fixedSize(horizontal: false, vertical: true)
            FlagList(flags: unique((earlier?.reliabilityFlags ?? []) + (later?.reliabilityFlags ?? [])))
        }
        .cardStyle()
    }

    @ViewBuilder
    private func pane(_ title: String, _ capture: Capture?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.slate)
            if let capture, let image = store.image(for: capture, in: session) {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                let warning = capture.quality.map { !$0.passed } ?? false
                Text(QualityAdvice.headline(report: capture.quality, overridden: capture.qualityOverridden))
                    .font(.subheadline)
                    .foregroundStyle(warning ? Theme.Colors.caution : Theme.Colors.slate)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Theme.Colors.hairline.frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(Text("Not taken").font(.subheadline).foregroundStyle(Theme.Colors.slate))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func unique(_ flags: [ReliabilityFlag]) -> [ReliabilityFlag] {
        var out: [ReliabilityFlag] = []
        for f in flags where !out.contains(f) { out.append(f) }
        return out
    }
}

/// An image with two landmark sets drawn in its pixel space: the earlier set filled in
/// slate grey, the later set hollow in the guide colour after registration.
struct LandmarkOverlayImage: View {
    let image: UIImage
    let baseline: LandmarkSet
    let current: LandmarkSet?
    let transform: SimilarityTransform?
    let dimmed: Bool

    private let earlierColor = Theme.Colors.slate
    private let laterColor = Theme.Colors.guide

    var body: some View {
        GeometryReader { geo in
            let fit = fitRect(in: geo.size)
            ZStack {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                Canvas { ctx, _ in
                    draw(ctx, set: baseline, transform: nil, filled: true, fit: fit)
                    if let current, let transform {
                        draw(ctx, set: current, transform: transform, filled: false, fit: fit)
                    }
                }
                .opacity(dimmed ? 0.6 : 1)
            }
        }
        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
    }

    private func fitRect(in size: CGSize) -> CGRect {
        let scale = min(size.width / image.size.width, size.height / image.size.height)
        let w = image.size.width * scale, h = image.size.height * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func toView(_ p: Point2D, fit: CGRect) -> CGPoint {
        CGPoint(x: fit.minX + CGFloat(p.x) * fit.width / image.size.width,
                y: fit.minY + CGFloat(p.y) * fit.height / image.size.height)
    }

    private func draw(_ ctx: GraphicsContext, set: LandmarkSet, transform: SimilarityTransform?, filled: Bool, fit: CGRect) {
        func map(_ p: Point2D) -> CGPoint { toView(transform?.apply(p) ?? p, fit: fit) }
        let color = filled ? earlierColor : laterColor
        for contour in [set.leftContour, set.rightContour] where contour.count > 1 {
            var path = Path()
            path.move(to: map(contour[0]))
            for p in contour.dropFirst() { path.addLine(to: map(p)) }
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, dash: filled ? [] : [4, 3]))
        }
        for (_, p) in set.points {
            let v = map(p)
            let r: CGFloat = filled ? 5 : 7
            let rect = CGRect(x: v.x - r, y: v.y - r, width: 2 * r, height: 2 * r)
            if filled {
                ctx.fill(Path(ellipseIn: rect), with: .color(color))
            } else {
                ctx.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 2)
            }
        }
    }
}
