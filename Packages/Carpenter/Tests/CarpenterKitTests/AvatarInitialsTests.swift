import Foundation
import Testing
import CarpenterKitTesting

@testable import CarpenterKit

@Suite("Avatar initials")
struct AvatarInitialsTests {
    @Test(
        "A multi-word name reduces to the first letter of its first two significant words",
        arguments: [
            ("Zeppelin Enthusiasts", "ZE"),
            ("Carcosa Aeronautics Club", "CA"),
            ("Lighter Than Air", "LT"),
            ("Blimps Only", "BO"),
        ]
    )
    func multiWord(name: String, expected: String) {
        #expect(AvatarInitials.of(name) == expected)
    }

    @Test("A leading article is not a significant word")
    func leadingArticle() {
        #expect(AvatarInitials.of("The Gasbag Gazette") == "GG")
        #expect(AvatarInitials.of("An Airship Concern") == "AC")
        #expect(AvatarInitials.of("a quiet room") == "QR")
    }

    @Test("An article standing alone is all the name there is")
    func articleAlone() {
        #expect(AvatarInitials.of("The") == "T")
    }

    @Test("A single-word name contributes a single letter")
    func singleWord() {
        #expect(AvatarInitials.of("Cassilda") == "C")
        #expect(AvatarInitials.of("Hastur") == "H")
    }

    @Test("Case and stray whitespace do not survive")
    func normalisation() {
        #expect(AvatarInitials.of("  blimps   only  ") == "BO")
        #expect(AvatarInitials.of("\tthe\ngasbag gazette ") == "GG")
    }

    @Test("Names outside the Latin alphabet still yield their own initials")
    func nonLatin() {
        #expect(AvatarInitials.of("Ада Лавлейс") == "АЛ")
        #expect(AvatarInitials.of("Åsa Öberg") == "ÅÖ")
    }

    @Test("A digit is as much a name as a letter")
    func digits() {
        #expect(AvatarInitials.of("Hangar 7") == "H7")
        #expect(AvatarInitials.of("Studio 54 Revival") == "S5")
        #expect(AvatarInitials.of("7") == "7")
    }

    @Test("An empty or punctuation-only name yields nothing rather than a stray glyph")
    func degenerate() {
        #expect(AvatarInitials.of("") == "")
        #expect(AvatarInitials.of("   ") == "")
        #expect(AvatarInitials.of("—") == "")
    }

    @Test("A stand-in for a name that was never given gets two characters, not one")
    func placeholderMonogram() {
        let id = ParticipantID(rawValue: WideID.of([0xA3, 0xF1, 0x09]))
        let unnamed = Member.placeholder(id)

        #expect(unnamed.isPlaceholder)
        #expect(unnamed.displayName == "A3F109")
        #expect(unnamed.initials == "A3", "an unnamed member drew a one-character monogram")
    }

    @Test("Two unnamed people do not collide")
    func placeholdersDiffer() {
        let one = Member.placeholder(ParticipantID(rawValue: WideID.of([0xA3, 0xF1])))
        let two = Member.placeholder(ParticipantID(rawValue: WideID.of([0xA7, 0x0B])))

        #expect(one.initials != two.initials)
    }

    @Test("A chosen name still follows the ordinary rule")
    func chosenNamesUnchanged() {
        #expect(Member(id: ParticipantID(rawValue: WideID.of([1])), displayName: "Cassilda").initials == "C")
        #expect(Member(id: ParticipantID(rawValue: WideID.of([2])), displayName: "Blimps Only").initials == "BO")
    }

    @Test("Two people who have never named themselves do not get the same disc")
    func peopleWithNoNameAreToldApart() {
        let discs = (1...32).map { seed -> String in
            let id = ParticipantID(rawValue: Data(repeating: UInt8(seed), count: 32))
            return Member(id: id, displayName: id.shortCode, isPlaceholder: true).initials
        }

        #expect(
            Set(discs).count == discs.count,
            """
            Two unnamed people drew the same monogram. A short code is one word, so taking the \
            first letter of each of the first two words gives a single character and the discs \
            collide all down a list of people who have never named themselves.
            """)
        #expect(discs.allSatisfy { $0.count == 2 }, "a monogram from a code should be two characters")
    }

    // MARK: Names somebody chose a mark for

    @Test("A room named only with an emoji draws the emoji, not an empty disc")
    func anEmojiNameDrawsTheEmoji() {
        #expect(
            AvatarInitials.of("🎈") == "🎈",
            """
            The initials were letters and numbers only, so a name made of an emoji filtered down to \
            nothing and drew a blank disc. An emoji in a name is a mark somebody picked.
            """)
    }

    @Test("An emoji in front of words is the mark, and the words are not")
    func aLeadingEmojiWins() {
        #expect(AvatarInitials.of("🎈 Lanterns") == "🎈")
        #expect(AvatarInitials.of("🛟 Safety Committee") == "🛟")
    }

    @Test("An emoji anywhere else leaves the letters alone")
    func anEmojiElsewhereDoesNotWin() {
        #expect(
            AvatarInitials.of("Lanterns 🎈") == "L",
            "an emoji at the end is decoration, not the mark somebody led with")
        #expect(AvatarInitials.of("The Gasbag 🎈 Gazette") == "GG")
    }

    @Test("A digit is not an emoji, whatever Unicode says about the character")
    func digitsAreNotEmoji() {
        #expect(
            AvatarInitials.of("7 Hangars") == "7H",
            """
            Character.isEmoji is true of a bare digit, because a digit becomes an emoji with a \
            variation selector after it. Presentation is the question, not eligibility.
            """)
        #expect(AvatarInitials.of("1984") == "1")
    }

    @Test("An emoji does not rescue a name that is otherwise punctuation")
    func punctuationStillYieldsNothing() {
        #expect(
            AvatarInitials.of("…") == "",
            """
            Reading an emoji as a mark must not turn every stray glyph into one. A punctuation-only \
            name still draws nothing, which `degenerate()` has required since before emoji names \
            were considered.
            """)
    }
}
