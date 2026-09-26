import CarpenterKit
import Foundation

// MARK: When another of this member's devices removes this one

extension AppSession {
    var thisDeviceWasRemoved: Bool {
        guard let enrolment else { return false }
        return replica.registry(for: enrolment.identity.id)?.standing(of: enrolment.device.id)?.revokedAt != nil
    }

    func eraseAfterRemoval() async {
        guard enrolment != nil else { return }
        Diagnostics.identity.notice("this device was removed by another of your devices; erasing what it holds")
        enrolment = nil
        state = .removed

        incomingTask?.cancel()
        incomingTask = nil
        deviceSync = nil

        let held = chains
        chains = [:]
        for (room, chain) in held {
            for epoch in chain.knownEpochs {
                try? await storage.keychain.remove(Self.epochKey(room, epoch))
            }
        }
        let store = IdentityStore(keychain: storage.keychain)
        await persistOrReport("the mark that this device was removed") {
            try await store.markRemoved()
        }
        try? await store.forgetDevice()
        try? await store.forgetCertificate()
        try? await storage.log.removeAll()

        replica = Replica()
        persisted = PersistedState()
        rooms = []
        try? await saveState()
    }
}
