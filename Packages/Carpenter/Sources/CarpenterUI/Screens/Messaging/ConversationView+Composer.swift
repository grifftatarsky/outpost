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

        draft = ""
        staged = []
        sent += 1
        problem = nil

        Task {
            for step in steps {
                let reason: String?
                let unsent: ArraySlice<StagedAttachment>
                switch step {
                case .text(let words):
                    reason = await onSend(words)
                    unsent = []
                case .media(let index, let caption):
                    guard let onAttach else { return }
                    let item = items[index]
                    sending.append(item.kind)
                    if item.picked.isMadeToFit { fittingNow += 1 }
                    reason = await onAttach(item.picked, caption)
                    if item.picked.isMadeToFit { fittingNow -= 1 }
                    if let position = sending.firstIndex(of: item.kind) { sending.remove(at: position) }
                    unsent = items[index...]
                }
                guard let reason else { continue }
                if draft.isEmpty { draft = outgoing }
                if staged.isEmpty { staged = Array(unsent) }
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
        // COPY BEGIN 0790e13e [NEEDS HUMAN REVIEW]
        guard let picked else {
            problem = String(
                localized: "Photo or video cannot be read", bundle: .module,
                comment: "The picker handed back something that would not load")
            failures += 1
            return
        }
        // COPY END 0790e13e

        switch picked {
        case .image(let data):
            let thumbnail = await Task.detached(priority: .userInitiated) {
                (try? ImagePreparer.thumbnail(data, edge: 240)).map(DecodedImage.init)
            }.value
            staged.append(StagedAttachment(picked: picked, kind: .image, thumbnail: thumbnail))
        case .video(let url), .videoToFit(let url):
            let poster = await MediaLoader.poster(of: url)
            let duration = try? await VideoPreparer.duration(of: url)
            Diagnostics.sync.notice(
                "media: staged a clip of \(duration.map { Int($0) } ?? -1, privacy: .public)s")
            staged.append(
                StagedAttachment(
                    picked: picked, kind: .video, thumbnail: poster, duration: duration,
                    tooLarge: VideoPreparer.sizeIfTooLarge(url)))
        }
    }

    private var clipTooLarge: Int? {
        staged.filter { !$0.picked.isMadeToFit }.compactMap(\.tooLarge).max()
    }

    @ViewBuilder private var fitOffer: some View {
        // COPY BEGIN 819afbbd [NEEDS HUMAN REVIEW]
        if let bytes = clipTooLarge {
            let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("This video is \(size). Videos up to 287 MB can be sent.", bundle: .module)
                    .foregroundStyle(palette.secondaryText)
                Spacer(minLength: 0)
                Button {
                    for index in staged.indices where staged[index].tooLarge != nil {
                        staged[index].picked = staged[index].picked.madeToFit
                    }
                } label: {
                    Text("Make it fit", bundle: .module).bold()
                }
                .buttonStyle(.borderless)
            }
            .font(CarpenterFont.footnote)
            .padding(.horizontal, 12)
            .transition(.opacity)
        }
        // COPY END 819afbbd
        // COPY BEGIN e49eda14 [NEEDS HUMAN REVIEW]
        if fittingNow > 0 {
            Text("Making the video smaller so it fits…", bundle: .module)
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, 12)
                .transition(.opacity)
        } else if clipTooLarge == nil, staged.contains(where: \.picked.isMadeToFit) {
            Text("It will be made smaller to fit when it is sent.", bundle: .module)
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, 12)
                .transition(.opacity)
        }
        // COPY END e49eda14
    }

    var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            // COPY BEGIN 78c653db [NEEDS HUMAN REVIEW]
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
            // COPY END 78c653db
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
            fitOffer
            composerRow
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: problem)
        .haptic(.failure, trigger: failures)
        .sheet(isPresented: $explainingPhotos) {
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
        heldableControls
            .disabled(iCloudHold)
            .opacity(iCloudHold ? 0.5 : 1)
    }

    private var heldableControls: some View {
        HStack(alignment: .bottom, spacing: CarpenterMetrics.composerSpacing) {
            if onAttach != nil {
                // COPY BEGIN 814da02a [NEEDS HUMAN REVIEW]
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
                // COPY END 814da02a
            }

            VStack(alignment: .leading, spacing: 0) {
            if !staged.isEmpty { stagedStrip }
            HStack(alignment: .bottom, spacing: 4) {
                // COPY BEGIN 74e6a94a [NEEDS HUMAN REVIEW]
                TextField(text: $draft, axis: .vertical) {
                    Text("Message", bundle: .module)
                }
                .textFieldStyle(.plain)
                .font(CarpenterFont.bubble)
                .foregroundStyle(palette.primaryText)
                .padding(.leading, 14)
                .padding(.vertical, 8)
                .lineLimit(1...6)
                .onSubmit(send)
                // COPY END 74e6a94a

                // COPY BEGIN 6d2d2146 [NEEDS HUMAN REVIEW]
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
                // COPY END 6d2d2146
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
    }

    private func stagedTile(_ item: StagedAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
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
                    Text(MediaBubbleView.length(duration))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(CarpenterMetrics.mediaOverlayDimming), in: Capsule())
                    .padding(4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tileLabel(item))
            .accessibilityAddTraits(.isImage)

            // COPY BEGIN 402dc267 [NEEDS HUMAN REVIEW]
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
            // COPY END 402dc267
        }
    }

    // COPY BEGIN 3034cc7f [NEEDS HUMAN REVIEW]
    private func tileLabel(_ item: StagedAttachment) -> Text {
        switch item.kind {
        case .image:
            Text("Photo, ready to send", bundle: .module)
        case .video:
            Text("Video, \(MediaBubbleView.length(item.duration ?? 0)), ready to send", bundle: .module)
        }
    }
    // COPY END 3034cc7f
}
