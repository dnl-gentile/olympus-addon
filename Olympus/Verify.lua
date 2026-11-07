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
-- The clock: GRACE (48 hours) from the guild's start, the same on every client. A verifier's client
-- records the first time it saw the guild (its census, or its own guild) and relays it with the
-- approvals; every client keeps the earliest start any verifier's client gave (ns.rdb.verify.start,
-- the earliest wins), so a reinstall, a rejoin or a new guild master never restarts it. Until a
-- verifier's start reaches it, a client counts from its own first sighting (ns.rdb.verify.seen).
-- Within GRACE the guild is pending: only its guild master sees "GM verification pending" (once a
-- session, reopened with /oly verify or the line on top of the Census). Past it the guild is
-- overdue: member-facing notices are temporarily paused; the guild master still sees the
-- reminder and the verifiers keep the guild on their list, marked overdue,
-- for follow-up; and while ns.VERIFY_HOLD is on (Core.lua, as it ships) its guild master's own
-- powers wait for his verification (ns.MasterHeld: Data.AuthorizedRank gives him an officer's
-- standing; his public card, his Legates and correspondents, his guild decrees and his guild bank
-- grant wait too). Nothing is taken from the members; nobody is removed.
--
-- The verifiers (the King, the High Council, the author) see the pending and overdue guilds in The
-- Watch (Guilds), are told once of each new pending guild (and of each new guild master to check),
-- and once more REMIND_LEFT before its deadline, to tell a guild master who has no addon to install
-- it and verify.
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
Verify.GRACE = 48 * 3600         -- a guild's grace, from its start
Verify.REMIND_LEFT = 12 * 3600   -- the verifiers are reminded of a pending guild this long before its deadline
Verify.NOTICE_AFTER = 90         -- the session's notices wait this long after login (roster and census in)
Verify.TICK = 60                 -- the guilds seen and the notices, every minute
Verify.ASK_AFTER, Verify.ASK_SPREAD = 25, 35 -- the login's ask, 25 to 60 s after it
Verify.ASK_EVERY = 30 * 60       -- and every half hour
Verify.ANSWER_GAP = 180          -- a verifier's client answers asks this often at most
Verify.REQUEST_GAP = 300         -- a guild master's queued request, kept across reloads
Verify.REVOKE_KEEP = 30 * 86400  -- a revocation is kept (and relayed) this long
Verify.START_KEEP = 90 * 86400   -- a guild's start, this long after it was last seen or heard
Verify.SEEN_KEEP = 30 * 86400    -- a guild's own first sighting, this long after it was last seen
Verify.MAX = 400                 -- words kept (past it: the oldest revocations, then the oldest approvals)
Verify.MAX_STARTS = 600          -- starts kept, and first sightings (past it: the longest unseen go)
Verify.MAX_ROWS = 240            -- rows in one answer
Verify.MAX_BYTES = ns.Codec.CHUNK * ns.Codec.MAX_CHUNKS
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

