import CryptoKit
import Foundation

public struct EpochNumber: Hashable, Sendable, Codable, Comparable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let initial = EpochNumber(rawValue: 0)

    public var next: EpochNumber { EpochNumber(rawValue: rawValue + 1) }

    public var previous: EpochNumber? {
        rawValue == 0 ? nil : EpochNumber(rawValue: rawValue - 1)
    }

    public static func < (lhs: EpochNumber, rhs: EpochNumber) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var canonicalBytes: Data { CanonicalBytes.sequence(rawValue) }
}

public struct EpochSecret: Hashable, Sendable {
    public let material: Data

    public init(material: Data) {
        self.material = material
    }

    public static func random() -> EpochSecret {
        EpochSecret(material: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
    }
}

public struct EpochLink: Hashable, Sendable, Codable {
    public let room: ConversationID
    public let epoch: EpochNumber
    public let wrapped: Data

    public init(room: ConversationID, epoch: EpochNumber, wrapped: Data) {
        self.room = room
        self.epoch = epoch
        self.wrapped = wrapped
    }

    var context: Data {
        CanonicalBytes.payload(
            domain: Domain.epochLink, fields: [room.canonicalBytes, epoch.canonicalBytes])
    }
}

public struct EpochChain: Sendable {
    public let room: ConversationID

    private var secrets: [EpochNumber: EpochSecret] = [:]
    private var links: [EpochNumber: EpochLink] = [:]

    public init(room: ConversationID) {
        self.room = room
    }

    public static func create(room: ConversationID) -> (chain: EpochChain, secret: EpochSecret) {
        var chain = EpochChain(room: room)
        let secret = EpochSecret.random()
        chain.adopt(secret, at: .initial)
        return (chain, secret)
    }

    public var knownEpochs: Set<EpochNumber> { Set(secrets.keys) }

    public var knownLinks: Set<EpochNumber> { Set(links.keys) }

    public func link(at epoch: EpochNumber) -> EpochLink? { links[epoch] }

    public var everyLink: [EpochLink] { links.values.sorted { $0.epoch < $1.epoch } }

    public var highestKnownEpoch: EpochNumber? { secrets.keys.max() }

    public mutating func adopt(_ secret: EpochSecret, at epoch: EpochNumber) {
        secrets[epoch] = secret
    }

    public mutating func record(_ link: EpochLink) throws {
        guard link.room == room else { throw CryptoError.wrongRoom }
        links[link.epoch] = link
    }

    public mutating func record(_ links: some Sequence<EpochLink>) throws {
        for link in links { try record(link) }
    }

    public static func advance(
        from previous: EpochSecret, at previousEpoch: EpochNumber, room: ConversationID
    ) throws -> (secret: EpochSecret, link: EpochLink) {
        let epoch = previousEpoch.next
        let secret = EpochSecret.random()
        let link = EpochLink(room: room, epoch: epoch, wrapped: Data())

        let sealed = try ChaChaPoly.seal(
            previous.material,
            using: wrappingKey(for: secret, room: room, epoch: epoch),
            authenticating: link.context
        )

        return (secret, EpochLink(room: room, epoch: epoch, wrapped: sealed.combined))
    }

    public func secret(for epoch: EpochNumber) throws -> EpochSecret {
        if let known = secrets[epoch] { return known }

        guard let start = secrets.keys.filter({ $0 > epoch }).min() else {
            throw CryptoError.unknownEpoch
        }

        var current = try requireSecret(at: start)
        var cursor = start

        while cursor > epoch {
            guard let link = links[cursor] else { throw CryptoError.unknownEpoch }
            let key = Self.wrappingKey(for: current, room: room, epoch: cursor)

            guard let box = try? ChaChaPoly.SealedBox(combined: link.wrapped),
                let opened = try? ChaChaPoly.open(box, using: key, authenticating: link.context)
            else {
                throw CryptoError.openFailed
            }

            current = EpochSecret(material: opened)
            guard let step = cursor.previous else { throw CryptoError.unknownEpoch }
            cursor = step
        }

        return current
    }

    public func sealingKey(for epoch: EpochNumber) throws -> SymmetricKey {
        Self.derivedKey(
            from: try secret(for: epoch), room: room, epoch: epoch, domain: Domain.epochSealing)
    }

    public mutating func warm(downTo epoch: EpochNumber) throws {
        guard let highest = highestKnownEpoch, epoch <= highest else { return }
        var cursor = highest
        while cursor >= epoch {
            secrets[cursor] = try secret(for: cursor)
            guard let step = cursor.previous else { break }
            cursor = step
        }
    }

    private func requireSecret(at epoch: EpochNumber) throws -> EpochSecret {
        guard let secret = secrets[epoch] else { throw CryptoError.unknownEpoch }
        return secret
    }

    private static func wrappingKey(
        for secret: EpochSecret, room: ConversationID, epoch: EpochNumber
    ) -> SymmetricKey {
        derivedKey(from: secret, room: room, epoch: epoch, domain: Domain.epochWrapping)
    }

    private static func derivedKey(
        from secret: EpochSecret, room: ConversationID, epoch: EpochNumber, domain: String
    ) -> SymmetricKey {
        SymmetricKey(
            data: HKDF<SHA256>.deriveKey(
                inputKeyMaterial: SymmetricKey(data: secret.material),
                salt: Data(domain.utf8),
                info: CanonicalBytes.payload(
                    domain: domain, fields: [room.canonicalBytes, epoch.canonicalBytes]),
                outputByteCount: 32
            ))
    }
}
