# Census statistics

Daniel, 2026-10-19: clicking the soldiers number opens a statistics page, in the addon's Census
tab and in the Olympus Companion, with a chart and these figures: the census with and without
banned guilds, the Battle.net accounts ("contas azuis"), the people who have the addon, a clean
(sanitized) census, and the list of all guilds.

## Who does what

- **The game's page** is `Olympus/CensusStats.lua` (commit 4cf3677b, branch `batch/census-chat`):
  the header shows the characters large and the people smaller; a click on the count opens a page in
  the Census tab with characters, people, linked alts, online now, guilds counted and reporting, the
  size-weighted average level, every server (1.4.0, in place of the largest guilds: Data.Groups), the levels online, and two
  graphs (characters over 30 days, online over 24 hours) from this client's own history
  (`ns.rdb.censusHistory`). Its last section, "How the census works" (the author, 2026-10-20), explains
  the data in seven topics: how the census is built (each guild's newest record over what was known,
  each with the time it was observed), where the numbers come from, validated data, estimates,
  sanitized data, how validation works and how sanitizing works, the last as numbered rules S1 to S5
  (valid record, recency, exclusions, agreement, impossible jump) (`CensusStats.HowTopics`, its
  numbers formatted from the constants). The Companion's page uses the same words, plus lines about
  what only it does.
- **The sanitized census** is `Olympus/CensusClean.lua` (branch `claude/census-stats-section`):
  computation only, no page. Its figures can become lines on the game's page once
  `batch/census-chat` is in the integration.
- **The Companion** reads both from the Bridge's `stats` section and shows them; it never
  recomputes them, so the game and the app agree.

## The sanitized census (`CensusClean.lua`)

Worked out on each client from what it already holds: the guild reports (`ns.rdb.guilds`), the
trusted relays' rows (`ns.rdb.censusGlobal`), the guilds `/who` saw, the moderators' net-off list
and the confirmed alt links. Nothing is sent.

1. **People, not characters.** Characters linked as alts (confirmed on both sides, `Alts.lua`)
   count once: `Data.Summary().total`, the page's people. The BattleTag never leaves the moderation
   team, so it cannot join characters in a public figure.
2. **Banned guilds apart.** A guild the moderators took off the network (net-off,
   `Moderation.lua`) is in no total. Its last size held here (its own report from before, or
   a relay row) gives `charactersWithBanned`, and it is listed apart; a banned guild never
   heard here is listed with its size unknown.
3. **Agreement preferred, disputes flagged.** Each counted guild's confidence:
   `own` (our roster), `confirmed` (two or more reporters, `Data.Dispute` has nothing to say),
   `relayed` (a trusted keeper's row), `single` (one reporter), `disputed` (`Data.Dispute().disputed`:
   split leader/officers, an outvoted report, sizes too far apart), `stale` (counted but not fresh:
   no vote is current). All of them count. `confirmedPeople` (own + confirmed + relayed, their linked
   alts once) is the lower bound.
4. **Stale reports out of "now".** Online counts and `addonOnline` take fresh reports only (15 min,
   `Data.FRESH`); a guild keeps its size for 24 h after its last report (`Data.TOTAL_KEEP`).
5. **Departed guilds tombstoned.** A guild not heard for more than 24 h leaves every total and is
   listed as departed with its last size and when it was heard, until it is forgotten (7 days,
   `Data.KEEP`). The Companion's bridge keeps its own tombstones the same way.
6. **Outliers rejected, on the statistics only.** A report over 1,000 (`Codec.GUILD_CAP`) was
   already refused. Besides, a guild whose size jumps past `max(25, 10%)` plus 20 members a minute
   since its last good size, with only one reporter or a disputed set behind it, counts at its last
   good size and is flagged `outlier`; the new size is taken once two reporters agree, our roster or
   a relay gives it, or it holds for an hour. `sanitizedPeople = people - held-back excess`. The
   header's count stays `Data.Summary()`'s. The last good sizes are `ns.rdb.censusClean.sizes`,
   pruned at login past `Data.KEEP`.

