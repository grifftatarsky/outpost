import CarpenterKit
import Foundation

@MainActor
enum DemoOutpost {
    private static func member(_ name: String) -> Member {
        Member(id: Identity.generate().id, displayName: name)
    }

    private static let superman = member("Superman")
    private static let batman = member("Batman")
    private static let wonderWoman = member("Wonder Woman")
    private static let flash = member("Flash")
    private static let lantern = member("Green Lantern")
    private static let aquaman = member("Aquaman")
    private static let manhunter = member("Martian Manhunter")
    private static let arrow = member("Green Arrow")

    static let authors: [Member] = [
        superman, batman, wonderWoman, flash, lantern, aquaman, manhunter, arrow,
    ]

    private static func id(_ seed: UInt8) -> PostID {
        PostID(entry: EntryHash(rawValue: Data(repeating: seed, count: 32)))
    }

    static func posts(now: Date = .now) -> [OutpostPost] {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        return [
            OutpostPost(
                id: id(201), author: flash,
                body: "expectations check for #Doomsday: I just want it to commit to a bill. anyway the bar for a team story is still animated — **The New Frontier** did cosmic dread and an era's whole politics in seventy minutes. #animationsupremacy",
                postedAt: ago(190), commentCount: 0),
            OutpostPost(
                id: id(202), author: superman,
                body: "hopeful about #Doomsday, honestly. but the quiet truth is DC's best work was never the tentpoles — it's *New Frontier*, __Young Justice__, and the first two seasons of *Doom Patrol* before it disappeared up its own robot.",
                postedAt: ago(160), commentCount: 0),
            OutpostPost(
                id: id(203), author: manhunter,
                body: "Young Justice wrote its aliens as immigrants rather than gimmicks, and stayed patient about it. if #Doomsday wants stakes, that is the note to steal. #animationsupremacy",
                postedAt: ago(140), commentCount: 0),
            OutpostPost(
                id: id(204), author: wonderWoman,
                body: "myth needs scale and consequence, and the movies keep buying scale with the consequence budget. *New Frontier* understood the trade. curious whether #Doomsday does.",
                postedAt: ago(110), commentCount: 0),
            OutpostPost(
                id: id(205), author: arrow,
                body: "hot take: the only DC that matters is **The Dark Knight** and #Doomsday should just copy it",
                postedAt: ago(80), commentCount: 3,
                previewComments: [
                    OutpostComment(
                        id: id(220), author: batman,
                        body: "no.", postedAt: ago(74)),
                    OutpostComment(
                        id: id(221), author: flash,
                        body: "eighteen years old. we have New Frontier at home",
                        postedAt: ago(70)),
                    OutpostComment(
                        id: id(222), author: wonderWoman,
                        body: "it is a fine film. it is not a personality.",
                        postedAt: ago(61)),
                ]),
            OutpostPost(
                id: id(206), author: aquaman,
                body: "doom patrol season 2? cinema. everything after? silly. #Doomsday will be fine if they let the villain be frightening instead of quippy",
                postedAt: ago(45), commentCount: 0),
            OutpostPost(
                id: id(207), author: batman,
                body: "expectations for #Doomsday: managed. hill I will hold: DC peaked with __Young Justice__ and *New Frontier*, and no budget has matched them since.",
                postedAt: ago(20), commentCount: 0),
        ].sorted { $0.postedAt > $1.postedAt }
    }

    static func comments(for post: OutpostPost) -> [OutpostComment] {
        post.previewComments
    }

    static func isDemo(_ post: OutpostPost) -> Bool {
        authors.contains { $0.id == post.author.id }
    }
}
