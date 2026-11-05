import SwiftUI

#if os(iOS)
    import UIKit
#endif

public struct OpenSettingsButton: View {
    @Environment(\.openURL) private var openURL

    public init() {}

    public var body: some View {
        if let settings = Self.appSettings {
            Button { openURL(settings) } label: {
                // COPY BEGIN 387cddf7 [NEEDS HUMAN REVIEW]
                Text("Open Settings", bundle: .module)
                // COPY END 387cddf7
            }
        }
    }

    private static var appSettings: URL? {
        #if os(iOS)
            URL(string: UIApplication.openSettingsURLString)
        #else
            nil
        #endif
    }
}
