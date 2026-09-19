@testable import CarpenterUI
import Testing

@Suite("Return on a field whose Return is Done")
struct TypedReturnTests {
    @Test("Return at the end is taken back out and ends the editing")
    func atTheEnd() {
        #expect(TypedReturn.removed(from: "a line about me\n", after: "a line about me") == "a line about me")
    }

    @Test("Return in the middle, where the caret was, is taken back out too")
    func inTheMiddle() {
        #expect(TypedReturn.removed(from: "a line\n about me", after: "a line about me") == "a line about me")
    }

    @Test("A paste that carries line breaks is left alone, because it is not somebody pressing Return")
    func aPasteIsNotReturn() {
        #expect(TypedReturn.removed(from: "OUTLINE\nKEY\nBODY", after: "") == nil)
        #expect(TypedReturn.removed(from: "ab\n\n", after: "ab") == nil)
    }

    @Test("Typing a letter or deleting one is not Return")
    func ordinaryTyping() {
        #expect(TypedReturn.removed(from: "abc", after: "ab") == nil)
        #expect(TypedReturn.removed(from: "a", after: "ab") == nil)
        #expect(TypedReturn.removed(from: "a\r\nb", after: "ab") == "ab")
    }
}
