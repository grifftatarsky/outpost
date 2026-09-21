import CryptoKit
import Foundation
import Testing

@testable import CarpenterKit

@Suite("What a seal is bound to")
struct SealBindingTests {
    private func feed(_ byte: UInt8) -> FeedKey {
        FeedKey(
            author: ParticipantID(rawValue: Data([byte, byte, byte])),
            device: DeviceID(rawValue: Data([byte, 0x0F])),
            conversation: ConversationID.room(UUID(uuidString: "00000000-0000-4000-8000-00000000C0DE")!))
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

    @Test("A payload not bound to its writer does not open, for anybody")
    func anUnboundSealIsRefused() throws {
        let (chain, _) = EpochChain.create(room: ConversationID.room(UUID()))
        let unboundContext = CanonicalBytes.payload(
            domain: Domain.sealedPayload,
            fields: [chain.room.canonicalBytes, EpochNumber.initial.canonicalBytes])
        let box = try ChaChaPoly.seal(
            try Payload.post("with nobody's name on it").plaintext(),
            using: try chain.sealingKey(for: .initial), authenticating: unboundContext)
        let unbound = SealedPayload(epoch: .initial, ciphertext: box.combined)

        for writer in [feed(0xC0), feed(0xDA)] {
            #expect(
                (try? unbound.opened(using: chain, by: writer)) == nil,
                "a seal with no writer in it opened as though somebody had written it")
        }
    }

    @Test("The bytes a seal is bound to are pinned: room, epoch and writer, in that order")
    func theContextIsPinned() {
        let room = ConversationID.room(UUID())
        let epoch = EpochNumber.initial
        let carol = feed(0xC0)

        let byHand = CanonicalBytes.payload(
            domain: Domain.sealedPayload,
            fields: [room.canonicalBytes, epoch.canonicalBytes, carol.canonicalBytes])
        #expect(SealedPayload.context(room: room, epoch: epoch, by: carol) == byHand)

        let sealed = SealedPayload(epoch: epoch, ciphertext: Data([0xAB, 0xCD]))
        let bytesAsTheyAlwaysWere = CanonicalBytes.payload(
            domain: Domain.sealedPayload, fields: [epoch.canonicalBytes, Data([0xAB, 0xCD])])
        #expect(
            sealed.canonicalBytes == bytesAsTheyAlwaysWere,
            "a payload with no second reader gained bytes it does not have")
    }

    @Test("A different writer, or a second reader, changes the bytes")
    func thePresentFieldsChangeTheBytes() {
        let room = ConversationID.room(UUID())
        #expect(
            SealedPayload.context(room: room, epoch: .initial, by: feed(0xC0))
                != SealedPayload.context(room: room, epoch: .initial, by: feed(0xDA)))
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
