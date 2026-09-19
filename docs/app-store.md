---
title: App Store
layout: default
nav_order: 13
---

# App Store Connect

Drafted for the **feature-complete TestFlight build**: everything in the design except Packs
and the Supporter purchase, both of which land later. The TestFlight build grants a free Supporter
year and the badge. The listing copy below describes that build.

Export compliance and Guideline 1.2 have both been researched and resolved. Section 3 assumes the
source is published alongside the TestFlight build, which is the plan and changes the obligations.

---

## 1. Listing

| Field | Value |
|---|---|
| Name | Outpost |
| Subtitle (30 char max) | `Group messaging, kept private` (29) |
| Primary category | Social Networking |
| Secondary category | Productivity |
| Price | Free |
| In-app purchases | Outpost Supporter — auto-renewing subscriptions, $12 a year or $1 a month, no introductory offers. Not in the TestFlight build, which grants a free year instead; add before the release. |
| Copyright | © 2026 Griff Tatarsky |
| Support URL | `https://outpostmessaging.com/support` |
| Marketing URL | `https://outpostmessaging.com` |
| Privacy Policy URL | `https://outpostmessaging.com/privacy-policy` |
| EULA | Custom, at `https://outpostmessaging.com/terms`. Apple's standard EULA is also acceptable; the custom one exists because §5's "no account to recover" needs saying. |
| TestFlight license agreement | Custom, in `docs/TESTFLIGHT_LICENCE.txt`. Pasted into TestFlight → Test Information → License Agreement, replacing Apple's standard beta agreement. Separate from the EULA above and needed sooner, because it governs the build the testers actually get. |

### Promotional text (170 max)

> Rooms for the group, an Outpost for you. Everything lives on the phones of the people you
> wrote it to — not on a server of ours, because there isn't one.

### Description

> Outpost is a group messaging app for friend groups.
>
> Rooms are for the group. Your Outpost is your own wall — you post, and the people you have
> allowed can see it and reply. You decide who those people are, one at a time.
>
> WHAT MAKES IT DIFFERENT
>
> There is no Outpost server. We do not run one. What you write is sealed on your phone and left
> in your own iCloud, addressed to the people it is for, until their devices collect it. Apple
> holds the sealed version and cannot open it. Neither can we, because we are not in the path.
>
> There is no account to create, no phone number to hand over, no directory to be found in, and
> no public profile. Your identity is a key on your devices.
>
> HOW SYNC WORKS
>
> Your phone gets a nudge when something is waiting for you. The nudge carries no content: your
> phone collects the sealed message and opens it itself to show who it is from. The app also
> collects whenever you open it, so notifications are optional. Nothing runs in your pocket all day
> polling, because there is no server to poll.
>
> THINGS WE WILL TELL YOU PLAINLY
>
> Adding someone to a room gives them its whole history, from the first message. Removing someone
> stops them receiving anything new — it cannot retrieve what they already have, because it is on
> their phone and always was. The app says both of these at the moment they matter.
>
> WHAT WE COLLECT
>
> Nothing. No analytics, no advertising identifiers, no third-party SDKs of any kind. The app
> depends only on Apple's own frameworks.

### Keywords (100 char max, comma-separated, no spaces)

```
private,encrypted,group chat,friends,e2e,no server,messaging,secure,rooms,wall,offline
```

### What's New (first release)

> First release. Rooms, Outposts, reactions, comments, and a device list you can revoke from.

---

## 2. Privacy nutrition label

Answer **"No, we do not collect data from this app."**

That is accurate and defensible: `Package.swift` has zero external dependencies, there is no
analytics or telemetry code anywhere in the tree, and the app transmits nothing to any server we
operate.

That last clause used to read "we operate none", which stopped being true when abuse intake moved to
`microgpt-comms` behind `outpostmessaging.com/report`. The app still never talks to it: the report
screen copies the report and opens the site in the browser, and the person submits it there
("This app sends nothing itself" — `ReportView`). What the form receives is the website's
collection, covered by the site's privacy policy, not the app's label.

**User Privacy Choices URL: leave it empty.** It is for an app that collects data and offers a page to
manage it. This one collects none, so there is nothing for such a page to govern.

The one thing worth understanding before answering: Apple's definition of *collect* is "transmit
data off the device in a way that allows you or your third-party partners to access it for longer
than necessary to service the request." Sealed packets go to **the user's own iCloud**, which we
have no access to, and are deleted on acknowledgment. That is not collection by us, and CloudKit
data in the user's own database is explicitly the user's, not the developer's.

