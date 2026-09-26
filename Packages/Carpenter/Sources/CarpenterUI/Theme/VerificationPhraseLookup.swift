import CarpenterKit
import SwiftUI

private struct VerificationPhraseKey: EnvironmentKey {
    static let defaultValue: @Sendable (Invite) -> String? = { _ in nil }
}

extension EnvironmentValues {
    public var verificationPhrase: @Sendable (Invite) -> String? {
        get { self[VerificationPhraseKey.self] }
        set { self[VerificationPhraseKey.self] = newValue }
    }
}

extension View {
    public func verificationPhrase(_ lookup: @escaping @Sendable (Invite) -> String?) -> some View {
        environment(\.verificationPhrase, lookup)
    }
}
