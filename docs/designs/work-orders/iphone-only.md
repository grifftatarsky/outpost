<!-- COPY BEGIN 71a6bc9d [NEEDS HUMAN REVIEW] -->

# Work order: plan step 5, iPhone only and portrait only, then archive and validate once

> **A working design, written by agents on 2026-11-10 and 2026-11-11 and kept so the work need not be
> done again.** Nothing in it is a ruling. Where it names a file under `scratchpad/`, that was a
> working file and was not kept. Line numbers are from the commit it names and will drift.
> What is waiting on Griff is in [the Part B plan](../../part-b-plan.md).

Source of the step: `docs/pre-testflight.md:118-120`. Written 2026-11-10 against the working tree at
`9af603a` on `overnight-2026-10-31`. Nothing in the repository was changed to write this, nothing was
built, and no test was run.

Line numbers are for the files as they stood at `9af603a`. `App/Carpenter.xcodeproj/project.pbxproj`
(last commit `c7c73e2`, md5 `582b683ff693df2ccd561bcfff6fdb53`), both entitlements files and
`.github/workflows/checks.yml` had no uncommitted changes. Other agents are committing on this
branch, so **edit by the exact strings given, not by line number**, and re-count the matches first.

Words used here: "measured" means read out of a file or a build product on this machine today.
"Inferred" means reasoned and not checked. "Not verified" means nobody checked.

---

## 1. Read this first: one decision changes the shape of the step

The step says "make the target iPhone only". There are two ways to read it and they differ a lot.

- **Path K, keep the Mac window.** iPhone becomes the only device family and the only thing the
  tester build claims. The app target still builds as a native Mac app for Griff's own use.
- **Path D, drop the Mac from the app target.** The app target builds for iPhone and the iPhone
  simulator and nothing else. The package still builds on macOS, because `swift test` runs there.

`docs/decisions.md:152-163` is **RULED 2026-09-13 by Griff** and says: "The Mac window keeps working
— it runs in three columns and its keychain behaves like iOS's — because Griff uses it. It is not
offered, described, or supported." Path D reverses that sentence. A RULED entry is not reversed
without asking him (`docs/decisions.md:34`).

**Default for whoever carries this out: Path K**, because it satisfies the plan step for the build
testers get and leaves the ruling standing. Do Path D only if Griff has said, in his own words, that
the Mac window can stop building. Section 5 lists the Path D edits so they are ready if he does.

Everything in section 4 ("Core") is the same on both paths.

---

## 2. What it must guarantee (for Griff to confirm, CLAUDE.md rule 1)

1. The build testers get declares iPhone as its only device family, and Xcode offers no iPad, Vision
   or "Designed for iPad" destination for it.
2. Turning the phone never turns the app.
3. The signed app and the signed extension claim only entitlements the iPhone build uses: no Mac
   entry, no empty entry.
4. `swift test` still builds and passes on the Mac. On Path K the Mac window still builds too.

What sentence 1 cannot promise: an iPad owner can still install an iPhone-only app. Apple: "Adding
or removing iPad as a supported destination in Xcode won't change that app's availability on iPad"
(source S6). See risk R4.

---

## 3. What is there today

### 3.1 Targets and settings

One project, `App/Carpenter.xcodeproj`, in `Carpenter.xcworkspace` (`contents.xcworkspacedata`
names only that project). `Config/Branding.xcconfig` is the base configuration of the **project**
level Debug and Release (`project.pbxproj:602`, `:667`); it holds nothing about platforms or
orientation. One shared scheme, `Carpenter` (`xcshareddata/xcschemes/Carpenter.xcscheme`); its
archive action uses Release (`:99-102`).

| Target | Build settings block | Device family | Supported platforms | SDK |
|---|---|---|---|---|
| `Carpenter` (the app) | Debug `:502-550`, Release `:551-599` | `"1,2,7"` (`:546`, `:595`) | `"iphoneos iphonesimulator macosx xros xrsimulator"` (`:539`, `:588`) | `auto` (`:537`, `:586`) |
| `CarpenterNotificationService` | Debug `:441-470`, Release `:471-501` | `"1,2"` (`:467`, `:497`) | not set | `iphoneos` (`:461`, `:491`) |
| `CarpenterTests` | Debug `:722-749`, Release `:750-777` | `"1,2,7"` (`:744`, `:772`) | same string as the app (`:738`, `:766`) | `auto` |
| `CarpenterUITests` | Debug `:778-804`, Release `:805-831` | `"1,2,7"` (`:799`, `:826`) | same string as the app (`:793`, `:820`) | `auto` |

Family numbers: 1 is iPhone, 2 is iPad (Xcode 27.2's `CoreBuildSystem.strings`, keys
`[TARGETED_DEVICE_FAMILY]-value-[1]` and `-[2]`). 7 is Apple Vision: from memory, not verified.

