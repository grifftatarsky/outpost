import CarpenterKit
import CryptoKit
import Foundation

// MARK: What rings, and what stays quiet

extension AppSession {
    // MARK: Do Not Disturb

    public var focusSharing: FocusSharing { persisted.preferences.focusSharing }

    public func setFocusSharing(_ wanted: FocusSharing) async {
        let preferences = persisted.preferences
        let before = preferences.focusSharing
        let shares = preferences.hasAnswered(\.sharesFocus) == false
            || before.sharesFocus != wanted.sharesFocus
        let shows = preferences.hasAnswered(\.showsOthersFocus) == false
            || before.showsOthersFocus != wanted.showsOthersFocus
        let custom = preferences.hasAnswered(\.usesCustomFocusMessage) == false
            || before.usesCustomMessage != wanted.usesCustomMessage
        let message = before.customMessage != wanted.customMessage
        guard shares || shows || custom || message else { return }

        let stamp = stamp()
        if shares { persisted.preferences.setSharesFocus(wanted.sharesFocus, stamp: stamp) }
        if shows {
            persisted.preferences.setShowsOthersFocus(wanted.showsOthersFocus, stamp: stamp)
        }
        if custom {
            persisted.preferences.setUsesCustomFocusMessage(wanted.usesCustomMessage, stamp: stamp)
        }
        if message { persisted.preferences.setFocusMessage(wanted.customMessage, stamp: stamp) }
        await savePreferences()

        if before.sharesFocus, !wanted.sharesFocus {
            await announceOrReport("that your notifications are no longer silenced") {
                try await announceFocus(silenced: false, in: roomsToTell())
            }
        } else if wanted.sharesFocus, isSilenced {
            await announceOrReport("your Do Not Disturb status") {
                try await announceFocus(silenced: true, in: roomsToTell())
            }
        }
    }

    public func reportFocus(silenced: Bool) async {
        isSilenced = silenced
        guard persisted.preferences.isSharingFocus else { return }
        await announceOrReport("your Do Not Disturb status") {
            try await announceFocus(silenced: silenced, in: roomsToTell())
        }
    }

    public func focusStatus(of person: ParticipantID) -> FocusStatusBody? {
        guard persisted.preferences.isShowingOthersFocus, !refusesToDraw(from: person) else { return nil }
        guard let status = projection.focusStatus(of: person), status.silenced else { return nil }
        return status
    }

    public func lastFocusStatus(of author: ParticipantID, in room: ConversationID) -> FocusStatusBody? {
        projection.lastFocusStatus(of: author, in: room)
    }

    func roomsToTell() -> [ConversationID] {
        guard let me = enrolment?.identity.id else { return [] }
        return chains.keys.filter { roster(of: $0).members.contains(me) }
    }

    func announceFocus(silenced: Bool, in rooms: [ConversationID]) async throws {
        guard let me = enrolment?.identity.id else { return }
        let prefs = persisted.preferences
        let body = FocusStatusBody(
            silenced: silenced,
            message: prefs.usesCustomMessageForFocus ? prefs.customFocusMessage : nil)
        var told = 0
        for room in rooms {
            let last = projection.lastFocusStatus(of: me, in: room)
            if last == body { continue }
            if last == nil, !silenced { continue }
            try await append(try Payload.focusStatus(body), to: room)
            told += 1
        }
        Diagnostics.sync.notice(
            "focus: silenced=\(silenced, privacy: .public) told \(told, privacy: .public) room(s)")
    }

    // MARK: Notification levels

    public var notificationLevel: NotificationLevel { persisted.preferences.defaultNotificationLevel }

    public func notificationLevel(for room: ConversationID) -> NotificationLevel {
        persisted.preferences.isMuted(room) ? .nothing : persisted.preferences.notificationLevel(for: room)
    }

    public func followsDefaultNotificationLevel(_ room: ConversationID) -> Bool {
        persisted.preferences.followsDefault(room)
    }

    public func isMuted(_ room: ConversationID) -> Bool { persisted.preferences.isMuted(room) }

    public var outpostNotifications: OutpostNotificationChoices {
        persisted.preferences.outpostNotificationChoices
    }

    public var hasAnsweredOutpostNotifications: Bool {
        persisted.preferences.outpostNotifications != nil
    }

    public var messagingNotifications: MessagingNotificationChoices {
        persisted.preferences.messagingNotificationChoices
    }

    public func setMessagingNotifications(_ choices: MessagingNotificationChoices) async {
        persisted.preferences.setMessagingNotifications(choices, stamp: stamp())
        await savePreferences()
    }

    public var badgeChoices: BadgeChoices { persisted.preferences.badgeChoices }

    public var badgeNumber: Int {
        BadgeCount.of(
            rooms, outposts: outpostAuthorsWithUnseen().count, choices: badgeChoices)
    }

    public func setBadgeChoices(_ choices: BadgeChoices) async {
        persisted.preferences.setBadges(choices, stamp: stamp())
        await savePreferences()
    }

    public func setOutpostNotifications(_ choices: OutpostNotificationChoices) async {
        persisted.preferences.setOutpostNotifications(choices, stamp: stamp())
        await savePreferences()
    }

    public func setNotificationLevel(_ level: NotificationLevel) async {
        guard persisted.preferences.hasAnswered(\.notificationLevel) == false
            || persisted.preferences.defaultNotificationLevel != level else { return }
        persisted.preferences.setNotificationLevel(level, stamp: stamp())
        await savePreferences()
    }

    public func setNotificationLevel(_ level: NotificationLevel?, for room: ConversationID) async {
        persisted.preferences.setNotificationLevel(level, for: room, stamp: stamp())
        await savePreferences()
    }

    public func setMuted(_ muted: Bool, for room: ConversationID) async {
        guard persisted.preferences.hasAnsweredMuted(room) == false
            || persisted.preferences.isMuted(room) != muted else { return }
        persisted.preferences.setMuted(muted, for: room, stamp: stamp())
        await savePreferences()
    }

    func savePreferences() async {
        await persistOrReport("your settings") { try await saveState() }
        sendOwnEntries()
        refresh()
    }

    public var reportsDisplaying: Bool { persisted.preferences.isReportingDisplaying }

    public func setReportsDisplaying(_ reports: Bool) async {
        guard persisted.preferences.hasAnswered(\.reportsDisplaying) == false
            || persisted.preferences.isReportingDisplaying != reports else { return }
        persisted.preferences.setReportsDisplaying(reports, stamp: stamp())
        await savePreferences()

        for room in rooms.map(\.id)
        where persisted.preferences.reportsDisplayingAnswer(for: room) == nil {
            await announceOrReport("your read-receipt policy") {
                try await append(try Payload.readPolicy(reports: reports), to: room)
            }
        }
        refresh()
    }

    public func reportsDisplayingAnswer(for room: ConversationID) -> Bool? {
        persisted.preferences.reportsDisplayingAnswer(for: room)
    }

    public func isReportingDisplaying(in room: ConversationID) -> Bool {
        persisted.preferences.isReportingDisplaying(in: room)
    }

    public func setReportsDisplaying(_ reports: Bool?, in room: ConversationID) async {
        let before = persisted.preferences.isReportingDisplaying(in: room)
        persisted.preferences.setReportsDisplaying(reports, for: room, stamp: stamp())
        await savePreferences()

        let after = persisted.preferences.isReportingDisplaying(in: room)
        guard after != before else {
            refresh()
            return
        }
        await announceOrReport("your read-receipt policy for this room") {
            try await append(try Payload.readPolicy(reports: after), to: room)
        }
        refresh()
    }
}
