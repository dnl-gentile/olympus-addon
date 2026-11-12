local ADDON, ns = ...
local L = ns.L

-- Guild verification (the launch's rule, from the moderators' spec): a guild is part of Olympus's
-- features once its guild master is verified. He whispers a verifier, who approves the guild and
-- him together; nothing else verifies a guild, and being verified grants nobody a role.
--
-- Who approves: a verifier, by the server-stamped sender of the word, as this client knows them
-- now (Verify.Trusted): the pinned King, a High Councillor of the author's signed list, or the
-- addon's author; never one the net-off list hides. A guild master gets no power from this, and a
-- pending guild (or a verified one) no council status, role or authority beyond its own master's.
--
-- What it belongs to: the guild AND its guild master. While the census (our own roster for our
-- guild) names someone else as its guild master, the approval lapses: a fresh check of the new
-- guild master, on the guild's same clock. The old one leading it again, it stands again.
--
-- The clock: GRACE (7 days; 48 hours before 1.5.4) from the guild's start, the same on every client.
-- A verifier's client records the first time it saw the guild (its census, or its own guild) and
-- relays it with the approvals; every client keeps the earliest start any verifier's client gave
-- (ns.rdb.verify.start, the earliest wins), so a reinstall, a rejoin or a new guild master never
-- restarts it. Until a verifier's start reaches it, a client counts from its own first sighting
-- (ns.rdb.verify.seen). (1.5.4, the dev's ask: every guild's verification period starts again,
-- with 7 days of grace.) No deadline counts from before RESET_AT, the release night: a guild started
-- before it has GRACE from RESET_AT, alike on every 1.5.4 client, and a client whose clock is before
-- it finds nothing overdue. Only the deadline moves (Verify.Status): the starts are kept and relayed
-- as they were, so the GV rows stay what a 1.5.3 client reads and the earliest still wins (a 1.5.3
-- client counts its 48 hours from them until it updates).
-- Within GRACE the guild is pending: only its guild master sees "GM verification pending" (once a
-- session, reopened with /oly verify or the line on top of the Census). Past it the guild is
-- overdue: member-facing notices are temporarily paused; the guild master still sees the
-- reminder and the verifiers keep the guild on their list, marked overdue,
-- for follow-up; and while ns.VERIFY_HOLD is on (Core.lua, as it ships) its guild master's own
-- powers wait for his verification (ns.MasterHeld: Data.AuthorizedRank gives him an officer's
-- standing; his public card, his Legates and correspondents, his guild decrees and his guild bank
-- grant wait too). Nothing is taken from the members; nobody is removed.
--
-- (1.5.5, the dev: "Postpone the hold on PvP") All of this runs only in a realm group where someone can
-- verify: our side's King or a councillor of the signed list, the author's characters left out
-- (Verify.VerifierHere). Elsewhere (ForeverPvP today) every guild waits, pending: no deadline, no notice to
-- its guild master, no hold. The signed list that brings the first verifier there starts it with a fresh
-- GRACE from the moment it arrives (Verify.ListTaken, Verify.HoldFrom).
--
-- The verifiers (the King, the High Council, the author) see the pending and overdue guilds in The
-- Watch (Guilds), are told once of each new pending guild (and of each new guild master to check),
-- and once more REMIND_LEFT before its deadline (and before a later deadline again, as the 1.5.4
-- reset made every one), to tell a guild master who has no addon to install it and verify.
--
-- Exemptions live in one predicate, Verify.Exempt. Nothing of the whole guild is gated:
-- ns.VERIFY_GATE (Core.lua) is off, and ns.GuildSanctioned(guild), the one predicate a feature
-- would ask, says yes while it is.
--
-- How it travels (GV, Comm.lua's list), on the Olympus channel:
--   GV~1~A~<server time>~<Guild>~<Guild master Name-Realm>   a verifier's approval (logged)
--   GV~1~R~<server time>~<Guild>~<Guild master Name-Realm>   a verifier's revocation (logged)
--   GV~1~Q~<count>~<newest>~<starts>~<digest>                 any member's ask (after login, then
--                                                             every half hour): what it holds
--   GV~1~S~<made>~<row>;<row>;...                             a verifier's client's answer, rows
--     A|R,<at>,<Guild>,<master>,<by>   every word it holds, the newest first
--     T,<at>,<Guild>,<by>              then the guilds' starts (the unverified first)
-- A single approval with a final semicolon is an explicit Watch resend. Older clients read the
-- same snapshot row; relays that know the marker can send it to the named guild's reporter.
--   GV~1~M~<id>~<faction>~<Guild>                  private request to one known reporter
--   GV~1~N~<id>~<faction>~<Guild>~<Guild master>   private reply after a complete native roster scan
--                                      in MAX_ROWS rows and MAX_BYTES at most (names without a realm
--                                      are the sender's realm's)
-- Each client keeps, per guild, the newest word by its time (the approver's server time, which a
-- relay carries unchanged: an old approval relayed is as old as it was). On the same second a
-- revocation stands over an approval. A relay is taken only from a verifier's client, which only
-- answers an ask from a client with different contents. Kept in the realm group's saved data: approvals
-- until revoked (MAX words at most), revocations REVOKE_KEEP, starts START_KEEP and first sightings
-- SEEN_KEEP after the guild was last seen.

local Verify = {}
ns.Verify = Verify

Verify.PROTOCOL = 1
Verify.GRACE = 7 * 86400         -- a guild's grace, from its start (1.5.4: 7 days, where it was 48 hours)
Verify.RESET_AT = 1794193200     -- (1.5.4) no deadline counts from before: 2026-11-09 00:00 BRT (03:00 UTC), the release night
Verify.REMIND_LEFT = 12 * 3600   -- the verifiers are reminded of a pending guild this long before its deadline
Verify.NOTICE_AFTER = 90         -- the session's notices wait this long after login (roster and census in)
Verify.TICK = 60                 -- the guilds seen and the notices, every minute
Verify.ASK_AFTER, Verify.ASK_SPREAD = 25, 35 -- the login's ask, 25 to 60 s after it
Verify.STARTUP_RETRY, Verify.STARTUP_SPREAD = 315, 45 -- past the relay's identical-word window
Verify.ASK_EVERY = 30 * 60       -- and every half hour
Verify.ANSWER_GAP = 180          -- a verifier's client answers asks this often at most
Verify.RELAY_ANSWER_GAP = 900    -- (1.5.4) and each relay that asked (relays first agree among themselves) this often
Verify.ANSWER_RETRIES, Verify.ANSWER_RETRY_EVERY = 6, 5 -- (1.5.4) a relay's answer its full queue refused, tried again
Verify.REQUEST_GAP = 300         -- a guild master's queued request, kept across reloads
Verify.RESEND_GAP = 15           -- a verifier can resend one existing decision at a time
Verify.POLL_GAP = 30             -- at most one roster poll per client in this interval
Verify.POLL_WAIT = 20            -- private replies only count for this long
Verify.REVOKE_KEEP = 30 * 86400  -- a revocation is kept (and relayed) this long
Verify.START_KEEP = 90 * 86400   -- a guild's start, this long after it was last seen or heard
Verify.SEEN_KEEP = 30 * 86400    -- a guild's own first sighting, this long after it was last seen
Verify.MAX = 400                 -- words kept (past it: the oldest revocations, then the oldest approvals)
Verify.MAX_STARTS = 600          -- starts kept, and first sightings (past it: the longest unseen go)
Verify.MAX_ROWS = 240            -- rows in one answer
-- (1.5.4: room left for the relay's envelope, "RM~P~<verifier>~", around a direct answer.)
Verify.MAX_BYTES = ns.Codec.CHUNK * ns.Codec.MAX_CHUNKS - 96
Verify.EPOCH = 1767225600        -- 2026-01-01: no word or start is older
Verify.AHEAD = 300               -- a time further ahead of the server's clock is not taken
Verify.SHOWN_MAX = 5             -- guilds named in one notice line to the verifiers
Verify.MARK_OK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t "
Verify.MARK_LATE = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12|t "

Verify.random = math.random -- (tests)
-- The server's clock (the same second on every client): every time this file keeps or sends.
function Verify.Clock()
	local t = ns.Data and ns.Data.ServerTime and ns.Data.ServerTime()
	return math.floor(tonumber(t) or ns.Now())
end

local stats = { taken = 0, starts = 0, refused = 0, bad = 0, asked = 0, answered = 0, unsent = 0 }
local snapshots, startup = 0, nil
function Verify.Stats() return stats end -- (unsent: answers refused a send, the review of the 1.5.4 candidate)

local function Key(s) return ns.Fold(tostring(s or "")) end
local function Grey(s) return "|cff9d9d9d" .. tostring(s or "") .. "|r" end
local function Gold(s) return "|cffffd200" .. tostring(s or "") .. "|r" end
local function Red(s) return "|cffff6060" .. tostring(s or "") .. "|r" end
local function Quiet() return ns.QuietPresence ~= nil and ns.QuietPresence() == true end
local function Shown(name) return type(name) == "string" and (ns.DisplayName(name) or name) or "?" end

local function Store()
	local rdb = ns.rdb
	if type(rdb) ~= "table" then return nil end
	local s = rdb.verify
	if type(s) ~= "table" then
		s = {}
		rdb.verify = s
	end
	for _, k in ipairs({ "list", "start", "seen", "told", "requests" }) do
		if type(s[k]) ~= "table" then s[k] = {} end
	end
	return s
end

local heldMemo, heldAt = {}, nil -- ns.MasterHeld's answers this second (cleared at every change)
local function Changed()
	heldMemo = {}
	ns.Fire("VERIFY_CHANGED")
	if ns.UI and type(ns.UI.Refresh) == "function" then ns.UI.Refresh() end
end

---------------------------------------------------------------------------
-- Fields, people, guilds
---------------------------------------------------------------------------

local function GuildField(s)
	if type(s) ~= "string" or s == "" or #s > 72 or s:find("[~;,|%c]") then return nil end
	if not ns.IsFederation(s) then return nil end
	return s
end
local function NameField(s, realm)
	if type(s) ~= "string" or s == "" or #s > 64 or s:find("[~;,|%c]") then return nil end
	return ns.FullName(s, realm)
end
local function TimeField(v)
	local n = tonumber(v)
	if not n or n ~= math.floor(n) or n < Verify.EPOCH or n > Verify.Clock() + Verify.AHEAD then return nil end
	return n
end

-- The same person: the same name, on the same realm group (Forever's names are one per group).
local function SamePerson(a, b)
	if type(a) ~= "string" or type(b) ~= "string" then return false end
	a, b = ns.FullName(a), ns.FullName(b)
	if Key(ns.ShortName(a)) ~= Key(ns.ShortName(b)) then return false end
	return ns.GroupOf(ns.RealmOf(a) or ns.realm) == ns.GroupOf(ns.RealmOf(b) or ns.realm)
end
Verify.SamePerson = SamePerson

-- A verifier: the pinned King, a High Councillor of the signed list, the addon's author; never a
-- name the net-off list hides. Nothing in this file makes anyone one.
function Verify.Trusted(name)
	if type(name) ~= "string" or name == "" then return false end
	local M = ns.Moderation
	if type(M) == "table" and type(M.Hidden) == "function" and M.Hidden(name) ~= nil then return false end
	if ns.IsKingCharacter(name) or ns.IsHighCouncillor(name) then return true end
	local W = ns.Workshop
	return type(W) == "table" and type(W.IsAuthorName) == "function" and W.IsAuthorName(name) == true
end

-- The guilds that need no verification, in this one place: the King's guild. The guilds the
-- author's signed list approves are not exempt (their guild masters verify too); to exempt them,
-- add `or ns.IsApprovedGuild(guild)` here.
function Verify.Exempt(guild)
	return ns.IsKingGuild(guild) == true
end

-- (1.5.5, the dev: "Postpone the hold on PvP") Someone of this realm group who can verify (Verify.Trusted):
-- our side's King (the signed list's; the code's on the beta's group) or a councillor of the signed list we
-- hold. The author's own characters never count here. Where nobody is, no deadline runs (Verify.Status):
-- every guild waits, pending, its guild master is told nothing and held in nothing. Kept a second.
local verifierMemo, verifierAt = nil, nil
-- The signed council's names we hold (Workshop.CouncilNames: the list ns.IsHighCouncillor reads).
local function CouncilNames()
	local W = ns.Workshop
	if type(W) ~= "table" or W.missing or type(W.CouncilNames) ~= "function" then return {} end
	return W.CouncilNames()
end
function Verify.VerifierHere(now)
	now = now or Verify.Clock()
	if verifierAt == now then return verifierMemo end
	local function Counts(name)
		if type(name) ~= "string" or name == "" then return false end
		local full = ns.FullName(name)
		return not ns.IsAuthorName(full) and Verify.Trusted(full)
	end
	local found = Counts((ns.KingFullName()))
	if not found then
		for _, name in ipairs(CouncilNames()) do
			if Counts(name) then found = true break end
		end
	end
	verifierMemo, verifierAt = found, now
	return found
end

-- The hold's fresh grace (1.5.5): Workshop.TakeCouncil and TakeTitles ask Verify.ListState right before they
-- keep a newer signed list (nil: none held here yet; else whether it names a verifier here) and tell
-- Verify.ListTaken right after. A list held that named none, then one that names the first verifier: from
-- that moment (rdb.verify.holdFrom, Verify.HoldFrom) every deadline here counts at the earliest, GRACE (7
-- days) for every guild. A realm group that had its verifiers from the start (the beta, ForeverPvE) keeps
-- its deadlines as they were; a client that held no list at all keeps them too (its own first sighting
-- gives each guild its grace, Verify.Start).
function Verify.ListState()
	if ns.CouncilTitles() == nil and #CouncilNames() == 0 then return nil end
	verifierAt = nil
	return Verify.VerifierHere()
end
function Verify.ListTaken(before)
	verifierAt = nil
	if before ~= false or not Verify.VerifierHere() then return false end
	local s = Store()
	if not s then return false end
	s.holdFrom = Verify.Clock()
	Changed()
	ns.Log("guild verification: a verifier here now; deadlines count from %d at the earliest", s.holdFrom)
	return true
end
function Verify.HoldFrom()
	local s = Store()
	return s and tonumber(s.holdFrom) or nil
end

-- A guild's census row, by its name in any case.
local function Row(guild)
	local guilds = ns.rdb and ns.rdb.guilds
	if type(guilds) ~= "table" or type(guild) ~= "string" then return nil end
	local g = guilds[guild]
	if type(g) == "table" then return g end
	local key = Key(guild)
	for name, row in pairs(guilds) do
		if type(row) == "table" and type(name) == "string" and Key(name) == key then return row end
	end
	return nil
end

-- A guild's guild master now, "Name-Realm": ourselves when we lead our guild (the game's rank), else
-- the census's (our own roster's report for our guild); nil while unknown.
function Verify.GuildMaster(guild)
	if type(guild) ~= "string" or guild == "" then return nil end
	local mine, _, rank = GetGuildInfo("player")
	if type(mine) == "string" and Key(mine) == Key(guild) and rank == 0 and type(ns.me) == "string" then return ns.FullName(ns.me) end
	local g = Row(guild)
	local leader = type(g) == "table" and g.leader or nil
	if type(leader) ~= "string" or leader == "" or leader == "?" then return nil end
	return ns.FullName(leader, g.realm or ns.realm)
