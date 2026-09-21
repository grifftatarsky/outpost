import Foundation

public struct MemberPreferences: Hashable, Sendable, Codable {
    public var hidden: [EntryHash: Stamped<Bool>] = [:]

    public var reportsDisplaying: Stamped<Bool>?

    public var isReportingDisplaying: Bool { reportsDisplaying?.value == true }

    public var roomReportsDisplaying: [ConversationID: Stamped<Bool>] = [:]

    public mutating func setReportsDisplaying(
        _ reports: Bool?, for room: ConversationID, stamp: OrganisationStamp
    ) {
        if let reports {
            roomReportsDisplaying[room] = Stamped(reports, stamp: stamp)
        } else {
            roomReportsDisplaying[room] = nil
        }
    }

    public func reportsDisplayingAnswer(for room: ConversationID) -> Bool? {
        roomReportsDisplaying[room]?.value
    }

    public func isReportingDisplaying(in room: ConversationID) -> Bool {
        roomReportsDisplaying[room]?.value ?? isReportingDisplaying
    }

    public mutating func setReportsDisplaying(_ reports: Bool, stamp: OrganisationStamp) {
        reportsDisplaying = Stamped(reports, stamp: stamp)
    }

    public var notificationLevel: Stamped<NotificationLevel>?

    public var roomNotificationLevel: [ConversationID: Stamped<NotificationLevel>] = [:]

    public var mutedRooms: [ConversationID: Stamped<Bool>] = [:]

    public var roomNotGoneWait: [ConversationID: Stamped<NotGoneWait>] = [:]

    public var deletedRooms: [ConversationID: Stamped<Bool>] = [:]

    public var roomsDeleted: Set<ConversationID> {
        Set(deletedRooms.filter { $0.value.value }.keys)
    }

    public mutating func setDeleted(_ deleted: Bool, _ room: ConversationID, stamp: OrganisationStamp) {
        deletedRooms[room] = Stamped(deleted, stamp: stamp)
    }

    public var checkedPeople: [ParticipantID: Stamped<Date>] = [:]

    public var comparisonOffered: [ParticipantID: Stamped<Bool>] = [:]

    public func checkedAt(_ person: ParticipantID) -> Date? { checkedPeople[person]?.value }

    public mutating func setChecked(_ person: ParticipantID, at instant: Date, stamp: OrganisationStamp) {
        checkedPeople[person] = Stamped(instant, stamp: stamp)
    }

    public func wasOfferedComparison(with person: ParticipantID) -> Bool {
        comparisonOffered[person]?.value == true
    }

    public mutating func setOfferedComparison(with person: ParticipantID, stamp: OrganisationStamp) {
        comparisonOffered[person] = Stamped(true, stamp: stamp)
    }

    public func notGoneWait(for room: ConversationID) -> NotGoneWait {
        roomNotGoneWait[room]?.value ?? .standard
    }

    public mutating func setNotGoneWait(_ wait: NotGoneWait, for room: ConversationID, stamp: OrganisationStamp) {
        roomNotGoneWait[room] = Stamped(wait, stamp: stamp)
    }

    public var requiresSoloCheck: Stamped<Bool>?

    public var outpostNotifications: Stamped<OutpostNotificationChoices>?

    public var messagingNotifications: Stamped<MessagingNotificationChoices>?

    public var badges: Stamped<BadgeChoices>?

    public var outpostNotificationChoices: OutpostNotificationChoices {
        outpostNotifications?.value ?? .default
    }

    public var messagingNotificationChoices: MessagingNotificationChoices {
        messagingNotifications?.value ?? .default
    }

    public mutating func setMessagingNotifications(
        _ choices: MessagingNotificationChoices, stamp: OrganisationStamp
    ) {
        messagingNotifications = Stamped(choices, stamp: stamp)
    }

    public var badgeChoices: BadgeChoices { badges?.value ?? .default }

