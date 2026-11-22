@testable import CarpenterApp
@testable import CarpenterKit
import Foundation

extension Gathering {
    func outpost(of owner: String) -> RoomID { self[owner].outpostRoom(for: id(owner)) }

    func reads(_ body: String, onTheOutpostOf owner: String, on name: String) -> Bool {
        self[name].feed().contains { $0.body == body && $0.author.id == id(owner) }
    }

    func post(saying body: String, onTheOutpostOf owner: String, on name: String) -> OutpostPost? {
        self[name].feed().first { $0.body == body && $0.author.id == id(owner) }
    }

    func entry(ofPostSaying body: String, by owner: String) -> Entry? {
        guard let post = self[owner].outpost().first(where: { $0.body == body }) else { return nil }
        return self[owner].replica.allEntries.first { $0.hash == post.id.entry }
    }
}
