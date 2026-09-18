import SwiftUI

public struct ChoiceRow<Sample: View>: View {
    @Environment(\.palette) private var palette

    private let title: Text
    private let detail: Text?
    private let isSelected: Bool
    private let action: () -> Void
    private let sample: Sample

    public init(
        title: Text,
        detail: Text? = nil,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder sample: () -> Sample = { EmptyView() }
    ) {
        self.title = title
        self.detail = detail
        self.isSelected = isSelected
        self.action = action
        self.sample = sample()
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                words
                sample
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var words: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                title.foregroundStyle(palette.primaryText)
                if let detail {
                    detail
                        .font(CarpenterFont.rowDetail)
                        .foregroundStyle(palette.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.accentColor)
                .opacity(isSelected ? 1 : 0)
                .accessibilityHidden(true)
        }
    }
}

#if DEBUG
    #Preview("Choice rows") {
        List {
            Section {
                ChoiceRow(
                    title: Text(verbatim: "Room, sender and message"),
                    detail: Text(verbatim: "Anyone who can see your lock screen can read it."),
                    isSelected: true,
                    action: {})
                ChoiceRow(
                    title: Text(verbatim: "Room only"),
                    detail: Text(verbatim: "They see which conversation is moving."),
                    isSelected: false,
                    action: {})
            }
            .groupedRowSurface()
        }
        .themed(.cobalt)
        .preferredColorScheme(.dark)
    }
#endif
