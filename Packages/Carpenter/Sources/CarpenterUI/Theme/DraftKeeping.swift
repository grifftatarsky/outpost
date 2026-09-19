import CarpenterKit
import SwiftUI

public struct DraftKeeping: Sendable {
    public let read: @MainActor @Sendable (RoomID) -> String
    public let keep: @MainActor @Sendable (String, RoomID) -> Void

    public init(
        read: @escaping @MainActor @Sendable (RoomID) -> String,
        keep: @escaping @MainActor @Sendable (String, RoomID) -> Void
    ) {
        self.read = read
        self.keep = keep
    }
}

extension EnvironmentValues {
    @Entry public var drafts: DraftKeeping? = nil
}
