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

// MARK: Pictures of people, and this member's own

extension AppRootView {
    func renameMember(_ name: String) async -> String? {
        await reporting("rename") { try await session.setDisplayName(name) }
    }

    var avatarStore: FileAvatarStore {
        FileAvatarStore(
            directory: StorageLocation.directory(container: Bundle.main.bundleIdentifier ?? "app"))
    }

    var outpostAvatarStore: FileAvatarStore {
        FileAvatarStore(
            directory: StorageLocation.directory(container: Bundle.main.bundleIdentifier ?? "app"),
            name: StorageLocation.outpostAvatarName)
    }

    func resolveOwnOutpostAvatar() {
        guard session.showsPhotoOnOutpost else {
            ownOutpostAvatar = nil
            return
        }
        ownOutpostAvatar = Self.decodeAvatar(outpostAvatarStore.load()) ?? ownAvatar
    }

    func changeAvatar(_ picked: PickedAvatar?) async {
        guard let picked else {
            do {
                try avatarStore.remove()
                ownAvatar = nil
                resolveOwnOutpostAvatar()
                if session.sharesAvatar { await session.withdrawPhoto(through: media) }
                await refreshOutpostPicture()
            } catch {
                Diagnostics.identity.error(
                    "avatar: could not remove (\(String(describing: error), privacy: .public))")
            }
            return
        }
        do {
            let jpeg = try ImagePreparer.avatar(picked.data, crop: picked.crop)
            try avatarStore.save(jpeg)
            ownAvatar = Self.decodeAvatar(jpeg)
            resolveOwnOutpostAvatar()
            if session.sharesAvatar { await sharePhoto(jpeg) }
            await refreshOutpostPicture()
        } catch {
            Diagnostics.identity.error(
                "avatar: could not prepare or save (\(String(describing: error), privacy: .public))")
        }
    }

    var personAvatarStore: PersonAvatarStore {
        PersonAvatarStore(
            directory: StorageLocation.directory(container: Bundle.main.bundleIdentifier ?? "app"))
    }

    func changePersonAvatar(_ person: ParticipantID, _ picked: PickedAvatar?) async {
        guard let picked else {
            do {
                try personAvatarStore.remove(for: person)
                personAvatars[person] = nil
            } catch {
                Diagnostics.identity.error(
                    "person avatar: could not remove (\(String(describing: error), privacy: .public))")
            }
            return
        }
        do {
            let jpeg = try ImagePreparer.avatar(picked.data, crop: picked.crop)
            try personAvatarStore.save(jpeg, for: person)
            personAvatars[person] = Self.decodeAvatar(jpeg)
        } catch {
            Diagnostics.identity.error(
                "person avatar: could not prepare or save (\(String(describing: error), privacy: .public))")
        }
    }

    // MARK: The picture on this member's own Outpost

    func refreshOutpostPicture() async {
        let bytes = session.showsPhotoOnOutpost ? (outpostAvatarStore.load() ?? avatarStore.load()) : nil
        _ = await reporting("put the picture on your Outpost") {
            try await session.shareOutpostPhoto(bytes, through: media)
        }
    }

    func changeOutpostPicture(_ picked: PickedAvatar?) async {
        guard keepOutpostPicture(picked) else { return }
        resolveOwnOutpostAvatar()
        await refreshOutpostPicture()
    }

    @discardableResult
    private func keepOutpostPicture(_ picked: PickedAvatar?) -> Bool {
        do {
            if let picked {
                try outpostAvatarStore.save(try ImagePreparer.avatar(picked.data, crop: picked.crop))
            } else {
                try outpostAvatarStore.remove()
            }
            return true
        } catch {
            Diagnostics.identity.error(
                "outpost avatar: could not prepare or keep (\(String(describing: error), privacy: .public))")
            problem = ActionProblem(
                title: String(localized: "Your Outpost picture was not changed"),
                detail: SessionProblem.sentence(for: error))
            return false
        }
    }

    func changeOutpostPicture(_ picked: PickedAvatar, reach: OutpostPictureReach) async {
        switch reach {
        case .outpostOnly:
            await changeOutpostPicture(picked)
        case .everywhere:
            keepOutpostPicture(nil)
            await changeAvatar(picked)
        }
    }

    func setShowsPhotoOnOutpost(_ shows: Bool) async {
        let changed = session.showsPhotoOnOutpost != shows
        await session.setShowsPhotoOnOutpost(shows)
        guard changed else { return }
        resolveOwnOutpostAvatar()
        await refreshOutpostPicture()
    }

    static func decodeAvatar(_ data: Data?) -> Image? {
        guard let data else { return nil }
        #if canImport(UIKit)
            return UIImage(data: data).map { Image(uiImage: $0) }
        #else
            return NSImage(data: data).map { Image(nsImage: $0) }
        #endif
    }
}
