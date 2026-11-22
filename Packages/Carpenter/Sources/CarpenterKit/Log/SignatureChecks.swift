import Foundation

public struct SignatureChecks: Sendable {
    private struct Passed: Hashable, Sendable {
        let entry: EntryHash
        let key: Data
    }

    private var passed: Set<Passed> = []

    public init() {}

    var count: Int { passed.count }

    func vouches(for entry: Entry, signedWith key: Data) -> Bool {
        passed.contains(Passed(entry: entry.hash, key: key))
    }

    static func verifying(_ signed: [(entry: Entry, key: Data)]) async -> SignatureChecks {
        let passed = await signed.inParallel { lane in
            lane.compactMap { entry, key in
                (try? entry.hasValidSignature(from: key)) == true ? Passed(entry: entry.hash, key: key) : nil
            }
        }
        var checks = SignatureChecks()
        checks.passed = Set(passed)
        return checks
    }
}
