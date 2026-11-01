import SwiftUI
import SymmetryCore
import UIKit

/// Pure layout rules of the symmetry plate. No drawing, so they can be unit tested.
enum PlateLayout {
    /// Inset of the height calipers from the plate's outer edge.
    static let caliperInset: CGFloat = 20
    /// Two lines closer than this collapse their caliper to a single tick.
    static let collapseDistance: CGFloat = 6
    /// Height of the dashed mirror tick that carries the patient-right distance across.
    static let mirrorTickHeight: CGFloat = 20
    /// Gap between the nipple-to-midline bracket and the caliper drawn under it.
    static let midlineCaliperDrop: CGFloat = 14

    /// The draw move: each guide grows for `drawDuration`, the next starts `Motion.drawStagger` later.
    static let drawDuration: Double = 0.3
    /// Right nipple guide, left nipple guide, right fold guide, left fold guide, right bracket, left bracket.
    static let drawStageCount = 6
    /// The whole staggered draw, from the first guide starting to the last one finishing.
    static var drawTotalDuration: Double {
        drawDuration + Motion.drawStagger * Double(drawStageCount - 1)
    }

    /// Which outer edge of the plate a height caliper sits on. The patient left is the
    /// screen-right side, so a positive value (patient left lower) puts it on the trailing
    /// edge; a negative one beyond its ± on the leading edge; a value within its ± stays on
    /// the trailing edge and is drawn hollow.
    static func caliperEdge(value: Double, uncertainty: Double) -> Edge {
        value < -abs(uncertainty) ? .leading : .trailing
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
/// brackets, the white calipers and the hand-placed points last. The focused layer is drawn
/// at full strength and the others at 25 percent; with `.all` everything sits at 60 percent.
struct SymmetryPlate: View {
    private let image: UIImage
    private let landmarks: LandmarkSet
    private let reading: SetReading
    private let focus: PlateLayer
    private let practice: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.staticMotion) private var staticMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Linear clock of the staggered draw, 0...1.
    @State private var drawClock: Double = 0
    /// 0 keeps the patient-right outline in its true place, 1 has it mirrored onto the left.
    @State private var mirror: Double = 0
    @State private var hasAppeared = false

    /// The plumb turn plus PlumbPhoto's overlay fade, before the constructions are visible.
    private static let turnDelay: Double = 0.5 + 0.2

    init(image: UIImage, landmarks: LandmarkSet, reading: SetReading, focus: PlateLayer, practice: Bool) {
        self.image = image
        self.landmarks = landmarks
        self.reading = reading
        self.focus = focus
        self.practice = practice
    }

    private var hasOutlines: Bool {
        !landmarks.leftContour.isEmpty || !landmarks.rightContour.isEmpty
    }

    /// Full motion: the draw grows and the outline flips. Off with static motion and with
    /// Reduce Motion (which crossfades instead).
    private var animatesFully: Bool {
        !staticMotion && !reduceMotion && Motion.draw(reduceMotion: reduceMotion, staticMotion: staticMotion) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            PlumbPhoto(image: image, landmarks: landmarks, practice: practice) { geometry in
                PlateCanvas(geometry: geometry,
                            landmarks: landmarks,
                            reading: reading,
                            focus: focus,
                            showsLabels: !dynamicTypeSize.isAccessibilitySize,
                            crossfadeMirror: reduceMotion,
                            drawClock: drawClock,
                            mirror: mirror)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reading.accessibilitySummary)

            if dynamicTypeSize.isAccessibilitySize {
                PlateKeyList(reading: reading)
            }
            if focus == .outlines, hasOutlines {
                OverlapLegend()
            }
        }
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
        if focus == .all { return 0.6 }
        return focus == layer ? 1 : 0.25
    }

    private func stage(_ index: Int) -> Double {
        PlateLayout.drawProgress(clock: drawClock, stage: index)
    }

    private func point(_ type: LandmarkType) -> CGPoint? {
        landmarks[type].map(geometry.viewPoint(pixel:))
    }

