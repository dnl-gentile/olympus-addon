-- 1.6.0, a member's /oly bug of 2026-11-15, on 1.5.9: his Census showed 3,202 on PvE and 3,202 on all
-- servers, then 1,544 and 7,068, with "reports heard=0" and old relayed rows. Nothing newer reached his
-- client, so each guild's last report left the count a day after it was read (Data.TOTAL_KEEP); the
-- client's saved look gave way with its oldest guild (its date) and the next quarter hour saved a smaller
-- one, while the other ruleset's count, kept until a newer one replaces it (Data.lua's Lasting), arrived
-- and stayed: one line fell while the total rose, with no member lost. Every name here is made up.
-- Loaded by tests/run.lua.
local ns, test, eq, extra = ...
local ROOT = assert(extra and extra.ROOT, "tests/run.lua hands ROOT to this file")
local Codec = ns.Codec

local REALM, PVP_REALM = "CAMWOWUS1Realm3PvE", "CAMWOWUS1Realm8PvP"
local RELAY = "Ledger Keeper-CAMWOWUS1Realm1PvE" -- a Church ledger relay: a trusted census source
local LEDGER = { ["Ledger Keeper"] = true, ["Ledger Scribe"] = true, ["Ledger Envoy"] = true, ["Ledger Warden"] = true }
local OWN = "Olympus II" -- the harness's GetGuildInfo()
local FILES = {
	["1.5.8"] = ROOT .. "tests/fixtures/data-1.5.8.lua",
	["1.5.9"] = ROOT .. "tests/fixtures/data-1.5.9.lua",
	["1.6.0"] = ROOT .. "Olympus/Data.lua",
}
local T0 = 2000000000
local HOUR = 3600

