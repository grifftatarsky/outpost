import Foundation

public struct DeviceRegistry: Hashable, Sendable {
    public struct Standing: Hashable, Sendable {
        public let addedAt: Date
        public fileprivate(set) var revokedAt: Date?
        public let approvedBy: DeviceID?
        public fileprivate(set) var revokedBy: DeviceID?
        public let recovered: Bool
        public fileprivate(set) var removedByRecovery: Bool = false
    }

    public let identity: IdentityPublicKeys

    private var submitted: [DeviceID: DeviceCertificate] = [:]
    private var revocations: Set<DeviceRevocation> = []
    private var stored: [Data: Date] = [:]
    private var standings: [DeviceID: Standing] = [:]
    private var windows: [DeviceID: Authority] = [:]

    public init(identity: IdentityPublicKeys) {
        self.identity = identity
    }

    public var deviceCount: Int { standings.count }

    public var deviceIDs: Set<DeviceID> { Set(standings.keys) }

    public var certificates: [DeviceCertificate] {
        standings.keys.compactMap { submitted[$0] }
    }

    public var knownRevocations: [DeviceRevocation] { Array(revocations) }

    public var storedTimes: [Data: Date] { stored }

    public func storedAt(_ digest: Data) -> Date? { stored[digest] }

    public mutating func settle(_ digest: Data, storedAt: Date) {
        guard stored[digest] != nil, stored[digest] != storedAt else { return }
        stored[digest] = storedAt
        recompute()
    }

    public mutating func admit(_ certificate: DeviceCertificate, storedAt: Date) throws {
        try certificate.verify(against: identity)
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
        guard revocation.revokedBy != nil else { throw CryptoError.notAuthorized }
        guard submitted[revocation.device] != nil else { throw CryptoError.unknownDevice }
        note(revocation.digest, storedAt)
        revocations.insert(revocation)
        recompute()
    }

    mutating func revoke(_ revocation: DeviceRevocation) throws {
        try revoke(revocation, storedAt: revocation.revokedAt)
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

    public func isAuthorized(_ device: DeviceID, at instant: Date) -> Bool {
        standings[device].map { Self.covers($0, instant) } ?? false
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
        let revocation: DeviceRevocation
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
                }
                combined[device] = capped
            }
            if next == nil { current = authority }
        }
        standings = combined
        windows = current
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
                if standing.revokedAt.map({ removal.revocation.revokedAt < $0 }) ?? true {
                    standing.revokedAt = removal.revocation.revokedAt
                    standing.revokedBy = removal.revocation.revokedBy
                }
                result[target] = standing
            }
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
                } else if removedFirst[revocation.device].map({ instant < $0.order }) ?? true {
                    removedFirst[revocation.device] = removal
                }
            }
        }
        return (result, authority)
    }
}
