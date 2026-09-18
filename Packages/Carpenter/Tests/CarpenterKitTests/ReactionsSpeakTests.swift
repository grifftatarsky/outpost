import CarpenterKit
import Foundation
import SwiftUI
import Testing

@testable import CarpenterUI

func resolved(_ text: Text) -> String? {
    let description = String(describing: text)
    guard let open = description.range(of: ": \""),
        let close = description.range(of: "\"), modifiers", options: .backwards),
        open.upperBound <= close.lowerBound
    else { return nil }
    return String(description[open.upperBound..<close.lowerBound])
}

@MainActor
@Suite("Reactions are spoken as one sentence, on a message and on a post")
struct ReactionsSpeakTests {
    private let me = ParticipantID(rawValue: Data(repeating: 1, count: 32))
    private let other = ParticipantID(rawValue: Data(repeating: 2, count: 32))
    private let third = ParticipantID(rawValue: Data(repeating: 3, count: 32))

    @Test("The sentence names each reaction, and yours first, whatever order they arrive in")
    func theSentence() throws {
        let arrived = ReactionSpeech.summary([
            (emoji: "🔥", count: 2, isMine: false), (emoji: "👍", count: 3, isMine: true),
        ])
        #expect(
            try #require(resolved(arrived), "SwiftUI no longer describes a Text this way")
                == "Reactions: 👍 from you and 2 others, 🔥 from 2 people")
    }

    @Test("Who reacted is said: you alone, you and others, or only others")
    func whoIsSaid() {
        #expect(resolved(ReactionSpeech.summary([(emoji: "👍", count: 1, isMine: true)])) == "Reactions: 👍 from you")
        #expect(
            resolved(ReactionSpeech.summary([(emoji: "👍", count: 2, isMine: true)]))
                == "Reactions: 👍 from you and 1 other")
        #expect(
            resolved(ReactionSpeech.summary([(emoji: "👍", count: 1, isMine: false)]))
                == "Reactions: 👍 from 1 person")
    }

    @Test("A post's row is one sentence, not a pill at a time")
    func aPostIsOneSentence() {
        let bar = ReactionBar(
            reactions: ["👍": [me, other], "🔥": [other, third], "🎉": [third], "👀": [other]],
            viewer: me, onReact: { _ in })
        #expect(
            resolved(bar.spoken)
                == "Reactions: 👍 from you and 1 other, 🎉 from 1 person, 👀 from 1 person, 🔥 from 2 people",
            "the row hides reactions past the third; the sentence must not")
    }
}
