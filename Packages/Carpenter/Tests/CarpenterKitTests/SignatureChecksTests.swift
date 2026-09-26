import Foundation
import Testing

@testable import CarpenterKit

@Suite("Signatures checked ahead of time")
struct SignatureChecksTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func history(of authors: inout [Author], each count: Int) throws -> [Entry] {
        var made: [Entry] = []
        for step in 0..<count {
            for index in authors.indices {
                made.append(try authors[index].post("\(index).\(step)", at: start.addingTimeInterval(Double(step))))
            }
        }
        return made
    }

    private func signed(_ entry: Entry, by device: DeviceKeys, payload: SealedPayload? = nil) throws -> Entry {
        let unsigned = Entry(
            author: entry.author, device: entry.device, seq: entry.seq, previous: entry.previous,
            clock: entry.clock, wallTime: entry.wallTime, room: entry.room,
            payload: payload ?? entry.payload, signature: Data())
        return Entry(
            author: entry.author, device: entry.device, seq: entry.seq, previous: entry.previous,
            clock: entry.clock, wallTime: entry.wallTime, room: entry.room,
            payload: payload ?? entry.payload, signature: try device.sign(unsigned.signingPayload))
    }

    @Test("A log integrated with its signatures checked ahead ends up exactly as one checked entry by entry")
    func checkedAheadMatchesCheckedOnArrival() async throws {
        var authors = [Author(), Author(), Author()]
        let entries = try history(of: &authors, each: 100)
        var ahead = Replica()
        var onArrival = Replica()
        for author in authors {
            try ahead.meet(author)
            try onArrival.meet(author)
        }

        let checks = await ahead.signatureChecks(for: entries)
        #expect(checks.count == entries.count)
        for entry in entries.shuffled() {
            let checked = try ahead.integrate(entry, checked: checks)
            #expect(checked == (try onArrival.integrate(entry)))
        }

        #expect(Set(ahead.allEntries.map(\.hash)) == Set(onArrival.allEntries.map(\.hash)))
        #expect(ahead.frontier == onArrival.frontier)
    }

    @Test("A tampered entry in a batch checked ahead is still refused")
    func aTamperedEntryIsStillRefused() async throws {
        var authors = [Author()]
        var entries = try history(of: &authors, each: 80)
        var replica = Replica()
        try replica.meet(authors[0])
        let genuine = entries[40]
        entries[40] = Entry(
            author: genuine.author, device: genuine.device, seq: genuine.seq, previous: genuine.previous,
            clock: genuine.clock, wallTime: genuine.wallTime, room: genuine.room,
            payload: try Payload.post("not what she said").sealed(at: .initial, using: authors[0].chain),
            signature: genuine.signature)

        let checks = await replica.signatureChecks(for: entries)

        #expect(checks.count == entries.count - 1)
        #expect(throws: LogError.badSignature) { try replica.integrate(entries[40], checked: checks) }
    }

    @Test("A check vouches for a signature under the key it was made with, and no other")
    func aCheckIsBoundToItsKey() async throws {
        var alice = Author()
        let eve = DeviceKeys.generate()
        var replica = Replica()
        try replica.meet(alice)
        let forged = try signed(try alice.post("hello", at: start), by: eve)
        let claimed = DeviceCertificate(
            participant: alice.identity.id, device: alice.device.id, devicePublicKey: eve.publicKey,
            issuedAt: start, signature: Data())

        let checks = await Replica().signatureChecks(for: [forged], alsoTrusting: [claimed])

        #expect(checks.count == 1, "precondition: the forgery verifies under the key it was made with")
        #expect(throws: LogError.badSignature) { try replica.integrate(forged, checked: checks) }
    }

    @Test("A check does not stand in for knowing the author or the device")
    func aCheckIsNotAnIntroduction() async throws {
        var alice = Author()
        let entry = try alice.post("hello", at: start)
        let checks = await Replica().signatureChecks(for: [entry], alsoTrusting: [alice.certificate])
        #expect(checks.count == 1)

        var stranger = Replica()
        #expect(throws: LogError.unknownParticipant) { try stranger.integrate(entry, checked: checks) }

        var uncertified = Replica()
        uncertified.introduce(alice.identity.publicKeys)
        #expect(throws: LogError.unauthorizedDevice) { try uncertified.integrate(entry, checked: checks) }
    }

    @Test("What the replica already holds is not checked again")
    func heldEntriesAreNotChecked() async throws {
        var authors = [Author()]
        let entries = try history(of: &authors, each: 50)
        var replica = Replica()
        try replica.meet(authors[0])
        for entry in entries.prefix(40) { try replica.integrate(entry) }

        let checks = await replica.signatureChecks(for: entries)

        #expect(checks.count == 10)
    }
}
