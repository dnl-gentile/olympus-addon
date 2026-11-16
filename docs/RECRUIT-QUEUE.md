# Recruiting queue

Church → Invites opens a single queue. Start is an explicit opt-in: it enables the
existing in-game scan and automatic local invite-command popups for JOINs and scans.
An existing player's popup settings remain available through Advanced; choosing Advanced exits
queue mode and resumes those settings. Back returns to the queue view; Start adopts
queue mode again. Advertising is separate and is never enabled by Start.

JOINs precede untouched scanned players. A JOIN and scan for the same character
appear once. Automatic popups are spaced at least 15 seconds apart, never replace an
open recruiting draft, and never take keyboard focus automatically. Movement keys
remain in gameplay; click the command or Prepare invite when ready to copy. JOINs come before scans. Each
row is offered once; Prepare can reopen its existing invite dialog. The player still
copies and sends the command or uses the game's invitation controls. Preparing is not
evidence of an invitation sent or a player joining. Only the current guild's fresh
roster confirms a join. A changed or expired candidate cannot be prepared.

Skip/Next sends no message and does not refer anyone to another recruiter. Skipped
scans stay suppressed for that scan session. The player's own later JOIN can bring
them back. Existing duplicate filtering and seven-day decline suppression remain;
decline detection still depends on the client's supported system-message strings.
This build does not add missing client strings to the offline fixture.

Pause closes recruiting drafts, stops automatic invite popups, suppresses ad
reminders, and stops collecting new scan candidates. Incoming JOINs can still wait in the queue. Preferences survive
reloads, but names and requests remain session-only with their existing expiry
times. No external companion, API service, or local database is required.

The paste watcher retains its 0.01-second check while chat is open and uses
0.25 seconds while closed. Opening chat through the copy dialog starts a fresh fast
watch. Closing the draft or switching to gamepad stops it. Reading pasted text only
closes the draft; it never sends a command or proves that an invitation succeeded.

## Offline checks

Run from the repository root with Bash and LuaJIT:

```sh
OLYMPUS_TEST_FILTER='gamepad unified recruiting' bash scripts/check.sh
OLYMPUS_TEST_FILTER='gamepad recruit movement focus' luajit tests/run.lua
OLYMPUS_TEST_FILTER='gamepad blocked diagnostics' luajit tests/run.lua
OLYMPUS_TEST_FILTER='recruit invite (review of 1.5.8)' luajit tests/run.lua
OLYMPUS_TEST_FILTER='recruit scan (review of 1.5.8)' luajit tests/run.lua
OLYMPUS_TEST_FILTER='recruit scan (1.5.9)' luajit tests/run.lua
OLYMPUS_TEST_FILTER='recruit referrals removed' luajit tests/run.lua
OLYMPUS_TEST_FILTER='gamepad Census offer: Turn on all' luajit tests/run.lua
OLYMPUS_TEST_FILTER='gamepad Church > Invites' luajit tests/run.lua
OLYMPUS_TEST_FILTER='gamepad attended recruit candidate queue' luajit tests/run.lua
```

The new gamepad scenarios exercise real addon functions and owned UI rows, both
login styles and both switches, JOIN priority and deduplication, pause/reload,
stale actions, a fresh roster confirmation, and paste-watch scheduling. The older
Church layout and candidate-list scenarios explicitly select Advanced to exercise
the preserved controls. Their removed handoff assertions now require those controls
to be absent. The Census offer also no longer advertises the removed handoffs.
The polling and obsolete-notice regressions both fail when their respective fixes
are removed in a scratch copy, and pass with the fixes.

## In-game acceptance still required

1. In US PvE, open Church → Invites as a member allowed to invite. Start once;
   nearby unguilded sightings should fill the queue and offer a local invite popup.
2. Have another player whisper JOIN. It should precede an untouched scanned
   candidate, with no duplicate if that player was also scanned.
3. Prepare, copy, paste and press Enter yourself. The panel should say prepared
   until the player's acceptance appears in a refreshed guild roster. Try a refusal
   and a candidate who joins another guild before preparing.
4. Pause with a request pending. New JOINs may queue, but new scanned candidates
   and ad reminders should stop. Reload while paused; it should stay paused.
5. Resume and use Skip/Next. Verify neither the candidate nor another guild member
   receives any message from these actions.
6. Hold WASD, arrow keys and custom movement bindings while an automatic draft
   appears, including movement against a wall. The command must remain intact,
   movement must continue, and native chat must stay closed. Click the command or
   Prepare invite before copying. Test both input modes and switches with a draft open. With gamepad, use the
   game's own invitation controls; Olympus must not open native chat. With mouse
   and keyboard, test quick paste/Enter, closing empty chat, and copying again.
7. Opt into an ad reminder separately, then pause. No reminder should open while
   paused; resuming should preserve the chosen reminder interval.
8. If Blizzard displays a blocked/forbidden-addon warning, open Help → Report a bug
   before reloading. The report should identify the refused function, attributed
   module, test build/commit, input mode and recruiting state, plus recent local UI
   actions. Repeat the warning after changing input mode or closing the draft: its
   count should increase and its latest context should change while the first stays.
   Reload/logout normally and verify `OlympusDB.actionsBlocked` in
   `WTF/Account/<ACCOUNT>/SavedVariables/Olympus.lua` retains the record. Logging does
   not fix the underlying blocked action; send the copied report for diagnosis.

Offline API models cannot establish live server acceptance, real chat delivery,
controller navigation quality, or account-policy approval.
