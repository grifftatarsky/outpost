import CarpenterKit
import Foundation
import SwiftUI
import Testing

@testable import CarpenterUI

@MainActor
@Suite("The delivery marks say what they show")
struct DeliveryMarkSpeaksTests {

    private let silence = Text(verbatim: "")

    private func mark(_ delivery: DeliveryState, edited: Bool = false) -> DeliveryMarkView {
        DeliveryMarkView(delivery: delivery, isEdited: edited)
    }

    @Test("A message somebody else edited is not silent")
    func editedByAnotherPersonSpeaks() {
        #expect(
            mark(.pending, edited: true).spoken != silence,
            "an edited message drew a mark and told VoiceOver nothing")
        #expect(mark(.pending, edited: true).spoken == Text("Edited.", bundle: .module))

        #expect(mark(.pending, edited: true).label == silence)
    }

    @Test("An edit is said as well as the delivery, in every visible state")
    func editedIsSaidAlongsideDelivery() {
        for delivery in [
            DeliveryState.sent, .delivered, .notReported, .noRecipients,
            .displayed(at: Date(timeIntervalSince1970: 1_786_635_000)),
        ] {
            let plain = mark(delivery).spoken
            let edited = mark(delivery, edited: true).spoken
            #expect(edited != plain, "\(delivery) said the same thing edited and not edited")
            #expect(edited != silence)
        }
    }

    @Test("Without an edit, the label is the delivery on its own")
    func unchangedWhenNotEdited() {
        for delivery in [DeliveryState.sent, .delivered, .notReported, .noRecipients] {
            #expect(mark(delivery).spoken == mark(delivery).label)
        }
    }

    @Test("Every state a member can see says something")
    func nothingVisibleIsSilent() {
        for delivery in [
            DeliveryState.sent, .delivered, .notReported, .noRecipients,
            .displayed(at: Date(timeIntervalSince1970: 1_786_635_000)),
        ] {
            #expect(delivery.isVisible)
            #expect(mark(delivery).spoken != silence, "\(delivery) is drawn and says nothing")
        }
        #expect(!DeliveryState.pending.isVisible)
    }

    @Test("Each state says something different from the others")
    func statesAreDistinguishable() {
        let spoken = [
            DeliveryState.sent, .delivered, .notReported, .noRecipients,
            .displayed(at: Date(timeIntervalSince1970: 1_786_635_000)),
        ].map { mark($0).spoken }

        for (i, one) in spoken.enumerated() {
            for other in spoken[(i + 1)...] {
                #expect(one != other, "two delivery states are spoken identically")
            }
        }
    }
}
