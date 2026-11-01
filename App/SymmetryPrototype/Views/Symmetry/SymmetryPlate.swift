import SwiftUI
import SymmetryCore
import UIKit

/// Pure layout rules of the symmetry plate. No drawing, so they can be unit tested.
enum PlateLayout {
    /// Every layer's strength with `.all` in focus.
    static let allOpacity: Double = 0.85
    /// A layer that is not in focus while another one is.
    static let dimmedOpacity: Double = 0.4
    /// Two lines closer than this collapse their caliper to a single tick.
    static let collapseDistance: CGFloat = 6
    /// Gap between the torso's lateral edge and a height caliper just outside it.
    static let caliperGap: CGFloat = 10
    /// The nearest a caliper or a label comes to the plate's outer edge.
    static let edgeMargin: CGFloat = 4
    /// Gap between the lowest guide and the nipple-to-midline comparison lane under it.
    static let laneGap: CGFloat = 24
    /// Where the torso's lateral edge is assumed to be, past a nipple, when no outline was drawn.
    static let lateralReachL: CGFloat = 0.17

    /// The draw move: each guide grows for `drawDuration`, the next starts `Motion.drawStagger` later.
    static let drawDuration: Double = 0.3
    /// Right nipple guide, left nipple guide, right fold guide, left fold guide, right bracket, left bracket.
    static let drawStageCount = 6
    /// The whole staggered draw, from the first guide starting to the last one finishing.
    static var drawTotalDuration: Double {
        drawDuration + Motion.drawStagger * Double(drawStageCount - 1)
    }

    /// How strongly a layer is drawn: everything at `allOpacity` with `.all` in focus, the
    /// focused layer at full strength and the rest at `dimmedOpacity`.
    static func opacity(of layer: PlateLayer, focus: PlateLayer) -> Double {
        if focus == .all { return allOpacity }
        return focus == layer ? 1 : dimmedOpacity
    }

    /// True when a layer is drawn strongly enough to carry its labels.
    static func showsLabels(of layer: PlateLayer, focus: PlateLayer) -> Bool {
        opacity(of: layer, focus: focus) >= allOpacity
    }

    /// True when two lines are too close for a caliper between them, so it becomes one tick.
    static func isCollapsed(_ a: CGFloat, _ b: CGFloat) -> Bool {
        abs(a - b) < collapseDistance
    }

    /// Where the patient-right nipple's distance from the midline lands when carried across
    /// onto the patient-left side: axisX + |normalized x| * k.
    static func mirrorTickX(geometry: PlateGeometry, rightNipplePixel: Point2D) -> CGFloat {
        let n = geometry.frame.normalize(rightNipplePixel)
        return geometry.axisX + CGFloat(abs(n.x)) * geometry.pointsPerL
    }

    /// A verbatim MetricFormatter readout broken before its ± so it fits a narrow gutter:
    /// "+0.071 ± 0.021 L" becomes "+0.071" and "± 0.021 L". The characters are unchanged and
    /// the ± stays with its number's label. Anything without a ± stays one line.
    static func readoutLines(_ readout: String) -> [String] {
        guard let range = readout.range(of: " ± ") else { return [readout] }
        return [String(readout[..<range.lowerBound]), "± " + String(readout[range.upperBound...])]
    }

    /// The scale-end words for a difference that can be told apart from zero: the patient-left
    /// end ("Left lower") for a positive value, the patient-right end for a negative one. Nil
    /// within the ±, when not measured, and for the overlap. Never a judgement.
    static func direction(of reading: MetricReading) -> String? {
        guard let m = reading.measurement, reading.isDistinguishableFromZero,
              reading.metric != .outlineOverlap else { return nil }
        return m.value > 0 ? reading.metric.patientLeftEnd : reading.metric.patientRightEnd
    }

    /// The lines of a gutter label: the readout broken before its ±, then the direction words.
    static func gutterLines(_ reading: MetricReading) -> [String] {
        readoutLines(reading.readout) + [direction(of: reading)].compactMap { $0 }
    }

    /// False when a ruler label centred on `y` would touch a guide, so it is left out.
    static func rulerLabelIsClear(y: CGFloat, labelHeight: CGFloat, guides: [CGFloat]) -> Bool {
        !guides.contains { abs($0 - y) < labelHeight }
    }

