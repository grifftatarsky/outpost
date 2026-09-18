import Foundation

public enum BubblePosition: Hashable, Sendable {
    case only
    case first
    case middle
    case last

    public var hasTail: Bool {
        switch self {
        case .only, .last: true
        case .first, .middle: false
        }
    }
}

public struct MessageRun: Identifiable, Hashable, Sendable {
    public let author: Member
    public let isMine: Bool
    public let messages: [Message]

    public var id: MessageID { messages[0].id }

    public init(author: Member, isMine: Bool, messages: [Message]) {
        precondition(!messages.isEmpty, "A run is defined by its messages and cannot be empty")
        self.author = author
        self.isMine = isMine
        self.messages = messages
    }

    public func position(at index: Int) -> BubblePosition {
        switch index {
        case _ where messages.count == 1: .only
        case 0: .first
        case messages.count - 1: .last
        default: .middle
        }
    }
}

public enum TranscriptItem: Identifiable, Hashable, Sendable {
    case run(MessageRun)
    case notice(RoomNotice)

    public var id: EntryHash {
        switch self {
        case .run(let run): run.id.entry
        case .notice(let notice): notice.id
        }
    }

    public var isNotice: Bool {
        if case .notice = self { return true }
        return false
    }
}

public enum NoticeRunPosition: Sendable, Hashable {
    case alone
    case first
    case middle
    case last

    public var opensARun: Bool { self == .alone || self == .first }
    public var closesARun: Bool { self == .alone || self == .last }
}

public enum ConversationLayout {
    public static let defaultGroupingWindow: TimeInterval = 300

    public static func items(
        from transcript: [TranscriptEntry],
        groupingWindow: TimeInterval = defaultGroupingWindow
    ) -> [TranscriptItem] {
        var items: [TranscriptItem] = []
        var current: [Message] = []

        func flush() {
            guard let first = current.first else { return }
            items.append(
                .run(MessageRun(author: first.author, isMine: first.isMine, messages: current)))
            current = []
        }

        for entry in transcript {
            switch entry {
            case .notice(let notice):
                flush()
                items.append(.notice(notice))
            case .message(let message):
                if let previous = current.last,
                    previous.author.id == message.author.id,
                    previous.isMine == message.isMine,
                    message.sentAt.timeIntervalSince(previous.sentAt) <= groupingWindow
                {
                    current.append(message)
                } else {
                    flush()
                    current = [message]
                }
            }
        }
        flush()

        return items
    }

    public static func noticePositions(in items: [TranscriptItem]) -> [EntryHash: NoticeRunPosition]
    {
        var positions: [EntryHash: NoticeRunPosition] = [:]
        for (index, item) in items.enumerated() {
            guard case .notice(let notice) = item else { continue }
            let follows = index > 0 && items[index - 1].isNotice
            let leads = index + 1 < items.count && items[index + 1].isNotice
            positions[notice.id] =
                switch (follows, leads) {
                case (false, false): .alone
                case (false, true): .first
                case (true, true): .middle
                case (true, false): .last
                }
        }
        return positions
    }

    public static func runs(
        from messages: [Message],
        groupingWindow: TimeInterval = defaultGroupingWindow
    ) -> [MessageRun] {
        items(from: messages.map(TranscriptEntry.message), groupingWindow: groupingWindow)
            .compactMap { if case .run(let run) = $0 { run } else { nil } }
    }
}
