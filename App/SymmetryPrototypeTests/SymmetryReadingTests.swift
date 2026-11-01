import XCTest
import SymmetryCore
import SymmetryModels
@testable import SymmetryPrototype

/// The left-right reading of one photo: sentence selection, Not measured reasons, verbatim
/// readouts, the stage series, and a scan of every ReadingCopy literal.
final class SymmetryReadingTests: XCTestCase {
    private let sigma = FrontalMetricsCalculator.defaultLandmarkSigmaRatio

    private func ratio(_ v: Double, _ u: Double = 0.021) -> MetricValue {
        MetricValue(value: v, uncertainty: u, unit: .ratioOfReference)
    }

    /// Notch (500, 300), midline bottom (500, 900): L = 600 px, x grows to patient left.
    private func landmarks(_ points: [LandmarkType: Point2D]? = nil, left: [Point2D] = [], right: [Point2D] = []) -> LandmarkSet {
        LandmarkSet(points: points ?? [
            .sternalNotch: Point2D(x: 500, y: 300),
            .midlineBottom: Point2D(x: 500, y: 900),
            .leftNipple: Point2D(x: 700, y: 642),   // 0.07 L lower than the right
            .rightNipple: Point2D(x: 300, y: 600),
            .leftIMF: Point2D(x: 690, y: 800),
            .rightIMF: Point2D(x: 310, y: 800),
        ], leftContour: left, rightContour: right, imageSize: Point2D(x: 1000, y: 1400))
    }

    private func circle(cx: Double, cy: Double, r: Double, n: Int) -> [Point2D] {
        (0..<n).map { i in
            let a = Double(i) / Double(n) * 2 * Double.pi
            return Point2D(x: cx + r * cos(a), y: cy + r * sin(a))
        }
    }

    // MARK: - Metric metadata

    func testMetricMetadata() {
        XCTAssertEqual(BilateralMetric.allCases.map(\.title), ["Nipple height", "Nipple to midline", "Fold height", "Outline overlap"])
        XCTAssertEqual(BilateralMetric.allCases.map(\.exportName),
                       ["Vertical nipple difference", "Nipple to midline difference", "Inframammary fold height difference", "Contour overlap"])
        XCTAssertEqual(BilateralMetric.allCases.map(\.patientRightEnd), ["Right lower", "Right farther", "Right lower", nil])
        XCTAssertEqual(BilateralMetric.allCases.map(\.patientLeftEnd), ["Left lower", "Left farther", "Left lower", nil])
        XCTAssertEqual(BilateralMetric.allCases.map(\.layer), [.nippleHeight, .nippleMidline, .foldHeight, .outlines])
        XCTAssertEqual(PlateLayer.allCases.map(\.title), ["All", "Nipple height", "Nipple to midline", "Fold height", "Outlines"])
        XCTAssertEqual(BilateralMetric.outlineOverlap.zeroCaption, "1 means the outlines coincide; 0 means they do not overlap.")
        XCTAssertEqual(BilateralMetric.nippleMidline.zeroCaption, "Zero means both nipples sit at the same distance from the midline.")
        XCTAssertEqual(BilateralMetric.foldHeight.requiredPoints, [.sternalNotch, .midlineBottom, .leftIMF, .rightIMF])
        XCTAssertEqual(BilateralMetric.outlineOverlap.requiredPoints, [.sternalNotch, .midlineBottom])
        // Every metric reads the matching FrontalMetrics field.
        let metrics = FrontalMetricsCalculator.compute(landmarks(left: circle(cx: 650, cy: 650, r: 80, n: 16),
                                                                 right: circle(cx: 350, cy: 650, r: 80, n: 16)))
        XCTAssertEqual(BilateralMetric.nippleHeight.measurement(in: metrics), metrics.verticalNippleDifference)
        XCTAssertEqual(BilateralMetric.nippleMidline.measurement(in: metrics), metrics.nippleToMidlineDifference)
        XCTAssertEqual(BilateralMetric.foldHeight.measurement(in: metrics), metrics.imfHeightDifference)
        XCTAssertEqual(BilateralMetric.outlineOverlap.measurement(in: metrics), metrics.contourOverlap)
        XCTAssertNotNil(metrics.contourOverlap)
    }

    // MARK: - Sentences

