# Church conversions

During signed rollout, a new confirmed handoff into an enrolled guild counts automatically. The recipient's client must see the native invitation and join pair and one matching character on the guild's current native roster. The keeper also needs the source's acknowledgement of the same handoff and independent strong guild-log evidence in the same scope. Scanned-player offers and earlier rolling ledger rows cannot create a conversion. The workflow counts characters for Apostles and missionaries.

## Recover a reviewed handoff

The offline signed workflow is available for recovery. It uses the exact original candidate and still requires the matching independent witness at the keeper.

1. The recipient runs `/oly church conversions review` in the destination guild and deliberately copies the appropriate candidate to the reviewer. A candidate line contains scoped in-game character and guild names, the handoff reference and times. Expired local candidates are dropped when logging in, reviewing or capturing another handoff.
2. The reviewer checks that it is the intended recruit and completed handoff in the exact guild, region, faction and realm group. If the team asks for a manual Discord check, the reviewer does that separately. Guild opt-in is its own signed decision, described in [Federation program enrollment](FEDERATION-PROGRAM.md).
3. With the author's existing key, run `python3 scripts/council-sign.py conversion-review candidate.txt`. Save one reviewed candidate line per input file. This prints a signed receipt without changing the council list. Share the receipt privately with the Church keeper who holds the strong recruiting witness for the same invite and join.
4. The keeper runs `/oly church conversions import` and pastes the receipt. The addon requires the exact scope, a current signed grant valid when the character joined, a strongly witnessed matching handoff and no duplicate. Successful imports appear on that keeper's **Church → Conversions** board, with this week's and all-time counts.

Keep candidates and receipts private. Accepted ledger rows store the credited name, scoped reference digests and timestamps. The workflow counts characters and uses no Olympus Link, account IDs or Discord IDs.

During signed rollout, members of the Church audience can open **Church → Conversions** to request the top standings privately from an online keeper in the same realm group, faction and region. A complete response carries only the keeper's ranked recruiter names and counts, the number ranked and the timestamp. It contains no recruit names, guild names or proof data. The page names the keeper whose reviews it is showing. Keepers retain separate ledgers and import their own receipts. A board reflects its source's coverage, so it cannot claim a network total or combine two keepers' copies.
