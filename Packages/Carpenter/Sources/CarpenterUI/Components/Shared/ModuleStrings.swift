import Foundation
import SwiftUI

extension LocalizedStringResource {
    public static func module(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}
