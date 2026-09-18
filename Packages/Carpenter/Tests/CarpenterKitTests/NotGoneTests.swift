@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("A message is only called not gone when nobody has it and waiting stopped being ordinary")
struct NotGoneTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let me = Member(id: ParticipantID(rawValue: WideID.of([1])), displayName: "Me")
    private let them = Member(id: ParticipantID(rawValue: WideID.of([2])), displayName: "Them")
    private let day: TimeInterval = 86_400

    private func message(
        _ number: UInt8, _ delivery: DeliveryState, hoursAgo: Double = 0, mine: Bool = true
    ) -> Message {
        Message(
            id: MessageID(entry: EntryHash(rawValue: Data(repeating: number, count: 32))),
            author: mine ? me : them, body: "\(number)",
            sentAt: start.addingTimeInterval(-hoursAgo * 3_600), isMine: mine, delivery: delivery)
    }

    @Test("Waiting a while for somebody to open the app is ordinary and says nothing")
    func waitingIsOrdinary() {
        let messages = [message(1, .sent, hoursAgo: 71)]
        #expect(NotGone.notices(in: messages, now: start, wait: .standard).isEmpty)
    }

    @Test("Past the room's chosen time, a message nobody has collected is called out")
    func pastTheChosenTime() {
        let waited = message(1, .sent, hoursAgo: 72)
        let notices = NotGone.notices(in: [waited], now: start, wait: .standard)
        #expect(notices[waited.id] == NotGone(signal: .waited(days: 3), hasLeftThisDevice: true))
    }

    @Test("One newer message collected is not proof; two are")
    func newerMessagesAreProof() {
        let stuck = message(1, .sent, hoursAgo: 1)
        let one = [stuck, message(2, .delivered)]
        #expect(NotGone.notices(in: one, now: start, wait: .off).isEmpty)

        let two = [stuck, message(2, .delivered), message(3, .displayed(at: start))]
        #expect(
            NotGone.notices(in: two, now: start, wait: .off)[stuck.id]
                == NotGone(signal: .newerMessagesCollected(2), hasLeftThisDevice: true))
    }

    @Test("Somebody else's messages are not evidence about mine")
    func onlyMyOwnCount() {
        let stuck = message(1, .sent)
        let messages = [stuck, message(2, .pending, mine: false), message(3, .pending, mine: false)]
        #expect(NotGone.notices(in: messages, now: start, wait: .off).isEmpty)
    }

    @Test("Anything collected by anybody has gone, however long ago it was sent")
    func collectedHasGone() {
        for delivery in [DeliveryState.delivered, .notReported, .displayed(at: start)] {
            #expect(
                NotGone.notices(in: [message(1, delivery, hoursAgo: 24 * 30)], now: start, wait: .standard)
                    .isEmpty)
        }
    }

    @Test("A room with nobody to send to has its own mark and is not called out")
    func nobodyToReachIsItsOwnMark() {
        #expect(
            NotGone.notices(in: [message(1, .noRecipients, hoursAgo: 24 * 30)], now: start, wait: .standard)
                .isEmpty)
    }

    @Test("Off leaves only the newer-messages signal")
    func offLeavesOnlyProof() {
        let old = message(1, .pending, hoursAgo: 24 * 30)
        #expect(NotGone.notices(in: [old], now: start, wait: .off).isEmpty)
        let notice = NotGone.notices(
            in: [old, message(2, .delivered), message(3, .delivered)], now: start, wait: .off)[old.id]
        #expect(notice == NotGone(signal: .newerMessagesCollected(2), hasLeftThisDevice: false))
    }

    @Test("The time is whole days from one to seven")
    func theTimeIsClamped() {
        #expect(NotGoneWait(days: 0).days == 1)
        #expect(NotGoneWait(days: 12).days == 7)
        #expect(NotGoneWait(days: nil).days == nil)
        #expect(NotGoneWait.standard.days == 3)
    }

    @Test("A room's time is kept, and follows the member to their other devices")
    func theTimeIsARoomPreference() throws {
        let room = RoomID()
        var here = MemberPreferences()
        #expect(here.notGoneWait(for: room) == .standard)

        here.setNotGoneWait(NotGoneWait(days: 6), for: room, stamp: OrganisationStamp(at: start, device: DeviceID(rawValue: WideID.of([7]))))
        let decoded = try JSONDecoder().decode(
            MemberPreferences.self, from: try JSONEncoder().encode(here))
        #expect(decoded.notGoneWait(for: room) == NotGoneWait(days: 6))
        #expect(MemberPreferences().merged(with: here).notGoneWait(for: room) == NotGoneWait(days: 6))
    }

    @MainActor
    @Test("A conversation marks a message that has waited past the room's time, and only that one")
    func theSessionMarksIt() async throws {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let alice = TestSession.make(clock: clock)
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Hangar 7")
        try await join(bob, into: room, of: alice, through: mailbox)

        try await alice.send("nobody collects this", to: room)
        try await alice.sync(through: mailbox)
        let sent = try #require(alice.messages(in: room).last)
        #expect(sent.notGone == nil, "precondition: it has only just gone")

        clock.advance(by: 3 * day)
        let waited = try #require(alice.messages(in: room).last)
        #expect(waited.notGone?.signal == .waited(days: 3))
        #expect(
            alice.transcript(in: room).compactMap(\.message).last?.notGone == waited.notGone,
            "the transcript and the message list disagreed")

        await alice.setNotGoneWait(.off, in: room)
        #expect(alice.messages(in: room).last?.notGone == nil)
    }
}
