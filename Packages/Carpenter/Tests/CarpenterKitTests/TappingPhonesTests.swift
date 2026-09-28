@testable import CarpenterKit
import CryptoKit
import Foundation
import Testing

@Suite("Tapping two phones swaps codes between those two and nobody else")
struct TappingPhonesTests {
    private final class Room {
        private var phones: [String: TapSwap] = [:]
        private var peerOf: [String: [String: TapPeer]] = [:]
        private var nameOf: [String: [TapPeer: String]] = [:]
        private(set) var arrived: [String: [String]] = [:]
        private(set) var ranging: [String: Set<String>] = [:]
        private(set) var wire: [(from: String, to: String, message: TapMessage)] = []
        var now = Date(timeIntervalSince1970: 1_786_635_000)

        init(_ handing: [String: String]) {
            for (name, code) in handing { phones[name] = TapSwap(handingOver: code) }
        }

        func link(_ one: String, _ other: String) {
            for (a, b) in [(one, other), (other, one)] {
                let peer = TapPeer()
                peerOf[a, default: [:]][b] = peer
                nameOf[a, default: [:]][peer] = b
            }
        }

        func connect(_ one: String, _ other: String) {
            link(one, other)
            for (a, b) in [(one, other), (other, one)] {
                deliver(phones[a]!.connected(peerOf[a]![b]!, token: Data("token \(a) to \(b)".utf8), at: now), from: a)
            }
        }

        func measure(_ one: String, _ other: String, _ distance: Double) {
            for _ in 0..<TapSwap.steadyReadings {
                now += 0.1
                deliver(phones[one]!.measured(peerOf[one]![other]!, distance: distance, at: now), from: one)
                deliver(phones[other]!.measured(peerOf[other]![one]!, distance: distance, at: now), from: other)
            }
        }

        func measure(_ one: String, sees other: String, at distance: Double) {
            for _ in 0..<TapSwap.steadyReadings {
                now += 0.1
                deliver(phones[one]!.measured(peerOf[one]![other]!, distance: distance, at: now), from: one)
            }
        }

        func accept(_ name: String) {
            deliver(phones[name]!.accept(at: now), from: name)
        }

        func handOver(_ text: String, from name: String) {
            deliver(phones[name]!.handOver(text), from: name)
        }

        func phase(_ name: String) -> TapSwap.Phase { phones[name]!.phase(at: now) }

        func number(_ name: String) -> TapSwap.Number? { phones[name]!.number }

        func partner(of name: String) -> String? { phones[name]!.partner.flatMap { nameOf[name]?[$0] } }

        func replay(_ message: TapMessage, from sender: String, to receiver: String) {
            deliver(phones[receiver]!.received(message, from: peerOf[receiver]![sender]!, at: now), from: receiver)
        }

        func hello(to receiver: String, from sender: String, token: Data, commitment: Data) -> TapSwap.Effects {
            phones[receiver]!.received(
                .hello(token: token, commitment: commitment), from: peerOf[receiver]![sender]!, at: now)
        }

        private func deliver(_ effects: TapSwap.Effects, from name: String) {
            arrived[name, default: []] += effects.arrived
            for peer in effects.rangeWith.keys { ranging[name, default: []].insert(nameOf[name]![peer]!) }
            for send in effects.sends {
                let receiver = nameOf[name]![send.to]!
                wire.append((from: name, to: receiver, message: send.message))
                let back = peerOf[receiver]![name]!
                deliver(phones[receiver]!.received(send.message, from: back, at: now), from: receiver)
            }
        }
    }

    private func aliceAndBob() -> Room {
        let room = Room(["alice": "alice's code", "bob": "bob's code"])
        room.connect("alice", "bob")
        return room
    }

    private static func isHello(_ message: TapMessage) -> Bool {
        if case .hello = message { true } else { false }
    }

    private static func isReveal(_ message: TapMessage) -> Bool {
        if case .reveal = message { true } else { false }
    }

    // MARK: The two phones touching

    @Test("Two phones held together swap codes once both people accept")
    func twoPhonesSwap() {
        let room = aliceAndBob()
        room.measure("alice", "bob", 0.04)
        #expect(room.phase("alice") == .touching)
        #expect(room.phase("bob") == .touching)
        #expect(room.number("alice") != nil)

        room.accept("alice")
        #expect(room.phase("alice") == .waitingForThem)
        #expect(room.arrived["bob", default: []].isEmpty, "a code went over before its owner's person accepted")

        room.accept("bob")
        #expect(room.arrived["alice"] == ["bob's code"])
        #expect(room.arrived["bob"] == ["alice's code"])
        #expect(room.phase("alice") == .swapped)
        #expect(room.phase("bob") == .swapped)
        #expect(room.partner(of: "alice") == "bob")
        #expect(room.partner(of: "bob") == "alice")
    }