-- One client's census (its own Data.lua of `version`), its clock the test's, on ForeverPvE.
local function World(version, me)
	local w = { clock = T0, version = version }
	local dns = setmetatable({
		rdb = { guilds = {}, seen = {} }, db = {},
		Codec = Codec, Who = { Listen = function() end },
		On = function() end, RegisterEvent = function() end, Every = function() end, Fire = function() end,
		After = function() end, Log = function() end,
		Now = function() return w.clock end,
	}, { __index = ns })
	assert(loadfile(FILES[version]))("Olympus", dns)
	dns.Church = { IsLedgerRelay = function(name) return LEDGER[ns.ShortName(name or "")] == true end }
	dns.Alts = nil
	dns.me = me or ("Plain Member-" .. REALM)
	dns.IsMember = function() return true end
	dns.QuietPresence = function() return false end
	dns.group, dns.realm, dns.faction = "ForeverPvE", REALM, "Alliance"
	w.sent = {}
	dns.Comm = { loginAt = T0 - HOUR, Send = function(_, text) w.sent[#w.sent + 1] = text return true end,
		SendChunked = function(text) w.sent[#w.sent + 1] = text return true end }
	w.ns, w.D = dns, dns.Data
	-- Our own guild, from our roster (read every minute): 380 characters.
	dns.rdb.guilds[OWN] = { total = 380, online = 40, t = T0, st = T0, mine = true, from = REALM }
	return w
end

-- The ruleset's 30 other guilds as the relay last heard them before T0: 8 heard ten minutes before it
-- (1,164 characters, with ours 1,544), 22 between 2 and 20 hours before it (1,658): 3,202 in all.
local GUILDS, OLDEST, NEWEST = {}, T0 - 20 * HOUR, T0 - 600
for i = 1, 30 do
	local late = i <= 8
	local size = late and (i == 1 and 149 or 145) or ((i == 9 or i == 10) and 79 or 75)
	local observed = late and NEWEST or math.floor(T0 - (2 + (i - 9) * 18 / 21) * HOUR)
	GUILDS[i] = { name = ("Olympus Legion %02d"):format(i), total = size, observed = observed }
end

local function Snapshot(made, rows)
	local out = {}
	for _, r in ipairs(rows) do out[#out + 1] = ("%s,%d,%d,%d,%d"):format(r.name, r.total, 0, 300, r.observed) end
	return ("CG~2~S~%d~ForeverPvE~Alliance~%s"):format(made, table.concat(out, ";"))
end
-- The relay's view again, `delta` characters each, all observed `at`.
local function Rows(at, delta, from, to)
	local out = {}
	for i = from or 1, to or #GUILDS do
		local g = GUILDS[i]
		out[#out + 1] = { name = g.name, total = g.total + (delta or 0), observed = at or g.observed }
	end
	return out
end
-- A trusted look of the other ruleset (CX 1): 5,524 characters in 40 guilds, observed two hours before.
local function PvPLook(w)
	return ("CX~1~S~%d~ForeverPvP,Alliance,5524,5524,40,%d"):format(w.clock, w.clock - 2 * HOUR)
end

-- Hear a word on every client given.
local function Hear(worlds, fn) for _, w in ipairs(worlds) do fn(w) end end
-- The clock moved on to `to`, a quarter hour at a time: our roster read again (fresh), and the census
-- page's sample (CensusStats.Sample): the client's own look saved whenever no saved one stands in.
local function Advance(w, to)
	while w.clock < to do
		w.clock = math.min(to, w.clock + 15 * 60)
		local own = w.ns.rdb.guilds[OWN]
		own.t, own.st = w.clock, w.clock
		local s = w.D.Summary()
		if not s.snapshot then w.D.RecordGroupCensus(s, w.clock) end
	end
end
-- What the client shows: this server's characters (the header's big number), all servers' (the smaller).
local function Shown(w)
	local s = w.D.Summary()
	local g = w.D.Groups(s, w.clock)
	return s.characters, g.characters, s, g
end
-- The jump as the member lived it, up to T0 + 23 h: the relay's snapshot at T0, an older one an hour
-- later (refused: older than what it holds), nothing newer since, then the other ruleset's count.
local function Live(worlds)
	Hear(worlds, function(w)
		assert(w.D.ReceiveGlobalCensus("CHANNEL", RELAY, Snapshot(T0, Rows())), w.version .. " takes the relay's snapshot")
		assert(w.D.RecordGroupCensus(), w.version .. " saves its own look")
	end)
	local at = {}
	at.T0 = {}
	for _, w in ipairs(worlds) do at.T0[w.version] = { Shown(w) } end
	Hear(worlds, function(w)
		w.clock = T0 + HOUR
		w.D.ReceiveGlobalCensus("CHANNEL", RELAY, Snapshot(w.clock, Rows(T0 - 22 * HOUR, -5)))
	end)
	at.older = {}
	for _, w in ipairs(worlds) do at.older[w.version] = { Shown(w) } end
	at.h12, at.h23, at.look = {}, {}, {}
	for _, w in ipairs(worlds) do
		Advance(w, T0 + 12 * HOUR)
		at.h12[w.version] = { Shown(w) }
		Advance(w, T0 + 23 * HOUR)
		at.h23[w.version] = { Shown(w) }
		assert(w.D.ReceiveGroupCensus("CHANNEL", RELAY, PvPLook(w)), w.version .. " takes the other ruleset's count")
		at.look[w.version] = { Shown(w) }
	end
	return at
end

-- Fails before (1.5.9 and the 1.6.0 candidate: 1,544 and 7,068 at T0 + 23 h, its own look saved smaller
-- every quarter hour).
test("1.6.0 census jump: a member whose census stops arriving keeps its last count, dated, through an older relay snapshot and a day of nothing new; the other ruleset's count adds to it, so the PvE line and the all-server total move together (3,202 and 8,726, not 1,544 and 7,068)", function()
	local w = World("1.6.0")
	local at = Live({ w })
	local v = "1.6.0"
	eq(at.T0[v][1], 3202); eq(at.T0[v][2], 3202, "no other server known yet: the total is this server's")
	eq(at.older[v][1], 3202, "a relay snapshot older than what the client holds changes nothing")
	eq(at.h12[v][1], 3202, "nothing newer heard: the saved count stands in for the guilds a day old")
	eq(at.h12[v][3].snapshot.observed, OLDEST); eq(at.h12[v][3].snapshot.quiet, true)
	eq(at.h12[v][3].live.characters, 2452, "the guilds still within their day, beside it")
	eq(at.h23[v][1], 3202); eq(at.h23[v][2], 3202)
	local s, g = at.look[v][3], at.look[v][4]
	eq(s.characters, 3202, "the PvE line keeps the last count")
	eq(g.characters, 3202 + 5524, "the all-server total is that count and the other ruleset's")
	eq(g.kinds.pve.characters, 3202); eq(g.kinds.pvp.characters, 5524)
	eq(g.kinds.pve.characters + g.kinds.pvp.characters, g.characters, "the ruleset lines add up to the total")
	local here
	for _, r in ipairs(g.rows) do if r.ours then here = r end end
	eq(here.characters, 3202); eq(here.observed, OLDEST, "dated as it was observed"); eq(here.src, "own")
	-- The client's own look is not replaced by a smaller one while nothing newer arrives: the look it
	-- carries to the other ruleset is the last full one.
	local kept = w.ns.db.groupCensus["Alliance|ForeverPvE"]
	eq(kept.characters, 3202); eq(kept.guilds, 31); eq(kept.observed, OLDEST); eq(kept.newest, NEWEST)
end)

test("1.6.0 census jump: newer census data still ends the saved count: a complete newer snapshot shows the live count, and once any newer report is heard past the count's day the guilds unheard for a day leave as before", function()
	local w = World("1.6.0")
	Live({ w })
	-- A guild's newer report (one of the eight late ones), past the saved count's day: the client hears
	-- the census again, so the saved count goes to history and the guilds unheard for a day are out.
	w.clock = T0 + 23 * HOUR + 60
	assert(w.D.ReceiveGlobalCensus("CHANNEL", RELAY, Snapshot(w.clock, Rows(w.clock - 30, 0, 1, 1))))
	local here, all, s = Shown(w)
	eq(s.snapshot, nil); eq(s.history.characters, 3202); eq(s.history.counted, false)
	eq(here, 1544, "the guilds heard within their day"); eq(all, 1544 + 5524)
	-- The relay's whole view, newer: the live count, its new sizes.
	w.clock = T0 + 24 * HOUR
	assert(w.D.ReceiveGlobalCensus("CHANNEL", RELAY, Snapshot(w.clock, Rows(w.clock - 60, 2))))
	here, all, s = Shown(w)
	eq(s.snapshot, nil); eq(here, 3202 + 60); eq(all, 3202 + 60 + 5524)

	-- A client the census reaches all along: a guild that stops reporting leaves the count a day after
	-- its last report, as in 1.5.9, once the next newer report is heard.
	local c = World("1.6.0")
	assert(c.D.ReceiveGlobalCensus("CHANNEL", RELAY, Snapshot(T0, Rows())))
	assert(c.D.RecordGroupCensus())
	local gone = GUILDS[30] -- (its last report, 20 hours before T0)
	while c.clock < OLDEST + c.D.TOTAL_KEEP + 15 * 60 do
		c.clock = c.clock + 15 * 60
		c.ns.rdb.guilds[OWN].t, c.ns.rdb.guilds[OWN].st = c.clock, c.clock
		assert(c.D.ReceiveGlobalCensus("CHANNEL", RELAY, Snapshot(c.clock, Rows(c.clock - 60, 0, 1, 29))))
		local s2 = c.D.Summary()
		if not s2.snapshot then c.D.RecordGroupCensus(s2, c.clock) end
	end
	here, all, s = Shown(c)
	eq(s.snapshot, nil); eq(here, 3202 - gone.total, "the silent guild is out"); eq(all, 3202 - gone.total)
end)

-- The header's words for it: the all-server total says the date of its oldest count past a day, and the
-- saved count says why it still stands.
test("1.6.0 census jump: the header dates an all-server total resting on a count over a day old and says the saved count stays because nothing newer arrived; a fresh total says neither", function()
	extra.WithUI(function()
		local UI = extra.LoadUI()
		local w = World("1.6.0")
		Live({ w })
		local saved = { groups = ns.Data.Groups, rebuilding = ns.Data.Rebuilding, group = ns.group }
		local ok, err = pcall(function()
			ns.group = "ForeverPvE"
			ns.Data.Groups, ns.Data.Rebuilding = w.D.Groups, function() return nil end
			local s = w.D.Summary()
			local h = UI.CensusHeader(s, w.clock)
			local F = ns.FormatNumber
			eq(h.characters, 3202)
			eq(h.secondary, ns.L.CENSUS_HEADER_ALL_OLD:format(F(8726), date("%m/%d", OLDEST)))
			eq(h.allNote, ns.L.CENSUS_HEADER_ALL_OLD_TIP:format(date("%m/%d %H:%M", OLDEST)))
			eq(h.sub, ns.L.CENSUS_STATS_KIND_PVE .. " · " .. ns.L.CENSUS_HEADER_SAVED:format(date("%m/%d %H:%M", OLDEST), F(380), 1))
			eq(h.note, ns.L.CENSUS_HEADER_SAVED_TIP:format(date("%m/%d %H:%M", OLDEST)) .. " " .. ns.L.CENSUS_HEADER_QUIET_TIP)
			-- The census reaches the client again: a live count and a fresh total, no date, no note.
			w.clock = T0 + 24 * HOUR
			assert(w.D.ReceiveGlobalCensus("CHANNEL", RELAY, Snapshot(w.clock, Rows(w.clock - 60, 2))))
			assert(w.D.ReceiveGroupCensus("CHANNEL", RELAY, PvPLook(w)))
			h = UI.CensusHeader(w.D.Summary(), w.clock)
			eq(h.characters, 3262); eq(h.secondary, ns.L.CENSUS_HEADER_ALL:format(F(3262 + 5524)))
			eq(h.allNote, nil); eq(h.note, nil)
		end)
		ns.Data.Groups, ns.Data.Rebuilding, ns.group = saved.groups, saved.rebuilding, saved.group
		if not ok then error(err, 0) end
	end)
end)

-- The census page (CensusStats.ServerLines) under the all-server totals: beside "Other servers as of",
-- this server's date while its count is the saved one.
test("1.6.0 census jump: the census page dates this server's saved count under the all-server totals, beside the other servers' date; a live count has no such line", function()
	assert(loadfile(ROOT .. "Olympus/Locales/CensusStatsText.lua"))("Olympus", ns) -- (the page's words)
	local w = World("1.6.0")
	Live({ w })
	local cns = setmetatable({ rdb = {}, Data = w.D, Now = function() return w.clock end,
		Comm = { loginAt = T0 - HOUR, Send = function() end, SendChunked = function() end },
		On = function() end, Every = function() end }, { __index = ns })
	assert(loadfile(ROOT .. "Olympus/CensusStats.lua"))("Olympus", cns)
	local function Bare(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
	local function Lines()
		local lines = {}
		cns.CensusStats.ServerLines(lines, w.D.Summary(), w.clock)
		local texts = {}
		for i, line in ipairs(lines) do texts[Bare(line.text)] = i end
		return lines, texts
	end
	local L = ns.L
	local lines, texts = Lines()
	local here = L.CENSUS_STATS_HERE_AS_OF:format(date("%Y-%m-%d %H:%M", OLDEST))
	local other = L.CENSUS_STATS_SERVERS_AS_OF:format(date("%Y-%m-%d %H:%M", T0 + 21 * HOUR))
	assert(texts[here], "this server's date: " .. here)
	eq(texts[here], texts[other] + 1, "right under the other servers' date")
	local tip = {}
	lines[texts[here]].tooltip({ AddLine = function(_, text) tip[#tip + 1] = text end })
	eq(tip[2], L.CENSUS_STATS_HERE_AS_OF_TIP)
	w.clock = T0 + 24 * HOUR
	assert(w.D.ReceiveGlobalCensus("CHANNEL", RELAY, Snapshot(w.clock, Rows(w.clock - 60, 2))))
	lines, texts = Lines()
	local prefix = L.CENSUS_STATS_HERE_AS_OF:match("^(.-)%%s")
	for text in pairs(texts) do assert(not text:find(prefix, 1, true), "no date for a live count: " .. text) end
end)

-- The new words in every language the addon speaks, each as the game loads it: translated, their %s
-- kept, Russian without the long dash.
test("1.6.0 census jump: the header's and the page's new lines in every language", function()
	local KEYS = { "CENSUS_HEADER_ALL_OLD", "CENSUS_HEADER_ALL_OLD_TIP", "CENSUS_HEADER_QUIET_TIP", "CENSUS_STATS_HERE_AS_OF", "CENSUS_STATS_HERE_AS_OF_TIP" }
	local function Load(code)
		local lns, saved = {}, GetLocale
		GetLocale = function() return code end
		local ok, err = pcall(function()
			assert(loadfile(ROOT .. "Olympus/Locales.lua"))("Olympus", lns)
			assert(loadfile(ROOT .. "Olympus/Locales/CensusStatsText.lua"))("Olympus", lns)
			if code ~= "enUS" and code ~= "ptBR" then assert(loadfile(ROOT .. "Olympus/Locales/" .. code .. ".lua"))("Olympus", lns) end
		end)
		GetLocale = saved
		if not ok then error(err, 0) end
		return lns.L
	end
	local en = Load("enUS")
	local function Formats(s) return select(2, s:gsub("%%s", "")) end
	for _, key in ipairs(KEYS) do assert(type(en[key]) == "string" and en[key] ~= "", "English " .. key) end
	for _, code in ipairs({ "ptBR", "deDE", "esES", "frFR", "itIT", "ruRU" }) do
		local L = Load(code)
		for _, key in ipairs(KEYS) do
			local text = L[key]
			assert(type(text) == "string" and text ~= en[key], code .. " translates " .. key)
			eq(Formats(text), Formats(en[key]), code .. " " .. key .. " keeps its %s")
			if code == "ruRU" then eq(text:find("\226\128\148", 1, true), nil, "ruRU " .. key .. " without the long dash") end
		end
		assert(#L.CENSUS_HEADER_ALL_OLD:format("12,345", "11/15") <= 44 * (code == "ruRU" and 2 or 1), code .. ": the header's number stays short")
	end
end)

-- /oly bug's compact census line (Diagnostics.lua's CensusBriefLine): the 11-15 report could not tell a
-- saved count from a live one. Ours says "saved" and its age when it is the saved count.
test("1.6.0 census jump: /oly bug's census brief says when this server's count is the saved one, and how old; a live count as before", function()
	local w = World("1.6.0")
	Live({ w })
	local saved = { groups = ns.Data.Groups, now = ns.Now, group = ns.group }
	local ok, err = pcall(function()
		ns.group = "ForeverPvE"
		ns.Data.Groups, ns.Now = function() return w.D.Groups(w.D.Summary(), w.clock) end, function() return w.clock end
		local brief = ns.StatusText():match("census brief: [^\n]+")
		assert(brief and brief:find("; ForeverPvE here saved 43h 3202;", 1, true), "ours, saved, 43 hours old: " .. tostring(brief))
		assert(brief:find("all 8726 chars", 1, true), brief)
		w.clock = T0 + 24 * HOUR
		assert(w.D.ReceiveGlobalCensus("CHANNEL", RELAY, Snapshot(w.clock, Rows(w.clock - 60, 2))))
		brief = ns.StatusText():match("census brief: [^\n]+")
		assert(brief:find("; ForeverPvE here 3262;", 1, true), "ours live: " .. brief)
	end)
	ns.Data.Groups, ns.Now, ns.group = saved.groups, saved.now, saved.group
	if not ok then error(err, 0) end
end)

-- The jump's census as clients of three releases live it side by side, hearing the same words: the relay's
-- snapshot, an older one, a day of nothing new, the other ruleset's count, then the relay's newer view.
-- Then three councillors (one per release) take their own look of PvE to PvP, where listeners of each
-- release count what they carry. Fails before on the 1.6.0 client (it lived the jump as 1.5.9 does).
test("1.6.0 census jump, mixed 1.5.8, 1.5.9 and 1.6.0 clients: the older ones still show 1,544 and 7,068 where 1.6.0 shows 3,202 and 8,726; all agree once newer census data arrives; a 1.6.0 councillor's look of PvE reaches PvP listeners of every release as the last full count", function()
	local worlds = { World("1.5.8", "Ledger Scribe-" .. REALM), World("1.5.9", "Ledger Envoy-" .. REALM), World("1.6.0", "Ledger Warden-" .. REALM) }
	local at = Live(worlds)
	local expect = { ["1.5.8"] = { 1544, 7068 }, ["1.5.9"] = { 1544, 7068 }, ["1.6.0"] = { 3202, 8726 } }
	for _, w in ipairs(worlds) do
		local v = w.version
		eq(at.T0[v][1], 3202, v .. " at T0"); eq(at.T0[v][2], 3202, v .. " at T0")
		eq(at.older[v][1], 3202, v .. ": the older snapshot changes nothing")
		eq(at.h12[v][1], v == "1.6.0" and 3202 or 2452, v .. " at T0 + 12 h")
		eq(at.look[v][1], expect[v][1], v .. ": this server at T0 + 23 h")
		eq(at.look[v][2], expect[v][2], v .. ": all servers at T0 + 23 h")
	end
	-- Each councillor goes to PvP and says its own look of PvE there (CX 1, its trusted word); a listener
	-- of each release on PvP counts what it hears.
	local carried = {}
	for _, w in ipairs(worlds) do
		w.clock = T0 + 23 * HOUR + 120
		local name = ns.ShortName(w.ns.me)
		w.ns.group, w.ns.realm, w.ns.me = "ForeverPvP", PVP_REALM, name .. "-" .. PVP_REALM
		carried[w.version] = { name = w.ns.me, word = assert(w.D.GroupCensusPayload(), w.version .. " says its look of PvE") }
	end
	local function Listener(version)
		local l = World(version, "Plain Listener-" .. PVP_REALM)
		l.clock = T0 + 23 * HOUR + 180
		l.ns.group, l.ns.realm = "ForeverPvP", PVP_REALM
		l.ns.rdb.guilds = {}
		return l
	end
	local function PvE(l)
		for _, r in ipairs(l.D.Groups(nil, l.clock).rows) do if r.group == "ForeverPvE" and r.counted then return r.characters, r.observed end end
	end
	for _, version in ipairs({ "1.5.8", "1.5.9", "1.6.0" }) do
		local l = Listener(version)
		assert(l.D.ReceiveGroupCensus("CHANNEL", carried["1.6.0"].name, carried["1.6.0"].word))
		local n, observed = PvE(l)
		eq(n, 3202, version .. " listener: the 1.6.0 councillor's look is the last full count"); eq(observed, OLDEST)
	end
	local fromOld = Listener("1.6.0")
	assert(fromOld.D.ReceiveGroupCensus("CHANNEL", carried["1.5.9"].name, carried["1.5.9"].word))
	eq(PvE(fromOld), 1544, "a 1.5.9 councillor carries the smaller look it saved")
	-- Heard after the full one, that smaller newer look covers under half its guilds: the full count stays.
	local both = Listener("1.6.0")
	assert(both.D.ReceiveGroupCensus("CHANNEL", carried["1.6.0"].name, carried["1.6.0"].word))
	assert(both.D.ReceiveGroupCensus("CHANNEL", carried["1.5.9"].name, carried["1.5.9"].word))
	eq(PvE(both), 3202)
	-- Back on PvE, the relay's newer view reaches all three: the same live count everywhere.
	for _, w in ipairs(worlds) do
		w.ns.group, w.ns.realm, w.ns.me = "ForeverPvE", REALM, ns.ShortName(w.ns.me) .. "-" .. REALM
		w.clock = T0 + 24 * HOUR
		w.ns.rdb.guilds[OWN].t, w.ns.rdb.guilds[OWN].st = w.clock, w.clock
		assert(w.D.ReceiveGlobalCensus("CHANNEL", RELAY, Snapshot(w.clock, Rows(w.clock - 60, 2))))
		local here, all = Shown(w)
		eq(here, 3262, w.version .. " after the newer view"); eq(all, 3262 + 5524, w.version .. " after the newer view")
	end
end)
