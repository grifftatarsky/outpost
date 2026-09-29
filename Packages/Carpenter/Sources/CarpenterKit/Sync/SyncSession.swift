import Foundation

public struct SyncReport: Hashable, Sendable {
    public var packetsWritten: Int = 0
    public var packetsFetched: Int = 0
    public var entriesSent: Int = 0
    public var entriesReceived: Int = 0
    public var entriesRejected: Int = 0

    public var entriesRefusedForever: Int = 0

    public var entriesDelivered: Int = 0

    public var entriesAlreadyPresent: Int = 0
    public var forksFound: Int = 0

    public var credentialsRejected: Int = 0

    public var refusals: [Refusal] = []

    public struct Refusal: Hashable, Sendable {
        public enum What: String, Hashable, Sendable {
            case credential
            case entry
        }

        public let packet: PacketID
        public let what: What
        public let author: ParticipantID?
        public let reason: String
        public let feed: FeedKey?
        public let seq: UInt64?
        public let isFinal: Bool

        public init(
            packet: PacketID, what: What, author: ParticipantID?, reason: String,
            feed: FeedKey? = nil, seq: UInt64? = nil, isFinal: Bool = false
        ) {
            self.packet = packet
            self.what = what
            self.author = author
            self.reason = reason
            self.feed = feed
            self.seq = seq
            self.isFinal = isFinal
        }

        public var summary: String {
            let who = author.map { Diagnostics.fingerprint($0.rawValue) } ?? "unknown"
            return "\(what.rawValue) from \(who): \(reason)"
        }
    }

    public var integrated: [Entry] = []

    public var readableFrom: [EntryHash: Date] = [:]

    mutating func took(_ entry: Entry, readableFrom instant: Date) {
        integrated.append(entry)
        readableFrom[entry.hash] = min(readableFrom[entry.hash] ?? instant, instant)
    }

    public struct WrittenPacket: Hashable, Sendable {
        public let packet: PacketID
        public let entries: Set<EntryHash>
        public let recipients: Set<RecipientTag>
        public let digest: Data?
        public let to: ParticipantID?

        public init(
            packet: PacketID, entries: Set<EntryHash>, recipients: Set<RecipientTag> = [], digest: Data? = nil,
            to: ParticipantID? = nil
        ) {
            self.packet = packet
            self.entries = entries
            self.recipients = recipients
            self.digest = digest
            self.to = to
        }
    }

    public var written: [WrittenPacket] = []

    public var wrote: WrittenPacket? { written.first }

    public var sendFailure: String?

    public var cannotSend: MailboxFailure?

    public var bellsRung: Int = 0

    public struct ReceivedGrant: Hashable, Sendable {
        public let grant: EpochGrant
        public let storedAt: Date

        public init(grant: EpochGrant, storedAt: Date) {
            self.grant = grant
            self.storedAt = storedAt
        }
    }

    public var grantsReceived: [ReceivedGrant] = []

    public var repairRequests: [RepairRequest] = []
    public var repairAnswers: [RepairAnswer] = []
    public var notifyWalls: [ParticipantID]?
    public var confirmations: [JoinConfirmedBody] = []
    public var photoAsks: [PhotoAsk] = []
    public var addresses: [ReceivedAddress] = []

    public struct ReceivedAddress: Hashable, Sendable {
        public let announcement: AddressAnnouncement
        public let storedAt: Date

        public init(announcement: AddressAnnouncement, storedAt: Date) {
            self.announcement = announcement
            self.storedAt = storedAt
        }
    }

    public init() {}

