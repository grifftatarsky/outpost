import CarpenterKit
import SwiftUI

struct RefusedCheck<Actions: View>: View {
    enum Placement {
        case screen
        case notice
    }

    @Environment(\.palette) private var palette

    let placement: Placement
    let readings: Text
    let protection: Text
    let nextStep: Text?
    let phrase: String?
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: placement == .screen ? 18 : 12) {
            // COPY BEGIN b3d7e2d2 [NEEDS HUMAN REVIEW]
            AdaptiveStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle")
                    .font(placement == .screen ? .title2 : .body)
                    .foregroundStyle(palette.destructive)
                    .accessibilityHidden(true)

                Text("The characters did not match", bundle: .module)
                    .font(placement == .screen ? CarpenterFont.rowTitle : CarpenterFont.rowTitle)
                    .foregroundStyle(palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
            }
            // COPY END b3d7e2d2

            readings
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            protection
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let phrase {
                VerificationPhrase(phrase)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, placement == .screen ? 4 : 0)
            }

            if let nextStep {
                nextStep
                    .font(CarpenterFont.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actions
        }
    }
}
