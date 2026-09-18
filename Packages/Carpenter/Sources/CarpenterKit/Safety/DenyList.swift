import CryptoKit
import Foundation

public struct DenyList: Hashable, Sendable {
    public let version: Int
    public let updated: String
    public let fingerprints: Set<String>

    public static let empty = DenyList(version: 0, updated: "", fingerprints: [])

    public init(version: Int, updated: String, fingerprints: Set<String>) {
        self.version = version
        self.updated = updated
        self.fingerprints = fingerprints
    }

    private struct File: Decodable {
        let version: Int
        let updated: String
        let fingerprints: [String]
    }

    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        self.init(
            version: file.version, updated: file.updated,
            fingerprints: Set(file.fingerprints.map { $0.lowercased() }))
    }

    public static func bundled() -> DenyList {
        guard let url = Bundle.module.url(forResource: "denylist", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let list = try? DenyList(data: data)
        else {
            Diagnostics.sync.error("safety: the bundled deny list did not load; treating it as empty")
            return .empty
        }
        return list
    }

    public static func fingerprint(of participant: ParticipantID) -> String {
        SHA256.hash(data: participant.rawValue).map { String(format: "%02x", $0) }.joined()
    }

    public func contains(_ participant: ParticipantID) -> Bool {
        fingerprints.contains(Self.fingerprint(of: participant))
    }
}
