import Foundation
import Testing

@testable import CarpenterKit

@Suite("A date nobody could have meant")
struct DatesPastTheEndOfTimeTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func redated<Value: Codable>(_ value: Value, key: String, to seconds: Double) throws -> Value {
        var fields = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        fields[key] = seconds
        return try JSONDecoder().decode(Value.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    @Test("An entry dated past the end of time is refused, not a crash")
    func aFarEntryIsRefused() throws {
        var replica = Replica()
        var alice = Author()
        try replica.meet(alice)
        let genuine = try alice.post("hello", at: start)

        let forged = try redated(genuine, key: "wallTime", to: 1e300)

        #expect(throws: LogError.self) { try replica.integrate(forged) }
    }

    @Test("A certificate issued past the end of time is refused, not a crash")
    func aFarCertificateIsRefused() throws {
        var replica = Replica()
        let alice = Author()
        replica.introduce(alice.identity.publicKeys)

        let forged = try redated(alice.certificate, key: "issuedAt", to: -1e300)

        #expect(throws: (any Error).self) { try replica.admit(forged) }
    }

    @Test("An ordinary date is written the way it always was")
    func ordinaryDatesAreUnchanged() {
        let date = Date(timeIntervalSince1970: 1_786_635_000.1234)
        let milliseconds = Int64(1_786_635_000_123)
        #expect(CanonicalBytes.timestamp(date) == withUnsafeBytes(of: UInt64(bitPattern: milliseconds).bigEndian) { Data($0) })
        let before = Date(timeIntervalSince1970: -12_345.6)
        #expect(CanonicalBytes.timestamp(before) == withUnsafeBytes(of: UInt64(bitPattern: -12_345_600).bigEndian) { Data($0) })
    }

    @Test("A timestamp is drawn for a post dated at either end of time", arguments: [-1e300, 1e300, -1e18, 1e18])
    func farDatesStillDraw(seconds: Double) {
        let formatter = RelativeTimestampFormatter(calendar: Calendar(identifier: .gregorian), locale: Locale(identifier: "en_US"))
        let far = Date(timeIntervalSince1970: seconds)

        #expect(!formatter.compact(for: far, now: start).isEmpty)
        #expect(!formatter.roomsList(for: far, now: start).isEmpty)
        #expect(!formatter.readReceipt(far, now: start).isEmpty)
    }
}

