import CarpenterKitTesting
import CryptoKit
import Foundation
import Testing

@testable import CarpenterKit

@Suite("A key handed to a device is sealed with X-Wing", .tags(.crypto))
struct AKeyHandedToADeviceIsSealedWithXWingTests {
    private let issued = Date(timeIntervalSince1970: 1_786_635_000)

    private func context(_ room: RoomID, _ epoch: UInt64, purpose: String = Domain.epochGrant) -> Data {
        CanonicalBytes.payload(
            domain: purpose, fields: [room.canonicalBytes, EpochNumber(rawValue: epoch).canonicalBytes])
    }

    private func to(_ device: DeviceKeys) -> DeviceRecipient {
        DeviceRecipient(device: device.id, sealingKey: device.sealingPublicKey)
    }

    @Test("A seal opens on the device it was made for, under the binding it was made with")
    func aSealOpensWhereItWasSent() throws {
        let (phone, tablet) = (DeviceKeys.generate(), DeviceKeys.generate())
        let room = RoomID()
        let secret = Data((0..<32).map { UInt8($0) })

        for device in [phone, tablet] {
            let seal = try DeviceSeal.seal(secret, to: to(device), context: context(room, 3))
            #expect(try seal.open(with: device, context: context(room, 3)) == secret)
        }
    }

    @Test("A seal does not open on another device, even when it is relabelled with that device's name")
    func anotherDeviceCannotOpen() throws {
        let (phone, removed) = (DeviceKeys.generate(), DeviceKeys.generate())
        let room = RoomID()
        let seal = try DeviceSeal.seal(Data(repeating: 4, count: 32), to: to(phone), context: context(room, 1))

        #expect(throws: CryptoError.openFailed) { try seal.open(with: removed, context: context(room, 1)) }
        let relabelled = DeviceSeal(device: removed.id, encapsulated: seal.encapsulated, sealed: seal.sealed)
        #expect(throws: CryptoError.openFailed) { try relabelled.open(with: removed, context: context(room, 1)) }
    }

