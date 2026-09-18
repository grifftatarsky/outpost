import Foundation
import Testing

@testable import CarpenterKit

@Suite struct OutpostAccessTests {
    private func person(_ seed: UInt8) -> ParticipantID {
        ParticipantID(rawValue: Data(repeating: seed, count: 32))
    }
    private func stamp(_ at: TimeInterval, device: UInt8 = 1) -> OrganisationStamp {
        OrganisationStamp(at: Date(timeIntervalSince1970: at), device: DeviceID(rawValue: Data([device])))
    }
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("Nobody can read an Outpost that has granted nothing")
    func defaultsToNobody() {
        let access = OutpostAccess()
        #expect(access.allows(person(1), at: now) == false)
        #expect(access.audience(at: now).isEmpty)
    }

    @Test("A grant with no date opens the whole history")
    func grantWithoutDate() {
        var access = OutpostAccess()
        access.allow(person(1), stamp: stamp(10))
        #expect(access.allows(person(1), at: now))
        #expect(access.allows(person(1), at: now.addingTimeInterval(-86_400 * 365)))
    }

    @Test("A grant from a date does not open what came before it")
    func grantFromADate() {
        var access = OutpostAccess()
        access.allow(person(1), from: now, stamp: stamp(10))
        #expect(access.allows(person(1), at: now.addingTimeInterval(1)))
        #expect(access.allows(person(1), at: now) == true, "the boundary instant is included")
        #expect(access.allows(person(1), at: now.addingTimeInterval(-1)) == false)
    }

    @Test("Revoking closes everything, including what was readable before")
    func revocationIsTotal() {
        var access = OutpostAccess()
        access.allow(person(1), stamp: stamp(10))
        access.revoke(person(1), stamp: stamp(20))
        #expect(access.allows(person(1), at: now) == false)
        #expect(access.audience(at: now).isEmpty)
    }

    @Test("A revocation survives a merge with a device that still has the grant")
    func revocationBeatsStaleGrant() {
        var revoked = OutpostAccess()
        revoked.allow(person(1), stamp: stamp(10))
        revoked.revoke(person(1), stamp: stamp(20))

        var stale = OutpostAccess()
        stale.allow(person(1), stamp: stamp(10))

        #expect(revoked.merged(with: stale).allows(person(1), at: now) == false)
        #expect(stale.merged(with: revoked).allows(person(1), at: now) == false)
    }

    @Test("Two devices granting different people keep both grants")
    func mergeIsPerPerson() {
        var phone = OutpostAccess()
        phone.allow(person(1), stamp: stamp(10, device: 1))
        var mac = OutpostAccess()
        mac.allow(person(2), stamp: stamp(11, device: 2))

        let merged = phone.merged(with: mac)
        #expect(merged.allows(person(1), at: now))
        #expect(merged.allows(person(2), at: now))
        #expect(merged.audience(at: now).count == 2)
    }

    @Test("Merging is order-independent for the same pair of edits")
    func mergeCommutes() {
        var a = OutpostAccess()
        a.allow(person(1), stamp: stamp(10, device: 1))
        a.allow(person(2), stamp: stamp(30, device: 1))
        var b = OutpostAccess()
        b.revoke(person(1), stamp: stamp(20, device: 2))

        #expect(a.merged(with: b).granted == b.merged(with: a).granted)
    }

    @Test("An inherited grant reads like any other but says where it came from")
    func inheritedGrantsAreMarked() {
        var access = OutpostAccess()
        access.allow(person(1), origin: .inherited, stamp: stamp(10))
        access.allow(person(2), stamp: stamp(10))

        #expect(access.allows(person(1), at: now))
        #expect(access.grant(for: person(1))?.origin == .inherited)
        #expect(access.grant(for: person(2))?.origin == .chosen)
    }

    @Test("The audience is exactly who can read something written now")
    func audienceCounts() {
        var access = OutpostAccess()
        access.allow(person(1), stamp: stamp(10))
        access.allow(person(2), from: now.addingTimeInterval(86_400), stamp: stamp(10))
        access.allow(person(3), stamp: stamp(10))
        access.revoke(person(3), stamp: stamp(20))

        #expect(access.audience(at: now) == [person(1)], "future grants and revocations both excluded")
    }
}
