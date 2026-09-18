import CarpenterKit
import Foundation
import Testing

@MainActor
@Suite("The active-usage sync loop")
struct ActiveSyncLoopTests {
    @Test("Ticks on a cadence and stops cleanly when cancelled")
    func ticksThenStops() async {
        var ticks = 0
        var waits = 0

        await ActiveSyncLoop.run(
            interval: .seconds(5),
            isCancelled: { waits >= 3 },
            sleep: { _ in waits += 1 },
            tick: { ticks += 1 }
        )

        #expect(ticks == 3, "expected one immediate tick and one after each of two waits")
        #expect(waits == 3)
    }

    @Test("Cancelled before it starts does nothing")
    func cancelledUpFront() async {
        var ticks = 0
        await ActiveSyncLoop.run(
            interval: .seconds(5),
            isCancelled: { true },
            sleep: { _ in },
            tick: { ticks += 1 }
        )
        #expect(ticks == 0, "a loop that ran after cancellation would keep syncing a closed view")
    }
}
