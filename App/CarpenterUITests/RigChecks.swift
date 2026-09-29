import XCTest

@MainActor
final class RigChecks: XCTestCase {
    let exchange = "/tmp/outpost-rig-exchange"

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OUTPOST_RIG"] == "1",
            "a rig run: set TEST_RUNNER_OUTPOST_RIG=1 and launch both devices under --mailbox")
        try? FileManager.default.createDirectory(atPath: exchange, withIntermediateDirectories: true)
    }

    var roomName: String { ProcessInfo.processInfo.environment["RIG_ROOM"] ?? "Checks" }

    func names(_ variable: String) -> [String] {
        (ProcessInfo.processInfo.environment[variable] ?? "").split(separator: ",").map(String.init)
    }

    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let offline = ProcessInfo.processInfo.environment["RIG_OFFLINE"] == "1" ? ["--mailbox-refuses", "full"] : []
        app.launchArguments += ["--mailbox", "/tmp/outpost-rig-mailbox"] + offline + extra
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
        if button.waitForExistence(timeout: timeout), stillThere(button) {
            button.tap()
            return true
        }
        guard scrolling else { return false }
        for _ in 0..<5 {
            app.swipeUp()
            if stillThere(button) {
                button.tap()
                return true
            }
        }
        return false
    }

    func stillThere(_ element: XCUIElement) -> Bool {
        var there = false
        XCTExpectFailure("a screen changing under the check makes the element vanish before it is read", strict: false) {
            there = element.exists && element.isHittable
        }
        return there
    }

    func settle(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        var idle = 0
        for _ in 0..<30 {
            var tapped = false
            for label in ["Allow", "Don’t Allow"] where springboard.buttons[label].exists {
                springboard.buttons[label].tap()
                tapped = true
                break
            }
            if !tapped, app.buttons["I've saved it"].exists {
                tapped = saveTheRecoveryKey(app)
            }
            if !tapped {
                for label in [
                    "Familiar and open", "Use these settings", "Not now", "Not for now", "Continue without it",
                    "Continue", "Get started", "Skip", "Next", "Finish", "Done",
                ] where tapIfThere(app, label, timeout: 0.5) {
                    tapped = true
                    break
                }
            }
            idle = tapped ? 0 : idle + 1
            if idle >= 3 { break }
            sleep(1)
        }
    }

    func saveTheRecoveryKey(_ app: XCUIApplication) -> Bool {
        guard tapIfThere(app, "Save key", timeout: 2) else { return false }
        sleep(2)
        let copy = app.buttons["Copy"].firstMatch
        if copy.waitForExistence(timeout: 5) { copy.tap() } else { app.swipeDown() }
        sleep(1)
        guard tapIfThere(app, "I've saved it", timeout: 5) else { return false }
        return tapIfThere(app, "It's saved", timeout: 3)
    }

    func write(_ value: String, to name: String) {
        try? value.write(toFile: "\(exchange)/\(name)", atomically: true, encoding: .utf8)
    }

    func read(_ name: String) -> String {
        (try? String(contentsOfFile: "\(exchange)/\(name)", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func onboard(as name: String) {
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
            field.typeText(name)
            sleep(1)
            XCTAssertTrue(tapIfThere(app, "Create my identity", timeout: 3), "could not create the identity")
        }
        sleep(3)
        settle(app)
        sleep(2)
        shoot(app, "\(name.lowercased())-home")
    }

    func testFifthOnboards() throws {
        onboard(as: ProcessInfo.processInfo.environment["RIG_NAME"] ?? "Fifth")
    }

    func testANewMemberSavesTheKeyAndLocksTheApp() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--mailbox", "/tmp/outpost-lock-check"]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 20)
        sleep(3)
        _ = tapIfThere(app, "Skip")
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no name field")
        field.tap()
        field.typeText("Lockwood")
        XCTAssertTrue(tapIfThere(app, "Create my identity", timeout: 3), "could not create the identity")

        let saved = app.buttons["I've saved it"]
        XCTAssertTrue(saved.waitForExistence(timeout: 15), "the recovery key was not shown at setup")
        shoot(app, "lock-1-recovery-key")
        XCTAssertFalse(saved.isEnabled, "the key could be marked saved before it was saved anywhere")
        XCTAssertTrue(tapIfThere(app, "Save key"), "no way to save the key")
        sleep(2)
        shoot(app, "lock-2-share-sheet")
        let copy = app.buttons["Copy"].firstMatch
        if copy.waitForExistence(timeout: 5) { copy.tap() } else { app.swipeDown() }
        sleep(1)
        XCTAssertTrue(saved.waitForExistence(timeout: 5) && saved.isEnabled, "saving did not let the member go on")
        saved.tap()
        shoot(app, "lock-3-is-it-saved")
        XCTAssertTrue(tapIfThere(app, "It's saved", timeout: 3), "no confirmation")

        XCTAssertTrue(
            app.buttons["Continue"].firstMatch.waitForExistence(timeout: 10), "notifications were not offered before the lock")
        XCTAssertFalse(app.staticTexts["Lock the app"].firstMatch.exists, "the lock was offered before notifications")
        shoot(app, "lock-3b-notifications-first")
        XCTAssertTrue(tapIfThere(app, "Continue", timeout: 3))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Allow"].waitForExistence(timeout: 8) { springboard.buttons["Allow"].tap() }
        _ = tapIfThere(app, "Not for now", timeout: 5)

        XCTAssertTrue(
            app.staticTexts["Lock the app"].firstMatch.waitForExistence(timeout: 10), "the lock was not offered at setup")
        shoot(app, "lock-4-offer")
        XCTAssertTrue(app.buttons["Not now"].firstMatch.isHittable, "the offer can't be declined as it opens")
        let fields = app.secureTextFields
        fields.element(boundBy: 0).tap()
        fields.element(boundBy: 0).typeText("482913")
        XCTAssertTrue(fields.element(boundBy: 1).isHittable, "the keyboard or the buttons cover the second field")
        fields.element(boundBy: 1).tap()
        fields.element(boundBy: 1).typeText("482913")
        shoot(app, "lock-5-code-typed")
        let lockButton = app.buttons["Lock the app"].firstMatch
        XCTAssertTrue(lockButton.waitForExistence(timeout: 3), "no button to finish")
        sleep(1)
        XCTAssertTrue(lockButton.isHittable, "the keyboard still covers the button once both codes match")
        lockButton.tap()
        let makePrivate = app.alerts.buttons["Make them private"].firstMatch
        XCTAssertTrue(makePrivate.waitForExistence(timeout: 5), "setting the lock did not offer private notifications")
        shoot(app, "lock-5b-private-notifications")
        makePrivate.tap()
        sleep(2)
        settle(app)

        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        let locked = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "is locked")).firstMatch
        XCTAssertTrue(locked.waitForExistence(timeout: 10), "the app opened without its lock")
        XCTAssertFalse(
            app.buttons["You"].firstMatch.exists,
            "the app under the lock could still be reached, by VoiceOver or anything that reads the screen's elements")
        shoot(app, "lock-6-locked")
        for digit in "000000" { app.buttons[String(digit)].firstMatch.tap() }
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "That's not it")).firstMatch
                .waitForExistence(timeout: 10),
            "a wrong code did not say so")
        shoot(app, "lock-7-wrong-code")
        for digit in "482913" { app.buttons[String(digit)].firstMatch.tap() }
        XCTAssertTrue(app.buttons["You"].firstMatch.waitForExistence(timeout: 10), "the right code did not open the app")
        shoot(app, "lock-8-open")

        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(locked.waitForExistence(timeout: 10), "the app opened without its lock the second time")
        for _ in 0..<4 where app.keyboards.count == 0 {
            app.secureTextFields.firstMatch.tap()
            sleep(1)
        }
        shoot(app, "lock-9-keyboard-up")
        let forgot = app.buttons["Forgot the code?"].firstMatch
        XCTAssertTrue(forgot.waitForExistence(timeout: 5), "no way back for somebody who forgot the code")
        XCTAssertTrue(forgot.isHittable, "the keyboard covers the way back")
        forgot.tap()
        let erase = app.alerts.buttons["Erase"].firstMatch
        XCTAssertTrue(erase.waitForExistence(timeout: 5), "forgetting did not ask before erasing")
        shoot(app, "lock-10-forgot")
        erase.tap()
        sleep(4)
        XCTAssertFalse(locked.exists, "the lock stayed up after the phone's copy was erased")
        let fresh = app.textFields.firstMatch
        XCTAssertTrue(
            fresh.waitForExistence(timeout: 20) || app.buttons["Skip"].firstMatch.exists,
            "erasing did not bring the phone back to the start")
        shoot(app, "lock-11-erased")
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
        onboard(as: "Trig")
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
        (try? String(contentsOfFile: "/tmp/outpost-rig-mailbox/codes/\(name)", encoding: .utf8)) ?? ""
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
        if !app.staticTexts[roomName].firstMatch.waitForExistence(timeout: 3) {
            XCTAssertTrue(tapIfThere(app, "Make a room", timeout: 3) || tapIfThere(app, "New room", timeout: 3))
            let name = app.textFields["Name"].firstMatch
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap()
            name.typeText(roomName)
            XCTAssertTrue(tapIfThere(app, "Create"))
            sleep(3)
        }
        app.staticTexts[roomName].firstMatch.tap()
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
        let invite = code("Trig.invite")
        XCTAssertFalse(invite.isEmpty, "Trig has not left an invite")
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
        let room = app.staticTexts[roomName].firstMatch
        XCTAssertTrue(room.waitForExistence(timeout: 10), "\(roomName) is not in the list")
        room.tap()
        sleep(3)
        _ = tapIfThere(app, "Open \(roomName)", timeout: 2)
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
        send(app, ProcessInfo.processInfo.environment["RIG_SAY"] ?? "hello from Quad")
        sleep(8)
        shoot(app, "q-said")
    }

    func testSees() throws {
        let expected = try XCTUnwrap(ProcessInfo.processInfo.environment["RIG_EXPECT"], "set RIG_EXPECT to the words to wait for")
        let app = launch()
        sleep(3)
        openChecks(app)
        let message = app.staticTexts[expected].firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 120), "\(expected) never arrived")
        shoot(app, "seen")
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
        remove("Quad", in: app)
        sleep(8)
        shoot(app, "r-4-removed")
    }

    func remove(_ name: String, in app: XCUIApplication) {
        XCTAssertTrue(roomMenu(app, "Who is in this room"))
        sleep(2)
        shoot(app, "r-1-members")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3), "\(name) is not in the member list")
        row.press(forDuration: 1.0)
        sleep(1)
        shoot(app, "r-2-row-menu")
        XCTAssertTrue(tapIfThere(app, "Remove from room", timeout: 3))
        sleep(1)
        shoot(app, "r-3-confirm")
        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Remove \(name)")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
    }

    func testRemoves() throws {
        let removed = try XCTUnwrap(ProcessInfo.processInfo.environment["RIG_REMOVE"], "set RIG_REMOVE to who to remove")
        let app = launch()
        sleep(3)
        openChecks(app)
        remove(removed, in: app)
        sleep(3)
        _ = tapIfThere(app, "Done", timeout: 3)
        if let said = ProcessInfo.processInfo.environment["RIG_SAY"] {
            sleep(1)
            send(app, said)
        }
        sleep(8)
        shoot(app, "r-4-removed")
    }

    func testStaysOpen() throws {
        let app = launch()
        sleep(3)
        openChecks(app)
        sleep(UInt32(ProcessInfo.processInfo.environment["RIG_SECONDS"].flatMap { UInt32($0) } ?? 30))
        shoot(app, "open-\(roomName.lowercased())")
    }

    func testRecordsMembers() throws {
        let people = names("RIG_PEOPLE")
        XCTAssertFalse(people.isEmpty, "set RIG_PEOPLE to the names to look for")
        let record = try XCTUnwrap(ProcessInfo.processInfo.environment["RIG_RECORD"], "set RIG_RECORD to a file name")
        let app = launch()
        sleep(3)
        openChecks(app)
        sleep(UInt32(ProcessInfo.processInfo.environment["RIG_SECONDS"].flatMap { UInt32($0) } ?? 30))
        XCTAssertTrue(roomMenu(app, "Who is in this room"))
        sleep(2)
        shoot(app, "members-\(record)")
        write(people.map { "\($0)=\(shows(app, $0) ? "in" : "out")" }.joined(separator: ","), to: record)
    }

    func shows(_ app: XCUIApplication, _ name: String) -> Bool {
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name))
        return (0..<rows.count).contains { stillThere(rows.element(boundBy: $0)) }
    }

    func testNeverSees() throws {
        let unexpected = try XCTUnwrap(
            ProcessInfo.processInfo.environment["RIG_EXPECT"], "set RIG_EXPECT to the words that must not arrive")
        let app = launch()
        sleep(3)
        openChecks(app)
        let message = app.staticTexts[unexpected].firstMatch
        XCTAssertFalse(message.waitForExistence(timeout: 90), "\(unexpected) reached this phone")
        shoot(app, "never-seen")
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
