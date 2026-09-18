import CarpenterKit
import SwiftUI

// MARK: - A preset, shown

struct PresetPage: View {
    @Environment(\.palette) private var palette
    @Environment(\.ownAvatar) private var ownAvatar

    let preset: PrivacyCheckupView.Preset
    let owner: Member
    let finishing: Bool
    let onConfirm: () -> Void

    private var choices: PrivacyChoices { preset.choices }

    var body: some View {
        SettingsPage {
            switch preset {
            case .familiar:
                SettingsHeaderCard(
                    icon: "person.2.fill",
                    title: Text("Familiar and open", bundle: .module),
                    paragraph: Text(
                        "The way Messages works. People in your rooms see your name and photo, you see theirs, and the people you write to know when you have notifications silenced. Read receipts stay off either way — Messages does not show them until you ask, and neither do we.",
                        bundle: .module))
            case .lockedDown:
                SettingsHeaderCard(
                    icon: "lock.fill",
                    title: Text("Locked down", bundle: .module),
                    paragraph: Text(
                        "As little as possible. You are a short code to everyone with no photo, everyone is a short code to you, senders are told you do not report, and nobody learns when you have a Focus on. A conversation with one person stays shut until the two of you have read the same characters to each other — yours included, the ones you already have.",
                        bundle: .module))
            }

            ExampleCard(caption: Text("How you appear to others", bundle: .module)) {
                SeenAsRow(
                    person: choices.sharing.sharesName ? owner : Member.placeholder(owner.id),
                    isAccented: true, photo: choices.sharing.sharesAvatar ? ownAvatar : nil)
            }
            ExampleCard(caption: Text("How others appear to you", bundle: .module)) {
                SeenAsRow(
                    person: Sample.other(named: choices.sharing.showsOthersNames), isAccented: false,
                    wearsTheMark: choices.sharing.showsOthersAvatars)
            }
            ExampleCard(caption: Text("What a sender sees under their message", bundle: .module)) {
                ReceiptExample(reports: choices.reportsDisplaying)
            }
            ExampleCard(caption: Text("What they see over the field while you have a Focus on", bundle: .module)) {
                FocusExample(shared: choices.focus.sharesFocus)
            }

            Section {
                EmptyView()
            } footer: {
                Text(
                    "Blurring sensitive photos and blocking known abusers stay on; both can be turned off under Privacy & Safety.",
                    bundle: .module)
            }
        }
        .listSurfaceHidden()
        .pageBackground()
        .toolbarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(action: onConfirm) {
                Text("Use these settings", bundle: .module).primaryAction()
            }
            .prominentActionButton()
            .disabled(finishing)
            .padding(.horizontal, CarpenterMetrics.screenMargin)
            .padding(.vertical, 10)
            .pageBackground()
        }
    }
}

// MARK: - One switch, shown

struct StepPage: View {
    @Environment(\.palette) private var palette
    @Environment(\.ownAvatar) private var ownAvatar

    let step: PrivacyCheckupView.Step
    let owner: Member
    @Binding var choices: PrivacyChoices
    let finishing: Bool
    let onNext: () -> Void

