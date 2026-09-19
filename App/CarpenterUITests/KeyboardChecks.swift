import XCTest

@MainActor
final class KeyboardChecks: XCTestCase {
    private var report: [String] = []

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OUTPOST_KEYS"] == "1",
            "a keyboard walk: set TEST_RUNNER_OUTPOST_KEYS=1 on an iPhone with the software keyboard")
        continueAfterFailure = true
    }

    override func tearDown() {
        let attachment = XCTAttachment(string: report.joined(separator: "\n"))
        attachment.name = "keyboard report"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? report.joined(separator: "\n").write(
            toFile: "/tmp/outpost-keyboard-report.txt", atomically: true, encoding: .utf8)
    }

    private func launch(_ shot: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--site-shot", shot, "-theme.accent", "verdigris"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        sleep(2)
        return app
    }

    private func field(_ app: XCUIApplication, _ placeholder: String) -> XCUIElement {
        let predicate = NSPredicate(format: "placeholderValue == %@ OR label == %@", placeholder, placeholder)
        let view = app.textViews.matching(predicate).firstMatch
        if view.waitForExistence(timeout: 3) { return view }
        let single = app.textFields.matching(predicate).firstMatch
        if single.exists { return single }
        try? app.debugDescription.write(
            toFile: "/tmp/outpost-keyboard-\(placeholder).txt", atomically: true, encoding: .utf8)
        return app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
    }

    private func tap(_ app: XCUIApplication, _ prefix: String) {
        let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        if button.waitForExistence(timeout: 4) {
            button.tap()
            sleep(2)
        } else {
            report.append("\(prefix): not found")
        }
    }

    private static let returnKeys = [
        "return", "Return", "Done", "done", "Next", "next", "Go", "go", "Send", "send", "Search", "search",
        "Join", "join", "Continue", "continue", "Route", "route",
    ]

    private func shoot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func focused(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
    }

    private func holding(_ app: XCUIApplication, _ typed: String) -> String {
        let predicate = NSPredicate(format: "value CONTAINS %@", typed)
        let view = app.textViews.matching(predicate).firstMatch
        if view.exists { return (view.value as? String) ?? "" }
        let single = app.textFields.matching(predicate).firstMatch
        return single.exists ? ((single.value as? String) ?? "") : ""
    }

    private func probe(_ app: XCUIApplication, _ name: String, _ input: XCUIElement, expecting: String) {
        guard input.waitForExistence(timeout: 5) else {
            report.append("\(name): not reached")
            return
        }
        for _ in 0..<4 where app.keyboards.count == 0 {
            input.tap()
            sleep(1)
        }
        guard app.keyboards.count > 0 else {
            report.append("\(name): no software keyboard came up")
            return
        }
        let typed = "q\(name.count)z"
        focused(app).typeText(typed)
        let labels = app.keyboards.buttons.allElementsBoundByIndex.map(\.label)
        let key = Self.returnKeys.first { labels.contains($0) } ?? "?"
        shoot("\(name) typed")
        if key != "?" { app.keyboards.buttons[key].firstMatch.tap() }
        sleep(1)
        let value = holding(app, typed)
        let stillUp = app.keyboards.count > 0
        let doneAbove = app.toolbars.buttons["Done"].exists
        var line = "\(name): key \"\(key)\"; return \(value.contains("\n") ? "wrote a line" : "wrote no line"); keyboard \(stillUp ? "up" : "down")"
        if stillUp {
            line += doneAbove ? "; Done above" : "; nothing above"
            if doneAbove {
                app.toolbars.buttons["Done"].firstMatch.tap()
                sleep(1)
                line += app.keyboards.count > 0 ? ", which did NOT put it away" : ", which put it away"
            }
        }
        line += " — expected \(expecting)"
        report.append(line)
        shoot("\(name) after")
    }

    private func longPress(_ app: XCUIApplication, _ text: String) -> Bool {
        let bubble = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        guard bubble.waitForExistence(timeout: 4) else { return false }
        bubble.press(forDuration: 1.2)
        sleep(1)
        return true
    }

    func testTheRestOfThem() {
        let tags = launch("rooms")
        tap(tags, "Rooms list options")
        tap(tags, "Manage tags")
        probe(tags, "New tag", field(tags, "New tag"), expecting: "next, keyboard stays for the next tag")
        tags.terminate()

        let post = launch("outposts")
        tap(post, "New post")
        probe(post, "New post", post.textViews.firstMatch, expecting: "return writes a line; Done above")
        post.terminate()

        let rooms = launch("rooms")
        tap(rooms, "Zeppelin Enthusiasts")
        let composer = field(rooms, "Message")
        if composer.waitForExistence(timeout: 4) {
            for _ in 0..<4 where rooms.keyboards.count == 0 {
                composer.tap()
                sleep(1)
            }
            let window = rooms.windows.firstMatch
            for (from, to) in [(0.35, 0.98), (0.25, 0.99)] where rooms.keyboards.count > 0 {
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
                    .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to)))
                sleep(1)
            }
            shoot("Conversation composer after dragging")
            report.append("Conversation composer: dragging the conversation down put the keyboard \(rooms.keyboards.count > 0 ? "NOWHERE" : "away")")
        }
        rooms.terminate()
    }

    func testEveryFieldTheDemoReaches() {
        let you = launch("you")
        tap(you, "Outpost settings")
        probe(you, "Outpost blurb", field(you, "A line about you"), expecting: "done, no line, down")
        probe(you, "Stranger's name", you.textFields.firstMatch, expecting: "done, down")
        you.terminate()

        let rooms = launch("rooms")
        tap(rooms, "Zeppelin Enthusiasts")
        probe(rooms, "Conversation composer", field(rooms, "Message"), expecting: "return writes a line; drag to dismiss")
        rooms.terminate()

        let edit = launch("rooms")
        tap(edit, "Zeppelin Enthusiasts")
        if longPress(edit, "a piano. inside") {
            tap(edit, "More actions")
            tap(edit, "Edit")
            probe(edit, "Editing a message", edit.textViews.firstMatch, expecting: "return writes a line; Done above")
        } else {
            report.append("Editing a message: not reached")
        }
        edit.terminate()

        let report = launch("rooms")
        tap(report, "Zeppelin Enthusiasts")
        if longPress(report, "Graf Zeppelin") {
            tap(report, "More actions")
            tap(report, "Report")
            probe(report, "Report", field(report, "What happened?"), expecting: "return writes a line; Done above")
        } else {
            self.report.append("Report: not reached")
        }
        report.terminate()

        let emoji = launch("rooms")
        tap(emoji, "Zeppelin Enthusiasts")
        if longPress(emoji, "Graf Zeppelin") {
            tap(emoji, "More reactions")
            probe(emoji, "Emoji search", field(emoji, "Search by name"), expecting: "search, down")
        } else {
            self.report.append("Emoji search: not reached")
        }
        emoji.terminate()

        let invite = launch("rooms")
        tap(invite, "Zeppelin Enthusiasts")
        tap(invite, "Room settings")
        tap(invite, "Invite someone")
        probe(invite, "Invite code", field(invite, "Paste their code"), expecting: "done, no line, down")
        invite.terminate()

        let newRoom = launch("rooms")
        tap(newRoom, "New room")
        if !newRoom.textFields.firstMatch.waitForExistence(timeout: 2) {
            tap(newRoom, "New")
            tap(newRoom, "New room")
        }
        probe(newRoom, "New room name", field(newRoom, "Name"), expecting: "done, down")
        newRoom.terminate()

        let tags = launch("rooms")
        tap(tags, "Rooms list options")
        tap(tags, "Manage tags")
        probe(tags, "New tag", field(tags, "New tag"), expecting: "next, keyboard stays for the next tag")
        tags.terminate()

        let post = launch("outposts")
        tap(post, "New post")
        probe(post, "New post", post.textViews.firstMatch, expecting: "return writes a line; Done above")
        post.terminate()
    }
}
