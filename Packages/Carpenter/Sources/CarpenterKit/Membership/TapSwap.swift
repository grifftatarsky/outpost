import CryptoKit
import Foundation

public struct TapPeer: Hashable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum TapMessage: Codable, Hashable, Sendable {
    case hello(token: Data, commitment: Data)
    case reveal(key: Data)
    case sealed(Data)
}

public struct TapSwap: Sendable {
    public enum Phase: Hashable, Sendable {
        case looking(closest: Double?)
        case crowded
        case touching
        case waitingForThem
        case swapped
    }

    public struct Send: Hashable, Sendable {
        public let to: TapPeer
        public let message: TapMessage
    }

    public struct Effects: Hashable, Sendable {
        public var sends: [Send] = []
        public var rangeWith: [TapPeer: Data] = [:]
        public var arrived: [String] = []
    }

    public struct Number: Hashable, Sendable {
        public let first: String
        public let second: String
        public let youSayFirst: Bool
    }

    public static let reach = 0.15
    public static let steadyReadings = 3
    public static let freshFor: TimeInterval = 1
    public static let settle: TimeInterval = 2
    public static let askLasts: TimeInterval = 30
    public static let largestHandOver = 16_384
    public static let mostHandOvers = 8
    public static let largestToken = 4_096
    public static let numberLength = 6

    private enum Body: Codable, Hashable {
        case ready
        case handOver(String)
    }

    private struct Word: Codable {
        let number: UInt64
        let body: Body
    }

    private struct Reading: Sendable {
        let distance: Double
        let at: Date
    }

    private struct Peer: Sendable {
        let connectedAt: Date
        var saidHello = false
        var readings: [Reading] = []
        var token: Data?
        var commitment: Data?
        var theirKey: Data?
        var key: Data?
        var number: Number?
        var sent: UInt64 = 0
        var lastHeard: UInt64 = 0

        func latest(at now: Date) -> Double? {
            guard let last = readings.last, now.timeIntervalSince(last.at) <= TapSwap.freshFor else { return nil }
            return last.distance
        }

        func isSteadilyClose(at now: Date) -> Bool {
            latest(at: now) != nil && readings.count == TapSwap.steadyReadings
                && readings.allSatisfy { $0.distance <= TapSwap.reach }
        }
    }

    private let mine: String
    private let secret = Curve25519.KeyAgreement.PrivateKey().rawRepresentation
    private var peers: [TapPeer: Peer] = [:]
    private var candidate: TapPeer?
    private var revealedTo: TapPeer?
    private var touchedAt: Date?
    private var readyFrom: [TapPeer: Date] = [:]
    private var iAccepted = false
    private var theirYes: Date?
    private var handedOver = false
    private var arrivals = 0

    public init(handingOver mine: String) {
        self.mine = mine
    }

