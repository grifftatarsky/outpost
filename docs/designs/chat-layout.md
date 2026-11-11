<!-- COPY BEGIN 7c2c60e0 [NEEDS HUMAN REVIEW] -->

# The list of conversations, the conversation screen, new message, default avatars and notifications: a spec to draw from

> **A working design, written by agents on 2026-11-10 and 2026-11-11 and kept so the work need not be
> done again.** Nothing in it is a ruling. Where it names a file under `scratchpad/`, that was a
> working file and was not kept. Line numbers are from the commit it names and will drift.
> What is waiting on Griff is in [the Part B plan](../part-b-plan.md).

Written 2026-11-10 from branch `overnight-2026-10-31`. Nothing was built, run or seen on a device.
This file is for the person drawing the artboards. Section 9 lists the boards.

## 0. How to read this

### 0.1 Labels

- A code fact carries `file:line`. Paths starting `UI/` are under
  `/Users/grifftatarsky/projects/outpost/Packages/Carpenter/Sources/CarpenterUI/`, `KIT/` under
  `.../Sources/CarpenterKit/`, `APP/` under `.../Sources/CarpenterApp/`, and `ROOT/` is
  `/Users/grifftatarsky/projects/outpost/`.
- **computed** = arithmetic from numbers in the source, not measured on a device.
- **inferred** = reasoned, not checked.
- **not verified** = could not be checked here.
- **proposal** = new in this spec. Any proposed wording a member would read needs a copy marker at
  `NEEDS HUMAN REVIEW` before it ships.
- A web fact carries the URL it was read at. `[me]` means read for this spec today. `[hig]`,
  `[pat]`, `[ntf]` mean it was read by the research file named below, and I did not re-read it:
  - `[hig]` `…/scratchpad/design/ui-research-hig.md`
  - `[pat]` `…/scratchpad/design/ui-research-patterns.md`
  - `[ntf]` `…/scratchpad/design/ui-research-notifications.md`
  - `[code]` `…/scratchpad/design/ui-research-code.md` (code facts I re-read are cited directly)

### 0.2 The artboard

- iPhone, portrait, 402 x 874 pt. The project names a "402pt phone" and a "440pt phone"
  (`ROOT/CLAUDE.md`, the HIG rule). The 874 height is from memory, not verified; take the device
  frame from Apple's iOS 27 design kit.
- **Side margin: draw 16 pt on the 402 pt board and 20 pt on a 440 pt board.** Apple documents only
  that iPhone system margins "range from 16 to 20 points" and says to read the margin guide rather
  than write the number
  (https://developer.apple.com/tutorials/data/documentation/swiftui/contentmarginguide/container.json
  `[hig]`). Which phone gets which number is not verified. In code the row must take the list's own
  margin, not a constant.
- Draw every list and conversation board in light. Draw the recommended ones in dark as well.

### 0.3 What the system draws

Take these from Apple's kit and do not redraw them: status bar, navigation bar and its glass
buttons, the large title, the floating glass tab bar and its separated search button, sheets and
their grabbers, menus and context menus, swipe-action buttons, the keyboard, banners, the Lock
Screen and Notification Center. This spec gives measurements only for what the app draws inside
them.

Rules that bind every board (`[hig]` section 5, inferred from the HIG pages listed there):

- No Liquid Glass on rows, bubbles, avatars or pinned tiles. Glass is for bars, the composer,
  sheets and menus.
- A banner never shows a face. A sender's picture needs a Siri donation, which is ruled out
  (`ROOT/docs/decisions.md:3412`, RULED 2026-09-27).
- On the list, the accent colour appears on the unread mark and nowhere else. Toolbar buttons are
  plain glass.

### 0.4 Colours

All from `UI/Theme/Palette.swift` and `KIT/Theme/Accent.swift`. The default accent is Verdigris
(`Accent.swift:28`). Blended values are computed.

| Token | Light | Dark | Source |
|---|---|---|---|
| Page | `#F2F2F7` | `#12141A` | `Palette.swift:188` |
| Primary text | `#000000` | `#FFFFFF` | `Palette.swift:205` |
| Secondary text (preview) | `#3C3C43` at 85% (`#57575E` on the page) | `#EBEBF5` at 75% (`#B5B5BE`) | `Palette.swift:208,219-223` |
| Time | `#3C3C43` at 92% (`#4B4B51`) | `#EBEBF5` at 75% | `Palette.swift:214` |
| Tertiary (marks) | `#626269` on the page | `#9999A2` | `Palette.swift:211` |
| Quaternary (date lines) | `#6B6B72` | `#83848C` | `Palette.swift:217` |
| Separator | `#BDBDC3` on the page | `#333439` | `Palette.swift:228-232` |
| Accent | `#14766C` | `#34A79B` | `Accent.swift:58,71` |
| Accent fill (unread mark, my bubble) | `#14766C`, white reads 5.47:1 | `#277D74`, white reads 4.92:1 | `Palette.swift:69-85` |
| Incoming bubble | accent at 13% = `#D5E2E5`, black text | accent at 22% = `#193436`, white text | `Accent.swift:52-53`, `Palette.swift:55-56` |

### 0.5 Type

System text styles only. Sizes are point size / leading.

| Style | Default (Large) | Largest (AX5) |
|---|---|---|
| Large Title | 34 / 41 | 60 / 70 |
| Headline (semibold) | 17 / 22 | 53 / 62 |
| Body | 17 / 22 | 53 / 62 |
| Subhead | 15 / 20 | 49 / 58 |
| Footnote | 13 / 18 | 44 / 52 |
| Caption 1 | 12 / 16 | 43 / 51 |
| Caption 2 | 11 / 13 | 40 / 48 |

Default column: https://developer.apple.com/tutorials/data/design/human-interface-guidelines/typography.json
`[hig]`. AX5 column: the same page, read from character 30,000 `[me]`.

### 0.6 Words

A Solo is a conversation between two people. A room is a group. An Outpost is a member's own feed.
In anything a member reads: request, shown, received, saved history, message. The delivery label is
"Received". The product name comes from `Config/Branding.xcconfig`; draw it as "Outpost" where the
system shows the app's name.

---

## 1. What is wrong today

Every number here is computed from the source. None was measured on a device.

### 1.1 The row as built

One view draws every row (`UI/Screens/Rooms/RoomRow.swift`). The list gives it a leading inset of 0
(`UI/Screens/Rooms/RoomsListView+Content.swift:60-66`, `UI/Theme/Metrics.swift:6`).

| | Comfortable (default) | Compact |
|---|---|---|
| Unread column | x 0 to 20. A 10 pt accent dot at x 5 to 15, drawn at opacity 0 when read (`RoomRow.swift:26-32`, `Metrics.swift:5`) | same |
| Avatar frame | x 20 to 68, 48 pt (`Metrics.swift:49`) | x 20 to 79.2: a frame 1.48 times the 40 pt disc, disc aligned to its right (`RoomRow.swift:47-50`, `UI/Components/Messaging/RoomRowViews.swift:61-65`) |
| Left edge of a Solo's disc | 20 | 39.2 |
| Gap | 12 (`RoomRow.swift:51`) | 12 |
| Text and separator start | x 80 (`RoomRow.swift:102`) | x 91.2 |
| Row padding | 8 above, 8 below (`Metrics.swift:7`) | same |
| Lines | name (Headline) and time (Subhead), then two reserved preview lines (Subhead) (`RoomRow.swift:61-99`, `UI/Theme/Typography.swift:7-9`) | name and time only (`RoomRow.swift:89`) |
| Row height | 8 + 22 + 2 + 40 + 8 = 80 | 8 + 40 + 8 = 56 |
| Trailing | 20 pt inset plus the system's chevron (`RoomsListView+Content.swift:57-66`) | same |
| Unread | a dot, yes or no; no count (`KIT/Model/ReadModel.swift:127`) | same |

### 1.2 Where the space left of the picture comes from

| # | Cause | Size | Where |
|---|---|---|---|
| 1 | The unread column is kept on every row and is empty when the row is read | 20 pt | `RoomRow.swift:26-32` |
| 2 | Compact reserves room for three overlapping faces on every row. A Solo, or a room with one speaker, uses one | 19.2 pt more, so 39.2 pt in all | `RoomRow.swift:47-50`, `RoomRowViews.swift:63-65,98-106` |
| 3 | A person with no picture is a disc of `#787880` at 8% on the page: `#E8E8ED` on `#F2F2F7`, a contrast of 1.09:1. The disc has no visible edge, so the initials read as the picture, and they start about 12 pt inside it | the picture appears to start near x 32 (inferred) | `Palette.swift:256-259`, `UI/Components/Shared/AvatarView.swift:54-62` |
| 4 | A room is a 48 pt frosted disc holding smaller faces. The left-most face starts inside it | x 27.2 with one speaker, 24.8 with two, 25.8 with three | `RoomRowViews.swift:108-130` |
| 5 | So one list has four different left edges: 20 (a picture), about 25 to 27 (a room), about 32 (initials), 39.2 (Compact) | a ragged edge | causes 1 to 4 |
| 6 | The margin is a constant 20, the top of Apple's 16 to 20 range | 4 pt on most phones (inferred) | `Metrics.swift:5` |

Which density Griff was looking at is not known. Comfortable is the default
(`UI/Theme/RoomsListPreferences.swift:56-63`), where causes 1, 3, 4 and 6 apply.

The Messages measurement this row was built against, 45 pt avatar and an 8 pt gutter holding the
dot, is in a RULED entry (`ROOT/docs/decisions.md:5206-5216`, 2026-09-13). The 20 pt grid came later,
inside another RULED entry about room avatars (`decisions.md:5043-5045`, 2026-09-28); that entry does
not say whether Griff ruled on the grid itself.

