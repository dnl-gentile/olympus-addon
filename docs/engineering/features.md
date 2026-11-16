# Feature map

[Documentation home](../README.md) · [Complete file inventory](module-map.md)

Olympus is a collection of cooperating modules, rather than one census screen. Most modules attach a service to `ns`, register native or internal events, maintain a bounded local store, and expose view data or actions. The files below are starting points; the inventory lists every loaded file separately.

## Census, membership and identity

| Area | Main files in `Olympus/` | Responsibility and boundary |
| --- | --- | --- |
| Census | `Roster.lua`, `Data.lua`, `Codec.lua`, `Comm.lua`, `CensusClean.lua`, `CensusStats.lua` | Observe the local guild, exchange reports and derive counts with freshness and scope rules. A peer report is not a native roster. |
| Membership | `Members.lua`, `Alts.lua` | Own-guild activity and mutually linked characters. Character counts and linked-person counts answer different questions. |
| Identity and charters | `Verify.lua`, `GuildCharter.lua` | Verification flows and guild-master-authored recruitment cards. A self-declared name is not evidence of authority. |
| Rankings | `RankingRules.lua`, `RecruitRanking.lua`, `CraftRanking.lua`, `Honors.lua`, `HonorsNet.lua` | Shared ranking policy, recruitment evidence, signed crafting completions and display honors. Each ranking has its own accepted evidence. |
| Privacy | `Accord.lua`, `Consent.lua`, `Cover.lua`, `PrivatePresence.lua` | Terms, feature consent, moderator cover names and permitted quiet presence. Quieting one client's broadcasts does not erase observations held by other clients. |

Read [data and census](data-and-census.md) before changing counts, and [networking and trust](network-and-trust.md) before changing who may publish them.

## Church and recruiting

`Church.lua` owns the offices book. `ChurchView.lua` presents it; `ChurchCount.lua` observes native guild events for recruitment credit; `ChurchFullness.lua` tracks eligible complete-roster observations.

`Recruit.lua` owns requests, routing and drafts. `RecruitCandidates.lua` gathers and filters scan candidates. `RecruitPanel.lua` combines incoming requests and scan candidates into one local queue. `RecruitHandoff.lua` remains as a disabled compatibility facade: it does not delegate the recruiter’s operation to guildmates. See the [recruiting flow](recruiting.md).

## Governance and moderation

| Area | Main files | What owns the decision |
| --- | --- | --- |
| Throne and offices | `King.lua`, `Acts.lua`, `Nominees.lua`, `MainKey.lua` | Crown actions, writs, appointments and a session-bound borrowed shortcut; possession of a UI control is not authorization. |
| Announcements and participation | `Decree.lua`, `Vox.lua`, `Court.lua`, `Week.lua`, `Chronicle.lua` | Decrees, polls, audiences, agenda and observed history. |
| Guild moderation desk | `Watch.lua` | Private own-guild records and officer whispers; both ends recheck the native roster. |
| Network sanctions | `Moderation.lua`, `Filter.lua`, `WatchChat.lua`, `ChatStrikes.lua`, `TagFollow.lua` | Network exclusion, blocked terms, removed chat lines, timeouts and associated sanction handling. These affect participating Olympus clients, not Blizzard's account enforcement. |
| Cases and follow-up | `Judgment.lua`, `JusticeTasks.lua`, `TabardsV2.lua`, `Inspect.lua` | Decisions, deliberate guild-action requests and opt-in observed tabard contracts. They do not create game privileges that the player lacks. |
| Guidance | `Letters.lua`, `RoleBriefings.lua`, `WeeklyBrief.lua`, `Answers.lua`, `AnswerBank.lua` | Version letters, role instructions, summaries and curated answers. Edit the generated answer bank through `docs/answers.json`. |

Signed author lists, native roster permissions and participant claims are different trust sources. See [networking and trust](network-and-trust.md); do not copy a permission check from an unrelated feature merely because it also mentions officers.

## Communication and coordination

