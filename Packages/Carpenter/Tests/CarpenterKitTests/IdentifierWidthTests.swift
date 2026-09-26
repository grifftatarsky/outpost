import CryptoKit
import Foundation
import Testing

@testable import CarpenterKit

@Suite("Identifiers are a fixed width")
struct IdentifierWidthTests {

    private func encoded(_ raw: Data) -> Data {
        Data("{\"rawValue\":\"\(raw.base64EncodedString())\"}".utf8)
    }

    private func decodeParticipant(_ raw: Data) throws -> ParticipantID {
        try JSONDecoder().decode(ParticipantID.self, from: encoded(raw))
    }

    private func decodeDevice(_ raw: Data) throws -> DeviceID {
        try JSONDecoder().decode(DeviceID.self, from: encoded(raw))
    }

    @Test("The encoder still writes the shape this test decodes")
    func wireShapeUnchanged() throws {
        let id = Identity.generate().id
        let written = try JSONEncoder().encode(id)
        #expect(try JSONDecoder().decode(ParticipantID.self, from: written) == id)
        #expect(try JSONDecoder().decode(ParticipantID.self, from: encoded(id.rawValue)) == id)
    }

    @Test("Both are a SHA256 digest wide")
    func width() {
        #expect(ParticipantID.width == 32)
        #expect(DeviceID.width == 32)
    }

    @Test("Every identifier the app derives is that width")
    func derivedAreAlwaysRight() {
        for _ in 0..<50 {
            let identity = Identity.generate()
            #expect(identity.id.rawValue.count == ParticipantID.width)

            let device = DeviceKeys.generate()
            #expect(device.id.rawValue.count == DeviceID.width)
        }
    }

    @Test("A round trip of a real identifier still works")
    func roundTrip() throws {
        let identity = Identity.generate()
        #expect(try decodeParticipant(identity.id.rawValue) == identity.id)

        let device = DeviceKeys.generate()
        #expect(try decodeDevice(device.id.rawValue) == device.id)
    }

    @Test("A participant of the wrong width is refused rather than decoded")
    func shortParticipantRefused() {
        for count in [0, 1, 16, 31, 33, 64] {
            #expect(throws: DecodingError.self) {
                try decodeParticipant(Data(repeating: 0xAB, count: count))
            }
        }
    }

    @Test("A device of the wrong width is refused rather than decoded")
    func shortDeviceRefused() {
        for count in [0, 1, 16, 31, 33, 64] {
            #expect(throws: DecodingError.self) {
                try decodeDevice(Data(repeating: 0xCD, count: count))
            }
        }
    }

    @Test("With the width held, two different feeds cannot share canonical bytes")
    func concatenationIsUnambiguous() {
        var seen: Set<Data> = []
        var keys: [FeedKey] = []

        for _ in 0..<40 {
            let key = FeedKey(author: Identity.generate().id, device: DeviceKeys.generate().id)
            keys.append(key)
            #expect(key.canonicalBytes.count == ParticipantID.width + DeviceID.width)
            seen.insert(key.canonicalBytes)
        }

        #expect(seen.count == keys.count, "two distinct feeds produced the same canonical bytes")

        for key in keys {
            #expect(key.canonicalBytes.prefix(ParticipantID.width) == key.author.rawValue)
            #expect(key.canonicalBytes.suffix(DeviceID.width) == key.device.rawValue)
        }
    }
}
