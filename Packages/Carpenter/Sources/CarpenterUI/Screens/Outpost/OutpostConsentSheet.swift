import CarpenterKit
import SwiftUI

public struct OutpostConsentSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let onAnswer: (OutpostConsent) async -> Void

    @State private var declining = false

    public init(onAnswer: @escaping (OutpostConsent) async -> Void) {
        self.onAnswer = onAnswer
    }

    public var body: some View {
        NavigationStack {
            List {
                SettingsHeaderCard(
                    icon: "bubble.left.and.text.bubble.right.fill",
                    title: Text("Before you join in", bundle: .module),
                    paragraph: Text(
                        "An Outpost is somebody's own page. They decide who reads it — and everybody who can read a post can read every comment underneath it.",
                        bundle: .module))

                Section {
                    point(
                        icon: "person.2.fill",
                        title: Text("Some readers are people you have not met", bundle: .module),
                        detail: Text(
                            "If two people are let in to the same Outpost, they read each other's comments there. Neither of them had to agree to that, and neither is told who the other is.",
                            bundle: .module))
                    point(
                        icon: "questionmark.circle.fill",
                        title: Text("They see one anonymous person", bundle: .module),
                        detail: Text(
                            "Your name, your picture and everything else about you stay off a comment anybody unmet reads. Every unmet person is drawn as the same single figure, so there is nothing to follow from one thread to the next.",
                            bundle: .module))
                    point(
                        icon: "heart.fill",
                        title: Text("A reaction is only a number", bundle: .module),
                        detail: Text(
                            "Somebody who has not met you never sees that you reacted at all — their post counts it and nothing more.",
                            bundle: .module))
                    point(
                        icon: "text.quote",
                        title: Text("The words are the words", bundle: .module),
                        detail: Text(
                            "What you write is read exactly as you wrote it. Anonymous is not private: keep out of a comment anything you would not hand to a stranger — where you live, where you work, who else is in the room.",
                            bundle: .module))
                }
                .groupedRowSurface()

                Section {
                } footer: {
                    Text(
                        "Your own Outpost is not affected either way. You choose who reads it, one person at a time, and this is only about the posts other people write.",
                        bundle: .module)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .safeAreaInset(edge: .bottom) { decision }
            .navigationTitle(Text("How comments travel", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
            .confirmationDialog(
                Text("What would you rather do?", bundle: .module),
                isPresented: $declining, titleVisibility: .visible
            ) {
                Button(role: .destructive) { Task { await onAnswer(.off) } } label: {
                    Text("Turn Outposts off", bundle: .module)
                }
                Button { Task { await onAnswer(.quiet) } } label: {
                    Text("Read only, write nothing", bundle: .module)
                }
                Button(role: .cancel) { declining = false } label: {
                    Text("Cancel", bundle: .module)
                }
            } message: {
                Text(
                    "Read only keeps the tab and takes away commenting and reacting on other people's posts. Turning Outposts off takes the tab away as well. Either can be changed later, under Your Outpost on the You page.",
                    bundle: .module)
            }
        }
        .animation(reduceMotion ? nil : .default, value: declining)
    }

    private var decision: some View {
        VStack(spacing: 8) {
            Button { Task { await onAnswer(.open) } } label: {
                Text("I understand", bundle: .module)
            }
            .prominentActionButton()

            Button { declining = true } label: {
                Text("Not for me", bundle: .module)
            }
            .quietActionButton()
        }
        .padding(.horizontal, CarpenterMetrics.screenMargin)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func point(icon: String, title: Text, detail: Text) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(icon, fill: palette.tileFill(.feature))
            VStack(alignment: .leading, spacing: 3) {
                title
                    .font(CarpenterFont.rowTitle)
                    .foregroundStyle(palette.primaryText)
                detail
                    .font(CarpenterFont.rowDetail)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview("How comments travel") {
        Color.clear.sheet(isPresented: .constant(true)) {
            OutpostConsentSheet(onAnswer: { _ in })
        }
        .themed(.default)
    }
#endif
