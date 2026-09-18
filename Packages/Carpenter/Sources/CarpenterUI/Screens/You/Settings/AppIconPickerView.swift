import CarpenterKit
import SwiftUI

public struct AppIconPickerView: View {
    @Environment(\.palette) private var palette

    @Binding private var choice: AppIconChoice
    private let isSupported: Bool

    public init(choice: Binding<AppIconChoice>, isSupported: Bool = true) {
        _choice = choice
        self.isSupported = isSupported
    }

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 16)]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !isSupported {
                    Text(
                        "Choosing an icon works on iPhone and iPad. On a Mac the app keeps the one it was built with.",
                        bundle: .module
                    )
                    .font(CarpenterFont.footnote)
                    .foregroundStyle(palette.secondaryText)
                }

                ForEach(AppIconChoice.Mark.allCases, id: \.self) { mark in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(mark.displayName)
                            .sectionHeading()
                            .foregroundStyle(palette.secondaryText)

                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(AppIconChoice.all(in: mark), id: \.self) { option in
                                Button {
                                    choice = option
                                } label: {
                                    tile(option)
                                }
                                .buttonStyle(.plain)
                                .disabled(!isSupported)
                            }
                        }
                    }
                }

                Text(
                    "The icon is separate from the color you picked for the app. They do not have to match.",
                    bundle: .module
                )
                .font(CarpenterFont.caption)
                .foregroundStyle(palette.quaternaryText)
            }
            .padding(.horizontal, CarpenterMetrics.screenMargin)
            .padding(.vertical, 16)
        }
        .background(palette.background)
        .navigationTitle(Text("App icon", bundle: .module))
    }

    private func tile(_ option: AppIconChoice) -> some View {
        VStack(spacing: 8) {
            preview(option)
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .strokeBorder(
                            choice == option ? palette.accentColor : edge(option),
                            lineWidth: choice == option ? 3 : 1)
                }

            Text(option.displayName)
                .font(CarpenterFont.caption)
                .foregroundStyle(
                    choice == option ? palette.primaryText : palette.secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(option.spokenName))
        .accessibilityAddTraits(choice == option ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private func preview(_ option: AppIconChoice) -> some View {
        #if canImport(UIKit)
            if let image = UIImage(named: option.previewAssetName) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
        #elseif canImport(AppKit)
            if let image = NSImage(named: option.previewAssetName) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
        #else
            placeholder
        #endif
    }

    private func edge(_ option: AppIconChoice) -> Color {
        switch option.ground {
        case .white: Color.black.opacity(0.35)
        case .black: Color.white.opacity(0.35)
        case .accent: .clear
        }
    }

    private var placeholder: some View {
        palette.neutralFill.overlay {
            Image(systemName: "app.dashed")
                .font(.title)
                .foregroundStyle(palette.tertiaryText)
        }
    }
}

#Preview("App icons") {
    @Previewable @State var choice = AppIconChoice.antennaCobalt
    NavigationStack { AppIconPickerView(choice: $choice) }
        .themed(.default)
}
