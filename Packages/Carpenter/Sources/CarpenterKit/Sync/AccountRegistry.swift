import Foundation

public enum RegistrationStall: Equatable, Sendable {
    case accountUnreadable
    case accountOffline
    case keychainUnreadable
    case heldBySecurity
}

public enum AccountOccupancy: Sendable, Equatable {
    case occupied
    case empty
    case offline
    case undetermined
    case held
}

public protocol AccountRegistry: Sendable {
    func occupancy() async -> AccountOccupancy
}
