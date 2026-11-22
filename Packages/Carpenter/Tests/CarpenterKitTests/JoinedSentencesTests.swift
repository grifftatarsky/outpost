import CarpenterKit
import Foundation
import SwiftUI
import Testing

@testable import CarpenterUI

@MainActor
@Suite("Sentences built from sentences read as one, with the spaces where they belong", .tags(.ui))
struct JoinedSentencesTests {
    private let ada = Member(id: ParticipantID(rawValue: Data(repeating: 4, count: 32)), displayName: "Ada")

    private func status(
        recovered: Int = 0, stillMissing: Int = 0, nobody: Int = 0, notArrived: Int = 0,
        unverifiable: Int = 0
    ) -> HistoryRepairStatus {
        HistoryRepairStatus(
            id: RepairID(), room: RoomID(), startedAt: .distantPast, asked: [ada], answered: [ada],
            waiting: [], recovered: recovered, stillMissing: stillMissing, heldByNobodyAsked: nobody,
            sentButNotArrived: notArrived, unverifiable: unverifiable)
    }

    @Test("A finished repair says what it checked and what it found")
    func repairLines() {
        #expect(resolved(RepairCopy.line(for: status())) == "Checked with Ada. Nothing is missing.")
        #expect(
            resolved(RepairCopy.line(for: status(recovered: 2)))
                == "Checked with Ada. 2 missing items arrived. Nothing is missing now.")
        #expect(
            resolved(RepairCopy.line(for: status(stillMissing: 1, nobody: 1)))
                == "Checked with Ada. 1 item still missing, and nobody asked has them.")
        #expect(
            resolved(RepairCopy.line(for: status(recovered: 1, unverifiable: 1)))
                == "Checked with Ada. 1 missing item arrived. 1 item can't be verified: the device that signed them was no longer allowed to act for its member.")
    }

    @Test("An edited message's mark says the edit and then the delivery")
    func editedMark() {
        #expect(
            resolved(DeliveryMarkView(delivery: .sent, isEdited: true).spoken)
                == "Edited. Sent. Not received yet.")
    }
}
