import CarpenterKit
import CarpenterMedia
import PhotosUI
import SwiftUI

public struct OutpostSettingsView: View {
    @Environment(\.palette) private var palette

    private let settings: OutpostSettings

    @State private var draft: String
    @State private var name: String
    @State private var picked: PhotosPickerItem?
    @State private var choosingFace = false
    @State private var pickedPicture: PhotosPickerItem?
    @State private var pendingBlurb: Task<Void, Never>?
    @State private var blurbProblem: String?
    @State private var pendingName: Task<Void, Never>?

    public init(_ settings: OutpostSettings) {
        self.settings = settings
        _draft = State(initialValue: settings.blurb)
        _name = State(initialValue: settings.persona.name ?? "")
    }

    private var persona: AnonPersona { settings.persona }
    private var consent: OutpostConsent? { settings.consent }
    private var hasCustomFace: Bool { settings.hasCustomFace }
    private var onBlurb: (String) async -> String? { settings.onBlurb }
    private var onPersona: (AnonPersona) async -> Void { settings.onPersona }
    private var onConsent: (OutpostConsent) async -> Void { settings.onConsent }
    private var onReview: (Bool) async -> Void { settings.onReview }
    private var onFace: ((PickedAvatar?) async -> Void)? { settings.onFace }
    private var onPicture: ((PickedAvatar?) async -> Void)? { settings.onPicture }