Of five messengers studied, Messages is the only one that spends leading width on the unread mark.
Signal and Threema put a 56 pt avatar at the layout margin; Telegram puts a 60 pt avatar 16 pt from
the edge (`[pat]`, from each app's public iOS source; Apple and WhatsApp publish no numbers).

### 1.3 The same fault in a conversation

Incoming bubbles start at x 50: 14 pt page padding, a 28 pt avatar, 8 pt gap
(`UI/Screens/Messaging/ConversationView+Transcript.swift:47`,
`UI/Components/Messaging/MessageBubbleView.swift:176-190`, `Metrics.swift:52`). The avatar is drawn
beside every incoming run in a Solo as well (`MessageBubbleView.swift:178`), where it is always the
same person and the name is already in the bar.

### 1.4 Other things the options below fix or leave

| Today | Where |
|---|---|
| No swipe actions on the list | grep of `UI/Screens/Rooms/`; only the Edit list sheet has them |
| No unread count, no Mark as Unread | `ReadModel.swift:127`; `UI/Screens/Rooms/RoomsListView+Actions.swift:23-33` |
| Pinned and silenced are discs on the avatar's corners | `RoomRowViews.swift:71-82` |
| A room nobody else has spoken in shows initials on the grey disc, the same drawing as a person | `RoomRowViews.swift:89-90` |
| Compose is on the leading side; in the combined list it is a menu of two | `RoomsListView+Content.swift:111`, `RoomsListView+Actions.swift:138-160` |
| Starting a Solo or a room does not open it | `ROOT/App/Carpenter/AppRootView.swift:542-575` |
| One date line in a whole conversation | `ConversationView+Transcript.swift:13-16` |
| The list's own search can never run | `[code]` section 8 |

---

## 2. The list of conversations: six options

### 2.0 Parts the options share

#### The screen

| Element | Drawn by | Notes |
|---|---|---|
| Tab bar | `TabView` with `Tab` (`UI/Screens/RootView+Phone.swift:37`). System glass, floating | Search is `Tab(role: .search)`; the system separates it at the trailing end (`[hig]` 2) |
| Navigation bar | `NavigationStack`, `.toolbar` | Buttons are system glass |
| Compose | `Button` in `ToolbarItem(placement: .primaryAction)`, symbol `square.and.pencil` (the HIG's standard Compose symbol, `[hig]` 3.18). Plain glass, not tinted | Trailing, because the HIG puts important actions trailing and navigation leading (`[hig]` 3.4). Never a tab: "Use a tab bar to support navigation, not to provide actions" (https://developer.apple.com/tutorials/data/design/human-interface-guidelines/tab-bars.json `[hig]`) |
| More | `Menu` with `ellipsis`, trailing, left of compose, split from it with `ToolbarSpacer(.fixed)` so each has its own glass | Holds what it holds today: Row size, Join with an invite, Edit list, Manage tags (`RoomsListView+Actions.swift:169-210`) |
| The line saying when the list last caught up | Today a hand-placed row (`UI/Components/Messaging/SyncStatusRow.swift:9-27`). Proposal: `navigationSubtitle(_:)`, iOS 26 (`[hig]` 2) | How iOS draws a subtitle under a large title is not verified. Draw it as one Footnote line in quaternary under the title, starting at the margin. Sample: "Caught up with Maren and Dev a moment ago." (`KIT/Presentation/HonestCopy.swift:23`) |
| List | `List`, `.listStyle(.plain)`, `.refreshable` | As today (`RoomsListView+Content.swift:12,84`) |
| Scroll edge | automatic, not the forced `.soft` of today (`RoomsListView+Content.swift:86`) | The HIG has preferred automatic since June 2026 (`[hig]` 3.11) |
| Row | `NavigationLink(value:)` with `.navigationLinkIndicatorVisibility(.hidden)` | The modifier exists from iOS 17 (https://developer.apple.com/tutorials/data/documentation/swiftui/view/navigationlinkindicatorvisibility(_:).json `[me]`). Option F keeps the chevron |
| Empty list | `ContentUnavailableView`, unchanged (`RoomsListView+Content.swift:199-247`) | Not redrawn |

#### The regular row, called R (options A, B, C, D)

Drawn at 402 pt with a 16 pt margin.

```
x   0      16            68    80                                      386   402
    |margin|   avatar    | gap |            text column, 306           |margin|
y   0  ──────────────────────────────────────────────────────────────────────
    10 ┌ name (Headline)  marks                              time (Footnote) ┐ 22
    34 │ preview line 1 (Subhead, secondary)                     [unread]    │ 20
    54 └ preview line 2                                                      ┘ 20
    84 ──────────── separator from x 80 to the screen edge ──────────────────
```

| Measure | Value | Drawn by |
|---|---|---|
| Leading and trailing inset | the list's margin; 16 drawn | `List` default. Do not set a leading inset or pad the row |
| Avatar | 52 pt circle, x 16 to 68, centred vertically (y 16 to 68) | `AvatarView` / `RoomAvatar`, section 3. 52 is the size the Outposts rail already uses (`UI/Screens/Outpost/OutpostFeedView.swift:258`) |
| Avatar to text | 12 | `HStack` spacing, as today |
| Text column | x 80 to 386, 306 wide (x 84 to 420, 336 wide at 440) | `VStack(alignment: .leading, spacing: 2)` |
| Above and below | 10 and 10 | `listRowInsets` top and bottom |
| Line 1 | name: Headline, primary, one line, truncates. Time: Footnote, the time colour, never truncates, 8 pt minimum gap, baselines aligned | `Text`. Time words as today: a clock time today, "Yesterday", a weekday, then a numeric date (`KIT/Presentation/RelativeTimestampFormatter.swift:13-20`) |
| Lines 2 and 3 | preview: Subhead, secondary, two lines always reserved | `Text` with `lineLimit(2, reservesSpace: true)`, as today (`RoomRow.swift:95-97`). "No messages yet" when empty |
| Row height | 10 + 22 + 2 + 40 + 10 = **84** | |
| Separator | system hairline from x 80 to the screen's trailing edge; hidden above the first row | `alignmentGuide(.listRowSeparatorLeading)`, as today (`RoomRow.swift:102-104`) |
| Chevron | none | see the screen table |
| Marks | silenced `moon.fill`, pinned `pin.fill`, invited-not-yet-in `person.crop.circle.badge.clock`: Caption 2, 5 pt apart, 6 pt after the name, in tertiary | `RoomMarks`, which exists for the pictures-off row (`RoomRowViews.swift:355-388`). It draws them in the accent today; tertiary is the change, so the accent means unread and nothing else |

#### The unread mark, three ways

| | U1: count at the trailing end | U2: dot inside the margin | U3: count on the avatar |
|---|---|---|---|
| Looks like | A capsule on the first preview line, right edge at x 386, top at y 34. 20 pt high, 20 pt minimum width, 6 pt side padding. Caption 1 semibold, white, digits monospaced, "99+" past 99. Fill: accent fill. The preview stops 8 pt short of it | An 8 pt accent dot centred at x 8, centred vertically. The avatar stays at x 16 | The U1 capsule centred on the avatar's edge at its top trailing corner, with a 2 pt ring in the page colour |
| Takes leading width | none | none beyond the margin | none |
| Until a count exists | a 10 pt accent dot in the same place (call it U1 dot) | | |
| Second signal, so colour is not the only one | the preview turns primary colour on an unread row; VoiceOver says "3 unread" | VoiceOver "Unread", as today (`RoomRow.swift:30`) | same as U1 |
| Silenced and unread | the capsule is grey (`palette.badgeFill`, `Palette.swift:269-270`) with secondary text. Telegram does this (`[pat]`, source) | the dot stays accent | grey |
| Used by | Signal, Telegram (`[pat]`, source); WhatsApp (general knowledge, not verified) | Messages, with a wider gutter (`[pat]`) | Threema (`[pat]`, source) |
| Drawn by | by hand: `Text` on a `Capsule`. Reason: the system row badge (`.badge(_:)`) sits at the row's trailing centre and cannot sit on the preview line; Apple's page does not say how it is drawn at each prominence (https://developer.apple.com/tutorials/data/documentation/swiftui/badgeprominence.json `[me]`) | by hand: `Circle`, as today | by hand |
| Costs | A count needs the read model to carry a number. `RoomSummary.hasUnread` is a yes or no (`ReadModel.swift:127`); the count is the same walk, counted instead of stopped at the first hit (`KIT/Log/Projection+Standing.swift:361-376`), and its cost has to be held by `ProjectionCostTests` | Nothing new | Covers part of a face; the supporter badge already sits on avatars (`AvatarView.swift:130`) |

U3 is listed for completeness and is not used by any option below.

#### Swipe actions (all options)

Drawn by the system: `swipeActions(edge:allowsFullSwipe:)`. Apple's own sample is a message list
with Read or Unread on the leading edge
(https://developer.apple.com/tutorials/data/documentation/swiftui/view/swipeactions(edge:allowsfullswipe:content:).json `[me]`).

| Edge | Actions, from the edge inward | Full swipe | Symbols | Tint |
|---|---|---|---|---|
| Leading | Read or Unread, then Pin or Unpin | performs Read or Unread | Read `checkmark.circle` (in the build, `RoomsListView+Actions.swift:30`); Unread `message.badge` (not checked against the symbol catalogue; `SymbolNameTests` decides); `pin` / `pin.slash` (in the build, `:17`) | Read or Unread: accent fill. Pin: grey |
| Trailing | Silence or Unsilence | off (`allowsFullSwipe: false`) | `moon` / `bell` (in the build, `:44`) | grey |

- Leave and Delete stay in the touch-and-hold menu, not on a swipe. A destructive swipe was tried
  twice on person rows and abandoned because the row slid out of view under the verb
  (`ROOT/docs/inbox.md:77-81`).
- The touch-and-hold menu opens with the same three actions, in one row at its top: Pin, Read or
  Unread, Silence. The HIG: "Match top menu actions to swipe actions"
  (https://developer.apple.com/tutorials/data/documentation/technologyoverviews/adopting-liquid-glass.json `[hig]`).
  The SwiftUI spelling for that row is a `ControlGroup` inside the menu; which style gives the
  labelled row of three is not verified (pages read `[me]`:
  `…/swiftui/controlgroupstyle/compactmenu.json`, `…/swiftui/controlgroupstyle/palette.json`). Below
  it, as today: Tags, Show only invited, Do Not Disturb message, then Leave or Delete in red
  (`RoomsListView+Actions.swift:49-125`). The preview of the last six messages stays
  (`RoomsListView+Content.swift:76-81`).
- **Cost.** Mark as Unread does not exist. The read mark only moves forward
  (`APP/Session/AppSession+Messaging.swift:560-575`), so Unread needs a new stored yes or no per
  conversation, and a new stored field has to be added to the hand-written decoder
  (`ROOT/CLAUDE.md`, the `PersistedState` trap). Until then the leading swipe offers Read only, on
  unread rows, and Pin.
- Archive is not offered. Nothing in the build archives or hides a conversation (`[code]` section 5).

#### How it should feel

| Moment | What happens | Drawn by |
|---|---|---|
| Tap a row | system highlight, then a push | `NavigationLink` |
| A message arrives | the row moves to the top with the list's own animation; the unread count changes with a number roll. With Reduce Motion: a cross-fade | `List` animation; `contentTransition(.numericText())` |
| Pin or unpin | the row moves; one selection tick | `sensoryFeedback(.selection, trigger:)` |
| Compose | the sheet grows out of the compose button | `matchedTransitionSource(id:in:)` on the button (iOS 18, https://developer.apple.com/tutorials/data/documentation/swiftui/view/matchedtransitionsource(id:in:).json `[me]`) with a zoom transition on the sheet. That a sheet can zoom out of its toolbar button is from WWDC25 session 323 `[hig]` |
| Send | the existing light impact and the bubble's arrival | `.haptic(.commit, trigger: sent)` (`UI/Screens/Messaging/ConversationView.swift:211`) |
| Pull down | system refresh | `.refreshable`, as today |

---

### Option A. One list

Solos and rooms together, newest first, with no filter control taking space on the screen. One
mixed list is what all five messengers studied use; Threema has no filter at all (`[pat]`).

| | |
|---|---|
| Tabs | Messages (`bubble.left.and.bubble.right`), Outposts (`rectangle.stack`), You; search button at the trailing end. The Messages badge is the number of conversations with something unread, as today (`UI/Screens/RootView.swift:51-53` `[code]`) |
| Title | Large title "Messages", which shrinks on scroll. The HIG asks for a large title on iOS to keep people oriented (`[hig]` 3.4). Its left edge is at the margin, in line with the avatars |
| Bar | trailing: More, compose. Leading: nothing |
| Row | R: margin 16, avatar 52, gap 12, text at x 80, row 84, separator from x 80 |
| Unread | U1 |
| Pinned | ordinary rows, first, in the order the member dragged (`KIT/Model/RoomOrganisation.swift:150-175`), each with `pin.fill` after the name. No header |
| Filters | Tags are a section of the More menu. The build can already show the tag filter as one menu in place of the pills (`UI/Screens/Rooms/TagScreens.swift:179-190` `[code]`, `RoomRowViews.swift:258`); this moves that menu into the bar |
| Swipe | the shared set |
| Rows on screen | about 7 (estimate: 158 pt of bar and large title, 96 pt of tab bar and home indicator, both assumed and not verified) |

**At the largest text size (AX5).** From AX3 up the avatar leaves the row and the text starts at
the margin; a room shows `person.2.fill` before its time so it can still be told from a Solo.

```
x 16                                                    386
  Name, Headline 53/62, up to two lines
  time, Footnote 44/52 · marks · unread capsule
  preview, Subhead 49/58, two lines
```

Heights: 12 + 62 or 124 + 4 + 52 + 4 + 116 + 12 = 262 with a one-line name, 324 with two. The
separator runs from the margin. At AX1 and AX2 the default layout stays and the time drops under
the name, as today (`RoomRow.swift:55-59`). Avatars keep their size at every text size, which is
the recorded default (`decisions.md:5470-5489`, PROPOSED).

**Costs.**

- Replaces the RULED row of 2026-09-13 (leading dot, chevron) and the grid in the RULED entry of
  2026-09-28. Both entries need Griff's yes and an update.
- The default changes from two tabs to one list (`RoomsListPreferences.swift:60-62`). No entry in
  `decisions.md` records who chose the split default (grep for "inbox", 2026-11-10).
- The unread count and Mark as Unread, as costed above.
- A member with many rooms and few Solos has no way to see only one kind without opening the menu.

### Option B. One list with a filter in view

Option A plus a control that narrows the list. The row is identical to A.

| | |
|---|---|
| Tabs | as A |
| Title | Inline "Messages", because the filter takes the height a large title would |
| Filter | A segmented `Picker`: **All, Solos, Rooms**. `.pickerStyle(.segmented)`; on iOS 27 `.pickerStyle(.tabs)`, which looks the same and reads to VoiceOver as tabs (`[hig]` 2; needs an availability check because the target is iOS 26.5). It sits in `safeAreaBar(edge: .top)`, which keeps the scroll edge effect behind it (iOS 26, https://developer.apple.com/tutorials/data/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:).json `[me]`) |
| Filter measures | margins 16; 8 above, 8 below; the control itself at the system's height (32 pt from memory, not verified), so a 48 pt band |
| Second filter | A `Menu` button at the bar's leading side, symbol `line.3.horizontal.decrease` (the HIG's standard Filter symbol, `[hig]` 3.18): Unread, then the member's tags, then Manage tags. The button is filled while any filter is on, as Messages does (`[pat]`) |
| Row, unread, pinned, swipe | as A |
| Rows on screen | about 7 (estimate, same assumptions) |
| AX5 | The segmented control is drawn by the system and does not grow; iOS offers the Large Content Viewer on it (inferred from `decisions.md:5486-5487`). Rows as A |

Variant B2, chips: replace the segmented control with the existing pill rail
(`RoomRowViews.swift:144-240`): All, Unread, Solos, Rooms, Invited, then tags. Pills are 30 pt high,
8 pt apart, 6 pt above and below, a 42 pt band, first pill at the margin. Drawn by hand, as today;
the reason is that more than about five choices do not fit a segmented control (`[hig]` 3.6). This is
WhatsApp's pattern (`[pat]`).

**Costs.** Everything in A, plus 48 pt of height given to a choice most people make rarely; a
second place (the menu) for Unread and tags; and the HIG reads a segmented control as switching
"closely related subviews", which means deciding that Solos and rooms are one section
(`[hig]` 3.6).

### Option C. Two tabs

Solos and rooms apart. This is today's default arrangement with the row corrected.

| | |
|---|---|
| Tabs | Solos (`bubble.left`), Rooms (`bubble.left.and.bubble.right`), Outposts, You; search button. Each of the first two carries its own unread badge, as today (`RootView+Phone.swift:81,124`) |
| Title | Large title "Solos" or "Rooms" |
| Bar | trailing: More, compose. On Solos, compose opens the people list; on Rooms, New room (section 4) |
| Row | R on both tabs |
| Unread | U1 |
| Pinned | first on each tab, with the glyph |
| Rooms tab, variant C2 | the preview starts with who spoke: "Tobias: Who has the long hose?", the name in primary colour, same line. `RoomSummary.lastAuthor` already exists (`ReadModel.swift:124`). **This reverses a ruling**: the sender was ruled out of the preview on 2026-09-13 because drawing it as a pill made a third line (`decisions.md:5206-5216`). Inline, it adds no line. Draw the Rooms tab both ways |
| Swipe | the shared set |
| AX5 | as A |

**Costs.**

- Two places to look, and an unread mark split over two badges. All five messengers studied keep
  one list and treat kinds as a filter (`[pat]`).
- Four tabs plus search.
- The Rooms tab exists only in this arrangement. Under the iOS 27 SDK a `TabView` "might crash when
  its selection is set to a hidden or otherwise unavailable tab" (iOS 27 release notes `[hig]` 2), so
  the selection must be moved before the tab goes.
- The list is constructed twice with two long argument lists (`RootView+Phone.swift:40-59`, `:86-106`
  `[code]`), which is the pattern `ROOT/CLAUDE.md` warns about.

### Option D. Pinned at the top, two ways

One list, as A, with pinned conversations given their own place above it. D1 and D2 are drawn side
by side.

#### D1. A grid of large avatars

What Messages does (`[pat]`: the grid from Apple's guide; the cap of nine from a 2020 article).

| Measure | Value at 402 | Drawn by |
|---|---|---|
| Grid | 3 columns, each (402 - 32 - 24) / 3 = 115.3 wide; 12 between columns, 14 between rows; 8 above, 12 below (125.3 wide at 440 with a 20 margin) | `LazyVGrid` in the list's first row, with zero row insets and no separator |
| Cell | avatar 80, centred in the column; 6; name in Footnote, primary, one line, centred, truncating | by hand, from `LazyVGrid`, the avatar views and `Text`. Reason: the system has no pinned tile |
| Cell height | 80 + 6 + 18 = 104 | |
| Grid height | 3 pins: 124. 6 pins: 242. 9 pins: 360 | |
| Unread | an 8 pt accent dot before the name, 4 pt gap; and the U1 capsule centred on the avatar's edge at the top trailing corner (centre 68, 12 inside the 80 pt box) with a 2 pt page-colour ring | by hand |
| Silenced | `moon.fill`, Caption 2, tertiary, before the name | `Image(systemName:)` |
| Limit | 9. The build has no pin limit today (`RoomOrganisation.swift:150-175`); past 9 the rest are pinned rows at the top of the list | |
| Tap, hold | tap opens it; touch and hold gives the same menu as a row | `NavigationLink`, `.contextMenu` |
| Reorder | in the Edit list sheet, as today (`UI/Screens/Rooms/EditRoomsListView.swift:57-64`); on iOS 27, drag in place with `reorderable()` (`[hig]` 2, needs an availability check) | |
| Swipe | none on a tile. The same actions are in the menu and the Edit list sheet | |
| AX5 | The grid becomes D2's pinned rows at any accessibility size: a 115 pt column cannot hold a 44 pt name | `dynamicTypeSize.isAccessibilitySize` |

**Costs.**

- A pinned conversation loses its last line and its time. Messages puts a preview bubble over the
  avatar to give some of that back (`[pat]`); this spec does not draw one.
- With six pins the first ordinary row starts 242 pt lower.
- The Outposts tab already opens with a row of 52 pt faces with names under them
  (`OutpostFeedView.swift:256-289`). Two tabs would then open with faces that mean different things.
- A new limit and a new layout to test at every text size.

#### D2. Pinned rows under a heading

What Signal does (`[pat]`, source).

| Measure | Value | Drawn by |
|---|---|---|
| Sections | "Pinned", then "Most recent". Both words are in the build (`EditRoomsListView.swift:63,98`). Shown only when something is pinned | `Section` with a header, `.sectionHeading()` (`UI/Theme/Accessibility.swift:22-25`): Caption 2 semibold |
| Header | text at the margin; a plain list keeps the header at the top while its section scrolls (from memory, not verified) | `List` |
| Rows | R, without the pin glyph inside "Pinned" | |
| Unread, swipe | as A | |
| AX5 | as A; headers grow with the text (Caption 2 is 40 / 48 at AX5) | |

**Costs.** Two header lines. Nothing is lost.

### Option E. Compact

One list, more rows. Two densities are drawn.

| Measure | E1: one preview line | E2: name only |
|---|---|---|
| Margin | 16 | 16 |
| Avatar | 40, x 16 to 56 | 32, x 16 to 48 |
| Gap | 12 | 10 |
| Text | x 68 to 386, 318 wide | x 58 to 386 |
| Above and below | 8 and 8 | 6 and 6 |
| Lines | name (Headline) with marks and time (Footnote); then **one** preview line (Subhead) with the U1 capsule at its trailing end | name (Headline), marks, then at the trailing end the unread mark and the time (Footnote) on the same line |
| Row height | 8 + 22 + 2 + 20 + 8 = **60** | 6 + 32 + 6 = **44**, the minimum touch height (`Metrics.swift:11`) |
| Separator | from x 68 | from x 58 |
| Room avatar | one 40 pt drawing, same box as a person's. No wider frame | one 32 pt drawing |
| Unread | U1, capsule 20 high | U1 dot, 10 pt (a capsule does not fit beside the time at this height) |
| Rows on screen | about 10 to 11 (estimate) | about 14 (estimate) |
| Title | Inline "Messages" | Inline |
| Tab bar | minimises as the list scrolls down: `tabBarMinimizeBehavior(.onScrollDown)` (`[hig]` 2) | same |
| Pinned, swipe | as A | as A |
| AX5 | Density stops applying at accessibility sizes; the row is A's AX5 row with one preview line | same |

For comparison, today's Compact is 56 pt with no preview (section 1.1). E1 costs 4 pt more per row
and gives the last line back.

With "Pictures in conversations" off (`UI/Screens/You/Settings/AppearanceSettingsView.swift:62-73`
`[code]`) every option loses its avatar and its text starts at the margin, x 16, as the build
already does at x 20 (`RoomRow.swift:35,68-73`).

**Costs.** None of the five messengers has a density switch on iPhone (`[pat]`), so this is the
app's own; it exists already and members may be using it. E2 has no preview and a 32 pt avatar,
which is small for a room drawing (section 3).

### Option F. Today, corrected

The row as built, with only the space taken out. This is the smallest change; section 7 gives the
lines.

| Measure | Comfortable | Compact |
|---|---|---|
| Unread column | 16 wide, an 8 pt dot at x 4 to 12 (U2) | same |
| Avatar | 48, x 16 to 64 | 40, x 16 to 56. No wider frame unless the room draws two or three faces |
| Gap, text | 12; text at x 76 | 12; text at x 68 |
| Row height | 80, unchanged | 56, unchanged |
| Separator | from x 76 | from x 68 |
| Trailing | 16, with the chevron | same |
| Default person disc | fill raised so it has an edge (section 3, P2 or P3) | same |
| Tabs, title, compose, pins | as today | as today |
| Swipe | none, as today | none |
| AX5 | as today: name and time stack, the preview may run to six lines (`RoomRow.swift:55-59,95-97`) | same |

**Costs.** The avatar stops lining up with the tag pills and the "Waiting to be let in" rows, both
at x 20 (`RoomRowViews.swift:190`, `RoomsListView+Content.swift:43-48`), unless those two lines move
to 16 as well. The grid in `decisions.md:5043-5045` has to be rewritten. Nothing else changes, so
none of the missing things in 1.4 is fixed.

### 2.G Side by side

Points, at 402 pt.

| | Today | A | B | C | D1 / D2 | E1 | E2 | F |
|---|---|---|---|---|---|---|---|---|
| Solos and rooms | two tabs (default) | one list | one list + filter | two tabs | one list | one list | one list | as today |
| Left of the avatar | 20 (39.2 Compact) | 16 | 16 | 16 | 16 | 16 | 16 | 16 |
| Avatar | 48 / 40 | 52 | 52 | 52 | 80 grid / 52 | 40 | 32 | 48 / 40 |
| Text starts | 80 / 91.2 | 80 | 80 | 80 | 80 | 68 | 58 | 76 / 68 |
| Row height | 80 / 56 | 84 | 84 | 84 | 104 tile / 84 | 60 | 44 | 80 / 56 |
| Unread | leading dot in its own column | count, trailing | count | count | dot and count / count | count | dot, trailing | dot in the margin |
| Pinned | first, disc on the avatar | first, glyph | first, glyph | first, glyph | grid / headed section | first, glyph | first, glyph | as today |
| Chevron | yes | no | no | no | no | no | no | yes |
| Swipe | none | Read, Pin; Silence | same | same | same (rows) | same | same | none |

---

## 3. Default avatars

None of these is a photograph. A picture is shown only when somebody chose one; the order that
decides which picture wins is unchanged (`UI/Components/Shared/AvatarSource.swift:12-34` `[code]`).

### 3.1 The rule that picks the colour

- Seven colours: the app's accent set without Monochrome, in the order the code lists them
  (`Accent.swift:19-26`): 0 Cobalt, 1 Verdigris, 2 Signal Amber, 3 Oxblood, 4 Aubergine,
  5 Hangar Slate, 6 Olive Drab.
- **A person: the first byte of their id, modulo 7.** The id is 32 bytes and is already a SHA-256
  digest (`KIT/Crypto/Identity.swift:4-11`).
- **A room: the first byte of its id, modulo 7.** The id is a random UUID
  (`KIT/Model/ReadModel.swift:3-8`).
- What that gives: the same colour on every device with nothing stored or sent; no change when a
  name changes; no new saved field. 256 is not a multiple of 7, so colours 0 to 3 turn up 37 times
  in 256 and colours 4 to 6 turn up 36 (computed).
- Exceptions, unchanged: the member's own avatar keeps the accent tint (`AvatarView.swift:56`); an
  anonymous persona keeps its symbol on the accent (`AvatarView.swift:41-44,55`).
- The HIG has no page on default avatars (`[hig]` 3.18). Signal and Telegram both pick the colour
  from the id (`[pat]`, source).

Values, computed with the palette's own arithmetic (`Palette.swift:75-83`, `UI/Theme/Contrast.swift:18-55`):

| # | Colour | Light solid | White on it | Dark solid | White on it | Light tint on the page | Dark tint on the page |
|---|---|---|---|---|---|---|---|
| 0 | Cobalt | `#2F62DE` | 5.35 | `#4171D4` | 4.63 | `#D9DFF4` | `#1F2D4B` |
| 1 | Verdigris | `#14766C` | 5.47 | `#277D74` | 4.92 | `#D5E2E5` | `#193436` |
| 2 | Signal Amber | `#945D0F` | 5.48 | `#9D6721` | 4.78 | `#E6DFD9` | `#3F301F` |
| 3 | Oxblood | `#A5333A` | 6.70 | `#AF5C5F` | 4.65 | `#E8D9DE` | `#3B272D` |
| 4 | Aubergine | `#7048BC` | 6.28 | `#7D63AA` | 4.96 | `#E1DCEF` | `#302B43` |
| 5 | Hangar Slate | `#546A7E` | 5.62 | `#627080` | 5.06 | `#DDE0E7` | `#2B313A` |
| 6 | Olive Drab | `#607120` | 5.41 | `#6A782E` | 4.84 | `#DFE1DB` | `#2F3523` |

"Solid" is the accent darkened until white reads at 4.6:1 or better, the rule the sent bubble uses
(`Palette.swift:69-85`). "Tint" is the accent at 13% (light) or 22% (dark) over the page
(`Accent.swift:52-53`).

### 3.2 A person with no picture, three ways

Sizes: initials are semibold at 0.37 of the diameter (`Typography.swift:25-27`): 19 pt in a 52 pt
disc, 15 in 40, 10 in 28. Initials are the first letters of up to two words, a leading article
dropped, or the name's leading emoji (`KIT/Presentation/AvatarInitials.swift:6-19`). With no usable
name: `person.fill` at 0.46 of the diameter (the size rule at `AvatarView.swift:43`).

| | P1. Tinted | P2. Solid | P3. One grey |
|---|---|---|---|
| Disc | the person's colour as a tint (table above) | the person's colour, solid | `#787880` at 20% light (`#DADADF` on the page), 30% dark (`#313239`): the existing `neutralFillStrong` (`Palette.swift:251-253`) |
| Initials | the person's colour at full strength | white | secondary text |
| Colour rule | 3.1 | 3.1 | none; everybody is the same |
| Disc against the page | 1.18 to 1.22 light, 1.33 to 1.45 dark | 4.80 to 6.00 light, 3.64 to 3.98 dark | 1.25 light, 1.44 dark |
| Initials against the disc | 4.03 to 4.92 light, 3.94 to 5.07 dark. Above the 3:1 the HIG asks of bold or large text; five of the seven in light are under the 4.5:1 it asks of small regular text (`[hig]` 3.10) | 4.63 to 6.70 | 5.40 light, 6.82 dark |
| Drawn by | `AvatarView`, the drawing it already does for the member's own avatar (`AvatarView.swift:56,61`), given a colour | `AvatarView` with a solid fill | `AvatarView` with the stronger fill |
| What it is like | Soft. The edge is still faint, so the left edge of the list is still soft | A clear disc with a clear edge; people can be told apart at a glance. Closest to Signal and Telegram | Calm and uniform, closest to Messages. People cannot be told apart, and the edge is only a little clearer than today's 1.09 |

### 3.3 A room with no picture, three ways

A room cannot have a picture of its own yet (`decisions.md:5051-5053`). What it shows today is a
ruling: the people who spoke last (`decisions.md:5032-5041`, RULED 2026-09-28), whose stated purpose
is that "a room never looks like a one-to-one conversation". Today's drawing misses that purpose
when nobody else has spoken (section 1.4). R1 keeps the ruling. R2 and R3 replace it and need
Griff's yes.

| | R1. The room, and who spoke last | R2. Rounded square | R3. Group glyph |
|---|---|---|---|
| Shape | Two overlapping discs in a box the size of a person's avatar, with nothing around them. **Back**, top leading, 0.58 of the box (30 pt in 52): the room's colour, solid, with the first initial of the room's name in white. **Front**, bottom trailing, 0.69 of the box (36 pt in 52): the most recent speaker other than the viewer, drawn as that person's own avatar, with a ring in the page colour (2.3 pt in 52; the existing rule, `RoomRowViews.swift:67`) | A square the size of a person's avatar with continuous corners of 0.25 of its side (13 pt in 52). The room's colour, solid. The room name's initials in white at 0.37 of the side | A circle in the room's colour, solid, with `person.2.fill` in white at 0.46 of the diameter (24 pt in 52) |
| When nobody else has spoken | The front disc is the grey of P3 with `person.2.fill` in secondary text. It is still two discs, so it is still a room | no change | no change |
| Small sizes | Under 48 pt the back disc carries no letter (in 40: back 23, front 28; in 32: back 19, front 22). The ruling already dropped letters that were too small to read | initials stay | glyph stays |
| Who spoke last | yes, the front disc | optional: that person's avatar at 0.4 of the side, bottom trailing, with the ring. That corner is free once the pin mark moves beside the name | same option |
| Stays the same between messages | the back disc does; the front changes | yes | yes |
| Tells a room from a Solo | by shape, always | by shape, always | by glyph, always; the outline is a circle like a person's |
| Colour rule | 3.1, on the room's id | same | same |
| Drawn by | by hand, from two `AvatarView`s in a `ZStack`. Reason: no system component draws a group avatar | by hand: `RoundedRectangle(cornerRadius:style: .continuous)` and `Text` | `AvatarView` with a symbol, which it already supports (`AvatarView.swift:41-44`) |
| Used by | Messages gathers member pictures in one circle (`[pat]`) | none of the five | Signal (`[pat]`, source) |
| Costs | Still changes when somebody speaks, though less than today. Replaces the frosted disc and the three-face stack Griff approved on his second look | Reverses the ruling. A room's initials can be odd ("A1" for Allotment 14) | Reverses the ruling. Every room looks alike apart from colour |

In every treatment the box is exactly the avatar size, so a room's left edge is at the margin and
its text starts where a Solo's does. The wider Compact frame goes.

---

## 4. Starting a conversation, two ways

What the build requires, and both options keep:

- A Solo is with somebody the member already shares a room with (`UI/Screens/Membership/SoloPickerView.swift:19-33`).
- Starting one makes the Solo and an invitation, and the invitation has to be sent by the member:
  "has not been sent this yet. Nothing reaches them until you do."
  (`UI/Screens/Membership/InviteView.swift:113-122`; `AppRootView.swift:562-575`).
- A room needs a name; who must agree before somebody joins is optional
  (`UI/Screens/Membership/NewRoomView.swift:33-78`).
- Whether a member can write in a new Solo before the other person joins was not traced: not
  verified.

HIG rules that apply (`[hig]` 3.7, 3.9): a compose sheet is full height; Cancel leading; in a sheet
with steps, Back replaces Cancel after the first and Done waits for the last; one sheet at a time;
a menu wants three or more items, and the combined list's compose menu has two.

### N1. One button, pick, and you are in it

What Signal, Threema and WhatsApp do (`[pat]`).

| Screen | What is on it | Drawn by |
|---|---|---|
| **1. The list** | One compose button, trailing, on every arrangement. VoiceOver: "New message" (proposal) | `Button`, `square.and.pencil` |
| **2. New message** | A full-height sheet that grows out of the button. Bar: "Cancel" leading, title "New message" (proposal) inline, nothing trailing. A search field that stays in view, prompt "Search people" (in the build, `SoloPickerView.swift:58`). First section, two rows: **New room** (`person.2`) and **Join with an invite** (`qrcode`; in the More menu today, `RoomsListView+Actions.swift:198-206`). Then the people the member can reach, A to Z with the index, each a 40 pt avatar and a name. With nobody yet: the two rows, then "Nobody to send to yet" and its line (in the build, `SoloPickerView.swift:21-31`) | `.sheet` with `.presentationDetents([.large])`; `NavigationStack`; `List` with `Section`, `.groupedRowSurface()`, `.sectionIndexLabel` as the Solo picker has today; `.searchable`; `PersonRow` (`UI/Components/Shared/PersonRow.swift`); `ContentUnavailableView`. Where iOS 27 places a search field inside a sheet is not verified; draw it under the title |
| **3a. A person who already has a Solo with the member** | The sheet closes and that Solo opens with the field focused and the keyboard up | dismiss, then append to the stack's path |
| **3b. A person with no Solo yet** | The same sheet pushes the invitation: the person's name as title, "Back" leading, "Done" trailing. Content as built: the line quoted above, the code to scan, the characters to compare, "Send the invite", when it expires (`InviteView.swift:48-105`). Done closes the sheet and opens the new Solo; its row carries the invited mark until they are in | `NavigationStack` push inside the sheet; `ShareLink`; the existing `InviteView` content |
| **4. New room** | The same sheet pushes "New room": "Back" leading, "Create" trailing, off until there is a name. Name field, focused. "Advanced setup" as built. In place of the "Bring people in" switch, a row "Invite people" with the number chosen as its value, which pushes the existing multi-select list (`UI/Screens/Membership/PeoplePickerView.swift:17-56` `[code]`) | `List`, `TextField`, `Toggle`, `NavigationLink`; `ToolbarItem(placement: .confirmationAction)` |
| **5. After Create** | The sheet closes and the room opens with the field focused | |

**Costs.** The Solo and room sheets become steps of one sheet, so the three places that present
them today (`RoomsListView+Content.swift:135-153`) become one. Opening the conversation afterwards
is new. The "Bring people in" preference (`NewRoomView.swift:57-70`) goes.

### N2. A To line

What Messages does: one screen, and a group is a message with more than one recipient (`[pat]`).

| Screen | What is on it | Drawn by |
|---|---|---|
| **1. The list** | as N1 | |
| **2. New message** | A full-height sheet. "Cancel" leading, title "New message". A **To:** line under the title that takes names as tokens. Under it, matching people as they are typed. The composer is at the bottom, off until somebody is chosen | `.searchable(text:tokens:)` standing in as the To line, or a `TextField` with tokens drawn by hand. Reason for anything by hand: SwiftUI has no recipient field |
| **3. One person** | The To line holds one token. The composer turns on. The member writes and sends | the conversation's own composer |
| **4. After Send, one person** | The sheet pushes the invitation step from N1 3b, then Done opens the Solo | |
| **5. Two or more people** | A "Room name" field appears under the To line and is required. "Create" appears trailing. Advanced setup is a row under the name | `TextField`, `ToolbarItem(.confirmationAction)` |
| **6. After Create** | The room opens; what was typed is its first message | |

**Costs.**

- A Solo and a room are different things here: a room has a name and rules about who gets in, a
  Solo has an invitation and a check. One To line draws them as the same thing with a different
  number of names.
- The first message is typed before the invitation is sent, and the build's own words are that
  nothing reaches the other person until it is. A screen that reads as "sent" when nothing can
  arrive overstates, which the project's honesty rules forbid (`ROOT/CLAUDE.md`). Whether that first
  message would reach somebody who joins later is not verified.
- More new code than N1, and a field the system does not supply.

---

## 5. The conversation screen

### 5.0 Parts both options keep

| Element | Value | Drawn by |
|---|---|---|
| Runs | Messages from one person, each within 300 seconds of the one before, are one run (`KIT/Presentation/ConversationLayout.swift:69,85-101`) | |
| Bubble | Body text; 14 pt side padding, 9 pt above and below; mine in the accent fill with white text, theirs in the accent tint. Corner radius by height: 9 under 40 pt, 14 under 64, else 20; the last bubble of a run has one 6 pt corner on the sender's side. A one-line bubble is 40 pt high, so it takes the 14 radius. No drawn tail (`MessageBubbleView.swift:17-49`, `Metrics.swift:15-25`) | by hand: `UnevenRoundedRectangle`. Reason: the system has no chat bubble |
| Width limit | 74% of the transcript: 274 pt at 402 (`Metrics.swift:17`) | |
| Mine | right-aligned to x 386; no avatar, no name | |
| Under my last bubble | the marks as built: a paper plane (received), an eye (shown), an optional time it was shown, or the orange not-received mark (`UI/Components/Messaging/DeliveryMarkView.swift:56-89`) | |
| Reactions, the long-press bar and menu | as built (`MessageBubbleView.swift:213-253`) | |
| Composer | As built: a 38 pt glass circle with `plus`, a glass field with a 19 pt radius, placeholder "Message", a 30 pt accent circle with `arrow.up` when there is something to send; 12 pt side and 8 pt vertical padding, in one `GlassEffectContainer` (`UI/Screens/Messaging/ConversationView+Composer.swift:204-294` `[code]`). **Change:** it moves from a sibling under the scroll view (`ConversationView.swift:157-200`) into `safeAreaBar(edge: .bottom)`, so messages pass under the glass and the scroll edge effect reaches it (`[me]`, URL in 2.B) | `GlassEffectContainer`, `TextField(axis: .vertical)`, `PhotosPicker` |
| Scroll edge | automatic, top and bottom (`.soft` is forced today, `ConversationView+Transcript.swift:56`) | |
| Tab bar | hidden in a conversation, as today (`ConversationView.swift:252`) | |
| A Solo | **No avatar beside any run.** The person is in the bar. Incoming bubbles start at the margin | |

Cost of the composer change: it alters how the keyboard and the scroll anchor behave, which has to
be looked at on the rig with the software keyboard up (`ROOT/CLAUDE.md`, the keyboard trap).

### T1. Quiet

The fewest marks. Times appear only where time passed.

| | A Solo | A room |
|---|---|---|
| Bar | Title: the person's name. Trailing: the menu, as built | Title: the room's name; under it "5 members" as the system's subtitle. Trailing: the menu. Drawn by `navigationTitle` and `navigationSubtitle` (iOS 26, `[hig]` 2), replacing the hand-built principal item (`ConversationView.swift:224-236`) |
| Side margin | 16 (14 today) | 16 |
| Incoming bubble starts | x 16 | x 52: a 28 pt avatar at x 16 to 44, 8 pt gap |
| Avatars | none | 28 pt, at the bottom of each incoming run, level with its last bubble; a tap opens that person's page, as today (`MessageBubbleView.swift:179-188`) |
| Names | none | above the first bubble of each incoming run: Caption 1 semibold, in the sender's colour from 3.1 at full strength (4.8:1 or better on the page in both modes, computed), 12 pt in from the bubble's edge, 3 pt above it. With avatar treatment P3 the name is tertiary grey, as today |
| Spacing | 3 pt between bubbles in a run, 8 pt after a run (as built, `ConversationView+Transcript.swift:12,26`) | same |
| Dates | A centred line in Caption 2 semibold, quaternary: before the first message of each day ("Yesterday 6:02 PM", "Today 9:36 AM"), and again inside a day when an hour or more has passed since the previous message ("11:15 AM"). 16 pt above, 12 pt below. The style is the built one (`ConversationView+Transcript.swift:102-108`); the build shows it once, at the top | same |
| A message's own time | not on screen; it is in Details from the long-press menu, as today | same |
| Room notices | the same centred line: "Tobias invited Len", "Len confirmed the invitation" (`UI/Components/Messaging/NoticeCopy.swift:24,29`) | |

### T2. Stated

Every run says when. Days are headed and the heading stays in view.

| | A Solo | A room |
|---|---|---|
| Bar | Centre: a button holding a 28 pt avatar and the name in Headline; it opens "Who you are talking to". Trailing: the menu | Centre: a button holding the room's 28 pt avatar and name; it opens "Who is in this room". Trailing: the menu. Drawn by `ToolbarItem(placement: .principal)` with a `Button`. Both destinations are the first items of today's menu (`UI/Screens/Messaging/ConversationView+Menu.swift:20-180` `[code]`) |
| Side margin | 16 | 16 |
| Incoming bubble starts | x 16 | x 52 |
| Avatars | none | 28 pt at the **top** of each incoming run, level with its first bubble |
| Names | none | **inside** the first bubble of the run, as its first line: Caption 1 semibold in the sender's colour, 2 pt above the text |
| Time | Under the last bubble of every run: Caption 2, tertiary, 3 pt below, in line with the bubble's text edge. For mine it sits at the trailing edge, before the received and shown marks | same |
| Spacing | 3 pt in a run, 10 pt after a run | same |
| Days | Each day is a section whose heading stays at the top while its messages scroll: "Today", "Yesterday", "Sunday", "Nov 2". The heading is a centred capsule 24 pt high, 10 pt side padding, Caption 1 semibold, secondary text, on `.regularMaterial`; 8 pt above and below. A run never crosses midnight | `LazyVStack(pinnedViews: [.sectionHeaders])` with a `Section` per day (https://developer.apple.com/tutorials/data/documentation/swiftui/pinnedscrollableviews.json `[me]`). The capsule is by hand; reason: a heading that stays over moving bubbles needs a backing, and a standard material is allowed in the content layer where glass is not (`[hig]` 3.11) |
| Room notices | the centred line, as T1 | |

### T3. Compact

For either option's Solo and room. More messages on screen, nothing removed but the pictures.

| Measure | Value |
|---|---|
| Side margin | 12 |
| Avatars | none, in rooms as well |
| Names (rooms) | above the first bubble of an incoming run: Caption 2 semibold in the sender's colour, 12 pt in |
| Bubble padding | 12 at the sides, 6 above and below. A one-line bubble is 34 pt high and takes the 9 radius |
| Spacing | 2 pt in a run, 6 pt after a run |
| Width limit | 80%: 302 pt at 402 |
| Dates | as T1, with 10 pt above and 8 below |
| Text size | Body, unchanged. Text size is the member's setting, not the density's |
| Gain | a one-line bubble and its gap take 36 pt in place of 43 (computed) |

### 5.4 At the largest text size

- Body is 53 / 62. The width limit rises to 92% so a bubble holds more than two words a line.
- From AX3 up, avatars leave rooms and the coloured name above the run is what says who.
- Date lines, names and time lines grow with their styles (Caption 2 is 40 / 48 at AX5).
- The bar is drawn by the system and keeps its size.

### 5.5 Optional, both options

A "latest" button: a 36 pt glass circle with `chevron.down`, 12 pt above the composer at the
trailing margin, shown when the member has scrolled up more than a screen. Drawn by `Button` with
`.buttonStyle(.glass)`. Not in the build (`[code]` section 6); it needs the scroll position.

---

## 6. Notifications

### 6.0 What a banner can be

- An ordinary notification: the app's icon at the leading edge, then title, subtitle and body. No
  face, no room avatar (section 0.3).
- The push carries no words. The phone writes them after it reads the message, and only if it can
  read (`ROOT/App/CarpenterNotificationService/NotificationService.swift:55-127`).
- **It cannot read when the app lock is set, or when Advanced On Device Security is on and the
  phone is locked.** Then the banner is the one fixed line and the icon's number is left alone
  (`NotificationService.swift:55-63,76-79`; accepted by Griff 2026-11-10,
  `ROOT/docs/open-questions.md:178-180` `[ntf]`).
- The fixed line today is the app's name over "New message"
  (`KIT/Presentation/MessageNotification.swift:24`). It is also what a post, a request for saved
  history, a comment and a device change give. Proposal: "Something new arrived." Shown below as
  **the plain line**.
- The four levels are the member's choice, named on screen "Room, sender and message", "Room and
  sender", "Room only", "That a message arrived"
  (`UI/Screens/Notifications/NotificationLevelView.swift:201-210`).
- No banner from another account has been watched arriving on the rig (`[ntf]` 1.1). Nothing in
  this section was seen on a screen.

Sample names are from section 8. T = title, S = subtitle, B = body.

### 6.1 Messages

| # | Kind | Room, sender and message | Room and sender | Room only | That a message arrived | App lock set, or locked with Advanced On Device Security | Stack | Delivery | Actions | In the build |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | A message in a Solo | T Maren Okafor · B Train's delayed. Order without me. | T Maren Okafor | the plain line (proposal: in a Solo the room is the person) | the plain line | the plain line | that Solo; none for the plain line | sound | Reply, Mark as Read, Silence | Banner yes. Today the name is title and subtitle both, and "Room only" names the person (inferred: `KIT/Log/Projection+Standing.swift:322-323`, `MessageNotification.swift:41-43`). Actions no |
| 2 | A message in a room | T Allotment 14 · S Tobias Wren · B Who has the long hose? | T Allotment 14 · S Tobias Wren | T Allotment 14 | the plain line | the plain line | that room | sound | same | Banner yes (`MessageNotification.swift:27-52`). Actions no |
| 3 | A photo or clip | as 1 or 2, with B the caption, or "📷 Photo" / "🎬 Video". Never the picture | as 1 or 2 | as 1 or 2 | the plain line | the plain line | the conversation | sound | same | yes (`NotificationLevelView.swift:178-180`) |
| 4 | A reaction to your message | T Allotment 14 · B Tobias Wren reacted 👍 to your message | T Allotment 14 · S Tobias Wren | T Allotment 14 | the plain line | the plain line | the conversation | quiet | none | No, and nothing rings for it. Proposal, off unless the member turns it on |
| 5 | A message in a silenced conversation | the plain line, at every level | | | | the plain line | none | quiet: no sound, the screen stays dark | none | Today it is the plain line with sound (inferred, `[ntf]` 1.3). Quiet is the proposal |
| 6 | A message for the conversation on screen | no banner | | | | | | | | yes (`APP/Push/PushPresentation.swift:11`) |
| 7 | A message for another conversation while the app is open | as 1 to 3 | | | | | | banner, sound, icon number (`PushPresentation.swift:12`) | | yes. The HIG suggests showing it in place, on the list row and the badge, without interrupting (`[hig]` 3.12) |
| 8 | Your own message was not received | never a notification; it is marked in the conversation | | | | | | | | yes |

### 6.2 Changes to a room

These have their own switch and their own four levels (`KIT/Presentation/MessagingNotificationChoices.swift:24-33`),
with example sentences already on the settings page
(`UI/Screens/Notifications/MessagingNotificationsView.swift:132-141`). **No code builds any of these
banners, and nothing rings for them** (`[ntf]` 1.7). Every sentence below except row 11's is a
proposal.

| # | Kind | Names the person and the room | Names the room | Names what happened | Says only that a room changed | Locked, as 6.1 | Stack | Delivery |
|---|---|---|---|---|---|---|---|---|
| 9 | You were invited to a room | Sol Ibarra invited you to Harbour Ringers | You were invited to Harbour Ringers | You were invited to a room | New room update | the plain line | that room | sound |
| 10 | Somebody requested to join a room and members must answer | Kofi Brandt requested to join Allotment 14 | Somebody requested to join Allotment 14 | Somebody requested to join one of your rooms | New room update | the plain line | that room | sound |
| 11 | Somebody joined, left or was removed; the room was renamed; who may join changed; an invitation was answered | Len Abara has been added to Allotment 14 | A new member has been added to Allotment 14 | A new member has been added to one of your rooms | New room update | the plain line | that room | quiet |
| 12 | You were removed from a room | You were removed from Flat 3B | You were removed from Flat 3B | You were removed from a room | New room update | the plain line | that room | sound |

No actions on any of these. A tap opens the room, or the invitation.

### 6.3 Outposts

| # | Kind | Room, sender and message | Room and sender | Room only | That a message arrived | Locked, as 6.1 | Stack | Delivery | On by default | In the build |
|---|---|---|---|---|---|---|---|---|---|---|
| 13 | A new post on an Outpost the member turned on | T Ines Varga · S Posted to their Outpost · B the words, or the photo line | T Ines Varga · S Posted to their Outpost | T New post | the plain line | the plain line | that Outpost | sound | by Outpost | yes (`MessageNotification.swift:58-79`). A tap does not open the Outpost today (`[ntf]` 1.6) |
| 14 | A comment on your post | T Dev Halloran · S Commented on your post · B the comment | T Dev Halloran · S Commented on your post | T New comment | the plain line | the plain line | that Outpost | sound | yes | It rings today and shows "New message" (inferred, `[ntf]` 1.3). The words are a proposal |
| 15 | A comment on a post you commented on | T Dev Halloran · S Also commented on Ines Varga's post · B the comment | T and S | T New comment | the plain line | the plain line | that Outpost | sound | yes | as 14 |
| 16 | A comment on a post you reacted to | as 15 | | | | | that Outpost | sound | no | nothing rings (`APP/Session/AppSession+Messaging.swift:76-80` `[ntf]`) |
| 17 | A reaction to your post | T Dev Halloran · S Reacted 💜 to your post | T Dev Halloran · S Reacted to your post | T New reaction | the plain line | the plain line | that Outpost | quiet | no | It rings today with sound and shows "New message"; the member's switch is not read (inferred, `[ntf]` 1.7) |
| 18 | Somebody shared their Outpost with you | T Ines Varga · S Shared their Outpost with you | same | T New Outpost | the plain line | the plain line | that Outpost | quiet | | no |

### 6.4 Devices, keys and the rest

The levels do not apply except on row 22.

| # | Kind | Banner | Locked, as 6.1 | Stack | Delivery | Actions | In the build |
|---|---|---|---|---|---|---|---|
| 19 | A new device on your Apple Account is requesting approval | T Device Approval Requested · B A new iPhone requested access to your account. | the same words, if it has its own kind of push: a push's fixed words are set per record type (`[ntf]` 3.2). The cost is that iCloud can see that kind of event happened | devices | Time Sensitive. Apple's own example of one is an account security issue (https://developer.apple.com/tutorials/data/design/human-interface-guidelines/managing-notifications.json `[ntf]`). Whether the level is honoured for an iCloud push is not verified | none. Approving is a security decision and stays on a screen in the app | no; silent today, shown when the app next runs (`[ntf]` section 4) |
| 20 | This device was approved or declined | B This iPhone was approved. | the plain line | devices | sound | none | no |
| 21 | One of your devices was removed | B Spare iPhone was removed. Nothing on the removed device | the plain line | devices | quiet | none | no |
| 22 | A contact restored with a recovery key and requested saved history | Top two levels: T Maren Okafor set up a new device · B New device requested history backfill of Allotment 14. "Room only": T Somebody set up a new device, same body. Lowest level: the plain line | the plain line | that person | sound | none | yes; these words are reviewed copy (`KIT/Presentation/RestoreNotification.swift:16-40`). A tap goes nowhere today (`[ntf]` 1.6) |
| 23 | A contact added or removed a device | Proposal: no banner; a line in the conversation | | | | | Today it rings every contact and shows "New message" (`ROOT/docs/inbox.md:508-513` `[ntf]`) |
| 24 | Somebody you blocked writes | nothing arrives | | | | | by construction (`ROOT/docs/pre-testflight.md:41-44` `[ntf]`) |
| 25 | A photo was screened; a check-up is due; the recovery key is not saved; wrong codes at the app lock | never a notification; in the app | | | | | yes |
| 26 | A newer version of the app is needed | in the app. No push can cause it without a server; the migration topic covers it | | | | | no |
| 27 | **The plain line**: the phone could not read, or the level says so, or a Focus leaves the room out, or time ran out | The app's name over "New message" today; proposal "Something new arrived." | the same | none | sound, except: quiet for a room a Focus leaves out and for an erased device (`NotificationService.swift:81-84`, `APP/Session/ArrivingBanner.swift:67-73` `[ntf]`) | none | yes |

### 6.5 Grouping, actions, the number on the icon

- **Stacks.** One per conversation, one per Outpost author, one per restoring person, one for the
  member's devices. The plain line carries no thread, because a thread identifier is itself a
  disclosure (`KIT/Presentation/NotificationLevel.swift:20` `[ntf]`), so plain lines stack only as
  the app's.
- **Actions**, on named message banners only (rows 1 to 3 at the top three levels): **Reply**, a
  text field (`UNTextInputNotificationAction`), requiring the phone to be unlocked; **Mark as
  Read**; **Silence**. They need only UserNotifications, not Siri. They run in the app in the
  background, so they cannot exist while the app lock is set (`[ntf]` 3.4). How long the app gets,
  and whether a reply can be sent in that time, is not verified. The HIG allows up to four and asks
  for none that merely opens the app (`[hig]` 3.12).
- **When the member has turned previews off in iOS Settings**, the system shows the app's icon,
  "Notification" and a placeholder the app supplies per category (`[hig]` 3.12). Proposed
  placeholders: "New message", "New post", "New comment", "Room update", "Device approval
  requested". There are no categories today, so what iOS shows is not verified.
- **The number on the icon** counts conversations with something unread plus Outposts with
  something unseen, each behind its own switch (`APP/Push/BadgeCount.swift:5-13` `[ntf]`). With the
  app lock set it goes stale until the app opens.
- **Clearing.** Reading a conversation in the app should take its banners out of Notification
  Center. Nothing does that today (`[ntf]` 1.6).
- **In the app.** The list's unread mark (section 2), the tab badges, the silenced moon. A tab
  badge counts conversations, not messages.

### 6.6 What is not true today, in one place

These change what the artboards may claim. All from `[ntf]` 1.7, read against the code there.

- The Messaging on/off switch, the Messaging levels, the room-changes switch and levels, "All
  posts" and "None", and the four Outpost comment and reaction switches are saved and read by
  nothing that makes a banner. The one default level the phone does read has no screen that sets it.
- With the app lock set, the four levels do nothing; the settings pages do not say so.

---

## 7. What I would pick, and the smallest fix

### 7.1 The combination

| Part | Pick | Why, in plain words |
|---|---|---|
| Arrangement | **Option A, one list**, with the filter as one menu button in the bar (borrowed from B, without the segmented band). Two tabs stay as the setting they already are | All five messengers studied do it this way. One list is one place to look and one badge. The filter is there for the member who has many rooms, and costs no height for the one who does not |
| Row | **R with U1**: a 52 pt avatar at the margin, nothing to its left, the count at the trailing end; the dot in the same place until the count exists | It removes the reserved column outright. Every row then starts with a visible disc on one line, which is the complaint. The text column stays at x 80, where it is today |
| Title | Large title "Messages" | Its left edge sits on the same line as the avatars |
| Pinned | First, as ordinary rows, with the glyph (A). Not the grid | The grid loses the last line and the time for the conversations the member cares most about, and looks like the Outposts tab |
| Compact | **E1**, 60 pt with one preview line, replacing today's 56 pt with none | Four points buys the last line back |
| Person default | **P2, solid colour with white initials** | The disc has an edge (4.8:1 or better against the page in light, where today's is 1.09:1), and people can be told apart |
| Room default | **R1, the room and who spoke last** | It keeps what Griff ruled on 2026-09-28 and meets that ruling's purpose in the one case today's drawing misses. The room keeps one stable mark, its own colour, so it can be found by eye |
| New message | **N1** | One button, one sheet, and it ends inside the conversation. It does not draw a Solo and a room as the same thing |
| Conversation | **T1**, and T3 when Row size is Compact, so one setting covers both screens | It takes the picture out of Solos, where it says nothing, and puts times only where time passed |
| Notifications | Make the kinds that ring today say true things first (rows 1, 5, 14, 17, 23, 27), then comments, then the device approval, then actions | A banner that says "New message" for a reaction is the app saying something untrue |

What I am not sure of: which density Griff was looking at; whether his phone's margin is 16 or 20;
whether R1 reads well at 40 pt, which only a drawing will show.

The parts are independent. Any row goes with any arrangement, any avatar treatment with any row,
and either conversation option with either new-message flow. The two exceptions: the D1 grid needs
its own unread mark, and T1's coloured names need P1 or P2.

### 7.2 If Griff wants only the padding fixed

Option F. Three changes, each on its own.

| # | Change | Where | Effect |
|---|---|---|---|
| a | Narrow the unread column from 20 to 16 and the dot from 10 to 8 | `RoomRow.swift:32` and `:28` | The avatar starts at 16 on every row |
| b | In Compact, use the wide frame only when the room draws two or three faces | `RoomRow.swift:47-50`, `RoomRowViews.swift:63-65` | A Solo's avatar moves from 39.2 to 16 (with a). Does nothing in Comfortable |
| c | Give the default disc an edge: raise the light fill from 8% to 20%, or adopt P2 | `Palette.swift:256-259` | The picture stops looking as if it starts at the initials |

In the default density, a and c are the fix. To keep things lined up, two more lines move from 20
to 16: the tag pills (`RoomRowViews.swift:190`) and the "Waiting to be let in" rows
(`RoomsListView+Content.swift:46`). The grid written down in `decisions.md:5043-5045` has to be
updated to match. None of this has been built or seen.

---

## 8. Sample content

Invented. No real people. "Now" is Tuesday 10 November 2026, 9:41 AM, written the way a US phone
shows it.

### 8.1 People

`#` is the colour from 3.1. "Picture" means draw a simple abstract image, never a photograph of a
person.

| Name | Initials | # | Picture |
|---|---|---|---|
| Maren Okafor | MO | 3 Oxblood | none |
| Dev Halloran | DH | 0 Cobalt | a leaf on teal |
| Ines Varga | IV | 4 Aubergine | none |
| Kofi Brandt | KB | 0 Cobalt | none |
| Lucille Tran | LT | 2 Signal Amber | none |
| Tobias Wren | TW | 6 Olive Drab | none |
| Priya Nandakumar | PN | 1 Verdigris | a striped mug on cream |
| Len Abara | LA | 5 Hangar Slate | none |
| Greta Lindqvist | GL | 2 Signal Amber | none |
| Sol Ibarra | SI | 3 Oxblood | none |

### 8.2 Rooms

| Name | Initials | # | Members | Most recent speakers, newest first |
|---|---|---|---|---|
| Allotment 14 | A1 | 6 Olive Drab | 5 | Tobias, Priya, Len |
| Sunday Long Run | SL | 1 Verdigris | 6 | Dev, Len |
| Flat 3B | F3 | 0 Cobalt | 3 | Greta, Ines |
| Book Club, Slowly | BC | 4 Aubergine | 8 | Priya, Maren, Lucille |
| Night Shift | NS | 5 Hangar Slate | 2 | nobody but the viewer |

### 8.3 The ten conversations, in list order

Pinned first in the order pinned, then newest first.

| # | Kind | Name | Last line | Who said it | Time shown | Unread | State |
|---|---|---|---|---|---|---|---|
| 1 | Solo | Maren Okafor | Train's delayed. Order without me. | Maren | 9:38 AM | 2 | pinned |
| 2 | Room | Sunday Long Run | 10k loop or the reservoir? | Dev | Sunday | 0 | pinned |
| 3 | Room | Allotment 14 | Who has the long hose? | Tobias | 9:12 AM | 4 | |
| 4 | Solo | Dev Halloran | 📷 Photo | Dev | 8:05 AM | 1 | |
| 5 | Room | Flat 3B | Bins go out tonight. | Greta | Yesterday | 3 | silenced, so its count is grey |
| 6 | Solo | Ines Varga | Sounds good. See you at seven. | the viewer | Yesterday | 0 | |
| 7 | Solo | Kofi Brandt | No messages yet | | Saturday | 0 | invited, not yet in: the `person.crop.circle.badge.clock` mark |
| 8 | Room | Book Club, Slowly | Chapter nine by Friday. No excuses. | Priya | 11/2/2026 | 12 | |
| 9 | Solo | Lucille Tran | Call me when you land. | Lucille | 10/30/2026 | 0 | |
| 10 | Room | Night Shift | Anyone awake? | the viewer | 10/28/2026 | 0 | nobody else has spoken |

- Tab badge on Messages: 5. In two tabs: Solos 2, Rooms 3. Whether a silenced conversation counts
  toward the badge was not read: not verified.
- Under the title: "Caught up with Maren and Dev a moment ago."
- A "Waiting to be let in" row, for the one board that shows it: Sol Ibarra, "Invited you"
  (`UI/Screens/Rooms/AwaitingRow.swift:20`), to Harbour Ringers.
- People for the New message list, A to Z: Dev Halloran, Greta Lindqvist, Ines Varga, Kofi Brandt,
  Len Abara, Lucille Tran, Maren Okafor, Priya Nandakumar, Tobias Wren.

### 8.4 A Solo to draw: Maren Okafor

| When | Who | Words | Notes |
|---|---|---|---|
| Yesterday 6:02 PM | Maren | Are we still on for breakfast tomorrow? | date line above |
| 6:03 PM | viewer | Yes. 9:30 at the usual place? | marks under it |
| 6:03 PM | Maren | Perfect. | |
| Today 9:36 AM | Maren | Running behind, sorry. | date line above; one run with the next |
| 9:38 AM | Maren | Train's delayed. Order without me. | last bubble of the run: the 6 pt corner |
| in the field | viewer | No rush. Coffee or tea? | typed, not sent, so the send button shows |

The marks sit under the viewer's 6:03 PM bubble: received and shown.

### 8.5 A room to draw: Allotment 14, 5 members

| When | Who | Words | Notes |
|---|---|---|---|
| Yesterday 5:20 PM | notice | Tobias invited Len | centred line |
| 5:41 PM | notice | Len confirmed the invitation | centred line |
| 5:44 PM | Len | Hello, all. Plot 9, by the gate. | |
| 5:46 PM | viewer | Welcome, Len. | marks under it: received and shown |
| Today 8:50 AM | Priya | Frost got the last of the beans. | date line above |
| 8:51 AM | Priya | Compost delivery is Thursday. | same run |
| 9:10 AM | Tobias | Can anyone help unload it at four? | one run with the next |
| 9:12 AM | Tobias | Who has the long hose? | reaction on it: 👍 from Priya |

### 8.6 Lines for the banners

Use sections 6.1 to 6.4 as written. For the stack board: three from Allotment 14 (Priya 8:50,
Priya 8:51, Tobias 9:12), one from Maren Okafor, one post from Ines Varga ("First frost on the
canal this morning.").

---

## 9. Boards to draw

402 x 874 unless said. "Rulers" means dimension lines for every number in the table named.

| Board | Shows | From |
|---|---|---|
| L0 | Today's list, Comfortable and Compact side by side, rulers on the six causes | 1.1, 1.2 |
| LU | One row three times: U1, U2, U3; then read, unread, silenced and unread, pinned | 2.0 |
| LA-1, LA-2 | Option A, light and dark, the ten conversations | 2.A, 8.3 |
| LA-3 | Option A with rulers on one Solo row and one room row | 2.0 |
| LA-4, LA-5 | Leading swipe open on row 3; trailing swipe open on row 3 | 2.0 |
| LA-6 | Touch and hold on row 3: the preview and the menu | 2.0 |
| LA-7 | Option A at AX5 | 2.A |
| LA-8 | Option A at 440 pt with a 20 pt margin | 0.2 |
| LB-1, LB-2 | Option B with the segmented control; the filter menu open | 2.B |
| LB-3 | Variant B2, chips | 2.B |
| LC-1, LC-2 | Option C: Solos tab; Rooms tab, without and with the sender in the preview | 2.C |
| LD-1, LD-2 | D1 with three pins and with six | 2.D |
| LD-3 | D2 | 2.D |
| LD-4 | D1 at AX5, fallen back to rows | 2.D |
| LE-1, LE-2 | E1 and E2 | 2.E |
| LF-1 | Option F, Comfortable and Compact | 2.F |
| AV-1 | P1, P2, P3 at 80, 52, 40 and 28 pt, light and dark, for MO, IV, LT and a person with no name | 3.2 |
| AV-2 | R1, R2, R3 at 80, 52, 40 and 32 pt, light and dark, for Allotment 14, Flat 3B and Night Shift | 3.3 |
| AV-3 | The seven colours as swatches, solid and tint, light and dark | 3.1 |
| NM-1 to NM-5 | N1, screens 2, 3b, 4, the people list inside 4, and the empty case | 4 |
| NM-6 to NM-8 | N2, screens 2, 3 and 5 | 4 |
| CV-1, CV-2 | T1: the Solo; the room | 5, 8.4, 8.5 |
| CV-3, CV-4 | T2: the Solo; the room | 5 |
| CV-5 | T3: the Solo and the room | 5 |
| CV-6 | T1 room at AX5 | 5.4 |
| CV-7 | T1 room, dark, keyboard up | 5.0 |
| NT-1, NT-2 | The four levels side by side: a room; a Solo | 6.1 |
| NT-3 | A photo: with a caption, and "📷 Photo" | 6.1 |
| NT-4 | A stack on the Lock Screen | 6.5, 8.6 |
| NT-5 | A named banner held open with Reply, Mark as Read, Silence; beside it the plain line held open with none | 6.5 |
| NT-6 | An Outpost post, a comment on your post, and a reaction sitting quietly in the list | 6.3 |
| NT-7 | Room changes: the four forms of row 11; an invitation; a request to join | 6.2 |
| NT-8 | A device requesting approval, marked Time Sensitive | 6.4 |
| NT-9 | The same minute twice: app lock set (plain lines, stale number) and not set | 6.0 |
| NT-10 | In the app: list with unread marks, a silenced row, tab badges | 6.5 |

---

## 10. For Griff, and what was not checked

### 10.1 Needs his answer before anything is built

| # | Question | What I would do |
|---|---|---|
| 1 | Replace the row ruled on 2026-09-13 (leading dot, chevron) and the grid in the 2026-09-28 entry? | Yes, with row R |
| 2 | One list by default, two tabs as the setting? | Yes |
| 3 | An unread count, which needs the read model to carry a number, or the dot? | Dot first, count when it is costed by a test |
| 4 | Mark as Unread, which needs a new saved yes or no per conversation? | Yes, after the row |
| 5 | Keep "who spoke last" for a room (R1) or replace it (R2, R3)? | Keep it, as R1 |
| 6 | The sender's name in a room's preview, ruled out on 2026-09-13 when it cost a third line? | Reopen it as an inline prefix; draw it and decide |
| 7 | A colour per person, picked from their id? | Yes |
| 8 | A Solo at "Room only": the plain line? | Yes |
| 9 | The plain line's words | "Something new arrived." |
| 10 | Raise the iOS target from 26.5 to 27, or check availability at each iOS 27 call (`.pickerStyle(.tabs)`, `reorderable()`, the margin guide)? | Check availability; nothing recommended here needs iOS 27 |

### 10.2 Not verified

- Anything about how the app looks on a device. Row heights, x positions and contrast figures are
  arithmetic.
- The 874 pt height; which phones have a 16 pt margin; the default insets of a plain `List`; the
  height of a segmented control; the heights of the bars used for the "rows on screen" estimates.
- How iOS 27 draws a navigation subtitle under a large title, a search field in a sheet, swipe
  action buttons, and the `ControlGroup` row at the top of a context menu.
- `message.badge` as a symbol name.
- Whether a member can write in a new Solo before the other person joins, and whether that message
  reaches them later.
- Whether pins and tags reach the member's other devices (`[code]` section 5).
- Whether a silenced conversation counts toward the tab badge.
- Whether a Time Sensitive level set on the phone is honoured for an iCloud push; how long an
  action gets to run; what iOS shows with previews off and no category.
- Messages' and WhatsApp's own measurements (`[pat]`).
- iPhone Duo and landscape are not covered.

### 10.3 Web pages read for this spec

- https://developer.apple.com/tutorials/data/design/human-interface-guidelines/typography.json (from character 30,000: the AX1, AX3, AX5 and xxxLarge tables)
- https://developer.apple.com/tutorials/data/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:).json
- https://developer.apple.com/tutorials/data/documentation/swiftui/badgeprominence.json
- https://developer.apple.com/tutorials/data/documentation/swiftui/controlgroupstyle/compactmenu.json
- https://developer.apple.com/tutorials/data/documentation/swiftui/controlgroupstyle/palette.json
- https://developer.apple.com/tutorials/data/documentation/swiftui/view/matchedtransitionsource(id:in:).json
- https://developer.apple.com/tutorials/data/documentation/swiftui/pinnedscrollableviews.json
- https://developer.apple.com/tutorials/data/documentation/swiftui/view/navigationlinkindicatorvisibility(_:).json
- https://developer.apple.com/tutorials/data/documentation/swiftui/view/swipeactions(edge:allowsfullswipe:content:).json

Every other web fact is cited through the research file that read it, with its URL where the claim
is specific. The colour arithmetic is in
`/private/tmp/claude-501/-Users-grifftatarsky-projects-outpost/f313c3e3-558d-46ba-9bcc-c43ae72ae298/scratchpad/design/work/ui_colours.py`.

<!-- COPY END 7c2c60e0 -->
