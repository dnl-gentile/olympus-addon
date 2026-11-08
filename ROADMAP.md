# Roadmap

## Done
- v0.1 Army census: members, online, leaders, zones, world map markers, Discord export, bug capture
- v0.2 Tabard Inspection: patrol auto-inspect, manual marks (player and guild), Discord export
- v0.3 The Realm: King -> Lords -> Captains -> ranks tree, leader/officer offline days, inactive 7/30d,
  level race, recruiting (free slots); layers named after the highest ranked member; guildmates on map
  and minimap; royal decrees (Call to Arms / Muster) with raid warning and map marker; button in
  Blizzard's Guild window that docks the Olympus window next to it; realm-themed texts
- Later versions up to v1.0.1: see the [GitHub releases](https://github.com/dnl-gentile/olympus-addon/releases)
- v1.1.0 The Fernmelder release: the LFG board (`/oly lfg`), the King's week with sign-ups (`/oly week`),
  a crafters' board and loot notes, a sound switch per alert, census search and marked rows, the
  first-open privacy page, the inactive list and mentors, net-off, block terms, alt links, the key
  rotation, a pinned line, the treasury's extras and the weekly dues; Spanish, French and German
- v1.1.1 The Chat tab: the [Olympus], [Captains] and [Lords] chats in the Olympus window, with search,
  a box to write in and the settings behind the gear (mute, chat window, an Olympus tab in the game chat)
- v1.1.2 Right-click a player for their Olympus version (Ask to update, Tell them about Olympus); the
  answer bank; a ? on every page; bug reports on request; Chattynator tabs; marks on Olympus lines in
  the game's chat
- v1.1.3 Ordinary clicks never start a restricted `/who`: census and player searches only from their own
  controls
- v1.1.4 Crafters as its own tab; the side tabs keep one order when they run out of room
- v1.1.5 Three elite borders (the King gold, the High Council silver, guild masters bronze) and
  their marks in the game's own chat (`/oly chatmarks`), none on Olympus lines; councillors'
  tooltips; a guild the High Council removed is no Olympus guild, with an appeal through the signed
  approved list; `<OLYMPIANS>` approved; the version letters (`/oly letters`); Blizzard's player
  menus untouched in gamepad mode (#56); restricted secret values ignored safely; the Chat tab's
  second help "i" gone (the window's own, left of the X, is the one there); the gamepad gate (every
  way into the game's own UI listed and asked of one gate: with the gamepad UI no typed command, no
  button in the guild windows, nothing on the world map; a switch steps back and says what a
  `/reload` completes); the nameplate marks no longer hook a plate's own layout (Lua errors)
- v1.2.0 The Watch (each guild's moderation desk, the Tabards in it); crafting requests on the Crafters
  tab; the King's arrow on the minimap; Vox Populi's history and a guild master's own questions; the
  Guild treasuries in one list with one search; Bones between players for points, at a tavern or at a
  camp; no arbiters without bets (duels and Bones between their two players); duel points that
  consider levels; Find a player by level, distance and game
- v1.2.1 Bones table chat; Watch and Wanted relay fixes; weekly briefs; local chat label options
- v1.2.2 The stutter fixed (the level race's checks off the message handler, data changes taken once
  a second, the map left alone while closed, the minute jobs spread out) and `/oly perf`; the
  privacy page and Bones invitations; guild removal and rank changes; Church counts; chat reports to
  the King and the High Council; [Olympus] links; Shift + the guild key; the security reviews' fixes
- v1.2.3 The King's stream fixes; the Chat tab's memory; guild masters' decrees to their own guild; Most Wanted
  from members' own kills and deaths, bounties by office and level; the missionaries' crook
- v1.2.4 Implementation candidate: role rooms, retained signed game records, guild average levels,
  Church appointment catch-up, Heraldry guild duties and Wanted count fixes. Not published;
  Windows visual and multiplayer acceptance remain separate gates. Undefined departmental metrics
  and unrelated future backlog are not included as finished features.
- v1.2.5 Follow-up candidate: chat replies, finalized office shields, normalized honour presentation,
  safer shared rankings and relay queues, and predictable Most Wanted list expansion.
- v1.2.5.1 Hotfix: officers can return a guild separated by a mismatched private realm key to the
  public Olympus channel, restoring shared chat and live census relay without accepting an older key again.
- v1.3.0 Shared durable records and rankings; Church catch-up; Wanted and Slayers pagination,
  rebalanced history and recent map sightings; the current Legate structure; safer Watch records;
  Companion exports after the Accord; and integrated Arena, Bones and chat fixes.
- v1.3.2 Correction: explicitly approximate Census people counts, preserve accepted Treasury rows,
  fix full-suite ordering regressions and export consented Companion identity evidence.
- v1.3.3 Deliberate site export: an optional Site Aggregate folder writes a masked own-guild count for the
  Olympus website on /oly site export and /reload, never uploads, and empties at the next logout or reload.
- v1.5.2 While no relay of the High Council answers, a guild's census report goes as its reporter's own text in the joined channel (which Forever delivers to everyone in it) and everyone takes it from there, so the census keeps moving in a realm family whose relays are offline; a relay's copy later is the same report again. The dev's second PvP character is a launch pin of that family. A family's store also drops another family's counts-only rows at open, a plain Forever realm's group row counts as its family's server (never "another" beside it), and its ruleset is its family's.
- v1.5.3 Temporarily pause overdue verification notices for guild members. Guild master reminders, verification deadlines, approvals and High Council follow-up continue. Existing clients need this update to stop their local notice.
- v1.5.1 On a PvP character the census page tells PvP from PvE again (a Forever family's ruleset is its name, not a realm of the signed table), and a family's store never takes another family's census: the PvE census no longer merges into the PvP store when that character met no PvE realm, and reports of another family merged so before are dropped at the next open.
- v1.5.0 The Olympus chats (the three tiers, the role rooms, the arena's rooms) travel as the player's own text in the hidden channel, which Forever delivers to everyone in it across every sub-realm; the hidden way by the relay stays the fallback (no echo) and the gamepad UI's way. The High Council's relay now carries the whole army: other guilds' reports reach each reporter as a trickle (the newest of each guild, keyed), the relay sends its own global census snapshot every two minutes, a client's own-clock words are fanned out to nobody, and a relay's client sends four parts a pump. The 1.5.0 letter is the dev's own word: sorry for the delay, what broke on launch night, what works now.
- v1.4.6 Forever's sub-realms of one ruleset are one realm group (every guild sees the same census, the signed lists reach every sub-realm), the Council's relays pass each word to one another (no more islands), a client without the lists finds the launch's relays by code, and the first talk at the innkeeper opens the Bones lesson.
- v1.4.5 The guild keeps one reporter where the relay carries the channel (the never-heard guard is off there), a chat line reaches the sender's own guild at once over GUILD, and the signed King wears his crown on The Realm whatever his rank.
- v1.4.4 The morning after: a guild finds a live High Council relay at once (every relay pinged together, the message held for the first answer, the ones that answered preferred), the relay's whispers to offline councillors leave no line in the chat, the duty letters open in a window of their own as plain missives, and the party portraits' borders draw over the game's ring.
- v1.4.3 Launch night: WoW: Forever delivers nothing an addon says on a chat channel, so everything between guilds (the census, the signed lists, the key, the rankings' words, the chat) travels by addon whispers relayed through the High Council's clients, with no module changed; whispers reach every sub-realm by the plain name.
- v1.4.2 Launch night: the author's own character may take the army's key back (/oly key off) and his client answers key asks with the clear, so a guild sealed by mistake returns to the public lanes as its members log in.
- v1.4.1 Launch night: the army's channel moves to the next lane by itself when the game refuses it (WoW: Forever refused every send on OlympusNet), so every guild hears the others again; the signed list loads from the addon's own folder.
- v1.4.0 Launch: the census agrees across clients and counts every realm group (PvP and PvE, NA and EU)
  without beta numbers; launch identities from the signed list; the Church top three and the donors reach
  late clients through the King and the High Council; duty letters from the King for every office; seven
  languages; the army's key in a form only 1.4.0 reads; the send queue holds through throttles and lockdowns.

## Next (after the base is proven in game)
- **Compact reply cards after sending** - keep the existing reply composer, but render a sent reply in
  Olympus Chat with a short, visually separate quote card above the new message (WhatsApp-style)
  instead of exposing the full textual reply prefix inline. Deferred beyond v1.2.5.
- ~~Guild leader offline for X days~~ (v0.3)
- ~~**Guild leader offline for X days (alerts)** - `GetGuildRosterLastOnline(i)` gives years/months/days/hours for
  our own guild; add `leaderLastSeen` to the report so every guild's leader age shows up. Alert above N days.~~
  (1.1: one line when a Lord crosses `/oly warndays`.)
- ~~**Inactive players** - same API: count members offline > 7/14/30 days per guild; list for officers to kick.~~
  (1.1: your own guild's list by name, one removal per click.)
- ~~**Officers and org chart** - `GuildControlGetNumRanks` / `GuildControlGetRankName` + rankIndex per member:
  rank tree per guild (Leader -> Officers -> ranks -> counts), who is online per rank, officers in the report.~~
  (v0.3: the Realm's King, Lords and Captains and each guild's ranks with their counts; later each guild's
  members online.)
- ~~**Dues** (was tax collection) - Classic has no guild bank: track gold received through mail and trade from
  guild members (MAIL_INBOX_UPDATE / TRADE_* events), ledger per member, "who has not paid this week".~~
  (1.1: one fixed amount a week the King sets, counted from the treasury's books, never public.)
- ~~**Layers** - zoneUID from NPC GUIDs (`/oly layer` is the probe); sample from addon users per layer.~~
  (Each layer named after its highest ranked member since v0.3, announced by officers and a stable 1 in 8
  sample; the layer hop since v0.8.1.)
- ~~**Share inspections** between officers over OlympusNet so several inspectors build one list.~~
  (1.1: among your guild's officers over guild addon messages, `/oly patrolshare`, off until you say yes.)
- ~~**Verification badge** when two reporters of the same guild agree~~ (1.1: the census marks a row whose
  senders disagree, and one a single sender stands behind).
- ~~**Channels view** - per-tier history (`Channels.History`, `CHAT_CHANGED`) in the window.~~
  (1.1.1: the Chat tab.)
