import CarpenterKit
import CarpenterMedia
import PhotosUI
import SwiftUI

struct PrivacyAndSafetySettingsView: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL

    let owner: Member
    @Binding var sharing: NameAndAvatarSharing
    @Binding var focus: FocusSharing
    @Binding var reportsDisplaying: Bool
    @Binding var blursSensitiveMedia: Bool
    let screening: ScreeningAvailability
    let onOpenSystemSettings: (() -> Void)?
    @Binding var blocksKnownAbusers: Bool
    let requiresSoloCheck: Bool
    let onRequiresSoloCheck: (Bool) async -> Void
    let requiresLongPhrase: Bool
    let onRequiresLongPhrase: (Bool) async -> Void
    let toldAboutRestores: Bool
    let onToldAboutRestores: (Bool) async -> Void
    let holdsHistoryForRestores: Bool
    let onHoldsHistoryForRestores: (Bool) async -> Void
    let asksPeersForHistory: Bool
    let onAsksPeersForHistory: (Bool) async -> Void
    let denyListUpdated: String
    let blockedPeople: [Member]
    let onUnblock: (ParticipantID) async -> Void
    let outposts: OutpostSettings

    @State private var isCheckingUp = false

    var body: some View {
        SettingsPage {
            SettingsHeaderCard(
                icon: "hand.raised.fill",
                title: Text("Privacy & Safety", bundle: .module),
                paragraph: Text(
                    "What this device tells other people, and what it does with what arrives. Every judgment here is made on this device and reaches nobody. Change any of it whenever you like; what has already been sent stays with whoever received it.",
                    bundle: .module))

            Section {
                SettingsToggle(
                    icon: "person.text.rectangle.fill", title: Text("Share my name", bundle: .module),
                    isOn: $sharing.sharesName)
                SettingsToggle(
                    icon: "person.crop.square.fill", title: Text("Share my photo", bundle: .module),
                    isOn: $sharing.sharesAvatar)
                SettingsToggle(
                    icon: "eye.fill", title: Text("Read receipts", bundle: .module),
                    isOn: $reportsDisplaying)
                SettingsToggle(
                    icon: "moon.fill", title: Text("Share when I've silenced notifications", bundle: .module),
                    isOn: $focus.sharesFocus)
                NavigationLink {
                    FocusMessageView(focus: $focus)
                } label: {
                    SettingsRow(
                        icon: "text.bubble.fill",
                        title: Text("Do Not Disturb message", bundle: .module),
                        detail: focus.usesCustomMessage && !focus.customMessage.isEmpty
                            ? Text(verbatim: focus.customMessage)
                            : Text("Do Not Disturb", bundle: .module))
                }
            } header: {
                Text("Send", bundle: .module).sectionHeading()
            } footer: {
                Text(
                    "Your name goes to the rooms you are in, as the name people see for you, once this is on; off, they see a short code. People you write to get it as the default name for you, and can call you something else on their own phone. Turning it off does not take a name back from a room that has it. Your photo goes the same way, to those rooms and to the people you let read your Outpost, and unlike a name it comes back: off, it is taken down everywhere, and their devices let it go as they next collect. Read receipts tell a sender when their message has been shown on your screen; off, they are told you do not report. Silenced notifications tells the people you write to when a Focus is on, the way Messages does, with the words you choose.",
                    bundle: .module)
            }
            .groupedRowSurface()

            Section {
                SettingsToggle(
                    icon: "person.text.rectangle.fill", title: Text("Show others' names", bundle: .module),
                    isOn: $sharing.showsOthersNames)
                SettingsToggle(
                    icon: "person.crop.square.fill", title: Text("Show others' photos", bundle: .module),
                    isOn: $sharing.showsOthersAvatars)
                SettingsToggle(
                    icon: "moon.fill", title: Text("Show others' silence", bundle: .module),
                    isOn: $focus.showsOthersFocus)
            } header: {
                Text("Receive", bundle: .module).sectionHeading()
            } footer: {
                Text(
                    "Off, every other person is shown as a short code and initials from it, even where they shared a name, and no photo of theirs is collected. On, a photo they share is drawn wherever they appear, under any photo you chose for them yourself. Others' silence puts a line over the field in a solo while the other person has a Focus on, where they share that.",
                    bundle: .module)
            }
            .groupedRowSurface()

            Section {
                Button { isCheckingUp = true } label: {
                    SettingsRow(
                        icon: "checklist", tone: .device,
                        title: Text("Run the privacy check-up", bundle: .module))
                }
            } footer: {
                Text(
                    "The questions a new member is asked, with what each answer looks like. Takes a preset or goes one switch at a time.",
                    bundle: .module)
            }
            .groupedRowSurface()

            Section {
                SettingsToggle(
                    icon: "eye.trianglebadge.exclamationmark.fill",
                    title: Text("Blur sensitive photos", bundle: .module),
                    isOn: $blursSensitiveMedia)
                if screening == .offInSystemSettings, let onOpenSystemSettings {
                    Button(action: onOpenSystemSettings) {
                        SettingsRow(
                            icon: "gear", tone: .device,
                            title: Text("Turn on Sensitive Content Warning", bundle: .module))
                    }
                }
            } footer: {
                screeningFooter
            }
            .groupedRowSurface()

            Section {
                SettingsToggle(
                    icon: "person.crop.circle.badge.checkmark",
                    title: Text("Check who I am talking to first", bundle: .module),
                    isOn: Binding(
                        get: { requiresSoloCheck },
                        set: { wanted in Task { await onRequiresSoloCheck(wanted) } }))
            } footer: {
                Text(
                    "You and anybody you talk to alone already have the same characters, from how you met. On, a conversation stays shut until you have read them to each other — and they are told you asked. Off, it opens as soon as somebody with your code writes.",
                    bundle: .module)
            }
            .groupedRowSurface()

            Section {
                SettingsToggle(
                    icon: "textformat.abc",
                    title: Text("Use a twenty-character code", bundle: .module),
                    isOn: Binding(
                        get: { requiresLongPhrase },
                        set: { wanted in Task { await onRequiresLongPhrase(wanted) } }))
            } footer: {
                Text(
                    "Ten characters is already far more than anybody could work out in the time an invitation is open. Twenty is for when you would rather not depend on that being true. It applies to everyone you meet from now on — if either of you asks for twenty, you both read twenty, and the first ten are the same characters you would have read anyway.",
                    bundle: .module)
            }
            .groupedRowSurface()

            Section {
                SettingsToggle(
                    icon: "key.horizontal.fill",
                    title: Text("Tell me when somebody sets up again", bundle: .module),
                    isOn: Binding(
                        get: { toldAboutRestores },
                        set: { wanted in Task { await onToldAboutRestores(wanted) } }))
                SettingsToggle(
                    icon: "hand.raised.fingers.spread.fill",
                    title: Text("Hold my history until I have checked", bundle: .module),
                    isOn: Binding(
                        get: { holdsHistoryForRestores },
                        set: { wanted in Task { await onHoldsHistoryForRestores(wanted) } }))
            } footer: {
                Text(
                    "Somebody who loses every device comes back with a recovery key, and their conversations come back from the people who were in them. The first decides whether you are told when one of those asks reaches you, and which conversation it was for. The second holds what was said before they lost their phone until you have read the characters to each other and said they matched — off, it goes as soon as the ask arrives. Either way they are still in your conversations, so anything said from now on still reaches them.",
                    bundle: .module)
            }
            .groupedRowSurface()

            Section {
                SettingsToggle(
                    icon: "hand.wave.fill",
                    title: Text("Ask the people I talk to for what was said", bundle: .module),
                    isOn: Binding(
                        get: { asksPeersForHistory },
                        set: { wanted in Task { await onAsksPeersForHistory(wanted) } }))
            } footer: {
                Text(
                    "This one is about your own history, not anybody else's. If you ever come back from a recovery key, your conversations return empty and this is what asks the people in them for their copy. Off, nobody is asked and nobody is told you set up again — and the only way to change your mind is here.",
                    bundle: .module)
            }
            .groupedRowSurface()

            Section {
                SettingsToggle(
                    icon: "hand.raised.slash.fill",
                    title: Text("Block known abusers", bundle: .module),
                    isOn: $blocksKnownAbusers)
                NavigationLink {
                    BlockedPeopleView(people: blockedPeople, onUnblock: onUnblock)
                } label: {
                    SettingsRow(
                        icon: "person.crop.circle.badge.xmark.fill",
                        title: Text("Blocked people", bundle: .module),
                        detail: Text("\(blockedPeople.count)", bundle: .module))
                }
            } footer: {
                Text(
                    "Known abusers is a short list shipped inside the app, last changed \(denyListUpdated). Nothing is fetched. Somebody you block is never shown, in any room, and is not told.",
                    bundle: .module)
            }
            .groupedRowSurface()

            if let form = Branding.contactFormURL {
                Section {
                    Link(destination: form) {
                        SettingsRow(
                            icon: "arrow.up.right.square.fill", tone: .device,
                            title: Text("Report a problem", bundle: .module))
                    }
                } footer: {
                    Text(
                        "Opens \(form.host() ?? "") in your browser. This app sends nothing itself and publishes no address.",
                        bundle: .module)
                }
                .groupedRowSurface()
            }
        }
        .listSurfaceHidden()
        .pageBackground()
        .navigationTitle(Text("Privacy & Safety", bundle: .module))
        .sizedSheet(isPresented: $isCheckingUp) {
            PrivacyCheckupView(
                owner: owner,
                current: PrivacyChoices(
                    sharing: sharing, focus: focus, reportsDisplaying: reportsDisplaying,
                    blursSensitiveMedia: blursSensitiveMedia, blocksKnownAbusers: blocksKnownAbusers,
                    requiresSoloCheck: requiresSoloCheck,
                    toldAboutRestores: toldAboutRestores,
                    holdsHistoryForRestores: holdsHistoryForRestores,
                    outposts: OutpostChoices(
                        consent: outposts.consent ?? .open,
                        offersReview: outposts.offersReview,
                        showsPhoto: outposts.showsPicture)),
                onFinish: { chosen in
                    sharing = chosen.sharing
                    var wantedFocus = focus
                    wantedFocus.sharesFocus = chosen.focus.sharesFocus
                    wantedFocus.showsOthersFocus = chosen.focus.showsOthersFocus
                    focus = wantedFocus
                    reportsDisplaying = chosen.reportsDisplaying
                    blursSensitiveMedia = chosen.blursSensitiveMedia
                    blocksKnownAbusers = chosen.blocksKnownAbusers
                    if chosen.requiresSoloCheck != requiresSoloCheck {
                        await onRequiresSoloCheck(chosen.requiresSoloCheck)
                    }
                    if chosen.toldAboutRestores != toldAboutRestores {
                        await onToldAboutRestores(chosen.toldAboutRestores)
                    }
                    if chosen.holdsHistoryForRestores != holdsHistoryForRestores {
                        await onHoldsHistoryForRestores(chosen.holdsHistoryForRestores)
                    }
                    if chosen.outposts.consent != outposts.consent {
                        await outposts.onConsent(chosen.outposts.consent)
                    }
                    if chosen.outposts.offersReview != outposts.offersReview {
                        await outposts.onReview(chosen.outposts.offersReview)
                    }
                    if chosen.outposts.showsPhoto != outposts.showsPicture {
                        await outposts.onShowsPicture(chosen.outposts.showsPhoto)
                    }
                    isCheckingUp = false
                })
        }
        .toolbarTitleDisplayMode(.inline)
    }

    private var screeningFooter: Text {
        switch screening {
        case .available:
            Text(
                "Photos the system judges sensitive are blurred until you choose to look. The judgment is made on this device; nothing about the photo leaves it.",
                bundle: .module)
        case .offInSystemSettings:
            Text(
                "Blurring needs the system's own Sensitive Content Warning, which is off. Until it is on, photos are not screened, and this app does not claim they were. It is under Settings › Privacy & Security.",
                bundle: .module)
        case .unsupported:
            Text(
                "This device cannot screen photos. They are not screened, and this app does not claim they were.",
                bundle: .module)
        }
    }
}
