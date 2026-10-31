import SwiftUI
import SymmetryCore

/// On-screen copy for the landmark editor. Left and right are always the patient's.
enum LandmarkHints {
    static let legend = "Orange = patient's left (on the right of the photo). Yellow = patient's right. White = midline."
    static let allMarked = "All 6 points marked. Outlines are optional and need at least 8 points each. Tap Save."
    static let waitingForPoints = "Measurements appear after all 6 points are marked."
    static let obliqueNote = "Points on this view are optional. They are used only to overlay photos, not for measurements. You can go back without marking anything."
    static let leftOutlineChip = "Left outline"
    static let rightOutlineChip = "Right outline"

    /// The instruction banner for the current editor mode.
    static func banner(for mode: LandmarkEditorView.Mode, landmarks: LandmarkSet?) -> String {
        switch mode {
        case .point(let type):
            if landmarks?.isComplete == true { return allMarked }
            return hint(for: type)
        case .leftContour:
            return "Left outline: drag along the patient's left breast edge. At least 8 points."
        case .rightContour:
            return "Right outline: drag along the patient's right breast edge. At least 8 points."
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

    /// "<n> of 6 points marked".
    static func progressLine(_ landmarks: LandmarkSet?) -> String {
        "\(pointsMarked(landmarks)) of 6 points marked"
    }

    static func pointsMarked(_ landmarks: LandmarkSet?) -> Int {
        LandmarkType.allCases.count - (landmarks?.missing.count ?? LandmarkType.allCases.count)
    }

    private static func hint(for type: LandmarkType) -> String {
        switch type {
        case .sternalNotch:
            return "Point 1 of 6: Sternal notch. Tap the notch at the top of the breastbone."
        case .midlineBottom:
            return "Point 2 of 6: Midline bottom. Tap the xiphoid or the umbilicus. Use the same one for every photo in this study."
        case .leftNipple:
            return "Point 3 of 6: Left nipple. The patient's left is on the right of the photo."
        case .rightNipple:
            return "Point 4 of 6: Right nipple. The patient's right is on the left of the photo."
        case .leftIMF:
            return "Point 5 of 6: Left fold. Tap the lowest point of the patient's left inframammary fold."
        case .rightIMF:
            return "Point 6 of 6: Right fold. Tap the lowest point of the patient's right inframammary fold."
        }
    }
}
