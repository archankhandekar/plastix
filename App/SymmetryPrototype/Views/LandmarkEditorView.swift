import SwiftUI
import SymmetryCore
import SymmetryModels
import UIKit

/// Screen 9: place and adjust landmarks and contours on one image. Tap places the selected
/// point; drag moves the nearest one; outline mode appends points while dragging. The
/// banner on the image says which point is next; measurements fold open once all six are placed.
struct LandmarkEditorView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    let sessionID: UUID
    let setID: UUID
    let captureID: UUID

    enum Mode: Hashable { case point(LandmarkType), leftContour, rightContour }

    @State private var landmarks: LandmarkSet?
    @State private var mode: Mode = .point(.sternalNotch)
    @State private var loaded = false
    @State private var showMetrics = false
    @State private var confirmDiscard = false
    /// Set when a save fails; the editor stays open so the points can be saved again.
    @State private var saveError: String?

    private var session: StudySession? { store.session(id: sessionID) }
    private var capture: Capture? { session?.captureSet(id: setID)?.captures.values.first { $0.id == captureID } }

    private var isContourMode: Bool {
        switch mode {
        case .point: return false
        case .leftContour, .rightContour: return true
        }
    }

    var body: some View {
        Group {
            if let session, let capture, let image = store.image(for: capture, in: session) {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        canvas(image: image, capture: capture)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 320)
                            .frame(height: max(320, geo.size.height * 0.55))
                            .layoutPriority(1)
                        ScrollView {
                            lowerPanel(capture: capture)
                                .padding(.horizontal, Theme.Spacing.m)
                                .padding(.vertical, Theme.Spacing.s)
                        }
                    }
                }
                .background(Theme.Colors.paper)
                .onAppear {
                    if !loaded {
                        landmarks = capture.landmarks ?? LandmarkSet(imageSize: capture.imageSize)
                        showMetrics = landmarks?.isComplete == true
                        loaded = true
                    }
                }
                .onChange(of: landmarks?.isComplete) { _, complete in
                    if complete == true { showMetrics = true }
                }
                .navigationTitle("Mark points")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button("Back", systemImage: "chevron.left") { attemptLeave(capture: capture) }
                            .labelStyle(.titleAndIcon)
                        Menu {
                            Button("Clear this point", action: clearSelected)
                            if isContourMode {
                                Button("Undo last outline point", action: undoContourPoint)
                            }
                            Button("Clear all points", role: .destructive) {
                                landmarks = LandmarkSet(imageSize: capture.imageSize)
                            }
                        } label: { Label("Edit", systemImage: "ellipsis.circle") }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: Theme.Spacing.s) {
                        if let saveError {
                            GuidanceCard(kind: .unreliable,
                                         title: "Not saved yet",
                                         lines: [saveError, "Your points are still on screen. Try saving again."])
                        }
                        Button("Save and go back") { save(capture, in: session) }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(Theme.Spacing.m)
                    .background(.bar)
                }
                .confirmationDialog("Discard the points you placed?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("Discard", role: .destructive) { dismiss() }
                    Button("Keep editing", role: .cancel) {}
                }
            } else {
                ContentUnavailableView("Image not available", systemImage: "photo")
            }
        }
    }

    // MARK: - Canvas

    private func canvas(image: UIImage, capture: Capture) -> some View {
        LandmarkCanvas(image: image,
                       landmarks: Binding(get: { landmarks ?? LandmarkSet(imageSize: capture.imageSize) },
                                          set: { landmarks = $0 }),
                       mode: mode) { placed in advance(after: placed) }
            .background(Theme.Colors.capture)
            .overlay(alignment: .top) { banner }
    }

    private var banner: some View {
        Text(LandmarkHints.banner(for: mode, landmarks: landmarks))
            .font(.body)
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: .infinity, minHeight: Theme.tapTarget, alignment: .leading)
            .background(Color.black.opacity(0.7))
            .allowsHitTesting(false)
            .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Lower panel

    @ViewBuilder
    private func lowerPanel(capture: Capture) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if capture.angle == .frontal {
                Text(LandmarkHints.legend)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            modeChips
            Text(LandmarkHints.progressLine(landmarks))
                .font(.body)
                .foregroundStyle(Theme.Colors.ink)
            metricsPreview(capture: capture)
        }
    }

    private var modeChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(LandmarkType.allCases) { type in
                        chip(LandmarkHints.chipLabel(type), selected: mode == .point(type), placed: landmarks?[type] != nil) {
                            mode = .point(type)
                        }
                        .id(Mode.point(type))
                    }
                    chip(LandmarkHints.leftOutlineChip, selected: mode == .leftContour,
                         placed: (landmarks?.leftContour.count ?? 0) >= ContourOverlap.minimumPoints) { mode = .leftContour }
                        .id(Mode.leftContour)
                    chip(LandmarkHints.rightOutlineChip, selected: mode == .rightContour,
                         placed: (landmarks?.rightContour.count ?? 0) >= ContourOverlap.minimumPoints) { mode = .rightContour }
                        .id(Mode.rightContour)
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
            .onChange(of: mode) { _, newMode in
                withAnimation { proxy.scrollTo(newMode, anchor: .center) }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, placed: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if placed { Image(systemName: "checkmark") }
                Text(title)
            }
            .font(.body.weight(selected ? .semibold : .regular))
            .padding(.horizontal, Theme.Spacing.m)
            .frame(minHeight: Theme.tapTarget)
            .background(selected ? Theme.Colors.accent : Theme.Colors.surface, in: Capsule())
            .foregroundStyle(selected ? .white : Theme.Colors.ink)
            .overlay(Capsule().stroke(Theme.Colors.hairline))
        }
        .accessibilityLabel("\(title)\(placed ? ", placed" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                        .foregroundStyle(Theme.Colors.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup(isExpanded: $showMetrics) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
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
            .cardStyle()
        } else if capture.angle != .frontal {
            GuidanceCard(kind: .info, body: LandmarkHints.obliqueNote)
        }
    }

    // MARK: - Actions

    /// After placing a point landmark, move to the next missing one.
    private func advance(after placed: Mode) {
        guard case .point = placed, let landmarks, let next = landmarks.missing.first else { return }
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

    private func save(_ capture: Capture, in session: StudySession) {
        guard var set = session.captureSet(id: setID) else { return }
        var updated = capture
        updated.landmarks = landmarks
        set.update(updated)
        var s = session
        s.update(set)
        guard store.save(s) else {
            saveError = store.lastError ?? "The points could not be saved."
            return
        }
        saveError = nil
        dismiss()
    }
}

