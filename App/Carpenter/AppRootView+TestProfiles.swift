import CarpenterApp
import CarpenterKeychain
import CarpenterKit
import CarpenterUI
import OSLog
import SwiftUI

// MARK: A world of its own, on a server somebody runs themselves

struct TestSession: Sendable {
    let profile: TestProfile
    let mailbox: any Mailbox & MediaMailbox
}

struct NoOtherMember: AccountRegistry {
    func occupancy() async -> AccountOccupancy { .empty }
}

enum TestProfileWorld {
    static var base: String { Bundle.main.bundleIdentifier ?? "app" }

    static var store: TestProfileStore {
        TestProfileStore(directory: StorageLocation.directory(container: base))
    }

    static func container(for profile: TestProfile?) -> String {
        profile?.container(within: base) ?? base
    }

    nonisolated static func supports(_ server: URL) -> Bool {
        #if DEBUG
            server.isFileURL
        #else
            false
        #endif
    }

    static func open(_ profile: TestProfile) -> (any Mailbox & MediaMailbox)? {
        #if DEBUG
            guard supports(profile.server) else { return nil }
            do {
                return try FileMailbox(root: profile.server)
            } catch {
                Diagnostics.sync.error(
                    "test profile: could not open its mailbox (\(String(describing: error), privacy: .public))")
                return nil
            }
        #else
            return nil
        #endif
    }

    static let launch: (session: TestSession?, profiles: TestProfiles) = {
        var profiles = store.load()
        guard let profile = profiles.active else { return (nil, profiles) }
        if let mailbox = open(profile) {
            Diagnostics.sync.notice("launch: in a test profile; iCloud stays closed")
            return (TestSession(profile: profile, mailbox: mailbox), profiles)
        }
        Diagnostics.sync.error("launch: the active test profile could not open; starting in iCloud")
        profiles.activate(nil)
        do {
            try store.save(profiles)
        } catch {
            Diagnostics.sync.error(
                "launch: could not record leaving the test profile (\(String(describing: error), privacy: .public))")
        }
        return (nil, profiles)
    }()
}

extension AppRootView {
    var worldContainer: String {
        TestProfileWorld.container(for: testSession?.profile)
    }

    var testProfilesControl: TestProfilesControl? {
        #if DEBUG
            TestProfilesControl(
                profiles: testProfiles.profiles,
                activeID: testSession?.profile.id,
                supports: { TestProfileWorld.supports($0) },
                add: { addTestProfile($0) },
                start: { await switchWorld(to: $0) },
                stop: { await switchWorld(to: nil) },
                remove: { await removeTestProfile($0) })
        #else
            nil
        #endif
    }

    @ViewBuilder var testSessionEscape: some View {
        #if DEBUG
            if let testSession, session.state != .ready {
                TestSessionEscape(name: testSession.profile.name) {
                    _ = await switchWorld(to: nil)
                }
                .themed(.default)
            }
        #endif
    }

    func addTestProfile(_ profile: TestProfile) -> TestProfileProblem? {
        guard TestProfileWorld.supports(profile.server) else { return .serverNotSupported }
        var list = testProfiles
        list.add(profile)
        return record(list)
    }

    func switchWorld(to id: UUID?) async -> TestProfileProblem? {
        guard !switchingWorld, id != testSession?.profile.id else { return nil }

        let next: TestSession?
        if let id {
            guard let profile = testProfiles.profiles.first(where: { $0.id == id }) else { return nil }
            guard let mailbox = TestProfileWorld.open(profile) else { return .serverUnreachable }
            next = TestSession(profile: profile, mailbox: mailbox)
        } else {
            next = nil
        }

        var list = testProfiles
        list.activate(id)
        if let problem = record(list) { return problem }

        switchingWorld = true
        defer { switchingWorld = false }
        while syncing {
            try? await Task.sleep(for: .milliseconds(100))
        }

        Diagnostics.sync.notice(
            "test profile: switching to \(next == nil ? "iCloud" : "a test profile", privacy: .public)")

        deviceSync = nil
        startedSyncFor = nil
        openRoom = nil
        testSession = next
        session = AppSession(storage: .onDisk(profile: next?.profile), clock: UITestMode.clock)
        session.enforcesDenyList = safety.blocksKnownAbusers
        mediaLoader = makeMediaLoader()
        session.checkAccount(with: accountRegistry)
        await openSession()
        loadAvatars()
        await session.settleRegistration()
        await session.nameThisDeviceIfUnnamed(HardwareName.ofThisDevice)
        resolveOwnOutpostAvatar()
        startDeviceSync()

        switchingWorld = false
        await syncNow()
        return nil
    }

    func removeTestProfile(_ id: UUID) async -> TestProfileProblem? {
        guard id != testSession?.profile.id,
            let profile = testProfiles.profiles.first(where: { $0.id == id })
        else { return nil }

        var list = testProfiles
        list.remove(id)
        if let problem = record(list) { return problem }

        let container = profile.container(within: TestProfileWorld.base)
        do {
            try await SystemKeychainStore(service: container, accessGroup: SharedKeychain.group).removeAll()
        } catch {
            Diagnostics.sync.error(
                "test profile: could not remove its keys (\(String(describing: error), privacy: .public))")
        }
        do {
            try FileManager.default.removeItem(at: StorageLocation.directory(container: container))
        } catch {
            Diagnostics.sync.error(
                "test profile: could not remove its storage (\(String(describing: error), privacy: .public))")
        }
        return nil
    }

    func loadAvatars() {
        ownAvatar = Self.decodeAvatar(avatarStore.load())
        personAvatars = personAvatarStore.loadAll().compactMapValues { Self.decodeAvatar($0) }
        sharedAvatars = [:]
        outpostAvatars = [:]
        ownOutpostAvatar = nil
        if session.showsOthersAvatars {
            sharedAvatars = personAvatarStore.loadAllPublished(.rooms)
                .compactMapValues { Self.decodeAvatar($0) }
            outpostAvatars = personAvatarStore.loadAllPublished(.outpost)
                .compactMapValues { Self.decodeAvatar($0) }
        }
    }

    private func record(_ list: TestProfiles) -> TestProfileProblem? {
        do {
            try TestProfileWorld.store.save(list)
        } catch {
            Diagnostics.sync.error(
                "test profile: could not write the list (\(String(describing: error), privacy: .public))")
            return .listNotSaved
        }
        testProfiles = list
        return nil
    }
}
