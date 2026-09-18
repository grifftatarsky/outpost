import CarpenterKit
import SwiftUI

private struct OwnAvatarKey: EnvironmentKey {
    static let defaultValue: Image? = nil
}

extension EnvironmentValues {
    @Entry public var personAvatars: [ParticipantID: Image] = [:]

    @Entry public var anonFace: AnonPersona.Face = .question

    @Entry public var sharedAvatars: [ParticipantID: Image] = [:]

    @Entry public var outpostAvatars: [ParticipantID: Image] = [:]

    @Entry public var ownOutpostAvatar: Image? = nil

    @Entry public var viewerID: ParticipantID? = nil

    public var ownAvatar: Image? {
        get { self[OwnAvatarKey.self] }
        set { self[OwnAvatarKey.self] = newValue }
    }
}
