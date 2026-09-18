import CarpenterKit
import SwiftUI

public struct HowItWorksView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    public init() {}

    private static let website = URL(string: "https://outpostmessaging.com")!

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        section(
                            "What this is",
                            [
                                "A place for a group of friends to talk. Rooms for shared conversation, and an Outpost of your own for the things you want that group to see.",
                                "Everything you write lives on the phones of the people you wrote it to. Not on a server that happens to be encrypted — on their devices.",
                            ]
                        )

                        section(
                            "There is a mailbox, and we will not pretend otherwise",
                            [
                                "Messages have to get from your device to theirs, and devices are not always awake. So there is a mailbox in the middle.",
                                "What it holds is sealed. It is addressed to a code that changes, so whoever runs it cannot build a picture of who talks to whom, and it is deleted once everyone has collected. Nobody — not us, not Apple — can read what passes through it, because nothing readable was ever put in.",
                                "A photo or a clip goes the same way, as a separate sealed file. The mailbox can see its size and nothing else.",
                            ]
                        )

                        section(
                            "You do not have an account",
                            [
                                "There is no sign-up, no password, and no e-mail address. Your device makes a key and that key is you.",
                                "Nobody can look you up. Somebody already in a room has to invite you, and their invitation is signed, expires, and names you specifically — so everyone can see who let you in, and nobody can be added by a stranger.",
                                "Whoever made a room can require approval before anyone new is let in — the founder's, one member's, or everybody's — and by default nobody else is asked. Either way you and whoever invited you read the same characters to each other first, so a room never takes somebody's word for who you are.",
                                "Your keys live in your iCloud Keychain, so a new phone picks them up by itself. If the keychain goes too, your recovery key is the way back — it makes you you again. It carries no conversations, so the app asks the people you were talking to for their copies, and tells them it asked.",
                            ]
                        )

                        comparisons

                        section(
                            "Who has checked this",
                            [
                                "The locks themselves are Apple's, and they are the same ones the apps above use. Nothing about the mathematics is homemade here — no cipher, no signature, no key exchange was written for this app.",
                                "What was written for this app is the arrangement: which key opens what, who is handed one, and when a room turns its key. Nobody outside the project has reviewed that arrangement. The source is published so that anybody can, but being open to inspection is not the same as having been inspected, and this app will not tell you otherwise.",
                            ]
                        )

                        section(
                            "Notifications",
                            [
                                "Outpost asks for notifications so a message from somebody else can announce itself. There is no server watching for you; the banner is put together on your own device after it decrypts the message, and it says as much as you allow under Notifications.",
                                "Your own devices keeping up with each other never make a sound and never show a banner. Say no to notifications and nothing announces itself; messages still arrive every time you open the app.",
                            ]
                        )

                        section(
                            "What you give up",
                            [
                                "It syncs when you open it. There is no background service keeping you current, so you learn about messages when you look — a deliberate choice, and the reason this works on iPhone at all when other attempts have not.",
                                "There is no search yet, and no web version.",
                                "Photos and clips can be sent. Each is scaled down, stripped of its location and camera details, and sealed like a message. Your own device can screen what arrives, using a capability built into the operating system, and blur it until you choose to look; that is a switch under Safety, and the judgment never leaves your device.",
                            ]
                        )
                    }
                    .padding(.horizontal, CarpenterMetrics.screenMargin)
                    .padding(.vertical, 20)
                }

                footer
            }
            .background(palette.background)
            .navigationTitle(Text("How this works", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                }
            }
        }
    }

    private var comparisons: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How it differs", bundle: .module)
                .font(CarpenterFont.rowTitle)
                .foregroundStyle(palette.primaryText)
                .heading()

            Text(
                "These are all decent apps. What follows is what is different here, not a claim that they are unsafe.",
                bundle: .module
            )
            .font(CarpenterFont.footnote)
            .foregroundStyle(palette.secondaryText)

            comparison(
                "Signal",
                "Signal's encryption is the standard the rest of the industry copied, this app included. The difference is the account: Signal knows a phone number for you and runs the servers your messages pass through. Here there is no number and no account, and your history lives on your friends' devices rather than being fetched from a service."
            )
            comparison(
                "iMessage",
                "Also end-to-end encrypted between devices. The gap most people miss is the backup: unless you have Advanced Data Protection switched on, iCloud holds a key to your conversations. Here there is no server-side copy to hold a key to."
            )
            comparison(
                "WhatsApp",
                "Encrypted in transit and at rest, and owned by Meta, which sees who you talk to and how often even when it cannot see what you say. That pattern — the words are private, the social graph is not — is what the rotating addresses here are for."
            )
            comparison(
                "Facebook Messenger",
                "Encrypted between people now, but built around an account tied to your real identity and a company whose business is knowing about you. There is no identity here to tie anything to."
            )
        }
    }

    private func comparison(_ name: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(CarpenterFont.postAuthor)
                .foregroundStyle(palette.primaryText)
                .heading()
            Text(body)
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            palette.elevatedSurface,
            in: .rect(cornerRadius: CarpenterMetrics.cardRadius, style: .continuous))
    }

    private func section(_ title: LocalizedStringKey, _ paragraphs: [LocalizedStringKey])
        -> some View
    {
        VStack(alignment: .leading, spacing: 8) {
            Text(title, bundle: .module)
                .font(CarpenterFont.rowTitle)
                .foregroundStyle(palette.primaryText)
                .heading()

            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph, bundle: .module)
                    .font(CarpenterFont.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        Button {
            openURL(Self.website)
        } label: {
            HStack(spacing: 6) {
                Text("outpostmessaging.com", bundle: .module)
                    .font(CarpenterFont.button)
                Image(systemName: "arrow.up.right")
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity, minHeight: CarpenterMetrics.buttonHeight)
        }
        .foregroundStyle(palette.accentColor)
        .padding(.horizontal, CarpenterMetrics.screenMargin)
        .background(.bar)
    }
}

#Preview("How this works") {
    HowItWorksView().themed(.default)
}
