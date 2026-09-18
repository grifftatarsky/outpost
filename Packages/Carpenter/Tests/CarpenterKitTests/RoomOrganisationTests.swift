import Foundation
import Testing

@testable import CarpenterKit

@Suite("Rooms list organisation")
struct RoomOrganisationTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let phone = DeviceKeys.generate().id
    private let mac = DeviceKeys.generate().id

    private func stamp(_ secondsIn: TimeInterval, on device: DeviceID? = nil) -> OrganisationStamp {
        OrganisationStamp(at: start.addingTimeInterval(secondsIn), device: device ?? phone)
    }

    private func room(_ name: String, minutesAgo: Int) -> RoomSummary {
        RoomSummary(
            name: name, memberCount: 4, lastAuthor: nil, lastMessage: "",
            lastActivity: start.addingTimeInterval(-Double(minutesAgo * 60)), hasUnread: false)
    }

    // MARK: Sorting

    @Test("With nothing pinned, the list is recency and nothing else")
    func recencyOnly() {
        let zeppelin = room("Zeppelin Enthusiasts", minutesAgo: 5)
        let hangar = room("Hangar 7", minutesAgo: 60)
        let carcosa = room("Carcosa", minutesAgo: 1)

        let arranged = RoomsListOrganisation().arrange([zeppelin, hangar, carcosa])

        #expect(arranged.map(\.name) == ["Carcosa", "Zeppelin Enthusiasts", "Hangar 7"])
    }

    @Test("Pinned rooms are held above the rest, however stale they are")
    func pinsSitOnTop() {
        let zeppelin = room("Zeppelin Enthusiasts", minutesAgo: 5)
        let hangar = room("Hangar 7", minutesAgo: 6_000)
        let carcosa = room("Carcosa", minutesAgo: 1)

        var organisation = RoomsListOrganisation()
        organisation.setPinned(true, for: hangar.id, stamp: stamp(0))

        let arranged = organisation.arrange([zeppelin, hangar, carcosa])

        #expect(arranged.map(\.name) == ["Hangar 7", "Carcosa", "Zeppelin Enthusiasts"])
    }

    @Test("Pins keep the order the member dragged them into")
    func pinsKeepTheirOrder() {
        let first = room("First", minutesAgo: 100)
        let second = room("Second", minutesAgo: 1)

        var organisation = RoomsListOrganisation()
        organisation.setPinned(true, for: first.id, stamp: stamp(0))
        organisation.setPinned(true, for: second.id, stamp: stamp(1))
        #expect(organisation.arrange([first, second]).map(\.name) == ["Second", "First"])

        organisation.movePin(second.id, between: first.id, and: nil, stamp: stamp(2))
        #expect(organisation.arrange([first, second]).map(\.name) == ["First", "Second"])
    }

    @Test("Unpinning drops a room back into recency")
    func unpin() {
        let stale = room("Stale", minutesAgo: 9_000)
        let fresh = room("Fresh", minutesAgo: 1)

        var organisation = RoomsListOrganisation()
        organisation.setPinned(true, for: stale.id, stamp: stamp(0))
        organisation.setPinned(false, for: stale.id, stamp: stamp(1))

        #expect(organisation.arrange([stale, fresh]).map(\.name) == ["Fresh", "Stale"])
        #expect(!organisation.isPinned(stale.id))
    }

    // MARK: Filtering

    @Test("A filter narrows the list but does not change how it is ordered")
    func filtering() {
        let zeppelin = room("Zeppelin Enthusiasts", minutesAgo: 5)
        let hangar = room("Hangar 7", minutesAgo: 6_000)
        let carcosa = room("Carcosa", minutesAgo: 1)

        var organisation = RoomsListOrganisation()
        let projects = organisation.addTag(named: "Projects", stamp: stamp(0))
        organisation.setTag(projects, on: true, for: hangar.id, stamp: stamp(1))
        organisation.setTag(projects, on: true, for: carcosa.id, stamp: stamp(2))
        organisation.setPinned(true, for: hangar.id, stamp: stamp(3))

        let all = organisation.arrange([zeppelin, hangar, carcosa])
        let filtered = organisation.arrange([zeppelin, hangar, carcosa], filteredBy: projects)

        #expect(all.count == 3)
        #expect(filtered.map(\.name) == ["Hangar 7", "Carcosa"])
    }

    @Test("A tag nobody has used filters to nothing rather than to everything")
    func emptyFilter() {
        var organisation = RoomsListOrganisation()
        let unused = organisation.addTag(named: "Reading", stamp: stamp(0))

        #expect(organisation.arrange([room("A", minutesAgo: 1)], filteredBy: unused).isEmpty)
    }

    @Test("Counts on the manage screen are local counts")
    func tagCounts() {
        let a = room("A", minutesAgo: 1)
        let b = room("B", minutesAgo: 2)

        var organisation = RoomsListOrganisation()
        let tag = organisation.addTag(named: "Airships", stamp: stamp(0))
        organisation.setTag(tag, on: true, for: a.id, stamp: stamp(1))
        organisation.setTag(tag, on: true, for: b.id, stamp: stamp(2))
        organisation.setTag(tag, on: false, for: b.id, stamp: stamp(3))

        #expect(organisation.roomCount(taggedWith: tag) == 1)
    }

    @Test("Deleting a tag leaves the rooms, their pins and their mute state alone")
    func deletingATagChangesNothingElse() {
        let a = room("A", minutesAgo: 1)

        var organisation = RoomsListOrganisation()
        let tag = organisation.addTag(named: "Airships", stamp: stamp(0))
        organisation.setTag(tag, on: true, for: a.id, stamp: stamp(1))
        organisation.setPinned(true, for: a.id, stamp: stamp(2))

        organisation.removeTag(tag, stamp: stamp(4))

        #expect(organisation.tags[tag] == nil)
        #expect(organisation.tags(of: a.id).isEmpty)
        #expect(organisation.isPinned(a.id))
        #expect(organisation.arrange([a]).count == 1)
    }

    @Test("Leaving a room drops the member's organisation of it")
    func forgettingARoom() {
        let a = room("A", minutesAgo: 1)

        var organisation = RoomsListOrganisation()
        let tag = organisation.addTag(named: "Airships", stamp: stamp(0))
        organisation.setTag(tag, on: true, for: a.id, stamp: stamp(1))
        organisation.setPinned(true, for: a.id, stamp: stamp(2))

        organisation.forget(a.id)

        #expect(organisation.organisation(of: a.id) == nil)
        #expect(organisation.roomCount(taggedWith: tag) == 0)
    }

    @Test("The filter rail is ordered, and new tags land at the end")
    func railOrder() {
        var organisation = RoomsListOrganisation()
        organisation.addTag(named: "Airships", stamp: stamp(0))
        organisation.addTag(named: "Projects", stamp: stamp(1))
        organisation.addTag(named: "Daily", stamp: stamp(2))

        #expect(organisation.orderedTags.map(\.name.value) == ["Airships", "Projects", "Daily"])
    }

    @Test("Tags can be reordered, and the rail follows")
    func reorderTags() {
        var organisation = RoomsListOrganisation()
        let airships = organisation.addTag(named: "Airships", stamp: stamp(0))
        organisation.addTag(named: "Projects", stamp: stamp(1))
        let daily = organisation.addTag(named: "Daily", stamp: stamp(2))

        organisation.moveTag(daily, between: nil, and: airships, stamp: stamp(3))

        #expect(organisation.orderedTags.map(\.name.value) == ["Daily", "Airships", "Projects"])
    }

    @Test("A tag can be moved to the end as well as the front")
    func reorderToEnd() {
        var organisation = RoomsListOrganisation()
        let airships = organisation.addTag(named: "Airships", stamp: stamp(0))
        organisation.addTag(named: "Projects", stamp: stamp(1))
        let daily = organisation.addTag(named: "Daily", stamp: stamp(2))

        organisation.moveTag(airships, between: daily, and: nil, stamp: stamp(3))

        #expect(organisation.orderedTags.map(\.name.value) == ["Projects", "Daily", "Airships"])
    }

    @Test("Two devices moving different tags keep both moves")
    func concurrentTagMovesCommute() {
        var base = RoomsListOrganisation()
        let a = base.addTag(named: "A", stamp: stamp(0))
        let b = base.addTag(named: "B", stamp: stamp(1))
        let c = base.addTag(named: "C", stamp: stamp(2))

        var onPhone = base
        onPhone.moveTag(c, between: nil, and: a, stamp: stamp(10, on: phone))

        var onMac = base
        onMac.rename(b, to: "Bravo", stamp: stamp(11, on: mac))

        let merged = onPhone.merged(with: onMac)

        #expect(merged.orderedTags.map(\.name.value) == ["C", "A", "Bravo"])
        #expect(merged == onMac.merged(with: onPhone))
    }

    // MARK: Merge — Design Decision P5

    @Test("Two devices editing different rooms both keep their edit")
    func disjointEditsCommute() {
        let a = room("A", minutesAgo: 1)
        let b = room("B", minutesAgo: 2)

        var onPhone = RoomsListOrganisation()
        onPhone.setPinned(true, for: a.id, stamp: stamp(10, on: phone))

        var onMac = RoomsListOrganisation()
        let tag = onMac.addTag(named: "Airships", stamp: stamp(11, on: mac))
        onMac.setTag(tag, on: true, for: b.id, stamp: stamp(12, on: mac))

        let merged = onPhone.merged(with: onMac)
        let other = onMac.merged(with: onPhone)

        #expect(merged.isPinned(a.id))
        #expect(merged.tags(of: b.id).contains(tag))
        #expect(merged == other)
    }

    @Test("When two devices set the same field, the later write wins")
    func lastWriterWins() {
        let a = room("A", minutesAgo: 1)

        var onPhone = RoomsListOrganisation()
        onPhone.setPinned(true, for: a.id, stamp: stamp(10, on: phone))

        var onMac = RoomsListOrganisation()
        onMac.setPinned(false, for: a.id, stamp: stamp(20, on: mac))

        #expect(onPhone.merged(with: onMac).isPinned(a.id) == false)
        #expect(onMac.merged(with: onPhone).isPinned(a.id) == false)
    }

    @Test("A simultaneous write resolves the same way on both devices")
    func tiesResolveDeterministically() {
        let a = room("A", minutesAgo: 1)
        let moment = start.addingTimeInterval(10)

        var onPhone = RoomsListOrganisation()
        onPhone.setPinned(true, for: a.id, stamp: OrganisationStamp(at: moment, device: phone))

        var onMac = RoomsListOrganisation()
        onMac.setPinned(false, for: a.id, stamp: OrganisationStamp(at: moment, device: mac))

        #expect(onPhone.merged(with: onMac) == onMac.merged(with: onPhone))
    }

    @Test("Two devices moving different pins keep both moves")
    func concurrentPinMovesCommute() {
        let a = room("A", minutesAgo: 1)
        let b = room("B", minutesAgo: 2)
        let c = room("C", minutesAgo: 3)

        var base = RoomsListOrganisation()
        base.setPinned(true, for: a.id, stamp: stamp(0))
        base.setPinned(true, for: b.id, stamp: stamp(1))
        base.setPinned(true, for: c.id, stamp: stamp(2))
        #expect(base.arrange([a, b, c]).map(\.name) == ["C", "B", "A"])

        var onPhone = base
        onPhone.movePin(c.id, between: b.id, and: a.id, stamp: stamp(10, on: phone))

        var onMac = base
        let tag = onMac.addTag(named: "Airships", stamp: stamp(11, on: mac))
        onMac.setTag(tag, on: true, for: b.id, stamp: stamp(12, on: mac))

        let merged = onPhone.merged(with: onMac)

        #expect(merged.arrange([a, b, c]).map(\.name) == ["B", "C", "A"])
        #expect(merged.tags(of: b.id).contains(tag), "the other device's edit survives the move")
    }

    @Test("Merging is idempotent and commutative across a whole list")
    func mergeIsAJoin() {
        let a = room("A", minutesAgo: 1)
        let b = room("B", minutesAgo: 2)

        var onPhone = RoomsListOrganisation()
        let airships = onPhone.addTag(named: "Airships", stamp: stamp(1, on: phone))
        onPhone.setTag(airships, on: true, for: a.id, stamp: stamp(2, on: phone))
        onPhone.setPinned(true, for: a.id, stamp: stamp(3, on: phone))

        var onMac = RoomsListOrganisation()
        let projects = onMac.addTag(named: "Projects", stamp: stamp(4, on: mac))
        onMac.setTag(projects, on: true, for: b.id, stamp: stamp(5, on: mac))

        let merged = onPhone.merged(with: onMac)

        #expect(merged == onMac.merged(with: onPhone))
        #expect(merged.merged(with: merged) == merged)
        #expect(merged.orderedTags.count == 2)
        #expect(merged.tags(of: a.id) == [airships])
        #expect(merged.tags(of: b.id) == [projects])
    }

    @Test("A rename made on one device reaches the other")
    func renamesMerge() {
        var onPhone = RoomsListOrganisation()
        let tag = onPhone.addTag(named: "Airships", stamp: stamp(1, on: phone))

        var onMac = onPhone
        onMac.rename(tag, to: "Lighter than air", stamp: stamp(10, on: mac))

        #expect(onPhone.merged(with: onMac).tags[tag]?.name.value == "Lighter than air")
    }
}
