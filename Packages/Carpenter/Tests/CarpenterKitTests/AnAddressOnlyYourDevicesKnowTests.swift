import CarpenterKitTesting
import CryptoKit
import Foundation
import Testing

@testable import CarpenterKit

@Suite("An address only your devices know")
struct AnAddressOnlyYourDevicesKnowTests {
    private let t0 = Date(timeIntervalSince1970: 1_786_635_000)

    private struct Household {
        var registry: DeviceRegistry
        let identity: Identity
        let phone: DeviceKeys
        let tablet: DeviceKeys
        let thief: DeviceKeys
    }

    private func household() throws -> Household {
        let identity = Identity.generate()
        let (phone, tablet, thief) = (DeviceKeys.generate(), DeviceKeys.generate(), DeviceKeys.generate())
        var registry = DeviceRegistry(identity: identity.publicKeys)
        try registry.admit(DeviceCertificate.recovered(for: phone, by: identity, at: t0), storedAt: t0)
        try registry.admit(
            DeviceCertificate.issue(for: tablet, by: identity, at: t0 + 10, approvedBy: phone), storedAt: t0 + 10)
        try registry.admit(
            DeviceCertificate.issue(for: thief, by: identity, at: t0 + 20, approvedBy: phone), storedAt: t0 + 20)
        try registry.revoke(
            DeviceRevocation.issue(for: thief.id, by: identity, at: t0 + 30, from: phone), storedAt: t0 + 30)
        return Household(registry: registry, identity: identity, phone: phone, tablet: tablet, thief: thief)
    }

    private func recipients(of house: Household) -> [DeviceRecipient] {
        [house.phone, house.tablet].map { DeviceRecipient(device: $0.id, agreementKey: $0.agreementPublicKey) }
    }

