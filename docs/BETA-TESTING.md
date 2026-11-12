# Testing an Olympus beta

An automated pass and an in-game pass are different evidence. Record both. A green
repository check means the Lua, fixtures and package invariants passed offline; it does not mean
that a World of Warcraft client, gamepad flow or exchange between real players was observed.

## 1. Build gate (automated)

Start from the exact commit to be tested, in a clean Git worktree. `package.sh` refuses tracked
changes and any untracked or ignored file under `Olympus/` or `Olympus_Arena/` that could enter a
zip.

```bash
git status --short
git diff --check
bash tests/check-scripts.sh
bash scripts/check.sh
scripts/package.sh --test N
```

The last command writes four tester artifacts:

- `dist/Olympus-<version>-testN.zip`
- `dist/Olympus-<version>-testN.files.txt`, the sorted files in that zip
- `dist/Olympus-<version>-testN.sha256`, the zip's SHA-256
- `dist/Olympus-<version>-testN.txt`, install and rollback instructions

Review the manifest before distributing the zip. On macOS verify it from `dist/` with
`shasum -a 256 -c Olympus-<version>-testN.sha256`; on Linux use `sha256sum -c`.
Keep the test zip and its sidecars together. Test builds expire, identify their build and commit
in game, stay in their test group, and are not release files.

## 2. One Windows client (observed)

1. Quit World of Warcraft. Back up both addon folders and
   `WTF/Account/<ACCOUNT>/SavedVariables/Olympus.lua`. Keep the backup outside `Interface/AddOns`.
2. Verify the downloaded zip in PowerShell. The printed hash must equal the first field of the
   supplied `.sha256` file:

   ```powershell
   (Get-FileHash .\Olympus-<version>-testN.zip -Algorithm SHA256).Hash
   ```

