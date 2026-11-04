import Foundation

public struct DeviceRegistry: Hashable, Sendable {
    public struct Standing: Hashable, Sendable {
        public let addedAt: Date
        public fileprivate(set) var revokedAt: Date?
        public let approvedBy: DeviceID?
        public fileprivate(set) var revokedBy: DeviceID?
        public let recovered: Bool
        public fileprivate(set) var removedByRecovery: Bool = false
        public fileprivate(set) var cutoff: UInt64?
        public fileprivate(set) var head: EntryHash?
        public fileprivate(set) var line: UInt64?
        fileprivate var limits: [Limit] = []
    }

    public struct Line: Hashable, Sendable, Codable {
        public let seq: UInt64
        public let head: EntryHash?

        public init(seq: UInt64, head: EntryHash?) {
            self.seq = seq
            self.head = head
        }
    }

    fileprivate struct Limit: Hashable, Sendable {
        let cutoff: UInt64?
        let head: EntryHash?
        let before: Date
        let remover: DeviceID?
        var alsoByDate = false
        var seen: UInt64 = 0

        var weighsEvidence: Bool { remover != nil }

        var isContradicted: Bool { cutoff.map { seen > $0 } ?? false }

        var bound: UInt64? { cutoff.map { Swift.max($0, seen) } }

        func admits(seq: UInt64, hash: EntryHash?, at instant: Date) -> Bool {
            if let cutoff, !isContradicted {
                if seq == cutoff, let head, let hash, hash != head { return false }
                return seq <= cutoff && (!alsoByDate || instant < before)
            }
            if seq <= seen { return true }
            return cutoff == nil && instant < before
        }
    }

    public static let mostDevices = 256

    public static let mostApprovalsByOneDevice = 16

    public static let mostRemovalsByOneDevice = 16

    private enum Place: Hashable, Sendable {
        case root
        case signed(by: DeviceID, lineage: DeviceID?)
        case unproven
    }

    public let identity: IdentityPublicKeys

    private var submitted: [DeviceID: DeviceCertificate] = [:]
    private var revocations: Set<DeviceRevocation> = []
    private var certificatePlaces: [DeviceID: Place] = [:]
    private var removalPlaces: [Data: Place] = [:]
    private var stored: [Data: Date] = [:]
    private var standings: [DeviceID: Standing] = [:]
    private var windows: [DeviceID: Authority] = [:]
    private var witnessed: [DeviceID: [DeviceID: UInt64]] = [:]
    private var supersededAt: [DeviceID: Line] = [:]

    public init(identity: IdentityPublicKeys) {
        self.identity = identity
    }

    public var supersededLines: [DeviceID: Line] { supersededAt }

    public var supersededWithoutALine: [DeviceID] {
        standings.filter { $0.value.removedByRecovery && supersededAt[$0.key] == nil }.map(\.key)
    }

    public mutating func fix(_ lines: [DeviceID: Line]) {
        let fresh = lines.filter { supersededAt[$0.key] == nil && standings[$0.key] != nil }
        guard !fresh.isEmpty else { return }
        supersededAt.merge(fresh) { held, _ in held }
        recompute()
    }

    public var deviceCount: Int { standings.count }

    public var deviceIDs: Set<DeviceID> { Set(standings.keys) }

    public var certificates: [DeviceCertificate] {
        standings.keys.compactMap { submitted[$0] }
    }

    public var knownRevocations: [DeviceRevocation] { Array(revocations) }

    public var lastRestoredDevice: DeviceID? {
        let roots = submitted.values.filter(\.isRecovery)
        guard roots.count > 1 else { return nil }
        return roots.max {
            $0.issuedAt != $1.issuedAt
                ? $0.issuedAt < $1.issuedAt : $0.digest.lexicographicallyPrecedes($1.digest)
        }?.device
    }

    public var storedTimes: [Data: Date] { stored }

    public func storedAt(_ digest: Data) -> Date? { stored[digest] }

    public func publishedAt(_ device: DeviceID) -> Date? {
        submitted[device].flatMap { stored[$0.digest] }
    }

    public mutating func settle(_ digest: Data, storedAt: Date) {
        guard stored[digest] != nil, stored[digest] != storedAt else { return }
        stored[digest] = storedAt
        recompute()
    }

