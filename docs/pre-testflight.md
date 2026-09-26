---
# COPY BEGIN 57d4dc21 [NEEDS HUMAN REVIEW]
title: Before TestFlight
layout: default
nav_order: 10
---

# Before TestFlight

{: .no_toc }

The list that has to be empty before a build goes to anybody who is not the developer. Started
2026-09-04, when photos, clips, reporting and blocking landed in one afternoon and half the app's
copy went stale in the same afternoon.

The rule this list enforces is the honesty rule in [CLAUDE.md](../CLAUDE.md): **present tense means
it is in the build.** A sentence in the app that describes something the app does not do — or
fails to describe something it now does — is a defect of the same kind as a delivery mark that
lies, and it ships invisibly because the English build looks fine.

1. TOC
{:toc}

<!-- COPY END 57d4dc21 -->

<!-- COPY BEGIN 04dcaec6 [NEEDS HUMAN REVIEW] -->

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
| App Store metadata, age suitability page | Rating 13+, review notes as in [App Store](app-store.md#5-review-notes). | **Partly.** The copy is drafted and current — [app-store.md](app-store.md) has the listing, the nutrition label, the age rating and the review notes, and the site's age-suitability page exists. What is left is **entering it into App Store Connect**, which needs Griff's account and is not something that can be done from here. |
| How it works, invitations | "By default that invitation is enough" stopped being true when an invitation became an offer. | **Done.** Rewritten 2026-09-15. It now separates the two questions it was running together: whether anybody else in the room has to approve (by default, no), and the characters you and your inviter read to each other, which happen whatever the room's policy is. |
| The marketing site | Support, How it works, Status and FAQ all say recovery through nominated friends is designed and not built. It was refused on 2026-09-09. | **Done.** 2026-09-15, in `outpost-site`. All four now say refused rather than pending, with the reasoning. **And the status page was stale the other way too**: seven things marked *Later* are built and tested — photographs, direct messages, per-person Outpost access, removing somebody, notification previews, search, and editing or deleting a post. Understating is the same defect as overstating. |

<!-- COPY END 04dcaec6 -->

<!-- COPY BEGIN 68adf3d4 [NEEDS HUMAN REVIEW] -->

## Permissions, explained before they are asked

Each system prompt is explained in the app's voice first — what is asked for, why, and what the app
does if the answer is no. None of them is asked at cold launch. A view shown just before a
system prompt has one button and cannot be dismissed — the HIG's pre-alert rule, applied 2026-09-16.

| Permission | When | Explained | Behavior on refusal |
|---|---|---|---|
| Notifications | Once the account is ready, on the first ready screen | **Done.** `PermissionExplainerView(.notifications)`, seen on both simulators at first ready screen, 2026-09-04. One button, *Continue*, and since 2026-09-16 it cannot be swiped away before Apple's prompt — the HIG's pre-alert rule. The no is given to Apple. | Messages arrive when the app is opened; nothing announces them. Said in the sheet, and in the Notifications footer of You since 2026-09-05. |
| Photos | Never asked. `PhotosPicker` is out-of-process; the system shows the library and hands over only what is picked. The first tap of ➕ explains this once. | **Done.** `PermissionExplainerView(.photos)`, seen on the rig 2026-09-04; *Choose a photo* opened the system picker, whose own banner read "Private Access to Photos". There is no API that narrows the system's library prompt to limited-only — the app simply never triggers that prompt. | Nothing to refuse; closing the picker sends nothing. |
| Camera | The first tap of **Scan** on *Join a room*, after the member has answered *Turn on scanning* to a question on that screen, or turning on **Behavior ▸ Scan invites with the camera**. Never at launch. | **Done.** In the app's words, and kept apart from the prompt, because the HIG forbids a way out of a view shown just before one ([Decisions](decisions.md#how-the-ask-and-the-higs-pre-alert-rules-both-hold)). The setting is saved on only once the camera is allowed. Usage string: "The camera reads the QR code on an invite somebody shows you, and the app keeps nothing else it sees." Seen on the rig 2026-09-16 up to the prompt, which a simulator never raises. | Paste stays, the setting is saved off, and the app says the camera is off with *Open Settings*. **Not yet seen on a phone.** |

<!-- COPY END 68adf3d4 -->

<!-- COPY BEGIN 33d9678e [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 33d9678e -->

<!-- COPY BEGIN dd229921 [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END dd229921 -->

<!-- COPY BEGIN c0f35cfb [NEEDS HUMAN REVIEW] -->

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
  [Proofs a rig cannot run](proofs-a-rig-cannot-run.md).
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

<!-- COPY END c0f35cfb -->

<!-- COPY BEGIN 594017ad [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 594017ad -->

<!-- COPY BEGIN a5e88687 [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END a5e88687 -->

<!-- COPY BEGIN acec3562 [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END acec3562 -->

<!-- COPY BEGIN 10a9563c [NEEDS HUMAN REVIEW] -->

## The marketing site

Added 2026-09-16, from Griff.

- **Done.** **The full rewrite**, 2026-09-17. The 84 design boards are deleted. `/screens` is ten
  screenshots of the running app, taken per accent in light and dark by `npm run shots` driving the
  app's own debug-only site-shot host — [Decisions](decisions.md#the-marketing-site-is-photographed-not-drawn).
  Every page's copy was checked against the code; `/roadmap` and `/bullet` are written. What the
  rewrite corrected is in the commit, and the short version is that the site claimed iPad and Mac,
  no media, a six-character phrase, unbuilt Solos, unbuilt blocking and a dollar-a-month
  subscription, and five of its seven accent values did not match `Accent.swift`.

<!-- COPY END 10a9563c -->

<!-- COPY BEGIN 99ff2cb8 [NEEDS HUMAN REVIEW] -->

## Before the source is public

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

<!-- COPY END 99ff2cb8 -->

<!-- COPY BEGIN cd0fafa6 [NEEDS HUMAN REVIEW] -->

## CloudKit, before the first real build

- **Done.** **The schema exists and is written down.** `CloudKit/schema.ckdb`, imported into
  development 2026-09-18. It had to be written rather than deployed from inference: the development
  environment was exported on Griff's ask and held one record type, `Users`, the stock one. Nothing
  the app writes had ever reached it — the rig runs against `FileMailbox` and the live suite is
  opt-in behind `CARPENTER_CLOUDKIT_TESTS`. Deploying development to production would have deployed
  nothing and looked like it worked.
- **Open, and his.** **Deploy development to production**, in the Console, for
  **`iCloud.com.microgpt.outpost`**. Check with
  `xcrun cktool export-schema … --environment production | grep "RECORD TYPE"` — six lines, not one.
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
- **Open.** **A real write has never been proven against the schema.** The live suite is what would
  settle it and it cannot run: alpha answers `CKError 36, Account Temporarily Unavailable`. Sign it
  back in, then `TEST_RUNNER_CARPENTER_CLOUDKIT_TESTS=1 xcodebuild test … -only-testing:CarpenterTests`
  — the `TEST_RUNNER_` prefix is not optional, because xcodebuild does not forward the shell
  environment into the test process and without it every live test skips and reports success.
- **Done.** **A Release build talks to the production APNs gateway.** `aps-environment` was
  hard-coded to `development` in `Carpenter.entitlements` and one file serves both configurations, so
  the TestFlight build would have registered, been accepted and received nothing. It comes from
  `APS_ENVIRONMENT` in `Branding.xcconfig` with a `[config=Release]` override now, verified through
  `-showBuildSettings`.
- **Open.** The App ID needs `iCloud.com.microgpt.outpost` enabled on it, or automatic signing has
  nothing to build a distribution profile from. Not exercised yet — every build so far has been
  `CODE_SIGNING_ALLOWED=NO` or a simulator.

<!-- COPY END cd0fafa6 -->

<!-- COPY BEGIN 5f374b31 [NEEDS HUMAN REVIEW] -->

## Operational

- **Changed.** **No address is published anywhere.** Griff, 2026-09-17: delete the abuse mailbox; the only
  way to reach a person is a form. `abuse@` and `info@` are gone from the site and from the app —
  eleven `mailto:` links across the legal pages, the footer, support, security and accessibility now
  point at `/contact`. `CMS_REPORT_TO` and `CMS_MESSAGE_TO` still name mailboxes, but they are where
  the service *delivers*, not somewhere anybody is invited to write. **What this leaves:** App Store
  Connect still wants a contact address of its own, which is his and never the app's, and somebody
  who cannot use a web form has no route at all. The phone number on `/support` and `/accessibility`
  is the remaining non-form route and it is deliberate — see
  [Decisions](decisions.md#every-route-to-a-person-is-a-form-and-no-address-is-published).
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
  ([Decisions](decisions.md#the-source-is-published-under-the-mozilla-public-license-20)). Publishing
  it is still to happen with the build — [App Store §3](app-store.md#3-export-compliance) rests the
  export position on it.
- **Done.** **`ITSAppUsesNonExemptEncryption` is `true`** in `App/Carpenter/Info.plist`, 2026-09-17, as
  [App Store §3](app-store.md#3-export-compliance) says. App Store Connect still asks Apple's
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

<!-- COPY END 5f374b31 -->
