import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp

@MainActor
@Suite("Being on the bundled list yourself")
struct BannedFromTheAppTests {
    private static func listing(_ who: ParticipantID) -> DenyList {
        DenyList(version: 1, updated: "today", fingerprints: [DenyList.fingerprint(of: who)])
    }

    @Test("locks the app on the next launch")
    func locksOnLaunch() async throws {
        let keychain = InMemoryKeychainStore()
        let directory = URL.temporaryDirectory.appending(path: "banned-\(UUID().uuidString)")

        let first = TestSession.make(keychain: keychain, at: directory)
        await first.load()
        try await first.createIdentity(displayName: "Mallory")
        let me = try #require(first.enrolment?.identity.id)
        #expect(!first.isBanned)

        let next = TestSession.make(keychain: keychain, at: directory, denyList: Self.listing(me))
        await next.load()

        #expect(next.isBanned)
        #expect(RootScreen.for(next.state, bannedSelf: next.isBanned) == .banned)
    }

    @Test("locks the app when the identity comes back from a recovery key")
    func locksOnRestore() async throws {
        let first = TestSession.make()
        await first.load()
        try await first.createIdentity(displayName: "Mallory")
        let me = try #require(first.enrolment?.identity.id)
        let key = try #require(first.recoveryKeyText())

        let restored = TestSession.make(denyList: Self.listing(me))
        await restored.load()
        try await restored.restore(fromRecoveryKey: key)

        #expect(restored.enrolment?.identity.id == me)
        #expect(restored.isBanned)
        #expect(RootScreen.for(restored.state, bannedSelf: restored.isBanned) == .banned)
    }

    @Test("holds whether or not the member turned the list off")
    func ignoresTheSwitch() async throws {
        let keychain = InMemoryKeychainStore()
        let directory = URL.temporaryDirectory.appending(path: "banned-\(UUID().uuidString)")

        let first = TestSession.make(keychain: keychain, at: directory)
        await first.load()
        try await first.createIdentity(displayName: "Mallory")
        let me = try #require(first.enrolment?.identity.id)

        let next = TestSession.make(keychain: keychain, at: directory, denyList: Self.listing(me))
        await next.load()
        next.enforcesDenyList = false

        #expect(!next.isDenyListed(me))
        #expect(next.isBanned)
    }

    @Test("stops every round, so nothing more is sent or collected")
    func stopsSyncing() async throws {
        let mailbox = InMemoryMailbox()
        let keychain = InMemoryKeychainStore()
        let directory = URL.temporaryDirectory.appending(path: "banned-\(UUID().uuidString)")

        let alice = TestSession.make(keychain: keychain, at: directory)
        await alice.load()
        try await alice.createIdentity(displayName: "Mallory")
        let me = try #require(alice.enrolment?.identity.id)

        let bob = TestSession.make()
        await bob.load()
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Somewhere")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox, media: mailbox)
            try await bob.sync(through: mailbox, media: mailbox)
        }
        try await alice.send("before", to: room)
        try await alice.sync(through: mailbox, media: mailbox)
        let wrote = await mailbox.serverWrites
        #expect(wrote > 0, "the round before the ban has to have written, or this proves nothing")

        let banned = TestSession.make(keychain: keychain, at: directory, denyList: Self.listing(me))
        await banned.load()
        #expect(banned.isBanned)
        try await banned.send("after", to: room)
        try await banned.sync(through: mailbox, media: mailbox)

        #expect(await mailbox.serverWrites == wrote)
    }

    @Test("leaves everybody else alone")
    func doesNotLockSomebodyElse() async throws {
        let stranger = ParticipantID(rawValue: Data("somebody else".utf8))
        let session = TestSession.make(denyList: Self.listing(stranger))
        await session.load()
        try await session.createIdentity(displayName: "Alice")

        #expect(!session.isBanned)
        #expect(RootScreen.for(session.state, bannedSelf: session.isBanned) == .ready)
    }
}
