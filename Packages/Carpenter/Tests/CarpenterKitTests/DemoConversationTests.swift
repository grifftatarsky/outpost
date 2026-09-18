import Foundation
import Testing

@testable import CarpenterUI

@MainActor
@Suite struct DemoConversationTests {
    @Test("The participant cap holds from both directions")
    func capHolds() {
        #expect(DemoConversation.clamped(1) == 2)
        #expect(DemoConversation.clamped(30) == 25)
        #expect(DemoConversation.clamped(8) == 8)
    }

    @Test("Every room size from two to the cap produces a coherent transcript")
    func everySizeRenders() {
        for n in DemoConversation.cap {
            let messages = DemoConversation.messages(participants: n)
            #expect(!messages.isEmpty)

            let authors = Set(messages.map(\.author.id))
            #expect(authors.count <= n, "\(n) participants but \(authors.count) speakers")

            let times = messages.map(\.sentAt)
            #expect(times == times.sorted(), "\(n) participants produced out-of-order timestamps")

            #expect(messages.contains { $0.isMine })
        }
    }

    @Test("The slider is not decorative: more people means more conversation")
    func gatedLinesAppear() {
        let small = DemoConversation.messages(participants: 8).count
        let full = DemoConversation.messages(participants: 25).count
        #expect(full > small)
        for n in 9...25 {
            #expect(
                DemoConversation.messages(participants: n).count
                    > DemoConversation.messages(participants: n - 1).count,
                "participant \(n) added no voice")
        }
    }

    @Test("The room summary agrees with the transcript it advertises")
    func summaryAgrees() {
        for n in [2, 8, 25] {
            let room = DemoConversation.room(participants: n)
            let messages = DemoConversation.messages(participants: n)
            #expect(room.memberCount == n)
            #expect(room.lastMessage == messages.last?.body)
        }
    }
}
