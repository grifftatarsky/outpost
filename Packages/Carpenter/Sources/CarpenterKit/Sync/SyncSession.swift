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

    public struct WrittenPacket: Hashable, Sendable {
        public let packet: PacketID
        public let entries: Set<EntryHash>

        public init(packet: PacketID, entries: Set<EntryHash>) {
            self.packet = packet
            self.entries = entries
        }
    }

    public var written: [WrittenPacket] = []

    public var wrote: WrittenPacket? { written.first }

    public var sendFailure: String?

    public var cannotSend: MailboxFailure?

    public var bellsRung: Int = 0

    public var grantsReceived: [EpochGrant] = []

    public var repairRequests: [RepairRequest] = []
    public var repairAnswers: [RepairAnswer] = []
    public var withheld: [FeedGap] = []
    public var attestations: [HeadAttestation] = []
    public var notifyWalls: [ParticipantID]?
    public var confirmations: [JoinConfirmedBody] = []

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
        merged.written.append(contentsOf: other.written)
        merged.sendFailure = merged.sendFailure ?? other.sendFailure
        merged.cannotSend = merged.cannotSend ?? other.cannotSend
        merged.grantsReceived.append(contentsOf: other.grantsReceived)
        merged.repairRequests.append(contentsOf: other.repairRequests)
        merged.repairAnswers.append(contentsOf: other.repairAnswers)
        merged.withheld.append(contentsOf: other.withheld)
        merged.attestations.append(contentsOf: other.attestations)
        if let theirs = other.notifyWalls { merged.notifyWalls = theirs }
        merged.confirmations.append(contentsOf: other.confirmations)
        return merged
    }

    public var didAnything: Bool {
        packetsWritten > 0 || entriesReceived > 0 || !grantsReceived.isEmpty
            || !repairRequests.isEmpty || !repairAnswers.isEmpty || !confirmations.isEmpty
    }
}

public struct SyncSession: Sendable {
    private let mailbox: any Mailbox
    private let clock: any Clock

    public init(mailbox: any Mailbox, clock: any Clock = SystemClock()) {
        self.mailbox = mailbox
        self.clock = clock
    }

    public static let tagWindow: TimeInterval = 86_400

    public static func window(at instant: Date) -> UInt64 {
        UInt64(max(instant.timeIntervalSince1970, 0) / tagWindow)
    }

    public static let windowLookback: UInt64 = 7

    public static func recentTags(for peer: Peer, at instant: Date) -> Set<RecipientTag> {
        let current = window(at: instant)
        let oldest = current >= windowLookback ? current - windowLookback : 0
        return Set((oldest...(current + 1)).map { peer.incomingTag(window: $0) })
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
        withholding: [FeedGap] = [],
        attesting: [HeadAttestation] = []
    ) async throws -> SyncReport {
        var report = SyncReport()
        guard !peers.isEmpty,
            !entries.isEmpty || !granting.isEmpty || !requests.isEmpty || !answers.isEmpty
                || notifyWalls != nil || !confirming.isEmpty || !withholding.isEmpty
                || !attesting.isEmpty
        else { return report }

        let now = instant ?? clock.now
        let window = Self.window(at: now)
        let batches = entries.isEmpty ? [[]] : Self.batches(of: entries)

        for (index, batch) in batches.enumerated() {
            let first = index == 0
            let packet = try SyncEngine.pack(
                batch, for: peers,
                certificates: first ? certificates : [],
                revocations: first ? revocations : [],
                granting: first ? granting : [],
                window: window,
                requests: first ? requests : [],
                answers: first ? answers : [],
                identities: first ? identities : [],
                notifyWalls: first ? notifyWalls : nil,
                confirmations: first ? confirming : [],
                withheld: first ? withholding : [],
                attestations: first ? attesting : [])
            do {
                try await mailbox.put(packet)
            } catch {
                report.cannotSend = error as? MailboxFailure
                if report.written.isEmpty { throw error }
                report.sendFailure = String(describing: error)
                Diagnostics.sync.error(
                    """
                    mailbox: packet \(index + 1, privacy: .public) of \(batches.count, privacy: .public) \
                    would not write; the rest waits for the next round \
                    (\(String(describing: error), privacy: .public))
                    """)
                break
            }
            report.packetsWritten += 1
            report.entriesSent += batch.count
            report.written.append(
                SyncReport.WrittenPacket(packet: packet.id, entries: Set(batch.map(\.hash))))
        }
        if batches.count > 1 {
            Diagnostics.sync.notice(
                """
                mailbox: a round of \(entries.count, privacy: .public) entries went as \
                \(report.packetsWritten, privacy: .public) of \(batches.count, privacy: .public) packets
                """)
        }

        if report.sendFailure == nil {
            report.bellsRung = await ring(to: ringing, at: now)
        }
        return report
    }

