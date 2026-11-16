# Olympus 1.6.0

Church recruiting stays with the player who starts it. This release keeps automatic
invite-command popups and removes the invitation handoffs that players reported as
unwanted messages and spam to other guild members. The usual in-game census works
without a desktop companion or API setup.

## What changes

- **One recruiting queue:** Church → Invites brings JOIN requests and observed
  candidates together, with Start/Pause, Prepare and Skip/Next. Advertising is optional.
- **Level and class filters:** set an inclusive range and select classes directly
  on the recruiting page. Both candidates and JOINs use the same saved filters.
  Unknown required details wait for a deliberate WHO check or target/mouseover
  observation. An excluded request does not hold up later eligible popups.
- **Movement-safe prompts:** an automatic window does not take keyboard focus.
  Click the command when ready to copy, paste and send it yourself.
- **JOIN recovery:** a request postponed by typing, combat or another window retries
  with scanning off. JOIN after an ordinary reply becomes an invite request once.
- **Census leadership stays visible:** newer guild totals no longer hide retained
  GM, Captain and rank details. Their original report age remains visible; an old
  online claim is not refreshed by a new total. Clients that have never received
  a detailed guild report still show that the information has not been reported.
- **Better diagnostics:** Help → Report a bug records Blizzard blocked/forbidden
  action warnings and nearby recruiting/UI state for troubleshooting.
- **Engineering documentation:** [docs/README.md](README.md) maps the application's
  modules, data, networking, UI, recruiting, diagnostics and development workflow.

## Install and test

Extract `Olympus-1.6.0.zip` into the active game's `Interface/AddOns` directory so
`Olympus`, `Olympus_Arena` and `OlympusSiteAggregate` are direct children. Restart the
game after installing. This fork's GitHub release does not update CurseForge listings.

The built-in relay version list includes 1.6.0. Older relays, or relays using signed
rules that omit 1.6.0, can refuse this version after their admission deadline. Their
maintainer must publish updated signed rules or update the relay as appropriate;
this package does not alter or bypass those signed rules.

Use [the recruiting acceptance checks](RECRUIT-QUEUE.md) on US PvE. Also open another
guild in Census after receiving a detailed roster and then newer census totals: the
GM and Captains should remain visible, with the detail age. A guild with no detailed
report should show “not reported yet”. Confirm a subsequent changed roster replaces
old leadership and that a stale report does not claim someone is online now.

Offline checks model the game. Live chat delivery, controller navigation and
communication between real clients still need in-game verification.