    public func adding(_ other: SyncReport) -> SyncReport {
        var merged = self
        merged.packetsWritten += other.packetsWritten
        merged.packetsFetched += other.packetsFetched
        merged.entriesSent += other.entriesSent
        merged.entriesReceived += other.entriesReceived
        merged.entriesRejected += other.entriesRejected
        merged.entriesRefusedForever += other.entriesRefusedForever
        merged.entriesDelivered += other.entriesDelivered
        merged.entriesAlreadyPresent += other.entriesAlreadyPresent
        merged.credentialsRejected += other.credentialsRejected
        merged.refusals.append(contentsOf: other.refusals)
        merged.forksFound += other.forksFound
        merged.bellsRung += other.bellsRung
        merged.integrated.append(contentsOf: other.integrated)
        merged.readableFrom.merge(other.readableFrom, uniquingKeysWith: min)
        merged.written.append(contentsOf: other.written)
        merged.sendFailure = merged.sendFailure ?? other.sendFailure
        merged.cannotSend = merged.cannotSend ?? other.cannotSend
        merged.grantsReceived.append(contentsOf: other.grantsReceived)
        merged.repairRequests.append(contentsOf: other.repairRequests)
        merged.repairAnswers.append(contentsOf: other.repairAnswers)
        if let theirs = other.notifyWalls { merged.notifyWalls = theirs }
        merged.confirmations.append(contentsOf: other.confirmations)
        merged.photoAsks.append(contentsOf: other.photoAsks)
        merged.addresses.append(contentsOf: other.addresses)
        return merged
    }

    public var didAnything: Bool {
        packetsWritten > 0 || entriesReceived > 0 || !grantsReceived.isEmpty
            || !repairRequests.isEmpty || !repairAnswers.isEmpty || !confirmations.isEmpty || !photoAsks.isEmpty
            || !addresses.isEmpty
    }
}

public struct SyncSession: Sendable {
    private let mailbox: any Mailbox
    private let pairs: Pairs
    private let clock: any Clock

    public init(mailbox: any Mailbox, pairs: Pairs, clock: any Clock = SystemClock()) {
        self.mailbox = mailbox
        self.pairs = pairs
        self.clock = clock
    }

    public static let tagWindow: TimeInterval = 86_400

    public static func window(at instant: Date) -> UInt64 {
        UInt64(max(instant.timeIntervalSince1970, 0) / tagWindow)
    }

    public static let windowLookback: UInt64 = 7

    public static let packetWaitsFor = tagWindow * Double(windowLookback + 2)

    public static func recentTags(for peer: Peer, at instant: Date) -> Set<RecipientTag> {
        Set(recentWindows(for: peer, at: instant).keys)
    }

    static func recentWindows(for peer: Peer, at instant: Date) -> [RecipientTag: UInt64] {
        let current = window(at: instant)
        let oldest = current >= windowLookback ? current - windowLookback : 0
        return Dictionary(uniqueKeysWithValues: (oldest...(current + 1)).map { (peer.incomingTag(window: $0), $0) })
    }

    static func firstLooked(for window: UInt64) -> Date {
        Date(timeIntervalSince1970: Double(window > 0 ? window - 1 : 0) * tagWindow)
    }

    public static let packetByteBudget = 700 * 1024

