import Foundation
import Testing

@testable import CarpenterApp

extension AppSession {
    func approveNewDevice(_ newDevice: AppSession, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        if newDevice.state == .checkingForRegistration {
            newDevice.checkAccount(with: StubAccountRegistry(hasMember: true))
            await newDevice.settleRegistration()
        }
        let pending = try #require(newDevice.pendingDevice?.id, "the new device is not waiting for approval")
        var approved = false
        while !approved, Date() < deadline {
            if let request = deviceRequests.first(where: { $0.device == pending }) {
                try await approveDevice(request)
                approved = true
                break
            }
            await newDevice.refreshDeviceSync()
            await refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(20))
        }
        try #require(approved, "the request from the new device never reached the approving device")
        while newDevice.enrolment == nil, Date() < deadline {
            await newDevice.refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(20))
        }
        try #require(newDevice.enrolment != nil, "the new device never took its approval")
    }
}
