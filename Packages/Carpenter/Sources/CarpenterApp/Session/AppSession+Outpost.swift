import CarpenterKit
import CryptoKit
import Foundation

// MARK: The wall, its readers and what is new on it

extension AppSession {
    // MARK: The picture at the top of this member's own Outpost

    public var ownOutpostPhotoReference: AttachmentReference? {
        enrolment.flatMap { projection.outpostPhotoReference(of: $0.identity.id) }
    }

    public func shareOutpostPhoto(_ jpeg: Data?, through mailbox: any MediaMailbox) async throws {
        guard let enrolment else { throw AppSessionError.noIdentity }
        guard let jpeg, persisted.preferences.isSharingAvatar,
            persisted.preferences.isShowingPhotoOnOutpost
        else { return await withdrawOutpostPhoto(through: mailbox) }
        let previous = projection.outpostPhotoReference(of: enrolment.identity.id)

        let (reference, ciphertext) = try SealedAttachment.seal(jpeg, kind: .image)
        let window = SyncSession.window(at: clock.now)
        let readers = outpostReaders()
        let recipients = Set(
            peers().filter { readers.contains($0.them) }.map { $0.outgoingTag(window: window) })
        uploading.insert(reference.id)
        defer { uploading.remove(reference.id) }
        try await mailbox.upload(
            OutgoingAttachment(id: reference.id, ciphertext: ciphertext, recipients: recipients))
        Diagnostics.sync.notice(
            "outpost avatar: uploaded \(ciphertext.count, privacy: .public) bytes for \(recipients.count, privacy: .public) peer(s)")

        try await announceOutpostPhoto(reference)
        try await dropOutpostAttachment(previous, through: mailbox)
    }

    public func withdrawOutpostPhoto(through mailbox: any MediaMailbox) async {
        guard let me = enrolment?.identity.id,
            let current = projection.outpostPhotoReference(of: me)
        else { return }
        await announceOrReport("taking the picture off your Outpost") {
            try await announceOutpostPhoto(nil)
        }
        await announceOrReport("taking the picture off your Outpost") {
            try await dropOutpostAttachment(current, through: mailbox)
        }
    }

    private func dropOutpostAttachment(
        _ previous: AttachmentReference?, through mailbox: any MediaMailbox
    ) async throws {
        guard let me = enrolment?.identity.id, let previous else { return }
        guard previous.id != projection.outpostPhotoReference(of: me)?.id,
            previous.id != projection.photoReference(of: me)?.id
        else { return }
        do { try await mailbox.delete(attachment: previous.id) } catch {
            Diagnostics.sync.error(
                "outpost avatar: could not delete the previous picture (\(String(describing: error), privacy: .public))")
        }
    }

    private func announceOutpostPhoto(_ reference: AttachmentReference?) async throws {
        guard let me = enrolment?.identity.id else { return }
        let wall = try await outpostChain()
        let announced = projection.announcedPhoto(of: me, in: wall)
        if let announced, announced == reference { return }
        if announced == nil, reference == nil { return }
        try await append(try Payload.memberPhoto(reference), to: wall)
    }

    func announcePhotoEverywhere(_ reference: AttachmentReference?) async throws {
        for room in roomsToTell() {
            try await announcePhoto(reference, in: room)
        }
    }

    func announcePhoto(_ reference: AttachmentReference?, in room: ConversationID) async throws {
        guard let me = enrolment?.identity.id else { return }
        let announced = projection.announcedPhoto(of: me, in: room)
        if let announced, announced == reference { return }
        if announced == nil, reference == nil { return }
        try await append(try Payload.memberPhoto(reference), to: room)
    }

    public func sharedPhotoReference(of person: ParticipantID) -> AttachmentReference? {
        guard persisted.preferences.isShowingOthersAvatars, !refusesToDraw(from: person) else {
            return nil
        }
        return projection.photoReference(of: person)
    }

    public func sharedOutpostPhotoReference(of person: ParticipantID) -> AttachmentReference? {
        guard persisted.preferences.isShowingOthersAvatars, !refusesToDraw(from: person) else {
            return nil
        }
        return projection.outpostPhotoReference(of: person)
    }

