import CryptoKit
import Foundation

public struct EntryHash: Hashable, Sendable, Codable {
    public let rawValue: Data

    public init(rawValue: Data) {
        self.rawValue = rawValue
    }
}

public struct EntryLink: Hashable, Sendable, Codable {
    public let seq: UInt64
    public let hash: EntryHash

    public init(seq: UInt64, hash: EntryHash) {
        self.seq = seq
        self.hash = hash
    }
}

public struct Entry: Hashable, Sendable, Codable {
    public let author: ParticipantID
    public let device: DeviceID
    public let seq: UInt64
    public let previous: EntryHash?
    public let clock: VectorClock

    public let wallTime: Date

    public let room: RoomID?

    public let payload: SealedPayload
    public let signature: Data
    public let hash: EntryHash

    public var feedKey: FeedKey { FeedKey(author: author, device: device) }

    private static func hash(signing: Data, signature: Data) -> EntryHash {
        let digest = SHA256.hash(
            data: CanonicalBytes.payload(domain: Domain.entryHash, fields: [signing, signature]))
        return EntryHash(rawValue: Data(digest))
    }

    var signingPayload: Data {
        Self.signingPayload(
            author: author, device: device, seq: seq, previous: previous, clock: clock,
            wallTime: wallTime, room: room, payload: payload)
    }

    private static func signingPayload(
        author: ParticipantID, device: DeviceID, seq: UInt64, previous: EntryHash?,
        clock: VectorClock, wallTime: Date, room: RoomID?, payload: SealedPayload
    ) -> Data {
        CanonicalBytes.payload(
            domain: Domain.entry,
            fields: [
                author.rawValue,
                device.rawValue,
                CanonicalBytes.sequence(seq),
            ]
                + CanonicalBytes.optional(previous?.rawValue)
                + [
                    clock.canonicalBytes,
                    CanonicalBytes.timestamp(wallTime),
                ]
                + CanonicalBytes.optional(room?.canonicalBytes)
                + [payload.canonicalBytes]
        )
    }

    public static let firstSequence: UInt64 = 1

    public var link: EntryLink { EntryLink(seq: seq, hash: hash) }

    public static func append(
        to previous: Entry?,
        author: ParticipantID,
        device: DeviceKeys,
        clock: VectorClock,
        wallTime: Date,
        room: RoomID?,
        payload: SealedPayload
    ) throws -> Entry {
        try append(
            after: previous?.link, author: author, device: device, clock: clock,
            wallTime: wallTime, room: room, payload: payload)
    }

    public static func append(
        after previous: EntryLink?,
        author: ParticipantID,
        device: DeviceKeys,
        clock: VectorClock,
        wallTime: Date,
        room: RoomID?,
        payload: SealedPayload
    ) throws -> Entry {
        let seq = (previous?.seq).map { $0 + 1 } ?? firstSequence

        var clock = clock
        clock.observe(FeedKey(author: author, device: device.id), seq: seq)

        var entry = Entry(
            author: author,
            device: device.id,
            seq: seq,
            previous: previous?.hash,
            clock: clock,
            wallTime: wallTime,
            room: room,
            payload: payload,
            signature: Data()
        )
        entry = Entry(entry, signature: try device.sign(entry.signingPayload))
        return entry
    }

    public static func append(
        to previous: Entry?,
        author: ParticipantID,
        device: DeviceKeys,
        clock: VectorClock,
        wallTime: Date,
        room: RoomID?,
        payload: Payload,
        at epoch: EpochNumber,
        sealedWith chain: EpochChain,
        alsoFor extra: PairwiseSecret? = nil
    ) throws -> Entry {
        try append(
            after: previous?.link, author: author, device: device, clock: clock,
            wallTime: wallTime, room: room, payload: payload, at: epoch, sealedWith: chain,
            alsoFor: extra)
    }

    public static func append(
        after previous: EntryLink?,
        author: ParticipantID,
        device: DeviceKeys,
        clock: VectorClock,
        wallTime: Date,
        room: RoomID?,
        payload: Payload,
        at epoch: EpochNumber,
        sealedWith chain: EpochChain,
        alsoFor extra: PairwiseSecret? = nil
    ) throws -> Entry {
        try append(
            after: previous, author: author, device: device, clock: clock, wallTime: wallTime,
            room: room,
            payload: try payload.sealed(
                at: epoch, using: chain, by: FeedKey(author: author, device: device.id),
                alsoFor: extra))
    }

    public func opened(using chain: EpochChain) -> Payload? {
        try? payload.opened(using: chain, by: feedKey)
    }

    public func opened(pairwise secret: PairwiseSecret, wall: RoomID) -> Payload? {
        guard payload.alsoFor != nil else { return nil }
        return try? payload.opened(pairwise: secret, room: room ?? wall, by: feedKey)
    }

    public var hasSecondReader: Bool { payload.alsoFor != nil }

    private init(_ entry: Entry, signature: Data) {
        author = entry.author
        device = entry.device
        seq = entry.seq
        previous = entry.previous
        clock = entry.clock
        wallTime = entry.wallTime
        room = entry.room
        payload = entry.payload
        self.signature = signature
        hash = Self.hash(signing: entry.signingPayload, signature: signature)
    }

    public init(
        author: ParticipantID,
        device: DeviceID,
        seq: UInt64,
        previous: EntryHash?,
        clock: VectorClock,
        wallTime: Date,
        room: RoomID?,
        payload: SealedPayload,
        signature: Data
    ) {
        self.author = author
        self.device = device
        self.seq = seq
        self.previous = previous
        self.clock = clock
        self.wallTime = wallTime
        self.room = room
        self.payload = payload
        self.signature = signature
        hash = Self.hash(
            signing: Self.signingPayload(
                author: author, device: device, seq: seq, previous: previous, clock: clock,
                wallTime: wallTime, room: room, payload: payload),
            signature: signature)
    }

    private enum CodingKeys: String, CodingKey {
        case author, device, seq, previous, clock, wallTime, room, payload, signature
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            author: try values.decode(ParticipantID.self, forKey: .author),
            device: try values.decode(DeviceID.self, forKey: .device),
            seq: try values.decode(UInt64.self, forKey: .seq),
            previous: try values.decodeIfPresent(EntryHash.self, forKey: .previous),
            clock: try values.decode(VectorClock.self, forKey: .clock),
            wallTime: try values.decode(Date.self, forKey: .wallTime),
            room: try values.decodeIfPresent(RoomID.self, forKey: .room),
            payload: try values.decode(SealedPayload.self, forKey: .payload),
            signature: try values.decode(Data.self, forKey: .signature))
    }

    public static func == (left: Entry, right: Entry) -> Bool {
        left.hash == right.hash
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(hash)
    }

    public func hasValidSignature(from devicePublicKey: Data) throws -> Bool {
        try DeviceKeys.isValidSignature(signature, for: signingPayload, publicKey: devicePublicKey)
    }
}

extension RoomID {
    var canonicalBytes: Data {
        withUnsafeBytes(of: rawValue.uuid) { Data($0) }
    }
}
