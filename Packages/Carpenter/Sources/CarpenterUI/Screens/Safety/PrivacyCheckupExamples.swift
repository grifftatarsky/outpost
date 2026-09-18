import CarpenterKit
import SwiftUI

// MARK: - What each switch looks like in use

struct TabExample: View {
    @Environment(\.palette) private var palette

    let present: Bool

    var body: some View {
        HStack(spacing: 26) {
            item("bubble.left", Text("Solos", bundle: .module), isOn: false)
            item("bubble.left.and.bubble.right", Text("Rooms", bundle: .module), isOn: false)
            if present {
                item("rectangle.stack", Text("Outposts", bundle: .module), isOn: true)
            }
            item("person.crop.circle", Text("You", bundle: .module), isOn: false)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func item(_ symbol: String, _ label: Text, isOn: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 17))
            label.font(.system(size: 10))
        }
        .foregroundStyle(isOn ? palette.accentColor : palette.tertiaryText)
    }
}

struct ReachExample: View {
    @Environment(\.palette) private var palette
    @Environment(\.anonFace) private var anonFace

    let consent: OutpostConsent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(
                Member(id: Sample.otherID, displayName: "Robin"),
                who: Text("whose post it is", bundle: .module),
                reads: consent.participates)
            row(
                Member.placeholder(ParticipantID(rawValue: Data([0x5C, 0x02, 0xE7]))),
                who: Text("somebody you have let in", bundle: .module),
                reads: consent.participates)
            row(
                .anonymous(AnonPersona(face: anonFace)),
                who: Text("somebody you have never met", bundle: .module),
                reads: consent == .open,
                note: consent == .open
                    ? Text("as one anonymous figure", bundle: .module) : nil)
        }
        .padding(.vertical, 2)
    }

    private func row(_ person: Member, who: Text, reads: Bool, note: Text? = nil) -> some View {
        HStack(spacing: 10) {
            PersonAvatarView(member: person, diameter: 28)
            VStack(alignment: .leading, spacing: 1) {
                who
                    .font(CarpenterFont.rowDetail)
                    .foregroundStyle(palette.primaryText)
                if let note {
                    note.font(CarpenterFont.caption).foregroundStyle(palette.tertiaryText)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: reads ? "checkmark" : "minus")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(reads ? palette.accentColor : palette.quaternaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ReviewExample: View {
    @Environment(\.palette) private var palette

    let asks: Bool

    var body: some View {
        Group {
            if asks {
                HStack(spacing: 10) {
                    PersonAvatarView(member: Sample.other(named: true), diameter: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Let Robin read your Outpost?", bundle: .module)
                            .font(CarpenterFont.rowTitle)
                            .foregroundStyle(palette.primaryText)
                        Text("You can say no, or decide later.", bundle: .module)
                            .font(CarpenterFont.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Text("Nothing. You add readers yourself, when you want to.", bundle: .module)
                    .font(CarpenterFont.rowDetail)
                    .foregroundStyle(palette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The examples

struct ExampleCard<Content: View>: View {
    @Environment(\.palette) private var palette

    let caption: Text
    @ViewBuilder let content: Content

    var body: some View {
        Section {
            content
                .padding(.vertical, 6)
        } header: {
            caption.sectionHeading()
        }
        .groupedRowSurface()
    }
}

enum Sample {
    static let otherID = ParticipantID(rawValue: Data([0xA4, 0x1F, 0x2C, 0x91, 0x37, 0x08]))

    static func other(named: Bool) -> Member {
        named ? Member(id: otherID, displayName: "Robin") : Member.placeholder(otherID)
    }
}

struct SeenAsRow: View {
    @Environment(\.palette) private var palette

    let person: Member
    let isAccented: Bool
    var photo: Image? = nil
    var wearsTheMark: Bool = false
    var preview: Text = Text("Are you around later?", bundle: .module)

    var body: some View {
        HStack(spacing: 12) {
            if wearsTheMark {
                ZStack {
                    Circle().fill(palette.accentFill)
                    AnimatedMark(size: CarpenterMetrics.roomAvatar * 0.6, tint: .white)
                }
                .frame(width: CarpenterMetrics.roomAvatar, height: CarpenterMetrics.roomAvatar)
                .accessibilityLabel(Text("A shared photo", bundle: .module))
            } else {
                AvatarView(
                    initials: person.initials, diameter: CarpenterMetrics.roomAvatar, isAccented: isAccented,
                    image: photo)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName)
                    .font(CarpenterFont.rowTitle)
                    .foregroundStyle(palette.primaryText)
                preview
                    .font(CarpenterFont.rowDetail)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer(minLength: 0)
        }
    }
}

struct FocusExample: View {
    @Environment(\.palette) private var palette

    let shared: Bool

    var body: some View {
        VStack(spacing: 8) {
            if shared {
                HStack(spacing: 6) {
                    Image(systemName: "moon.fill")
                    Text("Do Not Disturb", bundle: .module)
                }
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)
            } else {
                Text("Nothing. They see the field and no more.", bundle: .module)
                    .font(CarpenterFont.caption)
                    .foregroundStyle(palette.tertiaryText)
            }
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.contentSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(palette.separator, lineWidth: 1))
                .frame(height: 40)
                .overlay(alignment: .leading) {
                    Text("Message", bundle: .module)
                        .foregroundStyle(palette.tertiaryText)
                        .padding(.leading, 16)
                }
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ReceiptExample: View {
    @Environment(\.palette) private var palette

    let reports: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            MessageBubbleView(text: String(localized: "See you at eight", bundle: .module), isMine: true, position: .only)
            DeliveryMarkView(delivery: reports ? .displayed(at: .now) : .notReported)
            Text(
                reports
                    ? "Read, with the time it was shown."
                    : "Does not report. They are told, not left waiting.",
                bundle: .module
            )
            .font(CarpenterFont.caption)
            .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct BlurExample: View {
    @Environment(\.palette) private var palette

    let blurred: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [palette.accentColor.opacity(0.7), palette.accentColor.opacity(0.25)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 110, height: 82)
                    .blur(radius: blurred ? 10 : 0)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                if blurred {
                    Image(systemName: "eye.slash.fill")
                        .font(.title3)
                        .foregroundStyle(palette.textOnAccentTint)
                }
            }
            .accessibilityHidden(true)
            Text(
                blurred
                    ? "Blurred until you choose to look."
                    : "Shown as it is.",
                bundle: .module
            )
            .font(CarpenterFont.rowDetail)
            .foregroundStyle(palette.secondaryText)
            Spacer(minLength: 0)
        }
    }
}

struct SoloCheckExample: View {
    @Environment(\.palette) private var palette

    let required: Bool

    var body: some View {
        HStack(spacing: 12) {
            if required {
                IconTile(
                    "person.crop.circle.badge.checkmark",
                    fill: palette.tileFill(.device), size: CarpenterMetrics.roomAvatar)
                Text(
                    "Held until you have both read the characters. They are told you asked.",
                    bundle: .module)
                    .font(CarpenterFont.rowDetail)
                    .foregroundStyle(palette.secondaryText)
            } else {
                SeenAsRow(
                    person: Member.placeholder(Sample.otherID), isAccented: false,
                    preview: Text("\u{201C}hello — it's me\u{201D}", bundle: .module))
            }
            Spacer(minLength: 0)
        }
    }
}

struct RestoreAskExample: View {
    @Environment(\.palette) private var palette

    let told: Bool

    var body: some View {
        HStack(spacing: 12) {
            IconTile(
                told ? "key.horizontal.fill" : "bell.slash.fill",
                fill: palette.tileFill(.device), size: CarpenterMetrics.roomAvatar)
            VStack(alignment: .leading, spacing: 2) {
                if told {
                    Text("Outie set up a new device", bundle: .module)
                        .font(CarpenterFont.rowTitle)
                        .foregroundStyle(palette.primaryText)
                    Text(
                        "It asked for your copy of Kitchen. Your history is on its way to them.",
                        bundle: .module)
                        .font(CarpenterFont.rowDetail)
                        .foregroundStyle(palette.secondaryText)
                } else {
                    Text("Nothing appears", bundle: .module)
                        .font(CarpenterFont.rowTitle)
                        .foregroundStyle(palette.primaryText)
                    Text(
                        "Your history still goes to them. You are simply not told it was asked for.",
                        bundle: .module)
                        .font(CarpenterFont.rowDetail)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct RestoreHoldExample: View {
    @Environment(\.palette) private var palette

    let holding: Bool

    var body: some View {
        HStack(spacing: 12) {
            IconTile(
                holding ? "hand.raised.fingers.spread.fill" : "paperplane.fill",
                fill: palette.tileFill(.device), size: CarpenterMetrics.roomAvatar)
            VStack(alignment: .leading, spacing: 2) {
                if holding {
                    Text("Read these to each other first", bundle: .module)
                        .font(CarpenterFont.rowTitle)
                        .foregroundStyle(palette.primaryText)
                    Text(verbatim: "C A A E C 9")
                        .font(CarpenterFont.rowTitle.monospaced())
                        .foregroundStyle(palette.accentColor)
                } else {
                    Text("Your copy goes straight away", bundle: .module)
                        .font(CarpenterFont.rowTitle)
                        .foregroundStyle(palette.primaryText)
                    Text("Nothing waits for you to open the app.", bundle: .module)
                        .font(CarpenterFont.rowDetail)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct BlockExample: View {
    @Environment(\.palette) private var palette

    let blocked: Bool

    var body: some View {
        HStack(spacing: 12) {
            if blocked {
                IconTile("hand.raised.slash.fill", fill: palette.tileFill(.device), size: CarpenterMetrics.roomAvatar)
                Text("Not shown, in any room, and not told.", bundle: .module)
                    .font(CarpenterFont.rowDetail)
                    .foregroundStyle(palette.secondaryText)
            } else {
                SeenAsRow(
                    person: Member.placeholder(Sample.otherID), isAccented: false,
                    preview: Text("\u{201C}rude text\u{201D}", bundle: .module))
            }
            Spacer(minLength: 0)
        }
    }
}