    public func downloadSharedPhoto(
        _ reference: AttachmentReference, from person: ParticipantID, through mailbox: any MediaMailbox
    ) async throws -> Data? {
        let name = Diagnostics.fingerprint(reference.id.rawValue.uuidString)
        guard let bytes = try await mailbox.download(reference.id, hint: collectionTags(for: person)) else {
            Diagnostics.sync.notice("avatar: no outbox holds \(name, privacy: .public)")
            return nil
        }
        guard SealedAttachment.matches(bytes, reference) else {
            Diagnostics.sync.error("avatar: \(name, privacy: .public) does not match its pointer; not kept")
            throw AttachmentError.digestMismatch
        }
        return try SealedAttachment.open(bytes, with: reference)
    }

    // MARK: Who sees your Outpost

    public var outpostAccess: OutpostAccess {
        guard let me = enrolment?.identity.id else { return OutpostAccess() }
        if let known = cachedOutpostAccess { return known }
        let built = projection.outpostAccess(of: me, opening: payloadOpener())
        cachedOutpostAccess = built
        return built
    }

    public func outpostReaders() -> Set<ParticipantID> {
        notShutOut(outpostAccess.audience(at: clock.now))
    }

    public func outpostAccessChosen(in room: ConversationID) -> [Member] {
        outpostAccess.granted
            .filter { $0.value.value.chosenIn == room && $0.value.value.isAllowed }
            .map { member($0.key) }
            .sorted { $0.displayName < $1.displayName }
    }

    public func audienceCandidates() -> [Member] {
        var seen = Set<ParticipantID>()
        var people: [Member] = []
        for person in connections().map(\.person) where seen.insert(person.id).inserted {
            people.append(person)
        }
        for id in outpostAccess.granted.keys where seen.insert(id).inserted {
            people.append(member(id))
        }
        return people.sorted { $0.displayName < $1.displayName }
    }

    public func reciprocalAccess(with person: ParticipantID) -> ReciprocalAccess? {
        guard let me = enrolment?.identity.id, person != me else { return nil }
        let opening = payloadOpener()
        let shared = rooms.filter {
            !$0.isDirect && roster(of: $0.id).members.isSuperset(of: [me, person])
        }
        return ReciprocalAccess(
            person: member(person),
            sharedRooms: shared.map(\.name),
            theyGave: projection.outpostAccess(of: person, opening: opening).grant(for: me),
            youGave: outpostAccess.grant(for: person))
    }

    // MARK: What is new on somebody's wall

    public func unseenPosts(from author: ParticipantID) -> Int {
        guard let me = enrolment?.identity.id, author != me else { return 0 }
        guard let mark = persisted.outpostSeenThrough[author] else { return 0 }
        return projection.posts(by: author).count { $0.postedAt > mark }
    }

    public func outpostAuthorsWithUnseen() -> Set<ParticipantID> {
        guard let me = enrolment?.identity.id else { return [] }
        var found: Set<ParticipantID> = []
        for author in projection.outpostAuthors().map(\.id)
        where author != me && !refusesToDraw(from: author) {
            if unseenPosts(from: author) > 0 { found.insert(author) }
        }
        return found
    }

    func wallsToBeToldAbout() -> [ParticipantID] {
        persisted.preferences.outpostNotifiedPeople
            .sorted { $0.rawValue.lexicographicallyPrecedes($1.rawValue) }
    }

    public var ownBlurb: String? {
        let written = persisted.preferences.blurb?.value
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (written?.isEmpty ?? true) ? nil : written
    }

    public func blurb(of person: ParticipantID) -> String? {
        projection.blurb(of: person, opening: payloadOpener())
    }

