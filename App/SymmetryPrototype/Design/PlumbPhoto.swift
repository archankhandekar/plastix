import SwiftUI
import SymmetryCore
import UIKit

/// A frontal photo on the Plate, turned so the patient midline runs straight down the
/// centre. The turn ("Plumb") plays once on first appear. Constructions are drawn by the
/// `overlay` closure in plate coordinates and fade in once the turn has finished.
///
/// The plate is square by default; the symmetry result uses the slightly wider
/// `PlateGeometry.Framing.wide`. Side names, the practice marker and a photo-check caution
/// are small tags in the plate's corners, never a full-width strip, so the notch and the
/// shoulders stay visible. The screen's own practice band is the practice label; the plate
/// adds only a small hatched "Practice" tag.
///
/// When the notch or midline bottom is missing (or they coincide) the photo is shown
/// aspect-fit as taken, with no axis and no overlay.
struct PlumbPhoto<Overlay: View>: View {
    private let image: UIImage
    private let landmarks: LandmarkSet?
    private let showsAxis: Bool
    private let showsSideLabels: Bool
    private let animatesTurn: Bool
    private let practice: Bool
    private let caution: String?
    private let framing: PlateGeometry.Framing
    private let overlay: (PlateGeometry) -> Overlay

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.staticMotion) private var staticMotion

    @State private var progress: Double = 0
    @State private var photoOpacity: Double = 1
    @State private var overlayVisible = false
    @State private var hasAppeared = false

    init(image: UIImage,
         landmarks: LandmarkSet?,
         showsAxis: Bool = true,
         showsSideLabels: Bool = true,
         animatesTurn: Bool = true,
         practice: Bool = false,
         caution: String? = nil,
         framing: PlateGeometry.Framing = .square,
         @ViewBuilder overlay: @escaping (PlateGeometry) -> Overlay) {
        self.image = image
        self.landmarks = landmarks
        self.showsAxis = showsAxis
        self.showsSideLabels = showsSideLabels
        self.animatesTurn = animatesTurn
        self.practice = practice
        self.caution = caution
        self.framing = framing
        self.overlay = overlay
    }

    /// The size the landmark pixel coordinates refer to.
    private var pixelSize: CGSize {
        if let landmarks, landmarks.imageSize.x > 0, landmarks.imageSize.y > 0 {
            return CGSize(width: landmarks.imageSize.x, height: landmarks.imageSize.y)
        }
        return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                if let landmarks, let geometry = PlateGeometry(landmarks: landmarks, size: size, framing: framing) {
                    TurnedPhoto(image: image, pixelSize: pixelSize, geometry: geometry, progress: progress)
                        .opacity(photoOpacity)
                    if showsAxis {
                        Path { p in
                            p.move(to: CGPoint(x: geometry.axisX, y: geometry.notchY))
                            p.addLine(to: CGPoint(x: geometry.axisX, y: geometry.bottomY))
                        }
                        .stroke(Theme.Colors.drapeOnPlate, lineWidth: 2)
                        .opacity(overlayVisible ? 1 : 0)
                    }
                    overlay(geometry)
                        .frame(width: size.width, height: size.height)
                        .opacity(overlayVisible ? 1 : 0)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.width, height: size.height)
                }
                PlateCornerTags(showsSideLabels: showsSideLabels, practice: practice, caution: caution)
                    .frame(width: size.width, height: size.height)
            }
            .frame(width: size.width, height: size.height)
        }
        .aspectRatio(framing.aspectRatio, contentMode: .fit)
        .background(Theme.Colors.plate)
        .clipShape(RoundedRectangle(cornerRadius: Theme.photoRadius))
        .onAppear(perform: startTurn)
    }

    private func startTurn() {
        guard !hasAppeared else { return }
        hasAppeared = true
        let animation = Motion.plumb(reduceMotion: reduceMotion, staticMotion: staticMotion)
        guard animatesTurn, let animation, PlateGeometry.canTurn(landmarks) else {
            progress = 1
            overlayVisible = true
            return
        }
        if reduceMotion {
            // Reduce Motion: no turn, a short crossfade into the final state.
            progress = 1
            photoOpacity = 0
            withAnimation(animation) {
                photoOpacity = 1
            } completion: {
                withAnimation(animation) { overlayVisible = true }
            }
            return
        }
        progress = 0
        withAnimation(animation) {
            progress = 1
        } completion: {
            withAnimation(.easeOut(duration: 0.2)) { overlayVisible = true }
        }
    }
}

extension PlumbPhoto where Overlay == EmptyView {
    init(image: UIImage,
         landmarks: LandmarkSet?,
         showsAxis: Bool = true,
         showsSideLabels: Bool = true,
         animatesTurn: Bool = true,
         practice: Bool = false,
         caution: String? = nil,
         framing: PlateGeometry.Framing = .square) {
        self.init(image: image,
                  landmarks: landmarks,
                  showsAxis: showsAxis,
                  showsSideLabels: showsSideLabels,
                  animatesTurn: animatesTurn,
                  practice: practice,
                  caution: caution,
                  framing: framing,
                  overlay: { _ in EmptyView() })
    }
}

/// The plate's corner tags: "Patient right" top left and "Patient left" top right (patient
/// right is the screen-left side), a small hatched "Practice" tag bottom left and a
/// photo-check caution bottom right, in the drape below the midline bottom where nothing
/// is measured. The plate is a fixed-size figure, so the tags
/// stop growing at xxLarge text; every word on them is also said in full off the plate.
struct PlateCornerTags: View {
    let showsSideLabels: Bool
    let practice: Bool
    let caution: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if showsSideLabels {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    tag("Patient right")
                    Spacer(minLength: Theme.Spacing.s)
                    tag("Patient left")
                }
                .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: Theme.Spacing.s) {
                if practice {
                    PracticeTag()
                }
                Spacer(minLength: 0)
                if let caution {
                    cautionTag(caution)
                }
            }
        }
        .padding(Theme.Spacing.xs + 2)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .allowsHitTesting(false)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.Colors.plateInk)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.Colors.plate.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
    }

    private func cautionTag(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.Colors.cautionOnPlate)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Theme.Colors.plate.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.Colors.cautionOnPlate, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// The plate's practice marker: the word "Practice" on a small patch of the practice hatch.
/// The screen's pinned practice band says the full sentence; this only marks the photo.
struct PracticeTag: View {
    var body: some View {
        Text("Practice")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.Colors.plateInk)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Theme.Colors.plate, in: RoundedRectangle(cornerRadius: 2))
            .padding(4)
            .background {
                ZStack {
                    Theme.Colors.plate
                    HatchPattern(spacing: 6)
                        .stroke(Theme.Colors.plateGraduation.opacity(0.6), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .accessibilityLabel("Practice photo")
    }
}

/// The photo drawn through `PlateGeometry.turnTransform(progress:)`. Animatable, so the
/// turn interpolates the rotation rather than crossfading two images.
private struct TurnedPhoto: View, Animatable {
    let image: UIImage
    let pixelSize: CGSize
    let geometry: PlateGeometry
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { ctx, _ in
            ctx.concatenate(geometry.turnTransform(progress: progress))
            ctx.draw(Image(uiImage: image), in: CGRect(origin: .zero, size: pixelSize))
        }
        .accessibilityHidden(true)
    }
}
