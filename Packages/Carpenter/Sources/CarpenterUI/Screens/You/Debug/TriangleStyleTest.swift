import CarpenterKit
import SwiftUI

#if DEBUG

struct TriangleStyleTest: View {
    @Environment(\.palette) private var palette
    @Environment(\.anonFace) private var anonFace

    @State private var standing: OutpostConsent = .open
    @State private var explaining = false

    private static let bee = Member(
        id: ParticipantID(rawValue: Data([0xB0, 0xB0, 0xB0])), displayName: "B")
    private static let ay = Member(
        id: ParticipantID(rawValue: Data([0xA0, 0xA0, 0xA0])), displayName: "A")
    private static let cee = Member(
        id: ParticipantID(rawValue: Data([0xC0, 0xC0, 0xC0])), displayName: "C")

    private var post: Text { Text("The kite is up", bundle: .module) }
    private var comment: Text { Text("It is holding well", bundle: .module) }

    var body: some View {
        List {
            SettingsHeaderCard(
                icon: "triangle",
                title: Text("Three people, one Outpost", bundle: .module),
                paragraph: Text(
                    "A and B know each other. B and C know each other. A and C have never met, and both were let in to B's Outpost. C writes under one of B's posts. What each phone draws depends on C's answer, below — and on nothing else.",
                    bundle: .module))

            phone(
                whose: Text("On B's phone — whose post it is", bundle: .module),
                note: bNote, shows: bShows, knowsTheWriter: true, hidden: 0)

            phone(
                whose: Text("On A's phone — a reader who has never met C", bundle: .module),
                note: aNote, shows: aShows, knowsTheWriter: false,
                hidden: standing == .closed ? 1 : 0)

            phone(
                whose: Text("On C's phone — who wrote it", bundle: .module),
                note: cNote, shows: cShows, knowsTheWriter: true, hidden: 0)

            Section {
                EmptyView()
            } footer: {
                Text(
                    "What A holds either way, and what no setting changes: C's identifier, C's device, the time, and the signature. Those are on the envelope so a phone that cannot read a message can still carry it. What changes is whether A can open it, and whether A is ever told who wrote it.",
                    bundle: .module)
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .safeAreaInset(edge: .top) { chooser }
        .navigationTitle(Text("The triangle", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
        .sizedSheet(isPresented: $explaining) {
            HiddenCommentsSheet(hidden: 1, settings: OutpostSettings(consent: standing))
                .themed(.default)
        }
    }

    private var chooser: some View {
        VStack(spacing: 6) {
            Picker(selection: $standing) {
                ForEach(OutpostConsent.allCases, id: \.self) { answer in
                    OutpostConsentCopy.title(of: answer).tag(answer)
                }
            } label: {
                Text("C's setting", bundle: .module)
            }
            .pickerStyle(.segmented)
            .tint(palette.accentColor)

            OutpostConsentCopy.detail(of: standing)
                .font(CarpenterFont.caption)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, CarpenterMetrics.screenMargin)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(.bar)
    }

    // MARK: What each phone draws

    private var bShows: Bool { standing != .off }
    private var aShows: Bool { standing == .open }
    private var cShows: Bool { standing.participates }

    private var bNote: Text {
        switch standing {
        case .open, .closed:
            return Text(
                "B reads it either way. Under *closed* it reaches B through a second copy sealed to the two of them, which is what stops the setting silencing somebody's answer to their own friend.",
                bundle: .module)
        case .quiet:
            return Text("C wrote nothing, so there is nothing under the post.", bundle: .module)
        case .off:
            return Text(
                "C has no Outposts, so C never received the post and there was nothing to answer.",
                bundle: .module)
        }
    }

    private var aNote: Text {
        switch standing {
        case .open:
            return Text(
                "A reads the words and is shown one anonymous figure. No name, no picture, and no way through to C — the figure has no page to open.",
                bundle: .module)
        case .closed:
            return Text(
                "A holds the message and no key for it. The words are not drawn and the comment is not counted — A cannot even tell it was a comment, or what it was on. What A is told is that the thread is short, because B publishes how many comments the post has and B is the only person who can see all of them. Tapping that line explains it, including that the number is the one thing in the app A cannot check.",
                bundle: .module)
        case .quiet:
            return Text("Nothing was written, so there is nothing to hold.", bundle: .module)
        case .off:
            return Text("Nothing was written, so there is nothing to hold.", bundle: .module)
        }
    }

    private var cNote: Text {
        switch standing {
        case .open:
            return Text("C sees their own words, under their own name.", bundle: .module)
        case .closed:
            return Text(
                "C sees their own words. So does anybody C has let into their own Outpost — and nobody else.",
                bundle: .module)
        case .quiet:
            return Text(
                "C reads B's post and writes nothing under it. C's own Outpost is untouched.",
                bundle: .module)
        case .off:
            return Text("C has no Outposts tab at all.", bundle: .module)
        }
    }

    @ViewBuilder
    private func phone(
        whose: Text, note: Text, shows: Bool, knowsTheWriter: Bool, hidden: Int
    ) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                thread(shows: shows, knowsTheWriter: knowsTheWriter, hidden: hidden)
                note
                    .font(CarpenterFont.caption)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
        } header: {
            whose.sectionHeading()
        }
        .groupedRowSurface()
    }

    @ViewBuilder
    private func thread(shows: Bool, knowsTheWriter: Bool, hidden: Int) -> some View {
        let commenter = knowsTheWriter ? Self.cee : Member.anonymous(AnonPersona(face: anonFace))
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                PersonAvatarView(member: Self.bee, diameter: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: Self.bee.displayName)
                        .font(CarpenterFont.postAuthor)
                        .foregroundStyle(palette.primaryText)
                    post
                        .font(CarpenterFont.rowDetail)
                        .foregroundStyle(palette.primaryText)
                }
            }

            if shows {
                HStack(alignment: .top, spacing: 9) {
                    PersonAvatarView(
                        member: commenter, diameter: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: commenter.displayName)
                            .font(CarpenterFont.comment.weight(.semibold))
                            .foregroundStyle(palette.primaryText)
                        comment
                            .font(CarpenterFont.comment)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                .padding(.leading, 20)
            } else if hidden == 0 {
                Text("No comments.", bundle: .module)
                    .font(CarpenterFont.caption)
                    .foregroundStyle(palette.tertiaryText)
                    .padding(.leading, 20)
            }

            if hidden > 0 {
                Button { explaining = true } label: {
                    HStack(spacing: 5) {
                        (hidden == 1
                            ? Text("1 comment is not shown", bundle: .module)
                            : Text("\(hidden) comments are not shown", bundle: .module))
                            .font(CarpenterFont.caption)
                        Image(systemName: "info.circle").font(.caption2)
                    }
                    .foregroundStyle(palette.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                }
                .buttonStyle(.plain)
                .tappable()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(palette.contentSurface, in: .rect(cornerRadius: 14, style: .continuous))
    }

}

#endif
