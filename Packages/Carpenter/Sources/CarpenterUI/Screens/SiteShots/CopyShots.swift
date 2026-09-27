#if DEBUG

    import CarpenterKit
    import SwiftUI

    public enum CopyShot: String, CaseIterable, Sendable {
        case youSupporter = "you-supporter"
        case supporterClaimed = "supporter-claimed"
        case supporterWaiting = "supporter-waiting"
        case supporterEnded = "supporter-ended"
        case roomsHelp = "rooms-help"
        case roomsAwaiting = "rooms-awaiting"
        case photoRequests = "photo-requests"
        case outpostConsent = "outpost-consent"
        case outpostNotificationsAsk = "outpost-notifications-ask"
        case postReactions = "post-reactions"
        case conversationRepair = "conversation-repair"
        case conversationHeldRestore = "conversation-held-restore"
        case lockLocked = "lock-locked"
        case lockWrong = "lock-wrong"
        case lockErasing = "lock-erasing"
        case lockRecovery = "lock-recovery"
        case lockSetup = "lock-setup"

        public static let argument = "--copy-shot"

        public static func requested(in arguments: [String] = ProcessInfo.processInfo.arguments) -> CopyShot? {
            guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
            return CopyShot(rawValue: arguments[index + 1])
        }
    }

    public struct CopyShotView: View {
        private let shot: CopyShot
        @State private var theme = ThemeStore()

        public init(_ shot: CopyShot) {
            self.shot = shot
        }

        public var body: some View {
            content
                .environment(\.clock, Fixtures.PreviewClock())
                .themed(theme.accent)
        }

        @ViewBuilder
        private var content: some View {
            switch shot {
            case .youSupporter:
                RootView.demo(tab: .you, supporter: Self.supporter(.testFlightYear(endsAt: Self.yearFromNow)))
            case .supporterClaimed:
                NavigationStack { SupporterView(settings: Self.supporter(.testFlightYear(endsAt: Self.yearFromNow))) }
            case .supporterWaiting:
                NavigationStack { SupporterView(settings: Self.supporter(.testFlightYear(endsAt: nil))) }
            case .supporterEnded:
                NavigationStack { SupporterView(settings: Self.supporter(.none)) }
            case .roomsHelp:
                RootView.demo(tab: .rooms).environment(\.showsHelp, true)
            case .roomsAwaiting:
                RootView.demo(
                    tab: .rooms,
                    awaiting: [
                        AwaitingAdmission(
                            room: RoomID(), invitedBy: Fixtures.hastur, phrase: "K9F4V9TR2M",
                            confirmedAt: Fixtures.ago(minutes: 20), expiresAt: Fixtures.now.addingTimeInterval(3_600)),
                        AwaitingAdmission(
                            room: RoomID(), invitedBy: Fixtures.camilla, phrase: nil,
                            confirmedAt: Fixtures.ago(days: 3), expiresAt: Fixtures.ago(days: 1), hasLapsed: true),
                    ])
            case .photoRequests:
                NavigationStack { Color.clear }
                    .sheet(isPresented: .constant(true)) {
                        PhotoRequestsView(onShow: { _ in })
                            .environment(\.photoRequests, Self.requests)
                    }
            case .outpostConsent:
                OutpostConsentSheet(onAnswer: { _ in })
            case .outpostNotificationsAsk:
                OutpostNotificationsAskView(onAnswer: { _ in })
            case .postReactions:
                PostReactionsSheet(reactions: [("🎈", 4), ("🔥", 2), ("😂", 1)], mine: "🎈")
            case .conversationRepair:
                NavigationStack {
                    ConversationView(
                        room: Fixtures.zeppelinEnthusiasts, transcript: Fixtures.conversation.map(TranscriptEntry.message),
                        repair: Self.repair, onDismissRepair: {})
                }
            case .conversationHeldRestore:
                NavigationStack {
                    ConversationView(
                        room: Fixtures.zeppelinEnthusiasts, transcript: Fixtures.conversation.map(TranscriptEntry.message),
                        heldRestore: HeldRestore(
                            request: RepairID(), person: Fixtures.hastur.id, personName: "Hastur",
                            room: Fixtures.zeppelinEnthusiasts.id, roomName: Fixtures.zeppelinEnthusiasts.name,
                            phrase: "K9F4V9TR2M", askedAt: Fixtures.ago(minutes: 5)),
                        onLetHistoryThrough: { _ in }, onRefuseHistory: { _ in })
                }
            case .lockLocked:
                LockShot(wrongTries: 0, eraseAfter: nil)
            case .lockWrong:
                LockShot(wrongTries: 2, eraseAfter: nil)
            case .lockErasing:
                LockShot(wrongTries: 2, eraseAfter: 5)
            case .lockRecovery:
                LockShot(wrongTries: 0, eraseAfter: nil, recovering: true)
            case .lockSetup:
                NavigationStack { AppLockSetupView(biometricName: "Face ID", onLock: { _ in true }, onNotNow: {}) }
            }
        }

        private static var yearFromNow: Date { Fixtures.now.addingTimeInterval(365 * 86_400) }

        private static func supporter(_ standing: SupporterStanding) -> SupporterSettings {
            SupporterSettings(
                standing: standing, canClaim: false, showsBadge: standing.isSupporter, onClaim: {},
                onShowBadge: { _ in })
        }

        private static var requests: PhotoRequestsHelp {
            PhotoRequestsHelp(
                requests: [Fixtures.hastur, Fixtures.camilla].enumerated().map { index, person in
                    PhotoRequest(
                        person: person, sender: Fixtures.cassilda.id,
                        media: MediaAttachment(
                            reference: AttachmentReference(
                                id: AttachmentID(), key: Data(count: 32), digest: Data(count: 32), byteCount: 1),
                            kind: .image, width: 4, height: 3, preview: nil),
                        message: Fixtures.fixtureMessageID(index), room: Fixtures.zeppelinEnthusiasts.id,
                        askedAt: Fixtures.ago(hours: index + 1))
                },
                onSend: { _ in nil }, onDismiss: { _ in })
        }

        private static var repair: HistoryRepairStatus {
            HistoryRepairStatus(
                id: RepairID(), room: Fixtures.zeppelinEnthusiasts.id, startedAt: Fixtures.ago(minutes: 3),
                asked: [Fixtures.hastur, Fixtures.yhtill], answered: [Fixtures.hastur], waiting: [Fixtures.yhtill],
                recovered: 12, stillMissing: 4, heldByNobodyAsked: 0, sentButNotArrived: 4, unverifiable: 0)
        }
    }

    private struct LockShot: View {
        let wrongTries: Int
        let eraseAfter: Int?
        var recovering = false
        @State private var controller = AppLockController(store: AppLockStore(keychain: ShotKeychain()), biometrics: ShotBiometrics())

        var body: some View {
            Group {
                if recovering {
                    NavigationStack { RecoveryKeyUnlockView(controller: controller) }
                } else {
                    AppLockScreen(controller: controller)
                }
            }
            .task {
                await controller.load()
                if let eraseAfter { _ = await controller.setEraseAfter(eraseAfter) }
                for _ in 0..<wrongTries { await controller.unlock(with: "000000") }
            }
        }
    }

    private struct ShotBiometrics: Biometrics {
        var name: String? { "Face ID" }
        func state() -> Data? { Data([1]) }
        func evaluate(reason: String) async -> Bool { false }
    }

    private actor ShotKeychain: KeychainStore {
        private var stored: Data?
        func data(for key: KeychainKey) throws -> Data? {
            if let stored { return stored }
            return try JSONEncoder().encode(try AppLock.make("123456", as: .digits, usesBiometrics: false, rounds: 1))
        }
        func set(_ data: Data, for key: KeychainKey, scope: KeychainScope) throws { stored = data }
        func remove(_ key: KeychainKey) throws { stored = nil }
        func removeAll() throws { stored = nil }
    }

#endif
