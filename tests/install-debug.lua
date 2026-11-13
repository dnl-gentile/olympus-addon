-- 1.5.5: an install that does not fit the game (a player: "an install in the wrong flavor folder
-- changes the counts"; the CurseForge app's installation for Forever's folder left on Classic installs
-- an old Olympus) is told at login and heads /oly bug, and /oly bug carries a bounded debug section
-- after its status: per kind of message in pieces, the relay and the reporter, the census's sources per realm group,
-- the signed lists, the install. No other player's name or data, no BattleTag. Diagnostics.lua,
-- Codec.lua (Codec.PieceStats). Loaded by tests/run.lua.
local ns, test, eq, extra = ...
local ROOT = assert(extra and extra.ROOT, "tests/run.lua hands ROOT to this file")

-- The game and the installed files as fn's world: toc (GetBuildInfo's interface), the TOC versions
-- (C_AddOns.GetAddOnMetadata), the guildmates' versions (Comm.PeerVersions) and the author's released
-- version as Workshop.Behind answers. All put back after.
local function WithInstall(w, fn)
	local saved = { build = GetBuildInfo, addons = C_AddOns, peers = ns.Comm.PeerVersions, behind = ns.Workshop.Behind,
		author = ns.Workshop.AuthorVersion }
	local ok, err = pcall(function()
		GetBuildInfo = function() return w.game or "1.60.1", "70888", "Oct 1 2026", w.toc or 16001 end
		local meta = { Olympus = w.tocVersion or ns.VERSION, Olympus_Arena = w.arena, OlympusSiteAggregate = w.site }
		C_AddOns = setmetatable({ GetAddOnMetadata = function(addon, field)
			if field ~= "Version" then return nil end
			return meta[addon]
		end }, { __index = saved.addons })
		ns.Comm.PeerVersions = function() return w.peers or { [ns.VERSION] = 1 } end
		ns.Workshop.Behind = function() return w.behind end
		ns.Workshop.AuthorVersion = function() return w.behind end
		ns.ResetInstallWarnings()
		fn()
	end)
	GetBuildInfo, C_AddOns, ns.Comm.PeerVersions, ns.Workshop.Behind, ns.Workshop.AuthorVersion =
		saved.build, saved.addons, saved.peers, saved.behind, saved.author
	ns.ResetInstallWarnings()
	if not ok then error(err, 0) end
end
local function Has(list, value) for _, v in ipairs(list) do if v == value then return true end end return false end
local NEWER = "99.0.0" -- (newer than any version this file will run on)

