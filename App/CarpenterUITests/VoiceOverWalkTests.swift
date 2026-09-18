import XCTest

final class VoiceOverWalkTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["--quiet-for-audit", "-theme.accent", "verdigris"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "the app never came up")
    }

    // MARK: Reading the tree

    private func stops() -> [XCUIElement] {
        app.descendants(matching: .any).allElementsBoundByAccessibilityElement
    }

    private func described(_ element: XCUIElement) -> String {
        let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (element.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return [label, value].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    private func record(_ screen: String, _ elements: [XCUIElement]) {
        let lines = elements.enumerated().map { index, element in
            "\(index + 1). [\(element.elementType.rawValue)] \(described(element))"
        }
        let attachment = XCTAttachment(string: ([screen, ""] + lines).joined(separator: "\n"))
        attachment.name = "Element tree — \(screen)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertNothingIsSilent(on screen: String, file: StaticString = #filePath, line: UInt = #line) {
        let visited = stops()
        record(screen, visited)

        let announced: Set<XCUIElement.ElementType> = [
            .button, .staticText, .image, .textField, .textView, .secureTextField, .switch,
            .toggle, .slider, .link, .menuItem, .segmentedControl,
        ]
        let drawnByIOS: Set<String> = ["AdditionalDimmingOverlay", "chevron.forward"]
        let silent = visited.filter { element in
            guard element.exists, element.isHittable, announced.contains(element.elementType),
                !drawnByIOS.contains(element.identifier),
                !isToolbarMenuBacking(element)
            else { return false }
            return described(element).isEmpty
        }

        XCTAssertTrue(
            silent.isEmpty,
            """
            \(silent.count) element(s) on \(screen) stop VoiceOver and describe nothing. \
            Each is something a sighted member can read and a VoiceOver member cannot: \
            \(silent.map { "[\($0.elementType.rawValue)] \($0.debugDescription.prefix(120))" })
            """,
            file: file, line: line)
    }

    private func isToolbarMenuBacking(_ element: XCUIElement) -> Bool {
        element.elementType == .button
            && app.navigationBars.firstMatch.frame.maxY > element.frame.midY
            && app.buttons.allElementsBoundByIndex.contains { other in
                other != element && !other.label.isEmpty
                    && other.frame.intersects(element.frame)
            }
    }

    // MARK: The walk

    func testTheRoomsListSaysSomethingForEveryStop() throws {
        assertNothingIsSilent(on: "Rooms")
    }

    func testTheTabsAreReachableAndNamed() throws {
        for tab in ["Solos", "Rooms", "Outposts", "You"] {
            let button = app.buttons[tab]
            XCTAssertTrue(
                button.waitForExistence(timeout: 5),
                "VoiceOver cannot reach the \(tab) tab by name, so the rotor cannot either")
            XCTAssertFalse(button.label.isEmpty, "the \(tab) tab announces nothing")
        }
    }

    func testEachTabSaysSomethingForEveryStop() throws {
        for tab in ["Solos", "Outposts", "You", "Rooms"] {
            let button = app.buttons[tab]
            guard button.waitForExistence(timeout: 5) else {
                XCTFail("the \(tab) tab never appeared")
                continue
            }
            button.tap()
            _ = app.wait(for: .runningForeground, timeout: 2)
            assertNothingIsSilent(on: tab)
        }
    }

    func testAConversationSaysSomethingForEveryStop() throws {
        let rooms = app.buttons["Rooms"]
        if rooms.waitForExistence(timeout: 5) { rooms.tap() }

        let firstRoom = app.cells.firstMatch.exists ? app.cells.firstMatch : app.buttons.element(boundBy: 2)
        guard firstRoom.waitForExistence(timeout: 5) else {
            throw XCTSkip("no room on this device to walk into")
        }
        firstRoom.tap()

        XCTAssertTrue(
            app.textFields.firstMatch.waitForExistence(timeout: 5)
                || app.textViews.firstMatch.waitForExistence(timeout: 5),
            "the composer never appeared, so this is not a conversation")

        assertNothingIsSilent(on: "Conversation")
    }

    func testTheComposerFieldIsNamed() throws {
        let rooms = app.buttons["Rooms"]
        if rooms.waitForExistence(timeout: 5) { rooms.tap() }
        let firstRoom = app.cells.firstMatch
        guard firstRoom.waitForExistence(timeout: 5) else {
            throw XCTSkip("no room on this device to walk into")
        }
        firstRoom.tap()

        let field = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no composer field")
        XCTAssertFalse(
            described(field).isEmpty,
            "the composer announces nothing, so VoiceOver cannot say what typing here does")
    }

    private func open(_ label: String) -> Bool {
        let target = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        guard target.waitForExistence(timeout: 8) else {
            XCTFail("\(label) never appeared")
            return false
        }
        if !target.isHittable { app.swipeUp() }
        target.tap()
        return true
    }

    func testYouAndItsSettingsSaySomethingForEveryStop() throws {
        guard open("You") else { return }
        assertNothingIsSilent(on: "You")
        guard open("Privacy & Safety") else { return }
        assertNothingIsSilent(on: "Privacy & Safety")
        app.navigationBars.buttons.firstMatch.tap()
        guard open("Behavior") else { return }
        assertNothingIsSilent(on: "Behavior")
    }

    func testJoiningARoomSaysSomethingForEveryStop() throws {
        guard open("Solos") else { return }
        let join = app.buttons["I have an invite"]
        guard join.waitForExistence(timeout: 8) else { throw XCTSkip("this device has solos") }
        join.tap()
        assertNothingIsSilent(on: "Join a room")
    }

    func testARoomsMenuAndSheetsSaySomethingForEveryStop() throws {
        let rooms = app.buttons["Rooms"]
        if rooms.waitForExistence(timeout: 8) { rooms.tap() }
        guard app.cells.firstMatch.waitForExistence(timeout: 8) else { throw XCTSkip("no room") }
        app.cells.firstMatch.tap()
        guard open("Room settings") else { return }
        assertNothingIsSilent(on: "Room menu")
        guard open("Who this is waiting on") else { return }
        assertNothingIsSilent(on: "Waiting on")
        app.buttons["Done"].tap()
        guard open("Room settings"), open("Who you are talking to") else { return }
        assertNothingIsSilent(on: "Who you are talking to")
    }

}

final class AccessibilityAuditTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["--quiet-for-audit", "-theme.accent", "verdigris"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "the app never came up")
    }

    private func audit(_ screen: String, _ types: XCUIAccessibilityAuditType = .all) {
        do {
            try app.performAccessibilityAudit(for: types) { issue in
                let element = issue.element
                print(
                    "AUDIT \(screen) | \(issue.compactDescription) | \(element?.elementType.rawValue ?? 0) | \(element?.label ?? "?") | \(element.map { NSCoder.string(for: $0.frame) } ?? "")"
                )
                return false
            }
        } catch {
            XCTFail("the audit could not run on \(screen): \(error)")
        }
    }

    func testTheRoomsListPassesApplesAudit() throws {
        audit("Rooms")
    }

    func testEachTabPassesApplesAudit() throws {
        for tab in ["Solos", "Outposts", "You", "Rooms"] {
            let button = app.buttons[tab]
            guard button.waitForExistence(timeout: 8) else {
                XCTFail("the \(tab) tab never appeared")
                continue
            }
            button.tap()
            audit(tab)
        }
    }

    private func open(_ label: String) -> Bool {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        guard row.waitForExistence(timeout: 8) else {
            XCTFail("\(label) never appeared")
            return false
        }
        if !row.isHittable { app.swipeUp() }
        row.tap()
        return true
    }

    func testTheAppearancePagesPassApplesAudit() throws {
        guard open("You"), open("Appearance") else { return }
        audit("Appearance")
        guard open("Color") else { return }
        audit("Color")
    }

    func testPrivacyAndSafetyPassesApplesAudit() throws {
        guard open("You"), open("Privacy & Safety") else { return }
        audit("Privacy & Safety")
    }

    func testJoiningARoomPassesApplesAudit() throws {
        guard open("Solos") else { return }
        let join = app.buttons["I have an invite"]
        guard join.waitForExistence(timeout: 8) else { throw XCTSkip("this device has solos") }
        join.tap()
        audit("Join a room")
    }

    func testARoomsOwnSheetsPassApplesAudit() throws {
        let rooms = app.buttons["Rooms"]
        if rooms.waitForExistence(timeout: 8) { rooms.tap() }
        let room = app.cells.firstMatch
        guard room.waitForExistence(timeout: 8) else { throw XCTSkip("no room on this device") }
        room.tap()
        let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Room settings'")).firstMatch
        guard menu.waitForExistence(timeout: 8) else {
            XCTFail("the room menu never appeared")
            return
        }
        menu.tap()
        guard open("Who this is waiting on") else { return }
        audit("Waiting on")
        app.buttons["Done"].tap()
        menu.tap()
        guard open("Notifications") else { return }
        audit("The room's sheet")
    }

    func testAConversationPassesApplesAudit() throws {
        let rooms = app.buttons["Rooms"]
        if rooms.waitForExistence(timeout: 8) { rooms.tap() }
        let room = app.cells.firstMatch
        guard room.waitForExistence(timeout: 8) else { throw XCTSkip("no room on this device") }
        room.tap()
        audit("Conversation")
    }
}
