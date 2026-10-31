import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp
@testable import CarpenterKit

@Suite("An entry too big to send is refused for good")
struct RefusingAnEntryTooBigToSendTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func entry(_ bytes: Int, by author: Author, after previous: Entry? = nil) throws -> Entry {
        try Entry.append(
            to: previous, author: author.identity.id, device: author.device, clock: previous?.clock ?? VectorClock(),
            wallTime: start, room: nil, payload: SealedPayload(epoch: .initial, ciphertext: Data(repeating: 0, count: bytes)))
    }

    private func largestThatFits(by author: Author) throws -> Int {
        var (fits, misses) = (0, SyncSession.packetByteBudget)
        while misses - fits > 1 {
            let middle = (fits + misses) / 2
            if SyncSession.fitsAPacket(try entry(middle, by: author)) { fits = middle } else { misses = middle }
        }
        return fits
    }

    @Test("The sender's limit and the receiver's are the same number, at the very edge of it")
    func theLimitIsTheSenderS() throws {
        let alice = Author()
        let edge = try largestThatFits(by: alice)
        #expect(edge > SyncSession.packetByteBudget / 2, "the limit is not the packet budget any more")

        var outcomes: Set<IntegrationResult> = []
        for bytes in (edge - 30)...(edge + 30) {
            let written = try entry(bytes, by: alice)
            let fits = try JSONEncoder().encode(written).count + 2 <= SyncSession.packetByteBudget
            #expect(SyncSession.fitsAPacket(written) == fits)

            var replica = Replica()
            try replica.meet(alice)
            let outcome = try replica.integrate(written)
            #expect(outcome == (fits ? .accepted : .tooLarge))
            outcomes.insert(outcome)
        }
        #expect(outcomes == [.accepted, .tooLarge], "the test did not reach both sides of the limit")
    }

    @Test("A refused entry's number is spent, so a copy changes nothing and repair never asks for it")
    func aRefusedNumberIsSpent() throws {
        let alice = Author()
        let big = try entry(800_000, by: alice)
        var replica = Replica()
        try replica.meet(alice)

        #expect(try replica.integrate(big) == .tooLarge)

        #expect(try replica.integrate(big) == .alreadyPresent, "a second copy was counted again")
        #expect(replica.gaps().isEmpty)
        #expect(replica.spentEntries.map(\.hash) == [big.hash])
    }

    @Test("The entry after a refused one is accepted, and shows no gap")
    func theNextEntryStillLands() throws {
        let alice = Author()
        let big = try entry(800_000, by: alice)
        let next = try entry(10, by: alice, after: big)
        var replica = Replica()
        try replica.meet(alice)

        #expect(try replica.integrate(big) == .tooLarge)
        #expect(try replica.integrate(next) == .accepted)
        #expect(replica.gaps().isEmpty)
    }

    @Test("An oversized entry nobody signed spends nothing")
    func aForgedEntrySpendsNothing() throws {
        let alice = Author()
        let forged = Entry(
            author: alice.identity.id, device: alice.device.id, seq: Entry.firstSequence, previous: nil,
            clock: VectorClock(), wallTime: start, room: nil,
            payload: SealedPayload(epoch: .initial, ciphertext: Data(repeating: 0, count: 800_000)),
            signature: Data(repeating: 7, count: 64))
        var replica = Replica()
        try replica.meet(alice)

        #expect(throws: LogError.self) { try replica.integrate(forged) }

        #expect(replica.spentEntries.isEmpty)
        #expect(try replica.integrate(entry(10, by: alice)) == .accepted, "a forgery took somebody else's number")
    }

    @Test("An oversized entry at a number already held changes nothing")
    func aHeldNumberIsNotTaken() throws {
        let alice = Author()
        let small = try entry(10, by: alice)
        var replica = Replica()
        try replica.meet(alice)
        try replica.integrate(small)

        #expect(try replica.integrate(entry(800_000, by: alice)) == .tooLarge)

        #expect(replica.allEntries == [small])
        #expect(replica.forks.isEmpty)
        #expect(replica.spentEntries.isEmpty)
    }

    @Test("Asking whether an entry fits without encoding it never answers yes when encoding says no")
    func theShortcutIsNeverWrong() throws {
        let alice = Author()
        var clock = VectorClock()
        for seed in 1...400 {
            clock.observe(
                FeedKey(author: ParticipantID(rawValue: Data()), device: DeviceID(rawValue: Data([UInt8(seed % 256)]))),
                seq: .max - UInt64(seed))
        }
        for ciphertext in [Data(), Data(repeating: 0xFF, count: 60_000)] {
            let written = try Entry.append(
                to: nil, author: alice.identity.id, device: alice.device, clock: clock, wallTime: start, room: RoomID(),
                payload: SealedPayload(epoch: .initial, ciphertext: ciphertext), roomLink: RoomLink(previous: nil))
            #expect(try JSONEncoder().encode(written).count <= written.encodedBytesAtMost)
        }
    }

    @Test("An entry that fits is not encoded to find that out")
    func anOrdinaryEntryTakesTheShortcut() throws {
        var alice = Author()
        let ordinary = try alice.post("hello", at: start)
        #expect(ordinary.encodedBytesAtMost <= SyncSession.packetByteBudget)
    }
}