    /// The torso's lateral edge on one side: the farthest outline point from the axis, or a
    /// nipple plus `lateralReachL` when no outline was drawn. Nil with neither.
    /// `patientLeft` is the screen-right side.
    static func lateralEdge(outline: [CGPoint], nipple: CGPoint?, axisX: CGFloat, pointsPerL: CGFloat,
                            patientLeft: Bool) -> CGFloat? {
        let reach = lateralReachL * pointsPerL
        if patientLeft {
            let candidates = outline.map(\.x) + [nipple.map { $0.x + reach }].compactMap { $0 }
            return candidates.filter { $0 > axisX }.max()
        }
        let candidates = outline.map(\.x) + [nipple.map { $0.x - reach }].compactMap { $0 }
        return candidates.filter { $0 < axisX }.min()
    }

    /// The x of the height calipers: just outside the patient-left torso edge, never closer
    /// to the plate's edge than 12pt. They always sit on this side; the label says the direction.
    static func caliperX(lateralEdge: CGFloat?, plateWidth: CGFloat) -> CGFloat {
        let fallback = plateWidth * 0.85
        return min((lateralEdge ?? fallback) + caliperGap, plateWidth - 12)
    }

    /// The left x of a gutter label, flush with the plate's edge on its side.
    static func gutterLabelX(labelWidth: CGFloat, plateWidth: CGFloat, patientLeft: Bool) -> CGFloat {
        patientLeft ? plateWidth - edgeMargin - labelWidth : edgeMargin
    }

    /// The y of the nipple-to-midline comparison lane: `laneGap` under the lowest guide, kept
    /// on the plate.
    static func laneY(lowestGuide: CGFloat, plateHeight: CGFloat) -> CGFloat {
        min(lowestGuide + laneGap, plateHeight - 14)
    }

    /// Eased 0...1 progress of one draw stage, from a linear clock running 0...1 over
    /// `drawTotalDuration`.
    static func drawProgress(clock: Double, stage: Int) -> Double {
        let elapsed = clock * drawTotalDuration - Double(stage) * Motion.drawStagger
        let p = max(0, min(1, elapsed / drawDuration))
        return 1 - (1 - p) * (1 - p)
    }
}

