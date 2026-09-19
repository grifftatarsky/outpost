import CarpenterKit
import CarpenterMedia
import SwiftUI

#if DEBUG
    extension RootView {
        public static var demo: some View {
            demo(tab: .rooms)
        }

        static func demo(tab: PhoneTab, supporter: SupporterSettings? = nil, opening room: RoomID? = nil)
            -> some View
        {
            DemoHost(tab: tab, supporter: supporter, opened: room)
        }

        struct DemoHost: View {
            let tab: PhoneTab
            let supporter: SupporterSettings?
            @State var openRoom: RoomID?

            init(tab: PhoneTab, supporter: SupporterSettings?, opened: RoomID?) {
                self.tab = tab
                self.supporter = supporter
                _openRoom = State(initialValue: opened)
            }

            var body: some View {
                RootView.fixture(tab: tab, supporter: supporter, openRoom: $openRoom)
            }
        }

        static func fixture(tab: PhoneTab, supporter: SupporterSettings?, openRoom: Binding<RoomID?>)
            -> some View
        {
            fixtureRoot(supporter: supporter, openRoom: openRoom)
                .startingOn(tab)
                .environment(\.clock, Fixtures.PreviewClock())
        }

        static func fixtureRoot(supporter: SupporterSettings? = nil, openRoom: Binding<RoomID?>) -> RootView {
            RootView(
                rooms: Fixtures.rooms,
                syncedPeers: Fixtures.syncedPeers,
                lastSync: Fixtures.now,
                owner: Fixtures.cassilda,
                posts: Fixtures.posts,
                audiencePeople: Fixtures.audiencePeople,
                outpostAudience: Fixtures.outpostAudience,
                conversation: Fixtures.conversation,
                openRoom: openRoom,
                organisation: Fixtures.organisation,
                feed: Fixtures.feed,
                outpostAuthors: Fixtures.outpostAuthors,
                recoveryKey: Fixtures.savedRecoveryKey,
                connections: Fixtures.connections,
                devices: Fixtures.devices,
                viewer: Fixtures.cassilda.id,
                supporter: supporter,
                outpostSettings: Fixtures.outpostSettings
            )
        }
    }

    #Preview("00 Shell — dark") {
        RootView.demo
            .preferredColorScheme(.dark)
    }

    #Preview("00 Shell — light") {
        RootView.demo
            .preferredColorScheme(.light)
    }
#endif
