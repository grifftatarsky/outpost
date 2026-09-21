import CarpenterKit
import CryptoKit
import Foundation

// MARK: What this app will not do without being asked

extension AppSession {
    // MARK: The privacy check-up

    public var needsPrivacyCheckup: Bool {
        state == .ready && !persisted.preferences.isPrivacyCheckedUp && enrolment?.deviceIsNew != true
    }

    public var isPrivacyCheckedUp: Bool { persisted.preferences.isPrivacyCheckedUp }

    public func markPrivacyCheckedUp() async {
        guard !persisted.preferences.isPrivacyCheckedUp else { return }
        persisted.preferences.setPrivacyCheckedUp(true, stamp: stamp())
        await savePreferences()
    }

    func announceProfile(in room: ConversationID) async throws {
        if persisted.preferences.isSharingAvatar, let me = enrolment?.identity.id,
            let reference = projection.photoReference(of: me)
        {
            try await announcePhoto(reference, in: room)
        }
        if persisted.preferences.isSharingFocus, isSilenced {
            try await announceFocus(silenced: true, in: [room])
        }
        if showsSupporterBadge {
            try await announceSupporterBadge(in: [room])
        }
        guard persisted.preferences.isSharingName else { return }
        guard let enrolment, let name = ownDisplayName else { return }

        guard projection.announcedName(of: enrolment.identity.id, in: room) != name else { return }

        try await append(try Payload.memberProfile(displayName: name), to: room)
    }

    // MARK: Blocking

    public func block(_ person: ParticipantID) async {
        guard person != enrolment?.identity.id, !persisted.preferences.isBlocked(person) else { return }
        persisted.preferences.setBlocked(true, person, stamp: stamp())
        Diagnostics.sync.notice("safety: blocked \(Diagnostics.fingerprint(person.rawValue), privacy: .public)")
        await savePreferences()
    }

    public func unblock(_ person: ParticipantID) async {
        guard persisted.preferences.isBlocked(person) else { return }
        persisted.preferences.setBlocked(false, person, stamp: stamp())
        await savePreferences()
    }

    public func isBlocked(_ person: ParticipantID) -> Bool {
        persisted.preferences.isBlocked(person)
    }

    public var blockedPeople: [Member] {
        persisted.preferences.blockedPeople.map(member).sorted { $0.displayName < $1.displayName }
    }

    public func isDenyListed(_ person: ParticipantID) -> Bool {
        enforcesDenyList && denyList.contains(person)
    }

    public var isBanned: Bool {
        guard let enrolment else { return false }
        return denyList.contains(enrolment.identity.id)
    }

    func refusesToDraw(from author: ParticipantID) -> Bool {
        guard author != enrolment?.identity.id else { return false }
        return persisted.preferences.isBlocked(author) || isDenyListed(author)
    }

    func notShutOut(_ people: Set<ParticipantID>) -> Set<ParticipantID> {
        people.subtracting(shutOutAuthors())
    }

    func shutOutAuthors() -> Set<ParticipantID> {
        var authors = persisted.preferences.blockedPeople
        if enforcesDenyList {
            authors.formUnion(replica.knownParticipants.filter(denyList.contains))
        }
        authors.remove(enrolment?.identity.id ?? ParticipantID(rawValue: Data()))
        return authors
    }

    public func latestRestoreAsk() -> RestoreAsk? {
        guard persisted.preferences.isToldAboutRestores else { return nil }
        guard let me = enrolment?.identity.id else { return nil }

        for ask in persisted.restoreAsks.reversed() where ask.from != me {
            guard !refusesToDraw(from: ask.from) else { continue }
            return RestoreAsk(
                request: ask.request, person: ask.from,
                personName: member(ask.from).displayName, room: ask.room,
                roomName: ask.room.flatMap { asked in rooms.first { $0.id == asked }?.name } ?? "")
        }
        return nil
    }

    public var isToldAboutRestores: Bool { persisted.preferences.isToldAboutRestores }

    var hasAnsweredAboutRestores: Bool {
        persisted.preferences.hasAnswered(\.toldAboutRestores)
    }

    var answerStampAboutRestores: Date? { persisted.preferences.toldAboutRestores?.stamp.at }

    public var isHoldingHistoryForRestores: Bool {
        persisted.preferences.isHoldingHistoryForRestores
    }

    public var isAskingPeersForHistory: Bool { persisted.preferences.isAskingPeersForHistory }

