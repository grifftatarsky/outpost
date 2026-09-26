import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("Test profiles")
struct TestProfilesTests {
    private func scratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "test-profiles-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private let server = URL(fileURLWithPath: "/tmp/outpost-test-mailbox")

    @Test("A profile's world has its own container, apart from iCloud's and every other profile's")
    func containersAreSeparate() {
        let base = "com.example.app"
        let first = TestProfile(name: "Home lab", server: server)
        let second = TestProfile(name: "Home lab", server: server)

        #expect(first.container(within: base) != base)
        #expect(first.container(within: base).hasPrefix(base + "."))
        #expect(first.container(within: base) != second.container(within: base))
        #expect(first.container(within: base) == first.container(within: base))
    }

    @Test("A profile's identity is kept on this device and never offered to iCloud Keychain")
    func identityStaysOnTheDevice() async throws {
        let keychain = InMemoryKeychainStore()
        let identities = IdentityStore(keychain: DeviceOnlyKeychainStore(keychain))

        _ = try await identities.enrol()

        #expect(await keychain.scope(for: IdentityStore.identityKey) == .device)
        #expect(await keychain.scope(for: IdentityStore.deviceKey) == .device)
        #expect(await keychain.synchronizedItems.isEmpty)
    }

    @Test("Without the wrapper the identity does go to iCloud Keychain, which is what the wrapper is for")
    func theWrapperIsWhatKeepsItLocal() async throws {
        let keychain = InMemoryKeychainStore()
        _ = try await IdentityStore(keychain: keychain).enrol()

        #expect(await keychain.scope(for: IdentityStore.identityKey) == .synchronized)
    }

    @Test("No list on disk means no profiles, and the iCloud world")
    func nothingOnDisk() throws {
        let store = TestProfileStore(directory: try scratch())

        let loaded = store.load()

        #expect(loaded.profiles.isEmpty)
        #expect(loaded.active == nil)
    }

    @Test("The list and the active profile survive being written down and read back")
    func roundTrip() throws {
        let store = TestProfileStore(directory: try scratch())
        let lab = TestProfile(name: "Lab", server: server, syncsToOtherDevices: true)
        let other = TestProfile(name: "Other", server: server)
        var profiles = TestProfiles()
        profiles.add(lab)
        profiles.add(other)
        profiles.activate(lab.id)

        try store.save(profiles)

        #expect(store.load() == profiles)
        #expect(store.load().active == lab)
    }

    @Test("Decoding keeps every field it was given")
    func decodingKeepsEveryField() throws {
        let id = UUID()
        let json = """
            {"profiles":[{"id":"\(id.uuidString)","name":"Lab","server":"file:///tmp/box",\
            "syncsToOtherDevices":true}],"activeID":"\(id.uuidString)"}
            """
        let decoded = try JSONDecoder().decode(TestProfiles.self, from: Data(json.utf8))
        let profile = try #require(decoded.profiles.first)

        #expect(profile.id == id)
        #expect(profile.name == "Lab")
        #expect(profile.server == URL(string: "file:///tmp/box"))
        #expect(profile.syncsToOtherDevices)
        #expect(decoded.activeID == id)

        let named: Set<String> = ["id", "name", "server", "syncsToOtherDevices"]
        let fields = Set(Mirror(reflecting: profile).children.compactMap(\.label))
        #expect(
            fields == named,
            """
            A field was added to TestProfile. Add it to init(from:) with decodeIfPresent, and to \
            this test, or a list written by this build will lose it on the next launch.
            """)
    }

    @Test("A list written before a field existed still opens, with that field at its default")
    func olderListsStillOpen() throws {
        let id = UUID()
        let json = """
            {"profiles":[{"id":"\(id.uuidString)","name":"Lab","server":"file:///tmp/box"}]}
            """
        let decoded = try JSONDecoder().decode(TestProfiles.self, from: Data(json.utf8))

        #expect(decoded.profiles.first?.syncsToOtherDevices == false)
        #expect(decoded.active == nil)
    }

    @Test("A list that cannot be read is set aside, not written over")
    func unreadableIsSetAside() throws {
        let directory = try scratch()
        let store = TestProfileStore(directory: directory)
        let garbage = Data("{ not a list".utf8)
        try garbage.write(to: store.url)

        let loaded = store.load()

        #expect(loaded.profiles.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
        let aside = try #require(store.setAsideURLs.first)
        #expect(try Data(contentsOf: aside) == garbage)
    }

    @Test("Asking whether a profile is on never writes, even when the list cannot be read")
    func peekingNeverWrites() throws {
        let store = TestProfileStore(directory: try scratch())
        let lab = TestProfile(name: "Lab", server: server)
        try store.save(TestProfiles(profiles: [lab], activeID: lab.id))
        #expect(store.isAnyProfileActive)

        let garbage = Data("{ not a list".utf8)
        try garbage.write(to: store.url)

        #expect(!store.isAnyProfileActive)
        #expect(try Data(contentsOf: store.url) == garbage)
        #expect(store.setAsideURLs.isEmpty)
    }

    @Test("The profile in use cannot be deleted out from under the session")
    func activeCannotBeRemoved() {
        let lab = TestProfile(name: "Lab", server: server)
        var profiles = TestProfiles(profiles: [lab], activeID: lab.id)

        profiles.remove(lab.id)

        #expect(profiles.active == lab)
    }

    @Test("Only a profile in the list can be the active one")
    func activeMustExist() {
        let lab = TestProfile(name: "Lab", server: server)
        var profiles = TestProfiles(profiles: [lab], activeID: UUID())
        #expect(profiles.active == nil)

        profiles.activate(UUID())
        #expect(profiles.active == nil)

        profiles.activate(lab.id)
        #expect(profiles.active == lab)

        profiles.activate(nil)
        #expect(profiles.active == nil)
    }
}
