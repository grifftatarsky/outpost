@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
final class Gathering {
    @MainActor
    final class Device {
        let name: String
        let person: String
        let door: HookedMailbox
        let clock: TestClock
        var session: AppSession
        var engine: InMemoryEntrySync
        var keychain: InMemoryKeychainStore
        var folder: URL
        var mailboxOnly = false
        var away = false
        var ended: EndedProcess?
        var known: (person: ParticipantID, device: DeviceID)?

        func remember() {
            if let enrolment = session.enrolment { known = (enrolment.identity.id, enrolment.device.id) }
        }

        init(
            name: String, person: String, door: HookedMailbox, clock: TestClock, session: AppSession,
            engine: InMemoryEntrySync, keychain: InMemoryKeychainStore, folder: URL
        ) {
            self.name = name
            self.person = person
            self.door = door
            self.clock = clock
            self.session = session
            self.engine = engine
            self.keychain = keychain
            self.folder = folder
        }
    }

    actor EndedProcess {
        private(set) var keychain: InMemoryKeychainStore?
        private(set) var folder: URL?
        private(set) var iCloud: LocalPairStore?

        func keep(_ keychain: InMemoryKeychainStore, _ folder: URL, _ iCloud: LocalPairStore) {
            self.keychain = keychain
            self.folder = folder
            self.iCloud = iCloud
        }
    }

    struct NotSettled: Error, CustomStringConvertible {
        let description: String
    }

    static let yieldLimit = 20_000

    let cloud: InMemoryMailbox
    let iCloud: TestClock
    private(set) var devices: [Device] = []
    private var relays: [(person: String, relay: InMemoryEntrySync.Relay)] = []
    private let handsOver: InMemoryEntrySync.Relay.HandOver

    private init(handsOver: InMemoryEntrySync.Relay.HandOver) {
        iCloud = TestClock(now: TestSession.now)
        cloud = InMemoryMailbox(clock: iCloud)
        self.handsOver = handsOver
    }

    static func of(_ people: String...) async throws -> Gathering {
        try await of(people)
    }

    static func of(
        _ people: [String], handsOver: InMemoryEntrySync.Relay.HandOver = .once
    ) async throws -> Gathering {
        let gathering = Gathering(handsOver: handsOver)
        for person in people {
            let relay = InMemoryEntrySync.Relay(announces: false, clock: gathering.iCloud, handsOver: handsOver)
            gathering.relays.append((person, relay))
            let device = try gathering.makeDevice(person, of: person, keychain: InMemoryKeychainStore())
            await device.session.load()
            try await device.session.createIdentity(displayName: person)
        }
        try await gathering.quiesce()
        return gathering
    }

    func makeDevice(_ name: String, of person: String, keychain: InMemoryKeychainStore) throws -> Device {
        let folder = TestScratch.root.appending(path: "gathering-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let clock = TestClock(now: iCloud.now)
        let session = TestSession.make(keychain: keychain, at: folder, clock: clock)
        let engine = InMemoryEntrySync(relay: relay(of: person), as: name)
        session.syncDevices(through: engine)
        let device = Device(
            name: name, person: person, door: HookedMailbox(inner: cloud), clock: clock, session: session,
            engine: engine, keychain: keychain, folder: folder)
        devices.append(device)
        return device
    }

    // MARK: Who is who

    subscript(_ device: String) -> AppSession { find(device).session }

    func door(_ device: String) -> HookedMailbox { find(device).door }

    func clock(_ device: String) -> TestClock { find(device).clock }

    func relay(of person: String) -> InMemoryEntrySync.Relay {
        relays.first { $0.person == person }!.relay
    }

    func id(_ person: String) -> ParticipantID {
        guard let known = devices.first(where: { $0.person == person })?.known else {
            preconditionFailure("\(person) has no identity in this gathering")
        }
        return known.person
    }

    func device(_ name: String) -> DeviceID {
        guard let known = find(name).known else { preconditionFailure("\(name) was never approved") }
        return known.device
    }

    func devices(of person: String, seenBy viewer: String) -> Set<DeviceID> {
        self[viewer].replica.registry(for: id(person))?.activeDevices ?? []
    }

    func find(_ name: String) -> Device {
        guard let device = devices.first(where: { $0.name == name }) else {
            preconditionFailure("nobody in this gathering is called \(name)")
        }
        return device
    }

    private func name(of peer: ParticipantID?) -> String {
        guard let peer else { return "" }
        return devices.first { $0.known?.person == peer }?.person ?? "somebody"
    }

    func callsByName(_ device: String) async -> [String] {
        await door(device).calls.map { "\($0.call.rawValue) \(name(of: $0.peer))".trimmingCharacters(in: .whitespaces) }
    }

    // MARK: Rooms and devices

    func room(_ name: String, host: String, guests: [String]) async throws -> RoomID {
        let room = try await self[host].createRoom(named: name)
        for guest in guests {
            let invite = try await self[host].invite(
                joinerCode: await self[guest].joinerCode(through: door(guest)), joining: room, through: door(host))
            try await self[guest].redeem(inviteCode: try invite.encoded())
            for _ in 0..<5 { await takeTurns(host, guest) }
        }
        try await settle()
        try #require(
            self[host].roster(of: room).members.count == guests.count + 1, "precondition: everybody is in \(name)")
        return room
    }