    public func send(
        _ entries: [Entry],
        to peers: [Peer],
        certificates: [DeviceCertificate] = [],
        revocations: [DeviceRevocation] = [],
        granting: [(to: Peer, grant: EpochGrant)] = [],
        at instant: Date? = nil,
        ringing: [Peer] = [],
        requests: [RepairRequest] = [],
        answers: [RepairAnswer] = [],
        identities: [IdentityPublicKeys] = [],
        notifyWalls: [ParticipantID]? = nil,
        confirming: [JoinConfirmedBody] = [],
        asking: [PhotoAsk] = [],
        addresses: [AddressAnnouncement] = [],
        announcing: Bool = false,
        withholding withheld: @Sendable (Entry, ParticipantID) -> Bool = { _, _ in false }
    ) async throws -> SyncReport {
        var report = SyncReport()
        let carriesMoreThanEntries =
            !requests.isEmpty || !answers.isEmpty || notifyWalls != nil || !confirming.isEmpty || !asking.isEmpty
            || announcing
        guard !peers.isEmpty,
            !entries.isEmpty || !granting.isEmpty || !addresses.isEmpty || carriesMoreThanEntries
        else { return report }

        let now = instant ?? clock.now
        let window = Self.window(at: now)
        let forEveryone = entries.isEmpty ? [[]] : Self.batches(of: entries)
        var reached: Set<ParticipantID> = []
        var cutShort: Set<ParticipantID> = []
        var lastError: (any Error)?

        for peer in peers {
            var batches = forEveryone
            if entries.contains(where: { withheld($0, peer.them) }) {
                let theirs = entries.filter { !withheld($0, peer.them) }
                let owedThem =
                    granting.contains { $0.to.them == peer.them } || addresses.contains { $0.recipient == peer.them }
                guard !theirs.isEmpty || owedThem || carriesMoreThanEntries else { continue }
                batches = theirs.isEmpty ? [[]] : Self.batches(of: theirs)
            }
            for (index, batch) in batches.enumerated() {
                let first = index == 0
                let packet = try SyncEngine.pack(
                    batch, for: [peer],
                    certificates: first ? certificates : [],
                    revocations: first ? revocations : [],
                    granting: first ? granting.filter { $0.to.them == peer.them } : [],
                    window: window,
                    requests: first ? requests : [],
                    answers: first ? answers : [],
                    identities: first ? identities : [],
                    notifyWalls: first ? notifyWalls : nil,
                    confirmations: first ? confirming : [],
                    asks: first ? asking : [],
                    addresses: first ? addresses.filter { $0.recipient == peer.them } : [])
                do {
                    try await mailbox.put(packet, to: peer.them, in: pairs)
                } catch {
                    lastError = error
                    cutShort.insert(peer.them)
                    report.cannotSend = report.cannotSend ?? error as? MailboxFailure
                    report.sendFailure = String(describing: error)
                    Diagnostics.sync.error(
                        """
                        mailbox: packet \(index + 1, privacy: .public) of \(batches.count, privacy: .public) \
                        for one person would not write; the rest for them waits for the next round \
                        (\(String(describing: error), privacy: .public))
                        """)
                    break
                }
                reached.insert(peer.them)
                report.packetsWritten += 1
                report.entriesSent += batch.count
                report.written.append(
                    SyncReport.WrittenPacket(
                        packet: packet.id, entries: Set(batch.map(\.hash)), recipients: packet.recipients,
                        digest: packet.contentDigest, to: peer.them))
            }
        }
        if reached.isEmpty, let lastError { throw lastError }
        if forEveryone.count > 1 {
            Diagnostics.sync.notice(
                """
                mailbox: a round of \(entries.count, privacy: .public) entries went as \
                \(report.packetsWritten, privacy: .public) packets to \(reached.count, privacy: .public) people
                """)
        }

        report.bellsRung = await ring(to: ringing.filter { reached.contains($0.them) && !cutShort.contains($0.them) })
        return report
    }

    public static func fitsAPacket(_ entry: Entry) -> Bool {
        cost(of: entry, encoder: JSONEncoder()) <= packetByteBudget
    }

    private static func cost(of entry: Entry, encoder: JSONEncoder) -> Int {
        ((try? encoder.encode(entry).count) ?? 0) + 2
    }

