import CarpenterKit
import Foundation

public struct MailboxContractBreach: Error, CustomStringConvertible, Sendable {
    public let rule: MailboxContract.Rule
    public let saw: String

    public init(_ rule: MailboxContract.Rule, _ saw: String) {
        self.rule = rule
        self.saw = saw
    }

    public var description: String { "\(rule.rawValue) broken (\(rule.promise)): \(saw)" }
}

public enum MailboxContract {
    public typealias AfterWrite = @Sendable () async throws -> Void

    public enum Rule: String, CaseIterable, Sendable {
        case c1 = "C1"
        case c2 = "C2"
        case c3 = "C3"
        case c4 = "C4"
        case c5 = "C5"
        case c6 = "C6"
        case c7 = "C7"
        case c8 = "C8"
        case c9 = "C9"
        case c10 = "C10"
        case c11 = "C11"

        public var promise: String {
            switch self {
            case .c1: "a packet put is listed by sentPackets with the same recipients and digest"
            case .c2: "a packet over the record ceiling is refused before anything is stored; one at the budget goes"
            case .c3: "withdraw takes a packet out of sentPackets"
            case .c4: "a person's space is the same link every time; a code's is new each time; claim makes it theirs"
            case .c5: "a photo is one copy per person, says who it is for, and a rewrite keeps its first-stored time"
            case .c6: "join waits until the reader is named, then joins; one's own or a wrong-account link is gone"
            case .c7: "a packet arrives with the bytes it was put with, from its writer, dated when it was last stored"
            case .c8: "packets arrive in the order they were first stored"
            case .c9: "a receipt is listed for the writer with when it was stored, and rides the reader's next fetch"
            case .c10: "a ring is never returned by fetch"
            case .c11: "after stopSharing, leave or close, reads is false and fetch returns nothing"
            }
        }
    }

    // MARK: Own space, one account

    public static func aPutPacketIsListed(in mailbox: any Mailbox, afterWrite: AfterWrite) async throws {
        let toThem = try someone(for: Identity.generate())
        let pairs = Pairs.of(toThem)
        let packet = freshPacket(to: toThem)
        try await mailbox.put(packet, to: toThem.them, in: pairs)
        try await afterWrite()

        guard let listed = try await mailbox.sentPackets(in: pairs)[packet.id] else {
            throw MailboxContractBreach(.c1, "the packet put was not listed at all")
        }
        guard listed.to == toThem.them else {
            throw MailboxContractBreach(.c1, "the packet was listed as being for somebody else")
        }
        guard listed.recipients == packet.recipients else {
            throw MailboxContractBreach(.c1, "listed with \(listed.recipients.count) recipient(s), put with 1")
        }
        guard listed.contentDigest == packet.contentDigest else {
            throw MailboxContractBreach(.c1, "the listed packet's digest is not the digest of what was put")
        }
    }

    public static func theRecordCeilingHolds(in mailbox: any Mailbox, afterWrite: AfterWrite) async throws {
        let toThem = try someone(for: Identity.generate())
        let pairs = Pairs.of(toThem)
        let tag = toThem.outgoingTag(window: 1)
        let over = SyncPacket(
            wraps: [tag: Data(count: 32)], ciphertext: Data(count: MailboxRules.recordByteCeiling + 1))
        let atBudget = SyncPacket(wraps: [tag: Data(count: 32)], ciphertext: Data(count: SyncSession.packetByteBudget))

        var refusal: (any Error)?
        do { try await mailbox.put(over, to: toThem.them, in: pairs) } catch { refusal = error }
        guard let refusal else { throw MailboxContractBreach(.c2, "a packet over the ceiling was accepted") }
        guard case .recordTooLarge? = refusal as? MailboxError else {
            throw MailboxContractBreach(.c2, "a packet over the ceiling failed as \(refusal), not as too large")
        }
        do {
            try await mailbox.put(atBudget, to: toThem.them, in: pairs)
        } catch {
            throw MailboxContractBreach(.c2, "a packet at the app's own budget was refused: \(error)")
        }
        try await afterWrite()

        let listed = try await mailbox.sentPackets(in: pairs)
        guard listed[over.id] == nil else {
            throw MailboxContractBreach(.c2, "the refused packet was stored anyway")
        }
        guard listed[atBudget.id] != nil else {
            throw MailboxContractBreach(.c2, "the packet at the budget was accepted and then not listed")
        }
    }

