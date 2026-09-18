import CarpenterKit
import SwiftUI

public struct OutpostAccessSubject: Identifiable, Hashable, Sendable {
    public let person: Member
    public let grant: OutpostAccess.Grant?

    public var id: ParticipantID { person.id }

    public init(person: Member, grant: OutpostAccess.Grant?) {
        self.person = person
        self.grant = grant
    }
}

extension View {
    func outpostAccessSheet(
        deciding: Binding<OutpostAccessSubject?>,
        onChoose: @escaping (ParticipantID, OutpostAccessChoice) async -> String?
    ) -> some View {
        sheet(item: deciding) { subject in
            OutpostAccessSheet(person: subject.person, grant: subject.grant) { choice in
                await onChoose(subject.person.id, choice)
            }
        }
    }
}
