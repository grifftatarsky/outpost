import CarpenterKit
import CarpenterMedia
import PhotosUI
import SwiftUI

// MARK: Writing, staging and sending

extension ConversationView {
    private func send() {
        let outgoing = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = staged
        let steps = CompositionPlan.steps(text: outgoing, itemCount: items.count)
        guard !steps.isEmpty else { return }

        if items.contains(where: { $0.needsTrim(limit: VideoPreparer.maximumDuration) }) {
            problem = String(
                localized: "Trim the video to a minute before sending.", bundle: .module,
                comment: "Send was tapped with a clip over the limit in the composer")
            failures += 1
            return
        }

        draft = ""
        staged = []
        sent += 1
        problem = nil

        Task {
            for step in steps {
                let reason: String?
                switch step {
                case .text(let words):
                    reason = await onSend(words)
                case .media(let index, let caption):
                    guard let onAttach else { return }
                    let item = items[index]
                    sending.append(item.kind)
                    reason = await onAttach(item.picked, caption)
                    if let position = sending.firstIndex(of: item.kind) { sending.remove(at: position) }
                }
                guard let reason else { continue }
                if draft.isEmpty { draft = outgoing }
                if staged.isEmpty { staged = items }
                problem = reason
                failures += 1
                return
            }
        }
    }

    private func stage(_ item: PhotosPickerItem) async {
        let isClip = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        problem = nil

        let picked: PickedMedia?
        if isClip {
            picked = (try? await item.loadTransferable(type: PickedClip.self)).map { .video($0.url) }
        } else {
            picked = (try? await item.loadTransferable(type: Data.self)).map { .image($0) }
        }
        guard let picked else {
            problem = String(
                localized: "That could not be read from your library.", bundle: .module,
                comment: "The picker handed back something that would not load")
            failures += 1
            return
        }
        await stage(picked)
    }

    var acceptsDrops: Bool {
        onAttach != nil && standing == .present && !soloCheck.closesTheComposer
    }

    func stageDropped(_ items: [PickedMedia]) {
        problem = nil
        Diagnostics.sync.notice("media: \(items.count, privacy: .public) item(s) dropped on the composer")
        Task { for item in items.prefix(10) { await stage(item) } }
    }

    private func stage(_ picked: PickedMedia) async {
        switch picked {
        case .image(let data):
            let thumbnail = await Task.detached(priority: .userInitiated) {
                (try? ImagePreparer.thumbnail(data, edge: 240)).map(DecodedImage.init)
            }.value
            staged.append(StagedAttachment(picked: picked, kind: .image, thumbnail: thumbnail))
        case .video(let url):
            let poster = await MediaLoader.poster(of: url)
            let duration = try? await VideoPreparer.duration(of: url)
            #if os(iOS)
                Diagnostics.sync.notice(
                    """
                    media: staged a clip of \(duration.map { Int($0) } ?? -1, privacy: .public)s; \
                    the system trimmer \(VideoTrimmerView.canTrim(url) ? "can" : "cannot", privacy: .public) edit it
                    """)
            #endif
            staged.append(
                StagedAttachment(picked: picked, kind: .video, thumbnail: poster, duration: duration))
        }
    }

