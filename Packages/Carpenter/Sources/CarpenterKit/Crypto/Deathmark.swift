import CryptoKit
import Foundation

public struct Deathmark: Hashable, Sendable, Codable {
    public let member: ParticipantID
    public let issuedBy: DeviceID
    public let devices: [DeviceID]
    public let issuedAt: Date
    public let signature: Data

    public static func issue(
        for member: ParticipantID, listing devices: some Sequence<DeviceID>, by device: DeviceKeys, at instant: Date
    ) throws -> Deathmark {
        let listed = Array(Set(devices)).sorted { $0.rawValue.lexicographicallyPrecedes($1.rawValue) }
        let payload = signingPayload(member: member, issuedBy: device.id, devices: listed, issuedAt: instant)
        return Deathmark(
            member: member, issuedBy: device.id, devices: listed, issuedAt: instant,
            signature: try device.sign(payload))
    }

    static func signingPayload(member: ParticipantID, issuedBy: DeviceID, devices: [DeviceID], issuedAt: Date) -> Data {
        CanonicalBytes.payload(
            domain: Domain.deathmark,
            fields: [member.rawValue, issuedBy.rawValue, CanonicalBytes.timestamp(issuedAt)] + devices.map(\.rawValue))
    }

    public func isSigned(by registry: DeviceRegistry, storedAt: Date) -> Bool {
        guard registry.counts(issuedBy, storedAt: storedAt), let key = registry.signingKey(for: issuedBy) else {
            return false
        }
        let payload = Self.signingPayload(member: member, issuedBy: issuedBy, devices: devices, issuedAt: issuedAt)
        return (try? DeviceKeys.isValidSignature(signature, for: payload, publicKey: key)) == true
    }

    public func sealed(for identity: Identity) throws -> Data {
        try ChaChaPoly.seal(
            try JSONEncoder().encode(self), using: Self.key(for: identity),
            authenticating: Self.context(identity.id)
        ).combined
    }

    public static func open(_ sealed: Data, for identity: Identity) -> Deathmark? {
        guard let box = try? ChaChaPoly.SealedBox(combined: sealed),
            let plain = try? ChaChaPoly.open(box, using: key(for: identity), authenticating: context(identity.id)),
            let mark = try? JSONDecoder().decode(Deathmark.self, from: plain),
            mark.member == identity.id
        else { return nil }
        return mark
    }

    public static func sealedCheckOff(_ device: DeviceID, for identity: Identity) throws -> Data {
        try ChaChaPoly.seal(device.rawValue, using: key(for: identity), authenticating: context(identity.id)).combined
    }

    private static func context(_ member: ParticipantID) -> Data {
        CanonicalBytes.payload(domain: Domain.deathmark, fields: [member.rawValue])
    }

    private static func key(for identity: Identity) -> SymmetricKey {
        SymmetricKey(
            data: HKDF<SHA256>.deriveKey(
                inputKeyMaterial: SymmetricKey(data: identity.signingSeed + identity.agreementSeed),
                salt: Data(Domain.deathmark.utf8),
                info: CanonicalBytes.payload(domain: Domain.deathmark, fields: [identity.id.rawValue]),
                outputByteCount: 32))
    }
}

public struct PostedDeathmark: Sendable {
    public let sealed: Data
    public let storedAt: Date?
    public let checkedOff: Set<DeviceID>

    public init(sealed: Data, storedAt: Date?, checkedOff: Set<DeviceID>) {
        self.sealed = sealed
        self.storedAt = storedAt
        self.checkedOff = checkedOff
    }
}

public protocol DeathmarkBoard: Sendable {
    func read() async throws -> PostedDeathmark?
    func post(_ sealed: Data) async throws
    func checkOff(_ device: DeviceID, sealed: Data) async throws
    func clear() async throws
}
