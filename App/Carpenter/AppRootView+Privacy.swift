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

// MARK: The check-up, and what this member shares

extension AppRootView {
    var privacyCheckup: some View {
        PrivacyCheckupView(
            owner: session.viewer,
            current: currentPrivacyChoices,
            onFinish: { chosen in
                await applyPrivacy(chosen)
                await session.markPrivacyCheckedUp()
                showPrivacyNote()
            },
            onSkip: { await session.markPrivacyCheckedUp() }
        )
        .themed(.default)
    }

    private var currentPrivacyChoices: PrivacyChoices {
        PrivacyChoices(
            sharing: session.sharing, focus: session.focusSharing,
            reportsDisplaying: session.reportsDisplaying,
            blursSensitiveMedia: safety.blursSensitiveMedia,
            blocksKnownAbusers: safety.blocksKnownAbusers,
            requiresSoloCheck: session.requiresSoloCheck,
            toldAboutRestores: session.isToldAboutRestores,
            holdsHistoryForRestores: session.isHoldingHistoryForRestores,
            outposts: OutpostChoices(
                consent: session.outpostConsent ?? .open,
                offersReview: session.offersOutpostReview,
                showsPhoto: session.showsPhotoOnOutpost))
    }

    private func applyPrivacy(_ chosen: PrivacyChoices) async {
        await setShowsPhotoOnOutpost(chosen.outposts.showsPhoto)
        await applySharing(chosen.sharing)
        await session.setReportsDisplaying(chosen.reportsDisplaying)
        safety.blursSensitiveMedia = chosen.blursSensitiveMedia
        safety.blocksKnownAbusers = chosen.blocksKnownAbusers
        await session.setRequiresSoloCheck(chosen.requiresSoloCheck)
        await session.setToldAboutRestores(chosen.toldAboutRestores)
        await session.setHoldsHistoryForRestores(chosen.holdsHistoryForRestores)
        await session.setOutpostConsent(chosen.outposts.consent)
        await session.setOffersOutpostReview(chosen.outposts.offersReview)

        var focus = session.focusSharing
        focus.sharesFocus = chosen.focus.sharesFocus
        focus.showsOthersFocus = chosen.focus.showsOthersFocus
        await applyFocusSharing(focus)
    }

    private func showPrivacyNote() {
        privacyNote = true
        Task {
            try? await Task.sleep(for: .seconds(15))
            privacyNote = false
        }
    }

    func applySharing(_ wanted: NameAndAvatarSharing) async {
        let wasSharingPhoto = session.sharesAvatar
        await session.setSharesName(wanted.sharesName)
        await session.setSharesAvatar(wanted.sharesAvatar)
        await session.setShowsOthersNames(wanted.showsOthersNames)
        await session.setShowsOthersAvatars(wanted.showsOthersAvatars)

        if wanted.sharesAvatar, !wasSharingPhoto, let jpeg = avatarStore.load() {
            await sharePhoto(jpeg)
            await refreshOutpostPicture()
        } else if !wanted.sharesAvatar, wasSharingPhoto {
            await session.withdrawPhoto(through: media)
        }
        await collectSharedPhotos()
    }

    func applyFocusSharing(_ wanted: FocusSharing) async {
        if wanted.sharesFocus, !session.focusSharing.sharesFocus {
            _ = await INFocusStatusCenter.default.requestAuthorization()
        }
        await session.setFocusSharing(wanted)
        await reportFocusNow()
    }

    func reportFocusNow() async {
        guard session.focusSharing.sharesFocus else { return }
        if let pretendedFocus {
            await session.reportFocus(silenced: pretendedFocus)
            return
        }
        let center = INFocusStatusCenter.default
        guard center.authorizationStatus == .authorized else { return }
        await session.reportFocus(silenced: center.focusStatus.isFocused ?? false)
    }

    // COPY BEGIN 89523c13 [NEEDS HUMAN REVIEW]
    func sharePhoto(_ jpeg: Data) async {
        do {
            try await session.sharePhoto(jpeg, through: media)
        } catch {
            Diagnostics.identity.error(
                "avatar: could not share (\(String(describing: error), privacy: .public))")
            problem = ActionProblem(
                title: String(localized: "Your photo was not shared"),
                detail: SessionProblem.sentence(for: error))
        }
    }
    // COPY END 89523c13

    func collectSharedPhotos() async {
        guard session.showsOthersAvatars else {
            if !sharedAvatars.isEmpty { sharedAvatars = [:] }
            if !outpostAvatars.isEmpty { outpostAvatars = [:] }
            return
        }
        var rooms = sharedAvatars
        var walls = outpostAvatars
        var people = Set(session.connections().map(\.id))
        people.formUnion(session.outpostAuthors().map(\.id))
        people.remove(session.viewer.id)

        for person in people {
            rooms[person] = await collect(
                session.sharedPhotoReference(of: person), for: person, .rooms,
                drawn: rooms[person])
            walls[person] = await collect(
                session.sharedOutpostPhotoReference(of: person), for: person, .outpost,
                drawn: walls[person])
        }
        if rooms != sharedAvatars { sharedAvatars = rooms }
        if walls != outpostAvatars { outpostAvatars = walls }
    }

    private func collect(
        _ reference: AttachmentReference?, for person: ParticipantID,
        _ kind: PersonAvatarStore.Published, drawn: Image?
    ) async -> Image? {
        let held = personAvatarStore.publishedAttachment(for: person, kind)
        guard let reference else {
            if held != nil { try? personAvatarStore.removePublished(for: person, kind) }
            return nil
        }
        if reference.id == held {
            guard drawn == nil else { return drawn }
            return Self.decodeAvatar(personAvatarStore.loadPublished(for: person, kind))
        }
        guard !unfetchablePhotos.contains(reference.id) else { return drawn }
        do {
            guard let jpeg = try await session.downloadSharedPhoto(reference, from: person, through: media)
            else {
                unfetchablePhotos.insert(reference.id)
                return drawn
            }
            try personAvatarStore.savePublished(jpeg, for: person, kind, attachment: reference.id)
            return Self.decodeAvatar(jpeg)
        } catch {
            Diagnostics.sync.error(
                "avatar: could not collect a shared photo (\(String(describing: error), privacy: .public))")
            return drawn
        }
    }
}
