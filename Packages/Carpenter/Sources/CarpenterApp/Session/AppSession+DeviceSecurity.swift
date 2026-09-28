import CarpenterKit
import Foundation

// MARK: Advanced On Device Security: what this phone keeps, and when it opens

extension AppSession {
    public var protection: ProtectionDial { storage.protection }

    public var sealsWhileLocked: Bool { (protectionChoice?.chosen ?? storage.protection.current) == .whileUnlocked }

    public var storageIsSealed: Bool { phoneIsLocked && storage.protection.current == .whileUnlocked }

    public func phoneLocked(_ locked: Bool) {
        guard phoneIsLocked != locked else { return }
        phoneIsLocked = locked
        Diagnostics.identity.notice("storage: this phone \(locked ? "locked" : "unlocked", privacy: .public)")
    }

    public func readProtection() async {
        try? await inTurn { await self.readChosenProtection() }
    }

    public func sealWhileLocked(_ on: Bool) async throws {
        let wanted: StorageProtection = on ? .whileUnlocked : .afterFirstUnlock
        try await inTurn {
            if wanted != self.protectionChoice?.chosen { try await self.recordChoice(wanted) }
            try await self.applyChosenProtection()
        }
    }

    public func applyProtection() async throws {
        try await inTurn { try await self.applyChosenProtection() }
    }

    private func readChosenProtection() async {
        switch await ProtectionChoice.read(from: storage.keychain) {
        case .read(let choice):
            protectionChoice = choice
            storage.protection.turn(to: choice.chosen)
        case .unreadable:
            storage.protection.turn(to: .whileUnlocked)
            Diagnostics.identity.notice(
                "storage: the protection setting could not be read; everything stays sealed until it can be")
        }
    }

    private func recordChoice(_ wanted: StorageProtection) async throws {
        let choice = ProtectionChoice(chosen: wanted, applied: protectionChoice?.applied)
        let before = storage.protection.current
        storage.protection.turn(to: wanted)
        do {
            try await choice.write(to: storage.keychain)
        } catch {
            storage.protection.turn(to: before)
            throw error
        }
        protectionChoice = choice
        Diagnostics.identity.notice("storage: what this phone keeps now opens \(wanted.rawValue, privacy: .public)")
    }

    private func applyChosenProtection() async throws {
        guard let choice = protectionChoice, !choice.isApplied, !storageIsSealed else { return }
        let wanted = choice.chosen
        do {
            try await storage.keychain.protect(as: wanted)
        } catch {
            Diagnostics.identity.error(
                "storage: the keychain was not all protected (\(String(describing: error), privacy: .public))")
            throw AppSessionError.protectionUnfinished
        }
        let locations = storage.locations
        let refused = await Task.detached(priority: .userInitiated) {
            ProtectedFiles.reprotect(locations, as: wanted)
        }.value
        guard refused.isEmpty else {
            Diagnostics.identity.error("storage: \(refused.count, privacy: .public) file(s) were not protected")
            throw AppSessionError.protectionUnfinished
        }
        let applied = ProtectionChoice(chosen: wanted, applied: wanted)
        try await applied.write(to: storage.keychain)
        protectionChoice = applied
    }

    private func inTurn(_ work: @escaping @MainActor @Sendable () async throws -> Void) async throws {
        let before = protectionWork
        let mine = Task { @MainActor in
            _ = await before?.result
            try await work()
        }
        protectionWork = mine
        try await mine.value
    }
}
