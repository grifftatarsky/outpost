import CarpenterKit
import CarpenterMedia
import SwiftUI

public struct RootView: View {
    @State var theme = ThemeStore()
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.clock) var roomClock
    @Environment(\.stampDevice) var stampDevice
    @State var icons = AppIconStore()
    @State var organisation: RoomsListOrganisation
    @State var invite: PresentedInvite?
    @State var showingOutstanding: RoomID?
    @State var reviewing: RoomID?
    @State var checkingWho: RoomID?
    @State var offeringComparison: ComparisonOffer?
    @State var askingConsent = false
    @State var aboutPerson: ReciprocalAccess?
    @State var changingAccess: OutpostAccessSubject?
    @State var adjusting: RoomID?
    @State var greeting: RoomGreeting?
    @State var viewingMembers: RoomID?
    @State var notifying: RoomID?
    @State var showingWaiting: RoomID?
    @State var preferences = RoomsListPreferences()
    @State var safety: SafetyPreferences
    @State var destination: Destination? = .allOutposts
    @State var outpostsExpanded = true
    @State var showsAudienceRail = true
    @State var roomsExpanded = true
    @State var starting: RoomID?
    @State var tab: PhoneTab = .rooms
    @State var leaving: RoomSummary?
    @State var deleting: RoomSummary?
    @State var reviewingAccessBefore: RoomSummary?

    enum PhoneTab: Hashable { case messages, rooms, outposts, you, search }

    #if DEBUG
        func startingOn(_ tab: PhoneTab) -> Self {
            var copy = self
            copy._tab = State(initialValue: tab)
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

    @Binding var openRoom: RoomID?

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
    let messages: (RoomID) -> [Message]
    let transcript: (RoomID) -> [TranscriptEntry]
    let onSend: (String, RoomID?) async -> String?
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
    let pendingJoins: (RoomID) -> [PendingJoin]
    let onInvite: (RoomID, String, InvitationLifetime) async -> Invite?
    let onOutstandingInvite: (RoomID) async -> Invite?
    let onDecideJoin: (RoomID, PendingJoin, Bool) async -> Void
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
    let roomAccess: (RoomID) -> RoomAccess?
    let roomMembers: (RoomID) -> [Member]
    let roomInvitations: (RoomID) -> [InvitedPerson]
    let onRescindInvitation: (RoomID, ParticipantID) async -> Void
    let whoYouAreTalkingTo: (RoomID) -> [VerifiedPerson]
    let waitingOn: (RoomID) -> [WaitingOnPerson]
    let comparisonToOffer: (RoomID) -> [VerifiedPerson]
    let onComparisonOffered: ([ParticipantID]) async -> Void
    let onMarkChecked: (ParticipantID) async -> Void
    let soloCheck: (RoomID) -> SoloCheckPresentation
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
    let onAskWhoYouAreTalkingTo: (RoomID, Bool) async -> Void
    let onAnswerWhoYouAreTalkingTo: (RoomID, Bool) async -> Void
    let awaitingAdmission: [AwaitingAdmission]
    let managedTags: [ManagedTag]
    let repairStatus: (RoomID) -> HistoryRepairStatus?
    let onRepair: (RoomID, ParticipantID?) async -> Void
    let onDismissRepair: (RoomID) async -> Void
    let reciprocalAccess: (ParticipantID) -> ReciprocalAccess?
    let unseenOutposts: Set<ParticipantID>
    let roomReceipts: (@MainActor (RoomID) -> RoomReceiptChoice)?
    let roomNotGone: (@MainActor (RoomID) -> RoomNotGoneChoice)?
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
    let outpostReview: (RoomID) -> OutpostReview?
    let heldRestore: (RoomID) -> HeldRestore?
    let onLetHistoryThrough: (ParticipantID) async -> Void
    let onRefuseHistory: (ParticipantID) async -> Void
    let onOutpostChoice: (ParticipantID, OutpostAccessChoice, RoomID?) async -> String?
    let onPostponeReview: (RoomID) async -> Void
    let onRemoveMember: (RoomID, ParticipantID) async -> Void
    let roomStanding: (RoomID) -> RoomStanding
    let viewer: ParticipantID?
    let messageActions: MessageActions
    let onAttach: ((PickedMedia, String?, RoomID) async -> String?)?
    let screening: ScreeningAvailability
    let onOpenSystemSettings: (() -> Void)?
    let blockedPeople: [Member]
    let onUnblock: (ParticipantID) async -> Void
    let denyListUpdated: String
    let onEraseEverything: (() async -> Void)?
    let roomGreeting: (RoomID) -> RoomGreeting?
    let onGreetingSeen: (RoomID) async -> Void
    let onRoomAccessChange: (RoomID, RoomAccess) async -> Void
    let onHideMessage: (MessageID) async -> Void
    let hiddenInRoom: (RoomID) -> Int
    let onRevealHiddenInRoom: (RoomID) async -> Void
    let onSeenMessage: (MessageID, RoomID) async -> Void
    let onMarkRoomRead: (RoomID) async -> Void
    let onLeaveRoom: (RoomID) async -> Void
    let roomDeletion: (RoomID) -> RoomDeletion
    let onDeleteRoom: (RoomID) async -> Void
    let outpostAccessChosen: (RoomID) -> [Member]
    let onStopOutpostAccess: ([ParticipantID], RoomID) async -> Void
    let onReactToMessage: @Sendable (MessageID, RoomID, String?) async -> Void
    let isSilenced: (RoomID) -> Bool
    let onSilence: (RoomID, Bool) async -> Void
    let messageDelay: (MessageID) -> TimeInterval?
    let debugActions: DebugActions?
    let hiddenMessageCount: Int
    let recoveryKey: RecoveryKeyRow?
    let onRevealHidden: () async -> Void
    let reportsDisplaying: Bool
    let onReportsDisplayingChange: (Bool) async -> Void
    let notificationLevel: NotificationLevel
    let onNotificationLevelChange: (NotificationLevel) async -> Void
    let roomNotificationLevel: (RoomID) -> NotificationLevel
    let roomFollowsDefaultNotifications: (RoomID) -> Bool
    let onRoomNotificationLevelChange: (RoomID, NotificationLevel) async -> Void

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
        openRoom: Binding<RoomID?> = .constant(nil),
        organisation: RoomsListOrganisation = RoomsListOrganisation(),
        feed: [OutpostPost] = [],
        outpostAuthors: [Member] = [],
        onReact: @escaping (OutpostPost, String?) async -> Void = { _, _ in },
        comments: @escaping (OutpostPost) -> [OutpostComment] = { _ in [] },
        onComment: @escaping (OutpostPost, String) async -> Void = { _, _ in },
        onAttachPost: (([PickedMedia], String?) async -> String?)? = nil,
        postActions: PostActions = PostActions(),
        onReactToComment: @escaping (OutpostComment, String?) async -> Void = { _, _ in },
        messages: @escaping (RoomID) -> [Message] = { _ in [] },
        transcript: ((RoomID) -> [TranscriptEntry])? = nil,
        onHideMessage: @escaping (MessageID) async -> Void = { _ in },
        hiddenInRoom: @escaping (RoomID) -> Int = { _ in 0 },
        onRevealHiddenInRoom: @escaping (RoomID) async -> Void = { _ in },
        onSeenMessage: @escaping (MessageID, RoomID) async -> Void = { _, _ in },
        onMarkRoomRead: @escaping (RoomID) async -> Void = { _ in },
        onLeaveRoom: @escaping (RoomID) async -> Void = { _ in },
        roomDeletion: @escaping (RoomID) -> RoomDeletion = { _ in .stillIn },
        onDeleteRoom: @escaping (RoomID) async -> Void = { _ in },
        outpostAccessChosen: @escaping (RoomID) -> [Member] = { _ in [] },
        onStopOutpostAccess: @escaping ([ParticipantID], RoomID) async -> Void = { _, _ in },
        onReactToMessage: @escaping @Sendable (MessageID, RoomID, String?) async -> Void = { _, _, _ in },
        isSilenced: @escaping (RoomID) -> Bool = { _ in false },
        onSilence: @escaping (RoomID, Bool) async -> Void = { _, _ in },
        messageDelay: @escaping (MessageID) -> TimeInterval? = { _ in nil },
        debugActions: DebugActions? = nil,
        hiddenMessageCount: Int = 0,
        recoveryKey: RecoveryKeyRow? = nil,
        onRevealHidden: @escaping () async -> Void = {},
        reportsDisplaying: Bool = false,
        onReportsDisplayingChange: @escaping (Bool) async -> Void = { _ in },
        notificationLevel: NotificationLevel = .default,
        onNotificationLevelChange: @escaping (NotificationLevel) async -> Void = { _ in },
        roomNotificationLevel: @escaping (RoomID) -> NotificationLevel = { _ in .default },
        roomFollowsDefaultNotifications: @escaping (RoomID) -> Bool = { _ in true },
        onRoomNotificationLevelChange: @escaping (RoomID, NotificationLevel) async -> Void = { _, _ in },
        onSend: @escaping (String, RoomID?) async -> String? = { _, _ in nil },
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
        pendingJoins: @escaping (RoomID) -> [PendingJoin] = { _ in [] },
        onInvite: @escaping (RoomID, String, InvitationLifetime) async -> Invite? = { _, _, _ in nil },
        onOutstandingInvite: @escaping (RoomID) async -> Invite? = { _ in nil },
        onDecideJoin: @escaping (RoomID, PendingJoin, Bool) async -> Void = { _, _, _ in },
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
        roomAccess: @escaping (RoomID) -> RoomAccess? = { _ in nil },
        roomMembers: @escaping (RoomID) -> [Member] = { _ in [] },
        roomInvitations: @escaping (RoomID) -> [InvitedPerson] = { _ in [] },
        onRescindInvitation: @escaping (RoomID, ParticipantID) async -> Void = { _, _ in },
        waitingOn: @escaping (RoomID) -> [WaitingOnPerson] = { _ in [] },
        comparisonToOffer: @escaping (RoomID) -> [VerifiedPerson] = { _ in [] },
        onComparisonOffered: @escaping ([ParticipantID]) async -> Void = { _ in },
        onMarkChecked: @escaping (ParticipantID) async -> Void = { _ in },
        whoYouAreTalkingTo: @escaping (RoomID) -> [VerifiedPerson] = { _ in [] },
        soloCheck: @escaping (RoomID) -> SoloCheckPresentation = { _ in .nothing },
        onAskWhoYouAreTalkingTo: @escaping (RoomID, Bool) async -> Void = { _, _ in },
        onAnswerWhoYouAreTalkingTo: @escaping (RoomID, Bool) async -> Void = { _, _ in },
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
        onRemoveMember: @escaping (RoomID, ParticipantID) async -> Void = { _, _ in },
        roomStanding: @escaping (RoomID) -> RoomStanding = { _ in .present },
        viewer: ParticipantID? = nil,
        messageActions: MessageActions = MessageActions(),
        onAttach: ((PickedMedia, String?, RoomID) async -> String?)? = nil,
        safety: SafetyPreferences? = nil,
        screening: ScreeningAvailability = .unsupported,
        onOpenSystemSettings: (() -> Void)? = nil,
        blockedPeople: [Member] = [],
        onUnblock: @escaping (ParticipantID) async -> Void = { _ in },
        denyListUpdated: String = "",
        onEraseEverything: (() async -> Void)? = nil,
        roomGreeting: @escaping (RoomID) -> RoomGreeting? = { _ in nil },
        onGreetingSeen: @escaping (RoomID) async -> Void = { _ in },
        onRoomAccessChange: @escaping (RoomID, RoomAccess) async -> Void = { _, _ in },
        repairStatus: @escaping (RoomID) -> HistoryRepairStatus? = { _ in nil },
        onRepair: @escaping (RoomID, ParticipantID?) async -> Void = { _, _ in },
        onDismissRepair: @escaping (RoomID) async -> Void = { _ in },
        reciprocalAccess: @escaping (ParticipantID) -> ReciprocalAccess? = { _ in nil },
        unseenOutposts: Set<ParticipantID> = [],
        roomReceipts: (@MainActor (RoomID) -> RoomReceiptChoice)? = nil,
        roomNotGone: (@MainActor (RoomID) -> RoomNotGoneChoice)? = nil,
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
        outpostReview: @escaping (RoomID) -> OutpostReview? = { _ in nil },
        heldRestore: @escaping (RoomID) -> HeldRestore? = { _ in nil },
        onLetHistoryThrough: @escaping (ParticipantID) async -> Void = { _ in },
        onRefuseHistory: @escaping (ParticipantID) async -> Void = { _ in },
        onOutpostChoice: @escaping (ParticipantID, OutpostAccessChoice, RoomID?) async -> String? = {
            _, _, _ in nil
        },
        onPostponeReview: @escaping (RoomID) async -> Void = { _ in }
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
        case room(RoomID)
        case you
    }

    @Environment(\.displayScale) var displayScale
    @Environment(\.colorSchemeContrast) var contrast

    public var body: some View {
        layout
            .environment(\.showsHelp, theme.tutorialMode)
            // A confirmation dialog rather than an alert: Apple's answer for a choice related to an
            // intentional action, and an alert offers no additional choices related to the action.
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
            desktop
        #else
            phone
        #endif
    }
}
