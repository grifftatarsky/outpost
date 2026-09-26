---
# COPY BEGIN 9bd107c0 [NEEDS HUMAN REVIEW]
title: Trust and safety
layout: default
nav_order: 9
---

# Trust and safety

{: .no_toc }

What the app does about abuse, why it does it that way, and what the law asks of whoever runs it.
Written 2026-09-04, when photos were built. The decisions are recorded in [Decisions](decisions.md);
this page carries the reasoning, the checklist and the procedure for handling a report.

Scope: US and Canada launch, an individual developer, no server. **Nothing here is legal advice.**

1. TOC
{:toc}

<!-- COPY END 9bd107c0 -->

<!-- COPY BEGIN c66ddf0b [NEEDS HUMAN REVIEW] -->

## Context

Outpost is end-to-end encrypted, and messages move between members' own iCloud accounts. There is
no Outpost server, no plaintext the developer can reach, and no way to inspect content in transit or
at rest.

Photos create three obligations text did not:

- **App Store Guideline 1.2** — user-generated content precautions: a filter, a report mechanism, a
  block, and published contact information.
- **18 U.S.C. § 2258A** — mandatory CSAM reporting to NCMEC's CyberTipline.
- **Canada's Mandatory Reporting Act (S.C. 2011, c. 4)** — reporting duties for a person providing
  an Internet service to the public.

The design satisfies all three without acquiring the ability to read content, without a server, and
without a new outbound network destination.

<!-- COPY END c66ddf0b -->

<!-- COPY BEGIN 34e9f653 [NEEDS HUMAN REVIEW] -->

## Decisions

Each is in [Decisions](decisions.md) with its cost; this is the short form.

| | Decision | Where it lives |
|---|---|---|
| **D1** | **On-device screening only.** Apple's `SensitiveContentAnalysis` on the receive path, before rendering. Flagged photos blur with tap-to-reveal. No server-side scanning, no proactive scanning, ever. | `SystemMediaScreen`, `MediaLoader`, `MediaBubbleView` |
| **D2** | **Screening is the member's to switch off, default on.** Guideline 1.2 asks that a filter exist, not that it be unbypassable. | You › Privacy & Safety › *Blur sensitive photos* |
| **D3** | **A report is text only. Never media.** Description, sender fingerprint, entry hash, timestamps, app version. The type has no field for bytes. | `AbuseReport`, `ReportView` |
| **D4** | **Blocking is local, immediate and silent.** A stamped flag on the member's own devices, enforced on receive, nothing written to any room. A blocked person is handed no new room keys, media or bells. | `MemberPreferences.blocked`, `AppSession.block` |
| **D5** | **The deny list ships in the binary.** SHA-256 fingerprints in `denylist.json`, applied on receive, updated by shipping a build. Nothing fetched. | `DenyList`, `Scripts/denylist.py` |
| **D6** | **The report channel is a published address.** A mail the member sends. | `Config/Branding.xcconfig` → `Branding.abuseAddress` |
| **D7** | **Age rating 13+.** Computed by Apple's questionnaire from accurate answers; the reasoning, including why an earlier 17+ was wrong, is in [App Store](app-store.md#age-rating). | App Store Connect |

**Rejected for D5, and why.** A public CloudKit database violates the design's private-and-shared-only
rule, and every fetch is a device check-in visible in the container. A static file on GitHub Pages
or a CDN is worse: it moves the check-in log to a third party that also sees the requesting IP,
which CloudKit never does.

<!-- COPY END 34e9f653 -->

<!-- COPY BEGIN 09365ad5 [NEEDS HUMAN REVIEW] -->

## Implementation

As of 2026-09-17.

<!-- COPY END 09365ad5 -->

<!-- COPY BEGIN bc38b922 [NEEDS HUMAN REVIEW] -->

### Receiving

- **Built.** The `com.apple.developer.sensitivecontentanalysis.client` entitlement is on the app
  target.
- **Built.** `SCSensitivityAnalyzer.analysisPolicy` is read at launch and every time a photo is
  screened. `.disabled` means unavailable, never safe: `ScreeningVerdict.notScreened` is its own
  answer, and `MediaLoaderTests` holds that line.