3. Turn off automatic updates for Olympus while testing. Delete the installed `Olympus` and
   `Olympus_Arena` folders, then extract the zip directly into
   `<WoW flavor>\Interface\AddOns\`. Do not leave an extra zip-named directory around them.
4. Restart the game. Confirm the addon list shows the test number and `/oly arena status` shows
   the expected build, base version, lane and commit. Record any Lua error before continuing.
5. Walk the main windows at the tester's normal resolution and UI scale, then at one smaller
   scale. Check tabs, Back, scroll areas, hover help, overlays, portraits, close/reopen and combat
   transitions. Run the built-in simulation/UI tour where it is available.
6. Repeat the critical path with gamepad mode on, then turn it off during the same session. No
   protected game window should be forced and no taint or blocked-action error should appear.
7. Check `enUS`, `ptBR`, and at least one locale that intentionally falls back to English. Look
   for clipped labels, broken format placeholders and buttons narrower than their text.
8. `/reload`, relog, and restart the client. Record what persisted and what the client discarded.
   Use `/oly bug` and, after a reload or logout, `WOW_HOST=user@pc scripts/logs.sh` for the evidence.

Rollback is also an observed gate: quit the game, remove both test folders, reinstall the current
release from the addon app, restore saved data only if needed, restart, and confirm the release
version loads without errors.

## 3. Mixed-version and multi-account session (observed)

Use the same zip and SHA-256 on every tester. Use free games and a party or raid. Bets, gold
stakes, entry-fee pots and paid Lottery tickets are not part of a beta or release. Do not bypass
the gate to test dormant financial code on somebody's real character.

The minimum useful session has two participants, an organizer, a spectator, and one client on
the previous public release. Also keep one
non-participant outside the group. Record each character, version, role, client flavor, gamepad
state and join/leave time.

Exercise a complete successful cycle before the hostile cases. Then cover, without bypassing the
buttons and functions players really use:

- a late join, leave and rejoin; `/reload` and a client disconnect during an open session;
- an older client in the group and an older client outside it;
- an unauthorized action, a repeated click, duplicate result and attempted double recording;
- a stale or delayed action, actions arriving in a different order, and a session closed early;
- an unavailable participant, cancellation, disconnect and recovery;
- gamepad and keyboard users together, combat/instance transitions, ignore/block and rate limits;
- a ten-minute burst/soak with several simultaneous users, watching queues, memory and errors.

After each game, compare the players' results and history, then compare any permitted public
summary on the spectator. An unexplained difference is a failed gate, even when the UI looked
correct. Treasury contributions use their separate, normal manual mail/trade checks; they are
not game stakes or prizes.

For the 1.2.1 candidate, include these focused live checks:

The Wanted paragraph below describes the historical 1.2.1 local-only capture path. It is
superseded for 1.2.3 and later by ordinary-member public intake. For the consolidated 1.2.4
candidate, use the Wanted checks in section 4 instead of expecting another client's own
verified observation to stay local. The installation and build instructions above still apply.

- Bones: two players exchange Players messages, then switch to Everyone with a spectator.
  Private messages must never reach the spectator. Collapse/reopen the side panel; keep an
  unfinished draft in each tab; repeat with gamepad mode. Disable spectators during a queued
  public message: it must not be delivered. The innkeeper's practice has no multiplayer chat.
  In `/oly arena sim boneschat`, check the red square/yellow arrow to the right of Sit Down,
  including while the setup covers the table. It must remain clickable above the table's
  surfaces; collapse restores the original width without an extra bar. Expanded chat must have
  no world-visible seam between it and the table. Close the preview, then check that normal
  pages show real records or honest empty lists, not sample opponents or results. Repeat with
  `/oly arena sim off`; this empty layout preview is not proof of multiplayer routing.
  After completing the innkeeper lesson, find an opponent outside an inn/camp: Find opens and
  can search, but New Table remains blocked. Meet in the same mapped inn, at a real Forever
  campfire with **Campfire Nearby** on each player, or at an explicitly registered Board camp
  (`/oly camp`, requiring location consent). For a physical fire, keep location sharing off:
  the open Play page must enable New Table when the effect appears and disable it when the
  effect disappears, without reopening. No camp post or consent change should occur. A retained
  camping benefit or a classic cooking fire alone is not enough. The first lesson still requires
  the innkeeper. In a party and within ten yards, start
  and finish a free game. Both players must see their result exactly once in Your Games,
  including after a reload. Check an older retained ledger result whose detailed companion
  history is missing; show only the details actually retained, without inventing a replay.
- Chat: hide guild names through the gear. Normal, deleted and Bones table headers must follow
  the choice without losing the draft. Tooltips and guild searches must still identify the guild.
  Reload to check persistence, then show the names again. New native chat lines follow the
  choice; previously printed native lines are unchanged. Other players see their own choice.
- The Watch: create a timeout, appeal while a councillor is offline, then overlap online later.
  The subject sees only "a moderator"; authorized staff retain the actor. A preview role grants
  no permissions. Compare current timeout, appeal and decision once, without duplicate rows.
- Wanted: each participant sends their own observed kill/death evidence to a reviewer. Unknown
  identity is not accepted on a claimed guild alone. Publish the reviewed rankings; a trusted
  relay should recover the unchanged signed word for a recipient that already pinned that
  issuer independently. A new recipient without the pin cannot bootstrap from the relay.
  Separately check local capture: with a moderator's name-only listing, a locally observed
  Horde player's recent fatal killing blow against you should learn their GUID and add one
  bounty, not two after retries. Nonfatal damage, animals, stale recaps and conflicting pinned
  GUIDs must not count. Repeat without a prior listing to check automatic own-death discovery.
  The Horde target list is local; another client's observation or Slayers publication does not
  synchronize that list. A missing local recap is not proof that no PvP death occurred.
- Weekly brief: as an ordinary member, open Realm > Your week, in five lines in the main
  window. Check five readable sections on parchment, Back, switching tabs, and reopening;
  repeat in gamepad mode. The personal brief must not appear in the Throne or as an automatic
  popup after login/reload. No sharing setting changes; the separate public Board summary
  must not reveal private dues or poll data.
- Lottery: draw Mechanostrider and check its full label above, not across, the result numbers at
  the normal and smaller UI scales. Keep the five-place animation and free tickets.

The in-addon Director checklist is the session record. Mark each item Pass, Fail or Skip with a
short observation, then copy its test report. A skip is not a pass.

## Evidence and promotion

Keep one small table for every candidate:

| Gate | Evidence | Result |
|---|---|---|
| Repository and package | commit, command log, manifest, SHA-256 | Pass / Fail |
| Windows client | client build, screenshots, `/oly bug`, saved log | Pass / Fail / Not run |
| Gamepad, locales and UI | client build and observations | Pass / Fail / Not run |
| Mixed-version session | roster, versions and report | Pass / Fail / Not run |
| Multi-account/adversarial | roster, ledger reconciliation and report | Pass / Fail / Not run |
| Rollback | release restored and restarted | Pass / Fail / Not run |

Do not describe a client or multiplayer gate as passed until somebody observed it. Do not promote
a candidate with an unexplained Lua error, an unintended recipient, a missing recovery path, an
unreconciled balance or a rollback failure.

A [CurseForge Beta file](https://support.curseforge.com/support/solutions/articles/9000197242-file-types-and-additional-fields)
is a public, opt-in distribution. Use it only after the build is safe to publish. Named or closed
testers receive the expiring test zip and its checksum directly; that test zip is not uploaded to
CurseForge or GitHub.

## 4. Consolidated 1.2.4 live checks

Use [RELEASE-1.2.4.md](RELEASE-1.2.4.md) as the candidate's behavior and limitation list.
Apply sections 1–3 for installation, checksum, exact commit, input modes and evidence. This
section adds the current checks; it does not record any of them as passed and authorizes no
publication. Record **Pass / Fail / Not run**, with the client build, exact candidate, input
mode, roles, observed result and screenshot or error log. Stop on an unexplained Lua error or
an unintended recipient.

### Start and retain evidence

After a full client restart, use these in-game commands:

```text
/oly status
/oly arena status
/oly bug
/oly perf reset
/oly perf on
```

Confirm the supplied candidate/build/commit before testing. Play the normal workload, including
the busy Chat, Census, Realm, Treasury and Games pages. Then use `/oly perf` and save its
copyable report, screenshots and `/oly bug` output; finish with `/oly perf off`.
Repeat the same workload with Olympus disabled **after another full client restart**. Record
visible stutter, worst spikes and surrounding events; average CPU or RAM alone is insufficient.
Do not claim the enabled/disabled comparison passed from a Lua fixture or a short idle session.

### Windows UI, privacy and honours

1. Run `/oly privacy`. Close it with X without changing an existing choice, reload and relog.
   Existing choices should remain; the same questions should not reopen automatically. A new
   question may be asked once. Check that the version letter follows a pending privacy page
   without repeatedly reopening a previously answered page or the main window.
2. Run `/oly profile`. Test Look, Icons, Who sees what, Letters, Back and reopening. With Games
   off, an ordinary member can still select a personal portrait fallback icon, but no Games
   sharing is enabled. Council chat icons remain restricted to actual High Councillors. Own and
   other portrait/name right-clicks open **View profile** in the normal Olympus shell.
3. On an actually authorized author client, run `/oly honours preview`. Open every gallery
   family, including gold/silver/bronze, monthly, cross, charm and Slayer examples. The preview
   must create no saved award/letter/Wanted entry, change no worn pick and consume no real
   waiting letter. An ordinary member or a role preview gets no author gallery. Close it before
   testing a real earned letter.
4. Check paper, portrait, ring, words, red seal beside the signature and all buttons at normal
   and smaller UI scales. Honour art has no duplicate dragon beneath it; rank dragons remain.
   All cross frames are larger; other-honour size normalization is not claimed complete. A
   local red-cross choice is labelled local and other clients see the ordinary chosen honour.
5. Check a newly earned eligible honour, reload, lose/regain it and change place. First eligible
   letters should not repeat; subsequent movement uses quiet notices. The King gets no letter
   from himself. The completed-month koi/Bones charm and a retained cornucopia choice need
   their own checks; do not create fake saved achievements to mark them passed.
6. Click native `[Olympus]` in chat: its input targets Olympus when writing is permitted. Test
   the native chat UI and any chat replacement separately. With mouse input and a free guild
   shortcut, an authorized High Councillor's Shift + guild key opens The Watch; existing saved
   or override bindings are not replaced. Hotkey opt-out and gamepad mode remain respected.
7. As the real King, enable location sharing in the Throne, reload, enter/leave an instance,
   and wait for the map to load. The status distinguishes configured opt-in from effective
   location availability and resumes without an off/on workaround. Games live-table settings
   remain independent. Compare the visible crown/layer on another client.
8. Repeat native kick, promote, demote and rank changes with the game's guild window open and
   an Olympus question open. No Olympus line should be inserted into native guild roster menus.
   Separately reproduce the reported network-ban attempt in a battleground with authorized
   moderators; retain the exact action/error/stack. Generic popup checks do not prove this
   previously intermittent error resolved.

### Two or more real clients

- **Wanted:** use ordinary verified members from different Olympus guilds, with capture consent
  enabled, and a spectator. Perform agreed outdoor PvP observations; run `/oly wanted status`
  on sender and receiver. A player's own observed death/kill should reach the other client.
  Retry the same evidence: one death counts once. Nonfatal damage, animals, stale recaps,
  unresolved identities and instance deaths must not count. Zero/zero entries stay out of all
  views. Compare points, kills, revenge notice/avenger actions and the bounty's reset after a
  claim. Test a proved Olympian alt link and an unlinked character separately: do not infer
  Horde account ownership or claim the unrelated two-account farming case solved.
- **Role rooms and Games:** check approved HC, GM, legate, department, Church and Watch
  audiences with one authorized participant and one excluded client. A role preview grants
  no membership. Enter must yield an echo/history entry or an explanation of failure/partial
  delivery. With many rooms, selection and drafting remain responsive. Finish a Bones game:
  participants can continue its conversation; spectators retain read-only history. Reload and
  reconnect within retention limits; a lifecycle update must not open the window unasked.
- **Guild authority:** an ordinary sister-guild master cannot send a global Crown decree,
  muster, agenda or moderation action. Their own authorized guild actions stay available.
  Verify Heraldry correspondent revocation while a message is queued. Explicitly appoint a
  member of the King's guild as Legate; an unnamed High Councillor must not gain a group merely
  from that title. Check the 25-leader cap, the group's 40-total cap and Legate self-management
  without access to another leader's group. Nomination and its quiet local notice must explain
  attendance at events, raids and wars without repeating on unrelated appointments or reload.
  Review a retained oversized legacy group: cancel changes nothing; confirm retains the complete
  old membership privately before replacing it. Check the same actions with another client and
  gamepad mode. No automatic invitations, removals or native promotions may happen. Lottery
  draws remain King/author/HC-only, with no public Lottery ranking and no paid tickets.
- **Private Justice requests:** as the actual King/HC, open The Watch > Justice requests and
  issue a deliberate request to the verified correspondent's full name and own guild. Keep the
  assignee offline initially: no received time or speed should be invented. Overlap online and
  compare the first receipt; repeat it without resetting the timer. Review the existing native
  removal dialog: cancel performs nothing; only the player's confirmed click invokes it, with
  current native permissions. Promote the subject or revoke the correspondent before accepting
  to check that the stale dialog refuses. A partial/stale roster or ordinary departure must not
  complete the request. Observe later absence, then have the original issuer explicitly review
  human-confirmed completion. Disconnect during the decision, recover and compare exactly once.
  Check local retained-report counts, unknown coverage, own-only views and inert role previews.
  There must be no public task/name list, automatic removal, global quality score or new honour.
  Have a second actual councillor recover the original issuer/assignee signatures, then take
  both originals offline and let a third authorized staff reader recover from that councillor.
  Missing first-hand original keys must remain visibly pending, not trust a relayed key. Compare
  medians and sample counts; a legacy JT1 row is local-only and cannot enter that ranking. The
  verified author may read/relay but cannot issue, confirm, cancel or remove through this role.
- **Records:** compare the participants' retained game/duel results and closed-month ranking
  after reload, later join and recovery from another holder. Exercise more than one day/month
  page where records actually exist; a full rotating page should not label older coverage
  missing. Missing halves, conflicts and untrusted seals cannot become completed evidence.
  Record what is unavailable; do not fabricate historical games or infer a full replay.
- **Church:** check retained appointments while the source is offline, then reconnect; a signed
  Apostle must not degrade from incomplete data. Check the twelfth direct missionary and
  rejection of a thirteenth for both Apostle and missionary. A 5,000-entry offline fixture
  does not establish live synchronization performance. For correspondent daily history,
  **950 does not qualify; more than 950 does**. Unknown days pause with no increment and no
  break; known nonqualifying days must follow the implemented daily rule. Compare the average
  membership tie-break. Observe a real daily boundary and a following day before marking this
  gate passed. Clock jumps or a single-day session cannot replace that observation; existing
  snapshots cannot prove a historical streak.

### Treasury, dues, campaign and private quote transfer

1. As an ordinary member, open the dues page and Privacy reminder switch. With no retained
   receipt, payment is unknown. A successful native send may show sent, but not confirmed.
   Arrange a normal contribution with a pinned Treasurer; compare partial and counted receipt
   states after actual native mail/trade intake. A manual ledger entry must not authenticate an
   unrelated later receipt. Request a retained missing receipt through the page and reload.
   Dismissing the local reminder leaves sharing choices intact and keeps reminders quiet in
   combat/instances. No automatic payment or sanction is expected. The pinned primary
   Treasurer's own native guild has a bounded private recorded-week flow: observe real start/end
   membership and complete pinned books, then compare paid, first-week tolerance and a second
   covered week below the native confirmed amount. The private notice must go to the player
   before their current native GM. Absent/capped/offline history remains unknown; a manually
   entered line or an old current roster must not create historical confirmation or a miss.
   Changing confirmed alt links, duplicate pinned books and malformed saved rows must not
   create a false notice. Other guilds are not negatively judged through census-only coverage.
   For a sister guild, its actual current signed native GM explicitly enables reset sharing
   on their guild page; default off, 31-day expiry. Compare complete native membership/confirmed
   alt groups near both real resets and the amount captured then by the primary Treasurer.
   The private checkpoint must reach only the federal Treasurer. Test withheld sharing,
   missing original keys, a changed/demoted GM, partial roster, cap, conflict, reload, retry and
   withdrawal: these must yield unknown, not a missed-payment notice. An old book opening or
   a generic restored/remote book cannot provide negative native receipt coverage. Individual
   received proofs remain positive lower bounds; no public list or automatic native action.
2. As authorized staff, inspect affiliated Treasury snapshots, let the sharer go offline and
   reload. Retained gold/items show their observation age; absent data stays unknown. Check an
   unauthorized client cannot read restricted details. Public numeric summaries must not
   disclose private donor names or item histories.
   Open Guild income and event spending as a current keeper. Explicitly attribute a completed
   native expense or receipt once; an offered/cancelled trade or failed mail sends nothing and
   adds no proof. A mail expense is sent, not delivered. Assign an actual outgoing purchase to
   a recognized guild event, then inspect that guild's aggregate as its current verified GM.
   Two ordinary census claims cannot grant this private view. Withhold sharing/revoke a role
   during a queued transfer; every piece must stop, and the authenticated withdrawal hides the
   retained aggregate. Unknown-guild income and ambiguous returned mail remain unknown, not
   guessed refunds or guild balances. No auto bank, mail, Trade or AcceptTrade is called.
3. As the actual King, start a voluntary campaign through its Treasury controls. Check purpose,
   gold/material goals and the 14-day window. As a real keeper, explicitly assign an eligible
   newly received voluntary gift. Current-week dues remain reserved; old/manual money, sales,
   transfers and custody cannot be assigned as fresh campaign gifts. Cancel confirmation, then
   accept once, retry and reload: the same receipt cannot be counted twice. Public clients see
   only aggregates. Closing needs the King's purchases note and removes the bar; it moves no
   gold or items and awards no privilege. Do not manufacture receipts to exercise these checks.
4. For a deliberately arranged same-character guild move, retain source records and run:

   ```text
   /oly carry history collect <original author-Realm>
   /oly carry prepare <destination guild master-Realm>
   /oly carry
   /oly carry offer
   /oly carry cancel
   ```

   Prepare in the source guild; cancel its question first and verify nothing is sent. Confirm
   preparation, move by a human invitation and wait for the complete destination roster. Offer
   to that exact verified master. The master opens `/oly carry`, cancels the acceptance question
   once, then explicitly accepts the pending offer while it is fresh: only their current private
   master view may show unverified quotes.
   Compare original author/time/relay against retained originals. Destination Loot/Court/Dues/
   pardons/ranks/keys must not change. Revoke queued and completed copies; delivery cancels/hides
   the quote view and replay cannot restore it. Demotion, stale roster, another guild, unknown
   alt and replacement master grant no inherited copy. Offline withdrawal delivery is not
   guaranteed. See [history-carry.md](history-carry.md) for bounds and remaining limitations.

   Test the named-heir route separately before release: the actual King and both current guild
   masters must approve the same frozen index before any character is asked to consent. Confirm
   that only consenting characters' historical records appear for the exact approving heir
   master, that private Loot moves only keeper-to-keeper, and that no rank, key, payment, pardon
   or moderation record is imported. Replacing a master, using an alt or replaying a withdrawn
   consent must fail closed.

Justice quality/composite scoring, other-honour normalization, unlinked Horde/account
anti-farming, universally portable historical office proof, linked-alt merger consent,
moderation-record transport and complete sister-guild negative dues coverage remain separate
from the implemented original-signature archives, named-heir route, response metrics and
own-guild private grace. Keep these limits distinct from every unobserved live gate above.

## 5. The Olympus Accord and BattleTag (1.2.5.1) live checks

None of these has been observed yet. Run each on Classic Era 1.15.9, TBC Anniversary 2.5.6 and
WoW: Forever 1.60.1 where it applies, and record **Pass / Fail / Not run** as in section 4. The
offline tests stub Battle.net (`BNGetInfo`, `BNConnected`), which proves nothing about a client.

1. Battle.net's answers, on each client: `/dump BNGetInfo()`, `/dump BNConnected()` and
   `/dump BNFeaturesEnabledAndConnected()`; on Forever also `/dump issecretvalue(select(2, BNGetInfo()))`.
   Expected: the second value of `BNGetInfo()` is your own `Name#digits`, and connected is true.
   On the author's PC run `luajit scripts/forever-api.lua <Interface folder> --check`: the fixture's
   `BNGetInfo`, `BNConnected`, `BNFeaturesEnabledAndConnected` and `BN_*` entries were added by
   hand for 1.2.5.1 and must match what the script writes.
