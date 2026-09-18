import CarpenterKit
import SwiftUI

struct OutpostReviewPrompt: View {
    @Environment(\.palette) private var palette

    let review: OutpostReview
    let onReview: () -> Void
    let onLater: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "person.2.badge.key.fill")
                    .foregroundStyle(palette.secondaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        "^[\(review.undecided.count) person](inflect: true) here can't see your Outpost",
                        bundle: .module
                    )
                    .font(CarpenterFont.rowTitle)
                    .foregroundStyle(palette.primaryText)

                    explanation
                        .font(CarpenterFont.footnote)
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button { Task { await onLater() } } label: {
                    Text("Later", bundle: .module)
                        .frame(minWidth: CarpenterMetrics.hitTarget, minHeight: CarpenterMetrics.hitTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .tint(palette.secondaryActionLabel)
                Button(action: onReview) {
                    Text("Review", bundle: .module)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accentFill)
            }
            .font(CarpenterFont.footnote)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(palette.fieldFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }

    private var explanation: Text {
        let base = Text(
            "That is the default, and it stays that way until you choose otherwise.",
            bundle: .module)
        let allowed = review.alreadyAllowed
        guard !allowed.isEmpty else { return base }

        if allowed.count == 1, let only = allowed.first {
            if let decidedIn = only.decidedIn {
                return Text(
                    "\(base) \(only.member.displayName) already has access from \(decidedIn) and keeps it.",
                    bundle: .module)
            }
            return Text(
                "\(base) \(only.member.displayName) already has access and keeps it.", bundle: .module)
        }
        let names = allowed.map(\.member.displayName).formatted(.list(type: .and))
        return Text("\(base) \(names) already have access and keep it.", bundle: .module)
    }
}

#if DEBUG
    #Preview("59 Access review, prompt") {
        VStack {
            OutpostReviewPrompt(
                review: OutpostReview(
                    room: RoomID(),
                    roomName: "Zeppelin Enthusiasts",
                    people: [
                        OutpostReview.Person(member: Fixtures.hastur, grant: nil),
                        OutpostReview.Person(member: Fixtures.camilla, grant: nil),
                        OutpostReview.Person(
                            member: Fixtures.cassilda,
                            grant: OutpostAccess.Grant(), decidedIn: "The Gazette"),
                    ]),
                onReview: {}, onLater: {})
            Spacer()
        }
        .themed(.default)
    }
#endif
