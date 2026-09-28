import Foundation

public struct Invite: Hashable, Sendable, Codable {
    public let attestation: MembershipAttestation

    public let pair: SignedPairLink?

    public init(attestation: MembershipAttestation, pair: SignedPairLink? = nil) {
        self.attestation = attestation
        self.pair = pair
    }

    public var verifiedPair: PairLink? { pair?.verified(by: attestation.inviterKeys) }

    public func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self).base64URLEncodedString()
    }

    public static func decoded(from text: String) throws -> Invite {
        guard let data = Data(base64URLEncoded: InviteLink.payload(in: text)) else {
            throw MembershipError.malformedInvite
        }
        if let invite = try? JSONDecoder().decode(Invite.self, from: data) { return invite }
        return Invite(attestation: try JSONDecoder().decode(MembershipAttestation.self, from: data))
    }
}

public struct SignedPairLink: Hashable, Sendable, Codable {
    public let link: PairLink
    public let signature: Data

    public init(link: PairLink, signature: Data) {
        self.link = link
        self.signature = signature
    }

    public static func sign(_ link: PairLink, by identity: Identity) throws -> SignedPairLink {
        SignedPairLink(link: link, signature: try identity.sign(signingPayload(of: link, for: identity.id)))
    }

    public func verified(by keys: IdentityPublicKeys) -> PairLink? {
        let valid = try? keys.isValidSignature(signature, for: Self.signingPayload(of: link, for: keys.participantID))
        return valid == true ? link : nil
    }

    static func signingPayload(of link: PairLink, for owner: ParticipantID) -> Data {
        CanonicalBytes.payload(
            domain: Domain.pairLinkSignature,
            fields: [owner.rawValue, Data(link.account.utf8), Data(link.url.absoluteString.utf8)])
    }
}