Keep a note of this reasoning in case review asks. If a reviewer pushes back, the answer is: the
developer has no server, no account system, and no credential that could read any of it.

---

## 3. Export compliance

Researched against the regulation text rather than guessed. Both previously-open questions are now
closed. Sources at the end of this section.

### The finding that everything else rests on

**Outpost uses standard cryptography, not "non-standard cryptography."** The EAR defines the latter
(15 CFR 772.1) as cryptography "involving the incorporation or use of proprietary or unpublished
cryptographic functionality, including encryption algorithms or protocols that have not been adopted
or approved by a duly recognized international standards body (e.g. IEEE, IETF, ISO, ITU, ETSI,
3GPP, TIA, and GSMA) and have not otherwise been published."

Everything the app uses is an IETF standard, and none of it is implemented here — it is all CryptoKit:

| Primitive | Standard |
|---|---|
| ChaCha20-Poly1305 | RFC 8439 |
| Ed25519 | RFC 8032 |
| X25519 | RFC 7748 |
| HKDF-SHA256 | RFC 5869 |

This keeps the project out of 740.17(b)(3)(ii), the non-standard lane, which requires a
classification request to BIS before export. That is the expensive path and Outpost is not on it.

### Both open questions, closed

**ERN: not required.** 740.17(b)(1) authorizes export "subject to submission of a
self-classification report in accordance with § 740.17(e)(3)" and says nothing about registration.
Supplement No. 5 registration, and the ERN it produces, applies to someone redistributing another
party's encryption product when they cannot obtain that producer's classification. Not this
situation.

**Object code: it follows the source out of scope.** This was the question that mattered. The note to 15 CFR 734.3(b)(2) and (b)(3) says:

> "Publicly available encryption object code 'software' classified under ECCN 5D002 is not subject
> to the EAR when the corresponding source code meets the criteria specified in § 742.15(b) of the
> EAR."

And 742.15(b): *"Publicly available encryption source code classified under ECCN 5D002 is not
subject to the EAR."* The email notification buried in 742.15(b) applies only to source performing
**non-standard cryptography**, which the finding above rules out.

"Object code" is the compiled binary — the thing Apple distributes. So the question was whether
publishing the source frees only the repository or the shipped app as well. It frees both.

### What the decision to publish at TestFlight buys

| | Source published after launch | Source published at TestFlight |
|---|---|---|
| Classification | Self-classify as 5D992.c | Not subject to the EAR |
| Annual report to BIS and NSA | Every year, by 1 February | None |
| ERN | Not required either way | Not required |
| BIS/NSA email notification | n/a | Not required — standard crypto |

Publishing the source removes the recurring federal filing obligation rather than shrinking it.
There is nothing to send to anyone.

**Four conditions to actually hold this position:**

1. The published source is the source the shipped binary is built from.
2. "Publicly available" means available without restriction on further dissemination (EAR 734.7).
   A permissive or copyleft license satisfies this. A source-available license that forbids
   redistribution does not.
3. It stays public. Taking the repository down puts later builds back in scope.
4. The primitives stay standard. Substituting anything proprietary or unpublished moves the project
   into the non-standard lane and its classification-request requirement.

### What to put in App Store Connect

**`ITSAppUsesNonExemptEncryption` = `true`** — set in `App/Carpenter/Info.plist` on 2026-09-17 — and
answer Apple's questionnaire honestly. Being
outside the EAR is a US export question; Apple's questions are Apple's own. Do not answer `false` —
that answer exists for apps whose encryption is incidental, like an HTTPS call, and this app's
entire purpose is encryption.

Apple's documentation table is about what you must *upload*, which is narrower:

| Encryption type | Documentation Apple requires |
|---|---|
| Limited to that within the Apple operating system | None |
| Industry-standard algorithm not provided by the OS | French encryption declaration |
| Proprietary algorithm | US CCATS + French declaration |

Outpost sits on the first row, because it calls CryptoKit and ships no algorithms of its own. Expect
no upload. Answer the France question if distributing there.

### Sources

- 15 CFR 772.1, definition of "non-standard cryptography"
- 15 CFR 734.3(b), note on publicly available encryption object code
- 15 CFR 742.15(b), publicly available encryption source code
- 15 CFR 740.17(b)(1) and (e)(3), License Exception ENC and reporting
- Apple, *Export compliance documentation for encryption*, App Store Connect Help
- BIS, *Encryption items not subject to the EAR*

**None of this is legal advice.** The conclusions come from the regulation text quoted above and are
well-supported, but an hour with an export-controls attorney before submission is cheap insurance on
a position you will rely on for years.

