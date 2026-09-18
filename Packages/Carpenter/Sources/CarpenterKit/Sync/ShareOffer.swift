import Foundation

public struct ShareOffer: Hashable, Sendable {
    public let fetchTag: RecipientTag

    public let name: String

    public let sealed: Data

    public let digest: String

    public init(fetchTag: RecipientTag, name: String, sealed: Data, digest: String) {
        self.fetchTag = fetchTag
        self.name = name
        self.sealed = sealed
        self.digest = digest
    }
}
