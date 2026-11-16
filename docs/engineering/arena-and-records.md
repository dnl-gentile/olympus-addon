# Arena, games and records

[Documentation home](../README.md) · [Complete module map](module-map.md)

Arena is a domain inside Olympus, with a separate addon for its heavier screens. Seeing code for a game or wallet in the source does not establish that it is enabled in a distributed build. Permission gates, test/live mode and packaging exclusions all affect what runs.

## Domain code and screens

| Layer | Main files | Responsibility |
| --- | --- | --- |
| Pure calculations | `Olympus/ArenaMath.lua`, `ArenaRating.lua`, `ArenaBracket.lua`, `ArenaFarkle.lua`, `ArenaParse.lua` | Money arithmetic, ratings, brackets, dice/scoring and parsing of supplied observations |
| Runtime | `Olympus/ArenaNet.lua`, `ArenaRoles.lua`, `ArenaPlaces.lua` | Namespace, storage, protocol dispatch, roles, loader and known meeting places |
| Fights and results | `Olympus/ArenaFights.lua`, `ArenaTourney.lua`, `ArenaLedger.lua` | Challenges, fight cards, tournament progression and results |
| Bones | `Olympus/FarkleTable.lua`, `ArenaMatch.lua` | Table state, participant messages and matchmaking; player-facing Bones retains Farkle names in code |
| Social and observation | `Olympus/ArenaChat.lua`, `ArenaSpectate.lua`, `ArenaProfile.lua` | Fight rooms, observed duel state and preferences |
| Entry points and rehearsal | `Olympus/ArenaHome.lua`, `ArenaTest.lua` | Main-addon presentation, actions and test/rehearsal support |
| Screens | `Olympus_Arena/` | Window and pane registry, cards, brackets, boards, overlays, alerts and practice UI |

Files after the first path in a table cell share its directory. The [module map](module-map.md) links each file individually.

The main addon can receive and validate domain messages without loading every Arena screen. `Arena.LoadUI()` temporarily hands the host namespace to [Handoff.lua](../../Olympus_Arena/Handoff.lua), which checks compatibility. Arena's window uses registered panes and staff tabs; feature screens should extend that registry instead of editing unrelated pages.

Fight chat is presented through dynamic tabs in the main Olympus Chat page. The Arena `ChatPanel.lua` is an entry point to that shared room owner, not another independent history or audience authority.

## Live state, tests and lifetime

`ArenaNet.lua` owns mode-aware envelopes, such as an Arena message type followed by `L1` or `T1` and its body. Receivers validate the mode/version and feature permissions before applying messages. Rehearsal traffic must not become live results just because a body has the right fields.

Live state is partitioned under `ns.rdb.arena.realms[realm]`; test state uses `ns.rdb.arenaTest`. Heavy saved data attaches through `OlympusArenaDB` when the load-on-demand addon loads. Practice-game state in the Arena UI has a separate namespace and in-memory wallet; it must not be confused with a core ledger.

Packaging a test build generates `Olympus/TestBuild.lua` with the number, base version, build/expiry times and source commit. The current expiry policy turns **Arena off at login after expiry**; it does not expire the entire Olympus addon or interrupt an already-running match mid-session. Inspect [ArenaNet.lua](../../Olympus/ArenaNet.lua) and [package.sh](../../scripts/package.sh) together when changing this policy.

## Money and disabled wagering paths

[ArenaMoney.lua](../../Olympus/ArenaMoney.lua) watches eligible trade/mail observations and supplies guarded fill helpers. It does not complete a trade or send mail by itself. `Wallet.lua`, `Debts.lua`, `Stakes.lua`, `Markets.lua`, `MarketBank.lua` and `Lottery.lua` contain accounting, obligation or wagering-related paths, but their source presence is not a feature-enable flag.

[Compliance.lua](../../Olympus/Compliance.lua) currently has the wallet disabled and no enabled region declarations. Relevant UI, send and receive paths consult that policy; refunds have separate handling. This is an implementation policy, not a legal or platform certification.

Every ordinary package excludes the files listed in [bets-only.txt](../../scripts/bets-only.txt), currently `Olympus/Markets.lua`, `Olympus/MarketBank.lua` and `Olympus_Arena/Games/Bicho.lua`, and removes their TOC entries from the staged copy. The source TOCs retain them. Shared modules and the remaining Lottery UI still exist, with their gates and practice behavior. Review the actual package before describing a source-only feature as shipped.

## Two different record systems

| System | Owner | Purpose |
| --- | --- | --- |
| Shared result records | [Records.lua](../../Olympus/Records.lua) | Reconcile signed game/crafting evidence between participating clients and support rankings/history |
| Local witness file | [Record.lua](../../Olympus/Record.lua) | Optional local evidence chain stored in `OlympusRecordDB` for later inspection |

Shared results use stable identities and participant evidence. Conflicting verified results are not simply counted twice. Clients exchange bounded inventories/digests and reconcile what they hold; a local ranking reflects accepted local evidence, not a globally authoritative server database. Monthly seals have a separate offline author-signing workflow. See [RECORDS.md](../RECORDS.md).

The witness recorder is opt-in and has its own format and validation tooling. It is not the same store as the shared result inventory, nor an automatic upload. See [RECORD-FORMAT.md](../RECORD-FORMAT.md).

## Where to test a change

Pure rules and domain scenarios have coverage under [tests/arena](../../tests/arena). Native UI behavior also belongs in the gamepad pass. Test changes to results against duplicates, conflicting evidence and wrong-mode messages, not just a successful screen render. Package checks are necessary when a change touches the disabled wagering boundary, because tests against the full source tree alone do not prove the ZIP's contents.
