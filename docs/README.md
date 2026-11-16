# Olympus documentation

Olympus is a Lua addon that runs inside World of Warcraft. It builds a shared guild census from game observations, coordinates guild activities, and provides recruiting, chat, moderation, maps and games. Its normal operation does not require a web service or desktop companion.

## Engineering guide

Start with the architecture, then follow the chapter for the part you are changing. These pages describe the current source, including which code is optional, disabled or omitted from packaged builds.

| Read | What it explains |
| --- | --- |
| [Architecture and startup](engineering/architecture.md) | Packages, load order, shared namespace, events and timers |
| [Data and census](engineering/data-and-census.md) | SavedVariables, roster observations, reports, freshness and aggregation |
| [Networking and trust](engineering/network-and-trust.md) | Reporter election, transport queues, relays, validation and permissions |
| [Feature map](engineering/features.md) | Every major product area, its responsibilities and implementation files |
| [Recruiting](engineering/recruiting.md) | JOIN intake, scanning, queue state, copy/paste, retries and join confirmation |
| [UI and gamepad integration](engineering/ui-and-gamepad.md) | Rendering, owned dialogs, protected UI boundaries and input-mode changes |
| [Arena and records](engineering/arena-and-records.md) | Games, load-on-demand screens, results, rankings and disabled wagering paths |
| [Integrations and exports](engineering/integrations.md) | Public API, Bridge, website export and separately distributed tools |
| [Development and troubleshooting](engineering/development.md) | Editing, tests, diagnostics, packaging and release verification |
| [Complete module map](engineering/module-map.md) | Every entry in the three addon TOCs, in load order, with its purpose |

## Existing detailed references

| Document | Use it for |
| --- | --- |
| [Player README](../README.md) | Features, installation, commands and player-facing privacy explanations |
| [Addon API](API.md) | Public integration methods, permissions, limits and examples |
| [Recruiting queue](RECRUIT-QUEUE.md) | Current queue behavior, focused checks and in-game acceptance steps |
| [Transport lifecycle](transport-lifecycle.md) | Queue ownership, cancellation, retries and transport compatibility |
| [Census statistics](CENSUS-STATS.md) | Sanitized census calculations and export contracts |
| [Website aggregate](SITE-AGGREGATE.md) | Exact export schema and deliberate export workflow |
| [Shared records](RECORDS.md) | Result reconciliation, inventories and monthly seals |
| [Witness record format](RECORD-FORMAT.md) | Local evidence file format and validation |
| [History carry](history-carry.md) | Portable history and its authority limits |
| [Beta testing](BETA-TESTING.md) | Broader automated and in-game acceptance gates |

Release notes and some older design documents describe earlier versions or proposed work. When a historical statement differs from the current implementation, follow the linked source and its tests. The engineering guide is a navigation aid; it is not a second protocol specification.
