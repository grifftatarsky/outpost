import CarpenterKit
import Foundation
import Testing

@Suite("Notification levels")
struct NotificationLevelTests {
    private let room = ConversationID.room(UUID())

    private func copy(_ level: NotificationLevel) -> NotificationCopy {
        MessageNotification.of(
            room: room, roomName: "Hangar 7", author: "Alice", body: "are you coming", level: level)
    }

    @Test("Each rung says less than the one above it")
    func theLadderIsMonotonic() {
        let text = NotificationLevel.allCases.map { copy($0) }
        let leaks = text.map { [$0.title, $0.subtitle, $0.body].filter { !$0.isEmpty }.count }
        #expect(leaks == leaks.sorted(by: >), "a lower rung disclosed more than a higher one")
    }

    @Test("Everything shows the room, the sender and the message")
    func everythingShowsAll() {
        let full = copy(.everything)
        #expect(full.title == "Hangar 7")
        #expect(full.subtitle == "Alice")
        #expect(full.body == "are you coming")
    }

    @Test("Room and sender withholds the words")
    func whoAndWhereWithholdsTheMessage() {
        let c = copy(.whoAndWhere)
        #expect(c.title == "Hangar 7")
        #expect(c.subtitle == "Alice")
        #expect(c.body.isEmpty, "the message was on the lock screen at a rung that forbids it")
    }

    @Test("Room only names nobody")
    func whereOnlyNamesNobody() {
        let c = copy(.whereOnly)
        #expect(c.title == "Hangar 7")
        #expect(c.subtitle.isEmpty)
        #expect(c.body.isEmpty)
        #expect(!c.isGeneric, "a room-only banner is decrypted content, not the fallback")
    }

    @Test("The quietest rung is the content-free banner")
    func nothingIsGeneric() {
        #expect(copy(.nothing) == MessageNotification.generic)
    }

    @Test("The quietest rung does not group by room")
    func nothingDoesNotGroup() {
        #expect(!copy(.nothing).groupsByRoomThread)
        for rung in [NotificationLevel.everything, .whoAndWhere, .whereOnly] {
            #expect(copy(rung).groupsByRoomThread, "\(rung) lost its conversation grouping")
        }
    }

    @Test("A message with nothing to say falls back at every rung")
    func incompleteFallsBack() {
        for rung in NotificationLevel.allCases {
            let c = MessageNotification.of(
                room: room, roomName: "Hangar 7", author: "", body: "hello", level: rung)
            #expect(c.isGeneric, "\(rung) drew a banner from a message with no author")
        }
    }
}

extension NotificationCopy {
    fileprivate var groupsByRoomThread: Bool { !threadID.isEmpty }
}

@Suite struct SilencingTests {
    private func room() -> ConversationID { ConversationID.room(UUID()) }
    private func stamp(_ at: TimeInterval, device: UInt8 = 1) -> OrganisationStamp {
        OrganisationStamp(
            at: Date(timeIntervalSince1970: at), device: DeviceID(rawValue: Data([device])))
    }

    @Test("A silenced conversation has nothing to say")
    func silencingDropsTheLevel() {
        var preferences = MemberPreferences()
        let quiet = room()
        preferences.setMuted(true, for: quiet, stamp: stamp(10))

        #expect(preferences.isMuted(quiet))
        #expect(preferences.isMuted(room()) == false, "silence is per conversation")
    }

    @Test("Unsilencing restores the level that was set before")
    func unsilencingRestores() {
        var preferences = MemberPreferences()
        let quiet = room()
        preferences.setNotificationLevel(.whereOnly, for: quiet, stamp: stamp(10))
        preferences.setMuted(true, for: quiet, stamp: stamp(20))
        preferences.setMuted(false, for: quiet, stamp: stamp(30))

        #expect(preferences.isMuted(quiet) == false)
        #expect(preferences.notificationLevel(for: quiet) == .whereOnly)
    }

    @Test("Two devices silencing different rooms keep both")
    func mergesPerRoom() {
        let phone = room()
        let mac = room()
        var onPhone = MemberPreferences()
        onPhone.setMuted(true, for: phone, stamp: stamp(10, device: 1))
        var onMac = MemberPreferences()
        onMac.setMuted(true, for: mac, stamp: stamp(11, device: 2))

        let merged = onPhone.merged(with: onMac)
        #expect(merged.isMuted(phone))
        #expect(merged.isMuted(mac))
    }
}
