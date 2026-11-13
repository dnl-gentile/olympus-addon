local ADDON, ns = ...
local L = ns.L
local Relay = {}
ns.Relay = Relay

-- 1.4.3 (launch night, 2026-11-04). WoW: Forever's live realms accepted an addon's messages on any
-- player-made chat channel and delivered none of them, not even back to the sender (measured on launch
-- night: 0 of 123 members' messages heard in a minute; the beta delivered them, as Classic's beta
-- did before patch 1.13.3 cut it). (1.5.9) Two /oly bug reports of 2026-11-12 showed older clients'
-- census arriving on the public channel, OlympusNet (some 500 census pieces at a client there beyond
-- what its relay carried, beside words no relay hands on); not yet confirmed in game. Comm.ChannelSpec
-- puts every Forever client on that channel now. The guild and addon whispers are delivered, to any
-- player of the faction on any of Forever's sub-realms, by his plain "First Surname". So where names
-- split (ns.splitNames: Forever), everything the addon says "on the channel" travels like this
-- instead, and no module changes: the census, the signed lists, the key, the rankings' words, the chat.
--
--   hop 1  origin -> relay      RL~<f>~<text>            by whisper, to one relay (Pick)
--   hop 2  relay -> reporters   RM~<f>~<origin>~<text>   by whisper, one per guild (its reporter)
--   hop 3  reporter -> guild    RG~<f>~<origin>~<text>   over GUILD, once, to everyone there
--
-- The relays are the signed High Council's characters, the author's, the King and the Treasurer:
-- names every client holds from the signed list, so a guild that just arrived knows whom to
-- whisper. A client picks one relay (its guild's name decides which, changing every PICK_WINDOW so
-- the load spreads), pings it once (RP) and expects an answer (RA): a relay that does not answer
-- (offline, or an older version that cannot; the answer is RY: RA is the Records' ask) is left out for DEAD_FOR and the next one is picked;
-- the server's "No player named X" names an offline one at once. The relays know each guild's
-- reporter from its registration (RR, sent every REGISTER_EVERY while elected: Comm.MaybeBroadcast)
-- and forward to those alone; a reporter hands each message to its guild over GUILD once, where
-- every guildmate takes it as if it had come on the channel (Comm.Inject: the same handlers, the
-- origin as its sender). What came by the relay is taken once (Seen): a relay's copy and the
-- guild's copy of one message count once. <f> is L for a chat line (the origin sends it logged,
-- so his own words are on the server's log) and P for anything else. A piece too long for one
-- whisper travels in Codec's pieces (the assemblers put RL, RM and RG together like any other).
--
-- Trust: the server stamps every hop's sender. A relay is believed about the origin because it is
-- a signed councillor's, the author's, the King's or the Treasurer's character (RM from anyone else
-- is dropped); a reporter is believed by its guild because it is a guildmate (GUILD). Nothing here
-- lets a stranger speak as the King: his words still reach the guilds only through those clients.
-- Off Forever (the beta, Era, Anniversary) nothing here runs and the channel works as before.

--
-- 1.4.4 (the morning after): with one live relay among twenty signed names, a guild took up to an
-- hour to find it, picking one name at a time and waiting PING_WAIT for each. Now the first message
-- with no relay answered yet pings every relay at once (Sweep), is held for the first answer
-- (Flush, from HandleAck) and goes to whoever answered; the pick is made among the relays that
-- answered (VERIFIED_FOR) while any did. The server's "No player named X" for each ping to an
-- offline relay is kept out of the chat (Accord.Quiet) and still read (NotFound).
--
-- 1.5.4 (the presentation): a relay served whoever whispered it, so any build of the addon, changed
-- or not, could register as a guild's reporter and take every guild's feed. Now a client identifies
-- itself to its relay with its version, and from a deadline on a relay serves only clients that did
-- so with a published version (Relay.Admit, below): until then everyone, as before, so nobody loses
-- the census while the army updates. The deadline, a switch to pause it and the list of published
-- versions are the relay rules (RU): the author's client hands them to the relays in game and the
-- relays carry them to one another, so none of the three needs a release to change. A guild whose
-- members did not update still receives the census through a guildmate who did (hop 3, RG).

Relay.PICK_WINDOW = 600      -- seconds one relay serves a guild before the pick moves on
Relay.DEAD_FOR = 600         -- a relay that did not answer, or is offline, is left out this long
Relay.PING_WAIT = 30         -- an answer to the ping is due within this
Relay.VERIFIED_FOR = 900     -- a relay that answered is preferred this long (pinged again after DEAD_FOR)
Relay.PENDING_MAX = 40       -- messages held while no relay has answered yet
Relay.REGISTER_EVERY = 170   -- a reporter tells its relay it is the reporter this often
Relay.REPORTER_FOR = 600     -- a relay keeps a reporter this long past its last registration
Relay.SEEN_FOR = 300         -- a message taken is remembered this long (a second copy counts once)
Relay.SEEN_MAX = 2000
Relay.MAX_RELAYS = 40
Relay.MAX_GUILD_NAME = 48   -- (1.5.4) bytes: the game's 24 letters, accented ones taking 2, in a registration (RR)
Relay.MAX_REPORTERS = 400   -- (1.5.4) guilds a relay keeps a reporter for
-- (1.5.4) The presentation (HandleIn, HandlePresent, below). A client answered by a relay presents
-- itself to it with its version (RI~<version>, a word of its own, which no relay before 1.5.4 has a
-- handler for: an older relay ignores it and fans nothing out). A relay's answer to a ping is one
-- whisper as before: RY~<version> to a client it holds a presentation of, "RY~" (which every version
-- takes, and 1.5.3 and older nothing else) to any other. To a relay that named its version, a
-- reporter's registration names its own (RR~<guild>~<version>), which renews the presentation every
-- REGISTER_EVERY (a reporter's relay keeps it answered with every word it hands on, so it pings it
-- rarely). From the deadline on, a relay serves only a client that presented itself with a published
-- version; until then everyone. The deadline, its switch and the published versions are the relay
-- rules (RU, Relay.Rules): until a word of rules arrives, these constants are the rules.
-- PRESENT_REQUIRED_AT is set at release to the publish time plus seven days (this one, 1.5.5's:
-- 2026-11-17 21:00 UTC, seven days after its publish on 2026-11-10 21:00 UTC). Each release names
-- itself in PUBLISHED below (tests/relay-admit.lua checks it): a relay that holds no word of rules
-- goes by that list, and from the deadline on would refuse a release left off it.
Relay.PRESENT_REQUIRED_AT = 1794949200
Relay.PRESENT_FOR = 1800     -- a presentation is kept this long past its last word (a client pings its relay every DEAD_FOR)
Relay.PRESENT_GAP = 60       -- a client presents itself to one relay once this long at most
Relay.MAX_PRESENTED = 4000   -- characters a relay keeps a presentation for: every client that may whisper it, not only reporters
Relay.MAX_REFUSED = 200      -- refusals a relay notes for /oly relay admitted
Relay.PUBLISHED = { "1.4.0", "1.4.1", "1.4.3", "1.4.4", "1.4.5", "1.4.6", "1.5.0", "1.5.1", "1.5.2", "1.5.3", "1.5.4", "1.5.5", "1.5.6", "1.5.7", "1.5.8" }
Relay.RULES_EVERY = 1800     -- a relay asks the others for the rules this often; the author's client hands them out this often
Relay.MAX_RULE_VERSIONS = 40 -- versions one word of rules may name
Relay.VERIFY_ASK_EVERY = 180 -- one recovery ask across the signed relays, never per reporter
Relay.SNAPSHOT_WINDOW = 60  -- at most one bounded snapshot transfer per signed origin in this window
Relay.SET_WAIT = 60         -- idle seconds without a new piece
Relay.SET_MAX_AGE = 300     -- absolute assembly lifetime, even with continuing progress
Relay.ACROSS_MAX = 8        -- complete cross-relay transfers, including the one in flight
Relay.ACROSS_PER_PEER = 2   -- one peer cannot occupy the whole cross-relay backlog
Relay.LAUNCH_PINS = { ForeverPvE = { "Developus Olympicus", "Asmongold Thereal" }, ForeverPvP = { "Twalin Firebraid", "Elrond Oaklance" } }
-- (1.5.4) The above are Alliance characters: a Horde client's launch pins, by family, go here once
-- Horde ones exist (a whisper to an Alliance name never arrives on the Horde). None yet.
Relay.LAUNCH_PINS_HORDE = {}
-- (1.5.0) Words every client says on the channel on its own clock (the channel's hello H3, the
-- census ask Q1, the lists' ask HQ, positions P1, the Wanted list's ask W4, verification asks GV)
-- are heard by the relay and answered from there, but never fanned out: with 46 guilds registered
-- (the dev's log, 2026-11-05) each such word became 46 whispers, and the reports and the lists
-- waited behind them. A guild's census reports, the chats, the signed lists and every other word
-- go on to every reporter. Verification asks additionally cross signed relays at a bounded
-- cadence, without reaching reporters: the selected relay may not be the verifier holding a word.
Relay.NO_FORWARD = { H3 = true, Q1 = true, HQ = true, P1 = true, W4 = true, GV = true, CG = true }
-- (1.5.4) Guild verification between relays. A relay's own client counts itself as answered
-- (Pick), so it never pings the others and never learns that one answered: Across and the 1.5.2
-- crossing of verification asks went to nobody, and every verifier (the King, the High Council, the
-- author: each a relay) was an island. Verification alone now crosses, as RW, to every relay not
-- left out, answered or not: a verifier's decision (once, to each relay's reporters after), a
-- relay's own ask, one client's ask every VERIFY_ASK_EVERY, and a verifier's answer to a relay that
-- asked. RW never marks a relay as answered (verified), so no other word starts crossing (the census
-- alone would be every word a relay hears, times every other relay); older relays ignore the type.
-- (1.5.0) What one reporter can be sent of other clients' words that are not chat lines: pieces
-- a minute (REPORTER_RATE). 51 guilds reporting every three minutes, three pieces each, to 51
-- reporters is 2,700 pieces a minute; a relay sends 200. So each reporter gets a trickle of the
-- guilds' own reports, and the whole picture from the relay's own global census snapshot (CG,
-- Data.SendGlobalCensus: every guild's counts, trusted as the relay's signed name), sent every
-- GLOBAL_EVERY and exempt from the trickle, as the relay's own words all are.
Relay.REPORTER_RATE = 4
Relay.GLOBAL_EVERY = 120
-- (1.5.4) The King's crown (King.lua: T1~P where he is, T1~Q hidden again; his client says it every
-- 5 s while he moves, every 20 s while he stands) is what every member's map and minimap arrow
-- follow, and it reached nobody: his client, a relay itself, takes its own words to its own
-- reporters alone (relays hear one another only once one pinged the other); any other relay held
-- it in the trickle behind the guilds' reports; and his standing still was a second copy (Seen).
-- Now his client also whispers each crown to every other relay not left out, once each KING_GAP
-- at most; each relay hands the newest to its reporters, each once each KING_GAP at most and the
-- longest waiting first, KING_PER_MIN a minute in all (KING_BURST at once), ahead of the queue's
-- other words so a busy relay neither drops nor delays it; a repeat renews it wherever it arrives;
-- "hidden" goes to all at once. Clients keep it King.LOCATION_EXPIRE_RELAYED, past the slowest pace.
Relay.KING_GAP = 30
Relay.KING_PER_MIN = 40
Relay.KING_BURST = 20
local crownBucket = { tokens = 0, at = -math.huge } -- (on a relay) the crowns it may hand on now
local budget = {} -- reporter name (lower) -> { at = when refilled, left = pieces }
-- (The load review of the 1.5.4 candidate.) REPORTER_RATE to each reporter made the trickle grow with
-- the reporters: 35 of them could take 140 whispers a minute and 80 of them 320, more than a relay
-- sends in all (200), so the queue was never empty enough for a reporter's whole census snapshot
-- (the drip waits for room; the offline load model: about one whole snapshot per reporter in 20
-- minutes at 35 reporters, almost none at 80, and the trickle's own words gained nothing). The
-- trickle now shares TRICKLE_PER_MIN a minute among the reporters, REPORTER_RATE at most each (the
-- model: half again as many whole snapshots at 35 reporters and five times as many at 80, none left
-- without one at 35; more chat lines and decisions arrive). A whole allowance at a time, taken in
-- the order the words come, as before: REPORTER_RATE every minute up to 15 reporters, else three
-- whispers, a census report in two pieces, every 180 / share seconds. (The review of the candidate:
-- refilled a fraction at a time, it went to the first word that fitted one whisper, and a word in two
-- whispers, a census look in one chunk or any full piece, never found room beside the short ones.
-- The review again, mixed versions: an allowance of two above 20 reporters never held a report in
-- two pieces, three whispers, which 1.5.3 passed whenever its allowance was full, so no other guild's
-- full report reached any guild through a busy relay; an allowance holds three at the least now, the
-- same share a minute in a longer window.)
Relay.TRICKLE_PER_MIN = 60
local share = Relay.REPORTER_RATE -- each reporter's whispers a minute (ToReporters sets it)
local function Afford(name, pieces, now, need, word, first)
	local most = math.min(Relay.REPORTER_RATE, math.max(3, share))
	-- (The review of the candidate.) A piece of a word that needs more whispers than an allowance
	-- holds never reaches the reporter whole: it spends nothing (need: the least the word takes).
	if need and need > most then return false end
	local key = name:lower()
	local b = budget[key]
	local age = b and now - b.at
	-- (A clock set back starts a new allowance: the window never froze.)
	if not b or age < 0 or age >= 60 * most / share then
		b = { at = now, left = most, open = {}, last = b and b.open }; budget[key] = b
	end
	if word then
		-- (The review of the 1.5.4 candidate.) A word in pieces is paid for whole at its first piece
		-- (need), or refused there; its later pieces pass free once it is paid, in this allowance or
		-- the one before (a window turning over between two pieces). Charged piece by piece, an
		-- allowance partly spent let the short last piece through alone, or the full first one: a
		-- whisper wasted, and at every receiver an assembly that never closed (Comm's "incomplete
		-- reports"), the report itself never arriving.
		if not first then return b.open[word] == true or (b.last ~= nil and b.last[word] == true) end
		if b.open[word] then return true end
		if b.left < need then return false end
		b.left = b.left - need
		b.open[word] = true
		return true
	end
	if b.left < pieces then return false end
	b.left = b.left - pieces
	return true
end

local offline = {}   -- relay name (lower) -> until (ns.Now())
local verified = {}  -- relay name (lower) -> when its RA last came
local pinged = {}    -- relay name (lower) -> when we pinged it, while an answer is due
local reporters = {} -- (on a relay) guild name (lower) -> { name = "First Surname-Realm", t = when }
local seen = {}      -- origin .. "|" .. text -> when
local lastVerifyAsk = -math.huge
local snapshotTransfers = {}
local crownSent = {} -- "r:" reporter or "x:" relay (lower) -> when the King's crown last went to it
local crownLayer = {} -- (1.5.4) "l:" relay (lower) -> the King's layer word last whispered to it
local seenCount = 0
local pending = {}   -- (1.4.4) what waits for the first relay to answer: { parts, logged, done, key, urgent, options }
local holding = false -- a timer runs to send what waits anyway after PING_WAIT
local flushing = false
-- (1.5.4) The presentation (its own section, below; a relay's presentations are in its store).
local presentedMem = {} -- (on a relay, while no store is open) short name (lower) -> { name, v, t }
local refused = {}      -- (on a relay) short name (lower) -> { name, kind, why, t }: refusals noted for the report
local relayVersion = {} -- (on a client) relay short name (lower) -> the version its answer to our ping named
local presentedTo = {}  -- (on a client) relay short name (lower) -> when we last presented ourselves to it
local denied            -- (on a relay) the set another check hands over (Relay.SetDenied): short name (lower) -> true
local rulesSent = {}    -- (on a relay) relay short name (lower) -> the rules revision last handed to it
local lastRulesAsk, lastRulesSend = -math.huge, -math.huge
local stats = { out = 0, forwarded = 0, delivered = 0, dropped = 0, dead = 0, registered = 0,
	refused = 0, unpresented = 0, denied = 0, unserved = 0 }
-- (1.5.4) A client marked as a modified build (Builds.lua): a relay takes no registration from it,
-- drops one it holds and forwards nothing to it (Comm drops its words at the door already).
local function Quarantined(name)
	local B = ns.Builds
	return B ~= nil and not B.missing and type(name) == "string" and B.Quarantined(name) == true
end
function Relay.Stats()
	local n = 0
	for _, r in pairs(reporters) do n = n + 1 end
	local shown = Relay.PresentedCount()
	local relay, sure = Relay.Pick()
	return { out = stats.out, forwarded = stats.forwarded, delivered = stats.delivered, dropped = stats.dropped,
		dead = stats.dead, reporters = n, relay = relay, sure = sure == true, pending = #pending, on = Relay.On(),
		across = stats.across or 0, kept = stats.kept or 0, trickled = stats.trickled or 0,
		-- (1.5.4) Lists (LS) taken to the drip, ones that took a waiting one's place, ones refused, and
		-- ones every reporter held already.
		lists = stats.lists or 0, listsReplaced = stats.listsReplaced or 0, listsRefused = stats.listsRefused or 0,
		listsSame = stats.listsSame or 0,
		presented = shown, refused = stats.refused, unpresented = stats.unpresented, denied = stats.denied, unserved = stats.unserved,
		rules = Relay.Rules().rev, required = Relay.Required(),
		-- (The review of the 1.5.4 candidate: counted below, returned for /oly status, Diagnostics.lua.)
		verifyAcross = stats.verifyAcross or 0, direct = stats.direct or 0,
		-- (1.5.5) The chat lane: whispers waiting in it, lost (past its bound or its time), and skipped
		-- (nobody to send to by then: ChatAddressee).
		chatWaiting = Relay.ChatWaiting and Relay.ChatWaiting() or 0, chatLost = stats.chatLost or 0,
		chatSkipped = stats.chatSkipped or 0,
		-- (1.5.9's review) The drip's whispers handed to Comm: census transfers', the others', and those
		-- of either that went past its pace (Relay.DRIP_PER_MIN) while nothing else waited.
		dripCensus = stats.dripCensus or 0, dripOther = stats.dripOther or 0, dripFree = stats.dripFree or 0 }
end

local function Now() return ns.Now() end
local function Lower(s) return type(s) == "string" and s:lower() or "" end

-- (1.5.4) The King's crown, by his signed name (KING_GAP above), and whether one more is due to `to`.
local function Crown(origin, body)
	if type(body) ~= "string" or not body:match("^T1~[PQ]~") then return false end
	return type(origin) == "string" and ns.IsKingCharacter ~= nil and ns.IsKingCharacter(ns.FullName(origin)) == true
end
local function Hide(body) return body:match("^T1~Q~") ~= nil end
local function CrownDue(to, body, now)
	return Hide(body) or now - (crownSent[to] or -math.huge) >= Relay.KING_GAP
end

-- Where it runs: where the game splits names (Forever), unless switched off for a test.
function Relay.On()
	return ns.splitNames == true and ns.rdb ~= nil and ns.rdb.relayOff ~= true
end

-- The relays' names, as whispers reach them: the plain "First Surname", sorted; ours left out
-- unless asked for (IsRelay asks: our own client is a relay too).
-- (1.5.4) The Horde apart: a Horde client names only relays that can be Horde characters, those
-- the author's signed list names for its side (its King, its author characters, a Treasurer signed
-- for it). An Alliance name there was a relay nobody could reach: the whisper never arrives across
-- factions, so the name sat DEAD_FOR and the word fell back to the channel, which Forever did not
-- deliver (at launch; 1.5.9: older clients' census seen arriving on the public channel since, not yet
-- confirmed in game). The council's list names no side (every councillor is Alliance), the code's Treasurer
-- and the launch pins are Alliance characters: an Alliance client's names are as they were.
-- (1.5.5) signedOnly: the Treasurer's pins only where the signed list names them (Relay.IsSignedRelay).
function Relay.Names(withSelf, signedOnly)
	local out, set = {}, {}
	local mine = ns.ShortName(ns.me or ""):lower()
	local horde = ns.faction == "Horde"
	local function Add(n)
		if type(n) ~= "string" or n == "" then return end
		local short = ns.ShortName(n)
		local key = short:lower()
		if key == "" or set[key] or (not withSelf and key == mine) then return end
		if #out >= Relay.MAX_RELAYS then return end
		set[key] = true
		out[#out + 1] = short
	end
	local c = ns.rdb and ns.rdb.council
	if not horde and type(c) == "table" and type(c.names) == "table" then
		local list = {}
		for _, name in pairs(c.names) do list[#list + 1] = name end
		table.sort(list)
		for _, name in ipairs(list) do Add(name) end
	end
	if horde then
		if ns.AuthorCharactersOf then for _, n in ipairs((ns.AuthorCharactersOf("Horde"))) do Add(n) end end
	elseif ns.AuthorCharacters then
		for _, n in ipairs((ns.AuthorCharacters())) do Add(n) end
	end
	if ns.KingCharacter then Add(ns.KingCharacter()) end
	-- (1.4.6) A client with no signed list yet (a guild nobody handed it to) must still find a
	-- relay to get it from: the launch's author and King, by code, on their Forever family alone.
	local family = ns.ForeverFamily and ns.ForeverFamily(ns.realm)
	if family then
		local pins = horde and Relay.LAUNCH_PINS_HORDE or Relay.LAUNCH_PINS
		for _, p in ipairs(type(pins) == "table" and pins[family] or {}) do Add(p) end
	end
	if ns.TreasurerPins then
		local pins, signed = ns.TreasurerPins()
		if (not horde and not signedOnly) or signed == true then for _, n in ipairs(pins) do Add(n) end end
	end
	-- (1.5.5) The Quaestors the signed list names for our side (ns.QuaestorPins), never by code.
	if ns.QuaestorPins then for _, n in ipairs((ns.QuaestorPins(horde and "Horde" or "Alliance"))) do Add(n) end end
	table.sort(out)
	return out
end
function Relay.IsRelay(name)
	local key = ns.ShortName(name or ""):lower()
	if key == "" then return false end
	for _, n in ipairs(Relay.Names(true)) do if n:lower() == key then return true end end
	return false
end

local function Hash(text)
	local h = 5381
	for i = 1, #text do h = (h * 33 + text:byte(i)) % 2147483647 end
	return h
end
-- The relay this client whispers to now, and whether it is sure. A relay's own client, and a
-- serving provisional relay (RelayFallback.lua), carry their own words: themselves, no whisper
-- needed. (1.5.5) Anyone else, the first of:
--   (1) the relay a rebalance pinned (Relay.PinnedRelay), once it answered;
--   (2) the signed relays that answered a ping within VERIFIED_FOR, those whose answer named
--       PREFER_VERSION or newer first (the recovered mesh and tree ship in 1.5.6);
--   (3) the code's unsigned pins that answered, as transport alone (Relay.IsSignedRelay);
--   (4) the signed relays not left out, none answered yet: not sure (Out holds the word and pings);
--   (5) the provisional relays this client elected (RelayFallback.Elected), sure: each said yes or
--       answered our ping within VERIFIED_FOR;
-- else nil, and Out holds the word for HOLD_FOR: Forever's channel delivered nothing at launch (1.5.4
-- sent it there; 1.5.9: older clients' census seen arriving on the public channel since, not yet
-- confirmed in game). Within a step our guild's name and the window pick, so the load spreads.
Relay.PREFER_VERSION = "1.5.6"
local function Fallback()
	local F = ns.RelayFallback
	if type(F) == "table" and not F.missing then return F end
	return nil
end
local function Answered(key, now) return now - (verified[key] or -math.huge) < Relay.VERIFIED_FOR end
-- (The lanes' hooks, step 0's: asked through these so a hook a merge left out never stops the pick.)
local function IsSigned(name)
	local f = Relay.IsSignedRelay
	if type(f) == "function" then return f(name) == true end
	return Relay.IsRelay(name)
end
local function Pinned()
	local f = Relay.PinnedRelay
	return type(f) == "function" and f() or nil
end
local function Newer(key)
	local f = Relay.AtLeast
	return type(f) == "function" and f(relayVersion[key], Relay.PREFER_VERSION) == true
end
function Relay.Pick()
	if not Relay.On() then return nil end
	local now = Now()
	local F = Fallback()
	local function Picked(name, sure, why)
		if F and type(F.NotePick) == "function" then F.NotePick(name, why, now) end
		return name, sure
	end
	local mine = ns.ShortName(ns.me or "")
	if Relay.IsRelay(ns.me) then return Picked(mine, true, "self") end
	if F and F.Serving() then return Picked(mine, true, "provisional self") end
	local seed = Lower(GetGuildInfo and GetGuildInfo("player") or ns.me or "") .. "#" .. tostring(math.floor(now / Relay.PICK_WINDOW))
	local function From(pool) return pool[(Hash(seed) % #pool) + 1] end
	local pin = Pinned()
	if type(pin) == "string" and pin ~= "" then
		local key = Lower(ns.ShortName(pin))
		if (offline[key] or 0) <= now and Answered(key, now) then return Picked(ns.ShortName(pin), true, "pinned") end
	end
	local newer, signed, pins, live = {}, {}, {}, {}
	for _, n in ipairs(Relay.Names(false)) do
		local key = n:lower()
		if (offline[key] or 0) <= now then
			local isSigned = IsSigned(n)
			if not Answered(key, now) then
				if isSigned then live[#live + 1] = n end
			elseif not isSigned then pins[#pins + 1] = n
			elseif Newer(key) then newer[#newer + 1] = n
			else signed[#signed + 1] = n end
		end
	end
	if #newer > 0 then return Picked(From(newer), true, "signed " .. Relay.PREFER_VERSION) end
	if #signed > 0 then return Picked(From(signed), true, "signed") end
	if #pins > 0 then return Picked(From(pins), true, "unsigned pin") end
	if #live > 0 then return Picked(From(live), false, "not answered yet") end
	if F then
		local elected = F.Elected(now)
		if #elected > 0 then return Picked(From(elected), true, "provisional") end
	end
	return Picked(nil, nil, "none")
end
-- (1.5.5, for RelayFallback.lua) When `name` last answered our ping; whether it is left out now; a
-- signed relay but us that answered within VERIFIED_FOR; how many signed relays are not left out.
function Relay.AnsweredAt(name) return verified[Lower(ns.ShortName(name or ""))] end
function Relay.IsLeftOut(name) return (offline[Lower(ns.ShortName(name or ""))] or 0) > Now() end
function Relay.SignedAnswered(now)
	now = now or Now()
	for _, n in ipairs(Relay.Names(false)) do
		local key = n:lower()
		if (offline[key] or 0) <= now and Answered(key, now) and IsSigned(n) then return n end
	end
	return nil
end
function Relay.SignedLive(now)
	now = now or Now()
	local k = 0
	for _, n in ipairs(Relay.Names(false)) do
		if (offline[n:lower()] or 0) <= now and IsSigned(n) then k = k + 1 end
	end
	return k
end

local function LeaveOut(name, why)
	local key = ns.ShortName(name or ""):lower()
	if key == "" then return end
	offline[key] = Now() + Relay.DEAD_FOR
	pinged[key] = nil
	stats.dead = stats.dead + 1
	ns.Log("relay %s left out for %ds: %s", tostring(name), Relay.DEAD_FOR, tostring(why))
end
Relay.LeaveOut = LeaveOut

-- The envelope of hop 1 for one message: whole, or in pieces when a whisper cannot carry it.
local relayId = 0
local function Envelope(kind, text)
	if #text <= 255 then return { text } end
	relayId = (relayId + 1) % 1000
	return ns.Codec.Chunk(text, "R" .. relayId)
end

-- A relay not answered lately is pinged once; no answer in PING_WAIT leaves it out.
-- The server's "No player named X" for a whisper to someone offline: kept out of the chat for the
-- Accord's quiet window (Accord.Quiet, gated there); NotFound still reads the event.
local function Quiet(name)
	local A = ns.Accord
	if type(A) == "table" and type(A.Quiet) == "function" then ns.SafeCall("relay quiet", A.Quiet, name) end
end
Relay.Quiet = Quiet

local function Ping(relay)
	local key = relay:lower()
	local now = Now()
	if now - (verified[key] or -math.huge) < Relay.DEAD_FOR then return end
	if pinged[key] then return end
	pinged[key] = now
	Quiet(relay)
	ns.Comm.Whisper(relay, "RL~P~RP~", "relay ping:" .. key, true)
	ns.After(Relay.PING_WAIT, "relay ping", function()
		if pinged[key] == now and now - (verified[key] or -math.huge) >= Relay.DEAD_FOR then
			pinged[key] = nil
			LeaveOut(relay, "no answer to the ping")
		end
	end)
end
-- (1.4.4) Every relay not answered yet, pinged at once (one short whisper each): the first answer
-- takes what waits (HandleAck -> Flush); the offline ones the server names at once (NotFound), the
-- rest fall out after PING_WAIT, and each stays out for DEAD_FOR before it is pinged again.
local function Sweep()
	local now = Now()
	for _, n in ipairs(Relay.Names(false)) do
		if (offline[n:lower()] or 0) <= now then Ping(n) end
	end
end
Relay.Sweep = Sweep

-- (1.5.5) A relay named again (a provisional relay's "no", or its stand-down, named one it reached:
-- RelayFallback.lua): its left-out mark goes and it is pinged now.
function Relay.Reconsider(name)
	local short = ns.ShortName(name or "") or ""
	if short == "" or not Relay.IsRelay(short) then return false end
	local key = short:lower()
	offline[key], pinged[key] = nil, nil
	Ping(short)
	return true
end

-- Held for the first relay to answer. A keyed message takes a waiting one's place, as in Comm's
-- queue (the newest payload, a supplied callback replaces the old one); past PENDING_MAX the
-- oldest is dropped (its callback told, "dropped").
-- (1.5.5) Held HOLD_FOR at most for a relay picked sure (Daniel: "eu não quero que nenhum dado seja
-- perdido"): the signed relays are swept once a PING_WAIT at most and the provisional relays elected
-- meanwhile (RelayFallback.lua), and what waited goes to the first relay picked sure, signed or
-- provisional. 1.5.4 sent it on after PING_WAIT to a relay that had not answered, or with none to
-- pick on Forever's channel, which delivered nothing at launch: both lost it. Past HOLD_FOR its callback hears
-- "norelay" (counted, /oly bug), once.
Relay.HOLD_FOR = 600
local lastLook = -math.huge
local function Hold(parts, logged, done, key, urgent, options, at, copied)
	at = at or Now()
	if key then
		for _, p in ipairs(pending) do
			if p.key == key then
				p.parts, p.logged, p.urgent, p.options, p.at, p.copied = parts, logged, urgent, options, at, copied
				p.done = done or p.done
				return
			end
		end
	end
	if #pending >= Relay.PENDING_MAX then
		local old = table.remove(pending, 1)
		stats.holdDropped = (stats.holdDropped or 0) + 1
		if old.done then ns.SafeCall("relay done", old.done, false, "dropped") end
	end
	pending[#pending + 1] = { parts = parts, logged = logged, done = done, key = key, urgent = urgent, options = options, at = at, copied = copied }
end
-- What waited HOLD_FOR goes, its callback told "norelay".
local function Expire(now)
	local kept, gone = {}, {}
	for _, p in ipairs(pending) do
		if now - (p.at or now) >= Relay.HOLD_FOR then gone[#gone + 1] = p else kept[#kept + 1] = p end
	end
	if #gone == 0 then return end
	pending = kept
	stats.norelay = (stats.norelay or 0) + #gone
	ns.Log("relay: %d word(s) held %ds with no relay to take them: dropped", #gone, Relay.HOLD_FOR)
	for _, p in ipairs(gone) do
		if p.done then ns.SafeCall("relay done", p.done, false, "norelay") end
	end
end
-- A relay to take what waits: the signed relays pinged (once a PING_WAIT at most when none is
-- live), and the provisional relays' election run where this client elects (RelayFallback.Want).
local function LookForRelay(none)
	local now = Now()
	if not none or now - lastLook >= Relay.PING_WAIT then
		lastLook = now
		Sweep()
	end
	local F = Fallback()
	if F and type(F.Want) == "function" then ns.SafeCall("relay fallback", F.Want, now) end
end
-- What waited goes out to the relay picked now, once one is picked sure (an answer, or a provisional
-- relay elected); else, from the hold's timer (anyway), the stale ones go and a relay is looked for.
-- (1.5.5) A provisional relay hears first that a relay answered us (RelayFallback.Answered): a
-- signed one ends its service.
local function Flush(anyway)
	local F = Fallback()
	if F and type(F.Answered) == "function" then ns.SafeCall("relay fallback", F.Answered) end
	if flushing or #pending == 0 then return end
	local relay, sure = Relay.Pick()
	if not sure then
		if anyway then
			Expire(Now())
			if #pending > 0 then LookForRelay(relay == nil) end
		end
		return
	end
	flushing = true
	local list = pending
	pending = {}
	for _, p in ipairs(list) do
		if not Relay.Out(p.parts, p.logged, p.done, p.key, p.urgent, p.options, true, p.at, p.copied) and p.done then
			ns.SafeCall("relay done", p.done, false, "norelay")
		end
	end
	flushing = false
end
Relay.Flush = Flush
-- While anything waits: looked at again every PING_WAIT (Flush, anyway).
local function HoldTimer()
	if holding then return end
	holding = true
	ns.After(Relay.PING_WAIT + 1, "relay hold", function()
		holding = false
		Flush(true)
		if #pending > 0 then HoldTimer() end
	end)
end
-- (1.5.5) What waits and what HOLD_FOR dropped, for RelayFallback.Stats (/oly bug); the look's clock (tests).
function Relay.HoldStats()
	return { held = #pending, norelay = stats.norelay or 0, dropped = stats.holdDropped or 0, refused = stats.refusedOut or 0 }
end
function Relay.ResetHold() lastLook = -math.huge end

-- Hop 1: what a module said "on the channel" goes to our relay. parts: the message's pieces as the
-- channel would carry them (each one whisper). Returns true when handed to the queue.
local ToGuild, Seen -- (below: hop 3; a word taken once)
local function PermitParts(parts, options)
	for _, p in ipairs(parts) do
		local ok, valid, why = true, true
		if options and options.guard then ok, valid = pcall(options.guard) end
		if ok and valid == true and options and options.permit then
			ok, valid, why = pcall(options.permit, options.owner, options.guardKey, "CHANNEL", nil, p)
		end
		if not ok or valid ~= true then return false, why or "guard" end
	end
	return true
end

-- (The layer hop on Forever, after 1.5.3.) A layer-hop ask (LQ) and the King-sighting query (LY~Q)
-- are for helpers who can answer them, and on Forever those are the asker's own guildmates:
-- Hop.Member takes another guild's ordinary member for a stranger, a relay hands another client's
-- word to a reporter only within REPORTER_RATE (the dev's relay on 2026-11-07: about 149 words a
-- minute for 34 reporters, four of them passed a minute), and a word that passes waits in the
-- relay's queue past the ask's NOBODY window. So these go to the asker's guild at once over GUILD,
-- as the relay's hand-over from himself (RG, which 1.5.3 guildmates already take:
-- Relay.HandleGuild), and to no relay. Layer words (L1, L0) go to the guild at once as well, and
-- still to the relay. The origin is the plain name: Forever's roster files every guildmate by his
-- bare name under the reader's own sub-realm, so a name stamped with another sub-realm missed that
-- row and the guildmate was a stranger (Hop.Member, Roster.RankOf).
Relay.GUILD_ONLY = { LQ = true } -- (and LY~Q, GuildRoute)
Relay.GUILD_TOO = { L0 = true, L1 = true }
local function GuildRoute(text)
	if type(text) ~= "string" then return nil end
	if Relay.GUILD_ONLY[text:sub(1, 2)] or text:find("^LY~Q~") then return "only" end
	if Relay.GUILD_TOO[text:sub(1, 2)] then return "too" end
	return nil
end
Relay.GuildRoute = GuildRoute
-- nil when it cannot be wrapped (then the relay as before); else whether Comm took it.
local function OwnGuild(original, done, key, urgent, options)
	local me = ns.ShortName(ns.me or "") or ""
	local wrapped = "RG~P~" .. me .. "~" .. original
	if me == "" or #wrapped > 255 then return nil end
	local pass = { owner = options and options.owner or Relay, guard = function()
		-- The wrapped text names no type Comm's holds read: the original's are asked here, at the
		-- actual send, as Comm asks the original's on the channel (quiet presence, net-off).
		if ns.Comm.QuietHolds and ns.Comm.QuietHolds(original) then return false, "quiet" end
		local M = ns.Moderation
		if type(M) == "table" and not M.missing and type(M.Blocks) == "function" and M.Blocks(original) == true then
			return false, "held"
		end
		if options and options.guard then
			local ok, valid, why = pcall(options.guard)
			if not ok or valid ~= true then return false, why or "guard" end
		end
		return true
	end }
	if options and options.permit then
		-- The owner's permit keeps seeing its original lane and payload (as Relay.Out's whispers do).
		pass.key = options.guardKey
		pass.permit = function(owner, guardKey, dist, target, message)
			if owner ~= options.owner or guardKey ~= options.guardKey or dist ~= "GUILD" or target ~= nil
				or message ~= wrapped then return false, "lane" end
			return options.permit(owner, guardKey, "CHANNEL", nil, original)
		end
	end
	return ns.Comm.Send("GUILD", wrapped, key and ("guild " .. key) or nil, urgent, false, done, pass) ~= false
end

-- (1.5.4, the presentation: the client's side.) A relay's version, from its answer to our ping
-- (RY~<version>, HandleAck: a 1.5.4 relay names it once it holds our presentation); nil for an
-- older relay, which answers "RY~" alone, and for one not answered so yet.
function Relay.RelayVersion(name) return relayVersion[Lower(ns.ShortName(name or ""))] end
-- A registration to a relay that named its version names ours: RR~<guild>~<version>. An older
-- relay never sees that form (its RR takes everything after RR~ as the guild's name).
local function Identify(parts, relay)
	if #parts ~= 1 or type(parts[1]) ~= "string" or not parts[1]:match("^RR~[^~]+$") or not Relay.RelayVersion(relay) then return parts end
	return { parts[1] .. "~" .. tostring(ns.VERSION) }
end
-- A relay answered our ping: its version remembered when it names one, and we present ourselves to
-- it (RI~<version>), once a PRESENT_GAP at most: urgent, and queued before what waited for its
-- answer (HandleAck flushes after this), so the relay holds it before our words reach it. An older
-- relay has no handler for RI: it ignores it and fans nothing out.
local function PresentTo(sender, named)
	local short = ns.ShortName(sender or "") or ""
	if short == "" then return false end
	local key, now = short:lower(), Now()
	local version = Relay.VersionOf(named)
	if version then relayVersion[key] = version end
	if now - (presentedTo[key] or -math.huge) < Relay.PRESENT_GAP then return false end
	presentedTo[key] = now
	Quiet(short)
	ns.Comm.Whisper(short, "RI~" .. tostring(ns.VERSION), "relay present:" .. key, true)
	return true
end

-- (1.5.4) The King's own crown, to every other relay not left out: one whisper each, once each
-- KING_GAP at most, ahead of his queue's other words; the relay picked has it by the usual hop below.
local function CrownToRelays(parts, pick)
	if not (ns.me and ns.IsKingCharacter and ns.IsKingCharacter(ns.me)) then return end
	local now, mine, picked = Now(), Lower(ns.ShortName(ns.me)), Lower(pick)
	for _, p in ipairs(parts) do
		-- (His presence, T1~o every King.PRESENCE_EVERY, goes the same way, on its own gap slot: a
		-- relay never pings another, so the other relays' guilds heard it from nobody.)
		local presence = type(p) == "string" and p:match("^T1~o~%d+~") ~= nil
		-- (And his layer, L1 or L0: when it changes, else once each KING_REFRESH, as relays hand it on.)
		local layer = type(p) == "string" and p:match("^L[01]~") ~= nil
		if type(p) == "string" and (p:match("^T1~[PQ]~") or presence or layer) then
			for _, n in ipairs(Relay.Names(false)) do
				local to = Lower(n)
				local slot = (presence and "o:" or layer and "l:" or "x:") .. to
				local due = presence or (layer and (crownLayer[slot] ~= p or now - (crownSent[slot] or -math.huge) >= Relay.KING_REFRESH))
					or (not layer and CrownDue(slot, p, now))
				if to ~= mine and to ~= picked and (offline[to] or 0) <= now and due then
					if layer then crownLayer[slot] = p end
					crownSent[slot] = now
					Quiet(n)
					ns.Comm.Whisper(n, "RL~P~" .. p, (presence and "presence " or layer and "layer " or "crown ") .. to, true, false)
				end
			end
		end
	end
end
-- (1.5.5) A word our guild has at once while no relay is there (Out): a single one that is no census
-- report of ours, no registration and no ask only a relay answers (NO_FORWARD; a verifier's decision
-- goes), nor one GuildRoute gave the guild already. Our own census report is each guildmate's own.
local function GuildCopy(parts)
	local p = parts[1]
	if #parts ~= 1 or type(p) ~= "string" then return false end
	local approval = Relay.ApprovalResendGuild(p)
	if approval then return Lower(approval) == Lower(GetGuildInfo("player") or "") end
	if p:match("^C%w+:%d+:%d+:") or p:match("^RR~") or GuildRoute(p) then return false end
	if Relay.NO_FORWARD[p:sub(1, 2)] and not p:match("^GV~1~[ARS]~") then return false end
	return true
end
local function OwnReport(parts) return type(parts[1]) == "string" and parts[1]:match("^C%w+:1:%d+:R[12]~") ~= nil end
-- A relay that may carry our words: a signed relay (or a code pin), or a provisional relay we elected.
local function Carrier(name)
	if Relay.IsRelay(name) then return true end
	local F = Fallback()
	return F ~= nil and type(F.IsElected) == "function" and F.IsElected(name) == true
end
-- The word to one relay. True always: handed on, or refused with its callback told (once).
local function SendTo(relay, parts, logged, done, key, urgent, options)
	local flag = logged and "L" or "P"
	parts = Identify(parts, relay) -- (1.5.4: a registration names our version to a relay that named its own)
	-- Our own client the relay: handed to it here, whole (a whisper to oneself is never delivered).
	if relay:lower() == ns.ShortName(ns.me or ""):lower() then
		-- No physical queue exists on this route. Apply the same logical-channel
		-- guards before handing off any part, including a transfer held for a ping.
		local valid, why = PermitParts(parts, options)
		if not valid then
			if done then ns.SafeCall("relay done", done, false, why) end
			return true -- handled refusal; never fall back to an unguarded channel send
		end
		stats.out = stats.out + 1
		for _, p in ipairs(parts) do Relay.HandleIn("WHISPER", ns.me, "RL~" .. flag .. "~" .. p) end
		if done then ns.SafeCall("relay done", done, true) end
		return true
	end
	local pieces, originals = {}, {}
	for _, p in ipairs(parts) do
		for _, e in ipairs(Envelope("RL", "RL~" .. flag .. "~" .. p)) do
			pieces[#pieces + 1], originals[e] = e, p
		end
	end
	-- (1.5.5) Too long for one transfer: refused, its callback told once. 1.5.4 returned false and
	-- Comm put it on the channel, with the same callback to tell a second time.
	if #pieces == 0 or #pieces > ns.Codec.MAX_CHUNKS then
		stats.refusedOut = (stats.refusedOut or 0) + 1
		if done then ns.SafeCall("relay done", done, false, "size") end
		return true
	end
	Ping(relay)
	Quiet(relay)
	stats.out = stats.out + 1
	local pass
	if options then
		pass = { owner = options.owner, guard = options.guard, guardKey = options.guardKey }
		if options.permit then
			-- Comm normalized key -> guardKey on the logical CHANNEL job. Restore
			-- the public capability shape when creating its physical WHISPER job.
			-- Only these exact envelopes to this still-signed (or still-elected) relay may spend it;
			-- the owner's permit continues to see its original lane and payload.
			pass.key = options.guardKey
			pass.permit = function(owner, guardKey, dist, target, message)
				local original = originals[message]
				if owner ~= options.owner or guardKey ~= options.guardKey or dist ~= "WHISPER"
					or target ~= relay or not Carrier(target) or not original then return false, "lane" end
				return options.permit(owner, guardKey, "CHANNEL", nil, original)
			end
		end
	end
	if #pieces == 1 then ns.Comm.Whisper(relay, pieces[1], key, urgent, logged, done, pass)
	else ns.Comm.SendBatch("WHISPER", pieces, key, relay, urgent, done, pass) end
	return true
end
-- (1.5.5) Out takes every word it is handed on Forever and tells its callback once: sent, refused,
-- dropped, or "norelay" past HOLD_FOR (Comm makes no channel job there any more). False only where
-- the relay does not run (off Forever). at, copied: a held word's first hold, and whether our guild
-- had its copy then (Flush hands them back).
function Relay.Out(parts, logged, done, key, urgent, options, anyway, at, copied)
	if not Relay.On() then return false end
	if not anyway and not logged and #parts == 1 and IsInGuild() then
		local route = GuildRoute(parts[1])
		if route == "only" then
			if OwnGuild(parts[1], done, key, urgent, options) ~= nil then return true end
		elseif route == "too" then
			OwnGuild(parts[1], nil, key, urgent, options)
		end
	end
	local relay, sure = Relay.Pick()
	if relay and not anyway then CrownToRelays(parts, relay) end
	-- (1.4.5) A chat line reaches the sender's own guild at once, over GUILD, as hop 3 from himself,
	-- whatever the relays do (one dead, none answered yet): guildmates take it once (Seen), and
	-- the relay's copy that comes back later counts once too. The relay still carries it to the
	-- other guilds. The flush of a held line sends to the guild no second time.
	if logged and not anyway and IsInGuild() then
		local valid, why = PermitParts(parts, options)
		if not valid then
			if done then ns.SafeCall("relay done", done, false, why) end
			return true
		end
		-- (The review of the 1.5.4 candidate.) Our line is taken here by our plain name as it leaves,
		-- as Deliver takes a chat line: the copies that come back, our own client the relay (its
		-- reporter branch) or another relay's RM naming us as its client stamped us, are this line,
		-- and were handed to the guild a second time, shown to us again under the other stamp.
		for _, p in ipairs(parts) do
			if ToGuild("L", ns.me, p) then Seen(ns.ShortName(ns.me), p) end
		end
	end
	if not sure then
		if not anyway then
			-- A held message is refused now, as its whispers would be later, when the capability
			-- that guards it refuses it (1.5.2 checked it for the text fallback, gone in 1.5.4).
			local valid, why = PermitParts(parts, options)
			if not valid then
				if done then ns.SafeCall("relay done", done, false, why) end
				return true
			end
			-- (1.5.5) No relay at all: our guild has a single word at once, as a relay would hand it
			-- (RG from ourselves, OwnGuild), whatever becomes of it on the way to the others.
			if not relay and not logged and IsInGuild() and GuildCopy(parts) then
				OwnGuild(parts[1], nil, key, urgent, options)
				copied = true
			end
		end
		-- (1.4.4) No relay answered yet: all pinged at once, the message held for the first answer.
		-- (1.5.4: no channel text meanwhile; ChatHall.lua says why.) (1.5.5) Held HOLD_FOR at most.
		LookForRelay(relay == nil)
		Hold(parts, logged, done, key, urgent, options, at, copied)
		HoldTimer()
		return true
	end
	-- (1.5.5) While provisional relays carry our words, our census report goes to two of them (its
	-- guild's hash picks which): a row counts where two provisional snapshots agree (Data's witnesses).
	local F = Fallback()
	if OwnReport(parts) and F and not Relay.IsRelay(ns.me) and F.Active() then
		local targets = F.ReportTargets(GetGuildInfo and GetGuildInfo("player") or ns.me or "")
		if #targets > 1 then
			local left, ok = #targets, false
			local function Each(sent, why)
				left, ok = left - 1, ok or sent == true
				if left == 0 and done then ns.SafeCall("relay done", done, ok, (not ok) and (why or "failed") or nil) end
			end
			for _, target in ipairs(targets) do SendTo(target, parts, logged, Each, nil, urgent, options) end
			return true
		end
	end
	-- (1.5.5) A provisional relay hands no other origin's word on: our guild has a single word at once
	-- (unless it had it when the word was held), as it would from a signed relay's hand-over.
	if not copied and not logged and IsInGuild() and not Relay.IsRelay(relay)
		and relay:lower() ~= ns.ShortName(ns.me or ""):lower() and GuildCopy(parts) then
		OwnGuild(parts[1], nil, key, urgent, options)
	end
	return SendTo(relay, parts, logged, done, key, urgent, options)
end

-- The reporter's registration (Comm.MaybeBroadcast, every REGISTER_EVERY while elected).
local lastRegister = -math.huge
function Relay.Register(force)
	if not Relay.On() then return false end
	local now = Now()
	if not force and now - lastRegister < Relay.REGISTER_EVERY then return false end
	local guild = GetGuildInfo and GetGuildInfo("player")
	if type(guild) ~= "string" or guild == "" then return false end
	lastRegister = now
	return Relay.Out({ "RR~" .. guild }, false, nil, "relay register", false)
end

-- (1.5.4) A registration this relay holds from `name` goes (Builds.lua, when it marks a client as a
-- modified build); the guilds it reported for register again with another reporter. How many went.
function Relay.DropReporter(name)
	if type(name) ~= "string" or name == "" then return 0 end
	local key, short, n = Lower(ns.FullName(name)), Lower(ns.ShortName(name)), 0
	for g, r in pairs(reporters) do
		if Lower(r.name) == key or (ns.splitNames and Lower(ns.ShortName(r.name)) == short) then
			reporters[g] = nil
			n = n + 1
		end
	end
	if n > 0 then ns.Log("relay: %s's registration dropped (modified build)", tostring(name)) end
	return n
end

-- Taking a message and deciding whether to forward it use the same age limit. An expired
-- key may remain in this bounded table until cleanup; its presence alone is not a duplicate.
local function Remembered(origin, text, now)
	local at = seen[Lower(origin) .. "|" .. text]
	return at ~= nil and (now or Now()) - at < Relay.SEEN_FOR
end

-- Taken once: a message by its origin and text (the relay's copy and the guild's count once).
Seen = function(origin, text)
	local now = Now()
	local key = Lower(origin) .. "|" .. text
	if Remembered(origin, text, now) then return true end
	if seenCount >= Relay.SEEN_MAX then
		for k, t in pairs(seen) do
			if now - t >= Relay.SEEN_FOR then seen[k] = nil seenCount = seenCount - 1 end
		end
		if seenCount >= Relay.SEEN_MAX then wipe(seen) seenCount = 0 end
	end
	if not seen[key] then seenCount = seenCount + 1 end
	seen[key] = now
	return false
end

-- The last hop on this client: the message as if it had come on the channel from its origin.
local function Deliver(origin, text, logged)
	-- (1.5.4) The King's crown again (him standing still: the same words every 20 s) renews it.
	if Seen(origin, text) and not (text:match("^T1~P~") and Crown(origin, text)) then return false end
	-- (The review of the 1.5.4 candidate.) A layer word (L1, L0: GUILD_TOO) reaches the origin's
	-- guildmates twice: his own copy over GUILD names him plain (OwnGuild), the relay's copy as the
	-- relay's client stamped him, "Name-<its sub-realm>". Layers counted him twice, and a reporter
	-- handed the relay's copy to the guild again. A name is one across a Forever family: one word,
	-- once, whichever copy came first. (The review of the candidate.) A chat line travels both ways
	-- too (Relay.Out: hop 3 from the sender himself, and the relay's copy): a guildmate on another
	-- sub-realm than the relay's was shown twice, his reporter handed the relay's copy to the guild
	-- under the relay's stamp, and the sender saw his own line come back under it.
	if (GuildRoute(text) == "too" or logged) and origin:find("-", 1, true) and Seen(ns.ShortName(origin), text) then return false end
	stats.delivered = stats.delivered + 1
	ns.Comm.Inject("CHANNEL", origin, text, logged)
	return true
end

-- A reporter hands a message to its guild once (hop 3). (1.5.5) A chat line (flag L) goes urgent: a
-- reporter hands its guild every word its relay sends, at one whisper every 1.2 s, and an ordinary
-- chat line was the first a full queue pushed out, for its whole guild and for good.
ToGuild = function(flag, origin, text)
	if not IsInGuild() then return false end
	local pieces = Envelope("RG", "RG~" .. flag .. "~" .. origin .. "~" .. text)
	local urgent = flag == "L"
	if #pieces == 1 then return ns.Comm.Send("GUILD", pieces[1], nil, urgent, false) ~= false end
	return ns.Comm.SendBatch("GUILD", pieces, nil, nil, urgent) ~= false
end

-- A word to every guild's reporter we hold (ours included: delivered here and handed to our
-- guild), and heard here (a relay in a guild whose reporter is elsewhere, or none).
-- A Watch resend carries one original approval in the existing snapshot format. Its final
-- semicolon separates it from automatic snapshot replies, which must never fan out this way.
function Relay.ApprovalResendGuild(body)
	return body:match("^GV~1~S~%d+~A,%d+,([^,;~]+),[^,;~]+,[^,;~]+;$")
end

local function QueueWord(body)
	-- Fragment i and fragment i+1 are both required. Coalescing them by the first
	-- two bytes (C1, etc.) discarded all but the last before the queue could send.
	-- (1.5.4) The Throne's kinds apart too: the King's newest crown never takes a waiting call's place.
	-- (The review of the 1.5.4 candidate.) And each of the Treasurer's mail characters' books apart
	-- (TR~<name>~): Treasury.Relay passes on one per mail character in one tick, and keyed "TR" alone
	-- the last took the others' places, in the drip and in Comm's queue alike.
	-- Arena splits long records before they reach Comm. Keep their own id and index too.
	local approval = Relay.ApprovalResendGuild(body)
	if approval then return "GV resend " .. Lower(approval) end
	return body:match("^(C[^:]+:%d+):%d+:") or body:match("^(EP~[LT]%d+~[0-9a-z]+~[0-9a-z]+)~[0-9a-z]+~")
		or body:match("^(T1~%a)~") or body:match("^(TR~[^~]+)~") or body:sub(1, 2)
end

local function SetExpired(s, now)
	return now - (s.last or s.t) > Relay.SET_WAIT or now - s.t > Relay.SET_MAX_AGE
end
local function SnapshotExpired(s, now)
	if s.got == s.total then return now - s.t >= Relay.SNAPSHOT_WINDOW end
	return SetExpired(s, now)
end

local function SnapshotPart(origin, body, now)
	if not Relay.IsRelay(origin) then return false end
	local id, index, total, part = body:match("^C(%w+):(%d+):(%d+):(.*)$")
	index, total = tonumber(index), tonumber(total)
	if not id or #id > 16 or total < 1 or total > ns.Codec.MAX_CHUNKS
		or index < 1 or index > total or #part > ns.Codec.CHUNK
		or (index < total and #part ~= ns.Codec.CHUNK) then return false end
	local key = Lower(ns.FullName(origin))
	-- (1.5.8) A signed look (QA) has a slot of its own beside the origin's census snapshot: in one slot, a
	-- look said less than SNAPSHOT_WINDOW before the relay's census snapshot sent that snapshot through
	-- the trickle, where its many pieces reach a registrant whole or not at all.
	local look = snapshotTransfers[key .. "#qa"]
	if (index == 1 and part:match("^QA~1~")) or (index > 1 and look and look.id == id) then key = key .. "#qa" end
	local transfer = snapshotTransfers[key]
	if transfer and SnapshotExpired(transfer, now) then transfer = nil; snapshotTransfers[key] = nil end
	if not transfer then
		-- (1.5.8) And the author's signed look (QA, Data.lua) a relay says or another relay's copy brings:
		-- it proves itself, and in pieces through the trickle it reached a registrant whole or not at all.
		if index ~= 1 or not (part:match("^GV~1~S~%d+~")
			or part:match("^CG~[12]~S~%d+~") or part:match("^CX~[123]~S~") or part:match("^QA~1~")) then return false end
		local count = 0
		for who, entry in pairs(snapshotTransfers) do
			if SnapshotExpired(entry, now) then snapshotTransfers[who] = nil
			else count = count + 1 end
		end
		if count >= Relay.MAX_RELAYS then return false end
		transfer = { id = id, total = total, t = now, last = now, got = 0, bytes = 0, parts = {} }
		snapshotTransfers[key] = transfer
	end
	if transfer.id ~= id or transfer.total ~= total or transfer.parts[index] then return false end
	if transfer.bytes + #part > ns.Codec.CHUNK * ns.Codec.MAX_CHUNKS then return false end
	transfer.parts[index], transfer.bytes = true, transfer.bytes + #part
	transfer.got, transfer.last = transfer.got + 1, now
	return true
end
-- Whole sets, one reporter at a time (GitHub #76: the census showed only the player's own guild).
--
-- A word in pieces that skips the trickle (the relay's own global census snapshot, another relay's
-- signed snapshot) used to go out piece by piece to every reporter at once. With 46 guilds, an
-- 8-piece snapshot was 368 whispers; the send queue holds 60 (Comm's MAX_QUEUE) and dropped the
-- rest, so every reporter got one or two pieces of a message he could never put together.
--
-- Now the relay waits until it holds every piece of such a word, then hands each reporter the
-- whole set as one batch, and the next reporter's batch only once that one is done. A batch that
-- has begun is never dropped by the queue and reaches its reporter in seconds, well inside the
-- 60 seconds a receiver waits for missing pieces. Nothing new is trusted and nothing on the wire
-- changes: a reporter receives the same whispers as before, only all of them.
local sets = {}   -- origin#id -> { n = pieces expected, got = pieces held, pieces = { [i] = body }, t = first piece, last = last new piece }
local drip = {}   -- whole transfers, including the one in flight: { name, word, batches, index, started, at (1.5.9: queued) }
local dripBusy = false -- a queue callback or a retry timer owns the next turn
local dripping = false
local refillCensusAcross -- assigned by the mesh; run when an across slot is freed

local function CensusAcrossAllowed()
	return Relay.On() and Relay.IsSignedRelay(ns.me) and not (ns.QuietPresence and ns.QuietPresence())
end

-- The pieces of a word, in order, once all of them are here; false while some are missing;
-- nil when the body is not a piece of a larger word (it goes on as before).
local function CollectSet(origin, body, now)
	local id, i, n = body:match("^C(%w+):(%d+):(%d+):")
	i, n = tonumber(i), tonumber(n)
	if not id or n < 2 or n > ns.Codec.MAX_CHUNKS or i < 1 or i > n then return nil end
	for key, s in pairs(sets) do
		if SetExpired(s, now) then sets[key] = nil end -- (a set that never completed)
	end
	local key = Lower(origin) .. "#" .. id
	local s = sets[key]
	if not s or s.n ~= n then
		s = { n = n, got = 0, pieces = {}, t = now }
		sets[key] = s
	end
	if not s.pieces[i] then s.pieces[i], s.got, s.last = body, s.got + 1, now end
	if s.got < n then return false end
	sets[key] = nil
	return s.pieces
end

-- (1.5.4) A list (LS, Comm.SendList: the Church's public rows, the guild masters' nominees, the
-- shared block terms) in pieces from any origin is collected whole too and handed to each reporter
-- whole, keyed by its origin and kind, so a newer list takes a waiting one's place. Piece by piece
-- it passed the trickle whole or not at all, which with many reporters is not at all (need, in
-- ToReporters): the Church's rows reached a reporter one to four of twenty-two, and a guild
-- master's list in more than one part reached no other guild. Only the kinds of LIST_KINDS go so;
-- any other list keeps the trickle. A guild is sent a list it does not hold: an unchanged one,
-- which its sender repeats for late logins, goes to a guild that had it only `refresh` later (for
-- its late members), whoever reports for it now (a guild's reporter changes several times a day);
-- and a guild gets one list of an origin each `hold` at most, the newest when it is due (the
-- Church's rows, changed at most every desk's send, each hour: their receivers keep them
-- PUBLIC_FRESH, two hours, and the census snapshots get half the whispers back). What the relay
-- sent which guild is kept in its saved data (ns.rdb.relayLists: a sum of each origin's last list,
-- and when each guild had it, `refresh` at most), so a /reload sends nothing again. Every list
-- whisper is one the census snapshots do not get (the drip is theirs; the offline load model: a
-- list share in use costs them as much). What a list costs, its whispers to each reporter it goes
-- to, comes out of shares of so many whispers a minute for every reporter the relay holds, `cap` a
-- minute at most whatever their number (the relay sends some 200 a minute however many guilds it
-- serves), so lists never take the census's room: its kind's (`rate`) for the origins the relay can
-- trust for that kind by the very test their receivers make (`trusted`: the Church's keepers, the
-- guild's proven master, the block terms' editors), or a small one (LIST_OTHERS, LIST_OTHERS_CAP)
-- for anyone else, whose lists the receivers refuse but this relay cannot tell apart (a guild
-- master its census does not prove yet); and its origin's own (`each`), so no member, and no one
-- trusted origin, takes a whole share. (The first cut had one share for every list, taken first
-- come: a member's short list every few minutes kept the Church's longer one out.) A list goes
-- while both its shares are above nothing and may take them below it, so a long list is never
-- starved by short ones; a share saves up LIST_BURST for each reporter. From one origin, one list
-- of a kind each LIST_EVERY (a second within it only takes the place of the first's batches still
-- waiting); LIST_MAX_PIECES pieces at most (2.2 KB: the Church's 22 rows with the longest names
-- Forever gives take nine); one collecting from an origin of a kind, and LIST_OPEN in all from
-- origins not trusted. Past a bound the pieces go through the trickle as any client's word in
-- pieces. The relay's own lists skip the shares and bounds, as its own words do, never the
-- reporters who hold them already (the King's Legates every Nominees.EVERY, Nominees.SendMain).
Relay.LIST_EVERY = 120
Relay.LIST_MAX_PIECES = 10
Relay.LIST_OPEN = 16
Relay.LIST_BURST = 2      -- whispers a share saves up for each reporter
Relay.LIST_OTHERS = 0.02  -- a kind's share for the origins the relay cannot trust for it...
Relay.LIST_OTHERS_CAP = 0.5 -- ...whispers a minute at most
Relay.LIST_ORIGINS = 128  -- origins of a kind whose last list and share a relay remembers
Relay.LIST_KINDS = {
	-- The Church's public rows (Count.SendPublic): the desk alone, every 30 min; each guild its newest
	-- each hour (some 5 whispers to each of 35 reporters: 3 a minute; `cap` 8, about 90 guilds).
	NR = { rate = 0.25, each = 0.25, cap = 8, refresh = 3600, hold = 3600, trusted = function(origin)
		local C = ns.Church
		return type(C) == "table" and type(C.IsKeeper) == "function" and C.IsKeeper(origin) == true
	end },
	-- The guild masters' nominees (Nominees.Send): each master every Nominees.EVERY, his guild in each
	-- part; each guild once a change, and every 3 days for its late members.
	NM = { rate = 0.15, each = 0.05, cap = 4, refresh = 3 * 86400, trusted = function(origin, word)
		local N, guild = ns.Nominees, tostring(word or ""):match("^NM~%d+~([^~]+)~")
		return type(N) == "table" and type(N.Proven) == "function" and guild ~= nil and N.Proven(origin, guild) == true
	end },
	-- The shared block terms (Filter.SendAll): an editor every Filter.REPEAT, unless another said the same.
	BW = { rate = 0.05, each = 0.05, cap = 1, refresh = 3 * 86400, trusted = function(origin)
		local F = ns.Filter
		return type(F) == "table" and type(F.IsEditorName) == "function" and F.IsEditorName(origin) == true
	end },
}
-- (Until the saved data is there.) origin (short, lower) .. " " .. kind -> { tokens, at, admitted,
-- sum, to = { [guild] = when it had sum }, last = { [guild] = when it had one } }
local listOrigins = {}
local listShares = {}  -- kind (its trusted origins'), or kind .. "?" (the others') -> { tokens, at }
local listSets = {}    -- origin#id -> { kind, okey, trusted, own, one, key, t }: the lists being collected
-- "LS~<kind>" for a list, whole or its first piece, else nil: the queue's and the drip's key.
local function ListKind(text)
	local kind = text:match("^LS~1~(%u%w)~") or text:match("^C%w+:1:1:LS~1~(%u%w)~")
	return kind and ("LS~" .. kind) or nil
end
-- Whether a complete, replaceable transfer keyed `word` waits in the drip for `name`.
local function DripWaitingFor(name, word)
	for _, d in ipairs(drip) do
		if d.name == name and d.word == word and not d.started then return true end
	end
	return false
end
-- A share's whispers now: refilled at `rate` a minute for each of `reporters`, `cap` a minute at
-- most, LIST_BURST each saved up at most (a clock set back refills nothing).
local function Share(b, rate, reporters, now, cap)
	local most = Relay.LIST_BURST * reporters
	if b.tokens == nil then b.tokens = most end
	local perMinute = math.min(rate * reporters, cap or math.huge)
	if b.at and now > b.at then b.tokens = math.min(most, b.tokens + (now - b.at) * perMinute / 60) end
	b.at = now
	return b.tokens
end
-- The origins' records, in the saved data once it is there (a /reload keeps what each guild holds).
local function Origins()
	local r = ns.rdb
	if type(r) ~= "table" then return listOrigins end
	if type(r.relayLists) ~= "table" then r.relayLists = {} end
	return r.relayLists
end
-- An origin's record of a kind, made when new; past LIST_ORIGINS the one used longest ago goes, and
-- a guild's marks past its kind's refresh and hold with it.
local function ListOrigin(okey, now, refresh, hold)
	local all = Origins()
	local o = all[okey]
	if type(o) ~= "table" or type(o.to) ~= "table" or type(o.at) ~= "number" then
		o = nil
		local n, oldest = 0, nil
		for k, x in pairs(all) do
			n = n + 1
			if not oldest or (tonumber(x.at) or 0) < (tonumber(all[oldest].at) or 0) then oldest = k end
		end
		if n >= Relay.LIST_ORIGINS and oldest then all[oldest] = nil end
		o = { to = {}, at = now }
		all[okey] = o
	end
	for g, at in pairs(o.to) do
		if type(at) ~= "number" or now < at or now - at >= (refresh or 0) then o.to[g] = nil end
	end
	if type(o.last) ~= "table" then o.last = {} end
	for g, at in pairs(o.last) do
		if type(at) ~= "number" or now < at or now - at >= (hold or 0) then o.last[g] = nil end
	end
	return o
end
-- The list this piece belongs to ({ kind, okey, trusted, one }), opened at its first piece; nil when
-- it is not a list of a kind carried whole, or is past a bound (then the trickle, as before).
local function ListSet(origin, body, now, own)
	local id, i, n, head = body:match("^C(%w+):(%d+):(%d+):(.*)$")
	i, n = tonumber(i), tonumber(n)
	if not id or n < 1 or n > ns.Codec.MAX_CHUNKS then return nil end
	local open = 0
	for key, s in pairs(listSets) do
		if now - s.t > Relay.SET_WAIT then listSets[key] = nil elseif not s.trusted then open = open + 1 end
	end
	local key = Lower(origin) .. "#" .. id
	local s = listSets[key]
	if s then return s end
	if i ~= 1 then return nil end
	local kind, word = head:match("^LS~1~(%u%w)~%d+~([^\255]*)")
	local spec = kind and Relay.LIST_KINDS[kind]
	if not spec then return nil end
	local okey = Lower(ns.ShortName(origin)) .. " " .. kind
	local trusted = own == true
	if not own then
		local ok, yes = pcall(spec.trusted, origin, word)
		trusted = ok and yes == true
		-- (One collecting from an origin of a kind: a newer one takes its place.)
		for k, o in pairs(listSets) do
			if o.okey == okey then
				listSets[k] = nil
				if not o.trusted then open = open - 1 end
			end
		end
		if n > Relay.LIST_MAX_PIECES or (not trusted and open >= Relay.LIST_OPEN) then
			stats.listsRefused = (stats.listsRefused or 0) + 1
			return nil
		end
	end
	s = { kind = kind, okey = okey, trusted = trusted, own = own == true, one = n == 1, key = key, t = now }
	if n > 1 then listSets[key] = s end
	return s
end

-- (The review of the 1.5.4 candidate.) Whether `name` is some guild's reporter here now (Drip).
local function StillReporter(name)
	for _, r in pairs(reporters) do
		if r.name == name then return true end
	end
	return false
end

-- (1.5.9, an /oly bug of 2026-11-12: no census whisper reached a guild in a whole session.) A census
-- transfer waited for free room in the send queue for its whole batch, though Comm makes room by
-- dropping the ordinary whispers still waiting (the trickle, the relay's own single words to every
-- reporter), and its batch then waited there as an ordinary job, the first one a newer whisper pushed
-- out. Under a steady load of ordinary words none ever started (the offline harness: no census whisper
-- in 300 s, no tree registrant complete in 25 minutes), and any other transfer waiting at the front of
-- the drip held every census transfer behind it the same way. A census transfer (`census`: a
-- registrant's snapshot, the tree's word to a seed or a registrant and its repairs, the relay's own
-- snapshot to a mesh peer) starts once Comm can take its batch that way (Comm.QueueRoom(true)), waits
-- there as an urgent job, which nothing pushes out, and goes ahead of the other transfers.
--
-- (The review of 1.5.9.) Sent urgent back to back, the census took about half the relay's 200 whispers
-- a minute, and five of every eight sends while one of its batches went (Comm's BATCH_SLOTS): the chat
-- lane, the relay's own single words to every reporter, the trickle and the King's presence lost what
-- 1.5.8 delivered (the offline harness, 90 registrants and a chat line every 45 s: 727 of 3,060 chat
-- whispers lost, 1.5.8 none). An other transfer handed to Comm went as an ordinary batch, waited behind
-- the urgent ones, was pushed out and handed over again for up to a minute, the census held behind it
-- (75 of 90 registrants without a census in 20 minutes); its later batch waited for free room for good,
-- every census transfer behind it (a word one whisper past MAX_CHUNKS, begun in a lull: no census
-- whisper in five minutes); and the census went ahead of an other one for as long as any census waited
-- (the relay's own word in pieces: 0 of 90 registrants in an hour). So now the drip has a pace:
--   * at most DRIP_PER_MIN whispers a minute (one batch at once, MAX_CHUNKS), urgent, so nothing pushes
--     a batch out of the queue once it is there; the rest of the relay's sends, some 140 a minute, are
--     for the chat lane (Relay.CHAT_PER_MIN), the King's words, the tree's digests, the trickle and the
--     relay's own single words;
--   * past that pace, without paying, while nothing else waits (no chat whisper in the lane, no ordinary
--     whisper in the queue, room for the batch): a relay with nothing else to send sends the census as
--     fast as before. Such a first batch goes as an ordinary job, so a burst of ordinary whispers still
--     pushes it out before it begins, as before the pace;
--   * a census transfer, and a begun one, makes room as Comm does, by dropping the ordinary whispers still
--     waiting (Comm.QueueRoom(true)), and so does another server's census (a look: QA, CX), in the other
--     transfers' turn; any other one waits for free room, DRIP_ROOM_AFTER at most;
--   * a transfer begun takes its next batch at once, ahead of the pace (paid back before the next transfer
--     starts), so its receiver never waits past its 60 seconds for the rest;
--   * a census transfer goes ahead of the other ones, and they keep a share of the drip's whispers while
--     census transfers wait (DRIP_OTHER_SHARE, a quarter), so the lists and the relay's own words in
--     pieces still go; the next transfer chosen waits at the front for its turn, the pace saved up for it
--     (a small one never takes a big one's turn whisper by whisper).
-- The pace is a trade between the census and the chat (the offline harness, 90 registrants, 9 on 1.5.4,
-- the relay's own rounds, a chat line every 45 s for 30 minutes, the King's presence, the relay's own
-- words): at 40 no chat whisper lost and the slowest line 82 s, but the 1.5.4 registrants got no census
-- (the tree's rounds took the pace); at 60 none lost, the slowest line 197 s, every registrant served
-- within 15 minutes; at 80, 38 chat whispers lost. (1.5.8: none lost, 58 s, 69 registrants without a
-- census; 1.5.9 before this: 728 lost, 317 s.) With a chat line a minute or less, 60 delivered every
-- line within 82 s.
Relay.DRIP_PER_MIN = 60
Relay.DRIP_OTHER_SHARE = 0.25
Relay.DRIP_ROOM_AFTER = 120
local dripBucket = { at = -math.huge } -- tokens: whispers the drip may hand Comm now (DripTokens)
local dripOwed = 0 -- whispers the other transfers are owed of their share (DRIP_OTHER_SHARE), one batch at most
local function DripTokens(now)
	local b, most = dripBucket, ns.Codec.MAX_CHUNKS
	if b.tokens == nil then b.tokens = most end
	if now > b.at then b.tokens = math.min(most, b.tokens + (now - b.at) * Relay.DRIP_PER_MIN / 60) end
	b.at = math.max(b.at, now)
	return b.tokens
end
-- Whether the chat lane has no whisper waiting (those in flight are in Comm's queue already, ahead).
local function ChatIdle() return not (type(Relay.ChatWaiting) == "function" and Relay.ChatWaiting() > 0) end
local function CensusTransfer(d) return d.census == true end
-- Whether transfer d still goes: begun, or its receiver still one (a registrant here, a relay answering,
-- a mesh peer for the relay's own census). Eligibility is pinned at the first queue handoff.
local function Current(d)
	if d.started then return true end
	if d.censusAt then
		return Now() - d.censusAt <= Relay.SET_MAX_AGE and CensusAcrossAllowed() and Relay.MeshPeer(d.name) and true or false
	elseif d.across then
		return Relay.IsRelay(d.name) and Now() - (verified[Lower(d.name)] or -math.huge) < Relay.VERIFIED_FOR and true or false
	end
	return StillReporter(d.name)
end
-- How transfer d's next batch may go now (the pace, above): "free", "paid" or nil (not yet).
local function Turn(d, now, tokens)
	local n = #d.batches[d.index]
	local room = ns.Comm.QueueRoom()
	if ChatIdle() and room >= n and ns.Comm.QueueRoom(true) == room then return "free" end
	local evicts = d.started or CensusTransfer(d) or d.look or now - (d.at or now) >= Relay.DRIP_ROOM_AFTER
	if ns.Comm.QueueRoom(evicts == true) >= n and (d.started or tokens >= n) then return "paid" end
	return nil
end
-- The transfer to start next (none begun): the first census one, unless the first other one is owed its
-- share's batch, or no census one waits. On the way, the transfers that no longer go are dropped (and true
-- returned when one of them was to a relay: an across slot freed).
local function Next(now)
	local c, o, freed, i = nil, nil, false, 1
	while drip[i] and not (c and o) do
		local w = drip[i]
		if Current(w) then
			if CensusTransfer(w) then c = c or i else o = o or i end
			i = i + 1
		else
			table.remove(drip, i) -- a complete transfer, before its first batch
			if w.across then freed = true end
		end
	end
	if not (c and o) then return c or o, freed end
	local w = drip[o]
	local n = #w.batches[w.index]
	-- (An other one that waits for free room, DRIP_ROOM_AFTER at most, is no turn to save the pace for.)
	local waits = not w.look and ns.Comm.QueueRoom() < n and now - (w.at or now) < Relay.DRIP_ROOM_AFTER
	if not waits and dripOwed >= n then return o, freed end
	return c, freed
end

-- One transfer owns all its batches. Eligibility is pinned at the first queue handoff;
-- capacity eviction can return that first batch only before it sends anything. Later batches
-- keep their place and eligibility, even when the peer's verification expires between them.
local function Drip()
	if dripping or dripBusy then return end
	dripping = true
	while not dripBusy and drip[1] do
		local now = Now()
		if not drip[1].started then
			local k, freed = Next(now)
			if k and k > 1 then table.insert(drip, 1, table.remove(drip, k)) end
			if freed and refillCensusAcross then refillCensusAcross() end
		end
		local d = drip[1]
		if d and not d.started and not Current(d) then
			table.remove(drip, 1) -- (put at the front by the mesh's refill, and gone meanwhile)
			if d.across and refillCensusAcross then refillCensusAcross() end
		elseif d then
			local batch = d.batches[d.index]
			local tokens = DripTokens(now)
			local how = Turn(d, now, tokens)
			if not how then
				dripBusy = true
				ns.After(1, "relay drip", function() dripBusy = false; Drip() end)
			else
				if how == "paid" then dripBucket.tokens = tokens - #batch end
				-- (The other transfers' share: a census batch earns them a part of its whispers, theirs spend it.)
				local share = Relay.DRIP_OTHER_SHARE
				if CensusTransfer(d) then dripOwed = math.min(ns.Codec.MAX_CHUNKS, dripOwed + #batch * share / (1 - share))
				else dripOwed = math.max(0, dripOwed - #batch) end
				local kind = CensusTransfer(d) and "dripCensus" or "dripOther"
				stats[kind] = (stats[kind] or 0) + #batch
				if how == "free" then stats.dripFree = (stats.dripFree or 0) + #batch end
				-- (A first batch past the pace goes as an ordinary job: one that has not begun gives way to a
				-- burst of ordinary whispers, as before the pace. Any other batch urgent: nothing pushes it out.)
				local urgent = how ~= "free" or d.started == true
				Quiet(d.name)
				if not d.tried then stats.forwarded, d.tried, d.t = stats.forwarded + 1, true, now end
				d.started, dripBusy = true, true
				ns.Comm.SendBatch("WHISPER", batch, nil, d.name, urgent, function(sent, why)
					if not sent and (why == "full" or why == "dropped") then
						-- Comm never capacity-evicts a batch once it starts. Only an unsent
						-- first batch may yield to a newer complete copy or expire on retry.
						if d.index == 1 then
							d.started = nil
							for i = 2, #drip do
								local w = drip[i]
								if w.name == d.name and w.word == d.word then
									d.batches = w.batches; table.remove(drip, i); break
								end
							end
						end
						if d.index > 1 or Now() - d.t < Relay.SET_WAIT then
							ns.After(1, "relay drip", function() dripBusy = false; Drip() end)
							return
						end
					end
					if sent and d.index < #d.batches then
						d.index, d.tried = d.index + 1, nil
					else
						-- Terminal transport refusals (privacy, net-off, leaving, etc.) still stop it.
						table.remove(drip, 1)
						if sent and d.censusSent then d.censusSent() end
						if d.across and refillCensusAcross then refillCensusAcross() end
					end
					dripBusy = false
					Drip()
				end)
			end
		end
	end
	dripping = false
end

-- The whispers that carry a whole set to a reporter, cut into batches the queue accepts.
-- The set goes as the one word it carries, wrapped once and cut once, so every whisper is full.
-- Wrapped piece by piece, a full piece and its RM label overflowed one whisper and each piece went
-- as two (an 8-piece census snapshot as 16 whispers to every reporter). A reporter takes either
-- form the same way: it puts the RM together, then the word inside it.
local function SetWhispers(flag, origin, set, kind)
	kind = kind or "RM"
	local parts = {}
	for i, body in ipairs(set) do parts[i] = body:match("^C%w+:%d+:%d+:(.*)$") end
	local word = table.concat(parts)
	-- (review prototype) Only a word with a type a handler takes whole: a census report (R1, R2)
	-- is decoded from its pieces alone (Comm's CHANNEL path), so it keeps its pieces.
	-- RX keeps the original pieces too: the next relay reserves and collects signed snapshots
	-- from those pieces (SnapshotPart), before handing a whole set to its reporters.
	if kind ~= "RX" and #parts == #set and word:match("^%u%w~") and not word:match("^R[12]~") then
		local whispers = Envelope(kind, kind .. "~" .. flag .. "~" .. origin .. "~" .. word)
		if #whispers <= ns.Codec.MAX_CHUNKS then return whispers end
	end
	local whispers
	-- (Too long to travel as one word: the pieces as they came, each wrapped on its own.)
	whispers = {}
	for _, body in ipairs(set) do
		for _, e in ipairs(Envelope(kind, kind .. "~" .. flag .. "~" .. origin .. "~" .. body)) do
			whispers[#whispers + 1] = e
		end
	end
	return whispers
end

local function SetBatches(flag, origin, set, kind)
	local whispers = SetWhispers(flag, origin, set, kind)
	local batches, size = {}, ns.Codec.MAX_CHUNKS
	for first = 1, #whispers, size do
		local batch = {}
		for k = first, math.min(first + size - 1, #whispers) do batch[#batch + 1] = whispers[k] end
		batches[#batches + 1] = batch
	end
	return batches
end

-- Replace only a complete waiting transfer, even when the new copy has fewer batches.
-- The table is its identity: an in-flight copy and at most one waiting successor stay distinct.
-- census (1.5.9): a census transfer (CensusTransfer, above); look (1.5.9's review): another server's census
-- (CensusLook, below), which makes room at once as a census transfer does, in the other transfers' turn.
local function DripBatches(name, word, batches, waitingOnly, across, census, look)
	for _, d in ipairs(drip) do
		if d.name == name and d.word == word and not d.started then
			d.batches = batches
			return Drip()
		end
	end
	if waitingOnly then return end
	if across then
		local total, peer, oldest, peerOldest = 0, 0, nil, nil
		for i, d in ipairs(drip) do
			if d.across then
				total = total + 1
				local evictable = not d.started and not d.kingCensus
				if evictable then oldest = oldest or i end
				if d.name == name then
					peer = peer + 1
					if evictable then peerOldest = peerOldest or i end
				end
			end
		end
		local evict = peer >= Relay.ACROSS_PER_PEER and peerOldest or oldest
		if peer >= Relay.ACROSS_PER_PEER or total >= Relay.ACROSS_MAX then
			-- No room when only an in-flight tail or the King's census could be removed.
			if peer >= Relay.ACROSS_PER_PEER and not peerOldest then return end
			if not evict then return end
			table.remove(drip, evict)
		end
	end
	drip[#drip + 1] = { name = name, word = word, batches = batches, index = 1, across = across, census = census == true or nil,
		look = look == true or nil, at = Now() }
	Drip()
end

-- (1.5.4) A whole list (ListSet above): the guilds whose reporters it goes to now, and whether only
-- in place of a batch still waiting. Those that do not hold it yet, or had it `refresh` ago, within
-- its shares (the relay's own lists skip them); within LIST_EVERY of its origin's last, at no cost,
-- only those whose batch of that one still waits. None when it is refused.
-- (The review of the merged candidate.) `reachable(r)`: whether the relay hands that reporter words at
-- all now (no modified build, admitted): a guild whose reporter it serves nothing is not counted as
-- holding the list, or the served reporter who takes its place would wait `refresh` for it.
local function ListSend(s, origin, set, now, reachable)
	listSets[s.key] = nil
	local spec = Relay.LIST_KINDS[s.kind]
	local o = ListOrigin(s.okey, now, spec.refresh, spec.hold)
	local parts = {}
	for k, body in ipairs(set) do parts[k] = body:match("^C%w+:%d+:%d+:(.*)$") or "" end
	local sum, to, fresh = Hash(table.concat(parts)), {}, 0
	for _, r in pairs(reporters) do
		if now - r.t <= Relay.REPORTER_FOR and r.name ~= ns.me then fresh = fresh + 1 end
	end
	local word = Lower(origin) .. " LS~" .. s.kind
	if not s.own and o.admitted and now >= o.admitted and now - o.admitted < Relay.LIST_EVERY then
		if sum == o.sum then return to end -- (its repeat: what waits carries it already)
		o.sum, o.to = sum, {}
		for g, r in pairs(reporters) do
			if r.name ~= ns.me and (not reachable or reachable(r)) and DripWaitingFor(r.name, word) then to[g], o.to[g] = true, now end
		end
		if next(to) then stats.listsReplaced = (stats.listsReplaced or 0) + 1
		else stats.listsRefused = (stats.listsRefused or 0) + 1 end
		return to, true
	end
	if sum ~= o.sum then o.sum, o.to = sum, {} end
	local each, cost = #SetWhispers("P", origin, set), 0
	for g, r in pairs(reporters) do
		if now - r.t <= Relay.REPORTER_FOR and r.name ~= ns.me and not o.to[g] and not o.last[g] and (not reachable or reachable(r)) then
			to[g] = true
			cost = cost + each
		end
	end
	if cost == 0 then
		stats.listsSame = (stats.listsSame or 0) + 1
		return to
	end
	if not s.own then
		local which = s.kind .. (s.trusted and "" or "?")
		local share = listShares[which] or {}
		listShares[which] = share
		local rate, cap = spec.rate, spec.cap
		if not s.trusted then rate, cap = Relay.LIST_OTHERS, Relay.LIST_OTHERS_CAP end
		if Share(share, rate, fresh, now, cap) <= 0 or Share(o, spec.each, fresh, now, spec.cap) <= 0 then
			stats.listsRefused = (stats.listsRefused or 0) + 1
			return {}
		end
		share.tokens, o.tokens = share.tokens - cost, o.tokens - cost
		o.admitted = now
		stats.lists = (stats.lists or 0) + 1
	end
	for g in pairs(to) do o.to[g], o.last[g] = now, spec.hold and now or nil end
	return to
end

-- (1.5.4) An integration's profile presentation (ProfileEffects, FX) names its guild. A presenter's
-- own words (S, and its stop X) go to that guild's reporter alone. Their heartbeat (every 10 s, a
-- 32 s lease) to every reporter was most of what a relay sent: 44 of 353 words on the dev's relay
-- in 142 s, each to 32-36 reporters outside the trickle, about three times the relay's 200 whispers
-- a minute by itself, and the census snapshots waited behind it (the offline harness: complete
-- snapshots per reporter more than doubled without it).
-- The issuer's grant (G) and close (C) name the issuer's own guild, yet a member of any guild
-- presents only under a grant he holds: scoped like the rest, no other guild ever got one (the
-- review of the 1.5.4 candidate). A close goes to every reporter at once. A grant (its issuer beats
-- every 10 s) goes to every reporter at most once each GRANT_EVERY per origin, and to the named
-- guild's reporter alone in between; where names split a heard grant lives
-- ProfileEffects.SESSION_TTL_RELAYED, past two such beats.
Relay.GRANT_EVERY = 60
Relay.GRANT_ORIGINS = 64 -- origins whose last grant to every reporter a relay remembers
local grantSent = {} -- origin (short name, lower) -> when its grant last went to every reporter
-- Whether this origin's grant goes to every reporter now (and noted so). Keyed by the short name:
-- a name is one across a Forever family, whichever sub-realm stamped it. Bounded: the stale ones
-- leave, then the oldest, before a new origin is kept.
local function GrantToAll(origin, now)
	local key = Lower(ns.ShortName(origin))
	if now - (grantSent[key] or -math.huge) < Relay.GRANT_EVERY then return false end
	if not grantSent[key] then
		local n, oldest = 0, nil
		for k, at in pairs(grantSent) do
			if now - at >= Relay.GRANT_EVERY then grantSent[k] = nil
			else
				n = n + 1
				if not oldest or at < grantSent[oldest] then oldest = k end
			end
		end
		if n >= Relay.GRANT_ORIGINS and oldest then grantSent[oldest] = nil end
	end
	grantSent[key] = now
	return true
end
-- (The review of the 1.5.4 candidate, mixed versions.) A 1.5.3 client keeps a heard grant
-- ProfileEffects.SESSION_TTL (32 s) wherever it is, so a grant once each GRANT_EVERY left it none for
-- 28 s of every minute: a 1.5.3 presenter outside the issuer's guild lost his presentation at his
-- next heartbeat, and a 1.5.3 viewer there saw it come and go. A guild whose member presents (his S
-- names his guild) hears the grants each beat for PRESENTING_FOR after his last heartbeat, six
-- whispers a minute per such guild while it lasts; the rest once each GRANT_EVERY as above. A guild
-- with no reporter here is not noted, so the table holds at most MAX_REPORTERS guilds.
Relay.PRESENTING_FOR = 64 -- (twice ProfileEffects.LEASE_TTL: a presenter beats every 10 s)
local presented = {} -- guild (lower) -> when a member's presentation (S) last passed here
local function Presenting(guild, now) return now - (presented[guild] or -math.huge) < Relay.PRESENTING_FOR end
-- The guild (lower) a presentation goes to alone, or nil when it goes to every reporter; its kind second.
local function PresentationScope(origin, body, now)
	if type(body) ~= "string" then return nil end
	local kind, guild = body:match("^FX~%d+~(%a)~[^~]*~%d+~%d+~%d+~([^~]+)")
	if not kind then return nil end
	if kind == "C" or (kind == "G" and GrantToAll(origin, now)) then return nil end
	guild = Lower(guild)
	if kind == "S" and reporters[guild] then
		for g, at in pairs(presented) do if now - at >= Relay.PRESENTING_FOR then presented[g] = nil end end
		presented[guild] = now
	end
	return guild, kind
end
-- (1.5.4) The presentation and the relay's admission (the relay's side; the top of the file says why).
-- A release's version string: 1.5.4, 1.5.4.1, or an arena test build's 1.5.4-test.3; nil for anything else.
function Relay.VersionOf(s)
	if type(s) ~= "string" or #s > 24 then return nil end
	if s:match("^%d+%.%d+%.%d+$") or s:match("^%d+%.%d+%.%d+%.%d+$") or s:match("^%d+%.%d+%.%d+%-test%.%d+$") then return s end
	return nil
end
-- The relay rules in force: the newest word of rules this realm group's store holds (RU, below),
-- else the code's own (revision 0): the requirement on from PRESENT_REQUIRED_AT, PUBLISHED admitted.
local function DefaultRules()
	return { rev = 0, on = true, at = Relay.PRESENT_REQUIRED_AT, versions = Relay.PUBLISHED }
end
function Relay.Rules()
	local r = ns.rdb and ns.rdb.relayRules
	if type(r) == "table" and type(r.rev) == "number" and r.rev > 0 and type(r.at) == "number" and type(r.versions) == "table" then return r end
	return DefaultRules()
end
-- Whether a relay serves only the clients that presented themselves now.
function Relay.Required(now)
	local r = Relay.Rules()
	return r.on ~= false and (now or Now()) >= r.at
end
-- Whether a version presented is one the rules admit: on their list, or an arena test build of one
-- on it; a list left empty admits every release's form. (The list as a set, made again when the
-- rules in force change: a relay asks this for every reporter of every word it hands on.)
local listed, listedFrom
function Relay.Published(version)
	local v = Relay.VersionOf(version)
	if not v then return false end
	local list = Relay.Rules().versions
	if #list == 0 then return true end
	if listedFrom ~= list then
		listed, listedFrom = {}, list
		for _, p in ipairs(list) do listed[p] = true end
	end
	return listed[v] == true or listed[v:match("^(%d+%.%d+%.%d+)%-test%.%d+$") or v] == true
end
-- An entry of one of the relay's tables of characters (presented, refused), as it may come back from
-- the saved variables.
local function Fresh(e, now)
	return type(e) == "table" and type(e.t) == "number" and type(e.name) == "string" and now - e.t < Relay.PRESENT_FOR
end
-- One of those tables, bounded: the stale and malformed leave first, then the oldest, before a new
-- character is kept.
local function Keep(t, key, entry, cap, now)
	if not t[key] then
		local n, oldest = 0, nil
		for k, e in pairs(t) do
			if not Fresh(e, now) then t[k] = nil
			else
				n = n + 1
				if not oldest or e.t < t[oldest].t then oldest = k end
			end
		end
		if n >= cap and oldest then t[oldest] = nil end
	end
	t[key] = entry
end
-- The presentations a relay holds: in its realm group's store (ns.rdb.relayPresented), so a /reload
-- or its next login keeps them (a client pings its relay again only every DEAD_FOR, and its words
-- meanwhile would find none); in memory while no store is open. Made in the store by the first
-- presentation kept (write) alone: a client no one presents to saves nothing.
local function Book(write)
	local d = ns.rdb
	if type(d) ~= "table" then return presentedMem end
	if type(d.relayPresented) ~= "table" then
		if not write then return presentedMem end
		d.relayPresented = {}
	end
	return d.relayPresented
end
-- A character presented itself (its RI's or its registration's version, well formed): kept
-- PRESENT_FOR past its last word.
local function Present(sender, version, now)
	local short = ns.ShortName(sender or "") or ""
	if short == "" or not version then return false end
	Keep(Book(true), short:lower(), { name = short, v = version, t = now }, Relay.MAX_PRESENTED, now)
	return true
end
-- The version a character presented, and when; nil when it did not, or too long ago.
function Relay.Presented(name, now)
	local p = Book()[Lower(ns.ShortName(name or ""))]
	if not Fresh(p, now or Now()) or type(p.v) ~= "string" then return nil end
	return p.v, p.t
end
local function Listed(t, now)
	local out = {}
	for _, e in pairs(t) do
		if Fresh(e, now) then out[#out + 1] = e end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end
-- The presentations held, by name: { name, v, t }; and the refusals noted: { name, kind, why, t }.
function Relay.Presentations(now) return Listed(Book(), now or Now()) end
function Relay.Refusals(now) return Listed(refused, now or Now()) end
function Relay.PresentedCount(now)
	now = now or Now()
	local n = 0
	for _, e in pairs(Book()) do if Fresh(e, now) then n = n + 1 end end
	return n
end
-- A set of characters another check hands over (short names, lower; the modified-build check's):
-- each refused at once, deadline or not, as an unpresented one is. nil clears it.
function Relay.SetDenied(set) denied = type(set) == "table" and set or nil end
function Relay.IsDenied(name)
	if denied == nil or type(name) ~= "string" then return false end
	return denied[Lower(ns.ShortName(name))] == true or denied[name:lower()] == true
end
-- Never refused: the relay's own client, the King's character and the signed relays (the words
-- that hold the network together).
local function Exempt(sender)
	local full = ns.FullName(sender)
	if full == ns.me then return true end
	if type(ns.IsKingCharacter) == "function" and ns.IsKingCharacter(full) == true then return true end
	return Relay.IsRelay(sender)
end
Relay.Exempt = Exempt
-- The relay's admission of one character's word: true, or false and why. kind: "RR" its registration
-- as a reporter, "RL" a word of its to pass on or answer, "RM" a word to hand to it as a reporter.
-- The rule: a denied character never; before the deadline everyone; from then on one that presented
-- a published version. (A stub takes its place in the tests.)
function Relay.Admit(kind, sender, body, now)
	if Relay.IsDenied(sender) then return false, "denied" end
	if not Relay.Required(now) then return true end
	local v = Relay.Presented(sender, now)
	if not v then return false, "unpresented" end
	if not Relay.Published(v) then return false, "version " .. v end
	return true
end
-- Every word a relay hears, for whoever wants to watch it (nothing by default; the tests).
function Relay.Observe(kind, sender, body, now) end
local DefaultAdmit = Relay.Admit
-- Admit asked; the exempt never refused (asked after a refusal alone: a relay asks this for every
-- reporter of every word); a rule that fails falls back to the public one, so a relay never serves
-- everyone or nobody by mistake.
local function Ask(kind, sender, body, now)
	local ok, admit, why = pcall(Relay.Admit, kind, sender, body, now)
	if not ok then
		if ns.CaptureError then ns.CaptureError("relay admit", admit) end
		admit, why = DefaultAdmit(kind, sender, body, now)
	end
	if admit == true or Exempt(sender) then return true end
	return false, why or "refused"
end
-- A word refused is counted and noted (the report).
local function Admitted(kind, sender, body, now)
	local ok, why = Ask(kind, sender, body, now)
	if ok then return true end
	stats.refused = stats.refused + 1
	if why == "unpresented" then stats.unpresented = stats.unpresented + 1
	elseif why == "denied" then stats.denied = stats.denied + 1 end
	local short = ns.ShortName(sender or "") or ""
	if short ~= "" then Keep(refused, short:lower(), { name = short, kind = kind, why = why, t = now }, Relay.MAX_REFUSED, now) end
	return false, why
end
-- Whether a reporter is handed words now (never one that did not present, from the deadline on).
local function Served(r, body, now)
	local ok = Ask("RM", r.name, body, now)
	if not ok then stats.unserved = stats.unserved + 1 end
	return ok
end
-- A character's held registration goes (its RR renewed without a presentation, or refused).
local function Unregister(who)
	for g, r in pairs(reporters) do if r.name == who then reporters[g] = nil end end
end
-- What a registration says: RR~<guild> (every version), RR~<guild>~<version> (1.5.4, to a relay that
-- named its version). A well-formed version is the reporter's presentation.
local function Registration(sender, rest, now)
	local guild, named = rest:match("^(.-)~([^~]*)$")
	if not guild then return rest, nil end
	local version = Relay.VersionOf(named)
	if version then Present(sender, version, now) end
	return guild, version
end
-- The ping's answer, one whisper as before: RY~<version> to a client we hold a presentation of (a
-- 1.5.4 client: it takes it as the answer and learns our version), else "RY~", which every version
-- takes (1.5.3 and older, that text and nothing else). Keyed per client: one waiting at most.
local function Acknowledge(sender, now)
	local answer = Relay.Presented(sender, now) and ("RY~" .. tostring(ns.VERSION)) or "RY~"
	ns.Comm.Whisper(sender, answer, "relay ack:" .. sender, true)
end
-- Every word heard is shown to Observe (a failure there never stops the word).
local function Heard(kind, sender, body, now)
	ns.SafeCall("relay observe", Relay.Observe, kind, sender, body, now)
end
-- A client's presentation (RI~<version>, a word of its own) heard (we are a relay): kept. Answered
-- with our version when we held none of it (its first, or past PRESENT_FOR), so the client learns
-- it (its registration's form, Identify); keyed as the ping's answer, which it replaces when that
-- one still waits. Fanned out to nobody.
function Relay.HandlePresent(dist, sender, text)
	if dist ~= "WHISPER" or not Relay.On() or not Relay.IsRelay(ns.me) then return false end
	local named = tostring(text):match("^RI~(.*)$")
	if not named then return false end
	local now = Now()
	Heard("RI", sender, text, now)
	local had = Relay.Presented(sender, now)
	if not Present(sender, Relay.VersionOf(named), now) then
		stats.dropped = stats.dropped + 1
		return true
	end
	if not had and ns.FullName(sender) ~= ns.me then
		ns.Comm.Whisper(sender, "RY~" .. tostring(ns.VERSION), "relay ack:" .. sender, true)
	end
	return true
end

-- (1.5.4) The King's crown to this relay's reporters (KING_GAP above): each at most once a KING_GAP,
-- the longest waiting first, within the relay's KING_PER_MIN (KING_BURST at once), ahead in the
-- queue; "hidden" to all at once. Heard here too.
local function CrownToReporters(flag, origin, body, now)
	local hide, due = Hide(body), {}
	for g, r in pairs(reporters) do
		if now - r.t > Relay.REPORTER_FOR or Quarantined(r.name) then reporters[g] = nil
		elseif Served(r, body, now) and CrownDue("r:" .. Lower(r.name), body, now) then due[#due + 1] = r end
	end
	local function Last(r) return crownSent["r:" .. Lower(r.name)] or -math.huge end
	table.sort(due, function(a, b) return Last(a) < Last(b) end)
	local b = crownBucket
	b.tokens = math.min(Relay.KING_BURST, b.tokens + math.max(0, now - b.at) * Relay.KING_PER_MIN / 60)
	b.at = now
	local pieces, heard, ahead = nil, nil, 0
	for _, r in ipairs(due) do
		if r.name == ns.me then
			crownSent["r:" .. Lower(r.name)] = now
			heard = Deliver(origin, body, false)
			ToGuild(flag, origin, body)
		elseif hide or b.tokens >= 1 then
			if not hide then b.tokens = b.tokens - 1 end
			crownSent["r:" .. Lower(r.name)] = now
			pieces = pieces or Envelope("RM", "RM~" .. flag .. "~" .. origin .. "~" .. body)
			stats.forwarded = stats.forwarded + 1
			Quiet(r.name)
			-- (A "hidden" to more than KING_BURST reporters: the rest in line, never past the queue's room.)
			local urgent = ahead < Relay.KING_BURST
			ahead = ahead + 1
			local key = "relay " .. r.name .. " " .. Lower(origin) .. " " .. QueueWord(body)
			if #pieces == 1 then ns.Comm.Whisper(r.name, pieces[1], key, urgent, false)
			else ns.Comm.SendBatch("WHISPER", pieces, key, r.name, urgent) end
		else
			stats.trickled = (stats.trickled or 0) + 1
		end
	end
	if not heard then Deliver(origin, body, false) end
end
-- (1.5.5, the dev: "only half the chat messages arrive") The chat lane. A chat line is one whisper to
-- every reporter (and every other relay), unkeyed and ordinary in Comm's queue of MAX_QUEUE: with 46
-- reporters two lines a few seconds apart overflowed it, and the queue pushed out the oldest waiting
-- whispers, the first line's, for good (the offline harness: 114 of 184 deliveries of four lines lost).
-- The author's relay had 92 reporters on 2026-11-10: one line alone is more than the queue holds.
-- Now a relay's chat whispers wait here, in order, and go to Comm's queue CHAT_INFLIGHT at a time as
-- urgent ones, which nothing pushes out: a burst arrives later instead of not at all. At most
-- CHAT_PER_MIN a minute, so the census, the lists and the King's words keep the rest of the relay's
-- 200 whispers a minute. CHAT_BURST at once, no more: at 60 the lane took every whisper for the first
-- minute and a half of a burst, the census none (the check of the lane, tests/chat-delivery.lua).
-- What that carries at 92 reporters: one line in one piece is 92 whispers, about 35 s of the lane, so
-- some 1.7 lines a minute. Lines typed at once: the 5th reaches its last reporter about 3 minutes
-- later, and the 9th is the first that waits past CHAT_LANE_TTL. Past CHAT_LANE_MAX waiting the
-- oldest goes, and one that waited CHAT_LANE_TTL is no longer news (both counted: Stats().chatLost,
-- "lost" in /oly status). The real cure is several lines in one whisper: a new form, for 1.5.6.
Relay.CHAT_INFLIGHT = 8
Relay.CHAT_PER_MIN = 160
Relay.CHAT_BURST = 8
Relay.CHAT_LANE_MAX = 1500
Relay.CHAT_LANE_TTL = 300
local chatQ, chatFirst, chatLast, chatInflight, chatFeeding = {}, 1, 0, 0, false
local chatWaitUntil, chatTimer = -math.huge, false
local chatBucket = { tokens = Relay.CHAT_BURST, at = -math.huge }
local function ChatWaiting() return chatLast - chatFirst + 1 end
local FeedChat
-- Fed again after `seconds` (one timer at a time); meanwhile a word that arrives feeds it once it is due.
local function ChatLater(seconds)
	chatWaitUntil = math.max(chatWaitUntil, Now() + seconds)
	if chatTimer then return end
	chatTimer = true
	ns.After(seconds, "relay chat", function()
		chatTimer = false
		if Now() < chatWaitUntil then return ChatLater(chatWaitUntil - Now()) end
		FeedChat()
	end)
end
local function ChatSend(e)
	Quiet(e.name)
	chatInflight = chatInflight + 1
	local settled = false
	local function done(sent, why)
		if settled then return end
		settled = true
		chatInflight = math.max(0, chatInflight - 1)
		if not sent and why == "full" and Now() - e.t < Relay.CHAT_LANE_TTL then
			-- (No room even for an urgent whisper: back at the front, tried again in a second.)
			chatFirst = chatFirst - 1
			chatQ[chatFirst] = e
			ChatLater(1)
			return
		end
		if not sent then stats.chatLost = (stats.chatLost or 0) + 1 end
		FeedChat()
	end
	-- (The check of the lane: a send that throws is that whisper lost, its place in flight given back.)
	local ok = ns.SafeCall("relay chat send", function()
		if #e.pieces == 1 then ns.Comm.Whisper(e.name, e.pieces[1], nil, true, false, done)
		else ns.Comm.SendBatch("WHISPER", e.pieces, nil, e.name, true, done) end
	end)
	if not ok then done(false, "error") end
end
-- (The check of the lane: a whisper waits up to CHAT_LANE_TTL, so whom it goes to is asked again when
-- it goes, by the rule it was queued under.) Its guild's reporter as the relay holds him then:
-- registered within REPORTER_FOR, not quarantined, served (a guildmate who took the place of the one
-- it was queued for takes it, so the guild still gets the line). Or the relay it named, while that
-- relay still answers and was not left out. nil: nobody (not sent, counted apart from the lost).
local function ChatAddressee(e, now)
	if e.across then
		if (offline[e.across] or 0) > now or now - (verified[e.across] or -math.huge) >= Relay.VERIFIED_FOR then return nil end
		return e.name
	end
	local r = reporters[e.guild]
	if not r or now - r.t > Relay.REPORTER_FOR or Quarantined(r.name) or not Served(r, e.body, now) then return nil end
	return r.name
end
local function ChatPop()
	chatQ[chatFirst] = nil
	chatFirst = chatFirst + 1
end
local function FeedChatNow(now)
	local b = chatBucket
	if now > b.at then b.tokens = math.min(Relay.CHAT_BURST, b.tokens + (now - b.at) * Relay.CHAT_PER_MIN / 60) end
	b.at = math.max(b.at, now)
	while chatInflight < Relay.CHAT_INFLIGHT and chatFirst <= chatLast and now >= chatWaitUntil do
		local e = chatQ[chatFirst]
		if now - e.t >= Relay.CHAT_LANE_TTL then
			ChatPop()
			stats.chatLost = (stats.chatLost or 0) + 1
		elseif b.tokens < #e.pieces then
			ChatLater(math.max(1, (#e.pieces - b.tokens) * 60 / Relay.CHAT_PER_MIN))
		else
			ChatPop()
			local to = ChatAddressee(e, now)
			if not to then
				stats.chatSkipped = (stats.chatSkipped or 0) + 1
			elseif to == ns.me then
				-- (Our own client is its guild's reporter now: handed to the guild here, as ToReporters does.)
				ToGuild("L", e.wire, e.body)
			else
				b.tokens = b.tokens - #e.pieces
				e.name = to
				ChatSend(e)
			end
		end
	end
end
FeedChat = function()
	if chatFeeding then return end
	local now = Now()
	if now < chatWaitUntil then return end
	chatFeeding = true
	-- (The check of the lane.) Whatever throws in there is captured, and the lane goes on: it was left
	-- feeding for good, every later word stopped at its first line until a /reload.
	local ok = ns.SafeCall("relay chat", FeedChatNow, now)
	chatFeeding = false
	if not ok and chatFirst <= chatLast then ChatLater(1) end
end
-- A chat line's whisper in the lane: to `guild`'s reporter (`name` when queued; `wire` and `body` the
-- line as ToReporters has it), or, `across` (the relay's key), to that other relay.
local function ChatTo(name, pieces, body, wire, guild, across)
	while ChatWaiting() >= Relay.CHAT_LANE_MAX do
		ChatPop()
		stats.chatLost = (stats.chatLost or 0) + 1
	end
	chatLast = chatLast + 1
	chatQ[chatLast] = { name = name, pieces = pieces, body = body, wire = wire, guild = guild, across = across, t = Now() }
	FeedChat()
end
function Relay.ChatWaiting() return ChatWaiting() end -- (/oly status, tests)

-- (1.5.4) The King's presence (T1~o, King.SendPresence: one piece from his signed character every
-- King.PRESENCE_EVERY) goes to every reporter as the relay's own words do, ahead of the queue and keyed
-- per reporter: a busy relay holds at most one per reporter, the latest. 60 reporters, every five
-- minutes: 12 pieces a minute of the 200 a relay sends. Within the trickle it reached a reporter
-- only by chance, and the army never saw him online (the dev's report, 2026-11-08).
local function KingPresence(origin, body)
	return #body <= 64 and body:match("^T1~o~%d+~") ~= nil and ns.IsKingCharacter ~= nil and ns.IsKingCharacter(origin) == true
end
Relay.KingPresence = KingPresence
-- (The layer hop on Forever, after 1.5.3.) The King's own layer word (L1, or L0 when he hides it,
-- from his pinned character: the relay is believed about its origin) reaches every reporter outside
-- the trickle: once when it changes, and again at most every KING_REFRESH for each reporter, so a
-- guild's members learn where to ask for his layer without his minute-by-minute repeats costing a
-- whisper per reporter each minute. With 34 reporters: 34 whispers a change, under 7 a minute else.
Relay.KING_REFRESH = 300
local kingSent = {} -- reporter name (lower) -> { body, at }: the King's layer word last sent to him
local function KingLayer(origin, body, name, now)
	if type(body) ~= "string" or not body:find("^L[01]~") or type(ns.IsKingCharacter) ~= "function"
		or not ns.IsKingCharacter(origin) then return false end
	local key = name:lower()
	local last = kingSent[key]
	if last and last.body == body and now - last.at < Relay.KING_REFRESH then return false end
	kingSent[key] = { body = body, at = now }
	return true
end
Relay.ResetKingSent = function() wipe(kingSent) end -- (tests)

-- (1.5.5) One census snapshot for each registrant. The relay's own CG set and each set another relay
-- crossed here went to every registrant under its origin's key: a registrant got every origin's, and the
-- load grew with the relays. Now a whole CG~1 or CG~2 "S" set goes to a registrant under one key, "census
-- snapshot", in a waiting one's place, and which origin's set it is the origin preference says
-- (CensusFor), from the last whole set of each origin held here (MAX_RELAYS origins) with its time; a
-- registrant is never sent again the set it was handed last.
-- (1.5.9's review) Whether a word (its head, or a mesh kind such as "QA~1" or "CX~3~S") is another
-- server's census: the author's signed look (QA) or a realm group's carried totals (CX). The drip hands it
-- over as it does a census transfer, making room at once (Turn), in the other transfers' turn.
local function CensusLook(head)
	return type(head) == "string" and (head:match("^QA~1") ~= nil or head:match("^CX~[123]~S") ~= nil)
end
local census = { held = {}, sent = {}, sentN = 0 }
local function ForgetCensus()
	wipe(census.held); wipe(census.sent)
	census.sentN, census.set, census.entry = 0, nil, nil
end
-- The held entry of a whole census set, held now (its time the snapshot's own); nil for any other set.
local function CensusSet(origin, set, now)
	if census.set == set then return census.entry end
	census.set, census.entry = set, nil
	local id, head
	if type(set) == "table" and type(set[1]) == "string" then id, head = set[1]:match("^C(%w+):%d+:%d+:(.*)$") end
	if not head or not head:match("^CG~[12]~S~") then return nil end
	local made = tonumber(head:match("^CG~[12]~S~(%d+)~")) or now
	if made > now then made = now end
	local okey = Lower(ns.ShortName(origin))
	local e = { origin = origin, set = set, made = made, key = okey .. "#" .. id .. "#" .. made }
	census.held[okey] = e
	local n, oldest = 0, nil
	for k, x in pairs(census.held) do
		n = n + 1
		if not oldest or x.made < census.held[oldest].made then oldest = k end
	end
	if n > Relay.MAX_RELAYS and oldest then census.held[oldest] = nil end
	if census.sentN > 2 * Relay.MAX_REPORTERS then wipe(census.sent); census.sentN = 0 end
	census.entry = e
	return e
end
-- The set registrant r is handed (the origin preference). One that does not take the tree (1.5.3, 1.5.4,
-- or 1.5.5 before a restart: its census trusts the Church's ledger relays alone) gets the newest set of a
-- ledger relay at most Data.FRESH old; else, and one that takes it (its census trusts the author too),
-- the newest set of an origin the census trusts (Data.CensusTrusted); else the set at hand.
local function CensusFor(r, e, now)
	local D, C = ns.Data, ns.Church
	local fresh = type(D) == "table" and tonumber(D.FRESH) or 15 * 60
	local keep = type(D) == "table" and tonumber(D.TOTAL_KEEP) or 24 * 60 * 60
	local best
	if not Relay.TreeCapable(r.name) and type(C) == "table" and not C.missing and type(C.IsLedgerRelay) == "function" then
		for _, x in pairs(census.held) do
			if now - x.made <= fresh and (not best or x.made > best.made) and C.IsLedgerRelay(x.origin) == true then best = x end
		end
	end
	if not best and type(D) == "table" and type(D.CensusTrusted) == "function" then
		for _, x in pairs(census.held) do
			if now - x.made <= keep and (not best or x.made > best.made) and D.CensusTrusted(x.origin) == true then best = x end
		end
	end
	return best or e
end

-- (1.5.9's review) The census snapshot still waiting in the drip for registrant `name`, dropped: the tree
-- serves him now (RelayTree.Offer). Sent anyway, it went with the set it held when queued, stale, on top
-- of the tree's word, and the 1.5.4 registrants' snapshots waited behind it (the offline harness, a peer's
-- snapshot crossing just before the relay's first own round: all 30 tree-capable registrants took it by
-- the star as well). He is no longer counted as sent it, so a later turn back to the star sends him the
-- newest set again.
local function DropWaitingCensus(name)
	for i, d in ipairs(drip) do
		if d.name == name and d.word == "census snapshot" and not d.started then
			table.remove(drip, i)
			local who = Lower(name)
			if census.sent[who] ~= nil then census.sent[who], census.sentN = nil, math.max(0, census.sentN - 1) end
			return true
		end
	end
	return false
end

local function ToReporters(flag, origin, body, sender)
	local now = Now()
	if Crown(origin, body) then
		local n = 0
		for _ in pairs(reporters) do n = n + 1 end
		if not Remembered(origin, body) then ns.Log("relay: %s's word (T1) to %d reporters", tostring(sender), n) end
		return CrownToReporters(flag, origin, body, now)
	end
	local own = ns.FullName(origin) == ns.me
	local approvalGuild = Relay.ApprovalResendGuild(body)
	if approvalGuild then approvalGuild = Lower(approvalGuild) end
	local fresh = 0
	for _, r in pairs(reporters) do
		if now - r.t <= Relay.REPORTER_FOR then fresh = fresh + 1 end
	end
	share = math.min(Relay.REPORTER_RATE, Relay.TRICKLE_PER_MIN / math.max(1, fresh))
	local scoped, fxKind = PresentationScope(origin, body, now)
	local presence = flag ~= "L" and KingPresence(origin, body)
	-- (The review of the 1.5.4 candidate, mixed versions.) A layer word (L1, L0: GUILD_TOO) names its
	-- origin plain on the wire, as his own copy over GUILD does (OwnGuild). Stamped here with this
	-- relay's sub-realm, it was a second name for him at every 1.5.3 client, whose Seen and Layers key
	-- the name as written: a 1.5.3 reporter handed the relay's copy to the guild after the origin's own,
	-- and a 1.5.3 guildmate on another sub-realm counted him twice (a 1.5.4 one takes a layer word by
	-- the short name, Deliver). The origin as stamped stays everywhere else: Seen, the keys, Deliver here.
	local wire = GuildRoute(body) == "too" and ns.ShortName(origin) or origin
	-- Reserve a complete, bounded snapshot from a signed origin. Charging each
	-- fragment against the four-piece ordinary trickle stranded every larger
	-- snapshot mid-transfer. This admits no new authority and does not bypass
	-- Comm's queue/throughput limits; malformed or unreserved parts use the trickle.
	-- (1.5.5) And a signed relay's own staff word (Relay.StaffWord), in one piece: past the trickle.
	local snapshot = SnapshotPart(origin, body, now) or Relay.StaffWord(origin, body)
	-- A trickle-exempt word in pieces goes to the other reporters as a whole set (above).
	-- (1.5.4) And a list of a kind carried whole, from any origin, in one piece too (ListSet); once
	-- whole, to the reporters ListSend names, in place of a waiting batch alone when it says so.
	local set, batches, listTo, waitingOnly
	local list = flag ~= "L" and not snapshot and ListSet(origin, body, now, own) or nil
	if list then set = list.one and { body } or CollectSet(origin, body, now)
	elseif (own or snapshot) and flag ~= "L" then set = CollectSet(origin, body, now) end
	if list and type(set) == "table" then
		listTo, waitingOnly = ListSend(list, origin, set, now, function(r)
			return not Quarantined(r.name) and (Ask("RM", r.name, body, now)) == true
		end)
	end
	-- (The review of the candidate.) Another client's word in pieces passes the trickle whole or not
	-- at all: the pieces before its last are full, and a full piece with its RM label is one or two
	-- whispers. The least it takes, for Afford: a census report in two pieces (385 bytes) is three
	-- whispers, which every allowance holds; one in three pieces is five, which none does.
	local need, wordKey, first
	do
		local id, i, n = body:match("^C(%w+):(%d+):(%d+):")
		n = tonumber(n)
		if n and n >= 2 then
			local label = #("RM~" .. flag .. "~" .. origin .. "~" .. ("C%s:1:%d:"):format(id, n))
			need = (n - 1) * (label + ns.Codec.CHUNK > 255 and 2 or 1) + 1
			-- (The word, for Afford to pay for it whole at its first piece and let its others through.)
			wordKey, first = Lower(origin) .. "#" .. id, tonumber(i) == 1
		end
	end
	local pieces
	local snap = flag ~= "L" and type(set) == "table" and CensusSet(origin, set, now) or nil -- (1.5.5: a census set, held)
	for g, r in pairs(reporters) do
		if now - r.t > Relay.REPORTER_FOR or Quarantined(r.name) then
			reporters[g] = nil
		elseif approvalGuild and g ~= approvalGuild then
			-- The re-send is for the guild whose approval it carries.
		elseif not Served(r, body, now) then
			-- (1.5.4) A reporter the relay does not serve (no presentation from the deadline on, or
			-- denied): nothing to him (counted, Stats().unserved).
		elseif scoped and g ~= scoped and not (fxKind == "G" and Presenting(g, now)) then
			stats.scoped = (stats.scoped or 0) + 1 -- (another guild's presentation: heard here alone)
		elseif r.name == ns.me then
			if Deliver(origin, body, flag == "L") then ToGuild(flag, wire, body) end
		elseif set == false then
			-- (Some pieces of the set are still on their way: the whole set goes once they are here.)
		elseif set and listTo and not listTo[g] then
			-- (A list his guild holds already, or one refused: not to him.)
		elseif set and type(ns.RelayTree) == "table" and not ns.RelayTree.missing and type(ns.RelayTree.Offer) == "function"
			and ns.RelayTree.Offer(r, origin, set, flag, own) == true then
			-- (1.5.5) The tree took this set for this reporter (RelayTree.Offer).
			DropWaitingCensus(r.name)
		elseif set and snap then
			-- (1.5.5) One census snapshot a registrant, the origin's its census trusts (CensusFor), keyed
			-- "census snapshot" whatever its origin: a newer one takes a waiting one's place. Never the set
			-- it was handed last again.
			local e, who = CensusFor(r, snap, now), Lower(r.name)
			if census.sent[who] ~= e.key then
				if census.sent[who] == nil then census.sentN = census.sentN + 1 end
				census.sent[who] = e.key
				e.batches = e.batches or SetBatches("P", e.origin, e.set)
				DripBatches(r.name, "census snapshot", e.batches, waitingOnly, nil, true)
			end
		elseif set then
			batches = batches or SetBatches(flag, origin, set)
			-- (review prototype) A newer copy replaces a waiting one only where it supersedes it: the
			-- same origin's snapshot of one kind, or its census report. Any other word keeps its own
			-- place (two of the King's T1 words, say, are different words).
			-- (The review of the 1.5.4 candidate.) The relay's own words in pieces are its repeats (the
			-- King's Hands every 300 s, the Treasury's every 300 s, a ranking's repeat): keyed by their
			-- message id, each repeat waited as a new batch behind the rest, the drip grew without end
			-- and the census snapshots waited behind it. Its own word of one kind (as QueueWord keys
			-- the same word in one whisper) takes the waiting copy's place, as a snapshot does.
			local id, head = set[1]:match("^C(%w+):%d+:%d+:(.*)$")
			-- (1.5.4) A list by its kind (ListKind: "LS~NR"), any origin's: a newer list of the kind
			-- takes the waiting one's place, two kinds keep their own.
			local kind = head and (head:match("^(%u%w~%d+~S)~") or head:match("^(R[12])~") or ListKind(head)
				or (own and head:match("^%u%w~") and QueueWord(head)))
			local word = Lower(origin) .. " " .. (kind or ("#" .. tostring(id)))
			-- (The review of the candidate.) A word too long for one batch (its envelope past MAX_CHUNKS
			-- whispers, so each piece goes wrapped alone: two batches), replaced batch by batch, mixed
			-- halves of two copies where the older copy's first batch was in flight. (Its load review.)
			-- Keyed by its message id instead, no repeat ever took its waiting copy's place: the drip
			-- grew without end (70 batches a repeat at 35 reporters, drained at about three a minute)
			-- and the census snapshots waited behind it, hours stale. A copy takes the waiting one's
			-- place while every batch of that one still waits; with one in flight it takes the one
			-- "next" place, which the copy after it takes in turn: at most two copies a reporter, whole.
			-- (1.5.9's review) The other servers' census, a signed look (QA) and carried totals (CX), makes
			-- room at once (CensusLook): waiting for free room, under a busy queue no look reached a
			-- registrant (0 of 5 in five minutes; at 30 registrants 26 of 30 none in ten).
			DripBatches(r.name, word, batches, waitingOnly, nil, nil, CensusLook(head))
		else
			pieces = pieces or Envelope("RM", "RM~" .. flag .. "~" .. wire .. "~" .. body)
			-- (1.5.0) Another client's word that is not a chat line: within the reporter's trickle
			-- (REPORTER_RATE) or not sent to him; the relay's own words and chat lines always.
			if flag == "L" then
				-- (1.5.5) A chat line: by the chat lane (above), never pushed out of the queue.
				stats.forwarded = stats.forwarded + 1
				ChatTo(r.name, pieces, body, wire, g)
			elseif own or snapshot or presence or KingLayer(origin, body, r.name, now) or Afford(r.name, #pieces, now, need, wordKey, first) then
				stats.forwarded = stats.forwarded + 1
				Quiet(r.name) -- (a reporter gone offline since: the server's line out of the chat)
				-- A word that is not a chat line is keyed by its origin, kind and reporter: a newer
				-- census of the same guild takes the waiting one's place in the queue (Comm's keyed
				-- jobs), so a busy relay sends the latest, never a backlog. (1.5.4) A list in one
				-- piece by its kind (ListKind), so two kinds' lists never take each other's place.
				local word = presence and "T1~o" or ListKind(body) or QueueWord(body)
				local key = flag ~= "L" and ("relay " .. r.name .. " " .. Lower(origin) .. " " .. word) or nil
				if #pieces == 1 then ns.Comm.Whisper(r.name, pieces[1], key, presence, false)
				else ns.Comm.SendBatch("WHISPER", pieces, key, r.name, presence) end
			else
				stats.trickled = (stats.trickled or 0) + 1
			end
		end
	end
	local n = 0
	for _ in pairs(reporters) do n = n + 1 end
	if not Remembered(origin, body) then ns.Log("relay: %s's word (%s) to %d reporters", tostring(sender), body:sub(1, 2), n) end
	Deliver(origin, body, flag == "L")
	-- The same complete snapshot must cross to the other relays. Separately wrapping each
	-- piece with a Forever sender's long realm can exceed the queue before it starts sending.
	if own or snapshot then return set end
end

-- (1.5.5) The mesh. On Forever every live relay was an island: a relay's own client counts itself as
-- answered (Pick), so it never pinged another one, none learned that another answered, and Across
-- reached nobody: a word reached only the guilds registered with the relay that heard it, and the
-- author's census never left his own relay's guilds (the reports of 2026-11-09 and 11-10). Now each
-- signed relay pings the other signed relays (Relay.Mesh: 10 s after login, then every MESH_EVERY)
-- and tells each one that answered that it is of the mesh: RJ~1~<registrants>~<tree-capable ones>,
-- one whisper. A mesh peer (Relay.MeshPeer) answered within VERIFIED_FOR and said RJ within
-- MESH_FOR. A 1.5.4 relay answers the ping and never says RJ, so it never becomes one and is never
-- sent RX: an RX marks its sender answered there, and that relay's Across would then send it every
-- word its clients say, piece by piece, flooding both queues.
Relay.MESH_EVERY = 300
Relay.MESH_FOR = 630         -- (two rounds missed, and the whispers' way)
Relay.MESH_CROSS_EVERY = 300 -- our own census snapshot to one peer this often at most
-- The staff words (by RW, HandleIn and HandleVerify below): one piece, said by a signed relay's own
-- client, of these kinds; T1 but the King's crown and presence (T1~P, T1~Q, T1~o: CrownToRelays).
Relay.CROSS_KINDS = { T1 = true, D1 = true, O1 = true, O2 = true, MD = true, TF = true, MC = true, HA = true,
	V4 = true, U2 = true, BQ = true, PS = true, TA = true, WY = true, W5 = true, CX = true, RE = true }
-- seen: peer (short name, lower) -> when its RJ came; peers: -> { regs, tree } its RJ named; sent: ->
-- when ours went to it; cg: -> when our census snapshot last went across to it; plain: guild (lower)
-- -> when a registration came from a client that is not tree-capable; n: counters (/oly bug).
local mesh = { seen = {}, peers = {}, sent = {}, cg = {}, cgTurn = {}, plain = {}, n = {} }
-- Whether a signed relay (short name, lower) is a mesh peer now (Relay.MeshPeer asks its signature too).
function mesh.Fresh(key, now)
	return now - (verified[key] or -math.huge) < Relay.VERIFIED_FOR and now - (mesh.seen[key] or -math.huge) < Relay.MESH_FOR
end
local function StaffKind(body)
	if type(body) ~= "string" then return false end
	local word = body:match("^C%w+:1:1:(.*)$") or body -- (a word Comm.SendChunked cut into one piece: a census look)
	return word:sub(3, 3) == "~" and Relay.CROSS_KINDS[word:sub(1, 2)] == true and not word:match("^T1~[PQo]~")
end
-- A staff word of a signed relay's own (its origin is the relay): past the trickle (ToReporters).
function Relay.StaffWord(origin, body)
	return StaffKind(body) and type(origin) == "string" and Relay.IsSignedRelay(origin)
end

-- Hold only the newest complete CG while the cross-relay queue is busy. Fill free slots
-- in least-recently-offered order, with the King first. A missed slot never advances a
-- peer's send cadence; the clock starts only after the complete transfer has left Comm.
refillCensusAcross = function()
	local p = mesh.census
	if not p then return end
	local now = Now()
	if now - p.at > Relay.SET_MAX_AGE or not CensusAcrossAllowed() then
		mesh.census = nil
		return
	end
	local total, occupied, waiting = 0, {}, {}
	for _, d in ipairs(drip) do
		if d.across then
			total = total + 1
			occupied[d.name] = (occupied[d.name] or 0) + 1
			if d.word == p.word then waiting[d.name] = d end
		end
	end
	local due, blocked = {}, false
	for _, name in ipairs(Relay.Names(false, true)) do
		local key = name:lower()
		if key ~= p.from and mesh.Fresh(key, now) then
			local d = waiting[name]
			if d then
				-- In-flight batches are immutable. Only a still-waiting copy can be replaced.
				if not d.started then
					d.batches, d.censusAt, p.tried[key] = p.batches, p.at, true
				elseif not p.tried[key] then
					blocked = true
				end
			elseif not p.tried[key] then
				if now - (mesh.cg[key] or -math.huge) >= Relay.MESH_CROSS_EVERY then
					due[#due + 1] = { name = name, key = key, turn = mesh.cgTurn[key] or -math.huge,
						king = ns.IsKingCharacter and ns.IsKingCharacter(ns.FullName(name)) == true or false }
				else
					p.tried[key] = true
					mesh.n.cgHeld = (mesh.n.cgHeld or 0) + 1
				end
			end
		end
	end
	table.sort(due, function(a, b)
		if a.king ~= b.king then return a.king end
		if a.turn ~= b.turn then return a.turn < b.turn end
		return a.key < b.key
	end)
	for _, peer in ipairs(due) do
		if total >= Relay.ACROSS_MAX then blocked = true; break end
		if (occupied[peer.name] or 0) >= Relay.ACROSS_PER_PEER then
			blocked = true
		else
			local key = peer.key
			mesh.cgTurn[key], p.tried[key] = now, true
			local job = { name = peer.name, word = p.word, batches = p.batches, index = 1, across = true, census = true,
				censusAt = p.at, kingCensus = peer.king, censusSent = function() mesh.cg[key] = Now() end, at = now }
			-- The King's one due copy waits behind an active transfer, not behind the
			-- whole local reporter queue. Every waiting job keeps its place behind it.
			if peer.king then table.insert(drip, drip[1] and drip[1].started and 2 or 1, job)
			else drip[#drip + 1] = job end
			total = total + 1
			stats.across = (stats.across or 0) + p.parts
		end
	end
	if not blocked then mesh.census = nil end
end

-- (1.4.6) The same word to the other relays (RX), each to hand to its own reporters. (1.5.5)
-- Only mesh peers hear this relay's own census snapshots (CG, CX and GV "S" words), lists (LS)
-- and chat lines. The guilds' individual reports stay on their relay and are reflected in CG.
local function Across(flag, origin, body, set)
	if set == false then return end -- the whole transfer follows its last piece
	local mine, from = Lower(ns.ShortName(ns.me or "")), Lower(ns.ShortName(origin))
	local kind -- (a chat line is unkeyed, as ever)
	if flag == "L" then
		if set or (ns.FullName(origin) == ns.me and StaffKind(body)) then return end
	else
		if ns.FullName(origin) ~= ns.me then return end
		local first = type(set) == "table" and set[1] or body
		local head = first:match("^C%w+:%d+:%d+:(.*)$") or first
		-- (1.5.8, the author, 11-12: "não tá redistribuindo na rede") The author's signed look (QA) this
		-- relay's client says (Data.AttestPayload: the newest it holds of each origin, once each
		-- GROUP_SAY_EVERY unless heard meanwhile) crosses too: it proves itself whoever carries it, and it
		-- reached only this relay's own guilds, so the PvP look left other relays' guilds with the author.
		kind = head:match("^(CG~[12]~S)~%d+~") or head:match("^(GV~1~S)~%d+~") or ListKind(head)
			or (type(set) == "table" and #set > 1 and (head:match("^(CX~[123]~S)~") or head:match("^(QA~1)~"))) or nil
		if not kind then return end
		if kind:sub(1, 2) == "CG" then
			local whole = type(set) == "table"
			local batches = whole and SetBatches(flag, origin, set, "RX") or { Envelope("RX", "RX~" .. flag .. "~" .. origin .. "~" .. body) }
			mesh.census = { at = Now(), word = "across " .. from .. " CG", from = from, batches = batches, parts = whole and #set or 1, tried = {} }
			refillCensusAcross()
			Drip()
			return
		end
	end
	local now = Now()
	local pieces, batches
	for _, name in ipairs(Relay.Names(false, true)) do
		local key = name:lower()
		if key ~= mine and key ~= from and mesh.Fresh(key, now) then
			if type(set) == "table" then
				batches = batches or SetBatches(flag, origin, set, "RX")
				DripBatches(name, "across " .. from .. " " .. kind, batches, false, true, nil, CensusLook(kind))
				stats.across = (stats.across or 0) + #set
			else
				pieces = pieces or Envelope("RX", "RX~" .. flag .. "~" .. origin .. "~" .. body)
				stats.across = (stats.across or 0) + 1
				if flag == "L" then
					ChatTo(name, pieces, body, origin, nil, key)
				else
					Quiet(name)
					local qkey = "across " .. name .. " " .. from .. " " .. kind
					if #pieces == 1 then ns.Comm.Whisper(name, pieces[1], qkey, false, false)
					else ns.Comm.SendBatch("WHISPER", pieces, qkey, name, false) end
				end
			end
		end
	end
end

-- A verifier may be on another relay. Only the small, validated query crosses;
-- it never becomes one whisper per guild and never authorizes a cached decision.
local function VerificationAsk(body)
	if type(body) ~= "string" or #body > 128 then return false end
	return body:match("^GV~1~Q~%d+~%d+~%d+$") ~= nil
		or body:match("^GV~1~Q~%d+~%d+~%d+~%x+$") ~= nil
end

-- (1.5.4) A verifier's approval or revocation, and whether its origin is a verifier as this relay
-- knows them (Verify.Trusted): only such a decision is fanned out and crossed.
local function Decision(body) return type(body) == "string" and body:match("^GV~1~[AR]~") ~= nil end
local function Signed(origin)
	local V = ns.Verify
	return type(V) == "table" and type(V.Trusted) == "function" and V.Trusted(origin) == true
end

-- (1.5.4) Verification to every other relay not left out (RW), answered or not (see the top); the
-- origin, when a relay, is not sent its own word. Never marks a relay as answered. Urgent: a few
-- short whispers, rare (a decision, a relay's half-hourly ask, one client's ask each
-- VERIFY_ASK_EVERY), never evicted behind the reports. (1.5.5) staff: one of this relay's own staff
-- words (Relay.CROSS_KINDS), to the signed relays alone, the only ones that take it.
local function ToRelays(flag, origin, body, staff)
	local now = Now()
	local mine, from = ns.ShortName(ns.me or ""):lower(), ns.ShortName(origin):lower()
	local pieces, n = nil, 0
	for _, name in ipairs(Relay.Names(false, staff == true)) do
		local key = name:lower()
		if key ~= mine and key ~= from and (offline[key] or 0) <= now then
			pieces = pieces or Envelope("RW", "RW~" .. flag .. "~" .. origin .. "~" .. body)
			if staff then mesh.n.staffOut = (mesh.n.staffOut or 0) + 1
			else stats.verifyAcross = (stats.verifyAcross or 0) + 1 end
			n = n + 1
			Quiet(name)
			if #pieces == 1 then ns.Comm.Whisper(name, pieces[1], nil, true, false)
			else ns.Comm.SendBatch("WHISPER", pieces, nil, name, true) end
		end
	end
	-- (The review of the 1.5.4 candidate.) A line for /oly bug: that it crossed, and to how many.
	if pieces then ns.Log("relay: %s's word (%s) across to %d relays", tostring(origin), body:sub(1, 6), n) end
end

-- (1.5.4) A verifier's answer to the one client that asked, never to every reporter: a whole store
-- (up to MAX_CHUNKS pieces) to each of 30-60 reporters never got through a relay's queue of
-- MAX_QUEUE parts. A relay that asked takes it as RW; any other client as RM from its relay, and
-- hands it to its guild once (HandleRelayed). One urgent transfer. True when queued.
function Relay.Direct(target, body, key)
	if not Relay.On() or not Relay.IsRelay(ns.me) or type(target) ~= "string" or target == "" or type(body) ~= "string" then return false end
	if ns.ShortName(target):lower() == ns.ShortName(ns.me or ""):lower() then return false end
	local kind = Relay.IsRelay(target) and "RW" or "RM"
	local pieces = Envelope(kind, kind .. "~P~" .. ns.me .. "~" .. body)
	if #pieces == 0 or #pieces > ns.Codec.MAX_CHUNKS then return false end
	stats.direct = (stats.direct or 0) + 1
	Quiet(target)
	if #pieces == 1 then return ns.Comm.Whisper(target, pieces[1], key, true, false) ~= false end
	return ns.Comm.SendBatch("WHISPER", pieces, key, target, true) ~= false
end

-- (1.5.5) The hop delivering a word now and its sender (Relay.Hop, before Relay.Reset): declared
-- here, above the handlers that set it.
local hop, hopSender, WithHop

-- Hop 1 heard (we are a relay): a ping is answered, a registration kept, anything else forwarded
-- to every guild's reporter (ours included: delivered here and handed to our guild).
function Relay.HandleIn(dist, sender, text)
	if dist ~= "WHISPER" or not Relay.On() then return false end
	local flag, body = tostring(text):match("^RL~([LP])~(.*)$")
	if not flag then return false end
	if not Relay.IsRelay(ns.me) then -- (only a relay's client answers hop 1; 1.5.5: or a fallback relay)
		local F = ns.RelayFallback
		if type(F) == "table" and not F.missing and type(F.HandleIn) == "function" then
			return F.HandleIn(dist, sender, text) == true
		end
		return false
	end
	local now = Now()
	Heard(body == "RP~" and "RP" or (body:sub(1, 3) == "RR~" and "RR") or "RL", sender, body, now) -- (1.5.4)
	if body == "RP~" then
		if ns.FullName(sender) ~= ns.me then Acknowledge(sender, now) end
		return true
	end
	local guild = body:match("^RR~(.+)$")
	if guild then
		local version
		guild, version = Registration(sender, guild, now) -- (1.5.4: a version named is the reporter's presentation)
		-- (1.5.4, a player's security report of 1.5.3) A registration was taken from any whisperer,
		-- for any number of guilds, of any length: one character could take every guild's feed.
		-- A guild's name as the game allows it (at most MAX_GUILD_NAME, no separator), one guild
		-- per reporter (a new one leaves his old one), and at most MAX_REPORTERS guilds.
		local who, key = ns.FullName(sender), guild:lower()
		if #guild > Relay.MAX_GUILD_NAME or guild:find("[~|%c]") or Quarantined(who) then
			stats.dropped = stats.dropped + 1
			return true
		end
		-- (1.5.4) Refused (no presentation from the deadline on, a version the rules do not admit, a
		-- denied character): not kept, and a registration of his held from before goes with it.
		if not Admitted("RR", sender, body, now) then
			Unregister(who)
			return true
		end
		local count = 0
		for g, r in pairs(reporters) do
			if r.name == who and g ~= key then reporters[g] = nil else count = count + 1 end
		end
		if not reporters[key] and count >= Relay.MAX_REPORTERS then
			stats.dropped = stats.dropped + 1
			return true
		end
		local had = reporters[key]
		-- (1.5.5) A tree-capable registrant (RelayTree: digest-checked delivery from its guildmates) keeps
		-- its guild while fresh: a registration from a guildmate that is not one (an older version, which
		-- registers every REGISTER_EVERY whatever its newer guildmates do) does not take its place.
		local capable = Relay.TreeCapable(who)
		if not capable then mesh.plain[key] = now end
		if had and had.name ~= who and now - had.t <= Relay.REPORTER_FOR and not capable and Relay.TreeCapable(had.name) then
			mesh.n.rrKept = (mesh.n.rrKept or 0) + 1
			return true
		end
		reporters[key] = { name = who, t = now, guild = guild, v = version }
		stats.registered = stats.registered + 1
		if not had or had.name ~= ns.FullName(sender) then ns.Log("relay: %s's reporter is %s", guild, tostring(sender)) end
		return true
	end
	local origin = ns.FullName(sender)
	-- (1.5.4) A word from a character the relay does not serve (Admit): dropped, answered by nobody.
	if not Admitted("RL", sender, body, now) then return true end
	local fresh = not Remembered(origin, body, now)
	if Relay.ApprovalResendGuild(body) then
		if not (fresh and ns.Verify and ns.Verify.CanForwardResend and ns.Verify.CanForwardResend(body, origin)) then return true end
		ToRelays("P", origin, body)
		WithHop("L", sender, ToReporters, "P", origin, body, sender)
		return true
	end
	local localOnly = Relay.NO_FORWARD[body:sub(1, 2)]
	-- Verification queries are periodic background traffic; decisions and recovery snapshots
	-- must reach the guilds. Keeping the entire GV prefix here swallowed a verifier's direct
	-- approvals and revocations on Forever's relay-only route. Verify still checks the original
	-- sender against this origin group's signed authority at the destination.
	if body:match("^GV~1~[ARS]~") then localOnly = false end
	-- (1.5.4) A verifier's decision (as this relay knows them) also goes once to every other relay
	-- (RW), each handing it to its own reporters: no client makes every relay fan out a forged one.
	if fresh and Decision(body) and Signed(origin) then ToRelays(flag, origin, body) end
	-- (1.5.4) A modified-build sighting or its clear (BD, Builds.lua) heard from one of our clients
	-- goes once to every other relay too, each handing it to its own reporters; the origin's right to
	-- say it is checked where it is kept (Builds.HandleShare).
	if fresh and body:match("^BD~1~") then ToRelays(flag, origin, body) end
	-- (1.5.5) This relay's own staff word (Relay.CROSS_KINDS: the King's and the staff's acts, the
	-- author's presence and release, the Treasury's ask, a census look, the fallback's candidates) goes
	-- to every other signed relay (RW), answered or not; each hands it to its own registrants past
	-- their trickle and sends it on to nobody. Before, it reached this relay's own guilds alone.
	if fresh and origin == ns.me and StaffKind(body) and Relay.IsSignedRelay(ns.me) then ToRelays(flag, origin, body, true) end
	-- (1.5.5) This relay's own census claim (CG~n~C~, every GLOBAL_EVERY on a relay the census does not
	-- trust) and its census ask (CG~n~Q~): heard here alone. Fanned out, each was a whisper to every
	-- registrant, and none needs either: the guilds' answers come to this relay, which hears them all.
	if localOnly and (origin ~= ns.me or VerificationAsk(body) or body:match("^CG~%d+~[CQ]~")) then
		stats.kept = (stats.kept or 0) + 1
		WithHop("L", sender, Deliver, origin, body, flag == "L") -- (heard and answered here, fanned out to nobody)
		-- (1.5.4) Our own ask always crosses (our client is its own relay: nobody else hears it);
		-- a client's, one each VERIFY_ASK_EVERY, for a verifier on another relay to answer it.
		if fresh and VerificationAsk(body) and (origin == ns.me or now - lastVerifyAsk >= Relay.VERIFY_ASK_EVERY) then
			if origin ~= ns.me then lastVerifyAsk = now end
			ToRelays("P", origin, body)
		end
		return true
	end
	local set = WithHop("L", sender, ToReporters, flag, origin, body, sender)
	-- (1.4.6) To the other relays that answered our pings too (hop 1b, RX): each hands it to its
	-- own reporters. Without this every live relay was an island of the guilds registered with it
	-- (the dev's cousin saw other guilds and other numbers, 2026-11-05). A relay forwards RX no
	-- further, and a word already taken is not sent across again.
	if fresh then Across(flag, origin, body, set) end
	return true
end

-- (1.4.6) Hop 1b heard (we are a relay): another relay's copy of a word, from a relay alone,
-- handed to our reporters and heard here once; never sent across again. (1.5.5) From a signed relay
-- alone: an unsigned Treasurer code pin is transport, never a relay believed about other origins.
function Relay.HandleAcross(dist, sender, text)
	if dist ~= "WHISPER" or not Relay.On() then return false end
	local flag, origin, body = tostring(text):match("^RX~([LP])~([^~]+)~(.*)$")
	if not flag then return false end
	if not Relay.IsSignedRelay(sender) or not Relay.IsRelay(ns.me) then stats.dropped = stats.dropped + 1 return false end
	verified[ns.ShortName(sender):lower()] = Now()
	if Remembered(origin, body) then return true end
	-- (1.5.4) A word of a client marked as a modified build (Builds.lua): forwarded to nobody.
	if Quarantined(origin) then stats.dropped = stats.dropped + 1 return true end
	if VerificationAsk(body) then WithHop("X", sender, Deliver, origin, body, false); return true end
	WithHop("X", sender, ToReporters, flag, origin, body, sender)
	return true
end

-- (1.5.4) Verification between relays heard (RW): from a relay alone, to a relay, GV words alone.
-- A verifier's decision goes to our reporters and is heard here; an ask is heard here (our verifier
-- answers whoever asked, Verify.lua); an answer to our own ask is taken here. Never sent across
-- again, never fanned out as a store, and it marks nobody as answered (see the top).
-- (The review of the 1.5.4 candidate.) Each relay that asks is answered on its own gap
-- (Verify.RELAY_ANSWER_GAP), apart from the clients' one ANSWER_GAP. That gap was given to any ask
-- whose origin was a relay's name, and an ask's origin is a payload's word on RG, RM and RX: one
-- guildmate naming each relay in turn got the verifier's whole store sent once per relay, and the
-- real relay's own ask then waited RELAY_ANSWER_GAP. Only an ask that came across here, its relay's
-- name stamped by the server, is a relay's ask now (Relay.AskedAcross, read by Verify.lua).
local acrossFrom -- while an ask that came across is heard here: its relay's short name (lower)
function Relay.AskedAcross(name)
	return acrossFrom ~= nil and type(name) == "string" and Lower(ns.ShortName(name)) == acrossFrom
end
function Relay.HandleVerify(dist, sender, text)
	if dist ~= "WHISPER" or not Relay.On() then return false end
	local flag, origin, body = tostring(text):match("^RW~([LP])~([^~]+)~(.*)$")
	if not flag then return false end
	-- (1.5.5) A signed relay's own staff word (Relay.CROSS_KINDS, HandleIn): its origin is its sender,
	-- whose name the server stamps, so no relay passes another origin's staff word. Taken, handed to our
	-- registrants past their trickle (ToReporters: Relay.StaffWord), sent on to nobody. Its copies over
	-- RW count once; a copy that came first by our own guild (a guildmate reports to that relay) does
	-- not keep our registrants from it.
	if StaffKind(body) then
		if not Relay.IsRelay(ns.me) or not Relay.IsSignedRelay(sender) or Lower(ns.ShortName(origin)) ~= Lower(ns.ShortName(sender)) then
			stats.dropped = stats.dropped + 1
			return false
		end
		if Seen("rw " .. origin, body) then return true end
		mesh.n.staffIn = (mesh.n.staffIn or 0) + 1
		ns.Log("relay: RW %s from %s", body:sub(1, 6), tostring(sender))
		WithHop("W", sender, ToReporters, flag, origin, body, sender)
		return true
	end
	if not Relay.IsRelay(sender) or not Relay.IsRelay(ns.me) or not (body:match("^GV~1~[ARQS]~") or body:match("^BD~1~")) then
		stats.dropped = stats.dropped + 1
		return false
	end
	if Remembered(origin, body) then return true end
	-- (The review of the 1.5.4 candidate.) A line for /oly bug: what came across, from which relay.
	ns.Log("relay: RW %s from %s, origin %s", body:sub(1, 6), tostring(sender), tostring(origin))
	-- (1.5.4) A modified-build sighting or its clear crossed from another relay (Builds.lua): to our
	-- reporters, heard here (its origin checked where it is kept), never sent across again.
	if body:match("^BD~1~") then
		WithHop("W", sender, ToReporters, flag, origin, body, sender)
		return true
	end
	if Decision(body) then
		if not Signed(origin) then stats.dropped = stats.dropped + 1 return false end
		WithHop("W", sender, ToReporters, flag, origin, body, sender) -- (heard here too)
		return true
	end
	if Relay.ApprovalResendGuild(body) then
		if not (ns.Verify and ns.Verify.CanForwardResend and ns.Verify.CanForwardResend(body, origin)) then return false end
		WithHop("W", sender, ToReporters, "P", origin, body, sender)
		return true
	end
	acrossFrom = Lower(ns.ShortName(sender))
	local ok, err = pcall(WithHop, "W", sender, Deliver, origin, body, false)
	acrossFrom = nil -- (whatever happened: no later ask may pass for this one)
	if not ok then error(err, 0) end
	return true
end

-- Hop 2 heard (we are a reporter): from a relay alone; delivered here and handed to our guild.
function Relay.HandleRelayed(dist, sender, text)
	if dist ~= "WHISPER" or not Relay.On() then return false end
	local flag, origin, body = tostring(text):match("^RM~([LP])~([^~]+)~(.*)$")
	if not flag then return false end
	if not Relay.IsRelay(sender) then stats.dropped = stats.dropped + 1 return false end
	verified[ns.ShortName(sender):lower()] = Now()
	-- (1.5.4) A word of a client marked as a modified build (Builds.lua): not heard, not handed on.
	if Quarantined(origin) then stats.dropped = stats.dropped + 1 return true end
	if not Remembered(origin, body) then ns.Log("relay: %s's word (%s) by %s", tostring(origin), body:sub(1, 2), tostring(sender)) end
	if Relay.TakeVia("M", sender, origin, body, flag == "L") then ToGuild(flag, origin, body) end
	return true
end

-- Hop 3 heard (a guildmate's hand-over): delivered here once.
function Relay.HandleGuild(dist, sender, text)
	if dist ~= "GUILD" or not Relay.On() then return false end
	local flag, origin, body = tostring(text):match("^RG~([LP])~([^~]+)~(.*)$")
	if not flag then return false end
	Relay.TakeVia("G", sender, origin, body, flag == "L")
	return true
end

-- The relay's answer to our ping: "RY~", or (1.5.4) RY~<version> from a relay that holds our
-- presentation. Either way we present ourselves to it (PresentTo) before what waited goes.
function Relay.HandleAck(dist, sender, text)
	if dist ~= "WHISPER" then return false end
	local named = tostring(text):match("^RY~(.*)$")
	if not named then return false end
	local key = ns.ShortName(sender):lower()
	if not verified[key] then ns.Log("relay: %s answers", tostring(sender)) end
	verified[key] = Now()
	pinged[key] = nil
	offline[key] = nil
	PresentTo(sender, named) -- (1.5.4: queued first, so the relay holds it before our words)
	Flush() -- (1.4.4) what waited for an answer goes out now
	return true
end

-- (1.5.4) The relay rules (RU): the deadline of the presentation, its switch and the versions a relay
-- admits, handed to the relays in game so no release is needed to change them.
--   RU~1~<rev>~<on>~<at>~<v1,v2,...>   the rules: their revision, 1 or 0 (the requirement on or
--                                       paused), the deadline's epoch, the versions admitted
--                                       (MAX_RULE_VERSIONS at most; none named: every release's
--                                       form); in Codec's pieces when longer than one whisper
--   RU~1~Q~<rev>                        a relay's ask: rules newer than this revision
-- Only the author's client makes a new revision (/oly relay rules; ns.IsAuthorName on the sender the
-- server stamps; 1.5.5: or one of his launch characters, RulesAuthor below) and hands it to every
-- relay it knows, at login and every RULES_EVERY. He is rarely
-- online, so the relays carry it among themselves: each keeps the newest it holds in the realm
-- group's store (ns.rdb.relayRules: a /reload or the next login applies it with nothing arriving),
-- asks the other relays at login and every RULES_EVERY, answers an ask with its copy when newer, and
-- hands a newer revision it receives to every other relay once. A copy from a signed relay is taken
-- when newer than what is held (relays are trusted characters already); anyone else's is dropped; an
-- older or the same revision changes nothing; a malformed word is dropped.
function Relay.EncodeRules(r)
	return ("RU~1~%d~%d~%d~%s"):format(r.rev, r.on ~= false and 1 or 0, r.at, table.concat(r.versions, ","))
end
function Relay.DecodeRules(body)
	local rev, on, at, list = tostring(body):match("^(%d+)~([01])~(%d+)~(.*)$")
	if not rev or #rev > 9 or #at > 12 then return nil end
	local versions = {}
	if list ~= "" then
		for v in (list .. ","):gmatch("([^,]*),") do
			if not Relay.VersionOf(v) then return nil end
			versions[#versions + 1] = v
			if #versions > Relay.MAX_RULE_VERSIONS then return nil end
		end
	end
	return { rev = tonumber(rev), on = on == "1", at = tonumber(at), versions = versions }
end
-- Newer rules kept in the realm group's store, in force at once.
local function KeepRules(r, from, now)
	if not ns.rdb then return false end
	r.from, r.t = ns.ShortName(from or "") or "?", now
	ns.rdb.relayRules = r
	ns.Log("relay rules: revision %d from %s (%s from %d, %d versions)", r.rev, tostring(r.from), r.on and "required" or "paused", r.at, #r.versions)
	return true
end
local function RulesTo(name, r, key)
	local pieces = Envelope("RU", Relay.EncodeRules(r))
	if #pieces == 0 or #pieces > ns.Codec.MAX_CHUNKS then return false end
	Quiet(name)
	if #pieces == 1 then return ns.Comm.Whisper(name, pieces[1], key, true, false) ~= false end
	return ns.Comm.SendBatch("WHISPER", pieces, key, name, true) ~= false
end
-- To every other relay not left out, each once per revision (the one they came from left out).
local function ForwardRules(r, except)
	local now, mine, from = Now(), Lower(ns.ShortName(ns.me or "")), Lower(ns.ShortName(except or ""))
	for _, name in ipairs(Relay.Names(false)) do
		local key = Lower(name)
		if key ~= mine and key ~= from and (offline[key] or 0) <= now and rulesSent[key] ~= r.rev then
			rulesSent[key] = r.rev
			RulesTo(name, r, "relay rules " .. key)
		end
	end
end
-- (1.5.5) Who makes the rules: the author's characters, and his launch characters (LAUNCH_AUTHOR) on
-- their own family. The signed list names none of his PvP characters, so the PvP relays could take
-- no rules naming a newer version, and from the deadline on would have refused its clients.
local function RulesAuthor(name)
	return (type(ns.IsAuthorName) == "function" and ns.IsAuthorName(name) == true) or Relay.IsLaunchAuthor(name)
end
-- The author's client hands its rules to every relay it knows: at login and every RULES_EVERY, and
-- at once when they change (force).
function Relay.SendRules(force)
	if not Relay.On() or not RulesAuthor(ns.me) then return false end
	local r = ns.rdb and ns.rdb.relayRules
	if type(r) ~= "table" or (r.rev or 0) < 1 then return false end
	local now = Now()
	if not force and now - lastRulesSend < Relay.RULES_EVERY then return false end
	lastRulesSend = now
	wipe(rulesSent)
	ForwardRules(r, nil)
	return true
end
-- A relay asks the others for rules newer than its own: at login and every RULES_EVERY.
function Relay.AskRules(force)
	if not Relay.On() or not Relay.IsRelay(ns.me) then return false end
	local now = Now()
	if not force and now - lastRulesAsk < Relay.RULES_EVERY then return false end
	lastRulesAsk = now
	local ask, mine = ("RU~1~Q~%d"):format(Relay.Rules().rev), Lower(ns.ShortName(ns.me or ""))
	for _, name in ipairs(Relay.Names(false)) do
		local key = Lower(name)
		if key ~= mine and (offline[key] or 0) <= now then
			Quiet(name)
			ns.Comm.Whisper(name, ask, "relay rules ask " .. key, true)
		end
	end
	return true
end
-- The rules heard (we are a relay): an ask answered when ours are newer; a copy kept when newer.
function Relay.HandleRules(dist, sender, text)
	if dist ~= "WHISPER" or not Relay.On() then return false end
	local body = tostring(text):match("^RU~1~(.*)$")
	if not body or not Relay.IsRelay(ns.me) then return false end
	if not (Relay.IsRelay(sender) or RulesAuthor(sender)) then
		stats.dropped = stats.dropped + 1
		return false
	end
	local now = Now()
	local asked = body:match("^Q~(%d+)$")
	if asked then
		local r = Relay.Rules()
		if r.rev > 0 and r.rev > (tonumber(asked) or 0) then RulesTo(ns.ShortName(sender), r, "relay rules " .. Lower(ns.ShortName(sender))) end
		return true
	end
	local r = Relay.DecodeRules(body)
	if not r then
		stats.dropped = stats.dropped + 1
		return false
	end
	if r.rev <= Relay.Rules().rev then return true end -- (an older or the same revision: nothing changes)
	KeepRules(r, sender, now)
	ForwardRules(r, sender)
	return true
end
-- An epoch from "YYYY-MM-DD" (that day's 00:00 UTC), a number of seconds, or "now"; nil otherwise.
function Relay.Epoch(word, now)
	word = tostring(word or ""):lower()
	if word == "now" then return now or Now() end
	if word:match("^%d+$") and #word <= 12 then return tonumber(word) end
	local y, m, d = word:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not y then return nil end
	y, m, d = tonumber(y), tonumber(m), tonumber(d)
	if m < 1 or m > 12 or d < 1 or d > 31 then return nil end
	-- (Days from the civil date, the proleptic Gregorian calendar.)
	local yy = m <= 2 and y - 1 or y
	local era = math.floor(yy / 400)
	local yoe = yy - era * 400
	local doy = math.floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return (era * 146097 + doe - 719468) * 86400
end
-- The author's new revision: the requirement on or off, its deadline (an epoch), the versions
-- admitted (none named: the list in force stays). Kept and handed to the relays at once.
function Relay.SetRules(on, at, versions, now)
	now = now or Now()
	local held = Relay.Rules()
	local list = {}
	for i, v in ipairs(versions or held.versions) do
		if not Relay.VersionOf(v) then return false end
		list[i] = v
	end
	if type(at) ~= "number" or at < 0 or #list > Relay.MAX_RULE_VERSIONS then return false end
	local r = { rev = held.rev + 1, on = on ~= false, at = at, versions = list }
	if not KeepRules(r, ns.me, now) then return false end
	lastRulesSend = now
	wipe(rulesSent)
	ForwardRules(r, nil)
	return true, r
end
local function Day(t) return type(date) == "function" and date("!%Y-%m-%d %H:%M", t) or tostring(t) end
-- One line: the rules in force.
function Relay.RulesLine(now)
	now = now or Now()
	local r = Relay.Rules()
	local state = r.on == false and L.RELAY_RULES_PAUSED or (now >= r.at and L.RELAY_RULES_SINCE or L.RELAY_RULES_FROM):format(Day(r.at))
	local source = r.rev == 0 and L.RELAY_RULES_CODE or L.RELAY_RULES_FROM_AUTHOR:format(tostring(r.from or "?"), Day(r.t or 0))
	return L.RELAY_RULES_LINE:format(r.rev, source, state, #r.versions == 0 and L.RELAY_RULES_ANY or table.concat(r.versions, ", "))
end
-- The report of /oly relay admitted: whom this relay serves, whom it refused and why, the denied,
-- and the rules in force.
function Relay.Report(now)
	now = now or Now()
	local lines = { L.RELAY_REPORT_HEAD:format(tostring(ns.me), tostring(ns.VERSION), Relay.IsRelay(ns.me) and L.RELAY_REPORT_RELAY or L.RELAY_REPORT_NOT_RELAY),
		Relay.RulesLine(now) }
	local function Ago(t) return L.RELAY_AGO:format(math.floor(math.max(0, now - t) / 60)) end
	local shown = Relay.Presentations(now)
	lines[#lines + 1] = L.RELAY_REPORT_PRESENTED:format(#shown)
	for _, p in ipairs(shown) do lines[#lines + 1] = ("  %s  %s  %s"):format(p.name, p.v, Ago(p.t)) end
	local refusals = Relay.Refusals(now)
	lines[#lines + 1] = L.RELAY_REPORT_REFUSED:format(#refusals)
	for _, r in ipairs(refusals) do lines[#lines + 1] = ("  %s  %s  %s"):format(r.name, r.why, Ago(r.t)) end
	local names = {}
	for k in pairs(denied or {}) do names[#names + 1] = tostring(k) end
	table.sort(names)
	lines[#lines + 1] = L.RELAY_REPORT_DENIED:format(#names, table.concat(names, ", "))
	return table.concat(lines, "\n")
end
function Relay.ShowReport()
	local text = Relay.Report()
	local UI = ns.UI
	if type(UI) == "table" and type(UI.ShowCopy) == "function" then
		UI.ShowCopy(L.RELAY_REPORT_TITLE, text)
		return true
	end
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do ns.Print(line) end
	return true
end
-- /oly relay: "admitted" opens the report in the copy window; "rules" says the rules in force; the
-- author's "rules on|off [YYYY-MM-DD|epoch|now] [versions, comma-separated]" makes a new revision
-- and hands it to the relays.
function Relay.Slash(rest)
	local words = {}
	for w in tostring(rest or ""):gmatch("%S+") do words[#words + 1] = w end
	local cmd = (words[1] or ""):lower()
	if cmd == "admitted" then return Relay.ShowReport() end
	if cmd == "rules" and words[2] then
		if not RulesAuthor(ns.me) then
			ns.Print(L.RELAY_RULES_AUTHOR)
			return false
		end
		local on = words[2]:lower()
		local at = Relay.Rules().at -- (no date named: the deadline in force stays)
		if words[3] then at = Relay.Epoch(words[3]) end -- (a date that is none refuses the command)
		local versions
		if words[4] then
			versions = {}
			for v in (table.concat(words, ",", 4) .. ","):gmatch("([^,]*),") do
				if v ~= "" then versions[#versions + 1] = v end
			end
		end
		local ok, r = false, nil
		if (on == "on" or on == "off") and at then ok, r = Relay.SetRules(on == "on", at, versions) end
		if not ok then
			ns.Print(L.RELAY_USAGE)
			return false
		end
		ns.Print(L.RELAY_RULES_SET:format(r.rev))
		return true
	end
	if cmd == "rules" then
		ns.Print(Relay.RulesLine())
		return true
	end
	ns.Print(L.RELAY_USAGE)
	return false
end

-- The server's "No player named X is currently playing": a relay named is offline now.
function Relay.NotFound(text)
	-- (1.5.5) A secret line (a chat lockdown) is never read: 96 errors at Relay.lua:455 in a player's
	-- /oly bug of 11-09, 33 at Relay.lua:619 in another's.
	if type(text) ~= "string" or ns.Secret("relay not found", text) then return false end
	local T = ns.Treasury
	local pattern = type(T) == "table" and type(T.NotFoundPattern) == "function" and T.NotFoundPattern()
	local who = type(pattern) == "string" and type(text) == "string" and text:match(pattern)
	if type(who) ~= "string" then return false end
	who = who:gsub("^'", ""):gsub("'$", "")
	if not Relay.IsRelay(who) then return false end
	LeaveOut(who, "offline")
	return true
end

ns.Comm.Handle("RL", function(...) Relay.HandleIn(...) end)
ns.Comm.Handle("RM", function(...) Relay.HandleRelayed(...) end)
ns.Comm.Handle("RG", function(...) Relay.HandleGuild(...) end)
ns.Comm.Handle("RY", function(...) Relay.HandleAck(...) end)
ns.Comm.Handle("RX", function(...) Relay.HandleAcross(...) end)
ns.Comm.Handle("RW", function(...) Relay.HandleVerify(...) end)
ns.Comm.Handle("RI", function(...) Relay.HandlePresent(...) end) -- (1.5.4: a client's presentation)
ns.Comm.Handle("RU", function(...) Relay.HandleRules(...) end) -- (1.5.4: the relay rules)
ns.Comm.Handle("RJ", function(...) Relay.HandleMesh(...) end) -- (1.5.5: the mesh between the signed relays)
ns.Comm.RelayPieces({ RL = true, RM = true, RG = true, RX = true, RW = true, RU = true })

-- (1.4.6, the dev's ask) The server's "No player named X is currently playing" for a relay or a
-- reporter the relay whispered: out of the chat for good, not for a window (Accord.Quiet's ten
-- seconds left the login's first sweep in sight). Read all the same (NotFound, the event).
local function NotFoundName(text)
	-- (1.5.5) A secret line (Forever's chat locked down) goes on unread: the chat frame calls this
	-- filter itself, in the game's chat code, outside the event guard in Core.lua.
	if type(text) ~= "string" or ns.Secret("relay quiet line", text) then return nil end
	local T = ns.Treasury
	local pattern = type(T) == "table" and type(T.NotFoundPattern) == "function" and T.NotFoundPattern()
	local who = type(pattern) == "string" and type(text) == "string" and text:match(pattern)
	if type(who) ~= "string" then return nil end
	return (who:gsub("^'", ""):gsub("'$", ""))
end
function Relay.QuietLine(_, _, text) -- gp:system-filters
	if not ns.Gate.Allowed("system-filters") or not Relay.On() then return false end
	local who = NotFoundName(text)
	if not who then return false end
	if Relay.IsRelay(who) then return true end
	local key = ns.ShortName(who):lower()
	for _, r in pairs(reporters) do
		if ns.ShortName(r.name or ""):lower() == key then return true end
	end
	return false
end
local filtering
local function QuietLines() -- gp:system-filters!hook
	if filtering or not ns.Gate.Allowed("system-filters") then return end
	local add = rawget(_G, "ChatFrame_AddMessageEventFilter") -- gp:system-filters
	if type(add) ~= "function" then
		local U = rawget(_G, "ChatFrameUtil") -- gp:system-filters
		add = type(U) == "table" and rawget(U, "AddMessageEventFilter") or nil -- gp:system-filters
	end
	if type(add) ~= "function" then return end
	filtering = true
	pcall(add, "CHAT_MSG_SYSTEM", Relay.QuietLine) -- gp:system-filters
end
Relay.QuietLines = QuietLines

-- (1.5.0) A relay's own global census snapshot to its reporters every GLOBAL_EVERY (it hears every
-- guild's report; Data.SendGlobalCensus sends it "on the channel", so by this relay to every
-- reporter, keyed: the latest alone waits in the queue).
local lastGlobal = -math.huge
function Relay.SendGlobal(force)
	if not Relay.On() or not Relay.IsRelay(ns.me) then return false end
	local now = Now()
	if not force and now - lastGlobal < Relay.GLOBAL_EVERY then return false end
	local D = ns.Data
	if type(D) ~= "table" or type(D.SendGlobalCensus) ~= "function" then return false end
	lastGlobal = now
	return D.SendGlobalCensus() == true
end

ns.On("LOGIN", function()
	if not Relay.On() then return end
	pcall(ns.RegisterEvent, "CHAT_MSG_SYSTEM", function(text) ns.SafeCall("relay not found", Relay.NotFound, text) end)
	QuietLines()
	if ns.Every then ns.Every(Relay.GLOBAL_EVERY, "relay global census", function() ns.SafeCall("relay global", Relay.SendGlobal) end) end
	-- (1.5.5) The mesh between the signed relays (Relay.Mesh asks each time whether this client is
	-- one: the signed list may arrive after the login).
	if ns.After then ns.After(10, "relay mesh", function() ns.SafeCall("relay mesh", Relay.Mesh) end) end
	if ns.Every then ns.Every(Relay.MESH_EVERY, "relay mesh", Relay.Mesh) end
	-- (1.5.4) The relay rules: asked of the other relays, and handed to them by the author's client.
	if Relay.IsRelay(ns.me) then
		ns.SafeCall("relay rules", Relay.AskRules, true)
		ns.SafeCall("relay rules", Relay.SendRules, true)
		if ns.Every then
			ns.Every(Relay.RULES_EVERY, "relay rules", function()
				ns.SafeCall("relay rules", Relay.AskRules)
				ns.SafeCall("relay rules", Relay.SendRules)
			end)
		end
	end
end)

-- (1.5.5) What the relay's lanes share (no behaviour of its own): the hop a word came by ("L" RL at a
-- relay, "M" RM, "X" RX, "W" RW, "G" RG, "T" the tree, "O" a fallback relay), the parts of the relay
-- the tree and the fallback relays reuse, and the stubs each lane fills.
function Relay.Hop() return hop, hopSender end
WithHop = function(h, sender, fn, ...)
	local ph, ps = hop, hopSender
	hop, hopSender = h, sender
	local ok, res = pcall(fn, ...)
	hop, hopSender = ph, ps
	if not ok then error(res, 0) end
	return res
end
function Relay.TakeVia(h, sender, origin, text, logged) return WithHop(h, sender, Deliver, origin, text, logged) end
function Relay.Take(origin, text, logged) return Deliver(origin, text, logged) end
function Relay.HandOn(flag, origin, text) return ToGuild(flag, origin, text) end
Relay.Envelope = Envelope
function Relay.SetBatches(flag, origin, set, kind) return SetBatches(flag, origin, set, kind) end
-- A whole transfer to `name` through the drip, keyed `word` (a newer one takes a waiting one's place).
-- opts.across: to a relay; opts.front: right after the transfer in flight and the front ones before it;
-- opts.census (1.5.9): a census transfer (CensusTransfer: the tree's).
function Relay.DripTo(name, word, batches, opts)
	if type(name) ~= "string" or name == "" or type(word) ~= "string" or type(batches) ~= "table" or #batches == 0 then return false end
	opts = type(opts) == "table" and opts or {}
	if not opts.front then
		DripBatches(name, word, batches, nil, opts.across, opts.census == true)
		return true
	end
	for i, d in ipairs(drip) do
		if d.name == name and d.word == word and not d.started then table.remove(drip, i) break end
	end
	local at = 1
	while drip[at] and (drip[at].started or drip[at].front) do at = at + 1 end
	table.insert(drip, at, { name = name, word = word, batches = batches, index = 1, across = opts.across, front = true,
		census = opts.census == true or nil, at = Now() })
	Drip()
	return true
end
-- Whether a transfer to `name` keyed `word` is in the drip, waiting or in flight.
function Relay.Dripping(name, word)
	for _, d in ipairs(drip) do
		if d.name == name and d.word == word then return true end
	end
	return false
end
-- (1.5.9's review) How long the census snapshot that has waited longest in the drip for a registrant (the
-- star, not the tree's words) has waited, not begun; 0 when none waits (RelayTree.lua's StarFirst).
function Relay.StarWaiting(now)
	now = now or Now()
	local most = 0
	for _, d in ipairs(drip) do
		if d.word == "census snapshot" and not d.started then most = math.max(most, now - (d.at or now)) end
	end
	return most
end
-- (1.5.9) The drip for /oly bug, without a name: the transfers waiting (not begun), how many of them are
-- census transfers (CensusTransfer), and the longest any of them, and any census one, has waited since
-- it was queued (a census transfer goes ahead of one waiting for free room: the front is not the oldest).
-- (1.5.9's review) And the transfer in flight, the one that can hold all the others: census or not, its
-- batch, of how many, and how long since that batch was handed over (flight; nil when none is).
function Relay.DripStats()
	local now, out = Now(), { waiting = 0, census = 0 }
	for _, d in ipairs(drip) do
		if not d.started then
			local waited = math.max(0, now - (d.at or now))
			out.waiting = out.waiting + 1
			out.oldest = math.max(out.oldest or 0, waited)
			if d.census then out.census, out.oldestCensus = out.census + 1, math.max(out.oldestCensus or 0, waited) end
		elseif not out.flight then
			out.flight = { census = d.census == true, batch = d.index, of = #d.batches, since = math.max(0, now - (d.t or d.at or now)) }
		end
	end
	return out
end
function Relay.FirstHand() return hop == "L" end
function Relay.ViaProvisional() return hop == "O" end
-- (1.5.5) Whether the hop a word comes by vouches for its origin: never a provisional relay's (O); a
-- relay's (M, X) or the tree's (T) only when the client that whispered it is a signed relay (an
-- unsigned Treasurer code pin carries words, it proves nothing about who said them); any other hop,
-- and none (a direct call, off Forever), as before.
function Relay.HopTrusted()
	if hop == "O" then return false end
	if hop == "M" or hop == "X" or hop == "T" then return hopSender ~= nil and Relay.IsSignedRelay(hopSender) end
	return true
end
-- (1.5.5) A signed relay: a name of Relay.Names(true) that the council's list, the author's characters,
-- the King's, the launch pins or a Treasurer the signed list names give; the code's Treasurer pins
-- alone make a relay, not a signed one (they are no mesh peer, and no RX is taken from them).
function Relay.IsSignedRelay(name)
	local key = Lower(ns.ShortName(name or ""))
	if key == "" then return false end
	for _, n in ipairs(Relay.Names(true, true)) do if n:lower() == key then return true end end
	return false
end
function Relay.MeshPeer(name)
	local key = Lower(ns.ShortName(name or ""))
	return key ~= "" and mesh.Fresh(key, Now()) and Relay.IsSignedRelay(name)
end
function Relay.TreeCapable(name)
	local T = ns.RelayTree
	return type(T) == "table" and not T.missing and type(T.Capable) == "function" and T.Capable(name) == true
end
function Relay.ServingProvisional()
	local F = ns.RelayFallback
	return type(F) == "table" and not F.missing and type(F.Serving) == "function" and F.Serving() == true
end
function Relay.InFallback()
	local F = ns.RelayFallback
	return type(F) == "table" and not F.missing and type(F.Active) == "function" and F.Active() == true
end
-- Whether version v is floor or later, numbers compared ("a.b.c-test.n" as a.b.c); false for no version.
function Relay.AtLeast(v, floor)
	local function Parts(s)
		s = Relay.VersionOf(s)
		if not s then return nil end
		local out = {}
		for d in (s:match("^(%d+%.%d+%.%d+)%-test%.%d+$") or s):gmatch("%d+") do out[#out + 1] = tonumber(d) end
		return out
	end
	local a, b = Parts(v), Parts(floor)
	if not a or not b then return false end
	for i = 1, math.max(#a, #b) do
		local x, y = a[i] or 0, b[i] or 0
		if x ~= y then return x > y end
	end
	return true
end
-- Each fresh registration here: { guild, name, v, t }, by name.
function Relay.Reporters()
	local now, out = Now(), {}
	for g, r in pairs(reporters) do
		if now - r.t <= Relay.REPORTER_FOR then out[#out + 1] = { guild = r.guild or g, name = r.name, v = r.v, t = r.t } end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end
function Relay.PinnedRelay() return nil end -- (lane mesh fills it, with RB)
Relay.LAUNCH_AUTHOR = { ForeverPvE = { Relay.LAUNCH_PINS.ForeverPvE[1] }, ForeverPvP = Relay.LAUNCH_PINS.ForeverPvP }
-- Whether `name` is one of the author's launch characters of its own Forever family.
function Relay.IsLaunchAuthor(name)
	if type(name) ~= "string" or name == "" or type(ns.ForeverFamily) ~= "function" then return false end
	local full = ns.FullName(name)
	local family = ns.ForeverFamily(ns.RealmOf(full) or "")
	local list = family and Relay.LAUNCH_AUTHOR[family]
	if type(list) ~= "table" then return false end
	local key = Lower(ns.ShortName(full))
	for _, n in ipairs(list) do
		if type(n) == "string" and Lower(ns.ShortName(n)) == key then return true end
	end
	return false
end
Relay.ResetHooks = {} -- (each lane appends its reset: Relay.Reset calls them last)
Relay.ResetHooks[#Relay.ResetHooks + 1] = ForgetCensus -- (lane tree: the census sets held, ToReporters)

-- (1.5.5) The mesh's round (on a signed relay's client: 10 s after login, then every MESH_EVERY):
-- every other signed relay not left out is pinged (Ping: one answered within DEAD_FOR is not), and
-- each one answered is told RJ; those this round's pings reach are told PING_WAIT later.
function mesh.Join(name, now)
	local key, regs, tree = name:lower(), 0, 0
	for _, r in pairs(reporters) do
		if now - r.t <= Relay.REPORTER_FOR then
			regs = regs + 1
			if Relay.TreeCapable(r.name) then tree = tree + 1 end
		end
	end
	mesh.sent[key] = now
	mesh.n.rjOut = (mesh.n.rjOut or 0) + 1
	Quiet(name)
	ns.Comm.Whisper(name, ("RJ~1~%d~%d"):format(regs, tree), "relay rj " .. key, false)
end
function mesh.JoinAnswered()
	if not Relay.On() or not Relay.IsSignedRelay(ns.me) then return end
	local now, mine = Now(), Lower(ns.ShortName(ns.me or ""))
	for _, n in ipairs(Relay.Names(false, true)) do
		local key = n:lower()
		if key ~= mine and (offline[key] or 0) <= now and now - (verified[key] or -math.huge) < Relay.VERIFIED_FOR
			and now - (mesh.sent[key] or -math.huge) >= Relay.MESH_EVERY / 2 then
			mesh.Join(n, now)
		end
	end
end
function Relay.Mesh()
	if not Relay.On() or not Relay.IsSignedRelay(ns.me) then return false end
	local now, mine = Now(), Lower(ns.ShortName(ns.me or ""))
	mesh.n.rounds = (mesh.n.rounds or 0) + 1
	for _, n in ipairs(Relay.Names(false, true)) do
		if n:lower() ~= mine and (offline[n:lower()] or 0) <= now then Ping(n) end
	end
	mesh.JoinAnswered()
	ns.After(Relay.PING_WAIT, "relay mesh", function() ns.SafeCall("relay mesh", mesh.JoinAnswered) end)
	return true
end
-- RJ heard (we are a signed relay): the sender, a signed relay, is of the mesh. It answered (verified)
-- and joined (seen); it is told RJ in turn when we have not told it within half a round, so two
-- relays mesh within seconds of the first RJ, not a whole round later.
function Relay.HandleMesh(dist, sender, text)
	if dist ~= "WHISPER" or not Relay.On() then return false end
	local regs, tree = tostring(text):match("^RJ~1~(%d+)~(%d+)")
	if not regs then return false end
	local key, now = Lower(ns.ShortName(sender or "")), Now()
	if key == "" or key == Lower(ns.ShortName(ns.me or "")) or not Relay.IsSignedRelay(ns.me) or not Relay.IsSignedRelay(sender) then
		stats.dropped = stats.dropped + 1
		return false
	end
	if not mesh.Fresh(key, now) then ns.Log("relay: %s joins the mesh (%s registrants, %s tree-capable)", tostring(sender), regs, tree) end
	mesh.n.rjIn = (mesh.n.rjIn or 0) + 1
	mesh.seen[key], verified[key], offline[key], pinged[key] = now, now, nil, nil
	mesh.peers[key] = { regs = math.min(tonumber(regs) or 0, 99999), tree = math.min(tonumber(tree) or 0, 99999) }
	if now - (mesh.sent[key] or -math.huge) >= Relay.MESH_EVERY / 2 then mesh.Join(ns.ShortName(sender), now) end
	return true
end

-- (1.5.5) /oly bug's relay lines (the debug section asks this alone): the relay, the mesh and the
-- queue, then the tree's, the census's and the fallback's counters, each asked under pcall (a module
-- a client lacks, or one that fails, leaves its line saying so), all of it within maxBytes (1500),
-- the most useful first. A table becomes "key=value" words, sorted, nested ones in braces.
function mesh.Flat(v, depth)
	depth = depth or 0
	if type(v) == "number" then return v == math.floor(v) and tostring(v) or ("%.1f"):format(v) end
	if type(v) == "string" then return ns.Cut(v:gsub("[\r\n]", " "), 48) end
	if type(v) ~= "table" then return tostring(v) end
	if depth >= 3 then return "{...}" end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		if type(a) ~= type(b) then return type(a) < type(b) end
		if type(a) == "number" then return a < b end
		return tostring(a) < tostring(b)
	end)
	local out = {}
	for _, k in ipairs(keys) do
		if #out >= 64 then out[#out + 1] = "..." break end
		local item = mesh.Flat(v[k], depth + 1)
		out[#out + 1] = type(k) == "number" and item or (tostring(k) .. "=" .. item)
	end
	if depth == 0 then return #out > 0 and table.concat(out, " ") or "-" end
	return "{" .. table.concat(out, ",") .. "}"
end
function mesh.Module(M, fn)
	if type(M) ~= "table" then return "not loaded" end
	if M.missing then return "not loaded (a new file: the game must restart)" end
	if type(M[fn]) ~= "function" then return "none" end
	return mesh.Flat(M[fn]())
end
function Relay.BugLines(maxBytes)
	maxBytes = math.max(0, math.floor(tonumber(maxBytes) or 1500))
	local out, used, now = {}, 0, Now()
	local function Age(t) return t and ("%ds"):format(math.max(0, math.floor(now - t))) or "-" end
	local function Part(label, fn)
		local ok, text = pcall(fn)
		local line = (label .. ": " .. (ok and tostring(text) or ("error " .. tostring(text)))):gsub("[\r\n]", " ")
		local room = maxBytes - used - 1 -- (a line and its newline)
		if room < #label + 6 then return end
		if #line > room then line = ns.Cut(line, room - 3) .. "..." end
		out[#out + 1], used = line, used + #line + 1
	end
	Part("relay", function()
		local s, live, answered, mine = Relay.Stats(), 0, 0, Lower(ns.ShortName(ns.me or ""))
		for _, n in ipairs(Relay.Names(true)) do
			local key = n:lower()
			if key ~= mine and (offline[key] or 0) <= now then
				live = live + 1
				if now - (verified[key] or -math.huge) < Relay.VERIFIED_FOR then answered = answered + 1 end
			end
		end
		return ("pick=%s sure=%s live=%d answered=%d signed=%s regs=%d out=%d fwd=%d dlv=%d drop=%d dead=%d trickled=%d kept=%d across=%d verifyAcross=%d"):format(
			tostring(s.relay or "-"), s.sure and "y" or "n", live, answered, Relay.IsSignedRelay(ns.me) and "y" or "n",
			s.reporters or 0, s.out or 0, s.forwarded or 0, s.delivered or 0, s.dropped or 0, s.dead or 0, s.trickled or 0,
			s.kept or 0, s.across or 0, s.verifyAcross or 0)
	end)
	Part("mesh", function()
		local n, regs, tree = mesh.n, 0, 0
		for _, r in pairs(reporters) do
			if now - r.t <= Relay.REPORTER_FOR then
				regs = regs + 1
				if Relay.TreeCapable(r.name) then tree = tree + 1 end
			end
		end
		local parts = { ("me %d/%d rounds=%d rj=%d/%d staff=%d/%d cgHeld=%d rrKept=%d"):format(regs, tree, n.rounds or 0,
			n.rjOut or 0, n.rjIn or 0, n.staffOut or 0, n.staffIn or 0, n.cgHeld or 0, n.rrKept or 0) }
		local mine = Lower(ns.ShortName(ns.me or ""))
		for _, name in ipairs(Relay.Names(false, true)) do
			local key = name:lower()
			if key ~= mine and (verified[key] or mesh.seen[key]) then
				local p = mesh.peers[key]
				parts[#parts + 1] = ("%s v=%s j=%s %s%s"):format(name, Age(verified[key]), Age(mesh.seen[key]),
					p and (p.regs .. "/" .. p.tree) or "-/-", mesh.Fresh(key, now) and "" or " out")
			end
		end
		return table.concat(parts, "; ")
	end)
	Part("queue", function()
		local waiting, across, flight = 0, 0, nil
		for _, d in ipairs(drip) do
			if d.started then flight = d else waiting = waiting + 1 end
			if d.across then across = across + 1 end
		end
		return ("size=%d room=%d drip=%d waiting (%d across)%s"):format(ns.Comm.QueueSize(), ns.Comm.QueueRoom(), waiting, across,
			flight and (" sending %s to %s %d/%d"):format(tostring(flight.word), tostring(flight.name), flight.index, #flight.batches) or "")
	end)
	Part("tree", function() return mesh.Module(ns.RelayTree, "Stats") end)
	Part("census", function() return mesh.Module(ns.Data, "CensusStats") end)
	Part("fallback", function() return mesh.Module(ns.RelayFallback, "Stats") end)
	return out
end
Relay.ResetHooks[#Relay.ResetHooks + 1] = function() -- (the mesh's)
	wipe(mesh.seen); wipe(mesh.peers); wipe(mesh.sent); wipe(mesh.cg); wipe(mesh.cgTurn); wipe(mesh.plain); wipe(mesh.n)
	mesh.census = nil
end

-- Tests: a clean slate.
function Relay.Reset()
	wipe(offline); wipe(verified); wipe(pinged); wipe(reporters); wipe(seen); wipe(pending); wipe(budget)
	seenCount, lastRegister, holding, flushing, lastGlobal = 0, -math.huge, false, false, -math.huge
	lastVerifyAsk = -math.huge
	wipe(presentedMem); wipe(refused); wipe(relayVersion); wipe(presentedTo); wipe(rulesSent) -- (1.5.4)
	if type(ns.rdb) == "table" then ns.rdb.relayPresented = nil end
	denied, lastRulesAsk, lastRulesSend, listed, listedFrom = nil, -math.huge, -math.huge, nil, nil
	wipe(snapshotTransfers); wipe(crownSent); wipe(kingSent); wipe(crownLayer); wipe(grantSent); wipe(presented)
	crownBucket.tokens, crownBucket.at = 0, -math.huge
	wipe(sets); wipe(drip)
	wipe(listOrigins); wipe(Origins()); wipe(listShares); wipe(listSets)
	dripBusy, dripping = false, false
	dripBucket.tokens, dripBucket.at, dripOwed = nil, -math.huge, 0 -- (1.5.9's review: the drip's pace)
	wipe(chatQ); chatFirst, chatLast, chatInflight, chatFeeding = 1, 0, 0, false -- (1.5.5: the chat lane)
	chatWaitUntil, chatTimer, chatBucket.tokens, chatBucket.at = -math.huge, false, Relay.CHAT_BURST, -math.huge
	for k in pairs(stats) do stats[k] = 0 end
	hop, hopSender = nil, nil -- (1.5.5)
	for _, fn in ipairs(Relay.ResetHooks) do fn() end
end
