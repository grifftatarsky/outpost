import Foundation

public struct EpochGrant: Hashable, Sendable, Codable {
    public let room: RoomID
    public let epoch: EpochNumber

    public let link: EpochLink?

    public let links: [EpochLink]

    let wrapped: Data

    public let sealedFor: [DeviceSeal]

    public private(set) var grantedBy: DeviceID?
    public private(set) var signature: Data?

    init(
        room: RoomID, epoch: EpochNumber, link: EpochLink?, links: [EpochLink] = [], wrapped: Data,
        sealedFor: [DeviceSeal] = []
    ) {
        self.room = room
        self.epoch = epoch
        self.link = link
        self.links = links
        self.wrapped = wrapped
        self.sealedFor = sealedFor
    }

    private enum CodingKeys: String, CodingKey {
        case room, epoch, link, links, wrapped, sealedFor, grantedBy, signature
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        room = try container.decode(RoomID.self, forKey: .room)
        epoch = try container.decode(EpochNumber.self, forKey: .epoch)
        link = try container.decodeIfPresent(EpochLink.self, forKey: .link)
        links = try container.decodeIfPresent([EpochLink].self, forKey: .links) ?? []
        wrapped = try container.decode(Data.self, forKey: .wrapped)
        sealedFor = try container.decodeIfPresent([DeviceSeal].self, forKey: .sealedFor) ?? []
        grantedBy = try container.decodeIfPresent(DeviceID.self, forKey: .grantedBy)
        signature = try container.decodeIfPresent(Data.self, forKey: .signature)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(room, forKey: .room)
        try container.encode(epoch, forKey: .epoch)
        try container.encodeIfPresent(link, forKey: .link)
        try container.encode(links, forKey: .links)
        try container.encode(wrapped, forKey: .wrapped)
        if !sealedFor.isEmpty { try container.encode(sealedFor, forKey: .sealedFor) }
        try container.encodeIfPresent(grantedBy, forKey: .grantedBy)
        try container.encodeIfPresent(signature, forKey: .signature)
    }

    func signingPayload(from granter: ParticipantID, to recipient: ParticipantID, by device: DeviceID) -> Data {
        func link(_ link: EpochLink) -> Data {
            CanonicalBytes.payload(
                domain: Domain.epochLink, fields: [link.room.canonicalBytes, link.epoch.canonicalBytes, link.wrapped])
        }
        var fields = [
            granter.rawValue, recipient.rawValue, device.rawValue, room.canonicalBytes, epoch.canonicalBytes,
            wrapped, self.link.map(link) ?? Data(), CanonicalBytes.sequence(UInt64(links.count)),
        ]
        fields += links.map(link)
        fields.append(CanonicalBytes.sequence(UInt64(sealedFor.count)))
        fields += sealedFor.map {
            CanonicalBytes.payload(domain: Domain.deviceSeal, fields: [$0.device.rawValue, $0.ephemeral, $0.sealed])
        }
        return CanonicalBytes.payload(domain: Domain.epochGrantSignature, fields: fields)
    }

    public func signed(by device: DeviceKeys, from granter: ParticipantID, to recipient: ParticipantID) throws
        -> EpochGrant
    {
        var grant = self
        grant.grantedBy = device.id
        grant.signature = try device.sign(signingPayload(from: granter, to: recipient, by: device.id))
        return grant
    }

    public func isSigned(
        from granter: ParticipantID, to recipient: ParticipantID, by registry: DeviceRegistry, storedAt: Date
    ) -> Bool {
        guard let grantedBy, let signature, !sealedFor.isEmpty, registry.counts(grantedBy, storedAt: storedAt),
            let key = registry.signingKey(for: grantedBy)
        else { return false }
        return (try? DeviceKeys.isValidSignature(
            signature, for: signingPayload(from: granter, to: recipient, by: grantedBy), publicKey: key)) == true
    }

    public static func issue(
        _ secret: EpochSecret, at epoch: EpochNumber, link: EpochLink, to peer: PairwiseSecret
    ) throws -> EpochGrant {
        try issue(secret, at: epoch, in: link.room, link: link, to: peer)
    }

    public static func issue(
        _ secret: EpochSecret, at epoch: EpochNumber, in room: RoomID, link: EpochLink?,
        links: [EpochLink] = [], to peer: PairwiseSecret, devices: [DeviceRecipient] = []
    ) throws -> EpochGrant {
        let context = Self.context(room: room, epoch: epoch)
        let wrapped = try peer.wrap(secret.material, context: context)
        return EpochGrant(
            room: room,
            epoch: epoch,
            link: link,
            links: links.filter { $0.room == room && $0.epoch != link?.epoch },
            wrapped: devices.isEmpty ? wrapped : Data(),
            sealedFor: try devices.map { try DeviceSeal.seal(wrapped, to: $0, context: context) }
        )
    }

    public func open(with peer: PairwiseSecret, as device: DeviceKeys? = nil) throws -> EpochSecret {
        let context = Self.context(room: room, epoch: epoch)
        guard let device, let seal = sealedFor.first(where: { $0.device == device.id }) else {
            throw CryptoError.notSealedForThisDevice
        }
        return EpochSecret(
            material: try peer.unwrap(try seal.open(with: device, context: context), context: context))
    }

    private static func context(room: RoomID, epoch: EpochNumber) -> Data {
        CanonicalBytes.payload(
            domain: Domain.epochGrant, fields: [room.canonicalBytes, epoch.canonicalBytes])
    }
}

extension EpochChain {
    public mutating func adopt(
        _ grant: EpochGrant, using peer: PairwiseSecret, as device: DeviceKeys? = nil
    ) throws {
        guard grant.room == room else { throw CryptoError.wrongRoom }
        let secret = try grant.open(with: peer, as: device)
        if !knownEpochs.contains(grant.epoch) { adopt(secret, at: grant.epoch) }
        if let link = grant.link { try record(link) }
        try record(grant.links)
    }
}
