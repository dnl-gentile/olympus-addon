# Scoped federation authority

This is a review candidate. No real certificate has been issued, private key shipped,
existing approval reset, or external service activated by this change. The existing
Verify guild approval remains the participation decision; there is no second guild
enrollment list. Personal Discord verification is a separate flow.

## Authority and setup

`/oly federation key` copies a public request bound to the exact character, native
region, ruleset and faction. The existing account Ed25519 seed remains local.
After checking the exact character's existing role, the author signs a JSON file:

```json
{
  "request": "FKQ1~US:ForeverPvE:Alliance~Silver Rock-CAMWOWUS1Realm2PvE~PUBLIC_KEY_FROM_THE_REQUEST",
  "role": "council",
  "guild": "-",
  "issued": 1795000000,
  "expires": 1795604800
}
```

This fictional example is deliberately not a usable certificate. Use current Unix
times, a real public request and a reviewed role (`council`, `treasurer`, or a
guild-confined `operator`). The certificate interval is at most 31 days. A council
certificate still requires the currently signed Council/author identity; a Treasurer
certificate requires the current primary signed Treasurer. Neither grants a title.

Confirm the exact request bytes with that character through an authenticated native
game sender or an already established signed identity. A Discord display name or a
forwarded text request is not identity proof. The signature authenticates the authorized
attestor and message; it cannot prove that an authorized modified client reported a
truthful native event. Revocation and the staff appeal process remain necessary.

```sh
python3 scripts/federation-sign.py reviewed-public-key.json > reviewed-certificate.txt
```

The signer reads the existing `OLYMPUS_COUNCIL_KEY` or council-sign.py's default local
key path; it never writes or prints the private key. Import the public result with
`/oly federation certificate`. Do not commit actual identity lists or private keys.
The Treasurer can then publish informational milestones without asking the author
to sign each edit. Council can sign appeals and harboring decisions. An operator
cannot publish either of those or a Treasurer milestone.

A caretaker with a current council certificate and native rank 0 may give the exact
native rank-1 working GM a guild-only FK2 delegation. The request includes proof of
possession and uses the exact native whisper sender; a relay cannot substitute a name
or key. It expires within 30 minutes, never beyond its parent. Issuance and native
publication recheck the current complete roster and actual ranks.

For a remote guild, the signature is the rank attestation; generic census officer
rows are insufficient. Remote demotion cannot be observed instantaneously. A fresh
own-guild roster overrides the grant, and short expiry/revocation bounds remote use.
Direct author-issued operator certificates are explicit guild-only authority grants;
use short reviewed intervals and revoke them when the working GM changes.

## Decision lifetime and review choices

FA1 decisions are signed, scoped, at most seven days long, and **never outlive their
issuing certificate**. An expired delegation cannot publish a backdated long-lived ban.
Council-issued decisions can last up to seven days; an FK2 operator observation is
temporary, at most the remaining 30-minute grant. It is not a permanent federation ban.
A caretaker reading the same exact native event can issue its own longer-lived decision.
Persistent sanctions beyond these intervals require Council renewal or the existing
reviewed author-signed FUG1 snapshot. This intentionally avoids inventing a trusted
timestamp or silently granting permanent authority to a delegated operator.

The review must approve the proposed **24-hour harboring grace** and these bounded
sanction periods before issuing certificates. The source request did not specify a
grace duration. A guild approval remains stored even while shared access is suspended.
The code does not kick people from WoW, alter native guild permissions or activate the
old verification/exile warning rollout.

## Native observations, appeals and harboring

New automatic kick decisions require the local fresh complete roster, native staff
rank 0/1, an exact native removal event no older than 48 hours, and exact same-scope
names for both actor and target. Prime permits any native kicker; other guilds require
the recognized working GM or caretaker. A voluntary quit, inferred short name, remote
census, foreign scope, missing certificate, or stale roster never mints a ban. Native
records are deduplicated; a failed publication can retry. A native event predating an
accepted pardon cannot recreate its ban on reload.

Native relative age has only whole hours. The client uses a conservative earliest
bucket and confirmed linked identities when comparing a kick to a pardon, including
again after queued signing. A near-hour ambiguous removal requires staff review
rather than being treated automatically as a new post-pardon event.

Known confirmed alt links can match a signed fugitive. Unknown alts and account
identities cannot be inferred. `/oly fugitives appeal` retains Court routing.
`/oly fugitives pardon Exact Name-CAMWOWUS1Realm2PvE` requires current Council signing
authority; a working GM cannot pardon unilaterally. Newer pardons override both older
delegated decisions and matching legacy-list entries, including through known alts.

The caretaker's harboring audit requires at least two fresh observations, a full day
with the same outstanding matches, and a successfully displayed daily notice. Only
the current native rank-0 caretaker with Council authority can publish suspension.
The client renews a still-supported suspension near expiry and publishes a clearance
after a fresh full roster is clean. Missing evidence does not invent a suspension.
Control-plane recovery, approvals and appeals remain available during suspension.

## Propagation, revocation and performance

Transport uses chunked private addon whispers, normal queues and dispatch guards,
not an unsigned origin label. Recovery rotates peers once a minute; one reply has at
most four records, per-peer and global reply limits apply, and cryptographic receive
work runs in the existing frame-budgeted Ed25519 worker. The census lane retains its
existing scheduling. Native publication is also deferred and bounded. Exact-key
lookups avoid rescanning every decision for every roster member.

Newer decisions replace older ones deterministically, with replay floors retained
through the full decision window. Root revocation uses a signed FKR1 tombstone:

```json
{"scope":"US:ForeverPvE:Alliance","issued":1795000000,"certificate":"EXACT_LOWERCASE_CERTIFICATE_SHA256"}
```

```sh
python3 scripts/federation-sign.py --revoke reviewed-revocation.json > reviewed-revocation.txt
```

Import through the same certificate dialog. Recovery includes signed revocations
ahead of decision records; revoking a parent also invalidates its delegated children.
There is no immediate delivery guarantee to an offline or disconnected client. Old
addon versions and manual commands while the addon is disabled remain platform limits.

## Required native acceptance

Use two participating guilds and current installed clients. Confirm exact native
removal identities, role demotion while queued, grant expiry and renewal, cross-realm
chunk delivery, retained approvals, pardon/replay after reload, known-alt matching,
daily notices, harboring grace/clearance and suspended recovery. Repeat the key import
popup with gamepad mode on and across both input-style transitions. Offline crypto and
simulated clients do not establish these real-client outcomes.
