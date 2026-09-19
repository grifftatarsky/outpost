import XCTest

@MainActor
final class RigChecks: XCTestCase {
    let exchange = "/tmp/outpost-rig-exchange"

    var isCloud: Bool { ProcessInfo.processInfo.environment["RIG_CLOUD"] == "1" }

    var codes: String { isCloud ? "/tmp/outpost-rig-codes" : "/tmp/outpost-rig-mailbox/codes" }

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OUTPOST_RIG"] == "1",
            "a rig run: set TEST_RUNNER_OUTPOST_RIG=1 and launch both devices under --mailbox")
        try? FileManager.default.createDirectory(atPath: exchange, withIntermediateDirectories: true)
    }

    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += (isCloud ? ["--rig-codes", codes] : ["--mailbox", "/tmp/outpost-rig-mailbox"]) + extra
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 20)
        return app
    }

    func shoot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? app.debugDescription.write(toFile: "\(exchange)/\(name).txt", atomically: true, encoding: .utf8)
    }

    func tapIfThere(_ app: XCUIApplication, _ label: String, timeout: TimeInterval = 2, scrolling: Bool = false) -> Bool {
        let button = app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label + ",")).firstMatch
        if button.waitForExistence(timeout: timeout), button.isHittable {
            button.tap()
            return true
        }
        guard scrolling else { return false }
        for _ in 0..<5 {
            app.swipeUp()
            if button.exists, button.isHittable {
                button.tap()
                return true
            }
        }
        return false
    }

    func settle(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<30 {
            var tapped = false
            for label in ["Allow", "Don’t Allow"] where springboard.buttons[label].exists {
                springboard.buttons[label].tap()
                tapped = true
                break
            }
            if !tapped {
                for label in [
                    "Familiar and open", "Use these settings", "Not now", "Continue without it",
                    "Continue", "Get started", "Skip", "Next", "Finish", "Done",
                ] where tapIfThere(app, label, timeout: 0.5) {
                    tapped = true
                    break
                }
            }
            if !tapped { break }
            sleep(1)
        }
    }

    func write(_ value: String, to name: String) {
        try? value.write(toFile: "\(exchange)/\(name)", atomically: true, encoding: .utf8)
    }

    func read(_ name: String) -> String {
        (try? String(contentsOfFile: "\(exchange)/\(name)", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func testFifthOnboards() throws {
        let app = launch()
        sleep(3)
        _ = tapIfThere(app, "Skip")
        sleep(1)
        let field = app.textFields.firstMatch
        if field.waitForExistence(timeout: 5) {
            for _ in 0..<4 where app.keyboards.count == 0 {
                field.tap()
                sleep(1)
            }
            field.typeText("Fifth")
            sleep(1)
            XCTAssertTrue(tapIfThere(app, "Create my identity", timeout: 3), "could not create the identity")
        }
        sleep(3)
        settle(app)
        sleep(2)
        shoot(app, "fifth-home")
    }

    func testOfferShown() throws {
        let app = launch()
        sleep(3)
        settle(app)
        app.buttons["Rooms"].firstMatch.tap()
        sleep(6)
        let room = app.staticTexts["Checks"].firstMatch
        XCTAssertTrue(room.waitForExistence(timeout: 10))
        room.tap()
        sleep(3)
        _ = tapIfThere(app, "Open Checks", timeout: 2)
        sleep(3)
        shoot(app, "o-1-offer")
        let offer = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "never compared codes")).firstMatch
        XCTAssertEqual(
            offer.waitForExistence(timeout: 5), ProcessInfo.processInfo.environment["RIG_EXPECT_OFFER"] != "no",
            "the offer was or was not shown against what this member should see")
    }

    func testTrigOnboards() throws {
        let app = launch()
        sleep(3)
        _ = tapIfThere(app, "Skip")
        sleep(1)
        let field = app.textFields.firstMatch
        if field.waitForExistence(timeout: 5) {
            field.tap()
            field.typeText(ProcessInfo.processInfo.environment["RIG_NAME"] ?? "Trig")
            _ = tapIfThere(app, "Create my identity")
        }
        sleep(3)
        settle(app)
        sleep(2)
        shoot(app, "trig-home")
    }

    func testShareCode() throws {
        let app = launch()
        sleep(3)
        settle(app)
        app.buttons["You"].firstMatch.tap()
        sleep(1)
        shoot(app, "code-1-you")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "·")).firstMatch
        if row.waitForExistence(timeout: 3) { row.tap() } else { app.cells.element(boundBy: 0).tap() }
        sleep(1)
        shoot(app, "code-2-identity")
        let send = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Send someone your code")).firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()
        sleep(2)
        shoot(app, "code-3-sheet")
        let copy = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Copy"]
        let copyHere = app.buttons["Copy"]
        if copyHere.waitForExistence(timeout: 3) { copyHere.tap() } else if copy.exists { copy.tap() }
        sleep(1)
        shoot(app, "code-4-copied")
    }

    func testAppIconPicker() throws {
        let app = launch()
        sleep(3)
        settle(app)
        app.buttons["You"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue(tapIfThere(app, "Appearance", timeout: 5, scrolling: true))
        sleep(1)
        XCTAssertTrue(tapIfThere(app, "App icon", timeout: 5))
        sleep(1)
        shoot(app, "icon-1-top")
        app.swipeUp()
        sleep(1)
        shoot(app, "icon-2-lower")
        let tile = app.buttons["Cobalt, Mailbox"]
        XCTAssertTrue(tile.waitForExistence(timeout: 3))
        if !tile.isHittable { app.swipeUp() }
        tile.tap()
        sleep(2)
        shoot(app, "icon-3-changed")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["OK"].waitForExistence(timeout: 3) { springboard.buttons["OK"].tap() }
        if app.alerts.buttons["OK"].exists { app.alerts.buttons["OK"].tap() }
        XCUIDevice.shared.press(.home)
        sleep(2)
        shoot(app, "icon-4-home")
    }

    func testSupporter() throws {
        let app = launch(["--forget-supporter"])
        sleep(3)
        settle(app)
        app.buttons["You"].firstMatch.tap()
        sleep(2)
        shoot(app, "supporter-1-you")
        let bar = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Become a Supporter")).firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.tap()
        sleep(2)
        shoot(app, "supporter-2-thanks")
        XCTAssertTrue(tapIfThere(app, "Continue", timeout: 5))
        sleep(2)
        shoot(app, "supporter-3-ask")
        XCTAssertTrue(tapIfThere(app, "Show the badge", timeout: 5))
        sleep(2)
        shoot(app, "supporter-4-you-after")
        XCTAssertTrue(tapIfThere(app, "Supporter", timeout: 5, scrolling: true))
        sleep(1)
        shoot(app, "supporter-5-page")
    }

    func testPeopleAndRooms() throws {
        let app = launch()
        sleep(8)
        settle(app)
        app.buttons["Rooms"].firstMatch.tap()
        sleep(2)
        shoot(app, "people-1-rooms")
        app.buttons["You"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue(tapIfThere(app, "People", timeout: 5))
        sleep(2)
        shoot(app, "people-2-list")
        app.buttons["Rooms"].firstMatch.tap()
        sleep(1)
        let room = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Checks")).firstMatch
        if room.waitForExistence(timeout: 5) { room.tap() }
        sleep(3)
        shoot(app, "people-3-room")
    }

    func testSupporterDeclines() throws {
        let app = launch(["--forget-supporter"])
        sleep(3)
        settle(app)
        app.buttons["You"].firstMatch.tap()
        sleep(2)
        shoot(app, "declines-1-you")
        let bar = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Become a Supporter")).firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.tap()
        sleep(2)
        XCTAssertTrue(tapIfThere(app, "Continue", timeout: 5))
        sleep(1)
        XCTAssertTrue(tapIfThere(app, "Not now", timeout: 5))
        sleep(2)
        shoot(app, "declines-2-you-after")
        XCTAssertFalse(bar.exists, "the offer is still showing after it was taken")
    }

    func entry(_ app: XCUIApplication, _ placeholder: String) -> XCUIElement {
        let predicate = NSPredicate(format: "placeholderValue == %@", placeholder)
        let view = app.textViews.matching(predicate).firstMatch
        if view.waitForExistence(timeout: 3) { return view }
        return app.textFields.matching(predicate).firstMatch
    }

    func code(_ name: String) -> String {
        (try? String(contentsOfFile: "\(codes)/\(name)", encoding: .utf8)) ?? ""
    }

    func testTrigMakesARoomAndInvitesQuad() throws {
        let joiner = ProcessInfo.processInfo.environment["RIG_JOINER"] ?? "Quad"
        let quad = code("\(joiner).identity")
        XCTAssertFalse(quad.isEmpty, "\(joiner) has not left its code")
        let app = launch()
        sleep(3)
        settle(app)
        app.buttons["Rooms"].firstMatch.tap()
        sleep(1)
        if !app.staticTexts["Checks"].firstMatch.waitForExistence(timeout: 3) {
            XCTAssertTrue(tapIfThere(app, "Make a room", timeout: 3) || tapIfThere(app, "New room", timeout: 3))
            let name = app.textFields["Name"].firstMatch
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap()
            name.typeText("Checks")
            XCTAssertTrue(tapIfThere(app, "Create"))
            sleep(3)
        }
        app.staticTexts["Checks"].firstMatch.tap()
        sleep(2)
        shoot(app, "invite-1-room")
        XCTAssertTrue(roomMenu(app, "Invite someone"))
        sleep(2)
        shoot(app, "invite-2-sheet")
        let field = entry(app, "Paste their code")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(quad)
        shoot(app, "invite-2-pasted")
        _ = tapIfThere(app, "Done", timeout: 1)
        XCTAssertTrue(tapIfThere(app, "Create the invite", timeout: 3, scrolling: true))
        sleep(3)
        shoot(app, "invite-3-issued")
    }

    func testQuadJoins() throws {
        let inviter = ProcessInfo.processInfo.environment["RIG_INVITER"] ?? "Trig"
        let invite = code("\(inviter).invite")
        XCTAssertFalse(invite.isEmpty, "\(inviter) has not left an invite")
        let app = launch()
        sleep(3)
        settle(app)
        app.buttons["Rooms"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue(tapIfThere(app, "I have an invite", timeout: 3))
        sleep(1)
        let field = entry(app, "Paste the invite")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(invite)
        shoot(app, "join-1-pasted")
        XCTAssertTrue(tapIfThere(app, "Read the invite", timeout: 3))
        sleep(2)
        shoot(app, "join-2-read")
        _ = tapIfThere(app, "They match", timeout: 3)
        sleep(2)
        shoot(app, "join-3-matched")
        _ = tapIfThere(app, "Done", timeout: 3)
        sleep(2)
        shoot(app, "join-4-done")
    }

    func openChecks(_ app: XCUIApplication) {
        settle(app)
        app.buttons["Rooms"].firstMatch.tap()
        sleep(1)
        let room = app.staticTexts["Checks"].firstMatch
        XCTAssertTrue(room.waitForExistence(timeout: 10), "Checks is not in the list")
        room.tap()
        sleep(3)
        _ = tapIfThere(app, "Open Checks", timeout: 2)
        sleep(1)
        _ = tapIfThere(app, "Not now", timeout: 1)
    }

    func send(_ app: XCUIApplication, _ text: String) {
        let field = entry(app, "Message")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        for _ in 0..<4 where app.keyboards.count == 0 {
            field.tap()
            sleep(1)
        }
        shoot(app, "composer-focus")
        field.typeText(text)
        XCTAssertTrue(tapIfThere(app, "Send", timeout: 3))
        sleep(3)
    }

    func roomMenu(_ app: XCUIApplication, _ item: String) -> Bool {
        let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Room settings")).firstMatch
        guard menu.waitForExistence(timeout: 5) else { return false }
        menu.tap()
        sleep(1)
        return tapIfThere(app, item, timeout: 3)
    }

    func testQuadSays() throws {
        let app = launch()
        sleep(3)
        openChecks(app)
        send(app, "hello from Quad")
        sleep(8)
        shoot(app, "q-said")
    }

    func testQuadSaysWhatItIsTold() throws {
        let app = launch()
        sleep(3)
        openChecks(app)
        send(app, ProcessInfo.processInfo.environment["RIG_SAY"] ?? "are you there, Trig")
        sleep(6)
        shoot(app, "q-told")
    }

    func testQuadSeesTheAnswer() throws {
        let expected = ProcessInfo.processInfo.environment["RIG_EXPECT"] ?? "on my way"
        let app = launch()
        sleep(3)
        openChecks(app)
        let said = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", expected)).firstMatch
        for _ in 0..<15 where !said.exists {
            app.swipeUp()
            _ = said.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(said.exists, "the answer from the banner never reached Quad")
        shoot(app, "q-saw-answer")
    }

    func composer(_ app: XCUIApplication) -> XCUIElement {
        let named = entry(app, "Message")
        if named.waitForExistence(timeout: 3) { return named }
        return app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
    }

    func testDraftSurvives() throws {
        let words = "half a thought \(Int(Date().timeIntervalSince1970) % 100_000)"
        let showing = NSPredicate(format: "label CONTAINS %@", words)
        var app = launch()
        sleep(3)
        openChecks(app)
        let field = composer(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        if tapIfThere(app, "Send", timeout: 1) { sleep(3) }
        for _ in 0..<4 where app.keyboards.count == 0 {
            field.tap()
            sleep(1)
        }
        field.typeText(words)
        sleep(2)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(2)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(showing).firstMatch.waitForExistence(timeout: 5),
            "the rooms list does not show the draft")
        shoot(app, "draft-1-row")

        app.terminate()
        app = launch()
        sleep(4)
        settle(app)
        app.buttons["Rooms"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(showing).firstMatch.waitForExistence(timeout: 8),
            "the draft did not survive a relaunch in the list")
        openChecks(app)
        let back = composer(app)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertEqual(back.value as? String, words, "the composer did not bring the draft back")
        shoot(app, "draft-2-back")

        XCTAssertTrue(tapIfThere(app, "Send", timeout: 3))
        sleep(3)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(2)
        let draftLine = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Draft' AND label CONTAINS %@", words)).firstMatch
        XCTAssertFalse(draftLine.exists, "the draft stayed after it was sent")
        shoot(app, "draft-3-sent")
    }

    func testAnswerFromTheBanner() throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let env = ProcessInfo.processInfo.environment
        let body = env["RIG_BANNER_BODY"] ?? "are you there"
        let replying = env["RIG_ANSWER"] != "read"

        XCUIDevice.shared.press(.home)
        sleep(2)
        try? FileManager.default.removeItem(atPath: "\(exchange)/pushed")
        write("waiting", to: "ready-for-push")

        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'NotificationShortLookView' AND label CONTAINS %@", body))
            .firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 90), "no banner says \(body)")
        try? FileManager.default.removeItem(atPath: "\(exchange)/ready-for-push")
        shoot(springboard, "n-1-banner")

        let action = springboard.buttons[replying ? "Reply" : "Mark as Read"]
        let middle = banner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        middle.press(forDuration: 0.1, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: 260)))
        _ = action.waitForExistence(timeout: 4)
        if !action.exists {
            middle.press(forDuration: 2.0)
            _ = action.waitForExistence(timeout: 4)
        }
        shoot(springboard, "n-2-actions")
        XCTAssertTrue(action.exists, "the notification offers no \(replying ? "Reply" : "Mark as Read")")
        action.tap()
        if replying {
            for _ in 0..<5 where springboard.keyboards.count == 0 { sleep(1) }
            shoot(springboard, "n-3-field")
            springboard.typeText(env["RIG_REPLY"] ?? "on my way")
            shoot(springboard, "n-4-typed")
            let send = springboard.buttons["Send"]
            XCTAssertTrue(send.waitForExistence(timeout: 3), "the reply field has no Send")
            send.tap()
        }
        sleep(4)
        shoot(springboard, "n-5-after")
    }

    func testTrigBlockSheet() throws {
        let app = launch()
        sleep(3)
        openChecks(app)
        sleep(6)
        shoot(app, "b-1-room")
        let message = app.staticTexts["hello from Quad"].firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 20), "Quad's message never arrived")
        message.press(forDuration: 1.2)
        sleep(1)
        shoot(app, "b-2-held")
        XCTAssertTrue(tapIfThere(app, "More actions", timeout: 3))
        sleep(1)
        shoot(app, "b-3-actions")
        let block = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Block ")).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 3))
        block.tap()
        sleep(1)
        shoot(app, "b-4-sheet")
        XCTAssertTrue(app.buttons["Block and Leave"].firstMatch.waitForExistence(timeout: 3), "no Block and Leave")
        _ = tapIfThere(app, "Cancel", timeout: 2)
    }

    func testTrigWaitingAndCompare() throws {
        let app = launch()
        sleep(3)
        openChecks(app)
        XCTAssertTrue(roomMenu(app, "Who this is waiting on"))
        sleep(2)
        shoot(app, "w-1-waiting")
        _ = tapIfThere(app, "Done", timeout: 2)
        sleep(1)
        XCTAssertTrue(roomMenu(app, "Who you are talking to"))
        sleep(2)
        shoot(app, "c-1-who")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Quad")).firstMatch
        if row.waitForExistence(timeout: 3) { row.tap() } else { app.cells.element(boundBy: 1).tap() }
        sleep(2)
        shoot(app, "c-2-compare-trig")
    }

    func testQuadCompare() throws {
        let app = launch()
        sleep(3)
        openChecks(app)
        XCTAssertTrue(roomMenu(app, "Who you are talking to"))
        sleep(2)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Trig")).firstMatch
        if row.waitForExistence(timeout: 3) { row.tap() } else { app.cells.element(boundBy: 0).tap() }
        sleep(2)
        shoot(app, "c-3-compare-quad")
    }

    func testTrigSendsWhileQuadIsAway() throws {
        let app = launch()
        sleep(3)
        openChecks(app)
        send(app, "are you still there")
        sleep(3)
        shoot(app, "n-1-sent")
    }

    func testTrigFourDaysLater() throws {
        let app = launch(["--clock-ahead-days", "4"])
        sleep(3)
        openChecks(app)
        sleep(4)
        shoot(app, "n-2-four-days")
        let mark = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Not sent yet")).firstMatch
        XCTAssertTrue(mark.waitForExistence(timeout: 5), "no not-sent mark after four days")
        if mark.isHittable {
            mark.tap()
            sleep(1)
            shoot(app, "n-3-explained")
        }
    }

    func testTrigRemovesQuad() throws {
        let app = launch()
        sleep(3)
        openChecks(app)
        XCTAssertTrue(roomMenu(app, "Who is in this room"))
        sleep(2)
        shoot(app, "r-1-members")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Quad")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.press(forDuration: 1.0)
        sleep(1)
        shoot(app, "r-2-row-menu")
        XCTAssertTrue(tapIfThere(app, "Remove from room", timeout: 3))
        sleep(1)
        shoot(app, "r-3-confirm")
        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Remove Quad")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        sleep(8)
        shoot(app, "r-4-removed")
    }

    func testQuadDeletes() throws {
        let app = launch()
        sleep(3)
        settle(app)
        app.buttons["Rooms"].firstMatch.tap()
        sleep(6)
        let room = app.staticTexts["Checks"].firstMatch
        XCTAssertTrue(room.waitForExistence(timeout: 10))
        room.tap()
        sleep(4)
        shoot(app, "d-1-removed-room")
        XCTAssertFalse(app.staticTexts["Compare codes"].exists, "a removed member was offered a comparison")
        XCTAssertTrue(roomMenu(app, "Delete"), "no Delete in the conversation's menu")
        sleep(1)
        shoot(app, "d-2-alert-from-conversation")
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3), "no alert")
        app.alerts.buttons["Cancel"].firstMatch.tap()
        sleep(1)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(2)
        let row = app.staticTexts["Checks"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1.2)
        sleep(1)
        shoot(app, "d-3-context-menu")
        XCTAssertTrue(tapIfThere(app, "Delete", timeout: 3), "no Delete in the context menu")
        sleep(1)
        shoot(app, "d-4-alert")
        let delete = app.alerts.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "no alert")
        delete.tap()
        sleep(3)
        shoot(app, "d-5-gone")
        XCTAssertFalse(app.staticTexts["Checks"].firstMatch.exists, "the room is still listed")
    }

    func testQuadAfterRelaunch() throws {
        let app = launch()
        sleep(3)
        settle(app)
        app.buttons["Rooms"].firstMatch.tap()
        sleep(20)
        shoot(app, "d-6-relaunched")
        XCTAssertFalse(app.staticTexts["Checks"].firstMatch.exists, "the deleted room came back")
    }

    func testTrigRefused() throws {
        let app = launch(["--mailbox-refuses", ProcessInfo.processInfo.environment["RIG_REFUSAL"] ?? "full"])
        sleep(3)
        openChecks(app)
        send(app, "can this go")
        sleep(6)
        shoot(app, "f-1-conversation")
        let mark = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Not sent yet")).firstMatch
        if mark.waitForExistence(timeout: 3), mark.isHittable {
            mark.tap()
            sleep(1)
            shoot(app, "f-2-explained")
            _ = tapIfThere(app, "Done", timeout: 2)
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(3)
        shoot(app, "f-3-rooms")
    }

    func testRoomState() throws {
        let app = launch()
        sleep(3)
        settle(app)
        app.buttons["Rooms"].firstMatch.tap()
        sleep(8)
        shoot(app, "s-1-rooms")
        let room = app.staticTexts["Checks"].firstMatch
        if room.waitForExistence(timeout: 5) {
            room.tap()
            sleep(5)
            shoot(app, "s-2-room")
            let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Room settings")).firstMatch
            if menu.waitForExistence(timeout: 3) {
                menu.tap()
                sleep(1)
                shoot(app, "s-3-menu")
            }
        }
    }

    func testDump() throws {
        let app = launch()
        sleep(4)
        settle(app)
        shoot(app, read("dump-name").isEmpty ? "dump" : read("dump-name"))
    }
}
