import Foundation

public struct MembershipAttestation: Hashable, Sendable, Codable {
    public var room: RoomID
    public var joiner: ParticipantID
    public var joinerKeys: IdentityPublicKeys
    public var inviter: ParticipantID
    public var inviterKeys: IdentityPublicKeys
    public var issuedAt: Date
    public var expiresAt: Date

    /// `SHA256` of a nonce the joiner picked before this was signed, taken from their code. The
    /// verification phrase cannot be computed without the nonce, so the inviter has nothing to
    /// grind with — see `JoinCommitment`.
    public var joinerCommitment: Data

    public var joinerRequires: PhraseLength
    public var inviterRequires: PhraseLength

    public var signature: Data

    public static let defaultLifetime: TimeInterval = 24 * 60 * 60

    public init(
        room: RoomID,
        joiner: ParticipantID,
        joinerKeys: IdentityPublicKeys,
        inviter: ParticipantID,
        inviterKeys: IdentityPublicKeys,
        issuedAt: Date,
        expiresAt: Date,
        joinerCommitment: Data = Data(),
        joinerRequires: PhraseLength = .standard,
        inviterRequires: PhraseLength = .standard,
        signature: Data
    ) {
        self.room = room
        self.joiner = joiner
        self.joinerKeys = joinerKeys
        self.inviter = inviter
        self.inviterKeys = inviterKeys
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.joinerCommitment = joinerCommitment
        self.joinerRequires = joinerRequires
        self.inviterRequires = inviterRequires
        self.signature = signature
    }

    /// What the two of them will read to each other: whichever of the two is stricter.
    public var phraseLength: PhraseLength {
        PhraseLength.agreed(joinerRequires, inviterRequires)
    }

    public static func issue(
        joining room: RoomID,
        joinerKeys: IdentityPublicKeys,
        by identity: Identity,
        at issuedAt: Date,
        lifetime: TimeInterval = defaultLifetime,
        joinerCommitment: Data = Data(),
        joinerRequires: PhraseLength = .standard,
        inviterRequires: PhraseLength = .standard
    ) throws -> MembershipAttestation {
        var attestation = MembershipAttestation(
            room: room,
            joiner: joinerKeys.participantID,
            joinerKeys: joinerKeys,
            inviter: identity.id,
            inviterKeys: identity.publicKeys,
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(lifetime),
            joinerCommitment: joinerCommitment,
            joinerRequires: joinerRequires,
            inviterRequires: inviterRequires,
            signature: Data()
        )
        attestation.signature = try identity.sign(attestation.signingPayload)
        return attestation
    }

    public static func issue(
        joining room: RoomID,
        code: JoinerCode,
        by identity: Identity,
        at issuedAt: Date,
        lifetime: TimeInterval = defaultLifetime,
        requiring mine: PhraseLength = .standard
    ) throws -> MembershipAttestation {
        try issue(
            joining: room, joinerKeys: code.keys, by: identity, at: issuedAt, lifetime: lifetime,
            joinerCommitment: code.commitment, joinerRequires: code.requires,
            inviterRequires: mine)
    }

    var signingPayload: Data {
        CanonicalBytes.payload(
            domain: Domain.membershipAttestation,
            fields: [
                room.canonicalBytes,
                joiner.rawValue,
                joinerKeys.signing,
                joinerKeys.agreement,
                inviter.rawValue,
                inviterKeys.signing,
                inviterKeys.agreement,
                CanonicalBytes.timestamp(issuedAt),
                CanonicalBytes.timestamp(expiresAt),
                joinerCommitment,
                joinerRequires.canonicalBytes,
                inviterRequires.canonicalBytes,
            ]
        )
    }

    public func verify(
        against inviterKeys: IdentityPublicKeys, at instant: Date, allowingExpired: Bool = false
    ) throws {
        guard inviter == inviterKeys.participantID else { throw MembershipError.wrongInviter }
        guard self.inviterKeys == inviterKeys else { throw MembershipError.wrongInviter }
        guard joiner == joinerKeys.participantID else { throw MembershipError.wrongJoiner }
        guard allowingExpired || instant < expiresAt else { throw MembershipError.expired }
        guard try inviterKeys.isValidSignature(signature, for: signingPayload) else {
            throw MembershipError.badSignature
        }
    }

    public func verifyAsJoiner(at instant: Date) throws {
        try verify(against: inviterKeys, at: instant)
    }

    /// The characters two people read to each other, or `nil` until the joiner's nonce has arrived.
    ///
    /// The **signature is deliberately not in the transcript.** Two different valid signatures over
    /// one payload mean the same thing — `verify(against:at:)` checks the signature separately — so
    /// including it attested nothing extra while handing whoever produced it unlimited post-hoc
    /// freedom to grind. The nonce is what the transcript takes instead, and unlike a signature it
    /// was fixed before the signing happened.
    public func verificationPhrase(opening nonce: Data?) -> String? {
        guard let nonce, JoinCommitment.opens(nonce, joinerCommitment) else { return nil }
        return ShortAuthenticationString.derive(
            fromTranscript: signingPayload + nonce, length: phraseLength)
    }
}

/// What a joiner hands out so somebody can invite them: their public keys, the commitment that
/// stops the inviter grinding the phrase, and how many characters they insist on reading.
///
/// **Single use.** The commitment is only worth anything while its nonce is unknown, so a code
/// shown to two people would let the first grind against the second. A fresh one is minted each
/// time the code is shown, and the issuing device keeps the outstanding nonces until they lapse.
public struct JoinerCode: Hashable, Sendable, Codable {
    public let keys: IdentityPublicKeys
    public let commitment: Data
    public let requires: PhraseLength

    public init(keys: IdentityPublicKeys, commitment: Data, requires: PhraseLength = .standard) {
        self.keys = keys
        self.commitment = commitment
        self.requires = requires
    }

    public var participantID: ParticipantID { keys.participantID }

    public func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self).base64URLEncodedString()
    }

    public static func decoded(from text: String) throws -> JoinerCode {
        guard let data = Data(base64URLEncoded: InviteLink.payload(in: text)) else {
            throw MembershipError.malformedInvite
        }
        return try JSONDecoder().decode(JoinerCode.self, from: data)
    }
}

public enum MembershipError: Error, Hashable, Sendable {
    case wrongInviter
    case wrongJoiner
    case expired
    case badSignature
    case inviterNotAMember
    case wrongRoom
    case malformedInvite
    case notTheFounder
    case notAMember
    case cannotRemoveYourself
    case removedFromThisRoom
    case leftThisRoom
    case soloNotVerified
    case alreadyInTheRoom
    case invitationWithdrawn
    case unknownInviter
    case commitmentNotOpened
    case stillInTheRoom
    case departureNotSent
}

extension IdentityPublicKeys {
    public func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self).base64URLEncodedString()
    }

    public static func decoded(from text: String) throws -> IdentityPublicKeys {
        guard let data = Data(base64URLEncoded: InviteLink.payload(in: text)) else {
            throw MembershipError.malformedInvite
        }
        return try JSONDecoder().decode(IdentityPublicKeys.self, from: data)
    }
}

extension MembershipAttestation {
    public func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self).base64URLEncodedString()
    }

    public static func decoded(from text: String) throws -> MembershipAttestation {
        guard let data = Data(base64URLEncoded: InviteLink.payload(in: text)) else {
            throw MembershipError.malformedInvite
        }
        return try JSONDecoder().decode(MembershipAttestation.self, from: data)
    }
}
