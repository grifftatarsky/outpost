import CarpenterKit
import SwiftUI

struct StartingConversations: ViewModifier {
    @Environment(\.verificationPhrase) private var phraseLookup

    @Binding var namingRoom: Bool
    @Binding var pickingSolo: Bool
    @Binding var soloInvite: PresentedInvite?
    let preferences: RoomsListPreferences
    let connections: [Connection]
    let onCreateRoom: (String, RoomAccess, Set<ParticipantID>) async -> Void
    let onStartSolo: (ParticipantID) async -> Invite?

    func body(content: Content) -> some View {
        content
            .sizedSheet(isPresented: $namingRoom) {
                NewRoomView(preferences: preferences, connections: connections) { name, access, people in
                    await onCreateRoom(name, access, people)
                }
            }
            .sizedSheet(isPresented: $pickingSolo) {
                SoloPickerView(connections: connections) { person in
                    if let invite = await onStartSolo(person.id) {
                        soloInvite = PresentedInvite(
                            roomName: person.displayName, invite: invite, notAskedYet: true)
                    }
                }
            }
            .sizedSheet(item: $soloInvite) { presented in
                InviteView(
                    roomName: presented.roomName, invite: presented.invite,
                    phrase: phraseLookup(presented.invite),
                    notAskedYet: presented.notAskedYet)
            }
    }
}
