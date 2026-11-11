local ADDON, ns = ...

-- Reads our own guild roster. Any member (not only officers) sees name, level,
-- class, zone and online state of everyone, which is all the census needs.

local Roster = {}
ns.Roster = Roster

local CLASS_CODES = {
	WARRIOR = "WA", PALADIN = "PA", HUNTER = "HU", ROGUE = "RO", PRIEST = "PR",
	SHAMAN = "SH", MAGE = "MA", WARLOCK = "WL", DRUID = "DR", DEATHKNIGHT = "DK",
}
local CLASS_FILES = {}
for file, code in pairs(CLASS_CODES) do CLASS_FILES[code] = file end
ns.CLASS_FILES = CLASS_FILES

function Roster.ClassCode(classFile)
	return classFile and (CLASS_CODES[classFile] or classFile) or ""
end

local SCAN_EVERY = 60
local MIN_GAP = 20
Roster.AUTHORITY_FRESH = 120
-- (1.2.3) The longest a GUID the client gave no race for waits before it is asked again.
Roster.RACE_RETRY = 600
local lastScan, pending = 0, false
local raceByGUID = {} -- [guid] = its race: one of racePairs' entries, shared (no table per member)
local racePairs = {}  -- [key .. "\0" .. name] = { key = raceFile (or the name), name = the game's name }
local raceWait, raceTryAt = {}, {} -- [guid] = the wait after its last failed lookup, when it is asked again

-- The guild roster gives every member's GUID but not their race.  The client can resolve that
-- stable GUID locally through GetPlayerInfoByGUID, including for offline guildmates.  Keep the
-- answer only on this client's in-memory roster: census reports deliberately do not grow a race
-- field, and a lookup which has not resolved yet is tried again on the next scan, then (1.2.3) after
-- a wait that doubles up to RACE_RETRY: a client that never answers for a GUID is no longer asked a
-- thousand times a minute.
local function PublicString(value)
	if value == nil then return nil end
	if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
	return type(value) == "string" and value ~= "" and value or nil
end

local function RaceForGUID(guid, now)
	guid = PublicString(guid)
	if not guid then return nil end
	local cached = raceByGUID[guid]
	if cached then return cached.key, cached.name end
	if type(GetPlayerInfoByGUID) ~= "function" then return nil end
	local tryAt = raceTryAt[guid]
	if tryAt and now < tryAt then return nil end
	local ok, _, _, raceName, raceFile = pcall(GetPlayerInfoByGUID, guid)
	if ok then raceName, raceFile = PublicString(raceName), PublicString(raceFile) end
	local key = ok and (raceFile or raceName) or nil
	if not key then
		-- (A scan comes about every SCAN_EVERY seconds, a few early or late: the scan due when the
		-- wait ends asks, not the one after it.)
		local wait = math.min(Roster.RACE_RETRY, (raceWait[guid] or SCAN_EVERY / 2) * 2)
		raceWait[guid], raceTryAt[guid] = wait, now + wait - MIN_GAP
		return nil
	end
	raceWait[guid], raceTryAt[guid] = nil, nil
	local id = key .. "\0" .. (raceName or "")
	cached = racePairs[id]
	if not cached then
		cached = { key = key, name = raceName }
		racePairs[id] = cached
	end
	raceByGUID[guid] = cached
	return cached.key, cached.name
end
local function DropRace(guid)
	raceByGUID[guid], raceWait[guid], raceTryAt[guid] = nil, nil, nil
end

local function RequestServerRoster()
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	elseif GuildRoster then
		GuildRoster()
	end
end

local function DaysOffline(i, isOnline)
	if isOnline or not GetGuildRosterLastOnline then return 0 end
	local y, m, d, h = GetGuildRosterLastOnline(i)
	if not y then return 0 end
	return (y or 0) * 365 + (m or 0) * 30 + (d or 0) + (h or 0) / 24
end

-- Where the counts below come from: the name as the server sent it ("bare" = no realm) and the
-- server id of the member's GUID. ns.FullName gives bare names our realm, so counting after
-- it could never tell two realms apart.
local function CountRaw(t, key)
	t[key] = (t[key] or 0) + 1
end

-- (1.2.3) What the last scans made, kept to be used again. Before, a 1,000-member guild's scan made
-- every row, byName and the order anew each minute and sorted every row, however little had changed
-- (some 500 KB of garbage offline: a heap that climbs until the collector runs). Now a member whose
-- every field is the same keeps his row: Roster.members' and Roster.online's rows are never written
-- after the scan that makes them (Members, Views, War, ChatRooms, DuesHistory, Recruit, HonorsNet...
-- only read them). The members' order is the last scan's when nobody moved in it, the few new or
-- moved rows put in where they go; byName is the last one while every name and rank in it is the
-- same. A table a reader has seen is never filled again: one held by a reader still says what it said
-- (HonorsNet keeps its levels by Roster.members, Borders and Nominees know byName by the table), and
-- a new table still means something changed.
local rowOf, onlineOf = {}, {}   -- [raw name] = his member row, his online row (while online), as last made
local seenAt, guidOf = {}, {}    -- [raw name] = the scan that last saw him, the GUID it gave
local realmOf, serverOf = {}, {} -- [raw name] = the realm in it (false: none), his GUID's server id
local rowCount = 0               -- the raw names in rowOf
local scans = 0
local rowsOf = {}                -- whose rows they are: guild, realm, ns.FullName and ns.DisplayName
local byIndex, indexed = {}, 0   -- this scan's rows in the server's order (indexed: the last scan's count)
local moved, movedAt = {}, {}    -- the rows new to the order or moved in it, and where each goes
local order, orderScan, orderStrict -- Roster.members as last made, the scan that made it, no two rows tied
local pubByName, pubCount        -- Roster.byName as last made, and how many names it holds
local INSERT_MAX = 64            -- more rows new or moved than this: one sort of every row, as before

local function Clear(t)
	for k in pairs(t) do t[k] = nil end
end
local function CountKeys(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

-- Members by level, then name; Captains online first, then by days away; who is online by rank,
-- level, then name (made once, not at each scan).
local function MemberBefore(a, b)
	if a.level ~= b.level then return a.level > b.level end
	return a.name < b.name
end
local function OfficerBefore(a, b)
	if a.online ~= b.online then return a.online end
	return a.days < b.days
end
local function OnlineBefore(a, b)
	if a.rankIndex ~= b.rankIndex then return a.rankIndex < b.rankIndex end
	if a.level ~= b.level then return a.level > b.level end
	return a.name < b.name
end

local function SameRow(row, level, code, race, raceName, rankIndex, rank, days, online)
	return row.level == level and row.class == code and row.race == race and row.raceName == raceName
		and row.rankIndex == rankIndex and row.rank == rank and row.days == days and row.online == online
end
local function SameOnline(o, short, level, code, zone, rank, rankIndex)
	return o.name == short and o.level == level and o.class == code and o.zone == zone and o.rank == rank
		and o.rankIndex == rankIndex
end

-- A member who left: what was kept of him, his GUID's race with it.
local function Forget(raw)
	if guidOf[raw] then DropRace(guidOf[raw]) end
	if rowOf[raw] then rowCount = rowCount - 1 end
	rowOf[raw], onlineOf[raw], seenAt[raw], guidOf[raw], realmOf[raw], serverOf[raw] = nil, nil, nil, nil, nil, nil
end

-- This scan's members (byIndex[1..n]) in the last scan's order: each of its rows still here at the
-- same level and name in its place, the m rows new or moved (moved[1..m]) put in where they go. Nil
-- when that might not be what one sort of every row gives: no order of the last scan to keep, a tie
-- in it, more rows to put in than INSERT_MAX, or one of them tied with another row.
local function KeptOrder(n, m, scan)
	local old = order
	if not (old and orderStrict and orderScan == scan - 1) or m > INSERT_MAX then return nil end
	if m > 1 then table.sort(moved, MemberBefore) end
	local size = #old
	for j = 1, m do
		local x = moved[j]
		if j > 1 and not MemberBefore(moved[j - 1], x) then return nil end
		local lo, hi = 1, size + 1
		while lo < hi do
			local mid = math.floor((lo + hi) / 2)
			if MemberBefore(old[mid], x) then lo = mid + 1 else hi = mid end
		end
		if lo <= size and not MemberBefore(x, old[lo]) then return nil end
		movedAt[j] = lo
	end
	-- (An array of the right size at once, every place of it written below: no array grown and
	-- left behind.)
	local out, k, j = { unpack(byIndex, 1, n) }, 0, 1
	for i = 1, size do
		while j <= m and movedAt[j] == i do
			k = k + 1
			out[k] = moved[j]
			j = j + 1
		end
		local e = old[i]
		if seenAt[e.raw] == scan then
			local row = rowOf[e.raw]
			if row.level == e.level and row.name == e.name then
				k = k + 1
				out[k] = row
			end
		end
	end
	while j <= m do
		k = k + 1
		out[k] = moved[j]
		j = j + 1
	end
	if k ~= n then return nil end
	return out
end

-- Every row sorted, as before 1.2.3, and whether no two of them tie (the next scan may keep it).
local function SortedOrder(n, dup)
	local out = { unpack(byIndex, 1, n) }
	table.sort(out, MemberBefore)
	local strict = not dup
	for k = 2, strict and n or 0 do
		if not MemberBefore(out[k - 1], out[k]) then
			strict = false
			break
		end
	end
	return out, strict
end

function Roster.Scan()
	-- The 4th return is the guild's home realm, nil when it is ours.
	local guild, _, _, home = GetGuildInfo("player")
	if not guild then return nil end
	home = type(home) == "string" and home:gsub("[%s%-]", "") or ""
	local started = debugprofilestop and debugprofilestop() or 0
	local numTotal, numOnline = GetNumGuildMembers()
	numTotal = numTotal or 0
	local officerRank = ns.CAPTAIN_RANK
	local r = {
		guild = guild, total = numTotal, online = 0,
		zones = {}, classes = {}, levels = { 0, 0, 0, 0, 0, 0, 0 },
		leader = nil, leaderOnline = false, leaderDays = 0,
		ranks = {}, officers = {}, inactive7 = 0, inactive30 = 0, avgLevel = 0, top = {},
	}
	-- Rank names in rank order (1 = guild master).
	local numRanks = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
	for i = 1, numRanks do r.ranks[i] = { name = GuildControlGetRankName(i) or ("Rank " .. i), count = 0 } end

	-- (1.2.3) Rows kept for another guild, realm or way of naming are of no use: all made anew.
	if rowsOf.guild ~= guild or rowsOf.realm ~= ns.realm or rowsOf.full ~= ns.FullName or rowsOf.display ~= ns.DisplayName then
		Clear(rowOf); Clear(onlineOf); Clear(seenAt); Clear(guidOf); Clear(realmOf); Clear(serverOf)
		Clear(raceByGUID); Clear(raceWait); Clear(raceTryAt)
		rowCount, order = 0, nil
		rowsOf.guild, rowsOf.realm, rowsOf.full, rowsOf.display = guild, ns.realm, ns.FullName, ns.DisplayName
	end
	if moved[1] or movedAt[1] then Clear(moved); Clear(movedAt) end -- (left by a scan that failed)
	scans = scans + 1
	local scan, now = scans, ns.Now()
	-- byName stays the last one while every row names the same rank in it (and nothing else in it).
	local keep = pubByName ~= nil and Roster.byName == pubByName and pubByName or nil
	local sameNames = keep ~= nil
	local seen, seenOffline, zoneCount, levelSum = 0, 0, 0, 0
	local distinct, bare, made, m, dup = 0, 0, 0, 0, false
	local online = {} -- who is online now, for the Realm tab (Views.MembersOf)
	local covered = 0 -- online, but under a cover name (Cover.lua) or private (PrivatePresence.lua): counted offline
	local rawRealms, servers, sample, sampleDash = {}, {}, nil, false -- for /oly status (names raw)
	for i = 1, numTotal do
		local name, rankName, rankIndex, level, _, zone, _, _, isOnline, _, classFile, _, _, _, _, _, guid = GetGuildRosterInfo(i)
		if name then
			local at, prev = seenAt[name], rowOf[name]
			local again = at == scan -- (the server gave him twice: each row as it came, as before)
			local wasHere = prev ~= nil and at == scan - 1
			-- (1.2.3) The realm his name came with and his GUID's server, worked out once for him.
			local server
			if not again then
				local g = PublicString(guid)
				if guidOf[name] ~= g then
					if guidOf[name] then DropRace(guidOf[name]) end
					guidOf[name], serverOf[name] = g, g and (g:match("^Player%-(%d+)%-") or "?")
				end
				server = serverOf[name]
			end
			local race, raceName = RaceForGUID(guid, now)
			seen = seen + 1
			local rawRealm = realmOf[name]
			if rawRealm == nil then
				rawRealm = name:match("%-(.+)$") or false
				if not again then realmOf[name] = rawRealm end
			end
			CountRaw(rawRealms, rawRealm or "bare")
			CountRaw(servers, server or (type(guid) == "string" and guid:match("^Player%-(%d+)%-")) or "?")
			if not sample or (rawRealm and not sampleDash) then sample, sampleDash = name, name:find("-", 1, true) ~= nil end
			-- Identity is "Name-Realm"; reports carry the short form for our own realm (kept with his
			-- row: the same raw name, realm and functions give the same).
			local full, short
			if prev then
				full, short = prev.full, prev.name
			else
				full = ns.FullName(name)
				short = ns.DisplayName(full)
			end
			-- A moderator under a cover name (Cover.lua) asked to be off the network: offline in
			-- every census and page we make of our roster.
			local C = ns.Cover
			if isOnline and C and C.Offline(full) then isOnline, covered = false, covered + 1 end
			-- (1.4.0) So is a guildmate whose Private presence told our guild (PrivatePresence.lua).
			local P = ns.PrivatePresence
			if isOnline and P and P.Offline and P.Offline(full) then isOnline, covered = false, covered + 1 end
			if full ~= name then bare = bare + 1 end
			rankIndex = rankIndex or 9
			if sameNames and keep[full] ~= rankIndex then sameNames = false end
			-- (The hours offline are read for every member offline at every scan, as before 1.2.3:
			-- offline at two scans, he may have logged in and out between them, and the hours read
			-- before would be days wrong. His row is still kept while they are the same.)
			local days = DaysOffline(i, isOnline)
			level = level or 1
			levelSum = levelSum + level
			local rank = r.ranks[rankIndex + 1]
			if not rank then
				rank = { name = rankName or ("Rank " .. (rankIndex + 1)), count = 0 }
				r.ranks[rankIndex + 1] = rank
			end
			rank.count = rank.count + 1
			local code = classFile and (CLASS_CODES[classFile] or classFile)
			local zoneKey = isOnline and ns.Zones.KeyForName(zone) or nil
			if rankIndex == 0 then
				r.leader = short
				r.leaderOnline = isOnline and true or false
				r.leaderDays = days
				r.leaderClass, r.leaderLevel, r.leaderZone = code, level, zoneKey
			elseif rankIndex <= officerRank then
				r.officers[#r.officers + 1] = { name = short, online = isOnline and true or false, days = days, class = code, level = level, zone = zoneKey }
			end
			if days >= 30 then r.inactive30 = r.inactive30 + 1 end
			if days >= 7 then r.inactive7 = r.inactive7 + 1 end
			-- Every member, online or not, for our guild's members page (1.1, Members.lua): the
			-- name as the server gave it (raw: what a removal takes), rank, days offline. Kept in
			-- memory only, never in the report.
			local rankText, on = rankName or rank.name, isOnline and true or false
			local row = prev
			if again or not (row and SameRow(row, level, code, race, raceName, rankIndex, rankText, days, on)) then
				row = { name = short, level = level, class = code, race = race, raceName = raceName,
					raw = name, full = full, rankIndex = rankIndex, rank = rankText, days = days, online = on }
				made = made + 1
			end
			if again then
				dup = true
			else
				distinct = distinct + 1
				-- New to the order, or moved in it (his level changed): put in where he goes.
				if not (wasHere and prev.level == level and prev.name == short) then
					m = m + 1
					if m <= INSERT_MAX then moved[m] = row end
				end
				if not prev then rowCount = rowCount + 1 end
				rowOf[name], seenAt[name] = row, scan
			end
			byIndex[seen] = row
			if isOnline then
				local o = onlineOf[name]
				if again or not (o and SameOnline(o, short, level, code, zoneKey, rankName, rankIndex)) then
					o = { name = short, level = level, class = code, zone = zoneKey, rank = rankName, rankIndex = rankIndex }
					if not again then onlineOf[name] = o end
				end
				online[#online + 1] = o
				r.online = r.online + 1
				if zoneKey then
					if not r.zones[zoneKey] then zoneCount = zoneCount + 1 end
					r.zones[zoneKey] = (r.zones[zoneKey] or 0) + 1
				end
				if code then r.classes[code] = (r.classes[code] or 0) + 1 end
				local band = math.min(7, math.floor(level / 10) + 1)
				r.levels[band] = r.levels[band] + 1
			else
				if not again then onlineOf[name] = nil end
				seenOffline = seenOffline + 1
			end
		end
	end
	for k = seen + 1, indexed do byIndex[k] = nil end
	indexed = seen
	-- Fill gaps so rank order is kept even if a rank has nobody in it.
	for i = 1, #r.ranks do r.ranks[i] = r.ranks[i] or { name = "Rank " .. i, count = 0 } end
	table.sort(r.officers, OfficerBefore)
	-- (1.2.3) The members' order: the last one itself when no row changed, kept with the new or
	-- moved rows put in, or one sort of every row (KeptOrder).
	local everyone, strict
	if not dup and made == 0 and m == 0 and order and orderStrict and orderScan == scan - 1 and #order == seen then
		everyone, strict = order, true
	else
		everyone = not dup and KeptOrder(seen, m, scan)
		if everyone then strict = true else everyone, strict = SortedOrder(seen, dup) end
	end
	for j = 1, math.min(m, INSERT_MAX) do moved[j], movedAt[j] = nil, nil end
	order, orderScan, orderStrict = everyone, scan, strict
	-- The report is persisted locally before it is encoded.  Keep its public top-five rows to the
	-- three fields the wire actually carries; GUID-derived race and the richer roster-only identity
	-- fields must remain on Roster.members rather than leaking into OlympusDB through r.top.
	for i = 1, math.min(5, #everyone) do
		local member = everyone[i]
		r.top[i] = { name = member.name, level = member.level, class = member.class }
	end
	r.avgLevel = seen > 0 and levelSum / seen or 0
	-- (1.2.3) byName: the last one while it holds every row's name and rank and nothing more (two
	-- rows of one name, or names with and without their realm side by side: made anew, as before),
	-- else a new one, filled in the server's order as before.
	local byName = keep
	if not (sameNames and not dup and not (bare > 0 and bare < seen) and seen == pubCount and CountKeys(keep) == pubCount) then
		byName, pubCount = {}, 0
		for k = 1, seen do
			local row = byIndex[k]
			if byName[row.full] == nil then pubCount = pubCount + 1 end
			byName[row.full] = row.rankIndex
		end
		pubByName = byName
	end
	Roster.byName, Roster.guild = byName, guild -- (whose roster it is: Olympus Link's "r", the Olympus_Link module)
	-- Consumers which use the roster as an authority boundary need to distinguish a current
	-- server snapshot from rows left in memory after a guild/faction/realm-group change.  The
	-- generation is process-local; together with the identity and timestamp it is only a freshness
	-- capability, never a value sent over the wire.
	Roster.group, Roster.faction = ns.group, ns.faction or ns.Faction()
	Roster.snapshotAt = ns.Now()
	-- The Church reuses this native scan: a pre-midnight cache must not prove the next UTC day.
	Roster.serverAt = type(GetServerTime) == "function" and GetServerTime() or nil
	Roster.generation = math.max(0, math.floor(tonumber(Roster.generation) or 0)) + 1
	-- A GUILD_ROSTER_UPDATE can be observed while Blizzard is still filling the rows.  Such a
	-- partial scan remains useful to the census, but it must never authorize a third party or make
	-- an absent protected target look like a non-member to The Watch.
	Roster.complete = seen == numTotal and ns.me ~= nil and byName[ns.FullName(ns.me)] ~= nil
	Roster.members = everyone -- (1.1: every member's row, Members.lua)
	table.sort(online, OnlineBefore)
	Roster.online = online
	Roster.rawRealms, Roster.servers, Roster.rawSample = rawRealms, servers, sample
	-- (1.2.3) Who left is forgotten, his GUID's race with him: at a complete scan (a partial one may
	-- only not have his row yet), or when far more are kept than the roster has.
	if rowCount > distinct and (Roster.complete or rowCount > 2 * distinct + 50) then
		for raw, at in pairs(seenAt) do
			if at ~= scan then Forget(raw) end
		end
	end
	r.home = home ~= "" and home or ns.realm
	r.faction = ns.faction or ns.Faction()
	if numOnline and numOnline - covered > r.online then r.online = numOnline - covered end
	local ms = debugprofilestop and (debugprofilestop() - started) or 0
	Roster.lastStats = {
		numTotal = numTotal, numOnline = numOnline, seen = seen, seenOffline = seenOffline,
		leader = r.leader, leaderOnline = r.leaderOnline, zones = zoneCount, ms = ms, t = ns.Now(),
		ranks = #r.ranks, officers = #r.officers,
	}
	ns.Log("scan %s: total=%d online=%d rows=%d offlineRows=%d leader=%s ranks=%d officers=%d zones=%d newRows=%d %.1fms",
		guild, numTotal, r.online, seen, seenOffline, tostring(r.leader), #r.ranks, #r.officers, zoneCount, made, ms)
	return r
end

-- Rank of a member of OUR guild, from the roster the server gave us (nil if not a member).
--
-- (Forever) The roster lists every member by his bare name, even one who plays on another
-- sub-realm of our realm family, so his row is filed as "Name-<our sub-realm>". His whispers and
-- relayed words arrive stamped with his own sub-realm ("Name-CAMWOWUS2Realm7PvE"), which missed
-- that row: a guildmate was a stranger to his own guild (no layer hop, his guild chat "forged").
-- Forever's names are unique across the region, so the same name on a sub-realm of our own
-- family is the same character: looked up as the roster filed him. Another family (PvE / PvP)
-- or any realm outside Forever is never matched this way.
function Roster.RankOf(name)
	local byName = Roster.byName
	if not byName or not name then return nil end
	local full = ns.FullName(name)
	local rank = byName[full]
	if rank ~= nil or not ns.splitNames then return rank end
	local base, realm = full:match("^(.+)%-([^%-]+)$")
	if not realm or realm == ns.realm then return nil end
	local family = ns.ForeverFamily(realm)
	if not family or family ~= ns.ForeverFamily(ns.realm) then return nil end
	return byName[ns.FullName(base)]
end

-- (Olympus Link) The GUID the last scan gave for a member of OUR guild, found by name as RankOf
-- finds his rank (the same sub-realm family rule). nil when he is not a member, the scan gave no
-- GUID, or the value is secret. Read-only: nothing is sent and nothing is scanned here.
-- guidOf is filed by the raw name the roster gave; this index goes from the full name to it and is
-- made again when a scan has run since (Roster.generation), so it never outlives a guild change.
local rawOfFull, rawOfFullAt = {}, nil
function Roster.GuidOf(name)
	if not name or not Roster.byName then return nil end
	if rawOfFullAt ~= Roster.generation then
		rawOfFull = {}
		for raw, row in pairs(rowOf) do
			if type(row) == "table" and row.full then rawOfFull[row.full] = raw end
		end
		rawOfFullAt = Roster.generation
	end
	local full = ns.FullName(name)
	local raw = rawOfFull[full]
	if raw == nil and ns.splitNames then
		local base, realm = full:match("^(.+)%-([^%-]+)$")
		if realm and realm ~= ns.realm then
			local family = ns.ForeverFamily(realm)
			if family and family == ns.ForeverFamily(ns.realm) then raw = rawOfFull[ns.FullName(base)] end
		end
	end
	return raw and PublicString(guidOf[raw]) or nil
end

-- Our own rank index (0 = guild master), used for layer names and decree permission.
function Roster.MyRank()
	local _, _, rankIndex = GetGuildInfo("player")
	return rankIndex or 9
end

function Roster.IsOfficer()
	return IsInGuild() and Roster.MyRank() <= ns.CAPTAIN_RANK
end

-- A roster row may authorize another character only while it is a complete, recent snapshot of
-- this character's current guild, realm group and faction.  Census/display callers may still use
-- the last scan while the server fills a new one; security-sensitive callers must use this gate
-- before RankOf so a guild transfer cannot lend the old roster to the new guild.
function Roster.Fresh(maxAge)
	local guild = type(GetGuildInfo) == "function" and GetGuildInfo("player") or nil
	maxAge = tonumber(maxAge) or Roster.AUTHORITY_FRESH
	if type(guild) ~= "string" or guild == "" or maxAge < 0 or Roster.complete ~= true
		or type(Roster.byName) ~= "table" or type(Roster.generation) ~= "number" or Roster.generation < 1
		or Roster.guild ~= guild or Roster.group ~= ns.group or Roster.faction ~= ns.faction
		or type(Roster.snapshotAt) ~= "number" then return nil end
	local age = ns.Now() - Roster.snapshotAt
	if age < 0 or age > maxAge then return nil end
	return Roster
end

function Roster.TryScan()
	if not pending or ns.Now() - lastScan < MIN_GAP then return end
	pending = false
	lastScan = ns.Now()
	local r = Roster.Scan()
	if not r or not ns.IsFederation(r.guild) then return end
	-- (1.1, Members.lua: who joined since login, for the Lord's recruits; our Lord away past
	-- warnDays, one line to our officers.)
	ns.SafeCall("members scan", ns.Members.OnScan, r)
	-- Our guild lives on another realm: that realm shares our guilds, so it shares our census
	-- (first, so our report lands in the shared store).
	if r.home ~= ns.realm then ns.LinkRealms(ns.realm, r.home) end
	r.users = ns.Comm.PeerCount() + 1
	r.versions = ns.Comm.PeerVersions and ns.Comm.PeerVersions() or nil
	-- 1.0.0: the realms our guild's addon users play on now, and what our client takes part in
	-- (fields 27 and 26 of the report).
	r.pres = ns.Comm.Presence and ns.Comm.Presence() or nil
	r.cap = ns.Comm.CAPABILITY
	ns.Data.SetLocal(r)
	-- (1.2.5.1) Only a client whose player accepted the Olympus Accord takes part in the election:
	-- another would elect itself, and its report, refused at the send, would hold its first real
	-- one back (Comm.Broadcast moves on its time and id). Its guild's census comes from the others.
	if ns.IsMember() then ns.Comm.MaybeBroadcast(r) end
end

function Roster.RequestScan(force)
	if not IsInGuild() then return end
	if force then lastScan = 0 end
	pending = true
	RequestServerRoster()
	-- GUILD_ROSTER_UPDATE usually triggers the scan; this is the fallback.
	ns.After(4, "roster fallback", Roster.TryScan)
end

ns.RegisterEvent("GUILD_ROSTER_UPDATE", function()
	if pending then ns.After(1, "roster update", Roster.TryScan) end
end)

-- (1.2.1) The game sends this for other units too (a nameplate's, a party member's guild reaching
-- the client): only ours is a guild change, and a burst of ours waits for one timer.
local guildChangeQueued = false
ns.RegisterEvent("PLAYER_GUILD_UPDATE", function(unit)
	if unit and unit ~= "player" then return end
	if guildChangeQueued then return end
	guildChangeQueued = true
	ns.After(2, "guild changed", function()
		guildChangeQueued = false
		Roster.RequestScan(true)
		-- Left an Olympus guild (or joined one): leave the channel, redraw the map and window.
		ns.Comm.CheckMembership()
		ns.Fire("DATA_CHANGED")
	end)
end)

ns.On("LOGIN", function()
	ns.After(8, "first scan", function() Roster.RequestScan(true) end)
	ns.Every(SCAN_EVERY, "scan ticker", function() Roster.RequestScan() end)
end)
