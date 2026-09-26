import Foundation
import SwiftUI
import Testing

@testable import CarpenterUI

@MainActor
@Suite("Help on every screen")
struct HelpOnEveryScreenTests {

    private func defaults(_ name: String) -> UserDefaults {
        let suite = UserDefaults(suiteName: "help-tests-\(name)-\(UUID().uuidString)")!
        return suite
    }

    @Test("It is off until somebody turns it on")
    func offByDefault() {
        let theme = ThemeStore(defaults: defaults("default"))
        #expect(
            !theme.tutorialMode,
            "help on every screen should be something a member opts into, not something they meet")
    }

    @Test("Turning it on writes it down, so it survives the app being closed")
    func turningItOnPersists() {
        let store = defaults("persist")
        let theme = ThemeStore(defaults: store)
        theme.tutorialMode = true

        #expect(
            store.bool(forKey: "theme.tutorialMode"),
            """
            The switch moved and nothing was written. This is the first half of the defect that has \
            bitten twice: a preference nobody stores is a preference nobody can read back.
            """)

        let relaunched = ThemeStore(defaults: store)
        #expect(
            relaunched.tutorialMode,
            "the setting did not survive a relaunch, so the `?` would vanish on the next launch")
    }

    @Test("Turning it off again writes that too")
    func turningItOffPersists() {
        let store = defaults("off")
        let theme = ThemeStore(defaults: store)
        theme.tutorialMode = true
        theme.tutorialMode = false

        #expect(!ThemeStore(defaults: store).tutorialMode, "turning it back off did not stick")
    }

    @Test("The environment value the button reads is off unless it is set")
    func theEnvironmentDefaultIsOff() {
        let values = EnvironmentValues()
        #expect(!values.showsHelp)
    }
}
