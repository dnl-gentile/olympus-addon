local ADDON, ns = ...
local L = ns.L

-- Holds one report per Olympus guild (ours from the roster, others from the channel)
-- and aggregates them into the numbers the UI and the map show.

local Data = {}
ns.Data = Data

Data.FRESH = 15 * 60       -- a report older than this is shown grey and left out of totals
Data.KEEP = 24 * 60 * 60   -- older than this is forgotten at login

ns.On("INIT", function()
	local now = ns.Now()
	for name, g in pairs(ns.rdb.guilds) do
		if type(g) ~= "table" or now - (g.t or 0) > Data.KEEP then ns.rdb.guilds[name] = nil end
	end
end)

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
-- guild whose reports disagree about its leader is flagged as a conflict.
local senderGuild = {}

-- One guild per sender, shared by reports and chat: a name that spoke for one guild can't speak for another.
function Data.ClaimGuild(sender, guild)
	local who = ns.FullName(sender)
	if senderGuild[who] and senderGuild[who] ~= guild then return false end
	senderGuild[who] = guild
	return true
end

function Data.Receive(r, sender)
	if not ns.IsFederation(r.guild) then return false end
	-- Our own guild comes straight from our roster, never from someone else's claim.
	if r.guild == GetGuildInfo("player") then return false end
	local who = ns.FullName(sender)
	if not Data.ClaimGuild(who, r.guild) then
		ns.Log("ignored %s: already reported %s, now claims %s", who, senderGuild[who], r.guild)
		return false
	end
	local previous = ns.rdb.guilds[r.guild]
	local previousWho = previous and (previous.reporterFull or ns.FullName(previous.reporter))
	if previousWho and previousWho ~= who then
		if (previous.leader or "") ~= (r.leader or "") or math.abs((previous.total or 0) - (r.total or 0)) > 25 then
			r.conflict = true
			ns.Log("conflict on %s: %s says %s/%d, %s says %s/%d", r.guild, previousWho, tostring(previous.leader),
				previous.total or 0, who, tostring(r.leader), r.total or 0)
		end
	end
	r.t = ns.Now()
	r.reporter = ns.DisplayName(who)
	r.reporterFull = who
	r.realm = ns.RealmOf(who) or ns.realm
	ns.rdb.guilds[r.guild] = r
	ns.Fire("DATA_CHANGED")
	return true
end

-- What rank does this sender really have in that guild? Our own guild: from our roster.
-- Other guilds: from that guild's report (leader = 0, officers = 1). nil = unknown.
-- Names in a report without a realm belong to the reporter's realm, so a same-named
-- player from another realm never matches.
function Data.KnownRank(sender, guild)
	local who = ns.FullName(sender)
	if guild == GetGuildInfo("player") then return ns.Roster.RankOf(who) end
	local g = ns.rdb.guilds[guild]
	-- A report kept from an earlier session proves nothing about who leads the guild now.
	if not g or g.conflict or ns.Now() - (g.t or 0) > Data.FRESH then return nil end
	local home = g.realm or ns.realm
	if g.leader and ns.FullName(g.leader, home) == who then return 0 end
	for _, o in ipairs(g.officers or {}) do
		if ns.FullName(o.name, home) == who then return 1 end
	end
	return nil
end

function Data.Summary()
	local now = ns.Now()
	local s = { total = 0, online = 0, fresh = 0, newest = 0, guilds = {}, zones = {}, zoneGuilds = {}, zoneList = {} }
	for name, g in pairs(ns.rdb.guilds) do
		if ns.IsFederation(name) then
			local fresh = now - (g.t or 0) <= Data.FRESH
			s.guilds[#s.guilds + 1] = { name = name, g = g, fresh = fresh }
			if fresh then
				s.fresh = s.fresh + 1
				s.total = s.total + (g.total or 0)
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
	out[#out + 1] = L.DISCORD_HEADER:format(F(s.total), F(s.online), s.fresh)
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
