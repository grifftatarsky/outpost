import CarpenterKit
import CryptoKit
import Foundation

public struct SessionStorage: Sendable {
    public let keychain: any KeychainStore
    public let log: any LogStore
    public let documents: any DocumentStore
    public let media: any MediaStore
    public let protection: ProtectionDial
    public let locations: [URL]

    public init(
        keychain: any KeychainStore, log: any LogStore, documents: any DocumentStore,
        media: any MediaStore = MemoryMediaStore(), protection: ProtectionDial = ProtectionDial(),
        locations: [URL] = []
    ) {
        self.keychain = keychain
        self.log = log
        self.documents = documents
        self.media = media
        self.protection = protection
        self.locations = locations
    }

    public var readOnly: SessionStorage {
        SessionStorage(
            keychain: ReadOnlyKeychainStore(keychain), log: ReadOnlyLogStore(log),
            documents: ReadOnlyDocumentStore(documents), media: media, protection: protection)
    }
}

@MainActor
@Observable
public final class AppSession {
    public enum State: Equatable, Sendable {
        case loading
        case checkingForRegistration
        case needsIdentity
        case needsProfile
        case ready
        case failed(String)
        case registrationStalled(RegistrationStall)
        case awaitingApproval
        case removed
    }

    public internal(set) var state: State = .loading
    public internal(set) var rooms: [RoomSummary] = []

    var roomsThisMemberIsIn: Set<RoomID> = []
    public internal(set) var organisation = RoomsListOrganisation()

    public internal(set) var enrolment: Enrolment?

    public internal(set) var isHeldByICloud = false

    public internal(set) var phoneIsLocked = false
    public internal(set) var waitsForUnlock = false
    public internal(set) var protectionChoice: ProtectionChoice?

    public internal(set) var pendingDevice: DeviceKeys?
    var pendingIdentity: Identity?
    var unsavedRecoveryKey: RecoverySecret?
    public internal(set) var deviceRequests: [DeviceRequest] = []
    var declinedDeviceRequests: Set<DeviceID> = []

    public var thisDeviceID: DeviceID? { enrolment?.device.id ?? pendingDevice?.id }

    public var approvalCode: String? { pendingDevice.map { DeviceRequest(for: $0).code } }

    public internal(set) var forks: [Fork] = []

    public internal(set) var lastLoad: LogTermination = .complete

    public internal(set) var cannotSend: MailboxFailure?

    public internal(set) var integrity = IntegrityReport()

    public var entryCount: Int { replica.entryCount }

    let storage: SessionStorage
    let clock: any Clock

    var persisted = PersistedState()
    var replica = Replica() {
        didSet {
            guard replica.revision != projectedRevision else { return }
            projectedRevision = replica.revision
            logChanged()
        }
    }
    @ObservationIgnored private var projectedRevision: UUID?
    var chains: [RoomID: EpochChain] = [:] {
        didSet {
            if OpenedPayloads.keysWereForgotten(from: oldValue, to: chains) { openedPayloads.forget() }
            logChanged()
        }
    }
    @ObservationIgnored let openedPayloads = OpenedPayloads()

    private(set) var projectionGeneration = 0

    @ObservationIgnored var cachedProjection: Projection?
    @ObservationIgnored var cachedEntries: [EntryHash: Entry]?
    @ObservationIgnored var cachedRosters: [RoomID: RoomRoster] = [:]
    @ObservationIgnored var cachedOutOfRoom: [RoomID: Set<EntryHash>] = [:]
    @ObservationIgnored var cachedReadEvidence: [RoomID: ReadEvidence] = [:]
    @ObservationIgnored var cachedPositions: [RoomID: [MessageID: Int]] = [:]
    @ObservationIgnored var cachedReporting: [RoomID: Set<ParticipantID>] = [:]
    @ObservationIgnored var cachedWritingKeys: [RoomID: WritingKey?] = [:]
    @ObservationIgnored var cachedOutpostAccess: OutpostAccess?
    @ObservationIgnored var cachedDevicesAdded: [RoomID: [AddedDevice]] = [:]
    @ObservationIgnored var cachedComparisonHalves: [ParticipantID: String] = [:]
    @ObservationIgnored var cachedPairwise: [ParticipantID: PairwiseSecret] = [:]
    @ObservationIgnored var cachedLinksHeard: [ParticipantID: [PairLink]]?
    @ObservationIgnored var pairingUp: Task<Void, Never>?
    @ObservationIgnored var addressBook = AddressBook()
    @ObservationIgnored var addressBookLoaded = false
    @ObservationIgnored var addressBookWriting: Task<Bool, Never>?

