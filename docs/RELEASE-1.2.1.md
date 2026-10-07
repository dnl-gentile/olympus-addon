# Olympus 1.2.1 candidate

This is a local candidate, not a published release. Automated checks and live multiplayer checks
are separate gates; use [the beta checklist](BETA-TESTING.md) for the latter.

## Player-facing changes

- Bones has a collapsible chat beside the table. **Players** is for the two players; **Everyone**
  is for players and spectators when the table permits watching. It reuses the main chat's
  bubbles, name marks, input border and tab style, with separate drafts. Innkeeper practice does
  not pretend to have a multiplayer room.
- The Chat gear can hide guild labels beside sender names locally. Guild identity remains in
  tooltips, searches and message evidence; permissions and transport are unchanged.
- The Watch's notices identify **a moderator**, not their name. Authorized staff keep the actor
  in their audit. Retained unresolved appeals can retry when council members come online later;
  a failed queue submission no longer permanently marks an appeal as sent.
- Wanted publication no longer fails the real communication queue's guard validation. Trusted
  peers can relay an unchanged signed Slayers ranking to a client that already independently
  pinned its original issuer. Relay never supplies that initial trust or silently rotates a key.
- Wanted evidence requires verified membership and positive identity for the sender's own kill
  or death. A claimed guild or an unknown GUID is not enough. Evidence still needs human review.
- The Board offers a public weekly summary of facts this client knows. A personal five-line
  brief appears once per character/reset after privacy notices and the update letter, never in
  combat, an instance or Busy mode. Unknown coverage and receipts are shown honestly; opening
  the brief does not turn on sharing.
- The King may leave a short message with an audience. The recipient retains it in their local
  Chronicle with its sender; this does not create a jury or another punishment system.
- Invitations through the addon warn about a character blocked from the network, with a reason
  and date. The officer still chooses; native guild invitations are not silently declined.
- The race chat's short label is **Skyborn**. Long Lottery animal names stay on one line above
  the drawn numbers, with the original five-place animation kept.
- The detailed update parchment uses the existing game icons. For someone who has not seen the
  1.2.0 letter, that release's news comes before 1.2.1. The history keeps each letter separately.

## Reliability and review work

- Bones resync cannot invent the local player's decisions; reload retains locally witnessed
  retry proof. An opponent's instant departure claim is not accepted without local observation
  of the full grace period.
- Crafting accepts a sequence only after validating the actual payload and state. Arena profile
  history has a real bound. Church appointment and seen-check authority no longer comes from
  a claimed census rank alone.
- Remote rehearsal enrollment is off until the player explicitly permits it. Turning it off
  leaves an enrolled participant locally or closes their own directed session. No gold rehearsal
  bypasses the shipped financial gate.
- Photo-tour rolls no longer replace the game's global roll function. Innkeeper handoff waits
  for the native conversation to close and keeps the addon-only gamepad route.
- The test simulator isolates each client's popup/slash registrations, preventing old worlds
  from being retained by later clients. Diagnostic timing is optional; assertions and gameplay
  scenarios are retained. Affected runs include the complete Bones/Farkle regression family,
  while shared chat changes still require the full gate.

## Games stay free

No bets, gold stakes, paid Lottery tickets or entry-fee pots are enabled. Every package profile
excludes wager-only modules. Dormant local implementation is not a promise of a future release.

## Limits that must remain visible

Display privacy is not wire anonymity: clients receiving a moderation packet can inspect its
server-stamped sender. Previewing a staff role grants no real permission. Old appeals without
retained text cannot be reconstructed, and target self-testimony is not independent proof of a
moderator's action.

A new Wanted recipient without an independently pinned issuer cannot bootstrap from relay.
An unknown evidence identity is refused rather than placed in an unverified reviewer inbox;
the sender's original local observation stays saved. There is not yet a reviewer acceptance
receipt or guaranteed same-session automatic retry.

This candidate does not claim that every longer-term governance, recruitment, identity-backend
or contribution proposal is implemented. It must still be checked in the actual supported client
and across real players before publication.

## Private test installation

Use the filtered test package, not the raw source tree. Close the client and keep a recoverable
backup of both addon folders and SavedVariables **outside AddOns**. A private installation may
contain CouncilList.lua, LinkCA.lua and DevPerf.lua: preserve those files and restore only their
needed entries into the new TOC. Do not restore the old TOC wholesale. The generic deploy script
replaces both folders and does not perform this private-file preservation; do not use it for
this installation.
