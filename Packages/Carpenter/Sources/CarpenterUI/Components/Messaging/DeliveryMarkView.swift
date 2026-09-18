import CarpenterKit
import SwiftUI

struct DeliveryMarkView: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let delivery: DeliveryState
    var isEdited: Bool = false
    var notGone: NotGone?
    var sentAt: Date = .distantPast

    @ScaledMetric(relativeTo: .caption2) private var box = CarpenterMetrics.deliveryMarkBox

    var body: some View {
        if let notGone {
            HStack(spacing: 5) {
                if isEdited { EditedMark() }
                NotGoneMark(notGone: notGone, sentAt: sentAt)
            }
            .padding(.top, 3)
        } else if delivery.isVisible || isEdited {
            HStack(spacing: 5) {
                if isEdited { EditedMark() }
                if let at = delivery.displayedAt {
                    Text(RelativeTimestampFormatter().readReceipt(at))
                        .font(CarpenterFont.micro)
                        .foregroundStyle(palette.quaternaryText)
                }

                HStack(spacing: 4) {
                    if delivery.hasNobodyToReach {
                        mark(.nobodyToSendItTo)
                    } else {
                    mark(.plane(filled: delivery.isCollected))
                    mark(
                        delivery.reportingIsOff
                            ? .eyeThatWillNeverOpen
                            : .eye(filled: delivery.wasDisplayed))
                    }
                }
            }
            .padding(.top, 3)
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: delivery)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityRespondsToUserInteraction(false)
        }
    }

    private enum Mark {
        case plane(filled: Bool)
        case eye(filled: Bool)
        case eyeThatWillNeverOpen
        case nobodyToSendItTo
    }

    @ViewBuilder
    private func mark(_ kind: Mark) -> some View {
        switch kind {
        case .plane(let filled):
            glyph(filled ? "paperplane.fill" : "paperplane", lit: filled)
        case .eye(let filled):
            glyph(filled ? "eye.fill" : "eye", lit: filled)
        case .eyeThatWillNeverOpen:
            Image(systemName: "eye.slash")
                .font(.system(size: box, weight: .semibold))
                .foregroundStyle(palette.quaternaryText)
        case .nobodyToSendItTo:
            Image(systemName: "person.slash")
                .font(.system(size: box, weight: .semibold))
                .foregroundStyle(palette.quaternaryText)
        }
    }

    private func glyph(_ name: String, lit: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: box, weight: .semibold))
            .foregroundStyle(lit ? palette.accentColor : palette.unlitMark)
    }

    var spoken: Text {
        guard isEdited else { return label }
        let edited = Text("Edited.", bundle: .module)
        guard delivery.isVisible else { return edited }
        return Text("\(edited) \(label)", bundle: .module)
    }

    var label: Text {
        switch delivery {
        case .pending:
            return Text(verbatim: "")
        case .sent:
            return Text("Sent. Not collected yet.", bundle: .module)
        case .noRecipients:
            return Text(
                "Saved. There is nobody in this room to send it to yet — it will go when somebody joins.",
                bundle: .module)
        case .delivered:
            return Text("Collected. Not yet shown.", bundle: .module)
        case .notReported:
            return Text(
                "Collected. This person does not report when a message is shown.", bundle: .module)
        case .displayed(let at):
            return Text(
                "Collected. Shown \(RelativeTimestampFormatter().readReceipt(at)).", bundle: .module)
        }
    }
}

#if DEBUG
    #Preview("Delivery marks") {
        VStack(alignment: .trailing, spacing: 18) {
            DeliveryMarkView(delivery: .pending)
            DeliveryMarkView(delivery: .sent)
            DeliveryMarkView(delivery: .delivered)
            DeliveryMarkView(delivery: .notReported)
            DeliveryMarkView(delivery: .displayed(at: Date(timeIntervalSince1970: 1_786_635_000)))
        }
        .padding(40)
        .themed(.default)
    }
#endif

struct EditedMark: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Text("Edited", bundle: .module)
            .font(CarpenterFont.micro)
            .foregroundStyle(palette.quaternaryText)
    }
}
