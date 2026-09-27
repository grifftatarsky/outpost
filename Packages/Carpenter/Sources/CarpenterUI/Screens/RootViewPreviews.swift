import CarpenterKit
import CarpenterMedia
import SwiftUI

#if DEBUG
    extension RootView {
        public static var demo: some View {
            demo(tab: .rooms)
        }

        static func demo(
            tab: PhoneTab, supporter: SupporterSettings? = nil, awaiting: [AwaitingAdmission] = []
        ) -> some View {
            Demo(tab: tab, supporter: supporter, awaiting: awaiting)
        }

        private struct Demo: View {
            let tab: PhoneTab
            let supporter: SupporterSettings?
            let awaiting: [AwaitingAdmission]
            @State private var organisation = Fixtures.organisation
            @State private var preferences = RoomsListPreferences()

            var body: some View {
                RootView(
                    rooms: Fixtures.rooms,
                    syncedPeers: Fixtures.syncedPeers,
                    lastSync: Fixtures.now,
                    owner: Fixtures.cassilda,
                    posts: Fixtures.posts,
                    audiencePeople: Fixtures.audiencePeople,
                    conversation: Fixtures.conversation,
                    organisation: $organisation,
                    preferences: preferences,
                    feed: Fixtures.feed,
                    outpostAuthors: Fixtures.outpostAuthors,
                    recoveryKey: Fixtures.savedRecoveryKey,
                    connections: Fixtures.connections,
                    devices: Fixtures.devices,
                    awaitingAdmission: awaiting,
                    viewer: Fixtures.cassilda.id,
                    supporter: supporter,
                    outpostSettings: Fixtures.outpostSettings
                )
                .startingOn(tab)
                .environment(\.clock, Fixtures.PreviewClock())
            }
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
