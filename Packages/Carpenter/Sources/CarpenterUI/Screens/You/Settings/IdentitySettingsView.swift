import CarpenterKit
import CarpenterMedia
import PhotosUI
import SwiftUI

struct IdentitySettingsView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize

    let owner: Member
    let fingerprint: String
    let identityCode: String
    let onRename: ((String) async -> String?)?
    let onAvatarChange: ((PickedAvatar?) async -> Void)?
    @Environment(\.ownAvatar) private var ownAvatar
    @Environment(\.tapToSwap) private var tapToSwap
    @State private var pickedAvatar: PhotosPickerItem?
    @State private var choosingAvatar = false

    private var identityShareable: String {
        guard let code = try? JoinerCode.decoded(from: identityCode),
            let link = try? InviteLink.url(offering: code, scheme: Branding.urlScheme)
        else { return identityCode }
        return link.absoluteString
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    if onAvatarChange != nil {
                        Button { choosingAvatar = true } label: {
                            AvatarView(initials: owner.initials, diameter: 64, isAccented: true, image: ownAvatar)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(palette.accentFill, in: .circle)
                                        .overlay(Circle().strokeBorder(palette.contentSurface, lineWidth: 2))
                                        .offset(x: 3, y: 3)
                                        .accessibilityHidden(true)
                                }
                        }
                        .buttonStyle(.plain)
                        .photosPicker(isPresented: $choosingAvatar, selection: $pickedAvatar, matching: .images)
                        // COPY BEGIN 3812cbad [NEEDS HUMAN REVIEW]
                        .accessibilityLabel(Text("Change your photo", bundle: .module))
                        // COPY END 3812cbad
                    } else {
                        AvatarView(initials: owner.initials, diameter: 64, isAccented: true, image: ownAvatar)
                    }
                    Text(owner.displayName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(palette.primaryText)
                        .heading()
                    Text(fingerprint)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(palette.tertiaryText)
                    // COPY BEGIN da3b159f [NEEDS HUMAN REVIEW]
                    Text(
                        "This is your key, not an account. There is no sign-up, no password and no phone number, and nobody can look you up by it.",
                        bundle: .module
                    )
                    .font(CarpenterFont.rowDetail)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    // COPY END da3b159f
                }
                .padding(.vertical, 6)
            }
            .groupedRowSurface()

            if onAvatarChange != nil, ownAvatar != nil {
                // COPY BEGIN 628f64f4 [NEEDS HUMAN REVIEW]
                Section {
                    Button(role: .destructive) {
                        Task { await onAvatarChange?(nil) }
                    } label: {
                        SettingsRow(
                            icon: "person.crop.circle.badge.minus", tone: .destructive,
                            title: Text("Remove photo", bundle: .module))
                    }
                    .tint(palette.destructive)
                } footer: {
                    Text("Back to your initials on a disc, which is what everybody else sees today.", bundle: .module)
                }
                .groupedRowSurface()
                // COPY END 628f64f4
            }

            if let onRename {
                Section {
                    // COPY BEGIN c3543aff [NEEDS HUMAN REVIEW]
                    NavigationLink {
                        RenameMemberView(current: owner.displayName, onRename: onRename)
                    } label: {
                        SettingsRow(
                            icon: "pencil",
                            title: Text("Name", bundle: .module),
                            detail: Text(owner.displayName))
                    }
                } footer: {
                    Text(
                        "Your name is how people in your rooms see you, once Share my name is on in Privacy & Safety. Until then it stays on this device, and changing it reaches nobody.",
                        bundle: .module)
                    // COPY END c3543aff
                }
                .groupedRowSurface()
            }

            // COPY BEGIN b67a4def [NEEDS HUMAN REVIEW]
            if !identityCode.isEmpty {
                Section {
                    ShareLink(item: identityShareable) {
                        SettingsRow(
                            icon: "square.and.arrow.up",
                            title: Text("Send someone your code", bundle: .module))
                    }
                } footer: {
                    Text(
                        "Somebody needs your code before they can add you to a room. It carries your public key, how many characters you want to check, and a one-time value that stops anybody in the middle working those characters out in advance. Nothing in it says who you are.",
                        bundle: .module)
                }
                .groupedRowSurface()
            }
            // COPY END b67a4def

            if let tapToSwap, !identityCode.isEmpty {
                // COPY BEGIN cdd906bc [NEEDS HUMAN REVIEW]
                Section {
                    Button(action: tapToSwap) {
                        SettingsRow(
                            icon: "iphone.radiowaves.left.and.right",
                            title: Text("Tap phones to swap codes", bundle: .module))
                    }
                } footer: {
                    Text(
                        "When you're together, hold your iPhones against each other instead of sending a code. Your codes go straight from one phone to the other, and only after each of you says yes.",
                        bundle: .module)
                }
                .groupedRowSurface()
                // COPY END cdd906bc
            }

            // COPY BEGIN a018d8bc [NEEDS HUMAN REVIEW]
            Section {
                SettingsRow(
                    icon: "key.fill", tone: .device,
                    title: Text("Where your keys are", bundle: .module))
            } footer: {
                Text(
                    "Your keys are kept on this device only. A new device gets them when one of your devices approves it. If you lose every device, your recovery key is the way back — it returns you, removes every other device, and your conversations are asked for from the people who were in them.",
                    bundle: .module)
            }
            .groupedRowSurface()
            // COPY END a018d8bc
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        // COPY BEGIN 76020e40 [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("Your identity", bundle: .module))
        // COPY END 76020e40
        .toolbarTitleDisplayMode(.inline)
        .croppingPickedPhoto($pickedAvatar) { picked in await onAvatarChange?(picked) }
    }
}
