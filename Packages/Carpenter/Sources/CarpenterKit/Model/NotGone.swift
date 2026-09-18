import Foundation

public struct NotGone: Hashable, Sendable {
    public enum Signal: Hashable, Sendable {
        case newerMessagesCollected(Int)
        case waited(days: Int)
    }

    public let signal: Signal
    public let hasLeftThisDevice: Bool

    public init(signal: Signal, hasLeftThisDevice: Bool) {
        self.signal = signal
        self.hasLeftThisDevice = hasLeftThisDevice
    }

    public static func notices(
        in messages: [Message], now: Date, wait: NotGoneWait
    ) -> [MessageID: NotGone] {
        var notices: [MessageID: NotGone] = [:]
        var newerCollected = 0

        for message in messages.reversed() where message.isMine && !message.isWithdrawn {
            if message.delivery.isCollected {
                newerCollected += 1
                continue
            }
            guard message.delivery == .pending || message.delivery == .sent else { continue }
            let hasLeft = message.delivery == .sent

            if newerCollected > 1 {
                notices[message.id] = NotGone(
                    signal: .newerMessagesCollected(newerCollected), hasLeftThisDevice: hasLeft)
            } else if let days = wait.days,
                now.timeIntervalSince(message.sentAt) >= Double(days) * 86_400
            {
                notices[message.id] = NotGone(signal: .waited(days: days), hasLeftThisDevice: hasLeft)
            }
        }
        return notices
    }
}

public struct NotGoneWait: Hashable, Codable, Sendable {
    public static let range = 1...7
    public static let standard = NotGoneWait(days: 3)
    public static let off = NotGoneWait(days: nil)

    public let days: Int?

    public init(days: Int?) {
        self.days = days.map { min(max($0, Self.range.lowerBound), Self.range.upperBound) }
    }
}

public struct WaitingOnPerson: Identifiable, Hashable, Sendable {
    public enum Holding: Hashable, Sendable {
        case everything
        case missing(Int)
        case notCheckedYet
    }

    public let member: Member
    public let holding: Holding
    public let lastHeard: Date?

    public var id: ParticipantID { member.id }

    public init(member: Member, holding: Holding, lastHeard: Date?) {
        self.member = member
        self.holding = holding
        self.lastHeard = lastHeard
    }
}
