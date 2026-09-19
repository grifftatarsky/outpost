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
            if let notifications {
                NavigationLink {
                    notificationsScreen
                } label: {
                    SettingsRow(
                        icon: "bell.badge.fill",
                        title: Text("Notifications", bundle: .module),
                        detail: Text(
                            "\(notifications.messaging.wantsMessages ? 1 : 0)", bundle: .module))
                }
            }
            NavigationLink {
                privacyScreen
            } label: {
                SettingsRow(
                    icon: "hand.raised.fill",
                    title: Text("Privacy & Safety", bundle: .module))
            }
            NavigationLink {
                devicesScreen
            } label: {
                SettingsRow(
                    icon: "ipad.and.iphone",
                    title: Text("Devices", bundle: .module),
                    detail: Text("\(devices.filter(\.isActive).count)", bundle: .module))
            }
        }
        .groupedRowSurface()
    }

    @ViewBuilder
    var notificationsScreen: some View {
        if let notifications {
            NotificationsView(settings: notifications)
        }
    }

    var privacyScreen: some View {
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
    }

    var devicesScreen: some View {
        DeviceListView(
            devices: devices, onRevoke: onRevokeDevice, onPair: onPairDevice,
            onRename: onRenameDevice)
    }

    var yourOutpostRow: some View {
        NavigationLink(value: owner.id) {
            SettingsRow(
                icon: "rectangle.stack.fill",
                title: Text("Your Outpost", bundle: .module),
                detail: Text("^[\(postCount) post](inflect: true)", bundle: .module))
        }
    }

    var outpostSettingsScreen: some View {
        OutpostSettingsView(outpostSettings)
    }

    var outpost: some View {
        Section {
            yourOutpostRow
            NavigationLink {
                outpostSettingsScreen
            } label: {
                SettingsRow(
                    icon: "text.bubble.fill",
                    title: Text("Outpost settings", bundle: .module))
            }
        }
        .groupedRowSurface()
    }

    var howItLooks: some View {
        Section {
            NavigationLink {
                appearanceScreen
            } label: {
                SettingsRow(
                    icon: "paintpalette.fill",
                    title: Text("Appearance", bundle: .module),
                    detail: Text(accent.displayName),
                    swatch: true)
            }
            NavigationLink {
                behaviourScreen
            } label: {
                SettingsRow(
                    icon: "hand.tap.fill",
                    title: Text("Behavior", bundle: .module))
            }
        }
        .groupedRowSurface()
    }

    var appearanceScreen: some View {
        AppearanceSettingsView(
            accent: $accent, inbox: $inbox, appIcon: $appIcon,
            appIconIsSupported: appIconIsSupported, tagCount: tagCount,
            showsAvatars: $showsAvatars)
    }

    var behaviourScreen: some View {
        BehaviourSettingsView(playsHaptics: $playsHaptics, tutorialMode: $tutorialMode)
    }

    var thisDevice: some View {
        Section {
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
        }
        .groupedRowSurface()
    }

    var gettingHelp: some View {
        Section {
            NavigationLink {
                HowItWorksView()
            } label: {
                SettingsRow(
                    icon: "questionmark.circle.fill", tone: .device,
                    title: Text("How this works", bundle: .module))
            }
            if let blog = Branding.blogURL {
                Button {
                    openURL(blog)
                } label: {
                    SettingsRow(
                        icon: "newspaper.fill", tone: .device,
                        title: Text("What's new", bundle: .module))
                }
            }
            #if DEBUG
            if debugActions != nil {
                NavigationLink {
                    debugScreen
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

    #if DEBUG
        @ViewBuilder
        var debugScreen: some View {
            if let debugActions {
                DebugMenuView(
                    actions: debugActions,
                    demoConversation: $demoConversation,
                    demoParticipants: $demoParticipants,
                    demoOutpost: $demoOutpost,
                    blursEveryPhoto: $debugBlursEveryPhoto,
                    showsMessageDelay: $showsMessageDelay)
            }
        }
    #endif

    var erase: some View {
        Section {
            #if os(macOS)
                Button(role: .destructive) {
                    erasing = true
                } label: {
                    Text("Erase everything…", bundle: .module)
                }
                .buttonStyle(.bordered)
            #else
                Button(role: .destructive) {
                    erasing = true
                } label: {
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
                }
                .tint(palette.destructive)
            #endif
        } footer: {
            Text(
                "Removes your member and everything this Apple Account holds in iCloud, on every device. It cannot remove what you already sent from anybody else's.",
                bundle: .module)
        }
        .groupedRowSurface()
    }
}
