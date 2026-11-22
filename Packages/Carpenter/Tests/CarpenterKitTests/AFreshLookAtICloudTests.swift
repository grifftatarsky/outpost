@testable import CarpenterCloudKit
import Foundation
import Testing

@Suite("A fresh look at iCloud", .tags(.sync))
struct AFreshLookAtICloudTests {
    private actor Reads {
        private(set) var begun = 0
        private var held: CheckedContinuation<Void, Never>?

        func read(holdingTheFirst: Bool) async {
            begun += 1
            guard holdingTheFirst, begun == 1 else { return }
            await withCheckedContinuation { held = $0 }
        }

        func letTheFirstFinish() {
            held?.resume()
            held = nil
        }
    }

    private func untilARead(hasBegunOn reads: Reads) async throws {
        for _ in 0..<100_000 where await reads.begun == 0 { await Task.yield() }
        try #require(await reads.begun == 1, "precondition: the first read began")
    }

    @Test("A fresh look asked for while a read is under way gets a read that began after it was asked")
    func aLookAskedDuringAReadBeginsAnother() async throws {
        let (index, reads) = (PairIndex(), Reads())
        let first = Task { try await index.refresh { await reads.read(holdingTheFirst: true) } }
        try await untilARead(hasBegunOn: reads)

        await index.invalidate()
        let second = Task { try await index.refresh { await reads.read(holdingTheFirst: true) } }
        for _ in 0..<1_000 { await Task.yield() }
        await reads.letTheFirstFinish()
        try await first.value
        try await second.value

        #expect(await reads.begun == 2, "the fresh look was answered by a read that began before it was asked")
    }

    @Test("Two reads asked for with no fresh look between them share one")
    func twoReadsShareOne() async throws {
        let (index, reads) = (PairIndex(), Reads())
        let first = Task { try await index.refresh { await reads.read(holdingTheFirst: true) } }
        try await untilARead(hasBegunOn: reads)

        let second = Task { try await index.refresh { await reads.read(holdingTheFirst: true) } }
        for _ in 0..<1_000 { await Task.yield() }
        await reads.letTheFirstFinish()
        try await first.value
        try await second.value
        try await index.refresh { await reads.read(holdingTheFirst: true) }

        #expect(await reads.begun == 1, "a second read was made within two seconds with no fresh look asked for")
    }

    @Test("A fresh look after a read has finished reads again, even within two seconds")
    func aLookAfterAReadReadsAgain() async throws {
        let (index, reads) = (PairIndex(), Reads())
        try await index.refresh { await reads.read(holdingTheFirst: false) }
        await index.invalidate()
        try await index.refresh { await reads.read(holdingTheFirst: false) }

        #expect(await reads.begun == 2, "a fresh look was answered from what was read before it was asked")
    }
}