    public mutating func admit(_ certificate: DeviceCertificate, storedAt: Date) throws {
        try certificate.verify(against: identity)
        if submitted[certificate.device] == nil {
            guard let place = place(for: certificate, storedAt: storedAt) else { return }
            certificatePlaces[certificate.device] = place
        }
        note(certificate.digest, storedAt)

        if let existing = submitted[certificate.device] {
            guard existing.devicePublicKey == certificate.devicePublicKey else {
                throw CryptoError.deviceMismatch
            }
            let upgrade =
                existing.agreementKey == nil && certificate.agreementKey != nil
                && existing.issuedAt == certificate.issuedAt && existing.approvedBy == certificate.approvedBy
            guard upgrade else {
                recompute()
                return
            }
            if let earlier = stored[existing.digest] { note(certificate.digest, earlier) }
        }
        submitted[certificate.device] = certificate
        recompute()
    }

    mutating func admit(_ certificate: DeviceCertificate) throws {
        try admit(certificate, storedAt: certificate.issuedAt)
    }

    public mutating func revoke(_ revocation: DeviceRevocation, storedAt: Date) throws {
        try revocation.verify(against: identity)
        guard let remover = revocation.revokedBy else { throw CryptoError.notAuthorized }
        guard submitted[revocation.device] != nil else { throw CryptoError.unknownDevice }
        if !revocations.contains(revocation) {
            guard let place = place(for: revocation, by: remover, storedAt: storedAt) else { return }
            removalPlaces[revocation.digest] = place
        }
        note(revocation.digest, storedAt)
        revocations.insert(revocation)
        recompute()
    }

    mutating func revoke(_ revocation: DeviceRevocation) throws {
        try revoke(revocation, storedAt: revocation.revokedAt)
    }

    private var newestRoot: DeviceID? {
        submitted.values.filter(\.isRecovery).max {
            $0.issuedAt != $1.issuedAt
                ? $0.issuedAt < $1.issuedAt : $0.digest.lexicographicallyPrecedes($1.digest)
        }?.device
    }

    private func place(for certificate: DeviceCertificate, storedAt: Date) -> Place? {
        if certificate.isRecovery {
            return certificatePlaces.values.count(where: { $0 == .root }) < Self.mostDevices ? .root : nil
        }
        if let approver = certificate.approvedBy, counts(approver, storedAt: storedAt),
            let key = submitted[approver]?.devicePublicKey, certificate.isApproved(byKey: key)
        {
            let lineage = newestRoot
            let byApprover = certificatePlaces.values.count {
                if case .signed(by: approver, _) = $0 { return true }
                return false
            }
            let inLineage = certificatePlaces.values.count {
                if case .signed(_, lineage: lineage) = $0 { return true }
                return false
            }
            guard byApprover < Self.mostApprovalsByOneDevice, inLineage < Self.mostDevices else { return nil }
            return .signed(by: approver, lineage: lineage)
        }
        return certificatePlaces.values.count(where: { $0 == .unproven }) < Self.mostDevices ? .unproven : nil
    }

    private func place(for revocation: DeviceRevocation, by remover: DeviceID, storedAt: Date) -> Place? {
        if counts(remover, storedAt: storedAt), let key = submitted[remover]?.devicePublicKey,
            revocation.isSigned(byKey: key)
        {
            let byRemover = removalPlaces.values.count {
                if case .signed(by: remover, _) = $0 { return true }
                return false
            }
            return byRemover < Self.mostRemovalsByOneDevice ? .signed(by: remover, lineage: nil) : nil
        }
        return removalPlaces.values.count(where: { $0 == .unproven }) < Self.mostDevices ? .unproven : nil
    }

    public func standing(of device: DeviceID) -> Standing? {
        standings[device]
    }

    public func isPending(_ device: DeviceID) -> Bool {
        guard let certificate = submitted[device], standings[device] == nil else { return false }
        return certificate.approvedBy != nil || certificate.isRecovery
    }

    public func agreementKey(for device: DeviceID) -> Data? {
        standings[device] == nil ? nil : submitted[device]?.agreementKey
    }

    public var activeDevices: Set<DeviceID> {
        Set(standings.filter { $0.value.revokedAt == nil }.keys)
    }

    public func signingKey(for device: DeviceID) -> Data? {
        standings[device] == nil ? nil : submitted[device]?.devicePublicKey
    }

    public func counts(_ device: DeviceID, storedAt instant: Date) -> Bool {
        windows[device]?.covers(instant) ?? false
    }

    public func isAuthorized(_ device: DeviceID, at instant: Date, seq: UInt64? = nil, hash: EntryHash? = nil) -> Bool {
        guard let standing = standings[device] else { return false }
        guard standing.revokedAt != nil, let seq else { return Self.covers(standing, instant) }
        return instant >= standing.addedAt
            && standing.limits.allSatisfy { $0.admits(seq: seq, hash: hash, at: instant) }
    }

