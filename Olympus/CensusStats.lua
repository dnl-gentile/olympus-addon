local ADDON, ns = ...
local L = ns.L

-- CR-02 / KH-08 (the author's ask, 2026-10-19: "um número do lado, menorzinho, mais escuro: número
-- de pessoas ... quando você clicar no número ... uma página dentro do Census"): the window's header
-- shows the people (each player once) next to the characters, and a click on that count opens this
-- page in place of the Census's list: characters, people, linked alts, online, the guilds counted,
-- the army's average level, the largest guilds and the levels online, all from the census this
-- client already holds (Data.Summary), and how its totals moved.
--
-- The history is this client's own: every EVERY seconds while the player is on (after the census is
-- rebuilt at login, Data.CROWN_AFTER, as Tonight's count waits) it writes down the characters, the
-- people and who is online, in the realm group's store (ns.rdb.censusHistory): each sample of the
-- last RECENT_KEEP, and one line a day (its highest counts) for DAYS days. Both are bounded and
-- pruned at each sample and at login. Nothing is sent: another client keeps its own history, and
-- the page says so.

local CS = {}
ns.CensusStats = CS

CS.EVERY = 15 * 60         -- a sample every quarter-hour
CS.RECENT_KEEP = 48 * 3600 -- each sample of the last two days
CS.RECENT_MAX = 200        -- at most (two days of quarter-hours: 192)
CS.DAYS = 30               -- days, today among them
CS.HOURS = 24              -- the online graph's hours
CS.FUTURE = 5 * 60         -- a sample later than now by more than this (the clock went back) is dropped
CS.TICK = 60               -- how often the sampler looks whether a sample is due
CS.ARMY_COLOR = { 1, 0.82, 0 }
CS.ONLINE_COLOR = { 0.25, 1, 0.25 }

local MAX_COUNT = 10000000 -- far above any census (Data.MAX_GUILDS guilds of Codec.GUILD_CAP)
local DAY_KEY = "^(%d%d%d%d)%-(%d%d)%-(%d%d)$"

local shown = false

---------------------------------------------------------------------------
-- The page's state: shown from the header (UI.OpenCensusStats), closed by its Back line or any tab
-- opened (UI.lua's ShowTab).
---------------------------------------------------------------------------

function CS.Shown() return shown end
function CS.Open() shown = true end
function CS.Close() shown = false end

---------------------------------------------------------------------------
-- The history kept
---------------------------------------------------------------------------

local function Count(v)
	v = tonumber(v)
	if not v or v ~= v or v < 0 or v > MAX_COUNT then return nil end
	return math.floor(v)
end

-- The store, made or mended (a saved table of another shape starts again).
local function Store()
	local rdb = ns.rdb
	if type(rdb) ~= "table" then return nil end
	local h = rdb.censusHistory
	if type(h) ~= "table" or h.v ~= 1 then
		h = { v = 1, t = 0, recent = {}, days = {} }
		rdb.censusHistory = h
	end
	if type(h.recent) ~= "table" then h.recent = {} end
	if type(h.days) ~= "table" then h.days = {} end
	return h
end

-- "t,characters,people,online" and "characters,people,online,samples": numbers alone, so the saved
-- variables stay small and nothing else can ride in them.
local function ParseSample(s)
	if type(s) ~= "string" then return nil end
	local t, c, p, o = s:match("^(%d+),(%d+),(%d+),(%d+)$")
	t, c, p, o = tonumber(t), Count(c), Count(p), Count(o)
	if not (t and c and p and o) then return nil end
	return { t = t, c = c, p = p, o = o }
end
local function ParseDay(s)
	if type(s) ~= "string" then return nil end
	local c, p, o, n = s:match("^(%d+),(%d+),(%d+),(%d+)$")
	c, p, o, n = Count(c), Count(p), Count(o), Count(n)
	if not (c and p and o and n) then return nil end
	return { c = c, p = p, o = o, n = n }
end

-- A day's key, in the player's own calendar ("2026-10-19"), and noon of the day `t` falls in: a
-- step of a whole day back from noon stays in the day before, whatever the clocks did that night.
local function DayKey(t) return date("%Y-%m-%d", t) end
local function Noon(t)
	local d = date("*t", t)
	return time({ year = d.year, month = d.month, day = d.day, hour = 12, min = 0, sec = 0 })
end
-- The DAYS days' keys, the oldest first, today last.
local function DayKeys(now)
	local noon, keys = Noon(now), {}
	for k = CS.DAYS - 1, 0, -1 do keys[#keys + 1] = DayKey(noon - k * 86400) end
	return keys
end

-- Only what the bounds allow: the samples of the last RECENT_KEEP (none from the future), in time
-- order, RECENT_MAX at most; the days of the last DAYS (none after today), each well formed.
function CS.Prune(now)
	local h = Store()
	if not h then return end
	now = now or ns.Now()
	local kept = {}
	for _, s in ipairs(h.recent) do
		local e = ParseSample(s)
		if e and e.t <= now + CS.FUTURE and now - e.t <= CS.RECENT_KEEP then kept[#kept + 1] = e end
	end
	table.sort(kept, function(a, b) return a.t < b.t end)
	local recent = {}
	for i = math.max(1, #kept - CS.RECENT_MAX + 1), #kept do
		local e = kept[i]
		recent[#recent + 1] = ("%d,%d,%d,%d"):format(e.t, e.c, e.p, e.o)
	end
	h.recent = recent
	local keys = DayKeys(now)
	local first, last = keys[1], keys[#keys]
	local days = {}
	for key, s in pairs(h.days) do
		if type(key) == "string" and key:match(DAY_KEY) and key >= first and key <= last and ParseDay(s) then days[key] = s end
	end
	h.days = days
	if (tonumber(h.t) or 0) > now + CS.FUTURE then h.t = 0 end
end

-- One sample, at `now`, when one is due: EVERY after the last, the census rebuilt after login and
-- holding a count. True when it was taken.
function CS.Sample(now)
	now = now or ns.Now()
	local h = Store()
	if not h then return false end
	local last = tonumber(h.t) or 0
	if last > now + CS.FUTURE then last = 0 end
	if now - last < CS.EVERY then return false end
	local D = ns.Data
	local loginAt = ns.Comm and ns.Comm.loginAt
	if loginAt and now - loginAt < (D.CROWN_AFTER or 0) then return false end
	if D.Rebuilding and D.Rebuilding(now) then return false end
	local s = D.Summary()
	if s.snapshot then return false end -- retained evidence is not a newly observed history sample
	local c, p, o = Count(s.characters or s.total), Count(s.total), Count(s.online)
	if not (c and p and o) or c <= 0 then return false end
	h.t = now
	h.recent[#h.recent + 1] = ("%d,%d,%d,%d"):format(now, c, p, o)
	local key = DayKey(now)
	local day = ParseDay(h.days[key]) or { c = 0, p = 0, o = 0, n = 0 }
	h.days[key] = ("%d,%d,%d,%d"):format(math.max(day.c, c), math.max(day.p, p), math.max(day.o, o), day.n + 1)
	CS.Prune(now)
	-- (1.4.0) The same look kept as this realm group's, for the other groups this account plays
	-- (Data.RecordGroupCensus: every server's numbers on the page).
	if D.RecordGroupCensus then D.RecordGroupCensus(s, now) end
	return true
end

-- The DAYS days, the oldest first: { key, t (its noon), c, p, o, n } each, c nil for a day with no
-- sample.
function CS.DaySeries(now)
	now = now or ns.Now()
	local h = Store()
	local out, noon = {}, Noon(now)
	for k = CS.DAYS - 1, 0, -1 do
		local t = noon - k * 86400
		local key = DayKey(t)
		local d = h and ParseDay(h.days[key]) or nil
		out[#out + 1] = { key = key, t = t, ago = k, c = d and d.c, p = d and d.p, o = d and d.o, n = d and d.n or 0 }
	end
	return out
end

-- The HOURS hours up to now, the oldest first: each its own 60 minutes back from now (the last one
-- the hour just gone), with its sample of the most online ({ t, c, p, o }), nil where none.
function CS.HourSeries(now)
	now = now or ns.Now()
	local h = Store()
	local out = {}
	for k = CS.HOURS - 1, 0, -1 do out[#out + 1] = { ago = k } end
	for _, s in ipairs(h and h.recent or {}) do
		local e = ParseSample(s)
		local age = e and now - e.t
		if age and age >= -CS.FUTURE and age < CS.HOURS * 3600 then
			local slot = out[CS.HOURS - math.floor(math.max(0, age) / 3600)]
			if slot and (not slot.o or e.o > slot.o or e.o == slot.o and e.t > slot.t) then
				slot.t, slot.c, slot.p, slot.o = e.t, e.c, e.p, e.o
			end
		end
	end
	return out
end

-- When the history kept starts (its oldest sample or day), nil for none.
function CS.Since()
	local h = Store()
	if not h then return nil end
	local since
	for _, s in ipairs(h.recent) do
		local e = ParseSample(s)
		if e and (not since or e.t < since) then since = e.t end
	end
	for key in pairs(h.days) do
		local y, m, d = tostring(key):match(DAY_KEY)
		if y then
			local t = time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0, min = 0, sec = 0 })
			if t and (not since or t < since) then since = t end
		end
	end
	return since
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local function V() return ns.Views end
local function F(n) return ns.FormatNumber(n) end
local function White(s) return "|cffffffff" .. s .. "|r" end

-- A scale for `values` (nil entries skipped): from 0 (`fromZero`) or from a little under the
-- lowest, to a little over the highest, its ends round numbers. nil for no value.
function CS.Scale(values, n, fromZero)
	local lo, hi
	for i = 1, n do
		local v = values[i]
		if v then
			lo = (not lo or v < lo) and v or lo
			hi = (not hi or v > hi) and v or hi
		end
	end
	if not lo then return nil end
	if fromZero then
		local top = math.max(1, hi)
		local step = 10 ^ math.floor(math.log10(top))
		return 0, math.max(step, math.ceil(top / step) * step)
	end
	local pad = math.max((hi - lo) * 0.25, hi * 0.005, 1)
	lo, hi = math.max(0, lo - pad), hi + pad
	local step = 10 ^ math.floor(math.log10(math.max(1, hi - lo)))
	lo = math.max(0, math.floor(lo / step) * step)
	hi = math.ceil(hi / step) * step
	if hi <= lo then hi = lo + step end
	return lo, hi
end

-- The highest, the lowest and the latest of a series ({ v, label } each), for a graph's own tooltip.
local function SeriesTip(title, series, value, label, detail)
	return function(tt)
		tt:AddLine(title, 1, 0.82, 0)
		local hi, lo, latest
		for _, e in ipairs(series) do
			local v = value(e)
			if v then
				if not hi or v >= value(hi) then hi = e end
				if not lo or v < value(lo) then lo = e end
				latest = e
			end
		end
		if not latest then
			tt:AddLine(L.CENSUS_STATS_EMPTY_GRAPH, 1, 1, 1, true)
			return
		end
		tt:AddDoubleLine(L.CENSUS_STATS_HIGHEST, L.CENSUS_STATS_WHEN:format(F(value(hi)), label(hi)), 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L.CENSUS_STATS_LOWEST, L.CENSUS_STATS_WHEN:format(F(value(lo)), label(lo)), 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L.CENSUS_STATS_LATEST, L.CENSUS_STATS_WHEN:format(F(value(latest)), label(latest)), 1, 0.82, 0, 1, 1, 1)
		tt:AddLine(" ")
		tt:AddLine(detail or L.CENSUS_STATS_DETAIL, 0.75, 0.75, 0.75, true)
	end
end

local function DayLabel(e)
	if e.ago == 0 then return L.CENSUS_STATS_TODAY end
	return date(L.CENSUS_STATS_DAY_FORMAT, e.t)
end
local function HourLabel(e)
	return e.t and date(L.CENSUS_STATS_TIME_FORMAT, e.t) or L.CENSUS_STATS_HOURS_AGO:format(e.ago)
end

-- The army over the last DAYS days: each day's highest count of characters. (`est`: the people as
-- the page shows them, CS.PeopleEstimate: each day's people as an estimate too, CS.PeopleAt.)
local function ArmyGraph(now, est)
	local days = CS.DaySeries(now)
	local values, tips = {}, {}
	for i, e in ipairs(days) do
		values[i] = e.c
		tips[i] = function(tt)
			tt:AddLine(DayLabel(e), 1, 0.82, 0)
			if not e.c then tt:AddLine(L.CENSUS_STATS_NO_SAMPLE, 0.75, 0.75, 0.75, true) return end
			tt:AddDoubleLine(L.CENSUS_STATS_CHARACTERS, F(e.c), 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L.CENSUS_STATS_PEOPLE, CS.PeopleAt(e.p, e.c, est), 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L.CENSUS_STATS_PEAK_ONLINE, F(e.o), 1, 0.82, 0, 0.25, 1, 0.25)
			tt:AddDoubleLine(L.CENSUS_STATS_SAMPLES, tostring(e.n), 0.75, 0.75, 0.75, 0.75, 0.75, 0.75)
		end
	end
	local lo, hi = CS.Scale(values, #days, false)
	if not lo then return nil, days end
	return {
		n = #days, values = values, min = lo, max = hi, color = CS.ARMY_COLOR, tips = tips,
		top = F(hi), bottom = F(lo), left = L.CENSUS_STATS_DAYS_AGO:format(CS.DAYS - 1), right = L.CENSUS_STATS_TODAY,
	}, days
end

-- Who was online over the last HOURS hours: each hour's most online, from 0 (`est`: as ArmyGraph).
local function OnlineGraph(now, est)
	local hours = CS.HourSeries(now)
	local values, tips = {}, {}
	for i, e in ipairs(hours) do
		values[i] = e.o
		tips[i] = function(tt)
			if not e.o then
				tt:AddLine(L.CENSUS_STATS_HOURS_AGO:format(e.ago + 1), 1, 0.82, 0)
				tt:AddLine(L.CENSUS_STATS_NO_SAMPLE, 0.75, 0.75, 0.75, true)
				return
			end
			tt:AddLine(L.CENSUS_STATS_AROUND:format(HourLabel(e)), 1, 0.82, 0)
			tt:AddDoubleLine(L.CENSUS_STATS_ONLINE, F(e.o), 1, 0.82, 0, 0.25, 1, 0.25)
			tt:AddDoubleLine(L.CENSUS_STATS_CHARACTERS, F(e.c), 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L.CENSUS_STATS_PEOPLE, CS.PeopleAt(e.p, e.c, est), 1, 0.82, 0, 1, 1, 1)
		end
	end
	local lo, hi = CS.Scale(values, #hours, true)
	if not lo then return nil, hours end
	return {
		n = #hours, values = values, min = lo, max = hi, color = CS.ONLINE_COLOR, tips = tips,
		top = F(hi), bottom = F(lo), left = L.CENSUS_STATS_HOURS_AGO:format(CS.HOURS), right = L.CENSUS_STATS_NOW,
	}, hours
end

-- A graph's heading, the graph (or why there is none yet) and its summary on hover.
local function GraphLines(lines, title, graph, series, value, label, detail)
	local Vw = V()
	lines[#lines + 1] = { text = title, header = true }
	local tip = SeriesTip(title, series, value, label, detail)
	if graph then
		graph.tip = tip
		lines[#lines + 1] = { graph = graph, gapAfter = true }
	else
		lines[#lines + 1] = { text = Vw.Grey(L.CENSUS_STATS_EMPTY_GRAPH), tooltip = tip, gapAfter = true }
	end
end

local function Row(label, right, tip, indent)
	return { text = label, right = right, indent = indent, tooltip = tip and function(tt)
		tt:AddLine(label, 1, 0.82, 0)
		tt:AddLine(tip, 1, 1, 1, true)
	end or nil }
end

-- The army's average level: each guild's, weighted by its size, over those with one.
function CS.AverageLevel(s)
	local sum, weight = 0, 0
	for _, e in ipairs(s.guilds or {}) do
		local tenths = e.counted and ns.Data.AvgTenths(e.g)
		local size = tonumber(e.g and e.g.total) or 0
		if tenths and size > 0 then
			sum, weight = sum + tenths * size, weight + size
		end
	end
	if weight == 0 then return nil end
	return ns.Data.AvgLevelText({ avgLevel = sum / weight / 10 })
end

-- The levels of the soldiers online (seven bands: 1-9 ... 50-59, 60+), from the guilds reporting
-- now whose reports carry them; nil for none.
function CS.LevelBands(s)
	local bands, any = { 0, 0, 0, 0, 0, 0, 0 }, false
	for _, e in ipairs(s.guilds or {}) do
		local levels = e.fresh and type(e.g) == "table" and e.g.levels
		if type(levels) == "table" then
			for i = 1, 7 do
				local n = Count(levels[i])
				if n and n > 0 then bands[i], any = bands[i] + n, true end
			end
		end
	end
	return any and bands or nil
end

local function Percent(n, of)
	if not of or of <= 0 then return "0" end
	local p = n * 100 / of
	if p >= 10 or p == 0 then return tostring(math.floor(p + 0.5)) end
	return ("%d%s%d"):format(math.floor(p), L.DECIMAL_MARK or ".", math.floor(p * 10) % 10)
end

-- 1.4.0: every server this client knows of (Data.Groups): the characters and people of them all, by
-- ruleset (PvP, PvE...), by region (NA, EU) and by faction when both are known, then each server,
-- ours first. A server heard from one player alone is listed grey and left out of the totals.
CS.KIND_ORDER = { "pvp", "rppvp", "pve", "rp", "hardcore", "?" }
CS.REGION_ORDER = { "NA", "EU", "?" }
local function KindLabel(kind)
	local k = ({ pvp = "PVP", rppvp = "RPPVP", pve = "PVE", rp = "RP", hardcore = "HARDCORE" })[kind or "?"]
	return k and L["CENSUS_STATS_KIND_" .. k] or L.CENSUS_STATS_KIND_UNKNOWN
end
local function RegionLabel(region)
	return (region == "NA" or region == "EU") and L["CENSUS_STATS_REGION_" .. region] or L.CENSUS_STATS_REGION_UNKNOWN
end
local function ServerName(group) return (tostring(group):gsub("%+", " + ")) end
local function ObservationText(observed)
	local at = tonumber(observed)
	if not at or at <= 0 then return nil end
	return L.CENSUS_STATS_SEEN:format(date("%Y-%m-%d %H:%M", at))
end
local expandedGroup
function CS.ServerLines(lines, s, now)
	local D = ns.Data
	if not (D and D.Groups) then return end
	local g = D.Groups(s, now)
	if #g.rows == 0 then return end
	local Vw = V()
	local Grey = Vw.Grey
	lines[#lines + 1] = { text = L.CENSUS_STATS_SERVERS, header = true, tooltip = function(tt)
		tt:AddLine(L.CENSUS_STATS_SERVERS, 1, 0.82, 0)
		tt:AddLine(L.CENSUS_STATS_SERVERS_TIP, 1, 1, 1, true)
	end }
	lines[#lines + 1] = Row(L.CENSUS_STATS_ALL_CHARACTERS, White(F(g.characters)), L.CENSUS_STATS_SERVERS_TIP)
	-- (Each server's people as its reports give them, not this client's estimate: the servers' words,
	-- never the plain count's beside a team client's ~ estimate.)
	lines[#lines + 1] = Row(L.CENSUS_STATS_ALL_PEOPLE, White(L.CENSUS_STATS_APPROX:format(F(g.people))), L.CENSUS_STATS_SERVERS_TIP)
	-- (1.5.9) The date of the oldest other server's look these totals count: a server's last look counts
	-- until a newer one arrives (Data.lua's Lasting), so the totals can rest on an old one.
	if tonumber(g.oldestOther) then
		local text = L.CENSUS_STATS_SERVERS_AS_OF:format(date("%Y-%m-%d %H:%M", g.oldestOther))
		lines[#lines + 1] = { text = Grey(text), indent = 1, tooltip = function(tt)
			tt:AddLine(text, 1, 0.82, 0)
			tt:AddLine(L.CENSUS_STATS_SERVERS_AS_OF_TIP, 1, 1, 1, true)
		end }
	end
	local function Split(title, order, totals, label, field)
		local any = 0
		for _, key in ipairs(order) do if totals[key] then any = any + 1 end end
		if any == 0 or (any == 1 and totals["?"]) then return any == 1 end
		lines[#lines + 1] = { text = title, indent = 1 }
		for _, key in ipairs(order) do
			local t = totals[key]
			if t then
				lines[#lines + 1] = { text = label(key), indent = 2,
					right = White(F(t.characters)) .. " " .. Grey(Percent(t.characters, g.characters) .. "%"),
					meter = { value = t.characters, total = math.max(1, g.characters) },
					tooltip = function(tt)
						tt:AddLine(label(key), 1, 0.82, 0)
						tt:AddDoubleLine(L.CENSUS_STATS_CHARACTERS, F(t.characters), 1, 0.82, 0, 1, 1, 1)
						tt:AddDoubleLine(L.CENSUS_STATS_PEOPLE, L.CENSUS_STATS_APPROX:format(F(t.people)), 1, 0.82, 0, 1, 1, 1)
						for _, origin in ipairs(g.rows) do
							if origin.counted and (origin[field] or "?") == key then
								local observed = ObservationText(origin.observed)
								if observed then tt:AddLine(ServerName(origin.group) .. ": " .. observed, 0.75, 0.75, 0.75, true) end
							end
						end
					end }
			end
		end
		return false
	end
	local unknownKind = Split(L.CENSUS_STATS_BY_KIND, CS.KIND_ORDER, g.kinds, KindLabel, "kind")
	local unknownRegion = Split(L.CENSUS_STATS_BY_REGION, CS.REGION_ORDER, g.regions, RegionLabel, "region")
	if g.factions.Alliance and g.factions.Horde then
		Split(L.CENSUS_STATS_BY_FACTION, { "Alliance", "Horde" }, g.factions, function(f)
			return f == "Horde" and L.CENSUS_STATS_FACTION_HORDE or L.CENSUS_STATS_FACTION_ALLIANCE
		end, "faction")
	end
	if unknownKind then lines[#lines + 1] = { text = Grey(L.CENSUS_STATS_KIND_WAIT), indent = 1 } end
	if unknownRegion then lines[#lines + 1] = { text = Grey(L.CENSUS_STATS_REGION_UNAVAILABLE), indent = 1 } end
	lines[#lines + 1] = { text = L.CENSUS_STATS_EACH_SERVER, indent = 1 }
	for _, r in ipairs(g.rows) do
		local detailKey = r.faction .. "|" .. r.group
		local tags = {}
		if r.kind then tags[#tags + 1] = KindLabel(r.kind) end
		if r.region then tags[#tags + 1] = RegionLabel(r.region) end
		if r.faction == "Horde" then tags[#tags + 1] = L.CENSUS_STATS_FACTION_HORDE end
		local name = ServerName(r.group) .. (#tags > 0 and (" " .. Grey("(" .. table.concat(tags, ", ") .. ")")) or "")
		if r.ours then name = name .. " " .. Grey(L.CENSUS_STATS_HERE) end
		local right = r.counted and White(F(r.characters)) or Grey(F(r.characters))
		lines[#lines + 1] = { text = r.counted and name or Grey(ServerName(r.group)), indent = 2, right = right,
			onClick = function()
				expandedGroup = expandedGroup ~= detailKey and detailKey or nil
				if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
			end,
			tooltip = function(tt)
				tt:AddLine(ServerName(r.group), 1, 0.82, 0)
				tt:AddDoubleLine(L.CENSUS_STATS_CHARACTERS, F(r.characters), 1, 0.82, 0, 1, 1, 1)
				tt:AddDoubleLine(L.CENSUS_STATS_PEOPLE, L.CENSUS_STATS_APPROX:format(F(r.people)), 1, 0.82, 0, 1, 1, 1)
				tt:AddDoubleLine(L.CENSUS_STATS_GUILDS, F(r.guilds or 0), 1, 0.82, 0, 1, 1, 1)
				local observed = ObservationText(r.observed)
				if observed then tt:AddLine(observed, 0.75, 0.75, 0.75) end
				local src = r.src == "live" and L.CENSUS_STATS_SRC_LIVE or ({ own = L.CENSUS_STATS_SRC_OWN, relay = L.CENSUS_STATS_SRC_RELAY,
					author = L.CENSUS_STATS_SRC_AUTHOR, witnessed = L.CENSUS_STATS_SRC_WITNESSED, heard = L.CENSUS_STATS_SRC_HEARD })[r.src or ""] or ""
				if src ~= "" then tt:AddLine(src, 0.75, 0.75, 0.75, true) end
				if not r.counted and not r.ours then tt:AddLine(L.CENSUS_STATS_NOT_COUNTED, 1, 0.5, 0.5, true) end
			end }
		if expandedGroup == detailKey then
			local detail = {}
			if r.ours then
				for _, e in ipairs(s.guilds or {}) do
					detail[#detail + 1] = { name = e.name, characters = e.g.total, observed = e.g.st or e.g.t,
						counted = e.counted, source = e.g.relayed and "relay" or "own" }
				end
			elseif D.GroupGuilds then detail = D.GroupGuilds(r.group, r.faction) end
			lines[#lines + 1] = { text = Grey(#detail == 0 and L.CENSUS_STATS_DETAILS_PENDING or L.CENSUS_STATS_DETAILS_PARTIAL), indent = 3 }
			for _, guild in ipairs(detail) do
				lines[#lines + 1] = { text = guild.counted and guild.name or Grey(guild.name), indent = 3,
					right = guild.counted and White(F(guild.characters)) or Grey(F(guild.characters)),
					tooltip = function(tt)
						tt:AddLine(guild.name, 1, 0.82, 0)
						tt:AddDoubleLine(L.CENSUS_STATS_CHARACTERS, F(guild.characters), 1, 0.82, 0, 1, 1, 1)
						local observed = ObservationText(guild.observed)
						if observed then tt:AddLine(observed, 0.75, 0.75, 0.75) end
						local src = ({ own = L.CENSUS_STATS_SRC_OWN, relay = L.CENSUS_STATS_SRC_RELAY,
							author = L.CENSUS_STATS_SRC_AUTHOR, witnessed = L.CENSUS_STATS_SRC_WITNESSED, heard = L.CENSUS_STATS_SRC_HEARD })[guild.source]
						if src then tt:AddLine(src, 0.75, 0.75, 0.75, true) end
					end }
			end
		end
	end
	lines[#lines].gapAfter = true
end

---------------------------------------------------------------------------
-- The people, estimated
---------------------------------------------------------------------------
-- (The author, 2026-10-20: the people can't be told exactly until every player shared his account.)
-- A member's client shows the plain count (Data.Summary's people: the characters, confirmed linked
-- alts once) in the words the census page already uses for it ("about 80,500 people", "Estimated
-- people"): never divided by a rate. (The players who linked alts all have more than one
-- character, so an estimate from their rate came out about half the true number: the author's
-- "Membros: contagem atual".) A moderation team client (the King's is one) keeps the BattleTag
-- estimate, marked "~" (the game's fonts have no approximately-equal sign: Latin-1 only): once its
-- validated sample (Accord.Sample: the characters of the guilds counted whose BattleTag it holds,
-- and how many BattleTags) holds SAMPLE_MIN accounts or more, the people are the validated accounts
-- plus the characters not yet validated at that sample's characters per account, to three
-- significant figures; never fewer than the players the samples tell apart (BattleTags, and the
-- players who linked alts, Alts.Sample), never more than the plain count. With fewer validated
-- accounts it shows the plain count as a member's does. The staff (a team client, never on the
-- King's stream) also see the validated accounts, the characters not yet validated and the rate;
-- any other client shows none of it. Counts only: never a tag or a name. (A later release may bring
-- the team's rate to members through the Companion.)

CS.SAMPLE_MIN = 20 -- validated accounts, at least, before their rate counts

local function TeamSample(counted)
	local A = ns.Accord
	if type(A) ~= "table" or A.missing or type(A.TeamShown) ~= "function" or type(A.Sample) ~= "function" then return nil end
	local ok, team = pcall(A.TeamShown)
	if not ok or team ~= true then return nil end
	local okSample, characters, accounts = pcall(A.Sample, counted)
	if not okSample then return nil end
	return { characters = Count(characters) or 0, accounts = Count(accounts) or 0 }
end

local function AltSample(counted)
	local A = ns.Alts
	if type(A) ~= "table" or A.missing or type(A.Sample) ~= "function" then return nil end
	local ok, characters, people = pcall(A.Sample, counted)
	if not ok then return nil end
	return { characters = Count(characters) or 0, people = Count(people) or 0 }
end

-- `n` (rounded to a whole number) to three significant figures, and the step it was rounded to.
function CS.Round3(n)
	n = math.max(0, math.floor((tonumber(n) or 0) + 0.5))
	local step = 1
	while n >= 1000 * step do step = step * 10 end
	return math.floor(n / step + 0.5) * step, step
end

-- The people from `s` (Data.Summary()): { characters, people (the plain count), shown (what the
-- header shows), approx }; while approx (a team client's BattleTag estimate) also estimate, rate
-- (characters per validated account) and sample = { kind = "battletag", size (accounts),
-- characters }; on a team client also staff, validated (accounts), validatedCharacters and
-- unvalidated (characters not yet validated). Anywhere else: approx false, shown the plain count.
function CS.PeopleEstimate(s)
	s = s or ns.Data.Summary()
	local characters = Count(s.characters or s.total) or 0
	local people = math.min(Count(s.total) or 0, characters)
	local out = { characters = characters, people = people, shown = people, approx = false }
	local counted = {}
	for _, e in ipairs(s.guilds or {}) do
		if type(e) == "table" and e.counted and type(e.name) == "string" then counted[e.name:lower()] = true end
	end
	local team = TeamSample(counted)
	if not team then return out end
	team.characters = math.min(team.characters, characters)
	team.accounts = math.min(team.accounts, team.characters)
	out.staff, out.validated, out.validatedCharacters = true, team.accounts, team.characters
	out.unvalidated = characters - team.characters
	if characters <= 0 or team.accounts < CS.SAMPLE_MIN then return out end
	local least, most = team.accounts, people
	local alts = AltSample(counted)
	if alts then least = math.max(least, math.min(alts.people, alts.characters, characters)) end
	out.rate = team.characters / team.accounts
	out.sample = { kind = "battletag", size = team.accounts, characters = team.characters }
	local raw = team.accounts + out.unvalidated / out.rate
	local within = math.min(most, math.max(least, raw))
	local shown, step = CS.Round3(within)
	if shown > most then shown = math.floor(within / step) * step end
	if shown < least or shown > most then shown = math.floor(within + 0.5) end
	out.estimate, out.shown, out.approx = shown, shown, true
	return out
end

-- A rate as the page writes it: two decimals, the language's mark ("1.25", "1,25").
local function Rate(r)
	local hundredths = math.floor((tonumber(r) or 0) * 100 + 0.5)
	return ("%d%s%02d"):format(math.floor(hundredths / 100), L.DECIMAL_MARK or ".", hundredths % 100)
end
CS.Rate = Rate

local function Stream()
	local A = ns.Accord
	if type(A) ~= "table" or A.missing or type(A.Stream) ~= "function" then return false end
	local ok, on = pcall(A.Stream)
	return ok and on == true
end

-- The header's people: a team client's estimate ("~80,500 people"), else the plain count in the
-- members' words ("about 80,500 people").
function CS.PeopleText(s, e)
	e = e or CS.PeopleEstimate(s)
	if e.approx then return L.ARMY_PEOPLE_APPROX:format(F(e.shown)) end
	return L.ARMY_PEOPLE:format(F(e.people))
end

-- Whether the staff's figures of `e` show (a team client, never on the King's stream): the page's
-- line and rows, and the Bridge's (BridgeSections.lua's stats).
function CS.StaffShown(e)
	return type(e) == "table" and e.staff == true and not Stream()
end

-- The staff's line (CS.StaffShown), nil for anyone else.
function CS.StaffLine(e)
	if not CS.StaffShown(e) then return nil end
	if e.sample and e.sample.kind == "battletag" then
		return L.PEOPLE_STAFF_TAGS:format(F(e.validated), Rate(e.rate), F(e.unvalidated))
	end
	return L.PEOPLE_STAFF_NONE:format(F(e.validated), F(e.unvalidated), F(CS.SAMPLE_MIN))
end

-- A sample of the history's people (`p`, of `c` characters) as the page shows them: while the
-- people are a team client's estimate (`e`, CS.PeopleEstimate), "~" and that sample's characters at
-- the estimate's people per character, to three significant figures and never above the sample's
-- own count; else its plain count, as the header's. (The review of 2026-10-20: the graphs' tooltips
-- told the plain count beside the header's "~".)
function CS.PeopleAt(p, c, e)
	p = Count(p) or 0
	if type(e) ~= "table" or not e.approx or not tonumber(e.rate) or (tonumber(e.characters) or 0) <= 0 then return F(p) end
	local within = math.min(p, (Count(c) or 0) * e.shown / e.characters)
	local shown, step = CS.Round3(within)
	if shown > p then shown = math.floor(within / step) * step end
	return L.CENSUS_STATS_APPROX:format(F(shown))
end

-- The lines the header's tooltip adds about the people: what "~" means while it shows, and the
-- staff's line.
function CS.PeopleNotes(s, e)
	e = e or CS.PeopleEstimate(s)
	local out = {}
	if e.approx then out[#out + 1] = L.PEOPLE_ESTIMATE_TIP end
	local staff = CS.StaffLine(e)
	if staff then out[#out + 1] = staff end
	return out
end

-- The page's detail (its title stays the members' "How the people estimate is calculated"): the
-- members' formula, or while a team client's estimate shows, that estimate's.
function CS.DetailText(e)
	return type(e) == "table" and e.approx and L.CENSUS_STATS_DETAIL_TAGS or L.CENSUS_STATS_DETAIL
end

---------------------------------------------------------------------------
-- How the census works
---------------------------------------------------------------------------
-- (The author, 2026-10-20: "na pagina de censo (estatisticas dentro do botao) no addon e companion
-- quero explicacao de como dados funcionam, quebrados em topicos, dados validados, estimativas,
-- dados sanitizados, processos de validacao e sanitizacao... depois dos graficos", then the same
-- words on both pages.) The page's last section, after the graphs and the lists: seven topics, each
-- a small gold title and its lines. Every number is the code's own constant (Data, CensusClean,
-- this file), so the words follow it: the reports' 15 minutes (Data.FRESH), a size's day
-- (Data.TOTAL_KEEP), the week a guild stays listed (Data.KEEP), the votes' half hour
-- (Data.VOUCH_TTL), the dispute's margins (Data.SIZE_SLACK, SIZE_SHARE, SIZE_DRIFT), the held
-- size's (CensusClean.JUMP_MIN, JUMP_SHARE, JUMP_DRIFT; its hour, OUTLIER_HOLD, in words), the
-- validated accounts a team client's estimate needs (SAMPLE_MIN) and the history's bounds (EVERY,
-- RECENT_KEEP, DAYS). The estimates' topic says what a member's client shows (the plain count) and
-- what a moderation team client's shows (its "~" estimate), as CS.PeopleEstimate does.

-- A paragraph in rows short enough for the page (its rows are one line each: Views.Render), split
-- at spaces, about WRAP letters a row, as the Treasury's and the Dues' pages do. The last row takes
-- `gapAfter`.
CS.WRAP = 58
local function Para(lines, text, color, gapAfter)
	local row = ""
	for word in tostring(text or ""):gmatch("%S+") do
		if row ~= "" and #row + 1 + #word > CS.WRAP then
			lines[#lines + 1] = { text = color(row) }
			row = word
		else
			row = row == "" and word or (row .. " " .. word)
		end
	end
	if row ~= "" then lines[#lines + 1] = { text = color(row), gapAfter = gapAfter } end
end

local function Minutes(seconds) return math.floor(seconds / 60 + 0.5) end
local function Hours(seconds) return math.floor(seconds / 3600 + 0.5) end
local function Days(seconds) return math.floor(seconds / 86400 + 0.5) end
local function Percent100(share) return math.floor(share * 100 + 0.5) end

-- (The author, 2026-10-20: "que o processo de sanitização fosse bem estruturado, como por um
-- profissional data analyst, e explicado na página como funciona: info/records mais recentes no
-- jogo por cima de base sólida com data e hora e regras de como funciona".) A first topic, how the
-- census is built (each guild's newest record over what was known, each with its time), and the
-- sanitizing as numbered rules S1 to S5: S1 the door (Codec.DecodeReport, Data's Take and the
-- relayed rows' GlobalTake; the cap is Codec.GUILD_CAP, its "5 minutes ahead" in words), S2 the
-- recency (Data.FRESH, TOTAL_KEEP, KEEP), S3 the exclusions (net-off, /who alone), S4 the agreement
-- (CensusClean.Confidence: FRESH, and the votes' Data.VOUCH_TTL that Data.Dispute counts senders
-- in) and S5 the impossible jump (CensusClean's JUMP_MIN, JUMP_SHARE, JUMP_DRIFT; OUTLIER_HOLD in
-- words). The first topic's outvote holds while the row it would replace is FRESH (Data's Take).

-- The seven topics, in order: { title, lines = { text, ... } } each.
function CS.HowTopics()
	local D = ns.Data
	local C = ns.CensusClean
	if type(C) ~= "table" or C.missing or type(C.JUMP_MIN) ~= "number" then C = nil end
	local fresh, total, keep = Minutes(D.FRESH), Hours(D.TOTAL_KEEP), Days(D.KEEP)
	local sanitizing = {
		L.CENSUS_STATS_HOW_SANITIZING_RULES,
		L.CENSUS_STATS_HOW_SANITIZING_S1:format(F(ns.Codec.GUILD_CAP)),
		L.CENSUS_STATS_HOW_SANITIZING_S2:format(fresh, total, keep),
		L.CENSUS_STATS_HOW_SANITIZING_S3,
		L.CENSUS_STATS_HOW_SANITIZING_S4:format(fresh, Minutes(D.VOUCH_TTL)),
	}
	local sanitized = { L.CENSUS_STATS_HOW_SANITIZED_OUT:format(total) }
	-- (Without CensusClean, a client updated without a restart, nothing is held and S5's margins are
	-- not to be had: neither S5 nor the held size's line, which names it.)
	if C then
		sanitizing[#sanitizing + 1] = L.CENSUS_STATS_HOW_SANITIZING_S5:format(C.JUMP_MIN, Percent100(C.JUMP_SHARE), C.JUMP_DRIFT)
		sanitized[#sanitized + 1] = L.CENSUS_STATS_HOW_SANITIZED_HELD
	end
	return {
		{ title = L.CENSUS_STATS_HOW_BUILT, lines = { L.CENSUS_STATS_HOW_BUILT_BASE, L.CENSUS_STATS_HOW_BUILT_NEWER:format(fresh) } },
		{ title = L.CENSUS_STATS_HOW_SOURCE, lines = { L.CENSUS_STATS_HOW_SOURCE_REPORT, L.CENSUS_STATS_HOW_SOURCE_KEPT } },
		{ title = L.CENSUS_STATS_HOW_VALIDATED, lines = { L.CENSUS_STATS_HOW_VALIDATED_WHEN:format(fresh) } },
		{ title = L.CENSUS_STATS_HOW_ESTIMATES, lines = {
			L.CENSUS_STATS_HOW_ESTIMATES_PLAIN,
			L.CENSUS_STATS_HOW_ESTIMATES_RATE:format(CS.SAMPLE_MIN),
			L.CENSUS_STATS_HOW_ESTIMATES_ROUND,
			L.PEOPLE_ESTIMATE_MORE,
			L.CENSUS_STATS_HOW_ESTIMATES_ONLINE:format(fresh, total),
			L.CENSUS_STATS_HOW_ESTIMATES_GRAPHS:format(Minutes(CS.EVERY), Hours(CS.RECENT_KEEP), CS.DAYS),
		} },
		{ title = L.CENSUS_STATS_HOW_SANITIZED, lines = sanitized },
		{ title = L.CENSUS_STATS_HOW_VALIDATION, lines = {
			L.CENSUS_STATS_HOW_VALIDATION_VOTE,
			L.CENSUS_STATS_HOW_VALIDATION_DISPUTE:format(D.SIZE_SLACK, Percent100(D.SIZE_SHARE), D.SIZE_DRIFT),
			L.CENSUS_STATS_HOW_VALIDATION_COUNT,
		} },
		{ title = L.CENSUS_STATS_HOW_SANITIZING, lines = sanitizing },
	}
end

-- The section's rows, added to `lines`: its header, then each topic's title and its lines.
function CS.HowLines(lines)
	local Vw = V()
	if #lines > 0 then lines[#lines].gapAfter = true end
	lines[#lines + 1] = { text = L.CENSUS_STATS_HOW, header = true }
	for _, topic in ipairs(CS.HowTopics()) do
		lines[#lines + 1] = { text = Vw.Gold(topic.title) }
		for _, text in ipairs(topic.lines) do Para(lines, text, Vw.Grey, true) end
	end
	return lines
end

-- The page's lines, its detail title and text (Views.Build's census, while the page shows).
function CS.Build(s, now)
	s = s or ns.Data.Summary()
	now = now or ns.Now()
	local Vw = V()
	local Gold, Grey, Green = Vw.Gold, Vw.Grey, Vw.Green
	local Plain = ns.Codec.Plain
	local lines = {
		{ text = Gold(L.CENSUS_STATS_BACK), onClick = function()
			CS.Close()
			if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
		end, gapAfter = true },
		{ text = L.CENSUS_STATS_TITLE, header = true },
	}
	local characters, people = s.characters or s.total or 0, s.total or 0
	local counted, live = 0, 0
	for _, e in ipairs(s.guilds or {}) do
		if e.counted then counted = counted + 1 end
		if e.fresh then live = live + 1 end
	end
	lines[#lines + 1] = Row(L.CENSUS_STATS_CHARACTERS, White(F(characters)), L.CENSUS_STATS_CHARACTERS_TIP)
	-- The people: the plain count (a member's), or a team client's "~" estimate, its tooltip saying
	-- so; the staff's validated accounts, characters not yet validated and rate under it
	-- (CS.PeopleEstimate).
	local est = CS.PeopleEstimate(s)
	local detail = CS.DetailText(est)
	local staff = CS.StaffLine(est)
	-- (The review of 2026-10-20: while it is an estimate, what "~" means takes the place of the plain
	-- count's words, "a player who linked none counts once per character", which said otherwise;
	-- the linked alts' row then has words of its own.)
	lines[#lines + 1] = Row(L.CENSUS_STATS_PEOPLE, White(est.approx and L.CENSUS_STATS_APPROX:format(F(est.shown)) or F(people)), L.CENSUS_STATS_PEOPLE_TIP)
	if est.approx or staff then
		lines[#lines].tooltip = function(tt)
			tt:AddLine(L.CENSUS_STATS_PEOPLE, 1, 0.82, 0)
			if not est.approx then tt:AddLine(L.CENSUS_STATS_PEOPLE_TIP, 1, 1, 1, true) end
			for i, note in ipairs(CS.PeopleNotes(s, est)) do
				if i == 1 and est.approx then tt:AddLine(note, 1, 1, 1, true) else tt:AddLine(note, 0.75, 0.75, 0.75, true) end
			end
		end
	end
	lines[#lines + 1] = Row(L.CENSUS_STATS_ALTS, Grey(F(s.alts or 0)), L.CENSUS_STATS_ALTS_TIP, 1)
	if staff then
		local rate = est.sample and est.sample.kind == "battletag" and Rate(est.rate) .. " " .. L.CENSUS_STATS_RATE_TAGS:format(F(est.sample.size)) or "-"
		lines[#lines + 1] = Row(L.CENSUS_STATS_VALIDATED, Grey(F(est.validated)), staff, 1)
		lines[#lines + 1] = Row(L.CENSUS_STATS_UNVALIDATED, Grey(F(est.unvalidated)), staff, 1)
		lines[#lines + 1] = Row(L.CENSUS_STATS_RATE, Grey(rate), staff, 1)
		if est.sample and est.sample.kind == "battletag" then
			lines[#lines + 1] = Row(L.CENSUS_STATS_TAG_EXTRAS, Grey(F(est.validatedCharacters - est.validated)),
				L.CENSUS_STATS_TAG_EXTRAS_TIP, 1)
		end
	end
	lines[#lines + 1] = Row(L.CENSUS_STATS_ONLINE, Green(F(s.online or 0)))
	lines[#lines + 1] = Row(L.CENSUS_STATS_GUILDS, White(tostring(counted)) .. "  " .. Grey(L.CENSUS_STATS_GUILDS_LIVE:format(live)), L.CENSUS_STATS_GUILDS_TIP)
	local avg = CS.AverageLevel(s)
	lines[#lines + 1] = Row(L.CENSUS_STATS_AVG, avg and White(avg) or Grey("-"), L.CENSUS_STATS_AVG_TIP)
	lines[#lines].gapAfter = true

	local army, days = ArmyGraph(now, est)
	GraphLines(lines, L.CENSUS_STATS_ARMY_GRAPH, army, days, function(e) return e.c end, DayLabel, detail)
	local online, hours = OnlineGraph(now, est)
	GraphLines(lines, L.CENSUS_STATS_ONLINE_GRAPH, online, hours, function(e) return e.o end, HourLabel, detail)

	-- 1.4.0 (the author, 11-03): the "largest guilds" are gone ("sempre vai ser as guildas com 1000,
	-- então não vai ter primeiro lugar, aquela lista não faz sentido"); in their place every server
	-- this client knows of: the totals, PvP and PvE, NA and EU, and each server (Data.Groups).
	CS.ServerLines(lines, s, now)

	-- The levels online.
	local bands = CS.LevelBands(s)
	if bands then
		local sum = 0
		for i = 1, 7 do sum = sum + bands[i] end
		lines[#lines + 1] = { text = L.CENSUS_STATS_LEVELS, header = true, tooltip = function(tt)
			tt:AddLine(L.CENSUS_STATS_LEVELS, 1, 0.82, 0)
			tt:AddLine(L.CENSUS_STATS_LEVELS_TIP, 1, 1, 1, true)
		end }
		for i = 7, 1, -1 do
			if bands[i] > 0 then
				local label = i == 7 and L.CENSUS_STATS_LEVEL_TOP:format(60) or L.CENSUS_STATS_LEVEL_BAND:format(i == 1 and 1 or (i - 1) * 10, i * 10 - 1)
				lines[#lines + 1] = { text = label, right = Green(F(bands[i])) .. " " .. Grey(Percent(bands[i], sum) .. "%"),
					meter = { value = bands[i], total = sum } }
			end
		end
		lines[#lines].gapAfter = true
	end

	local since = CS.Since()
	if since then lines[#lines + 1] = { text = Grey(L.CENSUS_STATS_KEPT:format(date(L.CENSUS_STATS_DAY_FORMAT, since))) } end
	-- How the census works: after the graphs and the lists, the page's last section.
	CS.HowLines(lines)
	return lines, L.CENSUS_STATS_DETAIL_TITLE, detail
end

---------------------------------------------------------------------------
-- The sampler
---------------------------------------------------------------------------

ns.On("INIT", function() ns.SafeCall("census history", CS.Prune) end)
ns.On("LOGIN", function()
	ns.Every(CS.TICK, "census history", function() CS.Sample() end)
end)
