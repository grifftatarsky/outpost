import CarpenterApp
import CarpenterKit
import CarpenterUI
import OSLog
import StoreKit
import SwiftUI

enum Distribution {
    static func channel() async -> DistributionChannel {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            guard let flag = arguments.firstIndex(of: "--channel"), flag + 1 < arguments.count else {
                return .development
            }
            switch arguments[flag + 1] {
            case "testflight": return .testFlight
            case "appstore": return .appStore
            default: return .development
            }
        #else
            do {
                guard case .verified(let transaction) = try await AppTransaction.shared else { return .appStore }
                switch transaction.environment {
                case .sandbox: return .testFlight
                case .xcode: return .development
                default: return .appStore
                }
            } catch {
                Diagnostics.sync.error(
                    "supporter: could not read how this copy was installed (\(String(describing: error), privacy: .public))")
                return .appStore
            }
        #endif
    }
}

extension AppRootView {
    var supporterSettings: SupporterSettings? {
        guard session.canClaimSupporterYear || session.isSupporter else { return nil }
        return SupporterSettings(
            standing: session.supporterStanding,
            canClaim: session.canClaimSupporterYear,
            showsBadge: session.showsSupporterBadge,
            sharesBadge: session.sharesSupporterBadge,
            onClaim: { await session.claimSupporterYear() },
            onShowBadge: { await session.setShowsSupporterBadge($0) },
            onShareBadge: { await session.setSharesSupporterBadge($0) },
            onAnswerBadge: { await session.answerSupporterBadge($0) })
    }

    func settleDistribution() async {
        if distribution == nil { distribution = await Distribution.channel() }
        guard let distribution else { return }
        if session.distribution != distribution { session.distribution = distribution }
        await session.refreshSupporterStanding()
    }
}
