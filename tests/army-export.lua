local ns, test, eq, ADDON_DIR, WithUI = ...
local Army = assert(ns.ArmyExport)

-- Exercise the shipped Start function without adding a mutable production escape hatch to its
-- closed release gate. The test restores the exact local immediately, including on failure.
local function WithActivation(fn)
	local index, previous
	for i = 1, 32 do
		local name, value = debug.getupvalue(Army.Start, i)
		if not name then break end
		if name == "ACTIVATION_ENABLED" then index, previous = i, value break end
	end
	assert(index, "Army.Start release-gate upvalue")
	debug.setupvalue(Army.Start, index, true)
	local result = { pcall(fn) }
	debug.setupvalue(Army.Start, index, previous)
	if not result[1] then error(result[2], 0) end
	return unpack(result, 2)
end

local function Rows45()
	local classes = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
	local levels = { 5, 15, 25, 35, 45, 55, 60 }
	local rows = {}
	for i = 1, 45 do
		local band = i <= 35 and math.floor((i - 1) / 5) + 1 or 7
		rows[i] = { name = "Never serialized " .. i, guid = "Player-1-" .. i,
			classFile = classes[(i - 1) % 9 + 1], level = levels[band], rankIndex = (i - 1) % 9,
			online = i <= 10 }
	end
	return rows
end

test("Army QR: canonical aggregate JSON is byte-stable and contains no roster identity", function()
	local payload, a = Army.Payload({ guild = "Olympus II", faction = "Alliance", realmGroup = "ClassicBetaPvP", observedAt = 1800000000 }, Rows45())
	local want = '{"format":"olympus-stat-observation-v2","scope":"own-guild","source":"volunteer-client","sourceVerified":false,"membershipProof":false,"addonVersion":"0.2.0","realmGroup":"ClassicBetaPvP","faction":"Alliance","observedAt":1800000000,"guilds":[{"name":"Olympus II","receivedAt":1800000000,"reportedCharacters":45,"online":10,"classes":[5,5,5,5,5,5,5,5,5],"levels":[5,5,5,5,5,5,15],"ranks":[5,5,5,5,5,5,5,5,5,0]}]}'
	eq(payload, want)
	eq(a.reportedCharacters, 45); eq(a.online, 10)
	assert(not payload:find("Never serialized", 1, true) and not payload:find("Player-1-", 1, true), "no name or GUID in the payload")
end)

test("Army QR: privacy masking withholds small totals, online remainders and unsafe marginal distributions", function()
	local a = assert(Army.Aggregate({
		{ classFile = "WARRIOR", level = 1, rankIndex = 0, online = true },
		{ classFile = "WARRIOR", level = 2, rankIndex = 0, online = false },
		{ classFile = "WARRIOR", level = 3, rankIndex = 0, online = false },
	}))
	eq(a.reportedCharacters, "few"); eq(a.online, nil); eq(a.classes, nil); eq(a.levels, nil); eq(a.ranks, nil)
	local rows = {}
	for i = 1, 10 do rows[i] = { classFile = "WARRIOR", level = 60, rankIndex = 0, online = i <= 2 } end
	a = assert(Army.Aggregate(rows)); eq(a.reportedCharacters, 10); eq(a.online, "few")
	rows = {}
	for i = 1, 6 do rows[i] = { classFile = "WARRIOR", level = 60, rankIndex = 0, online = i <= 2 } end
	a = assert(Army.Aggregate(rows)); eq(a.online, "few", "the masked online value does not reveal the exact remainder")
	rows = {}
	for i = 1, 10 do rows[i] = { classFile = "WARRIOR", level = 60, rankIndex = 0, online = i <= 7 } end
	a = assert(Army.Aggregate(rows)); eq(a.online, nil, "three offline must not be derivable")
	for i = 1, 10 do rows[i].online = false end
	rows[1].classFile = "MAGE"
	a = assert(Army.Aggregate(rows)); eq(a.classes, nil, "one Mage withholds the whole class marginal")
end)

test("Army QR: a post-60 client keeps totals but withholds the incompatible level marginal", function()
	local rows = {}
	for i = 1, 5 do rows[i] = { classFile = "WARRIOR", level = 70, rankIndex = 0, online = false } end
	local payload, a = Army.Payload({ guild = "Olympus", faction = "Alliance", realmGroup = "Anniversary", observedAt = 1800000001 }, rows)
	assert(payload); eq(a.reportedCharacters, 5); eq(a.levels, nil)
	assert(payload:find('"levels":null', 1, true), "the level marginal is explicitly unavailable")
	assert(payload:find('"classes":[5,0,0,0,0,0,0,0,0]', 1, true), "a safe independent marginal remains")
end)

