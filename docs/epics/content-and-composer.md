---
title: Content and composer
layout: default
parent: Roadmap
nav_order: 6
---

# What you can send

{: .no_toc }

Text, photos, clips, reactions, and what the device does with what arrives.

1. TOC
{:toc}

## Where this stands

Text with formatting, and since 2026-09-04 photos and clips with captions, sent, sealed, fetched and
drawn across two Apple Accounts, screened on the receiving device. Reactions on posts, comments and
messages. Anything not built is drawn disabled rather than hidden, which is the honest treatment.

Every ticket on this page, with its status and what was actually observed, is on the
[Roadmap](../roadmap.md#where-everything-stands).

## Tickets

<details markdown="1" id="text-with-formatting">
<summary><b>Text, with formatting</b> — Complete (tested)</summary>

**Story.** As a member, I want emphasis in a message, so that a messenger's plainest expectation is
met.

**Acceptance criteria**

- **Done.** Emphasis applies to a selection and the selection is preserved afterwards.
- **Done.** Markers never appear in the rendered text on either device.
- **Done.** Fifty messages in one sync are still one packet, under the cap.

**Testing**

- Suite: the formatting round-trip tests.
- Two accounts: text proven daily; a formatted message has not been specifically watched.

</details>

<details markdown="1" id="photos">
<summary><b>Photos</b> — Complete (tested)</summary>

**Story.** As a member, I want to send a photo, so that the app covers the thing people mostly want
to send each other.

**Acceptance criteria**

- **Done.** Attached from the system picker, which is out of process and never asks for the library.
- **Done.** Scaled to 2048 on the long edge, JPEG, redrawn into a fresh context so no location, camera or
  time survives.
- **Done.** Sealed like everything else: a fresh content key inside the entry's sealed payload; the bytes
  as a `CKAsset` on their own record in the sender's outbox, deleted once the last recipient has
  collected, the packet's own rule.
- **Done.** The bubble is the right shape before a byte arrives, from the pixel size and a forty-pixel
  preview drawn blurred; a fetch that fails says so and retries on a thirty-second backoff; a photo
  the outbox let go of says *No longer available*.
- **Done.** Report a hold away; the report carries words and never media. The age rating is 13+.
- **Done.** On an Outpost: its own ticket below.

**Testing**

- Suite: twenty-nine tests across sealing, send, receive, sweep, loader and preparer. The test that
  caught the first version letting the Exif block through the thumbnail path holds
  `identifyingMetadata(of:)` to nothing identifying.
- Two accounts, 2026-09-04: 770 KB up from one account as an asset addressed to one recipient, the
  packet and the bell after it; the other fetched the same bytes, same fingerprint and size, and
  drew them in the received-bubble shape.
- Real account, 2026-09-15: the attachment record leaves the sender's outbox after the last
  acknowledgment, and not before.
- Owed: the sibling-device fetch by name from the member's own outbox is designed and needs two
  phones; a photo to a room of three over CloudKit needs a third account.

**Design: needed** for the bubble, the viewer and the blur; none of the boards shows an image, and
what is built is the messenger convention. Board 33 for storage.

<details markdown="1">
<summary>Record — what was built, and what is not built deliberately</summary>

Payload type 16 (`MediaBody`), `SealedAttachment`, the `MediaMailbox` seam and its CloudKit half,
`FileMediaStore`, `ImagePreparer`, `MediaLoader`, `MediaBubbleView`, `MediaViewerView` with the
system share sheet and pinch and double-tap zoom, and the composer's picker. Upload first, entry
second, so no entry ever names bytes that are not there; an orphan sweep once per launch for uploads
no entry names.

**Not built, deliberately.** Taking a photo with the camera: the picker asks no permission. (The
camera is used only to scan an invitation's QR code.) A trim on the Mac, which has no system trimmer.
Panning a zoomed photo was added on 2026-09-13 and has not been looked at.

The trust and safety design landed with photos: on-device screening with a switch, a local silent
block, a deny list in the binary, and the obligations written down in
[Trust and safety](../trust-and-safety.md).

</details>

</details>

<details markdown="1" id="clips">
<summary><b>Clips</b> — Complete (tested)</summary>

**Story.** As a member, I want to send a short clip, so that a moment can be sent as it happened.

**Acceptance criteria**

- **Done.** Up to a minute, with a longer clip sent to the system trimmer first; forty megabytes at the
  sealing ceiling.
- **Done.** Re-encoded at 960 × 540 through the system's `forSharing()` filter, so no location or device
  tag survives.
- **Done.** Drawn with its first frame, a play mark and its length in glass; played in the system player.
- **Done.** Screened as a file before its poster is drawn.

**Testing**

- Suite: `VideoPreparerTests`, with a fixture clip that carries a location tag and checks none of it
  survives.
- Two accounts, 2026-09-04: a five-second clip sent, screened as a video by the receiving device's
  analyzer before its first frame, played.

</details>

<details markdown="1" id="captions">
<summary><b>Captions</b> — Complete (tested)</summary>

**Story.** As a member, I want words to go with a picture, so that a photo can say what it is.

**Acceptance criteria**

- **Done.** A picked photo or clip waits in the composer as a tile inside the field's capsule with an ✕,
  the way Messages holds one.
- **Done.** One picture takes the words as its caption, drawn under it in the bubble. Several go first and
  the words follow as their own message, because a caption on the first of five reads as being about
  that one.

**Testing**

- Suite: `CompositionPlanTests`.
- Two accounts, 2026-09-04: *Ice plants in bloom* under the flowers on the other account.

</details>

<details markdown="1" id="trimming-a-long-clip">
<summary><b>Trimming a long clip</b> — Complete (hardware proof owed)</summary>

**Story.** As a member with a clip over a minute, I want to trim it in place, so that the limit is a
step rather than a wall.

**Acceptance criteria**

- **Done.** A red scissors-and-length badge on the tile; the tile opens the system's own trimmer with its
  maximum set so its handles cannot open wider; send is refused with a sentence until it has been.
- **Done.** Where the trimmer refuses the file, the fallback says to trim it in Photos and pick it again.

**Testing**

- Device: `canEditVideo(atPath:)` answers no on a simulator for every file, so only the fallback has
  been seen. The trimmer itself is a device proof still owed.

</details>

<details markdown="1" id="on-device-screening-and-the-blur">
<summary><b>On-device screening and the blur</b> — Complete (hardware proof owed)</summary>

**Story.** As a recipient, I want a sensitive photo blurred until I choose to look, so that what
arrives is mine to decide about.

**Acceptance criteria**

- **Done.** The system's analyzer runs on this device for photos and for clips as files; a switch under
  You › Privacy & Safety, on by default; the judgment never leaves the device.
- **Done.** A photo that was not screened is its own answer, drawn as an ordinary photo and explained in the
  Privacy & Safety footer. It is never called "clear".
- **Done.** The footer says what the analyzer can do on this device: available, off in system settings, or
  unsupported.
- **Done.** Revealing is remembered per photo.

**Testing**

- Suite: `MediaLoaderTests`, including that a disabled analyzer is not "clear".
- Two accounts: the analyzer ran on the rig, a real request on the waterfall and on the clip, and
  judged clear. The blur itself was driven with the debug switch. A positive verdict needs Apple's
  test profile on a device and has not been seen anywhere.

**Detail.** [Trust and safety](../trust-and-safety.md), decisions D1 to D3.

</details>

<details markdown="1" id="the-deny-list">
<summary><b>The deny list</b> — Complete (tested)</summary>

**Story.** As a member, I want known abusers dropped before I see them, so that a reported sender
does not get a second audience.

**Acceptance criteria**

- **Done.** SHA-256 fingerprints bundled in the binary with the date they were last changed; nothing is
  fetched; it changes when the app does.
- **Done.** A switch under Privacy & Safety; with it on, entries are dropped at receive.
- **Done.** Maintained by a script that appends and bumps the date.

**Testing**

- Suite: `BlockingTests.denyListSwitch`.
- Two accounts: no listed sender has written to the rig.

**Detail.** [Trust and safety](../trust-and-safety.md), decision D5.

</details>

<details markdown="1" id="reactions-on-messages">
<summary><b>Reactions on messages</b> — Complete (tested)</summary>

**Story.** As a member, I want to react to a message in a room, so that the fastest reply does not
have to be a message.

**Acceptance criteria**

- **Done.** Hold a message and a glass bar appears above it with the four emoji this member actually uses,
  counted rather than most recent, so the bar never reshuffles under a finger. Starts at ❤️ 👍 👎 🫡.
  The rest one tap on; the message's actions behind a ⋯ in a real menu.
- **Done.** Drawn as Messages draws them: one circle per person, three-quarters above the bubble at its
  corner, stacked with the leftmost on top, color only on your own, no rim and no tail, more than
  three collapsing into a count. Opaque, so the bubble never shows through.
- **Done.** Tapping the stack lists who reacted, yours first: your own row removes, anybody else's reacts
  the same way.
- **Done.** One summary element for VoiceOver, with *Remove my reaction* as a named action.
- **Done.** A reaction rings nobody's bell; only `send` marks a room for ringing.
- **Not done.** A visible trigger rather than a hold. Reversed deliberately, below.
- **Done.** The post row speaks one sentence, not a pill at a time. 2026-09-17: a post's reactions are one
  element saying the same sentence a message's stack says — *Reactions: 👍 from you and 1 other, 🔥
  from 2 people* — including the reactions past the third that the row folds away, with double-tap
  opening every reaction and *Remove my reaction* as a named action. And a message now carries a
  named *React* action, because holding it was the only way to react and nothing told VoiceOver so.
  `ReactionsSpeakTests` checks the exact sentence. **Unheard**: the VoiceOver walk waits for
  TestFlight.

**Testing**

- Suite: nine tests, one of them for reacting to your own message, because a `Message` field has
  been dropped on the way to the screen three times.
- Two accounts: a heart crossed 2026-09-03; the two-circle stack drawn on the receiving account, its
  own circle in accent and the other's gray behind, 2026-09-04.

**Design.** Boards 43, 44, 88; Component Blockers for sizes (38pt drawn, 44pt tappable).

<details markdown="1">
<summary>Record — Ruling 5 was reversed for messages on 2026-09-03, and what it costs</summary>

Ruling 5 chose a visible smiley over a hold, on three grounds: discoverability, VoiceOver, and not
competing with the system's own long-press menu. Griff asked for the hold, in the iMessage shape, and
that is what is built. The reasons it was rejected have not stopped being true:

- **Nothing on screen says to hold.** iMessage has the same problem and people learn it anyway, but
  that is a weaker argument than the one Ruling 5 made, and it is the cost.
- **The third ground no longer applies**, because a context menu consumes the long press so the two
  cannot coexist; the actions moved into the bar behind a ⋯, keeping roles, destructive tints and
  VoiceOver as the system does them.
- **VoiceOver reaches it**, a long press being double-tap-and-hold, but nothing announces that it is
  there. That gap is not fixed.

Recents-first became most-used-first, a strengthening of the same idea. `AppSession.react` writes into
the room, unlike a post's reaction, because a message's reaction has to be sealed under that room's
epoch. `FavouriteEmoji` counts uses device-locally; putting it on `MemberPreferences` would republish
the sibling feed, which carries every room key, every time somebody taps a heart. The pills under the
bubble became the tapback on it on 2026-09-04, drawn from Griff's iMessage screenshots; the palette's
neutral fills are translucent, so the circle lays `palette.background` under its fill.

</details>

</details>

<details markdown="1" id="storage-and-retention">
<summary><b>Storage and retention</b> — Complete (tested)</summary>

**Story.** As a member, I want to know how much this app keeps and for how long, so that my phone's
storage is mine to manage.

**Acceptance criteria**

- **Done.** A row on You, *Photos and clips on this device*, saying how many bytes are held, counted after
  each round. The footer says nothing is deleted on its own yet.
- **Deferred.** Pushed to [After TestFlight](../after-testflight.md) 2026-09-14. A control that clears media older than a date the member picks, run when they tap it. Sizes
  spoken in full words.
- **Done.** **Nothing is deleted on its own**, and that is the answer rather than a gap. Ruled 2026-09-13:
  no default age, no size cap, no background sweep. Both alternatives mean the app destroys something
  a member kept, unasked, to solve a problem it decided they had — which is the opposite of every
  other line this app takes about somebody's own history. The footer already says so.

**Cost, accepted.** A phone can fill up, and the app will say how much it is holding rather than fix
it quietly. See
[Decisions](../decisions.md#nothing-this-app-holds-is-deleted-without-being-asked).

**Testing**

- Device: 2.6 MB on the You screen 2026-09-05.

**Design.** Board 33, behind retention, whose date is not set.

</details>

<details markdown="1" id="the-system-emoji-picker">
<summary><b>A searchable emoji picker</b> — Complete (tested)</summary>

**Story.** As a member, I want any emoji, so that the list does not age every time the Unicode set
does.

**Acceptance criteria**

- **Done.** 2026-09-15. The bar is unchanged — four favorites, ranked by use — and the plus opens the grid:
  a search field, the recents row, and Unicode's nine groups with pinned headers. The hand-maintained
  twenty are gone.
- **Done.** Search by name, folding case and accents, ranking **whole-word matches above matches inside
  another word** so "cat" puts 🐱 above 🎓 *graduation cap*. It says plainly when nothing matches
  rather than showing an empty grid.
- **Done.** `Scripts/make-emoji-table.py` parses `unicode.org/Public/emoji/latest/emoji-test.txt` into
  `emoji.json` — 1,914 emoji, nine groups, 68KB. Fully-qualified sequences only; 2,030 skin-tone
  variants dropped, and the Component group with them. JSON rather than generated Swift because a
  1,900-entry literal is slow to type-check and reaches the binary as code rather than as data.
- **Done.** 2026-09-16. **A sheet on a phone, a popover on a wide screen.** It shipped as a popover
  everywhere, and the first time its field met a software keyboard the popover rose to clear the
  keys and put the field under the navigation bar. The HIG, read that day: "Avoid displaying
  popovers in compact views … use a sheet instead." Both call sites go through `.emojiPicker`, which
  presents `.sheet` in a compact width and `.popover` in a regular one, and the sheet has medium and
  large detents, so the keyboard grows it to large with the field in view.

  **The documented default did not happen, so it is stated rather than relied on.** Apple's
  reference for `presentationCompactAdaptation(horizontal:vertical:)` says "a popover presentation
  over a horizontally-compact view uses a sheet appearance by default". On iOS 26.5 this popover,
  with nothing forcing it, drew as a narrow popover under the navigation bar — and so did it with
  `.presentationCompactAdaptation(.sheet)` on the content. Both measured on alpha, from a build
  timestamped after the edit. Why is not known; the explicit `.sheet` is what made a sheet.

**A limit, named rather than papered over.** The names are **English only** — they come from the
Unicode file, which carries CLDR's English short names, and the translated names live in a much
larger CLDR set this app does not carry. So search works for an English speaker and not for anybody
else; the grid, the groups and the recents work regardless of language.

**Why not the system's, ruled 2026-09-13 after the first answer was wrong.** There is no public API
to present an emoji picker; the Reminders-style emoji-only keyboard is private. Apple's own Messages
opens the emoji **keyboard** from a gray button at the end of its tapback row, and that can be
reproduced by overriding `textInputMode` on a text field — public, and untested here. Every
third-party messenger draws a grid instead: Signal searchable with skin tones, WhatsApp six fixed plus
recents, Telegram sixteen. Griff chose Signal's shape.

Native-first does not forbid it, and the first answer claimed it did. The rule is that anything the
system draws, the system draws — and the system draws no emoji picker for apps, so there is no control
being reimplemented. See
[Decisions](../decisions.md#the-reaction-picker-is-drawn-here-and-it-is-the-one-place-the-system-offers-nothing).

**Testing.** Nine suite tests on the catalog and search. On the rig, 2026-09-16, alpha (402pt),
software keyboard on: long press a bubble, the plus on the tapback bar, the sheet opens at medium;
tap the field and the sheet goes to large with the field and caret below the drag indicator; type
"heart" and 34 matches come back; tap one and the sheet closes with the reaction on the bubble. The
Outpost post path uses the same modifier and was not walked. A regular width was not walked either.

</details>

<details markdown="1" id="photos-on-an-outpost">
<summary><b>Photos on an Outpost</b> — Complete (tested)</summary>

**Story.** As a member, I want a picture on a post, so that my wall is not text only.

**Acceptance criteria**

- **Done.** The post composer has a photo control: up to four photos or clips, from the system's picker,
  waiting as tiles above the format bar, the words as the caption on the first. The sheet stays
  until the uploads are done and says what went wrong if they did not.
- **Done.** They go as **one post**, not four: a post is one thing said, which is the opposite of a room,
  where a burst is several messages. The rest ride the entry as `MediaBody.extras`, so a build that
  predates them draws the first picture with its caption rather than the fallback sentence.
- **Done.** The arrangement changes rather than the tiles shrinking — one takes the column, two sit side by
  side, three are one tall beside two stacked, four are a square. A fifth is refused before
  anything is uploaded, and an upload that fails takes back the ones already up.
- **Done.** The Outpost feed, the wall and the thread draw the picture, blurred and screened the way a
  message is — the same view, `MediaPictureView`, that the bubble is made of.

**Testing.** Suite, `OutpostPhotoTests`: a photo becomes a post with a picture and its caption as
the words, and a photo alone has no placeholder line; the first full round's sweep leaves the bytes
in the outbox and a relaunch still draws and opens the picture; an upload that fails posts nothing
and keeps nothing. The sealing and the transport are the message path. Rig, 2026-09-06: alpha
picked a photo through the system picker, posted it with a caption, and the feed drew it in its
place; the log read `uploaded … bytes=1501814 recipients=0`, the bytes in CloudKit and addressed to
nobody, because nobody had been let in. Proved over real CloudKit on 2026-09-14: a post with a photo
reached a reader and the bytes came back identical (`LiveOutpostTests`).

<details markdown="1">
<summary>Record — the wall in place of a room, as built on 2026-09-06</summary>

*This record describes the first version. Per-person access, several photos or clips on one post,
reporting a post and withdrawing one were all built afterwards.*

A post's photo is a `media` entry on the member's own Outpost — `.outpost(you)`, sealed under that
Outpost's chain — exactly as a message's is in a room, through the one `upload(_:to:through:)` both now share:
upload first, entry second, the sender's own copy kept sealed, nothing written if the upload fails.
The fold gives `OutpostPost` a `media` and makes the caption its words, as it does for `Message`.
Collecting and sweeping attachments used to assume an entry had a room and silently skipped a wall
entry; both now read the chain an entry is sealed under, wall included, or the sweep would have
deleted a wall photo as an orphan on the next launch.

**Who receives the bytes.** Whoever holds the wall's key, read the way a room's rewrap targets are
— and that is nobody, because *Per-person Outpost access: the enforcement* is not built and nothing
writes into a wall's roster. The bytes wait in the poster's own outbox for the audience that ticket
will name; the sweep leaves them because the entry names them; the poster's own feed draws the
picture from the local copy. A reader who arrives after the enforcement lands will find the entry
and fetch the bytes by their id, which is how a room's late arrival does it.

**The picture is one view.** `MediaBubbleView` was the bubble and the honesty in one type — the
blur of the right color, the loading, the sensitive notice with its decision, *no longer
available*, *could not load* — so the honesty was lifted out as `MediaPictureView` and the bubble
became that picture with a tail and a caption. A post's `PostPictureView` is the same picture in
the feed's column, no taller than a screen wants, rounded like the comment card under it.

**What is not here, said plainly.** One photo per post, not a burst. No clips on a post; the picker
asks for photos only, so nothing can be picked that cannot be posted. The full-screen viewer reads a
`Message`, so the post is bridged into one from its own entry, and reporting from the viewer is not
offered for a post because reporting a post is not built anywhere. A wall photo cannot be withdrawn:
editing and deleting posts is its own ticket.

</details>

</details>

<details markdown="1" id="what-is-new-on-somebodys-wall">
<summary><b>What is new on somebody's wall</b> — Complete (hardware proof owed)</summary>

**Story.** As somebody who reads a few Outposts, I want to know which of them has something I have
not seen, without opening each one.

**Acceptance criteria**

- **Done.** A ring on the feed rail and a flag in the list, both from a device-local mark.
- **Done.** The mark is set when this member is let in, so a wall handed over in one round is not four years
  of unread.
- **Done.** Asking to be told rings the same bell a message does: the wish travels in the packet, and only
  the people who asked are rung.
- **Done.** The Outposts tab's badge counts the walls with something unseen, and reading one clears it.

**Testing.** `OutpostUnseenTests`, `WhatTheTabsBadgeTests`. Seen lighting on the rig 2026-09-07 and
clearing on 2026-09-11. A real banner from the extension has not been watched.

</details>

<details markdown="1" id="editing-and-deleting-your-own-posts">
<summary><b>Editing and deleting your own posts</b> — Complete (tested)</summary>

**Story.** As a member, I want to fix a typo or take back a post, so that my own wall is something I
can maintain.

**Acceptance criteria**

- **Done.** A post can be edited; the edit is an entry and the post shows it was edited.
- **Done.** A post can be withdrawn; the tombstone is an entry and the original stays hash-linked. The
  placeholder says *post*, not *message* — a placeholder that calls a post a message is the same
  small lie as one that calls a withdrawal a deletion.
- **Done.** Both work on comments. This is your own content only; anybody else's is Taking things back.

**Testing.** Suite, `OutpostEditingTests`: a rewrite carries the *Edited* mark and does not make a
second post; the window is enforced and the control withheld past it; a withdrawn post says so in
its own words and is never called deleted; withdrawing a photo post takes the picture with the
words; a comment does both; somebody else's post is not yours to change. Proved over real CloudKit on
2026-09-14: an edit and a withdrawal both reached the reader (`LiveOutpostTests`).

<details markdown="1">
<summary>Record — the log could always do this, and a dead control fell out of it</summary>

`Fold`'s edit and tombstone branches never asked which room an entry belonged to, and `append` has
taken a nil room since the Outpost existed — so a post has been editable and withdrawable in the log
from the day the log could do it. What was missing was a way for a member to say so, and a read
model that reported it: a post drew its new words with nothing beside them and reported
`isWithdrawn` as false while showing the placeholder, which is the same defect `Message` had once
and for the same reason.

The fold refuses an edit whose target is not text, because applying new words to a photo would
replace the picture with a sentence on every device. Asking that question in `timeLeft(toEdit:)` as
well is what stopped a photo — a message's as much as a post's — offering an Edit that wrote an
entry every device ignores.

</details>

</details>

<details markdown="1" id="search">
<summary><b>Search</b> — Complete (tested)</summary>

**Story.** As a member, I want to find something somebody said, or a photo they sent, without
scrolling a year of a room.

**Acceptance criteria**

- **Done.** Search is its own tab, declared with `Tab(role: .search)` so the system draws and places it. On
  a phone that is the trailing position in the tab bar.
- **Done.** Results are sectioned: conversations by name, then message text, then photos, then posts. Each
  row opens the thing it names, in the tab that holds it.
- **Done.** It searches what a member wrote and what was written to them, across every room, from the
  projection rather than from a second index.
- **Done.** Hidden messages, withdrawn messages and blocked people's messages are excluded.
- **Done.** Posts are filtered the same way, since 2026-09-13 — see the ticket below.
- **Done.** Results come back newest first, and two messages sharing an instant keep the order the log holds
  them in.

**Testing.** `SearchTests`, twelve tests: the two-character floor and that the query is trimmed
before it is measured; a room found by name; a message found with the room it came from; somebody
else's message found and correctly attributed; case-insensitivity; ordering and the same-instant
tiebreak; a post found on its words and on its author; and four refusals — withdrawn, hidden, a
blocked person's messages, a blocked person's posts. Not driven across two accounts.

**Design.** Apple's answer for a search that covers a whole app is a search tab; the inline field
under a title is for a search scoped to one section. Recorded in
[Decisions](../decisions.md).

</details>

<details markdown="1" id="blocking-reaches-posts">
<summary><b>Blocking reaches posts, not only messages</b> — Complete (tested)</summary>

**Story.** As somebody who has blocked a person, I want to stop seeing them everywhere, not just in
rooms, so that the control does what its own copy says.

**What was wrong.** `block(_:)` set a local preference, and only `messages(in:)` consulted it through
`refusesToDraw`. `feed()` was `projection.feed()` with nothing in front of it, so a blocked person's
posts stayed on the Outposts tab, in the search results, in the thread under somebody else's post,
and in the number on the Outposts badge. The same was true of the bundled deny list. Found
2026-09-13 while writing the search ticket, four days after blocking was called complete.

**Acceptance criteria**

- **Done.** `feed()`, `outpostAuthors()`, `comments(on:)` and `outpostAuthorsWithUnseen()` all refuse a
  blocked author, through the same `refusesToDraw` predicate messages already used.
- **Done.** A member is never filtered out of their own view of themselves — `refusesToDraw` guards on that
  first, so blocking cannot hide your own posts from you.
- **Done.** The key-handover half of blocking is built, on
  [the blocking ticket](rooms-and-membership.md#blocking-a-person) — the grants a round owes skip a
  blocked person (`AppSession+Peers.swift`). This line read **Not done.** until 2026-09-17, three days after it
  was built.

**Testing.** `SearchTests.aBlockedPersonsPostsAreNotFindable` blocks somebody who has let this
member into their wall and checks all four surfaces at once.

</details>

<details markdown="1" id="the-disabled-affordances">
<summary><b>The disabled affordances</b> — Complete (hardware proof owed)</summary>

**Story.** As a member, I want the controls that are drawn to work, so that the app stops
advertising things it cannot do.

**Acceptance criteria**

- **Done.** Composing from the feed, the pencil, opens a composer. `OutpostFeedView`'s leading toolbar item
  sets `isComposing`.
- **Done.** *Create the invite* waits for something that actually parses as an identity code, rather than
  lighting for any text at all. The paste field takes whitespace, so a pasted code with a newline
  around it still counts.
- **Done.** 2026-09-16. Camera scanning reads an invite QR, as a **Scan** button beside **Paste** on
  *Join a room*. It is VisionKit's `DataScannerViewController`, looking for QR codes only; a code
  that does not read as an invite for this identity is ignored and the sheet says so, and one that
  does is pasted and read straight away, which lands on the same check a pasted invite does.
- **Done.** 2026-09-16. The app asks in its own words before scanning is first used, never at launch, and
  refusing leaves the paste field. The question is a card under *Read the invite* — *Turn on
  scanning* or *Not now* — and **neither answer opens the camera prompt**: the HIG's rules for a view
  shown before a permission alert forbid a way out of it, so the prompt comes only from tapping Scan.
  Ruled that evening: **the setting is saved on only once the camera has been allowed**; *Turn on
  scanning* saves nothing, a no to Apple saves it off, and *Not now* saves it off and stops the
  asking. The switch is in **You ▸ Behavior**, since it is this device's alone. See
  [Decisions](../decisions.md#how-the-ask-and-the-higs-pre-alert-rules-both-hold).
- **Done.** Emoji in room names, 2026-09-14 (`0c9fb0f`): a leading emoji is the room's mark, so "🎈" and
  "🎈 Lanterns" draw the balloon and "Lanterns 🎈" still draws L. `AvatarInitialsTests`. Local
  nicknames for people that never enter a feed were already built, 2026-09-06 (`37fce43`): stored on
  `MemberPreferences`, merged across the member's own devices, reaching no feed. `NicknameTests`.
  This page said **Not done.** for both until 2026-09-16.
- **Done.** Anything still not built stays visibly disabled rather than hidden. Hiding it makes the app look
  complete and the member look wrong for expecting it.

**Testing.** `InviteScanningTests`, seven: an unanswered device asks; *Turn on scanning* shows Scan
and saves nothing; allowing the camera saves it on; a no to Apple or *Not now* saves it off and stops
the asking; a device that cannot scan is never asked and changes nothing; the stored answers keep
their spelling; and the system is asked only when undecided. On the rig, 2026-09-16 evening, alpha,
the saved value read out of the container at each step: the question; *Turn on scanning* shows Scan
with **no key written**; Scan says the device cannot scan and still writes nothing; the next visit
asks again; *Not now* writes `off` and the question is gone; the switch in Behavior is off, and
turning it on on a simulator leaves it off with *This device cannot scan codes*. **Owed: the
scanner has never run**, because a simulator has no camera and `DataScannerViewController.isSupported`
is false there. A phone needs to scan a real invite, allow the camera (and see the switch on), and
refuse it once (and see *Open Settings*).

**Design.** Boards 34–36, 41, 07, 72. Nicknames: design needed.

</details>

<details markdown="1" id="scale-and-crop-a-picked-avatar">
<summary><b>Scale and crop a picked avatar</b> — Complete (tested)</summary>

**Story.** As somebody choosing a picture of themselves, I want to say which part of it is the
picture, so that a photo with my face off to one side does not become a photo of my shoulder.

**What was wrong.** `ImagePreparer.avatar` took the largest centered square and scales it, with
no choice offered. That is right as a *fallback* and wrong as the only behavior, and it is wrong in
the most common case: a photo of a person is rarely composed with the face in the center.

**Acceptance criteria**

- **Done.** Picking a picture opens a crop step before anything is saved: the picture under a circular
  mask, pinch to zoom, drag to move, and *Use* / *Cancel*. Cancel keeps whatever was there.
- **Done.** The same step for all three pickers — the member's own avatar, the photo kept for somebody
  else, and the face chosen for the one stranger. One modifier, `croppingPickedPhoto`, so a fourth
  picker cannot quietly skip it.
- **Done.** The crop travels as a unit rectangle of the **oriented** image, and `ImagePreparer` applies it
  to the same oriented thumbnail it already builds. The two must agree about orientation or a
  portrait photo crops sideways, which is the whole risk in this ticket. Both ends go through
  `ImagePreparer.thumbnail`, which is the only place that decodes `withTransform`.
- **Done.** Zoom is bounded below by fill: the circle is never allowed to show ground. Fill *is* a scale
  of one, so the bound is a number rather than a computation.
- **Done.** `ImagePreparer.avatar` with no crop is still the largest centered square, so nothing regresses
  for somebody who does not care — and a rectangle off the edge is clamped rather than refused,
  since the alternative is telling somebody their photo could not be prepared.

**Two things found while building it.**

- **Zoom has to be anchored on the circle.** The offset is held in circle-diameters, and leaving it
  alone while the picture grows slides the circle back toward the middle of the picture — on the
  rig, zooming in on a face pushed the face out of frame. Scaling the offset by the pinch is what
  makes a pinch mean what people expect.
- **Zooming in must not cost resolution.** The old path decoded at twice the avatar's edge; taking
  a fifth of that leaves a fifth of the pixels. `decodeEdge` grows the decode so the *kept* part is
  avatar-sized, capped at 4096.

**Testing.** `AvatarCropTests`: a picture with a landmark in one corner, cropped to a rectangle over
that corner, comes back containing it — and the same rectangle over a picture whose landmark is
elsewhere does not, so the test cannot pass on a crop that was ignored (mutation-checked). Plus the
no-crop fallback, the clamp, and the decode arithmetic. The gesture was a rig job: verified on alpha
against a picture with its subject hard off to one side, through all three pickers.

</details>

<details markdown="1" id="an-outpost-inherits-your-face">
<summary><b>An Outpost inherits your face</b> — Complete (tested)</summary>

**Story.** As somebody with a photo of myself, I want my Outpost to show it without my setting it
twice — and I want to be able to use a different one there, or none, without that decision leaking
into every room.

**Where it started.** Somebody else's Outpost avatar already inherited the photo *this member* chose
for them in People, which is the right default. The other three were built here.

**Acceptance criteria**

- **Done.** This member's own Outpost draws their own avatar, the one the You page holds, with no second
  setting to find. The defect was that `PersonAvatarView` looked the viewer up in two maps that are
  about *other people* and found nothing in either; the viewer is now recognized rather than looked
  up. Five surfaces were drawing a monogram: the wall header, the composer, the feed rail, own
  posts and comments, and the Mac sidebar.
- **Done.** Outpost settings gains two controls over that: **Show my picture**, and **Use a different
  picture here** with **Use the picture from You** to undo it. Neither touches what rooms see.
- **Done.** The picture can be changed from the member's own wall directly — the header disc is the
  control, with a pencil, the way it is on You — and doing so asks once, *Just on my Outpost* or
  *Everywhere*. *Everywhere* clears the wall's own picture as well as setting the new photo, which
  is the point of asking: without it, somebody who once chose a wall-only picture and later says
  "everywhere" goes on seeing the old one there.
- **Done.** A reader whose friend shares a picture on their Outpost sees it without setting one in People;
  a photo the reader chose themselves still wins. The whole rule is `avatarSource`, tested.
- **Done.** Nothing here shares a picture that was not already being shared: `shareOutpostPhoto` guards on
  `isSharingAvatar` exactly as `sharePhoto` does, and `withdrawPhoto` takes the wall down with the
  rooms. With *Share my photo* off, the member's own wall still draws their face **to them** and
  nothing is uploaded or announced — the same asymmetry the You page has always had.

**The default is on**, and the honest price was a copy change rather than a second switch. "Share
my photo" was explained as going "to the people you share rooms with", which was silent about the
people a member deliberately let into their own wall; it now names both, in the check-up, in
Privacy & Safety, and in the modal. See [Decisions](../decisions.md), "A wall carries its own
picture pointer".

**Two defects found on the way, both fixed here.**

- **Being let in to somebody's Outpost announced your name, your photo and your Do Not Disturb
  status onto it** — the leak `roomsToTell()` closed, still running on the one path that does not
  go through it (`adopt` hands `announceProfile` the wall it was just given a key for). Readable by
  the wall's owner and by every other reader of it, whom this member has never met.
  `WallIsNotARoomTests` missed it purely on ordering: its fixture grants wall access *before* any
  sharing switch is on, so there was nothing to say. Reversing that order reproduces it every time.
- **Every Outpost answer given in the check-up's re-run door was discarded**, and the door opened
  on defaults rather than on the member's real settings. `PrivacyAndSafetyView` built its
  `PrivacyChoices` without `outposts:` and never read `chosen.outposts`.

**Testing.** `AvatarPrecedenceTests` holds the four rungs and the viewer short-circuit;
`OutpostPhotoSharingTests` holds both gates, the wall-only reader, the two pointers staying apart,
and the record the wall names not being deleted with the rooms' one;
`MemberPreferenceCoverageTests` is a `Mirror` walk that catches a preference left out of
`CodingKeys`, `init(from:)` or `merged(with:)` — three failures nothing in the tree caught before.

**Across the network.** Proved over real CloudKit on 2026-09-14: a wall's own picture crossed and the
reader fetched the same bytes (`LiveOutpostTests`). Checked on one device: the five monogram surfaces,
the modal and both its answers, the settings section, the check-up page, and the setting surviving
the check-up's re-run door.

</details>

## Test plan

<details markdown="1">
<summary>Two devices, two accounts, a third for the room-of-three cases</summary>

**Formatting.** A message with emphasis shows no markers on either device; emphasis on a selection
preserves the selection; fifty messages in one sync are one packet.

**Media.** A photo arrives, renders, and survives a relaunch on both devices: arrived and rendered
2026-09-04, the relaunch half not watched. A photo to a room of three is one packet, one asset, three
recipients. Killing the app mid-upload leaves nothing half-sent: by construction, no entry exists
until the upload has, and the sweep is tested. After the fetch, the attachment record is gone from
the sender's outbox: proved against a real account 2026-09-15.

**Editing posts.** Both devices show the edit and mark it; both show a withdrawal and
the log still verifies end to end.

</details>

**What would falsify the epic.** A formatting marker reaching a reader. A packet per message. A tag a
photo carried in that reaches a reader. An edit that does not converge, two devices showing different
text for the same entry, which is a fold bug and the one thing here that would undermine the log
rather than a feature.
