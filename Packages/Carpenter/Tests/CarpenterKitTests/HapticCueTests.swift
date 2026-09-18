import CarpenterKit
import SwiftUI
import Testing

@testable import CarpenterUI

@Suite("Haptic cues")
@MainActor
struct HapticCueTests {
    @Test("There are exactly three cues")
    func vocabularyIsBounded() {
        #expect(HapticCue.allCases.count == 3)
        #expect(Set(HapticCue.allCases) == [.commit, .refusal, .failure])
    }

    @Test("Every cue maps to feedback, and no two feel alike")
    func everyCueIsDistinct() {
        let feedback = HapticCue.allCases.map(\.feedback)
        #expect(Set(feedback.map(String.init(describing:))).count == 3)
    }

    @Test("Declining and failing do not feel the same")
    func refusalIsNotFailure() {
        #expect(
            HapticCue.refusal.feedback != HapticCue.failure.feedback,
            "a send that could not go feels like the app refusing it")
    }

    @Test("Committing is a single light impact, not a completion pattern")
    func commitIsLight() {
        #expect(HapticCue.commit.feedback == .impact(weight: .light, intensity: 0.7))
    }
}