    func secondDevice(_ name: String, of person: String) async throws {
        let first = try #require(devices.first { $0.person == person })
        let device = try makeDevice(name, of: person, keychain: await first.keychain.sibling())
        let new = device.session
        await new.load()
        try await first.session.approveNewDevice(new, between: quiesce)
        try await quiesce()
        for _ in 0..<12 where new.rooms.count < first.session.rooms.count {
            await new.refreshDeviceSync()
            try await quiesce()
            await first.session.refreshDeviceSync()
            try await quiesce()
        }
        try #require(new.enrolment != nil, "\(name) never took its approval")
        try await settle()
        try #require(new.rooms.count == first.session.rooms.count, "\(name) never heard of \(first.name)'s rooms")
    }

    // MARK: Turns

    @discardableResult
    func takeTurns(_ names: String...) async -> [String: Result<SyncReport, any Error>] {
        await takeTurns(names)
    }

    @discardableResult
    func takeTurns(_ names: [String]) async -> [String: Result<SyncReport, any Error>] {
        var results: [String: Result<SyncReport, any Error>] = [:]
        for name in names {
            let device = find(name)
            guard !device.away else { continue }
            results[name] = await turn(device)
        }
        return results
    }

    private func turn(_ device: Device) async -> Result<SyncReport, any Error> {
        var result: Result<SyncReport, any Error> = .success(SyncReport())
        let session = device.session
        _ = await SyncRound.run(
            deviceSync: { if !device.mailboxOnly { await session.refreshDeviceSync() } },
            mailbox: {
                guard session.enrolment != nil else { return }
                do {
                    result = .success(try await session.sync(through: device.door, media: device.door))
                } catch {
                    result = .failure(error)
                    throw error
                }
            },
            now: { device.clock.now })
        do {
            try await quiesce()
        } catch {
            return .failure(error)
        }
        return result
    }

    func mailboxOnly(_ name: String) { find(name).mailboxOnly = true }

    func away(_ names: String...) { for name in names { find(name).away = true } }

    func back(_ names: String...) { for name in names { find(name).away = false } }

    func settle(inOrder order: [String]? = nil, passes: Int = 12) async throws {
        let order = order ?? devices.map(\.name)
        var before = await everythingStored()
        var changing: [String] = []
        var quiet = false
        for pass in 0..<passes {
            await takeTurns(order)
            let after = await everythingStored()
            changing = after.symmetricDifference(before).sorted()
            if pass > 0, changing.isEmpty, quiet { return }
            quiet = changing.isEmpty
            before = after
        }
        throw NotSettled(description: "still changing after \(passes) passes: \(changing.prefix(8))")
    }

    private func everythingStored() async -> Set<String> {
        var stored: Set<String> = []
        for (person, relay) in relays {
            stored.formUnion(await relay.stamps().map { "\(person) \($0)" })
        }
        let people = Set(devices.compactMap { $0.known?.person })
        for device in devices {
            let session = device.session
            var seen = [
                "state \(session.state)", "entries \(session.replica.allEntries.count)",
                "owed \((try? session.grantsOwed().count) ?? -1)", "unsent \(session.unsentEntries().count)",
                "waiting \(session.waitingToBeTold.count)",
            ]
            for person in people.sorted(by: { $0.rawValue.lexicographicallyPrecedes($1.rawValue) }) {
                seen.append("devices \(session.replica.registry(for: person)?.activeDevices.count ?? 0)")
            }
            for room in session.rooms.map(\.id) {
                seen.append("keys \(session.chains[room]?.heldKeyCount ?? 0)")
                seen.append("members \(session.roster(of: room).members.count)")
                seen += session.messages(in: room).map { "\($0.body) \($0.delivery)" }
            }
            stored.formUnion(seen.map { "\(device.name) \($0)" })
        }
        return stored
    }

