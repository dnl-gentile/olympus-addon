# Federation program enrollment

The federation program is an optional guild-level grant. The existing Olympus Accord still governs personal consent, and ordinary guild verification and census visibility continue separately. Shipping the code alone leaves the program inactive. No production grant ships with the implementation.

The author can add a `program` array to the existing council JSON consumed by `scripts/council-sign.py council`. The rest of the council JSON and the signed list's delivery stay the same. The following is a fictitious Alliance example for the US region of `ForeverPvE`. Choose a current activation time and expiry before signing an actual list.

```json
{
  "realm": "ForeverPvE",
  "program": [
    {
      "faction": "Alliance",
      "region": "US",
      "mode": "enforce",
      "issued": 1795000000,
      "expires": 1795086400,
      "guilds": [
        {
          "guild": "Olympus Azure",
          "caretaker": "Silver Rock-CAMWOWUS2Realm5PvE",
          "official": "Amber Vale-CAMWOWUS1Realm2PvE"
        }
      ]
    }
  ]
}
```

The High Council manually verifies the guild in Discord and confirms the guild's opt-in before approval. Then the author records the approved Prime caretaker in the first native guild rank (index 0) and the day-to-day GM in the second native guild rank (index 1). Configure the day-to-day GM's permissions through WoW's guild rank controls and use the caretaker for actions reserved for the native guild master. An optional explicit `officialRankIndex` must be 1. The author signs the approval. Players' clients confirm both ranks against a fresh, complete native roster before enabling shared tools in that guild. Other guilds' clients rely on the signed attestation. The extension carries game character and guild names only. Keep account identifiers, Discord identifiers, proof material and keys out of the council list.

In an enrolled guild, `/oly caretaker` shows the exact character to whisper once the current native roster confirms both ranks. The player sends their own message.

Scope is the exact signed group, faction and region. Forever scope uses the region code from the native realm name. On other realms the region is `-`. Each entry is a complete replacement for that scope and has an inclusive `issued` and exclusive `expires` Unix second, at most 31 days apart. Repeat every active scope in subsequent council JSON updates. Removing a guild, expiry, or an omitted policy clears grants while the signed activation stays in force. Retiring that rollout requires a newer signed policy for its scope with `mode` set to `off`, valid times, and an empty `guilds` list. The signer rejects more than twenty guilds per scope. Normal signed titles size limits still apply across all scopes and the existing titles data.

## Addon APIs

- `ns.FederationProgram.Active()` checks whether this scope received a valid signed activation. It stays true after expiry or omission until an accepted newer signed policy explicitly says `off`.
- `ns.FederationProgram.IsEnrolled(guild[, at])` checks a current grant for the exact guild name, ignoring case. Passing a time also bounds the lookup to the current policy's interval.
- `ns.FederationProgram.Role(fullName, guild[, at])` returns `caretaker` or `official` for the enrolled guild's exact `Name-Realm` identity. Use the actual game sender identity where an action is role-restricted.
- `ns.FederationProgram.LocalEnrollment([at])` returns the current guild name if the grant and both native ranks are confirmed by the current roster, or `nil` otherwise. Use this check for local actions requiring enrollment. Callers still check their own capability, consent and normal tool-specific prerequisites.

The addon reads the signed `HT1` titles blob through the existing Workshop channel or a signed bundle. Before activation, each connected feature keeps its existing behavior. Once activated, a connected feature must gate both outbound writes and inbound records, as well as its UI. A signed grant is additive to any feature-specific approvals and does not confer native WoW permissions. Older addon versions can still use their own earlier behavior on the shared addon channel. Activation requires an authorized signing and in-game validation of receipt, role changes and eventual removal across clients. Guild approval uses the Council’s manual Discord check. Individual Discord account linking is a separate process.
