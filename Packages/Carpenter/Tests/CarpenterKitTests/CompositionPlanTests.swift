@testable import CarpenterUI
import CarpenterKit
import Foundation
import Testing

@Suite("Composing words with pictures")
struct CompositionPlanTests {
    @Test("Words alone are a message")
    func wordsAlone() {
        #expect(CompositionPlan.steps(text: "  hello ", itemCount: 0) == [.text("hello")])
        #expect(CompositionPlan.steps(text: "   ", itemCount: 0).isEmpty)
    }

    @Test("One picture takes the words as its caption")
    func onePictureIsCaptioned() {
        #expect(CompositionPlan.steps(text: "look", itemCount: 1) == [.media(index: 0, caption: "look")])
        #expect(CompositionPlan.steps(text: "", itemCount: 1) == [.media(index: 0, caption: nil)])
    }

    @Test("Several pictures go first, and the words follow as their own message")
    func severalPicturesThenWords() {
        #expect(
            CompositionPlan.steps(text: "the trip", itemCount: 3) == [
                .media(index: 0, caption: nil), .media(index: 1, caption: nil),
                .media(index: 2, caption: nil), .text("the trip"),
            ])
        #expect(
            CompositionPlan.steps(text: "", itemCount: 2) == [
                .media(index: 0, caption: nil), .media(index: 1, caption: nil),
            ])
    }
}