    public func line(of device: DeviceID) -> UInt64? {
        standings[device]?.line
    }

    public mutating func noteWhatWasSeen(by witness: DeviceID, in clock: VectorClock) {
        guard standings[witness] != nil else { return }
        var raised: Set<DeviceID> = []
        for (feed, seq) in clock.positions
        where feed.author == identity.participantID && feed.device != witness && standings[feed.device] != nil {
            guard seq > witnessed[feed.device]?[witness] ?? 0 else { continue }
            witnessed[feed.device, default: [:]][witness] = seq
            raised.insert(feed.device)
        }
        for device in raised where standings[device]?.limits.isEmpty == false { weighEvidence(for: device) }
    }

    private func statement(of witness: DeviceID, about device: DeviceID, in standing: Standing) -> UInt64 {
        let removed = standing.limits.filter { $0.remover == witness }.compactMap(\.cutoff).max() ?? 0
        return Swift.max(witnessed[device]?[witness] ?? 0, removed)
    }

    private mutating func weighEvidence(for device: DeviceID) {
        guard var standing = standings[device], !standing.limits.isEmpty else { return }
        let counting = standings.filter { $0.key != device && $0.value.revokedAt == nil }.keys
        let fromCounting = counting.map { statement(of: $0, about: device, in: standing) }.max() ?? 0
        for index in standing.limits.indices where standing.limits[index].weighsEvidence {
            let fromRemover = standing.limits[index].remover.map { statement(of: $0, about: device, in: standing) } ?? 0
            standing.limits[index].seen = Swift.max(fromCounting, fromRemover)
        }
        standing.line = standing.limits.compactMap(\.bound).min()
        let anchor = standing.limits.filter { $0.cutoff != nil && !$0.isContradicted }
            .min { ($0.cutoff ?? .max) < ($1.cutoff ?? .max) }
        standing.cutoff = anchor?.cutoff
        standing.head = anchor?.head
        standings[device] = standing
    }

    private mutating func note(_ digest: Data, _ instant: Date) {
        if let known = stored[digest], known <= instant { return }
        stored[digest] = instant
    }

    private static func covers(_ standing: Standing, _ instant: Date) -> Bool {
        guard instant >= standing.addedAt else { return false }
        guard let revokedAt = standing.revokedAt else { return true }
        return instant < revokedAt
    }

    private struct Authority: Hashable, Sendable {
        let from: Date
        var until: Date?

        func covers(_ instant: Date) -> Bool {
            guard instant >= from else { return false }
            guard let until else { return true }
            return instant < until
        }
    }

    private struct Removal {
        let order: Date
        let revokedAt: Date
        let revokedBy: DeviceID?
        let cutoff: UInt64?
        let head: EntryHash?

        init(order: Date, revocation: DeviceRevocation) {
            self.order = order
            revokedAt = revocation.revokedAt
            revokedBy = revocation.revokedBy
            cutoff = revocation.cutoff
            head = revocation.head
        }

        init(order: Date, leftOutOf revocation: DeviceRevocation) {
            self.order = order
            revokedAt = revocation.revokedAt
            revokedBy = revocation.revokedBy
            cutoff = 0
            head = nil
        }
    }

    private mutating func recompute() {
        let roots = submitted.values.filter(\.isRecovery).sorted {
            if $0.issuedAt != $1.issuedAt { return $0.issuedAt < $1.issuedAt }
            return $0.digest.lexicographicallyPrecedes($1.digest)
        }
        var combined: [DeviceID: Standing] = [:]
        var current: [DeviceID: Authority] = [:]
        for (index, root) in roots.enumerated().reversed() {
            let next = index + 1 < roots.count ? roots[index + 1] : nil
            let (lineage, authority) = replay(from: root)
            for (device, standing) in lineage where combined[device] == nil {
                var capped = standing
                if let next, capped.revokedAt.map({ next.issuedAt < $0 }) ?? true {
                    capped.revokedAt = next.issuedAt
                    capped.revokedBy = next.device
                    capped.removedByRecovery = true
                    let line = supersededAt[device]
                    capped.limits.append(
                        Limit(cutoff: line?.seq, head: line?.head, before: next.issuedAt, remover: nil, alsoByDate: true))
                }
                combined[device] = capped
            }
            if next == nil { current = authority }
        }
        standings = combined
        windows = current
        for device in standings.keys { weighEvidence(for: device) }
    }

