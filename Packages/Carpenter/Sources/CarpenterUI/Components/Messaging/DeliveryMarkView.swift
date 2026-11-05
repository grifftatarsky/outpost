import CarpenterKit
import SwiftUI

struct DeliveryGlyph: View {
    enum Kind {
        case plane(filled: Bool)
        case eye(filled: Bool)
        case eyeThatWillNeverOpen
        case nobodyToSendItTo
    }

    @Environment(\.palette) private var palette

    private let kind: Kind
    private let size: CGFloat

    init(_ kind: Kind, size: CGFloat) {
        self.kind = kind
        self.size = size
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
    }

    private var symbol: String {
        switch kind {
        case .plane(let filled): filled ? "paperplane.fill" : "paperplane"
        case .eye(let filled): filled ? "eye.fill" : "eye"
        case .eyeThatWillNeverOpen: "eye.slash"
        case .nobodyToSendItTo: "person.slash"
        }
    }

    private var color: Color {
        switch kind {
        case .plane(let lit), .eye(let lit): lit ? palette.accentColor : palette.unlitMark
        case .eyeThatWillNeverOpen, .nobodyToSendItTo: palette.quaternaryText
        }
    }
}

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
                        DeliveryGlyph(.nobodyToSendItTo, size: box)
                    } else {
                        DeliveryGlyph(.plane(filled: delivery.isCollected), size: box)
                        DeliveryGlyph(
                            delivery.reportingIsOff ? .eyeThatWillNeverOpen : .eye(filled: delivery.wasDisplayed),
                            size: box)
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

    // COPY BEGIN 31325a06 [NEEDS HUMAN REVIEW]
    var spoken: Text {
        guard isEdited else { return label }
        let edited = Text("Edited.", bundle: .module)
        guard delivery.isVisible else { return edited }
        return Text("\(edited) \(label)", bundle: .module)
    }
    // COPY END 31325a06

    var label: Text {
        // COPY BEGIN c562b6b2 [NEEDS HUMAN REVIEW]
        switch delivery {
        case .pending:
            return Text(verbatim: "")
        case .sent:
            return Text("Sent. Not collected yet.", bundle: .module)
        case .noRecipients:
            return Text(
                "Saved. There is nobody in this room to send it to yet — it will go when somebody joins.",
                bundle: .module)
        case .notCollected:
            return notCollectedLabel
        case .delivered:
            return Text("Collected. Not yet shown.", bundle: .module)
        case .notReported:
            return Text(
                "Collected. This person does not report when a message is shown.", bundle: .module)
        case .displayed(let at):
            return Text(
                "Collected. Shown \(RelativeTimestampFormatter().readReceipt(at)).", bundle: .module)
        }
        // COPY END c562b6b2
    }

    // COPY BEGIN 2c05bd49 [NEEDS HUMAN REVIEW]
    private var notCollectedLabel: Text {
        Text(
            "Not collected by everybody within ^[\(NotGone.takenBackAfterDays) day](inflect: true). The copy that was waiting was taken back from your iCloud.",
            bundle: .module)
    }
    // COPY END 2c05bd49
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

// COPY BEGIN 07a47466 [NEEDS HUMAN REVIEW]
struct EditedMark: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Text("Edited", bundle: .module)
            .font(CarpenterFont.micro)
            .foregroundStyle(palette.quaternaryText)
    }
}
// COPY END 07a47466
