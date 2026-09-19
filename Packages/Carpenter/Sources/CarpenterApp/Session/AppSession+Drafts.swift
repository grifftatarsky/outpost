import CarpenterKit
import Foundation

extension AppSession {
    public func draft(at place: DraftPlace) -> String {
        drafts[place] ?? ""
    }

    public func noteDraft(_ words: String, at place: DraftPlace) {
        drafts[place] = words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : words
    }

    public func keepDraft(_ words: String, at place: DraftPlace) async {
        noteDraft(words, at: place)
        await sealDraft(at: place)
    }

    public func sealDraft(at place: DraftPlace) async {
        guard enrolment != nil else { return }
        guard drafts[place] != nil else {
            guard persisted.sealedDraft(at: place) != nil else { return }
            persisted.setSealedDraft(nil, at: place)
            await persistOrReport("a draft") { try await saveState() }
            return
        }
        let key: Data
        do {
            key = try await draftSealingKey()
        } catch {
            Diagnostics.sync.error(
                "drafts: no key to seal a draft with, so it is kept in memory only: \(String(describing: error), privacy: .public)")
            return
        }
        guard let words = drafts[place], let sealed = try? DraftSeal.seal(words, at: place, with: key) else { return }
        persisted.setSealedDraft(sealed, at: place)
        await persistOrReport("a draft") { try await saveState() }
    }

    public var outpostDraftCount: Int {
        drafts.keys.filter(\.isOutpost).count
    }

    public func deleteOutpostDrafts() async {
        let places = Set(drafts.keys.filter(\.isOutpost)).union(persisted.sealedDrafts.map(\.0).filter(\.isOutpost))
        guard !places.isEmpty else { return }
        for place in places {
            drafts[place] = nil
            persisted.setSealedDraft(nil, at: place)
        }
        await persistOrReport("deleting drafts") { try await saveState() }
    }

    public func keepUnsentReply(_ words: String, in room: RoomID) async -> Bool {
        guard enrolment != nil, rooms.contains(where: { $0.id == room }) else { return false }
        let already = draft(at: .room(room))
        await keepDraft(already.isEmpty ? words : already + "\n" + words, at: .room(room))
        return persisted.drafts[room] != nil
    }

    func openDrafts() async {
        let sealed = persisted.sealedDrafts
        guard !sealed.isEmpty else {
            drafts = [:]
            return
        }
        guard let key = try? await draftSealingKey() else { return }
        var opened: [DraftPlace: String] = [:]
        for (place, box) in persisted.sealedDrafts {
            if let words = DraftSeal.open(box, at: place, with: key) { opened[place] = words }
        }
        drafts = opened
    }

    func draftSealingKey() async throws -> Data {
        if let draftKey { return draftKey }
        if let draftKeyInFlight { return try await draftKeyInFlight.value }
        let keychain = storage.keychain
        let fetching = Task { () async throws -> Data in
            if let kept = try await keychain.data(for: DraftSeal.key) { return kept }
            let fresh = DraftSeal.newKey()
            try await keychain.set(fresh, for: DraftSeal.key, scope: .device)
            return fresh
        }
        draftKeyInFlight = fetching
        defer { draftKeyInFlight = nil }
        let key = try await fetching.value
        draftKey = key
        return key
    }
}
