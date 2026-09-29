import CarpenterKit
import Foundation

struct KeptSalt: Codable, Equatable, Sendable {
    var salt: AddressSalt
    var since: Date
    var until: Date?
    var storedAt: Date?
}

struct AddressBook: Codable, Equatable, Sendable {
    static let overlap = SyncSession.packetWaitsFor
    static let key = KeychainKey("address.book")

    private(set) var own: [KeptSalt] = []
    private(set) var peers: [ParticipantID: [KeptSalt]] = [:]

    var ownCurrent: AddressSalt? { own.last(where: { $0.until == nil })?.salt }

    func current(of person: ParticipantID) -> AddressSalt? {
        peers[person]?.last(where: { $0.until == nil })?.salt
    }

    func ownRecent(at now: Date) -> [AddressSalt?] {
        Self.recent(own, at: now)
    }

    func recent(of person: ParticipantID, at now: Date) -> [AddressSalt?] {
        Self.recent(peers[person] ?? [], at: now)
    }

    func learned(_ salt: AddressSalt, of person: ParticipantID) -> Date? {
        peers[person]?.first { $0.salt == salt }?.storedAt
    }

    private static func recent(_ kept: [KeptSalt], at now: Date) -> [AddressSalt?] {
        let live = kept.reversed().filter { $0.until.map { now.timeIntervalSince($0) < overlap } ?? true }
        return live.map(\.salt) + [nil]
    }

    var ownNumber: UInt32 { own.map(\.salt.number).max() ?? 0 }

    mutating func rotateOwn(at now: Date) -> AddressSalt {
        let salt = AddressSalt.fresh(after: ownNumber)
        for index in own.indices where own[index].until == nil { own[index].until = now }
        own.append(KeptSalt(salt: salt, since: now))
        return salt
    }

    @discardableResult
    mutating func keepOwn(_ salt: AddressSalt, since: Date, at now: Date) -> Bool {
        guard !own.contains(where: { $0.salt == salt }) else { return false }
        own.append(KeptSalt(salt: salt, since: since))
        settle(&own, at: now)
        return true
    }

    @discardableResult
    mutating func adopt(_ salt: AddressSalt, for person: ParticipantID, storedAt: Date, at now: Date) -> Bool {
        var kept = peers[person] ?? []
        guard !kept.contains(where: { $0.salt == salt }) else { return false }
        if let newest = kept.compactMap(\.storedAt).max(), newest >= storedAt { return false }
        kept.append(KeptSalt(salt: salt, since: storedAt, storedAt: storedAt))
        settle(&kept, at: now)
        peers[person] = kept
        return true
    }

    private func settle(_ kept: inout [KeptSalt], at now: Date) {
        kept.sort { lhs, rhs in
            if lhs.since != rhs.since { return lhs.since < rhs.since }
            return lhs.salt.bytes.lexicographicallyPrecedes(rhs.salt.bytes)
        }
        for index in kept.indices {
            let isNewest = index == kept.count - 1
            if isNewest {
                kept[index].until = nil
            } else if kept[index].until == nil {
                kept[index].until = now
            }
        }
    }

    func hasExpired(at now: Date) -> Bool {
        (own + peers.values.flatMap { $0 }).contains { $0.until.map { now.timeIntervalSince($0) >= Self.overlap } ?? false }
    }

    mutating func forgetExpired(at now: Date) -> Bool {
        guard hasExpired(at: now) else { return false }
        own.removeAll { $0.until.map { now.timeIntervalSince($0) >= Self.overlap } ?? false }
        for (person, kept) in peers {
            peers[person] = kept.filter { $0.until.map { now.timeIntervalSince($0) < Self.overlap } ?? true }
        }
        return true
    }

    var held: [HeldAddress] {
        own.map { HeldAddress(owner: nil, salt: $0.salt, since: $0.since, storedAt: nil) }
            + peers.flatMap { person, kept in
                kept.map { HeldAddress(owner: person, salt: $0.salt, since: $0.since, storedAt: $0.storedAt) }
            }
    }
}
