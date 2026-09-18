import CarpenterKit
import SwiftUI

struct SyncStatusRow: View {
    @Environment(\.palette) private var palette

    let line: String?

    var body: some View {
        if let line {
            Text(line)
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.quaternaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 40)
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

extension View {
    func syncStatus(_ line: String?) -> some View {
        safeAreaInset(edge: .top, spacing: 0) { SyncStatusRow(line: line) }
    }
}
