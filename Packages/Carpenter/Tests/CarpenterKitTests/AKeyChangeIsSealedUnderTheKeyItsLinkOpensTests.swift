@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("A key change is sealed under the key its link opens", .serialized, .tags(.membership, .manyDevices))
struct AKeyChangeIsSealedUnderTheKeyItsLinkOpensTests {
    private func keyReplaced(by change: EpochChangeBody, in chain: EpochChain) throws -> EpochChain {
        let made = try #require(chain.heldSecrets(at: change.link.epoch).first { change.isAuthentic(under: $0) })
        let before = try #require(change.link.epoch.previous)
        var unwrapping = EpochChain(room: chain.room)
        unwrapping.adopt(made, at: change.link.epoch)
        try unwrapping.record(change.link)
        var replaced = EpochChain(room: chain.room)
        replaced.adopt(try unwrapping.secret(for: before), at: before)
        return replaced
    }

    @Test("An Outpost owed a new key before anything is written still seals each key change under the key it replaces")
    func aFlaggedWallStillSealsEachKeyChangeUnderTheKeyItReplaces() async throws {
        let g = try await Gathering.of("Alice", "Yan")
        _ = try await g.room("Lanterns", host: "Alice", guests: ["Yan"])
        let alice = g["Alice"]
        try await alice.send("before Yan", to: nil)
        let wall = alice.outpostRoom(for: g.id("Alice"))
        alice.persisted.rekeyBeforeWriting.insert(wall)

        try await alice.allowOutpost(g.id("Yan"), everything: false)
        try await alice.send("after Yan", to: nil)
        try await g.settle()

        let chain = try #require(alice.chains[wall])
        let changes = alice.replica.allEntries.compactMap { entry -> (Entry, EpochChangeBody)? in
            guard let opened = entry.opened(using: chain), opened.type == .epochChange,
                let change = try? opened.decode(EpochChangeBody.self)
            else { return nil }
            return (entry, change)
        }
        try #require(changes.count == 2, "precondition: the Outpost's key changed twice, found \(changes.count)")
        for (entry, change) in changes {
            #expect(
                entry.opened(using: try keyReplaced(by: change, in: chain)) != nil,
                "the change to key \(change.link.epoch.rawValue) does not open with the key it replaced")
        }

        let read = g["Yan"].feed().map(\.body)
        #expect(read.contains("after Yan"), "Yan cannot read what was posted after coming in")
        #expect(!read.contains("before Yan"), "Yan read a post from before coming in")
    }
}