/// The bold part of the symmetry result: the frontal photo on the Plate, turned so the
/// midline runs straight down, with every left-right construction layered over it.
///
/// Drawing order: the L ruler, the outlines, the height guides, the nipple-to-midline
/// brackets, the white calipers, the hand-placed points, then the labels. The focused layer
/// is drawn at full strength and the others at 40 percent; with `.all` everything sits at
/// 85 percent. Labels are always drawn at full strength, and only for layers that are not
/// dimmed.
struct SymmetryPlate: View {
    private let image: UIImage
    private let landmarks: LandmarkSet
    private let reading: SetReading
    private let focus: PlateLayer
    private let practice: Bool
    private let caution: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.staticMotion) private var staticMotion

    /// Linear clock of the staggered draw, 0...1.
    @State private var drawClock: Double = 0
    /// 0 keeps the patient-right outline in its true place, 1 has it mirrored onto the left.
    @State private var mirror: Double = 0
    @State private var hasAppeared = false

    /// The plumb turn plus PlumbPhoto's overlay fade, before the constructions are visible.
    private static let turnDelay: Double = 0.5 + 0.2

    init(image: UIImage, landmarks: LandmarkSet, reading: SetReading, focus: PlateLayer, practice: Bool,
         caution: String? = nil) {
        self.image = image
        self.landmarks = landmarks
        self.reading = reading
        self.focus = focus
        self.practice = practice
        self.caution = caution
    }

    /// Full motion: the draw grows and the outline flips. Off with static motion and with
    /// Reduce Motion (which crossfades instead).
    private var animatesFully: Bool {
        !staticMotion && !reduceMotion && Motion.draw(reduceMotion: reduceMotion, staticMotion: staticMotion) != nil
    }

    var body: some View {
        PlumbPhoto(image: image, landmarks: landmarks, practice: practice, caution: caution, framing: .wide) { geometry in
            PlateCanvas(geometry: geometry,
                        landmarks: landmarks,
                        reading: reading,
                        focus: focus,
                        showsLabels: true,
                        crossfadeMirror: reduceMotion,
                        drawClock: drawClock,
                        mirror: mirror)
                // The plate is a fixed-size figure: its labels stop growing at xLarge, and the
                // readouts under it carry every number at full size.
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.accessibilitySummary)
        .onAppear(perform: appear)
        .onChange(of: focus) { _, newFocus in
            focusChanged(to: newFocus)
        }
    }

    private static func mirrorTarget(_ focus: PlateLayer) -> Double {
        focus == .outlines || focus == .all ? 1 : 0
    }

    private func appear() {
        guard !hasAppeared else { return }
        hasAppeared = true
        let target = Self.mirrorTarget(focus)
        guard animatesFully else {
            drawClock = 1
            if reduceMotion, focus == .outlines, let crossfade = Motion.mirror(reduceMotion: true, staticMotion: staticMotion) {
                withAnimation(crossfade.delay(Self.turnDelay)) { mirror = target }
            } else {
                mirror = target
            }
            return
        }
        let delay = PlateGeometry.canTurn(landmarks) ? Self.turnDelay : 0
        // `.all` lands mirrored at once; only turning on Outlines plays the flip.
        mirror = focus == .outlines ? 0 : target
        withAnimation(.linear(duration: PlateLayout.drawTotalDuration).delay(delay)) {
            drawClock = 1
        }
        if focus == .outlines, let flip = Motion.mirror(reduceMotion: reduceMotion, staticMotion: staticMotion) {
            withAnimation(flip.delay(delay)) { mirror = 1 }
        }
    }

    private func focusChanged(to newFocus: PlateLayer) {
        let target = Self.mirrorTarget(newFocus)
        var instant = Transaction()
        instant.disablesAnimations = true

        guard animatesFully else {
            if newFocus == .outlines, let crossfade = Motion.mirror(reduceMotion: reduceMotion, staticMotion: staticMotion) {
                withTransaction(instant) { mirror = 0 }
                DispatchQueue.main.async {
                    withAnimation(crossfade) { mirror = target }
                }
            } else {
                withTransaction(instant) { mirror = target }
            }
            return
        }

        // Regrow the guides from the axis so the newly focused construction is drawn again.
        withTransaction(instant) {
            drawClock = 0
            mirror = newFocus == .outlines ? 0 : target
        }
        DispatchQueue.main.async {
            withAnimation(.linear(duration: PlateLayout.drawTotalDuration)) { drawClock = 1 }
            if newFocus == .outlines, let flip = Motion.mirror(reduceMotion: reduceMotion, staticMotion: staticMotion) {
                withAnimation(flip) { mirror = 1 }
            }
        }
    }
}

// MARK: - The drawing

