import CarpenterKit
import Foundation

// MARK: Comparing the characters again, after the introduction

extension AppSession {
    public func checkedAt(_ person: ParticipantID) -> Date? {
        persisted.preferences.checkedAt(person)
    }

    public func markChecked(_ person: ParticipantID) async {
        persisted.preferences.setChecked(person, at: clock.now, stamp: stamp())
        await savePreferences()
        refresh()
    }

    public func comparisonToOffer(in room: RoomID) -> [ParticipantID] {
        guard let me = enrolment?.identity.id else { return [] }
        let roster = roster(of: room)
        guard roster.members.contains(me) else { return [] }
        let myInviter = roster.requests[me]?.inviter
        let preferences = persisted.preferences

        return roster.members
            .filter { person in
                person != me && person != myInviter
                    && roster.requests[person]?.inviter != me
                    && preferences.checkedAt(person) == nil
                    && !preferences.wasOfferedComparison(with: person)
                    && replica.registry(for: person)?.identity != nil
            }
            .sorted { $0.rawValue.lexicographicallyPrecedes($1.rawValue) }
    }

    public func comparisonCode(with person: ParticipantID) -> [(Member, String)]? {
        guard let me = enrolment?.identity,
            let theirs = replica.registry(for: person)?.identity
        else { return nil }
        return [(me.id, me.publicKeys), (person, theirs)]
            .map { id, keys in (member(id), comparisonHalf(for: id, keys: keys)) }
            .sorted { $0.0.id.rawValue.lexicographicallyPrecedes($1.0.id.rawValue) }
    }

    private func comparisonHalf(for person: ParticipantID, keys: IdentityPublicKeys) -> String {
        if let known = cachedComparisonHalves[person] { return known }
        let half = ComparisonCode.half(for: keys)
        cachedComparisonHalves[person] = half
        return half
    }

    public func markComparisonOffered(_ people: [ParticipantID]) async {
        guard !people.isEmpty else { return }
        let stamp = stamp()
        for person in people {
            persisted.preferences.setOfferedComparison(with: person, stamp: stamp)
        }
        await savePreferences()
    }
}