    func testNippleHeightSentences() {
        let m = BilateralMetric.nippleHeight
        XCTAssertEqual(ReadingCopy.sentence(for: m, value: ratio(0.05)), "The patient's left nipple sits lower than the right.")
        XCTAssertEqual(ReadingCopy.sentence(for: m, value: ratio(-0.05)), "The patient's right nipple sits lower than the left.")
        let within = "The two nipple heights cannot be told apart: the difference is smaller than its ±."
        XCTAssertEqual(ReadingCopy.sentence(for: m, value: ratio(0.021)), within)
        XCTAssertEqual(ReadingCopy.sentence(for: m, value: ratio(-0.021)), within)
        XCTAssertEqual(ReadingCopy.sentence(for: m, value: ratio(0)), within)
    }

    func testNippleMidlineSentences() {
        let m = BilateralMetric.nippleMidline
        XCTAssertEqual(ReadingCopy.sentence(for: m, value: ratio(0.05)), "The patient's left nipple sits farther from the midline than the right.")
        XCTAssertEqual(ReadingCopy.sentence(for: m, value: ratio(-0.05)), "The patient's right nipple sits farther from the midline than the left.")
        let within = "The two nipple distances from the midline cannot be told apart: the difference is smaller than its ±."
        XCTAssertEqual(ReadingCopy.sentence(for: m, value: ratio(0.021)), within)
        XCTAssertEqual(ReadingCopy.sentence(for: m, value: ratio(-0.021)), within)
    }

    func testFoldHeightSentences() {
        let m = BilateralMetric.foldHeight
        XCTAssertEqual(ReadingCopy.sentence(for: m, value: ratio(0.05)), "The patient's left fold sits lower than the right.")
        XCTAssertEqual(ReadingCopy.sentence(for: m, value: ratio(-0.05)), "The patient's right fold sits lower than the left.")
        let within = "The two fold heights cannot be told apart: the difference is smaller than its ±."
        XCTAssertEqual(ReadingCopy.sentence(for: m, value: ratio(0.021)), within)
        XCTAssertEqual(ReadingCopy.sentence(for: m, value: ratio(-0.021)), within)
    }

    func testOverlapHasOneSentence() {
        let expected = "With the right outline mirrored onto the left, this is how much the two outlines overlap. 1 means they coincide; 0 means they do not overlap."
        for v in [0.0, 0.01, 0.5, 0.99, 1.0] {
            XCTAssertEqual(ReadingCopy.sentence(for: .outlineOverlap, value: MetricValue(value: v, uncertainty: 0.01, unit: .dice)), expected)
        }
    }

    // MARK: - Not measured reasons

    func testNotMeasuredReasons() {
        let all = LandmarkType.allCases
        func reason(_ m: BilateralMetric, _ missing: [LandmarkType], _ flags: [ReliabilityFlag] = []) -> String {
            ReadingCopy.notMeasuredReason(for: m, missing: missing, flags: flags)
        }
        let midline = "Not measured: place the sternal notch and the midline bottom first."
        for m in BilateralMetric.allCases {
            XCTAssertEqual(reason(m, all, [.missingLandmarks, .degenerateMidline]), midline)
            XCTAssertEqual(reason(m, [.sternalNotch]), midline)
            XCTAssertEqual(reason(m, [.midlineBottom, .leftNipple]), midline)
            XCTAssertEqual(reason(m, [], [.degenerateMidline]),
                           "Not measured: the notch and the midline bottom are on the same spot. Move one of them.")
        }
        for m in [BilateralMetric.nippleHeight, .nippleMidline] {
            XCTAssertEqual(reason(m, [.leftNipple]), "Not measured: place the patient left nipple.")
            XCTAssertEqual(reason(m, [.rightNipple, .leftIMF]), "Not measured: place the patient right nipple.")
            XCTAssertEqual(reason(m, [.leftNipple, .rightNipple]), "Not measured: place both nipples.")
        }
        XCTAssertEqual(reason(.foldHeight, [.leftIMF]), "Not measured: place the patient left fold.")
        XCTAssertEqual(reason(.foldHeight, [.rightIMF, .leftNipple]), "Not measured: place the patient right fold.")
        XCTAssertEqual(reason(.foldHeight, [.leftIMF, .rightIMF]), "Not measured: place both folds.")
        XCTAssertEqual(reason(.outlineOverlap, []), "Not measured: draw both outlines with at least 8 points each.")
        XCTAssertEqual(reason(.outlineOverlap, [], [.contourTooSparse]), "Not measured: draw both outlines with at least 8 points each.")
    }