    public func setBlurb(_ text: String) async throws {
        guard enrolment != nil else { throw AppSessionError.noIdentity }
        let trimmed = String(
            text.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(MemberProfileBody.blurbLimit))
        guard trimmed != (persisted.preferences.blurb?.value ?? "") else { return }
        persisted.preferences.setBlurb(trimmed, stamp: stamp())
        await savePreferences()

        let name = persisted.preferences.isSharingName ? ownDisplayName : nil
        let wall = try await outpostChain()
        try await append(
            try Payload.memberProfile(displayName: name, blurb: trimmed), to: wall)
    }

    func countWhatIsHeldForOthers() {
        let projected = projection
        let open = entryOpener()
        var sealed = 0
        var strangers: Set<ParticipantID> = []
        let met = projected.met ?? []

        for entry in replica.allEntries {
            if open(entry) == nil { sealed += 1 }
            if !met.contains(entry.author) { strangers.insert(entry.author) }
        }
        integrity.sealedForOthers = sealed
        integrity.unmetAuthorsHeld = strangers.count
    }

    func publishCommentTallies() async {
        guard let me = enrolment?.identity.id else { return }
        let wall = outpostRoom(for: me)
        let projected = projection
        let opener = payloadOpener()
        let held = entriesByHash

        for post in projected.posts(by: me) {
            let comments = projected.comments(on: post.id.entry)
            let anyClosed = comments.contains { comment in
                guard let entry = held[comment.id.entry] else { return false }
                return entry.conversation != wall
            }
            guard anyClosed else { continue }
            let total = comments.count
            guard projected.commentTally(for: post.id.entry, by: me, opening: opener) != total
            else { continue }
            await announceOrReport("how many comments your post has") {
                try await append(
                    try Payload.commentTally(post: post.id.entry, total: total), to: wall)
            }
        }
    }

    public func publishedTally(on post: OutpostPost) -> Int? {
        projection.commentTally(
            for: post.id.entry, by: post.author.id, opening: payloadOpener())
    }

    public func hiddenComments(on post: OutpostPost) -> Int {
        let projected = projection
        guard let total = projected.commentTally(
            for: post.id.entry, by: post.author.id, opening: payloadOpener())
        else { return 0 }
        return max(0, total - projected.commentCount(on: post.id.entry))
    }

    public func wantsOutpostBellFrom(_ person: ParticipantID) -> Bool {
        persisted.wantsOutpostBell.contains(person)
    }

    public func isNotified(about person: ParticipantID) -> Bool {
        persisted.preferences.isNotified(about: person)
    }

    public func outpostNotifiedPeople() -> Set<ParticipantID> {
        persisted.preferences.outpostNotifiedPeople
    }

    public func setNotified(_ isNotified: Bool, about person: ParticipantID) async {
        persisted.preferences.setNotified(isNotified, about: person, stamp: stamp())
        await savePreferences()
        refresh()
        sendOwnEntries()
    }

    public func markOutpostSeen(from author: ParticipantID) async {
        guard let me = enrolment?.identity.id, author != me else { return }
        let newest = projection.posts(by: author).map(\.postedAt).max() ?? clock.now
        guard persisted.outpostSeenThrough[author] != newest else { return }
        persisted.outpostSeenThrough[author] = newest
        await saveSeenMarks()
        refresh()
    }

    public func markOutpostSeen(_ post: OutpostPost) async {
        guard let me = enrolment?.identity.id, post.author.id != me else { return }
        let author = post.author.id
        let mark = persisted.outpostSeenThrough[author]
        guard mark == nil || post.postedAt > mark! else { return }
        persisted.outpostSeenThrough[author] = post.postedAt
        await saveSeenMarks()
        refresh()
    }

    func adoptNewOutpostAuthors() async {
        guard let me = enrolment?.identity.id else { return }
        var changed = false
        for author in projection.outpostAuthors().map(\.id)
        where author != me && persisted.outpostSeenThrough[author] == nil {
            persisted.outpostSeenThrough[author] =
                projection.posts(by: author).map(\.postedAt).max() ?? clock.now
            changed = true
        }
        if changed { await saveSeenMarks() }
    }

    func saveSeenMarks() async {
        do { try await saveState() } catch {
            Diagnostics.sync.error(
                "outpost: could not save what has been seen (\(String(describing: error), privacy: .public))")
        }
    }

