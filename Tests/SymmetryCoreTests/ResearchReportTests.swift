import XCTest
@testable import SymmetryCore

final class ResearchReportTests: XCTestCase {
    private func sampleReport() -> ResearchReport {
        let s = FrontalMetricsTests.symmetricSet()
        let m = FrontalMetricsCalculator.compute(s)
        let cmp = Comparator.compare(baseline: m, current: m, registration: Registration.register(s, to: s), angle: .frontal)
        let quality = QualityReport(blurScore: 120, clippedHighlightFraction: 0.01, clippedShadowFraction: 0, tiltDegrees: 2, failures: [])
        let capture = CaptureSummary(angle: .frontal, capturedAt: Date(timeIntervalSince1970: 1_700_000_000), quality: quality,
                                     qualityOverridden: false, landmarks: s, frontalMetrics: m)
        let set = CaptureSetSummary(id: UUID(), stageLabel: "After implant placement", positioningNote: "Table 30°, arms at 90°",
                                    capturedAt: Date(timeIntervalSince1970: 1_700_000_000), captures: [capture])
        return ResearchReport(studyID: "S-014", generatedAt: Date(timeIntervalSince1970: 1_700_000_100),
                              settings: ReportSettings(landmarkSigmaRatio: 0.015, qualityThresholds: QualityThresholds(), maxResidualRatio: 0.05),
                              captureSets: [set],
                              comparisons: [ComparisonSummary(baselineSetID: set.id, currentSetID: set.id, result: cmp)])
    }

    func testReportRoundTripsThroughJSON() throws {
        let report = sampleReport()
        let data = try report.jsonData()
        let back = try ResearchReport.decode(from: data)
        XCTAssertEqual(back, report)
        XCTAssertEqual(back.schemaVersion, ResearchReport.currentSchemaVersion)
    }

    func testReportCarriesResearchNoticeAndNoRecommendations() throws {
        let report = sampleReport()
        XCTAssertTrue(report.notice.localizedCaseInsensitiveContains("not clinically validated"))
        let text = String(decoding: try report.jsonData(), as: UTF8.self)
        for banned in ["recommend", "implant size", "better", "worse", "symmetry score"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(banned), "report must not contain '\(banned)'")
        }
    }

    func testReportJSONIsStableAndReadable() throws {
        let text = String(decoding: try sampleReport().jsonData(), as: UTF8.self)
        XCTAssertTrue(text.contains("\"studyID\" : \"S-014\""))
        XCTAssertTrue(text.contains("\"schemaVersion\""))
        XCTAssertTrue(text.contains("1700000100"))
    }

    func testDefinitionsMentionEveryMetricAndLimitations() {
        let md = MeasurementDefinitions.markdown
        for (name, _) in FrontalMetricsCalculator.compute(FrontalMetricsTests.symmetricSet()).namedMetrics {
            XCTAssertTrue(md.contains(name), "definitions missing \(name)")
        }
        XCTAssertTrue(md.contains("reference length"))
        XCTAssertTrue(md.contains("Limitations"))
        XCTAssertTrue(md.contains("millimetre"))
        XCTAssertTrue(md.contains("Dice"))
    }
}
