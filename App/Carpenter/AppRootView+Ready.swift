import CarpenterApp
import CarpenterCloudKit
import CarpenterKeychain
import CloudKit
import CarpenterKit
import CarpenterMedia
import CarpenterUI
import OSLog
import Intents
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

// MARK: The app once there is somebody to be

extension AppRootView {
    var ready: some View {
        RootView(
            rooms: session.rooms,
            syncedPeers: [],
            lastSync: .now,
            owner: session.viewer,
            posts: session.outpost(),
            onSearch: { session.search($0) },
            audiencePeople: session.outpostReaders().count,
            outpostAudience: OutpostAudience(
                people: session.audienceCandidates(),
                access: session.outpostAccess,
                keyTurnPending: session.outpostKeyTurnPending,
                allow: { person, everything in
                    await reporting("let somebody see the Outpost") {
                        try await session.allowOutpost(person, everything: everything)
                    }
                },
                revoke: { person in
                    await reporting("stop somebody seeing the Outpost") {
                        try await session.revokeOutpost(person)
                    }
                }),
            conversation: [],
            openRoom: $openRoom,
            organisation: session.organisation,
            feed: session.feed(),
            outpostAuthors: session.outpostAuthors(),
            onReact: { post, emoji in
                await attempting(
                    String(localized: "That reaction did not go through"), "react"
                ) { try await session.react(to: post, emoji: emoji) }
            },
            comments: { session.comments(on: $0) },
            onComment: { post, text in
                await attempting(
                    String(localized: "That comment did not go through"), "comment"
                ) { try await session.comment(on: post, text: text) }
            },
            onAttachPost: { picked, caption in await post(picked, caption: caption) },
            postActions: PostActions(
                edit: { post, text in
                    await reporting("edit post") { try await session.edit(post, to: text) }
                },
                withdraw: { post in
                    await reporting("withdraw post") { try await session.withdraw(post) }
                },
                editableFor: { session.timeLeft(toEdit: $0) },
                withdrawableFor: { session.timeLeft(toWithdraw: $0) }),
            onReactToComment: { comment, emoji in
                await attempting(
                    String(localized: "That reaction did not go through"), "react"
                ) { try await session.react(to: comment, emoji: emoji) }
            },
            messages: { session.messages(in: $0) },
            transcript: { session.transcript(in: $0) },
            onHideMessage: { await session.hide($0) },
            hiddenInRoom: { session.hiddenMessageCount(in: $0) },
            onRevealHiddenInRoom: { await session.revealHidden(in: $0) },
            onSeenMessage: { message, room in await session.markSeen(message, in: room) },
            onMarkRoomRead: { await session.markRoomRead($0) },
            onLeaveRoom: { room in
                await attempting(
                    String(localized: "You are still in that room"), "leave room"
                ) { try await session.leave(room) }
            },
            roomDeletion: { session.deletion(of: $0) },
            onDeleteRoom: { room in
                await attempting(
                    String(localized: "That room was not deleted"), "delete room"
                ) { try await session.deleteRoom(room) }
            },
            outpostAccessChosen: { session.outpostAccessChosen(in: $0) },
            onStopOutpostAccess: { people, room in
                for person in people {
                    await attempting(
                        String(localized: "They can still read your Outpost"), "stop outpost access"
                    ) { try await session.revokeOutpost(person, chosenIn: room) }
                }
            },
            onReactToMessage: { await react(to: $0, in: $1, with: $2) },
            isSilenced: { session.isMuted($0) },
            onSilence: { room, silenced in await session.setMuted(silenced, for: room) },
            messageDelay: { session.arrivalDelay(of: $0) },
            debugActions: debugActions,
            hiddenMessageCount: session.hiddenMessageCount,
            recoveryKey: session.recoveryKeyFingerprint.map { print in
                RecoveryKeyRow(
                    text: { session.recoveryKeyText() ?? "" },
                    fingerprint: print,
                    savedAt: session.recoveryKeySavedAt,
                    onSaved: { Task { await session.noteRecoveryKeyOffered() } })
            },
            onRevealHidden: { await session.revealAllHidden() },
            reportsDisplaying: session.reportsDisplaying,
            onReportsDisplayingChange: { await session.setReportsDisplaying($0) },
            notificationLevel: session.notificationLevel,
            onNotificationLevelChange: { await session.setNotificationLevel($0) },
            roomNotificationLevel: { session.notificationLevel(for: $0) },
            roomFollowsDefaultNotifications: { session.followsDefaultNotificationLevel($0) },
            onRoomNotificationLevelChange: { room, level in
                await session.setNotificationLevel(level, for: room)
            },
            onSend: { text, room in
                do {
                    try await session.send(text, to: room)
                    return nil
                } catch {
                    Diagnostics.sync.error(
                        "send failed: \(String(describing: error), privacy: .public)")
                    return SessionProblem.sentence(for: error)
                }
            },
            connections: session.connections(),
            onCreateRoom: { name, access, people in
                await createRoom(named: name, access: access, inviting: people)
            },
            onStartSolo: { person in await startSolo(with: person) },
            onRenameMember: renameMember,
            onAvatarChange: changeAvatar,
            sharing: session.sharing,
            showsPrivacyNote: privacyNote,
            onSharingChange: applySharing,
            focusSharing: session.focusSharing,
            onFocusSharingChange: applyFocusSharing,
            focusStatus: { session.focusStatus(of: $0) },
            nickname: { session.nickname(for: $0) },
            sharedName: { session.sharedName(of: $0) },
            onNicknameChange: { person, name in await session.setNickname(name, for: person) },
            onPersonAvatarChange: changePersonAvatar,
            onOrganisationChange: { session.updateOrganisation($0) },
            pendingJoins: { room in
                let waiting = session.pendingJoins(in: room).map { attestation in
                    PendingJoin(
                        id: attestation.joiner,
                        joiner: session.member(attestation.joiner),
                        inviter: session.member(attestation.inviter),
                        phrase: session.phrase(for: attestation) ?? "",
                        expiresAt: attestation.expiresAt,
                        refusedBy: session.whoRefused(attestation.joiner, in: room)
                    )
                }
                let unchecked = session.awaitingConfirmation(in: room).map { attestation in
                    PendingJoin(
                        id: attestation.joiner,
                        joiner: session.member(attestation.joiner),
                        inviter: session.member(attestation.inviter),
                        phrase: session.phrase(for: attestation) ?? "",
                        expiresAt: attestation.expiresAt,
                        isAlreadyIn: true,
                        refusedBy: session.whoRefused(attestation.joiner, in: room)
                    )
                }
                return waiting + unchecked
            },
            onInvite: { room, joinerCode, lifetime in
                let url = try? await (mailbox as? CloudKitMailbox)?.shareURL()
                do {
                    let issued = try await session.invite(
                        joinerCode: joinerCode, joining: room, mailbox: url,
                        lasting: lifetime)
                    #if DEBUG
                        if rig != nil, let code = try? issued.encoded() {
                            RigCodes.leave(code, as: "\(session.viewer.displayName).invite")
                        }
                    #endif
                    return issued
                } catch {
                    Diagnostics.identity.error(
                        "invite failed: \(String(describing: error), privacy: .public)")
                    return nil
                }
            },
            onOutstandingInvite: { room in
                let me = session.enrolment?.identity.id
                let roster = session.roster(of: room)
                guard
                    let pending = session.pendingInvitations(in: room)
                        .first(where: { $0.invitedBy == me && !roster.hasConfirmed($0.joiner) }),
                    let attestation = roster.requests[pending.joiner]
                else {
                    Diagnostics.identity.error("show invite: nothing outstanding to show")
                    return nil
                }
                let url = try? await (mailbox as? CloudKitMailbox)?.shareURL()
                Diagnostics.identity.notice(
                    "show invite: showing the invitation already standing, mailbox=\(url != nil, privacy: .public)")
                return Invite(attestation: attestation, mailbox: url)
            },
            onDecideJoin: { room, join, admit in
                let candidates =
                    session.pendingJoins(in: room) + session.awaitingConfirmation(in: room)
                guard let attestation = candidates.first(where: { $0.joiner == join.id })
                else { return }
                await attempting(
                    String(localized: "That answer did not go through"), "answer a join"
                ) {
                    try await session.decide(on: attestation, admit: admit)
                }
            },
            identityCode: session.codeForSharing,
            onSync: { await syncNow() },
            onRedeemInvite: { redeeming = true },
            integrity: session.integrity,
            mediaBytes: mediaBytes,
            onAppIconChange: { await applyAppIcon($0) },
            appIconIsSupported: AppIconSwitching.isSupported,
            devices: session.devices,
            onRevokeDevice: { going in
                do {
                    try await session.revoke(going.map(\.id))
                } catch let error as AppSessionError {
                    if case .keyNotTurned(let rooms) = error {
                        Diagnostics.identity.error(
                            "revoke: \(rooms, privacy: .public) room(s) did not turn their key")
                        problem = ActionProblem(
                            title: String(localized: "The device is out, but its key is still good"),
                            detail: String(
                                localized:
                                    "\(rooms) room(s) could not change their key, so that device can still read what is said in them until the next membership change. Try syncing, then remove it again."
                            ))
                    } else {
                        Diagnostics.identity.error(
                            "revoke failed: \(String(describing: error), privacy: .public)")
                        problem = ActionProblem(
                            title: String(localized: "Those devices were not removed"),
                            detail: SessionProblem.sentence(for: error))
                    }
                } catch {
                    Diagnostics.identity.error(
                        "revoke failed: \(String(describing: error), privacy: .public)")
                    problem = ActionProblem(
                        title: String(localized: "That device was not removed"),
                        detail: SessionProblem.sentence(for: error))
                }
            },
            onRenameDevice: { device, name in
                await session.setDeviceName(name, for: device.id)
            },
            roomAccess: { room in
                session.roster(of: room).founder == session.enrolment?.identity.id
                    ? session.access(of: room) : nil
            },
            roomMembers: { session.roster(of: $0).members.map(session.member).sorted { $0.displayName < $1.displayName } },
            roomInvitations: { room in
                let roster = session.roster(of: room)
                let me = session.enrolment?.identity.id
                let live = session.pendingInvitations(in: room).map { ($0, false) }
                let lapsed = session.lapsedInvitations(in: room).map { ($0, true) }
                return (live + lapsed).map { pending, hasLapsed in
                    let attestation = roster.requests[pending.joiner]
                    return InvitedPerson(
                        person: session.member(pending.joiner),
                        phrase: attestation.flatMap { session.phrase(for: $0) } ?? "",
                        expiresAt: pending.expiresAt,
                        hasConfirmed: roster.hasConfirmed(pending.joiner),
                        isMine: pending.invitedBy == me,
                        invitedBy: session.member(pending.invitedBy),
                        awaitsMyApproval: session.pendingJoins(in: room).contains {
                            $0.joiner == pending.joiner
                        },
                        agreed: {
                            let chosen: Int
                            switch roster.access {
                            case .atLeast(let n): chosen = n
                            case .unanimous: chosen = Int.max
                            default: return nil
                            }
                            return (
                                roster.admissions[pending.joiner]?.count ?? 0,
                                roster.effectiveThreshold(
                                    chosen, admitting: pending.joiner))
                        }(),
                        hasLapsed: hasLapsed)
                }
            },
            onRescindInvitation: { room, person in
                guard let attestation = session.roster(of: room).requests[person] else { return }
                await attempting(
                    String(localized: "That invitation was not taken back"), "rescind invitation"
                ) { try await session.rescind(attestation) }
            },
            waitingOn: { session.waitingOn(in: $0) },
            comparisonToOffer: { room in
                session.comparisonToOffer(in: room).map { verifiedPerson($0, in: room) }
            },
            onComparisonOffered: { await session.markComparisonOffered($0) },
            onMarkChecked: { await session.markChecked($0) },
            whoYouAreTalkingTo: { room in
                session.roster(of: room).members
                    .map { verifiedPerson($0, in: room) }
                    .sorted { $0.person.displayName < $1.person.displayName }
            },
            soloCheck: { room in
                SoloCheckPresentation.of(
                    session.soloCheck(in: room),
                    viewer: session.enrolment?.identity.id,
                    naming: { session.member($0) },
                    isSolo: session.rooms.first { $0.id == room }?.isDirect ?? false,
                    requiresCheck: session.requiresSoloCheck,
                    isHolding: session.isHoldingSolo(room))
            },
            onAskWhoYouAreTalkingTo: { room, holding in
                await attempting(
                    String(localized: "That check did not go out"), "ask a solo check"
                ) { try await session.askWhoYouAreTalkingTo(in: room, holding: holding) }
            },
            onAnswerWhoYouAreTalkingTo: { room, matched in
                await attempting(
                    String(localized: "That answer did not go through"), "answer a solo check"
                ) { try await session.answerWhoYouAreTalkingTo(in: room, matched: matched) }
            },
            requiresSoloCheck: session.requiresSoloCheck,
            onRequiresSoloCheck: { await session.setRequiresSoloCheck($0) },
            requiresLongPhrase: session.requiresLongPhrase,
            onRequiresLongPhrase: { await session.setRequiresLongPhrase($0) },
            toldAboutRestores: session.isToldAboutRestores,
            onToldAboutRestores: { await session.setToldAboutRestores($0) },
            holdsHistoryForRestores: session.isHoldingHistoryForRestores,
            onHoldsHistoryForRestores: { await session.setHoldsHistoryForRestores($0) },
            asksPeersForHistory: session.isAskingPeersForHistory,
            onAsksPeersForHistory: { await session.setAsksPeersForHistory($0) },
            awaitingAdmission: session.awaitingAdmission,
            managedTags: session.managedTags,
            onRemoveMember: { room, person in
                await attempting(
                    String(localized: "That person was not removed"), "remove member"
                ) { try await session.remove(person, from: room) }
            },
            roomStanding: { session.standing(in: $0) },
            viewer: session.enrolment?.identity.id,
            messageActions: MessageActions(
                edit: { message, text in
                    await reporting("edit message") {
                        try await session.edit(message, to: text)
                    }
                },
                withdraw: { message in
                    await reporting("withdraw message") {
                        try await session.withdraw(message)
                    }
                },
                hide: { await session.hide($0) },
                editableFor: { session.timeLeft(toEdit: $0) },
                withdrawableFor: { session.timeLeft(toWithdraw: $0) },
                block: { await session.block($0) },
                member: { session.member($0) },
                readBy: { message, room in session.readBy(message, in: room) }
            ),
            onAttach: { picked, caption, room in await attach(picked, caption: caption, to: room) },
            safety: safety,
            screening: screening,
            onOpenSystemSettings: openSystemSettings,
            blockedPeople: session.blockedPeople,
            onUnblock: { await session.unblock($0) },
            denyListUpdated: session.denyList.updated,
            onEraseEverything: { await nuke() },
            roomGreeting: { session.greeting(for: $0) },
            onGreetingSeen: { await session.acknowledgeGreeting(for: $0) },
            onRoomAccessChange: { room, access in
                await attempting(
                    String(localized: "That setting did not change"), "set access"
                ) { try await session.setAccess(access, in: room) }
            },
            repairStatus: { session.repairStatus(of: $0) },
            onRepair: { room, person in
                await session.startRepair(in: room, asking: person)
                await syncNow()
            },
            onDismissRepair: { await session.dismissRepair(in: $0) },
            reciprocalAccess: { session.reciprocalAccess(with: $0) },
            unseenOutposts: session.outpostAuthorsWithUnseen(),
            roomReceipts: { room in
                RoomReceiptChoice(
                    answer: session.reportsDisplayingAnswer(for: room)
                        .map { $0 ? .on : .off } ?? .followEverywhere,
                    everywhere: session.reportsDisplaying,
                    onChange: { answer in
                        switch answer {
                        case .followEverywhere:
                            await session.setReportsDisplaying(nil, in: room)
                        case .on: await session.setReportsDisplaying(true, in: room)
                        case .off: await session.setReportsDisplaying(false, in: room)
                        }
                    })
            },
            roomNotGone: { room in
                RoomNotGoneChoice(
                    wait: session.notGoneWait(in: room),
                    onChange: { await session.setNotGoneWait($0, in: room) })
            },
            cannotSend: session.cannotSend.map { SessionProblem.sentence(for: $0) },
            notifiedOutposts: session.outpostNotifiedPeople(),
            onMarkOutpostSeen: { await session.markOutpostSeen(from: $0) },
            onMarkOutpostSeenPost: { await session.markOutpostSeen($0) },
            notifications: notificationSettings,
            supporter: supporterSettings,
            onSetOutpostNotified: { person, wanted in
                await session.setNotified(wanted, about: person)
            },
            outpostBlurb: { session.blurb(of: $0) },
            outpostSettings: OutpostSettings(
                blurb: session.ownBlurb ?? "",
                persona: session.anonPersona,
                consent: session.outpostConsent,
                offersReview: session.offersOutpostReview,
                hasCustomFace: personAvatars[.anonymous] != nil,
                showsPicture: session.showsPhotoOnOutpost,
                hasOwnPicture: outpostAvatarStore.load() != nil,
                onBlurb: { text in
                    await reporting("write a blurb") { try await session.setBlurb(text) }
                },
                onPersona: { await session.setAnonPersona($0) },
                onConsent: { await session.setOutpostConsent($0) },
                onReview: { await session.setOffersOutpostReview($0) },
                onFace: { await changePersonAvatar(.anonymous, $0) },
                onShowsPicture: { await setShowsPhotoOnOutpost($0) },
                onPicture: { await changeOutpostPicture($0) },
                onWallPicture: { picked, reach in
                    await changeOutpostPicture(picked, reach: reach)
                }),
            hiddenComments: { session.hiddenComments(on: $0) },
            onBlock: { await session.block($0) },
            outpostReview: { session.outpostReview(in: $0) },
            heldRestore: { session.heldRestore(in: $0) },
            onLetHistoryThrough: { await session.letHistoryThrough(to: $0) },
            onRefuseHistory: { await session.refuseHistory(to: $0) },
            onOutpostChoice: { person, choice, room in
                await reporting("answer an access question") {
                    switch choice {
                    case .everything:
                        try await session.allowOutpost(
                            person, everything: true, chosenIn: room)
                    case .fromNow:
                        try await session.allowOutpost(
                            person, everything: false, chosenIn: room)
                    case .no:
                        try await session.revokeOutpost(person, chosenIn: room)
                    }
                }
            },
            onPostponeReview: { await session.postponeOutpostReview(in: $0) }
        )
        .task {
            guard !UITestMode.isOn else { return }
            await ActiveSyncLoop.run(
                interval: .seconds(Self.foregroundSyncSeconds),
                isCancelled: { Task.isCancelled },
                sleep: { try? await Task.sleep(for: $0) },
                tick: { await syncNow() })
        }
        .task {
            guard !UITestMode.isOn else { return }
            await enableMessagePush()
        }
.task { await readNotificationPermission() }
        .environment(
            \.stampDevice, session.enrolment?.device.id ?? DeviceID(rawValue: Data()))
        .verificationPhrase { [weak session] invite in
            MainActor.assumeIsolated { session?.phrase(for: invite.attestation) }
        }
    }
}

extension AppRootView {
    func verifiedPerson(_ person: ParticipantID, in room: RoomID) -> VerifiedPerson {
        let roster = session.roster(of: room)
        let me = session.enrolment?.identity.id
        let checkedAt = session.checkedAt(person)
        return VerifiedPerson(
            person: session.member(person),
            phrase: roster.requests[person].flatMap { session.phrase(for: $0) },
            confirmedAt: roster.confirmedAt(person),
            isViewer: person == me,
            isFounder: roster.founder == person,
            comparison: person == me
                ? []
                : (session.comparisonCode(with: person) ?? []).map { member, half in
                    ComparisonHalf(name: member.displayName, half: half, isViewer: member.id == me)
                },
            checkedAt: checkedAt,
            devicesAddedSince: checkedAt.map { session.devicesAdded(by: person, after: $0) } ?? [])
    }
}
