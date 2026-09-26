import CarpenterKit
import CarpenterMedia
import PhotosUI
import SwiftUI

public struct ConversationView: View {
    @Environment(\.palette) var palette
    @Environment(\.clock) var clock
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.notGoneHelp) var notGoneHelp

    @State var draft = ""
    @State var sent = 0
    @State var failures = 0
    @State var problem: String?
    @State var askingCheck = false
    @State var detailing: Message?
    @State var reviewing: OutpostReview?
    @State var picked: [PhotosPickerItem] = []
    @State var pickingPhotos = false
    @AppStorage("explained.photos") var photosExplained = false
    @State var explainingPhotos = false
    @State var sending: [MediaKind] = []
    @State var staged: [StagedAttachment] = []
    @State var trimming: StagedAttachment?

    let room: RoomSummary
    let entries: [TranscriptEntry]
    let onSend: (String) async -> String?
    let onAttach: ((PickedMedia, String?) async -> String?)?
    let onHide: ((MessageID) async -> Void)?
    let hiddenCount: Int
    let onRevealHidden: (() async -> Void)?
    let onSeen: ((MessageID) async -> Void)?
    let messageDelay: (MessageID) -> TimeInterval?
    let pendingJoinCount: Int
    let uncheckedCount: Int
    let onInvite: (() -> Void)?
    let onShowInvite: (() -> Void)?
    let onReviewJoins: (() -> Void)?
    let onWhoYouAreTalkingTo: (() -> Void)?
    let soloCheck: SoloCheckPresentation
    let onAskWhoYouAreTalkingTo: ((Bool) async -> Void)?
    let onAnswerWhoYouAreTalkingTo: ((Bool) async -> Void)?
    let onStopRequiringSoloCheck: (() async -> Void)?
    let soloPhrase: String?
    let onRoomAccess: (() -> Void)?
    let onRoomNotifications: (() -> Void)?
    let onRoomMembers: (() -> Void)?
    let onActiveSync: () async -> Void
    let messageActions: MessageActions?

    let standing: RoomStanding
    let partnerFocus: FocusStatusBody?
    let repair: HistoryRepairStatus?
    let repairTargets: [Member]
    let onRepair: ((ParticipantID?) async -> Void)?
    let onDismissRepair: (() async -> Void)?
    let outpostReview: OutpostReview?
    let heldRestore: HeldRestore?
    let onLetHistoryThrough: ((ParticipantID) async -> Void)?
    let onRefuseHistory: ((ParticipantID) async -> Void)?
    let onOutpostChoice: ((ParticipantID, OutpostAccessChoice, RoomID?) async -> String?)?
    let onPostponeReview: (() async -> Void)?
    let onDelete: (() -> Void)?

    public init(
        room: RoomSummary,
        transcript: [TranscriptEntry],
        pendingJoinCount: Int = 0,
        uncheckedCount: Int = 0,
        onSend: @escaping (String) async -> String? = { _ in nil },
        onAttach: ((PickedMedia, String?) async -> String?)? = nil,
        onHide: ((MessageID) async -> Void)? = nil,
        hiddenCount: Int = 0,
        onRevealHidden: (() async -> Void)? = nil,
        onSeen: ((MessageID) async -> Void)? = nil,
        messageDelay: @escaping (MessageID) -> TimeInterval? = { _ in nil },
        onInvite: (() -> Void)? = nil,
        onShowInvite: (() -> Void)? = nil,
        onReviewJoins: (() -> Void)? = nil,
        onWhoYouAreTalkingTo: (() -> Void)? = nil,
        soloCheck: SoloCheckPresentation = .nothing,
        onAskWhoYouAreTalkingTo: ((Bool) async -> Void)? = nil,
        onAnswerWhoYouAreTalkingTo: ((Bool) async -> Void)? = nil,
        onStopRequiringSoloCheck: (() async -> Void)? = nil,
        soloPhrase: String? = nil,
        onRoomAccess: (() -> Void)? = nil,
        onRoomNotifications: (() -> Void)? = nil,
        onRoomMembers: (() -> Void)? = nil,
        onActiveSync: @escaping () async -> Void = {},
        standing: RoomStanding = .present,
        messageActions: MessageActions? = nil,
        partnerFocus: FocusStatusBody? = nil,
        repair: HistoryRepairStatus? = nil,
        repairTargets: [Member] = [],
        onRepair: ((ParticipantID?) async -> Void)? = nil,
        onDismissRepair: (() async -> Void)? = nil,
        outpostReview: OutpostReview? = nil,
        heldRestore: HeldRestore? = nil,
        onLetHistoryThrough: ((ParticipantID) async -> Void)? = nil,
        onRefuseHistory: ((ParticipantID) async -> Void)? = nil,
        onOutpostChoice: ((ParticipantID, OutpostAccessChoice, RoomID?) async -> String?)? = nil,
        onPostponeReview: (() async -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.room = room
        entries = transcript
        self.onDelete = onDelete
        self.outpostReview = outpostReview
        self.heldRestore = heldRestore
        self.onLetHistoryThrough = onLetHistoryThrough
        self.onRefuseHistory = onRefuseHistory
        self.onOutpostChoice = onOutpostChoice
        self.onPostponeReview = onPostponeReview
        self.standing = standing
        self.partnerFocus = partnerFocus
        self.repair = repair
        self.repairTargets = repairTargets
        self.onRepair = onRepair
        self.onDismissRepair = onDismissRepair
        self.messageActions = messageActions
        self.onRoomMembers = onRoomMembers
        self.pendingJoinCount = pendingJoinCount
        self.uncheckedCount = uncheckedCount
        self.onSend = onSend
        self.onAttach = onAttach
        self.onHide = onHide
        self.hiddenCount = hiddenCount
        self.onRevealHidden = onRevealHidden
        self.onSeen = onSeen
        self.messageDelay = messageDelay
        self.onInvite = onInvite
        self.onShowInvite = onShowInvite
        self.onReviewJoins = onReviewJoins
        self.onWhoYouAreTalkingTo = onWhoYouAreTalkingTo
        self.soloCheck = soloCheck
        self.onAskWhoYouAreTalkingTo = onAskWhoYouAreTalkingTo
        self.onAnswerWhoYouAreTalkingTo = onAnswerWhoYouAreTalkingTo
        self.onStopRequiringSoloCheck = onStopRequiringSoloCheck
        self.soloPhrase = soloPhrase
        self.onRoomAccess = onRoomAccess
        self.onRoomNotifications = onRoomNotifications
        self.onActiveSync = onActiveSync
    }

    public init(
        room: RoomSummary,
        messages: [Message],
        pendingJoinCount: Int = 0,
        uncheckedCount: Int = 0,
        onSend: @escaping (String) async -> String? = { _ in nil },
        onAttach: ((PickedMedia, String?) async -> String?)? = nil,
        onHide: ((MessageID) async -> Void)? = nil,
        hiddenCount: Int = 0,
        onRevealHidden: (() async -> Void)? = nil,
        onSeen: ((MessageID) async -> Void)? = nil,
        messageDelay: @escaping (MessageID) -> TimeInterval? = { _ in nil },
        onInvite: (() -> Void)? = nil,
        onShowInvite: (() -> Void)? = nil,
        onReviewJoins: (() -> Void)? = nil,
        onWhoYouAreTalkingTo: (() -> Void)? = nil,
        soloCheck: SoloCheckPresentation = .nothing,
        onAskWhoYouAreTalkingTo: ((Bool) async -> Void)? = nil,
        onAnswerWhoYouAreTalkingTo: ((Bool) async -> Void)? = nil,
        onStopRequiringSoloCheck: (() async -> Void)? = nil,
        soloPhrase: String? = nil,
        onRoomAccess: (() -> Void)? = nil,
        onRoomNotifications: (() -> Void)? = nil,
        onRoomMembers: (() -> Void)? = nil,
        onActiveSync: @escaping () async -> Void = {},
        standing: RoomStanding = .present,
        messageActions: MessageActions? = nil,
        partnerFocus: FocusStatusBody? = nil
    ) {
        self.init(
            room: room, transcript: messages.map(TranscriptEntry.message),
            pendingJoinCount: pendingJoinCount, uncheckedCount: uncheckedCount, onSend: onSend,
            onAttach: onAttach, onHide: onHide,
            onSeen: onSeen,
            messageDelay: messageDelay, onInvite: onInvite, onReviewJoins: onReviewJoins,
            onRoomAccess: onRoomAccess, onRoomNotifications: onRoomNotifications,
            onRoomMembers: onRoomMembers, onActiveSync: onActiveSync, standing: standing,
            messageActions: messageActions, partnerFocus: partnerFocus)
    }

    var items: [TranscriptItem] { ConversationLayout.items(from: entries) }
    var noticePositions: [EntryHash: NoticeRunPosition] {
        ConversationLayout.noticePositions(in: items)
    }
    var messages: [Message] { entries.compactMap(\.message) }

    public var body: some View {
        VStack(spacing: 0) {
            if let repair, let onDismissRepair {
                HistoryRepairBanner(status: repair, onDismiss: onDismissRepair)
                    .transition(.opacity)
            }
            SoloCheckLine(
                state: soloCheck, onAnswer: onAnswerWhoYouAreTalkingTo, phrase: soloPhrase)
            if let heldRestore, let onLetHistoryThrough, let onRefuseHistory {
                HeldRestorePrompt(
                    held: heldRestore,
                    onLetThrough: { await onLetHistoryThrough(heldRestore.person) },
                    onRefuse: { await onRefuseHistory(heldRestore.person) })
                    .transition(.opacity)
            }
            if let outpostReview, let onPostponeReview {
                OutpostReviewPrompt(
                    review: outpostReview,
                    onReview: { reviewing = outpostReview },
                    onLater: onPostponeReview)
                    .transition(.opacity)
            }
            transcript
                .environment(\.showsRunAuthors, !room.isDirect)
            switch standing {
            case .present:
                if soloCheck.closesTheComposer {
                    SoloCheckNotice(
                        state: soloCheck,
                        onAnswer: onAnswerWhoYouAreTalkingTo,
                        onAskAgain: onAskWhoYouAreTalkingTo,
                        partner: room.partner.map { Member(id: $0, displayName: room.name) },
                        onBlock: messageActions?.block.map { block in
                            { person in await block(person) }
                        },
                        onStopRequiring: onStopRequiringSoloCheck,
                        phrase: soloPhrase)
                } else {
                    composer
                }
            case .removed(let by): removedNotice(by: by)
            case .left: leftNotice
            }
        }
        .animation(reduceMotion ? nil : .default, value: repair)
        .animation(reduceMotion ? nil : .default, value: outpostReview)
        .animation(reduceMotion ? nil : .default, value: heldRestore)
        .sheet(item: $reviewing) { review in
            OutpostReviewSheet(
                review: review, onChoose: { person, choice in
                    await onOutpostChoice?(person, choice, review.room)
                })
        }
        .background(palette.background.ignoresSafeArea())
        .haptic(.commit, trigger: sent)
        .task {
            await ActiveSyncLoop.run(
                interval: .seconds(5),
                isCancelled: { Task.isCancelled },
                sleep: { try? await Task.sleep(for: $0) },
                tick: { await onActiveSync() }
            )
        }
        .navigationTitle(Text(room.name))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            // COPY BEGIN 81fd2d71 [NEEDS HUMAN REVIEW]
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(room.name)
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                    if !room.isDirect {
                        Text("^[\(room.memberCount) member](inflect: true)", bundle: .module)
                            .font(.caption2)
                            .foregroundStyle(palette.tertiaryText)
                    }
                }
            }
            // COPY END 81fd2d71
            if hasRoomActions {
                ToolbarItem(placement: .primaryAction) { roomMenu }
            }
        }
        .sheet(isPresented: $askingCheck) {
            AskWhoYouAreTalkingToSheet(
                onAsk: { holding in await onAskWhoYouAreTalkingTo?(holding) },
                phrase: soloPhrase)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .hidingTabBar()
        .navigationDestination(item: $detailing) { message in
            MessageDetailView(
                message: message, actions: messageActions ?? MessageActions(),
                readers: messageActions?.readBy(message.id, room.id) ?? [],
                isSolo: room.isDirect)
        }
    }
}
