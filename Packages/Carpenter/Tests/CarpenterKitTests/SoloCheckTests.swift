import Foundation
import Testing
import CarpenterKitTesting

@testable import CarpenterKit

@Suite("Checking who you are talking to")
struct SoloCheckTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let room = ConversationID.room(UUID())

    private func rendered(
        _ author: ParticipantID, _ type: PayloadType, hash: UInt8, at offset: TimeInterval
    ) -> RenderedEntry {
        RenderedEntry(
            id: EntryHash(rawValue: Data(repeating: hash, count: 32)), type: type, author: author,
            device: DeviceID(rawValue: WideID.of([])), wallTime: start.addingTimeInterval(offset),
            conversation: room, content: .text(""), editedAt: nil, replyingTo: nil, reactions: [:])
    }

    private func hash(_ byte: UInt8) -> EntryHash {
        EntryHash(rawValue: Data(repeating: byte, count: 32))
    }

    @Test("It is classified, exactly once, as plumbing")
    func classified() {
        #expect(PayloadType.allKnown.contains(.soloCheck))
        #expect(PayloadType.plumbing.contains(.soloCheck))
        #expect(PayloadType.soloCheck.rawValue == 23)
    }

    @Test("It carries fallback text")
    func carriesFallbackText() throws {
        for move in SoloCheckBody.Move.allCases {
            let payload = try Payload.soloCheck(SoloCheckBody(move: move, answering: hash(1)))
            let fallback = try #require(payload.fallbackText, "\(move)")
            #expect(!fallback.isEmpty, "\(move)")
        }
    }

    @Test("Nobody has asked, so there is nothing to say")
    func nothingAsked() {
        #expect(SoloCheck().state == .notChecked)
    }

    @Test("Asking leaves it outstanding, and says who asked")
    func askingIsOutstanding() throws {
        let asker = ParticipantID(rawValue: WideID.of([1]))
        var check = SoloCheck()
        check.apply(
            rendered(asker, .soloCheck, hash: 1, at: 10),
            body: try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil)))

        #expect(check.state == .outstanding(askedBy: asker, at: start.addingTimeInterval(10)))
    }

    @Test("The other person confirming settles it")
    func confirmingSettlesIt() throws {
        let asker = ParticipantID(rawValue: WideID.of([1]))
        let them = ParticipantID(rawValue: WideID.of([2]))
        var check = SoloCheck()
        check.apply(
            rendered(asker, .soloCheck, hash: 1, at: 10),
            body: try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil)))
        check.apply(
            rendered(them, .soloCheck, hash: 2, at: 20),
            body: try Payload.soloCheck(SoloCheckBody(move: .confirmed, answering: hash(1))))

        #expect(check.state == .confirmed(at: start.addingTimeInterval(20)))
    }

    @Test("Answering your own ask settles nothing")
    func answeringYourselfSettlesNothing() throws {
        let asker = ParticipantID(rawValue: WideID.of([1]))
        var check = SoloCheck()
        check.apply(
            rendered(asker, .soloCheck, hash: 1, at: 10),
            body: try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil)))
        check.apply(
            rendered(asker, .soloCheck, hash: 2, at: 20),
            body: try Payload.soloCheck(SoloCheckBody(move: .confirmed, answering: hash(1))))

        #expect(check.state == .outstanding(askedBy: asker, at: start.addingTimeInterval(10)))
    }

    @Test("Either side refusing blocks it")
    func eitherSideCanRefuse() throws {
        let asker = ParticipantID(rawValue: WideID.of([1]))
        let them = ParticipantID(rawValue: WideID.of([2]))

        for refuser in [asker, them] {
            var check = SoloCheck()
            check.apply(
                rendered(asker, .soloCheck, hash: 1, at: 10),
                body: try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil)))
            check.apply(
                rendered(refuser, .soloCheck, hash: 2, at: 20),
                body: try Payload.soloCheck(SoloCheckBody(move: .refused, answering: hash(1))))

            #expect(check.state == .refused(by: refuser, at: start.addingTimeInterval(20)))
        }
    }

    @Test("Asking again does not clear a refusal on its own")
    func askingAgainDoesNotUnblock() throws {
        let asker = ParticipantID(rawValue: WideID.of([1]))
        let them = ParticipantID(rawValue: WideID.of([2]))
        var check = SoloCheck()
        check.apply(
            rendered(asker, .soloCheck, hash: 1, at: 10),
            body: try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil)))
        check.apply(
            rendered(them, .soloCheck, hash: 2, at: 20),
            body: try Payload.soloCheck(SoloCheckBody(move: .refused, answering: hash(1))))
        check.apply(
            rendered(asker, .soloCheck, hash: 3, at: 30),
            body: try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil)))

        #expect(check.state == .refused(by: them, at: start.addingTimeInterval(20)))
    }

    @Test("Checking again, and confirming, clears a refusal")
    func checkingAgainClearsIt() throws {
        let asker = ParticipantID(rawValue: WideID.of([1]))
        let them = ParticipantID(rawValue: WideID.of([2]))
        var check = SoloCheck()
        check.apply(
            rendered(asker, .soloCheck, hash: 1, at: 10),
            body: try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil)))
        check.apply(
            rendered(them, .soloCheck, hash: 2, at: 20),
            body: try Payload.soloCheck(SoloCheckBody(move: .refused, answering: hash(1))))
        check.apply(
            rendered(asker, .soloCheck, hash: 3, at: 30),
            body: try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil)))
        check.apply(
            rendered(them, .soloCheck, hash: 4, at: 40),
            body: try Payload.soloCheck(SoloCheckBody(move: .confirmed, answering: hash(3))))

        #expect(check.state == .confirmed(at: start.addingTimeInterval(40)))
    }

    @Test("An answer to an ask nobody made folds to nothing")
    func anAnswerToNothing() throws {
        let them = ParticipantID(rawValue: WideID.of([2]))
        var check = SoloCheck()
        check.apply(
            rendered(them, .soloCheck, hash: 2, at: 20),
            body: try Payload.soloCheck(SoloCheckBody(move: .confirmed, answering: hash(9))))

        #expect(check.state == .notChecked)
    }

    @Test("Two asks in flight both have to be answered")
    func twoAsksAtOnce() throws {
        let a = ParticipantID(rawValue: WideID.of([1]))
        let b = ParticipantID(rawValue: WideID.of([2]))
        var check = SoloCheck()
        check.apply(
            rendered(a, .soloCheck, hash: 1, at: 10),
            body: try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil)))
        check.apply(
            rendered(b, .soloCheck, hash: 2, at: 11),
            body: try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil)))
        check.apply(
            rendered(b, .soloCheck, hash: 3, at: 20),
            body: try Payload.soloCheck(SoloCheckBody(move: .confirmed, answering: hash(1))))

        #expect(check.state == .outstanding(askedBy: b, at: start.addingTimeInterval(11)))

        check.apply(
            rendered(a, .soloCheck, hash: 4, at: 21),
            body: try Payload.soloCheck(SoloCheckBody(move: .confirmed, answering: hash(2))))
        #expect(check.state == .confirmed(at: start.addingTimeInterval(21)))
    }

    @Test("A confirmation of another ask does not undo a refusal")
    func aConcurrentConfirmationDoesNotUndoARefusal() throws {
        let a = ParticipantID(rawValue: WideID.of([1]))
        let b = ParticipantID(rawValue: WideID.of([2]))
        var check = SoloCheck()
        check.apply(
            rendered(a, .soloCheck, hash: 1, at: 10),
            body: try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil)))
        check.apply(
            rendered(b, .soloCheck, hash: 2, at: 11),
            body: try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil)))
        check.apply(
            rendered(b, .soloCheck, hash: 3, at: 20),
            body: try Payload.soloCheck(SoloCheckBody(move: .refused, answering: hash(1))))
        check.apply(
            rendered(a, .soloCheck, hash: 4, at: 30),
            body: try Payload.soloCheck(SoloCheckBody(move: .confirmed, answering: hash(2))))

        #expect(
            check.state == .refused(by: b, at: start.addingTimeInterval(20)),
            "a refusal was undone by an answer to a different question")
    }

    @Test("A confirmation of an ask raised after the refusal does clear it")
    func askingAfterwardsClearsIt() throws {
        let a = ParticipantID(rawValue: WideID.of([1]))
        let b = ParticipantID(rawValue: WideID.of([2]))
        var check = SoloCheck()
        check.apply(
            rendered(a, .soloCheck, hash: 1, at: 10),
            body: try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil)))
        check.apply(
            rendered(b, .soloCheck, hash: 2, at: 20),
            body: try Payload.soloCheck(SoloCheckBody(move: .refused, answering: hash(1))))
        check.apply(
            rendered(a, .soloCheck, hash: 3, at: 30),
            body: try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil)))
        check.apply(
            rendered(b, .soloCheck, hash: 4, at: 40),
            body: try Payload.soloCheck(SoloCheckBody(move: .confirmed, answering: hash(3))))

        #expect(check.state == .confirmed(at: start.addingTimeInterval(40)))
    }

    @Test("A refusal survives a confirmation of the same ask, either way round")
    func aRefusalIsNeverLost() throws {
        let a = ParticipantID(rawValue: WideID.of([1]))
        let b = ParticipantID(rawValue: WideID.of([2]))
        let ask = (rendered(a, .soloCheck, hash: 1, at: 10),
                   try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil)))
        let yes = (rendered(b, .soloCheck, hash: 2, at: 20),
                   try Payload.soloCheck(SoloCheckBody(move: .confirmed, answering: hash(1))))
        let no = (rendered(a, .soloCheck, hash: 3, at: 21),
                  try Payload.soloCheck(SoloCheckBody(move: .refused, answering: hash(1))))

        var yesFirst = SoloCheck()
        for move in [ask, yes, no] { yesFirst.apply(move.0, body: move.1) }
        #expect(yesFirst.isBlocked, "a refusal was lost behind a confirmation of the same question")

        var noFirst = SoloCheck()
        for move in [ask, no, yes] { noFirst.apply(move.0, body: move.1) }
        #expect(noFirst.isBlocked, "a confirmation undid a refusal of the same question")
    }

    @Test("A refusal survives even when both answers arrive before the question")
    func aRefusalSurvivesArrivingEarly() throws {
        let a = ParticipantID(rawValue: WideID.of([1]))
        let b = ParticipantID(rawValue: WideID.of([2]))
        let ask = (rendered(a, .soloCheck, hash: 1, at: 10),
                   try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil)))
        let yes = (rendered(b, .soloCheck, hash: 2, at: 20),
                   try Payload.soloCheck(SoloCheckBody(move: .confirmed, answering: hash(1))))
        let no = (rendered(a, .soloCheck, hash: 3, at: 21),
                  try Payload.soloCheck(SoloCheckBody(move: .refused, answering: hash(1))))

        for order in [[yes, no, ask], [no, yes, ask]] {
            var check = SoloCheck()
            for move in order { check.apply(move.0, body: move.1) }
            #expect(check.isBlocked, "a refusal was dropped for arriving before its question")
        }
    }

    @Test("The order the entries arrive in does not change the verdict")
    func orderDoesNotMatter() throws {
        let a = ParticipantID(rawValue: WideID.of([1]))
        let b = ParticipantID(rawValue: WideID.of([2]))
        let ask = (rendered(a, .soloCheck, hash: 1, at: 10),
                   try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil)))
        let answer = (rendered(b, .soloCheck, hash: 2, at: 20),
                      try Payload.soloCheck(SoloCheckBody(move: .confirmed, answering: hash(1))))

        var forwards = SoloCheck()
        forwards.apply(ask.0, body: ask.1)
        forwards.apply(answer.0, body: answer.1)

        var backwards = SoloCheck()
        backwards.apply(answer.0, body: answer.1)
        backwards.apply(ask.0, body: ask.1)

        #expect(forwards.state == backwards.state)
        #expect(backwards.state == .confirmed(at: start.addingTimeInterval(20)))
    }
}
