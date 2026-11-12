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
- v1.5.4 On Forever the census reaches every guild: a relay sends each reporter its snapshot whole, one reporter at a time and wrapped once (XOData, PRs #81 and #82), keeps census reports in pieces, sends an integration's presentation to its own guild alone and keeps one guild per reporter; a guild elects one reporter across sub-realms and lanes; the channel-text fallback the game blocked is gone. Guildmates on other Forever sub-realms are recognised by their roster row, and their names show plain in Olympus chat (XOData). Guild verifications cross relays (RW) and each ask is answered to the client that asked. A trusted client's other-family totals count again. The signed King's crown, presence and layer reach every relay's guilds, and he shows online from his guild's report. Layer-hop asks go to the asker's own guild over GUILD; a layer on another Forever sub-realm is listed apart with its server's label, a hop there finishes after the player logs out and back in (or restarts the game), the pending hop kept in the saved variables for 15 minutes, and the hop is marked experimental with a window that tells the flow at the first ask. Dues History skips a Treasurer known offline (ArithmeticLogic, PR #86). A message's pieces keep their assembly open while they keep arriving, up to five minutes (fiddlecat, PR #80). The Horde is kept apart: its relays and verifiers come from the signed list's Horde entries (no King by code off the beta's realms on either side), Horde totals no longer appear in the Alliance census nor the Alliance's in the Horde's, and on the Horde a guild named by one of the community's Horde-race banter words counts as an Olympus guild. The Church's public scores, the guild masters' nominations and the shared block terms reach every guild: each goes as one list (LS, Comm.SendList), which the relay collects whole and hands to each guild's reporter whole, where word by word a reporter got one to four of the Church's twenty-two rows and no master's list in more than one part; a relay sends a guild only a list it does not hold, the Church's rows once an hour, within shares of its whispers kept for the senders it can trust, so a member's flood never keeps them out and the census keeps most of its room. Every guild's verification clock starts again on the release night, with 7 days of grace where it was 48 hours. Modified builds: a client whose announced version is no release (its guild check-in or its Check version answer) is marked in the right-click menu ("modified build"), listed by `/oly builds` in a copyable window, shared among guild masters, officers and the High Council (one word per sighting an hour, kept with the reporter's name, 400 at most), and locked out: its words are dropped at the door, a relay takes no registration from it and forwards nothing to it, until it announces a release; a guildmate who answers none of three version checks over five minutes while checking in is marked silent to version checks, never locked. The relays keep the shared list too, pass it to one another and lock a listed character out until it announces a release to one of them, a clearing they share as well. The author's relay asks each locked client online to update every 30 minutes, with his usual ask by whisper (20 at most). Clients identify themselves to the relays with their version; after the date in the release notes relays serve only published versions, under rules the author's client hands them in game.
- v1.5.5 The first of two parts. 1.5.6 continues work on sharing census data between relays. Census snapshots that cross the relays in many pieces arrive whole (grimreapper, PR #88). Every Olympus chat line reaches every member once, through a chat lane of the relay's own, and guildmates on other Forever sub-realms are no longer dropped. Chat and relay values the game keeps secret in dungeons and raids are left unread instead of raising errors; `/oly bug` has a debug section, and an install that does not fit the game (a copy in the wrong game folder) is told. The level race is paused and existing records are kept. The Wanted page names its realm group; verifiers see every guild with a verification start; a guild's bank snapshot is taken from its officer on any sub-realm; a keeper's donations off, the King's Agenda, its signup sheets and the gates arrive; the Companion bridge says which realm group and ruleset its Wanted data is. Item links in Olympus chat show their quality colours (grimreapper, PR #89).
- v1.5.6 Census delivery and guild tools. Signed relays actively discover peers and exchange complete census snapshots. Large transfers use verified forwarding through guild registrants, request missing pieces and fall back to the relay when a seed disappears. Clients prefer upgraded 1.5.6 bridges while retaining older bridges as a fallback. Enough newer guild reports replace the saved census even when an extra older row remains. The highest-average-level guild honour requires at least 950 members and uses the updated Census data. The package includes the author's signed lists. A signed author can see the private High Council, and verification notices move below the guilds on the King's Census screen. The King stays distinct from his guild master, with separate signed Treasurer and Quaestor roles. Verification holds await an appointed verifier where one is unavailable. Church history is consolidated across local characters and supported recruitment logs. Chat can be filtered by ruleset. Map naming, office shields and player-menu controls are revised. The first Bones lesson survives a roster update during gossip close, starts with the innkeeper and shows scoring groups gradually, pausing while the guide is open. Close and reopen WoW after updating to load the new network modules. Active relay clients need the update too.
- v1.5.7 Census startup and relay recovery. The saved count keeps its observation date while the header shows how many guilds have reported since login. Census transfers rotate guild coverage and age reports from their original observation. Church scores, Records and guild verification retry incomplete delivery. The optional personal Discord verification panel reports local delivery, and Olympus Prime can export its own aggregate manually. A recruitment ranking for all guild members is planned for a future update.
- v1.5.8 Recruiting and census. An officer who can invite turns recruiting on from the top of the Census or in Church > Invites, now the Church's first page (the choice is kept per character and guild). A player who whispers JOIN, with or without Olympus, opens a window with the /ginvite command, selected: the officer copies it (Ctrl+C), pastes it into the game's chat and presses Enter, because Forever blocks a /ginvite an addon fills in, so the invite is always the player's own; Queue only keeps requests in the list instead, and a request can be offered to another officer who accepts handoffs, or, opted in, to the guild's other officers while three or more wait. Public recruitment announcements name the recruiter's guild and post on a click or Enter; an optional reminder opens one every 2, 5, 10, 15 or 30 minutes, rotating through joined public channels, each channel with its own wait. Scan unguilded players (off by default) lists players without a guild seen nearby or in the player's own /who results (it starts no /who) for a copied invite, optional invite pop-ups or optional whisper drafts. Guild masters can ask the Apostles for recruiting help for 24 hours. A player without a guild gets the Join Olympus page at the first login: Request to join, a 45-second wait for the invite, Request again with another member and optional reminders. My Discord Verification is at the top of The Realm. The Census shows its connection (lane, relay, the latest other guild's report) and tells linked alts from the staff sample; relays answer census asks during their own broadcast, pack snapshots, try recent reporters when saved fallbacks do not answer and keep clients on a healthy lane. Church keepers recover verified recent history. The Watch can resend a guild approval, check the current guild master, hide guilds and copy names. Layer hop asks sister-guild helpers when no guildmate answers. Olympus guild chat gives each speaker a colour of their own. The Workshop names the last release marked in game beside the running build.
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
