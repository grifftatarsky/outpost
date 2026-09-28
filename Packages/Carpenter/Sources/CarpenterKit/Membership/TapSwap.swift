import CryptoKit
import Foundation

public struct TapPeer: Hashable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum TapMessage: Codable, Hashable, Sendable {
    case hello(token: Data, key: Data)
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

    public static let reach = 0.15
    public static let steadyReadings = 3
    public static let freshFor: TimeInterval = 1
    public static let settle: TimeInterval = 2
    public static let askLasts: TimeInterval = 30
    public static let largestHandOver = 16_384
    public static let mostHandOvers = 8
    public static let largestToken = 4_096

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
        var theirKey: Data?
        var key: Data?
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
    private var touchedAt: Date?
    private var readyFrom: [TapPeer: Date] = [:]
    private var iAccepted = false
    private var theyAccepted = false
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
        return Effects(sends: [Send(to: peer, message: .hello(token: token, key: publicKey))])
    }

    public mutating func disconnected(_ peer: TapPeer) {
        peers[peer] = nil
        readyFrom[peer] = nil
        if candidate == peer, !handedOver { forgetTheTouch(keepingTheirYes: false) }
    }

    public mutating func measured(_ peer: TapPeer, distance: Double?, at now: Date) {
        guard var state = peers[peer], state.key != nil else { return }
        state.readings = distance.map { Array((state.readings + [Reading(distance: $0, at: now)]).suffix(Self.steadyReadings)) } ?? []
        peers[peer] = state
        reconsider(at: now)
    }

    public mutating func received(_ message: TapMessage, from peer: TapPeer, at now: Date) -> Effects {
        switch message {
        case .hello(let token, let key):
            return greet(peer, token: token, key: key, at: now)
        case .sealed(let box):
            reconsider(at: now)
            guard let body = open(box, from: peer) else { return Effects() }
            guard peer == candidate else {
                if body == .ready { readyFrom[peer] = now }
                return Effects()
            }
            return take(body)
        }
    }

    // MARK: What the person holding it does

    public mutating func accept(at now: Date) -> Effects {
        reconsider(at: now)
        guard let candidate, !iAccepted, !handedOver, let ready = seal(.ready, to: candidate) else { return Effects() }
        iAccepted = true
        return Effects(sends: [ready] + handOverIfBothAgreed())
    }

    public mutating func handOver(_ text: String) -> Effects {
        guard handedOver, let candidate, let send = seal(.handOver(text), to: candidate) else { return Effects() }
        return Effects(sends: [send])
    }

    public var partner: TapPeer? { handedOver ? candidate : nil }

    public func phase(at now: Date) -> Phase {
        if handedOver { return arrivals > 0 ? .swapped : .waitingForThem }
        if candidate != nil, let touchedAt, now.timeIntervalSince(touchedAt) <= Self.askLasts {
            return iAccepted ? .waitingForThem : .touching
        }
        if peers.values.filter({ $0.isSteadilyClose(at: now) }).count > 1 { return .crowded }
        return .looking(closest: peers.values.compactMap { $0.latest(at: now) }.min())
    }

    // MARK: Choosing the one phone that touched

    private mutating func reconsider(at now: Date) {
        guard !handedOver else { return }
        if let candidate, let touchedAt, now.timeIntervalSince(touchedAt) > Self.askLasts {
            peers[candidate]?.readings = []
            forgetTheTouch(keepingTheirYes: false)
        }
        let close = peers.filter { $0.value.isSteadilyClose(at: now) }.map { $0.key }
        if let candidate, close.contains(where: { $0 != candidate }) {
            forgetTheTouch()
            return
        }
        guard candidate == nil, close.count == 1, let only = close.first,
            peers.allSatisfy({ peer, state in
                peer == only || !state.readings.isEmpty || now.timeIntervalSince(state.connectedAt) >= Self.settle
            })
        else { return }
        candidate = only
        touchedAt = now
        theyAccepted = readyFrom[only].map { now.timeIntervalSince($0) <= Self.askLasts } ?? false
    }

    private mutating func forgetTheTouch(keepingTheirYes: Bool = true) {
        if let candidate {
            readyFrom[candidate] = keepingTheirYes && theyAccepted ? touchedAt : nil
        }
        candidate = nil
        touchedAt = nil
        iAccepted = false
        theyAccepted = false
    }

    private mutating func handOverIfBothAgreed() -> [Send] {
        guard iAccepted, theyAccepted, !handedOver, let candidate, let send = seal(.handOver(mine), to: candidate)
        else { return [] }
        handedOver = true
        return [send]
    }

    private mutating func take(_ body: Body) -> Effects {
        switch body {
        case .ready:
            guard !theyAccepted else { return Effects() }
            theyAccepted = true
            return Effects(sends: handOverIfBothAgreed())
        case .handOver(let text):
            guard iAccepted, theyAccepted, arrivals < Self.mostHandOvers, text.utf8.count <= Self.largestHandOver
            else { return Effects() }
            arrivals += 1
            return Effects(arrived: [text])
        }
    }

    // MARK: The key two phones agree, and what it seals

    private mutating func greet(_ peer: TapPeer, token: Data, key: Data, at now: Date) -> Effects {
        var state = peers[peer] ?? Peer(connectedAt: now)
        guard state.key == nil, !token.isEmpty, token.count <= Self.largestToken,
            !peers.values.contains(where: { $0.token == token }),
            let theirs = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: key),
            let shared = try? agreement?.sharedSecretFromKeyAgreement(with: theirs)
        else { return Effects() }
        state.token = token
        state.theirKey = key
        state.key = Self.sessionKey(shared, between: publicKey, and: key)
        peers[peer] = state
        return Effects(rangeWith: [peer: token])
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
