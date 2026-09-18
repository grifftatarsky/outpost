import CarpenterKit
import SwiftUI

public struct VerificationPhrase: View {
    public enum Size: Sendable {
        case display
        case inline
    }

    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize

    private let phrase: String
    private let size: Size

    public init(_ phrase: String, size: Size = .display) {
        self.phrase = phrase
        self.size = size
    }

    /// Long phrases are read aloud, and twenty unbroken characters are read aloud badly. Five at a
    /// time is what people already do with anything they dictate.
    private static let group = 5

    private var grouped: String {
        guard phrase.count > Self.group * 2 else { return phrase }
        return stride(from: 0, to: phrase.count, by: Self.group)
            .map { start in
                let from = phrase.index(phrase.startIndex, offsetBy: start)
                let to = phrase.index(from, offsetBy: min(Self.group, phrase.count - start))
                return String(phrase[from..<to])
            }
            .joined(separator: " ")
    }

    public var body: some View {
        switch size {
        case .display:
            VStack(spacing: 8) {
                Text("^[Read these \(phrase.count) character](inflect: true) aloud", bundle: .module)
                    .sectionHeading()
                    .foregroundStyle(palette.secondaryText)

                characters
                    .font(.system(.largeTitle, design: .monospaced, weight: .semibold))
                    .tracking(phrase.count > 12 ? 2 : 6)
                    .foregroundStyle(palette.primaryText)
                    .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.4)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.center)
            }
        case .inline:
            characters
                .font(.system(.footnote, design: .monospaced, weight: .semibold))
                .tracking(2)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.6)
        }
    }

    @ViewBuilder
    private var characters: some View {
        switch size {
        case .display:
            Text(verbatim: grouped)
                .textSelection(.enabled)
                .spokenCharacterByCharacter(phrase)
        case .inline:
            Text(verbatim: grouped)
                .spokenCharacterByCharacter(phrase)
        }
    }
}

/// What stands where the phrase will be, before the other person has opened the invitation.
///
/// There is genuinely nothing to show yet: the phrase is derived from a nonce the joiner reveals
/// only after this invitation was signed, which is what leaves the inviter nothing to grind with.
/// So this is a real wait, not a spinner over work already done.
public struct VerificationPhrasePending: View {
    @Environment(\.palette) private var palette

    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            Text("The characters are not ready yet", bundle: .module)
                .sectionHeading()
                .foregroundStyle(palette.secondaryText)

            Text(
                "They appear once the other person opens this invitation. Neither of you can see them before that, which is what stops anybody working them out in advance.",
                bundle: .module
            )
            .font(CarpenterFont.footnote)
            .foregroundStyle(palette.tertiaryText)
            .multilineTextAlignment(.center)
        }
    }
}

#if DEBUG
    #Preview("The characters") {
        VStack(spacing: 32) {
            VerificationPhrase("K9F4V9TR2M")
            VerificationPhrase("K9F4V9TR2MBX7HQ4NJ5W")
            VerificationPhrase("K9F4V9TR2M", size: .inline)
            VerificationPhrasePending()
        }
        .padding()
        .themed(.default)
    }
#endif
