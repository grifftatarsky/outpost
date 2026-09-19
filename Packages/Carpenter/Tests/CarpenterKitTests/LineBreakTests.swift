import SwiftUI
import Testing

@testable import CarpenterUI

@Suite("Shift-Return writes a line where the cursor is")
struct LineBreakTests {
    @Test func withNoSelectionTheLineGoesAtTheEnd() {
        let (text, selection) = LineBreak.inserted(into: "hello", at: nil)
        #expect(text == "hello\n")
        #expect(selection == TextSelection(insertionPoint: text.endIndex))
    }

    @Test func atACaretTheLineGoesThereAndTheCaretFollowsIt() {
        let draft = "hello there"
        let caret = draft.index(draft.startIndex, offsetBy: 5)
        let (text, selection) = LineBreak.inserted(into: draft, at: TextSelection(insertionPoint: caret))
        #expect(text == "hello\n there")
        #expect(selection == TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: 6)))
    }

    @Test func aSelectionIsReplacedByTheLine() {
        let draft = "one two three"
        let start = draft.index(draft.startIndex, offsetBy: 3)
        let end = draft.index(draft.startIndex, offsetBy: 8)
        let (text, _) = LineBreak.inserted(into: draft, at: TextSelection(range: start..<end))
        #expect(text == "one\nthree")
    }

    @Test func aSelectionFromALongerDraftCannotReachPastTheEnd() {
        let longer = "a much longer draft"
        let stale = TextSelection(insertionPoint: longer.endIndex)
        let (text, _) = LineBreak.inserted(into: "short", at: stale)
        #expect(text == "short\n")
    }

    @Test func emojiAreNotSplit() {
        let draft = "🛩️🎈"
        let caret = draft.index(after: draft.startIndex)
        let (text, _) = LineBreak.inserted(into: draft, at: TextSelection(insertionPoint: caret))
        #expect(text == "🛩️\n🎈")
    }
}
