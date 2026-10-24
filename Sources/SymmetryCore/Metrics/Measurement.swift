import Foundation

/// A single reported quantity with its first-order uncertainty.
///
/// Values are never millimetres or volumes: the prototype has no physical calibration.
public struct Measurement: Codable, Equatable, Sendable {
    public enum Unit: String, Codable, Sendable {
        /// Fraction of the reference length (sternal notch to midline bottom).
        case ratioOfReference
        /// Raw image pixels.
        case pixels
        /// Dice overlap coefficient, 0 to 1.
        case dice
        /// Degrees.
        case degrees
    }

    public let value: Double
    public let uncertainty: Double
    public let unit: Unit

    public init(value: Double, uncertainty: Double, unit: Unit) {
        self.value = value
        self.uncertainty = uncertainty
        self.unit = unit
    }

    /// Difference `self - other` with uncertainties combined in quadrature.
    /// Returns nil when units differ.
    public func subtracting(_ other: Measurement) -> Measurement? {
        guard unit == other.unit else { return nil }
        return Measurement(value: value - other.value,
                           uncertainty: (uncertainty * uncertainty + other.uncertainty * other.uncertainty).squareRoot(),
                           unit: unit)
    }
}

/// Conditions that make a metric or comparison less trustworthy. They are always shown
/// alongside the number they qualify.
public enum ReliabilityFlag: String, Codable, CaseIterable, Sendable {
    case missingLandmarks
    case degenerateMidline
    case contourTooSparse
    case lowImageQuality
    case excessiveTilt
    case registrationResidualHigh
    case qualityOverridden

    public var displayText: String {
        switch self {
        case .missingLandmarks: return "Some landmarks are not placed"
        case .degenerateMidline: return "Midline landmarks coincide; nothing can be normalized"
        case .contourTooSparse: return "Contours have too few points for overlap"
        case .lowImageQuality: return "An image failed a quality check"
        case .excessiveTilt: return "The phone was tilted beyond the limit during capture"
        case .registrationResidualHigh: return "Comparison unreliable: landmarks did not align"
        case .qualityOverridden: return "A quality warning was overridden at capture"
        }
    }
}