---

## 4. Age rating, and Guideline 1.2

### Age rating

**13+, confirmed.** The questionnaire computes it from the answers below, with no override used.

Two earlier versions of this section were wrong and are recorded here so the reasoning is not
re-derived from scratch. It first said **17+**, which no longer exists — Apple's 2025 overhaul
replaced it with 18+ and added 13+ and 16+ in between. It then reasoned from "Unrestricted Web
Access", which Outpost does not have: there is no browser, no embedded web view and no link-opening
surface that reaches arbitrary content. The rating rests on user-generated content alone.

Answering the content questions "none" on the grounds that the app ships no content of its own
computes **4+**, and 4+ is actively dangerous here. It is the rating that invites questions about
under-13 users, COPPA and the Kids Category, on an app that by construction cannot screen a single
message. §5 already tells a reviewer there is no technical ability to filter content; that sentence
next to a 4+ badge is how a submission gets bounced.

**The comparator is Signal**, which is the closest thing that exists to this app and has every
incentive to declare accurately and none to inflate. Signal is rated **13+**, declaring *Infrequent*
on Profanity or Crude Humor, Mature or Suggestive Themes, and Medical Treatment information, plus a
*Contains: Messaging and Chat* tag. Their reading is that a messenger declares what a user will
realistically encounter through use of the app, not only what the developer authored. That reading
produces 13+.

**Answers to give:**

| Question | Answer |
|---|---|
| Profanity or Crude Humor | Infrequent/Mild |
| Mature or Suggestive Themes | Infrequent/Mild |
| Everything else | None |
| Social media features | **No** — see below |

That should compute to 13+ without touching the override. Medical Treatment is Signal's own
conservatism; leave it None unless you want to mirror them exactly.

**Do not use the override to get here.** The override exists for the case where your Terms of Use
set a higher minimum age than the questionnaire computes. Using it to paper over answers that were
too conservative leaves the wrong answers on file with the right rating bolted on top. Fix the input.

**Social media features: No.** Signal is the evidence — it has Stories, which is considerably more
feed-shaped than an Outpost wall, and carries no social media descriptor. Outpost has no public
profile, no follower graph, no discovery, no feed of people you have not admitted, and no algorithmic
distribution. These questions become mandatory in September 2026, and anything that trips the flag is
locked to a 13+ floor, so being on the right side of it is worth the care.

**Minimum age in the terms.** The marketing site's Terms of Use now bind at 13, with a clause
deferring to a higher local age where one applies — which covers the EU's 13-to-16 GDPR Article 8
range without naming a number per member state. Change it to 16 if you would rather sit above that
floor everywhere; it is one constant, `ageRating` in the site's `src/data/site.ts`, and the age page
and terms both read from it.

**The TestFlight license requiring 18+ is fine** alongside a 13+ listing. A beta restricted to adults
is normal and the two are separate instruments.

### Age suitability URL

```
https://outpostmessaging.com/age-suitability
```

Optional, beside the accessibility URL in section 8, and live with the first release. Written for a
parent rather than a reviewer: why the rating is what it is, what can reach a young person, what the
developer cannot do about content and why, what the young person can do in the moment, and what a
parent can and cannot do. It says there is no parental dashboard and cannot be one, and that a family
needing remote oversight of a child's messages should not use an end-to-end encrypted messenger. It
also publishes the questionnaire answers above and the reasoning.

It deliberately does not say the app is text-only, which stopped being true when photos arrived on
2026-09-04. It has to match the 13+ rating above; an earlier plan to rate the app 17+ was replaced by
the questionnaire's answer.

### Guideline 1.2

The guideline says apps with user-generated content **must** include:

> - A method for filtering objectionable material from being posted to the app
> - A mechanism to report offensive content and timely responses to concerns
> - The ability to block abusive users from the service
> - Published contact information so users can easily reach you

There is no exception for private messaging between people who know each other, and Apple has brought
random and anonymous chat explicitly under it. "Not a social network" is context for a reviewer, not
a defense.

| Requirement | Status |
|---|---|
| Published contact information | **Met, and it is a form rather than an address.** `outpostmessaging.com/support` in the listing, which routes to `/contact`. Nothing on the site or in the app is an email address any more — a form can refuse what a mailbox has to receive. Guideline 1.2 asks for contact information, not for a mailbox, and a reachable form is contact information. |
| Ability to block abusive users | **Built.** A silent, reversible block on every sender, from the held menu and the members list, with *Block and Leave* in a room, and a list of known abusers shipped in the app. |
| Mechanism to report | **Built.** Report on every message, photo and post. The app writes the report, shows every word of it, copies it, and opens `outpostmessaging.com/report`, which reads it and refuses anything that is not one. The app itself sends nothing and publishes no address. |
| Filtering objectionable material | **Built, on the device.** Apple's Sensitive Content Analysis on received photos and clips, blurred until revealed, and the app says when the system setting it depends on is off. Text nobody but the members can read cannot be filtered, and the review notes say so. |

