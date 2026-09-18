import CarpenterKit
import Foundation

@MainActor
enum DemoConversation {
    static let roomID = RoomID(
        rawValue: UUID(uuidString: "DEC0DEDD-0000-4000-8000-000000001114") ?? UUID())

    static let cap = 2...25

    static func clamped(_ n: Int) -> Int {
        min(max(n, cap.lowerBound), cap.upperBound)
    }

    static var refusal: String {
        String(
            localized: "This is the demo room — nothing sent here goes anywhere.",
            bundle: .module, comment: "Debug demo conversation")
    }

    static let directRoomID = RoomID(
        rawValue: UUID(uuidString: "DEC0DEDD-0000-4000-8000-000000002222") ?? UUID())

    static func directRoom() -> RoomSummary {
        let script = directScript
        let opening = Date.now.addingTimeInterval(-(script.last?.at ?? 0) - 300)
        return RoomSummary(
            id: directRoomID,
            name: cast[1].displayName,
            memberCount: 2,
            lastAuthor: cast[script.last?.slot ?? 1],
            lastMessage: script.last?.text ?? "",
            lastActivity: opening.addingTimeInterval(script.last?.at ?? 0),
            hasUnread: false,
            isDirect: true
        )
    }

    static func directMessages() -> [Message] {
        let script = directScript
        let opening = Date.now.addingTimeInterval(-(script.last?.at ?? 0) - 300)
        let said = script.enumerated().map { index, line in
            Message(
                id: MessageID(entry: EntryHash(rawValue: Data(repeating: UInt8(200 + index), count: 32))),
                author: cast[line.slot],
                body: line.text,
                sentAt: opening.addingTimeInterval(line.at),
                isMine: line.slot == 0,
                delivery: line.slot == 0 ? .displayed(at: opening.addingTimeInterval(line.at + 30)) : .delivered
            )
        }
        let waiting = Message(
            id: MessageID(entry: EntryHash(rawValue: Data(repeating: 199, count: 32))),
            author: cast[0],
            body: "did the photos from saturday come through",
            sentAt: opening.addingTimeInterval((script.last?.at ?? 0) + 60),
            isMine: true,
            delivery: .sent,
            notGone: NotGone(signal: .waited(days: 3), hasLeftThisDevice: true))
        return said + [waiting]
    }

    private static let directScript: [Line] = {
        var offset: TimeInterval = 0
        return [
            Line(slot: 1, gap: 0, text: "did you actually finish the rewatch or were you bluffing in the group"),
            Line(slot: 0, gap: 45, text: "finished it. the time skip still works"),
            Line(slot: 1, gap: 30, text: "ok good. I did not want to say this in front of everyone but season 3 drags"),
            Line(slot: 0, gap: 40, text: "it does. you were right to keep that to yourself"),
            Line(slot: 1, gap: 25, text: "thank you"),
        ].map { line in
            offset += line.gap
            return Line(slot: line.slot, gap: line.gap, text: line.text, minimum: 2, at: offset)
        }
    }()

    static func room(participants: Int) -> RoomSummary {
        let n = clamped(participants)
        let script = lines(for: n)
        let last = script.last
        return RoomSummary(
            id: roomID,
            name: "cartoon discourse containment",
            memberCount: n,
            lastAuthor: last.map { cast[$0.slot] },
            lastMessage: last?.text ?? "",
            lastActivity: last.map { start(for: n).addingTimeInterval($0.at) } ?? .now,
            hasUnread: false
        )
    }

    static func messages(participants: Int) -> [Message] {
        let n = clamped(participants)
        let opening = start(for: n)
        return lines(for: n).enumerated().map { index, line in
            Message(
                id: MessageID(entry: EntryHash(rawValue: Data(repeating: UInt8(index % 256), count: 32))),
                author: cast[line.slot],
                body: line.text,
                sentAt: opening.addingTimeInterval(line.at),
                isMine: line.slot == 0,
                delivery: line.slot == 0 ? .displayed(at: opening.addingTimeInterval(line.at + 40)) : .delivered
            )
        }
    }

    // MARK: - The room's people

    private static let cast: [Member] = {
        let names = [
            "You",
            "Robin", "Raven", "Cyborg", "Beast Boy", "Starfire", "Terra", "Jinx",
            "Bumblebee", "Aqualad", "Speedy", "Kid Flash", "Argent", "Kole", "Jericho",
            "Herald", "Pantha", "Hot Spot", "Wildebeest", "Killowat", "Red Star",
            "Gnarrk", "Blackfire", "Más", "Menos",
        ]
        return names.map { Member(id: Identity.generate().id, displayName: $0) }
    }()

    // MARK: - The script

    private struct Line {
        let slot: Int
        let gap: TimeInterval
        let text: String
        var minimum: Int = 2
        var at: TimeInterval = 0
    }

    private static func lines(for n: Int) -> [Line] {
        var offset: TimeInterval = 0
        return script.compactMap { line in
            guard line.minimum <= n else { return nil }
            var line = line
            offset += line.gap
            line.at = offset
            if line.slot >= n {
                line = Line(
                    slot: line.slot == 0 ? 0 : ((line.slot - 1) % (n - 1)) + 1,
                    gap: line.gap, text: line.text, minimum: line.minimum, at: line.at)
            }
            return line
        }
    }

    private static func start(for n: Int) -> Date {
        let span = lines(for: n).last?.at ?? 0
        return Date.now.addingTimeInterval(-(span + 120))
    }

