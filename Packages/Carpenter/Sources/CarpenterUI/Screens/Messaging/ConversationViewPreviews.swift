import CarpenterKit
import CarpenterMedia
import PhotosUI
import SwiftUI

#if DEBUG
    #Preview("03 Conversation — dark") {
        NavigationStack {
            ConversationView(
                room: Fixtures.zeppelinEnthusiasts,
                messages: Fixtures.conversation,
            )
        }
        .environment(\.clock, Fixtures.PreviewClock())
        .themed(.cobalt)
        .preferredColorScheme(.dark)
    }

    #Preview("14 Conversation — light") {
        NavigationStack {
            ConversationView(
                room: Fixtures.zeppelinEnthusiasts,
                messages: Fixtures.conversation,
            )
        }
        .environment(\.clock, Fixtures.PreviewClock())
        .themed(.verdigris)
        .preferredColorScheme(.light)
    }
#endif
