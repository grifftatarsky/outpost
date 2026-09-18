import CarpenterKit
import SwiftUI

enum NoticeCopy {
    static func text(for notice: RoomNotice) -> Text {
        switch notice.kind {
        case .created(let by, let named):
            return Text("\(by.displayName) started \(named)", bundle: .module)

        case .startedSolo(let by):
            return Text("\(by.displayName) started this solo", bundle: .module)

        case .renamed(let by, let to):
            return Text("\(by.displayName) renamed this to \(to)", bundle: .module)

        case .invited(let who, let by):
            return Text("\(by.displayName) invited \(who.displayName)", bundle: .module)

        case .confirmed(let who):
            return Text("\(who.displayName) confirmed the invitation", bundle: .module)

        case .checkAsked(let who):
            return Text("\(who.displayName) asked to check who you are talking to", bundle: .module)

        case .checkConfirmed(let who):
            return Text("\(who.displayName) confirmed the characters", bundle: .module)

        case .checkRefused(let who):
            return Text("\(who.displayName) said the characters did not match", bundle: .module)

        case .tookBackInvitation(let who, let by):
            return Text(
                "\(by.displayName) took back the invitation to \(who.displayName)", bundle: .module)

        case .admitted(let who, let by):
            return Text("\(by.displayName) let \(who.displayName) in", bundle: .module)

        case .refused(let who, let by):
            return Text("\(by.displayName) would not let \(who.displayName) in", bundle: .module)

        case .accessChanged(let by, let to):
            return Text("\(by.displayName) changed who gets in: \(describe(to))", bundle: .module)

        case .removed(let who, let by):
            return Text("\(by.displayName) removed \(who.displayName)", bundle: .module)

        case .left(let who):
            return Text("\(who.displayName) left this room", bundle: .module)

        case .addedADevice(let who):
            return Text("\(who.displayName) added a device", bundle: .module)
        }
    }

    static func describe(_ access: RoomAccess) -> String {
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
    }
}
