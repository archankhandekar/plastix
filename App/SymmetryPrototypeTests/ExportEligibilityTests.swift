import XCTest
import SymmetryModels
@testable import SymmetryPrototype

/// Practice is refused by either marker: the session kind or the reserved DEMO- code.
final class ExportEligibilityTests: XCTestCase {
    func testTruthTable() {
        let cases: [(SessionKind, String, ExportEligibility)] = [
            (.study, "S-014", .allowed),
            (.study, "DEMOX", .allowed),
            (.study, "DEM-1", .allowed),
            (.study, "S-DEMO-1", .allowed),
            (.study, "DEMO-VP1", .practiceRefused),
            (.study, "demo-vp1", .practiceRefused),
            (.study, "Demo-7", .practiceRefused),
            (.study, "DEMO", .practiceRefused),
            (.study, "demo", .practiceRefused),
            (.study, "DEMO-", .practiceRefused),
            (.practice, "S-014", .practiceRefused),
            (.practice, "DEMO-VP1", .practiceRefused),
            (.practice, "", .practiceRefused),
        ]
        for (kind, code, expected) in cases {
            XCTAssertEqual(ExportEligibility.check(kind: kind, studyID: code), expected, "\(kind) \(code)")
        }
        XCTAssertEqual(ExportEligibility.check(kind: .study, studyID: PracticeStore.studyID), .practiceRefused)
    }

    func testRefusalMessage() {
        XCTAssertEqual(ExportEligibility.refusalMessage, "Practice sessions are not exported. Start a study session to export.")
    }

    func testStudyIDCheckRejectsTheReservedPrefixFirst() {
        XCTAssertEqual(StudyIDCheck.reservedPrefix, "DEMO-")
        XCTAssertTrue(StudyIDCheck.isReserved("DEMO-7"))
        XCTAssertTrue(StudyIDCheck.isReserved(" demo-7 "))
        XCTAssertTrue(StudyIDCheck.isReserved("DEMO"))
        XCTAssertFalse(StudyIDCheck.isReserved("S-014"))
        XCTAssertFalse(StudyIDCheck.isReserved("DEMOGRAPHIC"))

        let message = "DEMO- is kept for the virtual patient. Choose another code."
        XCTAssertEqual(StudyIDCheck.reservedMessage, message)
        XCTAssertEqual(StudyIDCheck.validateNewStudyID("DEMO-7"), .failure(message))
        // The reserved check runs before validateStudyID, so even an invalid DEMO- code gets it.
        XCTAssertEqual(StudyIDCheck.validateNewStudyID("DEMO-a b"), .failure(message))
    }

    func testStudyIDCheckFallsBackToValidateStudyID() {
        XCTAssertEqual(StudyIDCheck.validateNewStudyID("  S-014 "), .success("S-014"))
        XCTAssertEqual(StudyIDCheck.validateNewStudyID(""), .failure(StudySession.StudyIDError.empty.message))
        XCTAssertEqual(StudyIDCheck.validateNewStudyID("ABCDEFGHIJKLMNOPQ"), .failure(StudySession.StudyIDError.tooLong.message))
        XCTAssertEqual(StudyIDCheck.validateNewStudyID("Jane Doe"), .failure(StudySession.StudyIDError.invalidCharacters.message))
    }
}
