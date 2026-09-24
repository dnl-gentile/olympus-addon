local ADDON, ns = ...
local L = ns.L

-- Holds one report per Olympus guild (ours from the roster, others from the channel)
-- and aggregates them into the numbers the UI and the map show.

local Data = {}
ns.Data = Data

Data.FRESH = 15 * 60           -- older: shown grey, its online players and zones leave the totals
Data.KEEP = 7 * 24 * 60 * 60   -- older than this is forgotten (a guild's size is kept until then)
Data.VOUCH_TTL = 30 * 60       -- a report vouches for the ranks it names this long
Data.BASE_TTL = 24 * 60 * 60   -- an agreed picture older than this no longer contests a new report
Data.CLAIM_TTL = 15 * 60       -- a sender quiet this long for its guild may speak for another one
local MAX_VOUCH, MAX_KNOWN = 8, 16

ns.On("INIT", function()
	local now = ns.Now()
	for name, g in pairs(ns.rdb.guilds) do
		if type(g) ~= "table" or now - (g.t or 0) > Data.KEEP then ns.rdb.guilds[name] = nil end
	end
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
	if next(count) then ns.Fire("DATA_CHANGED") end
end
ns.Who.Listen(Data.RecordSightings)

function Data.SetLocal(r)
	r.t = ns.Now()
	r.reporter = ns.DisplayName(ns.me)
	r.reporterFull = ns.me
	r.realm = ns.realm
	r.from = ns.realm -- travels in the report: whoever hears it on another realm knows the channel is shared
	r.heardOn = ns.realm -- see Data.Receive
	r.mine = true
	ns.rdb.guilds[r.guild] = r
	ns.Fire("DATA_CHANGED")
end

-- Sender names are set by the server and cannot be forged, so we tie every sender to the
-- one guild it reports. A (modified) client that reports several guilds is ignored, and a
-- guild whose reports disagree about its leader, its size or its officers is flagged as a
-- conflict.
local senderGuild = {} -- "Name-Realm" -> { guild, t }

-- One guild per sender, shared by reports and chat: a name that speaks for one guild can't
-- speak for another. A player who really moved guilds speaks again after CLAIM_TTL quiet.
function Data.ClaimGuild(sender, guild)
	local who, now = ns.FullName(sender), ns.Now()
	local c = senderGuild[who]
	if c and c.guild ~= guild and now - c.t < Data.CLAIM_TTL then return false end
	senderGuild[who] = { guild = guild, t = now }
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

-- A leader or officer that the other sender's report left out although its list had room for
-- them: someone added a name (a real promotion shows as a conflict once). However old that
-- report is: a stale report is exactly when a forger would try.
local function AddedName(previous, r)
	if #(previous.officers or {}) >= ns.Codec.MAX_OFFICERS then return nil end
	local before = Ranks(previous)
	for name in pairs(Ranks(r)) do
		if before[name] == nil then return name end
	end
	return nil
end

-- Why `new` disagrees with `old` (nil: it doesn't): another leader, a size more than 25 apart,
-- or an added leader or officer.
local function Differs(old, new)
	if (old.leader or "") ~= (new.leader or "") then return "leader " .. tostring(new.leader) end
	if math.abs((old.total or 0) - (new.total or 0)) > 25 then return "size " .. tostring(new.total) end
	local added = AddedName(old, new)
	return added and ("adds " .. added) or nil
end

-- What a contested report keeps of the picture it contests (the SavedVariables stay small).
local function Slim(g)
	return { leader = g.leader, total = g.total, officers = g.officers, realm = g.realm,
		reporter = g.reporter, reporterFull = g.reporterFull, t = g.t }
end

-- The senders who reported this guild before and were not contesting anyone (who they are,
-- when) and what each one named: copied from the previous report, the oldest dropped.
local function Carry(map, ttl, cap, now)
	local out, list = {}, {}
	for k, v in pairs(map or {}) do
		local t = type(v) == "table" and v.t or v
		if type(t) == "number" and now - t <= ttl then list[#list + 1] = { k = k, v = v, t = t } end
	end
	table.sort(list, function(a, b) return a.t > b.t end)
	for i = 1, math.min(cap, #list) do out[list[i].k] = list[i].v end
	return out
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
	-- Realms of one census group share this store, but a name without a realm takes the realm
	-- of the character that heard it. A report heard on another realm of the group names people
	-- in that realm's form: compared with ours, the same reporter and officers would look new
	-- (a false conflict), so here it counts as no report at all.
	if previous and previous.heardOn and previous.heardOn ~= ns.realm then previous = nil end
	local previousWho = previous and (previous.reporterFull or ns.FullName(previous.reporter))
	r.t = ns.Now()
	r.reporter = ns.DisplayName(who)
	r.reporterFull = who
	r.heardOn = ns.realm
	-- The realm of the sender's name as we got it, not the report's `from`: a report's short
	-- names are compared with senders in that same form (a sender that reaches us without a
	-- realm carries ours, whatever realm it plays on).
	r.realm = ns.RealmOf(who) or ns.realm
	local now = r.t
	-- The picture of the guild its reporters agreed on: the report before a contest began.
	local base = previous and (previous.conflict and previous.base or previous) or nil
	if base and now - (base.t or 0) > Data.BASE_TTL then base = nil end
	local baseWho = base and (base.reporterFull or ns.FullName(base.reporter))
	local known = Carry(previous and previous.known, Data.KEEP, MAX_KNOWN, now)
	local vouch = Carry(previous and previous.vouch, Data.VOUCH_TTL, MAX_VOUCH, now)
	local why, confirmed
	if previous and previous.conflict and previous.challenger == who then
		-- Saying it again settles nothing: the contest stays until someone else reports.
		why = "still contested"
	elseif previous and previous.conflict then
		if base and not Differs(base, r) then
			why = nil -- matches the agreed picture: the challenger was wrong
		elseif not Differs(previous, r) and (not base or known[who] or known[previous.challenger]) then
			-- A second sender says what the challenger said, and one of them reported this guild
			-- before: a real change (two new names can't confirm each other).
			why, confirmed = nil, previous
		else
			why = base and Differs(base, r) or "contested"
		end
	elseif base and baseWho ~= who then
		why = Differs(base, r)
	end
	-- One realm can't hold two guilds whose names differ only by case: while another spelling
	-- is fresh, one of the two is forged.
	for name, g in pairs(ns.rdb.guilds) do
		if name ~= r.guild and name:lower() == r.guild:lower() and r.t - (g.t or 0) <= Data.FRESH then
			why = "spelled " .. name
		end
	end
	if why then
		r.conflict, r.challenger, r.base = true, who, base and Slim(base) or nil
		ns.Log("conflict on %s: %s says %s (agreed: %s/%d by %s)", r.guild, who, why, tostring(base and base.leader),
			base and base.total or 0, tostring(baseWho))
	else
		known[who], vouch[who] = now, { t = now, ranks = Ranks(r) }
		if confirmed and confirmed.challenger then
			known[confirmed.challenger] = confirmed.t
			vouch[confirmed.challenger] = { t = confirmed.t, ranks = Ranks(confirmed) }
		end
	end
	r.known, r.vouch = known, vouch
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
	local now = ns.Now()
	-- A report kept from an earlier session proves nothing about who leads the guild now.
	if not g or g.conflict or now - (g.t or 0) > Data.FRESH then return nil end
	-- Anyone can send a report, so it never proves its own sender's rank: a recent report from
	-- someone else must name them. (Reports saved by older versions vouch as one sender.)
	local vouch = g.vouch or { [g.reporterFull or ns.FullName(g.reporter or "?")] = { t = g.t, ranks = Ranks(g) } }
	local rank, sources = nil, 0
	for src, v in pairs(vouch) do
		if type(v) == "table" and now - (v.t or 0) <= Data.VOUCH_TTL then
			sources = sources + 1
			local k = src ~= who and v.ranks and v.ranks[who]
			if k and (not rank or k < rank) then rank = k end
		end
	end
	-- The Crown (every guild master, the officers of <Olympus>) is taken on two senders' word only.
	if rank and ns.IsCrownRank(guild, rank) and sources < 2 then return nil end
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
