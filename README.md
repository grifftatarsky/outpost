# Outpost

Group messaging for iPhone with no Outpost server.

A message is sealed on the phone that sends it and left in the sender's own iCloud. The people it is
for collect it from there and open it on their own phones. There is no sign-up, no phone number and
no directory: you are a pair of keys your phone makes, and people reach you only through a code you
give them. The developer runs nothing that holds a conversation, so there is nothing to hand over.

Outpost is in development and has not been released. A TestFlight beta is next.

- **Website:** [outpostmessaging.com](https://outpostmessaging.com)
- **Documentation:** [grifftatarsky.github.io/outpost](https://grifftatarsky.github.io/outpost/),
  built from [`docs/`](docs/)
- **TestFlight:** link to come

## How it works

Every message, reaction and change to a room is an **entry** in a log. Each entry is sealed under the
room's key and signed by the device that wrote it. To send, a phone packs its new entries into one
**packet**, seals it again for the people it is for, and writes it into an `Outbox` zone in its
owner's iCloud private database. That zone is shared with the people they talk to. Their phones read
it, open what is addressed to them, and acknowledge it; once everyone has, the packet is deleted.

Addresses on a packet rotate daily and are derived from a secret each pair of people share. Apple
sees sealed records, their sizes, when they come and go, and which Apple Accounts have accepted a
share of someone's outbox. It does not see what was said, which room it was for, or anyone's name.
[Architecture](docs/architecture.md) explains the moving parts, and
[The crypto, written down](docs/crypto-brief.md) explains every key, including what has gone wrong.

Nobody outside this project has reviewed the protocol. The source is published so that it can be.

## What it does

- Rooms, and Solos with one person. Joining a room takes an invitation and ten characters the two of
  you read to each other, so nobody can slip into the middle.
- Messages, photos and clips, with captions, reactions, editing and withdrawal. Photos are stripped
  of location and camera details before they are sealed.
- Delivery and read marks drawn only from what was observed.
- Outposts: your own page, readable only by the people you let in, with posts and comments.
- Blocking, reporting, a list of known abusers, and on-device screening of sensitive photos.
- Notifications that name the room and sender, filled in on the phone after the push arrives.
- A recovery key, and your own devices kept in step through your iCloud.
- A Supporter badge, free for a year for everyone who tests the beta.

[The roadmap](docs/roadmap.md) is the full list, with what has been proved on real devices and what
has not.

## Building it

You need a Mac with an Xcode that includes the iOS 26.5 SDK. The app runs on iOS 26.5 or later.

```bash
cd Packages/Carpenter && swift test
```

```bash
xcodebuild -workspace Carpenter.xcworkspace -scheme Carpenter \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Sending anything needs an iCloud container and a development team you control: set
`APP_BUNDLE_ID_PREFIX` in `Config/Branding.xcconfig`, which names the container, and the team in the
project. The code is named **Carpenter**. The product name is set in `Config/Branding.xcconfig` and
nowhere else, and `Scripts/lint-branding.sh` enforces that.

| Module | What it is |
|---|---|
| `CarpenterKit` | The log, the cryptography and the sync engine. Depends only on Foundation. |
| `CarpenterApp` | The session: storage, rooms, membership and what a sync round does. |
| `CarpenterUI` | The SwiftUI screens. |
| `CarpenterCloudKit` | The mailbox and device sync, on CloudKit. |
| `CarpenterKeychain` | The one place that calls Security.framework. |
| `CarpenterMedia` | Preparing photos and clips, and on-device screening. |
| `App/Carpenter` | The app target and the notification service extension. |

[Testing](docs/testing.md) covers the suites, and [The simulator rig](docs/simulator-rig.md) covers
proving anything that crosses the network, which needs two Apple Accounts.

## Contributing and security

Read [`CLAUDE.md`](CLAUDE.md) before changing code. It holds the rules the lint enforces and the
mistakes this codebase has already made. Decisions and who made them are in
[Decisions](docs/decisions.md).

To report a security problem, use the contact form at outpostmessaging.com/contact rather than
opening a public issue.

## License

The source is licensed under the [Mozilla Public License 2.0](LICENSE).
