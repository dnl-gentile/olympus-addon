# Olympus 1.1.2 / layerfix.1

Local test build based on upstream tag `v1.1.2`, commit
`d75e12f850f0caaea94d48a0c593116b5e200acb`. It keeps the upstream message
protocol and `ns.VERSION`, and identifies the fork with `X-Local-Build` in the
TOC and `/oly hop status`. This is not an upstream release.

## Changes

- A hop succeeds only on its requested zone and layer. An intermediate/wrong
  layer no longer triggers automatic group departure.
- Automatic departure requires two distinct NPC GUID readings within 15 seconds.
  Target or mouse over two nearby NPCs after joining the helper. These are local
  observations; Blizzard still controls transfers and the readings are heuristic.
- Destination readings arriving before the group roster event are checked when
  the group is recognized, and on the existing one-second ticker.
- Delayed offers, invite requests and the Invite button recheck location,
  opt-in, combat, group capacity and expiry before inviting.
- Queued requests stop when the zone or group changes. An early decline waits
  for later helpers until the original 15-second collection deadline.
- A stale local reading no longer blocks an explicit request as "already there."
- Roster replacement, a delayed release and an old leave dialog cannot cause a
  cancelled hop to leave an unrelated group.
- Pending helper bookkeeping is pruned. Reporting a timeout or leaving without
  evidence no longer claims that the desired transfer succeeded.
- The Realm's layer section has an alternative-layer action, progress and cancel
  controls, and report-age tooltips.

## Commands

| Command | Behavior |
| --- | --- |
| `/oly hop` | Existing request for the King's layer. |
| `/oly hop list` | Known layers in the current zone, report counts and latest age. |
| `/oly hop <zone UID>` | Request one listed layer; these are zone UIDs, not layer 1/2 ordinals. |
| `/oly hop any` | Request the most recently reported different layer within 10 minutes. Requires a recent local reading. |
| `/oly hop status` | Local build marker, progress, last NPC reading and channel readiness. |
| `/oly hop cancel` | End local hop tracking; keep the current group and leave late invites to the player. |

Report counts are the add-on's sample. They are not population, latency or
available-helper counts. `any` does not promise a quieter layer. It sends one
ordinary request; there is no new channel scan, broadcast loop or automatic retry.
Cancellation cannot recall an invitation already sent by another player's client.

Helpers still need both location sharing and layer help enabled. Preferences
remain opt-in. A requester can keep their own layer private, although requesting
a hop discloses their zone and desired layer under the existing protocol.
The add-on does not bypass server cooldowns, faction/realm restrictions or
instance restrictions. Fixes on the helper side apply only when that helper
runs this build. Existing helpers can still answer its unchanged messages.

## Install and undo

Exit WoW. Copy the current `Interface/AddOns/Olympus` folder somewhere outside
`AddOns` as a backup, then replace it with the `Olympus` folder in the test ZIP.
Keep the folder named `Olympus`; do not load a second copy. Start WoW and check
`/oly hop status` for `layerfix.1`. Keep existing SavedVariables.

To undo, exit WoW and restore that backup (or reinstall official 1.1.2).
No new saved settings or database migration are introduced. An add-on manager
update can overwrite this local build.

## Validation

Run `bash scripts/check.sh` with Bash and LuaJIT as in `AGENTS.md`. Added coverage
is in `tests/hop-regressions.lua`, loaded through the existing `WithHop` fixture.
The backoff test now explicitly waits for the original collection deadline
after an early decline: this is the intentional new late-offer behavior.

Offline tests simulate WoW. Before calling this live-verified, test on the
installed Forever beta build (observed executable: 1.60.1.70124):

1. Two Olympus members, same faction/realm/zone, different observed layers.
   The helper explicitly opts into location sharing and layer help.
2. List layers and request the helper's UID. Check collect -> invite -> join ->
   confirm. The default `/oly hop` should still select the King's layer.
3. Read two different nearby NPCs after joining. Confirm the requested UID,
   departure from the temporary group, and that the UID persists afterward.
4. If an invite does not cause a transfer, verify the build says it is unconfirmed.
   Test a wrong intermediate UID, sparse NPCs and a server-imposed delay.
5. Have the helper change layer, enter combat, fill the party or turn sharing/help
   off between offer and request. No stale invitation should be sent by this build.
6. Cancel while queued and while joined, change zone, and join a friend's group.
   Verify no automatic acceptance/departure changes that group.
7. Test a stock 1.1.2 helper and controller mode. Check chat errors, `/oly bug`
   locally, and the Realm section's layout. Do not send bug reports automatically.

This build has not been installed into the running client or tested with live
players. Server transfer behavior, protected UI actions and controller rendering
remain unverified.
