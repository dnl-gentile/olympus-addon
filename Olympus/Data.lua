local ADDON, ns = ...
local L = ns.L

-- Holds one report per Olympus guild (ours from the roster, others from the channel)
-- and aggregates them into the numbers the UI and the map show.

local Data = {}
ns.Data = Data

Data.FRESH = 15 * 60           -- older: shown grey, its online players and zones leave the totals
Data.KEEP = 7 * 24 * 60 * 60   -- older than this is forgotten (the guild still listed, grey, until then)
Data.TOTAL_KEEP = 24 * 60 * 60 -- a guild's size counts in the army's total this long after its last report
Data.VOUCH_TTL = 30 * 60       -- a report counts as its sender's vote on the guild this long
Data.CLAIM_TTL = 15 * 60       -- a sender quiet this long for its guild may speak for another one
local MAX_VOUCH = 8            -- votes kept per guild (the newest)
-- 1.2.1: the reports kept, at most, ours among them. Any guild whose name holds "Olympus" is an
-- Olympus guild, so characters to spare (one guild each every CLAIM_TTL) could fill the saved
-- variables with guilds that do not exist, each kept for KEEP. Past it the report heard longest ago
-- goes (Data.Trim): a real guild reports every few minutes while anyone of it is on, so a forger's
-- old names go first. Never our own guild's, nor the King's guild or one the author's signed list
-- approves while another can go. Several times the guilds any realm group has.
Data.MAX_GUILDS = 300

