import Testing

@testable import CarpenterUI

@Suite("Where the wide layout opens, and where a room lives in it")
struct WideAreaTests {
    @Test func aSplitInboxOpensOnRoomsAndAMergedOneOnMessages() {
        #expect(WideArea.home(splitInbox: true) == .messages(.groups))
        #expect(WideArea.home(splitInbox: false) == .messages(.everything))
    }

    @Test func aSoloLivesUnderSolosOnlyWhenTheInboxIsSplit() {
        #expect(WideArea.holding(isDirect: true, splitInbox: true) == .messages(.direct))
        #expect(WideArea.holding(isDirect: false, splitInbox: true) == .messages(.groups))
        #expect(WideArea.holding(isDirect: true, splitInbox: false) == .messages(.everything))
    }

    @Test func mergingTheInboxFoldsSolosAndRoomsIntoMessages() {
        for scope in [InboxScope.direct, .groups, .everything] {
            #expect(
                WideArea.messages(scope).normalised(splitInbox: false, showsOutposts: true)
                    == .messages(.everything))
        }
    }

    @Test func splittingTheInboxSendsMessagesToRoomsAndKeepsTheOthers() {
        #expect(
            WideArea.messages(.everything).normalised(splitInbox: true, showsOutposts: true)
                == .messages(.groups))
        #expect(
            WideArea.messages(.direct).normalised(splitInbox: true, showsOutposts: true)
                == .messages(.direct))
    }

    @Test func turningOutpostsOffLeavesTheOutpostsArea() {
        #expect(WideArea.outposts.normalised(splitInbox: true, showsOutposts: false) == .messages(.groups))
        #expect(WideArea.outposts.normalised(splitInbox: false, showsOutposts: true) == .outposts)
        #expect(WideArea.search.normalised(splitInbox: false, showsOutposts: false) == .search)
        #expect(WideArea.you.normalised(splitInbox: true, showsOutposts: false) == .you)
    }
}
