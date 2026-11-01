#if DEBUG
import SwiftUI
import SymmetryCore
import UIKit

/// Every Plumb token and shared component on one scrolling screen, with sample values that
/// cover the cases each component must handle: positive, negative, within ±, off the scale
/// and not measured. DEBUG only; reached through the route harness ("gallery").
struct DesignGallery: View {
    @State private var segment = 0
    @State private var flip = true
    @State private var mirrorMode: MirrorPairMode = .sideBySide
    @State private var wipe: CGFloat = 0.5
    @State private var showingRight = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                section("Colour") { colours }
                section("Type") { type }
                section("Controls") { controls }
                section("Facing columns") { facing }
                section("Lean gauges") { gauges }
                section("Outline overlap") { overlap }
                section("Plate") { plate }
                section("Obliques") { obliques }
                section("Across sets") { charts }
                section("Steps") { steps }
                section("Guidance") { guidance }
                section("Rows") { rows }
            }
            .padding(Theme.Spacing.margin)
        }
        .background(Theme.Colors.tray)
        .foregroundStyle(Theme.Colors.ink)
        .practiceBand(true)
        .navigationTitle("Design gallery")
    }

    // MARK: Sections

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(title).font(.sectionTitle)
            content()
        }
    }

    private var colours: some View {
        let tray: [(String, Color)] = [
            ("Ink", Theme.Colors.ink), ("Tray", Theme.Colors.tray), ("Graduation", Theme.Colors.graduation),
            ("Drape", Theme.Colors.drape), ("On drape", Theme.Colors.onDrape), ("Field wash", Theme.Colors.fieldWash),
            ("Marker", Theme.Colors.marker), ("Caution", Theme.Colors.caution),
        ]
        let plate: [(String, Color)] = [
            ("Plate", Theme.Colors.plate), ("Plate ink", Theme.Colors.plateInk),
            ("Plate graduation", Theme.Colors.plateGraduation), ("Marker on plate", Theme.Colors.markerOnPlate),
            ("Drape on plate", Theme.Colors.drapeOnPlate), ("Caution on plate", Theme.Colors.cautionOnPlate),
            ("Caliper", Theme.Colors.caliper),
        ]
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            WrapLayout(spacing: Theme.Spacing.s) {
                ForEach(tray.indices, id: \.self) { i in swatch(tray[i].0, tray[i].1) }
            }
            WrapLayout(spacing: Theme.Spacing.s) {
                ForEach(plate.indices, id: \.self) { i in swatch(plate[i].0, plate[i].1) }
            }
            Text(MetricGlossary.provenanceLine).font(.body)
            Text(MetricGlossary.sidesLine).font(.body)
        }
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            RoundedRectangle(cornerRadius: Theme.photoRadius)
                .fill(color)
                .overlay(RoundedRectangle(cornerRadius: Theme.photoRadius).strokeBorder(Theme.Colors.graduation, lineWidth: 1))
                .frame(width: 32, height: 32)
            Text(name).font(.support)
        }
        .frame(minHeight: Theme.tapTarget)
    }

    private var type: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(MetricFormatter.text(Samples.positive)).font(.readoutHero)
            Text("Patient right").font(.sideLabel)
            Text("Set 3, after fat grafting").font(.screenTitle)
            Text("Left and right in this set").font(.sectionTitle)
            Text(MetricFormatter.text(Samples.negative)).font(.readoutRow)
            Text("Sentences and guidance are body text.").font(.body)
            Text("Taken 10:42. 3 photos, 6 of 6 points.").font(.support)
            Text("0  0.5 L  1 L").font(.scaleTick)
            Text("Take photos").font(.actionLabel)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Button("Take photos") {}.buttonStyle(PrimaryButtonStyle())
            Button("Mark points") {}.buttonStyle(SecondaryButtonStyle())
            Button("Delete this set") {}.buttonStyle(PrimaryButtonStyle(isDestructive: true))
            SegmentedChoice([(value: 0, title: "All"), (value: 1, title: "Nipple height"),
                             (value: 2, title: "Nipple to midline"), (value: 3, title: "Fold height"),
                             (value: 4, title: "Outlines")],
                            selection: $segment)
            ToggleChip("Flip", isOn: $flip)
            Text("Study code").fieldStyle()
            VStack(spacing: Theme.Spacing.s) {
                Button("Retake") {}.buttonStyle(PlateButtonStyle())
                Button("Match pose") {}.buttonStyle(OutlinedCaptureButtonStyle())
                SegmentedChoice([(value: 0, title: "Side by side"), (value: 1, title: "Wipe")],
                                selection: $segment, onPlate: true)
                ToggleChip("Flip", isOn: $flip, onPlate: true)
            }
            .padding(Theme.Spacing.m)
            .background(Theme.Colors.plate, in: RoundedRectangle(cornerRadius: Theme.photoRadius))
            PracticeBand()
            PracticeBand(PracticeBand.photoText, style: .plate)
        }
    }

    private var facing: some View {
        VStack(spacing: Theme.Spacing.s) {
            SideLabels()
            FacingColumns {
                Text("Patient right column, screen left").font(.body)
            } patientLeft: {
                Text("Patient left column, screen right").font(.body)
            }
            .frame(height: 80)
        }
    }

    private var gauges: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.gaugeGap) {
            LeanGauge(title: "Nipple height", measurement: Samples.positive,
                      patientRightEnd: "Right lower", patientLeftEnd: "Left lower",
                      sentence: "The patient's left nipple sits lower than the right.",
                      exportName: "Vertical nipple difference", notMeasuredReason: nil,
                      isFocused: true, onSelect: {})
            LeanGauge(title: "Nipple to midline", measurement: Samples.negative,
                      patientRightEnd: "Right farther", patientLeftEnd: "Left farther",
                      sentence: "The patient's right nipple sits farther from the midline than the left.",
                      exportName: "Nipple to midline difference", notMeasuredReason: nil)
            LeanGauge(title: "Fold height", measurement: Samples.within,
                      patientRightEnd: "Right lower", patientLeftEnd: "Left lower",
                      sentence: "The two fold heights cannot be told apart: the difference is smaller than its ±.",
                      exportName: "Inframammary fold height difference", notMeasuredReason: nil)
            LeanGauge(title: "Nipple height, off the scale", measurement: Samples.clamped,
                      patientRightEnd: "Right lower", patientLeftEnd: "Left lower",
                      sentence: nil, exportName: nil, notMeasuredReason: nil, compact: true)
            LeanGauge(title: "Fold height", measurement: nil,
                      patientRightEnd: "Right lower", patientLeftEnd: "Left lower",
                      sentence: nil, exportName: "Inframammary fold height difference",
                      notMeasuredReason: "Not measured: place both folds.",
                      onMarkPoints: {})
        }
    }

    private var overlap: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.gaugeGap) {
            OverlapScale(measurement: Samples.overlap,
                         sentence: "With the right outline mirrored onto the left, this is how much the two outlines overlap. 1 means they coincide; 0 means they do not overlap.",
                         exportName: "Contour overlap", notMeasuredReason: nil)
            OverlapScale(measurement: nil, sentence: nil, exportName: "Contour overlap",
                         notMeasuredReason: "Not measured: draw both outlines with at least 8 points each.",
                         onMarkPoints: {})
        }
    }

    private var plate: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            PlumbPhoto(image: Samples.frontalImage, landmarks: Samples.landmarks, practice: true) { geometry in
                Canvas { ctx, _ in
                    Samples.drawConstructions(in: ctx, geometry: geometry)
                }
            }
            Text("Photo turned so the midline runs straight down.").font(.support)
            PlumbPhoto(image: Samples.frontalImage, landmarks: nil)
            Text("Without a notch and midline bottom the photo is shown as taken.").font(.support)
        }
    }

    private var obliques: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SegmentedChoice([(value: MirrorPairMode.sideBySide, title: "Side by side"),
                             (value: MirrorPairMode.wipe, title: "Wipe"),
                             (value: MirrorPairMode.switchSide, title: "Switch side")],
                            selection: $mirrorMode)
            ToggleChip("Flip", isOn: $flip)
            MirrorPair(patientRightImage: Samples.obliqueImage(facingRight: true),
                       patientLeftImage: Samples.obliqueImage(facingRight: false),
                       flipPatientRight: flip, mode: mirrorMode,
                       wipeFraction: $wipe, showingPatientRight: $showingRight, practice: true)
            MirrorPair(patientRightImage: nil, patientLeftImage: Samples.obliqueImage(facingRight: false),
                       flipPatientRight: true, mode: .sideBySide,
                       wipeFraction: $wipe, showingPatientRight: $showingRight)
        }
    }

    private var charts: some View {
        let rows = [
            StageLeanChart.Row(id: 1, label: "Set 1", measurement: Samples.positive),
            StageLeanChart.Row(id: 2, label: "Set 2", measurement: Samples.negative),
            StageLeanChart.Row(id: 3, label: "Set 3", measurement: Samples.within),
            StageLeanChart.Row(id: 4, label: "Set 4", measurement: nil),
        ]
        let overlapRows = [
            StageLeanChart.Row(id: 1, label: "Set 1", measurement: Samples.overlap),
            StageLeanChart.Row(id: 2, label: "Set 2", measurement: MetricValue(value: 0.74, uncertainty: 0.02, unit: .dice)),
        ]
        return VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            StageLeanChart(kind: .difference(patientRightEnd: "Right lower", patientLeftEnd: "Left lower"), rows: rows)
            StageLeanChart(kind: .difference(patientRightEnd: "Right lower", patientLeftEnd: "Left lower"), rows: rows, compact: true)
            StageLeanChart(kind: .overlap, rows: overlapRows)
            ForEach(rows) { row in
                Text(row.label + ": " + MetricFormatter.text(row.measurement)).font(.readoutRow)
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            StepRail(items: [
                .init(id: 1, number: 1, title: "Take photos", status: "3 of 3 photos.", state: .done, isActionable: true),
                .init(id: 2, number: 2, title: "Mark points", status: "4 of 6 points.", state: .current, isActionable: true),
                .init(id: 3, number: 3, title: "See left and right", status: nil, state: .upcoming, isActionable: false),
                .init(id: 4, number: 4, title: "Export", status: nil, state: .upcoming, isActionable: false),
            ], onTap: { _ in })
            StepRail(items: [
                .init(id: 1, number: 1, title: "Take photos", status: nil, state: .done, isActionable: false),
                .init(id: 2, number: 2, title: "Mark points", status: nil, state: .current, isActionable: false),
                .init(id: 3, number: 3, title: "See left and right", status: nil, state: .upcoming, isActionable: false),
            ], compact: true)
            StepRail(staticTitles: ["Take photos", "Mark points", "See left and right", "Export"])
        }
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            GuidanceCard(kind: .info, body: "Hold the phone level, at chest height.")
            GuidanceCard(kind: .caution, title: "Photo check", body: "This photo was kept with a blur warning. Treat its points with care.")
            GuidanceCard(kind: .unreliable, body: "The two frontal photos did not line up.")
            GuidanceCard(kind: .dark, body: "Level, press the shutter")
                .padding(Theme.Spacing.m)
                .background(Theme.Colors.plate)
            HowToReadCard()
            ResearchNoticeBanner(showsExplainerLink: false)
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            MetricRow(name: "Vertical nipple difference", measurement: Samples.positive)
            MetricRow(name: "Contour overlap", measurement: nil, reason: "Outlines were not drawn. This one is optional.")
            NextActionBar(title: "See left and right", detail: "6 of 6 points placed.", action: {})
        }
    }
}

