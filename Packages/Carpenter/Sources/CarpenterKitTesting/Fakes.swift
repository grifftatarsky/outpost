import CarpenterKit
import CryptoKit
import Foundation
import ImageIO
import Synchronization

public final class TestClock: Clock {
    private let instant: Mutex<Date>

    public init(now: Date = Date(timeIntervalSince1970: 0)) {
        instant = Mutex(now)
    }

    public var now: Date { instant.withLock { $0 } }

    public func advance(by interval: TimeInterval) {
        instant.withLock { $0.addTimeInterval(interval) }
    }

    public func set(_ date: Date) {
        instant.withLock { $0 = date }
    }
}

public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public actor InMemoryKeychainStore: KeychainStore {
    public actor Synced {
        fileprivate var items: [KeychainKey: Data] = [:]

        public init() {}
    }

    public struct LockedPhone: Error {}
    public struct ProcessEnded: Error {}

    private let synced: Synced
    private let dial: ProtectionDial
    private var local: [KeychainKey: Data] = [:]
    private var protections: [KeychainKey: StorageProtection] = [:]

    public private(set) var writes = 0
    public private(set) var phoneIsLocked = false
    private var processEnded = false

    public func endProcess() { processEnded = true }

    public init(syncingThrough synced: Synced = Synced(), protection dial: ProtectionDial = ProtectionDial()) {
        self.synced = synced
        self.dial = dial
    }

    public func sibling() -> InMemoryKeychainStore {
        InMemoryKeychainStore(syncingThrough: synced)
    }

    private init(
        synced: Synced, dial: ProtectionDial, local: [KeychainKey: Data], protections: [KeychainKey: StorageProtection]
    ) {
        self.synced = synced
        self.dial = dial
        self.local = local
        self.protections = protections
    }

    public func copy() -> InMemoryKeychainStore {
        InMemoryKeychainStore(synced: synced, dial: dial, local: local, protections: protections)
    }

    public func data(for key: KeychainKey) async throws -> Data? {
        if let data = local[key] {
            guard !(phoneIsLocked && protections[key] == .whileUnlocked) else { throw LockedPhone() }
            return data
        }
        return await synced.item(key)
    }

    public func set(_ data: Data, for key: KeychainKey, scope: KeychainScope) async throws {
        guard !processEnded else { throw ProcessEnded() }
        guard !(phoneIsLocked && dial.current == .whileUnlocked) else { throw LockedPhone() }
        writes += 1
        switch scope {
        case .synchronized:
            local[key] = nil
            protections[key] = nil
            await synced.set(data, for: key)
        case .device:
            local[key] = data
            protections[key] = dial.current
            await synced.set(nil, for: key)
        }
    }

    public func remove(_ key: KeychainKey) async throws {
        guard !processEnded else { throw ProcessEnded() }
        local[key] = nil
        protections[key] = nil
    }

    public func removeAll(_ scope: KeychainScope) async throws {
        guard !processEnded else { throw ProcessEnded() }
        switch scope {
        case .device:
            local = [:]
            protections = [:]
        case .synchronized:
            await synced.clear()
        }
    }

    public func protect(as protection: StorageProtection) async throws {
        let touchesSealed = protection == .whileUnlocked || protections.values.contains(.whileUnlocked)
        guard !(phoneIsLocked && touchesSealed) else { throw LockedPhone() }
        for key in local.keys { protections[key] = protection }
    }

    public func lockPhone() { phoneIsLocked = true }

    public func unlockPhone() { phoneIsLocked = false }

    public var protectedKeys: [KeychainKey: StorageProtection] { protections }

    public func scope(for key: KeychainKey) async -> KeychainScope? {
        if local[key] != nil { return .device }
        return await synced.item(key) == nil ? nil : .synchronized
    }

    public var synchronizedItems: [KeychainKey: Data] {
        get async { await synced.all() }
    }
}

extension InMemoryKeychainStore.Synced {
    fileprivate func item(_ key: KeychainKey) -> Data? { items[key] }
    fileprivate func set(_ data: Data?, for key: KeychainKey) { items[key] = data }
    fileprivate func clear() { items = [:] }
    fileprivate func all() -> [KeychainKey: Data] { items }
}

