import CarpenterKit
import SwiftUI

public struct SupporterSettings {
    public let standing: SupporterStanding
    public let canClaim: Bool
    public let showsBadge: Bool
    public let onClaim: () async -> Void
    public let onShowBadge: (Bool) async -> Void

    public init(
        standing: SupporterStanding,
        canClaim: Bool,
        showsBadge: Bool,
        onClaim: @escaping () async -> Void,
        onShowBadge: @escaping (Bool) async -> Void
    ) {
        self.standing = standing
        self.canClaim = canClaim
        self.showsBadge = showsBadge
        self.onClaim = onClaim
        self.onShowBadge = onShowBadge
    }

    var standingSentence: Text {
        switch standing {
        case .none:
            Text("You are not a Supporter.", bundle: .module)
        case .testFlightYear(endsAt: nil):
            Text(
                "Your free year starts on the day the app is released on the App Store.",
                bundle: .module)
        case .testFlightYear(endsAt: let end?):
            Text(
                "Your free year runs until \(end.formatted(.dateTime.day().month(.wide).year())).",
                bundle: .module)
        }
    }

    var standingDetail: Text {
        switch standing {
        case .none: Text("Ended", bundle: .module)
        case .testFlightYear(endsAt: nil): Text("Free year", bundle: .module)
        case .testFlightYear(endsAt: let end?):
            Text("Until \(end.formatted(.dateTime.day().month(.abbreviated).year()))", bundle: .module)
        }
    }
}
