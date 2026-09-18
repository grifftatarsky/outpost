import CarpenterKit
import SwiftUI

#if DEBUG
    struct RoomsListPreview: View {
        @State private var organisation = Fixtures.organisation

        var body: some View {
            NavigationStack {
                RoomsListView(
                    rooms: Fixtures.rooms,
                    organisation: $organisation,
                    syncedPeers: Fixtures.syncedPeers,
                    lastSync: Fixtures.now
                )
            }
            .environment(\.clock, Fixtures.PreviewClock())
            .themed(.cobalt)
        }
    }

    #Preview("34 Rooms with pins — dark") {
        RoomsListPreview().preferredColorScheme(.dark)
    }

    #Preview("41 Rooms with pins — light") {
        RoomsListPreview().preferredColorScheme(.light)
    }
#endif

#if DEBUG
    #Preview("Rooms — nothing yet") {
        NavigationStack {
            RoomsListView(
                rooms: [], organisation: .constant(RoomsListOrganisation()), syncedPeers: [],
                lastSync: .distantPast, onJoinWithInvite: {}
            )
        }
        .environment(\.clock, Fixtures.PreviewClock())
        .themed(.default)
    }
#endif
