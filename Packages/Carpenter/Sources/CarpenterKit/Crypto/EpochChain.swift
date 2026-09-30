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

    public var fingerprint: Data {
        Data(SHA256.hash(data: CanonicalBytes.payload(domain: Domain.epochFingerprint, fields: [material])))
    }
}

public struct EpochLink: Hashable, Sendable, Codable {
    public let room: RoomID
    public let epoch: EpochNumber
    public let wrapped: Data

    public init(room: RoomID, epoch: EpochNumber, wrapped: Data) {
        self.room = room
        self.epoch = epoch
        self.wrapped = wrapped
    }

    var context: Data {
        CanonicalBytes.payload(
            domain: Domain.epochLink, fields: [room.canonicalBytes, epoch.canonicalBytes])
    }
}

extension EpochChangeBody {
    public init(link: EpochLink, heads: [EntryHash], under secret: EpochSecret) {
        self.init(
            link: link, heads: heads,
            proof: Data(
                HMAC<SHA256>.authenticationCode(for: Self.naming(heads), using: Self.key(of: link, under: secret))))
    }

    public func isAuthentic(under secret: EpochSecret) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(
            proof, authenticating: Self.naming(heads), using: Self.key(of: link, under: secret))
    }

    private static func naming(_ heads: [EntryHash]) -> Data {
        CanonicalBytes.payload(domain: Domain.epochChange, fields: heads.map(\.rawValue))
    }

    private static func key(of link: EpochLink, under secret: EpochSecret) -> SymmetricKey {
        EpochChain.changeKey(for: secret, room: link.room, epoch: link.epoch)
    }
}

public struct EpochChain: Sendable {
    public let room: RoomID

    private var secrets: [EpochNumber: EpochSecret] = [:]
    private var rivals: [EpochNumber: [EpochSecret]] = [:]
    private var givenBy: [EpochNumber: [EpochSecret: ParticipantID]] = [:]
    private var links: [EpochNumber: EpochLink] = [:]

    public static let mostRivals = 16

    public init(room: RoomID) {
        self.room = room
    }

    public static func create(room: RoomID) -> (chain: EpochChain, secret: EpochSecret) {
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

    public var heldKeyCount: Int { secrets.count + rivals.values.reduce(0) { $0 + $1.count } }

    public func heldSecrets(at epoch: EpochNumber) -> [EpochSecret] {
        ((try? secret(for: epoch)).map { [$0] } ?? []) + (rivals[epoch] ?? [])
    }

    public func giver(of secret: EpochSecret, at epoch: EpochNumber) -> ParticipantID? {
        givenBy[epoch]?[secret]
    }

    public mutating func adopt(_ secret: EpochSecret, at epoch: EpochNumber) {
        if let held = secrets[epoch], held != secret, !(rivals[epoch] ?? []).contains(held) {
            rivals[epoch, default: []].append(held)
        }
        rivals[epoch]?.removeAll { $0 == secret }
        secrets[epoch] = secret
    }

    public mutating func hold(_ secret: EpochSecret, at epoch: EpochNumber, from giver: ParticipantID? = nil) {
        if secrets[epoch] == nil, let derived = try? self.secret(for: epoch) { secrets[epoch] = derived }
        guard let primary = secrets[epoch] else {
            secrets[epoch] = secret
            if let giver { givenBy[epoch, default: [:]][secret] = giver }
            return
        }
        guard primary != secret, epoch != .initial, !(rivals[epoch] ?? []).contains(secret),
            (rivals[epoch]?.count ?? 0) < Self.mostRivals
        else { return }
        if let giver {
            guard !(givenBy[epoch]?.values.contains(giver) ?? false) else { return }
            givenBy[epoch, default: [:]][secret] = giver
        }
        rivals[epoch, default: []].append(secret)
    }

    public func choosing(_ secret: EpochSecret, at epoch: EpochNumber) -> EpochChain {
        var chosen = self
        chosen.adopt(secret, at: epoch)
        return chosen
    }

    public mutating func record(_ link: EpochLink) throws {
        guard link.room == room else { throw CryptoError.wrongRoom }
        if let held = links[link.epoch], opens(held) != false { return }
        guard opens(link) != false else { return }
        links[link.epoch] = link
    }

    private func opens(_ link: EpochLink) -> Bool? {
        guard let secret = secrets[link.epoch] else { return nil }
        guard let box = try? ChaChaPoly.SealedBox(combined: link.wrapped) else { return false }
        let key = Self.wrappingKey(for: secret, room: room, epoch: link.epoch)
        return (try? ChaChaPoly.open(box, using: key, authenticating: link.context)) != nil
    }

    public mutating func record(_ links: some Sequence<EpochLink>) throws {
        for link in links { try record(link) }
    }

    public static func advance(
        from previous: EpochSecret, at previousEpoch: EpochNumber, room: RoomID
    ) throws -> (secret: EpochSecret, link: EpochLink) {
        guard previousEpoch.rawValue < .max else { throw CryptoError.unknownEpoch }
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

    public func sealingKeys(for epoch: EpochNumber) -> [SymmetricKey] {
        heldSecrets(at: epoch).map { Self.derivedKey(from: $0, room: room, epoch: epoch, domain: Domain.epochSealing) }
    }

    public func unwrapping(_ epoch: EpochNumber, under secret: EpochSecret) -> EpochSecret? {
        guard let link = links[epoch], let box = try? ChaChaPoly.SealedBox(combined: link.wrapped),
            let opened = try? ChaChaPoly.open(
                box, using: Self.wrappingKey(for: secret, room: room, epoch: epoch), authenticating: link.context)
        else { return nil }
        return EpochSecret(material: opened)
    }

    public mutating func warm(downTo epoch: EpochNumber) throws {
        guard let highest = highestKnownEpoch, epoch <= highest else { return }
        var cursor = highest
        while cursor > epoch {
            guard links[cursor] != nil else { throw CryptoError.unknownEpoch }
            let opened = heldSecrets(at: cursor).compactMap { unwrapping(cursor, under: $0) }
            guard let linked = opened.first else { throw CryptoError.openFailed }
            guard let step = cursor.previous else { break }
            cursor = step
            if secrets[cursor] == nil { secrets[cursor] = linked }
            for secret in opened { hold(secret, at: cursor) }
        }
    }

    private func requireSecret(at epoch: EpochNumber) throws -> EpochSecret {
        guard let secret = secrets[epoch] else { throw CryptoError.unknownEpoch }
        return secret
    }

    fileprivate static func changeKey(for secret: EpochSecret, room: RoomID, epoch: EpochNumber) -> SymmetricKey {
        derivedKey(from: secret, room: room, epoch: epoch, domain: Domain.epochChange)
    }

    private static func wrappingKey(
        for secret: EpochSecret, room: RoomID, epoch: EpochNumber
    ) -> SymmetricKey {
        derivedKey(from: secret, room: room, epoch: epoch, domain: Domain.epochWrapping)
    }

    private static func derivedKey(
        from secret: EpochSecret, room: RoomID, epoch: EpochNumber, domain: String
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
