import CarpenterKit
import CryptoKit
import Foundation

// MARK: The hidden address, and changing it when a device is removed

struct AnnouncedAddress: Codable, Equatable, Sendable {
    var salt: Data
    var packet: PacketID?
    var confirmed = false
}

extension AppSession {
    func loadAddressBook() async {
        do {
            if let data = try await storage.keychain.data(for: AddressBook.key) {
                addressBook = try JSONDecoder().decode(AddressBook.self, from: data)
            } else {
                addressBook = AddressBook()
            }
            addressBookLoaded = true
        } catch {
            addressBookLoaded = false
            Diagnostics.identity.error(
                "address: could not read the address book; using it as it was (\(String(describing: error), privacy: .public))")
        }
        cachedPairwise.removeAll()
    }

    @discardableResult
    func changeAddressBook(_ change: @escaping @MainActor (inout AddressBook) -> Bool) async -> Bool {
        let previous = addressBookWriting
        let task = Task { @MainActor [self] () -> Bool in
            _ = await previous?.value
            if !addressBookLoaded { await loadAddressBook() }
            guard addressBookLoaded else { return false }
            var book = addressBook
            guard change(&book) else { return false }
            do {
                try await storage.keychain.set(try JSONEncoder().encode(book), for: AddressBook.key, scope: .device)
            } catch {
                integrity.writesFailed += 1
                Diagnostics.identity.error(
                    "address: could not write the address book, so nothing in it changes (\(String(describing: error), privacy: .public))")
                return false
            }
            addressBook = book
            cachedPairwise.removeAll()
            return true
        }
        addressBookWriting = task
        return await task.value
    }

    // MARK: The secrets a round writes under and listens under

    func legacySecret(with person: ParticipantID) -> PairwiseSecret? {
        guard let identity = enrolment?.identity, let keys = replica.registry(for: person)?.identity else { return nil }
        return try? PairwiseSecret.derive(mine: identity, theirs: keys)
    }

    func alternateSecrets(with person: ParticipantID) -> [PairwiseSecret] {
        let current = pairwiseSecret(with: person)
        return recentSecrets(with: person).map { $0.secret }.filter { $0 != current }
    }

    func whenAddressesWereLearned(of person: ParticipantID) -> [PairwiseSecret: Date] {
        var learned: [PairwiseSecret: Date] = [:]
        for (secret, theirs) in recentSecrets(with: person) {
            if let theirs, let at = addressBook.learned(theirs, of: person) { learned[secret] = at }
        }
        return learned
    }

    private func recentSecrets(with person: ParticipantID) -> [(secret: PairwiseSecret, theirs: AddressSalt?)] {
        guard let identity = enrolment?.identity, let keys = replica.registry(for: person)?.identity else { return [] }
        var found: [(secret: PairwiseSecret, theirs: AddressSalt?)] = []
        for mine in addressBook.ownRecent(at: clock.now) {
            for theirs in addressBook.recent(of: person, at: clock.now) {
                guard let secret = try? PairwiseSecret.derive(mine: identity, theirs: keys, mySalt: mine, theirSalt: theirs),
                    !found.contains(where: { $0.secret == secret })
                else { continue }
                found.append((secret, theirs))
            }
        }
        return found
    }

    func secrets(with person: ParticipantID) -> [PairwiseSecret] {
        (pairwiseSecret(with: person).map { [$0] } ?? []) + alternateSecrets(with: person)
    }

    // MARK: Changing it

    func rotateAddress(because reason: String) async {
        guard enrolment != nil else { return }
        let now = clock.now
        guard await changeAddressBook({ book in
            _ = book.rotateOwn(at: now)
            return true
        }), let salt = addressBook.ownCurrent
        else { return }
        persisted.addressAnnounced = [:]
        do { try await saveState() } catch {
            Diagnostics.identity.error(
                "address: could not write down that the new address is owed to everybody (\(String(describing: error), privacy: .public))")
        }
        Diagnostics.identity.notice(
            "address: changed this member's hidden address (\(reason, privacy: .public)); number \(salt.number, privacy: .public)")
        sendOwnEntries()
    }

    func rotateIfARemovalNeverChangedIt() async {
        guard addressBookLoaded, addressBook.ownCurrent == nil, let enrolment,
            let registry = replica.registry(for: enrolment.identity.id),
            registry.activeDevices.count < registry.deviceCount
        else { return }
        await rotateAddress(because: "a device was removed before addresses could change")
    }

