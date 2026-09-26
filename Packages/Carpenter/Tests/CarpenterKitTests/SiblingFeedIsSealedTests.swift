import CryptoKit
import Foundation
import Testing

@testable import CarpenterKit

@Suite("A sibling feed is sealed before it leaves the device")
struct SiblingFeedIsSealedTests {
    private static let identity = Identity.generate()
    private static let device = DeviceID(rawValue: Data(repeating: 0xA1, count: 32))
    private static let other = DeviceID(rawValue: Data(repeating: 0xB2, count: 32))

    private static let epochMaterial = Data(repeating: 0x5E, count: 32)
    private static let nickname = "Cassilda"
    private static let displayName = "Camilla"
    private static let blocked = ParticipantID(rawValue: Data(repeating: 0x77, count: 32))
    private static let room = RoomID()
    private static let keys = DeviceKeys.generate()

    private static func populated() -> SiblingFeed {
        let stamp = OrganisationStamp(at: Date(timeIntervalSince1970: 1_000), device: device)
        var prefs = MemberPreferences()
        prefs.setDisplayName(displayName, stamp: stamp)
        prefs.setNickname(nickname, for: blocked, stamp: stamp)
        prefs.setBlocked(true, blocked, stamp: stamp)
        prefs.setFocusMessage("Heads down till six", stamp: stamp)

        let entry = Entry(
            author: identity.id, device: device, seq: 1, previous: nil, clock: VectorClock(),
            wallTime: Date(timeIntervalSince1970: 2_000), room: room,
            payload: SealedPayload(epoch: .initial, ciphertext: Data(repeating: 0x0C, count: 16)),
            signature: Data(repeating: 0x0D, count: 64))

        return SiblingFeed(
            entries: [entry],
            certificates: [
                DeviceCertificate(
                    participant: identity.id, device: keys.id, devicePublicKey: keys.publicKey,
                    issuedAt: Date(timeIntervalSince1970: 3_000),
                    signature: Data(repeating: 0x0E, count: 64))
            ],
            epochs: [HeldEpoch(room: room, epoch: .initial, material: epochMaterial)],
            member: identity.id,
            writtenAt: Date(timeIntervalSince1970: 4_000),
            preferences: prefs)
    }

    private static func sealed() throws -> SealedSiblingFeed {
        try SealedSiblingFeed.seal(populated(), for: identity, on: device)
    }

    // MARK: What the transport can carry

