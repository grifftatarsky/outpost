import Foundation

public enum PostTags {
    public static func canonical(_ tag: String) -> String { tag.lowercased() }

    public static func occurrences(in text: String) -> [(range: Range<String.Index>, tag: String)] {
        var found: [(Range<String.Index>, String)] = []
        var previous: Character?
        var i = text.startIndex

        while i < text.endIndex {
            let character = text[i]
            let boundary = previous.map { !$0.isLetter && !$0.isNumber && $0 != "#" } ?? true
            if character == "#", boundary {
                var j = text.index(after: i)
                var word = ""
                while j < text.endIndex,
                    text[j].isLetter || text[j].isNumber || text[j] == "_"
                {
                    word.append(text[j])
                    j = text.index(after: j)
                }
                if !word.isEmpty {
                    found.append((i..<j, word))
                    previous = word.last
                    i = j
                    continue
                }
            }
            previous = character
            i = text.index(after: i)
        }
        return found
    }

    public static func tags(in text: String) -> [String] {
        var seen = Set<String>()
        return occurrences(in: text).compactMap { _, tag in
            seen.insert(canonical(tag)).inserted ? tag : nil
        }
    }

    public static func text(_ text: String, has tag: String) -> Bool {
        let wanted = canonical(tag)
        return occurrences(in: text).contains { canonical($0.tag) == wanted }
    }

    public static func index(of posts: [OutpostPost]) -> [String: [PostID]] {
        var index: [String: [PostID]] = [:]
        for post in posts {
            for tag in tags(in: post.body) {
                index[canonical(tag), default: []].append(post.id)
            }
        }
        return index
    }
}
