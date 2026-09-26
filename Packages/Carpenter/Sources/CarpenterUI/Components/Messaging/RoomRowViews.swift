import CarpenterKit
import SwiftUI

public struct RoomBadge: View {
    @Environment(\.palette) private var palette

    private let diameter: CGFloat
    private let symbol: String

    public init(diameter: CGFloat = 21, symbol: String = "pin.fill") {
        self.diameter = diameter
        self.symbol = symbol
    }

    public var body: some View {
        Circle()
            .fill(palette.accentFill)
            .frame(width: diameter, height: diameter)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: diameter * 0.5, weight: .semibold))
                    .foregroundStyle(palette.textOnSentBubble)
            }
            .overlay {
                Circle().strokeBorder(palette.background, lineWidth: diameter * 0.12)
            }
            .accessibilityHidden(true)
    }
}

public struct RoomAvatar: View {
    @Environment(\.palette) private var palette

    private let initials: String
    private let diameter: CGFloat
    private let isAccented: Bool
    private let isPinned: Bool
    private let isGroup: Bool
    private let isSilenced: Bool

    public init(
        initials: String, diameter: CGFloat, isAccented: Bool, isPinned: Bool,
        isGroup: Bool = false, isSilenced: Bool = false, image: Image? = nil
    ) {
        self.initials = initials
        self.diameter = diameter
        self.isAccented = isAccented
        self.isPinned = isPinned
        self.isGroup = isGroup
        self.isSilenced = isSilenced
        self.image = image
    }

    private let image: Image?

    private static let stackOffset: CGFloat = 0.18

    private var frontDiameter: CGFloat {
        isGroup ? diameter / (1 + Self.stackOffset) : diameter
    }

    private var ringWidth: CGFloat { max(1.5, frontDiameter * 0.06) }

    public var body: some View {
        avatar
            .overlay(alignment: .topLeading) {
                if isSilenced {
                    RoomBadge(diameter: diameter * 0.4, symbol: "moon.fill")
                        .offset(x: -diameter * 0.06, y: -diameter * 0.06)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isPinned {
                    RoomBadge(diameter: diameter * 0.4)
                        .offset(x: diameter * 0.06, y: diameter * 0.06)
                }
            }
    }

    @ViewBuilder
    private var avatar: some View {
        if isGroup {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(palette.avatarFillSwatch.over(palette.backgroundSwatch).color)
                    .frame(width: frontDiameter, height: frontDiameter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                AvatarView(initials: initials, diameter: frontDiameter, isAccented: isAccented)
                    .background { Circle().fill(palette.background).padding(-ringWidth) }
            }
            .frame(width: diameter, height: diameter)
        } else {
            AvatarView(initials: initials, diameter: diameter, isAccented: isAccented, image: image)
        }
    }

}

public struct TagFilterRail: View {
    @Environment(\.palette) private var palette

    private let tags: [RoomTag]
    private let managed: [ManagedTag]
    @Binding private var selection: TagID?

    public init(tags: [RoomTag], managed: [ManagedTag] = [], selection: Binding<TagID?>) {
        self.tags = tags
        self.managed = managed
        _selection = selection
    }

    public var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                // COPY BEGIN a55c04d7 [NEEDS HUMAN REVIEW]
                pill(
                    title: Text("All", bundle: .module),
                    titleText: String(localized: "All", bundle: .module),
                    isSelected: selection == nil
                ) {
                    selection = nil
                }
                // COPY END a55c04d7

                ForEach(managed) { tag in
                    pill(
                        title: ManagedTagCopy.name(of: tag.kind),
                        titleText: ManagedTagCopy.plainName(of: tag.kind),
                        isSelected: selection == tag.id,
                        isManaged: true
                    ) {
                        selection = selection == tag.id ? nil : tag.id
                    }
                }

