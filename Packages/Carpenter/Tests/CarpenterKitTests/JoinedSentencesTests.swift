import CarpenterKit
import Foundation
import SwiftUI
import Testing

@testable import CarpenterUI

@MainActor
@Suite("Sentences built from sentences read as one, with the spaces where they belong")
struct JoinedSentencesTests {
    private let ada = Member(id: ParticipantID(rawValue: Data(repeating: 4, count: 32)), displayName: "Ada")

    private func status(
        recovered: Int = 0, stillMissing: Int = 0, nobody: Int = 0, notArrived: Int = 0,
        unverifiable: Int = 0
    ) -> HistoryRepairStatus {
        HistoryRepairStatus(
            id: RepairID(), room: ConversationID.room(UUID()), startedAt: .distantPast, asked: [ada], answered: [ada],
            waiting: [], recovered: recovered, stillMissing: stillMissing, heldByNobodyAsked: nobody,
            sentButNotArrived: notArrived, unverifiable: unverifiable)
    }

    @Test("A finished repair says what it checked and what it found")
    func repairLines() {
        #expect(resolved(RepairCopy.line(for: status())) == "Checked with Ada. Nothing is missing.")
        #expect(
            resolved(RepairCopy.line(for: status(recovered: 2)))
                == "Checked with Ada. 2 missing entries arrived. Nothing is missing now.")
        #expect(
            resolved(RepairCopy.line(for: status(stillMissing: 1, nobody: 1)))
                == "Checked with Ada. 1 entry still missing, and nobody asked has them.")
        #expect(
            resolved(RepairCopy.line(for: status(recovered: 1, unverifiable: 1)))
                == "Checked with Ada. 1 missing entry arrived. 1 entry will not verify: a device that signed them had stopped being allowed to speak for its member.")
    }

    @Test("An edited message's mark says the edit and then the delivery")
    func editedMark() {
        #expect(
            resolved(DeliveryMarkView(delivery: .sent, isEdited: true).spoken)
                == "Edited. Sent. Not collected yet.")
    }
}