    public var body: some View {
        List {
            Section {
                TextField(
                    text: $draft, axis: .vertical
                ) {
                    // COPY BEGIN 4a9380b0 [NEEDS HUMAN REVIEW]
                    Text("A line about you", bundle: .module)
                    // COPY END 4a9380b0
                }
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .foregroundStyle(palette.primaryText)
                .onChange(of: draft) { _, typed in
                    if typed.count > MemberProfileBody.blurbLimit {
                        draft = String(typed.prefix(MemberProfileBody.blurbLimit))
                    }
                }
                .submitLabel(.done)
                .onSubmit { saveBlurb(now: true) }
            } header: {
                // COPY BEGIN f082e48d [NEEDS HUMAN REVIEW]
                Text("Your blurb", bundle: .module).sectionHeading()
            } footer: {
                if let blurbProblem {
                    Text(verbatim: blurbProblem).foregroundStyle(palette.destructive)
                } else {
                    Text(
                        "Sits under your name at the top of your Outpost, for anybody who can read it. A sentence or two — \(draft.count) of \(MemberProfileBody.blurbLimit).",
                        bundle: .module)
                }
                // COPY END f082e48d
            }
            .groupedRowSurface()

            picture
            stranger
            participation
        }
        .onDisappear {
            saveBlurb(now: true)
            saveName(now: true)
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(palette.background)
        // COPY BEGIN 1cdde6b2 [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("Outpost settings", bundle: .module))
        // COPY END 1cdde6b2
        .toolbarTitleDisplayMode(.inline)
        .croppingPickedPhoto($picked) { await onFace?($0) }
    }

    @ViewBuilder private var picture: some View {
        Section {
            // COPY BEGIN 13a41974 [NEEDS HUMAN REVIEW]
            SettingsToggle(
                icon: "person.crop.square.fill",
                title: Text("Show my picture", bundle: .module),
                isOn: Binding(
                    get: { settings.showsPicture },
                    set: { shows in Task { await settings.onShowsPicture(shows) } }))
            // COPY END 13a41974

            if settings.showsPicture, onPicture != nil {
                // COPY BEGIN 513788a6 [NEEDS HUMAN REVIEW]
                PhotosPicker(selection: $pickedPicture, matching: .images) {
                    SettingsRow(
                        icon: "photo.on.rectangle.angled",
                        title: Text("Use a different picture here", bundle: .module))
                }
                .buttonStyle(.plain)
                // COPY END 513788a6

                // COPY BEGIN 3f9ba109 [NEEDS HUMAN REVIEW]
                if settings.hasOwnPicture {
                    Button(role: .destructive) { Task { await onPicture?(nil) } } label: {
                        SettingsRow(
                            icon: "person.crop.circle.badge.minus", tone: .destructive,
                            title: Text("Use the picture from You", bundle: .module))
                    }
                    .tint(palette.destructive)
                }
            }
        } header: {
            Text("Your picture", bundle: .module).sectionHeading()
        } footer: {
            Text(
                "The photo on your You page, at the top of your Outpost, unless you choose a different one here. Off, your Outpost draws your initials and the rooms you are in are unchanged. Either way a reader is only ever sent a picture where Share my photo is on.",
                bundle: .module)
                // COPY END 3f9ba109
        }
        .groupedRowSurface()
        .croppingPickedPhoto($pickedPicture) { await onPicture?($0) }
    }

    @ViewBuilder private var stranger: some View {
        Section {
            VStack(spacing: 10) {
                // COPY BEGIN 8c851b5d [NEEDS HUMAN REVIEW]
                if onFace != nil {
                    Button { choosingFace = true } label: { face }
                        .buttonStyle(.plain)
                        .photosPicker(isPresented: $choosingFace, selection: $picked, matching: .images)
                        .accessibilityLabel(Text("Choose a picture for them", bundle: .module))
                } else {
                    face
                }
                // COPY END 8c851b5d
                Text(verbatim: persona.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } header: {
            // COPY BEGIN b58d985d [NEEDS HUMAN REVIEW]
            Text("People you have not met", bundle: .module).sectionHeading()
        } footer: {
            Text(
                "Anybody who comments on an Outpost you both read, but whom you have never shared a room or an Outpost with, is drawn like this — all of them as one person, so there is nothing to follow from thread to thread. This is how your own devices draw them. Nobody else sees it, and nobody is told.",
                bundle: .module)
            // COPY END b58d985d
        }
        .groupedRowSurface()

        Section {
            HStack(spacing: 12) {
                IconTile("pencil", fill: palette.tileFill(.feature))
                TextField(text: $name) {
                    Text(verbatim: AnonPersonaCopy.name(of: persona.face))
                }
                .textFieldStyle(.plain)
                .foregroundStyle(palette.primaryText)
                .onChange(of: name) { _, typed in
                    if typed.count > AnonPersona.nameLimit {
                        name = String(typed.prefix(AnonPersona.nameLimit))
                    }
                }
                .submitLabel(.done)
                .onSubmit { saveName(now: true) }
            }
            // COPY BEGIN 1a308145 [NEEDS HUMAN REVIEW]
            if hasCustomFace, let onFace {
                Button(role: .destructive) { Task { await onFace(nil) } } label: {
                    SettingsRow(
                        icon: "person.crop.circle.badge.minus", tone: .destructive,
                        title: Text("Remove picture", bundle: .module))
                }
                .tint(palette.destructive)
            }
        } header: {
            Text("What you call them", bundle: .module).sectionHeading()
        } footer: {
            Text("Leave it empty for the name that comes with the picture.", bundle: .module)
            // COPY END 1a308145
        }
        .groupedRowSurface()

        Section {
            ForEach(AnonPersona.Face.allCases, id: \.self) { face in
                ChoiceRow(
                    title: Text(verbatim: AnonPersonaCopy.name(of: face)),
                    isSelected: face == persona.face,
                    action: { Task { await onPersona(AnonPersona(face: face, name: persona.name)) } }
                ) {
                    AvatarView(initials: "", diameter: 34, symbol: face.symbol)
                }
            }
        } header: {
            // COPY BEGIN 971541fd [NEEDS HUMAN REVIEW]
            Text("Pick a face", bundle: .module).sectionHeading()
        } footer: {
            Text(
                "Each one takes your accent color, so changing the color changes them all. A picture you choose is left alone.",
                bundle: .module)
            // COPY END 971541fd
        }
        .groupedRowSurface()
    }

    private var face: some View {
        PersonAvatarView(member: .anonymous(persona), diameter: 88)
    }

    @ViewBuilder private var participation: some View {
        Section {
            ForEach(OutpostConsent.allCases, id: \.self) { standing in
                ChoiceRow(
                    title: OutpostConsentCopy.title(of: standing),
                    detail: OutpostConsentCopy.detail(of: standing),
                    isSelected: standing == consent,
                    action: { Task { await onConsent(standing) } })
            }
        } header: {
            // COPY BEGIN 7bea7391 [NEEDS HUMAN REVIEW]
            Text("Joining in", bundle: .module).sectionHeading()
        } footer: {
            Text(
                "None of these touch your own Outpost. You decide who reads that one person at a time, and nothing here changes what they can already read.",
                bundle: .module)
            // COPY END 7bea7391
        }
        .groupedRowSurface()

        // COPY BEGIN 1b55b0af [NEEDS HUMAN REVIEW]
        Section {
            Toggle(isOn: reviewing) {
                Text("Ask about people I meet", bundle: .module)
            }
        } header: {
            Text("Your own Outpost", bundle: .module).sectionHeading()
        } footer: {
            Text(
                "When you end up in a room with somebody new, the room asks once whether to let them read your Outpost. Off, nobody is ever offered it and you add people yourself. Either way nobody is let in until you say so.",
                bundle: .module)
        }
        .groupedRowSurface()
        // COPY END 1b55b0af
    }

    private var reviewing: Binding<Bool> {
        Binding(get: { settings.offersReview }, set: { on in Task { await onReview(on) } })
    }

    private func saveBlurb(now: Bool) {
        pendingBlurb?.cancel()
        let text = draft
        pendingBlurb = Task {
            if !now { try? await Task.sleep(for: .seconds(1)) }
            guard !Task.isCancelled else { return }
            blurbProblem = await onBlurb(text)
        }
    }

    private func saveName(now: Bool) {
        pendingName?.cancel()
        let typed = name
        let face = persona.face
        pendingName = Task {
            if !now { try? await Task.sleep(for: .seconds(1)) }
            guard !Task.isCancelled else { return }
            await onPersona(AnonPersona(face: face, name: typed))
        }
    }
}

public struct OutpostSettings {
    public var blurb: String
    public var persona: AnonPersona
    public var consent: OutpostConsent?
    public var offersReview: Bool
    public var hasCustomFace: Bool
    public var showsPicture: Bool
    public var hasOwnPicture: Bool
    public var onBlurb: (String) async -> String?
    public var onPersona: (AnonPersona) async -> Void
    public var onConsent: (OutpostConsent) async -> Void
    public var onReview: (Bool) async -> Void
    public var onFace: ((PickedAvatar?) async -> Void)?
    public var onShowsPicture: (Bool) async -> Void
    public var onPicture: ((PickedAvatar?) async -> Void)?
    public var onWallPicture: ((PickedAvatar, OutpostPictureReach) async -> Void)?

    public init(
        blurb: String = "",
        persona: AnonPersona = .default,
        consent: OutpostConsent? = nil,
        offersReview: Bool = true,
        hasCustomFace: Bool = false,
        showsPicture: Bool = true,
        hasOwnPicture: Bool = false,
        onBlurb: @escaping (String) async -> String? = { _ in nil },
        onPersona: @escaping (AnonPersona) async -> Void = { _ in },
        onConsent: @escaping (OutpostConsent) async -> Void = { _ in },
        onReview: @escaping (Bool) async -> Void = { _ in },
        onFace: ((PickedAvatar?) async -> Void)? = nil,
        onShowsPicture: @escaping (Bool) async -> Void = { _ in },
        onPicture: ((PickedAvatar?) async -> Void)? = nil,
        onWallPicture: ((PickedAvatar, OutpostPictureReach) async -> Void)? = nil
    ) {
        self.onWallPicture = onWallPicture
        self.blurb = blurb
        self.persona = persona
        self.consent = consent
        self.offersReview = offersReview
        self.hasCustomFace = hasCustomFace
        self.showsPicture = showsPicture
        self.hasOwnPicture = hasOwnPicture
        self.onBlurb = onBlurb
        self.onPersona = onPersona
        self.onConsent = onConsent
        self.onReview = onReview
        self.onFace = onFace
        self.onShowsPicture = onShowsPicture
        self.onPicture = onPicture
    }
}

public enum OutpostPictureReach: Hashable, Sendable {
    case outpostOnly
    case everywhere
}

#if DEBUG
    #Preview("Your Outpost settings") {
        NavigationStack {
            OutpostSettingsView(
                OutpostSettings(
                    blurb: "Keeping the masthead honest since the second dirigible.",
                    persona: AnonPersona(face: .cheshire),
                    consent: .open,
                    onFace: { _ in }))
        }
        .themed(.default)
    }
#endif
