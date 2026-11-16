# Complete module map

[Documentation home](../README.md) · [Architecture](architecture.md) · [Feature responsibilities](features.md)

This inventory follows the three source TOCs exactly. Order matters: each file executes before the next. It covers every Lua file currently present in the addon folders, including bundled libraries and translations. It describes ownership, not a claim that every feature is enabled.

The packaged TOCs can differ: packaging removes the entries in [bets-only.txt](../../scripts/bets-only.txt), and can insert generated test metadata or validated signed lists. Optional Olympus_Link comes from a separate checkout. See [development](development.md) for those rules.

## Olympus

Main runtime, domain services and ordinary UI. [Olympus.toc](../../Olympus/Olympus.toc) contains 203 entries.

| Order | Source file | Purpose |
| --- | --- | --- |
| 1 | [Bootstrap.lua](../../Olympus/Bootstrap.lua) | Early load-error capture and preparation for bundled map libraries. |
| 2 | [libs/LibStub/LibStub.lua](../../Olympus/libs/LibStub/LibStub.lua) | Bundled versioned library registry. |
| 3 | [libs/CallbackHandler-1.0/CallbackHandler-1.0.lua](../../Olympus/libs/CallbackHandler-1.0/CallbackHandler-1.0.lua) | Bundled library callback support. |
| 4 | [libs/HereBeDragons/HereBeDragons-2.0.lua](../../Olympus/libs/HereBeDragons/HereBeDragons-2.0.lua) | Bundled world/map coordinate library. |
| 5 | [libs/HereBeDragons/HereBeDragons-Pins-2.0.lua](../../Olympus/libs/HereBeDragons/HereBeDragons-Pins-2.0.lua) | Bundled map-pin placement library. |
| 6 | [Locales.lua](../../Olympus/Locales.lua) | Base translation table and locale fallback. |
| 7 | [Locales/ArenaNetText.lua](../../Olympus/Locales/ArenaNetText.lua) | Feature-specific strings for `ArenaNet` (including language overrides where provided). |
| 8 | [Locales/ArenaMoneyText.lua](../../Olympus/Locales/ArenaMoneyText.lua) | Feature-specific strings for `ArenaMoney` (including language overrides where provided). |
| 9 | [Locales/ArenaMarketsText.lua](../../Olympus/Locales/ArenaMarketsText.lua) | Feature-specific strings for `ArenaMarkets` (including language overrides where provided). |
| 10 | [Locales/ArenaFightsText.lua](../../Olympus/Locales/ArenaFightsText.lua) | Feature-specific strings for `ArenaFights` (including language overrides where provided). |
| 11 | [Locales/ArenaFarkleText.lua](../../Olympus/Locales/ArenaFarkleText.lua) | Feature-specific strings for `ArenaFarkle` (including language overrides where provided). |
| 12 | [Locales/ArenaHomeText.lua](../../Olympus/Locales/ArenaHomeText.lua) | Feature-specific strings for `ArenaHome` (including language overrides where provided). |
| 13 | [Locales/ArenaLotteryText.lua](../../Olympus/Locales/ArenaLotteryText.lua) | Feature-specific strings for `ArenaLottery` (including language overrides where provided). |
| 14 | [Locales/ArenaMatchText.lua](../../Olympus/Locales/ArenaMatchText.lua) | Feature-specific strings for `ArenaMatch` (including language overrides where provided). |
| 15 | [Locales/ComplianceText.lua](../../Olympus/Locales/ComplianceText.lua) | Feature-specific strings for `Compliance` (including language overrides where provided). |
| 16 | [Locales/ChurchText.lua](../../Olympus/Locales/ChurchText.lua) | Feature-specific strings for `Church` (including language overrides where provided). |
| 17 | [Locales/RecruitHandoffText.lua](../../Olympus/Locales/RecruitHandoffText.lua) | Feature-specific strings for `RecruitHandoff` (including language overrides where provided). |
| 18 | [Locales/ChurchFullnessText.lua](../../Olympus/Locales/ChurchFullnessText.lua) | Feature-specific strings for `ChurchFullness` (including language overrides where provided). |
| 19 | [Locales/WeeklyBriefText.lua](../../Olympus/Locales/WeeklyBriefText.lua) | Feature-specific strings for `WeeklyBrief` (including language overrides where provided). |
| 20 | [Locales/RoleBriefingsText.lua](../../Olympus/Locales/RoleBriefingsText.lua) | Feature-specific strings for `RoleBriefings` (including language overrides where provided). |
| 21 | [Locales/GuildCharterText.lua](../../Olympus/Locales/GuildCharterText.lua) | Feature-specific strings for `GuildCharter` (including language overrides where provided). |
| 22 | [Locales/MainKeyText.lua](../../Olympus/Locales/MainKeyText.lua) | Feature-specific strings for `MainKey` (including language overrides where provided). |
| 23 | [Locales/WatchCouncilText.lua](../../Olympus/Locales/WatchCouncilText.lua) | Feature-specific strings for `WatchCouncil` (including language overrides where provided). |
| 24 | [Locales/OfficerMusterText.lua](../../Olympus/Locales/OfficerMusterText.lua) | Feature-specific strings for `OfficerMuster` (including language overrides where provided). |
| 25 | [Locales/DuesHistoryText.lua](../../Olympus/Locales/DuesHistoryText.lua) | Feature-specific strings for `DuesHistory` (including language overrides where provided). |
| 26 | [Locales/DuesGraceText.lua](../../Olympus/Locales/DuesGraceText.lua) | Feature-specific strings for `DuesGrace` (including language overrides where provided). |
| 27 | [Locales/DuesRosterText.lua](../../Olympus/Locales/DuesRosterText.lua) | Feature-specific strings for `DuesRoster` (including language overrides where provided). |
| 28 | [Locales/JusticeResponseText.lua](../../Olympus/Locales/JusticeResponseText.lua) | Feature-specific strings for `JusticeResponse` (including language overrides where provided). |
| 29 | [Locales/CarryText.lua](../../Olympus/Locales/CarryText.lua) | Feature-specific strings for `Carry` (including language overrides where provided). |
| 30 | [Locales/CarryMergerText.lua](../../Olympus/Locales/CarryMergerText.lua) | Feature-specific strings for `CarryMerger` (including language overrides where provided). |
| 31 | [Locales/CampaignText.lua](../../Olympus/Locales/CampaignText.lua) | Feature-specific strings for `Campaign` (including language overrides where provided). |
| 32 | [Locales/GuildFinanceText.lua](../../Olympus/Locales/GuildFinanceText.lua) | Feature-specific strings for `GuildFinance` (including language overrides where provided). |
| 33 | [Locales/RankingRulesText.lua](../../Olympus/Locales/RankingRulesText.lua) | Feature-specific strings for `RankingRules` (including language overrides where provided). |
| 34 | [Locales/PerfText.lua](../../Olympus/Locales/PerfText.lua) | Feature-specific strings for `Perf` (including language overrides where provided). |
| 35 | [Locales/CoverText.lua](../../Olympus/Locales/CoverText.lua) | Feature-specific strings for `Cover` (including language overrides where provided). |
| 36 | [Locales/APIText.lua](../../Olympus/Locales/APIText.lua) | Feature-specific strings for `API` (including language overrides where provided). |
| 37 | [Locales/PlayerSightingsText.lua](../../Olympus/Locales/PlayerSightingsText.lua) | Feature-specific strings for `PlayerSightings` (including language overrides where provided). |
| 38 | [Locales/AccordText.lua](../../Olympus/Locales/AccordText.lua) | Feature-specific strings for `Accord` (including language overrides where provided). |
| 39 | [Locales/RecordText.lua](../../Olympus/Locales/RecordText.lua) | Feature-specific strings for `Record` (including language overrides where provided). |
| 40 | [Locales/CensusStatsText.lua](../../Olympus/Locales/CensusStatsText.lua) | Feature-specific strings for `CensusStats` (including language overrides where provided). |
| 41 | [Locales/VerifyText.lua](../../Olympus/Locales/VerifyText.lua) | Feature-specific strings for `Verify` (including language overrides where provided). |
| 42 | [Locales/SelfTestText.lua](../../Olympus/Locales/SelfTestText.lua) | Feature-specific strings for `SelfTest` (including language overrides where provided). |
| 43 | [Locales/MapNamesText.lua](../../Olympus/Locales/MapNamesText.lua) | Feature-specific strings for `MapNames` (including language overrides where provided). |
| 44 | [Locales/PlayerTooltipText.lua](../../Olympus/Locales/PlayerTooltipText.lua) | Feature-specific strings for `PlayerTooltip` (including language overrides where provided). |
| 45 | [Locales/deDE.lua](../../Olympus/Locales/deDE.lua) | German locale overrides. |
| 46 | [Locales/esES.lua](../../Olympus/Locales/esES.lua) | Spanish locale overrides. |
| 47 | [Locales/frFR.lua](../../Olympus/Locales/frFR.lua) | French locale overrides. |
| 48 | [Locales/itIT.lua](../../Olympus/Locales/itIT.lua) | Italian locale overrides. |
| 49 | [Locales/ruRU.lua](../../Olympus/Locales/ruRU.lua) | Russian locale overrides. |
| 50 | [Core.lua](../../Olympus/Core.lua) | Namespace helpers, compatibility, identity, storage migrations, events, timers and startup. |
| 51 | [GamepadRegistry.lua](../../Olympus/GamepadRegistry.lua) | Declared native UI integration policies and source pins. |
| 52 | [Gamepad.lua](../../Olympus/Gamepad.lua) | Input-mode policy evaluation and native integration install/park lifecycle. |
| 53 | [Diagnostics.lua](../../Olympus/Diagnostics.lua) | Bug-report context, blocked-action records and diagnostic presentation. |
| 54 | [RankingRules.lua](../../Olympus/RankingRules.lua) | Shared ranking definitions and evidence/eligibility policy. |
| 55 | [Perf.lua](../../Olympus/Perf.lua) | Opt-in performance measurements and reporting. |
| 56 | [Dialog.lua](../../Olympus/Dialog.lua) | Olympus-owned dialog facade and focus handling. |
| 57 | [PlayerMenu.lua](../../Olympus/PlayerMenu.lua) | Permitted native player-menu extensions. |
| 58 | [Codec.lua](../../Olympus/Codec.lua) | Bounded census report encoding and decoding. |
| 59 | [Sign.lua](../../Olympus/Sign.lua) | Verification of author-signed lists and related public-key data. |
| 60 | [Authority.lua](../../Olympus/Authority.lua) | Signed authority-manifest validation and staged enforcement policy. |
| 61 | [Zones.lua](../../Olympus/Zones.lua) | Localized zone names and map identifiers. |
| 62 | [Who.lua](../../Olympus/Who.lua) | Shared owner for deliberate native WHO queries and sightings. |
| 63 | [Data.lua](../../Olympus/Data.lua) | Census stores, scopes, report admission, freshness, summaries and revisions. |
| 64 | [Roster.lua](../../Olympus/Roster.lua) | Native own-guild roster cache, scans and fresh authority lookup. |
| 65 | [Comm.lua](../../Olympus/Comm.lua) | Message dispatch, reporter election, report publication and transport queues. |
| 66 | [Relay.lua](../../Olympus/Relay.lua) | Whisper relay transport and peer delivery handling. |
| 67 | [RelayTree.lua](../../Olympus/RelayTree.lua) | Relay topology and routing relationships. |
| 68 | [RelayFallback.lua](../../Olympus/RelayFallback.lua) | Fallback relay delivery and lifecycle. |
| 69 | [Map.lua](../../Olympus/Map.lua) | Census map markers and zone summaries through bundled map libraries. |
| 70 | [Layers.lua](../../Olympus/Layers.lua) | Layer inference from locally observed NPC identifiers. |
| 71 | [Hop.lua](../../Olympus/Hop.lua) | Requested layer hopping and invitation flow. |
| 72 | [Positions.lua](../../Olympus/Positions.lua) | Optional guild position sharing and map dots. |
| 73 | [Decree.lua](../../Olympus/Decree.lua) | Decrees, map alerts and announcement state. |
| 74 | [Channels.lua](../../Olympus/Channels.lua) | Federation chat tiers, admission and message handling. |
| 75 | [ChatHall.lua](../../Olympus/ChatHall.lua) | Forever chat-hall transport through native chat. |
| 76 | [Filter.lua](../../Olympus/Filter.lua) | Local/shared blocked-term filtering and policy. |
| 77 | [MapNames.lua](../../Olympus/MapNames.lua) | Permitted display labels for map features. |
| 78 | [Inspect.lua](../../Olympus/Inspect.lua) | Player inspection and tabard observations used by other features. |
| 79 | [PlayerTooltip.lua](../../Olympus/PlayerTooltip.lua) | Guarded additions to the native player tooltip. |
| 80 | [King.lua](../../Olympus/King.lua) | Throne state and crown-authorized actions. |
| 81 | [HopSightings.lua](../../Olympus/HopSightings.lua) | Request-bound discovery for crown/layer hopping. |
| 82 | [Vox.lua](../../Olympus/Vox.lua) | Poll creation, voting and results. |
| 83 | [Court.lua](../../Olympus/Court.lua) | Audience requests and court coordination. |
| 84 | [Board.lua](../../Olympus/Board.lua) | Flags, camps and shared board entries. |
| 85 | [Groups.lua](../../Olympus/Groups.lua) | Group listings and applications. |
| 86 | [Week.lua](../../Olympus/Week.lua) | Agenda and weekly activity entries. |
| 87 | [Treasury.lua](../../Olympus/Treasury.lua) | Receipt observations and treasury views. |
| 88 | [Dues.lua](../../Olympus/Dues.lua) | Weekly dues obligations and guarded payment helpers. |
| 89 | [DuesHistory.lua](../../Olympus/DuesHistory.lua) | Frozen weekly dues summaries and history. |
| 90 | [DuesGrace.lua](../../Olympus/DuesGrace.lua) | Missing-receipt grace and evidence handling. |
| 91 | [Bank.lua](../../Olympus/Bank.lua) | Inspected guild-bank snapshots. |
| 92 | [Backup.lua](../../Olympus/Backup.lua) | Deliberate clipboard backup and restore. |
| 93 | [Acts.lua](../../Olympus/Acts.lua) | Writs, gates, pardons and related governance acts. |
| 94 | [Chronicle.lua](../../Olympus/Chronicle.lua) | Observed governance history. |
| 95 | [Campaign.lua](../../Olympus/Campaign.lua) | Voluntary campaign assignments and receipt aggregates. |
| 96 | [GuildFinance.lua](../../Olympus/GuildFinance.lua) | Explicit guild/event attribution for finance records. |
| 97 | [Moderation.lua](../../Olympus/Moderation.lua) | Federation network exclusions and sanction handling. |
| 98 | [Alts.lua](../../Olympus/Alts.lua) | Two-sided linking of a player's characters. |
| 99 | [CensusClean.lua](../../Olympus/CensusClean.lua) | Sanitization and reconciliation of census inputs. |
| 100 | [Keys.lua](../../Olympus/Keys.lua) | Permitted realm-key distribution/rotation; keys do not move Forever clients off their public first lane. |
| 101 | [Loot.lua](../../Olympus/Loot.lua) | Loot notes and manually managed points. |
| 102 | [War.lua](../../Olympus/War.lua) | Own-guild war-room coordination. |
| 103 | [Crafters.lua](../../Olympus/Crafters.lua) | Opt-in profession skills and recipe listings. |
| 104 | [Workshop.lua](../../Olympus/Workshop.lua) | Author tools, signed-list intake and support controls. |
| 105 | [Versions.lua](../../Olympus/Versions.lua) | Version observations and update information. |
| 106 | [Builds.lua](../../Olympus/Builds.lua) | Build/version admission policy. |
| 107 | [Ed25519.lua](../../Olympus/Ed25519.lua) | Participant-signature cryptographic primitives. |
| 108 | [libs/QREncode/qrencode.lua](../../Olympus/libs/QREncode/qrencode.lua) | Bundled QR encoder used by export-related code. |
| 109 | [LinkLoader.lua](../../Olympus/LinkLoader.lua) | Loader for the separately distributed optional Olympus_Link addon. |
| 110 | [ArmyExport.lua](../../Olympus/ArmyExport.lua) | Inactive attended aggregate/QR export prototype; activation is disabled. |
| 111 | [GuildCharter.lua](../../Olympus/GuildCharter.lua) | Guild-master-authored recruitment cards. |
| 112 | [Recruit.lua](../../Olympus/Recruit.lua) | Join routing, incoming requests, reply reviews, command drafts and retry/copy flow. |
| 113 | [RecruitHandoff.lua](../../Olympus/RecruitHandoff.lua) | Disabled handoff facade, legacy-packet handling and obsolete state cleanup. |
| 114 | [RecruitCandidates.lua](../../Olympus/RecruitCandidates.lua) | Scan/WHO observations, candidate filtering and replenishment. |
| 115 | [RecruitPanel.lua](../../Olympus/RecruitPanel.lua) | Unified local recruiting queue, Start/Pause, Prepare, Skip/Next and pacing. |
| 116 | [PartyGuard.lua](../../Olympus/PartyGuard.lua) | Short-lived invitation inbox with guild/permission validation. |
| 117 | [AnswerBank.lua](../../Olympus/AnswerBank.lua) | Generated answer content; edit docs/answers.json and regenerate. |
| 118 | [Answers.lua](../../Olympus/Answers.lua) | Curated answer browsing and presentation. |
| 119 | [Views.lua](../../Olympus/Views.lua) | Shared row/detail rendering used by feature-owned view models. |
| 120 | [CensusStats.lua](../../Olympus/CensusStats.lua) | Sanitized census statistics and aggregate projections. |
| 121 | [Members.lua](../../Olympus/Members.lua) | Own-guild membership/activity views. |
| 122 | [Nominees.lua](../../Olympus/Nominees.lua) | Guild-master appointments and nomination data. |
| 123 | [UI.lua](../../Olympus/UI.lua) | Main Olympus window, layout, tabs and routing. |
| 124 | [MainKey.lua](../../Olympus/MainKey.lua) | Session-bound borrowed shortcut to permitted controls. |
| 125 | [Watch.lua](../../Olympus/Watch.lua) | Private own-guild moderation desk and officer-to-officer records. |
| 126 | [Judgment.lua](../../Olympus/Judgment.lua) | Council case voting and crown decisions. |
| 127 | [JusticeTasks.lua](../../Olympus/JusticeTasks.lua) | Deliberate follow-up guild-action requests, without granting game privileges. |
| 128 | [KingArrow.lua](../../Olympus/KingArrow.lua) | Permitted crown-location pointer and its lifecycle. |
| 129 | [Accord.lua](../../Olympus/Accord.lua) | Membership terms and acceptance state. |
| 130 | [Consent.lua](../../Olympus/Consent.lua) | Per-feature consent choices and checks. |
| 131 | [Cover.lua](../../Olympus/Cover.lua) | Permitted moderator cover names and quiet-presence integration. |
| 132 | [PrivatePresence.lua](../../Olympus/PrivatePresence.lua) | Own-guild private-presence notices used by roster reporters. |
| 133 | [Verify.lua](../../Olympus/Verify.lua) | Guild/personal verification flows and evidence. |
| 134 | [WeeklyBrief.lua](../../Olympus/WeeklyBrief.lua) | Weekly summaries of relevant feature state. |
| 135 | [Carry.lua](../../Olympus/Carry.lua) | Quoted portable history sidecars and their limits. |
| 136 | [ChatRooms.lua](../../Olympus/ChatRooms.lua) | Logical chat-room membership, protocol and lifecycle. |
| 137 | [WarSquads.lua](../../Olympus/WarSquads.lua) | War-room squad assignments. |
| 138 | [CraftRequests.lua](../../Olympus/CraftRequests.lua) | Crafting requests, claims and private fulfillment flow. |
| 139 | [ViewAs.lua](../../Olympus/ViewAs.lua) | Session-only presentation preview; never action authority. |
| 140 | [Church.lua](../../Olympus/Church.lua) | Church offices book and domain rules. |
| 141 | [ChurchCount.lua](../../Olympus/ChurchCount.lua) | Native guild-event observations for recruitment credit. |
| 142 | [ChurchFullness.lua](../../Olympus/ChurchFullness.lua) | Eligible complete-roster/fullness observations. |
| 143 | [RecruitRanking.lua](../../Olympus/RecruitRanking.lua) | Recruitment rankings from accepted observations. |
| 144 | [ChurchView.lua](../../Olympus/ChurchView.lua) | Church page rendering and recruiting entry points. |
| 145 | [TabardsV2.lua](../../Olympus/TabardsV2.lua) | Opt-in observed tabard-contract state. |
| 146 | [Letters.lua](../../Olympus/Letters.lua) | Version/onboarding letters and notices. |
| 147 | [GuildFrame.lua](../../Olympus/GuildFrame.lua) | Gate-controlled Olympus buttons/docking in supported native guild windows. |
| 148 | [Borders.lua](../../Olympus/Borders.lua) | Permitted portrait border presentation. |
| 149 | [ProfileEffects.lua](../../Olympus/ProfileEffects.lua) | Bounded profile presentation effects. |
| 150 | [Nameplates.lua](../../Olympus/Nameplates.lua) | Gate-controlled friendly-nameplate marks. |
| 151 | [ChatWindow.lua](../../Olympus/ChatWindow.lua) | Main Olympus Chat page and history presentation. |
| 152 | [WatchChat.lua](../../Olympus/WatchChat.lua) | Chat deletions, tombstones, timeouts and associated feature restrictions. |
| 153 | [ChatStrikes.lua](../../Olympus/ChatStrikes.lua) | Chat-strike tracking and escalation. |
| 154 | [TagFollow.lua](../../Olympus/TagFollow.lua) | Associated-identity sanction handling under verification and consent rules. |
| 155 | [OfficerMuster.lua](../../Olympus/OfficerMuster.lua) | Officer-only calls and their audience rules. |
| 156 | [Bridge.lua](../../Olympus/Bridge.lua) | Versioned external projections, census checkpoints and section registry. |
| 157 | [Wanted.lua](../../Olympus/Wanted.lua) | Observed kill/slay facts and related views. |
| 158 | [PlayerSightings.lua](../../Olympus/PlayerSightings.lua) | Voluntary request-bound sightings and area searches. |
| 159 | [API.lua](../../Olympus/API.lua) | Public OlympusAPI registration, permissioned handles and bounded operations. |
| 160 | [BridgeSections.lua](../../Olympus/BridgeSections.lua) | Core feature sections for Bridge consumers. |
| 161 | [BridgePeople.lua](../../Olympus/BridgePeople.lua) | People-related Bridge projections. |
| 162 | [BridgeAffairs.lua](../../Olympus/BridgeAffairs.lua) | Crafting, treasury, agenda, moderation and other affairs projections. |
| 163 | [Record.lua](../../Olympus/Record.lua) | Optional local witness chain in OlympusRecordDB. |
| 164 | [SelfTest.lua](../../Olympus/SelfTest.lua) | Author-only in-client checks in test builds. |
| 165 | [ArenaMath.lua](../../Olympus/ArenaMath.lua) | Pure money arithmetic helpers for Arena-related consumers. |
| 166 | [Compliance.lua](../../Olympus/Compliance.lua) | Wallet/wager policy gates; wallet currently disabled and region declarations empty. |
| 167 | [ArenaRating.lua](../../Olympus/ArenaRating.lua) | Pure rating calculations. |
| 168 | [ArenaBracket.lua](../../Olympus/ArenaBracket.lua) | Pure tournament-bracket calculations. |
| 169 | [ArenaFarkle.lua](../../Olympus/ArenaFarkle.lua) | Pure server-roll-to-dice and Bones/Farkle scoring rules. |
| 170 | [ArenaParse.lua](../../Olympus/ArenaParse.lua) | Parsing of supplied system/combat observations for Arena. |
| 171 | [Honors.lua](../../Olympus/Honors.lua) | Honor eligibility and display rules. |
| 172 | [ArenaPlaces.lua](../../Olympus/ArenaPlaces.lua) | Static Arena/inn meeting-place data. |
| 173 | [ArenaNet.lua](../../Olympus/ArenaNet.lua) | Arena namespace, storage, protocol/mode dispatch, authorization and UI loader. |
| 174 | [ArenaRoles.lua](../../Olympus/ArenaRoles.lua) | Arena role policy. |
| 175 | [ArenaMoney.lua](../../Olympus/ArenaMoney.lua) | Observed trade/mail flows and guarded fill helpers; never completes payment by itself. |
| 176 | [Debts.lua](../../Olympus/Debts.lua) | Obligation/IOU records and claims. |
| 177 | [DuesRosterCheckpoints.lua](../../Olympus/DuesRosterCheckpoints.lua) | Roster checkpoints supporting frozen dues history. |
| 178 | [CarryHistory.lua](../../Olympus/CarryHistory.lua) | Signed history originals and witness handling. |
| 179 | [CarryMerger.lua](../../Olympus/CarryMerger.lua) | Frozen archive-merger mandates and validation. |
| 180 | [Records.lua](../../Olympus/Records.lua) | Shared signed result inventory, reconciliation and seals. |
| 181 | [CraftRanking.lua](../../Olympus/CraftRanking.lua) | Two-party crafting-completion evidence and rankings. |
| 182 | [Wallet.lua](../../Olympus/Wallet.lua) | Wallet ledger paths, subject to the disabled compliance policy. |
| 183 | [Stakes.lua](../../Olympus/Stakes.lua) | Stake obligations and settlement paths under policy gates. |
| 184 | [Markets.lua](../../Olympus/Markets.lua) | Wager-market domain code; excluded from packaged builds. |
| 185 | [MarketBank.lua](../../Olympus/MarketBank.lua) | Wager-market bank code; excluded from packaged builds. |
| 186 | [Lottery.lua](../../Olympus/Lottery.lua) | Lottery domain/results paths, subject to compliance and package dependencies. |
| 187 | [ArenaFights.lua](../../Olympus/ArenaFights.lua) | Challenges, fight cards and fight progression. |
| 188 | [ArenaLedger.lua](../../Olympus/ArenaLedger.lua) | Arena result ledgers. |
| 189 | [ArenaTourney.lua](../../Olympus/ArenaTourney.lua) | Tournament orchestration. |
| 190 | [ArenaProfile.lua](../../Olympus/ArenaProfile.lua) | Arena-specific preferences/profile state. |
| 191 | [ProfileEdit.lua](../../Olympus/ProfileEdit.lua) | Main-addon's own-profile editor. |
| 192 | [PlayerProfile.lua](../../Olympus/PlayerProfile.lua) | Player card built from facts this client holds. |
| 193 | [HonorsNet.lua](../../Olympus/HonorsNet.lua) | Honor claims and network exchange. |
| 194 | [RoleBriefings.lua](../../Olympus/RoleBriefings.lua) | Role-specific instructions and letters. |
| 195 | [ChatMarks.lua](../../Olympus/ChatMarks.lua) | Permitted honor labels in chat presentation. |
| 196 | [FarkleTable.lua](../../Olympus/FarkleTable.lua) | Bones table state, participant messages and observed rolls. |
| 197 | [InnkeeperGossip.lua](../../Olympus/InnkeeperGossip.lua) | Opt-in addon-owned entry beside innkeeper interaction. |
| 198 | [InnkeeperArrow.lua](../../Olympus/InnkeeperArrow.lua) | Local navigation to training inns. |
| 199 | [ArenaMatch.lua](../../Olympus/ArenaMatch.lua) | Matchmaking and opponent-finding flow. |
| 200 | [ArenaChat.lua](../../Olympus/ArenaChat.lua) | Canonical fight-room specifications, audience and lifecycle. |
| 201 | [ArenaSpectate.lua](../../Olympus/ArenaSpectate.lua) | Observed duel/spectator state used by Arena screens. |
| 202 | [ArenaTest.lua](../../Olympus/ArenaTest.lua) | Arena rehearsal/test orchestration. |
| 203 | [ArenaHome.lua](../../Olympus/ArenaHome.lua) | Main-addon Arena tab, view-model entry point, menus and alerts. |