    func testSetReadingWithoutLandmarks() {
        let r = SetReading(landmarks: nil, sigma: sigma)
        XCTAssertNil(r.metrics)
        XCTAssertEqual(r.readings.count, 4)
        XCTAssertEqual(r.readings.map(\.metric), BilateralMetric.allCases)
        for reading in r.readings {
            XCTAssertNil(reading.measurement)
            XCTAssertEqual(reading.readout, "Not measured")
            XCTAssertNil(reading.sentence)
            XCTAssertEqual(reading.notMeasuredReason, "Not measured: place the sternal notch and the midline bottom first.")
            XCTAssertFalse(reading.isDistinguishableFromZero)
        }
        XCTAssertFalse(r.canTurn)
        XCTAssertEqual(r.leftToMidlineReadout, "Not measured")
        XCTAssertTrue(r.flagSentences.isEmpty)
    }

    func testSetReadingMissingOneFold() {
        var set = landmarks()
        set[.leftIMF] = nil
        let r = SetReading(landmarks: set, sigma: sigma)
        XCTAssertTrue(r.canTurn)
        XCTAssertNotNil(r.reading(.nippleHeight).measurement)
        XCTAssertEqual(r.reading(.foldHeight).notMeasuredReason, "Not measured: place the patient left fold.")
        XCTAssertEqual(r.reading(.foldHeight).readout, "Not measured")
        XCTAssertEqual(r.reading(.outlineOverlap).notMeasuredReason, "Not measured: draw both outlines with at least 8 points each.")
    }

    func testSetReadingWithDegenerateMidline() {
        var set = landmarks()
        set[.midlineBottom] = set[.sternalNotch]
        let r = SetReading(landmarks: set, sigma: sigma)
        XCTAssertFalse(r.canTurn)
        for reading in r.readings {
            XCTAssertEqual(reading.notMeasuredReason, "Not measured: the notch and the midline bottom are on the same spot. Move one of them.")
        }
    }

    func testOverlapSparseVersusNone() {
        let reason = "Not measured: draw both outlines with at least 8 points each."
        let none = SetReading(landmarks: landmarks(), sigma: sigma)
        XCTAssertFalse(none.metrics!.flags.contains(.contourTooSparse))
        XCTAssertEqual(none.reading(.outlineOverlap).notMeasuredReason, reason)

        let sparse = SetReading(landmarks: landmarks(left: circle(cx: 650, cy: 650, r: 80, n: 5),
                                                     right: circle(cx: 350, cy: 650, r: 80, n: 16)), sigma: sigma)
        XCTAssertTrue(sparse.metrics!.flags.contains(.contourTooSparse))
        XCTAssertEqual(sparse.reading(.outlineOverlap).notMeasuredReason, reason)

        let full = SetReading(landmarks: landmarks(left: circle(cx: 650, cy: 650, r: 80, n: 16),
                                                   right: circle(cx: 350, cy: 650, r: 80, n: 16)), sigma: sigma)
        let overlap = full.reading(.outlineOverlap)
        XCTAssertNotNil(overlap.measurement)
        XCTAssertNil(overlap.notMeasuredReason)
        XCTAssertTrue(overlap.isDistinguishableFromZero)
        XCTAssertEqual(overlap.sentence, ReadingCopy.sentence(for: .outlineOverlap, value: overlap.measurement!))
    }

    // MARK: - Readouts

    func testReadoutsAreVerbatimMetricFormatterText() {
        let set = landmarks(left: circle(cx: 650, cy: 650, r: 80, n: 16), right: circle(cx: 340, cy: 660, r: 75, n: 16))
        let r = SetReading(landmarks: set, sigma: sigma)
        let metrics = FrontalMetricsCalculator.compute(set, landmarkSigmaRatio: sigma)
        XCTAssertEqual(r.metrics, metrics)
        for m in BilateralMetric.allCases {
            XCTAssertEqual(r.reading(m).readout, MetricFormatter.text(m.measurement(in: metrics)))
            XCTAssertEqual(r.reading(m).measurement, m.measurement(in: metrics))
        }
        XCTAssertEqual(r.leftToMidlineReadout, MetricFormatter.text(metrics.leftNippleToMidline))
        XCTAssertEqual(r.rightToMidlineReadout, MetricFormatter.text(metrics.rightNippleToMidline))
        XCTAssertEqual(r.reading(.nippleHeight).readout, "+0.070 ± 0.021 L")
        XCTAssertTrue(r.reading(.nippleHeight).isDistinguishableFromZero)
        XCTAssertEqual(r.reading(.nippleHeight).sentence, "The patient's left nipple sits lower than the right.")
        XCTAssertFalse(r.reading(.foldHeight).isDistinguishableFromZero)
        XCTAssertEqual(r.reading(.foldHeight).sentence, "The two fold heights cannot be told apart: the difference is smaller than its ±.")
        XCTAssertTrue(r.canTurn)
    }

