---
title: Desktop roadmap
layout: default
nav_order: 6
---

# Desktop roadmap

{: .no_toc }

The Mac and iPad, as their own product, after the iPhone is on TestFlight.

1. TOC
{:toc}

## Why this is a separate page

`RULED` — Griff, 2026-09-14.

The product is an iPhone app until TestFlight; that was the 2026-09-13 ruling, and it is why the
listing, the site and the docs say iPhone. This page is the second half of it: the desktop work is
**sequenced after** a TestFlight build rather than carried alongside it, so it stops competing for a
place in the iPhone roadmap's counts and stops reading as though it were nearly due.

Nothing on this page is scheduled. Nothing on it blocks TestFlight. When an iPhone build is up and
being used, this page is where the next product decision starts.

**Other devices Griff has said he wants one day** — which as of 2026-09-16 means the iPhone Duo — are
on [After TestFlight](after-testflight.md#devices-to-eventually-support) rather than here, because
this page is the Mac and the iPad specifically and the work on it is sized.

The long form — the stories, the acceptance criteria, what was observed and when — stays in
[the desktop epic](epics/desktop.md). This page is only the status of record, and it uses the same
statuses as [the roadmap](roadmap.md#how-to-read-this).

## What stands today

The Mac **runs**: a window, three columns, a folding sidebar, and a keychain that behaves like iOS's
rather than the legacy file-based one — without that last part a Mac and an iPhone carried two
different identities while claiming to be one member. It keeps working because Griff uses it. It is
not offered, described or supported, and no member has ever been shown it.

The iPad at full width uses the Mac's layout, in both orientations, walked on a simulator by
`WideLayoutTests` — [Decisions](decisions.md#the-mac-and-an-ipad-at-full-width-share-one-layout-areas-a-list-and-what-is-open).
It has not been drawn by a designer; the implementation decided it.

## Tickets

| Ticket | Status | Evidence |
|---|---|---|
| The Mac window feels like a Mac app | Incomplete | Runs in three columns; invite control restored 2026-09-01. **The Mac stopped compiling the day `HardwareName` arrived** — an unconditional `import UIKit` — and builds again as of 2026-09-18. Return and Shift-Return, the flicker, the new-post sheet and the keyboard path all need measuring in a live window: see below. |
| The app icon on macOS | Built, not seen in the Dock | An Icon Composer document with a dark appearance, scoped to the macOS SDK; checked in the compiled `.icns` at every size. The full mark does not read at 16 points. [Decisions](decisions.md#the-mac-icon-is-an-icon-composer-document-and-ios-keeps-its-own). |
| The desktop wall | Built, not seen | An inspector beside your own Outpost holding *Who sees your Outpost*, open by default, hidden with ⌥⌘I. [Decisions](decisions.md#the-desktop-wall-is-an-inspector-open-by-default-and-hideable). |
| A Settings window | Built; panes drawn offscreen | ⌘, opens a Settings window with a toolbar of panes — Appearance, Behavior, Notifications, Privacy & Safety, Outposts, Devices, Data — holding the same pages the iPhone pushes from You. You on the Mac keeps your name, People, Supporter, your Outpost, help, and a *Settings* row. [Decisions](decisions.md#the-mac-has-a-settings-window-built-from-the-same-pages). |
| What's waiting, in the toolbar | Built, not seen live | The filled mailbox; a popover of unread rooms and new Outposts; a count that is the Dock's number and shows only when badges are on. Rendered offscreen at 3, 12 and 99+, unclipped. [Decisions](decisions.md#the-mac-toolbars-mailbox-carries-a-hand-drawn-count-and-only-when-badges-are-on). |
| The wide layout, Mac and iPad | Built; iPad walked in both orientations | Areas, the iPhone's own lists, and what is open, in three columns. The Mac's sidebar had no unread marks, pins, tags, search, waiting invitations or way to start a room; it has all of them now because the list is the iPhone's. [Decisions](decisions.md#the-mac-and-an-ipad-at-full-width-share-one-layout-areas-a-list-and-what-is-open). |
| The menu bar | Built; menu structure measured | File, View, Go and Help carry the app's commands with standard shortcuts, and a compose button in the sidebar starts a room, a solo or joins with an invite — the Mac had no way to do any of the three. [Decisions](decisions.md#the-macs-menu-bar-carries-the-apps-commands). |
| Draw the platforms the set claims | Not started | Design work: two platforms, neither drawn. |

### What needs a person at the Mac

Everything below was left because it can only be settled by looking at a window, and on the night of
2026-09-18 the display was asleep: every window counted as occluded, and SwiftUI draws no scrolling
content into an occluded window, so the sidebar and every list rendered blank. None of it was guessed
at instead.

- **The wide layout on a Mac — seen 2026-09-18**, in a real window on screen in both appearances:
  rooms with a room open, an empty detail, Outposts, your Outpost with the inspector, Search and You.
  It found one defect, now fixed: a sidebar row carrying a badge showed no selection on the Mac.
  Not seen: the window as the key window, so the focused selection color and a keyboard path.
- **The menus against a window.** Their structure was dumped from a windowless probe; with a window
  in front, New Room, the Conversation menu's items, ⌘1 onward and ⌘F should all enable and act.
- **Escape on a sheet — measured.** It leaves *New room* on the Mac, cursor in the field or not.
- **Return and Shift-Return — done 2026-09-18.** Return sends; Shift-Return and Option-Return write a
  line, measured on the real field — [Decisions](decisions.md#shift-return-writes-a-line-on-the-mac).
- **Sheets.** Every sheet goes through `sizedSheet`, which gives it a form size on the Mac: macOS
  sizes a sheet to its content, and a `List`, a `ScrollView` or a `TextEditor` has no natural height.
  Seen on Griff's Mac 2026-09-18 as the notifications explainer arriving as a lone *Continue* bar.
  `Scripts/lint/sheet-sizing.py` fails a bare `.sheet(`. Fixed after that screenshot; not yet seen fixed.
- **Titles.** Three screens printed their title twice on the Mac, once from the window and once from a
  `.principal` item. Fixed; the conversation's member count moved to the window subtitle.
- **The field's border while typing.** An observed behavior, so it needs observing.
- **A full keyboard path** through sidebar, list and detail, with a visible focus ring on every stop.
- **The icon at 16 points.** A design call: a simpler mark for the smallest sizes, or live with it.
- **The Settings window.** Each pane is the system's grouped form, as tall as what it holds up to
  620 points — [Decisions](decisions.md#on-the-mac-a-settings-page-is-the-systems-grouped-form).
  Every pane was drawn offscreen in both appearances; the real window's toolbar, and a page pushed
  inside a pane, were not.
- **The mailbox count on glass**, in light and dark. An offscreen window draws no Liquid Glass.

## What it would cost to offer them

Twelve acceptance criteria are open across the epic, and two are met. That is the smallest part of
the bill. The rest is what a second platform always is:

- **A design pass that is not a stretched phone.** Every screen in this app was drawn against iPhone
  boards, and the HIG's answers differ by platform — a sidebar is not a tab bar, a context menu is
  not a long press, and a pointer is not a thumb.
- **A second rig.** Everything crossing the network is unproven until two devices on two accounts
  have run it, and none of the current proofs were run on a Mac.
- **A second store listing**, its own screenshots, and copy that stops saying iPhone.
- **The same-account, two-device path**, which is hardware-only and is the one thing a Mac makes
  urgent: a member with a Mac and a phone is exactly the case the sibling feed exists for, and it has
  never been seen working on real hardware.

None of that is hard. All of it is a second product's worth of care, which is why it waits.
