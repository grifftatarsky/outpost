---
# COPY BEGIN 44fcc393 [NEEDS HUMAN REVIEW]
title: The simulator rig
layout: default
nav_order: 8
---

# The simulator rig

{: .no_toc }

The simulators this project proves things on, what a simulator can and cannot do, and how to drive
them without taking over the Mac.

1. TOC
{:toc}

<!-- COPY END 44fcc393 -->

<!-- COPY BEGIN ca11c7ca [NEEDS HUMAN REVIEW] -->

## The devices

Two simulators on iOS 27.2 (24B8117), run from Xcode 27.2. They were made on 2026-11-10, when every
earlier simulator and the older iOS 27.2 runtime were deleted. Neither is signed in to an Apple
Account yet, so nothing that crosses the network can run until Griff signs each into a different one.
**Address them by `id=<UDID>`, never by `name=`**: a duplicate name once made `xcodebuild` boot a
shut-down twin instead of the running device, and on Xcode 27 a name also means the newest iOS
(measured 2026-09-28). `Scripts/check-all.sh`, `Scripts/check-release-leaves.sh` and
`Scripts/scan-for-vulnerabilities.sh` look `outpost-alpha` up by name through
`.github/scripts/pick-simulator.py`.

| Name | UDID | Apple Account | Points |
|---|---|---|---|
| `outpost-alpha`, iPhone 17 | `5A43F953-128D-4FE6-9135-0D26520E02B6` | not signed in yet | 402 wide |
| `outpost-beta`, iPhone 17 Pro Max | `DF6EB0C7-9FCF-45C8-A120-6349FBFA288F` | not signed in yet | 440 wide |

The two are on different Apple Accounts, so they prove what two people over CloudKit can. Which
account belongs to which device is kept outside this repository, and so is whose they are:
**do not run `--reset-account` on either, or anything else that erases the account's data**, without
asking Griff first.

**What the live suite does to an account.** `CloudKitMailboxTests` and `LivePairTests` call
`eraseEverySpace()`, which deletes every `Pair-` zone in the account; `LiveDeathmarkTests` clears the
account's deathmark; `LiveSiblingFeedTests` writes records from made-up devices into the member's own
`SiblingFeeds` zone. So a member made on the device beforehand loses its spaces. Run the suite on an
account that holds nothing you want, or run it after the round. Both accounts held a member from
before when the rig started; Griff had them reset on 2026-11-04.

`--mailbox` does not keep a device off the account. It swaps the mailbox and the account check, but
`startDeviceSync()` still publishes a sibling feed to CloudKit. Read in the code, not measured.

