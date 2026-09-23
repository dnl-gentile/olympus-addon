-- Offline tests for the pure parts of the addon (codec, election, roster scan, aggregation).
-- Run: luajit tests/run.lua   (from the repo root)

local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\]run%.lua$") or "./"
local ADDON_DIR = ROOT .. "Olympus/"

---------------------------------------------------------------------------
-- Minimal WoW API stubs
---------------------------------------------------------------------------
local stub = setmetatable({}, { __index = function() return function() end end })
function CreateFrame() return stub end
C_Timer = { After = function() end, NewTicker = function() end }
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function GetLocale() return "enUS" end
function UnitFullName() return "Tester", "Realm" end
function IsInGuild() return true end
function GetBuildInfo() return "1.15.8", "99999", "", 11508 end
function geterrorhandler() return function() end end
C_AddOns = { LoadAddOn = function() end }
WorldMapFrame = {}
function GetTime() return os.clock() end
function seterrorhandler() end
function debugprofilestop() return os.clock() * 1000 end
time, date = os.time, os.date
SlashCmdList = {}
function GetTime() return os.clock() end
function LibStub() return nil end
function strsplit(sep, s)
	local out = {}
	for part in (s .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = part end
	return unpack(out)
end
function IsInInstance() return false end
function GuildControlGetNumRanks() return 4 end
function GuildControlGetRankName(i) return ({ "Zeus", "Titan", "Hero", "Recruit" })[i] end
function GetGuildRosterLastOnline(i) if i > 900 then return 0, 1, 2, 0 end return 0, 0, 0, 5 end
Enum = { UIMapType = { Continent = 2, Zone = 3 } }

local MAPS = {
	[947] = { "Azeroth", 1 }, [1415] = { "Eastern Kingdoms", 2 }, [1429] = { "Elwynn Forest", 3 },
	[1453] = { "Stormwind City", 3 }, [1436] = { "Westfall", 3 },
}
local CHILDREN = { [947] = { 1415 }, [1415] = { 1429, 1453, 1436 } }
C_Map = {
	GetMapInfo = function(id) local m = MAPS[id]; return m and { mapID = id, name = m[1], mapType = m[2] } end,
	GetMapChildrenInfo = function(id)
		local out = {}
		for _, c in ipairs(CHILDREN[id] or {}) do out[#out + 1] = C_Map.GetMapInfo(c) end
		return out
	end,
}

local MY_GUILD = "Olympus II"
function GetGuildInfo() return MY_GUILD end
local ZONES = { "Stormwind City", "Elwynn Forest", "Westfall", "The Stockade" }
local CLASSES = { "WARRIOR", "PALADIN", "MAGE", "PRIEST" }
function GetNumGuildMembers() return 1000, 300 end
function GetGuildRosterInfo(i)
	local online = i <= 300
	local rank = i == 1 and 0 or (i <= 6 and 1 or 3)
	return "Member" .. i .. "-Realm", "rank", rank, (i % 30) + 1, "class",
		online and ZONES[(i % #ZONES) + 1] or nil, "", "", online, 0, CLASSES[(i % #CLASSES) + 1]
end

---------------------------------------------------------------------------
-- Load addon files like WoW does: each gets (addonName, sharedTable)
---------------------------------------------------------------------------
local ns = {}
for _, file in ipairs({ "Bootstrap", "Locales", "Core", "Diagnostics", "Codec", "Zones", "Data", "Roster", "Comm", "Map", "Layers", "Positions", "Decree", "Inspect", "Views" }) do
	local chunk = assert(loadfile(ADDON_DIR .. file .. ".lua"))
	chunk("Olympus", ns)
end
ns.db = { pattern = "olympus", guilds = {}, log = {}, errors = {}, demo = false, showMap = true }
ns.me = "Tester-Realm"
function ns.Fire() end

---------------------------------------------------------------------------
local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1; print("  ok   " .. name)
	else failed = failed + 1; print("  FAIL " .. name .. "\n       " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local Codec = ns.Codec

test("federation filter matches any guild with 'olympus' in the name", function()
	eq(ns.IsFederation("Olympus"), true)
	eq(ns.IsFederation("OLYMPUS IV"), true)
	eq(ns.IsFederation("Sons of olympus"), true)
	eq(ns.IsFederation("Olympia"), false)
	eq(ns.IsFederation(nil), false)
end)

test("number formatting", function()
	eq(ns.FormatNumber(0), "0")
	eq(ns.FormatNumber(999), "999")
	eq(ns.FormatNumber(18420), "18,420")
	eq(ns.FormatNumber(1234567), "1,234,567")
end)

test("roster scan of 1000 members", function()
	local r = ns.Roster.Scan()
	eq(r.guild, MY_GUILD)
	eq(r.total, 1000)
	eq(r.online, 300)
	eq(r.leader, "Member1")
	eq(r.zones["m1453"], 75, "stormwind")
	eq(r.zones["tThe Stockade"], 75, "unresolved zone kept as text")
	local sum = 0
	for _, n in pairs(r.levels) do sum = sum + n end
	eq(sum, 300, "level bands")
end)

test("report encode/decode round trip", function()
	local r = ns.Roster.Scan()
	r.users = 4
	local d = Codec.DecodeReport(Codec.EncodeReport(r))
	eq(d.guild, r.guild); eq(d.total, 1000); eq(d.online, 300); eq(d.leader, "Member1")
	eq(d.users, 4); eq(d.zones["m1429"], r.zones["m1429"]); eq(d.classes.WA, r.classes.WA)
	eq(d.levels[1], r.levels[1])
end)

test("chunks fit in 255 bytes and reassemble out of order", function()
	local r = { guild = "Olympus Poseidon", total = 1000, online = 900, leader = "Somebody", users = 1,
		zones = {}, classes = {}, levels = {} }
	for i = 1, 90 do r.zones["m" .. (1400 + i)] = i end
	local payload = Codec.EncodeReport(r)
	local chunks = Codec.Chunk(payload, "7")
	assert(#chunks > 1, "expected several chunks")
	for _, c in ipairs(chunks) do assert(#c <= 255, "chunk too long: " .. #c) end
	local asm = Codec.NewAssembler()
	local full
	for i = #chunks, 1, -1 do full = Codec.Feed(asm, "A-Realm", chunks[i], 0) or full end
	eq(full, payload)
end)

test("decoder rejects garbage and clamps numbers", function()
	eq(Codec.DecodeReport("hello"), nil)
	eq(Codec.DecodeReport("R1~~1~1~~0~0~~~"), nil, "empty guild")
	eq(Codec.DecodeReport(("R1~%s~1~1~~0~0~~~"):format(("x"):rep(30))), nil, "long guild name")
	local d = Codec.DecodeReport("R1~Olympus~99999999~5~Boss~1~2~m1453=99999999~~1,2")
	eq(d.total, 10000); eq(d.zones.m1453, 10000); eq(d.levels[3], 0)
end)

test("one reporter per guild, same answer for everyone", function()
	local now = 1000
	local peers = { ["Bob-Realm"] = now, ["Alice-Realm"] = now - 500, ["Carl-Realm"] = now }
	eq(Codec.PickReporter("Dave-Realm", peers, now, 180), "Bob-Realm", "Alice is stale")
	eq(Codec.PickReporter("Aaron-Realm", peers, now, 180), "Aaron-Realm")
end)

test("summary sums fresh guilds and ignores stale ones and non-Olympus", function()
	local now = os.time()
	ns.db.guilds = {
		["Olympus"] = { total = 1000, online = 200, zones = { m1453 = 150, m1429 = 50 }, t = now },
		["Olympus II"] = { total = 800, online = 100, zones = { m1453 = 100 }, t = now - 60 },
		["Olympus Old"] = { total = 500, online = 50, zones = { m1436 = 50 }, t = now - 3600 },
		["Horde Pals"] = { total = 999, online = 999, zones = {}, t = now },
	}
	local s = ns.Data.Summary()
	eq(s.total, 1800); eq(s.online, 300); eq(s.fresh, 2); eq(#s.guilds, 3)
	eq(s.zoneList[1].key, "m1453"); eq(s.zoneList[1].count, 250)
	eq(s.guilds[3].name, "Olympus Old", "stale sorted last")
	assert(ns.Data.DiscordText():find("1,800 soldiers"), "discord text")
end)

test("receive refuses reports about our own guild", function()
	ns.db.guilds = {}
	eq(ns.Data.Receive({ guild = MY_GUILD, total = 1, online = 1, zones = {} }, "Liar-Realm"), false)
	eq(ns.Data.Receive({ guild = "Olympus Zeus", total = 1, online = 1, zones = {} }, "Zed-Realm"), true)
	eq(ns.db.guilds["Olympus Zeus"].reporter, "Zed")
end)

test("demo data builds 14 guilds", function()
	ns.Data.BuildDemo()
	local n = 0
	for _ in pairs(ns.demoGuilds) do n = n + 1 end
	eq(n, 14)
end)

test("errors are captured with dedupe", function()
	ns.db.errors = {}
	ns.CaptureError("test", "boom")
	ns.CaptureError("test", "boom")
	eq(#ns.db.errors, 1); eq(ns.db.errors[1].count, 2)
	assert(ns.BuildBugReport():find("boom"))
end)

test("tabard classification", function()
	local I = ns.Inspect
	eq(I.Classify(5976, true), "GUILD")
	eq(I.Classify(23192, true), "OTHER")
	eq(I.Classify(nil, true), "NONE")
	eq(I.Classify(nil, false), "UNKNOWN", "no gear visible is not an accusation")
end)

test("inspection summary, marks and discord text", function()
	ns.db.demo = false
	ns.db.inspect = nil
	local I = ns.Inspect
	I.Record("Good-Realm", "Olympus", "WARRIOR", 20, 5976, true)
	I.Record("Naked-Realm", "Olympus II", "MAGE", 18, nil, true)
	I.Record("Pirate-Realm", "Olympus II", "ROGUE", 19, 23192, true)
	I.ToggleMark("Good-Realm")
	I.ToggleGuildMark("Olympus Hermes")
	local s = I.Summary()
	eq(s.total, 3); eq(s.counts.NONE, 1); eq(s.counts.OTHER, 1); eq(s.counts.GUILD, 1)
	eq(s.players[1].name, "Good-Realm", "marked first")
	eq(s.players[2].name, "Naked-Realm", "then no tabard")
	eq(s.guilds[1].name, "Olympus Hermes", "marked guild first")
	eq(s.guilds[2].name, "Olympus II"); eq(s.guilds[2].bad, 2)
	local text = I.DiscordText()
	assert(text:find("NO TABARD") and text:find("Naked"), text)
	assert(I.TooltipLine("Naked-Realm"):find("NO TABARD"))
end)

test("inspection demo data", function()
	ns.Inspect.BuildDemo()
	local n = 0
	for _ in pairs(ns.demoInspect.players) do n = n + 1 end
	assert(n > 20)
end)

test("roster reads ranks, officers, inactivity and top levels", function()
	ns.db.officerRank = 1
	local r = ns.Roster.Scan()
	eq(#r.ranks, 4); eq(r.ranks[1].name, "Zeus"); eq(r.ranks[1].count, 1); eq(r.ranks[2].count, 5)
	eq(#r.officers, 5, "ranks 1 are officers")
	eq(r.inactive30, 100, "members 901-1000 offline 32 days")
	eq(r.top[1].level, 30)
	assert(r.avgLevel > 1)
end)

test("R2 report round trip keeps the hierarchy", function()
	local r = ns.Roster.Scan()
	local d = ns.Codec.DecodeReport(ns.Codec.EncodeReport(r))
	eq(d.ranks[2].name, "Titan"); eq(d.ranks[4].count, r.ranks[4].count)
	eq(#d.officers, 5); eq(d.officers[1].name, r.officers[1].name)
	eq(d.inactive30, 100); eq(d.top[1].level, 30)
	eq(math.floor(d.avgLevel), math.floor(r.avgLevel))
	local chunks = ns.Codec.Chunk(ns.Codec.EncodeReport(r), "9")
	for _, c in ipairs(chunks) do assert(#c <= 255) end
end)

test("old R1 reports still decode", function()
	local d = ns.Codec.DecodeReport("R1~Olympus~10~2~Boss~1~2~m1453=2~WA=2~0,2,0,0,0,0,0")
	eq(d.total, 10); eq(#d.officers, 0); eq(#d.ranks, 0)
end)

test("position, layer and decree messages", function()
	local C = ns.Codec
	local p = C.DecodePosition(C.EncodePosition(1453, 0.4567, 0.1234, "WA"))
	eq(p.mapID, 1453); eq(p.class, "WA"); assert(math.abs(p.x - 0.457) < 0.001)
	eq(C.DecodePosition("P1~1~2000~3~WA"), nil, "x out of range")
	local l = C.DecodeLayer(C.EncodeLayer(1453, 4102, 0, "Olympus II"))
	eq(l.zoneUID, 4102); eq(l.rank, 0); eq(l.guild, "Olympus II")
	local m = C.EncodeDecree("ARMS", 1436, 0.5, 0.5, "Olympus", 1, ("Horde~at the farm "):rep(20))
	assert(#m <= 255, "decree too long " .. #m)
	local d = C.DecodeDecree(m)
	eq(d.kind, "ARMS"); eq(d.mapID, 1436); eq(d.rank, 1)
	eq(C.DecodeDecree("D1~NUKE~1~1~1~x~0~boom"), nil, "unknown kind")
end)

test("layer named after the highest rank present", function()
	ns.db.demo = false
	C_Map.GetBestMapForUnit = function() return 1453 end
	ns.Data.Summary = ns.Data.Summary
	ns.db.guilds = { ["Olympus"] = { total = 1000, online = 1, zones = {}, t = os.time() },
		["Olympus II"] = { total = 500, online = 1, zones = {}, t = os.time() } }
	ns.Layers.Receive("Grunt-Realm", { mapID = 1453, zoneUID = 7, rank = 4, guild = "Olympus" })
	ns.Layers.Receive("Lordy-Realm", { mapID = 1453, zoneUID = 7, rank = 0, guild = "Olympus II" })
	ns.Layers.Receive("Kingy-Realm", { mapID = 1453, zoneUID = 7, rank = 0, guild = "Olympus" })
	ns.Layers.Receive("Solo-Realm", { mapID = 1453, zoneUID = 8, rank = 3, guild = "Olympus" })
	local layers = ns.Layers.ForMap(1453)
	eq(#layers, 2); eq(layers[1].count, 3)
	eq(ns.Layers.Name(layers[1]), "Kingy's layer", "rank 0 of the bigger guild wins")
	ns.db.demo = true
	ns.Layers.BuildDemo()
	eq(#ns.Layers.ForMap(1437), 3, "demo layers follow any zone")
	ns.db.demo = false
	eq(ns.Layers.Name(layers[2]), "Solo's layer")
end)

test("crown permissions", function()
	eq(ns.IsCrownRank("Olympus II", 0), true, "any guild master")
	eq(ns.IsCrownRank("Olympus", 1), true, "officers of the main guild")
	eq(ns.IsCrownRank("Olympus II", 1), false, "officers of other guilds")
	eq(ns.IsCrownRank("Olympus", 3), false)
end)

test("wall of shame round trip", function()
	local list = {}
	for i = 1, 50 do list[i] = { name = "Naked" .. i, guild = "Olympus II" } end
	local payload = ns.Codec.EncodeShame("Olympus", 0, list)
	local d = ns.Codec.DecodeShame(payload)
	eq(d.guild, "Olympus"); eq(d.rank, 0); eq(#d.list, 40, "capped"); eq(d.list[3].name, "Naked3")
	for _, c in ipairs(ns.Codec.Chunk(payload, "4")) do assert(#c <= 255) end
end)

test("person details travel in the report", function()
	local r = ns.Roster.Scan()
	local d = ns.Codec.DecodeReport(ns.Codec.EncodeReport(r))
	eq(d.leaderClass, "PA"); assert(d.leaderLevel and d.leaderLevel > 0)
	eq(d.officers[1].class ~= nil, true, "officer class")
	eq(d.top[1].class ~= nil, true, "top class")
	local old = ns.Codec.DecodeReport("R2~Olympus~10~2~Boss~1~2~~~0,0,0,0,0,0,0~~Cap:1:0~0~0~0~0~Top:20")
	eq(old.officers[1].name, "Cap"); eq(old.top[1].level, 20); eq(old.leaderClass, nil)
end)

test("every tab builds", function()
	ns.db.demo = true
	ns.Data.BuildDemo(); ns.Inspect.BuildDemo(); ns.Layers.BuildDemo()
	ns.UI = { StatusLine = function() return "status" end }
	for _, tab in ipairs({ "census", "realm", "decrees", "heraldry" }) do
		local lines, title = ns.Views.Build(tab)
		assert(#lines > 0 and title, tab)
	end
	ns.db.demo = false
end)

test("layer sample is stable and about 1 in 8", function()
	local saved, hits = ns.me, 0
	for i = 1, 800 do
		ns.me = "Player" .. i .. "-Realm"
		local a, b = ns.Layers.InSample(), ns.Layers.InSample()
		eq(a, b, "same answer every time")
		if a then hits = hits + 1 end
	end
	ns.me = saved
	assert(hits > 50 and hits < 150, "sample size " .. hits)
end)

test("realm view lists king, lords, captains and level race", function()
	ns.db.demo = true
	ns.Data.BuildDemo()
	local lines = ns.Views.RealmLines()
	assert(lines[1].text:find("King") and lines[1].text:find("Asmongold"), lines[1].text)
	local sawRace = false
	for _, l in ipairs(lines) do if l.text == "Level race" then sawRace = true end end
	assert(sawRace)
	ns.db.demo = false
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
