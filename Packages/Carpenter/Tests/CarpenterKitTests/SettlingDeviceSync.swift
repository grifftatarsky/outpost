import Foundation

@testable import CarpenterApp

extension AppSession {
    func settleDeviceSync(until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            await refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    func settleDeviceSync() async {
        let deadline = Date().addingTimeInterval(5)
        var quiet = 0
        while quiet < 4, Date() < deadline {
            await refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(25))
            quiet = publishing || publishAgain ? 0 : quiet + 1
        }
    }
}
