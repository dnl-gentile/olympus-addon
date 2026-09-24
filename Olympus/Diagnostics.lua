local ADDON, ns = ...
local L = ns.L

-- Everything that goes wrong is stored in OlympusDB.errors (deduplicated, with stack and count)
-- and OlympusDB.log. Both live in WTF/Account/<ACCOUNT>/SavedVariables/Olympus.lua, which WoW
-- writes on /reload or logout, so a developer can read it straight from disk.
-- Players without disk access use /oly bug, which opens a copyable report.

local MAX_ERRORS = 50
local warnedThisSession = false

local function ClientInfo()
	local version, build, _, toc = GetBuildInfo()
	return ("%s (%s) toc %s, locale %s"):format(tostring(version), tostring(build), tostring(toc), tostring(GetLocale()))
end

function ns.CaptureError(where, err)
	local db = ns.db
	local msg = tostring(err)
	local stack = debugstack and debugstack(3, 12, 0) or ""
	if not db then
		print("|cffff4040Olympus error (before load):|r " .. msg)
		return
	end
	local key = where .. "|" .. msg
	for _, e in ipairs(db.errors) do
		if e.key == key then
			e.count = e.count + 1
			e.last = date("%Y-%m-%d %H:%M:%S")
			return
		end
	end
	table.insert(db.errors, {
		key = key,
		where = where,
		msg = msg,
		stack = stack,
		count = 1,
		first = date("%Y-%m-%d %H:%M:%S"),
		last = date("%Y-%m-%d %H:%M:%S"),
		version = ns.VERSION,
		client = ClientInfo(),
	})
	while #db.errors > MAX_ERRORS do table.remove(db.errors, 1) end
	ns.Log("ERROR in %s: %s", where, msg)
	if not warnedThisSession then
		warnedThisSession = true
		ns.Print("|cffff4040" .. L.ERROR_CAUGHT .. "|r")
	end
end

-- Errors raised while loading (before SavedVariables existed) were kept by Bootstrap.lua.
ns.On("INIT", function()
	for _, e in ipairs(ns.earlyErrors or {}) do ns.CaptureError("load", e[1]) end
	ns.earlyErrors = {}
	ns.db.allErrors = ns.allErrors -- same table: errors seen later this session are saved too
end)

-- Blocked protected calls (taint) are not Lua errors, so log them separately.
for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
	ns.RegisterEvent(event, function(addon, func)
		ns.Log("%s: %s tried %s", event, tostring(addon), tostring(func))
	end)
end

