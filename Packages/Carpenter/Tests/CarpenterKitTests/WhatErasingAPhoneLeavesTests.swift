import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp

@MainActor
@Suite("Erasing a phone leaves nothing of the member on it", .serialized, .tags(.storage))
struct WhatErasingAPhoneLeavesTests {
    private struct Phone {
        let session: AppSession
        let keychain: InMemoryKeychainStore
        let kept: [URL]
        let defaults: UserDefaults
        let suite: String
    }

    private func phone() throws -> Phone {
        let root = TestScratch.root.appending(path: "phone-\(UUID().uuidString)", directoryHint: .isDirectory)
        let shared = root.appending(path: "group/world", directoryHint: .isDirectory)
        let fallback = root.appending(path: "support/world", directoryHint: .isDirectory)
        let focus = root.appending(path: "group/Focus", directoryHint: .isDirectory)
        let scratch = root.appending(path: "tmp/scratch", directoryHint: .isDirectory)
        let files = FileManager.default
        for folder in [shared, fallback, focus, scratch] {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let kept = [
            shared.appending(path: StorageLocation.avatarName),
            shared.appending(path: "\(StorageLocation.personAvatarsName)/someone.jpg"),
            fallback.appending(path: StorageLocation.logName),
            fallback.appending(path: "sync-engine.json"),
            focus.appending(path: "rooms.json"),
            scratch.appending(path: "picked-1.mov"),
        ]
        for file in kept {
            try files.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("Kitchen".utf8).write(to: file)
        }
        let suite = "carpenter-erase-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(["photo"], forKey: "media.revealed")
        defaults.set(Data([1]), forKey: "focusFilter.current")

        let keychain = InMemoryKeychainStore()
        let storage = SessionStorage(
            keychain: keychain,
            log: FileLogStore(url: shared.appending(path: StorageLocation.logName)),
            documents: FileDocumentStore(url: shared.appending(path: StorageLocation.stateName)),
            locations: [shared, fallback, focus, scratch],
            settings: [KeptSetting(suite: suite, key: "media.revealed"), KeptSetting(suite: suite, key: "focusFilter.current")])
        return Phone(
            session: AppSession(storage: storage, clock: TestClock(now: TestSession.now)),
            keychain: keychain, kept: kept, defaults: defaults, suite: suite)
    }

    private func nothingLeft(on phone: Phone) {
        let left = phone.kept.filter { FileManager.default.fileExists(atPath: $0.path) }
        #expect(left.isEmpty, "still on the phone: \(left.map(\.lastPathComponent))")
        #expect(phone.defaults.object(forKey: "media.revealed") == nil, "the photos the member revealed are still listed")
        #expect(phone.defaults.object(forKey: "focusFilter.current") == nil, "the Focus filter's rooms are still kept")
        UserDefaults().removePersistentDomain(forName: phone.suite)
    }

    @Test("A device removed by another device erases avatars, the Focus room list, scratch files and the copies from before the shared container")
    func removalErasesEverything() async throws {
        let phone = try phone()
        await phone.session.load()
        try await phone.session.createIdentity(displayName: "Griff")

        await phone.session.eraseAfterRemoval()

        #expect(phone.session.state == .removed)
        nothingLeft(on: phone)
        #expect(try await IdentityStore(keychain: phone.keychain).loadIdentity() == nil)
        #expect(try await IdentityStore(keychain: phone.keychain).wasRemoved(), "the phone forgot it was removed")
    }

    @Test("Erasing from Settings, after wrong codes, for a deathmark or for a forgotten code erases the same places")
    func everyEraseIsTheSameErase() async throws {
        let phone = try phone()
        await phone.session.load()
        try await phone.session.createIdentity(displayName: "Griff")

        await phone.session.eraseWhatThisPhoneKeeps()

        nothingLeft(on: phone)
        #expect(phone.session.enrolment == nil)
        #expect(try await IdentityStore(keychain: phone.keychain).loadIdentity() == nil)
        #expect(try await IdentityStore(keychain: phone.keychain).wasRemoved() == false)
    }
}
