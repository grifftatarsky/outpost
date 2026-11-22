<!-- COPY BEGIN 54917ea3 [NEEDS HUMAN REVIEW] -->

# The lock asks the phone first: design

> **A working design, written by agents on 2026-11-10 and 2026-11-11 and kept so the work need not be
> done again.** Nothing in it is a ruling. Where it names a file under `scratchpad/`, that was a
> working file and was not kept. Line numbers are from the commit it names and will drift.
> What is waiting on Griff is in [the Part B plan](../part-b-plan.md).

Written 2026-11-10 at commit `fe9ec3e` (branch `overnight-2026-10-31`). The lock's source files are
unchanged since `9af603a`, the commit the two research files were read at (`git diff --stat 9af603a
HEAD` over them is empty). Nothing was built or run for this design. Every statement about a real
iPhone is **not verified** unless it carries an Apple URL, and then it is what Apple's page says,
not what a phone did.

Griff's words this design answers, 2026-11-10: "How can you get Secure Enclave then. Does that share
info? It sounds like the two factors via face id and phone passcode is the move; a thief who knows
the passcode...you've got big problems and our app is the least of it. Can't account for peak stupid
ya know."

Short names for paths, relative to `/Users/grifftatarsky/projects/outpost`:

- `Vault.swift` = `Packages/Carpenter/Sources/CarpenterKit/Crypto/Vault.swift`
- `AppLock.swift` = `Packages/Carpenter/Sources/CarpenterKit/Crypto/AppLock.swift`
- `SE.swift` = `Packages/Carpenter/Sources/CarpenterKeychain/SecureEnclaveKeys.swift`
- `Fake.swift` = `Packages/Carpenter/Sources/CarpenterKitTesting/FakeHardwareKeys.swift`
- `Controller.swift` = `Packages/Carpenter/Sources/CarpenterUI/Screens/Safety/AppLockController.swift`
- `Views.swift` = `Packages/Carpenter/Sources/CarpenterUI/Screens/Safety/AppLockViews.swift`
- `OnDisk.swift` = `App/Carpenter/OnDiskStorage.swift`
- `Root.swift`, `Root+Lock.swift`, `Root+Device.swift`, `Root+Opening.swift` = `App/Carpenter/AppRootView.swift`,
  `App/Carpenter/AppRootView+Lock.swift` and so on
- `SystemKeychainStore.swift` = `Packages/Carpenter/Sources/CarpenterKeychain/SystemKeychainStore.swift`
- `NSE.swift` = `App/CarpenterNotificationService/NotificationService.swift`
- `HostedTest.swift` = `App/CarpenterTests/TheVaultOnTheRealKeychainTests.swift`
- `RigChecks.swift` = `App/CarpenterUITests/RigChecks.swift`
- `Identity.swift` = `Packages/Carpenter/Sources/CarpenterKit/Crypto/Identity.swift`
- `AppSession+Deathmark.swift`, `AppSession+Sync.swift` = `Packages/Carpenter/Sources/CarpenterApp/Session/…`
- `DeviceSecuritySettingsView.swift` = `Packages/Carpenter/Sources/CarpenterUI/Screens/You/Settings/…`
- `CopyShots.swift` = `Packages/Carpenter/Sources/CarpenterUI/Screens/SiteShots/CopyShots.swift`
- test suites named without a path are in `Packages/Carpenter/Tests/CarpenterKitTests/`
- "the research file" = `lock-research-code.md` beside this file; "the Apple research file" =
  `lock-research-apple.md`. A fact taken from one of them and not reread says so.

Words used below: **the sheet** is the Face ID or passcode sheet iOS draws. **The phone's check** is
the Secure Enclave deciding that Face ID or the phone's passcode passed. **The code** is the app's
own 4 to 6 digits (or passphrase). **Face ID alone** is the existing opt-in where a face opens the
app with no code (`Views.swift:343-347, 510-523`).

---

## 0. The design in one paragraph

The hardware key behind the code gets one more flag, `.userPresence`, so the Secure Enclave will not
use it until Face ID or the phone's passcode has passed. The lock screen asks for that check once,
as it comes up, and keeps the result for that one visit; the code is then tried against it with no
further sheet. A check that does not pass is never a wrong code. Wrapping a vault key stops calling
the enclave at all, which is what keeps every flow at one sheet. The stored format does not change.

---

## 1. What it must guarantee

For Griff to confirm before any code. The first tests try to break exactly these.

1. **No check, no guess.** With the lock on, no code is tried, right or wrong, until this phone's
   Secure Enclave has passed Face ID or the phone's passcode. Before that the app holds nothing a
   code can be tested against, on the phone or off it.
2. **A check that does not pass is not a wrong code.** A cancelled sheet, a failed face, a phone
   with no passcode: none of them counts a try, starts a wait, or sets off *Erase everything*.
3. **The phone's passcode alone never opens the app.** It only earns the right to try the code.
   A face alone opens the app only if the member turned *Face ID alone* on.
4. **Turning the lock on seals nothing until the new lock has opened once**, through the phone's
   check and the code just typed. If that fails the phone is exactly as it was.
5. **The recovery key still opens the app on this phone with no check from the phone**, so a member
   who turns the phone's passcode off is not shut out.

**Who it stops.** Somebody holding the unlocked phone who has neither the phone's passcode nor the
member's face:

- with the ordinary app: they see the sheet, cannot pass it, and never reach a try. They also can no
  longer use up tries, start a wait or set off *Erase everything* by typing junk, which today
  anybody holding the phone can do (`Controller.swift:159-186` counts before anything is checked).
