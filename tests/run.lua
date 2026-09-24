-- Offline tests for the addon: codec, election, roster scan, aggregation, and the windows
-- (guild window button, docking, layout) on stand-in frames.
-- Run: luajit tests/run.lua   (from the repo root)

local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\]run%.lua$") or "./"
local ADDON_DIR = ROOT .. "Olympus/"

---------------------------------------------------------------------------
-- Minimal WoW API stubs
---------------------------------------------------------------------------
local stub = setmetatable({}, { __index = function() return function() end end })
EVENT_SCRIPTS = {}
function CreateFrame()
	return setmetatable({ SetScript = function(_, kind, fn) if kind == "OnEvent" then EVENT_SCRIPTS[#EVENT_SCRIPTS + 1] = fn end end },
		{ __index = function() return function() end end })
end
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
function GetRealmName() return "Realm" end
function seterrorhandler() end
function debugprofilestop() return os.clock() * 1000 end
time, date = os.time, os.date
SlashCmdList = {}
StaticPopupDialogs = {}
function GetTime() return os.clock() end
function GetRealmName() return "Realm" end
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
for _, file in ipairs({ "Bootstrap", "Locales", "Core", "Diagnostics", "Codec", "Zones", "Data", "Roster", "Comm", "Map", "Layers", "Positions", "Decree", "Inspect", "Recruit", "Views" }) do
	local chunk = assert(loadfile(ADDON_DIR .. file .. ".lua"))
	chunk("Olympus", ns)
end
ns.db = { guilds = {}, log = {}, errors = {}, blocked = {}, demo = false, showMap = true }
ns.me = "Tester-Realm"
ns.realm = "Realm"
ns.rdb = { guilds = {} }
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
	ns.rdb.guilds = {
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
	ns.rdb.guilds = {}
	eq(ns.Data.Receive({ guild = MY_GUILD, total = 1, online = 1, zones = {} }, "Liar-Realm"), false)
	eq(ns.Data.Receive({ guild = "Olympus Zeus", total = 1, online = 1, zones = {} }, "Zed-Realm"), true)
	eq(ns.rdb.guilds["Olympus Zeus"].reporter, "Zed")
end)

test("demo data is gone and old installs forget the setting", function()
	eq(ns.Data.BuildDemo, nil); eq(ns.Data.SetDemo, nil); eq(ns.Inspect.BuildDemo, nil); eq(ns.Layers.BuildDemo, nil)
	local savedDB, savedR, savedRealm = ns.db, ns.rdb, ns.realm
	for _, old in ipairs({ { demo = true }, { demo = true, configVersion = 2 }, { demo = true, configVersion = 3 } }) do
		OlympusDB = old
		for _, fn in ipairs(EVENT_SCRIPTS) do fn(nil, "ADDON_LOADED", "Olympus") end
		eq(OlympusDB.demo, nil, "demo setting cleared (configVersion " .. tostring(old.configVersion) .. ")")
		eq(OlympusDB.configVersion, 3)
	end
	ns.db, ns.rdb, ns.realm = savedDB, savedR, savedRealm
end)

test("upgrade from account-wide data: block list, old census and key, inspections", function()
	local savedDB, savedR, savedRealm = ns.db, ns.rdb, ns.realm
	local blocked = {}
	for i = 1, 40 do blocked["troll" .. i] = true end
	blocked["far-other"] = true
	OlympusDB = { configVersion = 3, blocked = blocked, realmKey = "old-secret",
		guilds = { ["Olympus Far"] = { total = 5, t = os.time() } },
		inspect = { players = { Naked = { status = "NONE" } }, guildMarks = {} } }
	local errors = 0
	local savedCapture = ns.CaptureError
	ns.CaptureError = function() errors = errors + 1 end
	for _, fn in ipairs(EVENT_SCRIPTS) do fn(nil, "ADDON_LOADED", "Olympus") end
	ns.CaptureError = savedCapture
	eq(errors, 0, "no error while migrating")
	local short, full = 0, 0
	for k in pairs(OlympusDB.blocked) do if k:find("-", 1, true) then full = full + 1 else short = short + 1 end end
	eq(short, 0, "every short name converted"); eq(full, 41)
	eq(OlympusDB.blocked["troll7-realm"], true)
	eq(OlympusDB.realmKey, nil, "old key dropped, officers resend it")
	eq(OlympusDB.guilds, nil, "old census dropped")
	eq(OlympusDB.realms.Realm.realmKey, nil)
	eq(OlympusDB.realms.Realm.guilds["Olympus Far"], nil, "not moved into this realm")
	eq(OlympusDB.inspect, nil)
	eq(OlympusDB.realms.Realm.inspect.players.Naked.status, "NONE", "inspections kept on this realm")
	ns.db, ns.rdb, ns.realm = savedDB, savedR, savedRealm
end)

test("an old saved report does not grant rank", function()
	ns.rdb.guilds = { ["Olympus Zeus"] = { total = 10, online = 1, zones = {}, t = os.time() - 3600, leader = "Zed", realm = "Realm" } }
	eq(ns.Data.KnownRank("Zed-Realm", "Olympus Zeus"), nil, "report from an hour ago")
	ns.rdb.guilds["Olympus Zeus"].t = os.time()
	eq(ns.Data.KnownRank("Zed-Realm", "Olympus Zeus"), 0, "fresh report")
	ns.rdb.guilds = {}
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
	C_Map.GetBestMapForUnit = function() return 1453 end
	ns.Data.Summary = ns.Data.Summary
	ns.rdb.guilds = { ["Olympus"] = { total = 1000, online = 1, zones = {}, t = os.time(), leader = "Kingy" },
		["Olympus II"] = { total = 500, online = 1, zones = {}, t = os.time(), leader = "Lordy" } }
	ns.Layers.Receive("Grunt-Realm", { mapID = 1453, zoneUID = 7, rank = 4, guild = "Olympus" })
	-- Claims rank 0 but is nobody's Lord: counted, but cannot name the layer.
	ns.Layers.Receive("Aaron-Realm", { mapID = 1453, zoneUID = 7, rank = 0, guild = "Olympus" })
	ns.Layers.Receive("Lordy-Realm", { mapID = 1453, zoneUID = 7, rank = 0, guild = "Olympus II" })
	ns.Layers.Receive("Kingy-Realm", { mapID = 1453, zoneUID = 7, rank = 0, guild = "Olympus" })
	ns.Layers.Receive("Solo-Realm", { mapID = 1453, zoneUID = 8, rank = 3, guild = "Olympus" })
	local layers = ns.Layers.ForMap(1453)
	eq(#layers, 2); eq(layers[1].count, 4)
	eq(ns.Layers.Name(layers[1]), "Kingy's layer", "rank 0 of the bigger guild wins")
	-- A sender who moves counts on the new layer only.
	ns.Layers.Receive("Grunt-Realm", { mapID = 1453, zoneUID = 8, rank = 4, guild = "Olympus" })
	eq(ns.Layers.ForMap(1453)[1].count, 3, "moved sender left the old layer")
	eq(#ns.Layers.ForMap(1437), 0, "no made-up layers in other zones")
	eq(ns.Layers.Name(layers[2]), "Solo's layer")
end)

test("names carry the realm, so namesakes on other realms stay apart", function()
	eq(ns.FullName("Zed"), "Zed-Realm")
	eq(ns.FullName("Zed-Other"), "Zed-Other")
	eq(ns.DisplayName("Zed-Realm"), "Zed", "own realm shows short")
	eq(ns.DisplayName("Zed-Other"), "Zed-Other", "other realm keeps the suffix")
	ns.rdb.guilds = { ["Olympus Zeus"] = { total = 10, online = 1, zones = {}, t = os.time(), leader = "Zed", realm = "Realm",
		officers = { { name = "Capt", online = true, days = 0 } } } }
	eq(ns.Data.KnownRank("Zed", "Olympus Zeus"), 0, "short name from our realm")
	eq(ns.Data.KnownRank("Zed-Realm", "Olympus Zeus"), 0)
	eq(ns.Data.KnownRank("Zed-Other", "Olympus Zeus"), nil, "namesake on another realm is not the Lord")
	eq(ns.Data.KnownRank("Capt-Other", "Olympus Zeus"), nil, "namesake officer rejected")
	eq(ns.Data.KnownRank("Capt-Realm", "Olympus Zeus"), 1)
	-- A guild reported from another realm: its short names belong to that realm.
	ns.rdb.guilds["Olympus Far"] = { total = 10, online = 1, zones = {}, t = os.time(), leader = "Kay", realm = "Other" }
	eq(ns.Data.KnownRank("Kay-Other", "Olympus Far"), 0)
	eq(ns.Data.KnownRank("Kay-Realm", "Olympus Far"), nil)
	ns.rdb.guilds = {}
end)

test("reporter election compares full names", function()
	local now = os.time()
	eq(ns.Codec.PickReporter("Tester-Realm", { ["Abe-Realm"] = now }, now, 180), "Abe-Realm")
	eq(ns.Codec.PickReporter("Tester-Realm", { ["Abe-Realm"] = now - 999 }, now, 180), "Tester-Realm", "stale peer ignored")
	eq(ns.Roster.RankOf("Member1"), 0, "our roster answers short names")
	eq(ns.Roster.RankOf("Member1-Realm"), 0)
	eq(ns.Roster.RankOf("Member1-Other"), nil, "namesake from another realm is not in our guild")
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

test("only Olympus guilds count, the filter cannot be changed", function()
	eq(ns.IsFederation("House of Guedes"), false)
	eq(ns.IsMember(), true, "tests run as a member of Olympus II")
	local saved = GetGuildInfo
	GetGuildInfo = function() return "House of Guedes" end
	eq(ns.IsMember(), false)
	GetGuildInfo = saved
end)

test("ranks are verified, not taken from the message", function()
	ns.Roster.Scan()
	ns.rdb.guilds = {
		["Olympus"] = { guild = "Olympus", leader = "Asmongold", officers = { { name = "Capt" } }, total = 1000, online = 1, zones = {}, t = os.time() },
		["Olympus Bad"] = { guild = "Olympus Bad", leader = "X", conflict = true, total = 1, online = 1, zones = {}, t = os.time() },
	}
	eq(ns.Data.KnownRank("Asmongold-Realm", "Olympus"), 0)
	eq(ns.Data.KnownRank("Capt-Realm", "Olympus"), 1)
	eq(ns.Data.KnownRank("Random-Realm", "Olympus"), nil, "claims mean nothing")
	eq(ns.Data.KnownRank("X-Realm", "Olympus Bad"), nil, "conflicting guild is not trusted")
	eq(ns.Data.KnownRank("Member1-Realm", "Olympus II"), 0, "own guild from our roster")
end)

test("a sender can only report one guild", function()
	ns.rdb.guilds = {}
	eq(ns.Data.Receive({ guild = "Olympus Zeus", total = 5, online = 1, zones = {} }, "Liar2-Realm"), true)
	eq(ns.Data.Receive({ guild = "Olympus Fake", total = 900, online = 1, zones = {} }, "Liar2-Realm"), false)
end)

test("sealed channel name comes from the key", function()
	local a, b = ns.Comm.Hash36("secret-one"), ns.Comm.Hash36("secret-one")
	eq(a, b); eq(#a, 8)
	assert(ns.Comm.Hash36("secret-two") ~= a)
	ns.rdb.realmKey = "secret-one"
	local name, password = ns.Comm.ChannelSpec()
	eq(name, "Oly" .. a); eq(password, "secret-one")
	ns.rdb.realmKey = nil
	eq((ns.Comm.ChannelSpec()), "OlympusNet")
end)

test("join flow groups online Olympus players and never asks twice", function()
	local R = ns.Recruit
	R.found = {
		{ name = "A", guild = "Olympus II" }, { name = "B", guild = "Olympus II" }, { name = "C", guild = "Olympus" },
	}
	local g = R.Guilds()
	eq(g[1].name, "Olympus II"); eq(#g[1].members, 2)
	eq(R.NextContact("Olympus II").name, "A")
	R.asked.A = 1
	eq(R.NextContact("Olympus II").name, "B")
	R.asked.B = 1
	eq(R.NextContact("Olympus II"), nil)
	function UnitLevel() return 12 end
	function UnitClass() return "Mage", "MAGE" end
	assert(R.Message({ guild = "Olympus II" }):find("Olympus II"))
	assert(#ns.Views.RecruitLines() > 3)
	eq((R.Roast()), "<Olympus II>? Disband immediately.")
	local saved = GetGuildInfo
	GetGuildInfo = function() return nil end
	eq((R.Roast()), "No guild? What are you doing?")
	GetGuildInfo = saved
end)

test("worst case report still fits the message limits", function()
	local C = ns.Codec
	local r = { guild = "Olympus Longest NameHer", total = 1000, online = 1000, leader = "Averylongname", leaderOnline = true,
		users = 999, zones = {}, classes = {}, levels = { 1, 2, 3, 4, 5, 6, 7 }, ranks = {}, officers = {}, top = {},
		leaderClass = "WARRIOR", leaderLevel = 60, leaderZone = "tThe Temple of Atal'Hakkar" }
	for i = 1, 120 do r.zones["tSome Long Zone Name " .. i] = 999 end
	for _, c in ipairs({ "WA", "PA", "HU", "RO", "PR", "SH", "MA", "WL", "DR", "DK" }) do r.classes[c] = 999 end
	for i = 1, 10 do r.ranks[i] = { name = "Rank Name Number " .. i, count = 999 } end
	for i = 1, 30 do r.officers[i] = { name = "Officername" .. i, online = true, days = 99, class = "WARLOCK", level = 60, zone = "tSome Long Zone Name " .. i } end
	for i = 1, 5 do r.top[i] = { name = "Topplayer" .. i, level = 60, class = "PRIEST" } end
	local payload = C.EncodeReport(r)
	local chunks = C.Chunk(payload, "999")
	assert(#chunks <= C.MAX_CHUNKS, "too many chunks: " .. #chunks)
	for _, c in ipairs(chunks) do assert(#c <= 255) end
	local d = C.DecodeReport(payload)
	eq(#d.officers, 30); eq(#d.ranks, 10)
end)

local function SampleGuilds()
	local now = os.time()
	return {
		["Olympus"] = { total = 990, online = 210, zones = { m1453 = 120, m1429 = 40 }, t = now, leader = "Asmongold",
			leaderOnline = true, leaderLevel = 24, leaderClass = "WA", ranks = { { name = "King", count = 1 }, { name = "Knight", count = 989 } },
			officers = { { name = "Capt", online = true, days = 0, class = "PA", level = 22 } },
			top = { { name = "Racer", level = 25, class = "MA" } }, inactive7 = 10, inactive30 = 2, avgLevel = 14 },
		["Olympus II"] = { total = 500, online = 80, zones = { m1453 = 30 }, t = now, leader = "Lordy", leaderOnline = false, leaderDays = 4,
			officers = {}, top = { { name = "Other", level = 20, class = "RO" } } },
	}
end

test("every tab builds", function()
	ns.rdb.guilds = SampleGuilds()
	ns.UI = { StatusLine = function() return "status" end }
	for _, tab in ipairs({ "census", "realm", "decrees", "heraldry" }) do
		local lines, title = ns.Views.Build(tab)
		assert(#lines > 0 and title, tab)
	end
	ns.rdb.guilds = {}
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
	ns.rdb.guilds = SampleGuilds()
	local lines = ns.Views.RealmLines()
	assert(lines[1].text:find("King") and lines[1].text:find("Asmongold"), lines[1].text)
	local sawRace = false
	for _, l in ipairs(lines) do if l.text == "Level race" then sawRace = true end end
	assert(sawRace)
	ns.rdb.guilds = {}
end)

test("captains in the report are rank 1 whatever /oly officer says", function()
	local saved = ns.db.officerRank
	ns.db.officerRank = 9
	local r = ns.Roster.Scan()
	eq(#r.officers, 5, "only the rank 1 members")
	ns.db.officerRank = saved
end)

test("map refresh runs end to end with a map library (continent totals included)", function()
	-- A stub where every method returns another stub, so frame building code can run.
	local function deep()
		return setmetatable({}, { __index = function() return function() return deep() end end })
	end
	local calls = { world = 0 }
	local fakePins = setmetatable({
		AddWorldMapIconMap = function() calls.world = calls.world + 1 end,
		RemoveAllWorldMapIcons = function() end,
		AddMinimapIconMap = function() end,
		RemoveWorldMapIcon = function() end,
		RemoveMinimapIcon = function() end,
	}, { __index = function() return function() end end })
	local savedLibStub, savedCreateFrame, savedWMF = LibStub, CreateFrame, WorldMapFrame
	LibStub = function(name) if name == "HereBeDragons-Pins-2.0" then return fakePins end end
	CreateFrame = function() return deep() end
	WorldMapFrame = deep()
	C_Map.GetMapRectOnMap = function() return 0.1, 0.3, 0.2, 0.8 end
	MAPS[947] = { "Azeroth", 1 }; MAPS[1415] = { "Eastern Kingdoms", 2, 947 }
	local oldInfo = C_Map.GetMapInfo
	C_Map.GetMapInfo = function(id)
		local m = MAPS[id]
		if not m then return nil end
		local parent = ({ [1429] = 1415, [1453] = 1415, [1436] = 1415, [1415] = 947 })[id]
		return { mapID = id, name = m[1], mapType = m[2], parentMapID = parent }
	end
	local mapChunk = assert(loadfile(ADDON_DIR .. "Map.lua"))
	local captured
	local savedCapture = ns.CaptureError
	ns.CaptureError = function(where, err) captured = where .. ": " .. tostring(err) end
	mapChunk("Olympus", ns)
	ns.db.showMap = true
	ns.rdb.guilds = { ["Olympus"] = { total = 100, online = 10, zones = { m1453 = 7, m1429 = 3 }, t = os.time() } }
	ns.Map.Refresh()
	ns.CaptureError = savedCapture
	LibStub, CreateFrame, WorldMapFrame, C_Map.GetMapInfo = savedLibStub, savedCreateFrame, savedWMF, oldInfo
	eq(captured, nil, "map refresh raised an error")
	assert(calls.world >= 2, "zone pins were not added")
	local totals = ns.Map.ContinentTotals(ns.Data.Summary())
	eq(totals[1415], 10, "continent total")
end)

---------------------------------------------------------------------------
-- Guild window button (GuildFrame.lua): old Guild tab, new Communities window, or both
---------------------------------------------------------------------------

-- A frame with just what GuildFrame.lua uses. Scripts hooked on it can be run.
local function FakeFrame(name, parent, w, h)
	local f = { name = name, parent = parent, w = w, h = h, shown = false, hooks = {} }
	function f:GetName() return self.name end
	function f:GetParent() return self.parent end
	function f:GetWidth() return self.w end
	function f:GetHeight() return self.h end
	function f:GetFrameLevel() return 5 end
	function f:GetEffectiveScale() return 1 end
	function f:GetRect() if self.rect then return unpack(self.rect) end end -- where a test put it
	function f:IsShown() return self.shown end
	function f:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
	function f:HookScript(kind, fn) self.hooks[kind] = self.hooks[kind] or {}; table.insert(self.hooks[kind], fn) end
	function f:Run(kind) for _, fn in ipairs(self.hooks[kind] or {}) do fn(self) end end
	function f:Show() self.shown = true; self:Run("OnShow") end
	function f:Hide() self.shown = false; self:Run("OnHide") end
	return f
end

-- Loads GuildFrame.lua with fresh state into a namespace of its own. Its events and LOGIN
-- are fired by hand; the Olympus window is a stand-in that remembers where it is docked,
-- or with realUI the real UI.lua (which needs the widget toolkit further below).
local function LoadGuildFrame(realUI)
	local world = { events = {}, login = {}, buttons = {}, dock = { shown = false } }
	local dock = world.dock
	local gns = setmetatable({}, { __index = ns })
	world.ns = gns
	gns.RegisterEvent = function(event, fn) world.events[event] = world.events[event] or {}; table.insert(world.events[event], fn) end
	gns.On = function() end -- UI.lua's own callbacks (minimap button at LOGIN, refreshes) stay out
	if realUI then assert(loadfile(ADDON_DIR .. "UI.lua"))("Olympus", gns) end
	gns.On = function(name, fn) if name == "LOGIN" then table.insert(world.login, fn) end end
	gns.MakeRoundButton = function(name, parent, size)
		local b = setmetatable({ name = name, parent = parent, size = size, scripts = {} }, { __index = function() return function() end end })
		function b:SetScript(kind, fn) self.scripts[kind] = fn end
		function b:SetPoint(...) self.point = { ... } end
		function b:Click() self.scripts.OnClick(self) end
		world.buttons[#world.buttons + 1] = b
		return b
	end
	gns.UI = realUI and gns.UI or {
		IsShown = function() return dock.shown end,
		DockedTo = function() return dock.host end,
		OpenDocked = function(host, tab, heightOnly) dock.shown, dock.host, dock.tab, dock.heightOnly = true, host, tab, heightOnly end,
		CloseIfDocked = function(host) if dock.shown and (host == nil or dock.host == host) then dock.shown = false end end,
		FollowHost = function(host) dock.followed = host end,
	}
	assert(loadfile(ADDON_DIR .. "GuildFrame.lua"))("Olympus", gns)
	world.hook = gns.GuildFrameHook
	function world.Fire(event, ...) for _, fn in ipairs(world.events[event] or {}) do fn(...) end end
	function world.Login() for _, fn in ipairs(world.login) do fn() end end
	return world
end

-- Runs fn with fake Blizzard windows as globals (cleared afterwards), failing on any error
-- the addon caught along the way.
local GUILD_GLOBALS = { "UIParent", "FriendsFrame", "GuildFrame", "CommunitiesFrame", "ClassicUIForeverGuildPanel" }
local function WithGuildWindows(fn)
	local captured
	local savedCapture = ns.CaptureError
	ns.CaptureError = function(where, err) captured = captured or (where .. ": " .. tostring(err)) end
	UIParent = FakeFrame("UIParent")
	UIParent.shown = true
	local ok, err = pcall(fn)
	ns.CaptureError = savedCapture
	for _, name in ipairs(GUILD_GLOBALS) do _G[name] = nil end
	if not ok then error(err, 0) end
	eq(captured, nil, "error caught")
end

test("guild button: old UI only (Guild tab), same spot and docking as before", function()
	WithGuildWindows(function()
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 338, 424)
		GuildFrame = FakeFrame("GuildFrame", FriendsFrame, 338, 424)
		local w = LoadGuildFrame()
		w.Login()
		local hosts = w.hook.Hosts()
		eq(#hosts, 1, "hosts")
		eq(hosts[1].kind, "old")
		local b = w.buttons[1]
		eq(b.name, "OlympusGuildFrameButton"); eq(b.parent, GuildFrame); eq(b.size, 26)
		eq(b.point[1], "TOPLEFT"); eq(b.point[2], FriendsFrame); eq(b.point[3], "TOPLEFT"); eq(b.point[4], 62); eq(b.point[5], -26)
		FriendsFrame:Show(); GuildFrame:Show()
		b:Click()
		eq(w.dock.host, FriendsFrame, "docks to the Social window"); eq(w.dock.tab, "census"); eq(w.dock.heightOnly, false)
		b:Click()
		eq(w.dock.shown, false, "a second click closes it")
		b:Click(); FriendsFrame:Hide()
		eq(w.dock.shown, false, "closing the Social window closes it")
		b:Click(); GuildFrame:Hide()
		eq(w.dock.shown, false, "leaving the Guild tab closes it")
		-- Nothing else to hook, and scanning again (the Social window opening) hooks nothing twice.
		w.Fire("ADDON_LOADED", "Blizzard_Communities")
		FriendsFrame:Show()
		eq(#w.hook.Hosts(), 1); eq(#w.buttons, 1); eq(#GuildFrame.hooks.OnHide, 1, "OnHide hooks")
	end)
end)

test("guild button: new UI loaded at login (Forever: Communities window only)", function()
	WithGuildWindows(function()
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 385, 424)
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
		CommunitiesFrame.MaximizeMinimizeFrame = FakeFrame(nil, CommunitiesFrame, 24, 24)
		local w = LoadGuildFrame()
		w.Login()
		local hosts = w.hook.Hosts()
		eq(#hosts, 1, "hosts")
		eq(hosts[1].kind, "communities")
		local b = w.buttons[1]
		eq(b.parent, CommunitiesFrame); eq(b.point[1], "RIGHT"); eq(b.point[2], CommunitiesFrame.MaximizeMinimizeFrame, "title bar")
		CommunitiesFrame:Show()
		eq(w.hook.ActiveHost(), hosts[1], "in use")
		b:Click()
		eq(w.dock.host, CommunitiesFrame, "docks to the Communities window"); eq(w.dock.heightOnly, true)
		-- No Guild tab in the Social window, so nothing of ours listens to it closing (the
		-- other way round is covered in the "both windows" and real-window tests).
		eq(FriendsFrame.hooks.OnHide, nil, "no Social window hook without a Guild tab")
		CommunitiesFrame:Run("OnSizeChanged")
		eq(w.dock.followed, CommunitiesFrame, "follows minimize and maximize")
		CommunitiesFrame:Hide()
		eq(w.dock.shown, false, "closing the Communities window closes it")
		local status = w.hook.StatusLine()
		assert(status:find("communities=CommunitiesFrame", 1, true), status)
	end)
end)

test("guild button: new UI loaded later (ADDON_LOADED), next to the unused old tab", function()
	WithGuildWindows(function()
		-- Classic Era with the classic guild UI off: the old tab exists but never shows.
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 338, 424)
		GuildFrame = FakeFrame("GuildFrame", FriendsFrame, 338, 424)
		local w = LoadGuildFrame()
		w.Login()
		eq(#w.hook.Hosts(), 1, "only the old tab at login")
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 322, 406)
		CommunitiesFrame.CloseButton = FakeFrame(nil, CommunitiesFrame, 24, 24)
		w.Fire("ADDON_LOADED", "SomeOtherAddon")
		eq(#w.hook.Hosts(), 1, "other addons change nothing")
		w.Fire("ADDON_LOADED", "Blizzard_Communities")
		local hosts = w.hook.Hosts()
		eq(#hosts, 2, "hosts")
		eq(hosts[2].kind, "communities")
		local b = w.buttons[2]
		eq(b.parent, CommunitiesFrame); eq(b.point[2], CommunitiesFrame.CloseButton, "no minimize button: next to close")
		eq(w.hook.ActiveHost(), nil, "nothing opened yet")
		CommunitiesFrame:Show()
		eq(w.hook.ActiveHost(), hosts[2], "in use")
		b:Click()
		eq(w.dock.host, CommunitiesFrame)
		CommunitiesFrame:Hide()
		eq(w.hook.ActiveHost(), hosts[2], "last opened")
	end)
end)

test("guild button: both windows present, switching between them without /reload", function()
	WithGuildWindows(function()
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 338, 424)
		GuildFrame = FakeFrame("GuildFrame", FriendsFrame, 338, 424)
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
		local w = LoadGuildFrame()
		w.Login()
		local hosts = w.hook.Hosts()
		eq(#hosts, 2, "hosts")
		local old, new = w.buttons[1], w.buttons[2]
		eq(old.parent, GuildFrame); eq(new.parent, CommunitiesFrame)
		assert(old.name ~= new.name, "one button name per window")
		-- New UI in use.
		CommunitiesFrame:Show(); new:Click()
		eq(w.dock.host, CommunitiesFrame)
		-- The player switches to the old UI: the Communities window closes, the Guild tab opens.
		CommunitiesFrame:Hide()
		eq(w.dock.shown, false, "closed with the Communities window")
		FriendsFrame:Show(); GuildFrame:Show()
		eq(w.hook.ActiveHost().kind, "old")
		old:Click()
		eq(w.dock.host, FriendsFrame); eq(w.dock.heightOnly, false)
		-- Clicked in the other window while docked: it moves there instead of closing.
		CommunitiesFrame:Show(); new:Click()
		eq(w.dock.shown, true); eq(w.dock.host, CommunitiesFrame)
		eq(w.hook.ActiveHost().kind, "old", "both on screen: the Social window's first")
		eq(#FriendsFrame.hooks.OnHide, 1, "the Social window is watched (for the Guild tab)")
		FriendsFrame:Hide()
		eq(w.dock.shown, true, "still docked to the Communities window")
	end)
end)

test("guild button: standalone GuildFrame (Blizzard_GuildUI) is not taken for the old tab", function()
	WithGuildWindows(function()
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 338, 424)
		local oldTab = FakeFrame("GuildFrame", FriendsFrame, 338, 424)
		GuildFrame = oldTab
		local w = LoadGuildFrame()
		w.Login()
		-- Blizzard_GuildUI loads and takes over the name GuildFrame.
		GuildFrame = FakeFrame("GuildFrame", UIParent, 646, 468)
		GuildFrame.CloseButton = FakeFrame(nil, GuildFrame, 24, 24)
		w.Fire("ADDON_LOADED", "Blizzard_GuildUI")
		local hosts = w.hook.Hosts()
		eq(#hosts, 2, "hosts")
		eq(hosts[1].frame, oldTab); eq(hosts[1].kind, "old")
		eq(hosts[2].frame, GuildFrame); eq(hosts[2].kind, "guildui"); eq(hosts[2].dock, GuildFrame)
		GuildFrame:Show(); w.buttons[2]:Click()
		eq(w.dock.host, GuildFrame); eq(w.dock.heightOnly, true)
	end)
end)

test("guild button: ClassicUI Forever's Guild tab is found when the Social window opens", function()
	WithGuildWindows(function()
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 385, 424)
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
		local w = LoadGuildFrame()
		w.Login()
		eq(#w.hook.Hosts(), 1, "only the Communities window at login")
		-- Built after login, inside the Social window.
		ClassicUIForeverGuildPanel = FakeFrame("ClassicUIForeverGuildPanel", FriendsFrame)
		FriendsFrame:Show(); ClassicUIForeverGuildPanel:Show()
		local hosts = w.hook.Hosts()
		eq(#hosts, 2, "hosts")
		eq(hosts[2].kind, "classicui")
		local b = w.buttons[2]
		eq(b.parent, ClassicUIForeverGuildPanel); eq(b.point[2], FriendsFrame); eq(b.point[4], 62); eq(b.point[5], -26)
		b:Click()
		eq(w.dock.host, FriendsFrame)
		ClassicUIForeverGuildPanel:Hide()
		eq(w.dock.shown, false, "closing the Guild tab closes it")
	end)
end)

test("guild button: ClassicUI Forever's panel outside the Social window is a window of its own", function()
	WithGuildWindows(function()
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 385, 424)
		ClassicUIForeverGuildPanel = FakeFrame("ClassicUIForeverGuildPanel", UIParent, 338, 440)
		ClassicUIForeverGuildPanel.CloseButton = FakeFrame(nil, ClassicUIForeverGuildPanel, 24, 24)
		local w = LoadGuildFrame()
		w.Login()
		local hosts = w.hook.Hosts()
		eq(#hosts, 1, "hosts")
		eq(hosts[1].kind, "classicuiwindow"); eq(hosts[1].social, nil); eq(hosts[1].dock, ClassicUIForeverGuildPanel)
		local b = w.buttons[1]
		eq(b.name, "OlympusClassicGuildWindowButton"); eq(b.size, 22)
		eq(b.point[1], "RIGHT"); eq(b.point[2], ClassicUIForeverGuildPanel.CloseButton, "title bar, like the new windows")
		ClassicUIForeverGuildPanel:Show(); b:Click()
		eq(w.dock.host, ClassicUIForeverGuildPanel, "docks to itself"); eq(w.dock.heightOnly, true)
		eq(FriendsFrame.hooks.OnHide, nil, "the Social window is not watched for it")
		ClassicUIForeverGuildPanel:Run("OnSizeChanged")
		eq(w.dock.followed, ClassicUIForeverGuildPanel, "follows its size")
		ClassicUIForeverGuildPanel:Hide()
		eq(w.dock.shown, false, "closing it closes ours")
	end)
end)

test("docked size: the old Guild tab is copied, the new windows lend only their height", function()
	local uns = setmetatable({}, { __index = ns })
	assert(loadfile(ADDON_DIR .. "UI.lua"))("Olympus", uns)
	local DockSize = uns.UI.DockSize
	local function size(...) local w, h = DockSize(...); return w .. "x" .. h end
	eq(size(338, 424, false, 338, 424), "338x424", "old Guild tab")
	eq(size(385, 424, false, 385, 424), "385x424", "Forever's Social window")
	eq(size(814, 426, true, 385, 424), "385x426", "Communities window, maximized")
	eq(size(322, 406, true, 338, 424), "338x406", "Communities window, minimized")
	eq(size(0, 0, false, 338, 424), "338x424", "host not laid out yet")
	eq(size(nil, nil, true), "338x424", "nothing known")
end)

---------------------------------------------------------------------------
-- The Olympus window itself (UI.lua), on a small widget toolkit: frames keep their size,
-- anchors and shown state, scripts can be fired, rects are worked out from the anchors
-- and text is measured at a fixed width per letter.
---------------------------------------------------------------------------

local POINT_X = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = 0.5, CENTER = 0.5, BOTTOM = 0.5, TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1 }
local POINT_Y = { BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5, TOPLEFT = 1, TOP = 1, TOPRIGHT = 1 }
local CHAR_W = { GameFontNormalLarge = 9, GameFontNormal = 7, GameFontHighlight = 7 } -- small fonts: 6

local Widget = {}
local NOOP_VERBS = { "^Set", "^Enable", "^Disable", "^Register", "^Unregister", "^Lock", "^Unlock", "^Raise", "^Lower", "^Highlight", "^Play" }
local widgetNames = {}
local widgetMeta = { __index = function(_, key)
	local method = Widget[key]
	if method then return method end
	-- Setters and the like a test does not look at do nothing; anything else is nil, as a
	-- missing child key (CloseButton, TitleText, Left...) would be.
	if type(key) == "string" then
		for _, verb in ipairs(NOOP_VERBS) do if key:find(verb) then return function() end end end
	end
end }

local function NewWidget(kind, name, parent)
	local w = setmetatable({ kind = kind, name = name, parent = parent, points = {}, shown = true, scripts = {}, hooks = {} }, widgetMeta)
	if name then _G[name] = w; widgetNames[#widgetNames + 1] = name end
	return w
end

function Widget:GetName() return self.name end
function Widget:GetParent() return self.parent end
function Widget:GetObjectType() return self.kind end
function Widget:Fire(kind, ...)
	if self.scripts[kind] then self.scripts[kind](self, ...) end
	for _, fn in ipairs(self.hooks[kind] or {}) do fn(self, ...) end
end
function Widget:SetScript(kind, fn) self.scripts[kind] = fn end
function Widget:GetScript(kind) return self.scripts[kind] end
function Widget:HookScript(kind, fn) self.hooks[kind] = self.hooks[kind] or {}; table.insert(self.hooks[kind], fn) end
function Widget:Show() if not self.shown then self.shown = true; self:Fire("OnShow") end end
function Widget:Hide() if self.shown then self.shown = false; self:Fire("OnHide") end end
function Widget:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Widget:IsShown() return self.shown end
function Widget:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Widget:GetEffectiveScale() return self.scale or (self.parent and self.parent:GetEffectiveScale()) or 1 end
function Widget:GetFrameLevel() return self.level or 1 end
function Widget:SetFrameLevel(level) self.level = level end

function Widget:SetSize(w, h)
	local changed = self.w ~= w or self.h ~= h
	self.w, self.h = w, h
	if changed then self:Fire("OnSizeChanged", w, h) end
end
function Widget:SetWidth(w) self:SetSize(w, self.h) end
function Widget:SetHeight(h) self:SetSize(self.w, h) end
function Widget:GetWidth()
	if self.kind == "FontString" and (self.w or 0) == 0 then return self:GetStringWidth() end
	if self.w then return self.w end
	local _, _, w = self:GetRect()
	return w or 0
end
function Widget:GetHeight()
	if self.h then return self.h end
	local _, _, _, h = self:GetRect()
	return h or 0
end

-- SetPoint in all its WoW forms, kept as { point, relativeTo, relativePoint, x, y }.
function Widget:SetPoint(point, a, b, c, d)
	local rel, relPoint, x, y
	if type(a) == "number" then
		rel, relPoint, x, y = nil, point, a, b
	elseif type(b) == "string" then
		rel, relPoint, x, y = a, b, c, d
	else
		rel, relPoint, x, y = a, point, b, c
	end
	if type(rel) == "string" then rel = _G[rel] end
	local anchor = { point, rel or self.parent, relPoint, x or 0, y or 0 }
	for i, p in ipairs(self.points) do
		if p[1] == point then self.points[i] = anchor return end
	end
	self.points[#self.points + 1] = anchor
end
function Widget:SetAllPoints(rel)
	rel = rel or self.parent
	self.points = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } }
end
function Widget:ClearAllPoints() self.points = {} end
function Widget:GetNumPoints() return #self.points end
function Widget:GetPoint(i) return unpack(self.points[i or 1]) end
-- Anchor with this point name, or nil.
function Widget:Anchor(point) for _, p in ipairs(self.points) do if p[1] == point then return p end end end

-- left, bottom, width, height in the widget's own units, from a fixed rect or its anchors.
function Widget:GetRect()
	if self.rect then return unpack(self.rect) end
	if #self.points == 0 then return nil end
	local l, r, cx, b, t, cy
	for _, p in ipairs(self.points) do
		local rl, rb, rw, rh = p[2]:GetRect()
		if not rl then return nil end
		local ax, ay = rl + rw * POINT_X[p[3]] + p[4], rb + rh * POINT_Y[p[3]] + p[5]
		local fx, fy = POINT_X[p[1]], POINT_Y[p[1]]
		if fx == 0 then l = ax elseif fx == 1 then r = ax else cx = ax end
		if fy == 0 then b = ay elseif fy == 1 then t = ay else cy = ay end
	end
	local w, h = self.w or 0, self.h or 0
	if l and r then w = r - l elseif r then l = r - w elseif cx and not l then l = cx - w / 2 end
	if b and t then h = t - b elseif t then b = t - h elseif cy and not b then b = cy - h / 2 end
	if not l or not b then return nil end
	return l, b, w, h
end
function Widget:GetLeft() return (self:GetRect()) end
function Widget:GetBottom() return select(2, self:GetRect()) end
function Widget:GetTop() local _, b, _, h = self:GetRect(); return b and b + h end
function Widget:GetRight() local l, _, w = self:GetRect(); return l and l + w end

function Widget:StartMoving() self.moving = true end
function Widget:StopMovingOrSizing()
	-- Like the client: wherever it was dropped, now held by one absolute anchor.
	local l, b = self:GetRect()
	self.moving = nil
	self.points = { { "BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b } }
end

function Widget:CreateFontString(name, _, font) local fs = NewWidget("FontString", name, self); fs.font = font; return fs end
function Widget:CreateTexture(name) return NewWidget("Texture", name, self) end
function Widget:SetText(text)
	if self.kind == "FontString" then self.text = text return end
	self.fontString = self.fontString or self:CreateFontString(nil, "OVERLAY", self.normalFont or "GameFontNormal")
	self.fontString:SetText(text)
end
function Widget:GetText() if self.kind == "FontString" then return self.text end return self.fontString and self.fontString.text end
function Widget:GetFontString() return self.fontString end
function Widget:SetNormalFontObject(font) self.normalFont = font; if self.fontString then self.fontString.font = font end end
function Widget:SetFontObject(font) self.font = font end
function Widget:GetFontObject() return self.font end
function Widget:SetWordWrap(wrap) self.wrap = wrap end
function Widget:SetJustifyH(justify) self.justifyH = justify end
function Widget:GetUnboundedStringWidth() return #(self.text or "") * (CHAR_W[self.font] or 6) end
function Widget:GetStringWidth()
	local full = self:GetUnboundedStringWidth()
	return (self.w or 0) > 0 and math.min(full, self.w) or full
end
function Widget:IsTruncated() return self.wrap == false and (self.w or 0) > 0 and self:GetUnboundedStringWidth() > self.w end
function Widget:Click() self:Fire("OnClick") end

local TEMPLATES = {
	PortraitFrameTemplate = function(w)
		w.CloseButton = NewWidget("Button", nil, w)
		w.w, w.h = 338, 424
	end,
	BasicFrameTemplateWithInset = function(w)
		w.CloseButton = NewWidget("Button", nil, w)
		w.TitleText = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	end,
	-- The same atlas template on every client (see UI.TabStyle); the Lua sizing it differs.
	PanelTabButtonTemplate = function(w)
		w.h = 32
		for _, key in ipairs({ "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive" }) do w[key] = NewWidget("Texture", nil, w) end
		w.Text = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		w.fontString = w.Text
		w.parent.Tabs = w.parent.Tabs or {}
		table.insert(w.parent.Tabs, w)
	end,
}

local function FakeCreateFrame(kind, name, parent, template)
	local w = NewWidget(kind, name, parent)
	if TEMPLATES[template] then TEMPLATES[template](w) end
	return w
end

-- Blizzard's tab code, as far as it matters here (Blizzard_SharedXML, see UI.TabStyle):
-- Mainline sizes a tab to its text + 20 and has PanelTemplates_AnchorTabs, Classic sizes
-- it to its text + both end caps and does not.
local TAB_GLOBALS = { "PanelTemplates_TabResize", "PanelTemplates_AnchorTabs", "PanelTemplates_SelectTab", "PanelTemplates_DeselectTab" }
local function TabCode(family)
	local capW = 20
	PanelTemplates_SelectTab = function(tab) tab.selected = true end
	PanelTemplates_DeselectTab = function(tab) tab.selected = false end
	if family == "mainline" then
		PanelTemplates_AnchorTabs = function() end
		PanelTemplates_TabResize = function(tab, padding) tab:SetWidth(math.max(tab.Text:GetStringWidth() + 20 + (padding or 0), 2 * capW)) end
	else
		PanelTemplates_TabResize = function(tab, padding) tab:SetWidth(tab.Text:GetStringWidth() + (padding or 24) + 2 * capW) end
	end
end

-- Runs fn with the widget toolkit as the client (the screen is 1366 x 768), failing on
-- any error the addon caught. Everything it made global is cleared afterwards.
local function WithUI(fn)
	local captured
	local saved = { CreateFrame = CreateFrame, CaptureError = ns.CaptureError, UI = ns.UI, GetGuildInfo = GetGuildInfo }
	ns.CaptureError = function(where, err) captured = captured or (where .. ": " .. tostring(err)) end
	CreateFrame = FakeCreateFrame
	UIParent = NewWidget("Frame", "UIParent")
	UIParent.rect = { 0, 0, 1366, 768 }
	UISpecialFrames, tinsert = {}, table.insert
	GameTooltip = NewWidget("GameTooltip", "GameTooltip", UIParent)
	ns.rdb.guilds = SampleGuilds()
	local ok, err = pcall(fn)
	CreateFrame, ns.CaptureError, ns.UI, GetGuildInfo = saved.CreateFrame, saved.CaptureError, saved.UI, saved.GetGuildInfo
	for _, name in ipairs(widgetNames) do _G[name] = nil end
	widgetNames = {}
	for _, name in ipairs(GUILD_GLOBALS) do _G[name] = nil end
	for _, name in ipairs(TAB_GLOBALS) do _G[name] = nil end
	PTR_IssueReporter, UISpecialFrames, tinsert = nil, nil, nil
	ns.rdb.guilds = {}
	if not ok then error(err, 0) end
	eq(captured, nil, "error caught")
end

-- UI.lua with fresh state in a namespace of its own (Views and friends read ns.UI).
local function LoadUI()
	local uns = setmetatable({}, { __index = ns })
	uns.On = function() end
	assert(loadfile(ADDON_DIR .. "UI.lua"))("Olympus", uns)
	ns.UI = uns.UI
	return uns.UI
end

local function Anchor(frame, i)
	local p = frame.points[i or 1]
	return p and table.concat({ p[1], tostring(p[2] and p[2].name), p[3], p[4], p[5] }, " ")
end

test("tab spacing: Blizzard's on Forever (Mainline tab code), the old overlap on Classic", function()
	local uns = setmetatable({}, { __index = ns })
	assert(loadfile(ADDON_DIR .. "UI.lua"))("Olympus", uns)
	local UI = uns.UI
	local atlasTab, plainButton = { LeftActive = {} }, {}
	eq(UI.TabStyle(atlasTab), "classic", "same atlas template, Classic code")
	PanelTemplates_AnchorTabs = function() end
	eq(UI.TabStyle(atlasTab), "mainline")
	eq(UI.TabStyle(plainButton), "classic", "fallback buttons keep the old spacing")
	PanelTemplates_AnchorTabs = nil
	local f, prev = {}, {}
	eq(select(5, UI.TabAnchor("mainline", 1, f)), 2)
	eq(table.concat({ select(3, UI.TabAnchor("mainline", 1, f)) }, " "), "BOTTOMLEFT 5 2", "first tab where FriendsFrame has it")
	eq(table.concat({ UI.TabAnchor("mainline", 2, f, prev) }, " ", 3), "TOPRIGHT 3 0", "3 apart, like PanelTemplates_AnchorTabs")
	eq(select(2, UI.TabAnchor("mainline", 2, f, prev)), prev)
	eq(table.concat({ UI.TabAnchor("classic", 1, f) }, " ", 3), "BOTTOMLEFT 10 2")
	eq(table.concat({ UI.TabAnchor("classic", 3, f, prev) }, " ", 3), "RIGHT -15 0")
end)

test("tabs on the real window: side by side on Forever, unchanged on Classic", function()
	for _, family in ipairs({ "mainline", "classic" }) do
		WithUI(function()
			TabCode(family)
			local UI = LoadUI()
			UI.SelectTab("census")
			local main = OlympusFrame
			eq(UI.tabTemplate, "PanelTabButtonTemplate"); eq(UI.tabStyle, family)
			local tabs = main.tabs
			if family == "mainline" then
				eq(Anchor(tabs[1]), "TOPLEFT OlympusFrame BOTTOMLEFT 5 2")
				eq(Anchor(tabs[2]), "TOPLEFT " .. tabs[1].name .. " TOPRIGHT 3 0")
				for i = 2, #tabs do
					local gap = tabs[i]:GetLeft() - tabs[i - 1]:GetRight()
					eq(gap, 3, "gap before tab " .. i)
					assert(tabs[i].Text:GetStringWidth() + 20 <= tabs[i]:GetWidth(), "text fits tab " .. i)
				end
				assert(tabs[#tabs]:GetRight() <= main:GetRight(), "last tab inside the window")
			else
				eq(Anchor(tabs[1]), "TOPLEFT OlympusFrame BOTTOMLEFT 10 2")
				eq(Anchor(tabs[3]), "LEFT " .. tabs[2].name .. " RIGHT -15 0")
			end
			eq(tabs[1].selected, true); eq(tabs[2].selected, false)
		end)
	end
end)

test("Join screen: no column titles, the list starts higher, and it follows joining", function()
	WithUI(function()
		GetGuildInfo = function() return nil end
		local UI = LoadUI()
		UI.Toggle()
		local main = OlympusFrame
		local function listTop() return main.scroll:Anchor("TOPLEFT")[5] end
		eq(main.colHeader:IsShown(), false, "Join screen: no column titles")
		eq(listTop(), -64)
		eq(main.tabs[1]:IsShown(), false)
		-- The player joins an Olympus guild with the window open (DATA_CHANGED, or the
		-- 5 second refresh).
		GetGuildInfo = function() return "Olympus II" end
		UI.Refresh()
		eq(main.colHeader:IsShown(), true, "census column titles once a member")
		eq(listTop(), -80)
		eq(main.tabs[1]:IsShown(), true)
		-- And leaves it.
		GetGuildInfo = function() return "House of Guedes" end
		UI.Refresh()
		eq(main.colHeader:IsShown(), false); eq(listTop(), -64)
		-- Other tabs never had column titles.
		GetGuildInfo = function() return "Olympus II" end
		UI.SelectTab("realm")
		eq(main.colHeader:IsShown(), false); eq(listTop(), -64)
	end)
end)

test("header lines stay inside the window: smaller font first, then cut", function()
	WithUI(function()
		GetGuildInfo = function() return nil end
		local UI = LoadUI()
		UI.Toggle()
		local main = OlympusFrame
		local w = main:GetWidth()
		eq(w, 338, "the narrow window")
		-- "No guild? What are you doing?" is too wide in the large font, fits in the normal one.
		eq(main.total:GetText(), ns.L.ROAST_NOGUILD)
		eq(main.total.font, "GameFontNormal", "dropped to the smaller font")
		eq(main.total.w, w - 62 - 26); eq(main.total:IsTruncated(), false)
		-- The long line is cut ("...") at the window's edge instead of running past it.
		eq(main.sub:GetText(), ns.L.ROAST_NOGUILD_SUB)
		eq(main.sub.w, w - 62 - 8); eq(main.sub.wrap, false); eq(main.sub.justifyH, "LEFT")
		eq(main.sub:IsTruncated(), true)
		assert(62 + main.sub:GetStringWidth() <= w, "inside the window")
		-- A member's header fits in the large font and is not cut.
		GetGuildInfo = function() return "Olympus II" end
		UI.Refresh()
		eq(main.total.font, "GameFontNormalLarge"); eq(main.total:IsTruncated(), false)
		-- A wider window gives the lines more room.
		main:SetSize(385, 424)
		eq(main.sub.w, 385 - 62 - 8)
	end)
end)

test("docking with the real window: follows the guild window it was clicked in", function()
	WithUI(function()
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 338, 424)
		FriendsFrame.rect = { 20, 200, 338, 424 }
		GuildFrame = FakeFrame("GuildFrame", FriendsFrame, 338, 424)
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
		CommunitiesFrame.rect = { 20, 180, 814, 426 }
		local w = LoadGuildFrame(true)
		ns.UI = w.ns.UI
		w.Login()
		local UI = w.ns.UI
		local old, new = w.buttons[1], w.buttons[2]
		local function size() return OlympusFrame:GetWidth() .. "x" .. OlympusFrame:GetHeight() end
		-- Clicked in the Guild tab: next to the Social window, its size.
		FriendsFrame:Show(); GuildFrame:Show(); old:Click()
		local main = OlympusFrame
		eq(main:IsShown(), true); eq(UI.DockedTo(), FriendsFrame)
		eq(Anchor(main), "TOPLEFT FriendsFrame TOPRIGHT -2 0"); eq(main:GetNumPoints(), 1)
		eq(size(), "338x424")
		-- Clicked in the Communities window: moves there, its height, the Social width.
		CommunitiesFrame:Show(); new:Click()
		eq(main:IsShown(), true, "moved, not closed"); eq(UI.DockedTo(), CommunitiesFrame)
		eq(Anchor(main), "TOPLEFT CommunitiesFrame TOPRIGHT -2 0"); eq(main:GetNumPoints(), 1)
		eq(size(), "338x426")
		-- The Social window closing (it is watched) leaves it docked where it is.
		GuildFrame:Hide(); FriendsFrame:Hide()
		eq(main:IsShown(), true, "the Social window closing leaves it open"); eq(UI.DockedTo(), CommunitiesFrame)
		-- The Communities window is minimized: the new height is taken.
		CommunitiesFrame.w, CommunitiesFrame.h = 322, 406
		CommunitiesFrame:Run("OnSizeChanged")
		eq(size(), "338x406", "follows minimize")
		-- Dragged away: no longer docked, keeps its size and stays open when the guild window
		-- changes or closes.
		main.scripts.OnDragStart(main); main.scripts.OnDragStop(main)
		eq(UI.DockedTo(), nil, "dragged: not docked")
		eq(Anchor(main), "BOTTOMLEFT UIParent BOTTOMLEFT 832 200", "where it was dropped")
		CommunitiesFrame.w, CommunitiesFrame.h = 814, 500
		CommunitiesFrame:Run("OnSizeChanged")
		eq(size(), "338x406", "no longer follows")
		CommunitiesFrame:Hide()
		eq(main:IsShown(), true, "no longer closes with it")
		-- Clicked again: docks again, then a second click closes it.
		CommunitiesFrame:Show(); new:Click()
		eq(main:IsShown(), true); eq(UI.DockedTo(), CommunitiesFrame)
		eq(Anchor(main), "TOPLEFT CommunitiesFrame TOPRIGHT -2 0"); eq(size(), "338x500")
		new:Click()
		eq(main:IsShown(), false, "second click closes it")
		-- Opened from the Guild tab and closed with it.
		FriendsFrame:Show(); GuildFrame:Show(); old:Click()
		eq(UI.DockedTo(), FriendsFrame); eq(size(), "338x424")
		GuildFrame:Hide()
		eq(main:IsShown(), false, "leaving the Guild tab closes it")
	end)
end)

test("clearing a rect: up just enough, never off the screen", function()
	local uns = setmetatable({}, { __index = ns })
	assert(loadfile(ADDON_DIR .. "UI.lua"))("Olympus", uns)
	local ClearUp = uns.UI.ClearUp
	local function R(l, b, r, t) return { left = l, bottom = b, right = r, top = t } end
	local win = R(500, 182, 840, 636)
	eq(ClearUp(win, R(640, 142, 728, 228), 768, 4), 50, "overlapping: up past its top plus the gap")
	eq(ClearUp(win, R(10, 142, 90, 228), 768, 4), nil, "beside it")
	eq(ClearUp(win, R(640, 100, 728, 182), 768, 4), nil, "just touching below")
	eq(ClearUp(win, R(640, 600, 728, 700), 768, 4), nil, "cannot clear without leaving the screen")
	eq(ClearUp(win, R(640, 142, 728, 228), 690, 4), 50, "room enough")
	eq(ClearUp(win, R(640, 142, 728, 228), 680, 4), nil, "not quite")
	eq(ClearUp(nil, R(640, 142, 728, 228), 768, 4), nil)
end)

-- Blizzard's Issue Reporter (Blizzard_PTRFeedback): a 80 x 32 box, its bug button in a
-- body below it and a border around it, at `x, y` (screen pixels, bottom left) and `scale`.
local function IssueReporter(x, y, scale)
	local s = scale or 1
	local r = NewWidget("Frame", nil, UIParent)
	r.scale = s
	r.rect = { x / s, y / s, 80 / s, 32 / s }
	r.Border = NewWidget("Frame", nil, r); r.Border.rect = { (x - 4) / s, (y - 4) / s, 88 / s, 40 / s }
	r.Body = NewWidget("Frame", nil, r); r.Body.rect = { x / s, (y - 50) / s, 80 / s, 50 / s }
	r.ReportBug = NewWidget("Button", nil, r); r.ReportBug.rect = { (x + 13) / s, (y - 46) / s, 54 / s, 40 / s }
	PTR_IssueReporter = r
	return r
end

test("Issue Reporter: the window steps above it when it opens, never over a player's choice", function()
	WithUI(function()
		-- Where Blizzard puts it by default: bottom centre, a quarter up the screen.
		IssueReporter(643, 192)
		local UI = LoadUI()
		UI.Toggle()
		local main = OlympusFrame
		-- The window (bottom 212) and its tabs (down to 182) cover it (142 to 228): up 50.
		eq(Anchor(main), "CENTER UIParent CENTER 0 90", "moved up just enough")
		eq(main:GetBottom() - 30, 232, "tabs 4 above the reporter")
		UI.Toggle(); UI.Toggle()
		eq(Anchor(main), "CENTER UIParent CENTER 0 90", "clear now: not moved again")
		-- Dragged onto it by the player: stays there, now and when opened again.
		main.scripts.OnDragStart(main)
		main:ClearAllPoints(); main:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 500, 200)
		main.scripts.OnDragStop(main)
		UI.Toggle(); UI.Toggle()
		eq(Anchor(main), "BOTTOMLEFT UIParent BOTTOMLEFT 500 200", "the player's place is kept")
	end)
	WithUI(function()
		-- Join screen (no tabs), reporter drawn at a smaller scale, our window at 0.8.
		GetGuildInfo = function() return nil end
		UIParent.scale = 0.8
		UIParent.rect = { 0, 0, 1366 / 0.8, 768 / 0.8 }
		IssueReporter(643, 192, 0.5)
		local UI = LoadUI()
		UI.Toggle()
		local main = OlympusFrame
		-- Bottom at (480 + 40 - 212) * 0.8 = 246.4 px, the reporter's top 228 + 4: already clear.
		eq(Anchor(main), "CENTER UIParent CENTER 0 40", "no tabs on the Join screen, nothing to clear")
		GetGuildInfo = function() return "Olympus II" end
		UI.Toggle(); UI.Toggle()
		-- With the tabs: bottom (308 - 30) * 0.8 = 222.4 px, needs 9.6 px = 12 of ours.
		local y = main.points[1][5]
		assert(math.abs(y - 52) < 0.001, "moved up 12 in its own scale, got " .. y)
	end)
	WithUI(function()
		-- Too high to step above, or off to the side, or hidden: left alone.
		local UI = LoadUI()
		IssueReporter(643, 620)
		UI.Toggle()
		eq(Anchor(OlympusFrame), "CENTER UIParent CENTER 0 40", "cannot clear it: stays")
		UI.Toggle()
		IssueReporter(20, 192)
		UI.Toggle()
		eq(Anchor(OlympusFrame), "CENTER UIParent CENTER 0 40", "not in the way")
		UI.Toggle()
		IssueReporter(643, 192).shown = false
		UI.Toggle()
		eq(Anchor(OlympusFrame), "CENTER UIParent CENTER 0 40", "hidden")
	end)
	WithUI(function()
		-- Shown the moment it was made, before the client laid it out: looked at once more
		-- on the next frame, and only once.
		IssueReporter(643, 192)
		local savedAfter, later = C_Timer.After, {}
		C_Timer.After = function(_, fn) later[#later + 1] = fn end
		local rect = UIParent.rect
		UIParent.rect = nil
		local UI = LoadUI()
		UI.Toggle()
		UIParent.rect = rect
		C_Timer.After = savedAfter
		eq(#later, 1, "one retry")
		eq(Anchor(OlympusFrame), "CENTER UIParent CENTER 0 40", "nothing to measure yet")
		later[1]()
		eq(Anchor(OlympusFrame), "CENTER UIParent CENTER 0 90", "moved on the next frame")
	end)
	WithUI(function()
		-- Docked: stays glued to the guild window, whatever covers it.
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
		CommunitiesFrame.rect = { 0, 150, 500, 426 }
		CommunitiesFrame.shown = true
		IssueReporter(560, 192)
		local UI = LoadUI()
		UI.OpenDocked(CommunitiesFrame, "census", true)
		eq(Anchor(OlympusFrame), "TOPLEFT CommunitiesFrame TOPRIGHT -2 0")
	end)
end)

test("Issue Reporter: the person panel steps above it too", function()
	WithUI(function()
		local UI = LoadUI()
		UI.Toggle()
		-- Window at 514..852 x 212..636; the panel hangs off its right, 850..1080 x 398..608.
		-- The reporter with its border: 376..416.
		IssueReporter(900, 380)
		UI.ShowPerson({ name = "Asmongold-Realm", class = "WARRIOR", level = 25, online = true })
		local person = OlympusPersonFrame
		eq(Anchor(OlympusFrame), "CENTER UIParent CENTER 0 40", "the window is not in the way: not moved")
		eq(Anchor(person), "TOPLEFT OlympusFrame TOPRIGHT -2 -6", "panel up 22: 4 above the reporter")
		eq(person.name.wrap, false, "long names are not wrapped over the lines below")
		eq(person.name.font, "GameFontNormalLarge", "a short name keeps the large font")
		UI.ShowPerson({ name = "Bellattrixxlestrange-ClassicBetaPvP" })
		eq(person.name.font, "GameFontNormal", "a long one drops to the normal font")
		PTR_IssueReporter = nil
		UI.ShowPerson({ name = "Asmongold-Realm" })
		eq(Anchor(person), "TOPLEFT OlympusFrame TOPRIGHT -2 -28", "back in its place without it")
	end)
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
