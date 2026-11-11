@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("What an Outpost reader is handed", .serialized, .tags(.membership, .manyDevices))
struct WhatAnOutpostReaderIsHandedTests {
    private func aliceWithATablet(readers: [String]) async throws -> (Gathering, RoomID) {
        let g = try await Gathering.of(["Alice"] + readers)
        _ = try await g.room("Lanterns", host: "Alice", guests: readers)
        try await g["Alice"].send("the first post", to: nil)
        try await g.secondDevice("Alice's tablet", of: "Alice")
        let wall = g["Alice"].outpostRoom(for: g.id("Alice"))
        let shared = try #require(g.key(of: wall, on: "Alice"), "precondition: Alice's Outpost has a key")
        try #require(
            g.key(of: wall, on: "Alice's tablet") == shared,
            "precondition: both of Alice's devices write her Outpost under one key")
        return (g, wall)
    }

    @Test("A reader let in from now is handed no key from before they came in, whichever device made it")
    func aReaderLetInFromNowIsNotHandedARivalKeyBelowWhereTheyCameIn() async throws {
        let (g, wall) = try await aliceWithATablet(readers: ["Ro", "Rae", "Yan"])

        try await g["Alice"].allowOutpost(g.id("Ro"), everything: false)
        try await g["Alice"].send("from the phone, before Yan", to: nil)
        try await g["Alice's tablet"].allowOutpost(g.id("Rae"), everything: false)
        try await g["Alice's tablet"].send("from the tablet, before Yan", to: nil)
        try #require(
            g.key(of: wall, on: "Alice") != g.key(of: wall, on: "Alice's tablet"),
            "precondition: each device made its own key")
        try await g.settle()
        let rivals = try #require(g["Alice"].chains[wall])
        try #require(rivals.heldKeyCount > rivals.knownEpochs.count, "precondition: the phone holds both keys")

        try await g["Alice"].allowOutpost(g.id("Yan"), everything: false)
        let cameIn = try #require(g["Alice"].chains[wall]?.highestKnownEpoch)
        try await g["Alice"].send("after Yan", to: nil)
        try await g.settle()

        let held = try #require(g["Yan"].chains[wall])
        #expect(held.heldNumbers.allSatisfy { $0 >= cameIn }, "Yan holds a key from before Yan came in")
        let read = g["Yan"].feed().map(\.body)
        #expect(read.contains("after Yan"), "Yan cannot read what was posted after coming in")
        #expect(!read.contains("from the phone, before Yan"), "Yan read the phone's post from before coming in")
        #expect(!read.contains("from the tablet, before Yan"), "Yan read the tablet's post from before coming in")
        #expect(!read.contains("the first post"), "Yan read the first post")
    }

    @Test("A reader is handed no key another of the owner's devices made, at the same number, before they came in")
    func aReaderIsNotHandedARivalKeyAtTheNumberTheyCameInAt() async throws {
        let (g, wall) = try await aliceWithATablet(readers: ["Rae", "Yan"])

        try await g["Alice's tablet"].allowOutpost(g.id("Rae"), everything: false)
        try await g["Alice's tablet"].send("from the tablet, before Yan", to: nil)
        try await g["Alice"].allowOutpost(g.id("Yan"), everything: false)
        try #require(
            g.key(of: wall, on: "Alice") != g.key(of: wall, on: "Alice's tablet"),
            "precondition: the phone let Yan in without the tablet's key")
        try await g["Alice"].send("after Yan", to: nil)
        try await g.settle()

        let read = g["Yan"].feed().map(\.body)
        withKnownIssue("where a reader came in is a key's number, and two devices can each make a key at one number",
            isIntermittent: true)
        {
            #expect(read.contains("after Yan"), "Yan cannot read what was posted after coming in")
            #expect(!read.contains("from the tablet, before Yan"), "Yan read the tablet's post from before coming in")
        }
    }

    @Test("A post the owner's other device writes after a reader came in, under a key made out of touch, reaches them")
    func aPostFromADeviceThatWasOutOfTouchStillReachesTheReader() async throws {
        let (g, _) = try await aliceWithATablet(readers: ["Ro", "Rae", "Yan"])

        g.away("Alice's tablet")
        try await g["Alice"].allowOutpost(g.id("Ro"), everything: false)
        try await g["Alice"].allowOutpost(g.id("Yan"), everything: false)
        try await g.settle()
        try await g["Alice's tablet"].allowOutpost(g.id("Rae"), everything: false)
        try await g["Alice's tablet"].send("from the tablet, after Yan", to: nil)
        g.back("Alice's tablet")
        try await g.settle()

        let read = g["Yan"].feed().map(\.body)
        withKnownIssue("a key numbered below where a reader came in is withheld even when it was made afterwards") {
            #expect(read.contains("from the tablet, after Yan"), "Yan cannot read a post made after Yan came in")
        }
    }
}
