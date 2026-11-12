# Private history carry for 1.2.4 testing

This is a bounded, opt-in archive for the **same character** moving manually between
Olympus sister guilds. Older quotes remain unverified. A separate XC2 path preserves
original signatures after independent first-hand key confirmation. The separate XC3 named
merger route is described below; neither route certifies an old office merely from a current
title. No row enters Loot, Court,
pardons, Dues, ranks, keys or another authoritative ledger; no invitation, kick,
punishment or payment action is performed.

## Player flow

1. Before preparing, collect available original declarations with
   `/oly carry history collect <original author-Realm>`. The original must answer
   directly, and the key must bind to that server-stamped character through native GUID
   evidence. A relayed self-signed name/key cannot establish first-use identity.
   Ordinary collection excludes private Loot and moderator records.
2. While still in the original guild, with a current complete roster, run
   `/oly carry prepare <destination guild master-Realm>` and confirm the question.
   The destination guild master must have a current signed role or pinned King identity
   accepted by `Data.AuthorizedRank`; an ordinary census claim is insufficient. If this
   authority is unavailable, preparing is refused. Nothing is sent at preparation.
3. Arrange the guild move with the officers and accept the game's manual invitation.
4. Once the destination's roster confirms this character and its same verified master,
   open `/oly carry`, then choose **Offer prepared quotes** (or `/oly carry offer`).
5. That master opens `/oly carry`, reviews the warning and explicitly accepts the
   copy. Offers expire after three minutes. Queued messages recheck guild, identity,
   complete roster, authority and revocation before every native send.
6. The moved character can choose **Revoke this transfer** or `/oly carry cancel`.
   Revocation cancels pending data and sends a private withdrawal to the same recipient.
   The receiving client hides its copy and retains a replay floor when it hears withdrawal.
   This is an ordinary addon whisper: delivery to an offline recipient is not guaranteed.

The view is private to the exact consenting guild master's character, while still verified
as that character's current own guild master and while the quoted subject remains in the
current complete roster. A replacement master or an alt receives no inherited copy.
There is no automatic transfer between characters, even a confirmed alt.

## What can be quoted

- Private Loot is never collected, quoted or exported through the member. After the
  member's consent token, the current source guild master confirms direct transfer and
  the current destination guild master separately accepts. Original signed notes retain
  their signatures. Older unsigned notes become an explicit present-day source-master
  witness, not a signature impersonating their alleged original author. Moderator
  material is excluded even when the UI could have hidden the actor's name.
- This character's retained Court messages only, read through `Court.Messages()`;
  other people's Chronicle entries never enter the snapshot. The retained reference
  preserves the original server timestamp and the row also keeps its observation time.
  An unknown source guild stays unknown.
- A currently cached pardon observation, if present: its first observed local time only.
  That cache cannot establish the King's original deadline. No end date is calculated
  and no pardon is applied in the destination.
- If `Dues.PayerReceiptFacts(week)` is present, the current character's retained private
  pinned-Treasurer receipt facts for up to the retained five weeks. Issuer, source,
  sequence, week, original time, copper and amount remain quoted provenance. Relaying
  those facts does not authenticate the relay or create a new payment confirmation.

The older XC1 quote copy holds at most 24 rows and 4,096 encoded bytes, split into at most 24 private
180-byte fragments, each with its own bounded `XC~1` envelope. An oversized snapshot
is refused, not silently imported partially. Pending offers (8), saved imports (32) and
durable replay/revocation floors (128, including pending reservations) are bounded.
Reaching a retention limit refuses new work. No public or outsider chunk assembler is
extended; existing Comm member admission, server-stamped sender and queue guards apply.

XC2 retains at most 256 bounded declarations and 64 enrolled original keys per scoped
character. Archives use per-record fragments and receiver acknowledgements; they do not
silently truncate a batch at the transport's 34-chunk limit. A final acknowledgement is
separate from enqueueing. Expired offers are pruned, and early withdrawal creates a
durable floor before a delayed offer can arrive. Limits also apply per sender.

Original Court, native receipt, Loot write/removal and royal pardon declarations are
captured at their actor-owned source event. A new pardon declaration preserves its
original declared expiry; older ordinary-reader caches remain observations, never a
reconstructed royal deadline. A signature verifies the signing identity and its exact
declaration, not historical office or the truth of an unobserved event. Unknown original
keys remain visible in the archive with a direct-key confirmation action. A fresh witness
does not upgrade an old quote to original authorship. Scope/current-reader consent is
rechecked after cryptographic work and before sending.

## Named guild merger: a separate frozen archive

