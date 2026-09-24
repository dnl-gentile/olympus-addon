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
for _, file in ipairs({ "Bootstrap", "Locales", "Core", "Diagnostics", "Codec", "Zones", "Who", "Data", "Roster", "Comm", "Map", "Layers", "Positions", "Decree", "Channels", "Inspect", "Recruit", "Views" }) do
	local chunk = assert(loadfile(ADDON_DIR .. file .. ".lua"))
	chunk("Olympus", ns)
end
ns.db = { guilds = {}, log = {}, errors = {}, blocked = {}, demo = false, showMap = true }
ns.me = "Tester-Realm"
ns.realm = "Realm"
ns.rdb = { guilds = {} }
local CoreFire = ns.Fire -- the real one, for the tests that need INIT
function ns.Fire() end

---------------------------------------------------------------------------
local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1; print("  ok   " .. name)
	else failed = failed + 1; print("  FAIL " .. name .. "\n       " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

-- A stored report as if `...` (other senders) had each just reported the same ranks: ranks
-- from other guilds count only when someone else's recent report names them (Data.KnownRank).
local function Vouched(g, ...)
	local home, ranks = g.realm or "Realm", {}
	local function full(name) return name:find("-", 1, true) and name or (name .. "-" .. home) end
	for _, o in ipairs(g.officers or {}) do ranks[full(o.name)] = 1 end
	if g.leader then ranks[full(g.leader)] = 0 end
	g.vouch = {}
	for _, src in ipairs({ ... }) do g.vouch[src] = { t = g.t, sig = "fixture", ranks = ranks } end
	return g
end

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

test("summary keeps a stale guild's size, counts online and zones only while fresh", function()
	local now = os.time()
	ns.rdb.guilds = {
		["Olympus"] = { total = 1000, online = 200, zones = { m1453 = 150, m1429 = 50 }, t = now },
		["Olympus II"] = { total = 800, online = 100, zones = { m1453 = 100 }, t = now - 60 },
		["Olympus Old"] = { total = 500, online = 50, zones = { m1436 = 50 }, t = now - 3600 },
		["Olympus Gone"] = { total = 300, online = 30, zones = {}, t = now - ns.Data.KEEP - 1 },
		["Horde Pals"] = { total = 999, online = 999, zones = {}, t = now },
	}
	local s = ns.Data.Summary()
	eq(s.total, 2300, "the last report's size stays when its reporters log off")
	eq(s.online, 300, "online only from fresh reports"); eq(s.fresh, 2)
	eq(#s.guilds, 3, "older than KEEP is gone, non-Olympus never counts")
	eq(s.zoneList[1].key, "m1453"); eq(s.zoneList[1].count, 250)
	eq(#s.zoneList, 2, "a stale guild's zones are not on the map")
	eq(s.guilds[3].name, "Olympus Old", "stale sorted last")
	assert(ns.Data.DiscordText():find("2,300 soldiers"), "discord text")
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
	ns.rdb.guilds = { ["Olympus Zeus"] = Vouched({ total = 10, online = 1, zones = {}, t = os.time() - 3600, leader = "Zed", realm = "Realm" }, "W1-Realm", "W2-Realm") }
	eq(ns.Data.KnownRank("Zed-Realm", "Olympus Zeus"), nil, "report from an hour ago")
	Vouched(ns.rdb.guilds["Olympus Zeus"], "W1-Realm", "W2-Realm").t = os.time()
	for _, v in pairs(ns.rdb.guilds["Olympus Zeus"].vouch) do v.t = os.time() end
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
	ns.rdb.guilds = { ["Olympus"] = Vouched({ total = 1000, online = 1, zones = {}, t = os.time(), leader = "Kingy" }, "W1-Realm", "W2-Realm"),
		["Olympus II"] = Vouched({ total = 500, online = 1, zones = {}, t = os.time(), leader = "Lordy" }, "W1-Realm", "W2-Realm") }
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
	ns.rdb.guilds = { ["Olympus Zeus"] = Vouched({ total = 10, online = 1, zones = {}, t = os.time(), leader = "Zed", realm = "Realm",
		officers = { { name = "Capt", online = true, days = 0 } } }, "W1-Realm", "W2-Realm") }
	eq(ns.Data.KnownRank("Zed", "Olympus Zeus"), 0, "short name from our realm")
	eq(ns.Data.KnownRank("Zed-Realm", "Olympus Zeus"), 0)
	eq(ns.Data.KnownRank("Zed-Other", "Olympus Zeus"), nil, "namesake on another realm is not the Lord")
	eq(ns.Data.KnownRank("Capt-Other", "Olympus Zeus"), nil, "namesake officer rejected")
	eq(ns.Data.KnownRank("Capt-Realm", "Olympus Zeus"), 1)
	-- A guild reported from another realm: its short names belong to that realm.
	ns.rdb.guilds["Olympus Far"] = Vouched({ total = 10, online = 1, zones = {}, t = os.time(), leader = "Kay", realm = "Other" }, "W1-Other", "W2-Other")
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
		["Olympus"] = Vouched({ guild = "Olympus", leader = "Asmongold", officers = { { name = "Capt" } }, total = 1000, online = 1, zones = {}, t = os.time() }, "W1-Realm", "W2-Realm"),
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
		leaderClass = "WARRIOR", leaderLevel = 60, leaderZone = "tThe Temple of Atal'Hakkar",
		from = ("F"):rep(40), home = ("H"):rep(40) }
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
	eq(d.from, r.from, "the longest realm fits"); eq(d.home, r.home)
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
	-- Guilds seen with /who too, one of them also reported.
	ns.rdb.seen = { ["OLYMPUS VII"] = { online = 12, capped = true, t = os.time() }, ["Olympus"] = { online = 3, t = os.time() } }
	ns.UI = { StatusLine = function() return "status" end }
	for _, tab in ipairs({ "census", "realm", "decrees", "heraldry" }) do
		local lines, title = ns.Views.Build(tab)
		assert(#lines > 0 and title, tab)
	end
	ns.rdb.guilds, ns.rdb.seen = {}, nil
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
	function f:GetFrameLevel() return self.level or 5 end
	function f:GetEffectiveScale() return 1 end
	function f:GetAlpha() return self.alpha or 1 end
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
		function b:SetFrameLevel(level) self.level = level end
		function b:Click() self.scripts.OnClick(self) end
		world.buttons[#world.buttons + 1] = b
		return b
	end
	gns.UI = realUI and gns.UI or {
		IsShown = function() return dock.shown end,
		DockedTo = function() return dock.host end,
		OpenDocked = function(host, tab, heightOnly, style)
			dock.shown, dock.host, dock.tab, dock.heightOnly, dock.style = true, host, tab, heightOnly, style
		end,
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
	PanelTemplates_AnchorTabs = nil -- the Mainline tab code, set by the Forever tests
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
		PanelTemplates_AnchorTabs = function() end -- Forever's (Mainline) tab code
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
		eq(w.dock.style, "hd", "in the new window's look")
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

test("HD look: Forever's new guild window gets it, the old Guild tabs never do", function()
	WithGuildWindows(function()
		-- Forever: no Guild tab in the Social window, and the Mainline tab code.
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 385, 424)
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
		PanelTemplates_AnchorTabs = function() end
		local w = LoadGuildFrame()
		w.Login()
		eq(w.hook.IsHDClient(), true)
		eq(w.hook.IsHD(), true, "nothing opened yet: the client decides")
		CommunitiesFrame:Show(); w.buttons[1]:Click()
		eq(w.dock.host, CommunitiesFrame); eq(w.dock.style, "hd")
		local status = w.hook.StatusLine()
		assert(status:find("hd client=true", 1, true), status)
		-- ClassicUI Forever's old Guild tab: the old look there, and while it is on screen.
		ClassicUIForeverGuildPanel = FakeFrame("ClassicUIForeverGuildPanel", FriendsFrame)
		FriendsFrame:Show(); ClassicUIForeverGuildPanel:Show()
		eq(w.hook.Hosts()[2].kind, "classicui")
		w.buttons[2]:Click()
		eq(w.dock.host, FriendsFrame); eq(w.dock.style, "old")
		eq(w.hook.IsHD(), false, "the old tab in use")
		-- Only the Communities window left, then not even that: the last one shown decides.
		ClassicUIForeverGuildPanel:Hide(); FriendsFrame:Hide()
		eq(w.hook.IsHD(), true, "the new window on screen")
		CommunitiesFrame:Hide(); CommunitiesFrame:Show(); CommunitiesFrame:Hide()
		eq(w.hook.IsHD(), true, "the new window was the last one shown")
		-- ClassicUI Forever's roster opens the Communities window unseen (alpha 0, off the
		-- screen) for its notes and closes it with the Social window: not a window in use.
		FriendsFrame:Show(); ClassicUIForeverGuildPanel:Show()
		CommunitiesFrame.alpha = 0
		CommunitiesFrame:Show()
		eq(w.hook.IsHD(), false, "the old tab on screen")
		ClassicUIForeverGuildPanel:Hide(); FriendsFrame:Hide()
		CommunitiesFrame:Hide(); CommunitiesFrame.alpha = 1
		eq(w.hook.IsHD(), false, "the old tab was the last one the player saw")
	end)
	WithGuildWindows(function()
		-- ClassicUI Forever's tab built after the scan at login (a login in combat): the old
		-- look, before the Social window is ever opened.
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 385, 424)
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
		PanelTemplates_AnchorTabs = function() end
		local w = LoadGuildFrame()
		w.Login()
		eq(w.hook.IsHD(), true)
		ClassicUIForeverGuildPanel = FakeFrame("ClassicUIForeverGuildPanel", FriendsFrame)
		eq(#w.hook.Hosts(), 1, "not hooked yet"); eq(w.hook.IsHD(), false)
	end)
	WithGuildWindows(function()
		-- ClassicUI Forever's tab already there, nothing opened yet: the old look.
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 385, 424)
		ClassicUIForeverGuildPanel = FakeFrame("ClassicUIForeverGuildPanel", FriendsFrame)
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
		PanelTemplates_AnchorTabs = function() end
		local w = LoadGuildFrame()
		w.Login()
		eq(w.hook.IsHDClient(), true); eq(w.hook.IsHD(), false)
	end)
	WithGuildWindows(function()
		-- Classic Era: its Guild tab is always there (hidden when the new window is used).
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 338, 424)
		GuildFrame = FakeFrame("GuildFrame", FriendsFrame, 338, 424)
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 322, 406)
		PanelTemplates_AnchorTabs = function() end -- even with the Mainline tab code
		local w = LoadGuildFrame()
		w.Login()
		eq(w.hook.IsHDClient(), false)
		CommunitiesFrame:Show(); w.buttons[2]:Click()
		eq(w.dock.host, CommunitiesFrame); eq(w.dock.style, "old")
		assert(w.hook.StatusLine():find("hd client=false", 1, true))
	end)
end)

test("guild button: over Forever's metal title bar, where it always was on Classic", function()
	for _, forever in ipairs({ true, false }) do
		WithGuildWindows(function()
			FriendsFrame = FakeFrame("FriendsFrame", UIParent, 385, 424)
			if not forever then GuildFrame = FakeFrame("GuildFrame", FriendsFrame, 338, 424) end
			CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
			CommunitiesFrame.MaximizeMinimizeFrame = FakeFrame(nil, CommunitiesFrame, 24, 24)
			CommunitiesFrame.MaximizeMinimizeFrame.level = 515 -- frameLevel 510, over the NineSlice's 500
			PanelTemplates_AnchorTabs = forever and function() end or nil
			local w = LoadGuildFrame()
			w.Login()
			local b = w.buttons[#w.buttons]
			eq(b.parent, CommunitiesFrame)
			eq(b.level, forever and 515 or 15, forever and "Forever" or "Classic")
		end)
	end
end)

---------------------------------------------------------------------------
-- The Olympus window itself (UI.lua), on a small widget toolkit: frames keep their size,
-- anchors and shown state, scripts can be fired, rects are worked out from the anchors
-- and text is measured at a fixed width per letter.
---------------------------------------------------------------------------

local POINT_X = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = 0.5, CENTER = 0.5, BOTTOM = 0.5, TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1 }
local POINT_Y = { BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5, TOPLEFT = 1, TOP = 1, TOPRIGHT = 1 }
local CHAR_W = { GameFontNormalLarge = 9, GameFontNormal = 7, GameFontHighlight = 7, GameFontWhiteTiny = 5 } -- small fonts: 6
-- The client's font objects UI.lua fits text with (FitText skips the ones a client lacks).
local FONT_GLOBALS = { "GameFontNormalLarge", "GameFontNormal", "GameFontHighlightSmall", "GameFontWhiteTiny" }

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
function Widget:SetChecked(checked) self.checked = checked and true or false end
function Widget:GetChecked() return self.checked or false end
function Widget:LockHighlight() self.locked = true end
function Widget:UnlockHighlight() self.locked = false end
function Widget:SetHighlightTexture(texture) self.highlightTexture = texture end
function Widget:SetTexture(texture) self.texture = texture end
function Widget:SetClampRectInsets(...) self.clampInsets = { ... } end

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
function Widget:CreateTexture(name)
	local t = NewWidget("Texture", name, self)
	self.textures = self.textures or {}
	table.insert(self.textures, t)
	return t
end
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
	-- The Guild & Communities window's parts (Blizzard_SharedXML, loaded on every client
	-- family but not all of them on every client).
	RightSideTabTemplate = function(w)
		w.w, w.h = 32, 32
		w.Icon = NewWidget("Texture", nil, w)
		-- RightSideTabMixin:OnClick: its sound, and the check.
		w.scripts.OnClick = function(self) self.clickSound = true; self:SetChecked(true) end
	end,
	ColumnDisplayButtonNoScriptsTemplate = function(w)
		w.h = 24
		for _, key in ipairs({ "Left", "Middle", "Right" }) do w[key] = NewWidget("Texture", nil, w) end
	end,
	ScrollFrameTemplate = function(w)
		w.ScrollBar = NewWidget("EventFrame", nil, w)
		w.ScrollBar.w = 8
	end,
	DialogBorderDarkTemplate = function(w)
		w.Bg = NewWidget("Texture", nil, w)
	end,
}

local createdWidgets = {} -- everything FakeCreateFrame made in the current WithUI
local function FakeCreateFrame(kind, name, parent, template)
	local w = NewWidget(kind, name, parent)
	w.template = template
	if TEMPLATES[template] then TEMPLATES[template](w) end
	createdWidgets[#createdWidgets + 1] = w
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
	for _, font in ipairs(FONT_GLOBALS) do _G[font] = { font = font } end
	ns.rdb.guilds = SampleGuilds()
	local ok, err = pcall(fn)
	CreateFrame, ns.CaptureError, ns.UI, GetGuildInfo = saved.CreateFrame, saved.CaptureError, saved.UI, saved.GetGuildInfo
	for _, name in ipairs(widgetNames) do _G[name] = nil end
	widgetNames, createdWidgets = {}, {}
	for _, name in ipairs(GUILD_GLOBALS) do _G[name] = nil end
	for _, name in ipairs(TAB_GLOBALS) do _G[name] = nil end
	for _, font in ipairs(FONT_GLOBALS) do _G[font] = nil end
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

test("HD docking gap and side tabs: Blizzard's own numbers", function()
	local uns = setmetatable({}, { __index = ns })
	assert(loadfile(ADDON_DIR .. "UI.lua"))("Olympus", uns)
	local UI = uns.UI
	eq(UI.DockOffset("old", true), -2, "the old window overlaps the border, as always")
	eq(UI.DockOffset("old", false), -2)
	eq(UI.DockOffset("hd", true), 64, "past the Communities side tabs (32), then Blizzard's gap (32)")
	eq(UI.DockOffset("hd", false), 32, "no side tabs: Blizzard's gap between two windows")
	local f, prev = {}, {}
	eq(table.concat({ UI.TabAnchor("side", 1, f) }, " ", 3), "TOPRIGHT 0 -36", "like the Communities ChatTab")
	eq(select(2, UI.TabAnchor("side", 1, f)), f)
	eq(table.concat({ UI.TabAnchor("side", 2, f, prev) }, " ", 3), "BOTTOMLEFT 0 -20")
	eq(select(2, UI.TabAnchor("side", 2, f, prev)), prev)
	eq(UI.Style(), "old", "without GuildFrame.lua: the old look")
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
		-- The long line drops to the tiny font, and is cut ("...") at the window's edge
		-- instead of running past it when even that does not fit.
		eq(main.sub:GetText(), ns.L.ROAST_NOGUILD_SUB)
		eq(main.sub.w, w - 62 - 8); eq(main.sub.wrap, false); eq(main.sub.justifyH, "LEFT")
		eq(main.sub.font, "GameFontWhiteTiny")
		eq(main.sub:IsTruncated(), true)
		assert(62 + main.sub:GetStringWidth() <= w, "inside the window")
		-- Forever's window is wider: the Join line fits whole in the tiny font.
		main:SetSize(385, 424)
		eq(main.sub.w, 385 - 62 - 8)
		eq(main.sub.font, "GameFontWhiteTiny"); eq(main.sub:IsTruncated(), false)
		-- A client without the tiny font keeps the small one, cut.
		GameFontWhiteTiny = nil
		UI.Refresh()
		eq(main.sub.font, "GameFontHighlightSmall"); eq(main.sub:IsTruncated(), true)
		-- A member's header fits in the large font and is not cut.
		GetGuildInfo = function() return "Olympus II" end
		UI.Refresh()
		eq(main.total.font, "GameFontNormalLarge"); eq(main.total:IsTruncated(), false)
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
		-- Classic Era: its Communities window gets the old window too.
		eq(rawget(_G, "OlympusFrameHD"), nil, "no HD window on Classic")
	end)
end)

