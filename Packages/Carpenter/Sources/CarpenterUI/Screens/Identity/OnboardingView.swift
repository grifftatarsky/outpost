import CarpenterKit
import SwiftUI

public struct OnboardingView: View {
    @Environment(\.palette) private var palette

    private let createIdentity: (String) async -> String?
    private let redeemInvite: () -> Void
    private let restore: (() -> Void)?
    private let invitePending: Bool

    @State private var displayName = ""
    @State private var explaining = false
    @State private var problem: String?
    @State private var creating = false

    @FocusState private var naming: Bool

    public init(
        createIdentity: @escaping (String) async -> String?,
        redeemInvite: @escaping () -> Void,
        restore: (() -> Void)? = nil,
        invitePending: Bool = false
    ) {
        self.createIdentity = createIdentity
        self.redeemInvite = redeemInvite
        self.restore = restore
        self.invitePending = invitePending
    }

    private func create() {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !creating else { return }
        Task {
            creating = true
            problem = await createIdentity(name)
            creating = false
        }
    }

    public var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(palette.background.ignoresSafeArea())
        .sizedSheet(isPresented: $explaining) {
            HowItWorksView()
                .presentationDetents([.fraction(0.95)])
                .presentationDragIndicator(.visible)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 26) {
                OutpostMark(width: 260)

                VStack(spacing: 18) {
                    Text(
                        "Conversations should be owned by the people in them. With \(Branding.displayName), they are.",
                        bundle: .module
                    )
                    .font(.body)
                    .foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)

                    Button {
                        explaining = true
                    } label: {
                        Text("How this works", bundle: .module)
                            .font(CarpenterFont.footnote)
                            .underline()
                    }
                    .foregroundStyle(palette.secondaryText)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                if invitePending {
                    Text(
                        "Your invitation is waiting. Tell us what to call you and we will open it.",
                        bundle: .module
                    )
                    .font(CarpenterFont.footnote)
                    .foregroundStyle(palette.accentColor)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 2)
                }

                TextField(text: $displayName) {
                    Text("What your friends call you", bundle: .module)
                }
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(palette.primaryText)
                .multilineTextAlignment(.center)
                .focused($naming)
                .fieldChrome(isFocused: naming)
                .textContentType(.name)
                .submitLabel(.done)
                .onSubmit {
                    guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    else { return }
                    create()
                }
                .contentShape(.rect)
                .onTapGesture { if !naming { naming = true } }
                .onAppear { naming = true }

                Button(action: create) { 
                    Text("Create my identity", bundle: .module).primaryAction()
                }
                .prominentActionButton()
                .disabled(
                    creating || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let problem {
                    Text(problem)
                        .font(CarpenterFont.caption)
                        .foregroundStyle(palette.destructive)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                        .transition(.opacity)  // cross-fade only
                }

                Button(action: redeemInvite) {
                    Text("I have an invite", bundle: .module)
                        .font(CarpenterFont.button)
                        .foregroundStyle(palette.accentColor)
                        .frame(maxWidth: .infinity, minHeight: CarpenterMetrics.buttonHeight)
                        .background(
                            palette.elevatedSurface,
                            in: .rect(cornerRadius: CarpenterMetrics.buttonRadius, style: .continuous))
                }

                Text(
                    "Your keys are generated on this device and stored in your iCloud Keychain. \(Branding.displayName) has no account to sign in to.",
                    bundle: .module
                )
                .font(CarpenterFont.caption)
                .foregroundStyle(palette.quaternaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 6)

                if let restore {
                    Button(action: restore) {
                        Text("I have a recovery key", bundle: .module)
                            .font(CarpenterFont.caption)
                            .foregroundStyle(palette.tertiaryText)
                            .frame(maxWidth: .infinity, minHeight: CarpenterMetrics.hitTarget)
                    }
                    .padding(.top, 2)
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
    #Preview("01 Onboarding — dark") {
        OnboardingView(createIdentity: { _ in nil }, redeemInvite: {})
            .themed(.cobalt)
            .preferredColorScheme(.dark)
    }

    #Preview("01 Onboarding — light") {
        OnboardingView(createIdentity: { _ in nil }, redeemInvite: {})
            .themed(.oxblood)
            .preferredColorScheme(.light)
    }
#endif
