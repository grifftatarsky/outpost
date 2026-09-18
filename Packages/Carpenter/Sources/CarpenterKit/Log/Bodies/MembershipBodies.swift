import Foundation

// MARK: Getting into a room, out of one, and the keys in between

public struct JoinRequestBody: Hashable, Sendable, Codable {
    public let attestation: MembershipAttestation

    public init(attestation: MembershipAttestation) {
        self.attestation = attestation
    }
}

public struct JoinConfirmedBody: Hashable, Sendable, Codable {
    public let invitation: Data
    public let joiner: ParticipantID

    /// The joiner opening the commitment they published in their code, **after** the inviter signed.
    /// Until this arrives the inviter cannot compute the verification phrase, which is the whole
    /// point: it leaves them nothing to grind with. Carried here rather than in a body of its own
    /// because this is already the one thing the joiner sends back.
    public let nonce: Data

    public let signature: Data

    public init(invitation: Data, joiner: ParticipantID, nonce: Data = Data(), signature: Data) {
        self.invitation = invitation
        self.joiner = joiner
        self.nonce = nonce
        self.signature = signature
    }

    private enum CodingKeys: String, CodingKey { case invitation, joiner, nonce, signature }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        invitation = try container.decode(Data.self, forKey: .invitation)
        joiner = try container.decode(ParticipantID.self, forKey: .joiner)
        nonce = try container.decodeIfPresent(Data.self, forKey: .nonce) ?? Data()
        signature = try container.decode(Data.self, forKey: .signature)
    }

    public static func signedBytes(invitation: Data, joiner: ParticipantID, nonce: Data) -> Data {
        CanonicalBytes.payload(
            domain: Domain.joinConfirmed, fields: [invitation, joiner.rawValue, nonce])
    }

    public static func signed(
        confirming attestation: MembershipAttestation, opening nonce: Data, by identity: Identity
    ) throws -> JoinConfirmedBody {
        let joiner = identity.id
        return JoinConfirmedBody(
            invitation: attestation.signature,
            joiner: joiner,
            nonce: nonce,
            signature: try identity.sign(
                signedBytes(invitation: attestation.signature, joiner: joiner, nonce: nonce)))
    }

    public func verify(confirming attestation: MembershipAttestation) throws {
        guard invitation == attestation.signature else { throw MembershipError.wrongRoom }
        guard joiner == attestation.joiner else { throw MembershipError.wrongJoiner }
        guard
            try attestation.joinerKeys.isValidSignature(
                signature,
                for: Self.signedBytes(invitation: invitation, joiner: joiner, nonce: nonce))
        else { throw MembershipError.badSignature }
        guard JoinCommitment.opens(nonce, attestation.joinerCommitment) else {
            throw MembershipError.commitmentNotOpened
        }
    }
}

public struct InvitationRescindedBody: Hashable, Sendable, Codable {
    public let invitation: Data

    public init(invitation: Data) {
        self.invitation = invitation
    }
}

public struct SoloCheckBody: Hashable, Sendable, Codable {
    public enum Move: String, Hashable, Sendable, Codable, CaseIterable {
        case asked
        case confirmed
        case refused
    }

    public let move: Move
    public let answering: EntryHash?

    public init(move: Move, answering: EntryHash?) {
        self.move = move
        self.answering = answering
    }
}

public struct RemovalBody: Hashable, Sendable, Codable {
    public let removed: ParticipantID

    public init(removed: ParticipantID) {
        self.removed = removed
    }
}

public struct DepartureBody: Hashable, Sendable, Codable {
    public init() {}
}

public struct AdmissionBody: Hashable, Sendable, Codable {
    public let joiner: ParticipantID
    public let admitted: Bool

    public let invitation: Data?

    public init(joiner: ParticipantID, admitted: Bool, invitation: Data? = nil) {
        self.joiner = joiner
        self.admitted = admitted
        self.invitation = invitation
    }

    private enum CodingKeys: String, CodingKey { case joiner, admitted, invitation }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        joiner = try container.decode(ParticipantID.self, forKey: .joiner)
        admitted = try container.decode(Bool.self, forKey: .admitted)
        invitation = try container.decodeIfPresent(Data.self, forKey: .invitation)
    }
}

public struct EpochChangeBody: Hashable, Sendable, Codable {
    public let link: EpochLink

    public init(link: EpochLink) {
        self.link = link
    }
}

public struct RoomAccessBody: Hashable, Sendable, Codable {
    public var access: RoomAccess

    public init(access: RoomAccess) {
        self.access = access
    }
}

public enum RoomKind: String, Hashable, Sendable, Codable {
    case room
    case solo
}

public struct RoomProfileBody: Hashable, Sendable, Codable {
    public let name: String

    public let kind: RoomKind?

    public init(name: String, kind: RoomKind? = nil) {
        self.name = name
        self.kind = kind
    }
}
