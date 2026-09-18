import CarpenterKit
import SwiftUI

struct FormattedText: View {
    @Environment(\.palette) private var palette

    let source: String
    var font: Font = CarpenterFont.postBody

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        Self.attributed(PostFormatting.runs(in: source), palette: palette, font: font)
    }

    static func attributed(
        _ runs: [PostFormatting.Run], palette: Palette, font: Font = CarpenterFont.postBody
    ) -> AttributedString {
        var output = AttributedString()

        for run in runs {
            var piece = AttributedString(run.text)
            var resolved = font
            var intent: InlinePresentationIntent = []

            if run.traits.contains(.bold) {
                resolved = resolved.bold()
                intent.insert(.stronglyEmphasized)
            }
            if run.traits.contains(.italic) {
                resolved = resolved.italic()
                intent.insert(.emphasized)
            }

            piece.font = resolved
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }

            if run.traits.contains(.underline) {
                piece.foregroundColor = palette.accentColor
                piece.underlineStyle = Text.LineStyle(
                    pattern: .solid, color: palette.accentColor.opacity(0.35))
            }

            output.append(piece)
        }

        markTags(in: &output, palette: palette)
        return output
    }

    static let tagScheme = "carpenter-tag"

    private static func markTags(in text: inout AttributedString, palette: Palette) {
        let plain = String(text.characters)
        for occurrence in PostTags.occurrences(in: plain) {
            let lower = text.index(
                text.startIndex,
                offsetByCharacters: plain.distance(from: plain.startIndex, to: occurrence.range.lowerBound))
            let upper = text.index(
                text.startIndex,
                offsetByCharacters: plain.distance(from: plain.startIndex, to: occurrence.range.upperBound))
            text[lower..<upper].foregroundColor = palette.accentColor
            if let url = URL(string: "\(tagScheme)://\(PostTags.canonical(occurrence.tag))") {
                text[lower..<upper].link = url
            }
        }
    }

    static func runs(of attributed: AttributedString) -> [PostFormatting.Run] {
        attributed.runs.map { run in
            var traits: PostFormatting.Traits = []
            let intent = attributed[run.range].inlinePresentationIntent ?? []

            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            if attributed[run.range].underlineStyle != nil { traits.insert(.underline) }

            return PostFormatting.Run(
                text: String(attributed[run.range].characters), traits: traits)
        }
    }
}

#Preview("Formatted text") {
    VStack(alignment: .leading, spacing: 12) {
        FormattedText(source: "Plain, **bold**, *italic*, and __underlined__ together.")
        FormattedText(source: "**Bold with *italic* inside.**")
        FormattedText(source: "Nothing here: 2 * 3 is 6, and **this never closes")
    }
    .padding()
    .themed(.default)
}
