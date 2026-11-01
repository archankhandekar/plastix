import SwiftUI
import XCTest
import SymmetryCore
@testable import SymmetryPrototype

/// The DEBUG route harness's argument parser: every key, its default and unknown values.
final class LaunchRouteTests: XCTestCase {
    private func parse(_ args: String) -> LaunchRoute? {
        LaunchRoute.parse(["/path/to/SymmetryPrototype"] + args.split(separator: " ").map(String.init))
    }

    func testNilWithoutUIRoute() {
        XCTAssertNil(LaunchRoute.parse([]))
        XCTAssertNil(LaunchRoute.parse(["/app"]))
        XCTAssertNil(parse("-UIDemo 1 -UIStage 2 -UIScheme dark"))
        // A trailing -UIRoute with no value is not a route.
        XCTAssertNil(parse("-UIRoute"))
    }

    func testDefaults() throws {
        let r = try XCTUnwrap(parse("-UIRoute home"))
        XCTAssertEqual(r.route, .home)
        XCTAssertTrue(r.demo)
        XCTAssertNil(r.demoArgument)
        XCTAssertFalse(r.seedStudy)
        XCTAssertTrue(r.skipNotice)
        XCTAssertNil(r.stage)
        XCTAssertEqual(r.resolvedStage, 1)
        XCTAssertEqual(r.focus, .all)
        XCTAssertNil(r.state)
        XCTAssertFalse(r.showTruth)
        XCTAssertEqual(r.obliqueMode, .sideBySide)
        XCTAssertNil(r.captureAngle)
        XCTAssertFalse(r.practiceRetake)
        XCTAssertNil(r.studyCode)
        XCTAssertNil(r.scheme)
        XCTAssertNil(r.textSize)
        XCTAssertFalse(r.staticMotion)
        XCTAssertFalse(r.targetsStudy)
    }

    func testEveryRouteName() throws {
        XCTAssertEqual(LaunchRoute.Name.allCases.count, 18)
        for name in LaunchRoute.Name.allCases {
            XCTAssertEqual(try XCTUnwrap(parse("-UIRoute \(name.rawValue)")).route, name)
        }
        XCTAssertEqual(parse("-UIRoute newSession")?.route, .newSession)
        XCTAssertEqual(parse("-UIRoute newSet")?.route, .newSet)
    }

    func testUnknownRouteFallsBackToSessions() {
        XCTAssertEqual(parse("-UIRoute nowhere")?.route, .sessions)
        XCTAssertEqual(parse("-UIRoute Home")?.route, .sessions)
    }

    func testStageDefaultsPerRoute() {
        XCTAssertEqual(parse("-UIRoute mark")?.resolvedStage, 3)
        XCTAssertEqual(parse("-UIRoute capture")?.resolvedStage, 4)
        XCTAssertEqual(parse("-UIRoute symmetry")?.resolvedStage, 1)
        XCTAssertEqual(parse("-UIRoute photocheck")?.resolvedStage, 1)
        XCTAssertEqual(parse("-UIRoute mark -UIStage 1")?.resolvedStage, 1)
        XCTAssertEqual(parse("-UIRoute symmetry -UIStage 2")?.resolvedStage, 2)
        // Out of range or not a number: the default.
        XCTAssertEqual(parse("-UIRoute symmetry -UIStage 9")?.resolvedStage, 1)
        XCTAssertEqual(parse("-UIRoute mark -UIStage two")?.resolvedStage, 3)
        XCTAssertNil(parse("-UIRoute symmetry -UIStage 0")?.stage)
    }

    func testNoticeAndSkipNotice() {
        XCTAssertEqual(parse("-UIRoute notice")?.skipNotice, false)
        XCTAssertEqual(parse("-UIRoute sessions")?.skipNotice, true)
        XCTAssertEqual(parse("-UIRoute notice -UISkipNotice 1")?.skipNotice, true)
        XCTAssertEqual(parse("-UIRoute home -UISkipNotice 0")?.skipNotice, false)
    }

    func testDemoAndSeedStudy() throws {
        let sessionsStudy = try XCTUnwrap(parse("-UIRoute sessions -UISeedStudy 1"))
        XCTAssertTrue(sessionsStudy.seedStudy)
        XCTAssertFalse(sessionsStudy.demo, "sessions with -UISeedStudy does not seed the virtual patient by default")
        XCTAssertTrue(sessionsStudy.targetsStudy)

        let exportStudy = try XCTUnwrap(parse("-UIRoute export -UISeedStudy 1 -UIDemo 0"))
        XCTAssertFalse(exportStudy.demo)
        XCTAssertEqual(exportStudy.demoArgument, false)
        XCTAssertTrue(exportStudy.targetsStudy)

        let both = try XCTUnwrap(parse("-UIRoute home -UISeedStudy 1 -UIDemo 1"))
        XCTAssertTrue(both.demo)
        XCTAssertFalse(both.targetsStudy, "an explicit -UIDemo 1 targets the virtual patient")

        let homeStudy = try XCTUnwrap(parse("-UIRoute home -UISeedStudy 1"))
        XCTAssertTrue(homeStudy.demo)
        XCTAssertTrue(homeStudy.targetsStudy)

        XCTAssertEqual(parse("-UIRoute home -UIDemo 0")?.demo, false)
        XCTAssertEqual(parse("-UIRoute home -UIDemo maybe")?.demo, true)
    }

