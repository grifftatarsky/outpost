import Foundation
import Testing

@testable import CarpenterKit

@Suite("What a seal is bound to")
struct SealBindingTests {
    private func feed(_ byte: UInt8) -> FeedKey {
        FeedKey(
            author: ParticipantID(rawValue: Data([byte, byte, byte])),
            device: DeviceID(rawValue: Data([byte, 0x0F])))
    }

    @Test("One member cannot re-sign another's sealed words as their own")
    func aCiphertextCannotBeLifted() throws {
        let (chain, _) = EpochChain.create(room: ConversationID.room(UUID()))
        let carol = feed(0xC0)
        let dave = feed(0xDA)

        let sealed = try Payload.post("a thing only Carol said").sealed(
            at: .initial, using: chain, by: carol)

        let hers = try sealed.opened(using: chain, by: carol)
        #expect((try? hers.decode(PostBody.self))?.text == "a thing only Carol said")

        #expect(
            (try? sealed.opened(using: chain, by: dave)) == nil,
            "Dave opened Carol's ciphertext as though he had written it")
    }

    @Test("A seal does not travel between rooms or epochs")
    func aCiphertextCannotBeMoved() throws {
        let (here, _) = EpochChain.create(room: ConversationID.room(UUID()))
        let (elsewhere, _) = EpochChain.create(room: ConversationID.room(UUID()))
        let carol = feed(0xC0)
        let sealed = try Payload.post("here").sealed(at: .initial, using: here, by: carol)

        #expect((try? sealed.opened(using: elsewhere, by: carol)) == nil)
    }

    @Test("A payload sealed before the binding still opens")
    func oldSealsStillOpen() throws {
        let (chain, _) = EpochChain.create(room: ConversationID.room(UUID()))
        let unbound = try Payload.post("written last year").sealed(
            at: .initial, using: chain, by: nil)

        let opened = try unbound.opened(using: chain, by: feed(0xC0))
        #expect((try? opened.decode(PostBody.self))?.text == "written last year")
    }

    @Test("With nothing new to say, the bytes are the old bytes")
    func theAbsentFieldsAreAbsentBytes() {
        let room = ConversationID.room(UUID())
        let epoch = EpochNumber.initial

        let contextAsItAlwaysWas = CanonicalBytes.payload(
            domain: Domain.sealedPayload, fields: [room.canonicalBytes, epoch.canonicalBytes])
        #expect(
            SealedPayload.context(room: room, epoch: epoch, by: nil) == contextAsItAlwaysWas,
            "a payload sealed before the writer binding can no longer be opened")

        let sealed = SealedPayload(epoch: epoch, ciphertext: Data([0xAB, 0xCD]))
        let bytesAsTheyAlwaysWere = CanonicalBytes.payload(
            domain: Domain.sealedPayload, fields: [epoch.canonicalBytes, Data([0xAB, 0xCD])])
        #expect(
            sealed.canonicalBytes == bytesAsTheyAlwaysWere,
            "every signature over an entry written before the second reader stopped matching")
    }

    @Test("With something new to say, the bytes differ")
    func thePresentFieldsChangeTheBytes() {
        let room = ConversationID.room(UUID())
        #expect(
            SealedPayload.context(room: room, epoch: .initial, by: feed(0xC0))
                != SealedPayload.context(room: room, epoch: .initial, by: nil))
        #expect(
            SealedPayload(epoch: .initial, ciphertext: Data([1]), alsoFor: Data([2])).canonicalBytes
                != SealedPayload(epoch: .initial, ciphertext: Data([1])).canonicalBytes)
    }

    @Test("The second copy opens for its one reader and nobody else")
    func theSecondCopyIsForOnePerson() throws {
        let (chain, _) = EpochChain.create(room: ConversationID.room(UUID()))
        let carol = feed(0xC0)
        let theirs = PairwiseSecret(material: Data(repeating: 0x11, count: 32))
        let somebodyElse = PairwiseSecret(material: Data(repeating: 0x22, count: 32))

        let sealed = try Payload.comment(on: EntryHash(rawValue: Data([1])), text: "for you")
            .sealed(at: .initial, using: chain, by: carol, alsoFor: theirs)

        let opened = try sealed.opened(pairwise: theirs, room: chain.room, by: carol)
        #expect((try? opened.decode(CommentBody.self))?.text == "for you")

        #expect((try? sealed.opened(pairwise: somebodyElse, room: chain.room, by: carol)) == nil)
        #expect((try? sealed.opened(pairwise: theirs, room: chain.room, by: feed(0xDA))) == nil)
    }

    @Test("An entry with no second copy has none to open")
    func noSecondCopyByDefault() throws {
        let (chain, _) = EpochChain.create(room: ConversationID.room(UUID()))
        let sealed = try Payload.post("ordinary").sealed(at: .initial, using: chain, by: feed(0xC0))
        #expect(sealed.alsoFor == nil)
    }
}