public actor InMemoryMailbox: Mailbox, MediaMailbox {
    public struct Ring: Hashable, Sendable {
        public let from: ParticipantID
        public let to: ParticipantID
        public let reached: Set<String>
    }

    private let clock: any Clock
    private var store = LocalPairStore()
    private var pendingFailure: MailboxError?
    private var packetFailures: [Int: MailboxError] = [:]
    private var uploadFailures: [Int: MailboxError] = [:]

    public private(set) var writeCount = 0
    public private(set) var fetchCount = 0
    public private(set) var acknowledgeCount = 0
    public private(set) var withdrawCount = 0
    public private(set) var rings: [Ring] = []
    public private(set) var uploadCount = 0
    public private(set) var downloadCount = 0
    public private(set) var attachmentAcknowledgeCount = 0
    public private(set) var attachmentDeleteCount = 0

    public init(clock: any Clock = SystemClock()) {
        self.clock = clock
    }

    public var writtenPackets: [PacketID] { store.packetOrder }

    private var packetRecords: [(url: URL, name: String, record: LocalPairStore.Record)] {
        store.allRecords.filter { UUID(uuidString: $0.name) != nil }
    }

    private var photoOf: [PhotoCopyName: AttachmentID] = [:]

    private func copies(of photo: AttachmentID) -> [PhotoCopyName] {
        photoOf.filter { $0.value == photo }.map(\.key)
    }

    public var storedPacketCount: Int { packetRecords.count }
    public var storedAttachmentIDs: Set<AttachmentID> {
        Set(store.everyStoredCopy.compactMap { photoOf[$0.name] })
    }
    public var storedAttachmentCount: Int { storedAttachmentIDs.count }
    public var storedCopyCount: Int { store.everyStoredCopy.count }

    public var serverWrites: Int {
        writeCount + acknowledgeCount + withdrawCount + rings.count + uploadCount
            + attachmentAcknowledgeCount + attachmentDeleteCount
    }

    public var everySentPacket: [PacketID: SentPacket] { store.everySentPacket }

    public var everyStoredCopy: [StoredPhotoCopy] { store.everyStoredCopy }

    public var storedRecords: [(name: String, fields: [String: PacketField])] {
        store.allRecords.map { (name: $0.name, fields: $0.record.fields) }
    }

    public var everyPendingAttachment: [AttachmentID: SentAttachment] {
        var found: [AttachmentID: SentAttachment] = [:]
        for copy in store.everyStoredCopy {
            guard let photo = photoOf[copy.name] else { continue }
            let before = found[photo]
            found[photo] = SentAttachment(
                recipients: copy.recipients.union(before?.recipients ?? []),
                receipts: (before?.receipts ?? []) + copy.receipts)
        }
        return found
    }

    public func spaceCount(of participant: ParticipantID) -> Int {
        store.spaces.values.filter { $0.owner == participant }.count
    }

    public func readers(ofSpaceOf owner: ParticipantID) -> [Set<String>] {
        store.spaces.values.filter { $0.owner == owner }.map(\.joined)
    }

    // MARK: Pairing

    public func account(in pairs: Pairs) -> String { seat(pairs) }

    private var signedInAs: String?

    private func seat(_ pairs: Pairs) -> String { signedInAs ?? LocalPairStore.account(of: pairs.me) }

    public nonisolated func signedIn(as account: String) -> SignedInMailbox { SignedInMailbox(base: self, account: account) }

    func acting<T: Sendable>(as account: String, _ body: @Sendable (isolated InMemoryMailbox) throws -> T) rethrows -> T {
        signedInAs = account
        defer { signedInAs = nil }
        return try body(self)
    }

    public func space(for peer: ParticipantID, naming account: String?, in pairs: Pairs) throws -> URL {
        try store.space(for: peer, naming: account, in: pairs, as: seat(pairs))
    }

    public func spaceForACode(in pairs: Pairs) -> URL { store.spaceForACode(in: pairs, as: seat(pairs)) }

    public func claim(_ url: URL, for peer: ParticipantID, naming account: String?, in pairs: Pairs) throws -> URL {
        try store.claim(url, for: peer, naming: account, in: pairs, as: seat(pairs))
    }

    public func join(_ link: PairLink, of peer: ParticipantID, in pairs: Pairs) -> JoinOutcome {
        store.join(link, of: peer, in: pairs, as: seat(pairs))
    }

    public func reads(_ peer: ParticipantID, in pairs: Pairs) -> Bool {
        store.reads(peer, in: pairs, as: seat(pairs))
    }

    public func close(_ peer: ParticipantID, in pairs: Pairs) { store.close(peer, in: pairs, as: seat(pairs)) }

    public func stopSharing(with peer: ParticipantID, in pairs: Pairs) {
        store.stopSharing(with: peer, in: pairs, as: seat(pairs))
    }

    public func leave(_ peer: ParticipantID, in pairs: Pairs) { store.leave(peer, in: pairs, as: seat(pairs)) }

    // MARK: Packets

    public func put(_ packet: SyncPacket, to peer: ParticipantID, in pairs: Pairs) throws {
        writeCount += 1
        if let failure = pendingFailure {
            pendingFailure = nil
            throw failure
        }
        if let failure = packetFailures.removeValue(forKey: writeCount) { throw failure }
        try store.put(packet, to: peer, in: pairs, as: seat(pairs), at: clock.now)
    }

    public func ring(_ peer: ParticipantID, in pairs: Pairs) throws {
        let reached = try store.ring(peer, in: pairs, as: seat(pairs), at: clock.now)
        rings.append(Ring(from: pairs.me, to: peer, reached: reached))
    }

    public func fetch(from peer: ParticipantID, for tags: Set<RecipientTag>, in pairs: Pairs) -> [SyncPacket] {
        fetchCount += 1
        let account = seat(pairs)
        let lastStored = Dictionary(
            store.records(inSpaceOf: peer, forMe: pairs, as: account).map { ($0.name, $0.record.modifiedAt) },
            uniquingKeysWith: { first, _ in first })
        let found = store.fetch(from: peer, for: tags, in: pairs, as: account).map { packet in
            var packet = packet
            packet.storedAt = lastStored[packet.id.rawValue.uuidString] ?? packet.storedAt
            return packet
        }
        return inSameInstantOrder(found)
    }

    public func fetch(
        from peer: ParticipantID, for tags: Set<RecipientTag>, in pairs: Pairs, seenIn view: LocalPairStore
    ) -> [SyncPacket] {
        fetchCount += 1
        var seen = view
        let account = seat(pairs)
        let lastStored = Dictionary(
            seen.records(inSpaceOf: peer, forMe: pairs, as: account).map { ($0.name, $0.record.modifiedAt) },
            uniquingKeysWith: { first, _ in first })
        return seen.fetch(from: peer, for: tags, in: pairs, as: account).map { packet in
            var packet = packet
            packet.storedAt = lastStored[packet.id.rawValue.uuidString] ?? packet.storedAt
            return packet
        }
    }

    public func view() -> LocalPairStore { store }

    public var now: Date { clock.now }

    public func stamps(inSpaceOf peer: ParticipantID, in pairs: Pairs) -> Set<String> {
        Set(store.records(inSpaceOf: peer, forMe: pairs, as: seat(pairs)).map { "\($0.name) \($0.record.modifiedAt)" })
    }

    public func grantCount(in packet: PacketID) -> Int {
        store.allRecords.first { $0.name == packet.rawValue.uuidString }
            .flatMap { PacketWire.packet(from: $0.record.fields) }?.grants.values.reduce(0) { $0 + $1.count } ?? 0
    }

    public func sender(of packet: PacketID) -> ParticipantID? {
        store.allRecords.first { $0.name == packet.rawValue.uuidString }.flatMap { store.spaces[$0.url]?.owner }
    }

    public func sentPackets(in pairs: Pairs, seenIn view: LocalPairStore) -> [PacketID: SentPacket] {
        view.sentPackets(in: pairs, as: seat(pairs))
    }

    private var instant: (window: TimeInterval, generator: SeededGenerator)?

    public func sameInstant(within window: TimeInterval, seed: UInt64) {
        instant = (window, SeededGenerator(seed: seed))
    }

    private func inSameInstantOrder(_ packets: [SyncPacket]) -> [SyncPacket] {
        guard var drawn = instant else { return packets }
        var ordered: [SyncPacket] = []
        var group: [SyncPacket] = []
        for packet in packets {
            if let first = group.first, let at = packet.storedAt, let start = first.storedAt,
                at.timeIntervalSince(start) > drawn.window
            {
                ordered += group.shuffled(using: &drawn.generator)
                group = []
            }
            group.append(packet)
        }
        ordered += group.shuffled(using: &drawn.generator)
        instant = drawn
        return ordered
    }

    public func acknowledge(
        _ id: PacketID, from peer: ParticipantID, with receipt: SealedReceipt, in pairs: Pairs
    ) throws {
        acknowledgeCount += 1
        try store.acknowledge(id, from: peer, with: receipt, in: pairs, as: seat(pairs), at: clock.now)
    }

    public func sentPackets(in pairs: Pairs) -> [PacketID: SentPacket] { store.sentPackets(in: pairs, as: seat(pairs)) }

    public func withdraw(_ id: PacketID, in pairs: Pairs) {
        withdrawCount += 1
        store.withdraw(id, as: seat(pairs))
    }

    public func lookAgain() {}

    // MARK: Photos

    public func upload(_ copies: PhotoCopies, in pairs: Pairs) throws {
        uploadCount += 1
        if let failure = pendingFailure {
            pendingFailure = nil
            throw failure
        }
        if let failure = uploadFailures.removeValue(forKey: uploadCount) { throw failure }
        try store.upload(copies, in: pairs, as: seat(pairs), at: clock.now)
        for copy in copies.copies.values { photoOf[copy.name] = copies.photo }
    }

    public func download(_ copy: PhotoCopyName, of photo: AttachmentID, from sender: ParticipantID, in pairs: Pairs)
        -> Data?
    {
        downloadCount += 1
        return store.download(copy, from: sender, in: pairs, as: seat(pairs))
    }

    public func acknowledge(
        copy: PhotoCopyName, from sender: ParticipantID, with receipt: SealedReceipt, by device: DeviceID,
        in pairs: Pairs
    ) throws {
        attachmentAcknowledgeCount += 1
        try store.acknowledge(
            copy: copy, from: sender, with: receipt, by: device, in: pairs, as: seat(pairs), at: clock.now)
    }

    public func ownCopy(_ copy: PhotoCopyName, in pairs: Pairs) -> Data? {
        store.ownCopy(copy, in: pairs, as: seat(pairs))
    }

    public func storedCopies(in pairs: Pairs) -> [StoredPhotoCopy] {
        store.storedCopies(in: pairs, as: seat(pairs))
    }

    public func delete(copies: Set<PhotoCopyName>, in pairs: Pairs) {
        attachmentDeleteCount += 1
        store.delete(copies: copies, as: seat(pairs))
    }

    // MARK: What a test can reach in and do

    public func tamper(attachment id: AttachmentID, _ change: @Sendable (inout [String: PacketField]) -> Void) {
        for copy in copies(of: id) { store.change(copy.recordName, change, at: clock.now) }
    }

    public func tamper(packet id: PacketID, _ change: @Sendable (inout [String: PacketField]) -> Void) {
        store.change(id.rawValue.uuidString, change, at: clock.now)
    }

    public func forget(packet id: PacketID) { store.forgetPacket(id) }

    public func delete(packet id: PacketID) { store.forgetPacket(id) }

    public func forget(attachment id: AttachmentID) {
        for account in Set(store.spaces.values.map(\.account)) {
            for copy in copies(of: id) { store.remove(copy.recordName, fromEverySpaceIn: account) }
        }
    }

    public func failNextWrite(with error: MailboxError) { pendingFailure = error }

    public func failWrite(number: Int, with error: MailboxError) { packetFailures[writeCount + number] = error }

    public func failUpload(number: Int, with error: MailboxError) { uploadFailures[uploadCount + number] = error }

    public var largestPacketBytes: Int {
        packetRecords.compactMap { entry -> Int? in
            if case .data(let bytes)? = entry.record.fields[PacketWire.ciphertext] { return bytes.count }
            return nil
        }.max() ?? 0
    }

    public func storedCiphertextBytes(of packets: [PacketID]) -> Int {
        let wanted = Set(packets.map(\.rawValue.uuidString))
        return packetRecords.filter { wanted.contains($0.name) }.reduce(0) { total, entry in
            guard case .data(let body)? = entry.record.fields[PacketWire.ciphertext] else { return total }
            return total + body.count
        }
    }

    public func pendingRecipients(in pairs: Pairs) -> Set<RecipientTag> {
        store.sentPackets(in: pairs, as: seat(pairs)).values.reduce(into: Set<RecipientTag>()) { tags, sent in
            tags.formUnion(sent.recipients.subtracting(sent.receipts.map(\.tag)))
        }
    }
}