                ForEach(tags) { tag in
                    pill(
                        title: Text(tag.name.value), titleText: tag.name.value,
                        isSelected: selection == tag.id
                    ) {
                        selection = selection == tag.id ? nil : tag.id
                    }
                }
            }
            .padding(.horizontal, CarpenterMetrics.screenMargin)
            .padding(.bottom, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func pill(
        title: Text, titleText: String, isSelected: Bool, isManaged: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                title
                if isSelected, selection != nil {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isSelected ? palette.textOnSentBubble : palette.neutralText)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .frame(minHeight: 30)
            .background {
                if isSelected {
                    Capsule().fill(palette.accentFill)
                } else if isManaged {
                    Capsule()
                        .fill(palette.neutralFill)
                        .overlay(
                            Capsule()
                                .strokeBorder(palette.fieldBorder, lineWidth: CarpenterMetrics.hairline))
                } else {
                    Capsule().strokeBorder(palette.fieldBorder, lineWidth: CarpenterMetrics.hairline)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        // COPY BEGIN 808807a3 [NEEDS HUMAN REVIEW]
        .accessibilityHint(
            isManaged
                ? Text("Kept up to date by the app. It goes when nothing is waiting.", bundle: .module)
                : Text(verbatim: ""))
        .accessibilityLabel(
            isManaged
                ? Text("\(titleText), kept by the app", bundle: .module)
                : Text(verbatim: titleText))
        // COPY END 808807a3
    }
}

// COPY BEGIN eee6fec6 [NEEDS HUMAN REVIEW]
public enum ManagedTagCopy {
    public static func name(of kind: ManagedTagKind) -> Text {
        switch kind {
        case .invited: return Text("Invited", bundle: .module)
        }
    }

    public static func plainName(of kind: ManagedTagKind) -> String {
        switch kind {
        case .invited: return String(localized: "Invited", bundle: .module)
        }
    }
}
// COPY END eee6fec6

public struct TagFilterMenu: View {
    @Environment(\.palette) private var palette

    private let tags: [RoomTag]
    private let managed: [ManagedTag]
    @Binding private var selection: TagID?

    public init(tags: [RoomTag], managed: [ManagedTag] = [], selection: Binding<TagID?>) {
        self.tags = tags
        self.managed = managed
        _selection = selection
    }

    private var activeName: String? {
        selection.flatMap { id in tags.first { $0.id == id }?.name.value }
    }

    public var body: some View {
        Menu {
            // COPY BEGIN 31d0c409 [NEEDS HUMAN REVIEW]
            Picker(selection: $selection) {
                Text("All rooms", bundle: .module).tag(TagID?.none)
                ForEach(managed) { tag in
                    ManagedTagCopy.name(of: tag.kind).tag(TagID?.some(tag.id))
                }
                ForEach(tags) { tag in
                    Text(tag.name.value).tag(TagID?.some(tag.id))
                }
            } label: {
                Text("Filter by tag", bundle: .module)
            }
            .pickerStyle(.inline)
            // COPY END 31d0c409
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selection == nil ? "line.3.horizontal.decrease" : "tag.fill")
                    .font(.caption.weight(.semibold))
                // COPY BEGIN 6e3c76f3 [NEEDS HUMAN REVIEW]
                Group {
                    if let activeName {
                        Text(activeName)
                    } else {
                        Text("All", bundle: .module)
                    }
                }
                .font(.footnote.weight(.semibold))
                // COPY END 6e3c76f3
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(selection == nil ? palette.neutralText : palette.textOnSentBubble)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background {
                if selection == nil {
                    Capsule().strokeBorder(palette.fieldBorder, lineWidth: CarpenterMetrics.hairline)
                } else {
                    Capsule().fill(palette.accentFill)
                }
            }
        }
        // COPY BEGIN cc2f10d2 [NEEDS HUMAN REVIEW]
        .accessibilityLabel(Text("Filter by tag", bundle: .module))
        // COPY END cc2f10d2
    }
}

public struct TagChip: View {
    @Environment(\.palette) private var palette

    private let title: String
    private let isPlaceholder: Bool

    public init(title: String, isPlaceholder: Bool = false) {
        self.title = title
        self.isPlaceholder = isPlaceholder
    }

    public var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isPlaceholder ? palette.tertiaryText : palette.neutralText)
            .padding(.horizontal, 8)
            .frame(height: 19)
            .background {
                if isPlaceholder {
                    Capsule()
                        .strokeBorder(
                            palette.tertiaryText,
                            style: StrokeStyle(lineWidth: CarpenterMetrics.hairline, dash: [3, 2]))
                } else {
                    Capsule().fill(palette.badgeFill)
                }
            }
    }
}

public struct RoomMarks: View {
    @Environment(\.palette) private var palette

    private let isSilenced: Bool
    private let isPinned: Bool
    private let isAwaitingSomebody: Bool

    public init(isSilenced: Bool, isPinned: Bool, isAwaitingSomebody: Bool = false) {
        self.isSilenced = isSilenced
        self.isPinned = isPinned
        self.isAwaitingSomebody = isAwaitingSomebody
    }

    public var body: some View {
        HStack(spacing: 5) {
            // COPY BEGIN 8f41ec3f [NEEDS HUMAN REVIEW]
            if isSilenced {
                Image(systemName: "moon.fill")
                    .accessibilityLabel(Text("Silenced", bundle: .module))
            }
            if isPinned {
                Image(systemName: "pin.fill")
                    .accessibilityLabel(Text("Pinned", bundle: .module))
            }
            if isAwaitingSomebody {
                Image(systemName: "person.crop.circle.badge.clock")
                    .accessibilityLabel(Text("Somebody invited, not yet in", bundle: .module))
            }
            // COPY END 8f41ec3f
        }
        .font(.caption2)
        .foregroundStyle(palette.accentColor)
    }
}
