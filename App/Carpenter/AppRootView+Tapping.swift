import CarpenterApp
import CarpenterKit
import CarpenterUI
import SwiftUI

// MARK: Tapping two phones to swap codes

extension AppRootView {
    var tapToSwap: TapToSwap? {
        #if os(iOS)
            TapSwapper.canMeasure ? TapToSwap(start: { [self] in Task { await startTapping() } }) : nil
        #else
            nil
        #endif
    }

    #if os(iOS)
        func startTapping() async {
            let raw = await session.joinerCode(through: mailbox)
            guard let code = try? JoinerCode.decoded(from: raw),
                let link = try? InviteLink.url(offering: code, scheme: Branding.urlScheme)
            else { return }
            tapSwapper?.stop()
            tappedCodes = []
            let swapper = TapSwapper(handingOver: link.absoluteString)
            swapper.onArrival = { arrival in tapArrived(arrival) }
            swapper.start()
            tapSwapper = swapper
            tappingPhones = true
        }

        func tapArrived(_ text: String) {
            guard tappingPhones else { return route(tapped: text) }
            tapArrivals.append(text)
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                tappingPhones = false
            }
        }

        func finishTapping() {
            guard let swapper = tapSwapper else { return }
            let arrived = tapArrivals
            tapArrivals = []
            guard swapper.hasSwapped else {
                swapper.stop()
                tapSwapper = nil
                return
            }
            swapper.keepOnlyThePartner()
            for text in arrived { route(tapped: text) }
            Task {
                try? await Task.sleep(for: TapSwapper.lingers)
                guard tapSwapper === swapper else { return }
                swapper.stop()
                tapSwapper = nil
            }
        }

        func route(tapped text: String) {
            guard let url = URL(string: text) else { return }
            if case .code(let code)? = InviteLink.read(url, scheme: Branding.urlScheme), let raw = try? code.encoded() {
                tappedCodes.insert(raw)
            }
            take(url)
        }

        func handBack(_ invite: Invite, to joinerCode: String) {
            guard let swapper = tapSwapper, tappedCodes.contains(InviteLink.payload(in: joinerCode)),
                let link = try? InviteLink.url(inviting: invite, scheme: Branding.urlScheme)
            else { return }
            swapper.handOver(link.absoluteString)
        }
    #endif
}
