import Foundation
import Testing

@testable import CarpenterKit

@Suite("A name written in hex is spelled one way, and read back only that way")
struct ANameIsSpelledOneWayTests {
    private func random(_ count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: .min ... .max) })
    }

    @Test("Every name the app already wrote keeps its spelling")
    func theSpellingIsUnchanged() {
        for count in [1, 16, 32, 33] {
            let bytes = random(count)
            #expect(
                bytes.lowercaseHex == bytes.map { String(format: "%02x", $0) }.joined(),
                """
                The shared spelling differs from the one it replaced. Avatar files on disk, sibling \
                records and check-offs in iCloud are all named with it, and a different spelling \
                is a different name: every one of them would be lost.
                """)
        }
    }

    @Test("What is written reads back as the same bytes")
    func roundTrip() {
        for count in 1...64 {
            let bytes = random(count)
            #expect(Data(lowercaseHex: bytes.lowercaseHex) == bytes)
        }
    }

    @Test("Capitals, odd lengths, nothing at all and other characters are not a name")
    func onlyOneSpellingIsRead() {
        #expect(Data(lowercaseHex: "0a") == Data([0x0a]))
        #expect(Data(lowercaseHex: "0A") == nil, "a second spelling of the same bytes was read")
        #expect(Data(lowercaseHex: "abc") == nil)
        #expect(Data(lowercaseHex: "") == nil)
        #expect(Data(lowercaseHex: "zz") == nil)
        #expect(Data(lowercaseHex: " 0a") == nil)
    }

    @Test("A sibling record under a capitalized name is not the record it spells")
    func aCapitalizedRecordNameIsRefused() {
        let name = SiblingRecord.Name(writer: DeviceID(rawValue: Data(repeating: 0xab, count: 32)), kind: .state)
        #expect(SiblingRecord.Name(recordName: name.recordName) == name)
        #expect(SiblingRecord.Name(recordName: "feed-" + name.writer.rawValue.lowercaseHex.uppercased()) == nil)
    }

    @Test("A picture kept for somebody is read back as that person, and a file with no name is nobody")
    func anAvatarFileNamesItsPerson() {
        let person = ParticipantID(rawValue: random(32))
        #expect(PersonAvatarStore.person(named: PersonAvatarStore.name(for: person)) == person)
        #expect(PersonAvatarStore.person(named: "") == nil, "a file named only .jpg was read as a person")
        #expect(PersonAvatarStore.person(named: PersonAvatarStore.name(for: person).uppercased()) == nil)
    }

    @Test("A UUID's canonical bytes are its sixteen bytes in order, written out by hand")
    func aUUIDIsItsBytes() throws {
        let id = try #require(UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF"))
        #expect(
            CanonicalBytes.uuid(id)
                == Data([
                    0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff,
                ]))
    }
}
