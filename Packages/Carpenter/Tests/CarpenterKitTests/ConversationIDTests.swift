import Foundation
import Testing

@testable import CarpenterKit

@Suite("What names a conversation")
struct ConversationIDTests {
    private let uuid = UUID(uuidString: "8B0B4B36-51F1-4C4F-9C0E-4A2E9C7D1A55")!
    private let owner = ParticipantID(rawValue: Data((0..<32).map { UInt8($0) }))

    @Test("The bytes signed and sealed over are pinned, written out by hand")
    func canonicalBytesArePinned() {
        let uuidBytes: [UInt8] = [
            0x8B, 0x0B, 0x4B, 0x36, 0x51, 0xF1, 0x4C, 0x4F,
            0x9C, 0x0E, 0x4A, 0x2E, 0x9C, 0x7D, 0x1A, 0x55,
        ]
        #expect(ConversationID.room(uuid).canonicalBytes == Data([1] + uuidBytes))
        #expect(ConversationID.solo(uuid).canonicalBytes == Data([2] + uuidBytes))
        #expect(
            ConversationID.outpost(owner).canonicalBytes == Data([3] + (0..<32).map { UInt8($0) }))
    }

    @Test("A room and a solo with the same number are different conversations")
    func kindIsPartOfTheName() {
        #expect(ConversationID.room(uuid) != ConversationID.solo(uuid))
        #expect(ConversationID.room(uuid).canonicalBytes != ConversationID.solo(uuid).canonicalBytes)
        #expect(ConversationID.room(uuid).stableName != ConversationID.solo(uuid).stableName)
    }

    @Test("Every kind survives its stable name, and its JSON")
    func everyKindRoundTrips() throws {
        let all: [ConversationID] = [.room(uuid), .solo(uuid), .outpost(owner)]
        #expect(Set(all.map(\.kind)) == Set(ConversationID.Kind.allCases))
        for id in all {
            #expect(ConversationID(stableName: id.stableName) == id)
            let encoded = try JSONEncoder().encode(id)
            #expect(try JSONDecoder().decode(ConversationID.self, from: encoded) == id)
        }
    }

    @Test("The JSON form is the stable name and nothing else")
    func jsonIsTheStableName() throws {
        let encoded = try JSONEncoder().encode(ConversationID.room(uuid))
        #expect(String(decoding: encoded, as: UTF8.self) == "\"room.\(uuid.uuidString)\"")
    }

    @Test("An Outpost names its owner, and nothing else does")
    func onlyAnOutpostHasAnOwner() {
        #expect(ConversationID.outpost(owner).owner == owner)
        #expect(ConversationID.outpost(of: owner) == .outpost(owner))
        #expect(ConversationID.room(uuid).owner == nil)
        #expect(ConversationID.solo(uuid).owner == nil)
    }

    @Test("A name that is not a conversation is refused, not guessed at")
    func garbageIsRefused() {
        for name in [
            "", "room", "room.", "room.not-a-uuid", "wall.\(uuid.uuidString)", "outpost.",
            "outpost.!!!", "outpost.AAAA", uuid.uuidString, ".\(uuid.uuidString)",
        ] {
            #expect(ConversationID(stableName: name) == nil, "\(name) was accepted")
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ConversationID.self, from: Data("\"room.nope\"".utf8))
        }
    }
}