    func testFocusStateAndModes() {
        XCTAssertEqual(parse("-UIRoute symmetry -UIFocus nippleHeight")?.focus, .nippleHeight)
        XCTAssertEqual(parse("-UIRoute symmetry -UIFocus nippleMidline")?.focus, .nippleMidline)
        XCTAssertEqual(parse("-UIRoute symmetry -UIFocus foldHeight")?.focus, .foldHeight)
        XCTAssertEqual(parse("-UIRoute symmetry -UIFocus outlines")?.focus, .outlines)
        XCTAssertEqual(parse("-UIRoute symmetry -UIFocus all")?.focus, .all)
        XCTAssertEqual(parse("-UIRoute symmetry -UIFocus elsewhere")?.focus, .all)

        for state in LaunchRoute.SeedState.allCases {
            XCTAssertEqual(parse("-UIRoute symmetry -UIState \(state.rawValue)")?.state, state)
        }
        XCTAssertEqual(LaunchRoute.SeedState.allCases.map(\.rawValue),
                       ["complete", "unmarked", "missingFold", "noOutlines", "blurredKept"])
        XCTAssertNil(parse("-UIRoute symmetry -UIState broken")?.state)

        XCTAssertEqual(parse("-UIRoute obliques -UIObliqueMode pair")?.obliqueMode, .sideBySide)
        XCTAssertEqual(parse("-UIRoute obliques -UIObliqueMode wipe")?.obliqueMode, .wipe)
        XCTAssertEqual(parse("-UIRoute obliques -UIObliqueMode switch")?.obliqueMode, .switchSide)
        XCTAssertEqual(parse("-UIRoute obliques -UIObliqueMode spin")?.obliqueMode, .sideBySide)
    }

    func testCaptureAndMarkingFlags() throws {
        XCTAssertEqual(parse("-UIRoute capture -UICaptureAngle frontal")?.captureAngle, .frontal)
        XCTAssertEqual(parse("-UIRoute capture -UICaptureAngle leftOblique")?.captureAngle, .leftOblique)
        XCTAssertEqual(parse("-UIRoute capture -UICaptureAngle rightOblique")?.captureAngle, .rightOblique)
        XCTAssertNil(try XCTUnwrap(parse("-UIRoute capture -UICaptureAngle back")).captureAngle)

        XCTAssertEqual(parse("-UIRoute photocheck -UIPracticeRetake 1")?.practiceRetake, true)
        XCTAssertEqual(parse("-UIRoute photocheck -UIPracticeRetake 0")?.practiceRetake, false)
        XCTAssertEqual(parse("-UIRoute mark -UIShowTruth 1")?.showTruth, true)
        XCTAssertEqual(parse("-UIRoute mark -UIShowTruth true")?.showTruth, true)
        XCTAssertEqual(parse("-UIRoute newSession -UIStudyCode DEMO-7")?.studyCode, "DEMO-7")
    }

    func testAppearance() {
        XCTAssertEqual(parse("-UIRoute home -UIScheme light")?.scheme, .light)
        XCTAssertEqual(parse("-UIRoute home -UIScheme dark")?.scheme, .dark)
        XCTAssertNil(parse("-UIRoute home -UIScheme sepia")?.scheme)

        XCTAssertEqual(parse("-UIRoute home -UITextSize large")?.textSize, .large)
        XCTAssertEqual(parse("-UIRoute home -UITextSize xxxLarge")?.textSize, .xxxLarge)
        let accessibility: [DynamicTypeSize] = [.accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5]
        for (i, size) in accessibility.enumerated() {
            XCTAssertEqual(parse("-UIRoute home -UITextSize accessibility\(i + 1)")?.textSize, size)
        }
        XCTAssertNil(parse("-UIRoute home -UITextSize huge")?.textSize)

        XCTAssertEqual(parse("-UIRoute home -UIStatic 1")?.staticMotion, true)
        XCTAssertEqual(parse("-UIRoute home -UIStatic 0")?.staticMotion, false)
    }

    func testTheScreenshotCommandLine() throws {
        // The argument order scripts/screens.sh uses: appearance first, then the route row.
        let r = try XCTUnwrap(parse("-UIStatic 1 -UIScheme dark -UITextSize accessibility3 -UIRoute symmetry -UIStage 2 -UIFocus nippleHeight"))
        XCTAssertEqual(r.route, .symmetry)
        XCTAssertEqual(r.resolvedStage, 2)
        XCTAssertEqual(r.focus, .nippleHeight)
        XCTAssertEqual(r.scheme, .dark)
        XCTAssertEqual(r.textSize, .accessibility3)
        XCTAssertTrue(r.staticMotion)
        // Unrelated launch arguments (for example XCTest's) are ignored.
        XCTAssertEqual(LaunchRoute.parse(["-ApplePersistenceIgnoreState", "YES", "-UIRoute", "gallery"])?.route, .gallery)
    }
}
