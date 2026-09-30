#if DEBUG

    import CarpenterKit
    import CryptoKit
    import Foundation
    import os

    actor FileMailbox: Mailbox, MediaMailbox {
        private let file: URL
        private let lock: URL
        private let refusal: MailboxFailure?

        init(root: URL, refusal: MailboxFailure? = nil) throws {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            file = root.appending(path: "pairs.json")
            lock = root.appending(path: "pairs.lock")
            self.refusal = refusal
        }

        private func change<T>(writing: Bool = false, _ body: (inout LocalPairStore) throws -> T) throws -> T {
            if writing, let refusal { throw refusal }
            let descriptor = open(lock.path, O_CREAT | O_RDWR, 0o644)
            guard descriptor >= 0 else { throw MailboxError.unavailable }
            flock(descriptor, LOCK_EX)
            defer {
                flock(descriptor, LOCK_UN)
                Darwin.close(descriptor)
            }
            var store =
                (try? JSONDecoder().decode(LocalPairStore.self, from: Data(contentsOf: file))) ?? LocalPairStore()
            let result = try body(&store)
            try JSONEncoder().encode(store).write(to: file, options: .atomic)
            return result
        }

        func account(in pairs: Pairs) -> String { LocalPairStore.account(of: pairs.me) }

        func space(for peer: ParticipantID, naming account: String?, in pairs: Pairs) throws -> URL {
            try change { try $0.space(for: peer, naming: account, in: pairs, as: self.account(in: pairs)) }
        }

        func spaceForACode(in pairs: Pairs) throws -> URL { try change { $0.spaceForACode(in: pairs, as: self.account(in: pairs)) } }

        func claim(_ url: URL, for peer: ParticipantID, naming account: String?, in pairs: Pairs) throws -> URL {
            try change { try $0.claim(url, for: peer, naming: account, in: pairs, as: self.account(in: pairs)) }
        }

        func join(_ link: PairLink, of peer: ParticipantID, in pairs: Pairs) throws -> JoinOutcome {
            try change { $0.join(link, of: peer, in: pairs, as: self.account(in: pairs)) }
        }


        func reads(_ peer: ParticipantID, in pairs: Pairs) throws -> Bool {
            try change { $0.reads(peer, in: pairs, as: self.account(in: pairs)) }
        }

        func close(_ peer: ParticipantID, in pairs: Pairs) throws {
            try change { $0.close(peer, in: pairs, as: self.account(in: pairs)) }
        }

        func put(_ packet: SyncPacket, to peer: ParticipantID, in pairs: Pairs) throws {
            try change(writing: true) { try $0.put(packet, to: peer, in: pairs, as: self.account(in: pairs), at: Date()) }
        }

        func ring(_ peer: ParticipantID, in pairs: Pairs) throws {
            try change { try $0.ring(peer, in: pairs, as: self.account(in: pairs), at: Date()) }
        }

        func fetch(from peer: ParticipantID, for tags: Set<RecipientTag>, in pairs: Pairs) throws -> [SyncPacket] {
            try change { $0.fetch(from: peer, for: tags, in: pairs, as: self.account(in: pairs)) }
        }

        func acknowledge(_ id: PacketID, from peer: ParticipantID, with receipt: SealedReceipt, in pairs: Pairs) throws {
            try change { try $0.acknowledge(id, from: peer, with: receipt, in: pairs, as: self.account(in: pairs), at: Date()) }
        }

        func sentPackets(in pairs: Pairs) throws -> [PacketID: SentPacket] { try change { $0.sentPackets(in: pairs, as: self.account(in: pairs)) } }

        func withdraw(_ id: PacketID, in pairs: Pairs) throws { try change { $0.withdraw(id, as: self.account(in: pairs)) } }

        func upload(_ copies: PhotoCopies, in pairs: Pairs) throws {
            try change(writing: true) { try $0.upload(copies, in: pairs, as: self.account(in: pairs), at: Date()) }
        }

        func download(_ copy: PhotoCopyName, of photo: AttachmentID, from sender: ParticipantID, in pairs: Pairs) throws
            -> Data?
        {
            try change { $0.download(copy, from: sender, in: pairs, as: self.account(in: pairs)) }
        }

        func acknowledge(
            copy: PhotoCopyName, from sender: ParticipantID, with receipt: SealedReceipt, by device: DeviceID,
            in pairs: Pairs
        ) throws {
            try change {
                try $0.acknowledge(
                    copy: copy, from: sender, with: receipt, by: device, in: pairs, as: self.account(in: pairs),
                    at: Date())
            }
        }

        func storedCopies(in pairs: Pairs) throws -> [StoredPhotoCopy] {
            try change { $0.storedCopies(in: pairs, as: self.account(in: pairs)) }
        }

        func delete(copies: Set<PhotoCopyName>, in pairs: Pairs) throws {
            try change { $0.delete(copies: copies, as: self.account(in: pairs)) }
        }
    }

    struct RigAccount: AccountRegistry {
        func occupancy() async -> AccountOccupancy { .empty }
    }

    enum RigCodes {
        static func leave(_ code: String, as name: String) {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "--mailbox"), index + 1 < arguments.count
            else { return }
            let codes = URL(fileURLWithPath: arguments[index + 1]).appending(path: "codes")
            do {
                try FileManager.default.createDirectory(at: codes, withIntermediateDirectories: true)
                try code.write(to: codes.appending(path: name), atomically: true, encoding: .utf8)
            } catch {
                Diagnostics.sync.error(
                    "rig mailbox: could not leave a code — \(String(describing: error), privacy: .public)")
            }
        }
    }

    extension FileMailbox {
        static func fromLaunchArguments() -> FileMailbox? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "--mailbox"), index + 1 < arguments.count
            else { return nil }

            do {
                let refusal: MailboxFailure? =
                    switch arguments.firstIndex(of: "--mailbox-refuses").flatMap({
                        arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
                    }) {
                    case "full": .noRoomInICloud
                    case "signed-out": .notSignedIn
                    default: nil
                    }
                let mailbox = try FileMailbox(root: URL(fileURLWithPath: arguments[index + 1]), refusal: refusal)
                Diagnostics.sync.notice(
                    "rig mailbox: a directory, not CloudKit — proves nothing below the seam")
                return mailbox
            } catch {
                Diagnostics.sync.error(
                    "rig mailbox: could not open — \(String(describing: error), privacy: .public)")
                return nil
            }
        }
    }

#endif
