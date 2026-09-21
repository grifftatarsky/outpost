import CarpenterKit
import CarpenterMedia
import SwiftUI

public struct RootView: View {
    @State var theme: ThemeStore
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.clock) var roomClock
    @Environment(\.stampDevice) var stampDevice
    @State var icons: AppIconStore
    @State var organisation: RoomsListOrganisation
    @State var invite: PresentedInvite?
    @State var showingOutstanding: ConversationID?
    @State var reviewing: ConversationID?
    @State var checkingWho: ConversationID?
    @State var offeringComparison: ComparisonOffer?
    @State var askingConsent = false
    @State var aboutPerson: ReciprocalAccess?
    @State var changingAccess: OutpostAccessSubject?
    @State var adjusting: ConversationID?
    @State var greeting: RoomGreeting?
    @State var viewingMembers: ConversationID?
    @State var notifying: ConversationID?
    @State var showingWaiting: ConversationID?
    @State var preferences: RoomsListPreferences
    @State var safety: SafetyPreferences
    @State var destination: Destination? = .allOutposts
    @State var outpostsExpanded = true
    @State var showsAudienceRail = true
    @State var area: WideArea?
    @SceneStorage("wide.area") var storedArea = ""
    @State var wideColumns: NavigationSplitViewVisibility = .all
    @State var isUpright = false
    @ScaledMetric(relativeTo: .body) var sidebarWidth: CGFloat = 210
    @ScaledMetric(relativeTo: .body) var listWidth: CGFloat = 360
    #if os(iOS)
        @Environment(\.horizontalSizeClass) var horizontalSizeClass
        @Environment(\.dynamicTypeSize) var layoutTypeSize
    #endif
    @State var namingRoom = false
    @State var pickingSolo = false
    @State var soloInvite: PresentedInvite?
    @State var roomsExpanded = true
    @State var starting: ConversationID?
    @State var tab: PhoneTab = .rooms
    @State var leaving: RoomSummary?
    @State var deleting: RoomSummary?
    @State var reviewingAccessBefore: RoomSummary?

    enum PhoneTab: Hashable { case messages, rooms, outposts, you, search }

    var isSettingsWindow = false

    public func presentedAsSettings() -> Self {
        var copy = self
        copy.isSettingsWindow = true
        return copy
    }

    #if DEBUG
        func startingOn(_ tab: PhoneTab) -> Self {
            var copy = self
            copy._tab = State(initialValue: tab)
            return copy
        }

        func startingIn(_ area: WideArea, showing place: Destination? = nil) -> Self {
            var copy = self
            copy._area = State(initialValue: area)
            if let place { copy._destination = State(initialValue: place) }
            return copy
        }
    #endif

    @State var outpostPath = NavigationPath()

    // MARK: What the tabs badge

    func unreadCount(_ scope: InboxScope) -> Int {
        rooms.filter { scope.includes($0) && $0.hasUnread }.count
    }

    var unseenOutpostCount: Int { unseenOutposts.count }

    var youNeedsAttention: Bool {
        !integrity.isClean || recoveryKey?.savedAt == nil
    }

    var isSplitInbox: Bool { preferences.inbox == .split }

    @Binding var openRoom: ConversationID?

    let rooms: [RoomSummary]
    let syncedPeers: [String]
    let lastSync: Date
    let owner: Member
    let posts: [OutpostPost]
    let onSearch: (String) -> SearchResults
    let audiencePeople: Int
    let outpostAudience: OutpostAudience
    let conversation: [Message]
    let feed: [OutpostPost]
    let outpostAuthors: [Member]
    let onReact: (OutpostPost, String?) async -> Void
    let comments: (OutpostPost) -> [OutpostComment]
    let onComment: (OutpostPost, String) async -> Void
    let onAttachPost: (([PickedMedia], String?) async -> String?)?
    let postActions: PostActions
    let onReactToComment: (OutpostComment, String?) async -> Void
    let messages: (ConversationID) -> [Message]
    let transcript: (ConversationID) -> [TranscriptEntry]
    let onSend: (String, SendDestination) async -> String?
    let onCreateRoom: (String, RoomAccess, Set<ParticipantID>) async -> Void
    let onStartSolo: (ParticipantID) async -> Invite?
    let onRenameMember: ((String) async -> String?)?
    let onAvatarChange: ((PickedAvatar?) async -> Void)?
    let sharing: NameAndAvatarSharing
    let showsPrivacyNote: Bool
    let onSharingChange: (NameAndAvatarSharing) async -> Void
    let focusSharing: FocusSharing
    let onFocusSharingChange: (FocusSharing) async -> Void

    var focusBinding: Binding<FocusSharing> {
        Binding(get: { focusSharing }, set: { value in Task { await onFocusSharingChange(value) } })
    }
    let focusStatus: (ParticipantID) -> FocusStatusBody?
    let nickname: (ParticipantID) -> String?
    let sharedName: (ParticipantID) -> String?
    let onNicknameChange: ((ParticipantID, String?) async -> Void)?
    let onPersonAvatarChange: ((ParticipantID, PickedAvatar?) async -> Void)?
    @Environment(\.ownAvatar) var ownAvatar
    @Environment(\.verificationPhrase) var phraseLookup
    let connections: [Connection]
    let onOrganisationChange: ((inout RoomsListOrganisation) -> Void) -> Void
    let pendingJoins: (ConversationID) -> [PendingJoin]
    let onInvite: (ConversationID, String, InvitationLifetime, Bool) async -> Invite?
    let onOutstandingInvite: (ConversationID) async -> Invite?
    let onDecideJoin: (ConversationID, PendingJoin, Bool) async -> Void
    let identityCode: String
    let onRedeemInvite: (() -> Void)?
    let integrity: IntegrityReport
    let mediaBytes: Int?
    let onAppIconChange: (AppIconChoice) async -> Void
    let appIconIsSupported: Bool
    let devices: [DeviceSummary]
    let onRevokeDevice: ([DeviceSummary]) async -> Void
    let onRenameDevice: (DeviceSummary, String) async -> Void
    let onSync: () async -> Void
    let roomAccess: (ConversationID) -> RoomAccess?
    let roomMembers: (ConversationID) -> [Member]
    let roomInvitations: (ConversationID) -> [InvitedPerson]
    let onRescindInvitation: (ConversationID, ParticipantID) async -> Void
    let whoYouAreTalkingTo: (ConversationID) -> [VerifiedPerson]
    let waitingOn: (ConversationID) -> [WaitingOnPerson]
    let comparisonToOffer: (ConversationID) -> [VerifiedPerson]
    let onComparisonOffered: ([ParticipantID]) async -> Void
    let onMarkChecked: (ParticipantID) async -> Void
    let soloCheck: (ConversationID) -> SoloCheckPresentation
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
    let onAskWhoYouAreTalkingTo: (ConversationID, Bool) async -> Void
    let onAnswerWhoYouAreTalkingTo: (ConversationID, Bool) async -> Void
    let awaitingAdmission: [AwaitingAdmission]
    let managedTags: [ManagedTag]
    let repairStatus: (ConversationID) -> HistoryRepairStatus?
    let onRepair: (ConversationID, ParticipantID?) async -> Void
    let onDismissRepair: (ConversationID) async -> Void
    let reciprocalAccess: (ParticipantID) -> ReciprocalAccess?
    let unseenOutposts: Set<ParticipantID>
    let roomReceipts: (@MainActor (ConversationID) -> RoomReceiptChoice)?
    let roomNotGone: (@MainActor (ConversationID) -> RoomNotGoneChoice)?
    let cannotSend: String?
    let notifiedOutposts: Set<ParticipantID>
    let onMarkOutpostSeen: (ParticipantID) async -> Void
    let onMarkOutpostSeenPost: (OutpostPost) async -> Void
    let notifications: NotificationSettings?
    let supporter: SupporterSettings?
    let onSetOutpostNotified: (ParticipantID, Bool) async -> Void
    let outpostBlurb: (ParticipantID) -> String?
    let outpostSettings: OutpostSettings
    let hiddenComments: (OutpostPost) -> Int
    let onBlock: (ParticipantID) async -> Void
    let outpostReview: (ConversationID) -> OutpostReview?
    let heldRestore: (ConversationID) -> HeldRestore?
    let onLetHistoryThrough: (ParticipantID) async -> Void
    let onRefuseHistory: (ParticipantID) async -> Void
    let onOutpostChoice: (ParticipantID, OutpostAccessChoice, ConversationID?) async -> String?
    let onPostponeReview: (ConversationID) async -> Void
    let onRemoveMember: (ConversationID, ParticipantID) async -> Void
    let roomStanding: (ConversationID) -> RoomStanding
    let viewer: ParticipantID?
    let messageActions: MessageActions
    let onAttach: ((PickedMedia, String?, ConversationID) async -> String?)?
    let screening: ScreeningAvailability
    let onOpenSystemSettings: (() -> Void)?
    let blockedPeople: [Member]
    let onUnblock: (ParticipantID) async -> Void
    let denyListUpdated: String
    let onEraseEverything: (() async -> Void)?
    let roomGreeting: (ConversationID) -> RoomGreeting?
    let onGreetingSeen: (ConversationID) async -> Void
    let onRoomAccessChange: (ConversationID, RoomAccess) async -> Void
    let onHideMessage: (MessageID) async -> Void
    let hiddenInRoom: (ConversationID) -> Int
    let onRevealHiddenInRoom: (ConversationID) async -> Void
    let onSeenMessage: (MessageID, ConversationID) async -> Void
    let onMarkRoomRead: (ConversationID) async -> Void
    let onLeaveRoom: (ConversationID) async -> Void
    let roomDeletion: (ConversationID) -> RoomDeletion
    let onDeleteRoom: (ConversationID) async -> Void
    let outpostAccessChosen: (ConversationID) -> [Member]
    let onStopOutpostAccess: ([ParticipantID], ConversationID) async -> Void
    let onReactToMessage: @Sendable (MessageID, ConversationID, String?) async -> Void
    let isSilenced: (ConversationID) -> Bool
    let onSilence: (ConversationID, Bool) async -> Void
    let messageDelay: (MessageID) -> TimeInterval?
    let debugActions: DebugActions?
    let hiddenMessageCount: Int
    let recoveryKey: RecoveryKeyRow?
    let onRevealHidden: () async -> Void
    let reportsDisplaying: Bool
    let onReportsDisplayingChange: (Bool) async -> Void
    let notificationLevel: NotificationLevel
    let onNotificationLevelChange: (NotificationLevel) async -> Void
    let roomNotificationLevel: (ConversationID) -> NotificationLevel
    let roomFollowsDefaultNotifications: (ConversationID) -> Bool
    let onRoomNotificationLevelChange: (ConversationID, NotificationLevel) async -> Void

    public init(
        rooms: [RoomSummary],
        syncedPeers: [String],
        lastSync: Date,
        owner: Member,
        posts: [OutpostPost],
        onSearch: @escaping (String) -> SearchResults = { _ in SearchResults() },
        audiencePeople: Int,
        outpostAudience: OutpostAudience = OutpostAudience(),
        conversation: [Message],
        openRoom: Binding<ConversationID?> = .constant(nil),
        organisation: RoomsListOrganisation = RoomsListOrganisation(),
        feed: [OutpostPost] = [],
        outpostAuthors: [Member] = [],
        onReact: @escaping (OutpostPost, String?) async -> Void = { _, _ in },
        comments: @escaping (OutpostPost) -> [OutpostComment] = { _ in [] },
        onComment: @escaping (OutpostPost, String) async -> Void = { _, _ in },
        onAttachPost: (([PickedMedia], String?) async -> String?)? = nil,
        postActions: PostActions = PostActions(),
        onReactToComment: @escaping (OutpostComment, String?) async -> Void = { _, _ in },
        messages: @escaping (ConversationID) -> [Message] = { _ in [] },
        transcript: ((ConversationID) -> [TranscriptEntry])? = nil,
        onHideMessage: @escaping (MessageID) async -> Void = { _ in },
        hiddenInRoom: @escaping (ConversationID) -> Int = { _ in 0 },
        onRevealHiddenInRoom: @escaping (ConversationID) async -> Void = { _ in },
        onSeenMessage: @escaping (MessageID, ConversationID) async -> Void = { _, _ in },
        onMarkRoomRead: @escaping (ConversationID) async -> Void = { _ in },
        onLeaveRoom: @escaping (ConversationID) async -> Void = { _ in },
        roomDeletion: @escaping (ConversationID) -> RoomDeletion = { _ in .stillIn },
        onDeleteRoom: @escaping (ConversationID) async -> Void = { _ in },
        outpostAccessChosen: @escaping (ConversationID) -> [Member] = { _ in [] },
        onStopOutpostAccess: @escaping ([ParticipantID], ConversationID) async -> Void = { _, _ in },
        onReactToMessage: @escaping @Sendable (MessageID, ConversationID, String?) async -> Void = { _, _, _ in },
        isSilenced: @escaping (ConversationID) -> Bool = { _ in false },
        onSilence: @escaping (ConversationID, Bool) async -> Void = { _, _ in },
        messageDelay: @escaping (MessageID) -> TimeInterval? = { _ in nil },
        debugActions: DebugActions? = nil,
        hiddenMessageCount: Int = 0,
        recoveryKey: RecoveryKeyRow? = nil,
        onRevealHidden: @escaping () async -> Void = {},
        reportsDisplaying: Bool = false,
        onReportsDisplayingChange: @escaping (Bool) async -> Void = { _ in },
        notificationLevel: NotificationLevel = .default,
        onNotificationLevelChange: @escaping (NotificationLevel) async -> Void = { _ in },
        roomNotificationLevel: @escaping (ConversationID) -> NotificationLevel = { _ in .default },
        roomFollowsDefaultNotifications: @escaping (ConversationID) -> Bool = { _ in true },
        onRoomNotificationLevelChange: @escaping (ConversationID, NotificationLevel) async -> Void = { _, _ in },
        onSend: @escaping (String, SendDestination) async -> String? = { _, _ in nil },
        connections: [Connection] = [],
        onCreateRoom: @escaping (String, RoomAccess, Set<ParticipantID>) async -> Void = { _, _, _ in },
        onStartSolo: @escaping (ParticipantID) async -> Invite? = { _ in nil },
        onRenameMember: ((String) async -> String?)? = nil,
        onAvatarChange: ((PickedAvatar?) async -> Void)? = nil,
        sharing: NameAndAvatarSharing = NameAndAvatarSharing(),
        showsPrivacyNote: Bool = false,
        onSharingChange: @escaping (NameAndAvatarSharing) async -> Void = { _ in },
        focusSharing: FocusSharing = FocusSharing(),
        onFocusSharingChange: @escaping (FocusSharing) async -> Void = { _ in },
        focusStatus: @escaping (ParticipantID) -> FocusStatusBody? = { _ in nil },
        nickname: @escaping (ParticipantID) -> String? = { _ in nil },
        sharedName: @escaping (ParticipantID) -> String? = { _ in nil },
        onNicknameChange: ((ParticipantID, String?) async -> Void)? = nil,
        onPersonAvatarChange: ((ParticipantID, PickedAvatar?) async -> Void)? = nil,
        onOrganisationChange: @escaping ((inout RoomsListOrganisation) -> Void) -> Void = { _ in },
        pendingJoins: @escaping (ConversationID) -> [PendingJoin] = { _ in [] },
        onInvite: @escaping (ConversationID, String, InvitationLifetime, Bool) async -> Invite? = { _, _, _, _ in nil },
        onOutstandingInvite: @escaping (ConversationID) async -> Invite? = { _ in nil },
        onDecideJoin: @escaping (ConversationID, PendingJoin, Bool) async -> Void = { _, _, _ in },
        identityCode: String = "",
        onSync: @escaping () async -> Void = {},
        onRedeemInvite: (() -> Void)? = nil,
        integrity: IntegrityReport = IntegrityReport(),
        mediaBytes: Int? = nil,
        onAppIconChange: @escaping (AppIconChoice) async -> Void = { _ in },
        appIconIsSupported: Bool = true,
        devices: [DeviceSummary] = [],
        onRevokeDevice: @escaping ([DeviceSummary]) async -> Void = { _ in },
        onRenameDevice: @escaping (DeviceSummary, String) async -> Void = { _, _ in },
        roomAccess: @escaping (ConversationID) -> RoomAccess? = { _ in nil },
        roomMembers: @escaping (ConversationID) -> [Member] = { _ in [] },
        roomInvitations: @escaping (ConversationID) -> [InvitedPerson] = { _ in [] },
        onRescindInvitation: @escaping (ConversationID, ParticipantID) async -> Void = { _, _ in },
        waitingOn: @escaping (ConversationID) -> [WaitingOnPerson] = { _ in [] },
        comparisonToOffer: @escaping (ConversationID) -> [VerifiedPerson] = { _ in [] },
        onComparisonOffered: @escaping ([ParticipantID]) async -> Void = { _ in },
        onMarkChecked: @escaping (ParticipantID) async -> Void = { _ in },
        whoYouAreTalkingTo: @escaping (ConversationID) -> [VerifiedPerson] = { _ in [] },
        soloCheck: @escaping (ConversationID) -> SoloCheckPresentation = { _ in .nothing },
        onAskWhoYouAreTalkingTo: @escaping (ConversationID, Bool) async -> Void = { _, _ in },
        onAnswerWhoYouAreTalkingTo: @escaping (ConversationID, Bool) async -> Void = { _, _ in },
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
        awaitingAdmission: [AwaitingAdmission] = [],
        managedTags: [ManagedTag] = [],
        onRemoveMember: @escaping (ConversationID, ParticipantID) async -> Void = { _, _ in },
        roomStanding: @escaping (ConversationID) -> RoomStanding = { _ in .present },
        viewer: ParticipantID? = nil,
        messageActions: MessageActions = MessageActions(),
        onAttach: ((PickedMedia, String?, ConversationID) async -> String?)? = nil,
        safety: SafetyPreferences? = nil,
        theme: ThemeStore? = nil,
        icons: AppIconStore? = nil,
        preferences: RoomsListPreferences? = nil,
        screening: ScreeningAvailability = .unsupported,
        onOpenSystemSettings: (() -> Void)? = nil,
        blockedPeople: [Member] = [],
        onUnblock: @escaping (ParticipantID) async -> Void = { _ in },
        denyListUpdated: String = "",
        onEraseEverything: (() async -> Void)? = nil,
        roomGreeting: @escaping (ConversationID) -> RoomGreeting? = { _ in nil },
        onGreetingSeen: @escaping (ConversationID) async -> Void = { _ in },
        onRoomAccessChange: @escaping (ConversationID, RoomAccess) async -> Void = { _, _ in },
        repairStatus: @escaping (ConversationID) -> HistoryRepairStatus? = { _ in nil },
        onRepair: @escaping (ConversationID, ParticipantID?) async -> Void = { _, _ in },
        onDismissRepair: @escaping (ConversationID) async -> Void = { _ in },
        reciprocalAccess: @escaping (ParticipantID) -> ReciprocalAccess? = { _ in nil },
        unseenOutposts: Set<ParticipantID> = [],
        roomReceipts: (@MainActor (ConversationID) -> RoomReceiptChoice)? = nil,
        roomNotGone: (@MainActor (ConversationID) -> RoomNotGoneChoice)? = nil,
        cannotSend: String? = nil,
        notifiedOutposts: Set<ParticipantID> = [],
        onMarkOutpostSeen: @escaping (ParticipantID) async -> Void = { _ in },
        onMarkOutpostSeenPost: @escaping (OutpostPost) async -> Void = { _ in },
        notifications: NotificationSettings? = nil,
        supporter: SupporterSettings? = nil,
        onSetOutpostNotified: @escaping (ParticipantID, Bool) async -> Void = { _, _ in },
        outpostBlurb: @escaping (ParticipantID) -> String? = { _ in nil },
        outpostSettings: OutpostSettings = OutpostSettings(),
        hiddenComments: @escaping (OutpostPost) -> Int = { _ in 0 },
        onBlock: @escaping (ParticipantID) async -> Void = { _ in },
        outpostReview: @escaping (ConversationID) -> OutpostReview? = { _ in nil },
        heldRestore: @escaping (ConversationID) -> HeldRestore? = { _ in nil },
        onLetHistoryThrough: @escaping (ParticipantID) async -> Void = { _ in },
        onRefuseHistory: @escaping (ParticipantID) async -> Void = { _ in },
        onOutpostChoice: @escaping (ParticipantID, OutpostAccessChoice, ConversationID?) async -> String? = {
            _, _, _ in nil
        },
        onPostponeReview: @escaping (ConversationID) async -> Void = { _ in }
    ) {
        self.repairStatus = repairStatus
        self.onRepair = onRepair
        self.onDismissRepair = onDismissRepair
        self.reciprocalAccess = reciprocalAccess
        self.unseenOutposts = unseenOutposts
        self.roomReceipts = roomReceipts
        self.roomNotGone = roomNotGone
        self.cannotSend = cannotSend
        self.notifiedOutposts = notifiedOutposts
        self.onMarkOutpostSeen = onMarkOutpostSeen
        self.onMarkOutpostSeenPost = onMarkOutpostSeenPost
        self.notifications = notifications
        self.supporter = supporter
        self.onSetOutpostNotified = onSetOutpostNotified
        self.outpostBlurb = outpostBlurb
        self.outpostSettings = outpostSettings
        self.hiddenComments = hiddenComments
        self.onBlock = onBlock
        self.outpostReview = outpostReview
        self.heldRestore = heldRestore
        self.onLetHistoryThrough = onLetHistoryThrough
        self.onRefuseHistory = onRefuseHistory
        self.onOutpostChoice = onOutpostChoice
        self.onPostponeReview = onPostponeReview
        self.identityCode = identityCode
        self.onRedeemInvite = onRedeemInvite
        self.integrity = integrity
        self.mediaBytes = mediaBytes
        self.onAppIconChange = onAppIconChange
        self.appIconIsSupported = appIconIsSupported
        self.devices = devices
        self.onRevokeDevice = onRevokeDevice
        self.onRenameDevice = onRenameDevice
        self.onSync = onSync
        self.roomAccess = roomAccess
        self.roomMembers = roomMembers
        self.onRemoveMember = onRemoveMember
        self.roomStanding = roomStanding
        self.viewer = viewer
        self.messageActions = messageActions
        self.onAttach = onAttach
        _safety = State(initialValue: safety ?? SafetyPreferences())
        _theme = State(initialValue: theme ?? ThemeStore())
        _icons = State(initialValue: icons ?? AppIconStore())
        _preferences = State(initialValue: preferences ?? RoomsListPreferences())
        self.screening = screening
        self.onOpenSystemSettings = onOpenSystemSettings
        self.blockedPeople = blockedPeople
        self.onUnblock = onUnblock
        self.denyListUpdated = denyListUpdated
        self.onEraseEverything = onEraseEverything
        self.roomGreeting = roomGreeting
        self.onGreetingSeen = onGreetingSeen
        self.onRoomAccessChange = onRoomAccessChange
        self.onHideMessage = onHideMessage
        self.hiddenInRoom = hiddenInRoom
        self.onRevealHiddenInRoom = onRevealHiddenInRoom
        self.onSeenMessage = onSeenMessage
        self.onMarkRoomRead = onMarkRoomRead
        self.onLeaveRoom = onLeaveRoom
        self.roomDeletion = roomDeletion
        self.onDeleteRoom = onDeleteRoom
        self.outpostAccessChosen = outpostAccessChosen
        self.onStopOutpostAccess = onStopOutpostAccess
        self.onReactToMessage = onReactToMessage
        self.isSilenced = isSilenced
        self.onSilence = onSilence
        self.messageDelay = messageDelay
        self.debugActions = debugActions
        self.hiddenMessageCount = hiddenMessageCount
        self.recoveryKey = recoveryKey
        self.onRevealHidden = onRevealHidden
        self.reportsDisplaying = reportsDisplaying
        self.onReportsDisplayingChange = onReportsDisplayingChange
        self.notificationLevel = notificationLevel
        self.onNotificationLevelChange = onNotificationLevelChange
        self.roomNotificationLevel = roomNotificationLevel
        self.roomFollowsDefaultNotifications = roomFollowsDefaultNotifications
        self.onRoomNotificationLevelChange = onRoomNotificationLevelChange
        self.pendingJoins = pendingJoins
        self.onInvite = onInvite
        self.onOutstandingInvite = onOutstandingInvite
        self.onDecideJoin = onDecideJoin
        self.roomInvitations = roomInvitations
        self.onRescindInvitation = onRescindInvitation
        self.whoYouAreTalkingTo = whoYouAreTalkingTo
        self.waitingOn = waitingOn
        self.comparisonToOffer = comparisonToOffer
        self.onComparisonOffered = onComparisonOffered
        self.onMarkChecked = onMarkChecked
        self.soloCheck = soloCheck
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
        self.onAskWhoYouAreTalkingTo = onAskWhoYouAreTalkingTo
        self.onAnswerWhoYouAreTalkingTo = onAnswerWhoYouAreTalkingTo
        self.awaitingAdmission = awaitingAdmission
        self.managedTags = managedTags
        _organisation = State(initialValue: organisation)
        _openRoom = openRoom
        self.feed = feed
        self.outpostAuthors = outpostAuthors
        self.onReact = onReact
        self.comments = comments
        self.onComment = onComment
        self.onAttachPost = onAttachPost
        self.postActions = postActions
        self.onReactToComment = onReactToComment
        self.messages = messages
        self.transcript = transcript ?? { messages($0).map(TranscriptEntry.message) }
        self.onSend = onSend
        self.connections = connections
        self.onCreateRoom = onCreateRoom
        self.onStartSolo = onStartSolo
        self.onRenameMember = onRenameMember
        self.onAvatarChange = onAvatarChange
        self.sharing = sharing
        self.showsPrivacyNote = showsPrivacyNote
        self.onSharingChange = onSharingChange
        self.focusSharing = focusSharing
        self.onFocusSharingChange = onFocusSharingChange
        self.focusStatus = focusStatus
        self.nickname = nickname
        self.sharedName = sharedName
        self.onNicknameChange = onNicknameChange
        self.onPersonAvatarChange = onPersonAvatarChange
        self.onOrganisationChange = onOrganisationChange
        self.rooms = rooms
        self.syncedPeers = syncedPeers
        self.lastSync = lastSync
        self.owner = owner
        self.posts = posts
        self.onSearch = onSearch
        self.audiencePeople = audiencePeople
        self.outpostAudience = outpostAudience
        self.conversation = conversation
    }

    enum Destination: Hashable {
        case allOutposts
        case outpost(ParticipantID)
        case room(ConversationID)
        case you
    }

    @Environment(\.displayScale) var displayScale
    @Environment(\.colorSchemeContrast) var contrast

    public var body: some View {
        layout
            .environment(\.showsHelp, theme.tutorialMode)
            .confirmationDialog(
                Text("Leave \(leaving?.name ?? "")", bundle: .module),
                isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }),
                titleVisibility: .visible,
                presenting: leaving
            ) { room in
                if !outpostAccessChosen(room.id).isEmpty {
                    Button(role: .destructive) {
                        leaving = nil
                        reviewingAccessBefore = room
                    } label: {
                        Text("Leave and Review Outpost Access", bundle: .module)
                    }
                }
                Button(role: .destructive) {
                    Task { await onLeaveRoom(room.id) }
                } label: {
                    Text("Leave", bundle: .module)
                }
                Button(role: .cancel) {
                } label: {
                    Text("Cancel", bundle: .module)
                }
            } message: { room in
                if room.isDirect {
                    Text(
                        "\(room.name) will see that you left. What is already here stays on this device and stays readable; you will not receive anything new, and you cannot write.",
                        bundle: .module
                    )
                } else {
                    Text(
                        "Everybody in \(room.name) will see that you left. What is already here stays on this device and stays readable; you will not receive anything new, and you cannot write.",
                        bundle: .module
                    )
                }
            }
            .alert(
                Text("Delete \(deleting?.name ?? "")", bundle: .module),
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                presenting: deleting
            ) { room in
                Button {
                    Task {
                        await onDeleteRoom(room.id)
                        if openRoom == room.id, roomDeletion(room.id) != .allowed { openRoom = nil }
                    }
                } label: {
                    Text("Delete", bundle: .module)
                }
                Button(role: .cancel) {
                } label: {
                    Text("Cancel", bundle: .module)
                }
            } message: { _ in
                Text(
                    "Every message and photo in it goes from your devices, and being added back may not bring them back. This cannot be undone.",
                    bundle: .module)
            }
            .sizedSheet(item: $reviewingAccessBefore) { room in
                LeavingRoomView(
                    roomName: room.name,
                    people: outpostAccessChosen(room.id),
                    onLeave: { stopping in
                        await onStopOutpostAccess(stopping, room.id)
                        await onLeaveRoom(room.id)
                    })
            }
    }

    @ViewBuilder
    var layout: some View {
        #if os(macOS)
            if isSettingsWindow {
                settingsWindow
            } else {
                wide
            }
        #else
            if UIDevice.current.userInterfaceIdiom == .pad, horizontalSizeClass == .regular,
                !layoutTypeSize.isAccessibilitySize
            {
                wide
            } else {
                phone
            }
        #endif
    }
}