    func testAccessibilitySummaryListsEveryMetricInOrder() {
        var set = landmarks()
        set[.rightIMF] = nil
        let r = SetReading(landmarks: set, sigma: sigma)
        let expected = [
            "Nipple height", r.reading(.nippleHeight).readout, r.reading(.nippleHeight).sentence!,
            "Nipple to midline", r.reading(.nippleMidline).readout, r.reading(.nippleMidline).sentence!,
            "Fold height", "Not measured", "Not measured: place the patient right fold.",
            "Outline overlap", "Not measured", "Not measured: draw both outlines with at least 8 points each.",
        ].joined(separator: " ")
        XCTAssertEqual(r.accessibilitySummary, expected)
    }

    // MARK: - Flags

    private func frontal(quality: QualityReport?, overridden: Bool = false) -> Capture {
        Capture(angle: .frontal, imageFilename: "f.jpg", pixelWidth: 1000, pixelHeight: 1400,
                quality: quality, tiltDegrees: nil, qualityOverridden: overridden)
    }

    private func report(_ failures: [QualityReport.Failure]) -> QualityReport {
        QualityReport(blurScore: 10, clippedHighlightFraction: 0, clippedShadowFraction: 0, tiltDegrees: 0, failures: failures)
    }

    func testFlagSentences() {
        XCTAssertEqual(ReadingCopy.flagSentences(for: nil), [])
        XCTAssertEqual(ReadingCopy.flagSentences(for: frontal(quality: nil)), ["This photo was not checked for blur, light or tilt."])
        XCTAssertEqual(ReadingCopy.flagSentences(for: frontal(quality: report([]))), [])
        XCTAssertEqual(ReadingCopy.flagSentences(for: frontal(quality: report([.blurry, .overexposed, .underexposed, .tilted]), overridden: true)), [
            "This photo was kept with a blur warning. Treat its points with care.",
            "This photo was kept with a too-bright warning. Treat its points with care.",
            "This photo was kept with a too-dark warning. Treat its points with care.",
            "This photo was kept with a tilt warning. Treat its points with care.",
        ])
        XCTAssertEqual(ReadingCopy.flagSentences(for: frontal(quality: report([.tilted]))),
                       ["This photo was kept with a tilt warning. Treat its points with care."])
        let r = SetReading(landmarks: landmarks(), sigma: sigma, frontal: frontal(quality: report([.blurry]), overridden: true))
        XCTAssertEqual(r.flagSentences, ["This photo was kept with a blur warning. Treat its points with care."])
    }

    // MARK: - Stage series

    func testStageSeriesRowsAndLines() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        func capture(_ angle: ViewAngle, _ landmarks: LandmarkSet? = nil) -> Capture {
            Capture(angle: angle, imageFilename: "\(angle.rawValue).jpg", pixelWidth: 1000, pixelHeight: 1400,
                    quality: nil, tiltDegrees: nil, landmarks: landmarks)
        }
        var missingFold = landmarks()
        missingFold[.leftIMF] = nil
        let s1 = CaptureSet(stage: .preoperativeMarking, positioning: Positioning(), createdAt: t0,
                            captures: [.frontal: capture(.frontal, landmarks()), .leftOblique: capture(.leftOblique),
                                       .rightOblique: capture(.rightOblique)])
        let noFrontal = CaptureSet(stage: .afterResection, positioning: Positioning(), createdAt: t0.addingTimeInterval(60),
                                   captures: [.leftOblique: capture(.leftOblique)])
        let s3 = CaptureSet(stage: .afterFatGrafting, positioning: Positioning(), createdAt: t0.addingTimeInterval(120),
                            captures: [.frontal: capture(.frontal, missingFold)])
        let s4 = CaptureSet(stage: .afterClosure, positioning: Positioning(), createdAt: t0.addingTimeInterval(180),
                            captures: [.frontal: capture(.frontal, landmarks())])
        let session = StudySession(studyID: "S-014", captureSets: [s4, s3, noFrontal, s1])
        let series = StageSeries(session: session, sigma: sigma)