    public mutating func setBadges(_ choices: BadgeChoices, stamp: OrganisationStamp) {
        badges = Stamped(choices, stamp: stamp)
    }

    public mutating func setOutpostNotifications(
        _ choices: OutpostNotificationChoices, stamp: OrganisationStamp
    ) {
        outpostNotifications = Stamped(choices, stamp: stamp)
    }

    public var savedRecoveryKey: Stamped<Date>?

    public var heldSolos: [ConversationID: Stamped<Bool>] = [:]

    public var defaultNotificationLevel: NotificationLevel {
        notificationLevel?.value ?? .default
    }

    public func notificationLevel(for room: ConversationID) -> NotificationLevel {
        roomNotificationLevel[room]?.value ?? defaultNotificationLevel
    }

    public func isMuted(_ room: ConversationID) -> Bool { mutedRooms[room]?.value == true }

    public var requiresSoloCheckAnswer: Bool? { requiresSoloCheck?.value }

    public var isRequiringSoloCheck: Bool { requiresSoloCheck?.value == true }

    public var recoveryKeySavedAt: Date? { savedRecoveryKey?.value }

    public func isHoldingSolo(_ room: ConversationID) -> Bool { heldSolos[room]?.value == true }

    public var blocked: [ParticipantID: Stamped<Bool>] = [:]

    public func isBlocked(_ person: ParticipantID) -> Bool { blocked[person]?.value == true }

    public var outpostNotified: [ParticipantID: Stamped<Bool>] = [:]

    public func isNotified(about person: ParticipantID) -> Bool {
        outpostNotified[person]?.value == true
    }

    public var outpostNotifiedPeople: Set<ParticipantID> {
        Set(outpostNotified.filter { $0.value.value }.keys)
    }

    public mutating func setNotified(
        _ isNotified: Bool, about person: ParticipantID, stamp: OrganisationStamp
    ) {
        outpostNotified[person] = Stamped(isNotified, stamp: stamp)
    }

    public var blockedPeople: Set<ParticipantID> {
        Set(blocked.filter { $0.value.value }.keys)
    }

    public mutating func setBlocked(_ isBlocked: Bool, _ person: ParticipantID, stamp: OrganisationStamp) {
        blocked[person] = Stamped(isBlocked, stamp: stamp)
    }

    public func followsDefault(_ room: ConversationID) -> Bool { roomNotificationLevel[room] == nil }

    public mutating func setNotificationLevel(
        _ level: NotificationLevel, stamp: OrganisationStamp
    ) {
        notificationLevel = Stamped(level, stamp: stamp)
    }

    public mutating func setNotificationLevel(
        _ level: NotificationLevel?, for room: ConversationID, stamp: OrganisationStamp
    ) {
        guard let level else {
            roomNotificationLevel[room] = Stamped(defaultNotificationLevel, stamp: stamp)
            return
        }
        roomNotificationLevel[room] = Stamped(level, stamp: stamp)
    }

    public mutating func setRequiresSoloCheck(_ required: Bool, stamp: OrganisationStamp) {
        requiresSoloCheck = Stamped(required, stamp: stamp)
    }

    public mutating func setSavedRecoveryKey(_ when: Date, stamp: OrganisationStamp) {
        savedRecoveryKey = Stamped(when, stamp: stamp)
    }

    public mutating func setHoldingSolo(_ held: Bool, for room: ConversationID, stamp: OrganisationStamp) {
        heldSolos[room] = Stamped(held, stamp: stamp)
    }

    public mutating func setMuted(_ muted: Bool, for room: ConversationID, stamp: OrganisationStamp) {
        mutedRooms[room] = Stamped(muted, stamp: stamp)
    }

    public var displayName: Stamped<String>?
    public var blurb: Stamped<String>?

    // MARK: The one stranger

    public var anonFace: Stamped<AnonPersona.Face>?
    public var anonName: Stamped<String>?

    public var anonPersona: AnonPersona {
        AnonPersona(face: anonFace?.value ?? .question, name: anonName?.value)
    }

