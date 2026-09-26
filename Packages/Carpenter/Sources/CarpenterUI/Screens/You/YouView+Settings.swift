import CarpenterKit
import CarpenterMedia
import SwiftUI

// MARK: The settings this tab lists, and the pages behind them

extension YouView {
    var masthead: some View {
        AnimatedMark(size: 68)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, -AnimatedMark.touchInset)
            .padding(.bottom, 4)
    }

    var identityRow: some View {
        NavigationLink {
            IdentitySettingsView(
                owner: owner, fingerprint: fingerprint, identityCode: identityCode,
                onRename: onRename, onAvatarChange: onAvatarChange)
        } label: {
            HStack(spacing: 12) {
                AvatarView(initials: owner.initials, diameter: 44, isAccented: true, image: ownAvatar)
                    .supporterBadge(supporter?.showsBadge == true, onAvatarOf: 44)
                    .overlay(alignment: .bottomTrailing) {
                        if supporter?.showsBadge != true, onRename != nil || onAvatarChange != nil {
                            Image(systemName: "pencil")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(palette.accentFill, in: .circle)
                                .overlay(Circle().strokeBorder(palette.contentSurface, lineWidth: 2))
                                .offset(x: 3, y: 3)
                                .accessibilityHidden(true)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(owner.displayName)
                        .font(CarpenterFont.rowTitle)
                        .foregroundStyle(palette.primaryText)
                    Text(fingerprint)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(palette.tertiaryText)
                }
            }
            .padding(.vertical, 4)
        }
    }

    var reachingYou: some View {
        Section {
            // COPY BEGIN e27d2cdb [NEEDS HUMAN REVIEW]
            if let notifications {
                NavigationLink {
                    NotificationsView(settings: notifications)
                } label: {
                    SettingsRow(
                        icon: "bell.badge.fill",
                        title: Text("Notifications", bundle: .module),
                        detail: Text(
                            "\(notifications.messaging.wantsMessages ? 1 : 0)", bundle: .module))
                }
            }
            // COPY END e27d2cdb
            NavigationLink {
                PrivacyAndSafetySettingsView(
                    owner: owner,
                    sharing: $sharing,
                    focus: $focus,
                    reportsDisplaying: $reportsDisplaying,
                    blursSensitiveMedia: $blursSensitiveMedia,
                    screening: screening,
                    onOpenSystemSettings: onOpenSystemSettings,
                    blocksKnownAbusers: $blocksKnownAbusers,
                    requiresSoloCheck: requiresSoloCheck,
                    onRequiresSoloCheck: onRequiresSoloCheck,
                    requiresLongPhrase: requiresLongPhrase,
                    onRequiresLongPhrase: onRequiresLongPhrase,
                    toldAboutRestores: toldAboutRestores,
                    onToldAboutRestores: onToldAboutRestores,
                    holdsHistoryForRestores: holdsHistoryForRestores,
                    onHoldsHistoryForRestores: onHoldsHistoryForRestores,
                    asksPeersForHistory: asksPeersForHistory,
                    onAsksPeersForHistory: onAsksPeersForHistory,
                    denyListUpdated: denyListUpdated,
                    blockedPeople: blockedPeople,
                    onUnblock: onUnblock,
                    outposts: outpostSettings)
            } label: {
                // COPY BEGIN 798dd04d [NEEDS HUMAN REVIEW]
                SettingsRow(
                    icon: "hand.raised.fill",
                    title: Text("Privacy & Safety", bundle: .module))
            }
            NavigationLink {
                DeviceListView(
                    devices: devices, onRevoke: onRevokeDevice, onPair: onPairDevice,
                    onRename: onRenameDevice)
            } label: {
                SettingsRow(
                    icon: "ipad.and.iphone",
                    title: Text("Devices", bundle: .module),
                    detail: Text("\(devices.filter(\.isActive).count)", bundle: .module))
            }
                // COPY END 798dd04d
        }
        .groupedRowSurface()
    }

    var outpost: some View {
        Section {
            // COPY BEGIN df1b987c [NEEDS HUMAN REVIEW]
            NavigationLink(value: owner.id) {
                SettingsRow(
                    icon: "rectangle.stack.fill",
                    title: Text("Your Outpost", bundle: .module),
                    detail: Text("^[\(postCount) post](inflect: true)", bundle: .module))
            }
            NavigationLink {
                OutpostSettingsView(outpostSettings)
            } label: {
                SettingsRow(
                    icon: "text.bubble.fill",
                    title: Text("Outpost settings", bundle: .module))
            }
            // COPY END df1b987c
        }
        .groupedRowSurface()
    }

    var howItLooks: some View {
        Section {
            // COPY BEGIN b87e2993 [NEEDS HUMAN REVIEW]
            NavigationLink {
                AppearanceSettingsView(
                    accent: $accent, inbox: $inbox, appIcon: $appIcon,
                    appIconIsSupported: appIconIsSupported, tagCount: tagCount,
                    showsAvatars: $showsAvatars)
            } label: {
                SettingsRow(
                    icon: "paintpalette.fill",
                    title: Text("Appearance", bundle: .module),
                    detail: Text(accent.displayName),
                    swatch: true)
            }
            NavigationLink {
                BehaviourSettingsView(playsHaptics: $playsHaptics, tutorialMode: $tutorialMode)
            } label: {
                SettingsRow(
                    icon: "hand.tap.fill",
                    title: Text("Behavior", bundle: .module))
            }
            // COPY END b87e2993
        }
        .groupedRowSurface()
    }

    var thisDevice: some View {
        Section {
            // COPY BEGIN 07edb102 [NEEDS HUMAN REVIEW]
            SettingsRow(
                icon: "internaldrive.fill", tone: .device,
                title: Text("Storage", bundle: .module),
                detail: mediaBytes.map {
                    Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file))
                })
            if let recoveryKey {
                NavigationLink {
                    RecoveryKeyView(
                        text: recoveryKey.text(), fingerprint: recoveryKey.fingerprint,
                        isFirstTime: false, onSaved: recoveryKey.onSaved)
                } label: {
                    SettingsRow(
                        icon: recoveryKey.savedAt == nil
                            ? "exclamationmark.triangle.fill" : "key.horizontal.fill",
                        tone: recoveryKey.savedAt == nil ? .destructive : .device,
                        title: Text("Recovery key", bundle: .module),
                        detail: recoveryKey.savedAt.map {
                            Text(
                                "Last saved \($0.formatted(date: .abbreviated, time: .omitted))",
                                bundle: .module)
                        } ?? Text("Never saved", bundle: .module))
                }
            }
            NavigationLink {
                IntegrityView(report: integrity)
            } label: {
                SettingsRow(
                    icon: integrity.isClean ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                    tone: integrity.isClean ? .device : .destructive,
                    title: Text("History check", bundle: .module),
                    detail: integrity.isClean
                        ? Text("Nothing wrong", bundle: .module)
                        : Text("Needs a look", bundle: .module))
            }
            if hiddenMessageCount > 0 {
                Button {
                    Task { await onRevealHidden() }
                } label: {
                    SettingsRow(
                        icon: "eye.fill", tone: .device,
                        title: Text("Show hidden messages", bundle: .module),
                        detail: Text("\(hiddenMessageCount)", bundle: .module))
                }
            }
        } footer: {
            Text(
                "Photos and clips you receive stay on this device, sealed, until you erase everything.",
                bundle: .module)
            // COPY END 07edb102
        }
        .groupedRowSurface()
    }

    var gettingHelp: some View {
        Section {
            // COPY BEGIN 93d36060 [NEEDS HUMAN REVIEW]
            NavigationLink {
                HowItWorksView()
            } label: {
                SettingsRow(
                    icon: "questionmark.circle.fill", tone: .device,
                    title: Text("How this works", bundle: .module))
            }
            Button {
                openURL(Self.subscribeByEmail)
            } label: {
                SettingsRow(
                    icon: "envelope.fill", tone: .device,
                    title: Text("Get product updates", bundle: .module))
            }
            // COPY END 93d36060
            #if DEBUG
            if let debugActions {
                NavigationLink {
                    DebugMenuView(
                        actions: debugActions,
                        demoConversation: $demoConversation,
                        demoParticipants: $demoParticipants,
                        demoOutpost: $demoOutpost,
                        blursEveryPhoto: $debugBlursEveryPhoto,
                        showsMessageDelay: $showsMessageDelay)
                } label: {
                    SettingsRow(
                        icon: "ladybug.fill", tone: .device,
                        title: Text("Debug", bundle: .module))
                }
            }
            #endif
        }
        .groupedRowSurface()
    }

    var erase: some View {
        Section {
            Button(role: .destructive) {
                erasing = true
            } label: {
                // COPY BEGIN f952e135 [NEEDS HUMAN REVIEW]
                HStack(spacing: 12) {
                    IconTile(fill: palette.destructiveFill) {
                        Image("NukeMark", bundle: .module)
                            .resizable()
                            .scaledToFit()
                            .padding(3)
                    }
                    Text("Erase everything", bundle: .module)
                        .foregroundStyle(palette.destructive)
                }
                // COPY END f952e135
            }
            .tint(palette.destructive)
        } footer: {
            // COPY BEGIN 8a7d8ae2 [NEEDS HUMAN REVIEW]
            Text(
                "Removes your member and everything this Apple Account holds in iCloud, on every device. It cannot remove what you already sent from anybody else's.",
                bundle: .module)
            // COPY END 8a7d8ae2
        }
        .groupedRowSurface()
    }
}
