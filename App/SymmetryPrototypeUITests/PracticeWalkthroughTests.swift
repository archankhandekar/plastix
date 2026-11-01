import XCTest

/// Walks the virtual patient through the real app by tapping real controls, from the
/// research notice to Export and back to Sessions.
///
/// The app is launched without route-harness arguments, so it builds its real environment
/// (real stores, settings and navigator). `-UITestReset 1` (DEBUG only) wipes the defaults
/// and both store roots first, so every run starts at the research notice with no data.
///
/// Short pauses between the major steps keep a screen recording watchable. Set
/// `TEST_RUNNER_DEMO_STILLS_DIR` when running xcodebuild to also write a PNG of each key
/// moment into that folder; the same screenshots are always attached to the test result.
final class PracticeWalkthroughTests: XCTestCase {
    private var app: XCUIApplication!
    private var stillIndex = 0

    /// Pause between major steps, in seconds.
    private let beat: TimeInterval = 1.5
    private let timeout: TimeInterval = 15

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "1"]
    }

    func testVirtualPatientWalkthrough() throws {
        app.launch()

        // 1. The research notice, then Sessions.
        XCTAssertTrue(app.staticTexts["Research use only"].waitForExistence(timeout: timeout), "Research notice not shown")
        pause()
        still("research-notice")
        tap(app.buttons["I understand, start"])
        XCTAssertTrue(navTitle("Sessions").waitForExistence(timeout: timeout), "Sessions not shown")
        pause()
        still("sessions")

        // 2. Try the virtual patient: practice home.
        tap(button(beginningWith: "Try the virtual patient"))
        XCTAssertTrue(navTitle("Virtual patient").waitForExistence(timeout: timeout), "Practice home not shown")
        XCTAssertTrue(nextAction("See left and right for set 1").waitForExistence(timeout: timeout),
                      "Next action is not set 1's left and right")
        pause()
        still("practice-home")

        // 3. Follow Next to set 1's left and right, and tap each of the four differences.
        tap(nextAction("See left and right for set 1"))
        XCTAssertTrue(navTitle("Set 1").waitForExistence(timeout: timeout), "Set 1 result not shown")
        XCTAssertTrue(app.buttons["plateKey.nippleHeight"].waitForExistence(timeout: timeout), "Difference rows not shown")
        pause()
        still("set1-left-and-right")
        for metric in ["nippleHeight", "nippleMidline", "foldHeight", "outlineOverlap"] {
            let row = app.buttons["plateKey.\(metric)"]
            tap(row)
            XCTAssertTrue(waitFor(row, "isSelected == true"), "\(metric) did not come forward")
            pause(1)
        }
        still("set1-outline-overlap-focused")

        // 4. The obliques tab: side by side, Wipe, Switch side.
        tap(app.buttons["Obliques"])
        XCTAssertTrue(app.buttons["Wipe"].waitForExistence(timeout: timeout), "Obliques tab not shown")
        pause()
        still("set1-obliques")
        tap(app.buttons["Wipe"])
        XCTAssertTrue(waitFor(app.buttons["Wipe"], "isSelected == true"), "Wipe not selected")
        pause()
        tap(app.buttons["Switch side"])
        XCTAssertTrue(waitFor(app.buttons["Switch side"], "isSelected == true"), "Switch side not selected")
        pause()

        // Set 2 is measured too, so Next offers its left and right before any marking.
        tap(nextAction("See left and right for set 2"))
        XCTAssertTrue(navTitle("Set 2").waitForExistence(timeout: timeout), "Set 2 result not shown")
        pause()

        // 5. Back to the home, then mark set 3 from the practice tour with the teaching aid.
        goBack()
        XCTAssertTrue(navTitle("Set 1").waitForExistence(timeout: timeout), "Back did not return to set 1")
        pause(1)
        goBack()
        XCTAssertTrue(navTitle("Virtual patient").waitForExistence(timeout: timeout), "Not back on practice home")
        pause()
        openTourTask("Mark the points on set 3.")
        XCTAssertTrue(navTitle("Mark points").waitForExistence(timeout: timeout), "Point editor not shown for set 3")
        pause()
        markAllPointsWithTeachingAid(stillName: "set3-points-placed")
        tap(app.buttons["Save and see left and right"])
        XCTAssertTrue(navTitle("Set 3").waitForExistence(timeout: timeout), "Set 3 result not shown after saving")
        pause()
        still("set3-left-and-right")

        // 6. A new photo set at the next stage with the virtual camera.
        goBack()
        XCTAssertTrue(navTitle("Virtual patient").waitForExistence(timeout: timeout), "Not back on practice home")
        pause()
        openTourTask("Take set 4 with the virtual camera.")
        XCTAssertTrue(navTitle("New photo set").waitForExistence(timeout: timeout), "New photo set sheet not shown")
        // Pre-filled from set 3: the next stage is suggested, not the first preset.
        XCTAssertTrue(app.staticTexts["Suggested because the last set was After fat grafting."]
            .waitForExistence(timeout: timeout), "New photo set is not pre-filled from set 3")
        pause()
        still("new-photo-set")
        tap(app.buttons["Start the camera"])
        for angle in ["frontal", "left oblique", "right oblique"] {
            let shutter = app.buttons["Take \(angle) photo"]
            XCTAssertTrue(shutter.waitForExistence(timeout: timeout), "Virtual camera not showing \(angle)")
            XCTAssertTrue(waitFor(shutter, "isEnabled == true"), "Shutter not ready for \(angle)")
            pause(1)
            if angle == "frontal" { still("virtual-camera-frontal") }
            shutter.tap()
            let use = app.buttons["Use this photo"]
            let keepAnyway = app.buttons["Keep anyway"]
            XCTAssertTrue(waitForAny([use, keepAnyway]), "Photo check not shown for \(angle)")
            pause(1)
            if angle == "frontal" { still("photo-check-frontal") }
            tap(use.exists ? use : keepAnyway)
        }
        XCTAssertTrue(navTitle("Virtual patient").waitForExistence(timeout: timeout), "Camera did not close to the home")
        XCTAssertTrue(nextAction("Mark the points on set 4").waitForExistence(timeout: timeout),
                      "Next action is not marking set 4")
        pause()

        // 7. Set 4: mark its points, then see its left and right.
        tap(nextAction("Mark the points on set 4"))
        XCTAssertTrue(navTitle("Mark points").waitForExistence(timeout: timeout), "Point editor not shown for set 4")
        pause()
        markAllPointsWithTeachingAid(stillName: nil)
        tap(app.buttons["Save and see left and right"])
        XCTAssertTrue(navTitle("Set 4").waitForExistence(timeout: timeout), "Set 4 result not shown after saving")
        XCTAssertTrue(app.buttons["plateKey.nippleHeight"].waitForExistence(timeout: timeout), "Set 4 differences not shown")
        XCTAssertTrue(app.staticTexts["Set 4, after closure"].exists, "Set 4 does not carry the suggested stage")
        pause()
        still("set4-left-and-right")
        tap(app.buttons["Obliques"])
        XCTAssertTrue(app.buttons["Wipe"].waitForExistence(timeout: timeout), "Set 4 obliques not shown")
        pause()

        // 8. Across stages, by the Next action.
        tap(nextAction("See how each difference changed across stages"))
        XCTAssertTrue(navTitle("Across stages").waitForExistence(timeout: timeout), "Across stages not shown")
        pause()
        still("across-stages")

        // 9. Export: the practice refusal and the preview.
        tap(nextAction("See what a report would contain"))
        XCTAssertTrue(navTitle("Export").waitForExistence(timeout: timeout), "Export not shown")
        XCTAssertTrue(app.staticTexts["Practice sessions are not exported. Start a study session to export."]
            .waitForExistence(timeout: timeout), "Practice refusal not shown")
        pause()
        tap(button(beginningWith: "Preview what a report contains"))
        pause()
        still("export-practice-refusal")

        // 10. Back to Sessions.
        var hops = 0
        while !navTitle("Sessions").exists && hops < 6 {
            goBack()
            pause(1)
            hops += 1
        }
        XCTAssertTrue(navTitle("Sessions").waitForExistence(timeout: timeout), "Did not return to Sessions")
        XCTAssertTrue(button(beginningWith: "Open the virtual patient").waitForExistence(timeout: timeout),
                      "Sessions does not offer to open the virtual patient")
        pause()
        still("sessions-again")
    }

    // MARK: - Steps

    /// Turns on the teaching aid, taps where each of the six points goes, checks the points.
    private func markAllPointsWithTeachingAid(stillName: String?) {
        let aid = app.buttons["Show where the points go"]
        XCTAssertTrue(aid.waitForExistence(timeout: timeout), "Teaching aid not offered")
        tap(aid)
        XCTAssertTrue(waitFor(aid, "value == 'On'"), "Teaching aid did not turn on")
        pause()
        let marker = app.descendants(matching: .any)["markPoints.nextPoint"]
        for n in 1...6 {
            XCTAssertTrue(marker.waitForExistence(timeout: timeout), "No next point shown for point \(n)")
            let frame = marker.frame
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
            pause(0.8)
        }
        XCTAssertTrue(app.staticTexts["6 of 6 points placed"].waitForExistence(timeout: timeout), "Six points not placed")
        XCTAssertTrue(app.buttons["Save and see left and right"].waitForExistence(timeout: timeout),
                      "Saving would not show left and right")
        let check = app.buttons["Check my points"]
        if check.exists {
            tap(check)
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'its ring'")).firstMatch
                .waitForExistence(timeout: timeout), "Check my points showed no lines")
            pause(1)
            // Bring the per-point check lines into view.
            scrollUp(by: 0.14)
            pause(1)
        }
        if let stillName { still(stillName) }
    }

    /// Opens the practice tour on the home and taps one of its tasks.
    private func openTourTask(_ title: String) {
        // Task rows read "To do. <title>" or "Done. <title>"; the summary row also ends with
        // the next task's title, so match the row labels exactly.
        let task = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@",
                                                    "To do. " + title, "Done. " + title)).firstMatch
        if !task.exists {
            tap(button(beginningWith: "Practice tour"))
        }
        XCTAssertTrue(task.waitForExistence(timeout: timeout), "Tour task not shown: \(title)")
        pause(1)
        tap(task)
    }

    // MARK: - Helpers

    private func navTitle(_ title: String) -> XCUIElement {
        app.navigationBars[title]
    }

    private func nextAction(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'nextAction.primary' AND label == %@", title)).firstMatch
    }

    private func button(beginningWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// The navigation bar's back button (or the editor's own Back).
    private func goBack() {
        let bar = app.navigationBars.firstMatch
        let back = bar.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: timeout), "No back button")
        back.tap()
    }

    /// Scrolls the element into view when needed, then taps it.
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Not found: \(element)", file: file, line: line)
        var swipes = 0
        while (!element.isHittable || isUnderBottomBar(element)) && swipes < 8 {
            scrollUp()
            swipes += 1
        }
        XCTAssertTrue(element.isHittable, "Not hittable: \(element)", file: file, line: line)
        element.tap()
    }

    /// True when the element's centre sits under a pinned bottom bar (the Next action bar or
    /// the point editor's Save bar), where a tap would land on the bar instead. XCUITest
    /// still reports such an element as hittable.
    private func isUnderBottomBar(_ element: XCUIElement) -> Bool {
        // Each pinned button, with how far its bar reaches above it (detail line, padding).
        let bars: [(XCUIElement, CGFloat)] = [
            (app.buttons["nextAction.primary"].firstMatch, 72),
            (app.buttons["Save and see left and right"].firstMatch, 24),
            (app.buttons["Save and go back"].firstMatch, 24),
        ]
        for (bar, reach) in bars where bar.exists {
            if element.identifier == bar.identifier && element.label == bar.label { continue }
            let barTop = bar.frame.minY - reach
            if element.frame.midY > barTop && element.frame.midY < app.frame.maxY { return true }
        }
        return false
    }

    /// Scrolls the content up by about a third of the screen. Starts low on the screen, so on
    /// the point editor it drags the lower panel and never the photo, then lets the scroll
    /// settle so the next tap lands where the element is now.
    private func scrollUp(by fraction: CGFloat = 0.32) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82 - fraction))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        pause(0.8)
    }

    private func waitFor(_ element: XCUIElement, _ predicate: String, timeout: TimeInterval? = nil) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout ?? self.timeout) == .completed
    }

    private func waitForAny(_ elements: [XCUIElement]) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: \.exists) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    private func pause(_ seconds: TimeInterval? = nil) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds ?? beat))
    }

    /// Attaches a screenshot to the result and, when TEST_RUNNER_DEMO_STILLS_DIR (seen here as
    /// DEMO_STILLS_DIR) is set, writes it there as NN-name.png.
    private func still(_ name: String) {
        stillIndex += 1
        let shot = XCUIScreen.main.screenshot()
        let filename = String(format: "%02d-%@", stillIndex, name)
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = filename
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["DEMO_STILLS_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent(filename + ".png")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: url)
        }
    }
}