        XCTAssertEqual(series.entries.map(\.index), [1, 3, 4])
        XCTAssertEqual(series.entries.map(\.id), [s1.id, s3.id, s4.id])
        XCTAssertEqual(series.entries.map(\.title), ["Set 1, preoperative marking", "Set 3, after fat grafting", "Set 4, after closure"])
        XCTAssertEqual(series.measuredCount, 2)

        let rows = series.rows(for: .nippleHeight)
        XCTAssertEqual(rows.map(\.label), ["Set 1", "Set 3", "Set 4"])
        XCTAssertEqual(rows.map(\.id), [1, 3, 4])
        XCTAssertTrue(rows.allSatisfy { $0.measurement != nil })
        let folds = series.rows(for: .foldHeight)
        XCTAssertNotNil(folds[0].measurement)
        XCTAssertNil(folds[1].measurement)

        let readout = MetricFormatter.text(FrontalMetricsCalculator.compute(landmarks(), landmarkSigmaRatio: sigma).verticalNippleDifference)
        XCTAssertEqual(series.readoutLines(for: .nippleHeight), [
            "Set 1, preoperative marking: \(readout)",
            "Set 3, after fat grafting: \(readout)",
            "Set 4, after closure: \(readout)",
        ])
        XCTAssertEqual(series.readoutLines(for: .nippleHeight).first, "Set 1, preoperative marking: +0.070 ± 0.021 L")
        XCTAssertEqual(series.readoutLines(for: .foldHeight)[1], "Set 3, after fat grafting. Not measured: place the patient left fold.")
        XCTAssertEqual(series.readoutLines(for: .outlineOverlap)[0],
                       "Set 1, preoperative marking. Not measured: draw both outlines with at least 8 points each.")
    }

    // MARK: - Copy scan

    /// Every literal ReadingCopy and the metric tables can produce.
    private var allCopy: [String] {
        var out: [String] = []
        for m in BilateralMetric.allCases {
            out += [m.title, m.exportName, m.zeroCaption, m.patientRightEnd, m.patientLeftEnd].compactMap { $0 }
            let unit: MetricValue.Unit = m == .outlineOverlap ? .dice : .ratioOfReference
            for v in [-0.1, 0, 0.1] {
                out.append(ReadingCopy.sentence(for: m, value: MetricValue(value: v, uncertainty: 0.021, unit: unit)))
            }
            let missingSets: [[LandmarkType]] = [LandmarkType.allCases, [], [.leftNipple], [.rightNipple], [.leftNipple, .rightNipple],
                                                 [.leftIMF], [.rightIMF], [.leftIMF, .rightIMF]]
            for missing in missingSets {
                out.append(ReadingCopy.notMeasuredReason(for: m, missing: missing, flags: []))
            }
            out.append(ReadingCopy.notMeasuredReason(for: m, missing: [], flags: [.degenerateMidline]))
        }
        out += PlateLayer.allCases.map(\.title)
        out += ReadingCopy.flagSentences(for: frontal(quality: nil))
        out += ReadingCopy.flagSentences(for: frontal(quality: report(QualityReport.Failure.allCases), overridden: true))
        out += [ReadingCopy.photoTurnedCaption, ReadingCopy.cannotTurnCaption, ReadingCopy.referenceCaption,
                ReadingCopy.practiceMidlineCaption, ReadingCopy.obliquesCaption, ReadingCopy.obliquesNote]
        out += ReadingCopy.overlapLegend
        return out
    }

    func testNoReadingCopyJudgesOrUsesBannedTokens() {
        let copy = allCopy
        XCTAssertGreaterThan(copy.count, 60)
        let substrings = ["better", "worse", "improv", "normal", "score", "percent", "symmetric", "·", "→", "%"]
        for line in copy {
            let lower = line.lowercased()
            for banned in substrings {
                XCTAssertFalse(lower.contains(banned), "\"\(line)\" contains \(banned)")
            }
            XCTAssertNil(lower.range(of: #"\bmm\b"#, options: .regularExpression), "\"\(line)\" contains mm")
            XCTAssertNil(line.range(of: #"\b[LR] (nipple|fold|outline)\b"#, options: .regularExpression), "\"\(line)\" abbreviates a side")
        }
    }
}
