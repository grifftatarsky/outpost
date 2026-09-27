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
                        // COPY BEGIN 7d330d05 [HUMAN REVIEWED, UNVERIFIED]
                        section(
                            "What is \(Branding.displayName)?",
                            [
                                "\(Branding.displayName) is a messaging app with Rooms, Solos (Direct messaging), and a shareable page—your Outpost—for posts, photos, and more.",
                                "\(Branding.displayName) is a peer-to-peer messaging app. Everything you write is stored only on the devices of the people you wrote it to, not in a server, on personal hardware.",
                            ]
                        )
                        // COPY END 7d330d05

                        // COPY BEGIN 04884ac4 [HUMAN REVIEWED, UNVERIFIED]
                        section(
                            "Your own iCloud as a Mailbox",
                            [
                                "\(Branding.displayName) uses your own iCloud as a mailbox, which passes messages to their recipients, sealed by encryption, and deletes them after receipt.",
                                "The \(Branding.displayName) Dev has no server, and nothing to do with you after you download the app. Messages are placed inside your own iCloud, sealed and unreadable, addressed to a rotating code. Once all parties have retrieved the mail addressed to them, it's removed from the mailbox. Nobody—not even Apple—can read what passes through your mailbox.",
                                "Media is treated the same, as a sealed file. This means the mailbox can see the compressed size; it can see nothing else. The only time any of your data is readable is on your, or your recipients', devices.",
                            ]
                        )
                        // COPY END 04884ac4

                        // COPY BEGIN b561c670 [NEEDS HUMAN REVIEW]
                        section(
                            "Account Free",
                            [
                                "\(Branding.displayName) uses your Keychain as its identity: there is no account and no personal information stored by anyone.",
                                "Because your key, kept on your own devices, is your identity, there's no lookup. We do not integrate with Contacts.",
                            ]
                        )
                        section(
                            "Invitations and Approvals",
                            [
                                "Invitations to Rooms or Solos are signed and expire, and must name the invitee specifically.",
                                "Rooms can be customized to different member approval settings, from standard anyone-can-invite to any number of approvers to founder only. A key challenge is issued on invitation—\(Branding.displayName) never takes somebody's claim for who they are and presents it as proof. Verify!",
                            ]
                        )
                        section(
                            "Sync and Restore",
                            [
                                "Your identity reaches a new device only when one of your other devices approves it, and never goes to iCloud Keychain. If you lose every device, your recovery key restores your identity and removes every other device, and a restored identity can notify and request the people you talk to for their copies of your conversations, backfilling your history.",
                            ]
                        )
                        // COPY END b561c670

                        comparisons

                        // COPY BEGIN 614f14c4 [HUMAN REVIEWED, UNVERIFIED]
                        section(
                            "Source & Review",
                            [
                                "\(Branding.displayName) is open source, published under the Mozilla Public License 2.0. There are contributor instructions on GitHub for reviewing and contributing code. \(Branding.displayName) is scanned and tested for vulnerabilities thoroughly before releases. We take all feedback seriously, and we solicit external security reviews.",
                            ]
                        )
                        // COPY END 614f14c4

                        // COPY BEGIN 1675ec4f [HUMAN REVIEWED, UNVERIFIED]
                        section(
                            "Notifications",
                            [
                                "Notifications enable realtime banners, badges, and sounds to alert you of a new message, or configurable notifications for other events. If you decline notifications, you will see new messages when you open the app, and your devices will still sync. Notifications have full privacy controls.",
                            ]
                        )
                        // COPY END 1675ec4f

                        // COPY BEGIN 85f818ac [HUMAN REVIEWED, UNVERIFIED]
                        section(
                            "Media",
                            [
                                "Media is sent stripped of metadata, and sealed like any other message in the mailbox. Screening is on by default, using an on-device capability, and media is blurred until you decide to look at it. Toggled under Safety.",
                            ]
                        )
                        // COPY END 85f818ac
                    }
                    .padding(.horizontal, CarpenterMetrics.screenMargin)
                    .padding(.vertical, 20)
                }

                footer
            }
            .background(palette.background)
            // COPY BEGIN 79e25afb [HUMAN REVIEWED, UNVERIFIED]
            .navigationTitle(Text("How this works", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                }
            }
            // COPY END 79e25afb
        }
    }

    private var comparisons: some View {
        VStack(alignment: .leading, spacing: 14) {
            // COPY BEGIN 07207d26 [NEEDS HUMAN REVIEW]
            Text("\(Branding.displayName) vs. The Others", bundle: .module)
                .font(CarpenterFont.rowTitle)
                .foregroundStyle(palette.primaryText)
                .heading()

            Text(
                "The \(Branding.displayName) Dev Opinion is that all of these apps are impressive stacks, and by no means are unsafe. But they are different.\n\niCloud runs on Apple's servers and Big Cloud's. So does Signal, and so do WhatsApp and Meta, corporate interests with deals with Big Cloud and Big AI. On hosting, you gain nothing and lose nothing here. If you want more, the source is open, and a debug build can keep its mailbox in a folder you host instead of iCloud. We don't offer that. Technically.",
                bundle: .module
            )
            .font(CarpenterFont.footnote)
            .foregroundStyle(palette.secondaryText)
            // COPY END 07207d26

            // COPY BEGIN 43e010c0 [NEEDS HUMAN REVIEW]
            comparison(
                "Signal",
                "Signal's encryption set the standard the rest of the industry strives for, \(Branding.displayName) included. However, Signal knows your phone number and runs the servers your messages pass through. \(Branding.displayName) has no number and no account, and your history lives on your friends' devices rather than being fetched from a service. We don't know anything about you."
            )
            comparison(
                "iMessage",
                "Like Signal, iMessage is end-to-end encrypted between devices. The gap most people miss is the backup: unless you have Advanced Data Protection switched on, which limits some functionality, iCloud holds a key to your conversations. Here there is no server-side copy to hold a key to, and no option lets the \(Branding.displayName) Dev read anything you have. The \(Branding.displayName) Dev has nothing."
            )
            comparison(
                "WhatsApp",
                "Encrypted in transit and at rest, WhatsApp is owned by Meta, which sees who you talk to and how often even when it cannot see what you say. That pattern—the words are private, the social graph is not—is what the rotating addresses here are for. Your data is part of the larger Meta ecosystem."
            )
            // COPY END 43e010c0
            // COPY BEGIN 1b29af76 [HUMAN REVIEWED, UNVERIFIED]
            comparison(
                "Facebook Messenger",
                "Encrypted between people, but built around an account tied to your real identity and a company whose business is knowing about you. \(Branding.displayName) has no identity to tie anything to. There are no algorithms and no social media ecosystem to be a part of."
            )
            // COPY END 1b29af76
        }
    }

    private func comparison(_ name: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name, bundle: .module)
                .font(CarpenterFont.postAuthor)
                .foregroundStyle(palette.primaryText)
                .heading()
            Text(body, bundle: .module)
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
        // COPY BEGIN fb84afbe [HUMAN REVIEWED, UNVERIFIED]
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
        // COPY END fb84afbe
    }
}

#Preview("How this works") {
    HowItWorksView().themed(.default)
}
