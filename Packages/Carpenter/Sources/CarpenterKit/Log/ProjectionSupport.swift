import Foundation

extension RenderedEntry {
    var isConversation: Bool {
        !PayloadType.plumbing.contains(type)
    }

    var isReadable: Bool {
        if case .sealed = content { return false }
        return true
    }
}

extension Member {
    public static func placeholder(_ id: ParticipantID) -> Member {
        Member(id: id, displayName: id.shortCode, isPlaceholder: true)
    }
}

extension DeviceID {
    public var shortCode: String {
        rawValue.prefix(3).map { String(format: "%02X", $0) }.joined()
    }
}

extension ParticipantID {
    public var shortCode: String {
        rawValue.prefix(3).map { String(format: "%02X", $0) }.joined()
    }

    public var groupedFingerprint: String {
        stride(from: 0, to: 6, by: 2)
            .map { rawValue.dropFirst($0).prefix(2).map { String(format: "%02X", $0) }.joined() }
            .joined(separator: " · ")
    }
}

extension RenderedEntry {
    public var isOnOwnOutpost: Bool { conversation == .outpost(author) }
}
