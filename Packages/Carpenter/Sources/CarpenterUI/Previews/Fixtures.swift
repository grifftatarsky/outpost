#if DEBUG

    import CarpenterKit
    import CryptoKit
    import Foundation

    enum Fixtures {
        static func fixtureMessageID(_ seed: Int) -> MessageID {
            MessageID(entry: EntryHash(rawValue: Data(repeating: UInt8(seed % 256), count: 32)))
        }

        static let now: Date = {
            var components = DateComponents()
            components.year = 2026
            components.month = 8
            components.day = 13
            components.hour = 15
            components.minute = 30
            return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 1_786_635_000)
        }()

        static func ago(days: Int = 0, hours: Int = 0, minutes: Int = 0) -> Date {
            now.addingTimeInterval(-Double(days * 86_400 + hours * 3_600 + minutes * 60))
        }

        static func hash(_ seed: UInt8) -> EntryHash {
            EntryHash(rawValue: Data(repeating: seed, count: 32))
        }

        /*
         * The id is derived from the name rather than generated, so a fixture's fingerprint, the
         * colour of its avatar disc and every id-derived detail are the same on every launch. The
         * marketing site's screens are captured from these, and a random id churned every image on
         * every capture — which makes "did this screen change?" unanswerable from a diff.
         */
        static func member(_ displayName: String) -> Member {
            Member(id: ParticipantID(rawValue: Data(SHA256.hash(data: Data(displayName.utf8)))),
                   displayName: displayName)
        }

        static let cassilda = member("Cassilda")
        static let hastur = member("Hastur")
        static let yhtill = member("Yhtill")
        static let camilla = member("Camilla")
        static let naotalba = member("Naotalba")
        static let thale = member("Thale")

        static let zeppelinEnthusiasts = RoomSummary(
            name: "Zeppelin Enthusiasts",
            memberCount: 7,
            lastAuthor: hastur,
            lastMessage: "A smoking room. On a hydrogen airship. Behind an airlock.",
            lastActivity: ago(hours: 4, minutes: 26),
            hasUnread: true
        )

        static let rooms: [RoomSummary] = [
            zeppelinEnthusiasts,
            hangar7,
            RoomSummary(
                name: "Carcosa Aeronautics Club",
                memberCount: 5,
                lastAuthor: cassilda,
                lastMessage: "the mooring mast drawings are 1:200, I can scan them tonight",
                lastActivity: ago(days: 1),
                hasUnread: false
            ),
            RoomSummary(
                name: "Lighter Than Air",
                memberCount: 9,
                lastAuthor: naotalba,
                lastMessage: "ok but a dirigible has a frame, that's the whole argument",
                lastActivity: ago(days: 2),
                hasUnread: false
            ),
            RoomSummary(
                name: "The Gasbag Gazette",
                memberCount: 4,
                lastAuthor: thale,
                lastMessage: "issue 4 is written, someone else lay it out",
                lastActivity: ago(days: 3),
                hasUnread: false
            ),
            RoomSummary(
                name: "Blimps Only",
                memberCount: 6,
                lastAuthor: camilla,
                lastMessage: "non-rigid or nothing, that is the entire charter",
                lastActivity: ago(days: 4),
                hasUnread: false
            ),
        ]

        static let syncedPeers = ["Cassilda", "Hastur", "Yhtill", "Camilla", "Thale", "Naotalba"]

        static let conversation: [Message] = [
            Message(
                id: fixtureMessageID(1),
                author: hastur,
                body:
                    "The Graf Zeppelin crossed the Pacific in 1929 with a grand piano on board. Aluminum. 350 pounds.",
                sentAt: ago(hours: 4, minutes: 38),
                isMine: false
            ),
            Message(
                id: fixtureMessageID(2),
                author: cassilda,
                body: "a piano. inside a hydrogen balloon.",
                sentAt: ago(hours: 4, minutes: 36),
                isMine: true
            ),
            Message(
                id: fixtureMessageID(3),
                author: cassilda,
                body: "everything about that decade was a dare",
                sentAt: ago(hours: 4, minutes: 35),
                isMine: true
            ),
            Message(
                id: fixtureMessageID(4),
                author: yhtill,
                body: "I found a 1936 Hindenburg deck plan at an estate sale for eleven dollars",
                sentAt: ago(hours: 4, minutes: 32),
                isMine: false
            ),
            Message(
                id: fixtureMessageID(5),
                author: yhtill,
                body:
                    "The smoking room was pressurized so no hydrogen could get in. One lighter, bolted to the table.",
                sentAt: ago(hours: 4, minutes: 31),
                isMine: false
            ),
            Message(
                id: fixtureMessageID(6),
                author: hastur,
                body: "A smoking room. On a hydrogen airship. Behind an airlock.",
                sentAt: ago(hours: 4, minutes: 26),
                isMine: false
            ),
        ]

        static let posts: [OutpostPost] = [
            OutpostPost(
                id: PostID(entry: hash(11)),
                author: cassilda,
                body:
                    "Spent the afternoon at the archive reading loading manifests. A 1931 flight lists 1,200 kg of mail and one dog, named in full.",
                postedAt: ago(hours: 4),
                commentCount: 3
            ),
            OutpostPost(
                id: PostID(entry: hash(12)),
                author: cassilda,
                body:
                    "The word dirigible just means steerable. Everything else about the shape is downstream of that one requirement, which I find unreasonably moving.",
                postedAt: ago(days: 1),
                commentCount: 7,
                previewComments: [
                    OutpostComment(
                        id: PostID(entry: hash(21)), author: hastur,
                        body: "a balloon that made a decision"),
                    OutpostComment(
                        id: PostID(entry: hash(22)), author: camilla,
                        body: "putting this on the Gazette masthead"),
                ]
            ),
            OutpostPost(
                id: PostID(entry: hash(13)),
                author: cassilda,
                body: "Naotalba is wrong about blimps and I will be posting about it.",
                postedAt: ago(days: 2),
                commentCount: 0
            ),
        ]

        static let editingDevice = DeviceKeys.generate().id

        static let hangar7 = RoomSummary(
            name: "Hangar 7",
            memberCount: 3,
            lastAuthor: camilla,
            lastMessage: "door code changed again, it's the year the R101 went down",
            lastActivity: ago(days: 2),
            hasUnread: false
        )

        static let organisation: RoomsListOrganisation = {
            var organisation = RoomsListOrganisation()
            let stamp = { (n: Int) in
                OrganisationStamp(at: now.addingTimeInterval(Double(n)), device: editingDevice)
            }

            let airships = organisation.addTag(named: "Airships", stamp: stamp(0))
            let projects = organisation.addTag(named: "Projects", stamp: stamp(1))
            let daily = organisation.addTag(named: "Daily", stamp: stamp(2))
            organisation.addTag(named: "Reading", stamp: stamp(3))

            organisation.setPinned(true, for: hangar7.id, stamp: stamp(4))
            organisation.setPinned(true, for: zeppelinEnthusiasts.id, stamp: stamp(5))

            func room(_ name: String) -> RoomID { rooms.first { $0.name == name }!.id }

            organisation.setTag(airships, on: true, for: room("Zeppelin Enthusiasts"), stamp: stamp(6))
            organisation.setTag(daily, on: true, for: room("Zeppelin Enthusiasts"), stamp: stamp(7))
            organisation.setTag(projects, on: true, for: room("Hangar 7"), stamp: stamp(8))
            organisation.setTag(projects, on: true, for: room("Carcosa Aeronautics Club"), stamp: stamp(9))
            organisation.setTag(projects, on: true, for: room("The Gasbag Gazette"), stamp: stamp(10))
            organisation.setTag(airships, on: true, for: room("Lighter Than Air"), stamp: stamp(11))
            organisation.setTag(airships, on: true, for: room("Blimps Only"), stamp: stamp(12))
            organisation.setTag(daily, on: true, for: room("Hangar 7"), stamp: stamp(13))

            return organisation
        }()

        static let feed: [OutpostPost] = [
            OutpostPost(
                id: PostID(entry: hash(14)),
                author: hastur,
                body:
                    "Found the 1936 Hindenburg smoking room blueprints. One door, pressurised, and a steward whose entire job was holding the only lighter on board.",
                postedAt: ago(minutes: 22),
                commentCount: 4,
                reactions: ["🔥": [cassilda.id, camilla.id, yhtill.id], "😮": [thale.id, naotalba.id]]
            ),
            OutpostPost(
                id: PostID(entry: hash(15)),
                author: camilla,
                body: "Masthead is set. The Gasbag Gazette, issue nine, Thursday.",
                postedAt: ago(hours: 1),
                commentCount: 1,
                reactions: ["👏": [cassilda.id, hastur.id, yhtill.id, thale.id, naotalba.id]]
            ),
            OutpostPost(
                id: PostID(entry: hash(16)),
                author: cassilda,
                body:
                    "Spent the afternoon at the archive reading loading manifests. A 1931 flight lists 1,200 kg of mail and one dog, named in full.",
                postedAt: ago(hours: 4),
                commentCount: 3,
                isMine: true
            ),
        ]

        static var savedRecoveryKey: RecoveryKeyRow {
            RecoveryKeyRow(
                text: { "" }, fingerprint: "4F2A 91C7 0B6E 3D58", savedAt: ago(days: 12),
                onSaved: {})
        }

        static let outpostAuthors = [cassilda, hastur, camilla, yhtill, thale]

        static let connections: [Connection] = [
            Connection(person: hastur, sharedRooms: 4, seesTheirOutpost: true),
            Connection(person: camilla, sharedRooms: 3, seesTheirOutpost: true),
            Connection(person: yhtill, sharedRooms: 2, seesTheirOutpost: false),
            Connection(person: thale, sharedRooms: 2, seesTheirOutpost: true),
            Connection(person: naotalba, sharedRooms: 1, seesTheirOutpost: false),
        ]

        static var devices: [DeviceSummary] {
            [
                DeviceSummary(
                    id: DeviceID(rawValue: Data([0x11])), isCurrent: true, addedAt: ago(days: 94),
                    name: "iPhone"),
                DeviceSummary(
                    id: DeviceID(rawValue: Data([0x12])), isCurrent: false, addedAt: ago(days: 31),
                    name: "Spare iPhone"),
            ]
        }

        static var outpostSettings: OutpostSettings {
            OutpostSettings(
                blurb: "Airship archives, mostly interwar. Slow replies.", consent: .open,
                hasCustomFace: false, showsPicture: true)
        }

        static let audiencePeople = 14

        struct PreviewClock: Clock {
            var now: Date { Fixtures.now }
        }
    }

#endif