    public func outpostReview(in room: ConversationID) -> OutpostReview? {
        guard let me = enrolment?.identity.id else { return nil }
        guard persisted.preferences.isOfferingOutpostReview else { return nil }
        guard persisted.preferences.outpostStanding?.showsOutposts ?? true else { return nil }
        let roster = roster(of: room)
        guard roster.members.contains(me) else { return nil }

        let access = outpostAccess
        let named = rooms
        let people = roster.members.subtracting([me]).map { id -> OutpostReview.Person in
            let grant = access.grant(for: id)
            return OutpostReview.Person(
                member: member(id), grant: grant,
                decidedIn: grant?.chosenIn.flatMap { where_ in
                    named.first { $0.id == where_ }?.name
                })
        }
        let review = OutpostReview(
            room: room, roomName: rooms.first { $0.id == room }?.name ?? "", people: people)
        guard review.isWorthAsking else { return nil }

        let postponed = Set(persisted.reviewsPostponed[room] ?? [])
        guard !Set(review.undecided.map(\.id)).isSubset(of: postponed) else { return nil }
        return review
    }

    public func postponeOutpostReview(in room: ConversationID) async {
        guard let review = outpostReview(in: room) else { return }
        persisted.reviewsPostponed[room] = review.undecided.map(\.id)
        do { try await saveState() } catch {
            Diagnostics.sync.error(
                "outpost: could not record that a review was put off (\(String(describing: error), privacy: .public))")
        }
        refresh()
    }

    public func allowOutpost(
        _ person: ParticipantID, everything: Bool, chosenIn: ConversationID? = nil
    ) async throws {
        guard let enrolment else { throw AppSessionError.noIdentity }
        guard person != enrolment.identity.id else { throw AppSessionError.thatIsYou }
        let wall = try await outpostChain()

        if !everything { try await advanceEpoch(of: wall) }
        let since = everything ? nil : chains[wall]?.highestKnownEpoch?.rawValue

        try await append(
            try Payload.outpostAccess(
                OutpostAccessBody(
                    person: person, isAllowed: true, from: everything ? nil : clock.now,
                    origin: .chosen, sinceEpoch: since, chosenIn: chosenIn)),
            to: wall)
        if everything, !persisted.outpostMediaOwed.contains(person) {
            persisted.outpostMediaOwed.append(person)
            try await saveState()
        }
        Diagnostics.sync.notice(
            """
            outpost: let \(Diagnostics.fingerprint(person.rawValue), privacy: .public) in \
            (\(everything ? "everything" : "from now", privacy: .public))
            """)
    }

    func settleOutpostMediaOwed(through mailbox: any MediaMailbox) async {
        guard let enrolment, !persisted.outpostMediaOwed.isEmpty else { return }
        let owed = persisted.outpostMediaOwed
        let wall = outpostRoom(for: enrolment.identity.id)
        let window = SyncSession.window(at: clock.now)
        let tags = Set(
            peers().filter { owed.contains($0.them) }.map { $0.outgoingTag(window: window) })
        guard !tags.isEmpty else { return }

        let waiting = (try? await mailbox.pendingAttachments()) ?? [:]

        var offered = 0
        var gone = 0
        for entry in replica.allEntries
        where entry.author == enrolment.identity.id && entry.conversation == wall {
            guard let chain = chain(sealing: entry), let payload = entry.opened(using: chain),
                payload.type == .media, let body = try? payload.decode(MediaBody.self)
            else { continue }
            for picture in body.all {
                let id = picture.attachment.id
                guard let ciphertext = try? await storage.media.sealed(for: id) else {
                    gone += 1
                    continue
                }
                do {
                    try await mailbox.upload(
                        OutgoingAttachment(
                            id: id, ciphertext: ciphertext,
                            recipients: (waiting[id] ?? []).union(tags)))
                    offered += 1
                } catch {
                    Diagnostics.sync.error(
                        """
                        media: could not re-offer a wall picture to a new reader \
                        (\(String(describing: error), privacy: .public))
                        """)
                    return
                }
            }
        }

        persisted.outpostMediaOwed.removeAll { owed.contains($0) }
        do { try await saveState() } catch {
            Diagnostics.sync.error(
                "outpost: could not record that a reader's pictures were re-offered (\(String(describing: error), privacy: .public))")
        }
        Diagnostics.sync.notice(
            """
            outpost: re-offered \(offered, privacy: .public) wall picture(s) to \
            \(owed.count, privacy: .public) new reader(s); \(gone, privacy: .public) no longer here
            """)
    }

