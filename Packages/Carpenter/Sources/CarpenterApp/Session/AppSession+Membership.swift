import CarpenterKit
import CryptoKit
import Foundation

// MARK: Who is in a room, and how they got there

extension AppSession {
    // MARK: Membership

    func epochsHeld(in room: RoomID) -> Int { chains[room]?.knownEpochs.count ?? 0 }

    func knowsIdentity(of person: ParticipantID) -> Bool {
        replica.registry(for: person)?.identity != nil
    }

    public func roster(of room: RoomID) -> RoomRoster {
        if let known = cachedRosters[room] { return known }
        let built = projection.roster(of: room, opening: payloadOpener())
        cachedRosters[room] = built
        return built
    }

    func payloadOpener() -> (RenderedEntry) -> Payload? {
        let byHash = entriesByHash
        let open = entryOpener()
        return { rendered in
            guard let entry = byHash[rendered.id] else { return nil }
            return open(entry)
        }
    }

    func entryOpener() -> (Entry) -> Payload? {
        let chains = chains
        let identity = enrolment?.identity
        let replica = replica
        return { entry in
            if let room = entry.room, let chain = chains[room],
                let opened = entry.opened(using: chain)
            {
                return opened
            }
            if let opened = chains.values.lazy.compactMap(entry.opened(using:)).first {
                return opened
            }
            guard entry.hasSecondReader, let identity,
                let keys = replica.registry(for: entry.author)?.identity,
                let secret = try? PairwiseSecret.derive(mine: identity, theirs: keys)
            else { return nil }
            return entry.opened(pairwise: secret, wall: RoomID.outpost(of: entry.author))
        }
    }

    func pairwiseSecret(with person: ParticipantID) -> PairwiseSecret? {
        if let known = cachedPairwise[person] { return known }
        guard let identity = enrolment?.identity,
            let keys = replica.registry(for: person)?.identity,
            let secret = try? PairwiseSecret.derive(mine: identity, theirs: keys)
        else { return nil }
        cachedPairwise[person] = secret
        return secret
    }

    public func awaitingConfirmation(in room: RoomID) -> [MembershipAttestation] {
        guard let me = enrolment?.identity.id else { return [] }
        return roster(of: room).awaitingConfirmation(by: me)
    }

    public func publicKeys(of person: ParticipantID) -> IdentityPublicKeys? {
        replica.registry(for: person)?.identity
    }

    public func connections(excluding excluded: Set<ParticipantID> = []) -> [Connection] {
        guard let me = enrolment?.identity.id else { return [] }
        let named = projection.naming()
        return Connection.all(
            rosters: rooms.map { room in
                let roster = roster(of: room.id)
                return roster.members.union(roster.requests.keys)
            },
            outpostAuthors: outpostAuthors(),
            viewer: me,
            excluding: excluded,
            naming: named)
    }

    public func pendingInvitations(in room: RoomID) -> [RoomRoster.PendingInvitation] {
        roster(of: room).pendingInvitations(at: clock.now)
    }

    public func lapsedInvitations(in room: RoomID) -> [RoomRoster.PendingInvitation] {
        roster(of: room).lapsedInvitations(at: clock.now)
    }

    public var now: Date { clock.now }

    public func attest(
        code: JoinerCode, joining room: RoomID,
        lasting lifetime: InvitationLifetime = .aDay,
        sharingHistory: Bool = true
    ) async throws -> MembershipAttestation {
        guard let enrolment else { throw AppSessionError.noIdentity }

        let attestation = try MembershipAttestation.issue(
            joining: room, code: code, by: enrolment.identity, at: clock.now,
            lasting: lifetime, requiring: phraseLengthThisMemberRequires,
            sharesHistory: sharingHistory)

        try await append(try Payload.joinRequest(attestation), to: room)
        return attestation
    }

    public func rescind(_ attestation: MembershipAttestation) async throws {
        guard let enrolment else { throw AppSessionError.noIdentity }
        let roster = roster(of: attestation.room)
        guard roster.members.contains(enrolment.identity.id) else {
            throw MembershipError.notAMember
        }
        guard !roster.members.contains(attestation.joiner) else {
            throw MembershipError.alreadyInTheRoom
        }
        try await append(try Payload.invitationRescinded(of: attestation), to: attestation.room)
    }

