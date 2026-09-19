import Foundation

public struct RoomRoster: Hashable, Sendable {
    public let room: RoomID

    public private(set) var founder: ParticipantID?

    public private(set) var requests: [ParticipantID: MembershipAttestation] = [:]

    private var admissionsByInvitation: [Data: Set<ParticipantID>] = [:]

    private var refusalsByInvitation: [Data: Set<ParticipantID>] = [:]

    public var admissions: [ParticipantID: Set<ParticipantID>] {
        requests.compactMapValues { admissionsByInvitation[$0.signature] }
    }

    public var refusals: [ParticipantID: Set<ParticipantID>] {
        requests.compactMapValues { refusalsByInvitation[$0.signature] }
    }

    private func admitters(of joiner: ParticipantID) -> Set<ParticipantID> {
        requests[joiner].flatMap { admissionsByInvitation[$0.signature] } ?? []
    }

    private func refusers(of joiner: ParticipantID) -> Set<ParticipantID> {
        requests[joiner].flatMap { refusalsByInvitation[$0.signature] } ?? []
    }

    public private(set) var access: RoomAccess = .open

    public private(set) var removals: [ParticipantID: Removal] = [:]

    public private(set) var departures: [ParticipantID: Departure] = [:]

    private var established: Set<ParticipantID> = []

    private var confirmations: [Data: Date] = [:]

    private var rescinded: Set<Data> = []

    private var spent: Set<Data> = []

    public struct Removal: Hashable, Sendable {
        public let removed: ParticipantID
        public let by: ParticipantID
        public let at: Date

        public init(removed: ParticipantID, by: ParticipantID, at: Date) {
            self.removed = removed
            self.by = by
            self.at = at
        }
    }

    public struct Departure: Hashable, Sendable {
        public let member: ParticipantID
        public let at: Date
        public let entry: EntryHash

        public init(member: ParticipantID, at: Date, entry: EntryHash) {
            self.member = member
            self.at = at
            self.entry = entry
        }
    }

    public init(room: RoomID) {
        self.room = room
    }

    public var members: Set<ParticipantID> { established }

    public var invited: Set<ParticipantID> {
        Set(requests.filter { !rescinded.contains($0.value.signature) }.keys)
            .subtracting(established)
    }

    public func wasRescinded(_ person: ParticipantID) -> Bool {
        requests[person].map { !isOpen($0) } ?? false
    }

    public var confirmed: Set<ParticipantID> {
        Set(requests.filter { confirmations[$0.value.signature] != nil }.keys)
            .subtracting(established)
            .filter { !wasRescinded($0) }
    }

    private func confirmation(of person: ParticipantID) -> Date? {
        requests[person].flatMap { confirmations[$0.signature] }
    }

    public func isOpen(_ attestation: MembershipAttestation) -> Bool {
        !rescinded.contains(attestation.signature) && !spent.contains(attestation.signature)
    }

    public func confirmedAt(_ person: ParticipantID) -> Date? { confirmation(of: person) }

    public func hasConfirmed(_ person: ParticipantID) -> Bool { confirmation(of: person) != nil }

    public func hasConfirmed(_ attestation: MembershipAttestation) -> Bool {
        confirmations[attestation.signature] != nil
    }

    public func rewrapTargets(of member: ParticipantID) -> Set<ParticipantID> {
        var targets = members
        targets.remove(member)
        for (joiner, attestation) in requests
        where refusalsByInvitation[attestation.signature]?.contains(member) == true {
            targets.remove(joiner)
        }
        return targets
    }

    public func removal(of person: ParticipantID) -> Removal? { removals[person] }

    public func departure(of person: ParticipantID) -> Departure? { departures[person] }

    public var absent: Set<ParticipantID> { Set(removals.keys).union(departures.keys) }

    public func mayWrite(_ person: ParticipantID) -> Bool {
        removals[person] == nil && departures[person] == nil
    }

    public func hasRefused(_ joiner: ParticipantID, by member: ParticipantID) -> Bool {
        refusers(of: joiner).contains(member)
    }

    public func whoRefused(_ joiner: ParticipantID) -> Set<ParticipantID> {
        refusers(of: joiner)
    }

    public func hasDecided(on joiner: ParticipantID, as viewer: ParticipantID) -> Bool {
        admitters(of: joiner).contains(viewer) || refusers(of: joiner).contains(viewer)
    }

    public func pending(for viewer: ParticipantID, at instant: Date) -> [MembershipAttestation] {
        requests
            .filter {
                $0.key != viewer && !established.contains($0.key)
                    && mayDecide(viewer, on: $0.value)
                    && !hasDecided(on: $0.key, as: viewer)
                    && isOpen($0.value)
                    && !($0.value.hasLapsed(at: instant)
                        && confirmations[$0.value.signature] == nil)
            }
            .values
            .sorted { $0.issuedAt < $1.issuedAt }
    }