    public func revokeOutpost(_ person: ParticipantID, chosenIn: ConversationID? = nil) async throws {
        guard enrolment != nil else { throw AppSessionError.noIdentity }
        let wall = try await outpostChain()

        let held = outpostReaders().contains(person)

        if held { try await oweEpochTurn(in: wall) }
        try await append(
            try Payload.outpostAccess(
                OutpostAccessBody(person: person, isAllowed: false, chosenIn: chosenIn)),
            to: wall)
        if held { try await turnOwedEpoch(in: wall) }
        Diagnostics.sync.notice(
            """
            outpost: \(held ? "revoked" : "said no to", privacy: .public) \
            \(Diagnostics.fingerprint(person.rawValue), privacy: .public)
            """)
    }

    public var outpostKeyTurnPending: Bool {
        guard let me = enrolment?.identity.id else { return false }
        return persisted.epochTurnsOwed.contains(outpostRoom(for: me))
    }

    func oweEpochTurn(in room: ConversationID) async throws {
        guard !persisted.epochTurnsOwed.contains(room) else { return }
        persisted.epochTurnsOwed.append(room)
        try await saveState()
    }

    func turnOwedEpoch(in room: ConversationID) async throws {
        guard persisted.epochTurnsOwed.contains(room) else { return }
        try await advanceEpoch(of: room)
        persisted.epochTurnsOwed.removeAll { $0 == room }
        try await saveState()
    }

    func settleOwedEpochTurns() async {
        for room in persisted.epochTurnsOwed {
            do {
                try await turnOwedEpoch(in: room)
                Diagnostics.sync.notice("mailbox sync: turned a key that was owed from an earlier change")
            } catch {
                Diagnostics.sync.error(
                    """
                    mailbox sync: still cannot turn a key this device owes — somebody removed \
                    can read what is said until it turns \
                    (\(String(describing: error), privacy: .public))
                    """)
            }
        }
        for room in keyTurnsTheLogOwes() where !persisted.epochTurnsOwed.contains(room) {
            do {
                try await advanceEpoch(of: room)
                Diagnostics.sync.notice(
                    "mailbox sync: turned a key this device's own removal was still owed")
            } catch {
                Diagnostics.sync.error(
                    """
                    mailbox sync: still cannot turn a key this device's own removal owes — \
                    somebody removed can read what is said until it turns \
                    (\(String(describing: error), privacy: .public))
                    """)
            }
        }
    }

    func keyTurnsTheLogOwes() -> Set<ConversationID> {
        guard let enrolment else { return [] }
        let me = enrolment.identity.id
        let wall = outpostRoom(for: me)
        var owed: Set<ConversationID> = []

        for removal in projection.entries(of: .removal, by: me)
        where removal.device == enrolment.device.id {
            guard let entry = replica.entry(named: removal.id),
                entry.payload.epoch == chains[removal.conversation]?.highestKnownEpoch,
                standing(in: removal.conversation) == .present
            else { continue }
            owed.insert(removal.conversation)
        }

        guard let chain = chains[wall] else { return owed }
        var letIn: Set<ParticipantID> = []
        var shutOut: Set<ParticipantID> = []
        for choice in projection.entries(of: .outpostAccess, by: me) where choice.conversation == wall {
            guard let entry = replica.entry(named: choice.id),
                let body = try? entry.opened(using: chain)?.decode(OutpostAccessBody.self)
            else { continue }
            if body.isAllowed {
                letIn.insert(body.person)
            } else if choice.device == enrolment.device.id,
                entry.payload.epoch == chain.highestKnownEpoch
            {
                shutOut.insert(body.person)
            }
        }
        if !shutOut.isDisjoint(with: letIn) { owed.insert(wall) }
        return owed
    }

