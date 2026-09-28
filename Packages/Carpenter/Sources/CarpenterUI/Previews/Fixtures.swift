#if DEBUG

    import CarpenterKit
    import CryptoKit
    import Foundation
    import SwiftUI

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
        static let priya = member("Priya")
        static let jonah = member("Jonah")
        static let mae = member("Mae")
        static let rafi = member("Rafi")
        static let ines = member("Ines")

        static func solo(_ person: Member, _ message: String, _ when: Date, unread: Bool = false) -> RoomSummary {
            RoomSummary(
                name: person.displayName, memberCount: 2, lastAuthor: person, lastMessage: message,
                lastActivity: when, hasUnread: unread, isDirect: true, initials: person.initials, partner: person.id)
        }

        static let faces: [(Member, String, Color)] = [
            (camilla, "🦊", .orange), (naotalba, "🌻", .yellow), (thale, "🐙", .purple), (priya, "🥞", .pink),
            (jonah, "📚", .blue), (mae, "🎈", .red), (rafi, "🎸", .teal), (ines, "🥾", .green),
        ]

        @MainActor static let avatars: [ParticipantID: Image] = Dictionary(
            uniqueKeysWithValues: faces.compactMap { person, emoji, color in
                let renderer = ImageRenderer(
                    content: Text(verbatim: emoji)
                        .font(.system(size: 64))
                        .frame(width: 120, height: 120)
                        .background(LinearGradient(
                            colors: [color.opacity(0.55), color.opacity(0.9)], startPoint: .top, endPoint: .bottom)))
                renderer.scale = 2
                return renderer.cgImage.map { (person.id, Image(decorative: $0, scale: 2)) }
            })

        static let zeppelinEnthusiasts = RoomSummary(
            name: "Zeppelin Enthusiasts",
            memberCount: 7,
            lastAuthor: hastur,
            lastMessage: "A smoking room. On a hydrogen airship. Behind an airlock.",
            lastActivity: ago(hours: 4, minutes: 26),
            hasUnread: true,
            recentSpeakers: [hastur, yhtill, camilla]
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
                hasUnread: false,
                recentSpeakers: [naotalba, hastur, yhtill]
            ),
            RoomSummary(
                name: "Lighter Than Air",
                memberCount: 9,
                lastAuthor: naotalba,
                lastMessage: "ok but a dirigible has a frame, that's the whole argument",
                lastActivity: ago(days: 2),
                hasUnread: false,
                recentSpeakers: [naotalba, thale]
            ),
            RoomSummary(
                name: "The Gasbag Gazette",
                memberCount: 4,
                lastAuthor: thale,
                lastMessage: "issue 4 is written, someone else lay it out",
                lastActivity: ago(days: 3),
                hasUnread: false,
                recentSpeakers: [thale]
            ),
            RoomSummary(
                name: "Blimps Only",
                memberCount: 6,
                lastAuthor: camilla,
                lastMessage: "non-rigid or nothing, that is the entire charter",
                lastActivity: ago(days: 4),
                hasUnread: false,
                recentSpeakers: [camilla, hastur, thale]
            ),
            RoomSummary(
                name: "Sunday Pancake Summit", memberCount: 6, lastAuthor: priya,
                lastMessage: "I'm bringing the blueberries and nobody is allowed to fight me on this",
                lastActivity: ago(minutes: 12), hasUnread: true, recentSpeakers: [priya, rafi, mae]),
            RoomSummary(
                name: "Book club (we read it this time)", memberCount: 5, lastAuthor: jonah,
                lastMessage: "chapter twelve made me gasp out loud on a train. a stranger asked if I was ok",
                lastActivity: ago(hours: 2), hasUnread: true, recentSpeakers: [jonah, ines, thale]),
            RoomSummary(
                name: "Mae's surprise party 🤫", memberCount: 8, lastAuthor: rafi,
                lastMessage: "she asked what I'm doing Saturday and I said 'nothing' way too fast",
                lastActivity: ago(hours: 5), hasUnread: false, recentSpeakers: [rafi, priya, jonah]),
            RoomSummary(
                name: "Saturday hike", memberCount: 4, lastAuthor: ines,
                lastMessage: "trail is muddy, wear the shoes you don't love",
                lastActivity: ago(days: 1, hours: 3), hasUnread: false, recentSpeakers: [ines, mae]),
            RoomSummary(
                name: "The group project that ate June", memberCount: 3, lastAuthor: naotalba,
                lastMessage: "I renamed the file final_FINAL_v3 and I'm not sorry",
                lastActivity: ago(days: 5), hasUnread: false, recentSpeakers: [naotalba, camilla]),
        ]

        static let solos: [RoomSummary] = [
            solo(priya, "ok the recipe says 'a knob of butter'. what is a knob", ago(minutes: 3), unread: true),
            solo(mae, "thank you for yesterday. really ❤️", ago(minutes: 40)),
            solo(rafi, "running ten minutes late, save me a seat by the window", ago(hours: 1)),
            solo(jonah, "did you ever finish that podcast about lighthouse keepers", ago(hours: 6)),
            solo(ines, "the view from the top was worth every blister", ago(days: 1)),
            solo(hastur, "the airship model arrived. it is enormous. where do I put it", ago(days: 2)),
            solo(camilla, "found your scarf in my coat pocket, it's safe with me", ago(days: 3)),
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
            hasUnread: false,
            recentSpeakers: [camilla, yhtill]
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
            RecoveryKeyRow(fingerprint: "4F2A 91C7 0B6E 3D58", savedAt: ago(days: 12))
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
