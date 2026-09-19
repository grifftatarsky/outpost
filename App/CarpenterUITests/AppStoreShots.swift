import XCTest

@MainActor
final class AppStoreShots: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OUTPOST_SHOTS"] == "1",
            "App Store screenshots: set TEST_RUNNER_OUTPOST_SHOTS=1")
        continueAfterFailure = true
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func launch(_ shot: String) -> XCUIApplication {
        XCUIDevice.shared.orientation = isPad ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments += ["--site-shot", shot, "-theme.accent", "verdigris"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        sleep(3)
        return app
    }

    private func shoot(_ name: String) {
        sleep(1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tapRow(_ app: XCUIApplication, _ prefix: String) -> Bool {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        guard row.waitForExistence(timeout: 5) else { return false }
        row.tap()
        sleep(2)
        return true
    }

    private func openArea(_ app: XCUIApplication, _ area: String) -> Bool {
        let list = app.collectionViews["Sidebar"]
        if !list.exists || !list.isHittable {
            let show = app.buttons["Show Sidebar"]
            if show.waitForExistence(timeout: 2) { show.tap() }
        }
        let row = list.buttons[area]
        guard row.waitForExistence(timeout: 3) else { return false }
        row.tap()
        sleep(2)
        return true
    }

    func testShots() {
        let rooms = launch("rooms")
        if isPad {
            XCTAssertTrue(tapRow(rooms, "Zeppelin Enthusiasts"), "no Zeppelin Enthusiasts row")
            shoot("01 rooms and a conversation")
        } else {
            shoot("01 rooms")
            XCTAssertTrue(tapRow(rooms, "Zeppelin Enthusiasts"), "no Zeppelin Enthusiasts row")
            shoot("02 conversation")
        }
        rooms.terminate()

        let outposts = launch("outposts")
        if isPad { _ = openArea(outposts, "Outposts") }
        XCTAssertTrue(tapRow(outposts, "Hastur"), "no Hastur in Outposts")
        shoot("03 somebody's outpost")
        if isPad, openArea(outposts, "Outposts"), tapRow(outposts, "Your Outpost") {
            shoot("04 who sees your outpost")
        }
        outposts.terminate()

        if !isPad {
            let audience = launch("audience")
            shoot("04 who sees your outpost")
            audience.terminate()
        }

        let compare = launch("compare")
        shoot("05 the ten characters")
        compare.terminate()

        let verify = launch("verify")
        shoot("06 who you are talking to")
        verify.terminate()
    }
}
