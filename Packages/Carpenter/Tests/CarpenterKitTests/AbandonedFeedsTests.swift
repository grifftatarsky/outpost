import Foundation
import Testing

@testable import CarpenterKit

@Suite struct AbandonedFeedsTests {
    private func device(_ byte: UInt8) -> DeviceID { DeviceID(rawValue: Data([byte])) }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func longAgo() -> Date { now.addingTimeInterval(-60 * 86_400) }
    private func recently() -> Date { now.addingTimeInterval(-3_600) }

    @Test("An old feed from a device that was never enrolled here is reapable")
    func reapsTheAbandoned() {
        let reaped = AbandonedFeeds.reapable(
            among: [.init(device: device(9), writtenAt: longAgo())],
            knownDevices: [device(1)], thisDevice: device(1), now: now)
        #expect(reaped == [device(9)])
    }

    @Test("A feed too new to judge is left alone, certificate or not")
    func gracePeriodProtectsTheJoiner() {
        let reaped = AbandonedFeeds.reapable(
            among: [.init(device: device(9), writtenAt: recently())],
            knownDevices: [device(1)], thisDevice: device(1), now: now)
        #expect(reaped.isEmpty)
    }

    @Test("A device that holds a certificate is never reaped, however old its feed")
    func enrolledDevicesSurvive() {
        let reaped = AbandonedFeeds.reapable(
            among: [.init(device: device(2), writtenAt: longAgo())],
            knownDevices: [device(1), device(2)], thisDevice: device(1), now: now)
        #expect(reaped.isEmpty)
    }

    @Test("A device never reaps its own feed")
    func neverItself() {
        let reaped = AbandonedFeeds.reapable(
            among: [.init(device: device(1), writtenAt: longAgo())],
            knownDevices: [], thisDevice: device(1), now: now)
        #expect(reaped.isEmpty, "reaping your own feed deletes the history you are using")
    }

    @Test("A feed with no timestamp cannot be aged, so it is never reaped")
    func undatedFeedsSurvive() {
        let reaped = AbandonedFeeds.reapable(
            among: [.init(device: device(9), writtenAt: nil)],
            knownDevices: [], thisDevice: device(1), now: now)
        #expect(reaped.isEmpty)
    }

    @Test("A mixed account reaps only what satisfies every condition")
    func mixedAccount() {
        let reaped = AbandonedFeeds.reapable(
            among: [
                .init(device: device(1), writtenAt: longAgo()),   // this device
                .init(device: device(2), writtenAt: longAgo()),   // enrolled
                .init(device: device(3), writtenAt: recently()),  // too new
                .init(device: device(4), writtenAt: nil),         // undateable
                .init(device: device(5), writtenAt: longAgo()),   // abandoned
            ],
            knownDevices: [device(1), device(2)], thisDevice: device(1), now: now)
        #expect(reaped == [device(5)])
    }
}
