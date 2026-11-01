import SwiftUI
import SymmetryCore
import SymmetryModels
import UIKit

/// Mark points: place and adjust the six points and the two outlines on one photo. The photo
/// sits on the Plate exactly as taken (the editor never turns it). Tap places the selected
/// point; drag moves the nearest one; outline mode appends points while dragging.
///
/// Below the photo: the banner for the next step, the mirrored chip map (patient right on
/// the screen left), the mode choice, the progress line and the legend. On practice photos
/// only, the teaching aid can show where the virtual patient's points are.
struct LandmarkEditorView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var stores: SessionStores
    @EnvironmentObject private var navigator: AppNavigator
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.sessionKind) private var kind
    @Environment(\.dismiss) private var dismiss
    let sessionID: UUID
    let setID: UUID
    let captureID: UUID

    enum Mode: Hashable { case point(LandmarkType), leftContour, rightContour }

    /// The three choices of the mode control.
    enum Segment: Hashable { case points, leftOutline, rightOutline }

    @State private var landmarks: LandmarkSet?
    @State private var mode: Mode = .point(.sternalNotch)
    /// The point chosen last, so switching back from an outline returns to it.
    @State private var lastPoint: LandmarkType = .sternalNotch
    @State private var loaded = false
    @State private var showMetrics = false
    @State private var confirmDiscard = false
    /// Set when a save fails; the editor stays open so the points can be saved again.
    @State private var saveError: String?
    /// Practice only: the rings at the virtual patient's points.
    @State private var showRings: Bool
    /// Practice only: the per-point check lines are on screen.
    @State private var checkShown = false

    init(sessionID: UUID, setID: UUID, captureID: UUID, showTruth: Bool = false) {
        self.sessionID = sessionID
        self.setID = setID
        self.captureID = captureID
        self._showRings = State(initialValue: showTruth)
    }

    private var ref: SessionRef { SessionRef(id: sessionID, kind: kind) }
    private var session: StudySession? { store.session(id: sessionID) }
    private var capture: Capture? { session?.captureSet(id: setID)?.captures.values.first { $0.id == captureID } }

    private var selectedPoint: LandmarkType? {
        if case .point(let t) = mode { return t }
        return nil
    }

    private var isContourMode: Bool { selectedPoint == nil }

    // MARK: - Teaching gate

    /// The virtual patient's ground truth for this photo, in the photo's pixels, with its ring
    /// radius. Structurally practice-only: it needs the practice session kind AND an asset key
    /// recorded in the practice sidecar for this capture AND ground truth for that render. A
    /// study capture never has a key, so it can never reach this.
    private var teaching: LandmarkCanvas.Rings? {
        guard kind == .practice,
              let key = stores.practice.assetKey(forCaptureID: captureID),
              let truth = stores.practice.patient?.truth(stage: key.stageIndex, angle: key.angle),
              let capture else { return nil }
        let scaled = TeachingCheck.scaled(truth, to: capture.imageSize)
        guard let radius = TeachingCheck.ringRadiusPixels(truth: scaled, sigma: settings.landmarkSigmaRatio) else { return nil }
        return LandmarkCanvas.Rings(truth: scaled, radiusPixels: radius)
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let session, let capture, let image = store.image(for: capture, in: session) {
                let rings = teaching
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        canvas(image: image, capture: capture, rings: rings)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 320)
                            .frame(height: max(320, geo.size.height * 0.55))
                            .layoutPriority(1)
                        ScrollView {
                            lowerPanel(capture: capture, rings: rings)
                                .padding(.horizontal, Theme.Spacing.margin)
                                .padding(.vertical, Theme.Spacing.m)
                        }
                    }
                }
                .background(Theme.Colors.tray)
                .onAppear {
                    if !loaded {
                        let initial = capture.landmarks ?? LandmarkSet(imageSize: capture.imageSize)
                        landmarks = initial
                        let first = initial.missing.first ?? .sternalNotch
                        mode = .point(first)
                        lastPoint = first
                        showMetrics = initial.isComplete
                        loaded = true
                    }
                }
                .onChange(of: landmarks?.isComplete) { _, complete in
                    if complete == true { showMetrics = true }
                }
                .onChange(of: mode) { _, newMode in
                    if case .point(let t) = newMode { lastPoint = t }
                }
                .navigationTitle("Mark points")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { attemptLeave(capture: capture) } label: {
                            Label("Back", systemImage: "chevron.left").labelStyle(.titleAndIcon)
                        }
                        .frame(minHeight: Theme.tapTarget)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(isContourMode ? "Clear this outline" : "Clear this point", action: clearSelected)
                            if isContourMode {
                                Button("Undo last outline point", action: undoContourPoint)
                            }
                            Button {
                                landmarks = LandmarkSet(imageSize: capture.imageSize)
                                mode = .point(.sternalNotch)
                            } label: {
                                Label("Clear all points", systemImage: "trash")
                            }
                        } label: {
                            Text("Edit").frame(minWidth: Theme.tapTarget, minHeight: Theme.tapTarget)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: Theme.Spacing.s) {
                        if let saveError {
                            GuidanceCard(kind: .unreliable,
                                         title: "Not saved yet",
                                         lines: [saveError, "Your points are still on screen. Try saving again."])
                        }
                        Button(seesSidesAfterSave(capture, in: session) ? "Save and see left and right" : "Save and go back") {
                            save(capture, in: session)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(.horizontal, Theme.Spacing.margin)
                    .padding(.vertical, Theme.Spacing.m)
                    .background(Theme.Colors.tray)
                }
                .confirmationDialog("Discard the points you placed?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("Discard", role: .destructive) { dismiss() }
                    Button("Keep editing", role: .cancel) {}
                }
            } else {
                ContentUnavailableView("Image not available", systemImage: "photo")
            }
        }
        .practiceBand(kind == .practice)
    }

    // MARK: - Canvas

    private func canvas(image: UIImage, capture: Capture, rings: LandmarkCanvas.Rings?) -> some View {
        LandmarkCanvas(image: image,
                       landmarks: Binding(get: { landmarks ?? LandmarkSet(imageSize: capture.imageSize) },
                                          set: { landmarks = $0 }),
                       mode: mode,
                       rings: showRings ? rings : nil) { placed in advance(after: placed) }
            .background(Theme.Colors.plate)
            .clipShape(RoundedRectangle(cornerRadius: Theme.photoRadius))
    }

    // MARK: - Lower panel

    @ViewBuilder
    private func lowerPanel(capture: Capture, rings: LandmarkCanvas.Rings?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text(LandmarkHints.banner(for: mode, landmarks: landmarks))
                .font(.body)
                .foregroundStyle(Theme.Colors.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)

            ChipMap(landmarks: landmarks, selected: selectedPoint) { type in
                mode = .point(type)
            }

            SegmentedChoice([(value: Segment.points, title: LandmarkHints.pointsChip),
                             (value: Segment.leftOutline, title: LandmarkHints.leftOutlineChip),
                             (value: Segment.rightOutline, title: LandmarkHints.rightOutlineChip)],
                            selection: segment)

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(LandmarkHints.progressLine(landmarks))
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                Text(LandmarkHints.legend)
                    .font(.support)
                    .foregroundStyle(Theme.Colors.graduation)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let rings {
                teachingControls(rings)
            }

            metricsPreview(capture: capture)
        }
    }

    private var segment: Binding<Segment> {
        Binding(get: {
            switch mode {
            case .point: return .points
            case .leftContour: return .leftOutline
            case .rightContour: return .rightOutline
            }
        }, set: { newValue in
            switch newValue {
            case .points:
                if case .point = mode { return }
                mode = .point(landmarks?.missing.first ?? lastPoint)
            case .leftOutline: mode = .leftContour
            case .rightOutline: mode = .rightContour
            }
        })
    }

    /// Practice photos only (the caller passes rings only through the structural gate).
    private func teachingControls(_ rings: LandmarkCanvas.Rings) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ToggleChip(TeachingCheck.showRingsTitle, isOn: $showRings)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showRings {
                Text(TeachingCheck.caption)
                    .font(.support)
                    .foregroundStyle(Theme.Colors.graduation)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(TeachingCheck.checkTitle) { checkShown = true }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, Theme.Spacing.s)
            if checkShown {
                // A flat list of whole sentences: never a count, a tally or a grade.
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    ForEach(TeachingCheck.lines(placed: landmarks, truth: rings.truth,
                                                sigma: settings.landmarkSigmaRatio), id: \.self) { line in
                        Text(line)
                            .font(.body)
                            .foregroundStyle(Theme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    @ViewBuilder
    private func metricsPreview(capture: Capture) -> some View {
        if capture.angle == .frontal, let landmarks {
            let m = FrontalMetricsCalculator.compute(landmarks, landmarkSigmaRatio: settings.landmarkSigmaRatio)
            let hasContours = !landmarks.leftContour.isEmpty || !landmarks.rightContour.isEmpty
            let midlineMissing = landmarks[.sternalNotch] == nil || landmarks[.midlineBottom] == nil
            let visibleFlags = m.flags.filter { !($0 == .degenerateMidline && midlineMissing) }
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                if !landmarks.isComplete {
                    Text(LandmarkHints.waitingForPoints)
                        .font(.body)
                        .foregroundStyle(Theme.Colors.graduation)
                        .fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup(isExpanded: $showMetrics) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        ForEach(m.namedMetrics, id: \.name) { item in
                            MetricRow(name: item.name,
                                      measurement: item.measurement,
                                      explanation: MetricGlossary.meaning(for: item.name),
                                      reason: MetricGlossary.reason(flags: m.flags,
                                                                    missing: landmarks.missing,
                                                                    hasContours: hasContours,
                                                                    metricName: item.name))
                        }
                        FlagList(flags: visibleFlags)
                    }
                    .padding(.top, Theme.Spacing.s)
                } label: {
                    Text(showMetrics ? "Hide measurements" : "Show measurements")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .frame(maxWidth: .infinity, minHeight: Theme.tapTarget, alignment: .leading)
                }
                .tint(Theme.Colors.ink)
            }
        } else if capture.angle != .frontal {
            GuidanceCard(kind: .info, body: LandmarkHints.obliqueNote)
        }
    }

    // MARK: - Actions

    /// After placing a point, a light tap, then move to the next missing point.
    private func advance(after placed: Mode) {
        guard case .point = placed else { return }
        Haptics.pointPlaced()
        guard let landmarks, let next = landmarks.missing.first else { return }
        mode = .point(next)
    }

    private func clearSelected() {
        switch mode {
        case .point(let t): landmarks?[t] = nil
        case .leftContour: landmarks?.leftContour = []
        case .rightContour: landmarks?.rightContour = []
        }
    }

    private func undoContourPoint() {
        switch mode {
        case .leftContour: _ = landmarks?.leftContour.popLast()
        case .rightContour: _ = landmarks?.rightContour.popLast()
        case .point: break
        }
    }

    /// Leave without saving, asking first when the points on screen differ from the saved ones.
    private func attemptLeave(capture: Capture) {
        let saved = capture.landmarks ?? LandmarkSet(imageSize: capture.imageSize)
        if landmarks != saved {
            confirmDiscard = true
        } else {
            dismiss()
        }
    }

    /// The set as it would be after saving the points on screen.
    private func updatedSet(_ capture: Capture, in session: StudySession) -> CaptureSet? {
        guard var set = session.captureSet(id: setID) else { return nil }
        var updated = capture
        updated.landmarks = landmarks
        set.update(updated)
        return set
    }

    /// True when saving makes (or keeps) this set measured from its frontal photo, so the
    /// save opens the set's left-right result.
    private func seesSidesAfterSave(_ capture: Capture, in session: StudySession) -> Bool {
        guard capture.angle == .frontal, landmarks?.isComplete == true,
              let set = updatedSet(capture, in: session) else { return false }
        return SessionWizard.isMeasured(set, sigma: settings.landmarkSigmaRatio)
    }

    private func save(_ capture: Capture, in session: StudySession) {
        guard let set = updatedSet(capture, in: session) else { return }
        let opensSides = seesSidesAfterSave(capture, in: session)
        var s = session
        s.update(set)
        guard store.save(s) else {
            saveError = store.lastError ?? "The points could not be saved."
            return
        }
        saveError = nil
        if opensSides {
            openSides()
        } else {
            dismiss()
        }
    }

    /// Pops the editor and shows this set's left-right result. When the editor was opened
    /// from that result, popping is enough.
    private func openSides() {
        var path = navigator.path
        if case .markPoints? = path.last { path.removeLast() }
        if case .symmetry(let r, let shownSet, _, _, _)? = path.last, r == ref, shownSet == setID {
            navigator.path = path
            return
        }
        path.append(.symmetry(ref, setID: setID))
        navigator.path = path
    }
}

