@testable import CarpenterUI
import Testing

@Suite("Scanning an invite is asked about first, and saying no leaves pasting")
struct InviteScanningTests {
    @Test("Before anybody has answered, the join screen asks rather than scanning")
    func unansweredAsks() {
        #expect(InviteScanning.unasked.offer(deviceCanScan: true, wantsToScan: false) == .ask)
    }

    @Test("Turning scanning on shows Scan for this visit and saves nothing")
    func turningOnSavesNothing() {
        #expect(InviteScanning.unasked.offer(deviceCanScan: true, wantsToScan: true) == .scan)
        #expect(
            InviteScanning.unasked.after(.undecided) == .unasked,
            "the setting was saved before the camera had been allowed")
    }

    @Test("Allowing the camera is what saves the setting on")
    func allowingSaves() {
        #expect(InviteScanning.unasked.after(.granted) == .on)
        #expect(InviteScanning.off.after(.granted) == .on)
        #expect(InviteScanning.on.offer(deviceCanScan: true, wantsToScan: false) == .scan)
    }

    @Test("Saying no to Apple, or Not now, stops the asking and leaves Paste")
    func noStopsTheAsking() {
        #expect(InviteScanning.unasked.after(.refused) == .off)
        #expect(InviteScanning.on.after(.refused) == .off, "a camera turned off in Settings left Scan standing")
        #expect(InviteScanning.off.offer(deviceCanScan: true, wantsToScan: false) == .nothing)
    }

    @Test("A device that cannot scan is never asked, never offered a button, and changes nothing")
    func noScannerNoQuestion() {
        for answer in InviteScanning.allCases {
            #expect(answer.offer(deviceCanScan: false, wantsToScan: true) == .nothing)
            #expect(answer.after(.unsupported) == answer)
        }
    }

    @Test("An answer written by this build still reads in the next one")
    func storedAnswersAreStable() {
        #expect(InviteScanning.storageKey == "invites.scanning")
        #expect(InviteScanning.allCases.map(\.rawValue) == ["unasked", "on", "off"])
    }

    @Test("The system is asked only when nobody has answered it, and only on a device that can scan")
    func theSystemIsAskedOnce() {
        #expect(ScanAttempt(.undecided) == .askTheSystem)
        #expect(ScanAttempt(.unsupported) == .explainUnsupported)
        #expect(ScanAttempt(.granted) == .openScanner)
        #expect(ScanAttempt(.refused) == .explainRefused)
    }
}
