import CarpenterKit
import Foundation

struct PairBookEntry: Codable, Equatable, Sendable {
    var theirs: PairLink?
    var joinedSpace: URL?
    var announced: URL?
    var gone: Set<URL> = []
    var shut = false

    init(theirs: PairLink? = nil) {
        self.theirs = theirs
    }

    private enum CodingKeys: String, CodingKey { case theirs, joinedSpace, announced, gone, shut }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theirs = try container.decodeIfPresent(PairLink.self, forKey: .theirs)
        joinedSpace = try container.decodeIfPresent(URL.self, forKey: .joinedSpace)
        announced = try container.decodeIfPresent(URL.self, forKey: .announced)
        gone = try container.decodeIfPresent(Set<URL>.self, forKey: .gone) ?? []
        shut = try container.decodeIfPresent(Bool.self, forKey: .shut) ?? false
    }
}

struct OwedPhotoReceipt: Sendable {
    let receipt: SealedReceipt
    let sender: ParticipantID
}

struct CodeClaim: Codable, Equatable, Sendable {
    var url: URL
    var peer: ParticipantID
}

// MARK: Each pair of people has a space in each one's own iCloud

extension AppSession {
    public func pairs() -> Pairs? {
        guard let me = enrolment?.identity.id else { return nil }
        var hints: [ParticipantID: PairHint] = [:]
        var accounts: [ParticipantID: Set<String>] = [:]
        for person in replica.knownParticipants where person != me {
            guard let secret = legacySecret(with: person) else { continue }
            hints[person] = secret.pairHint
            accounts[person] = readable(from: person)
        }
        return Pairs(me: me, hints: hints, accounts: accounts)
    }

    public func pairUp(through mailbox: any Mailbox) async {
        if let pairingUp { return await pairingUp.value }
        let task = Task { await pairUpOnce(through: mailbox) }
        pairingUp = task
        await task.value
        pairingUp = nil
    }

    private func pairUpOnce(through mailbox: any Mailbox) async {
        guard let pairs = pairs(), let enrolment else { return }
        await makeACodeLink(through: mailbox, in: pairs, identity: enrolment.identity)
        await settleCodeClaims(through: mailbox, in: pairs)

        let blocked = persisted.preferences.blockedPeople
        for peer in blocked where persisted.pairBook[peer]?.shut != true && pairs.hints[peer] != nil {
            do {
                try await mailbox.close(peer, in: pairs)
                persisted.pairBook[peer, default: PairBookEntry()].shut = true
                persisted.pairBook[peer]?.announced = nil
            } catch {
                Diagnostics.sync.error(
                    "pairs: could not close the space of somebody blocked: \(String(describing: error), privacy: .public)")
            }
        }
        for peer in persisted.pairBook.keys where persisted.pairBook[peer]?.shut == true && !blocked.contains(peer) {
            persisted.pairBook[peer]?.shut = false
        }

        let account = try? await mailbox.account(in: pairs)
        let everyone = Set(peers().map(\.them)).union(persisted.pairBook.keys).subtracting(blocked)
        for peer in everyone where pairs.hints[peer] != nil {
            let theirs = link(for: peer)
            let url: URL
            do {
                url = try await mailbox.space(for: peer, naming: theirs?.account, in: pairs)
            } catch {
                Diagnostics.sync.error(
                    "pairs: could not make a space for somebody: \(String(describing: error), privacy: .public)")
                continue
            }
            if let theirs, (try? await mailbox.reads(peer, in: pairs)) != true {
                await join(theirs, of: peer, through: mailbox, in: pairs)
            }
            if persisted.pairBook[peer]?.announced != url, let account,
                await announce(PairLink(account: account, url: url), to: peer)
            {
                persisted.pairBook[peer, default: PairBookEntry()].announced = url
            }
        }
    }

    private func join(_ link: PairLink, of peer: ParticipantID, through mailbox: any Mailbox, in pairs: Pairs) async {
        switch try? await mailbox.join(link, of: peer, in: pairs) {
        case .joined?: persisted.pairBook[peer, default: PairBookEntry()].joinedSpace = link.url
        case .gone?: persisted.pairBook[peer, default: PairBookEntry()].gone.insert(link.url)
        case .notYetNamed?, nil: break
        }
    }

    func currentPairs() throws -> Pairs {
        guard let pairs = pairs() else { throw AppSessionError.noIdentity }
        return pairs
    }

    func addressed(to people: [Peer]) -> [ParticipantID: RecipientTag] {
        let window = SyncSession.window(at: clock.now)
        return Dictionary(people.map { ($0.them, $0.outgoingTag(window: window)) }, uniquingKeysWith: { first, _ in first })
    }

    public var pairsJoined: Set<ParticipantID> {
        Set(persisted.pairBook.compactMap { peer, entry in
            entry.joinedSpace != nil && entry.joinedSpace == link(for: peer)?.url ? peer : nil
        })
    }