/// The photo with its marks, handling placement gestures and a loupe while dragging.
struct LandmarkCanvas: View {
    /// The virtual patient's points and ring radius, in the photo's pixels. Practice only.
    struct Rings {
        let truth: LandmarkSet
        let radiusPixels: Double
    }

    let image: UIImage
    @Binding var landmarks: LandmarkSet
    let mode: LandmarkEditorView.Mode
    var rings: Rings? = nil
    let onPlaced: (LandmarkEditorView.Mode) -> Void

    @Environment(\.staticMotion) private var staticMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragging: LandmarkType?
    @State private var dragMoved = false
    @State private var fingerView: CGPoint?
    @State private var lastContourPoint: Point2D?

    private let grabRadius: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let fit = fitRect(in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .accessibilityLabel("Photo for marking points")
                if let rings {
                    TeachingRings(truth: rings.truth, radiusPixels: rings.radiusPixels,
                                  pixelSize: image.size, fit: fit)
                }
                Canvas { ctx, _ in
                    draw(ctx, fit: fit)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                if let center = pulseCenter(fit: fit) {
                    PulseRing(center: center, isStatic: staticMotion || reduceMotion)
                }
                if let finger = fingerView {
                    Loupe(image: image, fit: fit, center: finger)
                        .position(x: finger.x, y: max(70, finger.y - 110))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in handleChange(value, fit: fit) }
                    .onEnded { value in handleEnd(value, fit: fit) }
            )
        }
    }

    // MARK: - Coordinates

    private func fitRect(in size: CGSize) -> CGRect {
        let iw = image.size.width, ih = image.size.height
        guard iw > 0, ih > 0 else { return CGRect(origin: .zero, size: size) }
        let scale = min(size.width / iw, size.height / ih)
        let w = iw * scale, h = ih * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func toPixel(_ p: CGPoint, fit: CGRect) -> Point2D {
        let sx = image.size.width / fit.width, sy = image.size.height / fit.height
        let x = min(max(p.x, fit.minX), fit.maxX), y = min(max(p.y, fit.minY), fit.maxY)
        return Point2D(x: Double((x - fit.minX) * sx), y: Double((y - fit.minY) * sy))
    }

    private func toView(_ p: Point2D, fit: CGRect) -> CGPoint {
        let sx = fit.width / image.size.width, sy = fit.height / image.size.height
        return CGPoint(x: fit.minX + CGFloat(p.x) * sx, y: fit.minY + CGFloat(p.y) * sy)
    }

    /// The point to place next gets a pulsing ring: around it when it is already placed (it
    /// will move), or, with the teaching rings on, around the ring where it goes.
    private func pulseCenter(fit: CGRect) -> CGPoint? {
        guard case .point(let type) = mode else { return nil }
        if let p = landmarks[type] { return toView(p, fit: fit) }
        if let p = rings?.truth[type] { return toView(p, fit: fit) }
        return nil
    }

    // MARK: - Gestures

    private func handleChange(_ value: DragGesture.Value, fit: CGRect) {
        fingerView = value.location
        switch mode {
        case .point(let selected):
            if dragging == nil, !dragMoved {
                // Grab an existing landmark only when it is the selected one, or when the
                // selected one is already placed; otherwise the gesture places the selection.
                if let near = nearestLandmark(to: value.startLocation, fit: fit),
                   near == selected || landmarks[selected] != nil {
                    dragging = near
                }
            }
            if value.translation.width.magnitude > 4 || value.translation.height.magnitude > 4 { dragMoved = true }
            if let d = dragging, dragMoved { landmarks[d] = toPixel(value.location, fit: fit) }
        case .leftContour, .rightContour:
            let p = toPixel(value.location, fit: fit)
            let minSpacing = Double(image.size.width) / 150
            if let last = lastContourPoint, last.distance(to: p) < minSpacing { return }
            lastContourPoint = p
            if mode == .leftContour { landmarks.leftContour.append(p) } else { landmarks.rightContour.append(p) }
        }
    }

    private func handleEnd(_ value: DragGesture.Value, fit: CGRect) {
        defer { dragging = nil; dragMoved = false; fingerView = nil; lastContourPoint = nil }
        guard case .point(let type) = mode else { onPlaced(mode); return }
        // A tap, or a drag that started on empty image, places the selected landmark where
        // the finger lifted. Gloved taps often travel a few points; that still places.
        if dragging == nil {
            landmarks[type] = toPixel(value.location, fit: fit)
            onPlaced(mode)
        }
    }

    private func nearestLandmark(to p: CGPoint, fit: CGRect) -> LandmarkType? {
        var best: (LandmarkType, CGFloat)?
        for (type, pt) in landmarks.points {
            let v = toView(pt, fit: fit)
            let d = hypot(v.x - p.x, v.y - p.y)
            if d <= grabRadius, best == nil || d < best!.1 { best = (type, d) }
        }
        return best?.0
    }

    // MARK: - Drawing

    /// Violet is what a hand placed (points and both outlines, with a Plate halo); the dashed
    /// midline between the notch and the midline bottom is derived, so it is Drape blue.
    private func draw(_ ctx: GraphicsContext, fit: CGRect) {
        for (contour, title) in [(landmarks.leftContour, LandmarkHints.leftOutlineChip),
                                 (landmarks.rightContour, LandmarkHints.rightOutlineChip)] where contour.count > 1 {
            let points = contour.map { toView($0, fit: fit) }
            var path = Path()
            path.move(to: points[0])
            for p in points.dropFirst() { path.addLine(to: p) }
            ctx.stroke(path, with: .color(Theme.Colors.plate.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .color(Theme.Colors.markerOnPlate),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            if let top = points.min(by: { $0.y < $1.y }) {
                label(ctx, title, near: top, gap: 6, fit: fit)
            }
        }
        if let n = landmarks[.sternalNotch], let b = landmarks[.midlineBottom] {
            var path = Path()
            path.move(to: toView(n, fit: fit))
            path.addLine(to: toView(b, fit: fit))
            ctx.stroke(path, with: .color(Theme.Colors.plate.opacity(0.6)), lineWidth: 4)
            ctx.stroke(path, with: .color(Theme.Colors.drapeOnPlate), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }
        for type in LandmarkType.allCases {
            guard let p = landmarks[type] else { continue }
            let v = toView(p, fit: fit)
            switch type {
            case .leftNipple, .rightNipple: PlateInk.nipple(in: ctx, at: v)
            case .leftIMF, .rightIMF: PlateInk.fold(in: ctx, at: v)
            case .sternalNotch, .midlineBottom: PlateInk.midlinePoint(in: ctx, at: v)
            }
            label(ctx, LandmarkHints.chipLabel(type), near: v, gap: 12, fit: fit)
        }
    }

    /// A Plate-backed label just above `point`, or just below it when there is no room above.
    private func label(_ ctx: GraphicsContext, _ text: String, near point: CGPoint, gap: CGFloat, fit: CGRect) {
        let resolved = ctx.resolve(Text(text).font(.subheadline).foregroundColor(Theme.Colors.plateInk))
        let size = resolved.measure(in: CGSize(width: 240, height: 80))
        let pad: CGFloat = 4
        var centerY = point.y - gap - pad - size.height / 2
        if centerY - size.height / 2 - pad < fit.minY {
            centerY = point.y + gap + pad + size.height / 2
        }
        let minX = fit.minX + size.width / 2 + pad, maxX = fit.maxX - size.width / 2 - pad
        let centerX = minX <= maxX ? min(max(point.x, minX), maxX) : point.x
        let center = CGPoint(x: centerX, y: centerY)
        let backing = CGRect(x: center.x - size.width / 2 - pad, y: center.y - size.height / 2 - pad / 2,
                             width: size.width + 2 * pad, height: size.height + pad)
        ctx.fill(Path(roundedRect: backing, cornerRadius: 3), with: .color(Theme.Colors.plate.opacity(0.75)))
        ctx.draw(resolved, at: center)
    }

    /// A violet ring that breathes outward around the point to place next. Static (one ring
    /// at its middle size) when motion is static or Reduce Motion is on.
    struct PulseRing: View {
        let center: CGPoint
        let isStatic: Bool
        private let period: Double = 1.4

        var body: some View {
            // Qualified: the app has its own TimelineView screen.
            SwiftUI.TimelineView(.animation(minimumInterval: nil, paused: isStatic)) { timeline in
                Canvas { ctx, _ in
                    let phase = isStatic ? 0.5
                        : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                    let r = CGFloat(14 + 12 * phase)
                    let opacity = isStatic ? 1 : 1 - phase
                    let ring = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
                    var c = ctx
                    c.opacity = opacity
                    c.stroke(ring, with: .color(Theme.Colors.plate.opacity(0.7)), lineWidth: 5)
                    c.stroke(ring, with: .color(Theme.Colors.markerOnPlate), lineWidth: 2)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Magnified view of the photo under the finger. Flat: no shadow.
    struct Loupe: View {
        let image: UIImage
        let fit: CGRect
        let center: CGPoint
        private let diameter: CGFloat = 120
        private let zoom: CGFloat = 2.5

        var body: some View {
            Image(uiImage: image)
                .resizable()
                .frame(width: fit.width * zoom, height: fit.height * zoom)
                .offset(x: -(center.x - fit.minX) * zoom + diameter / 2, y: -(center.y - fit.minY) * zoom + diameter / 2)
                .frame(width: diameter, height: diameter, alignment: .topLeading)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.Colors.plate, lineWidth: 4))
                .overlay(Circle().stroke(Theme.Colors.plateInk, lineWidth: 2))
                .overlay(Image(systemName: "plus").font(.subheadline).foregroundStyle(Theme.Colors.plateInk))
        }
    }
}
