import CarpenterKit
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct DroppedMedia: Transferable {
    let picked: PickedMedia

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let copy = FileManager.default.temporaryDirectory
                .appending(path: "dropped-\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return DroppedMedia(picked: .video(copy))
        }
        DataRepresentation(importedContentType: .image) { data in
            DroppedMedia(picked: .image(data))
        }
    }
}

struct MediaDropTarget: ViewModifier {
    @Environment(\.palette) private var palette
    @State private var isTargeted = false

    let isEnabled: Bool
    let onDrop: ([PickedMedia]) -> Void

    func body(content: Content) -> some View {
        content
            .dropDestination(for: DroppedMedia.self) { items, _ in
                guard isEnabled, !items.isEmpty else { return false }
                onDrop(items.map(\.picked))
                return true
            } isTargeted: { targeted in
                isTargeted = isEnabled && targeted
            }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(palette.accentColor, lineWidth: 3)
                        .padding(3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

extension View {
    func acceptsDroppedMedia(_ isEnabled: Bool, onDrop: @escaping ([PickedMedia]) -> Void) -> some View {
        modifier(MediaDropTarget(isEnabled: isEnabled, onDrop: onDrop))
    }
}

enum DroppedPaths {
    static func files(insertedBetween old: String, and new: String) -> [URL]? {
        guard new.count > old.count else { return nil }
        let head = old.commonPrefix(with: new).count
        let oldTail = old.dropFirst(head)
        let newTail = new.dropFirst(head)
        var tail = 0
        while tail < oldTail.count, tail < newTail.count,
            oldTail[oldTail.index(oldTail.endIndex, offsetBy: -tail - 1)]
                == newTail[newTail.index(newTail.endIndex, offsetBy: -tail - 1)]
        {
            tail += 1
        }
        let inserted = newTail.dropLast(tail)
        let lines = inserted.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        var files: [URL] = []
        for line in lines {
            guard let url = fileURL(line) else { return nil }
            files.append(url)
        }
        return files
    }

    private static func fileURL(_ text: String) -> URL? {
        let url: URL?
        if text.hasPrefix("file://") {
            url = URL(string: text)
        } else if text.hasPrefix("/") {
            url = URL(fileURLWithPath: text)
        } else {
            url = nil
        }
        guard let url, url.isFileURL, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
            let type = UTType(filenameExtension: url.pathExtension),
            type.conforms(to: .image) || type.conforms(to: .movie)
        else { return nil }
        return url
    }

    static func media(_ url: URL) -> PickedMedia? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .movie) {
            let copy = FileManager.default.temporaryDirectory
                .appending(path: "dropped-\(UUID().uuidString).\(url.pathExtension)")
            guard (try? FileManager.default.copyItem(at: url, to: copy)) != nil else { return nil }
            return .video(copy)
        }
        return (try? Data(contentsOf: url)).map { .image($0) }
    }
}