end

---------------------------------------------------------------------------
-- A guild's state
---------------------------------------------------------------------------

local function Valid(e)
	return type(e) == "table" and (e.k == "A" or e.k == "R") and type(e.at) == "number" and e.at >= Verify.EPOCH
		and type(e.guild) == "string" and ns.IsFederation(e.guild) and type(e.gm) == "string" and type(e.by) == "string"
end
local function ValidStart(e)
	return type(e) == "table" and type(e.at) == "number" and e.at >= Verify.EPOCH and type(e.guild) == "string"
end

-- The guild's start: the earliest a verifier's client gave (shared), else this client's own first
-- sighting; and whether it is the shared one.
function Verify.Start(guild, now)
	local s = Store()
	local key = Key(guild)
	local e = s and s.start[key]
	if ValidStart(e) then return e.at, true end
	local seen = s and s.seen[key]
	if type(seen) == "table" and type(seen.at) == "number" then return seen.at, false end
	return now or Verify.Clock(), false
end

-- "exempt", "verified", "pending" or "overdue" (nil: no Olympus guild), with
-- { guild, gm (now, or nil), entry (its approval), lapsed (approved with another guild master),
--   revoked, since (its start), shared (a verifier's start), deadline (GRACE after its start, or
--   after RESET_AT for one started before it), left (seconds before its deadline) }.
function Verify.Status(guild, now)
	if type(guild) ~= "string" or guild == "" or not ns.IsFederation(guild) then return nil end
	now = now or Verify.Clock()
	local info = { guild = guild, gm = Verify.GuildMaster(guild) }
	if Verify.Exempt(guild) then return "exempt", info end
	local s = Store()
	local e = s and s.list[Key(guild)]
	if Valid(e) and e.k == "A" then
		info.entry = e
		if not info.gm or SamePerson(info.gm, e.gm) then return "verified", info end
		info.lapsed = true
	elseif Valid(e) then
		info.revoked = e
	end
	local since, shared = Verify.Start(guild, now)
	if since > now then since = now end
	info.since, info.shared = since, shared
	-- (1.5.5) Nobody here who can verify (Verify.VerifierHere): no deadline runs, the guild waits.
	if not Verify.VerifierHere(now) then
		info.waiting, info.deadline, info.left = true, now + Verify.GRACE, Verify.GRACE
		return "pending", info
	end
	-- (1.5.4) The deadline alone counts from RESET_AT at the earliest (see the top): since stays the
	-- guild's start, as it is kept and relayed. (1.5.5) And from the first verifier's arrival here, when
	-- one came after the rest (Verify.HoldFrom).
	info.deadline = math.max(since, Verify.RESET_AT, Verify.HoldFrom() or Verify.RESET_AT) + Verify.GRACE
	info.left = info.deadline - now
	if info.left > 0 then return "pending", info end
	return "overdue", info
end

-- The one predicate a feature asks before it would leave a whole guild out. With the gate off
-- (ns.VERIFY_GATE, Core.lua, as it ships) every guild is sanctioned.
function ns.GuildSanctioned(guild)
	if ns.VERIFY_GATE ~= true then return true end
	return Verify.Status(guild) ~= "overdue"
end

-- Whether an overdue guild's master's own powers wait (ns.VERIFY_HOLD, Core.lua): Data.AuthorizedRank,
-- GuildCharter, Nominees, Decree and Bank ask it. Never the King's guild, nor (1.5.5) where nobody can
-- verify (Verify.Status: no guild is overdue there). Asked often: kept a second.
function ns.MasterHeld(guild)
	if ns.VERIFY_HOLD ~= true or type(guild) ~= "string" or guild == "" then return false end
	local now = Verify.Clock()
	if heldAt ~= now then heldMemo, heldAt = {}, now end
	local v = heldMemo[guild]
	if v == nil then
		v = Verify.Status(guild, now) == "overdue"
		heldMemo[guild] = v
	end
	return v
end

-- The guilds this client sees (the census, our own): its own first sighting of each, and on a
-- verifier's client the guild's start. How many were new.
function Verify.Observe(now)
	now = now or Verify.Clock()
	local s = Store()
	if not s then return 0 end
	local trusted = Verify.Trusted(ns.me)
	local n = 0
	local function See(guild)
		if type(guild) ~= "string" or guild == "" or not ns.IsFederation(guild) then return end
		local key = Key(guild)
		local e = s.seen[key]
		if type(e) ~= "table" or type(e.at) ~= "number" then
			s.seen[key] = { at = now, last = now }
			n = n + 1
		else
			e.last = now
		end
		local st = s.start[key]
		if ValidStart(st) then
			st.last = now
		elseif trusted then
			s.start[key] = { at = now, guild = guild, by = ns.FullName(ns.me), last = now }
		end
	end
	for name in pairs(ns.rdb.guilds or {}) do See(name) end
	if IsInGuild() then See((GetGuildInfo("player"))) end
	if n > 0 then heldMemo = {} end
	return n
end

