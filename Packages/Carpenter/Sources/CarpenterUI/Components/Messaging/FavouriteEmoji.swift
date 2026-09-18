import Foundation
import Observation

@MainActor
@Observable
public final class FavouriteEmoji {
    private static let key = "reactions.counts"

    nonisolated public static let slots = 4

    nonisolated public static let starting = ["❤️", "👍", "👎", "🫡"]

    private let defaults: UserDefaults
    private var counts: [String: Int]

    public private(set) var emoji: [String] = []

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        counts = (defaults.dictionary(forKey: Self.key) as? [String: Int]) ?? [:]
        emoji = Self.ranked(counts)
    }

    public func record(_ value: String) {
        counts[value, default: 0] += 1
        defaults.set(counts, forKey: Self.key)
        emoji = Self.ranked(counts)
    }

    nonisolated static func ranked(_ counts: [String: Int]) -> [String] {
        let known = Set(counts.keys).union(starting)
        let ordered = known.sorted { left, right in
            let (a, b) = (counts[left] ?? 0, counts[right] ?? 0)
            if a != b { return a > b }

            let (i, j) = (starting.firstIndex(of: left), starting.firstIndex(of: right))
            switch (i, j) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return left < right
            }
        }
        return Array(ordered.prefix(slots))
    }
}
