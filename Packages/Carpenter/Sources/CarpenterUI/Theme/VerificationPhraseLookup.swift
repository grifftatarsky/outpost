import CarpenterKit
import SwiftUI

private struct VerificationPhraseKey: EnvironmentKey {
    static let defaultValue: @Sendable (Invite) -> String? = { _ in nil }
}

extension EnvironmentValues {
    /// The characters to read aloud for an invitation, or `nil` while the other person has not
    /// opened it yet.
    ///
    /// This is in the environment rather than in an argument list on purpose. Six screens want it,
    /// two of them sit behind fifty-parameter initialisers, and a defaulted parameter quietly lost
    /// from one of those lists is exactly how *Help on every screen* was broken on iPhone while
    /// working on the Mac — see CLAUDE.md. A value nothing has to remember to pass cannot be
    /// forgotten in one place and not the other.
    ///
    /// It is a closure rather than a value because the phrase **arrives later**: the joiner reveals
    /// the nonce only after the invitation was signed, so the inviter has nothing to show until
    /// their next sync round. Re-reading it each time the view draws is what makes it appear.
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