/// The image with its landmarks, handling placement gestures and a loupe while dragging.
struct LandmarkCanvas: View {
    let image: UIImage
    @Binding var landmarks: LandmarkSet
    let mode: LandmarkEditorView.Mode
    let onPlaced: (LandmarkEditorView.Mode) -> Void

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
                Canvas { ctx, _ in
                    draw(ctx, fit: fit)
                }
                .allowsHitTesting(false)
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

    private func draw(_ ctx: GraphicsContext, fit: CGRect) {
        for (contour, color) in [(landmarks.leftContour, Color.orange), (landmarks.rightContour, Color.yellow)] where contour.count > 1 {
            var path = Path()
            path.move(to: toView(contour[0], fit: fit))
            for p in contour.dropFirst() { path.addLine(to: toView(p, fit: fit)) }
            ctx.stroke(path, with: .color(color.opacity(0.9)), lineWidth: 2)
        }
        if let n = landmarks[.sternalNotch], let b = landmarks[.midlineBottom] {
            var path = Path()
            path.move(to: toView(n, fit: fit)); path.addLine(to: toView(b, fit: fit))
            ctx.stroke(path, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        for (type, p) in landmarks.points {
            let v = toView(p, fit: fit)
            let isLeft = type == .leftNipple || type == .leftIMF
            let color: Color = type == .sternalNotch || type == .midlineBottom ? .white : (isLeft ? .orange : .yellow)
            let r: CGFloat = 7
            // Dark halo under the ring and dot so they stay visible on light skin.
            let ring = Path(ellipseIn: CGRect(x: v.x - r, y: v.y - r, width: 2 * r, height: 2 * r))
            ctx.stroke(ring, with: .color(.black.opacity(0.7)), lineWidth: 4)
            ctx.stroke(ring, with: .color(color), lineWidth: 2)
            ctx.fill(Path(ellipseIn: CGRect(x: v.x - 2.5, y: v.y - 2.5, width: 5, height: 5)), with: .color(.black.opacity(0.7)))
            ctx.fill(Path(ellipseIn: CGRect(x: v.x - 1.5, y: v.y - 1.5, width: 3, height: 3)), with: .color(color))
            // Caption on a black 70% rounded backing, like the banner, just above the ring.
            let label = ctx.resolve(Text(type.shortName).font(.subheadline).foregroundStyle(color))
            let size = label.measure(in: CGSize(width: 240, height: 60))
            let pad: CGFloat = 4
            let center = CGPoint(x: v.x, y: v.y - r - 4 - pad - size.height / 2)
            let plate = CGRect(x: center.x - size.width / 2 - pad, y: center.y - size.height / 2 - pad / 2,
                               width: size.width + 2 * pad, height: size.height + pad)
            ctx.fill(Path(roundedRect: plate, cornerRadius: 4), with: .color(.black.opacity(0.7)))
            ctx.draw(label, at: center)
        }
    }

    /// Magnified view of the image under the finger.
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
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .overlay(Image(systemName: "plus").font(.subheadline).foregroundStyle(.white))
                .shadow(radius: 4)
        }
    }
}
