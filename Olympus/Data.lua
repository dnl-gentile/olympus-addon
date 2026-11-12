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
-- (1.5.5) Never on Forever's live realms (ns.KingIsMaster): the main guild's master there is not the King.
function Data.OtherKing(guild, leader)
	return ns.KingIsMaster() and ns.IsKingGuild(guild) and ns.KingCharacter() ~= nil and not ns.IsKingCharacter(leader)
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
ns.On("LOGIN", function() ns.RegisterEvent("PLAYER_LOGOUT", function()
	DropDeadVotes(ns.Now())
	-- (1.4.0) Our own look at this realm group, kept for the next group this account logs into
	-- (Data.RecordGroupCensus), once the census was rebuilt after login: never a half-heard count.
	local now, at = ns.Now(), ns.Comm and ns.Comm.loginAt
	if Data.RecordGroupCensus and at and now - at >= Data.CROWN_AFTER and not (Data.Rebuilding and Data.Rebuilding(now)) then
		ns.SafeCall("census group at logout", Data.RecordGroupCensus)
	end
end) end)

local function SavedTime(value)
	local n = tonumber(value)
	if n and n > 0 and n < math.huge then return n end
end

local function SavedCount(value)
	if value == nil then return 0 end
	local n = tonumber(value)
	if n and n >= 0 and n < math.huge and n == math.floor(n) then return n end
end

-- Read old numeric strings as numbers and discard a row whose census data cannot be read.
-- The next roster scan or peer report can replace it without clearing any other saved state.
local function CleanSavedReport(name, g, now)
	if type(name) ~= "string" or type(g) ~= "table" then return false end
	local at, total, online = SavedTime(g.t), SavedCount(g.total), SavedCount(g.online)
	if not at or now - at > Data.KEEP or not total or not online then return false end
	if g.zones ~= nil then
		if type(g.zones) ~= "table" then return false end
		for key, count in pairs(g.zones) do
			local n = SavedCount(count)
			if type(key) ~= "string" or not n then return false end
			g.zones[key] = n
		end
	end
	g.t, g.st, g.total, g.online = at, SavedTime(g.st), total, online
	return true
end