    public internal(set) var codeForSharing = ""

    @ObservationIgnored private(set) var projectionBuilds = 0

    func cached<Key: Hashable, Value>(
        _ store: ReferenceWritableKeyPath<AppSession, [Key: Value]>, _ key: Key, _ build: () -> Value
    ) -> Value {
        _ = projectionGeneration
        if let known = self[keyPath: store][key] { return known }
        let built = build()
        self[keyPath: store][key] = built
        return built
    }

    func update<Value: Equatable>(_ state: ReferenceWritableKeyPath<AppSession, Value>, to value: Value) {
        if self[keyPath: state] != value { self[keyPath: state] = value }
    }

    func projectionInputsChanged() {
        cachedProjection = nil
        projectionGeneration &+= 1
    }

    func logChanged() {
        projectionGeneration &+= 1
        cachedProjection = nil
        cachedEntries = nil
        cachedRosters = [:]
        cachedOutOfRoom = [:]
        cachedReadEvidence = [:]
        cachedPositions = [:]
        cachedReporting = [:]
        cachedWritingKeys = [:]
        cachedOutpostAccess = nil
        cachedDevicesAdded = [:]
        cachedLinksHeard = nil
    }
    var viewMayBeStale = false

    var entriesNotWrittenDown: [Entry] = []

    var head: EntryLink?
    var roomHeads: [RoomID: EntryLink] = [:]
    var accountRegistry: (any AccountRegistry)?

    var issuedGrants: Set<String> = []

    var roomsWithUnsentMessages: Set<RoomID> = []

    var unsentWallPosts: Set<EntryHash> = []

    var wallsWrittenOn: Set<ParticipantID> = []

    var notifyWallsSent: [ParticipantID]?

    var attachmentTasks: [AttachmentID: Task<Data?, any Error>] = [:]
    var hasAskedForWall: Set<ParticipantID> = []
    public internal(set) var peersLastRound: Set<ParticipantID> = []
    var pendingRecipients: [PacketID: Set<RecipientTag>]?

    public internal(set) var metSomebodyNew = false
    var attachmentRetryAfter: [AttachmentID: Date] = [:]
    var attachmentAcknowledgementsOwed: [AttachmentID: OwedPhotoReceipt] = [:]
    var uploading: Set<AttachmentID> = []
    var sweptAttachments = false

    public let denyList: DenyList
    public var enforcesDenyList = true { didSet { if enforcesDenyList != oldValue { refresh() } } }

    public var distribution: DistributionChannel = .appStore

    var furthestSeen: [RoomID: MessageID] = [:]

    var arrivalDelays: [EntryHash: TimeInterval] = [:]

    var publishing = false
    var publishAgain = false

    var stateWrites: Task<Void, any Error>?
    var stateOnDisk: PersistedState?

    func saveState() async throws {
        keepAuthorityTimes()
        let previous = stateWrites
        let write = Task { @MainActor [self] in
            _ = try? await previous?.value
            let state = persisted
            guard state != stateOnDisk else { return }
            try await storage.documents.save(state)
            stateOnDisk = state
        }
        stateWrites = write
        try await write.value
    }

    public internal(set) var cameBackFromARecoveryKey = false
    public internal(set) var isSilenced = false
    var deviceSync: (any EntrySync)?
    var incomingTask: Task<Void, Never>?
    var protectionWork: Task<Void, Error>?

    public func arrivalDelay(of message: MessageID) -> TimeInterval? {
        arrivalDelays[message.entry]
    }

    func peersToRing(in rooms: Set<RoomID>) -> [Peer] {
        guard !rooms.isEmpty, let me = enrolment?.identity.id else { return [] }

        let audience = rooms.reduce(into: Set<ParticipantID>()) { people, room in
            let roster = roster(of: room)
            people.formUnion(notShutOut(roster.rewrapTargets(of: me)))
            people.formUnion(notShutOut(Set(roster.requests.keys)))
        }
        let ringing = peers().filter { audience.contains($0.them) }

        if ringing.isEmpty {
            Diagnostics.sync.error(
                "mailbox: a message went out with nobody to ring — this room's roster names no peers")
        }
        return ringing
    }

    public init(
        storage: SessionStorage, clock: any Clock = SystemClock(),
        denyList: DenyList = DenyList.bundled()
    ) {
        self.storage = storage
        self.clock = clock
        self.denyList = denyList
    }

