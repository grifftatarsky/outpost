<!-- COPY BEGIN f55410ad [NEEDS HUMAN REVIEW] -->

# Work order: plan step 9, the rooms view's eleven sheets behind one enum

> **A working design, written by agents on 2026-11-10 and 2026-11-11 and kept so the work need not be
> done again.** Nothing in it is a ruling. Where it names a file under `scratchpad/`, that was a
> working file and was not kept. Line numbers are from the commit it names and will drift.
> What is waiting on Griff is in [the Part B plan](../../part-b-plan.md).

Source of the step: `docs/pre-testflight.md:127-128`.

Read at commit `9af603a` on `overnight-2026-10-31`, 2026-11-10. The Swift files named here had no
uncommitted changes when read. Every line number is from that commit. Nothing was built or run for
this work order: every statement about what SwiftUI does at run time is marked "inferred" or
"not verified" unless a source is given.

Paths are relative to `/Users/grifftatarsky/projects/outpost`. `UI/` below means
`Packages/Carpenter/Sources/CarpenterUI/`.

---

## 1. What is there now

The view is `RootView.roomDestination(_:)`, `UI/Screens/RootView+Rooms.swift:69-241`. It builds the
`ConversationView` for one room and hangs eleven `.sheet(item:)` modifiers on it (lines 124-239).
Their state is eleven `@State` properties on `RootView` (`UI/Screens/RootView.swift:13-17, 21-25, 31`).

`roomDestination` is called from three places: `RootView+Phone.swift:62` (Messages or Solos tab),
`RootView+Phone.swift:109` (Rooms tab, split inbox only), `RootView+Desktop.swift:80` (Mac).

| # | State (`RootView.swift` line) | Sheet at (`RootView+Rooms.swift`) | What sets it | What it shows | What it is passed |
|---|---|---|---|---|---|
| 1 | `greeting: RoomGreeting?` (22) | 124-127 | `.task(id: id)`, line 129, when the room opens | `JoinPromptView(greeting:onOpen:)`, `.interactiveDismissDisabled()` | the `RoomGreeting`; `onGreetingSeen(greeted.id)` |
| 2 | `offeringComparison: ComparisonOffer?` (17) | 137-139 | `offerComparison(in:)` lines 44-49; called from `.task(id:)` line 131 when there is no greeting, and from `.onChange(of: greeting)` lines 133-136 when the greeting closes | `ComparisonOfferView(offer:onMarkChecked:)` | the offer (room, people); `onMarkChecked`. `onComparisonOffered` is called when the state is set (line 48) |
| 3 | `viewingMembers: RoomID?` (23) | 140-162 | room menu *Who is in this room* (`UI/Screens/Messaging/ConversationView+Menu.swift:23-31`) through `onRoomMembers`, line 104; nil for a Solo | `NavigationStack { RoomMembersView }`, `.presentingReportedProblems()`, `.environment(\.leavingThisRoom, leaving(room))` | room name, `roomMembers`, `roomInvitations`, `viewer`, `roomStanding(room).mayWrite`, `onRemoveMember`, `onRescindInvitation`, `pendingJoins`, `onDecideJoin`, `messageActions.block`, `personPage` |
| 4 | `starting: RoomID?` (31) | 163-176 | room menu *Invite someone* (`ConversationView+Menu.swift:32-40`) through `onInvite`, line 89; nil for a Solo. Also the member list, line 150 | `StartInviteView(roomName:onIssue:)` (`UI/Screens/Membership/InviteView.swift:221`) | room name; `onInvite(room, code, lifetime)` |
| 5 | `showingWaiting: RoomID?` (25) | 177-183 | room menu *Who this is waiting on* (`ConversationView+Menu.swift:94-102`) and the not-sent mark's explanation (`UI/Components/Messaging/NotGoneExplanation.swift:78`), both through `notGoneHelp(for:)` lines 57-67 | `NavigationStack { WaitingOnView }` | room name, `waitingOn(room)` |
| 6 | `checkingWho: RoomID?` (16) | 184-191 | room menu *Who you are talking to* (`ConversationView+Menu.swift:74-82`), line 92 | `NavigationStack { WhoYouAreTalkingToView }` | room name, `whoYouAreTalkingTo(room)`, `onMarkChecked` |
| 7 | `showingOutstanding: RoomID?` (14) | 192-196 | room menu *Show the invite* (`ConversationView+Menu.swift:41-49`), line 90; only when `hasAnInviteToShow` (lines 39-42: a Solo with my unconfirmed invitation) | `OutstandingInviteSheet(roomName:load:)` (`InviteView.swift:168-219`), which loads the invitation and shows `InviteView` or "no invitation standing" | room name, `onOutstandingInvite(room)` |
| 8 | `invite: PresentedInvite?` (13) | 197-204 | only `StartInviteView`'s `onIssue`, lines 170-172 | `InviteView(roomName:invite:phrase:notAskedYet:)` | the `PresentedInvite`; `phraseLookup` (`RootView.swift:104`) |
| 9 | `notifying: RoomID?` (24) | 205-219 | room menu *Notifications* (`ConversationView+Menu.swift:103-111`), line 103; and the not-sent explanation (`NotGoneExplanation.swift:77`) through `notGoneHelp`, line 65, when `roomNotGone != nil` | `NavigationStack { NotificationLevelView }` | level binding over `roomNotificationLevel` / `onRoomNotificationLevelChange`, optional room name, `roomFollowsDefaultNotifications`, `roomReceipts`, `roomNotGone` |
| 10 | `adjusting: RoomID?` (21) | 220-229 | room menu *Who gets in* (`ConversationView+Menu.swift:112-120`), line 102; nil for a Solo or when `roomAccess(id)` is nil | `RoomAccessView`, only if `roomAccess(room)` is non-nil | room name, `roomMembers`, the access, `onRoomAccessChange` |
| 11 | `reviewing: RoomID?` (15) | 230-239 | room menu *Review N waiting to join* / *Check who joined…* (`ConversationView+Menu.swift:50-62`), line 91; nil for a Solo | `JoinRequestsView`, `.presentingReportedProblems()` | room name, `pendingJoins`, `onDecideJoin` |

