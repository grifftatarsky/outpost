<!-- COPY BEGIN ae137056 [NEEDS HUMAN REVIEW] -->

# Work order: plan step 12, the copy

> **A working design, written by agents on 2026-11-10 and 2026-11-11 and kept so the work need not be
> done again.** Nothing in it is a ruling. Where it names a file under `scratchpad/`, that was a
> working file and was not kept. Line numbers are from the commit it names and will drift.
> What is waiting on Griff is in [the Part B plan](../../part-b-plan.md).

Written 2026-11-10, read-only, against `overnight-2026-10-31` at `9af603a`. Line numbers are from that
tree. Another process was staging test files while this was written, so check the opening words of
each string before replacing it, and work from the bottom of a file upwards so the numbers hold.

Nothing here was built or run. Every code fact has a file and line. Every web fact has the URL it was
read at on 2026-11-10. "Not verified" and "inferred" mean what they say.

In this folder:

- `/private/tmp/claude-501/-Users-grifftatarsky-projects-outpost/f313c3e3-558d-46ba-9bcc-c43ae72ae298/scratchpad/design/step-copy.md`: this file.
- `/private/tmp/claude-501/-Users-grifftatarsky-projects-outpost/f313c3e3-558d-46ba-9bcc-c43ae72ae298/scratchpad/design/step-copy-current.json`: every Swift string over 200 characters as it stands (file, line, length, text, chunk). An interpolation is written `%@`.
- `/private/tmp/claude-501/-Users-grifftatarsky-projects-outpost/f313c3e3-558d-46ba-9bcc-c43ae72ae298/scratchpad/design/step-copy-proposed.json`: every replacement below, keyed by row id, exactly as it goes between the quotes in Swift (`proposed`), with the current text beside it (`current`, interpolations written `%@`).
- `/private/tmp/claude-501/-Users-grifftatarsky-projects-outpost/f313c3e3-558d-46ba-9bcc-c43ae72ae298/scratchpad/design/tools/catalogue_check.py`: a read-only check of the catalogues against the source (section 9).

## 1. What was measured

| Thing | Count | How |
|---|---|---|
| String catalogues | 3 | `CarpenterUI` 1,267 keys, `CarpenterApp` 36, `CarpenterKit` 69, all under `Packages/Carpenter/Sources/<module>/Resources/Localizable.xcstrings` |
| Catalogue strings over 200 characters | 65, all in `CarpenterUI` | parsed the JSON; taken to be the plan's 65 (inferred: the plan gives no method) |
| Of those 65, still in the Swift word for word | 42 | compared each key with every string literal in the module |
| Of those 65, no longer in the Swift | 23 | the source was shortened on 2026-11-10 (`c8bc149`) and the catalogue committed with it still holds the old text |
| Catalogue keys with no matching literal at all | about 80 in `CarpenterUI`, 1 in `CarpenterApp`, 0 in `CarpenterKit` | approximate: a string built with `+` is not followed |
| Swift literals over 200 characters inside a COPY chunk | 63 | 62 strings on screens, and the text of the recovery key file |
| Of the 62, in a chunk at `HUMAN REVIEWED, UNVERIFIED` | 6 strings in 5 chunks, all on How this works | the other 56 are already `NEEDS HUMAN REVIEW` |
| `python3 Scripts/copy-review.py report` | 1,443 / 36 / 0, 1,479 chunks, `check` exits 0 | run 2026-11-10 |

So the work is on the 62 strings in the Swift. The catalogue is cleaned at the end (section 9): it has
no markers, and 23 of its 65 long keys are text no screen shows any more. Those 23 still carry the
words the 2026-11-10 pass took out of the source ("the ask", "drawn", "collected", "log"), and a
catalogue is compiled into the app, so they would ship in the bundle.

Left alone, with the reason:

| String | Why |
|---|---|
| `CarpenterKit/Crypto/Identity.swift:58` (513) | The reason inside a `DecodingError`. No member reads it, it is in no COPY chunk and no catalogue. |
| `CarpenterUI/Screens/You/TestProfiles/TestProfilesView.swift:23` (366) | The whole file is inside `#if DEBUG` (line 1), so it is not in a tester build. |
| `CarpenterKit/Crypto/RecoveryKey.swift:58` (494), chunk `eb7806ac` | The text of the recovery key file, not a screen. It is not localized and not in a catalogue. One sentence is loose: "It was shown once, when you set up" (the app can show it again until the member marks it saved, `CarpenterApp/Session/AppSession+Identity.swift:479-506`). Left for Griff: it reads as his own wording (G10). |
| `MarkFrames.swift`, `DemoOutpost.swift`, `Screens/You/Debug/*`, the test targets | Drawing paths, demo content, debug screens and test messages. |

## 2. The rules the new words follow

- Griff's terms (`memory/outpost-copy-terms.md`): request, shown, received, saved history, item or
  message. A settings footer says what the setting does in one or two sentences, and says "When this
  is off, …" only when the off state is not obvious from the title.
- CLAUDE.md's honesty rules: present tense means it is in the build; no inference reported as a
  measurement; nothing claimed about delivery or reading that was not observed.