local function Trim(t, max, keep)
	local list = {}
	for key, e in pairs(t) do list[#list + 1] = { key = key, last = keep(e) } end
	if #list <= max then return end
	table.sort(list, function(a, b)
		if a.last ~= b.last then return a.last < b.last end
		return a.key < b.key
	end)
	for i = 1, #list - max do t[list[i].key] = nil end
end

function Verify.Prune(now)
	now = now or Verify.Clock()
	local s = Store()
	if not s then return end
	local kept = {}
	for key, e in pairs(s.list) do
		if not Valid(e) or (e.k == "R" and now - e.at > Verify.REVOKE_KEEP) then
			s.list[key] = nil
		else
			kept[#kept + 1] = { key = key, e = e }
		end
	end
	if #kept > Verify.MAX then
		table.sort(kept, function(a, b)
			if (a.e.k == "R") ~= (b.e.k == "R") then return a.e.k == "R" end
			if a.e.at ~= b.e.at then return a.e.at < b.e.at end
			return a.key < b.key
		end)
		for i = 1, #kept - Verify.MAX do s.list[kept[i].key] = nil end
	end
	local function Last(e) return type(e) == "table" and (tonumber(e.last) or tonumber(e.at)) or nil end
	for key, e in pairs(s.start) do
		local last = Last(e)
		if not ValidStart(e) or not last or now - last > Verify.START_KEEP then s.start[key] = nil end
	end
	for key, e in pairs(s.seen) do
		local last = Last(e)
		if type(e) ~= "table" or type(e.at) ~= "number" or not last or now - last > Verify.SEEN_KEEP then s.seen[key] = nil end
	end
	for key, e in pairs(s.told) do
		local last = Last(e)
		if not last or now - last > Verify.SEEN_KEEP then s.told[key] = nil end
	end
	Trim(s.start, Verify.MAX_STARTS, Last)
	Trim(s.seen, Verify.MAX_STARTS, Last)
	Trim(s.told, Verify.MAX_STARTS, Last)
	for key, e in pairs(s.requests) do
		local at = type(e) == "table" and TimeField(e.at)
		if not at or now - at > Verify.SEEN_KEEP then s.requests[key] = nil end
	end
	Trim(s.requests, Verify.MAX_STARTS, Last)
end

---------------------------------------------------------------------------
-- The words and the starts
---------------------------------------------------------------------------

-- Keeps a word when it is newer than the guild's (see the top). True when kept.
local function Take(kind, at, guild, gm, by, now)
	local s = Store()
	if not s then return false, "store" end
	local key = Key(guild)
	local old = s.list[key]
	if Valid(old) then
		if at < old.at then return false, "older" end
		if at == old.at then
			if old.k == kind and SamePerson(old.gm, gm) then return false, "same" end
			-- One second, two words: every client keeps the same one. A revocation stands over an
			-- approval; between two of a kind, the guild master's name first in order.
			if old.k == "R" and kind == "A" then return false, "older" end
			if old.k == kind and Key(old.gm) <= Key(gm) then return false, "older" end
		end
	end
	s.list[key] = { k = kind, at = at, guild = guild, gm = gm, by = by, heard = now }
	stats.taken = stats.taken + 1
	return true
end

-- Keeps a guild's start when it is earlier than the one held (the earliest wins). True when kept.
local function TakeStart(guild, at, by, now)
	local s = Store()
	if not s then return false end
	local key = Key(guild)
	local old = s.start[key]
	if ValidStart(old) then
		old.last = now
		if old.at <= at then return false end
	end
	s.start[key] = { at = at, guild = guild, by = by, last = now }
	stats.starts = stats.starts + 1
	return true
end

-- Our own guild's members hear a verifier's word on it as it comes (never a relay's).
local function TellOurs(kind, guild, by)
	local mine = IsInGuild() and GetGuildInfo("player")
	if type(mine) ~= "string" or Key(mine) ~= Key(guild) then return end
	ns.Print((kind == "A" and L.VERIFY_HEARD_OURS or L.VERIFY_HEARD_REVOKED):format(guild, Shown(by)))
end

-- Counts alone cannot distinguish two different sets of approvals made on the same second.
-- The optional content digest excludes receipt times; it is a convergence hint, never proof
-- of authority. Older clients still understand the first three fields.
function Verify.Digest()
	local n, newest, sum = 0, 0, 0
	local s = Store()
	local rows = {}
	for _, e in pairs(s and s.list or {}) do
		if Valid(e) then
			n = n + 1
			if e.at > newest then newest = e.at end
			rows[#rows + 1] = table.concat({ e.k, e.at, Key(e.guild), Key(ns.FullName(e.gm)), Key(ns.FullName(e.by)) }, "|")
		end
	end
	for _, e in pairs(s and s.start or {}) do
		if ValidStart(e) then
			n, sum = n + 1, (sum + e.at) % 2147483648
			rows[#rows + 1] = table.concat({ "T", e.at, Key(e.guild) }, "|")
		end
	end
	table.sort(rows)
	local hash = ns.Sign and ns.Sign.SHA256 and ns.Sign.SHA256(table.concat(rows, "\n"))
	if type(hash) == "string" then hash = hash:gsub(".", function(c) return ("%02x"):format(c:byte()) end) end
	return n, newest, sum, hash
end

-- A name as a relay writes it: without the realm when it is ours (the receiver puts the sender's back).
local function Relative(name)
	local realm = ns.RealmOf(name)
	if realm and realm == ns.realm then return ns.ShortName(name) end
	return name
end

-- Exact decision evidence; a start's earliest time is independent of who forwarded it.
-- Receipt times and snapshot creation times never establish coverage.
local function CoverageKey(kind, at, guild, gm, by)
	local fields = { kind, at, Key(guild) }
	if kind ~= "T" then
		fields[#fields + 1] = Key(ns.FullName(gm))
		fields[#fields + 1] = Key(ns.FullName(by))
	end
	return table.concat(fields, "|")
end

-- A verifier's client's answer: every word it holds, the newest first, then the starts (the
-- unverified guilds' first, the oldest first), bounded. And how many rows; with coverage supplied,
-- whether that received snapshot contains every row this answer would actually send.
function Verify.Payload(now, coverage)
	now = now or Verify.Clock()
	local s = Store()
	local words, starts = {}, {}
	for _, e in pairs(s and s.list or {}) do
		if Valid(e) then words[#words + 1] = e end
	end
	table.sort(words, function(a, b)
		if a.at ~= b.at then return a.at > b.at end
		return Key(a.guild) < Key(b.guild)
	end)
	for _, e in pairs(s and s.start or {}) do
		if ValidStart(e) and ns.IsFederation(e.guild) then
			starts[#starts + 1] = { e = e, done = Verify.Status(e.guild, now) == "verified" }
		end
	end
	table.sort(starts, function(a, b)
		if a.done ~= b.done then return b.done end
		if a.e.at ~= b.e.at then return a.e.at < b.e.at end
		return Key(a.e.guild) < Key(b.e.guild)
	end)
	local head = ("GV~%d~S~%d~"):format(Verify.PROTOCOL, now)
	local out, bytes, covered = {}, #head, coverage ~= nil
	local function Add(row, key)
		if #out >= Verify.MAX_ROWS then return false end
		local extra = #row + (#out > 0 and 1 or 0)
		if bytes + extra > Verify.MAX_BYTES then return false end
		out[#out + 1], bytes = row, bytes + extra
		if coverage and not coverage[key] then covered = false end
		return true
	end
	for _, e in ipairs(words) do
		if not Add(("%s,%d,%s,%s,%s"):format(e.k, e.at, e.guild, Relative(e.gm), Relative(e.by)),
			coverage and CoverageKey(e.k, e.at, e.guild, e.gm, e.by)) then break end
	end
	for _, x in ipairs(starts) do
		if not Add(("T,%d,%s,%s"):format(x.e.at, x.e.guild, Relative(type(x.e.by) == "string" and x.e.by or ns.FullName(ns.me))),
			coverage and CoverageKey("T", x.e.at, x.e.guild)) then break end
	end
	return head .. table.concat(out, ";"), #out, covered
end

local lastSent, pending = -math.huge, false
local answeredRelay = {} -- (1.5.4) a relay that asked (folded name) -> when we answered it
-- (1.5.4) Where the relay runs (Forever) an answer goes to the one client that asked
-- (Relay.Direct), which hands it to its guild: the whole store to every reporter of the relay
-- never got through its queue. Elsewhere, on the channel as before.
local function Direct()
	local R = ns.Relay
	return type(R) == "table" and type(R.On) == "function" and R.On() == true and type(R.Direct) == "function"
end
function Verify.SendSnapshot(target, toRelay)
	if Quiet() or not ns.IsMember() or not Verify.Trusted(ns.me) then return false end
	local payload, n = Verify.Payload()
	if n == 0 then return false end
	local ok
	if Direct() then
		ok = type(target) == "string" and ns.Relay.Direct(target, payload, "verify answer " .. Key(target)) == true
	else
		local key = "verify-snapshot"
		ok = ns.Comm.SendChunked(payload, false, "CHANNEL", nil, { owner = Verify, key = key,
			permit = function(_, guardKey, dist, target)
				if guardKey ~= key or dist ~= "CHANNEL" or target ~= nil then return false, "lane" end
				if not Verify.Trusted(ns.me) then return false, "trust" end
				return true
			end })
	end
	if ok then
		if not toRelay then lastSent = Verify.Clock() end
		stats.answered = stats.answered + 1
	else
		stats.unsent = stats.unsent + 1
	end
	-- (The review of the 1.5.4 candidate.) A line for /oly bug: the answer, to whom (direct, or the
	-- channel), its size, and a refusal (a full queue: AnswerAsk tries again). Until now an answer
	-- that went direct left no line anywhere, a crossed one none on the asker's relay (Relay.lua).
	ns.Log("verify: answer (%d rows) to %s%s", n, Direct() and tostring(target) or "the channel", ok and "" or ": refused")
	return ok
end

-- An ask heard: a verifier's client with different contents answers after 2-9 s, unless another
-- verifier delivered every row we would send. A smaller answer must not silence missing decisions.
-- (1.5.4) A relay that asked is answered on its own gap (RELAY_ANSWER_GAP each), whatever the
-- clients' asks: the relays agree among themselves first, then each answers its own clients.
-- (The review of the 1.5.4 candidate.) A relay's ask is one that came across from that relay itself,
-- its name stamped by the server (Relay.AskedAcross). Any other ask naming a relay as its origin
-- (a guildmate's RG, a relay's RM or RX carry the origin as a word) is a client's: the one
-- pending/ANSWER_GAP bound, never a gap per relay it names.
local function AnswerAsk(body, now, sender)
	if Quiet() or not ns.IsMember() or not Verify.Trusted(ns.me) then return true end
	local R = ns.Relay
	local toRelay = Direct() and type(sender) == "string" and R.IsRelay(sender) == true
		and type(R.AskedAcross) == "function" and R.AskedAcross(sender) == true
	if toRelay then
		if now - (answeredRelay[Key(sender)] or -math.huge) < Verify.RELAY_ANSWER_GAP then return true end
	elseif pending or now - lastSent < Verify.ANSWER_GAP then return true end
	local mine, _, _, fingerprint = Verify.Digest()
	if mine == 0 then return true end
	local n, theirs, theirSum, theirFingerprint = tostring(body or ""):match("^(%d+)~(%d+)~(%d+)~(%x+)$")
	if not n then n, theirs, theirSum = tostring(body or ""):match("^(%d+)~(%d+)~(%d+)$") end
	n, theirs, theirSum = tonumber(n), tonumber(theirs), tonumber(theirSum)
	if not n or n > Verify.MAX + Verify.MAX_STARTS or theirs > now + Verify.AHEAD
		or theirSum >= 2147483648 or (theirFingerprint and #theirFingerprint ~= 64) then return false end
	if fingerprint and fingerprint == theirFingerprint then return true end
	-- (The review of the 1.5.4 candidate.) A whole store is up to MAX_CHUNKS pieces, one urgent
	-- transfer: a relay's queue (MAX_QUEUE parts) refuses a second one asked in the same seconds, and
	-- that asker got nothing until its next ask (half an hour). Refused, an answer is tried again every
	-- ANSWER_RETRY_EVERY seconds, ANSWER_RETRIES times, while the first one goes out.
	local function MayRetry(tries)
		local R = ns.Relay
		return tries > 0 and Direct() and type(R.IsRelay) == "function" and R.IsRelay(ns.me) == true
	end
	if toRelay then
		local key = Key(sender)
		answeredRelay[key] = now
		local function Answer(tries)
			if Verify.SendSnapshot(sender, true) then return end
			if MayRetry(tries) then
				ns.After(Verify.ANSWER_RETRY_EVERY, "verify answer", function() Answer(tries - 1) end)
			-- (The review of the 1.5.4 candidate.) An answer refused (a full queue, no relay to carry
			-- it) leaves the relay's gap open: its next ask is answered, not ignored RELAY_ANSWER_GAP.
			elseif answeredRelay[key] == now then
				answeredRelay[key] = nil
			end
		end
		ns.After(Verify.random(2, 9), "verify answer", function() Answer(Verify.ANSWER_RETRIES) end)
		return true
	end
	-- A legacy ask cannot prove that it holds our words, even with equal counts.
	-- ANSWER_GAP and the delayed/coalesced answer still bound recovery traffic.
	-- (Pending until it is queued or given up: one answer at a time. Another verifier's answer heard
	-- meanwhile covers it on the channel alone: where answers go Direct (Forever), what this client
	-- hears went to someone else, its own ask's answer or a hand-over in its own guild.)
	local request = {}
	pending = request
	local function Answer(tries)
		if pending ~= request then return end
		if Verify.Clock() - lastSent < Verify.ANSWER_GAP then pending = false return end
		if request.coverage and not Direct() then
			local _, _, covered = Verify.Payload(nil, request.coverage)
			if covered then pending = false return end
		end
		if Verify.SendSnapshot(sender) or not MayRetry(tries) then pending = false return end
		ns.After(Verify.ANSWER_RETRY_EVERY, "verify answer", function() Answer(tries - 1) end)
	end
	ns.After(Verify.random(2, 9), "verify answer", function() Answer(Verify.ANSWER_RETRIES) end)
	return true
end

function Verify.Ask()
	if not ns.IsMember() or Quiet() then return false end
	local n, newest, sum, fingerprint = Verify.Digest()
	stats.asked = stats.asked + 1
	local body = ("GV~%d~Q~%d~%d~%d"):format(Verify.PROTOCOL, n, newest, sum)
	if fingerprint then body = body .. "~" .. fingerprint end
	return ns.Comm.Send("CHANNEL", body, "verify-ask")
end

function Verify.Handle(dist, sender, text)
	if dist == "WHISPER" then return Verify.HandleGuildPoll(sender, text) end
	if dist ~= "CHANNEL" or type(sender) ~= "string" or sender == "" or type(text) ~= "string" then return false end
	local ver, kind, body = text:match("^GV~(%d+)~(%u)~(.*)$")
	if tonumber(ver) ~= Verify.PROTOCOL then return false end
	local now = Verify.Clock()
	sender = ns.FullName(sender)
	if kind == "Q" then return AnswerAsk(body, now, sender) end
	-- A word or a relay: from a verifier's own client alone (the server stamps the sender).
	if not Verify.Trusted(sender) then
		stats.refused = stats.refused + 1
		return false
	end
	if kind == "A" or kind == "R" then
		local at, guild, gm = body:match("^(%d+)~([^~]+)~([^~]+)$")
		at, guild, gm = TimeField(at), GuildField(guild), NameField(gm, ns.RealmOf(sender))
		if not (at and guild and gm) then
			stats.bad = stats.bad + 1
			return false
		end
		if not Take(kind, at, guild, gm, sender, now) then return false end
		Changed()
		TellOurs(kind, guild, sender)
		return true
	end
	if kind == "S" then
		local relay = ns.Relay
		if relay and relay.ApprovalResendGuild and relay.ApprovalResendGuild(text)
			and not Verify.CanForwardResend(text, sender) then return false end
		local made, rows = body:match("^(%d+)~(.*)$")
		if not TimeField(made) then
			stats.bad = stats.bad + 1
			return false
		end
		local realm = ns.RealmOf(sender)
		local count, changed, bad = 0, false, false
		-- (only while answering on the channel; at most MAX_ROWS received entries)
		local coverage = pending and not Direct() and {}
		for row in rows:gmatch("[^;]+") do
			if count >= Verify.MAX_ROWS then bad = true break end
			count = count + 1
			local k, at, guild, gm, by = row:match("^([AR]),(%d+),([^,]+),([^,]+),([^,]+)$")
			if k then
				at, guild, gm, by = TimeField(at), GuildField(guild), NameField(gm, realm), NameField(by, realm)
				if at and guild and gm and by then
					if Take(k, at, guild, gm, by, now) then changed = true end
					if coverage then coverage[CoverageKey(k, at, guild, gm, by)] = true end
				else
					bad = true
				end
			else
				local sat, sguild, sby = row:match("^T,(%d+),([^,]+),([^,]+)$")
				sat, sguild, sby = TimeField(sat), GuildField(sguild), NameField(sby, realm)
				if sat and sguild and sby then
					if TakeStart(sguild, sat, sby, now) then changed = true end
					if coverage then coverage[CoverageKey("T", sat, sguild)] = true end
				else
					bad = true
				end
			end
		end
		if pending and not bad then pending.coverage = coverage end
		if count > 0 and not bad then snapshots = snapshots + 1 end
		if changed then Changed() end
		if bad then stats.bad = stats.bad + 1 end
		return not bad
	end
	return false
end
ns.Comm.Handle("GV", function(...) return Verify.Handle(...) end)

---------------------------------------------------------------------------
-- A verifier's approval and revocation
---------------------------------------------------------------------------

-- The guild named by a verifier as this client spells it (the census's, a word's, our own), with
-- what follows the name (a guild master's name, or ""); the longest known name the input starts with.
function Verify.FindGuild(input)
	input = tostring(input or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if input == "" then return nil end
	local best, rest
	local function Try(name)
		if type(name) ~= "string" or name == "" or #name > #input then return end
		local n = #name
		if Key(input:sub(1, n)) ~= Key(name) or not (#input == n or input:sub(n + 1, n + 1):match("%s")) then return end
		if not ns.IsFederation(name) then return end
		if not best or n > #best then best, rest = name, (input:sub(n + 1):gsub("^%s+", "")) end
	end
	for name in pairs(ns.rdb.guilds or {}) do Try(name) end
	local s = Store()
	for _, e in pairs(s and s.list or {}) do if Valid(e) then Try(e.guild) end end
	if IsInGuild() then Try((GetGuildInfo("player"))) end
	return best, rest
end

-- A guild master's code: six hex digits of his guild and his name, which he reads in his notice and
-- gives a verifier; the verifier's client finds the guild whose current guild master it matches.
function Verify.Code(guild, gm)
	if type(guild) ~= "string" or type(gm) ~= "string" then return nil end
	local S = ns.Sign
	local h = type(S) == "table" and type(S.SHA256) == "function" and S.SHA256("olympus-verify-1|" .. Key(guild) .. "|" .. Key(ns.ShortName(ns.FullName(gm)))) or nil
	if type(h) ~= "string" or #h < 3 then return nil end
	return ("%02X%02X%02X"):format(h:byte(1), h:byte(2), h:byte(3))
end
function Verify.FromCode(code)
	code = tostring(code or ""):gsub("%s", ""):upper()
	if not code:match("^%x%x%x%x%x%x$") then return nil end
	local found, gm, many
	local function Try(name)
		if type(name) ~= "string" or not ns.IsFederation(name) or Verify.Exempt(name) then return end
		local master = Verify.GuildMaster(name)
		if master and Verify.Code(name, master) == code then
			if found and Key(found) ~= Key(name) then many = true end
			found, gm = name, master
		end
	end
	for name in pairs(ns.rdb.guilds or {}) do Try(name) end
	if many then return nil end
	return found, gm
end

-- The word goes out on the channel (logged: the server keeps who approved), and is ours at once.
local function Say(kind, guild, gm)
	if not Verify.Trusted(ns.me) or not ns.IsMember() then return false, "trust" end
	local at = Verify.Clock()
	local s = Store()
	local old = s and s.list[Key(guild)]
	if Valid(old) and old.at >= at then at = old.at + 1 end
	if not Take(kind, at, guild, gm, ns.FullName(ns.me), Verify.Clock()) then return false, "older" end
	Changed()
	ns.Comm.Send("CHANNEL", ("GV~%d~%s~%d~%s~%s"):format(Verify.PROTOCOL, kind, at, guild, gm), "verify#" .. Key(guild), true, true)
	return true
end

-- Approves a guild with its guild master (by default the census's). ok, the guild master or why not.
function Verify.Approve(guild, gm)
	if not Verify.Trusted(ns.me) or not ns.IsMember() then return false, "trust" end
	guild = GuildField(guild)
	if not guild then return false, "guild" end
	gm = (gm and gm ~= "") and NameField(gm) or Verify.GuildMaster(guild)
	if not gm then return false, "master" end
	local ok, why = Say("A", guild, gm)
	if not ok then return false, why end
	return true, gm
end

function Verify.Revoke(guild)
	if not Verify.Trusted(ns.me) or not ns.IsMember() then return false, "trust" end
	local s = Store()
	local e = s and type(guild) == "string" and s.list[Key(guild)]
	if not (Valid(e) and e.k == "A") then return false, "none" end
	return Say("R", e.guild, e.gm)
end

-- Called by the relay before it shares a Watch resend. Its retained revocation or newer approval
-- must win even if the originating verifier missed it. Ordinary snapshots retain their own path.
function Verify.CanForwardResend(body, origin)
	if type(body) ~= "string" or #body > 255 or not Verify.Trusted(origin) then return false end
	local made, at, guild, gm, by = body:match("^GV~1~S~(%d+)~A,(%d+),([^,;]+),([^,;]+),([^,;]+);$")
	local realm = ns.RealmOf(origin)
	at, guild, gm, by = TimeField(at), GuildField(guild), NameField(gm, realm), NameField(by, realm)
	if not (TimeField(made) and at and guild and gm and by) or Verify.Exempt(guild) then return false end
	local status, info = Verify.Status(guild)
	if info.gm and not SamePerson(info.gm, gm) then return false end
	if info.revoked and info.revoked.at >= at then return false end
	local old = info.entry
	return not old or old.at < at or (status == "verified" and old.at == at and SamePerson(old.gm, gm) and SamePerson(old.by, by))
end

local resendPending, lastResend
function Verify.ResendApproval(guild, expected)
	if not Verify.CouncilShown() or Quiet() then return false, "trust" end
	local status, info = Verify.Status(guild)
	local entry = status == "verified" and info.entry
	if not entry or (expected and expected ~= entry) then return false, "none" end
	local now = Verify.Clock()
	if resendPending or (lastResend and now - lastResend < Verify.RESEND_GAP) then return false, "busy" end
	local body = ("GV~%d~S~%d~A,%d,%s,%s,%s;"):format(Verify.PROTOCOL, now, entry.at, entry.guild, Relative(entry.gm), Relative(entry.by))
	if not Verify.CanForwardResend(body, ns.me) then return false, "none" end
	local store, group, faction = ns.rdb, ns.group, ns.faction
	local function StillCurrent()
		if not Verify.CouncilShown() or Quiet() or ns.rdb ~= store or ns.group ~= group or ns.faction ~= faction then return false end
		local current, details = Verify.Status(guild)
		return current == "verified" and details.entry == entry and Verify.CanForwardResend(body, ns.me)
	end
	resendPending = true
	return ns.Comm.Send("CHANNEL", body, "verify resend#" .. Key(guild), true, false, function(sent)
		resendPending = false
		if sent then lastResend = Verify.Clock() end
		ns.Print((sent and L.VERIFY_RESEND_SENT or L.VERIFY_RESEND_FAILED):format(guild))
	end, { owner = Verify, guard = StillCurrent }) == true
end

local function SayWhy(why, guild)
	if why == "trust" then return ns.Print(L.VERIFY_ONLY) end
	if why == "master" then return ns.Print(L.VERIFY_NO_MASTER:format(guild)) end
	if why == "none" then return ns.Print(L.VERIFY_NOTHING:format(guild)) end
	if why == "older" then return ns.Print(L.VERIFY_REFUSED:format(guild)) end
	return ns.Print(L.VERIFY_BAD_GUILD)
end

function Verify.ResendClick(data)
	if type(data) ~= "table" or not data.entry then return false end
	local ok, why = Verify.ResendApproval(data.guild, data.entry)
	if why == "busy" then return ns.Print(L.VERIFY_RESEND_BUSY) end
	if why == "none" then return ns.Print(L.VERIFY_RESEND_FAILED:format(data.guild)) end
	if not ok and why then return SayWhy(why, data.guild) end
	return ok
end

local poll, pollResult, pollSerial, lastPoll, lastRosterPoll = nil, nil, 0, -math.huge, -math.huge
local function PollPeer(name)
	local realm = type(name) == "string" and ns.RealmOf(name) or ns.realm
	if type(name) ~= "string" or name == "" or not ns.group or ns.GroupOf(realm) ~= ns.group then return false end
	local region = tostring(ns.realm or ""):match("^CAMWOW(%u%u)")
	local reported = ns.Comm.PeerRealm and ns.Comm.PeerRealm(name)
	if region and (tostring(reported or realm):match("^CAMWOW(%u%u)") ~= region) then return false end
	local M = ns.Moderation
	return not (M and M.Hidden and M.Hidden(name))
end

local function NativeMaster(guild, previous)
	local R = ns.Roster and ns.Roster.Fresh and ns.Roster.Fresh()
	if not R or Key(R.guild) ~= Key(guild) or R.generation <= previous then return nil end
	local found
	for name, rank in pairs(R.byName) do
		if rank == 0 then
			if found then return nil end
			found = NameField(name)
		end
	end
	return found
end

local function ScanMaster(guild, allowed, finished)
	local R, now = ns.Roster, Verify.Clock()
	if now - lastRosterPoll < Verify.POLL_GAP or not R or not R.RequestScan or not allowed() then return false end
	lastRosterPoll = now
	local generation = tonumber(R.generation) or 0
	R.RequestScan(true)
	local function Read(again)
		if not allowed() then return end
		local gm = NativeMaster(guild, generation)
		if gm then finished(gm, generation)
		elseif again then ns.After(5, "watch roster poll", function() Read(false) end) end
	end
	ns.After(5, "watch roster poll", function() Read(true) end)
	return true
end

local function PollCurrent(p)
	return poll == p and p.store == ns.rdb and p.group == ns.group and p.faction == ns.faction
		and Verify.Clock() <= p.deadline and Verify.CouncilShown() and not Quiet()
end

local function ReportMaster(p, gm, reporter)
	poll = nil
	local text = L.VERIFY_POLL_RESULT:format(p.guild, Shown(gm), Shown(reporter))
	pollResult = { guild = p.guild, store = p.store, at = Verify.Clock(), text = text }
	ns.Print(text)
	Changed()
end

function Verify.PollGuild(guild)
	guild = GuildField(guild)
	if not guild or not Verify.CouncilShown() or Quiet() or not ns.group or not ns.faction then return false end
	local now = Verify.Clock()
	if poll or now - lastPoll < Verify.POLL_GAP then ns.Print(L.VERIFY_POLL_BUSY); return false end
	local own = Key(GetGuildInfo("player")) == Key(guild)
	local row = not own and Row(guild)
	local reporter = own and ns.me or (row and not row.conflict and row.reporterFull)
	local age = row and type(row.t) == "number" and ns.Now() - row.t
	if not PollPeer(reporter) or (not own and (not age or age < 0 or age > ns.Data.FRESH)) then
		ns.Print(L.VERIFY_POLL_UNAVAILABLE:format(guild)); return false
	end
	pollSerial = pollSerial + 1
	local p = { guild = guild, reporter = reporter, id = ("%d-%d"):format(now, pollSerial), store = ns.rdb,
		group = ns.group, faction = ns.faction, deadline = now + Verify.POLL_WAIT }
	poll, lastPoll = p, now
	local function Allowed() return PollCurrent(p) and PollPeer(reporter) end
	local function Failed()
		if poll ~= p then return end
		poll = nil
		if p.store == ns.rdb and Verify.CouncilShown() then ns.Print(L.VERIFY_POLL_UNAVAILABLE:format(guild)) end
	end
	local accepted
	if own then
		accepted = ScanMaster(guild, function() return Allowed() and Key(GetGuildInfo("player")) == Key(guild) end,
			function(gm) ReportMaster(p, gm, ns.me) end)
	else
		local text = ("GV~%d~M~%s~%s~%s"):format(Verify.PROTOCOL, p.id, p.faction, guild)
		accepted = ns.Comm.Whisper(reporter, text, nil, false, false, function(sent) if not sent then Failed() end end,
			{ owner = Verify, guard = Allowed })
	end
	if not accepted then Failed(); return false end
	if poll == p then ns.Print(L.VERIFY_POLL_SENT:format(guild)) end
	ns.After(Verify.POLL_WAIT, "watch roster poll timeout", Failed)
	return true
end

function Verify.HandleGuildPoll(sender, text)
	if type(text) ~= "string" or not PollPeer(sender) or Quiet() or not ns.IsMember() then return false end
	local id, faction, guild = text:match("^GV~1~M~(%d+%-%d+)~(%a+)~([^~]+)$")
	if id then
		guild = GuildField(guild)
		if #id > 32 or not guild or faction ~= ns.faction or not Verify.Trusted(sender) then return false end
		local store, group = ns.rdb, ns.group
		local function Allowed()
			return ns.rdb == store and ns.group == group and ns.faction == faction and ns.IsMember() and not Quiet()
				and PollPeer(sender) and Verify.Trusted(sender) and Key(GetGuildInfo("player")) == Key(guild)
		end
		return ScanMaster(guild, Allowed, function(gm, previous)
			ns.Comm.Whisper(sender, ("GV~%d~N~%s~%s~%s~%s"):format(Verify.PROTOCOL, id, faction, guild, gm),
				nil, false, false, nil, { owner = Verify, guard = function()
					return Allowed() and NativeMaster(guild, previous) == gm
				end })
		end)
	end
	local p, gm = poll
	id, faction, guild, gm = text:match("^GV~1~N~(%d+%-%d+)~(%a+)~([^~]+)~([^~]+)$")
	if not id or not p or not PollCurrent(p) or id ~= p.id or faction ~= p.faction or Key(guild) ~= Key(p.guild)
		or not SamePerson(sender, p.reporter) then return false end
	gm = NameField(gm, ns.RealmOf(sender))
	if not PollPeer(gm) then return false end
	ReportMaster(p, gm, sender)
	return true
end

function Verify.ApproveInput(input)
	if not Verify.Trusted(ns.me) then return ns.Print(L.VERIFY_ONLY) end
	local guild, gm = Verify.FindGuild(input)
	if not guild then guild, gm = Verify.FromCode(input) end
	if not guild then return ns.Print(L.VERIFY_BAD_GUILD) end
	if gm == "" then gm = nil end
	local census = Verify.GuildMaster(guild)
	local ok, who = Verify.Approve(guild, gm or census)
	if not ok then return SayWhy(who, guild) end
	ns.Print(L.VERIFY_APPROVED:format(guild, Shown(who)))
	if census and not SamePerson(census, who) then ns.Print(L.VERIFY_OTHER_MASTER:format(Shown(census), guild, Shown(who))) end
	return true
end

function Verify.RevokeInput(input)
	if not Verify.Trusted(ns.me) then return ns.Print(L.VERIFY_ONLY) end
	local guild = Verify.FindGuild(input) or tostring(input or "")
	local ok, why = Verify.Revoke(guild)
	if not ok then return SayWhy(why, guild) end
	ns.Print(L.VERIFY_REVOKED:format(guild))
	return true
end

---------------------------------------------------------------------------
-- The guild master's and the members' notice
---------------------------------------------------------------------------

function Verify.Duration(seconds)
	local s = math.max(0, math.floor(tonumber(seconds) or 0))
	local h = math.floor(s / 3600)
	if h >= 24 then return L.VERIFY_DAYS:format(math.floor(h / 24), h % 24) end
	return L.VERIFY_HOURS:format(h, math.floor((s % 3600) / 60))
end

-- Member-facing notices are paused, including overdue guilds. The master still has the original
-- deadline and reminder. Approval state and the verifiers' follow-up are independent of notices.
function Verify.Mine(now)
	if not ns.IsMember() then return nil end
	local guild, _, rank = GetGuildInfo("player")
	local status, info = Verify.Status(guild, now)
	if status == nil or status == "verified" or status == "exempt" then return nil end
	if info.waiting then return nil end -- (1.5.5: nobody here could verify him yet)
	local master = rank == 0
	if not master then return nil end
	return "master", guild, status, info
end

function Verify.WhisperText(guild)
	return L.VERIFY_WHISPER_TEXT:format(guild, Verify.Code(guild, ns.me) or "?")
end

function Verify.NoticeText(who, guild, status, info)
	local parts = {}
	if who == "master" then
		if info.lapsed and info.entry then parts[#parts + 1] = L.VERIFY_NOTICE_LAPSED:format(guild, Shown(info.entry.gm)) end
		local code = Verify.Code(guild, ns.me) or "?"
		if status == "pending" then
			parts[#parts + 1] = L.VERIFY_NOTICE_MASTER_GRACE:format(guild, Verify.Duration(info.left), L.VERIFY_CONTACT, code)
		else
			parts[#parts + 1] = L.VERIFY_NOTICE_MASTER_LATE:format(guild, L.VERIFY_CONTACT, code)
			if ns.VERIFY_HOLD == true then parts[#parts + 1] = L.VERIFY_NOTICE_HOLD end
		end
		parts[#parts + 1] = L.VERIFY_WHISPER_LABEL .. "\n" .. Verify.WhisperText(guild)
		parts[#parts + 1] = L.VERIFY_RESEND_NOTE
	else
		parts[#parts + 1] = L.VERIFY_NOTICE_MEMBER:format(guild, Shown(info.gm))
	end
	if ns.VERIFY_GATE ~= true then parts[#parts + 1] = L.VERIFY_NO_GATE end
	return table.concat(parts, "\n\n")
end

local function ChatLine(who, guild, status, info)
	if who == "member" then return L.VERIFY_CHAT_MEMBER:format(guild) end
	if status == "pending" then return L.VERIFY_CHAT_MASTER_GRACE:format(guild, Verify.Duration(info.left)) end
	return L.VERIFY_CHAT_MASTER_LATE:format(guild)
end

-- The verifiers a guild master's whisper goes to: the one the locale names, the councillors taking
-- requests now, the author while online. In that order.
function Verify.Verifiers()
	local out, seen = {}, {}
	local function Add(name)
		if type(name) ~= "string" or not name:match("%S") or seen[Key(name)] then return end
		seen[Key(name)] = true
		out[#out + 1] = name
	end
	Add(rawget(L, "VERIFY_WHISPER_TO"))
	local W = ns.Workshop
	if type(W) == "table" and not W.missing then
		if type(W.Available) == "function" then for _, name in ipairs(W.Available()) do Add(name) end end
		if type(W.AuthorOnline) == "function" and W.AuthorOnline() and type(W.AuthorName) == "function" then Add(W.AuthorName()) end
	end
	return out
end

-- The guild master's Whisper button: Olympus's own whisper window, written to the first verifier,
-- for him to send (nothing goes until he does).
function Verify.WhisperVerifier(guild)
	local list = Verify.Verifiers()
	local UI = ns.UI
	if #list == 0 or not (type(UI) == "table" and type(UI.WhisperText) == "function") then
		ns.Print(L.VERIFY_NOBODY:format(L.VERIFY_CONTACT))
		return false
	end
	return UI.WhisperText(ns.TellName(list[1]), Verify.WhisperText(guild)) ~= nil
end

-- Request timing is separate from the guild's earliest observation/start. It limits queued
-- requests across reloads without renewing the guild's verification deadline.
function Verify.RequestWait(guild, now)
	now = now or Verify.Clock()
	local s = Store()
	local e = s and s.requests[Key(guild)]
	local at = type(e) == "table" and TimeField(e.at)
	return at and math.max(0, at + Verify.REQUEST_GAP - now) or 0
end

-- Reuse the councillors' existing help request (Workshop.AskCouncil), with the same code.
-- A stale button cannot request for a former guild, a new master or an already approved guild.
function Verify.AskCouncil(guild)
	local now = Verify.Clock()
	local who, mine = Verify.Mine(now)
	if who ~= "master" or type(guild) ~= "string" or Key(guild) ~= Key(mine) then return false, "master" end
	local wait = Verify.RequestWait(guild, now)
	if wait > 0 then
		ns.Print(L.VERIFY_RETRY_WAIT:format(math.ceil(wait / 60)))
		return false, "cooldown"
	end
	local W = ns.Workshop
	if type(W) ~= "table" or W.missing or type(W.AskCouncil) ~= "function" then return false end
	Verify.Observe(now) -- establish a missing first sighting once; an existing start is untouched
	if W.AskCouncil(L.VERIFY_ASK_TEXT:format(guild, Verify.Code(guild, ns.me) or "?")) ~= true then return false, "unavailable" end
	local s = Store()
	if s then s.requests[Key(guild)] = { at = now } end
	ns.Print(L.VERIFY_RETRY_WAIT:format(math.ceil(Verify.REQUEST_GAP / 60)))
	return true
end

-- The notice, in a window it can be copied from; auto: opened by itself (no keyboard taken).
function Verify.ShowNotice(auto)
	local who, guild, status, info = Verify.Mine()
	local UI = ns.UI
	if not who or not (type(UI) == "table" and type(UI.ShowCopy) == "function") then return false end
	local action, second
	if who == "master" then
		-- (Neither button greys out: the window stays to try again.)
		action = { label = L.VERIFY_WHISPER_BTN, fn = function() Verify.WhisperVerifier(guild) end }
		second = { label = L.VERIFY_ASK_BTN, fn = function() Verify.AskCouncil(guild) end }
	end
	UI.ShowCopy(L.VERIFY_TITLE, Verify.NoticeText(who, guild, status, info), action, { key = "verify", auto = auto and true or nil, second = second })
	return true
end

-- On top of the Census (Views.lua) while our guild asks something of this player: a click opens
-- the notice (with the gamepad UI too, where nothing is typed).
function Verify.Lines(now)
	local who, guild, status, info = Verify.Mine(now)
	if not who then return {} end
	local text
	if who == "master" then
		text = status == "pending" and L.VERIFY_LINE_MASTER_GRACE:format(Verify.Duration(info.left)) or L.VERIFY_LINE_MASTER_LATE
	else
		text = L.VERIFY_LINE_MEMBER:format(guild)
	end
	return { { id = "verify-notice", text = status == "pending" and Gold(text) or Red(text), gapAfter = true,
		onClick = function() Verify.ShowNotice() end,
		tooltip = function(tt)
			tt:AddLine(L.VERIFY_TITLE, 1, 0.82, 0)
			tt:AddLine(L.VERIFY_LINE_TIP, 1, 1, 1, true)
		end } }
end

function Verify.PrintStatus()
	local guild = IsInGuild() and GetGuildInfo("player")
	local status, info = Verify.Status(guild)
	if not status then return ns.Print(L.VERIFY_STATUS_NONE) end
	if status == "exempt" then return ns.Print(L.VERIFY_STATUS_EXEMPT:format(guild)) end
	if status == "verified" then
		local e = info.entry
		return ns.Print(L.VERIFY_STATUS_VERIFIED:format(guild, Shown(e.gm), Shown(e.by), date("%Y-%m-%d", e.at)))
	end
	if info.waiting then return ns.Print(L.VERIFY_STATUS_WAITING:format(guild)) end -- (1.5.5)
	if status == "pending" then return ns.Print(L.VERIFY_STATUS_GRACE:format(guild, Verify.Duration(info.left))) end
	return ns.Print(L.VERIFY_STATUS_LATE:format(guild))
end

---------------------------------------------------------------------------
-- The verifiers' page: The Watch's Guilds (Watch.lua), and their notices
---------------------------------------------------------------------------

function Verify.CouncilShown()
	return ns.IsMember() and Verify.Trusted(ns.me)
end

local function Ignored()
	local list = ns.rdb and ns.rdb.verifyIgnored
	return type(list) == "table" and list or nil
end

function Verify.SetIgnored(guild, on)
	if not Verify.CouncilShown() or type(guild) ~= "string" then return false end
	local list, key = Ignored(), Key(guild)
	if on then
		guild = GuildField(guild)
		if not guild then return false end
		if not list then list = {}; ns.rdb.verifyIgnored = list end
		local count = 0
		for _ in pairs(list) do count = count + 1 end
		if not list[key] and count >= Verify.MAX then return false end
		list[key] = guild
	elseif list and list[key] then
		list[key] = nil
	else return false end
	Changed()
	return true
end

-- The guilds still to verify (the census's and our own; overdue first, then the least time left,
-- then the biggest) and the verified ones (by name), each { guild, status, info, total }.
-- (1.5.5) And every guild with a valid start: the starts cross the relays with the approvals (a
-- verifier's answer, GV~S), while the census reaches a verifier only from the guilds on his own relay,
-- so the verifiers' page missed the other relays' guilds before the hold began (the audit of 11-10:
-- more starts than census guilds on both realm groups). A guild the census never brought here shows
-- with its start, no guild master and no member count until it does.
function Verify.Pending(now)
	now = now or Verify.Clock()
	local pending, verified, done, ignored = {}, {}, {}, Ignored()
	local function Add(guild)
		if type(guild) ~= "string" then return end
		local key = Key(guild)
		if done[key] or (ignored and type(ignored[key]) == "string") then return end
		done[key] = true
		local status, info = Verify.Status(guild, now)
		if not status or status == "exempt" then return end
		local g = Row(guild)
		local row = { guild = guild, status = status, info = info, total = type(g) == "table" and tonumber(g.total) or nil }
		if status == "verified" then verified[#verified + 1] = row else pending[#pending + 1] = row end
	end
	for name in pairs(ns.rdb.guilds or {}) do Add(name) end
	if IsInGuild() then Add((GetGuildInfo("player"))) end
	local s = Store()
	for _, e in pairs(s and s.list or {}) do if Valid(e) and e.k == "A" then Add(e.guild) end end
	for _, e in pairs(s and s.start or {}) do if ValidStart(e) then Add(e.guild) end end
	table.sort(pending, function(a, b)
		if a.info.left ~= b.info.left then return a.info.left < b.info.left end
		if (a.total or 0) ~= (b.total or 0) then return (a.total or 0) > (b.total or 0) end
		return Key(a.guild) < Key(b.guild)
	end)
	table.sort(verified, function(a, b) return Key(a.guild) < Key(b.guild) end)
	return pending, verified
end

local function StateText(r)
	if r.status == "overdue" then return r.info.lapsed and L.VERIFY_COUNCIL_LAPSED_LATE or L.VERIFY_COUNCIL_LATE end
	if r.info.lapsed then return L.VERIFY_COUNCIL_LAPSED:format(Verify.Duration(r.info.left)) end
	return L.VERIFY_COUNCIL_GRACE:format(Verify.Duration(r.info.left))
end
local function Members(r) return r.total and ns.FormatNumber(r.total) or "?" end
local function By(name)
	if ns.CouncilMasked and ns.CouncilMasked() and ns.MaskName then return ns.MaskName(Shown(name)) end
	return Shown(name)
end
local function Named(rows)
	local out = {}
	for i, r in ipairs(rows) do
		if i > Verify.SHOWN_MAX then
			out[#out + 1] = L.VERIFY_MORE:format(#rows - Verify.SHOWN_MAX)
			break
		end
		out[#out + 1] = "<" .. r.guild .. "> (" .. Shown(r.info.gm) .. ")"
	end
	return table.concat(out, ", ")
end

-- The verifiers' notices, each once per guild and guild master (kept in the saved data): a guild
-- pending (new, or with a new guild master to check), and REMIND_LEFT before its deadline. One
-- chat line for each kind, naming the guilds. (1.5.4) A reminder is kept with the deadline it was
-- for: a later deadline is reminded again (the reset moved every one later, and 1.5.3 kept no
-- deadline, so each guild it reminded is reminded once more before its new one); a deadline that
-- only came nearer (an earlier start heard) is not.
function Verify.CouncilNotices(now)
	if not Verify.CouncilShown() then return 0 end
	now = now or Verify.Clock()
	local s = Store()
	local new, due = {}, {}
	for _, r in ipairs((Verify.Pending(now))) do
		local key = Key(r.guild)
		local gm = r.info.gm and Key(ns.ShortName(r.info.gm)) or ""
		local t = s.told[key]
		if type(t) ~= "table" or (gm ~= "" and t.gm ~= "" and t.gm ~= gm) then
			t = { gm = gm, new = now }
			s.told[key] = t
			new[#new + 1] = r
		elseif t.gm == "" and gm ~= "" then
			t.gm = gm
		end
		t.last = now
		local reminded = tonumber(t.deadline)
		if r.status == "pending" and r.info.left <= Verify.REMIND_LEFT and not (reminded and reminded >= r.info.deadline) then
			t.remind, t.deadline = now, r.info.deadline
			due[#due + 1] = r
		end
	end
	if #new > 0 then ns.Print(L.VERIFY_COUNCIL_NEW:format(Named(new))) end
	if #due > 0 then ns.Print(L.VERIFY_COUNCIL_REMIND:format(Verify.Duration(Verify.REMIND_LEFT), Named(due))) end
	return #new + #due
end

-- A row's click: approve, or whisper its guild master (Olympus's own whisper window, his words to edit).
function Verify.AskGuild(r)
	local gm = r.info.gm
	local text = L.VERIFY_GUILD_PROMPT:format(r.guild, Shown(gm), StateText(r) .. "  " .. L.VERIFY_COUNCIL_MEMBERS:format(Members(r)))
	return ns.ShowDialog("OLYMPUS_VERIFY_GUILD", text, nil, { guild = r.guild, gm = gm })
end
function Verify.Nudge(data)
	local UI = ns.UI
	if type(data) ~= "table" or type(data.gm) ~= "string" then return ns.Print(L.VERIFY_NO_MASTER:format(tostring(data and data.guild or "?"))) end
	if not (type(UI) == "table" and type(UI.WhisperText) == "function") then return false end
	return UI.WhisperText(ns.TellName(data.gm), L.VERIFY_NUDGE_TEXT:format(data.guild)) ~= nil
end
function Verify.ApproveClick(data)
	if type(data) ~= "table" then return false end
	local ok, why = Verify.Approve(data.guild, data.gm)
	if not ok then return SayWhy(why, data.guild) end
	ns.Print(L.VERIFY_APPROVED:format(data.guild, Shown(why)))
	return true
end

function Verify.ListText(now)
	now = now or Verify.Clock()
	local pending, verified = Verify.Pending(now)
	local out = { L.VERIFY_LIST_HEAD:format(Shown(ns.me), date("%Y-%m-%d %H:%M")) }
	for _, r in ipairs(pending) do
		out[#out + 1] = L.VERIFY_LIST_ROW:format(r.guild, Shown(r.info.gm), Members(r), Verify.Duration(now - r.info.since),
			StateText(r), (r.info.gm and Verify.Code(r.guild, r.info.gm)) or "?")
	end
	out[#out + 1] = ""
	out[#out + 1] = L.VERIFY_LIST_FOOT:format(#verified)
	return table.concat(out, "\n")
end
function Verify.ShowList()
	local UI = ns.UI
	if not Verify.CouncilShown() then return ns.Print(L.VERIFY_ONLY) end
	if not (type(UI) == "table" and type(UI.ShowCopy) == "function") then return false end
	return UI.ShowCopy(L.VERIFY_COUNCIL_TITLE, Verify.ListText(), nil, { key = "verify-list" }) ~= nil
end

function Verify.Count()
	return #(Verify.Pending())
end

local selectedGuild, managingIgnored
local function SelectGuild(guild)
	selectedGuild = selectedGuild ~= guild and guild or nil
	Changed()
end

local function CouncilActions(lines, r, approval)
	if selectedGuild ~= r.guild then return end
	lines[#lines + 1] = { indent = 2, text = Gold(L.VERIFY_GUILD_ACTIONS), onClick = approval }
	lines[#lines + 1] = { indent = 2, text = Gold(L.VERIFY_POLL_GUILD), onClick = function() Verify.PollGuild(r.guild) end }
	if pollResult and pollResult.guild == r.guild and pollResult.store == ns.rdb then
		local age = Verify.Clock() - pollResult.at
		if age >= 0 and age <= 300 then
			lines[#lines + 1] = { indent = 3, text = Grey(pollResult.text), right = Grey(ns.Ago(pollResult.at)), wrap = true }
		end
	end
	lines[#lines + 1] = { indent = 2, text = Gold(L.VERIFY_COPY_GUILD), onClick = function()
		if not Verify.CouncilShown() then return end
		if ns.UI and ns.UI.ShowCopy then ns.UI.ShowCopy(L.VERIFY_COPY_GUILD, r.guild, nil, { key = "verify-guild-name" }) end
	end }
	lines[#lines + 1] = { indent = 2, text = Gold(L.VERIFY_IGNORE_GUILD), onClick = function()
		if Verify.SetIgnored(r.guild, true) then selectedGuild = nil end
	end }
end

function Verify.CouncilLines(now)
	if not Verify.CouncilShown() then return {} end
	now = now or Verify.Clock()
	local pending, verified = Verify.Pending(now)
	local lines = {
		{ id = "verify-council", header = true, text = L.VERIFY_COUNCIL_TITLE, right = Grey(#pending) },
		{ text = Grey(L.VERIFY_COUNCIL_SCOPE), wrap = true },
		{ id = "verify-copy", text = Gold(L.VERIFY_COUNCIL_COPY), onClick = function() Verify.ShowList() end, gapAfter = true },
	}
	local ignored = {}
	for key, guild in pairs(Ignored() or {}) do
		if type(guild) == "string" and #guild <= 72 and not guild:find("[~;,|%c]") and key == Key(guild) then
			ignored[#ignored + 1] = guild
		end
	end
	table.sort(ignored, function(a, b) return Key(a) < Key(b) end)
	lines[#lines + 1] = { id = "verify-ignored", text = Gold(L.VERIFY_MANAGE_IGNORED:format(#ignored)), gapAfter = true,
		onClick = function() managingIgnored = not managingIgnored; Changed() end }
	if managingIgnored then
		lines[#lines + 1] = { indent = 1, text = Grey(L.VERIFY_IGNORED_HINT), wrap = true }
		for _, guild in ipairs(ignored) do
			lines[#lines + 1] = { indent = 1, text = Gold(L.VERIFY_RESTORE_IGNORED:format(guild)), onClick = function()
				Verify.SetIgnored(guild, false)
			end }
		end
		lines[#lines].gapAfter = true
	end
	if #pending == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.VERIFY_COUNCIL_EMPTY) } end
	for _, r in ipairs(pending) do
		local late = r.status == "overdue"
		lines[#lines + 1] = {
			indent = 1, text = (late and Verify.MARK_LATE or "") .. "<" .. r.guild .. ">  " .. Shown(r.info.gm),
			right = late and Red(StateText(r)) or Grey(StateText(r)),
			tooltip = function(tt)
				tt:AddLine("<" .. r.guild .. ">", 1, 0.82, 0)
				tt:AddLine(L.VERIFY_COUNCIL_MASTER:format(Shown(r.info.gm)), 1, 1, 1)
				tt:AddLine(L.VERIFY_COUNCIL_MEMBERS:format(Members(r)), 1, 1, 1)
				tt:AddLine(L.VERIFY_COUNCIL_SEEN:format(Verify.Duration(now - r.info.since)), 0.7, 0.7, 0.7)
				if r.info.gm then tt:AddLine(L.VERIFY_COUNCIL_CODE:format(Verify.Code(r.guild, r.info.gm) or "?"), 0.7, 0.7, 0.7) end
				tt:AddLine(StateText(r), late and 1 or 0.7, late and 0.4 or 0.7, late and 0.4 or 0.7, true)
				tt:AddLine(L.VERIFY_COUNCIL_CLICK, 0.25, 1, 0.25, true)
			end,
			onClick = function() SelectGuild(r.guild) end,
		}
		CouncilActions(lines, r, function() Verify.AskGuild(r) end)
	end
	lines[#lines].gapAfter = true
	lines[#lines + 1] = { header = true, text = L.VERIFY_COUNCIL_VERIFIED, right = Grey(#verified) }
	for _, r in ipairs(verified) do
		local e = r.info.entry
		lines[#lines + 1] = {
			indent = 1, text = Verify.MARK_OK .. "<" .. r.guild .. ">  " .. Shown(e.gm),
			right = Grey(L.VERIFY_COUNCIL_BY:format(By(e.by), date("%Y-%m-%d", e.at))),
			tooltip = function(tt)
				tt:AddLine("<" .. r.guild .. ">", 1, 0.82, 0)
				tt:AddLine(L.VERIFY_COUNCIL_MASTER:format(Shown(e.gm)), 1, 1, 1)
				tt:AddLine(L.VERIFY_COUNCIL_REVOKE_CLICK, 1, 0.4, 0.4, true)
			end,
			onClick = function() SelectGuild(r.guild) end,
		}
		CouncilActions(lines, r, function()
			ns.ShowDialog("OLYMPUS_VERIFY_REVOKE", L.VERIFY_REVOKE_PROMPT:format(r.guild, Shown(e.gm)), nil,
				{ guild = r.guild, entry = e })
		end)
	end
	return lines
end

-- Opens The Watch on its Guilds.
function Verify.OpenCouncil()
	local W = ns.Watch
	if type(W) == "table" and not W.missing and type(W.Show) == "function" then W.Show("verify") end
	if ns.UI and type(ns.UI.SelectTab) == "function" then ns.UI.SelectTab("watch") end
	return true
end

-- The Census's mark before a guild's name: verified, for everyone; overdue, for the verifiers.
function Verify.Mark(guild)
	local status = Verify.Status(guild)
	if status == "verified" then return Verify.MARK_OK end
	if status == "overdue" and Verify.Trusted(ns.me) then return Verify.MARK_LATE end
	return ""
end
function Verify.Tooltip(tt, guild)
	local status = Verify.Status(guild)
	if status == "verified" then
		tt:AddLine(L.VERIFY_MARK_VERIFIED, 0.25, 1, 0.25)
	elseif status == "overdue" and Verify.Trusted(ns.me) then
		tt:AddLine(L.VERIFY_MARK_LATE, 1, 0.4, 0.4)
	end
end

StaticPopupDialogs["OLYMPUS_VERIFY_GUILD"] = {
	text = "%s",
	button1 = L.VERIFY_APPROVE_BTN,
	button2 = CANCEL or "Cancel",
	button3 = L.VERIFY_WHISPER_GM_BTN,
	OnAccept = function(_, data) ns.SafeCall("verify approve", Verify.ApproveClick, data) end,
	OnAlt = function(_, data) ns.SafeCall("verify whisper", Verify.Nudge, data) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}
StaticPopupDialogs["OLYMPUS_VERIFY_REVOKE"] = {
	text = "%s",
	button1 = L.VERIFY_REVOKE_BTN,
	button2 = CANCEL or "Cancel",
	button3 = L.VERIFY_RESEND_APPROVAL,
	OnAccept = function(_, data)
		ns.SafeCall("verify revoke", function()
			if type(data) ~= "table" then return end
			local _, info = Verify.Status(data.guild)
			if not info or not data.entry or info.entry ~= data.entry then return SayWhy("older", data.guild) end
			local ok, why = Verify.Revoke(data.guild)
			if not ok then return SayWhy(why, data.guild) end
			ns.Print(L.VERIFY_REVOKED:format(data.guild))
		end)
	end,
	OnAlt = function(_, data) ns.SafeCall("verify resend", Verify.ResendClick, data) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- Optional local delivery view. The other addon installs its bridge at PLAYER_LOGIN;
-- opening the popup only reads local state. Keep the guild approval flow separate.
local deliveryStates = {
	{ "pending", "VERIFY_SELF_PENDING" }, { "delivered", "VERIFY_SELF_DELIVERED" },
	{ "rejected", "VERIFY_SELF_REJECTED" }, { "unsupported_callback", "VERIFY_SELF_UNSUPPORTED" },
	{ "unknown", "VERIFY_SELF_UNKNOWN" },
}
local deliveryTypes = { verify = true, role = true, guild = true, donation = true }
-- (1.5.8) A submission's answer shows once, in its result. Only an unconfirmed one stays on the
-- panel for the session: the bridge's status may not list it, and the player is asked to check
-- before sending the code again. A created request is listed by the status itself.
local unconfirmedSelf = false
local function SelfBridge()
	local b = rawget(_G, "OlympusVerifyBridge242")
	return type(b) == "table" and b or nil
end
local function DeliverySummary(s)
	if type(s) ~= "table" or s.version ~= 243 or s.deliveryOnly ~= true or s.membershipProof ~= false
		or s.roleAuthority ~= false or type(s.requests) ~= "table" or type(s.truncated) ~= "boolean" then return nil end
	local total = s.total
	if type(total) ~= "number" or total < 0 or total > 2147483647 or total ~= math.floor(total) then return nil end
	local counts, n = {}, 0
	for _, state in ipairs(deliveryStates) do counts[state[1]] = 0 end
	-- Display only known labels and counts. Never forward descriptors, raw fields or opaque IDs to the UI.
	for i = 1, math.min(total, 20) do
		local row = rawget(s.requests, i)
		if type(row) == "table" and type(row.type) == "string" and deliveryTypes[row.type]
			and type(row.deliveryState) == "string" and counts[row.deliveryState] ~= nil then
			counts[row.deliveryState] = counts[row.deliveryState] + 1
			n = n + 1
		end
	end
	return { total = total, counts = counts, shown = n, truncated = s.truncated or n < total }
end
local function SelfDelivery(b)
	if b and type(b.Status) == "function" then
		local ok, status = pcall(b.Status)
		local summary = ok and DeliverySummary(status)
		if summary then return summary end
	end
	local generic = rawget(_G, "OlympusBridge")
	if type(generic) == "table" and generic.API_VERSION == 1 and type(generic.GetSection) == "function" then
		local ok, section = pcall(generic.GetSection, "verification")
		if ok and type(section) == "table" and section.name == "verification" and section.version == 243 then
			return DeliverySummary(section.data)
		end
	end
end

local function SelfLinkReady()
	local loader, link = ns.LinkLoader, ns.Link
	return loader and type(loader.Loaded) == "function" and type(loader.Slash) == "function" and loader.Loaded()
		and type(link) == "table" and type(link.Slash) == "function"
		and type(link.BotReady) == "function" and link.BotReady() == true
end

local linkAction = {
	label = L.VERIFY_SELF_OPEN_LINK,
	shown = SelfLinkReady,
	onClick = function(f)
		if not SelfLinkReady() then return end
		f:Hide()
		ns.LinkLoader.Slash("")
	end,
}

local function SelfStatusLines(summary, submission)
	local lines = {}
	submission = submission or (unconfirmedSelf and "VERIFY_SELF_SUBMISSION_UNKNOWN") or nil
	if submission then lines[#lines + 1] = L[submission] end
	if not summary then
		lines[#lines + 1] = L.VERIFY_SELF_STATUS_UNAVAILABLE
	elseif summary.total > 0 then
		lines[#lines + 1] = L.VERIFY_SELF_TOTAL:format(summary.total)
		for _, state in ipairs(deliveryStates) do
			local n = summary.counts[state[1]]
			if n > 0 then lines[#lines + 1] = L[state[2]] .. ": " .. n end
		end
		if summary.truncated then lines[#lines + 1] = L.VERIFY_SELF_TRUNCATED:format(summary.shown, summary.total) end
		-- (1.5.8, the author could not tell what "Pending" meant after Discord had verified him) What
		-- the states a player asks about mean, below the counts.
		if summary.counts.pending > 0 then lines[#lines + 1] = "\n" .. L.VERIFY_SELF_PENDING_NOTE end
		if summary.counts.rejected > 0 then lines[#lines + 1] = "\n" .. L.VERIFY_SELF_REJECTED_NOTE end
	end
	return table.concat(lines, "\n")
end

-- (1.5.8) The guild the Discord bot verifies (Olympus Verify's FLAGSHIP_GUILD_NAME): there the rank
-- opens the member channels once the bot's checks pass. Other Olympus guilds are welcome in the
-- Olympus chat channel without a code. Only a text: the bot alone grants access and roles.
Verify.DISCORD_GUILD = "OLYMPUS PRIME"
function Verify.SelfWhy()
	local guild = IsInGuild() and GetGuildInfo("player")
	if type(guild) == "string" and guild:lower() == Verify.DISCORD_GUILD:lower() then return L.VERIFY_SELF_WHY_ROLE end
	return L.VERIFY_SELF_WHY_COMMUNITY:format(Verify.DISCORD_GUILD)
end

function Verify.SelfLine()
	local b = SelfBridge()
	return { id = "verify-self", text = L.VERIFY_SELF_TITLE,
		right = b and type(b.QueueSelf) == "function" and L.VERIFY_SELF_ENTER or nil, gapAfter = true,
		onClick = Verify.OpenSelf }
end

function Verify.OpenSelf()
	if not ns.Dialog or ns.Dialog.missing then return end
	local b = SelfBridge()
	local summary = SelfDelivery(b)
	local ready = b and type(b.QueueSelf) == "function" and summary
	local text = Verify.SelfWhy() .. "\n\n" .. L.VERIFY_SELF_GUIDE
	if not ready then text = text .. "\n\n" .. L.VERIFY_SELF_UNAVAILABLE end
	local status = SelfStatusLines(summary)
	if status ~= "" then text = text .. "\n\n" .. status end
	-- Requests already sent: Discord's answer is the one that counts.
	if summary and summary.total > 0 then text = text .. "\n\n" .. L.VERIFY_SELF_CHECK_DISCORD end
	return ns.Dialog.Show(ready and "OLYMPUS_VERIFY_SELF" or "OLYMPUS_VERIFY_SELF_UNAVAILABLE", text, nil, {})
end

StaticPopupDialogs["OLYMPUS_VERIFY_SELF_UNAVAILABLE"] = {
	text = "%s",
	button1 = OKAY or "OK",
	extra = linkAction,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["OLYMPUS_VERIFY_SELF_RESULT"] = {
	text = "%s",
	button1 = OKAY or "OK",
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["OLYMPUS_VERIFY_SELF"] = {
	text = "%s",
	button1 = L.VERIFY_SELF_SEND,
	button2 = CANCEL or "Cancel",
	extra = linkAction,
	hasEditBox = true,
	editBoxWidth = 350,
	maxLetters = 128,
	maxBytes = 128,
	OnShow = function(self)
		if self.editBox.SetPassword then self.editBox:SetPassword(true) end
		ns.Focus(self.editBox)
	end,
	OnHide = function(self)
		self.editBox:SetText("")
		if self.editBox.SetPassword then self.editBox:SetPassword(false) end
	end,
	OnAccept = function(self, attempt)
		if type(attempt) ~= "table" or attempt.used then return end
		attempt.used = true -- before the callback, including reentrant or duplicate clicks
		local code = self.editBox:GetText()
		self.editBox:SetText("")
		local b = SelfBridge()
		local submission = "VERIFY_SELF_REFUSED"
		if b and type(b.QueueSelf) == "function" and SelfDelivery(b) and type(code) == "string"
			and not (issecretvalue and issecretvalue(code)) and code:find("%S") and #code <= 128 then
			local ok, queued = pcall(b.QueueSelf, code)
			if not ok or type(queued) ~= "boolean" then
				submission = "VERIFY_SELF_SUBMISSION_UNKNOWN"
			elseif queued then
				submission = "VERIFY_SELF_QUEUED"
			end
		end
		unconfirmedSelf = submission == "VERIFY_SELF_SUBMISSION_UNKNOWN"
		self:Hide()
		local status = SelfStatusLines(SelfDelivery(b), submission)
		ns.Dialog.Show("OLYMPUS_VERIFY_SELF_RESULT", status .. "\n\n" .. L.VERIFY_SELF_CHECK_DISCORD)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

---------------------------------------------------------------------------
-- The session: the guilds seen, the notices, the asks
---------------------------------------------------------------------------

-- Once a session, while our guild asks something of this player: a chat line and the notice,
-- NOTICE_AFTER after login, never in an instance, on Busy or in a fight (it waits for the next
-- tick). The verifiers' own notices at each tick from then on.
local loginAt, told, ticking = nil, false, false
function Verify.Tick(now)
	now = now or Verify.Clock()
	Verify.Observe(now)
	Verify.Prune(now)
	if not loginAt or now - loginAt < Verify.NOTICE_AFTER then return false end
	Verify.CouncilNotices(now)
	if told then return false end
	local who, guild, status, info = Verify.Mine(now)
	if not who then return false end
	if (ns.Quiet and ns.Quiet()) or (InCombatLockdown and InCombatLockdown()) then return false end
	told = true
	ns.Print(ChatLine(who, guild, status, info))
	Verify.ShowNotice(true)
	return true
end

function Verify.Login(now)
	loginAt, told = now or Verify.Clock(), false
	Verify.Observe(loginAt)
	local session = {}
	startup = session
	ns.After(Verify.ASK_AFTER + Verify.random(0, Verify.ASK_SPREAD), "verify ask", function()
		if startup ~= session then return end
		local before = snapshots
		Verify.Ask()
		if not Direct() then return end
		-- A cold client can ask while nobody can answer, or when the shared relay ask is still
		-- on cooldown. Give it one more turn without changing the periodic traffic or trust rules.
		ns.After(Verify.STARTUP_RETRY + Verify.random(0, Verify.STARTUP_SPREAD), "verify startup retry", function()
			if startup == session and snapshots == before then Verify.Ask() end
		end)
	end)
	if not ticking then
		ticking = true
		ns.Every(Verify.TICK, "verify", function() Verify.Tick() end)
		ns.Every(Verify.ASK_EVERY, "verify ask", Verify.Ask)
	end
end

ns.On("LOGIN", function() Verify.Login() end)
-- (A member once the Accord is accepted: the login's ask found none, so it asks again.)
ns.On("ACCORD_CHANGED", function(on) if on then ns.After(40, "verify ask", Verify.Ask) end end)

-- /oly verify: alone, our guild's notice when it asks something of us, else the verifiers' page,
-- else our guild's state; status | list | approve <Guild> [Guild master] or <code> | revoke <Guild>.
function Verify.Slash(rest)
	rest = tostring(rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local verb, arg = rest:match("^(%S*)%s*(.-)$")
	verb = (verb or ""):lower()
	if verb == "" then
		if Verify.Mine() then return Verify.ShowNotice() end
		if Verify.CouncilShown() then return Verify.OpenCouncil() end
		return Verify.PrintStatus()
	elseif verb == "status" then
		return Verify.PrintStatus()
	elseif verb == "list" or verb == "lista" then
		return Verify.ShowList()
	elseif verb == "approve" or verb == "aprovar" then
		return Verify.ApproveInput(arg)
	elseif verb == "revoke" or verb == "revogar" then
		return Verify.RevokeInput(arg)
	end
	ns.Print(L.VERIFY_USAGE)
end