2. A fresh account (no saved variables) in an Olympus guild: the Accord's letter appears about 30
   seconds after login, or when the Olympus window opens. Check the parchment, the Morpheus title,
   the scroll with the mouse wheel, and that nothing is cut at normal and smaller UI scales. The tag
   shows as `Name#****`; **Show** reveals it for ten seconds. **I accept** leads to the privacy page
   and then the version letter; `/oly status` says `accord: v1 accepted`.
3. **Not now**: Olympus stays dark (no channel, no census, no chats; `/oly status` says not
   accepted). The window shows the Accord's page; opening the window shows the letter again.
4. Battle.net disconnected, if it can be reproduced: **I accept** is greyed and the wait text shows;
   an account that already accepted keeps working.
5. The gamepad UI: open, scroll, **I accept** and **Not now** with the controller. No Lua error, no
   game popup, no taint message.
6. Two clients: log the player in first, then the moderator's (or a High Councillor's) client, or
   `/reload` it. Its client asks 90 seconds after its login and the player's answer comes up to 4
   minutes later, so **BattleTags (n)** shows in The Watch within about 5.5 minutes of the
   moderator's login, and the open page counts up as answers arrive. A player who logs in while the
   moderator is already online is reached at the moderator's next ask, up to about 35 minutes
   later. The digits show as `#****` until the page's **Show**, and hide again after ten seconds.
   Two alts of one account are grouped, and the person page says "Same BattleTag". An ordinary
   member's client never shows one. The King's client shows no part of a tag, even after the eye
   button. Answers that arrive after a `/reload` of the moderator (within about 70 minutes of his
   ask) are still kept.
