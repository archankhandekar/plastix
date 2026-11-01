import SwiftUI
import SymmetryCore
import SymmetryModels
import UIKit

/// Compare two sets in detail: an earlier set against a later one. The frontal photos get a
/// registered point overlay and stacked metric rows with the change and its ±; oblique
/// photos are shown side by side only. Flat sections on the tray, photos on Plate.
/// All numbers come from `ReportBuilder.compareFrontal`, the same path the export uses.
struct ComparisonView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var navigator: AppNavigator
    @Environment(\.sessionKind) private var kind
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let sessionID: UUID

    @State private var baselineID: UUID?
    @State private var currentID: UUID?

    init(sessionID: UUID, earlierID: UUID? = nil, laterID: UUID? = nil) {
        self.sessionID = sessionID
        _baselineID = State(initialValue: earlierID)
        _currentID = State(initialValue: laterID)
    }

    private var session: StudySession? { store.session(id: sessionID) }
    private var ref: SessionRef { SessionRef(id: sessionID, kind: kind) }
    private var candidates: [CaptureSet] { session?.orderedCaptureSets.filter { $0.frontal != nil } ?? [] }

    private func set(_ id: UUID?) -> CaptureSet? { id.flatMap { session?.captureSet(id: $0) } }

    private func index(_ set: CaptureSet, in session: StudySession) -> Int {
        SessionWizard.index(of: set, in: session)
    }

    /// "Set 1, preoperative marking"
    private func label(_ set: CaptureSet, in session: StudySession) -> String {
        SessionWizard.title(of: set, in: session)
    }

    var body: some View {
        if let session {
            ScrollView {
                // The set choice sits close to the result it controls; result sections are
                // spaced apart from each other.
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    pickerSection(session: session)
                    VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                        content(session: session)
                        ResearchNoticeBanner(showsExplainerLink: false)
                    }
                }
                .padding(Theme.Spacing.margin)
            }
            .background(Theme.Colors.tray)
            .navigationTitle("Compare two sets in detail")
            .navigationBarTitleDisplayMode(.inline)
            .practiceBand(kind == .practice)
            .safeAreaInset(edge: .bottom) {
                if let next = nextAction(session: session) {
                    NextActionBar(title: next.title) { navigator.push(next.route) }
                }
            }
            .onAppear { seedSelection(session: session) }
        } else {
            ContentUnavailableView("Session not found", systemImage: "questionmark.folder")
        }
    }

    /// Defaults to the first and last measured sets, then to the first and last sets with a
    /// frontal photo.
    private func seedSelection(session: StudySession) {
        let wizard = SessionWizard(session: session, settings: settings.reportSettings, kind: kind)
        let measured = wizard.measuredSets
        let needsSeed = baselineID == nil || currentID == nil
        if baselineID == nil { baselineID = measured.first?.id ?? candidates.first?.id }
        if currentID == nil { currentID = measured.last?.id ?? candidates.last?.id }
        if needsSeed, baselineID == currentID, candidates.count >= 2 {
            baselineID = candidates.first?.id
            currentID = candidates.last?.id
        }
    }

    // MARK: - Set choice

    /// The two set menus, side by side at the default sizes (earlier on the left, like a
    /// timeline) and stacked at the larger sizes, where half the width would break words.
    @ViewBuilder
    private func pickerSection(session: StudySession) -> some View {
        let layout = dynamicTypeSize >= .xxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.s))
        layout {
            setMenu("Earlier set", selection: $baselineID, session: session)
            setMenu("Later set", selection: $currentID, session: session)
        }
        // Side by side, both outlines take the taller one's height.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A 56pt outlined menu holding the field name and the chosen set. The name gets the full
    /// width of the outline; the only other mark is a small up-down chevron by the field name.
    private func setMenu(_ title: String, selection: Binding<UUID?>, session: StudySession) -> some View {
        let chosen = set(selection.wrappedValue).map { label($0, in: session) } ?? "Choose a set"
        return Menu {
            ForEach(candidates) { s in
                Button(label(s, in: session)) { selection.wrappedValue = s.id }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(title)
                        .font(.support)
                        .foregroundStyle(Theme.Colors.graduation)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.support.weight(.semibold))
                        .foregroundStyle(Theme.Colors.drape)
                        .accessibilityHidden(true)
                }
                Text(chosen)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: .infinity, minHeight: Theme.tapTarget, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(Theme.Colors.graduation, lineWidth: 1.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(title)
        .accessibilityValue(chosen)
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
        -> (status: SetStatus, set: CaptureSet, frontal: Capture)? {
        let sigma = settings.landmarkSigmaRatio
        let sets = [c, b]
        let statuses = sets.map { SetStatus(set: $0, index: index($0, in: session), sigma: sigma) }
        guard let position = statuses.firstIndex(where: { $0.pointsMarked < LandmarkType.allCases.count }),
              let frontal = sets[position].frontal else { return nil }
        return (statuses[position], sets[position], frontal)
    }

    private func markPointsRoute(_ set: CaptureSet, _ frontal: Capture) -> AppRoute {
        .markPoints(ref, setID: set.id, captureID: frontal.id)
    }

    /// What the sticky bar offers: export when the comparison is ready, marking points when
    /// one set of the pair is short of them, nothing when there is no single target.
    private func nextAction(session: StudySession) -> (title: String, route: AppRoute)? {
        guard let pair = chosenPair() else { return nil }
        if readyComparison(baseline: pair.baseline, current: pair.current) != nil {
            // Practice sessions are never exported; their export screen is a preview.
            let title = kind == .practice ? "See what a report would contain" : "Export the report"
            return (title, .export(ref))
        }
        guard let gap = pointsTarget(session: session, baseline: pair.baseline, current: pair.current) else { return nil }
        let setNumber = gap.status.index
        return ("Mark the points on set \(setNumber)", markPointsRoute(gap.set, gap.frontal))
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
            // The one primary action is the bar below; this is its secondary twin in context.
            GuidanceCard(kind: .caution, body: text) {
                Button("Mark the points on set \(status.index)") {
                    navigator.push(markPointsRoute(target.set, target.frontal))
                }
                .buttonStyle(SecondaryButtonStyle())
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

        // The result comes first; how to read it follows the oblique photos.
        frontalSection(session: session, baseline: b, current: c, comparison: comparison, i: i, j: j)

        ForEach([ViewAngle.leftOblique, .rightOblique]) { angle in
            if b.captures[angle] != nil || c.captures[angle] != nil {
                ObliqueCompareCard(session: session, angle: angle,
                                   earlier: b.captures[angle], later: c.captures[angle], i: i, j: j)
            }
        }

        HowToReadCard()
    }

    private static let notLinedUp = "The two frontal photos did not line up. The numbers below are shown faded. Re-check the sternal notch and midline bottom on both frontal photos, then come back."

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

    @ViewBuilder
    private func frontalSection(session: StudySession, baseline b: CaptureSet, current c: CaptureSet,
                                comparison: CaptureComparison, i: Int, j: Int) -> some View {
        let reg = comparison.registration
        let dimmed = !(reg?.isReliable ?? false)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Frontal")
                .font(.sectionTitle)
                .foregroundStyle(Theme.Colors.ink)
                .accessibilityAddTraits(.isHeader)

            // A warning that changes how the numbers read comes before them.
            if !(reg?.isReliable ?? false) {
                cautionLine(Self.notLinedUp)
            }

            let differing = differingPositioningFields(b.positioning, c.positioning)
            if !differing.isEmpty {
                GuidanceCard(kind: .caution,
                             body: "Positioning differs between these sets (\(differing.joined(separator: ", "))). Differences may come from posture, not anatomy.")
            }

            // The change rows lead, so the first change with its ± is in the first screenful.
            let hasContours = [b.frontal?.landmarks, c.frontal?.landmarks].allSatisfy { set in
                guard let set else { return false }
                return !set.leftContour.isEmpty && !set.rightContour.isEmpty
            }
            let missing = LandmarkType.allCases.filter { type in
                (b.frontal?.landmarks?.missing.contains(type) ?? true) || (c.frontal?.landmarks?.missing.contains(type) ?? true)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                ForEach(comparison.deltas, id: \.name) { delta in
                    MetricDeltaRow(delta: delta,
                                   columnTitles: ("Set \(i)", "Set \(j)", "Change"),
                                   explanation: MetricGlossary.meaning(for: delta.name),
                                   reason: deltaReason(delta, comparison: comparison, missing: missing, hasContours: hasContours),
                                   dimmed: dimmed)
                }
            }

            Text(MetricGlossary.changeLine(earlier: i, later: j))
                .font(.support)
                .foregroundStyle(Theme.Colors.graduation)
                .fixedSize(horizontal: false, vertical: true)

            if let bf = b.frontal, let bl = bf.landmarks, let image = store.image(for: bf, in: session) {
                LandmarkOverlayImage(image: image, baseline: bl, current: c.frontal?.landmarks,
                                     transform: reg?.transform, dimmed: dimmed)
                    .frame(maxWidth: .infinity, maxHeight: 360)
                    .background(Theme.Colors.plate, in: RoundedRectangle(cornerRadius: Theme.photoRadius))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.photoRadius))
                    .padding(.top, Theme.Spacing.s)
                Text("Grey rings and dashed lines: set \(i) points and outlines. Violet dots and solid lines: set \(j) points and outlines, moved onto the set \(i) photo.")
                    .font(.support)
                    .foregroundStyle(Theme.Colors.graduation)
                    .fixedSize(horizontal: false, vertical: true)
                if dimmed {
                    Text("Faded because the photos did not line up.")
                        .font(.support)
                        .foregroundStyle(Theme.Colors.caution)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let reg {
                if reg.isReliable {
                    Text("The two frontal photos lined up: the average mismatch over \(reg.sharedLandmarkCount) points is within the limit.")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup {
                    Text("These are fit diagnostics, not measurements, so they have no ±.")
                        .font(.support)
                        .foregroundStyle(Theme.Colors.graduation)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Theme.Spacing.s)
                    Text(String(format: "Average mismatch %.3f L over %d points (limit %.2f L). Scale %.2f, rotation %.1f°.",
                                reg.rmsResidualRatio, reg.sharedLandmarkCount, reg.maxResidualRatio,
                                reg.transform.scale, reg.transform.rotation * 180 / .pi))
                        .font(.readoutRow)
                        .foregroundStyle(reg.isReliable ? Theme.Colors.graduation : Theme.Colors.caution)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Theme.Spacing.s)
                } label: {
                    Text("Show alignment details")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .tapTarget()
                }
                .tint(Theme.Colors.drape)
            }

            FlagList(flags: comparison.flags)
        }
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

/// One oblique angle, two photos side by side on Plate. Looking only: no number is defined
/// because both sides are never in one oblique photo.
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
                .font(.sectionTitle)
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                pane("Set \(i)", earlier)
                pane("Set \(j)", later)
            }
            Text("Oblique photos are for looking only. Both sides are never in one oblique photo, so no number is defined.")
                .font(.body)
                .foregroundStyle(Theme.Colors.graduation)
                .fixedSize(horizontal: false, vertical: true)
            FlagList(flags: unique((earlier?.reliabilityFlags ?? []) + (later?.reliabilityFlags ?? [])))
        }
    }

    @ViewBuilder
    private func pane(_ title: String, _ capture: Capture?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.support)
                .foregroundStyle(Theme.Colors.graduation)
            if let capture, let image = store.image(for: capture, in: session) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity)
                    .background(Theme.Colors.plate)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.photoRadius))
                let warning = capture.quality.map { !$0.passed } ?? false
                let headline = QualityAdvice.headline(report: capture.quality, overridden: capture.qualityOverridden)
                if warning {
                    Label {
                        Text(headline)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .accessibilityHidden(true)
                    }
                    .font(.support)
                    .foregroundStyle(Theme.Colors.caution)
                } else {
                    Text(headline)
                        .font(.support)
                        .foregroundStyle(Theme.Colors.graduation)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Theme.Colors.plate.frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.photoRadius))
                    .overlay(Text("Not taken").font(.support).foregroundStyle(Theme.Colors.plateGraduation))
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

