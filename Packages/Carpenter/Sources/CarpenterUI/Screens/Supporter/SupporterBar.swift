import CarpenterKit
import SwiftUI

struct SupporterBar: View {
    @Environment(\.palette) private var palette

    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(palette.accentFill, .white)
                    .font(.system(size: 30, weight: .semibold))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Become a Supporter", bundle: .module)
                        .font(.headline)
                    Text("**One Year Free** for TestFlight users", bundle: .module)
                        .font(.subheadline)
                        .opacity(0.9)
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.accentFill, in: .rect(cornerRadius: 22, style: .continuous))
            .contentShape(.rect(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("The Supporter bar") {
    SupporterBar {}
        .padding()
        .themed(.default)
}