    public static func aWithdrawnPacketIsNoLongerListed(in mailbox: any Mailbox, afterWrite: AfterWrite) async throws {
        let toThem = try someone(for: Identity.generate())
        let pairs = Pairs.of(toThem)
        let packet = freshPacket(to: toThem)
        try await mailbox.put(packet, to: toThem.them, in: pairs)
        try await afterWrite()
        guard try await mailbox.sentPackets(in: pairs)[packet.id] != nil else {
            throw MailboxContractBreach(.c3, "the packet was never listed, so withdrawing it proves nothing")
        }

        try await mailbox.withdraw(packet.id, in: pairs)
        try await afterWrite()
        guard try await mailbox.sentPackets(in: pairs)[packet.id] == nil else {
            throw MailboxContractBreach(.c3, "a withdrawn packet was still listed")
        }
    }

    public static func spacesAreFoundAgainAndCodesAreNew(in mailbox: any Mailbox, afterWrite: AfterWrite)
        async throws
    {
        let me = Identity.generate()
        let (toThem, toOther) = (try someone(for: me), try someone(for: me))
        let pairs = Pairs.of(toThem, toOther)

        let first = try await mailbox.space(for: toThem.them, naming: nil, in: pairs)
        try await afterWrite()
        let again = try await mailbox.space(for: toThem.them, naming: nil, in: pairs)
        guard again == first else {
            throw MailboxContractBreach(.c4, "asking twice for one person's space gave two links")
        }

        let code = try await mailbox.spaceForACode(in: pairs)
        let secondCode = try await mailbox.spaceForACode(in: pairs)
        try await afterWrite()
        guard code != secondCode, !Set([code, secondCode]).contains(first) else {
            throw MailboxContractBreach(.c4, "a space for a code reused a link already given out")
        }

        let claimed = try await mailbox.claim(code, for: toOther.them, naming: nil, in: pairs)
        try await afterWrite()
        guard claimed == code else {
            throw MailboxContractBreach(.c4, "claiming a code's space for a new person answered with another link")
        }
        guard try await mailbox.space(for: toOther.them, naming: nil, in: pairs) == code else {
            throw MailboxContractBreach(.c4, "a claimed code's space was not that person's space afterwards")
        }
    }

    public static func aPhotoIsOneCopyPerPerson(in mailbox: any Mailbox & MediaMailbox, afterWrite: AfterWrite)
        async throws
    {
        let me = Identity.generate()
        let (toThem, toOther) = (try someone(for: me), try someone(for: me))
        let pairs = Pairs.of(toThem, toOther)
        let peers = [toThem.them: toThem, toOther.them: toOther]
        let copies = try OutgoingAttachment(
            id: AttachmentID(), ciphertext: randomBytes(64),
            recipients: [toThem.them: toThem.outgoingTag(window: 1), toOther.them: toOther.outgoingTag(window: 1)]
        ).copies(between: { peers[$0]?.secret })
        let ours = Set(copies.copies.values.map(\.name))

        try await mailbox.upload(copies, in: pairs)
        try await afterWrite()
        let first = try await mailbox.storedCopies(in: pairs).filter { ours.contains($0.name) }
        guard first.count == 2, Set(first.map(\.name)) == ours else {
            throw MailboxContractBreach(.c5, "a photo for two people was stored as \(first.count) copy(ies)")
        }
        for stored in first {
            guard let peer = peers[stored.to], copies.copies[peer.them]?.name == stored.name else {
                throw MailboxContractBreach(.c5, "a copy was listed as being for somebody it was not sealed for")
            }
            guard stored.recipients == [peer.outgoingTag(window: 1)] else {
                throw MailboxContractBreach(.c5, "a copy did not name the one person it is for")
            }
        }

        try await mailbox.upload(copies, in: pairs)
        try await afterWrite()
        let again = try await mailbox.storedCopies(in: pairs).filter { ours.contains($0.name) }
        for before in first {
            guard let after = again.first(where: { $0.name == before.name }) else {
                throw MailboxContractBreach(.c5, "writing a photo again lost one of its copies")
            }
            guard after.storedAt == before.storedAt else {
                throw MailboxContractBreach(.c5, "writing a copy again moved when it was first stored")
            }
            guard after.modifiedAt > before.modifiedAt else {
                throw MailboxContractBreach(.c5, "writing a copy again did not move when it was last stored")
            }
        }
    }

    // MARK: A pair, two accounts

