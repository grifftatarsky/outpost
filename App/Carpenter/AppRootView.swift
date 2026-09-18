import CarpenterApp
import CarpenterCloudKit
import CarpenterKeychain
import CloudKit
import CarpenterKit
import CarpenterMedia
import CarpenterUI
import OSLog
import Intents
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

struct AppRootView: View {
    private static var becameActive: Notification.Name {
        #if os(macOS)
            NSApplication.didBecomeActiveNotification
        #else
            UIApplication.didBecomeActiveNotification
        #endif
    }

    @State var redeeming = false
    @State var restoring = false

    @State var sheetPreferences = RoomsListPreferences()
    @State var arrivingInvite: String?
    @State var arrivingCode: ArrivingCode?
    @AppStorage("onboarding.tourSeen") var tourSeen = false
    @AppStorage("onboarding.syncedSplashSeen") var syncedSplashSeen = false
    @State var syncing = false
    @State var syncAgain = false
    @State var lastRendezvous = Date.distantPast
    @State var lastSync = Date.distantPast
    @State var mediaBytes: Int?
    @Environment(\.scenePhase) private var scenePhase
    @State var cloudTrouble: String?
    @State var deviceSync: CloudKitEntrySync?
    @State var startedSyncFor: DeviceID?
    @State var messagePushArmed = false
    @State var openRoom: RoomID?

    @State var session = AppSession(storage: .onDisk(), clock: UITestMode.clock)

    @State var problem: ActionProblem?

    let cloud = CloudKitMailbox(
        container: .default(),
        directory: PeerZoneDirectory(store: AppRootView.mailboxDirectoryStore()))
    #if DEBUG
        let rig = FileMailbox.fromLaunchArguments()
    #endif

    var mailbox: any Mailbox {
        #if DEBUG
            if let rig { return rig }
        #endif
        return cloud
    }

    var accountRegistry: any AccountRegistry {
        #if DEBUG
            if rig != nil { return RigAccount() }
        #endif
        return CloudKitEntrySync(
            container: .default(),
            device: DeviceID(rawValue: Data()),
            stateStore: FileDocumentStore(url: Self.registrationProbeURL))
    }

    var media: any MediaMailbox {
        #if DEBUG
            if let rig { return rig }
        #endif
        return cloud
    }

    @State var safety = SafetyPreferences()
    @State var privacyNote = false
    @State var pretendedFocus: Bool?
    @State var mediaLoader: MediaLoader?
    @State var ownAvatar: Image?
    @State var personAvatars: [ParticipantID: Image] = [:]
    @State var sharedAvatars: [ParticipantID: Image] = [:]
    @State var distribution: DistributionChannel?
    @State var outpostAvatars: [ParticipantID: Image] = [:]
    @State var ownOutpostAvatar: Image?
    @State var unfetchablePhotos: Set<AttachmentID> = []
    @State var screening: ScreeningAvailability = .unsupported
    @AppStorage("explained.notifications") var notificationsExplained = false
    @State var explainingNotifications = false
    @State var notificationsAllowed: Bool?
    @State var askingOutpostNotifications = false

    var debugActions: DebugActions? {
        #if DEBUG
            DebugActions(
                checkMailbox: { await checkMailbox() },
                rotateMailboxShare: { await rotateMailboxShare() },
                pretendFocus: { silenced in
                    pretendedFocus = silenced ? true : nil
                    await session.reportFocus(silenced: silenced)
                })
        #else
            nil
        #endif
    }

    var body: some View {
        content
            .alert(
                Text(problem?.title ?? ""),
                isPresented: Binding(
                    get: { problem != nil },
                    set: { showing in if !showing { problem = nil } }),
                presenting: problem
            ) { _ in
                Button { problem = nil } label: { Text("OK") }
            } message: { problem in
                Text(problem.detail)
            }
    }

