import CarpenterKit
import Foundation

extension AppSession {
    public func draft(in room: RoomID) -> String {
        drafts[room] ?? ""
    }

    public func noteDraft(_ words: String, in room: RoomID) {
        drafts[room] = words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : words
    }

    public func keepDraft(_ words: String, in room: RoomID) async {
        noteDraft(words, in: room)
        await sealDraft(in: room)
    }

    public func sealDraft(in room: RoomID) async {
        guard enrolment != nil else { return }
        guard drafts[room] != nil else {
            guard persisted.drafts[room] != nil else { return }
            persisted.drafts[room] = nil
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
        guard let words = drafts[room], let sealed = try? DraftSeal.seal(words, in: room, with: key) else { return }
        persisted.drafts[room] = sealed
        await persistOrReport("a draft") { try await saveState() }
    }

    public func keepUnsentReply(_ words: String, in room: RoomID) async -> Bool {
        guard enrolment != nil, rooms.contains(where: { $0.id == room }) else { return false }
        let already = draft(in: room)
        await keepDraft(already.isEmpty ? words : already + "\n" + words, in: room)
        return persisted.drafts[room] != nil
    }

    func openDrafts() async {
        guard !persisted.drafts.isEmpty else {
            drafts = [:]
            return
        }
        guard let key = try? await draftSealingKey() else { return }
        var opened: [RoomID: String] = [:]
        for (room, sealed) in persisted.drafts {
            if let words = DraftSeal.open(sealed, in: room, with: key) { opened[room] = words }
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