No state is set from outside `RootView+Rooms.swift` (grep over `App` and `Packages`).

### The hand-overs

The plan says two. The code has two sheets that set another sheet's state, and one more sequence
that behaves the same way on screen. All three need the same watching.

- **H1, member list to Invite someone.** `RootView+Rooms.swift:149-150`:
  `onInvite: { viewingMembers = nil; starting = room }`. `RoomMembersView` does not dismiss itself
  here (`UI/Screens/Membership/RoomMembersView.swift:143-145`).
- **H2, Invite someone to the invitation.** `RootView+Rooms.swift:166-173`: `onIssue` sets `invite`
  while the Start sheet is still up and returns `true`; `StartInviteView` then calls `dismiss()`
  (`InviteView.swift:362-365`). That `dismiss()` runs after an `await`, and the sheet can be swiped
  away while the `await` is in flight.
- **H3, join prompt to the compare-codes offer.** `JoinPromptView` awaits `onOpen` and calls
  `dismiss()` (`UI/Screens/Membership/JoinPromptView.swift:34-40`); `.onChange(of: greeting)`
  (`RootView+Rooms.swift:133-136`) then starts a `Task` that sets `offeringComparison`. The prompt
  cannot be swiped away (line 126).

A fourth path arrives from outside the eleven and is already sequenced correctly: the not-sent
mark's own sheet closes, and its `onDismiss` calls back into `notGoneHelp` to open sheet 5 or 9
(`NotGoneExplanation.swift:71-81`). Only the state it writes changes.

---

## 2. What it must guarantee (Griff confirms before code, CLAUDE.md rule 1)

1. Every room sheet that opens today opens from the same control with the same content, and never
   more than one at a time.
2. When one sheet leads to another (H1, H2, H3), the second appears once, after the first has
   closed, and afterwards it closes normally and every room sheet can still be opened.
3. A sheet that has already gone cannot close a sheet that came after it.

Sentence 3 is the one a single shared binding can break: see H2 above and section 3.

---

## 3. The design

### Why a hand-over closes first and presents from `onDismiss`

- Apple's HIG, Sheets: "If something people do within a sheet results in another sheet appearing,
  close the first sheet before displaying the new one."
  https://developer.apple.com/design/human-interface-guidelines/sheets
- Apple documents that changing the item replaces the sheet: "If `item` changes, the system
  dismisses the sheet and replaces it with a new one using the same process."
  https://developer.apple.com/documentation/swiftui/view/sheet(item:ondismiss:content:)
