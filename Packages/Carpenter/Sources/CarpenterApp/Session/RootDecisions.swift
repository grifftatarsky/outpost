import CarpenterKit
import Foundation

public enum RootScreen: Equatable, Sendable {
    case loading
    case checkingForRegistration
    case registrationStalled(RegistrationStall)
    case onboarding(Onboarding)
    case ready
    case failed(String)
    case awaitingApproval
    case removed

    public enum Onboarding: Equatable, Sendable {
        case newIdentity
        case nameOnly
    }

    public static func `for`(_ state: AppSession.State) -> RootScreen {
        switch state {
        case .loading:
            return .loading
        case .checkingForRegistration:
            return .checkingForRegistration
        case .registrationStalled(let why):
            return .registrationStalled(why)
        case .needsIdentity:
            return .onboarding(.newIdentity)
        case .needsProfile:
            return .onboarding(.nameOnly)
        case .ready:
            return .ready
        case .failed(let reason):
            return .failed(reason)
        case .awaitingApproval:
            return .awaitingApproval
        case .removed:
            return .removed
        }
    }
}

public enum DeviceSyncDecision: Equatable, Sendable {
    case wait
    case alreadyRunning
    case start(DeviceID)

    public static func make(device: DeviceID?, startedFor: DeviceID?) -> DeviceSyncDecision {
        guard let device else { return .wait }
        return device == startedFor ? .alreadyRunning : .start(device)
    }
}

public enum SyncRound {
    public struct Outcome: Sendable {
        public let syncedAt: Date?
        public let deviceSyncFailed: Bool
        public let mailboxFailed: Bool
        public var erased = false

        public var messageForMember: String? { nil }
    }

    @MainActor
    public static func run(
        deathmark: () async -> Bool = { false },
        deviceSync: () async throws -> Void,
        mailbox: () async throws -> Void,
        now: () -> Date = { Date() }
    ) async -> Outcome {
        if await deathmark() {
            var outcome = Outcome(syncedAt: nil, deviceSyncFailed: false, mailboxFailed: false)
            outcome.erased = true
            return outcome
        }
        var deviceSyncFailed = false
        do {
            try await deviceSync()
        } catch {
            deviceSyncFailed = true
        }

        var syncedAt: Date?
        var mailboxFailed = false

        do {
            try await mailbox()
            syncedAt = now()
        } catch {
            mailboxFailed = true
        }

        return Outcome(
            syncedAt: syncedAt, deviceSyncFailed: deviceSyncFailed, mailboxFailed: mailboxFailed)
    }
}

public struct AcceptedInvitation: Codable, Hashable, Sendable {
    public var attestation: MembershipAttestation
    public var confirmedAt: Date

    public init(attestation: MembershipAttestation, confirmedAt: Date) {
        self.attestation = attestation
        self.confirmedAt = confirmedAt
    }
}