test("Army QR: scope is fail-closed to exact official Alliance guilds and a known realm group", function()
	eq(Army.OfficialGuild("Olympus"), true); eq(Army.OfficialGuild("OLYMPUS X"), true)
	eq(Army.OfficialGuild("Holypmus"), false); eq(Army.OfficialGuild("Olympus XI"), false); eq(Army.OfficialGuild("Anti Olympus"), false)
	local p, why = Army.Payload({ guild = "Holypmus", faction = "Alliance", realmGroup = "Realm", observedAt = 1 }, {})
	eq(p, nil); eq(why, "scope")
	p, why = Army.Payload({ guild = "Olympus", faction = "Horde", realmGroup = "Realm", observedAt = 1 }, {})
	eq(p, nil); eq(why, "scope")
	p, why = Army.Payload({ guild = "Olympus", faction = "Alliance", realmGroup = "", observedAt = 1 }, {})
	eq(p, nil); eq(why, "scope")
	p, why = Army.Payload({ guild = "Olympus", faction = "Alliance", realmGroup = "Realm", observedAt = 1 }, {})
	eq(p, nil); eq(why, "roster-count")
	local tooMany = {}
	for i = 1, 1001 do tooMany[i] = {} end
	p, why = Army.Payload({ guild = "Olympus", faction = "Alliance", realmGroup = "Realm", observedAt = 1 }, tooMany)
	eq(p, nil); eq(why, "roster-count")
	local five = {}
	for i = 1, 5 do five[i] = { classFile = "WARRIOR", level = 60, rankIndex = 0, online = false } end
	p = assert(Army.Payload({ guild = "OLYMPUS X", faction = "Alliance", realmGroup = "Realm", observedAt = 4102444800 }, five))
	assert(p:find('"name":"Olympus X"', 1, true), "accepted guild casing is canonical on the wire")
	p, why = Army.Payload({ guild = "Olympus", faction = "Alliance", realmGroup = "Realm|Other", observedAt = 1 }, five)
	eq(p, nil); eq(why, "scope")
	p, why = Army.Payload({ guild = "Olympus", faction = "Alliance", realmGroup = "Realm\nOther", observedAt = 1 }, five)
	eq(p, nil); eq(why, "scope")
	p, why = Army.Payload({ guild = "Olympus", faction = "Alliance", realmGroup = string.rep("r", 97), observedAt = 1 }, five)
	eq(p, nil); eq(why, "scope")
	p, why = Army.Payload({ guild = "Olympus", faction = "Alliance", realmGroup = " Realm", observedAt = 1 }, five)
	eq(p, nil); eq(why, "scope")
	p, why = Army.Payload({ guild = "Olympus", faction = "Alliance", realmGroup = "Realm ", observedAt = 1 }, five)
	eq(p, nil); eq(why, "scope")
	p, why = Army.Payload({ guild = "Olympus", faction = "Alliance", realmGroup = "Realm", observedAt = 4102444801 }, five)
	eq(p, nil); eq(why, "time")
end)

