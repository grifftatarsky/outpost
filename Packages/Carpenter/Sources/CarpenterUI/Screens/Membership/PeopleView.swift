import CarpenterKit
import CarpenterMedia
import PhotosUI
import SwiftUI

public struct PersonRoute: Hashable, Sendable {
    public let person: ParticipantID

    public init(_ person: ParticipantID) { self.person = person }
}

struct PeopleView: View {
    @Environment(\.palette) private var palette
    @Environment(\.showsAvatars) private var showsAvatars

    let connections: [Connection]
    let nickname: (ParticipantID) -> String?
    let sharedName: (ParticipantID) -> String?
    let onNicknameChange: ((ParticipantID, String?) async -> Void)?
    let onPersonAvatarChange: ((ParticipantID, PickedAvatar?) async -> Void)?

    @State private var query = ""

    private var sections: [(title: String, people: [Connection])] {
        connections.matching(query).sectionedByInitial()
    }

    private var noMatch: some View {
        ContentUnavailableView {
            Label {
                Text("Nobody by that name", bundle: .module)
            } icon: {
                Image(systemName: "person.2")
            }
        } description: {
            Text("Try part of their name, or the code shown on their row.", bundle: .module)
        }
        .background(palette.background)
    }

    var body: some View {
        Group {
            if connections.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("Nobody yet", bundle: .module)
                    } icon: {
                        Image(systemName: "person.2")
                    }
                } description: {
                    Text(
                        "People appear here once you share a room with them. Nobody can be looked up.",
                        bundle: .module)
                }
                .background(palette.background)
            } else {
                List {
                    ForEach(sections, id: \.title) { section in
                        Section {
                            ForEach(section.people) { connection in
                                NavigationLink {
                                    PersonDetailView(
                                        connection: connection,
                                        nickname: nickname(connection.id),
                                        sharedName: sharedName(connection.id),
                                        onNicknameChange: onNicknameChange,
                                        onPersonAvatarChange: onPersonAvatarChange)
                                } label: {
                                    row(connection)
                                }
                            }
                        } header: {
                            Text(verbatim: section.title).sectionHeading()
                        }
                        .groupedRowSurface()
                        .sectionIndexLabel(section.title)
                    }
                }
                .searchable(text: $query, prompt: Text("Search people", bundle: .module))
                .autocorrectionDisabled()
                .overlay {
                    if sections.isEmpty, !query.isEmpty { noMatch }
                }
                .scrollContentBackground(.hidden)
                .background(palette.background)
            }
        }
        .navigationTitle(Text("People", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
    }

    private func row(_ connection: Connection) -> some View {
        HStack(spacing: 12) {
            if showsAvatars {
                PersonAvatarView(member: connection.person, diameter: CarpenterMetrics.messageAvatar)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: connection.person.displayName)
                    .font(CarpenterFont.rowTitle)
                    .foregroundStyle(palette.primaryText)
                Group {
                    if connection.sharedRooms > 0 {
                        Text("^[\(connection.sharedRooms) room](inflect: true) together", bundle: .module)
                    } else {
                        Text("Outpost only", bundle: .module)
                    }
                }
                .font(CarpenterFont.rowDetail)
                .foregroundStyle(palette.tertiaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

public struct PersonDetailView: View {
    @Environment(\.palette) private var palette
    @Environment(\.personAvatars) private var personAvatars
    @Environment(\.sharedAvatars) private var sharedAvatars

    let connection: Connection
    let sharedName: String?
    let onNicknameChange: ((ParticipantID, String?) async -> Void)?
    let onPersonAvatarChange: ((ParticipantID, PickedAvatar?) async -> Void)?

    @State private var name: String
    @State private var picked: PhotosPickerItem?
    @State private var choosing = false
    @State private var pendingSave: Task<Void, Never>?

    public init(
        connection: Connection, nickname: String?, sharedName: String?,
        onNicknameChange: ((ParticipantID, String?) async -> Void)?,
        onPersonAvatarChange: ((ParticipantID, PickedAvatar?) async -> Void)?
    ) {
        self.connection = connection
        self.sharedName = sharedName
        self.onNicknameChange = onNicknameChange
        self.onPersonAvatarChange = onPersonAvatarChange
        _name = State(initialValue: nickname ?? "")
    }

    private var person: Member { connection.person }
    private var hasPhoto: Bool { personAvatars[person.id] != nil }
    private var canEdit: Bool { onNicknameChange != nil || onPersonAvatarChange != nil }

    public var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    if onPersonAvatarChange != nil {
                        Button { choosing = true } label: {
                            badgedAvatar
                        }
                        .buttonStyle(.plain)
                        .photosPicker(isPresented: $choosing, selection: $picked, matching: .images)
                    } else {
                        PersonAvatarView(member: person, diameter: 88)
                    }
                    Text(verbatim: person.displayName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(palette.primaryText)
                    Text(verbatim: person.id.groupedFingerprint)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(palette.tertiaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .groupedRowSurface()

            if canEdit {
                Section {
                    if onNicknameChange != nil {
                        HStack(spacing: 12) {
                            IconTile("pencil", fill: palette.tileFill(.feature))
                            TextField(text: $name) {
                                Text("What you call them", bundle: .module)
                            }
                            .textFieldStyle(.plain)
                            .foregroundStyle(palette.primaryText)
                            .textContentType(.name)
                            .submitLabel(.done)
                            .onSubmit { save(now: true) }
                        }
                    }
                    if hasPhoto, let onPersonAvatarChange {
                        Button(role: .destructive) {
                            Task { await onPersonAvatarChange(person.id, nil) }
                        } label: {
                            SettingsRow(
                                icon: "person.crop.circle.badge.minus", tone: .destructive,
                                title: Text("Remove photo", bundle: .module))
                        }
                        .tint(palette.destructive)
                    }
                } header: {
                    Text("On your phone", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "A name or photo you set here is yours alone: drawn wherever this person appears, and never sent to anybody — not to them, not to a room. Clear the name to go back to what they shared.",
                        bundle: .module)
                }
                .groupedRowSurface()
            }

            Section {
                HStack(spacing: 12) {
                    IconTile("person.text.rectangle.fill", fill: palette.tileFill(.feature))
                    Text("Their name", bundle: .module)
                        .foregroundStyle(palette.primaryText)
                    Spacer(minLength: 8)
                    if let shared = sharedAvatars[person.id] {
                        AvatarView(initials: person.initials, diameter: 28, image: shared)
                            .accessibilityLabel(Text("Their photo", bundle: .module))
                    }
                    (sharedName.map { Text(verbatim: $0) } ?? Text("Not shown", bundle: .module))
                        .foregroundStyle(palette.secondaryText)
                }
                .accessibilityElement(children: .combine)
                SettingsRow(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: Text("Rooms together", bundle: .module),
                    detail: Text("\(connection.sharedRooms)", bundle: .module))
            } footer: {
                Text(
                    "Their name and photo are what they shared, shown where Show others' names and photos are on. The code under their name is theirs for good.",
                    bundle: .module)
            }
            .groupedRowSurface()
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(palette.background)
        .navigationTitle(Text(verbatim: person.displayName))
        .toolbarTitleDisplayMode(.inline)
        .croppingPickedPhoto($picked) { await onPersonAvatarChange?(person.id, $0) }
        .onDisappear { save(now: true) }
    }

    private var badgedAvatar: some View {
        PersonAvatarView(member: person, diameter: 88)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(palette.accentFill, in: .circle)
                    .overlay(Circle().strokeBorder(palette.contentSurface, lineWidth: 2))
                    .offset(x: 4, y: 4)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel(Text("Choose a photo", bundle: .module))
    }

    private func save(now: Bool) {
        guard let onNicknameChange else { return }
        pendingSave?.cancel()
        let value = name
        pendingSave = Task {
            if !now { try? await Task.sleep(for: .milliseconds(600)) }
            guard !Task.isCancelled else { return }
            await onNicknameChange(person.id, value)
        }
    }
}
