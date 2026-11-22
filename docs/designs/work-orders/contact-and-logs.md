<!-- COPY BEGIN b499233b [NEEDS HUMAN REVIEW] -->

# Work order — plan step 7: the Contact address, and a way for a tester to hand over what the app noted

> **A working design, written by agents on 2026-11-10 and 2026-11-11 and kept so the work need not be
> done again.** Nothing in it is a ruling. Where it names a file under `scratchpad/`, that was a
> working file and was not kept. Line numbers are from the commit it names and will drift.
> What is waiting on Griff is in [the Part B plan](../../part-b-plan.md).

Source of the step: `docs/pre-testflight.md:123-124`. Read at commit `9af603a` on `overnight-2026-10-31`
(working tree had only docs and three test files modified). Line numbers below are from that state.
No Swift was built or run for this; every Swift sketch is **not compiled**.

## 0. The short version

1. One line in `Config/Branding.xcconfig` makes the Contact row appear. The value already exists in
   Griff's own commit `86f6f89` on `origin/desktop`, which never reached this branch.
2. The diagnostics export does nothing in Release because its two function bodies are inside
   `#if DEBUG`. The log lines themselves are written in every build.
3. Least change: let the gathering half compile in Release, scrub it, show it on one Settings page,
   and share it with a system `ShareLink`. No file is kept on the phone, nothing is sent by the app,
   no server.
4. Not covered, and it needs Griff's yes: the notification extension's lines and anything from
   before the last launch. Apple's platform does not let an app read either.

## 1. What is there now

### 1.1 The Contact address

| Fact | Where |
|---|---|
| Info.plist carries `ContactFormURL = $(APP_CONTACT_FORM_URL)` | `App/Carpenter/Info.plist:7-8` |
| The app reads it, with an environment fallback, and returns `nil` when empty | `Packages/Carpenter/Sources/CarpenterKit/Branding.swift:30-35` |
| `APP_CONTACT_FORM_URL` is defined nowhere on this branch; `APP_REPORT_FORM_URL` is | `Config/Branding.xcconfig:5` (only the report line) |
| The row: a `Link` titled "Report a problem" at the bottom of Privacy & Safety, drawn only when the URL is non-nil. Footer: "Opens <host> in your browser. This app sends nothing itself and publishes no address." | `Packages/Carpenter/Sources/CarpenterUI/Screens/You/Settings/PrivacyAndSafetySettingsView.swift:242-257` (copy chunk `a3421a78`) |
| An undefined build setting expands to an empty string, so the row is hidden | inferred; consistent with the message of `86f6f89`: "named by Info.plist and set nowhere, so the contact link … had never drawn in a real build" |
| The value Griff committed on 2026-09-19: `APP_CONTACT_FORM_URL = https:$(SLASH)$(SLASH)outpostmessaging.com/contact` | `git show 86f6f89 -- Config/Branding.xcconfig` (only on `remotes/origin/desktop`) |
| The same address is what the docs already promise | `docs/app-store.md:370`, `docs/app-store.md:433`, `docs/TESTFLIGHT_LICENCE.txt:6`, `docs/trust-and-safety.md:355` |
| A URL in an xcconfig must be written with `$(SLASH)$(SLASH)`; a lint checks it still has a host | `Scripts/lint/xcconfig-urls.py`, called at `Scripts/lint-branding.sh:364-372` |
| Ruling that binds here: every route to a person is a form, no address is published, and the forms have no file input | `docs/decisions.md:6328-6357` (`RULED`, Griff, 2026-09-17) |

Whether `/contact` is live today: **not verified** (the rules for this job forbid a web request
that names the product).

### 1.2 The diagnostics export

