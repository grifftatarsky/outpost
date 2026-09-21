import CarpenterKit
import CryptoKit
import Foundation

public struct SessionStorage: Sendable {
    public let keychain: any KeychainStore
    public let log: any LogStore
    public let documents: any DocumentStore
    public let media: any MediaStore

    public init(
        keychain: any KeychainStore, log: any LogStore, documents: any DocumentStore,
        media: any MediaStore = MemoryMediaStore()
    ) {
        self.keychain = keychain
        self.log = log
        self.documents = documents
        self.media = media
    }

    public var readOnly: SessionStorage {
        SessionStorage(
            keychain: ReadOnlyKeychainStore(keychain), log: ReadOnlyLogStore(log),
            documents: ReadOnlyDocumentStore(documents), media: media)
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
    }

    public internal(set) var state: State = .loading
    public internal(set) var rooms: [RoomSummary] = []

    var roomsThisMemberIsIn: Set<RoomID> = []
    public internal(set) var organisation = RoomsListOrganisation()

    public internal(set) var enrolment: Enrolment?

    public internal(set) var forks: [Fork] = []

    public internal(set) var lastLoad: LogTermination = .complete

    public internal(set) var cannotSend: MailboxFailure?

    public internal(set) var integrity = IntegrityReport()

    public var entryCount: Int { replica.entryCount }

    let storage: SessionStorage
    let clock: any Clock

    var persisted = PersistedState()
    var replica = Replica() { didSet { foldChanged() } }
    var chains: [RoomID: EpochChain] = [:] { didSet { foldChanged() } }

    var cachedProjection: Projection?
    var cachedEntries: [EntryHash: Entry]?
    var cachedRosters: [RoomID: RoomRoster] = [:]

    var cachedOutOfRoom: [RoomID: Set<EntryHash>] = [:]
    var cachedReadEvidence: [RoomID: ReadEvidence] = [:]
    var cachedReporting: [RoomID: Set<ParticipantID>] = [:]
    var cachedOutpostAccess: OutpostAccess?
    var cachedDevicesAdded: [RoomID: [AddedDevice]] = [:]
    var cachedComparisonHalves: [ParticipantID: String] = [:]

    var cachedPairwise: [ParticipantID: PairwiseSecret] = [:]

    public internal(set) var codeForSharing = ""

    private(set) var foldCount = 0

    func foldChanged() {
        cachedProjection = nil
        cachedEntries = nil
        cachedRosters = [:]
        cachedOutOfRoom = [:]
        cachedReadEvidence = [:]
        cachedReporting = [:]
        cachedOutpostAccess = nil
        cachedDevicesAdded = [:]
    }
    var viewMayBeStale = false

    var entriesNotWrittenDown: [Entry] = []

    var head: EntryLink?
    var accountRegistry: (any AccountRegistry)?
    var loadInFlight: Task<Void, Never>?
    public internal(set) var drafts: [DraftPlace: String] = [:]
    var draftKey: Data?
    var draftKeyInFlight: Task<Data, any Error>?

    var issuedGrants: Set<String> = []

    var roomsWithUnsentMessages: Set<RoomID> = []

    var unsentWallPosts: Set<EntryHash> = []

    var wallsWrittenOn: Set<ParticipantID> = []

    var notifyWallsSent: [ParticipantID]?

    var attachmentTasks: [AttachmentID: Task<Data?, any Error>] = [:]
    var hasAskedForWall: Set<ParticipantID> = []
    var peersLastRound: Set<ParticipantID> = []
    var pendingRecipients: [PacketID: Set<RecipientTag>]?

    public internal(set) var metSomebodyNew = false
    var attachmentRetryAfter: [AttachmentID: Date] = [:]
    var attachmentAcknowledgementsOwed: [AttachmentID: Set<RecipientTag>] = [:]
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

    func saveState() async throws {
        let previous = stateWrites
        let write = Task { @MainActor [self] in
            _ = try? await previous?.value
            try await storage.documents.save(persisted)
        }
        stateWrites = write
        try await write.value
    }

