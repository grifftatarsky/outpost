import Foundation
import Testing

@testable import CarpenterKit

@Suite("Pairwise secrets")
struct PairwiseTests {
    @Test("Both members derive the same secret without exchanging it")
    func symmetric() throws {
        let cassilda = Identity.generate()
        let hastur = Identity.generate()

        let hers = try PairwiseSecret.derive(mine: cassilda, theirs: hastur.publicKeys)
        let his = try PairwiseSecret.derive(mine: hastur, theirs: cassilda.publicKeys)

        #expect(hers == his)
        #expect(hers.material.count == 32)
    }

    @Test("A different pair derives a different secret")
    func distinctPerPair() throws {
        let cassilda = Identity.generate()
        let hastur = Identity.generate()
        let camilla = Identity.generate()

        #expect(
            try PairwiseSecret.derive(mine: cassilda, theirs: hastur.publicKeys)
                != PairwiseSecret.derive(mine: cassilda, theirs: camilla.publicKeys))
    }

    @Test("Recipient tags rotate, and both sides agree on each window")
    func rotatingTags() throws {
        let cassilda = Identity.generate()
        let hastur = Identity.generate()
        let hers = try PairwiseSecret.derive(mine: cassilda, theirs: hastur.publicKeys)
        let his = try PairwiseSecret.derive(mine: hastur, theirs: cassilda.publicKeys)

        #expect(
            hers.recipientTag(window: 7, for: hastur.id)
                == his.recipientTag(window: 7, for: hastur.id))
        #expect(
            hers.recipientTag(window: 7, for: hastur.id)
                != hers.recipientTag(window: 8, for: hastur.id))

        #expect(
            hers.recipientTag(window: 7, for: hastur.id)
                != hers.recipientTag(window: 7, for: cassilda.id))

        #expect(hers.recipientTag(window: 7, for: hastur.id).rawValue.count == 32)
    }

    @Test("A tag reveals nothing about who the pair are")
    func tagsAreNotDerivableFromPublicData() throws {
        let cassilda = Identity.generate()
        let hastur = Identity.generate()
        let outsider = Identity.generate()

        let real = try PairwiseSecret.derive(mine: cassilda, theirs: hastur.publicKeys)
        let guess = try PairwiseSecret.derive(mine: outsider, theirs: hastur.publicKeys)

        #expect(
            real.recipientTag(window: 1, for: hastur.id)
                != guess.recipientTag(window: 1, for: hastur.id))
    }

    @Test("A value wrapped to a pair opens for that pair and nobody else")
    func wrapping() throws {
        let cassilda = Identity.generate()
        let hastur = Identity.generate()
        let outsider = Identity.generate()

        let hers = try PairwiseSecret.derive(mine: cassilda, theirs: hastur.publicKeys)
        let his = try PairwiseSecret.derive(mine: hastur, theirs: cassilda.publicKeys)
        let theirs = try PairwiseSecret.derive(mine: outsider, theirs: hastur.publicKeys)

        let context = Data("epoch 4".utf8)
        let wrapped = try hers.wrap(Data("the secret".utf8), context: context)

        #expect(try his.unwrap(wrapped, context: context) == Data("the secret".utf8))
        #expect(throws: CryptoError.openFailed) { try theirs.unwrap(wrapped, context: context) }
    }

    @Test("A wrapped value does not open under a different context")
    func contextIsBound() throws {
        let cassilda = Identity.generate()
        let hastur = Identity.generate()
        let hers = try PairwiseSecret.derive(mine: cassilda, theirs: hastur.publicKeys)

        let wrapped = try hers.wrap(Data("the secret".utf8), context: Data("epoch 4".utf8))

        #expect(throws: CryptoError.openFailed) {
            try hers.unwrap(wrapped, context: Data("epoch 5".utf8))
        }
    }
}

@Suite("Epoch chain")
struct EpochChainTests {
    private let room = ConversationID.room(UUID())

    private func history(through epochs: Int) throws
        -> (secrets: [EpochNumber: EpochSecret], links: [EpochLink])
    {
        let (_, first) = EpochChain.create(room: room)
        var secrets: [EpochNumber: EpochSecret] = [.initial: first]
        var links: [EpochLink] = []
        var current = first
        var number = EpochNumber.initial

        for _ in 0..<epochs {
            let advanced = try EpochChain.advance(from: current, at: number, room: room)
            number = number.next
            current = advanced.secret
            secrets[number] = advanced.secret
            links.append(advanced.link)
        }

        return (secrets, links)
    }

    // MARK: The exit criterion

