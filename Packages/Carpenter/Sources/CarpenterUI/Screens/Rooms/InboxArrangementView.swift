import CarpenterKit
import SwiftUI

public struct InboxArrangementView: View {
    @Environment(\.palette) private var palette

    @Binding private var arrangement: InboxArrangement

    public init(arrangement: Binding<InboxArrangement>) {
        _arrangement = arrangement
    }

    public var body: some View {
        List {
            Section {
                ForEach(InboxArrangement.allCases, id: \.self) { option in
                    ChoiceRow(
                        title: Text(option.title),
                        detail: Text(option.detail),
                        isSelected: option == arrangement,
                        action: { arrangement = option }
                    ) {
                        picture(option)
                    }
                }
            } footer: {
                // COPY BEGIN f0cf8d6d [NEEDS HUMAN REVIEW]
                Text(
                    "Nothing moves except the dock and the lists. No conversation is renamed, nothing is re-sent, and no message changes hands.",
                    bundle: .module
                )
                .fixedSize(horizontal: false, vertical: true)
                // COPY END f0cf8d6d
            }
            .groupedRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        // COPY BEGIN c81094d8 [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("Inbox", bundle: .module))
        // COPY END c81094d8
        .toolbarTitleDisplayMode(.inline)
    }

    private func picture(_ option: InboxArrangement) -> some View {
        let tabs: [(String, Bool)] =
            option == .split
            ? [("bubble.left", true), ("bubble.left.and.bubble.right", false),
               ("rectangle.stack", false), ("person.crop.circle", false)]
            : [("bubble.left", true), ("rectangle.stack", false), ("person.crop.circle", false)]

        return VStack(spacing: 6) {
            HStack(spacing: 5) {
                ForEach(0..<(option == .split ? 2 : 1), id: \.self) { _ in
                    VStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule()
                                .fill(palette.neutralFill)
                                .frame(height: 4)
                        }
                    }
                }
            }
            .frame(height: 22, alignment: .top)

            HStack(spacing: 4) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { _, tab in
                    Image(systemName: tab.0)
                        .font(.system(size: 9))
                        .foregroundStyle(tab.1 ? palette.accentColor : palette.quaternaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 5)
            .background(palette.neutralFill, in: .capsule)
        }
        .padding(8)
        .frame(width: 116)
        .background(palette.background, in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}

extension InboxArrangement {
    // COPY BEGIN fcd48ebc [NEEDS HUMAN REVIEW]
    var shortTitle: LocalizedStringKey {
        switch self {
        case .split: "Split"
        case .merged: "Merged"
        }
    }
    // COPY END fcd48ebc

    // COPY BEGIN 049ed353 [NEEDS HUMAN REVIEW]
    var title: LocalizedStringResource {
        switch self {
        case .split: .module("Solos and Rooms apart")
        case .merged: .module("One list")
        }
    }
    // COPY END 049ed353

    // COPY BEGIN 2a51478b [NEEDS HUMAN REVIEW]
    var detail: LocalizedStringResource {
        switch self {
        case .split:
            .module("Two tabs. People you talk to one to one are kept away from the group rooms.")
        case .merged:
            .module("One tab, newest first. A group is marked by a second disc behind its avatar.")
        }
    }
    // COPY END 2a51478b
}

#if DEBUG
    private struct InboxArrangementPreview: View {
        @State private var arrangement = InboxArrangement.split

        var body: some View {
            NavigationStack { InboxArrangementView(arrangement: $arrangement) }
        }
    }

    #Preview("Inbox arrangement — dark") {
        InboxArrangementPreview().themed(.cobalt).preferredColorScheme(.dark)
    }

    #Preview("Inbox arrangement — light") {
        InboxArrangementPreview().themed(.verdigris).preferredColorScheme(.light)
    }
#endif
