import CarpenterKit
import SwiftUI

enum NoticeCopy {
    static func text(for notice: RoomNotice) -> Text {
        switch notice.kind {
        case .created(let by, let named):
            // COPY BEGIN c50f1148 [NEEDS HUMAN REVIEW]
            return Text("\(by.displayName) started \(named)", bundle: .module)
            // COPY END c50f1148

        case .startedSolo(let by):
            // COPY BEGIN 5ffcfc05 [NEEDS HUMAN REVIEW]
            return Text("\(by.displayName) started this solo", bundle: .module)
            // COPY END 5ffcfc05

        case .renamed(let by, let to):
            // COPY BEGIN 561914ed [NEEDS HUMAN REVIEW]
            return Text("\(by.displayName) renamed this to \(to)", bundle: .module)
            // COPY END 561914ed

        case .invited(let who, let by):
            // COPY BEGIN e318f7b2 [NEEDS HUMAN REVIEW]
            return Text("\(by.displayName) invited \(who.displayName)", bundle: .module)
            // COPY END e318f7b2

        case .confirmed(let who):
            // COPY BEGIN 67c95705 [NEEDS HUMAN REVIEW]
            return Text("\(who.displayName) confirmed the invitation", bundle: .module)
            // COPY END 67c95705

        case .checkAsked(let who):
            // COPY BEGIN 947bd1ef [NEEDS HUMAN REVIEW]
            return Text("\(who.displayName) asked to check who you are talking to", bundle: .module)
            // COPY END 947bd1ef

        case .checkConfirmed(let who):
            // COPY BEGIN 9d9118fb [NEEDS HUMAN REVIEW]
            return Text("\(who.displayName) confirmed the characters", bundle: .module)
            // COPY END 9d9118fb

        case .checkRefused(let who):
            // COPY BEGIN 2061e633 [NEEDS HUMAN REVIEW]
            return Text("\(who.displayName) said the characters did not match", bundle: .module)
            // COPY END 2061e633

        case .tookBackInvitation(let who, let by):
            // COPY BEGIN 646fbb41 [NEEDS HUMAN REVIEW]
            return Text(
                "\(by.displayName) took back the invitation to \(who.displayName)", bundle: .module)
            // COPY END 646fbb41

        case .admitted(let who, let by):
            // COPY BEGIN 921958a3 [NEEDS HUMAN REVIEW]
            return Text("\(by.displayName) let \(who.displayName) in", bundle: .module)
            // COPY END 921958a3

        case .refused(let who, let by):
            // COPY BEGIN eb316c05 [NEEDS HUMAN REVIEW]
            return Text("\(by.displayName) would not let \(who.displayName) in", bundle: .module)
            // COPY END eb316c05

        case .accessChanged(let by, let to):
            // COPY BEGIN ed230ed5 [NEEDS HUMAN REVIEW]
            return Text("\(by.displayName) changed who gets in: \(describe(to))", bundle: .module)
            // COPY END ed230ed5

        case .removed(let who, let by):
            // COPY BEGIN 21b9458a [NEEDS HUMAN REVIEW]
            return Text("\(by.displayName) removed \(who.displayName)", bundle: .module)
            // COPY END 21b9458a

        case .left(let who):
            // COPY BEGIN 04b40a76 [NEEDS HUMAN REVIEW]
            return Text("\(who.displayName) left this room", bundle: .module)
            // COPY END 04b40a76

        case .addedADevice(let who):
            // COPY BEGIN 4310ada4 [NEEDS HUMAN REVIEW]
            return Text("\(who.displayName) added a device", bundle: .module)
            // COPY END 4310ada4
        }
    }

    static func describe(_ access: RoomAccess) -> String {
        // COPY BEGIN a757e8a8 [NEEDS HUMAN REVIEW]
        switch access {
        case .open:
            String(
                localized: "an invitation is enough", bundle: .module,
                comment: "How a room admits people, completing “changed who gets in: …”")
        case .founder:
            String(localized: "whoever started the room decides", bundle: .module)
        case .member:
            String(localized: "one member decides", bundle: .module)
        case .anyMember:
            String(localized: "any member can agree", bundle: .module)
        case .atLeast(let count):
            String(localized: "^[\(count) member](inflect: true) must agree", bundle: .module)
        case .unanimous:
            String(localized: "everybody must agree", bundle: .module)
        }
        // COPY END a757e8a8
    }
}
