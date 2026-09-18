import Foundation

public enum PostFormatting {
    public struct Traits: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let bold = Traits(rawValue: 1 << 0)
        public static let italic = Traits(rawValue: 1 << 1)
        public static let underline = Traits(rawValue: 1 << 2)
    }

    public struct Run: Hashable, Sendable {
        public let text: String
        public let traits: Traits

        public init(text: String, traits: Traits = []) {
            self.text = text
            self.traits = traits
        }
    }

    private static let markers: [(String, Traits)] = [
        ("**", .bold),
        ("__", .underline),
        ("*", .italic),
    ]

    public static func runs(in source: String) -> [Run] {
        var output: [Run] = []
        var plain = ""
        var index = source.startIndex

        func flush() {
            if !plain.isEmpty {
                output.append(Run(text: plain))
                plain = ""
            }
        }

        while index < source.endIndex {
            guard let (marker, trait) = opening(at: index, in: source),
                let close = closing(marker, after: source.index(index, offsetBy: marker.count),
                    in: source)
            else {
                plain.append(source[index])
                index = source.index(after: index)
                continue
            }

            let inner = String(source[source.index(index, offsetBy: marker.count)..<close])
            flush()

            for nested in runs(in: inner) {
                output.append(Run(text: nested.text, traits: nested.traits.union(trait)))
            }

            index = source.index(close, offsetBy: marker.count)
        }

        flush()
        return output
    }

    private static func opening(at index: String.Index, in source: String) -> (String, Traits)? {
        markers.first { marker, _ in source[index...].hasPrefix(marker) }
    }

    private static func closing(
        _ marker: String, after start: String.Index, in source: String
    ) -> String.Index? {
        guard start <= source.endIndex else { return nil }
        var index = start
        while index < source.endIndex {
            if source[index...].hasPrefix(marker) { return index == start ? nil : index }
            index = source.index(after: index)
        }
        return nil
    }

    public static func text(from runs: [Run]) -> String {
        runs.map { run in
            var out = run.text
            if run.traits.contains(.italic) { out = "*" + out + "*" }
            if run.traits.contains(.underline) { out = "__" + out + "__" }
            if run.traits.contains(.bold) { out = "**" + out + "**" }
            return out
        }
        .joined()
    }

    public static func toggling(
        _ trait: Traits, in runs: [Run], over range: Range<Int>
    ) -> [Run] {
        guard !range.isEmpty else { return runs }

        let covered = split(runs, at: range)
        let selected = covered.filter { $0.range.overlaps(range) }
        let removing = !selected.isEmpty && selected.allSatisfy { $0.run.traits.contains(trait) }

        return merge(
            covered.map { piece in
                guard piece.range.overlaps(range) else { return piece.run }
                let traits =
                    removing
                    ? piece.run.traits.subtracting(trait) : piece.run.traits.union(trait)
                return Run(text: piece.run.text, traits: traits)
            })
    }

    private struct Piece {
        let run: Run
        let range: Range<Int>
    }

    private static func split(_ runs: [Run], at range: Range<Int>) -> [Piece] {
        var pieces: [Piece] = []
        var offset = 0

        for run in runs {
            let characters = Array(run.text)
            var start = 0

            for boundary in [range.lowerBound - offset, range.upperBound - offset]
                .filter({ $0 > 0 && $0 < characters.count })
                .sorted()
            {
                pieces.append(
                    Piece(
                        run: Run(text: String(characters[start..<boundary]), traits: run.traits),
                        range: (offset + start)..<(offset + boundary)))
                start = boundary
            }

            pieces.append(
                Piece(
                    run: Run(text: String(characters[start...]), traits: run.traits),
                    range: (offset + start)..<(offset + characters.count)))
            offset += characters.count
        }

        return pieces
    }

    private static func merge(_ runs: [Run]) -> [Run] {
        runs.reduce(into: [Run]()) { output, run in
            guard run.text.isEmpty == false else { return }
            if let last = output.last, last.traits == run.traits {
                output[output.count - 1] = Run(text: last.text + run.text, traits: last.traits)
            } else {
                output.append(run)
            }
        }
    }

    public static func plainText(_ source: String) -> String {
        runs(in: source).map(\.text).joined()
    }
}
