import CryptoKit
import Foundation

public struct AddressSalt: Hashable, Sendable, Codable {
    public static let width = 32

    public let number: UInt32
    public let bytes: Data

    public init(number: UInt32, bytes: Data) {
        self.number = number
        self.bytes = bytes
    }

    public static func fresh(after previous: UInt32) -> AddressSalt {
        AddressSalt(
            number: previous == .max ? .max : previous + 1,
            bytes: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
    }
}

extension PairwiseSecret {
    public static func derive(
        mine: Identity, theirs: IdentityPublicKeys, mySalt: AddressSalt?, theirSalt: AddressSalt?
    ) throws -> PairwiseSecret {
        guard mySalt != nil || theirSalt != nil else { return try derive(mine: mine, theirs: theirs) }
        let shared = try mine.sharedSecret(with: theirs)
        let me = (id: mine.id.rawValue, salt: mySalt?.bytes ?? Data())
        let them = (id: theirs.participantID.rawValue, salt: theirSalt?.bytes ?? Data())
        let (first, second) = me.id.lexicographicallyPrecedes(them.id) ? (me, them) : (them, me)
        let key = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(Domain.pairwiseAddress.utf8),
            sharedInfo: CanonicalBytes.payload(
                domain: Domain.pairwiseAddress, fields: [first.id, first.salt, second.id, second.salt]),
            outputByteCount: 32)
        return PairwiseSecret(material: key.withUnsafeBytes { Data($0) })
    }
}

public struct AddressAnnouncement: Hashable, Sendable, Codable {
    public let member: ParticipantID
    public let recipient: ParticipantID
    public let number: UInt32
    public let seals: [DeviceSeal]
    public let device: DeviceID
    public let signature: Data

    public static func make(
        _ salt: AddressSalt, from member: ParticipantID, by device: DeviceKeys, to recipient: ParticipantID,
        devices: [DeviceRecipient]
    ) throws -> AddressAnnouncement {
        let context = context(member: member, recipient: recipient, number: salt.number)
        let seals = try devices.map { try DeviceSeal.seal(salt.bytes, to: $0, context: context) }
        let payload = signingPayload(
            member: member, recipient: recipient, number: salt.number, seals: seals, device: device.id)
        return AddressAnnouncement(
            member: member, recipient: recipient, number: salt.number, seals: seals, device: device.id,
            signature: try device.sign(payload))
    }

    public func open(
        as device: DeviceKeys, of recipient: ParticipantID, from registry: DeviceRegistry, storedAt: Date
    ) -> AddressSalt? {
        guard self.recipient == recipient, member == registry.identity.participantID,
            registry.counts(self.device, storedAt: storedAt),
            let key = registry.signingKey(for: self.device),
            (try? DeviceKeys.isValidSignature(
                signature,
                for: Self.signingPayload(
                    member: member, recipient: recipient, number: number, seals: seals, device: self.device),
                publicKey: key)) == true,
            let seal = seals.first(where: { $0.device == device.id }),
            let bytes = try? seal.open(
                with: device, context: Self.context(member: member, recipient: recipient, number: number)),
            bytes.count == AddressSalt.width
        else { return nil }
        return AddressSalt(number: number, bytes: bytes)
    }

    static func context(member: ParticipantID, recipient: ParticipantID, number: UInt32) -> Data {
        CanonicalBytes.payload(
            domain: Domain.addressAnnouncement,
            fields: [member.rawValue, recipient.rawValue, CanonicalBytes.sequence(UInt64(number))])
    }

    static func signingPayload(
        member: ParticipantID, recipient: ParticipantID, number: UInt32, seals: [DeviceSeal], device: DeviceID
    ) -> Data {
        var fields = [member.rawValue, recipient.rawValue, CanonicalBytes.sequence(UInt64(number)), device.rawValue]
        for seal in seals.sorted(by: { $0.device.rawValue.lexicographicallyPrecedes($1.device.rawValue) }) {
            fields.append(contentsOf: [seal.device.rawValue, seal.ephemeral, seal.sealed])
        }
        return CanonicalBytes.payload(domain: Domain.addressAnnouncementSignature, fields: fields)
    }
}
