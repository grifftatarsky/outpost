import CarpenterApp
import CarpenterCloudKit
import CarpenterKit
import Foundation
import OSLog

extension AppShell {
    func answerWithoutAWindow(_ answer: NotificationAnswer) async {
        Diagnostics.sync.notice("push: no window is listening; answering from the background")
        await cloud.restoreDirectory()
        await session.load()
        guard session.enrolment != nil else {
            Diagnostics.sync.error("push: nobody is signed in here to answer as")
            return
        }
        do {
            try await session.answer(answer)
        } catch {
            Diagnostics.sync.error(
                "push: could not answer: \(String(describing: error), privacy: .public)")
            return
        }
        await PushRegistration.setBadge(session.badgeNumber)

        guard !syncing else {
            syncAgain = true
            return
        }
        syncing = true
        defer { syncing = false }
        do {
            if mailbox is CloudKitMailbox { try await cloud.prepare() }
            _ = try await session.sync(through: mailbox, media: media)
            lastSync = Date()
        } catch {
            Diagnostics.sync.error(
                "push: the answer is written down and will go with the next round: \(String(describing: error), privacy: .public)")
        }
    }
}

extension AppRootView {
    func answering(_ answer: NotificationAnswer) async {
        do {
            try await session.answer(answer)
        } catch {
            Diagnostics.sync.error(
                "push: could not answer: \(String(describing: error), privacy: .public)")
        }
    }
}
