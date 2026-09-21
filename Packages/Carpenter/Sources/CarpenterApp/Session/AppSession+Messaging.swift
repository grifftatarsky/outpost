import CarpenterKit
import CryptoKit
import Foundation

// MARK: What is said in a room, and how it is read

extension AppSession {
    // MARK: Writing

    @discardableResult
    public func createRoom(named name: String, kind: RoomKind = .room) async throws -> ConversationID {
        let room: ConversationID
        switch kind {
        case .room: room = .room(UUID())
        case .solo: room = .solo(UUID())
        }
        let (chain, secret) = EpochChain.create(room: room)
        chains[room] = chain
        try await persistEpoch(secret, at: .initial, for: room)

        try await append(try Payload.roomProfile(name: name, kind: kind), to: room)
        try await announceProfile(in: room)
        return room
    }

    @discardableResult
    public func startSolo(with person: ParticipantID) async throws -> ConversationID {
        try await createRoom(named: member(person).displayName, kind: .solo)
    }

    @discardableResult
    public func createRoom(named name: String, access: RoomAccess) async throws -> ConversationID {
        let room = try await createRoom(named: name)
        if access != .open { try await setAccess(access, in: room) }
        return room
    }

    public func send(_ text: String, to room: ConversationID?) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await append(try Payload.post(trimmed), to: room)
        if let room {
            roomsWithUnsentMessages.insert(room)
        } else if let head {
            unsentWallPosts.insert(head.hash)
        }
    }

    func ringWall(of owner: ParticipantID, threadOn post: OutpostPost? = nil) {
        guard let me = enrolment?.identity.id else { return }

        if owner != me { wallsWrittenOn.insert(owner) }

        if let post {
            for commenter in comments(on: post).map(\.author.id) where commenter != me {
                wallsWrittenOn.insert(commenter)
            }
        }
    }

    public func send(
        _ media: PreparedMedia, to room: ConversationID, through mailbox: any MediaMailbox
    ) async throws {
        guard let enrolment else { throw AppSessionError.noIdentity }
        let me = enrolment.identity.id
        let roster = roster(of: room)
        if roster.departure(of: me) != nil { throw MembershipError.leftThisRoom }
        if !roster.mayWrite(me) { throw MembershipError.removedFromThisRoom }

        let body = try await upload(
            media, to: notShutOut(roster.rewrapTargets(of: me)), through: mailbox)
        try await append(try Payload.media(body), to: room)
        roomsWithUnsentMessages.insert(room)
    }

    public func post(_ media: PreparedMedia, through mailbox: any MediaMailbox) async throws {
        try await post([media], through: mailbox)
    }

    public func post(_ media: [PreparedMedia], through mailbox: any MediaMailbox) async throws {
        guard !media.isEmpty else { return }
        guard media.count <= MediaBody.galleryLimit else { throw AppSessionError.tooManyPictures }

        let readers = outpostReaders()
        var bodies: [MediaBody] = []
        do {
            for one in media {
                bodies.append(try await upload(one, to: readers, through: mailbox))
            }
        } catch {
            for body in bodies { await discard(body.attachment.id, through: mailbox) }
            throw error
        }

        let first = bodies[0]
        try await append(
            try Payload.media(
                MediaBody(
                    attachment: first.attachment, kind: first.kind, width: first.width,
                    height: first.height, preview: first.preview, caption: first.caption,
                    duration: first.duration, extras: Array(bodies.dropFirst()))),
            to: nil)
        if let head { unsentWallPosts.insert(head.hash) }
    }

    private func discard(_ id: AttachmentID, through mailbox: any MediaMailbox) async {
        do { try await mailbox.delete(attachment: id) } catch {
            Diagnostics.sync.error(
                "media: could not take back an upload nothing names (\(String(describing: error), privacy: .public))")
        }
        do { try await storage.media.remove(id) } catch {
            Diagnostics.sync.error(
                "media: could not drop a local copy nothing names (\(String(describing: error), privacy: .public))")
        }
    }

    public func edit(_ message: MessageID, to text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppSessionError.nothingToSay }
        let original = try own(message)
        guard Editing.isOpen(
            at: clock.now, for: original.wallTime, within: Editing.editWindow)
        else { throw AppSessionError.tooLateToEdit }

        try await append(try Payload.edit(message.entry, to: trimmed), to: original.room)
    }

    public func withdraw(_ message: MessageID) async throws {
        let original = try own(message)
        guard Editing.isOpen(
            at: clock.now, for: original.wallTime, within: Editing.withdrawWindow)
        else { throw AppSessionError.tooLateToWithdraw }

        try await append(try Payload.tombstone(message.entry), to: original.room)
    }

    public func timeLeft(toEdit message: MessageID) -> TimeInterval? {
        guard let original = try? own(message), case .text = original.content else { return nil }
        return remaining(for: message, within: Editing.editWindow)
    }

    public func timeLeft(toWithdraw message: MessageID) -> TimeInterval? {
        remaining(for: message, within: Editing.withdrawWindow)
    }

    // MARK: Changing a post

    public func edit(_ post: PostID, to text: String) async throws {
        try await edit(MessageID(entry: post.entry), to: text)
    }

    public func withdraw(_ post: PostID) async throws {
        try await withdraw(MessageID(entry: post.entry))
    }

    public func timeLeft(toEdit post: PostID) -> TimeInterval? {
        timeLeft(toEdit: MessageID(entry: post.entry))
    }

    public func timeLeft(toWithdraw post: PostID) -> TimeInterval? {
        timeLeft(toWithdraw: MessageID(entry: post.entry))
    }

    private func remaining(for message: MessageID, within window: TimeInterval) -> TimeInterval? {
        guard let original = try? own(message) else { return nil }
        if case .withdrawn = original.content { return nil }
        let left = window - clock.now.timeIntervalSince(original.wallTime)
        return left > 0 ? left : nil
    }

    private func own(_ message: MessageID) throws -> RenderedEntry {
        guard let enrolment else { throw AppSessionError.noIdentity }
        guard let entry = projection.entry(message.entry) else {
            throw AppSessionError.unknownMessage
        }
        guard entry.author == enrolment.identity.id else { throw AppSessionError.notYourMessage }
        return entry
    }

    // MARK: Searching

    public func search(_ query: String) -> SearchResults {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2 else { return SearchResults() }

        var found = SearchResults()
        for summary in rooms {
            let named = summary.name.localizedStandardContains(needle)
            if named {
                found.conversations.append(
                    .init(room: summary.id, name: summary.name, isDirect: summary.isDirect))
            }

            for message in messages(in: summary.id) where !message.isWithdrawn {
                let saidIt = message.body.localizedStandardContains(needle)
                let byThem = message.author.displayName.localizedStandardContains(needle)

                if saidIt, !message.body.isEmpty {
                    found.said.append(
                        .init(
                            message: message.id, room: summary.id, roomName: summary.name,
                            author: message.author, body: message.body, sentAt: message.sentAt))
                }

                if let media = message.media, named || byThem || saidIt {
                    found.pictures.append(
                        .init(
                            message: message.id, room: summary.id, roomName: summary.name,
                            author: message.author, caption: message.body, media: media,
                            sentAt: message.sentAt))
                }
            }
        }

        found.posts = feed().filter {
            !$0.isWithdrawn
                && ($0.body.localizedStandardContains(needle)
                    || $0.author.displayName.localizedStandardContains(needle))
        }

        found.said.sort { $0.sentAt > $1.sentAt }
        found.pictures.sort { $0.sentAt > $1.sentAt }
        return found
    }

    // MARK: Reading

    public func messages(in room: ConversationID) -> [Message] {
        let projected = projection
        let mark = deliveryMarks(in: room, of: projected)
        let marked = projected.messages(in: room, outOfRoom: outOfRoom(in: room, of: projected))
            .filter(isDrawn).map(mark)
        let notices = NotGone.notices(in: marked, now: clock.now, wait: notGoneWait(in: room))
        guard !notices.isEmpty else { return marked }
        return marked.map { $0.noting(notices[$0.id]) }
    }

    public func waitingOn(in room: ConversationID) -> [WaitingOnPerson] {
        guard let me = enrolment?.identity.id else { return [] }
        let projected = projection
        let mine = Set(
            projected.messages(in: room, outOfRoom: outOfRoom(in: room, of: projected))
                .filter(\.isMine).map(\.id.entry))
        let unsent = Set(unsentEntries().map(\.hash)).intersection(mine)

        var lastHeard: [ParticipantID: Date] = [:]
        for entry in replica.allEntries where entry.author != me {
            lastHeard[entry.author] = max(lastHeard[entry.author] ?? .distantPast, entry.wallTime)
        }

        let current = SyncSession.window(at: clock.now)
        let oldest = current >= SyncSession.windowLookback ? current - SyncSession.windowLookback : 0

        return roster(of: room).members
            .filter { $0 != me }
            .map { person in
                let holding: WaitingOnPerson.Holding
                if let pending = pendingRecipients, let secret = pairwiseSecret(with: person) {
                    let theirs = Set(
                        (oldest...current).map { secret.recipientTag(window: $0, for: person) })
                    var missing = unsent
                    for (packet, tags) in pending where !tags.isDisjoint(with: theirs) {
                        missing.formUnion(
                            (persisted.outstandingPackets[packet] ?? []).intersection(mine))
                    }
                    holding = missing.isEmpty ? .everything : .missing(missing.count)
                } else {
                    holding = unsent.isEmpty ? .notCheckedYet : .missing(unsent.count)
                }
                return WaitingOnPerson(
                    member: projected.member(person), holding: holding,
                    lastHeard: lastHeard[person])
            }
            .sorted { left, right in
                left.member.displayName.localizedStandardCompare(right.member.displayName)
                    == .orderedAscending
            }
    }

    public func notGoneWait(in room: ConversationID) -> NotGoneWait {
        persisted.preferences.notGoneWait(for: room)
    }

    public func setNotGoneWait(_ wait: NotGoneWait, in room: ConversationID) async {
        persisted.preferences.setNotGoneWait(wait, for: room, stamp: stamp())
        await savePreferences()
        refresh()
    }

    public enum BannerDestination: Hashable, Sendable {
        case room(ConversationID)
        case theAppAsItStands
    }

    public func tapping(_ thread: String, whileViewing viewing: ConversationID?) -> BannerDestination {
        guard let room = ConversationID(stableName: thread) else { return .theAppAsItStands }

        guard rooms.contains(where: { $0.id == room }) else { return .theAppAsItStands }
        guard viewing != room else { return .theAppAsItStands }
        return .room(room)
    }

    public func readBy(_ message: MessageID, in room: ConversationID) -> [ReadBy] {
        let projected = projection
        let opening = payloadOpener()
        guard let position = projected.positions(in: room)[message] else { return [] }

        let me = enrolment?.identity.id
        let roster = projected.roster(of: room, opening: opening)
        let reporting = projected.reportingMembers(in: room, opening: opening)
        let evidence = projected.readEvidence(in: room, byEachMember: opening)

        return roster.members
            .filter { $0 != me }
            .map { who in
                let report: ReadReport
                if !reporting.contains(who) {
                    report = .doesNotReport
                } else if let at = evidence[who]?.firstCovering(position) {
                    report = .displayed(at: at)
                } else {
                    report = .nothingYet
                }
                return ReadBy(member: projected.member(who), report: report)
            }
            .sorted { left, right in
                switch (left.report, right.report) {
                case (.displayed(let a), .displayed(let b)): return a < b
                case (.displayed, _): return true
                case (_, .displayed): return false
                case (.nothingYet, .doesNotReport): return true
                case (.doesNotReport, .nothingYet): return false
                default:
                    return left.member.displayName
                        .localizedCaseInsensitiveCompare(right.member.displayName) == .orderedAscending
                }
            }
    }

    private func outOfRoom(in room: ConversationID, of projected: Projection) -> Set<EntryHash> {
        if let known = cachedOutOfRoom[room] { return known }
        let built = projected.outOfRoom(in: room, opening: payloadOpener())
        cachedOutOfRoom[room] = built
        return built
    }

    func readEvidence(in room: ConversationID, of projected: Projection) -> ReadEvidence {
        if let known = cachedReadEvidence[room] { return known }
        let built = projected.readEvidence(in: room, opening: payloadOpener())
        cachedReadEvidence[room] = built
        return built
    }

    func reportingMembers(in room: ConversationID, of projected: Projection) -> Set<ParticipantID> {
        if let known = cachedReporting[room] { return known }
        let built = projected.reportingMembers(in: room, opening: payloadOpener())
        cachedReporting[room] = built
        return built
    }

    public func transcript(in room: ConversationID) -> [TranscriptEntry] {
        let projected = projection
        let mark = deliveryMarks(in: room, of: projected)

        let marked: [TranscriptEntry] = projected.transcript(
            in: room, opening: payloadOpener(), outOfRoom: outOfRoom(in: room, of: projected)
        ).compactMap { item in
            guard let message = item.message else { return item }
            guard isDrawn(message) else { return nil }
            return .message(mark(message))
        }
        let notices = NotGone.notices(
            in: marked.compactMap(\.message), now: clock.now, wait: notGoneWait(in: room))
        let noted =
            notices.isEmpty
            ? marked
            : marked.map { item in
                guard let message = item.message else { return item }
                return .message(message.noting(notices[message.id]))
            }
        let added = devicesAdded(in: room).map { device in
            TranscriptEntry.notice(
                RoomNotice(
                    id: EntryHash(rawValue: device.device.rawValue),
                    kind: .addedADevice(projected.member(device.person)), at: device.at))
        }
        return TranscriptEntry.inserting(added, into: noted)
    }

    func devicesAdded(in room: ConversationID) -> [AddedDevice] {
        if let known = cachedDevicesAdded[room] { return known }
        guard let me = enrolment?.identity.id else { return [] }

        var firstHeard: [ParticipantID: Date] = [:]
        for entry in replica.entries(in: room) where entry.author != me {
            firstHeard[entry.author] = min(firstHeard[entry.author] ?? .distantFuture, entry.wallTime)
        }

        var added: [AddedDevice] = []
        for person in roster(of: room).members where person != me {
            guard let since = firstHeard[person], let registry = replica.registry(for: person)
            else { continue }
            for certificate in registry.certificates where certificate.issuedAt > since {
                added.append(
                    AddedDevice(person: person, device: certificate.device, at: certificate.issuedAt))
            }
        }
        added.sort { $0.at < $1.at }
        cachedDevicesAdded[room] = added
        return added
    }

    public func devicesAdded(by person: ParticipantID, after instant: Date) -> [Date] {
        guard let registry = replica.registry(for: person) else { return [] }
        return registry.certificates.map(\.issuedAt).filter { $0 > instant }.sorted()
    }

    private func isDrawn(_ message: Message) -> Bool {
        !persisted.preferences.isHidden(message.id.entry) && !refusesToDraw(from: message.author.id)
    }

    private func deliveryMarks(in room: ConversationID, of projected: Projection) -> (Message) -> Message {
        let unsent = Set(unsentEntries().map(\.hash))

        let hasSomebodyToReach = !peers().isEmpty

        let undelivered = undeliveredEntries()
        let evidence = readEvidence(in: room, of: projected)
        let reporting = reportingMembers(in: room, of: projected)
            .subtracting([enrolment?.identity.id].compactMap(\.self))
        let positions = projected.positions(in: room)
        return { [self] message in
            guard message.isMine else { return message }
            return Message(
                id: message.id,
                author: message.author,
                body: message.body,
                sentAt: message.sentAt,
                isMine: true,
                delivery: deliveryState(
                    of: message.id, unsent: unsent, undelivered: undelivered,
                    position: positions[message.id], evidence: evidence,
                    anyoneReports: !reporting.isEmpty,
                    hasSomebodyToReach: hasSomebodyToReach),
                editedAt: message.editedAt,
                reactions: message.reactions,
                myReaction: message.myReaction,
                isWithdrawn: message.isWithdrawn,
                revisions: message.revisions,
                media: message.media)
        }
    }

    public func latestIncomingMessage() -> IncomingMessage? {
        var newest: IncomingMessage?
        for room in rooms {
            for message in projection.messages(in: room.id)
            where !message.isMine && isDrawn(message) {
                guard newest == nil || message.sentAt > newest!.sentAt else { continue }
                newest = IncomingMessage(
                    id: message.id, room: room.id, roomName: room.name,
                    author: message.author.displayName, body: message.preview, sentAt: message.sentAt)
            }
        }
        return newest
    }

    public func latestIncomingPost() -> IncomingPost? {
        guard let me = enrolment?.identity.id else { return nil }
        var newest: IncomingPost?
        for post in projection.feed() where post.author.id != me {
            guard persisted.preferences.isNotified(about: post.author.id) else { continue }
            guard !refusesToDraw(from: post.author.id) else { continue }
            guard newest == nil || post.postedAt > newest!.postedAt else { continue }
            newest = IncomingPost(
                id: post.id, author: post.author.id, authorName: post.author.displayName,
                body: post.body, postedAt: post.postedAt)
        }
        return newest
    }

    // MARK: Read receipts

    public func markSeen(_ message: MessageID, in room: ConversationID) async {
        guard enrolment != nil else { return }
        let positions = projection.positions(in: room)
        guard let seen = positions[message] else { return }

        await advanceReadMark(to: message, at: seen, in: room, among: positions)

        guard persisted.preferences.isReportingDisplaying(in: room) else { return }

        guard projection.messages(in: room).first(where: { $0.id == message })?.isMine == false
        else { return }

        if let already = furthestSeen[room], let previous = positions[already], previous >= seen {
            return
        }
        furthestSeen[room] = message
        await announceOrReport("a read receipt") {
            try await append(try Payload.readReceipt(upTo: message.entry), to: room)
        }
    }

    private func advanceReadMark(
        to message: MessageID, at position: Int, in room: ConversationID, among positions: [MessageID: Int]
    ) async {
        if let mark = persisted.readThrough[room],
            let previous = positions[MessageID(entry: mark)],
            previous >= position
        {
            return
        }
        persisted.readThrough[room] = message.entry
        await persistOrReport("how far you have read") {
            try await saveState()
        }
        refresh()
    }

    public func markRoomRead(_ room: ConversationID) async {
        guard enrolment != nil else { return }
        let positions = projection.positions(in: room)
        guard let last = positions.max(by: { $0.value < $1.value }) else { return }
        await advanceReadMark(to: last.key, at: last.value, in: room, among: positions)
    }

    // MARK: Hiding

    public func hide(_ message: MessageID) async {
        guard !persisted.preferences.isHidden(message.entry) else { return }
        persisted.preferences.setHidden(true, for: message.entry, stamp: stamp())
        await savePreferences()
    }

    public func reveal(_ message: MessageID) async {
        guard persisted.preferences.isHidden(message.entry) else { return }
        persisted.preferences.setHidden(false, for: message.entry, stamp: stamp())
        await savePreferences()
    }

    public func revealHidden(in room: ConversationID) async {
        let inRoom = Set(projection.messages(in: room).map(\.id.entry))
        let hidden = persisted.preferences.hiddenEntries.intersection(inRoom)
        guard !hidden.isEmpty else { return }

        persisted.preferences.reveal(hidden, stamp: stamp())
        await savePreferences()
    }

    public func revealAllHidden() async {
        let hidden = persisted.preferences.hiddenEntries
        guard !hidden.isEmpty else { return }
        persisted.preferences.reveal(hidden, stamp: stamp())
        await savePreferences()
    }

    public var hiddenMessageCount: Int { persisted.preferences.hiddenEntries.count }

    public func hiddenMessageCount(in room: ConversationID) -> Int {
        let inRoom = Set(projection.messages(in: room).map(\.id.entry))
        return persisted.preferences.hiddenEntries.intersection(inRoom).count
    }

    public func isHidden(_ message: MessageID) -> Bool {
        persisted.preferences.isHidden(message.entry)
    }

    public func react(to message: MessageID, in room: ConversationID, with emoji: String?) async throws {
        try await append(try Payload.reaction(message.entry, emoji: emoji), to: room)
    }

    private func deliveryState(
        of message: MessageID, unsent: Set<EntryHash>, undelivered: Set<EntryHash>,
        position: Int?, evidence: ReadEvidence, anyoneReports: Bool,
        hasSomebodyToReach: Bool
    ) -> DeliveryState {
        if unsent.contains(message.entry) {
            return hasSomebodyToReach ? .pending : .noRecipients
        }
        if undelivered.contains(message.entry) { return .sent }
        if let position, let seenAt = evidence.firstCovering(position) {
            return .displayed(at: seenAt)
        }
        return anyoneReports ? .delivered : .notReported
    }
}