    public static func run(
        _ check: PairCheck, as role: PairRole, on mailbox: any Mailbox, board: any ContractBoard,
        afterWrite: @escaping AfterWrite
    ) async throws {
        let side = PairSide(role, of: check, on: mailbox, board: board, afterWrite: afterWrite)
        for step in check.steps where step.role == role { try await step.run(side) }
    }

    public static func runBothRoles(_ check: PairCheck, on mailbox: any Mailbox, afterWrite: @escaping AfterWrite)
        async throws
    {
        let board = MemoryBoard()
        let alice = PairSide(.alice, of: check, on: mailbox, board: board, afterWrite: afterWrite)
        let bob = PairSide(.bob, of: check, on: mailbox, board: board, afterWrite: afterWrite)
        for step in check.steps { try await step.run(step.role == .alice ? alice : bob) }
    }

    static func someone(for me: Identity) throws -> Peer {
        let them = Identity.generate()
        return Peer(secret: try PairwiseSecret.derive(mine: me, theirs: them.publicKeys), them: them.id, me: me.id)
    }

    static func freshPacket(to peer: Peer) -> SyncPacket {
        let tag = peer.outgoingTag(window: 1)
        return SyncPacket(wraps: [tag: randomBytes(48)], ciphertext: randomBytes(512), grants: [tag: [randomBytes(32)]])
    }

    static func randomBytes(_ count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: .min ... .max) })
    }
}

public enum PairRole: String, Sendable {
    case alice, bob

    var other: PairRole { self == .alice ? .bob : .alice }
}

public enum PairEnding: String, CaseIterable, Sendable {
    case stopSharing, leave, close
}

public enum PairCheck: Hashable, Sendable, CustomStringConvertible {
    case joinWaitsForTheReaderToBeNamed
    case aPacketArrivesAsItWasStored
    case packetsArriveInTheOrderFirstStored
    case aReceiptReachesBothSides
    case aRingIsNeverCollected
    case endingThePairStopsTheReading(PairEnding)

    public static let all: [PairCheck] =
        [
            .joinWaitsForTheReaderToBeNamed, .aPacketArrivesAsItWasStored, .packetsArriveInTheOrderFirstStored,
            .aReceiptReachesBothSides, .aRingIsNeverCollected,
        ] + PairEnding.allCases.map(PairCheck.endingThePairStopsTheReading)

    public var rule: MailboxContract.Rule {
        switch self {
        case .joinWaitsForTheReaderToBeNamed: .c6
        case .aPacketArrivesAsItWasStored: .c7
        case .packetsArriveInTheOrderFirstStored: .c8
        case .aReceiptReachesBothSides: .c9
        case .aRingIsNeverCollected: .c10
        case .endingThePairStopsTheReading: .c11
        }
    }

    public var description: String {
        if case .endingThePairStopsTheReading(let ending) = self { return "\(rule.rawValue)-\(ending.rawValue)" }
        return rule.rawValue
    }

    var steps: [PairStep] {
        switch self {
        case .joinWaitsForTheReaderToBeNamed:
            PairStep.meeting + [
                .alice { try await $0.offerALinkNamingNobody() },
                .bob { try await $0.joinBeforeBeingNamed() },
                .alice { try await $0.nameTheReader() },
                .bob { try await $0.joinOnceNamed() },
            ]
        case .aPacketArrivesAsItWasStored:
            PairStep.linking + [
                .alice { try await $0.putAPacket() },
                .bob { try await $0.collectThePacketAsItWent() },
                .alice { try await $0.writeThePacketAgain() },
                .bob { try await $0.collectThePacketWrittenAgain() },
            ]
        case .packetsArriveInTheOrderFirstStored:
            PairStep.linking + [
                .alice { try await $0.putThreeAndRewriteTheFirst() },
                .bob { try await $0.collectInTheOrderFirstStored() },
            ]
        case .aReceiptReachesBothSides:
            PairStep.linking + [
                .alice { try await $0.putAPacket() },
                .bob { try await $0.acknowledgeThePacket() },
                .alice { try await $0.seeTheReceipt() },
            ]
        case .aRingIsNeverCollected:
            PairStep.linking + [
                .alice { try await $0.ringThenPutAPacket() },
                .bob { try await $0.collectOnlyThePacket() },
            ]
        case .endingThePairStopsTheReading(let ending):
            PairStep.linking + [
                .alice { try await $0.putAPacket() },
                .bob { try await $0.collectBeforeTheEnd() },
            ] + PairStep.ending(ending)
        }
    }
}

