# Army QR in-game acceptance

This plan is for the attended OLCS2 v2 own-guild snapshot in `Olympus/ArmyExport.lua`. The shipped
source keeps `ACTIVATION_ENABLED = false`; do not turn it on in a release until the receiver named
for that release is live, reviewed and passes this plan. For acceptance, flip only that constant in
a local test copy and make a test package. Do not commit the enabled value.

## Clients and prerequisites

Run every applicable case on each interface declared by `Olympus/Olympus.toc`:

- Classic Era, Interface 11509;
- WoW: Forever, Interface 16001;
- Burning Crusade Classic, Interface 20506.

Use a browser receiver that explicitly accepts `OLCS2` and protocol format
`olympus-stat-observation-v2`, and start a new local scan so it displays a fresh 32-character
lowercase hexadecimal nonce. Use only synthetic/test guild state or a reviewer-approved live
observation. Record the exact addon commit, client build and receiver commit.

## Happy path

1. Log an Alliance character into one of the exact official branches: `Olympus`, or `Olympus I`
   through `Olympus X`. Confirm the native Guild Roster can show offline members.
2. Record the native roster total and online total. Close other roster-changing tests.
3. In the attended browser scan, copy its nonce. In game type `/oly army <nonce>` once.
4. Confirm no QR window opens in combat. Out of combat, wait for the native roster update. If Show
   Offline was off, confirm the addon temporarily enables it and restores the original setting
   after success, cancellation and timeout.
5. Scan all displayed frames. Confirm the frame label advances and wraps without a visible stall.
   Close the window and confirm it stops changing. Reopen with a new nonce; an old scan must not
   accept the new frames.
6. Before any separate browser publication/consent action, inspect the local review. It must hold
   exactly one guild and show only the canonical guild name, current realm group, observation time,
   masked total/online counts and masked class/level/rank distributions. It must show
   `sourceVerified: false` and `membershipProof: false`. Search the decoded JSON for several known
   character names and GUID prefixes; none may occur.
7. Compare every safe count with the native roster. Counts from 1 through 4 must be `few`, or the
   whole affected field/distribution must be `null` according to the masking rules. Every present
   distribution must sum to the exact reported total.
8. On a client that can report a level above 60, confirm `levels` is `null` while the independent
   total and any other safe distribution remain present.

Repeat one scan with the browser pilot's legacy `/ogarmy <nonce>` command. It must follow the exact
same gate and produce the same aggregate as `/oly army`; all documentation and new integrations
should continue to use `/oly army`.

## Fail-closed and lifecycle cases

Each case must produce no usable frame and no observation:

- missing, short, non-hex or stale-browser nonce;
- Horde, no guild, or a look-alike/nonofficial guild such as `Holypmus` or `Olympus XI`;
- missing/empty/invalid current realm-group identity;
- incomplete native roster, no exact own GUID, duplicate own GUID, zero rows or more than 1,000
  rows;
- Show Offline unavailable or still false after the client was asked to enable it;
- entering combat before completion, timeout, clock reversal/jump, logout/loading-screen transition,
  or changing guild/world during the scan.

For a world/guild transition while a QR window is already visible, confirm the window closes, its
frame label clears and rotation does not resume. Confirm a second `/oly army` cannot overlap a
pending scan.

## Resource and privacy inspection

- With no command issued, confirm no Army window, timer or permanent `OnUpdate` exists.
- While open, confirm one cancellable rotation timer is active and the QR uses merged dark
  rectangles rather than one texture for every possible module. Close it and confirm the timer is
  cancelled and all module textures are hidden.
- Reload after a scan and compare the addon's saved tables with a controlled pre-scan copy. The
  Army module must add no observation, nonce, frame, character name or GUID. Account for unrelated
  Olympus modules that may normally update their own data during a roster event.
- Capture addon traffic during the command. The Army module must emit no addon message, whisper,
  channel message, HTTP request or upload. Scanning and any later browser publication are separate,
  attended actions.

After the three clients and receiver pass, restore the test copy, run `bash scripts/check.sh`, and
make the activation decision as a separate reviewed release change.