    static func batches(of entries: [Entry], budget: Int = packetByteBudget) -> [[Entry]] {
        var batches: [[Entry]] = []
        var current: [Entry] = []
        var size = 0
        let encoder = JSONEncoder()
        for entry in entries {
            let cost = ((try? encoder.encode(entry).count) ?? 0) + 2
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

    private func ring(to peers: [Peer], at instant: Date) async -> Int {
        var rung = 0
        for peer in peers {
            let bell = MessageBell(
                fetchTag: peer.incomingTag(window: Self.window(at: instant)),
                name: peer.secret.bellName(for: peer.them),
                ring: UInt64(max(instant.timeIntervalSince1970, 0))
            )
            do {
                try await mailbox.ring(bell)
                rung += 1
            } catch {
                Diagnostics.sync.error(
                    "mailbox: could not ring a peer's bell: \(String(describing: error), privacy: .public)")
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
        }

        public let tags: Set<RecipientTag>
        public let packets: [Opened]

        public let unopened: [(id: PacketID, reason: any Error)]

        public var isEmpty: Bool { packets.isEmpty }

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

    public func collect(as peer: Peer, at instant: Date? = nil) async throws -> CollectedPackets {
        let now = instant ?? clock.now
        let tags = Self.recentTags(for: peer, at: now)

        let packets = try await mailbox.fetch(for: tags)

        var opened: [CollectedPackets.Opened] = []
        var unopened: [(PacketID, any Error)] = []
        for packet in packets {
            do {
                opened.append(
                    CollectedPackets.Opened(
                        id: packet.id, delivery: try Self.unpack(packet, as: peer, at: now)))
            } catch {
                unopened.append((packet.id, error))
            }
        }
        return CollectedPackets(tags: tags, packets: opened, unopened: unopened)
    }

    @discardableResult
    public static func integrate(
        _ collected: CollectedPackets, into replica: inout Replica
    ) -> (report: SyncReport, settled: Set<PacketID>) {
        var report = SyncReport()
        report.packetsFetched = collected.packets.count
        var settled: Set<PacketID> = []

        for packet in collected.packets {
            let delivery = packet.delivery
            report.grantsReceived.append(contentsOf: delivery.grants)
            report.repairRequests.append(contentsOf: delivery.requests)
            report.repairAnswers.append(contentsOf: delivery.answers)
            report.withheld.append(contentsOf: delivery.withheld)
            report.attestations.append(contentsOf: delivery.attestations)
            if let wishes = delivery.notifyWalls { report.notifyWalls = wishes }
            report.confirmations.append(contentsOf: delivery.confirmations)

            for identity in delivery.identities { replica.introduce(identity) }

            var rejected = 0
            for certificate in delivery.certificates {
                do { try replica.admit(certificate) } catch {
                    rejected += 1
                    report.refusals.append(
                        SyncReport.Refusal(
                            packet: packet.id, what: .credential, author: certificate.participant,
                            reason: String(describing: error)))
                }
            }
            for revocation in delivery.revocations {
                do { try replica.revoke(revocation) } catch {
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
                    switch try replica.integrate(entry) {
                    case .accepted:
                        report.entriesReceived += 1
                        report.integrated.append(entry)
                    case .alreadyPresent: report.entriesAlreadyPresent += 1
                    case .forked:
                        report.forksFound += 1
                        report.integrated.append(entry)
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

    public func acknowledge(_ collected: CollectedPackets, _ settled: Set<PacketID>) async throws {
        var failed: [PacketID: String] = [:]
        var acknowledged = 0
        for packet in collected.packets where settled.contains(packet.id) {
            do {
                try await mailbox.acknowledge(packet.id, by: collected.tags)
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
        acknowledging: Bool = true
    ) async throws -> SyncReport {
        let collected = try await collect(as: peer, at: instant)
        let (report, settled) = Self.integrate(collected, into: &replica)
        if acknowledging { try await acknowledge(collected, settled) }
        return report
    }
}
