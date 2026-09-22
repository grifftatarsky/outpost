---
title: The simulator rig
layout: default
nav_order: 15
---

# The simulator rig

{: .no_toc }

How to set up the four simulators this project tests on, how to drive them without taking over the
Mac, and what a simulator can and cannot do. Read this before running anything that crosses the
network.

1. TOC
{:toc}

## Set up the devices

Four simulators on iOS 26.5, run from Xcode 27, where `DeviceHub.app` replaces `Simulator.app`.
**Address them by `id=<UDID>`, never by `name=`**: a duplicate name once made `xcodebuild` boot a
shut-down twin instead of the running device.

| Name | UDID | Apple Account | Member | Points |
|---|---|---|---|---|
| `outpost-alpha`, iPhone 17 Pro | `4CB401B7-ABC0-4C00-ABEC-5BDBB84767D1` | development account A | Griff | 402 × 874 |
| `outpost-beta`, iPhone 17 Pro Max | `DADA1E7E-6CB3-44F9-B59A-5A8D4C9B7BAF` | development account B | Outie | 440 × 956 |
| `outpost-gamma`, iPhone 17 | `F7F2F5D2-5F36-4312-8A36-D5834C29CE70` | none | Trig | 402 × 874 |
| `outpost-delta`, iPhone 17 | `98E5967E-9EC6-4873-B44B-7A1E57258030` | none | Quad | 402 × 874 |

