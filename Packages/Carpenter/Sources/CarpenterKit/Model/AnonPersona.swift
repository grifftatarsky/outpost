import Foundation

public struct AnonPersona: Hashable, Sendable {
    public enum Face: String, Hashable, Sendable, Codable, CaseIterable {
        case question
        case cheshire
        case phantom
        case anonymous
        case somewhere
        case letter

        public var symbol: String {
            switch self {
            case .question: return "questionmark"
            case .cheshire: return "cat.fill"
            case .phantom: return "theatermasks.fill"
            case .anonymous: return "person.fill"
            case .somewhere: return "globe"
            case .letter: return "envelope.fill"
            }
        }
    }

    public var face: Face
    public var name: String?

    public static let nameLimit = 40

    public init(face: Face = .question, name: String? = nil) {
        self.face = face
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = (trimmed?.isEmpty ?? true) ? nil : String(trimmed!.prefix(Self.nameLimit))
    }

    public var displayName: String { name ?? AnonPersonaCopy.name(of: face) }

    public static let `default` = AnonPersona()
}

extension ParticipantID {
    public static let anonymous = ParticipantID(rawValue: Data(repeating: 0, count: 32))
}
