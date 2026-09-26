import CarpenterKit
import CarpenterKitTesting
import Foundation
import Observation
import Synchronization
import Testing

@testable import CarpenterApp

@Suite("What a screen is told to redraw for")
@MainActor
struct WhatAScreenIsToldTests {
    private func twoRooms() async throws -> (AppSession, RoomID, RoomID) {
        let alice = TestSession.make()
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        let first = try await alice.createRoom(named: "Kitchen")
        let second = try await alice.createRoom(named: "Hangar")
        try await alice.send("in the kitchen", to: first)
        try await alice.send("in the hangar", to: second)
        return (alice, first, second)
    }

    private func told(_ read: () -> Void, after change: () async throws -> Void) async rethrows -> Bool {
        let fired = Atomic(false)
        withObservationTracking(read) { fired.store(true, ordering: .relaxed) }
        try await change()
        return fired.load(ordering: .relaxed)
    }

    @Test("Reading one room does not tell a screen showing another room to redraw")
    func readingElsewhereIsQuiet() async throws {
        let (alice, kitchen, hangar) = try await twoRooms()
        _ = alice.messages(in: kitchen)

        let redrew = await told({ _ = alice.messages(in: kitchen) }) { _ = alice.messages(in: hangar) }

        #expect(
            !redrew,
            """
            Drawing the hangar told the kitchen to draw again. Filling a cache for one room was \
            observed as a change by every screen that had read that cache for any room.
            """)
    }

    @Test("A message sent into a room tells a screen showing it to redraw")
    func aNewMessageIsSeen() async throws {
        let (alice, kitchen, _) = try await twoRooms()
        _ = alice.messages(in: kitchen)

        let redrew = try await told({ _ = alice.messages(in: kitchen) }) {
            try await alice.send("more", to: kitchen)
        }

        #expect(redrew, "a new message did not reach the screen showing its room")
    }

    @Test("Renaming somebody tells a screen showing their name to redraw")
    func aNicknameIsSeen() async throws {
        let (alice, _, _) = try await twoRooms()
        let someone = ParticipantID(rawValue: Data(repeating: 9, count: 32))
        _ = alice.projection.member(someone)

        let redrew = await told({ _ = alice.projection.member(someone) }) {
            await alice.setNickname("Bobby", for: someone)
        }

        #expect(redrew, "a nickname did not reach the screen showing the name")
        #expect(alice.projection.member(someone).displayName == "Bobby")
    }

    @Test("A round that brings nothing new does not tell a conversation to redraw")
    func anEmptyRoundIsQuiet() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        for member in [alice, bob] { await member.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Kitchen")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        for _ in 0..<8 {
            for member in [alice, bob] { try await member.sync(through: mailbox) }
        }
        _ = alice.messages(in: room)

        let redrew = try await told({ _ = alice.messages(in: room) }) {
            try await alice.sync(through: mailbox)
        }

        #expect(
            !redrew,
            """
            A round that brought nothing new told the open conversation to draw again. On a phone \
            that is every twenty seconds in the foreground, for nothing.
            """)
    }
}
