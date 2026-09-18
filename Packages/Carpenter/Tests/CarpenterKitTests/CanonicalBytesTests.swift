import Foundation
import Testing

@testable import CarpenterKit

@Suite("Canonical signing bytes")
struct CanonicalBytesTests {
    @Test("The same fields in the same domain always produce the same bytes")
    func deterministic() {
        let a = CanonicalBytes.payload(domain: "carpenter.test.v1", fields: [Data([1, 2]), Data([3])])
        let b = CanonicalBytes.payload(domain: "carpenter.test.v1", fields: [Data([1, 2]), Data([3])])

        #expect(a == b)
    }

    @Test("A different domain produces different bytes, so a signature cannot be replayed as another kind")
    func domainSeparation() {
        let fields = [Data([1, 2, 3])]

        #expect(
            CanonicalBytes.payload(domain: "carpenter.device-certificate.v1", fields: fields)
                != CanonicalBytes.payload(domain: "carpenter.device-revocation.v1", fields: fields))
    }

    @Test("Field boundaries cannot be shifted — length framing makes concatenation unambiguous")
    func framingIsUnambiguous() {
        let split = CanonicalBytes.payload(
            domain: "carpenter.test.v1", fields: [Data([0x61, 0x62]), Data([0x63])])
        let shifted = CanonicalBytes.payload(
            domain: "carpenter.test.v1", fields: [Data([0x61]), Data([0x62, 0x63])])

        #expect(split != shifted)
    }

    @Test("An added empty field still changes the payload")
    func emptyFieldsCount() {
        #expect(
            CanonicalBytes.payload(domain: "carpenter.test.v1", fields: [Data([1])])
                != CanonicalBytes.payload(domain: "carpenter.test.v1", fields: [Data([1]), Data()]))
    }

    @Test("A domain cannot be made to look like the start of a field")
    func domainCannotBleedIntoFields() {
        #expect(
            CanonicalBytes.payload(domain: "carpenter.a", fields: [Data("b".utf8)])
                != CanonicalBytes.payload(domain: "carpenter.ab", fields: [Data()]))
    }

    @Test("Timestamps encode as fixed-width milliseconds, not as a formatted double")
    func timestampEncoding() {
        let epoch = CanonicalBytes.timestamp(Date(timeIntervalSince1970: 0))
        let oneSecond = CanonicalBytes.timestamp(Date(timeIntervalSince1970: 1))

        #expect(epoch.count == 8)
        #expect(epoch == Data([0, 0, 0, 0, 0, 0, 0, 0]))
        #expect(oneSecond == Data([0, 0, 0, 0, 0, 0, 0x03, 0xE8]))
    }

    @Test("Timestamps before the epoch round-trip rather than wrapping")
    func negativeTimestamps() {
        let before = CanonicalBytes.timestamp(Date(timeIntervalSince1970: -1))
        #expect(before.count == 8)
        #expect(before != CanonicalBytes.timestamp(Date(timeIntervalSince1970: 1)))
    }
}
