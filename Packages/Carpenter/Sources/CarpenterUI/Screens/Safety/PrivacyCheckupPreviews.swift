import CarpenterKit
import SwiftUI

#if DEBUG
    #Preview("Check-up — first run") {
        PrivacyCheckupView(
            owner: Member(id: Sample.otherID, displayName: "Griff"),
            current: .lockedDown,
            onFinish: { _ in },
            onSkip: {}
        )
        .themed(.default)
    }
#endif