/// Every construction in plate coordinates. Animatable, so the draw clock and the mirror
/// progress interpolate frame by frame.
private struct PlateCanvas: View, Animatable {
    let geometry: PlateGeometry
    let landmarks: LandmarkSet
    let reading: SetReading
    let focus: PlateLayer
    let showsLabels: Bool
    /// Reduce Motion: the mirrored outline fades in at its final place instead of flipping.
    let crossfadeMirror: Bool
    var drawClock: Double
    var mirror: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(drawClock, mirror) }
        set {
            drawClock = newValue.first
            mirror = newValue.second
        }
    }

    var body: some View {
        Canvas { ctx, size in
            draw(in: ctx, size: size)
        }
        .accessibilityHidden(true)
    }

    // MARK: Layer strength

    private func opacity(_ layer: PlateLayer) -> Double {
        PlateLayout.opacity(of: layer, focus: focus)
    }

    private func labelled(_ layer: PlateLayer) -> Bool {
        showsLabels && PlateLayout.showsLabels(of: layer, focus: focus)
    }

    private func stage(_ index: Int) -> Double {
        PlateLayout.drawProgress(clock: drawClock, stage: index)
    }

    private func point(_ type: LandmarkType) -> CGPoint? {
        landmarks[type].map(geometry.viewPoint(pixel:))
    }

    /// The outlines in plate points, patient left then patient right (in its true place).
    private var leftOutline: [CGPoint] { landmarks.leftContour.map(geometry.viewPoint(pixel:)) }
    private var rightOutline: [CGPoint] { landmarks.rightContour.map(geometry.viewPoint(pixel:)) }

    /// The comparison lane under the folds, drawn only with Nipple to midline in focus.
    private func laneY(size: CGSize) -> CGFloat? {
        guard focus == .nippleMidline, reading.reading(.nippleMidline).measurement != nil,
              let l = point(.leftNipple), let r = point(.rightNipple) else { return nil }
        let folds = [point(.leftIMF), point(.rightIMF)].compactMap { $0?.y }
        let lowest = folds.max() ?? (max(l.y, r.y) + 20)
        return PlateLayout.laneY(lowestGuide: lowest, plateHeight: size.height)
    }

    private func draw(in ctx: GraphicsContext, size: CGSize) {
        let axisX = geometry.axisX

        // After the flip, dim the patient-right half so it is clear the marks moved.
        if focus == .outlines, rightOutline.count >= 2, mirror > 0 {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: axisX, height: size.height)),
                     with: .color(Theme.Colors.plate.opacity(0.4 * mirror)))
        }

        // 0. The midline ruler, always on. Its labels step aside from every guide.
        let guideYs = [LandmarkType.rightNipple, .leftNipple, .rightIMF, .leftIMF].compactMap { point($0)?.y }
            + [laneY(size: size)].compactMap { $0 }
        PlateInk.axisRuler(in: ctx, geometry: geometry, showsLabels: showsLabels, avoiding: guideYs)

        drawOutlines(in: ctx, size: size)
        drawHeightGuides(in: ctx, size: size)
        drawBrackets(in: ctx)
        drawHeightCalipers(in: ctx, size: size)
        drawPoints(in: ctx)
        drawMidlineLane(in: ctx, size: size)
        drawLabels(in: ctx, size: size)
    }

    // MARK: 4. Outlines

    private func drawOutlines(in ctx: GraphicsContext, size: CGSize) {
        let op = opacity(.outlines)
        let axisX = geometry.axisX
        let left = leftOutline
        // x' = axisX + (x - axisX) * (1 - 2m): the scaleX 1 to -1 flip about the axis.
        let m = crossfadeMirror ? 1 : mirror
        let moved = rightOutline.map { CGPoint(x: axisX + ($0.x - axisX) * CGFloat(1 - 2 * m), y: $0.y) }

        // Only the Outlines layer marks the regions; "All" shows the two lines alone, so the
        // patient-left breast keeps its own skin and shading.
        if focus == .outlines, left.count >= 3, moved.count >= 3, mirror > 0 {
            var fills = ctx
            fills.opacity *= op * mirror
            let leftPath = PlateInk.smoothClosedPath(left)
            let mirroredPath = PlateInk.smoothClosedPath(moved)

            var both = fills
            both.clip(to: leftPath)
            both.clip(to: mirroredPath)
            both.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.Colors.drapeOnPlate.opacity(0.08)))

            var leftOnly = fills
            leftOnly.clip(to: mirroredPath, options: .inverse)
            PlateInk.hatch(in: leftOnly, path: leftPath, color: Theme.Colors.markerOnPlate.opacity(0.5))

            var mirroredOnly = fills
            mirroredOnly.clip(to: leftPath, options: .inverse)
            PlateInk.hatch(in: mirroredOnly, path: mirroredPath, color: Theme.Colors.drapeOnPlate.opacity(0.5))
        }

        PlateInk.outline(in: ctx, points: left, color: Theme.Colors.markerOnPlate, dashed: false, opacity: op)
        // The hand-drawn patient-right outline, faint in its true place until mirrored.
        PlateInk.outline(in: ctx, points: rightOutline, color: Theme.Colors.markerOnPlate, dashed: false,
                         opacity: op * 0.5 * (1 - mirror))
        // Derived: the same outline mirrored onto the patient-left side, dashed blue.
        PlateInk.outline(in: ctx, points: moved, color: Theme.Colors.drapeOnPlate, dashed: true,
                         opacity: op * mirror)
    }

    // MARK: 1 and 3. Height guides

    private func drawHeightGuides(in ctx: GraphicsContext, size: CGSize) {
        let pairs: [(LandmarkType, LandmarkType, PlateLayer, Int)] = [
            (.rightNipple, .leftNipple, .nippleHeight, 0),
            (.rightIMF, .leftIMF, .foldHeight, 2),
        ]
        let axisX = geometry.axisX
        for (rightType, leftType, layer, firstStage) in pairs {
            let op = opacity(layer)
            let r = point(rightType), l = point(leftType)
            let both = r != nil && l != nil
            // Patient right is dashed and on the screen-left side.
            for (p, isRight, index) in [(r, true, firstStage), (l, false, firstStage + 1)] {
                guard let p else { continue }
                let progress = CGFloat(stage(index))
                guard progress > 0 else { continue }
                let toLeftEdge = CGPoint(x: axisX - axisX * progress, y: p.y)
                let toRightEdge = CGPoint(x: axisX + (size.width - axisX) * progress, y: p.y)
                // With both points a guide grows from the axis to both edges, so the two can be
                // compared anywhere. A lone guide stays on its own side and stops at the axis.
                if both || isRight {
                    PlateInk.guide(in: ctx, from: CGPoint(x: axisX, y: p.y), to: toLeftEdge, dashed: isRight, opacity: op)
                }
                if both || !isRight {
                    PlateInk.guide(in: ctx, from: CGPoint(x: axisX, y: p.y), to: toRightEdge, dashed: isRight, opacity: op)
                }
            }
        }
    }

    // MARK: 2. Nipple to midline

    private func drawBrackets(in ctx: GraphicsContext) {
        let op = opacity(.nippleMidline)
        let axisX = geometry.axisX
        for (type, index) in [(LandmarkType.rightNipple, 4), (.leftNipple, 5)] {
            guard let p = point(type) else { continue }
            let progress = CGFloat(stage(index))
            guard progress > 0 else { continue }
            let end = CGPoint(x: axisX + (p.x - axisX) * progress, y: p.y)
            PlateInk.bracket(in: ctx, from: CGPoint(x: axisX, y: p.y), to: end, opacity: op)
        }
    }

    // MARK: The differences

    private var caliperAppear: Double { stage(PlateLayout.drawStageCount - 1) }

    private var heightCaliperX: CGFloat {
        let edge = PlateLayout.lateralEdge(outline: leftOutline, nipple: point(.leftNipple), axisX: geometry.axisX,
                                           pointsPerL: geometry.pointsPerL, patientLeft: true)
        return PlateLayout.caliperX(lateralEdge: edge, plateWidth: geometry.size.width)
    }

    /// Nipple height and fold height: a vertical white caliper between the two guides, just
    /// outside the patient-left torso edge, always on that side.
    private func drawHeightCalipers(in ctx: GraphicsContext, size: CGSize) {
        let appear = caliperAppear
        guard appear > 0 else { return }
        let x = heightCaliperX
        for (metric, leftType, rightType) in [(BilateralMetric.nippleHeight, LandmarkType.leftNipple, LandmarkType.rightNipple),
                                              (.foldHeight, .leftIMF, .rightIMF)] {
            let r = reading.reading(metric)
            guard let m = r.measurement, let l = point(leftType), let rp = point(rightType) else { continue }
            let collapsed = PlateLayout.isCollapsed(rp.y, l.y)
            PlateInk.caliperVertical(in: ctx, x: x, y1: rp.y, y2: l.y,
                                     whiskerY: collapsed ? (rp.y + l.y) / 2 : l.y,
                                     whiskerHalf: geometry.uncertaintyPoints(m.uncertainty),
                                     hollow: !r.isDistinguishableFromZero,
                                     opacity: opacity(metric.layer) * appear)
        }
    }

    /// Nipple to midline, in focus only: its own lane under the folds. A dashed blue ring
    /// marks the patient-right nipple mirrored onto the left side; thin leaders drop from it
    /// and from the patient-left nipple to the lane, and the white caliper spans between them.
    private func drawMidlineLane(in ctx: GraphicsContext, size: CGSize) {
        guard let laneY = laneY(size: size), let m = reading.reading(.nippleMidline).measurement,
              let l = point(.leftNipple), let r = point(.rightNipple),
              let rightPixel = landmarks[.rightNipple] else { return }
        let appear = caliperAppear
        guard appear > 0 else { return }
        let reading = reading.reading(.nippleMidline)
        let tickX = PlateLayout.mirrorTickX(geometry: geometry, rightNipplePixel: rightPixel)
        let mirrored = CGPoint(x: tickX, y: r.y)
        PlateInk.mirroredNipple(in: ctx, at: mirrored, opacity: appear)
        PlateInk.guide(in: ctx, from: CGPoint(x: tickX, y: mirrored.y + 10), to: CGPoint(x: tickX, y: laneY),
                       dashed: true, lineWidth: 1, opacity: appear)
        PlateInk.guide(in: ctx, from: CGPoint(x: l.x, y: l.y + 10), to: CGPoint(x: l.x, y: laneY),
                       dashed: true, lineWidth: 1, opacity: appear)
        let collapsed = PlateLayout.isCollapsed(tickX, l.x)
        PlateInk.caliperHorizontal(in: ctx, y: laneY, x1: tickX, x2: l.x,
                                   whiskerX: collapsed ? (tickX + l.x) / 2 : l.x,
                                   whiskerHalf: geometry.uncertaintyPoints(m.uncertainty),
                                   hollow: !reading.isDistinguishableFromZero,
                                   opacity: appear)
    }

    // MARK: Hand-placed points

    private func drawPoints(in ctx: GraphicsContext) {
        for type in LandmarkType.allCases {
            guard let p = point(type) else { continue }
            switch type {
            case .sternalNotch, .midlineBottom: PlateInk.midlinePoint(in: ctx, at: p)
            case .leftNipple, .rightNipple: PlateInk.nipple(in: ctx, at: p)
            case .leftIMF, .rightIMF: PlateInk.fold(in: ctx, at: p)
            }
        }
    }

    // MARK: Labels, last and at full strength

    private func drawLabels(in ctx: GraphicsContext, size: CGSize) {
        guard showsLabels, caliperAppear >= 1 else { return }
        drawMissingSideTags(in: ctx, size: size)
        drawHeightLabels(in: ctx, size: size)
        drawBracketLabels(in: ctx, size: size)
        drawLaneLabel(in: ctx, size: size)
    }

    /// One side of a pair is placed and the other is not: say so on the empty side, at the
    /// height of the placed one.
    private func drawMissingSideTags(in ctx: GraphicsContext, size: CGSize) {
        let pairs: [(LandmarkType, LandmarkType, String)] = [
            (.rightNipple, .leftNipple, "Nipple not marked"),
            (.rightIMF, .leftIMF, "Fold not marked"),
        ]
        let axisX = geometry.axisX
        for (rightType, leftType, text) in pairs {
            let r = point(rightType), l = point(leftType)
            guard (r == nil) != (l == nil), let placed = r ?? l else { continue }
            let missingIsLeft = l == nil
            let s = PlateInk.labelSize(in: ctx, lines: [text])
            let centreX = missingIsLeft ? (axisX + size.width) / 2 : axisX / 2
            let x = min(max(centreX - s.width / 2, PlateLayout.edgeMargin), size.width - PlateLayout.edgeMargin - s.width)
            PlateInk.label(in: ctx, lines: [text], in: CGRect(x: x, y: placed.y - s.height / 2, width: s.width, height: s.height),
                           color: Theme.Colors.cautionOnPlate, outlined: true)
        }
    }

    /// The height readouts in the patient-left gutter, beside their calipers: nipple height
    /// above its upper end, fold height under its lower end. Each carries the direction words.
    private func drawHeightLabels(in ctx: GraphicsContext, size: CGSize) {
        let x = heightCaliperX
        let specs: [(BilateralMetric, LandmarkType, LandmarkType, Bool)] = [
            (.nippleHeight, .leftNipple, .rightNipple, true),
            (.foldHeight, .leftIMF, .rightIMF, false),
        ]
        for (metric, leftType, rightType, above) in specs where labelled(metric.layer) {
            let r = reading.reading(metric)
            guard let m = r.measurement, let l = point(leftType), let rp = point(rightType) else { continue }
            let lines = PlateLayout.gutterLines(r)
            let s = PlateInk.labelSize(in: ctx, lines: lines)
            let whisker = geometry.uncertaintyPoints(m.uncertainty)
            let originX = PlateLayout.gutterLabelX(labelWidth: s.width, plateWidth: size.width, patientLeft: true)
            let y = above ? min(rp.y, l.y) - whisker - 6 - s.height : max(rp.y, l.y) + whisker + 6
            let rect = CGRect(x: originX, y: y, width: s.width, height: s.height)
            if x < rect.minX - 2 {
                let endY = above ? min(rp.y, l.y) : max(rp.y, l.y)
                PlateInk.leader(in: ctx, from: CGPoint(x: x + 6, y: endY), to: CGPoint(x: rect.minX, y: above ? rect.maxY - 4 : rect.minY + 4))
            }
            PlateInk.label(in: ctx, lines: lines, in: rect)
        }
    }

    /// With Nipple to midline in focus: each side's distance from the midline in the gutter
    /// on its own side, with a leader to its bracket's outer end.
    private func drawBracketLabels(in ctx: GraphicsContext, size: CGSize) {
        guard focus == .nippleMidline else { return }
        let sides: [(LandmarkType, String, Bool)] = [
            (.rightNipple, reading.rightToMidlineReadout, false),
            (.leftNipple, reading.leftToMidlineReadout, true),
        ]
        for (type, readout, patientLeft) in sides {
            guard let p = point(type) else { continue }
            let lines = PlateLayout.readoutLines(readout)
            let s = PlateInk.labelSize(in: ctx, lines: lines)
            let originX = PlateLayout.gutterLabelX(labelWidth: s.width, plateWidth: size.width, patientLeft: patientLeft)
            let rect = CGRect(x: originX, y: p.y - s.height / 2, width: s.width, height: s.height)
            let ringEdge = patientLeft ? p.x + 10 : p.x - 10
            let labelEdge = patientLeft ? rect.minX : rect.maxX
            if patientLeft ? labelEdge > ringEdge + 2 : labelEdge < ringEdge - 2 {
                PlateInk.leader(in: ctx, from: CGPoint(x: ringEdge, y: p.y), to: CGPoint(x: labelEdge, y: p.y))
            }
            PlateInk.label(in: ctx, lines: lines, in: rect)
        }
    }

    /// The nipple-to-midline difference beside its lane, in the patient-left gutter.
    private func drawLaneLabel(in ctx: GraphicsContext, size: CGSize) {
        guard let laneY = laneY(size: size), let l = point(.leftNipple), let rightPixel = landmarks[.rightNipple] else { return }
        let r = reading.reading(.nippleMidline)
        let lines = PlateLayout.gutterLines(r)
        let s = PlateInk.labelSize(in: ctx, lines: lines)
        let tickX = PlateLayout.mirrorTickX(geometry: geometry, rightNipplePixel: rightPixel)
        let caliperEnd = max(tickX, l.x) + 6
        var rect = CGRect(x: PlateLayout.gutterLabelX(labelWidth: s.width, plateWidth: size.width, patientLeft: true),
                          y: laneY - s.height / 2, width: s.width, height: s.height)
        if rect.minX < caliperEnd + 4 {
            // No room beside the lane: hang the label under the caliper instead.
            rect.origin.y = laneY + 10
            rect.origin.y = min(rect.origin.y, size.height - s.height - PlateLayout.edgeMargin)
        } else {
            PlateInk.leader(in: ctx, from: CGPoint(x: caliperEnd, y: laneY), to: CGPoint(x: rect.minX, y: laneY))
        }
        PlateInk.label(in: ctx, lines: lines, in: rect)
    }
}

