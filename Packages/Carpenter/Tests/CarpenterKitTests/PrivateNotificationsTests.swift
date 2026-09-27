@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Making notifications private, and checking a recovery key, for the app lock")
struct PrivateNotificationsTests {
    private func member() async throws -> (AppSession, RoomID) {
        let session = TestSession.make()
        await session.load()
        try await session.createIdentity(displayName: "Alice")
        let room = try await session.createRoom(named: "Lanterns")
        return (session, room)
    }

    @Test("Out of the box notifications show more than that something arrived, and made private they show nothing")
    func privateMeansNothing() async throws {
        let (session, room) = try await member()
        #expect(session.notificationsRevealMore)
        await session.makeNotificationsPrivate()
        #expect(!session.notificationsRevealMore)
        #expect(session.notificationLevel == .nothing)
        #expect(session.notificationLevel(for: room) == .nothing)
        #expect(session.messagingNotifications.roomUpdateLevel == .nothing)
    }

    @Test("A room set to show everything is made private too, and a muted one never counted")
    func perRoomLevelsAreCovered() async throws {
        let (session, room) = try await member()
        await session.makeNotificationsPrivate()
        await session.setNotificationLevel(.everything, for: room)
        #expect(session.notificationsRevealMore, "a room showing everything went unnoticed")
        await session.makeNotificationsPrivate()
        #expect(!session.notificationsRevealMore)
        #expect(session.notificationLevel(for: room) == .nothing)
    }

    @Test("The recovery key this member was given opens their identity, and nobody else's does")
    func onlyTheirKeyOpens() async throws {
        let (alice, _) = try await member()
        let key = try #require(alice.recoveryKeyText(), "precondition: a new member holds their unsaved key")
        #expect(alice.recoveryKeyOpens(key))
        let (bob, _) = try await member()
        let bobs = try #require(bob.recoveryKeyText())
        #expect(!alice.recoveryKeyOpens(bobs), "somebody else's recovery key opened this identity")
        #expect(!alice.recoveryKeyOpens("KEY: AAAA-BBBB"))
        #expect(!alice.recoveryKeyOpens(""))
    }
}