    @Test("A joiner at an epoch derives every earlier epoch", arguments: 0...5)
    func joinerDerivesHistory(joinAt: Int) throws {
        let (secrets, links) = try history(through: 5)
        let joinEpoch = EpochNumber(rawValue: UInt64(joinAt))

        var joiner = EpochChain(room: room)
        joiner.adopt(secrets[joinEpoch]!, at: joinEpoch)
        try joiner.record(links)

        for earlier in 0...joinAt {
            let epoch = EpochNumber(rawValue: UInt64(earlier))
            #expect(
                try joiner.secret(for: epoch) == secrets[epoch],
                "should have derived epoch \(earlier) from epoch \(joinAt)")
        }
    }

    @Test("A joiner derives nothing from a later epoch", arguments: 0...4)
    func joinerCannotReachTheFuture(joinAt: Int) throws {
        let (secrets, links) = try history(through: 5)
        let joinEpoch = EpochNumber(rawValue: UInt64(joinAt))

        var joiner = EpochChain(room: room)
        joiner.adopt(secrets[joinEpoch]!, at: joinEpoch)
        try joiner.record(links)

        for later in (joinAt + 1)...5 {
            #expect(throws: CryptoError.unknownEpoch) {
                try joiner.secret(for: EpochNumber(rawValue: UInt64(later)))
            }
        }
    }

    @Test("A removed member cannot read the epoch that begins after they leave")
    func removalIsEnforced() throws {
        let (chain, first) = EpochChain.create(room: room)

        var removed = chain
        removed.adopt(first, at: .initial)

        let advanced = try EpochChain.advance(from: first, at: .initial, room: room)
        try removed.record(advanced.link)

        #expect(throws: CryptoError.unknownEpoch) { try removed.secret(for: .initial.next) }
        #expect(try removed.secret(for: .initial) == first)
    }

    @Test("Holding every link but no secret yields nothing at all")
    func linksAloneAreUseless() throws {
        let (_, links) = try history(through: 4)

        var outsider = EpochChain(room: room)
        try outsider.record(links)

        for epoch in 0...4 {
            #expect(throws: CryptoError.unknownEpoch) {
                try outsider.secret(for: EpochNumber(rawValue: UInt64(epoch)))
            }
        }
    }

    // MARK: Mechanics

    @Test("Every advance produces a fresh secret")
    func secretsAreFresh() throws {
        let (secrets, _) = try history(through: 6)
        #expect(Set(secrets.values.map(\.material)).count == secrets.count)
    }

    @Test("A link from another room is refused rather than stored")
    func linksAreRoomBound() throws {
        let (_, first) = EpochChain.create(room: room)
        let advanced = try EpochChain.advance(from: first, at: .initial, room: ConversationID.room(UUID()))

        var chain = EpochChain(room: room)
        #expect(throws: CryptoError.wrongRoom) { try chain.record(advanced.link) }
    }

    @Test("A missing link breaks the walk rather than silently skipping an epoch")
    func gapsInTheChainAreFatal() throws {
        let (secrets, links) = try history(through: 4)

        var chain = EpochChain(room: room)
        chain.adopt(secrets[EpochNumber(rawValue: 4)]!, at: EpochNumber(rawValue: 4))
        try chain.record(links.filter { $0.epoch != EpochNumber(rawValue: 3) })

        #expect(try chain.secret(for: EpochNumber(rawValue: 3)) == secrets[EpochNumber(rawValue: 3)])
        #expect(throws: CryptoError.unknownEpoch) {
            try chain.secret(for: EpochNumber(rawValue: 1))
        }
    }

    @Test("Warming the cache does not change what can be derived")
    func warming() throws {
        let (secrets, links) = try history(through: 5)
        let top = EpochNumber(rawValue: 5)

        var chain = EpochChain(room: room)
        chain.adopt(secrets[top]!, at: top)
        try chain.record(links)
        try chain.warm(downTo: .initial)

        #expect(chain.knownEpochs.count == 6)
        for epoch in 0...5 {
            let number = EpochNumber(rawValue: UInt64(epoch))
            #expect(try chain.secret(for: number) == secrets[number])
        }
    }

    @Test("Sealing keys differ per epoch, and differ from the wrapping keys")
    func keysAreSeparated() throws {
        let (secrets, links) = try history(through: 2)
        var chain = EpochChain(room: room)
        chain.adopt(secrets[EpochNumber(rawValue: 2)]!, at: EpochNumber(rawValue: 2))
        try chain.record(links)

        let zero = try chain.sealingKey(for: .initial).withUnsafeBytes { Data($0) }
        let one = try chain.sealingKey(for: EpochNumber(rawValue: 1)).withUnsafeBytes { Data($0) }

        #expect(zero != one)
        #expect(zero != secrets[.initial]!.material)
    }
}

