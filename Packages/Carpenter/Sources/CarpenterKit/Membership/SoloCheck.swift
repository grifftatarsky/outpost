import Foundation

public struct SoloCheck: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case notChecked
        case outstanding(askedBy: ParticipantID, at: Date)
        case confirmed(at: Date)
        case refused(by: ParticipantID, at: Date)
    }

    private struct Ask: Hashable, Sendable {
        let asker: ParticipantID
        let at: Date
        let seq: Int
    }

    private struct Answer: Hashable, Sendable {
        let by: ParticipantID
        let at: Date
        let seq: Int
        let move: SoloCheckBody.Move
    }

    private var asks: [EntryHash: Ask] = [:]
    private var answered: Set<EntryHash> = []
    private var early: [EntryHash: Answer] = [:]
    private var settled: Answer?
    private var refusal: Refusal?

    private struct Refusal: Hashable, Sendable {
        let answer: Answer
    }

    private var applied = 0

    public init() {}

    public var state: State {
        if let refusal { return .refused(by: refusal.answer.by, at: refusal.answer.at) }
        if let oldest = oldestOpenAsk(after: 0) {
            return .outstanding(askedBy: oldest.asker, at: oldest.at)
        }
        if let settled, settled.move == .confirmed { return .confirmed(at: settled.at) }
        return .notChecked
    }

    public var answerableAsk: (asker: ParticipantID, at: Date)? {
        guard let refusal else { return nil }
        guard let ask = oldestOpenAsk(after: refusal.answer.seq) else { return nil }
        return (ask.asker, ask.at)
    }

    private func oldestOpenAsk(after seq: Int) -> Ask? {
        asks.filter { !answered.contains($0.key) && $0.value.seq > seq }
            .values
            .min { left, right in
                left.at == right.at
                    ? left.asker.rawValue.lexicographicallyPrecedes(right.asker.rawValue)
                    : left.at < right.at
            }
    }

    public var isBlocked: Bool {
        if case .refused = state { return true }
        return false
    }

    public var isOutstanding: Bool {
        if case .outstanding = state { return true }
        return false
    }

    public var isConfirmed: Bool {
        if case .confirmed = state { return true }
        return false
    }

    public var askedBy: ParticipantID? {
        if case .outstanding(let asker, _) = state { return asker }
        return nil
    }

    public static let shaping: Set<PayloadType> = [.soloCheck]

    public mutating func apply(_ entry: RenderedEntry, body: Payload) {
        guard body.type == .soloCheck,
            let move = try? body.decode(SoloCheckBody.self)
        else { return }
        applied += 1
        let seq = applied

        switch move.move {
        case .asked:
            asks[entry.id] = Ask(asker: entry.author, at: entry.wallTime, seq: seq)
            if let waiting = early.removeValue(forKey: entry.id) {
                resolve(
                    entry.id, by: waiting.by, at: waiting.at, seq: waiting.seq, as: waiting.move)
            }

        case .confirmed, .refused:
            guard let asked = move.answering else { return }
            guard asks[asked] != nil else {
                if early[asked]?.move != .refused {
                    early[asked] = Answer(
                        by: entry.author, at: entry.wallTime, seq: seq, move: move.move)
                }
                return
            }
            resolve(asked, by: entry.author, at: entry.wallTime, seq: seq, as: move.move)
        }
    }

    private mutating func resolve(
        _ ask: EntryHash, by author: ParticipantID, at: Date, seq: Int,
        as move: SoloCheckBody.Move
    ) {
        guard let asked = asks[ask] else { return }
        if move == .confirmed && author == asked.asker { return }
        answered.insert(ask)

        let answer = Answer(by: author, at: at, seq: seq, move: move)

        if move == .refused {
            if let held = refusal, held.answer.seq > seq { return }
            refusal = Refusal(answer: answer)
        } else if let held = refusal, asked.seq <= held.answer.seq {
            return
        } else {
            refusal = nil
        }

        if let settled, settled.seq > seq { return }
        settled = answer
    }
}
