---
# COPY BEGIN 2d97bebc [NEEDS HUMAN REVIEW]
title: Notifications
layout: default
parent: Roadmap
nav_order: 2
---

# Telling someone it arrived

{: .no_toc }

Telling somebody a message arrived, and nothing else.

1. TOC
{:toc}

<!-- COPY END 2d97bebc -->

<!-- COPY BEGIN ccb9afee [NEEDS HUMAN REVIEW] -->

## Where this stands

Three subscriptions, each scoped to a record type, exactly one visible. Everything up to the push
leaving CloudKit is built and observed on the rig. A push has never arrived on a simulator; Griff saw
a banner arrive on a phone from the other account on 2026-09-09, and nothing downstream of a push has
been watched since. Statuses are
defined on the [Roadmap](../roadmap.md#how-to-read-this).

Every ticket on this page, with its status and what was actually observed, is on the
[Roadmap](../roadmap.md#where-everything-stands).

<!-- COPY END ccb9afee -->

<!-- COPY BEGIN 2dd0043a [NEEDS HUMAN REVIEW] -->

## Tickets

<details markdown="1" id="a-bell-that-rings-for-a-message-and-nothing-else">
<summary><b>A bell that rings for a message and nothing else</b> — Complete (hardware proof owed)</summary>

**Story.** As a member, I want a banner when somebody sends me a message and for nothing else, so
that a notification means something.

**Acceptance criteria**

- **Done.** Three subscriptions, each scoped to a record type, exactly one visible: the inbox (silent,
  packets), the sibling feed (silent), the bell (visible, `MessageBell`, on this member's own zone).
- **Done.** A sender writes a bell into the recipient's zone only when it has put a real message there for
  them. Reactions, grants, acknowledgments, renames and admissions ring nobody.
- **Done.** The notification service extension decrypts locally and names the room and the sender.
- **Done.** Both databases are swept of any subscription not in the channel table, so a stale visible one
  from an older build cannot restore the old behavior.

**Testing**

- Suite: the push-channel table test, exactly one channel visible and every channel scoped.
- Two accounts, 2026-09-02: the sender's half works (`mailbox: rang a peer's bell`); the display
  half works (an injected push drew correctly with the app's icon); the middle does not: nothing
  arrived with the recipient backgrounded, and no log activity at all.
- Hardware: Griff reported a banner arriving on a phone from the other account's bell on 2026-09-09.
  Not watched again since the extension changed.

<!-- COPY END 2dd0043a -->

<!-- COPY BEGIN b9158b0a [NEEDS HUMAN REVIEW] -->

<details markdown="1">
<summary>Record — the unverified assumption, the cascade, and what 2026-09-02 settled</summary>

**One assumption underneath this has never been tested:** does a zone subscription on your own
private database fire when a share participant writes into your zone? It follows from how the
databases are defined, and the device-sync subscription already behaves this way. If it turns out
not to, the fallback is a database subscription on the shared database, still scoped to
`MessageBell`, with the sender writing the bell into its own zone; that costs one spurious banner
for peers who share the sender's outbox but not the room, and changes two files.

**Fixed on the way here:** a cascade where reading a message notified everybody else that there
was one; an extension that wrote to CloudKit on every push; a keychain group that could never
resolve; a collapse id that made every message replace the last unread one. The previous
arrangement was a single unscoped visible subscription on the shared database, which fired on every
write to every accepted zone: in a room of three, one banner for the message and one more for each
acknowledgment, grant and share offer.

**What 2026-09-02 does not settle, and must not be written down as if it did.** `simctl push`
injects a notification locally and never touches APNs, so it proves the device can display a push
and says nothing about whether it can receive one. The failure is isolated to "CloudKit did not
deliver", and whether that is a simulator limitation or the container's push configuration cannot
be told apart from this rig. The message itself appeared the instant the app was foregrounded, so
delivery is unaffected.

</details>

</details>

<!-- COPY END b9158b0a -->

<!-- COPY BEGIN cafc1f98 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="notification-previews">
<summary><b>Notification previews</b> — Complete (hardware proof owed)</summary>

**Story.** As a member, I want to choose how much of a message appears on my lock screen, so that
somebody glancing at my phone does not read my conversations.

**Acceptance criteria**

- **Done.** Four rungs, each previewed as the banner it produces, composed by the same code the extension
  uses, so the preview cannot drift from the thing it previews.
- **Done.** The ladder is monotonic: each step down discloses strictly less.
- **Done.** Per room, following the default until told otherwise, and naming the default it follows rather
  than reading as unset. Reachable from the room's menu.
- **Done.** The quietest rung does not group by room, because a thread identifier is itself a disclosure.
- **Done.** The rung is applied when the copy is composed, never by suppressing afterwards.
- **Done.** A photo or clip is announced by its caption or as "📷 Photo" or "🎬 Video", never by the
  picture.

**Testing**

- Suite: the ladder's monotonicity test.
- Device: the screen and its previews seen. The banner the extension composes is unproven for the
  same reason as the bell.

**Design.** The four rungs, drawn as the banners each produces.

<!-- COPY END cafc1f98 -->

<!-- COPY BEGIN 73c7dc65 [NEEDS HUMAN REVIEW] -->

<details markdown="1">
<summary>Record — the rungs, the limit, and why per member rather than per device</summary>

**Done 2026-08-18.** The per-room screen existed and nothing reached it until 2026-08-19; the room
menu in a conversation now carries Notifications, hidden where a room has no actions at all.

| Rung | Banner | What it gives away |
|---|---|---|
| Room, sender and message | Hangar 7 / Alice / are you coming | Anyone who can see the screen can read what was said. |
| Room and sender | Hangar 7 / Alice | Who is talking to you, and where, but not the words. |
| Room only | Hangar 7 | Which conversation is moving, and nothing about who. |
| That a message arrived | New message | Only that the app has something for you. |

**The limit, stated where the choice is made:** the banner is put together on this device after it
decrypts the message, so nothing readable crosses the network. But the finished banner goes into the
operating system's notification store, and this app cannot reach in and remove it. Choosing less is
the only way to keep something out of that store.

Stored in `MemberPreferences`, so it follows the member across their devices. Per device was
considered, a phone in a pocket and an iPad on a kitchen table not being the same risk, and set
aside: a room's sensitivity does not change between a member's own devices, and configuring it twice
is how one gets forgotten.

</details>

</details>

<!-- COPY END 73c7dc65 -->

<!-- COPY BEGIN 9deefa57 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="unread-and-the-number-on-the-icon">
<summary><b>Unread, and the number on the icon</b> — Complete (tested)</summary>

**Story.** As a member, I want the app icon and the rooms list to agree with what I have actually
read, so that a badge means something.

**Acceptance criteria**

- **Done.** A room has something unread when the transcript holds a message from somebody else, after the
  last entry this device showed, that this device would actually draw. Each clause has a test.
- **Done.** The mark is per device and is not the read receipt; the two were one call and are split.
- **Done.** The badge is the number of rooms with something unread, set when the count changes, not after
  a sync.
- **Done.** Reading clears it on the viewport rule read receipts use. *Mark as Read* moves the mark and
  tells nobody.
- **Done.** Unread is a dot that is present or absent and announced either way, never carried by color
  alone.

**Testing**

- Suite: one test per clause of the definition.
- Two accounts, 2026-09-02: Alpha sent; Beta's row grew a dot and the icon carried a 1; Beta opened
  the room and went to the home screen; both were gone with no sync between.
- Owed: the extension setting the badge when the app never opens rides on a push arriving.

**Design.** Boards 02, 34 (pinned variant), 92.

<!-- COPY END 9deefa57 -->

<!-- COPY BEGIN e56ba89c [NEEDS HUMAN REVIEW] -->

<details markdown="1">
<summary>Record — why the mark is not the receipt, and what it costs</summary>

Telling the room how far you have read is a disclosure about yourself and is opt-in. This device
remembering how far it has drawn reaches nobody. `markSeen` used to run them as one, gated on the
receipt opt-in, so the dot and the badge would have worked only for members who had agreed to be
reported on, and been stuck on forever for everybody else.

The mark lives in `PersistedState.readThrough`, device-local like `greetedRooms` and unlike
`preferences`: a read mark moves as fast as somebody's eyes, and `preferences` travel on a sibling
feed republished whole, carrying every room key, on every change. The cost is that reading a room on
the phone leaves the dot on the iPad, written down rather than discovered.

*Mark as Read* in the room's context menu is reachable for the first time; it was written behind
`if room.hasUnread`, which was never true.

</details>

</details>

<!-- COPY END e56ba89c -->

<!-- COPY BEGIN 02f59010 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="asking-for-notifications-honestly">
<summary><b>Asking for notifications honestly</b> — Complete (tested)</summary>

**Story.** As a new member, I want to be told what the app will ask for and what happens if I say
no before the system asks, so that the prompt is not a surprise.

**Acceptance criteria**

- **Done.** A sheet in the app's voice on the first ready screen, never at cold launch: what is asked (a
  banner for a message, a count on the icon, nothing else), and what refusing costs (messages still
  arrive every time the app is opened; nothing announces them). One button, *Continue*, and since
  2026-09-16 it cannot be swiped away before Apple's prompt: the no is given to Apple.
- **Done.** The Notifications footer in You says what refusing costs.
- **Done.** How it works no longer describes the badge-only era.

**Testing**

- Device: seen on both simulators at first ready screen, 2026-09-04.

**Detail.** [Before TestFlight](../pre-testflight.md#permissions-explained-before-they-are-asked).

</details>

<!-- COPY END 02f59010 -->

<!-- COPY BEGIN d9be335f [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="tapping-through-and-what-happens-next">
<summary><b>Tapping through, and what happens next</b> — Complete (hardware proof owed)</summary>

**Story.** As a member, I want a notification to take me to the conversation it was about, so that
the notification is a door rather than an announcement.

**Acceptance criteria**

- **Done.** Tapping opens the room and on iPhone brings the Rooms tab forward.
- **Done.** A generic banner, one the extension could not decrypt, opens the app without navigating rather
  than guessing.
- **Done.** Several notifications from different rooms are separately tappable, via `threadIdentifier`.
- **Done.** A notification for a room this member no longer has opens the app and navigates nowhere, which
  is the answer a generic banner already gets. A message since hidden needs nothing: the room opens
  and the message is simply not drawn, because `messages(in:)` filters it.
- **Done.** A notification tapped while already in that room does nothing at all.
- **Done.** The decision is `AppSession.tapping(_:whileViewing:)` rather than a guard inside a view, so it
  can be tested. The view does what it is told.

**Testing**

- Suite: `TappingThroughTests` — a room held, a room since left, the room already on screen, a
  thread that names nothing, and another room while in one.
- Device: not driven, because no push has arrived on the rig. `threadIdentifier` is to be verified
  on a device.

**Design: needed** for the edge states. The happy path is conventional enough not to need one.

</details>

<!-- COPY END d9be335f -->

<!-- COPY BEGIN c1b58e4b [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="a-banner-from-a-person">
<summary><b>A banner from a person</b> — Complete (hardware proof owed)</summary>

**Story.** As a member, I want a message's banner to look like a message from a person — their face,
their name — so that Focus treats it as one and my lock screen reads like a conversation.

**Acceptance criteria**

- **Done.** At the two levels that name the sender, the extension attaches the sender to the banner as a
  communication: their name as this device knows them, the photo it keeps or they shared, and the
  conversation it belongs to — the room's name for a room, nobody's for a solo.
- **Done.** The quieter levels attach nothing, so a banner that was meant to say less says nothing more.
- **Done.** The capability is the app's and the extension's; no Apple approval is needed for it.
- **Done.** Nothing is done for Focus's *allowed people*: the people here are not in Contacts, and the app
  does not pretend they are.

**Testing**

- Suite: none; the intent is built in the extension against the system's types.
- Device: not seen. No push has been watched arriving on the rig since this landed; the proof is a
  banner on a locked simulator with a face on it.

**Design.** Messages' banner.

</details>

<!-- COPY END c1b58e4b -->

<!-- COPY BEGIN 0ce85551 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="silenced-notifications-shared">
<summary><b>Silenced notifications, shared</b> — Complete (tested)</summary>

**Story.** As a member, I want the people I write to to know when I have notifications silenced, in
words of my choosing, so that they do not wait on a reply that is not coming — and I want to see
theirs.

**Acceptance criteria**

- **Done.** *Share when I've silenced notifications*, under Send, off by default. Turning it on asks the
  system for Focus status; the app reports that status to the session when it becomes active and
  after every round, and the session writes it to every room as an entry per change.
- **Done.** *Do Not Disturb message*: the stock words, or *Use custom message* and a line of the member's
  own, cut to sixty characters, previewed as others will see it. Changing it while silenced says it
  again.
- **Done.** *Show others' silence*, under Receive, off by default. On, a solo shows a line over the field
  while the other person is silenced: the moon, and their words or *Do Not Disturb*.
- **Done.** Turning sharing off tells every room that was told of a silence that it is over. A room never
  told is not told it ended. A room made during a silence is told of it.
- **Done.** Haptics and everything else are untouched; the line is the whole of it.

**Testing**

- Suite: `FocusStatusTests` — shared only where shared and shown; the custom message travels, is cut,
  and is said again; sharing off clears; a late room is told; the body never carries words for a
  silence that is over.
- Device: 2026-09-06 — beta granted the Focus prompt, *Pretend a Focus is on* on beta, and *Do Not
  Disturb* with the moon over alpha's field on the next round; then a custom line typed on beta,
  *Heads down till six*, in its place on the round after. A simulator has no Focus of its own, so
  the system half — the prompt aside — has not been seen; the debug row stands in for it.

**Design.** Messages' "has notifications silenced" line.

</details>

<!-- COPY END 0ce85551 -->

<!-- COPY BEGIN 75c6a08d [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="focus-filters">
<summary><b>Focus filters</b> — Complete (hardware proof owed)</summary>

**Story.** As a member, I want a Focus to decide which rooms may notify me and whether banners show
what was said, so that Work is Work without touching every room's setting by hand.

**Acceptance criteria**

- **Done.** The app offers a filter in Focus settings: *Only these rooms*, picked from the rooms this
  device knows, and *Show what was said*.
- **Done.** When the Focus turns on, the filter is written where the extension reads it; when it turns off,
  the system hands back the defaults, which are the neutral filter.
- **Done.** A room the filter leaves out is delivered as a passive banner saying nothing; with previews
  off, every room is capped at *Room and sender*. A room's own level is never raised.
- **Done.** The room picker answers without the session, from a directory the app refreshes after every
  round.

**Testing**

- Suite: `FocusFilterTests` — the neutral filter, the cap, the room left out, the round trip, the
  directory.
- Device: not seen. A simulator has no Focus settings, so the filter has not been attached to one.

**Design.** The system's Focus filter sheet.

</details>

<!-- COPY END 75c6a08d -->

<!-- COPY BEGIN 13ef2999 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="settings-split-by-what-rings">
<summary><b>Settings split by what rings</b> — Complete (hardware proof owed)</summary>

**Story.** As a member, I want the things that ring to be sorted by what they are, so that turning
off a wall I do not care about does not turn off the people writing to me.

**Acceptance criteria**

- **Done.** Notifications is one row on You that opens two pages: **Messaging** and **Outposts**. Each row
  says what it is set to without opening it — a level for messaging, a count for Outposts, *Off* for
  either.
- **Done.** Messaging holds *Tell me about messages* over the four preview rungs, and *Tell me about room
  updates* over how much an update says: who and where, where only, what only, or nothing. A room
  update is somebody joining, leaving, being removed, a rename, an invitation answered, or access
  changing.
- **Done.** Outposts holds new posts as one of three — *All posts*, *By Outpost* (only the walls turned on
  under the gear on an Outpost's own page), or *None* — then four switches: replies on posts I
  commented on, replies on posts I reacted to, comments on my posts, likes on my posts. Likes are the
  only one that arrives quietly; the rest interrupt.
- **Done.** Turning something off keeps what it was set to, so turning it back on returns the answer the
  member gave before.
- **Done.** The app icon's number has its own setting, on both pages, saying whether it counts messages,
  Outposts, both or neither. A line under it spells out in words what the number will mean.
- **Done.** With notifications off in iOS Settings, both pages say so and offer a way there, and what is
  chosen here is kept either way.
- **Done.** Alerts about a member's own account — a check-up, their history, their recovery key — stay
  inside the app on the You tab and never touch the icon's number, which means somebody is trying to
  reach you.

**Testing.** `NotificationLevelTests`, `BadgeCountTests`, `WhatTheTabsBadgeTests`,
`MessageNotificationTests`, `AnOutpostRingsTests`. Driven on the rig 2026-09-11 across both
accounts' settings. No real push has been watched arriving.

**Design.** Apple's guidance is that a badge is a number or an exclamation point and is reserved for
information a member would want to be interrupted for — which is why the icon's number can be told
what to count, and why the app's own housekeeping is not in it.

</details>

<!-- COPY END 13ef2999 -->

<!-- COPY BEGIN 55d3305b [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="asking-for-outpost-notifications">
<summary><b>Asking for Outpost notifications</b> — Complete (tested)</summary>

**Story.** As somebody who has just been let into a wall, I want to be asked once whether I want to
hear about it, rather than either being rung without being asked or never finding the setting.

**Acceptance criteria**

- **Done.** A step in onboarding, after the system permission is granted, naming the three things that would
  ring and saying that reactions stay off either way. Two answers: *Yes, tell me* and *Not for now*.
- **Done.** A gear on an Outpost's own page — *Get notifications for this Outpost* — so the answer can differ
  per wall without opening Settings.
- **Done.** The answer is remembered and the step is not offered again.

**Testing.** Seen on the rig 2026-09-11 on both accounts. No test covers the onboarding step.

</details>

<!-- COPY END 55d3305b -->

<!-- COPY BEGIN ec9de08b [NEEDS HUMAN REVIEW] -->

## What has actually been observed, 2026-09-02

<details markdown="1">
<summary>Two clean accounts, one room, permission granted on both</summary>

Both logs carried `bell: subscribed visibly for MessageBell on our own zone`.

**The sender's half works.** Alpha sent with Beta backgrounded. Alpha's log: `mailbox put: wrote a
packet addressed to 1 recipient(s)` then `mailbox: rang a peer's bell`. The bell was written into
the recipient's zone through the shared database.

**The display half works.** A notification injected with `xcrun simctl push` appeared correctly:
the app's own icon, its title and body, in Notification Center.

**The middle does not.** Between the bell being rung and Beta's screen, nothing happened. No banner,
no badge, nothing in Notification Center, and no log activity on Beta at all for three minutes. The
silent inbox subscription did not wake the app either, so it is not the bell specifically: no
CloudKit push of any kind arrived. The message appeared the instant Beta was foregrounded, at
`entriesReceived=1`.

**Standing that day:** the bell is written, the subscription is registered, the banner can be drawn,
and nothing arrived on its own. On 2026-09-09 Griff saw a banner arrive on a phone.

</details>

<!-- COPY END ec9de08b -->

<!-- COPY BEGIN fef3a188 [NEEDS HUMAN REVIEW] -->

## Test plan

<details markdown="1">
<summary>Two devices, two accounts, the receiving device locked</summary>

Both devices on a build from the same tree: subscription ids have changed more than once, and the
app sweeps subscriptions it does not recognize, so a device on an old build will keep deleting the
new device's subscriptions.

**Channel scoping.** Pull logs (`Scripts/pull-device-logs.sh`) and find the `push: registered`
block. Exactly one `VISIBLE` line; `recordType=nil` on any line is the original defect.

**The cascade.** Send one message: exactly one banner per recipient. Then leave every device open
and idle for two minutes: zero. Idle sync exchanges acknowledgments and grants, and none of that may
ring.

**Nothing but a message rings.** None of these may produce a banner: renaming yourself, reacting,
creating a room somebody is not in, renaming a room, admitting somebody, or a device collecting a
message.

**The banner itself.** Room name, sender name, message text; `nse: delivering a decrypted banner`
in the extension log, and `the generic banner` means decryption failed, so check the keychain group
first. Two messages from two people are two notifications. A message for the room already on screen
shows no banner.

**Declining notifications.** Turn them off entirely on B. Everything still arrives when B opens the
app, in order, with nothing lost, and the app does not nag or call it an error.

</details>

<!-- COPY END fef3a188 -->

<!-- COPY BEGIN a6a10f77 [NEEDS HUMAN REVIEW] -->

**What would falsify the epic.** A banner for something nobody said. A banner naming a message the
member has already read. Silence when somebody genuinely sent something. The first is noise, the
second is a lie, and the third is the feature not existing.

<!-- COPY END a6a10f77 -->
