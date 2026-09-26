import Foundation

extension Array where Element: Sendable {
    func inParallel<Result: Sendable>(
        atLeast minimumPerLane: Int = 64,
        _ lane: @escaping @Sendable (ArraySlice<Element>) -> [Result]
    ) async -> [Result] {
        let lanes = Swift.max(1, Swift.min(ProcessInfo.processInfo.activeProcessorCount, count / minimumPerLane))
        guard lanes > 1 else { return lane(self[...]) }
        let size = (count + lanes - 1) / lanes

        return await withTaskGroup(of: (start: Int, results: [Result]).self) { group in
            for start in stride(from: 0, to: count, by: size) {
                let slice = self[start..<Swift.min(start + size, count)]
                group.addTask { (start, lane(slice)) }
            }
            var finished: [(start: Int, results: [Result])] = []
            for await done in group { finished.append(done) }
            return finished.sorted { $0.start < $1.start }.flatMap(\.results)
        }
    }
}
