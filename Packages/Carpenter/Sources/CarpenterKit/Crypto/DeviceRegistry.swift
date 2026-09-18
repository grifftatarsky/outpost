import Foundation

public struct DeviceRegistry: Hashable, Sendable {
    private struct Enrolment: Hashable, Sendable {
        let certificate: DeviceCertificate
        var revokedAt: Date?

        var publicKey: Data { certificate.devicePublicKey }
        var issuedAt: Date { certificate.issuedAt }
    }

    public let identity: IdentityPublicKeys

    private var devices: [DeviceID: Enrolment] = [:]

    public init(identity: IdentityPublicKeys) {
        self.identity = identity
    }

    public var deviceCount: Int { devices.count }

    public var deviceIDs: Set<DeviceID> { Set(devices.keys) }

    public var certificates: [DeviceCertificate] { devices.values.map(\.certificate) }

    public mutating func admit(_ certificate: DeviceCertificate) throws {
        try certificate.verify(against: identity)

        if let existing = devices[certificate.device] {
            guard existing.publicKey == certificate.devicePublicKey else {
                throw CryptoError.deviceMismatch
            }
            return
        }

        devices[certificate.device] = Enrolment(
            certificate: certificate,
            revokedAt: nil
        )
    }

    public mutating func revoke(_ revocation: DeviceRevocation) throws {
        try revocation.verify(against: identity)

        guard var enrolment = devices[revocation.device] else {
            throw CryptoError.unknownDevice
        }

        enrolment.revokedAt = min(enrolment.revokedAt ?? revocation.revokedAt, revocation.revokedAt)
        devices[revocation.device] = enrolment
    }

    public func standing(of device: DeviceID) -> (addedAt: Date, revokedAt: Date?)? {
        devices[device].map { ($0.issuedAt, $0.revokedAt) }
    }

    public func signingKey(for device: DeviceID) -> Data? {
        devices[device]?.publicKey
    }

    public func isAuthorized(_ device: DeviceID, at instant: Date) -> Bool {
        guard let enrolment = devices[device] else { return false }
        guard instant >= enrolment.issuedAt else { return false }
        guard let revokedAt = enrolment.revokedAt else { return true }
        return instant < revokedAt
    }

    public func isValidSignature(
        _ signature: Data, for message: Data, from device: DeviceID, at instant: Date
    ) throws -> Bool {
        guard isAuthorized(device, at: instant), let publicKey = signingKey(for: device) else {
            return false
        }
        return try DeviceKeys.isValidSignature(signature, for: message, publicKey: publicKey)
    }
}
