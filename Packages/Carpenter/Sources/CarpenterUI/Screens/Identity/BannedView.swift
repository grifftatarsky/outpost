import CarpenterKit
import SwiftUI

public struct BannedView: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL

    private let contact: URL?

    public init(contact: URL?) {
        self.contact = contact
    }

    public var body: some View {
        ZStack {
            palette.destructiveFill
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Image("BanMark", bundle: .module)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 150)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)

                Text(
                    "You have been detected as a user in the app's bundled abuse list. As such, you have been banned. If you believe this was in error, please send us a message.",
                    bundle: .module
                )
                .font(CarpenterFont.rowDetail)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                if let contact {
                    Button {
                        openURL(contact)
                    } label: {
                        Text("Send a message", bundle: .module)
                            .font(CarpenterFont.button)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 13)
                            .overlay {
                                Capsule().strokeBorder(
                                    .white, lineWidth: CarpenterMetrics.hairline * 2)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 32)
        }
    }
}

#if DEBUG
    #Preview("Banned") {
        BannedView(contact: URL(string: "https://example.com/contact"))
            .themed(.default)
    }

    #Preview("Banned, no way to write") {
        BannedView(contact: nil)
            .themed(.default)
    }
#endif