public protocol ContractBoard: Sendable {
    func leave(_ value: String, as name: String) async throws

    func read(_ name: String) async throws -> String
}

public actor MemoryBoard: ContractBoard {
    public struct NothingLeft: Error, CustomStringConvertible {
        public let name: String
        public var description: String { "nothing was left on the board as \(name)" }
    }

    private var values: [String: String] = [:]

    public init() {}

    public func leave(_ value: String, as name: String) { values[name] = value }

    public func read(_ name: String) throws -> String {
        guard let value = values[name] else { throw NothingLeft(name: name) }
        return value
    }
}

struct PairStep: Sendable {
    let role: PairRole
    let run: @Sendable (PairSide) async throws -> Void

    static func alice(_ run: @escaping @Sendable (PairSide) async throws -> Void) -> PairStep {
        PairStep(role: .alice, run: run)
    }

    static func bob(_ run: @escaping @Sendable (PairSide) async throws -> Void) -> PairStep {
        PairStep(role: .bob, run: run)
    }

    static let meeting: [PairStep] = [
        .alice { try await $0.introduce() },
        .bob { try await $0.introduce() },
        .alice { try await $0.meet() },
        .bob { try await $0.meet() },
    ]

    static let linking: [PairStep] =
        meeting + [
            .alice { try await $0.offerALinkNamingThem() },
            .bob { try await $0.offerALinkNamingThem() },
            .alice { try await $0.joinTheirLink() },
            .bob { try await $0.joinTheirLink() },
        ]

    static func ending(_ ending: PairEnding) -> [PairStep] {
        switch ending {
        case .leave:
            [.bob { try await $0.leaveAndReadNothing() }]
        case .stopSharing, .close:
            [
                .alice { try await $0.end(ending) },
                .bob { try await $0.readNothingOnceEnded() },
            ]
        }
    }
}

