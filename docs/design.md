---
title: Design
layout: default
nav_order: 16
nav_exclude: true
has_children: true
---

# Design

{: .no_toc }

The drawings the app was built against, kept for reference. They are a record of what was
intended, not a description of what the build does — where the two disagree, the build is the
answer and [the roadmap](roadmap.md) is its status.

1. TOC
{:toc}

## The set

`docs/design/boards/` in this repository: three files, all required reading, and a text index.

| File | What it is |
|---|---|
| [Outpost Mockups]({{ site.baseurl }}{{ site.design_board }}) | 84 boards. The drawings. |
| [Component Decisions]({{ site.baseurl }}{{ site.design_decisions }}) | Twelve rulings where the app and the set disagreed, plus six taken while drawing. Each says which side changes. |
| [Component Blockers]({{ site.baseurl }}{{ site.design_blockers }}) | Every exact value, and the accessibility requirement for each of the 84 boards. |
| [Board index](design/board-index.md) | All 84 boards as text, generated so the set is greppable. The HTML is not. |

{: .important }
> **The captions on the canvas are marketing copy, published verbatim. They are not specifications.**
> Exact values and per-board accessibility requirements exist only in Component Blockers. A story
> that cites a board without citing the blockers page is citing prose.

**The design pass is closed.** Griff's decision, 2026-08-18: the design tool is retired and the
boards will not be re-exported, so the set is a historical record. Edit it in place when it is wrong,
cite it for content and copy, and answer presentation questions from the platform — iOS 26's own
apps, Messages first.

## The system beats a board

Griff's ruling, 2026-08-18: **wherever Liquid Glass and a board disagree, the system wins.** The
boards supply the content, the copy, the hierarchy and the accessibility requirements. Presentation
belongs to the OS.

It came out of blocker D4, which found the boards drawing a flat, full-width tab bar with a hairline
above it. iOS 26 renders `TabView` as a floating glass capsule and there is no way to turn that off:
the selection capsule survives `selectionIndicatorTintColor = .clear`, and the only global escape is
`UIDesignRequiresCompatibility`, which disables Liquid Glass app-wide and is already scheduled for
removal.

Applied so far: the tab bar; primary buttons as the system's prominent glass style, tinted with the
derived `accentFill`; the rooms list as a system `List`; search as a real search tab; create sheets as
`Form` with the actions in the bar; empty states as `ContentUnavailableView`.

"Use exactly this" now governs only what the app draws itself — bubbles, delivery marks, avatars, the
unread dot. Geometry tokens for system chrome were deleted rather than kept as documentation, because
a token nobody consumes is a second copy of a decision waiting to disagree with the first.

## What the set does not cover

Named by the designer at handoff. Each is a real limit on what a board can be taken to mean, and each
has a ticket.

**Units are px named as pt.** The boards are HTML approximations of SwiftUI drawn at 1:1 — fine for
layout intent, and nothing in them has been checked on a device at a real Dynamic Type size. A
measurement taken off the canvas is not a specification; Component Blockers is.

