import CarpenterApp
import CarpenterCloudKit
import CarpenterKeychain
import CloudKit
import CarpenterKit
import CarpenterMedia
import CarpenterUI
import OSLog
import Intents
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

// MARK: Reacting to what was said

extension AppRootView {
    func react(to message: MessageID, in room: RoomID, with emoji: String?) async {
        _ = await reporting("react to message") {
            try await session.react(to: message, in: room, with: emoji)
        }
    }
}
