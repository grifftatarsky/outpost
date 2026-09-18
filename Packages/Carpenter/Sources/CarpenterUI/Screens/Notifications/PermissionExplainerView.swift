import CarpenterKit
import SwiftUI

public struct PermissionExplainerView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    public enum Kind: Sendable {
        case notifications
        case photos
    }

    private let kind: Kind
    private let onContinue: () -> Void
    private let onDecline: (() -> Void)?

    public init(_ kind: Kind, onContinue: @escaping () -> Void, onDecline: (() -> Void)? = nil) {
        self.kind = kind
        self.onDecline = onDecline
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: symbol)
                            .font(.system(size: 40))
                            .foregroundStyle(palette.accentColor)
                            .accessibilityHidden(true)
                        title
                            .font(CarpenterFont.largeTitle)
                            .foregroundStyle(palette.primaryText)
                            .multilineTextAlignment(.center)
                            .heading()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    asked
                        .font(CarpenterFont.rowDetail)
                        .foregroundStyle(palette.primaryText)
                } header: {
                    Text("What is asked", bundle: .module).sectionHeading()
                }
                .groupedRowSurface()

                Section {
                    refused
                        .font(CarpenterFont.rowDetail)
                        .foregroundStyle(palette.primaryText)
                } header: {
                    Text("If you say no", bundle: .module).sectionHeading()
                }
                .groupedRowSurface()
            }
            .scrollContentBackground(.hidden)

            VStack(spacing: 10) {
                Button {
                    dismiss()
                    onContinue()
                } label: {
                    continueLabel.primaryAction()
                }
                .prominentActionButton()

                if let onDecline {
                    Button {
                        dismiss()
                        onDecline()
                    } label: {
                        Text("Not now", bundle: .module)
                    }
                    .quietActionButton()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(palette.background)
    }

    private var symbol: String {
        switch kind {
        case .notifications: "bell.badge"
        case .photos: "photo.on.rectangle"
        }
    }

    private var title: Text {
        switch kind {
        case .notifications: Text("Notifications", bundle: .module)
        case .photos: Text("Photos", bundle: .module)
        }
    }

    private var continueLabel: Text {
        switch kind {
        case .notifications: Text("Continue", bundle: .module)
        case .photos: Text("Choose a photo", bundle: .module)
        }
    }

    private var asked: Text {
        switch kind {
        case .notifications:
            Text(
                "This app asks to show a banner when somebody writes to you, and to put a count on its icon. Nothing from anybody but the people you have let in, no news, and nothing sold to anybody. You choose which of it you actually want on the next screen and under Notifications.",
                bundle: .module)
        case .photos:
            Text(
                "This app never asks for your photo library. The picker you are about to see belongs to the system: it shows your library to you, and hands this app only the photos and clips you choose. Nothing else is read, and there is no setting to grant.",
                bundle: .module)
        }
    }

    private var refused: Text {
        switch kind {
        case .notifications:
            Text(
                "Messages still arrive, every time you open the app. They just do not announce themselves, and the icon shows no count. You can turn this on later under Notifications.",
                bundle: .module)
        case .photos:
            Text(
                "Close the picker and nothing is sent. There is nothing to refuse, because nothing was requested.",
                bundle: .module)
        }
    }
}

#if DEBUG
    #Preview("Notifications, explained") {
        PermissionExplainerView(.notifications, onContinue: {})
            .themed(.default)
    }

    #Preview("Photos, explained") {
        PermissionExplainerView(.photos, onContinue: {})
            .themed(.default)
    }
#endif