    @Test("A seal made for one room, epoch, purpose or device does not open under another")
    func theBindingIsChecked() throws {
        let phone = DeviceKeys.generate()
        let (room, elsewhere) = (RoomID(), RoomID())
        let seal = try DeviceSeal.seal(Data(repeating: 5, count: 32), to: to(phone), context: context(room, 2))

        for wrong in [
            context(elsewhere, 2), context(room, 3),
            context(room, 2, purpose: Domain.addressAnnouncement), Data(),
        ] {
            #expect(throws: CryptoError.openFailed) { try seal.open(with: phone, context: wrong) }
        }

        let elsewhereNamed = DeviceRecipient(device: DeviceKeys.generate().id, sealingKey: phone.sealingPublicKey)
        let namedForAnother = try DeviceSeal.seal(
            Data(repeating: 5, count: 32), to: elsewhereNamed, context: context(room, 2))
        let claimed = DeviceSeal(
            device: phone.id, encapsulated: namedForAnother.encapsulated, sealed: namedForAnother.sealed)
        #expect(throws: CryptoError.openFailed, "a seal made out to another device opened on this one") {
            try claimed.open(with: phone, context: context(room, 2))
        }
    }

    @Test("A seal whose encapsulation or ciphertext was changed does not open")
    func aTamperedSealDoesNotOpen() throws {
        let phone = DeviceKeys.generate()
        let room = RoomID()
        let seal = try DeviceSeal.seal(Data(repeating: 6, count: 32), to: to(phone), context: context(room, 1))

        func flipped(_ data: Data, at index: Int) -> Data {
            var copy = data
            copy[copy.startIndex + index] ^= 0x01
            return copy
        }
        let last = seal.sealed.count - 1
        let tampered = [
            DeviceSeal(device: phone.id, encapsulated: flipped(seal.encapsulated, at: 0), sealed: seal.sealed),
            DeviceSeal(device: phone.id, encapsulated: flipped(seal.encapsulated, at: 1_119), sealed: seal.sealed),
            DeviceSeal(device: phone.id, encapsulated: seal.encapsulated, sealed: flipped(seal.sealed, at: 0)),
            DeviceSeal(device: phone.id, encapsulated: seal.encapsulated, sealed: flipped(seal.sealed, at: last)),
            DeviceSeal(device: phone.id, encapsulated: seal.encapsulated, sealed: Data(seal.sealed.dropLast())),
            DeviceSeal(device: phone.id, encapsulated: Data(seal.encapsulated.dropLast()), sealed: seal.sealed),
        ]
        for changed in tampered {
            #expect(throws: CryptoError.openFailed) { try changed.open(with: phone, context: context(room, 1)) }
        }
    }

    @Test("The seal is X-Wing: a 1,216-byte key from the device's own signing seed, and a 1,120-byte encapsulation")
    func theSealIsXWing() throws {
        let phone = DeviceKeys.generate()
        let seal = try DeviceSeal.seal(Data(repeating: 7, count: 32), to: to(phone), context: Data("c".utf8))

        #expect(phone.sealingPublicKey.count == 1_216)
        #expect(seal.encapsulated.count == DeviceSeal.encapsulatedByteCount)
        #expect(DeviceSeal.encapsulatedByteCount == 1_120)
        #expect(seal.sealed.count == 32 + 16, "the AEAD is not AES-256-GCM with its 16-byte tag")
        #expect(try DeviceKeys(signingSeed: phone.signingSeed).sealingPublicKey == phone.sealingPublicKey)
        #expect(DeviceKeys.generate().sealingPublicKey != phone.sealingPublicKey)

        var recipient = try HPKE.Recipient(
            privateKey: phone.sealingKey, ciphersuite: .XWingMLKEM768X25519_SHA256_AES_GCM_256,
            info: CanonicalBytes.payload(
                domain: "carpenter.device-seal.v2", fields: [phone.id.rawValue, Data("c".utf8)]),
            encapsulatedKey: seal.encapsulated)
        #expect(try recipient.open(seal.sealed) == Data(repeating: 7, count: 32))
    }

    private struct OldSeal: Codable {
        let device: DeviceID
        let ephemeral: Data
        let sealed: Data
    }

    private func oldFormSeal(
        _ plaintext: Data, to device: DeviceKeys, context: Data
    ) throws -> (Data, Curve25519.KeyAgreement.PrivateKey) {
        let seed = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: device.signingSeed),
            salt: Data("carpenter.device-agreement.v1".utf8), info: Data("carpenter.device-agreement.v1".utf8),
            outputByteCount: 32)
        let agreement = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: seed.withUnsafeBytes { Data($0) })
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: agreement.publicKey)
        let key = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: Data("carpenter.device-seal.v1".utf8),
            sharedInfo: CanonicalBytes.payload(
                domain: "carpenter.device-seal.v1",
                fields: [device.id.rawValue, ephemeral.publicKey.rawRepresentation, context]),
            outputByteCount: 32)
        let box = try ChaChaPoly.seal(plaintext, using: key, authenticating: context)
        let json = try JSONEncoder().encode(
            OldSeal(device: device.id, ephemeral: ephemeral.publicKey.rawRepresentation, sealed: box.combined))
        return (json, agreement)
    }

    @Test("A seal in the old X25519 form is refused, and the grant that carries it still decodes")
    func anOldFormSealIsRefused() throws {
        let phone = DeviceKeys.generate()
        let (sender, member) = (Identity.generate(), Identity.generate())
        let pairwise = try PairwiseSecret.derive(mine: sender, theirs: member.publicKeys)
        let theirs = try PairwiseSecret.derive(mine: member, theirs: sender.publicKeys)
        let room = RoomID()
        let grant = try EpochGrant.issue(
            EpochSecret.random(), at: .initial, in: room, link: nil, to: pairwise, devices: [to(phone)])
        let grantContext = context(room, EpochNumber.initial.rawValue)
        let wrapped = try pairwise.wrap(Data(repeating: 8, count: 32), context: grantContext)

        let (oldJSON, agreement) = try oldFormSeal(wrapped, to: phone, context: grantContext)
        let old = try JSONDecoder().decode(OldSeal.self, from: oldJSON)
        let shared = try agreement.sharedSecretFromKeyAgreement(
            with: try Curve25519.KeyAgreement.PublicKey(rawRepresentation: old.ephemeral))
        let oldKey = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: Data("carpenter.device-seal.v1".utf8),
            sharedInfo: CanonicalBytes.payload(
                domain: "carpenter.device-seal.v1", fields: [phone.id.rawValue, old.ephemeral, grantContext]),
            outputByteCount: 32)
        #expect(
            try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: old.sealed), using: oldKey, authenticating: grantContext)
                == wrapped,
            "precondition: this is a genuine old-form seal for the phone")

        let decoded = try JSONDecoder().decode(DeviceSeal.self, from: oldJSON)
        #expect(decoded.encapsulated.isEmpty)
        #expect(throws: CryptoError.openFailed) { try decoded.open(with: phone, context: grantContext) }

        let carried = try JSONEncoder().encode([ForwardedGrant(from: sender.id, grant: grant)])
        var waiting = try #require(try JSONSerialization.jsonObject(with: carried) as? [[String: Any]])
        var held = try #require(waiting[0]["grant"] as? [String: Any])
        held["sealedFor"] = [try #require(try JSONSerialization.jsonObject(with: oldJSON) as? [String: Any])]
        waiting[0]["grant"] = held
        let stored = try JSONSerialization.data(withJSONObject: waiting)

        let reopened = try JSONDecoder().decode([ForwardedGrant].self, from: stored)
        #expect(reopened.count == 1, "one old seal made everything stored beside it unreadable")
        #expect(throws: CryptoError.openFailed) { try reopened[0].grant.open(with: theirs, as: phone) }
    }

    @Test("A seal larger than any record can hold is refused before anything opens it")
    func anOversizedSealIsRefused() throws {
        let phone = DeviceKeys.generate()
        func seal(encapsulated: Int, sealed: Int) throws -> DeviceSeal {
            let json = try JSONEncoder().encode(
                DeviceSeal(
                    device: phone.id, encapsulated: Data(count: encapsulated), sealed: Data(count: sealed)))
            return try JSONDecoder().decode(DeviceSeal.self, from: json)
        }
        _ = try seal(encapsulated: 1_120, sealed: 48)
        _ = try seal(encapsulated: 1_120, sealed: MailboxRules.recordByteCeiling)
        #expect(throws: DecodingError.self) { try seal(encapsulated: 1_121, sealed: 48) }
        #expect(throws: DecodingError.self) {
            try seal(encapsulated: 1_120, sealed: MailboxRules.recordByteCeiling + 1)
        }
    }

    @Test("A grant is sealed with X-Wing for each device and signed over every encapsulation")
    func aGrantIsSignedOverItsSeals() throws {
        let (sender, member) = (Identity.generate(), Identity.generate())
        let sendingPhone = DeviceKeys.generate()
        let (phone, tablet) = (DeviceKeys.generate(), DeviceKeys.generate())
        var registry = DeviceRegistry(identity: sender.publicKeys)
        try registry.admit(try DeviceCertificate.recovered(for: sendingPhone, by: sender, at: issued))
        let pairwise = try PairwiseSecret.derive(mine: sender, theirs: member.publicKeys)

        let grant = try EpochGrant.issue(
            EpochSecret.random(), at: .initial, in: RoomID(), link: nil, to: pairwise, devices: [to(phone), to(tablet)]
        ).signed(by: sendingPhone, from: sender.id, to: member.id)
        #expect(grant.sealedFor.allSatisfy { $0.encapsulated.count == DeviceSeal.encapsulatedByteCount })
        #expect(grant.isSigned(from: sender.id, to: member.id, by: registry, storedAt: issued + 60))

        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(grant)) as? [String: Any])
        var seals = try #require(json["sealedFor"] as? [[String: Any]])
        let other = try DeviceSeal.seal(Data(repeating: 1, count: 60), to: to(phone), context: Data())
        seals[0]["encapsulated"] = other.encapsulated.base64EncodedString()
        json["sealedFor"] = seals
        let swapped = try JSONDecoder().decode(EpochGrant.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(
            !swapped.isSigned(from: sender.id, to: member.id, by: registry, storedAt: issued + 60),
            "a grant whose encapsulation was swapped still carried its sender's signature")
    }

    @Test("A new device's request names its X-Wing key, and the code both devices show covers it")
    func theRequestCarriesTheSealingKey() throws {
        let device = DeviceKeys.generate()
        let request = DeviceRequest(for: device)
        #expect(request.sealingKey == device.sealingPublicKey)
        #expect(DeviceRequest(record: try request.record()) == request)

        let substituted = DeviceRequest(
            devicePublicKey: device.publicKey, sealingKey: DeviceKeys.generate().sealingPublicKey)
        #expect(substituted.code != request.code, "swapping the key a new device is sealed to left the code unchanged")

        let cut = DeviceRequest(devicePublicKey: device.publicKey, sealingKey: Data(device.sealingPublicKey.prefix(32)))
        #expect(DeviceRequest(record: try cut.record()) == nil, "a request naming an X25519-sized key was taken")

        let old = SiblingRecord(
            name: SiblingRecord.Name(writer: device.id, kind: .request),
            sealed: SealedSiblingFeed(
                ciphertext: try JSONSerialization.data(withJSONObject: [
                    "devicePublicKey": device.publicKey.base64EncodedString(),
                    "agreementKey": Data(repeating: 9, count: 32).base64EncodedString(),
                ])))
        #expect(DeviceRequest(record: old) == nil, "a request in the old form was taken")
    }

    @Test("An approval opens only on the device that asked for it, sealed with X-Wing")
    func anApprovalOpensOnlyOnItsDevice() throws {
        let identity = Identity.generate()
        let (approver, newcomer) = (DeviceKeys.generate(), DeviceKeys.generate())
        let approval = DeviceApproval(identity: identity, certificates: [], revocations: [])
        let record = try approval.record(from: approver.id, to: DeviceRequest(for: newcomer))

        let seal = try JSONDecoder().decode(DeviceSeal.self, from: record.sealed.ciphertext)
        #expect(seal.encapsulated.count == DeviceSeal.encapsulatedByteCount)
        #expect(try DeviceApproval(record: record, opening: newcomer).identity().id == identity.id)

        let impostor = try DeviceKeys(signingSeed: DeviceKeys.generate().signingSeed)
        #expect(throws: CryptoError.openFailed) { try DeviceApproval(record: record, opening: impostor) }
    }
}
