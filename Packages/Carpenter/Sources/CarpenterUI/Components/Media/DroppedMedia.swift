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
        guard let lines = insertedLines(between: old, and: new) else { return nil }
        var files: [URL] = []
        for line in lines {
            guard let url = fileURL(line) else { return nil }
            files.append(url)
        }
        return files
    }

    static func insertedLines(between old: String, and new: String) -> [String]? {
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
        let lines = newTail.dropLast(tail).split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines
    }

    static func isMedia(_ url: URL) -> Bool {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return false
        }
        return looksLikeMedia(url.pathExtension)
    }

    static func looksLikeMedia(_ fileExtension: String) -> Bool {
        guard let type = UTType(filenameExtension: fileExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .movie)
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
        guard let url, isMedia(url) else { return nil }
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

    static func filesArriving(between old: String, and new: String) -> [URL]? {
        if let files = files(insertedBetween: old, and: new) { return files }
        #if os(macOS)
            guard let names = insertedLines(between: old, and: new),
                names.allSatisfy({ !$0.contains("/") && looksLikeMedia(($0 as NSString).pathExtension) })
            else { return nil }
            return ClipboardMedia.files(named: names, on: .general)
        #else
            return nil
        #endif
    }
}

#if os(macOS)
    import AppKit

    final class WindowBox {
        weak var window: NSWindow?
    }

    private struct WindowHandle: NSViewRepresentable {
        let box: WindowBox

        func makeNSView(context: Context) -> NSView { Reader(box: box) }
        func updateNSView(_ view: NSView, context: Context) { box.window = view.window }

        final class Reader: NSView {
            let box: WindowBox
            init(box: WindowBox) {
                self.box = box
                super.init(frame: .zero)
            }
            required init?(coder: NSCoder) { nil }
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                box.window = window
            }
        }
    }

    struct MediaPasteKey: View {
        let isActive: Bool
        let onPaste: ([PickedMedia]) -> Void
        @State private var box = WindowBox()

        var body: some View {
            if isActive {
                Button {
                    let media = ClipboardMedia.media(on: .general)
                    if media.isEmpty {
                        let paste = #selector(NSText.paste(_:))
                        let handled = box.window?.firstResponder?.tryToPerform(paste, with: nil) ?? false
                        if !handled { NSApp.sendAction(paste, to: nil, from: nil) }
                    } else {
                        onPaste(media)
                    }
                } label: {
                    EmptyView()
                }
                .background(WindowHandle(box: box))
                .keyboardShortcut("v", modifiers: .command)
                .buttonStyle(.plain)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            }
        }
    }

    enum ClipboardMedia {
        static let imageTypes: [NSPasteboard.PasteboardType] = [
            .png, .tiff, .init("public.jpeg"), .init("public.heic"),
        ]

        static func mediaFiles(on board: NSPasteboard) -> [URL] {
            let urls = board.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            return urls.filter(DroppedPaths.isMedia)
        }

        static func media(on board: NSPasteboard) -> [PickedMedia] {
            let files = mediaFiles(on: board)
            if !files.isEmpty { return files.compactMap(DroppedPaths.media) }
            if let words = board.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !words.isEmpty, !isJustALink(words)
            {
                return []
            }
            for type in imageTypes {
                if let data = board.data(forType: type) { return [.image(data)] }
            }
            return []
        }

        private static func isJustALink(_ words: String) -> Bool {
            guard !words.contains(where: \.isWhitespace), let url = URL(string: words) else { return false }
            return url.scheme == "http" || url.scheme == "https"
        }

        static func files(named names: [String], on board: NSPasteboard) -> [URL]? {
            let files = mediaFiles(on: board)
            let matched = names.compactMap { name in files.first { $0.lastPathComponent == name } }
            return matched.count == names.count && !matched.isEmpty ? matched : nil
        }
    }
#endif
