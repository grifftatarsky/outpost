import Foundation
import Testing

@testable import CarpenterKit

@Suite("What the app icon means")
struct WhatTheAppIconMeansTests {
    @Test("Every combination of the two switches has one true sentence")
    func everyCombinationIsCovered() {
        let cases: [(Bool, Bool, BadgeChoices.Meaning)] = [
            (true, true, .both),
            (false, true, .outpostsOnly),
            (true, false, .messagesOnly),
            (false, false, .off),
        ]
        for (messages, outposts, expected) in cases {
            #expect(
                BadgeChoices(messages: messages, outposts: outposts).meaning == expected,
                "messages=\(messages) outposts=\(outposts) described itself wrongly")
        }
    }

    @Test("Both halves of the badge start on")
    func bothStartOn() {
        #expect(BadgeChoices.default.messages)
        #expect(BadgeChoices.default.outposts)
        #expect(BadgeChoices.default.meaning == .both)
    }

    @Test("Turning messages off keeps what a banner would have said")
    func theLevelSurvivesBeingTurnedOff() {
        var choices = MessagingNotificationChoices.default
        choices.level = .whereOnly
        choices.roomUpdateLevel = .whatOnly

        choices.wantsMessages = false
        #expect(
            choices.level == .whereOnly,
            "turning messages off forgot how much a banner should say")

        choices.wantsMessages = true
        #expect(choices.level == .whereOnly, "turning it back on did not restore the last answer")
        #expect(choices.roomUpdateLevel == .whatOnly)
    }

    @Test("A room change's detail is its own setting")
    func roomDetailIsSeparate() {
        var choices = MessagingNotificationChoices.default
        choices.level = .everything
        choices.roomUpdateLevel = .nothing

        #expect(choices.level == .everything)
        #expect(choices.roomUpdateLevel == .nothing)
        #expect(!choices.roomUpdateLevel.namesThePerson)
        #expect(!choices.roomUpdateLevel.namesTheRoom)
        #expect(!choices.roomUpdateLevel.namesWhatHappened)
    }

    @Test("Each room-change rung says strictly less than the one above")
    func rungsDescend() {
        let ladder: [RoomUpdateLevel] = [.whoAndWhere, .whereOnly, .whatOnly, .nothing]
        let facts = ladder.map {
            [$0.namesThePerson, $0.namesTheRoom, $0.namesWhatHappened].count { $0 }
        }
        #expect(facts == [3, 2, 1, 0], "the rungs are not a descending scale: \(facts)")
    }
}