There is no device without an account any more, so nothing here runs the three-device walks under
`--mailbox` ([members without an Apple Account](#members-without-an-apple-account),
`Scripts/rig-walk-removals.sh`, which still names the old devices).

**Build once, install everywhere, and never leave an old build on a device.** A device running last
week's code looks exactly like a defect, and Griff has caught one twice.

```bash
xcodebuild -workspace Carpenter.xcworkspace -scheme Carpenter \
  -destination 'platform=iOS Simulator,id=5A43F953-128D-4FE6-9135-0D26520E02B6' \
  -derivedDataPath /tmp/carpenter-dd build
for u in 5A43F953-128D-4FE6-9135-0D26520E02B6 DF6EB0C7-9FCF-45C8-A120-6349FBFA288F; do
  xcrun simctl terminate "$u" com.microgpt.carpenter 2>/dev/null
  xcrun simctl install "$u" /tmp/carpenter-dd/Build/Products/Debug-iphonesimulator/Outpost.app
done
```

The bundle is `Outpost.app` and the identifier is `com.microgpt.carpenter`, the split set in
`Config/Branding.xcconfig`. After adding a file to a type split across files, delete the derived data
first (see [Architecture](architecture.md#where-the-source-lives)).

If `xcode-select -p` points at the Command Line Tools, `simctl`, `xcodebuild` and `swift test` all
fail, the last obscurely on the `@Entry` macro. Point it at Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

<!-- COPY END ca11c7ca -->

<!-- COPY BEGIN ec0d72fb [NEEDS HUMAN REVIEW] -->

## Driving the devices without taking the Mac

**Use XCUITest, one step per test, one device per run.** It runs headless and takes no focus from
whoever is using the Mac. Do not bring a simulator window to the front or send it keystrokes while
Griff is working.

The rig's steps are in `App/CarpenterUITests/RigChecks.swift`: onboarding, a room, an invitation,
joining, a message, the block sheet, the waiting list, comparing codes, the not-sent mark four days
on, a removal, deleting, a relaunch, the app icon picker and the Supporter flow. They skip unless
asked for:

```bash
TEST_RUNNER_OUTPOST_RIG=1 xcodebuild test -workspace Carpenter.xcworkspace -scheme Carpenter \
  -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath /tmp/carpenter-dd \
  -only-testing:CarpenterUITests/RigChecks/testSupporter -parallel-testing-enabled NO
```

`testFifthOnboards` takes a name in `RIG_NAME`, `testQuadSays` says what is in `RIG_SAY`, and
`testSees` opens Checks and waits for the words in `RIG_EXPECT`, so any three members can talk in one
run. `RIG_ROOM` names another room than Checks, and `RIG_OFFLINE=1` launches with every write refused,
so a member can act without anybody hearing until the next step.

**The removal walk** runs as one script, `Scripts/rig-walk-removals.sh`, on Trig, Quad and Fifth: two
people removing each other with neither sending, what is said after the removal, and two members
turning the key at once. It makes two new rooms each run, stops at the first failing step, and leaves
every step's log in `/tmp/outpost-rig-exchange`. Written 2026-09-29, not yet run.

Each step attaches screenshots to the result bundle and writes the screen's element tree to
`/tmp/outpost-rig-exchange/<step>.txt`. Export the screenshots with
`xcrun xcresulttool export attachments`.

**Never use a simulator's pasteboard.** It syncs with the Mac's clipboard, so copying a code on a
simulator overwrites whatever Griff last copied, and reading it reads his. That happened once, on
2026-09-17. Codes travel through the rig directory instead (below).

**Tap positions are device points.** If tapping from a screenshot, point = pixel × (points ÷
screenshot width). Twenty points of error near the bottom of the screen is the difference between the
composer and the gap under it.

**Keep both apps awake during a cross-account test.** An app in the background is suspended. On
2026-09-08 beta logged nothing for ten minutes and resumed within a second of being touched, and in
the meantime it looked exactly like a broken channel. Before deciding sync is broken, check the quiet
device logged anything at all in that window.

**Do not terminate an app mid-round.** A round takes a few seconds, and a launch that adopts many keys
takes longer. Give it 20 to 30 seconds, or wait for the `mailbox sync:` summary line.

Reading a device's log:

```bash
xcrun simctl spawn <udid> log show --last 3m --predicate 'subsystem CONTAINS "microgpt"' --style compact --info --debug
```

<!-- COPY END ec0d72fb -->

<!-- COPY BEGIN 704a6a43 [NEEDS HUMAN REVIEW] -->

## What a simulator can actually do

Measured on this Mac on 2026-09-01 and since.

| Capability | Works | Detail |
|---|---|---|
| CloudKit against a real account | yes | Unless the account has Advanced Data Protection on; see below. |
| App Group container shared with the extension | yes | `storage: … appGroup=true` in the log. |
| Push from real APNs | registers | A real sandbox token on Apple silicon. A bell rung by the other account on 2026-09-14 did not arrive in five minutes. |
| Notification service extension | yes | Runs, including for `xcrun simctl push`. |
| Keychain generic password items | yes | Persist across launches. `simctl uninstall` does not clear them. |
| Keychain access groups | no | Simulator builds are unsigned, so the app and extension's shared group behaves differently than on a phone. |
| Sensitive Content Analysis | yes | Judged a photo clear on 2026-09-04. A positive verdict needs Apple's test profile on a phone. |
| Secure Enclave | no | |
| A Focus | no | `INFocusStatusCenter` always says not focused. Use You › Debug › *Pretend a Focus is on*. |
| **An iCloud Keychain hand-off** | **no** | See below. |

<!-- COPY END 704a6a43 -->

<!-- COPY BEGIN d1e1366a [NEEDS HUMAN REVIEW] -->

### No iCloud Keychain hand-off

A simulator cannot join the account's Octagon trust circle. Every keychain sync view stays in
`waitfortrust`, and the *Sync this iPhone* switch for Passwords does not move:

```
<CKKSKeychainViewState(): Passwords(ckks), waitfortrust>
<CKKSKeychainViewState(): ProtectedCloudStorage(ckks), waitfortrust>
```

It reaches Apple's servers fine; it just never becomes trusted, because it has no Secure Enclave or
device attestation. So one member on two devices needs two real phones.

<!-- COPY END d1e1366a -->

<!-- COPY BEGIN 695e0ba3 [NEEDS HUMAN REVIEW] -->

### Advanced Data Protection makes a simulator useless

With Advanced Data Protection on, the whole private database is end-to-end encrypted, every write goes
through Protected Cloud Storage, and that needs the keychain trust a simulator cannot get. Measured on
2026-09-01 on two accounts the same afternoon:

| Account | ADP | Zone writes |
|---|---|---|
| one account | on | every one failed `PCSNoPublicIdentity` after about 20 seconds, 0 bytes uploaded |
| the other | off | 7 operations, no errors |

**Sign simulators into development accounts without ADP.**

**This does not affect real members with ADP on.** Without ADP, Apple keeps a copy of the CloudKit
service key, so even an untrusted device can use it. With ADP, only trusted devices hold it, and a
real iPhone with ADP on is trusted by definition. It has not been run on a real ADP device.

Two things about ADP are true for real members:

- **The outbox share is an "anyone with the link" share** (`publicPermission = .readWrite`), and Apple
  says link-shared content does not get ADP's end-to-end protection. That changes nothing Outpost
  promises: everything in the zone is sealed by the app before CloudKit sees it, so a leaked link
  yields sealed packets.
- **An app cannot read whether ADP is on**, so the app never says either way.

<!-- COPY END 695e0ba3 -->

<!-- COPY BEGIN 8d16f4ce [NEEDS HUMAN REVIEW] -->

## When a device will not let you in

A first launch checks whether the Apple Account already has a member before offering to make one,
because two members on one account refuse each other's messages. `AccountRegistry.occupancy()`
answers one of four things, and only `empty` leads to onboarding:

| Answer | What the device shows |
|---|---|
| `empty` | onboarding |
| `occupied` | waits for the identity to arrive through the Keychain, then stalls with an explanation |
| `offline` | *Could not reach iCloud*, and waits |
| `undetermined` | asks again, then stalls rather than guessing |

Before 2026-09-16 a failure to read the account became "empty", so a network blip offered onboarding
on an account that already had a member.

<!-- COPY END 8d16f4ce -->

<!-- COPY BEGIN 0ec9fe5e [NEEDS HUMAN REVIEW] -->

### An account that remembers dead devices

Occupancy asks whether any device ever published a feed, and a feed outlives the device that wrote
it. Deleting a simulator does not delete its feed, so an account collects feeds from dead devices and
every new device waits for a key nobody holds. The way out is a debug launch argument:

```bash
xcrun simctl launch <udid> com.microgpt.carpenter --reset-account
# wait for "erased this member's outbox zone and its share", then:
xcrun simctl terminate <udid> com.microgpt.carpenter
```

{: .warning }
> **This erases the Apple Account's data for this app, not just the device.** It deletes every device
> feed in the account's private database and removes the app's synchronizable keychain items, which
> reaches every real iPhone, iPad and Mac signed into that account that has this app. It is scoped to
> this app's service and access group and touches nothing else. **Ask Griff before running it.**

Terminate the app as soon as the erase finishes. If it keeps running, the change of session state
starts device sync again, which republishes a feed and makes the account occupied again.

`Scripts/reset-device.sh` resets a device and cannot clear iCloud, which is why the launch argument
exists.

**A simulator's iCloud can drop into `Account Temporarily Unavailable`** (CKError 36) and stay there
until the password is entered again in Settings. Only the account owner can do that.

<!-- COPY END 0ec9fe5e -->

<!-- COPY BEGIN 29af1dda [NEEDS HUMAN REVIEW] -->

## A quiet peer

Two members who talk each keep a space for the other, and each has joined the other's. Under
`--mailbox` every space is in `<directory>/pairs.json`: the account it lives in, the account it names,
and the accounts that have joined it. A space that names nobody and has no hint is one made for a
code. Two members whose spaces do not name each other have not swapped links yet; their room passes
the links on while a member who talks to both is running.

Over iCloud, a test that stops at its first CloudKit call, with `AuthTokenError` in cloudd's log, is
the Apple Account asking for its password. On 2026-09-28 alpha and beta both showed *Apple Account
Verification*, and after *Not Now* every request failed with *User rejected a prompt to enter their
iCloud account password*. Only Griff can enter it, in Settings on each simulator.

<!-- COPY END 29af1dda -->

<!-- COPY BEGIN fb141a22 [NEEDS HUMAN REVIEW] -->

## Members without an Apple Account

A third Apple Account needs a phone number Griff does not have, so gamma and delta run with **no
Apple Account** and a different transport. A signed-out simulator has no CloudKit (every request
fails `Not Authenticated`), but it can make a member, because creating an identity needs no network.

```bash
xcrun simctl launch <udid> com.microgpt.carpenter --mailbox /tmp/outpost-rig-mailbox
```

`--mailbox` swaps in `FileMailbox`, which keeps packets in a host directory. A simulator's `/tmp` is
the host's `/tmp`, so one directory is one group of members. Launch every member of a test with the
same flag; a mix is two separate groups. Debug builds only.

`FileMailbox` stores the same wire fields as CloudKit, returns packets in write order and never hands
a packet back to its writer. Acknowledgments are separate files, because three processes cannot
safely edit one.

Under `--mailbox`:

- **The account check answers `empty`** (`RigAccount`), so a member with no account can onboard.
- **Codes go through the directory.** The app writes its identity code to
  `<directory>/codes/<name>.identity` and each invitation to `<directory>/codes/<name>.invite`, and a
  UI test types them into the other device.
- **`--mailbox-refuses full`** or **`signed-out`** makes every write fail the way CloudKit fails for a
  full or signed-out account, to see what a member reads.

Other debug launch arguments are listed on [Testing](testing.md#launch-arguments-for-the-rig).

**What this proves, and what it must never be said to prove.** Everything above the mailbox: rosters,
rendering the log, keys, invitations, confirmations, and what a third or fourth member changes. Nothing below
it: zones, shares, the change feed, CloudKit's eventual consistency or push. A result from these
devices is **proved above the mailbox** and has to be written down in those words.

<!-- COPY END fb141a22 -->

<!-- COPY BEGIN b30668e4 [NEEDS HUMAN REVIEW] -->

### The removal walk, 2026-09-30

`Scripts/rig-walk-removals.sh` was run for the first time. It has **not finished**, and what it found
so far is about the walk, not the product:

- A joiner cannot reach the invite screen unless its room list is empty. "I have an invite" is only in
  the empty state; on a phone that already has rooms the way in is *Rooms list options → Join with an
  invite*. The step now tries both.
- The walk went straight from the two joins to the first message, with no round in which the inviter
  relays the confirmations and the joiners collect what they were admitted to. It now runs one round
  on each phone in between (`testRunsARound`).
- The joiner step ignored what came back from reading the invite, so a refused invite passed the step
  and the walk failed three steps later on a room that was never joined. It now says so where it
  happens, and a tap that lands on a screen already changing no longer fails the run outright.

On devices carrying state from earlier runs the walk stopped with *"That invite is not usable. It may
have expired."* on the second joiner, and one waiting invitation showed no characters to compare. That
was not chased to the bottom. The three devices were erased and onboarded again, and the walk was
stopped part-way through its first fresh run: **erasing three simulators at once leaves the Mac's load
average in the hundreds for a long while**, and every `xcodebuild` step then takes twenty minutes
instead of one. Erase them one at a time, or well before a walk.

<!-- COPY END b30668e4 -->

<!-- COPY BEGIN 9596e0ef [NEEDS HUMAN REVIEW] -->

### What these devices have shown

- **Three members, 2026-09-09.** Griff (alpha, on an account) invited Trig (gamma, no account). Both
  screens showed the same characters, Trig confirmed, and packets and acknowledgments went both ways.
- **The stranger, 2026-09-09.** Quad (delta) shared a room with Griff and nothing with Outie; both were
  let into Griff's Outpost. Quad's comment drew as *Quad* on Griff's phone and as *User 403* on
  Outie's. With Quad set to Closed, Outie's thread showed *2 comments are not shown*.
- **Taking back somebody else's invitation, 2026-09-09.** Outie withdrew an invitation Griff had made,
  and the transcript and rows attributed it correctly.
- **Two defects the suite could not see**, both fixed the same day. `SyncEngine.pack` kept one grant
  per recipient per packet, so Quad, let into a room and an Outpost the same afternoon, got only one
  key. And a round acknowledged packets before writing them to disk, so terminating a device mid-round
  lost a comment on both ends; that comment is still gone.
- **The room introduces two people, 2026-09-28.** Trig (gamma) invited Quad (delta) and Fifth
  (outpost-27) into one room. Quad and Fifth never swapped codes; the room passed their links on, each
  joined the other's space, and with Trig's app closed a message from Quad reached Fifth. Nothing in
  Trig's spaces changed. It also found that every launch before a round finished made one more empty
  space for a code, fixed the same night.

<!-- COPY END 9596e0ef -->

<!-- COPY BEGIN c16c17ef [NEEDS HUMAN REVIEW] -->

### What bullet and iPhone 17 have shown, 2026-11-04

On the build of `overnight-2026-10-31` at 1483934, two accounts, both reset first.

- **The live suite passed on iPhone 17**: 38 tests in 79 seconds, none failed. `LivePairTests`
  skipped, because it needs both devices and bullet's account had stopped answering (below).
- **A round between two people worked.** Ada (bullet) and Bea (iPhone 17) onboarded with the
  software keyboard. Codes went through a file saved to Files, not the pasteboard. Ada invited Bea to
  a room, both screens read `AQRENT6D5A`, and Bea confirmed. A message crossed each way. A photo
  went Ada to Bea at the same size on both ends (`media: uploaded 942bcf28 bytes=770768`, `fetched
  942bcf28 bytes=770768`). With Bea's read receipts on, Ada's photo showed a filled plane and eye and
  "10:42 AM".
- **Starting a Solo with somebody you already share a room with does not work.** On iPhone 17 the
  app said *The solo was started, but the invitation was not sent*, and logged `invite failed while
  making a room: DecodingError.keyNotFound … "keys"`. `AppRootView.invite(_:to:kind:)` passes
  `IdentityPublicKeys.encoded()` to `session.invite(joinerCode:)`, which decodes a `JoinerCode` (keys,
  commitment, requires). On bullet, *Send a Solo* opened nothing. Neither was chased further, and the
  block test below ran in the room instead.
- **After a block and an unblock, messages crossed only one way.** Bea blocked Ada at 10:43:59. Her
  rounds then showed `peers=0`, and Ada's message sent during the block appeared on Bea's screen once
  she unblocked. Bea's rounds wrote packets at 10:45:22, 10:45:29, 10:45:52 and 10:45:56, including
  *Bea after unblock*. Ada ran rounds throughout and logged `entriesReceived=0` from the block until
  10:47:08, and her message stayed not collected. Bea's round at 10:45:22 logged `met 1 new peer(s)`.
  Repeated on 2026-11-05 and the cause found; see below.
- **Running the suite on bullet stopped its account.** As the test host launched at 10:47:57, cloudd
  began failing every request with `AuthTokenError` (2011), and the device showed *Apple Account
  Verification*. The prompt was left for Griff. Whether the run caused it is not known.

<!-- COPY END c16c17ef -->

<!-- COPY BEGIN ba46c2cf [NEEDS HUMAN REVIEW] -->

### Blocking and unblocking, 2026-11-05

**On the build of `overnight-2026-10-31` at fc09845, before the fix.** Both accounts reset first. Ada
(bullet) invited Bea (iPhone 17) to a room of two, and a message crossed each way. Bea blocked Ada at
01:44:39. Ada wrote twice during the block, and Bea's rounds showed `peers=0`. Bea unblocked at about
01:47:15, and both of Ada's messages appeared on Bea's screen. Bea wrote *Bea after unblock* and her
rounds wrote packets at 01:47:26, 01:47:33 and 01:47:41. Ada logged `entriesReceived=0` from the
block until 01:49:06, when the run was stopped, while Ada's *Ada after unblock* reached Bea. So the
person who blocked stops reaching the person they blocked, the same as 2026-11-04.

The cause is in the code, not CloudKit: blocking deleted Bea's space for Ada and unblocking made a
new one, and the link to the new one can only reach Ada through a space of Bea's that Ada reads. In
a room of two there is none. The fix is in [Decisions](decisions.md#blocking-takes-a-person-off-your-space-and-you-off-theirs).
Screenshots are in the session's `rig-shots/blocking/base-*`.

**On the build of `overnight-2026-10-31` with the fix and post-quantum phase 1, at 19:03.** Both
accounts reset at 18:44 and the app installed fresh. Ada (bullet) and Bea (iPhone 17) onboarded,
Ada invited Bea to a room of two, both screens read `ABVQ46VT39`, and a message crossed each way.
Bea blocked Ada from Ada's page at 19:17:21; within four seconds her log read `took 1 reader(s) off
a space` and `left 1 space(s) of somebody blocked`, and her rounds showed `peers=0`. Ada wrote
*Ada during block* at 19:17:42. Bea unblocked at about 19:18:53, her log read `named the reader of
a space` at 19:19:07, and *Ada during block* arrived on her screen. Bea wrote *Bea after unblock*
at 19:19:33 and Ada's round at 19:19:38 collected it. Message detail on Ada's phone showed Bea with
a filled plane and *Collected 7:19 PM*. One run, not repeated. Screenshots are in the session's
`rig-shots/merged/`.

The same run found Block on a person's page did nothing: its confirmation was attached to the
members list underneath, which cannot present while the page is pushed over it. Fixed in the same
build before the block above.

Ringing could not be measured either way here: a push from the other account has never reached a
simulator on this rig (see [What a simulator can actually do](#what-a-simulator-can-actually-do)), so "no banner" on a
simulator proves nothing.

<!-- COPY END ba46c2cf -->

<!-- COPY BEGIN 0a839973 [NEEDS HUMAN REVIEW] -->

### What outpost-alpha and outpost-beta have shown, 2026-11-10

On the working tree of `overnight-2026-10-31` that afternoon, uncommitted, on iOS 27.2 (24B8117).
Each is one run.

- **Two accounts, in the app's test host, over CloudKit** (`LivePairSendTests`, Ann on alpha and Ben
  on beta, 85 and 84 seconds). Ann invited Ben to a room by his code and he joined. Ann started a
  Solo with Ben from the people she knows; Ben was let in and both ends read the same phrase. Ann
  replaced the room's key while Ben ran no rounds; Ben's next message collected first and was sealed
  under Ann's new key, and collecting and writing took 0.9 seconds. Ann removed Ben; Ben's next send
  collected the removal and wrote nothing. The key was replaced by calling the session directly,
  because a removal needs a third person and the rig has two accounts.
- **The lock, in the app, on alpha** (`RigChecks.testANewMemberSavesTheKeyAndLocksTheApp`, under
  `--mailbox`, so no iCloud). See [the lock's open question](open-questions.md#outposts-own-lock-seals-what-the-phone-keeps-and-what-that-costs).
  The walk first failed on this iOS because the share sheet's Copy is a cell, not a button; the test
  looks for both now.

**A side that only waits for a file is not running rounds.** The first live run stalled for six
minutes because Ann waited on a file while Ben still needed her next round to hand him the Solo's
key. A side waits with `LivePair.until`, which runs rounds, unless the other side needs nothing more
from it.

Not run: the app's own screens for any of this on two accounts, a ring after a block, and the older
live suite.

<!-- COPY END 0a839973 -->

<!-- COPY BEGIN a1f7ccec [NEEDS HUMAN REVIEW] -->

### What outpost-alpha and outpost-beta showed on the night of 2026-11-10

On the build at `fe9ec3e`, each simulator signed in to its own Apple Account.

- **The app suite against live iCloud passed on `outpost-alpha`:** 63 tests in 13 suites in 98
  seconds, with parallel testing off. Run with parallel testing on, Xcode ran it on a clone of the
  simulator and it passed there too; that run is not counted.
- **`LivePairTests` passed once on the two accounts,** 65 seconds a side: a space shared each way,
  24 entries in the order written, receipts emptying the sender's space, a photo and its copy
  cleared, a write into the other person's space refused, and a closed space gone.
- **`LivePairSendTests` passed a second time,** 71 seconds a side. Collecting and then writing took
  0.7 seconds for a room of two.

`LivePairTests` had not run since 2026-09-28 and stalled three ways before it passed. All three
were the test, not the app:

- One side waited on a file and ran no rounds while the other still needed its receipts.
- The sender waited on a file straight after sending a photo, so the photo's entry was never sent.
  In the app a round follows every send.
- The last check counts every shared space the account can see, and the runs that had failed left
  theirs behind.

Each side now clears its own spaces before it starts and keeps running rounds while it waits.
**A run that fails still leaves its spaces in the account** until the next run clears them.

One thing is not explained: in the first run Alice's test process ended after three and a half
minutes with no crash report. It has not happened again in four runs.

<!-- COPY END a1f7ccec -->

<!-- COPY BEGIN 0bf4dd34 [NEEDS HUMAN REVIEW] -->

### What outpost-alpha and outpost-beta showed on 2026-11-11

On the build at `07901f3`, which holds the fixes for all twelve faults, each simulator on its own
Apple Account, from derived data deleted first. Each is one run.

- **The app suite against live iCloud passed on `outpost-alpha`:** 63 tests in 13 suites in 88
  seconds.
- **`LivePairTests` passed on the two accounts,** 49 and 48 seconds a side.
- **`LivePairSendTests` passed on the two accounts,** 71 and 70 seconds a side. Collecting and then
  writing took 0.7 seconds. This is the run that reaches two of the fixes over real iCloud: the read
  before a send now drops what the mailbox last read, and a round collects again from a peer whose
  address moved.

- **Reading all device mail on launch works over real iCloud** (`LiveSiblingFeedTests`, one
  account, added the same night). A second device was handed its sibling's mail once. A new sync
  engine for that device, started from the same saved state as after a restart, fetched and was not
  handed it again, which is the fault. `readEverything` then handed it over.
- **`Scripts/smoke-two-accounts.sh` ran all three sets from one clean build** and all passed: 61
  tests in 12 suites on one account, then both pair suites at about 70 seconds a side. Five other
  builds were running on the Mac at the time.

**What that does and does not show about the twelve fixes.** The two accounts are two people with
one device each. Nine of the twelve faults need a third person or a second device on one account, so
on the rig their fixes were only shown not to break two people talking. Their evidence is the
package suite.

**The first run of the night passed and counted for nothing.** The build failed on a stale module
left in the derived data, `xcodebuild test-without-building` ran the build from that afternoon, and
both sides passed. `Scripts/smoke-two-accounts.sh` now deletes the derived data, stops if the build
fails, and prints the commit it ran.

<!-- COPY END 0bf4dd34 -->

<!-- COPY BEGIN b526cfb5 [NEEDS HUMAN REVIEW] -->

## What the rig cannot prove

A second Apple Account can accept a share; nothing else on this Mac can. A third party over CloudKit
needs a third account, and one member on two devices needs two phones. Those proofs are listed, with
what shipping without them costs, on [Proofs a rig cannot run](proofs-a-rig-cannot-run.md).

Anything that crosses the network is unproven until it has run on two accounts, and a simulator is
weaker evidence than a phone for anything involving the keychain or the extension. Say which was used.

<!-- COPY END b526cfb5 -->
