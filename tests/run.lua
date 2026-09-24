-- Offline tests for the pure parts of the addon (codec, election, roster scan, aggregation).
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
for _, file in ipairs({ "Bootstrap", "Locales", "Core", "Diagnostics", "Codec", "Zones", "Data", "Roster", "Comm", "Map", "Layers", "Positions", "Decree", "Channels", "Inspect", "Recruit", "Views" }) do
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
	function f:IsShown() return self.shown end
	function f:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
	function f:HookScript(kind, fn) self.hooks[kind] = self.hooks[kind] or {}; table.insert(self.hooks[kind], fn) end
	function f:Run(kind) for _, fn in ipairs(self.hooks[kind] or {}) do fn(self) end end
	function f:Show() self.shown = true; self:Run("OnShow") end
	function f:Hide() self.shown = false; self:Run("OnHide") end
	return f
end

-- Loads GuildFrame.lua with fresh state into a namespace of its own. Its events and LOGIN
-- are fired by hand; the Olympus window is a stand-in that remembers where it is docked.
local function LoadGuildFrame()
	local world = { events = {}, login = {}, buttons = {}, dock = { shown = false } }
	local dock = world.dock
	local gns = setmetatable({}, { __index = ns })
	gns.RegisterEvent = function(event, fn) world.events[event] = world.events[event] or {}; table.insert(world.events[event], fn) end
	gns.On = function(name, fn) if name == "LOGIN" then table.insert(world.login, fn) end end
	gns.MakeRoundButton = function(name, parent, size)
		local b = setmetatable({ name = name, parent = parent, size = size, scripts = {} }, { __index = function() return function() end end })
		function b:SetScript(kind, fn) self.scripts[kind] = fn end
		function b:SetPoint(...) self.point = { ... } end
		function b:Click() self.scripts.OnClick(self) end
		world.buttons[#world.buttons + 1] = b
		return b
	end
	gns.UI = {
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
		FriendsFrame:Show(); FriendsFrame:Hide()
		eq(w.dock.shown, true, "the Social window closing leaves it open")
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
-- Channels (Channels.lua): [Olympus] / [Captains] / [Lords] over the hidden channel
---------------------------------------------------------------------------

CHAT_LINES = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) CHAT_LINES[#CHAT_LINES + 1] = t end }
UnitClass = function() return "Paladin", "PALADIN" end
local Chan = ns.Channels
local ITEM = "|cff0070dd|Hitem:19019::::::::60:::::::::|h[Thunderfury]|h|r"
local ITEM_Q = "|cnIQ4:|Hitem:19019::::::::60:::::::::|h[Thunderfury]|h|r"

-- Runs fn(printed) with guild rank R in Olympus II (or in `guild`); ns.Print goes to `printed`.
local function AsRank(R, fn, guild)
	local savedInfo, savedPrint = GetGuildInfo, ns.Print
	local printed = {}
	GetGuildInfo = function() return guild or MY_GUILD, "rankname", R end
	ns.Print = function(msg) printed[#printed + 1] = tostring(msg) end
	local ok, err = pcall(fn, printed)
	GetGuildInfo, ns.Print = savedInfo, savedPrint
	if not ok then error(err, 0) end
end

-- Runs fn(sent) with the chat lane stubbed: SendChat records the message and reports it sent.
local function WithLane(fn, ready)
	local C = ns.Comm
	local savedReady, savedSend = C.ChannelReady, C.SendChat
	local sent = {}
	C.ChannelReady = function() return ready ~= false end
	C.SendChat = function(msg, done) sent[#sent + 1] = msg; done(true); return true end
	local ok, err = pcall(fn, sent)
	C.ChannelReady, C.SendChat = savedReady, savedSend
	if not ok then error(err, 0) end
end

local function Msg(tier, guild, id, text)
	return Codec.EncodeChat(tier, guild, id, "PA", text or "hi")
end

test("chat message round trip: separators, escapes and unicode", function()
	local text = "ataque em ~Tarren:Mill, já! a=b " .. ITEM .. " e " .. ITEM_Q
	eq(Codec.SanitizeChat(text), text, "nothing to neutralise")
	local d = Codec.DecodeChat(Codec.EncodeChat("C", "Olympus II", 42, "PA", text))
	eq(d.tier, "C"); eq(d.guild, "Olympus II"); eq(d.id, 42); eq(d.class, "PA"); eq(d.text, text)
	eq(Codec.DecodeChat(Codec.EncodeChat("A", "Olympus", 7, "", "oi")).class, nil, "no class")
	eq(Codec.DecodeChat(Codec.EncodeChat("A", "Olympus", 12345, "", "oi")).id, 2345, "id wraps at 10000")
	eq(Codec.DecodeChat("M1~X~Olympus~1~~hi"), nil, "unknown tier")
	eq(Codec.DecodeChat("M1~A~Oly|mpus~1~~hi"), nil, "| in the guild")
	eq(Codec.DecodeChat("M1~A~Olympus~12345~~hi"), nil, "5 digit id")
	eq(Codec.DecodeChat("M1~A~Olympus~1~~   "), nil, "whitespace only")
	eq(Codec.DecodeChat("M1~A~Olympus~1~~" .. ("x"):rep(240)), nil, "over 255 bytes")
	eq(Codec.DecodeChat("M1~A~" .. ("Olympus"):rep(4) .. "~1~~hi"), nil, "guild over 24 characters")
	-- WoW counts characters: 24 of them with an accent are 25 bytes.
	local accents = "Olympus Irmãos de Sangue"
	eq(#accents, 25)
	eq(Codec.DecodeChat(Codec.EncodeChat("A", accents, 1, "", "oi")).guild, accents, "chat")
	eq(Codec.DecodeReport(Codec.EncodeReport({ guild = accents, total = 1, online = 1 })).guild, accents, "report")
	eq(Codec.DecodeChat("M1~A~" .. ("\128"):rep(80) .. "~1~~hi"), nil, "bytes are limited too")
end)

test("chat sanitizer keeps item and spell links and neutralises every other escape", function()
	local S = Codec.SanitizeChat
	local spell = "|cff71d5ff|Hspell:8690|h[Hearthstone]|h|r"
	eq(S("hi " .. ITEM .. " ok"), "hi " .. ITEM .. " ok")
	eq(S(ITEM_Q), ITEM_Q); eq(S(spell), spell)
	eq(S("|TInterface\\Icons\\x:99|t"), "||TInterface\\Icons\\x:99||t", "texture")
	eq(S("|cffff0000fake|r"), "||cffff0000fake||r", "bare colour")
	eq(S("|HurlIndex:24|h[x]|h"), "||HurlIndex:24||h[x]||h", "other link types")
	eq(S("|A:atlas:16:16|a"), "||A:atlas:16:16||a", "atlas")
	eq(S("|Kq1|k"), "||Kq1||k", "protected name")
	eq(S("a|nb"), "a||nb", "raw |n")
	eq(S("a\nb\0c"), "abc", "control bytes")
	-- A newline inside a link's name would fake a second chat line: not a link we keep.
	eq(S("ok |Hitem:1|h[x\n[Olympus]|h [Zeus] <Olympus>: gold"), "ok ||Hitem:1||h[x[Olympus]||h [Zeus] <Olympus>: gold", "newline in a link")
	eq(S("|Hitem:1|h[a\0b]|h"), "||Hitem:1||h[ab]||h", "NUL in a link")
	eq(S("a||b"), "a||b", "escaped pipe kept")
	for _, x in ipairs({ "hi " .. ITEM, "|T x |t", "a||b|", "ção ~ : , = |", ITEM_Q .. "|" }) do
		local once = S(x)
		eq(S(once), once, "idempotent: " .. x)
	end
end)

test("long chat splits at safe points and every part fits one message", function()
	local guild = "Olympus Poseidon Real"
	eq(#guild, 21)
	local text = Codec.SanitizeChat(("ação "):rep(50) .. ITEM .. (" é"):rep(40))
	eq(#text, 530)
	local parts, cut = Codec.SplitChat(text, Codec.ChatBudget(guild, "PA"), Codec.CHAT_PARTS)
	eq(#parts, 3); eq(cut, false)
	local whole = false
	for _, p in ipairs(parts) do
		local b = p:byte(1)
		assert(not (b >= 128 and b < 192), "part starts inside a character")
		local msg = Codec.EncodeChat("A", guild, 9999, "PA", p)
		assert(msg and #msg <= 250, "message too long")
		eq(Codec.DecodeChat(msg).text, p)
		if p:find(ITEM, 1, true) then whole = true end
	end
	assert(whole, "the link stayed whole")
	eq((table.concat(parts, " "):gsub("%s+", " ")), (text:gsub("%s+", " ")), "nothing lost")
	local q = Codec.SplitChat(("x"):rep(90) .. ITEM .. ("y"):rep(20), 120, 3)
	eq(#q, 2); eq(q[1], ("x"):rep(90)); eq(q[2], ITEM .. ("y"):rep(20))
	for _, p in ipairs(Codec.SplitChat(("ç"):rep(150), 101, 3)) do eq(#p % 2, 0, "cut inside a character") end
	local long, lost = Codec.SplitChat(("x"):rep(1000), 200, 3)
	eq(#long, 3); eq(lost, true)
	-- The space in a link's name is not a place to cut.
	local named = "|cff0070dd|Hitem:19019::::::::60:::::::::|h[Thunderfury Blessed Blade]|h|r"
	local w = Codec.SplitChat(("y"):rep(40) .. named .. ("y"):rep(100), 120, 3)
	assert(w[1]:find(named, 1, true), "link cut at its space: " .. w[1])
end)

test("channel levels follow the realm hierarchy", function()
	eq(Chan.LevelOf("Olympus", 0), 3); eq(Chan.LevelOf("Olympus", 1), 3); eq(Chan.LevelOf("Olympus", 2), 1)
	eq(Chan.LevelOf("Olympus II", 0), 3); eq(Chan.LevelOf("Olympus II", 1), 2); eq(Chan.LevelOf("Olympus II", 3), 1)
	eq(Chan.LevelOf("Horde Pals", 0), 0)
	local function uses()
		local s = ""
		for _, t in ipairs(Chan.ORDER) do if Chan.CanUse(t) then s = s .. t end end
		return s
	end
	AsRank(0, function() eq(uses(), "ACL", "guild master") end)
	AsRank(1, function() eq(uses(), "AC", "officer") end)
	AsRank(3, function() eq(uses(), "A", "member") end)
	AsRank(0, function() eq(uses(), "", "outside Olympus") end, "House of Guedes")
end)

test("sending is gated with a clear answer", function()
	CHAT_LINES = {}
	WithLane(function(sent)
		AsRank(0, function(printed)
			local ok, why = Chan.Send("A", "hi", 100)
			eq(ok, false); eq(why, "member"); eq(printed[1], ns.L.MEMBERS_ONLY)
		end, "House of Guedes")
		AsRank(3, function()
			eq(select(2, Chan.Send("C", "hi", 100)), "rank")
			eq(select(2, Chan.Send("L", "hi", 100)), "rank")
		end)
		AsRank(1, function(printed)
			eq(select(2, Chan.Send("L", "hi", 100)), "rank")
			eq(printed[1], ns.L.CHAN_ONLY_LORDS:format("Lords"))
			eq(select(2, Chan.Send("C", " \n ", 100)), "empty")
			eq(printed[2], ns.L.CHAN_USAGE:format("/olc", "Captains"))
			C_ChatInfo = { InChatMessagingLockdown = function() return true end }
			eq(select(2, Chan.Send("C", "hi", 100)), "lockdown")
			C_ChatInfo = nil
			local savedRoom = ns.Comm.ChatRoom
			ns.Comm.ChatRoom = function() return 0 end
			eq(select(2, Chan.Send("C", "hi", 100)), "busy")
			ns.Comm.ChatRoom = savedRoom
		end)
		eq(#sent, 0, "nothing sent")
	end)
	WithLane(function(sent)
		AsRank(1, function() eq(select(2, Chan.Send("C", "hi", 100)), "ready") end)
		eq(#sent, 0)
	end, false)
	ns.db.chatNoticeShown = nil
	WithLane(function(sent)
		AsRank(1, function(printed)
			local ok, why = Chan.Send("C", "reunir em " .. ITEM, 100)
			eq(ok, true); eq(why, "ok")
			eq(printed[#printed], ns.L.CHAN_NOTICE, "not-encrypted notice, once")
		end)
		eq(#sent, 1)
		eq(sent[1]:sub(1, 16), "M1~C~Olympus II~")
		assert(sent[1]:find("~PA~reunir em " .. ITEM, 1, true), sent[1])
		eq(#CHAT_LINES, 1, "local echo")
		assert(CHAT_LINES[1]:find("[Captains]", 1, true) and CHAT_LINES[1]:find(ITEM, 1, true), CHAT_LINES[1])
	end)
	eq(ns.db.chatNoticeShown, true)
end)

test("sender ranks are verified on receipt, never taken from the message", function()
	ns.Roster.Scan()
	ns.rdb.guilds = {
		["Olympus"] = { guild = "Olympus", leader = "Asmongold", officers = { { name = "Capt" } }, total = 1000, online = 1, zones = {}, t = os.time() },
		["Olympus Bad"] = { guild = "Olympus Bad", leader = "X", conflict = true, total = 1, online = 1, zones = {}, t = os.time() },
	}
	eq(ns.Data.Receive({ guild = "Olympus Zeus", total = 5, online = 1, zones = {} }, "Liar2-Realm"), true)
	CHAT_LINES = {}
	AsRank(0, function()
		local n = 0
		local function R(sender, tier, guild, dist)
			n = n + 1
			return select(2, Chan.Receive(dist or "CHANNEL", sender, Msg(tier, guild, n), 1000 + n))
		end
		eq(R("Member2", "C", MY_GUILD), "ok", "our officer on [Captains]")
		eq(R("Member2", "L", MY_GUILD), "rank", "our officer is not a Lord")
		eq(R("Member1", "L", MY_GUILD), "ok", "our guild master")
		eq(R("Member500", "A", MY_GUILD), "ok", "our member on [Olympus]")
		eq(R("Member500", "C", MY_GUILD), "rank", "our member on [Captains]")
		eq(R("Stranger-Realm", "A", MY_GUILD), "forged", "not in our roster")
		eq(R("Member3", "A", "Olympus"), "forged", "a guildmate speaking for another guild")
		eq(R("Asmongold", "L", "Olympus"), "ok", "the King, from the report")
		eq(R("Capt", "L", "Olympus"), "ok", "officer of <Olympus>, from the report")
		eq(R("Random", "A", "Olympus"), "ok", "unverified members can use [Olympus]")
		eq(R("Random", "C", "Olympus"), "unverified")
		eq(R("X", "C", "Olympus Bad"), "unverified", "conflicting report")
		eq(R("Hordie", "A", "Horde Pals"), "bad", "not an Olympus guild")
		eq(R("Liar2", "A", "Olympus Fake"), "forged", "already reported another guild")
		eq(R("Member2", "A", MY_GUILD, "GUILD"), "dist")
	end)
	eq(#CHAT_LINES, 6)
	assert(CHAT_LINES[4]:find("[Lords]", 1, true) and CHAT_LINES[4]:find("<Olympus>", 1, true), CHAT_LINES[4])
	ns.rdb.guilds = {}
end)

test("players below a tier never see it", function()
	ns.rdb.chat = nil
	CHAT_LINES = {}
	local m = Msg("L", MY_GUILD, 777, "only for lords")
	AsRank(3, function()
		local shown, why = Chan.Receive("CHANNEL", "Member1", m, 2000)
		eq(shown, false); eq(why, "tier")
		eq(#Chan.History("L"), 0)
	end)
	eq(#CHAT_LINES, 0, "no line")
	eq(ns.rdb.chat, nil, "nothing stored")
	AsRank(0, function()
		eq((Chan.Receive("CHANNEL", "Member1", m, 2001)), true)
		eq(#Chan.History("L"), 1)
	end)
	eq(#CHAT_LINES, 1)
	-- A member doesn't read [Captains], and a Captain outside <Olympus> doesn't read [Lords].
	AsRank(3, function()
		eq(select(2, Chan.Receive("CHANNEL", "Member2", Msg("C", MY_GUILD, 778, "only for captains"), 2002)), "tier")
	end)
	AsRank(1, function()
		eq(select(2, Chan.Receive("CHANNEL", "Member1", Msg("L", MY_GUILD, 779, "lords again"), 2003)), "tier")
	end)
	eq(ns.rdb.chat.C, nil, "nothing stored")
	eq(#ns.rdb.chat.L, 1)
	-- Before our roster is read, even a real officer claiming our guild gets [Olympus] only.
	local byName = ns.Roster.byName
	ns.Roster.byName = nil
	AsRank(0, function()
		eq(select(2, Chan.Receive("CHANNEL", "Member3", Msg("C", MY_GUILD, 780), 2004)), "unverified")
		eq((Chan.Receive("CHANNEL", "Member3", Msg("A", MY_GUILD, 781), 2005)), true)
	end)
	ns.Roster.byName = byName
	C_FriendList = { IsIgnored = function() return true end }
	AsRank(0, function()
		eq(select(2, Chan.Receive("CHANNEL", "Member4", Msg("A", MY_GUILD, 782), 2006)), "ignored")
	end)
	C_FriendList = nil
	eq(#CHAT_LINES, 2)
end)

test("duplicate ids are shown once", function()
	AsRank(1, function()
		local m = Msg("A", MY_GUILD, 4242)
		eq((Chan.Receive("CHANNEL", "Member7", m, 3000)), true)
		eq(select(2, Chan.Receive("CHANNEL", "Member7", m, 3001)), "dup")
		eq((Chan.Receive("CHANNEL", "Member8", m, 3002)), true, "same id from another sender")
		eq((Chan.Receive("CHANNEL", "Member7", Msg("A", MY_GUILD, 4242, "after a /reload"), 3003)), true, "same id, new text")
		Chan.Prune(3000 + 121)
		eq((Chan.Receive("CHANNEL", "Member7", m, 3000 + 121)), true, "forgotten after the window")
	end)
end)

test("rate limits: sender cooldown and receiver burst guard", function()
	WithLane(function()
		AsRank(3, function(printed)
			eq((Chan.Send("A", "one", 4000)), true)
			local ok, why = Chan.Send("A", "two", 4001)
			eq(ok, false); eq(why, "fast"); eq(printed[#printed], ns.L.CHAN_TOO_FAST)
			eq((Chan.Send("A", "three", 4001.5)), true)
		end)
	end)
	AsRank(3, function()
		for i = 1, 6 do eq((Chan.Receive("CHANNEL", "Member9", Msg("A", MY_GUILD, 100 + i), 5000)), true, "burst " .. i) end
		eq(select(2, Chan.Receive("CHANNEL", "Member9", Msg("A", MY_GUILD, 107), 5000)), "rate")
		eq((Chan.Receive("CHANNEL", "Member9", Msg("A", MY_GUILD, 108), 5000 + 1.2)), true, "one more after 1.2 s")
		for i = 1, 60 do
			eq((Chan.Receive("CHANNEL", "Member" .. (200 + i), Msg("A", MY_GUILD, 1), 6000 + i * 0.5)), true, "sender " .. i)
		end
		eq(select(2, Chan.Receive("CHANNEL", "Member261", Msg("A", MY_GUILD, 1), 6030.5)), "flood")
	end)
end)

test("muted tiers stay out of chat but keep history", function()
	ns.db.chatMute, ns.rdb.chat = nil, nil
	AsRank(1, function(printed)
		Chan.ToggleMute("captains")
		eq(ns.db.chatMute.C, true)
		eq(printed[1], ns.L.CHAN_MUTED:format("Captains", "captains"))
		CHAT_LINES = {}
		local shown, why = Chan.Receive("CHANNEL", "Member2", Msg("C", MY_GUILD, 5150), 7000)
		eq(shown, false); eq(why, "muted")
		eq(#CHAT_LINES, 0, "no line"); eq(#Chan.History("C"), 1, "kept in history")
		eq(Chan.Stats().muted[1], "C")
		Chan.ToggleMute("capitães")
		eq(ns.db.chatMute.C, nil)
		Chan.ToggleMute("nonsense")
		eq(printed[#printed], ns.L.CHAN_MUTE_USAGE)
		-- "all" would read as every channel: [Olympus] is muted with its own name.
		Chan.ToggleMute("olympus")
		eq(printed[#printed], ns.L.CHAN_MUTED:format("Olympus", "olympus"))
		Chan.ToggleMute("all")
		eq(ns.db.chatMute.A, nil, "'all' still works")
		Chan.ToggleMute("captains")
		WithLane(function() eq((Chan.Send("C", "back", 7001)), true) end)
		eq(ns.db.chatMute.C, nil, "sending unmutes")
		eq(#CHAT_LINES, 1, "own line shown")
	end)
end)

test("chat history is per tier and capped", function()
	ns.rdb.chat = nil
	AsRank(0, function()
		for i = 1, 150 do
			Chan.Receive("CHANNEL", "Member" .. (300 + i), Msg("A", MY_GUILD, i, "line " .. i), 8000 + i * 1.1)
		end
		local h = Chan.History("A")
		eq(#h, 100); eq(h[1].text, "line 51", "oldest gone"); eq(h[100].text, "line 150")
		eq(h[100].sender, "Member450-Realm"); eq(h[100].guild, MY_GUILD); eq(h[100].class, "PA")
		eq((Chan.Receive("CHANNEL", "Member2", Msg("C", MY_GUILD, 1, "captains only"), 8200)), true)
		eq(#Chan.History("C"), 1); eq(#Chan.History("A"), 100, "separate lists")
		eq(ns.rdb.chat.A, h, "stored per realm")
	end)
	AsRank(3, function()
		eq(#Chan.History("C"), 0)
		eq(next(Chan.History("L")), nil)
	end)
end)

test("a report never vouches for its own sender", function()
	ns.Roster.Scan()
	ns.rdb.guilds = {}
	local D = ns.Data
	local LEVELS = "~0,0,0,0,0,0,0~~"
	local function Report(guild, leader, officers, sender)
		return D.Receive(Codec.DecodeReport("R2~" .. guild .. "~50~5~" .. leader .. "~1~1~~" .. LEVELS .. officers), sender)
	end
	local n = 0
	local function Line(sender, tier, guild)
		n = n + 1
		return select(2, Chan.Receive("CHANNEL", sender, Msg(tier, guild, n), 9000 + n))
	end
	CHAT_LINES = {}
	AsRank(0, function()
		-- A made-up guild naming its sender as leader: one /run, no guild needed.
		eq(Report("Olympus Lords", "Evil", "", "Evil-Realm"), true)
		eq(D.KnownRank("Evil-Realm", "Olympus Lords"), nil, "its own report")
		eq(Line("Evil", "L", "Olympus Lords"), "unverified")
		-- A member sends his guild's report again, same leader and size, and adds himself.
		eq(Report("Olympus Zeus", "Zeus", "Capt2:1:0", "Scribe-Realm"), true)
		eq(D.KnownRank("Capt2-Realm", "Olympus Zeus"), 1, "named by someone else")
		eq(Report("Olympus Zeus", "Zeus", "Capt2:1:0,Grunt:1:0", "Grunt-Realm"), true)
		eq(ns.rdb.guilds["Olympus Zeus"].conflict, true, "an added officer is a conflict")
		eq(Line("Grunt", "C", "Olympus Zeus"), "unverified")
		-- The same on <Olympus>, whose officers are Lords.
		eq(Report("Olympus", "King", "Duke:1:0", "Herald-Realm"), true)
		eq(Report("Olympus", "King", "Duke:1:0,Peon:1:0", "Peon-Realm"), true)
		eq(Line("Peon", "L", "Olympus"), "unverified")
		-- An elected reporter who leads the guild: proven by the report someone else sent before.
		eq(Report("Olympus Ares", "Ares", "", "Squire-Realm"), true)
		eq(Report("Olympus Ares", "Ares", "", "Ares-Realm"), true)
		eq(D.KnownRank("Ares-Realm", "Olympus Ares"), 0, "named by the report before")
		eq(Report("Olympus Ares", "Ares", "", "Ares-Realm"), true)
		eq(D.KnownRank("Ares-Realm", "Olympus Ares"), 0, "kept while the reporter stays")
		eq(Line("Ares", "L", "Olympus Ares"), "ok")
	end)
	eq(#CHAT_LINES, 1)
	ns.rdb.guilds = {}
end)

test("guild names ignore case, so another spelling can't pass for a guild", function()
	ns.Roster.Scan()
	ns.rdb.guilds = {}
	local function Report(guild, officers, sender)
		return ns.Data.Receive(Codec.DecodeReport("R2~" .. guild .. "~900~90~King~1~9~~~0,0,0,0,0,0,0~~" .. officers), sender)
	end
	AsRank(0, function()
		eq(select(2, Chan.Receive("CHANNEL", "Mimic", Msg("A", "olympus ii", 1), 9500)), "forged", "our guild, other capitals")
		eq(select(2, Chan.Receive("CHANNEL", "Member5", Msg("A", "olympus ii", 3), 9500)), "forged", "even from a guildmate")
		eq(Report("OLYMPUS II", "", "Mimic2-Realm"), false, "no report about our guild in any spelling")
		eq(Report("Olympus", "Duke:1:0", "Herald2-Realm"), true)
		eq(Report("OLYMPUS", "Evil2:1:0", "Scribe2-Realm"), true)
		eq(ns.rdb.guilds.OLYMPUS.conflict, true, "a second spelling of a fresh guild")
		eq(select(2, Chan.Receive("CHANNEL", "Evil2", Msg("L", "OLYMPUS", 2), 9501)), "unverified")
	end)
	ns.rdb.guilds = {}
end)

test("two spammers can't silence the other channels, nor everyone else", function()
	ns.db.chatMute = nil
	AsRank(0, function()
		-- Two unmodified clients at full speed in [Olympus] for most of a minute.
		local t
		for i = 1, 50 do
			t = 20000 + i * 1.2
			Chan.Receive("CHANNEL", "Member600", Msg("A", MY_GUILD, i, "spam " .. i), t)
			Chan.Receive("CHANNEL", "Member601", Msg("A", MY_GUILD, i, "spam " .. i), t + 0.1)
		end
		eq((Chan.Receive("CHANNEL", "Member1", Msg("L", MY_GUILD, 1, "lords"), t + 0.2)), true, "[Lords]")
		eq((Chan.Receive("CHANNEL", "Member2", Msg("C", MY_GUILD, 1, "captains"), t + 0.3)), true, "[Captains]")
		eq((Chan.Receive("CHANNEL", "Member602", Msg("A", MY_GUILD, 1, "hello"), t + 0.4)), true, "a third member in [Olympus]")
		eq(select(2, Chan.Receive("CHANNEL", "Member600", Msg("A", MY_GUILD, 51, "spam 51"), t + 0.5)), "flood", "the spammer waits")
		-- A muted channel takes no room from the flood guard.
		ns.db.chatMute = { A = true }
		for i = 1, 70 do Chan.Receive("CHANNEL", "Member" .. (700 + i), Msg("A", MY_GUILD, 1, "muted"), 30000 + i * 0.1) end
		ns.db.chatMute = nil
		eq((Chan.Receive("CHANNEL", "Member800", Msg("A", MY_GUILD, 1, "after"), 30008)), true)
	end)
end)

test("chat lane goes first but never starves or evicts reports", function()
	local C = ns.Comm
	local out = {}
	local savedGuild = GetGuildInfo
	C_ChatInfo = {
		SendAddonMessage = function(_, msg) out[#out + 1] = msg end,
		SendAddonMessageLogged = function(_, msg) out[#out + 1] = "logged " .. msg end,
	}
	GetChannelName = function() return 5 end
	local ok, err = pcall(function()
		C.JoinChannel()
		eq(C.ChannelReady(), true)
		for _ = 1, 200 do
			if C.Stats().queue == 0 and C.Stats().chatQueue == 0 then break end
			C.Pump() -- whatever earlier tests queued
		end
		wipe(out)
		local results = {}
		for i = 1, 3 do C.Send("CHANNEL", "X" .. i .. "~r") end
		for i = 1, 2 do eq(C.SendChat("M1~A~Olympus II~" .. i .. "~~hi", function(sent) results[i] = sent end), true) end
		for _ = 1, 5 do C.Pump() end
		eq(table.concat(out, ","), "logged M1~A~Olympus II~1~~hi,X1~r,logged M1~A~Olympus II~2~~hi,X2~r,X3~r")
		eq(results[1], true); eq(results[2], true)
		for i = 1, 70 do C.Send("CHANNEL", "R" .. i) end
		eq(C.ChatRoom(), 6, "reports never take the chat lane's room")
		local dropped
		for i = 1, 6 do eq(C.SendChat("M1~A~Olympus II~9~~x", i == 6 and function(sent) dropped = sent end or nil), true) end
		eq(C.SendChat("M1~A~Olympus II~9~~x"), false, "lane full")
		eq(C.Stats().queue, 60); eq(C.Stats().chatQueue, 6)
		assert(ns.StatusText():find("lane=6", 1, true), "chat line in /oly status")
		-- Out of Olympus: both lanes are dropped and the sender hears about it.
		GetGuildInfo = function() return "House of Guedes" end
		C.Pump()
		GetGuildInfo = savedGuild
		eq(C.Stats().queue, 0); eq(C.Stats().chatQueue, 0); eq(dropped, false)
	end)
	GetGuildInfo, C_ChatInfo, GetChannelName = savedGuild, nil, nil
	if not ok then error(err, 0) end
end)

test("chat line shows tier, clickable name, guild and neutralised escapes", function()
	local line = Chan.FormatLine("C", "Bob-Other", "Olympus II", "PA", "hi |Tx|t")
	assert(line:find("[Captains]", 1, true), line)
	assert(line:find("|Hplayer:Bob-Other|h[", 1, true), line)
	assert(line:find("<Olympus II>", 1, true), line)
	assert(line:find("||Tx||t", 1, true), line)
	RAID_CLASS_COLORS = { PALADIN = { colorStr = "fff58cba" } }
	line = Chan.FormatLine("A", "Bob-Realm", "Olympus", "PA", "x")
	RAID_CLASS_COLORS = nil
	assert(line:find("[Olympus] |Hplayer:Bob-Realm|h[|cfff58cbaBob|r]|h <Olympus>: x", 1, true), line)
end)

test("slash commands reach the right channel", function()
	eq(SLASH_OLYMPUSALL1, "/ol"); eq(SLASH_OLYMPUSCAPTAINS1, "/olc"); eq(SLASH_OLYMPUSLORDS1, "/oll")
	local savedTime, clock = GetTime, 50000
	GetTime = function() return clock end
	local ok, err = pcall(function()
		WithLane(function(sent)
			AsRank(0, function()
				local function Run(fn, arg, prefix)
					clock = clock + 10 -- past the 1.5 s gap
					local before = #sent
					fn(arg)
					eq(#sent, before + 1, arg)
					eq(sent[#sent]:sub(1, #prefix), prefix, arg)
				end
				Run(SlashCmdList.OLYMPUSALL, "hi", "M1~A~")
				Run(SlashCmdList.OLYMPUSCAPTAINS, "hi", "M1~C~")
				Run(SlashCmdList.OLYMPUSLORDS, "hi", "M1~L~")
				Run(SlashCmdList.OLYMPUS, "all hi", "M1~A~")
				Run(SlashCmdList.OLYMPUS, "captains hi", "M1~C~")
				Run(SlashCmdList.OLYMPUS, "lords hi", "M1~L~")
			end)
		end)
		ns.db.chatMute = nil
		AsRank(0, function()
			SlashCmdList.OLYMPUS("mute lords")
			eq(ns.db.chatMute.L, true)
			SlashCmdList.OLYMPUS("mute lords")
			eq(ns.db.chatMute.L, nil)
			SlashCmdList.OLYMPUS("mute olympus")
			eq(ns.db.chatMute.A, true)
			SlashCmdList.OLYMPUS("mute olympus")
			eq(ns.db.chatMute.A, nil)
		end)
	end)
	GetTime = savedTime
	if not ok then error(err, 0) end
end)

-- Comm.lua and Channels.lua loaded into a namespace of their own, like GuildFrame.lua above:
-- lines go through the real event, the M1 handler and Receive.
test("chat lines arrive through CHAT_MSG_ADDON_LOGGED, without our echo or blocked players", function()
	local events, login = {}, {}
	local cns = setmetatable({}, { __index = ns })
	cns.RegisterEvent = function(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end
	cns.On = function(name, fn) if name == "LOGIN" then table.insert(login, fn) end end
	cns.After, cns.Every = function() end, function() end
	local slash = { SlashCmdList.OLYMPUSALL, SlashCmdList.OLYMPUSCAPTAINS, SlashCmdList.OLYMPUSLORDS }
	C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
	ns.db.chatMute = nil
	local ok, err = pcall(function()
		assert(loadfile(ADDON_DIR .. "Comm.lua"))("Olympus", cns)
		assert(loadfile(ADDON_DIR .. "Channels.lua"))("Olympus", cns)
		for _, fn in ipairs(login) do fn() end
		eq(events.CHAT_MSG_ADDON_LOGGED and #events.CHAT_MSG_ADDON_LOGGED, 1, "listens to logged addon messages")
		local function Deliver(sender, id)
			for _, fn in ipairs(events.CHAT_MSG_ADDON_LOGGED) do fn(ns.PREFIX, Msg("A", MY_GUILD, id, "via event " .. id), "CHANNEL", sender) end
		end
		CHAT_LINES = {}
		AsRank(3, function()
			Deliver("Member40", 1)
			eq(#CHAT_LINES, 1, "one line")
			assert(CHAT_LINES[1]:find("via event 1", 1, true), CHAT_LINES[1])
			ns.Roster.byName["Tester-Realm"] = 3 -- we are in our own roster
			Deliver("Tester", 2)
			ns.Roster.byName["Tester-Realm"] = nil
			eq(#CHAT_LINES, 1, "our own echo is not shown twice")
			ns.db.blocked["member41-realm"] = true
			Deliver("Member41", 3)
			ns.db.blocked["member41-realm"] = nil
			eq(#CHAT_LINES, 1, "blocked player")
		end)
	end)
	SlashCmdList.OLYMPUSALL, SlashCmdList.OLYMPUSCAPTAINS, SlashCmdList.OLYMPUSLORDS = slash[1], slash[2], slash[3]
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
