---
title: Who you are talking to
layout: default
nav_order: 12
---

# Who you are talking to

{: .no_toc }

How the app makes sure the person in a conversation is the person you meant: at an invitation, in a
Solo, and at any time afterwards. Built, and proved on two Apple Accounts on 2026-09-09. The
cryptography behind the characters is in [The crypto, written down](crypto-brief.md).

1. TOC
{:toc}

## Why an invitation is an offer

In the first version, creating an invitation wrote the person invited into the room. On the rig on
2026-09-08, somebody shown a phrase tapped **They do not match** and was in the room anyway: the
check lived on their phone and decided only whether they accepted, while the inviter's phone had
already added them.

So the rule now is:

> **An invitation is an offer, not an admission.** Nobody is in a room until the person invited has
> confirmed the characters *and* the room's rule for who gets in is satisfied. Two gates, in that
> order.

The person invited checks first, so a room is never asked to approve somebody who is about to find
out the invitation is fake, and so they are never shown a room's name, members or history before
they accept it.

## An invitation, step by step

A invites B.

| | A sees | B sees |
|---|---|---|
| A creates the invitation | B under *Invited, not yet in*, with *Nothing back yet* and when it runs out | nothing yet |
| B opens it | no change | ten characters, and no room name, members or history |
| B taps **They do not match** | no change; the invitation runs out unanswered | a warning, and nothing joined or shared |
| B taps **They match** | B confirmed, then in or waiting, depending on the room | in, or waiting to be let in |
| B does nothing | *Invited, not yet in* until it runs out | nothing |

**A is never told B opened it.** Nothing travels from B to A before B confirms: B does not accept A's
CloudKit share until then. So A's list has two honest states, *invited* and *confirmed*, the same
rule as a delivery mark.

**A refusal is not sent.** To send one, B would have to connect to the mailbox of somebody they have
just judged possibly hostile, and in the case the warning exists for, that somebody is the attacker.
The refusal would tell the attacker their target is real and paying attention, and tell A nothing. So
B is told, on the screen where they refused:

> Nothing was joined and nothing was shared. You were never shown the room, and this device sent
> nothing back — including to whoever sent this, who does not learn that you looked.

A learns what A can observe: the invitation was never accepted.

**A controls the invitation.** A picks when it runs out when making it (a day unless changed), sees
everything outstanding under *Invited, not yet in*, and can take one back at any time. A withdrawn
invitation cannot be used even by somebody holding the link.

## Who gets in

After the characters, the room's own rule applies. The characters are required under every rule.

| Setting | After B confirms |
|---|---|
| **Anyone invited** | B is in. The characters are the only check. |
| **You approve** | waiting for whoever started the room |
| **One person decides** | waiting for the member chosen. If they have left, nobody can approve, and the room says so. |
| **Any member approves** | waiting; the first yes lets B in |
| **Several members approve** | waiting, with a running count |
| **Everyone approves** | waiting for every member; one silence holds it |

## A room nobody has joined yet

A room somebody is invited to and not in, or a room this member is waiting to be let into, carries
an **Invited** tag. The app adds and removes it; it sits at the front of the tag rail, drawn filled
where a member's own tags are outlined, and it is never sent to anybody. A room's long-press menu has
**Show only invited**. Each row says which way it is waiting: *Invited, not yet in* for the inviter,
*waiting to be let in* for the person invited.

## Seeing the characters again

**Who you are talking to**, in a room's menu, lists everybody in the room with the characters that
were read when they were invited and the date they were confirmed. Anybody on that list can be opened
to compare codes, below.

## Solos

A Solo has nobody to approve anybody, so the room rules do not apply. What a Solo offers is a check
either person can ask for.

**Check who I am talking to first**, in the privacy check-up and under Privacy & Safety, holds any
new Solo until the two people have read their characters to each other. What is held is the
composer: messages, banners and unread marks still arrive. The other person is not told about the
setting, because nothing on their phone can observe it; they see that they have been asked to check
who they are before carrying on.

**Check who I am talking to**, in a Solo's menu, asks at any time. The person asking chooses
**Keep talking** or **Hold until it is answered**, and the hold applies only to their own composer.
If asking could close the other person's conversation, anybody could close anybody's.

**A refusal closes the Solo for both people** and says why. Nothing already said is deleted. The way
out is to check again in person, or to block the person.

## Comparing codes later

The characters at an invitation exist only between the inviter and the person invited. Two other
people in the same room have nothing to compare. So any two people can open each other from **Who you
are talking to** and compare a code in two halves, one derived from each person's keys. Both phones
show the same two halves; if somebody had put their own keys in between, one half would not match.

The comparison is offered once per person. **They match** records a dated note on your own device and
sends nothing. When somebody you talk to adds a device, a dated line saying so appears in your
conversations with them.

This part is built and has run on the rig; the line about a new device needs one account on two
phones to see, and is listed on [Proofs a rig cannot run](proofs-a-rig-cannot-run.md).

## What this cost

**Rooms joined before the rule stopped counting their members.** The rule changes how the log is
read, not only what is written, so everybody who joined an open room before 2026-09-08 read as
invited and not confirmed until they confirmed. Nothing was lost and nobody was removed. This was
accepted because the app was in development; it would need a migration if a released build ever
changed a rule this way.

**What would change the refusal.** A way for B to reach A without first trusting A. There is none,
because the whole design is that you connect to the mailbox of somebody you have decided to talk to.
