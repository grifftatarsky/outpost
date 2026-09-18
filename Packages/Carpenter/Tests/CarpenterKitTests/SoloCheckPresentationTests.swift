import CarpenterUI

@testable import CarpenterKit
import Foundation
import Testing
import CarpenterKitTesting

@Suite("What a solo shows about its check")
struct SoloCheckPresentationTests {
    private let me = ParticipantID(rawValue: WideID.of([1]))
    private let them = ParticipantID(rawValue: WideID.of([2]))
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func naming(_ id: ParticipantID) -> Member {
        Member(id: id, displayName: id == me ? "Me" : "Them")
    }

    private func check(
        askedBy asker: ParticipantID? = nil, answeredBy answerer: ParticipantID? = nil,
        matched: Bool = true
    ) throws -> SoloCheck {
        var check = SoloCheck()
        guard let asker else { return check }
        let ask = EntryHash(rawValue: Data(repeating: 1, count: 32))
        check.apply(
            RenderedEntry(
                id: ask, type: .soloCheck, author: asker, device: DeviceID(rawValue: WideID.of([])),
                wallTime: start, room: RoomID(), content: .text(""), editedAt: nil,
                replyingTo: nil, reactions: [:]),
            body: try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil)))
        if let answerer {
            check.apply(
                RenderedEntry(
                    id: EntryHash(rawValue: Data(repeating: 2, count: 32)), type: .soloCheck,
                    author: answerer, device: DeviceID(rawValue: WideID.of([])),
                    wallTime: start.addingTimeInterval(10), room: RoomID(), content: .text(""),
                    editedAt: nil, replyingTo: nil, reactions: [:]),
                body: try Payload.soloCheck(
                    SoloCheckBody(move: matched ? .confirmed : .refused, answering: ask)))
        }
        return check
    }

    private func shown(
        _ check: SoloCheck, isSolo: Bool = true, requiresCheck: Bool = false,
        isHolding: Bool = false
    ) -> SoloCheckPresentation {
        SoloCheckPresentation.of(
            check, viewer: me, naming: naming, isSolo: isSolo, requiresCheck: requiresCheck,
            isHolding: isHolding)
    }

    @Test("A conversation nobody has asked about shows nothing")
    func nothing() throws {
        #expect(shown(try check()) == .nothing)
        #expect(!shown(try check()).closesTheComposer)
    }

    @Test("A question somebody else asked never closes this member's composer")
    func theirQuestionDoesNotCloseMine() throws {
        let waiting = shown(try check(askedBy: them), isHolding: false)
        #expect(waiting == .waitingOnYou(askedBy: naming(them), since: start))
        #expect(!waiting.closesTheComposer, "somebody else's question closed this member's composer")
        #expect(waiting.canAnswer)

        let alsoHolding = shown(try check(askedBy: them), isHolding: true)
        #expect(!alsoHolding.closesTheComposer)
    }

    @Test("Asking and choosing to wait closes this member's composer and nobody else's")
    func myChoiceClosesMine() throws {
        let held = shown(try check(askedBy: me), isHolding: true)
        #expect(held == .heldByYourChoice(since: start))
        #expect(held.closesTheComposer)
        #expect(!held.canAnswer)
    }

    @Test("Asking and carrying on leaves the composer open")
    func askingWithoutHolding() throws {
        let waiting = shown(try check(askedBy: me), isHolding: false)
        #expect(waiting == .waitingOnThem(since: start))
        #expect(!waiting.closesTheComposer)
    }

    @Test("The setting holds an unconfirmed conversation shut, asked or not")
    func theSettingHolds() throws {
        let never = shown(try check(), requiresCheck: true)
        #expect(never == .heldByYourSetting(askedBy: nil, since: nil))
        #expect(never.closesTheComposer)
        #expect(!never.canAnswer, "there is no question in front of them")

        let asked = shown(try check(askedBy: them), requiresCheck: true)
        #expect(asked == .heldByYourSetting(askedBy: naming(them), since: start))
        #expect(asked.closesTheComposer)
        #expect(asked.canAnswer, "the way out was taken away")
    }

    @Test("Held with nothing standing is not the same as held with your own question standing")
    func heldWithYourOwnQuestion() throws {
        let nothingStanding = shown(try check(), requiresCheck: true)
        #expect(nothingStanding == .heldByYourSetting(askedBy: nil, since: nil))

        let mine = shown(try check(askedBy: me), requiresCheck: true)
        #expect(mine == .heldByYourSetting(askedBy: nil, since: start))
        #expect(mine != nothingStanding, "the two say different things on the card")
        #expect(!mine.canAnswer, "agreeing with yourself is not a check")
    }

    @Test("A confirmed conversation is open again, setting or no setting")
    func confirmedOpensIt() throws {
        let confirmed = try check(askedBy: me, answeredBy: them)
        #expect(shown(confirmed) == .nothing)
        #expect(shown(confirmed, requiresCheck: true) == .nothing)
        #expect(!shown(confirmed, requiresCheck: true).closesTheComposer)
    }

    @Test("A refusal closes it whatever else is true")
    func refusalOutranksEverything() throws {
        let refused = try check(askedBy: me, answeredBy: them, matched: false)
        for requires in [true, false] {
            for holding in [true, false] {
                let shown = shown(refused, requiresCheck: requires, isHolding: holding)
                #expect(
                    shown
                        == .refused(
                            by: naming(them), at: start.addingTimeInterval(10), answerable: nil))
                #expect(shown.closesTheComposer)
                #expect(!shown.canAnswer, "there is no question standing behind the refusal")
            }
        }
    }

    @Test("A question asked after a refusal is the way out, and is offered")
    func aRefusalIsAnswerable() throws {
        var check = SoloCheck()
        let first = EntryHash(rawValue: Data(repeating: 1, count: 32))
        check.apply(ask(first, by: me, at: start), body: try asked())
        check.apply(
            answer(EntryHash(rawValue: Data(repeating: 2, count: 32)), by: them, at: start),
            body: try Payload.soloCheck(SoloCheckBody(move: .refused, answering: first)))

        let closed = shown(check)
        #expect(closed == .refused(by: naming(them), at: start, answerable: nil))
        #expect(!closed.canAnswer, "nobody has asked since, so there is nothing to answer")

        let second = EntryHash(rawValue: Data(repeating: 3, count: 32))
        check.apply(ask(second, by: them, at: start.addingTimeInterval(60)), body: try asked())

        let reopened = shown(check)
        #expect(
            reopened == .refused(by: naming(them), at: start, answerable: naming(them)),
            "the way out the fold describes is not on the screen")
        #expect(reopened.canAnswer)
        #expect(reopened.closesTheComposer, "answering it is the way out, not carrying on")
    }

    @Test("A question you asked yourself after a refusal is not answerable by you")
    func yourOwnQuestionIsNotTheWayOut() throws {
        var check = SoloCheck()
        let first = EntryHash(rawValue: Data(repeating: 1, count: 32))
        check.apply(ask(first, by: me, at: start), body: try asked())
        check.apply(
            answer(EntryHash(rawValue: Data(repeating: 2, count: 32)), by: them, at: start),
            body: try Payload.soloCheck(SoloCheckBody(move: .refused, answering: first)))
        check.apply(
            ask(EntryHash(rawValue: Data(repeating: 3, count: 32)), by: me, at: start.addingTimeInterval(60)),
            body: try asked())

        let shown = shown(check)
        #expect(shown == .refused(by: naming(them), at: start, answerable: nil))
        #expect(!shown.canAnswer)
    }

    private func asked() throws -> Payload {
        try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil))
    }

    private func ask(_ id: EntryHash, by author: ParticipantID, at: Date) -> RenderedEntry {
        RenderedEntry(
            id: id, type: .soloCheck, author: author, device: DeviceID(rawValue: WideID.of([])),
            wallTime: at, room: RoomID(), content: .text(""), editedAt: nil, replyingTo: nil,
            reactions: [:])
    }

    private func answer(_ id: EntryHash, by author: ParticipantID, at: Date) -> RenderedEntry {
        ask(id, by: author, at: at)
    }

    @Test("Whether the asker held is invisible on the other side")
    func theHoldIsInvisibleToThem() throws {
        let asked = try check(askedBy: them)
        let theirs = { (holding: Bool) in
            SoloCheckPresentation.of(
                asked, viewer: self.me, naming: self.naming, isSolo: true, requiresCheck: false,
                isHolding: holding)
        }
        #expect(
            theirs(true) == theirs(false),
            "the other person's screen can tell whether the asker held, which is one line from letting it freeze them")
    }

    @Test("A room is never held by the solo setting, whatever has been folded")
    func aRoomIsNeverHeld() throws {
        let asked = try check(askedBy: them)
        let refused = try check(askedBy: me, answeredBy: them, matched: false)
        let confirmed = try check(askedBy: me, answeredBy: them, matched: true)

        for folded in [try check(), asked, refused, confirmed] {
            for requires in [true, false] {
                for holding in [true, false] {
                    let inARoom = shown(
                        folded, isSolo: false, requiresCheck: requires, isHolding: holding)
                    #expect(
                        inARoom == .nothing,
                        "a room drew \(inARoom), and a room has no six characters to check")
                    #expect(!inARoom.closesTheComposer)
                }
            }
        }
    }

    @Test("A solo is still held by the setting")
    func aSoloIsStillHeld() throws {
        #expect(shown(try check(), isSolo: true, requiresCheck: true).closesTheComposer)
    }
}
