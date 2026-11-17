# Federation fugitive list

The author signs decisions for a particular Forever region, ruleset and faction after review. The addon applies a current list in guilds with a current signed federation enrollment. The list carries exact game character names and their native realms. Keep appeal notes, account identifiers and other evidence in the staff process.

Create a local JSON file with the desired **complete** list. The following example uses fictional characters and dates. Replace the times before signing.

```json
{
  "region": "US",
  "group": "ForeverPvE",
  "faction": "Alliance",
  "revision": 3,
  "issued": 1795000000,
  "expires": 1795086400,
  "names": ["Amber Vale-CAMWOWUS1Realm2PvE"]
}
```

Use the region from the native realm name. Use a revision greater than the last published revision for the same region, ruleset and faction, including expired revisions. `issued` and `expires` are Unix seconds, at most 31 days apart. The client uses the game's server time to reject a future or expired list.

Run the existing author's signing setup against this file. The command uses the same default key file as `scripts/council-sign.py`, with `OLYMPUS_COUNCIL_KEY` available to select the established key path. It creates a new owner-only output file.

```sh
python3 scripts/federation-fugitive-sign.py reviewed-fugitives.json signed-fugitives.txt
```

Open the signed output locally. On the matching game scope, run `/oly fugitives paste` and paste the exact signed line. Repeat with the clients that need the current decision. Paste an older revision to confirm it is refused after importing the new revision. A reload should keep the signed revision and expire it at the indicated server time.

When an appeal removes a character, omit that character from the next complete revision. If no names remain, use `"names": []` and sign the next revision for the same scope. Redistribute that signed replacement to affected clients. If a guild's enrollment is suspended or revoked, issue a newer signed federation enrollment without that guild. Native roster changes and guild-master actions remain attended. See [federation enrollment](FEDERATION-PROGRAM.md) for details.