    @Test("Nobody with a salt means the secret every build has always made")
    func noSaltIsTheOldSecret() throws {
        let (alice, bob) = (Identity.generate(), Identity.generate())
        #expect(
            try PairwiseSecret.derive(mine: alice, theirs: bob.publicKeys, mySalt: nil, theirSalt: nil)
                == PairwiseSecret.derive(mine: alice, theirs: bob.publicKeys))
    }

    @Test("Both people make the same secret from the same two salts, and any change makes another")
    func bothSidesAgree() throws {
        let (alice, bob) = (Identity.generate(), Identity.generate())
        let (a, b) = (AddressSalt.fresh(after: 0), AddressSalt.fresh(after: 0))
        let hers = try PairwiseSecret.derive(mine: alice, theirs: bob.publicKeys, mySalt: a, theirSalt: b)
        let his = try PairwiseSecret.derive(mine: bob, theirs: alice.publicKeys, mySalt: b, theirSalt: a)
        #expect(hers == his, "the two people worked out different secrets from the same salts")

        let old = try PairwiseSecret.derive(mine: alice, theirs: bob.publicKeys)
        let onlyHers = try PairwiseSecret.derive(mine: alice, theirs: bob.publicKeys, mySalt: a, theirSalt: nil)
        let swapped = try PairwiseSecret.derive(mine: alice, theirs: bob.publicKeys, mySalt: b, theirSalt: a)
        let another = try PairwiseSecret.derive(
            mine: alice, theirs: bob.publicKeys, mySalt: AddressSalt.fresh(after: 1), theirSalt: b)
        #expect(Set([hers, old, onlyHers, swapped, another]).count == 5, "two different salt pairs made one secret")
    }

    @Test("The salted secret is made exactly as written down, so a later build makes the same one")
    func theLayoutIsPinned() throws {
        let (alice, bob) = (Identity.generate(), Identity.generate())
        let salt = AddressSalt(number: 3, bytes: Data(repeating: 0x5A, count: 32))
        let shared = try alice.sharedSecret(with: bob.publicKeys)
        let ids = [alice.id.rawValue, bob.id.rawValue]
        let aliceFirst = ids[0].lexicographicallyPrecedes(ids[1])
        var fields: [Data] = []
        for (id, saltBytes) in aliceFirst ? [(ids[0], salt.bytes), (ids[1], Data())] : [(ids[1], Data()), (ids[0], salt.bytes)] {
            fields.append(id)
            fields.append(saltBytes)
        }
        let expected = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: Data("carpenter.pairwise-address.v1".utf8),
            sharedInfo: CanonicalBytes.payload(domain: "carpenter.pairwise-address.v1", fields: fields),
            outputByteCount: 32
        ).withUnsafeBytes { Data($0) }
        #expect(
            try PairwiseSecret.derive(mine: alice, theirs: bob.publicKeys, mySalt: salt, theirSalt: nil).material
                == expected)
    }

    @Test("An announcement opens on each device it was sealed for, and says the salt it carries")
    func itOpensForTheirDevices() throws {
        let alice = try household()
        let bob = try household()
        let salt = AddressSalt.fresh(after: 0)
        let announcement = try AddressAnnouncement.make(
            salt, from: alice.identity.id, by: alice.phone, to: bob.identity.id, devices: recipients(of: bob))
        for device in [bob.phone, bob.tablet] {
            #expect(
                announcement.open(as: device, of: bob.identity.id, from: alice.registry, storedAt: t0 + 40) == salt)
        }
        #expect(
            announcement.open(as: bob.thief, of: bob.identity.id, from: alice.registry, storedAt: t0 + 40) == nil,
            "a device the announcement was not sealed for opened it")
    }

    @Test("A removed device's announcement never counts, even one it signed before it was removed")
    func removedDevicesAnnounceNothing() throws {
        let alice = try household()
        let bob = try household()
        let salt = AddressSalt.fresh(after: 0)
        let fromThief = try AddressAnnouncement.make(
            salt, from: alice.identity.id, by: alice.thief, to: bob.identity.id, devices: recipients(of: bob))
        #expect(
            fromThief.open(as: bob.phone, of: bob.identity.id, from: alice.registry, storedAt: t0 + 25) == salt,
            "precondition: while it counted, its announcement opened")
        #expect(
            fromThief.open(as: bob.phone, of: bob.identity.id, from: alice.registry, storedAt: t0 + 40) == nil,
            "an announcement put in iCloud after its device was removed counted")
    }

    @Test("An announcement for somebody else, from somebody else, or changed on the way does not open")
    func wrongOrChangedAnnouncementsDoNotOpen() throws {
        let alice = try household()
        let bob = try household()
        let carol = try household()
        let salt = AddressSalt.fresh(after: 0)
        let real = try AddressAnnouncement.make(
            salt, from: alice.identity.id, by: alice.phone, to: bob.identity.id, devices: recipients(of: bob))

        #expect(
            real.open(as: bob.phone, of: carol.identity.id, from: alice.registry, storedAt: t0 + 40) == nil,
            "an announcement opened for a person it was not addressed to")
        #expect(
            real.open(as: bob.phone, of: bob.identity.id, from: carol.registry, storedAt: t0 + 40) == nil,
            "an announcement counted as somebody else's")

        let renumbered = AddressAnnouncement(
            member: real.member, recipient: real.recipient, number: real.number + 1, seals: real.seals,
            device: real.device, signature: real.signature)
        let readdressed = AddressAnnouncement(
            member: real.member, recipient: carol.identity.id, number: real.number, seals: real.seals,
            device: real.device, signature: real.signature)
        let impostor = try AddressAnnouncement.make(
            salt, from: alice.identity.id, by: carol.phone, to: bob.identity.id, devices: recipients(of: bob))
        let resealed = AddressAnnouncement(
            member: real.member, recipient: real.recipient, number: real.number,
            seals: try recipients(of: bob).map {
                try DeviceSeal.seal(
                    Data(repeating: 1, count: 32), to: $0,
                    context: AddressAnnouncement.context(
                        member: real.member, recipient: real.recipient, number: real.number))
            },
            device: real.device, signature: real.signature)
        for changed in [renumbered, readdressed, impostor, resealed] {
            #expect(
                changed.open(as: bob.phone, of: bob.identity.id, from: alice.registry, storedAt: t0 + 40) == nil,
                "an announcement changed on the way, or signed by a device that is not hers, opened")
        }
    }

    @Test("A salt of the wrong size is refused")
    func wrongSizedSaltsAreRefused() throws {
        let alice = try household()
        let bob = try household()
        let short = AddressSalt(number: 1, bytes: Data(repeating: 7, count: 16))
        let announcement = try AddressAnnouncement.make(
            short, from: alice.identity.id, by: alice.phone, to: bob.identity.id, devices: recipients(of: bob))
        #expect(announcement.open(as: bob.phone, of: bob.identity.id, from: alice.registry, storedAt: t0 + 40) == nil)
    }

    @Test("A salt's number stops at the top rather than wrapping back to the start")
    func numbersSaturate() {
        #expect(AddressSalt.fresh(after: .max).number == .max)
        #expect(AddressSalt.fresh(after: 4).number == 5)
    }
}
