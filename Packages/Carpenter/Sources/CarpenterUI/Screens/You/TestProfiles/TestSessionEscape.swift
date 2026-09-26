#if DEBUG

    import CarpenterKit
    import SwiftUI

    public struct TestSessionEscape: View {
        @Environment(\.palette) private var palette

        private let name: String
        private let leave: @MainActor () async -> Void

        @State private var leaving = false

        public init(name: String, leave: @escaping @MainActor () async -> Void) {
            self.name = name
            self.leave = leave
        }

        public var body: some View {
            HStack(spacing: 12) {
                Image(systemName: "testtube.2")
                    .foregroundStyle(palette.accentColor)
                    .accessibilityHidden(true)
                // COPY BEGIN bdbbd438 [NEEDS HUMAN REVIEW]
                VStack(alignment: .leading, spacing: 1) {
                    Text("Test profile", bundle: .module)
                        .font(CarpenterFont.caption)
                        .foregroundStyle(palette.tertiaryText)
                    Text(verbatim: name)
                        .font(CarpenterFont.rowDetail)
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button {
                    leaving = true
                    Task {
                        await leave()
                        leaving = false
                    }
                } label: {
                    Text("Back to iCloud", bundle: .module)
                }
                .buttonStyle(.glass)
                .disabled(leaving)
                // COPY END bdbbd438
            }
            .padding(.horizontal, CarpenterMetrics.screenMargin)
            .padding(.vertical, 8)
        }
    }

#endif
