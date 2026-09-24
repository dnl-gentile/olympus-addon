local ADDON, ns = ...
local L = ns.L

-- Holds one report per Olympus guild (ours from the roster, others from the channel)
-- and aggregates them into the numbers the UI and the map show.

local Data = {}
ns.Data = Data

Data.FRESH = 15 * 60           -- older: shown grey, its online players and zones leave the totals
Data.KEEP = 7 * 24 * 60 * 60   -- older than this is forgotten (a guild's size is kept until then)

ns.On("INIT", function()
	local now = ns.Now()
	for name, g in pairs(ns.rdb.guilds) do
		if type(g) ~= "table" or now - (g.t or 0) > Data.KEEP then ns.rdb.guilds[name] = nil end
	end
	local seen = Data.Seen()
	for name, e in pairs(seen) do
		if type(e) ~= "table" or now - (e.t or 0) > Data.KEEP then seen[name] = nil end
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
	if next(count) then ns.Fire("DATA_CHANGED") end
end
ns.Who.Listen(Data.RecordSightings)

function Data.SetLocal(r)
	r.t = ns.Now()
	r.reporter = ns.DisplayName(ns.me)
	r.reporterFull = ns.me
	r.realm = ns.realm
	r.mine = true
	ns.rdb.guilds[r.guild] = r
	ns.Fire("DATA_CHANGED")
end

-- Sender names are set by the server and cannot be forged, so we tie every sender to the
-- one guild it reports. A (modified) client that reports several guilds is ignored, and a
-- guild whose reports disagree about its leader, its size or its officers is flagged as a
-- conflict.
local senderGuild = {}

-- One guild per sender, shared by reports and chat: a name that spoke for one guild can't speak for another.
function Data.ClaimGuild(sender, guild)
	local who = ns.FullName(sender)
	if senderGuild[who] and senderGuild[who] ~= guild then return false end
	senderGuild[who] = guild
	return true
end

-- Every rank a report names, as "Name-Realm" -> 0 (leader) or 1 (officer). Names without a
-- realm belong to the reporter's realm, so a same-named player from another realm never matches.
local function Ranks(g)
	local home, out = g.realm or ns.realm, {}
	for _, o in ipairs(g.officers or {}) do out[ns.FullName(o.name, home)] = 1 end
	if g.leader then out[ns.FullName(g.leader, home)] = 0 end
	return out
end

-- A leader or officer that the other sender's fresh report left out although its list had
-- room for them: someone added a name (a real promotion shows as a conflict once).
local function AddedName(previous, r)
	if ns.Now() - (previous.t or 0) > Data.FRESH or #(previous.officers or {}) >= ns.Codec.MAX_OFFICERS then return nil end
	local before = Ranks(previous)
	for name in pairs(Ranks(r)) do
		if before[name] == nil then return name end
	end
	return nil
end

function Data.Receive(r, sender)
	if not ns.IsFederation(r.guild) then return false end
	-- Our own guild comes straight from our roster, never from someone else's claim (in any spelling).
	local mine = GetGuildInfo("player")
	if mine and r.guild:lower() == mine:lower() then return false end
	local who = ns.FullName(sender)
	if not Data.ClaimGuild(who, r.guild) then
		ns.Log("ignored %s: already reported %s, now claims %s", who, senderGuild[who], r.guild)
		return false
	end
	local previous = ns.rdb.guilds[r.guild]
	local previousWho = previous and (previous.reporterFull or ns.FullName(previous.reporter))
	r.t = ns.Now()
	r.reporter = ns.DisplayName(who)
	r.reporterFull = who
	r.realm = ns.RealmOf(who) or ns.realm
	if previousWho and previousWho ~= who then
		local added = AddedName(previous, r)
		if (previous.leader or "") ~= (r.leader or "") or math.abs((previous.total or 0) - (r.total or 0)) > 25 or added then
			r.conflict = true
			ns.Log("conflict on %s: %s says %s/%d, %s says %s/%d%s", r.guild, previousWho, tostring(previous.leader),
				previous.total or 0, who, tostring(r.leader), r.total or 0, added and (", adds " .. added) or "")
		end
	end
	-- One realm can't hold two guilds whose names differ only by case: while another spelling
	-- is fresh, one of the two is forged.
	for name, g in pairs(ns.rdb.guilds) do
		if name ~= r.guild and name:lower() == r.guild:lower() and r.t - (g.t or 0) <= Data.FRESH then
			r.conflict = true
			ns.Log("conflict on %s: %s reports it as %s", name, who, r.guild)
		end
	end
	-- The last fresh report someone else sent about this guild: KnownRank needs it to prove
	-- this sender's own rank. The same sender keeps the one it had.
	if previousWho == who then
		r.witness = previous.witness
	elseif previousWho and not previous.conflict and not r.conflict and r.t - (previous.t or 0) <= Data.FRESH then
		r.witness = Ranks(previous)
	end
	ns.rdb.guilds[r.guild] = r
	ns.Fire("DATA_CHANGED")
	return true
end

-- What rank does this sender really have in that guild? Our own guild: from our roster.
-- Other guilds: from that guild's report (leader = 0, officers = 1). nil = unknown.
function Data.KnownRank(sender, guild)
	local who = ns.FullName(sender)
	if guild == GetGuildInfo("player") then return ns.Roster.RankOf(who) end
	local g = ns.rdb.guilds[guild]
	-- A report kept from an earlier session proves nothing about who leads the guild now.
	if not g or g.conflict or ns.Now() - (g.t or 0) > Data.FRESH then return nil end
	local rank = Ranks(g)[who]
	-- Anyone can send a report, so it never proves its own sender's rank: the last report
	-- someone else sent about that guild must name them too.
	if rank and (g.reporterFull or ns.FullName(g.reporter)) == who then
		local other = g.witness and g.witness[who]
		rank = other and math.max(rank, other) or nil
	end
	return rank
end

function Data.Summary()
	local now = ns.Now()
	local s = { total = 0, online = 0, fresh = 0, newest = 0, guilds = {}, zones = {}, zoneGuilds = {}, zoneList = {} }
	for name, g in pairs(ns.rdb.guilds) do
		if ns.IsFederation(name) then
			local age = now - (g.t or 0)
			local fresh = age <= Data.FRESH
			-- A guild keeps its size from its last report when its reporters log off (the army
			-- does not shrink every night); who is online and where only count while fresh.
			if age <= Data.KEEP then
				s.guilds[#s.guilds + 1] = { name = name, g = g, fresh = fresh }
				s.total = s.total + (g.total or 0)
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
	table.sort(s.guilds, function(a, b)
		if a.fresh ~= b.fresh then return a.fresh end
		if (a.g.total or 0) ~= (b.g.total or 0) then return (a.g.total or 0) > (b.g.total or 0) end
		return a.name < b.name
	end)
	-- Guilds only /who has seen, for the census list alone: in no total, tree or map.
	s.seen = {}
	for name, e in pairs(Data.Seen()) do
		if ns.IsFederation(name) and not ns.rdb.guilds[name] and type(e) == "table" and now - (e.t or 0) <= Data.KEEP then
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

function Data.DiscordText()
	local s = Data.Summary()
	local F = ns.FormatNumber
	local out = {}
	out[#out + 1] = L.DISCORD_HEADER:format(F(s.total), F(s.online), #s.guilds)
	local where = {}
	for i = 1, math.min(8, #s.zoneList) do
		local z = s.zoneList[i]
		where[#where + 1] = ns.Zones.NameForKey(z.key) .. " " .. F(z.count)
	end
	if #where > 0 then out[#out + 1] = L.DISCORD_WHERE .. table.concat(where, " · ") end
	out[#out + 1] = "```"
	out[#out + 1] = ("%-22s %7s %7s  %s"):format("Guild", "Members", "Online", "Leader")
	for _, e in ipairs(s.guilds) do
		local g = e.g
		local leader = g.leader and (g.leader .. (g.leaderOnline and " (on)" or "")) or "?"
		out[#out + 1] = ("%-22s %7s %7s  %s%s"):format(e.name, F(g.total), F(g.online), leader, e.fresh and "" or "  [stale]")
	end
	out[#out + 1] = "```"
	out[#out + 1] = ("_Olympus addon v%s_"):format(ns.VERSION)
	return table.concat(out, "\n")
end
