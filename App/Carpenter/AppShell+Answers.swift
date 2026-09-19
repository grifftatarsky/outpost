import CarpenterApp
import CarpenterCloudKit
import CarpenterKit
import Foundation
import OSLog
import UserNotifications

extension AppShell {
    func answerWithoutAWindow(_ answer: NotificationAnswer) async {
        Diagnostics.sync.notice("push: no window is listening; answering from the background")
        await cloud.restoreDirectory()
        if session.state == .loading { await session.load() }
        guard session.enrolment != nil else {
            Diagnostics.sync.error("push: nobody is signed in here to answer as")
            await tellNotSent(answer)
            return
        }
        do {
            try await session.answer(answer)
        } catch {
            Diagnostics.sync.error(
                "push: could not answer without a window: \(String(describing: error), privacy: .public)")
            await tellNotSent(answer)
            return
        }
        await PushRegistration.setBadge(session.badgeNumber)

        await afterTheRoundInFlight()
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

extension AppShell {
    func untilLoaded(atMost limit: Duration = .seconds(20)) async {
        let clock = ContinuousClock()
        let deadline = clock.now + limit
        while session.state == .loading, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func tellNotSent(_ answer: NotificationAnswer) async {
        guard case .reply(let room, let words) = answer else { return }
        let content = NotificationAnswer.notSent(
            words, in: room, named: session.rooms.first { $0.id == room }?.name,
            showingWords: FocusFilterStore.shared.read().showsPreviews)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func afterTheRoundInFlight(atMost limit: Duration = .seconds(20)) async {
        let clock = ContinuousClock()
        let deadline = clock.now + limit
        while syncing, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
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
            await shell.tellNotSent(answer)
        }
    }
}