test("Army QR: OLCS2 frames bind nonce, SHA-256, part order and the 1023-byte ceiling", function()
	local payload = assert(Army.Payload({ guild = "Olympus II", faction = "Alliance", realmGroup = "ClassicBetaPvP", observedAt = 1800000000 }, Rows45()))
	local frames, digest = Army.Frames(payload, "0123456789ABCDEF0123456789ABCDEF")
	eq(digest, "ehTLrUPUrlP6dnx5gd0UyHjEsXY1vTz8JdWkVLtxeJw")
	assert(#frames >= 1 and #frames <= 14)
	local chunks = {}
	for i, value in ipairs(frames) do
		local nonce, hash, part, total, chunk = value:match("^OLCS2|([^|]+)|([^|]+)|(%d%d%d)|(%d%d%d)|([^|]*)$")
		eq(nonce, "0123456789abcdef0123456789abcdef"); eq(hash, digest)
		eq(tonumber(part), i); eq(tonumber(total), #frames); assert(#chunk <= 100); assert(#value <= 191)
		chunks[i] = chunk
	end
	eq(table.concat(chunks), ns.Ed25519.ToB64(payload))
	local max = assert(Army.Frames(string.rep("x", 1023), "0123456789abcdef0123456789abcdef"))
	eq(#max, 14); eq(#max[1], 191)
	local refused, why = Army.Frames(string.rep("x", 1024), "0123456789abcdef0123456789abcdef")
	eq(refused, nil); eq(why, "payload")
	refused, why = Army.Frames("ok", "not-a-browser-nonce")
	eq(refused, nil); eq(why, "nonce")
	refused, why = Army.Frames("", "0123456789abcdef0123456789abcdef")
	eq(refused, nil); eq(why, "payload")
end)

test("Army QR: existing BSD encoder makes bounded level-L matrices from the protocol frames", function()
	local frames = assert(Army.Frames(string.rep("x", 1023), "0123456789abcdef0123456789abcdef"))
	local matrix = assert(Army.Matrix(frames[1]))
	eq(#matrix, 49, "a maximum 191-byte frame is QR version 8")
	for x = 1, #matrix do eq(#matrix[x], #matrix) end
end)

test("Army QR: native scan requires a stable complete roster and one online matching player GUID", function()
	local saved = { IsInGuild, GetGuildInfo, UnitFactionGroup, UnitGUID, GetNumGuildMembers, GetGuildRosterInfo,
		GetGuildRosterShowOffline, ns.faction, ns.group }
	local ok, err = pcall(function()
		ns.faction, ns.group = "Alliance", "Realm"
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus III" end
		UnitFactionGroup = function() return "Alliance" end
		UnitGUID = function() return "Player-1-ME" end
		local mode, countCalls, showCalls = nil, 0, 0
		GetNumGuildMembers = function()
			countCalls = countCalls + 1
			if mode == "size-changed" and countCalls > 1 then return 4, 1 end
			if mode == "online-changed" and countCalls > 1 then return 5, 2 end
			if mode == "online-mismatch" then return 5, 2 end
			if mode == "online-missing" then return 5, nil end
			return 5, 1
		end
		GetGuildRosterShowOffline = function()
			showCalls = showCalls + 1
			return not (mode == "show-changed" and showCalls > 1)
		end
		GetGuildRosterInfo = function(i)
			if mode == "incomplete" and i == 5 then return nil end
			local name = "Member" .. i
			local guid = i == 3 and "Player-1-ME" or ("Player-1-" .. i)
			local online = i == 3
			if mode == "duplicate" and i == 5 then guid = "Player-1-4" end
			if mode == "duplicate-name" and i == 5 then name = "Member4" end
			if mode == "missing-online" and i == 5 then online = nil end
			if mode == "self-offline" then online = i == 1 end
			return name, "Rank", i - 1, i == 5 and 70 or 60, "Warrior", "", "", "", online,
				0, "WARRIOR", 0, 0, false, false, 0, guid
		end
		local scope = assert(Army.Scope())
		scope.playerGUID = UnitGUID("player")
		local rows = assert(Army.ReadRoster(scope)); eq(#rows, 5); eq(rows[5].level, 70)
		local function Refused(which, want)
			mode, countCalls, showCalls = which, 0, 0
			local none, why = Army.ReadRoster(scope)
			eq(none, nil, which); eq(why, want, which)
		end
		Refused("incomplete", "roster-incomplete")
		Refused("duplicate", "roster-duplicate")
		Refused("duplicate-name", "roster-duplicate")
		Refused("missing-online", "roster-incomplete")
		Refused("self-offline", "own-guid-offline")
		Refused("online-missing", "native-online")
		Refused("online-mismatch", "online-mismatch")
		Refused("size-changed", "roster-changed")
		Refused("online-changed", "online-changed")
		Refused("show-changed", "show-offline")
		mode, countCalls, showCalls = nil, 0, 0
		GetGuildRosterShowOffline = function() return false end
		local none, why = Army.ReadRoster(scope); eq(none, nil); eq(why, "show-offline")
		GetGuildRosterShowOffline = nil
		none, why = Army.ReadRoster(scope); eq(none, nil); eq(why, "show-offline")
	end)
	IsInGuild, GetGuildInfo, UnitFactionGroup, UnitGUID, GetNumGuildMembers, GetGuildRosterInfo,
		GetGuildRosterShowOffline = unpack(saved, 1, 7)
	ns.faction, ns.group = saved[8], saved[9]
	if not ok then error(err, 0) end
end)

test("Army QR: Start binds the native GUID and a roster event completes real frames", function()
	local saved = { IsInGuild, GetGuildInfo, UnitFactionGroup, UnitGUID, GetNumGuildMembers, GetGuildRosterInfo,
		GetGuildRosterShowOffline, SetGuildRosterShowOffline, GetServerTime, GetTimePreciseSec,
		InCombatLockdown, C_GuildInfo, GuildRoster, ns.faction, ns.group, ns.After, Army.ShowFrames }
	local shown, rosterCalls, captured = false, 0, nil
	local ok, err = pcall(function()
		Army.Cancel()
		ns.faction, ns.group = "Alliance", "Realm"
		IsInGuild = function() return true end
		GetGuildInfo = function() return "OLYMPUS III" end
		UnitFactionGroup = function() return "Alliance" end
		UnitGUID = function() return "Player-1-ME" end
		GetGuildRosterShowOffline = function() return shown end
		SetGuildRosterShowOffline = function(value) shown = value == true end
		GetNumGuildMembers = function() return 5, 1 end
		GetGuildRosterInfo = function(i)
			return "Member" .. i, "Rank", i - 1, 60, "Warrior", "", "", "", i == 3,
				0, "WARRIOR", 0, 0, false, false, 0, i == 3 and "Player-1-ME" or ("Player-1-" .. i)
		end
		GetServerTime = function() return 1800000000 end
		GetTimePreciseSec = function() return 42 end
		InCombatLockdown = function() return false end
		C_GuildInfo = { GuildRoster = function() rosterCalls = rosterCalls + 1 end }
		GuildRoster = nil
		ns.After = function() end
		Army.ShowFrames = function(frames) captured = frames return true end
		local started, why = WithActivation(function()
			return Army.Start("0123456789abcdef0123456789abcdef")
		end)
		eq(started, true, "Start: " .. tostring(why)); eq(why, nil); eq(shown, true, "show offline enabled"); eq(rosterCalls, 1)
		for _, dispatch in ipairs(EVENT_SCRIPTS) do dispatch(nil, "GUILD_ROSTER_UPDATE") end
		assert(type(captured) == "table" and #captured > 0, "the real completion path emitted OLCS2 frames")
		assert(captured[1]:find("^OLCS2|0123456789abcdef0123456789abcdef|"), captured[1])
		eq(shown, false, "the player's show-offline choice is restored")
		eq(rosterCalls, 2, "restoring show-offline refreshes the native roster")
		captured = nil
		started, why = WithActivation(function()
			return Army.Start("11111111111111111111111111111111")
		end)
		eq(started, true); eq(shown, true)
		for _, dispatch in ipairs(EVENT_SCRIPTS) do dispatch(nil, "PLAYER_GUILD_UPDATE", "target") end
		local again, pendingWhy = WithActivation(function()
			return Army.Start("22222222222222222222222222222222")
		end)
		eq(again, false); eq(pendingWhy, "pending", "another unit's guild update must not cancel our scan")
		for _, dispatch in ipairs(EVENT_SCRIPTS) do dispatch(nil, "PLAYER_GUILD_UPDATE", "player") end
		eq(shown, false, "our own guild update cancels and restores the roster filter")
		again, pendingWhy = WithActivation(function()
			return Army.Start("22222222222222222222222222222222")
		end)
		eq(again, true, "a player guild update cleared the pending scan"); eq(pendingWhy, nil)
		Army.Cancel()
	end)
	Army.Cancel()
	IsInGuild, GetGuildInfo, UnitFactionGroup, UnitGUID, GetNumGuildMembers, GetGuildRosterInfo =
		saved[1], saved[2], saved[3], saved[4], saved[5], saved[6]
	GetGuildRosterShowOffline, SetGuildRosterShowOffline, GetServerTime, GetTimePreciseSec =
		saved[7], saved[8], saved[9], saved[10]
	InCombatLockdown, C_GuildInfo, GuildRoster = saved[11], saved[12], saved[13]
	ns.faction, ns.group, ns.After, Army.ShowFrames = saved[14], saved[15], saved[16], saved[17]
	if not ok then error(err, 0) end
end)

test("Army QR: the release gate is closed for both canonical and pilot commands", function()
	eq(Army.Active(), false); eq(Army.Window(), nil)
	local oldPrint, oldRoster = ns.Print, GuildRoster
	local lines, calls = {}, 0
	local ok, err = pcall(function()
		ns.Print = function(text) lines[#lines + 1] = text end
		GuildRoster = function() calls = calls + 1 end
		SlashCmdList.OLYMPUS("army 0123456789abcdef0123456789abcdef")
		SlashCmdList.OLYMPUSARMY("0123456789abcdef0123456789abcdef")
		eq(calls, 0); eq(Army.Window(), nil)
		eq(#lines, 2)
		assert(lines[1]:find("not available", 1, true) and lines[2]:find("not available", 1, true))
	end)
	ns.Print, GuildRoster = oldPrint, oldRoster
	if not ok then error(err, 0) end
end)

test("Army QR: the lazy renderer rotates bounded rectangles and forgets frames when closed", function()
	assert(WithUI, "WithUI fixture")
	WithUI(function()
		local Ed, queued = ns.Ed25519, {}
		local oldAfter, oldTimer = Ed.after, C_Timer.NewTimer
		local timers = {}
		local ok, err = pcall(function()
			Ed.after = function(fn) queued[#queued + 1] = fn end
			C_Timer.NewTimer = function(_, fn)
				local timer = { fn = fn }
				function timer:Cancel() self.cancelled = true end
				timers[#timers + 1] = timer
				return timer
			end
			local frames = assert(Army.Frames(string.rep("x", 151), "0123456789abcdef0123456789abcdef"))
			eq(Army.ShowFrames(frames), true)
			while #queued > 0 do table.remove(queued, 1)() end
			local f = assert(Army.Window())
			eq(f:IsShown(), true); eq(f.frames, frames); eq(f:GetScript("OnUpdate"), nil)
			assert(#f.modules > 0 and #f.modules < 2401, "merged QR rectangles, not one texture per possible module")
			assert(f.canvas:GetWidth() > 0 and f.part:GetText() == "Frame 1 of 3")
			assert(timers[1] and not timers[1].cancelled, "one cancellable rotation timer")
			local started, why = WithActivation(function() return Army.Start("invalid") end)
			eq(started, false); eq(why, "nonce")
			eq(f:IsShown(), false, "a new refused attempt closes the stale QR")
			eq(f.frames, nil); eq(f.part:GetText(), ""); eq(timers[1].cancelled, true)
			for _, texture in ipairs(f.modules) do eq(texture:IsShown(), false) end
			eq(Army.ShowFrames(frames), true)
			for _, dispatch in ipairs(EVENT_SCRIPTS) do dispatch(nil, "PLAYER_GUILD_UPDATE", "target") end
			eq(f:IsShown(), true, "another unit's guild update leaves the attended QR visible")
			for _, dispatch in ipairs(EVENT_SCRIPTS) do dispatch(nil, "PLAYER_REGEN_DISABLED") end
			eq(f:IsShown(), false); eq(f.frames, nil, "combat clears the attended QR")
			eq(Army.ShowFrames(frames), true)
			for _, dispatch in ipairs(EVENT_SCRIPTS) do dispatch(nil, "PLAYER_LEAVING_WORLD") end
			eq(f:IsShown(), false); eq(f.frames, nil, "a supported leaving-world event clears the QR")
		end)
		Ed.after, C_Timer.NewTimer = oldAfter, oldTimer
		Ed.Reset()
		if not ok then error(err, 0) end
	end)
end)

test("Army QR: the shipped module has no storage, communication or upload path and loads after Link", function()
	local f = assert(io.open(ADDON_DIR .. "ArmyExport.lua", "rb")); local source = f:read("*a"); f:close()
	for _, forbidden in ipairs({ "SavedVariables", "OlympusDB", "SendAddonMessage", "SendChatMessage", "C_HTTP", "Upload" }) do
		assert(not source:find(forbidden, 1, true), "forbidden export path: " .. forbidden)
	end
	assert(not source:find('SetScript("OnUpdate"', 1, true), "no permanent animation loop")
	f = assert(io.open(ADDON_DIR .. "Olympus.toc", "rb")); local toc = f:read("*a"); f:close()
	assert(toc:find("Link.lua\nArmyExport.lua\nGuildCharter.lua", 1, true), "ArmyExport loads immediately after Link")
end)
