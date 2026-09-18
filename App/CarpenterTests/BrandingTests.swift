import Testing

import CarpenterKit

@Suite("Branding")
struct BrandingTests {
    @Test("The app reads its own name out of the bundle")
    func displayNameResolves() {
        #expect(!Branding.displayName.isEmpty)
    }

    @Test("The name in the bundle is the one the branding config sets")
    func displayNameMatchesConfiguration() {
        #expect(Branding.displayName == "Outpost")
    }
}
