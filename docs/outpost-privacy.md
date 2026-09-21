---
title: What an Outpost promises
layout: default
nav_order: 5
---

# What an Outpost promises

{: .no_toc }

What a member's Outpost protects, what it does not, and why the obvious fix for the part it does not
protect cannot work. Written 2026-09-07, after three designs for hiding a comment's author were built
and each was broken by an independent review.

1. TOC
{:toc}

## The question

An Outpost is a member's own page, and they choose who reads it. Everybody who can read a post can
read every comment under it, or a thread would have holes in it. So if B lets both A and C in, and C
comments, A gets C's comment, although A and C have never met.

The app draws C to A as one shared anonymous figure. But C's permanent identifier, a 32-byte number,
is stored on A's phone underneath that figure. The question was whether it could be moved inside the
sealed part of the entry.

## Why sealing it does not work

**The person it is hidden from holds the key.** Being let into B's Outpost means holding the key to
it. Anything sealed with that key, A can open. Putting C's identifier inside the seal hands it to
exactly the person it was meant to be kept from.

## The two real options

Every entry is an envelope with a sealed letter inside. The envelope is readable by anyone who carries
the entry, because that is how an entry moves between phones with no server. Today the envelope
carries a return address: who wrote this, from which device. There are two ways forward:

1. **Keep the return address**, and control what travels with it and who receives the envelope.
2. **Replace it with a throwaway name**, and privately tell the people the writer has met which
   throwaway name is theirs.

All three designs were versions of the second. It is blocked three ways.

**An entry lists where its writer has been in this conversation.** An entry's vector clock names
the logs its author has seen in the conversation it was written in, as person and device, which is
what lets two phones work out what the other is missing. Inside one Outpost, a clock names the logs
writing there, so a throwaway name and a real one posting on the same wall would be tied together
in both directions. A clock names nothing outside its own conversation, and a position counts only
within it, so nothing on an entry says what its writer does anywhere else.

**You cannot block what you cannot recognize.** Blocking and the list of known abusers both work on
the return address, including on entries the phone cannot open. A throwaway name is a different
address, so a blocked person's comments would come through. Unlinkable comments are, by the same
measure, unblockable.

**The format is already on disk.** The return address is part of every stored entry, so changing its
shape means nothing already written loads. Before release that costs a wipe; after release it costs
far more.

## What was done instead

**What travels with the address.** On its own, the identifier is a number. But a stranger reading
the same Outpost was also receiving the writer's display name, photo and Do Not Disturb message,
because three announcement paths treated "an Outpost I can read" as "a room I am in". That was fixed
on 2026-09-07 with no format change, and it was a bigger leak than the one being studied: an
identifier is a handle, a name is a person.

**Who can open a comment.** A member who does not want strangers reading what they write on other
people's Outposts can choose **Closed** under Outpost settings, *Joining in*. A closed comment is
sealed to the people *the writer* has let in, with a second copy for the post's author, so everybody
else holds bytes they cannot open and sees a count of comments not shown. Blocking still works, because the return address
is unchanged. The limit: a stranger can still tell *that* somebody commented. Closed hides the words,
not the fact. Built and proved on three devices on 2026-09-09
([the ticket](epics/rooms-and-membership.md#open-or-closed-on-other-peoples-outposts)).

**Who is offered an entry at all.** A device hands over an entry only to somebody allowed to read
it: a room's members, an Outpost's readers, and nobody past a history floor. Where that leaves a
reader with a gap — a member invited from today, looking at a log that started before them — the
sender says which positions it is withholding, and the reader stops asking for them. What a device
still carries for somebody else, posts on a shared Outpost mostly, is counted under History check,
*Carried for other people*.

## The promise

**Outposts are not anonymous, and the app does not say they are.**

> **What is promised.** Nobody learns who you are from this app. Your name, your face and your status
> never reach somebody you have not met, and the app never introduces you to anybody. To a stranger
> reading the same Outpost, you are one anonymous figure, and so is everybody else they have not met.
>
> **What is not promised.** That your comments cannot be grouped. Somebody technical, reading their
> own phone's storage, can tell that two comments on one Outpost came from the same person, and
> roughly how many people read it. They cannot turn that into a name, a face or a way to reach you.
>
> **If that is not enough**, choose Closed under Outpost settings, and what you write on other
> people's Outposts reaches only people you chose.
>
> **The owner of an Outpost always knows who wrote what on it.** They decide who gets in, and they are
> the only person who can put somebody out.

The nearest familiar thing is a private account on a social network: your followers can see each
other's replies.

## What would reopen it

All three of these, not any one.

1. A clock inside one Outpost that does not tie a throwaway name to a real one writing on the same
   wall.
2. A way to block and to enforce the abuse list without a stable return address, or a written
   decision that unlinkability wins and blocking gets weaker.
3. A third Apple Account, because the three-person case cannot be observed with two.

## Two findings from the same study

**A sealed letter was not bound to its writer.** Anybody holding a room's key could lift another
member's ciphertext into an entry of their own and sign it, and every phone would show it as theirs.
Fixed the same evening: the author and device are now part of what the seal authenticates, so a
lifted ciphertext does not open. A payload not bound to its writer opens for nobody.

**An Outpost is named by its owner.** Every entry on somebody's Outpost names their participant ID as
its conversation. That is visible to everybody holding the entry — the people let in, who already
know whose Outpost it is — and never to the relay, which sees only sealed packets. It has to be the
owner, so every device names the Outpost the same way without being told.

One review finding claimed that somebody let into an Outpost later receives its posts but not the
comments already under them. It was tested and does not reproduce; the test was kept.
