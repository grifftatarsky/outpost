import CarpenterKit
import SwiftUI

struct ComposerNotice<Actions: View>: View {
    @Environment(\.palette) private var palette

    let symbol: String?
    let headline: Text
    let detail: Text
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdaptiveStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.body)
                        .foregroundStyle(palette.secondaryText)
                        .accessibilityHidden(true)
                }
                headline
                    .font(CarpenterFont.rowTitle)
                    .foregroundStyle(palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
            }

            detail
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            actions
        }
        .padding(.horizontal, CarpenterMetrics.screenMargin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.elevatedSurface)
    }
}

extension ComposerNotice where Actions == EmptyView {
    init(symbol: String?, headline: Text, detail: Text) {
        self.init(symbol: symbol, headline: headline, detail: detail) { EmptyView() }
    }
}