The details, and the App Review reply, are in [Trust and safety](trust-and-safety.md).

### Sources

- Apple, *App Review Guidelines*, guideline 1.2, quoted verbatim above

---

## 5. Review notes

Paste roughly this into App Review Information → Notes. Reviewers often fail peer-to-peer apps because
the second device is missing.

> Outpost is a peer-to-peer group messaging app. There is no Outpost server and no login. A single
> device on its own will look empty by design, so please read this before testing.
>
> HOW TO TEST
>
> 1. Use two devices, each signed into iCloud with a **different** Apple Account.
> 2. On both, choose a display name and tap Create my identity. There is no sign-up, email or
>    password; the identity is a key made on the device.
> 3. On device B, open You, tap your name, and choose Send someone your code. Send it to device A.
> 4. On device A, create a room, open its menu, choose Invite someone, paste B's code under Their
>    code, and tap Create the invite. Send the invitation to device B.
> 5. On device B, tap I have an invite and paste it. Both devices now show the same ten characters.
>    Confirm they match on device B.
> 6. Messages arrive in the background when notifications are allowed. With notifications off, open
>    the app or pull to refresh on both devices.
>
> WHY THERE IS NO ACCOUNT
>
> There is no Outpost server, so there is nothing to have an account on. Messages are encrypted on the
> sending device and written into that user's own iCloud private database, shared with the people
> they talk to. The developer cannot read any of it.
>
> USER-GENERATED CONTENT AND GUIDELINE 1.2
>
> BLOCK: any member can block another at once, with nobody else's approval. A blocked person is handed
> no new keys, photos or notifications from the person who blocked them, and their messages are not
> shown. Outpost visibility is granted per person and can be withdrawn at any time.
>
> REPORT: any message, photo or post can be reported from the item itself. The report is written on
> the reporter's own device and every word of it is shown before anything leaves. The app then copies
> it and opens outpostmessaging.com/report in the browser, where the reporter pastes it, chooses a
> category and leaves a way to be reached. A person reads every one.
>
> The form is the only route in, and that is deliberate: it verifies that an upload is actually one of
> our reports and refuses everything else, which a mailbox cannot do. It has no file input, so no
> photograph can be sent to us even by somebody trying to.
>
> CONTACT: outpostmessaging.com/support, which routes to a contact form. There is no published email
> address, for the same reason.
>
> FILTERING: received photos and clips are screened on the device with Apple's Sensitive Content
> Analysis and blurred until the recipient chooses to see them. Message content is end-to-end
> encrypted and exists only on participants' devices, so the developer cannot scan, view or remove it,
> and does not claim to. What limits exposure is that nothing arrives from a stranger: there is no
> directory, no user search and no public content, and joining a room takes an invitation that the
> person joining confirms by reading characters with the person who invited them.

---

## 6. Screenshots

The iPhone and the iPad both ship in the first version (Griff, 2026-09-19), so App Store Connect asks
for both sizes. Both come from the real
build, drawing the Debug build's `--site-shot` fixtures, made by `Scripts/app-store-shots.sh`:

| Set | Simulator | Pixels |
|---|---|---|
| iPhone 6.9-inch | `outpost-shots-iphone`, iPhone 17 Pro Max | 1320 × 2868, portrait |
| iPad 13-inch | `outpost-shots-ipad`, iPad Pro 13-inch (M5) | 2752 × 2064, landscape |

Order, leading with what is different:

1. The rooms list. On iPad, with a conversation open beside it.
2. A conversation with reactions. On iPad the first shot already carries it.
3. Somebody's Outpost.
4. Choosing who sees your Outpost. On iPad, the panel beside your own Outpost.
5. The ten characters: comparing codes with somebody.
6. Who you are talking to. On iPad, as the sheet it is.

**Photos are not in the conversation yet.** The fixture has none, the project holds no photo it could
use, and a generated one looks generated. Two or three photos Griff owns, added to the fixture, finish
shot 2.

**Two things the export has to fix, both measured 2026-09-19.** An iPad captured in landscape comes out
as portrait pixels with the picture turned; and every capture carries an `eXIf` chunk whose
orientation still says "turn" after the pixels have been turned, so a viewer that honours it turns
them again. The script rotates the iPad set and keeps only the image and colour chunks.

