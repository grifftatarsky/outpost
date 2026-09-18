import CarpenterKit
import Foundation

extension AppSession {
    public var supporterStanding: SupporterStanding {
        let prefs = persisted.preferences
        return SupporterStanding.of(
            claimedAt: prefs.supporterYearClaimed?.value,
            startedAt: prefs.supporterYearStarted?.value,
            channel: distribution, now: clock.now)
    }

    public var isSupporter: Bool { supporterStanding.isSupporter }

    public var canClaimSupporterYear: Bool {
        distribution.offersTheTestFlightYear && persisted.preferences.supporterYearClaimed == nil
    }

    public var hasAnsweredSupporterBadge: Bool {
        persisted.preferences.showsSupporterBadge != nil
    }

    public var showsSupporterBadge: Bool {
        isSupporter && persisted.preferences.isShowingSupporterBadge
    }

    public var supporterBadges: Set<ParticipantID> {
        var shown = projection.supporterBadges.filter { !refusesToDraw(from: $0) }
        if let me = enrolment?.identity.id {
            if showsSupporterBadge { shown.insert(me) } else { shown.remove(me) }
        }
        return shown
    }

    #if DEBUG
        public func forgetSupporterYear() async {
            persisted.preferences.forgetSupporterYear()
            await savePreferences()
        }
    #endif

    public func claimSupporterYear() async {
        guard canClaimSupporterYear else { return }
        persisted.preferences.claimSupporterYear(at: clock.now, stamp: stamp())
        Diagnostics.sync.notice("supporter: claimed the free year on \(self.distribution.rawValue, privacy: .public)")
        await savePreferences()
    }

    public func setShowsSupporterBadge(_ shows: Bool) async {
        guard persisted.preferences.showsSupporterBadge?.value != shows else { return }
        persisted.preferences.setShowsSupporterBadge(shows, stamp: stamp())
        await savePreferences()
        await announceOrReport("your Supporter badge") {
            try await announceSupporterBadge(in: roomsToTell())
        }
    }

    public func refreshSupporterStanding() async {
        guard state == .ready else { return }
        let prefs = persisted.preferences
        if distribution == .appStore, prefs.supporterYearClaimed != nil, prefs.supporterYearStarted == nil {
            persisted.preferences.startSupporterYear(at: clock.now, stamp: stamp())
            Diagnostics.sync.notice("supporter: the free year starts now, on the App Store build")
            await savePreferences()
        }
        await announceOrReport("that your Supporter badge has lapsed") {
            try await announceSupporterBadge(in: roomsToTell())
        }
    }

    func announceSupporterBadge(in rooms: [RoomID]) async throws {
        guard let me = enrolment?.identity.id else { return }
        let shows = showsSupporterBadge
        var told = 0
        for room in rooms {
            let last = projection.lastSupporterBadge(of: me, in: room)
            if last?.shows == shows { continue }
            if last == nil, !shows { continue }
            try await append(try Payload.supporterBadge(shows: shows), to: room)
            told += 1
        }
        if told > 0 {
            Diagnostics.sync.notice(
                "supporter: badge shows=\(shows, privacy: .public) told \(told, privacy: .public) room(s)")
        }
    }
}