- Apple's writing guidance, read at
  `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/writing.json` (the
  data behind https://developer.apple.com/design/human-interface-guidelines/writing): "Check each
  word to be sure it needs to be there. If you can use fewer words, do so." "Describe what it does
  when turned on, and people can infer the opposite." "Avoid using *we* altogether because it may be
  unclear who the 'we' in question refers to."
- Apple's alert guidance, read at
  `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/alerts.json`: "If you
  need to add an informative message, keep it as short as possible". "Avoid explaining alert
  buttons."
- Every proposal is 200 characters or fewer, counted the way the catalogue counts (an interpolation
  is `%@`). The product's name is always `\(Branding.displayName)`. "Outpost" appears only as the
  word for a member's page.

## 3. How the COPY markers apply

**In Swift.** Every string a member reads sits between `// COPY BEGIN <id> [<status>]` and
`// COPY END <id>`. `Scripts/copy-review.py` finds markers with
`COPY (BEGIN|END) ([0-9a-f]{8})\b(.*)` and reads the status with `^ \[(NEEDS HUMAN REVIEW|HUMAN REVIEWED, UNVERIFIED|HUMAN REVIEWED & VERIFIED)\]`
(`Scripts/copy-review.py:23-25`), so the status is one space after the id, in square brackets,
spelled exactly.

1. Changing words inside a chunk: edit the string, then make sure the `COPY BEGIN` line of that chunk
   reads `[NEEDS HUMAN REVIEW]`. Do not touch the id, the `COPY END` line, or where either line sits.
2. A chunk can hold several strings. `92143e53` holds all six welcome tour panels and `43e010c0`
   holds three comparison cards. The status is for the whole chunk, so one changed string sends the
   whole chunk back.
3. 56 of the 62 long strings are in chunks already at `NEEDS HUMAN REVIEW`: for those the marker line
   does not change. The five chunks at `HUMAN REVIEWED, UNVERIFIED` that this order touches are
   `04884ac4`, `614f14c4`, `1675ec4f`, `85f818ac` and `1b29af76`, all in
   `CarpenterUI/Screens/Identity/HowItWorksView.swift`. `7d330d05` joins them if H23 is applied.
   Changing any of them undoes a review Griff did, so they wait for his yes (G2).
4. Never move a status forward. Only a person does that.
5. New copy that goes inside an existing chunk needs no new marker. New copy outside any chunk gets a
   new pair, with an id from `python3 Scripts/copy-review.py new-id` and the status
   `NEEDS HUMAN REVIEW`. In this order that is L17c only if it is placed outside chunk `93d56db0`
   (put it inside and no new pair is needed).
6. Copy that is deleted takes its markers with it. In this order that is chunk `095e4033` only if
   Griff chooses to remove the alert (G5).
7. Every `Text` keeps `bundle: .module`. The lint fails without it.
8. `python3 Scripts/copy-review.py check` must exit 0 afterwards, and `./Scripts/lint-branding.sh`
   runs the same check.

**In the catalogues.** There are no markers and there cannot be: "The three string catalogs, because
JSON takes no comments and the words are written in the source" (`docs/decisions.md:6431-6432`). A
catalogue key is the English text itself, so a changed string is a new key and the old key is left
behind. The review status of a catalogue string is the status of the Swift chunk its words are in.
Nothing in the catalogue is edited to record a review. Section 9 says how to bring the catalogue
back in line.

**In `Info.plist` and the docs.** The same markers in the file's own comment (`<!-- … -->`). This
order touches `App/Carpenter/Info.plist` only under G8, and the docs only when the work is written
up (section 10).

## 4. What only Griff can decide

Apply every row of class S or F without waiting. Hold every row of class G until he answers. Where a
default is given, it is what to do if he has not answered.

| # | Question | Recommendation | Default |
|---|---|---|---|
| G1 | The page that names Signal, iMessage, WhatsApp and Facebook Messenger makes claims that are wrong or were not found at the source (section 7). Keep the named cards with the checked text, or take the named cards out of the app? Either way, may the app say that Apple can see which Apple Accounts exchange sealed messages (`docs/crypto-brief.md:828-829`)? The welcome tour's "Compared to Other Apps" panel (L07) turns on the same answer. | Keep the cards, with the text in section 7, and say what Apple can see. | Hold H118, H128, H132, H136, H142 and L07. |
| G2 | Seven strings on How this works are in chunks he reviewed (six over 200, and H23). Five state something the build does not do (H23, H34, H68, H86, H142). Two are only long (H33, H77). Changing any of them sets his review of that chunk back to `NEEDS HUMAN REVIEW`. | Change the five with a wrong fact. Leave the two that are only long unless he wants them shorter. | Hold all seven. |
| G3 | "Source & Review" says "we solicit external security reviews" and "scanned and tested for vulnerabilities thoroughly before releases". He ruled on 2026-09-14 for no outside reviewer (`docs/decisions.md:1534-1541`). Is the repository public on GitHub with contributor instructions (not verified; `README.md:98-104` has a short section)? What should the app say has been checked, and by whom? | H68: open source, nobody outside the project has reviewed it, and where to report a problem. | Hold H68. |
| G4 | The bar says "One Year Free for TestFlight users" (his ruling, `docs/decisions.md:233-244`). Nothing can be bought: the only StoreKit call reads how the copy was installed (`App/Carpenter/AppRootView+Supporter.swift:22`). The year is a date in the member's own preferences (`CarpenterApp/Session/AppSession+Supporter.swift:39-44`). Keep the bar and make the page behind it say what is true today (section 8), or hide the bar until the purchase is built? May the app state the price? Does the year survive erasing everything, which starts a new identity (inferred: the claim is kept in that identity's preferences)? | Keep the bar. Apply section 8. | Apply S32, S43, S50 (they only correct tense and the start date). Hold S48, S60, S65. |
| G5 | After the lock is turned on, an alert asks "Make notifications private too?" and says anyone holding the phone can read them. With the lock on, this phone's banners already say only that something arrived (`App/CarpenterNotificationService/NotificationService.swift:56-79`). The choice still changes the member's other devices, because the level is a synced preference (`CarpenterKit/Sync/SiblingFeed.swift:40`). Reword it (K390t, K402), or remove the alert and the code only it uses? | Remove it: one fewer alert, and each device's lock already covers that device. It is a code change with tests to delete (section 6). | Reword: apply K390t and K402. |
| G6 | *Erase everything* after wrong codes says "on every device and in iCloud". When the app was started behind the lock, the other devices are not told (`docs/pre-testflight.md:104-107`, his open decision 5; `App/Carpenter/AppRootView+Device.swift:150-153`, `CarpenterApp/Session/AppSession+Deathmark.swift:22-25`). K672 says what the build does today. If he chooses the signed notice kept outside the vault, the old sentence becomes true again. | Apply K672 now. | Apply K672. |
| G7 | The lock's new sentences say it seals, and that with the lock on a notification says only that something arrived. Sealing has run against a stand-in Secure Enclave on a simulator and never on a phone (`docs/open-questions.md:167-173`). The notification sentence is from reading the extension's code; no banner was watched arriving with the lock on. CLAUDE.md asks for a callout, not a sentence, for something built and unproven. Do K313, K361 and K486 go in before the iPhone walk (plan step 4) or after it? | After. Step 4 comes before step 12 in the plan, and the walk should include one banner with the lock on. | Hold K313, K361, K486 and L17c until step 4 is written up as done. K159, K227, K402 and K672 do not wait: K402 replaces a sentence that the same code makes false. |
| G8 | He chose two factors on 2026-11-10: the code's key asks for Face ID or the phone's passcode first. It is not built (`CarpenterKeychain/SecureEnclaveKeys.swift:20` still asks for nothing but `.privateKeyUsage` on the code's key). When it is, K313 and the Face ID prompt text need the variants in section 6. | Apply the variants in the same change that builds it. | Do not apply the variants. |
| G9 | Measurement, not wording. A code carries a link to a space in the member's iCloud and the account's record name. Apple's page for `CKUserIdentity` says "A user identity provides identifiable data about an iCloud user, including their name" and "A share's owner has a user identity, as does each of its participants" (https://developer.apple.com/documentation/cloudkit/ckuseridentity, read as its `.json`). Whether a peer's phone can read the Apple Account's name that way was not verified, and this app never reads it (no use of `nameComponents` or `lookupInfo` in `CarpenterCloudKit`). If it can, "You are a short code to everyone", "no one can look you up" and "Nothing in it says who you are" are false against a modified app. It needs two accounts on the rig. | Run it before the tester build. L41 is worded to be true either way. | Apply L41. |
| G10 | The recovery key file's text (`RecoveryKey.swift:58-73`) was left alone. Does he want "It was shown once, when you set up" changed? | Leave it. | Leave it. |

## 5. Table A: the strings over 200 characters

62 strings. 50 are here; the 12 on How this works are in section 7 and are counted there. Each
heading reads: row id, file and line, chunk and its status today, length now → length proposed,
class. Class S is shorter with the same facts. Class F corrects a fact. Class G waits for Griff.

For every row: replace the whole string literal, leave everything around it, and keep
`bundle: .module`. The text in the box is what goes between the quotes. Where it shows `\n\n`, a
one-line literal keeps `\n\n` and a `"""` block takes a real blank line.
In "Now opens", `%@` stands for an interpolation in the source (`\(Branding.displayName)` and the
like). The full current text of every row is in `step-copy-current.json`.

#### L01 · `CarpenterUI/Components/Membership/JoinCheckCard.swift:46` · chunk `ec2f3dc1` [NEEDS HUMAN REVIEW] · 451 → 187 · class S

- Shown: A room, the card for somebody you invited who is already in (the room admits on an invitation), under the characters.
- Now opens: "You invited them, and this room lets anybody in …"
- Replace the whole literal with:

  ```
  This room admits anybody with an invitation, so they're already in. If their characters differ from these, say so: you stop sending them the room's key, but they stay. Only you are asked.
  ```
- Notes: Kept: they are in without approval; a mismatch stops you sending them the room's key; they are not removed; only you are asked. Dropped: why matching characters prove the person. The key claim was carried over, not re-checked against the session code.

#### L02 · `CarpenterUI/Components/Messaging/NotGoneExplanation.swift:39` · chunk `cf606016` [NEEDS HUMAN REVIEW] · 235 → 199 · class S

- Shown: A message marked Not received, its explanation.
- Now opens: "Somebody in this room didn't receive it within ^[%@ …"
- Replace the whole literal with:

  ```
  Somebody here didn't receive it within ^[\(Self.takenBackAfterDays) day](inflect: true), so the copy waiting in your iCloud was removed. Their phone requests it again once a newer message from you shows this one is missing.
  ```
- Notes: Checked: the wait is nine days (CarpenterKit/Model/NotGone.swift:9, CarpenterKit/Sync/SyncSession.swift:197-205). Keep the `^[\(Self.takenBackAfterDays) day](inflect: true)` part exactly.

#### L03 · `CarpenterUI/Components/Messaging/NotGoneExplanation.swift:231` · chunk `2cdcc54e` [NEEDS HUMAN REVIEW] · 330 → 197 · class S

- Shown: A room's Not sent yet page, footer under the choices.
- Now opens: "A message often waits until somebody opens the app, …"
- Replace the whole literal with:

  ```
  An orange circle marks a message when more than one newer message you sent here has been received and it hasn't, or when it has waited this long. The first option uses only the newer-message check.
  ```
- Notes: Dropped: 'nothing is marked at first' and 'nobody is singled out'. Not re-checked against code.

#### L04 · `CarpenterUI/Screens/Identity/DeviceListView.swift:75` · chunk `0bce4c15` [NEEDS HUMAN REVIEW] · 228 → 193 · class S

- Shown: You > Devices, footer under the list.
- Now opens: "Every device on this list can send messages as …"
- Replace the whole literal with:

  ```
  Every device here can send messages as you. Removing one stops it reading anything said afterwards. What it already sent stays. Other people's devices stop accepting it the next time they sync.
  ```
- Notes: Dropped: 'because it really was you'.

#### L05 · `CarpenterUI/Screens/Identity/RemovedDeviceView.swift:23` · chunk `ca91d2d2` [NEEDS HUMAN REVIEW] · 242 → 197 · class S

- Shown: The screen a removed device shows, under the title This device was removed.
- Now opens: "This device was removed, by another of your devices …"
- Replace the whole literal with:

  ```
  Another of your devices, or your recovery key, removed it. What it held is erased, and it receives nothing new. To use it again, restore it with your recovery key, which removes your other devices.
  ```
- Notes: The title already says it was removed, so the sentence no longer repeats it.

#### L06 · `CarpenterUI/Screens/Identity/WelcomeTourView.swift:33` · chunk `92143e53` [NEEDS HUMAN REVIEW] · 274 → 196 · class F

- Shown: Welcome tour, panel 2 (Message Delivery).
- Now opens: "Messages are delivered straight to their recipients. Your iCloud …"
- Replace the whole literal with:

  ```
  Your iCloud works as a mailbox. A message waits there sealed, under an address that changes daily, until its recipients receive it or nine days pass. Then it lives only on your devices and theirs.
  ```
- Notes: Was: 'delivered straight to their recipients' and removed once all have received it. A message waits in iCloud, and is also removed after nine days (SyncSession.swift:197-205). The address changes daily (tagWindow, SyncSession.swift:197).

#### L07 · `CarpenterUI/Screens/Identity/WelcomeTourView.swift:45` · chunk `92143e53` [NEEDS HUMAN REVIEW] · 225 → 190 · class G

- Shown: Welcome tour, panel 4 (Compared to Other Apps).
- Now opens: "At best, even security focused apps who can't read …"
- Replace the whole literal with:

  ```
  Most messaging apps run their own servers. \(Branding.displayName) has none, so its Dev holds nothing of yours. Apple holds your sealed messages and can see which Apple Accounts exchange them, not what they say.
  ```
- Notes: Was: 'even security focused apps ... still know who you talk to and how often'. Signal publishes that it can produce only a registration time and a last connection date (https://signal.org/bigbrother/). And this build tells Apple which accounts exchange messages: each space is shared with the reader's account and 'Apple holds every share list' (docs/crypto-brief.md:828-829; CarpenterCloudKit/CloudKitMailbox+Pairs.swift:16-23). Decision G1.

#### L08 · `CarpenterUI/Screens/Identity/WelcomeTourView.swift:51` · chunk `92143e53` [NEEDS HUMAN REVIEW] · 367 → 197 · class S

- Shown: Welcome tour, panel 5 (Drawbacks).
- Now opens: "A private and secure architecture does have cons. Your …"
- Replace the whole literal with:

  ```
  Your key lives only on your devices. A new device gets it when one of yours approves. Lose them all and only your recovery key brings you back; conversations are then requested from people in them.
  ```
- Notes: Dropped: 'A private and secure architecture does have cons' and 'the Dev has no way to help' (the sentence 'only your recovery key brings you back' carries it).

#### L09 · `CarpenterUI/Screens/Identity/WelcomeTourView.swift:57` · chunk `92143e53` [NEEDS HUMAN REVIEW] · 269 → 199 · class F

- Shown: Welcome tour, panel 6 (App Permissions).
- Now opens: "%@ requests permissions, all of which are optional, and …"
- Replace the whole literal with:

  ```
  All optional: notifications announce messages, Focus shares when you've silenced them, the camera scans an invite, Face ID opens the app lock. The system photo picker hands over only what you choose.
  ```
- Notes: Was missing two things the build asks for: the camera (App/Carpenter/Info.plist:25-26, InviteScanning.swift:213) and Face ID (Info.plist:33-34). Focus is Info.plist:29-30.

#### L10 · `CarpenterUI/Screens/Membership/CompareCodesView.swift:120` · chunk `ecdfae7b` [NEEDS HUMAN REVIEW] · 240 → 197 · class S

- Shown: Comparing characters, the note after They don't match.
- Now opens: "Check that you are both looking at each other, …"
- Replace the whole literal with:

  ```
  Check you're comparing with each other, not somebody else. If you are, somebody may be in the middle: say nothing here you wouldn't say to a stranger, and compare again in person. Nothing was sent.
  ```

#### L11 · `CarpenterUI/Screens/Membership/InviteScanning.swift:213` · chunk `8cc71634` [NEEDS HUMAN REVIEW] · 252 → 200 · class S

- Shown: Joining a room, the card Scan invites with the camera?.
- Now opens: "A Scan button would sit beside Paste and read …"
- Replace the whole literal with:

  ```
  Adds a Scan button beside Paste to read the QR code on somebody's screen. The camera looks only for an invite and keeps nothing. iOS asks for camera access the first time. Change it later in Behavior.
  ```
- Notes: Checked: the switch is on the Behavior page (You/Settings/BehaviourSettingsView.swift:17, 36).

#### L12 · `CarpenterUI/Screens/Membership/InviteScanning.swift:257` · chunk `7b2baf9b` [NEEDS HUMAN REVIEW] · 246 → 176 · class S

- Shown: You > Behavior > Scan invites with the camera, footer.
- Now opens: "Puts a Scan button beside Paste when you join …"
- Replace the whole literal with:

  ```
  Puts a Scan button beside Paste when you join a room. The camera looks only for an invite and keeps nothing it sees. If you refused camera access, allow it in the Settings app.
  ```

#### L13 · `CarpenterUI/Screens/Membership/WaitingOnView.swift:37` · chunk `0bcd12f2` [NEEDS HUMAN REVIEW] · 227 → 169 · class S

- Shown: A message's Waiting on list, footer.
- Now opens: "Nothing here is a fault. A message reaches somebody …"
- Replace the whole literal with:

  ```
  A message reaches somebody when they next open the app, so waiting is normal. Last heard is the newest thing of theirs on this phone, with the time their device gave it.
  ```
- Notes: Dropped: 'Nothing here is a fault.'

#### L14 · `CarpenterUI/Screens/Messaging/MessageDetailView.swift:181` · chunk `9de72c36` [NEEDS HUMAN REVIEW] · 400 → 197 · class S

- Shown: Message details > What hiding actually does.
- Now opens: "Hiding affects only you. The message stops appearing on …"
- Replace the whole literal with:

  ```
  Hiding affects only you. The message leaves your screens, stays saved, and can be shown again.\n\nOnly its writer can withdraw it, within two minutes. Everybody sees a placeholder; nothing is erased.
  ```
- Notes: Checked: two minutes (CarpenterKit/Log/Editing.swift:6). The literal is a `"""` block with `\` line continuations: replace the whole block, keep `"""`, and put a real blank line where the proposal shows `\n\n`.

#### L15 · `CarpenterUI/Screens/Messaging/SearchTabView.swift:221` · chunk `93a96e73` [NEEDS HUMAN REVIEW] · 213 → 193 · class S

- Shown: Search tab, empty state.
- Now opens: "Conversations by name, what was said, photos by their …"
- Replace the whole literal with:

  ```
  Find conversations by name, messages by what was said, photos by caption or sender, and Outpost posts. Hidden and withdrawn messages and blocked people never appear. Nothing leaves this device.
  ```

#### L16 · `CarpenterUI/Screens/Notifications/MessagingNotificationsView.swift:87` · chunk `5b69624a` [NEEDS HUMAN REVIEW] · 317 → 158 · class S

- Shown: You > Notifications > Messaging > Rooms, footer under Tell me about room changes.
- Now opens: "Somebody joining or leaving, somebody being removed, a room …"
- Replace the whole literal with:

  ```
  Somebody joining, leaving or being removed, a room being renamed, an invitation being answered, or a change to who may join. A solo has no changes like these.
  ```
- Notes: The literal holds `\n\n`; the proposal is one paragraph.

#### L17 · `CarpenterUI/Screens/Notifications/NotificationLevelView.swift:174` · chunk `93d56db0` [NEEDS HUMAN REVIEW] · 440 → 183 + 112 + 80 · class F

- Shown: Notification level page, the caveat under the banner preview.
- Now opens: "The banner is put together on this device after …"
- L17a:

  ```
  A banner is made on this device after the message is decrypted, so nothing readable crosses the network. iOS keeps it where this app can't remove it, so choose less to keep words out.
  ```
- L17b:

  ```
  A photo or clip is announced by its caption, or as "📷 Photo" or "🎬 Video". The picture never goes into a banner.
  ```
- L17c:

  ```
  App Lock is on, so every banner on this iPhone says only that something arrived.
  ```
- Notes: One 440-character string becomes two (L17a, L17b), plus one new line shown only while App Lock is on (L17c). See the code note under the table. New fact: with App Lock on the notification extension never opens the vault, so every banner is the generic one (App/CarpenterNotificationService/NotificationService.swift:56-79); read from the code, not watched, so L17c waits with G7. 'this app cannot remove it' is carried over from the current string and was not re-checked.

#### L18 · `CarpenterUI/Screens/Notifications/NotificationsView.swift:55` · chunk `0728e4fa` [NEEDS HUMAN REVIEW] · 239 → 146 · class S

- Shown: You > Notifications, first footer.
- Now opens: "Alerts about your own settings — a check-up, your …"
- Replace the whole literal with:

  ```
  Alerts about your own settings, such as a check-up or your recovery key, appear only on the You tab. They never add to the number on the app icon.
  ```
- Notes: Dropped: 'because that number means somebody is trying to reach you'.

#### L19 · `CarpenterUI/Screens/Notifications/NotificationsView.swift:65` · chunk `dd400255` [NEEDS HUMAN REVIEW] · 233 → 163 · class S

- Shown: You > Notifications, second footer.
- Now opens: "A Focus silences these like anything else. If you …"
- Replace the whole literal with:

  ```
  A Focus silences these notifications. To let them through, allow this app in that Focus, in the Settings app under Focus. Nobody who writes to you can override it.
  ```

#### L20 · `CarpenterUI/Screens/Notifications/PermissionExplainerView.swift:125` · chunk `f5b81be8` [NEEDS HUMAN REVIEW] · 267 → 188 · class S

- Shown: The page before the system's notification prompt.
- Now opens: "This app asks to show a banner when somebody …"
- Replace the whole literal with:

  ```
  This app asks to show a banner when somebody writes to you, and to put a count on its icon. Banners come only from people you've let in. You choose what a banner shows under Notifications.
  ```
- Notes: Dropped: 'no news, and nothing sold to anybody' and 'on the next screen' (what the next screen is was not verified).

#### L21 · `CarpenterUI/Screens/Notifications/PermissionExplainerView.swift:129` · chunk `f5b81be8` [NEEDS HUMAN REVIEW] · 241 → 176 · class S

- Shown: The page before the system's photo picker.
- Now opens: "This app never asks for your photo library. The …"
- Replace the whole literal with:

  ```
  This app never asks for your photo library. The picker you're about to see belongs to iOS: it shows your library to you and hands this app only the photos and clips you choose.
  ```
- Notes: Dropped: 'Nothing else is read, and there is no setting to grant.'

#### L22 · `CarpenterUI/Screens/Outpost/HiddenCommentsSheet.swift:61` · chunk `198639c1` [NEEDS HUMAN REVIEW] · 282 → 196 · class S

- Shown: Outpost > hidden comments sheet, This number is the one thing here you cannot check.
- Now opens: "Everything else in Outpost is proof of itself: you …"
- Replace the whole literal with:

  ```
  Everything else here can be checked: you hold the message and its signature. This count can't be, because it describes comments you hold no key for. It is a claim by the person whose post this is.
  ```
- Notes: Also removes the product name written inside a literal ('Everything else in Outpost').

#### L23 · `CarpenterUI/Screens/Outpost/HiddenCommentsSheet.swift:67` · chunk `198639c1` [NEEDS HUMAN REVIEW] · 324 → 189 · class S

- Shown: Outpost > hidden comments sheet, And why that does not much matter.
- Now opens: "Only the person whose post it is could put …"
- Replace the whole literal with:

  ```
  Only the post's owner could put a wrong number here, and only with a modified app. The count carries no key, no words and no names, so a wrong one changes only what you're told about a gap.
  ```
- Notes: Dropped: 'a misleading footnote shown to somebody who already knows somebody they know'.

#### L24 · `CarpenterUI/Screens/Outpost/OutpostConsentSheet.swift:40` · chunk `aa3c687e` [NEEDS HUMAN REVIEW] · 206 → 184 · class S

- Shown: How comments travel sheet, They see one anonymous person.
- Now opens: "Your name, photo and everything else about you stay …"
- Replace the whole literal with:

  ```
  Your name and photo stay off a comment read by anybody you haven't met. To them you look like every other person they haven't met, so nobody can follow you from one thread to the next.
  ```

#### L25 · `CarpenterUI/Screens/Outpost/OutpostConsentSheet.swift:89` · chunk `39f201a2` [NEEDS HUMAN REVIEW] · 201 → 175 · class S

- Shown: How comments travel > What would you rather do? (dialog message).
- Now opens: "Read only keeps the tab and takes away commenting …"
- Replace the whole literal with:

  ```
  Read only keeps the tab but stops you commenting or reacting on other people's posts. Turning Outposts off removes the tab too. You can change either later under Your Outpost.
  ```
- Notes: Checked: the row is Your Outpost (You/YouView+Settings.swift:126).

#### L26 · `CarpenterUI/Screens/Outpost/OutpostSettingsView.swift:124` · chunk `3f9ba109` [NEEDS HUMAN REVIEW] · 238 → 192 · class S

- Shown: You > Your Outpost > Your picture, footer.
- Now opens: "Shows the photo from your You page at the …"
- Replace the whole literal with:

  ```
  Shows your You photo at the top of your Outpost, unless you choose a different one here. When this is off, your Outpost shows your initials. Readers get a picture only if Share my photo is on.
  ```
- Notes: Dropped: 'and rooms aren't affected'.

#### L27 · `CarpenterUI/Screens/Outpost/OutpostSettingsView.swift:156` · chunk `b58d985d` [NEEDS HUMAN REVIEW] · 258 → 198 · class S

- Shown: You > Your Outpost > People you have not met, footer.
- Now opens: "Anybody who comments on an Outpost you both read, …"
- Replace the whole literal with:

  ```
  A commenter on an Outpost you both read who has never shared a room or an Outpost with you appears like this. They all look like one person. Only your devices show them this way, and nobody is told.
  ```
- Notes: Dropped: 'so nobody can be followed from thread to thread'.

#### K159 · `CarpenterUI/Screens/Safety/AppLockViews.swift:159` · chunk `7e88ab4a` [NEEDS HUMAN REVIEW] · 240 → 184 · class S

- Shown: Lock screen > Forgot the code? > alert message.
- Now opens: "If you have your recovery key, use the key …"
- Replace the whole literal with:

  ```
  Your recovery key opens the app and erases nothing; use the key button instead. Erasing removes everything this iPhone keeps, and you then set it up again from another of your devices.
  ```
- Notes: See the lock table (section 6).

#### L29 · `CarpenterUI/Screens/Safety/PrivacyCheckupPages.swift:26` · chunk `827c7293` [NEEDS HUMAN REVIEW] · 254 → 154 · class F

- Shown: Privacy check-up, the Familiar and open page.
- Now opens: "The way Messages works. People in your rooms see …"
- Replace the whole literal with:

  ```
  People in your rooms see your name and photo, and you see theirs. The people you write to know when you've silenced notifications. Read receipts stay off.
  ```
- Notes: Checked against PrivacyChoices.familiar (Safety/PrivacyChoices.swift:34-40). Dropped two claims about Apple's Messages that were not verified: 'The way Messages works' and 'Messages does not show them until you ask'.

#### L30 · `CarpenterUI/Screens/Safety/PrivacyCheckupPages.swift:33` · chunk `827c7293` [NEEDS HUMAN REVIEW] · 335 → 191 · class S

- Shown: Privacy check-up, the Locked down page.
- Now opens: "As little as possible. You are a short code …"
- Replace the whole literal with:

  ```
  You're a short code with no photo to everyone, and they are to you. Nobody learns when a Focus is on. Every solo, old or new, stays closed until you've read the same characters to each other.
  ```
- Notes: Checked against PrivacyChoices.lockedDown (PrivacyChoices.swift:42-47). Dropped: 'senders are told you do not report' (read receipts are off in both presets).

#### L31 · `CarpenterUI/Screens/Safety/PrivacyCheckupPages.swift:229` · chunk `f7d33891` [NEEDS HUMAN REVIEW] · 255 → 179 · class S

- Shown: Privacy check-up > Share my name.
- Now opens: "Sends your name to the rooms you're in, as …"
- Replace the whole literal with:

  ```
  Sends your name to the rooms you're in. People can call you something else on their own phone. When this is off, they see a short code. A room that already has your name keeps it.
  ```

#### L32 · `CarpenterUI/Screens/Safety/PrivacyCheckupPages.swift:236` · chunk `f7d33891` [NEEDS HUMAN REVIEW] · 212 → 188 · class S

- Shown: Privacy check-up > Share my photo.
- Now opens: "Shares the photo you pick on You with the …"
- Replace the whole literal with:

  ```
  Shares the photo you pick on You with people in your rooms and readers of your Outpost. When you turn this off, the photo is taken down and their devices remove it the next time they sync.
  ```

#### L33 · `CarpenterUI/Screens/Safety/PrivacyCheckupPages.swift:243` · chunk `f7d33891` [NEEDS HUMAN REVIEW] · 222 → 164 · class S

- Shown: Privacy check-up > Share when I've silenced notifications.
- Now opens: "Tells the people you write to when you have …"
- Replace the whole literal with:

  ```
  Tells the people you write to when you have a Focus on, so they don't wait for a reply. iOS asks your permission first. You choose the words under Privacy & Safety.
  ```
- Notes: Dropped: 'the way Messages does'.

#### L34 · `CarpenterUI/Screens/Safety/PrivacyCheckupPages.swift:296` · chunk `d7103db6` [NEEDS HUMAN REVIEW] · 363 → 200 · class S

- Shown: Privacy check-up > One conversation, one person.
- Now opens: "You and anybody you talk to alone share a …"
- Replace the whole literal with:

  ```
  Keeps a solo closed until you two have read your shared characters to each other and said they matched. They're told you're waiting. When this is off, a solo opens when somebody with your code writes.
  ```
- Notes: Dropped: 'worked out from how you met' and 'either of you can ask again at any time'.

#### L35 · `CarpenterUI/Screens/Safety/PrivacyCheckupPages.swift:303` · chunk `d7103db6` [NEEDS HUMAN REVIEW] · 320 → 181 · class S

- Shown: Privacy check-up > When somebody comes back.
- Now opens: "Somebody who loses every device can come back with …"
- Replace the whole literal with:

  ```
  Tells you when somebody who lost every device has set up again with a recovery key and requested a conversation from you, and which one. It doesn't change whether your copy is sent.
  ```

#### L36 · `CarpenterUI/Screens/Safety/PrivacyCheckupPages.swift:312` · chunk `6badc6d4` [NEEDS HUMAN REVIEW] · 450 → 196 · class S

- Shown: Privacy check-up > Before your history goes back.
- Now opens: "When this is off, your copy of a conversation …"
- Replace the whole literal with:

  ```
  Holds your copy of a conversation until you and whoever requests it have read your shared characters to each other and you've said they matched. They wait till then. New messages still reach them.
  ```
- Notes: Says what the switch does when on; the off state follows from it. Dropped: 'on a line you trust'.

#### L37 · `CarpenterUI/Screens/Safety/PrivacyCheckupPages.swift:319` · chunk `6badc6d4` [NEEDS HUMAN REVIEW] · 203 → 184 · class S

- Shown: Privacy check-up > Outposts.
- Now opens: "An Outpost is a page of your own. You …"
- Replace the whole literal with:

  ```
  An Outpost is a page of your own. You choose who reads it, one person at a time; sharing a room lets nobody in. When this is off, the tab is hidden and nothing is posted or downloaded.
  ```

#### L38 · `CarpenterUI/Screens/Safety/PrivacyCheckupPages.swift:328` · chunk `1b74f802` [NEEDS HUMAN REVIEW] · 291 → 193 · class S

- Shown: Privacy check-up > What you write on other people's.
- Now opens: "Everybody who can read a post can read every …"
- Replace the whole literal with:

  ```
  Everybody who can read a post can read every comment under it, and some of them are people you've never met. This decides how far your own comments go. It doesn't change who reads your Outpost.
  ```

#### L39 · `CarpenterUI/Screens/Safety/PrivacyCheckupPages.swift:335` · chunk `1b74f802` [NEEDS HUMAN REVIEW] · 253 → 196 · class S

- Shown: Privacy check-up > Your picture on your Outpost.
- Now opens: "Shows the photo you pick on You at the …"
- Replace the whole literal with:

  ```
  Shows the photo you pick on You at the top of your Outpost; you can choose a different one there. When this is off, your Outpost shows initials. Readers get a picture only if Share my photo is on.
  ```

#### L40 · `CarpenterUI/Screens/You/Settings/DeviceSecuritySettingsView.swift:34` · chunk `9057a976` [NEEDS HUMAN REVIEW] · 228 → 194 · class S

- Shown: You > Advanced On Device Security, header.
- Now opens: "When it's on, the messages, photos, names and keys …"
- Replace the whole literal with:

  ```
  Seals the messages, photos, names and keys this iPhone keeps for the app whenever the iPhone is locked. A copy of its storage taken while it's locked can't be read without the iPhone's passcode.
  ```
- Notes: This is the phone's lock, not the app's own lock. Facts unchanged.

#### L41 · `CarpenterUI/Screens/You/Settings/IdentitySettingsView.swift:122` · chunk `b67a4def` [NEEDS HUMAN REVIEW] · 253 → 195 · class F

- Shown: You > your identity page > Send someone your code, footer.
- Now opens: "Somebody needs your code before they can add you …"
- Replace the whole literal with:

  ```
  Somebody needs your code to add you to a room. It holds your public key, how many characters you check, a one-time value for them, and a link to a space in your iCloud. It holds no name or photo.
  ```
- Notes: Was: 'Nothing in it says who you are.' The code also carries a link to a space in the member's iCloud and that iCloud account's record name (CarpenterApp/Session/AppSession+Membership.swift:151-161; CarpenterKit/Platform/Pairs.swift:11-13; CarpenterCloudKit/CloudKitMailbox+Pairs.swift:9-13). It carries no name or photo. See G9.

#### L42 · `CarpenterUI/Screens/You/Settings/IdentitySettingsView.swift:153` · chunk `a018d8bc` [NEEDS HUMAN REVIEW] · 277 → 200 · class S

- Shown: You > your identity page > Where your keys are, footer.
- Now opens: "Your keys are kept on this device only. A …"
- Replace the whole literal with:

  ```
  Your keys are kept only on your devices. A new device gets them when one of yours approves it. Lose them all and your recovery key restores you and requests your conversations from the people in them.
  ```
- Notes: Was 'kept on this device only', next to 'a new device gets them'. Checked: every keychain write uses the device scope (13 uses of `scope: .device`, none synchronized). Dropped: 'removes every other device' (it is on the recovery key page).

#### L43 · `CarpenterUI/Screens/You/Settings/IntegrityView.swift:221` · chunk `9092655d` [NEEDS HUMAN REVIEW] · 242 → 160 · class S

- Shown: You > integrity report, the card about messages held for other people.
- Now opens: "^[%@ message](inflect: true) this device is passing along and …"
- Replace the whole literal with:

  ```
  ^[\(report.sealedForOthers) message](inflect: true) this device is passing along and cannot read, written by ^[\(report.unmetAuthorsHeld) person](inflect: true) you have not met. None of it is readable here.
  ```
- Notes: Keep both `^[...](inflect: true)` parts exactly.

#### L44 · `CarpenterUI/Screens/You/Settings/PrivacyAndSafetySettingsView.swift:43` · chunk `7f55c807` [NEEDS HUMAN REVIEW] · 230 → 189 · class S

- Shown: You > Privacy & Safety, header.
- Now opens: "What this device tells other people, and what it …"
- Replace the whole literal with:

  ```
  What this device tells other people, and what it does with what arrives. Every judgment is made on this device. Change any of it later; what was already sent stays with whoever received it.
  ```

#### L45 · `CarpenterUI/Screens/You/Settings/PrivacyAndSafetySettingsView.swift:75` · chunk `80171c59` [NEEDS HUMAN REVIEW] · 479 → 197 · class S

- Shown: You > Privacy & Safety > Send, footer under four switches.
- Now opens: "Share my name sends your name to the rooms …"
- Replace the whole literal with:

  ```
  Name and photo go to your rooms, and the photo to your Outpost's readers. Read receipts tell a sender when their message was shown to you. The Focus switch tells people you write to when one is on.
  ```
- Notes: One footer for four switches. What turning each off does is on the check-up pages (L31, L32). If Griff would rather have one short footer per switch, that is four sections and a layout change.

#### L46 · `CarpenterUI/Screens/You/Settings/PrivacyAndSafetySettingsView.swift:96` · chunk `2dc93f05` [NEEDS HUMAN REVIEW] · 315 → 199 · class S

- Shown: You > Privacy & Safety > Receive, footer under three switches.
- Now opens: "When names are off, everyone appears as a short …"
- Replace the whole literal with:

  ```
  Shows the names and photos people share, and a line in a solo while the other person has a Focus on. When names are off, everyone appears as a short code. A photo you chose for somebody always shows.
  ```

#### L47 · `CarpenterUI/Screens/You/Settings/PrivacyAndSafetySettingsView.swift:146` · chunk `8473ea72` [NEEDS HUMAN REVIEW] · 279 → 190 · class S

- Shown: You > Privacy & Safety > Check who I am talking to first, footer.
- Now opens: "You and anybody you talk to alone share a …"
- Replace the whole literal with:

  ```
  Keeps a solo closed until you two have read your shared characters to each other. The other person is told you're waiting. When this is off, a solo opens when somebody with your code writes.
  ```

#### L48 · `CarpenterUI/Screens/You/Settings/PrivacyAndSafetySettingsView.swift:162` · chunk `8edfd454` [NEEDS HUMAN REVIEW] · 336 → 169 · class S

- Shown: You > Privacy & Safety > Use a twenty-character code, footer.
- Now opens: "Ten characters is already far more than anybody could …"
- Replace the whole literal with:

  ```
  You read twenty characters instead of ten with everyone you meet from now on. If either of you asks for twenty, you both read twenty, and the first ten are the same ten.
  ```
- Notes: Checked: ten and twenty (CarpenterKit/Crypto/ShortAuthenticationString.swift:5-6). Dropped the unchecked claim that ten is 'far more than anybody could work out'.

#### L49 · `CarpenterUI/Screens/You/Settings/PrivacyAndSafetySettingsView.swift:184` · chunk `d5427ed4` [NEEDS HUMAN REVIEW] · 485 → 200 · class S

- Shown: You > Privacy & Safety, footer under Tell me when somebody sets up again and Hold my history until I have checked.
- Now opens: "Somebody who loses every device comes back with a …"
- Replace the whole literal with:

  ```
  Somebody who sets up again with a recovery key requests their conversations from the people in them. The first tells you when you're asked; the second holds your copy until you've compared characters.
  ```
- Notes: Dropped: 'anything said from now on still reaches them' (it is on the check-up page, L36).

#### L50 · `CarpenterUI/Screens/You/Settings/PrivacyAndSafetySettingsView.swift:200` · chunk `cd652188` [NEEDS HUMAN REVIEW] · 251 → 189 · class S

- Shown: You > Privacy & Safety > Ask the people I talk to for what was said, footer.
- Now opens: "This is about your own history. If you come …"
- Replace the whole literal with:

  ```
  If you set up again with a recovery key, your conversations start empty and this requests copies from the people in them. When it's off, nobody is asked and nobody is told you set up again.
  ```
- Notes: Dropped: 'You can change this only here.'

**Code note for L17** (`CarpenterUI/Screens/Notifications/NotificationLevelView.swift:171-185`). `caveat` is
one `Text` holding a `"""` block. Make it a `VStack(alignment: .leading, spacing: 8)` of two `Text`
values (L17a, L17b), each with `bundle: .module`, and move `.font(CarpenterFont.footnote)` and
`.fixedSize(horizontal: false, vertical: true)` onto the stack. L17b contains straight double quotes:
keep it a `"""` block, or escape them. For L17c add `@Environment(\.appLock) private var appLock`
to the view (the same line as `CarpenterUI/Screens/You/YouView.swift:7`) and show L17c first in the
stack when `appLock?.lock != nil`. All three stay inside chunk `93d56db0`, so no new marker. Two
`Text` values is the smallest change that gets under 200. If the layout must not change at all,
one `Text` holding L17a and L17b as two paragraphs is 297 characters: apply it, and leave the row
open in the write-up. L17c waits for G7 either way.
The same missing sentence applies to the footer at
`CarpenterUI/Screens/Notifications/MessagingNotificationsView.swift:68` ("This is what somebody
reading over your shoulder can see on a locked screen."), which is not over 200 and was left.


## 6. Table B: the lock's screens

What the lock does in this build, from the code and from `docs/open-questions.md:153-217`:

- With the lock on, the state file and every device-only key are sealed under a key that opens with
  the code, Face ID if chosen, or the recovery key (`CarpenterUI/Screens/Safety/AppLockController.swift:154-201, 307-322, 332-354`).
  Messages and photos are sealed under room keys, which are among those keys.
- Left in the clear: the lock's own record, and the outside of each item in the history file (which
  device wrote it, when, and in which room by number) (`docs/open-questions.md:206-208`). So the new
  words name what is sealed and do not say "everything".
- The app passes the vault to the lock (`App/Carpenter/AppRootView.swift:36`), and both places that
  turn the lock on pass the code (`App/Carpenter/AppRootView+Lock.swift:125`,
  `CarpenterUI/Screens/Safety/AppLockViews.swift:563`), so a lock that is on always has a vault.
- The notification extension shuts the vault and never opens it, so with the lock on every banner is
  the generic one (`App/CarpenterNotificationService/NotificationService.swift:56-79`).
- Face ID's key needs the enrolled set unchanged and has no passcode fallback
  (`CarpenterKeychain/SecureEnclaveKeys.swift:20`, `AppLockController.swift:33-38`). The code's key
  asks for nothing more than an unlocked phone.
- Five free tries, then waits of 1, 5 and 15 minutes and longer
  (`CarpenterKit/Crypto/AppLock.swift:149-156`).
- *Forgot the code?* erases this phone only (`AppRootView+Lock.swift:111-116`). The recovery key opens
  the vault and turns the lock off (`AppLockController.swift:332-354`).
- Sealing has not run on a phone (G7).

All in `Packages/Carpenter/Sources/CarpenterUI/Screens/Safety/AppLockViews.swift` unless a file is
named. Every chunk here is at `NEEDS HUMAN REVIEW`, so no marker line changes.

| Line | Chunk | Now | Still true? | Change |
|---|---|---|---|---|
| 38 | `5be5d303` | "%@ is locked" | Yes | none |
| 56, 58 | `5be5d303` | "Passphrase", "Code" | Yes | none |
| 75, 85 | `5be5d303` | "Unlock", "Use %@" | Yes | none |
| 118 | `5be5d303` | "%@ changed on this phone, so enter your code." | Yes (`SecureEnclaveKeys.swift:20`, `AppLockController.swift:100-103`) | none |
| 136 | `69fb0425` | "Use your recovery key" (the key button's label for VoiceOver) | Yes | none |
| 147, 150, 154, 156 | `7e88ab4a` | "Forgot the code?", "Erase this phone's copy?", "Erase", "Cancel" | Yes | none |
| 159 | `7e88ab4a` | "If you have your recovery key, use the key button instead: … then approve this phone from another of your devices." (240) | Yes, and too long for an alert | **K159** |
| 180, 182 | `c45e581f` | "That's not it. %@ more tries before a wait.", "Too many tries. Try again at %@." | Yes (`AppLock.swift:149-156`) | none |
| 184, 186 | `c45e581f` | "The lock couldn't be saved. Try again.", "Enter your current code first." | Yes | none |
| 189, 190, 192 | `c45e581f` | "… One more wrong code erases everything.", "… %@ more wrong codes erase everything.", "Erasing everything…" | Partly: see 672. Left as they are, because the row they answer to is titled *Erase everything*; they change with G6 if he wants. | none |
| 194 | `c45e581f` | "That isn't the recovery key for this identity." | Yes | none |
| 213 | `bfd439df` | "Paste your recovery key" | Yes | none |
| 227 | `bfd439df` | "Your recovery key opens the app and turns the lock off, so you can set a new code in Settings." | Yes, but "Settings" reads as the Settings app; the lock is under You, in the row *App lock* (`CarpenterUI/Screens/You/YouView+Settings.swift:175`) | **K227** |
| 243, 254, 258 | `bfd439df` | "Unlock", "Recovery Key", "Cancel" | Yes | none |
| 311 | `66758400` | "Lock the app" | Yes | none |
| 313 | `66758400` | "Ask for a code of its own whenever the app opens. Your phone's passcode never opens it." | True, and leaves out that it seals | **K313** (after G7) |
| 320, 321, 323, 330, 337, 345 | `66758400` | "A 4 to 6 digit code", "A passphrase", "Use", "Code", "Passphrase", "Again", "Also unlock with %@" | Yes | none |
| 353, 357, 358 | `66758400` | "The two don't match.", "Use 4 to 6 digits.", "Use at least 8 characters." | Yes (lengths not re-checked in `AppLock.isAcceptable`) | none |
| 361 | `66758400` | "The lock guards the app's screens. If you forget the code, your recovery key opens the app from the lock screen." | No: it seals what the phone keeps, and it changes notifications and collecting | **K361** (after G7) |
| 377, 384 | `672323bd`, `61f4704a` | "Done", "App Lock" | Yes | none |
| 390 | `095e4033` | "Make notifications private too?" | The question still does something, on the member's other devices | **K390t**, or removed (G5) |
| 397, 399 | `095e4033` | "Make them private", "Keep them as they are" | Yes | none (`App/CarpenterUITests/RigChecks.swift:209` taps "Make them private") |
| 402 | `095e4033` | "The lock covers the app, not your notifications. As they arrive, anyone holding your phone can read the names, rooms and words they show. Private notifications say only that something arrived." | No: with the lock on, this phone's banners already say only that something arrived | **K402**, or removed (G5) |
| 419, 425 | `82c694ab` | "Lock the app", "Not now" | Yes | none |
| 484 | `77e5e417` | "App lock" | Yes | none |
| 486 | `77e5e417` | "When it's on, the app asks for its own code, or Face ID, when it opens, and covers itself in the app switcher." | True, and leaves out that it seals and what happens to notifications | **K486** (after G7) |
| 503-508 | `77e5e417` | "Right away", "After 1 minute", "After 5 minutes", "After 15 minutes", "Lock" | Yes (`AppLockController.swift:118-136`) | none |
| 521, 525, 530, 535 | `77e5e417` | "Unlock with %@", "Change code", "Turn off the lock", "Turn on the lock" | Yes | none |
| 556 | `a60a94cd` | "App Lock" | Yes | none |
| 572, 576, 591, 593, 595 | `5e791962` | "Enter your current code", "Code", "Continue", "Cancel", "The lock only changes for somebody who knows it." | Yes | none |
| 600, 607, 610, 613 | `3fe7fb47` | "Turn it on without your recovery key?", "Turn it on", "Cancel", "If it erases everything, nothing brings your identity back, and the people you talk to would have to start again with a new you." | Yes in the ordinary case. When the other devices are not told (see 672) they still hold the identity. Left; it changes with G6. | none |
| 663-668 | `320ac2d4` | "Off", "After 1 wrong code", "After 5 wrong codes", "After 10 wrong codes", "Erase everything" | Yes | none |
| 672 | `320ac2d4` | "Every wrong code counts, wherever the app asks for it. When the count is reached, everything you keep is erased, on every device and in iCloud. Only your recovery key brings your identity back." | No. Started behind the lock, the app has no identity in memory, so it leaves no notice for the other devices (`App/Carpenter/AppRootView+Device.swift:150-153`), and if iCloud cannot be reached then, nothing is queued to finish later (`AppRootView+Device.swift:180-187`, `AppSession+Deathmark.swift:22-25`). That the notice is left when the app had been opened first is inferred. | **K672** |
| `AppLockController.swift:206` | `d35bb503` | "Unlock the app" (the Face ID prompt's reason) | Yes | none |
| `You/YouView+Settings.swift:175-176` | — | "App lock", "Off", "On" | Yes | none |
| `App/Carpenter/Info.plist:34` | `b6501cb1` | "Face ID opens the app when you have locked it, instead of typing your code." | Yes today | G8 variant when two factors are built |

**K159** · `AppLockViews.swift:159` · chunk `7e88ab4a` · 184 characters

```
Your recovery key opens the app and erases nothing; use the key button instead. Erasing removes everything this iPhone keeps, and you then set it up again from another of your devices.
```

Kept: the key opens the app and erases nothing; erasing is this phone only; the way back is another of the member's devices. The key button is always there when the lock is shut (`AppLockViews.swift:128`, `App/Carpenter/AppRootView+Lock.swift:70-74`).

**K227** · `AppLockViews.swift:227` · chunk `bfd439df` · 94 characters

```
Your recovery key opens the app and turns the lock off. Set a new code under You, in App lock.
```

**K313** · `AppLockViews.swift:313` · chunk `66758400` · 158 characters

```
Seals your messages, photos, names and keys on this iPhone under a code of its own, and asks for it when the app opens. Your iPhone's passcode never opens it.
```

Names what is sealed instead of "everything", because the outside of each history item is not sealed.

**K361** · `AppLockViews.swift:361` · chunk `66758400` · 182 characters

```
With the lock on, notifications say only that something arrived, and new messages wait until you unlock. If you forget the code, your recovery key opens the app from the lock screen.
```

"new messages wait until you unlock" is what the build does (`docs/open-questions.md:181-183`); Griff has not yet accepted that cost.

**K390t** · `AppLockViews.swift:390` · chunk `095e4033` · 38 characters

```
Make notifications private everywhere?
```

The alert's title. Only if G5 is answered "reword", or by default.

**K402** · `AppLockViews.swift:402` · chunk `095e4033` · 185 characters

```
On this iPhone, notifications now say only that something arrived. Your other devices still show the names, rooms and words you chose. Making them private does the same on every device.
```

True because the notification level is a preference the member's devices share (`CarpenterKit/Sync/SiblingFeed.swift:40`, `CarpenterKit/Sync/MemberPreferences.swift:116, 521`; `CarpenterApp/Session/AppSession+Notifications.swift:106-112`). The alert is shown only when notifications are allowed and some level shows more than arrival (`AppRootView+Lock.swift:81-83`).

**K486** · `AppLockViews.swift:486` · chunk `77e5e417` · 199 characters

```
Seals your messages, photos, names and keys on this iPhone until you enter the app's code or use Face ID. The app covers itself in the app switcher, and notifications say only that something arrived.
```

"Face ID" is written out here as it is today, on a phone with Touch ID too. `controller.biometricName` is to hand if that should follow the phone; not changed in this order.

**K672** · `AppLockViews.swift:672` · chunk `320ac2d4` · 196 characters

```
Every wrong code counts. At the count, this iPhone is erased, and iCloud too if it can be reached. Your other devices may not be told, and keep what they have. Only your recovery key restores you.
```

Says what the build does today (G6).

**If G5 is answered "remove"** (a code change, its own commit, built and tested):

- `AppLockViews.swift`: delete chunk `095e4033` with both marker lines (389-405), the state
  `askingAboutNotifications` (282), the `revealsNotifications` and `onMakeNotificationsPrivate`
  properties and init parameters (270, 272, 287-296), and in `save()` replace lines 449-453 with
  `finish()`. Delete the two arguments at 562 and 564.
- `AppLockController.swift`: delete `notificationPrivacy` (55) and `struct NotificationPrivacy`
  (377-385).
- `App/Carpenter/AppRootView+Lock.swift`: delete lines 81-83, 122 and 127.
- `CarpenterApp/Session/AppSession+Notifications.swift`: `notificationsRevealMore` (96) and
  `makeNotificationsPrivate()` (106) then have no caller in the app (`grep` found none on
  2026-11-10). Griff's rule is no app code that only tests call, so they go, with
  `Packages/Carpenter/Tests/CarpenterKitTests/PrivateNotificationsTests.swift`.
- `App/CarpenterUITests/RigChecks.swift:209` waits for "Make them private": delete that step.
- Then K361 already tells the member what happens to notifications on this phone.

**G8 variants, only when the two-factor wrapping is in the build.** Check first:
`grep -n "privateKeyUsage" Packages/Carpenter/Sources/CarpenterKeychain/SecureEnclaveKeys.swift`. If
line 20 still reads `requiringBiometrics ? [.privateKeyUsage, .biometryCurrentSet] : [.privateKeyUsage]`,
it is not built and these are not applied.

```
K313 (two factors): Seals your messages, photos, names and keys on this iPhone under a code of its own. iOS checks Face ID or your iPhone's passcode before the app asks for it, and neither opens the app alone.
Info.plist:34 (two factors): Face ID is checked before the app asks for its code, and opens the app by itself if you turned that on.
```

They are 189 and 103 characters. The `Info.plist` chunk is `b6501cb1`: set it to
`NEEDS HUMAN REVIEW` if its words change.

## 7. Table C: the page that names other messaging apps

The page is `Packages/Carpenter/Sources/CarpenterUI/Screens/Identity/HowItWorksView.swift`, opened
from the welcome tour and from You. Every string on it, top to bottom. HRU means
`HUMAN REVIEWED, UNVERIFIED`, NHR means `NEEDS HUMAN REVIEW`.

What was read on 2026-11-10 about the other apps:

- Signal: "you will still need a phone number to sign up for Signal"
  (https://signal.org/blog/phone-number-privacy-usernames/). The only data it says it can produce is
  when an account registered and when it last connected, and it says it has no access to messages,
  contacts or groups (https://signal.org/bigbrother/). It rents servers from "Amazon AWS, Google
  Compute Engine, Microsoft Azure" (https://signal.org/blog/signal-is-expensive/).
- iMessage: "Messages in iCloud is end-to-end encrypted when iCloud Backup is disabled." With backup
  on, "your backup includes a copy of the Messages in iCloud encryption key". With Advanced Data
  Protection it "is always end-to-end encrypted". "Both Apple and third-party data centers may be
  used to store and process your data." (https://support.apple.com/en-us/102651)
- WhatsApp: personal messages are end-to-end encrypted with no setting to turn on, and "No one
  outside of the chat, not even WhatsApp, can read, listen to, or share them"
  (https://faq.whatsapp.com/820124435853543). Its policy says it collects "the time, frequency, and
  duration of your activities and interactions" and that it "receives information from, and shares
  information" with other Meta Companies (https://www.whatsapp.com/legal/privacy-policy).
- Messenger: Meta is "rolling out default end-to-end encryption for personal messages and calls on
  Messenger and Facebook", and "nobody, including Meta, can see what's sent or said, unless you
  choose to report a message to us"
  (https://about.fb.com/news/2023/12/default-end-to-end-encryption-on-messenger/).
- App Review: nothing read forbids naming another app in an app's own text. What was read: 2.3.1(a)
  on marketing "in a misleading way", 5.2.1 "Don't use protected third-party material such as
  trademarks … in your app without permission", 1.1.1 on "Defamatory … or mean-spirited content"
  (https://developer.apple.com/app-store/review/guidelines/; the last 14,000 characters of that page
  were not read). Whether a reviewer objects is not verified. A wrong statement about a named
  company is the risk, with or without a guideline.

What is wrong on the page today:

| Line | Says | Against |
|---|---|---|
| 23 | "Everything you write is stored only on the devices of the people you wrote it to, not in a server" | A sealed copy waits in the sender's iCloud until it is received or nine days pass (`CarpenterKit/Sync/SyncSession.swift:197-205`, `docs/crypto-brief.md:823-826`). |
| 34 | "the mailbox can see the compressed size; it can see nothing else" | Apple can also see when it was left, when it was collected, and which account it is shared with (`docs/crypto-brief.md:828-832`). |
| 43 | "there is no account and no personal information stored by anyone" | It needs an Apple Account, and Apple holds the list of which accounts each space is shared with. |
| 68 | "we solicit external security reviews"; "scanned and tested for vulnerabilities thoroughly before releases" | G3. |
| 86 | "Screening is on by default … media is blurred until you decide to look at it. Toggled under Safety." | Only what iOS judges sensitive is blurred, only with iOS's Sensitive Content Warning on, and the page is Privacy & Safety (`You/Settings/PrivacyAndSafetySettingsView.swift:121, 315, 319`). |
| 118 | "So does Signal, and so do WhatsApp and Meta, corporate interests with deals with Big Cloud and Big AI" | Signal: yes, by its own account. WhatsApp and Meta on other companies' clouds: no source read, not verified. "deals with … Big AI": not checkable. |
| 118 | "a debug build can keep its mailbox in a folder you host instead of iCloud" | True of a debug build only (`You/TestProfiles/TestProfilesView.swift:1`). A tester build is not one. |
| 128 | "your history lives on your friends' devices rather than being fetched from a service" | Signal does not say it serves history from a service either; the contrast was not found at the source. "has no number and no account": it has no account of its own and needs an Apple Account. |
| 132 | "unless you have Advanced Data Protection switched on, which limits some functionality, iCloud holds a key to your conversations" | Apple says this of iCloud Backup being on. "limits some functionality" was not checked. |
| 136 | "Encrypted in transit and at rest" | WhatsApp says end-to-end encrypted, which is more. Understating is the same defect. |
| 136 | "That pattern—the words are private, the social graph is not—is what the rotating addresses here are for." | In this build each space is shared with the reader's account by name and "Apple holds every share list" (`docs/crypto-brief.md:828-829`), so Apple can see who exchanges messages with whom. |
| 142 | "%@ has no identity to tie anything to" | It is tied to an Apple Account. |

Every string on the page:

| Line | Chunk | Now | Change |
|---|---|---|---|
| 20 | `7d330d05` HRU | "What is %@?" | none |
| 22 | `7d330d05` HRU | "%@ is a messaging app with Rooms, Solos (Direct messaging), and a shareable page—your Outpost—for posts, photos, and more." | none |
| 23 | `7d330d05` HRU | "%@ is a peer-to-peer messaging app. Everything you write is stored only on the devices …" (156) | **H23** (G2) |
| 30, 32 | `04884ac4` HRU | "Your own iCloud as a Mailbox"; "%@ uses your own iCloud as a mailbox, which passes messages to their recipients, sealed by encryption, and deletes them after receipt." | none |
| 33 | `04884ac4` HRU | "The %@ Dev has no server, and nothing to do with you after you download the app. …" (333) | **H33**, optional (G2) |
| 34 | `04884ac4` HRU | "Media is treated the same, as a sealed file. …" (206) | **H34** (G2) |
| 41 | `b561c670` NHR | "Account Free" | none |
| 43 | `b561c670` NHR | "%@ uses your Keychain as its identity: there is no account and no personal information stored by anyone." | **H43** |
| 44 | `b561c670` NHR | "Because your key, kept on your own devices, is your identity, there's no lookup. We do not integrate with Contacts." | none (true: nothing imports Contacts) |
| 48, 50 | `b561c670` NHR | "Invitations and Approvals"; "Invitations to Rooms or Solos are signed and expire, and must name the invitee specifically." | none (`CarpenterKit/Membership/MembershipAttestation.swift:10`) |
| 51 | `b561c670` NHR | "Rooms can be customized to different member approval settings, …" (261) | **H51** |
| 55, 57 | `b561c670` NHR | "Sync and Restore"; "Your identity reaches a new device only when …" (353) | **H57** |
| 66, 68 | `614f14c4` HRU | "Source & Review"; "%@ is open source, published under the Mozilla Public License 2.0. …" (295) | **H68** (G3) |
| 75, 77 | `1675ec4f` HRU | "Notifications"; "Notifications enable realtime banners, badges, and sounds …" (291) | **H77**, optional (G2) |
| 84, 86 | `85f818ac` HRU | "Media"; "Media is sent stripped of metadata, …" (219) | **H86** (G2) |
| 99, 102 | `79e25afb` HRU | "How this works", "Done" | none |
| 112 | `07207d26` NHR | "%@ vs. The Others" | none |
| 118 | `07207d26` NHR | "The %@ Dev Opinion is that all of these apps are impressive stacks, …" (474) | **H118** (G1) |
| 127, 128 | `43e010c0` NHR | "Signal"; "Signal's encryption set the standard …" (333) | **H128** (G1) |
| 131, 132 | `43e010c0` NHR | "iMessage"; "Like Signal, iMessage is end-to-end encrypted …" (361) | **H132** (G1) |
| 135, 136 | `43e010c0` NHR | "WhatsApp"; "Encrypted in transit and at rest, WhatsApp is owned by Meta, …" (292) | **H136** (G1) |
| 141, 142 | `1b29af76` HRU | "Facebook Messenger"; "Encrypted between people, but built around an account …" (241) | **H142** (G1, G2) |
| 189 | `fb84afbe` HRU | "outpostmessaging.com" | none |

The proposals keep "the %@ Dev", the term in the chunks Griff reviewed, and none of them says "we".

#### H23 · `CarpenterUI/Screens/Identity/HowItWorksView.swift:23` · chunk `7d330d05` [HUMAN REVIEWED, UNVERIFIED] · 156 → 152 · class G

- Now opens: "%@ is a peer-to-peer messaging app. Everything you write is stored only …" (not over 200; here because it is on this page and wrong)
- Replace the whole literal with:

  ```
  \(Branding.displayName) runs no server. What you write is kept on your devices and the devices of the people you wrote it to. On the way, a sealed copy waits in your iCloud.
  ```
- Notes: G2. Sets chunk `7d330d05` back to `NEEDS HUMAN REVIEW`.

#### H43 · `CarpenterUI/Screens/Identity/HowItWorksView.swift:43` · chunk `b561c670` [NEEDS HUMAN REVIEW] · 104 → 176 · class F

- Now opens: "%@ uses your Keychain as its identity: there is no account …" (not over 200; here because it is on this page and wrong)
- Replace the whole literal with:

  ```
  Your identity is a key in your device's Keychain. \(Branding.displayName) has no account of its own, and its Dev stores nothing about you. It does use the Apple Account your iCloud is signed in to.
  ```
- Notes: Checked: every keychain write uses the device scope. Apply without waiting.

#### H33 · `CarpenterUI/Screens/Identity/HowItWorksView.swift:33` · chunk `04884ac4` [HUMAN REVIEWED, UNVERIFIED] · 333 → 198 · class G

- Shown: How this works > Your own iCloud as a Mailbox, paragraph 2.
- Now opens: "The %@ Dev has no server, and nothing to …"
- Replace the whole literal with:

  ```
  The \(Branding.displayName) Dev runs no server. A message waits in your own iCloud, sealed, under an address that changes daily, and is removed once it's received or after nine days. Nobody, Apple included, can read it.
  ```
- Notes: Optional. Shorter, and adds the nine days. The chunk is HUMAN REVIEWED, UNVERIFIED: G2.

#### H34 · `CarpenterUI/Screens/Identity/HowItWorksView.swift:34` · chunk `04884ac4` [HUMAN REVIEWED, UNVERIFIED] · 206 → 194 · class G

- Shown: How this works > Your own iCloud as a Mailbox, paragraph 3.
- Now opens: "Media is treated the same, as a sealed file. …"
- Replace the whole literal with:

  ```
  Photos and clips are sealed the same way. Apple can see a sealed file's size, when it was left and received, and which Apple Accounts it passed between. Only you and your recipients can read it.
  ```
- Notes: Wrong against the build: 'it can see nothing else'. Apple can also see when a file was left and collected and which account it is shared with (docs/crypto-brief.md:828-832). HUMAN REVIEWED, UNVERIFIED: G2.

#### H51 · `CarpenterUI/Screens/Identity/HowItWorksView.swift:51` · chunk `b561c670` [NEEDS HUMAN REVIEW] · 261 → 196 · class S

- Shown: How this works > Invitations and Approvals, paragraph 2.
- Now opens: "Rooms can be customized to different member approval settings, …"
- Replace the whole literal with:

  ```
  A room sets who approves a newcomer: nobody, its founder, one member, any member, or several. Whatever the rule, you and the person you invite compare characters, so nobody is taken at their word.
  ```
- Notes: Checked: the rules are open, founder, one member, any member, at least N (CarpenterKit/Membership/RoomAccess.swift:3-12).

#### H57 · `CarpenterUI/Screens/Identity/HowItWorksView.swift:57` · chunk `b561c670` [NEEDS HUMAN REVIEW] · 353 → 199 · class S

- Shown: How this works > Sync and Restore.
- Now opens: "Your identity reaches a new device only when one …"
- Replace the whole literal with:

  ```
  A new device gets your identity only when one of yours approves it, never through iCloud Keychain. Lose them all and your recovery key restores you and requests conversations from the people in them.
  ```
- Notes: Checked: no keychain write is synchronized (see L42).

#### H68 · `CarpenterUI/Screens/Identity/HowItWorksView.swift:68` · chunk `614f14c4` [HUMAN REVIEWED, UNVERIFIED] · 295 → 179 · class G

- Shown: How this works > Source & Review.
- Now opens: "%@ is open source, published under the Mozilla Public …"
- Replace the whole literal with:

  ```
  \(Branding.displayName) is open source under the Mozilla Public License 2.0, so anybody can read it. Nobody outside the project has reviewed it. Report a security problem to info@outpostmessaging.com.
  ```
- Notes: 'we solicit external security reviews' against RULED 2026-09-14 'the brief, and no outside reviewer' (docs/decisions.md:1534-1541). 'scanned and tested ... before releases': what exists is a weekly sanitizer job (.github/workflows/scan.yml) and there has been no release. The earlier section that said nobody outside had reviewed it (docs/epics/foundations.md:842-850) is no longer in the Swift. G3.

#### H77 · `CarpenterUI/Screens/Identity/HowItWorksView.swift:77` · chunk `1675ec4f` [HUMAN REVIEWED, UNVERIFIED] · 291 → 199 · class G

- Shown: How this works > Notifications.
- Now opens: "Notifications enable realtime banners, badges, and sounds to alert …"
- Replace the whole literal with:

  ```
  Notifications can show a banner, a badge and a sound for a new message, and for other events you choose. If you decline, new messages appear when you open the app. You choose how much a banner shows.
  ```
- Notes: Optional. Nothing wrong found; shorter only. HUMAN REVIEWED, UNVERIFIED: G2.

#### H86 · `CarpenterUI/Screens/Identity/HowItWorksView.swift:86` · chunk `85f818ac` [HUMAN REVIEWED, UNVERIFIED] · 219 → 196 · class G

- Shown: How this works > Media.
- Now opens: "Media is sent stripped of metadata, and sealed like …"
- Replace the whole literal with:

  ```
  Photos and clips are sent stripped of metadata and sealed like any message. With iOS's Sensitive Content Warning on, one judged sensitive is blurred until you choose to look. See Privacy & Safety.
  ```
- Notes: Wrong against the build: only a photo iOS judges sensitive is blurred, and only when iOS's Sensitive Content Warning is on (You/Settings/PrivacyAndSafetySettingsView.swift:121, 315, 319). The page is Privacy & Safety, not Safety. HUMAN REVIEWED, UNVERIFIED: G2.

#### H118 · `CarpenterUI/Screens/Identity/HowItWorksView.swift:118` · chunk `07207d26` [NEEDS HUMAN REVIEW] · 474 → 197 · class G

- Shown: How this works > the comparison heading's paragraph.
- Now opens: "The %@ Dev Opinion is that all of these …"
- Replace the whole literal with:

  ```
  The \(Branding.displayName) Dev's opinion: these apps are impressive and none is unsafe. They work differently.\n\nYou gain nothing on hosting: sealed messages wait in iCloud, and Apple sees which accounts exchange them.
  ```
- Notes: See section 7. G1.

#### H128 · `CarpenterUI/Screens/Identity/HowItWorksView.swift:128` · chunk `43e010c0` [NEEDS HUMAN REVIEW] · 333 → 196 · class G

- Shown: How this works > Signal.
- Now opens: "Signal's encryption set the standard the rest of the …"
- Replace the whole literal with:

  ```
  Signal's encryption set the standard this app follows. Signal needs a phone number and runs the servers messages pass through. \(Branding.displayName) runs no server and has no account of its own; it uses your iCloud.
  ```
- Notes: See section 7. G1.

#### H132 · `CarpenterUI/Screens/Identity/HowItWorksView.swift:132` · chunk `43e010c0` [NEEDS HUMAN REVIEW] · 361 → 200 · class G

- Shown: How this works > iMessage.
- Now opens: "Like Signal, iMessage is end-to-end encrypted between devices. The …"
- Replace the whole literal with:

  ```
  iMessage is end-to-end encrypted. With iCloud Backup on and Advanced Data Protection off, the backup holds a copy of the Messages in iCloud key. Here your keys stay on your devices and out of backups.
  ```
- Notes: See section 7. G1.

#### H136 · `CarpenterUI/Screens/Identity/HowItWorksView.swift:136` · chunk `43e010c0` [NEEDS HUMAN REVIEW] · 292 → 197 · class G

- Shown: How this works > WhatsApp.
- Now opens: "Encrypted in transit and at rest, WhatsApp is owned …"
- Replace the whole literal with:

  ```
  WhatsApp encrypts personal messages end to end. Its privacy policy says it collects how often you interact with others and shares information with other Meta companies. The \(Branding.displayName) Dev collects nothing.
  ```
- Notes: See section 7. G1.

#### H142 · `CarpenterUI/Screens/Identity/HowItWorksView.swift:142` · chunk `1b29af76` [HUMAN REVIEWED, UNVERIFIED] · 241 → 148 · class G

- Shown: How this works > Facebook Messenger.
- Now opens: "Encrypted between people, but built around an account tied …"
- Replace the whole literal with:

  ```
  Encrypted between people, but built around an account tied to your real identity. \(Branding.displayName) has no account of its own, no algorithms and no social network.
  ```
- Notes: See section 7. G1 and G2 (HUMAN REVIEWED, UNVERIFIED).

Notes on the five comparison strings:

- H118 drops the sentence about a debug build and the claims about where WhatsApp and Meta are
  hosted, and adds the one thing a reader weighing these apps should be told: Apple can see which
  accounts exchange sealed messages. Signal says it can produce less than that about its own users.
- H128 keeps the two facts read at Signal's own pages and drops the history contrast.
- H132 says "with iCloud Backup on and Advanced Data Protection off", which is the case Apple
  describes. "out of backups" is `CarpenterKit/Storage/StorageLocation.swift:46-50` and the
  `ThisDeviceOnly` keychain classes (`CarpenterKeychain/SystemKeychainStore.swift:23-24`).
- H136 says what WhatsApp and its policy say, in their terms.
- H142 keeps the first clause of the reviewed sentence and drops "a company whose business is knowing about you", which is
  an opinion about a named company, and "has no identity to tie anything to".
- If G1 is answered "take the named cards out": delete lines 125-144 of `HowItWorksView.swift` with
  both marker pairs (`43e010c0`, `1b29af76`), delete `comparison(_:_:)` at 148-163 (it then has no
  caller), keep the heading and H118, and change the heading at 112 to something that names nobody.
  That is a code change and is built before it is called done.

## 8. Table D: the banner that promises testers a free year

What backs it, from the code:

- The bar shows while `canClaimSupporterYear` is true: the copy did not come from the App Store and
  no year has been claimed (`CarpenterApp/Session/AppSession+Supporter.swift:16-18`,
  `CarpenterKit/Model/Supporter.swift:6`). A Release build learns how it was installed from
  `AppTransaction.shared` (`App/Carpenter/AppRootView+Supporter.swift:20-27`): sandbox means
  TestFlight.
- Tapping it writes today's date into the member's preferences as `supporterYearClaimed`
  (`AppSession+Supporter.swift:39-44`). Preferences travel to the member's other devices in the
  sealed sibling feed (`CarpenterKit/Sync/SiblingFeed.swift:40`).
- The year starts the first time an App Store build opens on this member's phone, not on the day of
  release (`AppSession+Supporter.swift:55-62`, `Supporter.swift:17-25`), and ends a year later.
- What a Supporter has in this build: a badge they may show, and a row under You. Nothing else reads
  `isSupporter` (`grep`, 2026-11-10: `SupporterView.swift:24`, `YouView.swift:247`,
  `AppSession+Supporter.swift:14, 21`, `AppRootView+Supporter.swift:39`).
- There is no purchase: no product, no price, no subscription, no offer code, no receipt check. The
  only StoreKit call is the one above. `docs/app-store.md:32` and `:483` say the same: "The Supporter
  purchase — Not built."
- "Packs" appear in four sentences and nowhere in the code.

So the promise is a year of something that cannot be bought yet, kept as a date in the member's own
preferences. It is honoured only if the build that sells Supporter reads that date. The bar's words
are Griff's ruling (`docs/decisions.md:233-244`), so they are not changed here. What is proposed is
that the page behind the bar says what is true today.

| File:line | Chunk | Now | Still true? | Change |
|---|---|---|---|---|
| `Supporter/SupporterBar.swift:19` | `2231431d` | "Become a Supporter" | His ruling | none |
| `Supporter/SupporterBar.swift:21` | `2231431d` | "**One Year Free** for TestFlight users" | His ruling. Nothing to buy stands behind "free" (G4). | none |
| `Supporter/SupporterWelcomeView.swift:38` | `d60c364b` | "You’re a Supporter" | Yes: the standing is set | none |
| `:48` | `69f3481f` | "Thank you for testing. Your year is free, and it starts on the day the app is released on the App Store." | No: it starts the day this member first opens an App Store build | **S48** (G4) |
| `:60` | `9824d46c` | "Supporters pay for the time it takes to build what comes next. First up are Packs: extras you add to a conversation, starting with shared lists." | Nobody pays yet; Packs are a plan | **S60** (G4) |
| `:65` | `9824d46c` | "A Pack you turn on works for everyone in that conversation. Your friends won’t need to be Supporters to use it with you." | Present tense for something not built | **S65** (G4) |
| `:81`, `:93` | `863632b8` | "Continue", "Close" | Yes | none |
| `:129`, `:139` | `a9ca4b86`, `c36056ae` | "Show the Supporter badge?"; "A small mark on your picture. Everyone in your conversations sees it, and so does anyone who can read your Outpost." | Yes by `docs/decisions.md:265-268`; not re-checked in code | none |
| `:156`, `:165`, `:171` | `1f448f68`, `7d3bb100`, `cba1e7bc` | "Show the badge", "Not now", "You can change this under You, Supporter." | Yes (`You/YouView.swift:247-255`) | none |
| `Supporter/SupporterSettings.swift:29` | `18b805c8` | "You are not a Supporter." | Yes | none |
| `:32` | `18b805c8` | "Your free year starts on the day the app is released on the App Store." | No, as `:48` | **S32** |
| `:36` | `18b805c8` | "Your free year runs until %@." | Yes | none |
| `:45-48` | `19b0bece` | "Ended", "Free year", "Until %@" | Yes | none |
| `Supporter/SupporterView.swift:21`, `:28`, `:64` | `66eb4921`, `06717d83` | "Supporter", "Show the badge", "Supporter" | Yes | none |
| `:32` | `66eb4921` | "A small mark on your picture. …" | As above | none |
| `:43` | `ede6da95` | "Supporters pay for the time it takes to build what comes next, starting with Packs." | Nobody pays yet | **S43** |
| `:50` | `ede6da95` | "A Pack you turn on works for everyone in that conversation, whether they support or not." | Present tense for something not built | **S50** |
| `:56` | `ede6da95` | "What it pays for" | Becomes "What it will pay for" if S43 is applied | see below |

**S48** · `Supporter/SupporterWelcomeView.swift:48` · chunk `69f3481f` [NEEDS HUMAN REVIEW] · 170 characters · class G

```
Thank you for testing. Supporter will be a paid subscription once the app is on the App Store. Your first year is free, and it starts the day you first open that version.
```

States a plan to charge. Hold for G4.

**S60** · `Supporter/SupporterWelcomeView.swift:60` · chunk `9824d46c` [NEEDS HUMAN REVIEW] · 176 characters · class G

```
There is nothing to buy yet, and today a Supporter gets a badge to show and nothing else. Planned first are Packs: extras you add to a conversation, starting with shared lists.
```

Says what a Supporter gets today. Hold for G4.

**S65** · `Supporter/SupporterWelcomeView.swift:65` · chunk `9824d46c` [NEEDS HUMAN REVIEW] · 138 characters · class G

```
A Pack is planned to work for everyone in the conversation it's turned on in. Your friends won't need to be Supporters to use it with you.
```

Hold for G4.

**S32** · `Supporter/SupporterSettings.swift:32` · chunk `18b805c8` [NEEDS HUMAN REVIEW] · 78 characters · class F

```
Your free year starts the day you first open the App Store version of the app.
```

**S43** · `Supporter/SupporterView.swift:43` · chunk `ede6da95` [NEEDS HUMAN REVIEW] · 112 characters · class F

```
Supporting will pay for the time it takes to build what comes next, starting with Packs. Nothing is charged yet.
```

With it, the heading at `SupporterView.swift:56` becomes `What it will pay for`.

**S50** · `Supporter/SupporterView.swift:50` · chunk `ede6da95` [NEEDS HUMAN REVIEW] · 125 characters · class F

```
Packs aren't built yet. A Pack you turn on is planned to work for everyone in that conversation, whether they support or not.
```

If G4 is answered "hide the bar until the purchase is built", that is his ruling changing and a code
change (`Supporter.swift:6` decides who is offered the year). It is not part of this order.

## 9. The string catalogues

Why they need attention: the catalogue committed in `c8bc149` holds the text from before that
commit's own shortening. Keys are the English text, so each shortened string left its old key behind
and has no key of its own yet. A string with no key is shown as written in the source (how the
system treats a missing key; not measured here), so the screens are right. What is wrong is that the old text is still compiled into the app's resources.

How Xcode keeps a catalogue: "Each time you build your project, Xcode updates your string catalogs
with changes you make to localizable strings in your code"
(https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog,
read as its `.json`). That page describes Product > Build in Xcode. Whether a command-line
`xcodebuild` writes the catalogue back into the source tree is not verified, and the state of this
repository suggests it did not happen on 2026-11-10.

Steps, after every Swift change in this order is in:

1. Build the app once from Xcode itself (Product > Build, scheme Carpenter), so the three catalogues
   are rewritten from the source. If the executing agent has no Xcode window, try the `xcodebuild`
   build from CLAUDE.md and look at `git diff --stat -- '*.xcstrings'`. If nothing changed, the
   catalogue was not synced: say so and leave steps 2 to 4 to a session that can.
2. Run the check:
   `python3 -I /private/tmp/claude-501/-Users-grifftatarsky-projects-outpost/f313c3e3-558d-46ba-9bcc-c43ae72ae298/scratchpad/design/tools/catalogue_check.py /Users/grifftatarsky/projects/outpost 200`.
   Before this order it prints `CarpenterUI: 1267 keys, 65 over 200, 80 with no literal`.
3. Remove every key Xcode marked `"extractionState" : "stale"`, and every key the check lists as
   having no literal once `grep -rnF` for its first few words finds nothing under
   `Packages/Carpenter/Sources` and `App`. No language other than English exists in any of the three
   files (`"sourceLanguage" : "en"`, and the only `localizations` are `en` entries that number the
   placeholders), so nothing translated is lost.
4. Do not write a status, a comment or a marker into a catalogue. The only fields a person wrote
   there are the `comment` strings; Xcode keeps those.

The 23 long keys that are already gone from the Swift (first words; all in
`CarpenterUI/Resources/Localizable.xcstrings`):

- "A message waiting for somebody to open the app is ordinary, …"
- "A torn or oversized record is cleared from the log at the next write. …"
- "An Outpost is a page of your own. You choose who reads it, one person at a time, and nobody …"
- "Anybody who comments on an Outpost you both read, but whom you have never shared …"
- "Anything on this list can send messages as you. …"
- "Hiding is yours alone. The message stops being drawn on your devices …"
- "Messages are delivered straight to their recipients. … Once all recipients have collected the message, …"
- "Nobody, until you say so. Being in a room together is not an answer to this. …"
- "Nothing here is a fault. A message reaches somebody when their app next opens and collects it, …"
- "Off, every other person is shown as a short code and initials from it, …"
- "Off, your copy goes as soon as the ask arrives — …"
- "Somebody in this room did not collect it within ^[%lld day](inflect: true), …"
- "Somebody who loses every device comes back with a recovery key, and their conversations come back … (513)"
- "The photo on your You page, at the top of your Outpost, unless you choose a different one here. Off, …"
- "The photo you pick on You goes to the people you share rooms with, …"
- "The photo you pick on You is drawn at the top of your Outpost as well, …"
- "This one is about your own history, not anybody else's. …"
- "When you end up in a room with somebody new, the room asks once …"
- "You and anybody you talk to alone already have the same characters, from how you met. On, …"
- "You and anybody you talk to alone already have the same characters, worked out from how you met. Off, …"
- "Your name goes to the rooms you are in, as the default name people see for you; …"
- "Your name goes to the rooms you are in, as the name people see for you, once this is on; … (736)"
- "Your name, your picture and everything else about you stay off a comment anybody unmet reads. …"

## 10. Order of work

1. Read sections 3 and 4. Find out which of G1 to G10 Griff has answered. With no answers, 51 of
   the 62 long strings are shortened by this order and 11 wait for him (L07 and ten on How this
   works).
2. Apply the class S and class F rows of Table A, file by file, bottom of each file first. For each:
   confirm the string still opens with the words given, replace the literal, confirm the chunk's
   `COPY BEGIN` line reads `[NEEDS HUMAN REVIEW]`. L07 waits (G1). For L17 apply L17a and L17b;
   L17c waits (G7).
3. Apply the lock rows that do not wait: K159, K227, K672, and K390t with K402 unless G5 says
   remove. Apply K313, K361 and K486 only if plan step 4 (the lock walked on an iPhone) is written
   up as done, or Griff says to (G7).
4. Apply S32, S43, S50 and the heading change.
5. Apply H43, H51, H57. Apply the other How this works rows and L07 only as far as G1, G2 and G3
   were answered. For each chunk at `HUMAN REVIEWED, UNVERIFIED` that changes, set its `COPY BEGIN`
   line to `[NEEDS HUMAN REVIEW]`.
6. Run the tests in section 12.
7. Bring the catalogues into line (section 9).
8. Write it up, each inside the COPY chunk it lands in or a new pair:
   - `docs/pre-testflight.md:134-136`: what of step 12 is done and what waits on Griff.
   - `docs/open-questions.md`: G1 to G9 as questions with the recommendations, for whichever are
     still open.
   - `docs/decisions.md`: a `PROPOSED` entry recording the sources in section 7 and the date they
     were read, because a statement about another company's product goes stale.
   - `docs/inbox.md`: section 14.
9. If asked to commit, keep these apart: the shortening (Table A), the lock, the Supporter page, How
   this works, the catalogues, and any code change (L17's layout, G5's removal). Say in each message
   what was built and what was not.

## 11. What done looks like

- No string a member reads on a screen is over 200 characters, except the rows still held for
  Griff and any he declined to change. `catalogue_check.py` lists, under "Swift literals over 200 inside a COPY chunk", only
  `CarpenterKit/Crypto/RecoveryKey.swift:58` and the held rows.
- After the catalogue sync the same check prints `0 over 200` for `CarpenterUI`, apart from held
  rows, and close to `0 with no literal`.
- `python3 Scripts/copy-review.py check` exits 0. `report` shows 1,479 chunks (1,478 if chunk
  `095e4033` was deleted under G5, more by one for each new pair). `HUMAN REVIEWED, UNVERIFIED` is 36
  less the number of reviewed chunks changed: at most 6 fewer.
- No sentence on the lock's screens says the lock only guards screens, and none says another device
  is erased when it may not be.
- No sentence on How this works states something about another company that was not read at that
  company's own page, and none says Apple can see nothing but a size.
- The page behind the Supporter bar says the year starts when the member first opens the App Store
  version, and no sentence about Packs is in the present tense.
- Every held row is written into `docs/open-questions.md` as a question for Griff, with the
  recommendation.

## 12. Tests to run

Copy cannot fail a unit test by being wrong, so most of this is mechanical and the rest is looking.

```bash
python3 Scripts/copy-review.py check && python3 Scripts/copy-review.py report
```

```bash
SKIP_SYMBOL_CHECK=1 ./Scripts/lint-branding.sh
```

```bash
python3 -I /private/tmp/claude-501/-Users-grifftatarsky-projects-outpost/f313c3e3-558d-46ba-9bcc-c43ae72ae298/scratchpad/design/tools/catalogue_check.py /Users/grifftatarsky/projects/outpost 200
```

```bash
xcodebuild -workspace Carpenter.xcworkspace -scheme Carpenter -destination 'platform=iOS Simulator,id=5A43F953-128D-4FE6-9135-0D26520E02B6' build
```

```bash
cd Packages/Carpenter && swift test
```

- The build is the test that every literal still parses: an unescaped quote, a broken `\(…)` or a
  `"""` block with its closing line indented wrongly fails there. Read the warnings.
- Tests that match on copy, found by `grep` on 2026-11-10: `App/CarpenterUITests/RigChecks.swift:96`
  ("Familiar and open"), `:186-204` ("Lock the app"), `:209` ("Make them private"), `:259` ("Forgot
  the code?"), `:357` and `:400` ("Become a Supporter"). None of those words change in this order,
  unless G5 is "remove", which deletes the step at `:209`.
  `Packages/Carpenter/Tests/CarpenterKitTests/JoinedSentencesTests.swift` matches "Not received",
  which does not change. `PrivateNotificationsTests.swift` goes only with G5 "remove".
- On a simulator, software keyboard on, look at each changed screen once at the default text size
  and once at the largest accessibility size: the welcome tour, How this works, You > Privacy &
  Safety, the privacy check-up, You > Notifications and the level page, You > Your Outpost, the lock
  setup and the lock's settings, the lock screen's *Forgot the code?* alert, the Supporter page. The
  two alerts (K159, K402) are the ones to watch at the largest size.
- Nothing here crosses the network, so the rig's two accounts are not needed for this step. G9 does
  need them.

## 13. Risks

1. **The catalogue is not synced.** If no build writes it back, the new strings have no key and the
   old ones stay. Screens still read correctly; the bundle still carries the old words. Say which
   happened.
2. **A reviewed chunk is reset without his yes.** Five chunks (six with H23) are at
   `HUMAN REVIEWED, UNVERIFIED`. Changing one without G2 throws away work only he can redo.
3. **A statement about another app goes stale or is wrong.** The sources were read once, on
   2026-11-10, each at one page. Meta's post describes a rollout begun in 2023 and was not checked
   against the product today. The quotations are as a page-reading tool returned them, so open each
   page again before words about another company ship. Keep the URLs with the decision.
4. **The lock's words run ahead of the proof.** K313, K361 and K486 describe sealing that has run on
   a simulator's stand-in and never on a phone. K361, K402, K486 and L17c say a banner is generic
   with the lock on: that is read from `NotificationService.swift:56-79`, not watched.
5. **K672 depends on a decision that is open.** If Griff chooses to keep a signed notice outside the
   vault, K672 goes back to saying every device.
6. **Line numbers move.** They are from `9af603a`. Match on the opening words.
7. **Interpolations.** L02 and L43 carry `^[…](inflect: true)` and must keep it byte for byte, or the
   plural stops working. L14 and L17 are `"""` blocks today.
8. **Facts dropped to get under 200.** Each row's notes say what was dropped. Where the dropped fact
   lives nowhere else, it is named: L34 drops "either of you can ask again at any time", L50 drops
   "You can change this only here", L42 and H57 drop "removes every other device" (it stays on the
   recovery key's own pages and in L05).
9. **Claims carried over without re-checking the code.** Marked in the notes: L01, L03, L13, L22 to
   L27, L35 to L39, L44 to L47, L49, L50. They say what the current string says, in fewer words.

## 14. Noticed and parked

For `docs/inbox.md`, none of it changed by this order:

- `CarpenterUI/Screens/Safety/BlockedPeopleView.swift:93` says "You can undo this under You ›
  Safety." The list of blocked people is on Privacy & Safety
  (`You/Settings/PrivacyAndSafetySettingsView.swift:227`).
- The lock is "App lock" on its row and header (`AppLockViews.swift:484`,
  `YouView+Settings.swift:175`) and "App Lock" as a title (`AppLockViews.swift:384, 556`).
- `AppLockViews.swift:486` writes "Face ID" on a phone that may have Touch ID.
- `CarpenterUI/Screens/Notifications/MessagingNotificationsView.swift:68` and
  `NotificationLevelView.swift:32, 216` describe what a banner shows and do not say that App Lock, or
  Advanced On Device Security while the phone is locked, reduces every banner to "something
  arrived".
- `You/Settings/DeviceSecuritySettingsView.swift:50` says messages "arrive when you unlock it". A
  message nobody collected in nine days is taken back first and returns only through history repair
  (`docs/decisions.md:4421-4424`).
- The welcome tour's first panel says "no one can look you up" and the locked-down preset says
  "You are a short code to everyone". Both wait on G9.
- `docs/pre-testflight.md:89-90` says 62 strings no longer say "the ask", "drawn", "collected",
  "log" or "entry". That is true of the Swift and not yet of the catalogue.

## 15. Sources read

Web, all on 2026-11-10:

- https://developer.apple.com/tutorials/data/design/human-interface-guidelines/writing.json
- https://developer.apple.com/tutorials/data/design/human-interface-guidelines/alerts.json
- https://developer.apple.com/app-store/review/guidelines/ (first 100,000 characters)
- https://developer.apple.com/tutorials/data/documentation/xcode/localizing-and-varying-text-with-a-string-catalog.json
- https://developer.apple.com/tutorials/data/documentation/cloudkit/ckuseridentity.json
- https://developer.apple.com/tutorials/data/documentation/cloudkit/ckshare/metadata.json
- https://support.apple.com/en-us/102651
- https://signal.org/bigbrother/
- https://signal.org/blog/phone-number-privacy-usernames/
- https://signal.org/blog/signal-is-expensive/
- https://faq.whatsapp.com/820124435853543
- https://www.whatsapp.com/legal/privacy-policy
- https://about.fb.com/news/2023/12/default-end-to-end-encryption-on-messenger/

Not reached: https://support.signal.org/hc/en-us/articles/6712070553754 (HTTP 403).

Repository, read at `9af603a`: `Scripts/copy-review.py`, `Scripts/lint-branding.sh:20-100`,
`docs/pre-testflight.md:26-136`, `docs/open-questions.md:153-235`, `docs/decisions.md:233-275,
1534-1556, 3722-3760, 4401-4440, 6395-6440`, `docs/crypto-brief.md:800-850`,
`docs/epics/identity-and-devices.md:712-760`, `docs/epics/foundations.md:836-850`, the three
catalogues, and the Swift files named in the tables.


<!-- COPY END ae137056 -->
