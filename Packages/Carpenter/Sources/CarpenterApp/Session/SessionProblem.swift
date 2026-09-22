import CarpenterKit
import Foundation

public enum SessionProblem {
    public static func sentence(for error: any Error) -> String {
        if let membership = error as? MembershipError { return sentence(for: membership) }
        if let mailbox = error as? MailboxFailure { return sentence(for: mailbox) }
        guard let refusal = error as? AppSessionError else { return error.localizedDescription }

        switch refusal {
        case .tooLateToEdit:
            return String(
                localized: "The fifteen minutes to change these words are up. Everybody who has it already read them as they are.",
                bundle: .module, comment: "The edit window has closed")
        case .tooLateToWithdraw:
            return String(
                localized: "The two minutes to take this back are up. It stays where it is.",
                bundle: .module, comment: "The withdrawal window has closed")
        case .notYourMessage:
            return String(
                localized: "Only the person who wrote it can change it.",
                bundle: .module, comment: "Tried to change somebody else's words")
        case .nothingToSay:
            return String(
                localized: "There is nothing there to save. Taking the words back is withdrawing it, which is a different thing.",
                bundle: .module, comment: "An edit with no words in it")
        case .unknownMessage:
            return String(
                localized: "This device no longer has the entry behind that.",
                bundle: .module, comment: "The entry is not on this device")
        case .cannotWriteThere:
            return String(
                localized: "This device has no key for that Outpost, so nothing written there could be read. Ask them to let you in.",
                bundle: .module, comment: "Tried to comment on an Outpost with no key for it")
        case .readingOnly:
            return String(
                localized: "You chose to read other people's Outposts without joining in. Change that under Outpost settings on the You page.",
                bundle: .module, comment: "Tried to comment or react while set to read only")
        case .tooManyPictures:
            return String(
                localized: "A post carries up to four pictures.",
                bundle: .module, comment: "More pictures than a post carries")
        case .thatIsYou:
            return String(
                localized: "That is you.",
                bundle: .module, comment: "Tried to invite or grant access to oneself")
        case .unknownRoom:
            return String(
                localized: "This device does not have that conversation.",
                bundle: .module, comment: "A room this device does not hold")
        case .noIdentity:
            return String(
                localized: "This device has not finished setting up yet.",
                bundle: .module, comment: "No identity on the device yet")
        case .cannotRevokeThisDevice:
            return String(
                localized: "This is the device you are holding. Removing it would leave nothing able to speak for you.",
                bundle: .module, comment: "Tried to revoke the current device")
        case .notAJoiningDevice:
            return String(
                localized: "That code came from a device that is already set up, so there is nothing to add.",
                bundle: .module, comment: "The pasted offer carries no device subkey")
        case .catchingUp:
            return String(
                localized: "This device is reading back from your iCloud where it had got to. You can write as soon as that is done.",
                bundle: .module, comment: "A reinstalled device has not yet read its own record back")
        case .keyNotTurned(let rooms):
            return String(
                localized: "That device is out. ^[\(rooms) conversation](inflect: true) has not turned its key yet, so it can still read what is said there until something does.",
                bundle: .module, comment: "A device was revoked but some rooms did not turn their key")
        }
    }

    public static func sentence(for refusal: MailboxFailure) -> String {
        switch refusal {
        case .noRoomInICloud:
            return String(
                localized: "Your iCloud is full, so there is nowhere to leave what you write. Free some space in Settings and it will go on its own.",
                bundle: .module,
                comment: "The member's iCloud has no room for the packet this app leaves there")
        case .notSignedIn:
            return String(
                localized: "You are signed out of iCloud, so there is nowhere to leave what you write. Sign in and it will go on its own.",
                bundle: .module, comment: "The member is not signed in to iCloud")
        }
    }

    private static func sentence(for refusal: MembershipError) -> String {
        switch refusal {
        case .expired:
            return String(
                localized: "That invitation ran out before it was answered. Sending another is the way back.",
                bundle: .module, comment: "The invitation's lifetime has passed")
        case .commitmentNotOpened:
            return String(
                localized: "The reply to that invitation did not match the code it answered, so this app has stopped. Nothing from your conversations was shared. Send a fresh invitation and check the characters in person.",
                bundle: .module,
                comment: "The joiner's nonce did not open the commitment in their code")
        case .alreadyInTheRoom:
            return String(
                localized: "They are already here. Taking back an invitation somebody has used takes nothing back — putting them out is removing them, and the room says so.",
                bundle: .module, comment: "Tried to withdraw an invitation somebody already joined on")
        case .invitationWithdrawn:
            return String(
                localized: "That invitation was taken back, so there is nothing to answer. The room says who took it back.",
                bundle: .module, comment: "Acted on an invitation somebody had withdrawn")
        case .notAMember:
            return String(
                localized: "You are not in that conversation, so nothing you say about who is in it would reach anybody.",
                bundle: .module, comment: "Acted on a room this member is not in")
        case .cannotRemoveYourself:
            return String(
                localized: "Leaving is a different thing, and the room is told differently. Use Leave.",
                bundle: .module, comment: "Tried to remove oneself")
        case .removedFromThisRoom:
            return String(
                localized: "You were removed from this conversation, so nothing written here would reach anybody in it.",
                bundle: .module, comment: "Tried to write to a room this member was removed from")
        case .leftThisRoom:
            return String(
                localized: "You left this conversation. Nothing written here would reach anybody still in it.",
                bundle: .module, comment: "Tried to write to a room this member left")
        case .soloNotVerified:
            return String(
                localized: "Check who you are talking to first. Read the characters to each other and say whether they matched.",
                bundle: .module, comment: "A solo held until the two people have checked each other")
        case .notTheFounder:
            return String(
                localized: "Only whoever named this conversation can change how people are let into it.",
                bundle: .module, comment: "Tried to change a room's access rule without founding it")
        case .inviterNotAMember:
            return String(
                localized: "Whoever signed that invitation is not in the conversation, so it lets nobody in.",
                bundle: .module, comment: "The inviter has no standing in the room")
        case .malformedInvite:
            return String(
                localized: "That does not read as an invitation. Ask them to send it again — a code picks up stray characters easily.",
                bundle: .module, comment: "The pasted text is not an invite")
        case .wrongRoom:
            return String(
                localized: "That invitation is for a different conversation.",
                bundle: .module, comment: "An attestation naming another room")
        case .wrongInviter, .wrongJoiner, .badSignature:
            return String(
                localized: "That invitation does not hold up to checking. Do not use it — ask the person by voice, on a number you already had.",
                bundle: .module, comment: "The attestation failed verification")
        case .stillInTheRoom:
            return String(
                localized: "You are still in this conversation. Deleting is for a conversation you have left or been removed from.",
                bundle: .module, comment: "Tried to delete a room this member is still in")
        case .departureNotSent:
            return String(
                localized: "That you left has not been sent yet, so the room would never hear it. Once it has gone, this conversation can be deleted.",
                bundle: .module, comment: "Tried to delete a room before the departure was sent")
        case .unknownInviter:
            return String(
                localized: "This device does not have keys for whoever sent that, so it cannot answer them.",
                bundle: .module, comment: "No keys held for the inviter")
        }
    }
}
