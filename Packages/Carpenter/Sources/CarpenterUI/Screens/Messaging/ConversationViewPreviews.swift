import CarpenterKit
import CarpenterMedia
import PhotosUI
import SwiftUI

#if DEBUG
    #Preview("03 Conversation — dark") {
        NavigationStack {
            ConversationView(
                room: Fixtures.zeppelinEnthusiasts,
                transcript: Fixtures.conversation.map(TranscriptEntry.message),
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
                transcript: Fixtures.conversation.map(TranscriptEntry.message),
            )
        }
        .environment(\.clock, Fixtures.PreviewClock())
        .themed(.verdigris)
        .preferredColorScheme(.light)
    }
#endif
