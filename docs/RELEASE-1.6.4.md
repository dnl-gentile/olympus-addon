# Olympus 1.6.4

Candidate prepared from the 23 November 2026 CurseForge and Discord review. This
document does not record publication or installed-client acceptance.

## Changes

- The internal Chat tab stays visible for Olympus members while approval or the
  native roster is unavailable. Its status explains the missing requirement and
  refreshes as data arrives. Shared history, the composer and transport retain
  their existing authorization checks; no pending or revoked guild gains access.
  Missing or partially loaded Chat modules keep the first-row restart instruction.
- The offline-player notice filters retry installation after a native API error,
  rather than remembering a failed installation as successful. Manual whispers,
  secret values, timeout boundaries and input-mode cleanup retain their checks.
  This repairs a demonstrated failure path, not every possible cause of a yellow
  offline-player notice.
- Slayer congratulations wait during combat and instances, including explicit
  letter-open paths and state changes while a letter is visible. Parking a letter
  keeps it unread and queued. State listeners are installed only for a real pending
  Slayer letter; an idle client gains no subscriptions. After first use they stay
  dormant while no Slayer letter waits. Gamepad transitions require a fresh action.
- A saved recruitment opt-in can be turned off even when the native invite right
  is false or unreadable. Church keeps the off action available and the explicit
  opt-out survives permission recovery and login. Enabling and sending retain
  their existing native permission checks.
- Recruitment discovery, routes, open drafts and final sends recheck current
  federation membership, net-off decisions and trusted local verification
  revocations. Pending or unknown verification alone does not remove an otherwise
  eligible guild. Each guild shows up to eight contacts plus the remaining count;
  online totals and the complete candidate pool remain intact.

## Validation and limits

The regression suites exercise actual addon functions in the existing simulated
client. Each behavioral fix has a case that fails against the pre-fix source.
Run `bash scripts/check.sh` on the final candidate before release. Focused tests,
static checks and documentation checks do not replace the full repository check.

Installed-client acceptance remains needed for Chat status and authorization
refresh, native offline-notice suppression without hiding manual-whisper errors,
Slayer combat/instance transitions, recruitment whose eligibility changes while
its draft is open, and turning recruitment off after demotion. No such in-game
acceptance is implied here.

A fresh outsider cannot establish an unknown revocation from the existing J2
discovery message alone. This update enforces trusted local decisions and current
eligible recommendations; it adds no unsigned revocation authority. No guild was
removed solely because a comment named it.

The review found no Olympus guild-online sound trigger. The reported tambourine's
origin remains unconfirmed and this candidate contains no sound change. Existing
guild approvals, verification deadlines and the paused warning rollout are kept.
