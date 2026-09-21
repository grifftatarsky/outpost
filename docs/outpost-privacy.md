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

**An entry still lists where its writer has been in *this* conversation.** An entry's vector clock
names the logs its author has seen, as person and device, which is what lets two phones work out what
the other is missing. It used to name every conversation its writer kept, anywhere — a comment under
a throwaway name would have carried the writer's real address in its own clock, and their next
ordinary message would have carried the throwaway name in its clock, linking the two in both
directions across the whole app. **That was fixed on 2026-09-20**: a clock now names only the
conversation its entry was written in, so nothing links an Outpost to a room any more.

What remains is narrower and still enough. Inside one Outpost, a clock names the logs writing there,
so a throwaway name and a real one posting on the same wall are still tied together.

The position numbers no longer say anything. Since 2026-09-21 each device keeps one log per
conversation, numbered from one there, so no number on any entry counts what its writer does
elsewhere. This page used to say that splitting the log would let a device drop or reorder its own
history undetected. It doesn't: within a conversation the chain is exactly as strict as before, and
members now vouch for each other's logs, which catches more than the old single chain did. See
[Architecture](architecture.md#members-vouch-for-each-others-logs).

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

**Who is offered an entry at all.** A friend of a friend used to store and forward entries for rooms
they were not in. They could not read them, but they could see that the room existed and who wrote in
it. Narrowing that was designed twice on 2026-09-07 and declined both times, because a phone tracks
what it is missing as one numbered run per person while any narrowing decides per room: a skipped
entry becomes a permanent gap nobody is allowed to fill and nobody can tell from a real loss. A way to
tell *withheld* from *lost* had to exist first.

**It exists now, and the narrowing is built.** A sender states, in the same packet, the positions it
is withholding; the reader writes them down and stops asking. So a device is no longer offered a
conversation it is not in, and no longer holds one. How much is still carried for somebody else —
posts on a shared Outpost, mostly — is counted under History check, *Carried for other people*, and
that number should now be small. Done 2026-09-20.

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

All three of these, not any one. The first is now done.

1. ~~A separate clock and log per conversation, so an entry stops listing everywhere its writer has
   been.~~ **Done 2026-09-20 and 2026-09-21.** A clock names only its own conversation, and positions
   count only there. What is left: inside one Outpost, a clock still ties a throwaway name to a real
   one writing on the same wall.
2. A way to block and to enforce the abuse list without a stable return address, or a written
   decision that unlinkability wins and blocking gets weaker.
3. A third Apple Account, because the three-person case cannot be observed with two.

## Two findings from the same study

**A sealed letter was not bound to its writer.** Anybody holding a room's key could lift another
member's ciphertext into an entry of their own and sign it, and every phone would show it as theirs.
Fixed the same evening: the author and device are now part of what the seal authenticates, so a
lifted ciphertext does not open. Since 2026-09-21 there is no fallback for older seals: a payload not bound to its writer opens for nobody.

**An Outpost's address is half its owner's identifier.** The room ID of somebody's Outpost is the
first 16 bytes of their participant ID, visible on every entry on it. It has to be derivable, so that
every device works it out the same way instead of being told, which is also why it cannot be hidden.

One review finding claimed that somebody let into an Outpost later receives its posts but not the
comments already under them. It was tested and does not reproduce; the test was kept.