actor PairSide {
    private let role: PairRole
    private let check: PairCheck
    private let mailbox: any Mailbox
    private let board: any ContractBoard
    private let afterWrite: MailboxContract.AfterWrite
    private let identity = Identity.generate()

    private var peer: Peer?
    private var pairs: Pairs?
    private var theirAccount = ""
    private var myAccount = ""
    private var offered: URL?
    private var written: [SyncPacket] = []
    private var firstSeenStoredAt: Date?

    init(
        _ role: PairRole, of check: PairCheck, on mailbox: any Mailbox, board: any ContractBoard,
        afterWrite: @escaping MailboxContract.AfterWrite
    ) {
        self.role = role
        self.check = check
        self.mailbox = mailbox
        self.board = board
        self.afterWrite = afterWrite
    }

    private func breach(_ saw: String) -> MailboxContractBreach {
        MailboxContractBreach(check.rule, "\(role.rawValue) \(saw)")
    }

    private func post(_ value: String, as name: String) async throws {
        try await board.leave(value, as: "\(check)-\(role.rawValue)-\(name)")
    }

    private func theirs(_ name: String) async throws -> String {
        let value = try await board.read("\(check)-\(role.other.rawValue)-\(name)")
        try await afterWrite()
        return value
    }

    private func linked() throws -> (peer: Peer, pairs: Pairs) {
        guard let peer, let pairs else { throw breach("ran a step before meeting the other side") }
        return (peer, pairs)
    }

    private func collect() async throws -> [SyncPacket] {
        let (peer, pairs) = try linked()
        return try await mailbox.fetch(from: peer.them, for: [peer.incomingTag(window: 1)], in: pairs)
    }

    private func packetIDs(_ name: String) async throws -> [PacketID] {
        try await theirs(name).split(separator: ",").compactMap { UUID(uuidString: String($0)) }
            .map(PacketID.init(rawValue:))
    }

    private func put(_ packet: SyncPacket) async throws {
        let (peer, pairs) = try linked()
        try await mailbox.put(packet, to: peer.them, in: pairs)
        try await afterWrite()
    }

    // MARK: Meeting and linking

    func introduce() async throws {
        myAccount = try await mailbox.account(in: Pairs(me: identity.id, hints: [:]))
        try await post(try JSONEncoder().encode(identity.publicKeys).base64EncodedString(), as: "keys")
        try await post(myAccount, as: "account")
    }

    func meet() async throws {
        guard let encoded = Data(base64Encoded: try await theirs("keys")),
            let keys = try? JSONDecoder().decode(IdentityPublicKeys.self, from: encoded)
        else { throw breach("could not read the other side's keys off the board") }
        theirAccount = try await theirs("account")
        let met = Peer(
            secret: try PairwiseSecret.derive(mine: identity, theirs: keys), them: keys.participantID, me: identity.id)
        peer = met
        pairs = Pairs(me: identity.id, hints: [met.them: met.secret.pairHint], accounts: [met.them: [theirAccount]])
    }

    func offerALinkNamingThem() async throws {
        let (peer, pairs) = try linked()
        let url = try await mailbox.space(for: peer.them, naming: theirAccount, in: pairs)
        try await afterWrite()
        try await post(url.absoluteString, as: "link")
    }

    func joinTheirLink() async throws {
        let outcome = try await join(theirs("link"), claiming: theirAccount)
        guard outcome == .joined else { throw breach("could not join a space that named them: \(outcome)") }
    }

    private func join(_ link: String, claiming account: String) async throws -> JoinOutcome {
        let (peer, pairs) = try linked()
        guard let url = URL(string: link) else { throw breach("read a link that is not a URL off the board") }
        return try await mailbox.join(PairLink(account: account, url: url), of: peer.them, in: pairs)
    }

    // MARK: C6

    func offerALinkNamingNobody() async throws {
        let (peer, pairs) = try linked()
        let url = try await mailbox.space(for: peer.them, naming: nil, in: pairs)
        offered = url
        try await afterWrite()
        try await post(url.absoluteString, as: "link")
    }

    func joinBeforeBeingNamed() async throws {
        let outcome = try await join(theirs("link"), claiming: theirAccount)
        guard outcome == .notYetNamed else {
            throw breach("joined a space nobody had named them on and was told \(outcome), not notYetNamed")
        }
        try await post("tried", as: "tried")
    }

    func nameTheReader() async throws {
        _ = try await theirs("tried")
        let (peer, pairs) = try linked()
        let url = try await mailbox.space(for: peer.them, naming: theirAccount, in: pairs)
        guard url == offered else { throw breach("naming the reader moved the space to another link") }
        try await afterWrite()
        try await post("named", as: "named")
    }

    func joinOnceNamed() async throws {
        let link = try await theirs("link")
        _ = try await theirs("named")
        let named = try await join(link, claiming: theirAccount)
        guard named == .joined else { throw breach("was named on the space and joining it said \(named)") }

        let (peer, pairs) = try linked()
        let own = try await mailbox.space(for: peer.them, naming: theirAccount, in: pairs)
        try await afterWrite()
        let ownOutcome = try await join(own.absoluteString, claiming: myAccount)
        guard ownOutcome == .gone else { throw breach("joined their own space's link and was told \(ownOutcome)") }

        let forged = try await join(link, claiming: myAccount)
        guard forged == .gone else {
            throw breach("joined a link that claimed the wrong account and was told \(forged)")
        }
    }

    // MARK: Packets

    func putAPacket() async throws {
        let packet = MailboxContract.freshPacket(to: try linked().peer)
        try await put(packet)
        written = [packet]
        try await post(packet.contentDigest.lowercaseHex, as: "digest")
        try await post(packet.id.rawValue.uuidString, as: "packet")
    }

    private func theOneWritten() async throws -> (id: PacketID, found: SyncPacket?) {
        guard let id = try await packetIDs("packet").first else { throw breach("found no packet named on the board") }
        return (id, try await collect().first { $0.id == id })
    }

    func collectThePacketAsItWent() async throws {
        let digest = try await theirs("digest")
        let (_, found) = try await theOneWritten()
        guard let packet = found else { throw breach("never collected the packet put for them") }
        guard packet.contentDigest.lowercaseHex == digest else {
            throw breach("collected bytes that are not the bytes that were put")
        }
        guard packet.from == (try linked().peer.them) else {
            throw breach("collected a packet not marked from its writer")
        }
        guard let storedAt = packet.storedAt else { throw breach("collected a packet with no stored time") }
        firstSeenStoredAt = storedAt
        try await post("seen", as: "seen")
    }

    func writeThePacketAgain() async throws {
        _ = try await theirs("seen")
        guard let packet = written.first else { throw breach("had no packet to write again") }
        try await put(packet)
        try await post("again", as: "again")
    }

    func collectThePacketWrittenAgain() async throws {
        _ = try await theirs("again")
        let (_, found) = try await theOneWritten()
        guard let packet = found, let storedAt = packet.storedAt, let first = firstSeenStoredAt else {
            throw breach("lost the packet once it was written again")
        }
        guard storedAt > first else {
            throw breach("collected a rewritten packet still dated \(first), when it was first stored, not last")
        }
    }

    func putThreeAndRewriteTheFirst() async throws {
        let peer = try linked().peer
        let three = (0..<3).map { _ in MailboxContract.freshPacket(to: peer) }
        for packet in three { try await put(packet) }
        try await put(three[0])
        try await post(three.map(\.id.rawValue.uuidString).joined(separator: ","), as: "packets")
    }

    func collectInTheOrderFirstStored() async throws {
        let order = try await packetIDs("packets")
        let wanted = Set(order)
        let arrived = try await collect().map(\.id).filter { wanted.contains($0) }
        guard arrived == order else {
            let positions = arrived.map { id in order.firstIndex(of: id).map { "\($0 + 1)" } ?? "?" }
            throw breach("collected packets first stored as 1,2,3 in the order \(positions.joined(separator: ","))")
        }
    }

    func acknowledgeThePacket() async throws {
        let (id, found) = try await theOneWritten()
        guard found != nil else { throw breach("never collected the packet put for them") }
        let (peer, pairs) = try linked()
        let receipt = SealedReceipt(tag: peer.incomingTag(window: 1), sealed: MailboxContract.randomBytes(24))
        try await mailbox.acknowledge(id, from: peer.them, with: receipt, in: pairs)
        try await afterWrite()
        try await post(receipt.sealed.lowercaseHex, as: "receipt")

        guard try await collect().first(where: { $0.id == id })?.receipts == [receipt] else {
            throw breach("acknowledged a packet and the next fetch did not carry the receipt")
        }
    }

    func seeTheReceipt() async throws {
        guard let sealed = Data(lowercaseHex: try await theirs("receipt")), let packet = written.first else {
            throw breach("could not read the receipt off the board")
        }
        let (peer, pairs) = try linked()
        let receipt = SealedReceipt(tag: peer.outgoingTag(window: 1), sealed: sealed)
        guard let listed = try await mailbox.sentPackets(in: pairs)[packet.id] else {
            throw breach("no longer listed the packet that was acknowledged")
        }
        guard listed.receipts == [receipt] else {
            throw breach("listed the acknowledged packet with \(listed.receipts.count) matching receipt(s), not one")
        }
        guard listed.receiptStoredAt != nil else { throw breach("listed the receipt without when it was stored") }
    }

    func ringThenPutAPacket() async throws {
        let (peer, pairs) = try linked()
        try await mailbox.ring(peer.them, in: pairs)
        try await afterWrite()
        try await putAPacket()
    }

    func collectOnlyThePacket() async throws {
        guard let id = try await packetIDs("packet").first else { throw breach("found no packet named on the board") }
        let collected = try await collect()
        guard collected.map(\.id) == [id] else {
            throw breach("collected \(collected.count) packet(s) after one ring and one packet")
        }
    }

    // MARK: C11

    func collectBeforeTheEnd() async throws {
        let (_, found) = try await theOneWritten()
        let (peer, pairs) = try linked()
        guard found != nil, try await mailbox.reads(peer.them, in: pairs) else {
            throw breach("could not read the space before it ended, so its ending proves nothing")
        }
        try await post("seen", as: "seen")
    }

    func end(_ ending: PairEnding) async throws {
        _ = try await theirs("seen")
        let (peer, pairs) = try linked()
        switch ending {
        case .stopSharing: try await mailbox.stopSharing(with: peer.them, in: pairs)
        case .close: try await mailbox.close(peer.them, in: pairs)
        case .leave: try await mailbox.leave(peer.them, in: pairs)
        }
        try await afterWrite()
        try await post(ending.rawValue, as: "ended")
    }

    func readNothingOnceEnded() async throws {
        _ = try await theirs("ended")
        try await readNothing()
    }

    func leaveAndReadNothing() async throws {
        let (peer, pairs) = try linked()
        try await mailbox.leave(peer.them, in: pairs)
        try await afterWrite()
        try await readNothing()
    }

    private func readNothing() async throws {
        let (peer, pairs) = try linked()
        guard !(try await mailbox.reads(peer.them, in: pairs)) else {
            throw breach("still reads the space after it ended")
        }
        let collected = try await collect()
        guard collected.isEmpty else { throw breach("collected \(collected.count) packet(s) after the space ended") }
    }
}