/// An image with two landmark sets drawn in its pixel space: the earlier set as hollow
/// grey rings (Graduation on Plate), the later set as filled violet dots (Marker on Plate,
/// with a Plate halo) after registration onto the earlier photo.
struct LandmarkOverlayImage: View {
    let image: UIImage
    let baseline: LandmarkSet
    let current: LandmarkSet?
    let transform: SimilarityTransform?
    let dimmed: Bool

    private let earlierColor = Theme.Colors.plateGraduation
    private let laterColor = Theme.Colors.markerOnPlate
    private let haloColor = Theme.Colors.plate

    var body: some View {
        GeometryReader { geo in
            let fit = fitRect(in: geo.size)
            ZStack {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                Canvas { ctx, _ in
                    draw(ctx, set: baseline, transform: nil, isEarlier: true, fit: fit)
                    if let current, let transform {
                        draw(ctx, set: current, transform: transform, isEarlier: false, fit: fit)
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

    private func draw(_ ctx: GraphicsContext, set: LandmarkSet, transform: SimilarityTransform?, isEarlier: Bool, fit: CGRect) {
        func map(_ p: Point2D) -> CGPoint { toView(transform?.apply(p) ?? p, fit: fit) }
        let color = isEarlier ? earlierColor : laterColor
        for contour in [set.leftContour, set.rightContour] where contour.count > 1 {
            var path = Path()
            path.move(to: map(contour[0]))
            for p in contour.dropFirst() { path.addLine(to: map(p)) }
            if !isEarlier {
                ctx.stroke(path, with: .color(haloColor), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round,
                                          dash: isEarlier ? [4, 3] : []))
        }
        for (_, p) in set.points {
            let v = map(p)
            if isEarlier {
                // A hollow ring, large enough to show the later dot inside it.
                let r: CGFloat = 7
                let rect = CGRect(x: v.x - r, y: v.y - r, width: 2 * r, height: 2 * r)
                ctx.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 2)
            } else {
                // A filled dot with a 2pt Plate halo.
                let r: CGFloat = 4.5
                let halo = CGRect(x: v.x - r - 2, y: v.y - r - 2, width: 2 * (r + 2), height: 2 * (r + 2))
                ctx.fill(Path(ellipseIn: halo), with: .color(haloColor))
                let rect = CGRect(x: v.x - r, y: v.y - r, width: 2 * r, height: 2 * r)
                ctx.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
    }
}
