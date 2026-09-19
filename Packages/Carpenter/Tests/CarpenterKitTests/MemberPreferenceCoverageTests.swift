import Foundation
import Testing
import CarpenterKitTesting

@testable import CarpenterKit

@Suite("Every preference survives the round trip")
struct MemberPreferenceCoverageTests {
    private static let person = ParticipantID(rawValue: WideID.of([9]))
    private static let room = RoomID()
    private static let entry = EntryHash(rawValue: Data(repeating: 3, count: 32))

    private static func populated() -> MemberPreferences {
        let stamp = OrganisationStamp(
            at: Date(timeIntervalSince1970: 1_000), device: DeviceID(rawValue: WideID.of([1])))
        var prefs = MemberPreferences()
        prefs.setHidden(true, for: entry, stamp: stamp)
        prefs.setReportsDisplaying(true, stamp: stamp)
        prefs.setReportsDisplaying(false, for: room, stamp: stamp)
        prefs.setNotificationLevel(.everything, stamp: stamp)
        prefs.setNotificationLevel(.everything, for: room, stamp: stamp)
        prefs.setMuted(true, for: room, stamp: stamp)
        prefs.setNotGoneWait(NotGoneWait(days: 6), for: room, stamp: stamp)
        prefs.setChecked(person, at: Date(timeIntervalSince1970: 3_000), stamp: stamp)
        prefs.setOfferedComparison(with: person, stamp: stamp)
        prefs.setDeleted(true, room, stamp: stamp)
        prefs.setBlocked(true, person, stamp: stamp)
        prefs.setNotified(true, about: person, stamp: stamp)
        prefs.setDisplayName("Cassilda", stamp: stamp)
        prefs.setBlurb("Keeping the masthead honest", stamp: stamp)
        prefs.setAnonPersona(AnonPersona(face: .cheshire, name: "Somebody"), stamp: stamp)
        prefs.setOffersOutpostReview(false, stamp: stamp)
        prefs.setOutpostConsent(.closed, stamp: stamp)
        prefs.setShowsPhotoOnOutpost(false, stamp: stamp)
        prefs.setSharesName(true, stamp: stamp)
        prefs.setSharesAvatar(true, stamp: stamp)
        prefs.setShowsOthersNames(true, stamp: stamp)
        prefs.setShowsOthersAvatars(true, stamp: stamp)
        prefs.setNickname("Cass", for: person, stamp: stamp)
        prefs.setSharesFocus(true, stamp: stamp)
        prefs.setShowsOthersFocus(true, stamp: stamp)
        prefs.setUsesCustomFocusMessage(true, stamp: stamp)
        prefs.setFocusMessage("Heads down", stamp: stamp)
        prefs.setToldAboutRestores(true, stamp: stamp)
        prefs.setRequiresLongPhrase(true, stamp: stamp)
        prefs.setHoldsHistoryForRestores(true, stamp: stamp)
        prefs.setAsksPeersForHistory(false, stamp: stamp)
        prefs.setName("The one in my pocket", for: DeviceID(rawValue: WideID.of([4])), stamp: stamp)
        prefs.setPrivacyCheckedUp(true, stamp: stamp)
        prefs.setRequiresSoloCheck(true, stamp: stamp)
        prefs.setHoldingSolo(true, for: room, stamp: stamp)
        prefs.setSavedRecoveryKey(Date(timeIntervalSince1970: 2_000), stamp: stamp)
        prefs.setOutpostNotifications(
            OutpostNotificationChoices(
                newPosts: .all, repliesOnPostsICommentedOn: false, repliesOnPostsIReactedTo: true,
                commentsOnMyPosts: false, likesOnMyPosts: true),
            stamp: stamp)
        prefs.setMessagingNotifications(
            MessagingNotificationChoices(
                wantsMessages: false, level: .whereOnly, wantsRoomUpdates: false,
                roomUpdateLevel: .nothing),
            stamp: stamp)
        prefs.setBadges(BadgeChoices(messages: false, outposts: true), stamp: stamp)
        prefs.claimSupporterYear(at: Date(timeIntervalSince1970: 4_000), stamp: stamp)
        prefs.startSupporterYear(at: Date(timeIntervalSince1970: 5_000), stamp: stamp)
        prefs.setShowsSupporterBadge(true, stamp: stamp)
        prefs.setSharesSupporterBadge(true, stamp: stamp)
        return prefs
    }

    private static func fields(of prefs: MemberPreferences) -> [String: String] {
        var found: [String: String] = [:]
        for child in Mirror(reflecting: prefs).children {
            guard let label = child.label else { continue }
            found[label] = String(describing: child.value)
        }
        return found
    }

    @Test func everyFieldIsActuallyFilled() {
        let full = Self.fields(of: Self.populated())
        let empty = Self.fields(of: MemberPreferences())
        for (name, value) in empty {
            #expect(
                full[name] != value,
                """
                `\(name)` is still at its default in this suite's `populated()`. \
                Set it there, or every check in this file passes vacuously for it.
                """)
        }
    }

    @Test func everyFieldSurvivesEncodingAndDecoding() throws {
        let before = Self.populated()
        let after = try JSONDecoder().decode(
            MemberPreferences.self, from: try JSONEncoder().encode(before))

        let sent = Self.fields(of: before)
        let arrived = Self.fields(of: after)
        for (name, value) in sent {
            #expect(
                arrived[name] == value,
                """
                `\(name)` did not survive a save and a load. Add it to `CodingKeys` — the encoder \
                is synthesised from that enum — and to `init(from:)`.
                """)
        }
    }

    @Test func everyFieldCrossesToASecondDevice() {
        let theirs = Self.populated()
        let merged = MemberPreferences().merged(with: theirs)

        let sent = Self.fields(of: theirs)
        let arrived = Self.fields(of: merged)
        for (name, value) in sent {
            #expect(
                arrived[name] == value,
                "`\(name)` is not merged, so it never crosses to this member's other devices.")
        }
    }

    @Test func aLaterAnswerWinsWhicheverSideItIsOn() {
        let stamp = OrganisationStamp(
            at: Date(timeIntervalSince1970: 9_000), device: DeviceID(rawValue: WideID.of([2])))
        var later = MemberPreferences()
        later.setShowsPhotoOnOutpost(true, stamp: stamp)

        #expect(Self.populated().merged(with: later).isShowingPhotoOnOutpost)
        #expect(later.merged(with: Self.populated()).isShowingPhotoOnOutpost)
    }
}
