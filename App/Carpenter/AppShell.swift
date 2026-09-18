import CarpenterApp
import CarpenterCloudKit
import CarpenterKit
import CarpenterMedia
import CarpenterUI
import CloudKit
import SwiftUI

@MainActor
@Observable
final class AppShell {
    let cloud = CloudKitMailbox(
        container: .default(),
        directory: PeerZoneDirectory(store: AppRootView.mailboxDirectoryStore()))
    #if DEBUG
        let rig = FileMailbox.fromLaunchArguments()
    #endif
    let safety = SafetyPreferences()
    let theme = ThemeStore()
    let icons = AppIconStore()
    let preferences = RoomsListPreferences()

    var syncing: Bool = false
    var syncAgain: Bool = false
    var lastRendezvous: Date = Date.distantPast
    var lastSync: Date = Date.distantPast
    var mediaBytes: Int?
    var cloudTrouble: String?
    var deviceSync: CloudKitEntrySync?
    var startedSyncFor: DeviceID?
    var messagePushArmed: Bool = false
    var session: AppSession = AppSession(storage: .onDisk(), clock: UITestMode.clock)
    var pretendedFocus: Bool?
    var mediaLoader: MediaLoader?
    var ownAvatar: Image?
    var personAvatars: [ParticipantID: Image] = [:]
    var sharedAvatars: [ParticipantID: Image] = [:]
    var distribution: DistributionChannel?
    var outpostAvatars: [ParticipantID: Image] = [:]
    var ownOutpostAvatar: Image?
    var unfetchablePhotos: Set<AttachmentID> = []
    var screening: ScreeningAvailability = .unsupported
    var notificationsAllowed: Bool?
    var badgesAllowed: Bool?
}