    public func checkAccount(with registry: any AccountRegistry) {
        accountRegistry = registry
    }

    public var viewer: Member {
        guard let enrolment else { return Member.placeholder(ParticipantID(rawValue: Data())) }
        if let own = persisted.preferences.displayName?.value, !own.isEmpty {
            return Member(id: enrolment.identity.id, displayName: own)
        }
        return projection.member(enrolment.identity.id)
    }

    var ownDisplayName: String? {
        if let own = persisted.preferences.displayName?.value, !own.isEmpty { return own }
        return enrolment.flatMap { projection.members[$0.identity.id]?.displayName }
    }

    var hasOwnName: Bool { ownDisplayName != nil }

    // MARK: Internals

    var projection: Projection {
        _ = projectionGeneration
        if let cachedProjection { return cachedProjection }
        var built = Projection(
            viewer: enrolment?.identity.id ?? ParticipantID(rawValue: Data()),
            rendered: LogRenderer.render(replica.allEntries, reading: renderStepReader()),
            chains: RoomChains(replica.allEntries),
            claimTimes: persisted.claimTimes,
            revealsNames: persisted.preferences.isShowingOthersNames,
            viewerName: persisted.preferences.displayName?.value,
            nicknames: persisted.preferences.currentNicknames,
            anonPersona: persisted.preferences.anonPersona
        )
        let opener = payloadOpener()
        let rosters = built.rosters(opening: opener)
        let access = enrolment.map { built.outpostAccess(of: $0.identity.id, opening: opener) }
        built.onlyName(peopleMet(in: built, rosters: rosters, access: access))
        cachedProjection = built
        cachedRosters = rosters
        cachedOutpostAccess = access
        projectionBuilds += 1
        return built
    }

    func peopleMet(
        in projected: Projection, rosters: [RoomID: RoomRoster], access: OutpostAccess?
    ) -> Set<ParticipantID> {
        guard let me = enrolment?.identity.id, let access else { return [] }
        var met = Projection.people(in: rosters)
        met.formUnion(access.audience(at: clock.now))
        met.formUnion(projected.outpostAuthors().map(\.id))
        met.formUnion(persisted.acceptedInvitations.map(\.attestation.inviter))
        met.insert(me)
        return met
    }

    public func hasMet(_ person: ParticipantID) -> Bool {
        projection.met?.contains(person) ?? true
    }

    var entriesByHash: [EntryHash: Entry] {
        _ = projectionGeneration
        if let cachedEntries { return cachedEntries }
        let built = Dictionary(
            replica.allEntries.map { ($0.hash, $0) }, uniquingKeysWith: { first, _ in first })
        cachedEntries = built
        return built
    }

    func appendToWall(of owner: ParticipantID, _ payload: Payload) async throws {
        guard let enrolment else { throw AppSessionError.noIdentity }
        guard owner != enrolment.identity.id else { return try await append(payload, to: nil) }

        if !(persisted.preferences.outpostStanding ?? .open).reachesThePostsReaders {
            guard let theirs = legacySecret(with: owner) else {
                throw AppSessionError.cannotWriteThere
            }
            return try await append(payload, to: nil, alsoFor: theirs)
        }

        let wall = outpostRoom(for: owner)
        guard chains[wall] != nil else { throw AppSessionError.cannotWriteThere }
        try await append(payload, to: wall, isWall: true)
    }

