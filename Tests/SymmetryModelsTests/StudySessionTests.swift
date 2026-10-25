import XCTest
import SymmetryCore
@testable import SymmetryModels

final class StudySessionTests: XCTestCase {
    func testStudyIDValidationAcceptsCodesAndTrims() {
        XCTAssertEqual(try StudySession.validateStudyID("  S-014 ").get(), "S-014")
        XCTAssertEqual(try StudySession.validateStudyID("ABC123").get(), "ABC123")
    }

    func testStudyIDValidationRejectsEmptyLongAndFreeText() {
        XCTAssertEqual(StudySession.validateStudyID("   "), .failure(.empty))
        XCTAssertEqual(StudySession.validateStudyID(String(repeating: "A", count: 17)), .failure(.tooLong))
        XCTAssertEqual(StudySession.validateStudyID("John Smith"), .failure(.invalidCharacters))
        XCTAssertEqual(StudySession.validateStudyID("1990/01/01"), .failure(.invalidCharacters))
    }

    func testCaptureSetsAreOrderedByCreation() {
        let a = CaptureSet(stage: .afterClosure, positioning: Positioning(), createdAt: Date(timeIntervalSince1970: 200))
        let b = CaptureSet(stage: .preoperativeMarking, positioning: Positioning(), createdAt: Date(timeIntervalSince1970: 100))
        let s = StudySession(studyID: "S-1", captureSets: [a, b])
        XCTAssertEqual(s.orderedCaptureSets.map(\.id), [b.id, a.id])
    }

    func testUpdateReplacesExistingSetOrAppends() {
        var s = StudySession(studyID: "S-1")
        var set = CaptureSet(stage: .afterResection, positioning: Positioning())
        s.update(set)
        set.stage = .afterClosure
        s.update(set)
        XCTAssertEqual(s.captureSets.count, 1)
        XCTAssertEqual(s.captureSets.first?.stage, .afterClosure)
    }

    func testOperativeStageCustomLabelAndCodable() throws {
        let stage = OperativeStage.custom("After nipple reconstruction")
        XCTAssertEqual(stage.label, "After nipple reconstruction")
        let back = try JSONDecoder().decode(OperativeStage.self, from: JSONEncoder().encode(stage))
        XCTAssertEqual(back, stage)
        XCTAssertEqual(OperativeStage.presets.count, 5)
    }
}