- That documented replacement has been reported broken on earlier releases: a crash on iOS 16.4 and
  a present/dismiss loop on iOS 15.5 (https://developer.apple.com/forums/thread/728427), and a
  binding that stops being reset after one swap on iOS 14 and an iOS 15 beta
  (https://developer.apple.com/forums/thread/682219). Neither thread has an Apple reply. Whether
  iOS 27 still does this: not verified.
- This repository already sequences two hand-overs through `onDismiss` after setting the binding to
  nil in code: `RoomMembersView.swift:179-198` (`rescindingOnceChecked`) and
  `NotGoneExplanation.swift:71-96` (`next`).

So: the item is never changed straight from one sheet to another. A hand-over puts the next sheet
in a second `@State`, closes the current one, and the sheet's `onDismiss` presents what was left.
Both existing uses present the second sheet from a different modifier; presenting again from the
same modifier inside its own `onDismiss` is inferred to work and is the thing to watch (section 7).

### Why `StartInviteView` stops dismissing itself on success

With eleven bindings, a late `dismiss()` from a Start sheet that was already swiped away writes nil
to `starting` and touches nothing else. With one binding, the same late `dismiss()` may write nil
to the binding that by then holds the invitation, or another sheet the member opened meanwhile.
What a `DismissAction` from a sheet that has gone does is not documented
(https://developer.apple.com/documentation/swiftui/dismissaction says only that it dismisses "a
modal presentation, like a sheet" and that "the specific behavior of the action depends on where
you call it from"). Inferred hazard, not verified. Removing the call removes the question: on
success the rooms view closes the Start sheet itself. `StartInviteView` has one caller besides its
preview (`RootView+Rooms.swift:164`, `InviteView.swift:400`).

`JoinPromptView` keeps its `dismiss()`: it cannot be swiped away, so the call always lands while
the prompt is the sheet on screen. No other view among the eleven calls `dismiss()` after an
`await` (grep of the eleven view files).

### The enum

Identity is the kind of sheet plus what it is about, the same keys the eleven bindings use today
(`RoomID`; `RoomGreeting.id` and `ComparisonOffer.id` are the room; `PresentedInvite.id` is the
joiner). It is not the whole value: a greeting whose member list changed is still the same sheet.

`UI/Screens/RootTypes.swift`, after `PresentedInvite`:

```swift
enum RoomSheet: Identifiable, Sendable {
    case greeting(RoomGreeting)
    case comparing(ComparisonOffer)
    case members(RoomID)
    case inviting(RoomID)
    case invite(PresentedInvite)
    case outstandingInvite(RoomID)
    case joinRequests(RoomID)
    case whoYouAreTalkingTo(RoomID)
    case waitingOn(RoomID)
    case notifications(RoomID)
    case access(RoomID)

    enum ID: Hashable {
        case greeting(RoomID), comparing(RoomID), members(RoomID), inviting(RoomID)
        case invite(ParticipantID), outstandingInvite(RoomID), joinRequests(RoomID)
        case whoYouAreTalkingTo(RoomID), waitingOn(RoomID), notifications(RoomID), access(RoomID)
    }

    var id: ID {
        switch self {
        case .greeting(let greeted): .greeting(greeted.id)
        case .comparing(let offer): .comparing(offer.room)
        case .members(let room): .members(room)
        case .inviting(let room): .inviting(room)
        case .invite(let presented): .invite(presented.id)
        case .outstandingInvite(let room): .outstandingInvite(room)
        case .joinRequests(let room): .joinRequests(room)
        case .whoYouAreTalkingTo(let room): .whoYouAreTalkingTo(room)
        case .waitingOn(let room): .waitingOn(room)
        case .notifications(let room): .notifications(room)
        case .access(let room): .access(room)
        }
    }
}
```

`Sendable` is needed because `notGoneHelp(for:)` captures the binding in `@MainActor @Sendable`
closures (`RootView+Rooms.swift:58-59, 63`). `RoomGreeting` and `ComparisonOffer` are `Sendable`
(`CarpenterKit/Model/ReadModel.swift:345`, `UI/Screens/Membership/CompareCodesView.swift:135`);
`PresentedInvite` needs it stated (below). The package is in Swift 6 language mode
(`Packages/Carpenter/Package.swift:5`).

---

## 4. The changes, file by file

One commit for 4.1 to 4.5. No copy changes, so no COPY marker is touched or added.

### 4.1 `UI/Screens/RootTypes.swift`

- Line 5: `struct PresentedInvite: Identifiable {` becomes
  `struct PresentedInvite: Identifiable, Sendable {`. (`Invite` is `Sendable`,
  `CarpenterKit/Membership/Invite.swift:3`.)
- Add `RoomSheet` as written in section 3.
- Lines 13-15, `extension RoomID: Identifiable`: by grep the eleven bindings were its only users.
  Delete it, build the package, the app and both test targets; if anything fails for want of it,
  put it back unchanged.

### 4.2 `UI/Screens/RootView.swift`

Delete the eleven properties at lines 13-17, 21-25 and 31 (`invite`, `showingOutstanding`,
`reviewing`, `checkingWho`, `offeringComparison`, `adjusting`, `greeting`, `viewingMembers`,
`notifying`, `showingWaiting`, `starting`). Add in their place:

```swift
    @State var roomSheet: RoomSheet?
    @State var nextRoomSheet: RoomSheet?
```

Leave `askingConsent`, `aboutPerson`, `changingAccess`, `leaving`, `deleting`,
`reviewingAccessBefore` alone.

### 4.3 `UI/Screens/RootView+Rooms.swift`

**Lines 44-49**, replace `offerComparison(in:)` with:

```swift
    private func comparisonOffer(in room: RoomID) -> ComparisonOffer? {
        let people = comparisonToOffer(room)
        return people.isEmpty ? nil : ComparisonOffer(room: room, people: people)
    }
```

**Lines 57-67**, `notGoneHelp(for:)`:

```swift
    func notGoneHelp(for id: RoomID) -> NotGoneHelp {
        let presented = $roomSheet
        let showWaiting: @MainActor @Sendable () -> Void = { presented.wrappedValue = .waitingOn(id) }
        guard roomNotGone != nil else {
            return NotGoneHelp(reason: cannotSend, onShowWaiting: showWaiting)
        }
        return NotGoneHelp(
            reason: cannotSend, onChangeWait: { presented.wrappedValue = .notifications(id) },
            onShowWaiting: showWaiting)
    }
```

**The `ConversationView` arguments**, plain assignments, because nothing is on screen when a menu
item is tapped. `docs/inbox.md:359-361` records that an item set from a `Task` after a menu closed
does not present, so these stay synchronous:

| Line | Now | Becomes |
|---|---|---|
| 89 | `{ starting = id }` | `{ roomSheet = .inviting(id) }` |
| 90 | `{ showingOutstanding = id }` | `{ roomSheet = .outstandingInvite(id) }` |
| 91 | `{ reviewing = id }` | `{ roomSheet = .joinRequests(id) }` |
| 92 | `{ checkingWho = id }` | `{ roomSheet = .whoYouAreTalkingTo(id) }` |
| 102 | `{ adjusting = id }` | `{ roomSheet = .access(id) }` |
| 103 | `{ notifying = id }` | `{ roomSheet = .notifications(id) }` |
| 104 | `{ viewingMembers = id }` | `{ roomSheet = .members(id) }` |

Line 119 (`deleting = room`) is an alert on `body` and does not change.

**Lines 124-239**, replace the eleven `.sheet` modifiers, the `.task(id:)` and the `.onChange` with
this, directly after the three `.environment` lines (121-123), in this order:

```swift
            .sheet(item: $roomSheet, onDismiss: presentNextRoomSheet) { roomSheetView($0) }
            .task(id: id) {
                if let greeted = roomGreeting(id) {
                    roomSheet = .greeting(greeted)
                } else if let offer = comparisonOffer(in: id) {
                    roomSheet = .comparing(offer)
                } else if case .greeting = roomSheet {
                    roomSheet = nil
                }
            }
```

The last branch keeps what line 129 does today: a greeting left over from another room does not
stay up when this room has none.

Keep the sheet where it is, on the conversation, below `.modifier(surroundings)`. A sheet presented
from above `.themed` draws with the default dark palette (`docs/style.md:143-146`), which is why the
one sheet on `RootView.body` re-themes itself (`RootView.swift:573-582`). Do not move this one up to
`body` or `layout`.

**Add the content function** in the same extension. Each case body is the existing closure body
moved as it stands; the only edits are the four marked lines.

```swift
    @ViewBuilder
    private func roomSheetView(_ item: RoomSheet) -> some View {
        switch item {
        case .greeting(let greeted):
            JoinPromptView(greeting: greeted) {
                await onGreetingSeen(greeted.id)
                nextRoomSheet = comparisonOffer(in: greeted.id).map(RoomSheet.comparing)   // edit 1
            }
            .interactiveDismissDisabled()

        case .comparing(let offer):
            ComparisonOfferView(offer: offer, onMarkChecked: onMarkChecked)
                .task { await onComparisonOffered(offer.people.map(\.id)) }                // edit 2

        case .members(let room):
            NavigationStack {
                RoomMembersView(
                    roomName: rooms.first { $0.id == room }?.name ?? "",
                    members: roomMembers(room),
                    invited: roomInvitations(room),
                    viewer: viewer,
                    onRemove: roomStanding(room).mayWrite
                        ? { await onRemoveMember(room, $0) } : nil,
                    onInvite: roomStanding(room).mayWrite
                        ? { replaceRoomSheet(with: .inviting(room)) } : nil,               // edit 3
                    onBlock: messageActions.block.map { block in { person in await block(person) } },
                    onRescind: roomStanding(room).mayWrite
                        ? { person in await onRescindInvitation(room, person) } : nil,
                    joins: pendingJoins(room),
                    onDecide: roomStanding(room).mayWrite
                        ? { join, admit in await onDecideJoin(room, join, admit) } : nil,
                    personPage: { person, actions in personPage(person, actions: actions) }
                )
            }
            .presentingReportedProblems()
            .environment(\.leavingThisRoom, leaving(room))

        case .inviting(let room):
            StartInviteView(
                roomName: rooms.first { $0.id == room }?.name ?? "",
                onIssue: { code, lifetime in
                    guard let issued = await onInvite(room, code, lifetime) else {
                        return false
                    }
                    replaceRoomSheet(                                                      // edit 4
                        with: .invite(
                            PresentedInvite(
                                roomName: rooms.first { $0.id == room }?.name ?? "",
                                invite: issued)))
                    return true
                }
            )

        case .invite(let presented):
            InviteView(
                roomName: presented.roomName,
                invite: presented.invite,
                phrase: phraseLookup(presented.invite),
                notAskedYet: presented.notAskedYet
            )

        case .outstandingInvite(let room):
            OutstandingInviteSheet(
                roomName: rooms.first { $0.id == room }?.name ?? "",
                load: { await onOutstandingInvite(room) })

        case .joinRequests(let room):
            JoinRequestsView(
                roomName: rooms.first { $0.id == room }?.name ?? "",
                joins: { pendingJoins(room) },
                onDecide: { join, admit in
                    await onDecideJoin(room, join, admit)
                }
            )
            .presentingReportedProblems()

        case .whoYouAreTalkingTo(let room):
            NavigationStack {
                WhoYouAreTalkingToView(
                    roomName: rooms.first { $0.id == room }?.name ?? "",
                    people: whoYouAreTalkingTo(room),
                    onMarkChecked: onMarkChecked)
            }

        case .waitingOn(let room):
            NavigationStack {
                WaitingOnView(
                    roomName: rooms.first { $0.id == room }?.name ?? "",
                    people: waitingOn(room))
            }

        case .notifications(let room):
            NavigationStack {
                NotificationLevelView(
                    level: Binding(
                        get: { roomNotificationLevel(room) },
                        set: { value in
                            Task { await onRoomNotificationLevelChange(room, value) }
                        }),
                    room: rooms.first { $0.id == room }?.name,
                    followingDefault: roomFollowsDefaultNotifications(room),
                    receipts: roomReceipts.map { $0(room) },
                    notGone: roomNotGone.map { $0(room) }
                )
            }

        case .access(let room):
            if let current = roomAccess(room) {
                RoomAccessView(
                    roomName: rooms.first { $0.id == room }?.name ?? "",
                    members: roomMembers(room),
                    access: current,
                    onChange: { await onRoomAccessChange(room, $0) }
                )
            }
        }
    }
```

(Do not copy the `// edit N` markers into the source: the repository has no comments.)

If the compiler reports that it cannot type-check `roomSheetView` in reasonable time, move the
`.members` body into `private func roomMembersSheet(_ room: RoomID) -> some View` and call it from
the case. Nothing else.

**Add the two functions that sequence a hand-over, as the last members of the extension, after
`roomPath` (line 255-259):**

```swift
    private func replaceRoomSheet(with next: RoomSheet) {
        guard roomSheet != nil else {
            roomSheet = next
            return
        }
        nextRoomSheet = next
        roomSheet = nil
    }

    private func presentNextRoomSheet() {
        guard let next = nextRoomSheet else { return }
        nextRoomSheet = nil
        roomSheet = next
    }
```

They go last on purpose. `Scripts/lint/reentrancy.py` reads lines, not scopes: it pairs any
`guard x != nil` with an `x = …` up to 40 lines further down if a line between them contains
`await` (`reentrancy.py:25-52`). At the end of the file there is no `await` after the guard.

How the three hand-overs run with the one item:

- **H1.** *Invite someone* in the member list calls `replaceRoomSheet(with: .inviting(room))`. A
  sheet is up, so the next one is stored and `roomSheet` goes to nil. The member list closes,
  `onDismiss` runs `presentNextRoomSheet`, and the Start sheet appears.
- **H2.** `onIssue` calls `replaceRoomSheet(with: .invite(…))` and returns `true`. Same sequence.
  If the member swiped the Start sheet away while the invitation was being made, nothing is up and
  the guard presents the invitation directly, which is what happens today. If they had opened
  another sheet meanwhile, that one closes and the invitation follows.
- **H3.** The join prompt's `onOpen` leaves the offer, if there is one, in `nextRoomSheet`.
  `JoinPromptView` then dismisses itself as it does now, and `onDismiss` presents the offer.
  `.onChange(of: greeting)` and its `Task` are gone.

`presentNextRoomSheet` returns early when nothing was left, so an ordinary close does nothing.

### 4.4 `UI/Screens/Membership/InviteView.swift`

Lines 362-365, inside COPY chunk `3697f9bd` (lines 359-374; no words change, the marker is not
touched):

```swift
                        Task {
                            failed = !(await onIssue(code, lifetime))
                        }
```

That is, delete line 364, `if !failed { dismiss() }`. `dismiss` is still used by *Cancel* at line
391, so the `@Environment` property stays.

### 4.5 `App/CarpenterUITests/RigChecks.swift`

The suite has no step for H1 and no assertion for H2. Add both; they are the first tests of
sentence 2.

In `testTrigMakesARoomAndInvitesQuad`, after the `Create the invite` tap (line 453), before the
final `sleep(3)`:

```swift
        let issued = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Send the invite")).firstMatch
        XCTAssertTrue(issued.waitForExistence(timeout: 15), "the invitation did not follow the sheet that made it")
```

and after `shoot(app, "invite-3-issued")`:

```swift
        XCTAssertTrue(tapIfThere(app, "Done", timeout: 3))
        sleep(1)
        XCTAssertTrue(roomMenu(app, "Notifications"), "the room menu opens nothing after a hand-over")
```

A new step, next to `testTrigWaitingAndCompare`:

```swift
    func testTrigInvitesFromTheMemberList() throws {
        let app = launch()
        sleep(3)
        openChecks(app)
        XCTAssertTrue(roomMenu(app, "Who is in this room"))
        sleep(2)
        XCTAssertTrue(
            tapIfThere(app, "Invite someone", timeout: 3, scrolling: true), "the member list offers no invitation")
        XCTAssertTrue(
            entry(app, "Paste their code").waitForExistence(timeout: 5),
            "the invitation sheet did not follow the member list")
        shoot(app, "h-1-invite-after-members")
        XCTAssertTrue(tapIfThere(app, "Cancel", timeout: 3))
        sleep(1)
        XCTAssertTrue(roomMenu(app, "Who is in this room"), "the room menu opens nothing after a hand-over")
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 5), "the member list did not open again")
        shoot(app, "h-2-members-again")
    }
```

`roomMenu`, `entry`, `tapIfThere`, `openChecks` and `shoot` exist (`RigChecks.swift:519, 412, 37,
492, 29`). The labels are the app's (`RoomMembersView.swift:147`, `InviteView.swift:328, 73, 391`).
Add the new step's name to the list in `docs/simulator-rig.md:91-94`.

### 4.6 Docs, when the code is in and the rig steps pass

All three chunks are already `NEEDS HUMAN REVIEW`; leave the markers as they are.

- `docs/inbox.md:359-361`: "`RootView` presents fourteen sheets from its files" becomes four (the
  room sheet, the access review before leaving at `RootView.swift:573`, the Outpost consent at
  `RootView+Outpost.swift:26`, the Outpost access sheet at `RootView+Outpost.swift:134`). Keep the
  sentence about setting an item from a `Task` after a menu closed.
- `docs/style.md`, SwiftUI list (after line 132): one bullet. Suggested words: "A screen that owns
  several sheets holds one optional enum and one `.sheet(item:onDismiss:)`. When one sheet leads to
  another, the first is closed and `onDismiss` presents the second; the item is never changed
  straight from one sheet to another. A sheet that is replaced this way does not call `dismiss()`
  after an `await`." This is a default Claude proposes, not a ruling.
- `docs/pre-testflight.md:127-128`: item 9 is not done until Griff has watched section 7 on a
  phone. Until then it should say what is built and what is still to be watched. Other agents are
  editing this file in this run; leave the edit to whoever owns it.
- No entry in `docs/decisions.md`: the design follows the HIG's sheet guidance, so there is no
  departure to record.

---

## 5. What done looks like

- `grep -c "\.sheet(" Packages/Carpenter/Sources/CarpenterUI/Screens/RootView+Rooms.swift` prints 1.
- None of the eleven old property names is left in `UI/Screens/RootView*.swift`.
- The package builds and its suite passes; the app and both test targets build with no new
  warning; `./Scripts/lint-branding.sh` passes.
- On the rig: `testTrigMakesARoomAndInvitesQuad` (with its new assertions),
  `testTrigInvitesFromTheMemberList`, `testOfferShown`, `testTrigWaitingAndCompare`,
  `testRecordsMembers`, `testARoomsMenuAndSheetsSaySomethingForEveryStop` and
  `testARoomsOwnSheetsPassApplesAudit` pass.
- Griff has watched section 7 on an iPhone. Until then the word is "not verified".

---

## 6. Tests to run

Wait until the build folders and the simulators are free.

```bash
cd Packages/Carpenter && swift build
cd Packages/Carpenter && swift test
./Scripts/lint-branding.sh
python3 Scripts/lint/reentrancy.py
xcodebuild -workspace Carpenter.xcworkspace -scheme Carpenter \
  -destination 'platform=iOS Simulator,id=5A43F953-128D-4FE6-9135-0D26520E02B6' \
  -derivedDataPath /tmp/carpenter-dd build
```

Remove `/tmp/carpenter-dd` before that build and read its warnings: members moved between files of
one type is where a name has bound to the wrong thing before (CLAUDE.md, the `sync()` trap).

No package test can see a sheet. The proof is the UI steps, on a fresh install on every simulator
(CLAUDE.md, "never leave a stale build on a sim"), software keyboard on (the Start sheet has a
field), one step per run:

```bash
TEST_RUNNER_OUTPOST_RIG=1 xcodebuild test -workspace Carpenter.xcworkspace -scheme Carpenter \
  -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath /tmp/carpenter-dd \
  -only-testing:CarpenterUITests/RigChecks/<step> -parallel-testing-enabled NO
```

UI tests that open these sheets today (`App/CarpenterUITests`):

| Test | Line | Sheets |
|---|---|---|
| `RigChecks.testTrigMakesARoomAndInvitesQuad` | `RigChecks.swift:423` | 4, then 8 through H2; no assertion on 8 before this change |
| `RigChecks.openChecks` (helper for most later steps) | `:492-504` | taps *Open <room>* (1) and *Not now* (2), neither asserted |
| `RigChecks.testOfferShown` | `:276` | 1, then asserts 2 is or is not shown (`RIG_EXPECT_OFFER`): H3 |
| `RigChecks.testTrigWaitingAndCompare` | `:584` | 5, closed, then 6 |
| `RigChecks.testQuadCompare` | `:602` | 6 |
| `RigChecks.remove(_:in:)`, used by `testTrigRemovesQuad` `:638` and `testRemoves` `:664` | `:646` | 3. Whether its long-press step still matches the member list: not verified |
| `RigChecks.testRecordsMembers` | `:688` | 3 |
| `RigChecks.testTrigFourDaysLater` | `:623` | the not-sent explanation only; it stops before 5 or 9 |
| `VoiceOverWalkTests.testARoomsMenuAndSheetsSaySomethingForEveryStop` | `VoiceOverWalkTests.swift:166` | 5, closed, then 6 |
| `AccessibilityAuditTests.testARoomsOwnSheetsPassApplesAudit` | `VoiceOverWalkTests.swift:256` | 5, closed, then 9 |

Not opened by any UI test (grep for the menu labels): 7 *Show the invite*, 10 *Who gets in*, 11
*Review … waiting to join*, and H1 until 4.5 adds it.

`UXFindingsTests.testLettingSomebodyInIsNeverInALongPressMenu` and `testRemovingSomebodyIsOnTheirPage`
(`UXFindingsTests.swift:26, 44`) open the member list through the DEBUG copy shot
(`UI/Screens/SiteShots/ScreenShots.swift:10-26`), not through the rooms view. They neither cover
this change nor are affected by it. Whether `ScreenCatalogueTests` reaches the room menu's sheets:
not verified.

---

## 7. To watch on a device

On the rig first, then on an iPhone (the plan asks for a device; only Griff has one).

1. H1: room menu, *Who is in this room*, *Invite someone*. The member list closes, then the Start
   sheet appears, once. *Cancel*. Open the member list again from the menu.
2. H2: room menu, *Invite someone*, paste a code, *Create the invite* with the software keyboard up.
   The Start sheet closes, then the invitation appears with its characters, once. *Done*. Open any
   other room sheet from the menu.
3. H3: join a room and open it. *Open <room>*, then the compare-codes offer appears, once. *Not
   now*. Leave the room and open it again: no prompt, no offer.
4. The not-sent mark: tap it, choose the waiting list, then the other choice. Each opens after the
   explanation closes.
5. Each of the other sheets from the menu, one after another, closed by its button and by a swipe.
6. All of 1 and 2 again with the split inbox on, after visiting both the Solos and the Rooms tab.
   In that layout two navigation stacks hold the same room (`RootView+Phone.swift:39, 85`, both on
   `roomPath`), so two copies of the modifier share the binding. That is true today of all eleven.
   Look for a sheet that opens twice or closes itself.
7. One sheet in light and one in dark appearance.

If in 1, 2 or 3 the second sheet never appears, `onDismiss` did not run or its assignment was not
honoured. Stop and report which step; do not add a delay.

---

## 8. Risks

- Presenting again from the same modifier inside its own `onDismiss` is inferred to work. The two
  places this repository already uses `onDismiss` for a hand-over present from a different modifier.
- Changing the item straight from one value to another can still happen in one corner: a room that
  has its own greeting is opened by a link or a notification while a sheet from another room is up
  (`.task(id:)` assigns `.greeting`). The old sheet's view is being torn down at that moment. Not
  exercised.
- A sheet's state outlives a change of room made from outside (a notification tap, a link) while
  the sheet is up, today and after this change: the new room's view presents whatever is still in
  the state. Inferred from the code, not verified. Not fixed here; see section 10.
- If a hand-over is started and the room's view is destroyed during the close animation, `onDismiss`
  may not run and `nextRoomSheet` would be presented after the next sheet closes. Inferred, not
  exercised.
- An invitation finishing while another room's join prompt is up closes that prompt without *Open*.
  The prompt returns the next time that room is opened, because `onGreetingSeen` was not called.
- "Offered" is recorded when the offer sheet's content appears (`.task`), not when the state is
  set. `markComparisonOffered` sets the same stamp either way
  (`CarpenterApp/Session/AppSession+Verifying.swift:51-58`).
- `StartInviteView` no longer closes itself on success. A second caller would have to replace it,
  as the rooms view does.
- `roomSheetView` is a long `switch` in a `ViewBuilder`; see the note under 4.3 if the compiler
  objects.

---

## 9. The same sheets built a second way

In `App/Carpenter`: none of the eleven views is constructed there (grep). `AppRootView` presents its
own sheets above `RootView` (`App/Carpenter/AppRootView.swift:217, 237, 286, 297, 334, 342, 480, 506,
515`); this step does not touch them.

In `CarpenterUI`:

- **`InviteView` from a `PresentedInvite`, three times**, the same four lines:
  `RootView+Rooms.swift:197-204`, `UI/Screens/Rooms/RoomsListView+Content.swift:148-153`,
  `UI/Screens/Membership/AddSomeoneView.swift:96-100` (which leaves `notAskedYet` to its default).
  A fourth builds it from an `Invite`: `InviteView.swift:182-184`.
- **"Make an invitation, then show it", three times**: H2 here; the Solo picker
  (`RoomsListView+Content.swift:140-153`, where the picker dismisses itself before the work starts,
  `UI/Screens/Membership/SoloPickerView.swift:39-41`); and `AddSomeoneView.swift:131-138`, which
  presents the invitation (`:96`) as a sheet on top of its own sheet (`AppRootView.swift:515`).
  `docs/inbox.md:368` notes a different nested sheet in the same view, the new-room one.
- **The room's name looked up nine times** in the eleven closures
  (`RootView+Rooms.swift:143, 165, 171, 180, 187, 194, 213, 223, 232`); eight end in `?? ""`, the
  notifications one passes the optional.
- **DEBUG fixtures** build four of the views with fixed data and their own `NavigationStack`:
  `SiteShots/ScreenShots.swift:10-26` (`RoomMembersView`, without `.presentingReportedProblems()`
  or the leaving environment), `:36-37` (`JoinRequestsView`), `:75-78` (`InviteView`),
  `SiteShots/SiteShotView.swift:78-95` (`WhoYouAreTalkingToView`). Both files are wrapped whole in
  `#if DEBUG`.
- **Previews**: `JoinPromptView.swift:134`, `WaitingOnView.swift:93`, `WhoYouAreTalkingToView.swift:211`,
  `RoomMembersView.swift:518`, `RoomAccessView.swift:175`, `JoinRequestsView.swift:102, 119`,
  `InviteView.swift:400, 405`.

Two follow-ups, each its own commit after 4.1-4.5, if Griff wants them in this step:

- F1. In `RootTypes.swift`:
  ```swift
  extension InviteView {
      init?(_ presented: PresentedInvite, phrase: String?) {
          self.init(
              roomName: presented.roomName, invite: presented.invite, phrase: phrase,
              notAskedYet: presented.notAskedYet)
      }
  }
  ```
  and the three call sites become `InviteView(presented, phrase: phraseLookup(presented.invite))`.
- F2. `private func name(of room: RoomID) -> String? { rooms.first { $0.id == room }?.name }` in
  `RootView+Rooms.swift`; eight sites become `name(of: room) ?? ""`, the notifications site
  `name(of: room)`.

The fixtures and previews stay as they are.

---

## 10. Only Griff can decide or supply

1. Confirm the three sentences in section 2.
2. Watch section 7 on an iPhone. The rig can run the UI steps; the plan asks for a device.
3. Yes or no to two small changes in behaviour that come with this design: "offered" is recorded
   when the compare-codes offer is on screen rather than when it is queued; and the Start sheet is
   closed by the rooms view on success rather than by itself. Recommendation: yes to both.
4. Whether F1 and F2 (section 9) are done now as their own commits or parked in `docs/inbox.md`.
   Recommendation: F1 now, F2 now; both are small and provable by build.
5. A sheet about one room can stay up over another when a link or notification changes the room
   under it (section 8, inferred). Fix it now by clearing both states when `openRoom` changes, in
   its own commit after the device check, or park it. Recommendation: fix it after step 9 is
   watched, so the two are not confused on the device.
6. Whether the pattern goes into `docs/style.md` (4.6). It would be a `PROPOSED` default.

---

## 11. Noticed, not part of this step

- `InviteView` declares `@Environment(\.verificationPhrase) private var phraseLookup`
  (`InviteView.swift:10`) and, by grep, never reads it; its callers pass `phrase:`.
- `NotificationLevelView` is constructed once, always for a room (`RootView+Rooms.swift:207`), so
  its `room == nil` header (`UI/Screens/Notifications/NotificationLevelView.swift:27-35`) shows only
  if the room is missing from `rooms`. It also has no close button; it closes by swipe.
- H1 today sets one binding to nil and another to a value in the same closure. A report of that
  exact swap losing later dismissal callbacks exists
  (https://gist.github.com/mbrandonw/f8b94957031160336cac6898a919cbb7, FB11975674, OS version not
  stated). Not verified here; this step removes the swap.

<!-- COPY END f55410ad -->
