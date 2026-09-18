import Foundation

public enum RegistrationStall: Equatable, Sendable {
    case accountHasAMember
    case accountUnreadable
    case accountOffline
    case keychainUnreadable
}

public enum AccountOccupancy: Sendable, Equatable {
    case occupied
    case empty
    case offline
    case undetermined
}

public protocol AccountRegistry: Sendable {
    func occupancy() async -> AccountOccupancy
}