-- "a=3 b=1", sorted, for small count tables.
local function CountList(t)
	local out = {}
	for k, v in pairs(t or {}) do out[#out + 1] = k .. "=" .. v end
	table.sort(out)
	return #out > 0 and table.concat(out, " ") or "none"
end

-- Everything that tells two realms apart, to settle whether PvP and PvP 2 share anything.
local function RealmLine()
	local guid = UnitGUID and UnitGUID("player")
	local serverID = guid and guid:match("^Player%-(%d+)%-")
	local linked = GetAutoCompleteRealms and GetAutoCompleteRealms() or nil
	local _, _, _, guildRealm = GetGuildInfo("player")
	return ("%s (normalized %s, stored as %s)  serverID=%s  guildRealm=%s  connected=%s  roster realms: %s"):format(
		tostring(GetRealmName and GetRealmName()), tostring(GetNormalizedRealmName and GetNormalizedRealmName()),
		tostring(ns.realm), tostring(serverID), tostring(guildRealm),
		linked and #linked > 0 and table.concat(linked, ",") or "none",
		CountList(ns.Roster and ns.Roster.realms))
end

-- How many players are in our channel, when the client knows (it may not until asked).
local function ChannelMembers(name)
	if not name or not GetNumDisplayChannels or not GetChannelDisplayInfo then return nil end
	local ok, n = pcall(function()
		for i = 1, GetNumDisplayChannels() do
			local cname, _, _, _, count = GetChannelDisplayInfo(i)
			if cname == name then return count end
		end
	end)
	return ok and n or nil
end

function ns.StatusText()
	local lines = {}
	local function add(fmt, ...) lines[#lines + 1] = fmt:format(...) end
	local guild = GetGuildInfo("player")
	add("Olympus v%s  |  %s", ns.VERSION, ClientInfo())
	add("player %s  |  guild %s  |  olympus member: %s", tostring(ns.me), tostring(guild), tostring(ns.IsMember()))
	add("realm: %s", RealmLine())
	local st = ns.Roster and ns.Roster.lastStats
	if st then
		add("roster: total=%s online=%s rowsRead=%d offlineRows=%d leader=%s (%s) zones=%d scanMs=%.1f %s",
			tostring(st.numTotal), tostring(st.numOnline), st.seen, st.seenOffline, tostring(st.leader),
			st.leaderOnline and "online" or "offline", st.zones, st.ms or 0, ns.Ago(st.t))
	else
		add("roster: not scanned yet")
	end
	local c = ns.Comm and ns.Comm.Stats()
	if c then
		add("channel '%s' = #%s  sealed=%s  |  peers in guild=%d  |  reporter=%s (me: %s)", tostring(c.channelName), tostring(c.channel), tostring(c.sealed), c.peers, tostring(c.reporter), tostring(c.isReporter))
		add("sent=%d recv=%d reports=%d sendFails=%d badMsgs=%d queue=%d lastFail=%s", c.sent, c.recv, c.reports, c.fails, c.bad, c.queue, tostring(c.lastFail))
		local types = {}
		for k, v in pairs(c.byType or {}) do types[#types + 1] = k .. "=" .. v end
		table.sort(types)
		add("received by type: %s  |  incomplete reports: %d waiting, %d dropped", #types > 0 and table.concat(types, " ") or "none", c.pending or 0, c.partial or 0)
		add("senders by realm: %s  |  own echoes: %d  |  channel members: %s", CountList(c.realms), c.echo or 0, tostring(ChannelMembers(c.channelName)))
	end
	local n = 0
	for _ in pairs(ns.rdb.guilds) do n = n + 1 end
	add("cached guilds=%d  |  map=%s  |  errors=%d  |  sessions=%d", n, tostring(ns.db.showMap), #ns.db.errors, ns.db.sessions or 0)
	add("map lib: %s  |  zones indexed=%d  |  tabs: %s", tostring(ns.Map and ns.Map.libOk), ns.Zones and ns.Zones.Count() or 0,
		tostring(ns.UI and ns.UI.tabTemplate or "not built"))
	-- Old Guild tab or new Communities window: which ones exist and got the Olympus button.
	add("guild UI: %s", ns.GuildFrameHook and ns.GuildFrameHook.StatusLine() or "not loaded")
	return table.concat(lines, "\n")
end

function ns.BuildBugReport()
	local out = { "```", ns.StatusText(), "" }
	local errors = ns.db.errors
	if #errors == 0 then
		out[#out + 1] = "No errors recorded."
	else
		for i = #errors, math.max(1, #errors - 4), -1 do
			local e = errors[i]
			out[#out + 1] = ("[%dx] %s  (%s .. %s, v%s)"):format(e.count, e.where, e.first, e.last, e.version)
			out[#out + 1] = "  " .. e.msg
			for line in (e.stack or ""):gmatch("[^\n]+") do out[#out + 1] = "    " .. line end
		end
	end
	local all = ns.allErrors or {}
	if #all > 0 then
		out[#out + 1] = ""
		out[#out + 1] = "All errors this session:"
		for i = 1, math.min(6, #all) do out[#out + 1] = ("  [%dx] %s"):format(all[i].count, all[i].msg) end
	end
	out[#out + 1] = ""
	out[#out + 1] = "Last log lines:"
	local log = ns.db.log
	for i = math.max(1, #log - 25), #log do out[#out + 1] = "  " .. log[i] end
	out[#out + 1] = "```"
	return table.concat(out, "\n")
end

function ns.PrintLayer()
	local guid = UnitGUID("target") or UnitGUID("mouseover")
	if not guid then
		ns.Print("target an NPC first")
		return
	end
	local parts = {}
	for p in guid:gmatch("[^%-]+") do parts[#parts + 1] = p end
	if parts[1] ~= "Creature" and parts[1] ~= "Vehicle" then
		ns.Print("not an NPC: " .. guid)
		return
	end
	-- Creature-0-serverID-instanceID-zoneUID-npcID-spawnUID; zoneUID is what layer addons key on.
	ns.Print(("GUID %s  |  server %s  instance %s  zoneUID %s  npc %s"):format(guid, tostring(parts[3]), tostring(parts[4]), tostring(parts[5]), tostring(parts[6])))
	ns.Log("layer probe %s", guid)
end
