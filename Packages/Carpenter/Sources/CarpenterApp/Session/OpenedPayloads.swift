import CarpenterKit

final class OpenedPayloads {
    private var byEntry: [EntryHash: Payload] = [:]
    private var steps: [EntryHash: RenderStep] = [:]

    subscript(entry: EntryHash) -> Payload? {
        get { byEntry[entry] }
        set { byEntry[entry] = newValue }
    }

    subscript(step entry: EntryHash) -> RenderStep? {
        get { steps[entry] }
        set { steps[entry] = newValue }
    }

    func forget() {
        byEntry.removeAll()
        steps.removeAll()
    }

    static func keysWereForgotten(from old: [RoomID: EpochChain], to new: [RoomID: EpochChain]) -> Bool {
        old.contains { room, chain in
            guard let now = new[room] else { return true }
            return !chain.knownEpochs.isSubset(of: now.knownEpochs)
        }
    }
}
