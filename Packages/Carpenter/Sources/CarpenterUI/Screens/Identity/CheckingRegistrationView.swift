import SwiftUI

public struct CheckingRegistrationView: View {
    @Environment(\.palette) private var palette

    private let onNuke: (() async -> Void)?

    public init(onNuke: (() async -> Void)? = nil) {
        self.onNuke = onNuke
    }

    public var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            ProgressView()

            Text("Checking Keychain for existing registration.", bundle: .module)
                .font(CarpenterFont.rowDetail)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer(minLength: 0)

            if let onNuke {
                DebugNukeButton(action: onNuke)
                    .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
    }
}

#if DEBUG
    #Preview("Checking registration — dark") {
        CheckingRegistrationView().themed(.default).preferredColorScheme(.dark)
    }

    #Preview("Checking registration — light") {
        CheckingRegistrationView().themed(.default).preferredColorScheme(.light)
    }

    #Preview("Checking registration — with the way out") {
        CheckingRegistrationView(onNuke: {}).themed(.default).preferredColorScheme(.dark)
    }
#endif
