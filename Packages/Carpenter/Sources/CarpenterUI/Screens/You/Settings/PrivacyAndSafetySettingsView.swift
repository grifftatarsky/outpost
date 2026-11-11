import CarpenterKit
import CarpenterMedia
import PhotosUI
import SwiftUI

struct PrivacyAndSafetySettingsView: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @AppStorage(OtherKeyboards.key) private var otherKeyboards = false

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
        List {
            // COPY BEGIN 7f55c807 [NEEDS HUMAN REVIEW]
            SettingsHeaderCard(
                icon: "hand.raised.fill",
                title: Text("Privacy & Safety", bundle: .module),
                paragraph: Text(
                    "What this device tells other people, and what it does with what arrives. Every judgment here is made on this device and reaches nobody. Change any of it whenever you like; what has already been sent stays with whoever received it.",
                    bundle: .module))
            // COPY END 7f55c807

            // COPY BEGIN 80171c59 [NEEDS HUMAN REVIEW]
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
                    "Share my name sends your name to the rooms you're in. When it's off, people see a short code, and a room that already has your name keeps it. Share my photo sends your photo to those rooms and to the people you let read your Outpost. Turning it off takes the photo down everywhere. Read receipts tell a sender when their message has been shown on your screen. Sharing when you've silenced notifications tells the people you write to when a Focus is on, with the words you choose.",
                    bundle: .module)
            }
            .groupedRowSurface()
            // COPY END 80171c59

            // COPY BEGIN 2dc93f05 [NEEDS HUMAN REVIEW]
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
                    "When names are off, everyone appears as a short code, even if they shared a name. When photos are off, no shared photo is downloaded. A photo you chose for somebody yourself always comes first. Others' silence shows a line above the message field in a solo while the other person has a Focus on, if they share that.",
                    bundle: .module)
            }
            .groupedRowSurface()
            // COPY END 2dc93f05

            // COPY BEGIN 40a7e7f2 [NEEDS HUMAN REVIEW]
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
            // COPY END 40a7e7f2

            Section {
                // COPY BEGIN 5b968939 [NEEDS HUMAN REVIEW]
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
                // COPY END 5b968939
            } footer: {
                screeningFooter
            }
            .groupedRowSurface()

            // COPY BEGIN 8473ea72 [NEEDS HUMAN REVIEW]
            Section {
                SettingsToggle(
                    icon: "person.crop.circle.badge.checkmark",
                    title: Text("Check who I am talking to first", bundle: .module),
                    isOn: Binding(
                        get: { requiresSoloCheck },
                        set: { wanted in Task { await onRequiresSoloCheck(wanted) } }))
            } footer: {
                Text(
                    "You and anybody you talk to alone share a set of characters from how you met. When this is on, a conversation stays closed until you've read them to each other, and the other person is told you asked. When it's off, a conversation opens as soon as somebody with your code writes.",
                    bundle: .module)
            }
            .groupedRowSurface()
            // COPY END 8473ea72

            // COPY BEGIN 8edfd454 [NEEDS HUMAN REVIEW]
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
            // COPY END 8edfd454

            // COPY BEGIN d5427ed4 [NEEDS HUMAN REVIEW]
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
                    "Somebody who loses every device comes back with a recovery key, and their conversations come back from the people who were in them. The first setting tells you when one of those requests reaches you, and which conversation it's for. The second holds what was said before they lost their phone until you've read the characters to each other and said they matched. When it's off, your copy is sent as soon as the request arrives. Either way, anything said from now on still reaches them.",
                    bundle: .module)
            }
            .groupedRowSurface()
            // COPY END d5427ed4

            // COPY BEGIN cd652188 [NEEDS HUMAN REVIEW]
            Section {
                SettingsToggle(
                    icon: "hand.wave.fill",
                    title: Text("Ask the people I talk to for what was said", bundle: .module),
                    isOn: Binding(
                        get: { asksPeersForHistory },
                        set: { wanted in Task { await onAsksPeersForHistory(wanted) } }))
            } footer: {
                Text(
                    "This is about your own history. If you come back with a recovery key, your conversations start empty, and this asks the people in them for their copies. When it's off, nobody is asked and nobody is told you set up again. You can change this only here.",
                    bundle: .module)
            }
            .groupedRowSurface()
            // COPY END cd652188

            // COPY BEGIN b6505bb1 [NEEDS HUMAN REVIEW]
            Section {
                SettingsToggle(
                    icon: "keyboard.fill",
                    title: Text("Keyboards from other apps", bundle: .module),
                    isOn: $otherKeyboards)
            } footer: {
                Text(
                    "A keyboard from another app can see everything you type with it. A change applies the next time you open the app.",
                    bundle: .module)
            }
            .groupedRowSurface()
            // COPY END b6505bb1

            // COPY BEGIN d4b10496 [NEEDS HUMAN REVIEW]
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
                    "Known abusers is a short list shipped inside the app, last changed \(denyListUpdated). Nothing is fetched. Somebody on it is never shown, in any room, and is not told.",
                    bundle: .module)
            }
            .groupedRowSurface()
            // COPY END d4b10496

            // COPY BEGIN a3421a78 [NEEDS HUMAN REVIEW]
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
            // COPY END a3421a78
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        // COPY BEGIN 3801b675 [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("Privacy & Safety", bundle: .module))
        // COPY END 3801b675
        .sheet(isPresented: $isCheckingUp) {
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

    // COPY BEGIN d699ba95 [NEEDS HUMAN REVIEW]
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
    // COPY END d699ba95
}
