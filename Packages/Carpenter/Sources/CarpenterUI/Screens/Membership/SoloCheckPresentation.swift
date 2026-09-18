import CarpenterKit
import SwiftUI

public enum SoloCheckPresentation: Hashable, Sendable {
    case nothing
    case heldByYourSetting(askedBy: Member?, since: Date?)
    case heldByYourChoice(since: Date)
    case waitingOnThem(since: Date)
    case waitingOnYou(askedBy: Member, since: Date)
    case refused(by: Member, at: Date, answerable: Member?)

    public var closesTheComposer: Bool {
        switch self {
        case .nothing, .waitingOnThem, .waitingOnYou: return false
        case .heldByYourSetting, .heldByYourChoice, .refused: return true
        }
    }

    public var canAnswer: Bool {
        switch self {
        case .waitingOnYou: return true
        case .heldByYourSetting(let askedBy, _): return askedBy != nil
        case .refused(_, _, let answerable): return answerable != nil
        case .nothing, .heldByYourChoice, .waitingOnThem: return false
        }
    }

    public static func of(
        _ check: SoloCheck, viewer: ParticipantID?, naming: (ParticipantID) -> Member,
        isSolo: Bool, requiresCheck: Bool, isHolding: Bool
    ) -> SoloCheckPresentation {
        guard isSolo else { return .nothing }

        if case .refused(let by, let at) = check.state {
            let standing = check.answerableAsk.flatMap { ask in
                ask.asker == viewer ? nil : naming(ask.asker)
            }
            return .refused(by: naming(by), at: at, answerable: standing)
        }

        guard case .outstanding(let askedBy, let at) = check.state else {
            return requiresCheck && !check.isConfirmed
                ? .heldByYourSetting(askedBy: nil, since: nil) : .nothing
        }

        let theirs = askedBy == viewer ? nil : naming(askedBy)

        if requiresCheck { return .heldByYourSetting(askedBy: theirs, since: at) }
        if let theirs { return .waitingOnYou(askedBy: theirs, since: at) }
        return isHolding ? .heldByYourChoice(since: at) : .waitingOnThem(since: at)
    }
}
