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

public final class SeededRandomSource: RandomSource {
    private let state: Mutex<UInt64>

    public init(seed: UInt64) {
        state = Mutex(seed)
    }

    public func bytes(count: Int) -> Data {
        state.withLock { state in
            var output = Data(capacity: count)
            while output.count < count {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                z ^= z >> 31
                withUnsafeBytes(of: z.littleEndian) { output.append(contentsOf: $0) }
            }
            return output.prefix(count)
        }
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

    private let synced: Synced
    private var local: [KeychainKey: Data] = [:]

    public private(set) var writes = 0

    public init(syncingThrough synced: Synced = Synced()) {
        self.synced = synced
    }

    public func sibling() -> InMemoryKeychainStore {
        InMemoryKeychainStore(syncingThrough: synced)
    }

    public func data(for key: KeychainKey) async throws -> Data? {
        if let data = local[key] { return data }
        return await synced.item(key)
    }

    public func set(_ data: Data, for key: KeychainKey, scope: KeychainScope) async throws {
        writes += 1
        switch scope {
        case .synchronized:
            local[key] = nil
            await synced.set(data, for: key)
        case .device:
            local[key] = data
            await synced.set(nil, for: key)
        }
    }

    public func remove(_ key: KeychainKey) async throws {
        local[key] = nil
        await synced.set(nil, for: key)
    }

    public func removeAll() async throws {
        local = [:]
        await synced.clear()
    }

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
                receipts: (before?.receipts ?? []) + (copy.receipt.map { [$0] } ?? []))
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
        try store.ring(peer, in: pairs, as: seat(pairs), at: clock.now)
        rings.append(Ring(from: pairs.me, to: peer))
    }

    public func fetch(from peer: ParticipantID, for tags: Set<RecipientTag>, in pairs: Pairs) -> [SyncPacket] {
        fetchCount += 1
        return store.fetch(from: peer, for: tags, in: pairs, as: seat(pairs))
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
        copy: PhotoCopyName, from sender: ParticipantID, with receipt: SealedReceipt, in pairs: Pairs
    ) throws {
        attachmentAcknowledgeCount += 1
        try store.acknowledge(copy: copy, from: sender, with: receipt, in: pairs, as: seat(pairs), at: clock.now)
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
    public func removeAll() throws { items = [:] }
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
    public func removeAll() throws { items = [:] }
}

public actor FailingMailbox: Mailbox, MediaMailbox {
    public struct Refused: Error {}

    public init() {}

    public func account(in pairs: Pairs) async throws -> String { throw Refused() }
    public func space(for peer: ParticipantID, naming account: String?, in pairs: Pairs) async throws -> URL {
        throw Refused()
    }
    public func spaceForACode(in pairs: Pairs) async throws -> URL { throw Refused() }
    public func claim(_ url: URL, for peer: ParticipantID, naming account: String?, in pairs: Pairs) async throws
        -> URL
    { throw Refused() }
    public func join(_ link: PairLink, of peer: ParticipantID, in pairs: Pairs) async throws -> JoinOutcome {
        throw Refused()
    }
    public func reads(_ peer: ParticipantID, in pairs: Pairs) async throws -> Bool { throw Refused() }
    public func close(_ peer: ParticipantID, in pairs: Pairs) async throws { throw Refused() }
    public func put(_ packet: SyncPacket, to peer: ParticipantID, in pairs: Pairs) async throws { throw Refused() }
    public func ring(_ peer: ParticipantID, in pairs: Pairs) async throws { throw Refused() }
    public func fetch(from peer: ParticipantID, for tags: Set<RecipientTag>, in pairs: Pairs) async throws
        -> [SyncPacket]
    { throw Refused() }
    public func acknowledge(_ id: PacketID, from peer: ParticipantID, with receipt: SealedReceipt, in pairs: Pairs)
        async throws
    { throw Refused() }
    public func sentPackets(in pairs: Pairs) async throws -> [PacketID: SentPacket] { throw Refused() }
    public func withdraw(_ id: PacketID, in pairs: Pairs) async throws { throw Refused() }
    public func upload(_ copies: PhotoCopies, in pairs: Pairs) async throws { throw Refused() }
    public func download(_ copy: PhotoCopyName, of photo: AttachmentID, from sender: ParticipantID, in pairs: Pairs)
        async throws -> Data?
    { throw Refused() }
    public func acknowledge(
        copy: PhotoCopyName, from sender: ParticipantID, with receipt: SealedReceipt, in pairs: Pairs
    ) async throws { throw Refused() }
    public func storedCopies(in pairs: Pairs) async throws -> [StoredPhotoCopy] { throw Refused() }
    public func delete(copies: Set<PhotoCopyName>, in pairs: Pairs) async throws { throw Refused() }
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
                throw StorageError.unreadable
            }
            written.append(record)
        }
        records.append(contentsOf: written)
    }

    public func loadAll() async throws -> LoadedLog {
        let decoder = JSONDecoder()
        var entries: [Entry] = []
        for record in records {
            guard let entry = try? decoder.decode(Entry.self, from: record) else {
                return LoadedLog(
                    entries: entries, discardedTrailingBytes: record.count,
                    termination: .undecodableRecord)
            }
            entries.append(entry)
        }
        return LoadedLog(entries: entries, discardedTrailingBytes: 0, termination: .complete)
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
