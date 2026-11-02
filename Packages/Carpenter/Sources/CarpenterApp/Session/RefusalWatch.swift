import CarpenterKit
import Foundation

struct RefusalWatch {
    static let onePersonHoldsKeysOnceIn: TimeInterval = 3_600

    private var refusedLastRound: [ParticipantID?: Set<SyncReport.Refusal>] = [:]
    private var lastHeldBy: [ParticipantID?: Date] = [:]

    mutating func holdsKeys(after refusals: [SyncReport.Refusal], at now: Date) -> Bool {
        let refused = Dictionary(grouping: refusals.filter { !$0.isFinal }, by: \.from).mapValues(Set.init)
        var holds = false
        for (person, theirs) in refused where !theirs.isSubset(of: refusedLastRound[person] ?? []) {
            if let last = lastHeldBy[person], now.timeIntervalSince(last) < Self.onePersonHoldsKeysOnceIn { continue }
            lastHeldBy[person] = now
            holds = true
        }
        refusedLastRound = refused
        return holds
    }
}
