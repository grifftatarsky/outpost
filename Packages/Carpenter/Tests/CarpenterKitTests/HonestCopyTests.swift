import Foundation
import Testing

@testable import CarpenterKit

@Suite("Honest copy")
struct HonestCopyTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let now = Date(timeIntervalSince1970: 1_786_635_000)

    private var summary: SyncSummary {
        SyncSummary(calendar: calendar, locale: Locale(identifier: "en_GB"))
    }

    // MARK: Sync footer

    @Test("Two peers are named and the rest are counted")
    func syncFooterNamesTwo() {
        let line = summary.caughtUpLine(
            peers: ["Cassilda", "Hastur", "Yhtill", "Camilla", "Thale", "Naotalba"],
            at: now.addingTimeInterval(-20),
            now: now
        )
        #expect(line == "Caught up with Cassilda, Hastur and 4 others a moment ago.")
    }

    @Test("One and two peers read as a sentence, not as a list with a count of zero")
    func syncFooterSmallGroups() {
        #expect(
            summary.caughtUpLine(peers: ["Cassilda"], at: now, now: now)
                == "Caught up with Cassilda a moment ago.")
        #expect(
            summary.caughtUpLine(peers: ["Cassilda", "Hastur"], at: now, now: now)
                == "Caught up with Cassilda and Hastur a moment ago.")
    }

    @Test("A third peer is counted in the singular")
    func syncFooterSingularOther() {
        #expect(
            summary.caughtUpLine(peers: ["Cassilda", "Hastur", "Yhtill"], at: now, now: now)
                == "Caught up with Cassilda, Hastur and 1 other a moment ago.")
    }

    @Test("Reaching nobody is not news, so the row says nothing and takes its space with it")
    func syncFooterNoPeers() {
        #expect(summary.caughtUpLine(peers: [], knowsAnyone: true, at: now, now: now) == nil)
    }

    @Test("Reaching somebody is still reported, and never as a last-synced time")
    func syncFooterReportsWhatHappened() {
        let line = summary.caughtUpLine(peers: ["Cassilda"], at: now, now: now)
        #expect(line == "Caught up with Cassilda a moment ago.")
        #expect(line?.lowercased().contains("last sync") == false)
    }

    @Test("Recency degrades in plain words")
    func syncFooterRecency() {
        func line(_ ago: TimeInterval) -> String? {
            summary.caughtUpLine(peers: ["Cassilda"], at: now.addingTimeInterval(-ago), now: now)
        }
        #expect(line(90) == "Caught up with Cassilda 1 minute ago.")
        #expect(line(600) == "Caught up with Cassilda 10 minutes ago.")
        #expect(line(3_600) == "Caught up with Cassilda 1 hour ago.")
        #expect(line(10_800) == "Caught up with Cassilda 3 hours ago.")
        #expect(line(86_400) == "Caught up with Cassilda yesterday.")
        #expect(line(86_400 * 30) == "Caught up with Cassilda on 14/07/2026.")
    }

    // MARK: Tag filter

    @Test("A filtered list says how much of the list it is showing")
    func tagFilterLine() {
        #expect(
            TagFilterSummary.line(matching: 3, of: 9, tagName: "Projects")
                == "3 of 9 rooms tagged Projects. Tags are only on your devices — nobody in these rooms can see them."
        )
    }

    @Test("A filter matching nothing says so rather than showing a zero")
    func tagFilterEmpty() {
        #expect(
            TagFilterSummary.line(matching: 0, of: 9, tagName: "Reading")
                == "No rooms tagged Reading. Tags are only on your devices — nobody in these rooms can see them."
        )
    }

    @Test("The privacy note claims what is true of every device, not just this one")
    func tagPrivacyNoteIsAccurate() {
        let line = TagFilterSummary.line(matching: 1, of: 2, tagName: "Daily")

        #expect(line.contains("your devices"))
        #expect(!line.contains("this device"))
    }

    // MARK: Outpost audience

    @Test("The audience line counts people, and says nothing about rooms")
    func audiencePlural() throws {
        let line = try #require(AudienceSummary.line(people: 14))
        #expect(line == "Visible to 14 people.")
        #expect(!line.localizedCaseInsensitiveContains("room"))
    }

    @Test("Singulars read as English, not as a template")
    func audienceSingular() {
        #expect(AudienceSummary.line(people: 1) == "Visible to 1 person.")
        #expect(AudienceSummary.line(people: 4) == "Visible to 4 people.")
    }

    @Test("An audience of nobody is left unsaid, never rounded up to a promise")
    func audienceEmpty() {
        #expect(AudienceSummary.line(people: 0) == nil)
    }

    @Test("A member who knows nobody is told nothing, not that nobody answered")
    func nobodyToReachSaysNothing() {
        let now = Date(timeIntervalSince1970: 1_786_635_000)
        #expect(SyncSummary().caughtUpLine(peers: [], knowsAnyone: false, at: now, now: now) == nil)
    }

    @Test("A room you are alone in is nobody to reach")
    func aloneInARoomIsStillAlone() {
        func room(_ members: Int) -> RoomSummary {
            RoomSummary(
                name: "Kitchen", memberCount: members, lastAuthor: nil, lastMessage: "",
                lastActivity: Date(timeIntervalSince1970: 0), hasUnread: false)
        }

        #expect(!SyncSummary.hasAnyoneToReach(in: []))
        #expect(!SyncSummary.hasAnyoneToReach(in: [room(1)]))
        #expect(!SyncSummary.hasAnyoneToReach(in: [room(1), room(1)]))
        #expect(SyncSummary.hasAnyoneToReach(in: [room(1), room(2)]))
    }
}