The fixtures had to agree with themselves before they could be shown: the composer said *Visible to
14 people* beside a panel saying *Nobody can see your Outpost*, and *Hangar 7* had three members
and four people listed in it. The audience count is derived from the fixture's audience now.

---

## 7. Before submitting

What has to be true for the listing, the review notes and the website to be honest. The operational
list is on [Before a build goes out](epics/foundations.md#operational).

| Item | Where it stands |
|---|---|
| **The website describes the app as it was** | **Done.** Rewritten 2026-09-17, screens retaken from the running build, and `/status` carries what is built against what is not. |
| **One identity on two phones is unproven** | The listing does not claim it, and the site must not. A simulator cannot receive an iCloud Keychain hand-off, so it needs two real phones. |
| **Push has been seen once** | Griff saw a banner arrive on a phone on 2026-09-09. The extension has changed since, and nothing arrived on the simulator on 2026-09-14. Watch one on the TestFlight build before the listing's sentence about a nudge is relied on. |
| **Sending a report from a phone** | The report screen hands off to the browser, seen on the rig 2026-09-17. What has not been watched on a phone is the whole path — copy, paste, send — against the live service, because the service is not deployed yet. |
| **The Supporter purchase** | Not built. The TestFlight build grants a free year instead. |

---

## 8. Accessibility

### Accessibility URL

```
https://outpostmessaging.com/accessibility
```

Goes in App Store Connect under **App Information → Accessibility → Accessibility URL**. It is
optional, it shows on the product page on every platform except Apple TV, and for an unreleased app
it goes live with the first release rather than immediately.

The page is a full accessibility statement in the shape W3C WAI recommends: commitment, the standard
applied, what is supported, known limitations, how it was assessed, and how to report a problem. The
limitations section is the point of it — Apple's own labels have no slot for "labeled but not driven
by voice", and claiming everything is how a statement becomes worthless.

### Accessibility Nutrition Labels

Separate from the URL, and also optional — still not mandatory as of this writing, though Apple has
signaled it intends to require them eventually. Filled in per platform under the same section.

Declare only what the app actually does; these appear next to the app's name and a false one is worse
than a blank. Based on the state of the tree:

| Feature | Declare | Basis |
|---|---|---|
| VoiceOver | **After the walk** | Every icon-only control has a label, selected state is announced, decorative views are hidden, headings are marked, and the rooms list has an Unread rotor. Apple asks that every common task be possible with VoiceOver alone, so declare it after the walk on the TestFlight build. |
| Larger Text | **Yes** | `CarpenterFont` is built from system text styles throughout, so the whole scale follows Dynamic Type. `RoomsListView` restructures at `typeSize.isAccessibilitySize` rather than truncating. |
| Sufficient Contrast | **Yes** | `ContrastAuditTests` measures every text and surface pair over what it is actually drawn on, across every accent in both appearances and with Increase Contrast on and off, against 4.5:1 for text and 3:1 for interface edges. Apple's contrast audit runs on the rendered app for every accent. |
| Dark Interface | **Yes** | Full dark palette resolved from `colorScheme`, drawn rather than inverted, held to the same contrast floor. |
| Reduced Motion | **Yes** | Every animation the app draws itself reads Reduce Motion, or is a cross-fade, and the lint fails a file that animates without saying which. |
| Differentiate Without Color Alone | **Yes** | Status is shown by presence, count or shape, not hue: unread is a dot that is there or not, delivery marks are counted, and the not-sent mark is its own shape. Re-check if a status color is added. |
| Voice Control | **No** | Correct labels are most of what it needs and those exist, but the app has never been driven by voice. Declare it after testing, not before. |
| Captions | **No** | The only video is clips members send each other, which carry no captions. |
| Audio Descriptions | **No** | Same. |

The palette also reads Increase Contrast and strengthens every translucent value. There is no label for
that; it is on the accessibility page instead.

Two things on the site's page are stated as untested and should be revisited before the label is
edited: Voice Control and Switch Control. If either gets tested, update both the page and the label.

---

## 9. URLs the listing depends on

All live on the marketing site and must be reachable before submission, since Apple checks them:

- `https://outpostmessaging.com/privacy-policy`
- `https://outpostmessaging.com/support`
- `https://outpostmessaging.com/terms`
- `https://outpostmessaging.com/security`
- `https://outpostmessaging.com/accessibility`
- `https://outpostmessaging.com/age-suitability`