    static func batches(of entries: [Entry], budget: Int = packetByteBudget) -> [[Entry]] {
        var batches: [[Entry]] = []
        var current: [Entry] = []
        var size = 0
        let encoder = JSONEncoder()
        for entry in entries {
            let cost = cost(of: entry, encoder: encoder)
            guard cost <= budget else {
                Diagnostics.sync.error(
                    "mailbox: left out an entry of \(cost, privacy: .public) bytes, too big for any packet")
                continue
            }
            if !current.isEmpty, size + cost > budget {
                batches.append(current)
                current = []
                size = 0
            }
            current.append(entry)
            size += cost
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }

    private func ring(to peers: [Peer]) async -> Int {
        var rung = 0
        for peer in peers {
            do {
                try await mailbox.ring(peer.them, in: pairs)
                rung += 1
            } catch {
                Diagnostics.sync.error(
                    "mailbox: could not ring somebody: \(String(describing: error), privacy: .public)")
            }
        }
        return rung
    }

    private static func unpack(
        _ packet: SyncPacket, as peer: Peer, at instant: Date
    ) throws -> SyncEngine.Delivery {
        let current = window(at: instant)
        let oldest = current >= windowLookback ? current - windowLookback : 0

        var lastError: any Error = SyncError.notAddressedToUs
        for candidate in stride(from: Int(current + 1), through: Int(oldest), by: -1) {
            do {
                return try SyncEngine.unpack(packet, as: peer, window: UInt64(candidate))
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    public struct CollectedPackets: Sendable {
        public struct Opened: Sendable {
            public let id: PacketID
            public let delivery: SyncEngine.Delivery
            public let storedAt: Date
            public let tag: RecipientTag?
            public let secret: PairwiseSecret?
            public let from: ParticipantID

            public init(
                id: PacketID, delivery: SyncEngine.Delivery, storedAt: Date, from: ParticipantID,
                tag: RecipientTag? = nil, secret: PairwiseSecret? = nil
            ) {
                self.id = id
                self.delivery = delivery
                self.storedAt = storedAt
                self.from = from
                self.tag = tag
                self.secret = secret
            }
        }

        public let tags: Set<RecipientTag>
        public let packets: [Opened]

        public let unopened: [(id: PacketID, reason: any Error)]

        public var isEmpty: Bool { packets.isEmpty }

        public var entries: [Entry] { packets.flatMap(\.delivery.entries) }

        public var certificates: [DeviceCertificate] { packets.flatMap(\.delivery.certificates) }

        public init(
            tags: Set<RecipientTag>,
            packets: [Opened],
            unopened: [(id: PacketID, reason: any Error)] = []
        ) {
            self.tags = tags
            self.packets = packets
            self.unopened = unopened
        }
    }

    public func collect(
        as peer: Peer, alternates: [PairwiseSecret] = [], learned: [PairwiseSecret: Date] = [:],
        at instant: Date? = nil, alreadyTaken: @Sendable (SyncPacket) -> Bool = { _ in false }
    ) async throws -> CollectedPackets {
        let now = instant ?? clock.now
        var ways: [(peer: Peer, windows: [RecipientTag: UInt64])] = []
        for secret in [peer.secret] + alternates where !ways.contains(where: { $0.peer.secret == secret }) {
            let way = Peer(secret: secret, them: peer.them, me: peer.me)
            ways.append((way, Self.recentWindows(for: way, at: now)))
        }
        let tags = ways.reduce(into: Set<RecipientTag>()) { $0.formUnion($1.windows.keys) }

        let packets = try await mailbox.fetch(from: peer.them, for: tags, in: pairs)

        var opened: [CollectedPackets.Opened] = []
        var unopened: [(PacketID, any Error)] = []
        for packet in packets where !alreadyTaken(packet) {
            guard let way = ways.first(where: { way in packet.recipients.contains { way.windows[$0] != nil } }),
                let earliest = packet.recipients.compactMap({ way.windows[$0] }).min()
            else { continue }
            let findable = max(Self.firstLooked(for: earliest), learned[way.peer.secret] ?? .distantPast)
            do {
                opened.append(
                    CollectedPackets.Opened(
                        id: packet.id, delivery: try Self.unpack(packet, as: way.peer, at: now),
                        storedAt: max(packet.storedAt ?? now, findable), from: peer.them,
                        tag: packet.recipients.first { way.windows[$0] != nil }, secret: way.peer.secret))
            } catch {
                unopened.append((packet.id, error))
            }
        }
        return CollectedPackets(tags: tags, packets: opened, unopened: unopened)
    }

    @discardableResult
    public static func integrate(
        _ collected: CollectedPackets, into replica: inout Replica,
        checked: SignatureChecks = SignatureChecks()
    ) -> (report: SyncReport, settled: Set<PacketID>) {
        var report = SyncReport()
        report.packetsFetched = collected.packets.count
        var settled: Set<PacketID> = []

        for packet in collected.packets {
            let delivery = packet.delivery
            report.grantsReceived.append(
                contentsOf: delivery.grants.map { SyncReport.ReceivedGrant(grant: $0, storedAt: packet.storedAt) })
            report.repairRequests.append(contentsOf: delivery.requests)
            report.repairAnswers.append(contentsOf: delivery.answers)
            if let wishes = delivery.notifyWalls { report.notifyWalls = wishes }
            report.confirmations.append(contentsOf: delivery.confirmations)
            report.photoAsks.append(contentsOf: delivery.asks)
            report.addresses.append(
                contentsOf: delivery.addresses.map { SyncReport.ReceivedAddress(announcement: $0, storedAt: packet.storedAt) })

            for identity in delivery.identities { replica.introduce(identity) }

            var rejected = 0
            for certificate in delivery.certificates {
                do { try replica.admit(certificate, storedAt: packet.storedAt) } catch {
                    rejected += 1
                    report.refusals.append(
                        SyncReport.Refusal(
                            packet: packet.id, what: .credential, author: certificate.participant,
                            reason: String(describing: error)))
                }
            }
            for revocation in delivery.revocations {
                do { try replica.revoke(revocation, storedAt: packet.storedAt) } catch {
                    rejected += 1
                    report.refusals.append(
                        SyncReport.Refusal(
                            packet: packet.id, what: .credential, author: revocation.participant,
                            reason: String(describing: error)))
                }
            }
            report.credentialsRejected += rejected

            var entriesRejected = 0
            var refusedForever = 0
            report.entriesDelivered += delivery.entries.count
            for entry in delivery.entries {
                do {
                    let result = try replica.integrate(entry, checked: checked)
                    switch result {
                    case .accepted: report.entriesReceived += 1
                    case .alreadyPresent: report.entriesAlreadyPresent += 1
                    case .forked: report.forksFound += 1
                    }
                    if result != .alreadyPresent {
                        let published = replica.registry(for: entry.author)?.publishedAt(entry.device)
                        report.took(entry, readableFrom: max(packet.storedAt, published ?? .distantPast))
                    }
                } catch {
                    let isFinal = replica.refusesForever(entry)
                    if isFinal { refusedForever += 1 } else { entriesRejected += 1 }
                    report.refusals.append(
                        SyncReport.Refusal(
                            packet: packet.id, what: .entry, author: entry.author,
                            reason: String(describing: error), feed: entry.feedKey, seq: entry.seq,
                            isFinal: isFinal))
                }
            }
            report.entriesRejected += entriesRejected
            report.entriesRefusedForever += refusedForever
            rejected += entriesRejected

            if rejected == 0 { settled.insert(packet.id) }
        }

        return (report, settled)
    }

    public func acknowledge(
        _ collected: CollectedPackets, _ settled: Set<PacketID>,
        signing receipt: @Sendable (PacketID, RecipientTag) throws -> SealedReceipt
    ) async throws {
        var failed: [PacketID: String] = [:]
        var acknowledged = 0
        for packet in collected.packets where settled.contains(packet.id) {
            guard let tag = packet.tag else { continue }
            do {
                try await mailbox.acknowledge(
                    packet.id, from: packet.from, with: try receipt(packet.id, tag), in: pairs)
                acknowledged += 1
            } catch {
                failed[packet.id] = String(describing: error)
            }
        }
        if !failed.isEmpty {
            throw AcknowledgementFailure(failed: failed, acknowledged: acknowledged)
        }
    }

    public func receive(
        as peer: Peer, into replica: inout Replica, at instant: Date? = nil,
        signing receipt: (@Sendable (PacketID, RecipientTag) throws -> SealedReceipt)? = nil,
        alreadyTaken: @Sendable (SyncPacket) -> Bool = { _ in false }
    ) async throws -> SyncReport {
        let collected = try await collect(as: peer, at: instant, alreadyTaken: alreadyTaken)
        let checked = await replica.signatureChecks(
            for: collected.entries, alsoTrusting: collected.certificates)
        let (report, settled) = Self.integrate(collected, into: &replica, checked: checked)
        if let receipt { try await acknowledge(collected, settled, signing: receipt) }
        return report
    }
}