    private func replay(from root: DeviceCertificate) -> ([DeviceID: Standing], [DeviceID: Authority]) {
        var authority: [DeviceID: Authority] = [root.device: Authority(from: .distantPast, until: nil)]
        var result: [DeviceID: Standing] = [
            root.device: Standing(
                addedAt: root.issuedAt, revokedAt: nil, approvedBy: nil, revokedBy: nil, recovered: true)
        ]
        var removedFirst: [DeviceID: Removal] = [:]

        func sortedForReplay<Event>(_ events: [Event], claimed: (Event) -> Date, digest: (Event) -> Data)
            -> [Event]
        {
            events.sorted {
                let (left, right) = (claimed($0), claimed($1))
                if left != right { return left < right }
                return digest($0).lexicographicallyPrecedes(digest($1))
            }
        }

        func apply(_ removal: Removal, to target: DeviceID) {
            if var power = authority[target] {
                if power.until.map({ removal.order < $0 }) ?? true { power.until = removal.order }
                authority[target] = power
            }
            if var standing = result[target] {
                if standing.revokedAt.map({ removal.revokedAt < $0 }) ?? true {
                    standing.revokedAt = removal.revokedAt
                    standing.revokedBy = removal.revokedBy
                }
                standing.limits.append(
                    Limit(
                        cutoff: removal.cutoff, head: removal.head, before: removal.revokedAt,
                        remover: removal.revokedBy))
                result[target] = standing
            }
        }

        func descends(_ device: DeviceID, from ancestor: DeviceID) -> Bool {
            var approver = result[device]?.approvedBy
            var steps = 0
            while let current = approver, steps < result.count {
                if current == ancestor { return true }
                approver = result[current]?.approvedBy
                steps += 1
            }
            return false
        }

        func leaveOut(everyDeviceApprovedThrough revocation: DeviceRevocation, at instant: Date) {
            guard let remaining = revocation.remaining.map(Set.init) else { return }
            let unnamed = result.keys.filter {
                !remaining.contains($0) && authority[$0].map { $0.until == nil } == true
                    && descends($0, from: revocation.device)
            }
            for device in unnamed { apply(Removal(order: instant, leftOutOf: revocation), to: device) }
        }

        let added = submitted.values.filter { !$0.isRecovery }.compactMap { certificate in
            stored[certificate.digest].map { (order: $0, certificate: certificate) }
        }
        let removed = revocations.compactMap { revocation in
            stored[revocation.digest].map { (order: $0, revocation: revocation) }
        }
        let instants = Set(added.map(\.order) + removed.map(\.order)).sorted()
        let addedAt = Dictionary(grouping: added, by: \.order)
        let removedAt = Dictionary(grouping: removed, by: \.order)

        for instant in instants {
            var waiting = sortedForReplay(
                (addedAt[instant] ?? []).map(\.certificate), claimed: \.issuedAt, digest: \.digest)
            var progressed = true
            while progressed {
                progressed = false
                for certificate in waiting {
                    guard let approver = certificate.approvedBy,
                        authority[approver]?.covers(instant) == true,
                        let key = submitted[approver]?.devicePublicKey,
                        certificate.isApproved(byKey: key)
                    else { continue }
                    authority[certificate.device] = Authority(from: instant, until: nil)
                    result[certificate.device] = Standing(
                        addedAt: certificate.issuedAt, revokedAt: nil, approvedBy: certificate.approvedBy,
                        revokedBy: nil, recovered: false)
                    if let earlier = removedFirst[certificate.device] { apply(earlier, to: certificate.device) }
                    waiting.removeAll { $0 == certificate }
                    progressed = true
                }
            }

            let removals = sortedForReplay(
                (removedAt[instant] ?? []).map(\.revocation), claimed: \.revokedAt, digest: \.digest)
            for revocation in removals {
                guard let revoker = revocation.revokedBy, authority[revoker]?.covers(instant) == true,
                    let key = submitted[revoker]?.devicePublicKey, revocation.isSigned(byKey: key)
                else { continue }
                let removal = Removal(order: instant, revocation: revocation)
                if authority[revocation.device] != nil {
                    apply(removal, to: revocation.device)
                    leaveOut(everyDeviceApprovedThrough: revocation, at: instant)
                } else if removedFirst[revocation.device].map({ instant < $0.order }) ?? true {
                    removedFirst[revocation.device] = removal
                }
            }
        }
        return (result, authority)
    }
}
