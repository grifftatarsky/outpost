import Foundation

public enum AuthorityEvent: Hashable, Sendable {
    case added(DeviceCertificate)
    case removed(DeviceRevocation)

    public var digest: Data {
        switch self {
        case .added(let certificate): certificate.digest
        case .removed(let revocation): revocation.digest
        }
    }

    public var participant: ParticipantID {
        switch self {
        case .added(let certificate): certificate.participant
        case .removed(let revocation): revocation.participant
        }
    }

    public func record(sealedFor identity: Identity, by writer: DeviceID) throws -> SiblingRecord {
        let kind = SiblingRecord.Kind.authority(digest)
        let feed: SiblingFeed
        switch self {
        case .added(let certificate):
            feed = SiblingFeed(entries: [], certificates: [certificate], member: identity.id)
        case .removed(let revocation):
            feed = SiblingFeed(entries: [], certificates: [], member: identity.id, revocations: [revocation])
        }
        return SiblingRecord(
            name: SiblingRecord.Name(writer: writer, kind: kind),
            sealed: try SealedSiblingFeed.seal(feed, for: identity, on: writer, as: kind))
    }

    public init(record: SiblingRecord, openedWith identity: Identity) throws {
        guard case .authority(let digest) = record.name.kind else { throw CryptoError.openFailed }
        let feed = try record.sealed.open(with: identity, from: record.name.writer, as: record.name.kind)
        switch (feed.certificates, feed.revocations) {
        case (let certificates, []) where certificates.count == 1:
            self = .added(certificates[0])
        case ([], let revocations) where revocations.count == 1:
            self = .removed(revocations[0])
        default:
            throw CryptoError.openFailed
        }
        guard self.digest == digest else { throw CryptoError.openFailed }
    }
}
