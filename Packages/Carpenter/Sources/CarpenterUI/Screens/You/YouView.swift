import CarpenterKit
import CarpenterMedia
import SwiftUI

public struct YouView: View {
    @Environment(\.palette) var palette
    @Environment(\.dynamicTypeSize) var typeSize

    @Binding var accent: Accent
    @Binding var tutorialMode: Bool
    @Binding var playsHaptics: Bool
    @Binding var showsMessageDelay: Bool
    @Binding var reportsDisplaying: Bool
    @Binding var notificationLevel: NotificationLevel
    let debugActions: DebugActions?
    @Binding var demoConversation: Bool
    @Binding var demoParticipants: Int
    @Binding var demoOutpost: Bool
    let outpostSettings: OutpostSettings
    @Binding var inbox: InboxArrangement
    @Binding var showsAvatars: Bool
    let hiddenMessageCount: Int
    let recoveryKey: RecoveryKeyRow?
    let notifications: NotificationSettings?
    let supporter: SupporterSettings?
    @State var welcomingSupporter = false
    let onRevealHidden: () async -> Void
    @Binding var blursSensitiveMedia: Bool
    let screening: ScreeningAvailability
    let onOpenSystemSettings: (() -> Void)?
    @Binding var blocksKnownAbusers: Bool
    let requiresSoloCheck: Bool
    let onRequiresSoloCheck: (Bool) async -> Void
    let requiresLongPhrase: Bool
    let onRequiresLongPhrase: (Bool) async -> Void
    let toldAboutRestores: Bool
    let onToldAboutRestores: (Bool) async -> Void
    let holdsHistoryForRestores: Bool
    let onHoldsHistoryForRestores: (Bool) async -> Void
    let asksPeersForHistory: Bool
    let onAsksPeersForHistory: (Bool) async -> Void
    let denyListUpdated: String
    let blockedPeople: [Member]
    let onUnblock: (ParticipantID) async -> Void
    @Binding var debugBlursEveryPhoto: Bool
    let onEraseEverything: (() async -> Void)?
    let onRename: ((String) async -> String?)?
    let onAvatarChange: ((PickedAvatar?) async -> Void)?
    let connections: [Connection]
    let nickname: (ParticipantID) -> String?
    let sharedName: (ParticipantID) -> String?
    let onNicknameChange: ((ParticipantID, String?) async -> Void)?
    let onPersonAvatarChange: ((ParticipantID, PickedAvatar?) async -> Void)?
    @Binding var sharing: NameAndAvatarSharing
    @Binding var focus: FocusSharing
    @Environment(\.ownAvatar) var ownAvatar
    @State var erasing = false
    var presentsAsSettings = false
    #if os(macOS)
        @AppStorage("settings.pane") var settingsPane = SettingsPane.appearance
    #endif
    @Environment(\.openURL) var openURL

    static let subscribeByEmail = URL(
        string:
            "mailto:updates@outpostmessaging.com?subject=Subscribe&body=Send%20me%20feature%20and%20security%20updates%20about%20Outpost."
    )!

    let owner: Member
    let fingerprint: String
    let identityCode: String
    let integrity: IntegrityReport
    let mediaBytes: Int?
    @Binding var appIcon: AppIconChoice
    let appIconIsSupported: Bool
    let devices: [DeviceSummary]
    let onRevokeDevice: ([DeviceSummary]) async -> Void
    let onPairDevice: (() -> Void)?
    let onRenameDevice: ((DeviceSummary, String) async -> Void)?
    let postCount: Int
    let audiencePeople: Int
    let tagCount: Int

