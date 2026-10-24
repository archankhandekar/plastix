import Foundation

/// Point landmarks placed by hand on a frontal image. "Left" and "right" always mean the
/// patient's left and right. In a frontal photograph the patient's left appears on the
/// image's right.
public enum LandmarkType: String, Codable, CaseIterable, Sendable, Identifiable {
    case sternalNotch
    case midlineBottom
    case leftNipple
    case rightNipple
    case leftIMF
    case rightIMF

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sternalNotch: return "Sternal notch"
        case .midlineBottom: return "Midline bottom (xiphoid or umbilicus)"
        case .leftNipple: return "Patient left nipple"
        case .rightNipple: return "Patient right nipple"
        case .leftIMF: return "Patient left inframammary fold"
        case .rightIMF: return "Patient right inframammary fold"
        }
    }

    /// Short label for tight UI such as the landmark chip row.
    public var shortName: String {
        switch self {
        case .sternalNotch: return "Notch"
        case .midlineBottom: return "Midline"
        case .leftNipple: return "L nipple"
        case .rightNipple: return "R nipple"
        case .leftIMF: return "L fold"
        case .rightIMF: return "R fold"
        }
    }

    public var isRequiredForFrontalMetrics: Bool { true }

    /// The two landmarks that define the midline and the reference length.
    public static let midline: [LandmarkType] = [.sternalNotch, .midlineBottom]
}