ns.On("INIT", function()
	local now = ns.Now()
	for name, g in pairs(ns.rdb.guilds) do
		if not CleanSavedReport(name, g, now) then
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
		local at, online
		if type(e) == "table" then at, online = SavedTime(e.t), SavedCount(e.online) end
		if type(name) ~= "string" or not at or now - at > Data.KEEP or not online then seen[name] = nil
		else e.t, e.online = at, online end
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
	ns.rdb.seen = type(ns.rdb.seen) == "table" and ns.rdb.seen or {}
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
-- A read-only check applies the same expiry and conflict rules without claiming or renewing it.
function Data.ClaimGuild(sender, guild, readOnly)
	local who, now = ns.FullName(sender), ns.Now()
	local c = senderGuild[who]
	if type(c) ~= "table" then
		if not readOnly then senderGuild[who] = { guild = guild, t = now } end
		return true
	end
	if c.guild:lower() ~= guild:lower() and now - c.t < Data.CLAIM_TTL then return false end
	if not readOnly then c.guild, c.t = guild, now end -- keep his claim's own table
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

-- (1.5.5) Where names split (Forever) a name is one across its realm family, and a report reaches us
-- stamped with its sender's sub-realm, so its bare names are keyed with that one: the same officer is
-- "Name-<one sub-realm>" in one reporter's vote, "Name-<another>" in the next one's, and his own chat
-- line comes under a third stamp. A name's family key ("Name-ForeverPvE") is the same in all of them;
-- anywhere else, or for a realm of no Forever family, the name as it is.
local function FamilyKey(name)
	if not ns.splitNames or type(name) ~= "string" then return name end
	local base, realm = name:match("^(.+)%-([^%-]+)$")
	local family = realm and ns.ForeverFamily and ns.ForeverFamily(realm)
	return family and (base .. "-" .. family) or name
end
-- A vote's rank for `who`: under his name as written, else (Forever) under the same name stamped with
-- another sub-realm of his family (the lowest rank, as the names' order is none). Without this an
-- officer's [Captains] line and a guild master's [Lords] line were "unverified" whenever his stamp
-- was not his guild's reporter's, and the census's ranks of other guilds held for nobody there.
local function RankIn(ranks, who)
	local k = ranks[who]
	if k ~= nil or not ns.splitNames then return k end
	local key = FamilyKey(who)
	if key == who then return nil end
	for name, rank in pairs(ranks) do
		if FamilyKey(name) == key and (k == nil or rank < k) then k = rank end
	end
	return k
end

-- The guild as a report pictures it: leader and officers, names in "Name-Realm" form so the
-- same people match whatever realm each reporter plays on (1.5.5: their family's key where names
-- split, FamilyKey: two reporters on two sub-realms give one picture). A list cut at MAX_OFFICERS is
-- pictured by its leader only (two cut lists need not hold the same officers).
local function Signature(r, ranks)
	local cut = #(r.officers or {}) >= ns.Codec.MAX_OFFICERS
	local parts = {}
	for name, rank in pairs(ranks) do
		if rank == 0 or not cut then parts[#parts + 1] = FamilyKey(name) .. "=" .. rank end
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
	if not ns.ReportInGroup(r, ns.group) then return false end
	if not ns.IsFederation(r.guild) then return false end
	-- 1.1: a guild the moderators took off (net-off): its report counts for nothing, not even as a vote.
	if ns.Moderation.Report and ns.Moderation.Report(r, sender) then return false end
	-- Our own guild comes straight from our roster, never from someone else's claim (in any spelling).
	local mine = GetGuildInfo("player")
	if mine and r.guild:lower() == mine:lower() then return false end
	local who = ns.FullName(sender)
	if not ns.ReportInGroup({ from = ns.RealmOf(who) }, ns.group) then return false end
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
	-- (1.5.5) Heard first-hand: whispered to this client by its sender (Relay.FirstHand: hop 1 at a relay
	-- or a provisional one), not handed on. A serving provisional relay's snapshot holds these alone.
	local R = ns.Relay
	r.fh = (type(R) == "table" and type(R.FirstHand) == "function" and R.FirstHand() == true) or nil
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
			local k = RankIn(v.ranks, who)
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

-- (1.5.5) Whether this client's census can rank anyone of another guild now, as Data.KnownRank asks
-- before any rank of it: the guild on the network (one the moderators took off ranks nobody on
-- another's client, NetOff) and a report of it heard within FRESH. Bank.lua asks it before the two
-- ways it takes a Lord or a Captain that KnownRank alone does not (the census's name on another
-- sub-realm, a guild master a verifier approved): the audit of 11-10 found the approval standing for
-- a guild that was off, and for one no report had named this session. (Bank.lua names no net-off
-- itself: the census says who it ranks; 1.1, #32 and #33.)
function Data.CanRank(guild, now)
	if type(guild) ~= "string" or guild == "" or NetOff(guild) then return false end
	local g = Data.Guild(guild)
	return type(g) == "table" and (now or ns.Now()) - (tonumber(g.t) or 0) <= Data.FRESH
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
		local k = RankIn(v.ranks, who)
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
local function AuthorizedRank(sender, guild)
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

-- Guild verification (Verify.lua): while a guild's verification is overdue (GRACE past, no approval
-- of its current guild master) and the hold is on (ns.VERIFY_HOLD, Core.lua), its guild master stands
-- as an officer: every power that asks rank 0 here waits for his verification, an officer's stays.
-- The King's guild is never held. Nothing about the guild's members changes.
function Data.AuthorizedRank(sender, guild)
	local rank, source, support = AuthorizedRank(sender, guild)
	if rank == 0 and ns.MasterHeld ~= nil and ns.MasterHeld(guild) == true then rank = ns.CAPTAIN_RANK end
	return rank, source, support
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
-- 1.4.0 (the author, 11-03: "garantir que a contagem das pessoas vai ser correta, vai retransmitir
-- e não vai ficar com as pessoas com números mais baixos do que outras... se múltiplas pessoas me
-- mandam números com os mesmos dados, eu vou confiar"): every client asks after login, again once
-- more of the army is on, then every half hour. An ask carries what its client already holds (how
-- many guilds, its newest observation), so a holder that has nothing newer stays silent and the
-- asks cost a few bytes each.
Data.GLOBAL_ASK_EVERY = 30 * 60
Data.GLOBAL_ASK_AGAIN = 3 * 60
Data.GLOBAL_ANSWER_GAP = 3 * 60
Data.GLOBAL_MAX_BYTES = ns.Codec.CHUNK * ns.Codec.MAX_CHUNKS
-- (1.5.4) A snapshot this client builds leaves room for a relay's label around it ("RM~P~<name>~",
-- then "RG~P~<name>~"), so a relay sends it whole in one envelope of at most MAX_CHUNKS whispers: a
-- full-size one took two batches, and a newer snapshot could replace the second after the first
-- left. One taken may still be the whole GLOBAL_MAX_BYTES (an older relay's).
Data.GLOBAL_SEND_BYTES = Data.GLOBAL_MAX_BYTES - 64
Data.GLOBAL_MAX_ROWS = 180
-- Hold an overflow page across several sends while coverage is steady. The tree and
-- cross-relay mesh deliver on slower cadences than the local 120-second broadcast.
Data.GLOBAL_ROTATE_EVERY = 7 * 60
-- 1.4.0, the witnesses (the author's rule of 10-20: one person is one witness; a count is confirmed
-- by a moderator alone, or by two or more people agreeing: observed within half an hour of each
-- other, sizes within max(5, 5%)). A trusted relay's row (above) stands alone; any other member's
-- row is a witness, kept a day, and a guild's row is taken when two people's agree. Our own direct
-- row of that guild (its reporter heard here) is one of the two.
Data.WITNESS_WINDOW = 30 * 60
Data.WITNESS_SLACK, Data.WITNESS_SHARE = 5, 0.05
Data.WITNESS_KEEP = 24 * 60 * 60
Data.WITNESS_MAX = 8
-- Who answers an ask: a trusted relay after 2-9 s, as before; any other member later, after
-- MEMBER_ANSWER_AFTER + up to MEMBER_ANSWER_SPREAD s, unless MEMBER_ANSWERS answers (or a trusted
-- one) were already heard since the ask. Each answer is announced first by a one-piece claim
-- ("CG~1~C~t"), which reaches everyone long before a snapshot of many pieces, so the rest hold back.
Data.MEMBER_ANSWER_AFTER, Data.MEMBER_ANSWER_SPREAD, Data.MEMBER_ANSWERS = 12, 60, 2
-- Periodic broadcasts must not advance the cooldown for answering a census request.
local globalLastAnswered, globalLastHeard, globalAnswerPending = 0, 0, false
local answersHeard = {} -- { t, trusted } of the claims and snapshots heard, the last few minutes

local function ScopedRealm(realm)
	return realm:match("^Forever%a+$") or (ns.ForeverFamily and ns.ForeverFamily(realm))
end
local function ScopedGroup(group)
	if type(group) ~= "string" then return nil end
	local family
	for realm in group:gmatch("[^+]+") do
		local f = ScopedRealm(realm)
		if not f or (family and family ~= f) then return nil end
		family = f
	end
	return family
end
local function LocalReport(g) return type(g) == "table" and ns.ReportInGroup(g, ns.group) end

-- CG1 did not carry an observation's scope. A later relay could stamp mixed
-- PvE/PvP counts with its own PvP name. Keep the old bytes, but never infer their
-- origin from that name, or let a derived snapshot resurrect them after reload.
function Data.MigrateCensusScope()
	if type(ns.db) ~= "table" then return end
	for _, side in ipairs({ { ns.db, "Alliance" }, { ns.db.horde, "Horde" } }) do
		local stores = type(side[1]) == "table" and side[1].realms or nil
		for group, R in pairs(type(stores) == "table" and stores or {}) do
			if ScopedGroup(group) and type(R) == "table" and R.censusScope ~= 2 then
				local legacy, witnesses = {}, {}
				for key, e in pairs(type(R.censusGlobal) == "table" and R.censusGlobal or {}) do
					if type(e) == "table" and e.scope ~= group then legacy[key], R.censusGlobal[key] = e, nil end
				end
				for key, e in pairs(type(R.censusWitness) == "table" and R.censusWitness or {}) do
					witnesses[key] = e
				end
				if next(legacy) or next(witnesses) or (type(R.censusForeign) == "table" and next(R.censusForeign)) then
					R.censusUnscoped = { global = legacy, witnesses = witnesses, snapshots = {}, details = {} }
					R.censusWitness = {}
					for key, e in pairs(type(ns.db.groupCensus) == "table" and ns.db.groupCensus or {}) do
						if type(e) == "table" and e.faction == side[2] and ScopedGroup(e.group) == ScopedGroup(group) then
							-- A complete independent set of correctly scoped direct reports
							-- may already substantiate this exact saved view. Receipt by a
							-- relay alone never does. Keep the original observation date.
							local count, total = 0, 0
							for _, g in pairs(type(R.guilds) == "table" and R.guilds or {}) do
								local observed = type(g) == "table" and (tonumber(g.st) or tonumber(g.t))
								if observed and observed >= (tonumber(e.observed) or math.huge) and ns.Now() - observed <= Data.TOTAL_KEEP
									and ScopedGroup(g.from) == ScopedGroup(group) and ns.ReportInGroup(g, group) then
									count, total = count + 1, total + math.min(tonumber(g.total) or 0, ns.Codec.GUILD_CAP)
								end
							end
							if count ~= e.guilds or total ~= e.characters then
								R.censusUnscoped.snapshots[key], e.unscoped = e, true
							end
						end
					end
					for key, e in pairs(type(ns.db.groupDetails) == "table" and ns.db.groupDetails or {}) do
						if type(e) == "table" and e.faction == side[2] and ScopedGroup(e.group) == ScopedGroup(group) then
							R.censusUnscoped.details[key], e.unscoped = e, true
						end
					end
				end
				R.censusScope = 2
			end
		end
	end
end

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

-- Guilds heard since login, deduplicated across roster reports and accepted relay counts.
function Data.Rebuilding(now)
	local login = ns.Comm and ns.Comm.loginAt
	if not login or not ns.IsMember() then return nil end
	now = now or ns.Now()
	if now - login >= Data.REBUILD_FOR then return nil end
	local seen, count = {}, 0
	local own = (GetGuildInfo("player") or ""):lower()
	local function Add(name, received, observed)
		if type(name) ~= "string" or (tonumber(received) or 0) < login
			or now - observed > Data.TOTAL_KEEP or NetOff(name) then return end
		local key = name:lower()
		if key == own or seen[key] then return end
		seen[key], count = true, count + 1
	end
	for name, g in pairs(ns.rdb and ns.rdb.guilds or {}) do
		if LocalReport(g) and not g.mine then Add(name, g.t, ObservationTime(g)) end
	end
	local scoped = ScopedGroup(ns.group)
	for _, g in pairs(ns.rdb and ns.rdb.censusGlobal or {}) do
		if type(g) == "table" and (not scoped or g.scope == ns.group) and g.by ~= ns.me then
			Add(g.name, g.heard, tonumber(g.observed) or 0)
		end
	end
	return count
end

local function GlobalNumber(v, low, high)
	local n = tonumber(v)
	if not n or n ~= math.floor(n) or n < low or n > high then return nil end
	return n
end
-- (The review of the 1.5.4 candidate.) This client's own word back from the relay's hops. On Forever
-- a whisper arrives with the sender's bare name and the relay's client stamps its own sub-realm on
-- the origin (Relay.lua's HandleIn), so "Name-Realm3" comes back for "Name-Realm1": one name across
-- a family, as PersonKey takes it. Comm's echo check (OnAddonMessage: sender == ns.me) sees another
-- name, so the census receivers ask here; a trusted client's own look of the other family (CX 1)
-- came back as another councillor's word, was noted as heard (groupHeard) and never said again that
-- session. Off Forever (no family) whole names alone, as before: "Bob-A" and "Bob-B" are two people.
local function OwnWord(sender)
	if type(ns.me) ~= "string" or type(sender) ~= "string" then return false end
	local me, other = ns.FullName(ns.me), ns.FullName(sender)
	if me == other then return true end
	if ns.ShortName(me):lower() ~= ns.ShortName(other):lower() then return false end
	local family = ns.ForeverFamily and ns.ForeverFamily(ns.RealmOf(me) or "")
	return family ~= nil and family == ns.ForeverFamily(ns.RealmOf(other) or "")
end
-- 1.5.5, the author as the census's trusted distributor (the author, 11-10: "garantir que os números
-- do PVP que estão saindo de mim vão chegar em todo mundo ... eu sou a pessoa mais confiável"). A
-- whisper reaches its own Forever family alone, so the PvP numbers reach PvE only in what a client
-- carries when its player logs in there: the author's own look among them. 1.5.4 trusted the Church's
-- ledger relays alone (Church.IsLedgerRelay: its keepers, the King, the signed High Council), so his
-- rows were one witness's and his carried look was "reported" everywhere. Now his characters are a
-- trusted census source too: the signed list's (ns.IsAuthorName) or the launch's (Relay.IsLaunchAuthor,
-- on the name's own family). A trusted origin counts only on a hop that proves it (Relay.HopTrusted,
-- the relay mesh's: a signed relay's), never through a provisional relay (RO: member weight), and our
-- own word back is ours whatever carried it. Our own client's trust is its identity alone.
local function RelayAsk(fn, ...)
	local R = ns.Relay
	local f = type(R) == "table" and R[fn]
	if type(f) ~= "function" then return nil end
	return f(...)
end
local function Hop() return RelayAsk("Hop") end
local function AuthorIdentity(name)
	if type(name) ~= "string" or name == "" then return false end
	if type(ns.IsAuthorName) == "function" and ns.IsAuthorName(name) == true then return true end
	return RelayAsk("IsLaunchAuthor", name) == true
end
local function LedgerRelay(name)
	return ns.Church ~= nil and ns.Church.IsLedgerRelay ~= nil and ns.Church.IsLedgerRelay(name) == true
end
local function TrustedCensusOrigin(name) return LedgerRelay(name) or AuthorIdentity(name) end
local function GlobalTrusted(name)
	if not TrustedCensusOrigin(name) then return false end
	if name == ns.me then return true end
	if Hop() == "O" then return false end
	return OwnWord(name) or RelayAsk("HopTrusted") ~= false
end
-- (1.5.5) What the census took, left unproven and refused (Data.CensusStats, for /oly bug).
Data.CENSUS_REFUSALS = 5 -- the last refusals kept, with their reason
local censusStats = { cg = { trusted = 0, witnessed = 0, lone = 0, refused = 0 },
	cx = { author = 0, trusted = 0, witnessed = 0, heard = 0, unproven = 0, refused = 0 },
	cx3 = { direct = 0, author = 0, unproven = 0 }, qa = { verified = 0, refused = 0, signed = 0 } }
local censusRefusals = {} -- { kind, why, from, t }, oldest first
local function Tally(kind, what) censusStats[kind][what] = censusStats[kind][what] + 1 end
local function Refused(kind, why, from)
	Tally(kind, "refused")
	if #censusRefusals >= Data.CENSUS_REFUSALS then table.remove(censusRefusals, 1) end
	censusRefusals[#censusRefusals + 1] = { kind = kind, why = why, t = ns.Now(),
		from = type(from) == "string" and ns.ShortName(from) or nil }
	return false
end
-- (1.5.5) The census's trust gate as the relays ask it, and its counters for /oly bug (lane trust fills both).
function Data.CensusTrusted(name) return GlobalTrusted(name) end
function Data.CensusStats() return {} end
-- 1.4.0: a member who may answer an ask with what it holds (any member; trust is the receiver's).
local function GlobalMember()
	if ns.QuietPresence and ns.QuietPresence() then return false end
	return type(ns.IsMember) ~= "function" or ns.IsMember() == true
end
-- A row as the wire carries it, checked: { name, total, online, avg10, observed } or nil.
local function GlobalRow(name, total, online, avg10, observed)
	name = GlobalGuildField(name)
	total = GlobalNumber(total, 0, ns.Codec.GUILD_CAP)
	online = GlobalNumber(online, 0, ns.Codec.GUILD_CAP)
	avg10 = GlobalNumber(avg10, 0, 600)
	observed = GlobalNumber(observed, 1, 4102444800)
	if not (name and total and online and avg10 and observed) or online > total then return nil end
	local now = ns.Now()
	if observed > now + 5 * 60 or now - observed > Data.KEEP then return nil end
	return { name = name, total = total, online = online, avg10 = avg10, observed = observed }
end
-- rg (1.5.5): a trusted row a guildmate handed over (RG, Relay.Hop "G"): his guild's word, any origin
-- he names. It counts here for display, and never enters a trusted client's own snapshot (SendableRows).
local function GlobalTake(name, total, online, avg10, observed, by, heardAt, witnesses, rg)
	local row = GlobalRow(name, total, online, avg10, observed)
	if not row then return false end
	local now = ns.Now()
	local store, key = GlobalStore(), row.name:lower()
	local old = store[key]
	if type(old) == "table" and (tonumber(old.observed) or 0) > row.observed then return false end
	store[key] = { name = row.name, total = row.total, online = row.online, avg10 = row.avg10,
		observed = row.observed, by = ns.FullName(by), heard = heardAt or now, w = witnesses, scope = ns.group, rg = rg or nil }
	if old == nil or old.total ~= row.total or old.online ~= row.online or old.avg10 ~= row.avg10 or old.observed ~= row.observed then return true end
	-- Even the same observation advances the startup status on its first receipt this login.
	local login = ns.Comm and ns.Comm.loginAt
	return login ~= nil and now - login < Data.REBUILD_FOR and (tonumber(old.heard) or 0) < login
		and now - row.observed <= Data.TOTAL_KEEP and not OwnWord(by)
end

-- 1.4.0, the witnesses (see Data.WITNESS_WINDOW above). ns.rdb.censusWitness[guild lower] =
-- { [person] = { name, total, online, avg10, observed, heard, by } }: the last row each person sent
-- for that guild. A person is his confirmed alt group's main (Alts.Group), else his name, so one
-- player's characters are one witness.
local function Witnesses()
	ns.rdb.censusWitness = type(ns.rdb.censusWitness) == "table" and ns.rdb.censusWitness or {}
	return ns.rdb.censusWitness
end
local function PersonKey(name)
	local full = ns.FullName(name)
	local A = ns.Alts
	local g = A and A.Group and full and A.Group(full)
	if type(g) == "table" and type(g.main) == "string" then full = ns.FullName(g.main) end
	if not full then return nil end
	-- Forever characters retain their identity when the server stamps another sub-realm.
	local realm = ns.RealmOf(full)
	local group = realm and ns.GroupOf and ns.GroupOf(realm)
	return group and (ns.ShortName(full):lower() .. "-" .. group:lower()) or full:lower()
end
-- Two rows agree: observed within the window of each other, sizes within max(5, 5%).
function Data.WitnessesAgree(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	if math.abs((a.observed or 0) - (b.observed or 0)) > Data.WITNESS_WINDOW then return false end
	local big = math.max(a.total or 0, b.total or 0)
	return math.abs((a.total or 0) - (b.total or 0)) <= math.max(Data.WITNESS_SLACK, Data.WITNESS_SHARE * big)
end
-- The direct row this client holds for a guild (its reporter heard here), as a witness, or nil.
local function OwnWitness(key)
	for name, g in pairs(ns.rdb.guilds or {}) do
		if name:lower() == key and LocalReport(g) then
			return GlobalRow(name, math.min(tonumber(g.total) or 0, ns.Codec.GUILD_CAP), math.min(tonumber(g.online) or 0, ns.Codec.GUILD_CAP),
				Data.AvgTenths(g) or 0, ObservationTime(g))
		end
	end
	return nil
end
-- A member's row heard: kept as his witness; when two people's rows of the guild agree, the newer of
-- the agreeing pair is taken (true when the shown row changed). Older witnesses and the excess go.
local function TakeWitness(row, sender, now)
	local who = PersonKey(sender)
	if not who then return false end
	local all, key = Witnesses(), row.name:lower()
	local list = type(all[key]) == "table" and all[key] or {}
	all[key] = list
	list[who] = { name = row.name, total = row.total, online = row.online, avg10 = row.avg10,
		observed = row.observed, heard = now, by = ns.FullName(sender) }
	local entries = {}
	for person, e in pairs(list) do
		if type(e) ~= "table" or now - (tonumber(e.heard) or 0) > Data.WITNESS_KEEP or now - (tonumber(e.observed) or 0) > Data.KEEP then
			list[person] = nil
		else
			entries[#entries + 1] = { person = person, e = e }
		end
	end
	if #entries > Data.WITNESS_MAX then
		table.sort(entries, function(a, b)
			if a.e.observed ~= b.e.observed then return a.e.observed > b.e.observed end
			return a.person < b.person
		end)
		for i = #entries, Data.WITNESS_MAX + 1, -1 do list[entries[i].person] = nil; entries[i] = nil end
	end
	local own = OwnWitness(key)
	if own then entries[#entries + 1] = { person = "\001self", e = own } end
	-- The row taken from the agreeing pairs: the newest observation; at the same time the larger
	-- size, then the more online. The same witnesses give every client the same row, whatever order
	-- they arrived in.
	local function Later(a, b)
		if a.observed ~= b.observed then return a.observed > b.observed end
		if a.total ~= b.total then return a.total > b.total end
		return a.online > b.online
	end
	local best
	for i = 1, #entries do
		for j = i + 1, #entries do
			local a, b = entries[i].e, entries[j].e
			if Data.WitnessesAgree(a, b) then
				local newer = Later(b, a) and b or a
				if not best or Later(newer, best) then best = newer end
			end
		end
	end
	-- (1.5.5) The second result: whether two people agreed on the guild (Data.CensusStats).
	if not best or best == own then return false, best ~= nil end
	return GlobalTake(best.name, best.total, best.online, best.avg10, best.observed, best.by, now, 2), true
end

local function TrimGlobal()
	for _, store in ipairs({ GlobalStore(), Witnesses() }) do
		local keys = {}
		for key, entry in pairs(store) do
			local observed = type(entry) == "table" and tonumber(entry.observed) or nil
			if not observed and type(entry) == "table" then
				for _, row in pairs(entry) do
					if type(row) == "table" then observed = math.max(observed or 0, tonumber(row.observed) or 0) end
				end
			end
			keys[#keys + 1] = { key = key, observed = observed or 0 }
		end
		table.sort(keys, function(a, b)
			if a.observed ~= b.observed then return a.observed > b.observed end
			return a.key < b.key
		end)
		for i = Data.MAX_GUILDS + 1, #keys do store[keys[i].key] = nil end
	end
end

-- The witnesses a guild's shown relayed row stands on (Census tooltips, /oly status): 2 for a row
-- two people agreed on, 1 for a trusted relay's own, nil for none.
function Data.GlobalWitnesses(name)
	local e = type(name) == "string" and GlobalStore()[name:lower()]
	if type(e) ~= "table" then return nil end
	return tonumber(e.w) or 1
end

function Data.CaptureGlobalCensus()
	if not GlobalTrusted(ns.me) then return 0 end
	local n, now = 0, ns.Now()
	for name, g in pairs(ns.rdb.guilds or {}) do
		local observed = ObservationTime(g)
		if LocalReport(g) and now - observed <= Data.KEEP and GlobalTake(name, tonumber(g.total) or 0, tonumber(g.online) or 0,
			Data.AvgTenths(g) or 0, observed, ns.me, now) then n = n + 1 end
	end
	TrimGlobal()
	return n
end

local function GlobalRows()
	local rows, now = {}, ns.Now()
	for key, e in pairs(GlobalStore()) do
		if type(e) ~= "table" or not GlobalGuildField(e.name) or now - (tonumber(e.observed) or 0) > Data.KEEP then
			GlobalStore()[key] = nil
		elseif not ScopedGroup(ns.group) or e.scope == ns.group then
			rows[#rows + 1] = e
		end
	end
	table.sort(rows, function(a, b)
		if a.observed ~= b.observed then return a.observed > b.observed end
		return a.name < b.name
	end)
	return rows
end

-- 1.4.0: the rows this client would send. A trusted relay's store (its own direct rows captured
-- into it, as before); a member's own direct rows with the confirmed rows it holds, the newer of
-- each guild's two. The freshest first.
-- (1.5.5) A trusted client never says a row it took over a guildmate's hand-over (rg, GlobalTake). A
-- provisional relay while it serves (RelayFallback.lua: no signed relay reachable, member weight) says
-- only what it heard first-hand: the reports whispered to it (Take's fh) and its own roster; never a
-- row it heard from anyone else, nor a global one.
local function SendableRows()
	local provisional = RelayAsk("ServingProvisional") == true
	if not provisional and GlobalTrusted(ns.me) then
		Data.CaptureGlobalCensus()
		local rows = {}
		for _, e in ipairs(GlobalRows()) do if not e.rg then rows[#rows + 1] = e end end
		return rows
	end
	local byKey, now = {}, ns.Now()
	if not provisional then for _, e in ipairs(GlobalRows()) do byKey[e.name:lower()] = e end end
	for name, g in pairs(ns.rdb.guilds or {}) do
		if LocalReport(g) and (not provisional or g.fh == true or g.mine == true) then
			local observed = ObservationTime(g)
			local row = now - observed <= Data.KEEP and GlobalRow(name, math.min(tonumber(g.total) or 0, ns.Codec.GUILD_CAP),
				math.min(tonumber(g.online) or 0, ns.Codec.GUILD_CAP), Data.AvgTenths(g) or 0, observed) or nil
			local key = row and row.name:lower()
			if row and (not byKey[key] or byKey[key].observed < row.observed) then byKey[key] = row end
		end
	end
	local rows = {}
	for _, e in pairs(byKey) do rows[#rows + 1] = e end
	table.sort(rows, function(a, b)
		if a.observed ~= b.observed then return a.observed > b.observed end
		return a.name < b.name
	end)
	return rows
end

-- What this client holds, for its asks: the guilds it could count (within TOTAL_KEEP) and its
-- newest observation of any of them.
function Data.GlobalDigest()
	local seen, n, newest, now = {}, 0, 0, ns.Now()
	local function Add(name, observed)
		if type(name) ~= "string" or now - observed > Data.TOTAL_KEEP then return end
		local key = name:lower()
		if not seen[key] then seen[key], n = true, n + 1 end
		if observed > newest then newest = observed end
	end
	for _, e in ipairs(GlobalRows()) do Add(e.name, e.observed) end
	for name, g in pairs(ns.rdb.guilds or {}) do
		if LocalReport(g) then Add(name, ObservationTime(g)) end
	end
	return n, newest
end

local function GlobalWireRow(e)
	return ("%s,%d,%d,%d,%d"):format(e.name, e.total, e.online, e.avg10, e.observed)
end

-- A CG receiver merges rows; an omitted guild is never a deletion. In an overflowing Forever
-- census, keep the newest rows at the front and give the other countable guilds a turn. Use the
-- original payload's actual row and byte counts, so this does not buy coverage with extra traffic.
local function RotateGlobalRows(rows, baseline, budget, now)
	local wire, largest = {}, 0
	for i, e in ipairs(rows) do
		if now - e.observed > Data.TOTAL_KEEP then break end
		wire[i] = baseline[i] or GlobalWireRow(e)
		largest = math.max(largest, #wire[i] + 1)
	end
	if largest > budget then return baseline end

	local out, included, room = {}, {}, budget
	local function Add(i)
		local cost = #wire[i] + 1
		if included[i] or #out == #baseline or cost > room then return end
		out[#out + 1], included[i], room = wire[i], true, room - cost
	end
	for i = 1, math.max(1, math.floor(#baseline / 3)) do
		if room - #wire[i] - 1 < largest then break end
		Add(i)
	end
	local tail = {}
	for i = #out + 1, #wire do tail[#tail + 1] = { i = i, key = rows[i].name:lower() } end
	table.sort(tail, function(a, b) return a.key < b.key end)

	-- Build pages using actual row sizes. A row with a long name starts the next page
	-- instead of being stepped over whenever it cannot fit at the end of this one.
	local pages, first, used = { 1 }, 1, 0
	local capacity = #baseline - #out
	for i, e in ipairs(tail) do
		local cost = #wire[e.i] + 1
		if i - first >= capacity or used + cost > room then
			pages[#pages + 1], first, used = i, i, 0
		end
		used = used + cost
	end
	local page = math.floor(now / Data.GLOBAL_ROTATE_EVERY) % #pages + 1
	for i = pages[page], (pages[page + 1] or #tail + 1) - 1 do Add(tail[i].i) end
	-- Use any slack on the last page for newer guilds that have not yet been included.
	for i = 1, #baseline do Add(i) end
	return out
end

function Data.GlobalCensusPayload()
	if not GlobalTrusted(ns.me) and not GlobalMember() then return nil end
	local now, scoped = math.floor(ns.Now()), ScopedGroup(ns.group)
	local head, out = ("CG~%d~S~%d~"):format(Data.GLOBAL_PROTOCOL, now), {}
	if scoped then head = ("CG~2~S~%d~%s~%s~"):format(now, ns.group, ns.faction or "Alliance") end
	local rows, bytes = SendableRows(), #head
	for _, e in ipairs(rows) do
		if #out >= Data.GLOBAL_MAX_ROWS then break end
		local row = GlobalWireRow(e)
		local extra = #row + (#out > 0 and 1 or 0)
		if bytes + extra > Data.GLOBAL_SEND_BYTES then break end
		out[#out + 1], bytes = row, bytes + extra
	end
	local omitted = rows[#out + 1]
	if scoped and #out > 1 and omitted and now - omitted.observed <= Data.TOTAL_KEEP then
		out = RotateGlobalRows(rows, out, bytes - #head + 1, now)
	end
	return head .. table.concat(out, ";")
end

function Data.SendGlobalCensus()
	-- Quiet presence (Core.lua): no snapshot of ours, which would name us as its sender online.
	if ns.QuietPresence and ns.QuietPresence() then return false end
	local trusted = GlobalTrusted(ns.me)
	if not trusted and not GlobalMember() then return false end
	local payload = Data.GlobalCensusPayload()
	if not payload or payload:sub(-1) == "~" then return false end
	-- 1.4.0: a member's answer is announced first by a one-piece claim, which reaches the channel
	-- long before the snapshot's pieces do, so the other members asked hold back (MEMBER_ANSWERS).
	if not trusted then
		ns.Comm.Send("CHANNEL", ("CG~%d~C~%d"):format(ScopedGroup(ns.group) and 2 or Data.GLOBAL_PROTOCOL, math.floor(ns.Now())), "census-global-claim")
	end
	-- A keyed job carries its permit, which the transport asks before each piece goes out
	-- (Comm.lua's NormalizeOptions refuses a key without one, and the snapshot then never left):
	-- the channel's lane alone, and only while this client still holds what it sent as (a trusted
	-- relay's trust, or a member's membership).
	local key = "census-global"
	return ns.Comm.SendChunked(payload, false, "CHANNEL", nil, { owner = Data, key = key,
		permit = function(_, guardKey, dist, target)
			if guardKey ~= key or dist ~= "CHANNEL" or target ~= nil then return false, "lane" end
			if trusted and not GlobalTrusted(ns.me) then return false, "trust" end
			if not trusted and not GlobalMember() then return false, "member" end
			return true
		end })
end

-- The answers (claims and snapshots) heard lately, and how many came since a time.
local function HeardAnswer(now, trusted, sender)
	local person = PersonKey(sender)
	if not person then return end
	for i = #answersHeard, 1, -1 do
		local a = answersHeard[i]
		-- A claim and its following snapshot are ONE answer, as are an alt's repeats.
		if now - a.t > 10 * 60 or a.person == person then table.remove(answersHeard, i) end
	end
	if #answersHeard >= 32 then table.remove(answersHeard, 1) end
	answersHeard[#answersHeard + 1] = { t = now, trusted = trusted == true, person = person }
end
local function AnswersSince(t)
	local n, trusted = 0, false
	for _, a in ipairs(answersHeard) do
		if a.t >= t then n, trusted = n + 1, trusted or a.trusted end
	end
	return n, trusted
end
-- An asker behind this client: it holds fewer guilds, or its newest observation is older than ours
-- by more than FRESH. An ask of 1.3.3 says nothing of what it holds: answered as before.
local function Behind(n, newest)
	if not n then return true end
	local mine, mineNewest = Data.GlobalDigest()
	return mine > n or mineNewest > (newest or 0) + Data.FRESH
end
local function AnswerAsk(body, now)
	local trusted = GlobalTrusted(ns.me)
	if not trusted and not GlobalMember() then return true end
	if now - globalLastAnswered < Data.GLOBAL_ANSWER_GAP or globalAnswerPending then return true end
	local n, newest = tostring(body or ""):match("^(%d+)~(%d+)$")
	if not Behind(tonumber(n), tonumber(newest)) then return true end
	globalAnswerPending = true
	local heardAt = globalLastHeard
	local delay = trusted and math.random(2, 9) or (Data.MEMBER_ANSWER_AFTER + math.random(0, Data.MEMBER_ANSWER_SPREAD))
	ns.After(delay, "global census answer", function()
		globalAnswerPending = false
		if ns.Now() - globalLastAnswered < Data.GLOBAL_ANSWER_GAP then return end
		if GlobalTrusted(ns.me) then
			if globalLastHeard <= heardAt and Data.SendGlobalCensus() then globalLastAnswered = ns.Now() end
			return
		end
		local count, byTrusted = AnswersSince(now)
		if byTrusted or count >= Data.MEMBER_ANSWERS then return end
		if GlobalMember() and Data.SendGlobalCensus() then globalLastAnswered = ns.Now() end
	end)
	return true
end

-- Public for the focused harness.  The server-stamped sender is the trust boundary: a trusted
-- relay's rows are taken as they come; any other member's are witnesses (TakeWitness), taken when
-- two people agree. The rows themselves are never mistaken for signed census authority.
function Data.ReceiveGlobalCensus(dist, sender, text)
	if dist ~= "CHANNEL" or type(text) ~= "string" or type(sender) ~= "string"
		or #text > Data.GLOBAL_MAX_BYTES or sender == "" or #sender > 100 or sender:find("[%c~]") then return false end
	local ver, kind, made, body = text:match("^CG~(%d+)~([SQC])~(%d*)~?(.*)$")
	ver = tonumber(ver)
	if ver ~= Data.GLOBAL_PROTOCOL and ver ~= 2 then return Refused("cg", "format", sender) end
	local now = ns.Now()
	local self = OwnWord(sender) -- (the relay's stamped copy of our own snapshot too)
	if kind == "C" then
		if ver == 1 and ScopedGroup(ns.group) then return false end
		-- A member's claim: its snapshot follows. It counts as an answer heard (AnswerAsk).
		if not self then HeardAnswer(now, GlobalTrusted(sender), sender) end
		return true
	end
	if kind == "Q" then
		-- A query grants no authority and the answer is broadcast to the channel.  Requiring
		-- the requester itself to be a keeper made anti-entropy useless for the ordinary late
		-- client it was designed to heal.  Only snapshot senders need the trusted-relay gate.
		if self then return true end
		return AnswerAsk(body, now)
	end
	if self then return true end
	if ver == 2 then
		local group, faction, rows = body:match("^([^~]+)~(%a+)~(.*)$")
		if group ~= ns.group or faction ~= (ns.faction or "Alliance") then return Refused("cg", "scope", sender) end
		body = rows
	elseif ScopedGroup(ns.group) then return false end
	local trusted = GlobalTrusted(sender)
	-- (1.5.5) A trusted row a guildmate handed over (RG): display only for a trusted holder (GlobalTake).
	local rg = trusted and Hop() == "G"
	local snapshotAt = GlobalNumber(made, 1, 4102444800)
	if not snapshotAt or snapshotAt > now + 5 * 60 or now - snapshotAt > Data.KEEP then return Refused("cg", "time", sender) end
	local changed, count, bad = false, 0, false
	for row in tostring(body):gmatch("[^;]+") do
		if count >= Data.GLOBAL_MAX_ROWS then bad = true; break end
		local name, total, online, avg10, observed = row:match("^([^,]+),(%d+),(%d+),(%d+),(%d+)$")
		if not name then bad = true; break end
		count = count + 1
		if trusted then
			Tally("cg", "trusted")
			if GlobalTake(name, total, online, avg10, observed, sender, now, nil, rg) then changed = true end
		else
			local r = GlobalRow(name, total, online, avg10, observed)
			if r then
				local took, agreed = TakeWitness(r, sender, now)
				Tally("cg", agreed and "witnessed" or "lone")
				if took then changed = true end
			end
		end
	end
	-- (1.4.0: the rows taken before a malformed one stay, and now say so.)
	TrimGlobal()
	if changed then Data.ChangedSoon() end
	if bad or count == 0 then return Refused("cg", "row", sender) end
	globalLastHeard = now
	HeardAnswer(now, trusted, sender)
	-- (1.5.4) The King's own snapshot (his relay's, every Relay.GLOBAL_EVERY, held by his quiet
	-- presence: Comm.QUIET_WORDS) is his word too: he is online (Hop.SignedKingPresence).
	if ns.Hop and ns.Hop.HeardKing then ns.Hop.HeardKing(sender) end
	return true
end

-- The ask, with what this client holds (Data.GlobalDigest): a holder with nothing newer stays quiet.
function Data.AskGlobalCensus()
	local n, newest = Data.GlobalDigest()
	return ns.Comm.Send("CHANNEL", ("CG~%d~Q~%d~%d~%d"):format(Data.GLOBAL_PROTOCOL, math.floor(ns.Now()), n, newest), "census-global-ask")
end

local function SummaryGuilds()
	local out, direct, now = {}, {}, ns.Now()
	for name, g in pairs(ns.rdb.guilds or {}) do
		if LocalReport(g) then out[name], direct[name:lower()] = g, name end
	end
	-- 1.3.3: our own guild comes straight from our roster, never from a relayed copy of another
	-- member's report (as in Take), so Stats and the site export keep our own count.
	local mine = GetGuildInfo("player")
	mine = mine and mine:lower()
	for _, e in ipairs(GlobalRows()) do
		local key = e.name:lower()
		local currentName = out[e.name] and e.name or direct[key]
		local current = out[currentName]
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
	local localGuilds, scoped = ns.rdb.guilds or {}, ScopedGroup(ns.group)
	local known = {}
	for name in pairs(guilds) do known[name:lower()] = true end
	local s = { total = 0, online = 0, fresh = 0, newest = 0, guilds = {}, zones = {}, zoneGuilds = {}, zoneList = {} }
	for name, g in pairs(guilds) do
		if ns.IsFederation(name) and not NetOff(name) then
			-- A forwarded report can arrive long after its roster was read. Keep the
			-- receipt for transport and votes, while Forever census totals use the read.
			local received, stamp = tonumber(g.t) or 0, ObservationTime(g)
			local observed = scoped and stamp > 0 and math.min(stamp, received) or received
			local age = now - observed
			local fresh = age <= Data.FRESH
			-- A guild keeps its size from its last report when its reporters log off (the army
			-- does not shrink every night), for a day; listed (grey) for a week; who is online
			-- and where only count while fresh.
			if age <= Data.KEEP then
				local row = { name = name, g = g, observed = observed, fresh = fresh, counted = age <= Data.TOTAL_KEEP }
				-- A count-only snapshot can be newer than a valid roster detail report. Keep
				-- recent player levels beside the display row, without attaching ranks to it.
				local levels = g.relayed and localGuilds[direct[name:lower()]] or g
				if fresh and type(levels.top) == "table" and #levels.top > 0 and now - ObservationTime(levels) <= Data.FRESH
					and (levels.faction or "Alliance") == (ns.faction or "Alliance") then
					row.topLevels, row.topRealm = levels.top, levels.realm
				end
				s.guilds[#s.guilds + 1] = row
				if age <= Data.TOTAL_KEEP then s.total = s.total + math.min(g.total or 0, ns.Codec.GUILD_CAP) end
			end
			if fresh then
				s.fresh = s.fresh + 1
				s.online = s.online + (g.online or 0)
				if observed > s.newest then s.newest = observed end
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
	if Data.ApplyGroupSnapshot then Data.ApplyGroupSnapshot(s, now) end
	return s
end

---------------------------------------------------------------------------
-- 1.4.0: every server's numbers (the author, 11-03: "o número principal ele vai contar do servidor
-- que você tá, em cima, o número de personagens e o número de pessoas. Quando você clica, aí tem o
-- número total de personagens, o número total de pessoas ... quantas pessoas estão no PVP, se a
-- pessoa tiver no PVE, ou vice-versa ... todos os servidores ... Europa, e América do Norte ... os
-- números do beta não devem ser utilizados").
-- The game shows a client its own realm group alone. Another group's numbers reach it only through
-- a player who was there: this account's own last look at each group it played (kept account-wide,
-- ns.db.groupCensus, as the census it held there: Data.Summary), and what other players who were
-- there say on our channel (CX). A trusted relay's word stands alone; anyone else's is a witness, and
-- a group's numbers are taken when two people's agree (the author's rule of 10-20), with a window and
-- a share wider than the guilds' (GROUP_WINDOW, GROUP_SHARE): they looked at different moments. A
-- lone witness is listed grey and stays out of the totals. The beta's realm groups never count on a
-- launch realm. A Forever origin names its ruleset and has no assigned region. Other realm groups
-- get their ruleset and region from the author's signed realm table (ns.RealmInfo).
---------------------------------------------------------------------------
Data.GROUP_PROTOCOL = 1
Data.GROUP_KEEP = 7 * 24 * 60 * 60  -- listed this long after it was seen
Data.GROUP_COUNT = 48 * 60 * 60     -- (1.5.8) a held look covering more guilds is kept against a newer narrow one this long
Data.GROUP_WINDOW = 2 * 60 * 60     -- two people's looks agree within this...
Data.GROUP_SHARE = 0.10             -- ...and within max(WITNESS_SLACK, this share)
Data.GROUP_MAX = 64                 -- groups kept per faction
Data.GROUP_SAY_AFTER = 20           -- channel/relay startup, then a small spread
Data.GROUP_SAY_EVERY = 30 * 60
Data.GROUP_SAY_SPREAD = 20
Data.GROUP_SEND_GAP = 65            -- one atomic origin after the relay's 60-second trickle refill
Data.GROUP_SAY_MAX = 24             -- rows in one word
Data.BETA_REALMS = { ClassicBetaPvP = true, ClassicBetaPvP2 = true }
local groupHeard = {}   -- [key] = the newest look at that group heard on our channel (this session)
-- (1.5.5) [key] = the newest look heard from a Church ledger relay: what a 1.5.4 client counts too.
local groupHeardLedger = {}
local portableCursor, portableSent, legacySent = 0, {}, -math.huge
-- (1.5.5) The author's checked looks (QA, below): when each origin's was last said here, and heard.
local attestCursor, attestSent, attestHeard = 0, {}, {}
local groupTicker = false
local groupWitness = {} -- [key] = { [person] = row }: the witnesses heard this session

local function GroupStore(which)
	local db = ns.db
	if type(db) ~= "table" then return {} end
	local name = which == "heard" and "groupHeard" or "groupCensus"
	db[name] = type(db[name]) == "table" and db[name] or {}
	return db[name]
end
local function GroupKey(faction, group) return faction .. "|" .. group end
local function GroupField(group)
	if type(group) ~= "string" or group == "" or #group > 160 or group:find("[|;~,%c]") then return nil end
	-- Old clients retained sub-realms as separate origins. Canonicalize on ingress, before
	-- voting or comparing with ours; mixed rulesets can never name one census origin.
	local family, other
	for realm in group:gmatch("[^+]+") do
		local f = ScopedRealm(realm)
		if f then
			if family and family ~= f then return nil end
			family = f
		else other = true end
	end
	if family then return not other and family or nil end
	return group
end
local function OurFaction() return ns.faction == "Horde" and "Horde" or "Alliance" end

-- A group of the beta's realms.
function Data.IsBetaGroup(group)
	for realm in tostring(group or ""):gmatch("[^+]+") do
		if Data.BETA_REALMS[realm] then return true end
	end
	return false
end
-- (1.4.0, the author: "todos os bans e tudo que tinha do beta tem que ser limpo") Whether something
-- this account noted on realm group `noted` is the beta's while `here` is a launch realm group: then
-- it never applies here. A note of a build before 1.4.0 names no group (nil or ""): Olympus ran on
-- the beta's realms alone then, so it is the beta's. On the beta's own group everything applies.
function Data.BetaOnLaunch(noted, here)
	if Data.IsBetaGroup(here) then return false end
	if type(noted) ~= "string" or noted == "" then return true end
	return Data.IsBetaGroup(noted)
end
-- A Forever family's ruleset ("ForeverRPPvP": "rppvp"), by its rules word in lower case (1.5.5: the
-- [Olympus] dropdown's families too, Channels.lua).
Data.RULES_KIND = { pve = "pve", pvp = "pvp", rp = "rp", rppvp = "rppvp", hardcore = "hardcore", hc = "hardcore" }
-- The kind ("pvp", "pve", "rp", "rppvp", "hardcore") and region ("NA", "EU") of a group, from the
-- first of its realms the signed realm table names; nil, nil while none is known.
function Data.GroupInfo(group)
	local info = ns.RealmInfo
	group = tostring(group or "")
	-- (1.5.1, the dev on his PvP character: the totals told PvE from PvP on no server) A Forever
	-- family ("ForeverPvE", "ForeverPvP") is no realm of the signed table: its ruleset is its name,
	-- its region the first of its realms this client met or the signed table names.
	local rules = group:match("^Forever(%a+)$")
	-- A plain Forever realm, or realms (a group learned before 1.4.6): its family's.
	if not rules and ns.ForeverFamily then
		local first = group:match("^[^+]+")
		local fam = first and ns.ForeverFamily(first)
		if fam then rules = fam:match("^Forever(%a+)$"); group = fam end
	end
	if rules then
		local kind = Data.RULES_KIND[rules:lower()]
		local realms = {}
		for _, r in ipairs(type(ns.GroupRealms) == "function" and ns.GroupRealms(group) or {}) do realms[#realms + 1] = r end
		local pins = type(ns.SignedPins) == "function" and ns.SignedPins() or nil
		if pins and type(pins.realms) == "table" then
			local keys = {}
			for key in pairs(pins.realms) do if key:find("^camwow%a%a%d+realm%d+" .. rules:lower() .. "$") then keys[#keys + 1] = key end end
			table.sort(keys)
			for _, key in ipairs(keys) do realms[#realms + 1] = key end
		end
		for _, realm in ipairs(realms) do
			local ok, i = pcall(type(info) == "function" and info or function() end, realm)
			local region = ok and type(i) == "table" and i.region or nil
			if not region then
				local code = realm:upper():match("^CAMWOW(%u%u)")
				region = code == "US" and "NA" or code == "EU" and "EU" or nil
			end
			if region then return kind, region end
		end
		return kind, nil
	end
	if type(info) ~= "function" then return nil, nil end
	for realm in group:gmatch("[^+]+") do
		local ok, i = pcall(info, realm)
		if ok and type(i) == "table" then return i.kind, i.region end
	end
	return nil, nil
end

-- A row as it is kept and sent, checked: { group, faction, characters, people, guilds, observed }.
local function GroupRow(group, faction, characters, people, guilds, observed)
	group = GroupField(group)
	if faction ~= "Alliance" and faction ~= "Horde" then return nil end
	characters = GlobalNumber(characters, 1, Data.MAX_GUILDS * ns.Codec.GUILD_CAP)
	people = characters and GlobalNumber(people, 0, characters)
	guilds = GlobalNumber(guilds, 0, Data.MAX_GUILDS)
	observed = GlobalNumber(observed, 1, 4102444800)
	if not (group and characters and people and guilds and observed) then return nil end
	local now = ns.Now()
	if observed > now + 5 * 60 or now - observed > Data.GROUP_KEEP then return nil end
	return { group = group, faction = faction, characters = characters, people = people, guilds = guilds, observed = observed }
end
-- Whether a group's numbers belong on this client's page: never the beta's on a launch realm.
local function Listed(group)
	return not Data.IsBetaGroup(group) or Data.IsBetaGroup(ns.group)
end

local function PruneGroups(now)
	for _, which in ipairs({ "counted", "heard" }) do
		local store = GroupStore(which)
		local per = {}
		for key, e in pairs(store) do
			local row = type(e) == "table" and GroupRow(e.group, e.faction, e.characters, e.people, e.guilds, e.observed)
			if not row then
				store[key] = nil
			else
				e.characters, e.people, e.guilds, e.observed = row.characters, row.people, row.guilds, row.observed
				per[e.faction] = per[e.faction] or {}
				table.insert(per[e.faction], { key = key, observed = e.observed })
			end
		end
		for _, list in pairs(per) do
			if #list > Data.GROUP_MAX then
				table.sort(list, function(a, b) return a.observed > b.observed end)
				for i = Data.GROUP_MAX + 1, #list do store[list[i].key] = nil end
			end
		end
	end
	-- The channel's corroborations and suppression hints are bounded too, including invented
	-- group names. Neither hundreds of senders nor hundreds of origins can grow this session.
	local keys = {}
	for key, list in pairs(groupWitness) do
		local entries = {}
		for person, row in pairs(list) do
			if now - row.observed > Data.GROUP_KEEP then list[person] = nil
			else entries[#entries + 1] = { person = person, observed = row.observed } end
		end
		table.sort(entries, function(a, b)
			if a.observed ~= b.observed then return a.observed > b.observed end
			return a.person < b.person
		end)
		for i = Data.WITNESS_MAX + 1, #entries do list[entries[i].person] = nil end
		if entries[1] then keys[#keys + 1] = { key = key, observed = entries[1].observed }
		else groupWitness[key] = nil end
	end
	table.sort(keys, function(a, b)
		if a.observed ~= b.observed then return a.observed > b.observed end
		return a.key < b.key
	end)
	for i = Data.GROUP_MAX * 2 + 1, #keys do groupWitness[keys[i].key] = nil end
	for _, heard in ipairs({ groupHeard, groupHeardLedger }) do
		for key, observed in pairs(heard) do
			if now - observed > Data.GROUP_KEEP or (not groupWitness[key] and not GroupStore()[key]) then heard[key] = nil end
		end
	end
end

-- This client's own look at its realm group: the census it holds now (Data.Summary). Taken by the
-- census page's sampler (CensusStats.Sample, every quarter-hour once the census is rebuilt) and at
-- logout, so a player who goes to another group carries it there.
function Data.RecordGroupCensus(s, now)
	local group = GroupField(ns.group)
	if not group then return false end
	s, now = s or Data.Summary(), now or ns.Now()
	if s.snapshot then return false end -- a displayed fallback is never a new observation
	local counted, observed = 0, now
	for _, e in ipairs(s.guilds or {}) do
		if e.counted then counted, observed = counted + 1, math.min(observed, ObservationTime(e.g)) end
	end
	local row = GroupRow(group, OurFaction(), tonumber(s.characters or s.total) or 0, tonumber(s.total) or 0, counted, observed)
	if not row then return false end
	row.src = "own"
	GroupStore()[GroupKey(row.faction, row.group)] = row
	GroupStore("heard")[GroupKey(row.faction, row.group)] = nil
	if Data.CaptureGroupDetails then Data.CaptureGroupDetails(s, now) end
	if Data.CapturePortable then Data.CapturePortable(row) end
	PruneGroups(now)
	return true
end

-- During reconciliation, a partial roster must not erase the last counted view of this
-- origin. Only the displayed totals fall back: no guild, officer, rank or online presence is
-- fabricated. Consumers can label the observation and inspect the partial live totals below.
function Data.ApplyGroupSnapshot(s, now)
	if not (ns.Comm and ns.Comm.loginAt) then return end
	local group = GroupField(ns.group)
	local held
	for _, e in pairs(GroupStore()) do
		if type(e) == "table" and GroupField(e.group) == group and e.faction == OurFaction()
			and GroupRow(e.group, e.faction, e.characters, e.people, e.guilds, e.observed)
			and (not held or e.observed > held.observed) then held = e end
	end
	if not held then return end
	local counted, refreshed, freshGuilds, freshCharacters = 0, 0, 0, 0
	for _, e in ipairs(s.guilds) do
		if e.counted then
			counted = counted + 1
			local observed = ObservationTime(e.g)
			if observed >= held.observed then refreshed = refreshed + 1 end
			if now - observed <= Data.FRESH then
				freshGuilds = freshGuilds + 1
				freshCharacters = freshCharacters + math.min(e.g.total or 0, ns.Codec.GUILD_CAP)
			end
		end
	end
	-- Enough newer guild reports reconcile the saved coverage. An extra older row cannot veto them.
	if not held.unscoped and refreshed >= held.guilds and s.characters > 0 then return end
	local snapshot = { group = group, faction = held.faction, observed = held.observed, source = held.src,
		witnesses = held.w, characters = held.characters, people = held.people, guilds = held.guilds,
		age = math.max(0, now - held.observed), unscoped = held.unscoped,
		counted = not held.unscoped and now - held.observed <= Data.TOTAL_KEEP }
	if not snapshot.counted then s.history = snapshot; return end
	-- The last-day sum can include old reports. Show the fresh subset separately so the retained
	-- total cannot hide changes in the guilds that are still reporting.
	s.live = { characters = s.characters, people = s.total, alts = s.alts, guilds = counted,
		freshGuilds = freshGuilds, freshCharacters = freshCharacters }
	s.snapshot = snapshot
	s.characters, s.total, s.alts = held.characters, held.people, held.characters - held.people
end

local function GroupAgree(a, b)
	if math.abs(a.observed - b.observed) > Data.GROUP_WINDOW then return false end
	local big = math.max(a.characters, b.characters)
	return math.abs(a.characters - b.characters) <= math.max(Data.WITNESS_SLACK, Data.GROUP_SHARE * big)
end
local function GroupLater(a, b)
	if a.observed ~= b.observed then return a.observed > b.observed end
	if a.characters ~= b.characters then return a.characters > b.characters end
	return a.people > b.people
end
-- Another group's row heard from `sender`: taken (true when what this client counts changed), and how
-- it was heard (Data.CensusStats): "author", "trusted", "witnessed", "heard" (a lone witness) or "unproven".
-- (1.5.5) A trusted row of the author's characters is kept as his (src "author", Data.CensusTrusted),
-- the newest observation winning, its observed time as it came. src: a checked look's (QA) "author",
-- whoever carried it. row.rg: a trusted row a guildmate handed over (RG), never said again (GroupCensusPayload).
local function TakeGroup(row, sender, trusted, now, src)
	local key = GroupKey(row.faction, row.group)
	if row.group == GroupField(ns.group) and row.faction == OurFaction() then return false end -- our own: we see it live
	local store = GroupStore()
	local held = store[key]
	-- Legacy CX rows have no original observer. Two forwarding clients are not
	-- two independent observations; retain their numbers as reported only.
	if row.unproven then
		local heard = GroupStore("heard")
		local old = heard[key]
		if not old or old.observed < row.observed then
			row.src, row.by, row.w, row.rg = "heard", ns.FullName(sender), 0, nil
			heard[key] = row
		end
		return false, "unproven"
	end
	local function Keep(r, src, w)
		if type(held) == "table" and (tonumber(held.observed) or 0) >= r.observed then
			-- (1.5.5) The same look again on a stamped hop: no longer a hand-over alone.
			if held.rg and not r.rg and tonumber(held.observed) == r.observed and held.src == src then held.rg = nil end
			return false
		end
		store[key] = { group = r.group, faction = r.faction, characters = r.characters, people = r.people, guilds = r.guilds,
			observed = r.observed, src = src, by = ns.FullName(sender), w = w, rg = r.rg or nil }
		local h = GroupStore("heard")[key]
		if type(h) == "table" and (tonumber(h.observed) or 0) <= r.observed then GroupStore("heard")[key] = nil end
		return true
	end
	if trusted then
		src = src or (AuthorIdentity(sender) and "author" or "relay")
		-- (1.5.4) While a look is still counted, a newer trusted one covering under half its guilds
		-- does not replace it: a client that saw only its own guild there is not the family's count.
		-- (The review of the 1.5.4 candidate.) Refused before it is noted as heard (groupHeard: a
		-- refused look silenced this client's own wider one), and the other way round too: a trusted
		-- look covering more than twice the guilds of the counted one replaces it even when older,
		-- while it still counts itself (a one-guild look heard first kept out the 19-guild one).
		local counted = type(held) == "table" and now - (tonumber(held.observed) or 0) <= Data.GROUP_COUNT
		local heldGuilds = counted and (tonumber(held.guilds) or 0) or 0
		local how = src == "author" and "author" or "trusted"
		if row.guilds * 2 < heldGuilds then return false, how end
		groupHeard[key] = math.max(groupHeard[key] or 0, row.observed)
		-- (1.5.5) A Church ledger relay's look is one a 1.5.4 client counts too: only such a look keeps a
		-- trusted holder from saying the family's row for them (GroupCensusPayload).
		if LedgerRelay(sender) then groupHeardLedger[key] = math.max(groupHeardLedger[key] or 0, row.observed) end
		if counted and heldGuilds * 2 < row.guilds and now - row.observed <= Data.GROUP_COUNT then held = nil end -- (Keep's age check)
		return Keep(row, src, 1), how
	end
	local who = PersonKey(sender)
	if not who then return false end
	local list = groupWitness[key] or {}
	groupWitness[key] = list
	list[who] = row
	PruneGroups(now)
	local entries = {}
	for _, e in pairs(list) do entries[#entries + 1] = e end
	-- Only two independent senders actually heard on THIS channel suppress our broadcast.
	-- Our own saved observation can corroborate locally, but other listeners still need us.
	for i = 1, #entries do
		for j = i + 1, #entries do
			if GroupAgree(entries[i], entries[j]) then
				groupHeard[key] = math.max(groupHeard[key] or 0, math.max(entries[i].observed, entries[j].observed))
			end
		end
	end
	if type(held) == "table" and held.src == "own" then entries[#entries + 1] = held end
	local best
	for i = 1, #entries do
		for j = i + 1, #entries do
			local a, b = entries[i], entries[j]
			if GroupAgree(a, b) then
				local newer = GroupLater(b, a) and b or a
				if not best or GroupLater(newer, best) then best = newer end
			end
		end
	end
	if best and best ~= held and Keep(best, "witnessed", 2) then return true, "witnessed" end
	-- A lone witness: listed grey (its newest), never counted.
	if not (type(held) == "table" and held.observed >= row.observed) then
		local heard = GroupStore("heard")
		local old = heard[key]
		if not (type(old) == "table" and (tonumber(old.observed) or 0) >= row.observed) then
			heard[key] = { group = row.group, faction = row.faction, characters = row.characters, people = row.people,
				guilds = row.guilds, observed = row.observed, src = "heard", by = ns.FullName(sender), w = 1 }
		end
	end
	return false, best and "witnessed" or "heard"
end

-- What this client sends: its rows of the OTHER groups (ours everyone here sees live), its own looks
-- and those it took, newer than what was said here lately; the beta's never on a launch realm.
-- (1.5.4) A Forever family's row only from a trusted client, whose word stands alone (1.4.0, "a
-- moderator's alone"): 1.5.2 kept every family out, so no client that never played the other family
-- ever counted it (the dev, 11-08: "para mim mostra os dados ... não mostra para ninguém"). A row
-- kept under a plain realm (learned before 1.4.6, a sub-realm's partial view) never travels.
-- (The review of the 1.5.4 candidate.) And only the trusted client's own look (src "own"): a row it
-- took from someone else, a forged one among them, is never said again in its trusted name (in a
-- later session nothing heard suppressed it).
-- (1.5.4) Our side's rows alone: an account that plays both sides said its Horde look to the
-- Alliance network and the reverse, so each side's totals held the other's (the dev, 11-08: "só
-- para diferenciar, para não cruzar os dados"). The other side's rows stay kept, for its own
-- characters' client (Data.Groups).
-- (1.5.5) The author's client says every family row of our side it counts (its own looks, and the
-- relays', the witnessed and his own it took), each with its original observed time: the trusted
-- distributor. Any other trusted client (a councillor, the King, a keeper) also says the author's rows
-- it took, for the clients that count only the Church's ledger relays (1.5.4 and older): what it heard
-- from the author keeps it quiet no more, only what it heard from a ledger relay (groupHeardLedger),
-- which those clients counted. No trusted client says a row it took over a guildmate's hand-over (rg).
local AUTHOR_SAYS = { own = true, relay = true, witnessed = true, author = true }
-- (1.5.8) The rows a trusted source gave (our own look, a trusted origin's, the author's): counted until
-- a newer one replaces them (Data.Groups). A witnessed row or a guildmate's hand-over (rg) counts GROUP_COUNT.
local LASTING_SRC = { own = true, relay = true, author = true }
function Data.GroupCensusPayload(now)
	now = now or ns.Now()
	local trusted = GlobalTrusted(ns.me)
	local author = trusted and AuthorIdentity(ns.me)
	local rows, byOrigin = {}, {}
	local side = OurFaction()
	for _, e in pairs(GroupStore()) do
		local row = type(e) == "table" and e.faction == side and GroupRow(e.group, e.faction, e.characters, e.people, e.guilds, e.observed)
		local key = row and GroupKey(row.faction, row.group)
		local say, heard = row and not ScopedGroup(row.group), groupHeard
		-- (1.5.8) The newest trusted look held is said however old it is (GROUP_KEEP at most, GroupRow): it
		-- counts until a newer one replaces it (Data.Groups), so a holder keeps carrying it to late clients.
		-- A witnessed row (two untrusted looks agreeing) is said only while it counts, GROUP_COUNT.
		if row and not say and trusted and e.group == row.group and not e.rg then
			if author then say = AUTHOR_SAYS[e.src] == true and (LASTING_SRC[e.src] == true or now - row.observed <= Data.GROUP_COUNT)
			else say, heard = e.src == "own" or e.src == "author", groupHeardLedger end
		end
		if say and not e.unscoped and row.group ~= GroupField(ns.group) and Listed(row.group)
			and row.observed > (heard[key] or 0) + Data.FRESH then
			if not byOrigin[key] or GroupLater(row, byOrigin[key]) then byOrigin[key] = row end
		end
	end
	for _, row in pairs(byOrigin) do rows[#rows + 1] = row end
	if #rows == 0 then return nil end
	table.sort(rows, function(a, b) return GroupLater(a, b) end)
	local out = {}
	for i = 1, math.min(#rows, Data.GROUP_SAY_MAX) do
		local r = rows[i]
		-- (1.5.4) Commas: every client's Comm drops a received message's "|" before any handler reads
		-- it (0.9.2, Comm's OnAddonMessage), so the rows 1.4.0 sent with "|" never parsed anywhere.
		out[#out + 1] = ("%s,%s,%d,%d,%d,%d"):format(r.group, r.faction, r.characters, r.people, r.guilds, r.observed)
	end
	return ("CX~%d~S~%d~%s"):format(Data.GROUP_PROTOCOL, math.floor(now), table.concat(out, ";"))
end

function Data.SayGroupCensus()
	if ns.QuietPresence and ns.QuietPresence() then return false end
	if not GlobalTrusted(ns.me) and not GlobalMember() then return false end
	local now = ns.Now()
	local payload, origin, index, observed
	-- (1.5.5) The author's checked look of an origin first, when one is due here (Data.AttestPayload).
	local attest
	if Data.AttestPayload then payload, origin, index, observed = Data.AttestPayload(now, true) end
	attest = payload ~= nil
	if not payload and Data.PortablePayload then payload, origin, index, observed = Data.PortablePayload(now, true) end
	if not payload and now - legacySent >= Data.GROUP_SAY_EVERY then payload = Data.GroupCensusPayload(now) end
	if not payload then return false end
	local trusted = GlobalTrusted(ns.me)
	local key = (attest and "census-attest" or "census-groups") .. (origin and ":" .. origin or "")
	local accepted = ns.Comm.SendChunked(payload, false, "CHANNEL", nil, { owner = Data, key = key,
		permit = function(_, guardKey, dist, target)
			if guardKey ~= key or dist ~= "CHANNEL" or target ~= nil then return false, "lane" end
			if trusted and not GlobalTrusted(ns.me) then return false, "trust" end
			if not trusted and not GlobalMember() then return false, "member" end
			return true
		end }) == true
	if accepted and attest then
		attestSent[origin] = { at = now, observed = observed }
		attestCursor = index
	elseif accepted then
		if origin then
			portableSent[origin] = { at = now, observed = observed }
			portableCursor = index
		else legacySent = now end
	end
	return accepted
end

function Data.ReceiveGroupCensus(dist, sender, text)
	if dist ~= "CHANNEL" or type(text) ~= "string" or type(sender) ~= "string"
		or #text > Data.GLOBAL_MAX_BYTES or sender == "" or #sender > 100 or sender:find("[%c~]") then return false end
	-- Our own word back (the relay's copy, stamped with its sub-realm: OwnWord): never news, of any
	-- kind. Taken as another councillor's, a trusted client's own look was noted as heard and never said again.
	if OwnWord(sender) then return true end
	if text:sub(1, 5) == "CX~3~" then return Data.ReceivePortable(sender, text) end
	if text:sub(1, 5) == "CX~2~" then return Data.ReceiveGroupDetails(sender, text) end
	local ver, made, body = text:match("^CX~(%d+)~S~(%d+)~(.*)$")
	if tonumber(ver) ~= Data.GROUP_PROTOCOL then return Refused("cx", "format", sender) end
	local now = ns.Now()
	local at = GlobalNumber(made, 1, 4102444800)
	if not at or at > now + 5 * 60 or now - at > Data.GROUP_KEEP then return Refused("cx", "time", sender) end
	local trusted = GlobalTrusted(sender)
	-- (1.5.5) A trusted row a guildmate handed over (RG): counted here, never said again (rg).
	local rg = trusted and Hop() == "G"
	local changed, count = false, 0
	for part in tostring(body):gmatch("[^;]+") do
		if count >= Data.GROUP_SAY_MAX then break end
		count = count + 1
		local g, f, c, p, n, o = part:match("^([^|,]+)[|,](%a+)[|,](%d+)[|,](%d+)[|,](%d+)[|,](%d+)$")
		local row = g and GroupRow(g, f, c, p, n, o)
		if row then
			-- A Forever family's row without an original observer: a trusted sender's word alone,
			-- anyone else's reported only (1.5.2: forwarders are not independent witnesses).
			row.unproven = ScopedGroup(row.group) ~= nil and not trusted
			row.rg = rg or nil
			if Listed(row.group) then
				local took, how = TakeGroup(row, sender, trusted, now)
				if how then Tally("cx", how) end
				if took then changed = true end
			end
		end
	end
	PruneGroups(now)
	if count == 0 then return Refused("cx", "row", sender) end
	if changed then Data.ChangedSoon() end
	return true
end

-- Every server this client knows of, for the census page: { rows = { { group, faction, characters,
-- people, guilds, observed, src, w, kind, region, counted, ours } }, characters, people, kinds =
-- { [kind or "?"] = { characters, people } }, regions = { [region or "?"] = {...} }, factions = {...} }.
-- Ours is the census held now (Data.Summary); the others as kept; a lone witness listed, not counted.
function Data.Groups(s, now)
	now = now or ns.Now()
	s = s or Data.Summary()
	local out = { rows = {}, characters = 0, people = 0, kinds = {}, regions = {}, factions = {} }
	local seen = {}
	local function Add(e, counted, ours)
		-- A saved plain Forever realm or compound alias describes the same ruleset as the
		-- canonical group. Keep just the newest row for that population.
		local groupName = GroupField(e.group)
		if not groupName then return end
		local key = GroupKey(e.faction, groupName)
		if seen[key] then return end
		seen[key] = true
		local kind, region = Data.GroupInfo(groupName)
		local forever = ScopedRealm(groupName) ~= nil
		-- A Forever family can contain homes in several regions. Its relay's or
		-- first known realm's region does not locate the aggregate's population.
		if forever then region = nil end
		local row = { group = groupName, faction = e.faction, characters = e.characters, people = e.people, guilds = e.guilds,
			observed = e.observed, src = e.src, w = e.w, kind = kind, region = region, counted = counted, ours = ours,
			canonicalGroup = groupName, product = forever and "forever" or nil,
			era = Data.IsBetaGroup(groupName) and "beta" or (forever and "launch" or nil),
			unscoped = e.unscoped, validation = e.unscoped and "origin-unknown" or (e.src == "heard" and "reported" or "accepted"),
			fresh = now - e.observed <= Data.FRESH }
		out.rows[#out.rows + 1] = row
		if not counted then return end
		out.characters, out.people = out.characters + e.characters, out.people + e.people
		out.oldest = out.oldest and math.min(out.oldest, e.observed) or e.observed
		out.newest = math.max(out.newest or 0, e.observed)
		for _, pair in ipairs({ { out.kinds, kind or "?" }, { out.regions, region or "?" }, { out.factions, e.faction } }) do
			local t = pair[1][pair[2]] or { characters = 0, people = 0 }
			t.characters, t.people = t.characters + e.characters, t.people + e.people
			pair[1][pair[2]] = t
		end
	end
	local group = GroupField(ns.group)
	if group and (tonumber(s.characters or s.total) or 0) > 0 then
		local counted, observed = 0, now
		for _, e in ipairs(s.guilds or {}) do
			if e.counted then counted, observed = counted + 1, math.min(observed, ObservationTime(e.g)) end
		end
		local snapshot = s.snapshot
		Add({ group = group, faction = OurFaction(), characters = tonumber(s.characters or s.total) or 0,
			people = tonumber(s.total) or 0, guilds = snapshot and snapshot.guilds or counted,
			observed = snapshot and snapshot.observed or observed, src = snapshot and snapshot.source or "live",
			w = snapshot and snapshot.witnesses }, true, true)
	end
	-- (1.5.4) Our side's rows alone, listed and summed: the other side's are kept in the account-wide
	-- store for its own characters' client (an account that plays both sides sees its Horde rows on
	-- the Horde), never on this side's page or in its totals.
	local side = OurFaction()
	local kept = {}
	for _, e in pairs(GroupStore()) do
		if type(e) == "table" and e.faction == side and GroupRow(e.group, e.faction, e.characters, e.people, e.guilds, e.observed) and Listed(e.group) then kept[#kept + 1] = e end
	end
	table.sort(kept, GroupLater)
	-- (1.5.8, the author, 11-12: "ele deveria redistribuir esses dados enquanto não tivessem dados novos
	-- na rede") Another origin's trusted look (LASTING_SRC, not a hand-over) counts until a newer accepted
	-- look of that origin takes its place (TakeGroup), dated as it was observed (the census page's "As
	-- of"): it no longer leaves the totals after GROUP_COUNT, which emptied the PvP count on every client
	-- two days after the last look anyone carried. A witnessed row (two untrusted looks agreeing) or a
	-- guildmate's hand-over still counts GROUP_COUNT. Our own origin's saved row keeps the day of a guild
	-- report (TOTAL_KEEP).
	for _, e in ipairs(kept) do
		local ours = GroupField(e.group) == group
		local lasting = not ours and LASTING_SRC[e.src] == true and not e.rg
		Add(e, not e.unscoped and (lasting or now - e.observed <= (ours and Data.TOTAL_KEEP or Data.GROUP_COUNT)), ours)
	end
	local heard = {}
	for _, e in pairs(GroupStore("heard")) do
		if type(e) == "table" and e.faction == side and GroupRow(e.group, e.faction, e.characters, e.people, e.guilds, e.observed) and Listed(e.group) then heard[#heard + 1] = e end
	end
	table.sort(heard, GroupLater)
	for _, e in ipairs(heard) do Add(e, false, false) end
	table.sort(out.rows, function(a, b)
		if a.ours ~= b.ours then return a.ours end
		if a.counted ~= b.counted then return a.counted end
		if a.characters ~= b.characters then return a.characters > b.characters end
		return a.group < b.group
	end)
	return out
end

-- 1.5.2: bounded detail for the other origins. CX1's totals stay interoperable; CX2 carries only
-- public census numbers, never a leader, officer, member list, rank, location or private data.
-- These rows NEVER enter rdb.guilds or censusGlobal, even on returning to their origin.
Data.GROUP_DETAIL_MAX = 8
Data.GROUP_DETAIL_WITNESSES = 4
local detailWitness, detailHeard, detailCursor = {}, {}, 0
local function DetailStore()
	if type(ns.db) ~= "table" then return {} end
	ns.db.groupDetails = type(ns.db.groupDetails) == "table" and ns.db.groupDetails or {}
	return ns.db.groupDetails
end
local function PruneDetails(now)
	local store, origins = DetailStore(), {}
	for key, entry in pairs(store) do
		if type(entry) ~= "table" or type(entry.rows) ~= "table" or not GroupField(entry.group)
			or (entry.faction ~= "Alliance" and entry.faction ~= "Horde") or now - (tonumber(entry.observed) or 0) > Data.KEEP then
			store[key] = nil
		else origins[#origins + 1] = { key = key, observed = entry.observed } end
	end
	for key, list in pairs(detailWitness) do
		for person, e in pairs(list) do if now - e.at > Data.WITNESS_KEEP then list[person] = nil end end
		if not next(list) then detailWitness[key] = nil
		elseif not store[key] then
			local newest = 0
			for _, e in pairs(list) do newest = math.max(newest, e.at) end
			origins[#origins + 1] = { key = key, observed = newest }
		end
	end
	table.sort(origins, function(a, b)
		if a.observed ~= b.observed then return a.observed > b.observed end
		return a.key < b.key
	end)
	for i = Data.GROUP_DETAIL_MAX + 1, #origins do
		local key = origins[i].key
		store[key], detailWitness[key] = nil, nil
	end
	for key, e in pairs(detailHeard) do
		if now - e.at > Data.GROUP_SAY_EVERY or (not store[key] and not detailWitness[key]) then detailHeard[key] = nil end
	end
end
local function DetailRows(body)
	local rows, count = {}, 0
	for text in body:gmatch("[^;]+") do
		count = count + 1
		if count > Data.GLOBAL_MAX_ROWS then return nil end
		local name, total, online, avg10, observed = text:match("^([^,]+),(%d+),(%d+),(%d+),(%d+)$")
		local row = name and GlobalRow(name, total, online, avg10, observed)
		if not row or rows[row.name:lower()] then return nil end
		rows[row.name:lower()] = row
	end
	return count > 0 and rows or nil
end
local function DetailBody(rows)
	local ordered = {}
	for _, row in pairs(rows) do ordered[#ordered + 1] = row end
	table.sort(ordered, function(a, b)
		if a.observed ~= b.observed then return a.observed > b.observed end
		return a.name < b.name
	end)
	local out, bytes = {}, 0
	for i = 1, math.min(#ordered, Data.GLOBAL_MAX_ROWS) do
		local r = ordered[i]
		local line = ("%s,%d,%d,%d,%d"):format(r.name, r.total, r.online, r.avg10, r.observed)
		if bytes + #line + 1 > Data.GLOBAL_MAX_BYTES - 220 then break end
		out[#out + 1], bytes = line, bytes + #line + 1
	end
	return table.concat(out, ";")
end
function Data.CaptureGroupDetails(s, now)
	local group = GroupField(ns.group)
	if not group or s.snapshot then return false end
	local rows, observed = {}, 0
	for _, e in ipairs(s.guilds or {}) do
		local g = e.g
		local r = e.counted and type(g) == "table" and GlobalRow(e.name, g.total, g.online or 0, Data.AvgTenths(g) or 0, ObservationTime(g))
		if r then rows[r.name:lower()] = r; observed = math.max(observed, r.observed) end
	end
	local bounded = DetailRows(DetailBody(rows))
	if not bounded then return false end
	for _, row in pairs(bounded) do row.source = "own" end
	local faction = OurFaction()
	DetailStore()[GroupKey(faction, group)] = { group = group, faction = faction, observed = observed,
		rows = bounded, source = "own", by = ns.FullName(ns.me) }
	PruneDetails(now or ns.Now())
	return true
end
function Data.ReceiveGroupDetails(sender, text)
	local made, origin, faction, body = text:match("^CX~2~S~(%d+)~([^~]+)~(%a+)~(.*)$")
	local now, group = ns.Now(), GroupField(origin)
	local at = GlobalNumber(made, 1, 4102444800)
	if not group or not Listed(group) or not at or at > now + 300 or now - at > Data.KEEP
		or (faction ~= "Alliance" and faction ~= "Horde") then return false end
	local rows = DetailRows(body)
	if not rows then return false end
	-- The old format omits its original observer and must not turn relays into votes.
	-- (1.5.5) But for the author's own capsule of a family (SayGroupDetails), trusted on its hop: his count.
	local trusted = GlobalTrusted(sender)
	local label = trusted and AuthorIdentity(sender) and "author" or "relay"
	if ScopedGroup(group) and label ~= "author" then return true end
	local who = PersonKey(sender)
	if not who or who == PersonKey(ns.me) then return true end
	local key, store = GroupKey(faction, group), DetailStore()
	local old = store[key]
	local witnesses = detailWitness[key] or {}
	detailWitness[key] = witnesses
	body = DetailBody(rows)
	local corroborated = trusted
	for person, e in pairs(witnesses) do
		if person ~= who and now - e.at <= Data.WITNESS_KEEP and e.body == body then corroborated = true end
	end
	if corroborated then
		detailHeard[key] = { body = body, at = now, here = GroupKey(OurFaction(), GroupField(ns.group) or "?") }
	end
	-- Keep compact wire bodies for pending witnesses; parse at most four bounded candidates.
	witnesses[who] = { at = now, body = body }
	local order = {}
	for person, e in pairs(witnesses) do order[#order + 1] = { person = person, at = e.at } end
	table.sort(order, function(a, b) if a.at ~= b.at then return a.at > b.at end return a.person < b.person end)
	for i = Data.GROUP_DETAIL_WITNESSES + 1, #order do witnesses[order[i].person] = nil end
	local candidates = {}
	if not trusted then
		for person, e in pairs(witnesses) do
			if person ~= who and now - e.at <= Data.WITNESS_KEEP then candidates[#candidates + 1] = DetailRows(e.body) end
		end
		if old and old.by and PersonKey(old.by) ~= who then
			local own = {}
			for name, row in pairs(old.rows) do if row.source == "own" then own[name] = row end end
			candidates[#candidates + 1] = own
		end
	end
	local accepted, newest = {}, 0
	for name, row in pairs(rows) do
		local confirmed = trusted
		local best = row
		for _, other in ipairs(candidates) do
			local candidate = other[name]
			if Data.WitnessesAgree(row, candidate) then
				confirmed = true
				if candidate.observed > best.observed or (candidate.observed == best.observed and candidate.total > best.total) then best = candidate end
			end
		end
		if confirmed then
			accepted[name] = { name = best.name, total = best.total, online = best.online, avg10 = best.avg10, observed = best.observed,
				source = trusted and label or "witnessed", witnesses = trusted and 1 or 2 }
			newest = math.max(newest, best.observed)
		end
	end
	if not next(accepted) then PruneDetails(now); return true end
	-- An incremental capsule cannot erase rows that it did not carry, nor replace newer evidence.
	for name, row in pairs(old and old.rows or {}) do
		if now - row.observed <= Data.KEEP and (not accepted[name] or accepted[name].observed < row.observed) then
			accepted[name], newest = row, math.max(newest, row.observed)
		end
	end
	local bounded = DetailRows(DetailBody(accepted))
	if bounded then
		for name, r in pairs(bounded) do r.source, r.witnesses = accepted[name].source or (old and old.source), accepted[name].witnesses end
		store[key] = { group = group, faction = faction, observed = newest, rows = bounded,
			source = trusted and label or "witnessed", by = old and old.by }
		Data.ChangedSoon()
	end
	PruneDetails(now)
	return true
end
function Data.GroupGuilds(group, faction)
	group = GroupField(group)
	local e = group and DetailStore()[GroupKey(faction or OurFaction(), group)]
	if e and e.unscoped then return {} end
	local out, now = {}, ns.Now()
	for _, r in pairs(e and e.rows or {}) do
		if now - r.observed <= Data.KEEP then
			out[#out + 1] = { name = r.name, characters = r.total, online = r.online, avg10 = r.avg10,
				observed = r.observed, source = r.source or e.source, witnesses = r.witnesses,
				fresh = now - r.observed <= Data.FRESH,
				counted = (r.source or e.source) ~= "heard" and now - r.observed <= Data.TOTAL_KEEP }
		end
	end
	table.sort(out, function(a, b) if a.characters ~= b.characters then return a.characters > b.characters end return a.name < b.name end)
	return out
end
-- (1.5.9) The Forever family ("ForeverPvE") whose census lists guild `name`, for the [Olympus] picker's
-- rulesets (Channels.lua): our own census (ns.rdb.guilds, our family's reports) and the other families'
-- rows kept within KEEP (the group details, Data.GroupGuilds), our side's alone, by name in any case.
-- nil when none lists it, or two families do: one name in two families says nothing about the speaker.
function Data.GuildFamily(name)
	if type(name) ~= "string" or name == "" then return nil end
	local found
	local function Seen(family)
		if family == nil then return true end
		if found ~= nil and found ~= family then return false end
		found = family
		return true
	end
	local ours = ScopedGroup(GroupField(ns.group) or "")
	if ours and LocalReport(Data.Guild(name)) then Seen(ours) end
	local now, lower, side = ns.Now(), name:lower(), OurFaction()
	for _, e in pairs(DetailStore()) do
		local row = type(e) == "table" and e.faction == side and not e.unscoped and type(e.rows) == "table" and e.rows[lower]
		if type(row) == "table" and now - (tonumber(row.observed) or 0) <= Data.KEEP then
			if not Seen(ScopedGroup(GroupField(e.group) or "")) then return nil end
		end
	end
	return found
end
function Data.SayGroupDetails()
	if not GlobalMember() then return false end
	PruneDetails(ns.Now())
	local keys = {}
	-- (1.5.4: our side's capsules alone, as GroupCensusPayload says only our side's rows.)
	-- (1.5.5) The author's client says its own capsules of the Forever families too (his count of each).
	local author = GlobalTrusted(ns.me) and AuthorIdentity(ns.me)
	for key, e in pairs(DetailStore()) do
		if e.faction == OurFaction() and (not ScopedGroup(e.group) or (author and e.source == "own")) and not e.unscoped
			and Listed(e.group) and e.group ~= GroupField(ns.group) then keys[#keys + 1] = key end
	end
	if #keys == 0 then return false end
	table.sort(keys)
	for _ = 1, #keys do
		detailCursor = detailCursor % #keys + 1
		local key = keys[detailCursor]
		local e, heard = DetailStore()[key], detailHeard[key]
		local body = DetailBody(e.rows)
		-- One trusted sender or two actual channel witnesses already supplied this capsule.
		-- A later character on another origin still carries it there; one ordinary sender
		-- never suppresses the independent second traveller needed to validate it.
		local known = heard and heard.here == GroupKey(OurFaction(), GroupField(ns.group) or "?") and heard.body == body
		if body ~= "" and not known then
			local payload = ("CX~2~S~%d~%s~%s~%s"):format(ns.Now(), e.group, e.faction, body)
			return ns.Comm.SendChunked(payload, false, "CHANNEL", nil, { owner = Data, key = "census-group-details",
				permit = function(_, guardKey, dist, target)
					return guardKey == "census-group-details" and dist == "CHANNEL" and target == nil and GlobalMember(), "member"
				end }) == true
		end
	end
	return false
end

-- Portable observations keep the original observer, scope and observation date
-- byte-for-byte at every hop. This is provenance, not an identity certificate:
-- an ordinary forwarder can transport a report but cannot become another vote.
-- Unknown originals remain visible, dated and uncounted. Existing authenticated
-- direct observations still use TakeGroup's trust/corroboration policy.
-- One logical chunk is atomic under the ordinary relay's trickle. With two
-- chunks a busy reporter could receive the first and lose the second forever.
-- The complete aggregate always fits; only whole detail rows use spare bytes.
Data.PORTABLE_MAX_BYTES = ns.Codec.CHUNK
local function PortableStore()
	if type(ns.db) ~= "table" then return {} end
	ns.db.groupPortable = type(ns.db.groupPortable) == "table" and ns.db.groupPortable or {}
	return ns.db.groupPortable
end
local function PortableTrim(now)
	local store, order = PortableStore(), {}
	for key, e in pairs(store) do
		if type(e) ~= "table" or type(e.wire) ~= "string" or #e.wire > Data.PORTABLE_MAX_BYTES
			or now - (tonumber(e.observed) or 0) > Data.GROUP_KEEP then store[key] = nil
		else order[#order + 1] = { key = key, at = e.observed, own = e.own == true } end
	end
	table.sort(order, function(a, b)
		if a.own ~= b.own then return a.own end
		if a.at ~= b.at then return a.at > b.at end
		return a.key < b.key
	end)
	for i = Data.GROUP_MAX + 1, #order do store[order[i].key] = nil end
	local present = {}
	for _, e in pairs(store) do present[GroupKey(e.faction, e.group)] = true end
	for origin in pairs(portableSent) do if not present[origin] then portableSent[origin] = nil end end
end
local function PortableKeep(observer, row, wire, own)
	local key = GroupKey(row.faction, row.group) .. "|" .. (PersonKey(observer) or observer:lower())
	local store = PortableStore()
	local old = store[key]
	if old and old.own and not own then return end
	if not old or old.observed < row.observed or (own and old.observed == row.observed and old.wire ~= wire) then
		store[key] = { observer = observer, group = row.group, faction = row.faction,
			observed = row.observed, wire = wire, own = own == true }
	end
	PortableTrim(ns.Now())
end
-- (1.5.5) The author's signed look (QA): a look of his own account's (CX 3, as CapturePortable makes
-- it) signed with his account key (Debts.lua's ns.db.arenaKey, one per WoW account, the same on every
-- character of it), whose public half is ns.AUTHOR_ATTEST_PK. It proves itself, so it counts as the
-- author's (src "author") whoever carries it, a provisional relay or an old client's guildmate among
-- them: the one route that reaches every client of a family whatever relay serves it.
--   QA~1~<sig>~<look>   sig: base64url (86 characters) of the Ed25519 signature of "OLYQA1|" .. look
-- About 320 bytes: two pieces (Comm.SendChunked). Checked off the frame (Ed25519.Run), once per word.
-- An empty constant signs nothing and takes nothing. Every client keeps the newest checked look of
-- each origin (ns.db.groupAttest, account-wide: a player carries it to the other family) and says it
-- once each GROUP_SAY_EVERY there, unless it heard one of that origin as new within the window.
local function AttestKey()
	local pk, Ed = ns.AUTHOR_ATTEST_PK, ns.Ed25519
	if type(pk) ~= "string" or pk == "" or type(Ed) ~= "table" or type(Ed.FromB64) ~= "function" then return nil end
	local raw = Ed.FromB64(pk)
	return raw ~= nil and #raw == 32 and raw or nil
end
local function AttestStore()
	if type(ns.db) ~= "table" then return {} end
	ns.db.groupAttest = type(ns.db.groupAttest) == "table" and ns.db.groupAttest or {}
	return ns.db.groupAttest
end
local function AttestKeep(row, wire, text, own)
	local store, origin = AttestStore(), GroupKey(row.faction, row.group)
	local old = store[origin]
	local at = type(old) == "table" and tonumber(old.observed) or 0
	if at > row.observed or (at == row.observed and old.own and not own) then return end
	store[origin] = { group = row.group, faction = row.faction, observed = row.observed, wire = wire, text = text, own = own == true or nil }
end
-- Our own look signed, when this client holds the author's account key, and not signed already.
local function SignLook(row, wire)
	local k = type(ns.db) == "table" and ns.db.arenaKey
	if not AttestKey() or type(k) ~= "table" or k.pk ~= ns.AUTHOR_ATTEST_PK then return false end
	local old = AttestStore()[GroupKey(row.faction, row.group)]
	if type(old) == "table" and old.own and old.wire == wire then return false end
	local D = ns.Debts
	if type(D) ~= "table" or type(D.Sign) ~= "function" then return false end
	local ok, sig = pcall(D.Sign, "OLYQA1|" .. wire)
	if not ok or type(sig) ~= "string" or #sig ~= 64 then return false end
	AttestKeep(row, wire, "QA~1~" .. ns.Ed25519.ToB64(sig) .. "~" .. wire, true)
	Tally("qa", "signed")
	return true
end
function Data.CapturePortable(row)
	if not ScopedGroup(row.group) then return false end
	local observer = ns.FullName(ns.me)
	if type(observer) ~= "string" or #observer > 100 or observer:find("[~|;,%c]") then return false end
	local details = DetailStore()[GroupKey(row.faction, row.group)]
	local body = details and not details.unscoped and DetailBody(details.rows) or ""
	local head = ("CX~3~S~%s~%s~%s~%d,%d,%d,%d~"):format(observer, row.group, row.faction,
		row.characters, row.people, row.guilds, row.observed)
	if #head > Data.PORTABLE_MAX_BYTES then return false end
	local parts, bytes = {}, #head
	for line in body:gmatch("[^;]+") do
		local extra = #line + (#parts > 0 and 1 or 0)
		if bytes + extra > Data.PORTABLE_MAX_BYTES then break end
		parts[#parts + 1], bytes = line, bytes + extra
	end
	local wire = head .. table.concat(parts, ";")
	PortableKeep(observer, row, wire, true)
	SignLook(row, wire) -- (1.5.5)
	return true
end
-- (1.5.4) One look carries an origin: this account's own, else the one covering the most guilds, then
-- the newest. Walking every observer's look let a newer one-guild look stand for the origin through
-- its window, and the account's own complete look was skipped every time (the dev's store of 11-07:
-- 21 one-guild looks said in 45 minutes, never its own 19 guilds of PvP). One word per origin a window.
local function PortableGuilds(e)
	return tonumber(tostring(e.wire):match("^CX~3~S~[^~]+~[^~]+~%a+~%d+,%d+,(%d+),%d+~")) or 0
end
local function PortableBetter(a, b)
	if (a.own == true) ~= (b.own == true) then return a.own == true end
	local ga, gb = PortableGuilds(a), PortableGuilds(b)
	if ga ~= gb then return ga > gb end
	if a.observed ~= b.observed then return a.observed > b.observed end
	return a.wire < b.wire
end
function Data.PortablePayload(now, sending)
	now = now or ns.Now()
	PortableTrim(now)
	local store, best, keys = PortableStore(), {}, {}
	for key, e in pairs(store) do
		if Listed(e.group) then
			local origin = GroupKey(e.faction, e.group)
			if not best[origin] or PortableBetter(e, store[best[origin]]) then best[origin] = key end
		end
	end
	for _, key in pairs(best) do keys[#keys + 1] = key end
	if #keys == 0 then return nil end
	table.sort(keys)
	for offset = 1, #keys do
		local index = (portableCursor + offset - 1) % #keys + 1
		local e = store[keys[index]]
		local origin = GroupKey(e.faction, e.group)
		local previous = portableSent[origin]
		local localOrigin = e.group == GroupField(ns.group) and e.faction == OurFaction()
		if not sending then return e.wire end
		if not localOrigin and (not previous or now - previous.at >= Data.GROUP_SAY_EVERY or e.observed > previous.observed) then
			return e.wire, origin, index, e.observed
		end
	end
end
-- (1.5.5) The next checked look of the author's to say here (QA, above): the text, its origin, its
-- place in the turn and its observed time; nil when none is due. Never our own origin's.
function Data.AttestPayload(now, sending)
	now = now or ns.Now()
	if not AttestKey() then return nil end
	local store, keys = AttestStore(), {}
	for origin, e in pairs(store) do
		if type(e) ~= "table" or type(e.text) ~= "string" or now - (tonumber(e.observed) or 0) > Data.GROUP_KEEP then
			store[origin] = nil
		elseif e.faction == OurFaction() and Listed(e.group) and e.group ~= GroupField(ns.group) then
			keys[#keys + 1] = origin
		end
	end
	if #keys == 0 then return nil end
	table.sort(keys)
	for offset = 1, #keys do
		local index = (attestCursor + offset - 1) % #keys + 1
		local origin = keys[index]
		local e = store[origin]
		if not sending then return e.text end
		local sent, heard = attestSent[origin], attestHeard[origin]
		local due = not sent or now - sent.at >= Data.GROUP_SAY_EVERY or e.observed > sent.observed
		local covered = heard ~= nil and now - heard.at < Data.GROUP_SAY_EVERY and heard.observed >= e.observed
		if due and not covered then return e.text, origin, index, e.observed end
	end
end
-- A look as the wire carries it, checked: { observer, row, rows (its guilds, or nil), faction, wire }.
local function ParseLook(text)
	if type(text) ~= "string" or #text > Data.PORTABLE_MAX_BYTES then return nil end
	local observer, origin, faction, c, p, n, o, body = text:match("^CX~3~S~([^~]+)~([^~]+)~(%a+)~(%d+),(%d+),(%d+),(%d+)~(.*)$")
	if not observer or #observer > 100 or observer:find("[|;,%c]") then return nil end
	local row = GroupRow(origin, faction, c, p, n, o)
	if not row or not Listed(row.group) then return nil end
	local rows = body ~= "" and DetailRows(body) or nil
	if body ~= "" and not rows then return nil end
	return { observer = observer, row = row, rows = rows, faction = faction, wire = text }
end
-- A look taken: kept to carry on, and counted as its proof allows (TakeGroup). src: a checked look's.
local function TakeLook(look, direct, trusted, src)
	local row, rows, observer, faction = look.row, look.rows, look.observer, look.faction
	PortableKeep(observer, row, look.wire)
	if row.group == GroupField(ns.group) and faction == OurFaction() then return true end
	row.unproven = not direct
	row.rg = (trusted and src == nil and Hop() == "G") or nil -- (a guildmate's hand-over: never said again)
	TakeGroup(row, observer, trusted, ns.Now(), src)
	if rows then
		local key, store = GroupKey(faction, row.group), DetailStore()
		local old = store[key]
		-- (1.5.5) The guilds in the author's own look are his word too (as his capsule, ReceiveGroupDetails).
		local label = trusted and (src == "author" or AuthorIdentity(observer)) and "author" or "heard"
		if not old or old.source == "heard" or old.unscoped or (label == "author" and old.source == "author") then
			local newest = 0
			for _, r in pairs(rows) do r.source = label; newest = math.max(newest, r.observed) end
			if not old or old.unscoped or newest > old.observed or (label == "author" and old.source == "heard") then
				store[key] = { group = row.group, faction = faction, observed = newest, rows = rows, source = label, by = observer }
			end
		end
	end
	PruneGroups(ns.Now()); PruneDetails(ns.Now())
	Data.ChangedSoon() -- reported-only origins and details are visible too
	return true
end
-- (1.5.5) A look is direct when its observer sends it, or when the author's client carries a look its
-- own family's author character made (both his, on the observer's own family: Relay.IsLaunchAuthor or
-- the signed list), on a trusted hop. The author's client carrying anyone else's look would launder it:
-- unproven, as any forwarder's.
-- (1.5.8, the review of the census-pvp candidate) A look a signed councillor's character took counts
-- when that character itself sends it (direct, above), never when another trusted character carries
-- it: every client keeps each look it hears (TakeLook, unproven ones too) and says the widest of an
-- origin (PortablePayload), so a member's forged look naming a councillor's character, heard by a
-- trusted client with no own look of that origin, came out under that client's trusted name and
-- counted everywhere. A councillor has no signing key: only the author's looks prove themselves
-- whoever carries them (QA below), and they cross the relay mesh (Relay.lua's Across).
local function AuthorLook(sender, look)
	if not (AuthorIdentity(look.observer) and AuthorIdentity(sender) and GlobalTrusted(sender)) then return false end
	local family = ScopedGroup(look.row.group)
	return family == nil or ns.ForeverFamily(ns.RealmOf(ns.FullName(look.observer)) or "") == family
end
function Data.ReceivePortable(sender, text)
	local look = ParseLook(text)
	if not look then return Refused("cx", "look", sender) end
	local direct = ns.FullName(sender):lower() == ns.FullName(look.observer):lower()
	local trusted, how = direct and GlobalTrusted(sender), direct and "direct" or "unproven"
	if not direct and AuthorLook(sender, look) then direct, trusted, how = true, true, "author" end
	Tally("cx3", how)
	return TakeLook(look, direct, trusted)
end

-- (1.5.5) A checked look of the author's (QA, above) heard: kept for saying, and taken as his.
Data.ATTEST_MEMO = 64 -- checked words remembered (SHA-256 of the word -> valid or not)
-- Checks of ours in Ed25519's queue at once: its slots are the arena's signatures' too, so a flood of
-- forged words (a new signature each) takes two of them at most; the rest wait to be heard again.
Data.ATTEST_JOBS = 2
local attestMemo, attestOrder, attestJobs = {}, {}, 0
local function AttestMemo(id, value)
	if attestMemo[id] == nil then
		attestOrder[#attestOrder + 1] = id
		while #attestOrder > Data.ATTEST_MEMO do attestMemo[table.remove(attestOrder, 1)] = nil end
	end
	attestMemo[id] = value
end
local function TakeAttest(look, text)
	local row, now = look.row, ns.Now()
	local origin = GroupKey(row.faction, row.group)
	local heard = attestHeard[origin]
	if not heard or now - heard.at >= Data.GROUP_SAY_EVERY or row.observed >= heard.observed then
		attestHeard[origin] = { at = now, observed = row.observed }
	end
	AttestKeep(row, look.wire, text)
	return TakeLook(look, true, true, "author")
end
function Data.ReceiveAttest(dist, sender, text)
	if dist ~= "CHANNEL" or type(text) ~= "string" or type(sender) ~= "string"
		or sender == "" or #sender > 100 or sender:find("[%c~]") then return false end
	if OwnWord(sender) then return true end
	local pk, Ed = AttestKey(), ns.Ed25519
	if not pk or type(Ed.Run) ~= "function" then return Refused("qa", "key", sender) end
	local sig64, wire = text:match("^QA~1~([%w%-_]+)~(CX~3~.+)$")
	local sig = sig64 and #sig64 == 86 and Ed.FromB64(sig64) or nil
	local look = sig and #sig == 64 and ParseLook(wire) or nil
	if not look then return Refused("qa", "format", sender) end
	local id = ns.Sign.SHA256(text)
	local known = attestMemo[id]
	if known == true then return TakeAttest(look, text) end
	if known == false then return Refused("qa", "signature", sender) end
	if known == "wait" then return true end
	-- Every slot of ours (ATTEST_JOBS) or of Ed25519's queue taken: refused now, checked when heard again.
	if attestJobs >= Data.ATTEST_JOBS then return Refused("qa", "busy", sender) end
	attestJobs = attestJobs + 1
	local settled = false
	local started = Ed.Run(function() return Ed.Verify(pk, "OLYQA1|" .. wire, sig) end, function(ok, valid)
		settled, attestJobs = true, math.max(0, attestJobs - 1)
		local good = ok == true and valid == true
		AttestMemo(id, good)
		if not good then return Refused("qa", "signature", sender) end
		Tally("qa", "verified")
		TakeAttest(look, text)
	end)
	if not started then
		attestJobs = math.max(0, attestJobs - 1)
		return Refused("qa", "busy", sender)
	end
	if not settled then AttestMemo(id, "wait") end
	return true
end

-- (1.5.5) What the census took, left unproven and refused since login, for /oly bug (the relay's
-- BugLines "census:" line): a copy, with the last refusals newest first and the whole as one line.
--   cg: trusted, witnessed, lone, refused (global rows)       cx: author, trusted, witnessed, heard, unproven, refused
--   cx3: direct, author, unproven (looks)                     qa: verified, refused, signed (the author's checked looks)
function Data.CensusStats()
	local out, now = { last = {} }, ns.Now()
	for kind, counts in pairs(censusStats) do
		local copy = {}
		for k, v in pairs(counts) do copy[k] = v end
		out[kind] = copy
	end
	local last = {}
	for i = #censusRefusals, 1, -1 do
		local r = censusRefusals[i]
		out.last[#out.last + 1] = { kind = r.kind, why = r.why, from = r.from, age = math.max(0, math.floor(now - r.t)) }
		last[#last + 1] = r.kind .. ":" .. r.why
	end
	local g, x, l, q = out.cg, out.cx, out.cx3, out.qa
	out.line = ("cg t%d w%d l%d r%d | cx a%d t%d w%d h%d u%d r%d | cx3 d%d a%d u%d | qa v%d r%d s%d"):format(
		g.trusted, g.witnessed, g.lone, g.refused, x.author, x.trusted, x.witnessed, x.heard, x.unproven, x.refused,
		l.direct, l.author, l.unproven, q.verified, q.refused, q.signed) .. (#last > 0 and (" | last " .. table.concat(last, ",")) or "")
	return out
end

local function SaySoon()
	ns.After(math.random(0, Data.GROUP_SAY_SPREAD), "census groups", function()
		ns.SafeCall("census groups", Data.SayGroupCensus)
		ns.SafeCall("census group details", Data.SayGroupDetails)
		if not groupTicker then
			groupTicker = true
			-- Retry a refused admission without skipping it; accepted foreign origins take turns.
			-- Per-origin windows prevent unchanged observations becoming a minute-by-minute broadcast.
			ns.Every(Data.GROUP_SEND_GAP, "census groups", Data.SayGroupCensus)
			ns.Every(Data.GROUP_SAY_EVERY, "census group details", Data.SayGroupDetails)
		end
	end)
end

ns.On("INIT", function()
	Data.MigrateCensusScope()
	local store, now = GlobalStore(), ns.Now()
	for key, e in pairs(store) do
		local row = type(key) == "string" and type(e) == "table" and GlobalRow(e.name, e.total, e.online, e.avg10, e.observed)
		if not row then store[key] = nil
		else e.total, e.online, e.avg10, e.observed = row.total, row.online, row.avg10, row.observed end
	end
	-- (1.4.0) The witnesses kept past a day, or of a guild no longer Olympus, go.
	local ws = ns.rdb.censusWitness
	if type(ws) == "table" then
		for key, list in pairs(ws) do
			if type(list) ~= "table" then
				ws[key] = nil
			else
				for person, e in pairs(list) do
					if type(e) ~= "table" or not GlobalGuildField(e.name) or now - (tonumber(e.heard) or 0) > Data.WITNESS_KEEP then list[person] = nil end
				end
				if next(list) == nil then ws[key] = nil end
			end
		end
	end
	if ns.Comm and ns.Comm.Handle then ns.Comm.Handle("CG", Data.ReceiveGlobalCensus) end
	TrimGlobal()
	ns.After(20, "global census ask", Data.AskGlobalCensus)
	-- (1.4.0) Once more after the evening's first minutes, when more of the army is on.
	ns.After(20 + Data.GLOBAL_ASK_AGAIN, "global census ask again", Data.AskGlobalCensus)
	ns.Every(Data.GLOBAL_ASK_EVERY, "global census ask", Data.AskGlobalCensus)
	-- Every server's numbers: foreign origins leave promptly in bounded turns after login;
	-- unchanged origins repeat at most once per half hour. Own looks are kept at logout/sampling.
	if ns.Comm and ns.Comm.Handle then ns.Comm.Handle("CX", Data.ReceiveGroupCensus) end
	-- (1.5.5) The author's checked looks (QA): taken by every 1.5.5 client, ignored by older ones.
	if ns.Comm and ns.Comm.Handle then ns.Comm.Handle("QA", Data.ReceiveAttest) end
	PruneGroups(now)
	PruneDetails(now)
	ns.After(Data.GROUP_SAY_AFTER, "census groups", SaySoon)
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
	-- (CR-02: the characters, as the window's header has them, then the people as the header gives
	-- them, CensusStats.PeopleText: 2026-10-20, a team client's "~" estimate.)
	local CS = ns.CensusStats
	local people = type(CS) == "table" and not CS.missing and type(CS.PeopleText) == "function" and CS.PeopleText(s) or L.ARMY_PEOPLE:format(F(s.total))
	out[#out + 1] = L.DISCORD_HEADER:format(F(s.characters or s.total), F(s.online), #s.guilds) .. " · " .. people
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
