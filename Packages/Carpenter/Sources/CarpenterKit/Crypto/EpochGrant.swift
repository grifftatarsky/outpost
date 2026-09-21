import Foundation

public struct EpochGrant: Hashable, Sendable, Codable {
    public let room: ConversationID
    public let epoch: EpochNumber

    public let link: EpochLink?

    public let links: [EpochLink]

    let wrapped: Data

    init(room: ConversationID, epoch: EpochNumber, link: EpochLink?, links: [EpochLink] = [], wrapped: Data) {
        self.room = room
        self.epoch = epoch
        self.link = link
        self.links = links
        self.wrapped = wrapped
    }

    private enum CodingKeys: String, CodingKey { case room, epoch, link, links, wrapped }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        room = try container.decode(ConversationID.self, forKey: .room)
        epoch = try container.decode(EpochNumber.self, forKey: .epoch)
        link = try container.decodeIfPresent(EpochLink.self, forKey: .link)
        links = try container.decodeIfPresent([EpochLink].self, forKey: .links) ?? []
        wrapped = try container.decode(Data.self, forKey: .wrapped)
    }

    public static func issue(
        _ secret: EpochSecret, at epoch: EpochNumber, link: EpochLink, to peer: PairwiseSecret
    ) throws -> EpochGrant {
        try issue(secret, at: epoch, in: link.room, link: link, to: peer)
    }

    public static func issue(
        _ secret: EpochSecret, at epoch: EpochNumber, in room: ConversationID, link: EpochLink?,
        links: [EpochLink] = [], to peer: PairwiseSecret
    ) throws -> EpochGrant {
        let context = Self.context(room: room, epoch: epoch)
        return EpochGrant(
            room: room,
            epoch: epoch,
            link: link,
            links: links.filter { $0.room == room && $0.epoch != link?.epoch },
            wrapped: try peer.wrap(secret.material, context: context)
        )
    }

    public func open(with peer: PairwiseSecret) throws -> EpochSecret {
        EpochSecret(
            material: try peer.unwrap(wrapped, context: Self.context(room: room, epoch: epoch)))
    }

    private static func context(room: ConversationID, epoch: EpochNumber) -> Data {
        CanonicalBytes.payload(
            domain: Domain.epochGrant, fields: [room.canonicalBytes, epoch.canonicalBytes])
    }
}

extension EpochChain {
    public mutating func adopt(_ grant: EpochGrant, using peer: PairwiseSecret) throws {
        guard grant.room == room else { throw CryptoError.wrongRoom }
        adopt(try grant.open(with: peer), at: grant.epoch)
        if let link = grant.link { try record(link) }
        try record(grant.links)
    }
}
