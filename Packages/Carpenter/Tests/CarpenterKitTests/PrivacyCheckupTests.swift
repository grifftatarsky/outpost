@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import CarpenterUI
import Foundation
import Testing

@MainActor
@Suite("The privacy check-up", .serialized)
struct PrivacyCheckupTests {
    @Test("A new member is asked once, and not again after a relaunch")
    func askedOnce() async throws {
        let keychain = InMemoryKeychainStore()
        let directory = URL.temporaryDirectory.appending(path: "checkup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = TestSession.make(keychain: keychain, at: directory)
        await session.load()
        #expect(!session.needsPrivacyCheckup, "nothing is owed before there is a member")
        try await session.createIdentity(displayName: "Alice")
        #expect(session.needsPrivacyCheckup)

        await session.markPrivacyCheckedUp()
        #expect(!session.needsPrivacyCheckup)

        let relaunched = TestSession.make(keychain: keychain, at: directory)
        await relaunched.load()
        #expect(relaunched.state == .ready)
        #expect(!relaunched.needsPrivacyCheckup, "asked again on the next launch")
    }

    @Test("Familiar shares the way Messages does; locked down shares nothing")
    func presets() {
        let familiar = PrivacyChoices.familiar
        #expect(familiar.sharing.sharesName && familiar.sharing.showsOthersNames)
        #expect(familiar.sharing.sharesAvatar && familiar.sharing.showsOthersAvatars)
        #expect(familiar.focus.sharesFocus && familiar.focus.showsOthersFocus)

        let locked = PrivacyChoices.lockedDown
        #expect(!locked.sharing.sharesName && !locked.sharing.showsOthersNames)
        #expect(!locked.sharing.sharesAvatar && !locked.sharing.showsOthersAvatars)
        #expect(!locked.focus.sharesFocus && !locked.focus.showsOthersFocus)

        for preset in [familiar, locked] {
            #expect(preset.blursSensitiveMedia && preset.blocksKnownAbusers, "safety stays on either way")
            #expect(
                !preset.reportsDisplaying,
                """
                Read receipts are off whatever the preset says — Griff, 2026-09-12: "Messages does \
                not show read receipts until somebody asks for them; neither do we." Familiar used \
                to turn them on, which is the one thing it was not allowed to do.
                """)
        }

        #expect(
            !MemberPreferences().isReportingDisplaying,
            "a bare install reports before anybody has asked it to")

        #expect(familiar.outposts.consent == .open && familiar.outposts.offersReview)
        #expect(familiar.outposts.showsPhoto)
        #expect(locked.outposts.consent == .closed && !locked.outposts.offersReview)
        #expect(!locked.outposts.showsPhoto)
        #expect(locked.outposts.isOn, "closed is the locked-down shape of taking part, not leaving")

        #expect(OutpostChoices().showsPhoto == MemberPreferences().isShowingPhotoOnOutpost)
    }

    @Test("A preset sets every switch the session owns, at once")
    func applyingAPreset() async throws {
        let session = TestSession.make()
        await session.load()
        try await session.createIdentity(displayName: "Alice")
        #expect(!session.sharesName && !session.showsOthersNames && !session.reportsDisplaying)

        await session.setSharing(PrivacyChoices.familiar.sharing)
        await session.setReportsDisplaying(PrivacyChoices.familiar.reportsDisplaying)
        #expect(session.sharesName && session.showsOthersNames)
        #expect(session.sharesAvatar && session.showsOthersAvatars)
        #expect(
            !session.reportsDisplaying,
            """
            Taking the familiar preset turned read receipts on. It is the one switch the presets \
            do not reach: off by default, on only when the member asks for it.
            """)

        await session.setReportsDisplaying(true)
        #expect(session.reportsDisplaying, "asking for receipts by hand still works")

        await session.setSharing(PrivacyChoices.lockedDown.sharing)
        #expect(!session.sharesName && !session.showsOthersNames)
    }
}
