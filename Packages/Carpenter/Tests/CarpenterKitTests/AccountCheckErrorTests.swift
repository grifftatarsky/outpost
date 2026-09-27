import CarpenterKit
import CarpenterKitTesting
import CloudKit
import Foundation
import Testing

@testable import CarpenterApp
@testable import CarpenterCloudKit

@Suite("Reading a failed account check")
struct AccountCheckErrorTests {
    private func ckError(_ code: CKError.Code, userInfo: [String: Any] = [:]) -> CKError {
        CKError(code, userInfo: userInfo)
    }

    @Test("A missing zone arrives wrapped in a partial failure, and still reads as empty")
    func partialFailureWrappingZoneNotFound() {
        let zone = CKRecordZone.ID(zoneName: "SiblingFeeds", ownerName: CKCurrentUserDefaultName)
        let wrapped = ckError(
            .partialFailure,
            userInfo: [CKPartialErrorsByItemIDKey: [zone: ckError(.zoneNotFound)]])

        #expect(CloudKitEntrySync.occupancy(for: wrapped) == .empty)
    }

    @Test("A bare missing zone reads as empty")
    func bareZoneNotFound() {
        #expect(CloudKitEntrySync.occupancy(for: ckError(.zoneNotFound)) == .empty)
        #expect(CloudKitEntrySync.occupancy(for: ckError(.userDeletedZone)) == .empty)
    }

    @Test("Never reaching iCloud reads as offline, so a first run still works")
    func networkFailuresReadAsOffline() {
        for code in [CKError.Code.networkUnavailable, .networkFailure, .notAuthenticated] {
            #expect(CloudKitEntrySync.occupancy(for: ckError(code)) == .offline, "\(code)")
        }
    }

    @Test("Being refused an answer is never read as an empty account")
    func transientFailuresAreUndetermined() {
        let transient: [CKError.Code] = [
            .serviceUnavailable, .requestRateLimited, .zoneBusy, .internalError, .serverResponseLost,
        ]
        for code in transient {
            #expect(CloudKitEntrySync.occupancy(for: ckError(code)) == .undetermined, "\(code)")
            #expect(CloudKitEntrySync.occupancy(for: ckError(code)) != .empty, "\(code)")
        }
    }

    @Test("An internal failure with no word of the account's security says nothing about a member")
    func internalFailureIsUndetermined() {
        #expect(CloudKitEntrySync.occupancy(for: ckError(.internalError)) == .undetermined)
    }

    @Test("iCloud not yet trusting this device reads as held, never as empty")
    func aSecurityHoldIsHeld() {
        let refused = NSError(
            domain: "com.apple.ProtectedCloudStorage", code: 7,
            userInfo: [NSLocalizedDescriptionKey: "PCSNoPublicIdentity"])
        let wrapped = ckError(.internalError, userInfo: [NSUnderlyingErrorKey: refused])
        let zone = CKRecordZone.ID(zoneName: "SiblingFeeds", ownerName: CKCurrentUserDefaultName)
        let partial = ckError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [zone: wrapped]])
        for error in [ckError(.accountTemporarilyUnavailable), wrapped, partial] as [any Error] {
            #expect(CloudKitHold.isSecurityHold(error))
            #expect(CloudKitEntrySync.occupancy(for: error) == .held)
        }
        #expect(!CloudKitHold.isSecurityHold(ckError(.networkFailure)))
        #expect(!CloudKitHold.isSecurityHold(ckError(.serverRecordChanged)))
        #expect(!CloudKitHold.isSecurityHold(NSError(domain: NSURLErrorDomain, code: -1009)))
    }

    @Test("An unrecognised failure holds rather than offering")
    func unknownFailuresHold() {
        struct Strange: Error {}
        #expect(CloudKitEntrySync.occupancy(for: Strange()) == .undetermined)
        #expect(CloudKitEntrySync.occupancy(for: ckError(.badContainer)) == .undetermined)
    }

    @Test("A partial failure that is not about a missing zone does not read as empty")
    func partialFailureWithoutZoneNotFound() {
        let zone = CKRecordZone.ID(zoneName: "SiblingFeeds", ownerName: CKCurrentUserDefaultName)
        let wrapped = ckError(
            .partialFailure,
            userInfo: [CKPartialErrorsByItemIDKey: [zone: ckError(.requestRateLimited)]])

        #expect(CloudKitEntrySync.occupancy(for: wrapped) == .undetermined)
    }
}

@Suite("While iCloud holds this device", .serialized)
@MainActor
struct WhileICloudHoldsThisDeviceTests {
    @Test("Nothing is sent or fetched, what is here stays readable, and it resumes when iCloud lets it in")
    func nothingMovesWhileHeld() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        for member in [alice, bob] { await member.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Kitchen")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        for _ in 0..<6 {
            for member in [alice, bob] { try await member.sync(through: mailbox) }
        }

        alice.noteICloudHold(true)
        try await alice.send("written during the hold", to: room)
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        #expect(!bob.messages(in: room).map(\.body).contains("written during the hold"), "a held device sent a message")
        #expect(alice.messages(in: room).map(\.body).contains("written during the hold"))

        alice.noteICloudHold(false)
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        #expect(
            bob.messages(in: room).map(\.body).contains("written during the hold"),
            "the device did not resume once iCloud let it in")
    }
}
