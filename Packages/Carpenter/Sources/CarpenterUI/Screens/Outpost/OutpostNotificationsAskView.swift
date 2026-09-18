import CarpenterKit
import SwiftUI

public struct OutpostNotificationsAskView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let onAnswer: (Bool) async -> Void

    @State private var answering = false

    public init(onAnswer: @escaping (Bool) async -> Void) {
        self.onAnswer = onAnswer
    }

    public var body: some View {
        SettingsPage {
                Section {
                    SettingsHeaderCard(
                        icon: "rectangle.stack.badge.person.crop.fill",
                        title: Text("Your Outposts", bundle: .module),
                        paragraph: Text(
                            "An Outpost is somebody's own page, which you can read if they let you in. Would you like to hear about what happens on them?",
                            bundle: .module))
                }
                .groupedRowSurface()

                Section {
                    Label {
                        Text("When somebody comments on your posts", bundle: .module)
                    } icon: {
                        Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            .foregroundStyle(palette.accentColor)
                    }
                    Label {
                        Text("When somebody answers a post you commented on", bundle: .module)
                    } icon: {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .foregroundStyle(palette.accentColor)
                    }
                    Label {
                        Text("When an Outpost you have turned on has something new", bundle: .module)
                    } icon: {
                        Image(systemName: "rectangle.stack.fill")
                            .foregroundStyle(palette.accentColor)
                    }
                } header: {
                    Text("What you would be told", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "Reactions are left off either way: a tap is not somebody writing to you, and you can turn them on later if you want them.",
                        bundle: .module)
                }
                .groupedRowSurface()
            }
        .listSurfaceHidden()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    answering = true
                    Task {
                        await onAnswer(true)
                        dismiss()
                    }
                } label: {
                    Text("Yes, tell me", bundle: .module).primaryAction()
                }
                .prominentActionButton()
                .disabled(answering)

                Button {
                    answering = true
                    Task {
                        await onAnswer(false)
                        dismiss()
                    }
                } label: {
                    Text("Not for now", bundle: .module)
                }
                .quietActionButton()
                .disabled(answering)

                Text(
                    "Either way, you can choose exactly what you hear about under You, Notifications, Outposts.",
                    bundle: .module)
                    .font(CarpenterFont.caption)
                    .foregroundStyle(palette.tertiaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle(Text("Outposts", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
    }
}
