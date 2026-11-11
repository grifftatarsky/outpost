import CarpenterKit
import Foundation

public actor HookedMailbox: Mailbox, MediaMailbox {
    public enum Call: String, Sendable, CaseIterable {
        case account, space, spaceForACode, claim, join, reads, close, stopSharing, leave
        case put, fetch, ring, acknowledge, sentPackets, withdraw
        case upload, download, acknowledgeCopy, ownCopy, storedCopies, delete
    }

    public struct Made: Sendable, Equatable {
        public let call: Call
        public let peer: ParticipantID?
        public let packet: PacketID?
    }

    private struct Planned {
        let call: Call
        var times: Int
        let error: MailboxError
        let landing: Bool
    }

    public let inner: InMemoryMailbox
    public private(set) var calls: [Made] = []
    private var duringPut: (@Sendable () async -> Void)?
    private var duringFetch: (@Sendable () async -> Void)?
    private var steps: [Int: @Sendable () async -> Void] = [:]
    private var planned: [Planned] = []
    private var silentAfter: Int?
    private var failingCalls: Set<Int> = []
    private var refusal: MailboxFailure?
    private var unreachable: Set<ParticipantID> = []
    private var unreadable: Set<ParticipantID> = []
    private var toSkip: Set<PacketID> = []
    private var skipped: [ParticipantID: (space: Set<String>, packets: Set<PacketID>)] = [:]
    private var view: LocalPairStore?

    public init(inner: InMemoryMailbox = InMemoryMailbox()) {
        self.inner = inner
    }

    public func onPut(_ work: @escaping @Sendable () async -> Void) { duringPut = work }
    public func onFetch(_ work: @escaping @Sendable () async -> Void) { duringFetch = work }
    public func refuse(_ failure: MailboxFailure) { refusal = failure }
    public func cannotReach(_ peer: ParticipantID) { unreachable.insert(peer) }
    public func reachesEveryone() { unreachable = [] }
    public func cannotCollect(from peer: ParticipantID) { unreadable.insert(peer) }
    public func collectsFromEveryone() { unreadable = [] }

    public func relent() {
        refusal = nil
        silentAfter = nil
    }

    public func before(call number: Int, _ work: @escaping @Sendable () async -> Void) {
        steps[calls.count + number] = work
    }

    public func fail(_ call: Call, times: Int = 1, with error: MailboxError = .unavailable, landing: Bool = false) {
        planned.append(Planned(call: call, times: times, error: error, landing: landing))
    }

    public var faultsPending: Int { planned.count + failingCalls.count + steps.count + toSkip.count }

    public func forgetSteps() {
        steps = [:]
        failingCalls = []
    }

    public func fail(call number: Int) { failingCalls.insert(calls.count + number) }

    public func stopAnswering(after count: Int = 0) { silentAfter = calls.count + count }

    public func hangUp() { silentAfter = max(0, calls.count - 1) }

    public func skip(_ packet: PacketID) { toSkip.insert(packet) }

    public func holdView() async { view = await inner.view() }

    public func refreshView() { view = nil }

    private func pass(
        _ call: Call, _ peer: ParticipantID? = nil, packet: PacketID? = nil
    ) async throws -> MailboxError? {
        calls.append(Made(call: call, peer: peer, packet: packet))
        let number = calls.count
        if let step = steps.removeValue(forKey: number) { await step() }
        if let silentAfter, number > silentAfter { throw MailboxError.unavailable }
        if failingCalls.remove(number) != nil { throw MailboxError.unavailable }
        guard let index = planned.firstIndex(where: { $0.call == call }) else { return nil }
        planned[index].times -= 1
        let fault = planned[index]
        if fault.times <= 0 { planned.remove(at: index) }
        if fault.landing { return fault.error }
        throw fault.error
    }

    private func landed<T>(_ work: () async throws -> T, failing lands: MailboxError?) async throws -> T {
        let value = try await work()
        if let lands { throw lands }
        return value
    }

    public func put(_ packet: SyncPacket, to peer: ParticipantID, in pairs: Pairs) async throws {
        let lands = try await pass(.put, peer, packet: packet.id)
        if let refusal { throw refusal }
        if unreachable.contains(peer) { throw MailboxError.unavailable }
        if let duringPut {
            self.duringPut = nil
            await duringPut()
        }
        try await landed(
            {
                try await inner.put(packet, to: peer, in: pairs)
                try await view?.put(packet, to: peer, in: pairs, as: inner.account(in: pairs), at: inner.now)
            }, failing: lands)
    }

    public func fetch(from peer: ParticipantID, for tags: Set<RecipientTag>, in pairs: Pairs) async throws
        -> [SyncPacket]
    {
        let lands = try await pass(.fetch, peer)
        if let duringFetch {
            self.duringFetch = nil
            await duringFetch()
        }
        if unreadable.contains(peer) { throw MailboxError.unavailable }
        var found: [SyncPacket]
        if let view {
            found = await inner.fetch(from: peer, for: tags, in: pairs, seenIn: view)
        } else {
            found = await inner.fetch(from: peer, for: tags, in: pairs)
        }
        found = await leavingOutSkipped(found, from: peer, in: pairs)
        return try await landed({ found }, failing: lands)
    }

    private func leavingOutSkipped(
        _ found: [SyncPacket], from peer: ParticipantID, in pairs: Pairs
    ) async -> [SyncPacket] {
        let space = await inner.stamps(inSpaceOf: peer, in: pairs)
        if let held = skipped[peer], held.space != space { skipped[peer] = nil }
        let skipping = Set(found.map(\.id)).intersection(toSkip)
        if !skipping.isEmpty {
            toSkip.subtract(skipping)
            skipped[peer] = (space, skipping.union(skipped[peer]?.packets ?? []))
        }
        let hidden = skipped[peer]?.packets ?? []
        return found.filter { !hidden.contains($0.id) }
    }

    public func account(in pairs: Pairs) async throws -> String {
        let lands = try await pass(.account)
        return try await landed({ await inner.account(in: pairs) }, failing: lands)
    }

    public func space(for peer: ParticipantID, naming account: String?, in pairs: Pairs) async throws -> URL {
        let lands = try await pass(.space, peer)
        return try await landed({ try await inner.space(for: peer, naming: account, in: pairs) }, failing: lands)
    }

    public func spaceForACode(in pairs: Pairs) async throws -> URL {
        let lands = try await pass(.spaceForACode)
        return try await landed({ await inner.spaceForACode(in: pairs) }, failing: lands)
    }

    public func claim(_ url: URL, for peer: ParticipantID, naming account: String?, in pairs: Pairs) async throws
        -> URL
    {
        let lands = try await pass(.claim, peer)
        return try await landed({ try await inner.claim(url, for: peer, naming: account, in: pairs) }, failing: lands)
    }

    public func join(_ link: PairLink, of peer: ParticipantID, in pairs: Pairs) async throws -> JoinOutcome {
        let lands = try await pass(.join, peer)
        return try await landed({ await inner.join(link, of: peer, in: pairs) }, failing: lands)
    }

    public func reads(_ peer: ParticipantID, in pairs: Pairs) async throws -> Bool {
        let lands = try await pass(.reads, peer)
        return try await landed({ await inner.reads(peer, in: pairs) }, failing: lands)
    }

    public func close(_ peer: ParticipantID, in pairs: Pairs) async throws {
        let lands = try await pass(.close, peer)
        try await landed({ await inner.close(peer, in: pairs) }, failing: lands)
    }

    public func stopSharing(with peer: ParticipantID, in pairs: Pairs) async throws {
        let lands = try await pass(.stopSharing, peer)
        try await landed({ await inner.stopSharing(with: peer, in: pairs) }, failing: lands)
    }

    public func leave(_ peer: ParticipantID, in pairs: Pairs) async throws {
        let lands = try await pass(.leave, peer)
        try await landed({ await inner.leave(peer, in: pairs) }, failing: lands)
    }

    public func ring(_ peer: ParticipantID, in pairs: Pairs) async throws {
        let lands = try await pass(.ring, peer)
        try await landed({ try await inner.ring(peer, in: pairs) }, failing: lands)
    }

    public func acknowledge(
        _ id: PacketID, from peer: ParticipantID, with receipt: SealedReceipt, in pairs: Pairs
    ) async throws {
        let lands = try await pass(.acknowledge, peer, packet: id)
        try await landed(
            {
                try await inner.acknowledge(id, from: peer, with: receipt, in: pairs)
                try await view?.acknowledge(
                    id, from: peer, with: receipt, in: pairs, as: inner.account(in: pairs), at: inner.now)
            }, failing: lands)
    }

    public func sentPackets(in pairs: Pairs) async throws -> [PacketID: SentPacket] {
        let lands = try await pass(.sentPackets)
        if let view { return try await landed({ await inner.sentPackets(in: pairs, seenIn: view) }, failing: lands) }
        return try await landed({ await inner.sentPackets(in: pairs) }, failing: lands)
    }

    public func withdraw(_ id: PacketID, in pairs: Pairs) async throws {
        let lands = try await pass(.withdraw, packet: id)
        try await landed(
            {
                await inner.withdraw(id, in: pairs)
                await view?.withdraw(id, as: inner.account(in: pairs))
            }, failing: lands)
    }

    public func upload(_ copies: PhotoCopies, in pairs: Pairs) async throws {
        let lands = try await pass(.upload)
        try await landed({ try await inner.upload(copies, in: pairs) }, failing: lands)
    }

    public func download(_ copy: PhotoCopyName, of photo: AttachmentID, from sender: ParticipantID, in pairs: Pairs)
        async throws -> Data?
    {
        let lands = try await pass(.download, sender)
        return try await landed({ await inner.download(copy, of: photo, from: sender, in: pairs) }, failing: lands)
    }

    public func acknowledge(
        copy: PhotoCopyName, from sender: ParticipantID, with receipt: SealedReceipt, by device: DeviceID,
        in pairs: Pairs
    ) async throws {
        let lands = try await pass(.acknowledgeCopy, sender)
        try await landed(
            { try await inner.acknowledge(copy: copy, from: sender, with: receipt, by: device, in: pairs) },
            failing: lands)
    }

    public func ownCopy(_ copy: PhotoCopyName, in pairs: Pairs) async throws -> Data? {
        let lands = try await pass(.ownCopy)
        return try await landed({ await inner.ownCopy(copy, in: pairs) }, failing: lands)
    }

    public func storedCopies(in pairs: Pairs) async throws -> [StoredPhotoCopy] {
        let lands = try await pass(.storedCopies)
        return try await landed({ await inner.storedCopies(in: pairs) }, failing: lands)
    }

    public func delete(copies: Set<PhotoCopyName>, in pairs: Pairs) async throws {
        let lands = try await pass(.delete)
        try await landed({ await inner.delete(copies: copies, in: pairs) }, failing: lands)
    }
}
