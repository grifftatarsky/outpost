import CarpenterKit
import CarpenterMedia
import SwiftUI

struct PresentedInvite: Identifiable {
    let roomName: String
    let invite: Invite
    var notAskedYet: Bool = false

    var id: ParticipantID { invite.attestation.joiner }
}

extension ConversationID: Identifiable {
    public var id: ConversationID { self }
}

public enum SendDestination: Hashable, Sendable {
    case conversation(ConversationID)
    case ownOutpost
}