-- Forever with the new guild window (in WithUI): the Social window without a Guild tab, the
-- Communities window with its side tabs shown or not (a guild member or not), the Mainline
-- tab code, and GuildFrame.lua with the real UI.lua.
local function ForeverWorld(sideTabs)
	TabCode("mainline")
	FriendsFrame = FakeFrame("FriendsFrame", UIParent, 385, 424)
	FriendsFrame.rect = { 20, 200, 385, 424 }
	CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
	CommunitiesFrame.rect = { 16, 180, 814, 426 }
	CommunitiesFrame.MaximizeMinimizeFrame = FakeFrame(nil, CommunitiesFrame, 24, 24)
	CommunitiesFrame.ChatTab = FakeFrame(nil, CommunitiesFrame, 32, 32)
	CommunitiesFrame.ChatTab.shown = sideTabs
	local w = LoadGuildFrame(true)
	ns.UI = w.ns.UI
	w.Login()
	return w, w.ns.UI
end

test("HD window: docked past the Communities window's side tabs, with icon tabs of its own", function()
	WithUI(function()
		local w, UI = ForeverWorld(true)
		CommunitiesFrame:Show(); w.buttons[1]:Click()
		local main = OlympusFrameHD
		eq(main:IsShown(), true); eq(UI.WindowStyle(), "hd")
		eq(rawget(_G, "OlympusFrame"), nil, "the old window is not even built")
		eq(Anchor(main), "TOPLEFT CommunitiesFrame TOPRIGHT 64 0"); eq(main:GetNumPoints(), 1)
		eq(main:GetWidth() .. "x" .. main:GetHeight(), "385x426", "the Social window's width, the host's height")
		eq(main.clampInsets[2], 40, "its side tabs stay on the screen too")
		-- Blizzard's icon tabs down the right side, one per TABS entry, the first one checked.
		local tabs = main.tabs
		eq(#tabs, #UI.TABS); eq(UI.tabTemplate, "RightSideTabTemplate"); eq(UI.tabStyle, "side")
		for i, tab in ipairs(tabs) do
			eq(tab.template, "RightSideTabTemplate")
			if i == 1 then
				eq(Anchor(tab), "TOPLEFT OlympusFrameHD TOPRIGHT 0 -36")
			else
				eq(tab.points[1][2], tabs[i - 1]); eq(Anchor(tab), "TOPLEFT nil BOTTOMLEFT 0 -20")
			end
			assert(tab.Icon.texture and tab.Icon.texture:find("Interface\\Icons\\", 1, true), "icon of tab " .. i)
			eq(tab.tooltip, ns.L[UI.TABS[i].label])
			eq(tab:GetChecked(), i == 1, "checked: tab " .. i)
			assert(tab.level > main:GetFrameLevel(), "over the frame's border")
		end
		eq(tabs[2].Icon.texture, "Interface\\Icons\\INV_BannerPVP_02", "the Alliance banner")
		tabs[3]:Click()
		eq(main.tab, "decrees"); eq(tabs[3].clickSound, true, "Blizzard's own click ran too")
		for i, tab in ipairs(tabs) do eq(tab:GetChecked(), i == 3, "after the click: tab " .. i) end
		for _, wdg in ipairs(createdWidgets) do
			assert(wdg.template ~= "PanelTabButtonTemplate", "no bottom tabs in the HD window")
		end
		-- The Communities window's buttons: 20 tall, 5 from the corner.
		for _, b in ipairs(main.buttons) do eq(b.h, 20); eq(b.w, 123) end
		eq(Anchor(main.buttons[1]), "BOTTOMLEFT OlympusFrameHD BOTTOMLEFT 5 5")
		eq(Anchor(main.detail), "BOTTOMLEFT OlympusFrameHD BOTTOMLEFT 4 28")
		-- The roster's column headers over the census, sorting on click, its thin scroll bar.
		tabs[1]:Click()
		eq(main.colHeader:IsShown(), true)
		eq(Anchor(main.colHeader), "TOPLEFT OlympusFrameHD TOPLEFT 6 -59"); eq(main.colHeader.h, 24)
		eq(main.listBox:Anchor("TOPLEFT")[5], -81); eq(main.scroll:Anchor("TOPLEFT")[5], -84)
		eq(main.scroll.template, "ScrollFrameTemplate"); eq(main.scroll:Anchor("BOTTOMRIGHT")[4], -24)
		eq(main.views.census:GetWidth(), 385 - 33)
		local header = main.colHeader.buttons[1]
		eq(header.template, "ColumnDisplayButtonNoScriptsTemplate"); eq(header.h, 24); eq(header:GetName(), nil)
		eq(header:GetText(), ns.L.COL_GUILD)
		local sort = ns.Views.sort
		header:Click()
		eq(ns.Views.sort.key, "name", "sorted by guild")
		ns.Views.sort = sort
		eq(main.views.census.rows[1].h, 20, "the roster's rows")
		-- The Communities side tabs go (minimized, Guild Finder) and come back.
		CommunitiesFrame.ChatTab:Hide()
		eq(Anchor(main), "TOPLEFT CommunitiesFrame TOPRIGHT 32 0", "Blizzard's gap only")
		CommunitiesFrame.ChatTab:Show()
		eq(Anchor(main), "TOPLEFT CommunitiesFrame TOPRIGHT 64 0")
		-- Minimized: its height.
		CommunitiesFrame.w, CommunitiesFrame.h = 322, 406
		CommunitiesFrame:Run("OnSizeChanged")
		eq(main:GetWidth() .. "x" .. main:GetHeight(), "385x406")
		eq(main.buttons[1].w, 123)
		local status = ns.StatusText()
		assert(status:find("tabs: RightSideTabTemplate (side spacing), window hd", 1, true), status)
	end)
end)

test("HD and old windows: each guild window gets its look, switched without /reload", function()
	WithUI(function()
		local w, UI = ForeverWorld(true)
		ClassicUIForeverGuildPanel = FakeFrame("ClassicUIForeverGuildPanel", FriendsFrame)
		FriendsFrame:Show(); ClassicUIForeverGuildPanel:Show() -- found when the Social window opens
		FriendsFrame:Hide()
		local new, classic = w.buttons[1], w.buttons[2]
		eq(w.hook.Hosts()[2].kind, "classicui")
		-- The new window in use, on the Realm tab.
		CommunitiesFrame:Show(); new:Click()
		local hd = OlympusFrameHD
		UI.SelectTab("realm")
		eq(hd.tab, "realm")
		-- Clicked in ClassicUI Forever's Guild tab: the old window, exactly as always.
		FriendsFrame:Show(); classic:Click()
		local old = OlympusFrame
		eq(hd:IsShown(), false, "the HD window closes"); eq(old:IsShown(), true)
		eq(UI.WindowStyle(), "old"); eq(UI.DockedTo(), FriendsFrame)
		eq(Anchor(old), "TOPLEFT FriendsFrame TOPRIGHT -2 0")
		eq(old:GetWidth() .. "x" .. old:GetHeight(), "385x424")
		eq(UI.tabTemplate, "PanelTabButtonTemplate"); eq(UI.tabStyle, "mainline")
		eq(Anchor(old.tabs[1]), "TOPLEFT OlympusFrame BOTTOMLEFT 5 2")
		eq(old.tab, "census", "a guild window's button opens the Census, as always")
		eq(Anchor(old.buttons[1]), "BOTTOMLEFT OlympusFrame BOTTOMLEFT 8 8"); eq(old.buttons[1].h, 22)
		eq(Anchor(old.scroll), "TOPLEFT OlympusFrame TOPLEFT 10 -80"); eq(old.views.census:GetWidth(), 385 - 42)
		eq(old.views.census.rows[1].h, 16)
		-- Back in the Communities window: the HD one again.
		new:Click()
		eq(hd:IsShown(), true); eq(old:IsShown(), false); eq(UI.DockedTo(), CommunitiesFrame)
		eq(Anchor(hd), "TOPLEFT CommunitiesFrame TOPRIGHT 64 0"); eq(UI.tabTemplate, "RightSideTabTemplate")
		-- /oly with the old tab the guild window in use: the old window, on the HD one's tab.
		UI.SelectTab("heraldry")
		CommunitiesFrame:Hide()
		eq(hd:IsShown(), false, "closed with the Communities window")
		UI.Toggle()
		eq(old:IsShown(), true); eq(hd:IsShown(), false); eq(old.tab, "heraldry")
		UI.Toggle()
		-- Only the Communities window used since: the HD one.
		ClassicUIForeverGuildPanel:Hide(); FriendsFrame:Hide()
		CommunitiesFrame:Show(); CommunitiesFrame:Hide()
		UI.Toggle()
		eq(hd:IsShown(), true); eq(old:IsShown(), false); eq(hd.tab, "heraldry")
		-- Docked with no tab asked for: the tab in use carries over to the other window.
		UI.SelectTab("decrees")
		FriendsFrame:Show(); UI.OpenDocked(FriendsFrame, nil, false, "old")
		eq(old:IsShown(), true); eq(hd:IsShown(), false); eq(old.tab, "decrees")
	end)
end)

test("ClassicUI Forever's unseen Communities window: /oly keeps the old window", function()
	WithUI(function()
		local _, UI = ForeverWorld(true)
		ClassicUIForeverGuildPanel = FakeFrame("ClassicUIForeverGuildPanel", FriendsFrame)
		-- Its roster open: the Communities window comes up unseen (alpha 0, off the screen)
		-- for the notes, and goes when the Social window closes.
		FriendsFrame:Show(); ClassicUIForeverGuildPanel:Show()
		CommunitiesFrame.alpha = 0
		CommunitiesFrame:Show()
		ClassicUIForeverGuildPanel:Hide(); FriendsFrame:Hide()
		CommunitiesFrame:Hide(); CommunitiesFrame.alpha = 1
		UI.Toggle()
		eq(UI.WindowStyle(), "old"); eq(OlympusFrame:IsShown(), true)
		eq(rawget(_G, "OlympusFrameHD"), nil, "the HD window is not even built")
	end)
end)

test("HD window from /oly before the Communities window has loaded, docked once it has", function()
	WithUI(function()
		TabCode("mainline")
		FriendsFrame = FakeFrame("FriendsFrame", UIParent, 385, 424)
		FriendsFrame.rect = { 20, 200, 385, 424 }
		local w = LoadGuildFrame(true)
		ns.UI = w.ns.UI
		w.Login()
		local UI = w.ns.UI
		UI.Toggle()
		local main = OlympusFrameHD
		eq(UI.WindowStyle(), "hd"); eq(main:IsShown(), true); eq(UI.DockedTo(), nil)
		eq(main:GetWidth() .. "x" .. main:GetHeight(), "385x426", "the Social window's width, the Communities window's height")
		eq(Anchor(main), "CENTER UIParent CENTER 0 40")
		UI.Toggle()
		-- Blizzard_Communities loads: its window gets the button, which docks the HD window
		-- and keeps it clear of the side tabs.
		CommunitiesFrame = FakeFrame("CommunitiesFrame", UIParent, 814, 426)
		CommunitiesFrame.rect = { 16, 180, 814, 426 }
		CommunitiesFrame.ChatTab = FakeFrame(nil, CommunitiesFrame, 32, 32)
		CommunitiesFrame.ChatTab.shown = true
		w.Fire("ADDON_LOADED", "Blizzard_Communities")
		eq(#w.hook.Hosts(), 1); eq(w.hook.Hosts()[1].kind, "communities")
		CommunitiesFrame:Show(); w.buttons[1]:Click()
		eq(main:IsShown(), true); eq(UI.DockedTo(), CommunitiesFrame)
		eq(Anchor(main), "TOPLEFT CommunitiesFrame TOPRIGHT 64 0")
		CommunitiesFrame.ChatTab:Hide()
		eq(Anchor(main), "TOPLEFT CommunitiesFrame TOPRIGHT 32 0", "its side tabs are followed")
	end)
end)

test("rows: the HD window's like the Communities roster's, the old window's unchanged", function()
	WithUI(function()
		local Views = ns.Views
		local function Content(style)
			local c = NewWidget("Frame", nil, UIParent)
			c.w, c.style = 300, style
			return c
		end
		local clicked
		local lines = {
			{ header = true, text = "Header" },
			{ text = "Plain" },
			{ text = "Lord", key = "Lordy", onClick = function() clicked = "Lordy" end },
			{ cols = { "a", "b", "c", "d" } },
			{ text = "Racer", key = "Racer", onClick = function() clicked = "Racer" end },
		}
		local hd = Content("hd")
		hd.selectedKey = "Racer"
		Views.Render(hd, lines, Views.COLUMNS.census)
		local rows = hd.rows
		eq(rows[1].h, 20, "20 tall, like the roster")
		eq(rows[2].points[1][5], -2 - 24, "a header line takes 4 more")
		eq(rows[3].points[1][5], -2 - 24 - 20)
		assert(rows[1].highlightTexture:find("UI-FriendsFrame-HighlightBar", 1, true), "the roster's gold bar")
		eq(rows[3].stripe.texture, "Interface\\GuildFrame\\GuildFrame")
		eq(rows[1].stripe:IsShown(), false, "no row background on a header")
		eq(rows[2].stripe:IsShown(), false, "nor on a line that cannot be clicked")
		eq(rows[3].stripe:IsShown(), true); eq(rows[4].stripe:IsShown(), true, "a table row")
		eq(rows[5].locked, true, "the person open stays lit"); eq(rows[3].locked, false)
		rows[3]:Click()
		eq(clicked, "Lordy"); eq(hd.selectedKey, "Lordy")
		eq(rows[3].locked, true); eq(rows[5].locked, false)
		Views.ClearSelection(hd)
		eq(rows[3].locked, false); eq(hd.selectedKey, nil)
		-- The old window's rows, as always: 16 tall, their own highlight, never kept lit.
		local old = Content("old")
		old.selectedKey = "Racer"
		Views.Render(old, lines, Views.COLUMNS.census)
		rows = old.rows
		eq(rows[1].h, 16); eq(rows[2].points[1][5], -2 - 20)
		eq(rows[1].stripe, nil); eq(rows[1].highlightTexture, nil)
		eq(rows[1].textures[1].texture, "Interface\\QuestFrame\\UI-QuestTitleHighlight")
		rows[3]:Click()
		eq(clicked, "Lordy"); eq(old.selectedKey, "Racer")
		for i = 1, #lines do eq(rows[i].locked, nil, "never lit: row " .. i) end
	end)
end)

test("HD person panel: the roster's member card, hanging off the HD window", function()
	WithUI(function()
		local w, UI = ForeverWorld(true)
		CommunitiesFrame:Show(); w.buttons[1]:Click()
		local main = OlympusFrameHD
		ns.Views.ExpandAll(true)
		UI.SelectTab("realm")
		-- The Lord of Olympus: his line opens his card and stays lit while it is open.
		local row
		for _, r in ipairs(main.views.realm.rows) do
			if r:IsShown() and r.line and r.line.key == "Asmongold" and r.line.indent == 1 then row = r break end
		end
		assert(row, "the Lord's line")
		row:Click()
		local person = OlympusPersonFrameHD
		eq(person:IsShown(), true); eq(person.parent, main)
		-- Docked to the maximized Communities window on the 1366 wide screen, the card would
		-- run past the edge onto our list: it hangs off the window's left side instead.
		eq(Anchor(person), "TOPRIGHT OlympusFrameHD TOPLEFT 4 -76")
		eq(person.w .. "x" .. person.h, "214x226")
		eq(person.Border.template, "DialogBorderDarkTemplate")
		assert(person.level >= main:GetFrameLevel() + 1000, "over the window and its tabs")
		eq(person.name.font, "GameFontNormal"); eq(person.guild:GetText(), "<Olympus>")
		eq(person.whisper.w .. "x" .. person.whisper.h, "96x22"); eq(person.whisper.small, true)
		-- (its `name` is the name line, as on the old panel: anchors are read by hand)
		local p = person.whisper.points[1]
		eq(p[1] .. " " .. p[3] .. " " .. p[4] .. " " .. p[5], "BOTTOMLEFT BOTTOMLEFT 12 36"); eq(p[2], person)
		p = person.mark.points[1]
		eq(p[2], person.who); eq(p[1] .. " " .. p[3] .. " " .. p[4] .. " " .. p[5], "LEFT RIGHT 1 0")
		eq(row.locked, true, "its line stays lit")
		eq(rawget(_G, "OlympusPersonFrame"), nil, "the old panel is not built")
		-- Its buttons: Who through Who.lua, Mark (Heraldry players) runs and closes it.
		local sent, savedSend = nil, ns.Who.SendPlain
		ns.Who.SendPlain = function(query) sent = query end
		person.who:Click()
		ns.Who.SendPlain = savedSend
		eq(sent, 'n-"Asmongold"')
		eq(person.mark:IsShown(), false, "no Mark outside the Heraldry tab")
		person:Hide()
		eq(row.locked, false, "closing the card lets the line go")
		-- Its close button and Escape close it too.
		row:Click()
		person.CloseButton:Click()
		eq(person:IsShown(), false, "closed by its button"); eq(row.locked, false)
		local escape
		for _, name in ipairs(UISpecialFrames) do if name == "OlympusPersonFrameHD" then escape = true end end
		eq(escape, true, "closed by Escape")
		local marked
		row:Click()
		UI.ShowPerson({ name = "Asmongold", guild = "Olympus", onMark = function() marked = true end })
		person.mark:Click()
		eq(marked, true); eq(person:IsShown(), false, "Mark closes it"); eq(row.locked, false)
		-- With room on the right (the Communities window minimized), it hangs off the right side
		-- like Blizzard's.
		CommunitiesFrame.w, CommunitiesFrame.h, CommunitiesFrame.rect = 322, 406, { 16, 200, 322, 406 }
		CommunitiesFrame:Run("OnSizeChanged")
		row:Click()
		eq(Anchor(person), "TOPLEFT OlympusFrameHD TOPRIGHT -4 -76")
		main:Hide()
		eq(person:IsShown(), false, "closed with the window"); eq(row.locked, false)
		ns.Views.ExpandAll(false)
	end)
end)

test("HD Join screen: no tabs or column titles, next to a Communities window without side tabs", function()
	WithUI(function()
		GetGuildInfo = function() return nil end
		local w, UI = ForeverWorld(false)
		CommunitiesFrame:Show(); w.buttons[1]:Click()
		local main = OlympusFrameHD
		eq(Anchor(main), "TOPLEFT CommunitiesFrame TOPRIGHT 32 0", "no side tabs there: Blizzard's gap")
		for _, tab in ipairs(main.tabs) do eq(tab:IsShown(), false) end
		eq(main.colHeader:IsShown(), false)
		eq(main.listBox:Anchor("TOPLEFT")[5], -60); eq(main.scroll:Anchor("TOPLEFT")[5], -63)
		local shown = {}
		for _, b in ipairs(main.buttons) do if b:IsShown() then shown[#shown + 1] = b end end
		eq(#shown, 2); eq(shown[1].w, 186); eq(shown[2].w, 186); eq(shown[1].h, 20)
		-- Joins an Olympus guild with both windows open: the Communities side tabs appear too.
		GetGuildInfo = function() return "Olympus II" end
		CommunitiesFrame.ChatTab:Show()
		UI.Refresh()
		eq(Anchor(main), "TOPLEFT CommunitiesFrame TOPRIGHT 64 0")
		for _, tab in ipairs(main.tabs) do eq(tab:IsShown(), true) end
		eq(main.colHeader:IsShown(), true)
		eq(main.listBox:Anchor("TOPLEFT")[5], -81); eq(main.scroll:Anchor("TOPLEFT")[5], -84)
	end)
end)

test("HD window on a client without Blizzard's new parts: built from what is there", function()
	local missing, saved = { "RightSideTabTemplate", "ColumnDisplayButtonNoScriptsTemplate", "ScrollFrameTemplate", "DialogBorderDarkTemplate" }, {}
	for _, name in ipairs(missing) do saved[name], TEMPLATES[name] = TEMPLATES[name], nil end
	local ok, err = pcall(WithUI, function()
		local w, UI = ForeverWorld(true)
		CommunitiesFrame:Show(); w.buttons[1]:Click()
		local main = OlympusFrameHD
		-- Side tabs made here, like RightSideTab.xml.
		eq(UI.tabTemplate, "fallback"); eq(UI.tabStyle, "side")
		local tab = main.tabs[1]
		eq(tab.w .. "x" .. tab.h, "32x32"); eq(tab.Icon.texture, UI.TABS[1].icon)
		eq(tab.highlightTexture, "Interface\\Buttons\\ButtonHilight-Square"); eq(tab:GetChecked(), true)
		main.tabs[2]:Click()
		eq(main.tab, "realm"); eq(main.tabs[2]:GetChecked(), true); eq(main.tabs[1]:GetChecked(), false)
		-- The old scroll bar, with the room it needs.
		eq(main.scroll:GetName(), "OlympusScrollHDOld"); eq(main.scroll:Anchor("BOTTOMRIGHT")[4], -30)
		eq(main.views.census:GetWidth(), 385 - 39)
		eq(OlympusScrollHD:IsShown(), false, "the one without a scroll bar is hidden")
		-- Plain column titles, the rejected ones hidden.
		main.tabs[1]:Click()
		local header = main.colHeader.buttons[1]
		eq(header.template, nil); eq(header:IsShown(), true); eq(header:GetText(), ns.L.COL_GUILD)
		eq(OlympusColumnHeaderHD1:IsShown(), false)
		-- The old person panel, next to the HD window: the row it was opened from is let go
		-- when it closes, as with the HD one.
		ns.Views.ExpandAll(true)
		UI.SelectTab("realm")
		local row
		for _, r in ipairs(main.views.realm.rows) do
			if r:IsShown() and r.line and r.line.key == "Asmongold" and r.line.indent == 1 then row = r break end
		end
		assert(row, "the Lord's line")
		row:Click()
		eq(OlympusPersonFrame:IsShown(), true); eq(OlympusPersonFrameHD:IsShown(), false)
		eq(Anchor(OlympusPersonFrame), "TOPLEFT OlympusFrameHD TOPRIGHT -2 -28")
		eq(row.locked, true)
		OlympusPersonFrame:Hide()
		eq(row.locked, false, "let go"); UI.Refresh(); eq(row.locked, false, "and stays so")
		row:Click()
		main:Hide()
		eq(OlympusPersonFrame:IsShown(), false, "closed with the window"); eq(row.locked, false)
		ns.Views.ExpandAll(false)
	end)
	for _, name in ipairs(missing) do TEMPLATES[name] = saved[name] end
	if not ok then error(err, 0) end
end)

test("a new tab is one entry in UI.TABS: an icon tab in the HD window, a bottom tab in the old", function()
	local channels = { key = "channels", label = "TAB_CHANNELS", icon = "Interface\\Icons\\INV_Misc_Note_02" }
	for _, hdLook in ipairs({ true, false }) do
		WithUI(function()
			local UI, main
			if hdLook then
				local w
				w, UI = ForeverWorld(true)
				table.insert(UI.TABS, channels)
				CommunitiesFrame:Show(); w.buttons[1]:Click()
				main = OlympusFrameHD
			else
				TabCode("mainline")
				UI = LoadUI()
				table.insert(UI.TABS, channels)
				UI.Toggle()
				main = OlympusFrame
			end
			eq(#main.tabs, 5)
			local last = main.tabs[5]
			if hdLook then
				eq(last.points[1][2], main.tabs[4]); eq(Anchor(last), "TOPLEFT nil BOTTOMLEFT 0 -20")
				eq(last.Icon.texture, channels.icon); eq(last.tooltip, "TAB_CHANNELS")
			else
				eq(last.template, "PanelTabButtonTemplate"); eq(last:GetText(), "TAB_CHANNELS")
			end
			UI.SelectTab("channels")
			eq(main.tab, "channels"); eq(#(main.views.channels.rows or {}), 0, "an empty list")
			for _, b in ipairs(main.buttons) do eq(b:IsShown(), false, "no buttons") end
		end)
	end
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

test("Issue Reporter: tabs appearing with the window open (joined a guild) step it up again", function()
	WithUI(function()
		GetGuildInfo = function() return nil end
		IssueReporter(643, 192)
		local UI = LoadUI()
		UI.Toggle()
		local main = OlympusFrame
		-- Join screen, no tabs: the window (bottom 212) steps 4 above the reporter (228).
		eq(Anchor(main), "CENTER UIParent CENTER 0 60")
		-- Joined with the window open: the tabs now hang down to 202, over the reporter.
		GetGuildInfo = function() return "Olympus II" end
		UI.Refresh()
		eq(main.tabs[1]:IsShown(), true)
		eq(Anchor(main), "CENTER UIParent CENTER 0 90", "tabs 4 above the reporter")
		eq(main:GetBottom() - 30, 232)
		UI.Refresh()
		eq(Anchor(main), "CENTER UIParent CENTER 0 90", "only when they appear")
	end)
end)

test("Issue Reporter: the copy box steps above it too, unless the player moved it", function()
	WithUI(function()
		IssueReporter(643, 192)
		local UI = LoadUI()
		UI.ShowCopy(ns.L.REPORT_BUG, "text")
		local box = OlympusCopyFrame
		-- 520 x 340 at the centre: its bottom (214) and hint are over the reporter (228).
		eq(Anchor(box), "CENTER UIParent CENTER 0 18", "4 above the reporter")
		box:Hide(); UI.ShowCopy(ns.L.REPORT_BUG, "text")
		eq(Anchor(box), "CENTER UIParent CENTER 0 18", "clear now: not moved again")
		box.scripts.OnDragStart(box)
		box:ClearAllPoints(); box:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 400, 150)
		box.scripts.OnDragStop(box)
		box:Hide(); UI.ShowCopy(ns.L.REPORT_BUG, "text")
		eq(Anchor(box), "BOTTOMLEFT UIParent BOTTOMLEFT 400 150", "the player's place is kept")
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

---------------------------------------------------------------------------
-- /who (Who.lua): quiet searches, the 50 cap, and the guilds it sees for the census
---------------------------------------------------------------------------

local WHO = "WHO_LIST_UPDATE"

-- A frame that listens to WHO_LIST_UPDATE (or not) and remembers every change to that.
local function ListenerFrame(name, listening)
	local f = { name = name, events = { [WHO] = listening or nil }, calls = {}, shown = false }
	function f:IsEventRegistered(event) return self.events[event] == true end
	function f:RegisterEvent(event) self.events[event] = true; self.calls[#self.calls + 1] = "register" end
	function f:UnregisterEvent(event) self.events[event] = nil; self.calls[#self.calls + 1] = "unregister" end
	function f:IsVisible() return self.shown end
	return f
end
local function Listening(f) return f:IsEventRegistered(WHO) end

-- Runs fn(server) against a stand-in of the game's /who: C_FriendList answers with the
-- rows the test gives Answer() (and announces them like the client), timers wait until
-- Run() and the clock only moves when the test says. Everything is put back afterwards.
local WHO_GLOBALS = { "C_FriendList", "hooksecurefunc", "GetMaxPlayerLevel", "FriendsFrame", "LFGWhoListFrame", "WhoFrame", "ClassicUIForeverWhoPanel" }
local function WithWho(fn)
	local server = { sent = {}, toUi = {}, rows = {}, timers = {}, printed = {}, clock = 5000 }
	local saved = { After = C_Timer.After, GetTime = GetTime, Print = ns.Print, CaptureError = ns.CaptureError,
		guilds = ns.rdb.guilds, seen = ns.rdb.seen, found = ns.Recruit.found }
	local captured
	ns.CaptureError = function(where, err) captured = captured or (where .. ": " .. tostring(err)) end
	ns.Print = function(msg) server.printed[#server.printed + 1] = msg end
	GetTime = function() return server.clock end
	C_Timer.After = function(seconds, f) server.timers[#server.timers + 1] = { seconds = seconds, fn = f } end
	C_FriendList = {
		SendWho = function(query) server.sent[#server.sent + 1] = query end,
		SetWhoToUi = function(on) server.toUi[#server.toUi + 1] = on end,
		GetNumWhoResults = function() return #server.rows, server.total or #server.rows end,
		GetWhoInfo = function(i)
			local r = server.rows[i]
			return r and { fullName = r[1], fullGuildName = r[2], level = r[3], filename = r[4], area = "Elwynn Forest" }
		end,
	}
	hooksecurefunc = function(t, key, post)
		local original = t[key]
		t[key] = function(...) original(...); post(...) end
	end
	GetMaxPlayerLevel = function() return 60 end
	-- The client announcing an answer (rows = { name, guild, level, class }); no rows: the
	-- same answer again.
	function server.Answer(rows, total)
		if rows then server.rows, server.total = rows, total end
		for _, f in ipairs(EVENT_SCRIPTS) do f(nil, WHO) end
	end
	-- Runs the waiting timers of that many seconds (every one when nil), oldest first.
	function server.Run(seconds)
		local keep, due = {}, {}
		for _, t in ipairs(server.timers) do
			if seconds == nil or t.seconds == seconds then due[#due + 1] = t else keep[#keep + 1] = t end
		end
		server.timers = keep
		for _, t in ipairs(due) do t.fn() end
	end
	-- A click on the search button once the cooldown is over.
	function server.Click()
		server.clock = server.clock + ns.Who.COOLDOWN + 1
		return ns.Who.Search()
	end
	ns.rdb.guilds, ns.rdb.seen, ns.Recruit.found = {}, {}, {}
	ns.Who.Reset()
	ns.Who.lastSend, ns.Who.lastPlain = 0, 0
	local ok, err = pcall(fn, server)
	ns.Who.Reset()
	ns.Who.lastSend, ns.Who.lastPlain = 0, 0
	C_Timer.After, GetTime, ns.Print, ns.CaptureError = saved.After, saved.GetTime, saved.Print, saved.CaptureError
	ns.rdb.guilds, ns.rdb.seen, ns.Recruit.found = saved.guilds, saved.seen, saved.found
	for _, name in ipairs(WHO_GLOBALS) do _G[name] = nil end
	if not ok then error(err, 0) end
	eq(captured, nil, "error caught")
end

-- Olympus players P<from>..P<to>, odd ones in OLYMPUS VII, even ones in OLYMPUS I, levels 7-20.
local function Players(from, to)
	local rows = {}
	for i = from, to do rows[#rows + 1] = { "P" .. i, i % 2 == 0 and "OLYMPUS I" or "OLYMPUS VII", 7 + i % 14, "MAGE" } end
	return rows
end

test("who on Forever: only the frames that listen are silenced, and get the event back with the answer", function()
	WithWho(function(server)
		-- Forever's Social window does not listen, the group finder's who list does, and so
		-- does ClassicUI Forever's list when that addon is on.
		FriendsFrame = ListenerFrame("FriendsFrame", false)
		LFGWhoListFrame = ListenerFrame("LFGWhoListFrame", true)
		ClassicUIForeverWhoPanel = { driver = ListenerFrame("driver", true) }
		local cui = ClassicUIForeverWhoPanel.driver
		eq(ns.Recruit.Search(), true)
		eq(table.concat(server.sent, "|"), 'g-"Olympus"')
		eq(Listening(LFGWhoListFrame), false, "the group finder's list is silenced")
		eq(Listening(cui), false, "ClassicUI Forever's list is silenced")
		eq(#FriendsFrame.calls, 0, "the Social window, which does not listen, is left alone")
		eq(server.toUi[#server.toUi], true, "results to the UI (the event), not to chat")
		server.Answer({ { "Aa", "OLYMPUS VII", 12, "MAGE" }, { "Bb", "OLYMPUS VII", 14, "ROGUE" },
			{ "Aa", "OLYMPUS VII", 12, "MAGE" }, { "Cc", "Horde Pals", 10, "MAGE" } })
		eq(#ns.Recruit.found, 2, "Olympus players, each once (the server lists some twice)")
		-- The same answer announced again (another addon sorting the list does that): still
		-- ours, read again, nobody twice, and Blizzard's list stays quiet.
		server.Answer()
		eq(#ns.Recruit.found, 2)
		eq(Listening(LFGWhoListFrame), false, "still quiet while the answer settles")
		server.Run(ns.Who.SETTLE)
		eq(Listening(LFGWhoListFrame), true, "event given back")
		eq(Listening(cui), true)
		eq(table.concat(LFGWhoListFrame.calls, " "), "unregister register", "once each")
		eq(#FriendsFrame.calls, 0, "never given an event it did not have")
		eq(server.toUi[#server.toUi], false, "back to Blizzard's default")
		server.Run()
		eq(table.concat(LFGWhoListFrame.calls, " "), "unregister register", "the timeout changes nothing more")
		-- The next answer is not ours: not read.
		server.Answer({ { "Dd", "OLYMPUS II", 5, "MAGE" } })
		eq(#ns.Recruit.found, 2, "someone else's answer")
		eq(ns.Who.StatusLines(), nil, "everyone fit in one answer: nothing to add")
	end)
end)

test("who on the old UI: no answer, the Social window gets the event back on the timeout", function()
	WithWho(function(server)
		FriendsFrame = ListenerFrame("FriendsFrame", true)
		eq(ns.Who.Search(), true)
		eq(Listening(FriendsFrame), false, "the Social window's Who tab is silenced")
		server.Run(ns.Who.SETTLE)
		eq(Listening(FriendsFrame), false, "nothing settles without an answer")
		server.Run(ns.Who.TIMEOUT)
		eq(Listening(FriendsFrame), true, "given back on the timeout")
		-- Its answer may still come. Blizzard's default would open the Who tab for a long
		-- one (ShowWhoPanel), so results go to the UI, where the event only updates the list.
		eq(server.toUi[#server.toUi], true, "still to the UI while the answer may come")
		server.Answer({ { "Aa", "OLYMPUS VII", 12, "MAGE" } })
		eq(#ns.Recruit.found, 0, "a late answer is not taken")
		eq(server.toUi[#server.toUi], false, "it came: back to Blizzard's default")
		local toUi = #server.toUi
		server.Run(ns.Who.LATE)
		eq(#server.toUi, toUi, "nothing more to do after it")
		-- 10 seconds between two searches, whichever button sends them.
		server.clock = server.clock + 5
		eq(ns.Who.Search(), false)
		eq(server.printed[#server.printed], ns.L.WHO_WAIT:format(5))
		eq(#server.sent, 1)
		-- Unanswered: the next click asks the same again.
		eq(server.Click(), true)
		eq(server.sent[2], 'g-"Olympus"')
		-- A search still waiting when the next one goes (cannot happen with a timeout shorter
		-- than the cooldown, but): the old timeout leaves the new search alone.
		eq(server.Click(), true)
		eq(Listening(FriendsFrame), false)
		eq(table.concat(FriendsFrame.calls, " "), "unregister register unregister register unregister")
		server.timers[1].fn()
		eq(Listening(FriendsFrame), false, "an old timeout does not end a newer search")
		server.Run()
		eq(Listening(FriendsFrame), true)
	end)
end)

test("who: with the player's own Who window open nothing is sent or silenced", function()
	WithWho(function(server)
		LFGWhoListFrame = ListenerFrame("LFGWhoListFrame", true)
		LFGWhoListFrame.shown = true
		eq(ns.Who.Search(), false)
		eq(#server.sent, 0); eq(#LFGWhoListFrame.calls, 0); eq(#server.toUi, 0)
		eq(server.printed[1], ns.L.WHO_WINDOW_OPEN)
		-- The old UI's Who tab counts too.
		LFGWhoListFrame.shown = false
		WhoFrame = ListenerFrame("WhoFrame")
		WhoFrame.shown = true
		eq(ns.Who.Search(), false)
		WhoFrame.shown = false
		eq(ns.Who.Search(), true, "a skipped search spends no cooldown")
	end)
end)

test("who: someone else's search while ours waits gives the event back at once", function()
	WithWho(function(server)
		LFGWhoListFrame = ListenerFrame("LFGWhoListFrame", true)
		ns.Who.Search()
		eq(Listening(LFGWhoListFrame), false)
		local toUi = #server.toUi
		C_FriendList.SendWho('n-"Bob"') -- the player's own /who
		eq(Listening(LFGWhoListFrame), true, "given back at once")
		eq(#server.toUi, toUi, "results still to the UI: our answer may come first")
		server.Answer({ { "Aa", "OLYMPUS VII", 12, "MAGE" } })
		eq(#ns.Recruit.found, 0, "that answer may be theirs: not read")
		eq(server.toUi[#server.toUi], false, "then Blizzard's default, for theirs")
		-- The player opened their Who window meanwhile: it keeps the results.
		server.Click()
		LFGWhoListFrame.shown = true
		toUi = #server.toUi
		C_FriendList.SendWho('n-"Bob"')
		server.Answer()
		server.Run()
		eq(#server.toUi, toUi, "results stay with the open Who window")
		eq(server.sent[#server.sent - 1], 'g-"Olympus"', "unanswered: the click repeated the broad search")
	end)
end)

test("who: a search given up goes back to Blizzard's default once it can no longer be answered", function()
	WithWho(function(server)
		FriendsFrame = ListenerFrame("FriendsFrame", true)
		-- Never answered: LATE seconds on.
		ns.Who.Search()
		server.Run(ns.Who.TIMEOUT)
		eq(server.toUi[#server.toUi], true)
		server.Run(ns.Who.LATE)
		eq(server.toUi[#server.toUi], false, "never answered")
		-- Given up, then the player searches: that answer gets Blizzard's default at once.
		server.Click()
		server.Run(ns.Who.TIMEOUT)
		eq(server.toUi[#server.toUi], true)
		C_FriendList.SendWho('n-"Bob"')
		eq(server.toUi[#server.toUi], false, "the player's own search, ours given up")
		-- A new search of ours: the old wait ends, and its timer leaves the new one alone.
		server.Click()
		server.Run(ns.Who.TIMEOUT)
		server.Click()
		eq(server.toUi[#server.toUi], true); eq(Listening(FriendsFrame), false)
		server.Run(ns.Who.LATE)
		eq(server.toUi[#server.toUi], true, "the old search's timer changes nothing")
		eq(Listening(FriendsFrame), false)
	end)
end)

test("who: the person panel's Who keeps its distance from our searches", function()
	WithWho(function(server)
		LFGWhoListFrame = ListenerFrame("LFGWhoListFrame", true)
		ns.Who.Search()
		server.clock = server.clock + 2
		eq(ns.Who.SendPlain('n-"Bob"'), false, "ours may still be answered")
		eq(server.printed[#server.printed], ns.L.WHO_WAIT:format(8))
		eq(#server.sent, 1); eq(Listening(LFGWhoListFrame), false, "ours still waits, quiet")
		server.Answer(Players(1, 3))
		server.Run()
		server.clock = server.clock + ns.Who.COOLDOWN
		local toUi = #server.toUi
		eq(ns.Who.SendPlain('n-"Bob"'), true)
		eq(server.sent[#server.sent], 'n-"Bob"')
		eq(Listening(LFGWhoListFrame), true, "nothing silenced"); eq(#server.toUi, toUi, "Blizzard's default")
		eq(ns.Who.SendPlain('n-"Ann"'), true, "one after another, as before")
		-- Ours waits after it: its answer is not ours.
		server.clock = server.clock + 3
		eq(ns.Who.Search(), false)
		eq(server.printed[#server.printed], ns.L.WHO_WAIT:format(7))
		server.Answer(Players(1, 1))
		eq(#ns.Recruit.found, 3, "their answer is not read")
	end)
end)

test("who: a round left unfinished starts over later, its old players dropped", function()
	WithWho(function(server)
		ns.Who.Search()
		server.Answer(Players(1, 50), 312)
		server.Run()
		eq(#ns.Recruit.found, 50); eq(ns.rdb.seen["OLYMPUS VII"].online, 25)
		-- Soon after: the round goes on with the first level range.
		server.Click()
		eq(server.sent[#server.sent], ('g-"Olympus" %d-%d'):format(unpack(ns.Who.sweep.brackets[1])))
		server.Answer(Players(51, 60), 10)
		server.Run()
		eq(#ns.Recruit.found, 60)
		-- An hour later: the broad search again, and only the players seen now count.
		server.clock = server.clock + 3600
		server.Click()
		eq(server.sent[#server.sent], 'g-"Olympus"')
		server.Answer(Players(101, 110), 10)
		server.Run()
		eq(#ns.Recruit.found, 10, "only the players seen now")
		eq(ns.rdb.seen["OLYMPUS VII"].online, 5); eq(ns.rdb.seen["OLYMPUS VII"].capped, nil)
		eq(ns.Who.StatusLines(), nil)
	end)
end)

test("who: a search that fails to send gives every event back", function()
	WithWho(function(server)
		FriendsFrame = ListenerFrame("FriendsFrame", true)
		ClassicUIForeverWhoPanel = { driver = ListenerFrame("driver", true) }
		C_FriendList.SendWho = function() error("who throttled") end
		local caught
		local capture = ns.CaptureError
		ns.CaptureError = function(_, err) caught = tostring(err) end
		eq(ns.SafeCall("button RECRUIT_FIND", ns.Who.Search), false)
		ns.CaptureError = capture
		assert(caught and caught:find("who throttled", 1, true), "error captured: " .. tostring(caught))
		eq(Listening(FriendsFrame), true); eq(Listening(ClassicUIForeverWhoPanel.driver), true)
		eq(server.toUi[#server.toUi], false)
		eq(ns.Who.IsPending(), false)
		server.Run()
		eq(table.concat(FriendsFrame.calls, " "), "unregister register", "the timeout changes nothing more")
	end)
end)

test("who: /oly reset while a search waits gives the event back", function()
	WithWho(function(server)
		LFGWhoListFrame = ListenerFrame("LFGWhoListFrame", true)
		ns.Who.Search()
		eq(Listening(LFGWhoListFrame), false)
		SlashCmdList.OLYMPUS("reset")
		eq(Listening(LFGWhoListFrame), true); eq(server.toUi[#server.toUi], false)
		eq(ns.Who.IsPending(), false)
	end)
end)

test("who: level ranges follow the levels seen", function()
	local function S(list)
		local out = {}
		for _, b in ipairs(list) do out[#out + 1] = b[1] .. "-" .. b[2] end
		return table.concat(out, " ")
	end
	local young = {}
	for i = 1, 50 do young[i] = 7 + i % 14 end
	eq(S(ns.Who.Brackets(young, 60, 5)), "1-9 10-12 13-14 15-17 18-60", "a young realm: ranges where the players are")
	eq(S(ns.Who.Brackets({}, 60, 5)), "1-12 13-24 25-36 37-48 49-60", "no levels seen: even ranges")
	local top = {}
	for i = 1, 50 do top[i] = 60 end
	eq(S(ns.Who.Brackets(top, 60, 5)), "1-59 60-60", "everyone at the top level: it gets a range of its own")
	eq(S(ns.Who.Brackets({}, 3, 5)), "1-1 2-2 3-3")
	eq(S(ns.Who.Brackets(young, 70, 5)), "1-9 10-12 13-14 15-17 18-70", "up to the client's top level")
end)

test("who: a capped answer (50 of 312) is dug through by level, merging, then a click starts over", function()
	WithWho(function(server)
		LFGWhoListFrame = ListenerFrame("LFGWhoListFrame", true)
		ns.Who.Search()
		server.Answer(Players(1, 50), 312)
		server.Run()
		eq(#ns.Recruit.found, 50)
		local brackets = ns.Who.sweep.brackets
		eq(#brackets, 5); eq(brackets[1][1], 1); eq(brackets[5][2], 60)
		local status = ns.Who.StatusLines()
		eq(status[1], "Showing 50 of 312 online.")
		eq(status[2], ("Next search: levels %d-%d (1 of 5)."):format(brackets[1][1], brackets[1][2]))
		-- The Join screen says so under its title.
		local lines = ns.Views.RecruitLines()
		eq(lines[2].text, ns.Views.Grey(status[1])); eq(lines[3].text, ns.Views.Grey(status[2]))
		eq(ns.rdb.seen["OLYMPUS VII"].capped, true, "the census knows more may be online")
		eq(ns.rdb.seen["OLYMPUS VII"].online, 25)
		-- Each click searches the next range and adds to what was found (P41-70, P61-90, ...).
		for k = 1, #brackets do
			eq(server.Click(), true)
			eq(server.sent[#server.sent], ('g-"Olympus" %d-%d'):format(brackets[k][1], brackets[k][2]))
			eq(Listening(LFGWhoListFrame), false, "quiet for the level searches too")
			server.Answer(Players(20 * k + 21, 20 * k + 50), 30)
			server.Run()
			eq(Listening(LFGWhoListFrame), true)
			eq(#ns.Recruit.found, 20 * k + 50, "merged, nobody twice")
			if k == 1 then eq(ns.Who.StatusLines()[1], "70 of 312 found so far.") end
		end
		eq(ns.Who.StatusLines()[1], "150 found, every level searched.")
		eq(#ns.Who.StatusLines(), 1)
		eq(ns.rdb.seen["OLYMPUS VII"].online, 75); eq(ns.rdb.seen["OLYMPUS I"].online, 75)
		eq(ns.rdb.seen["OLYMPUS VII"].capped, nil, "every range fit: exact")
		-- Every range searched once: the next click starts over with the broad search.
		server.Click()
		eq(server.sent[#server.sent], 'g-"Olympus"')
		eq(#ns.Recruit.found, 150, "kept until the new answer comes")
		server.Answer(Players(1, 10), 10)
		server.Run()
		eq(#ns.Recruit.found, 10, "a new round")
		eq(ns.Who.StatusLines(), nil)
	end)
end)

test("who: Forever reports no total past 50, and a crowded level range stays capped", function()
	WithWho(function(server)
		ns.Who.Search()
		server.Answer(Players(1, 50), 50) -- the "50 People Found" of the Forever screenshot
		server.Run()
		eq(ns.Who.StatusLines()[1], "Showing 50: the game lists no more per search.")
		for k = 1, #ns.Who.sweep.brackets do
			server.Click()
			-- The first range is as full as the broad search.
			server.Answer(k == 1 and Players(101, 150) or {}, k == 1 and 50 or 0)
			server.Run()
			if k == 1 then eq(ns.Who.StatusLines()[1], "100 found so far.") end
		end
		eq(ns.Who.StatusLines()[1], "100 found: some levels still had over 50.")
		eq(ns.rdb.seen["OLYMPUS VII"].capped, true, "a range was capped: still a floor")
	end)
end)

test("census: /who sightings for every Olympus guild we can see, never a report", function()
	WithWho(function(server)
		ns.rdb.guilds = SampleGuilds()
		ns.UI = { StatusLine = function() return "status" end }
		local before = ns.Data.Summary()
		ns.Who.Search()
		server.Answer({
			{ "Aa", "OLYMPUS VII", 12 }, { "Bb", "OLYMPUS VII", 14 }, { "Far-Other", "OLYMPUS VII", 14 },
			{ "Cc-Realm", "OLYMPUS XXL", 9 }, { "Dd", "Olympus", 20 }, { "Ee", "House of Guedes", 20 },
			{ "Ff-Other", "OLYMPUS LXIX", 3 },
		})
		server.Run()
		local seen = ns.rdb.seen
		eq(seen["OLYMPUS VII"].online, 3, "players from the other realm (PvP 2) count too")
		eq(seen["OLYMPUS XXL"].online, 1, "Name-OurRealm is ours")
		eq(seen["OLYMPUS LXIX"].online, 1, "a guild only seen on the other realm is listed")
		eq(seen["House of Guedes"], nil, "not an Olympus guild")
		eq(seen["OLYMPUS VII"].capped, nil, "everyone fit in one answer")
		eq(seen["Olympus"].online, 1, "a reported guild can be seen too...")
		eq(ns.rdb.guilds["Olympus"].total, 990, "...and its report is untouched")
		eq(ns.rdb.guilds["OLYMPUS VII"], nil, "a sighting is never a report")
		eq(ns.Data.KnownRank("Aa-Realm", "OLYMPUS VII"), nil, "and grants no rank")
		local s = ns.Data.Summary()
		eq(s.total, before.total); eq(s.online, before.online); eq(s.fresh, before.fresh)
		eq(#s.guilds, #before.guilds, "not among the reported guilds")
		eq(#s.zoneList, #before.zoneList, "nothing on the map")
		eq(#s.seen, 3, "seen and not reported"); eq(s.seen[1].name, "OLYMPUS VII")
		eq(s.seen[2].name, "OLYMPUS LXIX"); eq(s.seen[3].name, "OLYMPUS XXL")
		local realm = ns.Views.RealmLines()
		eq(realm[1].text:find("Asmongold", 1, true) ~= nil, true, "the King is a reported guild's")
		for _, l in ipairs(realm) do
			assert(not (l.text or ""):find("OLYMPUS", 1, true), "in the Realm tree: " .. tostring(l.text))
		end
		-- A report arriving later takes the guild's row; the sighting stays out of sight.
		eq(ns.Data.Receive({ guild = "OLYMPUS XXL", total = 40, online = 9, zones = {} }, "Reporter-Realm"), true)
		s = ns.Data.Summary()
		eq(#s.seen, 2); eq(s.total, before.total + 40)
		-- Forgotten like reports, and by /oly reset.
		seen["OLYMPUS VII"].t = os.time() - ns.Data.KEEP - 1
		seen["OLYMPUS LXIX"].t = os.time() - ns.Data.KEEP - 1
		eq(#ns.Data.Summary().seen, 0, "older than a day")
		SlashCmdList.OLYMPUS("reset")
		eq(next(ns.rdb.seen), nil, "/oly reset forgets sightings")
	end)
end)

test("census: sightings older than a day are forgotten at login", function()
	local savedR, savedCapture = ns.rdb, ns.CaptureError
	local captured
	ns.CaptureError = function(where, err) captured = captured or (where .. ": " .. tostring(err)) end
	ns.rdb = { guilds = {}, seen = { ["OLYMPUS VII"] = { online = 5, t = os.time() - ns.Data.KEEP - 1 },
		["OLYMPUS XXL"] = { online = 3, t = os.time() - 60 }, ["OLYMPUS X"] = "broken" } }
	CoreFire("INIT")
	local seen = ns.rdb.seen
	ns.rdb, ns.CaptureError = savedR, savedCapture
	eq(captured, nil, "error caught")
	eq(seen["OLYMPUS VII"], nil, "older than a day"); eq(seen["OLYMPUS X"], nil, "not a sighting")
	eq(seen["OLYMPUS XXL"].online, 3, "a recent one is kept")
end)

test("census: guilds only seen with /who are grey rows after the reported ones", function()
	WithWho(function()
		local L, Grey = ns.L, ns.Views.Grey
		ns.rdb.guilds = SampleGuilds()
		ns.rdb.seen = { ["OLYMPUS VII"] = { online = 12, capped = true, t = os.time() },
			["OLYMPUS XXL"] = { online = 30, t = os.time() }, ["Olympus"] = { online = 3, t = os.time() } }
		ns.UI = { StatusLine = function() return "status" end }
		ns.Views.sort = { key = "members", desc = false } -- sorting moves reported guilds only
		local lines = ns.Views.Build("census")
		eq(lines[1].cols[1], "Olympus II"); eq(lines[2].cols[1], "Olympus")
		eq(lines[3].cols[1], Grey("OLYMPUS XXL"), "most online first")
		eq(lines[3].cols[3], Grey("30")); eq(lines[3].dim, nil)
		eq(lines[4].cols[1], Grey("OLYMPUS VII")); eq(lines[4].cols[2], Grey("?"))
		eq(lines[4].cols[3], Grey("12+"), "capped: at least")
		eq(lines[4].cols[4], Grey(L.NO_ADDON))
		eq(lines[5].text, Grey(L.SEEN_HINT)); eq(#lines, 5)
		local tip = {}
		local tt = { AddLine = function(_, text) tip[#tip + 1] = text end,
			AddDoubleLine = function(_, a, b) tip[#tip + 1] = a .. "=" .. b end }
		lines[4].tooltip(tt)
		local text = table.concat(tip, "\n")
		assert(text:find(L.SEEN_TIP, 1, true) and text:find(L.SEEN_CAPPED_TIP, 1, true) and text:find("12+", 1, true), text)
		-- Nothing seen: no grey rows and no hint.
		ns.rdb.seen = {}
		eq(#ns.Views.Build("census"), 2)
		ns.Views.sort = { key = "members", desc = true }
	end)
end)

test("census Refresh: the roster, and one /who per click for the grey guilds", function()
	WithWho(function(server)
		WithUI(function()
			local scans = 0
			C_GuildInfo = { GuildRoster = function() scans = scans + 1 end }
			local UI = LoadUI()
			UI.SelectTab("census")
			local refresh = OlympusFrame.buttons[2]
			eq(refresh:GetText(), ns.L.REFRESH)
			refresh:Click()
			eq(scans, 1); eq(table.concat(server.sent, "|"), 'g-"Olympus"')
			refresh:Click()
			eq(scans, 2, "the roster every click"); eq(#server.sent, 1, "/who at most every 10 seconds")
			server.Answer({ { "Aa", "OLYMPUS VII", 12 } })
			UI.Refresh()
			local row = OlympusFrame.views.census.rows[3]
			eq(row.cols[1]:GetText(), ns.Views.Grey("OLYMPUS VII"), "the grey row is drawn")
			-- The person panel's Who goes through Who.lua: not right after our search.
			UI.ShowPerson({ name = "Aa-Realm", guild = "OLYMPUS VII" })
			OlympusPersonFrame.who:Click()
			eq(#server.sent, 1, "the person panel's Who waits for ours")
			server.clock = server.clock + ns.Who.COOLDOWN
			OlympusPersonFrame.who:Click()
			eq(server.sent[#server.sent], 'n-"Aa-Realm"')
			C_GuildInfo = nil
		end)
	end)
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
		["Olympus"] = Vouched({ guild = "Olympus", leader = "Asmongold", officers = { { name = "Capt" } }, total = 1000, online = 1, zones = {}, t = os.time() }, "W1-Realm", "W2-Realm"),
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

test("ranks come from the picture most senders agree on; forgers can't move it", function()
	ns.Roster.Scan()
	ns.rdb.guilds = {}
	local D = ns.Data
	local LEVELS = "~0,0,0,0,0,0,0~~"
	local function Report(guild, leader, officers, sender)
		return D.Receive(Codec.DecodeReport("R2~" .. guild .. "~900~90~" .. leader .. "~1~1~~" .. LEVELS .. officers), sender)
	end
	local savedNow = ns.Now
	local clock = os.time()
	ns.Now = function() return clock end
	local ok, err = pcall(function()
		-- <Olympus> as its reporter and runner-up send it.
		eq(Report("Olympus", "King", "Duke:1:0", "Crier-Realm"), true)
		eq(Report("Olympus", "King", "Duke:1:0", "Clerk-Realm"), true)
		eq(D.KnownRank("Duke-Realm", "Olympus"), 1, "two senders name the officer")
		eq(D.KnownRank("King-Realm", "Olympus"), 0, "and the King")
		-- One outsider copies the report (fine), then adds an accomplice: one vote against two.
		clock = clock + 60
		eq(Report("Olympus", "King", "Duke:1:0", "Aaa-Realm"), true)
		clock = clock + 1
		eq(Report("Olympus", "King", "Duke:1:0,Bbb:1:0", "Aaa-Realm"), true)
		eq(D.KnownRank("Bbb-Realm", "Olympus"), nil, "the copy-then-add trick gives nothing")
		eq(D.KnownRank("Duke-Realm", "Olympus"), 1, "and costs the real officers nothing")
		eq(ns.rdb.guilds.Olympus.conflict, true, "the forged report shows as a conflict")
		-- Its own report never makes a sender anything.
		eq(Report("Olympus", "King", "Duke:1:0,Aaa:1:0", "Aaa-Realm"), true)
		eq(D.KnownRank("Aaa-Realm", "Olympus"), nil)
		-- Two forgers against two reporters: contested, nobody's rank counts until it is settled.
		eq(Report("Olympus", "King", "Duke:1:0,Aaa:1:0", "Ccc-Realm"), true)
		eq(D.KnownRank("Aaa-Realm", "Olympus"), nil, "a tie is no majority")
		eq(D.KnownRank("Duke-Realm", "Olympus"), 1, "contested: what both pictures agree on still counts")
		-- Their votes expire when they stop; the real reporters' stay fresh.
		clock = clock + 20 * 60
		eq(Report("Olympus", "King", "Duke:1:0", "Crier-Realm"), true)
		eq(Report("Olympus", "King", "Duke:1:0", "Clerk-Realm"), true)
		clock = clock + 11 * 60
		eq(Report("Olympus", "King", "Duke:1:0", "Crier-Realm"), true)
		eq(D.KnownRank("Duke-Realm", "Olympus"), 1, "the forgers' votes are over 30 minutes old")
		eq(D.KnownRank("Aaa-Realm", "Olympus"), nil)
		-- A real promotion: split while only one of the two has reported it, then agreed.
		eq(Report("Olympus", "King", "Duke:1:0,Earl:1:0", "Clerk-Realm"), true)
		eq(D.KnownRank("Earl-Realm", "Olympus"), nil, "one sender so far")
		eq(D.KnownRank("Duke-Realm", "Olympus"), 1, "the others keep their ranks meanwhile")
		eq(D.KnownRank("King-Realm", "Olympus"), 0)
		eq(Report("Olympus", "King", "Duke:1:0,Earl:1:0", "Crier-Realm"), true)
		eq(D.KnownRank("Earl-Realm", "Olympus"), 1, "both reporters name him")
		-- Another guild: an outsider swapping the leader for an accomplice gets no Lord.
		eq(Report("Olympus Zeus", "Zeus", "", "Zclerk-Realm"), true)
		eq(Report("Olympus Zeus", "Zeus", "", "Zcrier-Realm"), true)
		eq(Report("Olympus Zeus", "Bbb2", "", "Aaa2-Realm"), true)
		eq(D.KnownRank("Bbb2-Realm", "Olympus Zeus"), nil, "leader swap: one vote against two")
		eq(D.KnownRank("Zeus-Realm", "Olympus Zeus"), 0)
	end)
	ns.Now = savedNow
	ns.rdb.guilds = {}
	if not ok then error(err, 0) end
end)

test("cut officer lists, channel changes and the first minutes after login", function()
	ns.rdb.guilds = {}
	local D = ns.Data
	local LEVELS = "~0,0,0,0,0,0,0~~"
	local function Officers(extra)
		local t = {}
		for i = 1, 30 do t[#t + 1] = "Off" .. i .. ":1:0" end
		if extra then t[#t] = extra .. ":1:0" end
		return table.concat(t, ",")
	end
	local function Report(guild, officers, sender)
		return D.Receive(Codec.DecodeReport("R2~" .. guild .. "~900~90~Boss~1~1~~" .. LEVELS .. officers), sender)
	end
	-- 30 officers: the list is cut, the picture is the leader only.
	eq(Report("Olympus Ares", Officers(), "Rep-Realm"), true)
	eq(Report("Olympus Ares", Officers(), "Run-Realm"), true)
	eq(D.KnownRank("Off3-Realm", "Olympus Ares"), 1, "named by both senders")
	eq(Report("Olympus Ares", Officers("Mallory"), "Pad-Realm"), true)
	eq(D.KnownRank("Mallory-Realm", "Olympus Ares"), nil, "a padded list gives nobody a rank")
	eq(D.KnownRank("Off3-Realm", "Olympus Ares"), 1, "the real officers keep theirs")
	-- Moving to another channel forgets every vote.
	D.ForgetVotes()
	eq(D.KnownRank("Off3-Realm", "Olympus Ares"), nil)
	eq(ns.rdb.guilds["Olympus Ares"].total, 900, "the census numbers stay")
	-- No Crown in the first minutes after login.
	local savedLogin = ns.Comm.loginAt
	eq(Report("Olympus Zeus2", "", "Zr-Realm"), true)
	eq(Report("Olympus Zeus2", "", "Zs-Realm"), true)
	ns.Comm.loginAt = ns.Now() - 30
	eq(D.KnownRank("Boss-Realm", "Olympus Zeus2"), nil, "30 s after login: not yet")
	ns.Comm.loginAt = ns.Now() - D.CROWN_AFTER - 1
	eq(D.KnownRank("Boss-Realm", "Olympus Zeus2"), 0, "after a reporting cycle")
	ns.Comm.loginAt = savedLogin
	ns.rdb.guilds = {}
end)

test("reporter and runner-up on two realms of the group picture the guild the same way", function()
	ns.rdb.guilds = {}
	local D = ns.Data
	local LEVELS = "~0,0,0,0,0,0,0~~"
	-- Boss plays on our realm. Our reporter names him bare; the runner-up plays on PvP 2, where
	-- Boss carries his realm, and reaches us with its own.
	eq(D.Receive(Codec.DecodeReport("R2~Olympus Span2~50~5~Boss~1~1~~" .. LEVELS .. "Capt:1:0"), "Here"), true)
	eq(D.Receive(Codec.DecodeReport("R2~Olympus Span2~50~5~Boss-Realm~1~1~~" .. LEVELS .. "Capt-Realm:1:0"), "There-Other"), true)
	eq(ns.rdb.guilds["Olympus Span2"].conflict, nil, "the same people, not a conflict")
	eq(D.KnownRank("Boss-Realm", "Olympus Span2"), 0, "a Lord on two senders' word")
	eq(D.KnownRank("Capt", "Olympus Span2"), 1)
	ns.rdb.guilds = {}
end)

test("ranks of other guilds: never your own word, the Crown on two, and only while recent", function()
	ns.rdb.guilds = {}
	local D = ns.Data
	local LEVELS = "~0,0,0,0,0,0,0~~"
	local function Report(guild, leader, officers, sender)
		return D.Receive(Codec.DecodeReport("R2~" .. guild .. "~40~9~" .. leader .. "~1~1~~" .. LEVELS .. officers), sender)
	end
	local savedNow = ns.Now
	local clock = os.time()
	ns.Now = function() return clock end
	local ok, err = pcall(function()
		-- A guild master who is his guild's only reporter: his own report proves nothing.
		eq(Report("Olympus Hermes", "Hermes", "Aide:1:0", "Hermes-Realm"), true)
		eq(D.KnownRank("Hermes-Realm", "Olympus Hermes"), nil, "own report")
		eq(D.KnownRank("Aide-Realm", "Olympus Hermes"), 1, "his officer, named by someone else")
		-- The runner-up reports too (Comm): now two senders, and one of them names Hermes.
		clock = clock + 30
		eq(Report("Olympus Hermes", "Hermes", "Aide:1:0", "Runner-Realm"), true)
		eq(D.KnownRank("Hermes-Realm", "Olympus Hermes"), 0, "a guild master on two senders' word")
		-- One sender only never makes anyone the Crown.
		eq(Report("Olympus Iris", "Iris", "", "Lone-Realm"), true)
		eq(D.KnownRank("Iris-Realm", "Olympus Iris"), nil, "the Crown needs two senders")
		-- Vouches expire: 40 minutes later only a fresh report counts.
		clock = clock + 40 * 60
		eq(Report("Olympus Hermes", "Hermes", "Aide:1:0", "Hermes-Realm"), true)
		eq(D.KnownRank("Hermes-Realm", "Olympus Hermes"), nil, "the runner-up's word is 40 minutes old")
		eq(D.KnownRank("Aide-Realm", "Olympus Hermes"), 1, "Hermes still vouches for his officer")
	end)
	ns.Now = savedNow
	ns.rdb.guilds = {}
	if not ok then error(err, 0) end
end)

test("a player who changed guilds can speak for the new one after a quiet while", function()
	local D = ns.Data
	local savedNow = ns.Now
	local clock = os.time()
	ns.Now = function() return clock end
	eq(D.ClaimGuild("Mover-Realm", "Olympus Alpha"), true)
	eq(D.ClaimGuild("Mover-Realm", "Olympus Beta"), false, "not right away")
	clock = clock + D.CLAIM_TTL + 1
	eq(D.ClaimGuild("Mover-Realm", "Olympus Beta"), true, "after CLAIM_TTL quiet")
	eq(D.ClaimGuild("Mover-Realm", "Olympus Alpha"), false, "and now bound to the new one")
	ns.Now = savedNow
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

---------------------------------------------------------------------------
-- Realm groups: PvP and PvP 2 share one census (Core.lua), and what tells realms apart
-- (names as the server sent them, the realm a report was sent from, guild peers by realm).
---------------------------------------------------------------------------

local BETA = "ClassicBetaPvP+ClassicBetaPvP2"

-- A table as text, keys sorted: two runs of the migration can be compared.
local function Dump(v)
	if type(v) ~= "table" then return type(v) == "string" and ("%q"):format(v) or tostring(v) end
	local keys, out = {}, {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. Dump(v[k]) end
	return "{" .. table.concat(out, ",") .. "}"
end

-- ADDON_LOADED on the saved variables `saved`, played on the realm named `realmName`.
-- Returns OlympusDB, the store it opened and its group; ns is put back afterwards.
local function LoadAs(realmName, saved)
	local keep = { db = ns.db, rdb = ns.rdb, realm = ns.realm, group = ns.group, name = GetRealmName, capture = ns.CaptureError }
	local captured
	ns.CaptureError = function(where, err) captured = captured or (where .. ": " .. tostring(err)) end
	GetRealmName = function() return realmName end
	OlympusDB = saved
	for _, fn in ipairs(EVENT_SCRIPTS) do fn(nil, "ADDON_LOADED", "Olympus") end
	local rdb, group = ns.rdb, ns.group
	ns.db, ns.rdb, ns.realm, ns.group, GetRealmName, ns.CaptureError = keep.db, keep.rdb, keep.realm, keep.group, keep.name, keep.capture
	eq(captured, nil, "error caught")
	return OlympusDB, rdb, group
end

test("realm groups: the beta PvP realms start as one, learned links override, other realms stay alone", function()
	local savedDB = ns.db
	ns.db = { log = {} }
	eq(ns.GroupOf("ClassicBetaPvP"), BETA); eq(ns.GroupOf("ClassicBetaPvP2"), BETA)
	eq(ns.GroupOf("Realm"), "Realm", "any other realm is a group of its own")
	eq(ns.GroupSource("ClassicBetaPvP2"), "seed"); eq(ns.GroupSource("Realm"), "own")
	local realms = ns.GroupRealms(BETA)
	eq(#realms, 2); eq(realms[1], "ClassicBetaPvP"); eq(realms[2], "ClassicBetaPvP2")
	ns.db.links = { ClassicBetaPvP = BETA .. "+Other" }
	eq(ns.GroupOf("ClassicBetaPvP"), BETA .. "+Other", "a learned link overrides the seed")
	eq(ns.GroupSource("ClassicBetaPvP"), "learned")
	ns.db = savedDB
end)

test("realm groups: the PvP and PvP 2 stores merge into one, newest wins, nothing of ours lost", function()
	local now = os.time()
	local chatA, chatB = {}, {}
	for i = 1, 60 do chatA[i] = { t = now - 1000 + i * 2, sender = "A" .. i, text = "a" } end
	for i = 1, 60 do chatB[i] = { t = now - 999 + i * 2, sender = "B" .. i, text = "b" } end
	chatB[61] = chatA[60] -- one line in both stores
	local saved = { configVersion = 3, blocked = { troll = true }, realms = {
		ClassicBetaPvP = {
			guilds = { ["OLYMPUS I"] = { total = 500, t = now - 50, mine = true }, ["OLYMPUS VII"] = { total = 40, t = now - 3000 },
				["OLYMPUS XXL"] = { total = 90, t = now - 10 } },
			seen = { ["OLYMPUS LXIX"] = { online = 3, t = now - 100 } },
			inspect = { players = { ["Naked-ClassicBetaPvP"] = { status = "NONE", t = now - 100 }, ["Both-X"] = { status = "OTHER", t = now - 500 },
				["Bob Smith"] = { status = "GUILD", t = now - 900, marked = true, note = "ganker" }, ["Cy Jones"] = { status = "GUILD", t = now - 5 },
				["Undone"] = { status = "GUILD", t = now - 900, marked = true, note = "old" } },
				guildMarks = { ["OLYMPUS II"] = true } },
			chat = { A = chatA },
			realmKey = "same-secret",
		},
		ClassicBetaPvP2 = {
			guilds = { ["OLYMPUS I"] = { total = 480, t = now - 5000 }, ["OLYMPUS VII"] = { total = 45, t = now - 20 },
				["OLYMPUS XIV"] = { total = 60, t = now - 30, mine = true } },
			seen = { ["OLYMPUS LXIX"] = { online = 7, t = now - 5 }, ["OLYMPUS X"] = { online = 1, t = now - 9 } },
			inspect = { players = { ["Both-X"] = { status = "GUILD", t = now - 5 }, ["Bob Smith"] = { status = "NONE", t = now - 5 },
				["Cy Jones"] = { status = "GUILD", t = now - 900, marked = true, note = "spy" }, ["Undone"] = { status = "GUILD", t = now - 5, marked = false } },
				guildMarks = { ["OLYMPUS III"] = true } },
			chat = { A = chatB, C = { { t = now, sender = "Cap", text = "c" } } },
			realmKey = "same-secret",
			shared = { realm = "ClassicBetaPvP", to = "ClassicBetaPvP2", t = now - 60 },
		},
		Faraway = { guilds = { ["Olympus Far"] = { total = 5, t = now } } },
	} }
	local db, R, group = LoadAs("Classic Beta PvP", saved)
	eq(group, BETA); eq(db.realms[BETA], R, "one store for both realms")
	eq(db.realms.ClassicBetaPvP, nil, "the per-realm stores are gone"); eq(db.realms.ClassicBetaPvP2, nil)
	eq(db.realms.Faraway.guilds["Olympus Far"].total, 5, "another realm's store is untouched")
	eq(R.guilds["OLYMPUS I"].total, 500, "our own guild's newer report stays"); eq(R.guilds["OLYMPUS I"].mine, true)
	eq(R.guilds["OLYMPUS VII"].total, 45, "the newer report wins"); eq(R.guilds["OLYMPUS XXL"].total, 90)
	eq(R.guilds["OLYMPUS XIV"].total, 60, "an alt's own guild is kept"); eq(R.guilds["OLYMPUS XIV"].mine, true)
	eq(R.seen["OLYMPUS LXIX"].online, 7, "the newer sighting wins"); eq(R.seen["OLYMPUS X"].online, 1)
	eq(R.inspect.players["Naked-ClassicBetaPvP"].status, "NONE"); eq(R.inspect.players["Both-X"].status, "GUILD", "newest inspection")
	eq(R.inspect.guildMarks["OLYMPUS II"], true); eq(R.inspect.guildMarks["OLYMPUS III"], true, "the marks of both")
	local bob, cy = R.inspect.players["Bob Smith"], R.inspect.players["Cy Jones"]
	eq(bob.status, "NONE", "the newer inspection..."); eq(bob.marked, true, "...keeps the older one's mark"); eq(bob.note, "ganker")
	eq(cy.t, now - 5, "the newer entry stays..."); eq(cy.marked, true, "...and takes the mark merged in"); eq(cy.note, "spy")
	eq(R.inspect.players["Undone"].marked, false, "an explicit unmark stays"); eq(R.inspect.players["Undone"].note, "old")
	eq(R.guilds["OLYMPUS VII"].heardOn, "ClassicBetaPvP2", "a realm's store: its reports were heard there")
	eq(R.guilds["OLYMPUS XXL"].heardOn, "ClassicBetaPvP")
	-- 121 lines, one of them twice: 120, of which the oldest 20 go.
	eq(#R.chat.A, 100, "capped"); eq(R.chat.A[1].sender, "A11", "oldest dropped"); eq(R.chat.A[100].sender, "B60", "newest last")
	for i = 2, #R.chat.A do assert(R.chat.A[i - 1].t < R.chat.A[i].t, "chat in time order, each line once") end
	eq(#R.chat.C, 1)
	eq(R.realmKey, "same-secret", "the same key on both realms is kept")
	eq(R.shared.realm, "ClassicBetaPvP", "anything else is carried over")
	eq(db.blocked["troll-classicbetapvp"], true, "block list keys take the character's own realm")
	-- Running it again changes nothing, and PvP 2 opens the same store.
	local before = Dump(db.realms) .. Dump(db.links) .. Dump(db.blocked)
	local db2, R2 = LoadAs("Classic Beta PvP", db)
	eq(Dump(db2.realms) .. Dump(db2.links) .. Dump(db2.blocked), before, "second run")
	eq(R2, R)
	local _, R3, group3 = LoadAs("Classic Beta PvP 2", db)
	eq(group3, BETA); eq(R3, R, "PvP 2 reads the same census")
	eq(Dump(db.realms), Dump(db2.realms))
end)

test("realm groups: sightings kept with a realm of the group on the guild's name go under its plain name", function()
	local now = os.time()
	local _, R = LoadAs("Classic Beta PvP", { configVersion = 3, realms = {
		ClassicBetaPvP = { seen = { ["OLYMPUS XIV"] = { online = 2, t = now - 500 }, ["OLYMPUS V-ClassicBetaPvP"] = { online = 1, t = now - 10 } } },
		ClassicBetaPvP2 = { seen = { ["OLYMPUS XIV-ClassicBetaPvP2"] = { online = 4, t = now - 50 }, ["OLYMPUS X-Faraway"] = { online = 3, t = now - 9 },
			["OLYMPUS X"] = { online = 6, t = now - 20 }, ["OLYMPUS X-ClassicBetaPvP"] = { online = 5, t = now - 400 } } },
	} })
	local keep = { rdb = ns.rdb, group = ns.group, capture = ns.CaptureError }
	local captured
	ns.CaptureError = function(where, err) captured = captured or (where .. ": " .. tostring(err)) end
	ns.rdb, ns.group = R, BETA
	CoreFire("INIT") -- as ADDON_LOADED does, with the group's store open
	ns.rdb, ns.group, ns.CaptureError = keep.rdb, keep.group, keep.capture
	eq(captured, nil, "error caught")
	eq(R.seen["OLYMPUS XIV"].online, 4, "the newer one, whatever its name"); eq(R.seen["OLYMPUS XIV-ClassicBetaPvP2"], nil)
	eq(R.seen["OLYMPUS V"].online, 1); eq(R.seen["OLYMPUS V-ClassicBetaPvP"], nil)
	eq(R.seen["OLYMPUS X"].online, 6, "an older one does not replace it"); eq(R.seen["OLYMPUS X-ClassicBetaPvP"], nil)
	eq(R.seen["OLYMPUS X-Faraway"].online, 3, "a realm outside the group keeps its name")
end)

test("realm groups: realm keys, one is taken, the same is kept, different ones are dropped", function()
	local function Key(a, b, group)
		local realms = { ClassicBetaPvP = { realmKey = a }, ClassicBetaPvP2 = { realmKey = b } }
		if group then realms[BETA] = { realmKey = group } end
		local db, R = LoadAs("Classic Beta PvP 2", { configVersion = 3, realms = realms })
		eq(db.realms.ClassicBetaPvP, nil); eq(db.realms.ClassicBetaPvP2, nil)
		return R.realmKey
	end
	eq(Key("one-secret", nil), "one-secret", "only one realm had a key: taken")
	eq(Key(nil, "two-secret"), "two-secret")
	eq(Key("same-secret", "same-secret"), "same-secret")
	eq(Key("one-secret", "two-secret"), nil, "two keys: dropped, our officers send ours again")
	eq(Key(nil, nil), nil)
	eq(Key("one-secret", nil, "one-secret"), "one-secret", "the group's own key counts too")
	eq(Key(nil, "two-secret", "one-secret"), nil)
end)

test("realm groups: a link learned mid-session moves the census over at once", function()
	local keep = { db = ns.db, rdb = ns.rdb, realm = ns.realm, group = ns.group, Fire = ns.Fire, print = print,
		Join = ns.Comm.JoinChannel, Name = ns.Comm.ChannelName, Ask = ns.Comm.RequestKey }
	local fired, joins, asks, channel = {}, 0, 0, "OlympusNet"
	local ok, err = pcall(function()
		print = function() end
		ns.Fire = function(name) fired[#fired + 1] = name end
		ns.Comm.JoinChannel = function() joins = joins + 1 end
		ns.Comm.ChannelName = function() return channel end
		ns.Comm.RequestKey = function() asks = asks + 1 end
		local now = os.time()
		local R0 = { guilds = { ["Olympus Here"] = { total = 10, t = now } }, seen = {} }
		ns.db = { log = {}, realms = { Realm = R0, Other = { guilds = { ["Olympus There"] = { total = 20, t = now } } } } }
		ns.realm, ns.group, ns.rdb = "Realm", "Realm", R0
		eq(ns.LinkRealms("Realm", nil), false); eq(ns.LinkRealms("Realm", "?"), false); eq(ns.LinkRealms("Realm", "Realm"), false)
		eq(ns.LinkRealms("Realm", "Other"), true)
		eq(ns.group, "Other+Realm"); eq(ns.db.links.Realm, "Other+Realm"); eq(ns.db.links.Other, "Other+Realm")
		eq(ns.rdb, ns.db.realms["Other+Realm"], "the census now lives in the group's store")
		eq(ns.rdb.guilds["Olympus Here"].total, 10, "what we had is carried over")
		eq(ns.rdb.guilds["Olympus There"].total, 20, "and the other realm's census joins it")
		eq(ns.db.realms.Realm, nil); eq(ns.db.realms.Other, nil)
		eq(fired[#fired], "DATA_CHANGED"); eq(joins, 0, "no key changed: same channel")
		eq(ns.LinkRealms("Other", "Realm"), false, "nothing new")
		-- A realm with another key: both keys go, and we move to the channel without one.
		ns.rdb.realmKey = "our-secret"
		ns.db.realms.Third = { realmKey = "their-secret" }
		eq(ns.LinkRealms("Realm", "Third"), true)
		eq(ns.group, "Other+Realm+Third", "the whole group grows"); eq(ns.db.links.Other, "Other+Realm+Third")
		eq(ns.rdb.guilds["Olympus Here"].total, 10, "the old group's store is merged too")
		eq(ns.db.realms["Other+Realm"], nil)
		eq(ns.rdb.realmKey, nil); eq(joins, 1, "the key changed: so does the channel")
		eq(asks, 1, "ours was dropped: our officers are asked for it again")
		ns.rdb.realmKey = "our-secret"
		ns.db.realms.Fourth = { realmKey = "our-secret" }
		eq(ns.LinkRealms("Realm", "Fourth"), true); eq(ns.rdb.realmKey, "our-secret"); eq(joins, 1, "same key"); eq(asks, 1)
		channel = nil
		ns.db.realms.Fifth = { realmKey = "their-secret" }
		eq(ns.LinkRealms("Fifth", "Realm"), true); eq(ns.rdb.realmKey, nil)
		eq(joins, 1, "not joined yet: the first join takes the new key"); eq(asks, 1, "and the login's request asks")
	end)
	ns.db, ns.rdb, ns.realm, ns.group, ns.Fire, print = keep.db, keep.rdb, keep.realm, keep.group, keep.Fire, keep.print
	ns.Comm.JoinChannel, ns.Comm.ChannelName, ns.Comm.RequestKey = keep.Join, keep.Name, keep.Ask
	if not ok then error(err, 0) end
end)

test("realm groups: our guild homed on another realm links it; roster names are counted as sent", function()
	local keep = { db = ns.db, rdb = ns.rdb, realm = ns.realm, group = ns.group, print = print,
		info = GetGuildInfo, roster = GetGuildRosterInfo }
	local ok, err = pcall(function()
		print = function() end
		ns.db = { log = {}, blocked = {}, realms = { Realm = { guilds = {}, seen = {} } } }
		ns.realm, ns.group, ns.rdb = "Realm", "Realm", ns.db.realms.Realm
		GetGuildInfo = function() return MY_GUILD, "Hero", 3, "Other" end
		GetGuildRosterInfo = function(i)
			local far = i % 3 == 0
			return far and ("Far" .. i .. "-Other") or ("Near" .. i), "rank", i == 1 and 0 or 3, 10, "class", "Elwynn Forest",
				"", "", true, 0, "MAGE", nil, nil, nil, nil, nil, ("Player-%d-%08X"):format(far and 4620 or 4619, i)
		end
		ns.Roster.RequestScan(true)
		ns.Roster.TryScan()
		eq(ns.db.links.Realm, "Other+Realm", "learned from our own guild's home")
		eq(ns.group, "Other+Realm")
		local mine = ns.rdb.guilds[MY_GUILD]
		eq(mine.home, "Other"); eq(mine.from, "Realm")
		local d = ns.Codec.DecodeReport(ns.Codec.EncodeReport(mine))
		eq(d.home, "Other"); eq(d.from, "Realm")
		eq(ns.Roster.rawRealms.bare, 667); eq(ns.Roster.rawRealms.Other, 333)
		eq(ns.Roster.servers["4619"], 667); eq(ns.Roster.servers["4620"], 333)
		eq(ns.Roster.rawSample, "Far3-Other", "an example with its realm, when there is one")
		-- Guild on our own realm: 4th return nil, home is ours, nothing to link.
		GetGuildInfo = function() return MY_GUILD, "Hero", 3 end
		eq(ns.Roster.Scan().home, "Realm")
	end)
	ns.db, ns.rdb, ns.realm, ns.group, print = keep.db, keep.rdb, keep.realm, keep.group, keep.print
	GetGuildInfo, GetGuildRosterInfo = keep.info, keep.roster
	ns.Roster.Scan() -- the roster of the other tests back
	if not ok then error(err, 0) end
end)

test("reports: fields 21 and 22 (reporter's realm, guild's home) are optional both ways", function()
	local C = ns.Codec
	local r = { guild = "Olympus Span", total = 9, online = 1, zones = {}, from = "ClassicBetaPvP2", home = "ClassicBetaPvP" }
	local payload = C.EncodeReport(r)
	local d = C.DecodeReport(payload)
	eq(d.from, "ClassicBetaPvP2"); eq(d.home, "ClassicBetaPvP")
	local f = C.Split(payload, "~")
	eq(#f, 22)
	local old = C.DecodeReport(table.concat(f, "~", 1, 20))
	eq(old.total, 9); eq(old.from, nil, "a 20-field report (older versions)"); eq(old.home, nil)
	local newer = C.DecodeReport(payload .. "~some field of a later version")
	eq(newer.from, "ClassicBetaPvP2", "a 23-field report still decodes")
	f[21], f[22] = "Bad|cffRealm", ("x"):rep(41)
	d = C.DecodeReport(table.concat(f, "~"))
	eq(d.from, nil, "no escape codes"); eq(d.home, nil, "no more than 40 characters")
	eq(C.RealmField("Two words"), nil); eq(C.RealmField(""), nil); eq(C.RealmField(("x"):rep(40)), ("x"):rep(40))
end)

test("a bare officer of a report sent from another realm keeps its rank (names as the sender sent them)", function()
	local saved = ns.rdb.guilds
	ns.rdb.guilds = {}
	eq(ns.Data.Receive({ guild = "Olympus Span", total = 9, online = 1, zones = {}, leader = "Spanboss", from = "Other",
		officers = { { name = "Spancapt", online = true, days = 0 } } }, "Spanboss"), true)
	eq(ns.rdb.guilds["Olympus Span"].realm, "Realm", "the realm of the sender's name, not the report's")
	eq(ns.Data.KnownRank("Spancapt", "Olympus Span"), 1, "a bare guildmate of the reporter matches")
	eq(ns.Data.KnownRank("Spancapt-Other", "Olympus Span"), nil)
	ns.rdb.guilds = saved
end)

test("a report heard by a character on another realm of the group is no previous report here", function()
	local saved = ns.rdb.guilds
	local ok, err = pcall(function()
		ns.rdb.guilds = {}
		local function Rep() return { guild = "Olympus Span", total = 9, online = 1, zones = {}, leader = "Spanboss",
			officers = { { name = "Spancapt", online = true, days = 0 } } } end
		-- Heard by our alt on Other: every bare name took Other.
		local keep = ns.realm
		ns.realm = "Other"
		eq(ns.Data.Receive(Rep(), "Spanboss"), true)
		ns.realm = keep
		local there = ns.rdb.guilds["Olympus Span"]
		eq(there.heardOn, "Other"); eq(there.reporterFull, "Spanboss-Other")
		eq(ns.Data.Receive(Rep(), "Spanboss"), true)
		local here = ns.rdb.guilds["Olympus Span"]
		eq(here.heardOn, "Realm"); eq(here.conflict, nil, "the same reporter and officers, not added ones")
		eq(here.vouch["Spanboss-Other"], nil, "nor a voucher in another form")
		-- Heard here: compared as always.
		eq(ns.Data.Receive(Rep(), "Otherguy"), true)
		eq(ns.rdb.guilds["Olympus Span"].conflict, nil); eq(ns.rdb.guilds["Olympus Span"].vouch["Otherguy-Realm"].ranks["Spancapt-Realm"], 1)
		local r = Rep()
		r.leader = "Usurper"
		ns.Data.Receive(r, "Thirdguy")
		eq(ns.rdb.guilds["Olympus Span"].conflict, true, "a real conflict still shows")
	end)
	ns.rdb.guilds = saved
	if not ok then error(err, 0) end
end)

-- Comm.lua loaded into a namespace of its own (fresh peers, stats and guard) with a clock the
-- test moves. Deliver(dist, sender, text) goes through the real CHAT_MSG_ADDON handler.
local function FreshComm()
	local events, login = {}, {}
	local cns = setmetatable({}, { __index = ns })
	cns.RegisterEvent = function(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end
	cns.On = function(name, fn) if name == "LOGIN" then table.insert(login, fn) end end
	cns.After, cns.Every = function() end, function() end
	cns.clock = 100000
	cns.Now = function() return cns.clock end
	C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
	assert(loadfile(ADDON_DIR .. "Comm.lua"))("Olympus", cns)
	for _, fn in ipairs(login) do fn() end
	local function Deliver(dist, sender, text)
		for _, fn in ipairs(events.CHAT_MSG_ADDON) do fn(ns.PREFIX, text, dist, sender) end
	end
	local id = 0
	local function Report(sender, r)
		id = id + 1
		for _, c in ipairs(ns.Codec.Chunk(ns.Codec.EncodeReport(r), tostring(id))) do Deliver("CHANNEL", sender, c) end
	end
	return cns, Deliver, Report
end

test("runner-up: only a 0.7.11+ peer on the reporter's channel", function()
	local savedChannel = GetChannelName
	local ok, err = pcall(function()
		GetChannelName = function() return 5 end
		local ours = { guild = MY_GUILD, total = 1000, online = 300, zones = {} }
		local cns, Deliver, Report = FreshComm()
		local C = cns.Comm
		C.loginAt = cns.clock - 1000
		C.JoinChannel()
		-- Aaa reports; Bob (before us in the election) runs 0.7.10 and never backs anyone.
		Deliver("GUILD", "Aaa", "H1~0.7.11~Realm~p")
		Deliver("GUILD", "Bob", "H1~0.7.10")
		Report("Aaa", { guild = MY_GUILD, total = 1000, online = 300, zones = {} })
		C.MaybeBroadcast(ours)
		eq(C.isRunnerUp, true, "the old peer is skipped: we back the reporter")
		-- Bcc (before us) is on the sealed channel, the reporter on the public one: skipped too.
		Deliver("GUILD", "Bcc", "H1~0.7.11~Realm~s")
		C.MaybeBroadcast(ours)
		eq(C.isRunnerUp, true, "a peer on the other channel can't back this reporter")
		Deliver("GUILD", "Bdd", "H1~0.7.11~Realm~p")
		C.MaybeBroadcast(ours)
		eq(C.isRunnerUp, false, "a 0.7.11 peer on the same channel comes first")
	end)
	GetChannelName, C_ChatInfo = savedChannel, nil
	if not ok then error(err, 0) end
end)

test("runner-up backs an active reporter; census on request, bounded", function()
	local savedChannel = GetChannelName
	local ok, err = pcall(function()
		local cns, Deliver, Report = FreshComm()
		local C = cns.Comm
		C.loginAt = cns.clock - 1000
		GetChannelName = function() return 5 end
		C.JoinChannel()
		local sent = {}
		C_ChatInfo.SendAddonMessage = function(_, msg, dist) sent[#sent + 1] = dist .. " " .. msg end
		local function Flush() for _ = 1, 40 do C.Pump() end end
		local function Chunks() local n = 0 for _, m in ipairs(sent) do if m:find("^CHANNEL C") then n = n + 1 end end return n end
		local ours = { guild = MY_GUILD, total = 1000, online = 300, zones = {}, leader = "Member1" }
		-- Abe (first in the election) is elected; we are the runner-up. Abe is not heard yet.
		Deliver("GUILD", "Abe", "H1~0.7.11~Realm~p")
		C.MaybeBroadcast(ours)
		eq(C.isReporter, false); eq(C.isRunnerUp, false, "reporter not heard: nothing to back")
		Flush(); eq(Chunks(), 0)
		-- Abe reports on the channel: now we back him, once every 10 minutes.
		Report("Abe", { guild = MY_GUILD, total = 1000, online = 300, zones = {} })
		C.MaybeBroadcast(ours)
		eq(C.isRunnerUp, true)
		Flush(); local first = Chunks(); assert(first > 0, "runner-up report sent")
		cns.clock = cns.clock + 300
		Deliver("GUILD", "Abe", "H1~0.7.11~Realm~p")
		Report("Abe", { guild = MY_GUILD, total = 1000, online = 300, zones = {} })
		C.MaybeBroadcast(ours)
		Flush(); eq(Chunks(), first, "not before 10 minutes")
		cns.clock = cns.clock + 301
		Deliver("GUILD", "Abe", "H1~0.7.11~Realm~p")
		Report("Abe", { guild = MY_GUILD, total = 1000, online = 300, zones = {} })
		C.MaybeBroadcast(ours)
		Flush(); eq(Chunks(), first * 2, "again after 10 minutes")
		-- Census requests: only the elected reporter answers, at most every 2 minutes.
		cns.After = function(_, _, fn) fn() end
		local before = Chunks()
		Deliver("CHANNEL", "Newbie", "Q1~")
		Flush(); eq(Chunks(), before, "the runner-up does not answer")
		cns.clock = cns.clock + 200
		C.MaybeBroadcast(ours) -- Abe was not heard for 200 s but is still elected
		local cns2, Deliver2 = FreshComm()
		local C2 = cns2.Comm
		C2.loginAt = cns2.clock - 1000
		C2.JoinChannel()
		cns2.After = function(_, _, fn) fn() end
		C_ChatInfo.SendAddonMessage = function(_, msg, dist) sent[#sent + 1] = dist .. " " .. msg end
		C2.MaybeBroadcast(ours) -- alone: we are the reporter, and report now
		eq(C2.isReporter, true)
		sent = {}
		Flush()
		for _ = 1, 40 do C2.Pump() end
		local afterOwn = Chunks()
		cns2.clock = cns2.clock + 60
		Deliver2("CHANNEL", "Newbie", "Q1~")
		for _ = 1, 40 do C2.Pump() end
		assert(Chunks() > afterOwn, "the reporter answers a request")
		local afterAnswer = Chunks()
		cns2.clock = cns2.clock + 50
		Deliver2("CHANNEL", "Other", "Q1~")
		for _ = 1, 40 do C2.Pump() end
		eq(Chunks(), afterAnswer, "not twice within 2 minutes")
		eq(C2.Stats().answered, 1)
	end)
	GetChannelName, C_ChatInfo = savedChannel, nil
	if not ok then error(err, 0) end
end)

test("census requests: nobody answers in their first minute, the runner-up answers too", function()
	local savedChannel = GetChannelName
	local ok, err = pcall(function()
		GetChannelName = function() return 5 end
		local ours = { guild = MY_GUILD, total = 1000, online = 300, zones = {} }
		-- Just logged in: alone so far, so we think we are the reporter, but must not answer.
		local cns, Deliver = FreshComm()
		local C = cns.Comm
		C.loginAt = cns.clock
		C.JoinChannel()
		local fired = 0
		cns.After = function(_, _, fn) fired = fired + 1; fn() end
		C.MaybeBroadcast(ours)
		cns.clock = cns.clock + 30
		Deliver("CHANNEL", "Newbie", "Q1~")
		eq(C.Stats().answered, 0, "not in the first minute after login")
		-- Settled, and the runner-up of an active reporter: answers.
		local cns2, Deliver2, Report2 = FreshComm()
		local C2 = cns2.Comm
		C2.loginAt = cns2.clock - 1000
		C2.JoinChannel()
		cns2.After = function(_, _, fn) fn() end
		Deliver2("GUILD", "Abe", "H1~0.7.11~Realm~p")
		Report2("Abe", { guild = MY_GUILD, total = 1000, online = 300, zones = {} })
		C2.MaybeBroadcast(ours)
		eq(C2.isRunnerUp, true)
		cns2.clock = cns2.clock + 60
		Deliver2("CHANNEL", "Newbie", "Q1~")
		eq(C2.Stats().answered, 1, "the runner-up answers")
	end)
	GetChannelName, C_ChatInfo = savedChannel, nil
	if not ok then error(err, 0) end
end)

test("only our channel counts, and chat only through the logged API", function()
	local savedChannel = GetChannelName
	local ok, err = pcall(function()
		local cns, Deliver = FreshComm()
		local C = cns.Comm
		GetChannelName = function() return 5 end
		C.JoinChannel()
		-- Deliver with the channel number the client gives (7th argument of CHAT_MSG_ADDON).
		local handlers = {}
		local seen = 0
		C.Handle("Z9", function() seen = seen + 1 end)
		Deliver("CHANNEL", "Outsider", "Z9~x")
		eq(seen, 1, "no channel number given: accepted, as before")
		local events = {}
		-- The real handler with all arguments: another channel's number is dropped.
		local cns3 = setmetatable({}, { __index = ns })
		local login = {}
		cns3.RegisterEvent = function(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end
		cns3.On = function(name, fn) if name == "LOGIN" then table.insert(login, fn) end end
		cns3.After, cns3.Every = function() end, function() end
		C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessageLogged = function() end }
		assert(loadfile(ADDON_DIR .. "Comm.lua"))("Olympus", cns3)
		for _, fn in ipairs(login) do fn() end
		cns3.Comm.JoinChannel()
		local got = 0
		cns3.Comm.Handle("Z9", function() got = got + 1 end)
		for _, fn in ipairs(events.CHAT_MSG_ADDON) do fn(ns.PREFIX, "Z9~x", "CHANNEL", "Outsider", "", 0, 9, "SomeoneElsesChannel") end
		eq(got, 0, "a message on channel #9 is not ours (#5)")
		eq(cns3.Comm.Stats().otherChannel, 1)
		for _, fn in ipairs(events.CHAT_MSG_ADDON) do fn(ns.PREFIX, "Z9~x", "CHANNEL", "Friend", "", 0, 5, "OlympusNet") end
		eq(got, 1, "ours (#5) is")
		assert(cns3.Comm.Stats().chanArgs:find("localID=9", 1, true), "the first channel's arguments are kept for /oly status")
		eq(cns3.Comm.DeliveredLogged(), false)
		local inside
		cns3.Comm.Handle("Z8", function() inside = cns3.Comm.DeliveredLogged() end)
		for _, fn in ipairs(events.CHAT_MSG_ADDON_LOGGED) do fn(ns.PREFIX, "Z8~x", "CHANNEL", "Friend", "", 0, 5, "OlympusNet") end
		eq(inside, true, "handlers know a message came through the logged API")
		eq(cns3.Comm.DeliveredLogged(), false, "and only while it is handled")
	end)
	GetChannelName, C_ChatInfo = savedChannel, nil
	if not ok then error(err, 0) end
end)

test("a channel number that changed under us holds channel messages", function()
	local savedChannel = GetChannelName
	local ok, err = pcall(function()
		local cns = FreshComm()
		local C = cns.Comm
		local id = 5
		GetChannelName = function() return id end
		C.JoinChannel()
		local sent = {}
		C_ChatInfo.SendAddonMessage = function(_, msg, dist, target) sent[#sent + 1] = dist .. "#" .. tostring(target) .. " " .. msg end
		C.Send("CHANNEL", "Z9~one")
		id = 0 -- the player left the channel (Chat Channels panel)
		C.Pump()
		eq(#sent, 0, "nothing goes to a number that is no longer ours")
		id = 5
		C.JoinChannel()
		C.Pump()
		eq(sent[1], "CHANNEL#5 Z9~one", "sent once we are back")
	end)
	GetChannelName, C_ChatInfo = savedChannel, nil
	if not ok then error(err, 0) end
end)

test("hello: guild peers say their realm, older versions count as old", function()
	local ok, err = pcall(function()
		local cns, Deliver = FreshComm()
		Deliver("GUILD", "Abe-ClassicBetaPvP2", "H1~0.7.11~ClassicBetaPvP2")
		Deliver("GUILD", "Bob", "H1~0.7.10")
		Deliver("GUILD", "Cy", "H1~0.7.11~Bad|cffRealm")
		local st = cns.Comm.Stats()
		eq(st.peers, 3); eq(st.peerRealms.ClassicBetaPvP2, 1); eq(st.peerRealms.old, 2, "no realm, or not a realm")
		eq(st.raw.g.bare, 2, "counted as sent, before our realm is added"); eq(st.raw.g.ClassicBetaPvP2, 1)
		eq(st.rawSample.g, "Abe-ClassicBetaPvP2")
		local sent = {}
		C_ChatInfo.SendAddonMessage = function(_, msg, dist) sent[#sent + 1] = dist .. " " .. msg end
		cns.Comm.Hello()
		cns.Comm.Pump()
		eq(sent[1], "GUILD H1~" .. ns.VERSION .. "~Realm~p", "ours names our realm and channel (public)")
		local savedKey = ns.rdb.realmKey
		ns.rdb.realmKey = "secret"
		cns.clock = cns.clock + 600
		cns.Comm.Hello()
		cns.Comm.Pump()
		ns.rdb.realmKey = savedKey
		eq(sent[2], "GUILD H1~" .. ns.VERSION .. "~Realm~s", "sealed")
	end)
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)

test("a report sent from another realm proves the channel is shared", function()
	local saved = { guilds = ns.rdb.guilds, shared = ns.rdb.shared }
	local ok, err = pcall(function()
		local cns, _, Report = FreshComm()
		ns.rdb.guilds, ns.rdb.shared = {}, nil
		Report("Nearby", { guild = "Olympus Near", total = 5, online = 1, zones = {}, from = "Realm" })
		eq(ns.rdb.shared, nil, "a report from our own realm proves nothing")
		Report("Faraway-Other", { guild = "Olympus Far", total = 7, online = 2, zones = {}, from = "Other" })
		eq(ns.rdb.shared.realm, "Other"); eq(ns.rdb.shared.to, "Realm")
		Report("Oldtimer-Realm", { guild = "Olympus Old", total = 3, online = 1, zones = {} })
		local st = cns.Comm.Stats()
		eq(st.reportRealms.Realm, 1); eq(st.reportRealms.Other, 1); eq(st.reportRealms.old, 1, "older versions send no realm")
		eq(st.raw.ch.bare, 1, "Nearby came without a realm..."); eq(ns.rdb.guilds["Olympus Near"].reporterFull, "Nearby-Realm", "...and got ours")
		eq(st.raw.ch.Other, 1); eq(st.raw.ch.Realm, 1)
		eq(ns.rdb.guilds["Olympus Far"].from, "Other")
		assert(ns.StatusText():find("channel SHARED (Other -> Realm", 1, true), "in /oly status")
	end)
	ns.rdb.guilds, ns.rdb.shared = saved.guilds, saved.shared
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)

test("election guard: a reporter never heard on the channel is left out a while, one that is heard stays", function()
	local savedChannel = GetChannelName
	local ok, err = pcall(function()
		local cns, Deliver, Report = FreshComm()
		local C = cns.Comm
		C.loginAt = cns.clock - 1000
		local ours = { guild = MY_GUILD, total = 1000, online = 300, zones = {} }
		local function Tick(seconds, hellos, heard)
			cns.clock = cns.clock + seconds
			for _, name in ipairs(hellos) do Deliver("GUILD", name, "H1~0.7.11~Realm") end
			for _, name in ipairs(heard or {}) do Report(name, ours) end
			C.MaybeBroadcast(ours)
		end
		Tick(0, { "Abe" })
		eq(C.reporterName, "Abe", "Abe sorts first")
		for _ = 1, 10 do Tick(60, { "Abe" }) end
		eq(C.reporterName, "Abe", "we are not on the channel: we could not have heard it")
		GetChannelName = function() return 5 end
		C.JoinChannel()
		Tick(0, { "Abe" })
		for _ = 1, 6 do Tick(60, { "Abe" }) end
		eq(C.reporterName, "Abe", "on the channel 360 s: not yet")
		Tick(60, { "Abe" })
		eq(C.reporterName, "Tester", "never heard in 400 s: left out, we report"); eq(C.isReporter, true)
		eq(C.Stats().benched[1], "Abe")
		eq(C.Stats().queue > 0, true, "and our report goes out")
		-- Aaron sorts first and is heard every 180 s: elected and kept.
		for _ = 1, 8 do Tick(180, { "Abe", "Aaron" }, { "Aaron" }) end
		eq(C.reporterName, "Aaron", "heard: stays elected")
		eq(C.Stats().heardOwn, "Aaron")
		-- Aaron logs off; 30 minutes after it was left out, Abe may be elected again.
		Tick(1800 - 8 * 180, { "Abe" })
		eq(#C.Stats().benched, 0); eq(C.reporterName, "Abe")
		-- A peer left out is back as soon as it is heard.
		for _ = 1, 7 do Tick(60, { "Abe" }) end
		eq(C.reporterName, "Tester")
		Report("Abe", ours)
		Tick(0, { "Abe" })
		eq(C.reporterName, "Abe", "heard: in again")
	end)
	GetChannelName, C_ChatInfo = savedChannel, nil
	if not ok then error(err, 0) end
end)

test("election guard: a reporter named with its realm over GUILD and without it on the channel is heard", function()
	local savedChannel = GetChannelName
	local ok, err = pcall(function()
		local cns, Deliver, Report = FreshComm()
		local C = cns.Comm
		C.loginAt = cns.clock - 1000
		local ours = { guild = MY_GUILD, total = 1000, online = 300, zones = {} }
		GetChannelName = function() return 5 end
		C.JoinChannel()
		local function Tick(seconds, heard)
			cns.clock = cns.clock + seconds
			Deliver("GUILD", "Abe-ClassicBetaPvP2", "H1~0.7.11~ClassicBetaPvP2~p")
			if heard then Report("Abe", ours) end
			C.MaybeBroadcast(ours)
		end
		Tick(0)
		for _ = 1, 8 do Tick(180, true) end
		eq(C.reporterName, "Abe-ClassicBetaPvP2", "heard as Abe: stays elected"); eq(#C.Stats().benched, 0)
		for _ = 1, 3 do Tick(180) end
		eq(C.reporterName, "Tester", "silent: left out"); eq(C.Stats().benched[1], "Abe-ClassicBetaPvP2")
		Tick(0, true)
		eq(C.reporterName, "Abe-ClassicBetaPvP2", "heard as Abe: in again")
	end)
	GetChannelName, C_ChatInfo = savedChannel, nil
	if not ok then error(err, 0) end
end)

test("election guard: a sealed reporter is not judged without the key, and another channel starts the watch again", function()
	local savedChannel, savedKey, savedLeave = GetChannelName, ns.rdb.realmKey, LeaveChannelByName
	local ok, err = pcall(function()
		LeaveChannelByName = function() end
		local cns, Deliver = FreshComm()
		local C = cns.Comm
		C.loginAt = cns.clock - 1000
		local ours = { guild = MY_GUILD, total = 1000, online = 300, zones = {} }
		local sent = {}
		C_ChatInfo.SendAddonMessage = function(_, msg, dist) sent[#sent + 1] = dist .. " " .. msg end
		ns.rdb.realmKey = nil
		GetChannelName = function() return 5 end
		C.JoinChannel()
		eq(C.ChannelName(), "OlympusNet")
		local function Tick(seconds, flag)
			cns.clock = cns.clock + seconds
			Deliver("GUILD", "Abe", "H1~0.7.11~Realm" .. (flag and ("~" .. flag) or ""))
			C.MaybeBroadcast(ours)
		end
		for _ = 1, 12 do Tick(60, "s") end
		eq(C.reporterName, "Abe", "on the sealed channel: we can't hear it, so we don't judge it"); eq(#C.Stats().benched, 0)
		eq(C.Stats().queue, 1, "we ask for the key instead...")
		C.Pump()
		eq(sent[1], "GUILD K0~")
		for _ = 1, 5 do Tick(60, "s") end
		eq(C.Stats().queue, 0, "...not every minute")
		-- An older version says nothing about its channel: judged as before, watched from now.
		for _ = 1, 5 do Tick(60) end
		eq(C.reporterName, "Abe")
		-- The key arrives: another channel, and what we did not hear on the public one says nothing.
		ns.rdb.realmKey = "secret"
		C.JoinChannel()
		assert(C.ChannelName() ~= "OlympusNet", "sealed channel")
		Tick(0)
		for _ = 1, 6 do Tick(60) end
		eq(C.reporterName, "Abe", "360 s on the sealed channel: not yet")
		Tick(60)
		eq(C.reporterName, "Tester", "400 s there: left out")
		-- We have the key: a peer on the public channel is judged like any other.
		local cns2, Deliver2 = FreshComm()
		local C2 = cns2.Comm
		C2.loginAt = cns2.clock - 1000
		C2.JoinChannel()
		for _ = 1, 8 do
			cns2.clock = cns2.clock + 60
			Deliver2("GUILD", "Abe", "H1~0.7.11~Realm~p")
			C2.MaybeBroadcast(ours)
		end
		eq(C2.reporterName, "Tester", "public reporter, never heard on our sealed channel: left out")
	end)
	GetChannelName, C_ChatInfo, ns.rdb.realmKey, LeaveChannelByName = savedChannel, nil, savedKey, savedLeave
	if not ok then error(err, 0) end
end)

test("who: a guild named with a realm of our census group is the same guild", function()
	local savedGroup = ns.group
	local ok, err = pcall(WithWho, function(server)
		ns.group = "Other+Realm"
		ns.Who.Search()
		server.Answer({
			{ "Aa", "OLYMPUS VII-Other", 12 }, { "Bb", "OLYMPUS VII", 14 }, { "Cc-Far", "OLYMPUS VII-Faraway", 9 },
			{ "Dd", "OLYMPUS I-Realm", 20 },
		})
		server.Run()
		local seen = ns.rdb.seen
		eq(seen["OLYMPUS VII"].online, 2, "OLYMPUS VII-Other is OLYMPUS VII"); eq(seen["OLYMPUS VII-Other"], nil)
		eq(seen["OLYMPUS I"].online, 1, "so is a guild named with our own realm")
		eq(seen["OLYMPUS VII-Faraway"].online, 1, "a realm outside the group keeps its name")
		local names, suffixed, sample = ns.Who.RawCounts()
		eq(names.bare, 3); eq(names.Far, 1); eq(suffixed, 3); eq(sample, "Cc-Far")
	end)
	ns.group = savedGroup
	if not ok then error(err, 0) end
end)

test("/oly status: realm, census, raw names and topology, short, and without the newer realm APIs", function()
	local keep = { group = ns.group, realm = ns.realm, shared = ns.rdb.shared, info = GetGuildInfo, Stats = ns.Comm.Stats, RawCounts = ns.Who.RawCounts }
	local ok, err = pcall(function()
		eq(C_AutoComplete, nil); eq(GetNativeRealmID, nil); eq(RegionalUniqueNamesEnabled, nil); eq(GetRealmID, nil)
		local text = ns.StatusText()
		for _, want in ipairs({ "id=nil native=nil guid=nil", "unique names=?", "connected=n/a", "shared: not seen yet" }) do
			assert(text:find(want, 1, true), want .. "\n" .. text)
		end
		ns.realm, ns.group = "ClassicBetaPvP", BETA
		C_AutoComplete = { GetAutoCompleteRealms = function() return {} end }
		GetRealmID = function() return 4619 end
		GetNativeRealmID = function() error("not on this client") end
		RegionalUniqueNamesEnabled = function() return true end
		UnitGUID = function() return "Player-4619-0A1B2C3D" end
		GetRealmName = function() return "Classic Beta PvP" end
		ns.rdb.shared = { realm = "ClassicBetaPvP2", to = "ClassicBetaPvP", t = os.time() - 250 }
		text = ns.StatusText()
		for _, want in ipairs({ "realm: Classic Beta PvP = ClassicBetaPvP  id=4619 native=nil guid=4619  guild home=ours",
			"census: " .. BETA .. " (seed)  unique names=true  connected=none", "names raw: roster Realm=1000  e.g. [Member1-Realm]",
			"names raw: roster by server (GUID) ?=1000", "topology: channel SHARED (ClassicBetaPvP2 -> ClassicBetaPvP, 4m ago)",
			"topology: guild peers by realm" }) do
			assert(text:find(want, 1, true), want .. "\n" .. text)
		end
		-- The longest these lines get on the beta: still short.
		local long = "Bellattrixx Lesstrange-ClassicBetaPvP2"
		GetGuildInfo = function() return MY_GUILD, "Hero", 3, "ClassicBetaPvP2" end
		GetNativeRealmID = function() return 4620 end
		C_AutoComplete.GetAutoCompleteRealms = function() return { "Classic Beta PvP", "Classic Beta PvP 2", "Classic Beta PvE", "Classic Beta RP" } end
		local R = ns.Roster
		local raw = { bare = 300, ClassicBetaPvP2 = 263 } -- names as sent: bare, or with PvP 2
		local realms = { ClassicBetaPvP = 300, ClassicBetaPvP2 = 263, old = 12 }
		R.rawRealms, R.servers, R.rawSample = raw, { ["4619"] = 300, ["4620"] = 263 }, long
		ns.Comm.Stats = function()
			local c = keep.Stats()
			c.raw, c.rawSample = { ch = raw, g = raw }, { ch = long, g = long }
			c.reportRealms, c.peerRealms, c.heardOwn, c.heardOwnAt, c.benched = realms, realms, long, os.time() - 100, { long }
			return c
		end
		ns.Who.RawCounts = function() return raw, 30, long end
		text = ns.StatusText()
		local checked = 0
		for line in text:gmatch("[^\n]+") do
			if line:find("^realm:") or line:find("^census:") or line:find("^names raw:") or line:find("^topology:") then
				checked = checked + 1
				assert(#line <= 110, ("too long for the /oly bug window (%d): %s"):format(#line, line))
			end
		end
		eq(checked, 12)
		assert(text:find("connected=ClassicBetaPvP2,ClassicBetaPvE,+1", 1, true), "ours left out, two named\n" .. text)
	end)
	C_AutoComplete, GetRealmID, GetNativeRealmID, RegionalUniqueNamesEnabled, UnitGUID = nil, nil, nil, nil, nil
	GetRealmName = function() return "Realm" end
	GetGuildInfo, ns.Comm.Stats, ns.Who.RawCounts = keep.info, keep.Stats, keep.RawCounts
	ns.group, ns.realm, ns.rdb.shared = keep.group, keep.realm, keep.shared
	ns.Roster.Scan() -- the roster counts of the other tests back
	if not ok then error(err, 0) end
end)

test("census subtitle names the realms sharing it", function()
	local savedGroup = ns.group
	local uns = setmetatable({}, { __index = ns })
	uns.On = function() end
	assert(loadfile(ADDON_DIR .. "UI.lua"))("Olympus", uns)
	ns.group = BETA
	eq(uns.UI.CensusName(), "ClassicBetaPvP + ClassicBetaPvP2")
	ns.group = "Realm"
	eq(uns.UI.CensusName(), "Realm", "one realm: its name")
	ns.group = savedGroup
end)

---------------------------------------------------------------------------
-- After an update adds files, /reload keeps the old file list until the game restarts.
---------------------------------------------------------------------------

test("files added by an update and not loaded yet: stand-ins keep everything else working", function()
	local savedSlash, savedEvents, savedPrint = {}, #EVENT_SCRIPTS, print
	for k, v in pairs(SlashCmdList) do savedSlash[k] = v end
	local printed = {}
	print = function(msg) printed[#printed + 1] = tostring(msg) end
	local ok, err = pcall(function()
		local fresh = {}
		for _, file in ipairs({ "Bootstrap", "Locales", "Core", "Diagnostics", "Codec", "Zones", "Data", "Roster", "Comm", "Recruit", "Views" }) do
			assert(loadfile(ADDON_DIR .. file .. ".lua"))("Olympus", fresh)
		end
		eq(fresh.Who.missing, true, "Who.lua stood in for")
		eq(fresh.Channels.missing, true, "Channels.lua stood in for")
		eq(fresh.Who.StatusLines(), nil, "any other call is a quiet no-op")
		fresh.Who.Search()
		eq(printed[#printed]:find("reopen the game", 1, true) ~= nil, true, "a search says to restart the game")
		fresh.Channels.Send("A", "hi")
		eq(printed[#printed]:find("reopen the game", 1, true) ~= nil, true, "so does a channel message")
	end)
	print = savedPrint
	for k in pairs(SlashCmdList) do SlashCmdList[k] = savedSlash[k] end
	for i = #EVENT_SCRIPTS, savedEvents + 1, -1 do EVENT_SCRIPTS[i] = nil end
	if not ok then error(err, 0) end
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
