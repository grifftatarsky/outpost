---
title: Desktop
layout: default
parent: Roadmap
nav_order: 7
---

# Mac and iPad

{: .no_toc }

The Mac and iPad as first-class, rather than a stretched phone.

1. TOC
{:toc}

## Where this stands

{: .warning }
> **The product is an iPhone app until TestFlight.** Griff's ruling, 2026-09-13. The set claims three
> platforms and draws one, and every decision in this epic is Claude's, taken against iPhone boards —
> so the claim changed rather than the app. The listing, the site and the docs say iPhone. The Mac
> window keeps working because Griff uses it; it is not offered, described or supported. Everything
> below is what it would take to change that.
>
> **Sequenced after TestFlight** since 2026-09-14, and lifted out of the iPhone roadmap into
> [the desktop roadmap](../desktop-roadmap.md), which is the status of record for this epic.

The Mac runs, in a window, with three columns and a sidebar that folds, and its keychain behaves like
iOS's rather than the legacy file-based one; without that, a Mac and an iPhone carried two different
identities while claiming to be one member. What is left is polish, and one structural gap blocked
on another epic.

Every ticket on this page, with its status and what was actually observed, is on the
[Roadmap](../roadmap.md#where-everything-stands).

## Tickets

<details markdown="1" id="the-mac-window-feels-like-a-mac-app">
<summary><b>The Mac window feels like a Mac app</b> — Incomplete</summary>

**Story.** As somebody using this on a Mac, I want the app to behave the way Mac apps behave, so that
it does not read as an iPad app in a window.

**Acceptance criteria**

- **Done.** A window with three columns and a sidebar that folds; collapsing it leaves a way to change
  destination, built as a setting.
- **Done.** The split-view detail pane carries the room actions. It was building its room screen without any
  of them, so the Mac and iPad had no invite control at all; fixed 2026-09-01.
- **Not done.** Return sends; Shift-Return makes a new line. Shared with *Sending feels like sending*; do it
  once.
- **Not done.** The message field's border does not flicker while typing.
- **Built, not seen.** The new-post sheet does not collapse. It had no size of its own and a text editor
  has no natural height; it asks for `.presentationSizing(.form)` on the Mac since 2026-09-18.
- **Not done.** A full keyboard path through sidebar, list and detail, with a visible focus ring on every stop;
  column order follows reading order.

**Testing**

- Device: the Mac builds and runs. The parity steps of the test plan have not been driven.

**Design.** Boards 15 (Desktop Wall) and 46 (Desktop feed), the only two boards for iPad and Mac in
the set; 85 for the system navigation bar. The flicker and the sheet's collapsed state are platform
behaviors the set does not draw.

</details>

<details markdown="1" id="the-app-icon-on-macos">
<summary><b>The app icon on macOS</b> — Built, not seen in the Dock</summary>

**Story.** As somebody with this in their Dock, I want the icon to look like it belongs there, so
that the app does not look unfinished before it opens.

**Acceptance criteria**

- **Done.** The Mac icon renders with no dark fringing at every size the Dock and Finder use — checked in
  the compiled `.icns` at 16, 32, 128 and 256 against dark and light grounds, 2026-09-18. It is an Icon
  Composer document, `AppIconMac.icon`, scoped to the macOS SDK. At 16 points the full mark does not read.
- **Done.** The dark-appearance variant is handled by whatever macOS actually supports — Icon Composer's
  dark appearance, rendered with `ictool`. Not seen in a Dock set to dark.
- **Done.** The alternate icons offered on iOS are not offered on macOS: they were already compiled for iOS
  only, and the *App icon* row under Appearance is hidden where icons cannot change.

**Testing.** Nothing yet. **Design.** Board 83: seven icons on the seven accents, plus a plain one for
a home screen that should not announce what the app is, which the board names as the only reason the
feature is worth having.

<details markdown="1">
<summary>Record — the mark exists, and one naming inconsistency</summary>

Blocker D1 was raised against the eight files the design pass was handed, full lockups, dark only,
one per accent; a correct statement about those eight and a wrong conclusion about the brand assets.
Superseded 2026-08-19: the mark is one template vector, `OutpostLogo` in `CarpenterUI`'s asset
catalog, tinted in code, so appearance and accent are not files.

The source SVGs spell it `verdegris`; everything else spells it `verdigris`. Nothing resolves the SVGs
by name at runtime, so it breaks nothing today; it matters at the point somebody regenerates the icon
sets from source. Rename the files.

</details>

</details>

<details markdown="1" id="the-desktop-wall">
<summary><b>The desktop wall</b> — Built, not seen</summary>

**Story.** As somebody using this on a Mac, I want the third column to be worth having, so that the
extra space earns itself.

**Acceptance criteria**

- **Built, not seen.** An audience rail in the third column, stating who will collect a post as a fact:
  an inspector beside your own Outpost holding *Who sees your Outpost*, open by default and hidden with
  ⌥⌘I. "Permanent" became "open unless you close it", following the HIG —
  [Decisions](../decisions.md#the-desktop-wall-is-an-inspector-open-by-default-and-hideable).

**Testing.** Nothing yet. **Unblocked 2026-09-07**:
[Per-person Outpost access](rooms-and-membership.md#per-person-outpost-access) landed, so the rail
now has something to show. Board 90's rail was explicitly deferred to here rather than built with
it — a rail sits beside an Outpost composer, and this platform has no wall to put one beside. The
fact it carries, who will collect this, is already said under the composer on iPhone in the words
board 90 asked for; what is missing is the third column that would hold it. **Design.** Boards 15,
90.

</details>

<details markdown="1" id="a-settings-window">
<summary><b>A Settings window</b> — Built, not seen</summary>

**Story.** As somebody using this on a Mac, I want settings where every Mac app keeps them, so that
the main window is for the people in it.

**Acceptance criteria**

- **Built, not seen.** ⌘, opens a Settings window with a toolbar of panes, titled by pane and reopened
  on the last one: Appearance, Behavior, Notifications, Privacy & Safety, Outposts, Devices, Data.
- **Built, not seen.** Each pane is the page the iPhone pushes from You, built by the same `var`, so
  the two cannot drift. You on the Mac keeps your name, People, Supporter, your Outpost and help, and
  gains a *Settings* row.
- **Built, not seen.** A change made in Settings shows in the main window at once: both scenes share
  one `AppShell` and one set of preference stores —
  [Decisions](../decisions.md#the-mac-has-a-settings-window-built-from-the-same-pages).

**Testing.** Builds for both platforms; the suite is green and covers none of it. Needs a person at
the Mac: every pane, and a page that pushes inside a pane.

</details>

<details markdown="1" id="whats-waiting-in-the-toolbar">
<summary><b>What's waiting, in the toolbar</b> — Built, not seen live</summary>

**Story.** As somebody using this on a Mac, I want to see from any screen that something is waiting,
and get to it, so that I do not have to walk the sidebar.

**Acceptance criteria**

- **Built.** The filled mailbox, without its antenna, in the window's toolbar, opening a popover of
  rooms with something unread and Outposts with something new.
- **Built, not seen live.** A count on it that is the Dock's number exactly, shown only while the
  system has badges on for the app. A hand-drawn count departs from the HIG, which is recorded —
  [Decisions](../decisions.md#the-mac-toolbars-mailbox-carries-a-hand-drawn-count-and-only-when-badges-are-on).

**Testing.** `BadgeCountTests` holds the number. The count's placement was rendered in an offscreen
window at 3, 12 and 99+ and is not clipped; Liquid Glass and dark mode were not drawn there.

</details>

<details markdown="1" id="the-menu-bar">
<summary><b>The menu bar</b> — Built, structure measured</summary>

**Story.** As somebody using this on a Mac, I want every command in the menu bar with a shortcut, so
that I can find what the app does and do it from the keyboard.

**Acceptance criteria**

- **Built.** File: New Room… ⌘N, New Solo… ⇧⌘N, Join with an Invite…. View: sidebar, and Who Sees Your
  Outpost on ⌥⌘I. Go: All Outposts, Your Outpost, You, rooms on ⌘1–⌘9. Help: How This Works.
- **Built.** A command that cannot act is disabled, not hidden, and a show/hide item names what it will
  do — [Decisions](../decisions.md#the-macs-menu-bar-carries-the-apps-commands).
- **Built, not seen.** A compose button in the sidebar reaches the same sheets as the menu, built once
  with the iPhone's.

**Testing.** A windowless probe dumped the menu bar the package builds. Enabled items against a real
window, the compose button and the help window need a person at the Mac.

</details>

<details markdown="1" id="the-wide-layout">
<summary><b>The wide layout, on a Mac and an iPad</b> — Built; iPad walked, Mac not seen</summary>

**Story.** As somebody on a Mac or an iPad, I want the screen used like the platform uses it, so that
the app is not an iPhone stretched wide.

**Acceptance criteria**

- **Built, walked on an iPad.** Three columns: areas, the iPhone's own list for the area, what is
  open. Upright the sidebar steps aside; at an accessibility text size an iPad uses the tabs —
  [Decisions](../decisions.md#the-mac-and-an-ipad-at-full-width-share-one-layout-areas-a-list-and-what-is-open).
- **Built, measured on an iPad.** ⌘N, ⇧⌘N and ⌘1 onward from a keyboard; the area is restored on
  launch.
- **Built.** Copy names the device and says click on a Mac; swipe-only actions have context menus —
  [Decisions](../decisions.md#copy-names-the-device-says-click-on-a-mac-and-a-hint-never-names-a-gesture).
- **Not seen on a Mac.** The screen was locked for the whole pass.

**Testing.** `WideLayoutTests` (opt-in, iPad) and `WideAreaTests` (suite). See
[Testing](../testing.md).

</details>

<details markdown="1" id="draw-the-platforms-the-set-claims">
<summary><b>Draw the platforms the set claims</b> — Not started</summary>

**Story.** As the designer and whoever builds from the set, I want iPad and Mac drawn rather than
inferred, so that two of the three platforms stop being decided by whoever implements them.

**Acceptance criteria**

- **Not done.** The Mac's three-column behavior is drawn: what each column holds, what collapsing does, where
  focus goes.
- **Not done.** iPad is drawn as its own thing rather than as a wide iPhone or a narrow Mac.
- **Not done.** Where the implementation already answered a question, the board ratifies or overrules it
  explicitly.
- **Not done.** Anything the boards decline to cover is named, so it is a known gap rather than a silent one.

**Testing.** Not applicable; this story is the design work. The Mac layout was decided by
implementation and there is nothing to check it against, which is a live risk rather than a
complaint about coverage.

</details>

## Test plan

<details markdown="1">
<summary>A Mac and at least one iOS device</summary>

Same Apple Account for the identity checks, different accounts for messaging.

**Identity across platforms.** Create an identity on the Mac; the iPhone adopts it; they are one
member with one set of rooms. Confirm the item is in the data-protection keychain, not
`login.keychain-db`; two identities claiming to be one member is the failure this prevents, and it is
silent.

**The window.** Resize from narrow to wide without losing the current conversation. Collapse the
sidebar and still change destination. Type a long message: the field grows, the border does not
flicker. Return sends; Shift-Return makes a line.

**Parity.** Send from the Mac; it arrives on iOS with the same marks and the same notification
behavior. Leave the Mac open and idle while the iPhone sends; it arrives without the window being
touched. `scenePhase` does not reliably flip on macOS, which is why this is a listed check.

</details>

**What would falsify the epic.** A Mac and a phone that are the same member and disagree about their
rooms. A message that arrives on one platform and not the other. A Mac left open that never learns
anything.
