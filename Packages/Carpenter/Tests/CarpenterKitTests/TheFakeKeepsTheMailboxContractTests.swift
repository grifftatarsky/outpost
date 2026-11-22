import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@Suite(
    "The in-memory mailbox keeps every rule the iCloud mailbox is held to", .serialized, .timeLimit(.minutes(10)),
    .tags(.sync))
struct TheFakeKeepsTheMailboxContractTests {
    private let nothingToWaitFor: MailboxContract.AfterWrite = {}

    @Test("A packet put is listed with the recipients and contents it was put with")
    func aPutPacketIsListed() async throws {
        try await MailboxContract.aPutPacketIsListed(in: InMemoryMailbox(), afterWrite: nothingToWaitFor)
    }

    @Test("A packet over the record ceiling is refused before anything is stored, and one at the budget goes")
    func theRecordCeilingHolds() async throws {
        try await MailboxContract.theRecordCeilingHolds(in: InMemoryMailbox(), afterWrite: nothingToWaitFor)
    }

    @Test("A withdrawn packet is no longer listed")
    func aWithdrawnPacketIsNoLongerListed() async throws {
        try await MailboxContract.aWithdrawnPacketIsNoLongerListed(in: InMemoryMailbox(), afterWrite: nothingToWaitFor)
    }

    @Test("A person's space is found again, a space for a code is new each time, and claiming one makes it theirs")
    func spacesAreFoundAgainAndCodesAreNew() async throws {
        try await MailboxContract.spacesAreFoundAgainAndCodesAreNew(in: InMemoryMailbox(), afterWrite: nothingToWaitFor)
    }

    @Test("A photo is stored once for each person it is for, and writing it again keeps when it was first stored")
    func aPhotoIsOneCopyPerPerson() async throws {
        try await MailboxContract.aPhotoIsOneCopyPerPerson(in: InMemoryMailbox(), afterWrite: nothingToWaitFor)
    }

    @Test("Joining waits until the reader is named, and one's own link or a link from the wrong account is gone")
    func joinWaitsForTheReaderToBeNamed() async throws {
        try await MailboxContract.runBothRoles(
            .joinWaitsForTheReaderToBeNamed, on: InMemoryMailbox(), afterWrite: nothingToWaitFor)
    }

    @Test("A packet arrives with the bytes it was put with, from its writer, dated when it was last stored")
    func aPacketArrivesAsItWasStored() async throws {
        try await MailboxContract.runBothRoles(
            .aPacketArrivesAsItWasStored, on: InMemoryMailbox(), afterWrite: nothingToWaitFor)
    }

    @Test("Packets arrive in the order they were first stored, whatever was written again since")
    func packetsArriveInTheOrderFirstStored() async throws {
        try await MailboxContract.runBothRoles(
            .packetsArriveInTheOrderFirstStored, on: InMemoryMailbox(), afterWrite: nothingToWaitFor)
    }

    @Test("A receipt shows on the writer's side with when it was stored, and on the reader's next collection")
    func aReceiptReachesBothSides() async throws {
        try await MailboxContract.runBothRoles(
            .aReceiptReachesBothSides, on: InMemoryMailbox(), afterWrite: nothingToWaitFor)
    }

    @Test("A ring is never collected as a packet")
    func aRingIsNeverCollected() async throws {
        try await MailboxContract.runBothRoles(
            .aRingIsNeverCollected, on: InMemoryMailbox(), afterWrite: nothingToWaitFor)
    }

    @Test(
        "Once a space is unshared, left or closed, its reader reads nothing from it",
        arguments: PairEnding.allCases)
    func endingThePairStopsTheReading(_ ending: PairEnding) async throws {
        try await MailboxContract.runBothRoles(
            .endingThePairStopsTheReading(ending), on: InMemoryMailbox(), afterWrite: nothingToWaitFor)
    }
}
