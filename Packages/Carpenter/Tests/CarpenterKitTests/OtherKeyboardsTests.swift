import CarpenterUI
import Foundation
import Testing

@Suite("Keyboards from other apps are refused unless the member allows them")
struct OtherKeyboardsTests {
    private func defaults() -> UserDefaults {
        let name = "keyboards-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Out of the box, another app's keyboard is refused and nothing else is")
    func refusedByDefault() {
        let fresh = defaults()
        #expect(!OtherKeyboards.allows(extensionPoint: OtherKeyboards.keyboardExtensionPoint, defaults: fresh))
        #expect(OtherKeyboards.allows(extensionPoint: "com.apple.share-services", defaults: fresh))
    }

    @Test("Allowing them in Privacy & Safety lets them in")
    func allowedWhenAsked() {
        let allowing = defaults()
        allowing.set(true, forKey: OtherKeyboards.key)
        #expect(OtherKeyboards.allows(extensionPoint: OtherKeyboards.keyboardExtensionPoint, defaults: allowing))
        allowing.set(false, forKey: OtherKeyboards.key)
        #expect(!OtherKeyboards.allows(extensionPoint: OtherKeyboards.keyboardExtensionPoint, defaults: allowing))
    }
}