- **Built.** Images are analyzed from the decoded `CGImage`, so nothing is written to a temporary
  file to be looked at. Clips are analyzed with `videoAnalysis(forFileAt:)` before the poster frame
  is drawn, with the same three verdicts, the same blur and the same reveal.
- **Built.** A flagged photo is blurred until the member taps to reveal it, and the reveal is
  remembered per photo on that device.
- **Needs a device.** The analyzer runs on the simulator and judged a received photo clear on
  2026-09-04, so the negative path is proven. A positive verdict needs Apple's test profile on a
  phone and has not been observed; the blur was driven with a debug switch.

<!-- COPY END bc38b922 -->

<!-- COPY BEGIN cf683561 [NEEDS HUMAN REVIEW] -->

### Settings

- **Built.** *Blur sensitive photos*, on by default, under You › Privacy & Safety, with a footer that
  says what the device is doing: screening, off in the system's own settings (with a row that opens
  Settings), or unsupported. Where photos are not screened, it says so.
- **Built.** *Block known abusers*, on by default, with the list's date in the footer.
- **Built.** *Report a problem* opens a mail to the support address.

<!-- COPY END cf683561 -->

<!-- COPY BEGIN 87960e50 [NEEDS HUMAN REVIEW] -->

### Reporting and blocking

- **Built.** *Report* on every message somebody else wrote: in the held menu, on the details screen,
  on the full-screen photo, and on posts.
- **Built.** *Block* on every sender, in the held menu and on the members list, with *Block and Leave*
  where the person is in a room. Blocking is kept on the member's own devices and enforced on receive:
  in the transcript, the unread dot, the notification extension's banner and the photo fetch.
- **Built.** The report composer takes a description and shows exactly what goes with it. There is
  no attachment path: `AbuseReport` has no field for bytes, and `TrustAndSafetyTests.noRoomForMedia`
  fails if one is added.
- **Built.** Sending opens the system mail composer, filled in, addressed to the abuse address.
  Nothing is sent in the background. Without a mail account, the report is offered for copying.
- **Built.** The report screen tells the reporter to keep their own copy and links CyberTipline (US)
  and Cybertip.ca (Canada).

<!-- COPY END 87960e50 -->

<!-- COPY BEGIN 7b82d069 [NEEDS HUMAN REVIEW] -->

### The deny list

- **Built.** `denylist.json` in `CarpenterKit`'s resources: a version, a date and SHA-256
  fingerprints, covered by the app's code signature.
- **Built.** A listed sender is treated as blocked on receive.
- **Built.** `Scripts/denylist.py add <fingerprint>` appends to the list and updates the date.

<!-- COPY END 7b82d069 -->

<!-- COPY BEGIN 3b6ff346 [NEEDS HUMAN REVIEW] -->

### Documents

- **Built.** The TestFlight license has a no-tolerance clause for objectionable content and abusive
  use, and says what a report does and does not carry (`docs/TESTFLIGHT_LICENCE.txt`, sections 9
  and 10).