local stats = { taken = 0, starts = 0, refused = 0, bad = 0, asked = 0, answered = 0 }
function Verify.Stats() return stats end

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
--   revoked, since (its start), shared (a verifier's start), left (seconds before its deadline) }.
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
	info.left = since + Verify.GRACE - now
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
-- GuildCharter, Nominees, Decree and Bank ask it. Never the King's guild. Asked often: kept a second.
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
function Verify.SendSnapshot()
	if Quiet() or not ns.IsMember() or not Verify.Trusted(ns.me) then return false end
	local payload, n = Verify.Payload()
	if n == 0 then return false end
	local key = "verify-snapshot"
	local ok = ns.Comm.SendChunked(payload, false, "CHANNEL", nil, { owner = Verify, key = key,
		permit = function(_, guardKey, dist, target)
			if guardKey ~= key or dist ~= "CHANNEL" or target ~= nil then return false, "lane" end
			if not Verify.Trusted(ns.me) then return false, "trust" end
			return true
		end })
	if ok then
		lastSent = Verify.Clock()
		stats.answered = stats.answered + 1
	end
	return ok
end

-- An ask heard: a verifier's client with different contents answers after 2-9 s, unless another
-- verifier delivered every row we would send. A smaller answer must not silence missing decisions.
local function AnswerAsk(body, now)
	if Quiet() or not ns.IsMember() or not Verify.Trusted(ns.me) then return true end
	if pending or now - lastSent < Verify.ANSWER_GAP then return true end
	local mine, _, _, fingerprint = Verify.Digest()
	if mine == 0 then return true end
	local n, theirs, theirSum, theirFingerprint = tostring(body or ""):match("^(%d+)~(%d+)~(%d+)~(%x+)$")
	if not n then n, theirs, theirSum = tostring(body or ""):match("^(%d+)~(%d+)~(%d+)$") end
	n, theirs, theirSum = tonumber(n), tonumber(theirs), tonumber(theirSum)
	if not n or n > Verify.MAX + Verify.MAX_STARTS or theirs > now + Verify.AHEAD
		or theirSum >= 2147483648 or (theirFingerprint and #theirFingerprint ~= 64) then return false end
	if fingerprint and fingerprint == theirFingerprint then return true end
	-- A legacy ask cannot prove that it holds our words, even with equal counts.
	-- ANSWER_GAP and the delayed/coalesced answer still bound recovery traffic.
	local request = {}
	pending = request
	ns.After(Verify.random(2, 9), "verify answer", function()
		pending = false
		if Verify.Clock() - lastSent < Verify.ANSWER_GAP then return end
		if request.coverage then
			local _, _, covered = Verify.Payload(nil, request.coverage)
			if covered then return end
		end
		Verify.SendSnapshot()
	end)
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
	if dist ~= "CHANNEL" or type(sender) ~= "string" or sender == "" or type(text) ~= "string" then return false end
	local ver, kind, body = text:match("^GV~(%d+)~(%u)~(.*)$")
	if tonumber(ver) ~= Verify.PROTOCOL then return false end
	local now = Verify.Clock()
	sender = ns.FullName(sender)
	if kind == "Q" then return AnswerAsk(body, now) end
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
		local made, rows = body:match("^(%d+)~(.*)$")
		if not TimeField(made) then
			stats.bad = stats.bad + 1
			return false
		end
		local realm = ns.RealmOf(sender)
		local count, changed, bad = 0, false, false
		local coverage = pending and {} -- only while answering; at most MAX_ROWS received entries
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

local function SayWhy(why, guild)
	if why == "trust" then return ns.Print(L.VERIFY_ONLY) end
	if why == "master" then return ns.Print(L.VERIFY_NO_MASTER:format(guild)) end
	if why == "none" then return ns.Print(L.VERIFY_NOTHING:format(guild)) end
	if why == "older" then return ns.Print(L.VERIFY_REFUSED:format(guild)) end
	return ns.Print(L.VERIFY_BAD_GUILD)
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
-- requests across reloads without renewing the 48-hour verification deadline.
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
	if status == "pending" then return ns.Print(L.VERIFY_STATUS_GRACE:format(guild, Verify.Duration(info.left))) end
	return ns.Print(L.VERIFY_STATUS_LATE:format(guild))
end

---------------------------------------------------------------------------
-- The verifiers' page: The Watch's Guilds (Watch.lua), and their notices
---------------------------------------------------------------------------

function Verify.CouncilShown()
	return ns.IsMember() and Verify.Trusted(ns.me)
end

-- The guilds still to verify (the census's and our own; overdue first, then the least time left,
-- then the biggest) and the verified ones (by name), each { guild, status, info, total }.
function Verify.Pending(now)
	now = now or Verify.Clock()
	local pending, verified, done = {}, {}, {}
	local function Add(guild)
		if type(guild) ~= "string" then return end
		local key = Key(guild)
		if done[key] then return end
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
-- chat line for each kind, naming the guilds.
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
		if r.status == "pending" and r.info.left <= Verify.REMIND_LEFT and not t.remind then
			t.remind = now
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

function Verify.CouncilLines(now)
	if not Verify.CouncilShown() then return {} end
	now = now or Verify.Clock()
	local pending, verified = Verify.Pending(now)
	local lines = {
		{ id = "verify-council", header = true, text = L.VERIFY_COUNCIL_TITLE, right = Grey(#pending) },
		{ text = Grey(L.VERIFY_COUNCIL_SCOPE), wrap = true },
		{ id = "verify-copy", text = Gold(L.VERIFY_COUNCIL_COPY), onClick = function() Verify.ShowList() end, gapAfter = true },
	}
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
			onClick = function() Verify.AskGuild(r) end,
		}
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
			onClick = function()
				ns.ShowDialog("OLYMPUS_VERIFY_REVOKE", L.VERIFY_REVOKE_PROMPT:format(r.guild, Shown(e.gm)), nil, { guild = r.guild })
			end,
		}
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
	OnAccept = function(_, data)
		ns.SafeCall("verify revoke", function()
			if type(data) == "table" then Verify.RevokeInput(data.guild) end
		end)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
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
	ns.After(Verify.ASK_AFTER + Verify.random(0, Verify.ASK_SPREAD), "verify ask", Verify.Ask)
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