    func prepareCodeForSharing(replacingSpent spent: Bool = false) {
        guard enrolment != nil else { return }
        guard spent || codeForSharing.isEmpty else { return }
        codeForSharing = identityCode()
    }

    public func identityCode() -> String {
        guard let keys = enrolment?.identity.publicKeys else { return "" }

        let nonce = JoinCommitment.nonce()
        let commitment = JoinCommitment.of(nonce)
        remember(nonce, opening: commitment)

        let code = JoinerCode(
            keys: keys, commitment: commitment, requires: phraseLengthThisMemberRequires)
        return (try? code.encoded()) ?? ""
    }

    public var phraseLengthThisMemberRequires: PhraseLength {
        persisted.preferences.requiresLongPhrase ? .strict : .standard
    }

    func remember(_ nonce: Data, opening commitment: Data) {
        guard !commitment.isEmpty else { return }
        persisted.phraseNonces[commitment.base64EncodedString()] = nonce
        Task { try? await saveState() }
    }

    func nonce(opening commitment: Data) -> Data? {
        persisted.phraseNonces[commitment.base64EncodedString()]
    }

    public func phrase(for attestation: MembershipAttestation) -> String? {
        attestation.verificationPhrase(opening: nonce(opening: attestation.joinerCommitment))
    }

    public func invite(
        joinerCode: String, joining room: RoomID, mailbox: URL?,
        lasting lifetime: InvitationLifetime = .aDay,
        sharingHistory: Bool = true
    ) async throws -> Invite {
        let code = try JoinerCode.decoded(from: joinerCode)

        guard code.participantID != enrolment?.identity.id else {
            throw AppSessionError.thatIsYou
        }

        let attestation = try await attest(
            code: code, joining: room, lasting: lifetime, sharingHistory: sharingHistory)
        return Invite(attestation: attestation, mailbox: mailbox)
    }

    public func inspect(inviteCode: String) -> Invite? {
        guard let invite = try? Invite.decoded(from: inviteCode),
            invite.attestation.joiner == enrolment?.identity.id,
            (try? invite.attestation.verifyAsJoiner(at: clock.now)) != nil
        else { return nil }
        return invite
    }

    @discardableResult
    public func redeem(inviteCode: String) async throws -> Invite {
        guard let invite = inspect(inviteCode: inviteCode) else {
            throw MembershipError.malformedInvite
        }

        guard invite.attestation.inviterKeys.participantID != enrolment?.identity.id else {
            throw AppSessionError.thatIsYou
        }

        try await accept(invite.attestation, from: invite.attestation.inviterKeys)
        return invite
    }

    public func accept(
        _ attestation: MembershipAttestation, from inviterKeys: IdentityPublicKeys
    ) async throws {
        guard let enrolment else { throw AppSessionError.noIdentity }
        guard attestation.joiner == enrolment.identity.id else {
            throw MembershipError.wrongJoiner
        }
        try attestation.verify(against: inviterKeys, at: clock.now)

        replica.introduce(inviterKeys)
        if !persisted.knownKeys.contains(inviterKeys) { persisted.knownKeys.append(inviterKeys) }
        if !persisted.knownRooms.contains(attestation.room) {
            persisted.knownRooms.append(attestation.room)
        }
        let wasDeleted = replica.closedRooms.contains(attestation.room)
        reopen(attestation.room)
        if !persisted.acceptedInvitations.contains(where: {
            $0.attestation.signature == attestation.signature
        }) {
            persisted.acceptedInvitations.append(
                AcceptedInvitation(attestation: attestation, confirmedAt: clock.now))
        }
        let request = RepairRequest(
            authors: [inviterKeys.participantID, enrolment.identity.id],
            heads: replica.heads(
                of: [inviterKeys.participantID, enrolment.identity.id],
                inRoom: attestation.room, onWallOf: nil),
            gaps: [], room: attestation.room)
        persisted.repairs.removeAll { $0.room == attestation.room && $0.quiet }
        persisted.repairs.append(
            HistoryRepair(
                id: request.id, room: attestation.room, startedAt: clock.now, request: request,
                asked: [inviterKeys.participantID], quiet: true))
        try await saveState()
        refresh()
        if wasDeleted { sendOwnEntries() }

        if let shared = try? JoinerCode.decoded(from: codeForSharing),
            shared.commitment == attestation.joinerCommitment
        {
            prepareCodeForSharing(replacingSpent: true)
        }
    }

