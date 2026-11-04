@testable import CarpenterKit
import Foundation
import Testing

@Suite("A damaged record the reader steps over is gone after the next write")
struct ADamagedRecordIsRepairedTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func recordOffsets(in data: Data) -> [Int] {
        var offsets: [Int] = []
        var cursor = 0
        while cursor + 4 <= data.count {
            offsets.append(cursor)
            let length = data[cursor..<(cursor + 4)].reduce(0) { $0 << 8 | Int($1) }
            cursor += 4 + length
        }
        return offsets
    }

    @Test("A garbled record whose length still frames is repaired by the next append, as a torn tail is")
    func aGarbledRecordIsRepairedByTheNextWrite() async throws {
        let url = TestScratch.root
            .appending(path: "carpenter-tests-\(UUID().uuidString)")
            .appending(path: "log.carpenter")
        var alice = Author()
        var entries: [Entry] = []
        for step in 0..<10 { entries.append(try alice.post("\(step)", at: start.addingTimeInterval(Double(step)))) }
        try await FileLogStore(url: url).append(entries)
        var data = try Data(contentsOf: url)
        let offsets = recordOffsets(in: data)
        data.replaceSubrange(
            (offsets[5] + 4)..<offsets[6], with: Data(repeating: 0x41, count: offsets[6] - offsets[5] - 4))
        try data.write(to: url)

        try await FileLogStore(url: url).append([try alice.post("after", at: start.addingTimeInterval(20))])
        let loaded = try await FileLogStore(url: url).loadAll()

        #expect(loaded.entries.count == 10, "precondition: the nine good records and the new one are read")
        #expect(loaded.termination == .complete, "the next write left the damage in place: \(loaded.termination)")
        #expect(loaded.discardedBytes == 0)
        try await FileLogStore(url: url).removeAll()
    }
}
