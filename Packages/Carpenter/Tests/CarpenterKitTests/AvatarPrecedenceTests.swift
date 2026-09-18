import CarpenterUI
import Testing

@Suite("Which picture is drawn for somebody")
struct AvatarPrecedenceTests {
    private func source(
        isViewer: Bool = false,
        onOutpost: Bool = false,
        own: Bool = true,
        ownOutpost: Bool = true,
        chosen: Bool = true,
        outpost: Bool = true,
        rooms: Bool = true
    ) -> AvatarSource {
        avatarSource(
            isViewer: isViewer, onOutpost: onOutpost, hasOwn: own, hasOwnOutpost: ownOutpost,
            hasChosen: chosen, hasOutpost: outpost, hasRooms: rooms)
    }

    @Test("A photo the reader chose beats everything the other person published")
    func chosenWins() {
        #expect(source() == .chosen)
        #expect(source(onOutpost: true) == .chosen)
    }

    @Test("On a wall, the picture its owner put there leads")
    func wallLeadsOnAWall() {
        #expect(source(onOutpost: true, chosen: false) == .outpost)
        #expect(source(onOutpost: true, chosen: false, outpost: false) == .rooms)
    }

    @Test("Off a wall, the picture their rooms see leads")
    func roomsLeadElsewhere() {
        #expect(source(chosen: false) == .rooms)
    }

    @Test("Each stands in for the other where there is only one")
    func eachStandsIn() {
        #expect(source(chosen: false, rooms: false) == .outpost)
        #expect(source(onOutpost: true, chosen: false, outpost: false) == .rooms)
    }

    @Test("Nothing at all is the monogram")
    func nothingIsInitials() {
        #expect(source(chosen: false, outpost: false, rooms: false) == .monogram)
        #expect(source(onOutpost: true, chosen: false, outpost: false, rooms: false) == .monogram)
    }

    @Test("The viewer is recognised rather than looked up")
    func theViewerIsShortCircuited() {
        #expect(source(isViewer: true, chosen: false, outpost: false, rooms: false) == .own)
        #expect(
            source(isViewer: true, onOutpost: true, chosen: false, outpost: false, rooms: false)
                == .ownOutpost)
    }

    @Test("The viewer's own picture is not overruled by anything keyed to them")
    func theViewerIsNotOverruled() {
        #expect(source(isViewer: true) == .own)
        #expect(source(isViewer: true, onOutpost: true) == .ownOutpost)
    }

    @Test("No picture on the wall is the monogram, whichever reason")
    func hiddenIsInitials() {
        #expect(source(isViewer: true, onOutpost: true, ownOutpost: false) == .monogram)
        #expect(source(isViewer: true, own: false) == .monogram)
    }
}
