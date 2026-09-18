import Foundation
import Testing
import CarpenterKitTesting

@testable import CarpenterKit

@Suite("What an Outpost tells you")
struct WhatAnOutpostTellsYouTests {
    @Test("Every switch is independent of the other three")
    func independent() {
        for flipped in OutpostNotificationChoices.Kind.allCases {
            var choices = OutpostNotificationChoices.none
            choices[keyPath: flipped.path] = true

            for other in OutpostNotificationChoices.Kind.allCases where other != flipped {
                #expect(
                    choices.wants(other) == false,
                    "turning on \(flipped.rawValue) also turned on \(other.rawValue)")
            }
            #expect(choices.wants(flipped), "turning on \(flipped.rawValue) did not turn it on")
            #expect(
                choices.newPosts == .none,
                "turning on \(flipped.rawValue) also changed what new posts do")
        }
    }

    @Test("Nothing about reactions is on by default")
    func reactionsStartOff() {
        let fresh = OutpostNotificationChoices.default
        #expect(fresh.newPosts == .each, "new posts should defer to each Outpost's own switch")
        #expect(fresh.commentsOnMyPosts)
        #expect(fresh.repliesOnPostsICommentedOn)
        #expect(!fresh.repliesOnPostsIReactedTo, "reacting is not the same as joining in")
        #expect(!fresh.likesOnMyPosts, "a reaction should not light up a phone until asked")
        #expect(fresh.wantsAnything)
    }

    @Test("New posts has three answers and they do not collapse")
    func newPostsIsThreeWay() {
        #expect(OutpostNotificationChoices.none.newPosts == .none)
        #expect(!OutpostNotificationChoices.none.wantsAnything)

        var everything = OutpostNotificationChoices.none
        everything.newPosts = .all
        #expect(everything.wantsAnything, "All posts is something, so the page must not read Off")
        #expect(everything.wantedCount == 1)

        var perWall = OutpostNotificationChoices.none
        perWall.newPosts = .each
        #expect(perWall.wantsAnything, "By Outpost is an answer, not silence")
    }

    @Test("Saying no to everything wants nothing")
    func noneWantsNothing() {
        #expect(!OutpostNotificationChoices.none.wantsAnything)
        #expect(OutpostNotificationChoices.none.likesOnMyPosts == false)
    }

    @Test("Never having answered is not the same as answering no")
    func neverAsked() {
        var prefs = MemberPreferences()
        #expect(prefs.outpostNotifications == nil, "a fresh member has not been asked")
        #expect(prefs.outpostNotificationChoices == .default)

        let stamp = OrganisationStamp(
            at: Date(timeIntervalSince1970: 1), device: DeviceID(rawValue: WideID.of([1])))
        prefs.setOutpostNotifications(.none, stamp: stamp)
        #expect(prefs.outpostNotifications != nil, "answering is recorded, even when the answer is no")
        #expect(!prefs.outpostNotificationChoices.wantsAnything)
    }

    @Test("A choice made on one device is the choice on the other")
    func crossesDevices() throws {
        let stamp = OrganisationStamp(
            at: Date(timeIntervalSince1970: 10), device: DeviceID(rawValue: WideID.of([1])))
        var phone = MemberPreferences()
        phone.setOutpostNotifications(
            OutpostNotificationChoices(
                newPosts: .all, repliesOnPostsICommentedOn: true, repliesOnPostsIReactedTo: false,
                commentsOnMyPosts: false, likesOnMyPosts: true),
            stamp: stamp)

        let travelled = try JSONDecoder().decode(
            MemberPreferences.self, from: JSONEncoder().encode(phone))
        let pad = MemberPreferences().merged(with: travelled)

        #expect(pad.outpostNotificationChoices == phone.outpostNotificationChoices)
        #expect(pad.outpostNotificationChoices.likesOnMyPosts)
        #expect(pad.outpostNotificationChoices.newPosts == .all)
    }

    @Test("The later answer wins")
    func laterWins() {
        let device = DeviceID(rawValue: WideID.of([1]))
        var early = MemberPreferences()
        early.setOutpostNotifications(
            .none, stamp: OrganisationStamp(at: Date(timeIntervalSince1970: 1), device: device))
        var late = MemberPreferences()
        late.setOutpostNotifications(
            .default, stamp: OrganisationStamp(at: Date(timeIntervalSince1970: 2), device: device))

        #expect(early.merged(with: late).outpostNotificationChoices == .default)
        #expect(late.merged(with: early).outpostNotificationChoices == .default)
    }
}
