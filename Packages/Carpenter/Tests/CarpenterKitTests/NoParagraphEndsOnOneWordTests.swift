import Testing

@testable import CarpenterUI

@Suite("No paragraph ends on one word by itself")
struct NoParagraphEndsOnOneWordTests {
    @Test("The last two words of each paragraph are held together")
    func lastTwoWords() {
        let text = "Only you have your messages.\n\nThe recovery key brings it back."
        #expect(text.keepingLastWordsTogether == "Only you have your\u{00A0}messages.\n\nThe recovery key brings it\u{00A0}back.")
    }

    @Test("A single word is left alone")
    func oneWord() {
        #expect("Start".keepingLastWordsTogether == "Start")
    }
}
