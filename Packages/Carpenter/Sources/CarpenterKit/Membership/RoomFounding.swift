import CryptoKit
import Foundation

extension RoomID {
    public static let foundingBytes = 32

    public static func founded(by founder: ParticipantID, as kind: RoomKind, founding: Data) -> RoomID {
        let digest = Array(
            SHA256.hash(
                data: CanonicalBytes.payload(
                    domain: Domain.roomFounding, fields: [founder.rawValue, Data(kind.rawValue.utf8), founding])))
        return RoomID(
            rawValue: UUID(
                uuid: (
                    digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
                    digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]
                )))
    }

    public static func founding(by founder: ParticipantID, as kind: RoomKind) -> (room: RoomID, founding: Data) {
        let founding = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        return (founded(by: founder, as: kind, founding: founding), founding)
    }
}

extension RoomProfileBody {
    public func founds(_ room: RoomID?, by author: ParticipantID) -> Bool {
        guard let room, let founding, founding.count == RoomID.foundingBytes else { return false }
        return RoomID.founded(by: author, as: kind ?? .room, founding: founding) == room
    }
}
