# Federation program enrollment

On Forever, the High Council's existing guild verification is the participation decision. A guild with a retained valid approval can use the shared tools and Church conversion tracking without entering another list of guild names. Pending, overdue, revoked, removed or off-network guilds have no participation grant. Olympus Prime uses its existing exemption. Personal Accord consent still applies.

The addon reads the native roster to identify the current guild master and the next native rank. Missing or ambiguous officer data does not invent a privileged contact. An existing explicit author-signed program policy still takes precedence for scopes that already use one. The configuration below documents that advanced policy and its compatibility with earlier clients.

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

The High Council manually verifies the guild in Discord and records its approval through the existing addon verification flow. On Forever, that retained approval is sufficient for guild participation; the author does not need to copy the guild into a second list. The approved guild master is the caretaker. A fresh, complete native roster must confirm that character at native rank 0 before local caretaker actions can run. When the actual native roster identifies a day-to-day GM at native rank 1, that character can act as the official. A remote census entry saying only "officer" cannot establish that exact rank. Configure permissions through WoW's guild rank controls; the addon cannot confer native permissions.

For the optional legacy signed policy, the author instead records the approved caretaker and day-to-day GM in the example above and signs the list. An optional explicit `officialRankIndex` must be 1. Local clients confirm both named ranks against a fresh, complete native roster; remote clients rely on that signed attestation. The extension carries game character and guild names only. Keep account identifiers, Discord identifiers, proof material and keys out of the council list.

In an enrolled guild, `/oly caretaker` shows the exact character to whisper once the current native roster confirms the approved caretaker, or both named ranks when a legacy signed policy applies. The player sends their own message.

Scope is the exact signed group, faction and region. Forever scope uses the region code from the native realm name. On other realms the region is `-`. Each entry is a complete replacement for that scope and has an inclusive `issued` and exclusive `expires` Unix second, at most 31 days apart. Repeat every active scope in subsequent council JSON updates. Removing a guild, expiry, or an omitted policy clears grants while the signed activation stays in force. Retiring that rollout requires a newer signed policy for its scope with `mode` set to `off`, valid times, and an empty `guilds` list. The signer rejects more than twenty guilds per scope. Normal signed titles size limits still apply across all scopes and the existing titles data.

## Recruiting overflow

On Forever's verification route, the existing King's guild is primary and the other verified guilds are candidates for side-guild placement. A legacy signed policy instead marks each primary guild's enrollment row with `"primary": true`. A cross-guild handoff starts with the applicant's explicit `JOIN OLYMPUS` whisper to a recruiter in a primary guild. The recruiter opens the handoff picker in Church → Invites. A recipient in an eligible side guild with room can claim the offer once every primary has a complete native roster at the game's cap. Missing or old evidence leaves the request in the origin queue. Guild-only joins and scanned players stay in their original guild's recruiting flow.

For a remote guild, the addon requests only the roster count and observation time from its approved caretaker or precisely established official by direct addon whisper. Observations count for up to 90 seconds. The recipient independently checks its own roster and the primary capacities. Preliminary messages carry no applicant data. The origin shares only the claimed applicant's name, directly with the claimant, after rechecking capacity, enrollment and the applicant's request. The recipient still prepares an attended invite. The recipient checks the rule again before preparing the invitation in the addon. An already copied native command remains in the player's hands.

Test in game with enrolled primary and side guilds before activating the rollout. Check a primary opening a seat, an unavailable roster observer, an expired policy, a full or revoked side guild, and a pending claim when any of those changes. On Forever, confirm that the upgraded clients see exact sender identities for direct addon whispers across native sub-realms.

## Cross-guild membership

An ordinary member can show their current guild membership for Olympus chat and Crafters. A viewer who has no live proof asks their own caretaker. That caretaker checks the viewer in the native roster before forwarding a private nonce to the other guild's approved caretaker. The second caretaker checks the exact subject in its own fresh native roster and answers the viewer directly. The witness contains the subject, nonce and roster observation time. Chat text, crafting details and roster lists stay out of this exchange.