- with a modified app on a jailbroken phone: today one enclave call gives them the bytes every guess
  is tested against, and the rest is PBKDF2 on any machine (`Vault.swift:192-203`; measured at
  0.067 s a guess on an M1 Mac, `docs/open-questions.md:187-205`). After this change the enclave
  refuses that one call. Apple says access rules on keychain items are evaluated inside the Secure
  Enclave and the item is released only when they are met
  (https://support.apple.com/guide/security/keychain-data-protection-secb0694df1a/web), and that the
  Secure Enclave is designed to hold when the main processor's kernel is compromised
  (https://support.apple.com/guide/security/secure-enclave-sec59b0b31ff/web). That it holds on a
  jailbroken phone is **inferred** from those two pages, not tested.
- with a copy of the phone's files and no phone: already stopped, because each wrapping needs this
  phone's enclave key.

**What it does not stop.** Plainly:

- **Somebody who knows the phone's passcode.** Ruled out of scope by Griff on 2026-11-10. They pass
  the check, and what is left between them and the app is the code and the app's own count, which a
  modified app skips. They can also enrol their own face; that kills *Face ID alone* (the key is
  tied to the faces enrolled when it was made) and does nothing for them at the code.
- **Somebody who can hold the phone up to the member's face.** They pass the check. They still need
  the code, unless the member turned *Face ID alone* on, in which case the face opens the app. That
  is Griff's own objection to biometrics, recorded at `docs/decisions.md:4376-4395`.
- **Code already running as the app at the moment the member unlocks.** It can keep what the enclave
  returned and guess the code anywhere, or simply read what the app reads. Nothing in an app can
  stop that.
- **Somebody who can read the memory of an app still running behind its lock screen.** When the lock
  comes up in a running app the vault key is dropped (`Controller.swift:88-91`) but the session keeps
  the identity, the device key and the room keys it loaded until the process ends (research file,
  section 3.6). The doc states the cost as "from an unlock until the lock screen next comes up";
  Griff's words accepting it were "until the app is closed or the phone is locked"
  (`docs/open-questions.md:183-186`). The code matches his words, not the doc's sentence. This
  change does not touch it. It goes to him as a question (section 10).
- Notifications, and the parts left in the clear (costs 1 and 5 of the open question), are as they
  were.

---

## 2. The change

### 2.1 Which key gets which rule

All three keys stay `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Only the code's key changes.

| Wrapping | Flags today (`SE.swift:19-20`) | Flags after | What the enclave wants before it will use the key |
|---|---|---|---|
| code | `[.privateKeyUsage]` | `[.privateKeyUsage, .userPresence]` | Face ID, or the phone's passcode |
| Face ID alone | `[.privateKeyUsage, .biometryCurrentSet]` | the same | a face that was enrolled when the key was made; no passcode fallback |
| recovery | `[.privateKeyUsage]` | the same | an unlocked phone |

- `userPresence` is biometry or passcode, does not need biometry to be enrolled, survives Face ID
  being re-enrolled, and is the same as `biometryAny` + `or` + `devicePasscode`
  (https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/userpresence).
- `biometryCurrentSet` needs Face ID enrolled and the item is invalidated when the member re-enrols
  (https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/biometrycurrentset).
  It must stay on the *Face ID alone* key: with `userPresence` there, the phone's passcode alone
  would open the app.
- The recovery key's hardware key gets no check on purpose. The recovery secret is 32 bytes derived
  from the identity's seeds (`Identity.swift:166-173`), so there is nothing to guess, and a key with
  no check keeps working if the phone's passcode is turned off (section 3).
- Not `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`: Apple deletes items in that class when the
  passcode is removed
  (https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility), and
  the member would lose the code's key for good instead of until the passcode is back.

In code the two-way `requiringBiometrics: Bool` (`Vault.swift:30`) becomes a three-way rule chosen
from the wrapping's purpose at `Vault.swift:169`. Suggested shape, names open:

```swift
public enum HardwareKeyRule: Sendable { case unlockedPhone, ownerPresent, enrolledFaces }

public protocol HardwareKeys: Sendable {
    func make(_ id: HardwareKeyID, opensFor rule: HardwareKeyRule) async throws -> Data
    func agree(_ id: HardwareKeyID, with publicKey: Data, reason: String) async throws -> Data
    func remove(_ id: HardwareKeyID) async throws
}
```

`publicKey(of:)` leaves the protocol: one test calls it and nothing in the app does
(`OutpostsOwnLockSealsThisPhoneTests.swift:140`).

### 2.2 Wrapping stops calling the enclave

Today every wrap makes a hardware key and then asks the enclave for a key agreement with a
throwaway public key (`Vault.swift:168-173`). With a rule on the code's key that call would raise a
sheet at every wrap: turning the lock on, changing the code, turning *Face ID alone* on.

A key agreement gives the same bytes from either side. `make` already returns the hardware key's
public half (`SE.swift:40-43`, discarded at `Vault.swift:169`). So `wrap` keeps the throwaway
**private** key for one line, agrees with the hardware key's **public** key in CryptoKit, and never
calls the enclave. What is stored is unchanged: the throwaway key's public half, the salt, the
sealed bytes (`Vault.swift:176`). Opening is unchanged: the enclave agrees with that stored public
half (`Vault.swift:196`).

This is what makes the sheet counts in 2.5 exact. The other way to get one
sheet for two keys is to pass one `LAContext` to both, which Apple documents
(https://developer.apple.com/documentation/security/ksecuseauthenticationcontext) but which nobody
has watched on this app's keys; this design does not depend on it.

It leans on one thing nobody has checked: that `SecKeyCopyKeyExchangeResult` with
`.ecdhKeyExchangeStandard` (`SE.swift:70-71`) returns the same 32 bytes CryptoKit's
`sharedSecretFromKeyAgreement` does. Apple's page for that algorithm has no text at all
(https://developer.apple.com/documentation/security/seckeyalgorithm/ecdhkeyexchangestandard).
**Not verified.** It is checked on the iPhone before anything else (section 6.4, step 2), and
guarantee 4 means a mismatch shows as "the lock could not be turned on", with nothing sealed. If
they differ, the way out is CryptoKit's own `SecureEnclave.P256.KeyAgreement.PrivateKey`, which takes
the same `SecAccessControl` and returns CryptoKit's `SharedSecret`
(https://developer.apple.com/documentation/cryptokit/secureenclave/p256/keyagreement/privatekey).

### 2.3 The check and the code become two steps

Today `Vault.open` does the enclave call, the key stretch and the opening in one go
(`Vault.swift:119-123, 179-203`), every failure reads as a wrong code (`Vault.swift:292-296`,
`SE.swift:69-72`, the `try?` at `Controller.swift:175`), and the try is counted first
(`Controller.swift:159-171`). Split it:

1. **Ask the phone.** One enclave agreement on the code's key, with the reason text. Returns a small
   value holding the agreement (suggested: `PassedCheck`), or throws. Never counted.
2. **Try the code.** Pure arithmetic on that value: PBKDF2, HKDF, open the wrapping. Returns right
   or wrong. No enclave, no sheet.

The controller's `check` (`Controller.swift:154-201`) becomes, in order:

1. If a wait is running, say so and stop. No sheet during a wait.
2. Get a passed check: the one already held for this visit, or the one in flight, or ask now. If it
   does not pass, show why (2.6) and stop. Nothing is counted or saved.
3. Count the try and save it before the code is tested, as today (`Controller.swift:159-171`).
4. Try the code against the passed check. Right, wrong, tries left, wait, erase: all as today.

The controller holds the passed check as main-actor state and drops it synchronously when the vault
opens, when the lock comes up (`lockNow`, `Controller.swift:88-91`), and when the app goes to the
background. The check in flight is held as a `Task`, so a code typed while the sheet is still up
waits for that sheet and does not raise a second one (the reentrancy trap in `CLAUDE.md`).

`VaultKeeper.opening` stops turning `HardwareKeyError.refused` into `false`
(`Vault.swift:294-296`). `HardwareKeyError` gains `noPasscode`. `SE.swift:69-72` reads the `CFError`
it is given and maps it; which domain and code each case produces on a phone is **not verified**,
so the mapping is: the phone has no passcode → `noPasscode`; key not found → `noSuchKey`; phone
locked → `locked`; anything else → `refused`. Each failure is logged with its domain and code so
the iPhone run can read them (`CarpenterKeychain` already logs through `Diagnostics`,
`SystemKeychainStore.swift:63`).

### 2.4 When the sheet comes up

- **Lock screen, *Face ID alone* off.** The sheet comes up by itself as the lock screen appears,
  the way Face ID is tried today (`Views.swift:103-108`). The member looks at the phone while
  reaching for the pad, then types the code. After the last digit there is only the key stretch.
- **Lock screen, *Face ID alone* on.** As today: one Face ID sheet as the lock screen appears; a
  pass opens the app. If it does not pass, the pad is there, and the sheet for the code's key comes
  up when the code is entered, not straight after the failed one. Face ID is tried again in that
  sheet, then the phone's passcode.
- **In Settings**, confirming the current code (`Views.swift:571-597` → `Controller.swift:143-147`):
  the sheet comes up after *Continue*.
- **Only while the scene is active.** A push can start the app in the background
  (`App/Carpenter/PushRegistration.swift:91-97`), and a sheet asked for then fails or lands on
  nothing. Today `sceneChanged` is only told about changes (`Root.swift:442-444`, no
  `initial: true`), so the controller does not know the first phase; it has to be told. Whether iOS
  refuses a sheet asked for during launch is **not verified**.

### 2.5 How many sheets

Exact, because the only enclave calls left are: the check on the code's key, the *Face ID alone*
unlock, and the recovery unlock (which never raises one).

| Flow | Sheets | Where |
|---|---|---|
| Turning the lock on | 1 | after *Lock the app*, before anything is sealed (guarantee 4) |
| Unlocking with the code | 1 | as the lock screen appears; then the code |
| A wrong code, then another try, same visit | 0 more | the passed check is still held |
| Unlocking with *Face ID alone* | 1 | as the lock screen appears; no code |
| *Face ID alone* on, and Face ID fails | 2 | the failed one, then one when the code is entered |
| A clean restart | the same as unlocking | |
| Changing the code | 1 | on confirming the current code; none for the new one |
| Turning *Face ID alone* on, a longer delay, *Erase everything*, turning the lock off | 1 each | on confirming the current code |
| The recovery key | 0 | |
| *Forgot the code?* | 0 | |

One more, once per install: the first time an app uses Face ID, iOS shows its own permission alert
with the app's `NSFaceIDUsageDescription`
(https://developer.apple.com/documentation/localauthentication/accessing-keychain-items-with-face-id-or-touch-id).
That will now happen when the lock is turned on. If the member says no there, `userPresence` should
fall to the phone's passcode; **not verified**.

A possible later saving, not in this build: with *Face ID alone* on, ask once on the code's key and
then try the Face ID key on the same `LAContext`, so a failed face costs one sheet, not two. It
depends on one context serving two keys with different rules. Decide after the iPhone shows it
(6.4, step 14).

### 2.6 Each flow, step by step

**Turning the lock on** (`Views.swift:437-455` → `Controller.swift:223-226, 266-318` →
`Vault.swift:239-245`):

1. Make the hardware keys and the wrappings. No enclave use, no sheet.
2. Ask the phone on the new code key (reason: "Turn on the lock"), then open the new wrapping with
   the code just typed and compare with the vault key just made.
3. If either fails: remove the new hardware keys, write nothing, tell the member why (cancelled or
   failed → the check line; no passcode → the passcode line; anything else → "The lock couldn't be
   saved. Try again."). Today the setup sheet only gets a yes or no back
   (`Views.swift:271, 445-447`); it needs the reason.
4. Only then write `vault.key`, save `app.lock`, open the gate and re-seal what the phone keeps, as
   today (`Controller.swift:279-303`).

**Unlocking with the code:** 2.3 and 2.4.

**Unlocking with *Face ID alone*:** as today (`Controller.swift:203-220`) with the simulator's extra
branch gone (2.7). A refusal stays silent and leaves the pad.

**A clean restart:** the lock screen is the same screen; the same steps. The vault is shut and the
session unloaded as today (`Root+Opening.swift:14-31`).

**Changing the code:** confirm the current code (sheet, check, count, code). Then the new code is
wrapped under a new `ownerPresent` key with no enclave call and the old key is retired
(`Vault.swift:139-145, 267-270`). The new wrapping is not opened to prove it: that would be a second
sheet, and the same arithmetic was proved on this phone when the lock was turned on.

**The recovery key:** unchanged (`Controller.swift:332-354`). No sheet, not counted, turns the lock
off.

**Turning the lock off:** confirm the current code (one sheet), then as today
(`Controller.swift:236-239, 308-312`).

### 2.7 The simulator's side door closes

`VaultKeeper.checksBiometricsItself` (`Vault.swift:215-225`) and the branch at
`Controller.swift:209` exist because the simulator's stand-in checks nothing. Once the stand-in
enforces the rule itself (section 6.1) both go, and a simulator takes the path a phone takes.

---

## 3. Phones that cannot pass the check the usual way

### 3.1 A phone with no passcode

Face ID cannot be used without a passcode (https://support.apple.com/en-us/102381), and the
passcode policy fails with `passcodeNotSet`
(https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthentication).
So nothing can satisfy the code's key. **Inferred**; whether making the key fails or only using it
does is **not verified**.

- The setup sheet asks first, with the question the settings screen already asks
  (`DeviceSecuritySettingsView.swift:80-84`, which becomes the one copy of it). No passcode: the
  button is off and the member reads **"Set a passcode on this phone first. The lock needs one."**
- If that question is ever wrong, step 2 of turning the lock on fails and nothing is sealed.

### 3.2 The passcode turned off after the lock is on

What happens to a `userPresence` key then is **not verified**: it may refuse until a passcode is
back, or be gone. Face ID cannot be used without a passcode (same Apple page as above), so *Face ID
alone* stops too (**inferred**). The design covers both outcomes without promising either:

- The lock screen asks the same question as it comes up and, with no passcode, raises no sheet. The
  member reads **"This phone has no passcode, so your code can't be checked. Set a passcode in
  Settings, or use your recovery key."** Typing a code changes nothing and counts nothing.
- The recovery key opens the app as it does today, because its hardware key has no check and a
  phone with no passcode counts as unlocked
  (https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility).
  That this holds on a phone is **inferred**.
- If the passcode comes back and the key still works, the code works again. If the key is gone, the
  member reads the general line, **"This phone couldn't check your code. Try again, or use your
  recovery key."**, and the recovery key or *Forgot the code?* is the way on.

### 3.3 Face ID re-enrolled

- The code's key still works (Apple, `userPresence` page above). The sheet takes the new face.
- The *Face ID alone* key is dead (Apple, `biometryCurrentSet` page above). Today the lock screen
  hides Face ID and says "Face ID changed on this phone, so enter your code."
  (`Views.swift:117-122`); entering the code stores the new state (`Controller.swift:196`) and Face
  ID is offered again, but nothing makes a new key, so it would be offered and never open (research
  file, 3.3; **inferred**, a simulator cannot show it).
- Fix, in this build: when the code opens the vault and the faces had changed, make a new *Face ID
  alone* wrapping for the faces now enrolled and retire the dead key. No sheet, because wrapping no
  longer calls the enclave. This is what "a face added since needs the code once"
  (`docs/decisions.md`, the app lock entry) already promises.

### 3.4 Face ID unavailable

Not enrolled, switched off for the app, locked out after five misses
(https://support.apple.com/en-us/102381), a mask, a phone with Touch ID: the sheet asks for the
phone's passcode (Apple's policy page above: biometry first when it can, the passcode otherwise),
then the member types the code. Two things typed. The *Face ID alone* row is not shown when the
phone has no usable biometry (`Controller.swift:16-25`).

### 3.5 The sheet is cancelled, or fails

The member reads **"Your phone checks it's you first. Then enter your code."** Nothing is counted.
Entering a code raises the sheet again.

---

## 4. The extension, and anything else that runs while locked

- **The notification extension** never opens the vault and has no way to (`NSE.swift:55-63`): with a
  vault present it marks storage shut and says only that something arrived. Unchanged; Griff
  accepted that cost. One thing is gained: today the code's hardware key asks for nothing, and it
  sits in the keychain group the extension shares (no group is named at `SE.swift:25-35`; the app's
  only group is the shared one, `App/Carpenter/Carpenter.entitlements:29-32`, and the extension
  lists the same one, `App/CarpenterNotificationService/CarpenterNotificationService.entitlements:19-22`),
  so the extension's process could run that key agreement (**inferred**). With the rule on, a
  process that cannot show a sheet cannot. **Inferred** from two forum reports in the Apple research
  file (its section 7); **not verified**.
- **A push that wakes the app** (`PushRegistration.swift:91-97`): the session is not loaded behind
  the lock and a round collects nothing (`AppSession+Sync.swift:14-17`). No sheet may be asked for
  here (2.4).
- **The Focus filter** (`App/Carpenter/RoomsFocusFilter.swift:37-66`) reads and writes its own
  store, which the vault does not seal. Unchanged, and already an open question of its own.
- **The cover.** A sheet may make the scene inactive, which raises the cover
  (`Controller.swift:93, 119`). At the lock screen that is invisible. In Settings and in the setup
  sheet the app would blank behind the sheet and come back. If a sheet ever sends the scene to
  *background* and the delay is *Right away*, coming back would lock the app again
  (`Controller.swift:125-133`) and loop. **Not verified** either way; it is the second thing to
  watch on the iPhone (6.4, step 5), and the fix if it happens is to not start the away clock while
  the app's own sheet is up.

---

## 5. No reader for the old arrangement

Nothing new is stored. `vault.key` keeps the same fields (`Vault.swift:36-70`) and `app.lock` is
untouched. The rule lives on the hardware key, which the app cannot read back. So there is nothing
for a reader to read, and none is written (the ruling at `docs/decisions.md:6471`).

- **No phone has a vault.** The lock has never run on hardware (`docs/open-questions.md`, "Not
  proven").
- **If a phone gets the present build first and the lock is turned on there**, its code key has no
  rule and the app cannot tell. It opens with the code alone and guarantee 1 does not hold on that
  phone until the lock is turned off and on again (changing the code also makes a new code key).
  Say so in the commit; write no code for it.
- **A development simulator with the lock on** will not open after this build: the stand-in's kept
  key changes form (section 6.1) and the old form is not read. Turn the lock off before installing,
  or use *Forgot the code?*, or erase the simulator. The rig's lock walk already ends by erasing
  through *Forgot the code?* (`RigChecks.swift:259-274`).

---

## 6. Tests

### 6.1 What the stand-ins must refuse

There are three (`Fake.swift`; `SimulatorHardwareKeys`, `OnDisk.swift:70-99`;
`KeysKeptInTheKeychain`, `HostedTest.swift:11-38`). Today none refuses anything on the code path.

**`FakeHardwareKeys` (package).** It models who is holding the phone and counts sheets.

- It keeps the rule each key was made with, and a test asserts the rule per purpose.
- A key with a rule is never used without a sheet in that same call. There is no way to get an
  agreement from it otherwise.
- A sheet with no reason text is refused (`unavailable`), whoever holds the phone. `open(with:)`
  passes `""` today (`Vault.swift:251`, `Controller.swift:175`), so the present code fails this at
  once, which is the point.
- Who holds the phone is set by the test: the owner (Face ID passes), the owner answering with the
  passcode, somebody who cancels, somebody whose check fails. Default: the owner.
- An `enrolledFaces` key is refused when the sheet was answered with the passcode, and refused for
  good once the faces change. Which error the real one gives for a dead key is not known, so the
  fake can give `noSuchKey` or `refused` and the controller must take both.
- With no passcode, every key with a rule throws `noPasscode`; a switch decides whether `make`
  throws too, since the real behaviour is not known.
- It looks for the key before it checks availability, the order the real one uses
  (`docs/testing.md:117-120` records the mismatch).
- It counts `sheets` beside `agreements`.

**`SimulatorHardwareKeys` (simulator build of the app).** It asks `LAContext` itself, with the
reason, before it agrees: the owner policy for `ownerPresent`, the biometry policy with no fallback
button for `enrolledFaces`, nothing for `unlockedPhone`. It keeps the rule, and for `enrolledFaces`
the biometry state hash, beside the key and refuses on a mismatch. No let-through when the
simulator cannot check: a simulator with no biometrics enrolled is then a phone with no passcode,
which is a state worth walking (3.1). It still protects nothing, and cannot show the enclave
refusing, the passcode half, or the counting; its job is the app's handling of yes, no and cancel.

**`KeysKeptInTheKeychain` (hosted test).** Stays a plain stand-in; that suite is about the real
keychain and real files. It picks the real enclave by `SecureEnclave.isAvailable`
(`HostedTest.swift:46-48`). People have seen that be true on a simulator (Apple research file, section 8),
and a `userPresence` key there would fail or raise a sheet nobody answers. Choose by
`#if targetEnvironment(simulator)`, as the app does (`OnDisk.swift:60`).

### 6.2 Package tests, written first

New suite, suggested name `TheCodeIsTriedOnlyAfterThePhonesCheckTests`, driving `Vault`,
`VaultKeeper` and `AppLockController` with the fake, in the harness
`TheLockScreenDrivesTheVaultTests.swift:23-70` already has.

Breaking guarantee 1:
- "Until the phone's check passes, the right code opens nothing and no code is tested": the holder
  cancels; `agreements == 0`; the vault is shut.
- "Somebody with the phone's files and a phone that refuses cannot tell a right code from a wrong
  one."
- "The code's key is made to ask for the owner, the recovery key's for an unlocked phone, and Face
  ID's for the enrolled faces."

Breaking guarantee 2:
- "A cancelled check counts no try": `failures == 0` after ten cancels; no wait.
- "With Erase after 1, a cancelled check and a failed check erase nothing."
- "A wrong code after a passed check counts, and the next try raises no second sheet":
  `sheets == 1` across a wrong then a right code.
- "A code typed while the sheet is still up waits for that sheet": `sheets == 1`.
- "During a wait no sheet is raised."

Breaking guarantee 3:
- "The phone's passcode passes the check and opens nothing by itself."
- "A sheet answered with the passcode does not open Face ID alone."

Breaking guarantee 4:
- "Turning the lock on raises one sheet", with and without *Face ID alone*.
- "If the check is refused while turning the lock on, nothing is sealed, no vault is kept, no
  hardware key is left behind and no lock is saved."
- "A phone with no passcode cannot turn the lock on, and nothing is sealed."

Breaking guarantee 5:
- "The recovery key opens with no sheet, and with no passcode on the phone."
- "With the passcode turned off after the lock is on, a code counts nothing and the recovery key
  opens", run for both outcomes (key refuses, key gone).

Sheet counts and the rest:
- "The lock coming up again asks again": unlock, lock, unlock: `sheets == 2`.
- "Changing the code raises one sheet, and only the new code opens."
- "Turning Face ID alone on raises one sheet; turning the lock off raises one."
- "After the faces change, Face ID alone opens nothing until the code is entered once, and then it
  opens again" (3.3).

Existing suites change where they call `open(with:)` or `make(_:requiringBiometrics:)`
(`OutpostsOwnLockSealsThisPhoneTests`, `TheLockSealsWhatThisPhoneKeepsTests`,
`TheLockScreenDrivesTheVaultTests`, and the `Biometrics` doubles at `AppLockTests.swift:142`,
`Views.swift:686`, `CopyShots.swift:274`). The test titled "Every code is worth a guess on the phone
itself and nowhere else" (`OutpostsOwnLockSealsThisPhoneTests.swift:37`) keeps passing and is still
only about a different enclave.

### 6.3 The simulator walk

Before anything is built, on one simulator: does
`xcrun devicectl device settings biometrics --device <udid> --enable` work on the rig's iOS 27.2, is
the owner policy then usable, and does `xcrun devicectl device simulate biometrics --device <udid>
--success` (or `--failure`) answer a waiting sheet. Both commands are in Xcode 27.2's help (read
2026-11-10); neither has been run. If the simulator cannot be driven, stop and ask Griff: the choice
is a stand-in that lets the code through, as today, with every sheet left to the iPhone.

Then, software keyboard on, one simulator, each step once and anything intermittent ten times:

1. Biometrics not enrolled: the setup sheet shows the passcode line and the button is off.
2. Enrol. Turn the lock on: one sheet, answered `--success`; the lock is on.
3. Home and back: the sheet at once; `--success`; a wrong code says so with no second sheet; the
   right code opens.
4. Home and back; cancel the sheet: the check line shows; with *Erase everything* at 1, nothing is
   erased; entering the code raises the sheet again; `--success`; it opens.
5. Stop the app and start it: as step 3, and the member's name is still there.
6. Change the code: one sheet on the current code, none on the new; the new code opens.
7. Turn *Face ID alone* on: one sheet. Home and back: `--success` opens with no pad;
   `--failure` leaves the pad and the code path.
8. Disable and enable biometrics (whether that changes the state hash on a simulator is **not
   verified**): the lock screen says Face ID changed; the code opens; Face ID opens again after.
9. The recovery key from the lock screen: no sheet; the lock is off.
10. Turn the lock on again, then off in Settings: one sheet; a restart opens with no lock.

`RigChecks.testANewMemberSavesTheKeyAndLocksTheApp` sets a code (`RigChecks.swift:197-208`) and
then meets the lock screen three times (`:216-233`, `:235-243`, `:250-262`). A UI test runs inside
the simulator and cannot call `devicectl`, so the script that runs it has to enrol biometrics first
and answer the sheets from the Mac. How that behaves is **not verified**.

### 6.4 What only an iPhone can show

Everything the Secure Enclave does. In order; each needs a person holding the phone.

1. Today's build, unchanged: does `SecKeyCopyKeyExchangeResult` work on a Secure Enclave key at
   all. `HostedTest.swift` run on the phone is that test (code key only, no sheets with today's
   flags).
2. The enclave's agreement equals CryptoKit's with the public key `make` returned (2.2 depends on
   it). A new hosted test, phone only.
3. A `[.privateKeyUsage, .userPresence]` key: making it raises no sheet; using it raises one; what
   the sheet says with the reason; the one-time Face ID permission alert.
4. The error's domain and code for: cancel; Face ID failing, then cancel; Face ID locked out; a
   wrong passcode, then cancel; the app sent away while the sheet is up.
5. The scene's phases during the Face ID sheet and during the passcode sheet (inactive or
   background), and whether a sheet asked for during launch is refused (2.4, section 4).
