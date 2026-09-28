import Foundation
import Testing

@testable import CarpenterUI

@MainActor
@Suite("The mailbox on You says tap me until it is tapped")
struct TheMailboxSaysTapMeTests {
    private func defaults() -> UserDefaults {
        let name = "mark-bubbles-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test("It asks until the mailbox is tapped, then never again, even on the next launch")
    func goneForGood() {
        let store = defaults()
        let bubbles = MarkBubbles(defaults: store)
        #expect(bubbles.current?.id == "tap-me")
        #expect(bubbles.current?.closable == false, "tap me has no close button")
        bubbles.markTapped()
        #expect(bubbles.current == nil)
        #expect(MarkBubbles(defaults: store).current == nil, "it came back after a relaunch")
    }
}