    @discardableResult
    private func outpostChain() async throws -> ConversationID {
        guard let enrolment else { throw AppSessionError.noIdentity }
        let wall = outpostRoom(for: enrolment.identity.id)
        guard chains[wall] == nil else { return wall }

        let (chain, secret) = EpochChain.create(room: wall)
        chains[wall] = chain
        try await persistEpoch(secret, at: .initial, for: wall)
        return wall
    }

    func upload(
        _ media: PreparedMedia, to targets: Set<ParticipantID>, through mailbox: any MediaMailbox
    ) async throws -> MediaBody {
        let (reference, ciphertext) = try SealedAttachment.seal(media.bytes, kind: media.kind)
        let body = MediaBody(
            attachment: reference, kind: media.kind, width: media.width, height: media.height,
            preview: media.preview, caption: media.caption, duration: media.duration)
        _ = try Payload.media(body)

        try await storage.media.store(ciphertext, for: reference.id)

        let window = SyncSession.window(at: clock.now)
        let recipients = Set(
            peers().filter { targets.contains($0.them) }.map { $0.outgoingTag(window: window) })

        uploading.insert(reference.id)
        defer { uploading.remove(reference.id) }
        do {
            try await mailbox.upload(
                OutgoingAttachment(id: reference.id, ciphertext: ciphertext, recipients: recipients))
        } catch {
            do { try await storage.media.remove(reference.id) } catch {
                Diagnostics.sync.error(
                    "media: could not drop the local copy of an upload that failed (\(String(describing: error), privacy: .public))")
            }
            Diagnostics.sync.error(
                "media: upload failed, nothing sent (\(String(describing: error), privacy: .public))")
            throw error
        }
        Diagnostics.sync.notice(
            """
            media: uploaded \(Diagnostics.fingerprint(reference.id.rawValue.uuidString), privacy: .public) \
            bytes=\(ciphertext.count, privacy: .public) recipients=\(recipients.count, privacy: .public)
            """)
        return body
    }

    public func outpost() -> [OutpostPost] {
        guard let enrolment else { return [] }
        return projection.posts(by: enrolment.identity.id)
    }

    public func feed() -> [OutpostPost] {
        projection.feed().filter { !refusesToDraw(from: $0.author.id) }
    }

    public func outpostAuthors() -> [Member] {
        projection.outpostAuthors().filter { !refusesToDraw(from: $0.id) }
    }

    public func react(to post: OutpostPost, emoji: String?) async throws {
        try requireJoiningIn(unless: post.isMine)
        try await appendToWall(
            of: post.author.id, try Payload.reaction(post.id.entry, emoji: emoji))
        if emoji != nil { ringWall(of: post.author.id) }
    }

    public func react(to comment: OutpostComment, emoji: String?) async throws {
        try requireJoiningIn(unless: comment.isMine)
        guard let owner = wallOwner(of: comment.id.entry) else {
            throw AppSessionError.cannotWriteThere
        }
        try await appendToWall(of: owner, try Payload.reaction(comment.id.entry, emoji: emoji))
    }

    private func wallOwner(of entry: EntryHash) -> ParticipantID? {
        entriesByHash[entry]?.conversation.owner
    }

    private func requireJoiningIn(unless mine: Bool) throws {
        guard !mine else { return }
        guard persisted.preferences.outpostStanding?.participates ?? true else {
            throw AppSessionError.readingOnly
        }
    }

    public func comment(on post: OutpostPost, text: String) async throws {
        try requireJoiningIn(unless: post.isMine)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await appendToWall(
            of: post.author.id, try Payload.comment(on: post.id.entry, text: trimmed))
        ringWall(of: post.author.id, threadOn: post)
    }

    public func comments(on post: OutpostPost) -> [OutpostComment] {
        projection.comments(on: post.id.entry).filter { !refusesToDraw(from: $0.author.id) }
    }
}
