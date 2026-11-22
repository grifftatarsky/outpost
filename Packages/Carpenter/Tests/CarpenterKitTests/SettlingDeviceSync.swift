import Foundation

@testable import CarpenterApp

extension AppSession {
    func settleDeviceSync(until condition: () -> Bool) async {
        let deadline = TestDeadline.fromNow
        while !condition(), Date() < deadline {
            await refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    func settleDeviceSync() async {
        let deadline = TestDeadline.fromNow
        var quiet = 0
        while quiet < 4, Date() < deadline {
            await refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(25))
            quiet = publishing || publishAgain ? 0 : quiet + 1
        }
    }
}
