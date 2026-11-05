#if DEBUG

    import CarpenterKit
    import SwiftUI

    enum ScreenShots {
        @MainActor @ViewBuilder
        static func view(of shot: CopyShot) -> some View {
            switch shot {
            case .members:
                NavigationStack {
                    RoomMembersView(
                        roomName: Fixtures.hangar7.name,
                        members: [Fixtures.cassilda, Fixtures.hastur, Fixtures.camilla],
                        invited: invited, viewer: Fixtures.cassilda.id, onRemove: { _ in }, onInvite: {},
                        onBlock: { _ in }, onRescind: { _ in }, joins: [join], onDecide: { _, _ in },
                        personPage: { person, actions in
                            PersonDetailView(
                                connection: Connection(
                                    person: [Fixtures.cassilda, Fixtures.hastur, Fixtures.camilla]
                                        .first { $0.id == person } ?? .placeholder(person),
                                    sharedRooms: 1, seesTheirOutpost: false),
                                nickname: nil, sharedName: nil, onNicknameChange: nil, onPersonAvatarChange: nil,
                                actions: actions)
                        })
                }
            case .membersCheck:
                InvitedPersonSheet(person: invited[0], join: join, onDecide: { _, _ in }, onRescind: {})
            case .personActions:
                NavigationStack {
                    PersonDetailView(
                        connection: Fixtures.connections[0], nickname: nil, sharedName: "Hastur",
                        onNicknameChange: nil, onPersonAvatarChange: nil,
                        actions: PersonActions(roomName: Fixtures.hangar7.name, remove: {}, block: {}))
                }
            case .joinCheck:
                JoinRequestsView(roomName: Fixtures.hangar7.name, joins: { [join] }, onDecide: { _, _ in })
            case .eraseEverything:
                EraseEverythingView(onErase: {})
            case .awaitingApproval:
                AwaitingApprovalView(code: "7K3M9Q", onRecoveryKey: {})
            case .stalledOffline:
                RegistrationStalledView(stall: .accountOffline, onRetry: {}, onRestore: {})
            case .stalledSignedOut:
                RegistrationStalledView(stall: .signedOut, onRetry: {}, onRestore: {})
            case .roomsCannotSend:
                RootView.demo(
                    tab: .rooms,
                    cannotSend: "You are signed out of iCloud, so there is nowhere to leave what you write. Sign in and it will go on its own.")
            case .messageDetail:
                NavigationStack {
                    MessageDetailView(message: detailMessage, actions: MessageActions(), readers: readers)
                }
            case .tapTrouble:
                TapToSwapView(phase: .looking(closest: nil), number: nil, trouble: .notAllowed, onAccept: {})
            case .otherDevices:
                OtherDevicesAfterRestoreView(devices: Fixtures.devices, onRevoke: { _ in }, onDone: {})
            case .devices:
                NavigationStack { DeviceListView(devices: Fixtures.devices + [removedDevice]) }
            case .postThread:
                NavigationStack {
                    PostThreadView(post: Fixtures.posts[0], comments: [], viewer: Fixtures.cassilda.id)
                }
            case .postComposer:
                PostComposerView(onPost: { _ in nil })
            case .onboarding:
                OnboardingView(createIdentity: { _ in nil }, redeemInvite: {}, restore: {})
            case .redeem:
                RedeemInviteView(
                    arriving: "demo",
                    read: { _ in
                        InviteOffer(
                            roomName: Fixtures.hangar7.name, inviterName: Fixtures.hastur.displayName,
                            phrase: "K9F4V9TR2M", expiresAt: Date.now.addingTimeInterval(86_400))
                    },
                    accept: { _ in nil })
            case .invite:
                InviteView(
                    roomName: Fixtures.hangar7.name, invite: "demo", phrase: "K9F4V9TR2M",
                    expiresAt: Date.now.addingTimeInterval(86_400))
            case .addSomeone:
                AddSomeoneView(
                    rooms: { [Fixtures.hangar7, Fixtures.zeppelinEnthusiasts] }, code: "demo",
                    onAdd: { _, _ in nil }, preferences: RoomsListPreferences())
            case .removeMember:
                RemoveMemberView(member: Fixtures.hastur, roomName: Fixtures.hangar7.name, onRemove: {})
            case .checkingRegistration:
                CheckingRegistrationView()
            case .approveDevice:
                RootView.demo(tab: .rooms)
                    .approvingDevices(DeviceRequest(for: DeviceKeys.generate()), onApprove: { _ in }, onDecline: { _ in })
            case .dataProblem:
                DataProblemView(reason: "CarpenterKeychain.KeychainError error 1.", onTryAgain: {})
            default:
                EmptyView()
            }
        }

        private static var invited: [InvitedPerson] {
            [
                InvitedPerson(
                    person: Fixtures.thale, phrase: "K9F4V9TR2M", expiresAt: Date.now.addingTimeInterval(86_400),
                    hasConfirmed: true, isMine: false, invitedBy: Fixtures.hastur, awaitsMyApproval: true),
                InvitedPerson(
                    person: Fixtures.yhtill, phrase: "BX7HQ4NJ5W", expiresAt: Date.now.addingTimeInterval(3_600),
                    hasConfirmed: false, isMine: true, invitedBy: Fixtures.cassilda, awaitsMyApproval: false),
            ]
        }

        private static var join: PendingJoin {
            PendingJoin(
                id: Fixtures.thale.id, joiner: Fixtures.thale, inviter: Fixtures.hastur, phrase: "K9F4V9TR2M",
                expiresAt: Date.now.addingTimeInterval(86_400))
        }

        private static var removedDevice: DeviceSummary {
            DeviceSummary(
                id: DeviceID(rawValue: Data([0x13])), isCurrent: false, addedAt: Fixtures.ago(days: 200),
                revokedAt: Fixtures.ago(days: 40), name: "Old iPhone")
        }

        private static var detailMessage: Message {
            Message(
                id: Fixtures.fixtureMessageID(90), author: Fixtures.cassilda,
                body: "The hangar doors open at six. Bring the long ropes.", sentAt: Fixtures.ago(minutes: 42),
                isMine: true, delivery: .displayed(at: Fixtures.ago(minutes: 30)))
        }

        private static var readers: [ReadBy] {
            [
                ReadBy(member: Fixtures.hastur, report: .displayed(at: Fixtures.ago(minutes: 30))),
                ReadBy(member: Fixtures.camilla, report: .nothingYet),
                ReadBy(member: Fixtures.yhtill, report: .doesNotReport),
            ]
        }
    }

#endif