test("1.5.5 install: the interfaces Diagnostics checks are Olympus.toc's Interface line, the same in the arena's and the site reporter's TOC", function()
	local function Interfaces(path)
		for line in io.lines(path) do
			local list = line:match("^## Interface:%s*(.-)%s*$")
			if list then
				local out = {}
				for n in list:gmatch("%d+") do out[#out + 1] = tonumber(n) end
				return out
			end
		end
	end
	local toc = assert(Interfaces(ROOT .. "Olympus/Olympus.toc"))
	eq(#ns.TOC_INTERFACES, #toc, "as many interfaces")
	for i, n in ipairs(toc) do eq(ns.TOC_INTERFACES[i], n, "interface " .. i) end
	for _, other in ipairs({ "Olympus_Arena/Olympus_Arena.toc", "OlympusSiteAggregate/OlympusSiteAggregate.toc" }) do
		local list = assert(Interfaces(ROOT .. other), other)
		eq(table.concat(list, ","), table.concat(toc, ","), other)
	end
end)

test("1.5.5 install: a Forever client this copy lists, its files of one version, nobody newer: no problem, nothing said, /oly bug starts as before", function()
	WithInstall({ toc = 16001, arena = ns.VERSION, site = ns.VERSION .. "-site.1", peers = { [ns.VERSION] = 4, ["1.4.6"] = 2 } }, function()
		local s = ns.Install()
		eq(s.client, "Forever"); eq(s.declared, true); eq(#s.problems, 0, table.concat(s.problems, ","))
		eq(#ns.InstallWarnings(), 0, "nothing said")
		local line = ns.InstallLine()
		assert(line:find("install: problems none  |  client Forever (toc 16001, in Olympus.toc: yes", 1, true), line)
		local report = ns.BuildBugReport()
		assert(not report:find("INSTALL PROBLEM", 1, true), "no install line on top")
		assert(report:find("\ndebug (1.5.5):\ninstall: problems none  |  client Forever", 1, true), "the debug section, its install line first")
	end)
	-- Era and Anniversary are clients this copy lists too.
	WithInstall({ toc = 11510 }, function() eq(ns.Install().client, "Era"); eq(#ns.Install().problems, 0) end)
	WithInstall({ toc = 20507 }, function() eq(ns.Install().client, "Anniversary"); eq(#ns.Install().problems, 0) end)
end)

-- (The independent check of the 1.5.5 lane: two guildmates on a test build of the next version, or
-- two forged hellos, made every guildmate see "INSTALL PROBLEM: behind" and an update notice with
-- nothing on CurseForge. Hellos are unsigned: shown in /oly bug, marked so, never a problem.)
test("1.5.5 install: guildmates' hellos never make an install problem, however many name a newer release; only the author's released version does", function()
	for _, count in ipairs({ 2, 40 }) do
		WithInstall({ peers = { [ns.VERSION] = 3, [NEWER] = count } }, function()
			local s = ns.Install()
			eq(#s.problems, 0, count .. " hellos: " .. table.concat(s.problems, ",")); eq(s.behind, nil)
			eq(#ns.InstallWarnings(), 0, count .. " hellos: nothing said at login")
			assert(not ns.BuildBugReport():find("INSTALL PROBLEM", 1, true), count .. " hellos: no install line on top")
			assert(ns.InstallFilesLine():find("guild hellos " .. NEWER .. " x" .. count .. " (unsigned)", 1, true), ns.InstallFilesLine())
		end)
	end
	WithInstall({ peers = { [ns.VERSION] = 3, [NEWER] = 1 } }, function()
		eq(#ns.Install().problems, 0)
		assert(ns.InstallFilesLine():find("guild hellos none newer", 1, true), ns.InstallFilesLine())
	end)
	WithInstall({ peers = { [ns.VERSION] = 3, [NEWER .. "-mod"] = 5, ["?"] = 4 } }, function()
		eq(#ns.Install().problems, 0, "no release's form, no version")
	end)
	-- The author's released version newer (his presence, under a name pinned as his: Workshop.Behind):
	-- his own line says so (Workshop.HeardVersion), this adds the app's installation.
	WithInstall({ behind = NEWER, peers = { [ns.VERSION] = 3 } }, function()
		local s = ns.Install()
		eq(table.concat(s.problems, ","), "behind"); eq(s.behind, NEWER)
		local said = ns.InstallWarnings()
		eq(#said, 1); eq(said[1], ns.L.INSTALL_FLAVOR)
		eq(#ns.InstallWarnings(), 0, "once a session")
		local report = ns.BuildBugReport()
		assert(report:find("^```\nINSTALL PROBLEM: behind %(Olympus " .. ns.VERSION:gsub("%.", "%%.")), report:sub(1, 200))
		assert(ns.InstallFilesLine():find("released: author " .. NEWER, 1, true), ns.InstallFilesLine())
	end)
end)

-- (The independent check: the "toc" problem matched the interface number exactly, so Forever's next
-- patch, before an Olympus lists it, would have told every player at login to update and to change
-- the CurseForge app's installation, with no update to get.)
test("1.5.5 install: a patch of a game this copy is made for whose number Olympus.toc does not list is a note in /oly bug alone, never told", function()
	-- (Olympus.toc lists Forever's 16001-16005, 16010 and 16100: its 16006 falls between them.)
	local patches = { { 16006, "Forever", "unlisted" }, { 16200, "Forever", "newer" }, { 11511, "Era", "newer" },
		{ 11508, "Era", "older" }, { 20508, "Anniversary", "newer" } }
	for _, p in ipairs(patches) do
		local toc, client, note = p[1], p[2], p[3]
		WithInstall({ toc = toc }, function()
			local s = ns.Install()
			eq(#s.problems, 0, toc .. ": " .. table.concat(s.problems, ","))
			eq(#ns.InstallWarnings(), 0, toc .. ": nothing said at login")
			assert(not ns.BuildBugReport():find("INSTALL PROBLEM", 1, true), toc .. ": no install line on top")
			eq(s.client, client); eq(s.declared, false); eq(s.note, note, toc .. "'s note")
			local line = ("install: problems none  |  client %s (toc %d, in Olympus.toc: no, %s %s patch: a note, not told"):format(client, toc, note, client)
			assert(ns.InstallLine():find(line, 1, true), ns.InstallLine())
		end)
	end
	-- No interface from the client (GetBuildInfo failing): nothing to judge, a note too.
	WithInstall({}, function()
		GetBuildInfo = function() error("no build info") end
		local s = ns.Install()
		eq(#s.problems, 0, table.concat(s.problems, ",")); eq(#ns.InstallWarnings(), 0); eq(s.note, "unread")
		assert(ns.InstallLine():find("in Olympus.toc: interface not read: a note, not told", 1, true), ns.InstallLine())
	end)
	-- On such a patch, files of two versions are still a problem, told with the game's own installation.
	WithInstall({ toc = 16006, arena = "1.4.6" }, function()
		eq(table.concat(ns.Install().problems, ","), "mixed")
		local said = ns.InstallWarnings()
		eq(#said, 2); eq(said[1], ns.L.INSTALL_MIXED:format(ns.VERSION, "1.4.6")); eq(said[2], ns.L.INSTALL_FLAVOR)
	end)
end)

-- (The independent check: the CurseForge app hint always named WoW: Forever, wrong advice on the Era
-- and Anniversary clients the TOC also lists; followed, it caused the wrong-flavor install it is for.)
test("1.5.5 install: the CurseForge app's installation the hint names is the player's own game: Forever, Era or Anniversary", function()
	for toc, key in pairs({ [16001] = "INSTALL_FLAVOR", [11510] = "INSTALL_FLAVOR_ERA", [20507] = "INSTALL_FLAVOR_ANNIVERSARY" }) do
		WithInstall({ toc = toc, arena = "1.4.6" }, function()
			local said = ns.InstallWarnings()
			eq(#said, 2, toc .. ": the problem, then the hint")
			eq(said[1], ns.L.INSTALL_MIXED:format(ns.VERSION, "1.4.6"))
			eq(said[2], ns.L[key], toc .. ": " .. key)
		end)
		WithInstall({ toc = toc, behind = NEWER }, function()
			local said = ns.InstallWarnings()
			eq(#said, 1); eq(said[1], ns.L[key], toc .. " behind: " .. key)
		end)
	end
	-- Each hint names its own game's installation, in every language file.
	local names = { INSTALL_FLAVOR = "WoW: Forever,", INSTALL_FLAVOR_ERA = "_classic_era_", INSTALL_FLAVOR_ANNIVERSARY = "_anniversary_" }
	for key, name in pairs(names) do assert(ns.L[key]:find(name, 1, true), key .. ": " .. ns.L[key]) end
	local found = {}
	for _, file in ipairs({ "Locales.lua", "Locales/deDE.lua", "Locales/esES.lua", "Locales/frFR.lua", "Locales/itIT.lua", "Locales/ruRU.lua" }) do
		for line in io.lines(ROOT .. "Olympus/" .. file) do
			local key = line:match("^%s*L?%.?(INSTALL_FLAVOR[%u_]*) = ")
			if key then
				assert(names[key] and line:find(names[key], 1, true), file .. ": " .. line)
				found[key] = (found[key] or 0) + 1
			end
		end
	end
	for key in pairs(names) do eq(found[key], 7, key .. " in the 7 languages") end
end)

test("1.5.5 install: another game's interface (none of that game's in Olympus.toc) and files of two versions (an arena or a site reporter left from another install) are told and head /oly bug", function()
	for _, toc in ipairs({ 50500, 110205 }) do
		WithInstall({ toc = toc }, function()
			local s = ns.Install()
			eq(s.client, "?"); eq(s.declared, false); eq(s.note, nil); assert(Has(s.problems, "toc"))
			local said = ns.InstallWarnings()
			eq(#said, 1, toc .. ": no CurseForge installation to name for a game Olympus is not made for")
			eq(said[1], ns.L.INSTALL_TOC:format(ns.VERSION, tostring(toc)))
			assert(ns.BuildBugReport():find("INSTALL PROBLEM: toc", 1, true))
			assert(ns.InstallLine():find("in Olympus.toc: NO", 1, true), ns.InstallLine())
		end)
	end
	WithInstall({ arena = "1.4.6" }, function()
		assert(Has(ns.Install().problems, "mixed"), "an old arena folder")
		eq(ns.InstallWarnings()[1], ns.L.INSTALL_MIXED:format(ns.VERSION, "1.4.6"))
	end)
	WithInstall({ tocVersion = "1.4.6" }, function() assert(Has(ns.Install().problems, "mixed"), "an old TOC over new files") end)
	WithInstall({ site = "1.4.6-site.1" }, function() assert(Has(ns.Install().problems, "mixed"), "an old site reporter") end)
	WithInstall({ site = ns.VERSION .. "-site.3" }, function() eq(#ns.Install().problems, 0, "the site reporter's own build number") end)
	WithInstall({ tocVersion = ns.VERSION .. "-test.3" }, function() eq(#ns.Install().problems, 0, "an arena test build's TOC (scripts/package.sh --test)") end)
	WithInstall({ arena = ns.VERSION .. "-test.3" }, function() assert(Has(ns.Install().problems, "mixed"), "the arena module's version is ours alone") end)
	-- The message in every language keeps the English one's codes (tests/locales-full.lua checks the rest).
	for _, k in ipairs({ "INSTALL_TOC", "INSTALL_MIXED", "INSTALL_FLAVOR", "INSTALL_FLAVOR_ERA", "INSTALL_FLAVOR_ANNIVERSARY" }) do
		assert(type(ns.L[k]) == "string" and ns.L[k] ~= k, k)
	end
end)

test("1.5.5 install: /oly bug's install lines name the problems first and each stays within one debug line, their longest fields filled", function()
	local savedRealm, savedGroup = ns.realm, ns.group
	local ok, err = pcall(function()
		ns.realm, ns.group = "CAMWOWUS12Realm12PvE", "ForeverPvE"
		WithInstall({ toc = 20508, game = "2.5.5", tocVersion = ns.VERSION .. "-test.12", arena = "1.4.6", site = "1.4.6-site.12",
			behind = "10.12.12", peers = { [ns.VERSION] = 3, ["10.12.13"] = 120 } }, function()
			local line, files = ns.InstallLine(), ns.InstallFilesLine()
			assert(line:find("^install: problems mixed, behind  |  client Anniversary %(toc 20508, in Olympus%.toc: no, newer Anniversary patch"), line)
			assert(files:find("^install files: Olympus " .. ns.VERSION:gsub("%.", "%%.") .. " %(toc "), files)
			assert(files:find("released: author 10.12.12, guild hellos 10.12.13 x120 (unsigned)", 1, true), files)
			assert(#line <= ns.DEBUG_LINE, #line .. " bytes: " .. line)
			assert(#files <= ns.DEBUG_LINE, #files .. " bytes: " .. files)
			local debug = table.concat(ns.DebugLines(), "\n")
			assert(debug:find("\n" .. line .. "\n" .. files .. "\n", 1, true), "both in the debug section, whole: " .. debug)
		end)
	end)
	ns.realm, ns.group = savedRealm, savedGroup
	if not ok then error(err, 0) end
end)

-- (The independent check: the debug section, up to DEBUG_MAX bytes, came before the status, so a
-- report sent in game, cut at Workshop.BUG_MAX, carried that much less of the status.)
test("1.5.5 /oly bug: the status comes first and the debug section after it, so a report sent in game carries the whole status it carried before 1.5.5", function()
	local savedStatus, savedBlocked = ns.StatusText, ns.db.actionsBlocked
	local ok, err = pcall(function()
		WithInstall({ toc = 16001 }, function()
			ns.db.actionsBlocked = {}
			-- A status as long as a report sent in game can carry after its fence: lines with the
			-- status's separators (sent as "!"), each line break sent as two bytes (Workshop's Pack).
			local lines, size, budget = {}, 4, ns.Workshop.BUG_MAX - 8 - 40
			while true do
				local line = ("status line %02d: value %d  |  other value %d"):format(#lines + 1, #lines + 1, (#lines + 1) * 7)
				if size + #line + 2 > budget then break end
				lines[#lines + 1] = line
				size = size + #line + 2
			end
			local status = table.concat(lines, "\n")
			ns.StatusText = function() return status end
			local report = ns.BuildBugReport()
			eq(report:sub(1, 4 + #status), "```\n" .. status, "the status first")
			local at = report:find("\ndebug (1.5.5):\ninstall: ", 1, true)
			assert(at and at > 4 + #status, "the debug section after the status")
			local sent = ns.Workshop.Outgoing(report)
			assert(sent:find((status:gsub("|", "!")), 1, true), "the report sent in game carries the whole status")
			assert(#sent < #report, "and is cut (the debug section and the rest are past BUG_MAX)")
		end)
	end)
	ns.StatusText, ns.db.actionsBlocked = savedStatus, savedBlocked
	if not ok then error(err, 0) end
end)

test("1.5.5 /oly bug debug: per kind of message in pieces, what was put together, dropped incomplete (stale, old) or refused (full, bad, restart)", function()
	local C = ns.Codec
	C.ResetPieceStats()
	local asm, now = C.NewAssembler(), 1000
	-- A list in two pieces, put together.
	eq(C.Feed(asm, "A-Realm", "C1:1:2:CX~1~", now), nil)
	eq(C.Feed(asm, "A-Realm", "C1:2:2:rest", now), "CX~1~rest")
	-- A report whose second and third pieces never come: dropped after a minute (stale).
	eq(C.Feed(asm, "B-Realm", "C2:1:3:R2^Olympus", now), nil)
	-- A piece whose first piece never came: its kind unknown.
	eq(C.Feed(asm, "B-Realm", "C3:2:2:tail", now), nil)
	-- A piece out of bounds, and a first piece of another length under an open id (the pieces before lost).
	eq(C.Feed(asm, "D-Realm", "C4:3:2:LS~x", now), nil)
	eq(C.Feed(asm, "E-Realm", "C5:1:3:WK~a", now), nil)
	eq(C.Feed(asm, "E-Realm", "C5:1:2:WK~b", now), nil)
	-- A sender holding OPEN_PER_SENDER open messages: the next one finds no room.
	for i = 1, C.OPEN_PER_SENDER do C.Feed(asm, "F-Realm", ("C9%d:1:2:H3~%d"):format(i, i), now) end
	eq(C.Feed(asm, "F-Realm", "C99:1:2:H3~full", now), nil)
	C.Gc(asm, now + 61)
	local st = C.PieceStats()
	eq(st.pieces, 8 + C.OPEN_PER_SENDER)
	local k = st.kinds
	eq(k.CX.a, 1); eq(k.CX.p, 2); eq(k.CX.i, 0); eq(k.CX.d, 0)
	eq(k.R2.i, 1, "the report dropped incomplete"); eq(k.R2.p, 1)
	eq(k["?"].i, 1, "the piece whose first never came"); eq(k["?"].d, 1, "and the one out of bounds")
	eq(k.WK.d, 1, "the restarted one"); eq(k.WK.i, 1, "then its new one dropped")
	eq(k.H3.d, 1, "no room"); eq(k.H3.i, C.OPEN_PER_SENDER)
	eq(st.why.stale, 3 + C.OPEN_PER_SENDER); eq(st.why.full, 1); eq(st.why.bad, 1); eq(st.why.restart, 1); eq(st.why.old, nil)
	-- Open longer than ASM_MAX_AGE, its pieces still coming: "old".
	local asm2 = C.NewAssembler()
	C.Feed(asm2, "G-Realm", "C7:1:3:RG~1", now)
	C.Feed(asm2, "G-Realm", "C7:2:3:2", now + C.ASM_MAX_AGE)
	C.Gc(asm2, now + C.ASM_MAX_AGE + 1)
	eq(C.PieceStats().why.old, 1); eq(C.PieceStats().kinds.RG.i, 1)
	-- Bounded: KINDS_MAX kinds, the rest as "other".
	local asm3 = C.NewAssembler()
	for i = 1, C.KINDS_MAX + 10 do C.Feed(asm3, "H" .. i .. "-Realm", ("C1:1:1:%s~"):format(("%02d"):format(i):gsub("%d", function(d) return string.char(65 + tonumber(d)) end)), now) end
	local kinds = 0
	for _ in pairs(C.PieceStats().kinds) do kinds = kinds + 1 end
	eq(kinds, C.KINDS_MAX + 1, "the bounded kinds and other")
	assert(C.PieceStats().kinds.other.a >= 10, "the rest counted as other")
	-- /oly bug's line: the kinds with the most pieces, and the reasons.
	local pieces
	for _, line in ipairs(ns.DebugLines()) do if line:find("^pieces: ") then pieces = line end end
	assert(pieces and pieces:find("why: ", 1, true) and pieces:find("stale=", 1, true), tostring(pieces))
	assert(#pieces <= ns.DEBUG_LINE, "one bounded line")
	C.ResetPieceStats()
end)

test("1.5.5 /oly bug debug: the relay, the reporter, the census's sources per realm group, the signed lists and the secret values left unread; bounded, and no other player's name or BattleTag", function()
	local R, Cm = ns.Relay, ns.Comm
	local saved = { guilds = ns.rdb.guilds, census = ns.db.groupCensus, heard = ns.db.groupHeard, commStats = Cm.Stats,
		check = rawget(_G, "issecretvalue"), relay = R, group = ns.group }
	local ok, err = pcall(function()
		local now = ns.Now()
		ns.group = "ForeverPvE"
		ns.rdb.guilds = {
			["Olympus Far"] = { guild = "Olympus Far", leader = "Faraway Leaderperson", t = now - 90, from = "CAMWOWUS2Realm3PvE", by = "Reporting Personname" },
			["Olympus Near"] = { guild = "Olympus Near", leader = "Nearby Leaderperson", t = now - 7200 },
		}
		-- (1.5.8: each with its source and guilds, as the store keeps them, for the source and counted fields.)
		ns.db.groupCensus = { ["Alliance|ForeverPvP"] = { group = "ForeverPvP", faction = "Alliance", people = 2000, characters = 2400,
			guilds = 12, observed = now - 3 * 3600, src = "author", by = "Carrying Personname" } }
		ns.db.groupHeard = { ["Alliance|ForeverRP"] = { group = "ForeverRP", faction = "Alliance", people = 300, characters = 300, guilds = 2,
			observed = now - 600, src = "heard", by = "Witness Personname" } }
		ns.Relay = setmetatable({ Stats = function()
			return { on = true, relay = "Relaying Personname", sure = true, reporters = 3, pending = 1, out = 4, delivered = 5, dead = 2, dropped = 0, trickled = 7 }
		end, IsRelay = function() return false end, Rules = function() return { rev = 2 } end }, { __index = R })
		Cm.Stats = function() return { isReporter = false, reporter = "Elected Personname", peers = 7, reports = 12, bad = 1, partial = 3 } end
		issecretvalue = function(v) return v == "SECRET" end
		ns.ResetSecretSkips()
		ns.Secret("relay not found", "SECRET")
		local lines = ns.DebugLines()
		local text = table.concat(lines, "\n")
		eq(lines[1], "debug (1.5.5):")
		local size = 0
		for _, line in ipairs(lines) do
			assert(#line <= ns.DEBUG_LINE, "a bounded line: " .. line)
			size = size + #line + 1
		end
		assert(size <= ns.DEBUG_MAX + #"(debug cut)" + 1, "bounded in all: " .. size)
		assert(text:find("relay: picked, answered, relay here: no, reporters 3, pending 1, out 4 delivered 5 dead 2 dropped 0 trickled 7", 1, true), text)
		assert(text:find("reporter: this client no, guild's known yes, guild peers 7, reports heard 12, bad 1, incomplete 3", 1, true), text)
		assert(text:find("census: group ForeverPvE: 2 guild reports, newest 90s, oldest 2h", 1, true), text)
		assert(text:find("by realm CAMWOWUS2Realm3PvE=1 old=1", 1, true), text)
		-- (1.5.8) Each with its source and whether the all-server total counts it.
		assert(text:find("census: other groups Alliance|ForeverRP heard 10m (300) heard uncounted, Alliance|ForeverPvP look 3h (2000) author counted", 1, true), text)
		assert(text:find("signed: titles ", 1, true) and text:find("relay rules rev 2", 1, true), text)
		assert(text:find("secret values left unread: relay not found=1", 1, true), text)
		-- No other player's name or data: neither the relay's, the reporter's, a leader's nor a witness's.
		for _, name in ipairs({ "Personname", "Leaderperson", "Olympus Far", "Olympus Near" }) do
			assert(not text:find(name, 1, true), "no other player's data: " .. name)
		end
		assert(not text:find("%a#%d%d%d%d"), "no BattleTag")
	end)
	ns.rdb.guilds, ns.db.groupCensus, ns.db.groupHeard, Cm.Stats, issecretvalue, ns.Relay, ns.group =
		saved.guilds, saved.census, saved.heard, saved.commStats, saved.check, saved.relay, saved.group
	ns.ResetSecretSkips()
	if not ok then error(err, 0) end
end)

test("/oly bug debug: fallback relay shows bounded aggregate counters without peer identities", function()
	local saved = ns.RelayFallback
	local ok, err = pcall(function()
		local stats = {
			source = "list", candidates = 4, pinged = 5, yes = 2, no = 1, none = 2, serving = true,
			elected = { "ElectedPeerOne-Realm", "ElectedPeerTwo-Realm" }, held = 7, holdDropped = 3,
			listFrom = "FallbackListKeeper-Realm", picks = { { to = "FallbackPicker-Realm" } },
			line = "PrivateFallbackDebugLine-Realm",
		}
		ns.RelayFallback = { Stats = function() return stats end }
		local report = ns.BuildBugReport()
		local line = assert(report:match("\nfallback: ([^\n]+)"), "the copyable report includes fallback counters")
		eq(line, "source list, candidates 4, asked 5, yes 2, no 1, no answer 2, elected 2, serving yes, held 7, dropped 3")
		assert(#("fallback: " .. line) <= ns.DEBUG_LINE, "within the debug line limit")
		for _, private in ipairs({ "ElectedPeerOne", "ElectedPeerTwo", "FallbackListKeeper", "FallbackPicker", "PrivateFallbackDebugLine" }) do
			assert(not report:find(private, 1, true), "peer data is not copied: " .. private)
		end

		stats.source = "UnknownPeerName-Realm"
		stats.serving = false
		report = ns.BuildBugReport()
		assert(report:find("\nfallback: source unknown,", 1, true), "candidate source is restricted to known labels")
		assert(report:find("elected 2, serving no,", 1, true), "the fallback can be idle")
		assert(not report:find(stats.source, 1, true), "an unrecognized source stays private")

		ns.RelayFallback = nil
		assert(ns.BuildBugReport():find("\nfallback: not loaded\n", 1, true), "a missing module still produces a report")
		ns.RelayFallback = { Stats = function() error("PrivateFallbackError-Realm") end }
		report = ns.BuildBugReport()
		assert(report:find("\nfallback: unavailable\n", 1, true), "a failed stats read still produces a report")
		assert(not report:find("PrivateFallbackError", 1, true), "errors from the module stay private")
	end)
	ns.RelayFallback = saved
	if not ok then error(err, 0) end
end)

test("1.5.5 /oly bug debug: the whole section is cut at DEBUG_MAX, said so, and /oly bug still builds when a part fails", function()
	local savedMax, savedLine = ns.DEBUG_MAX, ns.InstallLine
	local ok, err = pcall(function()
		ns.DEBUG_MAX = 120
		local lines = ns.DebugLines()
		eq(lines[#lines], "(debug cut)")
		local size = 0
		for i = 1, #lines - 1 do size = size + #lines[i] + 1 end
		assert(size <= 120, "within the bound: " .. size)
		ns.DEBUG_MAX = savedMax
		ns.InstallLine = function() error("broken") end
		local report = ns.BuildBugReport()
		assert(report:find("\ndebug (1.5.5):\ninstall: ?\n", 1, true), "a part that fails says so, the rest stays")
	end)
	ns.DEBUG_MAX, ns.InstallLine = savedMax, savedLine
	if not ok then error(err, 0) end
end)

test("/oly recent: bounded local diagnostics, filter selection and sealed channel scrubbing", function()
	local savedLog, savedErrors, savedSpec = ns.db.log, ns.db.errors, ns.Comm.ChannelSpec
	local ok, err = pcall(function()
		ns.db.log, ns.db.errors = {}, {}
		eq(ns.RecentDiagnostics("errors"), ns.L.RECENT_EMPTY)
		for i = 1, 41 do ns.db.log[i] = ("unrelated line %02d"):format(i) end
		ns.db.log[42] = "relay joined channel Oly1234abcd"
		ns.Comm.ChannelSpec = function() return "Oly1234abcd", "test key" end
		local all = ns.RecentDiagnostics("")
		assert(all:find("unrelated line 03", 1, true))
		assert(not all:find("unrelated line 02", 1, true))
		eq(ns.RecentDiagnostics("census"), "relay joined channel (sealed channel)")
		ns.db.errors[1] = { count = 2, where = "test", first = "10:00", last = "10:01", version = "1.5.7", msg = "channel Oly1234abcd" }
		eq(ns.RecentDiagnostics("errors"), "[2x] test (10:00 .. 10:01, v1.5.7): channel (sealed channel)")
	end)
	ns.db.log, ns.db.errors, ns.Comm.ChannelSpec = savedLog, savedErrors, savedSpec
	if not ok then error(err, 0) end
end)

-- 1.5.8 (Daniel, 11-12: why other guilds see fewer servers). Fails before: /oly bug showed none of the
-- census's counters, the relay tree's registrant line or the relayed rows (Relay.BugLines has no caller),
-- and "other groups" said neither a row's source nor whether it counts.
test("1.5.8 /oly bug debug: the census counters, the tree's registrant line and the relayed rows come last, after a whole signed line; their counters move with what the census takes; bounded and nameless", function()
	local saved = { census = ns.db.groupCensus, heard = ns.db.groupHeard, global = ns.rdb.censusGlobal, group = ns.group, tree = ns.RelayTree }
	local ok, err = pcall(function()
		local now = ns.Now()
		ns.group = "ForeverPvE"
		-- Our own group's saved look: "here" (its live count stands in the total), never "counted" twice.
		ns.db.groupCensus = { ["Alliance|ForeverPvE"] = { group = "ForeverPvE", faction = "Alliance", people = 900, characters = 1000,
			guilds = 8, observed = now - 300, src = "own", by = "Own Personname" } }
		ns.db.groupHeard = {}
		ns.rdb.censusGlobal = {
			["olympus relayed"] = { name = "Olympus Relayed", total = 300, online = 20, avg10 = 300, observed = now - 120, by = "Relaying Personname", heard = now },
			["olympus stale"] = { name = "Olympus Stale", total = 200, online = 0, avg10 = 300, observed = now - 2 * 86400, by = "Relaying Personname", heard = now },
		}
		local function Section() return table.concat(ns.DebugLines(), "\n") end
		local function Refused(text) return tonumber(text:match("census counters: [^\n]-| cx a%d+ t%d+ w%d+ h%d+ u%d+ r(%d+)")) end
		local text = Section()
		local counters = text:match("\n(census counters: [^\n]+)")
		assert(counters, "the census counters: " .. text)
		eq(counters, "census counters: " .. ns.Data.CensusStats().line, "Data.CensusStats().line, whole")
		assert(text:find("census: other groups Alliance|ForeverPvE look 5m (900) own here", 1, true), text)
		local before = assert(Refused(text), counters)
		-- A malformed CX word from a member: refused, and the line says one more.
		eq(ns.Data.ReceiveGroupCensus("CHANNEL", "Plain Personname-Realm", "CX~1~S~x~broken"), false)
		eq(Refused(Section()), before + 1, "the counter moved by the refusal")
		eq(text:find("\ntree: not loaded", 1, true) ~= nil, true, "no tree here: said so")
		-- The tree's first line alone: the later ones name the registrants a piece came from.
		ns.RelayTree = { Stats = function()
			return { lines = { "tree: rn 3, complete 2, rounds 1 (deferred 0), capable 4, open 0, registrant true", "tree 7 1/2 missing [2] from Seeding Personname: open, 4s" } }
		end }
		text = Section()
		assert(text:find("\ntree: rn 3, complete 2, rounds 1 (deferred 0), capable 4, open 0, registrant true\n", 1, true), "the tree's first line, with registrant: " .. text)
		assert(text:find("\ncensus relayed: rows 1 within a day, newest 2m", 1, true), "the relayed rows a client could count: " .. text)
		-- After the signed line, which stays whole, and the whole section within DEBUG_MAX.
		local lines = ns.DebugLines()
		local signedAt, countersAt, size = nil, nil, 0
		for i, line in ipairs(lines) do
			if line:find("^signed: ") then signedAt = i end
			if line:find("^census counters: ") then countersAt = i end
			assert(#line <= ns.DEBUG_LINE, "a bounded line: " .. line)
			size = size + #line + 1
		end
		assert(signedAt and countersAt and signedAt < countersAt, "the new lines come after the signed line")
		assert(lines[signedAt]:find("relay rules rev ", 1, true) and not lines[signedAt]:find("%.%.%.$"), "the signed line whole: " .. lines[signedAt])
		assert(size <= ns.DEBUG_MAX, "bounded in all: " .. size)
		eq(lines[#lines]:find("(debug cut)", 1, true), nil, "nothing cut")
		for _, name in ipairs({ "Personname", "Olympus Relayed", "Olympus Stale" }) do
			assert(not text:find(name, 1, true), "no player's, relay's or guild's name: " .. name)
		end
	end)
	ns.db.groupCensus, ns.db.groupHeard, ns.rdb.censusGlobal, ns.group, ns.RelayTree = saved.census, saved.heard, saved.global, saved.group, saved.tree
	if not ok then error(err, 0) end
end)

-- 1.5.9 (two /oly bug reports of 2026-11-12: a member's census came by no relay, and the report said
-- "registrant false" without naming who registers the guild, nor the version it runs). /oly status names
-- the guild's registrant beside its reporter now, each with the version its hello named. Real Comm: a
-- guildmate on 1.5.4 (no N in its hello) comes first by name and reports, one on 1.5.8 (N) registers.
-- Fails before (no registrant in the line, no version).
test("1.5.9 /oly bug: the guild's registrant beside its reporter, each with the version its hello named: a 1.5.4 guildmate without the tree's N reports, a 1.5.8 one with it registers", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, info = C_ChatInfo, stats = ns.Comm.Stats }
	local ok, err = pcall(function()
		GetChannelName = function() return 5 end
		ns.IsMember = function() return true end
		local cns, Deliver = assert(extra.FreshComm, "tests/run.lua hands FreshComm to this file")()
		cns.RelayTree = { Announce = function() return false end } -- (this client takes the tree too: N)
		local C = cns.Comm
		C.loginAt = cns.clock - 1000
		C.JoinChannel()
		local old, new = "Aaa Oldhello-Realm", "Bbb Newhello-Realm"
		assert(old < cns.me and new < cns.me, "both come before this client by name")
		Deliver("GUILD", old, "H1~1.5.4~Realm~p~~~~R")
		Deliver("GUILD", new, "H1~1.5.8~Realm~p~~~~R~N")
		C.MaybeBroadcast({ guild = "Olympus II", total = 1000, online = 300, zones = {} })
		local st = C.Stats()
		eq(st.isReporter, false); eq(st.isRegistrant, false)
		eq(st.reporter, ns.DisplayName(old)); eq(st.reporterVersion, "1.5.4")
		eq(st.registrant, ns.DisplayName(new)); eq(st.registrantVersion, "1.5.8")
		ns.Comm.Stats = C.Stats
		local report = ns.BuildBugReport()
		local line = assert(report:match("\n(channel [^\n]+)"), report)
		assert(line:find(("reporter=%s v1.5.4 (me: false)"):format(ns.DisplayName(old)), 1, true), line)
		assert(line:find(("registrant=%s v1.5.8 (me: false)"):format(ns.DisplayName(new)), 1, true), line)
		-- This client registers when it comes first among those with N: its own version then.
		ns.Comm.Stats = saved.stats
		local cns2, Deliver2 = extra.FreshComm()
		cns2.RelayTree = { Announce = function() return false end }
		local C2 = cns2.Comm
		C2.loginAt = cns2.clock - 1000
		C2.JoinChannel()
		Deliver2("GUILD", old, "H1~1.5.4~Realm~p~~~~R")
		C2.MaybeBroadcast({ guild = "Olympus II", total = 1000, online = 300, zones = {} })
		eq(C2.Stats().isRegistrant, true); eq(C2.Stats().registrantVersion, ns.VERSION)
		eq(C2.Stats().reporterVersion, "1.5.4")
	end)
	GetChannelName, ns.IsMember, C_ChatInfo, ns.Comm.Stats = saved.channel, saved.member, saved.info, saved.stats
	if not ok then error(err, 0) end
end)

-- 1.5.9's review (D3): the registrant's fields and isRegistrant were reset in different places. Turned
-- quiet (Private presence) after it was elected, a client still named itself registrant with "(me:
-- false)"; moved to another guild, it said "registrant=nil (me: true)". Both reset together now. Fails
-- before (the elected name kept under quiet presence; isRegistrant kept true after the move).
test("1.5.9's review /oly bug: the registrant line under quiet presence names no registrant, and after a guild change nobody is registrant", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, info = C_ChatInfo, guild = GetGuildInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 5 end
		ns.IsMember = function() return true end
		local report = { guild = "Olympus II", total = 1000, online = 300, zones = {} }
		for _, case in ipairs({ "quiet", "moved" }) do
			local cns, Deliver = extra.FreshComm()
			cns.RelayTree = { Announce = function() return false end } -- (this client takes the tree: N)
			local C = cns.Comm
			C.loginAt = cns.clock - 1000
			C.JoinChannel()
			Deliver("GUILD", "Zzz Later-Realm", "H1~1.5.4~Realm~p~~~~R")
			C.MaybeBroadcast(report)
			eq(C.Stats().isRegistrant, true, case .. ": elected registrant")
			eq(C.Stats().registrant, ns.DisplayName(cns.me), case)
			if case == "quiet" then
				cns.QuietPresence = function() return true end
				cns.clock = cns.clock + 60
				C.MaybeBroadcast(report)
				eq(C.Stats().isRegistrant, false, "quiet: not the registrant")
				eq(C.Stats().registrant, nil, "quiet: nor named as one")
				eq(C.Stats().registrantVersion, nil); eq(C.Stats().reporterVersion, nil)
			else
				GetGuildInfo = function() return "Another Guild", "Member", 5, nil end
				C.Hello(true) -- (the guild change seen first: SyncGuild)
				eq(C.Stats().isRegistrant, nil, "moved: nobody is registrant until the next election")
				eq(C.Stats().registrant, nil)
				GetGuildInfo = saved.guild
			end
		end
	end)
	GetChannelName, ns.IsMember, C_ChatInfo, GetGuildInfo = saved.channel, saved.member, saved.info, saved.guild
	if not ok then error(err, 0) end
end)

-- 1.5.9: on a relay's own client, /oly bug says what decides whether its registrants get the census,
-- naming nobody: quiet presence (no snapshot of its own then), the drip's transfers waiting and the
-- longest any of them, and any census one, waited, and how long ago its own last tree round was. Not on
-- any other client. Fails before (no such line).
-- (1.5.9's review) And the transfer in flight, which holds every other one while its batch waits (D2:
-- shown as nothing before); in the status right below the channel line, not the debug section, which a
-- report sent in game (Workshop.Outgoing, cut at Workshop.BUG_MAX) loses on a relay (P8). The old place
-- is asserted gone: the line in the debug section was the one the cut took.
-- (Round 1's re-review) And the drip's whispers since login, census, other and past its pace (Relay.Stats),
-- and on the channel line the words taken on Olympus's leftover channels (Comm.Stats().leftover): counted
-- by 1.5.9's review, shown nowhere. Fails before (neither is in the status). (Round 2) Those past the pace
-- are some of the census and other ones, so the line says so: as three counts side by side ("1234 census,
-- 56 other, 78 past the pace") they read as 1,368 whispers where 1,290 went.
test("1.5.9 /oly bug: on a relay, the status says, below the channel line, quiet presence, the drip's waiting transfers and the longest wait, the transfer in flight, the drip's whispers sent (census, other, past its pace), and its own last tree round's age, without a name; the channel line the words taken on leftover channels; on any other client no relay line; a long report sent in game keeps both", function()
	local saved = { relay = ns.Relay, tree = ns.RelayTree, quiet = ns.QuietPresence, log = ns.db.log, commStats = ns.Comm.Stats }
	local ok, err = pcall(function()
		local R = saved.relay
		local relay = true
		ns.Relay = setmetatable({ IsRelay = function() return relay end, DripStats = function()
			return { waiting = 3, census = 2, oldest = 95, oldestCensus = 40, name = "Waiting Personname",
				flight = { census = false, batch = 2, of = 2, since = 300, name = "Flying Personname" } }
		end, Stats = function()
			return { on = true, dripCensus = 1234, dripOther = 56, dripFree = 78 }
		end }, { __index = R })
		ns.Comm.Stats = function()
			local c = saved.commStats()
			c.leftover = 12
			return c
		end
		ns.QuietPresence = function() return true end
		ns.RelayTree = { Stats = function()
			return { round = { age = 300, tid = "abcd1234" }, lines = { "tree: rn 0, complete 0, rounds 1 (deferred 0), capable 31, open 0, registrant false" },
				seed = "Seeding Personname" }
		end }
		local text = ns.StatusText()
		local line = "relay here: quiet presence on  |  drip 3 waiting (2 census), the oldest for 95s, the oldest census one for 40s, "
			.. "in flight: other, batch 2/2, for 5m  |  drip sent 1234 census + 56 other (78 of them past the pace)  |  own tree round 5m ago"
		assert(text:find("\n" .. line .. "\n", 1, true), text)
		assert(text:find("\nchannel [^\n]+\nrelay here: "), "right below the channel line: " .. text)
		local channel = text:match("\n(channel [^\n]+)\n")
		assert(channel and channel:find("  leftover taken=12  |  peers in guild=", 1, true), "the channel line: " .. tostring(channel))
		assert(not text:find("Personname", 1, true), "no name: " .. text)
		-- (The debug section's relay line says "relay here: yes" of itself now that Relay.Stats answers: the
		-- status's line, which starts "relay here: quiet presence", is the one that must not be there.)
		assert(not table.concat(ns.DebugLines(), "\n"):find("relay here: quiet presence", 1, true), "no longer in the debug section")
		-- A long report, sent in game: the status comes first, and the line with it.
		local logged = {}
		for i = 1, 40 do logged[i] = ("relay: a long log line %02d "):format(i) .. ("x"):rep(150) end
		ns.db.log = logged
		local report = ns.BuildBugReport()
		assert(#report > ns.Workshop.BUG_MAX, "a report longer than the in-game cut: " .. #report)
		local sent = ns.Workshop.Outgoing(report)
		assert(sent:find((line:gsub("|", "!")), 1, true), "the line is in what is sent in game (its pipes as \"!\")")
		assert(sent:find((channel:gsub("|", "!")), 1, true), "and the channel line")
		assert(not sent:find("census counters:", 1, true), "where the debug section's census counters are cut off")
		ns.QuietPresence = function() return false end
		ns.RelayTree = { Stats = function() return { lines = {} } end }
		ns.Relay.DripStats = function() return { waiting = 0, census = 0 } end
		text = ns.StatusText()
		assert(text:find("\nrelay here: quiet presence off  |  drip 0 waiting (0 census), the oldest for -, the oldest census one for -, in flight: none  |  drip sent 1234 census + 56 other (78 of them past the pace)  |  own tree round none\n", 1, true), text)
		relay = false
		text = ns.StatusText()
		assert(not text:find("relay here:", 1, true), "not a relay: no line: " .. text)
	end)
	ns.Relay, ns.RelayTree, ns.QuietPresence, ns.db.log, ns.Comm.Stats = saved.relay, saved.tree, saved.quiet, saved.log, saved.commStats
	if not ok then error(err, 0) end
end)
