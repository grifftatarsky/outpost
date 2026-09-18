import SwiftUI

extension View {
    func codeEntry() -> some View {
        autocorrectionDisabled()
            .modifier(NoAutocapitalisation())
    }
}

private struct NoAutocapitalisation: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS) || os(visionOS)
            content.textInputAutocapitalization(.never)
        #else
            content
        #endif
    }
}
