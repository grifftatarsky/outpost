import Foundation

struct Introduction: Sendable {
    var identity: IdentityPublicKeys?
    var certificates: [DeviceCertificate] = []
    var revocations: [DeviceRevocation] = []
    var bytes = 0

    var credentials: Int { certificates.count + revocations.count }
}

struct Introductions: Sendable {
    private var people: [ParticipantID: Introduction] = [:]
    private var weighed: Set<ParticipantID> = []

    init(identities: [IdentityPublicKeys], certificates: [DeviceCertificate], revocations: [DeviceRevocation]) {
        for identity in identities { people[identity.participantID, default: Introduction()].identity = identity }
        for certificate in certificates { people[certificate.participant, default: Introduction()].certificates.append(certificate) }
        for revocation in revocations { people[revocation.participant, default: Introduction()].revocations.append(revocation) }
    }

    mutating func of(_ person: ParticipantID, encoder: JSONEncoder) -> Introduction {
        guard var found = people[person] else { return Introduction() }
        guard !weighed.contains(person) else { return found }
        found.bytes =
            ((try? encoder.encode(found.identity))?.count ?? 0)
            + ((try? encoder.encode(found.certificates))?.count ?? 0)
            + ((try? encoder.encode(found.revocations))?.count ?? 0)
        weighed.insert(person)
        people[person] = found
        return found
    }
}

struct PlannedPacket: Sendable {
    var entries: [Entry] = []
    var grants: [(to: Peer, grant: EpochGrant)] = []
    var introducing: [ParticipantID: Introduction] = [:]
    var bytes = 0
    var mustGo = false

    var credentials: Int { introducing.values.reduce(0) { $0 + $1.credentials } }

    var identities: [IdentityPublicKeys] { introducing.values.compactMap(\.identity) }
    var certificates: [DeviceCertificate] { introducing.values.flatMap(\.certificates) }
    var revocations: [DeviceRevocation] { introducing.values.flatMap(\.revocations) }
}

struct PacketPlan {
    let budget: Int
    let sender: Introduction
    let me: ParticipantID

    private(set) var packets: [PlannedPacket] = []
    private(set) var leftOut = 0
    private var current: PlannedPacket

    init(budget: Int, sender: Introduction, me: ParticipantID, firstPacketAlsoCarries extras: Int) {
        self.budget = budget
        self.sender = sender
        self.me = me
        current = PlannedPacket()
        current.introducing[me] = sender
        current.bytes = sender.bytes + extras
        current.mustGo = extras > 0
    }

    private mutating func closeThePacket() {
        guard current.mustGo || !current.entries.isEmpty || !current.grants.isEmpty else { return }
        packets.append(current)
        current = PlannedPacket()
        current.introducing[me] = sender
        current.bytes = sender.bytes
    }

    mutating func add(_ grant: (to: Peer, grant: EpochGrant), bytes: Int) {
        guard sender.bytes + bytes <= budget else {
            leftOut += 1
            return
        }
        if current.bytes + bytes > budget { closeThePacket() }
        current.grants.append(grant)
        current.bytes += bytes
    }

    mutating func add(_ entry: Entry, bytes: Int, by author: Introduction) {
        let fits = fitsOnItsOwn(author)
        let newcomer = current.introducing[entry.author] == nil && fits
        let needs = bytes + (newcomer ? author.bytes : 0)
        if current.bytes + needs > budget || (newcomer && isFull(adding: author)) { closeThePacket() }
        if fits, current.introducing[entry.author] == nil {
            current.introducing[entry.author] = author
            current.bytes += author.bytes
        }
        current.entries.append(entry)
        current.bytes += bytes
    }

    private func fitsOnItsOwn(_ author: Introduction) -> Bool {
        sender.bytes + author.bytes <= budget / 2 && author.credentials <= SyncSession.mostCredentialsInAPacket / 2
    }

    private func isFull(adding author: Introduction) -> Bool {
        current.introducing.count >= SyncSession.mostIdentitiesInAPacket
            || current.credentials + author.credentials > SyncSession.mostCredentialsInAPacket
    }

    mutating func finished() -> [PlannedPacket] {
        closeThePacket()
        return packets.isEmpty ? [current] : packets
    }
}
