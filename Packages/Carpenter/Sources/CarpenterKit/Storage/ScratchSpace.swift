import Foundation

public struct ScratchSpace: Sendable {
    public static let shared = ScratchSpace(
        directory: URL.temporaryDirectory.appending(path: "scratch", directoryHint: .isDirectory),
        protection: .main)

    public let directory: URL
    private let dial: ProtectionDial

    public init(directory: URL, protection dial: ProtectionDial) {
        self.directory = directory
        self.dial = dial
    }

    public func newFile(_ stem: String, extension ext: String) throws -> ScratchFile {
        let fileManager = FileManager.default
        let attributes = dial.current.fileAttributes
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: attributes)
        try fileManager.setAttributes(attributes, ofItemAtPath: directory.path)
        let name = ext.isEmpty ? "\(stem)-\(UUID().uuidString)" : "\(stem)-\(UUID().uuidString).\(ext)"
        return ScratchFile(directory.appending(path: name), protection: dial)
    }

    public func empty() throws {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
        }
    }
}

public final class ScratchFile: Hashable, Sendable {
    public let url: URL
    private let dial: ProtectionDial

    init(_ url: URL, protection dial: ProtectionDial) {
        self.url = url
        self.dial = dial
    }

    public func protect() throws {
        try FileManager.default.setAttributes(dial.current.fileAttributes, ofItemAtPath: url.path)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    public static func == (lhs: ScratchFile, rhs: ScratchFile) -> Bool { lhs === rhs }

    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
