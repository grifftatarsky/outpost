import XCTest

@MainActor
final class WideLayoutTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OUTPOST_WIDE"] == "1",
            "a wide-layout run: set TEST_RUNNER_OUTPOST_WIDE=1 and run on an iPad")
        continueAfterFailure = true
    }

    private func launch(_ shot: String, _ orientation: UIDeviceOrientation) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments += ["--site-shot", shot, "-theme.accent", "verdigris"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        return app
    }

    private func shoot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func audit(_ app: XCUIApplication, _ screen: String) {
        do {
            try app.performAccessibilityAudit(for: .all) { issue in
                let described = "\(screen): \(issue.auditType) — \(issue.compactDescription) — \(issue.element?.debugDescription.prefix(160) ?? "no element")"
                let attachment = XCTAttachment(string: described)
                attachment.name = "audit \(screen)"
                attachment.lifetime = .keepAlways
                self.add(attachment)
                return false
            }
        } catch {
            XCTFail("\(screen): \(error)")
        }
    }

    private func sidebar(_ app: XCUIApplication) -> XCUIElement {
        let list = app.collectionViews["Sidebar"]
        if !list.exists || !list.isHittable {
            let show = app.buttons["Show Sidebar"]
            if show.waitForExistence(timeout: 2) { show.tap() }
            _ = list.waitForExistence(timeout: 3)
        }
        return list
    }

    private func open(_ app: XCUIApplication, area: String, _ label: String) -> Bool {
        let row = sidebar(app).buttons[area]
        guard row.waitForExistence(timeout: 3) else {
            XCTFail("\(label): the sidebar has no \(area)")
            return false
        }
        row.tap()
        sleep(2)
        return true
    }

    private func tapRow(_ app: XCUIApplication, _ prefix: String) -> Bool {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        guard row.waitForExistence(timeout: 5) else { return false }
        if !row.isHittable { app.swipeUp() }
        row.tap()
        sleep(2)
        return true
    }

    private func walk(_ orientation: UIDeviceOrientation, _ label: String) {
        let app = launch("rooms", orientation)
        sleep(2)
        shoot("\(label) 01 rooms")
        audit(app, "\(label) rooms")

        if tapRow(app, "Hangar 7") {
            shoot("\(label) 02 room open")
            audit(app, "\(label) room open")
        } else {
            XCTFail("\(label): no Hangar 7 row")
        }

        _ = sidebar(app)
        shoot("\(label) 03 sidebar")

        if open(app, area: "Outposts", label) {
            shoot("\(label) 04 outposts")
            audit(app, "\(label) outposts")
            if tapRow(app, "Your Outpost") {
                shoot("\(label) 05 own outpost")
                audit(app, "\(label) own outpost")
            }
        }

        if open(app, area: "Search", label) {
            let field = app.searchFields.firstMatch
            if field.waitForExistence(timeout: 3) {
                field.tap()
                field.typeText("zeppelin")
                sleep(2)
            }
            shoot("\(label) 06 search")
            audit(app, "\(label) search")
        }

        if open(app, area: "You", label) {
            shoot("\(label) 07 you")
            audit(app, "\(label) you")
            if tapRow(app, "Appearance") {
                shoot("\(label) 08 appearance")
                audit(app, "\(label) appearance")
            }
        }
    }

    func testYouOpensFromSearchWithTheKeyboardUp() {
        let app = launch("rooms", .landscapeLeft)
        sleep(2)
        _ = open(app, area: "Search", "search to you")
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 3) {
            field.tap()
            field.typeText("zep")
        }
        _ = open(app, area: "You", "search to you")
        let appearance = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Appearance")).firstMatch
        XCTAssertTrue(
            appearance.waitForExistence(timeout: 4),
            "choosing You while searching opened another area")
        shoot("search to you")
    }

    func testPortrait() { walk(.portrait, "portrait") }

    func testLandscape() { walk(.landscapeLeft, "landscape") }
}