Before the source guild folds, its actual current native GM opens `/oly carry merger prepare
<exact heir guild master-Realm>`. The actual King, the source GM and that exact current heir
GM each review and sign the same frozen record index (OLYCM1), source/destination guilds and
private reader. This requires current signed role material and firsthand native character/key
binding. A census claim or a key forwarded in a packet cannot establish authority. The King
must be the pinned actual King of the connected realm group, not someone whose title looks
similar. `/oly carry` displays the mandate, three approvals and per-character progress.

Each subject separately consents to that exact source/destination archive. The subject receives
no private Loot; keepers send only retained records included in the frozen index to the exact
approving heir GM. Per-record hashes, original signatures and dates are retained. An older
unsigned note stays a visibly labelled present-day witness declaration, never a signature
impersonating its alleged author. The approving heir GM can resume stored partial progress
after reload; a retry retains the same root, subject consent and reader scope. A replacement
master receives no inherited permission. Revocation cancels queued work and hides received
records when delivered, with durable replay floors.

After the source folds, its source keeper must still manually remain/join Olympus to use the
ordinary private transport; no outsider exception is added. The historical mandate proves only
what was approved before dissolution. It imports no office, key, active pardon, payment status
or points and reconstructs no lost record. Alts and moderator material are still excluded.

## Validation and remaining live checks

`OLYMPUS_TEST_FILTER='carry:' luajit tests/run.lua` exercises the actual Carry functions,
Comm dispatcher and scheduler, Loot book and Court/Chronicle readers. Coverage includes
both consents, sender/recipient forgery, other-character subjects, missing consent,
faction/realm scope, replay, conflicts, revocation, expiry, malformed/oversized packets,
bounded state, stale rosters, role/guild changes and cancellation before native send.
The binary SHA256 digest failed transport tests, so the digest goes out as hexadecimal,
which restores successful bounded packets. A signed destination role also keeps the
multiple return values that the Lua `and` expression discarded.

`OLYMPUS_TEST_FILTER='carry-history:' luajit tests/run.lua` adds actual Ed25519 account
signing and native GUID binding, source-event captures, 12-record archives larger than
34 transport messages, direct-key recovery, loss/retry/ACK, scope/cancellation after
crypto, private staff-only Loot and consent-only members. A regression against the
pre-fix Carry source proves that a retained private Loot note could previously enter
the member's quote export; the new path refuses that leak.

`OLYMPUS_TEST_FILTER='carry-merger:' luajit tests/run.lua` exercises the actual mandate,
original Ed25519 declarations and signed role proofs, native identity binding, private Comm
sanitization, frozen index and hashes, each subject's separate consent, pages/ACK/retry, saved
progress, cancellation, scope changes and admission after a source guild folds. Mutation
regressions cover stale native GM rank, historical source admission and missing resume action.

Run the consolidated `bash scripts/check.sh` after integration. The gamepad session pass
loads the TOC and exercises all Olympus dialog definitions through existing dialog flows;
the carry consent questions use Olympus's own dialog in both input modes.

Still needed in the real Forever client, with two players and retained source records:

1. Verify the signed/pinned destination identity before preparation, then cancel the
   preparation question: no outbound offer or private data should appear.
2. Prepare as an ordinary member, move manually, and verify the new complete roster.
   A stale source roster, a demoted destination master or an unknown alt must not send.
3. Offer and cancel the master's question: no records should arrive. Offer again and
   explicitly accept; only the exact current destination master should see unverified
   quotes. Other members, Lords of another guild and replacement masters see none.
4. Compare original Court/receipt declarations and their timestamps against source records;
   an unknown original key stays unverified until directly confirmed. For private Loot, the
   member initiates consent but receives no notes; source and destination masters separately
   confirm their direct staff route. Compare original/witness attribution on the destination
   master only. A receipt changes no payment status; a declared pardon expiry creates no
   active pardon. Loot books and the destination Chronicle remain unchanged.
5. Revoke during a longer queued copy, then revoke a completed copy. Data stops, the
   accepted view disappears once the withdrawal arrives, and replay cannot restore it.
   Check what happens with an offline master; no guaranteed delivery is claimed.
6. Reload each client, switch guild/role, and use mouse/gamepad input modes. The saved
   copy keeps the same private reader boundary and both consent windows fit/read well.
7. For an intentionally arranged merger, prepare before the source folds. Cancel any one of
   the three approvals: nothing may be inherited. Compare the frozen index on all approvers,
   then approve all three. Cancel one subject's consent: that person's records must not arrive.
   Transfer another consenting subject, reload halfway and resume. Compare timestamps,
   signatures and witness labels, then revoke. An excluded member, alt, successor GM or
   outsider must see no private Loot or inherited records. No guild, status or ledger changes.

No Windows install, live multiplayer acceptance, publication or release is implied by
offline checks or this implementation.
