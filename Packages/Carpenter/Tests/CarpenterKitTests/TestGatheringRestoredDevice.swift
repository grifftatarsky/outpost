@testable import CarpenterApp
import CarpenterKitTesting
import Foundation

extension Gathering {
    func restoredDevice(_ name: String, of person: String, fromRecoveryKey key: String) async throws {
        let device = try makeDevice(name, of: person, keychain: InMemoryKeychainStore())
        await device.session.load()
        try await device.session.restore(fromRecoveryKey: key)
        try await quiesce()
    }
}
