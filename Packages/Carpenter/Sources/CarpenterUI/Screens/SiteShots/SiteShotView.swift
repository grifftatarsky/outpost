#if DEBUG

    import CarpenterKit
    import SwiftUI

    public enum SiteShot: String, CaseIterable, Sendable {
        case rooms
        case conversation
        case outposts
        case you
        case supporter
        case verify
        case audience
        case checkup
        case notifications
        case photos

        public static let argument = "--site-shot"

        public static func requested(in arguments: [String] = ProcessInfo.processInfo.arguments)
            -> SiteShot?
        {
            guard let index = arguments.firstIndex(of: argument),
                index + 1 < arguments.count
            else { return nil }
            return SiteShot(rawValue: arguments[index + 1])
        }
    }

    public struct SiteShotView: View {
        private let shot: SiteShot
        @State private var theme = ThemeStore()

        public init(_ shot: SiteShot) {
            self.shot = shot
        }

        public var body: some View {
            switch shot {
            case .rooms: shell(.rooms)
            case .outposts: shell(.outposts)
            case .you:
                RootView.demo(
                    tab: .you,
                    supporter: SupporterSettings(
                        standing: .none, canClaim: true, showsBadge: false, onClaim: {},
                        onShowBadge: { _ in }))
            case .conversation: standalone { conversation }
            case .supporter: standalone { welcome }
            case .verify: standalone { verify }
            case .audience: standalone { audience }
            case .checkup: standalone { checkup }
            case .notifications: standalone { PermissionExplainerView(.notifications, onContinue: {}) }
            case .photos: standalone { PermissionExplainerView(.photos, onContinue: {}) }
            }
        }

        private func shell(_ tab: RootView.PhoneTab) -> some View {
            RootView.demo(tab: tab)
        }

        private func standalone(@ViewBuilder _ content: () -> some View) -> some View {
            content()
                .environment(\.clock, Fixtures.PreviewClock())
                .themed(theme.accent)
        }

        private var conversation: some View {
            NavigationStack {
                ConversationView(room: Fixtures.zeppelinEnthusiasts, messages: Fixtures.conversation)
            }
        }

        private var welcome: some View {
            SupporterWelcomeView(owner: Fixtures.cassilda, ownAvatar: nil) { _ in }
        }

        private var verify: some View {
            NavigationStack {
                WhoYouAreTalkingToView(
                    roomName: Fixtures.hangar7.name,
                    people: [
                        VerifiedPerson(
                            person: Fixtures.cassilda, phrase: nil, confirmedAt: nil, isViewer: true,
                            isFounder: true),
                        VerifiedPerson(
                            person: Fixtures.hastur, phrase: "K9F4V9TR2M",
                            confirmedAt: Fixtures.ago(days: 1)),
                        VerifiedPerson(
                            person: Fixtures.camilla, phrase: "BX7HQ4NJ5W",
                            confirmedAt: Fixtures.ago(days: 6)),
                        VerifiedPerson(person: Fixtures.yhtill, phrase: nil, confirmedAt: nil),
                    ])
            }
        }

        private var audience: some View {
            var access = OutpostAccess()
            access.allow(
                Fixtures.hastur.id,
                stamp: OrganisationStamp(at: .distantPast, device: DeviceID(rawValue: Data([1]))))
            return NavigationStack {
                OutpostAudienceView(people: [Fixtures.hastur, Fixtures.camilla], access: access)
            }
        }

        private var checkup: some View {
            PrivacyCheckupView(
                owner: Fixtures.cassilda, current: .lockedDown, onFinish: { _ in }, onSkip: {})
        }
    }

    #Preview("Site shot — the inbox") {
        SiteShotView(.rooms)
    }

    #Preview("Site shot — who you are talking to") {
        SiteShotView(.verify)
    }

#endif
