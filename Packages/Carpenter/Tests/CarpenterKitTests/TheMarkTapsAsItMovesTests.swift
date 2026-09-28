import Testing

@testable import CarpenterUI

@Suite("The mark on You taps as it moves")
struct TheMarkTapsAsItMovesTests {
    @Test("Opening builds to a thud as the door shuts, then taps for each squint and each opening of the eyes")
    func opening() {
        let taps = (1..<14).map { AnimatedMark.tap(from: $0 - 1, to: $0) }
        #expect(taps == [
            .building(0.35), .building(0.45), .building(0.6), .thud, .squint, nil, nil, .open,
            nil, nil, nil, .squint, .open,
        ])
    }

    @Test("Closing thuds as the lid opens and again as the letters slide back")
    func closing() {
        let taps = (0..<13).reversed().map { AnimatedMark.tap(from: $0 + 1, to: $0) }
        #expect(taps == [
            .squint, .open, nil, nil, nil, .squint, nil, nil, nil, .thud, .building(0.45), .thud, nil,
        ])
    }

    @Test("A jump straight to the end, as with Reduce Motion, taps nothing")
    func aJumpIsSilent() {
        #expect(AnimatedMark.tap(from: 0, to: 13) == nil)
        #expect(AnimatedMark.tap(from: 13, to: 0) == nil)
    }
}