    private static let script: [Line] = [
        Line(slot: 1, gap: 0, text: "ok I finished the young justice rewatch"),
        Line(slot: 1, gap: 25, text: "and I need everyone to know season 1 holds up completely"),
        Line(slot: 1, gap: 40, text: "the whole premise is the proteges being tired of carrying capes for adults who don't rate them, and the show actually takes that seriously instead of playing it for laughs"),
        Line(slot: 3, gap: 90, text: "here we go"),
        Line(slot: 1, gap: 15, text: "no listen. covert ops instead of a junior league. the stakes are real precisely because nobody's watching them"),
        Line(slot: 3, gap: 50, text: "I'm not disagreeing, I'm just saying you send this exact message every six months"),
        Line(slot: 0, gap: 70, text: "he's right though. the show trusts you to keep up in a way kids stuff usually doesn't"),
        Line(slot: 2, gap: 120, text: "it assumes you can hold a fact for more than one episode. that alone puts it above most of what airs for adults."),

        Line(slot: 5, gap: 540, text: "I have only now reached the part where five years have passed between the seasons?? and nobody explains?? I was very upset and then I was very impressed"),
        Line(slot: 4, gap: 35, text: "THE TIME SKIP IS THE BEST DECISION THE SHOW MAKES"),
        Line(slot: 4, gap: 20, text: "everyone's different. some friendships died offscreen. you have to figure out what happened from how people stand next to each other"),
        Line(slot: 4, gap: 30, text: "name another cartoon that does that to you"),
        Line(slot: 2, gap: 60, text: "it grieves offscreen. that's the tell. immature shows grieve loudly and then reset by thursday."),

        Line(slot: 6, gap: 420, text: "ok since we're doing this: the reason it reads as mature has nothing to do with being dark"),
        Line(slot: 6, gap: 25, text: "it's that consequences stay. wally is gone and STAYS gone for years of runtime. the show sits in it"),
        Line(slot: 6, gap: 25, text: "and the kids are competent. they lose because the problems are hard, not because the writers need a lesson"),
        Line(slot: 7, gap: 15, text: "counterpoint: season 3 got a little pleased with how gritty it was"),
        Line(slot: 6, gap: 10, text: "I'M NOT DONE"),
        Line(slot: 6, gap: 20, text: "maturity is trusting the audience. time skips, politics, trauma that shapes people instead of branding them. it grew up with the people watching it and never announced it was doing that"),
        Line(slot: 6, gap: 30, text: "ok now I'm done. jinx is a little right about season 3"),
        Line(slot: 7, gap: 25, text: "thank you"),

        Line(slot: 3, gap: 180, text: "the maturity conversation is incomplete without the boring answer: it's tightly plotted. mature is mostly craft"),
        Line(slot: 2, gap: 40, text: "the boring answer is usually the answer"),
        Line(slot: 0, gap: 55, text: "does the fandom overrate it because it got canceled though. martyrdom does a lot of work"),
        Line(slot: 3, gap: 30, text: "getting canceled twice is the most mature thing a good show can do"),
        Line(slot: 1, gap: 20, text: "grim"),
        Line(slot: 5, gap: 45, text: "I do not think a show should have to die to be respected!!"),

        Line(slot: 8, gap: 240, text: "the season 1 finale is a perfect episode of television and I will not be elaborating", minimum: 9),
        Line(slot: 9, gap: 60, text: "the underwater politics episodes are criminally underrated btw", minimum: 10),
        Line(slot: 10, gap: 45, text: "hot take: the show is at its best when the mentors are wrong", minimum: 11),
        Line(slot: 11, gap: 30, text: "the wally thing broke me and I've never fully come back", minimum: 12),
        Line(slot: 12, gap: 50, text: "it's the only capes show where secret identities feel like an actual cost", minimum: 13),
        Line(slot: 13, gap: 40, text: "the tie-in comics are canon and essential and I'm tired of pretending otherwise", minimum: 14),
        Line(slot: 14, gap: 65, text: "👍", minimum: 15),
        Line(slot: 15, gap: 35, text: "watched it with my little cousin and we both thought it was pitched at us. that's the trick", minimum: 16),
        Line(slot: 16, gap: 40, text: "THE FIGHT CHOREOGRAPHY ALONE.", minimum: 17),
        Line(slot: 17, gap: 30, text: "every team roster after season 2 is too big and I say that with love", minimum: 18),
        Line(slot: 18, gap: 45, text: "big roster is realistic. nobody's team stays small", minimum: 19),
        Line(slot: 19, gap: 50, text: "the show about young heroes aging its cast in real time is the entire point, keep up", minimum: 20),
        Line(slot: 20, gap: 35, text: "where I grew up it aired out of order and the show survived even that", minimum: 21),
        Line(slot: 21, gap: 55, text: "gnarrk agrees", minimum: 22),
        Line(slot: 22, gap: 40, text: "objectively my taste is better than everyone's here and I also loved it", minimum: 23),
        Line(slot: 23, gap: 25, text: "¡más rápido que un episodio de relleno!", minimum: 24),
        Line(slot: 24, gap: 5, text: "¡no hay relleno!", minimum: 25),
        Line(slot: 8, gap: 90, text: "anyway. rewatch thread when", minimum: 9),

        Line(slot: 4, gap: 300, text: "petition to do a synchronized rewatch. one season a week. discussion here"),
        Line(slot: 2, gap: 45, text: "fine. but if anyone resets by thursday I'm leaving."),
        Line(slot: 0, gap: 60, text: "I'm in. starting friday"),
    ]
}
