import Foundation
import SwiftUI
import Testing

@testable import CarpenterUI

/// *Help on every screen* has been broken twice, the same way both times: the switch moved, and the
/// preference behind it reached nothing that draws the `?`.
///
/// The first time, the preference was written and never read. That was fixed on the desktop path.
/// The second time — found by walking the rig on 2026-09-15 — the **iPhone** tab constructed its own
/// `YouView` and simply left `tutorialMode:` off the argument list, so it took the `.constant(false)`
/// default. The switch moved, wrote nothing, and no `?` ever appeared on the only platform this app
/// ships on. The desktop path had the binding all along.
///
/// The structural fix is that there is one `youScreen` now, used by both, so the two argument lists
/// cannot drift apart again. These tests hold the storage underneath it.
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
        // `showsHelp` is what `helpButton()` consults. Its default has to be off, or every screen
        // would carry a `?` for members who never asked for one — including before onboarding.
        let values = EnvironmentValues()
        #expect(!values.showsHelp)
    }
}
