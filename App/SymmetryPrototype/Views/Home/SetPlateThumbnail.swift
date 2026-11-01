import SwiftUI
import SymmetryCore
import UIKit

/// The focus set's frontal photo on the Plate, turned so the midline runs straight down,
/// with a light overlay: the placed points and both nipple height guides. It is one button
/// that opens the set's left and right result.
///
/// The overlay follows the plate grammar: violet marks are what a hand placed (the shape
/// carries the point type), blue guides are what the app drew from them. The patient-left
/// guide is solid and the patient-right guide is dashed. There are no numbers on it.
struct SetPlateThumbnail: View {
    let image: UIImage?
    let landmarks: LandmarkSet?
    let setIndex: Int
    let practice: Bool
    let onOpen: () -> Void

    /// Wide enough for both on-plate side labels; the plate stays centred so its axis sits
    /// on the screen's centre line.
    private static let maxWidth: CGFloat = 340

    var body: some View {
        Button(action: onOpen) {
            Group {
                if let image {
                    PlumbPhoto(image: image, landmarks: landmarks, practice: practice) { geometry in
                        ThumbnailInk(landmarks: landmarks, geometry: geometry)
                    }
                } else {
                    notTaken
                }
            }
            .frame(maxWidth: Self.maxWidth)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        let photo = image == nil ? "Set \(setIndex) has no frontal photo yet." : "Frontal photo of set \(setIndex)."
        return photo + " Opens left and right for set \(setIndex)."
    }

    private var notTaken: some View {
        ZStack {
            Theme.Colors.plate
            Text("Not taken: frontal.")
                .font(.body)
                .foregroundStyle(Theme.Colors.plateInk)
                .multilineTextAlignment(.center)
                .padding(Theme.Spacing.m)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.photoRadius))
    }
}

/// Points and the two nipple guides, drawn in plate coordinates.
private struct ThumbnailInk: View {
    let landmarks: LandmarkSet?
    let geometry: PlateGeometry

    /// Guides stop 20pt short of the plate edges, like the plate's own guides.
    private static let edgeInset: CGFloat = 20

    var body: some View {
        Canvas { ctx, size in
            guard let landmarks else { return }
            let left = Self.edgeInset, right = size.width - Self.edgeInset

            // Derived first, so the hand-placed marks sit on top.
            if let p = landmarks[.leftNipple] {
                let v = geometry.viewPoint(pixel: p)
                PlateInk.guide(in: ctx, from: CGPoint(x: left, y: v.y), to: CGPoint(x: right, y: v.y), dashed: false)
            }
            if let p = landmarks[.rightNipple] {
                let v = geometry.viewPoint(pixel: p)
                PlateInk.guide(in: ctx, from: CGPoint(x: left, y: v.y), to: CGPoint(x: right, y: v.y), dashed: true)
            }

            for type in LandmarkType.allCases {
                guard let p = landmarks[type] else { continue }
                let v = geometry.viewPoint(pixel: p)
                switch type {
                case .leftNipple, .rightNipple:
                    PlateInk.nipple(in: ctx, at: v)
                case .leftIMF, .rightIMF:
                    PlateInk.fold(in: ctx, at: v)
                case .sternalNotch, .midlineBottom:
                    PlateInk.midlinePoint(in: ctx, at: v)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