@Suite("Sealed payloads")
struct SealedPayloadTests {
    private let room = ConversationID.room(UUID())

    private func chainAt(_ epoch: Int) throws -> (EpochChain, [EpochLink]) {
        let (_, first) = EpochChain.create(room: room)
        var chain = EpochChain(room: room)
        chain.adopt(first, at: .initial)
        var links: [EpochLink] = []
        var current = first
        var number = EpochNumber.initial

        for _ in 0..<epoch {
            let advanced = try EpochChain.advance(from: current, at: number, room: room)
            number = number.next
            current = advanced.secret
            links.append(advanced.link)
            chain.adopt(advanced.secret, at: number)
        }
        try chain.record(links)
        return (chain, links)
    }

    @Test("A payload seals and opens under the same epoch")
    func roundTrip() throws {
        let (chain, _) = try chainAt(0)
        let payload = try Payload.post("hydrogen, obviously")

        let sealed = try payload.sealed(at: .initial, using: chain)
        #expect(try sealed.opened(using: chain) == payload)
    }

    @Test("Nothing about the payload is readable without the key")
    func ciphertextRevealsNothing() throws {
        let (chain, _) = try chainAt(0)
        let payload = Payload(
            type: PayloadType(rawValue: 4_242), version: 3,
            body: Data("the mooring mast drawings".utf8),
            fallbackText: "Cassilda posted a poll")

        let sealed = try payload.sealed(at: .initial, using: chain)

        #expect(!sealed.ciphertext.contains(Data("mooring".utf8)))
        #expect(!sealed.ciphertext.contains(Data("Cassilda".utf8)))
        #expect(sealed.epoch == .initial)
    }

    @Test("A ciphertext lifted into another room does not open")
    func roomIsBound() throws {
        let (chain, _) = try chainAt(0)
        let sealed = try Payload.post("private").sealed(at: .initial, using: chain)

        var elsewhere = EpochChain(room: ConversationID.room(UUID()))
        elsewhere.adopt(try chain.secret(for: .initial), at: .initial)

        #expect(throws: CryptoError.openFailed) { try sealed.opened(using: elsewhere) }
    }

    @Test("A ciphertext relabelled with another epoch does not open")
    func epochIsBound() throws {
        let (chain, _) = try chainAt(2)
        let sealed = try Payload.post("private").sealed(at: .initial, using: chain)
        let relabelled = SealedPayload(
            epoch: EpochNumber(rawValue: 1), ciphertext: sealed.ciphertext)

        #expect(throws: CryptoError.openFailed) { try relabelled.opened(using: chain) }
    }

    @Test("A tampered ciphertext does not open")
    func tamperIsDetected() throws {
        let (chain, _) = try chainAt(0)
        var bytes = try Payload.post("private").sealed(at: .initial, using: chain).ciphertext
        bytes[bytes.count / 2] ^= 0xFF

        #expect(throws: CryptoError.openFailed) {
            try SealedPayload(epoch: .initial, ciphertext: bytes).opened(using: chain)
        }
    }

    @Test("A joiner opens old messages; a removed member cannot open new ones")
    func historyAndRemovalTogether() throws {
        let (_, first) = EpochChain.create(room: room)

        var founder = EpochChain(room: room)
        founder.adopt(first, at: .initial)
        let old = try Payload.post("said in epoch zero").sealed(at: .initial, using: founder)

        let advanced = try EpochChain.advance(from: first, at: .initial, room: room)
        var current = EpochChain(room: room)
        current.adopt(advanced.secret, at: .initial.next)
        try current.record(advanced.link)
        let new = try Payload.post("said in epoch one").sealed(
            at: .initial.next, using: current)

        var joiner = EpochChain(room: room)
        joiner.adopt(advanced.secret, at: .initial.next)
        try joiner.record(advanced.link)
        #expect(try joiner.opened(old) == "said in epoch zero")
        #expect(try joiner.opened(new) == "said in epoch one")

        var removed = EpochChain(room: room)
        removed.adopt(first, at: .initial)
        try removed.record(advanced.link)
        #expect(try removed.opened(old) == "said in epoch zero")
        #expect(throws: CryptoError.unknownEpoch) { try removed.opened(new) }
    }
}

extension EpochChain {
    fileprivate func opened(_ sealed: SealedPayload) throws -> String {
        let payload = try sealed.opened(using: self)
        return try payload.decode(PostBody.self).text
    }
}
