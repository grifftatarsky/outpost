import CarpenterKit
import SwiftUI

struct HeldRestorePrompt: View {
    @Environment(\.palette) private var palette

    let held: HeldRestore
    let onLetThrough: () async -> Void
    let onRefuse: () async -> Void

    @State private var deciding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "hand.raised.fingers.spread.fill")
                    .foregroundStyle(palette.secondaryText)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(held.personName) set up a new device", bundle: .module)
                        .font(CarpenterFont.rowTitle)
                        .foregroundStyle(palette.primaryText)

                    Text(
                        "It asked you for what was said here before. You chose to hold that until you have checked, so none of it has gone. Read the characters below to each other on a line you trust. Anything said from now on still reaches them — they are still in this conversation.",
                        bundle: .module)
                        .font(CarpenterFont.footnote)
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let phrase = held.phrase {
                VerificationPhrase(phrase)
            }

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button {
                    deciding = true
                    Task {
                        await onRefuse()
                        deciding = false
                    }
                } label: {
                    Text("Don't send", bundle: .module)
                }
                .buttonStyle(.borderless)
                .tint(palette.destructive)
                Button {
                    deciding = true
                    Task {
                        await onLetThrough()
                        deciding = false
                    }
                } label: {
                    Text("Confirmed", bundle: .module)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accentFill)
            }
            .font(CarpenterFont.footnote)
            .disabled(deciding)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(palette.fieldFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }
}
