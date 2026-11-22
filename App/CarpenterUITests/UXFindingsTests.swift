import XCTest

@MainActor
final class UXFindingsTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func open(_ shot: String, textSize: String? = nil) {
        app = XCUIApplication()
        app.launchArguments = ["--copy-shot", shot, "-theme.accent", "verdigris"]
        if let textSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize] }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "the app never came up")
    }

    private func photograph(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLettingSomebodyInIsNeverInALongPressMenu() {
        open("members")
        let invited = app.buttons.containing(.staticText, identifier: "Thale").firstMatch
        XCTAssertTrue(invited.waitForExistence(timeout: 10), "the invited person is not a button")
        invited.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Show the characters"].waitForExistence(timeout: 5), "the menu did not open")
        photograph("members › long-press menu")
        XCTAssertFalse(app.buttons["Let them in"].exists, "admitting somebody is still one long-press away")
        XCTAssertFalse(app.buttons["Do not let them in"].exists)
        app.buttons["Show the characters"].tap()

        XCTAssertTrue(
            app.staticTexts["K, 9, F, 4, V, 9, T, R, 2, M"].waitForExistence(timeout: 5),
            "the characters are not shown, one by one, to VoiceOver")
        XCTAssertTrue(app.buttons["Admit"].exists, "the card with the characters has no Admit")
        photograph("members › the join check")
    }

    func testRemovingSomebodyIsOnTheirPage() {
        open("members")
        let hastur = app.buttons.containing(.staticText, identifier: "Hastur").firstMatch
        XCTAssertTrue(hastur.waitForExistence(timeout: 10))
        hastur.tap()
        let remove = app.buttons.containing(.staticText, identifier: "Remove from Hangar 7").firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "the person's page offers no way to remove them")
        photograph("members › a member's page")
        remove.tap()
        XCTAssertTrue(
            app.staticTexts["Remove Hastur?"].waitForExistence(timeout: 5),
            "tapping Remove did not open the decision sheet")
        photograph("members › removing from the member's page")
    }

    func testEraseAlertSaysWhatThePageSays() {
        open("erase-everything")
        let erase = app.buttons["Erase everything"].firstMatch
        XCTAssertTrue(erase.waitForExistence(timeout: 10))
        erase.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        photograph("erase everything › the alert")
        let words = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(words.contains("erase themselves"), "the alert read: \(words)")
        XCTAssertFalse(words.contains("keep theirs"), "the alert still contradicts the page: \(words)")
        alert.buttons["Cancel"].tap()
    }

    func testEachPersonIsOneVoiceOverStop() {
        open("message-detail")
        let row = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Hastur'")).firstMatch
        let combined = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Hastur' AND label CONTAINS 'Received'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10) || combined.exists)
        XCTAssertTrue(combined.exists, "Hastur's name and when he collected it are separate stops")
        XCTAssertTrue(
            combined.label.contains("Shown"), "his shown time is not read with his row: \(combined.label)")
    }

    func testPhotographEveryFixedScreen() {
        let shots = [
            "members", "join-check", "erase-everything", "awaiting-approval", "stalled-offline",
            "stalled-signed-out", "rooms-cannot-send", "message-detail", "tap-trouble", "devices",
            "post-thread", "post-composer", "onboarding", "redeem", "invite", "add-someone", "remove-member",
            "checking-registration", "approve-device", "data-problem", "members-check", "person-actions",
        ]
        for shot in shots {
            open(shot)
            _ = app.staticTexts.firstMatch.waitForExistence(timeout: 10)
            _ = app.activityIndicators.firstMatch.waitForNonExistence(timeout: 2)
            photograph(shot)
        }
    }

    func testTheLargestTextStillFits() {
        for shot in ["message-detail", "members-check", "awaiting-approval", "stalled-signed-out"] {
            open(shot, textSize: "UICTContentSizeCategoryAccessibilityXXXL")
            _ = app.staticTexts.firstMatch.waitForExistence(timeout: 10)
            photograph("\(shot) › largest text")
        }
    }
}
