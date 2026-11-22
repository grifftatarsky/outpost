import CarpenterKit
import SwiftUI

struct JoinCheckCard: View {
    @Environment(\.palette) private var palette

    let join: PendingJoin
    let onDecide: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                PersonAvatarView(member: join.joiner, diameter: CarpenterMetrics.roomAvatar)
                VStack(alignment: .leading, spacing: 2) {
                    Text(join.joiner.displayName)
                        .font(CarpenterFont.rowTitle)
                        .foregroundStyle(palette.primaryText)
                    // COPY BEGIN 94193b69 [NEEDS HUMAN REVIEW]
                    join.isAlreadyIn
                        ? Text("Joined on your invitation", bundle: .module)
                            .font(CarpenterFont.rowDetail)
                            .foregroundStyle(palette.secondaryText)
                        : Text("Invited by \(join.inviter.displayName)", bundle: .module)
                            .font(CarpenterFont.rowDetail)
                            .foregroundStyle(palette.secondaryText)
                    // COPY END 94193b69

                    // COPY BEGIN 03e0ade6 [NEEDS HUMAN REVIEW]
                    if !join.isAlreadyIn, !join.isIndefinite {
                        Text(
                            "Runs out \(join.expiresAt.formatted(.relative(presentation: .named)))",
                            bundle: .module)
                            .font(CarpenterFont.rowDetail)
                            .foregroundStyle(palette.tertiaryText)
                    }
                    // COPY END 03e0ade6
                }
            }

            VerificationPhrase(join.phrase)
                .frame(maxWidth: .infinity)

            // COPY BEGIN ec2f3dc1 [NEEDS HUMAN REVIEW]
            join.isAlreadyIn
                ? Text(
                    "You invited them, and this room lets anybody in on an invitation — so nobody was asked to approve and they are already here. This is the one check nothing else does: the same characters were shown to both of you, so if theirs match, the person who joined is the person you meant to invite. If they do not, somebody else used your invitation. Saying so stops you sending them the room's key from now on; it does not remove them, and only you are asked.",
                    bundle: .module
                )
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)
                : Text(
                    "Admit them only if the characters on their screen match these. Admitting them gives them everything this room has ever held, including what was said before today.",
                    bundle: .module
                )
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)
            // COPY END ec2f3dc1

            // COPY BEGIN 129eb001 [NEEDS HUMAN REVIEW]
            if !join.refusedBy.isEmpty {
                Label {
                    Text(
                        "\(ListFormatter.localizedString(byJoining: join.refusedBy.map(\.displayName))) already refused.",
                        bundle: .module
                    )
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)
            }
            // COPY END 129eb001

            HStack(spacing: 10) {
                Button {
                    onDecide(false)
                } label: {
                    // COPY BEGIN cbfa08f3 [NEEDS HUMAN REVIEW]
                    (join.isAlreadyIn
                        ? Text("Does not match", bundle: .module)
                        : Text("Refuse", bundle: .module))
                        .primaryAction()
                    // COPY END cbfa08f3
                }
                .quietActionButton()

                // COPY BEGIN f427f1b3 [NEEDS HUMAN REVIEW]
                Button {
                    onDecide(true)
                } label: {
                    (join.isAlreadyIn
                        ? Text("They match", bundle: .module)
                        : Text("Admit", bundle: .module)).primaryAction()
                }
                .prominentActionButton()
                // COPY END f427f1b3
            }
        }
        .padding(16)
        .background(
            palette.elevatedSurface,
            in: .rect(cornerRadius: CarpenterMetrics.cardRadius, style: .continuous))
    }
}
