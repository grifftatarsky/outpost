import CarpenterKit
import SwiftUI

struct AwaitingRow: View {
    @Environment(\.palette) private var palette

    let admission: AwaitingAdmission
    let diameter: CGFloat

    var body: some View {
        PersonRow(
            name: admission.invitedBy.displayName,
            initials: admission.invitedBy.initials,
            id: admission.invitedBy.id,
            detail: admission.hasLapsed && !admission.isIndefinite
                ? Text(
                    "Invited you. The invitation has run out — ask them to send another.",
                    bundle: .module)
                : Text("Invited you", bundle: .module),
            diameter: diameter
        ) {
            if let phrase = admission.phrase {
                VerificationPhrase(phrase, size: .inline)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            admission.hasLapsed && !admission.isIndefinite
                ? Text(
                    "\(admission.invitedBy.displayName) invited you. The invitation has run out — ask them to send another. The characters to check are \(spoken).",
                    bundle: .module)
                : Text(
                    "\(admission.invitedBy.displayName) invited you. Waiting to be let in. The characters to check are \(spoken).",
                    bundle: .module))
    }

    private var spoken: String {
        (admission.phrase ?? "").map(String.init).joined(separator: ", ")
    }
}
