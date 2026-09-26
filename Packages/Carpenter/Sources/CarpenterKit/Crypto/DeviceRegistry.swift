import Foundation

public struct DeviceRegistry: Hashable, Sendable {
    public struct Standing: Hashable, Sendable {
        public let addedAt: Date
        public fileprivate(set) var revokedAt: Date?
        public let approvedBy: DeviceID?
        public fileprivate(set) var revokedBy: DeviceID?

        public var isRoot: Bool { approvedBy == nil }
    }

    public let identity: IdentityPublicKeys

    private var submitted: [DeviceID: DeviceCertificate] = [:]
    private var revocations: Set<DeviceRevocation> = []
    private var standings: [DeviceID: Standing] = [:]

    public init(identity: IdentityPublicKeys) {
        self.identity = identity
    }

    public var deviceCount: Int { standings.count }

    public var deviceIDs: Set<DeviceID> { Set(standings.keys) }

    public var certificates: [DeviceCertificate] {
        standings.keys.compactMap { submitted[$0] }
    }

    public var knownRevocations: [DeviceRevocation] { Array(revocations) }

    public mutating func admit(_ certificate: DeviceCertificate) throws {
        try certificate.verify(against: identity)

        if let existing = submitted[certificate.device] {
            guard existing.devicePublicKey == certificate.devicePublicKey else {
                throw CryptoError.deviceMismatch
            }
            let upgrade =
                existing.agreementKey == nil && certificate.agreementKey != nil
                && existing.issuedAt == certificate.issuedAt && existing.approvedBy == certificate.approvedBy
            guard upgrade else { return }
        }
        submitted[certificate.device] = certificate
        recompute()
    }

    public mutating func revoke(_ revocation: DeviceRevocation) throws {
        try revocation.verify(against: identity)
        guard submitted[revocation.device] != nil else { throw CryptoError.unknownDevice }
        guard !revocations.contains(revocation) else { return }
        revocations.insert(revocation)
        recompute()
    }

    public func standing(of device: DeviceID) -> Standing? {
        standings[device]
    }

    public func isPending(_ device: DeviceID) -> Bool {
        submitted[device] != nil && standings[device] == nil
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

    public func isAuthorized(_ device: DeviceID, at instant: Date) -> Bool {
        standings[device].map { Self.covers($0, instant) } ?? false
    }

    public func isValidSignature(
        _ signature: Data, for message: Data, from device: DeviceID, at instant: Date
    ) throws -> Bool {
        guard isAuthorized(device, at: instant), let publicKey = signingKey(for: device) else {
            return false
        }
        return try DeviceKeys.isValidSignature(signature, for: message, publicKey: publicKey)
    }

    private static func covers(_ standing: Standing, _ instant: Date) -> Bool {
        guard instant >= standing.addedAt else { return false }
        guard let revokedAt = standing.revokedAt else { return true }
        return instant < revokedAt
    }

    private enum Event {
        case added(DeviceCertificate)
        case removed(DeviceRevocation)

        var at: Date {
            switch self {
            case .added(let certificate): certificate.issuedAt
            case .removed(let revocation): revocation.revokedAt
            }
        }
    }

    private mutating func recompute() {
        var result: [DeviceID: Standing] = [:]
        var revokedEarly: [DeviceID: (Date, DeviceID?)] = [:]

        let events = submitted.values.map(Event.added) + revocations.map(Event.removed)
        let byTime = Dictionary(grouping: events, by: \.at).sorted { $0.key < $1.key }

        for (instant, group) in byTime {
            var waiting = group.compactMap { event -> DeviceCertificate? in
                if case .added(let certificate) = event { return certificate }
                return nil
            }
            var progressed = true
            while progressed {
                progressed = false
                for certificate in waiting {
                    guard let approver = certificate.approvedBy else {
                        result[certificate.device] = Standing(
                            addedAt: instant, revokedAt: nil, approvedBy: nil, revokedBy: nil)
                        waiting.removeAll { $0 == certificate }
                        progressed = true
                        continue
                    }
                    guard let standing = result[approver], Self.covers(standing, instant),
                        let key = submitted[approver]?.devicePublicKey,
                        certificate.isApproved(byKey: key)
                    else { continue }
                    result[certificate.device] = Standing(
                        addedAt: instant, revokedAt: nil, approvedBy: approver, revokedBy: nil)
                    waiting.removeAll { $0 == certificate }
                    progressed = true
                }
            }

            for event in group {
                guard case .removed(let revocation) = event else { continue }
                if let revoker = revocation.revokedBy {
                    guard let standing = result[revoker], Self.covers(standing, instant),
                        let key = submitted[revoker]?.devicePublicKey,
                        revocation.isSigned(byKey: key)
                    else { continue }
                }
                let target = revocation.device
                if var standing = result[target] {
                    if standing.revokedAt.map({ instant < $0 }) ?? true {
                        standing.revokedAt = instant
                        standing.revokedBy = revocation.revokedBy
                    }
                    result[target] = standing
                } else if revokedEarly[target].map({ instant < $0.0 }) ?? true {
                    revokedEarly[target] = (instant, revocation.revokedBy)
                }
            }
        }

        for (device, early) in revokedEarly {
            guard var standing = result[device] else { continue }
            if standing.revokedAt.map({ early.0 < $0 }) ?? true {
                standing.revokedAt = early.0
                standing.revokedBy = early.1
            }
            result[device] = standing
        }
        standings = result
    }
}