/// Sample values and synthetic images for the gallery. Nothing here is study data.
private enum Samples {
    static let positive = MetricValue(value: 0.062, uncertainty: 0.021, unit: .ratioOfReference)
    static let negative = MetricValue(value: -0.041, uncertainty: 0.018, unit: .ratioOfReference)
    static let within = MetricValue(value: 0.012, uncertainty: 0.021, unit: .ratioOfReference)
    static let clamped = MetricValue(value: 0.21, uncertainty: 0.02, unit: .ratioOfReference)
    static let overlap = MetricValue(value: 0.82, uncertainty: 0.01, unit: .dice)

    static let imageSize = CGSize(width: 600, height: 800)

    /// A tilted midline (about 6 degrees), so the plumb turn is visible.
    static let landmarks: LandmarkSet = {
        let notch = Point2D(x: 290, y: 190)
        let bottom = Point2D(x: 330, y: 620)
        func along(_ t: Double, _ side: Double) -> Point2D {
            // t along the midline, side across it in pixels (positive toward image right, patient left).
            let d = bottom - notch
            let len = d.length
            let ux = d.x / len, uy = d.y / len
            return Point2D(x: notch.x + d.x * t + uy * side, y: notch.y + d.y * t - ux * side)
        }
        var set = LandmarkSet(imageSize: Point2D(x: imageSize.width, y: imageSize.height))
        set[.sternalNotch] = notch
        set[.midlineBottom] = bottom
        set[.leftNipple] = along(0.47, 120)
        set[.rightNipple] = along(0.43, -112)
        set[.leftIMF] = along(0.66, 104)
        set[.rightIMF] = along(0.63, -100)
        set.leftContour = (0..<16).map { i in
            let a = Double(i) / 16 * 2 * .pi
            return along(0.5 + 0.17 * sin(a), 112 + 80 * cos(a))
        }
        set.rightContour = (0..<16).map { i in
            let a = Double(i) / 16 * 2 * .pi
            return along(0.48 + 0.16 * sin(a), -104 - 76 * cos(a))
        }
        return set
    }()

