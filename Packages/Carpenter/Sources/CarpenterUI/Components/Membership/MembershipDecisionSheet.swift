import CarpenterKit
import SwiftUI

struct MembershipDecisionSheet<Facts: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let question: Text
    let context: Text
    let confirm: Text
    let onConfirm: () async -> Void
    @ViewBuilder let facts: Facts

    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        question
                            .font(CarpenterFont.largeTitle)
                            .foregroundStyle(palette.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        context
                            .font(CarpenterFont.footnote)
                            .foregroundStyle(palette.secondaryText)
                    }

                    VStack(alignment: .leading, spacing: 16) { facts }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }

            VStack(spacing: 10) {
                Button(role: .destructive) {
                    Task {
                        working = true
                        await onConfirm()
                        working = false
                        dismiss()
                    }
                } label: {
                    confirm.primaryAction()
                }
                .destructiveActionButton()
                .disabled(working)

                // COPY BEGIN 10d12958 [NEEDS HUMAN REVIEW]
                Button {
                    dismiss()
                } label: {
                    Text("Cancel", bundle: .module)
                        .font(CarpenterFont.button)
                        .foregroundStyle(palette.accentColor)
                        .frame(maxWidth: .infinity, minHeight: CarpenterMetrics.buttonHeight)
                }
                // COPY END 10d12958
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(palette.background)
    }
}

struct MembershipFact: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.palette) private var palette

    let symbol: String
    let text: Text

    init(_ symbol: String, _ text: Text) {
        self.symbol = symbol
        self.text = text
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            text
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                text
                    .font(CarpenterFont.footnote)
                    .foregroundStyle(palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
