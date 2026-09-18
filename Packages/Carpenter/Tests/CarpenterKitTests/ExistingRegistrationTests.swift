import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp

@Suite("Checking for an existing registration", .serialized)
@MainActor
struct ExistingRegistrationTests {
    private func session(
        _ keychain: InMemoryKeychainStore = InMemoryKeychainStore(),
        registry: StubAccountRegistry
    ) -> AppSession {
        let session = TestSession.make(keychain: keychain)
        session.checkAccount(with: registry)
        return session
    }

    @Test("A device with no identity checks before it offers anything")
    func checkingComesFirstAndBlocks() async {
        let app = session(registry: StubAccountRegistry(hasMember: false))
        await app.load()

        #expect(app.state == .checkingForRegistration, "the welcome screen was reachable unchecked")
    }

    @Test("An empty account then offers to make a member")
    func emptyAccountOffersOnboarding() async {
        let app = session(registry: StubAccountRegistry(hasMember: false))
        await app.load()
        await app.settleRegistration(attempts: 2)

        #expect(app.state == .needsIdentity)
    }

    @Test("An account that already has a member never offers a fresh start")
    func occupiedAccountWaitsInstead() async {
        let app = session(registry: StubAccountRegistry(hasMember: true))
        await app.load()
        await app.settleRegistration(attempts: 2)

        #expect(app.state != .needsIdentity, "offered a new member to an occupied account")
        #expect(
            app.state == .registrationStalled(.accountHasAMember),
            "the wait ended by holding, so the spinner kept claiming to be checking")
    }

    @Test("The key arriving while waiting moves the device on by itself")
    func theKeyArrivingEndsTheWait() async throws {
        let keychain = InMemoryKeychainStore()
        let app = session(keychain, registry: StubAccountRegistry(hasMember: true))
        await app.load()
        await app.settleRegistration(attempts: 2)
        #expect(app.state == .registrationStalled(.accountHasAMember))

        _ = try await IdentityStore(keychain: keychain).enrol()

        #expect(await app.recheckForSyncedIdentity())
        #expect(app.state == .needsProfile || app.state == .ready)
    }

    @Test("A device that already has an identity does not wait on the network")
    func enrolledDeviceSkipsTheCheck() async throws {
        let keychain = InMemoryKeychainStore()
        let first = TestSession.make(keychain: keychain)
        await first.load()
        try await first.createIdentity(displayName: "Griff")

        let registry = StubAccountRegistry(hasMember: true)
        let second = session(keychain, registry: registry)
        await second.load()

        #expect(second.state == .needsProfile || second.state == .ready)
        #expect(registry.asked == 0, "asked the network about an account it was already a member of")
    }

    @Test("An account that cannot be reached waits rather than offering a member")
    func unreachableAccountWaits() async {
        let registry = StubAccountRegistry(.offline, .empty)
        let app = session(registry: registry)
        await app.load()
        await app.settleRegistration(attempts: 2)

        #expect(
            app.state == .registrationStalled(.accountOffline),
            "offered a member without knowing whether the account already has one")

        await app.retryRegistration()
        #expect(app.state == .needsIdentity, "once iCloud answered, the fresh start never came")
    }

    @Test("A session that was never given a way to ask the account does not offer a member")
    func noRegistryWaits() async {
        let app = AppSession(storage: TestSession.storage(), clock: TestClock(now: TestSession.now))
        await app.load()
        await app.settleRegistration(attempts: 1)

        #expect(app.state == .registrationStalled(.accountOffline))
    }

    @Test("An account that will not answer holds rather than offering a member")
    func undeterminedAccountHoldsInsteadOfOffering() async {
        let app = session(registry: StubAccountRegistry(.undetermined))
        await app.load()
        await app.settleRegistration(attempts: 2)

        #expect(app.state != .needsIdentity, "offered a member on an answer that was not an answer")
        #expect(app.state == .registrationStalled(.accountUnreadable))
    }

    @Test("An account that answers on the second ask is believed")
    func undeterminedThenEmptyProceeds() async {
        let registry = StubAccountRegistry(.undetermined, .empty)
        let app = session(registry: registry)
        await app.load()
        await app.settleRegistration(attempts: 4)

        #expect(app.state == .needsIdentity)
        #expect(registry.asked > 1, "never asked again after an answer that said to ask again")
    }

    @Test("An account that turns out to be occupied stops offering")
    func undeterminedThenOccupiedWaits() async {
        let app = session(registry: StubAccountRegistry(.undetermined, .occupied))
        await app.load()
        await app.settleRegistration(attempts: 4)

        #expect(app.state == .registrationStalled(.accountHasAMember))
    }

    @Test("The wait ends by saying what it ended on, never by spinning")
    func theWaitEndsWithAnAnswer() async {
        let app = session(registry: StubAccountRegistry(hasMember: true))
        await app.load()
        await app.settleRegistration(attempts: 2)

        #expect(app.state != .checkingForRegistration, "still claiming to be checking")
        guard case .registrationStalled(let why) = app.state else {
            Issue.record("the wait ended somewhere that says nothing: \(app.state)")
            return
        }
        #expect(why == .accountHasAMember)
    }

    @Test("Asking again from a stalled screen re-runs the whole check")
    func retryFromAStallAsksAgain() async throws {
        let registry = StubAccountRegistry(.occupied, .empty)
        let app = session(registry: registry)
        await app.load()
        await app.settleRegistration(attempts: 2)
        try #require(app.state == .registrationStalled(.accountHasAMember))

        await app.retryRegistration()

        #expect(app.state == .needsIdentity, "asking again did not ask anything")
        #expect(registry.asked > 1, "the retry reused the answer it was stuck on")
    }

    @Test("A key arriving after the wait has ended still moves the device on")
    func aLateKeyStillRescuesAStalledDevice() async throws {
        let keychain = InMemoryKeychainStore()
        let app = session(keychain, registry: StubAccountRegistry(hasMember: true))
        await app.load()
        await app.settleRegistration(attempts: 2)
        try #require(app.state == .registrationStalled(.accountHasAMember))
        #expect(app.isWaitingForAnIdentity, "the ladder would have stopped looking")

        _ = try await IdentityStore(keychain: keychain).enrol()

        #expect(await app.recheckForSyncedIdentity())
        #expect(app.state == .needsProfile || app.state == .ready)
    }

    @Test("A definite answer is asked for once, not once per attempt")
    func definiteAnswerIsNotRefetched() async {
        let registry = StubAccountRegistry(.occupied)
        let app = session(registry: registry)
        await app.load()
        await app.settleRegistration(attempts: 5)

        #expect(registry.asked == 1, "asked \(registry.asked) times for an answer that was definite")
    }
}