The witness lasts up to 90 seconds from the roster observation. Each client keeps at most 24 pending lookups and 128 witnesses in memory. At most two actions per subject can wait for a witness, for up to 15 seconds. An existing Verify approval change, new signed enrollment revision, guild change, Accord withdrawal, or Privacy Mode clears this state. Every retry still goes through the existing chat, Crafters and moderation checks. The witness grants membership only. Officer channels keep their separate rank rules, and the Companion records only lines that reach the existing admitted chat path and satisfy its existing consent gates.

Both approved caretaker clients must be online with fresh native rosters and current enrollments for this fallback. When either cannot answer, the addon omits an unverified incoming line or listing and keeps the existing signed-role and corroborated-census checks. Test this flow on two Forever guilds with ordinary members and separate custodians. Confirm native roster changes, approval revocation, cross-sub-realm sender identities, and chat/recipe visibility on both clients.

## Addon APIs

- `ns.FederationProgram.Active()` uses the existing Verify approvals on a recognized Forever family and region. If an explicit legacy signed activation exists, that policy takes precedence and stays active after expiry or omission until an accepted newer signed policy explicitly says `off`.
- `ns.FederationProgram.IsEnrolled(guild[, at])` checks a current approval for the exact guild name, ignoring case. Passing a time also requires the approval to have existed at that time; a later approval grants no retrospective participation. With an explicit legacy signed policy, its current grant and time interval apply instead.
- `ns.FederationProgram.Role(fullName, guild[, at])` returns `caretaker` or `official` for the enrolled guild's exact `Name-Realm` identity. Use the actual game sender identity where an action is role-restricted.
- `ns.FederationProgram.LocalEnrollment([at])` returns the current guild name if a current, complete native roster confirms the approved caretaker at rank 0, or `nil` otherwise. A legacy signed policy additionally requires its named official at rank 1. Callers still check their own capability, consent and normal tool-specific prerequisites.

Guild approval uses the Council's manual Discord check and the existing Verify approval; it does not require individual Discord account linking. The optional legacy policy arrives in the signed `HT1` titles blob through the existing Workshop channel or a signed bundle. Connected features gate outbound writes, inbound records and their UI while preserving their own capability and consent checks. Neither a guild approval nor a signed grant confers native WoW permissions. Older addon versions can still use their own earlier behavior on the shared addon channel. In-game acceptance must confirm receipt, role changes and eventual removal across clients.

## Voluntary contributions

On Forever, existing verified guild participation also enables the voluntary contributions policy by default. Mandatory dues remain confined to Olympus Prime. If this scope already received an explicit legacy policy, that policy continues to take precedence. The optional legacy `contributions` array in the same council JSON has one entry per faction and region, with `faction`, `region`, `mode`, `issued` and `expires` and the same time and renewal rules as the enrollment marker.

While the contributions policy is active, each eligible non-Prime guild with a matching native roster sees **Charitable Contributions** in The Realm. The page displays recorded voluntary in-game guild contributions and recognition. A lost or revoked guild approval hides that guild's voluntary page. For an explicit legacy policy, expiry or omission hides the page until renewal while keeping mandatory dues suppressed outside Prime. A newer signed `off` marker ends that rollout and restores legacy dues behavior, including outside Prime. The default Forever verification route keeps mandatory dues confined to Prime. Existing payment history is retained. Prime members with an unconfirmed or partially confirmed weekly payment see a private reminder at most once per UTC day, subject to their existing reminder preference. Missing receipts are not treated as arrears.

The contribution ranking covers new observed gold trades with the signed Federal Treasurer, where the client knows the donor's enrolled guild. It excludes historical donations, ordinary mail and manually entered ledger lines. The Treasurer’s protected trade totals are separate from legacy donor lists and leaderboards. Anonymous rows carry neither character names nor gold amounts. Explicit name choices go directly to the Treasurer, expire when no longer refreshed and can be withdrawn. The page expires downloaded snapshots after five minutes.

Prime interest has its own opt-in and seven-day window. It can be read by the Treasurer and Prime officers with current native roster or signed leadership evidence. It includes only the character name, a contribution group, and whether the last recorded guild's verification is available. It does not count as Discord verification or invite players.

The Treasurer can edit a local draft from Prime recruitment interest. For publication, the author signs a current council file with up to four informational `contributionMilestones` per scope. Each item names the signed regional Treasurer as `issuer` and has `faction`, `region`, and a `milestones` list of `title` and `description` objects. Milestones do not request funds, move gold, grant benefits or change ranks.
