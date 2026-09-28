import CarpenterKit
import Foundation

struct PairBookEntry: Codable, Equatable, Sendable {
    var theirs: PairLink?
    var joined = false
    var announced: URL?
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
        for person in replica.knownParticipants where person != me {
            if let secret = legacySecret(with: person) { hints[person] = secret.pairHint }
        }
        return Pairs(me: me, hints: hints)
    }

    public func pairUp(through mailbox: any Mailbox) async {
        guard let pairs = pairs(), let enrolment else { return }
        takePairLinks()
        await makeACodeLink(through: mailbox, in: pairs, identity: enrolment.identity)
        await settleCodeClaims(through: mailbox, in: pairs)

        let account = try? await mailbox.account(in: pairs)
        for peer in Set(peers().map(\.them)).union(persisted.pairBook.keys) where pairs.hints[peer] != nil {
            var entry = persisted.pairBook[peer] ?? PairBookEntry()
            let url: URL
            do {
                url = try await mailbox.space(for: peer, naming: entry.theirs?.account, in: pairs)
            } catch {
                Diagnostics.sync.error(
                    "pairs: could not make a space for somebody: \(String(describing: error), privacy: .public)")
                continue
            }
            if let theirs = entry.theirs, !entry.joined {
                switch try? await mailbox.join(theirs, of: peer, in: pairs) {
                case .joined?: entry.joined = true
                case .gone?: entry.theirs = nil
                case .notYetNamed?, nil: break
                }
            }
            if entry.announced != url, let account,
                await announce(PairLink(account: account, url: url), to: peer)
            {
                entry.announced = url
            }
            if persisted.pairBook[peer] != entry { persisted.pairBook[peer] = entry }
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
        Set(persisted.pairBook.filter(\.value.joined).keys)
    }

    func takePairLinks() {
        guard let me = enrolment?.identity.id else { return }
        let projected = projection
        var latest: [ParticipantID: PairLinkBody] = [:]
        for room in persisted.knownRooms {
            let out = outOfRoom(in: room, of: projected)
            for link in projected.pairLinks(in: room, to: me) where !out.contains(link.id) {
                latest[link.author] = link.body
            }
        }
        for (author, body) in latest {
            guard let secret = legacySecret(with: author), let link = body.open(from: author, with: secret) else { continue }
            take(link, from: author)
        }
    }

    func take(_ link: PairLink, from peer: ParticipantID) {
        var entry = persisted.pairBook[peer] ?? PairBookEntry()
        guard entry.theirs != link else { return }
        entry.theirs = link
        entry.joined = false
        persisted.pairBook[peer] = entry
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
        } catch {
            Diagnostics.sync.error(
                "pairs: could not make a space for a new code: \(String(describing: error), privacy: .public)")
        }
    }

    private func settleCodeClaims(through mailbox: any Mailbox, in pairs: Pairs) async {
        for claim in persisted.codeClaims where pairs.hints[claim.peer] != nil {
            let account = persisted.pairBook[claim.peer]?.theirs?.account
            guard (try? await mailbox.claim(claim.url, for: claim.peer, naming: account, in: pairs)) != nil else { continue }
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
