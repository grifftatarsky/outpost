import Foundation

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
