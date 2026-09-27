import Foundation
import Testing

@testable import CarpenterApp

@Suite("Writes that cannot land are counted")
@MainActor
struct WritesThatCannotLandTests {
    @Test("A join nonce that cannot be written down is reported, not swallowed")
    func aLostNonceWriteIsCounted() async throws {
        let root = TestScratch.root.appending(path: "carpenter-test-\(UUID().uuidString)")
        let alice = TestSession.make(at: root)
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")

        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path) }
        let before = alice.integrity.writesFailed

        _ = alice.identityCode()

        let deadline = Date().addingTimeInterval(2)
        while alice.integrity.writesFailed == before, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(
            alice.integrity.writesFailed > before,
            """
            The nonce behind a joiner's code went unwritten and nothing noticed. Without it the \
            phrase cannot be computed after a relaunch, so the join fails later with no trace.
            """)
    }
}