## Olympus_Arena

Load-on-demand Arena screens; requires Olympus and its supported handoff. [Olympus_Arena.toc](../../Olympus_Arena/Olympus_Arena.toc) contains 26 entries.

| Order | Source file | Purpose |
| --- | --- | --- |
| 1 | [Handoff.lua](../../Olympus_Arena/Handoff.lua) | Consumes the temporary host namespace and checks module compatibility. |
| 2 | [Locales/UIText.lua](../../Olympus_Arena/Locales/UIText.lua) | Feature-specific strings for `UI` (including language overrides where provided). |
| 3 | [Locales/FarkleText.lua](../../Olympus_Arena/Locales/FarkleText.lua) | Feature-specific strings for `Farkle` (including language overrides where provided). |
| 4 | [Locales/BonesChatText.lua](../../Olympus_Arena/Locales/BonesChatText.lua) | Feature-specific strings for `BonesChat` (including language overrides where provided). |
| 5 | [Locales/LotteryText.lua](../../Olympus_Arena/Locales/LotteryText.lua) | Feature-specific strings for `Lottery` (including language overrides where provided). |
| 6 | [Panes.lua](../../Olympus_Arena/Panes.lua) | Registry of Arena panes and role-specific staff tabs. |
| 7 | [Kit.lua](../../Olympus_Arena/Kit.lua) | Shared Arena widgets, view rendering and countdown support. |
| 8 | [Window.lua](../../Olympus_Arena/Window.lua) | Load-on-demand Arena window and section navigation. |
| 9 | [PagesPlayer.lua](../../Olympus_Arena/PagesPlayer.lua) | Player panes for fights, tournaments, rankings and gated account/profile views. |
| 10 | [PagesStaff.lua](../../Olympus_Arena/PagesStaff.lua) | Role-gated arbiter, bank, ledger and director panes. |
| 11 | [Slip.lua](../../Olympus_Arena/Slip.lua) | Wager-slip presentation; shared code remains subject to compliance gates. |
| 12 | [Card.lua](../../Olympus_Arena/Card.lua) | Fighter card and tale-of-the-tape presentation. |
| 13 | [BracketView.lua](../../Olympus_Arena/BracketView.lua) | Tournament bracket window. |
| 14 | [ChatPanel.lua](../../Olympus_Arena/ChatPanel.lua) | Compatibility entry point to fight rooms in the main Olympus Chat page. |
| 15 | [Overlay.lua](../../Olympus_Arena/Overlay.lua) | Crown overlay and stream-delay presentation. |
| 16 | [Spectate.lua](../../Olympus_Arena/Spectate.lua) | Duel-view window drawn from the core's spectator/inspection state. |
| 17 | [Popups.lua](../../Olympus_Arena/Popups.lua) | Olympus-owned Arena alerts and toasts. |
| 18 | [BonesChat.lua](../../Olympus_Arena/BonesChat.lua) | Bones table chat presentation and session-only UI state. |
| 19 | [FarkleBoard.lua](../../Olympus_Arena/FarkleBoard.lua) | Bones/Farkle table window, controls and rules presentation. |
| 20 | [LotteryBoard.lua](../../Olympus_Arena/LotteryBoard.lua) | Lottery board presentation with remaining gated/practice paths. |
| 21 | [Games/GamesRules.lua](../../Olympus_Arena/Games/GamesRules.lua) | Pure rules in the practice UI namespace. |
| 22 | [Games/Games.lua](../../Olympus_Arena/Games/Games.lua) | Shared in-memory practice wallet and game-window support. |
| 23 | [Games/Bicho.lua](../../Olympus_Arena/Games/Bicho.lua) | Practice animal-lottery implementation; excluded from packaged builds. |
| 24 | [Games/Farkle.lua](../../Olympus_Arena/Games/Farkle.lua) | Bones practice/lesson UI and integration with the real table flow. |
| 25 | [Games/Hookup.lua](../../Olympus_Arena/Games/Hookup.lua) | Explicit test/simulation hookup for practice panes. |
| 26 | [Sim.lua](../../Olympus_Arena/Sim.lua) | Solo sample scenes and UI simulation entry point. |

