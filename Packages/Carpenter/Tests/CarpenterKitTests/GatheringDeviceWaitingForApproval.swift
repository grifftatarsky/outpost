@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

extension Gathering {
    @discardableResult
    func deviceWaitingForApproval(_ name: String, of person: String) async throws -> AppSession {
        let first = try #require(devices.first { $0.person == person })
        let new = try makeDevice(name, of: person, keychain: await first.keychain.sibling()).session
        await new.load()
        if new.state == .checkingForRegistration {
            new.checkAccount(with: StubAccountRegistry(hasMember: true))
            await new.settleRegistration()
        }
        try await quiesce()
        try #require(new.pendingDevice != nil, "precondition: \(name) is waiting for one of \(person)'s devices")
        return new
    }

    func takeApproval(on name: String) async throws {
        let new = self[name]
        for _ in 0..<12 where new.enrolment == nil {
            await new.refreshDeviceSync()
            try await quiesce()
        }
        try #require(new.enrolment != nil, "precondition: \(name) took its approval")
    }
}
