import CarpenterKit
import CloudKit
import Foundation
import Testing

@testable import CarpenterCloudKit

@Suite("Reading a mailbox that would not take a packet")
struct MailboxRefusalTests {
    private func ckError(_ code: CKError.Code, userInfo: [String: Any] = [:]) -> CKError {
        CKError(code, userInfo: userInfo)
    }

    @Test("A full iCloud is named as a full iCloud")
    func aFullICloudIsNamed() {
        #expect(CloudKitMailbox.refusal(for: ckError(.quotaExceeded)) == .noRoomInICloud)
    }

    @Test("Being signed out is told apart from being full")
    func signedOutIsToldApart() {
        #expect(CloudKitMailbox.refusal(for: ckError(.notAuthenticated)) == .notSignedIn)
        #expect(
            CloudKitMailbox.refusal(for: ckError(.accountTemporarilyUnavailable)) == .notSignedIn)
    }

    @Test("A quota refusal nested in a partial failure still reads as full")
    func nestedQuotaStillReads() {
        let record = CKRecord.ID(recordName: "packet")
        let wrapped = ckError(
            .partialFailure,
            userInfo: [CKPartialErrorsByItemIDKey: [record: ckError(.quotaExceeded)]])

        #expect(
            CloudKitMailbox.refusal(for: wrapped) == .noRoomInICloud,
            """
            CloudKit reports a write refusal as a partial failure with the real reason nested \
            inside, the same shape that hid the account check for a week.
            """)
    }

    @Test("Everything else is left alone rather than guessed at")
    func everythingElseIsLeftAlone() {
        for code: CKError.Code in [
            .networkUnavailable, .networkFailure, .requestRateLimited, .serviceUnavailable,
            .zoneNotFound, .serverRecordChanged, .unknownItem,
        ] {
            #expect(
                CloudKitMailbox.refusal(for: ckError(code)) == nil,
                """
                \(code) was read as something a member could fix. A rate limit or a dropped \
                connection is the app's problem and it retries; telling somebody their iCloud is \
                full when it is not is worse than saying nothing.
                """)
        }
        #expect(CloudKitMailbox.refusal(for: CryptoError.openFailed) == nil)
    }
}
