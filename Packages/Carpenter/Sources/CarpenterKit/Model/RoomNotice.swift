import Foundation

public struct RoomNotice: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case created(by: Member, named: String)
        case startedSolo(by: Member)
        case renamed(by: Member, to: String)
        case invited(Member, by: Member)
        case confirmed(Member)
        case checkAsked(Member)
        case checkConfirmed(Member)
        case checkRefused(Member)
        case tookBackInvitation(Member, by: Member)
        case admitted(Member, by: Member)
        case refused(Member, by: Member)
        case accessChanged(by: Member, to: RoomAccess)
        case removed(Member, by: Member)
        case left(Member)
        case addedADevice(Member)
    }

    public let id: EntryHash
    public let kind: Kind
    public let at: Date

    public init(id: EntryHash, kind: Kind, at: Date) {
        self.id = id
        self.kind = kind
        self.at = at
    }
}

public enum TranscriptEntry: Identifiable, Hashable, Sendable {
    case message(Message)
    case notice(RoomNotice)

    public var id: EntryHash {
        switch self {
        case .message(let message): message.id.entry
        case .notice(let notice): notice.id
        }
    }

    public var at: Date {
        switch self {
        case .message(let message): message.sentAt
        case .notice(let notice): notice.at
        }
    }

    public var message: Message? {
        if case .message(let message) = self { return message }
        return nil
    }
}

public struct AddedDevice: Hashable, Sendable {
    public let person: ParticipantID
    public let device: DeviceID
    public let at: Date

    public init(person: ParticipantID, device: DeviceID, at: Date) {
        self.person = person
        self.device = device
        self.at = at
    }
}

extension TranscriptEntry {
    public static func inserting(_ notices: [TranscriptEntry], into transcript: [TranscriptEntry])
        -> [TranscriptEntry]
    {
        guard !notices.isEmpty else { return transcript }
        var merged: [TranscriptEntry] = []
        merged.reserveCapacity(transcript.count + notices.count)
        var pending = notices.sorted { $0.at < $1.at }[...]
        for item in transcript {
            while let next = pending.first, next.at <= item.at {
                merged.append(next)
                pending = pending.dropFirst()
            }
            merged.append(item)
        }
        merged.append(contentsOf: pending)
        return merged
    }
}
