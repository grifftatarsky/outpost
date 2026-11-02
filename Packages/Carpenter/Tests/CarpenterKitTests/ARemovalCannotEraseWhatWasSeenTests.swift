import CarpenterKit
import Foundation
import Testing

@Suite("A removal cannot erase what the member's devices had already seen")
struct ARemovalCannotEraseWhatWasSeenTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let identity = Identity.generate()
    private let phone = DeviceKeys.generate()
    private let stolen = DeviceKeys.generate()
    private let tablet = DeviceKeys.generate()
    private let chain = EpochChain.create(room: RoomID()).chain

    private func friend(with devices: [DeviceKeys] = []) throws -> Replica {
        var replica = Replica()
        replica.introduce(identity.publicKeys)
        try replica.admit(DeviceCertificate.recovered(for: phone, by: identity, at: start), storedAt: start)
        for (index, device) in ([stolen, tablet] + devices).enumerated() {
            let at = start + 10 + Double(index)
            try replica.admit(DeviceCertificate.issue(for: device, by: identity, at: at, approvedBy: phone), storedAt: at)
        }
        return replica
    }

    private func feed(of device: DeviceKeys, _ count: Int, from: Entry? = nil, seeing: VectorClock = VectorClock())
        throws -> [Entry]
    {
        var head = from
        var written: [Entry] = []
        for _ in 0..<count {
            var clock = seeing
            if let head { clock.observe(head.feedKey, seq: head.seq) }
            let entry = try Entry.append(
                to: head, author: identity.id, device: device, clock: clock,
                wallTime: start + 100 + Double(head?.seq ?? 0), room: nil,
                payload: try Payload.post("\(head?.seq ?? 0)"), at: .initial, sealedWith: chain)
            head = entry
            written.append(entry)
        }
        return written
    }

    private func clock(seeing entry: Entry) -> VectorClock {
        var clock = VectorClock()
        clock.observe(entry.feedKey, seq: entry.seq)
        return clock
    }

    private func removal(
        of device: DeviceKeys, by remover: DeviceKeys, at top: Entry?, dated: Date? = nil
    ) throws -> DeviceRevocation {
        try DeviceRevocation.issue(
            for: device.id, by: identity, at: dated ?? start + 1000, from: remover,
            cutoff: dated == nil ? top?.seq ?? 0 : nil, head: dated == nil ? top?.hash : nil)
    }

    private func held(_ replica: Replica, of device: DeviceKeys) -> [UInt64] {
        replica.allEntries.filter { $0.device == device.id }.map(\.seq).sorted()
    }

    @Test("A stolen phone's removal with a cutoff of 0 keeps what its own entries showed it had seen")
    func theRemoversOwnEntriesVouch() throws {
        var replica = try friend()
        let words = try feed(of: phone, 5)
        let seen = try feed(of: stolen, 1, seeing: clock(seeing: words[4]))
        for entry in words + seen { try replica.integrate(entry) }

        try replica.revoke(try removal(of: phone, by: stolen, at: nil), storedAt: start + 1000)

        #expect(held(replica, of: phone) == [1, 2, 3, 4, 5], "the removal erased what its own remover had seen")
        let next = try feed(of: phone, 1, from: words[4])
        #expect(throws: (any Error).self, "an entry nobody had seen got past a removal") {
            try replica.integrate(next[0])
        }
    }

    @Test("A removal dated before everything keeps what its remover had seen")
    func aBackdatedRemovalKeepsWhatWasSeen() throws {
        var replica = try friend()
        let words = try feed(of: phone, 5)
        let seen = try feed(of: stolen, 1, seeing: clock(seeing: words[4]))
        for entry in words + seen { try replica.integrate(entry) }

        try replica.revoke(try removal(of: phone, by: stolen, at: nil, dated: .distantPast), storedAt: start + 1000)

        #expect(held(replica, of: phone) == [1, 2, 3, 4, 5], "a removal dated at the beginning of time erased history")
    }

    @Test("Another device that still counts vouches for what it had seen, when the remover wrote nothing")
    func aCountingDeviceVouches() throws {
        var replica = try friend()
        let words = try feed(of: phone, 5)
        let seen = try feed(of: tablet, 1, seeing: clock(seeing: words[3]))
        for entry in words + seen { try replica.integrate(entry) }

        try replica.revoke(try removal(of: phone, by: stolen, at: nil), storedAt: start + 1000)

        #expect(held(replica, of: phone) == [1, 2, 3, 4], "what another of the member's devices had seen was erased")
    }

    @Test("An honest removal still drops what no device of the member had seen")
    func anHonestRemovalStillCuts() throws {
        var replica = try friend()
        let words = try feed(of: stolen, 5)
        let seen = try feed(of: tablet, 1, seeing: clock(seeing: words[1]))
        for entry in words + seen { try replica.integrate(entry) }

        try replica.revoke(try removal(of: stolen, by: phone, at: words[2]), storedAt: start + 1000)

        #expect(held(replica, of: stolen) == [1, 2, 3])
        #expect(replica.registry(for: identity.id)?.standing(of: stolen.id)?.head == words[2].hash)
    }

    @Test("Once a device is removed, what it said it had seen stops keeping anything")
    func aRemovedWitnessStopsVouching() throws {
        let accomplice = DeviceKeys.generate()
        var replica = try friend(with: [accomplice])
        let words = try feed(of: stolen, 9)
        let claim = try feed(of: accomplice, 1, seeing: clock(seeing: words[8]))
        for entry in words + claim { try replica.integrate(entry) }

        try replica.revoke(try removal(of: stolen, by: phone, at: words[4]), storedAt: start + 1000)
        #expect(held(replica, of: stolen) == Array(1...9), "precondition: a device that counts vouches")

        try replica.revoke(try removal(of: accomplice, by: phone, at: claim[0]), storedAt: start + 1001)
        #expect(held(replica, of: stolen) == [1, 2, 3, 4, 5], "a removed device's claim still kept what nobody else had seen")
    }

    @Test("Two removals: the one that had seen more keeps it")
    func theRemovalThatSawMoreKeepsIt() throws {
        var replica = try friend()
        let words = try feed(of: stolen, 6)
        try replica.revoke(try removal(of: stolen, by: tablet, at: words[1]), storedAt: start + 1000)
        try replica.revoke(try removal(of: stolen, by: phone, at: words[4]), storedAt: start + 1001)

        _ = replica.integrate(words)

        #expect(held(replica, of: stolen) == [1, 2, 3, 4, 5])
    }

    @Test("A new phone that had not caught up keeps what another counting device had seen")
    func aNewPhoneThatHadNotCaughtUp() throws {
        let newPhone = DeviceKeys.generate()
        var replica = try friend(with: [newPhone])
        let words = try feed(of: phone, 5)
        let seen = try feed(of: tablet, 1, seeing: clock(seeing: words[4]))
        for entry in words + seen { try replica.integrate(entry) }

        try replica.revoke(try removal(of: phone, by: newPhone, at: words[1]), storedAt: start + 1000)

        #expect(held(replica, of: phone) == [1, 2, 3, 4, 5])
    }

    @Test("A new phone with nobody else to vouch keeps what it had received, as ruled")
    func aNewPhoneAloneKeepsWhatItReceived() throws {
        let newPhone = DeviceKeys.generate()
        var replica = try friend(with: [newPhone])
        let words = try feed(of: phone, 5)
        for entry in words { try replica.integrate(entry) }

        try replica.revoke(try removal(of: phone, by: newPhone, at: words[1]), storedAt: start + 1000)

        #expect(held(replica, of: phone) == [1, 2])
    }

    @Test("What vouches for an entry can arrive after it: the order entries arrive in does not matter")
    func theOrderDoesNotMatter() throws {
        var replica = try friend()
        let words = try feed(of: phone, 5)
        let seen = try feed(of: stolen, 1, seeing: clock(seeing: words[4]))
        try replica.revoke(try removal(of: phone, by: stolen, at: nil), storedAt: start + 1000)

        let outcomes = replica.integrate(words + seen)

        #expect(held(replica, of: phone) == [1, 2, 3, 4, 5])
        #expect(outcomes.allSatisfy { (try? $0.outcome.get()) == .accepted })
    }

    @Test("The line a phone asks for history up to is the one the evidence draws")
    func gapsFollowTheLine() throws {
        var replica = try friend()
        let words = try feed(of: phone, 5)
        let seen = try feed(of: stolen, 1, seeing: clock(seeing: words[4]))
        try replica.integrate(seen[0])
        try replica.integrate(words[0])
        try replica.revoke(try removal(of: phone, by: stolen, at: nil), storedAt: start + 1000)

        let gap = replica.gaps().first { $0.feed == words[0].feedKey }
        #expect(gap?.spans == [SequenceSpan(2, 5)])
    }
}
