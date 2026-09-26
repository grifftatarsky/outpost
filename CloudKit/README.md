<!-- COPY BEGIN 2afcc63d [NEEDS HUMAN REVIEW] -->

# The CloudKit schema

`schema.ckdb` is the container's record types, written by hand and kept in git.

<!-- COPY END 2afcc63d -->

<!-- COPY BEGIN 076986d5 [NEEDS HUMAN REVIEW] -->

## Why it is written rather than inferred

CloudKit's development environment invents a record type the first time you write one, and the
usual route to production is to deploy whatever that inference produced. On 2026-09-17 the
development schema was exported and it held one type: `Users`, the stock one every container is born
with. Nothing the app writes had ever reached it — the rig runs against `FileMailbox` most of the
time, and the live suite is opt-in behind `CARPENTER_CLOUDKIT_TESTS`.

So there was nothing to deploy, and "Deploy Development to Production" would have pushed nothing
while looking like it had worked. The first write from a TestFlight build would have failed on a
record type that does not exist, with no error anywhere saying why.

A written schema is better than the inferred one would have been. It is reviewable, it is in git
beside the code that writes it, and it says what is intended rather than whatever a test run
happened to leave behind.

<!-- COPY END 076986d5 -->

<!-- COPY BEGIN 6970ec1d [NEEDS HUMAN REVIEW] -->

## Where each field comes from

Every type and field is read off the line that writes it. Nothing here is a guess.

| Record type | Field | Type | Written at |
|---|---|---|---|
| `SyncPacket` | `packetID` | STRING | `PacketWire.fields(of:)` |
| | `ciphertext` | BYTES | same |
| | `outstanding`, `wrapTags`, `wrapValues`, `grantTags`, `grantValues` | LIST\<BYTES\> | same |
| `MessageBell` | `ring` | INT64 | `CloudKitMailbox+Bell.swift` |
| `SiblingFeed` | `feed` | BYTES | `CloudKitEntrySync.payloadKey` |
| `Attachment` | `attachmentID` | STRING | `AttachmentWire.fields(of:)` |
| | `blob` | ASSET | written as a `CKAsset` in `CloudKitRecords.swift` |
| | `outstanding` | LIST\<BYTES\> | `AttachmentWire` |
| `OutboxShareOffer` | `sealed` | BYTES | `CloudKitMailbox+ReverseChannel.swift` |
| | `digest` | STRING | same |

**No queryable indexes on anything.** The app reads zone change feeds and never runs a `CKQuery` —
deliberately, because the query index is eventually consistent and that cost a week once. A field
added here needs an index only if something starts querying, which nothing should.

The grants are CloudKit's own defaults. They govern the public database, which this app never
touches: every record is in a private zone or a zone shared through `CKShare`, where access follows
ownership and the share rather than a role.

<!-- COPY END 6970ec1d -->

<!-- COPY BEGIN 998ea099 [NEEDS HUMAN REVIEW] -->

## Changing it

The record types are `PushChannel.recordType` plus `Attachment` and `OutboxShareOffer`. If you add a
field, add it here in the same commit — and remember that **a production schema is additive**. A
field deployed to production cannot be removed, ever, so the review is the only gate there is.

```bash
xcrun cktool validate-schema --team-id 999S5A5WC5 \
  --container-id iCloud.com.microgpt.outpost --environment development \
  --file CloudKit/schema.ckdb

xcrun cktool import-schema --team-id 999S5A5WC5 \
  --container-id iCloud.com.microgpt.outpost --environment development \
  --file CloudKit/schema.ckdb
```

Production is deployed from the CloudKit Console, not from here, because the Console shows a diff
first and `import-schema --environment production` does not.

<!-- COPY END 998ea099 -->
