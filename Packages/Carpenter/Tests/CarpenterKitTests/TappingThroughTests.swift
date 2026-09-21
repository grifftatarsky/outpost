import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@MainActor
@Suite("Tapping a banner", .serialized)
struct TappingThroughTests {
    private func member() async throws -> AppSession {
        let session = TestSession.make()
        await session.load()
        try await session.createIdentity(displayName: "Griff")
        return session
    }

    @Test("A banner for a room this member is in opens that room")
    func aBannerForARoomOpensIt() async throws {
        let session = try await member()
        let room = try await session.createRoom(named: "Kitchen")

        #expect(
            session.tapping(MessageNotification.thread(for: room), whileViewing: nil)
                == .room(room))
    }

    @Test("A banner for a room since left opens the app without navigating")
    func aBannerForARoomSinceLeftDoesNotNavigate() async throws {
        let session = try await member()
        let gone = ConversationID.room(UUID())

        #expect(
            session.tapping(MessageNotification.thread(for: gone), whileViewing: nil)
                == .theAppAsItStands,
            """
            A banner named a room this member no longer has, and the app navigated to it anyway. \
            The honest answer is the one a generic banner already gets: open, and do not guess.
            """)
    }

    @Test("A banner tapped while already in that room does nothing")
    func aBannerTappedWhileAlreadyThereDoesNothing() async throws {
        let session = try await member()
        let room = try await session.createRoom(named: "Kitchen")

        #expect(
            session.tapping(MessageNotification.thread(for: room), whileViewing: room)
                == .theAppAsItStands,
            "tapping a banner for the room already on screen pushed it again")
    }

    @Test("A banner carrying nothing readable opens the app without guessing")
    func aGenericBannerDoesNotGuess() async throws {
        let session = try await member()
        _ = try await session.createRoom(named: "Kitchen")

        for thread in ["", "not-a-uuid", "  ", "00000000"] {
            #expect(
                session.tapping(thread, whileViewing: nil) == .theAppAsItStands,
                "\"\(thread)\" was read as a room")
        }
    }

    @Test("A banner for another room, while in one, still moves")
    func aBannerForAnotherRoomStillMoves() async throws {
        let session = try await member()
        let kitchen = try await session.createRoom(named: "Kitchen")
        let hangar = try await session.createRoom(named: "Hangar")

        #expect(
            session.tapping(MessageNotification.thread(for: hangar), whileViewing: kitchen)
                == .room(hangar),
            "being in one room stopped a banner about another from opening it")
    }
}
