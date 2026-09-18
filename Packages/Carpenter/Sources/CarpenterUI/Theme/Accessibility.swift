import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif
#if canImport(AppKit)
    import AppKit
#endif

extension View {
    func barIconLargeContent(_ title: Text, systemImage: String) -> some View {
        accessibilityShowsLargeContentViewer {
            Label {
                title
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }

    @ViewBuilder
    public func sectionHeading() -> some View {
        #if os(macOS)
            accessibilityAddTraits(.isHeader)
        #else
            font(CarpenterFont.sectionLabel)
                .accessibilityAddTraits(.isHeader)
        #endif
    }

    public func heading() -> some View {
        accessibilityAddTraits(.isHeader)
    }
}

public struct PrimaryActionStyle: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(CarpenterFont.button)
            .frame(maxWidth: CarpenterMetrics.readableWidth)
            .frame(maxWidth: .infinity)
    }
}

public struct ProminentActionButton: ViewModifier {
    @Environment(\.palette) private var palette

    public func body(content: Content) -> some View {
        content
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(palette.accentFill)
    }
}

public struct DestructiveActionButton: ViewModifier {
    @Environment(\.palette) private var palette

    public func body(content: Content) -> some View {
        content
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(palette.destructiveFill)
    }
}

public struct QuietActionButton: ViewModifier {
    @Environment(\.palette) private var palette

    public func body(content: Content) -> some View {
        content
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(palette.accentColor)
            .foregroundStyle(palette.secondaryActionLabel)
    }
}

extension View {
    public func primaryAction() -> some View {
        modifier(PrimaryActionStyle())
    }

    public func prominentActionButton() -> some View {
        modifier(ProminentActionButton())
    }

    public func destructiveActionButton() -> some View {
        modifier(DestructiveActionButton())
    }

    public func quietActionButton() -> some View {
        modifier(QuietActionButton())
    }

    public func fieldChrome(isFocused: Bool = false) -> some View {
        modifier(FieldChromeStyle(isFocused: isFocused))
    }
}

public struct PasteCodeButton: View {
    @Environment(\.palette) private var palette

    private let onPaste: (String) -> Void

    public init(onPaste: @escaping (String) -> Void) {
        self.onPaste = onPaste
    }

    @State private var nothingToPaste = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
        Button {
            var pasted: String?
            #if canImport(UIKit) && !os(macOS)
                pasted = UIPasteboard.general.string
            #elseif canImport(AppKit)
                pasted = NSPasteboard.general.string(forType: .string)
            #endif
            if let pasted, !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                nothingToPaste = false
                onPaste(pasted)
            } else {
                nothingToPaste = true
            }
        } label: {
            Label {
                Text("Paste", bundle: .module)
            } icon: {
                Image(systemName: "doc.on.clipboard")
            }
            .codeEntryButtonChrome()
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.primaryText)
        .haptic(.refusal, trigger: nothingToPaste ? 1 : 0)

        if nothingToPaste {
            Text("There is nothing to paste. Copy the code again, or type it in.", bundle: .module)
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        }
    }
}

struct CodeEntryButtonChrome: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .font(CarpenterFont.button)
            .frame(maxWidth: .infinity, minHeight: CarpenterMetrics.buttonHeight)
            .background(
                palette.neutralFill,
                in: .rect(cornerRadius: CarpenterMetrics.buttonRadius, style: .continuous))
    }
}

extension View {
    func codeEntryButtonChrome() -> some View {
        modifier(CodeEntryButtonChrome())
    }
}

public struct FieldChromeStyle: ViewModifier {
    @Environment(\.palette) private var palette

    let isFocused: Bool

    public func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .frame(minHeight: CarpenterMetrics.fieldMinHeight)
            .background(
                palette.fieldFill,
                in: .rect(cornerRadius: CarpenterMetrics.fieldRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: CarpenterMetrics.fieldRadius, style: .continuous
                )
                .strokeBorder(
                    isFocused ? palette.accentColor : palette.fieldBorder,
                    lineWidth: isFocused
                        ? CarpenterMetrics.fieldFocusedBorderWidth
                        : CarpenterMetrics.fieldBorderWidth
                )
            }
    }
}

public struct GroupedRowSurface: ViewModifier {
    @Environment(\.palette) private var palette

    public func body(content: Content) -> some View {
        #if os(macOS)
            content
        #else
            content
                .listRowBackground(palette.contentSurface)
                .environment(\.avatarGround, .contentSurface)
        #endif
    }
}

extension View {
    public func groupedRowSurface() -> some View {
        modifier(GroupedRowSurface())
    }
}
