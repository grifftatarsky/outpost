import CarpenterKit
import Foundation

public struct PreparedDeathmark: Codable, Hashable, Sendable {
    public let mark: Data
    public let device: DeviceID
    public let checkOff: Data

    public func post(on board: any DeathmarkBoard) async throws {
        try await board.post(mark)
        try await board.checkOff(device, sealed: checkOff)
    }
}

public enum DeathmarkVerdict: Hashable, Sendable {
    case carryOn
    case eraseThisDevice
}

extension AppSession {
    public func prepareDeathmark() throws -> PreparedDeathmark {
        guard let enrolment, let registry = replica.registry(for: enrolment.identity.id) else {
            throw AppSessionError.noIdentity
        }
        let me = enrolment.device.id
        let mark = try Deathmark.issue(
            for: enrolment.identity.id, listing: registry.activeDevices.union([me]), by: enrolment.device,
            at: clock.now)
        return PreparedDeathmark(
            mark: try mark.sealed(for: enrolment.identity), device: me,
            checkOff: try Deathmark.sealedCheckOff(me, for: enrolment.identity))
    }

    public func leaveDeathmark(on board: any DeathmarkBoard) async throws {
        try await prepareDeathmark().post(on: board)
    }

    public func deathmarkNamesThisDevice(on board: any DeathmarkBoard) async -> Bool {
        guard let enrolment, let posted = try? await board.read(), let storedAt = posted.storedAt,
            let mark = Deathmark.open(posted.sealed, for: enrolment.identity),
            mark.devices.contains(enrolment.device.id),
            let registry = replica.registry(for: enrolment.identity.id)
        else { return false }
        return mark.isSigned(by: registry, storedAt: storedAt)
    }

    public func obeyDeathmark(on board: any DeathmarkBoard) async -> DeathmarkVerdict {
        guard let enrolment, let posted = try? await board.read(), let storedAt = posted.storedAt,
            let mark = Deathmark.open(posted.sealed, for: enrolment.identity),
            mark.devices.contains(enrolment.device.id),
            let registry = replica.registry(for: enrolment.identity.id),
            mark.isSigned(by: registry, storedAt: storedAt)
        else { return .carryOn }
        let me = enrolment.device.id
        if let tick = try? Deathmark.sealedCheckOff(me, for: enrolment.identity) {
            try? await board.checkOff(me, sealed: tick)
        }
        if Set(mark.devices).subtracting(posted.checkedOff).subtracting([me]).isEmpty {
            try? await board.clear()
        }
        Diagnostics.identity.notice("deathmark: this device is on the list; erasing it")
        return .eraseThisDevice
    }
}