@Suite("A contact sends an entry too big to send", .serialized)
@MainActor
struct OversizedEntryFromAContactTests {
    private struct Pair {
        let mallory: AppSession
        let bob: AppSession
        let room: RoomID
        let mailbox: InMemoryMailbox
        let keychain: InMemoryKeychainStore
        let directory: URL
        let clock: TestClock
    }

    private func scratch() -> URL {
        TestScratch.root.appending(path: "carpenter-oversized-\(UUID().uuidString)")
    }

    private func pair() async throws -> Pair {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let (keychain, directory) = (InMemoryKeychainStore(), scratch())
        let mallory = TestSession.make(clock: clock)
        let bob = TestSession.make(keychain: keychain, at: directory, clock: clock)
        for session in [mallory, bob] { await session.load() }
        try await mallory.createIdentity(displayName: "Mallory")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await mallory.createRoom(named: "Kitchen")
        let invite = try await mallory.invite(
            joinerCode: await bob.joinerCode(through: mailbox), joining: room, through: mailbox)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await mallory.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(mallory.enrolment?.identity.publicKeys))
        for _ in 0..<6 {
            for session in [mallory, bob] { try await session.sync(through: mailbox) }
        }
        return Pair(
            mallory: mallory, bob: bob, room: room, mailbox: mailbox, keychain: keychain, directory: directory,
            clock: clock)
    }

    private func signed(_ bytes: Int, by mallory: AppSession, in room: RoomID) throws -> Entry {
        let enrolment = try #require(mallory.enrolment)
        let entry = try Entry.append(
            after: mallory.head, author: enrolment.identity.id, device: enrolment.device,
            clock: mallory.replica.frontier, wallTime: TestSession.now, room: room,
            payload: SealedPayload(epoch: .initial, ciphertext: Data(repeating: 0, count: bytes)),
            roomLink: RoomLink(previous: mallory.roomHeads[room]?.hash))
        mallory.head = entry.link
        mallory.roomHeads[room] = entry.link
        return entry
    }

    private func deliver(_ entry: Entry, in pair: Pair) async throws -> PacketID {
        let peer = try #require(pair.mallory.peers().first { $0.them == pair.bob.enrolment?.identity.id })
        let packet = try SyncEngine.pack(
            [entry], for: [peer], window: SyncSession.window(at: pair.clock.now))
        try await pair.mailbox.put(packet, to: peer.them, in: try #require(pair.mallory.pairs()))
        return packet.id
    }

    private func reopened(_ pair: Pair) async -> AppSession {
        let session = TestSession.make(keychain: pair.keychain, at: pair.directory, clock: pair.clock)
        await session.load()
        return session
    }

    private func logBytes(_ pair: Pair) throws -> Int {
        try Data(contentsOf: pair.directory.appending(path: "log.carpenter")).count
    }

    @Test(
        "Nine megabytes from a contact cost the receiver nothing, on the file log, across a relaunch",
        arguments: [9 * 1024 * 1024, 800_000])
    func oneEntryCutsOffNothing(bytes: Int) async throws {
        let pair = try await pair()
        try await pair.mallory.send("before", to: pair.room)
        try await pair.mallory.sync(through: pair.mailbox)
        try await pair.bob.sync(through: pair.mailbox)

        let packet = try await deliver(try signed(bytes, by: pair.mallory, in: pair.room), in: pair)
        try await pair.mallory.send("after", to: pair.room)
        try await pair.mallory.sync(through: pair.mailbox)
        let report = try await pair.bob.sync(through: pair.mailbox)
        try await pair.bob.send("and a reply", to: pair.room)
        try await pair.bob.sync(through: pair.mailbox)

        #expect(report.entriesTooLarge == 1)
        #expect(report.entriesRejected == 0)
        #expect(pair.bob.integrity.rejectedFromPeers == 1, "the refusal left no trace a member can see")
        #expect(
            await pair.mailbox.everySentPacket[packet]?.receipts.isEmpty == false,
            "a packet that will never change is left to be fetched every round")
        #expect(try logBytes(pair) < 500_000, "the refused entry reached the disk")

        let bob = await reopened(pair)
        let said = bob.messages(in: pair.room).map(\.body)
        #expect(said.contains("before"))
        #expect(said.contains("after"), "history stopped at the oversized entry")
        #expect(said.contains("and a reply"))
        #expect(bob.integrity.lastLoad == .complete)
        #expect(bob.integrity.discardedBytes == 0)
        #expect(bob.replica.gaps().isEmpty, "repair would ask for an entry that will be refused again")
    }

    @Test("Mail from the member's own device is held to the same limit, and a repeat writes nothing twice")
    func siblingMailMeetsTheSameLimit() async throws {
        let mailbox = InMemoryMailbox()
        let relay = InMemoryEntrySync.Relay()
        let keychain = InMemoryKeychainStore()
        let phone = TestSession.make(keychain: keychain)
        phone.syncDevices(through: InMemoryEntrySync(relay: relay))
        let friend = TestSession.make()
        for session in [phone, friend] { await session.load() }
        try await phone.createIdentity(displayName: "Griff")
        try await friend.createIdentity(displayName: "Outie")
        let room = try await phone.createRoom(named: "Kitchen")
        let invite = try await phone.invite(joinerCode: await friend.joinerCode(through: mailbox), joining: room, through: mailbox)
        try await friend.redeem(inviteCode: try invite.encoded())
        try await phone.sync(through: mailbox)
        try await friend.accept(invite.attestation, from: try #require(phone.enrolment?.identity.publicKeys))
        for _ in 0..<6 {
            for session in [phone, friend] { try await session.sync(through: mailbox) }
        }
        let tablet = TestSession.make(keychain: await keychain.sibling())
        tablet.syncDevices(through: InMemoryEntrySync(relay: relay))
        await tablet.load()
        try await phone.approveNewDevice(tablet)
        await tablet.settleDeviceSync { tablet.rooms.contains { $0.id == room } }
        for _ in 0..<4 {
            await phone.settleDeviceSync()
            await tablet.settleDeviceSync()
        }

        let oversized = try signed(800_000, by: friend, in: room)
        try await friend.send("small", to: room)
        let small = try #require(friend.replica.allEntries.last)
        let enrolment = try #require(phone.enrolment)
        let writer = try #require(tablet.enrolment?.device)
        let toPhone = [DeviceRecipient(device: enrolment.device.id, agreementKey: enrolment.device.agreementPublicKey)]
        func mail(_ number: Int) async throws {
            let feed = SiblingFeed(
                entries: [oversized, small], certificates: [], member: enrolment.identity.id,
                writtenAt: TestSession.now)
            let sealed = try SealedSiblingFeed.seal(
                feed, for: enrolment.identity, on: writer.id, as: .mail(number), to: toPhone, signedBy: writer)
            try await relay.place(SiblingRecord.Name(writer: writer.id, kind: .mail(number)), sealed)
            for _ in 0..<3 {
                await phone.refreshDeviceSync()
                await phone.settleDeviceSync()
            }
        }

        try await mail(900)

        #expect(phone.messages(in: room).contains { $0.body == "small" })
        #expect(phone.integrity.rejectedFromPeers == 1)
        let written = try await phone.storage.log.loadAll().entries
        #expect(!written.contains { $0.hash == oversized.hash }, "an entry refused by the replica reached the disk")
        #expect(written.filter { $0.hash == small.hash }.count == 1)

        try await mail(901)

        #expect(phone.integrity.rejectedFromPeers == 1, "the same refusal was counted twice")
        let again = try await phone.storage.log.loadAll().entries
        #expect(again.count == written.count, "mail repeating what the log holds was written again")
    }

    private func splice(_ record: Data, intoLogOf pair: Pair, before last: Int) throws {
        let url = pair.directory.appending(path: "log.carpenter")
        let data = try Data(contentsOf: url)
        var offsets: [Int] = []
        var cursor = 0
        while cursor + 4 <= data.count {
            offsets.append(cursor)
            cursor += 4 + data[cursor..<(cursor + 4)].reduce(0) { $0 << 8 | Int($1) }
        }
        let at = offsets[offsets.count - last]
        let framed = withUnsafeBytes(of: UInt32(record.count).bigEndian) { Data($0) } + record
        try (data[..<at] + framed + data[at...]).write(to: url)
    }

    @Test("A log already holding a record past the ceiling reads through it, and the next write clears it")
    func aPoisonedLogStillReads() async throws {
        let pair = try await pair()
        for word in ["one", "two", "three"] { try await pair.bob.send(word, to: pair.room) }
        let poison = try JSONEncoder().encode(try signed(9 * 1024 * 1024, by: pair.mallory, in: pair.room))
        try splice(poison, intoLogOf: pair, before: 2)

        let bob = await reopened(pair)

        #expect(bob.messages(in: pair.room).map(\.body).suffix(3) == ["one", "two", "three"])
        #expect(bob.integrity.lastLoad == .recordTooLarge)
        #expect(bob.integrity.discardedBytes == poison.count + 4)

        try await bob.send("four", to: pair.room)
        #expect(try logBytes(pair) < 1_000_000, "the poisoned record outlived the repair")

        let again = await reopened(pair)
        #expect(again.messages(in: pair.room).map(\.body).suffix(4) == ["one", "two", "three", "four"])
        #expect(again.integrity.lastLoad == .complete)
        #expect(again.replica.forks.isEmpty, "a sequence number was used twice after the poisoned load")
    }

    @Test("An entry over the sender's limit already on disk is refused on load, not called altered")
    func anOldOversizedRecordIsRefusedOnLoad() async throws {
        let pair = try await pair()
        try await pair.bob.send("mine", to: pair.room)
        let oversized = try signed(800_000, by: pair.mallory, in: pair.room)
        try splice(try JSONEncoder().encode(oversized), intoLogOf: pair, before: 1)

        let bob = await reopened(pair)

        #expect(bob.messages(in: pair.room).contains { $0.body == "mine" })
        #expect(bob.integrity.unverifiableOnDisk == 0)
        #expect(bob.integrity.rejectedFromPeers == 1)
        #expect(bob.integrity.lastLoad == .complete)
        #expect(!bob.replica.allEntries.contains { $0.hash == oversized.hash })
    }

    @Test("A round whose only unsent entry is too big still sends everything else it owes")
    func aRoundStillCarriesTheRest() async throws {
        let pair = try await pair()
        let oversized = try signed(800_000, by: pair.mallory, in: pair.room)
        let peer = try #require(pair.mallory.peers().first)
        let session = SyncSession(
            mailbox: pair.mailbox, pairs: try #require(pair.mallory.pairs()), clock: pair.clock)
        let wishes = [try #require(pair.bob.enrolment?.identity.id)]

        let report = try await session.send([oversized], to: [peer], notifyWalls: wishes)

        #expect(report.packetsWritten == 1, "the entry that could not go took the rest of the round with it")
        #expect(report.entriesSent == 0)

        let reading = SyncSession(mailbox: pair.mailbox, pairs: try #require(pair.bob.pairs()), clock: pair.clock)
        let peerOfBob = try #require(pair.bob.peers().first)
        let collected = try await reading.collect(as: peerOfBob)
        #expect(collected.packets.contains { $0.delivery.notifyWalls == wishes })
    }

    @Test("A round with nothing to carry but an entry too big writes nothing")
    func aRoundWithNothingElseWritesNothing() async throws {
        let pair = try await pair()
        let oversized = try signed(800_000, by: pair.mallory, in: pair.room)
        let peer = try #require(pair.mallory.peers().first)
        let session = SyncSession(
            mailbox: pair.mailbox, pairs: try #require(pair.mallory.pairs()), clock: pair.clock)
        let before = await pair.mailbox.writtenPackets.count

        let report = try await session.send([oversized], to: [peer])

        #expect(report.packetsWritten == 0)
        #expect(await pair.mailbox.writtenPackets.count == before, "an empty packet was written every round")
    }
}
