import Foundation

/// Every emoji Unicode knows about, grouped and searchable by name.
///
/// Griff ruled 2026-09-14: our own grid from a **refreshable** Unicode table, searchable by name —
/// the one thing the system keyboard cannot do. A hand-maintained list of twenty stood in until
/// 2026-09-15. `Scripts/make-emoji-table.py` regenerates `emoji.json` from
/// `unicode.org/Public/emoji/latest/emoji-test.txt` whenever a new set ships.
///
/// **The names are English, and only English.** They come out of the Unicode file, which carries
/// CLDR's English short names and nothing else; the translated names live in a much larger CLDR
/// data set this app does not carry. So search works for an English speaker and not for anybody
/// else, which is a real limit and is written down in `docs/inbox.md` rather than papered over —
/// the grid itself, the groups and the recents all work regardless of language.
public struct EmojiCatalogue: Sendable {
    public struct Group: Identifiable, Hashable, Sendable {
        public let name: String
        public let emoji: [Entry]
        public var id: String { name }
    }

    public struct Entry: Identifiable, Hashable, Sendable {
        public let emoji: String
        public let name: String
        public var id: String { emoji }
    }

    public let groups: [Group]

    public static let shared = EmojiCatalogue()

    public init(groups: [Group]) {
        self.groups = groups
    }

    private init() {
        struct Wire: Decodable {
            struct Item: Decodable {
                let e: String
                let n: String
            }
            let name: String
            let emoji: [Item]
        }

        guard let url = Bundle.module.url(forResource: "emoji", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let read = try? JSONDecoder().decode([Wire].self, from: data)
        else {
            // A missing resource is a build mistake, not something a member can cause. The picker
            // draws its empty state rather than crashing, and `EmojiCatalogueTests` fails loudly.
            groups = []
            return
        }

        groups = read.map { group in
            Group(
                name: group.name,
                emoji: group.emoji.map { Entry(emoji: $0.e, name: $0.n) })
        }
    }

    public var count: Int { groups.reduce(0) { $0 + $1.emoji.count } }

    public var all: [Entry] { groups.flatMap(\.emoji) }

    /// Matches on whole words first, then on any substring, so typing "cat" puts 🐱 *cat face*
    /// above 🎓 *graduation cap* rather than below it.
    public func search(_ query: String) -> [Entry] {
        let needle = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }

        var exact: [Entry] = []
        var leading: [Entry] = []
        var anywhere: [Entry] = []

        for entry in all {
            let name = entry.name.folding(
                options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            guard name.contains(needle) else { continue }

            let words = name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == ":" })
            if words.contains(where: { $0 == needle }) {
                exact.append(entry)
            } else if words.contains(where: { $0.hasPrefix(needle) }) {
                leading.append(entry)
            } else {
                anywhere.append(entry)
            }
        }

        return exact + leading + anywhere
    }
}