    public mutating func setAnonPersona(_ persona: AnonPersona, stamp: OrganisationStamp) {
        anonFace = Stamped(persona.face, stamp: stamp)
        anonName = Stamped(persona.name ?? "", stamp: stamp)
    }

    public var offersOutpostReview: Stamped<Bool>?

    public var isOfferingOutpostReview: Bool { offersOutpostReview?.value ?? true }

    public mutating func setOffersOutpostReview(_ offers: Bool, stamp: OrganisationStamp) {
        offersOutpostReview = Stamped(offers, stamp: stamp)
    }

    public var outpostConsent: Stamped<OutpostConsent>?

    public var outpostStanding: OutpostConsent? { outpostConsent?.value }

    public mutating func setOutpostConsent(_ consent: OutpostConsent, stamp: OrganisationStamp) {
        outpostConsent = Stamped(consent, stamp: stamp)
    }

    public var showsPhotoOnOutpost: Stamped<Bool>?

    public var isShowingPhotoOnOutpost: Bool { showsPhotoOnOutpost?.value ?? true }

    public mutating func setShowsPhotoOnOutpost(_ shows: Bool, stamp: OrganisationStamp) {
        showsPhotoOnOutpost = Stamped(shows, stamp: stamp)
    }

    public var sharesName: Stamped<Bool>?
    public var sharesAvatar: Stamped<Bool>?
    public var showsOthersNames: Stamped<Bool>?
    public var showsOthersAvatars: Stamped<Bool>?

    public var nicknames: [ParticipantID: Stamped<String>] = [:]

    public func nickname(for person: ParticipantID) -> String? {
        guard let name = nicknames[person]?.value, !name.isEmpty else { return nil }
        return name
    }

    public var currentNicknames: [ParticipantID: String] {
        nicknames.compactMapValues { $0.value.isEmpty ? nil : $0.value }
    }

    public mutating func setNickname(_ name: String?, for person: ParticipantID, stamp: OrganisationStamp) {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        nicknames[person] = Stamped(trimmed, stamp: stamp)
    }

    public var sharesFocus: Stamped<Bool>?
    public var showsOthersFocus: Stamped<Bool>?
    public var usesCustomFocusMessage: Stamped<Bool>?
    public var focusMessage: Stamped<String>?

    public var isSharingFocus: Bool { sharesFocus?.value == true }
    public var isShowingOthersFocus: Bool { showsOthersFocus?.value == true }
    public var usesCustomMessageForFocus: Bool { usesCustomFocusMessage?.value == true }
    public var customFocusMessage: String { focusMessage?.value ?? "" }

    public mutating func setSharesFocus(_ shares: Bool, stamp: OrganisationStamp) {
        sharesFocus = Stamped(shares, stamp: stamp)
    }

    public mutating func setShowsOthersFocus(_ shows: Bool, stamp: OrganisationStamp) {
        showsOthersFocus = Stamped(shows, stamp: stamp)
    }

    public mutating func setUsesCustomFocusMessage(_ uses: Bool, stamp: OrganisationStamp) {
        usesCustomFocusMessage = Stamped(uses, stamp: stamp)
    }

    public var toldAboutRestores: Stamped<Bool>?

    public var isToldAboutRestores: Bool { toldAboutRestores?.value != false }

    public mutating func setToldAboutRestores(_ told: Bool, stamp: OrganisationStamp) {
        toldAboutRestores = Stamped(told, stamp: stamp)
    }

    public var longPhrase: Stamped<Bool>?

    public var requiresLongPhrase: Bool { longPhrase?.value == true }

    public mutating func setRequiresLongPhrase(_ requires: Bool, stamp: OrganisationStamp) {
        longPhrase = Stamped(requires, stamp: stamp)
    }

    public func hasAnswered<Value>(_ question: KeyPath<MemberPreferences, Stamped<Value>?>) -> Bool
    {
        self[keyPath: question] != nil
    }

