import SwiftUI
import SymmetryCore

/// On-screen copy for the landmark editor. Left and right are always the patient's: the
/// patient's left is on the right of a frontal photo.
enum LandmarkHints {
    static let legend = "Violet is what you marked. The patient's left is on the right of the photo."
    static let allMarked = "All 6 points placed. Outlines are optional and need at least 8 points each."
    static let waitingForPoints = "Measurements appear after all 6 points are placed."
    static let obliqueNote = "Points on this view are optional. They are used only to overlay photos, not for measurements. You can go back without marking anything."
    static let pointsChip = "Points"
    static let leftOutlineChip = "Left outline"
    static let rightOutlineChip = "Right outline"
    static let leftOutlineBanner = "Left outline: drag along the patient's left breast edge, on the right of the photo. At least 8 points."
    static let rightOutlineBanner = "Right outline: drag along the patient's right breast edge, on the left of the photo. At least 8 points."

    /// The instruction banner for the current editor mode.
    static func banner(for mode: LandmarkEditorView.Mode, landmarks: LandmarkSet?) -> String {
        switch mode {
        case .point(let type):
            if landmarks?.isComplete == true { return allMarked }
            return hint(for: type)
        case .leftContour:
            return leftOutlineBanner
        case .rightContour:
            return rightOutlineBanner
        }
    }

    /// Chip label for a point landmark.
    static func chipLabel(_ type: LandmarkType) -> String {
        switch type {
        case .sternalNotch: return "Notch"
        case .midlineBottom: return "Midline bottom"
        case .leftNipple: return "Left nipple"
        case .rightNipple: return "Right nipple"
        case .leftIMF: return "Left fold"
        case .rightIMF: return "Right fold"
        }
    }

    /// "<n> of 6 points placed".
    static func progressLine(_ landmarks: LandmarkSet?) -> String {
        "\(pointsMarked(landmarks)) of 6 points placed"
    }

    static func pointsMarked(_ landmarks: LandmarkSet?) -> Int {
        LandmarkType.allCases.count - (landmarks?.missing.count ?? LandmarkType.allCases.count)
    }

    /// "Next: ..." for one point. Whole literals, so the copy guard sees every word.
    static func hint(for type: LandmarkType) -> String {
        switch type {
        case .sternalNotch:
            return "Next: sternal notch. Tap the notch at the top of the breastbone."
        case .midlineBottom:
            return "Next: midline bottom. Tap the xiphoid or the umbilicus. Use the same one for every photo in this study."
        case .leftNipple:
            return "Next: patient left nipple. It is on the right of the photo. Tap it."
        case .rightNipple:
            return "Next: patient right nipple. It is on the left of the photo. Tap it."
        case .leftIMF:
            return "Next: patient left fold. Tap the lowest point of the fold on the right of the photo."
        case .rightIMF:
            return "Next: patient right fold. Tap the lowest point of the fold on the left of the photo."
        }
    }
}