    func announceAddresses(through session: SyncSession) async {
        guard let enrolment, let salt = addressBook.ownCurrent else { return }
        let digest = Self.saltDigest(salt)
        let open = Set(persisted.outstandingPackets.keys)
        for peer in peers() {
            if let told = persisted.addressAnnounced[peer.them], told.salt == digest,
                told.confirmed || told.packet.map(open.contains) == true
            {
                continue
            }
            let devices = deviceRecipients(of: peer.them)
            guard !devices.isEmpty, let legacy = legacySecret(with: peer.them) else { continue }
            do {
                let announcement = try AddressAnnouncement.make(
                    salt, from: enrolment.identity.id, by: enrolment.device, to: peer.them, devices: devices)
                let sent = try await session.send(
                    [], to: [Peer(secret: legacy, them: peer.them, me: peer.me)],
                    certificates: knownCertificates(), revocations: persisted.revocations, at: clock.now,
                    addresses: [announcement])
                noteWritten(sent)
                guard let packet = sent.written.first?.packet else { continue }
                persisted.addressAnnounced[peer.them] = AnnouncedAddress(salt: digest, packet: packet)
            } catch {
                Diagnostics.sync.error(
                    "address: could not tell a peer the new address (\(String(describing: error), privacy: .public))")
            }
        }
    }

    func confirmAnnouncement(_ packet: PacketID) {
        for (person, told) in persisted.addressAnnounced where told.packet == packet {
            persisted.addressAnnounced[person]?.confirmed = true
        }
    }

    static func saltDigest(_ salt: AddressSalt) -> Data {
        Data(SHA256.hash(data: CanonicalBytes.payload(domain: "carpenter.address-digest.v1", fields: [salt.bytes])))
    }

    // MARK: Hearing a contact's new address, and noticing a contact who has not heard ours

    func takeAddresses(_ received: [SyncReport.ReceivedAddress], from peer: Peer) async {
        guard let enrolment, !received.isEmpty, let registry = replica.registry(for: peer.them) else { return }
        var opened: [(AddressSalt, Date)] = []
        for item in received where item.announcement.member == peer.them {
            guard let salt = item.announcement.open(
                as: enrolment.device, of: enrolment.identity.id, from: registry, storedAt: item.storedAt)
            else {
                Diagnostics.sync.notice("address: refused an address no device of its sender could announce")
                continue
            }
            opened.append((salt, item.storedAt))
        }
        let (person, now) = (peer.them, clock.now)
        guard !opened.isEmpty,
            await changeAddressBook({ book in
                opened.reduce(false) { changed, item in
                    book.adopt(item.0, for: person, storedAt: item.1, at: now) || changed
                }
            })
        else { return }
        Diagnostics.sync.notice("address: a peer's hidden address changed; writing to them at the new one")
        if persisted.addressAnnounced[peer.them]?.confirmed == true {
            persisted.addressAnnounced[peer.them]?.confirmed = false
            persisted.addressAnnounced[peer.them]?.packet = nil
        }
        sendOwnEntries()
    }

    func noticeOldAddresses(_ collected: SyncSession.CollectedPackets, from peer: Peer) {
        guard let mine = addressBook.ownCurrent, let identity = enrolment?.identity,
            let keys = replica.registry(for: peer.them)?.identity,
            persisted.addressAnnounced[peer.them]?.confirmed == true
        else { return }
        let current = addressBook.recent(of: peer.them, at: clock.now).compactMap { theirs in
            try? PairwiseSecret.derive(mine: identity, theirs: keys, mySalt: mine, theirSalt: theirs)
        }
        let stale = collected.packets.contains { packet in
            guard let secret = packet.secret else { return false }
            return !current.contains(secret)
        }
        guard stale else { return }
        persisted.addressAnnounced[peer.them]?.confirmed = false
        persisted.addressAnnounced[peer.them]?.packet = nil
        Diagnostics.sync.notice("address: a peer is still writing to an old address; telling them the new one again")
    }

    func keepAddresses(fromSibling held: [HeldAddress]) async {
        guard !held.isEmpty else { return }
        let now = clock.now
        guard await changeAddressBook({ book in
            held.reduce(false) { changed, address in
                let took: Bool
                if let owner = address.owner {
                    took = book.adopt(address.salt, for: owner, storedAt: address.storedAt ?? address.since, at: now)
                } else {
                    took = book.keepOwn(address.salt, since: address.since, at: now)
                }
                return took || changed
            }
        })
        else { return }
        Diagnostics.identity.notice("address: took addresses from another of this member's devices")
    }
}