| Fact | Where |
|---|---|
| `DiagnosticsExport.write(to:window:throttled:)` reads this process's entries for the app's subsystem from `OSLogStore(scope: .currentProcessIdentifier)`, last 30 minutes, formats `ISO8601 [category] message`, writes the file atomically | `Packages/Carpenter/Sources/CarpenterKit/Platform/DiagnosticsExport.swift:10-36` |
| Its whole body is inside `#if DEBUG` … `#endif`. In Release the function is empty. This is the "does nothing" | same file, lines 13 and 35 |
| `DiagnosticsExport.note(_:)` appends a plain line to the extension's file; body also `#if DEBUG` | same file, lines 47-61 |
| The app calls `write` after every sync, to `Documents/diagnostics.log` | `App/Carpenter/AppRootView+Sync.swift:85-86` |
| The extension calls `note` six times and `write` once, to `diagnostics-extension.log` at the App Group root | `App/CarpenterNotificationService/NotificationService.swift:50,70,77,82,107,126,170` |
| The developer collects both files with a script; a member has no way to | `Scripts/pull-device-logs.sh:57-100`, `docs/testing.md:459-470` |
| No screen shows or shares either file | grep for `DiagnosticsExport.` finds only the callers above |

### 1.3 What the app logs at all

- One subsystem, `com.microgpt.carpenter`, three `Logger`s: `pairing`, `sync`, `identity`
  (`Packages/Carpenter/Sources/CarpenterKit/Platform/Diagnostics.swift:5-10`). No other `Logger(`,
  no `os_log`, no `NSLog`; `print(` only in tests.
- 315 call sites in `App` and `Packages/Carpenter/Sources`: `sync.error` 117, `sync.notice` 113,
  `identity.error` 44, `identity.notice` 41, `pairing` 0 (counted with a script over the source).
