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
    private struct Item {
        let data: Data
        let scope: KeychainScope
    }

    private var items: [KeychainKey: Item] = [:]

    public init() {}

    public func data(for key: KeychainKey) throws -> Data? { items[key]?.data }

    public func set(_ data: Data, for key: KeychainKey, scope: KeychainScope) throws {
        items[key] = Item(data: data, scope: scope)
    }

    public func remove(_ key: KeychainKey) throws { items[key] = nil }

    public func removeAll() throws { items = [:] }

    public func scope(for key: KeychainKey) -> KeychainScope? { items[key]?.scope }

    public var synchronizedItems: [KeychainKey: Data] {
        items
            .filter { $0.value.scope == .synchronized }
            .mapValues(\.data)
    }
}

public actor InMemoryMailbox: Mailbox, MediaMailbox {
    private struct Stored {
        var fields: [String: PacketField]
        var outstanding: Set<RecipientTag>
        var storedAt: Date = .distantPast
    }

    private let clock: any Clock

    private var stored: [PacketID: Stored] = [:]
    private var order: [PacketID] = []
    public var writtenPackets: [PacketID] { order }
    private var attachments: [AttachmentID: Stored] = [:]
    private var pendingFailure: MailboxError?
    private var packetFailures: [Int: MailboxError] = [:]
    private var uploadFailures: [Int: MailboxError] = [:]

    public private(set) var writeCount = 0
    public private(set) var fetchCount = 0
    public private(set) var acknowledgeCount = 0
    public private(set) var bells: [MessageBell] = []
    public private(set) var uploadCount = 0
    public private(set) var downloadCount = 0
    public private(set) var attachmentAcknowledgeCount = 0
    public private(set) var attachmentDeleteCount = 0

    public init(clock: any Clock = SystemClock()) {
        self.clock = clock
    }

    public var storedPacketCount: Int { stored.count }

    public var storedWireBytes: [Data] {
        order.compactMap { stored[$0] }.flatMap(\.fields.values).flatMap { field -> [Data] in
            switch field {
            case .string(let text): [Data(text.utf8)]
            case .data(let data): [data]
            case .dataList(let list): list
            }
        }
    }
    public var storedAttachmentCount: Int { attachments.count }

    public var serverWrites: Int {
        writeCount + acknowledgeCount + bells.count + uploadCount + attachmentAcknowledgeCount
            + attachmentDeleteCount
    }

    // MARK: Attachments

    public func upload(_ attachment: OutgoingAttachment) throws {
        uploadCount += 1
        if let failure = pendingFailure {
            pendingFailure = nil
            throw failure
        }
        if let failure = uploadFailures.removeValue(forKey: uploadCount) { throw failure }
        attachments[attachment.id] = Stored(
            fields: AttachmentWire.fields(of: attachment), outstanding: attachment.recipients,
            storedAt: clock.now)
    }

    public func download(_ id: AttachmentID, hint tags: Set<RecipientTag>) throws -> Data? {
        downloadCount += 1
        guard let entry = attachments[id] else { return nil }
        guard tags.isEmpty || !entry.outstanding.isDisjoint(with: tags) else { return nil }
        return AttachmentWire.attachment(from: entry.fields)?.ciphertext
    }

    public func acknowledge(attachment id: AttachmentID, by tags: Set<RecipientTag>) throws {
        guard var entry = attachments[id] else { throw MailboxError.unknownPacket }
        attachmentAcknowledgeCount += 1
        entry.outstanding.subtract(tags)
        if entry.outstanding.isEmpty {
            attachments[id] = nil
        } else {
            attachments[id] = entry
        }
    }

    public func pendingAttachments() throws -> [AttachmentID: Set<RecipientTag>] {
        attachments.reduce(into: [:]) { found, entry in found[entry.key] = entry.value.outstanding }
    }

    public func sweepableAttachments() throws -> [AttachmentID: Set<RecipientTag>] {
        let settled = clock.now.addingTimeInterval(-MailboxRules.sweepAge)
        return attachments.reduce(into: [:]) { found, entry in
            guard entry.value.storedAt < settled else { return }
            found[entry.key] = entry.value.outstanding
        }
    }

    public func delete(attachment id: AttachmentID) throws {
        attachmentDeleteCount += 1
        attachments[id] = nil
    }

    public func forget(packet id: PacketID) {
        stored[id] = nil
        order.removeAll { $0 == id }
    }

    public func forget(attachment id: AttachmentID) {
        attachments[id] = nil
    }

    public func failNextWrite(with error: MailboxError) {
        pendingFailure = error
    }

    public func failWrite(number: Int, with error: MailboxError) {
        packetFailures[writeCount + number] = error
    }

    public func failUpload(number: Int, with error: MailboxError) {
        uploadFailures[uploadCount + number] = error
    }

    public var largestPacketBytes: Int {
        stored.values.compactMap { entry -> Int? in
            if case .data(let bytes)? = entry.fields[PacketWire.ciphertext] { return bytes.count }
            return nil
        }.max() ?? 0
    }

    public func put(_ packet: SyncPacket) throws {
        writeCount += 1
        if let failure = pendingFailure {
            pendingFailure = nil
            throw failure
        }
        if let failure = packetFailures.removeValue(forKey: writeCount) { throw failure }
        let fields = PacketWire.fields(of: packet)
        let weight = MailboxRules.weigh(fields)
        guard weight <= MailboxRules.recordByteCeiling else {
            throw MailboxError.recordTooLarge(
                bytes: weight, ceiling: MailboxRules.recordByteCeiling)
        }
        stored[packet.id] = Stored(
            fields: fields, outstanding: packet.recipients, storedAt: clock.now)
        order.append(packet.id)
    }

    public func fetch(for tags: Set<RecipientTag>) throws -> [SyncPacket] {
        fetchCount += 1
        return order.compactMap { stored[$0] }
            .filter { !$0.outstanding.isDisjoint(with: tags) }
            .compactMap { PacketWire.packet(from: $0.fields) }
    }

    public func pendingDeliveries() throws -> [PacketID: Set<RecipientTag>] {
        stored.reduce(into: [:]) { found, entry in found[entry.key] = entry.value.outstanding }
    }

    public func acknowledge(_ id: PacketID, by tags: Set<RecipientTag>) throws {
        guard var entry = stored[id] else { throw MailboxError.unknownPacket }
        acknowledgeCount += 1

        entry.outstanding.subtract(tags)
        if entry.outstanding.isEmpty {
            stored[id] = nil
            order.removeAll { $0 == id }
        } else {
            stored[id] = entry
        }
    }

    public func ring(_ bell: MessageBell) throws { bells.append(bell) }
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

    public func put(_ packet: SyncPacket) async throws { throw Refused() }
    public func fetch(for tags: Set<RecipientTag>) async throws -> [SyncPacket] { throw Refused() }
    public func acknowledge(_ id: PacketID, by tags: Set<RecipientTag>) async throws { throw Refused() }
    public func pendingDeliveries() async throws -> [PacketID: Set<RecipientTag>] { throw Refused() }
    public func ring(_ bell: MessageBell) async throws { throw Refused() }
    public func upload(_ attachment: OutgoingAttachment) async throws { throw Refused() }
    public func download(_ id: AttachmentID, hint tags: Set<RecipientTag>) async throws -> Data? {
        throw Refused()
    }
    public func acknowledge(attachment id: AttachmentID, by tags: Set<RecipientTag>) async throws {
        throw Refused()
    }
    public func sweepableAttachments() async throws -> [AttachmentID: Set<RecipientTag>] {
        throw Refused()
    }

    public func pendingAttachments() async throws -> [AttachmentID: Set<RecipientTag>] {
        throw Refused()
    }
    public func delete(attachment id: AttachmentID) async throws { throw Refused() }
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
    public func setAvailability(_ availability: ScreeningAvailability) { state = availability }

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

/// A `ParticipantID` and a `DeviceID` are SHA256 digests, always 32 bytes, and `FeedKey` leans on
/// that: it concatenates the two without length prefixes, so a fixture of some other width is a
/// fixture that could not exist in the app. Decoding now refuses one.
///
/// Test fixtures used to be written as `Data([1])` because nothing stopped them. `WideID.of([1])`
/// keeps the seed bytes at the front — so a failure still reads as "the one starting 01" — and pads
/// to the width the real thing has.
public enum WideID {
    public static func of(_ seed: [UInt8]) -> Data {
        var bytes = seed
        bytes.append(contentsOf: repeatElement(0, count: max(0, 32 - bytes.count)))
        return Data(bytes.prefix(32))
    }
}

/// Invitations for tests, with a commitment that can be opened again later.
///
/// Every real invitation carries `SHA256` of a nonce the joiner picked, and the verification phrase
/// cannot be computed without that nonce — which is the whole point, because it leaves the inviter
/// nothing to grind with. A test that built an attestation by hand had no nonce to hand back.
///
/// So the nonce here is **derived from the joiner's own signing key** rather than random: any test,
/// anywhere, can recover it from the attestation without having threaded it through. That is safe
/// precisely because it is not safe — a predictable nonce is exactly what the commitment is supposed
/// to prevent, so this must never leave the testing module.
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
    /// The phrase, opened with the testing nonce. `nil` in production terms means "not yet".
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
