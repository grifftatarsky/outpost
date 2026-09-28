import CarpenterKit
import Foundation
import Testing

private let onASimulator: Bool = {
    #if targetEnvironment(simulator)
        return true
    #else
        return false
    #endif
}()

@Suite(
    "What this phone keeps is written with the protection the setting names",
    .disabled(if: onASimulator, "A simulator does not keep a file's protection class, so only an iPhone can answer this"))
struct FileProtectionTests {
    private func scratch() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "carpenter-protection-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func protection(of url: URL) throws -> URLFileProtection? {
        try url.resourceValues(forKeys: [.fileProtectionKey]).fileProtection
    }

    @Test("With Advanced On Device Security on, the state is written so it opens only while the phone is unlocked")
    func stateIsSealed() async throws {
        let url = scratch().appending(path: "state.json")
        try await FileDocumentStore(url: url, protection: ProtectionDial(.whileUnlocked)).save(["kept": 1])
        #expect(try protection(of: url) == .complete)
    }

    @Test("Changing the setting reaches what is already kept, the folders included")
    func reprotectingReachesWhatIsKept() throws {
        let folder = scratch()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "log.carpenter")
        try Data([1]).write(to: file, options: .completeFileProtectionUntilFirstUserAuthentication)

        #expect(ProtectedFiles.reprotect([folder], as: .whileUnlocked).isEmpty)
        #expect(try protection(of: file) == .complete)
        #expect(try protection(of: folder) == .complete)

        #expect(ProtectedFiles.reprotect([folder], as: .afterFirstUnlock).isEmpty)
        #expect(try protection(of: file) == .completeUntilFirstUserAuthentication)
    }
}