    public init(
        accent: Binding<Accent>,
        tutorialMode: Binding<Bool> = .constant(false),
        playsHaptics: Binding<Bool> = .constant(true),
        showsMessageDelay: Binding<Bool> = .constant(false),
        reportsDisplaying: Binding<Bool> = .constant(false),
        notificationLevel: Binding<NotificationLevel> = .constant(.default),
        debugActions: DebugActions? = nil,
        demoConversation: Binding<Bool> = .constant(false),
        demoParticipants: Binding<Int> = .constant(8),
        demoOutpost: Binding<Bool> = .constant(false),
        outpostSettings: OutpostSettings = OutpostSettings(),
        inbox: Binding<InboxArrangement> = .constant(.split),
        showsAvatars: Binding<Bool> = .constant(true),
        hiddenMessageCount: Int = 0,
        recoveryKey: RecoveryKeyRow? = nil,
        notifications: NotificationSettings? = nil,
        supporter: SupporterSettings? = nil,
        onRevealHidden: @escaping () async -> Void = {},
        blursSensitiveMedia: Binding<Bool> = .constant(true),
        screening: ScreeningAvailability = .unsupported,
        onOpenSystemSettings: (() -> Void)? = nil,
        blocksKnownAbusers: Binding<Bool> = .constant(true),
        requiresSoloCheck: Bool = false,
        onRequiresSoloCheck: @escaping (Bool) async -> Void = { _ in },
        requiresLongPhrase: Bool = false,
        onRequiresLongPhrase: @escaping (Bool) async -> Void = { _ in },
        toldAboutRestores: Bool = false,
        onToldAboutRestores: @escaping (Bool) async -> Void = { _ in },
        holdsHistoryForRestores: Bool = false,
        onHoldsHistoryForRestores: @escaping (Bool) async -> Void = { _ in },
        asksPeersForHistory: Bool = true,
        onAsksPeersForHistory: @escaping (Bool) async -> Void = { _ in },
        denyListUpdated: String = "",
        blockedPeople: [Member] = [],
        onUnblock: @escaping (ParticipantID) async -> Void = { _ in },
        debugBlursEveryPhoto: Binding<Bool> = .constant(false),
        onEraseEverything: (() async -> Void)? = nil,
        onRename: ((String) async -> String?)? = nil,
        onAvatarChange: ((PickedAvatar?) async -> Void)? = nil,
        connections: [Connection] = [],
        nickname: @escaping (ParticipantID) -> String? = { _ in nil },
        sharedName: @escaping (ParticipantID) -> String? = { _ in nil },
        onNicknameChange: ((ParticipantID, String?) async -> Void)? = nil,
        onPersonAvatarChange: ((ParticipantID, PickedAvatar?) async -> Void)? = nil,
        sharing: Binding<NameAndAvatarSharing> = .constant(NameAndAvatarSharing()),
        focus: Binding<FocusSharing> = .constant(FocusSharing()),
        owner: Member,
        fingerprint: String,
        postCount: Int,
        audiencePeople: Int,
        tagCount: Int,
        identityCode: String = "",
        integrity: IntegrityReport = IntegrityReport(),
        mediaBytes: Int? = nil,
        appIcon: Binding<AppIconChoice>? = nil,
        appIconIsSupported: Bool = true,
        devices: [DeviceSummary] = [],
        onRevokeDevice: @escaping ([DeviceSummary]) async -> Void = { _ in },
        onPairDevice: (() -> Void)? = nil,
        onRenameDevice: ((DeviceSummary, String) async -> Void)? = nil
    ) {
        _accent = accent
        _tutorialMode = tutorialMode
        _playsHaptics = playsHaptics
        _showsMessageDelay = showsMessageDelay
        _reportsDisplaying = reportsDisplaying
        _notificationLevel = notificationLevel
        self.debugActions = debugActions
        _demoConversation = demoConversation
        _demoParticipants = demoParticipants
        _demoOutpost = demoOutpost
        self.outpostSettings = outpostSettings
        _inbox = inbox
        _showsAvatars = showsAvatars
        self.hiddenMessageCount = hiddenMessageCount
        self.recoveryKey = recoveryKey
        self.notifications = notifications
        self.supporter = supporter
        self.onRevealHidden = onRevealHidden
        _blursSensitiveMedia = blursSensitiveMedia
        self.screening = screening
        self.onOpenSystemSettings = onOpenSystemSettings
        _blocksKnownAbusers = blocksKnownAbusers
        self.requiresSoloCheck = requiresSoloCheck
        self.onRequiresSoloCheck = onRequiresSoloCheck
        self.requiresLongPhrase = requiresLongPhrase
        self.onRequiresLongPhrase = onRequiresLongPhrase
        self.toldAboutRestores = toldAboutRestores
        self.onToldAboutRestores = onToldAboutRestores
        self.holdsHistoryForRestores = holdsHistoryForRestores
        self.onHoldsHistoryForRestores = onHoldsHistoryForRestores
        self.asksPeersForHistory = asksPeersForHistory
        self.onAsksPeersForHistory = onAsksPeersForHistory
        self.denyListUpdated = denyListUpdated
        self.blockedPeople = blockedPeople
        self.onUnblock = onUnblock
        _debugBlursEveryPhoto = debugBlursEveryPhoto
        self.onEraseEverything = onEraseEverything
        self.onRename = onRename
        self.onAvatarChange = onAvatarChange
        self.connections = connections
        self.nickname = nickname
        self.sharedName = sharedName
        self.onNicknameChange = onNicknameChange
        self.onPersonAvatarChange = onPersonAvatarChange
        _sharing = sharing
        _focus = focus
        self.owner = owner
        self.fingerprint = fingerprint
        self.identityCode = identityCode
        self.integrity = integrity
        self.mediaBytes = mediaBytes
        _appIcon = appIcon ?? .constant(.default)
        self.appIconIsSupported = appIconIsSupported
        self.devices = devices
        self.onRevokeDevice = onRevokeDevice
        self.onPairDevice = onPairDevice
        self.onRenameDevice = onRenameDevice
        self.postCount = postCount
        self.audiencePeople = audiencePeople
        self.tagCount = tagCount
    }