**Validated people** (the Olympus Accord's BattleTags): only a moderation team client holds any
(`Accord.lua`'s team store), so only its export carries `validated`: how many distinct BattleTags and
characters it holds, never a tag or a name. Every other client sends none and its Companion shows
no line for it (Daniel, 2026-10-20: the public sees only what is counted).

**People, estimated** (the author, 2026-10-20: the people can't be told exactly until every player
shared his account): `CensusStats.PeopleEstimate` (`Olympus/CensusStats.lua`) gives the people as
each client can tell them:

- **A member's client** (and a team client with fewer than 20 validated accounts): the plain people
  count (`Data.Summary().total`: the characters, confirmed linked alts once), in the words the page
  already uses ("about 80,500 people", "Estimated people", the formula in its tooltip and detail).
  It is never divided by a rate: the players who linked alts all have more than one character, so
  their rate runs high and an estimate from it came out about half the true number (the author's
  "Membros: contagem atual").
- **A moderation team client (the King's is one) whose validated sample holds 20 accounts or more**
  (`CensusStats.SAMPLE_MIN`; `Accord.Sample`: the characters of the counted guilds whose BattleTag it
  holds, and how many BattleTags): the validated accounts plus the characters not validated at that
  sample's characters per account, to three significant figures, never fewer than the players the
  samples tell apart (BattleTags, and the players who linked alts, `Alts.Sample`) and never more
  than the plain people count. The header, the census page, the minimap button and the copy for
  Discord show it as "~80,500 people" (the game's fonts have no approximately-equal sign); the
  tooltip and the page's detail say how it is made and that the more players use the Olympus addon
  and the Olympus Companion, the more precise it gets. The census page's graphs give each day's and
  hour's people the same way ("~", that sample's characters at the estimate's people per character,
  never above its own count).

Only the staff (a team client, never on the King's screen) see the validated accounts, the
characters not yet validated and the rate; every other client shows none of it. A later release may
bring the team's rate to members through the Companion.

**Not counted yet:** people with the addon (beyond those online now) and Battle.net accounts.
Counting them needs a census wire change on every reporter (a per-account flag in the hello, report
fields for guildmates seen with the addon). Not in this release: the export leaves them out and the
Companion shows no line for them. To be designed with Daniel after 2026-10-21.

## Export (`stats` section, version 1, `Olympus/BridgeSections.lua`)

The page's figures come from `Data.Summary()` and its series from `CensusStats.DaySeries` /
`HourSeries` / `AverageLevel` when the build has them (without them the series are empty). Strings
and whole numbers only (`validated.rate` aside), within the Bridge's section limits (1500
values, depth 5):

```text
stats = {
  at, characters, people, linkedAlts, online, freshGuilds, countedGuilds, avgLevel?, addonOnline,
  charactersWithBanned, sanitizedPeople, confirmedPeople,
  confidence = { own, confirmed, relayed, single, disputed, stale },        -- characters
  banned = { guilds, characters, list = { "members~name", ... } },
  departed = { guilds, characters, list = { "members~lastHeard~name", ... } },
  outliers = { guilds, list = { "reported~kept~name", ... } },
  days = { "t~characters~people~online", ... },      -- the page's 30 days, days without a sample out
  hours = { "t~characters~people~online", ... },     -- the page's 24 hours, hours without one out
  guilds = { "members~online~users~avg10~status~name", ... },  -- 256 at most, biggest first
  peopleEstimate?,                           -- a team client's "~" estimate, as its header shows it
  validated? = { battleTags, characters, countedBattleTags?, countedCharacters?, unvalidated?, rate? },
                                             -- a moderation team client only: numbers, never tags or names
}
```

`peopleEstimate` is a whole number, sent only while the header shows a team client's "~" estimate
(the King's stream included): the Companion shows it with its "~". Without it, the people are
`people`, the plain count a member's header shows, and the Companion shows that.
`validated.countedBattleTags` / `countedCharacters` are the validated accounts and characters of the
guilds counted, `unvalidated` the counted characters not yet validated, and `rate`, while they made
the estimate, their characters per account (two decimals, the one number of the section that is not
whole): the staff's line. On the King's stream (`Accord.Stream`) a team client sends none of these
four, as its page shows none of them there (`CensusStats.StaffShown`). The `days` / `hours` series
keep the plain people count of each sample.

`status` is one of `own`, `confirmed`, `relayed`, `single`, `disputed`, `outlier`, `stale` or
`seen` (only `/who` saw it, in no total). Banned and departed guilds are in their own lists. The
guild name is the last field, so nothing in it can shift the others.

## The Companion

- The Companion's own bridge addon (OlympusCompanionBridge, kept with the Companion, not in this
  repository) saves `stats` with the other sections at logout or `/reload`, read through
  `OlympusBridge.GetSection("stats")`.
- The core reads it from the same SavedVariables file as the checkpoint (`CensusStatisticsDecoder`,
  `companion/core/.../CheckpointIngestion.kt`); a missing, unknown or malformed section is null and
  never blocks the census. `CensusStatisticsPage` gives both shells the same lines and words.
  `GuildAverageLevelDecoder` gives each guild's average level from the `guilds` section (else from
  `stats`) for the census list's Avg lvl column ("—" without one).
- Compose (`companion/shared/.../CensusStatisticsScreen.kt`) and SwiftUI
  (`companion/appleAppNative/Sources/Shared/CensusStatisticsView.swift`): the census header's
  soldiers number opens the page: figures, the two graphs, the confidence bars, banned, held-back
  and departed guilds, and every guild.
- The desktop watcher (Windows) and the Mac runtime attach the statistics and average levels to the
  live census. Phones get the census through the LAN journal, which carries the checkpoint only:
  they show the checkpoint's figures and guild list and say the rest comes from the game, until the
  statistics travel with the census envelope too.