    func link(for peer: ParticipantID) -> PairLink? {
        let gone = persisted.pairBook[peer]?.gone ?? []
        if let heard = linksHeard()[peer]?.first(where: { !gone.contains($0.url) }) { return heard }
        guard let introduced = persisted.pairBook[peer]?.theirs, !gone.contains(introduced.url) else { return nil }
        return introduced
    }

    func readable(from peer: ParticipantID) -> Set<String> {
        let gone = persisted.pairBook[peer]?.gone ?? []
        var links = linksHeard()[peer] ?? []
        if let introduced = persisted.pairBook[peer]?.theirs { links.append(introduced) }
        return Set(links.filter { !gone.contains($0.url) }.map(\.account))
    }

    func linksHeard() -> [ParticipantID: [PairLink]] {
        _ = projectionGeneration
        if let cachedLinksHeard { return cachedLinksHeard }
        let built = heardLinks()
        cachedLinksHeard = built
        return built
    }

    private func heardLinks() -> [ParticipantID: [PairLink]] {
        guard let me = enrolment?.identity.id else { return [:] }
        let projected = projection
        var heard: [ParticipantID: [(entry: RenderedEntry, body: PairLinkBody)]] = [:]
        for room in persisted.knownRooms {
            let out = outOfRoom(in: room, of: projected)
            for link in projected.pairLinks(in: room, to: me) where !out.contains(link.entry.id) {
                let author = link.entry.author
                guard replica.registry(for: author)?.activeDevices.contains(link.entry.feedKey.device) == true
                else { continue }
                heard[author, default: []].append(link)
            }
        }
        return heard.reduce(into: [:]) { found, pair in
            guard let secret = legacySecret(with: pair.key) else { return }
            found[pair.key] = pair.value
                .sorted { ($0.entry.wallTime, $0.entry.seq) > ($1.entry.wallTime, $1.entry.seq) }
                .compactMap { $0.body.open(from: pair.key, with: secret) }
        }
    }

    func take(_ link: PairLink, from peer: ParticipantID) {
        guard self.link(for: peer) == nil else { return }
        persisted.pairBook[peer, default: PairBookEntry()].theirs = link
    }

    private func announce(_ link: PairLink, to peer: ParticipantID) async -> Bool {
        guard let me = enrolment?.identity.id, let secret = legacySecret(with: peer),
            let room = roomShared(with: peer)
        else { return false }
        do {
            try await append(try Payload.pairLink(try PairLinkBody.seal(link, from: me, to: peer, with: secret)), to: room)
            return true
        } catch {
            Diagnostics.sync.error(
                "pairs: could not send a link to somebody: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func roomShared(with peer: ParticipantID) -> RoomID? {
        guard let me = enrolment?.identity.id else { return nil }
        let shared = persisted.knownRooms.filter { room in
            guard chains[room] != nil else { return false }
            let roster = roster(of: room)
            return roster.members.contains(peer) && roster.mayWrite(me)
        }
        return shared.first { projection.kind(of: $0) == .solo } ?? shared.first
    }

    private func makeACodeLink(through mailbox: any Mailbox, in pairs: Pairs, identity: Identity) async {
        guard persisted.codeLink == nil else { return }
        do {
            let url = try await mailbox.spaceForACode(in: pairs)
            let account = try await mailbox.account(in: pairs)
            persisted.codeLink = try SignedPairLink.sign(PairLink(account: account, url: url), by: identity)
            prepareCodeForSharing(replacingSpent: true)
            await persistOrReport("the space a code offers") { try await saveState() }
        } catch {
            Diagnostics.sync.error(
                "pairs: could not make a space for a new code: \(String(describing: error), privacy: .public)")
        }
    }

    private func settleCodeClaims(through mailbox: any Mailbox, in pairs: Pairs) async {
        for claim in persisted.codeClaims where pairs.hints[claim.peer] != nil {
            let reader = link(for: claim.peer)?.account
            guard (try? await mailbox.claim(claim.url, for: claim.peer, naming: reader, in: pairs)) != nil else { continue }
            persisted.codeClaims.removeAll { $0 == claim }
        }
    }

    func codeWasUsed(by inviter: ParticipantID) {
        guard let used = persisted.codeLink else { return }
        persisted.codeClaims.append(CodeClaim(url: used.link.url, peer: inviter))
        persisted.codeLink = nil
        codeForSharing = ""
    }

    public func close(pairWith peer: ParticipantID, through mailbox: any Mailbox) async {
        guard let pairs = pairs() else { return }
        do {
            try await mailbox.close(peer, in: pairs)
            persisted.pairBook[peer] = nil
        } catch {
            Diagnostics.sync.error(
                "pairs: could not close a space: \(String(describing: error), privacy: .public)")
        }
    }
}
