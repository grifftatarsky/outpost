import CarpenterKit
import CryptoKit
import Foundation

public actor FakeHardwareKeys: HardwareKeys {
    public enum Holder: Sendable {
        case owner
        case ownerWithThePasscode
        case somebodyWhoCancels
        case somebodyWhoFails
    }

    private var keys: [HardwareKeyID: P256.KeyAgreement.PrivateKey] = [:]
    private var rules: [HardwareKeyID: HardwareKeyRule] = [:]
    private var facesChangedFor: Set<HardwareKeyID> = []
    private var heldSheets: [CheckedContinuation<Void, Never>] = []

    public private(set) var agreements = 0
    public private(set) var sheets = 0
    public private(set) var holder: Holder = .owner
    public private(set) var hasPasscode = true
    public private(set) var isAvailable = true
    public private(set) var phoneIsLocked = false
    public private(set) var holdsSheetsOpen = false
    public private(set) var makingNeedsAPasscode = false

    public init() {}

    public func setMakingNeedsAPasscode(_ needs: Bool) { makingNeedsAPasscode = needs }

    public func hand(to holder: Holder) { self.holder = holder }

    public func makeUnavailable() { isAvailable = false }

    public func lockPhone() { phoneIsLocked = true }

    public func unlockPhone() { phoneIsLocked = false }

    public func changeFaces() {
        facesChangedFor.formUnion(rules.filter { $0.value == .enrolledFaces }.map(\.key))
    }

    public func turnOffPasscode(keysSurvive: Bool) {
        hasPasscode = false
        guard !keysSurvive else { return }
        for (id, rule) in rules where rule != .unlockedPhone {
            keys[id] = nil
            rules[id] = nil
        }
    }

    public func turnOnPasscode() { hasPasscode = true }

    public func holdSheetsOpen() { holdsSheetsOpen = true }

    public var sheetsWaiting: Int { heldSheets.count }

    public func answerHeldSheets() {
        holdsSheetsOpen = false
        let waiting = heldSheets
        heldSheets = []
        for sheet in waiting { sheet.resume() }
    }

    public var held: Set<HardwareKeyID> { Set(keys.keys) }

    public func rule(of id: HardwareKeyID) -> HardwareKeyRule? { rules[id] }

    public func forgetEverything() {
        keys = [:]
        rules = [:]
        facesChangedFor = []
    }

    public func make(_ id: HardwareKeyID, opensFor rule: HardwareKeyRule) async throws -> Data {
        guard isAvailable else { throw HardwareKeyError.unavailable }
        if rule != .unlockedPhone, !hasPasscode, makingNeedsAPasscode { throw HardwareKeyError.noPasscode }
        let key = P256.KeyAgreement.PrivateKey()
        keys[id] = key
        rules[id] = rule
        return key.publicKey.x963Representation
    }

    public func agree(_ id: HardwareKeyID, with publicKey: Data, reason: String) async throws -> Data {
        guard let key = keys[id], let rule = rules[id] else { throw HardwareKeyError.noSuchKey }
        guard isAvailable else { throw HardwareKeyError.unavailable }
        guard !phoneIsLocked else { throw HardwareKeyError.locked }
        if rule != .unlockedPhone {
            guard hasPasscode else { throw HardwareKeyError.noPasscode }
            guard !reason.isEmpty else { throw HardwareKeyError.unavailable }
            try await showSheet(for: id, rule: rule)
        }
        agreements += 1
        let theirs = try P256.KeyAgreement.PublicKey(x963Representation: publicKey)
        return try key.sharedSecretFromKeyAgreement(with: theirs).withUnsafeBytes { Data($0) }
    }

    public func remove(_ id: HardwareKeyID) async throws {
        keys[id] = nil
        rules[id] = nil
        facesChangedFor.remove(id)
    }

    private func showSheet(for id: HardwareKeyID, rule: HardwareKeyRule) async throws {
        sheets += 1
        if holdsSheetsOpen { await withCheckedContinuation { heldSheets.append($0) } }
        switch holder {
        case .owner:
            if rule == .enrolledFaces, facesChangedFor.contains(id) { throw HardwareKeyError.refused }
        case .ownerWithThePasscode:
            if rule == .enrolledFaces { throw HardwareKeyError.refused }
        case .somebodyWhoCancels, .somebodyWhoFails:
            throw HardwareKeyError.refused
        }
    }
}
