import XCTest

final class AccentContrastAuditTests: XCTestCase {

    private func audit(accent: String) {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["--quiet-for-audit", "-theme.accent", accent]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "\(accent): the app never came up")

        for tab in ["Solos", "You"] {
            let button = app.buttons[tab]
            guard button.waitForExistence(timeout: 8) else {
                XCTFail("\(accent): the \(tab) tab never appeared")
                continue
            }
            button.tap()
            do {
                try app.performAccessibilityAudit(for: .contrast)
            } catch {
                XCTFail("\(accent): the audit could not run on \(tab): \(error)")
            }
        }
        app.terminate()
    }

    func testCobalt() { audit(accent: "cobalt") }
    func testVerdigris() { audit(accent: "verdigris") }
    func testSignalAmber() { audit(accent: "signalAmber") }
    func testOxblood() { audit(accent: "oxblood") }
    func testAubergine() { audit(accent: "aubergine") }
    func testHangarSlate() { audit(accent: "hangarSlate") }
    func testOliveDrab() { audit(accent: "oliveDrab") }
    func testMonochrome() { audit(accent: "monochrome") }
}
