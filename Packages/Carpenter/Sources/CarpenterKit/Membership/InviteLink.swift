import Foundation

public enum InviteLink {
    public enum Contents: Hashable, Sendable {
        case code(JoinerCode)
        case invite(Invite)
    }

    private enum Kind: String {
        case code
        case invite
    }

    private static let payloadKey = "c"

    public static func url(offering code: JoinerCode, scheme: String) throws -> URL {
        try url(kind: .code, payload: code.encoded(), scheme: scheme)
    }

    public static func url(inviting invite: Invite, scheme: String) throws -> URL {
        try url(kind: .invite, payload: invite.encoded(), scheme: scheme)
    }

    public static func read(_ url: URL, scheme: String) -> Contents? {
        guard url.scheme?.lowercased() == scheme.lowercased() else { return nil }

        let name = url.host() ?? url.pathComponents.first { $0 != "/" }
        guard let name, let kind = Kind(rawValue: name.lowercased()) else { return nil }

        guard let payload = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == payloadKey })?.value
        else { return nil }

        switch kind {
        case .code:
            return (try? JoinerCode.decoded(from: payload)).map(Contents.code)
        case .invite:
            return (try? Invite.decoded(from: payload)).map(Contents.invite)
        }
    }

    public static func payload(in text: String) -> String {
        let compact = text.filter { !$0.isWhitespace }
        guard compact.contains("?\(payloadKey)="),
            let components = URLComponents(string: compact),
            let value = components.queryItems?.first(where: { $0.name == payloadKey })?.value
        else { return compact }
        return value
    }

    private static func url(kind: Kind, payload: String, scheme: String) throws -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = kind.rawValue
        components.queryItems = [URLQueryItem(name: payloadKey, value: payload)]
        guard let url = components.url else { throw MembershipError.malformedInvite }
        return url
    }
}

extension InviteLink {
    public static func namesSomebody(_ text: String) -> Bool {
        (try? JoinerCode.decoded(from: payload(in: text))) != nil
    }
}
