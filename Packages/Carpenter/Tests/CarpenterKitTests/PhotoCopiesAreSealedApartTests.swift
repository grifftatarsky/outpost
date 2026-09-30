@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Each person's copy of a photo is sealed apart, so nothing in iCloud ties two copies together", .serialized)
struct PhotoCopiesAreSealedApartTests {
    private let tag = RecipientTag(rawValue: Data([7]))

    private func pair() throws -> PairwiseSecret {
        try PairwiseSecret.derive(mine: Identity.generate(), theirs: Identity.generate().publicKeys)
    }

    private func sealedPhoto() throws -> (id: AttachmentID, inner: Data, digest: Data) {
        let (reference, ciphertext) = try SealedAttachment.seal(Data((0..<4_000).map { UInt8($0 % 251) }))
        return (reference.id, ciphertext, reference.digest)
    }

    private func bytes(of field: PacketField) -> [Data] {
        switch field {
        case .string(let text): [Data(text.utf8)]
        case .data(let bytes): [bytes]
        case .dataList(let list): list
        }
    }

    private func anything(in records: [(name: String, fields: [String: PacketField])], names photo: AttachmentID)
        -> Bool
    {
        let marks = [
            CanonicalBytes.uuid(photo.rawValue), Data(photo.rawValue.uuidString.utf8),
            Data(photo.rawValue.uuidString.lowercased().utf8),
        ]
        return records.contains { record in
            ([Data(record.name.utf8)] + record.fields.values.flatMap { bytes(of: $0) }).contains { data in
                marks.contains { data.range(of: $0) != nil }
            }
        }
    }

    // MARK: The seal itself