    func append(
        _ payload: Payload, to room: RoomID?, isWall: Bool = false,
        alsoFor extra: PairwiseSecret? = nil, readableAt readable: EpochNumber? = nil
    ) async throws {
        guard let enrolment else { throw AppSessionError.noIdentity }

        if let room, !isWall {
            let roster = roster(of: room)
            if roster.departure(of: enrolment.identity.id) != nil {
                throw MembershipError.leftThisRoom
            }
            if !roster.mayWrite(enrolment.identity.id) {
                throw MembershipError.removedFromThisRoom
            }
            if !PayloadType.plumbing.contains(payload.type), !canWrite(in: room) {
                throw MembershipError.soloNotVerified
            }
        }

        defer { sendOwnEntries() }

        let chainRoom = room ?? outpostRoom(for: enrolment.identity.id)
        if chains[chainRoom] == nil {
            let (chain, secret) = EpochChain.create(room: chainRoom)
            chains[chainRoom] = chain
            try await persistEpoch(secret, at: .initial, for: chainRoom)
        }
        if persisted.rekeyBeforeWriting.contains(chainRoom) { try await rekeyBeforeWriting(chainRoom) }
        guard let chain = chains[chainRoom] else { throw AppSessionError.noIdentity }
        let writing = writingKey(of: chainRoom)

        let entry = try Entry.append(
            after: head,
            author: enrolment.identity.id,
            device: enrolment.device,
            clock: replica.frontier,
            wallTime: clock.now,
            room: room,
            payload: payload,
            at: readable ?? writing?.epoch ?? chain.highestKnownEpoch ?? .initial,
            sealedWith: readable == nil ? (writing.map { chain.choosing($0.secret, at: $0.epoch) } ?? chain) : chain,
            alsoFor: extra,
            roomLink: room.map { RoomLink(previous: roomHeads[$0]?.hash) }
        )
        guard SyncSession.fitsAPacket(entry) else { throw AppSessionError.tooBigToSend }

        if case .forked(let fork) = try replica.integrate(entry) { forks.append(fork) }
        head = entry.link
        if let room { roomHeads[room] = entry.link }
        try await storage.log.append([entry])
        refresh()
    }

    func restoreLog(identity: Identity) async throws {
        replica = Replica()
        replica.introduce(identity.publicKeys)
        roomHeads = [:]

        for keys in persisted.knownKeys { replica.introduce(keys) }
        for certificate in persisted.certificates {
            guard let at = storedTime(for: certificate.digest, claimed: certificate.issuedAt) else {
                Diagnostics.identity.error("authority: a saved certificate had no stored time and was left out")
                continue
            }
            try? replica.admit(certificate, storedAt: at)
        }

        for revocation in persisted.revocations + persisted.otherRevocations {
            guard let at = storedTime(for: revocation.digest, claimed: revocation.revokedAt) else {
                Diagnostics.identity.error("authority: a saved removal had no stored time and was left out")
                continue
            }
            try? replica.revoke(revocation, storedAt: at)
        }
        if enrolment != nil { recordAuthority() }
        replica.restore(spent: persisted.spentEntries, closing: persisted.preferences.roomsDeleted)

        let loaded = try await storage.log.loadAll()
        lastLoad = loaded.termination
        integrity = IntegrityReport()
        integrity.lastLoad = loaded.termination
        integrity.discardedBytes = loaded.discardedTrailingBytes

        let checked = await replica.signatureChecks(for: loaded.entries)
        let ownFeed = enrolment.map { FeedKey(author: $0.identity.id, device: $0.device.id) }
        var stillOnDisk: [Entry] = []
        for entry in loaded.entries {
            let outcome: IntegrationResult
            do {
                outcome = try replica.integrate(entry, checked: checked)
            } catch {
                integrity.unverifiableOnDisk += 1
                continue
            }
            if case .forked(let fork) = outcome {
                forks.append(fork)
            }
            if entry.feedKey == ownFeed {
                head = entry.link
                if let room = entry.room { noteOwn(entry.link, in: room) }
            }
            if let room = entry.room, replica.closedRooms.contains(room) {
                stillOnDisk.append(entry)
            }
        }
        if let ownFeed, let spentTop = replica.spentLink(atTopOf: ownFeed),
            spentTop.seq > head?.seq ?? 0
        {
            head = spentTop
        }
        for spent in replica.spentEntries where spent.feed == ownFeed {
            if let room = spent.room { noteOwn(spent.link, in: room) }
        }
        persisted.spentEntries = replica.spentEntries

        try await restoreEpochs()

        let unfinished = replica.closedRooms.filter {
            persisted.knownRooms.contains($0) || persisted.epochs[$0] != nil
        }
        await finishDeleting(unfinished.union(stillOnDisk.compactMap(\.room)), removing: stillOnDisk)

        for room in persisted.knownRooms where chains[room] != nil {
            try await unwindEpochs(in: room, bounded: walkStopsShort(in: room))
        }

        integrity.forks = replica.forks
        refresh()
    }

    private func noteOwn(_ link: EntryLink, in room: RoomID) {
        if (roomHeads[room]?.seq ?? 0) < link.seq { roomHeads[room] = link }
    }