    @Test("The wire form is ciphertext and nothing else")
    func theWireFormIsCiphertextAndNothingElse() throws {
        let children = Mirror(reflecting: try Self.sealed()).children.compactMap(\.label)
        #expect(
            children == ["ciphertext"],
            """
            `SealedSiblingFeed` now carries \(children). Every property of it is written to a \
            CloudKit record in the clear, so anything but `ciphertext` is a field an operator can \
            read. Put it inside the seal, or explain here why it is safe outside one.
            """)
    }

    @Test("Every field of a feed is inside the seal")
    func everyFieldOfAFeedIsInsideTheSeal() throws {
        let bytes = try Self.sealed().ciphertext
        let feed = Self.populated()

        for child in Mirror(reflecting: feed).children {
            guard let label = child.label else { continue }
            #expect(
                !bytes.contains(Data(String(describing: child.value).utf8)),
                """
                `SiblingFeed.\(label)` is readable in the sealed bytes. It is not being sealed.
                """)
        }

        for (name, marker) in [
            ("an epoch secret", Self.epochMaterial),
            ("a nickname", Data(Self.nickname.utf8)),
            ("the display name", Data(Self.displayName.utf8)),
            ("a blocked person", Self.blocked.rawValue),
            ("the member's own id", Self.identity.id.rawValue),
        ] {
            #expect(
                !bytes.contains(marker),
                """
                \(name) appears verbatim in what goes to CloudKit. This is the defect of \
                2026-08-16: the record is readable by anybody who can read the container.
                """)
        }
    }

    @Test("The fixture actually fills every field")
    func theFixtureActuallyFillsEveryField() {
        let full = Mirror(reflecting: Self.populated()).children
        let empty = Mirror(reflecting: SiblingFeed(entries: [], certificates: [], epochs: []))
            .children.reduce(into: [String: String]()) { found, child in
                if let label = child.label { found[label] = String(describing: child.value) }
            }

        for child in full {
            guard let label = child.label, let bare = empty[label] else { continue }
            #expect(
                String(describing: child.value) != bare,
                """
                `SiblingFeed.\(label)` is still at its default in `populated()`. Fill it there, \
                or the leak check above passes vacuously for it.
                """)
        }
    }

    // MARK: Who can open it

    @Test("Its own identity opens it, whole")
    func itsOwnIdentityOpensItWhole() throws {
        let opened = try Self.sealed().open(with: Self.identity, from: Self.device)
        #expect(opened == Self.populated())
    }

    @Test("Another identity cannot open it")
    func anotherIdentityCannotOpenIt() throws {
        #expect(throws: (any Error).self) {
            try Self.sealed().open(with: Identity.generate(), from: Self.device)
        }
    }

    @Test("A record moved into another device's slot will not open")
    func aRecordMovedIntoAnotherDevicesSlotWillNotOpen() throws {
        #expect(throws: (any Error).self) {
            try Self.sealed().open(with: Self.identity, from: Self.other)
        }
    }

    @Test("A changed byte is refused rather than half-read")
    func aChangedByteIsRefusedRatherThanHalfRead() throws {
        var bytes = try Self.sealed().ciphertext
        bytes[bytes.count / 2] ^= 0xFF
        #expect(throws: (any Error).self) {
            try SealedSiblingFeed(ciphertext: bytes).open(with: Self.identity, from: Self.device)
        }
    }

    @Test("Two seals of the same feed differ")
    func twoSealsOfTheSameFeedDiffer() throws {
        #expect(try Self.sealed().ciphertext != Self.sealed().ciphertext)
    }
}

@Suite("Sealing the feed between your devices")
@MainActor
struct SiblingFeedOffTheMainActorTests {
    private final class Ticks {
        var count = 0
    }

    private func longFeed(_ count: Int) throws -> (feed: SiblingFeed, identity: Identity, device: DeviceID) {
        var alice = Author()
        var entries: [Entry] = []
        for step in 0..<count {
            entries.append(try alice.post("\(step)", at: Date(timeIntervalSince1970: Double(step))))
        }
        let feed = SiblingFeed(
            entries: entries, certificates: [alice.certificate], epochs: [], member: alice.identity.id,
            writtenAt: Date(timeIntervalSince1970: 0), preferences: MemberPreferences())
        return (feed, alice.identity, alice.device.id)
    }

    @Test("Sealed and opened in the background, a feed comes back whole, and only for the device it names")
    func theBackgroundRoundTrip() async throws {
        let (feed, identity, device) = try longFeed(20)

        let sealed = try await SealedSiblingFeed.sealInBackground(feed, for: identity, on: device)

        #expect(try await sealed.openInBackground(with: identity, from: device) == feed)
        await #expect(throws: CryptoError.openFailed) {
            try await sealed.openInBackground(with: identity, from: DeviceID(rawValue: Data(repeating: 1, count: 32)))
        }
    }

    @Test("Sealing a long feed leaves the main actor free to draw")
    func sealingLeavesTheMainActorFree() async throws {
        let (feed, identity, device) = try longFeed(300)
        let ticks = Ticks()
        let ticker = Task { @MainActor in
            while !Task.isCancelled {
                ticks.count += 1
                await Task.yield()
            }
        }

        _ = try await SealedSiblingFeed.sealInBackground(feed, for: identity, on: device)
        ticker.cancel()

        #expect(
            ticks.count > 0,
            """
            Nothing else ran on the main actor while the feed was sealed. Every send seals the \
            whole feed, and on the main actor that is a frozen screen.
            """)
    }
}
