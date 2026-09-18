import Foundation
import Testing

@testable import CarpenterKit

@Suite("Vector clocks")
struct VectorClockTests {
    private let alice = FeedKey(author: Identity.generate().id, device: DeviceKeys.generate().id)
    private let bob = FeedKey(author: Identity.generate().id, device: DeviceKeys.generate().id)

    @Test("A feed nobody has heard from is at zero, not absent")
    func defaultsToZero() {
        #expect(VectorClock()[alice] == 0)
    }

    @Test("Observing only ever moves a feed forward")
    func observeTakesTheMaximum() {
        var clock = VectorClock()
        clock.observe(alice, seq: 5)
        clock.observe(alice, seq: 3)

        #expect(clock[alice] == 5)
    }

    @Test("Merging takes the componentwise maximum")
    func merge() {
        var left = VectorClock()
        left.observe(alice, seq: 4)
        left.observe(bob, seq: 1)

        var right = VectorClock()
        right.observe(alice, seq: 2)
        right.observe(bob, seq: 7)

        let merged = left.merging(right)

        #expect(merged[alice] == 4)
        #expect(merged[bob] == 7)
    }

    @Test("Merging is commutative and idempotent, so replicas agree however they got there")
    func mergeIsAJoin() {
        var left = VectorClock()
        left.observe(alice, seq: 4)
        var right = VectorClock()
        right.observe(bob, seq: 7)

        #expect(left.merging(right) == right.merging(left))
        #expect(left.merging(left) == left)
        #expect(left.merging(right).merging(right) == left.merging(right))
    }

    @Test("A clock that has seen strictly less happened first")
    func happensBefore() {
        var earlier = VectorClock()
        earlier.observe(alice, seq: 1)

        var later = earlier
        later.observe(alice, seq: 2)

        #expect(earlier.happensBefore(later))
        #expect(!later.happensBefore(earlier))
    }

    @Test("A clock does not happen before itself")
    func irreflexive() {
        var clock = VectorClock()
        clock.observe(alice, seq: 1)

        #expect(!clock.happensBefore(clock))
        #expect(!clock.isConcurrent(with: clock))
    }

    @Test("Clocks that each know something the other does not are concurrent")
    func concurrency() {
        var left = VectorClock()
        left.observe(alice, seq: 1)
        var right = VectorClock()
        right.observe(bob, seq: 1)

        #expect(left.isConcurrent(with: right))
        #expect(right.isConcurrent(with: left))
        #expect(!left.happensBefore(right))
        #expect(!right.happensBefore(left))
    }

    @Test("Canonical bytes do not depend on the order feeds were observed in")
    func canonicalBytesAreOrderIndependent() {
        var left = VectorClock()
        left.observe(alice, seq: 1)
        left.observe(bob, seq: 2)

        var right = VectorClock()
        right.observe(bob, seq: 2)
        right.observe(alice, seq: 1)

        #expect(left.canonicalBytes == right.canonicalBytes)
    }

    @Test("A feed at zero does not change the canonical bytes")
    func zeroEntriesAreNotSignificant() {
        var explicit = VectorClock()
        explicit.observe(alice, seq: 1)
        explicit.observe(bob, seq: 0)

        var implicit = VectorClock()
        implicit.observe(alice, seq: 1)

        #expect(explicit.canonicalBytes == implicit.canonicalBytes)
        #expect(explicit == implicit)
    }

    @Test("Clocks survive encoding, because they travel inside every entry")
    func codableRoundTrip() throws {
        var clock = VectorClock()
        clock.observe(alice, seq: 3)
        clock.observe(bob, seq: 9)

        let restored = try JSONDecoder().decode(
            VectorClock.self, from: JSONEncoder().encode(clock))

        #expect(restored == clock)
    }
}
