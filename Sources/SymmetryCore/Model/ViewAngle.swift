import Foundation

/// The three handheld views captured at each operative stage.
public enum ViewAngle: String, Codable, CaseIterable, Sendable, Identifiable {
    case frontal
    case leftOblique
    case rightOblique

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .frontal: return "Frontal"
        case .leftOblique: return "Left oblique"
        case .rightOblique: return "Right oblique"
        }
    }

    /// Short guidance shown in the viewfinder. Left and right are the patient's sides.
    public var guidanceText: String {
        switch self {
        case .frontal:
            return "Face the patient squarely. Line the sternal notch up with the centre guide."
        case .leftOblique:
            return "Move about 45° toward the patient's left side. Keep the same distance and height."
        case .rightOblique:
            return "Move about 45° toward the patient's right side. Keep the same distance and height."
        }
    }

    /// Whether bilateral frontal metrics are defined for this view.
    public var supportsBilateralMetrics: Bool { self == .frontal }
}