    public func hasAnsweredMuted(_ room: ConversationID) -> Bool { mutedRooms[room] != nil }

    public var deviceNames: [DeviceID: Stamped<String>] = [:]

    public static let deviceNameLimit = 40

    public func name(of device: DeviceID) -> String? {
        guard let name = deviceNames[device]?.value, !name.isEmpty else { return nil }
        return name
    }

    public mutating func setName(_ name: String?, for device: DeviceID, stamp: OrganisationStamp) {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        deviceNames[device] = Stamped(String(trimmed.prefix(Self.deviceNameLimit)), stamp: stamp)
    }

    public var asksPeersForHistory: Stamped<Bool>?

    public var isAskingPeersForHistory: Bool { asksPeersForHistory?.value != false }

    public mutating func setAsksPeersForHistory(_ asks: Bool, stamp: OrganisationStamp) {
        asksPeersForHistory = Stamped(asks, stamp: stamp)
    }

    public var holdsHistoryForRestores: Stamped<Bool>?

    public var isHoldingHistoryForRestores: Bool { holdsHistoryForRestores?.value == true }

    public mutating func setHoldsHistoryForRestores(_ holds: Bool, stamp: OrganisationStamp) {
        holdsHistoryForRestores = Stamped(holds, stamp: stamp)
    }