public actor RefusingGroupKeychainStore: KeychainStore {
    public struct Refused: Error {}

    private var items: [KeychainKey: Data] = [:]
    public private(set) var refusals = 0

    public var sharedGroupRefused: Bool

    public init(sharedGroupRefused: Bool = true) {
        self.sharedGroupRefused = sharedGroupRefused
    }

    public func data(for key: KeychainKey) throws -> Data? {
        if sharedGroupRefused { refusals += 1 }
        return items[key]
    }

    public func set(_ data: Data, for key: KeychainKey, scope: KeychainScope) throws {
        if sharedGroupRefused { refusals += 1 }
        items[key] = data
    }

    public func remove(_ key: KeychainKey) throws { items[key] = nil }
    public func removeAll(_ scope: KeychainScope) throws { if scope == .device { items = [:] } }
    public func protect(as protection: StorageProtection) throws {}
}

public actor UnreadableKeychainStore: KeychainStore {
    public struct Refused: Error {}

    private var items: [KeychainKey: Data] = [:]
    public private(set) var reads = 0

    public var readable: Bool

    public init(readable: Bool = false) { self.readable = readable }

    public func becomeReadable() { readable = true }

    public func becomeUnreadable() { readable = false }

    public func data(for key: KeychainKey) throws -> Data? {
        reads += 1
        guard readable else { throw Refused() }
        return items[key]
    }

    public func set(_ data: Data, for key: KeychainKey, scope: KeychainScope) throws {
        items[key] = data
    }

    public func remove(_ key: KeychainKey) throws { items[key] = nil }
    public func removeAll(_ scope: KeychainScope) throws { if scope == .device { items = [:] } }

    public func protect(as protection: StorageProtection) throws {
        guard readable else { throw Refused() }
    }
}

