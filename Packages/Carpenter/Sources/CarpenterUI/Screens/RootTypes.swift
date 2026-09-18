import CarpenterKit
import CarpenterMedia
import SwiftUI

struct PresentedInvite: Identifiable {
    let roomName: String
    let invite: Invite
    var notAskedYet: Bool = false

    var id: ParticipantID { invite.attestation.joiner }
}

extension RoomID: Identifiable {
    public var id: RoomID { self }
}