    @Test("No number shows, and no yes counts, until both phones have found each other")
    func nothingBeforeBothHaveTouched() {
        let room = aliceAndBob()
        room.measure("alice", sees: "bob", at: 0.04)
        #expect(room.phase("alice") == .touching)
        #expect(room.number("alice") == nil, "a number showed before the other phone had shown its key")
        room.accept("alice")
        #expect(room.phase("alice") == .touching, "a yes counted before there was a number to check")

        room.measure("bob", sees: "alice", at: 0.04)
        #expect(room.number("alice") != nil)
        room.accept("alice")
        room.accept("bob")
        #expect(room.arrived["alice"] == ["bob's code"])
        #expect(room.arrived["bob"] == ["alice's code"])
    }

    @Test("Both phones show the same six digits, and each is told which half to say")
    func bothShowTheSameNumber() throws {
        let room = aliceAndBob()
        room.measure("alice", "bob", 0.04)
        let hers = try #require(room.number("alice"))
        let his = try #require(room.number("bob"))
        #expect(hers.first == his.first && hers.second == his.second)
        #expect(hers.youSayFirst != his.youSayFirst, "both phones told their person to speak first")
        #expect((hers.first + hers.second).count == TapSwap.numberLength)
        #expect((hers.first + hers.second).allSatisfy(\.isNumber))
    }

    @Test(
        "A code that lands after the other phone's ask has lapsed is sent again when that person says yes again",
        arguments: [1, TapSwap.askLasts + 1])
    func aLateCodeIsSentAgain(pause: TimeInterval) {
        let room = aliceAndBob()
        room.measure("alice", sees: "bob", at: 0.04)
        room.now += 20
        room.measure("bob", sees: "alice", at: 0.04)
        room.accept("alice")
        room.now += 11
        room.accept("bob")
        #expect(room.arrived["alice", default: []].isEmpty, "precondition: bob's code landed after alice's ask lapsed")
        #expect(room.phase("bob") == .waitingForThem)

        room.now += pause
        room.measure("alice", sees: "bob", at: 0.04)
        room.accept("alice")
        #expect(room.arrived["alice"] == ["bob's code"], "the phone that had already sent its code never sent it again")
        #expect(room.arrived["bob"] == ["alice's code"])
        #expect(room.phase("alice") == .swapped)
        #expect(room.phase("bob") == .swapped)
    }

    @Test("A code that arrives before this phone's person says yes brings nothing back until they do")
    func aCodeSentFirstBringsNothingBack() {
        let room = aliceAndBob()
        room.measure("alice", sees: "bob", at: 0.04)
        room.now += 20
        room.measure("bob", sees: "alice", at: 0.04)
        room.accept("alice")
        room.now += 11
        room.measure("alice", sees: "bob", at: 1)
        room.measure("alice", sees: "bob", at: 0.04)
        #expect(room.phase("alice") == .touching, "precondition: alice's first yes lapsed and she is being asked again")

        let sentBefore = room.wire.filter { $0.from == "alice" }.count
        room.accept("bob")
        #expect(room.wire.filter { $0.from == "alice" }.count == sentBefore, "a phone answered a code its person had not said yes to")
        #expect(room.arrived["alice", default: []].isEmpty)

        room.accept("alice")
        #expect(room.arrived["alice"] == ["bob's code"])
        #expect(room.arrived["bob"] == ["alice's code"])
    }

    @Test("Nothing is shared until each person accepts, and an ask left too long lapses")
    func nothingWithoutBothYeses() {
        let room = aliceAndBob()
        room.measure("alice", "bob", 0.04)
        room.accept("alice")
        room.now += TapSwap.askLasts + 1
        #expect(room.phase("bob") != .touching, "an ask outlived its half-minute")

        room.accept("bob")
        #expect(room.arrived["alice", default: []].isEmpty, "a code went over after the ask had lapsed")
        #expect(room.arrived["bob", default: []].isEmpty)
    }

    @Test("After the swap, what either hands over next goes to that phone, and nothing goes before it")
    func anInviteFollows() {
        let room = aliceAndBob()
        room.handOver("an invite, too early", from: "alice")
        #expect(room.arrived["bob", default: []].isEmpty, "something was handed over before the swap")

        room.measure("alice", "bob", 0.04)
        room.accept("alice")
        room.accept("bob")
        room.handOver("alice's invite", from: "alice")
        #expect(room.arrived["bob"] == ["alice's code", "alice's invite"])
    }

    // MARK: A phone across the room

