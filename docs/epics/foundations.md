---
# COPY BEGIN 64b59f32 [NEEDS HUMAN REVIEW]
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

<!-- COPY END 64b59f32 -->

<!-- COPY BEGIN b9b9b38d [NEEDS HUMAN REVIEW] -->

## Where this stands

Cross-cutting work: the rules that hold everywhere, the tests that hold them, and what has to be true
before anybody outside sees a build.

Every ticket on this page, with its status and what was actually observed, is on the
[Roadmap](../roadmap.md#where-everything-stands).

<!-- COPY END b9b9b38d -->

<!-- COPY BEGIN 7572746d [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 7572746d -->

<!-- COPY BEGIN a18e6058 [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END a18e6058 -->

<!-- COPY BEGIN 8add9285 [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 8add9285 -->

<!-- COPY BEGIN 9e180cb3 [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 9e180cb3 -->

<!-- COPY BEGIN 939218f4 [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 939218f4 -->

<!-- COPY BEGIN 279b1803 [NEEDS HUMAN REVIEW] -->

<details markdown="1">
<summary>Record — the six that went</summary>

`messageArrived`, `reactionAdded`, `reactionRemoved`, `selectionChanged`, and the split between
admitting and refusing a join. Each was defensible alone; together they were an app that vibrates
while you use it, and every one failed the rule by carrying no visible partner. `joinRefused` looks
like a refusal and is not: refusing somebody is the member deciding, and it succeeds, so it is a
commit.

</details>

</details>

<!-- COPY END 279b1803 -->

<!-- COPY BEGIN a3de464d [NEEDS HUMAN REVIEW] -->

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

**Detail.** [Before TestFlight](../pre-testflight.md#permissions-explained-before-they-are-asked).

</details>

<!-- COPY END a3de464d -->

<!-- COPY BEGIN d8d96ee2 [NEEDS HUMAN REVIEW] -->

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
[Before TestFlight, operational](../pre-testflight.md#operational).

</details>

<!-- COPY END d8d96ee2 -->

<!-- COPY BEGIN 79e7ec2d [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 79e7ec2d -->

<!-- COPY BEGIN 2b0740b6 [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 2b0740b6 -->

<!-- COPY BEGIN 38d00008 [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 38d00008 -->

<!-- COPY BEGIN e6621dbd [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END e6621dbd -->

<!-- COPY BEGIN a31b88f6 [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END a31b88f6 -->

<!-- COPY BEGIN 7ea350db [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 7ea350db -->

<!-- COPY BEGIN 8077dda9 [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 8077dda9 -->

<!-- COPY BEGIN 7e190556 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="a-cloudkit-integration-target">
<summary><b>A CloudKit integration target</b> — Complete (tested)</summary>

**Story.** As somebody changing the sync code, I want a target that fails when I break CloudKit, so
that the one seam a green suite has been wrong about more than once is covered by something that
touches it.

<!-- COPY END 7e190556 -->

<!-- COPY BEGIN 605d2405 [NEEDS HUMAN REVIEW] -->

### Why it can be small

The seam is already right, and that is most of the work. `Mailbox` is a protocol, `PacketWire` maps a
packet to named fields **above every transport**, and `CloudKitMailbox` is the only thing that knows
what a `CKRecord` is. So this target needs no app, no session and no UI — it drives the mailbox
directly.

<!-- COPY END 605d2405 -->

<!-- COPY BEGIN 3dfc424d [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 3dfc424d -->

<!-- COPY BEGIN 7f7862ee [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 7f7862ee -->

<!-- COPY BEGIN 88331dfb [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 88331dfb -->

<!-- COPY BEGIN efd60359 [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END efd60359 -->

<!-- COPY BEGIN 397a14d1 [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 397a14d1 -->

<!-- COPY BEGIN 9fa4ce4f [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 9fa4ce4f -->

<!-- COPY BEGIN 33967feb [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 33967feb -->

<!-- COPY BEGIN fca6e1eb [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END fca6e1eb -->

<!-- COPY BEGIN 949d237a [NEEDS HUMAN REVIEW] -->

- **Done.** The palette answers both appearances, and the contrast audit covers both rather than only dark.
- **Done.** **The sweep**, done 2026-09-15 and recorded on
  [Before TestFlight](../pre-testflight.md#dark-and-light-on-every-surface). It found one real defect
  — a context menu's preview is hosted outside the app's hierarchy, so `\.palette` fell back to its
  declared default, which is dark, and the preview drew dark inside a light app. Fixed, and a lint
  rule now catches the next one. Everything else follows the appearance: sheets,
  the notification surfaces Griff flagged on 2026-09-14, menus, alerts, confirmation dialogs and the
  keyboard's accessory. These are the surfaces the app does not paint, so a test cannot reach them.
  Tracked on [Before TestFlight](../pre-testflight.md#dark-and-light-on-every-surface).
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

<!-- COPY END 949d237a -->

<!-- COPY BEGIN a6075f6b [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END a6075f6b -->

<!-- COPY BEGIN 5bd4c3cc [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 5bd4c3cc -->

<!-- COPY BEGIN 74808cb2 [NEEDS HUMAN REVIEW] -->

**What would falsify the epic.** A green suite next to a broken app. That is the specific failure
this epic exists to prevent, and it has happened enough times here to be the working assumption
rather than a worry.

<!-- COPY END 74808cb2 -->
