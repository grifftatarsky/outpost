import Foundation

public enum AnonPersonaCopy {
    public static func name(of face: AnonPersona.Face) -> String {
        switch face {
        case .question:
            return String(
                localized: "User 403", bundle: .module,
                comment: "The default name for everybody this member has not met")
        case .cheshire:
            return String(
                localized: "A Cheshire Cat", bundle: .module,
                comment: "A name a member can pick for everybody they have not met")
        case .phantom:
            return String(
                localized: "An Opera Phantom", bundle: .module,
                comment: "A name a member can pick for everybody they have not met")
        case .anonymous:
            return String(
                localized: "Anonymous", bundle: .module,
                comment: "A name a member can pick for everybody they have not met")
        case .somewhere:
            return String(
                localized: "Somebody Somewhere", bundle: .module,
                comment: "A name a member can pick for everybody they have not met")
        case .letter:
            return String(
                localized: "Ted L. Mancy", bundle: .module,
                comment: "A name a member can pick for everybody they have not met; a pun on 'anonymity'")
        }
    }
}