    @Test("A phone across the room gets no code and slips in none of its own")
    func farPhoneGetsNothing() {
        let room = Room(["alice": "alice's code", "bob": "bob's code", "mallory": "mallory's code"])
        room.connect("alice", "bob")
        room.connect("alice", "mallory")
        room.connect("bob", "mallory")
        room.measure("alice", "mallory", 3)
        room.measure("bob", "mallory", 3)
        room.measure("alice", "bob", 0.04)
        #expect(room.phase("alice") == .touching)

        room.accept("mallory")
        room.accept("alice")
        room.accept("bob")
        #expect(room.arrived["alice"] == ["bob's code"])
        #expect(room.arrived["bob"] == ["alice's code"])
        #expect(room.arrived["mallory", default: []].isEmpty, "a phone across the room got a code")
    }

    @Test("A phone that claims to be touching, while the other measures it across the room, gets nothing and gives nothing")
    func lyingPhoneGetsNothing() {
        let room = Room(["alice": "alice's code", "mallory": "mallory's code"])
        room.connect("alice", "mallory")
        room.measure("alice", sees: "mallory", at: 4)
        room.measure("mallory", sees: "alice", at: 0.04)
        room.accept("mallory")
        room.accept("alice")
        #expect(room.arrived["alice", default: []].isEmpty, "a far phone slipped in its code")
        #expect(room.arrived["mallory", default: []].isEmpty, "a far phone got a code")
        #expect(
            !room.wire.contains { $0.from == "alice" && Self.isReveal($0.message) },
            "alice showed her key to a phone she measured across the room")
    }

    @Test("A phone shows its key only to the phone it is touching, after that phone has committed to its own")
    func aKeyIsShownOnlyToTheTouchingPhone() throws {
        let room = Room(["alice": "alice's code", "bob": "bob's code", "mallory": "mallory's code"])
        room.connect("alice", "bob")
        room.connect("alice", "mallory")
        room.measure("alice", "mallory", 3)
        room.measure("alice", "bob", 0.04)

        let reveals = room.wire.filter { $0.from == "alice" && Self.isReveal($0.message) }
        #expect(reveals.map(\.to) == ["bob"], "alice showed her key to a phone she was not touching")
        let committed = try #require(room.wire.firstIndex { $0.from == "bob" && $0.to == "alice" && Self.isHello($0.message) })
        let revealed = try #require(room.wire.firstIndex { $0.from == "alice" && Self.isReveal($0.message) })
        #expect(committed < revealed, "alice showed her key before bob had committed to his")
    }

    @Test("A key that does not match what its phone committed to is refused")
    func aKeyMustMatchItsCommitment() {
        let room = aliceAndBob()
        room.measure("alice", sees: "bob", at: 0.04)
        let other = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        room.replay(.reveal(key: other), from: "bob", to: "alice")
        #expect(room.number("alice") == nil, "a key its phone never committed to was taken")

        room.measure("bob", sees: "alice", at: 0.04)
        #expect(room.number("alice") != nil, "precondition: the key bob committed to is taken")
    }

    @Test("A phone in the middle shows each side a different number")
    func aRelayShowsTwoNumbers() throws {
        let room = Room(["alice": "alice's code", "bob": "bob's code", "near alice": "relay", "near bob": "relay"])
        room.connect("alice", "near alice")
        room.connect("bob", "near bob")
        room.measure("alice", "near alice", 0.04)
        room.measure("bob", "near bob", 0.04)

        let hers = try #require(room.number("alice"))
        let his = try #require(room.number("bob"))
        #expect(hers.first + hers.second != his.first + his.second, "a relay made both phones show one number")
    }

    @Test("Once a phone has shown its key, it shows it to no other phone in the same tap")
    func oneKeyPerTap() {
        let room = Room(["alice": "alice's code", "bob": "bob's code", "carol": "carol's code"])
        room.connect("alice", "bob")
        room.connect("alice", "carol")
        room.measure("alice", "carol", 3)
        room.measure("alice", "bob", 0.04)
        room.measure("alice", "bob", 3)
        room.measure("alice", "carol", 0.04)

        #expect(
            room.wire.filter { $0.from == "alice" && Self.isReveal($0.message) }.map(\.to) == ["bob"],
            "a phone showed its key to a second phone in the same tap")
        #expect(room.phase("alice") != .touching)
    }

    @Test("Two phones within reach at once is nobody's turn")
    func twoAtOnceIsCrowded() {
        let room = Room(["alice": "alice's code", "bob": "bob's code", "carol": "carol's code"])
        room.connect("alice", "bob")
        room.connect("alice", "carol")
        room.measure("alice", "bob", 0.04)
        room.measure("alice", "carol", 0.05)
        #expect(room.phase("alice") == .crowded)

        room.accept("alice")
        room.accept("bob")
        room.accept("carol")
        #expect(room.arrived["alice", default: []].isEmpty)
    }

    @Test("A phone that has just arrived holds the choice until it has been measured, or has had time to be")
    func aNewcomerHoldsTheChoice() {
        let room = Room(["alice": "alice's code", "bob": "bob's code", "carol": "carol's code"])
        room.connect("alice", "bob")
        room.connect("alice", "carol")
        room.measure("alice", "bob", 0.04)
        #expect(room.phase("alice") != .touching, "a phone nobody had measured yet could have been the close one")

        room.now += TapSwap.settle
        room.measure("alice", "bob", 0.04)
        #expect(room.phase("alice") == .touching)
    }

    // MARK: What goes over the air

    @Test("Nothing on the air carries a code")
    func theAirCarriesNoCode() throws {
        let room = aliceAndBob()
        room.measure("alice", "bob", 0.04)
        room.accept("alice")
        room.accept("bob")
        try #require(room.arrived["alice"] == ["bob's code"], "precondition: the swap happened")

        for sent in room.wire {
            let bytes = try JSONEncoder().encode(sent.message)
            for code in ["alice's code", "bob's code"] {
                #expect(bytes.range(of: Data(code.utf8)) == nil, "\(sent.from) sent \(code) where anybody nearby could read it")
            }
        }
    }

    @Test("A message played back, or bounced back to its sender, does nothing")
    func replayedOrReflectedDoesNothing() throws {
        let room = aliceAndBob()
        room.measure("alice", "bob", 0.04)
        room.accept("alice")
        room.accept("bob")
        let fromBob = try #require(room.wire.last { $0.from == "bob" && $0.to == "alice" })
        let fromAlice = try #require(room.wire.last { $0.from == "alice" && $0.to == "bob" })

        room.replay(fromBob.message, from: "bob", to: "alice")
        room.replay(fromAlice.message, from: "bob", to: "alice")
        #expect(room.arrived["alice"] == ["bob's code"], "a played-back or bounced message was taken again")
    }

    @Test("A second hello cannot change the key or the phone being measured")
    func aSecondHelloChangesNothing() {
        let room = aliceAndBob()
        let again = room.hello(
            to: "alice", from: "bob", token: Data("another token".utf8), commitment: Data(repeating: 9, count: 32))
        #expect(again.rangeWith.isEmpty)
        #expect(room.ranging["alice"] == ["bob"])
    }

    @Test("A phone's own hello, played back to it, is refused")
    func itsOwnHelloIsRefused() throws {
        let room = Room(["alice": "alice's code", "bob": "bob's code", "mallory": "mallory's code"])
        room.connect("alice", "bob")
        let hers = try #require(
            room.wire.lazy.compactMap { sent -> Data? in
                guard sent.from == "alice", case .hello(_, let commitment) = sent.message else { return nil }
                return commitment
            }.first)
        room.link("alice", "mallory")
        let token = Data("token mallory to alice".utf8)

        let bounced = room.hello(to: "alice", from: "mallory", token: token, commitment: hers)
        #expect(bounced.rangeWith.isEmpty, "a phone took its own commitment back, so what it sent could be bounced back")
        let theirs = Data(SHA256.hash(data: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation))
        let fresh = room.hello(to: "alice", from: "mallory", token: token, commitment: theirs)
        #expect(!fresh.rangeWith.isEmpty, "precondition: a commitment of its own is taken")
    }

    @Test("A token another phone already presented is refused")
    func aCopiedTokenIsRefused() {
        let room = Room(["alice": "alice's code", "bob": "bob's code", "carol": "carol's code"])
        room.connect("alice", "bob")
        room.link("alice", "carol")
        let commitment = Data(SHA256.hash(data: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation))
        let copied = room.hello(
            to: "alice", from: "carol", token: Data("token bob to alice".utf8), commitment: commitment)
        #expect(copied.rangeWith.isEmpty, "a phone was measured under a token another phone had presented")
        let its = room.hello(
            to: "alice", from: "carol", token: Data("token carol to alice".utf8), commitment: commitment)
        #expect(!its.rangeWith.isEmpty, "precondition: a token of its own is taken")
    }

    @Test("What a phone hands over is bounded in size and in number")
    func handOversAreBounded() {
        let room = aliceAndBob()
        room.measure("alice", "bob", 0.04)
        room.accept("alice")
        room.accept("bob")
        room.handOver(String(repeating: "x", count: TapSwap.largestHandOver + 1), from: "bob")
        for index in 0..<(TapSwap.mostHandOvers + 2) { room.handOver("more \(index)", from: "bob") }
        #expect(room.arrived["alice", default: []].count == TapSwap.mostHandOvers)
        #expect(!room.arrived["alice", default: []].contains { $0.count > TapSwap.largestHandOver })
    }
}