    var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let partnerFocus {
                HStack(spacing: 6) {
                    Image(systemName: "moon.fill")
                    (partnerFocus.message.map { Text(verbatim: $0) } ?? Text("Do Not Disturb", bundle: .module))
                        .lineLimit(1)
                }
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .transition(.opacity)  // cross-fade only
                .accessibilityElement(children: .combine)
            }
            if !sending.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    (sending.contains(.video)
                        ? Text("Sending video…", bundle: .module)
                        : Text("Sending photo…", bundle: .module))
                        .font(CarpenterFont.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
                .padding(.horizontal, 12)
                .transition(.opacity)
            }
            if let cannotSend = notGoneHelp.reason {
                Label {
                    Text(verbatim: cannotSend)
                } icon: {
                    Image(systemName: "exclamationmark.icloud")
                        .foregroundStyle(palette.notGone)
                }
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, 12)
                .transition(.opacity)
            }
            if let problem {
                Text(problem)
                    .font(CarpenterFont.footnote)
                    .foregroundStyle(palette.accentColor)
                    .padding(.horizontal, 12)
                    .transition(.opacity)
            }
            composerRow
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: problem)
        .haptic(.failure, trigger: failures)
        .sizedSheet(isPresented: $explainingPhotos) {
            PermissionExplainerView(
                .photos,
                onContinue: {
                    photosExplained = true
                    pickingPhotos = true
                },
                onDecline: { photosExplained = true })
        }
        .photosPicker(
            isPresented: $pickingPhotos, selection: $picked, maxSelectionCount: 10,
            matching: .any(of: [.images, .videos]))
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Diagnostics.sync.notice(
                "media: the picker handed back \(items.count, privacy: .public) photo(s)")
            picked = []
            Task { for item in items { await stage(item) } }
        }
    }

    private var composerRow: some View {
        GlassEffectContainer(spacing: CarpenterMetrics.composerSpacing) {
            composerControls
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var plus: some View {
        Image(systemName: "plus")
            .font(.body.weight(.medium))
            .foregroundStyle(palette.secondaryText)
            .frame(
                width: CarpenterMetrics.composerControlHeight,
                height: CarpenterMetrics.composerControlHeight)
    }

    private var composerControls: some View {
        HStack(alignment: .bottom, spacing: CarpenterMetrics.composerSpacing) {
            if onAttach != nil {
                Button {
                    Diagnostics.sync.notice("media: asking for the photo picker")
                    if photosExplained { pickingPhotos = true } else { explainingPhotos = true }
                } label: {
                    plus
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .tappable()
                .accessibilityLabel(Text("Add a photo", bundle: .module))
            } else {
                Button {
                    // intentionally empty
                } label: {
                    plus
                }
                .buttonStyle(.plain)
                .disabled(true)
                .glassEffect(.regular, in: Circle())
                .tappable()
                .accessibilityLabel(Text("Add a photo", bundle: .module))
            }

            VStack(alignment: .leading, spacing: 0) {
            if !staged.isEmpty { stagedStrip }
            HStack(alignment: .bottom, spacing: 4) {
                TextField(text: $draft, selection: $draftSelection, axis: .vertical) {
                    Text("Message", bundle: .module)
                }
                .textFieldStyle(.plain)
                .font(CarpenterFont.bubble)
                .foregroundStyle(palette.primaryText)
                .padding(.leading, 14)
                .padding(.vertical, 8)
                .lineLimit(1...6)
                .onSubmit(send)
                .shiftReturnBreaksLine($draft, selection: $draftSelection)
                .onChange(of: draft) { old, new in
                    guard acceptsDrops, let files = DroppedPaths.files(insertedBetween: old, and: new) else {
                        return
                    }
                    draft = old
                    stageDropped(files.compactMap(DroppedPaths.media))
                }

                if hasSomethingToSend {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(palette.accentFill, in: .circle)
                    }
                    .accessibilityLabel(Text("Send", bundle: .module))
                    .padding(.trailing, 4)
                    .padding(.bottom, 4)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            }
            .glassEffect(
                .regular,
                in: RoundedRectangle(
                    cornerRadius: CarpenterMetrics.composerFieldRadius, style: .continuous))
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: hasSomethingToSend)
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: staged.count)
        }
    }

    private var hasSomethingToSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !staged.isEmpty
    }

    private var stagedStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(staged) { item in
                    stagedTile(item)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
        }
        .scrollIndicators(.hidden)
        .presentingTrimmer($trimming, maximumDuration: VideoPreparer.maximumDuration) { item, url in
            trimmed(item, to: url)
        }
    }

    private func stagedTile(_ item: StagedAttachment) -> some View {
        let needsTrim = item.needsTrim(limit: VideoPreparer.maximumDuration)
        return ZStack(alignment: .topTrailing) {
            Group {
                if let thumbnail = item.thumbnail {
                    thumbnail.image.resizable().scaledToFill()
                } else {
                    palette.neutralFill
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if item.kind == .video, let duration = item.duration {
                    HStack(spacing: 3) {
                        if needsTrim { Image(systemName: "scissors") }
                        Text(MediaBubbleView.length(duration))
                    }
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(needsTrim ? palette.destructiveFill : Color.black.opacity(CarpenterMetrics.mediaOverlayDimming), in: Capsule())
                    .padding(4)
                }
            }
            .contentShape(.rect)
            .onTapGesture { if needsTrim { trimming = item } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tileLabel(item, needsTrim: needsTrim))
            .accessibilityAddTraits(needsTrim ? [.isImage, .isButton] : [.isImage])

            Button {
                staged.removeAll { $0.id == item.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(palette.primaryText)
                    .frame(width: 22, height: 22)
                    .background(palette.neutralFillStrong, in: Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
            .accessibilityLabel(Text("Remove", bundle: .module))
        }
    }

    private func tileLabel(_ item: StagedAttachment, needsTrim: Bool) -> Text {
        switch (item.kind, needsTrim) {
        case (.image, _):
            Text("Photo, ready to send", bundle: .module)
        case (.video, false):
            Text("Video, \(MediaBubbleView.length(item.duration ?? 0)), ready to send", bundle: .module)
        case (.video, true):
            Text("Video, \(MediaBubbleView.length(item.duration ?? 0)), longer than a minute. Trim it to send.", bundle: .module)
        }
    }

    private func trimmed(_ item: StagedAttachment, to url: URL) {
        guard let index = staged.firstIndex(where: { $0.id == item.id }) else { return }
        if case .video(let original) = item.picked { try? FileManager.default.removeItem(at: original) }
        staged[index].picked = .video(url)
        Task {
            staged[index].duration = try? await VideoPreparer.duration(of: url)
        }
    }
}