    func quiesce() async throws {
        for device in devices { await device.session.incomingTask?.value }
        defer { for device in devices { device.remember() } }
        for _ in 0..<Self.yieldLimit {
            if !devices.contains(where: { $0.session.publishing || $0.session.publishAgain }) { return }
            await Task.yield()
        }
        let busy = devices.filter { $0.session.publishing || $0.session.publishAgain }.map(\.name)
        throw NotSettled(description: "still publishing to device sync: \(busy)")
    }

    // MARK: Processes and clocks

    @discardableResult
    func endProcess(of name: String, atCall number: Int) async -> EndedProcess {
        let device = find(name)
        let ended = EndedProcess()
        device.ended = ended
        let (door, keychain, folder, engine, cloud) = (
            device.door, device.keychain, device.folder, device.engine, cloud
        )
        await door.before(call: number) {
            guard let copy = Self.wholeCopy(of: folder) else {
                Issue.record("\(name)'s folder could not be copied whole, so there is nothing to relaunch from")
                return
            }
            await ended.keep(await keychain.copy(), copy, await cloud.view())
            await keychain.endProcess()
            await engine.cut()
            await door.hangUp()
        }
        return ended
    }

    private nonisolated static func wholeCopy(of folder: URL) -> URL? {
        for _ in 0..<20 {
            let copy = TestScratch.root.appending(path: "gathering-ended-\(UUID().uuidString)")
            do {
                try FileManager.default.copyItem(at: folder, to: copy)
                return copy
            } catch {
                try? FileManager.default.removeItem(at: copy)
            }
        }
        return nil
    }

    func relaunch(_ name: String) async {
        let device = find(name)
        if let ended = device.ended, let keychain = await ended.keychain, let folder = await ended.folder {
            device.keychain = keychain
            device.folder = folder
        }
        device.ended = nil
        await device.engine.cut()
        await device.door.forgetSteps()
        await device.door.relent()
        let session = TestSession.make(keychain: device.keychain, at: device.folder, clock: device.clock)
        let engine = InMemoryEntrySync(relay: relay(of: device.person), as: name)
        session.syncDevices(through: engine)
        device.session = session
        device.engine = engine
        await session.load()
        try? await quiesce()
    }

    func advance(by interval: TimeInterval) {
        iCloud.advance(by: interval)
        for device in devices { device.clock.advance(by: interval) }
    }

    // MARK: What every phone shows

    func sameRoom(_ room: RoomID, on names: [String], sourceLocation: SourceLocation = #_sourceLocation) {
        guard let first = names.first else { return }
        let reference = shown(room, on: first)
        for name in names.dropFirst() {
            let seen = shown(room, on: name)
            #expect(
                seen.members == reference.members, "\(name) and \(first) disagree on who is in the room",
                sourceLocation: sourceLocation)
            #expect(
                seen.key == reference.key && seen.key != nil,
                "\(name) writes under a different key from \(first)", sourceLocation: sourceLocation)
            #expect(
                seen.messages == reference.messages,
                "\(name) shows \(seen.messages.count) messages and \(first) shows \(reference.messages.count)",
                sourceLocation: sourceLocation)
        }
    }

    private func shown(_ room: RoomID, on name: String) -> (
        members: Set<ParticipantID>, key: Data?, messages: [String]
    ) {
        let session = self[name]
        return (
            session.roster(of: room).members,
            session.writingKey(of: room)?.secret.fingerprint,
            session.messages(in: room).map { "\(self.name(of: $0.author.id)): \($0.body)" }
        )
    }

    func key(of room: RoomID, on name: String) -> Data? { self[name].writingKey(of: room)?.secret.fingerprint }

    func chainHoldingOnlyTheWritingKey(of room: RoomID, on name: String) -> EpochChain? {
        guard let key = self[name].writingKey(of: room) else { return nil }
        var chain = EpochChain(room: room)
        chain.adopt(key.secret, at: key.epoch)
        return chain
    }

    func entry(saying body: String, in room: RoomID, on name: String) -> Entry? {
        let session = self[name]
        guard let message = session.messages(in: room).last(where: { $0.body == body }) else { return nil }
        return session.replica.allEntries.first { $0.hash == message.id.entry }
    }

    func shows(_ body: String, in room: RoomID, on name: String) -> Bool {
        self[name].messages(in: room).contains { $0.body == body }
    }
}