    static let frontalImage: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: imageSize, format: format).image { ctx in
            let c = ctx.cgContext
            UIColor(red: 0.18, green: 0.22, blue: 0.25, alpha: 1).setFill()
            c.fill(CGRect(origin: .zero, size: imageSize))
            UIColor(red: 0.80, green: 0.66, blue: 0.58, alpha: 1).setFill()
            c.saveGState()
            c.translateBy(x: 310, y: 400)
            c.rotate(by: -0.093)
            c.fillEllipse(in: CGRect(x: -230, y: -330, width: 460, height: 760))
            c.restoreGState()
            UIColor(red: 0.70, green: 0.55, blue: 0.48, alpha: 1).setFill()
            for p in [landmarks.leftContour, landmarks.rightContour] {
                guard let first = p.first else { continue }
                c.move(to: CGPoint(x: first.x, y: first.y))
                for q in p.dropFirst() { c.addLine(to: CGPoint(x: q.x, y: q.y)) }
                c.closePath()
                c.fillPath()
            }
        }
    }()

    static func obliqueImage(facingRight: Bool) -> UIImage {
        let size = CGSize(width: 450, height: 600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let c = ctx.cgContext
            UIColor(red: 0.18, green: 0.22, blue: 0.25, alpha: 1).setFill()
            c.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.80, green: 0.66, blue: 0.58, alpha: 1).setFill()
            let x: CGFloat = facingRight ? 60 : 110
            c.fillEllipse(in: CGRect(x: x, y: 40, width: 280, height: 540))
            UIColor(red: 0.70, green: 0.55, blue: 0.48, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: facingRight ? 230 : 80, y: 250, width: 140, height: 130))
        }
    }

    /// A sample of every plate construction, drawn with PlateInk.
    static func drawConstructions(in ctx: GraphicsContext, geometry g: PlateGeometry) {
        PlateInk.axisRuler(in: ctx, geometry: g, showsLabels: true)
        guard let ln = landmarks[.leftNipple], let rn = landmarks[.rightNipple],
              let lf = landmarks[.leftIMF], let rf = landmarks[.rightIMF],
              let notch = landmarks[.sternalNotch], let bottom = landmarks[.midlineBottom] else { return }
        let l = g.viewPoint(pixel: ln), r = g.viewPoint(pixel: rn)
        let w = g.size.width

        // Nipple height guides and caliper.
        PlateInk.guide(in: ctx, from: CGPoint(x: 0, y: l.y), to: CGPoint(x: w, y: l.y))
        PlateInk.guide(in: ctx, from: CGPoint(x: 0, y: r.y), to: CGPoint(x: w, y: r.y), dashed: true)
        PlateInk.caliperVertical(in: ctx, x: w - 20, y1: r.y, y2: l.y, whiskerY: l.y,
                                 whiskerHalf: g.uncertaintyPoints(positive.uncertainty))

        // Nipple to midline brackets and the mirror tick.
        PlateInk.bracket(in: ctx, from: CGPoint(x: g.axisX, y: r.y), to: r, opacity: 0.6)
        PlateInk.bracket(in: ctx, from: CGPoint(x: g.axisX, y: l.y), to: l, opacity: 0.6)
        let mirrorX = g.axisX + abs(r.x - g.axisX)
        PlateInk.guide(in: ctx, from: CGPoint(x: mirrorX, y: l.y - 10), to: CGPoint(x: mirrorX, y: l.y + 10),
                       dashed: true, opacity: 0.6)
        PlateInk.caliperHorizontal(in: ctx, y: l.y + 18, x1: mirrorX, x2: l.x, whiskerX: l.x,
                                   whiskerHalf: g.uncertaintyPoints(within.uncertainty), hollow: true, opacity: 0.6)

        // Outlines: left solid violet, right mirrored dashed blue, with overlap fills.
        let left = landmarks.leftContour.map(g.viewPoint(pixel:))
        let mirrored = landmarks.rightContour.map(g.mirroredViewPoint(pixel:))
        let leftPath = PlateInk.closedPath(left), mirroredPath = PlateInk.closedPath(mirrored)
        var both = ctx
        both.clip(to: leftPath)
        both.clip(to: mirroredPath)
        both.fill(Path(CGRect(origin: .zero, size: g.size)), with: .color(Theme.Colors.drapeOnPlate.opacity(0.22)))
        var leftOnly = ctx
        leftOnly.clip(to: mirroredPath, options: .inverse)
        PlateInk.hatch(in: leftOnly, path: leftPath, color: Theme.Colors.markerOnPlate.opacity(0.25))
        var mirroredOnly = ctx
        mirroredOnly.clip(to: leftPath, options: .inverse)
        PlateInk.hatch(in: mirroredOnly, path: mirroredPath, color: Theme.Colors.drapeOnPlate.opacity(0.25))
        PlateInk.outline(in: ctx, points: left, color: Theme.Colors.markerOnPlate, dashed: false)
        PlateInk.outline(in: ctx, points: mirrored, color: Theme.Colors.drapeOnPlate, dashed: true)
        PlateInk.outline(in: ctx, points: landmarks.rightContour.map(g.viewPoint(pixel:)),
                         color: Theme.Colors.markerOnPlate, dashed: false, opacity: 0.3)

        // Marks last, so they sit on top.
        PlateInk.midlinePoint(in: ctx, at: g.viewPoint(pixel: notch))
        PlateInk.midlinePoint(in: ctx, at: g.viewPoint(pixel: bottom))
        PlateInk.nipple(in: ctx, at: l)
        PlateInk.nipple(in: ctx, at: r)
        PlateInk.fold(in: ctx, at: g.viewPoint(pixel: lf))
        PlateInk.fold(in: ctx, at: g.viewPoint(pixel: rf))
    }
}

#Preview {
    NavigationStack { DesignGallery() }
}
#endif