    var body: some View {
        SettingsPage {
            header

            example

            Section {
                switch step {
                case .shareName:
                    SettingsToggle(
                        icon: "person.text.rectangle.fill",
                        title: Text("Share my name", bundle: .module),
                        isOn: $choices.sharing.sharesName)
                case .sharePhoto:
                    SettingsToggle(
                        icon: "person.crop.square.fill",
                        title: Text("Share my photo", bundle: .module),
                        isOn: $choices.sharing.sharesAvatar)
                case .shareFocus:
                    SettingsToggle(
                        icon: "moon.fill",
                        title: Text("Share when I've silenced notifications", bundle: .module),
                        isOn: $choices.focus.sharesFocus)
                case .showOthersNames:
                    SettingsToggle(
                        icon: "person.text.rectangle.fill",
                        title: Text("Show others' names", bundle: .module),
                        isOn: $choices.sharing.showsOthersNames)
                case .showOthersPhotos:
                    SettingsToggle(
                        icon: "person.crop.square.fill",
                        title: Text("Show others' photos", bundle: .module),
                        isOn: $choices.sharing.showsOthersAvatars)
                case .showOthersFocus:
                    SettingsToggle(
                        icon: "moon.fill",
                        title: Text("Show others' silence", bundle: .module),
                        isOn: $choices.focus.showsOthersFocus)
                case .readReceipts:
                    SettingsToggle(
                        icon: "eye.fill",
                        title: Text("Read receipts", bundle: .module),
                        isOn: $choices.reportsDisplaying)
                case .blurSensitive:
                    SettingsToggle(
                        icon: "eye.trianglebadge.exclamationmark.fill",
                        title: Text("Blur sensitive photos", bundle: .module),
                        isOn: $choices.blursSensitiveMedia)
                case .blockKnownAbusers:
                    SettingsToggle(
                        icon: "hand.raised.slash.fill",
                        title: Text("Block known abusers", bundle: .module),
                        isOn: $choices.blocksKnownAbusers)
                case .soloCheck:
                    SettingsToggle(
                        icon: "person.crop.circle.badge.checkmark",
                        title: Text("Check who I am talking to first", bundle: .module),
                        isOn: $choices.requiresSoloCheck)
                case .restoreAsks:
                    SettingsToggle(
                        icon: "key.horizontal.fill",
                        title: Text("Tell me when somebody sets up again", bundle: .module),
                        isOn: $choices.toldAboutRestores)
                case .restoreHold:
                    SettingsToggle(
                        icon: "hand.raised.fingers.spread.fill",
                        title: Text("Hold my history until I have checked", bundle: .module),
                        isOn: $choices.holdsHistoryForRestores)
                case .outpostsOn:
                    SettingsToggle(
                        icon: "rectangle.stack.fill",
                        title: Text("Use Outposts", bundle: .module),
                        isOn: $choices.outposts.isOn)
                case .outpostReach:
                    ForEach([OutpostConsent.open, .closed, .quiet], id: \.self) { standing in
                        ChoiceRow(
                            title: OutpostConsentCopy.title(of: standing),
                            detail: OutpostConsentCopy.detail(of: standing),
                            isSelected: choices.outposts.consent == standing,
                            action: { choices.outposts.consent = standing })
                    }
                case .outpostFace:
                    SettingsToggle(
                        icon: "person.crop.square.fill",
                        title: Text("Show my picture there", bundle: .module),
                        isOn: $choices.outposts.showsPhoto)
                case .outpostReview:
                    SettingsToggle(
                        icon: "person.crop.circle.badge.questionmark.fill",
                        title: Text("Ask about people I meet", bundle: .module),
                        isOn: $choices.outposts.offersReview)
                }
            } footer: {
                let place = step.position(under: choices)
                Text("\(place.at) of \(place.of)", bundle: .module)
            }
            .groupedRowSurface()
        }
        .listSurfaceHidden()
        .pageBackground()
        .toolbarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(action: onNext) {
                (step.next(under: choices) == nil
                    ? Text("Finish", bundle: .module) : Text("Next", bundle: .module))
                    .primaryAction()
            }
            .prominentActionButton()
            .disabled(finishing)
            .padding(.horizontal, CarpenterMetrics.screenMargin)
            .padding(.vertical, 10)
            .pageBackground()
        }
    }

    @ViewBuilder
    private var header: some View {
        switch step {
        case .shareName:
            SettingsHeaderCard(
                icon: "person.text.rectangle.fill",
                title: Text("Share my name", bundle: .module),
                paragraph: Text(
                    "Your name goes to the rooms you are in, as the default name people see for you; they can call you something else on their own phone. Off, they see a short code. Turning it off later does not take a name back from a room that already has it.",
                    bundle: .module))
        case .sharePhoto:
            SettingsHeaderCard(
                icon: "person.crop.square.fill",
                title: Text("Share my photo", bundle: .module),
                paragraph: Text(
                    "The photo you pick on You goes to the people you share rooms with, and to the people you let read your Outpost, once this is on. Off, it is taken down, and their devices let it go as they next collect.",
                    bundle: .module))
        case .shareFocus:
            SettingsHeaderCard(
                icon: "moon.fill",
                title: Text("Share when I've silenced notifications", bundle: .module),
                paragraph: Text(
                    "Tells the people you write to when you have a Focus on, the way Messages does, so they do not wait on a reply that is not coming. The system asks your permission first. The words are yours to choose under Privacy & Safety.",
                    bundle: .module))
        case .showOthersNames:
            SettingsHeaderCard(
                icon: "person.text.rectangle.fill",
                title: Text("Show others' names", bundle: .module),
                paragraph: Text(
                    "People who share their name are drawn by it. Off, everyone is a short code and two characters of it on a disc, whatever they chose to share.",
                    bundle: .module))
        case .showOthersPhotos:
            SettingsHeaderCard(
                icon: "person.crop.square.fill",
                title: Text("Show others' photos", bundle: .module),
                paragraph: Text(
                    "A photo somebody shares is collected and drawn wherever they appear, under any photo you chose for them yourself. Off, nothing of theirs is collected and everyone is initials on a disc.",
                    bundle: .module))
        case .showOthersFocus:
            SettingsHeaderCard(
                icon: "moon.fill",
                title: Text("Show others' silence", bundle: .module),
                paragraph: Text(
                    "A line over the field in a solo while the other person has a Focus on, where they share that. Off, nothing is drawn, whatever they share.",
                    bundle: .module))
        case .readReceipts:
            SettingsHeaderCard(
                icon: "eye.fill",
                title: Text("Read receipts", bundle: .module),
                paragraph: Text(
                    "Tells a sender when their message has been shown on your screen. Off, they are told you do not report, rather than left waiting for a mark that never comes.",
                    bundle: .module))
        case .blurSensitive:
            SettingsHeaderCard(
                icon: "eye.trianglebadge.exclamationmark.fill",
                title: Text("Blur sensitive photos", bundle: .module),
                paragraph: Text(
                    "Photos the system judges sensitive are blurred until you choose to look. The judgment is made on this device; nothing about the photo leaves it.",
                    bundle: .module))
        case .blockKnownAbusers:
            SettingsHeaderCard(
                icon: "hand.raised.slash.fill",
                title: Text("Block known abusers", bundle: .module),
                paragraph: Text(
                    "A short list shipped inside the app. Nothing is fetched. Somebody on it is never shown, in any room, and is not told.",
                    bundle: .module))
        case .soloCheck:
            SettingsHeaderCard(
                icon: "person.crop.circle.badge.checkmark",
                title: Text("One conversation, one person", bundle: .module),
                paragraph: Text(
                    "You and anybody you talk to alone already have the same characters, worked out from how you met. Off, a conversation opens as soon as somebody who has your code writes — what Messages does. On, it stays shut until the two of you have read those characters to each other and said they matched. They are told you are waiting, and either of you can ask again at any time.",
                    bundle: .module))
        case .restoreAsks:
            SettingsHeaderCard(
                icon: "key.horizontal.fill",
                title: Text("When somebody comes back", bundle: .module),
                paragraph: Text(
                    "Somebody who loses every device can come back with a recovery key. It makes them them again, and nothing else — so their conversations come back from the people who were in them, which means from you. Your history goes either way. This only decides whether you are told it happened, and which conversation was asked for.",
                    bundle: .module))
        case .restoreHold:
            SettingsHeaderCard(
                icon: "hand.raised.fingers.spread.fill",
                title: Text("Before your history goes back", bundle: .module),
                paragraph: Text(
                    "Off, your copy goes as soon as the ask arrives — what Messages would do, and what most people want. On, it waits. You are shown the characters the two of you already share, you read them to each other on a line you trust, and none of it goes until you say it matched. This covers what was said before they lost their phone; they are still in your conversations, so anything said from now on still reaches them. The cost is that somebody who has genuinely lost their phone waits for you to pick up.",
                    bundle: .module))
        case .outpostsOn:
            SettingsHeaderCard(
                icon: "rectangle.stack.fill",
                title: Text("Outposts", bundle: .module),
                paragraph: Text(
                    "An Outpost is a page of your own. You choose who reads it, one person at a time, and nobody is let in until you say so — sharing a room grants nothing. Off, the tab goes away and nothing is written or fetched for one.",
                    bundle: .module))
        case .outpostReach:
            SettingsHeaderCard(
                icon: "bubble.left.and.text.bubble.right.fill",
                title: Text("What you write on other people's", bundle: .module),
                paragraph: Text(
                    "Everybody who can read a post can read every comment under it — otherwise a thread has holes in it. Some of those readers are people you have never met. This decides how far your own comments go. None of it touches your Outpost: who reads that is still yours to decide, one person at a time.",
                    bundle: .module))
        case .outpostFace:
            SettingsHeaderCard(
                icon: "person.crop.square.fill",
                title: Text("Your picture on your Outpost", bundle: .module),
                paragraph: Text(
                    "The photo you pick on You is drawn at the top of your Outpost as well, without your choosing a second one — and you can choose a different one there whenever you like. Off, your Outpost draws your initials and the rooms you are in are unchanged. Either way a reader is only ever sent a picture where Share my photo is on.",
                    bundle: .module))
        case .outpostReview:
            SettingsHeaderCard(
                icon: "person.crop.circle.badge.questionmark.fill",
                title: Text("Being asked about people you meet", bundle: .module),
                paragraph: Text(
                    "When you end up in a room with somebody new, the room can ask once whether to let them read your Outpost. Off, nobody is ever offered it and you add readers yourself. Either way, nobody is let in until you say so — this only decides whether you are asked.",
                    bundle: .module))
        }
    }

    @ViewBuilder
    private var example: some View {
        switch step {
        case .shareName:
            ExampleCard(caption: Text("How you appear to others", bundle: .module)) {
                SeenAsRow(
                    person: choices.sharing.sharesName ? owner : Member.placeholder(owner.id),
                    isAccented: true, photo: choices.sharing.sharesAvatar ? ownAvatar : nil)
            }
        case .sharePhoto:
            ExampleCard(caption: Text("How you appear to others", bundle: .module)) {
                VStack(alignment: .leading, spacing: 8) {
                    SeenAsRow(
                        person: choices.sharing.sharesName ? owner : Member.placeholder(owner.id),
                        isAccented: true, photo: choices.sharing.sharesAvatar ? ownAvatar : nil)
                    if choices.sharing.sharesAvatar, ownAvatar == nil {
                        Text("You have no photo yet. Pick one on You and it goes with your name.", bundle: .module)
                            .font(CarpenterFont.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
            }
        case .shareFocus:
            ExampleCard(caption: Text("What they see over the field while you have a Focus on", bundle: .module)) {
                FocusExample(shared: choices.focus.sharesFocus)
            }
        case .showOthersNames:
            ExampleCard(caption: Text("How others appear to you", bundle: .module)) {
                SeenAsRow(person: Sample.other(named: choices.sharing.showsOthersNames), isAccented: false)
            }
        case .showOthersPhotos:
            ExampleCard(caption: Text("How others appear to you", bundle: .module)) {
                VStack(alignment: .leading, spacing: 8) {
                    SeenAsRow(
                        person: Sample.other(named: choices.sharing.showsOthersNames), isAccented: false,
                        wearsTheMark: choices.sharing.showsOthersAvatars)
                    Text(
                        choices.sharing.showsOthersAvatars
                            ? "Their photo, where they share one."
                            : "Initials, whatever they share.",
                        bundle: .module
                    )
                    .font(CarpenterFont.caption)
                    .foregroundStyle(palette.secondaryText)
                }
            }
        case .showOthersFocus:
            ExampleCard(caption: Text("What you see over the field while they have a Focus on", bundle: .module)) {
                FocusExample(shared: choices.focus.showsOthersFocus)
            }
        case .readReceipts:
            ExampleCard(caption: Text("What a sender sees under their message", bundle: .module)) {
                ReceiptExample(reports: choices.reportsDisplaying)
            }
        case .blurSensitive:
            ExampleCard(caption: Text("A photo the system judged sensitive", bundle: .module)) {
                BlurExample(blurred: choices.blursSensitiveMedia)
            }
        case .blockKnownAbusers:
            ExampleCard(caption: Text("Somebody on the list, in a room you share", bundle: .module)) {
                BlockExample(blocked: choices.blocksKnownAbusers)
            }
        case .soloCheck:
            ExampleCard(caption: Text("A conversation with somebody new", bundle: .module)) {
                SoloCheckExample(required: choices.requiresSoloCheck)
            }
        case .restoreAsks:
            ExampleCard(caption: Text("When one of their asks reaches you", bundle: .module)) {
                RestoreAskExample(told: choices.toldAboutRestores)
            }
        case .restoreHold:
            ExampleCard(caption: Text("In the conversation they asked about", bundle: .module)) {
                RestoreHoldExample(holding: choices.holdsHistoryForRestores)
            }
        case .outpostsOn:
            ExampleCard(caption: Text("Along the bottom of the app", bundle: .module)) {
                TabExample(present: choices.outposts.isOn)
            }
        case .outpostReach:
            ExampleCard(caption: Text("Who reads a comment you leave on somebody's post", bundle: .module)) {
                ReachExample(consent: choices.outposts.consent)
            }
        case .outpostFace:
            ExampleCard(caption: Text("The top of your own Outpost", bundle: .module)) {
                VStack(alignment: .leading, spacing: 8) {
                    SeenAsRow(
                        person: choices.sharing.sharesName ? owner : Member.placeholder(owner.id),
                        isAccented: true,
                        photo: choices.outposts.showsPhoto ? ownAvatar : nil)
                    if choices.outposts.showsPhoto, ownAvatar == nil {
                        Text("You have no photo yet. Pick one on You and your Outpost takes it.", bundle: .module)
                            .font(CarpenterFont.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                    if choices.outposts.showsPhoto, !choices.sharing.sharesAvatar {
                        Text("This is your own screen. With Share my photo off, no reader is sent it.", bundle: .module)
                            .font(CarpenterFont.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
            }
        case .outpostReview:
            ExampleCard(caption: Text("When you end up in a room with somebody new", bundle: .module)) {
                ReviewExample(asks: choices.outposts.offersReview)
            }
        }
    }
}