7. The moderator logs off within a minute of his ask: the player's chat shows no "No player named"
   line with mouse and keyboard (with the gamepad UI the line may show: the filter stays off there),
   and his `/oly status` accord line counts `gone`. `/oly accord forget <player>` on the moderator's
   client removes that player's characters from the page.
8. Right-click a player in a guild outside Olympus (Trade, his portrait): only the Olympus version
   line, **Check version** and, when his addon does not answer, **Tell them about Olympus**. Right-click
   an Olympus guildmate: the profile, **Report to Olympus** and the Arena's lines too.
   A member of another Olympus guild who just wrote on `/ol` gets **Report to Olympus** too.
9. An update with the game running, then `/reload`: the restart message, and Olympus stays off
   until the game restarts.
10. Census: with one guildmate who has not accepted, the guild stays in the census from the others.
11. In an Olympus guild, **Not now**, then `/ol hello` or `/oly profile`: the chat says Olympus stays
    off until the Accord is accepted (`/oly accord`), not "Olympus members only".
12. Battle.net disconnected (step 4) in pt-BR too: the red note sits under "Your BattleTag:", never
    over it, and the band and the words above it make room for its second line.

A sanction that follows the BattleTag (TagFollow.lua). None of these has been observed yet. Use two
characters of one game account (S, sanctioned, and A, his alt) and a High Councillor's client (C)
that holds S's BattleTag (step 6), plus a named moderator's client (M) for the timeout steps.

