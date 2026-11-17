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

## Recruiting overflow

Mark each primary guild's enrollment row with `"primary": true`. Guilds without that marker are candidates for side-guild placement. During the signed rollout, a cross-guild handoff starts with the applicant's explicit `JOIN OLYMPUS` whisper to a recruiter in a primary guild. The recruiter opens the handoff picker in Church → Invites. A recipient in a signed side guild with room can claim the offer once every configured primary has a complete native roster at the game's cap. Missing or old evidence leaves the request in the origin queue. Guild-only joins and scanned players stay in their original guild's recruiting flow.

For a remote guild, the addon requests only the roster count and observation time from a signed roleholder by direct addon whisper. Observations count for up to 90 seconds. The recipient independently checks its own roster and the primary capacities. Preliminary messages carry no applicant data. The origin shares only the claimed applicant's name, directly with the claimant, after rechecking capacity, enrollment and the applicant's request. The recipient still prepares an attended invite. The recipient checks the rule again before preparing the invitation in the addon. An already copied native command remains in the player's hands.

Test in game with enrolled primary and side guilds before activating the rollout. Check a primary opening a seat, an unavailable roster observer, an expired policy, a full or revoked side guild, and a pending claim when any of those changes. On Forever, confirm that the upgraded clients see exact sender identities for direct addon whispers across native sub-realms.

## Cross-guild membership

During the rollout, an ordinary member can show their current guild membership for Olympus chat and Crafters. A viewer who has no live proof asks their own caretaker. That caretaker checks the viewer in the native roster before forwarding a private nonce to the other guild's signed caretaker. The second caretaker checks the exact subject in its own fresh native roster and answers the viewer directly. The witness contains the subject, nonce and roster observation time. Chat text, crafting details and roster lists stay out of this exchange.

The witness lasts up to 90 seconds from the roster observation. Each client keeps at most 24 pending lookups and 128 witnesses in memory. At most two actions per subject can wait for a witness, for up to 15 seconds. A new signed enrollment revision, guild change, Accord withdrawal, or Privacy Mode clears this state. Every retry still goes through the existing chat, Crafters and moderation checks. The witness grants membership only. Officer channels keep their separate rank rules, and the Companion records only lines that reach the existing admitted chat path and satisfy its existing consent gates.

Both signed caretaker clients must be online with fresh native rosters and current enrollments for this fallback. When either cannot answer, the addon omits an unverified incoming line or listing and keeps the existing signed-role and corroborated-census checks. Test this flow on two Forever guilds with ordinary members and separate custodians. Confirm native roster changes, signed revocation, cross-sub-realm sender identities, and chat/recipe visibility on both clients.

## Addon APIs

- `ns.FederationProgram.Active()` checks whether this scope received a valid signed activation. It stays true after expiry or omission until an accepted newer signed policy explicitly says `off`.
- `ns.FederationProgram.IsEnrolled(guild[, at])` checks a current grant for the exact guild name, ignoring case. Passing a time also bounds the lookup to the current policy's interval.
- `ns.FederationProgram.Role(fullName, guild[, at])` returns `caretaker` or `official` for the enrolled guild's exact `Name-Realm` identity. Use the actual game sender identity where an action is role-restricted.
- `ns.FederationProgram.LocalEnrollment([at])` returns the current guild name if the grant and both native ranks are confirmed by the current roster, or `nil` otherwise. Use this check for local actions requiring enrollment. Callers still check their own capability, consent and normal tool-specific prerequisites.

The addon reads the signed `HT1` titles blob through the existing Workshop channel or a signed bundle. Before activation, each connected feature keeps its existing behavior. Once activated, a connected feature must gate both outbound writes and inbound records, as well as its UI. A signed grant is additive to any feature-specific approvals and does not confer native WoW permissions. Older addon versions can still use their own earlier behavior on the shared addon channel. Activation requires an authorized signing and in-game validation of receipt, role changes and eventual removal across clients. Guild approval uses the Council’s manual Discord check. Individual Discord account linking is a separate process.

## Voluntary contributions

On Forever, the optional `contributions` array in the same council JSON has one entry per faction and region. Each entry has `faction`, `region`, `mode`, `issued` and `expires`, with the same time and renewal rules as the enrollment marker. Receiving an enrollment by itself leaves the contributions policy inactive.

While the contributions rollout is active, mandatory dues stay in Olympus Prime. Outside Prime, each enrolled guild with a matching native roster sees **Charitable Contributions** in The Realm during the signed policy's validity. The page displays recorded voluntary in-game guild contributions and recognition. Expiry or omission hides the voluntary page until renewal and keeps mandatory dues suppressed outside Prime. A newer signed `off` marker ends the rollout. Existing payment history is retained. Prime members with an unconfirmed or partially confirmed weekly payment see a private reminder at most once per UTC day, subject to their existing reminder preference. Missing receipts are not treated as arrears.

The contribution ranking covers new observed gold trades with the signed Federal Treasurer, where the client knows the donor's enrolled guild. It excludes historical donations, ordinary mail and manually entered ledger lines. The Treasurer’s protected trade totals are separate from legacy donor lists and leaderboards. Anonymous rows carry neither character names nor gold amounts. Explicit name choices go directly to the Treasurer, expire when no longer refreshed and can be withdrawn. The page expires downloaded snapshots after five minutes.

Prime interest has its own opt-in and seven-day window. It can be read by the Treasurer and Prime officers with current native roster or signed leadership evidence. It includes only the character name, a contribution group, and whether the last recorded guild's verification is available. It does not count as Discord verification or invite players.

The Treasurer can edit a local draft from Prime recruitment interest. For publication, the author signs a current council file with up to four informational `contributionMilestones` per scope. Each item names the signed regional Treasurer as `issuer` and has `faction`, `region`, and a `milestones` list of `title` and `description` objects. Milestones do not request funds, move gold, grant benefits or change ranks.