    public func awaitingConfirmation(by inviter: ParticipantID) -> [MembershipAttestation] {
        guard access.approvers(among: established, founder: founder).isEmpty else { return [] }
        return requests.values
            .filter {
                $0.inviter == inviter && established.contains($0.joiner)
                    && !hasDecided(on: $0.joiner, as: inviter)
            }
            .sorted { $0.issuedAt < $1.issuedAt }
    }

    public struct PendingInvitation: Hashable, Sendable {
        public let joiner: ParticipantID
        public let joinerKeys: IdentityPublicKeys
        public let invitedBy: ParticipantID
        public let issuedAt: Date
        public let expiresAt: Date

        public var isIndefinite: Bool { expiresAt >= .distantFuture }
    }

    public func pendingInvitations(at instant: Date) -> [PendingInvitation] {
        requests.values
            .filter {
                !established.contains($0.joiner)
                    && !($0.hasLapsed(at: instant) && confirmations[$0.signature] == nil)
                    && isOpen($0)
            }
            .map {
                PendingInvitation(
                    joiner: $0.joiner, joinerKeys: $0.joinerKeys, invitedBy: $0.inviter,
                    issuedAt: $0.issuedAt, expiresAt: $0.expiresAt)
            }
            .sorted {
                $0.issuedAt == $1.issuedAt
                    ? $0.joiner.rawValue.lexicographicallyPrecedes($1.joiner.rawValue)
                    : $0.issuedAt < $1.issuedAt
            }
    }

    public func lapsedInvitations(at instant: Date) -> [PendingInvitation] {
        requests.values
            .filter {
                !established.contains($0.joiner) && $0.hasLapsed(at: instant)
                    && confirmations[$0.signature] == nil
                    && isOpen($0)
            }
            .map {
                PendingInvitation(
                    joiner: $0.joiner, joinerKeys: $0.joinerKeys, invitedBy: $0.inviter,
                    issuedAt: $0.issuedAt, expiresAt: $0.expiresAt)
            }
            .sorted {
                $0.expiresAt == $1.expiresAt
                    ? $0.joiner.rawValue.lexicographicallyPrecedes($1.joiner.rawValue)
                    : $0.expiresAt > $1.expiresAt
            }
    }

    public mutating func set(access newAccess: RoomAccess, by author: ParticipantID) {
        guard author == founder else { return }
        access = newAccess
    }

    public func mayDecide(_ viewer: ParticipantID, on attestation: MembershipAttestation) -> Bool {
        eligibleApprovers(of: attestation).contains(viewer)
    }

    public func eligibleApprovers(of attestation: MembershipAttestation) -> Set<ParticipantID> {
        let standing = access.approvers(among: established, founder: founder)
            .subtracting([attestation.joiner])
        guard access.excludesTheInviter else { return standing }
        let others = standing.subtracting([attestation.inviter])
        return others.isEmpty ? standing : others
    }

    private func isAdmitted(_ joiner: ParticipantID) -> Bool {
        guard let attestation = requests[joiner] else { return false }

        guard confirmations[attestation.signature] != nil else { return false }

        guard isOpen(attestation) else { return false }

        let eligible = eligibleApprovers(of: attestation)
        let admitters = (admissionsByInvitation[attestation.signature] ?? []).intersection(eligible)
        let refusers = refusalsByInvitation[attestation.signature] ?? []

        switch access {
        case .open:
            return true
        case .founder:
            return founder.map { admitters.contains($0) } ?? false
        case .members:
            return !admitters.isEmpty
        case .anyMember:
            return !admitters.isEmpty
        case .atLeast(let count):
            return admitters.count >= effectiveThreshold(count, admitting: attestation)
        case .unanimous:
            guard refusers.isEmpty else { return false }
            return !eligible.isEmpty && eligible.isSubset(of: admitters)
        }
    }

    public func effectiveThreshold(_ chosen: Int, admitting attestation: MembershipAttestation) -> Int {
        max(1, min(chosen, eligibleApprovers(of: attestation).count))
    }

    public func effectiveThreshold(_ chosen: Int, admitting joiner: ParticipantID) -> Int {
        guard let attestation = requests[joiner] else {
            return max(1, min(chosen, established.subtracting([joiner]).count))
        }
        return effectiveThreshold(chosen, admitting: attestation)
    }

    public func isUnanimous(_ joiner: ParticipantID) -> Bool {
        refusers(of: joiner).isEmpty && !admitters(of: joiner).isEmpty
    }