    private func draw(in ctx: GraphicsContext, size: CGSize) {
        let axisX = geometry.axisX
        let rightOutline = landmarks.rightContour.map(geometry.viewPoint(pixel:))

        // After the flip, dim the patient-right half so it is clear the marks moved.
        if focus == .outlines, rightOutline.count >= 2, mirror > 0 {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: axisX, height: size.height)),
                     with: .color(Theme.Colors.plate.opacity(0.4 * mirror)))
        }

        // 0. The midline ruler, always on.
        PlateInk.axisRuler(in: ctx, geometry: geometry, showsLabels: showsLabels)

        drawOutlines(in: ctx, size: size, rightOutline: rightOutline)
        drawHeightGuides(in: ctx, size: size)
        drawBrackets(in: ctx, size: size)
        drawCalipers(in: ctx, size: size)
        drawPoints(in: ctx)
    }

    // MARK: 4. Outlines

    private func drawOutlines(in ctx: GraphicsContext, size: CGSize, rightOutline: [CGPoint]) {
        let op = opacity(.outlines)
        let axisX = geometry.axisX
        let left = landmarks.leftContour.map(geometry.viewPoint(pixel:))
        // x' = axisX + (x - axisX) * (1 - 2m): the scaleX 1 to -1 flip about the axis.
        let m = crossfadeMirror ? 1 : mirror
        let moved = rightOutline.map { CGPoint(x: axisX + ($0.x - axisX) * CGFloat(1 - 2 * m), y: $0.y) }

        if left.count >= 3, moved.count >= 3, mirror > 0 {
            var fills = ctx
            fills.opacity *= op * mirror
            let leftPath = PlateInk.closedPath(left)
            let mirroredPath = PlateInk.closedPath(moved)

            var both = fills
            both.clip(to: leftPath)
            both.clip(to: mirroredPath)
            both.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.Colors.drapeOnPlate.opacity(0.22)))

            var leftOnly = fills
            leftOnly.clip(to: mirroredPath, options: .inverse)
            PlateInk.hatch(in: leftOnly, path: leftPath, color: Theme.Colors.markerOnPlate.opacity(0.25))

            var mirroredOnly = fills
            mirroredOnly.clip(to: leftPath, options: .inverse)
            PlateInk.hatch(in: mirroredOnly, path: mirroredPath, color: Theme.Colors.drapeOnPlate.opacity(0.25))
        }

        PlateInk.outline(in: ctx, points: left, color: Theme.Colors.markerOnPlate, dashed: false, opacity: op)
        // The hand-drawn patient-right outline, faint in its true place until mirrored.
        PlateInk.outline(in: ctx, points: rightOutline, color: Theme.Colors.markerOnPlate, dashed: false,
                         opacity: op * 0.3 * (1 - mirror))
        // Derived: the same outline mirrored onto the patient-left side, dashed blue.
        PlateInk.outline(in: ctx, points: moved, color: Theme.Colors.drapeOnPlate, dashed: true,
                         opacity: op * mirror)
    }

    // MARK: 1 and 3. Height guides

    private func drawHeightGuides(in ctx: GraphicsContext, size: CGSize) {
        let guides: [(LandmarkType, PlateLayer, Bool, Int)] = [
            (.rightNipple, .nippleHeight, true, 0),
            (.leftNipple, .nippleHeight, false, 1),
            (.rightIMF, .foldHeight, true, 2),
            (.leftIMF, .foldHeight, false, 3),
        ]
        for (type, layer, dashed, index) in guides {
            guard let p = point(type) else { continue }
            let progress = CGFloat(stage(index))
            guard progress > 0 else { continue }
            let axisX = geometry.axisX
            let op = opacity(layer)
            // Grows from the axis outward to both edges.
            PlateInk.guide(in: ctx, from: CGPoint(x: axisX, y: p.y),
                           to: CGPoint(x: axisX - axisX * progress, y: p.y), dashed: dashed, opacity: op)
            PlateInk.guide(in: ctx, from: CGPoint(x: axisX, y: p.y),
                           to: CGPoint(x: axisX + (size.width - axisX) * progress, y: p.y), dashed: dashed, opacity: op)
        }
    }

    // MARK: 2. Nipple to midline

    private func drawBrackets(in ctx: GraphicsContext, size: CGSize) {
        let op = opacity(.nippleMidline)
        let axisX = geometry.axisX
        let sides: [(LandmarkType, String, Int)] = [
            (.rightNipple, reading.rightToMidlineReadout, 4),
            (.leftNipple, reading.leftToMidlineReadout, 5),
        ]
        for (type, label, index) in sides {
            guard let p = point(type) else { continue }
            let progress = CGFloat(stage(index))
            guard progress > 0 else { continue }
            let end = CGPoint(x: axisX + (p.x - axisX) * progress, y: p.y)
            PlateInk.bracket(in: ctx, from: CGPoint(x: axisX, y: p.y), to: end, opacity: op)
            // Each bracket carries its own verbatim MetricFormatter string, only where it can be read.
            if showsLabels, op >= 0.6, progress >= 1 {
                // Each label stays on its own side of the axis, clear of the ruler labels.
                let side: ClosedRange<CGFloat> = p.x < axisX ? 2...(axisX - 14) : (axisX + 4)...(size.width - 2)
                drawLabel(label, in: ctx, size: size, centreX: (axisX + p.x) / 2, bottomY: p.y - 10,
                          within: side, opacity: op)
            }
        }
    }

    private func drawLabel(_ text: String, in ctx: GraphicsContext, size: CGSize, centreX: CGFloat, bottomY: CGFloat,
                           within side: ClosedRange<CGFloat>, opacity: Double) {
        var c = ctx
        c.opacity *= opacity
        let resolved = c.resolve(Text(text).font(.scaleTick).foregroundColor(Theme.Colors.plateInk))
        let s = resolved.measure(in: CGSize(width: size.width, height: 100))
        let half = s.width / 2 + 4
        // Inside its side when it fits there, and always inside the plate.
        var x = min(max(centreX, side.lowerBound + half), side.upperBound - half)
        x = min(max(x, half + 2), size.width - half - 2)
        let backing = CGRect(x: x - half, y: bottomY - s.height - 2, width: 2 * half, height: s.height + 2)
        c.fill(Path(roundedRect: backing, cornerRadius: 3), with: .color(Theme.Colors.plate.opacity(0.8)))
        c.draw(resolved, at: CGPoint(x: x, y: bottomY - 1), anchor: .bottom)
    }

    // MARK: The differences

    private func drawCalipers(in ctx: GraphicsContext, size: CGSize) {
        let appear = stage(PlateLayout.drawStageCount - 1)
        guard appear > 0 else { return }

        // Nipple height and fold height: a vertical caliper between the two guides at the outer edge.
        let heights: [(BilateralMetric, LandmarkType, LandmarkType)] = [
            (.nippleHeight, .leftNipple, .rightNipple),
            (.foldHeight, .leftIMF, .rightIMF),
        ]
        for (metric, leftType, rightType) in heights {
            let r = reading.reading(metric)
            guard let m = r.measurement, let l = point(leftType), let rp = point(rightType) else { continue }
            let edge = PlateLayout.caliperEdge(value: m.value, uncertainty: m.uncertainty)
            let x = edge == .trailing ? size.width - PlateLayout.caliperInset : PlateLayout.caliperInset
            let collapsed = PlateLayout.isCollapsed(rp.y, l.y)
            PlateInk.caliperVertical(in: ctx, x: x, y1: rp.y, y2: l.y,
                                     whiskerY: collapsed ? (rp.y + l.y) / 2 : l.y,
                                     whiskerHalf: geometry.uncertaintyPoints(m.uncertainty),
                                     hollow: !r.isDistinguishableFromZero,
                                     opacity: opacity(metric.layer) * appear)
        }

        // Nipple to midline: a dashed mirror tick carries the right distance across, and a
        // white caliper spans from it to the patient-left nipple.
        let r = reading.reading(.nippleMidline)
        guard let m = r.measurement, let l = point(.leftNipple), let rightPixel = landmarks[.rightNipple] else { return }
        let op = opacity(.nippleMidline) * appear
        let tickX = PlateLayout.mirrorTickX(geometry: geometry, rightNipplePixel: rightPixel)
        let half = PlateLayout.mirrorTickHeight / 2
        PlateInk.guide(in: ctx, from: CGPoint(x: tickX, y: l.y - half), to: CGPoint(x: tickX, y: l.y + half),
                       dashed: true, opacity: op)
        let y = l.y + PlateLayout.midlineCaliperDrop
        let collapsed = PlateLayout.isCollapsed(tickX, l.x)
        PlateInk.caliperHorizontal(in: ctx, y: y, x1: tickX, x2: l.x,
                                   whiskerX: collapsed ? (tickX + l.x) / 2 : l.x,
                                   whiskerHalf: geometry.uncertaintyPoints(m.uncertainty),
                                   hollow: !r.isDistinguishableFromZero,
                                   opacity: op)
    }

    // MARK: Hand-placed points, last

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
}

// MARK: - Overlap legend

/// The five outline rows, each with a 24pt swatch drawn exactly as on the plate.
private struct OverlapLegend: View {
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
                    ctx.fill(inner, with: .color(Theme.Colors.drapeOnPlate.opacity(0.22)))
                case 3:
                    PlateInk.hatch(in: ctx, path: inner, color: Theme.Colors.markerOnPlate.opacity(0.25))
                default:
                    PlateInk.hatch(in: ctx, path: inner, color: Theme.Colors.drapeOnPlate.opacity(0.25))
                }
            }
            .frame(width: 24, height: 24)
            .background(Theme.Colors.plate, in: RoundedRectangle(cornerRadius: Theme.photoRadius))
            .accessibilityHidden(true)
        }
    }
}
