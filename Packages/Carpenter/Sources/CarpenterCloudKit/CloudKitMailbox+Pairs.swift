import CloudKit
import CarpenterKit
import Foundation

// MARK: One space per person, in this member's own iCloud, readable by that person alone

extension CloudKitMailbox {
    public func account(in pairs: Pairs) async throws -> String {
        if let known = await index.account { return known }
        let found = try await container.userRecordID().recordName
        await index.remember(account: found)
        return found
    }

    public func space(for peer: ParticipantID, naming account: String?, in pairs: Pairs) async throws -> URL {
        let hint = try pairs.hint(for: peer)
        try await refresh()
        let zone: CKRecordZone.ID
        if let known = await index.mineFor(hint) {
            zone = known
        } else {
            zone = try await makeZone(hint: hint)
        }
        let share = try await share(of: zone)
        if let account { try await name(account, in: share) }
        guard let url = share.url else { throw MailboxError.unavailable }
        await index.remember(url, for: zone)
        return url
    }

    public func spaceForACode(in pairs: Pairs) async throws -> URL {
        let zone = try await makeZone(hint: nil)
        guard let url = try await share(of: zone).url else { throw MailboxError.unavailable }
        await index.remember(url, for: zone)
        return url
    }

    public func claim(_ url: URL, for peer: ParticipantID, naming account: String?, in pairs: Pairs) async throws
        -> URL
    {
        let hint = try pairs.hint(for: peer)
        try await refresh()
        let code = await index.zone(linkedBy: url)
        if let existing = await index.mineFor(hint), existing != code {
            if let code {
                _ = try? await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [code])
                await index.dropMine(code)
            }
            return try await space(for: peer, naming: account, in: pairs)
        }
        guard let code else { return try await space(for: peer, naming: account, in: pairs) }
        try await writeHint(hint, in: code)
        let share = try await share(of: code)
        if let account { try await name(account, in: share) }
        return url
    }

    public func join(_ link: PairLink, of peer: ParticipantID, in pairs: Pairs) async throws -> JoinOutcome {
        let metadata: CKShare.Metadata
        do {
            metadata = try await container.shareMetadata(for: link.url)
        } catch let error as CKError where error.code == .unknownItem || error.code == .participantMayNeedVerification {
            return .notYetNamed
        }
        guard metadata.share.owner.userIdentity.userRecordID?.recordName == link.account else {
            Diagnostics.sync.error("pairs: a link's space belongs to somebody other than the person who sent it")
            return .gone
        }
        guard metadata.participantRole != .owner else { return .gone }
        if metadata.participantStatus != .accepted {
            _ = try await container.accept(metadata)
        }
        await index.invalidate()
        return .joined
    }

    public func close(_ peer: ParticipantID, in pairs: Pairs) async throws {
        let hint = try pairs.hint(for: peer)
        try await refresh()
        guard let zone = await index.mineFor(hint) else { return }
        _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [zone])
        await index.dropMine(zone)
    }

    func zone(for peer: ParticipantID, in pairs: Pairs) async throws -> CKRecordZone.ID {
        let hint = try pairs.hint(for: peer)
        try await refresh()
        if let known = await index.mineFor(hint) { return known }
        return try await makeZone(hint: hint)
    }

    private func makeZone(hint: PairHint?) async throws -> CKRecordZone.ID {
        let zone = CKRecordZone.ID(zoneName: Self.pairZonePrefix + UUID().uuidString)
        let database = container.privateCloudDatabase
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zone)], deleting: [])
        let share = CKShare(recordZoneID: zone)
        share.publicPermission = .none
        var records: [CKRecord] = [share]
        if let hint { records.append(Self.hintRecord(hint, in: zone)) }
        try await save(records, in: database)
        await index.adopt(zone, hint: hint, link: share.url)
        return zone
    }

    private func writeHint(_ hint: PairHint, in zone: CKRecordZone.ID) async throws {
        try await save([Self.hintRecord(hint, in: zone)], in: container.privateCloudDatabase)
        await index.adopt(zone, hint: hint, link: nil)
    }

    private static func hintRecord(_ hint: PairHint, in zone: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: PairWire.infoType, recordID: CKRecord.ID(recordName: PairWire.infoRecord, zoneID: zone))
        record[PairWire.hint] = hint.rawValue
        return record
    }

    private func share(of zone: CKRecordZone.ID) async throws -> CKShare {
        let database = container.privateCloudDatabase
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone)
        do {
            guard let share = try await database.record(for: id) as? CKShare else { throw MailboxError.unavailable }
            return share
        } catch let error as CKError where error.code == .unknownItem {
            let share = CKShare(recordZoneID: zone)
            share.publicPermission = .none
            try await save([share], in: database)
            guard let saved = try await database.record(for: id) as? CKShare else { throw MailboxError.unavailable }
            return saved
        }
    }

    private func name(_ account: String, in share: CKShare) async throws {
        let others = share.participants.filter { $0.role != .owner }
        if others.count == 1, others[0].userIdentity.userRecordID?.recordName == account { return }
        for participant in others { share.removeParticipant(participant) }
        let participant = try await participant(for: account)
        participant.permission = .readOnly
        share.addParticipant(participant)
        share.publicPermission = .none
        _ = try await container.privateCloudDatabase.modifyRecords(
            saving: [share], deleting: [], savePolicy: .changedKeys)
    }

    private func participant(for account: String) async throws -> CKShare.Participant {
        let lookup = CKUserIdentity.LookupInfo(userRecordID: CKRecord.ID(recordName: account))
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchShareParticipantsOperation(userIdentityLookupInfos: [lookup])
            let found = FoundParticipant()
            operation.perShareParticipantResultBlock = { _, result in
                if case .success(let participant) = result { found.participant = participant }
            }
            operation.fetchShareParticipantsResultBlock = { result in
                switch result {
                case .success:
                    if let participant = found.participant {
                        continuation.resume(returning: participant)
                    } else {
                        continuation.resume(throwing: MailboxError.unknownPeer)
                    }
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }
}

final class FoundParticipant: @unchecked Sendable {
    var participant: CKShare.Participant?
}
