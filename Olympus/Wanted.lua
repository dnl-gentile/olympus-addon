local ADDON, ns = ...
local L = ns.L

-- Horde Most Wanted (1.2.3, Daniel: "that list should never have existed"): there is no list to
-- be put on first. A Horde player enters by himself the moment an Olympus member's own client
-- observes him killing that member (the member's own death recap) or being killed by that member
-- (the member's own killing blow, PARTY_KILL), and the kill or death counts at once: a bounty on
-- him, or a claim of his open bounty for the member's Slayers row. The faction is proven by this
-- client, never guessed or typed: a Horde unit it sees (or saw within a minute), else the GUID's
-- own race as the game gives it (GetPlayerInfoByGUID); a pet, a creature, the environment, an
-- Alliance player (a free-for-all zone), an instance (a battleground, an arena) and a hidden
-- (secret) payload never count.
--
-- Each own row goes at once to the Olympus channel (WK, the section "Shared kills and deaths"
-- below), and every member's client applies it to its own Wanted list straight away: no Send, no
-- review, no accept. A receiver takes it only from a verified member (its own guild's roster, or
-- a guild rank it can verify), about that member's own death or killing blow (the Olympian side is
-- the server-stamped sender; his GUID only where this client can prove it is his), of this realm
-- group and faction, fresh, once, within per-sender and per-Horde-player rate limits and caps. A
-- reviewer (the King, a signed High Councillor or the author) relays what his client admitted, so
-- members of other guilds hear it too, and answers a late login's catch-up ask (W4) with the
-- recent rows. A reviewer can only take an abusive entry off afterwards, or void one row (WV): it
-- stops counting on every client, and a later event does not bring the entry back.
--
-- A full list never refuses a Horde player: the least active entry makes room (Share.MakeRoom),
-- and the ones taken off are kept off apart, taking no place (MAX_REMOVED). A Horde player is his
-- GUID: rows find his entry by it alone (ResolveTarget), and his name, only a label, is the one the
-- game gives for that GUID wherever this client can look it up (Share.HordeOf, Share.Take).
--
-- The signed top three (WY) is the publisher's own Slayers board, by verified GUID: GUIDs and
-- scores only, never victims, locations or rows. It is signed with the existing Arena account key
-- and accepted only when the server-stamped sender is currently the King, a signed High
-- Councillor, or the author. The receivers keep the last word they accepted live, and after a
-- reload check it again (its signature, the key pinned for its issuer, its expiry, and that its
-- issuer still holds the role) before it shows any frame. A saved word is only ever used by the
-- client that heard it. W4 asks for catch-up; a real reviewer may relay an unchanged signed word
-- in W5. A receiver must already have independently pinned that issuer's key from a verified
-- direct word: a relay never supplies a first-use key or key rotation. Editing a word's rows
-- breaks its signature, and a word under another key than the one pinned for its issuer is
-- refused; whoever rewrites both in his own saved data changes only what his own client shows,
-- as editing the addon itself would.
--
-- Sightings (the section "Most Wanted sightings" below): a Horde player this client saw,
-- where its own player stood then, on its map for 15 minutes and whispered to the one reviewer
-- the member chose. Off until the member's Yes; never on the channel, never in an instance.
--
-- The bounty (1.2.3, Daniel's weights: the section "The bounty" below): a death adds the victim's
-- office and level to the Horde player's bounty, a kill pays a small level base and his whole bounty,
-- a member who kills his own killer gets more. Each own row freezes what it was worth where it
-- was observed (the office, both levels) and carries it on the channel, and every client scores
-- the same rows with the same function, so every client counts the same points. At each login
-- the deaths the game's death recaps still hold this session count too, once, and the member is
-- told so in one window. (In this file, not a new one: a file the TOC adds loads only after the
-- game restarts, and a restart empties the death recaps; this one loads at the first /reload.)
local Wanted = {}
ns.Wanted = Wanted

Wanted.VERSION = 1
-- The facts on WK rows do not change with the scoring rule. Local derived Slayer totals and the
-- signed WY board do: keep their version separate so a mixed-version realm never compares an old
-- 2 x level total with the current, bounty-led total.
Wanted.SCORE_VERSION = 2
-- The Horde players held on the list (the most recently active: a full list makes room by itself,
-- Share.MakeRoom, and never refuses one), and apart from them the ones a reviewer took off, kept
-- off (the oldest removal goes first).
Wanted.MAX_TARGETS = 200
Wanted.MAX_REMOVED = 512
Wanted.MAX_SLAYERS = 500
Wanted.MAX_EVIDENCE = 512
Wanted.MAX_SEEN = 2048
Wanted.MAX_VICTIMS = 32
Wanted.MAX_CLAIMS = 30
Wanted.MAX_AUDIT = 100
Wanted.MAX_MONTHS = 24
Wanted.MAX_POINTS = 100000
Wanted.LIST_FIRST = 5
Wanted.LIST_PAGE = 10
Wanted.RATE_MAX = 20
Wanted.RATE_WINDOW = 60
Wanted.GLOBAL_BORDERS_ACTIVE = true
Wanted.GLOBAL_ROWS = 3
-- A signed word holds for a month unless a newer one replaces it, its issuer loses the role or
-- he revokes it (was 30 minutes, for one session). Publishing again starts a new month.
Wanted.GLOBAL_LIFE = 31 * 86400
Wanted.GLOBAL_SKEW = 2 * 60
-- The publisher repeats his word for late logins: 6 times 5 minutes apart, then every 30
-- minutes while he stays online, and once 90 seconds after he logs in. Never a new expiry.
Wanted.GLOBAL_BURST = 6
Wanted.GLOBAL_BURST_GAP = 5 * 60
Wanted.GLOBAL_REPEAT_EVERY = 30 * 60
Wanted.GLOBAL_LOGIN_REPEAT = 90
Wanted.GLOBAL_ASK_FIRST, Wanted.GLOBAL_ASK_GAP, Wanted.GLOBAL_ASK_TRIES = 45, 300, 3
Wanted.GLOBAL_DIRECT_PINS_MAX = 64
-- One death has one killer: rows naming the same victim this close together describe one death.
Wanted.DEATH_WINDOW = 5
-- Shared kills and deaths (WK, WV: see "Shared kills and deaths" below).
Wanted.SHARE_AGE = 7 * 86400     -- a row heard older than this is refused (a live row is seconds old)
Wanted.SHARE_RATE_MAX = 8        -- rows taken from one member a window...
Wanted.SHARE_RATE_WINDOW = 60    -- ...of this many seconds
Wanted.SHARE_TARGET_MAX = 20     -- rows taken about one Horde player a window...
Wanted.SHARE_TARGET_WINDOW = 300 -- ...of this many seconds, from everyone
Wanted.SHARE_DAY_MAX = 60        -- rows taken from one member a day (SHARE_DAY): a flood of made-up deaths
Wanted.SHARE_DAY = 86400
Wanted.SHARE_SENDERS_MAX = 1024  -- members (and Horde players) counted at once in a window
Wanted.SHARE_DAY_SENDERS_MAX = 8192 -- members counted at once in a day
Wanted.SHARE_RELAY_MAX = 40      -- rows taken from one reviewer's relays a window (SHARE_RATE_WINDOW)
Wanted.SHARE_ROOM = 20           -- a relay or a catch-up answer leaves this much of Comm's queue free
Wanted.SHARE_CATCH_ROWS = 24     -- rows one catch-up answer carries at most (the newest)
Wanted.SHARE_CATCH_MARKS = 8     -- and removals, and voided rows, each
Wanted.SHARE_RELAY_DELAY = 3     -- a reviewer relays a row this long after he took it (and a part of 8 s his own)
Wanted.SHARE_RESEND_FIRST = 60   -- this client's own rows the channel did not take go again this long after login...
Wanted.SHARE_RESEND_EVERY = 300  -- ...then this often...
Wanted.SHARE_RESEND_MAX = 4      -- ...this many at a time
Wanted.SHARE_HEARD_MAX = 512     -- relayed row ids remembered (a reviewer relays each once)
Wanted.VOIDS_MAX = 256           -- voided rows remembered, so one heard later is refused too
Wanted.DIAG_MAX = 40             -- this session's captures and refusals /oly wanted status lists
Wanted.GLOBAL_MAX_SEQ = 2147483647
Wanted.GLOBAL_MAX_EPOCH = 2147483647
Wanted.GLOBAL_MAX_VERIFY = 8
-- Sightings (see "Most Wanted sightings" below).
Wanted.SIGHT_TTL = 15 * 60       -- a pin shows this long after the sighting
Wanted.SIGHT_GAP = 180           -- this client records one Horde player once this often on one map
Wanted.SIGHT_GRID = 5            -- the observer's spot, in thousandths of the map rounded to 5 (0.5%)
Wanted.SIGHT_SEND_MAX = 3        -- sightings this client sends a window...
Wanted.SIGHT_WINDOW = 60         -- ...of this many seconds (the rest stay on its own map)
Wanted.SIGHT_QUEUE_MAX = 8       -- sighting whispers waiting in Comm, at most
Wanted.SIGHT_QUEUE_TTL = 30      -- a sighting that waited this long in Comm is not sent
Wanted.SIGHT_RECV_MAX = 3        -- sightings a reviewer takes from one sender a window...
Wanted.SIGHT_INTAKE_MAX = 30     -- ...and from everyone
Wanted.SIGHT_SENDERS_MAX = 128   -- senders a reviewer counts at once
Wanted.SIGHT_PINS = 48           -- pins held at most (the newest)
Wanted.SIGHT_SEEN_MAX = 512      -- sighting ids remembered (replays)
Wanted.SIGHT_OWN_MAX = 256       -- Horde players this client remembers seeing (SIGHT_GAP)
Wanted.SIGHT_LAYER_FRESH = 120   -- this client's layer, when Layers saw it this recently
Wanted.SIGHT_TICK = 15           -- pins expire (and follow the interface style) on this beat
Wanted.SIGHT_QUIET = 5           -- the server's "No player named" for a sighting whisper, kept out of chat this long
Wanted.SIGHT_BADGE = 16          -- the world map's badge
Wanted.SIGHT_MINI = 12           -- the minimap's
Wanted.HISTORY_BADGE = 22        -- a dated zone-only marker, deliberately unlike a fresh nearby pin
Wanted.HISTORY_TIP_MAX = 8       -- names on one zone marker before its summary line
Wanted.REVIEWER_FIRST = 45       -- a reviewer says he takes sightings this long after login...
Wanted.REVIEWER_EVERY = 5 * 60   -- ...then this often...
Wanted.REVIEWER_FOR = 11 * 60    -- ...and is sent them for this long after the last time
Wanted.REVIEWERS_MAX = 32
Wanted.ICON_PATHS = {
	"Interface\\Icons\\INV_Misc_Tournaments_banner_Orc",
	"Interface\\Icons\\INV_BannerPVP_01",
	"Interface\\Icons\\INV_Misc_QuestionMark",
}

local stats = { accepted = 0, replay = 0, refused = 0, corrected = 0, checkpointed = 0, conflict = 0,
	reviewed = 0, globalAccepted = 0, globalRefused = 0, globalReplay = 0, globalRestored = 0,
	sightSeen = 0, sightRepeat = 0, sightRate = 0, sightSent = 0, sightCancelled = 0, sightTaken = 0,
	sightRefused = 0, sightReplay = 0, sightExpired = 0, sightWithdrawn = 0, leases = 0 }
local rate = {}
local mode, opened = "list", nil
-- RankingRules belongs to this exact addon namespace. `rawget` deliberately ignores an inherited
-- test/client namespace: loading Wanted for a second simulated client must not replace the real
-- client's rule specification with callbacks closed over the other client.
Wanted.Rules = rawget(ns, "RankingRules")
-- The word shown now. After a reload it comes back only through RestoreGlobal, which checks the
-- saved copy again; the copy alone (or any other saved field) never shows a frame.
local authenticatedGlobal
local globalFloor, publisherHeads = nil, {}
local pendingGlobal, pendingGlobalCount = {}, 0
-- The saved word being checked again after a load (its floor and pin hold meanwhile), and each
-- saved text's signature, checked once a session.
local restoring, restoreChecked = nil, {}
local publishedGlobal
Wanted.globalCatch = { asked = -math.huge, replied = -math.huge, generation = 0 }
Wanted.listShown = { wanted = Wanted.LIST_FIRST, month = Wanted.LIST_FIRST, all = Wanted.LIST_FIRST }
local watchingNotFound = false
-- 1.2.3: the shared kills and deaths' helpers and this session's state (the section "Shared kills
-- and deaths" below; a table, as Wanted.lua's main chunk is at Lua's 200 locals): the senders'
-- and Horde players' rate windows, the rows a reviewer heard relayed (he relays each once), and
-- this session's captures and refusals for /oly wanted status.
local Share = { rates = {}, days = {}, targets = {}, relayed = {}, relayedOrder = {},
	log = {}, why = {}, counts = {}, catchReplied = -math.huge, catchHeard = -math.huge }
-- 1.2.3: the bounty's weights, its scoring and the earlier deaths (the section "The bounty" below;
-- a table, as Share is), and this session's state of the earlier deaths' reader and its notice.
local Bounty = { session = {} }
Wanted.Bounty = Bounty -- (tests, /oly wanted status)
local scoreMigrationFrame
local ScheduleGlobalRepeat
-- Sightings, this session's only (nothing of them is saved): the pins ([Horde GUID] = the newest
-- sighting of him), their frames, the ids taken (replays), this client's own last sighting of each
-- Horde player (SIGHT_GAP), when its last ones went (SIGHT_SEND_MAX), its whispers waiting in Comm,
-- the reviewers they reached (a No takes them back), the reviewers whose "No player named" it
-- keeps out of chat for a moment, each sender's count and everyone's (a reviewer's intake), and
-- the reviewers heard taking them.
local pins, pinFrames, spareFrames, historyFocus = {}, {}, {}, nil
local sightSeen, sightSeenOrder = {}, {}
local ownSeen, ownSeenCount = {}, 0
local sightSends = {}
local sightJobs, sightJobCount = {}, 0
-- (told.by: [folded reviewer] = { name, target }; told.quiet: [lowered name] = until)
local told = { by = {}, quiet = {}, filter = false }
local sightFrom, sightFromCount, sightIntake = {}, 0, { at = 0, n = 0 }
local reviewers, reviewerCount = {}, 0
local leaseGen, leaseAt = 0, nil
local pinTicker = false
local SightingNotFound
local deathSerial = 0
local knownHorde = {} -- this session's verified unit identities, never addon messages

local function Clock()
	local D = ns.Data
	return (D and D.ServerTime and D.ServerTime()) or ns.Now()
end

local function Secret(...)
	if type(issecretvalue) ~= "function" then return false end
	for i = 1, select("#", ...) do if issecretvalue((select(i, ...))) then return true end end
	return false
end

local function Whole(v, lo, hi)
	if Secret(v) then return nil end
	local ok, number = pcall(tonumber, v)
	v = ok and number or nil
	return v and v == math.floor(v) and v >= lo and v <= hi and v or nil
end

local function Count(t)
	local n = 0
	for _ in pairs(type(t) == "table" and t or {}) do n = n + 1 end
	return n
end

local function Clean(value, limit)
	if Secret(value) then return nil end
	local ok, s = pcall(tostring, value or "")
	if not ok then return nil end
	s = s:gsub("[~|%^%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if s == "" then return nil end
	return ns.Cut(s, limit or 96)
end

local function CleanRealm(realm)
	if Secret(realm) then return nil end
	realm = type(realm) == "string" and realm:gsub("[%s%-]", "") or nil
	if not realm or realm == "" or realm == "?" or realm:find("+", 1, true) then return nil end
	return ns.Cut(realm, 48)
end

local function CleanName(name, realm)
	if Secret(name, realm) then return nil end
	name = Clean(ns.Normal and ns.Normal(name) or name, 72)
	if not name then return nil end
	local namedRealm = ns.RealmOf and ns.RealmOf(name) or name:match("%-(.+)$")
	local short = ns.ShortName and ns.ShortName(name) or name:gsub("%-.*$", "")
	short = Clean(short, 48)
	if not short then return nil end
	realm = CleanRealm(namedRealm) or CleanRealm(realm) or CleanRealm(ns.realm)
	return realm and (short .. "-" .. realm) or short
end

local function Guid(guid)
	if Secret(guid) then return nil end
	if type(guid) ~= "string" or #guid > 64 then return nil end
	local server, id = guid:match("^Player%-(%d+)%-(%x+)$")
	if not server or #id < 8 or #id > 16 then return nil end
	return "Player-" .. server .. "-" .. id:upper()
end

local function GuidKey(guid)
	guid = Guid(guid)
	return guid and ("g:" .. guid) or nil
end

local function NameKey(name)
	name = CleanName(name)
	return name and ("n:" .. ns.Fold(name)) or nil
end

local function Identity(value, guid, realm)
	if type(value) == "table" then
		guid, realm, value = value.guid, value.realm, value.name
	end
	local name = CleanName(value, realm)
	guid = Guid(guid)
	if not name and not guid then return nil end
	return { name = name, realm = name and ns.RealmOf(name) or CleanRealm(realm), guid = guid,
		key = GuidKey(guid) or NameKey(name), nameKey = NameKey(name), guidKey = GuidKey(guid) }
end
Wanted.Identity = Identity

local function SameIdentity(a, b)
	a, b = type(a) == "table" and a or Identity(a), type(b) == "table" and b or Identity(b)
	if not a or not b then return false end
	if a.guid and b.guid then return a.guid == b.guid end
	return a.nameKey ~= nil and a.nameKey == b.nameKey
end

local function Store(create)
	if type(ns.rdb) ~= "table" then return nil end
	local s = ns.rdb.wanted
	if type(s) ~= "table" or s.version ~= Wanted.VERSION or s.group ~= ns.group or s.faction ~= ns.faction then
		if not create then return nil end
		s = { version = Wanted.VERSION, group = ns.group, faction = ns.faction, targets = {}, aliases = {},
		scoreVersion = Wanted.SCORE_VERSION, slayers = {}, slayerAliases = {}, baseSlayers = {}, evidence = {}, seen = {}, seenOrder = {}, recent = {}, audit = {},
		voids = {}, seq = 0 }
		ns.rdb.wanted = s
	end
	-- A newer client may have changed the meaning of stored totals again. Never silently
	-- downgrade, initialize or reinterpret that data with this build's migration.
	local scoreVersion = Whole(s.scoreVersion, 1, 2147483647)
	if scoreVersion and scoreVersion > Wanted.SCORE_VERSION then return nil end
	-- (voids, 1.2.3: [sender#digest] = when a reviewer voided that shared row, so a copy heard later
	-- is refused too. recapsRead, 1.2.3: [killer GUID@time] = when, each death recap this client
	-- read, so it never counts twice; inside: this client's own times in an instance, { from, to }.
	-- 1.2.4, the notices': mine, [Horde GUID] = { name, deaths }: this store's characters' own deaths
	-- to him, open; avenged, the avenged notices waiting; slayerLetters, the Slayer letters waiting;
	-- avengedTold, [claim id|character] = when, the claims each character was told of: once.)
	for _, key in ipairs({ "targets", "aliases", "slayers", "slayerAliases", "baseSlayers", "evidence", "seen", "seenOrder", "recent", "audit", "voids",
		"recapsRead", "inside", "mine", "avenged", "slayerLetters", "avengedTold" }) do
		if type(s[key]) ~= "table" then s[key] = {} end
	end
	s.seq = Whole(s.seq, 0, 2147483647) or 0
	if s.scoreVersion ~= Wanted.SCORE_VERSION and type(Wanted.MigrateScoring) == "function" then Wanted.MigrateScoring(s) end
	return s
end

local function Sighting(value)
	if type(value) ~= "table" then return nil end
	local zone, at = Clean(value.zone, 80), Whole(value.at, 0, 4294967295)
	if not zone or not at then return nil end
	return { zone = zone, at = at, precision = value.precision == "consented" and "consented" or "approximate",
		evidence = value.evidence == "SELF_DEATH" and "SELF_DEATH" or "PARTY_KILL",
		mapID = Whole(value.mapID, 1, 9999999) }
end

local CopySlayers

-- (paid, 1.2.3: what this entry's claims paid each Slayer, in the shape of the Slayers rows. The
-- Slayers board is built from the entries on the list, so an entry taken off takes its points with
-- it, folded or not: Rebuild. bounty, 1.2.3: what its rows set going for the next ones, the
-- corpse-camping gaps, the grudges and the cycle's highest level: Bounty.State.)
local function TargetDerived(t)
	return {
		bounty = Bounty.State(t.bounty),
		current = Whole(t.current, 0, Wanted.MAX_POINTS) or 0,
		lifetimeKills = Whole(t.lifetimeKills, 0, Wanted.MAX_POINTS) or 0,
		cycle = Whole(t.cycle, 1, Wanted.MAX_POINTS) or 1,
		openSince = Whole(t.openSince, 0, 4294967295) or (tonumber(t.addedAt) or 0),
		lastDeath = Whole(t.lastDeath, 0, 4294967295),
		-- Whether every row in the open bounty cycle came from membership this client could
		-- independently verify.  Old stores predate self-claimed cross-guild membership and are
		-- therefore trusted; a new unverified row flips the current cycle until it closes.
		cycleVerified = t.cycleVerified ~= false,
		lastSighting = Sighting(t.lastSighting),
		victimOverflow = Whole(t.victimOverflow, 0, Wanted.MAX_POINTS) or 0,
		-- Older saved cycles counted every overflow death as a kill. New cycles keep the
		-- counted part separately, so trimming a repeated death never inflates the letter.
		victimKillOverflow = Whole(t.victimKillOverflow, 0, Wanted.MAX_POINTS)
			or Whole(t.victimOverflow, 0, Wanted.MAX_POINTS) or 0,
		victims = type(t.victims) == "table" and t.victims or {},
		claims = type(t.claims) == "table" and t.claims or {},
		paid = CopySlayers(t.paid),
	}
end

local function CopyList(list, limit)
	local out = {}
	for i = math.max(1, #(type(list) == "table" and list or {}) - (limit or 100) + 1), #(type(list) == "table" and list or {}) do
		local e = list[i]
		if type(e) == "table" then
			local c = {}
			for k, v in pairs(e) do
				if type(v) == "table" then c[k] = CopyList(v, Wanted.MAX_VICTIMS) else c[k] = v end
			end
			out[#out + 1] = c
		end
	end
	return out
end

CopySlayers = function(rows)
	local out = {}
	for key, r in pairs(type(rows) == "table" and rows or {}) do
		if type(key) == "string" and type(r) == "table" then
			local months, monthAt, monthClaims, available = {}, {}, {}, {}
			for m, n in pairs(type(r.months) == "table" and r.months or {}) do
				m, n = tonumber(m), Whole(n, 0, Wanted.MAX_POINTS)
				if m and n then available[#available + 1] = { m, n } end
			end
			table.sort(available, function(a, b) return a[1] > b[1] end)
			for i = 1, math.min(Wanted.MAX_MONTHS, #available) do
				local m, n = available[i][1], available[i][2]
				months[m] = n
				monthAt[m] = Whole(type(r.monthAt) == "table" and r.monthAt[m], 0, 4294967295) or 0
				monthClaims[m] = Whole(type(r.monthClaims) == "table" and r.monthClaims[m], 0, Wanted.MAX_POINTS) or 0
			end
			local total = Whole(r.total, 0, Wanted.MAX_POINTS) or 0
			local verifiedTotal = Whole(r.verifiedTotal, 0, total)
			if verifiedTotal == nil then verifiedTotal = total end -- rows saved before membership provenance
			out[key] = { key = key, name = CleanName(r.name), guid = Guid(r.guid), total = total,
				claims = Whole(r.claims, 0, Wanted.MAX_POINTS) or 0, reachedAt = Whole(r.reachedAt, 0, 4294967295) or 0,
				lastAt = Whole(r.lastAt, 0, 4294967295) or 0, months = months, monthAt = monthAt, monthClaims = monthClaims,
				verifiedTotal = verifiedTotal,
				verifiedClaims = Whole(r.verifiedClaims, 0, Wanted.MAX_POINTS)
					or Whole(r.claims, 0, Wanted.MAX_POINTS) or 0,
				verifiedReachedAt = Whole(r.verifiedReachedAt, 0, 4294967295)
					or Whole(r.reachedAt, 0, 4294967295) or 0 }
		end
	end
	return out
end

local function MergeSlayer(into, from)
	into.total = math.min(Wanted.MAX_POINTS, (into.total or 0) + (from.total or 0))
	into.claims = math.min(Wanted.MAX_POINTS, (into.claims or 0) + (from.claims or 0))
	into.verifiedTotal = math.min(Wanted.MAX_POINTS, (into.verifiedTotal or 0) + (from.verifiedTotal or 0))
	into.verifiedClaims = math.min(Wanted.MAX_POINTS, (into.verifiedClaims or 0) + (from.verifiedClaims or 0))
	into.verifiedReachedAt = math.max(into.verifiedReachedAt or 0, from.verifiedReachedAt or 0)
	into.reachedAt = math.max(into.reachedAt or 0, from.reachedAt or 0)
	into.lastAt = math.max(into.lastAt or 0, from.lastAt or 0)
	into.months, into.monthAt, into.monthClaims = into.months or {}, into.monthAt or {}, into.monthClaims or {}
	for month, points in pairs(from.months or {}) do
		into.months[month] = math.min(Wanted.MAX_POINTS, (into.months[month] or 0) + points)
		into.monthAt[month] = math.max(into.monthAt[month] or 0, from.monthAt and from.monthAt[month] or 0)
		into.monthClaims[month] = math.min(Wanted.MAX_POINTS,
			(into.monthClaims[month] or 0) + (from.monthClaims and from.monthClaims[month] or 0))
	end
	into.name, into.guid = into.name or from.name, into.guid or from.guid
	return into
end

-- A Slayer's key as this store knows him now (a name known first, his GUID learned later: the
-- aliases ResolveSlayer keeps).
function Share.SlayerKey(s, key)
	for _ = 1, 3 do
		local alias = s.slayerAliases[key]
		if type(alias) ~= "string" or alias == key then break end
		key = alias
	end
	return key
end

-- One entry's contribution (a Slayers-shaped row) added into a Slayers table under its Slayer's
-- key now (rows: s.slayers, or the points no entry holds any more, s.baseSlayers).
function Share.AddPaid(s, rows, r)
	local key = Share.SlayerKey(s, r.key)
	local into = rows[key]
	if not into then
		-- (A GUID's key names his GUID, though the row was folded when his name alone was known.)
		into = { key = key, name = r.name, guid = r.guid or Guid(key:match("^g:(.+)$")), total = 0, claims = 0,
			verifiedTotal = 0, verifiedClaims = 0, verifiedReachedAt = 0,
			months = {}, monthAt = {}, monthClaims = {} }
		rows[key] = into
	end
	MergeSlayer(into, r)
end

local function ResolveSlayer(s, value, create, upgrade)
	local ident = Identity(value)
	if not ident then return nil end
	if upgrade == nil then upgrade = create == true end
	local gk, nk = ident.guidKey, ident.nameKey
	local key = gk and (s.slayerAliases[gk] or gk) or nil
	local r = key and s.slayers[key] or nil
	if not r and nk then
		key = s.slayerAliases[nk] or nk
		r = s.slayers[key]
	end
	if r and r.guid and ident.guid and r.guid ~= ident.guid then return nil end
	if r and gk and r.key ~= gk and upgrade then
		local oldKey, other = r.key, s.slayers[gk]
		if other and other ~= r then
			r = MergeSlayer(other, r)
			s.slayers[oldKey] = nil
		else
			s.slayers[oldKey] = nil
			r.key = gk
			s.slayers[gk] = r
		end
		s.slayerAliases[oldKey] = gk
		key = gk
	elseif not r and create then
		if Count(s.slayers) >= Wanted.MAX_SLAYERS then return nil, "full" end
		key = gk or nk
		if not key then return nil, "identity" end
		r = { key = key, name = ident.name, guid = ident.guid, total = 0, claims = 0,
			verifiedTotal = 0, verifiedClaims = 0, verifiedReachedAt = 0,
			months = {}, monthAt = {}, monthClaims = {} }
		s.slayers[key] = r
	end
	if not r then return nil end
	if upgrade or create then r.name, r.guid = ident.name or r.name, ident.guid or r.guid end
	if upgrade or create then
		if nk then s.slayerAliases[nk] = r.key end
		if gk then s.slayerAliases[gk] = r.key end
	end
	return r, r.key
end

local function TrimList(list, max)
	while #list > max do table.remove(list, 1) end
end

-- Whether entry a holds a name's alias before entry b (or none): one on the list before one taken
-- off, a name this client's game gave before one only a shared row wrote, then the newer.
function Share.Better(a, b)
	if type(b) ~= "table" then return true end
	if (a.active == true) ~= (b.active == true) then return a.active == true end
	if (a.wireName == true) ~= (b.wireName == true) then return b.wireName == true end
	return (tonumber(a.addedAt) or 0) > (tonumber(b.addedAt) or 0)
end

-- An entry's name, and its alias (only a lookup by name reads it: a row about a Horde player
-- finds him by his GUID alone, ResolveTarget). wire: the name is a shared row's, which this
-- client's game could not check; it takes the alias only from an entry no better (Share.Better).
-- A name this client's game gave takes it from anyone: the newest proof wins.
function Share.Name(s, t, ident, wire)
	local oldKey = NameKey(t.name)
	-- (The name he had still finds him, unless only a row wrote it.)
	if oldKey and oldKey ~= ident.nameKey then
		if t.wireName then
			if s.aliases[oldKey] == t.key then s.aliases[oldKey] = nil end
		elseif s.aliases[oldKey] == nil then
			s.aliases[oldKey] = t.key
		end
	end
	t.name, t.realm, t.wireName = ident.name, ident.realm, wire and true or nil
	local nk = ident.nameKey
	if not nk or nk == t.key then return end
	local holder = s.targets[s.aliases[nk] or nk]
	if not wire or holder == t or Share.Better(t, holder) then s.aliases[nk] = t.key end
end

-- An entry taken off lets go of his name: it finds the best other entry under it (Share.Better,
-- one on the list first), and him only while there is none (his page, as an audit). Nothing a row
-- counts against is found by a name any more (ResolveTarget), so a name never keeps anyone off.
function Share.ReleaseName(s, t)
	local nk = NameKey(t.name)
	if not nk or nk == t.key or s.aliases[nk] ~= t.key then return end
	local best = t
	for key, o in pairs(s.targets) do
		if o ~= t and key ~= nk and NameKey(o.name) == nk and Share.Better(o, best) then best = o end
	end
	s.aliases[nk] = best.key
end

-- The entry an identity names, or nil. A GUID finds only the entry pinned to it, or a name-only
-- listing (1.2.2's, a moderator's) under his name while it is on the list, and that only from
-- what this client proved itself: a shared row's name is its sender's word (wire), and never
-- pins a GUID to a typed name. A name alone finds the entry under it; from a shared row (wire:
-- its Olympian, by the name the server stamps), only one pinned to no GUID, so that an entry a
-- row made under someone's name never stands for him. upgrade: what the identity teaches the
-- entry (his GUID, a name from this client's game, or a name where it had none).
local function ResolveTarget(s, ident, upgrade, wire)
	if not ident then return nil end
	local t, key
	if ident.guidKey then
		key = s.aliases[ident.guidKey] or ident.guidKey
		t = s.targets[key]
		if t and t.guid ~= ident.guid then t = nil end
		if not t and ident.nameKey and not wire then
			local named = s.targets[ident.nameKey]
			if type(named) == "table" and not named.guid and named.active == true then t, key = named, ident.nameKey end
		end
	elseif ident.nameKey then
		key = s.aliases[ident.nameKey] or ident.nameKey
		t = s.targets[key]
		if not t then key = ident.nameKey; t = s.targets[key] end
		if t and wire and t.guid then t = nil end
	end
	if not t then return nil end
	if ident.guid and not t.guid and upgrade then
		local newKey = ident.guidKey
		local other = s.targets[newKey]
		if other and other ~= t then return nil end
		local oldKey = t.key
		s.targets[oldKey] = nil
		t.key, t.guid = newKey, ident.guid
		s.targets[newKey] = t
		s.aliases[oldKey], s.aliases[newKey] = newKey, newKey
		if ident.name then Share.Name(s, t, ident, false) end
		for _, e in ipairs(s.evidence) do if e.targetKey == oldKey then e.targetKey = newKey end end
		key = newKey
	elseif ident.name and ident.guid and upgrade and (not t.name or not wire and t.name ~= ident.name) then
		Share.Name(s, t, ident, wire)
	end
	return t, key
end

function Bounty.RealmOffset(now)
	now = now or Clock()
	local offset = 0
	if type(GetGameTime) == "function" then
		local ok, h, m = pcall(GetGameTime)
		if ok and type(h) == "number" and type(m) == "number" then
			local d = (h * 60 + m - math.floor(now / 60) % 1440) % 1440
			if d > 720 then d = d - 1440 end
			offset = math.floor(d / 15 + 0.5) * 900
		end
	end
	return offset
end

function Bounty.MonthAt(at)
	at = Whole(at, 0, 4294967295) or math.floor(Clock())
	local offset = Bounty.RealmOffset(Clock())
	if ns.Honors and ns.Honors.MonthOf then return ns.Honors.MonthOf(at, offset) end
	local dateFn = date or (os and os.date)
	if type(dateFn) ~= "function" then return math.floor(at / 2592000) end
	local d = dateFn("!*t", at + offset)
	return d.year * 12 + d.month - 1
end

local function MonthNow()
	local c = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
	if type(c) == "table" and Whole(c.year, 1970, 9999) and Whole(c.month, 1, 12) then return c.year * 12 + c.month - 1 end
	return Bounty.MonthAt(math.floor(Clock()))
end
Wanted.MonthNow = MonthNow

local function TrimMonths(r, current)
	local first = current - Wanted.MAX_MONTHS + 1
	for month in pairs(type(r.months) == "table" and r.months or {}) do
		if type(month) ~= "number" or month < first or month > current then
			r.months[month] = nil
			if type(r.monthAt) == "table" then r.monthAt[month] = nil end
			if type(r.monthClaims) == "table" then r.monthClaims[month] = nil end
		end
	end
end

-- One paid claim on a Slayers-shaped row: the Slayer's own, or what one entry paid him.
function Share.Pay(r, points, at, month, verified)
	r.months, r.monthAt, r.monthClaims = r.months or {}, r.monthAt or {}, r.monthClaims or {}
	r.total, r.claims, r.reachedAt, r.lastAt = math.min(Wanted.MAX_POINTS, (r.total or 0) + points),
		math.min(Wanted.MAX_POINTS, (r.claims or 0) + 1), at, at
	r.months[month], r.monthAt[month] = math.min(Wanted.MAX_POINTS, (r.months[month] or 0) + points), at
	r.monthClaims[month] = math.min(Wanted.MAX_POINTS, (r.monthClaims[month] or 0) + 1)
	if verified then
		r.verifiedTotal = math.min(Wanted.MAX_POINTS, (r.verifiedTotal or 0) + points)
		r.verifiedClaims = math.min(Wanted.MAX_POINTS, (r.verifiedClaims or 0) + 1)
		r.verifiedReachedAt = at
	end
	TrimMonths(r, MonthNow())
end

local function AddVictim(t, e)
	local row = { name = e.victimName, guid = e.victimGuid, at = e.at, evidence = e.kind, id = e.id,
		zone = e.zone, precision = e.precision, points = e.points, again = e.again }
	t.victims[#t.victims + 1] = row
	if #t.victims > Wanted.MAX_VICTIMS then
		local dropped = table.remove(t.victims, 1)
		t.victimOverflow = (t.victimOverflow or 0) + 1
		if not dropped.again then t.victimKillOverflow = (t.victimKillOverflow or 0) + 1 end
	end
end

local function ApplyEvidence(s, e)
	local t = s.targets[e.targetKey]
	if not t then return false end
	-- 1.2.3: an entry a reviewer took off (abuse) keeps its rows, and they count for nothing: no
	-- bounty on him, no point paid for him (Wanted.RemoveTarget rebuilds the totals without them).
	if t.active ~= true then return true end
	if e.action == "bounty" then
		if t.lifetimeKills >= Wanted.MAX_POINTS then return false end
		-- 1.2.3 (Daniel's weights): what this death adds (Bounty.Death: the victim's office and level,
		-- nothing inside the corpse-camping gap; 1 for a row without them), the cycle's bounty at
		-- most BOUNTY_MAX; e.points is what it added.
		-- 1.2.4 (the author's report: "3 kills, 18 points", one member killed three times in a few
		-- minutes): the kills count as the points do. A death inside that gap (e.again) adds no kill
		-- either; it stays among his victims, marked so. A death at the cap still counts its kill.
		local worth, again = Bounty.Death(t, e)
		local added = math.max(0, math.min(worth, Bounty.SCORE.BOUNTY_MAX - t.current))
		t.current, e.points, e.again = t.current + added, added, again or nil
		if e.memberVerified == false then t.cycleVerified = false end
		if not again then t.lifetimeKills = t.lifetimeKills + 1 end
		AddVictim(t, e)
	elseif e.action == "claim" then
		-- 1.2.4: what the kill pays (Bounty.Claim: the small level base, the whole bounty and the revenge;
		-- the bounty alone for a row without the fields), then a new cycle.
		local points, level, revenge = Bounty.Claim(t, e)
		local rankVerified = e.memberVerified ~= false and t.cycleVerified ~= false
		local r
		if points > 0 then
			r = ResolveSlayer(s, { name = e.killerName, guid = e.killerGuid }, true)
			if not r then return false end
		end
		e.points, e.level, e.revenge = points, level, revenge or nil
		local claim = { id = e.id, at = e.at, month = e.month, slayer = e.killerName, slayerGuid = e.killerGuid, points = points,
			evidence = e.kind, cycle = t.cycle, victims = CopyList(t.victims, Wanted.MAX_VICTIMS), overflow = t.victimOverflow or 0,
			killOverflow = t.victimKillOverflow or 0,
			bounty = t.current, level = level, revenge = revenge or nil, scoreVersion = Wanted.SCORE_VERSION }
		t.claims[#t.claims + 1] = claim
		TrimList(t.claims, Wanted.MAX_CLAIMS)
		t.current, t.victims, t.victimOverflow, t.victimKillOverflow = 0, {}, 0, 0
		t.lastDeath, t.openSince, t.cycle = e.at, e.at, math.min(Wanted.MAX_POINTS, t.cycle + 1)
		Bounty.Closed(t, e)
		if points > 0 then
			r.name, r.guid = e.killerName or r.name, e.killerGuid or r.guid
			Share.Pay(r, points, e.at, e.month, rankVerified)
			-- (And on this entry's own account of what it paid him: Rebuild, Checkpoint.)
			if type(t.paid) ~= "table" then t.paid = {} end
			local p = t.paid[r.key]
			if not p then p = { key = r.key } t.paid[r.key] = p end
			p.name, p.guid = r.name, r.guid
			Share.Pay(p, points, e.at, e.month, rankVerified)
		end
		t.cycleVerified = true
	else
		return false
	end
	if e.zone then t.lastSighting = { zone = e.zone, at = e.at, precision = e.precision, evidence = e.kind,
		mapID = Whole(e.mapID, 1, 9999999) } end
	return true
end

-- The totals built again: each entry from its base, the Slayers from the points no entry holds any
-- more (s.baseSlayers: an entry that made room for another, or folded before 1.2.3) and what each
-- entry on the list paid, folded (its base's paid: an entry taken off pays nothing any more, on
-- every client, whenever it folded), then the live rows in the order of the deaths.
local function Rebuild(s)
	for _, t in pairs(s.targets) do
		local b = TargetDerived(type(t.base) == "table" and t.base or {})
		t.current, t.lifetimeKills, t.cycle, t.openSince, t.lastDeath = b.current, b.lifetimeKills, b.cycle, b.openSince, b.lastDeath
		t.cycleVerified = b.cycleVerified
		t.lastSighting = b.lastSighting
		t.victimOverflow, t.victimKillOverflow = b.victimOverflow, b.victimKillOverflow
		t.victims, t.claims = CopyList(b.victims, Wanted.MAX_VICTIMS), CopyList(b.claims, Wanted.MAX_CLAIMS)
		t.paid, t.bounty = b.paid, b.bounty
	end
	s.slayers = CopySlayers(s.baseSlayers)
	for _, t in pairs(s.targets) do
		if t.active == true then for _, p in pairs(t.paid) do Share.AddPaid(s, s.slayers, p) end end
	end
	for _, e in ipairs(s.evidence) do if type(e) == "table" and not e.void then ApplyEvidence(s, e) end end
	return true
end
Wanted.Rebuild = function() local s = Store(false); return s and Rebuild(s) or false end

local function Checkpoint(s)
	for _, t in pairs(s.targets) do
		t.base = TargetDerived(t)
		t.base.victims, t.base.claims = CopyList(t.victims, Wanted.MAX_VICTIMS), CopyList(t.claims, Wanted.MAX_CLAIMS)
		-- (What it paid, each Slayer under his key now.)
		local paid = {}
		for _, p in pairs(t.base.paid) do Share.AddPaid(s, paid, p) end
		for _, p in pairs(paid) do TrimMonths(p, MonthNow()) end
		t.base.paid = paid
	end
	-- (The Slayers' points stay with the entries that paid them; s.baseSlayers keeps only the
	-- points no entry holds any more.)
	for _, r in pairs(s.baseSlayers) do TrimMonths(r, MonthNow()) end
	-- (1.2.3: the newest death folded. A shared row about a death before it can no longer take its
	-- place in the order of the deaths, and is refused: "late".)
	for _, e in ipairs(s.evidence) do
		local at = Whole(type(e) == "table" and e.at, 0, 4294967295)
		if at and at > (Whole(s.foldedAt, 0, 4294967295) or 0) then s.foldedAt = at end
	end
	s.evidence = {}
	stats.checkpointed = stats.checkpointed + 1
end

local function Audit(s, op, target, detail)
	s.audit[#s.audit + 1] = { op = op, target = target, detail = detail, at = math.floor(Clock()), by = ns.me }
	TrimList(s.audit, Wanted.MAX_AUDIT)
end

local function Changed()
	ns.Fire("WANTED_CHANGED")
	if ns.UI and ns.UI.RefreshSoon then ns.UI.RefreshSoon() end
	if Wanted.RefreshPins then Wanted.RefreshPins() end
end

function Wanted.CanManage()
	if not ns.IsMember or not ns.IsMember() or not ns.me then return false end
	local M = ns.Moderation
	if M and M.CanIssue and M.CanIssue() == true then return true end
	local W = ns.Workshop
	return W and W.IsAuthor and W.IsAuthor() == true or false
end

-- 1.2.3: nobody lists a Horde player first any more, and no button does it: he enters by himself
-- from a member's own death or killing blow (RecordKill). This listing by name or GUID, for a
-- Watch moderator or the author and through this function alone, stays for the targets 1.2.2
-- saved and for the tests: such an entry is a Horde player like any other, and an own event
-- about him counts against it (a name-only one learns his GUID then).
function Wanted.AddTarget(value, guid, realm)
	if not Wanted.CanManage() then return false, "access" end
	local ident = Identity(value, guid, realm)
	if not ident then return false, "identity" end
	local s = Store(true)
	local t = ResolveTarget(s, ident, true)
	if t then
		if t.active then return false, "listed" end
		Share.MakeRoom(s)
		t.active, t.removedAt, t.removedBy = true, nil, nil
		t.addedAt, t.addedBy = math.floor(Clock()), ns.me
	else
		Share.MakeRoom(s)
		t = { key = ident.key, name = ident.name, realm = ident.realm, guid = ident.guid, active = true,
			addedAt = math.floor(Clock()), addedBy = ns.me, source = "manual", current = 0, lifetimeKills = 0,
			cycle = 1, openSince = math.floor(Clock()), victims = {}, claims = {}, victimOverflow = 0 }
		s.targets[t.key] = t
		if ident.nameKey then s.aliases[ident.nameKey] = t.key end
		if ident.guidKey then s.aliases[ident.guidKey] = t.key end
	end
	Audit(s, "add", t.key)
	Changed()
	return true, t.key
end

-- 1.2.3: who may take an abusive entry off, or void one row: the King, a signed High Councillor
-- or the author (the roles every client checks on his word, WV), never a member, nor a review.
function Wanted.CanRemove() return Wanted.CanPublish(ns.me) == true end

-- An abusive entry taken off: here at once, and on every client through the reviewer's word on
-- the channel (WV, Share.SendMark). Its rows stay, as an audit, and count for nothing any more
-- (ApplyEvidence): no bounty on him, no point paid for him, even what was folded (Rebuild). A
-- later event about him is refused ("removed"), so it never comes back by itself. He is kept off
-- by his GUID apart from the list (MAX_REMOVED), and lets go of his name (Share.ReleaseName).
function Wanted.RemoveTarget(value, guid, realm)
	if not Wanted.CanRemove() then return false, "access" end
	local s, ident = Store(false), Identity(value, guid, realm)
	local t = s and ResolveTarget(s, ident, false)
	if not (t and t.active) then return false, "missing" end
	Share.TakeOff(s, t, CleanName(ns.me), math.floor(Clock()))
	Audit(s, "remove", t.key)
	if opened == t.key then mode, opened = "list", nil end
	if t.guid then Share.SendMark("T", t.guid) end
	Changed()
	return true
end

-- (The entry off, nothing of what it held kept, folded or not, and the totals again without it.)
function Share.TakeOff(s, t, by, at)
	t.active, t.removedAt, t.removedBy, t.base = false, at, by, nil
	Share.ReleaseName(s, t)
	Share.TrimRemoved(s)
	Rebuild(s)
end

-- One entry gone from this store: its aliases and its rows with it.
function Share.Drop(s, key)
	s.targets[key] = nil
	for alias, held in pairs(s.aliases) do if held == key then s.aliases[alias] = nil end end
	for i = #s.evidence, 1, -1 do if s.evidence[i].targetKey == key then table.remove(s.evidence, i) end end
end

-- The entries taken off, MAX_REMOVED at most, apart from the list: past it the oldest removal goes.
function Share.TrimRemoved(s)
	local off = {}
	for key, t in pairs(s.targets) do if t.active ~= true then off[#off + 1] = key end end
	if #off <= Wanted.MAX_REMOVED then return end
	table.sort(off, function(a, b)
		local x, y = tonumber(s.targets[a].removedAt) or 0, tonumber(s.targets[b].removedAt) or 0
		if x ~= y then return x < y end
		return a < b
	end)
	for i = 1, #off - Wanted.MAX_REMOVED do Share.Drop(s, off[i]) end
end

local function UnitIdentity(unit)
	if type(UnitIsPlayer) == "function" then
		local ok, yes = pcall(UnitIsPlayer, unit)
		if not ok or yes ~= true then return nil end
	end
	local okName, name = pcall(function() return ns.UnitFullName and ns.UnitFullName(unit) or nil end)
	local okGuid, guid = pcall(function() return UnitGUID and UnitGUID(unit) or nil end)
	if not okName or not okGuid or Secret(name, guid) then return nil end
	return Identity(name, guid)
end

function Wanted.AddTargetUnit(unit)
	unit = unit or "target"
	local ident = UnitIdentity(unit)
	if not ident then return false, "identity" end
	if type(UnitFactionGroup) == "function" then
		local ok, known, horde = pcall(function()
			local faction = UnitFactionGroup(unit)
			if Secret(faction) then return true, false end
			return faction ~= nil, faction == "Horde"
		end)
		if not ok or known and not horde then return false, "faction" end
	end
	return Wanted.AddTarget(ident)
end

local function UnitMatches(unit, ident)
	local u = UnitIdentity(unit)
	return u and SameIdentity(u, ident)
end

-- (1.2.3: and his level as the game showed it on that unit, -1 for its "??": Share.SeenLevel.)
local function RememberHorde(ident, unit)
	if not ident or not ident.guid or not ident.name then return end
	local now = math.floor(Clock())
	knownHorde[ident.guid] = { identity = ident, at = now, level = unit and Share.UnitLevel(unit) or nil }
	for guid, row in pairs(knownHorde) do if now - row.at > 60 or row.at > now then knownHorde[guid] = nil end end
	while Count(knownHorde) > Wanted.MAX_TARGETS do
		local oldest
		for guid, row in pairs(knownHorde) do if not oldest or row.at < knownHorde[oldest].at then oldest = guid end end
		knownHorde[oldest] = nil
	end
end

-- The units this client may see a player by: the game's own token for his GUID first, then the
-- target, the focus, the mouse's and the nameplates.
function Share.Units(guid)
	local units = { "target", "focus", "mouseover" }
	for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
	if guid and type(UnitTokenFromGUID) == "function" then
		local ok, token = pcall(UnitTokenFromGUID, guid)
		if ok and type(token) == "string" and not Secret(token) then table.insert(units, 1, token) end
	end
	return units
end

-- A unit's level as the game gives it (UnitLevel): a whole level, -1 for the game's "??" (one far
-- above this player's), nil for none (no unit, a hidden value).
function Share.UnitLevel(unit)
	if type(UnitLevel) ~= "function" or type(unit) ~= "string" then return nil end
	local ok, level = pcall(UnitLevel, unit)
	if not ok or Secret(level) or type(level) ~= "number" then return nil end
	if level == -1 then return -1 end
	return level >= 1 and math.floor(level) or nil
end

-- A Horde player's level as this client sees it (1.2.3): a unit of his now (his corpse, a
-- nameplate, the target: the game's token for his GUID first), else the unit it saw him by within
-- a minute (RememberHorde). -1: the game's "??". nil: none.
function Share.SeenLevel(guid)
	guid = Guid(guid)
	if not guid then return nil end
	for _, unit in ipairs(Share.Units(guid)) do
		local ok, g = pcall(function() return UnitGUID and UnitGUID(unit) end)
		if ok and not Secret(g) and Guid(g) == guid then
			local level = Share.UnitLevel(unit)
			if level then return level end
		end
	end
	local row, now = knownHorde[guid], math.floor(Clock())
	return row and row.at <= now and now - row.at <= 60 and row.level or nil
end

-- A Horde player this client sees now (a unit with his GUID: the target, the focus, the mouse's,
-- a nameplate, or the game's own token for that GUID) or saw within a minute, or nil. nil, true
-- when a unit of his shows now and is no Horde player (or its faction is unknown): the current
-- unit overrides an old observation.
local function KnownHorde(ident)
	if not ident or not ident.guid then return nil end
	for _, unit in ipairs(Share.Units(ident.guid)) do
		local observed = UnitIdentity(unit)
		if observed and observed.guid == ident.guid then
			local ok, faction = pcall(function() return UnitFactionGroup and UnitFactionGroup(unit) end)
			if ok and not Secret(faction) and faction == "Horde" then RememberHorde(observed, unit); return observed end
			return nil, true -- current contradictory/unknown faction overrides an old observation
		end
	end
	local row, now = knownHorde[ident.guid], math.floor(Clock())
	return row and row.at <= now and now - row.at <= 60 and row.identity or nil
end

local function VerifiedOlympian(ident)
	if not ident then return false end
	local mine = UnitIdentity("player") or Identity(ns.me)
	if mine and SameIdentity(mine, ident) and ns.IsMember and ns.IsMember() then return true end
	local R = ns.Roster
	if ident.name and R and R.RankOf and R.RankOf(ident.name) ~= nil then return true end
	local units = { "player", "target", "focus", "mouseover" }
	for i = 1, 4 do units[#units + 1] = "party" .. i end
	for i = 1, 40 do units[#units + 1] = "raid" .. i end
	for _, unit in ipairs(units) do
		if UnitMatches(unit, ident) then
			local guild = GetGuildInfo and GetGuildInfo(unit)
			if not Secret(guild) and type(guild) == "string" and ns.IsFederation(guild) then return true end
		end
	end
	return false
end

local function Zone()
	if type(GetRealZoneText) ~= "function" then return nil end
	local ok, zone = pcall(GetRealZoneText)
	local mapID
	if type(C_Map) == "table" and type(C_Map.GetBestMapForUnit) == "function" then
		local mapOK, value = pcall(C_Map.GetBestMapForUnit, "player")
		if mapOK and not Secret(value) then mapID = Whole(value, 1, 9999999) end
	end
	return ok and Clean(zone, 80) or nil, mapID
end

local function InInstance()
	if type(IsInInstance) ~= "function" then return false end
	local ok, inside = pcall(IsInInstance)
	if not ok or Secret(inside) then return true end -- (not known: as if inside)
	return inside == true
end

local function Hex(bytes)
	return type(bytes) == "string" and (bytes:gsub(".", function(c) return ("%02x"):format(c:byte()) end)) or nil
end

local function Digest(text)
	local S = ns.Sign
	local raw = S and S.SHA256 and S.SHA256(tostring(text or "")) or nil
	return raw and Hex(raw):sub(1, 16) or nil
end

-- 1.2.3: the races only the Horde plays, by the game's own file names (GetPlayerInfoByGUID's
-- fourth return, as C_CreatureInfo.GetRaceInfo's clientFileString). Forever's Skyborn are of both
-- factions (ChatRooms.lua), and a race this table does not name proves nothing either.
Share.HORDE_RACES = { Orc = true, Scourge = true, Undead = true, Tauren = true, Troll = true, BloodElf = true,
	Goblin = true, Nightborne = true, HighmountainTauren = true, MagharOrc = true, ZandalariTroll = true, Vulpera = true }

-- A character's name as the game's lookup of his GUID gives it (Debts.InfoName: Forever splits a
-- surname into the realm's place), or nil.
function Share.InfoName(guid)
	local D = ns.Debts
	if type(D) == "table" and type(D.InfoName) == "function" then
		local ok, name = pcall(D.InfoName, guid)
		if ok and type(name) == "string" and name ~= "" and not Secret(name) then return name end
		return nil
	end
	if type(GetPlayerInfoByGUID) ~= "function" then return nil end
	local ok, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
	if not ok or type(name) ~= "string" or name == "" or Secret(name, realm) then return nil end
	return ns.FullName(name, type(realm) == "string" and realm ~= "" and realm or nil)
end

-- A Horde player's identity as this client proves it, never as a row or a player names him: his
-- entry here (a Horde player already), a unit of his it sees now or saw within a minute
-- (KnownHorde: the target, the focus, the mouse's, a nameplate, the game's token for his GUID),
-- else the game's lookup of his GUID (GetPlayerInfoByGUID: a race only the Horde plays, and his
-- name). No unit, nameplate or target is needed: a killer never targeted, a stealth or ranged
-- kill, nameplates off. nil, why otherwise: "identities" (no player GUID: a pet, a creature, the
-- environment), "faction" (a unit of his shows no Horde player, or nothing proves it: an
-- Alliance race, a race of both factions, no answer from the game). hint: the name the death
-- recap gives him (no surname on Forever), used only when the game's lookup has none.
function Share.HordeOf(guid, hint)
	guid = Guid(guid)
	if not guid then return nil, "identities" end
	local s, key = Store(false), GuidKey(guid)
	local t = s and s.targets[s.aliases[key] or key]
	-- (His name as the game gives it first, so that a name a shared row wrote, which the game could
	-- not check then, is corrected now (ResolveTarget learns it); else the one held here, unless a
	-- row wrote it; else the recap's. One kept off by a reviewer's word may have no name here.)
	if type(t) == "table" and t.guid == guid then
		return Identity(Share.InfoName(guid) or (not t.wireName and t.name) or hint or t.name, guid)
	end
	local seen, contradicted = KnownHorde(Identity(nil, guid))
	if seen then return seen end
	if contradicted then return nil, "faction" end
	if type(GetPlayerInfoByGUID) ~= "function" then return nil, "faction" end
	local ok, _, _, _, race = pcall(GetPlayerInfoByGUID, guid)
	if not ok or Secret(race) or not Share.HORDE_RACES[race] then return nil, "faction" end
	local ident = Identity(Share.InfoName(guid) or hint, guid)
	if not ident or not ident.name then return nil, "identity" end
	return ident
end

local function RateAllowed(now)
	for i = #rate, 1, -1 do if now - rate[i] >= Wanted.RATE_WINDOW then table.remove(rate, i) end end
	if #rate >= Wanted.RATE_MAX then return false end
	rate[#rate + 1] = now
	return true
end

local function Remember(s, id, fingerprint, at, seq)
	s.seen[id] = { at = at, seq = seq }
	s.seenOrder[#s.seenOrder + 1] = id
	s.recent[fingerprint] = at
	while #s.seenOrder > Wanted.MAX_SEEN do
		local old = table.remove(s.seenOrder, 1)
		if old and s.seen[old] and s.seen[old].seq <= seq - Wanted.MAX_SEEN then s.seen[old] = nil end
	end
	for key, seenAt in pairs(s.recent) do if at - (tonumber(seenAt) or 0) > 30 then s.recent[key] = nil end end
end

local function EvidenceId(kind, raw, killer, victim)
	local source = Clean(raw, 64) or tostring(math.floor(Clock()))
	return ns.Cut(table.concat({ kind, killer.guid or killer.name or "?", victim.guid or victim.name or "?", source }, ":"), 160)
end

-- The newest live evidence about this victim's death inside the death window: "replay" when it
-- names the same killer (two adapters, or one row read twice across a 3-second bucket),
-- "conflict" when it names another (one death never pays twice, nor two slayers).
local function SameDeath(s, killer, victim, now)
	for i = #s.evidence, 1, -1 do
		local e = s.evidence[i]
		if type(e) == "table" and not e.void and math.abs(now - (tonumber(e.at) or 0)) <= Wanted.DEATH_WINDOW
			and SameIdentity(Identity(e.victimName, e.victimGuid), victim) then
			return SameIdentity(Identity(e.killerName, e.killerGuid), killer) and "replay" or "conflict"
		end
	end
	return nil
end

-- A death at or before the newest one folded into the targets' base (Checkpoint): a shared row
-- about it could no longer take its place in the order of the deaths.
function Share.Late(s, at)
	local folded = Whole(s.foldedAt, 0, 4294967295)
	return folded ~= nil and at <= folded
end

-- An entry's last activity: its newest death (a bounty), its last claim, or when it entered.
function Share.LastActive(t)
	local at = math.max(tonumber(t.lastDeath) or 0, tonumber(t.openSince) or 0, tonumber(t.addedAt) or 0)
	local victims = type(t.victims) == "table" and t.victims or {}
	local last = victims[#victims]
	return math.max(at, type(last) == "table" and tonumber(last.at) or 0)
end

-- Room for one more Horde player on the list (MAX_TARGETS; those taken off are kept apart and
-- take no place). It never refuses one (Daniel: every Horde killer enters by himself): the least
-- active entry goes, with its rows, the one that holds least first (Share.Holds): nothing open,
-- no grudge and nothing it ever paid, then nothing open and no grudge (1.2.3: a kill with no
-- bounty pays his level now, so nearly every entry a kill made has paid), then nothing open, then
-- the oldest of all by its last activity (Share.LastActive), an open bounty too. What its claims
-- paid stays with its Slayers, in the points no entry holds any more (s.baseSlayers). Returns true.
function Share.Holds(t)
	local paid = type(t.paid) == "table" and next(t.paid) ~= nil
	for _, c in ipairs(type(t.claims) == "table" and t.claims or {}) do if (tonumber(c.points) or 0) > 0 then paid = true break end end
	if (tonumber(t.current) or 0) > 0 then return 3 end
	local st, since = type(t.bounty) == "table" and t.bounty or {}, math.floor(Clock()) - Bounty.SCORE.GRUDGE_DAYS * 86400
	for _, at in pairs(type(st.grudge) == "table" and st.grudge or {}) do if (tonumber(at) or 0) >= since then return 2 end end
	return paid and 1 or 0
end
function Share.MakeRoom(s)
	while true do
		local listed, drop, dropAt, dropHolds = 0, nil, nil, nil
		for key, t in pairs(s.targets) do
			if t.active == true then
				listed = listed + 1
				local at, holds = Share.LastActive(t), Share.Holds(t)
				if not drop or holds < dropHolds or holds == dropHolds and (at < dropAt or at == dropAt and key < drop) then
					drop, dropAt, dropHolds = key, at, holds
				end
			end
		end
		if listed < Wanted.MAX_TARGETS or not drop then return true end
		local key = drop
		for _, p in pairs(type(s.targets[key].paid) == "table" and s.targets[key].paid or {}) do Share.AddPaid(s, s.baseSlayers, p) end
		Share.Drop(s, key)
	end
end

-- The order of the deaths, the same on every client (RecordKill, Prune): by the row's time, and
-- in one second a death before a kill (a bounty before the claim that pays it), then by its
-- sender's name and its digest, as every client holds them (an own row's id is its client's own).
function Share.Before(a, b)
	local x, y = tonumber(a.at) or 0, tonumber(b.at) or 0
	if x ~= y then return x < y end
	if a.action ~= b.action then return a.action == "bounty" end
	local p, q = ns.Fold(tostring(a.from or "")), ns.Fold(tostring(b.from or ""))
	if p ~= q then return p < q end
	p, q = tostring(a.digest or a.id or ""), tostring(b.digest or b.id or "")
	return p < q
end

-- One kill or death into this client's ledger, its entry made when the Horde player has none.
-- opts: zone, precision (where this client's player stood: its own rows only); horde = "killer"
-- or "victim", the side whose Horde faction the caller proved (Share.HordeOf, or the sharing
-- member's client: Share.Take), the side whose entry the row may make; own = this client's own
-- death or killing blow (shared on the channel by its caller); peer = a row another member
-- shared: from (his server-stamped name), digest, id, at and month as he sent them; wire = the
-- Horde player's name is that row's, which this client's game could not check (Share.Take).
-- 1.2.3: bounty = what the row is worth, frozen (the Olympian's office and level, the Horde
-- player's level and whether it is a floor: Bounty.Capture, Bounty.Intake), none for a row
-- without them; earlier = an own death read from a recap after it (Bounty.Earlier), at its time.
local function RecordKill(kind, rawId, killer, victim, opts)
	opts = opts or {}
	killer, victim = Identity(killer), Identity(victim)
	local peer = opts.peer == true
	local earlier = opts.earlier == true and not peer
	local hordeSide = opts.horde == "killer" and killer or opts.horde == "victim" and victim or nil
	local olympianSide = opts.horde == "killer" and victim or opts.horde == "victim" and killer or nil
	-- Both sides must be players the row names and identifies (Guid takes Player- GUIDs only): a
	-- pet, a creature or the environment never credits a kill, and a pet or an NPC that merely
	-- carries a listed target's name never matches that target. (Prune keeps no other row.) A
	-- shared row's Olympian side is its sender by the name the server stamps: his GUID only where
	-- this client proved it is his (Share.Take).
	if not killer or not victim or not killer.name or not victim.name
		or not killer.guid and not (peer and olympianSide == killer) or not victim.guid and not (peer and olympianSide == victim) then
		stats.refused = stats.refused + 1
		return false, "identities"
	end
	local s = Store(true)
	if not s then return false, "store" end
	-- (wire: a side whose name is only a shared row's word: its Olympian, named by the server,
	-- and its Horde player where this client's game could not check his name, opts.wire. Such a
	-- name finds no entry pinned to a GUID, and teaches none: ResolveTarget.)
	local killerWire, victimWire = peer, peer
	if hordeSide == killer then killerWire = opts.wire == true elseif hordeSide == victim then victimWire = opts.wire == true end
	-- Resolve first without learning anything: a rejected/forged row must not be able to pin a
	-- new GUID or spelling onto a listed target merely by naming it.
	local killerTarget = ResolveTarget(s, killer, false, killerWire)
	local victimTarget = ResolveTarget(s, victim, false, victimWire)
	if killerTarget and victimTarget then
		stats.refused = stats.refused + 1
		return false, "ambiguous"
	end
	-- (A death is dated by its recap's killing blow, the live one too, read a moment after it: the
	-- order of the deaths is the deaths' own on every client, not when a client read the recap.)
	local dated = peer or earlier or opts.own == true and opts.at ~= nil
	local now = dated and Whole(opts.at, 0, 4294967295) or math.floor(Clock())
	-- 1.2.3 (Daniel: "that list should never have existed"): a Horde player nobody listed enters
	-- by himself, from the proven side of the row. Only a row without that proof (the combat-log
	-- adapter's, CaptureCombatLog) still needs one side already here.
	local fresh
	if not killerTarget and not victimTarget then
		if not hordeSide then
			stats.refused = stats.refused + 1
			return false, "unlisted"
		end
		-- (Every proven side carries his GUID, and his entry is his GUID's alone: another entry
		-- under his name, pinned to another GUID, is another character (a made-up GUID a shared row
		-- named, a rename, a typed listing), and never keeps him off. Before, it did: "identity".)
		fresh = { key = hordeSide.key, name = hordeSide.name, realm = hordeSide.realm, guid = hordeSide.guid, active = true,
			addedAt = now, addedBy = peer and opts.from or CleanName(ns.me), source = peer and "shared" or kind, current = 0,
			lifetimeKills = 0, cycle = 1, openSince = now, victims = {}, claims = {}, victimOverflow = 0 }
		if opts.horde == "killer" then killerTarget = fresh else victimTarget = fresh end
	end
	local action, target, olympian
	if killerTarget then action, target, olympian = "bounty", killerTarget, victim
	else action, target, olympian = "claim", victimTarget, killer end
	-- The proven Horde side is the one the row is about: an Olympian found on the list instead is
	-- no Horde player's entry.
	if opts.horde and (opts.horde == "killer") ~= (action == "bounty") then
		stats.refused = stats.refused + 1
		return false, "ambiguous"
	end
	if not target.active then
		stats.refused = stats.refused + 1
		return false, "removed"
	end
	-- (A shared row's sender was verified as a member when it was taken: Share.Take.)
	if not peer and not VerifiedOlympian(olympian) then
		stats.refused = stats.refused + 1
		return false, "olympus"
	end
	-- (1.2.3: a kill with no open bounty pays his level now, Bounty.Claim.)
	local worth = Bounty.Fields(opts.bounty)
	if action == "claim" and (target.current > 0 or worth and worth.hl > 0) and not ResolveSlayer(s, killer, false, false)
		and Count(s.slayers) >= Wanted.MAX_SLAYERS then return false, "slayers" end
	local id = peer and opts.id or EvidenceId(kind, rawId, killer, victim)
	local fingerprint = table.concat({ killer.guidKey or killer.nameKey, victim.guidKey or victim.nameKey, tostring(math.floor(now / 3)) }, ">")
	if s.seen[id] or s.recent[fingerprint] and math.abs(now - s.recent[fingerprint]) <= 5 then
		stats.replay = stats.replay + 1
		return false, "replay"
	end
	local death = SameDeath(s, killer, victim, now)
	if death == "replay" then stats.replay = stats.replay + 1 return false, "replay" end
	if death == "conflict" then stats.conflict = stats.conflict + 1 return false, "conflict" end
	if dated and Share.Late(s, now) then stats.refused = stats.refused + 1 return false, "late" end
	if not peer and not RateAllowed(math.floor(Clock())) then stats.refused = stats.refused + 1 return false, "rate" end
	if fresh then
		Share.MakeRoom(s)
		s.targets[fresh.key] = fresh
		if hordeSide.guidKey then s.aliases[hordeSide.guidKey] = fresh.key end
		Share.Name(s, fresh, hordeSide, opts.wire == true)
	end
	local learned
	if action == "bounty" then learned = ResolveTarget(s, killer, true, killerWire)
	else learned = ResolveTarget(s, victim, true, victimWire) end
	if not learned or learned ~= target then
		if fresh and s.targets[fresh.key] == fresh then Share.Drop(s, fresh.key) end
		return false, "identity"
	end
	target = learned
	if #s.evidence >= Wanted.MAX_EVIDENCE then Checkpoint(s) end
	s.seq = s.seq + 1
	local e = { id = id, seq = s.seq, at = now, month = peer and opts.month or MonthNow(), kind = kind, action = action,
		targetKey = target.key, killerName = killer.name, killerGuid = killer.guid, victimName = victim.name, victimGuid = victim.guid,
		zone = opts.zone, mapID = Whole(opts.mapID, 1, 9999999), precision = opts.precision, from = peer and opts.from or CleanName(ns.me),
		peer = peer or nil, own = opts.own == true or nil, earlier = earlier or nil,
		-- Own rows are native observations. A received row retains whether membership was proven
		-- independently; false rows remain visible locally but cannot contribute to a signed board.
		memberVerified = not peer or opts.memberVerified == true }
	if worth then e.office, e.ml, e.hl, e.hf = worth.office, worth.ml, worth.hl, worth.hf or nil end
	-- (1.2.4 repair: a member's claim keeps the guild its row named, for the avenged notice's words
	-- when a death before it is heard after it: Bounty.Grieve.)
	if peer then e.guild = Clean(opts.guild, 48) end
	e.digest = peer and opts.digest or Digest(table.concat({ e.id, e.at, e.kind, e.action, e.killerGuid or "", e.victimGuid or "" }, "|"))
	Remember(s, id, fingerprint, now, e.seq)
	-- In the order of the deaths: a shared row may come after a later one (a relay, a catch-up),
	-- and then the totals are built again, so that every client holding the same rows counts them
	-- the same (and rows of one second in the same order everywhere: Share.Before).
	local at = #s.evidence + 1
	while at > 1 and Share.Before(e, s.evidence[at - 1]) do at = at - 1 end
	table.insert(s.evidence, at, e)
	if at < #s.evidence then
		Rebuild(s)
	elseif not ApplyEvidence(s, e) then
		e.void = true
		Rebuild(s)
		return false, "bounds"
	end
	stats.accepted = stats.accepted + 1
	Changed()
	-- (1.2.4: what the row tells its members: an own death kept for the avenged notice, a claim's
	-- avenged notices, an own kill's Slayer letter: the section "The notices" below.)
	Bounty.Recorded(s, e)
	return true, e
end

-- The combat-log adapter accepts only PARTY_KILL, whose payload names both sides. UNIT_DIED and
-- damage rows never identify a killer reliably and are intentionally ignored. Nothing registers
-- it on Forever (its combat log is restricted: see the registrations at the end); it stays the
-- ledger's adapter for a client that allows the combat log, and the tests'. Its rows carry no
-- faction proof, so one of their sides must already have an entry ("unlisted" otherwise), and
-- they are never shared.
function Wanted.CaptureCombatLog(...)
	local a = { ... }
	if #a == 0 and type(CombatLogGetCurrentEventInfo) == "function" then
		local ok, values = pcall(function() return { CombatLogGetCurrentEventInfo() } end)
		if not ok then return false, "api" end
		a = values
	end
	local timestamp, subevent, sourceGuid, sourceName, destGuid, destName = a[1], a[2], a[4], a[5], a[8], a[9]
	if Secret(timestamp, subevent, sourceGuid, sourceName, destGuid, destName) then return false, "secret" end
	if subevent ~= "PARTY_KILL" then return false, "event" end
	if not sourceGuid or not sourceName or not destGuid or not destName then return false, "identities" end
	local zone, mapID = Zone()
	return RecordKill("PARTY_KILL", tostring(timestamp or ""), { name = sourceName, guid = sourceGuid },
		{ name = destName, guid = destGuid }, { zone = zone, mapID = mapID, precision = "approximate" })
end

-- Native frame event, distinct from the CLEU subevent: UnitDocumentation.lua, PartyKill (Forever
-- 1.60.1's own API documentation): attackerGUID and targetGUID, nothing else, both secret while
-- unit identity is restricted (an unfinished PvP match). Only our own killing blow counts: another
-- party member's is his to share, and a pet's GUID is not ours. The victim needs no listing: his
-- Horde faction is proven here (Share.HordeOf) and the row makes his entry, then goes to every
-- member (Share.Send). Returns true and the row, or false and why, and the Horde player's name.
function Share.PartyKill(attackerGUID, targetGUID)
	if Secret(attackerGUID, targetGUID) then return false, "secret" end
	local attacker, victim = Guid(attackerGUID), Guid(targetGUID)
	if not attacker or not victim then return false, "identities" end
	local mine = UnitIdentity("player")
	if not mine or mine.guid ~= attacker then return false, "attacker" end
	if not ns.IsMember or ns.IsMember() ~= true then return false, "olympus" end
	if ns.faction == "Horde" then return false, "faction" end
	if InInstance() then return false, "instance" end
	local horde, why = Share.HordeOf(victim)
	if not horde then return false, why end
	-- (1.2.3: what the kill is worth, frozen here: his level on his corpse, Bounty.Capture.)
	local zone, mapID = Zone()
	local ok, e = RecordKill("PARTY_KILL", "native:" .. tostring(math.floor(Clock())), mine, horde,
		{ zone = zone, mapID = mapID, precision = "approximate", horde = "victim", own = true, bounty = Bounty.Capture(horde.guid) })
	if ok then Share.Send(e) end
	return ok, e, horde.name
end

function Wanted.CapturePartyKill(attackerGUID, targetGUID)
	local ok, e, who = Share.PartyKill(attackerGUID, targetGUID)
	-- (/oly wanted status: a kill of a player only, or a hidden one (a PvP match); every creature a
	-- party member kills fires it too.)
	if Secret(attackerGUID, targetGUID) or Guid(targetGUID) then
		Share.Note("kill", ok, e, who or (not ok and Share.InfoName(Guid(targetGUID))) or nil)
	end
	return ok, e
end

-- Forever's last-death reader: C_DeathRecap without a recap ID, as the game's own death dialog
-- and feedback form read it (GameDialogDefs.lua, Blizzard_PTRFeedback_Events.lua: the client's
-- UI source, 1.60.1). Its rows come newest first, and the first is the one that killed
-- (Blizzard_DeathRecap.lua: causedDeath = i == 1). HeadHunter's Forever probe (build 69913,
-- https://github.com/GudaAddons/HeadHunter/blob/main/Detection/ForeverDeaths.lua) gives the
-- rest: sourceName "Given-Realm" (no surname), sourceFlags, overkill 0 or more on the killing
-- blow and -1 on the others, timestamp in the server's seconds. The killing blow is the first
-- row with overkill 0 or more; it counts when it is recent, a damage event, a hostile player's
-- (flags 0x440, where the row has flags), with a player GUID whose Horde faction this client
-- proves (Share.HordeOf): no target, nameplate or listing is needed. Never the latest damage, a
-- pet's possible owner, or a death in an instance (a battleground, an arena). The victim is our
-- own verified player unit. Returns true and the row, or false and why, and the killer's name.
-- 1.2.3: the killing blow and its checks are Bounty.KillingBlow's and Bounty.Hostile's, which the
-- earlier deaths' reader shares; the death read now is marked read (Bounty.MarkRead: counted or
-- not, that reader never takes it again), and its row freezes what it is worth (Bounty.Capture).
local function ReadSelfDeathRecap()
	local recap = C_DeathRecap
	if type(recap) ~= "table" or type(recap.HasRecapEvents) ~= "function" or type(recap.GetRecapEvents) ~= "function" then return false, "recap" end
	local hasOK, has = pcall(recap.HasRecapEvents)
	if not hasOK or Secret(has) or has ~= true then return false, "recap" end
	local readOK, events = pcall(recap.GetRecapEvents)
	if not readOK or type(events) ~= "table" then return false, "recap" end
	local mine = UnitIdentity("player")
	local deadOK, dead = pcall(function() return UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") end)
	if not mine or not deadOK or Secret(dead) or dead ~= true then return false, "alive" end
	if ns.faction == "Horde" then return false, "faction" end
	local inside = InInstance()
	local now = math.floor(Clock())
	local kb, why, name = Bounty.KillingBlow(events)
	if not kb then return false, inside and "instance" or why, name end
	if kb.stamp < now - Wanted.DEATH_WINDOW or kb.stamp > now + 1 then return false, inside and "instance" or "stale", kb.name end
	-- (1.2.3: a row that names the victim names this player: Bounty.Mine.)
	local own, whose = Bounty.Mine(events, mine.guid, true)
	if not own then return false, whose, kb.name end
	-- (This death's own recap, whatever the answer below: an instance's too.)
	Bounty.MarkRead(kb)
	if inside then return false, "instance", kb.name end
	local horde, refusal = Bounty.Hostile(kb)
	if not horde then return false, refusal, kb.name end
	-- (Dated by its killing blow, not when it was read: RecordKill.)
	local zone, mapID = Zone()
	local ok, e = RecordKill("SELF_DEATH", "native:" .. tostring(kb.stamp), horde, mine,
		{ zone = zone, mapID = mapID, precision = "approximate", horde = "killer", own = true, at = kb.at, bounty = Bounty.Capture(horde.guid) })
	-- (1.2.4: and the toast, at the death: a retry's second reading is a replay, so once a death.)
	if ok then Share.Send(e) Bounty.DeathToast(e) end
	return ok, e, horde.name
end

-- A reviewer voids one row he finds wrong (the King, a signed High Councillor or the author:
-- Wanted.CanRemove), with a reason: here, and on every client through his word (WV), as long as
-- the row is still live (not yet folded into the base: Checkpoint).
function Wanted.Correct(id, reason)
	if not Wanted.CanRemove() then return false, "access" end
	id = Clean(id, 160)
	if not id then return false, "id" end
	local s = Store(false)
	for _, e in ipairs(s and s.evidence or {}) do
		if e.id == id and not e.void then
			e.void, e.correctedAt, e.correctedBy, e.correction = true, math.floor(Clock()), CleanName(ns.me), Clean(reason, 80)
			Audit(s, "correct", e.targetKey, id)
			Share.KeepVoid(s, e.from, e.digest, e.correctedAt)
			Rebuild(s)
			stats.corrected = stats.corrected + 1
			if e.from and e.digest then Share.SendMark("V", e.from, e.digest) end
			Changed()
			return true
		end
	end
	return false, "expired"
end

-- A voided shared row remembered (VOIDS_MAX, the oldest go), so that a copy heard later is
-- refused too: [folded sender#digest] = { at = when, from, digest }.
function Share.KeepVoid(s, from, digest, at)
	from = CleanName(from)
	if not from or type(digest) ~= "string" then return end
	s.voids[ns.Fold(from) .. "#" .. digest] = { at = Whole(at, 0, 4294967295) or 0, from = from, digest = digest }
	local n = Count(s.voids)
	while n > Wanted.VOIDS_MAX do
		local oldest
		for key, v in pairs(s.voids) do if not oldest or (v.at or 0) < (s.voids[oldest].at or 0) then oldest = key end end
		s.voids[oldest], n = nil, n - 1
	end
end

local function PublicTarget(t)
	if type(t) ~= "table" then return nil end
	return { key = t.key, name = t.name, realm = t.realm, guid = t.guid, active = t.active == true, addedAt = t.addedAt,
		addedBy = t.addedBy, source = t.source, removedAt = t.removedAt, removedBy = t.removedBy,
		current = t.current or 0, lifetimeKills = t.lifetimeKills or 0, cycle = t.cycle or 1,
		openSince = t.openSince, lastDeath = t.lastDeath, lastSighting = t.lastSighting and CopyList({ t.lastSighting }, 1)[1] or nil,
		victimOverflow = t.victimOverflow or 0, victimKillOverflow = t.victimKillOverflow or 0,
		victims = CopyList(t.victims, Wanted.MAX_VICTIMS), claims = CopyList(t.claims, Wanted.MAX_CLAIMS) }
end

function Wanted.Target(value, guid, realm)
	local s, ident = Store(false), Identity(value, guid, realm)
	local t = s and ResolveTarget(s, ident, false)
	return PublicTarget(t)
end

-- 1.2.4 (the author's report: "many with 0 points, 0 kills: with 0 points and 0 kills he should
-- not be on the Most Wanted list"): an entry is wanted, on the list, while it is on the ledger (not
-- taken off) with a bounty open or a kill of ours counted. A Horde player a member killed who
-- killed none of ours keeps his entry, off the list: it holds the claim, what it paid its Slayer and
-- the kill's gap, and its rows go to every member as before. So does one listed by hand before
-- 1.2.3 that never counted anything, and one whose rows a reviewer voided.
function Wanted.IsWanted(t)
	return type(t) == "table" and t.active == true
		and ((tonumber(t.current) or 0) > 0 or (tonumber(t.lifetimeKills) or 0) > 0)
end

-- The entries, in the list's order. activeOnly: true, those on the ledger (not taken off);
-- "listed" (1.2.4), the Most Wanted list itself, as its tab shows it (Wanted.IsWanted).
function Wanted.Targets(activeOnly)
	local s, out = Store(false), {}
	for _, t in pairs(s and s.targets or {}) do
		if not activeOnly or t.active and (activeOnly ~= "listed" or Wanted.IsWanted(t)) then out[#out + 1] = PublicTarget(t) end
	end
	table.sort(out, function(a, b)
		if a.active ~= b.active then return a.active end
		if a.current ~= b.current then return a.current > b.current end
		if a.lifetimeKills ~= b.lifetimeKills then return a.lifetimeKills > b.lifetimeKills end
		return tostring(a.name or a.guid or a.key) < tostring(b.name or b.guid or b.key)
	end)
	return out
end

local function Ranked(rows, month)
	local out = {}
	for _, r in pairs(type(rows) == "table" and rows or {}) do
		local points = month and (type(r.months) == "table" and r.months[month] or 0) or r.total
		if (tonumber(points) or 0) > 0 then
			out[#out + 1] = { key = r.key, name = r.name, guid = r.guid, points = points,
				claims = month and (r.monthClaims and r.monthClaims[month] or 0) or r.claims or 0,
				reachedAt = month and (r.monthAt and r.monthAt[month] or 0) or r.reachedAt or 0, lastAt = r.lastAt or 0,
				verifiedPoints = month and points or tonumber(r.verifiedTotal) or 0,
				verifiedClaims = month and (r.monthClaims and r.monthClaims[month] or 0) or tonumber(r.verifiedClaims) or 0,
				verifiedReachedAt = month and (r.monthAt and r.monthAt[month] or 0) or tonumber(r.verifiedReachedAt) or 0 }
		end
	end
	table.sort(out, function(a, b)
		if a.points ~= b.points then return a.points > b.points end
		if a.reachedAt ~= b.reachedAt then return a.reachedAt < b.reachedAt end
		return a.key < b.key
	end)
	for i, r in ipairs(out) do r.place = i end
	return out
end

function Wanted.Rankings(month)
	local s = Store(false)
	month = tonumber(month) or MonthNow()
	return { month = Ranked(s and s.slayers or {}, month), all = Ranked(s and s.slayers or {}, nil), monthNo = month }
end

---------------------------------------------------------------------------
-- The signed global top three
---------------------------------------------------------------------------

local function Scope()
	return Digest(tostring(ns.group or ns.realm or "?") .. "|" .. tostring(ns.faction or "?"))
end

local function SameName(a, b)
	return type(a) == "string" and type(b) == "string" and ns.Fold(ns.FullName(a)) == ns.Fold(ns.FullName(b))
end

-- Authority is derived every time from the current signed/pinned state. Preview/debug views never
-- count. Revoking the signed council list therefore removes a held snapshot on the next read.
function Wanted.CanPublish(name)
	name = CleanName(name)
	if not name or not ns.IsMember or ns.IsMember() ~= true then return false end
	local WC = ns.WatchChat
	if WC and WC.PowersBarred and WC.PowersBarred(name) then return false end
	local W = ns.Workshop
	if W and W.IsAuthorName and W.IsAuthorName(name) == true then return true end
	if ns.IsKingCharacter and ns.IsKingCharacter(name) == true then return true end
	if ns.IsHighCouncillor and ns.IsHighCouncillor(name) == true then return true end
	return false
end

local function WireGuid(guid)
	guid = Guid(guid)
	if not guid then return nil end
	local server, id = guid:match("^Player%-(%d+)%-(%x+)$")
	return server .. "." .. id:lower()
end

local function GameGuid(wire)
	if type(wire) ~= "string" or #wire > 24 then return nil end
	local server, id = wire:match("^(%d+)%.(%x+)$")
	if not server or #server > 7 or #id < 8 or #id > 16 or id:find("[A-F]") then return nil end
	return Guid("Player-" .. server .. "-" .. id)
end

local function CanonicalRows(rows)
	local out, seen = {}, {}
	for _, row in ipairs(type(rows) == "table" and rows or {}) do
		local guid = Guid(type(row) == "table" and row.guid)
		local points = Whole(type(row) == "table" and row.points, 1, Wanted.MAX_POINTS)
		local claims = Whole(type(row) == "table" and row.claims, 0, Wanted.MAX_POINTS)
		local reachedAt = Whole(type(row) == "table" and row.reachedAt, 0, 4294967295)
		if not guid or not points or not claims or not reachedAt or seen[guid] then return nil, "rows" end
		seen[guid] = true
		out[#out + 1] = { key = GuidKey(guid), guid = guid, points = points, claims = claims, reachedAt = reachedAt }
		if #out > Wanted.GLOBAL_ROWS then return nil, "rows" end
	end
	table.sort(out, function(a, b)
		if a.points ~= b.points then return a.points > b.points end
		if a.reachedAt ~= b.reachedAt then return a.reachedAt < b.reachedAt end
		return a.guid < b.guid
	end)
	return out
end

local function RowsText(rows)
	local out = {}
	for i, row in ipairs(rows) do
		local wire = WireGuid(row.guid)
		if not wire then return nil end
		out[i] = table.concat({ wire, row.points, row.claims, row.reachedAt }, ":")
	end
	return #out > 0 and table.concat(out, ",") or "-"
end

local function ReadRows(text)
	if text == "-" then return {} end
	if type(text) ~= "string" or text == "" or #text > 256 then return nil, "rows" end
	local rows = {}
	for item in text:gmatch("[^,]+") do
		local wire, points, claims, reachedAt = item:match("^([^:]+):(%d+):(%d+):(%d+)$")
		rows[#rows + 1] = { guid = GameGuid(wire), points = tonumber(points), claims = tonumber(claims), reachedAt = tonumber(reachedAt) }
	end
	return CanonicalRows(rows)
end

local function AuthorityWeight(name)
	local W = ns.Workshop
	if W and W.IsAuthorName and W.IsAuthorName(name) == true then return 3 end
	if ns.IsKingCharacter and ns.IsKingCharacter(name) == true then return 2 end
	return 1
end

-- Between publishers the newer word wins (its issue time), then the higher role, then a fixed
-- name order; the epoch and sequence come last, and one publisher's own words also follow his
-- pins (NewerSnapshot). (It was the epoch first: a publisher whose key generation began earlier,
-- the King say, could then never replace or revoke the word of a councillor who began later.)
local function Order(snapshot)
	return { snapshot.issued, AuthorityWeight(snapshot.issuer), ns.Fold(snapshot.issuer), snapshot.epoch, snapshot.seq }
end

local function CompareOrder(a, b)
	if not b then return 1 end
	for i = 1, 5 do
		if a[i] ~= b[i] then
			if i == 3 then return a[i] < b[i] and 1 or -1 end -- deterministic name tie-break
			return a[i] > b[i] and 1 or -1
		end
	end
	return 0
end

local function Fresh(snapshot, now)
	now = now or math.floor(Clock())
	return snapshot.issued <= now + Wanted.GLOBAL_SKEW and snapshot.expires >= now
		and snapshot.epoch <= snapshot.issued + Wanted.GLOBAL_SKEW
		and snapshot.expires > snapshot.issued and snapshot.expires - snapshot.issued <= Wanted.GLOBAL_LIFE
end

-- The saved copy of the word shown (this realm group and faction's store): its text, its issuer,
-- when it came, and the publishers' pins as they were then. Only RestoreGlobal reads it.
local function SaveGlobal(snapshot)
	local s = Store(true)
	if not s then return end
	s.global = { text = snapshot.text, issuer = snapshot.issuer, at = math.floor(Clock()), relay = snapshot.relay }
	local heads = {}
	for who, h in pairs(publisherHeads) do heads[who] = { epoch = h.epoch, seq = h.seq, pk64 = h.pk64 } end
	s.globalHeads = heads
end

local function ForgetGlobal(text)
	local s = Store(false)
	if s and type(s.global) == "table" and (text == nil or s.global.text == text) then s.global, s.globalHeads = nil, nil end
end

local function ClearGlobal(expired)
	local held = authenticatedGlobal
	authenticatedGlobal = nil
	-- The floor and per-publisher key pins protect only a currently valid word. Keeping them
	-- after that word expires, leaves this realm/faction, or loses its authority would let a
	-- revoked publisher strand every legitimate replacement until /reload.
	globalFloor, publisherHeads = nil, {}
	-- An expired word leaves the saved data too. One whose issuer does not hold the role now
	-- (the council's list may not have come yet) or of another realm group stays saved for
	-- RestoreGlobal to look at again; it shows nothing meanwhile.
	if expired and held then ForgetGlobal(held.text) end
	if held then Changed() end
	return held ~= nil
end

local function CurrentGlobal()
	local held = authenticatedGlobal
	if held then
		if not Fresh(held) then ClearGlobal(true)
		elseif not Wanted.CanPublish(held.issuer) or held.scope ~= Scope() then ClearGlobal(false) end
	end
	return authenticatedGlobal
end

-- A fresh own-guild roster, or independently verified federation membership; a guild claim
-- alone (VerifiedLevel's numeric fallback) is not evidence authority. guild (1.2.3): the guild a
-- shared row says its sender speaks for, when this client heard none of his own (M.GuildOf).
local function EvidenceMember(sender, guild)
	local R = ns.Roster
	if R and type(R.Fresh) == "function" and type(R.RankOf) == "function" then
		local ok, fresh = pcall(R.Fresh)
		if ok and fresh and R.RankOf(sender) ~= nil then return true end
	end
	local C, M = ns.Channels, ns.Moderation
	if type(C) ~= "table" or C.missing or type(C.VerifiedLevel) ~= "function" then return false end
	guild = M and M.GuildOf and M.GuildOf(sender) or guild
	if type(guild) ~= "string" or guild == "" or not (ns.IsFederation and ns.IsFederation(guild)) then return false end
	local ok, level, verified = pcall(C.VerifiedLevel, sender, guild)
	return ok and type(level) == "number" and level >= 1 and verified == true
end

-- (1.2.4) Who may speak for his own death or killing blow here (Share.Take): a member as the
-- [Olympus] chat takes one (Channels.VerifiedLevel 1 or more), plus whether he was proven.
-- Proven first (EvidenceMember: this client's own guild's fresh roster, a rank the census or the
-- signed manifest names). A plain member of another Olympus guild is in neither, and no client can
-- prove more of him: the game gives a player's guild only for a unit of his (GetGuildInfo), the
-- /who ask is a restricted call (C_FriendList.SendWho, HasRestrictions: Forever's
-- FriendListDocumentation.lua) and an addon message carries no guild (CHAT_MSG_ADDON:
-- ChatInfoDocumentation.lua). Until 1.2.4 every other client refused him for it, the reviewers'
-- too, so nothing was relayed and Most Wanted stayed empty. Now his own word counts as the chat's
-- does for the local ledger: for the Olympus guild the row names (guild, from Sight.GuildName),
-- his one guild
-- (Data.ClaimGuild: not another that his messages named within CLAIM_TTL, the signed manifest on
-- or not), never a guildmate of ours speaking for another guild, nor one our own roster lacks
-- naming ours (VerifiedLevel 0). A reviewer can still take off what such a member sends (WV).
function Share.Member(sender, guild)
	if EvidenceMember(sender, guild) then return true, true end
	if type(guild) ~= "string" or guild == "" then return false end
	local C, D = ns.Channels, ns.Data
	if type(C) ~= "table" or C.missing or type(C.VerifiedLevel) ~= "function" then return false end
	if type(D) == "table" and type(D.ClaimGuild) == "function" then
		local ok, bound = pcall(D.ClaimGuild, sender, guild)
		if not ok or not bound then return false end
	end
	local ok, level = pcall(C.VerifiedLevel, sender, guild)
	return ok and type(level) == "number" and level >= 1, false
end

-- Whether a player GUID is the sender's character: true or false when this client can name it
-- (a unit, or the game's cache of seen players), nil when it cannot.
local function GuidIsSender(guid, sender)
	local who = ns.Fold(ns.FullName(sender))
	local self = UnitIdentity("player")
	if self and self.guid == guid then return ns.Fold(ns.FullName(self.name)) == who end
	if type(UnitTokenFromGUID) == "function" then
		local ok, token = pcall(UnitTokenFromGUID, guid)
		if ok and type(token) == "string" and not Secret(token) then
			local unit = UnitIdentity(token)
			if unit and unit.guid == guid then return ns.Fold(ns.FullName(unit.name)) == who end
		end
	end
	-- Debts.InfoName is the existing guarded server GUID lookup (including clients that split
	-- character surnames into the realm field); it does not accept a packet's asserted name.
	local D = ns.Debts
	if D and type(D.InfoName) == "function" then
		local ok, name = pcall(D.InfoName, guid)
		if ok and type(name) == "string" and name ~= "" and not Secret(name) then return ns.Fold(ns.FullName(name)) == who end
	end
	if type(GetPlayerInfoByGUID) == "function" then
		local ok, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
		if ok and type(name) == "string" and name ~= "" and not Secret(name) and not Secret(realm) then
			return ns.Fold(ns.FullName(name, type(realm) == "string" and realm ~= "" and realm or nil)) == who
		end
	end
	return nil
end

-- 1.2.3: the top three this client would sign, as its own Slayers board counts it (every member's
-- shared kills and deaths it holds: Share.Take), all time, by verified GUID: a slayer this client
-- knows by his name alone (a member of another guild whose GUID it could not prove) is left out,
-- never awarded a frame by a name. No review: the rows counted as they came.
function Wanted.SignableRankings()
	local rows = {}
	for _, r in ipairs(Wanted.Rankings().all) do
		local points = Whole(r.verifiedPoints, 1, Wanted.MAX_POINTS)
		if Guid(r.guid) and points then
			rows[#rows + 1] = { guid = r.guid, points = points, claims = r.verifiedClaims or 0,
				reachedAt = r.verifiedReachedAt or 0 }
		end
	end
	table.sort(rows, function(a, b)
		if a.points ~= b.points then return a.points > b.points end
		if a.reachedAt ~= b.reachedAt then return a.reachedAt < b.reachedAt end
		return a.guid < b.guid
	end)
	while #rows > Wanted.GLOBAL_ROWS do table.remove(rows) end
	return CanonicalRows(rows) or {}
end

-- The Slayers ranked among the top three's places whom this client knows by name only, left out
-- of what it would sign (the frames page names them).
function Share.Unsignable()
	local out, signable = {}, 0
	for _, r in ipairs(Wanted.Rankings().all) do
		if signable >= Wanted.GLOBAL_ROWS or #out >= Wanted.GLOBAL_ROWS then break end
		if Guid(r.guid) then signable = signable + 1 else out[#out + 1] = r end
	end
	return out
end

local function ParseSnapshot(sender, text, relay)
	if type(text) ~= "string" or #text > 1200 then return nil, "size" end
	local version, scope, issuer, epoch, seq, issued, expires, rowsText, pk64, sig64 =
		text:match("^WY~(%d+)~(%x+)~([^~]+)~(%d+)~(%d+)~(%d+)~(%d+)~([^~]+)~([^~]+)~([^~]+)$")
	epoch, seq, issued, expires = tonumber(epoch), tonumber(seq), tonumber(issued), tonumber(expires)
	issuer = CleanName(issuer)
	if version ~= tostring(Wanted.SCORE_VERSION) or not issuer or not Whole(epoch, 1, Wanted.GLOBAL_MAX_EPOCH) or not Whole(seq, 1, Wanted.GLOBAL_MAX_SEQ)
		or not Whole(issued, 0, 4294967295) or not Whole(expires, 0, 4294967295) then return nil, "shape" end
	if scope ~= Scope() then return nil, "scope" end
	if not Wanted.CanPublish(issuer) or not Wanted.CanPublish(sender) or (not relay and not SameName(sender, issuer)) then return nil, "authority" end
	local rows, why = ReadRows(rowsText)
	if not rows then return nil, why end
	local D, Ed = ns.Debts, ns.Ed25519
	local pk = D and D.UnB64 and D.UnB64(pk64) or nil
	local sig = D and D.UnB64 and D.UnB64(sig64) or nil
	if not pk or #pk ~= 32 or not sig or #sig ~= 64 or not Ed or not Ed.ValidPublicKey or not Ed.ValidPublicKey(pk) then return nil, "signature" end
	local signed = table.concat({ "OLYW" .. Wanted.SCORE_VERSION, scope, issuer, epoch, seq, issued, expires, rowsText }, "|")
	return { scope = scope, issuer = issuer, epoch = epoch, seq = seq, issued = issued, expires = expires,
		rows = rows, rowsText = rowsText, pk = pk, pk64 = pk64, sig = sig, signed = signed, text = text, relay = relay and CleanName(sender) or nil }
end

-- These anchors are learned only after a direct issuer word's signature was verified. Neither
-- another reviewer's role nor a relay's globalHeads can introduce or rotate an issuer key.
function Wanted.IndependentlyPinned(snapshot)
	local s = Store(false)
	local pin = s and type(s.globalDirectPins) == "table" and s.globalDirectPins[ns.Fold(snapshot.issuer)]
	return type(pin) == "table" and Whole(pin.epoch, 1, Wanted.GLOBAL_MAX_EPOCH) == snapshot.epoch and pin.pk64 == snapshot.pk64
end

function Wanted.PinDirectGlobal(snapshot)
	if snapshot.relay then return false end
	local s = Store(true)
	if not s then return false end
	if type(s.globalDirectPins) ~= "table" then s.globalDirectPins = {} end
	local pins, key = s.globalDirectPins, ns.Fold(snapshot.issuer)
	if not pins[key] and Count(pins) >= Wanted.GLOBAL_DIRECT_PINS_MAX then
		local oldest, at
		for k, p in pairs(pins) do
			local t = type(p) == "table" and tonumber(p.at) or 0
			if not at or (t or 0) < at then oldest, at = k, t or 0 end
		end
		if oldest then pins[oldest] = nil end
	end
	pins[key] = { epoch = snapshot.epoch, pk64 = snapshot.pk64, at = math.floor(Clock()) }
	return true
end

local function NewerSnapshot(snapshot)
	local head = publisherHeads[ns.Fold(snapshot.issuer)]
	if head then
		if snapshot.epoch < head.epoch then return false, "rollback" end
		if snapshot.epoch == head.epoch and snapshot.seq <= head.seq then return false, "replay" end
		if snapshot.epoch == head.epoch and snapshot.pk64 ~= head.pk64 then return false, "key" end
	end
	if CompareOrder(Order(snapshot), globalFloor) <= 0 then return false, "rollback" end
	return true
end

-- The order (Order) of the word a WY body carries, read from its fields, or nil.
local function BodyOrder(body)
	if type(body) ~= "string" then return nil end
	local issuer, epoch, seq, issued = body:match("^WY~" .. Wanted.SCORE_VERSION .. "~%x+~([^~]+)~(%d+)~(%d+)~(%d+)~")
	if not issuer then return nil end
	return Order({ issued = tonumber(issued), issuer = issuer, epoch = tonumber(epoch), seq = tonumber(seq) })
end

-- A word this client checked that is newer than the one published here replaced ours for good:
-- ours is not repeated any more, after a reload neither. (A client that never heard the newer
-- word would take ours, the older, from the repeat: an issuer's revocation undone by another's
-- older word.)
local function NoteReplaced(snapshot)
	local p = publishedGlobal
	local mine = p and not p.replaced and BodyOrder(p.body)
	if not mine or CompareOrder(Order(snapshot), mine) <= 0 then return end
	p.replaced = true
	local last = type(ns.db) == "table" and type(ns.db.wantedPublisher) == "table" and ns.db.wantedPublisher.last or nil
	if type(last) == "table" and last.body == p.body then last.replaced = true end
end

local function Install(snapshot)
	globalFloor = Order(snapshot)
	authenticatedGlobal = snapshot
	NoteReplaced(snapshot)
	Changed()
	if ns.After then
		local held = snapshot
		ns.After(math.max(1, snapshot.expires - math.floor(Clock()) + 1), "wanted global expiry", function()
			if authenticatedGlobal == held and not Fresh(held) then ClearGlobal(true) end
		end)
	end
	return true
end

local function AcceptSnapshot(snapshot)
	-- Recheck every mutable trust input after the asynchronous Ed25519 job. In particular, a
	-- realm/faction transition while verification yielded must never install the old scope.
	if snapshot.scope ~= Scope() or not Fresh(snapshot) or not Wanted.CanPublish(snapshot.issuer) then return false, "stale" end
	if snapshot.relay and (not Wanted.CanPublish(snapshot.relay) or not Wanted.IndependentlyPinned(snapshot)) then return false, "unanchored" end
	local ok, why = NewerSnapshot(snapshot)
	if not ok then return false, why end
	publisherHeads[ns.Fold(snapshot.issuer)] = { epoch = snapshot.epoch, seq = snapshot.seq, pk64 = snapshot.pk64 }
	stats.globalAccepted = stats.globalAccepted + 1
	Wanted.PinDirectGlobal(snapshot)
	Install(snapshot)
	SaveGlobal(snapshot)
	return true
end

-- After a load, and again while no word is shown (a change of authority or realm group): the
-- saved word comes back only once its signature holds again under the key pinned for its
-- issuer, unexpired, of this realm group and faction, from someone who holds the role now. Its
-- order and pins hold while the signature is checked, so a live replay of an older word cannot
-- slip in meanwhile; a newer live word simply wins. Nothing else saved ever shows a frame.
local function RestoreGlobal()
	if authenticatedGlobal or restoring then return false, "held" end
	local s = Store(false)
	local saved = s and s.global
	if type(saved) ~= "table" then return false, "none" end
	local snapshot, why = ParseSnapshot(saved.issuer, saved.text)
	if not snapshot then
		-- Not a role holder here now, or another realm group's word: kept for a later look.
		if why ~= "authority" and why ~= "scope" then ForgetGlobal() end
		return false, why
	end
	if not Fresh(snapshot) then ForgetGlobal() return false, "stale" end
	-- A legacy saved word came directly from its issuer (the old protocol admitted no relays).
	-- Retain provenance for new relayed copies so restoration cannot turn them into direct pins.
	snapshot.relay = type(saved.relay) == "string" and saved.relay or nil
	if snapshot.relay and not Wanted.IndependentlyPinned(snapshot) then return false, "unanchored" end
	local pins = {}
	for who, h in pairs(type(s.globalHeads) == "table" and s.globalHeads or {}) do
		local epoch = type(h) == "table" and Whole(h.epoch, 1, Wanted.GLOBAL_MAX_EPOCH)
		local seq = type(h) == "table" and Whole(h.seq, 1, Wanted.GLOBAL_MAX_SEQ)
		if type(who) == "string" and epoch and seq and type(h.pk64) == "string" then pins[who] = { epoch = epoch, seq = seq, pk64 = h.pk64 } end
	end
	local pin = pins[ns.Fold(snapshot.issuer)]
	if not pin or pin.epoch ~= snapshot.epoch or pin.seq ~= snapshot.seq or pin.pk64 ~= snapshot.pk64 then
		ForgetGlobal()
		return false, "key"
	end
	local floor = Order(snapshot)
	globalFloor, publisherHeads, restoring = floor, pins, snapshot
	local function Done(valid)
		if restoring ~= snapshot then return false, "superseded" end
		restoring = nil
		restoreChecked[snapshot.text] = valid
		local current = not authenticatedGlobal and globalFloor == floor
		if valid and current and snapshot.scope == Scope() and Fresh(snapshot) and Wanted.CanPublish(snapshot.issuer)
			and (not snapshot.relay or Wanted.IndependentlyPinned(snapshot)) then
			stats.globalRestored = stats.globalRestored + 1
			Wanted.PinDirectGlobal(snapshot)
			return Install(snapshot)
		end
		if not valid then ForgetGlobal(snapshot.text) stats.globalRefused = stats.globalRefused + 1 end
		if current then globalFloor, publisherHeads = nil, {} end
		return false, valid and "stale" or "signature"
	end
	if restoreChecked[snapshot.text] ~= nil then return Done(restoreChecked[snapshot.text]) end
	local Ed = ns.Ed25519
	local started = Ed and Ed.Run and Ed.Verify and not (Ed.Busy and Ed.Busy() >= 40) and Ed.Run(function()
		return Ed.Verify(snapshot.pk, snapshot.signed, snapshot.sig)
	end, function(jobOk, valid) Done(jobOk and valid == true) end)
	if not started then
		if restoring == snapshot then restoring, globalFloor, publisherHeads = nil, nil, {} end
		return false, "busy"
	end
	return true, "pending"
end
Wanted.RestoreGlobal = RestoreGlobal

function Wanted.HandleGlobalSnapshot(dist, sender, text, relay)
	if dist ~= "CHANNEL" then stats.globalRefused = stats.globalRefused + 1 return false, "lane" end
	CurrentGlobal() -- expiry/revocation must release its ordering floor before a replacement arrives
	local snapshot, why = ParseSnapshot(sender, text, relay)
	if not snapshot or not Fresh(snapshot) then stats.globalRefused = stats.globalRefused + 1 return false, why or "stale" end
	if relay and not Wanted.IndependentlyPinned(snapshot) then stats.globalRefused = stats.globalRefused + 1 return false, "unanchored" end
	local ok
	ok, why = NewerSnapshot(snapshot)
	if not ok then
		if why == "replay" or why == "rollback" then stats.globalReplay = stats.globalReplay + 1 end
		stats.globalRefused = stats.globalRefused + 1
		return false, why
	end
	local digest = Digest(snapshot.signed .. snapshot.pk64 .. tostring(text:match("([^~]+)$") or ""))
	if not digest or pendingGlobal[digest] or pendingGlobalCount >= Wanted.GLOBAL_MAX_VERIFY then return false, pendingGlobal[digest] and "pending" or "busy" end
	local Ed = ns.Ed25519
	if not Ed or not Ed.Run or Ed.Busy and Ed.Busy() >= 40 then return false, "busy" end
	pendingGlobal[digest], pendingGlobalCount = snapshot, pendingGlobalCount + 1
	local started = Ed.Run(function() return Ed.Verify(snapshot.pk, snapshot.signed, snapshot.sig) end, function(jobOk, valid)
		pendingGlobal[digest], pendingGlobalCount = nil, math.max(0, pendingGlobalCount - 1)
		if jobOk and valid == true then
			local accepted, refused = AcceptSnapshot(snapshot)
			if not accepted then
				if refused == "replay" or refused == "rollback" then stats.globalReplay = stats.globalReplay + 1 end
				stats.globalRefused = stats.globalRefused + 1
			end
		else stats.globalRefused = stats.globalRefused + 1 end
	end)
	if not started then pendingGlobal[digest], pendingGlobalCount = nil, math.max(0, pendingGlobalCount - 1) return false, "busy" end
	return true, "pending"
end

function Wanted.HandleGlobalRelay(dist, sender, text)
	local prefix = "W5~" .. Wanted.SCORE_VERSION .. "~"
	if type(text) ~= "string" or text:sub(1, #prefix) ~= prefix then return false, "shape" end
	return Wanted.HandleGlobalSnapshot(dist, sender, text:sub(#prefix + 1), true)
end

-- Public, unchanged signed rankings only. A reply does not publish this client's observations
-- or ledger; it repeats precisely its already-verified current word, subject to all live roles.
function Wanted.AnswerGlobal(dist, sender, text)
	if dist ~= "CHANNEL" or text ~= "W4~1" then return false, "shape" end
	if SameName(sender, ns.me) then return false, "own" end
	if not Wanted.CanPublish(ns.me) then return false, "authority" end
	local held, C, now = CurrentGlobal(), ns.Comm, ns.Now()
	if not held then return false, "none" end
	if now - Wanted.globalCatch.replied < Wanted.GLOBAL_ASK_GAP then return false, "rate" end
	if not C or not C.SendChunked then return false, "transport" end
	local body = SameName(held.issuer, ns.me) and held.text or ("W5~" .. Wanted.SCORE_VERSION .. "~" .. held.text)
	local sent, why = C.SendChunked(body, false, nil, nil, { owner = Wanted, guardKey = "wanted-global-relay", guard = function()
		return Wanted.CanPublish(ns.me) and Wanted.CanPublish(held.issuer) and CurrentGlobal() == held and held.scope == Scope() and Fresh(held)
	end })
	if sent then Wanted.globalCatch.replied = now end
	return sent, why
end

function Wanted.AskGlobal()
	local C, now, scope = ns.Comm, ns.Now(), Scope()
	if not ns.IsMember or not ns.IsMember() then return false, "member" end
	if now - Wanted.globalCatch.asked < Wanted.GLOBAL_ASK_GAP then return false, "rate" end
	if not C or not C.Send then return false, "transport" end
	local sent, why = C.Send("CHANNEL", "W4~1", "wanted-global-ask", false, false, nil,
		{ owner = Wanted, guardKey = "wanted-global-ask", guard = function() return ns.IsMember() == true and Scope() == scope end })
	if sent then Wanted.globalCatch.asked = now end
	return sent, why
end

function Wanted.ScheduleGlobalCatchUp(generation, attempt)
	if not ns.After or generation ~= Wanted.globalCatch.generation or attempt > Wanted.GLOBAL_ASK_TRIES then return end
	ns.After(attempt == 1 and Wanted.GLOBAL_ASK_FIRST or Wanted.GLOBAL_ASK_GAP, "wanted global catch-up", function()
		if generation ~= Wanted.globalCatch.generation then return end
		Wanted.AskGlobal()
		Wanted.ScheduleGlobalCatchUp(generation, attempt + 1)
	end)
end

-- A publication's lease is its captured signed word, actor and realm/faction audience. Every
-- native chunk rechecks this same lease; queue admission never lets a replaced word escape.
function Wanted.PublicationGuard(p)
	local body, expires, issuer, scope = p.body, p.expires, p.issuer, p.scope
	local mine = BodyOrder(body)
	local signedScope, signedIssuer, signedExpires
	if type(body) == "string" then
		signedScope, signedIssuer, signedExpires = body:match("^WY~" .. Wanted.SCORE_VERSION .. "~(%x+)~([^~]+)~%d+~%d+~%d+~(%d+)~")
	end
	local fresh = mine and { issued = mine[1], epoch = mine[4], expires = expires }
	return function()
		return mine ~= nil and publishedGlobal == p and not p.replaced and p.body == body
			and p.expires == expires and p.issuer == issuer and p.scope == scope and scope == Scope()
			and signedScope == scope and signedIssuer == issuer and tonumber(signedExpires) == expires
			and SameName(issuer, ns.me) and Wanted.CanPublish(ns.me) and Wanted.CanPublish(issuer)
			and Fresh(fresh) and not (globalFloor and CompareOrder(globalFloor, mine) > 0)
	end
end

local function PublishRows(rows)
	if not Wanted.CanPublish(ns.me) then return false, "access" end
	rows = CanonicalRows(rows)
	if not rows then return false, "rows" end
	local D, C = ns.Debts, ns.Comm
	local _, pk
	if D and D.MyKey then _, pk = D.MyKey() end
	local Ed = ns.Ed25519
	if type(pk) ~= "string" or #pk ~= 32 or not Ed or not Ed.ValidPublicKey or not Ed.ValidPublicKey(pk)
		or not D.Sign or not D.B64 or not C or not C.SendChunked then return false, "key" end
	local now = math.floor(Clock())
	if type(ns.db) ~= "table" then return false, "store" end
	local p = type(ns.db.wantedPublisher) == "table" and ns.db.wantedPublisher or {}
	local pk64 = D.B64(pk)
	local epoch = Whole(p.epoch, 1, Wanted.GLOBAL_MAX_EPOCH) or math.min(now, Wanted.GLOBAL_MAX_EPOCH)
	-- A regenerated account key starts a new epoch automatically. Within one epoch receivers pin
	-- the first public key, so an edited packet cannot swap it underneath an accepted publisher.
	if type(p.pk64) == "string" and p.pk64 ~= pk64 then
		if epoch >= Wanted.GLOBAL_MAX_EPOCH then return false, "sequence" end
		epoch = math.max(epoch + 1, math.min(now, Wanted.GLOBAL_MAX_EPOCH))
	end
	if epoch > now + Wanted.GLOBAL_SKEW then return false, "epoch" end
	local seq = epoch == p.epoch and p.pk64 == pk64 and (tonumber(p.seq) or 0) + 1 or 1
	if seq > Wanted.GLOBAL_MAX_SEQ then return false, "sequence" end
	local rowsText, issuer, scope = RowsText(rows), CleanName(ns.me), Scope()
	local expires = now + Wanted.GLOBAL_LIFE
	local signed = table.concat({ "OLYW" .. Wanted.SCORE_VERSION, scope, issuer, epoch, seq, now, expires, rowsText }, "|")
	local sig = D.Sign(signed)
	if type(sig) ~= "string" or #sig ~= 64 then return false, "key" end
	p.epoch, p.seq, p.pk64 = epoch, seq, pk64
	ns.db.wantedPublisher = p
	local body = table.concat({ "WY", Wanted.SCORE_VERSION, scope, issuer, epoch, seq, now, expires, rowsText, pk64, D.B64(sig) }, "~")
	publishedGlobal = { body = body, expires = expires, issuer = issuer, scope = scope }
	local sent, why = C.SendChunked(body, true, nil, nil, { owner = Wanted, guardKey = "wanted-global", guard = Wanted.PublicationGuard(publishedGlobal) })
	if sent then
		-- Kept, so that after his next login the publisher repeats this same word (Wanted.Load).
		p.last = { body = body, expires = expires, issuer = issuer, scope = scope }
		if ScheduleGlobalRepeat then ScheduleGlobalRepeat(publishedGlobal) end
		-- Our own message never comes back to us (Comm drops our echo): the word is taken here as
		-- heard from ourselves, through every check another client makes, so that the publisher's
		-- own client shows it (or, a revocation, stops showing the frames) as everyone's does.
		Wanted.HandleGlobalSnapshot("CHANNEL", ns.me, body)
	end
	return sent, why
end

-- The server's "No player named ... is currently playing" (its pattern as Treasury reads it)
-- for a reviewer this client sends sightings to: he is not online, so his lease goes, and what
-- waits for him (SightingNotFound).
function Wanted.NotFound(text)
	if type(text) ~= "string" or Secret(text) or next(reviewers) == nil then return false end
	local T = ns.Treasury
	local pattern = T and T.NotFoundPattern and T.NotFoundPattern()
	local who = pattern and text:match(pattern)
	if not who then return false end
	return SightingNotFound ~= nil and SightingNotFound(who:lower()) == true
end

-- (Registered the first time a sighting goes, as the Arena's whispers do.)
local function WatchNotFound()
	if watchingNotFound then return end
	watchingNotFound = true
	pcall(ns.RegisterEvent, "CHAT_MSG_SYSTEM", function(text) Wanted.NotFound(text) end)
end

-- What this reviewer last published here (for his frames page), or nil.
function Wanted.LastPublished()
	local p = publishedGlobal
	if not p then
		local saved = type(ns.db) == "table" and type(ns.db.wantedPublisher) == "table" and ns.db.wantedPublisher.last or nil
		p = type(saved) == "table" and saved.scope == Scope() and SameName(saved.issuer, ns.me) and saved or nil
	end
	if not p or type(p.body) ~= "string" then return nil end
	local issued, expires, rowsText = p.body:match("^WY~" .. Wanted.SCORE_VERSION .. "~%x+~[^~]+~%d+~%d+~(%d+)~(%d+)~([^~]+)~")
	local rows = rowsText and ReadRows(rowsText) or nil
	return { issued = tonumber(issued), expires = tonumber(expires), rows = rows or {} }
end

-- The public publication path is deliberately tied to this client's own Slayers board
-- (Wanted.SignableRankings: every shared kill and death it counted, by verified GUID). An
-- authority may publish an empty board or use RevokeGlobal for an emergency removal, but no
-- caller can hand this API an arbitrary scoreboard.
function Wanted.PublishGlobal()
	return PublishRows(Wanted.SignableRankings())
end

function Wanted.RevokeGlobal()
	return PublishRows({})
end

-- Repeats the same signed word for late logins; it never extends its expiry or silently turns a
-- stale review into a fresh one. A caller/timer may invoke this while the publisher stays online.
-- A word replaced is not repeated: by a newer one this client checked (NoteReplaced), or by the
-- saved one it is checking again after a load (its floor is newer than ours).
function Wanted.RepeatGlobal()
	local p, C = publishedGlobal, ns.Comm
	local mine = p and BodyOrder(p.body)
	if not mine or p.expires < math.floor(Clock()) or not SameName(p.issuer, ns.me) or not Wanted.CanPublish(ns.me)
		or (p.scope and p.scope ~= Scope()) or not C or not C.SendChunked then return false, "stale" end
	if p.replaced or globalFloor and CompareOrder(globalFloor, mine) > 0 then return false, "replaced" end
	local sent, why = C.SendChunked(p.body, false, nil, nil, { owner = Wanted, guardKey = "wanted-global-repeat", guard = Wanted.PublicationGuard(p) })
	-- Heard from ourselves again where this client does not hold it (its check was busy when he
	-- published, say), as PublishRows does.
	if sent and not restoring and not (authenticatedGlobal and authenticatedGlobal.text == p.body) then
		Wanted.HandleGlobalSnapshot("CHANNEL", ns.me, p.body)
	end
	return sent, why
end

-- GLOBAL_BURST repeats GLOBAL_BURST_GAP apart, then one every GLOBAL_REPEAT_EVERY, for as long
-- as this word is the one published, has not expired and was not replaced (a tick while the role
-- is not known sends nothing and waits for the next one).
ScheduleGlobalRepeat = function(p, n)
	if not ns.After then return end
	n = n or 0
	ns.After(n < Wanted.GLOBAL_BURST and Wanted.GLOBAL_BURST_GAP or Wanted.GLOBAL_REPEAT_EVERY, "wanted global repeat", function()
		if publishedGlobal ~= p or p.replaced or p.expires < math.floor(Clock()) then return end
		if Wanted.CanPublish(ns.me) then Wanted.RepeatGlobal() end
		ScheduleGlobalRepeat(p, n + 1)
	end)
end

-- Pure deterministic assignment used by the future authoritative publication: the current
-- all-time first, second and third get distinct keys; everyone else is absent (revoked).
function Wanted.BorderAssignments(rows)
	local ranked = type(rows) == "table" and rows or {}
	local out = {}
	for i = 1, math.min(3, #ranked) do
		local r = ranked[i]
		if type(r) == "table" and type(r.key) == "string" then out[r.key] = "wanted-slayer-" .. i end
	end
	return out
end

-- 1.2.4: the slayers' frame is an honour (Honors' wanted-slayer-1/2/3: the skeletal horse, Honors.ArtOf;
-- the orc's wolf until then), and a player's pick decides it as any other's. Where this client knows his
-- pick (his own, or his profile heard: HonorsNet.PickKnown), nothing here: the honours show what it
-- shows (HonorsNet.Verified: "none", another frame he holds, the horse he picked; until 1.2.4 this frame
-- went over all of them). Only a slayer whose pick is unknown here wears it by his GUID, as before.
function Wanted.GlobalBorder(name, guid)
	if Wanted.GLOBAL_BORDERS_ACTIVE ~= true then return nil end
	local snapshot = CurrentGlobal()
	local key = GuidKey(guid)
	if not snapshot or not key then return nil end -- never award a global frame by a name alone
	local award = Wanted.BorderAssignments(snapshot.rows)[key]
	local H = ns.HonorsNet
	if award and type(H) == "table" and type(H.PickKnown) == "function" and H.PickKnown(name) == true then return nil end
	return award
end

function Wanted.GlobalSnapshot()
	local s = CurrentGlobal()
	if not s then return nil end
	return { issuer = s.issuer, epoch = s.epoch, seq = s.seq, issued = s.issued, expires = s.expires,
		rows = CopyList(s.rows, Wanted.GLOBAL_ROWS) }
end

function Wanted.Icon()
	local UI = ns.UI
	return UI and UI.FirstTexture and UI.FirstTexture(Wanted.ICON_PATHS) or Wanted.ICON_PATHS[#Wanted.ICON_PATHS]
end

-- A location sanction hides every Wanted location too. Historical combat evidence is still held
-- in the scoped ledger, but it is not rendered while this client may not see locations.
function Wanted.CanSeeLocations()
	if not ns.IsMember or ns.IsMember() ~= true or ns.faction == "Horde" then return false end
	local WC = ns.WatchChat
	if type(WC) == "table" and not WC.missing and type(WC.Barred) == "function" then
		local ok, barred = pcall(WC.Barred, "locations")
		if not ok or barred then return false end
	end
	return true
end

-- A stored sighting deliberately has a zone, not coordinates. Resolve that localised zone through
-- Zones; a fresh native observation already has the map the game supplied. Only zone/micro maps
-- are focusable, never a guessed continent or world map.
function Wanted.SightingMapID(sighting)
	if type(sighting) ~= "table" then return nil end
	local mapID = tonumber(sighting.mapID)
	if not mapID and type(sighting.zone) == "string" then
		local Z = ns.Zones
		if type(Z) == "table" and type(Z.KeyForName) == "function" and type(Z.MapID) == "function" then
			local okKey, key = pcall(Z.KeyForName, sighting.zone)
			local okMap, resolved = false, nil
			if okKey then okMap, resolved = pcall(Z.MapID, key) end
			if okMap then mapID = tonumber(resolved) end
		end
	end
	if not mapID or mapID < 1 or mapID ~= math.floor(mapID) or type(C_Map) ~= "table"
		or type(C_Map.GetMapInfo) ~= "function" then return nil end
	local ok, info = pcall(C_Map.GetMapInfo, mapID)
	if not ok or type(info) ~= "table" or Secret(info.mapType) then return nil end
	local T = type(Enum) == "table" and type(Enum.UIMapType) == "table" and Enum.UIMapType or {}
	if info.mapType ~= (T.Zone or 3) and info.mapType ~= (T.Micro or 5) then return nil end
	return mapID
end

-- Exact date plus age: an old sighting remains useful and is never silently hidden as "stale".
-- A live sighting's server time is translated to this client's clock only for ns.Ago.
function Wanted.SightingWhen(at, live)
	at = math.floor(tonumber(at) or 0)
	local dateFn = date or (os and os.date)
	local stamp = type(dateFn) == "function" and dateFn("%Y-%m-%d %H:%M", at) or tostring(at)
	local agoAt = live and (ns.Now() - math.max(0, math.floor(Clock()) - at)) or at
	return L.WANTED_SEEN_WHEN:format(stamp, ns.Ago(agoAt))
end

-- A separate, genuine in-game observation for this session. It is never inferred from an old
-- ledger row or an external service and expires with the existing 15-minute nearby pin.
function Wanted.LiveSighting(t)
	if not Wanted.CanSeeLocations() or type(t) ~= "table" or not Wanted.IsWanted(t) then return nil end
	local e = t.guid and pins[t.guid] or nil
	if not e and t.name then
		for _, candidate in pairs(pins) do if SameName(candidate.name, t.name) then e = candidate break end end
	end
	local now = math.floor(Clock())
	if type(e) ~= "table" or type(e.at) ~= "number" or e.at > now + Wanted.GLOBAL_SKEW
		or now - e.at > Wanted.SIGHT_TTL then return nil end
	return e
end

-- Newest truthful source: compare the native nearby observation with the permanent zone/time
-- carried by combat evidence. A combat row can arrive after a nearby observation and must not be
-- hidden merely because the older pin is still alive. Neither path manufactures coordinates.
function Wanted.LastSeen(t)
	if not Wanted.CanSeeLocations() or type(t) ~= "table" then return nil end
	local old, live = t.lastSighting, Wanted.LiveSighting(t)
	if type(old) == "table" and type(old.at) == "number" and (not live or old.at > live.at) then
		return { source = "ledger", at = old.at, zone = old.zone, precision = old.precision, evidence = old.evidence, mapID = old.mapID }
	end
	if live then
		local zone
		if type(C_Map) == "table" and type(C_Map.GetMapInfo) == "function" then
			local ok, info = pcall(C_Map.GetMapInfo, live.mapID)
			zone = ok and type(info) == "table" and not Secret(info.name) and info.name or nil
		end
		return { source = "native", at = live.at, zone = zone or (old and old.zone) or L.WANTED_UNKNOWN,
			mapID = live.mapID, x = live.x, y = live.y, observer = live.observer, nearby = true }
	end
	return nil
end

function Wanted.CanOpenSighting(sighting) -- gp:wanted-map
	if not Wanted.CanSeeLocations() or InInstance() or ns.db and ns.db.showWanted == false then return nil end
	local G = ns.Gate
	if type(G) == "table" and type(G.Allowed) == "function" then
		local ok, allowed = pcall(G.Allowed, "wanted-map")
		if not ok or allowed ~= true then return nil end
	end
	if type(WorldMapFrame) ~= "table" or type(WorldMapFrame.SetMapID) ~= "function"
		or type(ShowUIPanel) ~= "function" then return nil end
	return Wanted.SightingMapID(sighting)
end

function Wanted.OpenSightingMap(sighting) -- gp:wanted-map
	local G = ns.Gate
	if type(G) == "table" and type(G.Allowed) == "function" then
		local ok, allowed = pcall(G.Allowed, "wanted-map")
		if not ok or allowed ~= true then return false end
	end
	local mapID = Wanted.CanOpenSighting(sighting)
	if not mapID then return false end
	local shown = pcall(ShowUIPanel, WorldMapFrame)
	local focused = shown and pcall(WorldMapFrame.SetMapID, WorldMapFrame, mapID)
	if not focused then return false end
	historyFocus = mapID
	Wanted.RefreshPins()
	return true
end

function Wanted.LocationTip(tt, t, seen)
	if type(tt) ~= "table" or type(seen) ~= "table" then return false end
	local shown = t.name and ((ns.DisplayName and ns.DisplayName(t.name)) or ns.ShortName(t.name) or t.name) or L.WANTED_UNKNOWN
	tt:AddLine(shown, 1, 0.82, 0)
	tt:AddLine(L.WANTED_LAST_SEEN_TIP:format(seen.zone or L.WANTED_UNKNOWN,
		Wanted.SightingWhen(seen.at, seen.source == "native")), 1, 1, 1, true)
	if seen.source == "native" then tt:AddLine(L.WANTED_SIGHT_NEARBY, 0.65, 0.65, 0.65, true)
	else tt:AddLine(L.WANTED_ZONE_ONLY, 0.65, 0.65, 0.65, true) end
	if Wanted.CanOpenSighting(seen) then tt:AddLine(L.WANTED_SHOW_ON_MAP_TIP, 1, 0.82, 0, true) end
	return true
end

function Wanted.LocationLine(t, indent)
	local seen = Wanted.LastSeen(t)
	if not seen then return nil end
	local precision = seen.nearby and L.WANTED_NEARBY
		or (seen.precision == "consented" and L.WANTED_CONSENTED or L.WANTED_APPROXIMATE)
	local canOpen = Wanted.CanOpenSighting(seen) ~= nil
	return { id = "wanted-location:" .. tostring(t.key), indent = indent or 1,
		text = "|cff9d9d9d" .. L.WANTED_LAST_SIGHTING:format(seen.zone or L.WANTED_UNKNOWN, precision,
			Wanted.SightingWhen(seen.at, seen.source == "native")) .. "|r",
		right = canOpen and ("|cffffd200" .. L.WANTED_SHOW_ON_MAP .. "|r") or nil,
		onClick = canOpen and function() return Wanted.OpenSightingMap(seen) end or nil,
		tooltip = function(tt) return Wanted.LocationTip(tt, t, seen) end }
end

local function Grey(s) return "|cff9d9d9d" .. tostring(s or "") .. "|r" end
local function Gold(s) return "|cffffd200" .. tostring(s or "") .. "|r" end
local function Green(s) return "|cff40ff40" .. tostring(s or "") .. "|r" end
local PLACE = { "|cffffd200#1|r", "|cffc7c7cf#2|r", "|cffb07a45#3|r" }

local function Display(identity)
	return identity.name and ((ns.DisplayName and ns.DisplayName(identity.name)) or ns.ShortName(identity.name) or identity.name)
		or L.WANTED_UNKNOWN
end

local function EvidenceLabel(kind)
	return kind == "PARTY_KILL" and L.WANTED_EVIDENCE_PARTY or kind == "SELF_DEATH" and L.WANTED_EVIDENCE_RECAP or L.WANTED_UNKNOWN
end

-- (1.2.4: the open cycle's deaths and how many counted, when one did not: the same member again
-- inside the corpse-camping gap, Bounty.Death. The minutes are the gap's.)
local function Repeats(t)
	local counted = t.victimKillOverflow or 0
	for _, v in ipairs(t.victims) do if not v.again then counted = counted + 1 end end
	local deaths = #t.victims + (t.victimOverflow or 0)
	if counted == deaths then return nil end
	return L.WANTED_REPEATS:format(deaths, counted, math.floor(Bounty.SCORE.REPEAT_GAP / 60))
end

local function TargetTip(t)
	return function(tt)
		tt:AddLine(Display(t), 1, 0.82, 0)
		tt:AddLine(L.WANTED_BOUNTY:format(t.current), 1, 1, 1)
		tt:AddLine(L.WANTED_LIFETIME:format(t.lifetimeKills), 0.8, 0.8, 0.8)
		local repeats = Repeats(t)
		if repeats then tt:AddLine(repeats, 0.8, 0.8, 0.8, true) end
		local seen = Wanted.LastSeen(t)
		if seen then
			local precision = seen.nearby and L.WANTED_NEARBY
				or (seen.precision == "consented" and L.WANTED_CONSENTED or L.WANTED_APPROXIMATE)
			tt:AddLine(L.WANTED_LAST_SIGHTING:format(seen.zone or L.WANTED_UNKNOWN, precision,
				Wanted.SightingWhen(seen.at, seen.source == "native")), 0.8, 0.8, 0.8, true)
		end
		for _, v in ipairs(t.victims) do
			local line = L.WANTED_VICTIM_TIP:format(v.name and (ns.DisplayName(v.name) or v.name) or L.WANTED_UNKNOWN,
				v.zone or L.WANTED_UNKNOWN, EvidenceLabel(v.evidence), ns.Ago(v.at))
			if v.again then tt:AddLine(line .. " · " .. L.WANTED_AGAIN_SHORT, 0.6, 0.6, 0.6, true)
			else tt:AddLine(line, 1, 1, 1, true) end
		end
		if t.victimOverflow > 0 then tt:AddLine(L.WANTED_MORE_EVIDENCE:format(t.victimOverflow), 0.7, 0.7, 0.7) end
	end
end

function Wanted.OpenTarget(value, guid, realm)
	local s, ident = Store(false), Identity(value, guid, realm)
	local t = s and ResolveTarget(s, ident, false)
	if not t then return false end
	mode, opened = "target", t.key
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
	return true
end

-- The frames page (the King, a signed High Councillor or the author): the top three he would
-- sign from his own Slayers board, and his last word.
function Wanted.OpenReview()
	if not Wanted.CanPublish(ns.me) then return false end
	mode, opened = "review", nil
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
	return true
end

function Wanted.RulesAllowed()
	return ns.IsMember ~= nil and ns.IsMember() == true
end

function Wanted.OpenRules()
	if not (Wanted.Rules and Wanted.RulesAllowed()) then return false end
	Wanted.rulesReturn = { mode = mode, opened = opened }
	mode, opened = "rules", nil
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
	return true
end

function Wanted.CloseRules()
	local back = Wanted.rulesReturn
	Wanted.rulesReturn = nil
	if Wanted.RulesAllowed() and type(back) == "table" then
		mode, opened = back.mode or "list", back.opened
	else
		mode, opened = "list", nil
	end
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
	return true
end

function Wanted.Back()
	if mode == "list" then return false end
	if mode == "rules" then return Wanted.CloseRules() end
	mode, opened = "list", nil
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
	return true
end

function Wanted.PageId()
	if mode == "target" then return "target:" .. tostring(opened) end
	if mode == "rules" then return "rules" end
	return mode == "review" and "review" or "list"
end

local function OpenSlayer(r)
	if not (r and r.name and ns.UI and ns.UI.ShowPerson) then return false end
	return ns.UI.ShowPerson({ name = ns.ShortName(r.name), realm = ns.RealmOf(r.name), source = "addon", at = r.lastAt })
end

-- A GUID as a name a person can read: what this client knows of it (its slayers, its targets,
-- the game's own lookup through Debts.InfoName), else the GUID itself.
local function GuidName(guid)
	guid = Guid(guid)
	if not guid then return L.WANTED_UNKNOWN end
	local s, key = Store(false), GuidKey(guid)
	local known = s and (s.slayers[s.slayerAliases[key] or key] or s.targets[s.aliases[key] or key]) or nil
	local name = type(known) == "table" and known.name or nil
	if not name then
		local D = ns.Debts
		local ok, info = false, nil
		if type(D) == "table" and type(D.InfoName) == "function" then ok, info = pcall(D.InfoName, guid) end
		name = ok and type(info) == "string" and info ~= "" and not Secret(info) and info or nil
	end
	return name and (ns.DisplayName and ns.DisplayName(name) or name) or guid
end

local function DaysLeft(expires)
	return math.max(0, math.ceil(((tonumber(expires) or 0) - Clock()) / 86400))
end

local function IssuerName(name) return ns.DisplayName and ns.DisplayName(name) or name end

-- Each of the page's three long lists starts small enough that the next section remains visible in
-- the ordinary window. They open independently, ten more at a time; this is session UI state only
-- and never changes the ledger, its order or the signed board.
function Wanted.VisibleRows(kind, total)
	local shown = math.floor(tonumber(Wanted.listShown[kind]) or Wanted.LIST_FIRST)
	return math.min(math.max(0, tonumber(total) or 0), math.max(Wanted.LIST_FIRST, shown))
end

-- Expanding a ranking is useful only while reading this visit to Most Wanted. There is no collapse
-- affordance in the compact page, so leaving the outer tab restores its three short previews.
function Wanted.CollapseLists()
	Wanted.listShown.wanted = Wanted.LIST_FIRST
	Wanted.listShown.month = Wanted.LIST_FIRST
	Wanted.listShown.all = Wanted.LIST_FIRST
end

function Wanted.MoreLine(lines, kind, id, total)
	local shown = Wanted.VisibleRows(kind, total)
	if shown >= total then return false end
	lines[#lines + 1] = { id = id, indent = 1,
		text = Grey(L.SHOW_MORE:format(math.min(Wanted.LIST_PAGE, total - shown), shown, total)),
		onClick = function()
			Wanted.listShown[kind] = shown + Wanted.LIST_PAGE
			if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
		end }
	return true
end

local function RankingLines(lines, title, rows, kind)
	lines[#lines + 1] = { header = true, text = title }
	if #rows == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_NO_SLAYERS) } return end
	for i = 1, Wanted.VisibleRows(kind, #rows) do
		local r = rows[i]
		lines[#lines + 1] = { indent = 1, key = r.key, player = r.name,
			text = (PLACE[i] or ("#" .. i)) .. "  " .. (r.name and (ns.DisplayName(r.name) or r.name) or L.WANTED_UNKNOWN),
			right = L.WANTED_POINTS:format(r.points), onClick = r.name and function() return OpenSlayer(r) end or nil,
			tooltip = function(tt)
				tt:AddLine(r.name and (ns.DisplayName(r.name) or r.name) or L.WANTED_UNKNOWN, 1, 0.82, 0)
				tt:AddLine(L.WANTED_SLAYER_TIP:format(r.points, r.claims), 1, 1, 1, true)
			end }
	end
	Wanted.MoreLine(lines, kind, "slayers-" .. kind .. "-more", #rows)
end

-- The signed all-time top three this client holds (the one that sets the frames), if any.
local function SignedLines(lines)
	local g = Wanted.GlobalSnapshot()
	if not g then return false end
	lines[#lines + 1] = { header = true, text = L.WANTED_SIGNED, right = Grey(L.WANTED_SIGNED_BY:format(IssuerName(g.issuer), ns.Ago(g.issued))) }
	if #g.rows == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_SIGNED_EMPTY) } end
	for i, row in ipairs(g.rows) do
		local name = GuidName(row.guid)
		lines[#lines + 1] = { indent = 1, key = row.key, text = (PLACE[i] or ("#" .. i)) .. "  " .. name,
			right = L.WANTED_POINTS:format(row.points), tooltip = function(tt)
				tt:AddLine(name, 1, 0.82, 0)
				tt:AddLine(L.WANTED_SLAYER_TIP:format(row.points, row.claims), 1, 1, 1, true)
				tt:AddLine(L.WANTED_SIGNED_HELD:format(IssuerName(g.issuer), DaysLeft(g.expires)), 0.8, 0.8, 0.8, true)
			end }
	end
	lines[#lines].gapAfter = true
	return true
end

local function ListLines()
	local lines, targets = {}, Wanted.Targets("listed")
	lines[#lines + 1] = { header = true, text = L.WANTED_TARGETS, right = Grey(tostring(#targets)) }
	local rules = Wanted.Rules and Wanted.Rules.Link("wanted-slayers", Wanted.OpenRules)
	if rules then lines[#lines + 1] = rules end
	if #targets == 0 then lines[#lines + 1] = { text = Grey(L.WANTED_EMPTY) } end
	for i = 1, Wanted.VisibleRows("wanted", #targets) do
		local t = targets[i]
		lines[#lines + 1] = { id = "wanted:" .. t.key, key = t.key, text = Display(t),
			right = L.WANTED_ROW_COUNTS:format(t.current, t.lifetimeKills), onClick = function() return Wanted.OpenTarget(t) end,
			tooltip = TargetTip(t) }
		local location = Wanted.LocationLine(t, 1)
		if location then lines[#lines + 1] = location end
	end
	Wanted.MoreLine(lines, "wanted", "wanted-more", #targets)
	lines[#lines].gapAfter = true
	local signed = SignedLines(lines)
	-- This client's own two boards: what it observed, never everyone's ranking (only the signed
	-- top three above is that).
	local rank = Wanted.Rankings()
	local year, month = math.floor(rank.monthNo / 12), rank.monthNo % 12 + 1
	RankingLines(lines, L.WANTED_MONTHLY:format(year, month), rank.month, "month")
	lines[#lines].gapAfter = true
	RankingLines(lines, L.WANTED_LOCAL_ALL, rank.all, "all")
	if not signed then lines[#lines + 1] = { text = Grey(L.WANTED_AUTHORITY_OFF), gapAfter = true } end
	return lines
end

local function LiveEvidence(id)
	local s = Store(false)
	for _, e in ipairs(s and s.evidence or {}) do if e.id == id and not e.void then return true end end
	return false
end

-- A reviewer (Wanted.CanRemove) voids a row still live (not yet checkpointed), with a reason.
local function CorrectClick(id, label)
	if not (id and Wanted.CanRemove() and LiveEvidence(id)) then return nil end
	return function() return ns.ShowDialog("OLYMPUS_WANTED_CORRECT", label, nil, id) end
end

local function TargetLines()
	local s, t = Store(false), nil
	if s and opened then t = s.targets[s.aliases[opened] or opened] end
	if not t then mode, opened = "list", nil return ListLines() end
	t = PublicTarget(t)
	local lines = { { text = Gold(L.WANTED_BACK), onClick = Wanted.Back },
		{ header = true, text = Display(t), right = Wanted.IsWanted(t) and Green(L.WANTED_LISTED)
			or Grey(t.active and L.WANTED_NOT_WANTED or L.WANTED_REMOVED) },
		{ indent = 1, text = L.WANTED_GUID:format(t.guid or L.WANTED_UNKNOWN) },
		{ indent = 1, text = L.WANTED_BOUNTY:format(t.current), right = L.WANTED_LIFETIME:format(t.lifetimeKills) },
		{ indent = 1, text = L.WANTED_CYCLE:format(t.cycle, t.openSince and ns.Ago(t.openSince) or L.WANTED_UNKNOWN) },
	}
	-- (1.2.3: how he entered, by himself, and who took him off.)
	if t.addedAt and t.addedBy then
		lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_ENTERED:format(ns.Ago(t.addedAt), IssuerName(t.addedBy))) }
	end
	if not t.active and t.removedBy then
		lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_TAKEN_OFF:format(IssuerName(t.removedBy), t.removedAt and ns.Ago(t.removedAt) or L.WANTED_UNKNOWN)) }
	end
	local location = Wanted.LocationLine(t, 1)
	if location then lines[#lines + 1] = location end
	local observed = Wanted.LiveSighting(t)
	if observed then
		lines[#lines + 1] = { id = "wanted-observed:" .. tostring(t.key), indent = 1,
			text = Grey(L.WANTED_LAST_OBSERVED:format(Wanted.SightingWhen(observed.at, true))),
			tooltip = function(tt)
				tt:AddLine(L.WANTED_LAST_OBSERVED_LABEL, 1, 0.82, 0)
				tt:AddLine(L.WANTED_LAST_OBSERVED_TIP, 0.8, 0.8, 0.8, true)
			end }
	end
	lines[#lines + 1] = { header = true, text = L.WANTED_OPEN_CYCLE }
	if #t.victims == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_NO_VICTIMS) } end
	local repeats = Repeats(t)
	if repeats then lines[#lines + 1] = { indent = 1, text = Grey(repeats) } end
	local gap = math.floor(Bounty.SCORE.REPEAT_GAP / 60)
	for _, v in ipairs(t.victims) do
		local label = v.name and (ns.DisplayName(v.name) or v.name) or L.WANTED_UNKNOWN
		-- (1.2.3: what each death added to his bounty, Bounty.Death; 1.2.4: one inside the corpse-
		-- camping gap says it counted neither points nor a kill.)
		local right = v.again and L.WANTED_VICTIM_AGAIN:format(ns.Ago(v.at)) or L.WANTED_VICTIM_POINTS:format(tonumber(v.points) or 0, ns.Ago(v.at))
		lines[#lines + 1] = { indent = 1, text = label, right = Grey(right),
			onClick = CorrectClick(v.id, label),
			tooltip = function(tt)
				tt:AddLine(L.WANTED_EVIDENCE, 1, 0.82, 0)
				tt:AddLine(EvidenceLabel(v.evidence), 1, 1, 1, true)
				tt:AddLine(L.WANTED_LOCATION:format(v.zone or L.WANTED_UNKNOWN, v.precision == "consented" and L.WANTED_CONSENTED or L.WANTED_APPROXIMATE),
					0.8, 0.8, 0.8, true)
				if v.again then tt:AddLine(L.WANTED_VICTIM_AGAIN_TIP:format(gap), 0.8, 0.8, 0.8, true) end
			end }
	end
	if t.victimOverflow > 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_MORE_EVIDENCE:format(t.victimOverflow)) } end
	lines[#lines + 1] = { header = true, text = L.WANTED_CLAIMS }
	if #t.claims == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_NO_CLAIMS) } end
	for i = #t.claims, 1, -1 do
		local c = t.claims[i]
		local label = c.slayer and (ns.DisplayName(c.slayer) or c.slayer) or L.WANTED_UNKNOWN
		lines[#lines + 1] = { indent = 1, text = label, right = L.WANTED_CLAIM_POINTS:format(c.points or 0), onClick = CorrectClick(c.id, label),
			tooltip = function(tt)
				tt:AddLine(L.WANTED_CLAIM_TIP:format(c.points or 0, c.cycle or 0, EvidenceLabel(c.evidence), ns.Ago(c.at)), 1, 1, 1, true)
				-- (1.2.3: what it paid for: his level, his bounty, the revenge.)
				local level = tonumber(c.level) or 0
				tt:AddLine(L.WANTED_CLAIM_PARTS:format(level, Bounty.BasePoints(level), tonumber(c.bounty) or 0,
					c.revenge and Bounty.SCORE.REVENGE or 0), 0.8, 0.8, 0.8, true)
			end }
	end
	return lines
end

-- The frames page: the top three this reviewer would sign (Wanted.SignableRankings), the Slayers
-- left out of it for want of a verified GUID, and when he last published.
local function FramesLines()
	if not Wanted.CanPublish(ns.me) then mode, opened = "list", nil return ListLines() end
	local lines = { { text = Gold(L.WANTED_BACK), onClick = Wanted.Back } }
	lines[#lines + 1] = { header = true, text = L.WANTED_TO_PUBLISH }
	local rows = Wanted.SignableRankings()
	if #rows == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_NO_SLAYERS) } end
	for i, row in ipairs(rows) do
		lines[#lines + 1] = { indent = 1, key = row.key, text = (PLACE[i] or ("#" .. i)) .. "  " .. GuidName(row.guid),
			right = L.WANTED_POINTS:format(row.points) }
	end
	for _, r in ipairs(Share.Unsignable()) do
		lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_NO_GUID:format(r.name and (ns.DisplayName(r.name) or r.name) or L.WANTED_UNKNOWN)) }
	end
	local last = Wanted.LastPublished()
	lines[#lines + 1] = { indent = 1, text = Grey(last and last.issued and L.WANTED_LAST_PUBLISHED:format(ns.Ago(last.issued), DaysLeft(last.expires))
		or L.WANTED_NOT_PUBLISHED) }
	return lines
end

function Wanted.Build()
	if mode == "rules" then
		local lines = Wanted.Rules and Wanted.Rules.Lines("wanted-slayers", Wanted.CloseRules)
		if lines then return lines, L.WANTED_TITLE, L.WANTED_ABOUT end
		Wanted.rulesReturn = nil
		mode, opened = "list", nil
		return {}, L.WANTED_TITLE, L.WANTED_ABOUT
	end
	if mode == "review" then
		local lines = FramesLines()
		if mode == "review" then return lines, L.WANTED_REVIEW_TITLE, L.WANTED_REVIEW_ABOUT end
		return lines, L.WANTED_TITLE, L.WANTED_ABOUT
	end
	local lines = mode == "target" and TargetLines() or ListLines()
	local g = Wanted.GlobalSnapshot()
	local note = g and L.WANTED_SIGNED_HELD:format(IssuerName(g.issuer), DaysLeft(g.expires)) or L.WANTED_AUTHORITY_OFF
	return lines, L.WANTED_TITLE, L.WANTED_ABOUT .. "\n" .. Grey(note)
end

-- The entry open now, while it is on the list (a reviewer's Remove).
local function OpenedActive()
	local s = Store(false)
	local t = mode == "target" and s and opened and s.targets[s.aliases[opened] or opened]
	return type(t) == "table" and t.active == true and t or nil
end

local function PromptRemove()
	local t = Wanted.CanRemove() and OpenedActive()
	if not t then return false end
	return ns.ShowDialog("OLYMPUS_WANTED_REMOVE", Display(t), nil, t.key)
end

-- 1.2.3: the one reviewer this member's sightings are whispered to. He was the one the member sent
-- his evidence to; there is no evidence to send any more, so the member names him here: the King,
-- a signed High Councillor or the author, typed, or nobody (empty). Returns true, or false and why.
function Wanted.SetReviewer(name)
	name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if name == "" then
		local s = Store(false)
		if s then s.reviewer = nil end
		ns.Print(L.WANTED_REVIEWER_NONE)
		return true
	end
	local reviewer = CleanName(ns.FullName and ns.FullName(name) or name)
	if not reviewer or SameName(reviewer, ns.me) or not Wanted.CanPublish(reviewer) then return false, "reviewer" end
	local s = Store(true)
	if not s then return false, "store" end
	s.reviewer = reviewer
	ns.Print(L.WANTED_REVIEWER_SET:format(IssuerName(reviewer)))
	return true
end

local function PromptReviewer()
	if not Wanted.SightingsOn() then return false end
	return ns.ShowDialog("OLYMPUS_WANTED_REVIEWER")
end

local function RowsSummary(rows)
	local out = {}
	for i, row in ipairs(rows) do out[i] = ("#%d %s · %s"):format(i, GuidName(row.guid), L.WANTED_POINTS:format(row.points)) end
	return #out > 0 and table.concat(out, "\n") or L.WANTED_SIGNED_EMPTY
end

local function PromptPublish()
	if not Wanted.CanPublish(ns.me) then return false end
	return ns.ShowDialog("OLYMPUS_WANTED_PUBLISH", RowsSummary(Wanted.SignableRankings()))
end

local function PromptRevoke()
	if not Wanted.CanPublish(ns.me) then return false end
	return ns.ShowDialog("OLYMPUS_WANTED_REVOKE")
end

local function Failed(why) ns.Print(L.WANTED_ACTION_FAILED:format(tostring(why or "?"))) end

local function Focus(eb)
	if ns.Focus then ns.Focus(eb) elseif eb.SetFocus then eb:SetFocus() end
end

StaticPopupDialogs["OLYMPUS_WANTED_REMOVE"] = {
	text = L.WANTED_REMOVE_PROMPT, button1 = REMOVE or "Remove", button2 = CANCEL or "Cancel",
	OnAccept = function(self, key)
		key = key or (self and self.data)
		local s = Store(false)
		local t = s and s.targets[s.aliases[key] or key]
		local ok, why
		if t then ok, why = Wanted.RemoveTarget(t) else ok, why = false, "missing" end
		if not ok then ns.Print(L.WANTED_ACTION_FAILED:format(tostring(why or "?"))) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Sightings to: the reviewer typed (prefilled with the one chosen), or nobody.
StaticPopupDialogs["OLYMPUS_WANTED_REVIEWER"] = {
	text = L.WANTED_REVIEWER_PROMPT, button1 = L.WANTED_REVIEWER_ACCEPT, button2 = CANCEL or "Cancel", hasEditBox = true,
	editBoxWidth = 300, maxLetters = 72,
	-- (Focus: with the gamepad UI, never the keyboard taken from another box, the chat's.)
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		local s = Store(false)
		if eb then eb:SetText(s and s.reviewer and (ns.TellName(s.reviewer) or s.reviewer) or ""); Focus(eb) end
	end,
	OnAccept = function(self)
		local eb = self.editBox or self.EditBox
		local ok, why = Wanted.SetReviewer(eb and eb:GetText() or "")
		if not ok then Failed(why) end
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		local ok, why = Wanted.SetReviewer(self:GetText() or "")
		if not ok then Failed(why) end
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_WANTED_PUBLISH"] = {
	text = L.WANTED_PUBLISH_PROMPT, button1 = L.WANTED_PUBLISH_BTN, button2 = CANCEL or "Cancel",
	OnAccept = function()
		local ok, why = Wanted.PublishGlobal()
		if ok then ns.Print(L.WANTED_PUBLISHED) else Failed(why) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_WANTED_REVOKE"] = {
	text = L.WANTED_REVOKE_PROMPT, button1 = L.WANTED_REVOKE_BTN, button2 = CANCEL or "Cancel",
	OnAccept = function()
		local ok, why = Wanted.RevokeGlobal()
		if ok then ns.Print(L.WANTED_REVOKED) else Failed(why) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_WANTED_CORRECT"] = {
	text = L.WANTED_CORRECT_PROMPT, button1 = L.WANTED_CORRECT_BTN, button2 = CANCEL or "Cancel", hasEditBox = true,
	editBoxWidth = 300, maxLetters = 80,
	OnShow = function(self) local eb = self.editBox or self.EditBox if eb then eb:SetText(""); Focus(eb) end end,
	OnAccept = function(self, id)
		local eb = self.editBox or self.EditBox
		local ok, why = Wanted.Correct(id or (self and self.data), eb and eb:GetText() or "")
		if not ok then Failed(why) end
	end,
	EditBoxOnEnterPressed = function(self, id)
		local parent = self:GetParent()
		local ok, why = Wanted.Correct(id or (parent and parent.data), self:GetText() or "")
		if not ok then Failed(why) end
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- 1.2.3: no Add (Horde players enter by themselves), no Send evidence and no review: a reviewer's
-- Frames page (the top three he signs), his Remove on an entry, and a member's Sightings to.
local buttons = {
	{ "WANTED_BACK_BTN", Wanted.Back, shown = function() return mode ~= "list" end },
	{ "WANTED_REVIEW_BTN", Wanted.OpenReview, shown = function() return mode == "list" and Wanted.CanPublish(ns.me) end },
	{ "WANTED_REVIEWER_BTN", PromptReviewer, shown = function()
		return mode == "list" and ns.IsMember ~= nil and ns.IsMember() == true and ns.faction ~= "Horde" and Wanted.SightingsOn()
	end },
	{ "WANTED_REMOVE_BTN", PromptRemove, shown = function() return mode == "target" and Wanted.CanRemove() and OpenedActive() ~= nil end },
	{ "WANTED_PUBLISH_BTN", PromptPublish, shown = function() return mode == "review" and Wanted.CanPublish(ns.me) end },
	{ "WANTED_REVOKE_BTN", PromptRevoke, shown = function() return mode == "review" and Wanted.CanPublish(ns.me) end },
}
Wanted.buttons = buttons -- (tests)

---------------------------------------------------------------------------
-- Most Wanted sightings
--
-- A sighting is what this client saw itself: a Horde player on its own Most Wanted list (1.2.3:
-- every Horde player who killed or was killed by a member it heard of, by himself), by his name
-- and GUID as the game gives them (a secret value is refused), and where this player stood then:
-- his own map position, rounded to SIGHT_GRID thousandths of the map, and his layer when Layers
-- knows it. "Seen nearby": never the Horde player's own coordinates. Off until the member's own
-- Yes on its line of the privacy page (1.2.0), off again by his No (/oly sightings off), which
-- stops collecting, cancels what waits in Comm and takes back what reached a reviewer, at once.
-- Nothing goes while he keeps his zone and layer private (Layers.Sharing). The King's position is
-- his crown on the map (King.SharingLocation, as for his layer): while it is hidden his client
-- sends none, and hiding it takes back what went. Nothing is collected in an instance, nor by a
-- client the moderators took off (net-off).
-- It shows on this client's own map, and goes to the one reviewer (the King, a signed High
-- Councillor, the author) the member chose (Sightings to on the Most Wanted page:
-- Wanted.SetReviewer; until 1.2.3, the one he sent his evidence to), by whisper only, never on
-- the channel, and only while that reviewer's client says it takes sightings (its lease: no place
-- in it); a member who chose nobody sends his sightings to nobody. SIGHT_SEND_MAX a window from
-- this client, each Horde player once per SIGHT_GAP.
-- Comm checks each whisper again when it leaves (the No, net-off, the crown, the reviewer's
-- lease, its age).
--   WS~R~1                                                             channel: a reviewer's lease
--   WS~R~0                                                             channel: his No (lease off)
--   WS~S~1~<guild>~<id>~<at>~<map>~<x>~<y>~<layer>~<guid>~<name>       whisper: one sighting
--   WS~X~1                                                             whisper: the sender's taken back
-- A reviewer takes one only while his own sightings are on, from a member of an Olympus guild (as
-- the Olympus chats verify one), fresh (SIGHT_TTL, GLOBAL_SKEW), once (its id, per sender),
-- SIGHT_RECV_MAX a window from one sender and SIGHT_INTAKE_MAX from all (counted before anything
-- is parsed). A client without WS (1.1.4, or 1.2 before it) ignores every one of these words.
-- A pin is one Horde player where he was seen last, SIGHT_TTL long, SIGHT_PINS at most; its hover
-- says his name, his kills by this client's Most Wanted ledger, how long ago and by whom. Nothing
-- of it is saved. Pins follow the map rules of Olympus's other icons: on the world map only with
-- mouse and keyboard (ns.WorldMapIcons), on the minimap always, for members only, none while this
-- player is in an instance.
---------------------------------------------------------------------------

-- (1.2.0: off until the member's own Yes on its line.)
local function SightingsOn() return type(ns.db) == "table" and ns.db.wantedSightings == true end
Wanted.SightingsOn = SightingsOn
-- (The section's helpers: Wanted.lua's main chunk is near Lua's 200 locals.)
local Sight = {}
Sight.historyFrames, Sight.historySpare = {}, {}

-- A session-only sighting changes only the Wanted page. Redraw it when it is actually open;
-- the 15-second pin beat otherwise stays silent and cannot create a UI refresh loop.
function Sight.RefreshPage()
	local U = ns.UI
	if type(U) ~= "table" or type(U.RefreshSoon) ~= "function"
		or type(U.IsShown) ~= "function" or type(U.PageId) ~= "function" then return false end
	local okShown, shown = pcall(U.IsShown)
	local okPage, page = pcall(U.PageId)
	if not okShown or shown ~= true or not okPage or type(page) ~= "string" or not page:match("^wanted/") then return false end
	U.RefreshSoon()
	return true
end

-- The moderators took this client off (net-off): it sends none of this.
local function NetOff()
	local M = ns.Moderation
	if type(M) ~= "table" or M.missing or type(M.SelfOff) ~= "function" then return false end
	local ok, off = pcall(M.SelfOff)
	return not ok or (off ~= nil and off ~= false)
end

-- A unit API's first answer, nil when it fails or is secret.
local function Ask(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	if not ok or Secret(v) then return nil end
	return v
end

-- This client collects sightings: a member's, on the Alliance side, not refused, not off.
local function Collects()
	if not ns.IsMember or ns.IsMember() ~= true or not ns.me then return false, "member" end
	if ns.faction == "Horde" then return false, "faction" end
	if not SightingsOn() then return false, "off" end
	if NetOff() then return false, "netoff" end
	return true
end

-- This client takes sightings: a reviewer's (Wanted.CanPublish), a member's, not off (his own
-- No stops what he takes too), not net-off.
local function TakesSightings()
	return ns.IsMember and ns.IsMember() == true and ns.me ~= nil and ns.faction ~= "Horde"
		and SightingsOn() and Wanted.CanPublish(ns.me) and not NetOff()
end

-- The King's position goes out only while his crown shows on the map (King.SharingLocation), as
-- his zone and layer do (Layers.Sharing): while it is hidden, his client sends no sighting (it
-- still pins what it saw on his own map). Not known (King.lua missing, or failing): hidden for a
-- King's character.
function Sight.CrownHidden()
	local K = ns.King
	if type(K) ~= "table" or K.missing or type(K.IsKing) ~= "function" or type(K.SharingLocation) ~= "function" then
		return ns.IsKingCharacter ~= nil and ns.me ~= nil and ns.IsKingCharacter(ns.me) == true
	end
	local ok, king = pcall(K.IsKing)
	if not ok then return true end
	if king ~= true then return false end
	local okShown, shown = pcall(K.SharingLocation)
	return not okShown or shown ~= true
end

function Sight.GuildName(guild)
	if Secret(guild) or type(guild) ~= "string" or guild == "" or #guild > 48 or guild:find("[~|%c]") then return nil end
	return ns.IsFederation and ns.IsFederation(guild) and guild or nil
end

-- This player's Olympus guild, as the game says it.
function Sight.OwnGuild()
	if type(GetGuildInfo) ~= "function" then return nil end
	local ok, guild = pcall(GetGuildInfo, "player")
	return ok and Sight.GuildName(guild) or nil
end

-- A zone's map (or a smaller one in it): never a continent, the world, or a dungeon's.
function Sight.OpenMap(mapID)
	if not Whole(mapID, 1, 9999999) or type(C_Map) ~= "table" or type(C_Map.GetMapInfo) ~= "function" then return false end
	local ok, info = pcall(C_Map.GetMapInfo, mapID)
	if not ok or type(info) ~= "table" or Secret(info.mapType) then return false end
	local T = type(Enum) == "table" and type(Enum.UIMapType) == "table" and Enum.UIMapType or {}
	return info.mapType == (T.Zone or 3) or info.mapType == (T.Micro or 5)
end

function Sight.Grid(v)
	local g = Wanted.SIGHT_GRID
	return math.max(0, math.min(1000, math.floor(v * 1000 / g + 0.5) * g))
end

-- Where this player stands: his map and position there, rounded (Grid), or nil.
function Sight.Spot()
	if type(C_Map) ~= "table" or type(C_Map.GetBestMapForUnit) ~= "function" or type(C_Map.GetPlayerMapPosition) ~= "function" then return nil end
	local mapID = Ask(C_Map.GetBestMapForUnit, "player")
	if not Sight.OpenMap(mapID) then return nil end
	local pos = Ask(C_Map.GetPlayerMapPosition, mapID, "player")
	if not pos then return nil end
	local ok, x, y = pcall(function() return pos:GetXY() end)
	if not ok or Secret(x, y) or type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y
		or x < 0 or x > 1 or y < 0 or y > 1 or (x == 0 and y == 0) then return nil end
	return mapID, Sight.Grid(x), Sight.Grid(y)
end

-- This player's layer on that map when Layers saw it lately, else 0 (not known).
function Sight.MyLayer(mapID)
	local Ly = ns.Layers
	if type(Ly) ~= "table" or Ly.missing or type(Ly.Mine) ~= "function" then return 0 end
	local ok, m = pcall(Ly.Mine)
	local now = ns.Now()
	if not ok or type(m) ~= "table" or m.mapID ~= mapID or not Whole(m.zoneUID, 1, 2147483647) or type(m.t) ~= "number"
		or now - m.t > Wanted.SIGHT_LAYER_FRESH or m.t > now + 5 then return 0 end
	return m.zoneUID
end

-- The unit, when it is a sighting: a Horde player (not us) listed here (true). Only the wanted:
-- nobody else is recorded, sent or pinned. nil, why otherwise (and, for a hostile one flagged for
-- PvP of no Olympus guild, his identity: remembered here as Horde, for one's own death recap).
local function SightedUnit(unit)
	if Ask(UnitIsPlayer, unit) ~= true then return nil, "player" end
	if Ask(UnitFactionGroup, unit) ~= "Horde" then return nil, "faction" end
	local ident = UnitIdentity(unit)
	if not ident or not ident.guid or not ident.name then return nil, "identity" end
	local me = UnitIdentity("player") or Identity(ns.me)
	if me and SameIdentity(me, ident) then return nil, "self" end
	local s = Store(false)
	local t = s and ResolveTarget(s, ident, false)
	if Wanted.IsWanted(t) then return ident, true end
	if Ask(UnitCanAttack, "player", unit) ~= true or Ask(UnitIsPVP, unit) ~= true then return nil, "unlisted" end
	if type(GetGuildInfo) == "function" then
		local ok, guild = pcall(GetGuildInfo, unit)
		if not ok or Secret(guild) or (type(guild) == "string" and ns.IsFederation and ns.IsFederation(guild)) then return nil, "unlisted" end
	end
	return nil, "unlisted", ident
end

local function SightLive(e, now)
	return now - e.at <= Wanted.SIGHT_TTL and e.at <= now + Wanted.GLOBAL_SKEW
end

-- An observation may stay in the private history after its entry stops being wanted.
-- Only entries on the current list can be sent or drawn.
function Sight.Wanted(guid, name)
	local s = Store(false)
	return Wanted.IsWanted(s and ResolveTarget(s, Identity(name, guid), false))
end

-- The newest sighting of each Horde player, SIGHT_PINS of them at most (the oldest go first).
local function Keep(e)
	local old = pins[e.guid]
	if old and old.at > e.at then return false end
	pins[e.guid] = e
	local n = Count(pins)
	while n > Wanted.SIGHT_PINS do
		local oldest
		for guid, p in pairs(pins) do if not oldest or p.at < pins[oldest].at then oldest = guid end end
		pins[oldest], n = nil, n - 1
	end
	return pins[e.guid] == e
end

local function LeaseLive(r, now)
	return type(r) == "table" and now - r.at <= Wanted.REVIEWER_FOR and r.at <= now + Wanted.GLOBAL_SKEW
		and Wanted.CanPublish(r.name)
end

-- Whom a sighting goes to: the reviewer this member chose (s.reviewer, set by Wanted.SetReviewer;
-- by 1.2.2's Send evidence before), while his client says it takes them (his lease) and he holds
-- the role; never us, never anyone else. Nobody when this member chose nobody.
local function Recipients(now)
	local s = Store(false)
	local chosen = s and CleanName(s.reviewer) or nil
	if not chosen or SameName(chosen, ns.me) then return {} end
	local r = reviewers[ns.Fold(chosen)]
	if not LeaseLive(r, now) then return {} end
	return { r.name }
end
Wanted.SightingRecipients = function() return Recipients(math.floor(Clock())) end

local function DropJob(job)
	if sightJobs[job.key] == job then sightJobs[job.key], sightJobCount = nil, sightJobCount - 1 end
end

-- Cancels the sightings waiting in Comm (every one, or one reviewer's: his folded name).
local function CancelSightings(why, onlyTo)
	local list = {}
	for _, job in pairs(sightJobs) do
		if onlyTo == nil or job.toKey == onlyTo then list[#list + 1] = job end
	end
	local C = ns.Comm
	for _, job in ipairs(list) do
		job.cancelled = true
		DropJob(job)
		if type(C) == "table" and type(C.CancelQueued) == "function" then C.CancelQueued(Wanted, job.key, why or "cancelled") end
	end
	stats.sightCancelled = stats.sightCancelled + #list
	return #list
end

-- When Comm is about to send one: still wanted, still allowed, still fresh, still taken.
local function SightPermit(job)
	if sightJobs[job.key] ~= job or job.cancelled then return false, "cancelled" end
	if not Sight.Wanted(job.guid) then return false, "unlisted" end
	local ok, why = Collects()
	if not ok then return false, why end
	if Sight.CrownHidden() then return false, "crown" end
	if not Sight.Sharing() then return false, "private" end
	local now = math.floor(Clock())
	if now - job.at > Wanted.SIGHT_QUEUE_TTL then return false, "stale" end
	if not LeaseLive(reviewers[job.toKey], now) then return false, "reviewer" end
	return true
end

function Sight.Sharing()
	local Ly = ns.Layers
	return type(Ly) == "table" and type(Ly.Sharing) == "function" and Ly.Sharing() == true
end

-- The server's "No player named <reviewer> is currently playing" that answers a whisper this
-- client sent him on its own (a sighting, or taking them back): kept out of the chat frames for
-- SIGHT_QUIET seconds after it went (Wanted.NotFound still reads it, and drops him). The player
-- typed nothing, and a line naming the King out of nowhere says nothing to him. A line for anyone
-- else, or later, shows as ever.
function Wanted.QuietLine(_, _, text)
	if not ns.Gate.Allowed("system-filters") then return false end
	if next(told.quiet) == nil or type(text) ~= "string" or Secret(text) then return false end
	local T = ns.Treasury
	local pattern = T and type(T.NotFoundPattern) == "function" and T.NotFoundPattern()
	local who = type(pattern) == "string" and text:match(pattern)
	if type(who) ~= "string" then return false end
	local untilAt = told.quiet[who:lower()]
	local now = math.floor(Clock())
	return untilAt ~= nil and now <= untilAt and untilAt - now <= Wanted.SIGHT_QUIET
end

function Sight.Quiet(name)
	local now = math.floor(Clock())
	for who, untilAt in pairs(told.quiet) do if untilAt < now then told.quiet[who] = nil end end
	for _, shown in ipairs({ ns.TellName and ns.TellName(name), ns.DisplayName and ns.DisplayName(name) }) do
		if type(shown) == "string" and shown ~= "" then told.quiet[shown:lower()] = now + Wanted.SIGHT_QUIET end
	end
	if told.filter or not ns.Gate.Allowed("system-filters") then return end
	local U = rawget(_G, "ChatFrameUtil") -- gp:system-filters
	local add = type(U) == "table" and type(U.AddMessageEventFilter) == "function" and U.AddMessageEventFilter
		or rawget(_G, "ChatFrame_AddMessageEventFilter") -- gp:system-filters
	if type(add) ~= "function" then return end
	told.filter = true
	pcall(add, "CHAT_MSG_SYSTEM", Wanted.QuietLine) -- gp:system-filters
end

-- A reviewer this client's sightings reached this session (Withdraw takes them back).
function Sight.Told(job)
	if not told.by[job.toKey] then told.by[job.toKey] = { name = job.to, target = job.target } end
	Sight.Quiet(job.to)
end

-- Takes this client's sightings off the maps of the reviewers they reached this session (a No,
-- the King's crown hidden): one whisper each. (A reviewer who logged out since kept none: his
-- pins are his session's.) Returns how many were asked.
function Sight.Withdraw()
	local C = ns.Comm
	local list = {}
	for key, r in pairs(told.by) do list[#list + 1] = { key = key, name = r.name, target = r.target } end
	for key in pairs(told.by) do told.by[key] = nil end
	if type(C) ~= "table" or type(C.Whisper) ~= "function" then return 0 end
	table.sort(list, function(a, b) return a.key < b.key end)
	local n = 0
	for _, r in ipairs(list) do
		local asked = C.Whisper(r.target, "WS~X~1", "wanted-sighting-back:" .. r.key, false, false, function(sent)
			if sent then Sight.Quiet(r.name) end
		end)
		if asked then n = n + 1 end
	end
	return n
end

local function SendSighting(e)
	local C = ns.Comm
	-- (Only through a Comm that can cancel what waits: a No must reach every queued sighting.)
	if type(C) ~= "table" or type(C.Whisper) ~= "function" or type(C.CancelQueued) ~= "function" then return 0, "transport" end
	if Sight.CrownHidden() then return 0, "crown" end
	-- (1.2.0: a sighting carries where this player stands and his layer: none goes while he keeps
	-- his zone and layer private.)
	if not Sight.Sharing() then return 0, "private" end
	local guild = Sight.OwnGuild()
	if not guild then return 0, "guild" end
	local now = math.floor(Clock())
	for i = #sightSends, 1, -1 do
		if now - sightSends[i] >= Wanted.SIGHT_WINDOW or sightSends[i] > now then table.remove(sightSends, i) end
	end
	if #sightSends >= Wanted.SIGHT_SEND_MAX then stats.sightRate = stats.sightRate + 1 return 0, "rate" end
	local to = Recipients(now)
	if #to == 0 then return 0, "reviewers" end
	local wire = WireGuid(e.guid)
	if not wire then return 0, "identity" end
	local body = ("WS~S~1~%s~%s~%d~%d~%d~%d~%d~%s~%s"):format(guild, e.id, e.at, e.mapID, e.x, e.y, e.layer, wire, e.name)
	if #body > 255 then return 0, "size" end
	local queued = 0
	for _, name in ipairs(to) do
		if sightJobCount >= Wanted.SIGHT_QUEUE_MAX then break end
		local toKey = ns.Fold(name)
		local key = "wanted-sighting:" .. toKey .. ":" .. e.id
		local target = ns.TellName and ns.TellName(name) or name
		local job = { key = key, toKey = toKey, to = name, target = target, body = body, at = now, guid = e.guid }
		sightJobs[key], sightJobCount = job, sightJobCount + 1
		local accepted = C.Whisper(target, body, nil, false, false, function(sent)
			DropJob(job)
			if sent then stats.sightSent = stats.sightSent + 1 Sight.Told(job) end
		end, { owner = Wanted, key = key, permit = function(owner, permitKey, dist, permitTarget, msg)
			if owner ~= Wanted or permitKey ~= key or dist ~= "WHISPER" or permitTarget ~= target or msg ~= body then return false, "target" end
			return SightPermit(job)
		end })
		if accepted then queued = queued + 1 else DropJob(job) end
	end
	if queued == 0 then return 0, "queue" end
	sightSends[#sightSends + 1] = now
	WatchNotFound()
	return queued
end

local function RememberOwn(guid, now, mapID)
	if not ownSeen[guid] then ownSeenCount = ownSeenCount + 1 end
	ownSeen[guid] = { at = now, mapID = mapID }
	if ownSeenCount <= Wanted.SIGHT_OWN_MAX then return end
	for key, o in pairs(ownSeen) do
		if now - o.at >= Wanted.SIGHT_GAP or o.at > now then ownSeen[key], ownSeenCount = nil, ownSeenCount - 1 end
	end
	while ownSeenCount > Wanted.SIGHT_OWN_MAX do
		local oldest
		for key, o in pairs(ownSeen) do if not oldest or o.at < ownSeen[oldest].at then oldest = key end end
		ownSeen[oldest], ownSeenCount = nil, ownSeenCount - 1
	end
end

-- What this client sees (a nameplate, its target, the unit under the mouse). Returns true and the
-- sighting, or false and why it is none.
function Wanted.ObserveUnit(unit)
	local ok, why = Collects()
	if not ok then
		-- (1.2.0: sightings wait for a Yes; until one is answered, a hostile Horde player seen is
		-- still remembered here, never sent, for one's own death recap. A No stops that too.)
		if why == "off" and type(ns.db) == "table" and ns.db.wantedSightings == nil and type(unit) == "string" and not InInstance() then
			local _, _, horde = SightedUnit(unit)
			if horde then RememberHorde(horde, unit) end
		end
		return false, why
	end
	if InInstance() then return false, "instance" end
	if type(unit) ~= "string" then return false, "unit" end
	-- A Horde player this client recorded on this map within SIGHT_GAP: dropped before anything
	-- else is asked of the game (nameplates come and go all through a fight).
	local now = math.floor(Clock())
	local last = ownSeen[Guid(Ask(UnitGUID, unit)) or false]
	if last and now - last.at < Wanted.SIGHT_GAP and last.at <= now and type(C_Map) == "table"
		and last.mapID == Ask(C_Map.GetBestMapForUnit, "player") then
		stats.sightRepeat = stats.sightRepeat + 1
		return false, "repeat"
	end
	local ident, listed, horde = SightedUnit(unit)
	if horde then RememberHorde(horde, unit) end
	if not ident then return false, listed end
	RememberHorde(ident, unit)
	local mapID, x, y = Sight.Spot()
	if not mapID then return false, "position" end
	local observer = CleanName(ns.me)
	local id = observer and Digest(table.concat({ "OLYS1", observer, ident.guid, now, mapID, x, y }, "|"))
	if not id then return false, "identity" end
	RememberOwn(ident.guid, now, mapID)
	local e = { id = id, guid = ident.guid, name = ident.name, mapID = mapID, x = x, y = y, layer = Sight.MyLayer(mapID),
		at = now, observer = observer, own = true, listed = listed }
	stats.sightSeen = stats.sightSeen + 1
	local changed = Keep(e)
	e.sent = SendSighting(e)
	Wanted.RefreshPins(changed)
	return true, e
end

-- The No (or Yes again). Off, at once: no more collecting, what waits in Comm cancelled, what
-- reached a reviewer taken back (Withdraw), every pin off this client's map, and a reviewer stops
-- taking them: his lease goes off on the channel (WS~R~0), so members stop whispering him. On
-- again: a reviewer says at once that he takes them.
function Wanted.SetSightings(on, silent)
	if type(ns.db) ~= "table" then return false end
	on = on == true
	ns.db.wantedSightings = on
	if not on then
		knownHorde = {}
		CancelSightings("off")
		Sight.Withdraw()
		for guid in pairs(pins) do pins[guid] = nil end
		for key in pairs(ownSeen) do ownSeen[key] = nil end
		ownSeenCount = 0
		local C = ns.Comm
		if leaseAt ~= nil and type(C) == "table" and type(C.Send) == "function" then
			leaseAt = nil
			-- (The lease's key: a lease still waiting in Comm is replaced, not sent before it.)
			C.Send("CHANNEL", "WS~R~0", "wanted-reviewer", false, false, nil, { owner = Wanted })
		end
	end
	Wanted.RefreshPins(true)
	if not silent then ns.Print(on and L.WANTED_SIGHTINGS_ON or L.WANTED_SIGHTINGS_OFF) end
	if on and TakesSightings() and leaseAt == nil then Wanted.AnnounceReviewer() end
	return true
end

-- /oly sightings on | off; alone, says which.
function Wanted.SightingsSlash(rest)
	local word = type(rest) == "string" and rest:lower():match("^%s*(%S*)") or ""
	if word == "on" or word == "off" then return Wanted.SetSightings(word == "on") end
	ns.Print(SightingsOn() and L.WANTED_SIGHTINGS_ON or L.WANTED_SIGHTINGS_OFF)
	return true
end

-- The reviewer's lease: "I take sightings", on the channel (no place, no name but his own, which
-- the server stamps). Every client checks his role itself.
function Wanted.AnnounceReviewer()
	local C = ns.Comm
	if not TakesSightings() then return false, "reviewer" end
	if type(C) ~= "table" or type(C.Send) ~= "function" then return false, "transport" end
	leaseAt = math.floor(Clock())
	return C.Send("CHANNEL", "WS~R~1", "wanted-reviewer", false, false, nil, { owner = Wanted, guard = TakesSightings })
end

local function HeardLease(dist, sender, text)
	if dist ~= "CHANNEL" or (text ~= "WS~R~1" and text ~= "WS~R~0") then return false, "shape" end
	sender = CleanName(sender)
	-- His No: no lease, nothing waiting for him (only his own: the server stamps the sender).
	if text == "WS~R~0" then
		local key = sender and ns.Fold(sender)
		if not key or not reviewers[key] then return false, "unknown" end
		reviewers[key], reviewerCount = nil, reviewerCount - 1
		CancelSightings("reviewer", key)
		return true
	end
	if not sender or SameName(sender, ns.me) or not Wanted.CanPublish(sender) then return false, "authority" end
	local key, now = ns.Fold(sender), math.floor(Clock())
	if not reviewers[key] then
		if reviewerCount >= Wanted.REVIEWERS_MAX then
			local oldest
			for k, r in pairs(reviewers) do if not oldest or r.at < reviewers[oldest].at then oldest = k end end
			reviewers[oldest], reviewerCount = nil, reviewerCount - 1
			CancelSightings("reviewer", oldest)
		end
		reviewerCount = reviewerCount + 1
	end
	reviewers[key] = { key = key, name = sender, at = now }
	stats.leases = stats.leases + 1
	return true
end

-- The server says a reviewer is not online: no lease, nothing waiting for him.
SightingNotFound = function(who)
	local hit = false
	for key, r in pairs(reviewers) do
		if (ns.TellName(r.name) or ""):lower() == who or (ns.DisplayName(r.name) or ""):lower() == who then
			reviewers[key], reviewerCount = nil, reviewerCount - 1
			CancelSightings("offline", key)
			hit = true
		end
	end
	return hit
end

-- The sender speaks for an Olympus guild as the Olympus chats check it (Channels.VerifiedLevel),
-- and the moderators did not take him off.
local function FromOlympian(sender, guild)
	local Ch = ns.Channels
	if type(Ch) ~= "table" or Ch.missing or type(Ch.VerifiedLevel) ~= "function" then return false end
	local ok, level, verified = pcall(Ch.VerifiedLevel, sender, guild)
	if not ok or type(level) ~= "number" or level < 1 or verified ~= true then return false end
	local M = ns.Moderation
	if type(M) == "table" and not M.missing and type(M.Hides) == "function" then
		local okHides, hidden = pcall(M.Hides, sender, guild)
		if not okHides or hidden then return false end
	end
	return true
end

-- SIGHT_RECV_MAX a window from one sender, SIGHT_INTAKE_MAX from all, SIGHT_SENDERS_MAX counted.
local function SightAdmit(sender, now)
	if now - sightIntake.at >= Wanted.SIGHT_WINDOW or sightIntake.at > now then sightIntake.at, sightIntake.n = now, 0 end
	if sightIntake.n >= Wanted.SIGHT_INTAKE_MAX then return false end
	local key = ns.Fold(sender)
	local b = sightFrom[key]
	if not b then
		if sightFromCount >= Wanted.SIGHT_SENDERS_MAX then
			for other, held in pairs(sightFrom) do
				if now - held.at >= Wanted.SIGHT_WINDOW then sightFrom[other], sightFromCount = nil, sightFromCount - 1 end
			end
			if sightFromCount >= Wanted.SIGHT_SENDERS_MAX then return false end
		end
		b = { at = now, n = 0 }
		sightFrom[key], sightFromCount = b, sightFromCount + 1
	elseif now - b.at >= Wanted.SIGHT_WINDOW or b.at > now then
		b.at, b.n = now, 0
	end
	if b.n >= Wanted.SIGHT_RECV_MAX then return false end
	b.n, sightIntake.n = b.n + 1, sightIntake.n + 1
	return true
end

local function RememberSight(key)
	sightSeen[key] = true
	sightSeenOrder[#sightSeenOrder + 1] = key
	while #sightSeenOrder > Wanted.SIGHT_SEEN_MAX do sightSeen[table.remove(sightSeenOrder, 1)] = nil end
end

local function Refuse(why)
	stats.sightRefused = stats.sightRefused + 1
	return false, why
end

-- This window is full (everyone's, or this sender's): checked before anything is parsed.
function Sight.Full(sender, now)
	if now - sightIntake.at < Wanted.SIGHT_WINDOW and sightIntake.at <= now and sightIntake.n >= Wanted.SIGHT_INTAKE_MAX then return true end
	local b = sightFrom[ns.Fold(sender)]
	return b ~= nil and now - b.at < Wanted.SIGHT_WINDOW and b.at <= now and b.n >= Wanted.SIGHT_RECV_MAX
end

local function TakeSighting(dist, sender, text)
	if dist ~= "WHISPER" then return Refuse("lane") end
	if not TakesSightings() then return Refuse("reviewer") end
	local cleanSender = CleanName(sender)
	if cleanSender and Sight.Full(cleanSender, math.floor(Clock())) then stats.sightRate = stats.sightRate + 1 return false, "rate" end
	if #text > 255 then return Refuse("shape") end
	local version, guild, id, at, mapID, x, y, layer, wire, name =
		text:match("^WS~S~(%d+)~([^~]+)~(%x+)~(%d+)~(%d+)~(%d+)~(%d+)~(%d+)~([^~]+)~([^~]+)$")
	at, mapID, x, y, layer = tonumber(at), tonumber(mapID), tonumber(x), tonumber(y), tonumber(layer)
	local guid = GameGuid(wire)
	local ident = guid and Identity(name, guid) or nil
	guild = Sight.GuildName(guild)
	if version ~= "1" or not id or #id ~= 16 or not Whole(at, 0, 4294967295) or not Whole(x, 0, 1000) or not Whole(y, 0, 1000)
		or not Whole(layer, 0, 2147483647) or not Sight.OpenMap(mapID) or not ident or not ident.name or not guild then return Refuse("shape") end
	local now = math.floor(Clock())
	if at > now + Wanted.GLOBAL_SKEW or now - at > Wanted.SIGHT_TTL then return Refuse("stale") end
	sender = CleanName(sender)
	if not sender or SameName(sender, ns.me) then return Refuse("sender") end
	if not FromOlympian(sender, guild) then return Refuse("olympus") end
	local listed = Store(false)
	listed = listed and ResolveTarget(listed, ident, false)
	if not Wanted.IsWanted(listed) then return Refuse("unlisted") end
	local key = ns.Fold(sender) .. "#" .. id
	if sightSeen[key] then stats.sightReplay = stats.sightReplay + 1 return false, "replay" end
	if not SightAdmit(sender, now) then stats.sightRate = stats.sightRate + 1 return false, "rate" end
	RememberSight(key)
	local e = { id = id, guid = ident.guid, name = ident.name, mapID = mapID, x = x, y = y, layer = layer, at = at,
		observer = sender, guild = guild, own = false }
	stats.sightTaken = stats.sightTaken + 1
	local changed = Keep(e)
	Wanted.RefreshPins(changed)
	return true, e
end

-- The sender takes his sightings back (his No, or the King's crown hidden): his pins leave this
-- map, whatever this client's own answer. (Only his own: the server stamps the sender.)
function Sight.TakeBack(dist, sender, text)
	if dist ~= "WHISPER" or text ~= "WS~X~1" then return false, "shape" end
	sender = CleanName(sender)
	if not sender then return false, "sender" end
	local n = 0
	for guid, e in pairs(pins) do
		if not e.own and SameName(e.observer, sender) then pins[guid], n = nil, n + 1 end
	end
	stats.sightWithdrawn = stats.sightWithdrawn + n
	if n > 0 then Wanted.RefreshPins(true) end
	return true, n
end

function Wanted.HandleSighting(dist, sender, text)
	if type(text) ~= "string" or type(sender) ~= "string" then return false, "shape" end
	local kind = text:match("^WS~(%u)~")
	if kind == "R" then return HeardLease(dist, sender, text) end
	if kind == "S" then return TakeSighting(dist, sender, text) end
	if kind == "X" then return Sight.TakeBack(dist, sender, text) end
	return false, "shape"
end

-- The pins held now (copies), the newest first.
function Wanted.Sightings()
	local now, out = math.floor(Clock()), {}
	for _, e in pairs(pins) do
		if SightLive(e, now) and Sight.Wanted(e.guid, e.name) then
			local c = {} for k, v in pairs(e) do c[k] = v end out[#out + 1] = c
		end
	end
	table.sort(out, function(a, b)
		if a.at ~= b.at then return a.at > b.at end
		return a.guid < b.guid
	end)
	return out
end

-- How long ago, in this computer's clock (ns.Ago) from the server's.
local function SightAgo(at)
	return ns.Ago(ns.Now() - math.max(0, math.floor(Clock()) - at))
end

-- A pin's hover: his name, his kills by this client's ledger, when and by whom he was seen, the
-- layer against this player's, and that the spot is where the Olympian stood.
function Wanted.SightingTip(tt, e)
	if type(tt) ~= "table" or type(e) ~= "table" then return false end
	tt:AddLine(Display({ name = e.name }), 1, 0.82, 0)
	local s = Store(false)
	local t = s and ResolveTarget(s, Identity(e.name, e.guid), false)
	if Wanted.IsWanted(t) then
		tt:AddLine(L.WANTED_LIFETIME:format(t.lifetimeKills or 0), 1, 1, 1)
		tt:AddLine(L.WANTED_BOUNTY:format(t.current or 0), 0.8, 0.8, 0.8)
	elseif t and not t.active then
		-- Taken off the list here: his kills stay a fact, no bounty is said.
		tt:AddLine(L.WANTED_LIFETIME:format(t.lifetimeKills or 0), 1, 1, 1)
		tt:AddLine(L.WANTED_SIGHT_REMOVED, 0.8, 0.8, 0.8, true)
	else
		tt:AddLine(t and L.WANTED_NOT_WANTED or L.WANTED_SIGHT_UNLISTED, 0.8, 0.8, 0.8, true)
	end
	tt:AddLine(L.WANTED_SIGHT_SEEN:format(SightAgo(e.at), e.own and L.WANTED_SIGHT_BY_YOU or IssuerName(e.observer)), 1, 1, 1, true)
	if (e.layer or 0) > 0 then
		local mine = Sight.MyLayer(e.mapID)
		if mine > 0 then tt:AddLine(mine == e.layer and L.WANTED_SIGHT_YOUR_LAYER or L.WANTED_SIGHT_OTHER_LAYER, 0.8, 0.8, 0.8) end
	end
	tt:AddLine(L.WANTED_SIGHT_NEARBY, 0.6, 0.6, 0.6, true)
	return true
end

function Wanted.SightingShortAge(at)
	local seconds = math.max(0, math.floor(Clock()) - math.floor(tonumber(at) or 0))
	if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
	if seconds < 86400 then return math.floor(seconds / 3600) .. "h" end
	if seconds < 31536000 then return math.floor(seconds / 86400) .. "d" end
	return math.floor(seconds / 31536000) .. "y"
end

-- Permanent, zone-only history for the world map. It is suppressed only when the live native
-- observation is the newer source selected by LastSeen; a newer combat sighting remains visible.
function Wanted.HistoricalSightings(mapFilter)
	local grouped = {}
	if not Wanted.CanSeeLocations() then return grouped end
	for _, t in ipairs(Wanted.Targets("listed")) do
		local old = Wanted.LastSeen(t)
		if type(old) == "table" and old.source == "ledger" then
			local mapID = Wanted.SightingMapID(old)
			if mapID and (not mapFilter or mapID == mapFilter) then
				local group = grouped[mapID]
				if not group then
					group = { mapID = mapID, zone = old.zone, newest = old.at, rows = {} }
					grouped[mapID] = group
				end
				group.newest = math.max(group.newest, old.at)
				group.rows[#group.rows + 1] = { key = t.key, name = t.name, at = old.at,
					zone = old.zone, precision = old.precision }
			end
		end
	end
	for _, group in pairs(grouped) do
		table.sort(group.rows, function(a, b)
			if a.at ~= b.at then return a.at > b.at end
			return tostring(a.key) < tostring(b.key)
		end)
	end
	return grouped
end

function Wanted.HistoryTip(tt, group)
	if type(tt) ~= "table" or type(group) ~= "table" then return false end
	tt:AddLine(L.WANTED_MAP_HISTORY:format(group.zone or L.WANTED_UNKNOWN), 1, 0.82, 0)
	for i = 1, math.min(Wanted.HISTORY_TIP_MAX, #(group.rows or {})) do
		local row = group.rows[i]
		tt:AddLine(L.WANTED_MAP_HISTORY_ROW:format(Display(row), Wanted.SightingWhen(row.at, false)), 1, 1, 1, true)
	end
	if #(group.rows or {}) > Wanted.HISTORY_TIP_MAX then
		tt:AddLine(L.WANTED_MAP_HISTORY_MORE:format(#group.rows - Wanted.HISTORY_TIP_MAX), 0.7, 0.7, 0.7)
	end
	tt:AddLine(L.WANTED_ZONE_ONLY, 0.6, 0.6, 0.6, true)
	return true
end

function Sight.ShowTip(self, fill, value)
	if type(GameTooltip) ~= "table" or type(fill) ~= "function" then return false end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	fill(GameTooltip, value)
	GameTooltip:Show()
	return true
end

function Sight.HistoryEnter(self)
	local group = self and self.history
	if not group then return end
	return Sight.ShowTip(self, Wanted.HistoryTip, group)
end

local function PinEnter(self)
	local e = self and self.sighting and pins[self.sighting]
	if not e then return end
	return Sight.ShowTip(self, Wanted.SightingTip, e)
end
local function PinLeave() if type(GameTooltip) == "table" then GameTooltip:Hide() end end

-- A pin's two frames: the world map's badge (Map.Badge: the orc banner in a red disc) and the
-- minimap's icon. nil where the map module or frames are missing.
local function MakeFrames()
	local M = ns.Map
	if type(M) ~= "table" or M.missing or type(M.Badge) ~= "function" or type(M.SetBadge) ~= "function" then return nil end
	local world = M.Badge(Wanted.SIGHT_BADGE, true)
	M.SetBadge(world, Wanted.Icon(), 0.8, 0.12, 0.08)
	world.badge:SetScript("OnEnter", PinEnter)
	world.badge:SetScript("OnLeave", PinLeave)
	local mini = CreateFrame("Frame", nil, UIParent)
	mini.olympus = true -- (ours: photo mode leaves it shown, UI.TogglePhoto)
	mini:SetSize(Wanted.SIGHT_MINI, Wanted.SIGHT_MINI)
	mini.icon = mini:CreateTexture(nil, "OVERLAY")
	mini.icon:SetAllPoints()
	mini.icon:SetTexture(Wanted.Icon())
	mini:EnableMouse(true)
	mini:SetScript("OnEnter", PinEnter)
	mini:SetScript("OnLeave", PinLeave)
	mini:Hide() -- (the pin library shows it when it puts it on the minimap)
	return { world = world, mini = mini }
end

function Sight.MakeHistoryFrame()
	local M = ns.Map
	if type(M) ~= "table" or M.missing or type(M.Badge) ~= "function" or type(M.SetBadge) ~= "function" then return nil end
	local frame = M.Badge(Wanted.HISTORY_BADGE, true)
	M.SetBadge(frame, Wanted.Icon(), 0.62, 0.36, 0.18)
	frame.badge.age = frame.badge:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	frame.badge.age:SetPoint("BOTTOM", frame.badge, "BOTTOM", 0, -7)
	frame.badge:SetScript("OnEnter", Sight.HistoryEnter)
	frame.badge:SetScript("OnLeave", PinLeave)
	frame.onWorld = false
	return frame
end

local SIGHT_SHOW = HBD_PINS_WORLDMAP_SHOW_PARENT or 1

local function RefreshPinsNow(refreshPage) -- gp:wanted-map
	local now = math.floor(Clock())
	local pageChanged = refreshPage == true
	for guid, e in pairs(pins) do
		if not SightLive(e, now) then
			pins[guid] = nil
			stats.sightExpired = stats.sightExpired + 1
			pageChanged = true
		end
	end
	if pageChanged then Sight.RefreshPage() end
	local P = ns.Pins and ns.Pins()
	if not P then return false end
	local world = ns.WorldMapIcons(P, Wanted)
	local showWorld = world and not (ns.db and ns.db.showWanted == false)
	-- This map-menu choice hides only world-map artwork, not consent or minimap sightings.
	if not showWorld then
		for _, f in pairs(pinFrames) do
			if world and f.onWorld then P:RemoveWorldMapIcon(Wanted, f.world) end
			f.world:Hide()
			f.onWorld = nil
		end
	end
	-- Alliance members who may see locations only, never in an instance.
	local allowed = Wanted.CanSeeLocations() and not InInstance()
	for guid, f in pairs(pinFrames) do
		if not (allowed and pins[guid] and Sight.Wanted(guid, pins[guid].name)) then
			if world and f.onWorld then P:RemoveWorldMapIcon(Wanted, f.world) end
			P:RemoveMinimapIcon(Wanted, f.mini)
			f.world:Hide()
			f.mini:Hide()
			f.onWorld, f.drawn, f.world.badge.sighting, f.mini.sighting = nil, nil, nil, nil
			pinFrames[guid] = nil
			spareFrames[#spareFrames + 1] = f
		end
	end
	if allowed then
		for guid, e in pairs(pins) do
			if Sight.Wanted(guid, e.name) then
				local f = pinFrames[guid]
				if not f then
					f = table.remove(spareFrames) or MakeFrames()
					if not f then return false end
					pinFrames[guid] = f
				end
				f.world.badge.sighting, f.mini.sighting, f.world.since = guid, guid, e.at
				-- (With the gamepad UI ns.WorldMapIcons took this module's world icons off already.)
				if not showWorld then f.onWorld = nil end
				if f.drawn ~= e or (showWorld and not f.onWorld) then
					if showWorld then
						P:AddWorldMapIconMap(Wanted, f.world, e.mapID, e.x / 1000, e.y / 1000, SIGHT_SHOW)
						f.onWorld = true
					end
					if f.drawn ~= e then P:AddMinimapIconMap(Wanted, f.mini, e.mapID, e.x / 1000, e.y / 1000, false, false) end
					f.drawn = e
				end
			end
		end
	end

	-- Historical markers are relevant to the map currently being viewed. Restricting them to that
	-- zone also keeps unrelated old sightings from competing with a fresh nearby marker.
	local historyMap, mapAllowed = historyFocus, false
	local G = ns.Gate
	if type(G) == "table" and type(G.Allowed) == "function" then
		local ok, allowedMap = pcall(G.Allowed, "wanted-map")
		mapAllowed = ok and allowedMap == true
	end
	if mapAllowed and type(WorldMapFrame) == "table" and type(WorldMapFrame.IsShown) == "function"
		and WorldMapFrame:IsShown() and type(WorldMapFrame.GetMapID) == "function" then
		local ok, current = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
		if ok and tonumber(current) then historyMap = tonumber(current) end
	end
	local wantedHistory = showWorld and allowed and historyMap and Wanted.HistoricalSightings(historyMap) or {}
	for mapID, frame in pairs(Sight.historyFrames) do
		if not wantedHistory[mapID] then
			if world and frame.onWorld then P:RemoveWorldMapIcon(Wanted, frame) end
			frame:Hide()
			frame.onWorld, frame.badge.history = false, nil
			Sight.historyFrames[mapID] = nil
			Sight.historySpare[#Sight.historySpare + 1] = frame
		end
	end
	for mapID, group in pairs(wantedHistory) do
		local frame = Sight.historyFrames[mapID]
		if not frame then
			frame = table.remove(Sight.historySpare) or Sight.MakeHistoryFrame()
			if not frame then return false end
			Sight.historyFrames[mapID] = frame
		end
		frame.badge.history, frame.since = group, group.newest
		frame.badge.age:SetText(Wanted.SightingShortAge(group.newest))
		frame:SetAlpha(now - group.newest > Wanted.SIGHT_TTL and 0.58 or 0.82)
		if not frame.onWorld then
			P:AddWorldMapIconMap(Wanted, frame, mapID, 0.5, 0.5, SIGHT_SHOW)
			frame.onWorld = true
		end
	end
	return true
end

function Wanted.RefreshPins(refreshPage)
	if ns.SafeCall then return ns.SafeCall("wanted pins", RefreshPinsNow, refreshPage) end
	return RefreshPinsNow(refreshPage)
end

-- (Tests: the frames each pin has now.)
function Wanted.PinFrames() return pinFrames end
function Wanted.HistoryFrames() return Sight.historyFrames end

-- A reviewer's lease is due: he takes sightings and has not said so for a beat (a few seconds'
-- slack: the timer's beat and the role's arrival may come close together).
local function LeaseDue()
	return TakesSightings() and (leaseAt == nil or math.floor(Clock()) - leaseAt >= Wanted.REVIEWER_EVERY - 5)
end

-- The lease, LOGIN's REVIEWER_FIRST later, then every REVIEWER_EVERY while the reviewer stays.
local function ScheduleLease(gen, wait)
	if not ns.After then return end
	ns.After(wait, "wanted reviewer", function()
		if gen ~= leaseGen then return end
		if LeaseDue() then Wanted.AnnounceReviewer() end
		ScheduleLease(gen, Wanted.REVIEWER_EVERY)
	end)
end

if ns.Consent and ns.Consent.Register then
	ns.Consent.Register({
		key = "wantedsightings", label = "CONSENT_WANTED_SIGHTINGS", text = "CONSENT_WANTED_SIGHTINGS_TEXT",
		shown = function() return ns.IsMember() == true and ns.faction ~= "Horde" end,
		-- Keep unanswered distinct from No on the authorization page. Runtime collection still uses
		-- SightingsOn(), where both nil and false are safely off.
		get = function()
			local answer
			if type(ns.db) == "table" then answer = ns.db.wantedSightings end
			if answer == true or answer == false then return answer end
			return nil
		end,
		set = function(on) Wanted.SetSightings(on) end,
		-- Off until an explicit choice. Authorize all includes every visible pending line, including
		-- this one; an earlier No remains a No because it is no longer pending.
		pending = function() return type(ns.db) == "table" and ns.db.wantedSightings == nil end,
		explicit = true,
	})
end

---------------------------------------------------------------------------
-- Shared kills and deaths (1.2.3)
--
-- This client's own row (its player's own death to a Horde player, or his own killing blow on one)
-- goes at once to the Olympus channel, and every member's client counts it straight away:
--   WK~1~<scope>~<guild>~<digest>~<at>~<month>~<S|P>~<horde guid>~<own guid>~<horde name>
--       channel: one own row. S: the sender's death, a bounty on the Horde player. P: the
--       sender's killing blow, a claim of the Horde player's open bounty.
--   WK~R~1~<scope>~<from>~<b>~<digest>~<at>~<month>~<S|P>~<horde guid>~<own guid|->~<horde name>
--       channel: a reviewer's relay of a row his client took from <from>: b is 1 when his client
--       proved the GUID is the sender's (else 0, and no GUID: -).
--   WK~C~1~...   the same, in his answer to a late login's catch-up ask (W4)
--   WK~2~...~<own guid>~<office>~<level>~<horde level>[+]~<horde name>, WK~R~2~..., WK~C~2~...
--       1.2.3's bounty: the same rows with what each is worth, frozen where it was observed (the
--       Olympian's office and level, the Horde player's level, "+" when it is a floor: the section
--       "The bounty" below); a client reads both, and a WK~1 row counts as one without them.
--   WK~R~3~...~<bound>~<member>~... and WK~R~4~...~<bound>~<member>~...~<worth>~...
--       1.2.4 relays keep GUID binding and independently verified membership as separate facts;
--       3 has no frozen worth, 4 has it.  Unverified rows remain in the perennial local ledger,
--       but cannot contribute points to a signed global board until a verified relay promotes it.
--   WV~T~1~<scope>~<horde guid>~<at>            channel: a reviewer took that Horde player off
--   WV~V~1~<scope>~<from>~<digest>~<at>         channel: a reviewer voided that member's row
-- GUIDs as WY writes them (server.id), <scope> the realm group and faction (Scope), <digest> the
-- row's own (16 hex), <at> its time and <month> its month as the sender's client counted them.
-- What a receiver takes (Share.Take): a row of its own realm group and faction, fresh (SHARE_AGE,
-- GLOBAL_SKEW), from a member as the [Olympus] chat takes one (Share.Member, 1.2.4: its own guild's
-- fresh roster, a guild rank it can verify for the guild the row names, a reviewer, else that
-- Olympus guild as its sender's one claimed guild), whom the moderators do not hide, about the
-- sender's own death or killing blow: the Olympian side is the sender, by the name the server
-- stamps, his GUID only where this client proves it is his (GuidIsSender: a unit, or the game's
-- lookup), refused where it proves it is someone else's. The Horde side as the sender's client
-- proved it, refused where this client sees him as no Horde player (a unit, an Alliance race) or
-- as an Olympian. Once (its id: the sender and the digest), unless voided, SHARE_RATE_MAX a window
-- from one member and SHARE_TARGET_MAX about one Horde player from everyone. A relay only from a
-- reviewer (the King, a signed High Councillor, the author), on whose word a client before 1.2.4
-- counts a member it cannot verify (one of another guild, whose rank no census names), unless this
-- client knows him no member (Share.Disowned), SHARE_RELAY_MAX a window from one. A mark (WV) only
-- from a reviewer, on his own word. A client before 1.2.3 has
-- no handler for WK or WV, and ignores them.
---------------------------------------------------------------------------

Share.ALLIANCE_RACES = { Human = true, Dwarf = true, NightElf = true, Gnome = true, Draenei = true, Worgen = true,
	VoidElf = true, LightforgedDraenei = true, DarkIronDwarf = true, KulTiran = true, Mechagnome = true }

-- (This session's captures and refusals, the newest last, DIAG_MAX at most: /oly wanted status.)
-- kind: "kill" (own killing blow), "death" (own death), "heard" (a member's row), "relay" (a
-- reviewer's relay), "mark" (a reviewer's removal or void). why: the row recorded, or the reason.
-- guild (1.2.4): the guild a member's row names, shown after its sender.
function Share.Note(kind, ok, why, who, from, guild)
	local reason = ok and "ok" or tostring(why or "?")
	Share.counts[kind] = (Share.counts[kind] or 0) + 1
	if ok then Share.counts.counted = (Share.counts.counted or 0) + 1 else Share.why[reason] = (Share.why[reason] or 0) + 1 end
	local e = ok and type(why) == "table" and why or nil
	local row = { at = math.floor(Clock()), kind = kind, ok = ok == true, why = not ok and reason or nil, who = Clean(who, 72),
		from = Clean(from, 72), guild = Clean(guild, 48), action = e and e.action or nil, points = e and e.points or nil,
		again = e and e.again or nil }
	Share.log[#Share.log + 1] = row
	while #Share.log > Wanted.DIAG_MAX do table.remove(Share.log, 1) end
	return row
end

-- One death's reading (PLAYER_DEAD and its retries): one line, the last answer.
function Share.NoteDeath(serial, ok, why, who)
	local last = Share.deathRow
	if last and last.serial == serial then
		Share.counts.death = math.max(0, (Share.counts.death or 1) - 1)
		if last.ok then Share.counts.counted = math.max(0, (Share.counts.counted or 1) - 1)
		else Share.why[last.why] = math.max(0, (Share.why[last.why] or 1) - 1) end
		for i = #Share.log, 1, -1 do if Share.log[i] == last then table.remove(Share.log, i) break end end
	end
	local row = Share.Note("death", ok, why, who)
	row.serial, Share.deathRow = serial, row
	return row
end

-- (A reviewer's own part of a few seconds: two reviewers online do not relay at the same moment.)
function Share.Offset()
	local n, me = 0, tostring(ns.me or "")
	for i = 1, #me do n = n + me:byte(i) end
	return n
end

-- A window's count for key, one more within max: false when it is full. The table holds keysMax
-- keys at most (SHARE_SENDERS_MAX by default; those whose window ended go first; none, false).
function Share.Count(list, key, now, window, max, keysMax)
	keysMax = keysMax or Wanted.SHARE_SENDERS_MAX
	local b = list[key]
	if not b then
		if Count(list) >= keysMax then
			for other, held in pairs(list) do if now - held.at >= window or held.at > now then list[other] = nil end end
			if Count(list) >= keysMax then return false end
		end
		b = { at = now, n = 0 }
		list[key] = b
	elseif now - b.at >= window or b.at > now then
		b.at, b.n = now, 0
	end
	if b.n >= max then return false end
	b.n = b.n + 1
	return true
end

-- SHARE_RATE_MAX rows a window from one member and SHARE_DAY_MAX a day (SHARE_RELAY_MAX a window
-- from one reviewer's relays), and SHARE_TARGET_MAX about one Horde player from everyone.
function Share.Admit(who, hordeGuid, now, relay)
	local key, max = ns.Fold(who), Wanted.SHARE_RATE_MAX
	if relay then key, max = "r:" .. key, Wanted.SHARE_RELAY_MAX end
	if not Share.Count(Share.rates, key, now, Wanted.SHARE_RATE_WINDOW, max) then return false, "rate" end
	if not relay and not Share.Count(Share.days, key, now, Wanted.SHARE_DAY, Wanted.SHARE_DAY_MAX, Wanted.SHARE_DAY_SENDERS_MAX) then
		return false, "rate"
	end
	if not Share.Count(Share.targets, hordeGuid, now, Wanted.SHARE_TARGET_WINDOW, Wanted.SHARE_TARGET_MAX) then return false, "target" end
	return true
end

-- A row's Horde side and Olympian side as the wire carries them: (horde GUID, Olympian GUID, the
-- Horde player's name).
function Share.Sides(e)
	if e.action == "bounty" then return e.killerGuid, e.victimGuid, e.killerName end
	return e.victimGuid, e.killerGuid, e.victimName
end

-- This client's own row on the channel (WK~1), its done marking it shared (saved); one the channel
-- did not take goes again later (Share.Resend). Nothing goes from a client outside an Olympus
-- guild, of the Horde, or one the moderators took off (net-off).
function Share.Send(e)
	if type(e) ~= "table" or not e.own or e.void or not e.digest then return false, "row" end
	local C = ns.Comm
	if type(C) ~= "table" or type(C.Send) ~= "function" then return false, "transport" end
	if not ns.IsMember or ns.IsMember() ~= true or ns.faction == "Horde" or NetOff() then return false, "member" end
	local guild = Sight.OwnGuild()
	if not guild then return false, "guild" end
	local horde, own, name = Share.Sides(e)
	name = CleanName(name)
	if not WireGuid(horde) or not WireGuid(own) or not name then return false, "shape" end
	local scope = Scope()
	-- (1.2.3: WK~2, what the row is worth after the GUIDs, Bounty.Wire; WK~1 for a row without it.)
	local worth = Bounty.Wire(e)
	local fields = { "WK", worth and 2 or 1, scope, guild, e.digest, e.at, e.month, e.kind == "SELF_DEATH" and "S" or "P",
		WireGuid(horde), WireGuid(own) }
	if worth then fields[#fields + 1] = worth end
	fields[#fields + 1] = name
	local body = table.concat(fields, "~")
	if #body > 255 then return false, "size" end
	local sent = C.Send("CHANNEL", body, "wanted-kill:" .. e.digest, false, false, function(went)
		if went then e.shared = true end
		local key = went and "sent" or "unsent"
		Share.counts[key] = (Share.counts[key] or 0) + 1
	end, { owner = Wanted, guardKey = "wanted-kill", guard = function()
		return ns.IsMember() == true and ns.faction ~= "Horde" and not NetOff() and Scope() == scope
	end })
	return sent == true
end

-- This client's own rows the channel did not take (sent while it was not on it, or refused there)
-- go again, SHARE_RESEND_MAX at a time, while they are fresh (SHARE_AGE).
function Share.Resend()
	local s = Store(false)
	if not s then return 0 end
	local now, n = math.floor(Clock()), 0
	for i = #s.evidence, 1, -1 do
		if n >= Wanted.SHARE_RESEND_MAX then break end
		local e = s.evidence[i]
		local t = s.targets[e.targetKey]
		if e.own and not e.shared and not e.void and type(t) == "table" and t.active == true
			and now - (tonumber(e.at) or 0) <= Wanted.SHARE_AGE and Share.Send(e) then n = n + 1 end
	end
	return n
end

function Share.ScheduleResend(gen, wait)
	if not ns.After then return end
	ns.After(wait, "wanted resend", function()
		if gen ~= Share.resendGen then return end
		Share.Resend()
		Share.ScheduleResend(gen, Wanted.SHARE_RESEND_EVERY)
	end)
end

-- A relayed row's id remembered (SHARE_HEARD_MAX): this reviewer relays it no more.
function Share.Heard(id)
	if Share.relayed[id] then return end
	Share.relayed[id] = true
	Share.relayedOrder[#Share.relayedOrder + 1] = id
	while #Share.relayedOrder > Wanted.SHARE_HEARD_MAX do Share.relayed[table.remove(Share.relayedOrder, 1)] = nil end
end

-- A reviewer's relay of a row his client holds (via "R": one he took now, "C": a catch-up answer),
-- while Comm's queue has room (SHARE_ROOM kept free).
function Share.Relay(e, via)
	local C = ns.Comm
	if type(C) ~= "table" or type(C.Send) ~= "function" or not Wanted.CanPublish(ns.me) then return false end
	if type(C.QueueRoom) == "function" and C.QueueRoom() <= Wanted.SHARE_ROOM then return false end
	local horde, own, name = Share.Sides(e)
	local from = CleanName(e.from)
	name = CleanName(name)
	if not (e.own or e.peer) or e.void or not from or not name or not WireGuid(horde) or type(e.digest) ~= "string" then return false end
	local scope = Scope()
	-- (1.2.3: what his client froze for the row, as it counts it: Bounty.Wire.)
	local worth = Bounty.Wire(e)
	-- Relay v3 keeps two independent facts: whether this client bound the character GUID and
	-- whether it independently verified the sender's Olympus membership.  Recipients may keep an
	-- unverified event for the local/perennial history, but never promote its points into WY.
	local fields = { "WK", via, worth and 4 or 3, scope, from, WireGuid(own) and 1 or 0, e.memberVerified ~= false and 1 or 0,
		e.digest, e.at, e.month,
		e.kind == "SELF_DEATH" and "S" or "P", WireGuid(horde), WireGuid(own) or "-" }
	if worth then fields[#fields + 1] = worth end
	fields[#fields + 1] = name
	local body = table.concat(fields, "~")
	if #body > 255 then return false end
	Share.Heard(e.id)
	return C.Send("CHANNEL", body, "wanted-relay:" .. via .. ":" .. e.id, false, false, nil, { owner = Wanted, guardKey = "wanted-relay",
		guard = function() return Wanted.CanPublish(ns.me) and Scope() == scope end }) == true
end

-- A reviewer relays a row he took from a member (once, SHARE_RELAY_DELAY and a part of 8 s of his
-- own later, unless another reviewer's relay of it came first), so current clients can retain it
-- across guilds and distinguish a roster-backed confirmation from a self-asserted membership.
function Share.RelaySoon(e)
	local function Go()
		if Share.relayed[e.id] or e.void or not Wanted.CanPublish(ns.me) then return end
		Share.Relay(e, "R")
	end
	if ns.After then ns.After(Wanted.SHARE_RELAY_DELAY + Share.Offset() % 8, "wanted relay", Go) else Go() end
end

-- WK's fields, or nil. (1.2.3: WK~2 and its relays carry what the row is worth after the GUIDs,
-- <office>~<level>~<Horde level>[+]: Bounty.Wire, Bounty.Unwire; WK~1 is a row without it.
-- 1.2.4: relay v3/v4 also carries the independent membership bit; v4 carries worth.)
function Share.Parse(text)
	if type(text) ~= "string" or #text > 255 then return nil end
	local r, worth = {}, nil
	if text:sub(1, 5) == "WK~1~" then
		r.scope, r.guild, r.digest, r.at, r.month, r.kind, r.horde, r.own, r.name =
			text:match("^WK~1~(%x+)~([^~]+)~(%x+)~(%d+)~(%d+)~([PS])~([^~]+)~([^~]+)~([^~]+)$")
	elseif text:sub(1, 5) == "WK~2~" then
		r.scope, r.guild, r.digest, r.at, r.month, r.kind, r.horde, r.own, worth, r.name =
			text:match("^WK~2~(%x+)~([^~]+)~(%x+)~(%d+)~(%d+)~([PS])~([^~]+)~([^~]+)~(%u~%d+~%d+%+?)~([^~]+)$")
	elseif text:sub(5, 7) == "~4~" then
		r.via, r.scope, r.from, r.bound, r.member, r.digest, r.at, r.month, r.kind, r.horde, r.own, worth, r.name =
			text:match("^WK~([RC])~4~(%x+)~([^~]+)~([01])~([01])~(%x+)~(%d+)~(%d+)~([PS])~([^~]+)~([^~]+)~(%u~%d+~%d+%+?)~([^~]+)$")
	elseif text:sub(5, 7) == "~3~" then
		r.via, r.scope, r.from, r.bound, r.member, r.digest, r.at, r.month, r.kind, r.horde, r.own, r.name =
			text:match("^WK~([RC])~3~(%x+)~([^~]+)~([01])~([01])~(%x+)~(%d+)~(%d+)~([PS])~([^~]+)~([^~]+)~([^~]+)$")
	elseif text:sub(5, 7) == "~2~" then
		r.via, r.scope, r.from, r.bound, r.digest, r.at, r.month, r.kind, r.horde, r.own, worth, r.name =
			text:match("^WK~([RC])~2~(%x+)~([^~]+)~([01])~(%x+)~(%d+)~(%d+)~([PS])~([^~]+)~([^~]+)~(%u~%d+~%d+%+?)~([^~]+)$")
	else
		r.via, r.scope, r.from, r.bound, r.digest, r.at, r.month, r.kind, r.horde, r.own, r.name =
			text:match("^WK~([RC])~1~(%x+)~([^~]+)~([01])~(%x+)~(%d+)~(%d+)~([PS])~([^~]+)~([^~]+)~([^~]+)$")
	end
	if not r.scope or #r.digest ~= 16 then return nil end
	if worth then
		r.worth = Bounty.Unwire(worth)
		if not r.worth then return nil end
	end
	r.at, r.month = Whole(tonumber(r.at), 0, 4294967295), Whole(tonumber(r.month), 0, 120000)
	r.horde = GameGuid(r.horde)
	if r.own == "-" then r.own = nil elseif r.own then r.own = GameGuid(r.own) or false end
	if not r.at or not r.month or not r.horde or r.own == false or not r.via and not r.own then return nil end
	return r
end

-- Whether two names can be one character's: the same given name (Forever's death recap, and a
-- client the game's lookup did not answer, write "Given-Realm"; the lookup "Given Surname-Realm").
function Share.SameGiven(a, b)
	local function Given(name) return ns.Fold((ns.ShortName(tostring(name or "")) or ""):match("^%s*(%S+)") or "") end
	local given = Given(a)
	return given ~= "" and given == Given(b)
end

-- (1.2.4) A reviewer's relay restores the row unless this client knows better; only a current
-- relay that separately marks membership verified can contribute it to the signed global board. The
-- guild its sender's own messages named here (Data.ClaimedGuild: his row, a chat line, a census
-- report) makes him no member (Share.Member), as when he names our own guild and our roster lacks
-- him. A reviewer still relays rows he cannot prove, so every current client retains the local
-- history; his relay never overrules what this client proves.
function Share.Disowned(sender)
	local D = ns.Data
	if type(D) ~= "table" or type(D.ClaimedGuild) ~= "function" then return false end
	local ok, claimed = pcall(D.ClaimedGuild, sender)
	if not ok or type(claimed) ~= "string" then return false end
	return not Share.Member(sender, Sight.GuildName(claimed))
end

-- A later roster-backed relay may confirm a row this client already retained on the member's own
-- word.  Change provenance in place and rebuild the derived boards; the evidence id, notices and
-- local score do not change.
local function PromoteMembership(s, id, ownGuid)
	for _, held in ipairs(s.evidence) do
		if held.id == id then
			local changed = false
			if held.memberVerified == false then held.memberVerified, changed = true, true end
			-- The same confirming relay may be the first receiver-side proof of the sender's GUID.
			-- Bind only the Olympian side; the Horde side was already required independently.
			if ownGuid then
				if held.action == "claim" and not held.killerGuid then held.killerGuid, changed = ownGuid, true end
				if held.action == "bounty" and not held.victimGuid then held.victimGuid, changed = ownGuid, true end
			end
			if changed then Rebuild(s) Changed() end
			return changed
		end
	end
	return false
end

-- One shared row (WK) taken into this client's ledger: true and the row recorded, or false, why.
function Share.Take(dist, sender, row)
	if dist ~= "CHANNEL" then return false, "lane" end
	if not ns.IsMember or ns.IsMember() ~= true or not ns.me then return false, "member" end
	if ns.faction == "Horde" then return false, "faction" end
	if not row then return false, "shape" end
	if row.scope ~= Scope() then return false, "scope" end
	sender = CleanName(sender)
	if not sender then return false, "sender" end
	local relay = row.via ~= nil
	local from = relay and CleanName(row.from) or sender
	if not from then return false, "shape" end
	-- (Our own row, back in a reviewer's relay: this client holds it.)
	if SameName(from, ns.me) then return false, "own" end
	if relay and not Wanted.CanPublish(sender) then return false, "authority" end
	local now = math.floor(Clock())
	if row.at > now + Wanted.GLOBAL_SKEW or now - row.at > Wanted.SHARE_AGE then return false, "stale" end
	if not Whole(row.month, MonthNow() - Wanted.MAX_MONTHS + 1, MonthNow() + 1) then return false, "shape" end
	-- (1.2.4: each refusal its own word in /oly wanted status, "olympus" for all three before:
	-- "hidden", the moderators hide him, or the guild his row names; "stranger", no member here,
	-- Share.Member; "olympian", the Horde side is a member.)
	local guild = not relay and Sight.GuildName(row.guild) or nil
	local M = ns.Moderation
	if type(M) == "table" and not M.missing and type(M.Hides) == "function" then
		local ok, hidden = pcall(M.Hides, from, guild, true)
		if not ok or hidden then return false, "hidden" end
	end
	local memberVerified = Wanted.CanPublish(from) == true
	if not relay and not memberVerified then
		local member, verified = Share.Member(from, guild)
		if not member then return false, "stranger" end
		memberVerified = verified == true
	elseif relay then
		-- Only v3/v4 can carry the relayer's independent membership result. Older relay formats still
		-- restore the visible history, but cannot silently become points in a newly signed board.
		memberVerified = row.member == "1"
	end
	if relay and not Wanted.CanPublish(from) and Share.Disowned(from) then return false, "stranger" end
	local horde = Identity(row.name, row.horde)
	if not horde or not horde.name then return false, "shape" end
	-- The Horde side as the sender's client proved it, unless this client sees him otherwise.
	if VerifiedOlympian(horde) then return false, "olympian" end
	local seen, contradicted = KnownHorde(horde)
	if contradicted then return false, "faction" end
	if not seen and type(GetPlayerInfoByGUID) == "function" then
		local ok, _, _, _, race = pcall(GetPlayerInfoByGUID, horde.guid)
		if ok and type(race) == "string" and not Secret(race) and Share.ALLIANCE_RACES[race] then return false, "faction" end
	end
	-- His name as this client's game knows his GUID (a unit of his, or its lookup), never as the
	-- row writes it: a row that gives his GUID another character's name is refused. One the game
	-- cannot check keeps the row's name as its sender's word (wire): it finds and teaches no entry
	-- by that name, and holds the name's alias only where no better entry does (Share.Name).
	local known = seen and seen.name or Share.InfoName(horde.guid)
	local wire = known == nil
	if known then
		if not Share.SameGiven(known, horde.name) then return false, "identity" end
		horde = Identity(known, horde.guid)
		if not horde or not horde.name then return false, "shape" end
		if VerifiedOlympian(horde) then return false, "olympian" end
	end
	-- The Olympian side: the sender, his GUID only where this client proves it is his (or the
	-- reviewer who relays it says his own client did).
	local ownGuid = row.own
	if ownGuid then
		local mine = GuidIsSender(ownGuid, from)
		if mine == false then return false, "not-own" end
		if mine == nil and not (relay and row.bound == "1") then ownGuid = nil end
	end
	local s = Store(true)
	if not s then return false, "store" end
	local key = ns.Fold(from) .. "#" .. row.digest
	if s.voids[key] then return false, "void" end
	local id = "p:" .. key
	if s.seen[id] then
		if memberVerified then PromoteMembership(s, id, ownGuid) end
		return false, "replay"
	end
	local admitted, why = Share.Admit(relay and sender or from, horde.guid, now, relay)
	if not admitted then return false, why end
	local olympian = Identity(from, ownGuid)
	local killer, victim, side = olympian, horde, "victim"
	if row.kind == "S" then killer, victim, side = horde, olympian, "killer" end
	-- (1.2.3: what the row is worth, as this client freezes it: never above what its sender says,
	-- nor an office it cannot verify, nor a level above one it sees: Bounty.Intake.)
	local worth = row.worth and Bounty.Intake(row.worth, from, row.guild, relay, ownGuid, horde.guid) or nil
	-- (1.2.4: guild, the one the row names, kept on a claim for the avenged notice's words alone:
	-- RecordKill, Bounty.AvengeOpen.)
	local ok, e = RecordKill(row.kind == "S" and "SELF_DEATH" or "PARTY_KILL", id, killer, victim,
		{ peer = true, from = from, digest = row.digest, id = id, at = row.at, month = row.month, horde = side, wire = wire, bounty = worth,
			guild = Sight.GuildName(row.guild), memberVerified = memberVerified })
	-- A client may have kept the direct row before a roster-backed reviewer repeats it. Promote the
	-- existing evidence in place and rebuild; never add a second death/kill or a second notice.
	if not ok and e == "replay" and memberVerified then
		PromoteMembership(s, id, ownGuid)
	end
	-- (A reviewer relays what he took from a member; another reviewer's own row every client takes
	-- from him directly.)
	if ok and not relay and Wanted.CanPublish(ns.me) and not Wanted.CanPublish(from) then Share.RelaySoon(e) end
	return ok, e
end

-- The WK handler: a member's row, or a reviewer's relay of one.
function Wanted.HandleShared(dist, sender, text)
	local row = Share.Parse(text)
	-- A reviewer's relay of a row, whatever this client makes of it: this reviewer's own relay of it
	-- is not needed any more, nor, after a catch-up answer, his own answer.
	if row and row.via and dist == "CHANNEL" and Wanted.CanPublish(CleanName(sender)) then
		local from = CleanName(row.from)
		if from then Share.Heard("p:" .. ns.Fold(from) .. "#" .. row.digest) end
		if row.via == "C" then Share.catchHeard = math.floor(Clock()) end
	end
	local ok, e = Share.Take(dist, sender, row)
	-- (Not noted: our own row coming back, and a relay of a row held already.)
	if ok or not (e == "own" or e == "replay" and row and row.via) then
		Share.Note(row and row.via and "relay" or "heard", ok, e, row and row.name, row and row.from or sender, row and row.guild)
	end
	return ok, e
end

-- A reviewer's mark on the channel (WV): "T" a Horde player taken off (a: his GUID), "V" a row
-- voided (a: its sender, b: its digest). at: when (now by default).
function Share.SendMark(kind, a, b, at)
	local C = ns.Comm
	if type(C) ~= "table" or type(C.Send) ~= "function" or not Wanted.CanPublish(ns.me) then return false end
	at = Whole(at, 0, 4294967295) or math.floor(Clock())
	local scope, body, key = Scope(), nil, nil
	if kind == "T" then
		local wire = WireGuid(a)
		if not wire then return false end
		body, key = table.concat({ "WV", "T", 1, scope, wire, at }, "~"), wire
	else
		local from = CleanName(a)
		if not from or type(b) ~= "string" or not b:match("^%x+$") or #b ~= 16 then return false end
		body, key = table.concat({ "WV", "V", 1, scope, from, b, at }, "~"), ns.Fold(from) .. "#" .. b
	end
	if #body > 255 then return false end
	return C.Send("CHANNEL", body, "wanted-mark:" .. kind .. ":" .. key, false, false, nil, { owner = Wanted, guardKey = "wanted-mark",
		guard = function() return Wanted.CanPublish(ns.me) and Scope() == scope end }) == true
end

-- The WV handler: a reviewer's word that a Horde player is off (his rows count for nothing here
-- any more, and a later event does not bring him in: an entry is kept for him, off), or that one
-- member's row is void (and one heard later too).
function Share.Mark(dist, sender, text)
	if dist ~= "CHANNEL" then return false, "lane" end
	if not ns.IsMember or ns.IsMember() ~= true or not ns.me then return false, "member" end
	if type(text) ~= "string" or #text > 255 then return false, "shape" end
	sender = CleanName(sender)
	if not sender or SameName(sender, ns.me) then return false, "own" end
	if not Wanted.CanPublish(sender) then return false, "authority" end
	local kind, scope, a, b, at = text:sub(4, 4), nil, nil, nil, nil
	if kind == "T" then scope, a, at = text:match("^WV~T~1~(%x+)~([^~]+)~(%d+)$")
	elseif kind == "V" then scope, a, b, at = text:match("^WV~V~1~(%x+)~([^~]+)~(%x+)~(%d+)$") end
	if not scope then return false, "shape" end
	if scope ~= Scope() then return false, "scope" end
	at = Whole(tonumber(at), 0, 4294967295)
	local now = math.floor(Clock())
	if not at or at > now + Wanted.GLOBAL_SKEW or now - at > Wanted.SHARE_AGE then return false, "stale" end
	if not Share.Count(Share.rates, "m:" .. ns.Fold(sender), now, Wanted.SHARE_RATE_WINDOW, Wanted.SHARE_RELAY_MAX) then return false, "rate" end
	local s = Store(true)
	if not s then return false, "store" end
	if kind == "T" then
		local guid = GameGuid(a)
		if not guid then return false, "shape" end
		local key = GuidKey(guid)
		local t = s.targets[s.aliases[key] or key]
		if type(t) == "table" and t.guid == guid then
			if t.active ~= true then return false, "held" end
			Share.TakeOff(s, t, sender, at)
		else
			-- No entry here: one is kept for him, off, so that a later event does not bring him in.
			-- (Apart from the list: it takes no place there, MAX_REMOVED.)
			t = { key = key, guid = guid, active = false, removedAt = at, removedBy = sender, addedAt = at, source = "removed",
				current = 0, lifetimeKills = 0, cycle = 1, openSince = at, victims = {}, claims = {}, victimOverflow = 0 }
			s.targets[key], s.aliases[key] = t, key
			Share.TrimRemoved(s)
		end
		Audit(s, "remove", t.key, sender)
		if opened == t.key then mode, opened = "list", nil end
	else
		local from = CleanName(a)
		if not from or #b ~= 16 then return false, "shape" end
		if s.voids[ns.Fold(from) .. "#" .. b] then return false, "held" end
		Share.KeepVoid(s, from, b, at)
		for _, e in ipairs(s.evidence) do
			if not e.void and e.digest == b and SameName(e.from, from) then
				e.void, e.correctedAt, e.correctedBy = true, at, sender
				Audit(s, "correct", e.targetKey, e.id)
			end
		end
		Rebuild(s)
	end
	Changed()
	return true
end

function Wanted.HandleMark(dist, sender, text)
	local ok, why = Share.Mark(dist, sender, text)
	if ok or why ~= "own" and why ~= "held" then Share.Note("mark", ok, why, nil, sender) end
	return ok, why
end

-- A late login's catch-up ask (W4, AskGlobal): a reviewer answers with the Horde players taken off
-- and the rows voided lately (SHARE_CATCH_MARKS each), then the newest rows his client holds
-- (SHARE_CATCH_ROWS, of SHARE_AGE), once every GLOBAL_ASK_GAP at most, a part of 20 s of his own
-- after the ask, and not when another reviewer's answer came first; only what Comm's queue has
-- room for (SHARE_ROOM kept free).
function Share.Answer(dist, sender, text)
	if dist ~= "CHANNEL" or text ~= "W4~1" or SameName(sender, ns.me) or not Wanted.CanPublish(ns.me) then return false end
	local now = math.floor(Clock())
	if now - Share.catchReplied < Wanted.GLOBAL_ASK_GAP then return false, "rate" end
	Share.catchReplied = now
	local function Go()
		if Share.catchHeard >= now or not Wanted.CanPublish(ns.me) then return end
		Share.CatchUp()
	end
	if ns.After then ns.After(2 + Share.Offset() % 20, "wanted catch-up", Go) else Go() end
	return true
end

function Share.CatchUp()
	local s, C = Store(false), ns.Comm
	if not s or type(C) ~= "table" then return 0 end
	local now, n = math.floor(Clock()), 0
	local function Fresh(at) return now - (tonumber(at) or 0) <= Wanted.SHARE_AGE end
	local off = {}
	for _, t in pairs(s.targets) do if t.active ~= true and Guid(t.guid) and Fresh(t.removedAt) then off[#off + 1] = t end end
	table.sort(off, function(a, b) return (a.removedAt or 0) > (b.removedAt or 0) end)
	for i = 1, math.min(#off, Wanted.SHARE_CATCH_MARKS) do
		if type(C.QueueRoom) == "function" and C.QueueRoom() <= Wanted.SHARE_ROOM then return n end
		if Share.SendMark("T", off[i].guid, nil, off[i].removedAt) then n = n + 1 end
	end
	local voids = {}
	for _, v in pairs(s.voids) do if type(v) == "table" and Fresh(v.at) then voids[#voids + 1] = v end end
	table.sort(voids, function(a, b) return (a.at or 0) > (b.at or 0) end)
	for i = 1, math.min(#voids, Wanted.SHARE_CATCH_MARKS) do
		if type(C.QueueRoom) == "function" and C.QueueRoom() <= Wanted.SHARE_ROOM then return n end
		if Share.SendMark("V", voids[i].from, voids[i].digest, voids[i].at) then n = n + 1 end
	end
	-- The newest rows, sent oldest first: each client takes them in the order of the deaths.
	local rows = {}
	for i = #s.evidence, 1, -1 do
		if #rows >= Wanted.SHARE_CATCH_ROWS then break end
		local e = s.evidence[i]
		local t = s.targets[e.targetKey]
		if (e.own or e.peer) and not e.void and Fresh(e.at) and type(t) == "table" and t.active == true then rows[#rows + 1] = e end
	end
	for i = #rows, 1, -1 do if Share.Relay(rows[i], "C") then n = n + 1 end end
	return n
end

---------------------------------------------------------------------------
-- The bounty (1.2.3, Daniel's decisions of 2026-10-11)
--
-- A death adds to the Horde player's open bounty the victim's office (his highest only: the King
-- 100, a High Councillor 50, the master of an Olympus guild 30, a centurion 20, any other office
-- 10, a member 0) and his level. The same member killed by the same Horde player counts once in
-- REPEAT_GAP (corpse camping: the deaths in between stay, worth nothing), and one cycle's bounty
-- holds BOUNTY_MAX at most. A kill pays the killer one base point per ten Horde levels (rounded
-- up) and his whole open bounty, which then starts again at 0 (a new cycle); a kill with no bounty
-- open pays the small level base alone. A member who kills the very Horde player who killed him
-- within GRUDGE_DAYS (his own death row and his own kill row, the same GUID) gets REVENGE more,
-- once a claim: his
-- claim closes it, another member's kill or the bounty's reset does not. A Slayer holds MAX_POINTS
-- at most. Only outside instances (a battleground, an arena, a dungeon, a raid), the death and the
-- kill alike: the captures refuse one inside, and a member's client never shares it.
--
-- What a row is worth is frozen where it is observed: the member's client freezes its own office
-- and level and the Horde player's level as it saw him (Bounty.Capture) and carries them on the
-- channel (WK~2); each receiver freezes them again, never higher than the row says nor than it can
-- verify (Bounty.Intake). Replays, reloads, folds and relays read only the frozen fields, and every
-- client scores the rows it holds with the same function in the order of the deaths (Bounty.Death,
-- Bounty.Claim), so the same rows give the same points on every client. A row without the fields
-- (WK~1, the combat-log adapter's, a saved row from before them) counts as it always did: 1 a
-- death, its open bounty for a kill, no level, no revenge.
--
-- Offices come only from what this client can trust (Bounty.OfficeOf): the pinned King (where none
-- is pinned, the master of the King's guild, as Borders.lua's rule says); the author-signed High
-- Council list; for a guild master the game's own rank on his own client, else Data.AuthorizedRank
-- (the roster of this client's guild, the signed leadership manifest, or the Crown's census rule of
-- two senders); a centurion or a correspondent from his guild master's own list (Nominees); the
-- signed titles (a Steward, an arbiter), the King's Hands, the Treasurer's characters, the author's.
-- Never a census rank alone, a guild officer's rank, or an office a row says that is not verified.
--
-- Levels: the member's own from his client at the moment (UnitLevel), never above what a receiver
-- sees of him (a unit, its own guild's fresh roster: levels never go down); the Horde player's from
-- a unit of his (his corpse, a nameplate, the target) or the one this client saw him by within a
-- minute, the game's "??" as this player's level plus HIDDEN_GAP (a floor, the least it can be),
-- none 0; a claim whose own level is a floor or none counts the highest exact level a row of the
-- open cycle saw, when higher. A death recap carries no level, and nothing is taken from a name.
--
-- Earlier deaths (Daniel: "tem como popular com mortes anteriores de olimpians que baixaram addon,
-- com mensagem única avisando que foram adicionados"): Olympus kept no death before 1.2.3 and the
-- game keeps no PvP history, but its death recaps of this game session are still there (the
-- client's, as its Death Recap shows them: lost when the game closes, kept across a /reload).
-- Once a login, EARLIER_WAIT after it (Bounty.Earlier), every recap the game still holds is read:
-- the latest (no ID), and the IDs from 1 up it answers for (RECAP_IDS at most, stopping after
-- RECAP_MISSES unanswered in a row: an ID comes from the combat log, which Forever restricts, the
-- chat's death link or the damage meter, and the client's UI source shows no other). Each goes
-- through the live death's own gate (Bounty.KillingBlow, Bounty.Hostile: an explicit hostile Horde
-- player's killing blow with both identities), outside an instance (read only outside one, and
-- never one dated while this client knew it was inside: Bounty.Spans), with the same REPEAT_GAP and
-- caps, the member's office and level frozen at the reading, and is shared like a live death
-- (EARLIER_MAX added a reading, the newest: each member's client takes them all within its limit
-- for one member; the rest at the next login). Each recap is marked read (s.recapsRead, by its
-- killing blow), counted or not, the live death's too, so none ever counts twice. The member is told once, in an Olympus copy window (never the chat, never the
-- game's popups; it takes no keyboard, in either input mode), each death added a line: the killer,
-- his level, the time and the points it added to his bounty; nothing when none was added. The
-- window waits out combat, an instance, a death and the privacy page (shown, or waiting to ask this
-- session), and is saved until it shows (s.earlierNotice), so a /reload before then never loses it.
-- A death typed or reported by hand is never taken: it could not be told from a forged one.
---------------------------------------------------------------------------

-- The bounty's weights (Daniel's): one table.
Bounty.SCORE = {
	OFFICE = { K = 100, H = 50, G = 30, C = 20, O = 10, M = 0 }, -- the victim's highest office (Bounty.OfficeOf)
	VICTIM_LEVEL = 1,    -- times the victim's level, added to his office for each death
	KILL_LEVEL_STEP = 10,-- one base point per this many Horde-player levels, rounded up
	REVENGE = 100,       -- paid to a member who kills the very Horde player who killed him...
	GRUDGE_DAYS = 14,    -- ...within this many days of that death, once a claim
	REPEAT_GAP = 600,    -- one member killed by one Horde player counts once in this many seconds
	-- A kill pays its small level base even with no bounty open, so corpse camping and a Horde
	-- friend killed in a loop must not pay it again and again.
	KILL_GAP = 3600,     -- one member's kills of one Horde player pay his level once in this many seconds (the bounty always)
	REVENGE_GAP = 86400, -- and the revenge on him once in this many seconds
	BOUNTY_MAX = 2000,   -- the most one bounty cycle holds
	MAX_POINTS = 100000, -- the most one claim pays, and a Slayer holds (Wanted.MAX_POINTS, what WY carries)
	HIDDEN_GAP = 10,     -- a level the game hides ("??") counts as this player's level plus this, at least
	LEVEL_MAX = 60,      -- every level's clamp when the game gives no highest level (GetMaxPlayerLevel)
	LEGACY_DEATH = 1,    -- a death in a row without the fields (WK~1, before them)
}
Bounty.OFFICES = { "K", "H", "G", "C", "O", "M" } -- the highest first
Bounty.STATE_MAX = 64      -- members one entry keeps a gap and a grudge for, each (the oldest go)
Bounty.RECAP_IDS = 256     -- recap IDs the earlier deaths' reader asks the game about, at most...
Bounty.RECAP_MISSES = 8    -- ...and it stops after this many unanswered in a row once one answered
Bounty.RECAP_READ_MAX = 64 -- recaps kept as read (the oldest go)
Bounty.INSIDE_MAX = 16     -- this client's own times in an instance kept (the oldest go)
Bounty.EARLIER_WAIT = 20   -- the earlier deaths are read this long after login (the game's lookups ready)
Bounty.EARLIER_MAX = 6     -- earlier deaths added at most a reading (the newest), within SHARE_RATE_MAX
Bounty.NOTICE_TICK = 15    -- their notice, while it waits, is tried again this often

-- A level as the rows keep it: a whole number, 0 for none.
function Bounty.Level(v) return Whole(v, 0, 255) or 0 end

-- The game's highest level: every level's clamp.
function Bounty.LevelMax()
	if type(GetMaxPlayerLevel) == "function" then
		local ok, v = pcall(GetMaxPlayerLevel)
		v = ok and not Secret(v) and Whole(v, 1, 255) or nil
		if v then return v end
	end
	return Bounty.SCORE.LEVEL_MAX
end

-- An office's place, 1 the highest; nil for none.
function Bounty.Rank(office)
	for i, o in ipairs(Bounty.OFFICES) do if o == office then return i end end
	return nil
end

-- The lower of two offices (an unknown one counts as a member's).
function Bounty.Lower(a, b)
	local last = #Bounty.OFFICES
	return Bounty.OFFICES[math.max(Bounty.Rank(a) or last, Bounty.Rank(b) or last)]
end

-- The scoring itself, pure and the same on every client: what one death adds...
function Bounty.DeathPoints(office, ml)
	local S = Bounty.SCORE
	return (S.OFFICE[office] or 0) + S.VICTIM_LEVEL * Bounty.Level(ml)
end
-- ...the level a kill pays for: its own exact one, else the higher of its floor (or none) and the
-- highest exact level a row of the open cycle saw...
function Bounty.ClaimLevel(hl, hf, cycle)
	hl = Bounty.Level(hl)
	if hl > 0 and not hf then return hl end
	return math.max(hl, Bounty.Level(cycle))
end
-- ...the deliberately small level base for any qualifying Horde kill...
function Bounty.BasePoints(level)
	level = Bounty.Level(level)
	return level > 0 and math.ceil(level / Bounty.SCORE.KILL_LEVEL_STEP) or 0
end
-- ...and what a kill pays. The bounty and revenge keep their existing weight.
function Bounty.ClaimPoints(level, bounty, revenge)
	local S = Bounty.SCORE
	return math.min(S.MAX_POINTS, Bounty.BasePoints(level) + math.max(0, math.floor(tonumber(bounty) or 0))
		+ (revenge and S.REVENGE or 0))
end

-- Score-version 1's formula exists only for validating retained checkpoint claims during the
-- one-way migration. It is never used for a new claim.
function Bounty.LegacyClaimPoints(level, bounty, revenge)
	local S = Bounty.SCORE
	return math.min(S.MAX_POINTS, 2 * Bounty.Level(level) + math.max(0, math.floor(tonumber(bounty) or 0))
		+ (revenge and S.REVENGE or 0))
end

-- This character's saved Slayer total, when the store actually has one. The score migration uses
-- the number the player saw before it rebuilds the derived table, then the number made from the
-- same retained history afterwards. A missing old row is not silently treated as a loss.
local function OwnSlayerTotal(s)
	local name = CleanName(ns.me)
	if not name then return nil, nil end
	local guid
	if type(UnitGUID) == "function" then
		local ok, value = pcall(UnitGUID, "player")
		if ok and not Secret(value) then guid = Guid(value) end
	end
	local row = ResolveSlayer(s, { name = name, guid = guid }, false, false)
	return row and Whole(row.total, 0, Wanted.MAX_POINTS) or nil, NameKey(name)
end

-- Saved score-version 1 data has two sources. Live evidence still contains the frozen facts and
-- Rebuild can score it exactly. A checkpoint has only its retained claims plus aggregate paid
-- rows: each retained claim is recalculated only when its old points match the old formula and
-- its Slayer/amount can be reconciled with that aggregate. Anything older or malformed is kept
-- in scoreArchive, never guessed and never mixed into a version-2 ranking.
function Wanted.MigrateScoring(s)
	if type(s) ~= "table" or s.scoreVersion == Wanted.SCORE_VERSION then return false end
	local savedVersion = Whole(s.scoreVersion, 1, 2147483647)
	if savedVersion and savedVersion > Wanted.SCORE_VERSION then return false end
	local from = Whole(savedVersion, 1, Wanted.SCORE_VERSION - 1) or 1
	local oldOwn, ownKey = OwnSlayerTotal(s)
	local archive = { from = from, to = Wanted.SCORE_VERSION, at = math.floor(Clock()), targets = {},
		recalculatedClaims = 0, archivedClaims = 0, archivedPoints = 0 }
	local bases = {}
	for targetKey, t in pairs(type(s.targets) == "table" and s.targets or {}) do
		if type(targetKey) == "string" and type(t) == "table" and type(t.base) == "table" then
			local base = TargetDerived(t.base)
			local oldPaid, remaining, newPaid = CopySlayers(base.paid), {}, {}
			for _, p in pairs(oldPaid) do Share.AddPaid(s, remaining, p) end
			local claims = CopyList(base.claims, Wanted.MAX_CLAIMS)
			local invalid = 0
			for _, claim in ipairs(claims) do
				local ident = type(claim) == "table" and Identity(claim.slayer, claim.slayerGuid) or nil
				local at = type(claim) == "table" and Whole(claim.at, 0, 4294967295) or nil
				local level = type(claim) == "table" and Whole(claim.level, 0, 255) or nil
				local bounty = type(claim) == "table" and Whole(claim.bounty, 0, Bounty.SCORE.BOUNTY_MAX) or nil
				local oldPoints = type(claim) == "table" and Whole(claim.points, 0, Wanted.MAX_POINTS) or nil
				local revengeShape = type(claim) == "table" and (claim.revenge == nil or claim.revenge == false or claim.revenge == true)
				local revenge = type(claim) == "table" and claim.revenge == true or false
				local expected = level and bounty and Bounty.LegacyClaimPoints(level, bounty, revenge) or nil
				local key = ident and Share.SlayerKey(s, ident.guidKey or ident.nameKey) or nil
				local paid = key and remaining[key] or nil
				local reconciled = oldPoints == 0 or paid and (paid.claims or 0) >= 1 and (paid.total or 0) >= oldPoints
				if ident and at and level and bounty and oldPoints == expected and revengeShape and reconciled then
					local month = Whole(claim.month, 0, 200000) or Bounty.MonthAt(at)
					local points = Bounty.ClaimPoints(level, bounty, revenge)
					if oldPoints > 0 then
						paid.total, paid.claims = paid.total - oldPoints, paid.claims - 1
						local monthPoints = type(paid.months) == "table" and tonumber(paid.months[month]) or nil
						if monthPoints then
							monthPoints = math.max(0, monthPoints - oldPoints)
							if monthPoints > 0 then
								paid.months[month] = monthPoints
								if type(paid.monthClaims) == "table" then
									paid.monthClaims[month] = math.max(0, (tonumber(paid.monthClaims[month]) or 0) - 1)
								end
							else
								paid.months[month] = nil
								if type(paid.monthAt) == "table" then paid.monthAt[month] = nil end
								if type(paid.monthClaims) == "table" then paid.monthClaims[month] = nil end
							end
						end
					end
					if oldPoints ~= points then claim.legacyPoints = oldPoints end
					claim.points, claim.month, claim.scoreVersion, claim.unranked = points, month, Wanted.SCORE_VERSION, nil
					if points > 0 then
						local row = newPaid[key]
						if not row then
							row = { key = key, name = ident.name, guid = ident.guid, total = 0, claims = 0,
								months = {}, monthAt = {}, monthClaims = {} }
							newPaid[key] = row
						end
						Share.Pay(row, points, at, month, true)
					end
					archive.recalculatedClaims = archive.recalculatedClaims + 1
				else
					claim.scoreVersion, claim.unranked = from, true
					archive.archivedClaims = archive.archivedClaims + 1
					invalid = invalid + 1
				end
			end
			local unresolved = {}
			for key, row in pairs(remaining) do
				if (row.total or 0) > 0 or (row.claims or 0) > 0 then
					unresolved[key] = row
					archive.archivedPoints = archive.archivedPoints + (row.total or 0)
				end
			end
			if next(unresolved) or invalid > 0 then archive.targets[targetKey] = { paid = unresolved, invalidClaims = invalid } end
			base.paid, base.claims = newPaid, claims
			bases[targetKey] = base
		end
	end
	for targetKey, base in pairs(bases) do s.targets[targetKey].base = base end
	archive.baseSlayers = CopySlayers(s.baseSlayers)
	for _, row in pairs(archive.baseSlayers) do
		archive.archivedPoints = archive.archivedPoints + (row.total or 0)
	end
	s.baseSlayers, s.scoreArchive = {}, archive
	-- A signed board contains derived totals, so a version-1 word cannot survive this migration.
	s.global, s.globalHeads = nil, nil
	local publisher = type(ns.db) == "table" and type(ns.db.wantedPublisher) == "table" and ns.db.wantedPublisher or nil
	if publisher and type(publisher.last) == "table" and not tostring(publisher.last.body or ""):find("^WY~" .. Wanted.SCORE_VERSION .. "~") then
		publisher.last = nil
	end
	s.scoreVersion = Wanted.SCORE_VERSION
	Rebuild(s)
	local newOwn = select(1, OwnSlayerTotal(s)) or 0
	-- The balancing note belongs only to the character whose displayed total went down. It stays in
	-- the realm store until its parchment really opens; another character cannot consume it.
	if ownKey and oldOwn and oldOwn > newOwn then
		s.scoreMigrationLetter = { version = Wanted.SCORE_VERSION, who = ownKey, old = oldOwn, new = newOwn }
	else
		s.scoreMigrationLetter = nil
	end
	return true
end

-- What a row is worth, checked: { office, ml (the Olympian's level), hl (the Horde player's), hf
-- (hl is a floor) }, or nil for none.
function Bounty.Fields(v)
	if type(v) ~= "table" or not Bounty.Rank(v.office) then return nil end
	local hl = Bounty.Level(v.hl)
	return { office = v.office, ml = Bounty.Level(v.ml), hl = hl, hf = v.hf == true and hl > 0 or nil }
end
-- Whether a row carries what it is worth.
function Bounty.Scored(e) return type(e) == "table" and Bounty.Rank(e.office) ~= nil and type(e.hl) == "number" end
-- On the wire (WK~2): <office>~<level>~<Horde level>, "+" after a floor; nil for a row without it.
function Bounty.Wire(e)
	if not Bounty.Scored(e) then return nil end
	return ("%s~%d~%d%s"):format(e.office, Bounty.Level(e.ml), Bounty.Level(e.hl), e.hf and "+" or "")
end
function Bounty.Unwire(text)
	local office, ml, hl, floor = tostring(text or ""):match("^(%u)~(%d+)~(%d+)(%+?)$")
	if not office or not Bounty.Rank(office) or #ml > 3 or #hl > 3 then return nil end
	ml, hl = Whole(tonumber(ml), 0, 255), Whole(tonumber(hl), 0, 255)
	if not ml or not hl or floor == "+" and hl == 0 then return nil end
	return { office = office, ml = ml, hl = hl, hf = floor == "+" or nil }
end

-- A member's key in an entry's account: his name's (a shared row's Olympian is his sender, by the
-- name the server stamps; this client's own rows, its player's).
function Bounty.Who(name) return NameKey(name) or "?" end

-- Keep the persisted per-character keys, but compare only proved owners: reciprocal alt links,
-- this account's known characters or a verified account key (Debts.SameOwner). A missing helper
-- may still use Alts.Linked's confirmed group; a one-sided offer never joins it. Unknown players
-- stay independent. No new identity is inferred from a Horde character or from a claimed name.
function Bounty.SameWho(a, b)
	if a == b then return true end
	local an = type(a) == "string" and a:match("^n:(.+)$")
	local bn = type(b) == "string" and b:match("^n:(.+)$")
	if not an or not bn then return false end
	local D = ns.Debts
	if D and type(D.SameOwner) == "function" and D.SameOwner(an, bn) == true then return true end
	local A = ns.Alts
	if A and type(A.Linked) == "function" then
		for _, name in ipairs(A.Linked(an)) do if Bounty.Who(name) == b then return true end end
	end
	return false
end

-- Look through at most STATE_MAX retained keys. This also applies an old character's persisted
-- gap to its now-confirmed alt; closing a grudge clears all matching characters, not just the
-- one that delivered the killing blow. The original timestamps and expiry rules are unchanged.
function Bounty.OwnerAt(map, who, close)
	local at, checked = map[who], map[who] ~= nil and 1 or 0
	if close then map[who] = nil end
	for key, held in pairs(map) do
		if key ~= who then
			checked = checked + 1
			if checked > Bounty.STATE_MAX then break end
			if Bounty.SameWho(who, key) then
				if not at or held > at then at = held end
				if close then map[key] = nil end
			end
		end
	end
	return at
end

-- One of an entry's account's maps kept to STATE_MAX members: the oldest go (then by key).
function Bounty.Trim(map)
	local keys = {}
	for key in pairs(map) do keys[#keys + 1] = key end
	if #keys <= Bounty.STATE_MAX then return end
	table.sort(keys, function(a, b)
		if map[a] ~= map[b] then return map[a] < map[b] end
		return a < b
	end)
	for i = 1, #keys - Bounty.STATE_MAX do map[keys[i]] = nil end
end

-- An entry's own account (t.bounty), checked and copied: gap[member] = his last death that counted
-- (REPEAT_GAP), grudge[member] = his last death that counted, still open (the revenge), kill[member]
-- = his last kill of him that paid the level (KILL_GAP), revenged[member] = his last revenge on him
-- (REVENGE_GAP), hl = the highest exact level a row of the open cycle saw. Built again with the rest
-- (Rebuild), folded with the rest (Checkpoint).
Bounty.PARTS = { "gap", "grudge", "kill", "revenged" }
function Bounty.State(v)
	local out = { gap = {}, grudge = {}, kill = {}, revenged = {} }
	if type(v) ~= "table" then return out end
	for _, part in ipairs(Bounty.PARTS) do
		for key, at in pairs(type(v[part]) == "table" and v[part] or {}) do
			at = Whole(at, 0, 4294967295)
			if type(key) == "string" and #key <= 120 and at then out[part][key] = at end
		end
		Bounty.Trim(out[part])
	end
	local hl = Bounty.Level(v.hl)
	out.hl = hl > 0 and hl or nil
	return out
end

-- The entry's account as of a row's time: gaps and grudges that ran out let go.
function Bounty.Due(t, at)
	local st = t.bounty
	local whole = type(st) == "table"
	for _, part in ipairs(Bounty.PARTS) do whole = whole and type(st[part]) == "table" end
	if not whole then
		st = Bounty.State(st)
		t.bounty = st
	end
	local S = Bounty.SCORE
	for key, last in pairs(st.gap) do if at - last >= S.REPEAT_GAP then st.gap[key] = nil end end
	for key, last in pairs(st.grudge) do if at - last > S.GRUDGE_DAYS * 86400 then st.grudge[key] = nil end end
	for key, last in pairs(st.kill) do if at - last >= S.KILL_GAP then st.kill[key] = nil end end
	for key, last in pairs(st.revenged) do if at - last >= S.REVENGE_GAP then st.revenged[key] = nil end end
	return st
end

-- What one death adds to the entry's bounty (before its cap), and true when it is the same member's
-- again inside REPEAT_GAP (it adds nothing, and 1.2.4, no kill either); what it sets going for the
-- next rows. Called in the order of the deaths (ApplyEvidence).
function Bounty.Death(t, e)
	local at = Whole(e.at, 0, 4294967295) or 0
	local st = Bounty.Due(t, at)
	local who = Bounty.Who(e.victimName)
	if not Bounty.Scored(e) then
		st.grudge[who] = at
		Bounty.Trim(st.grudge)
		return Bounty.SCORE.LEGACY_DEATH
	end
	if not e.hf and Bounty.Level(e.hl) > (st.hl or 0) then st.hl = Bounty.Level(e.hl) end
	if Bounty.OwnerAt(st.gap, who) then return 0, true end
	st.gap[who], st.grudge[who] = at, at
	Bounty.Trim(st.gap)
	Bounty.Trim(st.grudge)
	return Bounty.DeathPoints(e.office, e.ml)
end

-- What a kill pays (the points, the level it paid for, whether a revenge) as of the open cycle;
-- nothing changes until it is paid (Bounty.Closed). The same member's kills of the same Horde
-- player pay his level once in KILL_GAP (corpse camping, a Horde friend killed in a loop: the open
-- bounty alone then, no level and no revenge), and the revenge on him once in REVENGE_GAP.
function Bounty.Claim(t, e)
	local at = Whole(e.at, 0, 4294967295) or 0
	local st = Bounty.Due(t, at)
	if not Bounty.Scored(e) then return t.current, 0, false end
	local who = Bounty.Who(e.killerName)
	if Bounty.OwnerAt(st.kill, who) then return Bounty.ClaimPoints(0, t.current, false), 0, false end
	local grudge = Bounty.OwnerAt(st.grudge, who)
	local level = Bounty.ClaimLevel(e.hl, e.hf, st.hl)
	local revenge = grudge ~= nil and grudge <= at and Bounty.OwnerAt(st.revenged, who) == nil
	return Bounty.ClaimPoints(level, t.current, revenge), level, revenge
end

-- A kill paid: the killer's grudge against him closed (paid or not), his kill gap and his revenge
-- gap started where they paid, a new cycle's levels.
function Bounty.Closed(t, e)
	local at = Whole(e.at, 0, 4294967295) or 0
	local st = Bounty.Due(t, at)
	local who = Bounty.Who(e.killerName)
	Bounty.OwnerAt(st.grudge, who, true)
	if Bounty.Scored(e) and Bounty.Level(e.level) > 0 then st.kill[who] = at Bounty.Trim(st.kill) end
	if e.revenge then st.revenged[who] = at Bounty.Trim(st.revenged) end
	st.hl = nil
end

-- This client's own guild, as the game says it.
function Bounty.OwnGuild()
	if type(GetGuildInfo) ~= "function" then return nil end
	local ok, guild = pcall(GetGuildInfo, "player")
	return ok and not Secret(guild) and type(guild) == "string" and guild ~= "" and guild or nil
end

-- This player's level now, 0 when the game gives none.
function Bounty.OwnLevel()
	local level = Share.UnitLevel("player")
	return level and level >= 1 and math.min(level, Bounty.LevelMax()) or 0
end

-- A level as this client saw it (Share.UnitLevel, Share.SeenLevel): the level, and whether it is a
-- floor (the game's "??": this player's level plus HIDDEN_GAP); 0 for none.
function Bounty.Seen(raw)
	local max = Bounty.LevelMax()
	if raw == -1 then return math.min(Bounty.OwnLevel() + Bounty.SCORE.HIDDEN_GAP, max), true end
	if type(raw) == "number" and raw >= 1 then return math.min(math.floor(raw), max), false end
	return 0, false
end

-- Every client counts a death's office the same way: only offices every client verifies from the
-- same signed or pinned source count.  Local roster/census appointments may still be shown by the
-- role UI, but never enter a relayed score because another honest client may not hold that session
-- evidence.  The base level, bounty and revenge remain unchanged.
-- The deterministic sources are: the pinned
-- King, the signed High Council list, the signed titles (a Steward, an arbiter), the Treasurer's
-- and the author's characters, and for a guild master the signed leadership manifest (Authority).
Bounty.LOCAL_OFFICES = false
-- (A member's level on this client's own guild's roster, which is at most Roster.AUTHORITY_FRESH
-- old, may be this many levels behind the level his own client gave: the clamp leaves them.)
Bounty.ROSTER_SLACK = 1

-- The Olympus guild name masters, or nil: with the signed leadership manifest alone (the same on
-- every client); with LOCAL_OFFICES, on his own client the game's own rank for him in guild, else
-- Data.AuthorizedRank (this client's own roster for its guild, the signed manifest, or the Crown's
-- census rule: two senders, one of them someone else). Never one report.
function Bounty.GuildMaster(name, guild)
	if not Bounty.LOCAL_OFFICES then
		local A = ns.Authority
		if type(A) ~= "table" or A.missing or type(A.Role) ~= "function" then return nil end
		local ok, g, rank = pcall(A.Role, name)
		local okF, fed = pcall(function() return type(g) == "string" and ns.IsFederation(g) end)
		return ok and rank == 0 and okF and fed == true and g or nil
	end
	if guild == nil then return nil end
	local okF, fed = pcall(function() return ns.IsFederation(guild) end)
	if not okF or fed ~= true then return nil end
	if SameName(name, ns.me) then
		local ok, mine, _, rank = pcall(GetGuildInfo, "player")
		if ok and not Secret(mine, rank) and mine == guild then return rank == 0 and guild or nil end
	end
	local D = ns.Data
	if type(D) ~= "table" or type(D.AuthorizedRank) ~= "function" then return nil end
	local ok, rank = pcall(D.AuthorizedRank, name, guild)
	return ok and rank == 0 and guild or nil
end

-- A member's highest office, from what this client can trust (the section's head): "K", "H",
-- "G", "C", "O" or "M". guild: the guild he is of (his own client: the game's; a receiver: the one
-- it heard him speak for, else the one his row names), read only with LOCAL_OFFICES.
function Bounty.OfficeOf(name, guild)
	name = CleanName(name)
	if not name then return "M" end
	guild = type(guild) == "string" and guild ~= "" and not Secret(guild) and guild or nil
	local function Is(fn, ...)
		if type(fn) ~= "function" then return false end
		local ok, yes = pcall(fn, ...)
		return ok and yes == true
	end
	local master = Bounty.GuildMaster(name, guild)
	if Is(ns.IsKingCharacter, name) then return "K" end
	if master and Is(ns.IsKingGuild, master) and type(ns.KingCharacter) == "function" and ns.KingCharacter() == nil then return "K" end
	if Is(ns.IsHighCouncillor, name) then return "H" end
	if master then return "G" end
	local N, K, W, role = ns.Nominees, ns.King, ns.Workshop, nil
	if Bounty.LOCAL_OFFICES and guild and type(N) == "table" and not N.missing and type(N.RoleOf) == "function" then
		local ok, r = pcall(N.RoleOf, name, guild)
		role = ok and r or nil
	end
	if role == "centurion" then return "C" end
	if Is(ns.IsSteward, name) or Is(ns.IsTreasurerCharacter, name) or Is(ns.IsSignedArbiter, name)
		or type(W) == "table" and not W.missing and Is(W.IsAuthorName, name) then return "O" end
	if role == "correspondent" or Bounty.LOCAL_OFFICES and type(K) == "table" and not K.missing and Is(K.IsHandName, name) then return "O" end
	return "M"
end

-- A member's level as this client sees it: a unit of his (his GUID's token, the target, the focus,
-- the mouse's, his party or raid), else this client's own guild's fresh roster; nil for none. And
-- where it comes from: "unit" (the game's level now) or "roster" (as old as the roster is).
function Bounty.MemberLevel(name, guid)
	local ident = Identity(name, guid)
	if not ident then return nil end
	local units = { "target", "focus", "mouseover" }
	for i = 1, 4 do units[#units + 1] = "party" .. i end
	for i = 1, 40 do units[#units + 1] = "raid" .. i end
	if ident.guid and type(UnitTokenFromGUID) == "function" then
		local ok, token = pcall(UnitTokenFromGUID, ident.guid)
		if ok and type(token) == "string" and not Secret(token) then table.insert(units, 1, token) end
	end
	for _, unit in ipairs(units) do
		if UnitMatches(unit, ident) then
			local level = Share.UnitLevel(unit)
			if level and level >= 1 then return level, "unit" end
		end
	end
	local R = ns.Roster
	local ok, fresh = false, nil
	if type(R) == "table" and type(R.Fresh) == "function" then ok, fresh = pcall(R.Fresh) end
	if ok and type(fresh) == "table" and type(fresh.members) == "table" and ident.name then
		local want = ns.Fold(ns.FullName(ident.name))
		for _, m in ipairs(fresh.members) do
			if type(m) == "table" and type(m.full) == "string" and ns.Fold(m.full) == want then
				local level = Whole(m.level, 1, 255)
				return level, level and "roster" or nil
			end
		end
	end
	return nil
end

-- What this client's own row is worth, frozen now (its own death, its own killing blow): its
-- player's office and level, and the Horde player's level as it sees him.
function Bounty.Capture(hordeGuid)
	local hl, hf = Bounty.Seen(Share.SeenLevel(hordeGuid))
	return { office = Bounty.OfficeOf(ns.me, Bounty.OwnGuild()), ml = Bounty.OwnLevel(), hl = hl, hf = hf or nil }
end

-- What a shared row is worth, as this client freezes it (Share.Take): its sender's office no
-- higher than the row says and than this client verifies (the same on every client: a relay's
-- too; with LOCAL_OFFICES, a reviewer's relay as his client froze it, on his word, as the sender's
-- membership is), his level no higher than the row says and than this client sees of him (a unit
-- of his; his guild's roster, ROSTER_SLACK behind), the Horde player's no higher than it sees of
-- him; each within the game's highest level. guild: the one the row names.
function Bounty.Intake(worth, from, guild, relay, ownGuid, hordeGuid)
	worth = Bounty.Fields(worth)
	if not worth then return nil end
	local max = Bounty.LevelMax()
	if not relay or not Bounty.LOCAL_OFFICES then
		local M, heard = ns.Moderation, nil
		if type(M) == "table" and not M.missing and type(M.GuildOf) == "function" then
			local ok, g = pcall(M.GuildOf, from)
			heard = ok and type(g) == "string" and g or nil
		end
		worth.office = Bounty.Lower(worth.office, Bounty.OfficeOf(from, heard or Sight.GuildName(guild)))
	end
	local level, source = Bounty.MemberLevel(from, ownGuid)
	if level and source == "roster" then level = level + Bounty.ROSTER_SLACK end
	worth.ml = math.min(worth.ml, level or worth.ml, max)
	local seen = Share.SeenLevel(hordeGuid)
	worth.hl = math.min(worth.hl, type(seen) == "number" and seen >= 1 and seen or worth.hl, max)
	if worth.hl == 0 then worth.hf = nil end
	return worth
end

-- A death recap's killing blow, as the game's Death Recap shows it (Blizzard_DeathRecap.lua: the
-- rows newest first, the first with overkill 0 or more is the one that killed): { row, stamp (its
-- time, the server's seconds), at (whole), guid, name, key (what marks it read) }, or nil and why
-- ("secret", "fatal": none, "stale": no time) and the name it gives.
function Bounty.KillingBlow(events)
	for i = 1, #events do
		local row = events[i]
		if type(row) == "table" then
			if Secret(row.sourceGUID, row.sourceName, row.sourceFlags, row.event, row.overkill, row.timestamp) then return nil, "secret" end
			if Whole(row.overkill, 0, 2147483647) then
				local ok, stamp = pcall(tonumber, row.timestamp)
				local name = Clean(row.sourceName, 72)
				if not ok or type(stamp) ~= "number" or stamp ~= stamp or stamp < 0 or stamp > 4294967295 then return nil, "stale", name end
				local guid = Guid(row.sourceGUID) or Clean(row.sourceGUID, 64) or "?"
				return { row = row, stamp = stamp, at = math.floor(stamp), guid = row.sourceGUID, name = name,
					key = guid .. "@" .. math.floor(stamp) }
			end
		end
	end
	return nil, "fatal"
end

-- A killing blow's killer, when it is a hostile player's damage (flags 0x440, where the row has
-- flags) and a Horde player this client proves (Share.HordeOf): his identity, or nil and why.
function Bounty.Hostile(kb)
	local row = kb.row
	if type(row.event) ~= "string" or not row.event:match("_DAMAGE$") then return nil, "event" end
	local flags = row.sourceFlags
	if flags ~= nil and not (Whole(flags, 0, 2147483647) and bit.band(flags, 0x440) == 0x440) then return nil, "flags" end
	return Share.HordeOf(row.sourceGUID, row.sourceName)
end

-- A recap marked read (s.recapsRead, RECAP_READ_MAX: the oldest go): it never counts again.
function Bounty.MarkRead(kb, s)
	s = s or Store(true)
	if not s or type(kb) ~= "table" or type(kb.key) ~= "string" then return end
	s.recapsRead[kb.key] = kb.at
	Bounty.TrimRead(s)
end
function Bounty.TrimRead(s)
	local keys = {}
	for key in pairs(s.recapsRead) do keys[#keys + 1] = key end
	if #keys <= Bounty.RECAP_READ_MAX then return end
	table.sort(keys, function(a, b)
		local x, y = tonumber(s.recapsRead[a]) or 0, tonumber(s.recapsRead[b]) or 0
		if x ~= y then return x < y end
		return a < b
	end)
	for i = 1, #keys - Bounty.RECAP_READ_MAX do s.recapsRead[keys[i]] = nil end
end

-- This client's own times in an instance (s.inside: { from, to }, the newest INSIDE_MAX): noted at
-- each login and change of zone, for a member; and since when they are whole (s.insideSince: when
-- this client first noted them, or the end of the newest one let go since). Before it this client
-- does not know where its player was (Bounty.Tracked).
function Bounty.Spans()
	if not ns.IsMember or ns.IsMember() ~= true or ns.faction == "Horde" then return end
	local s = Store(true)
	if not s then return end
	local now, inside = math.floor(Clock()), InInstance()
	s.insideSince = Whole(s.insideSince, 0, 4294967295) or now
	local last = s.inside[#s.inside]
	local open = type(last) == "table" and last.to == nil
	if inside and not open then s.inside[#s.inside + 1] = { from = now }
	elseif not inside and open then last.to = now end
	Bounty.TrimSpans(s, now)
end
function Bounty.TrimSpans(s, now)
	while #s.inside > Bounty.INSIDE_MAX do
		local gone = table.remove(s.inside, 1)
		local to = type(gone) == "table" and Whole(gone.to, 0, 4294967295) or now
		s.insideSince = math.max(Whole(s.insideSince, 0, 4294967295) or 0, to)
	end
end

-- Whether a time falls in one of them (DEATH_WINDOW around it).
function Bounty.Inside(s, at)
	for _, span in ipairs(s.inside) do
		local from = type(span) == "table" and tonumber(span.from) or nil
		local to = type(span) == "table" and tonumber(span.to) or math.huge
		if from and at >= from - Wanted.DEATH_WINDOW and at <= to + Wanted.DEATH_WINDOW then return true end
	end
	return false
end

-- Whether this client knows where its player was at a time: from when it began noting its
-- instances (s.insideSince). Before that (the first login with 1.2.3: its first /reload after the
-- update, with a battleground earlier in that game session) an earlier death has no proof that it
-- was outside one, and Daniel's "only outside instances" refuses it ("untracked"); true here (his
-- choice to confirm) takes it all the same.
Bounty.EARLIER_UNTRACKED = false
function Bounty.Tracked(s, at)
	if Bounty.EARLIER_UNTRACKED == true then return true end
	local since = Whole(s.insideSince, 0, 4294967295)
	return since ~= nil and at >= since
end

-- Whether a recap is this player's own death (a death counts only from the victim's own client): a
-- row that names its victim (destGUID, the combat log's shape, where the game's rows carry it)
-- names this player, and none another; with no row naming one, only a recap the game shows as his
-- (proven: the one without an ID, his own death dialog's; a death of the local player in the
-- game's damage meter). Forever's damage meter holds a recap ID for every death in the group
-- (DamageMeterDocumentation.lua: deathRecapID beside isLocalPlayer, and its window opens any of
-- them), so an ID the game answers for proves nothing by itself. true, or false and why: "victim"
-- (another character's death: a party member's), "unproven".
function Bounty.Mine(events, guid, proven)
	local named = false
	for i = 1, #events do
		local row = events[i]
		local dest = type(row) == "table" and row.destGUID or nil
		if Secret(dest) then
			if not proven then return false, "unproven" end
		elseif type(dest) == "string" and dest ~= "" then
			if Guid(dest) == nil or Guid(dest) ~= guid then return false, "victim" end
			named = true
		end
	end
	if named or proven then return true end
	return false, "unproven"
end

-- The recap IDs the game's damage meter shows as this player's own deaths (C_DamageMeter: the
-- Deaths sources with isLocalPlayer, in its overall and current sessions and each one it keeps,
-- METER_SESSIONS at most), as a set; empty where it keeps none or has no meter. (Its sessions are
-- secret in combat: the reading waits it out.)
-- (The meter's values as DamageMeterConstantsDocumentation.lua gives them: Enum.DamageMeterType
-- Deaths 9, Enum.DamageMeterSessionType Overall 0 and Current 1.)
Bounty.METER_SESSIONS = 64
Bounty.METER_DEATHS, Bounty.METER_OVERALL, Bounty.METER_CURRENT = 9, 0, 1
function Bounty.OwnRecapIDs()
	local out, D = {}, C_DamageMeter
	if type(D) ~= "table" then return out end
	local deaths = Bounty.METER_DEATHS
	local function Take(ok, session)
		local sources = ok and type(session) == "table" and session.combatSources or nil
		if type(sources) ~= "table" then return end
		for _, src in ipairs(sources) do
			if type(src) == "table" and not Secret(src.isLocalPlayer, src.deathRecapID) and src.isLocalPlayer == true then
				local id = Whole(src.deathRecapID, 1, 2147483647)
				if id then out[id] = true end
			end
		end
	end
	pcall(function()
		if type(D.GetCombatSessionFromType) == "function" then
			Take(pcall(D.GetCombatSessionFromType, Bounty.METER_OVERALL, deaths))
			Take(pcall(D.GetCombatSessionFromType, Bounty.METER_CURRENT, deaths))
		end
		if type(D.GetAvailableCombatSessions) ~= "function" or type(D.GetCombatSessionFromID) ~= "function" then return end
		local ok, list = pcall(D.GetAvailableCombatSessions)
		if not ok or type(list) ~= "table" then return end
		for i = 1, math.min(#list, Bounty.METER_SESSIONS) do
			local id = type(list[i]) == "table" and Whole(list[i].sessionID, 0, 2147483647) or nil
			if id then Take(pcall(D.GetCombatSessionFromID, id, deaths)) end
		end
	end)
	return out
end

-- One earlier death through the live death's gate: true and the row recorded, or false, why and
-- the killer's name.
function Bounty.TakeEarlier(s, kb, mine, now)
	if kb.stamp > now + 1 or now - kb.at > Wanted.SHARE_AGE then return false, "stale", kb.name end
	if not Bounty.Tracked(s, kb.at) then return false, "untracked", kb.name end
	if Bounty.Inside(s, kb.at) then return false, "instance", kb.name end
	local horde, why = Bounty.Hostile(kb)
	if not horde then return false, why, kb.name end
	-- (Its id is the live death's own, "native:" and the killing blow's time: a death counted
	-- when it happened is a "replay" here.)
	local ok, e = RecordKill("SELF_DEATH", "native:" .. tostring(kb.stamp), horde, mine,
		{ precision = "approximate", horde = "killer", own = true, earlier = true, at = kb.at, bounty = Bounty.Capture(horde.guid) })
	if ok then Share.Send(e) end
	return ok, e, horde.name
end

-- Whether this player is in combat now (the game's own lockdown; not known: as if he were).
function Bounty.InCombat()
	if type(InCombatLockdown) ~= "function" then return false end
	local ok, yes = pcall(InCombatLockdown)
	return not ok or yes == true
end

-- A reading again, wait seconds from now (one waiting at a time): after a reading that left
-- recaps unread (EARLIER_AGAIN), or one that waited out combat (NOTICE_TICK).
Bounty.EARLIER_AGAIN = 2 * Wanted.SHARE_RATE_WINDOW -- (past the window of every receiver's limit for one member)
Bounty.EARLIER_PASSES = 4 -- readings a session at most, EARLIER_MAX added each
function Bounty.EarlierLater(wait)
	local session = Bounty.session
	if session.again or not ns.After then return false end
	session.again = true
	local gen = session.gen
	ns.After(wait, "wanted earlier deaths", function()
		if gen ~= Bounty.session.gen then return end
		Bounty.session.again = false
		Bounty.Earlier()
	end)
	return true
end

-- This session's reading over: a notice waiting shows now, once (Bounty.NoticeSoon).
function Bounty.EarlierDone()
	Bounty.session.read = true
	local s = Store(false)
	if s and type(s.earlierNotice) == "table" then Bounty.NoticeSoon() end
end

-- The earlier deaths, read (a login's reading, outside an instance and out of combat): returns how
-- many were added, or 0 and why none was read. The recaps of this player's own deaths
-- (Bounty.Mine): the latest (no ID), the IDs the damage meter gives for his deaths, and the IDs
-- from 1 up the game answers for whose rows name him. EARLIER_MAX added a reading, the newest, so
-- that every member's client takes them within its limit for one member; while recaps are left
-- unread, another reading EARLIER_AGAIN later (EARLIER_PASSES a session: a logout empties them).
-- The ones added wait for one notice (s.earlierNotice) until this session's reading is over.
function Bounty.Earlier()
	local session = Bounty.session
	if session.read then return 0, "read" end
	local function Over(why) Bounty.EarlierDone() return 0, why end
	if not ns.IsMember or ns.IsMember() ~= true or not ns.me then return Over("member") end
	if ns.faction == "Horde" then return Over("faction") end
	if InInstance() then return 0, "instance" end
	if Bounty.InCombat() then Bounty.EarlierLater(Bounty.NOTICE_TICK) return 0, "combat" end
	local recap = C_DeathRecap
	if type(recap) ~= "table" or type(recap.HasRecapEvents) ~= "function" or type(recap.GetRecapEvents) ~= "function" then return Over("recap") end
	local mine, s = UnitIdentity("player"), Store(true)
	if not mine or not mine.guid or not s then return Over("identity") end
	session.passes = (session.passes or 0) + 1
	session.noted = session.noted or {}
	Bounty.Spans()
	local found, order = {}, {}
	local function Read(id, proven)
		local okH, has = pcall(recap.HasRecapEvents, id)
		if not okH or Secret(has) or has ~= true then return false end
		local okR, events = pcall(recap.GetRecapEvents, id)
		local kb = okR and type(events) == "table" and Bounty.KillingBlow(events) or nil
		if kb and not found[kb.key] then
			local own, why = Bounty.Mine(events, mine.guid, proven)
			if own then
				found[kb.key] = true
				order[#order + 1] = kb
			elseif Guid(kb.guid) and not session.noted[kb.key] and not s.recapsRead[kb.key] then
				-- (Another's death, or one the game does not show as ours: never ours to count, so not
				-- marked read either; /oly wanted status says so once a session.)
				session.noted[kb.key] = true
				Share.Note("earlier", false, why, kb.name)
			end
		end
		return true
	end
	Read(nil, true)
	local own, ids = Bounty.OwnRecapIDs(), {}
	for id in pairs(own) do ids[#ids + 1] = id end
	table.sort(ids)
	for _, id in ipairs(ids) do Read(id, true) end
	local answered, misses = false, 0
	for id = 1, Bounty.RECAP_IDS do
		if own[id] or Read(id, false) then answered, misses = true, 0
		elseif answered then
			misses = misses + 1
			if misses >= Bounty.RECAP_MISSES then break end
		end
	end
	-- (The newest first, EARLIER_MAX added at most; each goes in the order of the deaths: RecordKill.)
	table.sort(order, function(a, b)
		if a.stamp ~= b.stamp then return a.stamp > b.stamp end
		return a.key < b.key
	end)
	local now, added, more = math.floor(Clock()), {}, false
	for _, kb in ipairs(order) do
		if not s.recapsRead[kb.key] then
			if #added >= Bounty.EARLIER_MAX then more = true break end
			local ok, e, who = Bounty.TakeEarlier(s, kb, mine, now)
			Bounty.MarkRead(kb, s)
			if ok then added[#added + 1] = e end
			-- (/oly wanted status: a player's killing blow, not a creature's.)
			if ok or Guid(kb.guid) then Share.Note("earlier", ok, e, who or kb.name) end
		end
	end
	session.added = (session.added or 0) + #added
	if #added > 0 then
		-- (What each added, read after them all: one may have changed another's, REPEAT_GAP. One
		-- notice for the session's readings, the oldest death first.)
		local n = type(s.earlierNotice) == "table" and type(s.earlierNotice.rows) == "table" and s.earlierNotice or { rows = {} }
		for _, e in ipairs(added) do
			local t = s.targets[e.targetKey]
			n.rows[#n.rows + 1] = { id = e.id, name = t and t.name or e.killerName, hl = e.hl, hf = e.hf, at = e.at, points = e.points }
		end
		table.sort(n.rows, function(a, b)
			local x, y = tonumber(a.at) or 0, tonumber(b.at) or 0
			if x ~= y then return x < y end
			return tostring(a.id) < tostring(b.id)
		end)
		while #n.rows > Wanted.MAX_VICTIMS do table.remove(n.rows, 1) end
		s.earlierNotice = n
	end
	if more and session.passes < Bounty.EARLIER_PASSES and Bounty.EarlierLater(Bounty.EARLIER_AGAIN) then return #added end
	Bounty.EarlierDone()
	return #added
end

-- Why the notice waits now, or nil: this session's reading of the earlier deaths not over (it
-- would add to it: one notice), combat, an instance, a death, the privacy page (shown, or waiting
-- to ask this session: Consent.Waiting, as the version letter waits for it).
-- (1.2.4: Bounty.Blocked's, the notices' too, and the update letter open: a window over another.)
function Bounty.Busy()
	if not Bounty.session.read then return "reading" end
	return Bounty.Blocked()
end
function Bounty.Blocked()
	if Bounty.InCombat() then return "combat" end
	if InInstance() then return "instance" end
	local okD, dead = pcall(function() return UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") end)
	if not okD or dead == true then return "dead" end
	local C, LT = ns.Consent, ns.Letters
	if type(C) == "table" and not C.missing then
		local ok, shown = pcall(function()
			local f = type(C.Frame) == "function" and C.Frame() or nil
			return f and f.IsShown and f:IsShown() or type(C.Waiting) == "function" and C.Waiting() == true
		end)
		if not ok or shown then return "privacy" end
	end
	if type(LT) == "table" and not LT.missing and type(LT.Frame) == "function" then
		local ok, shown = pcall(function()
			local f = LT.Frame()
			return f and f.IsShown and f:IsShown() or false
		end)
		if not ok or shown then return "letter" end
	end
	if scoreMigrationFrame then
		local ok, shown = pcall(function() return scoreMigrationFrame:IsShown() end)
		if not ok or shown then return "score-letter" end
	end
	return nil
end

-- The notice's text: each death added a line (its row's points now, while the row is held: none
-- once a reviewer voided it), or nil for none.
function Bounty.NoticeText(s)
	local n = s and s.earlierNotice
	if type(n) ~= "table" or type(n.rows) ~= "table" then return nil end
	local live = {}
	for _, e in ipairs(s.evidence) do if type(e) == "table" and e.id then live[e.id] = e end end
	local dateFn = date or (os and os.date)
	local lines, count = { L.WANTED_EARLIER_INTRO, "" }, 0
	for _, r in ipairs(n.rows) do
		local e = type(r) == "table" and live[r.id] or nil
		if type(r) == "table" and not (e and e.void) then
			local hl = Bounty.Level(r.hl)
			local level = hl > 0 and (r.hf and L.WANTED_LEVEL_FLOOR:format(hl) or tostring(hl)) or L.WANTED_LEVEL_UNKNOWN
			local at = Whole(r.at, 0, 4294967295) or 0
			local when = type(dateFn) == "function" and dateFn("%H:%M", at) or tostring(at)
			lines[#lines + 1] = L.WANTED_EARLIER_ROW:format(Display({ name = CleanName(r.name) }), level, when,
				Whole(e and e.points or r.points, 0, Wanted.MAX_POINTS) or 0)
			count = count + 1
		end
	end
	if count == 0 then return nil end
	lines[#lines + 1] = ""
	lines[#lines + 1] = L.WANTED_EARLIER_END
	return table.concat(lines, "\n")
end

-- The notice shown, when nothing makes it wait, in the Olympus copy window (opened by itself: it
-- takes no keyboard, UI.ShowCopy's auto), and gone from the saved data: once. true, or false and
-- why ("none", "ui", or what it waits for: Bounty.Busy).
function Bounty.ShowNotice()
	local s = Store(false)
	if not s or type(s.earlierNotice) ~= "table" then return false, "none" end
	local busy = Bounty.Busy()
	if busy then return false, busy end
	local UI = ns.UI
	if type(UI) ~= "table" or type(UI.ShowCopy) ~= "function" then return false, "ui" end
	local text = Bounty.NoticeText(s)
	s.earlierNotice = nil
	if not text then return false, "none" end
	UI.ShowCopy(L.WANTED_EARLIER_TITLE, text, nil, { key = "wanted-earlier", auto = true })
	Bounty.session.told = (Bounty.session.told or 0) + 1
	return true
end

-- The notice now, else again every NOTICE_TICK while it waits for something (one beat a session).
function Bounty.NoticeSoon()
	local shown, why = Bounty.ShowNotice()
	if shown or why == "none" or why == "ui" or Bounty.session.ticking or not ns.After then return shown end
	Bounty.session.ticking = true
	local gen = Bounty.session.gen
	local function Tick()
		if gen ~= Bounty.session.gen then return end
		local ok, wait = Bounty.ShowNotice()
		if ok or wait == "none" or wait == "ui" then Bounty.session.ticking = false return end
		ns.After(Bounty.NOTICE_TICK, "wanted earlier notice", Tick)
	end
	ns.After(Bounty.NOTICE_TICK, "wanted earlier notice", Tick)
	return false
end

-- At login (and each /reload): this client's instance time noted; the earlier deaths read
-- EARLIER_WAIT later (outside an instance: else when it next leaves one, Bounty.Zone; out of
-- combat); a notice saved before the reload shown once this session's reading is over.
function Bounty.Login()
	local session = Bounty.session
	session.gen = (session.gen or 0) + 1
	session.read, session.due, session.ticking, session.again, session.passes = false, false, false, false, 0
	session.noticeTick, session.loginAt = false, math.floor(Clock())
	session.askSettle, session.held, session.heldTick = nil, nil, false
	Bounty.Spans()
	local gen = session.gen
	if not ns.After then Bounty.EarlierDone() return end
	-- (1.2.4: the notices that waited, a reload or a logout before they could show, NOTICE_LOGIN
	-- later: after the privacy page's ask and the update letter's; none shows before, a notice heard
	-- meanwhile neither, Bounty.Notices. None waiting, no timer.)
	if Bounty.Waiting() then
		ns.After(Bounty.NOTICE_LOGIN, "wanted notices", function()
			if gen == Bounty.session.gen then Bounty.NoticesSoon() end
		end)
	end
	-- (1.2.4 repair: while this character keeps deaths open, the avenged ask, W7: Bounty.Ask. None
	-- open, no timer.)
	if #Bounty.Open(Store(false), NameKey(ns.me)) > 0 then Bounty.AskLater(gen, 1) end
	ns.After(Bounty.EARLIER_WAIT, "wanted earlier deaths", function()
		if gen ~= Bounty.session.gen then return end
		Bounty.session.due = true
		Bounty.Earlier()
	end)
end

-- A change of zone (into an instance, or out): noted; out of one, the earlier deaths when they
-- were due (unless another reading waits its time), and a notice that waited.
function Bounty.Zone()
	Bounty.Spans()
	if InInstance() then return end
	local session = Bounty.session
	if session.due and not session.read and not session.again then Bounty.Earlier() end
	local s = Store(false)
	if s and type(s.earlierNotice) == "table" then Bounty.NoticeSoon() end
	-- (1.2.4: and the notices that waited for the outside.)
	if Bounty.Waiting() then Bounty.NoticesSoon() end
end

---------------------------------------------------------------------------
-- The notices (1.2.4). Daniel: "quando ela morrer por um player da Horda, toda vez devia aparecer
-- uma mensagem para ela"; "quando os players que morreram para aquele jogador forem mortos,
-- deveria aparecer uma mensagem avisando que o cara que matou eles foi morto, que eles foram
-- vingados e explicando quem matou ele"; and the Slayer letter, in the King's letter's model.
--
-- The death. At each own death to a Horde player that counts (ReadSelfDeathRecap: the recap's
-- gate, outside an instance; the retries' second success is a replay, so once a death), a toast:
-- Olympus's own window at the bottom of the screen (the game's release popup is at its top), his
-- name and the points this death added to his bounty ("again", no points, inside the
-- corpse-camping gap), TOAST_SECONDS, then gone. No button, no mouse, no keyboard, off the escape
-- list (the game's sweep at a death leaves it), at the death itself, in both input modes.
--
-- Avenged. Each own death to a Horde player (live or earlier) is kept apart, open, by his GUID
-- (s.mine: a fold empties the rows, Checkpoint), each by the character who died (one account's
-- characters share the store), GRUDGE_DAYS at most. A claim on him recorded here (a member's own
-- kill heard on the channel, a reviewer's relay, the catch-up answer at the next login, this
-- client's own kill: RecordKill) avenges every such death before it, once: one notice for each
-- character (s.avenged, AVENGED_MAX waiting, the oldest drop), saved until it shows; a later claim
-- finds nothing open. The character who is himself the avenger has them closed with no notice (his
-- letter says it). The notice is Olympus's own dialog (Dialog.Show, in both input modes, never the
-- game's popups): who slew him and his guild, the Horde player, how many times he had killed this
-- one; Thank (Olympus's whisper window with the thanks written in it: nothing goes until the
-- player's own Send or Enter), Whisper (that window, empty), See (the avenger's Olympus profile;
-- the dialog stays) and Close. It carries no point (the points are the rows') and names the member
-- whose own kill it was. It waits out combat, an instance, a death, the privacy page, the update
-- letter and the King's letter, one at a time; with the gamepad UI nothing of Olympus opens by
-- itself, so it waits for the Olympus window, and chat says so once.
-- (1.2.4 repair: the rows come in any order. A death heard after the claim that avenged it, its
-- recap read at a retry or by the earlier deaths' reader, is avenged at once by that claim's
-- slayer, Bounty.Grieve, and its toast says so; a member offline at the kill asks for it at his
-- next login, W7, "The avenged ask" below.)
--
-- The Slayer letter. At this client's own killing blow that paid points (Share.PartyKill), the
-- King's letter (HonorsNet: its window, the profile Edit's list to read it again, never to the King
-- himself), its words Wanted's (Wanted.LetterText) and made of its key alone (Bounty.LetterKey), so
-- they read the same after any reload, in the reader's language: whom he slew, how many of ours
-- that one had slain in the bounty paid, the bounty, his level's points, the revenge and the total,
-- as this client counts them LETTER_SETTLE after the kill (every member's own rows reach every
-- client, a moment after: the whole bounty, no review; its key made then, once: Bounty.SettledKey).
-- Never in combat, an instance, a death, over the privacy page or the update letter: it waits,
-- saved (s.slayerLetters), and goes to HonorsNet when nothing is in the way, one at a time, and with
-- the gamepad UI only while the Olympus window is open (chat says once that one waits:
-- HonorsNet.WaitForWindow), so it shows as it goes, once (this queue's: HonorsNet keeps no mark of
-- it). Its first button is Slayers (the Wanted tab), its portrait his rank's frame. The King: a
-- toast instead.
---------------------------------------------------------------------------

Bounty.TOAST_SECONDS = 10  -- a toast shows this long
Bounty.TOAST_W = 360       -- its width (its height follows its words)
Bounty.TOAST_Y = 150       -- above the screen's bottom: clear of the game's popups at its top
Bounty.MINE_MAX = 32       -- Horde players this store keeps its own open deaths to...
Bounty.MINE_DEATHS = 8     -- ...and this many of them each, the newest
Bounty.AVENGED_MAX = 5     -- avenged notices waiting at most (the oldest drop)
Bounty.LETTERS_MAX = 20    -- Slayer letters waiting at most (HonorsNet keeps 20 to read again)
Bounty.NOTICE_LOGIN = 90   -- what waited is tried this long after login (the privacy page asks at 45, the update letter at 60)
Bounty.WINDOW_TICK = 2     -- a notice waiting for a window (the Olympus window, a dialog, the King's letter) looks this often

-- The toast: Olympus's own window (ns.Window: the Olympus window's bronze metal, "Wanted" in its
-- title bar), the words in ink on a parchment, at the bottom centre; the newest takes the place of
-- the one shown. Where no window can be made (ns.Window missing), one chat line.
function Bounty.Toast(text)
	if type(text) ~= "string" or text == "" then return nil end
	local f = Bounty.toast
	if not f then
		if type(ns.Window) ~= "function" then ns.Print(text) return nil end
		f = ns.Window("OlympusWantedToast", UIParent, { title = L.TAB_WANTED, inset = false, close = false, escape = false })
		f:SetFrameStrata("DIALOG")
		f:SetClampedToScreen(true)
		f:EnableMouse(false)
		f:SetWidth(Bounty.TOAST_W)
		local inner = type(f.inner) == "table" and f.inner or { 9, -24, -6, 4 }
		f.bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
		f.bg:SetPoint("TOPLEFT", inner[1], inner[2])
		f.bg:SetPoint("BOTTOMRIGHT", inner[3], inner[4])
		local UI = ns.UI
		local file = type(UI) == "table" and type(UI.FirstTexture) == "function" and type(UI.PARCHMENTS) == "table"
			and UI.FirstTexture(UI.PARCHMENTS) or "Interface\\QuestFrame\\QuestBG"
		if type(GetFileIDFromPath) == "function" and not GetFileIDFromPath(file) then
			f.bg:SetColorTexture(0.87, 0.80, 0.64, 0.97)
		else
			f.bg:SetTexture(file)
			if file:find("QuestBG", 1, true) then f.bg:SetTexCoord(0, 296 / 512, 0, 331 / 512) end
		end
		f.text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		f.text:SetPoint("TOPLEFT", inner[1] + 12, inner[2] - 10)
		f.text:SetWidth(Bounty.TOAST_W - inner[1] + inner[3] - 24)
		f.text:SetJustifyH("LEFT")
		f.text:SetTextColor(0.18, 0.10, 0.02)
		if f.text.SetWordWrap then f.text:SetWordWrap(true) end
		f.inside = inner
		f:Hide()
		Bounty.toast = f
	end
	f.text:SetText(text)
	-- (As tall as its words: the client's measure, else about 50 letters a line.)
	local h = f.text.GetStringHeight and f.text:GetStringHeight()
	if type(h) ~= "number" or h <= 0 then h = 14 * math.max(1, math.ceil(#text / 50)) end
	f:SetHeight(math.ceil(h) - f.inside[2] + 10 + f.inside[4] + 14)
	f:ClearAllPoints()
	f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, Bounty.TOAST_Y)
	f:Show()
	Bounty.toastGen = (Bounty.toastGen or 0) + 1
	local gen = Bounty.toastGen
	if ns.After then
		ns.After(Bounty.TOAST_SECONDS, "wanted toast", function() if Bounty.toastGen == gen then f:Hide() end end)
	end
	return f
end
-- A toast, else (its window failed) its chat line: a notice is never lost to the interface, nor
-- breaks the row that brought it.
function Bounty.Say(text)
	local ok, f = pcall(Bounty.Toast, text)
	if ok then return f end
	if ns.CaptureError then ns.CaptureError("wanted toast", f) end
	ns.Print(text)
	return nil
end

-- The death's toast: its row's Horde player and what the death added to his bounty; none added,
-- "again" inside the corpse-camping gap (an earlier death of his kept it), else his name alone (a
-- bounty at BOUNTY_MAX). Returns the window and its words.
-- (1.2.4 repair: a death whose killer this client already holds slain after it, a member's kill
-- row heard before this death's own was read (the recap ready only at a retry), is avenged
-- already: the toast says so, never "we will avenge you", and the avenged notice tells by whom,
-- Bounty.Grieve.)
function Bounty.DeathToast(e)
	if type(e) ~= "table" or e.action ~= "bounty" or not e.own or e.earlier then return nil end
	local s = Store(false)
	local t = s and s.targets[e.targetKey] or nil
	local name = Display({ name = CleanName(type(t) == "table" and t.name or e.killerName) })
	local points = Whole(e.points, 0, Wanted.MAX_POINTS) or 0
	local text
	if Bounty.AvengedBy(t, Whole(e.at, 0, 4294967295)) then
		text = L.WANTED_DEATH_TOAST_SLAIN:format(name)
	elseif points > 0 then
		text = L.WANTED_DEATH_TOAST:format(name, points)
	else
		local st = type(t) == "table" and type(t.bounty) == "table" and t.bounty or {}
		local last = type(st.gap) == "table" and tonumber(st.gap[Bounty.Who(e.victimName)]) or nil
		text = (last and last < (tonumber(e.at) or 0)) and L.WANTED_DEATH_TOAST_AGAIN:format(name) or L.WANTED_DEATH_TOAST_PLAIN:format(name)
	end
	Bounty.session.toasts = (Bounty.session.toasts or 0) + 1
	return Bounty.Say(text), text
end

-- A row recorded (RecordKill), for the notices: an own death kept, a claim's avenged notices, an
-- own kill's letter.
function Bounty.Recorded(s, e)
	if e.action == "bounty" then
		if e.own then Bounty.Grieve(s, e) end
	elseif e.action == "claim" then
		Bounty.Avenge(s, e)
		if e.own then Bounty.Slain(s, e) end
	end
end

-- s.mine kept to its bounds: GRUDGE_DAYS, MINE_DEATHS a Horde player (the newest), MINE_MAX Horde
-- players (those with the newest deaths).
function Bounty.TrimMine(s, now)
	local since, keys = (now or math.floor(Clock())) - Bounty.SCORE.GRUDGE_DAYS * 86400, {}
	for guid, m in pairs(s.mine) do
		local kept = {}
		for _, d in ipairs(type(m) == "table" and type(m.deaths) == "table" and m.deaths or {}) do
			if type(d) == "table" and (tonumber(d.at) or 0) >= since then kept[#kept + 1] = d end
		end
		table.sort(kept, function(a, b) return a.at < b.at end)
		while #kept > Bounty.MINE_DEATHS do table.remove(kept, 1) end
		if #kept == 0 then s.mine[guid] = nil else m.deaths = kept keys[#keys + 1] = guid end
	end
	if #keys <= Bounty.MINE_MAX then return end
	local function Last(guid) local d = s.mine[guid].deaths return d[#d].at end
	table.sort(keys, function(a, b)
		if Last(a) ~= Last(b) then return Last(a) < Last(b) end
		return a < b
	end)
	for i = 1, #keys - Bounty.MINE_MAX do s.mine[keys[i]] = nil end
end

-- The claim on an entry that avenged a death at `at`: the first held at or after it (a death
-- before a kill in the same second, Share.Before), within GRUDGE_DAYS, or nil. (1.2.4 repair: the
-- rows come in any order, the claim's before the death's own; the claims are the rebuilt ones.)
function Bounty.AvengedBy(t, at)
	if type(t) ~= "table" or type(t.claims) ~= "table" or not at then return nil end
	local first, span = nil, Bounty.SCORE.GRUDGE_DAYS * 86400
	for _, c in ipairs(t.claims) do
		local when = type(c) == "table" and Whole(c.at, 0, 4294967295) or nil
		if when and when >= at and when - at <= span and (not first or when < first.at) then first = c end
	end
	return first
end

-- The ledger's row of a claim (its id), or nil once folded (Checkpoint).
function Bounty.RowOf(s, id)
	for i = #s.evidence, 1, -1 do
		local e = s.evidence[i]
		if type(e) == "table" and e.id == id then return e end
	end
	return nil
end

-- The avenger's guild for the notice's words: the one his own messages named last (Moderation),
-- else the one his row named, else this client's own for its own kill.
function Bounty.AvengerGuild(name, given, own)
	local M, guild = ns.Moderation, nil
	if type(M) == "table" and not M.missing and type(M.GuildOf) == "function" then
		local ok, g = pcall(M.GuildOf, name)
		guild = ok and Sight.GuildName(g) or nil
	end
	return guild or Sight.GuildName(given) or (own and Sight.OwnGuild()) or nil
end

-- One avenged notice queued for a character (r: id, the claim's; who, the character; name, guild,
-- horde, times, at), once a claim each character: another death of his that claim avenged, heard
-- while its notice waits, adds to its times; once it went (s.avengedTold), nothing again. true
-- when one was queued or grew.
Bounty.TOLD_MAX = 64 -- claims told of kept (the newest), GRUDGE_DAYS at most
function Bounty.Tell(s, r)
	local told = tostring(r.id) .. "|" .. tostring(r.who)
	for _, w in ipairs(s.avenged) do
		if type(w) == "table" and w.id == r.id and w.who == r.who then
			w.times = math.min(Bounty.MINE_DEATHS, (tonumber(w.times) or 1) + (tonumber(r.times) or 1))
			return true
		end
	end
	if s.avengedTold[told] then return false end
	s.avenged[#s.avenged + 1] = r
	while #s.avenged > Bounty.AVENGED_MAX do table.remove(s.avenged, 1) end
	s.avengedTold[told] = Whole(r.at, 0, 4294967295) or math.floor(Clock())
	Bounty.TrimTold(s)
	return true
end
function Bounty.TrimTold(s, now)
	local since, keys = (now or math.floor(Clock())) - Bounty.SCORE.GRUDGE_DAYS * 86400, {}
	for key, at in pairs(s.avengedTold) do
		if type(key) ~= "string" or #key > 300 or not Whole(at, 0, 4294967295) or at < since then s.avengedTold[key] = nil
		else keys[#keys + 1] = key end
	end
	if #keys <= Bounty.TOLD_MAX then return end
	table.sort(keys, function(a, b)
		if s.avengedTold[a] ~= s.avengedTold[b] then return s.avengedTold[a] < s.avengedTold[b] end
		return a < b
	end)
	for i = 1, #keys - Bounty.TOLD_MAX do s.avengedTold[keys[i]] = nil end
end

-- An own death kept, open, for the avenged notice (its character's key: this player's name as
-- ns.me holds it, the one the notices are shown for).
-- (1.2.4 repair: then avenged at once by a claim on him held already at or after it, its row heard
-- before this death's own (the recap read at a retry, or by the earlier deaths' reader at the next
-- login): Bounty.AvengeSoon. Before, the death stayed open and the next kill on him, days later,
-- was told as its avenger, the first never.)
function Bounty.Grieve(s, e)
	local guid, who, at = Guid(e.killerGuid), NameKey(ns.me), Whole(e.at, 0, 4294967295)
	if not guid or not who or not at then return end
	local t = s.targets[e.targetKey]
	local m = type(s.mine[guid]) == "table" and s.mine[guid] or { deaths = {} }
	m.name = CleanName(type(t) == "table" and t.name or e.killerName) or m.name
	m.deaths[#m.deaths + 1] = { at = at, who = who }
	s.mine[guid] = m
	Bounty.TrimMine(s)
	Bounty.AvengeSoon(s, guid, e.targetKey)
end

-- A claim on a Horde player: the deaths of his kept here that it avenged (Bounty.AvengeSoon).
function Bounty.Avenge(s, e)
	local guid = Guid(e.victimGuid)
	if not guid or type(s.mine[guid]) ~= "table" then return 0 end
	return Bounty.AvengeSoon(s, guid, e.targetKey)
end

-- Every open death to a Horde player that a claim held here avenged, closed: each by the first
-- claim at or after it (Bounty.AvengedBy), so the order the rows came in does not matter; one
-- notice for each claim and character (Bounty.Tell: another death of his it avenged adds to its
-- times), none for the avenger himself (his letter says it). targetKey: his entry. How many notices
-- were queued or grew.
-- (1.2.4 repair: while this session's avenged ask is answered (ASK_SETTLE after it went, W7), the
-- answers' claims come from several clients in any order: the deaths wait for them all, so that a
-- later kill heard first never names its slayer as the avenger of a death an earlier one avenged.)
Bounty.ASK_SETTLE = 15 -- seconds after the ask (its answers' ASK_DELAY, their part of 5 s, the channel's wait)
function Bounty.AvengeSoon(s, guid, targetKey)
	local session = Bounty.session
	local now = math.floor(Clock())
	if (tonumber(session.askSettle) or 0) > now and ns.After then
		session.held = session.held or {}
		session.held[guid] = targetKey
		if not session.heldTick then
			session.heldTick = true
			local gen = session.gen
			ns.After(math.max(1, session.askSettle - now), "wanted avenged settle", function()
				if gen ~= Bounty.session.gen then return end
				local held = Bounty.session.held or {}
				Bounty.session.held, Bounty.session.heldTick = nil, false
				local st = Store(false)
				if st then for g, key in pairs(held) do Bounty.AvengeOpen(st, g, key) end end
			end)
		end
		return 0
	end
	return Bounty.AvengeOpen(s, guid, targetKey)
end
function Bounty.AvengeOpen(s, guid, targetKey)
	local m = s.mine[guid]
	if type(m) ~= "table" or type(m.deaths) ~= "table" then return 0 end
	local t = type(targetKey) == "string" and s.targets[targetKey] or nil
	local groups, order, kept = {}, {}, {}
	for _, d in ipairs(m.deaths) do
		local c = type(d) == "table" and Bounty.AvengedBy(t, Whole(d.at, 0, 4294967295)) or nil
		if c then
			local k = tostring(c.id) .. "|" .. tostring(d.who)
			if not groups[k] then groups[k], order[#order + 1] = { claim = c, who = d.who, times = 0 }, k end
			groups[k].times = groups[k].times + 1
		else
			kept[#kept + 1] = d
		end
	end
	m.deaths = kept
	if #kept == 0 then s.mine[guid] = nil end
	table.sort(order)
	local horde, n = CleanName(m.name or (type(t) == "table" and t.name or nil)), 0
	for _, k in ipairs(order) do
		local g = groups[k]
		local c, row = g.claim, Bounty.RowOf(s, g.claim.id)
		local own = row ~= nil and row.own == true
		local by = own and NameKey(row.from) or NameKey(c.slayer)
		local name = CleanName(c.slayer)
		if by ~= g.who and name and horde and Bounty.Tell(s, { id = c.id, who = g.who, name = name,
			guild = Bounty.AvengerGuild(c.slayer, row and row.guild, own), horde = horde, times = g.times,
			at = Whole(c.at, 0, 4294967295) or 0 }) then n = n + 1 end
	end
	if n > 0 then Bounty.NoticesSoon() end
	return n
end

-- The Slayer letter's key, its place in HonorsNet's list and its words' every part (Wanted.LetterText):
-- wanted@<digest>~<points>~<level's points>~<bounty>~<revenge>~<kills>~<level>[+]~<name>, as this
-- client counts the claim (its row's digest: one letter a kill; 1.2.4 repair: made as the letter
-- goes, Bounty.SettledKey, and kept at the kill for a claim gone by then). The level shown is the one the
-- kill paid for, else the one seen (a kill inside KILL_GAP pays none); "+" a floor (a "??").
function Bounty.LetterKey(e, claim, name)
	name = CleanName(name)
	local digest = type(e.digest) == "string" and #e.digest == 16 and e.digest:match("^%x+$") or nil
	local points = Whole(e.points, 0, Wanted.MAX_POINTS)
	if not name or not digest or not points or type(claim) ~= "table" then return nil end
	local S, paid = Bounty.SCORE, Bounty.Level(e.level)
	local level = paid > 0 and paid or Bounty.Level(e.hl)
	local floor = level > 0 and e.hf == true and level == Bounty.Level(e.hl)
	-- (1.2.4, the author's report "3 kills, 18 points": the kills it names count as the bounty does,
	-- a death inside the corpse-camping gap none: v.again, ApplyEvidence.)
	local kills = Whole(claim.killOverflow, 0, Wanted.MAX_POINTS) or Whole(claim.overflow, 0, Wanted.MAX_POINTS) or 0
	for _, v in ipairs(type(claim.victims) == "table" and claim.victims or {}) do
		if type(v) == "table" and not v.again then kills = kills + 1 end
	end
	kills = math.min(Wanted.MAX_POINTS, kills)
	return ("wanted@%s~%d~%d~%d~%d~%d~%d%s~%s"):format(digest, points, Bounty.BasePoints(paid),
		Whole(claim.bounty, 0, Wanted.MAX_POINTS) or 0, e.revenge and S.REVENGE or 0, kills, level, floor and "+" or "", name)
end
-- Its parts, or nil.
function Bounty.LetterOf(key)
	if type(key) ~= "string" or #key > 200 then return nil end
	local digest, points, base, bounty, revenge, kills, level, floor, name =
		key:match("^wanted@(%x+)~(%d+)~(%d+)~(%d+)~(%d+)~(%d+)~(%d+)(%+?)~([^~]+)$")
	if not digest or #digest ~= 16 then return nil end
	local M = Wanted.MAX_POINTS
	local r = { digest = digest, points = Whole(tonumber(points), 0, M), base = Whole(tonumber(base), 0, M), bounty = Whole(tonumber(bounty), 0, M),
		revenge = Whole(tonumber(revenge), 0, M), kills = Whole(tonumber(kills), 0, M), level = Whole(tonumber(level), 0, 255),
		floor = floor == "+" or nil, name = CleanName(name) }
	if not (r.points and r.base and r.bounty and r.revenge and r.kills and r.level and r.name) then return nil end
	return r
end

-- The letter's words (HonorsNet.LetterText's for its "wanted@" keys) and its title; nil for a key
-- that is none.
function Wanted.LetterText(key)
	local r = Bounty.LetterOf(key)
	if not r then return nil end
	local name = Display({ name = r.name })
	local level = r.level > 0 and (r.floor and L.WANTED_LEVEL_FLOOR:format(r.level) or tostring(r.level)) or L.WANTED_LEVEL_UNKNOWN
	local more = (r.base > 0 and L.WANTED_LETTER_LEVEL:format(r.base) or "") .. (r.revenge > 0 and L.WANTED_LETTER_REVENGE:format(r.revenge) or "")
	local text
	if r.kills > 0 then text = L.WANTED_LETTER:format(name, level, r.kills, r.bounty, more, r.points)
	else text = L.WANTED_LETTER_FIRST:format(name, level, more, r.points) end
	return text, Wanted.LetterTitle(key)
end
-- (HonorsNet.TitleText's for its "wanted@" keys: the list in the profile's Edit.)
function Wanted.LetterTitle(key)
	local r = Bounty.LetterOf(key)
	return r and L.WANTED_LETTER_TITLE:format(Display({ name = r.name })) or nil
end

-- An own kill: its letter waits to go (Bounty.Notices), and its numbers to settle.
-- (1.2.4 repair: the letter's key was made here, at the kill, but a member's death before the kill
-- often reaches this client after it (his recap read at a retry, then the channel): the Rebuild
-- orders it in and the claim, and the Slayers ranking, pay more than the letter said. Now the
-- letter keeps its claim (id, entry) and what the row saw of his level, and its key is made once,
-- as it goes, from the claim as this client holds it then (Bounty.SettledKey), LETTER_SETTLE after
-- the kill at the soonest. A kill that pays nothing then has no letter; the key made here is kept
-- for a claim this client no longer holds, its entry gone.)
Bounty.LETTER_SETTLE = 15 -- seconds after the kill (the recap's retries, 2 s, and the channel's own wait)
function Bounty.Slain(s, e)
	local t = s.targets[e.targetKey]
	local claim
	for _, c in ipairs(type(t) == "table" and type(t.claims) == "table" and t.claims or {}) do if c.id == e.id then claim = c end end
	local key = claim and Bounty.LetterKey(e, claim, t.name or e.victimName) or nil
	local who = NameKey(ns.me)
	if not key or not who then return nil end
	s.slayerLetters[#s.slayerLetters + 1] = { key = key, who = who, at = Whole(e.at, 0, 4294967295) or 0, id = e.id, target = e.targetKey,
		digest = e.digest, hl = Bounty.Level(e.hl), hf = e.hf == true or nil, due = math.floor(Clock()) + Bounty.LETTER_SETTLE }
	while #s.slayerLetters > Bounty.LETTERS_MAX do table.remove(s.slayerLetters, 1) end
	Bounty.NoticesSoon()
	return key
end

-- A waiting letter's key, as it goes: made from its claim as this client holds it now (a death
-- heard after the kill and ordered in: Rebuild), else the key the kill made (its entry made room,
-- or its claims past MAX_CLAIMS); nil for none: the kill pays nothing now, its row was voided or
-- its entry taken off.
function Bounty.SettledKey(s, r)
	local t = type(r.target) == "string" and (s.targets[r.target] or s.targets[s.aliases[r.target] or ""]) or nil
	if type(t) == "table" and t.active ~= true then return nil end
	local row = r.id and Bounty.RowOf(s, r.id) or nil
	if row and row.void then return nil end
	local claim
	for _, c in ipairs(type(t) == "table" and type(t.claims) == "table" and t.claims or {}) do if c.id == r.id then claim = c end end
	local key = claim and Bounty.LetterKey({ digest = r.digest, points = claim.points, level = claim.level, hl = r.hl, hf = r.hf,
		revenge = claim.revenge }, claim, t.name) or r.key
	local parts = Bounty.LetterOf(key)
	return parts and parts.points > 0 and key or nil
end

-- A letter to HonorsNet's queue (it shows, and keeps it to read again); to the King, or where
-- HonorsNet is not there, the toast. true when it went (or there was none to send), else false
-- and why it waits.
-- (1.2.4 repair: one at a time, with nothing of the King's letter's open or waiting in its queue,
-- so it shows as it goes; with the gamepad UI it stays here, saved, until the Olympus window is
-- open (chat says once that a letter waits, HonorsNet.WaitForWindow), then shows at once. Before,
-- it went to HonorsNet's queue at once, which marked it told: a /reload or a logout before the
-- Olympus window opened lost its showing, and the window's opening showed it even in an instance.
-- The letter is never marked told in the profile: this queue shows it once, HonorsNet.QueueLetter.)
function Bounty.SendLetter(key)
	local r = Bounty.LetterOf(key)
	if not r then return true end
	local toast = L.WANTED_LETTER_TOAST:format(Display({ name = r.name }), r.points)
	local HN = ns.HonorsNet
	if type(HN) ~= "table" or HN.missing or type(HN.QueueLetter) ~= "function" then Bounty.Say(toast) return true end
	local okK, king = pcall(function() return type(HN.LetterToSender) == "function" and HN.LetterToSender() == true end)
	if not okK or king then Bounty.Say(toast) return true end
	local okB, busy = pcall(function()
		local f = type(HN.LetterFrame) == "function" and HN.LetterFrame() or nil
		local queued = type(HN.QueuedLetters) == "function" and HN.QueuedLetters() or nil
		return f and f.IsShown and f:IsShown() or type(queued) == "table" and queued[1] ~= nil
	end)
	if not okB or busy then return false, "kings-letter" end
	local UI = ns.UI
	if ns.GamepadUI() and not (type(UI) == "table" and type(UI.IsShown) == "function" and UI.IsShown()) then
		if type(HN.WaitForWindow) == "function" then pcall(HN.WaitForWindow) end
		return false, "window"
	end
	if not pcall(HN.QueueLetter, key, nil, true) then Bounty.Say(toast) end
	return true
end

-- The letters waiting for this character: each once its numbers settled (its due), the oldest
-- first, as long as each goes (Bounty.SendLetter: one at a time). How many went, and why the rest
-- wait (nil: none waits); "settling", its due then in Bounty.session.settleAt.
function Bounty.SendLetters(s, me)
	local now, n, i, soonest = math.floor(Clock()), 0, 1, nil
	while i <= #s.slayerLetters do
		local r = s.slayerLetters[i]
		local due = type(r) == "table" and Whole(r.due, 0, 4294967295) or 0
		if type(r) ~= "table" or r.who ~= me then
			i = i + 1
		elseif due > now then
			soonest = math.min(soonest or due, due)
			i = i + 1
		else
			local key = Bounty.SettledKey(s, r)
			if key then
				local went, why = Bounty.SendLetter(key)
				if not went then return n, why end
				n = n + 1
			end
			table.remove(s.slayerLetters, i)
		end
	end
	Bounty.session.settleAt = soonest
	return n, soonest and "settling" or nil
end

-- The avenged notice's words.
function Bounty.AvengedText(r)
	local avenger, horde = Display({ name = r.name }), Display({ name = r.horde })
	local times = (tonumber(r.times) or 1) > 1 and L.WANTED_AVENGED_TIMES:format(r.times) or ""
	if r.guild then return L.WANTED_AVENGED:format(avenger, r.guild, horde, times) end
	return L.WANTED_AVENGED_NOGUILD:format(avenger, horde, times)
end

-- Its buttons: Thank (Olympus's whisper window with the thanks in its box: nothing is sent until the
-- player's own Send or Enter), Whisper (that window, its box empty: Olympus's in both input modes,
-- its box never taking the keyboard from the chat's, ns.Focus) and See (his Olympus profile).
function Bounty.Thank(r)
	local UI, name = ns.UI, type(r) == "table" and CleanName(r.name) or nil
	if not name or type(UI) ~= "table" or type(UI.WhisperText) ~= "function" then return false end
	return UI.WhisperText(ns.TellName(name), L.WANTED_THANK_TEXT) ~= nil
end
function Bounty.Whisper(r)
	local D, name = ns.Dialog, type(r) == "table" and CleanName(r.name) or nil
	if not name then return false end
	if type(D) ~= "table" or D.missing or type(D.Show) ~= "function" then ns.Print(L.RESTART_NEEDED) return false end
	local tell = ns.TellName(name)
	return D.Show("OLYMPUS_WHISPER", tell, nil, tell) ~= nil
end
function Bounty.See(r)
	local UI, name = ns.UI, type(r) == "table" and CleanName(r.name) or nil
	if not name or type(UI) ~= "table" or type(UI.ShowPerson) ~= "function" then return false end
	return UI.ShowPerson({ name = ns.ShortName(name), realm = ns.RealmOf(name), guild = r.guild, source = "addon" }) and true or false
end

-- The one-way score-v2 balancing note. It is personal to the character that saw a lower total,
-- never a broadcast or a reusable King's letter. Its saved row is removed only after this
-- parchment reports itself shown, so a missing UI or a reload before then cannot consume it.
function Bounty.ScoreMigration(s, me)
	local r = type(s) == "table" and s.scoreMigrationLetter or nil
	if type(r) ~= "table" or r.version ~= Wanted.SCORE_VERSION or type(r.who) ~= "string" or #r.who > 120
		or not r.who:find("^n:") then return nil end
	local old, new = Whole(r.old, 0, Wanted.MAX_POINTS), Whole(r.new, 0, Wanted.MAX_POINTS)
	if not old or not new or old <= new or me and r.who ~= me then return nil end
	return { version = Wanted.SCORE_VERSION, who = r.who, old = old, new = new }
end

function Bounty.ScoreMigrationText(r)
	r = type(r) == "table" and r or {}
	return L.WANTED_SCORE_MIGRATION_BODY:format(tonumber(r.old) or 0, tonumber(r.new) or 0)
end

local function MakeScoreMigrationFrame()
	if type(ns.Window) ~= "function" then return nil end
	local f = ns.Window("OlympusWantedScoreMigration", UIParent, { inset = false, close = false, escape = false })
	if type(f) ~= "table" then return nil end
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetSize(470, 530)
	f:SetPoint("CENTER", 0, 30)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	local inner = type(f.inner) == "table" and f.inner or { 9, -24, -6, 4 }
	local bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	bg:SetPoint("TOPLEFT", inner[1], inner[2])
	bg:SetPoint("BOTTOMRIGHT", inner[3], inner[4])
	local ui = ns.UI
	local parchments = type(ui) == "table" and type(ui.PARCHMENTS) == "table" and ui.PARCHMENTS
		or { "Interface\\QuestFrame\\QuestBG", "Interface\\Stationery\\StationeryTest1" }
	local file = type(ui) == "table" and type(ui.FirstTexture) == "function" and ui.FirstTexture(parchments) or parchments[1]
	if type(GetFileIDFromPath) == "function" and not GetFileIDFromPath(file) then
		bg:SetColorTexture(0.87, 0.80, 0.64, 0.97)
	else
		bg:SetTexture(file)
		if file:find("QuestBG", 1, true) then bg:SetTexCoord(0, 296 / 512, 0, 331 / 512) end
	end
	f.title = f:CreateFontString(nil, "ARTWORK", _G.QuestTitleFont and "QuestTitleFont" or "GameFontNormalLarge")
	f.title:SetPoint("TOP", 0, -30)
	f.title:SetText(L.WANTED_SCORE_MIGRATION_TITLE)
	f.body = f:CreateFontString(nil, "ARTWORK", _G.QuestFont and "QuestFont" or "GameFontHighlight")
	f.body:SetPoint("TOPLEFT", 38, -74)
	f.body:SetPoint("RIGHT", -38, 0)
	f.body:SetJustifyH("LEFT")
	f.body:SetJustifyV("TOP")
	if f.body.SetWordWrap then f.body:SetWordWrap(true) end
	f.done = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.done:SetSize(100, 24)
	f.done:SetPoint("BOTTOM", 0, 24)
	f.done:SetText(OKAY or "OK")
	f.done:SetScript("OnClick", function() f:Hide() end)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", -4, -4)
	f.close:SetScript("OnClick", function() f:Hide() end)
	f:SetScript("OnHide", function()
		if ns.After and Bounty.Waiting() then ns.After(1, "wanted notices", Bounty.NoticesSoon) end
	end)
	if ns.EscapeCloses then
		ns.EscapeCloses("OlympusWantedScoreMigration")
		if f.HookScript then f:HookScript("OnShow", function() ns.EscapeCloses("OlympusWantedScoreMigration") end) end
	end
	return f
end

function Bounty.ShowScoreMigration(s, me)
	local r = Bounty.ScoreMigration(s, me)
	if not r then return false, "none" end
	local ok, frame = pcall(function()
		scoreMigrationFrame = scoreMigrationFrame or MakeScoreMigrationFrame()
		if not scoreMigrationFrame then return nil end
		scoreMigrationFrame.body:SetText(Bounty.ScoreMigrationText(r))
		scoreMigrationFrame:Show()
		return scoreMigrationFrame
	end)
	if not ok or not frame then
		if not ok and ns.CaptureError then ns.CaptureError("wanted score migration letter", frame) end
		return false, "ui"
	end
	local shownOK, shown = pcall(function() return frame:IsShown() end)
	if not shownOK or shown ~= true then return false, "ui" end
	s.scoreMigrationLetter = nil
	return true
end

function Bounty.ScoreMigrationFrame() return scoreMigrationFrame end

-- The first of a list's notices for this character, or nil, and its place.
function Bounty.For(list, me)
	for i, r in ipairs(type(list) == "table" and list or {}) do if type(r) == "table" and r.who == me then return r, i end end
	return nil
end
-- Whether a notice waits for this character.
function Bounty.Waiting()
	local s, me = Store(false), NameKey(ns.me)
	return s ~= nil and me ~= nil and (Bounty.ScoreMigration(s, me) ~= nil
		or Bounty.For(s.slayerLetters, me) ~= nil or Bounty.For(s.avenged, me) ~= nil)
end

-- The notices for this character shown, when nothing is in the way (NOTICE_LOGIN after login, and
-- Bounty.Blocked): the letters waiting whose numbers settled, one at a time (Bounty.SendLetters),
-- then one avenged dialog, unless one of ours is up already (an avenged one, a whisper window it
-- opened), the King's letter shows or, with the gamepad UI, the Olympus window is closed. Returns
-- how many went, and why the rest wait (nil: none waits; of the letters' and the dialog's, the one
-- looked at again soonest).
Bounty.DIALOGS_UP = { "OLYMPUS_WANTED_AVENGED", "OLYMPUS_WHISPER_TEXT", "OLYMPUS_WHISPER" }
function Bounty.Notices()
	local s, me = Store(false), NameKey(ns.me)
	if not s or not me or not ns.IsMember or ns.IsMember() ~= true or ns.faction == "Horde" then return 0 end
	if not Bounty.Waiting() then return 0 end
	if Bounty.LoginLeft() > 0 then return 0, "login" end
	local why = Bounty.Blocked()
	if why then return 0, why end
	local migration, migrationWhy = Bounty.ShowScoreMigration(s, me)
	if migration then return 1, Bounty.Waiting() and "score-letter" or nil end
	if migrationWhy ~= "none" then return 0, migrationWhy end
	local n, letters = Bounty.SendLetters(s, me)
	local function Sooner(other)
		if not letters then return other end
		if not other then return letters end
		return Bounty.NoticeWait(other) <= Bounty.NoticeWait(letters) and other or letters
	end
	local r, i = Bounty.For(s.avenged, me)
	if not r then return n, letters end
	local D, HN, UI = ns.Dialog, ns.HonorsNet, ns.UI
	if type(D) ~= "table" or D.missing or type(D.Show) ~= "function" then
		table.remove(s.avenged, i)
		ns.Print(Bounty.AvengedText(r))
		return n + 1, Sooner(Bounty.For(s.avenged, me) and "dialog" or nil)
	end
	if type(D.Find) == "function" then
		for _, which in ipairs(Bounty.DIALOGS_UP) do if D.Find(which) then return n, Sooner("dialog") end end
	end
	local okL, letter = pcall(function()
		local f = type(HN) == "table" and not HN.missing and type(HN.LetterFrame) == "function" and HN.LetterFrame() or nil
		return f and f.IsShown and f:IsShown() or false
	end)
	if not okL or letter then return n, Sooner("kings-letter") end
	if ns.GamepadUI() and not (type(UI) == "table" and type(UI.IsShown) == "function" and UI.IsShown()) then
		if not Bounty.session.toldAvenged then
			Bounty.session.toldAvenged = true
			ns.Print(L.WANTED_AVENGED_WAITING)
		end
		return n, Sooner("window")
	end
	table.remove(s.avenged, i)
	Bounty.session.toldAvenged = nil
	local text = Bounty.AvengedText(r)
	local ok, f = pcall(D.Show, "OLYMPUS_WANTED_AVENGED", text, nil, r)
	if not ok or not f then
		if not ok and ns.CaptureError then ns.CaptureError("wanted avenged", f) end
		ns.Print(text)
	end
	return n + 1, Sooner(Bounty.For(s.avenged, me) and "dialog" or nil)
end

-- The seconds left of NOTICE_LOGIN since this session's login (0 past it, or before any login).
function Bounty.LoginLeft()
	local at = Bounty.session.loginAt
	if type(at) ~= "number" then return 0 end
	local left = Bounty.NOTICE_LOGIN - (math.floor(Clock()) - at)
	return (left > 0 and left <= Bounty.NOTICE_LOGIN) and left or 0
end
-- The notices now, else again while some wait (one beat a session): the rest of NOTICE_LOGIN after
-- a login, WINDOW_TICK for a window to open or close, NOTICE_TICK for the rest; a letter settling,
-- until its due (Bounty.SendLetters).
function Bounty.NoticeWait(why)
	if why == "login" then return math.max(1, Bounty.LoginLeft()) end
	if why == "settling" then
		local left = (tonumber(Bounty.session.settleAt) or 0) - math.floor(Clock())
		return math.max(1, math.min(Bounty.LETTER_SETTLE, left))
	end
	return (why == "window" or why == "dialog" or why == "kings-letter" or why == "score-letter")
		and Bounty.WINDOW_TICK or Bounty.NOTICE_TICK
end
function Bounty.NoticesSoon()
	local n, why = Bounty.Notices()
	if not why or Bounty.session.noticeTick or not ns.After then return n end
	Bounty.session.noticeTick = true
	local gen = Bounty.session.gen
	local function Tick()
		if gen ~= Bounty.session.gen then return end
		local _, again = Bounty.Notices()
		if not again then Bounty.session.noticeTick = false return end
		ns.After(Bounty.NoticeWait(again), "wanted notices", Tick)
	end
	ns.After(Bounty.NoticeWait(why), "wanted notices", Tick)
	return n
end

-- The avenged dialog: Olympus's own (Dialog.Show), in both input modes, no edit box; See keeps it.
StaticPopupDialogs["OLYMPUS_WANTED_AVENGED"] = {
	text = "%s",
	button1 = L.WANTED_AVENGED_THANK,
	button2 = L.WANTED_AVENGED_CLOSE,
	button3 = L.WANTED_AVENGED_WHISPER,
	extra = { label = L.WANTED_AVENGED_SEE, onClick = function(_, r) Bounty.See(r) end },
	OnAccept = function(_, r) Bounty.Thank(r) end,
	OnAlt = function(_, r) Bounty.Whisper(r) end,
	-- (The next one waiting, a moment after.)
	OnHide = function() if ns.After then ns.After(1, "wanted notices", Bounty.NoticesSoon) end end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

---------------------------------------------------------------------------
-- The avenged ask (1.2.4 repair, W7). A member offline when the Horde player who killed him was
-- slain heard that kill's row from nobody but a reviewer's catch-up answer (W4: its newest rows
-- alone, and only while a reviewer is online), so most often he was never told. Now, at login,
-- while this character keeps deaths open (s.mine), his client asks the channel ASK_AFTER after
-- login (after the catch-up's answer) and ASK_EVERY apart, ASK_TRIES at most, until none is open:
--   W7~1~<scope>~<d>[,<d>...]   channel: ASK_MAX digests at most, his newest deaths' first, each
--       the first 8 hex of the digest of "OLYW7|<scope>|<the Horde player's GUID>" (Bounty.AskDigest):
--       no GUID, name, time or count of his deaths on the wire.
-- A client answers only with rows every client takes from it anyway, on the channel, as it sends
-- them: its player's own kills of a Horde player a digest names (Share.Send: his own row again),
-- and a reviewer's client the other members' too (Share.Relay "R": his relay), the claims its
-- ledger holds live and fresh (SHARE_AGE), the newest ASK_ROWS sent oldest first (each avenges the
-- deaths before it, Bounty.Avenge). ASK_PER answers to one asker in ASK_WINDOW, ASK_ALL asks
-- answered a minute in all; never its own echo, an asker the moderators hide, another realm group
-- or faction, nor from a client the moderators took off. A plain member never answers with another
-- member's row: no client would take it from him. The asker takes the rows as any row
-- (Share.Take), and the first claim after each open death avenges it, the answers heard within
-- ASK_SETTLE of the ask together, whatever the order they came in (Bounty.AvengeSoon).
---------------------------------------------------------------------------

Bounty.ASK_AFTER = 120  -- the ask this long after login (the catch-up's answer first: W4 at 45 s)...
Bounty.ASK_EVERY = 600  -- ...again this often...
Bounty.ASK_TRIES = 3    -- ...this many times a login at most, while a death is open
Bounty.ASK_MAX = 4      -- Horde players one ask names at most (the newest deaths')
Bounty.ASK_ROWS = 6     -- rows one answer carries at most (the newest)
Bounty.ASK_PER = 2      -- answers to one asker...
Bounty.ASK_WINDOW = 600 -- ...in this many seconds...
Bounty.ASK_ALL = 10     -- ...and asks answered a minute, everyone's
Bounty.ASK_DELAY = 2    -- an answer this long after the ask (and a part of 5 s of its own)

-- A Horde player's GUID as an ask names it: the first 8 hex of its digest with the scope.
function Bounty.AskDigest(guid, scope)
	guid = Guid(guid)
	local d = guid and type(scope) == "string" and Digest("OLYW7|" .. scope .. "|" .. guid) or nil
	return d and d:sub(1, 8) or nil
end

-- This character's open deaths' Horde players, his newest death first: { guid, at } each.
function Bounty.Open(s, me)
	local out = {}
	if not s or not me then return out end
	for guid, m in pairs(s.mine) do
		local last
		for _, d in ipairs(type(m) == "table" and type(m.deaths) == "table" and m.deaths or {}) do
			if type(d) == "table" and d.who == me and (not last or (tonumber(d.at) or 0) > last) then last = tonumber(d.at) or 0 end
		end
		if last then out[#out + 1] = { guid = guid, at = last } end
	end
	table.sort(out, function(a, b)
		if a.at ~= b.at then return a.at > b.at end
		return a.guid < b.guid
	end)
	return out
end

-- The ask, now: true when it went to Comm, else false and why ("none": no death open).
function Bounty.Ask()
	local s, me, C = Store(false), NameKey(ns.me), ns.Comm
	if not ns.IsMember or ns.IsMember() ~= true or ns.faction == "Horde" or NetOff() then return false, "member" end
	if not s or not me then return false, "none" end
	Bounty.TrimMine(s)
	local open, scope, digests = Bounty.Open(s, me), Scope(), {}
	for i = 1, math.min(#open, Bounty.ASK_MAX) do digests[#digests + 1] = Bounty.AskDigest(open[i].guid, scope) end
	if #digests == 0 then return false, "none" end
	if type(C) ~= "table" or type(C.Send) ~= "function" then return false, "transport" end
	local body = table.concat({ "W7", 1, scope, table.concat(digests, ",") }, "~")
	local session = Bounty.session
	session.asked = (session.asked or 0) + 1
	-- (Its answers avenge together, ASK_SETTLE after it: Bounty.AvengeSoon.)
	return C.Send("CHANNEL", body, "wanted-ask", false, false, function(went)
		if went then session.askSettle = math.floor(Clock()) + Bounty.ASK_SETTLE end
	end, { owner = Wanted, guardKey = "wanted-ask", guard = function()
		return ns.IsMember() == true and ns.faction ~= "Horde" and not NetOff() and Scope() == scope
	end }) == true
end
-- The ask's next try (try: 1 the first, ASK_AFTER after login), this session's only.
function Bounty.AskLater(gen, try)
	if not ns.After then return end
	ns.After(try == 1 and Bounty.ASK_AFTER or Bounty.ASK_EVERY, "wanted avenged ask", function()
		if gen ~= Bounty.session.gen then return end
		local _, why = Bounty.Ask()
		if why ~= "none" and try < Bounty.ASK_TRIES then Bounty.AskLater(gen, try + 1) end
	end)
end

-- The W7 handler: an ask heard, answered later with the rows found (Bounty.ASK_DELAY). true and
-- how many rows will go, or false and why.
function Bounty.Answer(dist, sender, text)
	if dist ~= "CHANNEL" or type(text) ~= "string" or #text > 255 then return false, "lane" end
	if not ns.IsMember or ns.IsMember() ~= true or not ns.me or ns.faction == "Horde" or NetOff() then return false, "member" end
	sender = CleanName(sender)
	if not sender or SameName(sender, ns.me) then return false, "own" end
	local scope, list = text:match("^W7~1~(%x+)~([%x,]+)$")
	if not scope then return false, "shape" end
	if scope ~= Scope() then return false, "scope" end
	local asked, n = {}, 0
	for d in list:gmatch("[^,]+") do
		if #d ~= 8 then return false, "shape" end
		n = n + 1
		if n > Bounty.ASK_MAX then return false, "shape" end
		asked[d:lower()] = true
	end
	if n == 0 or #list ~= n * 9 - 1 then return false, "shape" end
	local M = ns.Moderation
	if type(M) == "table" and not M.missing and type(M.Hides) == "function" then
		local ok, hidden = pcall(M.Hides, sender)
		if not ok or hidden then return false, "olympus" end
	end
	local s = Store(false)
	if not s then return false, "none" end
	local reviewer, now, rows = Wanted.CanPublish(ns.me), math.floor(Clock()), {}
	for i = #s.evidence, 1, -1 do
		if #rows >= Bounty.ASK_ROWS then break end
		local e = s.evidence[i]
		local t = type(e) == "table" and s.targets[e.targetKey] or nil
		if type(t) == "table" and t.active == true and e.action == "claim" and not e.void and now - (tonumber(e.at) or 0) <= Wanted.SHARE_AGE
			and (e.own and SameName(e.from, ns.me) or reviewer and e.peer) and asked[Bounty.AskDigest(e.victimGuid, scope) or ""] then
			rows[#rows + 1] = e
		end
	end
	if #rows == 0 then return false, "none" end
	local session = Bounty.session
	session.asks, session.askers = session.asks or {}, session.askers or {}
	if not Share.Count(session.asks, "all", now, 60, Bounty.ASK_ALL) then return false, "rate" end
	if not Share.Count(session.askers, ns.Fold(sender), now, Bounty.ASK_WINDOW, Bounty.ASK_PER) then return false, "rate" end
	local gen = session.gen
	local function Go()
		if gen ~= Bounty.session.gen then return end
		for i = #rows, 1, -1 do
			local e = rows[i]
			if not e.void then
				if e.own then Share.Send(e) elseif Wanted.CanPublish(ns.me) then Share.Relay(e, "R") end
			end
		end
	end
	if ns.After then ns.After(Bounty.ASK_DELAY + Share.Offset() % 5, "wanted avenged answer", Go) else Go() end
	return true, #rows
end

-- The notices' saved parts by shape (Wanted.Prune): s.mine within its bounds (Bounty.TrimMine), the
-- avenged notices (AVENGED_MAX) and the letters (LETTERS_MAX) waiting.
function Bounty.PruneNotices(s, now)
	for guid, m in pairs(s.mine) do
		local deaths = {}
		for _, d in ipairs(type(m) == "table" and type(m.deaths) == "table" and m.deaths or {}) do
			local at, who = type(d) == "table" and Whole(d.at, 0, 4294967295) or nil, type(d) == "table" and d.who or nil
			if at and type(who) == "string" and #who <= 120 then deaths[#deaths + 1] = { at = at, who = who } end
		end
		if type(guid) ~= "string" or Guid(guid) ~= guid or #deaths == 0 then s.mine[guid] = nil
		else s.mine[guid] = { name = CleanName(m.name), deaths = deaths } end
	end
	Bounty.TrimMine(s, now)
	local avenged, letters = {}, {}
	for _, r in ipairs(s.avenged) do
		local name, horde = type(r) == "table" and CleanName(r.name) or nil, type(r) == "table" and CleanName(r.horde) or nil
		if name and horde and type(r.who) == "string" and #r.who <= 120 then
			avenged[#avenged + 1] = { id = Clean(r.id, 160), who = r.who, name = name, guild = Sight.GuildName(r.guild), horde = horde,
				times = Whole(r.times, 1, Bounty.MINE_DEATHS) or 1, at = Whole(r.at, 0, 4294967295) or 0 }
		end
	end
	while #avenged > Bounty.AVENGED_MAX do table.remove(avenged, 1) end
	-- (1.2.4 repair: a letter keeps its claim, its row's digest and level, and its due: Bounty.Slain.)
	for _, r in ipairs(s.slayerLetters) do
		if type(r) == "table" and Bounty.LetterOf(r.key) and type(r.who) == "string" and #r.who <= 120 then
			local digest = type(r.digest) == "string" and #r.digest == 16 and r.digest:match("^%x+$") or nil
			letters[#letters + 1] = { key = r.key, who = r.who, at = Whole(r.at, 0, 4294967295) or 0, id = Clean(r.id, 160),
				target = type(r.target) == "string" and #r.target <= 160 and r.target or nil, digest = digest, hl = Bounty.Level(r.hl),
				hf = r.hf == true or nil, due = Whole(r.due, 0, 4294967295) or 0 }
		end
	end
	while #letters > Bounty.LETTERS_MAX do table.remove(letters, 1) end
	s.avenged, s.slayerLetters = avenged, letters
	-- A balancing letter survives reloads only in its exact personal, decreasing v2 shape. It is
	-- otherwise inert data, never a source for either ranking or protocol.
	local migration = Bounty.ScoreMigration(s)
	s.scoreMigrationLetter = migration
	-- (1.2.4 repair: the claims told of, by shape, within GRUDGE_DAYS and TOLD_MAX.)
	Bounty.TrimTold(s, now)
end

-- /oly wanted status: what Most Wanted holds and did this session, in the copy window (a chat line
-- cannot be copied): the store, the sources it reads (the game's own APIs, the native kill event's
-- registration), what this client captured and shared, what it heard, and why each capture or row
-- was refused, the newest first, with a key to the reasons. 1.2.3: the bounty's weights, each Horde
-- player's bounty in points and the Slayers' points (the highest first), and the earlier deaths.
Wanted.STATUS_ROWS = 10 -- bounties and Slayers listed, each
function Wanted.StatusText()
	local s = Store(false)
	local out = {}
	local function Add(text) out[#out + 1] = text end
	local function Yes(v) return v and L.WANTED_STATUS_YES or L.WANTED_STATUS_NO end
	local active, held, off, rows, mine, unsent = 0, 0, 0, 0, 0, 0
	-- (1.2.4: wanted, the entries on the list; held, those on the ledger off it, 0 points and 0
	-- kills: Wanted.IsWanted.)
	for _, t in pairs(s and s.targets or {}) do
		if Wanted.IsWanted(t) then active = active + 1 elseif t.active then held = held + 1 else off = off + 1 end
	end
	for _, e in ipairs(s and s.evidence or {}) do
		if not e.void then rows = rows + 1 end
		if e.own then mine = mine + 1 if not e.shared then unsent = unsent + 1 end end
	end
	Add(L.WANTED_STATUS_STORE:format(tostring(ns.group or ns.realm or "?"), tostring(ns.faction or "?"), active, held, off, rows,
		Count(s and s.slayers or {}), s and L.WANTED_STATUS_YES or L.WANTED_STATUS_NO))
	local C = ns.Comm
	Add(L.WANTED_STATUS_SOURCES:format(Yes(Share.partyKill), Yes(type(C_DeathRecap) == "table" and type(C_DeathRecap.GetRecapEvents) == "function"),
		Yes(type(GetPlayerInfoByGUID) == "function"), Yes(InInstance()),
		Yes(type(C) == "table" and type(C.ChannelReady) == "function" and C.ChannelReady() == true)))
	local n = Share.counts
	Add(L.WANTED_STATUS_SESSION:format(n.kill or 0, n.death or 0, n.sent or 0, n.unsent or 0, mine, unsent,
		n.heard or 0, n.relay or 0, n.mark or 0, n.counted or 0))
	local reasons = {}
	for why, count in pairs(Share.why) do if count > 0 then reasons[#reasons + 1] = why .. " " .. count end end
	table.sort(reasons)
	Add(L.WANTED_STATUS_EARLIER_LINE:format(n.earlier or 0, Bounty.session.added or 0))
	Add(L.WANTED_STATUS_REFUSED:format(#reasons > 0 and table.concat(reasons, ", ") or "-"))
	Add("")
	local S = Bounty.SCORE
	Add(L.WANTED_STATUS_WEIGHTS:format(S.OFFICE.K, S.OFFICE.H, S.OFFICE.G, S.OFFICE.C, S.OFFICE.O, math.floor(S.REPEAT_GAP / 60), S.BOUNTY_MAX,
		S.KILL_LEVEL_STEP, S.REVENGE, S.GRUDGE_DAYS))
	Add(L.WANTED_STATUS_BOUNTIES)
	local listed = 0
	for _, t in ipairs(Wanted.Targets(true)) do
		if t.current > 0 and listed < Wanted.STATUS_ROWS then
			listed = listed + 1
			Add(L.WANTED_STATUS_BOUNTY_ROW:format(Display(t), t.current, t.lifetimeKills))
		end
	end
	if listed == 0 then Add("  " .. L.WANTED_STATUS_NONE) end
	Add(L.WANTED_STATUS_SLAYERS)
	local all = Wanted.Rankings().all
	for i = 1, math.min(#all, Wanted.STATUS_ROWS) do
		Add(L.WANTED_STATUS_SLAYER_ROW:format(i, all[i].name and (ns.DisplayName and ns.DisplayName(all[i].name) or all[i].name) or L.WANTED_UNKNOWN,
			all[i].points, all[i].claims or 0))
	end
	if #all == 0 then Add("  " .. L.WANTED_STATUS_NONE) end
	Add("")
	Add(L.WANTED_STATUS_LAST)
	local kinds = { kill = L.WANTED_STATUS_KILL, death = L.WANTED_STATUS_DEATH, heard = L.WANTED_STATUS_HEARD,
		relay = L.WANTED_STATUS_RELAY, mark = L.WANTED_STATUS_MARK, earlier = L.WANTED_STATUS_EARLIER }
	local dateFn = date or (os and os.date)
	for i = #Share.log, 1, -1 do
		local r = Share.log[i]
		local when = type(dateFn) == "function" and dateFn("%H:%M:%S", r.at) or tostring(r.at)
		local result = r.ok and (r.action == "claim" and L.WANTED_STATUS_CLAIM:format(r.points or 0)
			or r.again and L.WANTED_STATUS_AGAIN:format(math.floor(S.REPEAT_GAP / 60)) or L.WANTED_STATUS_BOUNTY:format(r.points or 0))
			or L.WANTED_STATUS_REFUSAL:format(r.why or "?")
		Add(("  %s  %s  %s%s%s  %s"):format(when, kinds[r.kind] or r.kind, r.who or "?", r.from and (" · " .. r.from) or "",
			r.guild and (" <" .. r.guild .. ">") or "", result))
	end
	if #Share.log == 0 then Add("  " .. L.WANTED_STATUS_EMPTY) end
	Add("")
	Add(L.WANTED_STATUS_KEY)
	return table.concat(out, "\n")
end

function Wanted.ShowStatus()
	local text = Wanted.StatusText()
	if ns.UI and ns.UI.ShowCopy then
		ns.UI.ShowCopy(L.WANTED_STATUS_TITLE, text, { label = L.WANTED_STATUS_REFRESH, fn = function() Wanted.ShowStatus() end },
			{ key = "wanted", big = true })
		return true
	end
	for line in text:gmatch("[^\n]+") do ns.Print(line) end
	return true
end

-- /oly wanted [status]
function Wanted.Slash(rest)
	local word = (tostring(rest or ""):match("^%s*(%S*)") or ""):lower()
	if word == "" or word == "status" then return Wanted.ShowStatus() end
	ns.Print(L.WANTED_STATUS_USAGE)
	return false
end

function Wanted.Prune()
	local s = Store(false)
	if not s then return false end
	local SOURCES = { manual = true, SELF_DEATH = true, PARTY_KILL = true, shared = true, removed = true }
	for key, t in pairs(s.targets) do
		local ident = type(t) == "table" and Identity(t.name, t.guid, t.realm) or nil
		if not ident or type(key) ~= "string" then
			s.targets[key] = nil
		else
			t.key, t.name, t.guid, t.realm = key, ident.name, ident.guid, ident.realm
			t.active = t.active == true
			t.addedAt = Whole(t.addedAt, 0, 4294967295) or 0
			t.addedBy = CleanName(t.addedBy)
			t.source = SOURCES[t.source] and t.source or "manual"
			t.removedAt, t.removedBy = Whole(t.removedAt, 0, 4294967295), CleanName(t.removedBy)
			t.wireName = t.wireName == true and t.name ~= nil or nil
			local d = TargetDerived(t)
			for field, value in pairs(d) do t[field] = value end
			t.victims, t.claims = CopyList(t.victims, Wanted.MAX_VICTIMS), CopyList(t.claims, Wanted.MAX_CLAIMS)
			if ident.guidKey then s.aliases[ident.guidKey] = key end
		end
	end
	local evidence, first = {}, math.max(1, #s.evidence - Wanted.MAX_EVIDENCE + 1)
	for i = first, #s.evidence do
		local e = s.evidence[i]
		local id = type(e) == "table" and Clean(e.id, 160) or nil
		local targetKey = type(e) == "table" and type(e.targetKey) == "string" and (s.aliases[e.targetKey] or e.targetKey) or nil
		local target = targetKey and s.targets[targetKey] or nil
		local killer = type(e) == "table" and Identity(e.killerName, e.killerGuid) or nil
		local victim = type(e) == "table" and Identity(e.victimName, e.victimGuid) or nil
		local targetIdentity = e and e.action == "bounty" and killer or victim
		-- (1.2.3: a shared row's Olympian side may be its sender's name alone.)
		local peer = type(e) == "table" and e.peer == true
		local olympian = e and e.action == "bounty" and victim or killer
		if id and target and killer and killer.name and victim and victim.name and targetIdentity and targetIdentity.guid
			and (olympian and olympian.guid or peer)
			and (e.kind == "PARTY_KILL" or e.kind == "SELF_DEATH") and (e.action == "bounty" or e.action == "claim")
			and SameIdentity(Identity(target), targetIdentity) and Whole(e.at, 0, 4294967295) and Whole(e.month, 0, 200000) then
			local digest = type(e.digest) == "string" and e.digest:match("^%x+$") and #e.digest == 16 and e.digest or nil
			evidence[#evidence + 1] = { id = id, seq = Whole(e.seq, 0, 2147483647) or 0, at = math.floor(e.at), month = math.floor(e.month),
				kind = e.kind, action = e.action, targetKey = targetKey, killerName = killer.name, killerGuid = killer.guid,
				victimName = victim.name, victimGuid = victim.guid, zone = Clean(e.zone, 80), mapID = Whole(e.mapID, 1, 9999999),
				precision = e.precision == "consented" and "consented" or "approximate", void = e.void == true,
				correctedAt = Whole(e.correctedAt, 0, 4294967295), correctedBy = CleanName(e.correctedBy),
				correction = Clean(e.correction, 80), from = CleanName(e.from), digest = digest,
				peer = peer or nil, own = e.own == true and not peer or nil, shared = e.shared == true or nil,
				-- Absence means a row saved before the 1.2.4 self-claim path and remains trusted.
				memberVerified = not peer or e.memberVerified ~= false,
				earlier = e.earlier == true and not peer or nil,
				-- Keep the claimed guild for later membership promotion and deterministic office checks.
				guild = peer and Sight.GuildName(e.guild) or nil }
			-- (1.2.3: what it is worth, as frozen; a malformed one is none: it counts as a row without it.)
			local worth = Bounty.Fields(e)
			if worth then
				local kept = evidence[#evidence]
				kept.office, kept.ml, kept.hl, kept.hf = worth.office, worth.ml, worth.hl, worth.hf
			end
		end
	end
	-- (In the order of the deaths, as RecordKill keeps them: Share.Before.)
	for i = 2, #evidence do
		local e, j = evidence[i], i
		while j > 1 and Share.Before(e, evidence[j - 1]) do evidence[j] = evidence[j - 1] j = j - 1 end
		evidence[j] = e
	end
	s.evidence = evidence
	-- (The names' aliases, 1.2.3: each name to the best entry under it, Share.Better.)
	for alias, held in pairs(s.aliases) do
		if type(alias) ~= "string" or type(s.targets[held]) ~= "table" then s.aliases[alias] = nil end
	end
	for key, t in pairs(s.targets) do
		local nk = NameKey(t.name)
		if nk and nk ~= key then
			local holder = s.targets[s.aliases[nk] or nk]
			if holder ~= t and Share.Better(t, holder) then s.aliases[nk] = key end
		end
	end
	local order, seen, have = {}, {}, {}
	first = math.max(1, #s.seenOrder - Wanted.MAX_SEEN + 1)
	for i = first, #s.seenOrder do
		local id = Clean(s.seenOrder[i], 160)
		local old = id and s.seen[id]
		if id and not have[id] and type(old) == "table" then
			local at, seq = Whole(old.at, 0, 4294967295), Whole(old.seq, 0, 2147483647)
			if at and seq then order[#order + 1], seen[id], have[id] = id, { at = at, seq = seq }, true end
		end
	end
	s.seenOrder, s.seen = order, seen
	local now = math.floor(Clock())
	for fingerprint, at in pairs(s.recent) do
		if type(fingerprint) ~= "string" or not Whole(at, 0, 4294967295) or now - at > 30 then s.recent[fingerprint] = nil end
	end
	TrimList(s.audit, Wanted.MAX_AUDIT)
	-- The voided shared rows, by shape (1.2.3), within SHARE_AGE and VOIDS_MAX.
	for key, v in pairs(s.voids) do
		if type(key) ~= "string" or #key > 120 or type(v) ~= "table" or not Whole(v.at, 0, 4294967295) or not CleanName(v.from)
			or type(v.digest) ~= "string" or now - v.at > Wanted.SHARE_AGE then s.voids[key] = nil end
	end
	s.foldedAt = Whole(s.foldedAt, 0, 4294967295)
	-- 1.2.3: the recaps read (by shape, within SHARE_AGE and RECAP_READ_MAX), this client's own
	-- times in an instance (whole, in order, INSIDE_MAX), and the earlier deaths' notice waiting.
	for key, at in pairs(s.recapsRead) do
		if type(key) ~= "string" or #key > 96 or not Whole(at, 0, 4294967295) or now - at > Wanted.SHARE_AGE then s.recapsRead[key] = nil end
	end
	Bounty.TrimRead(s)
	-- (A time let go, or one not whole, moves s.insideSince past it: before it the times are not
	-- known whole any more, Bounty.Tracked.)
	local inside = {}
	s.insideSince = Whole(s.insideSince, 0, 4294967295)
	for _, span in ipairs(s.inside) do
		local from = type(span) == "table" and Whole(span.from, 0, 4294967295) or nil
		local to = type(span) == "table" and Whole(span.to, from or 0, 4294967295) or nil
		if from and (span.to == nil or to) and now - (to or now) <= Wanted.SHARE_AGE then inside[#inside + 1] = { from = from, to = to }
		elseif s.insideSince then s.insideSince = math.max(s.insideSince, to or now) end
	end
	s.inside = inside
	Bounty.TrimSpans(s, now)
	local notice = type(s.earlierNotice) == "table" and type(s.earlierNotice.rows) == "table" and s.earlierNotice.rows or {}
	local waiting = {}
	for _, r in ipairs(notice) do
		local id = type(r) == "table" and Clean(r.id, 160) or nil
		if id and Whole(r.at, 0, 4294967295) then
			waiting[#waiting + 1] = { id = id, name = CleanName(r.name), hl = Bounty.Level(r.hl), hf = r.hf == true or nil, at = r.at,
				points = Whole(r.points, 0, Wanted.MAX_POINTS) or 0 }
		end
	end
	while #waiting > Wanted.MAX_VICTIMS do table.remove(waiting, 1) end
	s.earlierNotice = #waiting > 0 and { rows = waiting } or nil
	-- 1.2.4: the notices' saved parts (the own deaths kept open, the notices and letters waiting).
	Bounty.PruneNotices(s, now)
	-- 1.2.2's review: its ledger (a reviewer's accepted rows) and when his evidence went to each
	-- reviewer. There is no review any more (1.2.3); they count for nothing and are dropped.
	s.ledger, s.sentAt = nil, nil
	-- The saved word, by shape only: RestoreGlobal checks everything else before it shows it.
	local g = s.global
	if type(g) ~= "table" or type(g.text) ~= "string" or #g.text > 1200 or type(g.issuer) ~= "string" then s.global = nil end
	if type(s.globalHeads) ~= "table" then s.globalHeads = nil end
	if type(s.reviewer) ~= "string" or not CleanName(s.reviewer) then s.reviewer = nil end
	Rebuild(s)
	for _, r in pairs(s.slayers) do TrimMonths(r, MonthNow()) end
	return true
end

-- At login: the saved data checked (Prune), the saved word looked at again (RestoreGlobal),
-- and the publisher's own last word repeated once he is back online (the same body and expiry),
-- unless a newer one replaced it. On LOGIN (PLAYER_LOGIN), not INIT (ADDON_LOADED): only then
-- does the client know the character's name (ns.me), and so whether the word is his, and its
-- faction's store (ns.CheckFaction). 1.2.3: this client's own rows the channel did not take go
-- again SHARE_RESEND_FIRST after login, then every SHARE_RESEND_EVERY.
function Wanted.Load()
	-- Create the ordinary empty realm store at login, but fail closed without touching a store
	-- written by a newer scoring version.
	if not Store(true) or not Wanted.Prune() then return false end
	local p = type(ns.db) == "table" and type(ns.db.wantedPublisher) == "table" and ns.db.wantedPublisher.last or nil
	if not publishedGlobal and type(p) == "table" and type(p.body) == "string" and Whole(p.expires, 0, 4294967295)
		and p.body:find("^WY~" .. Wanted.SCORE_VERSION .. "~")
		and not p.replaced and p.expires >= math.floor(Clock()) and SameName(p.issuer, ns.me) and p.scope == Scope() then
		local held = { body = p.body, expires = p.expires, issuer = p.issuer, scope = p.scope }
		publishedGlobal = held
		if ns.After then
			ns.After(Wanted.GLOBAL_LOGIN_REPEAT, "wanted global login", function()
				if publishedGlobal ~= held or held.replaced then return end
				Wanted.RepeatGlobal()
				ScheduleGlobalRepeat(held, Wanted.GLOBAL_BURST)
			end)
		end
	end
	-- Once the publisher's own word is known: a newer saved word, checked again, replaces it.
	RestoreGlobal()
	Wanted.globalCatch.generation = Wanted.globalCatch.generation + 1
	Wanted.ScheduleGlobalCatchUp(Wanted.globalCatch.generation, 1)
	-- Sightings: a reviewer's lease REVIEWER_FIRST after login (his name is known now), then on
	-- its beat; the pins expire on theirs.
	leaseGen = leaseGen + 1
	ScheduleLease(leaseGen, Wanted.REVIEWER_FIRST)
	Share.resendGen = (Share.resendGen or 0) + 1
	Share.ScheduleResend(Share.resendGen, Wanted.SHARE_RESEND_FIRST)
	-- 1.2.3: the earlier deaths (this session's death recaps), read EARLIER_WAIT after login.
	Bounty.Login()
	if ns.Every and not pinTicker then
		pinTicker = true
		ns.Every(Wanted.SIGHT_TICK, "wanted pins", Wanted.RefreshPins)
	end
	return true
end

function Wanted.Stats() return stats end
-- (Tests: this session's shared-row state, as /oly wanted status reads it.)
function Wanted.ShareState() return Share end
function Wanted.ResetForTests()
	deathSerial = deathSerial + 1
	knownHorde = {}
	rate, mode, opened = {}, "list", nil
	Wanted.rulesReturn = nil
	Wanted.listShown = { wanted = Wanted.LIST_FIRST, month = Wanted.LIST_FIRST, all = Wanted.LIST_FIRST }
	authenticatedGlobal, globalFloor, publisherHeads = nil, nil, {}
	pendingGlobal, pendingGlobalCount = {}, 0
	publishedGlobal = nil
	scoreMigrationFrame = nil
	Wanted.globalCatch.asked, Wanted.globalCatch.replied = -math.huge, -math.huge
	Wanted.globalCatch.generation = Wanted.globalCatch.generation + 1
	restoring, restoreChecked = nil, {}
	pins, pinFrames, spareFrames, historyFocus = {}, {}, {}, nil
	Sight.historyFrames, Sight.historySpare = {}, {}
	sightSeen, sightSeenOrder, ownSeen, ownSeenCount, sightSends = {}, {}, {}, 0, {}
	sightJobs, sightJobCount, sightFrom, sightFromCount, sightIntake = {}, 0, {}, 0, { at = 0, n = 0 }
	told.by, told.quiet = {}, {}
	reviewers, reviewerCount, leaseGen, leaseAt = {}, 0, leaseGen + 1, nil
	for key in pairs(stats) do stats[key] = 0 end
	Share.rates, Share.days, Share.targets, Share.relayed, Share.relayedOrder = {}, {}, {}, {}, {}
	Share.log, Share.why, Share.counts, Share.deathRow = {}, {}, {}, nil
	Share.catchReplied, Share.catchHeard = -math.huge, -math.huge
	Share.resendGen = (Share.resendGen or 0) + 1
	Bounty.session = { gen = (Bounty.session.gen or 0) + 1 }
end

if Wanted.Rules then
	Wanted.Rules.Register("wanted-slayers", {
		title = function() return L.RANK_RULE_WANTED_TITLE end,
		icon = Wanted.Icon,
		allowed = Wanted.RulesAllowed,
		sections = function()
			return {
				{ topic = "score", text = {
					L.RANK_RULE_WANTED_BOUNTY:format(Bounty.SCORE.BOUNTY_MAX,
						math.floor(Bounty.SCORE.REPEAT_GAP / 60)),
					L.RANK_RULE_WANTED_SLAYER:format(Bounty.SCORE.KILL_LEVEL_STEP,
						Bounty.SCORE.REVENGE, Bounty.SCORE.GRUDGE_DAYS),
				} },
				{ topic = "limits", text = L.RANK_RULE_WANTED_LIMITS:format(
					math.floor(Bounty.SCORE.KILL_GAP / 60), math.floor(Bounty.SCORE.REVENGE_GAP / 3600)) },
				{ topic = "order", text = L.RANK_RULE_WANTED_ORDER },
				{ topic = "evidence", text = L.RANK_RULE_WANTED_EVIDENCE },
				{ topic = "visibility", text = L.RANK_RULE_WANTED_VISIBILITY },
			}
		end,
	})
end

if ns.UI and ns.UI.AddTab then
	ns.UI.AddTab({ key = "wanted", label = "TAB_WANTED", after = "realm",
		icon = Wanted.Icon, visible = function() return ns.IsMember and ns.IsMember() end, build = Wanted.Build,
		onLeave = Wanted.CollapseLists, buttons = buttons })
end

-- Never COMBAT_LOG_EVENT_UNFILTERED: on Forever it is a restricted event (HasRestrictions in the
-- client's CombatLog API documentation), and an addon's RegisterEvent on it is blocked with the
-- game's "blocked from an action" pop-up at every login (Daniel's test build, taint.log:
-- Frame:RegisterEvent() from this line). The native PARTY_KILL (our own killing blow) and the
-- player's own death recap (PLAYER_DEAD) are what the client allows.
-- Unsupported/restricted registration must not abort login; this is not the restricted CLEU.
-- (Whether it registered: /oly wanted status says so.)
Share.partyKill = pcall(ns.RegisterEvent, "PARTY_KILL", Wanted.CapturePartyKill)
ns.RegisterEvent("PLAYER_DEAD", function()
	deathSerial = deathSerial + 1
	local serial = deathSerial
	local captured, why, who = ReadSelfDeathRecap()
	Share.NoteDeath(serial, captured, why, who)
	-- The native recap may arrive after PLAYER_DEAD. Bounded retries belong to this death
	-- alone, and the native timestamp/identity/fatal checks still run on every attempt.
	if not captured and ns.After and C_DeathRecap and type(C_DeathRecap.HasRecapEvents) == "function" then
		for _, delay in ipairs({ 0.3, 1, 2 }) do
			ns.After(delay, "wanted death recap", function()
				if not captured and serial == deathSerial then
					captured, why, who = ReadSelfDeathRecap()
					Share.NoteDeath(serial, captured, why, who)
				end
			end)
		end
	end
end)
ns.On("LOGIN", Wanted.Load)
-- An expiry or a lost role clears the word shown; a role that came back (the council's list),
-- or another realm group's store, may bring a saved one back.
-- A reviewer whose role came (the council's list) says at once that he takes sightings.
ns.On("DATA_CHANGED", function()
	CurrentGlobal()
	if not authenticatedGlobal then RestoreGlobal() end
	if LeaseDue() then Wanted.AnnounceReviewer() end
end)
-- A newly applied location bar must remove both fresh and historical pins at once, and the open
-- Wanted page must stop showing its location rows without waiting for the pin ticker.
ns.On("WATCHCHAT_CHANGED", function() Wanted.RefreshPins(true) end)
-- The King hid his crown: what waits for a reviewer is cancelled, what went is taken back.
ns.On("KING_LOCATION_CHANGED", function()
	if Sight.CrownHidden() and (sightJobCount > 0 or next(told.by) ~= nil) then
		CancelSightings("crown")
		Sight.Withdraw()
	end
end)
ns.On("LAYER_SHARING_CHANGED", function(on)
	if on ~= true and (sightJobCount > 0 or next(told.by) ~= nil) then
		CancelSightings("private")
		Sight.Withdraw()
	end
end)
-- What this client sees: the nameplates, its target, the unit under the mouse (sightings); the
-- pins follow it in and out of instances.
ns.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(unit) Wanted.ObserveUnit(unit) end)
ns.RegisterEvent("PLAYER_TARGET_CHANGED", function() Wanted.ObserveUnit("target") end)
ns.RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() Wanted.ObserveUnit("mouseover") end)
-- (1.2.3: and the bounty's: this client's own times in an instance, what waited for the outside.)
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function() Wanted.RefreshPins() Bounty.Zone() end)
ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function() Wanted.RefreshPins() Bounty.Zone() end)
-- (1.2.4: the notices that waited out a fight, at once when it ends: Bounty.Notices. A death's end
-- is caught by their beat, NOTICE_TICK: Forever's UI source lists no event of its own for it.)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() if Bounty.Waiting() then Bounty.NoticesSoon() end end)
-- (1.2.3: no WX handler, 1.2.2's evidence whispered for a review: there is none any more, and a
-- member of 1.2.2 who still sends one is heard by nobody.)
if ns.Comm and ns.Comm.Handle then
	ns.Comm.Handle("WK", function(...) return Wanted.HandleShared(...) end)
	ns.Comm.Handle("WV", function(...) return Wanted.HandleMark(...) end)
	ns.Comm.Handle("WY", function(...) Wanted.HandleGlobalSnapshot(...) end)
	-- A late login's ask: the signed word, and (a reviewer's) the recent shared rows.
	ns.Comm.Handle("W4", function(...) Wanted.AnswerGlobal(...) Share.Answer(...) end)
	ns.Comm.Handle("W5", function(...) Wanted.HandleGlobalRelay(...) end)
	ns.Comm.Handle("WS", function(...) Wanted.HandleSighting(...) end)
	-- (1.2.4 repair: a member's avenged ask, answered with the matching kills' rows: Bounty.Answer.)
	ns.Comm.Handle("W7", function(...) return Bounty.Answer(...) end)
end