- 284 interpolated values, **every one marked `privacy: .public`**. So the text is whole in a Release
  build's system log, and `composedMessage` returns it whole. Apple: dynamic strings are redacted by
  default unless made public
  (https://developer.apple.com/tutorials/data/documentation/os/generating-log-messages-from-your-code.json).
- `notice` and `error` are both kept on disk by the system "up to a storage limit"; old messages are
  purged to make room (same URL).
- The same lines therefore sit in the phone's own system log in every build, whether or not anybody
  shares anything. A sysdiagnose would hold them. See question 9 in section 7.

### 1.4 What a line can hold

Read from all 284 interpolations (list kept at
`/private/tmp/claude-501/-Users-grifftatarsky-projects-outpost/f313c3e3-558d-46ba-9bcc-c43ae72ae298/scratchpad/design/work/interps.tsv`).

| What | Can a line hold it? | Where |
|---|---|---|
| Message text, a post, a comment, a blurb | No. No interpolation carries one. | whole list |
| A person's, room's or device's name | No. Every `name` variable in a log call is a fingerprint. | `AppSession+Attachments.swift:66`, `AppSession+Outpost.swift:100` |
| A key or a secret | No. | whole list |
| A short code for a person, device, photo or push token: first 8 hex of SHA-256, unsalted, the same on every phone | Yes: 10 interpolations directly, 6 more through a `name` variable, and every refusal summary | `Diagnostics.swift:12-15`; e.g. `AppSession+DeviceSync.swift:90,161`, `AppSession+Outpost.swift:378,446,554`, `PushRegistration.swift:38`, `SyncSession.swift:56-59` |
| The device approval code | Yes, 3 sites. It is derived from the new device's public keys and is shown on screen. | `AppSession+Approval.swift:20-21,41,56`; `DeviceApproval.swift:19-34` |
| The storage folder's full path: the container UUID, the bundle identifier (which holds the source name in lower case), and on a simulator the Mac user's name | Yes, 1 site, every launch | `App/Carpenter/OnDiskStorage.swift:21-22`; container name is the bundle id, `App/Carpenter/AppRootView+TestProfiles.swift:20` |
| **A system error's own text** via `String(describing: error)` | Yes, 125 sites plus `error.localizedDescription` twice. This is the one input the app does not choose. | e.g. `CloudKitEntrySync.swift:202-203,388-389`, `AppRootView.swift:164-165,176-177`, `AppSession+HistoryRepair.swift:410-411,420-421` |
| …a CloudKit error names records and zones. Record names are packet and attachment UUIDs, full device IDs in hex (`feed-<device>`, `request-<device>`, `approval-<device>-<device>`), photo copy names in hex; pair zones are `Pair-<UUID>`; a shared zone carries its owner's account record name. | inferred from how the names are built: `CloudKitRecords.swift:28,32`, `SiblingMail.swift:62-70`, `PhotoCopy.swift:24-28`, `CloudKitMailbox+Pairs.swift:167,223`. The exact text of a `CKError` description was **not verified**. |
| …a file error names a path and a file (`log.carpenter`, `state.json`) | inferred | `StorageLocation.swift:13-17` |
| …a decoding error can print module-qualified type names (the source name with a capital) and dictionary keys, which here are IDs | inferred, not verified |
| The app's own error enums carry no identifier | verified by reading each | `Replica.swift:22-27`, `MembershipAttestation.swift:172-192`, `CanonicalBytes.swift:48-63`, `SyncEngine.swift:24-27`, `Mailbox.swift:56-62`, `LogStore.swift:36-40`, `MailboxFailure.swift:3-6`, `SessionModels.swift:68-85`, `SystemKeychainStore.swift:233-239` |
| When the member sent and received, how many items, how big, how many rooms and people | Yes. That is what the log is for. | throughout |

### 1.5 Platform facts

- `OSLogStore.Scope` has `currentProcessIdentifier` and `system`; the type is iOS 15+
  (https://developer.apple.com/tutorials/data/documentation/oslog/oslogstore/scope.json).
- On iOS an app reads only its own process. Apple DTS: "It gives you log entries for the current
  process. It doesn't include log entries for any other process, and the fact that app extensions
  are related to the current process doesn't change that," and "It doesn't even give you log
  entries for previously instances of the current program"
  (https://developer.apple.com/forums/thread/697734). A relaunch is a new process ID
  (https://developer.apple.com/forums/thread/691093).
- How far back the entries go depends on the whole system's log load, per Apple DTS
  (https://developer.apple.com/forums/thread/716924). So the file may be short.
- One developer reports that on iOS 17 the position passed to `getEntries` is ignored and every
  entry comes back (https://developer.apple.com/forums/thread/737223). One report, no Apple
  confirmation. Filtering on `entry.date` as well costs one clause.
- `ShareLink` shares anything `Transferable`, iOS 16+
  (https://developer.apple.com/tutorials/data/documentation/swiftui/sharelink.json). HIG: "Use the
  Share button to display an activity view" and "Avoid creating duplicate versions of common actions
  that are already available in the activity view"
  (https://developer.apple.com/tutorials/data/design/human-interface-guidelines/activity-views.json).
  So: the system share control, and no separate Copy button.
- TestFlight already gives the developer crash reports and tester screenshots with comments, in App
  Store Connect (https://developer.apple.com/testflight/). That path goes through Apple and carries
  none of the app's own lines (inferred from that page: it lists screenshots, comments and crash
  reports only).

## 2. What it must guarantee — Griff confirms these before code (CLAUDE.md, "Before building", rule 1)

1. Nothing leaves the phone unless the member taps Share and picks where it goes. The app keeps no
   copy of it and sends nothing itself.
2. What is shared is exactly what the page lists, line for line.
3. It holds no message text, no name of a person, room or device, no photo and no key. People,
   devices and photos appear only as 8-character codes. Every longer identifier (iCloud record, zone
   and account names, file paths, the source name) is replaced before the member sees it.

One exception to sentence 3, to be said out loud: a new device's approval code appears as it is
(`AppSession+Approval.swift:20-21,41,56`). The member has already seen it on screen and it is spent
once the device is approved. Recommendation: leave it.

Who it must stop: nobody new. A person holding the unlocked app can already read the messages. The
recipient of the file is the one to think about, which is why sentence 3 exists.

## 3. The change

Five commits, in this order. Each is small; C and D are the feature. A and B can go ahead once
Griff answers item 1 of section 7. C, D and E wait for his answer on the sentences in section 2.

### Commit A — define the address

`Config/Branding.xcconfig`, after line 5, add exactly:

```
APP_CONTACT_FORM_URL = https:$(SLASH)$(SLASH)outpostmessaging.com/contact
```

`Scripts/check-release-leaves.sh`: after the `LEAVES` loop (line 74) and before the summary at line
76, read the built plist back, so "the row never shows" becomes a failing check:

```bash
CONTACT=$(/usr/libexec/PlistBuddy -c 'Print :ContactFormURL' "$APP/Info.plist" 2>/dev/null)
case "$CONTACT" in
    https://?*/?*) ;;
    *) echo "error: a Release build has no contact address (ContactFormURL is \"$CONTACT\")"; status=1 ;;
esac
```

Do **not** bring the rest of `86f6f89` (the blog link) in this commit. That belongs to plan step 2.

### Commit B — one text-file type, moved (a cleanup, its own commit)

`ReportView.swift:6-16` holds `private struct ReportFile: Transferable` (text, name, plain-text
`DataRepresentation`, `suggestedFileName`). The new page needs the same thing.

- New file `Packages/Carpenter/Sources/CarpenterUI/Components/Shared/SharedTextFile.swift`: the same
  struct, internal, named `SharedTextFile`, with its `CoreTransferable` and `UniformTypeIdentifiers`
  imports.
- `ReportView.swift`: delete lines 6-16; change the type at lines 57-59 to `SharedTextFile`.
- CLAUDE.md's trap applies (a private member moved to a sibling file): delete derived data, build,
  and read the warnings. The name `SharedTextFile` was not checked against the SDKs.

### Commit C — gather in every build, write the file only in Debug, and scrub

`Packages/Carpenter/Sources/CarpenterKit/Platform/DiagnosticsExport.swift`. Split what `write` does
today into a gatherer that compiles everywhere and a file writer that stays Debug-only:

```swift
public static let mostLinesHandedOver = 4_000
public static let longestLineHandedOver = 1_000

public static func lines(since start: Date) -> [String]? {
    guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return nil }
    let predicate = NSPredicate(format: "subsystem == %@", Diagnostics.subsystem)
    guard let entries = try? store.getEntries(at: store.position(date: start), matching: predicate)
    else { return nil }
    var lines: [String] = []
    for case let entry as OSLogEntryLog in entries where entry.date >= start {
        lines.append("\(entry.date.ISO8601Format()) [\(entry.category)] \(entry.composedMessage)")
    }
    return lines
}

public static func handedOver(since start: Date) -> [String]? {
    lines(since: start).map { DiagnosticsScrub.scrubbed($0.suffix(mostLinesHandedOver)) }
}
```

`write(to:window:throttled:)` keeps its `#if DEBUG`, its throttle, and its early return, and calls
`lines(since:)` instead of repeating lines 24-32. `note(_:)`, `documentsURL`, `groupURL` unchanged.
`nil` means the store could not be read; an empty array means nothing was noted. The page says
which.

New file `Packages/Carpenter/Sources/CarpenterKit/Platform/DiagnosticsScrub.swift`:
`public enum DiagnosticsScrub { public static func scrubbed(_ lines: some Sequence<String>) -> [String] }`.
Per line, in this order:

| # | Replace | With | Why |
|---|---|---|---|
| 0 | the source name in any letter case. Take it from the code, not a new literal: the last dot-separated part of `Diagnostics.subsystem`. Foundation's `replacingOccurrences(of:with:options: .caseInsensitive)`. | `<app>` | bundle id, App Group id, `log.carpenter`, module-qualified type names in error text |
| 1 | `(?:file://)?/(?:private/var|var|Users)/[^\s,;"'”’)}\]]*` | `<path>` | container UUID, Mac user name on a simulator |
| 2 | `[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}` | `<id>` | packet, attachment, pair-zone and request UUIDs |
| 3 | `(?<![0-9A-Za-z])_?(?=[0-9A-Fa-f]*[A-Fa-f])[0-9A-Fa-f]{9,}(?![0-9A-Za-z])` | `<id>` | device IDs, photo copy names, account record names (`_` + hex). Leaves 8-character codes, plain numbers and `0x…` pointers alone. |
| 4 | `(?<![A-Za-z0-9+/_=-])(?=[A-Za-z+/_-]*[0-9])(?=[0-9+/_-]*[A-Za-z])[A-Za-z0-9+/_-]{32,}={0,2}` | `<id>` | any long opaque token, should one ever appear |

Then cut each line to `longestLineHandedOver` characters. Both bounds are constants in code (CLAUDE.md: every size
that arrives from elsewhere has a bound; a CloudKit partial failure can be very long).

Notes for whoever writes it: `Regex` is not `Sendable`, so a `static let` of one will not compile
under Swift 6 strict concurrency; build the patterns inside the function, or use
`NSRegularExpression`. The patterns were run against the vectors in section 5 in Python's `re`
(`/private/tmp/claude-501/-Users-grifftatarsky-projects-outpost/f313c3e3-558d-46ba-9bcc-c43ae72ae298/scratchpad/design/work/scrubcheck.py`,
all pass). They were **not** run in Swift or ICU; the Swift tests are what counts.

One thing pattern 1 does not do: a path with a space in it is cut at the space. The fallback store
under `Application Support` would come out as `<path> Support/com.microgpt.<app>/state.json`. The
UUID and any user name are before the space and are gone; what is left names no one. Keep that case
as a vector so nobody is surprised by it.

Optional, same commit or dropped: `App/Carpenter/AppRootView+Sync.swift:85-87` creates the Documents
folder and starts a detached task that does nothing in Release. Wrapping those three lines in
`#if DEBUG` is tidy and not required.

### Commit D — the page and its row

New file `Packages/Carpenter/Sources/CarpenterUI/Screens/You/Settings/TroubleshootingView.swift`.
Shape (house components, same chrome as `PrivacyAndSafetySettingsView.swift:258-263`):

- `List` with `.scrollContentBackground(.hidden)`, `.background(palette.background)`, a
  `.navigationTitle`.
- `SettingsHeaderCard` first (`SettingsChrome.swift:115`): the explanation lives there, not in a
  footer on the root.
- One `@State private var noted: [String]?` and one `@State private var unreadable = false`. A
  `.task` fills them off the main actor:
  `await Task.detached(priority: .userInitiated) { DiagnosticsExport.handedOver(since: start) }.value`,
  with `start` 24 hours before `clock.now` (`@Environment(\.clock)`, as `ReportView.swift:22`).
  Three header lines are put at the front of that same array:
  `"\(Branding.displayName) \(Branding.version)"`,
  `ProcessInfo.processInfo.operatingSystemVersionString`, and the time it was gathered.
- While loading: `ProgressView`. Then a `Section` holding
  `ShareLink(item: SharedTextFile(text: noted.joined(separator: "\n") + "\n", name: fileName), preview: SharePreview(fileName, image: Image(systemName: "doc.text")))`
  with **no custom label**, so it is the system's Share control.
- Then a `Section` whose rows are the same array: `ForEach(noted.indices, id: \.self)` of
  `Text(verbatim: noted[$0]).font(.caption2.monospaced())`. The file and the list come from one
  array, which is what makes guarantee 2 true by construction.
- No animation, no glass, no `Button`, no confirmation dialog: the share sheet is the choice and can
  be cancelled (my judgment; the HIG alerts page was not re-read for this).
- `CarpenterUI` calling a `CarpenterKit` static directly has precedent
  (`PrivacyAndSafetySettingsView.swift:243`, `ReportView.swift:47`). Doing it this way adds no
  parameter to `YouView`, which is the "two constructions drift" trap.

Row: `Packages/Carpenter/Sources/CarpenterUI/Screens/You/YouView+Settings.swift`, in `gettingHelp`,
after line 270 (`// COPY-END 93d36060`) and before line 271 (`#if DEBUG`), in its own new copy
pair:

```swift
NavigationLink {
    TroubleshootingView()
} label: {
    SettingsRow(
        icon: "stethoscope", tone: .device,
        title: Text("Troubleshooting", bundle: .module))
}
```

The symbol name is **not verified**; the lint checks it (`Scripts/lint-branding.sh:215-233`). If it
fails, `doc.text.magnifyingglass`.

Copy, drafted for review. Every chunk gets a pair from `python3 Scripts/copy-review.py new-id`,
status `NEEDS HUMAN REVIEW`, and `bundle: .module`. It avoids "log" and "entry" (Griff's copy terms,
2026-11-10) and names no destination (ruling of 2026-09-17).

| Where | Draft |
|---|---|
| Row title, navigation title | Troubleshooting |
| Card title | Troubleshooting details |
| Card paragraph | A list of what this app did recently: when it sent and received, how much, and any errors. It has no messages, no names, no photos and no keys. |
| Footer under Share | This app sends nothing itself. You choose where the file goes. |
| Header over the lines | What is shared |
| Footer under the lines | People, devices and photos appear as short codes. A code is the same in every file, so somebody who already knows one can recognise it. |
| Nothing noted | Nothing has been noted since this app started. |
| Could not be read | The list could not be read on this phone. |
| File name (as `ReportView.swift:50-55`) | `"\(Branding.displayName) troubleshooting \(day)"` |

New keys must end up in `Packages/Carpenter/Sources/CarpenterUI/Resources/Localizable.xcstrings`.
Whether a command-line build adds them was **not verified**; check `git status` after building and
add them by hand if it did not (the form is `"Key" : { },` as at lines 2690-2692).

### Commit E — the record

- `docs/decisions.md`: one `PROPOSED` entry (Claude), in its own copy pair: a member can hand over
  what the app noted through the share sheet; what is replaced; what it costs (a pattern list has to
  be kept up; no extension lines; nothing from before the last launch); what would change it. Mark
  it `RULED` only if Griff says so.
- `docs/pre-testflight.md:123-124`: status of step 7.
- `docs/testing.md:459-470`: one sentence that a Release build has the page and no file.
- `docs/open-questions.md`: questions 5, 6 and 9 from section 7, each with its recommendation.
- `docs/inbox.md`: the three things noticed in section 8.
- `docs/app-store.md:111-125`: one sentence for question 7 once Griff answers it.

## 4. What done looks like

1. A Release build's `Info.plist` has `ContactFormURL = https://outpostmessaging.com/contact`, and
   `Scripts/check-release-leaves.sh` fails without it.
2. In Privacy & Safety, "Report a problem" is the last row and opens that address in the browser.
3. In a **Release** build on a simulator: Settings ▸ Troubleshooting lists lines within a second or
   two of opening, among them `storage: <path> appGroup=true` and `load: ready`
   (`OnDiskStorage.swift:21-22`, `AppSession+Identity.swift:95`).
4. Share ▸ Save to Files, then read the file from that simulator's File Provider Storage on the Mac
   (or Share ▸ Copy and `xcrun simctl pbpaste <udid>`, if Copy puts text on the pasteboard; not
   verified). The text equals the list, and `grep -i` finds no `carpenter`, no `/Users/`, no UUID,
   no hex run of nine or more with a letter in it.
5. The three sentences in section 2 hold in that run, and the tests in section 5 pass.
6. The Debug build's `Documents/diagnostics.log` is unchanged, so `Scripts/pull-device-logs.sh`
   still works.
7. The Debug build is put back on any simulator the Release build was installed on (CLAUDE.md: never
   leave a stale build on a sim).

## 5. Tests

New, in `Packages/Carpenter/Tests/CarpenterKitTests`, suites named as sentences.

**A. The scrub, by vector** (pure, fast). Each input must come out as shown:

| In | Out |
|---|---|
| `storage: /private/var/mobile/Containers/Shared/AppGroup/3F2504E0-4F89-41D3-9A0C-0305E82C3301/com.microgpt.carpenter appGroup=true` | `storage: <path> appGroup=true` |
| `storage: /Users/someone/Library/Developer/CoreSimulator/Devices/5A43F953-128D-4FE6-9135-0D26520E02B6/data/x appGroup=true` | `storage: <path> appGroup=true` |
| `UserInfo={NSFilePath=/private/var/mobile/a/state.json, NSURL=file:///private/var/mobile/a/state.json}` | `UserInfo={NSFilePath=<path>, NSURL=<path>}` |
| `zoneID=Pair-3F2504E0-4F89-41D3-9A0C-0305E82C3301:_0123456789abcdef0123456789abcdef` | `zoneID=Pair-<id>:<id>` |
| `recordName=approval-` + 64 hex + `-` + 64 hex | `recordName=approval-<id>-<id>` |
| `op = 1A2B3C4D5E6F7A8B; uuid = 0A1B2C3D-1111-4222-8333-444455556666` | `op = <id>; uuid = <id>` |
| `entry from 3fa9c1d2: badSignature` | unchanged (an 8-character code stays) |
| `was 123456789012 bytes` and `<CKError 0x16f2a3b40: …` | unchanged |
| `Error Domain=CarpenterKit.CryptoError Code=3` | holds no `carpenter` in any case |
| `The file “log.carpenter” couldn’t be opened.` | holds no `carpenter` in any case |
| a 43-character base64url run with digits | `<id>` |
| `/private/var/mobile/Containers/Data/Application/<UUID>/Library/Application Support/com.microgpt.carpenter/state.json` | `<path> Support/com.microgpt.<app>/state.json` |
| `approval: a new device asked to join (K7Q2-M9XD)` and `device-feed.v1 zoneIDsWithUnfetchedServerChanges=3` | unchanged |
| 10,000 lines in | the last 4,000 out |
| one line of 100,000 characters | at most 1,000 |

The CloudKit rows are shaped from how the app builds names, not copied from a real error. On the
first live failure seen on the rig, add its real text as a vector.

**B. What the app really writes** (the test that tries to break sentence 3). `@MainActor`,
`.serialized`. Note the time. Make two sessions with `TestSession.make()` as
`AMessageReachesEveryoneItIsForTests.swift:33-45` does, give them display names, a room name and a
message that are unmistakable canaries, let them sync through a `HookedMailbox`, and revoke a
device or force one failing write so an error line exists. Then call
`DiagnosticsExport.handedOver(since:)`, the function the page calls, and require: at least one line
came back (fail loudly on none; wait by attempts, not seconds); no line holds a canary; no line
holds either participant's ID in hex, the room's UUID, or `carpenter` in any case. That
`OSLogStore` returns the test process's entries under `swift test` is **not verified**; macOS has
the scope since 12.0 (URL in 1.5). If it cannot, say so and keep A; do not let B pass empty.
Run B ten times (CLAUDE.md, "count to ten").

Existing, to run:

```bash
cd Packages/Carpenter && swift test --filter <the two new suites>
cd Packages/Carpenter && swift test
./Scripts/lint-branding.sh
python3 Scripts/copy-review.py check && python3 Scripts/copy-review.py report
xcodebuild -workspace Carpenter.xcworkspace -scheme Carpenter -destination 'platform=iOS Simulator,id=5A43F953-128D-4FE6-9135-0D26520E02B6' build
xcodebuild test -workspace Carpenter.xcworkspace -scheme Carpenter -destination 'platform=iOS Simulator,id=5A43F953-128D-4FE6-9135-0D26520E02B6' -only-testing:CarpenterTests
Scripts/check-release-leaves.sh
```

Nothing here crosses the network, so the two-account rig is not what proves it. A Release build on
one simulator is (section 4, items 3-4), because Debug never runs the Release half of
`DiagnosticsExport`.

## 6. Risks

1. **The scrub is a list of patterns.** A shape nobody listed gets through. What limits the damage:
   the member reads every line first; the app's own words carry no identifier longer than 8
   characters; test B runs the real lines. What would remove the risk is question 9.
2. **The file can be short or empty.** Only this launch, only as far back as the system kept, and
   never the extension. The copy says "recently" and promises no span.
3. **`OSLogStore` speed on a phone is not measured.** It runs off the main actor behind a
   `ProgressView`. If a day's window takes more than a couple of seconds on an iPhone, shorten it.
4. **Test B may be flaky** under the full parallel run (shared process, log latency). Serialized,
   waits by attempts, ten runs before trusting it.
5. **Release-only code.** The rig runs Debug. Item 3 of section 4 is the only thing that exercises
   it; skip it and the word is "not verified".
6. **Strings and symbol.** New keys may not reach the catalogue from the command line; `stethoscope`
   may not exist. Both are caught by the build and the lint, not by reading.
7. **Other work on this branch.** Files touched: `Config/Branding.xcconfig`,
   `Scripts/check-release-leaves.sh`, `DiagnosticsExport.swift`, `ReportView.swift`,
   `YouView+Settings.swift`, `Localizable.xcstrings`, three new source files, two new test files,
   six docs. `YouView+Settings.swift` and the catalogue are the likely collisions with the copy and
   sheet steps.
8. **The address is not checked.** If `/contact` is down, the row opens an error page.
9. **The share sheet may make its own temporary copy** while it is open (inferred, not verified).
   Sentence 1 says the app keeps none, which is what the code can promise.

## 7. Only Griff

1. **The address.** Is `https://outpostmessaging.com/contact` live and still the one? It is his value
   from `86f6f89`; nobody here could load it.
2. **Where a tester sends the file.** No address is published and the site's forms take no file, so
   the app names no destination. He has to tell testers himself: the TestFlight notes, AirDrop,
   Messages, or the feedback address App Store Connect asks him for
   (https://developer.apple.com/testflight/).
3. **The three sentences in section 2.** Confirm or change them before code.
4. **Who sees the row.** Recommendation: every build. It sends nothing, and an App Store member
   with a problem needs the same thing. The alternative is TestFlight only, through the
   `DistributionChannel` the app already works out (`App/Carpenter/AppRootView+Supporter.swift:8-22`).
5. **The 8-character codes.** They are the same on every phone, so Griff, who knows his testers'
   IDs, can tell which of them a file mentions. Recommendation: keep them, because matching one
   phone's file against another's is how a sync fault is found, and say so on the page (the footer
   drafted above). The alternative is to renumber them per file and lose that.
6. **What the file cannot hold.** Lines from the notification extension, and anything before the
   last launch. Crashes reach him through TestFlight anyway. Recommendation: accept both for the
   first tester build; if banners turn out to be what testers report, let the extension keep a small
   scrubbed file in the shared container and append it. That is a file at rest, so it is his call.
7. **The privacy label.** `docs/app-store.md:113` answers "we do not collect data". A file a tester
   chooses to send through their own Mail or Messages is not the app transmitting anything, and
   Apple says optional feedback and support requests may not need disclosing when four listed
   conditions hold (https://developer.apple.com/app-store/app-privacy-details/). Recommendation: no
   change to the answer, one sentence of reasoning added to the doc. His to confirm.
8. **The copy.** About eight new chunks, `NEEDS HUMAN REVIEW`. Only a person moves them.
9. **Should a system error's text be in the phone's log at all?** Today 125 lines put it there in
   the clear, in every build, and a sysdiagnose would carry it. The fix at the source is one
   function that logs an error's domain and code and nothing else, used at those 125 sites; then
   patterns 1-4 have little left to do. It makes his own rig logs thinner unless Debug keeps the full
   text. Recommendation: yes, as its own commit after this step, not inside it.
10. **A leftover address.** `Packages/Carpenter/Sources/CarpenterUI/Screens/You/YouView.swift:64-67`
    still holds `mailto:updates@…`, a published address, against the 2026-09-17 ruling. His commit
    `86f6f89` replaced it with a blog link (`RULED` 2026-09-19 in that commit's `decisions.md`) and
    never reached this branch. It is plan step 2's, flagged here because it sits beside this work.

## 8. Noticed, not part of this step

- `Diagnostics.pairing` has no caller (`Diagnostics.swift:8`).
- In a Debug build the extension's `note` lines are replaced at each banner: `write` at
  `NotificationService.swift:170` rewrites the same file atomically
  (`DiagnosticsExport.swift:34`). Found by reading, not measured. `docs/testing.md:469` also says
  the extension "cannot use `OSLogStore`" while that line uses it.
- `docs/crypto-brief.md:1432` says the diagnostics files are out of backups. `documentsURL` and
  `groupURL` (`DiagnosticsExport.swift:41-45,63-67`) are not under the folder
  `StorageLocation.leaveOutOfBackups` marks (`StorageLocation.swift:36-56`). True in Release only
  because nothing is written there. Not verified further.

## 9. A smaller alternative, if Griff wants less

No page: a single `ShareLink` row in `gettingHelp` whose `Transferable` gathers and scrubs when the
sheet asks for it. About fifteen lines of UI. It breaks guarantee 2 as written, because the member
is not shown the lines first, so it is not the recommendation.

<!-- COPY END b499233b -->
