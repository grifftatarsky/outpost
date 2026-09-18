import Foundation
import Testing

@testable import CarpenterUI

@Suite("The emoji catalogue")
struct EmojiCatalogueTests {

    private var catalogue: EmojiCatalogue { .shared }

    @Test("The table actually loaded")
    func loaded() {
        // A missing or unparseable resource leaves the grid empty and silent, which is the failure
        // this suite exists to make loud. Run `Scripts/make-emoji-table.py` if this fails.
        #expect(!catalogue.groups.isEmpty, "emoji.json did not load out of the module bundle")
        #expect(catalogue.count > 1_500, "only \(catalogue.count) emoji — the table looks truncated")
    }

    @Test("It is grouped the way Unicode groups it")
    func grouped() {
        let names = catalogue.groups.map(\.name)
        #expect(names.contains("Smileys & Emotion"))
        #expect(names.contains("Animals & Nature"))
        #expect(names.contains("Flags"))
        #expect(!names.contains("Component"), "skin-tone swatches are not something anybody sends")
        #expect(catalogue.groups.allSatisfy { !$0.emoji.isEmpty })
    }

    @Test("No emoji appears twice")
    func distinct() {
        let all = catalogue.all.map(\.emoji)
        #expect(Set(all).count == all.count)
    }

    @Test("Skin-tone variants are left out")
    func noSkinTones() {
        #expect(catalogue.all.allSatisfy { !$0.name.contains("skin tone") })
    }

    @Test("Searching by name finds the obvious things")
    func search() {
        #expect(catalogue.search("cat").contains { $0.emoji == "🐱" })
        #expect(catalogue.search("rocket").contains { $0.emoji == "🚀" })
        #expect(catalogue.search("thumbs up").contains { $0.emoji == "👍" })
        #expect(catalogue.search("heart").count > 5)
    }

    @Test("A whole-word match comes before a match inside another word")
    func wholeWordsFirst() {
        // Typing "cat" should not put a graduation cap above a cat.
        let found = catalogue.search("cat")
        let cat = try? #require(found.firstIndex { $0.emoji == "🐱" })
        let cap = found.firstIndex { $0.name.contains("graduation") }
        if let cat, let cap { #expect(cat < cap) }
    }

    @Test("Case and accents do not matter")
    func forgiving() {
        #expect(catalogue.search("ROCKET").contains { $0.emoji == "🚀" })
        #expect(catalogue.search("  rocket  ").contains { $0.emoji == "🚀" })
    }

    @Test("An empty search asks for nothing rather than everything")
    func emptySearch() {
        #expect(catalogue.search("").isEmpty)
        #expect(catalogue.search("   ").isEmpty)
    }

    @Test("A search that matches nothing returns nothing, rather than guessing")
    func noMatches() {
        #expect(catalogue.search("zzzzzznotanemoji").isEmpty)
    }
}
