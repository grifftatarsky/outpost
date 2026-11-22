import Foundation

public enum AvatarInitials {
    private static let articles: Set<String> = ["a", "an", "the"]

    public static func of(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let mark = leadingEmoji(of: trimmed) { return mark }

        var words =
            trimmed
            .split(whereSeparator: \.isWhitespace)
            .map { String($0.filter { $0.isLetter || $0.isNumber }) }
            .filter { !$0.isEmpty }

        if words.count > 1, articles.contains(words[0].lowercased()) {
            words.removeFirst()
        }

        return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private static func leadingEmoji(of name: String) -> String? {
        guard let first = name.first, isEmoji(first) else { return nil }
        return String(first)
    }

    public static func isEmoji(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        if character.unicodeScalars.count == 1 {
            return scalar.properties.isEmojiPresentation
        }
        return character.unicodeScalars.contains { $0.properties.isEmojiPresentation }
            || character.unicodeScalars.contains { $0.value == 0xFE0F }
    }
}
