import CarpenterKit
import CarpenterUI
import Foundation
import Testing

@Suite("The joiner's sheet")
struct RedeemInviteFlowTests {
    private let offer = InviteOffer(
        roomName: nil, inviterName: nil, phrase: "K7M2QX",
        expiresAt: Date(timeIntervalSince1970: 1_786_721_400))

    private func checking() -> RedeemInviteFlow {
        var flow = RedeemInviteFlow()
        flow.paste("an-invite")
        #expect(flow.read { _ in self.offer })
        return flow
    }

    @Test("Reading a usable invite shows the phrase")
    func readingShowsThePhrase() {
        let flow = checking()
        guard case .checking(let shown) = flow.step else {
            Issue.record("reading a usable invite did not show the phrase: \(flow.step)")
            return
        }
        #expect(shown.phrase == "K7M2QX")
    }

    @Test("Nothing about the room is shown before the phrase is confirmed")
    func nothingAboutTheRoom() {
        let flow = checking()
        guard case .checking(let shown) = flow.step else {
            Issue.record("no offer to check")
            return
        }
        #expect(shown.roomName == nil, "an unconfirmed invitation named the room it offers")
        #expect(shown.inviterName == nil, "an unconfirmed invitation named who sent it")
    }

    @Test("Refusing goes to the warning, not back to the field")
    func refusingWarns() {
        var flow = checking()
        flow.refuse()
        #expect(flow.step == .refused(offer))
    }

    @Test("A refusal keeps the six characters it refused")
    func refusingKeepsThePhrase() {
        var flow = checking()
        flow.refuse()
        guard case .refused(let refused) = flow.step else {
            Issue.record("a refusal with nothing behind it")
            return
        }
        #expect(refused.phrase == offer.phrase)
    }

    @Test("Nothing on the refused screen leads back to the invitation")
    func refusingIsTerminal() {
        var flow = checking()
        flow.refuse()

        flow.paste("an-invite")
        _ = flow.read { _ in self.offer }
        flow.settled(nil)
        flow.failed("anything")

        #expect(flow.step == .refused(offer), "a refused invitation was reopened")
    }

    @Test("Refusing drops the invitation itself")
    func refusingDropsTheCode() {
        var flow = checking()
        flow.refuse()
        #expect(flow.code.isEmpty, "a refused invitation was kept, ready to be sent")
        #expect(flow.problem == nil, "a refusal was drawn as an error under the field")
    }

    @Test("An unusable invite stays on the field with its reason")
    func unusableStaysPut() {
        var flow = RedeemInviteFlow()
        flow.paste("nonsense")
        #expect(!flow.read { _ in nil })
        flow.failed("That is not a usable invite.")

        #expect(flow.step == .pasting)
        #expect(flow.problem == "That is not a usable invite.")
    }

    @Test("An accept that failed keeps the phrase up and says why")
    func failedAcceptKeepsThePhrase() {
        var flow = checking()
        flow.settled("That did not go through")

        guard case .checking = flow.step else {
            Issue.record("a failed accept left the phrase screen: \(flow.step)")
            return
        }
        #expect(flow.problem == "That did not go through")
        #expect(flow.code == "an-invite", "a failed accept threw away what it would retry")
    }
}
