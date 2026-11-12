# Shared game records (1.2.4)

Bones and direct duels keep their two original signed result halves in Olympus's core saved
data, separately for each realm group and faction. Any ordinary holder can relay those halves.
A receiver normally needs each player's key heard from that player, or an already verified wallet
claim; one relay never establishes another player's identity. Unknown keys leave a bounded pending
record until a player's own key arrives. When both original players are offline, two independent
holders that already validated the exact signed record can jointly attest the original key binding.
Each holder signs its own attestation with a key the receiver heard directly from that holder, so
one modified relay cannot bootstrap an invented player or result. Attestations are heard live,
in one session: a receiver still holding a pending record names it again with each ask of its
day, for attestations alone (never the body again), so a quorum left short by one holder drawn
for an answer, or by a reload, completes in a later round. A holder declares its key once per
answer and signs each attestation when its turn on the paced low lane comes. Older clients
continue using KN/AX and their existing ranking rules.

Accepted records are a union by stable game/pair identity. Repeats add no second game. Two different
results for the same identity become a conflict only after both original signatures verify against
the established keys. Conflicting records stay for review and count in neither ranking; an
unsigned or incorrectly signed allegation cannot invalidate an accepted result. Duel GUIDs still
need the game's existing name/GUID proof before a result becomes rated.

About three holders send digests every ten minutes, regardless of network size. Each bounded
digest names the newest three record-days and rotates through older unsealed record-days in its
remaining slots. Sealed months likewise keep the newest month visible and rotate through older
ones, so years-old retained summaries remain discoverable. Reading a digest does not advance
either rotation; only an admitted send does, so a full queue does not skip a historical page.
An omitted older day or month on a full rotating page is not treated as missing evidence;
equal inventories on different pages do not provoke extra response digests. Newer evidence,
different listed hashes, and omissions from a short complete inventory still request recovery.
Missing results travel on the existing paced low lane. Large days are requested in successive hash buckets, with
at most 350 64-bit SHA-256 fingerprints per request, below the transport's assembly size.
Verification has 20 records in flight and 200 waiting; pending keys hold at most 500 records,
and each relayer has separate attempt and accepted-result budgets. Receiving a digest does not
grant authority or change any ranking itself.

Unsealed original records do not expire with the legacy half stores. Bones can reconstruct an old
monthly ranking from those records; direct duels also expose monthly win/loss totals through
`ArenaLedger.RecordMonth(month)`. Season Elo, pair/day caps, minimum duration and GUID proof
continue to use the established rating rules.

## Requesting an inventory from a ranking page (1.5.2)

The first visible games or crafting ranking opened in a session requests the record types whose
inventory has not been heard yet (`RH`). It retries once after 90 seconds if inventories
are still missing. A refused transport send does not consume the first attempt. Quiet presence
suppresses these requests. Opening a tab without a visible ranking sends none.
Each attempt carries a bounded time/attempt tag so the relay's five-minute duplicate window
does not swallow the ninety-second retry. Copies of the same attempt still count once;
receivers also accept older two-field requests, with the same reply budgets.
The relay applies its duplicate window to both local delivery and forwarding between relays;
an unchanged inventory can circulate again after that window expires. Recent copies remain
suppressed, so discovery is eventual and still depends on inventory rounds, budgets and peers.

Holders schedule replies using the existing spaced digest rounds and low-priority queue. Each
holder begins at most one reply round per type per minute, even if many players ask; equivalent
inventories suppress redundant replies. Original records and their two-holder signature checks
are unchanged. This helps discover records held by online peers; it cannot recover data no
connected client has retained. Clients predating RH still use their periodic inventory rounds.

## Closing a month

Seven days after a month closes, `/oly arena records` shows that client's unsigned monthly
requests. A request includes the realm group, faction, game type, month, number of players and
SHA-256 of canonical totals. The author reviews the actual totals before signing it:

```sh
python3 scripts/council-sign.py seal 'RS1~...'
```

This prints a signed seal using the existing council key. It does not change the key, council
membership, leadership authority or council output. No test reads the author's key: the round
trip generates a temporary key and removes that temporary folder afterward.

Paste the signed result with `/oly arena records seal`. Anyone can relay a genuine seal and its
totals, but only the existing author's public key can authorize it. The receiver adopts the totals
only after their complete text matches the signed hash and row count. Only then can original
records older than 62 days in that month be compacted; the authenticated monthly totals remain.
A seal without matching totals permits no deletion. Totals assemblies are bounded and kept long
enough for the client's paced transport.

## Client checks still required

Use two players and an ordinary observer. Complete one free Bones game and one direct duel with
the King's live switch off; each result should appear once, survive reload, and remain ranked.
Join a later observer that has heard the players' keys; a holder's digest should bring the signed
results over the low lane while the ordinary chat and invitations stay responsive. A later
observer without those keys should show pending records and accept them only after the players'
own key declarations. Also test mixed 1.2.3/1.2.4 clients, including the old KN/AX repeat path.

Inspect an old month's request and test a temporary signed seal with mismatching totals first:
its original records must stay. Once the exact authenticated totals arrive, the old originals
may compact and the month must keep its podium and totals across reload.