Orientation, app target only:

- `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad` = all four (`:527`, `:576`).
- `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone` = portrait, landscape left, landscape
  right (`:528`, `:577`).
- No `UISupportedInterfaceOrientations` and no `UIRequiresFullScreen` in `App/Carpenter/Info.plist`
  or anywhere in the project file (0 matches).

Mac Catalyst and "Designed for iPad":

- `SUPPORTS_MACCATALYST`, `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD` and
  `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD` are set nowhere in the project (0 matches each).
- Xcode 27.2's defaults, read from its spec files: the application product type sets
  `SUPPORTS_MACCATALYST = NO` (`DarwinProductTypes.xcspec:38`); the other two default to `YES`
  (`iOSDevice.xcspec:120-133`). Their own descriptions say they only "Show the Mac (Designed for
  iPhone) and Mac (Designed for iPad) destinations" and the Vision equivalent. They are about what
  Xcode lists, not about what the store offers (see R5).

Mac-only build settings on the app target, both configurations: `ENABLE_APP_SANDBOX = YES` (`:513`,
`:562`), `ENABLE_HARDENED_RUNTIME = YES` (`:514`, `:563`), `ENABLE_USER_SELECTED_FILES = readonly`
(`:516`, `:565`), `"LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]"` (`:531`, `:580`),
`MACOSX_DEPLOYMENT_TARGET = 26.5` (`:532`, `:581`, and on both test targets), `REGISTER_APP_GROUPS =
YES` (`:536`, `:585`; Xcode's description: "only applicable to platforms supporting unregistered app
groups"). Vision: `XROS_DEPLOYMENT_TARGET = 26.5` in six places (`:547 :596 :746 :774 :801 :828`).

The extension is embedded and depended on with `platformFilter = ios` (`:10`, `:424`), so the Mac
build already leaves it out.

Signing, all four targets: `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = <the Team ID>`. Versions:
`MARKETING_VERSION = 0.1.0`, `CURRENT_PROJECT_VERSION = 1` on the app and the extension, which match
each other.

### 3.2 The Mac-only entitlement entries: three, not two, and none reaches an iPhone signature

`App/Carpenter/Carpenter.entitlements` serves the iPhone build and the Mac build. Three of its keys
are for macOS only:

| Lines | Key | What Apple says |
|---|---|---|
| `:7-8` | `com.apple.developer.aps-environment` | "The environment for push notifications in macOS apps." Platform: macOS 10.14 (S2). The iPhone key is `aps-environment` on `:5-6`; its platform list has iOS and no macOS (S1). |
| `:21-22` | `com.apple.security.app-sandbox` | Platform: macOS 10.7 only (S4). |
| `:27-28` | `com.apple.security.network.client` | Platform: macOS 10.7 only (S5). |

The plan says two; the third is the Mac push key.

**Measured:** Xcode already leaves all three out of an iPhone signature. There is a signed Debug
device build from 2026-11-06 00:10 (Xcode 27.1) in
`~/Library/Developer/Xcode/DerivedData/Carpenter-cbxhfgypjiklpnewtxdjxxfdpiht/Build/`. The
entitlements file has not changed since 2026-09-27 (`git log`, last commit `74d18db`), so that build
was made from the file as it is now. Both the generated
`Intermediates.noindex/Carpenter.build/Debug-iphoneos/Carpenter.build/Outpost.app.xcent` and
`codesign -d --entitlements -` on `Products/Debug-iphoneos/Outpost.app` list exactly nine keys:
`application-identifier`, `aps-environment`, `com.apple.developer.icloud-container-identifiers`,
`com.apple.developer.icloud-services`, `com.apple.developer.sensitivecontentanalysis.client`,
`com.apple.developer.team-identifier`, `com.apple.security.application-groups`, `get-task-allow`,
`keychain-access-groups`. None of the three Mac keys is there. A Release archive has not been
measured; the archive in section 8 is where that gets checked.

For comparison, the one archive of this app on this machine
(`~/Library/Developer/Xcode/Archives/2026-08-17/Carpenter 8-17-26, 11.23 AM.xcarchive`) is a **Mac**
bundle (`Outpost.app/Contents`), and its signature carries all three Mac keys. That is what happens
when Archive is pressed with My Mac selected (R7).

So, can each go?

- **Path K:** all three stay. The Mac build needs them, and they do not reach the iPhone.
- **Path D:** all three go. Nothing would read them.

### 3.3 The empty share-access entry on the extension

`App/CarpenterNotificationService/CarpenterNotificationService.entitlements:9-10`:

```xml
	<key>com.apple.developer.icloud-extended-share-access</key>
	<array/>
```

Apple (S3): "An array of strings that represent the types of information an app can request about a
CloudKit share." Values: `InProcessShareOwnerParticipantInfo`, `InProcessOneTimeLinks`,
`InProcessShareAccessRequests`. iOS 26 and later. "Include only the strings that support your app's
features."

**Measured:** unlike the Mac keys, this one does reach the iPhone signature. The 2026-11-06 device
build's extension is signed with the key and an empty array. The extension's local profile allows
all three values, so it is not a signing fault; it is a claim of nothing.

It can go, on both paths. No Swift source uses one-time links or access requests (no match for
`oneTimeURL`, `CKShareAccessRequest`, `accessRequest`, `allowsAccessRequests` under
`Packages/Carpenter/Sources` or `App`). The app's own entitlements file has never had the key
(`git log -S`), so the app and the extension end up the same. Inferred, not verified: an empty array
and a missing key behave the same; Apple's page treats "don't add the entitlement" and "don't have
this value in the array" as one case for the owner-info value.

### 3.4 What else in the app target assumes a Mac or an iPad

Nothing assumes an iPad. There is no `userInterfaceIdiom` check anywhere in `App/` or
`Packages/Carpenter/Sources`, and the root layout chooses by platform, not by width:
`Packages/Carpenter/Sources/CarpenterUI/Screens/RootView.swift:586-592` is `#if os(macOS)` →
`desktop`, otherwise `phone`.

Mac branches in `App/Carpenter` (the app target's own folder):

| File | Lines | What the Mac branch does |
|---|---|---|
| `CarpenterMain.swift` | `:11-15`, `:40-42`, `:44-47` | `NSApplicationDelegateAdaptor`, window minimum and default size |
| `PushRegistration.swift` | `:28-32`, `:89`, `:128-152` | `NSApplication` push registration and a second `PushDelegate` |
| `HardwareName.swift` | `:19-25` | `hw.model` instead of `hw.machine` |
| `AppRootTypes.swift` | `:23-27`, `:31-34` | alternate icons off on the Mac |
| `AppRootView.swift` | `:18-22`, `:56-58`, `:420-432`, `:505-514`, `:523-525` | `NSApplication.didBecomeActiveNotification`, iOS-only blocks |
| `AppRootView+Device.swift` | `:37-41`, `:270-278` | the device name "Mac", and opening System Settings through `NSWorkspace` |
| `AppRootView+Opening.swift` | `:15-17`, `:52-54` | iOS-only blocks |
| `AppRootView+Tapping.swift` | `:11-15`, `:18-75` | iOS-only blocks |
| `AppRootView+Ready.swift` | `:208-210` | iOS-only block |
| `TapSwapper.swift` | `:1`, `:299` | whole file is iOS only |

Thirteen files in `App/Carpenter` also carry `#if canImport(UIKit)`. In most it wraps the import
alone; in `AppRootView+Lock.swift` it wraps `:7-50` and `:59-65`, and in
`AppRootView+Avatars.swift` there is a second one at `:151-155`.

On Path K none of this changes. On Path D all of it becomes code no build compiles (section 5.4).

Other things that assume the Mac build exists:

- `Scripts/check-all.sh:247` runs `build-macos build_for "platform=macOS"`.
- `.github/workflows/checks.yml:119-146` builds a matrix of iOS and macOS.
- `App/Carpenter/Assets.xcassets/AppIcon.appiconset/Contents.json` carries ten Mac icon sizes
  (already noted in `docs/inbox.md:490`).
- Docs that say the Mac builds and runs: `CLAUDE.md:5-6`, `docs/index.md:18`,
  `docs/after-testflight.md:100`, `docs/desktop-roadmap.md:47-50`, `docs/epics/desktop.md:69`,
  `docs/inbox.md:59-61`, `docs/testing.md:56-57`.

The test targets cannot build for the Mac today anyway:
`App/CarpenterTests/KeyboardExtensionPointTests.swift:3` imports UIKit with no guard. Inferred from
reading; not built.

In the package, `ReactionBar.swift:292-293, :327, :368, :382` choose a different layout at regular
width. After this step no iPhone reaches regular width in the app (portrait only). The Mac build
does. Leave it.

The package itself is untouched by this step: `Packages/Carpenter/Package.swift:13` stays
`platforms: [.iOS(.v26), .macOS(.v26)]`.

### 3.5 What an archive needs, and what this machine has

Measured today:

- One signing identity in the keychain, of type "Apple Development". No "Apple Distribution"
  identity.
- Xcode-managed profiles in `~/Library/Developer/Xcode/UserData/Provisioning Profiles`:
  "iOS Team Provisioning Profile: com.microgpt.carpenter" (created 2026-09-27, expires 2027-09-27),
  the same for `…carpenter.CarpenterNotificationService`, and a Mac development profile. The iPhone
  app profile grants `aps-environment`, `iCloud.com.microgpt.outpost`, the app group,
  `sensitivecontentanalysis.client` and a wildcard keychain group, which covers everything the app
  claims. **No App Store ("Team Store") profile exists for either bundle ID.** They exist for
  another app of the same team on this machine, with no local distribution identity, so this
  account has used Apple's cloud-managed distribution signing before (inferred).
- No App Store Connect API key file in `~/.appstoreconnect/private_keys`, `~/private_keys` or
  `~/.private_keys`.
- Whether Xcode is signed in to the team's Apple Account right now: not verified.
- Whether an App Store Connect app record exists for `com.microgpt.carpenter`: not known.

What Apple says:

- An archive is built "for the class of device you select" (S9). The scheme can still select My Mac
  on Path K.
- Validation: "select your archive and then click Validate App. Xcode will perform a limited,
  automated initial validation" (S9).
- "Xcode 13 or later will cloud sign any apps or software for distribution if you're using the Xcode
  Organizer archive and distribution workflow, and a local signing certificate is not found" (S10).
  So a missing local distribution certificate is not a blocker when the account's role allows it.
- "Before you upload your app to the App Store for the first time, create an app record … If you
  haven't done this already, Xcode asks you for the information it needs to create this record for
  you" (S9).

The archive itself is signed for development and needs nothing this machine lacks (inferred from the
profiles above). Validation and upload need Griff's account.

---

## 4. Core changes, the same on both paths

All in `App/Carpenter.xcodeproj/project.pbxproj` unless a file is named. The file indents with tabs,
four of them inside a `buildSettings` block.

**C1. Device family, six places.** Replace every

```
TARGETED_DEVICE_FAMILY = "1,2,7";
```

with

```
TARGETED_DEVICE_FAMILY = 1;
```

Six matches expected (`:546 :595 :744 :772 :799 :826`).

**C2. Device family on the extension, two places.** Replace every

```
TARGETED_DEVICE_FAMILY = "1,2";
```

with `TARGETED_DEVICE_FAMILY = 1;`. Two matches expected (`:467 :497`).

**C3. Vision out, six lines.** Delete every line

```
				XROS_DEPLOYMENT_TARGET = 26.5;
```

Six matches expected (`:547 :596 :746 :774 :801 :828`).

**C4. Supported platforms, six places.** Replace every

```
SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx xros xrsimulator";
```

with, on **Path K**:

```
SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
```

or, on **Path D**:

```
SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
```

Six matches expected (`:539 :588 :738 :766 :793 :820`).

**C5. No "Designed for iPad" destinations, app target, two places.** The string

```
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
```

occurs only in the app target's two configurations (`:540-541`, `:589-590`). Put these two lines
directly above it in both:

```
				SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
				SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO;
```

That keeps the block alphabetical: they land after `SUPPORTED_PLATFORMS`. Leave
`SUPPORTS_MACCATALYST` unset; it is already `NO` by default for an application.

**C6. Portrait only, app target, two places.** Delete both lines that begin

```
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad =
```

(`:527`, `:576`). Then replace both

```
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
```

with

```
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait;
```

(`:528`, `:577`). Do not add `UIRequiresFullScreen`: it is an iPad setting and the family no longer
has an iPad. The `_iPhone` key is kept, not the unsuffixed one, because it is the key the file
already uses and the one Xcode's target editor writes; all three keys exist in Xcode 27.2
(`CoreBuildSystem.xcspec:4498`, `:4617`, `:4627`).

**C7. The empty share-access entry.** In
`App/CarpenterNotificationService/CarpenterNotificationService.entitlements`, delete lines 9 and 10
(the `com.apple.developer.icloud-extended-share-access` key and its `<array/>`). Nothing else in
that file changes.

**C8. Two tests that try to break sentences 1 and 2.** Both folders are synchronized groups
(`project.pbxproj:108-117`), so a new file joins its target without a project edit.

`App/CarpenterTests/WhatTheBundleDeclaresTests.swift`, in the style of `BrandingTests.swift` (Swift
Testing, no comments). It reads the app's own bundle, which the tests are hosted in:

- `Bundle.main.object(forInfoDictionaryKey: "UIDeviceFamily") as? [Int] == [1]`
- `Bundle.main.object(forInfoDictionaryKey: "UISupportedInterfaceOrientations") as? [String] ==
  ["UIInterfaceOrientationPortrait"]`

Inferred, not verified: at run time the bundle folds the `~iphone` variant into the plain key, so
the plain key is the one to ask for. If that expectation fails, print
`Bundle.main.infoDictionary?.keys` once, see which key is present, and assert on that. This suite
runs in CI (`checks.yml:98-105` runs `-only-testing:CarpenterTests`).

`App/CarpenterUITests/TheAppStaysUprightTests.swift`, an `XCTestCase` on the main actor like the
other UI tests: launch with `["--site-shot", "rooms", "-theme.accent", "verdigris"]` (the launch
`ScreenCatalogueTests.swift:64` uses, which needs no account), set
`XCUIDevice.shared.orientation = .landscapeLeft`, wait for `app.windows.firstMatch`, assert its
frame is taller than it is wide, and set the orientation back to `.portrait`. This is the test that
does what a member does. It runs through `xcodebuild test`, which raises no access request.

Write both before C1-C6 and watch them fail, then make the changes.

---

## 5. Path D only: drop the Mac from the app target

Only with Griff's yes (section 1). In its own commits, after the Core commit builds.

**D1. Project file.**

- Replace every `SDKROOT = auto;` with `SDKROOT = iphoneos;` (six matches: `:537 :586 :736 :764 :791
  :818`).
- Delete every `MACOSX_DEPLOYMENT_TARGET = 26.5;` line (six: `:532 :581 :732 :760 :787 :814`).
- In the app target's two configurations delete: `ENABLE_APP_SANDBOX = YES;`,
  `ENABLE_HARDENED_RUNTIME = YES;`, `ENABLE_USER_SELECTED_FILES = readonly;`,
  `"LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]" = "@executable_path/../Frameworks";`,
  `REGISTER_APP_GROUPS = YES;` (two matches each).
- Leave the `[sdk=iphoneos*]` and `[sdk=iphonesimulator*]` conditions and `platformFilter = ios`
  alone. They are harmless and removing them is a separate tidy-up.

**D2. `App/Carpenter/Carpenter.entitlements`.** Delete lines 7-8
(`com.apple.developer.aps-environment`), 21-22 (`com.apple.security.app-sandbox`) and 27-28
(`com.apple.security.network.client`). Nine lines of keys remain: `aps-environment`, the two iCloud
keys, the sensitive-content key, the app group and the keychain group.

**D3. The checks that build for the Mac.**

- `Scripts/check-all.sh:247`: delete the line `run build-macos build_for "platform=macOS"`.
- `.github/workflows/checks.yml:119-146`: remove the `strategy` block, name the job `Build`, and
  pass `-destination "generic/platform=iOS Simulator"` directly. Keep the comment about signing
  (`:136-138`). If the repository has a required status check named "Build (macOS)", it has to be
  removed in GitHub's settings, which is Griff's; not verified whether one exists.
- A push that touches a workflow file needs the GitHub CLI's token (memory note
  "outpost-git-push-credential").

**D4. Dead branches, in a commit of their own.** Every row of the table in 3.4: keep the iOS branch,
delete the Mac branch and the directive lines, and unwrap the `#if canImport(UIKit)` guards in the
thirteen files, keeping what is inside them. `CarpenterMain.swift` keeps line 12 only out of `:11-15` and loses `:40-42` and `:44-47`;
`PushRegistration.swift` loses `:128-152` and the `#if os(iOS)` on `:89`. Read each file's warnings
after: a member that lost its only other user binds elsewhere without an error (CLAUDE.md, the
`sync()` trap).

**D5. Not part of this order, and Griff's:** on Path D the desktop layout in the package
(`RootView+Desktop.swift` and the other `os(macOS)` branches, 8 uses in 5 files) is compiled by
`swift test` and run by no app. Whether it stays for the desktop roadmap or goes is his call.

**D6. Docs on Path D.** `docs/decisions.md:160-161` changes only on Griff's word, as a new dated
line under the entry. Then the sentences listed in 3.4. Words changed inside a copy chunk put that
chunk back to `NEEDS HUMAN REVIEW`; never re-id or reword a marker.

---

## 6. Order of work

1. Write the two tests in C8; see them fail.
2. C1-C6 in one edit of the project file. C7.
3. Checks 7.1-7.5.
4. Commit, if committing is in your brief: one commit for C1-C6 and C8 ("Make the app iPhone only
   and portrait only"), one for C7 ("Drop the empty share-access entry from the extension").
5. Reinstall the new build on every rig simulator that has the app; a stale build on a simulator has
   been caught twice (CLAUDE.md, "The rig").
6. Archive and inspect (section 8.1, 8.2). Validation (8.3) waits for Griff.
7. Docs (section 10).
8. Path D, only with his yes.

---

## 7. Checks, in order

Use a derived-data folder of your own; another process uses the usual ones.

**7.1 Settings, without building.**

```bash
xcodebuild -workspace Carpenter.xcworkspace -scheme Carpenter -configuration Release -sdk iphoneos \
  -showBuildSettings 2>/dev/null | grep -E ' (TARGETED_DEVICE_FAMILY|SUPPORTED_PLATFORMS|SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD|SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD|SUPPORTS_MACCATALYST|INFOPLIST_KEY_UISupportedInterfaceOrientations[_A-Za-z]*) ='
```

Expect: family `1`; platforms as chosen in C4; both `SUPPORTS_…DESIGNED…` `NO`; Catalyst `NO`; one
orientation key, `_iPhone = UIInterfaceOrientationPortrait`.

```bash
xcodebuild -workspace Carpenter.xcworkspace -scheme Carpenter -showdestinations 2>/dev/null
```

Expect no iPad, no Vision and no "Designed for iPad/iPhone" line. On Path K a native "My Mac" line
stays. If a "Designed for" line is still listed, add the two C5 lines to the other three targets and
say so.

**7.2 The simulator build** (CLAUDE.md, third command, with `-derivedDataPath`). Then read the built
`Outpost.app/Info.plist`: `UIDeviceFamily` is `[1]`, `UISupportedInterfaceOrientations~iphone` is
`[UIInterfaceOrientationPortrait]`, there is no `UISupportedInterfaceOrientations~ipad`. The
extension's `Info.plist` has `UIDeviceFamily` `[1]`.

**7.3 The app suite** (CLAUDE.md, fourth command). `WhatTheBundleDeclaresTests` passes with the rest.

**7.4 The turning test.**

```bash
xcodebuild test -workspace Carpenter.xcworkspace -scheme Carpenter \
  -destination 'platform=iOS Simulator,id=5A43F953-128D-4FE6-9135-0D26520E02B6' \
  -only-testing:CarpenterUITests/TheAppStaysUprightTests
```

**7.5 The rest.** `./Scripts/lint-branding.sh`, `python3 Scripts/copy-review.py check`, and before
committing `cd Packages/Carpenter && swift test`. On Path K also the Mac build exactly as
`check-all.sh:167-170` runs it (`-destination "platform=macOS" CODE_SIGNING_ALLOWED=NO -quiet`). On
Path D that command must now fail to find a destination, and `Scripts/check-all.sh` must run clean
without it.

---

## 8. Archive and validate once

**8.1 Archive.** `OUT` is a folder outside the repository.

```bash
xcodebuild archive -workspace Carpenter.xcworkspace -scheme Carpenter -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$OUT/Outpost.xcarchive" -derivedDataPath "$OUT/dd"
```

No `-allowProvisioningUpdates` on this call: the local development profiles should be enough
(3.5), and that flag lets xcodebuild "create and update profiles, app IDs, and certificates" on
Griff's developer account (`xcodebuild -help`). If the archive fails for want of a profile, stop and
report the error text; do not add the flag without his yes.

**8.2 Read the archive.** This is where sentence 3 is checked on a Release build.

```bash
APP="$OUT/Outpost.xcarchive/Products/Applications/Outpost.app"
codesign -d --entitlements - "$APP"
codesign -d --entitlements - "$APP/PlugIns/CarpenterNotificationService.appex"
plutil -p "$APP/Info.plist" | grep -A5 -E 'UIDeviceFamily|UISupportedInterfaceOrientations|CFBundleSupportedPlatforms'
plutil -p "$APP/PlugIns/CarpenterNotificationService.appex/Info.plist" | grep -A3 UIDeviceFamily
```

Expect: `$APP` has no `Contents` folder (an iPhone bundle). The app's keys are the nine listed in
3.2 and no `com.apple.security.app-sandbox`, `com.apple.security.network.client` or
`com.apple.developer.aps-environment`. The extension has no
`com.apple.developer.icloud-extended-share-access`. `CFBundleSupportedPlatforms` is `iPhoneOS`.
`get-task-allow` is expected at this stage; the archive is signed for development and export
re-signs it. Record the `aps-environment` value you see (R2).

**8.3 Validate.** Needs Griff's account, so it is his unless he says otherwise (section 9, G3).

- In Xcode: Window → Organizer → the archive → Validate App (S9).
- From the command line, only with his yes: an export options file with `method` = `validation`,
  `teamID` = `<the Team ID>`, `signingStyle` = `automatic`, passed to
  `xcodebuild -exportArchive -archivePath … -exportOptionsPlist … -exportPath … -allowProvisioningUpdates`.
  `validation` is in the list of methods `xcodebuild -help` prints on this machine (Xcode 27.2). It
  has not been run here. Never type a password, an app-specific password or an API key into a
  command.

Write down every message validation returns, word for word.

---

## 9. Risks

- **R1. Path D reverses a RULED entry.** Section 1.
- **R2. The Release push environment against a development profile.** `Config/Branding.xcconfig:10`
  sets `APS_ENVIRONMENT[config=Release] = production`, so a Release archive asks for
  `aps-environment = production` while the development profile it is signed with grants
  `development`. A signed Release device build has never been made (only `Debug-iphoneos` exists in
  derived data); `docs/pre-testflight.md:466-470` says the override was checked through
  `-showBuildSettings` only. Whether Xcode refuses the mismatch, rewrites it or lets it through: not
  verified, and a search found no clear answer. If the archive fails naming `aps-environment`, the
  cause is that line. Apple's engineer on the forums: "for `aps-environment` a distribution allowlist
  always contains `production`" (S11), and Apple's page says Xcode sets the value from the profile
  (S1), so the exported build should say `production` without the override. Removing the line undoes
  an item the doc marks Done, so take it to Griff with this paragraph (G6).
- **R3. The app icons have an alpha channel.** All 27 iPhone icon files (`AppIcon` and 26
  alternates, each `ios.png`, 1024 square) report `hasAlpha: yes` in `sips`, because
  `Scripts/render-icon.swift:15-18` always draws into a bitmap with alpha. App Store Connect has
  refused icons for this: "The App Store Icon in the asset catalog … can't be transparent nor contain
  an alpha channel" (S12, ITMS-90717). Against that, measured in the 2026-11-06 device build: the
  compiled catalogue marks the 1024 icon `Opaque = true` and the loose `AppIcon60x60@2x.png` has no
  alpha. So it will probably pass; not verified. If validation returns ITMS-90717, the fix is in the
  renderer and the 27 files, as its own work.
- **R4. iPad.** An iPhone-only app can still be downloaded on iPad and runs "in compatibility mode"
  (S6), guideline 2.4.1 says "iPhone apps should run on iPad whenever possible" (S8), and Apple
  says "Don't submit for review without testing your app's behavior in compatibility modes" (S6).
  Nobody has run this app on an iPad and neither rig simulator is one. Whether the `~iphone`
  orientation list is honoured there: not verified. This matters for App Review, not for an internal
  TestFlight build.
- **R5. The Mac and Vision Pro are offered by the store unless switched off.** The two build
  settings in C5 only hide Xcode destinations. In App Store Connect, under Pricing and Availability,
  an iPhone app is available on Apple silicon Macs and on Apple Vision Pro until "Make this app
  available" and "Make this app available on Apple Vision Pro" are deselected; the Mac choice "also
  applies to tester groups … with TestFlight" (S7a, S7b). Only an Account Holder, Admin or App
  Manager can change it.
- **R6. A wide photo or clip cannot be turned.** The viewer draws its player inside the app's own
  screen (`Packages/Carpenter/Sources/CarpenterUI/Screens/Messaging/MediaViewerView.swift:127`), so
  after C6 it stays upright with the rest. As a member, I turn my phone to watch a wide clip and
  nothing turns. Making one screen an exception needs landscape left in the list and an app delegate
  that locks every other screen, which is a different design.
- **R7. Path K: Archive in Xcode with My Mac selected makes a Mac archive.** It happened on
  2026-08-17 (3.2). Use the command in 8.1, or select Any iOS Device first.
- **R8. Line numbers move.** Other agents are committing. Count matches before each replace.
- **R9. Xcode holding the project open.** If Xcode has the project open while the file is edited it
  normally reloads it; if it then saves an older copy the edits are lost. Check the diff after.
- **R10. The HIG.** The layout page does not forbid a locked orientation: "Even if your app is
  locked to a certain orientation … it's still important to ensure your interface resizes well"
  (S13). So portrait only is not a recorded departure. It is still a decision, and goes in
  `docs/decisions.md` (section 10).

---

## 10. Docs when done

- `docs/pre-testflight.md:118-120` (step 5): what was changed, what the archive's signature showed,
  what validation said or that it has not been run. `:40` says no build has been archived; correct it
  once one has, and note that the only earlier archive was a Mac one. `:471-473` says the App ID's
  container has never been exercised and every build has been unsigned or a simulator: the local
  profile of 2026-09-27 grants `iCloud.com.microgpt.outpost`, and a signed Debug device build exists
  from 2026-11-06. Say what was measured, no more. All three are inside copy chunks; changed words
  set the chunk to `NEEDS HUMAN REVIEW`.
- `docs/decisions.md`: one entry, "The tester build is iPhone only and portrait only", with its cost
  (R4, R5, R6). Mark it `RULED` only with Griff's own words; otherwise `PROPOSED`. New copy gets a
  marker pair with an id from `python3 Scripts/copy-review.py new-id`.
- `docs/open-questions.md`: R4 and R6 as questions for him, if he has not answered them.
- Path D: section 5, D6.

---

## 11. Only Griff can decide or supply

- **G1.** Keep the Mac window building (the 2026-09-13 ruling, Path K, the default here) or drop it
  from the app target (Path D). Recommendation: K for the first tester build; it costs nothing on
  the iPhone, since the Mac entries do not reach the iPhone signature.
- **G2.** Confirm the four sentences in section 2.
- **G3.** Validation runs under his developer account. Either he presses Validate App in the
  Organizer, or he says the command in 8.3 may run with `-allowProvisioningUpdates`. Xcode has to be
  signed in to the team; not verified that it is.
- **G4.** App Store Connect: whether an app record exists for `com.microgpt.carpenter`. The bundle
  ID (`project.pbxproj:534`, `:583`) carries the source name and cannot be changed once a build is
  uploaded under it; say now if it should be different. Then deselect the Mac and Vision Pro
  availability boxes (R5).
- **G5.** Portrait only everywhere, including the photo and clip viewer (R6)?
- **G6.** If the archive fails on `aps-environment` (R2): may `Config/Branding.xcconfig:10` go?
- **G7.** An iPad, or an iPad simulator he has granted, to run the app on once before App Review
  (R4). Not needed for internal testers.

---

## 12. Noticed, not this step

- The extension's built `Info.plist` has `CFBundleDisplayName` and `CFBundleName`
  "CarpenterNotificationService" (`project.pbxproj:450`, `:480`; measured in the 2026-11-06 build).
  A notification service extension's name is not shown to members as far as is known (not
  verified), but it is the source name in a shipped bundle.
- `App/Carpenter/Info.plist:29-30` asks for Focus status and
  `App/Carpenter/AppRootView+Privacy.swift:88, :100-102` reads it. The Communication Notifications
  capability was removed from both entitlements files on 2026-09-27 (`74d18db`). Whether Focus
  status still answers without it: not verified.
- `Packages/Carpenter/Sources/CarpenterCloudKit/CloudKitMailbox+Pairs.swift:90` compares a share
  owner's `userIdentity.userRecordID`. Apple's page for the share-access entitlement says that
  without `InProcessShareOwnerParticipantInfo` "the fields in the `CKUserIdentity` for the owner's
  contact info are all `nil`" (S3). Whether `userRecordID` counts as contact info on a phone: not
  verified. The app has never claimed that value, so C7 changes nothing here; it is one to watch on
  the two-phone run.
- `docs/app-store.md:481` says Griff saw a banner on a phone on 2026-09-09, and
  `docs/pre-testflight.md:40` says no build has run on a phone. One of them needs a qualifier.
- The local profiles still grant `com.apple.developer.usernotifications.communication` and a second
  container, `iCloud.com.microgpt.carpenter`. A profile may grant more than the app claims; the
  capability is still switched on for the App ID in the developer portal (inferred).

---

## 13. Sources

Web pages were read through a fetch tool that returns extracts; quotations are as it returned them.

- S1 `aps-environment`: https://developer.apple.com/tutorials/data/documentation/bundleresources/entitlements/aps-environment.json
- S2 `com.apple.developer.aps-environment`: https://developer.apple.com/tutorials/data/documentation/bundleresources/entitlements/com.apple.developer.aps-environment.json
- S3 `com.apple.developer.icloud-extended-share-access`: https://developer.apple.com/tutorials/data/documentation/bundleresources/entitlements/com.apple.developer.icloud-extended-share-access.json
- S4 `com.apple.security.app-sandbox`: https://developer.apple.com/tutorials/data/documentation/bundleresources/entitlements/com.apple.security.app-sandbox.json
- S5 `com.apple.security.network.client`: https://developer.apple.com/tutorials/data/documentation/bundleresources/entitlements/com.apple.security.network.client.json
- S6 App Review Help, test compatible devices: https://developer.apple.com/help/app-review/before-submitting-for-review/test-compatible-devices
- S7a iPhone apps on Apple silicon Macs: https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-macs-with-apple-silicon
- S7b iPhone apps on Apple Vision Pro: https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-apple-vision-pro
- S8 App Review Guidelines, 2.4.1: https://developer.apple.com/app-store/review/guidelines/
- S9 Distributing your app for beta testing and releases: https://developer.apple.com/tutorials/data/documentation/xcode/distributing-your-app-for-beta-testing-and-releases.json
- S10 Cloud-managed certificates: https://developer.apple.com/help/account/certificates/cloud-managed-certificates
- S11 Apple Developer Forums, the distribution allowlist for `aps-environment`: https://developer.apple.com/forums/thread/703422
- S12 Apple Developer Forums, ITMS-90717 (developers' reports, not Apple documentation): https://developer.apple.com/forums/thread/86829 and https://developer.apple.com/forums/thread/795411
- S13 Human Interface Guidelines, Layout: https://developer.apple.com/tutorials/data/design/human-interface-guidelines/layout.json

Local, Xcode 27.2 (build 27B52), under
`/Applications/Xcode.app/Contents/SharedFrameworks/SwiftBuild.framework/Versions/A/PlugIns/SWBBuildService.bundle/Contents/`:
`Frameworks/SWBCore.framework/Versions/A/Resources/CoreBuildSystem.xcspec` and `.strings`;
`PlugIns/SWBApplePlatformPlugin.bundle/Contents/Frameworks/SWBApplePlatform.framework/Versions/A/Resources/iOSDevice.xcspec`
and `DarwinProductTypes.xcspec`; and `xcodebuild -help`.

<!-- COPY END 71a6bc9d -->
