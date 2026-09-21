@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
func join(
    _ joiner: AppSession, into room: ConversationID, of host: AppSession,
    through mailbox: InMemoryMailbox, media: (any MediaMailbox)? = nil, rounds: Int = 5
) async throws {
    let invite = try await host.invite(
        joinerCode: joiner.identityCode(), joining: room, mailbox: nil)
    try await joiner.redeem(inviteCode: try invite.encoded())
    for _ in 0..<rounds {
        try await host.sync(through: mailbox, media: media)
        try await joiner.sync(through: mailbox, media: media)
    }
}
