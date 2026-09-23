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

ns.On("LOGIN", function()
	if ns.db.demo then Data.BuildDemo() end
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
function Data.Receive(r, sender)
	if not ns.IsFederation(r.guild) then return false end
	-- Our own guild comes straight from our roster, never from someone else's claim.
	if r.guild == GetGuildInfo("player") then return false end
	local who = ns.FullName(sender)
	if senderGuild[who] and senderGuild[who] ~= r.guild then
		ns.Log("ignored %s: already reported %s, now claims %s", who, senderGuild[who], r.guild)
		return false
	end
	senderGuild[who] = r.guild
	local previous = ns.rdb.guilds[r.guild]
	local previousWho = previous and (previous.reporterFull or ns.FullName(previous.reporter))
	if previousWho and previousWho ~= who and not ns.db.demo then
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
	if not g or g.conflict then return nil end
	local home = g.realm or ns.realm
	if g.leader and ns.FullName(g.leader, home) == who then return 0 end
	for _, o in ipairs(g.officers or {}) do
		if ns.FullName(o.name, home) == who then return 1 end
	end
	return nil
end

local function Source()
	if ns.db.demo then return ns.demoGuilds or {} end
	return ns.rdb.guilds
end

function Data.Summary()
	local now = ns.Now()
	local s = { total = 0, online = 0, fresh = 0, newest = 0, guilds = {}, zones = {}, zoneGuilds = {}, zoneList = {} }
	for name, g in pairs(Source()) do
		if ns.db.demo or ns.IsFederation(name) then
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
	out[#out + 1] = ("_Olympus addon v%s%s_"):format(ns.VERSION, ns.db.demo and " - DEMO DATA" or "")
	return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- Demo data: lets anyone see the full UI and map without a guild.
---------------------------------------------------------------------------

local DEMO_GUILDS = {
	"Olympus", "Olympus II", "Olympus III", "Olympus IV", "Olympus V",
	"Olympus Ares", "Olympus Athena", "Olympus Zeus", "Olympus Hermes", "Olympus Apollo",
	"Olympus Hades", "Olympus Poseidon", "Olympus Artemis", "Olympus Nike",
}
local DEMO_LEADERS = {
	"Asmongold", "Zeuslord", "Tankmoose", "Holyrina", "Bladeon", "Aresbro", "Owlwise",
	"Thunderpaw", "Swiftfeet", "Sunbow", "Gravemist", "Tidecall", "Moonarrow", "Victora",
}
local DEMO_OFFICERS = { "Brava", "Kellan", "Mirra", "Torvald", "Isolde", "Garrick", "Seraphine", "Doran", "Lyra", "Bram" }
-- Weighted: cities and early zones get the crowds, like a fresh launch.
local DEMO_ZONES = {
	{ "Stormwind City", 30 }, { "Elwynn Forest", 14 }, { "Westfall", 10 }, { "Ironforge", 9 },
	{ "Dun Morogh", 8 }, { "Loch Modan", 6 }, { "Redridge Mountains", 6 }, { "Darkshore", 4 },
	{ "Teldrassil", 4 }, { "Darnassus", 3 }, { "Wetlands", 3 }, { "Duskwood", 3 },
}
local DEMO_CLASSES = { "WA", "PA", "HU", "RO", "PR", "MA", "WL", "DR" }

local function WeightedZone()
	local total = 0
	for _, z in ipairs(DEMO_ZONES) do total = total + z[2] end
	local r = math.random() * total
	for _, z in ipairs(DEMO_ZONES) do
		r = r - z[2]
		if r <= 0 then return z[1] end
	end
	return DEMO_ZONES[1][1]
end

function Data.BuildDemo()
	local now = ns.Now()
	local t = {}
	for i, name in ipairs(DEMO_GUILDS) do
		local total = i <= 5 and 1000 or math.random(180, 980)
		local online = math.floor(total * (0.12 + math.random() * 0.22))
		local zones, classes, levels = {}, {}, { 0, 0, 0, 0, 0, 0, 0 }
		for _ = 1, online do
			local key = ns.Zones.KeyForName(WeightedZone())
			zones[key] = (zones[key] or 0) + 1
			local c = DEMO_CLASSES[math.random(#DEMO_CLASSES)]
			classes[c] = (classes[c] or 0) + 1
			local band = math.random(1, 3) -- beta cap is 20-30
			levels[band] = levels[band] + 1
		end
		local officers = {}
		for o = 1, math.random(3, 7) do
			local on = math.random() > 0.4
			officers[o] = {
				name = DEMO_OFFICERS[math.random(#DEMO_OFFICERS)] .. o, online = on, days = on and 0 or math.random(0, 9),
				class = DEMO_CLASSES[math.random(#DEMO_CLASSES)], level = math.random(12, 22),
				zone = on and ns.Zones.KeyForName(WeightedZone()) or nil,
			}
		end
		table.sort(officers, function(a, b)
			if a.online ~= b.online then return a.online end
			return a.days < b.days
		end)
		local ranks, left = {}, total - 1 - #officers
		ranks[1] = { name = "Zeus", count = 1 }
		ranks[2] = { name = "Titan", count = #officers }
		ranks[3] = { name = "Hero", count = math.floor(left * 0.15) }
		ranks[4] = { name = "Hoplite", count = math.floor(left * 0.35) }
		ranks[5] = { name = "Recruit", count = left - math.floor(left * 0.15) - math.floor(left * 0.35) }
		local top = {}
		for k = 1, 5 do top[k] = { name = DEMO_OFFICERS[math.random(#DEMO_OFFICERS)] .. "x" .. k, level = math.random(17, 22) - k + 1, class = DEMO_CLASSES[math.random(#DEMO_CLASSES)] } end
		local leaderOnline = math.random() > 0.3
		t[name] = {
			guild = name, total = total, online = online,
			leader = DEMO_LEADERS[i], leaderOnline = leaderOnline, leaderDays = leaderOnline and 0 or math.random(0, 6),
			leaderClass = DEMO_CLASSES[math.random(#DEMO_CLASSES)], leaderLevel = math.random(16, 24),
			leaderZone = leaderOnline and ns.Zones.KeyForName(WeightedZone()) or nil,
			users = math.random(1, 60), zones = zones, classes = classes, levels = levels,
			ranks = ranks, officers = officers, top = top, avgLevel = 8 + math.random() * 6,
			inactive7 = math.floor(total * 0.1 * math.random()), inactive30 = math.floor(total * 0.04 * math.random()),
			reporter = "Demo", t = now - math.random(5, 300) - (i == 13 and 3600 or 0),
		}
	end
	ns.demoGuilds = t
end

function Data.SetDemo(on)
	ns.db.demo = on and true or false
	if on then Data.BuildDemo() end
	ns.Print(on and L.DEMO_ON or L.DEMO_OFF)
	ns.Log("demo = %s", tostring(on))
	ns.Fire("DEMO_CHANGED", ns.db.demo)
	ns.Fire("DATA_CHANGED")
end