    func confirmationsOwed() -> [(to: ParticipantID, body: JoinConfirmedBody)] {
        guard let enrolment else { return [] }
        return outstandingInvitations().compactMap { accepted in
            guard let opening = nonce(opening: accepted.attestation.joinerCommitment),
                let body = try? JoinConfirmedBody.signed(
                    confirming: accepted.attestation, opening: opening, by: enrolment.identity)
            else { return nil }
            return (accepted.attestation.inviter, body)
        }
    }

    func invitationsOutsideTheirRoom() -> [AcceptedInvitation] {
        guard enrolment != nil else { return [] }
        let held = Set(rooms.map(\.id))
        return persisted.acceptedInvitations.filter { !held.contains($0.attestation.room) }
    }

    private func outstandingInvitations() -> [AcceptedInvitation] {
        let now = clock.now
        return persisted.acceptedInvitations.filter {
            !roomsThisMemberIsIn.contains($0.attestation.room) && $0.attestation.expiresAt > now
        }
    }

    public var awaitingAdmission: [AwaitingAdmission] {
        let now = clock.now
        return invitationsOutsideTheirRoom()
            .map {
                AwaitingAdmission(
                    room: $0.attestation.room,
                    invitedBy: member($0.attestation.inviter),
                    phrase: phrase(for: $0.attestation),
                    confirmedAt: $0.confirmedAt,
                    expiresAt: $0.attestation.expiresAt,
                    hasLapsed: $0.attestation.hasLapsed(at: now))
            }
            .sorted { $0.confirmedAt < $1.confirmedAt }
    }

    // MARK: Who you are talking to, in a solo

    public func soloCheck(in room: RoomID) -> SoloCheck {
        projection.soloCheck(in: room, opening: payloadOpener())
    }

    public var hasAnsweredSoloCheckQuestion: Bool {
        persisted.preferences.requiresSoloCheckAnswer != nil
    }

    public var requiresSoloCheck: Bool { persisted.preferences.isRequiringSoloCheck }

    public func isHoldingSolo(_ room: RoomID) -> Bool {
        persisted.preferences.isHoldingSolo(room)
    }

    public func setRequiresSoloCheck(_ required: Bool) async {
        persisted.preferences.setRequiresSoloCheck(required, stamp: stamp())
        await savePreferences()
    }

    public var requiresLongPhrase: Bool { persisted.preferences.requiresLongPhrase }

    public func setRequiresLongPhrase(_ required: Bool) async {
        persisted.preferences.setRequiresLongPhrase(required, stamp: stamp())
        await savePreferences()
    }

    public func canCheckWhoTheyAreTalkingTo(in room: RoomID) -> Bool {
        rooms.first { $0.id == room }?.isDirect ?? false
    }