    func refresh() {
        prepareCodeForSharing()
        var projected = projection
        if introduceEstablishedMembers(in: projected, opening: payloadOpener()) {
            projected = projection
        }

        let hidden = persisted.preferences.hiddenEntries
        let shutOut = shutOutAuthors()
        let me = enrolment?.identity.id
        var joined: Set<RoomID> = []
        let summaries: [RoomSummary] = projected.roomIDs().compactMap { room in
            let roster = roster(of: room)
            if let me, roster.members.contains(me) { joined.insert(room) }
            let blocked = projected.entries(by: shutOut, in: room)
            return projected.summary(
                of: room,
                memberCount: roster.members.count,
                others: roster.members.union(roster.requests.keys)
                    .filter { $0 != me }
                    .sorted { $0.rawValue.lexicographicallyPrecedes($1.rawValue) },
                unreadFor: me,
                readThrough: persisted.readThrough[room],
                undrawn: hidden.union(outOfRoom(in: room, of: projected)).union(blocked))
        }
        update(\.rooms, to: summaries)
        update(\.roomsThisMemberIsIn, to: joined)
        var organised = organisation
        organised.forgetRoomsMissing(from: Set(rooms.map(\.id)).union(awaitingAdmission.map(\.room)))
        update(\.organisation, to: organised)
    }

    @discardableResult
    func introduceEstablishedMembers(
        in projected: Projection, opening: (RenderedEntry) -> Payload?
    ) -> Bool {
        var introduced = false
        for room in projected.namedRoomIDs() {
            let roster = introduced ? projected.roster(of: room, opening: opening) : roster(of: room)
            for attestation in roster.requests.values {
                guard !replica.knownParticipants.contains(attestation.joinerKeys.participantID)
                else { continue }
                replica.introduce(attestation.joinerKeys)
                introduced = true
                if !persisted.knownKeys.contains(attestation.joinerKeys) {
                    persisted.knownKeys.append(attestation.joinerKeys)
                }
            }
        }
        return introduced
    }

    // MARK: Epoch persistence

    func persistEpoch(
        _ secret: EpochSecret, at epoch: EpochNumber, for room: RoomID
    ) async throws {
        var keys = chains[room]?.heldSecrets(at: epoch) ?? []
        if !keys.contains(secret) { keys.insert(secret, at: 0) }
        try await storage.keychain.set(Self.keychainForm(of: keys), for: Self.epochKey(room, epoch), scope: .device)

        if !persisted.knownRooms.contains(room) { persisted.knownRooms.append(room) }
        var held = persisted.epochs[room] ?? []
        if !held.contains(epoch.rawValue) { held.append(epoch.rawValue) }
        persisted.epochs[room] = held.sorted()
        persisted.organisation = organisation
        try await saveState()
    }

    func restoreEpochs() async throws {
        for room in persisted.knownRooms {
            var chain = EpochChain(room: room)
            var found = false

            for raw in persisted.epochs[room] ?? [] {
                let epoch = EpochNumber(rawValue: raw)
                guard let stored = try await storage.keychain.data(for: Self.epochKey(room, epoch))
                else { continue }
                let keys = Self.keys(inKeychainForm: stored)
                chain.adopt(keys[0], at: epoch)
                for rival in keys.dropFirst() { chain.hold(rival, at: epoch) }
                found = true
            }

            if found { chains[room] = chain }
        }
    }

    static func epochKey(_ room: RoomID, _ epoch: EpochNumber) -> KeychainKey {
        KeychainKey("epoch.\(room.rawValue.uuidString).\(epoch.rawValue)")
    }

    static func keychainForm(of keys: [EpochSecret]) -> Data {
        guard keys.count > 1, let list = try? JSONEncoder().encode(keys.map(\.material)) else {
            return keys.first?.material ?? Data()
        }
        return list
    }

    static func keys(inKeychainForm stored: Data) -> [EpochSecret] {
        guard stored.count != 32, let list = try? JSONDecoder().decode([Data].self, from: stored), !list.isEmpty
        else { return [EpochSecret(material: stored)] }
        return list.map(EpochSecret.init(material:))
    }

    func outpostRoom(for participant: ParticipantID) -> RoomID {
        RoomID.outpost(of: participant)
    }

    func walkStopsShort(in room: RoomID) -> Bool {
        guard let me = enrolment?.identity.id, room != outpostRoom(for: me) else { return false }
        guard let owner = replica.knownParticipants.first(where: { outpostRoom(for: $0) == room })
        else { return false }
        guard let floor = projection.outpostFloors(of: owner, opening: payloadOpener())[me]
        else { return false }
        return floor != nil
    }

    func chain(sealing entry: Entry) -> EpochChain? {
        chains[entry.room ?? outpostRoom(for: entry.author)]
    }

}