    @Test("Two people's copies of one photo share no name, no label and no sealed bytes")
    func twoCopiesAreApart() throws {
        let photo = try sealedPhoto()
        let (bob, carol) = (Identity.generate().id, Identity.generate().id)
        let secrets = [bob: try pair(), carol: try pair()]
        let copies = try OutgoingAttachment(id: photo.id, ciphertext: photo.inner, recipients: [bob: tag, carol: tag])
            .copies(between: { secrets[$0] })
        let (bobs, carols) = (try #require(copies.copies[bob]), try #require(copies.copies[carol]))

        #expect(bobs.name != carols.name, "two copies carry the same name, so Apple can pair them")
        let signer = DeviceID(rawValue: Data(repeating: 7, count: DeviceID.width))
        #expect(
            bobs.name.receiptName(by: signer) != carols.name.receiptName(by: signer),
            "two receipts carry the same name")
        #expect(bobs.label != carols.label)
        #expect(bobs.sealed != carols.sealed, "two copies are the same bytes, so Apple can pair them")
        for copy in [bobs, carols] {
            #expect(copy.sealed.range(of: photo.inner) == nil, "a copy carries the photo as it was before this seal")
            #expect(
                !anything(in: [(name: copy.name.recordName, fields: AttachmentWire.fields(of: copy))], names: photo.id),
                "a copy's record names the photo it is a copy of")
        }
    }

    @Test("Somebody with no secret shared with the sender gets no copy")
    func noSecretNoCopy() throws {
        let photo = try sealedPhoto()
        let (bob, stranger) = (Identity.generate().id, Identity.generate().id)
        let bobs = try pair()
        let copies = try OutgoingAttachment(id: photo.id, ciphertext: photo.inner, recipients: [bob: tag, stranger: tag])
            .copies(between: { $0 == bob ? bobs : nil })
        #expect(Set(copies.copies.keys) == [bob])
    }

    @Test("A copy opens only with its own pair's secret, and only as the photo it was made for")
    func aCopyOpensOnlyForItsPair() throws {
        let photo = try sealedPhoto()
        let (bobs, carols) = (try pair(), try pair())
        let copy = try PhotoCopy.seal(photo.inner, of: photo.id, for: tag, between: bobs)

        #expect(try PhotoCopy.open(copy.sealed, of: photo.id, matching: photo.digest, between: bobs) == photo.inner)
        #expect(throws: AttachmentError.digestMismatch) {
            try PhotoCopy.open(copy.sealed, of: photo.id, matching: photo.digest, between: carols)
        }
        let other = try sealedPhoto()
        #expect(throws: AttachmentError.digestMismatch) {
            try PhotoCopy.open(copy.sealed, of: other.id, matching: photo.digest, between: bobs)
        }
    }

    @Test("A photo stored before copies were sealed is still taken when it is exactly what the entry names")
    func anUnsealedCopyThatMatchesIsTaken() throws {
        let photo = try sealedPhoto()
        let anybody = try pair()
        #expect(try PhotoCopy.open(photo.inner, of: photo.id, matching: photo.digest, between: anybody) == photo.inner)
        #expect(throws: AttachmentError.digestMismatch) {
            try PhotoCopy.open(Data(photo.inner.reversed()), of: photo.id, matching: photo.digest, between: anybody)
        }
    }

    @Test("A label names its photo only on the copy it was sealed on")
    func aLabelStaysOnItsCopy() throws {
        let (first, second) = (AttachmentID(), AttachmentID())
        let (bobs, carols) = (try pair(), try pair())
        let one = try PhotoCopy.seal(Data([1]), of: first, for: tag, between: bobs)
        let two = try PhotoCopy.seal(Data([2]), of: second, for: tag, between: bobs)
        let theirs = try PhotoCopy.seal(Data([1]), of: first, for: tag, between: carols)

        #expect(PhotoCopy.photo(labelled: one.label, named: one.name, between: bobs) == first)
        #expect(
            PhotoCopy.photo(labelled: one.label, named: two.name, between: bobs) == nil,
            "a label moved onto another copy still named its photo, so the sender would clear the wrong one")
        #expect(PhotoCopy.photo(labelled: one.label, named: theirs.name, between: carols) == nil)
        #expect(PhotoCopy.photo(labelled: Data([0, 1, 2]), named: one.name, between: bobs) == nil)
    }

    @Test("A copy's name is read back only as it is written")
    func namesAreReadOneWay() throws {
        let name = PhotoCopyName(of: AttachmentID(), between: try pair())
        let one = DeviceID(rawValue: Data(repeating: 1, count: DeviceID.width))
        let two = DeviceID(rawValue: Data(repeating: 2, count: DeviceID.width))
        #expect(PhotoCopyName(recordName: name.recordName) == name)
        #expect(PhotoCopyName(receiptName: name.receiptName(by: one)) == name)
        #expect(PhotoCopyName(receiptName: name.receiptName(by: two)) == name)
        #expect(
            name.receiptName(by: one) != name.receiptName(by: two),
            "two devices signed for one copy under one name, so the second overwrote the first")
        #expect(PhotoCopyName(recordName: name.receiptName(by: one)) == nil, "a receipt was read as a copy")
        #expect(PhotoCopyName(receiptName: name.recordName) == nil, "a copy was read as a receipt")
        #expect(
            PhotoCopyName(recordName: "photo-" + UUID().uuidString) == nil,
            "a name written before copies were sealed was read as one")
    }

    // MARK: Through the app, as a member uses it

    @MainActor
    private struct Three {
        let mailbox: InMemoryMailbox
        let alice: AppSession
        let bob: AppSession
        let carol: AppSession
        let room: RoomID

        var bobID: ParticipantID { bob.enrolment!.identity.id }
        var carolID: ParticipantID { carol.enrolment!.identity.id }

        func settle(_ sessions: [AppSession], rounds: Int = 1) async throws {
            for _ in 0..<rounds {
                for session in sessions { try await session.sync(through: mailbox, media: mailbox) }
            }
        }
    }

    private func three() async throws -> Three {
        let mailbox = InMemoryMailbox()
        let (alice, bob, carol) = (TestSession.make(), TestSession.make(), TestSession.make())
        for (session, name) in [(alice, "Alice"), (bob, "Bob"), (carol, "Carol")] {
            await session.load()
            try await session.createIdentity(displayName: name)
        }
        let room = try await alice.createRoom(named: "Darkroom")
        try await join(bob, into: room, of: alice, through: mailbox)
        try await join(carol, into: room, of: alice, through: mailbox)
        let three = Three(mailbox: mailbox, alice: alice, bob: bob, carol: carol, room: room)
        try await three.settle([alice, bob, carol], rounds: 5)
        try #require(alice.roster(of: room).members.count == 3, "precondition: three members")
        return three
    }

    @Test("Nothing in iCloud names a photo, from sending it to clearing it")
    func nothingInICloudNamesThePhoto() async throws {
        let t = try await three()
        try await t.alice.send(SendingPhotoTests.photo(), to: t.room, through: t.mailbox)
        let sent = try #require(t.alice.messages(in: t.room).last?.media)
        try await t.alice.sync(through: t.mailbox, media: t.mailbox)

        let copies = await t.mailbox.everyStoredCopy
        try #require(Set(copies.map(\.to)) == [t.bobID, t.carolID], "precondition: one copy each for Bob and Carol")
        #expect(Set(copies.map(\.name)).count == 2, "the two copies share a name")
        #expect(!anything(in: await t.mailbox.storedRecords, names: sent.id), "a record names the photo once it is sent")

        try await t.settle([t.bob, t.carol])
        for reader in [t.bob, t.carol] {
            #expect(
                try await reader.attachmentData(for: sent, sentBy: try #require(t.alice.enrolment?.identity.id), through: t.mailbox)
                    == SendingPhotoTests.photo().bytes,
                "a reader could not open their own copy")
        }
        #expect(
            !anything(in: await t.mailbox.storedRecords, names: sent.id),
            "a receipt names the photo it signs for")

        try await t.alice.sync(through: t.mailbox, media: t.mailbox)
        #expect(await t.mailbox.everyStoredCopy.isEmpty, "the sender did not clear copies both readers signed for")
    }

    @Test("A copy that left one person's space early is put back for that person alone")
    func oneMissingCopyIsPutBack() async throws {
        let t = try await three()
        try await t.alice.send(SendingPhotoTests.photo(), to: t.room, through: t.mailbox)
        let sent = try #require(t.alice.messages(in: t.room).last?.media)
        try await t.alice.sync(through: t.mailbox, media: t.mailbox)
        let bobsCopy = try #require(t.alice.photoCopyName(of: sent.id, for: t.bobID))
        let carolsBefore = try #require(await t.mailbox.everyStoredCopy.first { $0.to == t.carolID })

        let alicePairs = try t.alice.currentPairs()
        await t.mailbox.delete(copies: [bobsCopy], in: alicePairs)
        let uploads = await t.mailbox.uploadCount
        try await t.alice.sync(through: t.mailbox, media: t.mailbox)

        let after = await t.mailbox.everyStoredCopy
        #expect(after.contains { $0.name == bobsCopy }, "Bob's copy was not put back")
        #expect(await t.mailbox.uploadCount == uploads + 1, "putting back one copy uploaded more than one")
        #expect(
            after.first { $0.to == t.carolID }?.modifiedAt == carolsBefore.modifiedAt,
            "Carol's copy was written again, which would void a receipt she had already written for it")

        try await t.settle([t.bob, t.carol])
        #expect(await t.bob.holdsAttachment(sent.id))
        #expect(await t.carol.holdsAttachment(sent.id))
    }
}