    public func askWhoYouAreTalkingTo(in room: RoomID, holding: Bool) async throws {
        guard canCheckWhoTheyAreTalkingTo(in: room) else { throw AppSessionError.cannotWriteThere }
        persisted.preferences.setHoldingSolo(holding, for: room, stamp: stamp())
        await savePreferences()
        try await append(try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil)), to: room)
    }

    public func answerWhoYouAreTalkingTo(in room: RoomID, matched: Bool) async throws {
        guard let me = enrolment?.identity.id else { throw AppSessionError.noIdentity }
        let asks = projection.soloChecksAwaiting(in: room, opening: payloadOpener())
        for ask in asks where !(matched && ask.asker == me) {
            try await append(
                try Payload.soloCheck(
                    SoloCheckBody(move: matched ? .confirmed : .refused, answering: ask.id)),
                to: room)
        }
        if persisted.preferences.isHoldingSolo(room) {
            persisted.preferences.setHoldingSolo(false, for: room, stamp: stamp())
            await savePreferences()
        }
    }

    func raiseSoloChecksOwed() async {
        guard requiresSoloCheck else { return }
        for solo in rooms where solo.isDirect && solo.memberCount > 1 {
            let room = solo.id
            let check = soloCheck(in: room)
            guard !check.isConfirmed, !check.isOutstanding, !check.isBlocked else { continue }
            do {
                try await append(
                    try Payload.soloCheck(SoloCheckBody(move: .asked, answering: nil)), to: room)
            } catch {
                Diagnostics.sync.error(
                    "solo: could not raise the check this member requires: \(String(describing: error), privacy: .public)")
            }
        }
    }

    public func canWrite(in room: RoomID) -> Bool {
        guard rooms.contains(where: { $0.id == room && $0.isDirect && $0.memberCount > 1 })
        else { return true }
        let check = soloCheck(in: room)
        if check.isBlocked { return false }
        if check.isOutstanding, persisted.preferences.isHoldingSolo(room) { return false }
        if requiresSoloCheck, !check.isConfirmed { return false }
        return true
    }

    public var managedTags: [ManagedTag] {
        let inviting = rooms.map(\.id).filter { !pendingInvitations(in: $0).isEmpty }
        let waiting = awaitingAdmission.map(\.room)
        let invited = ManagedTag(kind: .invited, rooms: Set(inviting).union(waiting))
        return [invited].filter(\.isWorthShowing)
    }

    public func ownInvitation(to room: RoomID) -> AcceptedInvitation? {
        persisted.acceptedInvitations.last { $0.attestation.room == room }
    }

    func relayJoinConfirmations(_ confirmations: [JoinConfirmedBody]) async {
        guard let me = enrolment?.identity.id, !confirmations.isEmpty else { return }

        let projected = projection
        let opener = payloadOpener()
        let collectedAt = clock.now

        var owed: [(room: RoomID, body: JoinConfirmedBody)] = []
        for summary in projected.summaries() {
            let roster = projected.roster(of: summary.id, opening: opener)
            var claimed: Set<ParticipantID> = []
            for body in confirmations {
                guard let attestation = roster.requests[body.joiner],
                    attestation.inviter == me,
                    attestation.signature == body.invitation,
                    roster.isOpen(attestation),
                    !attestation.hasLapsed(at: collectedAt),
                    !roster.hasConfirmed(attestation),
                    claimed.insert(body.joiner).inserted,
                    (try? body.verify(confirming: attestation)) != nil
                else { continue }
                remember(body.nonce, opening: attestation.joinerCommitment)
                owed.append((summary.id, body))
            }
        }

        for (room, body) in owed {
            do {
                try await append(try Payload.joinConfirmed(body), to: room)

                let roster = roster(of: room)
                if roster.access.admitsOnInvitation, roster.members.contains(body.joiner) {
                    try await advanceEpoch(of: room)
                }
            } catch {
                Diagnostics.sync.error(
                    "join: could not relay a confirmation: \(String(describing: error), privacy: .public)")
            }
        }
    }

    public func epoch(of room: RoomID) -> EpochNumber? { chains[room]?.highestKnownEpoch }

    public func member(_ id: ParticipantID) -> Member { projection.member(id) }

    public func announcedName(of author: ParticipantID, in room: RoomID) -> String? {
        projection.announcedName(of: author, in: room)
    }

    public func announcedPhoto(of author: ParticipantID, in room: RoomID) -> AttachmentReference?? {
        projection.announcedPhoto(of: author, in: room)
    }

    public func whoRefused(_ joiner: ParticipantID, in room: RoomID) -> [Member] {
        roster(of: room).whoRefused(joiner).map(member).sorted { $0.displayName < $1.displayName }
    }

    public func access(of room: RoomID) -> RoomAccess {
        roster(of: room).access
    }

    public func setAccess(_ access: RoomAccess, in room: RoomID) async throws {
        guard let enrolment else { throw AppSessionError.noIdentity }
        guard roster(of: room).founder == enrolment.identity.id else {
            throw MembershipError.notTheFounder
        }
        try await append(try Payload.roomAccess(access), to: room)
    }

    public func remove(_ person: ParticipantID, from room: RoomID) async throws {
        guard let enrolment else { throw AppSessionError.noIdentity }
        let roster = roster(of: room)

        guard roster.members.contains(enrolment.identity.id) else {
            throw MembershipError.notAMember
        }
        guard person != enrolment.identity.id else { throw MembershipError.cannotRemoveYourself }
        guard roster.members.contains(person) else { throw MembershipError.notAMember }

        try await oweEpochTurn(in: room)
        try await append(try Payload.removal(of: person), to: room)
        try await turnOwedEpoch(in: room)
    }

    public func leave(_ room: RoomID) async throws {
        guard let enrolment else { throw AppSessionError.noIdentity }

        guard roster(of: room).members.contains(enrolment.identity.id) else {
            throw MembershipError.notAMember
        }

        try await append(try Payload.departure(), to: room)
    }

    public func standing(in room: RoomID) -> RoomStanding {
        guard let enrolment else { return .present }
        let roster = roster(of: room)
        if let removal = roster.removal(of: enrolment.identity.id) {
            return .removed(by: member(removal.by))
        }
        if roster.departure(of: enrolment.identity.id) != nil { return .left }
        return .present
    }

    func turnKeysOwedToDepartures() async {
        guard let me = enrolment?.identity.id else { return }

        for room in persisted.knownRooms where chains[room] != nil {
            let roster = roster(of: room)
            guard roster.keyTurner == me else { continue }

            for departure in roster.departures.values
            where !persisted.answeredDepartures.contains(departure.entry) {
                do {
                    try await advanceEpoch(of: room)
                    persisted.answeredDepartures.insert(departure.entry)
                    await persistOrReport("that this room's key has been turned") {
                        try await saveState()
                    }
                    Diagnostics.sync.notice(
                        "mailbox sync: turned a room's key because somebody left it")
                } catch {
                    Diagnostics.sync.error(
                        "could not turn a room's key after somebody left — they can still read what is said in it (\(String(describing: error), privacy: .public))")
                }
            }
        }
    }

    public func greeting(for room: RoomID) -> RoomGreeting? {
        guard let enrolment, !persisted.greetedRooms.contains(room) else { return nil }
        let roster = roster(of: room)
        guard roster.members.contains(enrolment.identity.id) else { return nil }
        guard roster.founder != enrolment.identity.id else { return nil }
        guard let stored = projection.name(of: room) else { return nil }

        let named = projection.naming()
        let invitedBy = roster.requests[enrolment.identity.id].map { named($0.inviter) }
        let isSolo = projection.kind(of: room) == .solo
        let name = isSolo ? invitedBy?.displayName ?? stored : stored
        return RoomGreeting(
            id: room,
            name: name,
            invitedBy: invitedBy,
            members: roster.members
                .map(named)
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending },
            access: roster.access,
            isDirect: isSolo)
    }

    public func acknowledgeGreeting(for room: RoomID) async {
        guard !persisted.greetedRooms.contains(room) else { return }
        persisted.greetedRooms.append(room)
        await persistOrReport("which rooms you have been introduced to") {
            try await saveState()
        }
        refresh()
    }

    public func removal(from room: RoomID) -> RoomRoster.Removal? {
        guard let enrolment else { return nil }
        return roster(of: room).removal(of: enrolment.identity.id)
    }

    public func pendingJoins(in room: RoomID) -> [MembershipAttestation] {
        guard let enrolment else { return [] }
        return roster(of: room).pending(for: enrolment.identity.id, at: clock.now)
    }

    public func decide(
        on attestation: MembershipAttestation, admit: Bool
    ) async throws {
        guard let enrolment else { throw AppSessionError.noIdentity }
        let roster = roster(of: attestation.room)

        if admit {
            try roster.verify(
                attestation,
                inviterKeys: try inviterKeys(for: attestation, in: roster),
                at: clock.now,
                allowingExpired: roster.members.contains(attestation.joiner)
                    || roster.hasConfirmed(attestation)
            )
            replica.introduce(attestation.joinerKeys)
        }

        try await append(
            try Payload.admission(
                of: attestation.joiner, admitted: admit, invitation: attestation.signature),
            to: attestation.room)

        if admit, attestation.inviter == enrolment.identity.id,
            !roster.access.admitsOnInvitation
        {
            try await advanceEpoch(of: attestation.room)
        }
    }

    func settleHistoryFloors() async {
        guard let me = enrolment?.identity.id else { return }
        for room in persisted.knownRooms {
            let roster = roster(of: room)
            for person in roster.members {
                guard let attestation = roster.invitation(of: person),
                    !attestation.sharesHistory,
                    attestation.inviter == me,
                    roster.historyFloor(of: person) == nil
                else { continue }
                do {
                    try await closeHistoryTo(person, invitedOn: attestation, in: room)
                    Diagnostics.sync.notice(
                        "membership: a new member starts from today; the key turned and the room was restated")
                } catch {
                    Diagnostics.sync.error(
                        "membership: could not close history to a new member (\(String(describing: error), privacy: .public))")
                }
            }
        }
    }

    private func closeHistoryTo(
        _ person: ParticipantID, invitedOn attestation: MembershipAttestation, in room: RoomID
    ) async throws {
        try await advanceEpoch(of: room)
        guard let epoch = chains[room]?.highestKnownEpoch else { throw AppSessionError.unknownRoom }

        try await append(
            try Payload.admission(
                of: person, admitted: true, invitation: attestation.signature,
                sinceEpoch: epoch.rawValue),
            to: room)

        let roster = roster(of: room)
        try await append(
            try Payload.roomState(
                RoomStateBody(
                    name: rooms.first { $0.id == room }?.name,
                    kind: (rooms.first { $0.id == room }?.isDirect ?? false) ? .solo : .room,
                    access: roster.access,
                    founder: roster.founder,
                    members: roster.members.sorted {
                        $0.rawValue.lexicographicallyPrecedes($1.rawValue)
                    },
                    statedAt: clock.now)),
            to: room)
    }

    public func advanceEpoch(of room: RoomID) async throws {
        guard let chain = chains[room] else { throw AppSessionError.unknownRoom }

        let epoch = chain.highestKnownEpoch ?? .initial
        let advanced = try EpochChain.advance(
            from: try chain.secret(for: epoch), at: epoch, room: room)

        try await append(try Payload.epochChange(advanced.link), to: room)

        try adopt(secret: advanced.secret, link: advanced.link, at: epoch.next, in: room)

        try await persistEpoch(advanced.secret, at: epoch.next, for: room)
    }

    private func adopt(
        secret: EpochSecret, link: EpochLink, at epoch: EpochNumber, in room: RoomID
    ) throws {
        guard var current = chains[room] else { throw AppSessionError.unknownRoom }
        current.adopt(secret, at: epoch)
        try current.record(link)
        chains[room] = current
    }

    func unwindEpochs(in room: RoomID, bounded: Bool = false) async throws {
        guard var chain = chains[room] else { return }

        var progressed = true
        while progressed {
            progressed = false
            let before = chain.knownLinks

            for entry in replica.entries(in: room) {
                guard let payload = entry.opened(using: chain),
                    payload.type == .epochChange,
                    let body = try? payload.decode(EpochChangeBody.self)
                else { continue }
                try? chain.record(body.link)
            }

            if chain.knownLinks != before { progressed = true }
        }

        do {
            try chain.warm(downTo: .initial)
        } catch {
            let reached = chain.knownEpochs.map { String($0.rawValue) }.sorted().joined(separator: ",")
            if bounded {
                Diagnostics.sync.notice(
                    """
                    adopt: this key opens from where this member was let in and no further \
                    (holding \(reached, privacy: .public))
                    """)
            } else {
                Diagnostics.sync.error(
                    """
                    adopt: could not walk this room's key back to the beginning — history from \
                    before this device joined stays unreadable and the room may not appear at all \
                    (reached \(reached, privacy: .public)): \
                    \(String(describing: error), privacy: .public)
                    """)
            }
        }
        chains[room] = chain

        for epoch in chain.knownEpochs {
            guard let secret = try? chain.secret(for: epoch) else { continue }
            try await persistEpoch(secret, at: epoch, for: room)
        }
    }

    private func inviterKeys(
        for attestation: MembershipAttestation, in roster: RoomRoster
    ) throws -> IdentityPublicKeys {
        guard let keys = replica.registry(for: attestation.inviter)?.identity else {
            throw MembershipError.inviterNotAMember
        }
        return keys
    }

    public func updateOrganisation(_ change: (inout RoomsListOrganisation) -> Void) {
        change(&organisation)
        persisted.organisation = organisation
        Task { await persistOrReport("how your rooms are arranged") {
            try await saveState()
        } }
    }

    public func stamp() -> OrganisationStamp {
        OrganisationStamp(
            at: clock.now, device: enrolment?.device.id ?? DeviceID(rawValue: Data()))
    }
}
