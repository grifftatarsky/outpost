import CarpenterKit
import CloudKit
import Foundation
import Testing

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
            .accountTemporarilyUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy,
            .internalError, .serverResponseLost,
        ]
        for code in transient {
            #expect(CloudKitEntrySync.occupancy(for: ckError(code)) == .undetermined, "\(code)")
            #expect(CloudKitEntrySync.occupancy(for: ckError(code)) != .empty, "\(code)")
        }
    }

    @Test("A PCS failure says nothing about whether a member exists")
    func pcsFailureIsUndetermined() {
        #expect(CloudKitEntrySync.occupancy(for: ckError(.internalError)) == .undetermined)
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
