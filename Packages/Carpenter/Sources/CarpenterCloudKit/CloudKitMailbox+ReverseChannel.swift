import CloudKit
import CarpenterKit
import Foundation

// MARK: Leaving our share URL in a peer's own zone

extension CloudKitMailbox {
    enum ShareOfferRecord {
        static let type = "OutboxShareOffer"
        static let sealed = "sealed"
        static let digest = "digest"
    }

    public struct OfferOutcome: Sendable, Equatable {
        public var written = 0
        public var standing = 0
        public var unplaced = 0
        public var failed = 0
        public init() {}
    }

    public func offer(_ offers: [ShareOffer]) async -> OfferOutcome {
        var outcome = OfferOutcome()
        for offer in offers {
            guard let (zone, scope) = await directory.place(for: offer.fetchTag), scope == .shared
            else {
                outcome.unplaced += 1
                continue
            }

            let id = CKRecord.ID(recordName: offer.name, zoneID: zone)
            let existing = try? await container.sharedCloudDatabase.record(for: id)
            if let existing, existing[ShareOfferRecord.digest] as? String == offer.digest {
                outcome.standing += 1
                continue
            }

            let record = existing ?? CKRecord(recordType: ShareOfferRecord.type, recordID: id)
            record[ShareOfferRecord.sealed] = offer.sealed
            record[ShareOfferRecord.digest] = offer.digest
            do {
                let saved = try await container.sharedCloudDatabase.modifyRecords(
                    saving: [record], deleting: [], savePolicy: .allKeys)
                guard let result = saved.saveResults[id] else { throw MailboxError.unavailable }
                _ = try result.get()
                outcome.written += 1
            } catch {
                outcome.failed += 1
                Diagnostics.sync.error(
                    """
                    mailbox: could not leave our offer in a peer's zone \
                    (\(String(zone.ownerName.suffix(6)), privacy: .public)): \
                    \(String(describing: error), privacy: .public)
                    """)
            }
        }
        if !offers.isEmpty {
            Diagnostics.sync.notice(
                """
                mailbox: offers — \(outcome.written, privacy: .public) written, \
                \(outcome.standing, privacy: .public) standing, \
                \(outcome.unplaced, privacy: .public) unplaced, \
                \(outcome.failed, privacy: .public) failed
                """)
        }
        return outcome
    }

    public func retractOffer(named name: String) async throws {
        let id = CKRecord.ID(recordName: name, zoneID: outbox)
        _ = try await container.privateCloudDatabase.modifyRecords(saving: [], deleting: [id])
        Diagnostics.sync.notice("mailbox: retracted a dead offer so its owner leaves a current one")
    }

    public func collectOffers() async -> [String: Data] {
        let records = (try? await everything(in: outbox, of: container.privateCloudDatabase)) ?? []
        var found: [String: Data] = [:]
        for record in records where record.recordType == ShareOfferRecord.type {
            guard let sealed = record[ShareOfferRecord.sealed] as? Data else { continue }
            found[record.recordID.recordName] = sealed
        }
        return found
    }
}