public actor FakeMediaScreen: MediaScreen {
    public struct CouldNotLook: Error {}
    public struct Unavailable: Error {}
    public struct NotAnImage: Error {}

    private var state: ScreeningAvailability
    public var sensitive: Set<Data> = []
    public var sensitiveVideos: Set<String> = []
    public var refuses = false
    public private(set) var looks = 0

    public init(availability: ScreeningAvailability = .available) {
        state = availability
    }

    public func availability() -> ScreeningAvailability { state }

    public func flag(_ data: Data) { sensitive.insert(data) }
    public func setRefuses(_ refuses: Bool) { self.refuses = refuses }

    public func isSensitive(image data: Data) throws -> Bool {
        looks += 1
        if refuses { throw CouldNotLook() }
        guard state == .available else { throw Unavailable() }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
        else { throw NotAnImage() }
        return sensitive.contains(data)
    }

    public func flagVideo(named name: String) { sensitiveVideos.insert(name) }

    public func isSensitive(videoAt url: URL) throws -> Bool {
        looks += 1
        if refuses { throw CouldNotLook() }
        guard state == .available else { throw Unavailable() }
        guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileReadNoSuchFile) }
        return sensitiveVideos.contains(url.lastPathComponent)
    }
}

public actor MemoryLogStore: LogStore {
    public struct Refused: Error {}

    private var records: [Data] = []
    public var isRefusing: Bool

    private let maximumRecordBytes: Int

    public private(set) var appendsAttempted = 0

    public init(
        refusing: Bool = false,
        maximumRecordBytes: Int = FileLogStore.defaultMaximumRecordBytes
    ) {
        isRefusing = refusing
        self.maximumRecordBytes = maximumRecordBytes
    }

    public func refuse(_ shouldRefuse: Bool) { isRefusing = shouldRefuse }

    public func append(_ entries: [Entry]) async throws {
        appendsAttempted += 1
        if isRefusing { throw Refused() }

        let encoder = JSONEncoder()
        var written: [Data] = []
        for entry in entries {
            let record = try encoder.encode(entry)
            guard record.count <= maximumRecordBytes else {
                throw StorageError.recordTooLarge
            }
            written.append(record)
        }
        records.append(contentsOf: written)
    }

    public func loadAll() async throws -> LoadedLog {
        let decoder = JSONDecoder()
        var entries: [Entry] = []
        var discarded = 0
        for record in records {
            if let entry = try? decoder.decode(Entry.self, from: record) {
                entries.append(entry)
            } else {
                discarded += record.count
            }
        }
        return LoadedLog(
            entries: entries, discardedBytes: discarded,
            termination: discarded > 0 ? .undecodableRecord : .complete)
    }

    public func removeAll() async throws { records = [] }

    @discardableResult
    public func removeEntries(where shouldRemove: @escaping @Sendable (Entry) -> Bool) async throws -> Int {
        if isRefusing { throw Refused() }
        let decoder = JSONDecoder()
        let before = records.count
        records.removeAll { record in
            (try? decoder.decode(Entry.self, from: record)).map(shouldRemove) ?? false
        }
        return before - records.count
    }

    public var stored: [Entry] {
        let decoder = JSONDecoder()
        return records.compactMap { try? decoder.decode(Entry.self, from: $0) }
    }
}