    private var agreement: Curve25519.KeyAgreement.PrivateKey? {
        try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: secret)
    }

    private var publicKey: Data { agreement?.publicKey.rawRepresentation ?? Data() }

    // MARK: What the phones around it do

    public mutating func connected(_ peer: TapPeer, token: Data, at now: Date) -> Effects {
        var state = peers[peer] ?? Peer(connectedAt: now)
        guard !state.saidHello else { return Effects() }
        state.saidHello = true
        peers[peer] = state
        return Effects(
            sends: [Send(to: peer, message: .hello(token: token, commitment: Self.commitment(to: publicKey)))])
    }

    public mutating func disconnected(_ peer: TapPeer) {
        peers[peer] = nil
        readyFrom[peer] = nil
        if candidate == peer, !handedOver { forgetTheTouch(keepingTheirYes: false) }
    }

    public mutating func measured(_ peer: TapPeer, distance: Double?, at now: Date) -> Effects {
        guard var state = peers[peer], state.token != nil else { return Effects() }
        state.readings = distance.map { Array((state.readings + [Reading(distance: $0, at: now)]).suffix(Self.steadyReadings)) } ?? []
        peers[peer] = state
        return Effects(sends: reconsider(at: now))
    }

    public mutating func received(_ message: TapMessage, from peer: TapPeer, at now: Date) -> Effects {
        switch message {
        case .hello(let token, let commitment):
            return greet(peer, token: token, commitment: commitment, at: now)
        case .reveal(let key):
            take(key, from: peer)
            return Effects(sends: reconsider(at: now))
        case .sealed(let box):
            let reveal = reconsider(at: now)
            guard let body = open(box, from: peer) else { return Effects(sends: reveal) }
            guard peer == candidate else {
                if body == .ready { readyFrom[peer] = now }
                return Effects(sends: reveal)
            }
            var effects = take(body, at: now)
            effects.sends = reveal + effects.sends
            return effects
        }
    }

    // MARK: What the person holding it does

    public mutating func accept(at now: Date) -> Effects {
        let reveal = reconsider(at: now)
        guard let candidate, !iAccepted, !handedOver, let ready = seal(.ready, to: candidate) else {
            return Effects(sends: reveal)
        }
        iAccepted = true
        return Effects(sends: reveal + [ready] + handOverIfBothAgreed())
    }

    public mutating func handOver(_ text: String) -> Effects {
        guard handedOver, let candidate, let send = seal(.handOver(text), to: candidate) else { return Effects() }
        return Effects(sends: [send])
    }

    public var partner: TapPeer? { handedOver ? candidate : nil }

    public var number: Number? { candidate.flatMap { peers[$0]?.number } }

    public func phase(at now: Date) -> Phase {
        if handedOver { return arrivals > 0 ? .swapped : .waitingForThem }
        if candidate != nil, let touchedAt, now.timeIntervalSince(touchedAt) <= Self.askLasts {
            return iAccepted ? .waitingForThem : .touching
        }
        if peers.values.filter({ $0.isSteadilyClose(at: now) }).count > 1 { return .crowded }
        return .looking(closest: peers.values.compactMap { $0.latest(at: now) }.min())
    }

    // MARK: Choosing the one phone that touched

    private mutating func reconsider(at now: Date) -> [Send] {
        guard !handedOver else { return [] }
        if let candidate, let touchedAt, now.timeIntervalSince(touchedAt) > Self.askLasts {
            peers[candidate]?.readings = []
            forgetTheTouch(keepingTheirYes: false)
        }
        let close = peers.filter { $0.value.isSteadilyClose(at: now) }.map { $0.key }
        if let candidate, close.contains(where: { $0 != candidate }) {
            forgetTheTouch()
            return []
        }
        guard candidate == nil, close.count == 1, let only = close.first, revealedTo == nil || revealedTo == only,
            peers.allSatisfy({ peer, state in
                peer == only || !state.readings.isEmpty || now.timeIntervalSince(state.connectedAt) >= Self.settle
            })
        else { return [] }
        candidate = only
        touchedAt = now
        theirYes = readyFrom[only].flatMap { now.timeIntervalSince($0) <= Self.askLasts ? $0 : nil }
        guard revealedTo == nil else { return [] }
        revealedTo = only
        agree(with: only)
        return [Send(to: only, message: .reveal(key: publicKey))]
    }

    private mutating func forgetTheTouch(keepingTheirYes: Bool = true) {
        if let candidate {
            readyFrom[candidate] = keepingTheirYes ? theirYes : nil
        }
        candidate = nil
        touchedAt = nil
        iAccepted = false
        theirYes = nil
    }

    private mutating func handOverIfBothAgreed() -> [Send] {
        guard iAccepted, theirYes != nil, !handedOver, let candidate, let send = seal(.handOver(mine), to: candidate)
        else { return [] }
        handedOver = true
        return [send]
    }

    private mutating func take(_ body: Body, at now: Date) -> Effects {
        switch body {
        case .ready where handedOver:
            guard let candidate, let again = seal(.handOver(mine), to: candidate) else { return Effects() }
            return Effects(sends: [again])
        case .ready:
            guard theirYes == nil else { return Effects() }
            theirYes = now
            return Effects(sends: handOverIfBothAgreed())
        case .handOver(let text):
            guard iAccepted, arrivals < Self.mostHandOvers, text.utf8.count <= Self.largestHandOver
            else { return Effects() }
            theirYes = theirYes ?? now
            arrivals += 1
            return Effects(sends: handOverIfBothAgreed(), arrived: [text])
        }
    }

    // MARK: The key two phones agree, and what it seals

    private mutating func greet(_ peer: TapPeer, token: Data, commitment: Data, at now: Date) -> Effects {
        var state = peers[peer] ?? Peer(connectedAt: now)
        guard state.token == nil, commitment.count == SHA256.byteCount, commitment != Self.commitment(to: publicKey),
            !token.isEmpty, token.count <= Self.largestToken, !peers.values.contains(where: { $0.token == token })
        else { return Effects() }
        state.token = token
        state.commitment = commitment
        peers[peer] = state
        return Effects(rangeWith: [peer: token])
    }

    private mutating func take(_ key: Data, from peer: TapPeer) {
        guard var state = peers[peer], state.theirKey == nil, key != publicKey,
            let commitment = state.commitment, Self.commitment(to: key) == commitment
        else { return }
        state.theirKey = key
        peers[peer] = state
        if revealedTo == peer { agree(with: peer) }
    }

    private mutating func agree(with peer: TapPeer) {
        guard var state = peers[peer], state.key == nil, let theirKey = state.theirKey,
            let theirs = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirKey),
            let shared = try? agreement?.sharedSecretFromKeyAgreement(with: theirs)
        else { return }
        state.key = Self.sessionKey(shared, between: publicKey, and: theirKey)
        state.number = Self.number(between: publicKey, and: theirKey)
        peers[peer] = state
    }

    private mutating func seal(_ body: Body, to peer: TapPeer) -> Send? {
        guard var state = peers[peer], let key = state.key,
            let word = try? JSONEncoder().encode(Word(number: state.sent + 1, body: body)),
            let box = try? ChaChaPoly.seal(word, using: SymmetricKey(data: key), authenticating: publicKey)
        else { return nil }
        state.sent += 1
        peers[peer] = state
        return Send(to: peer, message: .sealed(box.combined))
    }

    private mutating func open(_ sealed: Data, from peer: TapPeer) -> Body? {
        guard var state = peers[peer], let key = state.key, let theirKey = state.theirKey,
            let box = try? ChaChaPoly.SealedBox(combined: sealed),
            let word = try? ChaChaPoly.open(box, using: SymmetricKey(data: key), authenticating: theirKey),
            let opened = try? JSONDecoder().decode(Word.self, from: word),
            opened.number > state.lastHeard
        else { return nil }
        state.lastHeard = opened.number
        peers[peer] = state
        return opened.body
    }

    private static func commitment(to key: Data) -> Data {
        Data(SHA256.hash(data: CanonicalBytes.payload(domain: Domain.tapCommitment, fields: [key])))
    }

    private static func number(between mine: Data, and theirs: Data) -> Number {
        let youSayFirst = mine.lexicographicallyPrecedes(theirs)
        let (low, high) = youSayFirst ? (mine, theirs) : (theirs, mine)
        let digits = ShortAuthenticationString.derive(
            fromTranscript: CanonicalBytes.payload(domain: Domain.tapNumber, fields: [low, high]),
            count: numberLength, domain: Domain.tapNumber, from: ShortAuthenticationString.digits)
        let half = digits.index(digits.startIndex, offsetBy: numberLength / 2)
        return Number(first: String(digits[..<half]), second: String(digits[half...]), youSayFirst: youSayFirst)
    }

    private static func sessionKey(_ shared: SharedSecret, between one: Data, and other: Data) -> Data {
        let (low, high) = one.lexicographicallyPrecedes(other) ? (one, other) : (other, one)
        return shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(Domain.tapSwap.utf8),
            sharedInfo: CanonicalBytes.payload(domain: Domain.tapSwap, fields: [low, high]),
            outputByteCount: 32
        ).withUnsafeBytes { Data($0) }
    }
}
