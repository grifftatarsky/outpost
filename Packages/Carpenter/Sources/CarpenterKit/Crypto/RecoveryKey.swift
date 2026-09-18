import CryptoKit
import Foundation

public enum RecoveryKey {
    public static let header = "OUTPOST RECOVERY KEY"

    public static let version = 1

    public enum Failure: Error, Equatable {
        case notARecoveryKey
        case fromANewerVersion(Int)
        case damaged
    }

    public static func text(for identity: Identity, createdAt: Date) -> String {
        let signing = identity.signingSeed.base64EncodedString()
        let agreement = identity.agreementSeed.base64EncodedString()
        let made = ISO8601DateFormatter().string(from: createdAt)
        return """
            \(header) v\(version)

            Anybody with this file can become you. There is no way to change it and no way to
            revoke it. Keep it where you keep passwords, not where you keep photographs.

            It restores who you are, not what was said. Your conversations come back from the
            people you were talking to. Anything nobody else still holds is gone.

            Created: \(made)
            Fingerprint: \(fingerprint(of: identity))

            SIGNING: \(signing)
            AGREEMENT: \(agreement)
            CHECK: \(checksum(signingSeed: identity.signingSeed, agreementSeed: identity.agreementSeed))
            """
    }

    public static func identity(from text: String) throws -> Identity {
        let lines = text.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let headerLine = lines.first(where: { $0.hasPrefix(header) }) else {
            throw Failure.notARecoveryKey
        }

        let stamped = headerLine.dropFirst(header.count).trimmingCharacters(in: .whitespaces)
        if stamped.hasPrefix("v"), let found = Int(stamped.dropFirst()), found > version {
            throw Failure.fromANewerVersion(found)
        }

        func field(_ name: String) -> String? {
            lines.first { $0.hasPrefix("\(name):") }?
                .dropFirst(name.count + 1).trimmingCharacters(in: .whitespaces)
        }

        guard let signingText = field("SIGNING"), let agreementText = field("AGREEMENT"),
            let signingSeed = Data(base64Encoded: signingText),
            let agreementSeed = Data(base64Encoded: agreementText)
        else { throw Failure.damaged }

        guard let check = field("CHECK"),
            check == checksum(signingSeed: signingSeed, agreementSeed: agreementSeed)
        else { throw Failure.damaged }

        do {
            return try Identity(signingSeed: signingSeed, agreementSeed: agreementSeed)
        } catch {
            throw Failure.damaged
        }
    }

    public static func fingerprint(of identity: Identity) -> String {
        identity.id.shortCode
    }

    private static func checksum(signingSeed: Data, agreementSeed: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: signingSeed)
        hasher.update(data: agreementSeed)
        let digest = Data(hasher.finalize())
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String(digest.prefix(8).map { alphabet[Int($0) % alphabet.count] })
    }
}
