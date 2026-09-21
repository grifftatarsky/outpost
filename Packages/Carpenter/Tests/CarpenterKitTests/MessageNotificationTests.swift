import CarpenterKit
import Foundation
import Testing

@Suite("Message notification copy")
struct MessageNotificationTests {
    private let room = ConversationID.room(UUID())

    @Test("A full message names the room, the author and the text")
    func fullMessage() {
        let copy = MessageNotification.of(room: room, roomName: "Kitchen", author: "Alice", body: "on my way")
        #expect(copy.title == "Kitchen")
        #expect(copy.subtitle == "Alice")
        #expect(copy.body == "on my way")
        #expect(
            copy.threadID == MessageNotification.thread(for: room),
            "without a thread the banner cannot group, and the foreground delegate cannot tell which conversation it is about")
    }

    @Test("A nameless room falls back to the author as the title")
    func namelessRoom() {
        let copy = MessageNotification.of(room: room, roomName: "  ", author: "Alice", body: "hi")
        #expect(copy.title == "Alice")
        #expect(copy.subtitle.isEmpty)
        #expect(copy.body == "hi")
    }

    @Test("Missing text or author collapses to the generic banner")
    func collapsesToGeneric() {
        #expect(
            MessageNotification.of(room: room, roomName: "Kitchen", author: "Alice", body: "   ")
                == MessageNotification.generic)
        #expect(
            MessageNotification.of(room: room, roomName: "Kitchen", author: "", body: "hi")
                == MessageNotification.generic)
        #expect(MessageNotification.generic.body.isEmpty)
        #expect(MessageNotification.generic.threadID.isEmpty)
    }

    @Test("Each room gets its own thread, stably")
    func threadsArePerRoom() {
        let other = ConversationID.room(UUID())
        #expect(MessageNotification.thread(for: room) != MessageNotification.thread(for: other))
        #expect(MessageNotification.thread(for: room) == MessageNotification.thread(for: room))
        #expect(!MessageNotification.thread(for: room).isEmpty)
    }
}
