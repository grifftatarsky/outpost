<!-- COPY BEGIN b022a007 [NEEDS HUMAN REVIEW] -->

# Part B: what is left after 2026-11-11

Part A is what Griff asked for on 2026-11-10: a plan for formats after the first tester build, a way
to tell members to update with no server, the lock's second factor, tests with many devices and no
simulator, and layouts for the chat list. What was built is in the commits of 2026-11-11. This page
is everything that was found, designed or left, in the order to take it. It replaces "Left to do" in
[the plan to a first tester build](pre-testflight.md#the-plan-to-a-first-tester-build-2026-11-10)
where the two disagree.

## Waiting on Griff

Nothing below is built until he answers. Each line has a recommendation where it is linked.

1. **Six things found while fixing the twelve faults**
   ([the list](open-questions.md#twelve-faults-the-many-device-tests-found)). All twelve faults are
   fixed. Two of the six let a removed device keep something it should not, and each has a
   recommendation.
2. **A reader let in "from now" when the owner posts from two devices**
   ([the question](open-questions.md#a-reader-let-in-from-now-when-the-owner-posts-from-two-devices)).
   Today's fix is a trade. Say whether it stays, and whether the entry that lets a reader in should
   name the exact key.
3. **Formats and the update notice** ([design](designs/formats-and-updates.md), first page). Confirm
   the thirteen promises in its section 2 and answer five decisions: old messages are never
   converted; a release reads a new form one release before any release writes it; whether the
   notice also compares the App Store build number; a room takes no writes while a current member
   has written something newer; no App Store lookup, no public iCloud record, no reminder by age.
4. **How much a newcomer can read** ([design](designs/room-history.md), first page). Confirm four
   promises and answer six decisions. A time window can only honestly say "no more than N days".
5. **The lock** ([the question](open-questions.md#outposts-own-lock-seals-what-the-phone-keeps-and-what-that-costs)).
   Five things found while building the second factor, and the five sentences it must guarantee.
6. **Five rulings that exist only on a branch that never merged**
   ([the question](open-questions.md#five-rulings-were-recorded-on-a-branch-that-never-merged)).
   Which still stand.
7. **The chat list** ([design](designs/chat-layout.md), section 10, ten questions; the mockups are a
   private artifact). Pick a layout. The smallest change is to stop keeping an empty unread column
   on every row.
8. **The two-account rule** ([design](designs/many-device-tests.md), section 8). Whether a change
   that touches nothing at the iCloud seam may be called proven by the many-device suite once the
   fake and iCloud pass one shared set of checks. Until he says so the rule stands.
9. **The work orders that change behaviour** ([folder](designs/work-orders/)): keeping or dropping
   the Mac build, portrait only including the media viewer, the sheets, a contact address and a way
   for a tester to send logs.

## To build, in order

1. Done 2026-11-11: all twelve faults, one commit each.
2. Formats, part one (design section 5): the format number in every packet, refusing a newer one,
   keeping a newer message and showing it after the update, the room that takes no writes, the
   state-file check, the notices, the version in Settings. Then both live pair suites, because the
   packet changes.
3. Send each person only what they may read (a lost ruling, if it stands), then the room history
   setting, which leans on it.
4. Tests: the shared checks run against the fake and against iCloud; `Scripts/smoke-two-accounts.sh`;
   scenarios 13 to 26; move `ScannedFieldsTests` into the package. The suite's time: `swift test` takes
   about 305 seconds and `Scripts/test-package.sh` about 215, by running six processes.
5. The lock on a simulator with Face ID enrolled (`RigChecks` does not enrol one yet), then on an
   iPhone, where the Secure Enclave runs for the first time.
6. The chat list, once picked. Then the notification settings that are saved and read by nothing.
7. The work orders that change nothing a member sees: accessors only tests call, the
   `legacySecret(with:)` rename, test waits counted in attempts.
8. The tester build itself: iPhone only, archive, validate, the schema to production. Each needs
   Griff's go-ahead.

## Not verified

- Nothing from 2026-11-11 has run on two Apple Accounts or on an iPhone. That covers the lock's
  second factor, the three fixes and every fault in the list.
- The twelve faults were shown, and their fixes pass, against the fake iCloud. Most need three people
  or two devices on one account, which the rig does not have.
- The layouts were not looked at as drawn.
- The audit of the unmerged branch was checked by hand only for the five rulings.

<!-- COPY END b022a007 -->
