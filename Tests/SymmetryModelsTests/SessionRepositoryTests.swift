import XCTest
import SymmetryCore
@testable import SymmetryModels

final class SessionRepositoryTests: XCTestCase {
    private var root: URL!
    private var repo: SessionRepository!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SymmetryRepoTests-\(UUID().uuidString)")
        repo = try SessionRepository(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSaveAndLoadRoundTrip() throws {
        var session = StudySession(studyID: "S-014", notes: "n")
        var set = CaptureSet(stage: .afterImplantOrExpander, positioning: Positioning(tableAngle: "30°"))
        var capture = Capture(angle: .frontal, imageFilename: "frontal.jpg", pixelWidth: 10, pixelHeight: 20, quality: nil, tiltDegrees: 2.5)
        var lm = LandmarkSet(imageSize: capture.imageSize)
        lm[.sternalNotch] = Point2D(x: 5, y: 2)
        capture.landmarks = lm
        set.captures[.frontal] = capture
        session.update(set)
        try repo.save(session)
        let loaded = repo.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.studyID, "S-014")
        XCTAssertEqual(loaded.first?.captureSets.first?.captures[.frontal]?.landmarks, lm)
        XCTAssertEqual(loaded.first?.captureSets.first?.positioning.tableAngle, "30°")
    }

    func testImagesAreStoredBesideTheSessionAndDeletedWithIt() throws {
        let session = StudySession(studyID: "S-1")
        try repo.save(session)
        let capture = Capture(angle: .frontal, imageFilename: "frontal.jpg", pixelWidth: 1, pixelHeight: 1, quality: nil, tiltDegrees: nil)
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xD9])
        try repo.writeImage(bytes, for: capture, in: session)
        XCTAssertEqual(repo.readImage(for: capture, in: session), bytes)
        XCTAssertEqual(repo.imageURL(for: capture, in: session).lastPathComponent, "frontal.jpg")
        try repo.delete(session)
        XCTAssertNil(repo.readImage(for: capture, in: session))
        XCTAssertTrue(repo.loadAll().isEmpty)
    }

    func testDeleteAllRemovesEverySession() throws {
        try repo.save(StudySession(studyID: "A"))
        try repo.save(StudySession(studyID: "B"))
        XCTAssertEqual(repo.loadAll().count, 2)
        try repo.deleteAll()
        XCTAssertTrue(repo.loadAll().isEmpty)
    }

    func testLoadAllIgnoresCorruptSessions() throws {
        try repo.save(StudySession(studyID: "A"))
        let bad = root.appendingPathComponent("not-a-session", isDirectory: true)
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try Data("{broken".utf8).write(to: bad.appendingPathComponent("session.json"))
        XCTAssertEqual(repo.loadAll().count, 1)
    }

    func testDeletingMissingSessionDoesNotThrow() throws {
        XCTAssertNoThrow(try repo.delete(StudySession(studyID: "ghost")))
    }
}

final class SessionRepositoryCleanupTests: XCTestCase {
    private var root: URL!
    private var repo: SessionRepository!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SymmetryRepoCleanup-\(UUID().uuidString)")
        repo = try SessionRepository(root: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testDeleteImageRemovesOnlyThatFile() throws {
        let session = StudySession(studyID: "S-1")
        try repo.save(session)
        let a = Capture(angle: .frontal, imageFilename: "a.jpg", pixelWidth: 1, pixelHeight: 1, quality: nil, tiltDegrees: nil)
        let b = Capture(angle: .leftOblique, imageFilename: "b.jpg", pixelWidth: 1, pixelHeight: 1, quality: nil, tiltDegrees: nil)
        try repo.writeImage(Data([1]), for: a, in: session)
        try repo.writeImage(Data([2]), for: b, in: session)
        try repo.deleteImage(for: a, in: session)
        XCTAssertNil(repo.readImage(for: a, in: session))
        XCTAssertEqual(repo.readImage(for: b, in: session), Data([2]))
        XCTAssertEqual(repo.loadAll().count, 1)
        XCTAssertNoThrow(try repo.deleteImage(for: a, in: session)) // already gone
    }

    func testDeleteAllRemovesUndecodableSessionDirectoriesToo() throws {
        try repo.save(StudySession(studyID: "A"))
        let bad = root.appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try Data("{broken".utf8).write(to: bad.appendingPathComponent("session.json"))
        try Data([1, 2, 3]).write(to: bad.appendingPathComponent("frontal.jpg"))
        try repo.deleteAll()
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertTrue(remaining.isEmpty, "left behind: \(remaining)")
    }
}
