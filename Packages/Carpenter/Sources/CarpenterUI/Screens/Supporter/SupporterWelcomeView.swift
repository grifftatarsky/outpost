import CarpenterKit
import SwiftUI

struct SupporterWelcomeView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverIsOn

    let owner: Member
    let ownAvatar: Image?
    let onShowBadge: (Bool) async -> Void

    @State private var asking = false
    @State private var answering = false
    @AccessibilityFocusState private var readingThanks: Bool
    @AccessibilityFocusState private var readingQuestion: Bool

    var body: some View {
        NavigationStack {
            thanks
                .navigationDestination(isPresented: $asking) { badgeQuestion }
        }
    }

    private var thanks: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "party.popper.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(palette.accentColor)
                    .font(.system(size: 96))
                    .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 0.6)), isActive: !reduceMotion)
                    .padding(.top, 32)
                    .accessibilityHidden(true)

                Text("You’re a Supporter", bundle: .module)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(palette.primaryText)
                    .multilineTextAlignment(.center)
                    .heading()
                    .accessibilityFocused($readingThanks)

                Text(
                    "Thank you for testing. Your year is free, and it starts on the day the app is released on the App Store.",
                    bundle: .module)
                    .font(.title3)
                    .foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 18) {
                    point(
                        "hammer.fill",
                        Text(
                            "Supporters pay for the time it takes to build what comes next. First up are Packs: extras you add to a conversation, starting with shared lists.",
                            bundle: .module))
                    point(
                        "person.2.fill",
                        Text(
                            "A Pack you turn on works for everyone in that conversation. Your friends won’t need to be Supporters to use it with you.",
                            bundle: .module))
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .fixedSize(horizontal: false, vertical: true)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button {
                asking = true
            } label: {
                Text("Continue", bundle: .module).primaryAction()
            }
            .prominentActionButton()
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(palette.background.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text("Close", bundle: .module)
                }
            }
        }
        .onAppear { announce($readingThanks) }
    }

    private func announce(_ focus: AccessibilityFocusState<Bool>.Binding) {
        guard voiceOverIsOn else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            focus.wrappedValue = true
        }
    }

    private func point(_ symbol: String, _ words: Text) -> some View {
        Label {
            words
                .font(.body)
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(palette.accentColor)
        }
    }

    private var badgeQuestion: some View {
        ScrollView {
            VStack(spacing: 20) {
                AvatarView(initials: owner.initials, diameter: 112, isAccented: true, image: ownAvatar)
                    .supporterBadge(true, onAvatarOf: 112)
                    .padding(.top, 32)

                Text("Show the Supporter badge?", bundle: .module)
                    .font(.title.weight(.bold))
                    .foregroundStyle(palette.primaryText)
                    .multilineTextAlignment(.center)
                    .heading()
                    .accessibilityFocused($readingQuestion)

                Text(
                    "A small mark on your picture. Everyone in your conversations sees it, and so does anyone who can read your Outpost.",
                    bundle: .module)
                    .font(.body)
                    .foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .fixedSize(horizontal: false, vertical: true)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    answer(true)
                } label: {
                    Text("Show the badge", bundle: .module).primaryAction()
                }
                .prominentActionButton()

                Button {
                    answer(false)
                } label: {
                    Text("Not now", bundle: .module)
                }
                .quietActionButton()

                Text("You can change this under You, Supporter.", bundle: .module)
                    .font(CarpenterFont.caption)
                    .foregroundStyle(palette.tertiaryText)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            .disabled(answering)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(palette.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(answering)
        .onAppear { announce($readingQuestion) }
    }

    private func answer(_ shows: Bool) {
        answering = true
        Task {
            await onShowBadge(shows)
            dismiss()
        }
    }
}

#Preview("Welcoming a Supporter") {
    SupporterWelcomeView(owner: Member(id: Identity.generate().id, displayName: "Griff"), ownAvatar: nil) { _ in }
        .themed(.default)
}
