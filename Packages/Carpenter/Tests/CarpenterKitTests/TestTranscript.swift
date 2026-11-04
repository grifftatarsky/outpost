@testable import CarpenterKit

extension Projection {
    func transcript(in room: RoomID, opening: (RenderedEntry) -> Payload?) -> [TranscriptEntry] {
        transcript(in: room, opening: opening, roster: roster(of: room, opening: opening))
    }
}