    public internal(set) var cameBackFromARecoveryKey = false
    public internal(set) var isSilenced = false
    var deviceSync: (any EntrySync)?
    var incomingTask: Task<Void, Never>?

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
        if let cachedProjection { return cachedProjection }
        var built = Projection(
            viewer: enrolment?.identity.id ?? ParticipantID(rawValue: Data()),
            rendered: Fold.render(replica.ordered(), opening: entryOpener()),
            revealsNames: persisted.preferences.isShowingOthersNames,
            viewerName: persisted.preferences.displayName?.value,
            nicknames: persisted.preferences.currentNicknames,
            anonPersona: persisted.preferences.anonPersona
        )
        built.onlyName(peopleMet(in: built))
        cachedProjection = built
        foldCount += 1
        return built
    }

    func peopleMet(in projected: Projection) -> Set<ParticipantID> {
        guard let me = enrolment?.identity.id else { return [] }
        let opener = payloadOpener()
        var met = projected.peopleInRooms(opening: opener)
        met.formUnion(projected.outpostAccess(of: me, opening: opener).audience(at: clock.now))
        met.formUnion(projected.outpostAuthors().map(\.id))
        met.formUnion(persisted.acceptedInvitations.map(\.attestation.inviter))
        met.insert(me)
        return met
    }

    public func hasMet(_ person: ParticipantID) -> Bool {
        projection.met?.contains(person) ?? true
    }

    var entriesByHash: [EntryHash: Entry] {
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
            guard let theirs = pairwiseSecret(with: owner) else {
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
        alsoFor extra: PairwiseSecret? = nil
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
        guard let chain = chains[chainRoom] else { throw AppSessionError.noIdentity }

        let entry = try Entry.append(
            after: head,
            author: enrolment.identity.id,
            device: enrolment.device,
            clock: replica.frontier(in: room),
            wallTime: clock.now,
            room: room,
            payload: payload,
            at: chain.highestKnownEpoch ?? .initial,
            sealedWith: chain,
            alsoFor: extra
        )

        if case .forked(let fork) = try replica.integrate(entry) { forks.append(fork) }
        head = entry.link
        try await storage.log.append([entry])
        refresh()
    }

    func restoreLog(identity: Identity) async throws {
        replica = Replica()
        replica.introduce(identity.publicKeys)

        for keys in persisted.knownKeys { replica.introduce(keys) }
        for certificate in persisted.certificates { try? replica.admit(certificate) }

        if let enrolment,
            replica.registry(for: identity.id)?.standing(of: enrolment.device.id) == nil
        {
            try replica.admit(
                DeviceCertificate.issue(
                    for: enrolment.device.publicKey, by: identity, at: clock.now))
            persisted.certificates = knownCertificates()
        }
        for revocation in persisted.revocations { try? replica.revoke(revocation) }
        replica.restore(spent: persisted.spentEntries, closing: persisted.preferences.roomsDeleted)

        let loaded = try await storage.log.loadAll()
        lastLoad = loaded.termination
        integrity = IntegrityReport()
        integrity.lastLoad = loaded.termination
        integrity.discardedBytes = loaded.discardedTrailingBytes

        let ownFeed = enrolment.map { FeedKey(author: $0.identity.id, device: $0.device.id) }
        var stillOnDisk: [Entry] = []
        for entry in loaded.entries {
            let outcome: IntegrationResult
            do {
                outcome = try replica.integrate(entry)
            } catch {
                integrity.unverifiableOnDisk += 1
                continue
            }
            if case .forked(let fork) = outcome {
                forks.append(fork)
            }
            if entry.feedKey == ownFeed {
                head = entry.link
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

    func refresh() {
        prepareCodeForSharing()
        var projected = projection
        var opener = payloadOpener()

        if introduceEstablishedMembers(in: projected, opening: opener) {
            projected = projection
            opener = payloadOpener()
        }

        let hidden = persisted.preferences.hiddenEntries
        let shutOut = shutOutAuthors()
        let me = enrolment?.identity.id
        var joined: Set<RoomID> = []
        rooms = projected.summaries().map { summary in
            let roster = projected.roster(of: summary.id, opening: opener)
            if let me, roster.members.contains(me) { joined.insert(summary.id) }
            return projected.summary(
                of: summary.id,
                memberCount: roster.members.count,
                others: roster.members.union(roster.requests.keys)
                    .filter { $0 != me }
                    .sorted { $0.rawValue.lexicographicallyPrecedes($1.rawValue) },
                unreadFor: me,
                readThrough: persisted.readThrough[summary.id],
                undrawn: hidden
                    .union(projected.outOfRoom(in: summary.id, opening: opener))
                    .union(projected.entries(by: shutOut, in: summary.id))
            ) ?? summary
        }
        roomsThisMemberIsIn = joined
        organisation.forgetRoomsMissing(
            from: Set(rooms.map(\.id)).union(awaitingAdmission.map(\.room)))
    }

    @discardableResult
    func introduceEstablishedMembers(
        in projected: Projection, opening: (RenderedEntry) -> Payload?
    ) -> Bool {
        var introduced = false
        for summary in projected.summaries() {
            let roster = projected.roster(of: summary.id, opening: opening)
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
        try await storage.keychain.set(
            secret.material, for: Self.epochKey(room, epoch), scope: .device)

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
                guard let material = try await storage.keychain.data(for: Self.epochKey(room, epoch))
                else { continue }
                chain.adopt(EpochSecret(material: material), at: epoch)
                found = true
            }

            if found { chains[room] = chain }
        }
    }

    static func epochKey(_ room: RoomID, _ epoch: EpochNumber) -> KeychainKey {
        KeychainKey("epoch.\(room.rawValue.uuidString).\(epoch.rawValue)")
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
