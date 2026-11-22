import CarpenterUI
import Testing
import UIKit

@Suite("The keyboard rule names the system's own keyboard extension point")
struct KeyboardExtensionPointTests {
    @Test("The identifier the rule refuses is the one iOS asks about")
    func identifierMatches() {
        #expect(UIApplication.ExtensionPointIdentifier.keyboard.rawValue == OtherKeyboards.keyboardExtensionPoint)
    }
}
