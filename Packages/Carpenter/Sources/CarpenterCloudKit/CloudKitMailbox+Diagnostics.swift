import CloudKit
import CarpenterKit
import Foundation

// MARK: The round trip a member can run from Settings

extension CloudKitMailbox {
    public func roundTrip() async -> String {
        var steps: [String] = []

        func attempt(_ name: String, _ work: () async throws -> String) async -> Bool {
            do {
                steps.append("\(name): \(try await work())")
                return true
            } catch {
                steps.append("\(name): FAILED — \(error)")
                return false
            }
        }

        let tag = RecipientTag(rawValue: Data((0..<16).map { _ in UInt8.random(in: 0...255) }))
        let packet = SyncPacket(
            wraps: [tag: Data("wrap".utf8)], ciphertext: Data("sealed".utf8))

        guard await attempt("zone", { try await prepare(); return "ready" }) else {
            return steps.joined(separator: "\n")
        }
        guard await attempt("put", { try await put(packet); return "wrote one packet" }) else {
            return steps.joined(separator: "\n")
        }

        let found = await attempt("fetch") {
            let all = try await fetch(for: tag)
            guard all.contains(where: { $0.id == packet.id }) else {
                return "did NOT find it — \(all.count) other packet(s) for this tag"
            }
            return "found it"
        }

        _ = await attempt("acknowledge") {
            try await acknowledge(packet.id, by: tag)
            return "removed"
        }

        _ = await attempt("fetch again") {
            let all = try await fetch(for: tag)
            return all.contains { $0.id == packet.id } ? "still there — not deleted" : "gone"
        }

        steps.append(found ? "\nThe mailbox works for one member." : "\nThe mailbox does not work.")
        return steps.joined(separator: "\n")
    }
}