// MARK: - Overlap legend

/// The five outline rows, each with a 24pt swatch drawn exactly as on the plate.
struct OverlapLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(ReadingCopy.overlapLegend.indices, id: \.self) { index in
                HStack(alignment: .center, spacing: Theme.Spacing.m) {
                    Swatch(kind: index)
                    Text(ReadingCopy.overlapLegend[index])
                        .font(.support)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private struct Swatch: View {
        let kind: Int

        var body: some View {
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)
                var line = Path()
                line.move(to: CGPoint(x: 3, y: size.height / 2))
                line.addLine(to: CGPoint(x: size.width - 3, y: size.height / 2))
                let inner = Path(rect.insetBy(dx: 3, dy: 3))
                switch kind {
                case 0:
                    ctx.stroke(line, with: .color(Theme.Colors.markerOnPlate),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                case 1:
                    ctx.stroke(line, with: .color(Theme.Colors.drapeOnPlate),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [7, 5]))
                case 2:
                    // Inside both outlines: left clear on the plate, with only a faint tint.
                    ctx.fill(inner, with: .color(Theme.Colors.drapeOnPlate.opacity(0.08)))
                    ctx.stroke(inner, with: .color(Theme.Colors.markerOnPlate), lineWidth: 1.5)
                    ctx.stroke(Path(rect.insetBy(dx: 6, dy: 6)), with: .color(Theme.Colors.drapeOnPlate),
                               style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                case 3:
                    PlateInk.hatch(in: ctx, path: inner, color: Theme.Colors.markerOnPlate.opacity(0.5))
                default:
                    PlateInk.hatch(in: ctx, path: inner, color: Theme.Colors.drapeOnPlate.opacity(0.5))
                }
            }
            .frame(width: 24, height: 24)
            .background(Theme.Colors.plate, in: RoundedRectangle(cornerRadius: Theme.photoRadius))
            .accessibilityHidden(true)
        }
    }
}
