import Foundation

public enum RegistrationStall: Equatable, Sendable {
    case accountUnreadable
    case accountOffline
    case signedOut
    case restricted
    case keychainUnreadable
    case heldBySecurity
}

public enum AccountOccupancy: Hashable, Sendable {
    case occupied
    case empty
    case offline
    case signedOut
    case restricted
    case undetermined
    case held
}

public protocol AccountRegistry: Sendable {
    func occupancy() async -> AccountOccupancy
}