`Channels.lua` owns federation chat admission and tiers. `ChatHall.lua` handles the Forever native-chat transport, `ChatWindow.lua` draws the Olympus Chat page, and `ChatRooms.lua` owns logical room membership and messages. Room membership is a separate concern from the transport carrying a line.

`Board.lua` manages flags and camps; `Groups.lua` handles group listings and applications. `War.lua` owns the guild war room, `WarSquads.lua` its squad assignments, and `OfficerMuster.lua` officer calls. `PartyGuard.lua` handles a short-lived, validated invitation inbox. `ChatMarks.lua` adds permitted honor labels to chat presentation.

## World and player presentation

| Area | Main files | Data source or responsibility |
| --- | --- | --- |
| World map | `Map.lua`, `Zones.lua`, `MapNames.lua`, bundled HereBeDragons libraries | Aggregate zone markers, zone-name mapping and permitted labels. |
| Layers and hopping | `Layers.lua`, `Hop.lua`, `HopSightings.lua` | Layer inference from observed NPC identifiers, deliberate hop requests and request-bound discovery. |
| Positions and navigation | `Positions.lua`, `KingArrow.lua`, `InnkeeperArrow.lua` | Optional position sharing, a permitted crown pointer and local navigation to training inns. These are distinct data flows. |
| Sightings | `Wanted.lua`, `PlayerSightings.lua` | Observed kill/slay facts and voluntary, request-bound sightings. No global omniscient player tracker exists. |
| Player cards | `PlayerProfile.lua`, `ProfileEdit.lua`, `ProfileEffects.lua` | Read held player facts, edit one's profile and apply bounded presentation effects. |
| Native UI additions | `GuildFrame.lua`, `PlayerMenu.lua`, `PlayerTooltip.lua`, `Borders.lua`, `Nameplates.lua` | Guild-window entry points, menus, tooltip details, portrait borders and friendly-nameplate marks. All must obey the gamepad gate. |

See [UI and gamepad integration](ui-and-gamepad.md) before changing any native frame, tooltip, chat window or callback.

## Crafting and guild finances

| Area | Main files | Meaning of the stored data |
| --- | --- | --- |
| Crafting | `Crafters.lua`, `CraftRequests.lua`, `CraftRanking.lua` | Opt-in skills/recipes, requests and claims, private fulfillment, and two-party completion evidence. |
| Treasury and banks | `Treasury.lua`, `Bank.lua`, `GuildFinance.lua` | Observed receipts, inspected bank snapshots and explicit guild/event attribution. A displayed balance is not an account managed by a central server. |
| Dues | `Dues.lua`, `DuesHistory.lua`, `DuesGrace.lua`, `DuesRosterCheckpoints.lua` | Weekly obligations, frozen summaries, missing-evidence handling and roster checkpoints. Missing a receipt must not silently become proof of nonpayment. |
| Campaigns | `Campaign.lua` | Voluntary assignments and receipt aggregates. |
| Portability | `Carry.lua`, `CarryHistory.lua`, `CarryMerger.lua`, `Backup.lua` | Quoted history, signed originals versus witnesses, archive-merger mandates and deliberate backup/restore. Importing history does not grant office or turn a quote into a new ledger entry. |
| Loot | `Loot.lua` | Loot notes and manually maintained points, not an automatic auction service. |

Detailed portability rules are in [history carry](../history-carry.md). Arena money, games and result records are described separately in [Arena and records](arena-and-records.md).

## Infrastructure and integration

Startup, events, timers and compatibility live in `Bootstrap.lua` and `Core.lua`. `GamepadRegistry.lua`, `Gamepad.lua` and `Dialog.lua` control UI integration. `Diagnostics.lua`, `Perf.lua`, `SelfTest.lua`, `Workshop.lua`, `Builds.lua` and `Versions.lua` support diagnosis, author tools and version handling.

The [integration chapter](integrations.md) explains `API.lua`, the Bridge family, the separate website aggregate addon, the inactive `ArmyExport.lua` path and the optional `LinkLoader.lua`. These have different contracts; none makes a desktop companion a prerequisite for normal recruiting or census operation.
