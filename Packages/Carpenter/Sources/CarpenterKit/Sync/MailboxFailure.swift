import Foundation

public enum MailboxFailure: Error, Hashable, Sendable {
    case noRoomInICloud
    case notSignedIn
}