    public func verify(
        _ attestation: MembershipAttestation,
        inviterKeys: IdentityPublicKeys,
        at instant: Date,
        allowingExpired: Bool = false
    ) throws {
        guard attestation.room == room else { throw MembershipError.wrongRoom }
        guard members.contains(attestation.inviter) else {
            throw MembershipError.inviterNotAMember
        }
        guard isOpen(attestation) else { throw MembershipError.invitationWithdrawn }
        try attestation.verify(
            against: inviterKeys, at: instant, allowingExpired: allowingExpired)
    }

    // MARK: Folding

    public static let rosterShaping: Set<PayloadType> = [
        .roomProfile, .roomAccess, .joinRequest, .joinConfirmed, .invitationRescinded, .admission,
        .removal, .departure,
    ]

    public mutating func apply(_ entry: RenderedEntry, body: Payload) {
        switch body.type {
        case .roomProfile:
            if founder == nil {
                founder = entry.author
                establish(entry.author)
            }

        case .roomAccess:
            guard let body = try? body.decode(RoomAccessBody.self) else { return }
            set(access: body.access, by: entry.author)

        case .joinRequest:
            guard let request = try? body.decode(JoinRequestBody.self),
                request.attestation.room == room
            else { return }
            requests[request.attestation.joiner] = request.attestation

            if isAdmitted(request.attestation.joiner) {
                establish(request.attestation.joiner)
            }

        case .joinConfirmed:
            guard let confirmation = try? body.decode(JoinConfirmedBody.self),
                let attestation = requests[confirmation.joiner],
                (try? confirmation.verify(confirming: attestation)) != nil
            else { return }
            let at = entry.wallTime
            if let already = confirmations[attestation.signature] {
                confirmations[attestation.signature] = Swift.min(already, at)
            } else {
                confirmations[attestation.signature] = at
            }

            if isAdmitted(confirmation.joiner) { establish(confirmation.joiner) }

        case .invitationRescinded:
            guard let taken = try? body.decode(InvitationRescindedBody.self),
                established.contains(entry.author),
                let attestation = requests.values.first(where: { $0.signature == taken.invitation })
            else { return }
            guard !established.contains(attestation.joiner) else { return }
            rescinded.insert(taken.invitation)

        case .admission:
            guard let decision = try? body.decode(AdmissionBody.self) else { return }
            guard let invitation = decision.invitation ?? requests[decision.joiner]?.signature
            else { return }
            if decision.admitted {
                admissionsByInvitation[invitation, default: []].insert(entry.author)
                refusalsByInvitation[invitation]?.remove(entry.author)
            } else {
                refusalsByInvitation[invitation, default: []].insert(entry.author)
                admissionsByInvitation[invitation]?.remove(entry.author)
            }

            guard requests[decision.joiner] != nil else { return }
            if isAdmitted(decision.joiner) { establish(decision.joiner) }

        case .removal:
            guard let body = try? body.decode(RemovalBody.self) else { return }
            apply(removalOf: body.removed, by: entry.author, at: entry.wallTime)

        case .departure:
            apply(departureOf: entry.author, at: entry.wallTime, entry: entry.id)

        default:
            break
        }
    }

    private mutating func establish(_ person: ParticipantID) {
        established.insert(person)
        removals[person] = nil
        departures[person] = nil
    }

    private mutating func apply(removalOf removed: ParticipantID, by author: ParticipantID, at when: Date) {
        guard established.contains(author), established.contains(removed) else { return }

        guard removed != author else { return }

        guard removals[removed] == nil else { return }

        removals[removed] = Removal(removed: removed, by: author, at: when)
        established.remove(removed)

        if let attestation = requests[removed] {
            admissionsByInvitation[attestation.signature] = nil
            refusalsByInvitation[attestation.signature] = nil
        }
        spend(requests[removed])
        requests[removed] = nil
    }

    private mutating func spend(_ attestation: MembershipAttestation?) {
        guard let attestation else { return }
        spent.insert(attestation.signature)
        confirmations[attestation.signature] = nil
    }

    private mutating func apply(
        departureOf member: ParticipantID, at when: Date, entry: EntryHash
    ) {
        guard established.contains(member) else { return }

        departures[member] = Departure(member: member, at: when, entry: entry)
        established.remove(member)

        if let attestation = requests[member] {
            admissionsByInvitation[attestation.signature] = nil
            refusalsByInvitation[attestation.signature] = nil
        }
        spend(requests[member])
        requests[member] = nil
    }

    public var keyTurner: ParticipantID? {
        if let founder, established.contains(founder) { return founder }
        return established.min { $0.rawValue.lexicographicallyPrecedes($1.rawValue) }
    }
}
