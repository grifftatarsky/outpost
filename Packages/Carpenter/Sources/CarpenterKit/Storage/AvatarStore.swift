import Foundation

public struct FileAvatarStore: Sendable {
    private let url: URL
    private let dial: ProtectionDial

    public init(
        directory: URL, name: String = StorageLocation.avatarName, protection dial: ProtectionDial = ProtectionDial()
    ) {
        url = directory.appending(path: name)
        self.dial = dial
    }

    public func load() -> Data? {
        try? Data(contentsOf: url)
    }

    public func save(_ jpeg: Data) throws {
        try ProtectedFiles.write(jpeg, to: url, as: dial.current)
    }

    public func remove() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

public struct PersonAvatarStore: Sendable {
    private let directory: URL
    private let dial: ProtectionDial

    public init(directory: URL, protection dial: ProtectionDial = ProtectionDial()) {
        self.directory = directory.appending(path: StorageLocation.personAvatarsName)
        self.dial = dial
    }

    private func url(for person: ParticipantID) -> URL {
        directory.appending(path: Self.name(for: person)).appendingPathExtension("jpg")
    }

    static func name(for person: ParticipantID) -> String {
        person.rawValue.lowercaseHex
    }

    static func person(named name: String) -> ParticipantID? {
        Data(lowercaseHex: name).map { ParticipantID(rawValue: $0) }
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
        try ProtectedFiles.write(jpeg, to: url(for: person), as: dial.current)
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
        try ProtectedFiles.write(jpeg, to: url, as: dial.current)
    }

    public func removePublished(for person: ParticipantID, _ kind: Published) throws {
        for url in urls(for: person, kind) { try FileManager.default.removeItem(at: url) }
    }

    public func loadShared(for person: ParticipantID) -> Data? { loadPublished(for: person, .rooms) }

    public func loadOutpost(for person: ParticipantID) -> Data? {
        loadPublished(for: person, .outpost)
    }

    public func removeAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}