-- 1.2.1 (the stutter players reported, measured on the owner's PC): every census report heard,
-- about one a second and up to nine in a burst, ran every DATA_CHANGED listener at once, inside
-- the game's addon-message event. A report heard from someone else now marks the census changed,
-- and DATA_CHANGED follows within NOTIFY_GAP, once for every report heard meanwhile (one timer
-- waits at a time); so does our own roster's report, read once a minute, on a frame of its own
-- rather than the scan's. What the player does himself (a /who, /oly reset, a realm linked) still
-- fires it at once. Data.Revision(): a number that grows with every change to the census's
-- reports, for what is worked out from them and kept (HonorsNet's level race).
-- Every report taken is seen by the listeners before it is replaced: a guild's row is its newest
-- report, and a listener reads the rows as they stand (the level race keeps each sender it sees on
-- a claim), so a second report of one guild within NOTIFY_GAP tells the first one's DATA_CHANGED
-- at once, before it takes its place, as every report did before 1.2.1.
Data.NOTIFY_GAP = 1
local revision, notifyQueued, notifyDirty = 0, false, false
local unseen = {} -- the rows taken since DATA_CHANGED last went out (emptied each time it does)
function Data.Revision() return revision end
local function Tell()
	notifyDirty = false
	for row in pairs(unseen) do unseen[row] = nil end
	ns.Fire("DATA_CHANGED")
end
local function Notify()
	notifyQueued = false
	if not notifyDirty then return end -- (fired at once meanwhile: Data.ChangedNow, or a row replaced)
	Tell()
end
-- A change heard from someone else, or our roster's: DATA_CHANGED within NOTIFY_GAP. row: the
-- report just taken, which the listeners see before another takes its place.
function Data.ChangedSoon(row)
	revision = revision + 1
	notifyDirty = true
	if row ~= nil then unseen[row] = true end
	if notifyQueued then return end
	notifyQueued = true
	ns.After(Data.NOTIFY_GAP, "census changed", Notify)
end
-- A change the player made: DATA_CHANGED now, which answers for what was waiting too.
function Data.ChangedNow()
	revision = revision + 1
	Tell()
end

-- The key a guild is stored under, whatever the case a report spells it in: a realm has one
-- guild of a name, so "OLYMPUS X" and "Olympus X" are the same one (or one is forged).
function Data.GuildKey(name)
	if type(name) ~= "string" then return nil end
	local guilds = ns.rdb and ns.rdb.guilds
	if not guilds then return nil end
	if guilds[name] then return name end
	local lower = name:lower()
	for key in pairs(guilds) do
		if type(key) == "string" and key:lower() == lower then return key end
	end
	return nil
end
function Data.Guild(name)
	local key = Data.GuildKey(name)
	return key and ns.rdb.guilds[key] or nil
end

-- (1.2.3) About 40 census reports a minute reach a client, and each one was decoded and voted from
-- scratch: some 11 KB of garbage each for the collector, what the owner's PC felt as memory peaks.
-- Many come out as their sender's last one did, but for field 25 (the server time it was made,
-- stamped at every roster read: Codec.ReportTime). So each sender's last report taken is kept as
-- it came, its text but for that time, with the row it made, while that row is still its guild's:
-- the same report again is that row again (Data.DecodeReport), not decoded. Data.Receive takes it
-- as any report, from the same checks to the votes counted again: the row gets the new time and
-- its sender's vote a new time, what a new report alike but for its time made of it. One per
-- sender, gone with its row (the guild's report from anyone else, Data.Trim, a reset or another
-- realm's store) or once that row is FRESH old (Data.Housekeeping), so MAX_GUILDS at most. Only a
-- report whose guild is spelled as its row's key is kept (the checks read the spelling it gives).
local repeats = {} -- "Name-Realm" -> { head, tail, row, vote }: his report's text around field 25
local heard = {} -- what Data.DecodeReport gave last (r, who, text, at, stop, st, again, entry), for Data.Receive
-- A row that goes, or another report replaces: its sender's report is not the guild's any more.
local function Forget(row)
	local who = type(row) == "table" and row.reporterFull
	local e = type(who) == "string" and repeats[who]
	if e and e.row == row then repeats[who] = nil end
end

-- (1.2.1) The store at MAX_GUILDS reports less `room` (0, or 1 before a new guild goes in): the
-- reports heard longest ago go, the King's guild and the approved ones only once no other is
-- left, our own never. Returns how many went.
local trimmed = 0
function Data.Trim(room)
	local guilds = ns.rdb and ns.rdb.guilds
	if type(guilds) ~= "table" then return 0 end
	local count = 0
	for _ in pairs(guilds) do count = count + 1 end
	local over = count + (room or 0) - Data.MAX_GUILDS
	if over <= 0 then return 0 end
	local list = {}
	for name, g in pairs(guilds) do
		if not (type(g) == "table" and g.mine) then
			local kept = type(name) == "string" and (ns.IsKingGuild(name) or (ns.IsApprovedGuild ~= nil and ns.IsApprovedGuild(name)))
			list[#list + 1] = { name = name, t = type(g) == "table" and tonumber(g.t) or -math.huge, kept = kept and 1 or 0 }
		end
	end
	table.sort(list, function(a, b)
		if a.kept ~= b.kept then return a.kept < b.kept end
		if a.t ~= b.t then return a.t < b.t end
		return tostring(a.name) < tostring(b.name)
	end)
	local n = math.min(over, #list)
	for i = 1, n do
		Forget(guilds[list[i].name])
		guilds[list[i].name] = nil
	end
	trimmed = trimmed + n
	if n > 0 then revision = revision + 1 end
	return n
end
function Data.Trimmed() return trimmed end -- (this session: /oly status)

-- Where the King is pinned by name (ns.KING_CHARACTER), a report of his guild that names
-- anyone else as its leader (or nobody) is not his guild's: forged, or out of date.
function Data.OtherKing(guild, leader)
	return ns.IsKingGuild(guild) and ns.KingCharacter() ~= nil and not ns.IsKingCharacter(leader)
end

-- (1.2.3) Every report's vote stays in its row until the guild's next report counts the votes again
-- (Votes, Data.Receive), so the rows of guilds not heard since kept theirs, past VOUCH_TTL, in
-- memory and in the saved variables (71 of the owner's 300). Those no count takes any more go at
-- INIT and at logout: older than VOUCH_TTL (Votes, Majority; DuesHistory reads 90 s of them).
local function DropDeadVotes(now)
	for _, g in pairs(ns.rdb and ns.rdb.guilds or {}) do
		local vouch = type(g) == "table" and g.vouch
		if type(vouch) == "table" then
			for sender, v in pairs(vouch) do
				if type(v) ~= "table" or now - (tonumber(v.t) or 0) > Data.VOUCH_TTL then vouch[sender] = nil end
			end
			if next(vouch) == nil then g.vouch = nil end
		end
	end
end
ns.On("LOGIN", function() ns.RegisterEvent("PLAYER_LOGOUT", function() DropDeadVotes(ns.Now()) end) end)

ns.On("INIT", function()
	local now = ns.Now()
	for name, g in pairs(ns.rdb.guilds) do
		if type(g) ~= "table" or now - (g.t or 0) > Data.KEEP then
			ns.rdb.guilds[name] = nil
		elseif ns.Codec.Dirty(name) or ns.Codec.Dirty(g) then
			-- Kept by versions before 0.9.2, which let escape codes (colours, textures, links)
			-- and control bytes in from the channel: the guild's next report (stripped now,
			-- Comm.lua) takes its place, and ours comes back from the roster.
			ns.Log("dropped guild %s: escape codes in its report", ns.Codec.Plain(name))
			ns.rdb.guilds[name] = nil
		elseif not g.mine and Data.OtherKing(name, g.leader) then
			-- Kept from before the King was pinned: the next real report takes its place.
			ns.Log("dropped guild %s: names %s its leader, not the King", name, tostring(g.leader))
			ns.rdb.guilds[name] = nil
		end
	end
	-- Kept by older versions: a report bigger than a guild can be (forged), and one guild under
	-- two spellings (the newer one stays). Collected first: pairs() must not see removals twice.
	local drop, byLower = {}, {}
	for name, g in pairs(ns.rdb.guilds) do
		if (tonumber(g.total) or 0) > ns.Codec.GUILD_CAP then
			drop[#drop + 1] = name
		else
			local other = byLower[name:lower()]
			if other then
				local older = (g.t or 0) < (ns.rdb.guilds[other].t or 0) and name or other
				drop[#drop + 1] = older
				if older == other then byLower[name:lower()] = name end
			else
				byLower[name:lower()] = name
			end
		end
	end
	for _, name in ipairs(drop) do
		ns.Log("dropped guild %s: forged size or a second spelling", name)
		ns.rdb.guilds[name] = nil
	end
	-- (1.2.1) Kept by older versions, without a cap: MAX_GUILDS at most from now on.
	local over = Data.Trim(0)
	if over > 0 then ns.Log("census: %d guild reports heard longest ago let go (%d kept at most)", over, Data.MAX_GUILDS) end
	DropDeadVotes(now) -- (1.2.3)
	local seen = Data.Seen()
	for name, e in pairs(seen) do
		if type(e) ~= "table" or now - (e.t or 0) > Data.KEEP then seen[name] = nil end
	end
	-- Sightings kept before v0.7.11 may carry a "-Realm" of our census group on the guild's
	-- name (Who.GuildName): they go under its plain name, the newest one kept, or the guild
	-- would show twice. Collect first: pairs() must not see new keys.
	local renamed = {}
	for name in pairs(seen) do
		local base = type(name) == "string" and ns.Who.GuildName and ns.Who.GuildName(name)
		if base and base ~= name then renamed[#renamed + 1] = { name, base } end
	end
	for _, pair in ipairs(renamed) do
		local e, old = seen[pair[1]], seen[pair[2]]
		seen[pair[1]] = nil
		if type(old) ~= "table" or (e.t or 0) > (old.t or 0) then seen[pair[2]] = e end
	end
end)

-- Olympus guilds seen online with /who (census Refresh, Join screen), per realm:
-- [guild] = { online = players seen, capped = more may be online, t }. Kept apart from the
-- reports on purpose: a sighting knows no members, leader or zones, never counts in the
-- totals, and must never pass for a report (the conflict and rank checks trust
-- ns.rdb.guilds). The census lists the guilds seen that nobody reports, in grey.
function Data.Seen()
	ns.rdb.seen = ns.rdb.seen or {}
	return ns.rdb.seen
end

-- players: the Olympus players of the current round of /who searches (Who.lua), each once.
-- Players of other realms count too: /who only lists who shares our world, and on the
-- Forever beta Olympus guilds span PvP and PvP 2, so everyone we can see belongs here.
function Data.RecordSightings(players, capped)
	local count = {}
	for _, p in ipairs(players or {}) do
		if ns.IsFederation(p.guild) then
			count[p.guild] = (count[p.guild] or 0) + 1
		end
	end
	local seen, now = Data.Seen(), ns.Now()
	for guild, n in pairs(count) do seen[guild] = { online = n, capped = capped or nil, t = now } end
	if next(count) then Data.ChangedNow() end -- (a /who: the player's own click)
end
ns.Who.Listen(Data.RecordSightings)

-- The server's clock (1.0.0), the same second on every realm, where ns.Now() is this computer's:
-- nil on a client without it.
function Data.ServerTime()
	if type(GetServerTime) ~= "function" then return nil end
	local ok, t = pcall(GetServerTime)
	return ok and type(t) == "number" and t > 0 and t or nil
end

-- Two reports alike but for when they were made (t, st), their tables compared value by value.
local WHEN = { t = true, st = true }
local function SameReport(a, b, depth)
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" or depth > 4 then return false end
	for k, v in pairs(a) do
		if not (depth == 0 and WHEN[k]) and not SameReport(v, b[k], depth + 1) then return false end
	end
	for k in pairs(b) do
		if not (depth == 0 and WHEN[k]) and a[k] == nil then return false end
	end
	return true
end

-- (1.2.1) The roster is read once a minute, and some minutes our guild's report comes out as the
-- last one did: stored (its time is new) with no DATA_CHANGED, so nothing is worked out again for
-- it. Only against the report stored by this session: the first one after login, a /oly reset or
-- another realm's store (Core.lua's ns.LinkRealms) is always news. A report that changed (most
-- minutes in a big guild: who is online, where, at what level) tells DATA_CHANGED within
-- NOTIFY_GAP (Data.ChangedSoon), never inside the scan (Roster.TryScan), so the scan and the
-- listeners land on different frames.
local lastLocal
function Data.SetLocal(r)
	r.t = ns.Now()
	r.st = Data.ServerTime() -- field 25 of our report: when it was made, by the server's clock
	r.reporter = ns.DisplayName(ns.me)
	r.reporterFull = ns.me
	r.realm = ns.realm
	r.from = ns.realm -- travels in the report: whoever hears it on another realm sees the channel shared (/oly status)
	r.heardOn = ns.realm -- see Data.Receive
	r.mine = true
	local old = ns.rdb.guilds[r.guild]
	if old == nil then Data.Trim(1) end -- (1.2.1: MAX_GUILDS)
	ns.rdb.guilds[r.guild] = r
	local same = old ~= nil and old == lastLocal and SameReport(old, r, 0)
	lastLocal = r
	if not same then Data.ChangedSoon() end
end

-- Sender names are set by the server and cannot be forged, so we tie every sender to the
-- one guild it reports. A (modified) client that reports several guilds is ignored, and a
-- guild whose reports disagree about its leader or its officers is flagged as a conflict (the
-- census marks it, and sizes that disagree too: Data.Dispute, 1.1).
-- (1.2.3) Every sender heard stayed, a table each, for the whole session. A claim CLAIM_TTL old
-- binds nobody: once a minute (Data.Housekeeping) it keeps only the guild it spoke for, which
-- Data.ClaimedGuild still answers for the rest of the session, as before (the council copy of a
-- report from a sender quiet since, Watch.lua; a guild master's mark on his Trade lines, Borders.lua).
-- None is dropped: an old claim is a slot here holding its guild's one name string.
local senderGuild = {} -- "Name-Realm" -> { guild, t }, or the guild alone once CLAIM_TTL old

-- One guild per sender, shared by reports and chat: a name that speaks for one guild can't
-- speak for another. A player who really moved guilds speaks again after CLAIM_TTL quiet.
function Data.ClaimGuild(sender, guild)
	local who, now = ns.FullName(sender), ns.Now()
	local c = senderGuild[who]
	if type(c) ~= "table" then
		senderGuild[who] = { guild = guild, t = now }
		return true
	end
	if c.guild:lower() ~= guild:lower() and now - c.t < Data.CLAIM_TTL then return false end
	c.guild, c.t = guild, now -- (1.2.3: his claim's own table, not a new one each report or line)
	return true
end

-- The guild a sender's own messages speak for (Data.ClaimGuild: his chat lines, census reports,
-- board posts, decrees, crafters' listings), nil when none was heard this session. A lookup:
-- nothing is claimed (1.1.5, the game's chat marks, Borders.lua).
function Data.ClaimedGuild(sender)
	if type(sender) ~= "string" or sender == "" then return nil end
	local c = senderGuild[ns.FullName(sender)]
	if type(c) == "table" then return c.guild end
	return c
end

-- Every rank a report names, as "Name-Realm" -> 0 (leader) or 1 (officer). Names without a
-- realm belong to the reporter's realm, so a same-named player from another realm never matches.
local function Ranks(g)
	local home, out = g.realm or ns.realm, {}
	for _, o in ipairs(g.officers or {}) do out[ns.FullName(o.name, home)] = 1 end
	if g.leader then out[ns.FullName(g.leader, home)] = 0 end
	return out
end

-- The guild as a report pictures it: leader and officers, names in "Name-Realm" form so the
-- same people match whatever realm each reporter plays on. A list cut at MAX_OFFICERS is
-- pictured by its leader only (two cut lists need not hold the same officers).
local function Signature(r, ranks)
	local cut = #(r.officers or {}) >= ns.Codec.MAX_OFFICERS
	local parts = {}
	for name, rank in pairs(ranks) do
		if rank == 0 or not cut then parts[#parts + 1] = name .. "=" .. rank end
	end
	table.sort(parts)
	return table.concat(parts, ",") .. (cut and ",+" or "")
end

-- The votes kept for a guild: one per sender (its newest report), for VOUCH_TTL, the newest
-- MAX_VOUCH. Votes of older versions (no signature) are dropped.
local function Votes(map, now)
	local list, out = {}, {}
	for sender, v in pairs(map or {}) do
		if type(v) == "table" and v.sig and v.ranks and now - (v.t or 0) <= Data.VOUCH_TTL then
			list[#list + 1] = { sender = sender, v = v }
		end
	end
	table.sort(list, function(a, b) return a.v.t > b.v.t end)
	for i = 1, math.min(MAX_VOUCH, #list) do out[list[i].sender] = list[i].v end
	return out
end

-- The picture most senders agree on right now, its count, and every picture with that many
-- senders (`tops`). `top` is nil when there is none, or when two pictures have as many
-- senders each: then the guild is contested, and only what all of them agree on counts.
local function Majority(votes, now)
	local count = {}
	for _, v in pairs(votes) do
		if now - (v.t or 0) <= Data.VOUCH_TTL then count[v.sig] = (count[v.sig] or 0) + 1 end
	end
	local best, tops = 0, {}
	for sig, n in pairs(count) do
		if n > best then best, tops = n, { [sig] = true } elseif n == best then tops[sig] = true end
	end
	local top, n = nil, 0
	for sig in pairs(tops) do top, n = sig, n + 1 end
	if n ~= 1 then top = nil end
	return top, best, tops
end
Data.Majority = Majority -- for /oly status and tests

-- Votes heard on one channel say nothing on another (the public channel lets anyone vote):
-- called when we move to another channel, e.g. when the realm key arrives.
function Data.ForgetVotes()
	for _, g in pairs(ns.rdb and ns.rdb.guilds or {}) do
		if type(g) == "table" then g.vouch, g.conflict, g.outvoted = nil, nil, nil end
	end
	revision = revision + 1
end

-- What the census's mark on a row says (1.1, Fern's #30): its senders split on the guild's leader
-- or officers (`split`: no picture leads; `outvoted`: a sender's report is not what the others
-- say), two fresh senders give sizes farther apart than SIZE_SLACK or SIZE_SHARE of the bigger
-- plus SIZE_DRIFT a minute between their two reports (`sizes`: the pair farthest past that, the
-- smaller first, { sender, n } each; the reporter speaks every 3 minutes and the runner-up every
-- 10, and a guild that fills, or has its inactive members removed, changes meanwhile), or one
-- sender alone stands behind it (`single`: that sender). nil
-- when nothing is to say: our own guild (our roster, the server's word), and a report older than
-- FRESH (grey already, and out of the online counts). It changes nothing that counts; a marked
-- row can still be the true one.
Data.SIZE_SLACK, Data.SIZE_SHARE = 5, 0.05
Data.SIZE_DRIFT = 20 -- members a minute (one removal per Members.REMOVE_GAP, 3 s, is 20)
function Data.Dispute(g, now)
	if type(g) ~= "table" or g.mine then return nil end
	now = now or ns.Now()
	if now - (g.t or 0) > Data.FRESH then return nil end
	local d, senders, count, sized = {}, {}, 0, {}
	for src, v in pairs(Votes(g.vouch, now)) do
		local short = ns.ShortName(src)
		if not senders[short] then senders[short], count = src, count + 1 end
		if type(v.n) == "number" and now - (v.t or 0) <= Data.FRESH then sized[#sized + 1] = { sender = src, n = v.n, t = v.t or 0 } end
	end
	d.split = g.conflict and true or nil
	d.outvoted = g.outvoted and true or nil
	local worst
	for i = 1, #sized do
		for j = i + 1, #sized do
			local lo, hi = sized[i], sized[j]
			if lo.n > hi.n or (lo.n == hi.n and lo.sender > hi.sender) then lo, hi = hi, lo end
			local past = hi.n - lo.n - math.max(Data.SIZE_SLACK, hi.n * Data.SIZE_SHARE) - Data.SIZE_DRIFT * math.abs(hi.t - lo.t) / 60
			if past > 0 and (not worst or past > worst.past or (past == worst.past and lo.sender .. hi.sender < worst.key)) then
				worst = { past = past, key = lo.sender .. hi.sender, lo = lo, hi = hi }
			end
		end
	end
	if worst then d.sizes = { { sender = worst.lo.sender, n = worst.lo.n }, { sender = worst.hi.sender, n = worst.hi.n } } end
	if count <= 1 then d.single = next(senders) and senders[next(senders)] or g.reporterFull or g.reporter or "?" end
	d.disputed = (d.split or d.outvoted or d.sizes) and true or nil
	if not (d.disputed or d.single) then return nil end
	return d
end

-- No Crown from other guilds' votes until a full reporting cycle has passed since login: a
-- guild's reporter and runner-up must have had the time to vote before outsiders can win.
Data.CROWN_AFTER = 200

-- The census after login (1.1): the beta often loads an empty save, and an empty window reads as
-- "the army is gone", which sends players into /reload after /reload. The census refills on its
-- own: the channel is joined within 15 s, every guild's reporter answers the census request (Q1,
-- Comm.AskCensus) or reports within 170 s. For REBUILD_FOR after login the window says so, with
-- how many guilds were heard since. A line and nothing else: no /who (the game takes it from a
-- click alone), no window or popup of any kind.
Data.REBUILD_FOR = 200

-- The guilds heard since login while the census is being rebuilt (0 or more), nil once it is
-- (or outside an Olympus guild, or before login).
function Data.Rebuilding(now)
	local login = ns.Comm and ns.Comm.loginAt
	if not login or not ns.IsMember() then return nil end
	now = now or ns.Now()
	if now - login >= Data.REBUILD_FOR then return nil end
	local heard = 0
	for _, g in pairs(ns.rdb and ns.rdb.guilds or {}) do
		if type(g) == "table" and not g.mine and (g.t or 0) >= login then heard = heard + 1 end
	end
	return heard
end

-- At login: the window drawn once more when the rebuild is over, so its line goes. That redraw
-- is all it does (UI.RefreshSoon searches nothing, and does nothing while the window is closed).
function Data.OnLogin()
	ns.After(Data.REBUILD_FOR + 1, "census rebuilt", function()
		if ns.UI and ns.UI.RefreshSoon then ns.UI.RefreshSoon() end
	end)
end
ns.On("LOGIN", function() Data.OnLogin() end)

-- 1.1: a guild the moderators took off the network (net-off, Moderation.lua): not counted, not listed.
local function NetOff(guild)
	local M = ns.Moderation
	return M ~= nil and M.Guild ~= nil and M.Guild(guild) ~= nil
end
Data.NetOff = NetOff

-- (1.2.3) A census report heard on the channel (Comm.lua), as Codec.DecodeReport reads it; or, when
-- it is its sender's last report taken but for its time, the row that report made, as it stands
-- (Data.Receive takes it as that report again). nil for a text that is no report.
function Data.DecodeReport(text, sender)
	local who = ns.FullName(sender)
	local at, stop, st = ns.Codec.ReportTime(text)
	heard.r, heard.who, heard.text, heard.at, heard.stop, heard.st = nil, who, text, at, stop, st
	heard.again, heard.entry = false, nil
	local e = at and repeats[who]
	if e then
		local guilds = ns.rdb and ns.rdb.guilds
		local row = e.row
		if type(guilds) ~= "table" or guilds[row.guild] ~= row or row.heardOn ~= ns.realm then
			repeats[who] = nil -- (its row went)
		-- The same text but for field 25, compared where it lies: nothing is cut out of it for that.
		elseif at == #e.head and #text - stop + 1 == #e.tail and text:find(e.head, 1, true) == 1
			and (e.tail == "" or text:find(e.tail, stop, true) == stop) then
			heard.r, heard.again, heard.entry = row, true, e
			return row
		end
	end
	heard.r = ns.Codec.DecodeReport(text)
	if heard.r == nil then heard.text = nil end
	return heard.r
end

-- A report from a sender (r: from Codec.DecodeReport, or Data.DecodeReport), taken or not.
-- h: what Data.DecodeReport kept of it, when r came from there.
local function Take(r, sender, h)
	-- (1.2.3) r is the row of his last report, which that same report again finds as it stands: it
	-- keeps its time and votes until it is taken (the listeners, an outvoted report, see it so).
	local again = h ~= nil and h.again
	if not ns.IsFederation(r.guild) then return false end
	-- 1.1: a guild the moderators took off (net-off): its report counts for nothing, not even as a vote.
	if ns.Moderation.Report and ns.Moderation.Report(r, sender) then return false end
	-- Our own guild comes straight from our roster, never from someone else's claim (in any spelling).
	local mine = GetGuildInfo("player")
	if mine and r.guild:lower() == mine:lower() then return false end
	local who = ns.FullName(sender)
	-- The other faction's Olympus guilds are not ours to count (their channel is another one;
	-- this only matters if a report reaches ours anyway).
	if (r.faction or "Alliance") ~= (ns.faction or "Alliance") then
		ns.Log("ignored %s from %s: a %s guild", r.guild, who, tostring(r.faction))
		return false
	end
	-- The King's guild is led by the King: where he is pinned by name, a report naming anyone
	-- else at its head counts for nothing, not even as a vote. It can't replace the row
	-- everyone sees, nor outvote the real reporters (GitHub issue #18).
	if Data.OtherKing(r.guild, r.leader) then
		ns.Log("ignored %s from %s: names %s its leader, not the King", r.guild, who, tostring(r.leader))
		return false
	end
	if not Data.ClaimGuild(who, r.guild) then
		ns.Log("ignored %s: already reported %s, now claims %s", who, Data.ClaimedGuild(who) or "?", r.guild)
		return false
	end
	-- One guild whatever the case it is spelled in: the spelling already stored is its key, and
	-- a report under another spelling is one more vote on that guild.
	local spelled = r.guild
	r.guild = Data.GuildKey(r.guild) or r.guild
	local previous = ns.rdb.guilds[r.guild]
	-- Realms of one census group share this store, but a name without a realm takes the realm
	-- of the character that heard it. A report heard on another realm of the group names people
	-- in that realm's form: compared with ours, the same reporter and officers would look new
	-- (a false conflict), so here it counts as no report at all.
	if previous and previous.heardOn and previous.heardOn ~= ns.realm then previous = nil end
	local now = ns.Now()
	if not again then -- (his same report again: its row says all this already)
		r.t = now
		r.reporter = ns.DisplayName(who)
		r.reporterFull = who
		r.heardOn = ns.realm
		-- The realm of the sender's name as we got it, not the report's `from`: a report's short
		-- names are compared with senders in that same form (a sender that reaches us without a
		-- realm carries ours, whatever realm it plays on).
		r.realm = ns.RealmOf(who) or ns.realm
	end
	-- Every report is its sender's vote on who leads the guild and who its officers are. Ranks
	-- count only from the picture most senders agree on (Data.KnownRank): one sender changing
	-- or repeating a report can't move it, and two pictures with as many senders each are a
	-- contest where no rank counts. Nothing here needs saved history (the Forever beta client
	-- never loads it back).
	local votes = Votes(previous and previous.vouch, now)
	local vote
	if again then
		-- (1.2.3) His last vote's picture: the same leader, officers and size give the same one.
		local last = h.entry.vote
		vote = { t = now, sig = last.sig, ranks = last.ranks, n = last.n }
	else
		local ranks = Ranks(r)
		-- n (1.1): the size this sender gives, for the census's dispute mark (Data.Dispute).
		vote = { t = now, sig = Signature(r, ranks), ranks = ranks, n = tonumber(r.total) }
		r.vouch = votes
	end
	votes[who] = vote
	local top, _, tops = Majority(votes, now)
	-- Against the picture most senders give while that picture is fresh: the vote counts, the
	-- row everyone sees (and the King's guild's leader with it) stays the majority's.
	if previous and top and vote.sig ~= top and now - (previous.t or 0) <= Data.FRESH then
		previous.vouch = votes
		if not previous.outvoted then ns.Log("conflict on %s: %s's report is not what the other senders say", r.guild, who) end
		previous.outvoted = true
		if again then h.entry.vote = vote end
		Data.ChangedSoon() -- (1.2.1: within NOTIFY_GAP, once for a burst)
		return false
	end
	-- Shown in the census: the senders are split on this guild (no picture leads).
	local pictures = 0
	for _ in pairs(tops) do pictures = pictures + 1 end
	local conflict = (top == nil and pictures > 1) and true or nil
	if conflict and not (previous and previous.conflict) then
		ns.Log("conflict on %s: the senders are split on it", r.guild)
	end
	-- (1.2.1) A guild not kept yet: room for it first (MAX_GUILDS, Data.Trim).
	local stored = ns.rdb.guilds[r.guild]
	if stored == nil then Data.Trim(1) end
	-- (1.2.1) Its row taken since DATA_CHANGED last went out: the listeners see it now, before
	-- this one replaces it (one guild heard twice within NOTIFY_GAP).
	if stored ~= nil and unseen[stored] then Tell() end
	-- (1.2.3) His same report again: its row as a new report alike but for its time makes it (a
	-- new time, field 25, the votes counted now, no other sender's report outvoted against it).
	if again then r.t, r.st, r.vouch, r.outvoted = now, h.st, votes, nil end
	r.conflict = conflict
	ns.rdb.guilds[r.guild] = r
	-- (1.2.3) The row it replaced is no sender's report any more; this one's text is kept for his
	-- next (Data.DecodeReport), when it came from there spelling its guild as the row's key.
	if stored ~= nil and stored ~= r and stored.reporterFull ~= who then Forget(stored) end
	if again then
		h.entry.vote = vote
	elseif h ~= nil and h.at and spelled == r.guild then
		local e = repeats[who] or {}
		e.head, e.tail, e.row, e.vote = h.text:sub(1, h.at), h.text:sub(h.stop), r, vote
		repeats[who] = e
	else
		repeats[who] = nil
	end
	Data.ChangedSoon(r) -- (1.2.1: within NOTIFY_GAP, once for a burst)
	return true
end

function Data.Receive(r, sender)
	local h = r ~= nil and heard.r == r and heard.who == ns.FullName(sender) and heard or nil
	local taken = Take(r, sender, h)
	heard.r, heard.text, heard.entry = nil, nil, nil -- (the text goes with its report)
	-- Record mode (Record.lua): a report taken may go into the witness's own file (nothing is sent).
	local record = ns.Record
	if taken and record and record.Recording and record.Recording() then ns.SafeCall("record heard", record.Heard, r) end
	return taken
end

-- (1.2.3) Once a minute, with the evening count: the claims CLAIM_TTL old keep only their guild
-- (Data.ClaimGuild), still answered by Data.ClaimedGuild; the kept reports whose row went another
-- way than a report (a reset, another realm's store) or is older than FRESH (its guild quiet) go:
-- their sender's next report is decoded, as any.
function Data.Housekeeping(now)
	now = now or ns.Now()
	for who, c in pairs(senderGuild) do
		if type(c) == "table" and now - (c.t or 0) >= Data.CLAIM_TTL then senderGuild[who] = c.guild end
	end
	local guilds = ns.rdb and ns.rdb.guilds
	for who, e in pairs(repeats) do
		if type(guilds) ~= "table" or guilds[e.row.guild] ~= e.row or now - (e.row.t or 0) > Data.FRESH then repeats[who] = nil end
	end
end
-- (Tests: how many senders' reports are kept.)
function Data.Repeats()
	local n = 0
	for _ in pairs(repeats) do n = n + 1 end
	return n
end

-- What rank does this sender really have in that guild? Our own guild: from our roster.
-- Other guilds: from that guild's report (leader = 0, officers = 1). nil = unknown.
-- soft: for what only shows (the King's layer line and crown), one report naming them is
-- enough while no other one disagrees; the Crown's powers need two. Both wait CROWN_AFTER
-- after login, when the real reports have come in (a lone forged one would be alone then).
-- Another guild's rank comes with the number of senders of the leading picture naming them,
-- theirs included (1.0.0: the borders ask two for any rank, Borders.lua).
function Data.KnownRank(sender, guild, soft)
	local who = ns.FullName(sender)
	if guild == GetGuildInfo("player") then return ns.Roster.RankOf(who) end
	if NetOff(guild) then return nil end -- (1.1: a guild off the network ranks nobody on another's client)
	local g = Data.Guild(guild)
	local now = ns.Now()
	-- A report kept from an earlier session proves nothing about who leads the guild now.
	if not g or now - (g.t or 0) > Data.FRESH then return nil end
	local votes = Votes(g.vouch, now)
	local _, _, tops = Majority(votes, now)
	-- The rank the leading picture gives (every leading picture, if they tie: then only what
	-- they all agree on counts), named by someone else too: a report never proves its own
	-- sender's rank. The Lords (every guild master, the officers of <Olympus>: ns.IsLordRank)
	-- need two senders naming them (theirs may be one).
	-- A sender is itself by its name alone: "Asmon-OtherRealm" can't vouch for "Asmon-Realm".
	local self = ns.ShortName(who)
	local bySig, total, named, others = {}, 0, 0, 0
	for src, v in pairs(votes) do
		if tops[v.sig] then
			if ns.ShortName(src) ~= self then total = total + 1 end
			local k = v.ranks[who]
			if bySig[v.sig] == nil then bySig[v.sig] = k or false end
			if k then
				named = named + 1
				if ns.ShortName(src) ~= self then others = others + 1 end
				if bySig[v.sig] and k < bySig[v.sig] then bySig[v.sig] = k end
			end
		end
	end
	local rank
	for sig in pairs(tops) do
		local k = bySig[sig]
		if not k or (rank and k ~= rank) then return nil end
		rank = k
	end
	if not rank or others < 1 then return nil end
	-- A picture cut at MAX_OFFICERS leaves the officers out of its signature: an officer needs
	-- most of the other senders of the leading picture to name them, not just one.
	if rank > 0 and others * 2 <= total then
		for sig in pairs(tops) do
			if sig:sub(-2) == ",+" then return nil end
		end
	end
	if ns.IsLordRank(guild, rank) then
		if named < 2 and not soft then return nil end
		if now - (ns.Comm and ns.Comm.loginAt or 0) < Data.CROWN_AFTER then return nil end
	end
	return rank, named
end

-- 1.2.4 (Bank.lua: a guild's snapshot held until the census can judge its sender): whether a
-- current report on `guild` (a vote of VOUCH_TTL, its sender's own among them) names `sender` at
-- `rank` or above. It proves nothing (a report never proves its own sender's rank: KnownRank); it
-- only says that more reports may.
function Data.Names(sender, guild, rank)
	local g = type(guild) == "string" and Data.Guild(guild) or nil
	if type(g) ~= "table" or type(sender) ~= "string" then return false end
	local who = ns.FullName(sender)
	for _, v in pairs(Votes(g.vouch, ns.Now())) do
		local k = v.ranks[who]
		if k and k <= rank then return true end
	end
	return false
end

-- A rank that may grant a capability. Our own guild comes from Blizzard's roster and the pinned
-- King from Core.lua. The existing census trust model remains byte-for-byte compatible until the
-- author's signed list explicitly activates Authority.lua's one-way enforcement boundary. From
-- then on every other guild requires the signed, time-bounded leadership manifest and a missing,
-- expired or revoked entry fails closed. The third result is the census support count in legacy
-- mode (Recruit.lua preserves its old two-report rule).
function Data.AuthorizedRank(sender, guild)
	if type(sender) ~= "string" or type(guild) ~= "string" or guild == "" then return nil end
	local enforcing = ns.Authority and ns.Authority.Enforced and ns.Authority.Enforced()
	-- Until an explicit author-signed marker activates the boundary, this is deliberately the
	-- old function.  In particular, keep its exact guild-name comparison, census timing and
	-- support-count results: merely installing a build that can read the extension changes no
	-- existing authority decision.
	if not enforcing then
		local rank, named = Data.KnownRank(sender, guild)
		local mine = GetGuildInfo("player")
		local source = rank ~= nil and mine ~= nil and guild == mine and "roster"
			or (rank ~= nil and "census" or nil)
		return rank, source, named
	end
	local who, mine = ns.FullName(sender), GetGuildInfo("player")
	if mine and ns.Fold(mine) == ns.Fold(guild) then
		local rank = ns.Roster.RankOf(who)
		return rank, rank ~= nil and "roster" or nil
	end
	-- A guildmate cannot simultaneously exercise a stale signed role in another guild.
	if ns.Roster.RankOf(who) ~= nil or NetOff(guild) or not ns.IsFederation(guild) then return nil end
	if ns.IsKingGuild(guild) and ns.IsKingCharacter(who) then return 0, "pinned" end
	local rank = ns.Authority.Rank(who, guild)
	return rank, rank ~= nil and "signed" or "enforced"
end

-- 1.2.4 (the author's ask: the average level shown and sorted everywhere guilds are listed, and
-- one of the first tie-breaks, a guild master's charge). A guild's average level as every client
-- shows and ranks it, in tenths: a report carries it so, cut down (Codec: math.floor(avgLevel * 10)),
-- and our own guild's, from our roster unrounded, is cut the same way here, so that this client
-- and every other show and order it alike (it was 48.0 in our own tooltip for a 47.96 the others
-- heard as 47.9). None (nil): no report yet, a report of a version that sent none (0), or what no
-- guild can have, under level 1 or over the game's highest level (a malformed or forged report:
-- the field reads up to 1000.0).
Data.AVG_LEVEL_MAX = 60 -- the highest level when the game gives none (GetMaxPlayerLevel)
local maxLevel
local function MaxLevel()
	if maxLevel then return maxLevel end
	if type(GetMaxPlayerLevel) == "function" then
		local ok, v = pcall(GetMaxPlayerLevel)
		v = ok and tonumber(v)
		if v and v >= 1 and v <= 255 and v == math.floor(v) then
			maxLevel = v
			return v
		end
	end
	return Data.AVG_LEVEL_MAX
end
function Data.AvgTenths(g)
	local v = type(g) == "table" and tonumber(g.avgLevel) or nil
	if not v or v ~= v then return nil end
	local tenths = math.floor(v * 10 + 1e-6) -- (1e-6: a report's 47.9 times 10 is 479, never 478.99...)
	if tenths < 10 or tenths > MaxLevel() * 10 then return nil end
	return tenths
end
-- As the rows show it, one decimal with the language's mark ("47.9", "47,9"); nil for none.
function Data.AvgLevelText(g)
	local tenths = Data.AvgTenths(g)
	if not tenths then return nil end
	return ("%d%s%d"):format(math.floor(tenths / 10), L.DECIMAL_MARK or ".", tenths % 10)
end
-- A guild's tenths by its name, from the census kept (0 for none: lowest), for the lists that
-- hold names alone (a zone's guilds, the map's pins, the Throne's inspection, the dues).
function Data.AvgTenthsOf(name)
	return Data.AvgTenths(Data.Guild(name)) or 0
end
-- The lists of guilds by a count of theirs (free slots, soldiers in a zone, players inspected,
-- dues paid), sorted in place: the larger first by each count named in turn; then, all alike, the
-- exact <OLYMPUS> first (the standard-bearer, as in the default order: the author's ask), then the
-- higher average level (1.2.4), then the name, so the order is the same every time. `rows`:
-- { name = <guild>, [count] = n, ... } each, its census entry as `e` where it has one (Data.Summary's:
-- read from it, else from the census kept by its name); each row gets its tenths as `avg` (0 for none).
function Data.SortGuildCounts(rows, ...)
	local counts = { ... }
	for _, r in ipairs(rows) do
		local g = type(r.e) == "table" and r.e.g or nil
		r.avg = (g and (Data.AvgTenths(g) or 0)) or Data.AvgTenthsOf(r.name)
	end
	table.sort(rows, function(a, b)
		for _, k in ipairs(counts) do
			local na, nb = tonumber(a[k]) or 0, tonumber(b[k]) or 0
			if na ~= nb then return na > nb end
		end
		local bearerA, bearerB = Data.IsStandardBearer(a.name), Data.IsStandardBearer(b.name)
		if bearerA ~= bearerB then return bearerA end
		if a.avg ~= b.avg then return a.avg > b.avg end
		return tostring(a.name) < tostring(b.name)
	end)
	return rows
end

-- The shared default order of guilds in the Census and the Realm. A current report stays
-- ahead of an old one; the army's largest guild comes first. If two guilds are the same size,
-- the exact <OLYMPUS> is the standard-bearer (1.1.5), then the higher average level breaks the
-- next tie (1.2.4: in tenths, Data.AvgTenths, as every client has it). Names make the final order
-- deterministic when a report has no average level yet.
-- (Each name is folded once, not at every comparison of every sort: the Realm's search keeps
-- its folds to the text typed.)
local guildSortNames, guildSortNamesCount = {}, 0
local function GuildSortName(name)
	local folded = guildSortNames[name]
	if not folded then
		if guildSortNamesCount >= 2048 then wipe(guildSortNames); guildSortNamesCount = 0 end
		folded = ns.Fold(name)
		guildSortNames[name] = folded
		guildSortNamesCount = guildSortNamesCount + 1
	end
	return folded
end
-- The standard-bearer: the exact <OLYMPUS> (any case), first on a tie of any order of guilds, the
-- default one's and a column's whichever way it runs, before the average level (the author's ask).
function Data.IsStandardBearer(name)
	return type(name) == "string" and GuildSortName(name) == "olympus"
end
function Data.GuildDefaultLess(a, b)
	if a.fresh ~= b.fresh then return a.fresh end
	local totalA, totalB = a.g.total or 0, b.g.total or 0
	if totalA ~= totalB then return totalA > totalB end
	local nameA, nameB = GuildSortName(a.name), GuildSortName(b.name)
	local olympusA, olympusB = nameA == "olympus", nameB == "olympus"
	if olympusA ~= olympusB then return olympusA end
	local levelA, levelB = Data.AvgTenths(a.g) or 0, Data.AvgTenths(b.g) or 0
	if levelA ~= levelB then return levelA > levelB end
	if nameA ~= nameB then return nameA < nameB end
	return a.name < b.name
end

-- 1.2.6: a census report used to survive only on clients that heard its elected reporter.
-- That made the army total depend on login time even though several trusted desks still held
-- the same last verified sizes.  Keep a second, deliberately narrow anti-entropy store.  It is
-- used for display and totals only: it never enters ns.rdb.guilds, elects a reporter, proves a
-- rank, changes a leader, or authorizes anything.  Church keepers, the King and signed High
-- Council may retain and repeat these normalized rows; the original observation time travels
-- with each row, so a relay cannot make old information fresh.
Data.GLOBAL_PROTOCOL = 1
-- Every client asks once after login, then only occasionally. A six-hour refresh is enough for
-- anti-entropy without turning a large installation into a continuous query stream; trusted
-- relays still answer a fresh client immediately.
Data.GLOBAL_ASK_EVERY = 6 * 60 * 60
Data.GLOBAL_ANSWER_GAP = 3 * 60
Data.GLOBAL_MAX_BYTES = ns.Codec.CHUNK * ns.Codec.MAX_CHUNKS
Data.GLOBAL_MAX_ROWS = 180
local globalLastSent, globalLastHeard, globalAnswerPending = 0, 0, false

local function GlobalStore()
	ns.rdb.censusGlobal = type(ns.rdb.censusGlobal) == "table" and ns.rdb.censusGlobal or {}
	return ns.rdb.censusGlobal
end
local function ObservationTime(g)
	return math.floor(tonumber(g and g.st) or tonumber(g and g.t) or 0)
end
local function GlobalGuildField(name)
	if type(name) ~= "string" or name == "" or #name > 72 or name:find("[~;,%c]") then return nil end
	if ns.Codec.LongGuild(name) or not ns.IsFederation(name) then return nil end
	return name
end
local function GlobalNumber(v, low, high)
	local n = tonumber(v)
	if not n or n ~= math.floor(n) or n < low or n > high then return nil end
	return n
end
local function GlobalTrusted(name)
	return ns.Church and ns.Church.IsLedgerRelay and ns.Church.IsLedgerRelay(name) == true
end
local function GlobalTake(name, total, online, avg10, observed, by, heardAt)
	name = GlobalGuildField(name)
	total = GlobalNumber(total, 0, ns.Codec.GUILD_CAP)
	online = GlobalNumber(online, 0, ns.Codec.GUILD_CAP)
	avg10 = GlobalNumber(avg10, 0, 600)
	observed = GlobalNumber(observed, 1, 4102444800)
	if not (name and total and online and avg10 and observed) or online > total then return false end
	local now = ns.Now()
	if observed > now + 5 * 60 or now - observed > Data.KEEP then return false end
	local store, key = GlobalStore(), name:lower()
	local old = store[key]
	if type(old) == "table" and (tonumber(old.observed) or 0) > observed then return false end
	store[key] = { name = name, total = total, online = online, avg10 = avg10,
		observed = observed, by = ns.FullName(by), heard = heardAt or now }
	return old == nil or old.total ~= total or old.online ~= online or old.avg10 ~= avg10 or old.observed ~= observed
end

function Data.CaptureGlobalCensus()
	if not GlobalTrusted(ns.me) then return 0 end
	local n, now = 0, ns.Now()
	for name, g in pairs(ns.rdb.guilds or {}) do
		local observed = ObservationTime(g)
		if now - observed <= Data.KEEP and GlobalTake(name, tonumber(g.total) or 0, tonumber(g.online) or 0,
			Data.AvgTenths(g) or 0, observed, ns.me, now) then n = n + 1 end
	end
	return n
end

local function GlobalRows()
	local rows, now = {}, ns.Now()
	for key, e in pairs(GlobalStore()) do
		if type(e) ~= "table" or not GlobalGuildField(e.name) or now - (tonumber(e.observed) or 0) > Data.KEEP then
			GlobalStore()[key] = nil
		else
			rows[#rows + 1] = e
		end
	end
	table.sort(rows, function(a, b)
		if a.observed ~= b.observed then return a.observed > b.observed end
		return a.name < b.name
	end)
	return rows
end

-- One bounded chunked snapshot.  The freshest rows win the bound; with the current army the
-- complete snapshot is well below it.  A later ask repeats it, so queue pressure loses no state.
function Data.GlobalCensusPayload()
	if not GlobalTrusted(ns.me) then return nil end
	Data.CaptureGlobalCensus()
	local head, out = ("CG~%d~S~%d~"):format(Data.GLOBAL_PROTOCOL, math.floor(ns.Now())), {}
	local bytes = #head
	for _, e in ipairs(GlobalRows()) do
		if #out >= Data.GLOBAL_MAX_ROWS then break end
		local row = ("%s,%d,%d,%d,%d"):format(e.name, e.total, e.online, e.avg10, e.observed)
		local extra = #row + (#out > 0 and 1 or 0)
		if bytes + extra > Data.GLOBAL_MAX_BYTES then break end
		out[#out + 1], bytes = row, bytes + extra
	end
	return head .. table.concat(out, ";")
end

function Data.SendGlobalCensus()
	-- Quiet presence (Core.lua): no snapshot of ours, which would name us as its sender online.
	if ns.QuietPresence and ns.QuietPresence() then return false end
	local payload = Data.GlobalCensusPayload()
	if not payload or payload:sub(-1) == "~" then return false end
	-- A keyed job carries its permit, which the transport asks before each piece goes out
	-- (Comm.lua's NormalizeOptions refuses a key without one, and the snapshot then never left):
	-- the channel's lane alone, and only while this client still holds the relay's trust.
	local key = "census-global"
	local ok = ns.Comm.SendChunked(payload, false, "CHANNEL", nil, { owner = Data, key = key,
		permit = function(_, guardKey, dist, target)
			if guardKey ~= key or dist ~= "CHANNEL" or target ~= nil then return false, "lane" end
			if not GlobalTrusted(ns.me) then return false, "trust" end
			return true
		end })
	if ok then globalLastSent = ns.Now() end
	return ok
end

-- Public for the focused harness.  The server-stamped sender is the trust boundary; the rows
-- themselves are never mistaken for signed census authority.
function Data.ReceiveGlobalCensus(dist, sender, text)
	if dist ~= "CHANNEL" or type(text) ~= "string" or type(sender) ~= "string"
		or sender == "" or #sender > 100 or sender:find("[%c~]") then return false end
	local ver, kind, made, body = text:match("^CG~(%d+)~([SQ])~(%d*)~?(.*)$")
	if tonumber(ver) ~= Data.GLOBAL_PROTOCOL then return false end
	if kind == "Q" then
		-- A query grants no authority and the answer is broadcast to the channel.  Requiring
		-- the requester itself to be a keeper made anti-entropy useless for the ordinary late
		-- client it was designed to heal.  Only snapshot senders need the trusted-relay gate.
		if not GlobalTrusted(ns.me) or ns.Now() - globalLastSent < Data.GLOBAL_ANSWER_GAP or globalAnswerPending then return true end
		globalAnswerPending = true
		local heardAt = globalLastHeard
		ns.After(math.random(2, 9), "global census answer", function()
			globalAnswerPending = false
			if GlobalTrusted(ns.me) and globalLastHeard <= heardAt and ns.Now() - globalLastSent >= Data.GLOBAL_ANSWER_GAP then Data.SendGlobalCensus() end
		end)
		return true
	end
	if not GlobalTrusted(sender) then return false end
	local snapshotAt = GlobalNumber(made, 1, 4102444800)
	if not snapshotAt or snapshotAt > ns.Now() + 5 * 60 or ns.Now() - snapshotAt > Data.KEEP then return false end
	local changed, count = false, 0
	for row in tostring(body):gmatch("[^;]+") do
		if count >= Data.GLOBAL_MAX_ROWS then return false end
		local name, total, online, avg10, observed = row:match("^([^,]+),(%d+),(%d+),(%d+),(%d+)$")
		if not name then return false end
		count = count + 1
		if GlobalTake(name, total, online, avg10, observed, sender, ns.Now()) then changed = true end
	end
	if count == 0 then return false end
	globalLastHeard = ns.Now()
	if changed then Data.ChangedSoon() end
	return true
end

function Data.AskGlobalCensus()
	return ns.Comm.Send("CHANNEL", ("CG~%d~Q~%d"):format(Data.GLOBAL_PROTOCOL, math.floor(ns.Now())), "census-global-ask")
end

local function SummaryGuilds()
	local out, direct, now = {}, {}, ns.Now()
	for name, g in pairs(ns.rdb.guilds or {}) do
		out[name], direct[name:lower()] = g, true
	end
	-- 1.3.3: our own guild comes straight from our roster, never from a relayed copy of another
	-- member's report (as in Take), so Stats and the site export keep our own count.
	local mine = GetGuildInfo("player")
	mine = mine and mine:lower()
	for _, e in ipairs(GlobalRows()) do
		local key, current, currentName = e.name:lower(), out[e.name], out[e.name] and e.name or nil
		if not current then
			for name, g in pairs(out) do
				if name:lower() == key then current, currentName = g, name; break end
			end
		end
		local ours = current and current.mine and key == mine
		if not ours and (not current or ObservationTime(current) < e.observed) then
			-- A normalized display row, intentionally missing leaders, ranks, zones and votes.
			if currentName and currentName ~= e.name then out[currentName] = nil end
			out[e.name] = { total = e.total, online = e.online, avgLevel = e.avg10 / 10,
				t = e.observed, st = e.observed, zones = {}, relayed = true, relayBy = e.by }
		end
	end
	return out, direct, now
end

function Data.Summary()
	local guilds, direct, now = SummaryGuilds()
	local known = {}
	for name in pairs(guilds) do known[name:lower()] = true end
	local s = { total = 0, online = 0, fresh = 0, newest = 0, guilds = {}, zones = {}, zoneGuilds = {}, zoneList = {} }
	for name, g in pairs(guilds) do
		if ns.IsFederation(name) and not NetOff(name) then
			local age = now - (g.t or 0)
			local fresh = age <= Data.FRESH
			-- A guild keeps its size from its last report when its reporters log off (the army
			-- does not shrink every night), for a day; listed (grey) for a week; who is online
			-- and where only count while fresh.
			if age <= Data.KEEP then
				s.guilds[#s.guilds + 1] = { name = name, g = g, fresh = fresh, counted = age <= Data.TOTAL_KEEP }
				if age <= Data.TOTAL_KEEP then s.total = s.total + math.min(g.total or 0, ns.Codec.GUILD_CAP) end
			end
			if fresh then
				s.fresh = s.fresh + 1
				s.online = s.online + (g.online or 0)
				if (g.t or 0) > s.newest then s.newest = g.t end
				for key, n in pairs(g.zones or {}) do
					s.zones[key] = (s.zones[key] or 0) + n
					s.zoneGuilds[key] = s.zoneGuilds[key] or {}
					s.zoneGuilds[key][name] = n
				end
			end
		end
	end
	table.sort(s.guilds, Data.GuildDefaultLess)
	-- 1.1: a count of people. The characters their players linked as alts (Alts.lua: confirmed on
	-- each character) count once in the army's total, whatever guilds they are in; each guild's own
	-- size stays its roster's. s.characters: the total before.
	s.characters, s.alts = s.total, 0
	local A = ns.Alts
	if A and A.Duplicates then
		local counted = {}
		for _, e in ipairs(s.guilds) do if e.counted then counted[e.name:lower()] = true end end
		local dup = A.Duplicates(counted) -- (nil from the stand-in until the game restarts)
		s.alts = math.max(0, math.min(s.total, tonumber(dup) or 0))
		s.total = s.total - s.alts
	end
	-- Guilds only /who has seen, for the census list alone: in no total, tree or map.
	s.seen = {}
	for name, e in pairs(Data.Seen()) do
		if ns.IsFederation(name) and not NetOff(name) and not direct[name:lower()] and not known[name:lower()] and type(e) == "table" and now - (e.t or 0) <= Data.KEEP then
			s.seen[#s.seen + 1] = { name = name, online = e.online or 0, capped = e.capped, t = e.t }
		end
	end
	table.sort(s.seen, function(a, b)
		if a.online ~= b.online then return a.online > b.online end
		return a.name < b.name
	end)
	for key, n in pairs(s.zones) do s.zoneList[#s.zoneList + 1] = { key = key, count = n } end
	table.sort(s.zoneList, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.key < b.key
	end)
	return s
end

ns.On("INIT", function()
	local store, now = GlobalStore(), ns.Now()
	for key, e in pairs(store) do
		if type(e) ~= "table" or not GlobalGuildField(e.name) or now - (tonumber(e.observed) or 0) > Data.KEEP then store[key] = nil end
	end
	if ns.Comm and ns.Comm.Handle then ns.Comm.Handle("CG", Data.ReceiveGlobalCensus) end
	ns.After(20, "global census ask", Data.AskGlobalCensus)
	ns.Every(Data.GLOBAL_ASK_EVERY, "global census ask", Data.AskGlobalCensus)
end)

-- Tonight's count (1.1, Fern's #16): this client's own view of the evening, from the reports it
-- already holds. Once a minute (Data.EVENING_EVERY) it reads the online total and each zone's
-- count (Data.Summary: fresh reports only, zones only from reporters who share them), and keeps
-- the peak and, per zone, its first count, so the Census shows whether a zone fills or empties.
-- It starts a full reporting cycle after login (Data.CROWN_AFTER, about 3 minutes): before that
-- the census is still rebuilding and every count would look like growth. In memory only, never
-- saved and never sent: another client counts its own evening, so it is labelled "this client".
Data.EVENING_EVERY = 60
local evening = { samples = 0, zones = {} }
function Data.Evening() return evening end
function Data.ResetEvening() evening = { samples = 0, zones = {} } end -- tests

-- One sample, at `now`; false while the census is rebuilding after login.
function Data.SampleEvening(now)
	now = now or ns.Now()
	local loginAt = ns.Comm and ns.Comm.loginAt
	if loginAt and now - loginAt < Data.CROWN_AFTER then return false end
	local s = Data.Summary()
	local e = evening
	if e.samples == 0 then e.since = now end
	e.samples, e.t, e.online = e.samples + 1, now, s.online
	if not e.peak or s.online > e.peak then e.peak, e.peakAt = s.online, now end
	-- A zone nobody stood in at the first sample started at 0; one left empty since is at 0 now.
	for key, z in pairs(e.zones) do
		if not s.zones[key] then z.now = 0 end
	end
	for key, n in pairs(s.zones) do
		local z = e.zones[key]
		if not z then
			z = { first = e.samples == 1 and n or 0 }
			e.zones[key] = z
		end
		z.now = n
		if not z.peak or n > z.peak then z.peak = n end
	end
	return true
end

-- A zone's count now and how it moved since the first sample (nil before any sample).
function Data.ZoneTrend(key)
	local z = evening.zones[key]
	if not z or evening.samples == 0 then return nil end
	return z.now or 0, (z.now or 0) - (z.first or 0)
end

ns.On("LOGIN", function()
	ns.Every(Data.EVENING_EVERY, "evening count", function()
		Data.Housekeeping() -- (1.2.3: the census's own, on the same tick)
		Data.SampleEvening()
	end)
end)

-- (1.2.1) The guilds' names, their leaders' and the zones come from other players' reports: each
-- through Codec.Discord, so none ends the table's block or shows as Discord's markup.
function Data.DiscordText()
	local s = Data.Summary()
	local F, D = ns.FormatNumber, ns.Codec.Discord
	local out = {}
	-- (CR-02: the characters, as the window's header has them, then the people.)
	out[#out + 1] = L.DISCORD_HEADER:format(F(s.characters or s.total), F(s.online), #s.guilds) .. " · " .. L.ARMY_PEOPLE:format(F(s.total))
	local where = {}
	for i = 1, math.min(8, #s.zoneList) do
		local z = s.zoneList[i]
		where[#where + 1] = D(ns.Zones.NameForKey(z.key)) .. " " .. F(z.count)
	end
	if #where > 0 then out[#out + 1] = L.DISCORD_WHERE .. table.concat(where, " · ") end
	out[#out + 1] = "```"
	-- (1.2.4: each guild's average level too, "-" for none, as the Census's column.)
	out[#out + 1] = ("%-22s %7s %7s %7s  %s"):format("Guild", "Members", "Online", "Avg lvl", "Leader")
	for _, e in ipairs(s.guilds) do
		local g = e.g
		local leader = g.leader and (D(g.leader, true) .. (g.leaderOnline and " (on)" or "")) or "?"
		out[#out + 1] = ("%-22s %7s %7s %7s  %s%s"):format(D(e.name, true), F(g.total), F(g.online), Data.AvgLevelText(g) or "-", leader,
			e.fresh and "" or "  [stale]")
	end
	out[#out + 1] = "```"
	out[#out + 1] = ("_Olympus addon v%s_"):format(ns.VERSION)
	return table.concat(out, "\n")
end
