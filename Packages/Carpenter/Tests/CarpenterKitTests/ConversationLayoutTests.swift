import Foundation
import Testing

@testable import CarpenterKit

@Suite("Conversation layout")
struct ConversationLayoutTests {
    private let hastur = Member(id: Identity.generate().id, displayName: "Hastur")
    private let yhtill = Member(id: Identity.generate().id, displayName: "Yhtill")
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func message(
        _ body: String, from author: Member, isMine: Bool = false, secondsIn: TimeInterval = 0
    ) -> Message {
        Message(
            id: MessageID(
                entry: EntryHash(rawValue: Data(repeating: UInt8(Int(secondsIn) % 256), count: 32))),
            author: author, body: body, sentAt: start.addingTimeInterval(secondsIn), isMine: isMine)
    }

    @Test("Consecutive messages from one person become one run")
    func groupsBySpeaker() {
        let runs = ConversationLayout.runs(from: [
            message("one", from: hastur),
            message("two", from: yhtill, secondsIn: 10),
            message("three", from: yhtill, secondsIn: 20),
        ])

        #expect(runs.count == 2)
        #expect(runs[0].author == hastur)
        #expect(runs[1].messages.count == 2)
    }

    private func notice(_ n: UInt8, at secondsIn: TimeInterval = 0) -> TranscriptEntry {
        .notice(
            RoomNotice(
                id: EntryHash(rawValue: Data(repeating: 200 &+ n, count: 32)),
                kind: .invited(yhtill, by: hastur),
                at: start.addingTimeInterval(secondsIn)))
    }

    @Test("Consecutive notices know where they sit in the run")
    func noticesKnowTheirRun() {
        let items = ConversationLayout.items(from: [
            .message(message("one", from: hastur)),
            notice(1, at: 10),
            notice(2, at: 20),
            notice(3, at: 30),
            .message(message("two", from: yhtill, secondsIn: 40)),
        ])
        let positions = ConversationLayout.noticePositions(in: items)

        #expect(positions.count == 3)
        #expect(positions[EntryHash(rawValue: Data(repeating: 201, count: 32))] == .first)
        #expect(positions[EntryHash(rawValue: Data(repeating: 202, count: 32))] == .middle)
        #expect(positions[EntryHash(rawValue: Data(repeating: 203, count: 32))] == .last)

        #expect(positions[EntryHash(rawValue: Data(repeating: 201, count: 32))]?.opensARun == true)
        #expect(positions[EntryHash(rawValue: Data(repeating: 201, count: 32))]?.closesARun == false)
        #expect(positions[EntryHash(rawValue: Data(repeating: 202, count: 32))]?.opensARun == false)
        #expect(positions[EntryHash(rawValue: Data(repeating: 203, count: 32))]?.closesARun == true)
    }

    @Test("A notice on its own keeps its air on both sides")
    func aLoneNoticeIsUnchanged() {
        let items = ConversationLayout.items(from: [
            .message(message("one", from: hastur)),
            notice(1, at: 10),
            .message(message("two", from: yhtill, secondsIn: 20)),
        ])
        let position = ConversationLayout.noticePositions(in: items)[
            EntryHash(rawValue: Data(repeating: 201, count: 32))]

        #expect(position == .alone)
        #expect(position?.opensARun == true)
        #expect(position?.closesARun == true)
    }

    @Test("A transcript of nothing but notices is one run end to end")
    func allNoticesIsOneRun() {
        let items = ConversationLayout.items(from: [notice(1), notice(2, at: 10), notice(3, at: 20)])
        let positions = ConversationLayout.noticePositions(in: items)

        #expect(positions[EntryHash(rawValue: Data(repeating: 201, count: 32))] == .first)
        #expect(positions[EntryHash(rawValue: Data(repeating: 203, count: 32))] == .last)
    }

    @Test("A long enough pause starts a new run even for the same person")
    func breaksOnPause() {
        let runs = ConversationLayout.runs(from: [
            message("one", from: hastur),
            message("two", from: hastur, secondsIn: ConversationLayout.defaultGroupingWindow + 1),
        ])

        #expect(runs.count == 2)
    }

    @Test("A message exactly on the window boundary still joins the run")
    func inclusiveWindow() {
        let runs = ConversationLayout.runs(from: [
            message("one", from: hastur),
            message("two", from: hastur, secondsIn: ConversationLayout.defaultGroupingWindow),
        ])

        #expect(runs.count == 1)
    }

    @Test("My own messages never merge into someone else's run")
    func separatesBySide() {
        let me = Member(id: Identity.generate().id, displayName: "Cassilda")
        let runs = ConversationLayout.runs(from: [
            message("theirs", from: me, isMine: false),
            message("mine", from: me, isMine: true, secondsIn: 5),
        ])

        #expect(runs.count == 2)
    }

    @Test("Only the bubble that ends a run carries a tail")
    func tailPlacement() {
        let run = ConversationLayout.runs(from: [
            message("one", from: yhtill),
            message("two", from: yhtill, secondsIn: 5),
            message("three", from: yhtill, secondsIn: 10),
        ])[0]

        #expect(run.position(at: 0) == .first)
        #expect(run.position(at: 1) == .middle)
        #expect(run.position(at: 2) == .last)
        #expect([0, 1, 2].map { run.position(at: $0).hasTail } == [false, false, true])
    }

    @Test("A lone message is a whole run and keeps its tail")
    func singleMessage() {
        let run = ConversationLayout.runs(from: [message("one", from: hastur)])[0]

        #expect(run.position(at: 0) == .only)
        #expect(run.position(at: 0).hasTail)
    }

    @Test("An empty conversation lays out as nothing, not as an empty run")
    func emptyConversation() {
        #expect(ConversationLayout.runs(from: []).isEmpty)
    }
}
