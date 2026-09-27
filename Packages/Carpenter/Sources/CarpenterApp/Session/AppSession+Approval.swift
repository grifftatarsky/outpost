import CarpenterKit
import Foundation

// MARK: A new device waits until one of this member's devices approves it

extension AppSession {
    func noteRequest(_ record: SiblingRecord) {
        guard let enrolment, let request = DeviceRequest(record: record) else { return }
        let registry = replica.registry(for: enrolment.identity.id)
        guard request.device != enrolment.device.id,
            registry?.standing(of: request.device) == nil,
            !declinedDeviceRequests.contains(request.device),
            !deviceRequests.contains(request)
        else { return }
        deviceRequests.append(request)
        Diagnostics.identity.notice(
            "approval: a new device asked to join (\(request.code, privacy: .public))")
    }

    public func approveDevice(_ request: DeviceRequest) async throws {
        guard let enrolment, let deviceSync else { throw AppSessionError.noIdentity }
        let certificate = try DeviceCertificate.issue(
            for: request.devicePublicKey, agreementKey: request.agreementKey, by: enrolment.identity,
            at: clock.now, approvedBy: enrolment.device)
        try replica.admit(certificate, storedAt: authorityNow())
        recordAuthority()
        try await saveState()

        let own = replica.registry(for: enrolment.identity.id)
        let approval = DeviceApproval(
            identity: enrolment.identity, certificates: own?.certificates ?? [],
            revocations: own?.knownRevocations ?? [], stored: own?.storedTimes ?? [:])
        try await deviceSync.send(
            [try approval.record(from: enrolment.device.id, to: request)],
            deleting: [SiblingRecord.Name(writer: request.device, kind: .request)])
        deviceRequests.removeAll { $0 == request }
        Diagnostics.identity.notice("approval: approved a new device (\(request.code, privacy: .public))")
        refresh()
        sendOwnEntries()
    }

    public func declineDevice(_ request: DeviceRequest) async {
        deviceRequests.removeAll { $0 == request }
        declinedDeviceRequests.insert(request.device)
        do {
            try await deviceSync?.send(
                [], deleting: [SiblingRecord.Name(writer: request.device, kind: .request)])
        } catch {
            Diagnostics.identity.error(
                "approval: could not remove a declined request: \(String(describing: error), privacy: .public)")
        }
        Diagnostics.identity.notice("approval: declined a new device (\(request.code, privacy: .public))")
    }

    func takeApproval(_ record: SiblingRecord) async {
        guard enrolment == nil, let device = pendingDevice else { return }
        let approval: DeviceApproval
        let identity: Identity
        do {
            approval = try DeviceApproval(record: record, opening: device)
            identity = try approval.identity()
        } catch {
            Diagnostics.identity.error("approval: an approval for this device would not open")
            return
        }
        if let pendingIdentity, pendingIdentity.id != identity.id {
            Diagnostics.identity.error("approval: refused an approval from a different member")
            return
        }

        let arrived = record.modified ?? clock.now
        var check = Replica()
        check.introduce(identity.publicKeys)
        for certificate in approval.certificates {
            try? check.admit(certificate, storedAt: approval.stored[certificate.digest] ?? arrived)
        }
        for revocation in approval.revocations {
            try? check.revoke(revocation, storedAt: approval.stored[revocation.digest] ?? arrived)
        }
        guard let standing = check.registry(for: identity.id)?.standing(of: device.id),
            standing.revokedAt == nil, !standing.isRoot
        else {
            Diagnostics.identity.error("approval: the approval did not approve this device")
            return
        }

        let store = IdentityStore(keychain: storage.keychain)
        do {
            if try await store.loadIdentity() == nil { try await store.save(identity) }
            if let own = approval.certificates.first(where: { $0.device == device.id }) {
                try await store.keepCertificate(own)
            }
        } catch {
            Diagnostics.identity.error(
                "approval: could not keep the identity: \(String(describing: error), privacy: .public)")
            return
        }
        persisted.certificates = approval.certificates
        persisted.revocations = approval.revocations
        persisted.authorityStored = check.storedTimes
        persisted.authorityIsLegacy = false
        await persistOrReport("the approval of this device") { try await saveState() }

        try? await deviceSync?.send(
            [], deleting: [record.name, SiblingRecord.Name(writer: device.id, kind: .request)])
        Diagnostics.identity.notice("approval: this device was approved; opening")
        pendingDevice = nil
        pendingIdentity = nil
        await load()
    }

    func noteDevicesAddedWithTheRecoveryKey(since before: Set<DeviceID>) {
        guard let enrolment, let registry = replica.registry(for: enrolment.identity.id) else { return }
        let added = registry.deviceIDs.subtracting(before).filter {
            $0 != enrolment.device.id && registry.standing(of: $0)?.isRoot == true
        }
        guard !added.isEmpty else { return }
        persisted.devicesAddedWithTheRecoveryKey.formUnion(added)
        Diagnostics.identity.notice(
            "approval: \(added.count, privacy: .public) device(s) joined with the recovery key rather than an approval")
    }
}