- **Built.** In-app account deletion: *Erase everything*, the last section of You, states what is
  erased and what is not (anybody else's copy of what you sent). Guideline 5.1.1(v).
- **Not done.** The App Store EULA and the website's privacy policy need the same clause and a
  section on what a report contains and how long it is kept.
- **Not done.** Contact information in App Store Connect.
- **Not done.** The encrypted vault for report records; see
  [where report records live](#where-report-records-live).

<!-- COPY END 3b6ff346 -->

<!-- COPY BEGIN 461adb91 [NEEDS HUMAN REVIEW] -->

## Acceptance criteria

All met.

1. **A reviewer can find, in under thirty seconds,** report (hold any message), block (the same menu),
   the filter switch and contact information (You › Privacy & Safety), and the EULA. The EULA is the
   TestFlight license until the store copy exists.
2. **Reporting a message never sends media.** By construction, and by test.
3. **Blocking takes effect with no network call**, on messages already received as well as new ones.
   `BlockingTests` checks the mailbox saw no packet for it.
4. **With screening unavailable, photos draw normally and the app does not claim they were
   screened.** `offInSystemIsNotScreened`, and the Privacy & Safety footer.
5. **A deny-listed sender's messages are dropped on receive while the switch is on.**
   `denyListSwitch`.
6. **No new outbound network destination compared with the build before photos.** Photos travel in
   the same CloudKit container and zone as packets, and reports go through the member's own mail app.
   Not measured with a proxy; nothing in the code opens a connection anywhere new.

<!-- COPY END 461adb91 -->

<!-- COPY BEGIN 07cdfec5 [NEEDS HUMAN REVIEW] -->

## Mandatory reporting obligations

### United States — 18 U.S.C. § 2258A

**Who it applies to.** Providers of an electronic communication service or remote computing service
to the public. Outpost qualifies, and an individual developer is covered the same as a company.

**Trigger.** *Actual knowledge* of facts or circumstances from which there is an apparent violation
of the child-exploitation statutes listed in § 2258A(a)(2)(A). A member's report describing apparent
CSAM can constitute actual knowledge. Report **as soon as reasonably possible**.

**Where.** NCMEC's CyberTipline. Registration as an ESP is *not* required to file — it is required
only for the secure mechanism that permits submitting images and video with a report. Unregistered
providers file at <https://report.cybertip.org/>. Outpost never possesses media, so the public form
is sufficient; registering anyway is optional and gives a named point of contact.

**What goes in the report.** § 2258A(b): contents are *at the sole discretion of the provider*, and
only to the extent the information is within the provider's custody or control. Visual depictions
are not required. Submit what exists: the reporter's description, the sender's fingerprint, the
entry hash, the timestamps, and contact details.

**No duty to monitor.** § 2258A(f): nothing requires a provider to monitor any user, monitor the
content of any communication, or affirmatively search, screen or scan. This is the statutory basis
for D1's "no proactive scanning".

**Preservation.** § 2258A(h): a completed CyberTipline submission is a request to preserve the
contents provided in the report for **one year**, in a secure location with limited access, in a
manner consistent with the current NIST Cybersecurity Framework. **This overrides delete-after-action
for CSAM-related reports.**

**Penalties.** § 2258A(e): knowing and willful failure to report — up to **$600,000** for a first
failure by a provider with fewer than 100 million monthly active users, up to **$850,000** for any
later one.

<!-- COPY END 07cdfec5 -->

<!-- COPY BEGIN 118f776a [NEEDS HUMAN REVIEW] -->

### Canada — Mandatory Reporting Act (S.C. 2011, c. 4)

Current text: <https://laws-lois.justice.gc.ca/eng/acts/I-20.7/FullText.html>

- **s. 2 — Report an address.** If advised of an IP address or URL where child sexual abuse material
  may be available *to the public*, report it to the designated organization (Cybertip.ca) as soon
  as feasible. Rarely applicable — nothing in the app is public — but a report may surface a URL.
- **s. 3 — Notify police.** With reasonable grounds to believe the service is being or has been used
  to commit such an offense, notify a peace officer as soon as feasible. This is the one that will
  apply.
- **s. 4 — Preserve 21 days.** Preserve related computer data for 21 days after notification, then
  destroy anything not retained in the ordinary course of business (unless under judicial order).
- **s. 5 — No disclosure.** Do not disclose that a report or notification was made, or its contents,
  if disclosure could prejudice an investigation — whether or not one has begun. **Design
  consequence, built:** the app never tells the reporter or the reported person that a report was
  escalated. The report screen says so: acknowledged, never explained.
- **s. 6 — No seeking out.** Nothing requires or authorizes seeking out such material. Same basis as
  § 2258A(f).
- **s. 7 — Immunity.** No civil proceeding for a good-faith report or notification.
- **s. 9 — Foreign compliance.** Reporting under a foreign jurisdiction's law is deemed compliance
  with s. 2 — s. 2 only; it does not discharge s. 3.
- **s. 10 — Penalties for an individual.** First offense up to $1,000; second up to $5,000;
  subsequent up to $10,000 or six months, or both.

**Definitional gap, current law.** "Internet service" is presently Internet access, content hosting,
or electronic mail. Whether a peer-to-peer encrypted messenger fits is arguable. Do not rely on the
argument.

**Amendments not yet in force (2026, c. 19)**, to be tracked:

- "Internet service" expands to *a service facilitating interpersonal communication over the
  Internet*. Outpost is squarely covered once in force.
- New s. 3 narrows police notification to offenses committed by means of a computer system **located
  in Canada**, **in the person's possession or control**, with the material **stored on that
  system**. Outpost plausibly fails the second and third — the devices are the members' and CloudKit
  is Apple's — which may substantially reduce the s. 3 duty.
- Preservation extends from 21 days to **one year**.
- New s. 9.01: reporting under a foreign obligation removes the s. 3 requirement. A CyberTipline
  filing would then cover it.
- Limitation period extends from two years to five.

**Action:** re-read the Act before a Canadian launch and again when the amendments come into force.
Design to the stricter reading in the meantime.

<!-- COPY END 118f776a -->

<!-- COPY BEGIN d45d6538 [NEEDS HUMAN REVIEW] -->

### Standard operating procedure

1. **Receive** a report at the abuse address. Acknowledge receipt within 24 hours. Promise no outcome.
2. **Do not request the media.** If a reporter attaches media, do not open it, do not forward it;
   delete the attachment and note that it was deleted.
3. **Assess** from the description alone. Two buckets:
   - *Harassment, spam, unwanted explicit material between adults* → the deny-list track (step 6),
     no external reporting.
   - *Apparent CSAM, child sexual exploitation, enticement, trafficking of a minor* → escalation
     (step 4).
4. **US escalation.** File at <https://report.cybertip.org/> as soon as reasonably possible: the
   reporter's description, the sender fingerprint, the entry hash, timestamps with time zone, contact
   details. State plainly that the media was never possessed and the service is end-to-end encrypted.
5. **Canada escalation.** If the reporter or sender is in Canada, notify police as soon as feasible.
   If a public URL was reported, also report to <https://www.cybertip.ca/>.
6. **Deny list.** `Scripts/denylist.py add <fingerprint>`; ship in the next build.
7. **Preserve.** Retain the report record — never media, which was never held — for **one year**
   from the CyberTipline submission (US) and per the Canadian window if s. 3 notification was made.
   Encrypted at rest, access limited to the developer.
8. **Do not disclose.** Tell neither the reporter nor the sender that an escalation occurred.
9. **Close** with a dated note in the vault: what was reported, what was filed, where, when.

<!-- COPY END d45d6538 -->

<!-- COPY BEGIN 01d7b9b4 [NEEDS HUMAN REVIEW] -->

### Where report records live

**Closed 2026-09-17.** Griff: "I delete the abuse email. You can only submit through the site."

The problem this section described was mail: reports landing in a third-party mailbox, which is not
consistent with § 2258A(h)(3) (secure location, limited access) or (h)(6) (NIST-consistent), and
which leaves the mailbox provider holding records the developer is supposed to be safeguarding. The
proposed fix was an encrypted disk image the rare filed report is moved into.

There is no mailbox now, so there is nothing to move a record out of. A report is a row in `cms-db`,
in the Postgres cluster on a machine Griff owns and physically holds, reached only from that machine
— no cloud service and no third party in the path at all. It is covered by the `pg_dumpall` sidecar
that was already running nightly, which picked the database up the moment Liquibase created it.

**What changed in the published claim, which matters more than the storage did.** The privacy policy
said a report is "encrypted at rest" and "moved out of the receiving mailbox". Nobody had checked the
first, and it is a property of that machine's disk rather than of any software here; the second no
longer describes anything. Section 10 now says where a report actually lives and adds the sentence
the backup schedule makes necessary: a deleted report survives in a nightly dump for up to three
further days, because three are kept.

**What is left, and it is his and not the code's.** § 2258A(h) wants a filed report kept in a secure
location with limited access for a year. A database on a machine in his house, reachable from
nowhere else, is a defensible reading. Whether the disk under it is encrypted is an operating-system
decision he can make in an afternoon and no commit here can make for him.

<!-- COPY END 01d7b9b4 -->

<!-- COPY BEGIN 19a5b739 [NEEDS HUMAN REVIEW] -->

## Risks and open questions

| Risk | Note |
|---|---|
| Deny-list latency | Days to weeks. Local blocking is the real-time mitigation. Accepted. |
| Key rotation defeats bans | A banned member generates a new key pair. Consider tying identity to something scarce, or rate-limiting rotation. Unresolved. |
| Anonymous-chat clarification | Apple clarified in February 2026 that random or anonymous chat apps fall under 1.2. Outpost is contact-based rather than stranger-matching, but expect the question. |
| Published contact information as an individual | The developer's legal name and address become the published contact. For an anonymity-focused app this is a mismatch; an LLC fixes it for a few hundred dollars. |
| Screening is opt-in at the OS level | Most members will have Sensitive Content Warning off, so the filter does nothing for them. The app says so in the Safety footer; the App Review reply must not overstate coverage either. |
| Legal review | Not required by statute. Given the individual-not-entity posture and the one-year preservation duty, an hour of counsel before launch is cheap insurance. |

<!-- COPY END 19a5b739 -->

<!-- COPY BEGIN d15c1679 [NEEDS HUMAN REVIEW] -->

## App Review reply — draft

> Outpost is an end-to-end encrypted messaging app. Message content is not accessible to the
> developer at any point, so server-side moderation is technically impossible by design.
>
> The Guideline 1.2 precautions are implemented as follows:
>
> - **Filtering objectionable material:** on-device screening of received photos using Apple's
>   SensitiveContentAnalysis framework, enabled by default. Flagged photos are blurred until the
>   recipient chooses to reveal them. The framework answers only when the device's Sensitive Content
>   Warning is on, and the app says so in its settings rather than claiming coverage it lacks.
> - **Reporting:** a Report action on every message, photo and post. The app composes the report on
>   the device, shows every word of it, copies it and opens a form on the developer's website, where
>   the reporter pastes it and chooses a category. The form verifies that what it was given is one of
>   these reports and refuses anything else; it has no file input, so no media can be sent to the
>   developer even deliberately. Reports carry no message content and no media. A person reads every
>   one, and a reporter who leaves an email address is told what was done.
> - **Blocking:** members can block any sender immediately; blocks are enforced on the receiving
>   device, in every room. Senders confirmed abusive are added to a deny list distributed with app
>   updates and blocked for all members by default.
> - **Contact:** a contact form at outpostmessaging.com/contact, linked from the support URL in the
>   listing, and a support contact in App Store Connect. No email address is published, because a
>   form can refuse what a mailbox has to receive.
>
> The EULA prohibits objectionable content and abusive use. The app complies with 18 U.S.C. § 2258A
> and Canada's Mandatory Reporting Act; confirmed child-safety reports are escalated to NCMEC's
> CyberTipline and to law enforcement as required.

<!-- COPY END d15c1679 -->

<!-- COPY BEGIN 4e61b7ad [NEEDS HUMAN REVIEW] -->

## Sources

- SCSensitivityAnalyzer — <https://developer.apple.com/documentation/sensitivecontentanalysis/scsensitivityanalyzer>
- Testing SCA responses — <https://developer.apple.com/documentation/sensitivecontentanalysis/testing-your-app-s-response-to-sensitive-media>
- App Review Guidelines — <https://developer.apple.com/app-store/review/guidelines/>
- 18 U.S.C. § 2258A — <https://www.law.cornell.edu/uscode/text/18/2258A>
- NCMEC CyberTipline — <https://www.missingkids.org/gethelpnow/cybertipline>
- CyberTipline public report form — <https://report.cybertip.org/>
- Canada Mandatory Reporting Act, current and amendments not in force — <https://laws-lois.justice.gc.ca/eng/acts/I-20.7/FullText.html>
- Cybertip.ca mandatory reporting — <https://www.cybertip.ca/en/about/mandatory-reporting/>

<!-- COPY END 4e61b7ad -->
