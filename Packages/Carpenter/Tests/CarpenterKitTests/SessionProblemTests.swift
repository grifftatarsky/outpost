import CarpenterApp
import CarpenterKit
import Testing

@Suite("What a refusal says")
struct SessionProblemTests {
    private static let everyRefusal: [AppSessionError] = [
        .noIdentity, .unknownRoom, .cannotRevokeThisDevice, .notAJoiningDevice, .thatIsYou,
        .nothingToSay, .unknownMessage, .notYourMessage, .tooLateToEdit, .tooLateToWithdraw,
        .tooManyPictures, .keyNotTurned(rooms: 2),
    ]

    @Test("Every refusal is a sentence, and never the one Foundation makes up")
    func everyCaseReads() {
        for refusal in Self.everyRefusal {
            let sentence = SessionProblem.sentence(for: refusal)
            #expect(!sentence.isEmpty, "\(refusal) has nothing to say")
            #expect(
                !sentence.contains("couldn\u{2019}t be completed"),
                "\(refusal) fell through to Foundation's description")
            #expect(
                !sentence.contains("CarpenterApp"), "\(refusal) shows a type name to a member")
        }
    }

    @Test("A closed window says what closed and does not apologise")
    func windowsReadWell() {
        let edit = SessionProblem.sentence(for: AppSessionError.tooLateToEdit)
        #expect(edit.contains("fifteen minutes"))
        let withdraw = SessionProblem.sentence(for: AppSessionError.tooLateToWithdraw)
        #expect(withdraw.contains("two minutes"))
        for sentence in [edit, withdraw] {
            #expect(!sentence.localizedStandardContains("sorry"))
            #expect(!sentence.localizedStandardContains("error"))
        }
    }

    private static let everyMembershipRefusal: [MembershipError] = [
        .wrongInviter, .wrongJoiner, .expired, .badSignature, .inviterNotAMember, .wrongRoom,
        .malformedInvite, .notTheFounder, .notAMember, .cannotRemoveYourself,
        .removedFromThisRoom, .leftThisRoom, .soloNotVerified, .alreadyInTheRoom, .unknownInviter,
        .invitationWithdrawn,
    ]

    @Test("A membership refusal is a sentence too, not a case number")
    func everyMembershipCaseReads() {
        for refusal in Self.everyMembershipRefusal {
            let sentence = SessionProblem.sentence(for: refusal)
            #expect(!sentence.isEmpty, "\(refusal) has nothing to say")
            #expect(
                !sentence.contains("couldn\u{2019}t be completed"),
                "\(refusal) fell through to Foundation's description")
            #expect(
                !sentence.contains("Carpenter"), "\(refusal) shows a type name to a member")
        }
    }

    @Test("An invitation that ran out says so, and says what to do instead")
    func theExpiredOneSaysWhatToDo() {
        let expired = SessionProblem.sentence(for: MembershipError.expired)
        #expect(expired.localizedStandardContains("ran out"))
        #expect(expired.localizedStandardContains("another"), "it refused and offered nothing")
        #expect(!expired.localizedStandardContains("sorry"))
    }

    @Test("An error the app has no sentence for keeps the one it came with")
    func othersKeepTheirOwn() {
        struct Elsewhere: Error {}
        #expect(SessionProblem.sentence(for: Elsewhere()) == Elsewhere().localizedDescription)
    }
}
