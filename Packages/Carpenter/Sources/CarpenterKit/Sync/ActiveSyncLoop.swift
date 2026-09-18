import Foundation

@MainActor
public enum ActiveSyncLoop {
    public static func run(
        interval: Duration,
        isCancelled: () -> Bool,
        sleep: (Duration) async -> Void,
        tick: () async -> Void
    ) async {
        guard !isCancelled() else { return }
        await tick()
        while !isCancelled() {
            await sleep(interval)
            if isCancelled() { break }
            await tick()
        }
    }
}
