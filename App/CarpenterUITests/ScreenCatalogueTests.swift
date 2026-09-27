import XCTest

@MainActor
final class ScreenCatalogueTests: XCTestCase {
    private var app: XCUIApplication!
    private var seen = Set<String>()
    private var shots = 0

    private let refused = ["erase", "delete", "nuke", "sign out", "subscribe", "purchase", "buy"]
    private let dismissals = [
        "Cancel", "Not now", "Done", "Close", "Keep", "Keep it", "Don't approve", "OK", "Back",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CARPENTER_SCREEN_CATALOGUE"] == "1",
            "a catalogue run: set TEST_RUNNER_CARPENTER_SCREEN_CATALOGUE=1 to photograph every screen")
    }

    func testEveryTabAndWhatItOpens() throws {
        launch("you")
        let tabs = app.tabBars.buttons.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
        for tab in tabs {
            launch("you")
            let button = app.tabBars.buttons[tab]
            guard button.waitForExistence(timeout: 5) else { continue }
            button.tap()
            settle()
            shoot([tab])
            walk([tab], depth: 0)
        }
    }

    func testTheScreensReachedFromOutsideTheTabs() throws {
        for start in ["conversation", "verify", "audience", "checkup", "supporter"] {
            launch(start)
            shoot([start])
            walk([start], depth: 0)
        }
    }

    private func launch(_ shot: String) {
        app = XCUIApplication()
        app.launchArguments = ["--site-shot", shot, "-theme.accent", "verdigris"]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 20)
        settle()
    }

    private func settle() {
        _ = app.activityIndicators.firstMatch.waitForNonExistence(timeout: 2)
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func shoot(_ path: [String]) {
        let name = path.joined(separator: " › ")
        guard !seen.contains(name) else { return }
        seen.insert(name)
        shots += 1
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = String(format: "%03d ", shots) + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func everything() -> [XCUIElementSnapshot] {
        guard let root = try? app.snapshot() else { return [] }
        var all: [XCUIElementSnapshot] = []
        var queue = [root]
        while let next = queue.popLast() {
            all.append(next)
            queue.append(contentsOf: next.children)
        }
        return all
    }

    private func signature() -> String {
        let all = everything()
        let bars = all.filter { $0.elementType == .navigationBar }
        let titles = bars.flatMap { bar in bar.children.filter { $0.elementType == .staticText }.map(\.label) }
        let alerts = all.filter { $0.elementType == .alert }.count
        let sheets = all.filter { $0.elementType == .sheet }.count
        let popover = all.contains { $0.identifier == "PopoverDismissRegion" }
        return "\(bars.map(\.identifier))#\(titles)#\(alerts)#\(sheets)#\(popover)"
    }

    private func isRefused(_ label: String) -> Bool {
        let lower = label.lowercased()
        return refused.contains { lower.contains($0) }
    }

    private func targets() -> [String] {
        var labels: [String] = []
        func add(_ label: String) {
            if !label.isEmpty, !labels.contains(label) { labels.append(label) }
        }
        func texts(_ node: XCUIElementSnapshot) -> [String] {
            (node.elementType == .staticText && !node.label.isEmpty ? [node.label] : [])
                + node.children.flatMap(texts)
        }
        func firstText(_ node: XCUIElementSnapshot) -> String {
            let found = texts(node)
            return found.first { $0.count > 3 } ?? found.first ?? ""
        }
        let all = everything()
        for cell in all.filter({ $0.elementType == .cell }).prefix(30) {
            add(cell.label.isEmpty ? firstText(cell) : cell.label)
        }
        for bar in all.filter({ $0.elementType == .navigationBar }) {
            for button in bar.children.filter({ $0.elementType == .button }) where button.identifier != "BackButton" {
                add(button.label)
            }
        }
        return labels.filter { !isRefused($0) && !dismissals.contains($0) }
    }

    private func element(_ label: String) -> XCUIElement? {
        let cell = app.cells.containing(NSPredicate(format: "label == %@", label)).firstMatch
        if cell.exists { return cell }
        let named = app.cells[label]
        if named.exists { return named }
        let barButton = app.navigationBars.firstMatch.buttons[label]
        if barButton.exists { return barButton }
        let text = app.cells.staticTexts[label]
        if text.exists { return text }
        return nil
    }

    private func reveal(_ element: XCUIElement) -> Bool {
        let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
        guard list.exists else { return element.isHittable }
        let middle = app.windows.firstMatch.frame.midY
        var tries = 0
        while !element.isHittable, tries < 8 {
            if element.frame.minY < middle { list.swipeDown(velocity: .slow) } else { list.swipeUp(velocity: .slow) }
            tries += 1
        }
        return element.isHittable
    }

    private func walk(_ path: [String], depth: Int) {
        guard depth < 3 else { return }
        for label in targets() {
            let before = signature()
            guard let target = element(label), reveal(target) else { continue }
            target.tap()
            settle()
            if app.keyboards.count > 0 {
                app.navigationBars.firstMatch.tap()
                settle()
            }
            guard signature() != before else { continue }
            let next = path + [label]
            shoot(next)
            if app.alerts.count == 0, app.sheets.count == 0 {
                walk(next, depth: depth + 1)
            }
            if !back(to: before) {
                relaunch(into: path)
            }
        }
    }

    private func back(to before: String) -> Bool {
        for _ in 0..<4 {
            if signature() == before { return true }
            let alert = app.alerts.firstMatch
            let sheet = app.sheets.firstMatch
            let popover = app.otherElements["PopoverDismissRegion"]
            let backButton = app.navigationBars.buttons["BackButton"]
            if alert.exists {
                guard let cancel = alert.buttons.allElementsBoundByIndex.first(where: { dismissals.contains($0.label) })
                else { return false }
                cancel.tap()
            } else if sheet.exists {
                guard let cancel = sheet.buttons.allElementsBoundByIndex.first(where: { dismissals.contains($0.label) })
                else { return false }
                cancel.tap()
            } else if popover.exists {
                popover.tap()
            } else if backButton.exists, backButton.isHittable {
                backButton.tap()
            } else if let close = dismissals.lazy.map({ self.app.navigationBars.buttons[$0] })
                .first(where: { $0.exists && $0.isHittable })
            {
                close.tap()
            } else {
                app.swipeDown(velocity: .fast)
            }
            settle()
        }
        return signature() == before
    }

    private func relaunch(into path: [String]) {
        let start = path.first ?? "you"
        let isTab = app.tabBars.buttons[start].exists || ["Solos", "Rooms", "Outposts", "You", "Search"].contains(start)
        launch(isTab ? "you" : start)
        if isTab {
            app.tabBars.buttons[start].tap()
            settle()
        }
        for label in path.dropFirst() {
            guard let target = element(label), reveal(target) else { return }
            target.tap()
            settle()
        }
    }
}