6. Face ID switched off for the app in Settings: does the sheet go to the passcode.
7. A phone with no passcode: can the key be made, and what comes back.
8. The passcode turned off with the lock on, then on again: is the code's key usable, stuck or
   gone; does the recovery key open; what happened to *Face ID alone*.
9. Face ID re-enrolled: the code's key works, the *Face ID alone* key does not, which error it
   gives, and 3.3's renewal works.
10. Two wrong phone passcodes typed into the app's sheet, then two at the lock screen: if the
    fourth brings the one-minute wait, the count is shared. Apple's table gives a one-minute wait
    at the fourth wrong passcode
    (https://support.apple.com/guide/security/passcodes-and-passwords-sec20230a10d/web). It spends
    Griff's own phone's tries, so only with his yes.
11. Stolen Device Protection on, away from a familiar place: is the passcode still offered.
12. How long 600,000 rounds take on the phone. The open question says not measured.
13. With the lock on, a push: the banner says only that something arrived.
14. One `LAContext` across the code's key and the *Face ID alone* key: one sheet or two (2.5).

Commands. None has been run. `<phone>` is the identifier from `xcrun devicectl list devices`.

```bash
xcodebuild test -workspace Carpenter.xcworkspace -scheme Carpenter \
  -destination 'platform=iOS,id=<phone>' \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  -only-testing:CarpenterTests/TheVaultOnTheRealKeychainTests
```

```bash
xcodebuild -workspace Carpenter.xcworkspace -scheme Carpenter \
  -destination 'platform=iOS,id=<phone>' -derivedDataPath /tmp/carpenter-phone-dd \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
xcrun devicectl device install app --device <phone> \
  /tmp/carpenter-phone-dd/Build/Products/Debug-iphoneos/Outpost.app
xcrun devicectl device process launch --device <phone> com.microgpt.carpenter
```

The `.app` path is **inferred** from the simulator path in `CLAUDE.md`. Whether the scheme's test
action builds for a device is **not verified**. The phone needs pairing, Trust, Developer Mode, and
to be unlocked (Apple research file, section 9).

**Before pointing it at Griff's phone:** the hosted test launches the whole app, under whatever
Apple Account the phone is signed into. Keep `-only-testing` on the vault suite. The walk by hand
onboards a member in that account's development iCloud. Griff decides which account the phone uses.

---

## 7. Decision 5: erasing after wrong codes when the app started behind the lock

**The gap** (`docs/pre-testflight.md:104-107`). Started behind the lock, nothing is loaded, so
`wipe()` skips the signed notice that tells the member's other devices to erase
(`Root+Device.swift:151-154`; making it needs the device key, the identity and the device list,
`AppSession+Deathmark.swift:22-33`). This phone and the member's iCloud are erased; the other
devices are not told. The setting's footer says "on every device" (`Views.swift:672`), and Griff's
ruling says everywhere (`docs/decisions.md`, the app lock entry). It is also the likely case when it
matters: a phone that was taken and whose app was not running. The whole cold-start erase has never
been run, on a simulator or in a test.

**Recommendation: keep a prepared notice that only the phone's check can open, and build it straight
after this change.** This change is what makes it safe:

- After this change a try is counted only once the phone's check has passed, so at the moment the
  count is reached the app is holding a passed check.
- While the app is open and *Erase everything* is on, it prepares the notice (the type already
  exists and is already kept outside the vault for the case where iCloud could not be reached,
  `AppSession+Deathmark.swift:5-14`, `Root+Device.swift:180-204`) and seals it under a key derived
  from the code key's agreement. That key is derived when the code's wrapping is made or opened,
  and a copy is kept inside the vault, so the notice can be refreshed whenever the app is open: at
  each unlock and each time the app leaves the foreground. Behind the lock only a passed check can
  derive it.
- Behind the lock, when the count is reached, the passed check opens the notice and it is posted
  before the erase. No extra sheet.

Who can use it: only somebody who passes Face ID or the phone's passcode on this phone, and that
person can already erase everything the same way when the app was running. Somebody holding only
the phone's files gets nothing, which was the objection to keeping a notice in the clear.

**What it costs.** One more kept item to keep fresh, and one limit Griff has to say yes to: a device
approved since this phone last had the app open is not on the notice, and is not erased by it.

**Until it is built** the footer overstates. If it will not be built before the tester build, the
footer has to change: "…everything this phone keeps is erased, and your iCloud. Your other devices
are erased too if the app was open."

---

## 8. Copy, files, build order

### 8.1 Copy

Every string sits in a marker pair. Changing words inside a pair leaves it at `NEEDS HUMAN REVIEW`
(all of these already are). New strings outside an existing pair take a new id from
`python3 Scripts/copy-review.py new-id`. Proposed words, for Griff's team to review:

| Where | Marker | Now | Proposed |
|---|---|---|---|
| Setup header, `Views.swift:313` | `66758400` | "Ask for a code of its own whenever the app opens. Your phone's passcode never opens it." | "When the app opens, your phone checks it's you, then the app asks for a code of its own. Your phone's passcode alone never opens it." |
| Setup, new line when there is no passcode | `66758400` | none | "Set a passcode on this phone first. The lock needs one." |
| Setup toggle, `Views.swift:345` | `66758400` | "Also unlock with \(name)" | "Skip the code with \(name)" |
| Settings header, `Views.swift:486` | `77e5e417` | "When it's on, the app asks for its own code, or Face ID, when it opens, and covers itself in the app switcher." | "When it's on, your phone checks it's you and the app asks for its own code when it opens. The app covers itself in the app switcher." |
| Settings toggle, `Views.swift:521` | `77e5e417` | "Unlock with \(name)" | "Skip the code with \(name)" |
| Problem lines, `Views.swift:177-196` | `c45e581f` | none | "Your phone checks it's you first. Then enter your code." |
| | `c45e581f` | none | "This phone has no passcode, so your code can't be checked. Set a passcode in Settings, or use your recovery key." |
| | `c45e581f` | none | "This phone couldn't check your code. Try again, or use your recovery key." |
| Sheet reason at the lock screen, `Controller.swift:205-207` | `d35bb503` | "Unlock the app" | unchanged; used for both keys |
| Sheet reason, turning the lock on | new id | none | "Turn on the lock" |
| Sheet reason, confirming in Settings | new id | none | "Change the lock" |
| `App/Carpenter/Info.plist:33-34` | `b6501cb1` | "Face ID opens the app when you have locked it, instead of typing your code." | "When you have locked the app, Face ID comes before your code, or in place of it if you choose that." |
| Erase footer, `Views.swift:672` | `320ac2d4` | "…on every device and in iCloud…" | unchanged if section 7 is built; otherwise as in section 7 |

The sheet already names the app, so a reason need not (Apple, the keychain article above).
"The lock guards the app's screens." in the setup footer (`Views.swift:361`) has been out of date
since the lock began sealing; it belongs to item 12 of `docs/pre-testflight.md:134`, not to this
change.

Docs, all copy, all in marker pairs:

- `docs/decisions.md`: a new entry, **RULED 2026-11-10** with Griff's words above, and under it,
  marked **PROPOSED**, what he has not seen: the sheet comes up with the lock screen, a refused
  check is not a wrong code, wrapping by the public key, the proof when the lock is turned on, *Face
  ID alone* staying. The app lock entry's bullet "It guards the screens; it does not encrypt"
  (`:4319-4324`) and the two passages the research file lists (`:4421-4447`, `:4492-4495`) are
  already wrong since `6579ed9`.
- `docs/open-questions.md`, `5d82a14a` (`:153-217`): item 4 and the three-part recommendation are
  answered; "Each guess then costs one Secure Enclave operation" (`:190-191`) is not what the code
  does for that attacker (one enclave call serves every guess, `Vault.swift:192-203`) and goes; the
  new questions in section 10 come in.
- `docs/pre-testflight.md`: decisions 2 and 5 (`:99-107`), left-to-do 4 and 13 (`:115-117, :137`).
  The file has uncommitted changes from other work; edit, do not replace.
- `docs/crypto-brief.md`, "The app lock" (`:1449-1484`) describes the lock before it sealed
  anything, and `:1547-1550` says the vault is not connected. Rewrite as what each key is derived
  from and bound to.
- `docs/testing.md` (`c835132c`, `:113-125`): the fake's new rules, and how Face ID is driven on a
  simulator. `docs/simulator-rig.md`: the Secure Enclave row (`:155`), and the phone.
- `docs/roadmap.md:191`, `docs/epics/identity-and-devices.md:508`: the same stale sentence.

### 8.2 Files to touch

- `Vault.swift`: the rule; the protocol; `wrap` by public key; the two-step open; the proof in
  `VaultKeeper.make`; renewing the *Face ID alone* wrapping; `checksBiometricsItself` gone; errors
  no longer folded into `false`.
- `SE.swift`: flags per rule; the reason always passed; the `CFError` read, mapped and logged; no
  fallback button on the faces-only sheet.
- `Fake.swift`: section 6.1.
- `Controller.swift`: `check` reordered; the passed check and the one in flight; three new
  problems; whether the phone has a passcode, through the `Biometrics` seam; the first scene phase.
- `Views.swift`: the lock screen starts the check; the setup sheet shows why it failed and the
  no-passcode state; copy.
- `DeviceSecuritySettingsView.swift`: uses the one passcode question.
- `CopyShots.swift:274`, `AppLockTests.swift:142`: the `Biometrics` doubles.
- `OnDisk.swift`: the simulator stand-in (6.1); `LockVault.keeper` loses the flag.
- `Root.swift:442-444`, `Root+Lock.swift:118-135`: the first scene phase; the setup closure's result.
- `App/Carpenter/Info.plist`: the Face ID string.
- `HostedTest.swift`: stand-in chosen by target; a phone-only suite for 6.4 steps 2 to 4.
- `RigChecks.swift` and the script that runs it: enrol and answer the sheets.
- The new package suite, and the three existing ones.
- The docs in 8.1, and the string catalogue by extraction.

### 8.3 Build order

One thing at a time; each line is its own commit unless it says otherwise.

0. **Look first, no code.** On one simulator, the two `devicectl` commands (6.3). On the iPhone,
   today's hosted test (6.4, step 1). Both need Griff: the simulators are in use, and it is his
   phone.
1. **Its own commit, before the feature:** changing the code keeps *Lock* and *Erase everything*
   as they were. Today the setup sheet builds a new lock with the defaults (`Views.swift:443`,
   `AppLock.swift:57-67`), which looks like it turns *Erase everything* off without saying so
   (research file, 3.7; read, not run). Write the failing test first.
2. The fake (6.1) and the new package suite (6.2), failing.
3. `Vault.swift` and `SE.swift` until the suite passes. Filtered suite while working.
4. `Controller.swift`, `Views.swift`, the copy.
5. The app target: the simulator stand-in, the scene phase, `Info.plist`. Remove the derived data
   and read the warnings.
6. The whole package suite, the lint, the build, the hosted suite on a simulator
   (`Scripts/check-all.sh`).
7. The simulator walk (6.3), on a fresh install on every rig simulator.
8. The iPhone list (6.4). The feature is done when the five sentences in section 1 hold there.
9. Docs.
10. Section 7, after Griff's yes, as its own piece of work.

---

## 9. For Griff: how the app gets the Secure Enclave, and whether anything is shared

The Secure Enclave is a separate small computer inside the iPhone's chip. The app asks it to make a
key that never leaves it and says "only use this after Face ID or the phone's passcode"; iOS draws
the sheet, the chip does the checking, and the app is told yes or no. The nearest thing in your
world is a hardware key store behind a Spring service: the service can ask it to use a key and can
never read the key out.

Nothing is shared. There is no account and no network step in making or using these keys, Face ID
data never leaves the phone and is not available to apps or to Apple, and the app never sees the
face or the passcode (https://support.apple.com/en-us/102381,
https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave). The one
Secure Enclave feature that does contact Apple is App Attest
(https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity), and the
lock does not use it. Apple's pages name no network step; nobody has confirmed that with a packet
capture.

---

## 10. Decided here without Griff, and questions for him

Decided here, all **PROPOSED**:

- The sheet comes up with the lock screen, not after the code.
- A try is counted only after the phone's check passes. So somebody who cannot pass it cannot set
  off *Erase everything* either.
- Wrapping agrees with the hardware key's public half and never calls the enclave.
- The lock is on only after it has opened once.
- The recovery key's hardware key keeps no check.

Questions:

1. **The five sentences in section 1.** Confirm or change.
2. ***Face ID alone* stays?** It is the opt-in from his 2026-09-28 ruling, not the *Face ID only*
   mode he turned down, but with it on a face is the only factor. Recommendation: keep it, and
   start it **off** in the setup sheet (it starts on today, `Views.swift:279`; the ruling calls it
   demoted, with a warning that is not built).
3. **Does "no passphrase" take the passphrase option out?** It is in the build by his 2026-09-27
   ruling (`AppLock.swift:33-36`, `Views.swift:319-321`). Recommendation: leave it; this design
   adds no note about passphrases and does not touch the option.
4. **Decision 5** (section 7): build the sealed notice, and accept that a device approved since the
   app was last open is not named.
5. **What stays in memory behind the lock screen** (section 1). He accepted keys in memory "until
   the app is closed or the phone is locked"; the doc says "until the lock screen next comes up";
   the code does the first for everything the session loaded. Recommendation: make the doc say what
   the code does. Dropping the loaded session when the lock comes up is the stronger form, and its
   own piece of work with the reload time measured, if he wants it.
6. **The iPhone:** which Apple Account it uses for the run, and whether step 10 of 6.4 may spend
   wrong passcodes on it.

Noticed and parked, not designed:

- `AppLockController` still has a path for a lock with no vault (`Controller.swift:176-179,
  211-213`), reached only by tests, previews and site shots (`Root.swift:36` always passes a vault),
  and `AppLock.make` still stretches a verifier that is thrown away (`Views.swift:442-444`,
  `Controller.swift:277`). A candidate for the test-only cleanup at `docs/pre-testflight.md` item
  10.
- Apple's `applicationPassword` flag mixes an app-supplied password into a keychain item's key
  (https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility). Used
  on the code's key it might tie every guess to an enclave call on this phone. Whether the enclave
  counts those is not documented. Not explored.

---

## 11. Process notes

- Read-only on the repository. Nothing was built, run or tested. `xcrun devicectl help` was read
  for `device settings biometrics`, `device simulate biometrics`, `device install app` and
  `device process launch`; no device or simulator was touched.
- Apple pages were read on 2026-11-10 in their `.md` form (the URL with `.md` added), except the
  three `support.apple.com` pages, which were read as they are. The URLs above are the pages
  without `.md`.
- Facts taken from the two research files and not reread: the forum reports about extensions and
  simulators, the WWDC22 session, Stolen Device Protection, the phone set-up steps, and the code
  line numbers in `AppSession+DeviceSecurity.swift`, `AppSession+Identity.swift` and
  `AppSession+Erasing.swift`.

<!-- COPY END 54917ea3 -->
