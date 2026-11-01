import XCTest
import SymmetryModels
@testable import SymmetryPrototype

/// UI-only flags over a wiped UserDefaults suite.
final class UIFlagsTests: XCTestCase {
    private let suiteName = "UIFlagsTests"
    private var suite: UserDefaults!

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        suite = UserDefaults(suiteName: suiteName)
        UIFlags.defaults = suite
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        UIFlags.defaults = .standard
        super.tearDown()
    }

    private func session(sets: Int) -> StudySession {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let captureSets = (0..<sets).map {
            CaptureSet(stage: .preoperativeMarking, positioning: Positioning(), createdAt: t0.addingTimeInterval(Double($0) * 60))
        }
        return StudySession(studyID: "S-014", captureSets: captureSets)
    }

    func testViewedRoundTrips() {
        let s = session(sets: 3)
        let ids = s.orderedCaptureSets.map(\.id)
        XCTAssertFalse(UIFlags.hasViewed(setID: ids[0]))
        XCTAssertEqual(UIFlags.viewedSetIDs(in: s), [])
        UIFlags.markViewed(setID: ids[0])
        UIFlags.markViewed(setID: ids[2])
        XCTAssertTrue(UIFlags.hasViewed(setID: ids[0]))
        XCTAssertFalse(UIFlags.hasViewed(setID: ids[1]))
        XCTAssertEqual(UIFlags.viewedSetIDs(in: s), [ids[0], ids[2]])
        XCTAssertTrue(suite.bool(forKey: "viewed-" + ids[0].uuidString))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "viewed-" + ids[0].uuidString))
    }

    func testStagesRoundTripsAndCountsTheLegacyKey() {
        let a = UUID(), b = UUID()
        XCTAssertFalse(UIFlags.hasOpenedStages(sessionID: a))
        UIFlags.markOpenedStages(sessionID: a)
        XCTAssertTrue(UIFlags.hasOpenedStages(sessionID: a))
        XCTAssertTrue(suite.bool(forKey: "stages-" + a.uuidString))

        XCTAssertFalse(UIFlags.hasOpenedStages(sessionID: b))
        suite.set(true, forKey: "compared-" + b.uuidString)
        XCTAssertTrue(UIFlags.hasOpenedStages(sessionID: b))
    }

    func testObliquesRoundTrips() {
        let a = UUID()
        XCTAssertFalse(UIFlags.hasSeenObliques(sessionID: a))
        UIFlags.markSeenObliques(sessionID: a)
        XCTAssertTrue(UIFlags.hasSeenObliques(sessionID: a))
        XCTAssertTrue(suite.bool(forKey: "obliques-" + a.uuidString))
    }

    func testClearRemovesEveryFlagOfTheSession() {
        let s = session(sets: 2)
        let other = session(sets: 1)
        for set in s.captureSets + other.captureSets { UIFlags.markViewed(setID: set.id) }
        UIFlags.markOpenedStages(sessionID: s.id)
        UIFlags.markSeenObliques(sessionID: s.id)
        suite.set(true, forKey: "compared-" + s.id.uuidString)
        UIFlags.markOpenedStages(sessionID: other.id)

        UIFlags.clear(session: s)
        XCTAssertEqual(UIFlags.viewedSetIDs(in: s), [])
        XCTAssertFalse(UIFlags.hasOpenedStages(sessionID: s.id))
        XCTAssertFalse(UIFlags.hasSeenObliques(sessionID: s.id))
        XCTAssertNil(suite.object(forKey: "compared-" + s.id.uuidString))
        // Another session keeps its flags.
        XCTAssertEqual(UIFlags.viewedSetIDs(in: other), Set(other.captureSets.map(\.id)))
        XCTAssertTrue(UIFlags.hasOpenedStages(sessionID: other.id))
    }
}
