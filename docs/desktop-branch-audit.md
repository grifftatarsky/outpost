<!-- COPY BEGIN 3c7009be [NEEDS HUMAN REVIEW] -->

# What `origin/desktop` delivered that this branch lacks

> **How far this was checked.** Written on 2026-11-10 by reading agents, which built and ran nothing.
> On 2026-11-11 one part was checked again by hand: the five entries marked RULED in that branch's
> `docs/decisions.md` are not in this branch's, and `mayReceive` and `ConversationID` are in no file
> here. The rest is as the readers left it. The question it raises for Griff is in
> [open questions](open-questions.md#five-rulings-were-recorded-on-a-branch-that-never-merged).

Checked 2026-11-10 against the working tree of `overnight-2026-10-31` at `fe9ec3e` (another process
was committing while I read, so line numbers are as of my read). `origin/desktop` is 86 commits,
2026-09-18 to 2026-09-22, tip `6969995`, forked at `030c736`. This branch has 260 commits since the
fork and has changed 401 files under `Packages/Carpenter/Sources` and `App`, so almost nothing below
cherry-picks. "Bring over" means rebuild against today's code.

Nothing was built or run. Every "does X today" below is from reading; where it matters it says
"inferred" or "not verified".

Paths are relative to `/Users/grifftatarsky/projects/outpost`. `KIT/` = `Packages/Carpenter/Sources/CarpenterKit`,
`APP/` = `Packages/Carpenter/Sources/CarpenterApp`, `UI/` = `Packages/Carpenter/Sources/CarpenterUI`,
`TESTS/` = `Packages/Carpenter/Tests/CarpenterKitTests`.

## Count

| Status | Commits |
|---|---|
| Missing | 70 |
| Partly here | 13 |
| Obsolete | 2 |
| Already here | 1 |

I rechecked the symbol or line behind each missing and partly entry (docs-only commits by the code
they describe, plus spot checks of the pages) and agree with all 83 statuses. Six details the
readers had wrong or incomplete are listed at the end.

**Already here (1):** the Mac build fix, `40a946b`. `App/Carpenter/HardwareName.swift:1` imports only
Foundation and `:19-25` picks `hw.model` on a Mac. Written separately here by `4ddb3bd`.

**Obsolete (2):** CI and test-timing workarounds. `6ce36bb` dodged a compiler crash that CI no longer
hits (`.github/workflows/checks.yml:40`, `:48` run Xcode 27). `fe86686` parked a ten-second test
deadline and a fold cost; here the deadline is a shared sixty seconds (`TESTS/TestDeadline.swift:3-7`)
and the fold has a memory of opened entries (`APP/Session/OpenedPayloads.swift`).

## Four things only Griff can settle, because the two branches disagree

1. **Which platforms.** `origin/desktop` records two rulings dated 2026-09-19: "the iOS app is
   unticked, since we have the mac app" (`7d1e247`) and "Yes, ipad" (`b2a19f2`). This branch still
   carries the 2026-09-13 ruling they replaced (`docs/decisions.md:152-163`, `CLAUDE.md:3-6`), and the
   2026-11-10 plan says iPhone only without a RULED mark (`docs/pre-testflight.md:31-32`, `:118`). The
   25 Mac and iPad commits in section E wait on this.
2. **Who is sent an entry.** RULED 2026-09-20 on `origin/desktop` (`101f93f`): "a user provides only
   what another user is allowed to see. Ideally, they cannot retrieve something they will not be
   allowed to read." This branch says the opposite is "the design rather than a defect"
   (`docs/decisions.md:729-740`). The ruling wins by this repository's own rule; it is listed here
   because the fix changes the round.
3. **One numbered log per conversation.** RULED 2026-09-21 on `origin/desktop` ("I do believe that is
   enough.", "yes. I love an enum."). It changes the bytes of every entry. Before a tester build it
   is free; after one it is the first migration.
4. **A reinstall.** RULED 2026-09-21 on `origin/desktop`: "A reinstall should become the same device
   - if it's still correctly identified." Not recorded here, and not built here (row `6fbd452`).

## Everything missing or partly here

Verdicts: **Yes** = bring over before a tester build. **Later** = worth having, not a blocker.
**Ask** = waits on one of the four questions. **With** = goes with the commit named. **No** = leave.

### A. Who gets in, and who is sent what

| Commit | Date | What it was | What is here instead | Bring over? |
|---|---|---|---|---|
| `7125d1d` | 09-19 | RULED. An approver is a list of names; the inviter's own yes never counts. `WhoMayApproveTests`. | One named approver (`KIT/Membership/RoomAccess.swift:8`). Under any member, a number, or unanimous, the inviter's yes counts (`KIT/Membership/RoomRoster.swift:229`, `:239-246`). So I can invite somebody into an "any member approves" room and let them in myself. `docs/verification.md:87` says so. | **Yes.** A ruling, and it decides who enters a room. It changes `RoomAccess`'s stored form, which is free only now. Leave out the desktop decoder for the old single name. |
| `f75295a` | 09-19 | RULED. An invitation says, signed, whether it carries the history; a from-today joiner gets a new key and a floor. `JoiningFromTodayTests`. | No such field (`KIT/Membership/MembershipAttestation.swift:3-17`). A newcomer gets the newest key, which opens every earlier one. Already written down as decision 1 of the tester plan (`docs/open-questions.md:221-245`, `docs/pre-testflight.md:54`, `:96`, `:111`). | **Yes.** It changes what an invitation carries. Leave out the rule that a missing field means "shares history". |
| `21e9c73` | 09-21 | A round sends each reader only entries they may read, and says what it withheld. A repair answer is scoped and respects a history floor. `RepairScopeTests`. | Repair scoping is here, written differently (`APP/Session/AppSession+HistoryRepair.swift:356-365`). The round is not: every unsent entry on every held feed is offered to every reachable contact (`APP/Session/AppSession+Sync.swift:95-102`, `:134-140`, `:437-448`); only people removed from or gone from a room are held back (`APP/Session/AppSession+TellingLast.swift:13-30`). No floor check in repair. | **Yes**, question 2. Rebuilt, not ported: this branch already writes one packet per contact and filters through a `withholding(entry, person)` closure (`KIT/Sync/SyncSession.swift:266-270`), so the rule has a place to go (inferred, not designed). |
| `101f93f` | 09-21 | Docs. Records the ruling in question 2 and what was measured before the fix. | Not recorded. `docs/decisions.md:729-740` says the opposite. | **Yes**, with `21e9c73`. Record the ruling even if the code waits. |
| `a1a7cd1` | 09-21 | An entry's clock names only its own conversation. 12 lines in `Replica`, 1 in `append`. `EnvelopeLeakTests`. | `APP/Session/AppSession.swift:410` stamps `replica.frontier`, everything the device holds, in the clear and under the signature. `docs/decisions.md:1772-1779` calls it the whole social graph. | **Yes.** Small, and it changes what every entry signs. Not checked: whether `AppSession+TellingLast.swift:42-44`, which reads clocks, still works with a per-room clock. |
| `c6192d5` | 09-21 | A packet names only people its reader shares something with; a contact is told only "I want yours", never the whole list of Outposts this member follows. | Introductions are limited here, done differently (`KIT/Sync/PacketPlan.swift:12-47`, `TESTS/APacketOfStrangersTests.swift`). The follow list still goes whole to every contact (`APP/Session/AppSession+Outpost.swift:180-183`, `APP/Session/AppSession+Sync.swift:130-131`, `KIT/Sync/SyncSession.swift:299`). | **Yes**, the follow list only. A contact in one room learns that their friend follows a stranger. |
| `8e3c4a3` | 09-21 | An Outpost photo is uploaded for the Outpost's readers only. | Uploaded for every reachable contact (`APP/Session/AppSession+Outpost.swift:23`). The pairwise-secret cache half is here (`APP/Session/AppSession+Membership.swift:68-78`). | **Yes.** One line of recipients. Whether a non-reader's copy is ever cleared: not verified. |
| `2a10379` | 09-21 | Repair heads are counted only inside the conversation asked about. | `KIT/Log/Replica.swift:511` `heads(of:)` takes authors only, so a peer learns how far each author has got everywhere. | **Yes**, with `21e9c73`. |
| `384ec7c` | 09-21 | (a) A seal no longer opens without its writer. (b) An entry opens only under its own conversation's key. (c) Kind comes from the id. | (b) and (c) are here (`KIT/Log/Entry.swift:172-173`; `KIT/Membership/RoomFounding.swift:7`). (a) is not: `KIT/Crypto/SealedPayload.swift:71-75` still tries the context with no writer, and `TESTS/SealBindingTests.swift:41` holds that it opens. The app never writes that form (`Entry.swift:165`). | **Yes**, (a). It is a reader of a form no build writes, which the 2026-11-10 ruling removed everywhere else (`docs/decisions.md:6471`). Three files. |
| `4c18307` | 09-21 | A key turn a removal owes is found in the log each round, so losing the state file does not forget it. `OwedKeyTurnTests`. | Owed turns live only in the state file (`APP/Session/PersistedState.swift:53`, `APP/Session/AppSession+Outpost.swift:452-462`). A missing state file is an empty state (`APP/Session/AppSession+Identity.swift:47`). | **Yes.** If the turn is forgotten, the removed member keeps reading. |
| `368b6e4` | 09-19 | RULED. A member whose own fingerprint is on the bundled list gets one locked screen with a button to the contact form; no round runs. | Nothing. The list only hides other people, and only while the switch is on (`APP/Session/AppSession+Etiquette.swift:66-67`). No banned case in `APP/Session/RootDecisions.swift:5-12`. | **Later.** A ruling, 227 lines there. The desktop build never taught the notification extension the check; do that too. |
| `7b73c34`, `72eba81` | 09-19 | The ban screen's drawing and its source SVGs. | `UI/Resources/Logo.xcassets` has no BanMark; `logo_svgs/` has no BAN files. | **With** `368b6e4`. |
| `86396bd` | 09-19 | RULED. Supporter badge: one switch draws it for you, a second shows it to others. | One switch does both (`APP/Session/AppSession+Supporter.swift:20`, `:70`; `KIT/Sync/MemberPreferences.swift:377-379`). | **Later.** Small. Leave out the fallback that read the old single answer. |
| `e43d2ba`, `08f84e7`, `6533cb3`, `8175175`, `79ba2f0` | 09-21 | Docs for the round and envelope fixes: the ruling "I'd like you to fix the problem where the whole count/existence is legible", two roadmap tickets, two epic stories, privacy page and inbox corrections. | The old statements are still in the docs and still true of this code (`docs/inbox.md:109`, `:113`, `:264`; `docs/outpost-privacy.md:96`). | **With** `21e9c73` and `a1a7cd1`. Copying them now would be untrue. Record the quoted ruling now. |
| `cef51f2` | 09-21 | Architecture page rewritten to say what the app does, plus a new section "Who a Packet Is For". | The three rule sections are here (`docs/architecture.md:261-338`); `:264-266` still opens with what broke on 2026-09-16. No "Who a Packet Is For". | **With** `21e9c73`. |

### B. The log, the files, and a reinstall

| Commit | Date | What it was | What is here instead | Bring over? |
|---|---|---|---|---|
| `6fbd452` | 09-22 | A reinstall is the same device once it has read its own positions back from iCloud; until then it writes and publishes nothing. `ReinstallTests`, proved on two accounts. | Keys stay on the device and a reinstall is not asked for approval again (`APP/Session/AppSession+Identity.swift:41-52`, `TESTS/DeviceApprovalTests.swift:252`). The hold is not here: this device's place is set only when it writes or loads its own log (`APP/Session/AppSession.swift:422`, `:489`, `:499`), never from an arriving entry. Inferred, not run: delete and reinstall, and the next message is written at position 1, where peers hold a different entry. | **Yes**, question 4. Testers reinstall. Rebuilt: the 1,458 desktop lines sit on device records this branch replaced (`KIT/Sync/SiblingMail.swift:38-40`). |
| `8699970` | 09-21 | A device moves its writing position forward when it sees its own entry come back. | Not here (same three lines as above). | **With** `6fbd452`. It is the small half and may be enough for a first build. |
| `6ecd617`, `6969995` | 09-22 | The hold starts before device sync attaches; the "record was ahead" count survives a relaunch. Also a note that the production CloudKit schema was found already deployed on 2026-09-22. | Not here. `docs/pre-testflight.md:442` still lists deploying to production as open. | **With** `6fbd452`. Carry the schema note now: the plan prunes names from the schema, and a production schema only grows (`docs/pre-testflight.md:458`). Not verified against the Console. |
| `ead0d84` | 09-22 | Docs for the reinstall, and two rig facts: a parallel-testing clone carried alpha's keychain and Apple Account and sent as alpha's device; uninstall then install is a reinstall. | `docs/testing.md:372-373` still says a clone "has no iCloud account". | **Yes**, the clone fact, as one corrected sentence. The rest with `6fbd452`. |
| `d9df536` | 09-21 | The log and state files are named for a format generation; older names are deleted on launch. | Plain names (`KIT/Storage/StorageLocation.swift:13-14`). No version anywhere in storage. | **Ask.** The file-name generation is useful input to the migration plan. Deleting the old files is the opposite of reading one prior format, so not as written. |
| `8186619` | 09-21 | `ConversationID` enum (.room, .solo, .outpost(owner)) replaces `RoomID` in 170 files. | `KIT/Model/ReadModel.swift:3` is still `RoomID`; an Outpost's id is still the first 16 bytes of its owner (`:10`, parked at `docs/inbox.md:109`). The kind is bound into a room's id by hash here (`KIT/Membership/RoomFounding.swift:7`). | **Ask**, question 3. |
| `caef13e` | 09-21 | Every entry names its conversation; nil no longer means the wall. Two guards on posting to somebody else's Outpost. | `KIT/Log/Entry.swift:41` is `room: RoomID?`; `:170` falls back to the author's Outpost. | **Ask**, question 3. |
| `ce6421e` | 09-21 | `FeedKey` gains the conversation, so positions count from one in each conversation. | `KIT/Log/VectorClock.swift:3-11` is author and device. Two PROPOSED entries here name "a feed per room" as what would change them (`docs/decisions.md:591`, `:714`). | **Ask**, question 3. |
| `2a980c7` | 09-21 | Members tell each other where each log in a room has got to; a mismatch is recorded and shown on the Integrity screen. `AttestationTests`. | Nothing (`KIT/Model/IntegrityReport.swift:4-28`). | **Later**, after question 3. It depends on per-conversation logs. |
| `d72e191`, `5c595c3`, `63c50f1` | 09-21 | Docs for the above, Griff's rulings of 2026-09-21, a two-account proof, and a rig trap (run the live suite before clearing an account). | None of the quotes are on this branch. `docs/outpost-privacy.md:63-65` still calls a chain per conversation "the wrong trade". | Record the rulings now. The pages **with** question 3. |
| `e0ca1ae` | 09-21 | Log, state, sync-engine state marked out of backups. | The whole store directory is marked (`KIT/Storage/StorageLocation.swift:38-50`). Not covered: `sync-engine.json` and `registration-probe.json` in Application Support (`App/Carpenter/AppRootView+Sync.swift:31-33`, `App/Carpenter/AppRootView+Device.swift:49-51`, `:258-260`). | **Yes**, those two files. A restored engine state tells a device with an empty log it has fetched everything (the desktop reason; not checked on a device). |

### C. Tester-build housekeeping

| Commit | Date | What it was | What is here instead | Bring over? |
|---|---|---|---|---|
| `2d219eb` | 09-19 | Opaque app icons; privacy manifest reason 1C8F.1; a manifest for the extension; README sends security reports to the form. | All 37 icon PNGs are RGBA (byte 25 = 6). `App/Carpenter/PrivacyInfo.xcprivacy` declares CA92.1 only, and the app and extension read App Group defaults (`KIT/Presentation/FocusFilter.swift:55`, `App/CarpenterNotificationService/NotificationService.swift:92`). No manifest in the extension. `README.md:104` is an email address. The single-read of the identity is here (`APP/Session/AppSession+Identity.swift:27`). | **Yes.** The upload error reads "can't be transparent or contain an alpha channel" (https://developer.apple.com/forums/thread/795411). 1C8F.1 is the reason for defaults shared within an App Group (https://developer.apple.com/tutorials/data/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons.json). Whether an extension needs its own manifest: not verified. |
| `86f6f89` | 09-19 | RULED: updates are a blog, not a mail link. Defines `APP_CONTACT_FORM_URL`. | `UI/Screens/You/YouView.swift:64-67` is a `mailto:` literal (it also has the product name in Swift). `Config/Branding.xcconfig` has no contact URL, so the "Report a problem" row never draws (`UI/Screens/You/Settings/PrivacyAndSafetySettingsView.swift:243`). Already item 7 of the plan. | **Yes.** Five files there. |
| `cf0e83f` | 09-19 | iOS 26.0 minimum. | 26.5 on all eight lines (`App/Carpenter.xcodeproj/project.pbxproj:452` and seven more). Who chose 26.0 is not recorded. | **Ask.** One number. |
| `32e5671` | 09-19 | Removed stray comments; `Scripts/lint/no-comments.py`. | No stray comments today (my grep: 0). No lint, so nothing stops them returning. | **Yes**, the lint. It must allow `COPY BEGIN`/`COPY END`, which its allow list does not. |
| `6a6ce59` | 09-19 | `__pycache__/` in `.gitignore`. | No bytecode tracked; no ignore rule. | **Yes.** One line. |
| `2988ca8` | 09-18 | Screen-read budgets scale with the machine. | Fixed 1 ms and 5 ms (`TESTS/ProjectionCostTests.swift:276`, `:283`). The `timing` tag only skips it under the sanitizer; CI runs it (`.github/workflows/checks.yml:57-59`). | **Later.** 15 lines. `foldChanged()` is `projectionInputsChanged()` here. |
| `315e47c` | 09-19 | `--rig-codes <dir>`: codes left in a directory while the transport stays CloudKit. | Codes are left only under `--mailbox` (`App/Carpenter/FileMailbox.swift:127-141`). The last CloudKit walk passed codes through Files (`docs/simulator-rig.md:371`). | **Yes.** 23 lines, and plan step 3 is a two-account walk. |
| `8cc37e9` | 09-19 | App Store screenshots from the fixtures, and fixtures made consistent. | No script. Fixtures disagree (`UI/Previews/Fixtures.swift:340`, `:244`). | **Later.** Not needed for internal testers. |
| `dc91991` | 09-19 | Docs: on Xcode 27 `simctl push` no longer runs the notification extension. | `docs/simulator-rig.md:151` says it does. | Re-measure, then fix one row. Not verified which is true. |
| `9bf55f9`, `06a9b5e` | 09-19, 09-20 | One roadmap, rig pages as instructions, TestFlight pages for testers. | Old pages, still edited. `nav_order` collides at 5, 6, 7 and 8. | **No** as a port. Fix `nav_order`. |
| `48c6cb0` | 09-21 | Decision log restarted with the old one archived; a reply that decides ends with a Decisions log (asked for by Griff 2026-09-20). | One log, 6,570 lines, now carrying copy markers. | **Ask.** |

### D. iPhone screens and copy

| Commit | Date | What it was | What is here instead | Bring over? |
|---|---|---|---|---|
| `a6e0d26` | 09-19 | A reacted bubble sharing a run was cut to one line. One `.fixedSize` line. | Same construction, no `.fixedSize` (`UI/Components/Messaging/MessageBubbleView.swift:206-273`). Whether it still reproduces: not verified. | **Yes.** Look at it on a simulator first. |
| `6fc5db4` | 09-19 | Griff's report: the blurb's Return wrote a second line and nothing closed the keyboard. `returnIsDone`, `doneAboveKeyboard`. | The reported field is unchanged (`UI/Screens/Outpost/OutpostSettingsView.swift:39-55`). Three separate keyboard bars now (`UI/Components/Messaging/MessageBubbleView.swift:484`, `UI/Screens/Membership/InviteView.swift:380`, `UI/Screens/Safety/AppLockViews.swift:374`). | **Yes.** |
| `7d1e247` | 09-19 | Filled Supporter mark; RULED: recovery key header from the display name; RULED: the Mac ships as its own app. | Header is the literal `"OUTPOST RECOVERY KEY"` (`KIT/Crypto/RecoveryKey.swift:44`), parked at `docs/inbox.md:231-235` as something to fix before anybody saves a key. Supporter mark unchanged. | **Yes**, the header. Mac ruling: question 1. |
| `f57ffff` | 09-18 | "phone" became "device"; "Click" on a Mac; VoiceOver hints name no gesture; context menus beside swipes. | Hints still say "Double-tap to" (`UI/Components/Messaging/MessageTapbackBar.swift:166`, `ReactionBar.swift:122`, `UI/Components/Media/MediaPictureView.swift:225`, `:237`, `:242`). Swipe-only: `UI/Screens/Safety/BlockedPeopleView.swift:37`, `UI/Screens/Rooms/EditRoomsListView.swift:71`, `:179`. | **Yes**, hints and context menus. Wording: question 1. Changed words reset their copy markers. |
| `051782d` | 09-19 | The last "phone" sentences say "device". | Some are "device" already (`UI/Screens/Identity/HowItWorksView.swift:23`). Many still say "phone", including screens written since (`UI/Screens/Safety/AppLockViews.swift:118`, `:150`, `:159`). | **Ask**, question 1. "Phone" is true on an iPhone. |
| `f24127e`, `ae6782a`, `be6b837` | 09-19 | RULED. A sealed draft per conversation, new post and comment; "Delete drafts" in Outpost settings. Also corrected `docs/app-store.md`. | Drafts are view state (`UI/Screens/Messaging/ConversationView.swift:14`). `docs/app-store.md:116-117` still says "we operate none". | **Later.** Inferred: the lock now seals the state file, so the draft's own key may not be needed. Fix the app-store sentence now. |
| `d6cb90e`, `d2858d0` | 09-19 | Reply and Mark as Read from a banner, and the two faults found on the rig. | A response only opens the thread (`App/Carpenter/PushRegistration.swift:67-76`). | **Later.** PROPOSED there. Inferred: it has to be squared with the lock, under which a notification says only that something arrived. |
| `75258aa`, `68a73c6` | 09-18, 09-19 | Asked for and RULED: the filled mailbox drawing, on white and then as a fourth icon in nine colours. | Three drawings (`KIT/Theme/AppIconChoice.swift:20`); no filled SVG in `logo_svgs/`. | **Later.** Regenerate with opaque output (`2d219eb`). |

Also in D, from two Mac commits: `4a1f543` built the rooms list once (here it is built twice,
`UI/Screens/RootView+Phone.swift:40`, `:86`) and raised two controls to 44 points
(`UI/Components/Messaging/ReactionBar.swift:166-177`, `UI/Screens/Outpost/OutpostView.swift:259-268`
at 38); `8c6d618` fixed `App/CarpenterUITests/VoiceOverWalkTests.swift:65-67` reading a navigation
bar that You does not have.

### E. Mac and iPad (all wait on question 1)

| Commit | Date | What it was | What is here instead |
|---|---|---|---|
| `7e1d72a`, `a6b2f28` | 09-18 | Mac icon (Icon Composer), tinted rule, App icon row hidden on Mac. | No `AppIconMac.icon`. The row draws; the picker behind it already refuses (`UI/Screens/You/Settings/AppIconPickerView.swift:21`, `:45`). |
| `d5ad57d` | 09-18 | Audience inspector beside your Outpost. | `UI/Screens/RootView+Desktop.swift:85-86`, no inspector. |
| `2f681ff`, `c8cfe3c` | 09-18 | `sizedSheet` for all sheets and a lint. | 72 bare `.sheet(`; no lint. |
| `40a7840` | 09-18 | Each title once. | Principal items unconditional (`UI/Screens/Outpost/OutpostFeedView.swift:127`, `UI/Screens/Rooms/RoomsListView+Content.swift:108`, `UI/Screens/Messaging/ConversationView.swift:224`). |
| `752414d` | 09-18 | Toolbar mailbox with a count. | None. `BadgeCount` still in `APP/Push`. |
| `6fbd0bf`, `30cc23b` | 09-18 | Settings window; grouped form on Mac. | One `WindowGroup` (`App/Carpenter/CarpenterMain.swift:38`). |
| `b816111` | 09-18 | Menu bar commands; shared start sheets. | None. The Mac window cannot start a room (inferred: `RootView+Desktop.swift` uses none of `onCreateRoom`, `onStartSolo`, `onRedeemInvite`). |
| `4a1f543`, `670a6e3`, `8c6d618`, `82a702a`, `32089b8` | 09-18 | Wide three-column layout for Mac and iPad, and its fixes. | `UI/Screens/RootView.swift:586-591`: Mac gets `desktop`, everything else the tabs. |
| `9e2e69b` | 09-18 | Escape on cancel; hover on photos. | None. (The cancel lint was deleted on desktop by `32089b8`.) |
| `0ebcc73` | 09-18 | RULED: Shift-Return writes a line on the Mac. | `.onSubmit(send)` only (`UI/Screens/Messaging/ConversationView+Composer.swift:268`). |
| `7672cf0`, `2e5631e` | 09-18, 09-19 | Drag and drop, and paste, of photos. Fixed a Mac text view pasting a dropped file's path. | None. Whether the Mac build here pastes the path: not verified. |
| `90327d2` | 09-19 | String catalogues for the above. | Follows the code. |
| `b2a19f2` | 09-19 | RULED: "Yes, ipad." | Question 1. |
| `98b216e`, `f766f58`, `3f9d83f`, `f162f45` | 09-18 | Desktop docs. | `docs/desktop-roadmap.md:60-65` is the pre-fork table. |

## What to bring over first

Ordered by: stops an upload, then a ruling about who reads what, then small iPhone fixes. Items 2 to
5 change stored or signed bytes, which is why they come before a tester build.

1. **Upload blockers** (`2d219eb`, `86f6f89`, `6a6ce59`).
   `Scripts/render-icon.swift`, `Scripts/make-app-icons.py`, the 37 PNGs under
   `App/Carpenter/Assets.xcassets/*.appiconset`, `App/Carpenter/PrivacyInfo.xcprivacy`, a new
   `App/CarpenterNotificationService/PrivacyInfo.xcprivacy`, `App/Carpenter.xcodeproj/project.pbxproj`,
   `Config/Branding.xcconfig`, `UI/Screens/You/YouView.swift`, `UI/Screens/You/YouView+Settings.swift`,
   `README.md`, `.gitignore`.
2. **The inviter cannot approve their own invitation; approvers are a list** (`7125d1d`).
   `KIT/Membership/RoomAccess.swift`, `KIT/Membership/RoomRoster.swift`,
   `KIT/Log/Bodies/MembershipBodies.swift`, `UI/Screens/Membership/RoomAccessView.swift`,
   `UI/Screens/Membership/NewRoomView.swift`, `UI/Components/Messaging/NoticeCopy.swift`,
   `TESTS/RoomAccessTests.swift`, a new `WhoMayApproveTests`, `docs/verification.md`.
3. **Room history setting** (`f75295a`), on Griff's yes to decision 1.
   `KIT/Membership/MembershipAttestation.swift`, `KIT/Membership/RoomRoster.swift`,
   `APP/Session/AppSession+Membership.swift`, `KIT/Log/Projection+Outpost.swift` (the floor to copy),
   `APP/Session/AppSession+HistoryRepair.swift`, `UI/Screens/Membership/AddSomeoneView.swift`.
4. **Send only what the reader may read, and sign only this conversation's clock** (`21e9c73`,
   `a1a7cd1`, `2a10379`, `c6192d5`, `8e3c4a3`).
   `APP/Session/AppSession+Sync.swift`, `APP/Session/AppSession+TellingLast.swift`,
   `KIT/Sync/SyncSession.swift`, `KIT/Log/Replica.swift`, `APP/Session/AppSession.swift`,
   `APP/Session/AppSession+Outpost.swift`, `APP/Session/AppSession+HistoryRepair.swift`,
   `KIT/Sync/HistoryRepair.swift`; then `docs/decisions.md`, `docs/inbox.md`,
   `docs/outpost-privacy.md`, and the "Carried for other people" row at
   `UI/Screens/You/Settings/IntegrityView.swift:211`. Needs the rig.
5. **A reinstall does not write over its own history** (`8699970`, then `6fbd452`).
   `APP/Session/AppSession.swift`, `APP/Session/AppSession+Identity.swift`,
   `APP/Session/AppSession+DeviceSync.swift`, `KIT/Sync/SiblingMail.swift`,
   `TESTS/DeletingARoomTests.swift`, a new `ReinstallTests`. Needs the rig.
6. **Drop the seal's no-writer fallback** (`384ec7c` a).
   `KIT/Crypto/SealedPayload.swift`, `TESTS/SealBindingTests.swift`, `docs/inbox.md`.
7. **A removal's key turn is read from the log** (`4c18307`).
   `APP/Session/AppSession+Outpost.swift`, `APP/Session/PersistedState.swift`, a new
   `OwedKeyTurnTests`.
8. **Recovery key header from the display name** (`7d1e247`).
   `KIT/Crypto/RecoveryKey.swift`, `KIT/Branding.swift`, `TESTS/ARecoveryKeyTests.swift`.
9. **Small iPhone fixes** (`a6e0d26`, `6fc5db4`, parts of `4a1f543`, `f57ffff`, `8c6d618`).
   `UI/Components/Messaging/MessageBubbleView.swift`, `UI/Screens/Outpost/OutpostSettingsView.swift`,
   `UI/Screens/Membership/InviteView.swift`, `UI/Screens/Safety/AppLockViews.swift`,
   `UI/Screens/Rooms/TagScreens.swift`, `UI/Components/Messaging/ReactionBar.swift`,
   `UI/Screens/Outpost/OutpostView.swift`, `UI/Screens/RootView+Phone.swift`,
   `UI/Components/Messaging/MessageTapbackBar.swift`, `UI/Components/Media/MediaPictureView.swift`,
   `UI/Screens/Safety/BlockedPeopleView.swift`, `UI/Screens/Rooms/EditRoomsListView.swift`,
   `App/CarpenterUITests/VoiceOverWalkTests.swift`. Building the rooms list once is also the base for
   the new message layout.
10. **Rig and lint upkeep** (`315e47c`, `32e5671`, `e0ca1ae`, `ead0d84` clone fact).
    `App/Carpenter/FileMailbox.swift`, `App/CarpenterUITests/RigChecks.swift`, a new
    `Scripts/lint/no-comments.py`, `Scripts/lint-branding.sh`, `App/Carpenter/AppRootView+Sync.swift`,
    `App/Carpenter/AppRootView+Device.swift`, `docs/testing.md`.
11. **Record the rulings that exist only on `origin/desktop`** in `docs/decisions.md`: the ones
    quoted in the four questions, plus the ban, the two Supporter switches, drafts, the blog, the
    filled mailbox, Shift-Return, and "Keep the log and state out of backups. And wait only for its
    own record." Each was found by `git grep` on `origin/desktop` and none on this branch.
12. **After the tester build, or on Griff's word:** the ban screen, Supporter switches, drafts,
    banner replies, filled icons, screenshots, timing budgets, and all of section E.

Question 3 (one log per conversation, `8186619`, `caef13e`, `ce6421e`, `2a980c7`) is not ranked. It
is the largest change on the branch and the only one that gets more expensive every build it waits.

## Where the readers were off

- `7e1d72a`: the App icon row is unhidden, but the picker already refuses on a Mac
  (`AppIconPickerView.swift:21`, `:45`), so only the row is extra.
- `21e9c73` / `101f93f`: "the design rather than a defect" was not written on 2026-11-04. It was in
  `docs/decisions.md` at the fork (`030c736`, line 465) and was edited that day; it now sits under
  the PROPOSED 2026-11-04 heading at `:690`.
- `21e9c73`: the desktop built one packet per audience. This branch already has a packet per contact
  and a withholding closure, so the port is a rule plus the accounting for what was withheld.
- `6fc5db4`: the separate keyboard bars are three, not two (`AppLockViews.swift:374` is new).
- `051782d`: more "phone" sentences than listed, in screens written since
  (`AppLockViews.swift`, `WaitingOnView.swift:37`, `RedeemInviteView.swift:320`,
  `MessageDetailView.swift:90`, `:97`).
- `4c18307`: the owed-turn lines are `AppSession+Outpost.swift:452-462` today.

<!-- COPY END 3c7009be -->
