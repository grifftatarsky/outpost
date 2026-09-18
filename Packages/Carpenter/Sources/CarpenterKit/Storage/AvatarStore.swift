import Foundation

public struct FileAvatarStore: Sendable {
    private let url: URL

    public init(directory: URL, name: String = StorageLocation.avatarName) {
        url = directory.appending(path: name)
    }

    public func load() -> Data? {
        try? Data(contentsOf: url)
    }

    public func save(_ jpeg: Data) throws {
        try jpeg.write(to: url, options: .atomic)
    }

    public func remove() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

public struct PersonAvatarStore: Sendable {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory.appending(path: StorageLocation.personAvatarsName)
    }

    private func url(for person: ParticipantID) -> URL {
        directory.appending(path: Self.name(for: person)).appendingPathExtension("jpg")
    }

    static func name(for person: ParticipantID) -> String {
        person.rawValue.map { String(format: "%02x", $0) }.joined()
    }

    static func person(named name: String) -> ParticipantID? {
        guard name.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var index = name.startIndex
        while index < name.endIndex {
            let next = name.index(index, offsetBy: 2)
            guard let byte = UInt8(name[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return ParticipantID(rawValue: Data(bytes))
    }

    public func load(for person: ParticipantID) -> Data? {
        try? Data(contentsOf: url(for: person))
    }

    public func loadAll() -> [ParticipantID: Data] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return [:]
        }
        var all: [ParticipantID: Data] = [:]
        for name in names where name.hasSuffix(".jpg") {
            guard let person = Self.person(named: String(name.dropLast(4))),
                let data = try? Data(contentsOf: directory.appending(path: name))
            else { continue }
            all[person] = data
        }
        return all
    }

    public func save(_ jpeg: Data, for person: ParticipantID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try jpeg.write(to: url(for: person), options: .atomic)
    }

    public func remove(for person: ParticipantID) throws {
        let url = url(for: person)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: What people shared

    public enum Published: String, Sendable, CaseIterable {
        case rooms = "shared"
        case outpost = "outpost"

        fileprivate var infix: String { ".\(rawValue)." }
    }

    private func urls(for person: ParticipantID, _ kind: Published) -> [URL] {
        let prefix = Self.name(for: person) + kind.infix
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".jpg") }
            .map { directory.appending(path: $0) }
    }

    public func publishedAttachment(for person: ParticipantID, _ kind: Published) -> AttachmentID? {
        urls(for: person, kind).first.flatMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard let range = name.range(of: kind.infix) else { return nil }
            return UUID(uuidString: String(name[range.upperBound...])).map(AttachmentID.init(rawValue:))
        }
    }

    public func loadPublished(for person: ParticipantID, _ kind: Published) -> Data? {
        urls(for: person, kind).first.flatMap { try? Data(contentsOf: $0) }
    }

    public func loadAllPublished(_ kind: Published) -> [ParticipantID: Data] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return [:]
        }
        var all: [ParticipantID: Data] = [:]
        for name in names where name.contains(kind.infix) && name.hasSuffix(".jpg") {
            guard let range = name.range(of: kind.infix),
                let person = Self.person(named: String(name[..<range.lowerBound])),
                let data = try? Data(contentsOf: directory.appending(path: name))
            else { continue }
            all[person] = data
        }
        return all
    }

    public func savePublished(
        _ jpeg: Data, for person: ParticipantID, _ kind: Published, attachment: AttachmentID
    ) throws {
        try removePublished(for: person, kind)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory
            .appending(path: Self.name(for: person) + kind.infix + attachment.rawValue.uuidString)
            .appendingPathExtension("jpg")
        try jpeg.write(to: url, options: .atomic)
    }

    public func removePublished(for person: ParticipantID, _ kind: Published) throws {
        for url in urls(for: person, kind) { try FileManager.default.removeItem(at: url) }
    }

    public func sharedAttachment(for person: ParticipantID) -> AttachmentID? {
        publishedAttachment(for: person, .rooms)
    }
    public func loadShared(for person: ParticipantID) -> Data? { loadPublished(for: person, .rooms) }
    public func loadAllShared() -> [ParticipantID: Data] { loadAllPublished(.rooms) }
    public func saveShared(_ jpeg: Data, for person: ParticipantID, attachment: AttachmentID) throws {
        try savePublished(jpeg, for: person, .rooms, attachment: attachment)
    }
    public func removeShared(for person: ParticipantID) throws { try removePublished(for: person, .rooms) }

    public func loadOutpost(for person: ParticipantID) -> Data? {
        loadPublished(for: person, .outpost)
    }

    public func faceForABanner(from person: ParticipantID, aboutAPost: Bool) -> Data? {
        if aboutAPost, let wall = loadOutpost(for: person) { return wall }
        return load(for: person) ?? loadShared(for: person) ?? loadOutpost(for: person)
    }

    public func removeAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}
