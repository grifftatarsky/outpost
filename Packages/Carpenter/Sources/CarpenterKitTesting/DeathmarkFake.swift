import CarpenterKit
import Foundation

public actor InMemoryDeathmarkBoard: DeathmarkBoard {
    private var sealed: Data?
    private var storedAt: Date?
    private var checkOffs: [DeviceID: Data] = [:]
    private let clock: any Clock
    public private(set) var clearCount = 0
    public private(set) var reads = 0

    public init(clock: any Clock = SystemClock()) {
        self.clock = clock
    }

    public func read() -> PostedDeathmark? {
        reads += 1
        return sealed.map { PostedDeathmark(sealed: $0, storedAt: storedAt, checkedOff: Set(checkOffs.keys)) }
    }

    public func post(_ sealed: Data) {
        self.sealed = sealed
        storedAt = clock.now
        checkOffs = [:]
    }

    public func checkOff(_ device: DeviceID, sealed: Data) {
        guard self.sealed != nil else { return }
        checkOffs[device] = sealed
    }

    public func clear() {
        sealed = nil
        storedAt = nil
        checkOffs = [:]
        clearCount += 1
    }

    public func overwrite(with sealed: Data, storedAt: Date) {
        self.sealed = sealed
        self.storedAt = storedAt
        checkOffs = [:]
    }

    public var isPosted: Bool { sealed != nil }
    public var checkedOff: Set<DeviceID> { Set(checkOffs.keys) }
}