## OlympusSiteAggregate

Dedicated, deliberate website aggregate exporter; requires Olympus. [OlympusSiteAggregate.toc](../../OlympusSiteAggregate/OlympusSiteAggregate.toc) contains 1 entries.

| Order | Source file | Purpose |
| --- | --- | --- |
| 1 | [SiteAggregate.lua](../../OlympusSiteAggregate/SiteAggregate.lua) | Validate a fresh own-guild checkpoint, mask counts and prepare only the dedicated SavedVariables export; no upload. |

## Other repository areas

| Path | Responsibility |
| --- | --- |
| [tests/](../../tests) | Offline scenarios, the gamepad integration pass, Arena tests and client fixtures. |
| [scripts/](../../scripts) | Validation, code/data generation, package assembly, signing helpers and deployment tooling. Start with `check.sh` and `package.sh`. |
| [.github/workflows/](../../.github/workflows) | Repository automation, including CI checks. |
| [media/](../../media) | Source artwork and related assets; installed addon media also lives under its addon folder. |
| [docs/](../README.md) | Engineering navigation, contracts, acceptance guides and historical design/release documents. |
| `dist/` (generated, ignored) | Local staging trees, ZIPs, checksums, manifests and other build artifacts. |

When adding, removing or reordering a TOC entry, update this table alongside the relevant feature chapter. A generated artifact is not a missing source module: document the script that produces it and the stage where it is inserted.
