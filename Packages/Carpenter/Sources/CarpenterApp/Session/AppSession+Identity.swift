import CarpenterKit
import CryptoKit
import Foundation

// MARK: Who this member is, on this device and the next

extension AppSession {
    // MARK: Lifecycle

    public func load() async {
        do {
            let store = IdentityStore(keychain: storage.keychain)
            guard try await store.loadIdentity() != nil else {
                state = .checkingForRegistration
                return
            }
            let identity = try await store.loadIdentity()!

            let existingDevice = try await store.loadDeviceKeys()
            let device = existingDevice ?? DeviceKeys.generate()
            if existingDevice == nil { try await store.save(device) }

            enrolment = Enrolment(
                identity: identity, device: device, deviceIsNew: existingDevice == nil)
            persisted = try await storage.documents.load(PersistedState.self) ?? PersistedState()
            organisation = persisted.organisation

            try await restoreLog(identity: identity)

            if existingDevice == nil {
                Diagnostics.identity.notice("load: new device on a known account, enrolled itself")
            }
            if !replica.allEntries.contains(where: { $0.device == device.id }) {
                sendOwnEntries()
            }

            await adoptNewOutpostAuthors()

            countWhatIsHeldForOthers()

            state = hasOwnName ? .ready : .needsProfile
            Diagnostics.identity.notice("load: \(String(describing: self.state), privacy: .public)")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private static let extendedKeyWaitAttempts = 24

    public func settleRegistration(attempts: Int = 20) async {
        switch state {
        case .checkingForRegistration:
            break
        case .registrationStalled:
            state = .checkingForRegistration
        default:
            return
        }

        let store = IdentityStore(keychain: storage.keychain)

        var occupancy = await accountRegistry?.occupancy() ?? .offline
        var presence = await identityPresence(store)

        for _ in 0..<attempts {
            if presence == .found {
                await load()
                return
            }
            if presence != .unreadable, occupancy == .empty || occupancy == .offline { break }
            try? await Task.sleep(for: .milliseconds(300))
            if occupancy == .undetermined {
                occupancy = await accountRegistry?.occupancy() ?? .offline
            }
            presence = await identityPresence(store)
        }

        if presence == .found {
            await load()
            return
        }

        guard presence == .absent else {
            Diagnostics.identity.notice(
                "load: the Keychain would not say whether this device holds a member; stopping rather than offering one")
            state = .registrationStalled(.keychainUnreadable)
            return
        }

        guard occupancy == .empty else {
            if occupancy == .occupied {
                Diagnostics.identity.notice(
                    "load: this account has a member and its key has not arrived; stopping here")
                state = .registrationStalled(.accountHasAMember)
            } else if occupancy == .offline {
                Diagnostics.identity.notice(
                    "load: iCloud could not be reached; stopping rather than offering a member")
                state = .registrationStalled(.accountOffline)
            } else {
                Diagnostics.identity.notice(
                    "load: the account could not be read; stopping rather than offering a member")
                state = .registrationStalled(.accountUnreadable)
            }
            return
        }

        state = .needsIdentity
        Diagnostics.identity.notice(
            "load: nothing registered on this account; offering a new member")
    }

    public var isWaitingForAnIdentity: Bool {
        switch state {
        case .needsIdentity, .checkingForRegistration, .registrationStalled: true
        default: false
        }
    }

    public func retryRegistration() async {
        guard case .registrationStalled = state else { return }
        await settleRegistration()
    }

    @discardableResult
    public func recheckForSyncedIdentity() async -> Bool {
        guard isWaitingForAnIdentity else { return false }
        let store = IdentityStore(keychain: storage.keychain)
        guard await identityPresence(store) == .found else { return false }

        await load()
        return state != .needsIdentity && state != .checkingForRegistration
    }

    private enum IdentityPresence: Sendable, Equatable {
        case found
        case absent
        case unreadable
    }

    private func identityPresence(_ store: IdentityStore) async -> IdentityPresence {
        do {
            return try await store.loadIdentity() == nil ? .absent : .found
        } catch {
            Diagnostics.identity.error(
                "load: the Keychain could not be read for this device's member (\(String(describing: error), privacy: .public))")
            return .unreadable
        }
    }

    public func createIdentity(displayName: String) async throws {
        let store = IdentityStore(keychain: storage.keychain)

        if try await store.loadIdentity() != nil {
            await load()
            return
        }

        let enrolled = try await store.enrol()
        enrolment = enrolled

        replica = Replica()
        replica.introduce(enrolled.identity.publicKeys)
        let founding = try DeviceCertificate.issue(
            for: enrolled.device.publicKey, by: enrolled.identity, at: clock.now)
        try replica.admit(founding)
        persisted.certificates = knownCertificates()

        try await setDisplayName(displayName)
    }

    public enum RestoreFailure: Error, Equatable, Sendable {
        case thisDeviceAlreadyHasAMember
        case keyRefused(RecoveryKey.Failure)
    }

    public func restore(
        fromRecoveryKey text: String, askingPeers: Bool = true, afterALoss: Bool = false
    ) async throws {
        let store = IdentityStore(keychain: storage.keychain)

        if try await store.loadIdentity() != nil {
            throw RestoreFailure.thisDeviceAlreadyHasAMember
        }

        let identity: Identity
        do {
            identity = try RecoveryKey.identity(from: text)
        } catch let failure as RecoveryKey.Failure {
            throw RestoreFailure.keyRefused(failure)
        }

        try await store.save(identity)
        let enrolled = try await store.enrol()
        enrolment = enrolled

        replica = Replica()
        replica.introduce(enrolled.identity.publicKeys)
        try replica.admit(
            DeviceCertificate.issue(
                for: enrolled.device.publicKey, by: enrolled.identity, at: clock.now))
        persisted.certificates = knownCertificates()

        Diagnostics.sync.notice(
            "recovery: restored \(Diagnostics.fingerprint(enrolled.identity.id.rawValue), privacy: .public) onto a new device")

        cameBackFromARecoveryKey = true
        persisted.preferences.setAsksPeersForHistory(askingPeers, stamp: stamp())
        persisted.wantsWhatWasSaid = askingPeers
        persisted.turnsEveryKeyAfterALoss = afterALoss
        cachedProjection = nil
        if afterALoss {
            Diagnostics.sync.notice(
                "recovery: a device was lost or stolen; every room's key turns")
        }
        if !askingPeers {
            Diagnostics.sync.notice(
                "recovery: restored without asking anybody for what was said")
        }
        await savePreferences()
        refresh()
        state = .ready
    }

    public func setDisplayName(_ displayName: String) async throws {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if persisted.preferences.displayName?.value != trimmed {
            persisted.preferences.setDisplayName(trimmed, stamp: stamp())
            cachedProjection = nil
            await savePreferences()
        }

        guard persisted.preferences.isSharingName else {
            state = .ready
            return
        }
        try await shareNameEverywhere(trimmed)
        state = .ready
    }

    private func shareNameEverywhere(_ name: String) async throws {
        let current = enrolment.flatMap { projection.members[$0.identity.id]?.displayName }
        guard current != name else { return }

        try await append(try Payload.memberProfile(displayName: name), to: nil)

        if enrolment?.identity.id != nil {
            for room in roomsToTell() {
                await announceOrReport("your name into a room you joined") {
                    try await announceProfile(in: room)
                }
            }
        }
    }

    // MARK: Sharing names and avatars

    public var sharing: NameAndAvatarSharing { persisted.preferences.sharing }
    public var sharesName: Bool { persisted.preferences.isSharingName }
    public var showsOthersNames: Bool { persisted.preferences.isShowingOthersNames }
    public var sharesAvatar: Bool { persisted.preferences.isSharingAvatar }
    public var showsOthersAvatars: Bool { persisted.preferences.isShowingOthersAvatars }

    public func setSharesName(_ shares: Bool) async {
        guard persisted.preferences.hasAnswered(\.sharesName) == false
            || persisted.preferences.isSharingName != shares else { return }
        persisted.preferences.setSharesName(shares, stamp: stamp())
        await savePreferences()
        guard shares, let name = ownDisplayName else { return }
        await announceOrReport("your name") { try await shareNameEverywhere(name) }
    }

    public func setShowsOthersNames(_ shows: Bool) async {
        guard persisted.preferences.hasAnswered(\.showsOthersNames) == false
            || persisted.preferences.isShowingOthersNames != shows else { return }
        persisted.preferences.setShowsOthersNames(shows, stamp: stamp())
        cachedProjection = nil
        await savePreferences()
    }

    public func setSharesAvatar(_ shares: Bool) async {
        guard persisted.preferences.hasAnswered(\.sharesAvatar) == false
            || persisted.preferences.isSharingAvatar != shares else { return }
        persisted.preferences.setSharesAvatar(shares, stamp: stamp())
        await savePreferences()
    }

    public func setShowsOthersAvatars(_ shows: Bool) async {
        guard persisted.preferences.hasAnswered(\.showsOthersAvatars) == false
            || persisted.preferences.isShowingOthersAvatars != shows else { return }
        persisted.preferences.setShowsOthersAvatars(shows, stamp: stamp())
        await savePreferences()
    }

    public var showsPhotoOnOutpost: Bool { persisted.preferences.isShowingPhotoOnOutpost }

    public func setShowsPhotoOnOutpost(_ shows: Bool) async {
        guard persisted.preferences.hasAnswered(\.showsPhotoOnOutpost) == false
            || persisted.preferences.isShowingPhotoOnOutpost != shows else { return }
        persisted.preferences.setShowsPhotoOnOutpost(shows, stamp: stamp())
        await savePreferences()
    }

    public func setSharing(_ sharing: NameAndAvatarSharing) async {
        await setShowsOthersNames(sharing.showsOthersNames)
        await setShowsOthersAvatars(sharing.showsOthersAvatars)
        await setSharesAvatar(sharing.sharesAvatar)
        await setSharesName(sharing.sharesName)
    }

    public func sharedName(of person: ParticipantID) -> String? {
        guard persisted.preferences.isShowingOthersNames else { return nil }
        return projection.members[person]?.displayName
    }

    // MARK: Nicknames

    public func nickname(for person: ParticipantID) -> String? {
        persisted.preferences.nickname(for: person)
    }

    public func setNickname(_ name: String?, for person: ParticipantID) async {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard (persisted.preferences.nickname(for: person) ?? "") != trimmed else { return }
        persisted.preferences.setNickname(trimmed, for: person, stamp: stamp())
        cachedProjection = nil
        await savePreferences()
    }

    // MARK: Sharing a photo

    public var ownPhotoReference: AttachmentReference? {
        enrolment.flatMap { projection.photoReference(of: $0.identity.id) }
    }

    public func sharePhoto(_ jpeg: Data, through mailbox: any MediaMailbox) async throws {
        guard let enrolment else { throw AppSessionError.noIdentity }
        guard persisted.preferences.isSharingAvatar else { return }
        let me = enrolment.identity.id
        let previous = projection.photoReference(of: me)

        let (reference, ciphertext) = try SealedAttachment.seal(jpeg, kind: .image)
        let window = SyncSession.window(at: clock.now)
        let recipients = Set(peers().map { $0.outgoingTag(window: window) })
        uploading.insert(reference.id)
        defer { uploading.remove(reference.id) }
        try await mailbox.upload(
            OutgoingAttachment(id: reference.id, ciphertext: ciphertext, recipients: recipients))
        Diagnostics.sync.notice(
            "avatar: uploaded \(ciphertext.count, privacy: .public) bytes for \(recipients.count, privacy: .public) peer(s)")

        try await announcePhotoEverywhere(reference)

        if let previous, previous.id != reference.id {
            do { try await mailbox.delete(attachment: previous.id) } catch {
                Diagnostics.sync.error(
                    "avatar: could not delete the previous photo (\(String(describing: error), privacy: .public))")
            }
        }
    }

    public func withdrawPhoto(through mailbox: any MediaMailbox) async {
        await withdrawOutpostPhoto(through: mailbox)

        guard let me = enrolment?.identity.id, let current = projection.photoReference(of: me) else {
            return
        }
        await announceOrReport("taking your photo down") { try await announcePhotoEverywhere(nil) }
        do {
            try await mailbox.delete(attachment: current.id)
            Diagnostics.sync.notice("avatar: taken down")
        } catch {
            Diagnostics.sync.error(
                "avatar: could not delete the photo (\(String(describing: error), privacy: .public))")
        }
    }

    // MARK: The recovery key

    public func recoveryKeyText() -> String? {
        guard let enrolment else { return nil }
        return RecoveryKey.text(for: enrolment.identity, createdAt: clock.now)
    }

    public var recoveryKeyFingerprint: String? {
        enrolment.map { RecoveryKey.fingerprint(of: $0.identity) }
    }

    public var recoveryKeySavedAt: Date? { persisted.preferences.recoveryKeySavedAt }

    public func noteRecoveryKeyOffered() async {
        persisted.preferences.setSavedRecoveryKey(clock.now, stamp: stamp())
        await savePreferences()
    }

    // MARK: Devices

    public func deviceName(_ device: DeviceID) -> String? {
        persisted.preferences.name(of: device)
    }

    public func setDeviceName(_ name: String?, for device: DeviceID) async {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard persisted.preferences.name(of: device) != (trimmed.isEmpty ? nil : trimmed) else {
            return
        }
        persisted.preferences.setName(trimmed, for: device, stamp: stamp())
        await savePreferences()
    }

    public func nameThisDeviceIfUnnamed(_ name: String) async {
        guard let device = enrolment?.device.id else { return }
        guard persisted.preferences.name(of: device) == nil else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        persisted.preferences.setName(trimmed, for: device, stamp: stamp())
        await savePreferences()
        Diagnostics.identity.notice("devices: named this device from its hardware")
    }

    public var devices: [DeviceSummary] {
        guard let enrolment, let registry = replica.registry(for: enrolment.identity.id) else {
            return []
        }
        let spoken = Set(replica.allEntries.map(\.device))

        return registry.deviceIDs
            .compactMap { id -> DeviceSummary? in
                guard let standing = registry.standing(of: id) else { return nil }
                return DeviceSummary(
                    id: id,
                    isCurrent: id == enrolment.device.id,
                    addedAt: standing.addedAt == .distantPast ? nil : standing.addedAt,
                    revokedAt: standing.revokedAt,
                    hasSpoken: id == enrolment.device.id || spoken.contains(id),
                    name: persisted.preferences.name(of: id)
                )
            }
            .sorted {
                ($0.isCurrent ? 0 : 1, $0.addedAt ?? .distantPast)
                    < ($1.isCurrent ? 0 : 1, $1.addedAt ?? .distantPast)
            }
    }

    public func revoke(_ device: DeviceID) async throws {
        try await revoke([device])
    }

    public func revoke(_ devices: [DeviceID]) async throws {
        guard let enrolment else { throw AppSessionError.noIdentity }
        let wanted = devices.filter { $0 != enrolment.device.id }
        guard wanted.count == devices.count else {
            throw AppSessionError.cannotRevokeThisDevice
        }
        guard !wanted.isEmpty else { return }

        for device in wanted {
            let revocation = try DeviceRevocation.issue(
                for: device, by: enrolment.identity, at: clock.now)
            try replica.revoke(revocation)
            persisted.revocations.append(revocation)
        }
        try await saveState()

        Diagnostics.identity.notice(
            """
            revoke: cutting off \(wanted.count, privacy: .public) device(s); each room's key \
            turns once
            """)

        var notTurned: [RoomID] = []
        for room in persisted.knownRooms where chains[room] != nil {
            do {
                try await advanceEpoch(of: room)
            } catch {
                notTurned.append(room)
                Diagnostics.identity.error(
                    "revoke: could not turn the key of a room — the revoked device can still read what is said in it (\(String(describing: error), privacy: .public))")
            }
        }
        refresh()

        guard notTurned.isEmpty else { throw AppSessionError.keyNotTurned(rooms: notTurned.count) }
    }
}
