import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@Suite("Settings converge between your devices")
struct SettingsConvergeTests {
    private let person = ParticipantID(rawValue: WideID.of([9]))
    private let room = RoomID()

    private func stamp(_ seconds: Double, _ device: UInt8) -> OrganisationStamp {
        OrganisationStamp(at: Date(timeIntervalSince1970: seconds), device: DeviceID(rawValue: WideID.of([device])))
    }

    @Test("Two answers written at the same instant by the same device settle the same way on both sides")
    func aTieSettlesTheSameEverywhere() {
        let tie = stamp(1_000, 1)
        let yes = Stamped(true, stamp: tie)
        let no = Stamped(false, stamp: tie)

        #expect(
            yes.merged(with: no) == no.merged(with: yes),
            "each side kept its own answer, so two devices merging each other disagree for good")
    }

    @Test("Merging settings is commutative, associative and idempotent")
    func mergingObeysTheLaws() {
        var random = Seeded(state: 26)
        func side(_ device: UInt8) -> MemberPreferences {
            var prefs = MemberPreferences()
            let when = { Double(Int.random(in: 0...3, using: &random)) }
            prefs.setBlocked(Bool.random(using: &random), person, stamp: stamp(when(), device))
            prefs.setMuted(Bool.random(using: &random), for: room, stamp: stamp(when(), device))
            prefs.setDisplayName(Bool.random(using: &random) ? "Cassilda" : "Camilla", stamp: stamp(when(), device))
            prefs.setNotificationLevel(
                NotificationLevel.allCases.randomElement(using: &random) ?? .everything, stamp: stamp(when(), device))
            return prefs
        }

        for _ in 0..<300 {
            let (a, b, c) = (side(1), side(Bool.random(using: &random) ? 1 : 2), side(2))
            #expect(a.merged(with: b) == b.merged(with: a))
            #expect(a.merged(with: b).merged(with: c) == a.merged(with: b.merged(with: c)))
            #expect(a.merged(with: a) == a)
        }
    }
}
