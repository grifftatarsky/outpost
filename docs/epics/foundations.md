---
title: Foundations
layout: default
parent: Roadmap
nav_order: 8
---

# Groundwork

{: .no_toc }

Accessibility, the test seam, an outside review of the crypto, and getting it shipped.

1. TOC
{:toc}

## Where this stands

Cross-cutting work: the rules that hold everywhere, the tests that hold them, and what has to be true
before anybody outside sees a build.

Every ticket on this page, with its status and what was actually observed, is on the
[Roadmap](../roadmap.md#where-everything-stands).

## Tickets

<details markdown="1" id="the-contrast-finding-and-the-test-that-missed-it">
<summary><b>The contrast finding, and the test that missed it</b> — Complete (tested)</summary>

**Story.** As anybody reading text on a colored button, I want it legible at every accent, so that
the theme is a choice rather than a hazard.

**Acceptance criteria**

- **Done.** One derived token, `accentFillSwatch`, used by filled buttons and sent bubbles, darkening the
  accent in small steps until white clears 4.6:1, a margin over the 4.5 the audit asserts.
- **Done.** The default accent is verdigris, the one the boards are drawn on.
- **Done.** Field borders join the audit as interface edges at 3:1 (ruling 9).
- **Done.** The destructive fill is `#D1382F` at 4.86:1, not the system red at 3.41.

**Testing**

- Suite: white on every filled surface clears 4.5:1 at all seven accents in both appearances, the
  test that would have caught this; a filled surface is still recognizably the accent, without which
  "derive until it passes" is satisfied by black; the border test.

**Design.** Rulings 13, 9 and the appendix.

<details markdown="1">
<summary>Record — what was actually wrong, and the measurements</summary>

**Done 2026-08-18.** Sent bubbles were already correct. Filled buttons were not: they used the
accent's own value and moved the text instead, picking whichever of black and white contrasted
better, which passes an audit and puts black text on a colored button in dark mode. And the audit
tested neither: the white-on-fill pair was never a test, so the bubble's derivation was unpinned.

Measured, white against the fill:

| Accent | Dark base | Dark fill | Light base | Light fill |
|---|---|---|---|---|
| cobalt | 3.88 | **4.64** | 5.35 | 5.35 |
| verdigris | 2.94 | **4.92** | 4.38 | **4.79** |
| signal amber | 2.50 | **4.78** | 4.13 | **4.95** |
| oxblood | 4.33 | **4.72** | 6.70 | 6.70 |
| aubergine | 3.36 | **4.96** | 6.28 | 6.28 |
| hangar slate | 3.04 | **5.01** | 5.62 | 5.62 |
| olive drab | 2.53 | **4.84** | 4.47 | **4.84** |

Every dark base failed; every fill passes. Four light accents already cleared it and are left
untouched. Verdigris on its own is a worse pairing than the cobalt it replaced, second-worst of the
seven; it is only safe because filled surfaces derive their own value.

</details>

</details>

<details markdown="1" id="tab-roots-on-system-navigation-bars">
<summary><b>Tab roots on system navigation bars</b> — Complete (tested)</summary>

**Story.** As anybody using the app, I want the top of each screen to behave the way the platform's
does, so that large titles, search placement and accessibility work without anybody maintaining
them.

**Acceptance criteria**

- **Done.** Rooms, Outposts and You use `.navigationTitle` and `.toolbar`; the three hand-drawn headers
  are deleted.
- **Changed.** Titles. Rooms and Outposts carry `.toolbarTitleDisplayMode(.inline)`. **You carries no title at
  all** — an empty `navigationTitle`, inline display mode, and the `AnimatedMark` drawn at the top of
  its content where a title would be. This criterion read "You is large" from the design audit of
  2026-09-05 until the code was read on 2026-09-14; it was never true of the build. Ruled a
  deliberate departure that day, with what it costs written down in
  [Decisions](../decisions.md#the-mark-stands-where-yous-title-would-be-and-that-is-a-departure).
- **Done.** The sync line is its own row directly beneath the bar, a live region announcing once, absent
  from the accessibility tree when there is nothing to report.
- **Done.** The washed bars are audited as their own surfaces, at the specified 14%, in both states, at all
  seven accents.

**Testing**

- Suite: the bar audit, verified to fail at an unsafe opacity (45% drops toolbar glyphs to 2.50:1);
  a second test pins the wash as visible, because a tint nobody can see is a switch that lies.

**Design.** Rulings 11 and 2; board 85.

<details markdown="1">
<summary>Record — what the ruling reversed</summary>

**Done 2026-08-18.** Three tab roots drew their own headers, a title and its actions on one row. The
ruling calls this the most expensive divergence in the table: large titles and their collapse on
scroll, the toolbar's own Dynamic Type and accessibility behavior, search field placement, and
whatever the OS adds next, traded away on three platforms and maintained by one person. The stated
reason was consistency across the three roots; a system bar gives that by construction. The tag
filter and the people rail became their own insets under the bar for the same reason. The bar had
been a `Color`, which cannot be measured; it is a `Swatch` composited over the ground now.

</details>

</details>

<details markdown="1" id="haptics-bounded-to-three-cues">
<summary><b>Haptics, bounded to three cues</b> — Complete (tested)</summary>

**Story.** As anybody holding the phone, I want the app to buzz only when it is telling me
something, so that a haptic means something rather than being texture.

**Acceptance criteria**

- **Done.** Exactly three cues, each with a visible partner so the app stays usable with haptics off:
  `commit` (a light impact for sending, joining, leaving, removing), `refusal` (a warning
  notification, paired with the message saying why), `failure` (an error notification, paired with
  the inline failure).
- **Done.** Arrival of a message is not a cue; announcing an arrival is the notification system's job.

**Testing**

- Suite: `vocabularyIsBounded` asserts there are exactly three. A fourth needs a board, so that test
  failing is the intended way to discover one was added without going back for the drawing.

**Design.** Ruling 12.

<details markdown="1">
<summary>Record — the six that went</summary>

`messageArrived`, `reactionAdded`, `reactionRemoved`, `selectionChanged`, and the split between
admitting and refusing a join. Each was defensible alone; together they were an app that vibrates
while you use it, and every one failed the rule by carrying no visible partner. `joinRefused` looks
like a refusal and is not: refusing somebody is the member deciding, and it succeeds, so it is a
commit.

</details>

</details>

<details markdown="1" id="asking-for-photos-honestly">
<summary><b>Asking for photos honestly</b> — Complete (tested)</summary>

**Story.** As a member about to send a photo, I want to know what will be asked of me, so that the
picker is not a surprise.

**Acceptance criteria**

- **Done.** A sheet on the first tap of the composer's plus, saying nothing is asked at all: the system
  picker shows the library to the member and hands over only what they choose, and there is no
  setting to grant.
- **Done.** The welcome tour names the two things the app will ask for, each when it comes up and never at
  launch, and says there is no camera.

**Testing**

- Device: the explainer, then the system picker with its own "Private Access to Photos" banner,
  2026-09-04. There is no API that narrows the system's library prompt to limited-only; the app
  simply never triggers that prompt.

**Detail.** [Before a build goes out](foundations.md#permissions-explained-before-they-are-asked).

</details>

<details markdown="1" id="trust-and-safety-in-the-app">
<summary><b>Trust and safety in the app</b> — Complete (operational proof owed)</summary>

**Story.** As a reviewer or a member, I want to find report, block, the filter, contact and the EULA
in under thirty seconds, so that Guideline 1.2 is met in fact and not in a note.

**Acceptance criteria**

- **Done.** Report and block on any message's menu; the filter switch, the deny-list switch, blocked people
  and *Report a problem* under You › Privacy & Safety; the EULA is TestFlight's until the store copy
  exists.
- **Done.** Reporting never transmits media, by construction and by test.
- **Done.** Blocking takes effect on current and future messages with no network call.
- **Done.** With the analyzer disabled, media renders normally and the app does not claim it was screened.
- **Done.** No new outbound network destination versus the pre-media build: photos travel in the same
  container and zone as packets; reports go through the member's own mail client.
- **Done.** The mandatory-reporting obligations written down, with the App Review reply drafted.
- **Partly.** Operational. Done: the abuse, support and info mailboxes exist and receive mail (2026-09-17); the
  privacy policy and terms carry the report-retention sections (2026-09-15); the deny list's date was
  corrected rather than changed. Open: the acknowledgment template, the encrypted vault for report
  records, and refusing attachments at `abuse@`.

**Testing**

- Suite: `BlockingTests`, the report composition, `MediaLoaderTests`.
- Two accounts: report, block and the Safety section seen 2026-09-04. The network claim is by
  reading the code, not measured with a proxy.

**Detail.** [Trust and safety](../trust-and-safety.md) ·
[Before a build goes out](foundations.md#operational).

</details>

<details markdown="1" id="an-accessibility-pass">
<summary><b>An accessibility pass</b> — Complete (hardware proof owed)</summary>

**Story.** As somebody using VoiceOver, Dynamic Type or Reduce Motion, I want the app to work, so
that it is usable rather than nominally accessible.

**Acceptance criteria**

- **Done.** Hit targets are 44pt by a tappable inset everywhere they were not: swatches 40/44, reaction
  buttons 38/44, chips 30/44. Glyph-only buttons say what they do; decorative marks are hidden.
- **Done.** Usable at the largest Dynamic Type size on the screens checked: the room name no longer
  truncates, the identity header stacks, settings rows drop their value beneath the title.
- **Done.** **The Dynamic Type pass, 2026-09-16.** Alpha at `accessibility-extra-extra-extra-large`, walked
  screen by screen, beside a sweep of every fixed-size font in `CarpenterUI`. What already scaled:
  room rows, which stack; bubbles and author names; room notices; the composer; empty states, which
  scroll; settings rows and page headers; *Join a room*. What did not, and now does:
  - **Delivery marks and the not-sent circle** were a fixed 10pt beside a time that grew to several
    times that. `@ScaledMetric(relativeTo: .caption2)`, so they grow with the time they sit beside;
    the not-sent circle keeps its 44pt hit area and a layout the size of the glyph.
  - **Identity fingerprints** — You, your identity page, a person's page, an Outpost header — were
    fixed 13 and 15pt monospaced. Now `footnote` and `subheadline`, monospaced.
  - **Verification characters** shrank to fit two lines (down to 40%) at every size. At an
    accessibility size they now take as many lines as they need, at full size.
  - **Emoji** in the picker and both reaction lists, and the Outpost's add-a-reaction control, scale
    with body text; the picker's cells stop at twice their size so a row still holds more than two.

  What does not scale, and why:
  - **Navigation titles, *Done* and *Cancel*, and the tab bar** — drawn by iOS, measured the same size
    at the largest setting. Apple's own answer for bar items is the Large Content Viewer, and iOS
    provides it: pressing and holding a toolbar icon at that size showed it. For an icon-only
    **button** it showed the icon alone, so seven of them now name themselves with
    `accessibilityShowsLargeContentViewer` — *How this works* was seen reading its name. For an
    icon-only **menu** (compose, list options, room settings, More) the name never appeared, with the
    modifier on the menu or on its label, so it was taken back off those.
  - **Avatar initials** sit in a fixed disc, with the name beside them in text that scales; the
    avatar is hidden from VoiceOver. Recorded as a departure in
    [Decisions](../decisions.md#what-stays-a-fixed-size-when-text-grows).
  - **The tapback bar and the reaction chips on a bubble's corner** are laid out in fixed geometry
    over the bubble; also recorded there.

  **Apple's audit is not the measure for this, and the numbers say why.** Re-run after the pass on the
  same seven screens: 29 *partially unsupported* and 3 *unsupported*, against 28 and 3 before. It
  flags text that visibly scales — *No solos yet*, its explanation, *Send a Solo*, *I have an invite*,
  room titles, all large at the largest size in the rig's screenshots — and it named nothing on the You
  tab while the fingerprint there was a fixed 13pt. It also names avatar initials that are hidden from
  VoiceOver. Apple does not document what the check measures. The screenshots are the evidence here.
- **Done.** The contrast audit covers every palette and both appearances for filled surfaces, and the two
  surfaces it had never measured.
- **Done.** Haptics respect the system settings and the in-app switch.
- **Partly.** Every control labeled by what it does: **done and measured, 2026-09-16.** Every glyph-only
  control in the tree — 22 of them — already carries an `accessibilityLabel`; the first audit said
  none did, because it stopped at the closing brace of the `Button` while the labels sit on the
  modifier chain after it. Every element that takes `children: .ignore` — five — supplies a label,
  and each label function was read to the bottom for a branch that could come back empty. **One
  could**, and it was the one that mattered: see below. *Navigable* is the half still owed — reading
  order, grouping and rotor behavior need VoiceOver actually running — which the **simulator does**
  do, once the daemon is kicked. [Testing](../testing.md) has the two commands.
- **Partly.** Reduce Motion: **verified at every call site, 2026-09-16**, which is a stronger check than the
  lint makes. `Scripts/lint-branding.sh` excuses a whole file for one mention of `reduceMotion`; this
  read every `.animation`, `.transition`, `matchedGeometryEffect` and `repeatForever` individually.
  Each is either driven by an `.animation(reduceMotion ? nil : …)` or is a `.transition(.opacity)`,
  the cross-fade Reduce Motion asks motion to be replaced *with*. Eight looked unguarded at a glance
  and all eight were fine. Still owed: the same walk on a device, for the surfaces the system draws
  rather than this app.
- **Done.** Color is never the only carrier of state, on both surfaces the criterion names.
  **The delivery marks** carry it three ways: shape (`paperplane` against `paperplane.fill`, `eye`
  against `eye.fill`, and distinct `eye.slash` and `person.slash`), opacity, and a spoken sentence
  per state — tested to be different from every other state's. Color only ever reinforces.
  **Unread** is a dot that is present or absent, which is not a color distinction at all, and it
  carries an `Unread` label that is hidden when there is nothing to say.

**Apple's own audit, run 2026-09-16.** `AccessibilityAuditTests` calls
`XCUIApplication.performAccessibilityAudit()` on the rooms list, every tab and a conversation. It
could not run for a day because the app never went idle — that turned out to be a render loop, see
[Decisions](../decisions.md) — and once fixed it found **24 issues in six categories**. The summary
line reports three, because it collapses every issue in a test into one; the element list below is
out of the result bundle's activity tree.

| Issue | Count | Elements |
|---|---|---|
| Dynamic Type partially unsupported | 12 | the *Rooms*, *Solos* and *Outposts* labels; *Send a Solo*, *I have an invite*; *Kitchen*, *1 member*, *Griff started Kitchen*, *User 403 confirmed the invitation*, *Yesterday 12:39 AM*; *No solos yet* and its explanation |
| Contrast failed | 5 | *Yesterday* (a room row's time), *Behavior*, *Verdigris*, *I have an invite*, the avatar initial *K* |
| Contrast nearly passed | 3 | the Solos explanation, the Outposts empty state, the avatar initial *G* |
| Hit area too small | 2 | the composer's **plus**; the delivery marks |
| Dynamic Type unsupported | 1 | the avatar initial *K* |
| Text clipped | 1 | the Solos explanation |

**Read before fixing, because not all of these are defects of the same kind.**

- **Tab-bar labels staying small is documented; nothing else in that list is.** Corrected
  2026-09-16 after Griff asked for the documentation. Apple's `UILargeContentViewerInteraction`
  reference — the UIKit class docs, not the HIG tab-bars page, which says nothing about it — reads:
  "Rely on the large content viewer only in situations where items must remain small due to
  unavoidable design constraints. For example, buttons in a tab bar remain small to leave more room
  for the main app content." It also says: "Don't use the large content viewer as a replacement for
  proper Dynamic Type support." So the **tab labels** are covered; the navigation title, the row
  text and the buttons are **not**, and an earlier version of this entry lumped them together. Not
  yet established either way: whether SwiftUI's `TabView` wires up the large content viewer on its
  own. The docs do not say.
- **Contrast is a real finding and it disagrees with the existing contrast audit.** That audit is
  sixteen tests over the palette's *tokens*, and passes. This one measures *rendered pixels* — a
  token drawn at some opacity, over some ground, at some size — and fails five. Same lesson as the
  render-cost guard that counted folds: a check on the wrong quantity reads as coverage.
- **The avatar initial not scaling** may be deliberate — it sits in a fixed-size disc — and if so
  it is a departure to record, not a bug.
- **The two hit areas are fixed, 2026-09-16, and a re-run of the audit confirms both are gone.**
  They were not the same kind of problem. The composer's **plus** was a real control at 38pt; it now
  takes `tappable()` after its glass, so it still draws at 38 and is hit at 44 — the same "38/44"
  this ticket already records for reaction buttons. The **delivery marks** were never a control:
  they have no gesture. The audit's own description said "too small for user to interact", and
  Apple's `accessibilityRespondsToUserInteraction` docs say why — when unset, interactivity is
  inferred from "the presence of gestures on the element **or containing views**", and the bubble
  has a long press. So Switch Control, Voice Control and Full Keyboard Access were offering a status
  glyph as something to press. Declaring it non-interactive is the truthful fix and moves no pixel;
  enlarging it would have put ~30pt of blank space under every run of messages.
- **Contrast, looked at rather than counted: eight distinct, and two are not color problems.** Three
  fail outright — a room row's time, a room's avatar initial, and *I have an invite*. Three nearly
  pass. And *Verdigris* and *Behavior* were rows scrolled **underneath the floating tab bar** when
  the audit looked, with the glass washing them out. Screenshots went to Griff before any color
  moves.

**Changing a color for contrast changes how the app looks**, so those five are Griff's to see before
they move.

**The audit extended, 2026-09-16 evening.** `AccessibilityAuditTests` now launches quieted and pinned
to verdigris, and covers four more surfaces: *Appearance* and *Color*, *Privacy & Safety*, *Join a
room*, and a room's *Who this is waiting on* and *Notifications* sheets. Its issue handler returns
`false`, so every issue still fails the test; the element each one names was read from the result
bundle's element screenshots, which this Xcode crops to the element.

| Surface | Flagged | What it is |
|---|---|---|
| Join a room | Contrast failed | the **disabled** *Read the invite* — measured **1.70:1** label on fill |
| Privacy & Safety | Contrast failed | a footer paragraph scrolled under the floating tab bar |
| Privacy & Safety | Text clipped | *Do Not Disturb*, a settings row's one-line value |
| Appearance | Contrast nearly passed | the *User Avatars* footer, the system's footer gray |
| Color | Text clipped | *hydrogen, obviously*, the light and dark sample bubbles |
| Waiting on | Contrast nearly passed | its footer, the system's footer gray |
| Conversation | Contrast failed | a 💜 reaction on its accent disc |
| every screen | Dynamic Type partially unsupported | as before |

**What each is, before anything moves.**

- **The disabled button is a real disagreement with the record, and not with WCAG.** The record below
  says a disabled button's "label still clears the floor against that fill". What ships is the
  system's `.glassProminent` in its disabled state, and its label measures 1.70:1. WCAG 2.2, read
  today: text "that are part of an inactive user interface component … have no contrast
  requirement". So the build is inside the standard and outside the record. Repainting a system
  control's disabled state is a departure from native-first; correcting the record is not. **Ruled
  2026-09-16: keep Apple's look**, and the record is corrected.
- **Footers under the tab bar and the system's footer gray** are the same two kinds found in the first
  run: glass over content, and a color the app does not choose.
- **A reaction emoji on its disc** is a picture, which the contrast check was not written for.
- **The settings row's value** is one line on purpose — CLAUDE.md: "one line, a short value". Changed
  anyway, 2026-09-16: at an accessibility text size the row already stacks, so the value may now wrap
  there. The audit still flags it because it also checks the larger sizes below that range, where the
  rule holds.
- **The sample bubbles** have no line limit and no fixed height in `AppearanceSample`; why they are
  flagged is not established.

Nothing else on the four new surfaces was flagged: no hit region, no missing or useless description,
no trait. Of what was built today, the waiting list and the room sheet's new section were audited and
added nothing but the system footer gray; *Join a room* was audited with scanning **off** on the
clone, so the scanning question and the Scan button were not; and the not-sent mark and its sheet
were not on any audited screen, because no audited room holds a stuck message.

**The defect this pass found.** `DeliveryMarkView` draws as one element with `children: .ignore`,
which throws away the glyphs, the time **and the *Edited* mark**, replacing them with a single label
— and that label was `Text(verbatim: "")` for `.pending`. Since `isVisible` is `self != .pending`,
the view appears in that state for exactly one reason: **somebody else edited the message**. Its only
job in that case was to say *Edited*, and what VoiceOver got was an empty string. In every other
state an edit was never mentioned either, so a message the member had edited sounded identical to one
they had not. Fixed with `DeliveryMarkSpeaksTests`, five tests, one of which pins the shape of the
original defect so that wiring the old label back up fails loudly.

**Testing**

- Suite: the contrast and symbol-name tests.
- Device: Dynamic Type at `accessibility-extra-extra-extra-large`, 2026-08-19.
- Suite: `DeliveryMarkSpeaksTests`, 2026-09-16 — every visible delivery state says something, no two
  say the same thing, and an edit is spoken in all of them.
- **The VoiceOver walk-through is what is left, and it waits for TestFlight** — Griff ruled
  2026-09-17 that the app uses system components everywhere and the walk is done on a phone from the
  first TestFlight build ([Decisions](../decisions.md#the-voiceover-walk-waits-for-testflight)).
  Measured 2026-09-17: on the
  rig VoiceOver runs, draws its cursor and prints what it says in the Caption Panel, and the first
  thing it said on each screen tried was right — *Outpost, Rooms, Back button*; *purple heart,
  Button*; *Pin, Button*. It cannot be stepped from here without taking the Mac's focus: injected
  touches become long presses, swipes do nothing, and the keyboard only reaches it with DeviceHub
  frontmost. [Testing](../testing.md#accessibility) has the commands.
  `VoiceOverWalkTests` is a label lint over the rendered tree — it was described as reading
  VoiceOver's stops in order, and it does not — and it finds nothing of this app's unlabelled.

  **The walk, on a phone** (Settings ▸ Accessibility ▸ VoiceOver), one pass per tab: swipe right
  through every stop and listen for anything read twice, read as a fragment, or skipped; check that a
  room row reads as one stop with its name, last message and time; open the rotor on a conversation
  and step by Headings and Buttons; and check the orange not-sent circle, the Scan button, the
  waiting list and the compare-codes page, which the rig has not heard.

**Design.** Board 87 (bubbles, buttons, fields) for the three rulings the set never drew; boards 91
and 92 for light mode as values; Component Blockers carries the requirement for every board plus the
four rules that hold everywhere.

<details markdown="1">
<summary>Record — the values that hold everywhere</summary>

Bubble radius clamps to the bubble's own height: 9pt one line, 14pt two, 18–20pt beyond. A disabled
button is the system's own disabled appearance, and its label is **not** held to the floor —
corrected 2026-09-16 after Apple's audit measured the disabled *Read the invite* at 1.70:1; see
[Decisions](../decisions.md#a-disabled-button-keeps-the-systems-look). (This used to say a disabled button was a
neutral fill whose label cleared the floor; that was the board, not the build.) A field has an explicit fill and border, `1pt rgba(84,84,88,.9)` on
`rgba(120,120,128,.14)`, focused `1.5pt` accent. A field's border was being compared to the page
behind it rather than to the fill it encloses, measured properly at 2.77:1 against a required 3:1;
it is Apple's own `systemGray` now. Delivery marks are not controls and have no tap area at all.

</details>

</details>

<details markdown="1" id="a-cloudkit-integration-target">
<summary><b>A CloudKit integration target</b> — Complete (tested)</summary>

**Story.** As somebody changing the sync code, I want a target that fails when I break CloudKit, so
that the one seam a green suite has been wrong about more than once is covered by something that
touches it.

### Why it can be small

The seam is already right, and that is most of the work. `Mailbox` is a protocol, `PacketWire` maps a
packet to named fields **above every transport**, and `CloudKitMailbox` is the only thing that knows
what a `CKRecord` is. So this target needs no app, no session and no UI — it drives the mailbox
directly.

### Shape

A separate test target in the workspace beside `CarpenterTests`, **which `swift test` never runs and
CI never runs**, because it needs an account, a container and entitlements. Runnable from Xcode and
from one `make` target. Its absence from `swift test` is the point rather than an apology, and the
target's own header says so.

**A dedicated container, never the production one**, and the target erases its own zone in `setUp`.
A test that leaves records behind is eventually the reason a real member's device sees something
impossible.

**One Apple Account, deliberately.** An account cannot participate in its own share, so share
acceptance is not reachable here and this target must not imply it covers it — the mailbox is a zone
in the writer's own database, so everything below works single-account. The share path stays the
rig's, and the rig doc says which.

**Acceptance criteria**

- **Done.** A packet survives the round trip byte-identical: `PacketWire.fields(of:)` → `CKRecord` →
  `packet(from:)` — `aPacketComesBackExactly`, against a live account, 2026-09-13. **This is the test
  that would have caught `grants` being silently stripped**, which is the defect `PacketWire` exists
  because of, and the grants are compared as a set because the wire promises no order for that list.
- **Done.** Every field the mapping emits appears in `CloudKitMailbox.scannedFields`, checked against the
  mapping rather than against a second list — `ScannedFieldsTests`, 2026-09-14, and proven to fail by
  dropping `PacketWire.grantValues`. The `desiredKeys` trap, mechanised: a field left off that list is
  not an error anywhere, it is a record that reads as empty. The attachment blob is asserted *absent*,
  because the routing read is the one place it must not be dragged in.
- **Done.** A record written a moment ago comes back from the zone's **change feed** —
  `aPacketIsReadableImmediately`. It does not come back from the query index, which is eventually
  consistent and cost a week once; the test pins which one the code uses.
- **Done.** `acknowledge` shrinks `outstanding`, and a fully acknowledged packet stops being fetched —
  `acknowledgingStopsTheOffer`, and `anAttachmentSurvivesTheWire` for the media record.
- **Done.** A record over the size limit fails the way the code expects rather than the way it hopes —
  `aPacketOverTheCeilingIsRefused`, and `aPacketAtTheBudgetIsAccepted` for the other side of it.
  **Asking the real server changed the answer**: CloudKit accepted one, two, four, eight and sixteen
  megabytes without a word, so `MailboxRules.recordByteCeiling` was never the server's limit — it is
  the app's own, and only the fake was enforcing it. `CloudKitMailbox.put` weighs the record now, so
  a packet the fake refuses is a packet the real mailbox refuses. A photo is not subject to it and a
  live test says so: the blob is a `CKAsset`, and one at 1.5MB goes through.
- **Done.** The target is documented as not runnable in CI rather than quietly skipped, and named in
  `docs/testing.md` with the command that runs it — including
  `-parallel-testing-enabled NO`, because a parallel run clones the simulator and the clone carries no
  iCloud account.

**Testing.** Itself. **Detail.** Unblocks the third criterion of
[A test seam that cannot lie](#a-test-seam-that-cannot-lie), which is where this was parked.

</details>

<details markdown="1" id="a-test-seam-that-cannot-lie">
<summary><b>A test seam that cannot lie</b> — Complete (tested)</summary>

**Story.** As somebody changing the sync code, I want the tests to fail when I break CloudKit, so
that a green suite means something.

**Acceptance criteria**

- **Done.** The in-memory mailbox goes through the same wire mapping as the real transport and counts every
  server operation, so a test that asserts "writes nothing" counts every kind.
- **Done.** The account check's error handling is a pure function with tests; the joining handshake is
  tested across both halves. Both written because a real defect had hidden exactly there.
- **Done.** A CloudKit integration target exercising put, fetch, acknowledge and the share against a real
  account, documented as not runnable in CI rather than pretending.
- **Done.** Every remaining seam a fake that is harder than the real thing where the real thing has an
  opinion. 2026-09-17, audited seam by seam in [Testing](../testing.md#the-fakes-are-held-to-the-real-seams):
  the one still easier was `FakeMediaScreen`, which judged a picture with screening off and judged
  bytes that were not a picture at all, where Apple's analyzer refuses both. It refuses them now,
  and a clip that is not on disk.
- **Done.** Concurrency across the app and the extension covered; the cross-process lock is tested and was
  verified to fail without it, and that property is kept. 2026-09-17, and it found a real defect:
  **the extension's read-only round saved its own older copy of the state file over the app's**, so
  a setting changed while a banner was being prepared was undone, and a room deletion was no longer
  recorded as one. The extension now opens the container
  through read-only views of the log, the state file and the keychain, writes nothing, and looks at
  what its own round collected before it reloads. `AppAndExtensionTests`, five. The log's new rewrite
  is held to the same lock as appends: `removalDuringAppendsLosesNothing` loses appended entries
  without it, and passed ten runs of ten with it.

**Testing**

- Suite: the regression guards below.

<details markdown="1">
<summary>Record — the regression guards worth knowing</summary>

Each caught a real defect the rest of the suite did not. Do not delete them to make a refactor
easier. **Concurrent storage**, verified to lose 118 of 200 entries without the cross-process lock.
**Send race**, a message typed mid-sync and the bell for it, both silently lost. **Stranded
packets**, a message written before an address rotates. **Packet wire round-trip**, whole-value
equality, because field-by-field assertions are what let epoch grants slip through. **Push channel
table**, exactly one channel visible, every channel scoped. **Persisted state**,
`decodingPersistedStateKeepsEveryFieldItWasGiven`, which fails if a field the encoder writes is not
read back. **Scan keys**, the record types a zone scan is asked to read, after the offer's field was
left off the list and the rendezvous read every offer as empty for an afternoon.

This project's characteristic defect is code that passes every test and does not work over
CloudKit. It has happened at least five times.

</details>

</details>

<details markdown="1" id="before-testflight">
<summary><b>Before TestFlight</b> — Incomplete</summary>

**Story.** As the person shipping this, I want every sentence in the build to be true and every claim
proven, so that the first outside tester is not the first audit.

**Acceptance criteria**

- **Done.** The language pass over every member-facing screen, checked against the build, 2026-09-05.
- **Done.** Permissions explained before they are asked; none asked at cold launch.
- **Done.** *Erase everything* in every build, with its facts checked against the wipe.
- **Done.** The debug leaves: the Debug section, the launch argument, the demo rooms and *Blur every
  photo* said in the code to be DEBUG-only or removed.
- **Not done.** The hardware-only proofs: the trimmer, the Keychain hand-off, a positive screening verdict, and
  everything downstream of a push (Griff saw one banner arrive on a phone on 2026-09-09). The
  attachment record leaving the outbox was proved against a real account on 2026-09-15.
- **Partly.** The operational list. **Done.** The policy sections are written — the privacy policy's retention
  section and the terms' short form, 2026-09-15. **Done.** The deny list's date was **corrected rather than
  done**: the item asked for the build date and the copy says *last changed*, so a build date would
  claim a change that never happened. **Done.** The mailboxes exist (2026-09-17). **Not done.** The encrypted vault still
  has to exist, and it is not code.
- **Partly.** App Store metadata and the age-suitability page. The copy is drafted and current in
  [app-store.md](../app-store.md) and the site's page exists; entering it into App Store Connect
  needs Griff's account.

**Testing.** The checklist itself: [Before TestFlight](../pre-testflight.md).

<details markdown="1">
<summary>Record — the gates before any release</summary>

| Gate | How |
|---|---|
| Package suite green | `swift test` in `Packages/Carpenter` |
| Three targets build | iOS, macOS, and the notification service extension |
| No debug tools in a release build | Build Release; You › Debug is absent |
| VoiceOver reaches every control | One pass per tab, largest Dynamic Type |
| Contrast holds | Audit tests pass for every accent, both appearances |
| Claims check out | Every present-tense sentence in the listing has code behind it |

</details>

</details>

<details markdown="1" id="the-help-the-welcome-tour-promises">
<summary><b>The help the welcome tour promises</b> — Complete (tested)</summary>

**Story.** As somebody who has just finished the welcome tour, I want the `?` it told me about to
actually be there, so that I can find out how this works without hunting.

**Acceptance criteria**

- **Done.** A `?` in the navigation bar of each of the three tab roots, opening the how-it-works page — the
  same page onboarding already shows, so there is one copy of it.
- **Done.** It follows the *Help on every screen* switch, which until 2026-09-13 wrote a preference nothing
  read: a member could turn it on, be told help was on every screen, and find none.
- **Done.** The switch reaches the roots through one environment value and one modifier, so a fourth tab
  cannot arrive without it and quietly reintroduce the gap.

**Testing.** Not covered by the suite — it is a toolbar item behind a preference, which is the shape
the UI tests exist for and those are not run. Not seen on the rig either. **Design.**
[Design](../design.md) records the product decision that pointed here.

</details>

<details markdown="1" id="light-mode-from-rules-rather-than-drawings">
<summary><b>Light mode, from rules rather than drawings</b> — Complete (tested)</summary>

**Story.** As somebody building a screen, I want light mode to be checkable, so that the second
appearance is not inferred one screen at a time.

**Acceptance criteria**

**Rewritten 2026-09-14.** The criteria below used to ask for the values from board 91 to exist as
tokens and for board 92 to be built as a proving screen. Griff ruled that day that the boards are no
longer the reference, and reading the code the same day found the substance already done: every
swatch in `Palette` carries a real light value, nothing sets `preferredColorScheme` outside a
`#Preview`, and `ContrastAuditTests` holds sixteen tests — among them *Every text weight is readable
on every surface it is drawn on* and *White clears AA on every accent, **in both appearances***.

What is left is not building; it is looking.

- **Done.** The palette answers both appearances, and the contrast audit covers both rather than only dark.
- **Done.** **The sweep**, done 2026-09-15 and recorded on
  [Before a build goes out](foundations.md#dark-and-light-on-every-surface). It found one real defect
  — a context menu's preview is hosted outside the app's hierarchy, so `\.palette` fell back to its
  declared default, which is dark, and the preview drew dark inside a light app. Fixed, and a lint
  rule now catches the next one. Everything else follows the appearance: sheets,
  the notification surfaces Griff flagged on 2026-09-14, menus, alerts, confirmation dialogs and the
  keyboard's accessory. These are the surfaces the app does not paint, so a test cannot reach them.
  Tracked on [Before a build goes out](foundations.md#dark-and-light-on-every-surface).
- **Done.** Where a screen's light treatment was inferred during implementation, it is checked against the
  rules and any difference recorded. 2026-09-17: every color a view picks for itself was read, and
  every pairing the audit did not already hold was measured with the app's own contrast code, in both
  appearances, with Increase Contrast on and off, for all eight accents. It found the destructive red
  failing as text in dark everywhere and on the light background; Increase Contrast turning cards and
  chips into slabs that gray, accent and red text failed on; unlit delivery marks under the 3:1 a
  graphic needs; four filled buttons carrying white on the plain accent; accent words on cards; the
  anonymous face in white on the accent; and white words on regular Liquid Glass over photos, which
  goes near-white in light. All fixed, and what stays is written down —
  [Decisions](../decisions.md#a-color-is-measured-on-every-ground-it-is-drawn-on-in-both-appearances).
  Seen on the rig in both appearances: the rooms list, a room's context menu, a conversation with lit
  and unlit marks, and You. The glass over a photo and the in-conversation cards were not on the rig's
  data and have not been seen.

**Testing.** `ContrastAuditTests` gained seven: the destructive color on every ground and card; a
bordered destructive label on its capsule; primary, secondary, tertiary and neutral text on a card and
on both chips, and the accent label on a card, with Increase Contrast on and off; Increase Contrast
raising a fill by iOS's own 0.08; an unlit mark clearing 3:1 and staying lighter than a lit one; and
white words over a white photo through the dimming. Each rule was broken once to see its test fail. **Design.** Boards 91 and 92 define light mode as values rather than a
second set of drawings: four surfaces, the ink and edge steps, the accent's light measurement, every
swatch's value as text beside it. Boards 13 and 14.

</details>

<details markdown="1" id="transitions">
<summary><b>Transitions</b> — Complete (tested)</summary>

**Story.** As a member, I want the app to move coherently between screens, so that "almost no motion"
reads as a position rather than as unfinished.

**Acceptance criteria**

**Answered 2026-09-14.** Ruled: sheet presentation, tab switching and navigation push use **the
system's own motion**, and that is the deliberate answer rather than an omission. The app does not
invent a transition for what the platform already animates — the *Native first* rule, and the same
reasoning that puts glass in a `GlassEffectContainer`: what the system animates stays free across OS
releases instead of becoming a migration. Reduce Motion is the system's answer too for those three,
and the lint already fails any file that animates without reading `accessibilityReduceMotion` or
declaring a cross-fade on the line.

- **Done.** Sheet presentation, tab switching and navigation push have a stated behavior, decided once and
  applied everywhere: the system's.
- **Done.** Reduce Motion has a defined answer for those three — the system's — and the lint enforces that
  anything the app animates itself reads the setting.
- **Done.** Anything deliberately still is recorded as deliberate: this entry is that record.
- **Done.** The accent retint is the one motion the app commits to and owns, and is built. Described here
  rather than pointed at, since the boards are no longer the reference: the whole hierarchy's tint
  crosses to the newly chosen accent together, as one change rather than a cascade, and it is cut to
  a cross-fade under Reduce Motion.

  **Measured 2026-09-16, and nearly true.** `AccentPickerView` sets the accent inside one
  `withAnimation(.snappy(duration: 0.2))`, marked `cross-fade only` — a color interpolation moves
  nothing, so it is the same with Reduce Motion on. A screen recording of alpha changing verdigris to
  oxblood, split into frames: the bubbles, the dark and light samples, the name and the selection
  ring all cross together over about five frames. **The system tab bar does not** — its selected
  label is fully oxblood on the first frame after the tap, about 85ms ahead of everything else,
  because the transaction does not reach what UIKit draws. Whether to keep the cross-fade with the
  tab bar leading, or drop it so every surface changes on one frame, was put to Griff: **ruled
  2026-09-16, keep the fade**, with the tab bar leading.

**Testing.** The recording above, 2026-09-16. **Design: needed.** Transitions are not drawn; this is a drawing and
decision task before it is an implementation one.

</details>

<details markdown="1" id="somebody-outside-the-project-reads-the-crypto">
<summary><b>The crypto, written down</b> — Complete (tested)</summary>

**Story.** As the person shipping this, I want an outsider to have checked how the pieces fit, so
that the central claim is not resting on one person's reasoning.

**Acceptance criteria**

- **Done.** [The crypto, written down](../crypto-brief.md), 2026-09-15, read out of the twelve files
  rather than out of `architecture.md` — which has restated a wrong comment confidently before. It
  covers every construction **twice**, in a plain register and a technical one kept deliberately
  separate, plus the threat model, exactly what the relay is handed, and what the brief does not
  cover. Confirmed on the way through that the primitives are all Apple's, that signing and
  agreement use **two independent seeds** rather than one key reused for both, and that there are
  twenty-four distinct domain strings.
- **Canceled.** A review by somebody competent and unconnected. Canceled 2026-09-14: the source will be open,
  so problems surface by being read. See
  [Decisions](../decisions.md#the-crypto-gets-a-brief-and-no-outside-reviewer).
- **Done.** [Decisions](../decisions.md#what-the-crypto-brief-found), 2026-09-15. One finding needed a
  ruling: the six-character phrase was ~29.4 bits with no commitment step, so one side of a
  man-in-the-middle could grind it offline in minutes on a desktop. Griff ruled ten characters and a
  commitment, built the same day. Three trade-offs are accepted with the reasoning written out — no
  forward secrecy, non-repudiability, and the plaintext recovery key. Of two smaller things, the
  identifier width became an invariant and `RandomSource` is parked in [Inbox](../inbox.md).
- **Done.** Both, 2026-09-15. The site already said it — `Security.tsx` §5 says the app "has not undergone
  an independent security audit" and that the composition "has been reviewed by nobody outside the
  project". **The app did not**, and now does: a *Who has checked this* section on How it works,
  placed straight after the Signal/iMessage comparisons, where a reader is actually calibrating
  trust. It says the locks are Apple's and the arrangement is not, that nobody outside the project
  has reviewed the arrangement, and that "being open to inspection is not the same as having been
  inspected, and this app will not tell you otherwise." Checked across both: no copy anywhere claims
  a review, audit or verification.

**Testing.** The brief itself is prose and has no suite. What it leans on does: `SealBindingTests`
pins the old wire layout by hand (a round-trip test cannot catch a format change, because it seals
and opens with the same build), `SiblingFeedIsSealedTests` and `LiveSiblingFeedTests` fetch a record
back off real CloudKit and assert it carries no epoch secret, and `EpochDistributionTests`,
`DeviceTrustTests` and `CanonicalBytesTests` cover the rest. The composition still has nobody outside
the project behind it, which is the ruling and not an omission.

</details>

**What would falsify the epic.** A green suite next to a broken app. That is the specific failure
this epic exists to prevent, and it has happened enough times here to be the working assumption
rather than a worry.

## Before a build goes out

The checklist that used to be its own page. Everything here is work on this build, not something a
tester does.

## Every sentence a member reads, checked against the build

Walk each screen with the build in hand and the list of what it actually does. Rewrite anything
that overstates, understates, or describes a plan.

| Screen | What to check | Status |
|---|---|---|
| Onboarding, welcome tour | Says text *and photos and clips* can be sent; says nothing about the camera. Names the permission conversations honestly (below). | **Done.** 2026-09-05: "messages, photos and clips alike" on the mailbox panel; a sixth panel, *What it will ask you*, names the two and says there is no camera. |
| How it works | The "what we can see" list includes attachments: sealed, sizes visible to the relay, nothing else. Screening described as on-device and optional. | **Done.** 2026-09-05. The notifications section, which still described a badge-only era, now describes the bell and what refusing costs. |
| You › Safety footer | Matches `ScreeningAvailability` on this device; the deny list's date is real. | **Done.** built to read the device |
| You › Privacy (read receipts) | Still true. | **Done.** re-read 2026-09-05 against `markSeen` |
| You › Devices footer | Recovery. | **Done.** 2026-09-15. All three screens already described the recovery key correctly; this row was stale. What they *did* do was understate — each said the key does not bring conversations with it, which is true of the key and leaves out the part a member wants, that the app then asks the people who were there and tells them it asked. All three now say both halves. |
| You › Storage & retention row | A row that opens nothing. Wire it to `FileMediaStore.byteCount()` or remove it. | **Done.** 2026-09-05: *Photos and clips on this device*, a number from `byteCount()` refreshed after each round, seen as 2.6 MB on the rig; the footer says nothing is deleted on its own yet. "Retention" is no longer named. |
| Room greeting, join prompt | Still true. | **Done.** re-read 2026-09-05 |
| Notification level screen | Says what a banner carries; now also carries "📷 Photo". | **Done.** 2026-09-05: the caveat says a photo or clip is announced by its caption or as "📷 Photo" / "🎬 Video", never by the picture. |
| Notifications, Messaging, Outposts | Three screens added 2026-09-11. Every sentence on them describes a push that has never been watched arriving. | **Done.** 2026-09-15. Read line by line for a promise of arrival and there is none: the copy says the app *asks* to show a banner, and that messages arrive every time the app is opened — which is the foreground loop and is true. Nothing claims a background push works. |
| Search | Added 2026-09-11. Its empty state and section headings have not been read against what it actually returns. | **Done.** 2026-09-15, and it was wrong. The four section headings were right — Conversations, Messages, Photos, Outposts — but the empty state and the field's prompt both named only conversations and Outpost posts, so search looked like it could not find a message or a photo when it finds both. Both rewritten, and the empty state now also says what search refuses: hidden, withdrawn, blocked. Each of those three is pinned by a test. |
| Recovery key screen | Says the file is the only way back and that it does not bring conversations with it. | **Done.** 2026-09-15: both halves are now true and this row was stale. `restore(fromRecoveryKey:)` reads a key back, against 24 tests, and a restore that asks nobody was proved over real CloudKit on 2026-09-14. |
| Removed / left notices | Still true. | **Done.** re-read 2026-09-05 |
| Report sheet | Addresses are the live mailboxes. | **Done.** `abuse@`, `support@` and `info@` confirmed working by Griff, 2026-09-17 |
| Erase everything sheet | Every fact on it is what `wipe()` does. Re-read after any change to `wipe()`. | **Done.** facts checked against `wipe()` 2026-09-05, one added (history on this device goes too) and one widened (photos in flight); **Done.** sheet opened and canceled on the rig 2026-09-04 (the erase itself has not been run from this sheet) |
| TestFlight license | §§9–10 match the report sheet; §4 mentions attachments. | **Done.** §4 2026-09-05 |
| App Store metadata, age suitability page | Rating 13+, review notes as in [App Store](../app-store.md#5-review-notes). | **Partly.** The copy is drafted and current — [app-store.md](../app-store.md) has the listing, the nutrition label, the age rating and the review notes, and the site's age-suitability page exists. What is left is **entering it into App Store Connect**, which needs Griff's account and is not something that can be done from here. |
| How it works, invitations | "By default that invitation is enough" stopped being true when an invitation became an offer. | **Done.** Rewritten 2026-09-15. It now separates the two questions it was running together: whether anybody else in the room has to approve (by default, no), and the characters you and your inviter read to each other, which happen whatever the room's policy is. |
| The marketing site | Support, How it works, Status and FAQ all say recovery through nominated friends is designed and not built. It was refused on 2026-09-09. | **Done.** 2026-09-15, in `outpost-site`. All four now say refused rather than pending, with the reasoning. **And the status page was stale the other way too**: seven things marked *Later* are built and tested — photographs, direct messages, per-person Outpost access, removing somebody, notification previews, search, and editing or deleting a post. Understating is the same defect as overstating. |

## Permissions, explained before they are asked

Each system prompt is explained in the app's voice first — what is asked for, why, and what the app
does if the answer is no. None of them is asked at cold launch. A view shown just before a
system prompt has one button and cannot be dismissed — the HIG's pre-alert rule, applied 2026-09-16.

| Permission | When | Explained | Behavior on refusal |
|---|---|---|---|
| Notifications | Once the account is ready, on the first ready screen | **Done.** `PermissionExplainerView(.notifications)`, seen on both simulators at first ready screen, 2026-09-04. One button, *Continue*, and since 2026-09-16 it cannot be swiped away before Apple's prompt — the HIG's pre-alert rule. The no is given to Apple. | Messages arrive when the app is opened; nothing announces them. Said in the sheet, and in the Notifications footer of You since 2026-09-05. |
| Photos | Never asked. `PhotosPicker` is out-of-process; the system shows the library and hands over only what is picked. The first tap of ➕ explains this once. | **Done.** `PermissionExplainerView(.photos)`, seen on the rig 2026-09-04; *Choose a photo* opened the system picker, whose own banner read "Private Access to Photos". There is no API that narrows the system's library prompt to limited-only — the app simply never triggers that prompt. | Nothing to refuse; closing the picker sends nothing. |
| Camera | The first tap of **Scan** on *Join a room*, after the member has answered *Turn on scanning* to a question on that screen, or turning on **Behavior ▸ Scan invites with the camera**. Never at launch. | **Done.** In the app's words, and kept apart from the prompt, because the HIG forbids a way out of a view shown just before one ([Decisions](../decisions.md#how-the-ask-and-the-higs-pre-alert-rules-both-hold)). The setting is saved on only once the camera is allowed. Usage string: "The camera reads the QR code on an invite somebody shows you, and the app keeps nothing else it sees." Seen on the rig 2026-09-16 up to the prompt, which a simulator never raises. | Paste stays, the setting is saved off, and the app says the camera is off with *Open Settings*. **Not yet seen on a phone.** |

## Debug leaves

**Closed 2026-09-15, and measured rather than read.** Every control was already behind `#if DEBUG`
at its call site — but gating a call site is not enough, and that is the finding worth keeping.

A `strings` pass over an actual Release build returned **"Blur every photo"**, **"Rotate mailbox
share"** and **"Show message delay"**. The views behind those controls were still being *compiled*,
so their words reached the shipped binary and the string catalog a translator works from, even
though nothing could ever draw them. The four debug screens are now wrapped in `#if DEBUG` as whole
files, and a second `strings` pass returns nothing.

- **Done.** *Erase everything* has replaced *Start over*, at the bottom of You in every build, with the
  facts on its sheet. *Resend everything* is deleted, replaced by history repair for everybody.
- **Done.** The Debug section — *Check mailbox*, *Rotate mailbox share*, *Show message delay*, the demo
  rooms, *Blur every photo* — is not reachable **and not compiled** into a Release build.
- **Done.** `--reset-account` and `--reset-device` are inside `#if DEBUG`, so a release build has no such
  argument to give rather than an argument that is merely harmless.
- **Done.** The debug nuke on the checking and stalled screens is DEBUG-only.
- **Done.** The demo conversation and demo Outpost feed are DEBUG-only.

**It stays closed by a script, not by memory.** `Scripts/check-release-leaves.sh [udid]` builds
Release and fails on any of fifteen developer-only strings. It is about strings rather than
reachability on purpose: reachability is what the `#if DEBUG` on a call site already buys, and the
strings are what survived it.

## Claims that need a proof first

Anything crossing the network is unproven until it has run on two devices on two accounts. Before
TestFlight these have to have been seen, not reasoned about:

- **Done.** A banner arriving on a phone from a bell rung by the other account: confirmed by Griff on hardware. Recorded here from his report rather than from a log this session read.
- **Done.** A reaction crossing the network and drawing beside the other person's on the receiving
  device: seen on beta at 20:04 on 2026-09-04, after the rendezvous healed.
- **Done.** The rendezvous healing a dead share on purpose: *Rotate mailbox share* on alpha at 01:40 on
  2026-09-05, alpha stopped; beta failed to accept with "Unknown Item", retracted the offer and
  fell to one zone at 01:40:17; alpha relaunched and wrote a fresh offer at 01:40:45; beta
  accepted it and read two zones at 01:41:17; a message each way at 01:42 arrived and was read.
- **Open.** A positive screening verdict, via Apple's test profile on a device.
- **Open.** The system trimmer opening on a phone.
- **Done.** The attachment record leaving the sender's outbox after the last acknowledgment. Proved against
  a real account 2026-09-15, and it was on this list as a *hardware* proof when it never needed one:
  one recipient collecting leaves the other still owed and the bytes still downloadable; the second
  one takes the record out of the listing and the bytes with it.
- **Open.** A member's second device on one Apple Account (hardware only).

## Dark and light, on every surface

**Raised by Griff on 2026-09-14: the notification sheets do not look like they follow dark and
light.** Not yet measured — this is his report, and it is the reason this section exists rather than
a finding of its own. The app paints its own palette and the system paints sheets, alerts, pickers
and anything UIKit still owns, so the two can disagree on exactly the surfaces nobody screenshots
twice.

Do this as one pass, both appearances, on a 402pt phone and a 440pt one, and tick a row only when
both were actually looked at:

- **Done.** The notification sheets — the permission explainer and the Outpost notifications ask. **The
  banner itself needs a push**, which is hardware; see
  [Still to prove](../roadmap.md#still-to-prove).
- **Done.** Sheets and confirmation dialogs: the per-room notification sheet, the privacy check-up, the
  photo explainer, the hide confirmation, the leave confirmation, the Outpost access review.
- **Done.** `alert`: the *this cannot be undone* alert before allowing everyone into an Outpost.
  **Both appearances, both widths, 2026-09-15** — raised from the Outpost access review on alpha
  (402pt) and beta (440pt) with the appearance set to dark, and correct on each: the title white on
  the system's own dark material, the message legible, *Cancel* in the app's accent and *Let them
  all in* in the system's destructive red. It was already seen in light on 2026-09-14.
  **And the class was audited rather than the instance.** Every one of the app's seventeen `.alert`
  modifiers was read for an app-painted color inside its own closures, and there is not one —
  no `palette.` anywhere in a title, message or button of any alert in the app. So there is no
  surface on any of them for the app's palette to disagree with the system's, which is what this
  section exists to catch. That is a stronger statement than looking at one alert twice, and it is
  the reason this row can close rather than staying a spot check.
- **Partly.** The photo picker: **Done.** both appearances. The camera, the trimmer and the crop screen are
  hardware — a simulator's trimmer refuses every file.
- **Done.** The privacy check-up. **Done.** The onboarding tour, walked on a freshly erased account.
- **Open.** The notification service extension's own rendering. It is a second process **and it needs a push
  to run at all**, so this is hardware rather than a sweep item.
- **Done.** Increase Contrast in both, Reduce Transparency in both.

Switch appearance with `xcrun simctl ui <udid> appearance dark|light` rather than in Settings, so
the same command can be run against every booted device in the rig.

### What the rig found on 2026-09-14

Walking the two flows built that day, on alpha, with the app in **light**:

| Surface | What was seen |
|---|---|
| The room row's context menu | The **preview** of the conversation renders on a black ground while the app is light — the bubbles are correct, the sheet behind them is not. iOS draws that preview itself, so this is the exact class of surface this section exists for. Not yet diagnosed; it may be the preview inheriting a `colorScheme` the app never set. |
| The hide confirmation | Correct in light. Quotes the message, states the scope before the buttons, destructive tint on word and glyph. |
| The leave confirmation | Correct in light. The *Review Outpost Access* choice is correctly **absent** when nobody holds access chosen in that room. |
| The per-room notification sheet | Correct in **both**, checked with the sheet open and the appearance switched under it. This is the surface Griff reported; it follows the appearance. |
| The Outpost notifications page | Correct in both. |
| The privacy check-up | Correct in both. |
| A system alert | Correct in light — the *this cannot be undone* alert before allowing everyone into an Outpost. **Correct in dark too, on both widths, 2026-09-15**, and an audit of all seventeen `.alert` modifiers found no app-painted color inside any of them. |
| Increase Contrast | Correct in **both**; the palette reads the trait and the bubbles gain contrast rather than ignoring it. |
| The photo permission explainer, and the system picker behind it | Correct in both. The system picker draws its own "Private Access to Photos" banner, which is out of this app's hands and follows the system. |
| Reduce Transparency | Correct in both. The glass surfaces — the tab bar and the in-room banner — go opaque and stay legible. It is **not** settable with `simctl ui`, which only offers appearance, increase_contrast and content_size; it has to be turned on in the simulator's own Settings, under Accessibility › Display & Text Size. |
| The room row's context-menu preview | **Was the defect.** Fixed 2026-09-15 and correct in both now — see the section below. |
| Onboarding, end to end | Correct in dark, walked on a freshly erased account: the welcome screen, the privacy check-up's sixteen steps, and the empty rooms list at the end. |
| The erase-everything sheet and its dialog | Correct in light. |

**And one thing the erase confirmed that was not about color.** A fresh account taking *Familiar
and open* now has **Tell me when somebody sets up again** switched **on**, with *Hold my history
until I have checked* off. Before 2026-09-15 that first switch was off, and the friendly preset —
the one most people take — turned it off explicitly. Fixed earlier that day and seen here on a real
device rather than only in a test.

## A scan against iOS 27

Added 2026-09-15, at Griff's instruction, after Xcode updated itself to **27.0** mid-session.

Everything this project has ever been built and seen working was built against the iOS 26 SDK and
run on an **iOS 26.5** runtime. Xcode 27 changes the SDK the App Store will accept and the OS most
TestFlight testers will be on, and a major release is where behavior moves under an app that did
not change: default styling, gesture handling, focus order, deprecations, and the small layout
shifts that only show on a device.

**None of this is a build failure.** The app compiles against the new toolchain today — measured
2026-09-15, both the package suite and the app target. That is the part that is easy to check and
the part that proves least.

| Item | What it has to do | Status |
|---|---|---|
| Build against the iOS 27 SDK | Compile clean for a **device**, and read the warnings from a clean build. | **Done.** 2026-09-16. Xcode 27 carries only the iOS 27 SDK (`xcodebuild -showsdks`), so every build since it arrived has been against 27 — the earlier line here said otherwise. A clean generic-device build succeeds. It also caught a device-only error the simulator builds could not: `InviteScanning.deviceCanScan` read a main-actor property from a nonisolated one, behind `#if targetEnvironment(simulator)`. **Build for a device, not only the simulator, before calling the build green.** |
| Apple's iOS 27 release notes, read against this app | Every change that applies to an app built with the 27 SDK, checked in the code. | **Done.** 2026-09-16, below. |
| Deprecations answered | Each one either fixed or written down with why it stands. | **Done.** 2026-09-17, **all fixed**: a clean generic-device build has no compiler warnings. 26 `Text + Text` joins in seven files are string interpolation now, so a translator sees one sentence with a placeholder rather than fragments — proven on the rig, where a reaction's spoken summary nests three of them and reads *Reactions: 💜 from you*. Four photo pickers that built their label inside `PhotosPicker`'s nonisolated `@Sendable` closure are a `Button` with `.photosPicker(isPresented:)`, the same system picker, seen opening on the rig. The notification extension's `NSLock` is `withLock`, the scoped form. Four tidy-ups: a `var` that was a `let`, an unused `try?` result, an unused binding, and a `??` on a value that could not be nil. **What stays:** the build prints one tool note, `appintentsmetadataprocessor`: *Metadata extraction skipped, no AppIntents.framework dependency found*, for the notification extension, which has no App Intents; the app target's extraction runs clean. |
| Both suites on an iOS 27 runtime | The package suite and the app-target suite, including the live CloudKit ones. | **Deferred, ruled.** Griff, 2026-09-17: it runs on an iOS 27 device, and the in-depth pass waits for the duo. The runtime is still not installed and the rig is still 26.5, so this is unproven here rather than proven elsewhere. |
| A rig walk on iOS 27 | Every screen, both appearances, with the software keyboard up. | **Deferred, ruled.** Same ruling, same day. TestFlight on real hardware is what answers this. |

**What Apple's iOS 27 release notes change for this app**, read 2026-09-16 from
`developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes`:

- **`TabView` "might crash when its selection is set to a hidden or otherwise unavailable tab."**
  This one applied. The Rooms tab exists only when the inbox is split, and the tab selection starts
  on Rooms — so anybody who had merged their inbox would launch with the selection on a tab that is
  not there. Fixed: the `TabView` reads a selection that falls back to the first tab whenever Rooms
  is not drawn.
- **A `Text` with `.textSelection(.enabled)` now uses the system's selection gestures.** The inline
  verification characters sit inside tappable rows, where selection gestures could take the tap.
  Selection is now on only for the large display of the characters, where copying them is the
  point.
- **Apps built with the 27 SDK must include a launch screen and adopt the scene-based life cycle.**
  Both already true: `UILaunchScreen` and the scene manifest are generated by the build settings,
  and the app is a SwiftUI `App`.
- **`@State` is now a macro** that no longer compiles a few patterns. The app compiles, so none are
  used.
- **Sheets and popovers reset `controlSize` and button shape.** Every control here sets its own size
  on the button, not on a container around a sheet, so nothing inherited is lost.
- **`canOpenURL` is deprecated; the old status-bar accessors may return NaN; `originalFilename` on a
  photo resource is being replaced; `toolbarMinimizeBehavior` is renamed.** None is used.

## A scan for known vulnerabilities

Added 2026-09-14. Griff gave this as one of two reasons the crypto needs no outside reviewer, and it
did not exist: CI runs the package suite, the app suite, the branding lint and the builds, and
nothing else. It is listed here so the reason becomes true rather than assumed.

Run by `Scripts/scan-for-vulnerabilities.sh [udid]`, first on 2026-09-15 and clean:

| Item | What it has to do | Status |
|---|---|---|
| Dependency scan | The package graph checked for code this project did not write. | **Done.** **There is none.** No remote package references in the Xcode project, no `Package.resolved` anywhere, and every target in `Package.swift` depends only on its siblings. Every line that ships is this project's or Apple's — which is worth stating plainly, because it is the strongest single thing that can be said about this app's supply chain. The check is a count rather than an advisory lookup for exactly that reason, and it says so: the day a dependency arrives, it has to become a real one. |
| Static analysis | Xcode's own analyzer over both targets, clean or with every finding answered. | **Done.** Clean 2026-09-15. |
| Secrets scan | No key, token or account credential, in the working tree or anywhere in the history. | **Done.** Clean across the working tree and the last 500 commits. It matches on **shapes** rather than words — a credential that matters has a recognizable form, and grepping for "password" finds this app's copy about passwords instead. The history is checked as well as the tree, because removing a key in a later commit does not unpublish it once the source is open; it has to be rotated. |

None of these substitutes for the brief, and none of them reads a protocol. They catch the things a
person would not think to look at.

## The marketing site

Added 2026-09-16, from Griff.

- **Done.** **The full rewrite**, 2026-09-17. The 84 design boards are deleted. `/screens` is ten
  screenshots of the running app, taken per accent in light and dark by `npm run shots` driving the
  app's own debug-only site-shot host — [Decisions](../decisions.md#the-marketing-site-is-photographed-not-drawn).
  Every page's copy was checked against the code; `/roadmap` and `/bullet` are written. What the
  rewrite corrected is in the commit, and the short version is that the site claimed iPad and Mac,
  no media, a six-character phrase, unbuilt Solos, unbuilt blocking and a dollar-a-month
  subscription, and five of its seven accent values did not match `Accent.swift`.

## Before the source is public

- **Open, and his.** **Two tracked files would go public as they are.** `scratch.md` holds notes for
  •bullet, a different app, and `YouView.subscribeByEmail` opens a mail to `updates@`, an address, in
  a build where the 2026-09-17 ruling says the only route to a person is a form. Found 2026-09-19.

- **Done.** **The history is one commit.** `RULED` — Griff, 2026-09-17; done 2026-09-18 with an
  orphan branch rather than `git filter-repo`, since the whole history went rather than one field of
  it. Every commit now carries one identity.

  **Why.** Commit metadata is public the moment the repository is, and earlier history carried
  addresses that belonged to employers rather than to this project. They are deliberately not
  repeated here: a document explaining why an address should not be public is still a public place
  to have written it down. That was true of this paragraph until 2026-09-18, and of the rewrite
  script beside it.

  **What it cost.** Every commit message, which was a second copy of the reasoning `docs/` holds the
  first of; `git log -S` as a way to find when something entered the build; and the co-authorship on
  every commit Claude wrote. A full copy of the old history is kept off the repository, in a git
  bundle Griff holds.

  **What a force-push does not do.** GitHub keeps `refs/pull/1/head` and `refs/pull/2/head`, which
  still reach every old commit, and they cannot be deleted by the owner. `main` is clean; the old
  commits stay fetchable from the PR refs unless the repository itself is recreated.

## CloudKit, before the first real build

- **Done.** **The schema exists and is written down.** `CloudKit/schema.ckdb`, imported into
  development 2026-09-18. It had to be written rather than deployed from inference: the development
  environment was exported on Griff's ask and held one record type, `Users`, the stock one. Nothing
  the app writes had ever reached it — the rig runs against `FileMailbox` and the live suite is
  opt-in behind `CARPENTER_CLOUDKIT_TESTS`. Deploying development to production would have deployed
  nothing and looked like it worked.
- **Done.** **Development is deployed to production** for **`iCloud.com.microgpt.outpost`**. Found
  deployed on 2026-09-22: `xcrun cktool export-schema … --environment production` lists six record
  types, and the production schema is identical to development's, field for field.
- **The trap, and it was walked into once.** There is a second container,
  `iCloud.com.microgpt.carpenter`, which is **not the app's**. `APP_ICLOUD_CONTAINER` resolves to
  `…outpost`, the built entitlement carries `…outpost`, and `CKContainer.default()` takes the first
  identifier in that list. `…carpenter` has never appeared in `Branding.xcconfig` — the value went
  `…dec` → `…outpost` on 2026-09-04 — so Xcode presumably made it from the bundle ID. A deploy into
  it on 2026-09-18 made three dead record types permanent there: `PairingRequest`, `PairingRequests`
  and **`packetID`**, which is a field name, so a field name reached `CKRecord(recordType:)` at some
  point in the history. A production schema is additive and a container cannot be deleted, so the fix
  is to leave it unused. **Read the container name in the Console breadcrumb before every schema
  action.**
- **Done, in development.** **Real writes against the schema.** The live suite ran on alpha on
  2026-09-19 once its account was signed in again: 47 tests in 10 suites passed against
  `iCloud.com.microgpt.outpost`'s development environment, including a message crossing between two
  identities, a round bigger than one packet, a hole refilled over the network, a restore from a
  recovery key, and ciphertext alone reaching the server. The same day two accounts exchanged rooms,
  replies and bells on the rig. Production is proven by the first TestFlight build writing, after the
  schema is deployed.
- **Done.** **A Release build talks to the production APNs gateway.** `aps-environment` was
  hard-coded to `development` in `Carpenter.entitlements` and one file serves both configurations, so
  the TestFlight build would have registered, been accepted and received nothing. It comes from
  `APS_ENVIRONMENT` in `Branding.xcconfig` with a `[config=Release]` override now, verified through
  `-showBuildSettings`.
- **Open.** The App ID needs `iCloud.com.microgpt.outpost` enabled on it, or automatic signing has
  nothing to build a distribution profile from. Not exercised yet — every build so far has been
  `CODE_SIGNING_ALLOWED=NO` or a simulator.

## Operational

- **Changed.** **No address is published anywhere.** Griff, 2026-09-17: delete the abuse mailbox; the only
  way to reach a person is a form. `abuse@` and `info@` are gone from the site and from the app —
  eleven `mailto:` links across the legal pages, the footer, support, security and accessibility now
  point at `/contact`. `CMS_REPORT_TO` and `CMS_MESSAGE_TO` still name mailboxes, but they are where
  the service *delivers*, not somewhere anybody is invited to write. **What this leaves:** App Store
  Connect still wants a contact address of its own, which is his and never the app's, and somebody
  who cannot use a web form has no route at all. The phone number on `/support` and `/accessibility`
  is the remaining non-form route and it is deliberate — see
  [Decisions](../decisions.md#every-route-to-a-person-is-a-form-and-no-address-is-published).
- **Partly.** **Media cannot reach the abuse intake.** Added 2026-09-17, answered the same day with a
  form rather than a mailbox rule. `microgpt-comms` in the SpringBonk ecosystem takes a report at
  `outpostmessaging.com/report`, verifies the upload **by its bytes** — strict UTF-8, no control
  characters, then the app's own labelled grammar — and refuses everything else, so an image, a PDF,
  an archive or a video never reaches storage. Eighteen tests, written from `AbuseReport.body`.
  **Closed 2026-09-17.** The mailbox is gone, so there is no longer a path that bypasses the parser:
  the app writes the report, copies it, and opens the form, and the form has no file input at all.
  A category rides with every report and decides where it is taken; `/resources` publishes that
  routing. `CategoryTest` pins both slug lists, because `outpost-site` posts them and no compiler
  joins the two repositories.
- **Changed.** **There is no vault, and there should not be one.** Asked 2026-09-17 how a vault would
  work on the Pi; the answer is that the intake moving off mail dissolved the question. A report is a
  row in `cms-db` on the developer's own machine, on the volume Postgres already uses, covered by the
  `pg_dumpall` sidecar that was already running. Nothing new to mount and nothing new to back up.
  What did have to change was the published claim: the privacy policy said reports are "encrypted at
  rest", which nobody had checked and which is a property of that machine's disk, not of this
  software. It now says where a report actually lives and that a deleted one survives three nightly
  backups. `pg-backup-report` mails a weekly note saying whether the dumps happened — names, sizes
  and checksums, never the dump, because `pg_dumpall` carries every role password and now every
  reporter's address too.
  **What is still open:** § 2258A(h) wants a filed report kept "in a secure location with limited
  access" for a year. A Postgres database on a machine in his house, reached only from that machine,
  is a defensible reading of that. Whether the disk under it should be encrypted is his call and it
  is an operating-system decision, not a code one.
- **Partly.** **The source is published, under a license, when the TestFlight build goes out.** The license
  exists: the Mozilla Public License 2.0, in `LICENSE`, 2026-09-17
  ([Decisions](../decisions.md#the-source-is-published-under-the-mozilla-public-license-20)). Publishing
  it is still to happen with the build — [App Store §3](../app-store.md#3-export-compliance) rests the
  export position on it.
- **Done.** **`ITSAppUsesNonExemptEncryption` is `true`** in `App/Carpenter/Info.plist`, 2026-09-17, as
  [App Store §3](../app-store.md#3-export-compliance) says. App Store Connect still asks Apple's
  questionnaire; this is not verified to stop it asking again per build.
- **Done.** **The rig's iCloud sign-ins.** Both lapsed on 2026-09-17 ("bad or missing auth token"); Griff
  reset alpha and signed alpha and beta back in the same day, and the live deletion test ran on beta.
- **Done.** The privacy policy and the store EULA carry the report-retention section, written 2026-09-15 in
  `outpost-site`. Section 10 of the policy had said "We retain nothing, because we receive nothing",
  which is true of messages and false of a report. It now says what a report contains and that it is
  text with no field for media, how long it is kept and under which law, that it is encrypted with
  access limited and moved out of the receiving mailbox, and that an escalation is not confirmed to
  either party. The terms carry the short form and link to it.
- **Changed.** The deny list's `updated` date. **This item was wrong and is corrected rather than done.** It
  asked for the date of the build; the copy beside it reads "a short list shipped inside the app,
  **last changed** \(date)". The list is empty and has not changed since 2026-09-04, so stamping it
  with a build date would make the app claim a change that never happened — the same class of defect
  this whole page exists to catch, pointed the other way. The date is right as it stands. What has to
  happen before a build is that somebody **looks**: if the list changed, the date moves with it, and
  if it did not, it does not.
