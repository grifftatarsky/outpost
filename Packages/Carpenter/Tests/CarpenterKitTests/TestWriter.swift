@testable import CarpenterKit
import Foundation

func testWriter(in conversation: ConversationID) -> FeedKey {
    FeedKey(
        author: ParticipantID(rawValue: Data(repeating: 0xA1, count: 32)),
        device: DeviceID(rawValue: Data(repeating: 0xD1, count: 32)),
        conversation: conversation)
}
