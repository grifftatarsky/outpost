import Foundation

public enum AvatarInitials {
    private static let articles: Set<String> = ["a", "an", "the"]

    public static func of(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // A name that opens with an emoji is a name whose mark somebody chose. Letters-only
        // initials threw it away, and a room called only "🎈" drew an empty disc.
        if let mark = leadingEmoji(of: trimmed) { return mark }

        var words =
            trimmed
            .split(whereSeparator: \.isWhitespace)
            .map { String($0.filter { $0.isLetter || $0.isNumber }) }
            .filter { !$0.isEmpty }

        if words.count > 1, articles.contains(words[0].lowercased()) {
            words.removeFirst()
        }

        // Nothing but punctuation still yields nothing: a stray glyph in a disc reads as a fault,
        // and `degenerate()` has pinned that since before emoji were considered.
        return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    /// The first character, when it is one somebody picked as a mark rather than a letter.
    private static func leadingEmoji(of name: String) -> String? {
        guard let first = name.first, isEmoji(first) else { return nil }
        return String(first)
    }

    public static func isEmoji(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        // A single scalar is only an emoji when it is meant to be presented as one: `isEmoji` alone
        // is true of digits and `#`, which are emoji only with a variation selector after them.
        if character.unicodeScalars.count == 1 {
            return scalar.properties.isEmojiPresentation
        }
        return character.unicodeScalars.contains { $0.properties.isEmojiPresentation }
            || character.unicodeScalars.contains { $0.value == 0xFE0F }
    }
}