**One platform is genuinely drawn.** iPhone is complete. iPad and Mac have two boards between them,
and the Mac's `NavigationSplitView` behavior was settled without boards at all. The set claims three
platforms and draws one. → [Draw the platforms the set claims](epics/desktop.md#draw-the-platforms-the-set-claims)

**Light mode is rules, not drawings.** Two boards define the values and four use them. Every other
screen needs the substitution applied, which is an inference rather than a copy. →
[Light mode, from rules rather than drawings](epics/foundations.md#light-mode-from-rules-rather-than-drawings)

**Transitions are not drawn.** "Almost no motion" is a position, and what happens between two boards —
sheet presentation, tab switch, the retint — exists in prose at most. →
[Transitions](epics/foundations.md#transitions)

## The contrast finding

Ruling 13, found by measuring rather than in the designer's own table, and the most consequential
thing the pass produced.

**Every filled primary button and every sent bubble put white text on the accent's base value, and no
accent is dark enough to carry it.** Cobalt 3.88, oxblood 4.33, aubergine 3.36, hangar slate 3.04,
verdigris 2.94, olive drab 2.53, signal amber 2.50. At 17pt regular and semibold this is normal text,
so 4.5:1 applies rather than 3:1. Not one cleared it.

Fixed 2026-08-18, and the finding was half right about this app: sent bubbles already derived a
darkened fill and were fine, filled buttons used the accent's own value and moved the *text* instead,
which puts black text on a colored button in dark mode. The audit tested neither pair, so the
bubble's derivation was unpinned — it worked, and nothing would have noticed if it stopped.

The fix keeps the accent recognizable: a solid fill behind white text uses a derived darkened step of
the same accent, taken down until white clears 4.6:1. One token rather than seven hand-picked hexes,
so it holds if an accent is retuned. The accent's own value still carries text, icons, tints, edges
and the unread dot, where 3:1 applies and every accent passes. →
[The contrast finding, and the test that missed it](epics/foundations.md#the-contrast-finding-and-the-test-that-missed-it)

**The set's own grays fail the same floor.** "Use exactly this" gives Apple's `secondaryLabel` and
`tertiaryLabel` values, which on this app's surfaces measure 2.33–3.44 in light and 3.93–4.00 for
dark tertiary against a required 4.5. Eleven pairs fail. That is the set disagreeing with itself —
its own accessibility section requires every board to clear the floor — and it is the same shape as
ruling 13: a token borrowed from the platform, correct as a platform default and wrong as a contract.
The app keeps its stronger grays, which are the weakest values that clear 4.5 on every surface in both
appearances.

## What the rulings ask of the app

Six changes and two tests, from Component Decisions. Each has a ticket.

| Ruling | Change | Ticket |
|---|---|---|
| 11 | Three tab roots move to system navigation bars with large titles; the sync line becomes an inset row beneath. Since revised: Rooms and Outposts have inline titles and You has none. | [Tab roots on system navigation bars](epics/foundations.md#tab-roots-on-system-navigation-bars) |
| 5 | The plus in the reaction picker opens the system emoji picker instead of a fixed list. | [Reactions on messages](epics/content-and-composer.md#reactions-on-messages) |
| 4 | The unlit delivery mark becomes an outline, gains two spoken strings and a third "not reported" state, and read reporting becomes opt-in. | [Delivery marks, and who reports](epics/messaging.md#delivery-marks-and-who-reports) |
| 12 | Any haptic cue outside the three named is removed. | [Haptics, bounded to three cues](epics/foundations.md#haptics-bounded-to-three-cues) |
| 13 | Filled buttons and sent bubbles use the derived fill step. | [The contrast finding](epics/foundations.md#the-contrast-finding-and-the-test-that-missed-it) |
| 2 | Washed bars audited as their own surfaces at all seven accents. | [The contrast finding](epics/foundations.md#the-contrast-finding-and-the-test-that-missed-it) |
| 9 | Field borders join the audit as interface edges at 3:1. | [The contrast finding](epics/foundations.md#the-contrast-finding-and-the-test-that-missed-it) |
| appendix | The default accent becomes verdigris. | [The contrast finding](epics/foundations.md#the-contrast-finding-and-the-test-that-missed-it) |

Everything else in the rulings is a board redraw, already done in the set.

## Rulings that changed what a feature is

Six were taken while drawing. They are product decisions rather than component ones, and they are
recorded here because a reader of the boards alone would not know a decision had been made.

- **Outpost access is an allow-list defaulting to nobody.** Joining a room grants nothing. →
  [Per-person Outpost access](epics/rooms-and-membership.md#per-person-outpost-access)
- **Notification levels are four, drawn as the banner each produces.** A per-room override names the
  default it follows rather than reading as unset. →
  [Notification previews](epics/notifications.md#notification-previews)
- **The welcome tour keeps its promise.** The `?` it names is drawn into every tab root, opening a
  how-this-works page. →
  [The help the welcome tour promises](epics/foundations.md#the-help-the-welcome-tour-promises)
- **Show hidden messages stays a count.** Restoring is all-or-nothing per room, messages return to
  their original positions, and hidden messages are excluded from local search. →
  [Hiding, as the set draws it](epics/data-etiquette.md#hiding-as-the-set-draws-it)
- **Blocking and reporting are screens, not systems.** Blocking states plainly that the person
  remains in the room; reporting composes an email from the reporter's own device, because there is
  no server to report to. →
  [Reporting a message](epics/rooms-and-membership.md#reporting-a-message)
- **Solos are separate by default, blended by switch.** Solos and Rooms are two tabs by default and
  one Messages tab when merged. A two-person conversation is a *Solo*, Griff's word. →
  [Solos](epics/messaging.md#solos-a-conversation-with-one-person)

## Where the app departs from a board

A board is the design, and overruling one has to be written down or the next person reading the board
will "fix" the app back.

### Board 74 — the admission policy sits behind an advanced toggle

**The board says** the policy is set on the creation sheet as a radio group: "a real choice with a
stated default rather than a setting to be found later".

**Griff decided otherwise, 2026-09-01.** The creation sheet shows the name and the defaults; the
policy sits behind an understated *advanced setup* toggle, off by default.

The board's argument is sound in isolation — on this architecture a policy change is itself a message
that lands device by device, so choosing well at creation matters more than it would with a server.
What won is that most rooms are a few friends who will take the default, and putting a five-way
security choice in front of every one of them trains people to tap past the screen. The cost is
accepted: somebody who would have chosen differently has to notice a toggle first. Board 75, the same
control in room settings, is untouched.

### Board 53 — the list row names no sender

**The board** puts the sender's name in a group's preview. The app drew it as a pill above the
preview and the row went to three lines.

**Claude changed it, 2026-09-05**, and Griff has not seen the reasoning. The row is now measured
against Messages on the same simulator: 45pt avatar, 8pt gutter with the unread dot in it, text at
84pt, two reserved preview lines, a chevron, and no sender named. Listed as a question in
[Open questions](open-questions.md).
