import CarpenterKit
import CarpenterMedia
import PhotosUI
import SwiftUI

public struct PostComposerView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var writing: Bool
    @AppStorage("explained.photos") private var photosExplained = false

    @State private var rich = AttributedString()
    @State private var richSelection = AttributedTextSelection()

    @State private var draft = ""
    @State private var selection: TextSelection?
    @State private var showsMarkers = false
    @State private var posted = 0

    @State private var photos: [StagedPhoto] = []
    @State private var explainingPhotos = false
    @State private var pickingPhoto = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var posting = false
    @State private var problem: String?

    private let onPost: (String) async -> String?
    private let onAttach: (([PickedMedia], String?) async -> String?)?

    public init(
        onAttach: (([PickedMedia], String?) async -> String?)? = nil,
        onPost: @escaping (String) async -> String?
    ) {
        self.onAttach = onAttach
        self.onPost = onPost
    }

    private var outgoing: String {
        showsMarkers ? draft : PostFormatting.text(from: FormattedText.runs(of: rich))
    }

    private var hasWords: Bool {
        !outgoing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isEmpty: Bool { !hasWords && photos.isEmpty }

    private var isFull: Bool { photos.count >= MediaBody.galleryLimit }

    private struct StagedPhoto: Identifiable {
        let id = UUID()
        let picked: PickedMedia
        let kind: MediaKind
        let thumbnail: DecodedImage?
        var duration: TimeInterval?
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if showsMarkers {
                        TextEditor(text: $draft, selection: $selection)
                            .font(CarpenterFont.postBody)
                            .foregroundStyle(palette.primaryText)
                    } else {
                        TextEditor(text: $rich, selection: $richSelection)
                            .font(CarpenterFont.postBody)
                            .foregroundStyle(palette.primaryText)
                    }
                }
                .scrollContentBackground(.hidden)
                #if os(macOS)
                    .background(MediaPasteKey(isActive: writing && onAttach != nil, onPaste: stageDropped))
                #endif
                .padding(.horizontal, CarpenterMetrics.screenMargin - 5)
                .padding(.top, 8)
                .focused($writing)
                .doneAboveKeyboard($writing)
                .overlay(alignment: .topLeading) {
                    if !hasWords {
                        Text("Say something to your Outpost", bundle: .module)
                            .font(CarpenterFont.postBody)
                            .foregroundStyle(palette.tertiaryText)
                            .padding(.horizontal, CarpenterMetrics.screenMargin)
                            .padding(.top, 16)
                            .allowsHitTesting(false)
                    }
                }

                if !photos.isEmpty {
                    stagedStrip
                }
                if let problem {
                    Text(verbatim: problem)
                        .font(CarpenterFont.footnote)
                        .foregroundStyle(palette.destructive)
                        .padding(.horizontal, CarpenterMetrics.screenMargin)
                        .padding(.bottom, 8)
                }

                formatBar
            }
            .background(palette.background.ignoresSafeArea())
            .acceptsDroppedMedia(onAttach != nil, onDrop: stageDropped)
            .onChange(of: draft) { old, new in
                guard onAttach != nil, let files = DroppedPaths.filesArriving(between: old, and: new) else {
                    return
                }
                draft = old
                stageDropped(files.compactMap(DroppedPaths.media))
            }
            .onChange(of: rich) { old, new in
                guard onAttach != nil,
                    let files = DroppedPaths.filesArriving(
                        between: String(old.characters), and: String(new.characters))
                else { return }
                rich = old
                stageDropped(files.compactMap(DroppedPaths.media))
            }
            .keepsDraft(outgoing, at: .newPost) { kept in
                rich = FormattedText.attributed(PostFormatting.runs(in: kept), palette: palette)
                draft = kept
            }
            .navigationTitle(Text("New post", bundle: .module))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        post()
                    } label: {
                        if posting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Post", bundle: .module).bold()
                        }
                    }
                    .disabled(isEmpty || posting)
                }
            }
            .sensoryFeedback(.success, trigger: posted)
            .task { writing = true }
            .sizedSheet(isPresented: $explainingPhotos) {
                PermissionExplainerView(
                    .photos,
                    onContinue: {
                        photosExplained = true
                        pickingPhoto = true
                    },
                    onDecline: { photosExplained = true })
            }
            .photosPicker(
                isPresented: $pickingPhoto, selection: $picked,
                maxSelectionCount: Swift.max(1, MediaBody.galleryLimit - photos.count),
                matching: .any(of: [.images, .videos]))
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                picked = []
                problem = nil
                Task {
                    var refused = 0
                    for item in items {
                        if isFull {
                            refused += 1
                        } else {
                            await stage(item)
                        }
                    }
                    if refused > 0 {
                        let over = Self.overflow(refused)
                        problem = problem.map { $0 + " " + over } ?? over
                    }
                }
            }
        }
    }

    private func post() {
        let body = outgoing
        if !photos.isEmpty, let onAttach {
            posting = true
            problem = nil
            let picked = photos.map(\.picked)
            Task {
                let failure = await onAttach(picked, hasWords ? body : nil)
                posting = false
                if let failure {
                    problem = failure
                } else {
                    posted += 1
                    draft = ""
                    rich = AttributedString()
                    dismiss()
                }
            }
        } else {
            posting = true
            problem = nil
            Task {
                let failure = await onPost(body)
                posting = false
                if let failure {
                    problem = failure
                } else {
                    posted += 1
                    draft = ""
                    rich = AttributedString()
                    dismiss()
                }
            }
        }
    }

    private func stage(_ item: PhotosPickerItem) async {
        guard !isFull else { return }
        let isClip = item.supportedContentTypes.contains { $0.conforms(to: .movie) }

        if isClip {
            guard let clip = try? await item.loadTransferable(type: PickedClip.self) else {
                problem = Self.unreadable
                return
            }
            await stage(.video(clip.url))
            return
        }

        guard let data = try? await item.loadTransferable(type: Data.self) else {
            problem = Self.unreadable
            return
        }
        await stage(.image(data))
    }

    private func stage(_ picked: PickedMedia) async {
        guard !isFull else { return }
        switch picked {
        case .video(let url):
            let poster = await MediaLoader.poster(of: url)
            let seconds = try? await VideoPreparer.duration(of: url)
            photos.append(StagedPhoto(picked: picked, kind: .video, thumbnail: poster, duration: seconds))
        case .image(let data):
            let thumbnail = await Task.detached(priority: .userInitiated) {
                (try? ImagePreparer.thumbnail(data, edge: 240)).map(DecodedImage.init)
            }.value
            photos.append(StagedPhoto(picked: picked, kind: .image, thumbnail: thumbnail))
        }
    }

    private func stageDropped(_ items: [PickedMedia]) {
        problem = nil
        Task {
            var refused = 0
            for item in items {
                if isFull {
                    refused += 1
                } else {
                    await stage(item)
                }
            }
            if refused > 0 { problem = Self.overflow(refused) }
        }
    }

    private static let unreadable = String(
        localized: "That could not be read from your library.", bundle: .module,
        comment: "The picker handed back something that would not load")

    private static func overflow(_ refused: Int) -> String {
        String(
            localized:
                "\(refused) more did not fit: a post carries \(MediaBody.galleryLimit).",
            bundle: .module, comment: "More pictures were picked than a post can carry")
    }

    private var stagedStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(photos) { item in
                    stagedTile(item)
                }
            }
            .padding(.horizontal, CarpenterMetrics.screenMargin)
        }
        .scrollIndicators(.hidden)
        .padding(.bottom, 8)
    }

    private func stagedTile(_ item: StagedPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumbnail = item.thumbnail {
                    thumbnail.image.resizable().scaledToFill()
                } else {
                    palette.neutralFill
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if item.kind == .video, let duration = item.duration {
                    Text(MediaPictureView.length(duration))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(CarpenterMetrics.mediaOverlayDimming), in: Capsule())
                        .padding(4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                item.kind == .video
                    ? Text("Clip to post", bundle: .module)
                    : Text("Photo to post", bundle: .module))
            .accessibilityAddTraits(.isImage)

            Button {
                photos.removeAll { $0.id == item.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel(Text("Remove it", bundle: .module))
        }
    }

    private var formatBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    if photosExplained { pickingPhoto = true } else { explainingPhotos = true }
                } label: {
                    Image(systemName: "photo")
                        .font(.body)
                        .frame(width: 38, height: 34)
                        .background(
                            palette.neutralFill,
                            in: .rect(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(onAttach != nil ? palette.primaryText : palette.quaternaryText)
                .disabled(onAttach == nil || isFull)
                .accessibilityLabel(Text("Add a photo", bundle: .module))

                emphasis("bold", "**", .bold, label: Text("Bold", bundle: .module))
                emphasis("italic", "*", .italic, label: Text("Italic", bundle: .module))
                emphasis("underline", "__", .underline, label: Text("Underline", bundle: .module))

                Spacer()

                Button { toggleMarkers() } label: {
                    Text("MD", bundle: .module)
                        .font(CarpenterFont.caption.weight(.semibold))
                        .frame(width: 38, height: 34)
                        .background(
                            showsMarkers ? palette.accentTint : palette.neutralFill,
                            in: .rect(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(showsMarkers ? palette.accentColor : palette.primaryText)
                .accessibilityLabel(Text("Show formatting marks", bundle: .module))
                .accessibilityAddTraits(showsMarkers ? [.isSelected] : [])

                if writing {
                    Button { writing = false } label: {
                        Text("Done", bundle: .module)
                            .font(CarpenterFont.button)
                            .frame(height: 34)
                            .padding(.horizontal, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.accentColor)
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: writing)
            .padding(.horizontal, CarpenterMetrics.screenMargin)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func emphasis(
        _ symbol: String, _ marker: String, _ trait: PostFormatting.Traits, label: Text
    ) -> some View {
        Button {
            if showsMarkers { wrapSelection(with: marker) } else { apply(trait) }
        } label: {
            Image(systemName: symbol)
                .font(.body)
                .frame(width: 38, height: 34)
                .background(
                    palette.neutralFill,
                    in: .rect(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(hasSelection ? palette.primaryText : palette.quaternaryText)
        .disabled(!hasSelection)
        .accessibilityLabel(label)
    }

    private func apply(_ trait: PostFormatting.Traits) {
        let runs = FormattedText.runs(of: rich)
        guard case .ranges(let selected) = richSelection.indices(in: rich) else { return }

        let offsets = selected.ranges.map { range in
            rich.characters.distance(from: rich.startIndex, to: range.lowerBound)
                ..< rich.characters.distance(from: rich.startIndex, to: range.upperBound)
        }

        guard let span = offsets.first, !span.isEmpty else { return }

        let updated = offsets.reduce(runs) { PostFormatting.toggling(trait, in: $0, over: $1) }
        rich = FormattedText.attributed(updated, palette: palette)

        let lower = rich.characters.index(rich.startIndex, offsetBy: span.lowerBound)
        let upper = rich.characters.index(rich.startIndex, offsetBy: span.upperBound)
        richSelection = AttributedTextSelection(range: lower..<upper)
    }

    private var hasSelection: Bool {
        if showsMarkers {
            if case .selection(let range)? = selection?.indices { return !range.isEmpty }
            return false
        }
        guard case .ranges(let selected) = richSelection.indices(in: rich) else { return false }
        return selected.ranges.contains { $0.lowerBound < $0.upperBound }
    }

    private func toggleMarkers() {
        if showsMarkers {
            rich = FormattedText.attributed(PostFormatting.runs(in: draft), palette: palette)
        } else {
            draft = PostFormatting.text(from: FormattedText.runs(of: rich))
        }
        selection = nil
        richSelection = AttributedTextSelection()
        showsMarkers.toggle()
        Task { writing = true }
    }

    private func wrapSelection(with marker: String) {
        guard case .selection(let range)? = selection?.indices, !range.isEmpty,
            range.lowerBound >= draft.startIndex, range.upperBound <= draft.endIndex
        else {
            draft.append(marker + marker)
            return
        }

        let selected = String(draft[range])
        draft.replaceSubrange(range, with: marker + selected + marker)
    }
}

#Preview("New post") {
    PostComposerView { _ in nil }
        .themed(.default)
}
