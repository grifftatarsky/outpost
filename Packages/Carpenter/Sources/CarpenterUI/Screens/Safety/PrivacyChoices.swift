import CarpenterKit
import SwiftUI

public struct PrivacyChoices: Hashable, Sendable {
    public var sharing: NameAndAvatarSharing
    public var focus: FocusSharing
    public var reportsDisplaying: Bool
    public var blursSensitiveMedia: Bool
    public var blocksKnownAbusers: Bool
    public var requiresSoloCheck: Bool = false
    public var toldAboutRestores: Bool = true
    public var holdsHistoryForRestores: Bool = false
    public var outposts: OutpostChoices

    public init(
        sharing: NameAndAvatarSharing, focus: FocusSharing = FocusSharing(), reportsDisplaying: Bool,
        blursSensitiveMedia: Bool, blocksKnownAbusers: Bool,
        requiresSoloCheck: Bool = false,
        toldAboutRestores: Bool = true,
        holdsHistoryForRestores: Bool = false,
        outposts: OutpostChoices = OutpostChoices()
    ) {
        self.sharing = sharing
        self.focus = focus
        self.reportsDisplaying = reportsDisplaying
        self.blursSensitiveMedia = blursSensitiveMedia
        self.blocksKnownAbusers = blocksKnownAbusers
        self.requiresSoloCheck = requiresSoloCheck
        self.toldAboutRestores = toldAboutRestores
        self.holdsHistoryForRestores = holdsHistoryForRestores
        self.outposts = outposts
    }

    public static let familiar = PrivacyChoices(
        sharing: NameAndAvatarSharing(
            sharesName: true, sharesAvatar: true, showsOthersNames: true, showsOthersAvatars: true),
        focus: FocusSharing(sharesFocus: true, showsOthersFocus: true),
        reportsDisplaying: false, blursSensitiveMedia: true, blocksKnownAbusers: true,
        requiresSoloCheck: false, toldAboutRestores: true, holdsHistoryForRestores: false,
        outposts: OutpostChoices(consent: .open, offersReview: true, showsPhoto: true))

    public static let lockedDown = PrivacyChoices(
        sharing: NameAndAvatarSharing(), focus: FocusSharing(),
        reportsDisplaying: false, blursSensitiveMedia: true, blocksKnownAbusers: true,
        requiresSoloCheck: true, toldAboutRestores: true, holdsHistoryForRestores: true,
        outposts: OutpostChoices(consent: .closed, offersReview: false, showsPhoto: false))
}

public struct OutpostChoices: Hashable, Sendable {
    public var consent: OutpostConsent
    public var offersReview: Bool
    public var showsPhoto: Bool

    public init(
        consent: OutpostConsent = .open, offersReview: Bool = true, showsPhoto: Bool = true
    ) {
        self.consent = consent
        self.offersReview = offersReview
        self.showsPhoto = showsPhoto
    }

    public var isOn: Bool {
        get { consent != .off }
        set { consent = newValue ? (consent == .off ? .open : consent) : .off }
    }
}
