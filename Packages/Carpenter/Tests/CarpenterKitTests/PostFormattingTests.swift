import Foundation
import Testing

@testable import CarpenterKit

@Suite("Post formatting")
struct PostFormattingTests {
    private func runs(_ source: String) -> [PostFormatting.Run] {
        PostFormatting.runs(in: source)
    }

    @Test("Plain text is one run with no emphasis")
    func plain() {
        #expect(runs("just words") == [PostFormatting.Run(text: "just words")])
    }

    @Test("Each marker produces its own emphasis")
    func eachMarker() {
        #expect(runs("**b**") == [PostFormatting.Run(text: "b", traits: .bold)])
        #expect(runs("*i*") == [PostFormatting.Run(text: "i", traits: .italic)])
        #expect(runs("__u__") == [PostFormatting.Run(text: "u", traits: .underline)])
    }

    @Test("Emphasis sits inside the surrounding text")
    func surrounded() {
        #expect(
            runs("a **b** c") == [
                PostFormatting.Run(text: "a "),
                PostFormatting.Run(text: "b", traits: .bold),
                PostFormatting.Run(text: " c"),
            ])
    }

    @Test("The longer marker is matched first")
    func longestMarkerWins() {
        #expect(runs("**b**") == [PostFormatting.Run(text: "b", traits: .bold)])
    }

    @Test("Emphases nest")
    func nesting() {
        #expect(
            runs("**b *i* **") == [
                PostFormatting.Run(text: "b ", traits: .bold),
                PostFormatting.Run(text: "i", traits: [.bold, .italic]),
                PostFormatting.Run(text: " ", traits: .bold),
            ])
    }

    @Test("An unclosed marker is literal text, not an opening")
    func unclosedIsLiteral() {
        #expect(runs("2 * 3 is 6") == [PostFormatting.Run(text: "2 * 3 is 6")])
        #expect(runs("**never closed") == [PostFormatting.Run(text: "**never closed")])
    }

    @Test("An empty pair is literal, not an empty run")
    func emptyPair() {
        #expect(runs("****") == [PostFormatting.Run(text: "****")])
    }

    @Test("Plain text strips every marker")
    func stripped() {
        #expect(PostFormatting.plainText("**b** and *i* and __u__") == "b and i and u")
        #expect(PostFormatting.plainText("2 * 3") == "2 * 3")
    }

    @Test("Runs survive a round trip through marker text")
    func roundTrip() {
        for source in [
            "plain",
            "a **b** c",
            "*i*",
            "__u__",
            "**b** and *i* and __u__",
        ] {
            let once = runs(source)
            #expect(runs(PostFormatting.text(from: once)) == once, "round trip changed \(source)")
        }
    }

    // MARK: Selection

    private func toggled(
        _ trait: PostFormatting.Traits, _ source: String, _ range: Range<Int>
    ) -> String {
        PostFormatting.text(from: PostFormatting.toggling(trait, in: runs(source), over: range))
    }

    @Test("Emphasis applies to the selection, not the post")
    func selectionOnly() {
        #expect(toggled(.bold, "one two", 0..<3) == "**one** two")
        #expect(toggled(.bold, "one two", 4..<7) == "one **two**")
    }

    @Test("Emphasis is removed when the whole selection already has it")
    func removesWhenFullyCovered() {
        #expect(toggled(.bold, "**one** two", 0..<3) == "one two")
    }

    @Test("A partly emphasised selection gains the emphasis")
    func partialSelectionGains() {
        #expect(toggled(.bold, "**one** two", 0..<7) == "**one two**")
    }

    @Test("An empty selection changes nothing")
    func emptySelection() {
        #expect(toggled(.bold, "one two", 3..<3) == "one two")
    }

    @Test("Neighbours with the same emphasis are rejoined")
    func mergesNeighbours() {
        let once = PostFormatting.toggling(.bold, in: runs("one two"), over: 0..<3)
        let twice = PostFormatting.toggling(.bold, in: once, over: 3..<7)
        #expect(twice.count == 1)
        #expect(PostFormatting.text(from: twice) == "**one two**")
    }
}
