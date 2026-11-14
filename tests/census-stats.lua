-- CR-02 / KH-08 (the author's ask, 2026-10-19): the people next to the characters in the window's
-- header, smaller and darker; a click on that count opens the census's own page inside the Census
-- tab (CensusStats.lua): its numbers, its largest guilds and levels online, and two graphs of this
-- client's own light history (a sample every 15 minutes, 30 days kept, bounded, never sent).
-- Loaded by tests/run.lua with the harness's WithUI and LoadUI.
local ns, test, eq, extra = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]census%-stats%.lua$")) or "./"
local WithUI, LoadUI = extra.WithUI, extra.LoadUI
local L, V = ns.L, ns.Views

-- The page's words, as the game loads them (English here; Portuguese below).
assert(loadfile(ROOT .. "Olympus/Locales/CensusStatsText.lua"))("Olympus", ns)

local function Bare(s) return (tostring(s or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local T0 = os.time({ year = 2026, month = 10, day = 19, hour = 15, min = 0, sec = 0 })

-- CensusStats.lua in a namespace of its own: its own saved store (rdb), clock and listeners, and
-- (o.data) a census of its own, or the harness's real one (Data.Summary over ns.rdb.guilds).
-- Anything sent fails the test: the history is this client's alone.
local function World(o)
	o = o or {}
	local w = { clock = o.clock or T0, on = {}, every = {}, sent = 0 }
	local census = { characters = 1000, total = 990, online = 120, guilds = {} }
	w.census = census
	local data = o.realData and ns.Data or setmetatable({
		Summary = function() return census end,
		Rebuilding = function() return w.rebuilding end,
		CROWN_AFTER = 200,
	}, { __index = ns.Data })
	local cns = setmetatable({
		rdb = o.rdb or {},
		L = o.L, -- (the page's words in another language: nil, the harness's own)
		Data = data,
		Now = function() return w.clock end,
		Comm = { loginAt = o.loginAt or (T0 - 100 * 86400), Send = function() w.sent = w.sent + 1 end, SendChunked = function() w.sent = w.sent + 1 end },
		On = function(name, fn) w.on[name] = w.on[name] or {}; table.insert(w.on[name], fn) end,
		Every = function(seconds, where, fn) w.every[#w.every + 1] = { seconds = seconds, where = where, fn = fn } end,
	}, { __index = ns })
	assert(loadfile(ROOT .. "Olympus/CensusStats.lua"))("Olympus", cns)
	w.ns, w.CS = cns, cns.CensusStats
	function w.History() return cns.rdb.censusHistory end
	function w.Fire(name) for _, fn in ipairs(w.on[name] or {}) do fn() end end
	return w
end

local function Keys(t)
	local out = {}
	for k in pairs(t) do out[#out + 1] = k end
	table.sort(out)
	return out
end

test("census continuity: a retained count is not recorded as a new history observation", function()
	local w = World()
	w.census.snapshot = { observed = T0 - 3600, characters = 1000 }
	eq(w.CS.Sample(), false)
	eq(#w.History().recent, 0)
end)

test("census continuity: clicking a server exposes scoped guild details and their original observation", function()
	local w = World()
	w.ns.Data.Groups = function() return { characters = 640, people = 600, kinds = {}, regions = {}, factions = {},
		rows = { { group = "Foreign", faction = "Alliance", characters = 640, people = 600, guilds = 1, observed = T0 - 600,
			src = "witnessed", counted = true, ours = false } } } end
	w.ns.Data.GroupGuilds = function(group, faction)
		eq(group, "Foreign"); eq(faction, "Alliance")
		return { { name = "Olympus Dawn", characters = 640, observed = T0 - 600, source = "witnessed", counted = true } }
	end
	local lines = {}
	w.CS.ServerLines(lines, w.census, T0)
	local server
	for _, line in ipairs(lines) do if line.onClick then server = line end end
	assert(server); server.onClick()
	lines = {}
	w.CS.ServerLines(lines, w.census, T0)
	local detail
	for _, line in ipairs(lines) do if line.text == "Olympus Dawn" then detail = line end end
	assert(detail); eq(detail.indent, 3); eq(Bare(detail.right), "640")
	local tip = {}
	detail.tooltip({ AddLine = function(_, text) tip[#tip + 1] = text end, AddDoubleLine = function() end })
	assert(table.concat(tip, " "):find(L.CENSUS_STATS_SRC_WITNESSED, 1, true))
end)

test("census continuity: server and ruleset hovers retain the original date and time", function()
	local w = World()
	local rows = {
		{ group = "ForeverPvE", faction = "Alliance", kind = "pve", characters = 700, people = 700, guilds = 2,
			observed = T0 - 7200, src = "live", counted = true, ours = true },
		{ group = "ForeverPvP", faction = "Alliance", kind = "pvp", characters = 500, people = 500, guilds = 1,
			observed = T0 - 3600, src = "relay", counted = true },
		{ group = "ForeverRP", faction = "Alliance", kind = "rp", characters = 20, people = 20, guilds = 1,
			observed = T0 - 600, src = "own", counted = true },
	}
	w.ns.Data.Groups = function() return { characters = 1220, people = 1220, rows = rows, regions = {}, factions = {},
		kinds = { pve = rows[1], pvp = rows[2], rp = rows[3] } } end
	for _, clock in ipairs({ T0, T0 + 600 }) do
		w.clock = clock
		local lines = {}; w.CS.ServerLines(lines, w.census, clock)
		for i, label in ipairs({ L.CENSUS_STATS_KIND_PVE, L.CENSUS_STATS_KIND_PVP, L.CENSUS_STATS_KIND_RP }) do
			local found = 0
			for _, line in ipairs(lines) do
				if line.tooltip and (line.text == label or Bare(line.text):find(rows[i].group, 1, true)) then
					local tip = {}; line.tooltip({ AddLine = function(_, text) tip[#tip + 1] = text end, AddDoubleLine = function() end })
					assert(table.concat(tip, " "):find(os.date("%Y-%m-%d %H:%M", rows[i].observed), 1, true), "missing original time for " .. label)
					found = found + 1
				end
			end
			eq(found, 2, "both ruleset and server show time")
		end
	end
end)

-- 1.5.9 (the census items left from 1.5.8). Fails before: the all-server totals had no date, though a
-- server's last count now stays in them until a newer one arrives (Data.lua's Lasting): days old, maybe.
test("census servers (1.5.9): the all-server totals carry the date of the oldest other server's count in them, in every language; none while they hold none", function()
	local w = World()
	local old = T0 - 9 * 86400
	local rows = {
		{ group = "ForeverPvE", faction = "Alliance", kind = "pve", characters = 700, people = 700, guilds = 2,
			observed = T0 - 60, src = "live", counted = true, ours = true },
		{ group = "ForeverPvP", faction = "Alliance", kind = "pvp", characters = 500, people = 500, guilds = 1,
			observed = old, src = "author", counted = true },
	}
	w.ns.Data.Groups = function() return { characters = 1200, people = 1200, rows = rows, kinds = {}, regions = {}, factions = {},
		oldestOther = old } end
	local lines = {}
	w.CS.ServerLines(lines, w.census, T0)
	local want = L.CENSUS_STATS_SERVERS_AS_OF:format(os.date("%Y-%m-%d %H:%M", old))
	local at
	for i, line in ipairs(lines) do if Bare(line.text) == want then at = i end end
	assert(at, "the date line: " .. want)
	eq(Bare(lines[at - 1].text), L.CENSUS_STATS_ALL_PEOPLE, "right under the totals")
	local tip = {}
	lines[at].tooltip({ AddLine = function(_, text) tip[#tip + 1] = text end, AddDoubleLine = function() end })
	assert(table.concat(tip, " "):find(L.CENSUS_STATS_SERVERS_AS_OF_TIP, 1, true), "its tooltip says what it is")
	w.ns.Data.Groups = function() return { characters = 700, people = 700, rows = { rows[1] }, kinds = {}, regions = {}, factions = {} } end
	lines = {}
	w.CS.ServerLines(lines, w.census, T0)
	local prefix = L.CENSUS_STATS_SERVERS_AS_OF:match("^(.-)%%s")
	for _, line in ipairs(lines) do assert(not Bare(line.text):find(prefix, 1, true), "no date while no other server counts") end
	-- Every language the addon speaks, each as the game loads it: both lines, translated.
	local english = L.CENSUS_STATS_SERVERS_AS_OF
	for _, code in ipairs({ "ptBR", "deDE", "esES", "frFR", "itIT", "ruRU" }) do
		local lns, saved = {}, GetLocale
		GetLocale = function() return code end
		local ok, err = pcall(function()
			assert(loadfile(ROOT .. "Olympus/Locales.lua"))("Olympus", lns)
			assert(loadfile(ROOT .. "Olympus/Locales/CensusStatsText.lua"))("Olympus", lns)
			if code ~= "ptBR" then assert(loadfile(ROOT .. "Olympus/Locales/" .. code .. ".lua"))("Olympus", lns) end
		end)
		GetLocale = saved
		if not ok then error(err, 0) end
		local text, tipText = lns.L.CENSUS_STATS_SERVERS_AS_OF, lns.L.CENSUS_STATS_SERVERS_AS_OF_TIP
		assert(text ~= english and text:find("%s", 1, true), code .. " translates the line, its date kept")
		assert(tipText ~= L.CENSUS_STATS_SERVERS_AS_OF_TIP, code .. " translates its tooltip")
		assert(#text:format("2026-11-05 14:30") <= 55 * (code == "ruRU" and 2 or 1.2), code .. ": a short line")
	end
end)

test("census origin labels: a known ruleset shows unavailable region without a ruleset warning", function()
	local w = World()
	local row = { group = "ForeverPvE", faction = "Alliance", kind = "pve", characters = 700, people = 700,
		guilds = 2, observed = T0 - 600, src = "live", counted = true, ours = true }
	w.ns.Data.Groups = function()
		return { characters = 700, people = 700, rows = { row }, kinds = { pve = row }, regions = { ["?"] = row }, factions = {} }
	end
	local labels, lines = {}, {}
	w.CS.ServerLines(lines, w.census, T0)
	for _, line in ipairs(lines) do labels[Bare(line.text)] = true end
	assert(labels[L.CENSUS_STATS_BY_KIND], "the available ruleset still appears")
	assert(labels["Region unavailable for these totals."], "regional coverage is explained separately")
	eq(labels[L.CENSUS_STATS_KIND_WAIT], nil)
	eq(labels[L.CENSUS_STATS_BY_REGION], nil)
end)

test("census history: a sample every 15 minutes once the census is rebuilt after login, the day's highest counts kept; nothing sent", function()
	local w = World({ loginAt = T0 - 60 })
	local CS = w.CS
	eq(CS.EVERY, 15 * 60); eq(CS.DAYS, 30)
	-- Right after login, the census is still being rebuilt: no sample (it would look like growth).
	eq(CS.Sample(), false, "within Data.CROWN_AFTER of login")
	w.clock = T0 - 60 + 200
	w.rebuilding = 4
	eq(CS.Sample(), false, "the census still says it is rebuilding")
	w.rebuilding = nil
	eq(CS.Sample(), true, "the first sample")
	local h = w.History()
	eq(#h.recent, 1); eq(h.recent[1], ("%d,1000,990,120"):format(w.clock)); eq(h.t, w.clock)
	local today = os.date("%Y-%m-%d", w.clock)
	eq(h.days[today], "1000,990,120,1")
	-- Not again before the quarter-hour is over.
	w.clock = w.clock + CS.EVERY - 1
	eq(CS.Sample(), false)
	-- Then again; the day keeps its highest counts and how many samples it holds.
	w.clock = w.clock + 1
	w.census.characters, w.census.total, w.census.online = 1012, 1001, 80
	eq(CS.Sample(), true)
	eq(#w.History().recent, 2)
	eq(w.History().days[today], "1012,1001,120,2", "the highest characters and people, the most online")
	-- An empty census (nothing heard) is no sample.
	w.clock = w.clock + CS.EVERY
	w.census.characters, w.census.total, w.census.online = 0, 0, 0
	eq(CS.Sample(), false)
	eq(w.sent, 0, "nothing sent")
	-- The sampler runs on its own minute tick from login, and the store is mended at INIT.
	eq(#w.every, 0)
	w.Fire("LOGIN")
	eq(#w.every, 1); eq(w.every[1].seconds, CS.TICK)
	assert(w.on.INIT and #w.on.INIT == 1, "pruned at INIT")
end)

test("census history: bounded: the last 48 hours sample by sample, 30 days of daily lines, nothing from the future; a damaged store starts again", function()
	local w = World()
	local CS = w.CS
	-- 32 days of a sample every 15 minutes.
	local start = T0 - 32 * 86400
	for k = 0, 32 * 96 do
		w.clock = start + k * CS.EVERY
		w.census.characters = 1000 + math.floor(k / 96)
		w.census.total = w.census.characters - 10
		CS.Sample()
	end
	local h = w.History()
	assert(#h.recent <= CS.RECENT_MAX, "recent " .. #h.recent)
	eq(#h.recent, 193, "two days of quarter-hours (both ends)")
	local first = tonumber(h.recent[1]:match("^(%d+),"))
	assert(w.clock - first <= CS.RECENT_KEEP, "nothing older than 48 hours")
	local days = Keys(h.days)
	eq(#days, CS.DAYS, "30 days")
	eq(days[#days], os.date("%Y-%m-%d", w.clock), "today the last")
	eq(days[1], os.date("%Y-%m-%d", w.clock - 29 * 86400), "29 days ago the first")
	-- The clock went back an hour: what was taken "later" is dropped, and a sample is due again.
	w.clock = w.clock - 3600 - CS.FUTURE - 1
	eq(CS.Sample(), true, "a store from the future does not stop the sampler")
	for _, s in ipairs(w.History().recent) do
		assert(tonumber(s:match("^(%d+),")) <= w.clock + CS.FUTURE, "no sample from the future")
	end
	-- Damaged: another shape, junk entries, keys and text.
	local d = World({ rdb = { censusHistory = "junk" } })
	d.CS.Prune()
	eq(type(d.History()), "table"); eq(d.History().v, 1); eq(#d.History().recent, 0)
	local j = World({ rdb = { censusHistory = { v = 1, t = 0,
		recent = { "x", ("%d,5,4,3"):format(T0 - 60), ("%d,5,4,3|cffff0000"):format(T0), 42, ("%d,99999999999,1,1"):format(T0) },
		days = { [os.date("%Y-%m-%d", T0)] = "5,4,3,1", ["2026-13-99x"] = "1,1,1,1", [7] = "1,1,1,1", [os.date("%Y-%m-%d", T0 - 86400)] = "a,b" } } } })
	j.CS.Prune()
	eq(#j.History().recent, 1, "only the well formed sample"); eq(j.History().recent[1], ("%d,5,4,3"):format(T0 - 60))
	eq(table.concat(Keys(j.History().days), ","), os.date("%Y-%m-%d", T0))
end)

test("census history: the 30 days oldest first (no sample: no value), the 24 hours each its most online", function()
	local w = World()
	local CS = w.CS
	w.clock = T0 - 2 * 86400
	CS.Sample() -- two days ago
	w.clock = T0 - 3 * 3600 - 45 * 60
	w.census.online = 50
	CS.Sample()
	w.clock = w.clock + CS.EVERY
	w.census.online = 70
	w.census.characters = 1005
	CS.Sample()
	w.clock = T0
	w.census.online = 30
	CS.Sample()
	local days = CS.DaySeries()
	eq(#days, 30)
	eq(days[30].key, os.date("%Y-%m-%d", T0)); eq(days[30].ago, 0); eq(days[30].c, 1005)
	eq(days[28].c, 1000, "two days ago"); eq(days[29].c, nil, "yesterday: no sample")
	eq(days[1].key, os.date("%Y-%m-%d", T0 - 29 * 86400))
	local hours = CS.HourSeries()
	eq(#hours, 24)
	eq(hours[24].o, 30, "the last hour")
	eq(hours[21].o, 70, "three hours back: the most online of its two samples"); eq(hours[21].c, 1005)
	eq(hours[22].o, nil); eq(hours[23].o, nil)
	eq(hours[1].ago, 23)
	local first = os.date("*t", T0 - 2 * 86400)
	eq(CS.Since(), os.time({ year = first.year, month = first.month, day = first.day, hour = 0 }), "since the first day's start")
	-- Scales: online from 0 to a round number; the army from a round number under its lowest.
	local lo, hi = CS.Scale({ 30, nil, 3210 }, 3, true)
	eq(lo, 0); eq(hi, 4000)
	lo, hi = CS.Scale({ 84900, 85012 }, 2, false)
	assert(lo < 84900 and hi > 85012, lo .. " " .. hi)
	eq(lo % 10, 0); eq(hi % 10, 0)
	lo, hi = CS.Scale({ 500, 500 }, 2, false)
	assert(lo < 500 and hi > 500, "a flat series still has a scale")
	eq(CS.Scale({}, 3, true), nil)
end)

-- fn with these reports as the census, a sample history from `samples` ({ ago, c, p, o } each),
-- and the page built by CensusStats.Build with the harness's real Data.Summary.
local function Report(total, more)
	local r = { total = total, online = 10, zones = {}, t = os.time(), leader = "Lead", leaderOnline = true, officers = {}, mine = true }
	for k, v in pairs(more or {}) do r[k] = v end
	return r
end
local function WithCensus(guilds, alts, fn)
	local saved = { guilds = ns.rdb.guilds, seen = ns.rdb.seen, alts = ns.Alts,
		group = ns.group, groups = ns.db.groupCensus, heard = ns.db.groupHeard }
	ns.rdb.guilds, ns.rdb.seen = guilds, {}
	-- A logged-in census always has an origin. Isolate its saved cross-server counts too,
	-- so the header's new all-server total cannot inherit another test's session.
	ns.group, ns.db.groupCensus, ns.db.groupHeard = "Realm", {}, {}
	ns.Alts = { Duplicates = function() return alts end }
	local ok, err = pcall(fn)
	ns.rdb.guilds, ns.rdb.seen, ns.Alts = saved.guilds, saved.seen, saved.alts
	ns.group, ns.db.groupCensus, ns.db.groupHeard = saved.group, saved.groups, saved.heard
	if not ok then error(err, 0) end
end
local function Find(lines, text)
	for i, line in ipairs(lines) do if Bare(line.text) == text then return line, i end end
end

test("census page: characters, people, linked alts, online, guilds counted, the weighted average level, every server (1.4.0, no largest guilds) and the levels online", function()
	WithCensus({
		["Olympus"] = Report(900, { online = 200, avgLevel = 40, levels = { 10, 20, 30, 40, 50, 30, 20 } }),
		["Olympus II"] = Report(300, { online = 50, avgLevel = 60, levels = { 0, 0, 0, 0, 10, 20, 20 } }),
		["Olympus III"] = Report(100, { online = 0, avgLevel = nil, t = os.time() - ns.Data.FRESH - 60 }),
	}, 4, function()
		local w = World({ realData = true, clock = os.time() })
		local lines, title, text = w.CS.Build()
		eq(title, L.CENSUS_STATS_DETAIL_TITLE); eq(text, L.CENSUS_STATS_DETAIL)
		assert(L.CENSUS_STATS_PEOPLE:lower():find("estimated", 1, true), "the page labels people as an estimate")
		assert(text:find("characters - confirmed linked alts", 1, true), "the visible detail explains the formula")
		assert(text:find("estimate can be high", 1, true), "the visible detail explains why it is approximate")
		eq(Bare(lines[1].text), L.CENSUS_STATS_BACK, "the way back first"); assert(lines[1].onClick)
		eq(lines[2].text, L.CENSUS_STATS_TITLE); eq(lines[2].header, true)
		eq(Bare(Find(lines, L.CENSUS_STATS_CHARACTERS).right), "1,300")
		eq(Bare(Find(lines, L.CENSUS_STATS_PEOPLE).right), "1,296", "the linked alts counted once")
		eq(Bare(Find(lines, L.CENSUS_STATS_ALTS).right), "4")
		eq(Bare(Find(lines, L.CENSUS_STATS_ONLINE).right), "250", "online: the guilds reporting now")
		eq(Bare(Find(lines, L.CENSUS_STATS_GUILDS).right), "3  " .. L.CENSUS_STATS_GUILDS_LIVE:format(2))
		-- (40 x 900 + 60 x 300) / 1200 = 45; the guild without one is left out.
		eq(Bare(Find(lines, L.CENSUS_STATS_AVG).right), "45.0")
		-- The people row explains itself.
		local tip = {}
		Find(lines, L.CENSUS_STATS_PEOPLE).tooltip({ AddLine = function(_, s) tip[#tip + 1] = s end })
		eq(tip[2], L.CENSUS_STATS_PEOPLE_TIP)
		-- 1.4.0 (the author, 11-03: "Guilda com mais jogadores... sempre vai ser as guildas com 1000...
		-- aquela lista não faz sentido"): no largest guilds; every server in their place, ours counted live.
		eq(Find(lines, "Largest guilds"), nil, "the largest guilds are gone")
		-- (Every server: its own test below, with a realm group known.)
		-- The levels online, the highest band first, from the guilds reporting now.
		local _, lv = Find(lines, L.CENSUS_STATS_LEVELS)
		assert(lv, "levels online")
		eq(Bare(lines[lv + 1].text), L.CENSUS_STATS_LEVEL_TOP:format(60)); eq(lines[lv + 1].meter.value, 40)
		eq(Bare(lines[lv + 1].right), "40 16%", "40 of 250")
		eq(Bare(lines[lv + 7].text), L.CENSUS_STATS_LEVEL_BAND:format(1, 9))
		-- No history yet: each graph says why there is none.
		local _, g = Find(lines, L.CENSUS_STATS_ARMY_GRAPH)
		eq(Bare(lines[g + 1].text), L.CENSUS_STATS_EMPTY_GRAPH); eq(lines[g + 1].graph, nil)
		eq(Find(lines, L.CENSUS_STATS_KEPT:format("x")), nil)
	end)
end)

-- 1.4.0 (the author, 11-03): every server on the page: "os números totais, tipo todas as pessoas
-- que estão jogando PVP e PVE ... quantas tem nesse servidor, quantas tem nesse. E, tipo, Europa, e
-- América do Norte"; "os números do beta não devem ser utilizados".
test("census page (1.4.0): every server: the totals, by ruleset and by region, each server with ours first; a lone report grey and out of the totals; the beta's never on a launch realm", function()
	local saved = { group = ns.group, info = ns.RealmInfo, counted = ns.db.groupCensus, heard = ns.db.groupHeard, faction = ns.faction }
	local ok, err = pcall(function()
		WithCensus({ ["Olympus"] = Report(900, { online = 200 }) }, 0, function()
			local now = os.time()
			ns.group, ns.faction = "Normalone+Normaltwo", "Alliance"
			ns.RealmInfo = function(realm)
				return ({ Normalone = { kind = "pve", region = "NA" }, Pvpone = { kind = "pvp", region = "NA" },
					Euro = { kind = "pvp", region = "EU" } })[realm]
			end
			ns.db.groupCensus = {
				["Alliance|Pvpone"] = { group = "Pvpone", faction = "Alliance", characters = 3000, people = 2500, guilds = 4, observed = now - 3600, src = "own" },
				["Alliance|Euro"] = { group = "Euro", faction = "Alliance", characters = 600, people = 500, guilds = 2, observed = now - 7200, src = "witnessed", w = 2 },
				["Alliance|ClassicBetaPvP+ClassicBetaPvP2"] = { group = "ClassicBetaPvP+ClassicBetaPvP2", faction = "Alliance", characters = 80000, people = 70000, guilds = 120, observed = now - 3600, src = "own" },
			}
			ns.db.groupHeard = {
				["Alliance|Lonely"] = { group = "Lonely", faction = "Alliance", characters = 9999, people = 9000, guilds = 9, observed = now - 600, src = "heard", w = 1 },
			}
			local w = World({ realData = true, clock = now })
			local lines = w.CS.Build()
			eq(Bare(Find(lines, L.CENSUS_STATS_ALL_CHARACTERS).right), "4,500", "900 here + 3,000 PvP + 600 EU; the beta and the lone report out")
			eq(Bare(Find(lines, L.CENSUS_STATS_ALL_PEOPLE).right), "~3,900")
			local _, kinds = Find(lines, L.CENSUS_STATS_BY_KIND)
			assert(kinds, "by ruleset")
			eq(Bare(lines[kinds + 1].text), L.CENSUS_STATS_KIND_PVP); eq(Bare(lines[kinds + 1].right), "3,600 80%")
			eq(Bare(lines[kinds + 2].text), L.CENSUS_STATS_KIND_PVE); eq(Bare(lines[kinds + 2].right), "900 20%")
			local _, regions = Find(lines, L.CENSUS_STATS_BY_REGION)
			eq(Bare(lines[regions + 1].text), L.CENSUS_STATS_REGION_NA); eq(Bare(lines[regions + 1].right), "3,900 87%")
			eq(Bare(lines[regions + 2].text), L.CENSUS_STATS_REGION_EU); eq(Bare(lines[regions + 2].right), "600 13%")
			eq(Find(lines, L.CENSUS_STATS_KIND_WAIT), nil, "every server's kind is known")
			local _, each = Find(lines, L.CENSUS_STATS_EACH_SERVER)
			assert(Bare(lines[each + 1].text):find("Normalone + Normaltwo", 1, true), "ours first")
			assert(Bare(lines[each + 1].text):find(L.CENSUS_STATS_HERE, 1, true))
			eq(Bare(lines[each + 1].right), "900")
			assert(Bare(lines[each + 2].text):find("Pvpone", 1, true)); eq(Bare(lines[each + 2].right), "3,000")
			assert(Bare(lines[each + 3].text):find("Euro", 1, true))
			eq(lines[each + 4].text, V.Grey("Lonely"), "a lone report: grey"); eq(lines[each + 4].right, V.Grey("9,999"))
			-- (The census page's explanation follows the servers since 1.4.0, v14/bridge: the next line is
			-- no server row.)
			assert(not lines[each + 5] or lines[each + 5].indent ~= 2, "the beta's realms: not listed on a launch realm")
			for _, line in ipairs(lines) do assert(not tostring(line.text):find("ClassicBeta", 1, true), "no beta anywhere") end
			-- With no realm table, each missing breakdown has its own status.
			ns.RealmInfo = nil
			lines = World({ realData = true, clock = now }).CS.Build()
			assert(Find(lines, L.CENSUS_STATS_KIND_WAIT), "the missing ruleset is explained")
			assert(Find(lines, L.CENSUS_STATS_REGION_UNAVAILABLE), "the missing region is explained separately")
			eq(Find(lines, L.CENSUS_STATS_BY_KIND), nil)
		end)
	end)
	ns.group, ns.RealmInfo, ns.db.groupCensus, ns.db.groupHeard, ns.faction = saved.group, saved.info, saved.counted, saved.heard, saved.faction
	if not ok then error(err, 0) end
end)

test("census page: the graphs: 30 days of characters, the scale's ends written on its left, today last and brighter; 24 hours of online from 0; each slot its own tooltip", function()
	WithCensus({ ["Olympus"] = Report(900, { online = 200 }) }, 0, function()
		-- (Noon today: the samples' days and hours whatever the time the test runs.)
		local d = os.date("*t")
		local now = os.time({ year = d.year, month = d.month, day = d.day, hour = 12 })
		local w = World({ realData = true, clock = now - 2 * 86400 })
		w.CS.Sample()
		w.clock = now - 30 * 60
		w.CS.Sample()
		w.clock = now
		local lines = w.CS.Build()
		local _, g = Find(lines, L.CENSUS_STATS_ARMY_GRAPH)
		local army = lines[g + 1].graph
		assert(army, "the army's graph")
		eq(army.n, 30); eq(army.values[30], 900); eq(army.values[28], 900); eq(army.values[29], nil)
		eq(army.left, L.CENSUS_STATS_DAYS_AGO:format(29)); eq(army.right, L.CENSUS_STATS_TODAY)
		assert(army.min < 900 and army.max > 900)
		eq(army.top, ns.FormatNumber(army.max)); eq(army.bottom, ns.FormatNumber(army.min))
		local tip = {}
		local tt = { AddLine = function(_, s) tip[#tip + 1] = s end, AddDoubleLine = function(_, a, b) tip[#tip + 1] = a .. "=" .. b end }
		army.tips[30](tt)
		eq(tip[1], L.CENSUS_STATS_TODAY); eq(tip[2], L.CENSUS_STATS_CHARACTERS .. "=900"); eq(tip[3], L.CENSUS_STATS_PEOPLE .. "=900")
		tip = {}
		army.tips[29](tt)
		eq(tip[2], L.CENSUS_STATS_NO_SAMPLE)
		-- The scale's own tooltip sums the series up (the row takes no mouse).
		eq(lines[g + 1].tooltip, nil); eq(lines[g + 1].onClick, nil)
		tip = {}
		army.tip(tt)
		eq(tip[1], L.CENSUS_STATS_ARMY_GRAPH); eq(tip[2], L.CENSUS_STATS_HIGHEST .. "=" .. L.CENSUS_STATS_WHEN:format("900", L.CENSUS_STATS_TODAY))
		local _, o = Find(lines, L.CENSUS_STATS_ONLINE_GRAPH)
		local online = lines[o + 1].graph
		eq(online.n, 24); eq(online.min, 0); eq(online.values[24], 200); eq(online.right, L.CENSUS_STATS_NOW)
		assert(Find(lines, L.CENSUS_STATS_KEPT:format(os.date(L.CENSUS_STATS_DAY_FORMAT, w.CS.Since()))), "how long it is kept")
	end)
end)

test("census page: a graph row drawn with plain textures: a step line at each value over a faint fill, a dot where none, the last slot brighter, each slot's tooltip on hover, gone when the row shows text again", function()
	WithUI(function()
		local content = CreateFrame("Frame", nil, UIParent)
		content:SetWidth(346)
		content.style = "old"
		local graph = { n = 4, values = { 10, nil, 20, 30 }, min = 0, max = 40, color = { 1, 0.82, 0 },
			top = "40", bottom = "0", left = "first", right = "last",
			tips = { function(tt) tt:AddLine("slot one") end, nil, nil, function(tt) tt:AddLine("slot four") end },
			tip = function(tt) tt:AddLine("the whole series") end }
		V.Render(content, { { text = "Heading", header = true }, { graph = graph } })
		local r = content.rows[2]
		eq(r.h, V.GraphHeight(graph)); eq(V.GraphHeight(graph), V.GRAPH_H + V.GRAPH_AXIS_H + 4)
		eq(V.LinesHeight({ { graph = graph } }, false, 346), 2 + V.GraphHeight(graph) + 8, "measured as drawn")
		local g = r.graph
		assert(g and g:IsShown(), "the graph's holder")
		eq(r.left:IsShown(), false)
		eq(g.top:GetText(), "40"); eq(g.bottom:GetText(), "0"); eq(g.left:GetText(), "first"); eq(g.right:GetText(), "last")
		local plotW = 346 - V.GRAPH_GUTTER - 4
		local s1, s2, s3, s4 = g.slots[1], g.slots[2], g.slots[3], g.slots[4]
		-- Slot one: its fill from the baseline up to a quarter of the plot, its line on top.
		local base = V.GRAPH_AXIS_H
		eq(s1.fill:Anchor("BOTTOMLEFT")[4], V.GRAPH_GUTTER); eq(s1.fill:Anchor("BOTTOMLEFT")[5], base)
		eq(s1.fill.h, V.GRAPH_H / 4); eq(s1.cap.h, 2); eq(s1.cap:Anchor("BOTTOMLEFT")[5], base + V.GRAPH_H / 4 - 1)
		eq(s1.rise:IsShown(), false, "nothing before it")
		-- Slot two has no value: a dot on the baseline, no fill.
		eq(s2.fill:IsShown(), false); eq(s2.cap.w, 2); eq(s2.cap.h, 2); eq(s2.cap:Anchor("BOTTOMLEFT")[5], base)
		eq(s3.rise:IsShown(), false, "no step from a slot with no value")
		-- Slot four: a step up from slot three.
		eq(s4.rise:IsShown(), true); eq(s4.rise.w, 2)
		eq(s4.rise:Anchor("BOTTOMLEFT")[5], base + V.GRAPH_H / 2 - 1); eq(s4.rise.h, V.GRAPH_H / 4 + 2)
		-- Across the plot, slot by slot, nothing past its end.
		local right = s4.hit:Anchor("BOTTOMLEFT")[4] + s4.hit.w
		assert(math.abs(right - (V.GRAPH_GUTTER + plotW)) <= 1, "the last slot ends with the plot: " .. right)
		-- The colours: the last slot brighter than the others, the empty slot's dot grey.
		for _, s in ipairs({ s1, s2, s4 }) do
			for _, t in ipairs({ s.fill, s.cap }) do t.SetVertexColor = function(self, ...) self.vc = { ... } end end
		end
		V.Render(content, { { text = "Heading", header = true }, { graph = graph } })
		assert(s4.cap.vc[4] > s1.cap.vc[4] and s4.fill.vc[4] > s1.fill.vc[4], "the last slot brighter")
		eq(s1.cap.vc[1], 1); eq(s2.cap.vc[1], 0.62, "a grey dot")
		-- A slot's own tooltip; a slot without one takes no mouse.
		GameTooltip.AddDoubleLine = function(self, a, b) self.lines[#self.lines + 1] = a .. "=" .. b end
		s4.hit:Fire("OnEnter")
		eq(GameTooltip.owner, s4.hit); eq(GameTooltip.lines[1], "slot four")
		s2.hit:Fire("OnEnter")
		eq(GameTooltip.owner, s4.hit, "no tooltip for a slot without one")
		-- The scale on the left: the whole series; the row itself takes no mouse.
		eq(g.scale.w, V.GRAPH_GUTTER - 2); eq(g.scale.h, V.GRAPH_H)
		g.scale:Fire("OnEnter")
		eq(GameTooltip.owner, g.scale); eq(GameTooltip.lines[1], "the whole series")
		-- Fewer slots: the rest hide; the same row as text: the graph goes.
		V.Render(content, { { text = "Heading", header = true }, { graph = { n = 2, values = { 1, 2 }, min = 0, max = 2 } } })
		eq(s3.hit:IsShown(), false); eq(s4.cap:IsShown(), false)
		V.Render(content, { { text = "Heading", header = true }, { text = "a line again" } })
		eq(r.graph:IsShown(), false); eq(r.left:IsShown(), true); eq(r.h, 16)
	end)
end)

-- The window opened on the Census with these reports, this module as the game has it (ns.CensusStats).
local function OpenWindow(fn)
	WithUI(function()
		WithCensus({
			["Olympus"] = Report(900, { online = 200, avgLevel = 40 }),
			["Olympus II"] = Report(300, { online = 50 }),
		}, 4, function()
			local w = World({ realData = true, clock = os.time() })
			local saved = ns.CensusStats
			ns.CensusStats = w.CS
			local ok, err = pcall(function()
				local UI = LoadUI()
				UI.Toggle()
				fn(OlympusFrame, UI, w)
			end)
			ns.CensusStats = saved
			if not ok then error(err, 0) end
		end)
	end)
end

test("census header: current-server characters and a smaller all-server total; people remain in the Discord copy", function()
	OpenWindow(function(main, UI)
		eq(main.tab, "census")
		eq(main.total:GetText(), L.ARMY_TOTAL:format("1,200"), "the characters")
		eq(main.people:GetText(), L.CENSUS_HEADER_ALL:format("1,200"), "all-server characters do not subtract linked alts")
		eq(main.people:IsShown(), true)
		eq(main.people.font, "GameFontNormalSmall", "smaller than the characters'"); eq(main.total.font, "GameFontNormalLarge")
		eq(table.concat(main.people.textColor, ","), table.concat(UI.PEOPLE_COLOR, ","), "darker")
		assert(UI.PEOPLE_COLOR[1] < 1 and UI.PEOPLE_COLOR[2] < 0.82, "darker than the gold of the characters")
		-- Right after the characters' words, on their line, inside the window.
		local a = main.people:Anchor("BOTTOMLEFT")
		eq(a[2], main.total); eq(a[4], main.total:GetUnboundedStringWidth() + UI.PEOPLE_GAP)
		assert(main.headerX + a[4] + main.people:GetUnboundedStringWidth() <= main:GetWidth() - 26, "inside the header")
		-- The hover lights it and says a click opens the page.
		main.headerHover:Fire("OnEnter")
		eq(table.concat(main.people.textColor, ","), table.concat(UI.PEOPLE_LIT, ","))
		eq(GameTooltip.lines[#GameTooltip.lines], L.HEADER_TIP_OPEN)
		main.headerHover:Fire("OnLeave")
		eq(table.concat(main.people.textColor, ","), table.concat(UI.PEOPLE_COLOR, ","))
		-- The copy for Discord: the same two counts.
		local copy = ns.Data.DiscordText()
		assert(copy:find(L.DISCORD_HEADER:format("1,200", "250", 2) .. " · " .. L.ARMY_PEOPLE:format("1,196"), 1, true), copy)
		-- The minimap button's tooltip: the same two counts, the people in the same colour.
		eq(UI.PEOPLE_CODE, "|cffb89957")
		Minimap = CreateFrame("Frame", "Minimap", UIParent)
		Minimap:SetSize(140, 140)
		UI.UpdateMinimapButton()
		OlympusMinimapButton:Fire("OnEnter")
		eq(GameTooltip.lines[2], L.ARMY_TOTAL:format("1,200") .. "  " .. UI.PEOPLE_CODE .. L.CENSUS_HEADER_ALL:format("1,200") .. "|r")
		Minimap = nil
		-- On the Join screen (no Olympus guild) the header is the roast's alone.
		GetGuildInfo = function() return nil end
		UI.Refresh()
		eq(main.people:IsShown(), false)
	end)
end)

test("census page: a click on the header's count opens it inside the Census tab from any tab, no column titles, its own page id; Back, the tab or another tab returns to the list; a drag opens nothing", function()
	OpenWindow(function(main, UI, w)
		local CS = w.CS
		eq(main.colHeader:IsShown(), true)
		UI.SelectTab("realm")
		-- A drag of the window from the count opens nothing.
		local hover = main.headerHover
		hover:Fire("OnMouseDown", "LeftButton"); hover:Fire("OnDragStart"); hover:Fire("OnDragStop"); hover:Fire("OnMouseUp", "LeftButton")
		eq(main.tab, "realm"); eq(CS.Shown(), false)
		-- A right click neither.
		hover:Fire("OnMouseDown", "RightButton"); hover:Fire("OnMouseUp", "RightButton")
		eq(CS.Shown(), false)
		-- A click: the Census tab, its own page.
		hover:Fire("OnMouseDown", "LeftButton"); hover:Fire("OnMouseUp", "LeftButton")
		eq(main.tab, "census"); eq(CS.Shown(), true)
		eq(main.colHeader:IsShown(), false, "no column titles over the page")
		eq(UI.PageId(), "census/stats")
		local rows = main.views.census.rows
		eq(Bare(rows[1].left:GetText()), L.CENSUS_STATS_BACK)
		eq(rows[2].left:GetText(), L.CENSUS_STATS_TITLE)
		eq(main.detailTitle:GetText(), L.CENSUS_STATS_DETAIL_TITLE)
		eq(main.people:IsShown(), true, "the count stays in the header")
		-- Back: the list again, its column titles too.
		rows[1]:Click()
		eq(CS.Shown(), false); eq(main.colHeader:IsShown(), true); eq(UI.PageId(), "census/")
		assert(main.views.census.rows[1].line.input, "the Census's search on top again")
		-- The Census tab clicked, or another tab: the list.
		UI.OpenCensusStats()
		eq(CS.Shown(), true)
		UI.SelectTab("census")
		eq(CS.Shown(), false); eq(main.colHeader:IsShown(), true)
		UI.OpenCensusStats()
		UI.SelectTab("realm")
		eq(CS.Shown(), false)
		-- Never from a person page or the Join screen.
		GetGuildInfo = function() return nil end
		UI.Refresh()
		eq(UI.OpenCensusStats(), false); eq(CS.Shown(), false)
	end)
end)

test("census page: a client updated without a restart (no CensusStats.lua yet) keeps the Census list, says to restart on a click, and offers no click in the tooltip", function()
	WithUI(function()
		WithCensus({ ["Olympus"] = Report(900) }, 0, function()
			local saved = ns.CensusStats
			ns.CensusStats = nil
			local printed = {}
			local savedPrint = ns.Print
			ns.Print = function(s) printed[#printed + 1] = s end
			local ok, err = pcall(function()
				local UI = LoadUI()
				UI.Toggle()
				local main = OlympusFrame
				eq(main.people:GetText(), L.CENSUS_HEADER_ALL:format("900"))
				main.headerHover:Fire("OnEnter")
				for _, line in ipairs(GameTooltip.lines) do assert(line ~= L.HEADER_TIP_OPEN, "no click offered") end
				main.headerHover:Fire("OnMouseDown", "LeftButton"); main.headerHover:Fire("OnMouseUp", "LeftButton")
				eq(printed[#printed], L.RESTART_NEEDED)
				eq(main.colHeader:IsShown(), true); eq(UI.PageId(), "census/")
			end)
			ns.CensusStats, ns.Print = saved, savedPrint
			if not ok then error(err, 0) end
		end)
	end)
end)

---------------------------------------------------------------------------
-- (The author, 2026-10-20) The people, estimated: CensusStats.PeopleEstimate, and where it shows. A
-- member's client keeps the plain count in the words above ("about 1,196 people"); a moderation
-- team client (the King's is one) with SAMPLE_MIN validated accounts shows the BattleTag estimate,
-- marked "~", and the staff's figures off the King's stream.
---------------------------------------------------------------------------

-- A census of `characters` characters and `people` people, over a guild counted and one that is
-- out of every total.
local function Census(characters, people)
	return { characters = characters, total = people, online = 0,
		guilds = { { name = "Olympus", counted = true }, { name = "Olympus Gone", counted = false } } }
end

-- World with the samples this client holds, as the modules count them: o.team ({ characters,
-- accounts }: a moderation team client's validated sample, Accord.Sample), o.alts ({ characters,
-- people }: the players who linked alts, Alts.Sample; false: an Alts without Sample). The guilds
-- each sample was asked about: w.asked.
local function Sampled(o)
	local w = World()
	w.asked = {}
	w.ns.Accord = { TeamShown = function() return o.team ~= nil end, Stream = function() return false end,
		Sample = function(counted) w.asked.team = counted return o.team.characters, o.team.accounts end }
	local alts = o.alts or { characters = 0, people = 0 }
	w.ns.Alts = o.alts == false and {} or { Sample = function(counted) w.asked.alts = counted return alts.characters, alts.people end }
	return w
end

test("census people estimate: on a moderation team client, the validated sample: its accounts, then the characters not yet validated at its characters per account, to three significant figures; only the guilds counted asked", function()
	local w = Sampled({ team = { characters = 960, accounts = 800 }, alts = { characters = 250, people = 100 } })
	local e = w.CS.PeopleEstimate(Census(10000, 9850))
	eq(e.approx, true); eq(e.sample.kind, "battletag")
	eq(e.sample.size, 800); eq(e.sample.characters, 960); eq(e.rate, 1.2)
	-- 800 + 9,040 / 1.2 = 8,333.3: 8,330.
	eq(e.estimate, 8330); eq(e.shown, 8330); eq(e.people, 9850, "the plain count kept beside it")
	eq(e.staff, true); eq(e.validated, 800); eq(e.validatedCharacters, 960); eq(e.unvalidated, 9040)
	eq(w.asked.team.olympus, true); eq(w.asked.team["olympus gone"], nil, "a guild out of the total is not in the sample")
	eq(w.CS.PeopleText(Census(10000, 9850)), L.ARMY_PEOPLE_APPROX:format("8,330"))
	eq(w.CS.StaffLine(e), L.PEOPLE_STAFF_TAGS:format("800", "1.20", "9,040"))
	local notes = w.CS.PeopleNotes(Census(10000, 9850))
	eq(notes[1], L.PEOPLE_ESTIMATE_TIP, "what ~ means"); eq(notes[2], L.PEOPLE_STAFF_TAGS:format("800", "1.20", "9,040")); eq(#notes, 2)
	eq(w.CS.DetailText(e), L.CENSUS_STATS_DETAIL_TAGS)
end)

test("census people estimate: a member's client, or a team client under SAMPLE_MIN validated accounts, keeps the plain count in the members' words, never an alt-link rate; the staff told why; an empty census: nothing", function()
	local w = Sampled({ alts = { characters = 250, people = 100 } })
	local e = w.CS.PeopleEstimate(Census(10000, 9850))
	eq(e.approx, false); eq(e.shown, 9850, "the count, not 10,000 / 2.5"); eq(e.estimate, nil)
	eq(e.rate, nil, "no rate"); eq(e.sample, nil, "no sample")
	eq(e.staff, nil, "no staff figures off the team"); eq(e.validated, nil); eq(e.unvalidated, nil)
	eq(w.asked.alts, nil, "the alt links are not even asked on a member's client")
	eq(w.CS.StaffLine(e), nil)
	eq(w.CS.PeopleText(Census(10000, 9850)), L.ARMY_PEOPLE:format("9,850"), "the members' words, as before")
	eq(#w.CS.PeopleNotes(Census(10000, 9850)), 0, "nothing to say about a ~ that is not there")
	eq(w.CS.DetailText(e), L.CENSUS_STATS_DETAIL, "the members' formula")
	-- No Alts.Sample (a client updated without a restart): the same.
	e = Sampled({ alts = false }).CS.PeopleEstimate(Census(10000, 9850))
	eq(e.approx, false); eq(e.shown, 9850)
	-- A team client whose validated sample is too small: the count as members see it; its staff
	-- figures stay, and say the estimate needs more validated accounts.
	w = Sampled({ team = { characters = 6, accounts = 5 }, alts = { characters = 250, people = 100 } })
	e = w.CS.PeopleEstimate(Census(10000, 9850))
	eq(e.approx, false); eq(e.shown, 9850); eq(e.rate, nil); eq(e.sample, nil)
	eq(e.staff, true); eq(e.validated, 5); eq(e.unvalidated, 9994)
	eq(w.CS.PeopleText(Census(10000, 9850)), L.ARMY_PEOPLE:format("9,850"))
	eq(w.CS.StaffLine(e), L.PEOPLE_STAFF_NONE:format("5", "9,994", tostring(w.CS.SAMPLE_MIN)))
	eq(w.CS.PeopleNotes(Census(10000, 9850))[1], L.PEOPLE_STAFF_NONE:format("5", "9,994", tostring(w.CS.SAMPLE_MIN)))
	-- An empty census, even on a team client with a big sample.
	e = Sampled({ team = { characters = 960, accounts = 800 } }).CS.PeopleEstimate(Census(0, 0))
	eq(e.approx, false); eq(e.shown, 0)
end)

-- The review's census, and the regression the members-plain decision fixed: from the alt-link rate a
-- member saw ~480 where a team client saw ~960 for the same census.
test("census people estimate: the same census, a member's plain count and never the alt-link rate's half; a team client with SAMPLE_MIN validated accounts takes the BattleTag rate, one fewer the plain count", function()
	-- 1,200 characters, 1,196 people as counted, 100 players linked 250 characters.
	local member = Sampled({ alts = { characters = 250, people = 100 } })
	local e = member.CS.PeopleEstimate(Census(1200, 1196))
	eq(e.shown, 1196); eq(e.approx, false); eq(member.CS.PeopleText(Census(1200, 1196)), L.ARMY_PEOPLE:format("1,196"))
	assert(e.shown ~= 480, "the alt-link rate's 1,200 / 2.5")
	-- A team client with 24 validated accounts of 30 characters: 24 + 1,170 / 1.25 = 960, the alt
	-- links beside it changing nothing.
	local team = Sampled({ team = { characters = 30, accounts = 24 }, alts = { characters = 250, people = 100 } })
	e = team.CS.PeopleEstimate(Census(1200, 1196))
	eq(e.shown, 960); eq(e.approx, true); eq(e.rate, 1.25); eq(e.sample.kind, "battletag"); eq(e.sample.size, 24)
	eq(team.CS.PeopleText(Census(1200, 1196)), L.ARMY_PEOPLE_APPROX:format("960"))
	-- One validated account fewer than SAMPLE_MIN: the count as members see it.
	team = Sampled({ team = { characters = 30, accounts = team.CS.SAMPLE_MIN - 1 }, alts = { characters = 250, people = 100 } })
	e = team.CS.PeopleEstimate(Census(1200, 1196))
	eq(e.shown, 1196); eq(e.approx, false); eq(e.rate, nil)
	team = Sampled({ team = { characters = 30, accounts = team.CS.SAMPLE_MIN } })
	eq(team.CS.PeopleEstimate(Census(1200, 1196)).approx, true, "SAMPLE_MIN itself is enough")
end)

test("census people estimate: three significant figures; never more than the plain count (nor the characters), never fewer than the players the samples tell apart", function()
	local CS = World().CS
	for _, c in ipairs({ { 8333.3, 8330 }, { 80544, 80500 }, { 123456, 123000 }, { 999.6, 1000 }, { 99950, 100000 }, { 47.4, 47 }, { 0, 0 } }) do
		eq((CS.Round3(c[1])), c[2], tostring(c[1]))
	end
	-- Every validated account one character: the rate 1 would make every character a player; the plain count is the most.
	local w = Sampled({ team = { characters = 100, accounts = 100 } })
	eq(w.CS.PeopleEstimate(Census(10000, 9850)).estimate, 9850)
	-- Rounded above it (9,849 to 9,850): down to the step under it.
	eq(w.CS.PeopleEstimate(Census(10000, 9849)).estimate, 9840)
	-- A census whose people say more than its characters: the characters are the most.
	eq(w.CS.PeopleEstimate(Census(1000, 1200)).estimate, 1000)
	-- The team's rate (10 characters per account) gives 20 + 800 / 10 = 100, but 300 players linked
	-- alts here: at least 300.
	w = Sampled({ team = { characters = 200, accounts = 20 }, alts = { characters = 600, people = 300 } })
	local e = w.CS.PeopleEstimate(Census(1000, 1000))
	eq(e.sample.kind, "battletag"); eq(e.estimate, 300)
	eq(w.asked.alts.olympus, true); eq(w.asked.alts["olympus gone"], nil, "the floor asks the guilds counted alone")
	-- A sample bigger than the census (rows of guilds since grown smaller) never counts past it.
	w = Sampled({ team = { characters = 5000, accounts = 4000 } })
	e = w.CS.PeopleEstimate(Census(1000, 1000))
	eq(e.validatedCharacters, 1000); eq(e.unvalidated, 0); assert(e.estimate <= 1000 and e.estimate >= e.validated, e.estimate)
end)

test("census people estimate: Alts.Sample counts the players whose confirmed links have a character in the guilds counted, and those characters; a link one side claims counts nothing", function()
	local A = ns.Alts -- (the real Alts.lua: the harness loads it before these files)
	local saved = { claims = ns.rdb.altClaims, alts = ns.db.alts }
	local ok, err = pcall(function()
		ns.db.alts, ns.rdb.altClaims = nil, nil
		A.Reset()
		local function AL(sender, role, guild, names) A.Handle("CHANNEL", sender, ("AL~1~%s~%s~%s"):format(role, guild, names)) end
		AL("Main One-Realm", "M", "Olympus", "Alt One,Alt Two")
		AL("Alt One-Realm", "A", "Olympus", "Main One")
		AL("Alt Two-Realm", "A", "Olympus Far", "Main One")
		AL("Main Two-Realm", "M", "Olympus Far", "Alt Three")
		AL("Alt Three-Realm", "A", "Olympus", "Main Two")
		AL("Main Three-Realm", "M", "Olympus", "Alt Four") -- (Alt Four never says so)
		local c, p = A.Sample({ olympus = true })
		eq(c, 3, "Main One, Alt One and Alt Three"); eq(p, 2)
		c, p = A.Sample({ olympus = true, ["olympus far"] = true })
		eq(c, 5); eq(p, 2)
		c, p = A.Sample({})
		eq(c, 0); eq(p, 0)
	end)
	ns.db.alts, ns.rdb.altClaims = saved.alts, saved.claims
	A.Reset()
	if not ok then error(err, 0) end
end)

-- fn with the harness's real census over these reports (WithCensus, o.dups linked alts), the
-- players who linked alts as o.alts says ({ characters, people }, Alts.Sample), and the real
-- Accord.lua's BattleTag store holding o.rows, this client on the moderation team while o.team
-- (Accord.TeamShown) and on the King's stream while o.stream (Accord.Stream), as they are when asked.
local function WithSamples(guilds, o, fn)
	local A = ns.Accord
	local saved = { tags = ns.rdb.battletags, team = A.TeamShown, stream = A.Stream, sample = ns.Alts.Sample }
	ns.rdb.battletags = o.rows and { v = 1, rows = o.rows } or nil
	A.TeamShown = function() return o.team == true end
	A.Stream = function() return o.stream == true end
	local ok, err = pcall(WithCensus, guilds, o.dups or 0, function()
		ns.Alts.Sample = function()
			local a = o.alts or { characters = 0, people = 0 }
			return a.characters, a.people
		end
		fn()
	end)
	ns.rdb.battletags, A.TeamShown, A.Stream, ns.Alts.Sample = saved.tags, saved.team, saved.stream, saved.sample
	if not ok then error(err, 0) end
end
-- BattleTag rows as a team client keeps them: `accounts` players in `guild`, the first `seconds`
-- of them with a second character, and two rows of a guild out of the census.
local function TagRows(accounts, seconds, guild)
	local rows = {}
	for i = 1, accounts do
		local tag = ("Hidden%d#%d"):format(i, 1000 + i)
		rows[("hidden%d-realm"):format(i)] = { name = ("Hidden%d-Realm"):format(i), tag = tag, guild = guild or "Olympus", last = os.time() }
		if i <= seconds then rows[("second%d-realm"):format(i)] = { name = ("Second%d-Realm"):format(i), tag = tag, guild = guild or "Olympus", last = os.time() } end
	end
	rows["far1-realm"] = { name = "Far1-Realm", tag = "Faraway#4242", guild = "Olympus Far", last = os.time() }
	rows["far2-realm"] = { name = "Far2-Realm", tag = "Faraway#4243", guild = "Olympus Far", last = os.time() }
	return rows
end
-- Every word a list of lines shows: text, right side and tooltip.
local function Said(lines)
	local out = {}
	local tt = { AddLine = function(_, s) out[#out + 1] = tostring(s) end, AddDoubleLine = function(_, a, b) out[#out + 1] = tostring(a) .. "=" .. tostring(b) end }
	for _, line in ipairs(lines) do
		out[#out + 1] = tostring(line.text or "") .. " | " .. tostring(line.right or "")
		if type(line.tooltip) == "function" then line.tooltip(tt) end
	end
	return table.concat(out, "\n")
end
local function Tip(line)
	local out = {}
	line.tooltip({ AddLine = function(_, s) out[#out + 1] = s end })
	return out
end
local function NoTagOrName(text, where)
	for _, bit in ipairs({ "#", "Hidden", "Second1", "Faraway", "Far1" }) do
		assert(not text:find(bit, 1, true), (where or "") .. ": " .. bit .. " in\n" .. text)
	end
end
local ESTIMATE_GUILDS = function()
	return { ["Olympus"] = Report(900, { online = 200, avgLevel = 40 }), ["Olympus II"] = Report(300, { online = 50 }) }
end

test("census page: a member's people as before; a team client's ~ estimate, its tooltip and detail saying how it is made, the staff's validated accounts, characters not yet validated and rate under it, never on the King's stream; no BattleTag or name anywhere", function()
	-- 1,200 characters, 4 linked alts: 1,196 people as counted.
	local o = { dups = 4, alts = { characters = 250, people = 100 } }
	WithSamples(ESTIMATE_GUILDS(), o, function()
		local w = World({ realData = true, clock = os.time() })
		-- An ordinary member: the plain count, the members' words, nothing of the staff's.
		local lines, _, detail = w.CS.Build()
		local row = Find(lines, L.CENSUS_STATS_PEOPLE)
		eq(Bare(row.right), "1,196")
		eq(Tip(row)[2], L.CENSUS_STATS_PEOPLE_TIP); eq(#Tip(row), 2)
		eq(Tip(Find(lines, L.CENSUS_STATS_ALTS))[2], L.CENSUS_STATS_ALTS_TIP)
		eq(detail, L.CENSUS_STATS_DETAIL)
		local all = Said(lines)
		assert(not all:find(L.PEOPLE_ESTIMATE_TIP, 1, true), "no ~ to explain:\n" .. all)
		eq(Find(lines, L.CENSUS_STATS_VALIDATED), nil); eq(Find(lines, L.CENSUS_STATS_UNVALIDATED), nil); eq(Find(lines, L.CENSUS_STATS_RATE), nil)
		eq(Find(lines, L.CENSUS_STATS_TAG_EXTRAS), nil, "a member sees no private sample")
		assert(not all:find("Staff", 1, true), "nothing the staff alone see:\n" .. all)
		-- A moderation team client: 24 validated accounts of 30 characters in the guilds counted (the
		-- two rows of a guild out of the census aside): 24 + 1,170 / 1.25 = 960.
		ns.rdb.battletags = { v = 1, rows = TagRows(24, 6) }
		o.team = true
		lines, _, detail = w.CS.Build()
		row = Find(lines, L.CENSUS_STATS_PEOPLE)
		eq(Bare(row.right), L.CENSUS_STATS_APPROX:format("960"))
		eq(detail, L.CENSUS_STATS_DETAIL_TAGS, "the page's detail says how the ~ is made")
		local staff = L.PEOPLE_STAFF_TAGS:format("24", "1.25", "1,170")
		-- (The review of 2026-10-20: beside the ~, what it means takes the place of the plain count's
		-- words, and the linked alts' row has words of its own.)
		local tip = Tip(row)
		eq(tip[2], L.PEOPLE_ESTIMATE_TIP); eq(tip[3], staff); eq(#tip, 3)
		eq(Tip(Find(lines, L.CENSUS_STATS_ALTS))[2], L.CENSUS_STATS_ALTS_TIP)
		assert(not Said(lines):find(L.CENSUS_STATS_PEOPLE_TIP, 1, true), "the plain count's words, beside an estimate")
		local validated, at = Find(lines, L.CENSUS_STATS_VALIDATED)
		eq(Bare(validated.right), "24"); eq(validated.indent, 1)
		eq(Bare(lines[at + 1].text), L.CENSUS_STATS_UNVALIDATED); eq(Bare(lines[at + 1].right), "1,170")
		eq(Bare(lines[at + 2].text), L.CENSUS_STATS_RATE); eq(Bare(lines[at + 2].right), "1.25 " .. L.CENSUS_STATS_RATE_TAGS:format("24"))
		eq(Tip(validated)[2], staff)
		local extras = assert(Find(lines, L.CENSUS_STATS_TAG_EXTRAS))
		eq(Bare(extras.right), "6", "additional characters in the scoped private sample")
		eq(Tip(extras)[2], L.CENSUS_STATS_TAG_EXTRAS_TIP)
		eq(Bare(Find(lines, L.CENSUS_STATS_ALTS).right), "4", "explicitly linked alts remain separate")
		NoTagOrName(Said(lines), "the team's page")
		-- The King's stream: the estimate, nothing of the staff's.
		o.stream = true
		lines = w.CS.Build()
		eq(Bare(Find(lines, L.CENSUS_STATS_PEOPLE).right), L.CENSUS_STATS_APPROX:format("960"))
		eq(Find(lines, L.CENSUS_STATS_VALIDATED), nil); eq(#Tip(Find(lines, L.CENSUS_STATS_PEOPLE)), 2)
		eq(Find(lines, L.CENSUS_STATS_TAG_EXTRAS), nil, "the private sample is hidden on stream")
		o.stream = false
		-- Too few validated accounts: the count as members see it, in their words; the staff told why.
		ns.rdb.battletags = { v = 1, rows = TagRows(3, 0) }
		lines, _, detail = w.CS.Build()
		row = Find(lines, L.CENSUS_STATS_PEOPLE)
		eq(Bare(row.right), "1,196"); eq(detail, L.CENSUS_STATS_DETAIL)
		eq(Bare(Find(lines, L.CENSUS_STATS_RATE).right), "-")
		eq(Find(lines, L.CENSUS_STATS_TAG_EXTRAS), nil, "the private sample needs the minimum account count")
		tip = Tip(row)
		eq(tip[2], L.CENSUS_STATS_PEOPLE_TIP); eq(tip[3], L.PEOPLE_STAFF_NONE:format("3", "1,197", tostring(w.CS.SAMPLE_MIN))); eq(#tip, 3)
		eq(Tip(Find(lines, L.CENSUS_STATS_ALTS))[2], L.CENSUS_STATS_ALTS_TIP)
	end)
end)

-- Every word the page's graphs show on hover: each slot's tooltip and the series' own.
local function GraphSaid(lines)
	local out = {}
	local tt = { AddLine = function(_, s) out[#out + 1] = tostring(s) end, AddDoubleLine = function(_, a, b) out[#out + 1] = tostring(a) .. "=" .. tostring(b) end }
	for _, line in ipairs(lines) do
		local g = line.graph
		if g then
			for i = 1, g.n do if g.tips[i] then g.tips[i](tt) end end
			if g.tip then g.tip(tt) end
		end
	end
	return table.concat(out, "\n")
end

-- (The review of 2026-10-20: the header and the people's row said "~" while each graph's day and
-- hour still said the plain count.)
test("census page: the graphs' days and hours give the people as the header does: a team client's at the estimate's people per character, never above the sample's count; a member's each sample's own count", function()
	local o = { dups = 4, alts = { characters = 250, people = 100 } }
	WithSamples(ESTIMATE_GUILDS(), o, function()
		local d = os.date("*t")
		local now = os.time({ year = d.year, month = d.month, day = d.day, hour = 12 })
		local w = World({ realData = true, clock = now - 30 * 60 })
		eq(w.CS.Sample(), true, "a sample: 1,200 characters, 1,196 people")
		w.clock = now
		local function Tips(lines, title, slot)
			local _, g = Find(lines, title)
			local out = {}
			lines[g + 1].graph.tips[slot]({ AddLine = function(_, s) out[#out + 1] = s end, AddDoubleLine = function(_, a, b) out[#out + 1] = a .. "=" .. b end })
			return table.concat(out, "\n")
		end
		-- An ordinary member: the sample's 1,196, today and in the last hour, as his header.
		local lines = w.CS.Build()
		assert(Tips(lines, L.CENSUS_STATS_ARMY_GRAPH, 30):find(L.CENSUS_STATS_PEOPLE .. "=1,196", 1, true))
		assert(Tips(lines, L.CENSUS_STATS_ONLINE_GRAPH, 24):find(L.CENSUS_STATS_PEOPLE .. "=1,196", 1, true))
		local all = GraphSaid(lines)
		assert(not all:find("480", 1, true), "the alt-link rate's:\n" .. all)
		assert(all:find(L.CENSUS_STATS_DETAIL, 1, true), "the members' detail under each graph:\n" .. all)
		-- A moderation team client: 960, the same in the graphs; no tag or name there either.
		ns.rdb.battletags = { v = 1, rows = TagRows(24, 6) }
		o.team = true
		lines = w.CS.Build()
		assert(Tips(lines, L.CENSUS_STATS_ARMY_GRAPH, 30):find(L.CENSUS_STATS_PEOPLE .. "=" .. L.CENSUS_STATS_APPROX:format("960"), 1, true))
		assert(Tips(lines, L.CENSUS_STATS_ONLINE_GRAPH, 24):find(L.CENSUS_STATS_PEOPLE .. "=" .. L.CENSUS_STATS_APPROX:format("960"), 1, true))
		all = Said(lines) .. "\n" .. GraphSaid(lines)
		-- The graphs use the staff estimate; the cross-server section deliberately retains
		-- each origin's own linked-alt count, without applying this client's staff sample.
		assert(not GraphSaid(lines):find("1,196", 1, true), GraphSaid(lines))
		assert(not all:find(L.CENSUS_STATS_DETAIL, 1, true) and all:find(L.CENSUS_STATS_DETAIL_TAGS, 1, true), "the estimate's detail:\n" .. all)
		NoTagOrName(GraphSaid(lines), "the team's graphs")
	end)
	-- The arithmetic: with the BattleTag rate, the estimate's people per character, three significant
	-- figures, never above the sample's own count (rounded above it: the step under it); no estimate
	-- (or one without a rate): the plain count.
	local CS = World().CS
	local e = { approx = true, shown = 960, characters = 1200, rate = 1.25 }
	eq(CS.PeopleAt(1196, 1200, e), L.CENSUS_STATS_APPROX:format("960"))
	eq(CS.PeopleAt(1000, 1100, e), L.CENSUS_STATS_APPROX:format("880"))
	eq(CS.PeopleAt(9849, 10000, { approx = true, shown = 9850, characters = 10000, rate = 1 }), L.CENSUS_STATS_APPROX:format("9,840"))
	eq(CS.PeopleAt(50, 1000, { approx = true, shown = 900, characters = 1000, rate = 1.1 }), L.CENSUS_STATS_APPROX:format("50"), "never above its own count")
	eq(CS.PeopleAt(1196, 1200, { approx = true, shown = 1196, characters = 1200 }), "1,196", "no rate: the plain count")
	eq(CS.PeopleAt(990, 1000, { approx = false, shown = 990, characters = 1000 }), "990")
	eq(CS.PeopleAt(990, 1000, nil), "990")
end)

-- The window opened on the Census over ESTIMATE_GUILDS with these samples (WithSamples).
local function OpenSampled(o, fn)
	WithUI(function()
		WithSamples(ESTIMATE_GUILDS(), o, function()
			local w = World({ realData = true, clock = os.time() })
			local saved = ns.CensusStats
			ns.CensusStats = w.CS
			local ok, err = pcall(function()
				local UI = LoadUI()
				UI.Toggle()
				fn(OlympusFrame, UI, w)
			end)
			ns.CensusStats = saved
			if not ok then error(err, 0) end
		end)
	end)
end

test("census header: role changes do not put people estimates in the headline; internal people calculations and Discord stay intact", function()
	local o = { dups = 4, alts = { characters = 250, people = 100 } }
	OpenSampled(o, function(main, UI)
		local function CheckHeader()
			eq(main.people:GetText(), L.CENSUS_HEADER_ALL:format("1,200"))
			main.headerHover:Fire("OnEnter")
			local scope
			for _, line in ipairs(GameTooltip.lines) do
				if line == L.CENSUS_HEADER_ALL_TIP then scope = true end
				assert(line ~= L.PEOPLE_ESTIMATE_TIP, "people estimates belong inside the detail page")
				assert(not tostring(line):find("Staff", 1, true), "the header exposes no staff estimate")
			end
			assert(scope, "the hover explains the two census scopes")
			main.headerHover:Fire("OnLeave")
			Minimap = CreateFrame("Frame", "Minimap", UIParent)
			Minimap:SetSize(140, 140)
			UI.UpdateMinimapButton()
			OlympusMinimapButton:Fire("OnEnter")
			eq(GameTooltip.lines[2], L.ARMY_TOTAL:format("1,200") .. "  " .. UI.PEOPLE_CODE .. L.CENSUS_HEADER_ALL:format("1,200") .. "|r")
			Minimap = nil
		end
		CheckHeader()
		assert(ns.Data.DiscordText():find(" · " .. L.ARMY_PEOPLE:format("1,196"), 1, true))
		ns.rdb.battletags = { v = 1, rows = TagRows(24, 6) }
		o.team = true
		UI.Refresh()
		CheckHeader()
		assert(ns.Data.DiscordText():find(" · " .. L.ARMY_PEOPLE_APPROX:format("960"), 1, true))
		NoTagOrName(main.people:GetText() .. "\n" .. ns.Data.DiscordText(), "the header and Discord copy")
		o.stream = true
		UI.Refresh()
		CheckHeader()
		o.stream, o.team = false, false
		UI.Refresh()
		CheckHeader()
	end)
end)

test("census people estimate: its words in English and Portuguese: the sign, how a team client's estimate is made and that the more players use the Olympus addon and the Olympus Companion, the more precise it gets; the staff's lines; the members' words unchanged", function()
	local function Words(locale)
		local savedLocale = GetLocale
		GetLocale = function() return locale end
		local w = { L = setmetatable({}, { __index = function(_, k) return k end }) }
		local ok, err = pcall(function() assert(loadfile(ROOT .. "Olympus/Locales/CensusStatsText.lua"))("Olympus", w) end)
		GetLocale = savedLocale
		if not ok then error(err, 0) end
		return w.L
	end
	local en, pt = Words("enUS"), Words("ptBR")
	eq(en.ARMY_PEOPLE_APPROX:format("80,500"), "~80,500 people"); eq(pt.ARMY_PEOPLE_APPROX:format("80.500"), "~80.500 pessoas")
	eq(en.CENSUS_STATS_APPROX:format("480"), "~480")
	eq(en.ARMY_PEOPLE:format("80,500"), "about 80,500 people", "the members' words, as before")
	assert(en.PEOPLE_ESTIMATE_TIP:find("estimate", 1, true) and en.PEOPLE_ESTIMATE_TIP:find("BattleTags", 1, true), en.PEOPLE_ESTIMATE_TIP)
	assert(en.PEOPLE_ESTIMATE_TIP:find("The more players use the Olympus addon and the Olympus Companion, the more precise this number gets.", 1, true))
	assert(pt.PEOPLE_ESTIMATE_TIP:find("estimativa", 1, true) and pt.PEOPLE_ESTIMATE_TIP:find("BattleTags", 1, true), pt.PEOPLE_ESTIMATE_TIP)
	assert(pt.PEOPLE_ESTIMATE_TIP:find("Quanto mais jogadores usarem o addon Olympus e o Olympus Companion, mais preciso fica este número.", 1, true))
	-- A member's number has no rate behind it, and the tip says so.
	assert(en.PEOPLE_ESTIMATE_TIP:find("Members see the characters minus the confirmed linked alts", 1, true), en.PEOPLE_ESTIMATE_TIP)
	assert(pt.PEOPLE_ESTIMATE_TIP:find("Os membros veem os personagens menos os alts ligados e confirmados", 1, true), pt.PEOPLE_ESTIMATE_TIP)
	assert(en.CENSUS_STATS_DETAIL_TAGS:find("People (~) = validated accounts", 1, true), en.CENSUS_STATS_DETAIL_TAGS)
	assert(pt.CENSUS_STATS_DETAIL_TAGS:find("Pessoas (~) = contas validadas", 1, true), pt.CENSUS_STATS_DETAIL_TAGS)
	eq(en.PEOPLE_STAFF_ALTS, "PEOPLE_STAFF_ALTS", "no staff line of an alt-link rate"); eq(pt.PEOPLE_STAFF_ALTS, "PEOPLE_STAFF_ALTS")
	eq(pt.PEOPLE_STAFF_TAGS:format("800", "1,20", "9.040"), "Staff: 800 contas validadas, 1,20 personagens por conta; 9.040 personagens ainda não validados.")
	eq(en.PEOPLE_STAFF_TAGS:format("800", "1.20", "9,040"), "Staff: 800 accounts validated, 1.20 characters per account; 9,040 characters not yet validated.")
	-- The linked alts' row beside an estimate: what a link does, not how the plain count goes.
	assert(en.CENSUS_STATS_ALTS_TIP:find("/oly alts", 1, true) and pt.CENSUS_STATS_ALTS_TIP:find("/oly alts", 1, true))
	assert(en.CENSUS_STATS_ALTS_TIP ~= pt.CENSUS_STATS_ALTS_TIP)
	-- Not a word of "not counted": the words say what is shown, never what is missing.
	for _, key in ipairs({ "ARMY_PEOPLE_APPROX", "CENSUS_STATS_APPROX", "PEOPLE_ESTIMATE_TIP" }) do
		assert(not en[key]:lower():find("not counted", 1, true) and not pt[key]:lower():find("não contad", 1, true), key)
	end
	-- The rate in each language's own decimal mark.
	local w = World()
	eq(w.CS.Rate(1.25), "1.25"); eq(w.CS.Rate(2), "2.00"); eq(w.CS.Rate(1.006), "1.01")
	local savedMark = L.DECIMAL_MARK
	L.DECIMAL_MARK = ","
	local ok, err = pcall(function() eq(w.CS.Rate(1.25), "1,25") end)
	L.DECIMAL_MARK = savedMark
	if not ok then error(err, 0) end
end)

test("census page: every line in English and Portuguese, the Portuguese its own", function()
	local pt = {}
	local savedLocale = GetLocale
	GetLocale = function() return "ptBR" end
	local ok, err = pcall(function()
		pt.L = setmetatable({}, { __index = function(_, k) return k end })
		assert(loadfile(ROOT .. "Olympus/Locales/CensusStatsText.lua"))("Olympus", pt)
	end)
	GetLocale = savedLocale
	if not ok then error(err, 0) end
	local en = {}
	en.L = setmetatable({}, { __index = function(_, k) return k end })
	assert(loadfile(ROOT .. "Olympus/Locales/CensusStatsText.lua"))("Olympus", en)
	-- (1.4.0: the ~ of an estimate and the rulesets' names are the same words in both; a team client's
	-- estimate adds CENSUS_STATS_APPROX, "~" and a number, the same in every language.)
	local same = { CENSUS_STATS_TIME_FORMAT = true, CENSUS_STATS_WHEN = true, CENSUS_STATS_OF_CAP = true, CENSUS_STATS_APPROX = true,
		CENSUS_STATS_KIND_PVP = true, CENSUS_STATS_KIND_PVE = true, CENSUS_STATS_KIND_RPPVP = true, CENSUS_STATS_KIND_RP = true, CENSUS_STATS_KIND_HARDCORE = true }
	local n = 0
	for key, text in pairs(en.L) do
		n = n + 1
		assert(type(rawget(pt.L, key)) == "string", "Portuguese " .. key)
		if not same[key] then assert(pt.L[key] ~= text, "Portuguese of its own: " .. key) end
		local function Codes(s) local c = {} for spec in s:gsub("%%%%", ""):gmatch("%%%a") do c[#c + 1] = spec end return table.concat(c) end
		if key ~= "CENSUS_STATS_DAY_FORMAT" then eq(Codes(pt.L[key]), Codes(text), key .. ": the same format codes") end
	end
	assert(n >= 40, "lines: " .. n)
	eq(pt.L.ARMY_PEOPLE:format("80.544"), "aprox. 80.544 pessoas")
	eq(pt.L.CENSUS_STATS_TITLE, "O censo em números")
	assert(pt.L.CENSUS_STATS_PEOPLE:find("estimativa", 1, true))
	assert(pt.L.CENSUS_STATS_DETAIL:find("personagens contados - alts ligados", 1, true))
end)

---------------------------------------------------------------------------
-- (The author, 2026-10-20: "quero explicacao de como dados funcionam, quebrados em topicos ... depois
-- dos graficos", the same words as the Companion's page.) How the census works: the page's last
-- section, CensusStats.HowTopics and HowLines. These are the words the Companion copies.
-- (The author, 2026-10-20, then: "que o processo de sanitização fosse bem estruturado, como por um
-- profissional data analyst, e explicado na página como funciona: info/records mais recentes no
-- jogo por cima de base sólida com data e hora e regras de como funciona": a first topic, how the
-- census is built, and the sanitizing as the numbered rules S1 to S5; tests/census-clean.lua checks
-- the behaviour behind each.)
---------------------------------------------------------------------------

local HOW_EN = {
	{ "How the census is built", {
		"The census is each guild's latest record on top of what was known before. Every report and relay keeps the time it was observed (the server's clock where the game gives it).",
		"A newer report replaces the older one, guild by guild, unless the guild's other reporters outvote it while the older one is under 15 minutes old. A keeper's relay keeps the time its record was first observed and never replaces a record observed after it, so passing a record on never makes it newer.",
	} },
	{ "Where the numbers come from", {
		"In each Olympus guild, the addon of one member reads the guild's roster and reports its size on Olympus's channel every few minutes; a second member's addon, when one is on, reports it less often.",
		"Every player's addon keeps those reports: the census is each guild's latest report. Nothing comes from Blizzard's servers directly.",
	} },
	{ "Validated data", {
		"A guild's size is confirmed when it comes from your own guild's roster or, while its last report is under 15 minutes old, when two or more recent reporters voted on the guild without a dispute (S4) or a trusted keeper (Church keepers, the King, the High Council) relays it.",
	} },
	{ "Estimates", {
		"People are the characters minus the confirmed linked alts known here: an alt nobody linked, or whose two confirmations have not reached this client, counts as one more person, so the number can be high and fall as confirmations arrive.",
		"On a moderation team's client with at least 20 validated BattleTags, people are an estimate (~): the validated accounts, plus the characters not yet validated at their characters per account.",
		"That estimate is rounded to three significant figures and never falls below the players the samples count or rises above the plain count.",
		"The more players use the Olympus addon and the Olympus Companion, the more precise this number gets.",
		"Online counts only reports from the last 15 minutes. A guild keeps its last size for 24 hours after its last report.",
		"The graphs are this client's own samples: one every 15 minutes while you play (kept 48 hours) and each day's highest (kept 30 days).",
	} },
	{ "Sanitized data", {
		"The sanitized census leaves out guilds the moderators took off the network (banned) and guilds not heard for 24 hours (departed), and lists both apart.",
		"A size that jumped further than a guild can change is held at its last good size until it is confirmed or comes within reach (S5).",
	} },
	{ "How validation works", {
		"Each report is its sender's vote on the guild's leader and officers.",
		"When the reporters split, a report is outvoted, or two sizes are further apart than 5 members or 5% (whichever is larger, plus 20 members a minute between the two reports), the guild is marked disputed.",
		"Disputed and single-reporter guilds still count, marked as such.",
	} },
	{ "How sanitizing works", {
		"Sanitizing runs as numbered rules: S1 at the door, the others on what this client keeps. Past the door no rule changes what a guild reported: each keeps a value out of a total, holds it at its last good value or marks it, and records why.",
		"S1 Valid record: A report must parse, name an Olympus guild, carry a size of at most 1,000 (the game's cap), and count no more players by zone, class or level than it has online; an online count above its size is cut to its size. A keeper's relayed row must also have no more online than members and not be dated more than 5 minutes ahead. What fails is refused at the door: it never enters the census.",
		"S2 Recency: Online counts only reports from the last 15 minutes: an older report is stale and leaves \"now\". A guild keeps its last size for 24 hours after its last report; after that it has departed: it leaves every total and is listed apart. It is forgotten 7 days after its last report.",
		"S3 Exclusions: Guilds the moderators took off the network (banned) are in no total and their new reports are refused; they are listed apart with their last size, when this client holds one. Guilds only seen with /who (this client holds no report or relay of theirs) are in no total either; they are listed apart with the players /who saw online.",
		"S4 Agreement: A size from your own guild's roster is confirmed. Any other guild's size, while its last report is under 15 minutes old, is confirmed when a trusted keeper relays it, or when two or more reporters voted on the guild in the last 30 minutes and no dispute is marked (How validation works); single when only one did, and disputed when a dispute is marked; older, it is stale. All count; each guild carries its confidence.",
		"S5 Impossible jump: A size more than 25 members or 10% away from the guild's last good size (whichever is larger, plus 20 a minute since that size) and not confirmed (single, disputed or stale: S4) is further than a guild can move. It is held at the last good size until it is confirmed, until the minutes since bring it within reach, or until the same size holds for an hour.",
	} },
}

local HOW_PT = {
	{ "Como o censo é montado", {
		"O censo é o registro mais recente de cada guilda por cima do que já se sabia. Cada relato e cada repasse guarda a hora em que foi observado (o relógio do servidor, quando o jogo o dá).",
		"Um relato mais novo substitui o anterior, guilda por guilda, a menos que os outros relatores da guilda o vençam na votação enquanto o anterior tem menos de 15 minutos. O repasse de um guardião guarda a hora em que o registro foi observado pela primeira vez e nunca substitui um registro observado depois dele, então repassar um registro nunca o torna mais novo.",
	} },
	{ "De onde vêm os números", {
		"Em cada guilda Olympus, o addon de um membro lê o roster da guilda e informa o tamanho dela no canal do Olympus a cada poucos minutos; o addon de um segundo membro, quando há um online, informa com menos frequência.",
		"O addon de cada jogador guarda esses relatos: o censo é o último relato de cada guilda. Nada vem diretamente dos servidores da Blizzard.",
	} },
	{ "Dados validados", {
		"O tamanho de uma guilda é confirmado quando vem do roster da sua própria guilda ou, enquanto o último relato dela tem menos de 15 minutos, quando dois ou mais relatores recentes votaram sobre ela sem disputa (S4) ou um guardião confiável (guardiões da Igreja, o Rei, o Alto Conselho) o repassa.",
	} },
	{ "Estimativas", {
		"Pessoas são os personagens menos os alts ligados e confirmados conhecidos aqui: um alt que ninguém vinculou, ou cujas duas confirmações ainda não chegaram a este cliente, conta como mais uma pessoa, então o número pode ficar alto e cair quando as confirmações chegam.",
		"No cliente da equipe de moderação com pelo menos 20 BattleTags validadas, pessoas é uma estimativa (~): as contas validadas, mais os personagens ainda não validados à razão de personagens por conta delas.",
		"Essa estimativa é arredondada a três algarismos significativos e nunca fica abaixo dos jogadores que as amostras contam nem acima da contagem simples.",
		"Quanto mais jogadores usarem o addon Olympus e o Olympus Companion, mais preciso fica este número.",
		"Online conta só relatos dos últimos 15 minutos. Uma guilda mantém seu último tamanho por 24 horas depois do último relato.",
		"Os gráficos são amostras deste próprio cliente: uma a cada 15 minutos enquanto você joga (guardadas 48 horas) e o maior valor de cada dia (guardado 30 dias).",
	} },
	{ "Dados sanitizados", {
		"O censo sanitizado deixa de fora as guildas que os moderadores tiraram da rede (banidas) e as guildas sem notícia há 24 horas (que saíram), e lista as duas à parte.",
		"Um tamanho que saltou além do que uma guilda consegue mudar fica no último tamanho bom até ser confirmado ou ficar ao alcance (S5).",
	} },
	{ "Como funciona a validação", {
		"Cada relato é o voto de quem o enviou sobre o líder e os oficiais da guilda.",
		"Quando os relatores se dividem, um relato é vencido na votação, ou dois tamanhos ficam mais distantes que 5 membros ou 5% (o que for maior, mais 20 membros por minuto entre os dois relatos), a guilda é marcada como em disputa.",
		"Guildas em disputa e de um relator só continuam contando, marcadas assim.",
	} },
	{ "Como funciona a sanitização", {
		"A sanitização roda como regras numeradas: a S1 na entrada, as outras sobre o que este cliente guarda. Depois da entrada, nenhuma regra altera o que uma guilda relatou: cada uma deixa um valor fora de um total, segura-o no último valor bom ou o marca, e registra por quê.",
		"S1 Registro válido: um relato precisa ser legível, nomear uma guilda Olympus, trazer um tamanho de no máximo 1.000 (o limite do jogo) e não contar, por zona, classe ou nível, mais jogadores do que tem online; um online acima do tamanho é cortado para o tamanho. Uma linha repassada por um guardião também não pode ter mais online que membros nem estar datada mais de 5 minutos à frente. O que falha é recusado na entrada: nunca entra no censo.",
		"S2 Atualidade: Online conta só relatos dos últimos 15 minutos: um relato mais antigo é velho e sai do \"agora\". Uma guilda mantém seu último tamanho por 24 horas depois do último relato; depois disso ela saiu: deixa todos os totais e é listada à parte. Ela é esquecida 7 dias depois do último relato.",
		"S3 Exclusões: guildas que os moderadores tiraram da rede (banidas) não entram em nenhum total e seus relatos novos são recusados; são listadas à parte com o último tamanho delas, quando este cliente tem um. Guildas vistas só no /who (este cliente não tem nenhum relato nem repasse delas) também não entram em nenhum total; são listadas à parte com os jogadores que o /who viu online.",
		"S4 Concordância: um tamanho do roster da sua própria guilda é confirmado. O de qualquer outra guilda, enquanto o último relato dela tem menos de 15 minutos, é confirmado quando um guardião confiável o repassa, ou quando dois ou mais relatores votaram sobre a guilda nos últimos 30 minutos e nenhuma disputa é marcada (Como funciona a validação); único quando só um votou, e em disputa quando uma disputa é marcada; mais antigo, é velho. Todas contam; cada guilda leva sua confiança.",
		"S5 Salto impossível: um tamanho a mais de 25 membros ou 10% do último tamanho bom da guilda (o que for maior, mais 20 por minuto desde esse tamanho) e não confirmado (único, em disputa ou velho: S4) foi mais longe do que uma guilda consegue. Fica segurado no último tamanho bom até ser confirmado, até os minutos passados o trazerem ao alcance, ou até o mesmo tamanho se manter por uma hora.",
	} },
}

-- The topics as HowTopics gives them, against `want` word for word.
local function SameTopics(got, want)
	eq(#got, #want, "seven topics")
	for k, topic in ipairs(want) do
		eq(got[k].title, topic[1], "topic " .. k)
		eq(#got[k].lines, #topic[2], topic[1] .. ": its lines")
		for j, text in ipairs(topic[2]) do eq(got[k].lines[j], text, topic[1] .. " " .. j) end
	end
end
local function AllText(topics)
	local out = {}
	for _, topic in ipairs(topics) do out[#out + 1] = topic.title; out[#out + 1] = table.concat(topic.lines, " ") end
	return table.concat(out, " ")
end

test("census page: how the census works, after the graphs and the lists: its header, then the seven topics in order, each a small gold title and its lines in grey rows that fit the page; none of the Companion's own lines", function()
	WithCensus({ ["Olympus"] = Report(900, { online = 200, levels = { 10, 20, 30, 40, 50, 30, 20 } }) }, 0, function()
		local w = World({ realData = true, clock = os.time() })
		eq(w.CS.Sample(), true, "a sample, so the graphs draw")
		local lines = w.CS.Build()
		local _, army = Find(lines, L.CENSUS_STATS_ARMY_GRAPH)
		local _, online = Find(lines, L.CENSUS_STATS_ONLINE_GRAPH)
		local _, largest = Find(lines, L.CENSUS_STATS_LARGEST)
		local _, levels = Find(lines, L.CENSUS_STATS_LEVELS)
		assert(lines[army + 1].graph and lines[online + 1].graph, "both graphs drawn")
		local how, at = Find(lines, L.CENSUS_STATS_HOW)
		assert(how, "the section")
		eq(how.header, true)
		for _, i in ipairs({ army + 1, online + 1, largest, levels }) do assert(at > i, "after the graphs and the lists: " .. at .. " > " .. i) end
		eq(lines[at - 1].gapAfter, true, "a gap before it")
		-- Under it: a gold title per topic, then its lines, each a paragraph of grey rows.
		local topics, current = {}, nil
		for i = at + 1, #lines do
			local line = lines[i]
			local text = Bare(line.text)
			eq(line.header, nil, "small titles: one header, the section's")
			eq(line.onClick, nil); eq(line.tooltip, nil)
			if line.text == V.Gold(text) then
				current = { title = text, rows = {}, paragraphs = 0 }
				topics[#topics + 1] = current
			else
				assert(current, "a topic's title first")
				eq(line.text, V.Grey(text), "its lines grey")
				assert(#text <= w.CS.WRAP, "a row that fits the page: " .. text)
				current.rows[#current.rows + 1] = text
				if line.gapAfter then current.paragraphs = current.paragraphs + 1 end
			end
		end
		eq(#topics, 7)
		for k, want in ipairs(HOW_EN) do
			eq(topics[k].title, want[1], "in order")
			eq(table.concat(topics[k].rows, " "), table.concat(want[2], " "), want[1] .. ": every word, in its rows")
			eq(topics[k].paragraphs, #want[2], want[1] .. ": each line its own paragraph")
			assert(#topics[k].rows > #want[2], want[1] .. ": long lines wrapped")
		end
		-- The words, as the Companion copies them.
		local got = w.CS.HowTopics()
		SameTopics(got, HOW_EN)
		eq(got[4].lines[4], L.PEOPLE_ESTIMATE_MORE, "the people's tooltip's own sentence")
		assert(L.PEOPLE_ESTIMATE_TIP:find(L.PEOPLE_ESTIMATE_MORE, 1, true))
		-- Nothing that only the Companion does or keeps.
		local all = AllText(got)
		for _, s in ipairs({ "[Companion only]", "The Companion reads", "Across the Companions", "longer history", "checkpoints", "/reload",
			"S6", "S7", "z-score", "Army-level", "base panel" }) do
			assert(not all:find(s, 1, true), "a line of the Companion's own: " .. s)
		end
		local _, named = all:gsub("Companion", "")
		eq(named, 1, "the Companion named once: the more players use it")
	end)
end)

test("census page: how the census works: each number it states is the code's own constant, and the words follow it", function()
	local D, C = ns.Data, ns.CensusClean
	-- The numbers HOW_EN states, each the constant behind it.
	eq(D.FRESH, 15 * 60); eq(D.TOTAL_KEEP, 24 * 3600); eq(D.KEEP, 7 * 86400); eq(D.VOUCH_TTL, 30 * 60)
	eq(D.SIZE_SLACK, 5); eq(D.SIZE_SHARE, 0.05); eq(D.SIZE_DRIFT, 20)
	eq(C.JUMP_MIN, 25); eq(C.JUMP_SHARE, 0.10); eq(C.JUMP_DRIFT, 20)
	eq(C.OUTLIER_HOLD, 60 * 60, "\"the same size holds for an hour\" (in words, so asserted here)")
	eq(ns.Codec.GUILD_CAP, 1000, "S1's cap")
	local w = World()
	eq(w.CS.SAMPLE_MIN, 20); eq(w.CS.EVERY, 15 * 60); eq(w.CS.RECENT_KEEP, 48 * 3600); eq(w.CS.DAYS, 30)
	eq((w.CS.Round3(123456)), 123000, "three significant figures"); eq((w.CS.Round3(8333.3)), 8330)
	-- Other constants, other words (this world's Data and CensusClean only).
	w.ns.Data.FRESH, w.ns.Data.TOTAL_KEEP, w.ns.Data.KEEP, w.ns.Data.VOUCH_TTL = 20 * 60, 36 * 3600, 10 * 86400, 40 * 60
	w.ns.Data.SIZE_SLACK, w.ns.Data.SIZE_SHARE, w.ns.Data.SIZE_DRIFT = 6, 0.04, 15
	w.ns.CensusClean = setmetatable({ JUMP_MIN = 30, JUMP_SHARE = 0.12, JUMP_DRIFT = 10 }, { __index = C })
	w.CS.SAMPLE_MIN, w.CS.EVERY, w.CS.RECENT_KEEP, w.CS.DAYS = 25, 10 * 60, 72 * 3600, 14
	w.ns.Codec = setmetatable({ GUILD_CAP = 900 }, { __index = ns.Codec })
	local all = AllText(w.CS.HowTopics())
	-- (The estimates' topic now names the validated BattleTags a team client's estimate needs, once:
	-- the members-plain decision left no alt-link sample to name.)
	for _, s in ipairs({ "under 20 minutes old", "at least 25 validated BattleTags", "from the last 20 minutes",
		"its last size for 36 hours", "one every 10 minutes", "(kept 72 hours)", "(kept 14 days)", "not heard for 36 hours",
		"than 6 members or 4% (whichever is larger, plus 15 members a minute",
		"a size of at most 900 (the game's cap)", "reports from the last 20 minutes: an older report is stale",
		"for 36 hours after its last report; after that it has departed", "forgotten 10 days after its last report",
		"while its last report is under 20 minutes old, is confirmed", "voted on the guild in the last 40 minutes",
		"outvote it while the older one is under 20 minutes old",
		"more than 30 members or 12% away from the guild's last good size (whichever is larger, plus 10 a minute since that size)" }) do
		assert(all:find(s, 1, true), "follows the code: " .. s)
	end
	eq(D.FRESH, 15 * 60, "the harness's own Data untouched"); eq(ns.Codec.GUILD_CAP, 1000, "and its Codec")
	-- A client updated without a restart (no CensusClean yet): nothing is held, so S5's line and the
	-- held size's, which names S5, are left out; the rest as ever.
	w.ns.CensusClean = { missing = true }
	local topics = w.CS.HowTopics()
	eq(#topics, 7); eq(#topics[7].lines, 5); eq(topics[7].lines[5]:sub(1, 3), "S4 ")
	eq(#topics[5].lines, 1); eq(topics[5].lines[1], L.CENSUS_STATS_HOW_SANITIZED_OUT:format(36))
	assert(not AllText(topics):find("S5", 1, true), "no rule named that is not shown")
end)

test("census page: how the census works in Portuguese: the same seven topics, every line its own Portuguese, the same numbers, rows that fit", function()
	local function Words(locale, base)
		local savedLocale = GetLocale
		GetLocale = function() return locale end
		local w = { L = base or {} }
		local ok, err = pcall(function() assert(loadfile(ROOT .. "Olympus/Locales/CensusStatsText.lua"))("Olympus", w) end)
		GetLocale = savedLocale
		if not ok then error(err, 0) end
		return w.L
	end
	-- Every English word of the section has its Portuguese, with the same numbers in it.
	local en, ptOnly = Words("enUS"), Words("ptBR")
	local n = 0
	for key, text in pairs(en) do
		if key:find("^CENSUS_STATS_HOW") or key == "PEOPLE_ESTIMATE_MORE" then
			n = n + 1
			local pt = rawget(ptOnly, key)
			assert(type(pt) == "string" and pt ~= text, "Portuguese of its own: " .. key)
			local function Codes(s) local c = {} for spec in s:gsub("%%%%", ""):gmatch("%%%a") do c[#c + 1] = spec end return table.concat(c) end
			eq(Codes(pt), Codes(text), key .. ": the same numbers")
		end
	end
	eq(n, 30, "the section's header, seven titles, twenty-two lines (the people's sentence shared)")
	-- The page's words in Portuguese, as the Companion copies them.
	local pt = Words("ptBR", setmetatable({}, { __index = ns.L }))
	local w = World({ L = pt })
	-- (Its numbers as the game writes them in Portuguese: "1.000", the ptBR thousands mark of Locales.lua.)
	local savedSep = ns.L.THOUSANDS
	ns.L.THOUSANDS = "."
	local okPt, got = pcall(w.CS.HowTopics)
	ns.L.THOUSANDS = savedSep
	if not okPt then error(got, 0) end
	SameTopics(got, HOW_PT)
	eq(got[4].lines[4], pt.PEOPLE_ESTIMATE_MORE); assert(pt.PEOPLE_ESTIMATE_TIP:find(pt.PEOPLE_ESTIMATE_MORE, 1, true))
	local all = AllText(got)
	for _, s in ipairs({ "[Só Companion]", "O Companion lê", "Entre os Companions", "histórico, mais longo", "checkpoints", "/reload",
		"S6", "S7", "z-score" }) do
		assert(not all:find(s, 1, true), "a line of the Companion's own: " .. s)
	end
	local rows = w.CS.HowLines({})
	eq(Bare(rows[1].text), "Como o censo funciona"); eq(rows[1].header, true)
	for _, line in ipairs(rows) do assert(#Bare(line.text) <= w.CS.WRAP, "a row that fits: " .. Bare(line.text)) end
end)