public enum WideID {
    public static func of(_ seed: [UInt8]) -> Data {
        var bytes = seed
        bytes.append(contentsOf: repeatElement(0, count: max(0, 32 - bytes.count)))
        return Data(bytes.prefix(32))
    }
}

public enum TestFounding {
    public static func room(
        named name: String = "Hangar 7", by founder: ParticipantID, as kind: RoomKind = .room
    ) throws -> (room: RoomID, profile: Payload) {
        let (room, founding) = RoomID.founding(by: founder, as: kind)
        return (room, try Payload.roomProfile(name: name, kind: kind, founding: founding))
    }
}

public enum TestInvite {
    public static func nonce(for joinerKeys: IdentityPublicKeys) -> Data {
        Data(SHA256.hash(data: Data("carpenter.test-nonce".utf8) + joinerKeys.signing))
    }

    public static func nonce(for attestation: MembershipAttestation) -> Data {
        nonce(for: attestation.joinerKeys)
    }

    public static func issue(
        joining room: RoomID,
        joinerKeys: IdentityPublicKeys,
        by identity: Identity,
        at issuedAt: Date,
        lifetime: TimeInterval = MembershipAttestation.defaultLifetime,
        joinerRequires: PhraseLength = .standard,
        inviterRequires: PhraseLength = .standard
    ) throws -> MembershipAttestation {
        try MembershipAttestation.issue(
            joining: room, joinerKeys: joinerKeys, by: identity, at: issuedAt, lifetime: lifetime,
            joinerCommitment: JoinCommitment.of(nonce(for: joinerKeys)),
            joinerRequires: joinerRequires, inviterRequires: inviterRequires)
    }

    public static func issue(
        joining room: RoomID,
        joinerKeys: IdentityPublicKeys,
        by identity: Identity,
        at issuedAt: Date,
        lasting lifetime: InvitationLifetime
    ) throws -> MembershipAttestation {
        try MembershipAttestation.issue(
            joining: room, joinerKeys: joinerKeys, by: identity, at: issuedAt, lasting: lifetime,
            joinerCommitment: JoinCommitment.of(nonce(for: joinerKeys)))
    }
}

extension MembershipAttestation {
    public var testPhrase: String {
        verificationPhrase(opening: TestInvite.nonce(for: self)) ?? ""
    }
}

extension JoinConfirmedBody {
    public static func signed(
        confirming attestation: MembershipAttestation, by identity: Identity
    ) throws -> JoinConfirmedBody {
        try signed(
            confirming: attestation, opening: TestInvite.nonce(for: attestation), by: identity)
    }
}
