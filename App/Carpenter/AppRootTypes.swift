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

struct ArrivingCode: Identifiable {
    let value: String
    var id: String { value }
}

enum AppIconSwitching {
    static var isSupported: Bool {
        #if canImport(UIKit) && !os(macOS)
            return UIApplication.shared.supportsAlternateIcons
        #else
            return false
        #endif
    }

    static func apply(_ choice: AppIconChoice) async {
        #if canImport(UIKit) && !os(macOS)
            guard UIApplication.shared.supportsAlternateIcons else { return }
            try? await UIApplication.shared.setAlternateIconName(choice.alternateName)
        #endif
    }
}
