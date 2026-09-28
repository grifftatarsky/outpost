import CarpenterKit
import Foundation

extension Pairs {
    public static func of(_ peers: Peer...) -> Pairs {
        Pairs(me: peers[0].me, hints: Dictionary(peers.map { ($0.them, $0.secret.pairHint) }, uniquingKeysWith: { a, _ in a }))
    }
}

public func link(_ mine: Peer, _ theirs: Peer, through mailbox: any Mailbox) async throws -> (mine: Pairs, theirs: Pairs) {
    let (asMe, asThem) = (Pairs.of(mine), Pairs.of(theirs))
    let myAccount = try await mailbox.account(in: asMe)
    let theirAccount = try await mailbox.account(in: asThem)
    let myLink = try await mailbox.space(for: mine.them, naming: theirAccount, in: asMe)
    let theirLink = try await mailbox.space(for: theirs.them, naming: myAccount, in: asThem)
    _ = try await mailbox.join(PairLink(account: myAccount, url: myLink), of: mine.me, in: asThem)
    _ = try await mailbox.join(PairLink(account: theirAccount, url: theirLink), of: theirs.me, in: asMe)
    return (asMe, asThem)
}

public func peers(_ a: Identity, _ b: Identity) throws -> (Peer, Peer) {
    (
        Peer(secret: try PairwiseSecret.derive(mine: a, theirs: b.publicKeys), them: b.id, me: a.id),
        Peer(secret: try PairwiseSecret.derive(mine: b, theirs: a.publicKeys), them: a.id, me: b.id)
    )
}
