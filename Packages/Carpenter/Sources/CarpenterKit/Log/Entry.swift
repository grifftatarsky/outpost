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

    public var feedKey: FeedKey { FeedKey(author: author, device: device) }

    public var hash: EntryHash {
        let digest = SHA256.hash(
            data: CanonicalBytes.payload(
                domain: Domain.entryHash, fields: [signingPayload, signature]))
        return EntryHash(rawValue: Data(digest))
    }

    var signingPayload: Data {
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