Alpha and beta are on two different Apple Accounts, and only they prove anything about CloudKit.
Gamma and delta have no account and reach each other through a directory instead; see
[members without an Apple Account](#members-without-an-apple-account). Which account's password
belongs to which device is kept outside this repository.

**Build once, install everywhere, and never leave an old build on a device.** A device running last
week's code looks exactly like a defect, and Griff has caught one twice.

```bash
xcodebuild -workspace Carpenter.xcworkspace -scheme Carpenter \
  -destination 'platform=iOS Simulator,id=4CB401B7-ABC0-4C00-ABEC-5BDBB84767D1' \
  -derivedDataPath /tmp/carpenter-dd build
for u in 4CB401B7-ABC0-4C00-ABEC-5BDBB84767D1 DADA1E7E-6CB3-44F9-B59A-5A8D4C9B7BAF \
         F7F2F5D2-5F36-4312-8A36-D5834C29CE70 98E5967E-9EC6-4873-B44B-7A1E57258030; do
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

## Drive them without taking the Mac

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

Leave `-parallel-testing-enabled NO` on every run. Without it the runner clones the simulator, shuts
the original down, and runs the step on the clone, which carries the original's keychain and Apple
Account: on 2026-09-22 a clone of alpha sent a message as alpha's own device, and beta received it.

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

## Know what a simulator can do

Measured on this Mac on 2026-09-01 and since.

| Capability | Works | Detail |
|---|---|---|
| CloudKit against a real account | yes | Unless the account has Advanced Data Protection on; see below. |
| App Group container shared with the extension | yes | `storage: … appGroup=true` in the log. |
| Push from real APNs | registers | A real sandbox token on Apple silicon. A bell rung by the other account on 2026-09-14 did not arrive in five minutes. |
| Notification service extension | not reachable | Nothing triggers it. No real push arrives, and in Xcode 27 `simctl push` goes through CoreSimulatorBridge, which adds the request directly: a payload with `mutable-content: 1` was posted as sent, with no extension process, on 2026-09-19. It ran for `simctl push` on 2026-09-01. |
| Keychain generic password items | yes | Persist across launches. `simctl uninstall` does not clear them, so uninstalling and installing again is a reinstall: on 2026-09-22 alpha came back with its keys and nothing else, and read its place back from iCloud. |
| Keychain access groups | no | Simulator builds are unsigned, so the app and extension's shared group behaves differently than on a phone. |
| Sensitive Content Analysis | yes | Judged a photo clear on 2026-09-04. A positive verdict needs Apple's test profile on a phone. |
| Secure Enclave | no | |
| A Focus | no | `INFocusStatusCenter` always says not focused. Use You › Debug › *Pretend a Focus is on*. |
| **An iCloud Keychain hand-off** | **no** | See below. |

### No iCloud Keychain hand-off

A simulator cannot join the account's Octagon trust circle. Every keychain sync view stays in
`waitfortrust`, and the *Sync this iPhone* switch for Passwords does not move:

```
<CKKSKeychainViewState(): Passwords(ckks), waitfortrust>
<CKKSKeychainViewState(): ProtectedCloudStorage(ckks), waitfortrust>
```

It reaches Apple's servers fine; it just never becomes trusted, because it has no Secure Enclave or
device attestation. So one member on two devices needs two real phones.

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

**Run the live CloudKit suite before a reset, never after.** `TEST_RUNNER_CARPENTER_CLOUDKIT_TESTS=1`
publishes real feeds into the signed-in account and leaves them there, so an account cleared and then
used for the live suite reads as occupied again — *This Apple Account already has a member* — and the
rig cannot onboard on it.

Terminate the app as soon as the erase finishes. If it keeps running, the change of session state
starts device sync again, which republishes a feed and makes the account occupied again.

`Scripts/reset-device.sh` resets a device and cannot clear iCloud, which is why the launch argument
exists.

**A simulator's iCloud can drop into `Account Temporarily Unavailable`** (CKError 36) and stay there
until the password is entered again in Settings. Only the account owner can do that.

## When a peer goes quiet

On 2026-09-04 beta read only its own zone all day, and a message from alpha was never found, because
the share link in alpha's standing offer had gone stale. It healed without re-pairing once alpha
rewrote its offer.

The fetch line names reachable zones by owner: `3 zone(s) reachable [own 945e3b fdd60b]`. Two
accounts that should be paired and each show only `[own]` are not paired. The offer line says what the
rendezvous did: `offers — 0 written, 1 standing, 0 unplaced, 0 failed` is healthy; `unplaced` means
no packet from that peer has been seen in the current window; `failed` carries the CloudKit error.
Rounds run while a room is open or on a push, so keep a conversation open on both devices.

To cause it on purpose: You › Debug › **Rotate mailbox share** on one device, then terminate that app
within the minute so the other reads the dead offer. The other logs `1 failed` with *Zone does not
exist*, retracts the offer, and shows `[own]`. Relaunch the first, and within about 90 seconds the
other reads `found 1 offer(s)` and `2 zone(s) reachable`.

## Add members without an Apple Account

A third Apple Account needs a phone number Griff does not have, so gamma and delta run with **no
Apple Account** and a different transport. A signed-out simulator has no CloudKit (every request
fails `Not Authenticated`), but it can make a member, because creating an identity needs no network.

```bash
xcrun simctl launch <udid> com.microgpt.carpenter --mailbox /tmp/outpost-rig-mailbox
```

`--mailbox` swaps in `FileMailbox`, which keeps packets in a host directory. A simulator's `/tmp` is
the host's `/tmp`, so one directory is one group of members. Launch every member of a test with the
same flag; a mix is two separate groups. Debug builds only. A device on the directory mailbox does
not start device sync: with no Apple Account it could never save its records, and it holds none of
its own writing back waiting for them.

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
the fold, keys, invitations, confirmations, and what a third or fourth member changes. Nothing below
it: zones, shares, the change feed, CloudKit's eventual consistency or push. A result from these
devices is **proved above the mailbox** and has to be written down in those words.

### What these devices have shown

- **Answering from the notification on two accounts, 2026-09-19.** Alpha's account was reset on
  Griff's word, and Griff onboarded again. Griff invited Outie over CloudKit, with codes passed through
  `--rig-codes`. Outie replied from a banner warm and cold, and marked read, and the replies drew on
  alpha. The banner's payload carried the category and room, because nothing on a simulator runs the
  extension.
- **Answering from the notification, 2026-09-19.** Trig answered Quad from the banner: Reply warm,
  Reply cold (app quit), and Mark as Read. The replies drew on Quad's device and the read mark
  crossed. Proved above the mailbox. A cold launch has no launch arguments, so its round goes to
  CloudKit, which is signed out on gamma; the reply waits on disk for a launch under `--mailbox`.

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

## What to take somewhere else

A second Apple Account can accept a share; nothing else on this Mac can. A third party over CloudKit
needs a third account, and one member on two devices needs two phones. Those are listed on
[Still to prove](roadmap.md#still-to-prove).

When you write down what you saw, say which device it ran on. A simulator is weaker evidence than a
phone for anything involving the keychain or the notification extension.
