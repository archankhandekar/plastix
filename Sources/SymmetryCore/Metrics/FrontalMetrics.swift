import Foundation

/// Explicitly defined, normalized frontal measurements. See `MeasurementDefinitions`.
///
/// Every field is optional: a metric that cannot be computed is nil, never zero, and the
/// reason is in `flags`.
public struct FrontalMetrics: Codable, Equatable, Sendable {
    /// (y of patient-left nipple − y of patient-right nipple) / L. Positive: left nipple lower.
    public let verticalNippleDifference: Measurement?
    /// |x of patient-left nipple| / L in the midline frame.
    public let leftNippleToMidline: Measurement?
    /// |x of patient-right nipple| / L in the midline frame.
    public let rightNippleToMidline: Measurement?
    /// leftNippleToMidline − rightNippleToMidline.
    public let nippleToMidlineDifference: Measurement?
    /// (y of patient-left fold − y of patient-right fold) / L. Positive: left fold lower.
    public let imfHeightDifference: Measurement?
    /// Dice overlap of the patient-left contour with the mirrored patient-right contour.
    public let contourOverlap: Measurement?
    /// Sternal notch to midline bottom distance in pixels; 0 when degenerate.
    public let referenceLengthPixels: Double
    public let flags: [ReliabilityFlag]

    public init(verticalNippleDifference: Measurement? = nil,
                leftNippleToMidline: Measurement? = nil,
                rightNippleToMidline: Measurement? = nil,
                nippleToMidlineDifference: Measurement? = nil,
                imfHeightDifference: Measurement? = nil,
                contourOverlap: Measurement? = nil,
                referenceLengthPixels: Double,
                flags: [ReliabilityFlag]) {
        self.verticalNippleDifference = verticalNippleDifference
        self.leftNippleToMidline = leftNippleToMidline
        self.rightNippleToMidline = rightNippleToMidline
        self.nippleToMidlineDifference = nippleToMidlineDifference
        self.imfHeightDifference = imfHeightDifference
        self.contourOverlap = contourOverlap
        self.referenceLengthPixels = referenceLengthPixels
        self.flags = flags
    }

    /// Named metrics in display order, for tables and reports.
    public var namedMetrics: [(name: String, measurement: Measurement?)] {
        [
            ("Vertical nipple difference", verticalNippleDifference),
            ("Patient left nipple to midline", leftNippleToMidline),
            ("Patient right nipple to midline", rightNippleToMidline),
            ("Nipple to midline difference", nippleToMidlineDifference),
            ("Inframammary fold height difference", imfHeightDifference),
            ("Contour overlap", contourOverlap),
        ]
    }
}

public enum FrontalMetricsCalculator {
    /// Default assumed landmark placement standard deviation, as a fraction of L.
    public static let defaultLandmarkSigmaRatio = 0.015

    /// Computes frontal metrics from a landmark set in pixel coordinates.
    /// - Parameter landmarkSigmaRatio: assumed isotropic placement sigma of each landmark,
    ///   as a fraction of the reference length. Propagated first-order; the uncertainty of
    ///   the midline landmarks themselves is not included (see definitions).
    public static func compute(_ set: LandmarkSet,
                               landmarkSigmaRatio: Double = defaultLandmarkSigmaRatio) -> FrontalMetrics {
        var flags: [ReliabilityFlag] = []
        if !set.isComplete { flags.append(.missingLandmarks) }

        guard let frame = MidlineFrame.from(set) else {
            flags.append(.degenerateMidline)
            return FrontalMetrics(referenceLengthPixels: 0, flags: flags)
        }

        let n = frame.normalize(set)
        let sigma = landmarkSigmaRatio
        let sigmaDiff = sigma * 2.0.squareRoot()

        func ratio(_ value: Double, _ u: Double) -> Measurement {
            Measurement(value: value, uncertainty: u, unit: .ratioOfReference)
        }

        let ln = n[.leftNipple], rn = n[.rightNipple]
        let lf = n[.leftIMF], rf = n[.rightIMF]

        let vertical = zip2(ln, rn).map { ratio($0.y - $1.y, sigmaDiff) }
        let leftDist = ln.map { ratio(abs($0.x), sigma) }
        let rightDist = rn.map { ratio(abs($0.x), sigma) }
        let distDiff = zip2(leftDist, rightDist).flatMap { $0.subtracting($1) }
        let imf = zip2(lf, rf).map { ratio($0.y - $1.y, sigmaDiff) }

        let overlap = ContourOverlap.compute(normalized: n)
        let contourAttempted = !set.leftContour.isEmpty || !set.rightContour.isEmpty
        if overlap == nil && contourAttempted { flags.append(.contourTooSparse) }

        return FrontalMetrics(verticalNippleDifference: vertical,
                              leftNippleToMidline: leftDist,
                              rightNippleToMidline: rightDist,
                              nippleToMidlineDifference: distDiff,
                              imfHeightDifference: imf,
                              contourOverlap: overlap,
                              referenceLengthPixels: frame.referenceLength,
                              flags: flags)
    }

    private static func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
        guard let a, let b else { return nil }
        return (a, b)
    }
}

/// Placeholder until Task 4 adds raster Dice. Returns nil (not measured).
enum ContourOverlap {
    static func compute(normalized set: LandmarkSet) -> Measurement? { nil }
}