    public mutating func setFocusMessage(_ message: String, stamp: OrganisationStamp) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        focusMessage = Stamped(String(trimmed.prefix(FocusStatusBody.messageLimit)), stamp: stamp)
    }

    public var privacyCheckedUp: Stamped<Bool>?

    public var isPrivacyCheckedUp: Bool { privacyCheckedUp?.value == true }

    public var isSharingName: Bool { sharesName?.value == true }
    public var isSharingAvatar: Bool { sharesAvatar?.value == true }
    public var isShowingOthersNames: Bool { showsOthersNames?.value == true }
    public var isShowingOthersAvatars: Bool { showsOthersAvatars?.value == true }

    public mutating func setDisplayName(_ name: String, stamp: OrganisationStamp) {
        displayName = Stamped(name, stamp: stamp)
    }

    public mutating func setBlurb(_ blurb: String, stamp: OrganisationStamp) {
        self.blurb = Stamped(String(blurb.prefix(MemberProfileBody.blurbLimit)), stamp: stamp)
    }

    public mutating func setSharesName(_ shares: Bool, stamp: OrganisationStamp) {
        sharesName = Stamped(shares, stamp: stamp)
    }

    public mutating func setSharesAvatar(_ shares: Bool, stamp: OrganisationStamp) {
        sharesAvatar = Stamped(shares, stamp: stamp)
    }

    public mutating func setShowsOthersNames(_ shows: Bool, stamp: OrganisationStamp) {
        showsOthersNames = Stamped(shows, stamp: stamp)
    }

    public mutating func setShowsOthersAvatars(_ shows: Bool, stamp: OrganisationStamp) {
        showsOthersAvatars = Stamped(shows, stamp: stamp)
    }

    public mutating func setPrivacyCheckedUp(_ done: Bool, stamp: OrganisationStamp) {
        privacyCheckedUp = Stamped(done, stamp: stamp)
    }

    public var supporterYearClaimed: Stamped<Date>?
    public var supporterYearStarted: Stamped<Date>?
    public var showsSupporterBadge: Stamped<Bool>?
    public var sharesSupporterBadge: Stamped<Bool>?

    public var isShowingSupporterBadge: Bool { showsSupporterBadge?.value == true }

    public var isSharingSupporterBadge: Bool {
        (sharesSupporterBadge ?? showsSupporterBadge)?.value == true
    }

    public mutating func claimSupporterYear(at date: Date, stamp: OrganisationStamp) {
        guard supporterYearClaimed == nil else { return }
        supporterYearClaimed = Stamped(date, stamp: stamp)
    }

    public mutating func startSupporterYear(at date: Date, stamp: OrganisationStamp) {
        guard supporterYearStarted == nil else { return }
        supporterYearStarted = Stamped(date, stamp: stamp)
    }

    #if DEBUG
        public mutating func forgetSupporterYear() {
            supporterYearClaimed = nil
            supporterYearStarted = nil
            showsSupporterBadge = nil
            sharesSupporterBadge = nil
        }
    #endif

    public mutating func setShowsSupporterBadge(_ shows: Bool, stamp: OrganisationStamp) {
        showsSupporterBadge = Stamped(shows, stamp: stamp)
    }

    public mutating func setSharesSupporterBadge(_ shares: Bool, stamp: OrganisationStamp) {
        sharesSupporterBadge = Stamped(shares, stamp: stamp)
    }

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case hidden, reportsDisplaying, roomReportsDisplaying, notificationLevel, roomNotificationLevel, mutedRooms, blocked
        case roomNotGoneWait, checkedPeople, comparisonOffered, deletedRooms
        case requiresSoloCheck, heldSolos
        case outpostNotified
        case displayName, blurb, sharesName, sharesAvatar, showsOthersNames, showsOthersAvatars
        case anonFace, anonName, outpostConsent, offersOutpostReview, showsPhotoOnOutpost
        case privacyCheckedUp, nicknames
        case sharesFocus, showsOthersFocus, usesCustomFocusMessage, focusMessage
        case savedRecoveryKey, outpostNotifications, messagingNotifications, badges
        case toldAboutRestores, holdsHistoryForRestores, asksPeersForHistory
        case longPhrase
        case deviceNames
        case supporterYearClaimed, supporterYearStarted, showsSupporterBadge, sharesSupporterBadge
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hidden =
            try container.decodeIfPresent([EntryHash: Stamped<Bool>].self, forKey: .hidden) ?? [:]
        reportsDisplaying =
            try container.decodeIfPresent(Stamped<Bool>.self, forKey: .reportsDisplaying)
        roomReportsDisplaying =
            try container.decodeIfPresent(
                [ConversationID: Stamped<Bool>].self, forKey: .roomReportsDisplaying) ?? [:]
        notificationLevel =
            try container.decodeIfPresent(Stamped<NotificationLevel>.self, forKey: .notificationLevel)
        roomNotificationLevel =
            try container.decodeIfPresent(
                [ConversationID: Stamped<NotificationLevel>].self, forKey: .roomNotificationLevel) ?? [:]
        mutedRooms =
            try container.decodeIfPresent([ConversationID: Stamped<Bool>].self, forKey: .mutedRooms) ?? [:]
        roomNotGoneWait =
            try container.decodeIfPresent(
                [ConversationID: Stamped<NotGoneWait>].self, forKey: .roomNotGoneWait) ?? [:]
        deletedRooms =
            try container.decodeIfPresent([ConversationID: Stamped<Bool>].self, forKey: .deletedRooms) ?? [:]
        checkedPeople =
            try container.decodeIfPresent(
                [ParticipantID: Stamped<Date>].self, forKey: .checkedPeople) ?? [:]
        comparisonOffered =
            try container.decodeIfPresent(
                [ParticipantID: Stamped<Bool>].self, forKey: .comparisonOffered) ?? [:]
        requiresSoloCheck =
            try container.decodeIfPresent(Stamped<Bool>.self, forKey: .requiresSoloCheck)
        heldSolos =
            try container.decodeIfPresent([ConversationID: Stamped<Bool>].self, forKey: .heldSolos) ?? [:]
        blocked =
            try container.decodeIfPresent([ParticipantID: Stamped<Bool>].self, forKey: .blocked) ?? [:]
        outpostNotified =
            try container.decodeIfPresent(
                [ParticipantID: Stamped<Bool>].self, forKey: .outpostNotified) ?? [:]
        displayName = try container.decodeIfPresent(Stamped<String>.self, forKey: .displayName)
        blurb = try container.decodeIfPresent(Stamped<String>.self, forKey: .blurb)
        anonFace = try container.decodeIfPresent(Stamped<AnonPersona.Face>.self, forKey: .anonFace)
        anonName = try container.decodeIfPresent(Stamped<String>.self, forKey: .anonName)
        outpostConsent =
            try container.decodeIfPresent(Stamped<OutpostConsent>.self, forKey: .outpostConsent)
        offersOutpostReview =
            try container.decodeIfPresent(Stamped<Bool>.self, forKey: .offersOutpostReview)
        showsPhotoOnOutpost =
            try container.decodeIfPresent(Stamped<Bool>.self, forKey: .showsPhotoOnOutpost)
        savedRecoveryKey =
            try container.decodeIfPresent(Stamped<Date>.self, forKey: .savedRecoveryKey)
        outpostNotifications =
            try container.decodeIfPresent(
                Stamped<OutpostNotificationChoices>.self, forKey: .outpostNotifications)
        messagingNotifications =
            try container.decodeIfPresent(
                Stamped<MessagingNotificationChoices>.self, forKey: .messagingNotifications)
        badges = try container.decodeIfPresent(Stamped<BadgeChoices>.self, forKey: .badges)
        sharesName = try container.decodeIfPresent(Stamped<Bool>.self, forKey: .sharesName)
        sharesAvatar = try container.decodeIfPresent(Stamped<Bool>.self, forKey: .sharesAvatar)
        showsOthersNames = try container.decodeIfPresent(Stamped<Bool>.self, forKey: .showsOthersNames)
        showsOthersAvatars =
            try container.decodeIfPresent(Stamped<Bool>.self, forKey: .showsOthersAvatars)
        privacyCheckedUp = try container.decodeIfPresent(Stamped<Bool>.self, forKey: .privacyCheckedUp)
        nicknames =
            try container.decodeIfPresent([ParticipantID: Stamped<String>].self, forKey: .nicknames) ?? [:]
        longPhrase = try container.decodeIfPresent(Stamped<Bool>.self, forKey: .longPhrase)
        toldAboutRestores =
            try container.decodeIfPresent(Stamped<Bool>.self, forKey: .toldAboutRestores)
        holdsHistoryForRestores =
            try container.decodeIfPresent(Stamped<Bool>.self, forKey: .holdsHistoryForRestores)
        asksPeersForHistory =
            try container.decodeIfPresent(Stamped<Bool>.self, forKey: .asksPeersForHistory)
        deviceNames =
            try container.decodeIfPresent([DeviceID: Stamped<String>].self, forKey: .deviceNames)
            ?? [:]
        sharesFocus = try container.decodeIfPresent(Stamped<Bool>.self, forKey: .sharesFocus)
        showsOthersFocus = try container.decodeIfPresent(Stamped<Bool>.self, forKey: .showsOthersFocus)
        usesCustomFocusMessage =
            try container.decodeIfPresent(Stamped<Bool>.self, forKey: .usesCustomFocusMessage)
        focusMessage = try container.decodeIfPresent(Stamped<String>.self, forKey: .focusMessage)
        supporterYearClaimed =
            try container.decodeIfPresent(Stamped<Date>.self, forKey: .supporterYearClaimed)
        supporterYearStarted =
            try container.decodeIfPresent(Stamped<Date>.self, forKey: .supporterYearStarted)
        showsSupporterBadge =
            try container.decodeIfPresent(Stamped<Bool>.self, forKey: .showsSupporterBadge)
        sharesSupporterBadge =
            try container.decodeIfPresent(Stamped<Bool>.self, forKey: .sharesSupporterBadge)
    }

    public func isHidden(_ entry: EntryHash) -> Bool { hidden[entry]?.value == true }

    public var hiddenEntries: Set<EntryHash> {
        Set(hidden.filter { $0.value.value }.keys)
    }

    public mutating func setHidden(_ isHidden: Bool, for entry: EntryHash, stamp: OrganisationStamp) {
        hidden[entry] = Stamped(isHidden, stamp: stamp)
    }

    public mutating func reveal(_ entries: some Sequence<EntryHash>, stamp: OrganisationStamp) {
        for entry in entries { setHidden(false, for: entry, stamp: stamp) }
    }

    public func merged(with other: MemberPreferences) -> MemberPreferences {
        var merged = self
        for (entry, flag) in other.hidden {
            merged.hidden[entry] = merged.hidden[entry].map { $0.merged(with: flag) } ?? flag
        }
        if let theirs = other.reportsDisplaying {
            merged.reportsDisplaying = merged.reportsDisplaying.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.notificationLevel {
            merged.notificationLevel = merged.notificationLevel.map { $0.merged(with: theirs) } ?? theirs
        }
        for (room, level) in other.roomNotificationLevel {
            merged.roomNotificationLevel[room] =
                merged.roomNotificationLevel[room].map { $0.merged(with: level) } ?? level
        }
        for (room, muted) in other.mutedRooms {
            merged.mutedRooms[room] = merged.mutedRooms[room].map { $0.merged(with: muted) } ?? muted
        }
        for (room, wait) in other.roomNotGoneWait {
            merged.roomNotGoneWait[room] =
                merged.roomNotGoneWait[room].map { $0.merged(with: wait) } ?? wait
        }
        for (person, checked) in other.checkedPeople {
            merged.checkedPeople[person] =
                merged.checkedPeople[person].map { $0.merged(with: checked) } ?? checked
        }
        for (person, offered) in other.comparisonOffered {
            merged.comparisonOffered[person] =
                merged.comparisonOffered[person].map { $0.merged(with: offered) } ?? offered
        }
        for (room, reports) in other.roomReportsDisplaying {
            merged.roomReportsDisplaying[room] =
                merged.roomReportsDisplaying[room].map { $0.merged(with: reports) } ?? reports
        }
        if let theirs = other.requiresSoloCheck {
            merged.requiresSoloCheck =
                merged.requiresSoloCheck.map { $0.merged(with: theirs) } ?? theirs
        }
        for (room, deleted) in other.deletedRooms {
            merged.deletedRooms[room] = merged.deletedRooms[room].map { $0.merged(with: deleted) } ?? deleted
        }
        for (room, held) in other.heldSolos {
            merged.heldSolos[room] = merged.heldSolos[room].map { $0.merged(with: held) } ?? held
        }
        for (person, flag) in other.outpostNotified {
            merged.outpostNotified[person] =
                merged.outpostNotified[person].map { $0.merged(with: flag) } ?? flag
        }
        for (person, flag) in other.blocked {
            merged.blocked[person] = merged.blocked[person].map { $0.merged(with: flag) } ?? flag
        }
        if let theirs = other.blurb {
            merged.blurb = merged.blurb.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.anonFace {
            merged.anonFace = merged.anonFace.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.anonName {
            merged.anonName = merged.anonName.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.outpostConsent {
            merged.outpostConsent = merged.outpostConsent.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.offersOutpostReview {
            merged.offersOutpostReview =
                merged.offersOutpostReview.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.showsPhotoOnOutpost {
            merged.showsPhotoOnOutpost =
                merged.showsPhotoOnOutpost.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.savedRecoveryKey {
            merged.savedRecoveryKey =
                merged.savedRecoveryKey.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.outpostNotifications {
            merged.outpostNotifications =
                merged.outpostNotifications.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.messagingNotifications {
            merged.messagingNotifications =
                merged.messagingNotifications.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.badges {
            merged.badges = merged.badges.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.displayName {
            merged.displayName = merged.displayName.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.sharesName {
            merged.sharesName = merged.sharesName.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.sharesAvatar {
            merged.sharesAvatar = merged.sharesAvatar.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.showsOthersNames {
            merged.showsOthersNames = merged.showsOthersNames.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.showsOthersAvatars {
            merged.showsOthersAvatars =
                merged.showsOthersAvatars.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.privacyCheckedUp {
            merged.privacyCheckedUp = merged.privacyCheckedUp.map { $0.merged(with: theirs) } ?? theirs
        }
        for (device, name) in other.deviceNames {
            merged.deviceNames[device] =
                merged.deviceNames[device].map { $0.merged(with: name) } ?? name
        }
        for (person, name) in other.nicknames {
            merged.nicknames[person] = merged.nicknames[person].map { $0.merged(with: name) } ?? name
        }
        if let theirs = other.sharesFocus {
            merged.sharesFocus = merged.sharesFocus.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.showsOthersFocus {
            merged.showsOthersFocus = merged.showsOthersFocus.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.usesCustomFocusMessage {
            merged.usesCustomFocusMessage =
                merged.usesCustomFocusMessage.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.focusMessage {
            merged.focusMessage = merged.focusMessage.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.longPhrase {
            merged.longPhrase = merged.longPhrase.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.toldAboutRestores {
            merged.toldAboutRestores =
                merged.toldAboutRestores.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.asksPeersForHistory {
            merged.asksPeersForHistory =
                merged.asksPeersForHistory.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.holdsHistoryForRestores {
            merged.holdsHistoryForRestores =
                merged.holdsHistoryForRestores.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.supporterYearClaimed {
            merged.supporterYearClaimed =
                merged.supporterYearClaimed.map { $0.earlier(than: theirs) } ?? theirs
        }
        if let theirs = other.supporterYearStarted {
            merged.supporterYearStarted =
                merged.supporterYearStarted.map { $0.earlier(than: theirs) } ?? theirs
        }
        if let theirs = other.showsSupporterBadge {
            merged.showsSupporterBadge =
                merged.showsSupporterBadge.map { $0.merged(with: theirs) } ?? theirs
        }
        if let theirs = other.sharesSupporterBadge {
            merged.sharesSupporterBadge =
                merged.sharesSupporterBadge.map { $0.merged(with: theirs) } ?? theirs
        }
        return merged
    }
}

public struct NameAndAvatarSharing: Hashable, Sendable {
    public var sharesName: Bool
    public var sharesAvatar: Bool
    public var showsOthersNames: Bool
    public var showsOthersAvatars: Bool

    public init(
        sharesName: Bool = false, sharesAvatar: Bool = false,
        showsOthersNames: Bool = false, showsOthersAvatars: Bool = false
    ) {
        self.sharesName = sharesName
        self.sharesAvatar = sharesAvatar
        self.showsOthersNames = showsOthersNames
        self.showsOthersAvatars = showsOthersAvatars
    }
}

extension MemberPreferences {
    public var sharing: NameAndAvatarSharing {
        NameAndAvatarSharing(
            sharesName: isSharingName, sharesAvatar: isSharingAvatar,
            showsOthersNames: isShowingOthersNames, showsOthersAvatars: isShowingOthersAvatars)
    }
}

public struct FocusSharing: Hashable, Sendable {
    public var sharesFocus: Bool
    public var showsOthersFocus: Bool
    public var usesCustomMessage: Bool
    public var customMessage: String

    public init(
        sharesFocus: Bool = false, showsOthersFocus: Bool = false,
        usesCustomMessage: Bool = false, customMessage: String = ""
    ) {
        self.sharesFocus = sharesFocus
        self.showsOthersFocus = showsOthersFocus
        self.usesCustomMessage = usesCustomMessage
        self.customMessage = customMessage
    }
}

extension MemberPreferences {
    public var focusSharing: FocusSharing {
        FocusSharing(
            sharesFocus: isSharingFocus, showsOthersFocus: isShowingOthersFocus,
            usesCustomMessage: usesCustomMessageForFocus, customMessage: customFocusMessage)
    }
}