final class StubAccountRegistry: AccountRegistry, @unchecked Sendable {
    private let answers: [AccountOccupancy]
    private(set) var asked = 0

    init(hasMember: Bool = false, failing: Bool = false) {
        self.answers = [failing ? .offline : (hasMember ? .occupied : .empty)]
    }

    init(_ answers: AccountOccupancy...) {
        self.answers = answers.isEmpty ? [.empty] : answers
    }

    func occupancy() async -> AccountOccupancy {
        defer { asked += 1 }
        return answers[min(asked, answers.count - 1)]
    }
}

@MainActor
@Suite("Handing over a room after a relaunch", .serialized)
struct EpochLinkRestoreTests {
    @Test("A joiner can read a room whose host has relaunched since making it")
    func aRelaunchedHostStillHandsOverHistory() async throws {
        let mailbox = InMemoryMailbox()
        let directory = URL.temporaryDirectory.appending(path: "carpenter-links-\(UUID().uuidString)")
        let keychain = InMemoryKeychainStore()

        let host = TestSession.make(keychain: keychain, at: directory)
        await host.load()
        try await host.createIdentity(displayName: "Alice")
        let room = try await host.createRoom(named: "Hangar 7")

        let joiner = TestSession.make()
        await joiner.load()
        try await joiner.createIdentity(displayName: "Bob")

        let invite = try await host.invite(
            joinerCode: joiner.identityCode(), joining: room, mailbox: nil)
        try await joiner.redeem(inviteCode: try invite.encoded())

        let relaunched = TestSession.make(keychain: keychain, at: directory)
        await relaunched.load()
        try await relaunched.sync(through: mailbox)

        try await joiner.accept(
            invite.attestation, from: try #require(relaunched.enrolment?.identity.publicKeys))
        for _ in 0..<4 {
            try await relaunched.sync(through: mailbox)
            try await joiner.sync(through: mailbox)
        }

        #expect(
            joiner.rooms.contains { $0.name == "Hangar 7" },
            "the joiner was handed the room's key and still cannot see the room")
    }
}