    public func setAsksPeersForHistory(_ asks: Bool) async {
        guard persisted.preferences.hasAnswered(\.asksPeersForHistory) == false
            || persisted.preferences.isAskingPeersForHistory != asks else { return }
        persisted.preferences.setAsksPeersForHistory(asks, stamp: stamp())
        if asks, cameBackFromARecoveryKey { persisted.wantsWhatWasSaid = true }
        if !asks { persisted.wantsWhatWasSaid = false }
        await savePreferences()
        refresh()
    }

    func isHoldingBack(_ person: ParticipantID) -> Bool {
        persisted.restoreAsks.last { $0.from == person }?.hold == .held
    }

    public func heldRestores() -> [HeldRestore] {
        guard let me = enrolment?.identity.id else { return [] }
        var seen: Set<ParticipantID> = []
        var held: [HeldRestore] = []
        for ask in persisted.restoreAsks.reversed()
        where ask.hold == .held && ask.from != me && !seen.contains(ask.from) {
            seen.insert(ask.from)
            guard !refusesToDraw(from: ask.from) else { continue }
            let room = ask.room
            held.append(
                HeldRestore(
                    request: ask.request, person: ask.from,
                    personName: member(ask.from).displayName, room: room,
                    roomName: room.flatMap { asked in rooms.first { $0.id == asked }?.name } ?? "",
                    phrase: room.flatMap { asked in phrase(with: ask.from, in: asked) },
                    askedAt: ask.at))
        }
        return held.sorted { $0.askedAt < $1.askedAt }
    }

    private func phrase(with person: ParticipantID, in room: ConversationID) -> String? {
        let roster = roster(of: room)
        if let theirs = roster.requests[person] { return phrase(for: theirs) }
        guard let me = enrolment?.identity.id, let mine = roster.requests[me],
            mine.inviter == person
        else { return nil }
        return phrase(for: mine)
    }

    public func heldRestore(in room: ConversationID) -> HeldRestore? {
        let here = Set(roster(of: room).members)
        return heldRestores().first { here.contains($0.person) }
    }

    public func letHistoryThrough(to person: ParticipantID) async {
        await decideHold(.allowed, for: person)
    }

    public func refuseHistory(to person: ParticipantID) async {
        await decideHold(.refused, for: person)
    }

    private func decideHold(_ hold: RestoreHold, for person: ParticipantID) async {
        var changed = false
        for index in persisted.restoreAsks.indices
        where persisted.restoreAsks[index].from == person
            && persisted.restoreAsks[index].hold == .held
        {
            persisted.restoreAsks[index].hold = hold
            changed = true
        }
        guard changed else { return }

        if hold == .refused {
            persisted.repairDuties.removeAll {
                $0.from == person && $0.request.reason == .recovery
            }
        }
        Diagnostics.sync.notice(
            """
            recovery: \(Diagnostics.fingerprint(person.rawValue), privacy: .public) was \
            \(hold == .allowed ? "let through" : "refused", privacy: .public)
            """)
        await persistOrReport("a held restore") { try await saveState() }
        refresh()
    }


    public func setHoldsHistoryForRestores(_ holds: Bool) async {
        guard persisted.preferences.hasAnswered(\.holdsHistoryForRestores) == false
            || persisted.preferences.isHoldingHistoryForRestores != holds else { return }
        persisted.preferences.setHoldsHistoryForRestores(holds, stamp: stamp())
        if !holds {
            for index in persisted.restoreAsks.indices
            where persisted.restoreAsks[index].hold == .held {
                persisted.restoreAsks[index].hold = .allowed
            }
        }
        await savePreferences()
        refresh()
    }

    public func setToldAboutRestores(_ told: Bool) async {
        guard persisted.preferences.hasAnswered(\.toldAboutRestores) == false
            || persisted.preferences.isToldAboutRestores != told else { return }
        persisted.preferences.setToldAboutRestores(told, stamp: stamp())
        await savePreferences()
        refresh()
    }

    // MARK: The one stranger, and the deal that raises them

    public var anonPersona: AnonPersona { persisted.preferences.anonPersona }

    public func setAnonPersona(_ persona: AnonPersona) async {
        persisted.preferences.setAnonPersona(persona, stamp: stamp())
        foldChanged()
        await savePreferences()
    }

    public var outpostConsent: OutpostConsent? { persisted.preferences.outpostStanding }

    public func setOutpostConsent(_ consent: OutpostConsent) async {
        persisted.preferences.setOutpostConsent(consent, stamp: stamp())
        await savePreferences()
    }

    public var offersOutpostReview: Bool { persisted.preferences.isOfferingOutpostReview }

    public func setOffersOutpostReview(_ offers: Bool) async {
        persisted.preferences.setOffersOutpostReview(offers, stamp: stamp())
        await savePreferences()
    }
}