    public func presentedAsSettings() -> Self {
        var copy = self
        copy.presentsAsSettings = true
        return copy
    }

    public var body: some View {
        presented
            .sizedSheet(isPresented: $welcomingSupporter) {
                SupporterWelcomeView(
                    owner: owner, ownAvatar: ownAvatar,
                    onShowBadge: { await supporter?.onShowBadge($0) })
            }
            .sizedSheet(isPresented: $erasing) {
                EraseEverythingView(onErase: { await onEraseEverything?() })
            }
    }

    @ViewBuilder
    var presented: some View {
        #if os(macOS)
            if presentsAsSettings {
                settingsPanes
            } else {
                list
            }
        #else
            list
        #endif
    }

    var list: some View {
        List {
            Section {
                masthead
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            #if os(iOS)
                .listSectionSpacing(.compact)
            #endif

            if let supporter, supporter.canClaim {
                Section {
                    SupporterBar {
                        welcomingSupporter = true
                        Task { await supporter.onClaim() }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            }

            Section {
                identityRow
                NavigationLink {
                    PeopleView(
                        connections: connections, nickname: nickname, sharedName: sharedName,
                        onNicknameChange: onNicknameChange, onPersonAvatarChange: onPersonAvatarChange)
                } label: {
                    SettingsRow(
                        icon: "person.2.fill",
                        title: Text("People", bundle: .module),
                        detail: Text("\(connections.count)", bundle: .module))
                }
                if let supporter, !supporter.canClaim, supporter.standing.isSupporter {
                    NavigationLink {
                        SupporterView(settings: supporter)
                    } label: {
                        SettingsRow(
                            icon: "party.popper.fill",
                            title: Text("Supporter", bundle: .module),
                            detail: supporter.standingDetail)
                    }
                }
            }
            .groupedRowSurface()

            #if os(macOS)
                Section {
                    yourOutpostRow
                    SettingsLink {
                        SettingsRow(
                            icon: "gearshape.fill", tone: .device,
                            title: Text("Settings", bundle: .module))
                    }
                    .buttonStyle(.plain)
                }
                .groupedRowSurface()
                gettingHelp
            #else
                reachingYou
                outpost
                howItLooks
                thisDevice
                gettingHelp
                if onEraseEverything != nil { erase }
            #endif
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, CarpenterMetrics.mastheadTopInset, for: .scrollContent)
        .background(palette.background)
        .navigationTitle(Text(verbatim: ""))
        .helpButton()
        .toolbarTitleDisplayMode(.inline)
    }
}