13. On C: `/oly netoff S: test`. Expected: C's chat says S's sanction follows his BattleTag too
    (the count of his other characters C knows). `/oly status` on C counts `follows 1 (yours 1)`.
14. Log in as A. Precondition: S was logged in during step 13 (so the follow is in the account's
    saved file) and A is on the same realm group and faction. Otherwise the pop-up comes only with
    C's next repeat, within about 6.5 minutes while C stays online (at once if A chats on an Olympus
    channel first: C's addon sends it again), and never while C is offline. Expected: within about
    30 seconds Olympus's pop-up says a sanction on another
    character of his BattleTag applies to this one (the reason and the time, never C's name);
    `/ol hi` is refused; the Decrees tab shows the red "Your BattleTag's sanction is on you" line,
    its tooltip the same text. If A sent C his BattleTag, C sees none of A's lines, and The Watch's
    BattleTags page shows the red "Sanction follows this BattleTag" line and "same BattleTag as a
    sanctioned player" beside A.
15. On C: `/oly neton S`. Expected: at once A's chat says the sanction that followed his BattleTag
    is over, and `/ol hi` goes again.
16. M gives S a 5-minute timeout. Expected: A's pop-up starts with "This sanction was given to another
    character of your BattleTag"; **Appeal** sends (the council sees it); after five minutes A chats again.
17. With S off again: `/oly accord unfollow S` on C (or the red line's click, Yes). Expected: A is
    free within a minute while S stays off, and the page drops the red line.
18. Steps 14 and 17 with the gamepad UI on A and C: the pop-up and the stop dialog are Olympus's own
    windows, the controller answers them, no taint message and no game popup.
19. On the King's client (or the author's King preview) with the BattleTags page open: the follow's
    line and the mark show, the names masked, no part of any BattleTag.
20. A client on the CurseForge version before this release, on the same channel during steps 13-17:
    no Lua error; it hides S by name and never A.
21. After A logs out, search A's `WTF/Account/<account>/SavedVariables/Olympus.lua` for the
    BattleTag (`Name#digits`) and for its name alone: neither appears (A keeps the follow without
    its code).
22. Step 14 with its precondition unmet (S logged out during step 13, C online): A's first `/ol hi`
    goes out; a moment later A's own pop-up comes (C's addon sent the follow again for that line),
    the next `/ol hi` is refused, and C's `/oly status` still counts `derived 0`. A typing in the
    game's own guild chat (`/g hi`) never changes that count.
23. A character of the King's game account (once the King's own character logged in on it) and a
    councillor's client C that asks for BattleTags: C's BattleTags page never lists that character.