    struct ActionProblem: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
    }

    func reporting(_ log: String, _ action: () async throws -> Void) async -> String? {
        do {
            try await action()
            return nil
        } catch {
            Diagnostics.identity.error(
                "\(log, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            return SessionProblem.sentence(for: error)
        }
    }

    func attempting(
        _ title: String, _ log: String, _ action: () async throws -> Void
    ) async {
        do {
            try await action()
        } catch {
            Diagnostics.identity.error(
                "\(log, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            problem = ActionProblem(title: title, detail: SessionProblem.sentence(for: error))
        }
    }

    var screen: some View {
        Group {
            switch RootScreen.for(session.state) {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .checkingForRegistration:
                #if DEBUG
                    CheckingRegistrationView(onNuke: { await nuke() })
                        .themed(.default)
                #else
                    CheckingRegistrationView()
                        .themed(.default)
                #endif

            case .registrationStalled(let why):
                Group {
                    #if DEBUG
                        RegistrationStalledView(
                            stall: why,
                            onRetry: { await session.retryRegistration() },
                            onRestore: { restoring = true },
                            onNuke: { await nuke() }
                        )
                    #else
                        RegistrationStalledView(
                            stall: why,
                            onRetry: { await session.retryRegistration() },
                            onRestore: { restoring = true }
                        )
                    #endif
                }
                .themed(.default)
                .sheet(isPresented: $restoring) {
                    NavigationStack {
                        RestoreFromKeyView(restore: { key, asksPeers, afterALoss in
                            await reporting("restore from a recovery key") {
                                try await session.restore(
                                    fromRecoveryKey: key, askingPeers: asksPeers,
                                    afterALoss: afterALoss)
                            }
                        })
                    }
                    .themed(.default)
                }

            case .onboarding(.newIdentity) where !tourSeen:
                WelcomeTourView { tourSeen = true }
                    .themed(.default)

            case .onboarding(.newIdentity):
                OnboardingView(
                    createIdentity: { name in
                        await reporting("create identity") {
                            try await session.createIdentity(displayName: name)
                        }
                    },
                    redeemInvite: { redeeming = true },
                    restore: { restoring = true },
                    invitePending: arrivingInvite != nil
                )
                .themed(.default)
                .sheet(isPresented: $restoring) {
                    NavigationStack {
                        RestoreFromKeyView(restore: { key, asksPeers, afterALoss in
                            await reporting("restore from a recovery key") {
                                try await session.restore(
                                    fromRecoveryKey: key, askingPeers: asksPeers,
                                    afterALoss: afterALoss)
                            }
                        })
                    }
                    .themed(.default)
                }

            case .onboarding(.nameOnly):
                OnboardingView(
                    createIdentity: { name in
                        await reporting("set display name") { try await session.setDisplayName(name) }
                    },
                    redeemInvite: { redeeming = true },
                    invitePending: arrivingInvite != nil
                )
                .themed(.default)

            case .ready where session.enrolment?.deviceIsNew == true && !syncedSplashSeen:
                DeviceSyncedView(
                    memberName: session.viewer.displayName,
                    arrival: session.cameBackFromARecoveryKey ? .recoveryKey : .keychain
                ) {
                    syncedSplashSeen = true
                }
                .themed(.default)

            case .ready where session.needsPrivacyCheckup:
                privacyCheckup

            case .ready:
                ready

            case .failed(let reason):
                ContentUnavailableView(
                    "Something is wrong with this device's data",
                    systemImage: "exclamationmark.triangle",
                    description: Text(reason)
                )
            }
        }
    }

    var content: some View {
        screen
        .environment(\.mediaLoader, mediaLoader)
        .environment(\.ownAvatar, ownAvatar)
        .environment(\.personAvatars, personAvatars)
        .environment(\.anonFace, session.anonPersona.face)
        .environment(\.sharedAvatars, sharedAvatars)
        .environment(\.outpostAvatars, outpostAvatars)
        .environment(\.ownOutpostAvatar, ownOutpostAvatar)
        .environment(\.viewerID, session.viewer.id)
        .environment(\.supporters, session.supporterBadges)
        .sheet(isPresented: $askingOutpostNotifications) {
            NavigationStack {
                OutpostNotificationsAskView { wanted in
                    await session.setOutpostNotifications(wanted ? .default : .none)
                }
            }
        }
        .sheet(isPresented: $explainingNotifications) {
            PermissionExplainerView(
                .notifications,
                onContinue: {
                    notificationsExplained = true
                    Task {
                        await PushRegistration.requestMessageAuthorization()
                        await readNotificationPermission()
                        if notificationsAllowed == true, !session.hasAnsweredOutpostNotifications {
                            askingOutpostNotifications = true
                        }
                    }
                })
                .interactiveDismissDisabled()
        }
        .onChange(of: safety.blocksKnownAbusers) { _, on in session.enforcesDenyList = on }
        .onChange(of: safety.blursEveryPhoto) { _, on in
            mediaLoader?.treatsEveryPhotoAsSensitive = on
        }
        .task {
            mediaLoader = makeMediaLoader()
            ownAvatar = Self.decodeAvatar(avatarStore.load())
            personAvatars = personAvatarStore.loadAll().compactMapValues { Self.decodeAvatar($0) }
            if session.showsOthersAvatars {
                sharedAvatars = personAvatarStore.loadAllPublished(.rooms)
                    .compactMapValues { Self.decodeAvatar($0) }
                outpostAvatars = personAvatarStore.loadAllPublished(.outpost)
                    .compactMapValues { Self.decodeAvatar($0) }
            }
            resolveOwnOutpostAvatar()
            screening = await SystemMediaScreen().availability()
            session.enforcesDenyList = safety.blocksKnownAbusers
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--reset-account") {
                    Diagnostics.identity.notice("launch: --reset-account given; clearing this account")
                    await attempting(
                        String(localized: "This account was not cleared"), "reset account"
                    ) { try await wipe() }
                    Diagnostics.identity.notice("launch: the account is cleared; stopping")
                    exit(0)
                }
                if ProcessInfo.processInfo.arguments.contains("--reset-device") {
                    Diagnostics.identity.notice("launch: --reset-device given; clearing this device")
                    await eraseThisDevice()
                    Diagnostics.identity.notice("launch: this device is cleared; stopping")
                    exit(0)
                }
            #endif

            await (mailbox as? CloudKitMailbox)?.restoreDirectory()

            session.checkAccount(with: accountRegistry)

            await session.load()
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--forget-supporter") {
                    await session.forgetSupporterYear()
                }
            #endif
            await session.settleRegistration()
            await session.nameThisDeviceIfUnnamed(HardwareName.ofThisDevice)
            startDeviceSync()

            var delay = 1
            while session.isWaitingForAnIdentity {
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { break }
                if await session.recheckForSyncedIdentity() { break }
                delay = min(delay * 2, 30)
            }
        }
        .onChange(of: session.state) { _, _ in startDeviceSync() }
        .task(id: session.state) { await settleDistribution() }
        .task { PushArrivals.shared.onArrival { await syncNow() } }
        .task {
            PushArrivals.shared.onOpenRoom { thread in
                switch session.tapping(thread, whileViewing: openRoom) {
                case .room(let room): openRoom = room
                case .theAppAsItStands:
                    Diagnostics.sync.notice("push: a banner opened the app without navigating")
                }
            }
        }
        .onOpenURL { url in take(url) }
        .onChange(of: session.state) { _, _ in openWhatArrived() }
        .onChange(of: openRoom) { _, room in
            PushDesk.viewing = room.map(MessageNotification.thread(for:))
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.becameActive)) { _ in
            Task {
                await session.recheckForSyncedIdentity()
                await syncNow()
            }
        }
        .onChange(of: badgeCount, initial: true) { _, count in
            Task { await PushRegistration.setBadge(count) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await session.recheckForSyncedIdentity()

                await syncNow()
                await reportFocusNow()
                await settleDistribution()
            }
        }
        .sheet(isPresented: $redeeming, onDismiss: { arrivingInvite = nil }) {
            RedeemInviteView(
                arriving: arrivingInvite,
                read: { code in
                    guard let invite = session.inspect(inviteCode: code) else { return nil }
                    return InviteOffer(
                        roomName: nil,
                        inviterName: nil,
                        phrase: session.phrase(for: invite.attestation) ?? "",
                        expiresAt: invite.attestation.expiresAt
                    )
                },
                accept: { code in
                    do {
                        let invite = try await session.redeem(inviteCode: code)
                        if let url = invite.mailbox {
                            try await CloudKitMailbox.accept(url, in: .default())
                            await (mailbox as? CloudKitMailbox)?.subscribeForInbox()
                        }
                        await syncNow()
                        return nil
                    } catch {
                        return SessionProblem.sentence(for: error)
                    }
                }
            )
            .themed(.default)
        }
        .sheet(item: $arrivingCode) { code in
            AddSomeoneView(
                rooms: { session.rooms.filter { !$0.isDirect } },
                code: code.value,
                onAdd: { room, joinerCode in
                    let url = try? await (mailbox as? CloudKitMailbox)?.shareURL()
                    do {
                        return try await session.invite(
                            joinerCode: joinerCode, joining: room, mailbox: url)
                    } catch {
                        Diagnostics.identity.error(
                            "invite failed: \(String(describing: error), privacy: .public)")
                        return nil
                    }
                },
                preferences: sheetPreferences,
                connections: session.connections(),
                onCreateRoom: { name, access, people in
                    await createRoom(named: name, access: access, inviting: people)
                }
            )
            .themed(.default)
        }
    }
    func createRoom(
        named name: String, access: RoomAccess, inviting people: Set<ParticipantID>
    ) async {
        let room: RoomID
        do {
            room = try await session.createRoom(named: name, access: access)
        } catch {
            Diagnostics.identity.error(
                "create room failed: \(String(describing: error), privacy: .public)")
            problem = ActionProblem(
                title: String(localized: "That room was not made"),
                detail: SessionProblem.sentence(for: error))
            return
        }
        await invite(people, to: room, kind: .room)
    }

    func startSolo(with person: ParticipantID) async -> Invite? {
        let room: RoomID
        do {
            room = try await session.startSolo(with: person)
        } catch {
            Diagnostics.identity.error(
                "start solo failed: \(String(describing: error), privacy: .public)")
            problem = ActionProblem(
                title: String(localized: "That solo was not started"),
                detail: SessionProblem.sentence(for: error))
            return nil
        }
        return await invite([person], to: room, kind: .solo)[person]
    }

    @discardableResult
    func invite(
        _ people: Set<ParticipantID>, to room: RoomID, kind: RoomKind
    ) async -> [ParticipantID: Invite] {
        guard !people.isEmpty else { return [:] }

        let url = try? await (mailbox as? CloudKitMailbox)?.shareURL()

        var missed: [String] = []
        var issued: [ParticipantID: Invite] = [:]
        for person in people.sorted(by: { $0.rawValue.lexicographicallyPrecedes($1.rawValue) }) {
            do {
                guard let keys = session.publicKeys(of: person) else {
                    throw AppSessionError.noIdentity
                }
                issued[person] = try await session.invite(
                    joinerCode: try keys.encoded(), joining: room, mailbox: url)
            } catch {
                Diagnostics.identity.error(
                    "invite failed while making a room: \(String(describing: error), privacy: .public)")
                missed.append(session.member(person).displayName)
            }
        }

        guard !missed.isEmpty else { return issued }
        problem = switch kind {
        case .room:
            ActionProblem(
                title: String(localized: "The room was made, but not everybody was invited"),
                detail: String(
                    localized:
                        "\(missed.formatted(.list(type: .and))) were not invited. Open the room and invite them from there."
                ))
        case .solo:
            ActionProblem(
                title: String(localized: "The solo was started, but the invitation was not sent"),
                detail: String(
                    localized:
                        "\(missed.formatted(.list(type: .and))) was not asked, and nothing reached them. Start the solo again to send one."
                ))
        }
        return issued
    }

    func take(_ url: URL) {
        switch InviteLink.read(url, scheme: Branding.urlScheme) {
        case .invite(let invite):
            arrivingInvite = try? invite.encoded()
        case .code(let keys):
            arrivingCode = (try? keys.encoded()).map(ArrivingCode.init)
        case nil:
            Diagnostics.identity.notice("link: opened with something that is not an invite")
            return
        }
        openWhatArrived()
    }

    func openWhatArrived() {
        guard session.state == .ready else { return }
        if arrivingInvite != nil { redeeming = true }
    }
}
