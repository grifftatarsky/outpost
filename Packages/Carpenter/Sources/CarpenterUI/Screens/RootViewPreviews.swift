import CarpenterKit
import CarpenterMedia
import SwiftUI

#if DEBUG
    extension RootView {
        public static var demo: some View {
            demo(tab: .rooms)
        }

        static func demo(tab: PhoneTab, supporter: SupporterSettings? = nil) -> some View {
            RootView(
                rooms: Fixtures.rooms,
                syncedPeers: Fixtures.syncedPeers,
                lastSync: Fixtures.now,
                owner: Fixtures.cassilda,
                posts: Fixtures.posts,
                audiencePeople: Fixtures.audiencePeople,
                conversation: Fixtures.conversation,
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
            .startingOn(tab)
            .environment(\.clock, Fixtures.PreviewClock())
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
