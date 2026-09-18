import Foundation

public struct Invite: Hashable, Sendable, Codable {
    public let attestation: MembershipAttestation

    public let mailbox: URL?

    public init(attestation: MembershipAttestation, mailbox: URL?) {
        self.attestation = attestation
        self.mailbox = mailbox
    }

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
        return Invite(
            attestation: try JSONDecoder().decode(MembershipAttestation.self, from: data),
            mailbox: nil)
    }
}
