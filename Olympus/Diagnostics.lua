local ADDON, ns = ...
local L = ns.L

-- Everything that goes wrong is stored in OlympusDB.errors (deduplicated, with stack and count)
-- and OlympusDB.log. Both live in WTF/Account/<ACCOUNT>/SavedVariables/Olympus.lua, which WoW
-- writes on /reload or logout, so a developer can read it straight from disk.
-- Players without disk access use /oly bug, which opens a copyable report.

local MAX_ERRORS = 50
local warnedThisSession = false

-- 1.2: lines other files add to /oly status and /oly bug (ns.StatusText), each a fn(lines) that
-- appends its own strings: the Blood Arena's (ArenaNet.lua) without the arena editing this file.
ns.statusLines = ns.statusLines or {}

local function ClientInfo()
	local version, build, _, toc = GetBuildInfo()
	return ("%s (%s) toc %s, locale %s"):format(tostring(version), tostring(build), tostring(toc), tostring(GetLocale()))
end

-- 1.1.5, the gamepad gate: Bootstrap.lua's error handler (that file loads before any gate) gives the
-- game's back at a switch to the gamepad UI (GamepadRegistry.lua's "error-handler").
if ns.Gate and ns.ParkErrorHandler then ns.Gate.Hooks("error-handler", { park = ns.ParkErrorHandler }) end

-- s with every `secret` in it (plain text) as `as` ("(key)" unless given).
local function Without(s, secret, as)
	if type(s) ~= "string" or type(secret) ~= "string" or secret == "" then return s end
	local out, i = {}, 1
	while true do
		local a, b = s:find(secret, i, true)
		if not a then break end
		out[#out + 1] = s:sub(i, a - 1) .. (as or "(key)")
		i = b + 1
	end
	out[#out + 1] = s:sub(i)
	return table.concat(out)
end

-- 1.2.1: what /oly status and /oly bug never show, nor the error list or the log keep.
-- The sealed channel's name (Comm.ChannelSpec: "Oly" or "OlyH" and eight letters and digits made
-- from the realm key) gives a short key back to anyone who tries keys against it offline, and a
-- report gets pasted on Discord. It shows as "(sealed channel)", in the lines of older versions
-- too (the log names it); the public channel's name is no secret and stays.
-- A word shaped like a sealed name is also a character's name ("Oly" and eight lowercase letters
-- is a name the game allows), so the shape alone is never enough: the names this client's key gives
-- go word for word, and one of an older key only where Comm.lua writes a channel's name (its log's
-- "channel X", "joining channel X", "left channel X"; the first channel message's name= and target=).
-- (1.5.9) On Forever nobody joins the sealed channel any more (Comm.ChannelSpec), yet the log keeps the
-- name this client joined before: the names the key it holds gives, on any lane, go too (Comm.SealedBase).
local SEALED_SHAPE = "OlyH?" .. ("[0-9a-z]"):rep(8)
local SEALED_AFTER = { "(channel )", "(name=)", "(target=)" }
local function Scrub(text)
	text = tostring(text or "")
	local C = ns.Comm
	if C then
		local base = type(C.SealedBase) == "function" and C.SealedBase() or nil
		if type(base) == "string" and base ~= "" then text = text:gsub(base:gsub("%W", "%%%0") .. "%d?", "(sealed channel)") end
		local name, key = nil, nil
		if type(C.ChannelSpec) == "function" then name, key = C.ChannelSpec() end
		if key and type(name) == "string" then text = Without(text, name, "(sealed channel)") end
		local joined = type(C.ChannelName) == "function" and C.ChannelName()
		if type(joined) == "string" and joined:match("^" .. SEALED_SHAPE .. "$") then text = Without(text, joined, "(sealed channel)") end
	end
	-- (1.5.9's review) An older key's name with its lane digit after it too (a key rotated while this client
	-- sat on lane 7 left "joining channel Oly...7" in the log): the frontier alone failed on the digit.
	for _, at in ipairs(SEALED_AFTER) do text = text:gsub(at .. SEALED_SHAPE .. "%d?%f[^%w]", "%1(sealed channel)") end
	return text
end

-- A failure inside /oly key <secret>: Core.lua's SlashWhere names the command with what followed
-- it, the key itself here. It is kept as "slash key" alone, and the key (as typed, and as
-- Comm.SetRealmKey keeps it) comes out of the message and the stack. "/oly key rotate" names no key.
local function Unkeyed(where, msg, stack)
	local cmd, typed = tostring(where or ""):match("^slash%s+(%S+)%s*(.-)%s*$")
	if not cmd or cmd:lower() ~= "key" or typed == "" or typed:lower() == "rotate" then return where, msg, stack end
	local kept = typed:gsub("[~|\n]", "")
	return "slash key", Without(Without(msg, typed), kept), Without(Without(stack, typed), kept)
end

-- An error already kept is counted and its stack is not read again: one that repeats in a burst (a
-- timer's, an event's, the game's error handler's in Bootstrap.lua, for each repeat) reads it once.
function ns.CaptureError(where, err)
	local db = ns.db
	local said, raw = where, tostring(err)
	local msg
	where, msg = Unkeyed(said, raw, nil)
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
	-- (Read here, in this function itself, so its level is the one it always was; a key typed with
	-- /oly key comes out of it as out of the message.)
	local _, _, stack = Unkeyed(said, raw, debugstack and debugstack(3, 12, 0) or "")
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
		-- (With the gamepad UI not "type /oly bug": a command typed there can set off a block.)
		ns.Print("|cffff4040" .. (ns.GamepadUI() and L.ERROR_CAUGHT_GAMEPAD or L.ERROR_CAUGHT) .. "|r")
	end
end

-- Errors raised while loading (before SavedVariables existed) were kept by Bootstrap.lua.
ns.On("INIT", function()
	for _, e in ipairs(ns.earlyErrors or {}) do ns.CaptureError("load", e[1]) end
	ns.earlyErrors = {}
	-- (1.2.1) A key typed with /oly key that older versions kept with a failure: out of the saved
	-- errors and log ("ERROR in slash key <key>: ..." there: the line keeps the command alone).
	for _, e in ipairs(type(ns.db.errors) == "table" and ns.db.errors or {}) do
		if type(e) == "table" and type(e.where) == "string" then
			local where = e.where
			e.where, e.msg, e.stack = Unkeyed(e.where, e.msg, e.stack)
			if e.where ~= where then e.key = e.where .. "|" .. tostring(e.msg) end
		end
	end
	local log = type(ns.db.log) == "table" and ns.db.log or {}
	for i, line in ipairs(log) do
		if type(line) == "string" then
			local head, cmd, rest = line:match("^(.-ERROR in slash%s+)(%S+)%s+(.*)$")
			if head and cmd:lower() == "key" and not rest:lower():find("^rotate:") then log[i] = head .. "key (not kept)" end
		end
	end
	-- Only Olympus's own errors are kept (0.9.2, Bootstrap.lua): the saved list of an older
	-- version, with every other addon's in it, is replaced, and nothing of theirs stays.
	local all = ns.allErrors or {}
	for i = #all, 1, -1 do
		local e = all[i]
		if type(e) ~= "table" or not (ns.OwnError and ns.OwnError(e.msg, e.stack)) then table.remove(all, i) end
	end
	ns.allErrors, ns.db.allErrors = all, all -- same table: errors seen later this session are saved too
end)

-- What Blizzard's gamepad UI reads on its way to the calls only it may make (0.9.8), from its
-- own code on Forever 1.60: the interact button's target (Blizzard_GamepadActionBars/
-- MainActionBarFrame.lua, UpdateInteractIcons -> SetPreferredGamepadInteractTarget), the binding
-- stack it asks first (Blizzard_GamepadSharedUtility/InputBindingStack/InputBindingManager.lua),
-- the frames and popups it follows (FrameControlsManager.lua, Blizzard_StaticPopup/
-- StaticPopupGamepad.lua), the escape list its menus sweep (CloseSpecialWindows) and the chat box
-- it focuses (an addon's slash command runs inside the chat box's own code: ChatFrameEditBox.lua).
-- A value an addon wrote there makes the game blame that addon when the call comes;
-- issecurevariable says which values, and whose.
local PROBE_GLOBALS = {
	"GamepadSharedUtility", "GamepadMode", "GamepadMainActionBarFrame", "SmartNavigation", "InputUtil",
	"EventRegistry", "RunNextFrame", "GenerateClosure", "C_Timer", "C_Spell", "SetPreferredGamepadInteractTarget",
	"SetUnitCursorTexture", "UnitExists", "UnitIsGameObject", "UnitHasLootInteraction", "UnitIsInInteractRange",
	"UnitIsInteractable", "UnitCanAttack", "UISpecialFrames", "CloseSpecialWindows", "CloseAllWindows",
	"ShowUIPanel", "HideUIPanel", "StaticPopup_Show", "StaticPopup_Hide", "ACTIVE_CHAT_EDIT_BOX", "LAST_ACTIVE_CHAT_EDIT_BOX",
}
-- label, the object (nil when this client has none), its fields, and the field that is a list
-- whose slots are read one by one.
-- gp:diagnostics
local PROBE_OBJECTS = {
	{ "binding stack", function() return type(GamepadSharedUtility) == "table" and GamepadSharedUtility.InputBindingManager end,
		{ "bindingSetStack", "currentCoreBindingActive", "assumeCoreBindingsUsable", "coreSet", "coreBindingListenerFunctions" }, "bindingSetStack" },
	{ "frame controls", function() return type(GamepadMode) == "table" and GamepadMode.FrameControlsManager end,
		{ "shownFrames", "focusedFrame", "isUIFocused", "fallThroughCatcherActive", "topSuspendedFrame" }, "shownFrames" },
	{ "gamepad popups", function() return type(GamepadMode) == "table" and GamepadMode.PopupHandler end,
		{ "visiblePopups", "activePopup" }, "visiblePopups" },
	{ "action bar", function() return GamepadMainActionBarFrame end, { "PageUnit", "autoLootOnTap" } },
	{ "smart navigation", function() return SmartNavigation end, { "currentButton", "activeInfo" } },
}
local PROBE_SLOTS = 20 -- slots of a list read at most (one past its end too: a slot emptied)

-- One line: the values above an addon wrote, and whose, or that none was.
function ns.TaintProbe() -- gp:diagnostics
	if type(issecurevariable) ~= "function" then return "taint: not checked (no issecurevariable)" end
	local found, checked = {}, 0
	local function Check(label, t, key)
		local ok, secure, by
		if t == nil then ok, secure, by = pcall(issecurevariable, key) else ok, secure, by = pcall(issecurevariable, t, key) end
		if not ok then return end
		checked = checked + 1
		if not secure then found[#found + 1] = label .. " by " .. tostring(by or "?") end
	end
	local function Slots(label, list)
		if type(list) ~= "table" then return end
		for i = 1, math.min(#list + 1, PROBE_SLOTS) do
			local v = list[i]
			Check(("%s[%d]%s"):format(label, i, type(v) == "string" and ("=" .. v) or ""), list, i)
			if type(v) == "table" and label == "bindingSetStack" then
				Check(("%s[%d].treatBindsAsCore"):format(label, i), v, "treatBindsAsCore")
			end
		end
	end
	for _, name in ipairs(PROBE_GLOBALS) do Check(name, nil, name) end
	for _, o in ipairs(PROBE_OBJECTS) do
		local ok, t = pcall(o[2])
		if ok and type(t) == "table" then
			for _, key in ipairs(o[3]) do Check(o[1] .. "." .. key, t, key) end
			if o[4] then Slots(o[4], rawget(t, o[4])) end
		end
	end
	Slots("UISpecialFrames", UISpecialFrames)
	if #found == 0 then return ("taint: none of %d values the gamepad UI reads"):format(checked) end
	local shown = {}
	for i = 1, math.min(8, #found) do shown[i] = found[i] end
	return ("taint: %s%s (%d checked)"):format(table.concat(shown, ", "), #found > 8 and (", +" .. (#found - 8)) or "", checked)
end

-- Blocked protected calls (taint) are not Lua errors, so they are kept apart. The first ones
-- logged with where they came from (the handler runs inside the blocked call); a burst
-- (Blizzard's gamepad UI repeats a block on every popup) counted, not logged line by line.
-- Each blocked call of ours is also kept (0.9.8) in OlympusDB.actionsBlocked, once per call
-- with a count: the call the game refused, the stack it was refused in and what the taint
-- probe saw, all in /oly bug. With the gamepad UI one line in chat, once a session, asks the
-- player for that report: there it is the only way to learn what the game refused.
local MAX_BLOCKED = 10
local blocked, toldGamepad = 0, false
function ns.ResetBlocked() blocked, toldGamepad = 0, false end -- tests

-- The game raises the event inside the refused call, so the stack read here starts with this
-- handler's own frames (it, pcall, Core.lua's SafeCall and event dispatch), which never made the
-- call. They are dropped (1.2.1): the report's 8 lines then start at the refused call and reach
-- what called it, where they had stopped at UpdateInteractIcons under four lines of ours.
local OWN_FRAMES = { "AddOns[\\/]Olympus[\\/]Diagnostics%.lua", "AddOns[\\/]Olympus[\\/]Core%.lua", "^%[C%]: in function [`']x?pcall'" }
local function Own(line)
	for _, p in ipairs(OWN_FRAMES) do if line:find(p) then return true end end
	return false
end
function ns.RefusedStack(stack) -- (tests)
	local out, ours = {}, true
	for line in tostring(stack or ""):gmatch("[^\n]+") do
		ours = ours and Own(line)
		if not ours then out[#out + 1] = line end
	end
	return #out > 0 and table.concat(out, "\n") or tostring(stack or "")
end

-- Kept once per call; the first time it comes in a session its stack and probe are taken
-- again (and it moves to the end, the newest), so the report shows this version's evidence.
local function RecordBlocked(event, func)
	local db = ns.db
	if not db then return end
	db.actionsBlocked = type(db.actionsBlocked) == "table" and db.actionsBlocked or {}
	local list, key, now = db.actionsBlocked, event .. "|" .. func, date("%Y-%m-%d %H:%M:%S")
	local b
	for i, e in ipairs(list) do
		if e.key == key then
			e.count, e.last = (e.count or 0) + 1, now
			if e.session == db.sessions then return end
			b = table.remove(list, i)
			break
		end
	end
	local stack = ""
	if type(debugstack) == "function" then
		local ok, s = pcall(debugstack, 2, 24, 6)
		stack = ok and type(s) == "string" and ns.RefusedStack(s) or ""
	end
	local okProbe, taint = pcall(ns.TaintProbe)
	b = b or { key = key, event = event, func = func, count = 1, first = now, last = now }
	b.session, b.version, b.client, b.gamepad, b.stack = db.sessions, ns.VERSION, ClientInfo(), ns.GamepadUI(), stack
	b.taint = okProbe and taint or ("taint: probe failed: " .. tostring(taint))
	list[#list + 1] = b
	while #list > MAX_BLOCKED do table.remove(list, 1) end
end

for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
	ns.RegisterEvent(event, function(addon, func)
		-- Another addon's: logged as always.
		if addon ~= ADDON then return ns.Log("%s: %s tried %s", event, tostring(addon), tostring(func)) end
		blocked = blocked + 1
		if blocked <= 3 then
			local stack = debugstack and debugstack(2, 12, 0) or ""
			ns.Log("%s: %s tried %s | %s", event, tostring(addon), tostring(func), (stack:gsub("\n", " < ")))
		elseif blocked <= 10 or blocked % 100 == 0 then
			ns.Log("%s: %s tried %s (%d this session)", event, tostring(addon), tostring(func), blocked)
		end
		RecordBlocked(event, tostring(func))
		if ns.GamepadUI() and not toldGamepad then
			toldGamepad = true
			ns.Print("|cffff4040" .. L.BLOCKED_GAMEPAD .. "|r")
		end
	end)
end

-- "a=3 b=1", sorted by key, for small count tables.
local function CountList(t)
	local keys, out = {}, {}
	for k in pairs(t or {}) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	for i, k in ipairs(keys) do out[i] = tostring(k) .. "=" .. tostring(t[k]) end
	return #out > 0 and table.concat(out, " ") or "none"
end

-- fn(...) for an API some clients lack: nil when it is missing or fails.
local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	if ok then return v end
	return nil
end

-- Everything that tells two realms apart, to settle whether PvP and PvP 2 share anything.
-- Short lines here and below: they have to be readable in the /oly bug window.
local function RealmLines()
	local guid = Try(UnitGUID, "player")
	local serverID = type(guid) == "string" and guid:match("^Player%-(%d+)%-") or nil
	local guild, _, _, guildRealm = GetGuildInfo("player")
	-- Connected realms, other than ours. The global GetAutoCompleteRealms only exists with
	-- Blizzard's deprecation fallbacks on, so its "none" meant nothing.
	local auto = Try(C_AutoComplete and C_AutoComplete.GetAutoCompleteRealms)
	local linked = "n/a"
	if type(auto) == "table" then
		local others = {}
		for _, name in ipairs(auto) do
			name = tostring(name):gsub("[%s%-]", "")
			if name ~= ns.realm then others[#others + 1] = name end
		end
		linked = #others > 0 and table.concat(others, ",", 1, math.min(#others, 2)) .. (#others > 2 and (",+" .. (#others - 2)) or "") or "none"
	end
	local unique = Try(RegionalUniqueNamesEnabled)
	return ("realm: %s = %s  id=%s native=%s guid=%s  guild home=%s"):format(
			tostring(Try(GetRealmName)), tostring(ns.realm), tostring(Try(GetRealmID)), tostring(Try(GetNativeRealmID)),
			tostring(serverID), guild and tostring(guildRealm or "ours") or "-"),
		("census: %s (%s)  unique names=%s  connected=%s"):format(
			tostring(ns.group), ns.GroupSource and ns.GroupSource(ns.realm) or "?", unique == nil and "?" or tostring(unique), linked)
end

-- "[name]" as the server sent it, or "-" when there is none.
local function Sample(name)
	return name and ("[" .. name .. "]") or "-"
end

-- Names as the server sent them, before ns.FullName gives bare names our realm: the only
-- counts that can tell a guildmate on the other realm from one on ours. One short line each.
local function NamesLines(c)
	local R, raw, samples = ns.Roster, c.raw or {}, c.rawSample or {}
	local whoNames, whoSuffix, whoSample
	if ns.Who and ns.Who.RawCounts then whoNames, whoSuffix, whoSample = ns.Who.RawCounts() end
	return {
		("names raw: roster %s  e.g. %s"):format(CountList(R and R.rawRealms), Sample(R and R.rawSample)),
		("names raw: roster by server (GUID) %s"):format(CountList(R and R.servers)),
		("names raw: ch %s  e.g. %s"):format(CountList(raw.ch), Sample(samples.ch)),
		("names raw: g %s  e.g. %s"):format(CountList(raw.g), Sample(samples.g)),
		("names raw: who %s guild-suffix=%d  e.g. %s"):format(CountList(whoNames), whoSuffix or 0, Sample(whoSample)),
	}
end

-- "ClassicBetaPvP,ClassicBetaPvP2", two realms named at most (then "+n"), or "-".
local function RealmList(list)
	if type(list) ~= "table" or #list == 0 then return "-" end
	return table.concat(list, ",", 1, math.min(#list, 2)) .. (#list > 2 and (",+" .. (#list - 2)) or "")
end

-- Does the channel cross realms (a report sent from another realm reached us), where do our
-- guildmates with the addon play, and is our guild's reporter heard?
local function TopologyLines(c)
	local shared = type(c.shared) == "table" and c.shared
	return {
		shared and ("topology: channel SHARED (%s -> %s, %s)"):format(tostring(shared.realm), tostring(shared.to), ns.Ago(shared.t))
			or "topology: channel shared: not seen yet",
		("topology: reports by realm %s"):format(CountList(c.reportRealms)),
		("topology: guild peers by realm %s"):format(CountList(c.peerRealms)),
		("topology: own guild's report heard from %s"):format(c.heardOwn and (c.heardOwn .. " " .. ns.Ago(c.heardOwnAt)) or "nobody yet"),
		("topology: left out of the election: %s"):format(c.benched and #c.benched > 0 and table.concat(c.benched, ", ") or "none"),
		-- 1.0.0: a reporter per realm (or one for all while the channel is shared), and what our
		-- own report says of our guild's realms (fields 25-27).
		("topology: reporter elected on %s  |  quiet after %s before us"):format(
			c.electAll and "every realm (channel shared)" or "this realm", tostring(c.quietAfter or "?")),
		("topology: guild on %s  |  report st=%s cap=%s pres=%s"):format(RealmList(c.presence), tostring(c.reportSt or "-"),
			tostring(c.reportCap or "-"), type(c.reportPres) == "table" and #c.reportPres > 0 and table.concat(c.reportPres, ".", 1, math.min(#c.reportPres, 4)) or "-"),
	}
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

-- (The review of the 1.5.4 candidate.) The relay's counters (Relay.Stats) and verification's
-- (Verify.Stats) for /oly status and /oly bug. A relay's log turns the lines /oly bug prints over in
-- seconds (one line per piece it carries), so what crossed to the other relays (RW), what was
-- answered direct, and what was asked, answered, unsent (a full queue) or refused (an untrusted
-- sender's word) is counted here. Read at the call: Relay.lua and Verify.lua load after this file.
local function RelayLine()
	local R, V = ns.Relay, ns.Verify
	if type(R) ~= "table" or type(R.Stats) ~= "function" then return "not loaded" end
	local s = R.Stats()
	local v = type(V) == "table" and type(V.Stats) == "function" and V.Stats() or {}
	local function N(x) return tonumber(x) or 0 end
	-- (1.5.5) The relay's chat lane (Relay.lua): chat whispers waiting, lost (past its bound or its time),
	-- and skipped (their reporter quarantined, no longer served or registered, a relay left out, by then).
	return ("%s  |  out %d  forwarded %d  delivered %d  dropped %d  dead %d  kept %d  trickled %d  reporters %d  pending %d  |  verify across %d  direct %d  asked %d  answered %d  unsent %d  untrusted %d  bad %d  |  chat lane %d waiting, %d lost, %d skipped"):format(
		not s.on and "off" or (tostring(s.relay or "none") .. (s.sure and "" or " (unanswered)")),
		N(s.out), N(s.forwarded), N(s.delivered), N(s.dropped), N(s.dead), N(s.kept), N(s.trickled), N(s.reporters), N(s.pending),
		N(s.verifyAcross), N(s.direct), N(v.asked), N(v.answered), N(v.unsent), N(v.refused), N(v.bad), N(s.chatWaiting), N(s.chatLost), N(s.chatSkipped))
end

---------------------------------------------------------------------------
-- (1.5.5) The game this client is, and whether this copy of Olympus fits it. A player said an install
-- in the wrong flavor folder changed his counts: the CurseForge app's installation for Forever's
-- folder left on "Classic" installs the last file listed for Classic, an old Olympus, whose census
-- and relay no longer meet the others' (about a thousand soldiers instead of thirty thousand), and no
-- update ever comes. What this client can tell, and /oly bug shows: which game it is by its interface
-- number (Forever 1.60, Era 1.15, Anniversary 2.5, as Workshop.Client reads it), its realm's family
-- (a WoW: Forever realm, ns.ForeverFamily), whether this copy's TOC lists that interface
-- (ns.TOC_INTERFACES, the Interface line of Olympus.toc: a test keeps them one), whether its files are
-- of one version (the TOC's, Olympus_Arena's and the site reporter's against ns.VERSION), and whether
-- a newer Olympus is out (the author's released version, Workshop.Behind).
-- Said at login, once a session, only when something is really wrong ("problems"): a game this copy
-- was not made for (no interface of that game in its TOC), files of two versions, or the author's
-- released version newer than ours. A patch of a game it was made for whose number its TOC does not
-- list (Forever's next interface, 16006, before an Olympus lists it) is a note in /oly bug alone: no
-- Olympus for it exists yet, and every player on that patch would be told to update. Guildmates'
-- hellos are never trusted for it: they are unsigned (two testers on a test build, or two forged
-- hellos, name any version); /oly bug shows the newest they named, marked so, and nothing else.
-- The author's version comes only from his presence (V4) under a name pinned as his
-- (Workshop.HandlePresence, ns.IsAuthorName).
---------------------------------------------------------------------------
ns.TOC_INTERFACES = { 11509, 11510, 16001, 16002, 16003, 16004, 16005, 16010, 16100, 20506, 20507 }
ns.INSTALL_PEERS = 2 -- guildmates on one newer release before /oly bug shows it (shown only: never a problem)

local function ClientOf(toc)
	if toc >= 16000 and toc < 20000 then return "Forever" end
	if toc >= 20000 and toc < 30000 then return "Anniversary" end
	if toc >= 10000 and toc < 16000 then return "Era" end
	return "?"
end
-- The CurseForge app's installation to pick, per game: the hint names the player's own game (none
-- for a game Olympus is not made for).
local FLAVOR = { Forever = "INSTALL_FLAVOR", Era = "INSTALL_FLAVOR_ERA", Anniversary = "INSTALL_FLAVOR_ANNIVERSARY" }
local function Meta(addon, field)
	local AO = C_AddOns
	local get = type(AO) == "table" and AO.GetAddOnMetadata or nil
	local v = Try(get, addon, field)
	return type(v) == "string" and v ~= "" and v or nil
end
-- The newest release INSTALL_PEERS guildmates or more ran by their hellos (Comm.PeerVersions), and
-- how many: only one newer than ours, else nil. Shown in /oly bug as unsigned; never a problem.
local function PeersNewer()
	local C, W = ns.Comm, ns.Workshop
	local counts = type(C) == "table" and type(C.PeerVersions) == "function" and Try(C.PeerVersions) or nil
	if type(counts) ~= "table" or type(W) ~= "table" or type(W.Newer) ~= "function" then return nil end
	local best, n = nil, 0
	for v, count in pairs(counts) do
		if type(v) == "string" and v:match("^%d+%.%d+%.%d+$") and tonumber(count) and count >= ns.INSTALL_PEERS
			and W.Newer(v, ns.VERSION) and (not best or W.Newer(v, best)) then best, n = v, count end
	end
	return best, n
end

-- { client, toc, game, build, project, realm, family, group, version, tocVersion, arena, site,
--   declared, note ("newer" | "older" | "unlisted": a patch of this game the TOC does not list;
--   "unread": no interface from the client),
--   author, behind, peers, peersCount (unsigned: shown only), problems = { "toc" | "mixed" | "behind" ... } }
function ns.Install()
	local okB, game, build, _, toc = pcall(GetBuildInfo)
	toc = okB and tonumber(toc) or 0
	local W = ns.Workshop
	local s = {
		client = ClientOf(toc), toc = toc, game = okB and tostring(game) or "?", build = okB and tostring(build) or "?",
		project = tonumber(rawget(_G, "WOW_PROJECT_ID")), realm = ns.realm, group = ns.group,
		family = type(ns.ForeverFamily) == "function" and ns.ForeverFamily(ns.realm or "") or nil,
		version = ns.VERSION, tocVersion = Meta(ADDON, "Version"), arena = Meta("Olympus_Arena", "Version"),
		site = Meta("OlympusSiteAggregate", "Version"), problems = {},
	}
	s.declared = false
	local lowest, highest -- this game's interfaces in the TOC
	for _, n in ipairs(ns.TOC_INTERFACES) do
		if n == toc then s.declared = true end
		if ClientOf(n) == s.client then lowest, highest = math.min(lowest or n, n), math.max(highest or n, n) end
	end
	s.author = type(W) == "table" and type(W.AuthorVersion) == "function" and Try(W.AuthorVersion) or nil
	s.peers, s.peersCount = PeersNewer()
	if not s.declared then
		-- A patch of a game this copy is made for: a note (the game loads it as out of date). Another
		-- game's interface: a problem. An interface the client did not give: nothing to judge, a note.
		if toc <= 0 then s.note = "unread"
		elseif highest then s.note = toc > highest and "newer" or (toc < lowest and "older" or "unlisted")
		else s.problems[#s.problems + 1] = "toc" end
	end
	-- (Ours, or ours and a build of it: an arena test build's TOC says "1.5.5-test.3", the site
	-- reporter's "1.5.5-site.1", scripts/package.sh; the arena module's is ours alone.)
	local function Ours(v) return v == s.version or v:sub(1, #s.version + 1) == s.version .. "-" end
	if s.tocVersion and not Ours(s.tocVersion) then s.odd = s.tocVersion
	elseif s.arena and s.arena ~= s.version then s.odd = s.arena
	elseif s.site and not Ours(s.site) then s.odd = s.site end
	if s.odd then s.problems[#s.problems + 1] = "mixed" end
	-- Behind the author's released version alone (his presence, under a name pinned as his).
	s.behind = type(W) == "table" and type(W.Behind) == "function" and Try(W.Behind) or nil
	if s.behind then s.problems[#s.problems + 1] = "behind" end
	return s
end

-- The install's lines for /oly bug: the problems and the game (the problems first: a line cut at
-- DEBUG_LINE keeps them), then the files and the versions heard.
function ns.InstallLine()
	local s = ns.Install()
	local listed = s.declared and "yes" or (s.note == "unread" and "interface not read: a note, not told")
		or (s.note and ("no, %s %s patch: a note, not told"):format(s.note, s.client)) or "NO"
	return ("install: problems %s  |  client %s (toc %s, in Olympus.toc: %s; game %s build %s, project %s)  |  realm family %s, group %s"):format(
		#s.problems > 0 and table.concat(s.problems, ", ") or "none", s.client, tostring(s.toc), listed, s.game, s.build,
		tostring(s.project or "?"), tostring(s.family or "none"), tostring(s.group or "?"))
end
function ns.InstallFilesLine()
	local s = ns.Install()
	return ("install files: Olympus %s (toc %s, arena %s, site %s)  |  released: author %s, guild hellos %s"):format(
		s.version, tostring(s.tocVersion or "?"), tostring(s.arena or "not installed"), tostring(s.site or "not installed"),
		tostring(s.author or "none"), s.peers and (s.peers .. " x" .. tostring(s.peersCount) .. " (unsigned)") or "none newer")
end

-- What the player is told (once a session for each problem): the lines, or an empty list. "behind"
-- has its own line already (Workshop.HeardVersion: BEHIND_CHAT); the CurseForge app's installation
-- for this game follows any of them.
local installTold = {}
function ns.InstallWarnings()
	local s, out = ns.Install(), {}
	for _, p in ipairs(s.problems) do
		if not installTold[p] then
			installTold[p] = true
			if p == "toc" then out[#out + 1] = L.INSTALL_TOC:format(s.version, tostring(s.toc))
			elseif p == "mixed" then out[#out + 1] = L.INSTALL_MIXED:format(s.version, tostring(s.odd)) end
		end
	end
	local flavor = FLAVOR[s.client]
	if #s.problems > 0 and flavor and not installTold.flavor then
		installTold.flavor = true
		out[#out + 1] = L[flavor]
	end
	return out
end
function ns.ResetInstallWarnings() wipe(installTold) end -- (tests)
local function WarnInstall()
	for _, line in ipairs(ns.InstallWarnings()) do ns.Print("|cffff8040" .. line .. "|r") end
end
ns.On("LOGIN", function()
	-- (After the guildmates' first hellos, and again once the author's presence had time to come.)
	ns.After(45, "install check", WarnInstall)
	ns.After(300, "install check", WarnInstall)
end)

---------------------------------------------------------------------------
-- (1.5.5) /oly bug's debug section: short, bounded lines (DEBUG_LINE bytes each, DEBUG_MAX in all), no
-- other player's name or data and no BattleTag: counts, ages, this client's own state, realm names.
---------------------------------------------------------------------------
-- (1.5.8: 3700, for the census and tree lines added last, so the signed line before them is never cut.)
ns.DEBUG_LINE, ns.DEBUG_MAX = 320, 3700
-- A length of time, short: 90s, 5m, 3h, 2d.
local function Span(d)
	d = math.max(0, tonumber(d) or 0)
	if d < 120 then return ("%ds"):format(d) end
	if d < 7200 then return ("%dm"):format(math.floor(d / 60)) end
	if d < 172800 then return ("%dh"):format(math.floor(d / 3600)) end
	return ("%dd"):format(math.floor(d / 86400))
end
local function Age(t)
	t = tonumber(t)
	if not t then return "?" end
	return Span((ns.Now and ns.Now() or time()) - t)
end
local function Cap(line) return #line > ns.DEBUG_LINE and (line:sub(1, ns.DEBUG_LINE - 3) .. "...") or line end

-- Per kind of message in pieces (Codec.PieceStats): the ten with the most pieces, then the reasons.
local function PiecesLine()
	local C = ns.Codec
	local st = type(C) == "table" and type(C.PieceStats) == "function" and Try(C.PieceStats) or nil
	if type(st) ~= "table" then return "pieces: not counted" end
	local list = {}
	for kind, k in pairs(st.kinds or {}) do list[#list + 1] = { kind = kind, k = k } end
	table.sort(list, function(a, b)
		if a.k.p ~= b.k.p then return a.k.p > b.k.p end
		return a.kind < b.kind
	end)
	local parts = {}
	for i = 1, math.min(10, #list) do
		local e = list[i]
		parts[#parts + 1] = ("%s p%d a%d i%d d%d"):format(e.kind, e.k.p, e.k.a, e.k.i, e.k.d)
	end
	if #list > 10 then parts[#parts + 1] = "+" .. (#list - 10) .. " kinds" end
	return ("pieces: in %d  |  %s  |  why: %s"):format(tonumber(st.pieces) or 0, #parts > 0 and table.concat(parts, ", ") or "none",
		CountList(st.why))
end

-- The relay and the reporter: this client's side, no name.
local function RelayReporterLine()
	local R, C = ns.Relay, ns.Comm
	local s = type(R) == "table" and type(R.Stats) == "function" and Try(R.Stats) or nil
	local c = type(C) == "table" and type(C.Stats) == "function" and Try(C.Stats) or {}
	local relay = "not loaded"
	if type(s) == "table" then
		relay = not s.on and "off" or ("%s, relay here: %s, reporters %d, pending %d, out %d delivered %d dead %d dropped %d trickled %d"):format(
			s.relay and (s.sure and "picked, answered" or "picked, unanswered") or "none picked",
			R.IsRelay and Try(R.IsRelay, ns.me) and "yes" or "no", tonumber(s.reporters) or 0, tonumber(s.pending) or 0,
			tonumber(s.out) or 0, tonumber(s.delivered) or 0, tonumber(s.dead) or 0, tonumber(s.dropped) or 0, tonumber(s.trickled) or 0)
	end
	return ("relay: %s  |  reporter: this client %s, guild's known %s, guild peers %s, reports heard %s, bad %s, incomplete %s"):format(
		relay, c.isReporter and "yes" or "no", c.reporter and "yes" or "no", tostring(c.peers or 0), tostring(c.reports or 0),
		tostring(c.bad or 0), tostring(c.partial or 0))
end

-- (1.5.9, two /oly bug reports of 2026-11-12: no census piece came by the relay, and nothing showed
-- why.) On a relay, what decides whether its registrants get the census, no name: quiet presence (no
-- snapshot of its own then: Data.SendGlobalCensus), the drip's transfers waiting and the longest any of
-- them, and any census one, has waited (Relay.DripStats), and its own last tree round's age. (1.5.9's
-- review) And the transfer in flight, which holds every other one while its batch waits (census or other,
-- its batch of how many, and for how long): a begun transfer stuck between batches showed as nothing.
-- In the status (StatusText, below the channel line), not the debug section: a report sent in game stops
-- at Workshop.BUG_MAX bytes, past which a relay's debug section fell. (Round 1's re-review) And the drip's
-- whispers handed to the send queue since login (Relay.Stats): its census transfers', the others', and
-- those of either past its pace (Relay.DRIP_PER_MIN) while nothing else waited: census starved behind
-- other words, or a pace that never lets census go, shows there.
local function RelayHereLine()
	local R = ns.Relay
	if type(R) ~= "table" or type(R.IsRelay) ~= "function" or Try(R.IsRelay, ns.me) ~= true then return nil end
	local quiet = type(ns.QuietPresence) == "function" and Try(ns.QuietPresence) == true
	local d = type(R.DripStats) == "function" and Try(R.DripStats) or nil
	local drip = "?"
	if type(d) == "table" then
		local f = type(d.flight) == "table" and d.flight or nil
		drip = ("%d waiting (%d census), the oldest for %s, the oldest census one for %s, in flight: %s"):format(tonumber(d.waiting) or 0,
			tonumber(d.census) or 0, d.oldest and Span(d.oldest) or "-", d.oldestCensus and Span(d.oldestCensus) or "-",
			f and ("%s, batch %d/%d, for %s"):format(f.census and "census" or "other", tonumber(f.batch) or 0, tonumber(f.of) or 0,
				Span(f.since)) or "none")
	end
	local s = type(R.Stats) == "function" and Try(R.Stats) or nil
	local sent = type(s) == "table" and ("%d census, %d other, %d past the pace"):format(tonumber(s.dripCensus) or 0,
		tonumber(s.dripOther) or 0, tonumber(s.dripFree) or 0) or "?"
	local T = ns.RelayTree
	local tree = type(T) == "table" and not T.missing and type(T.Stats) == "function" and Try(T.Stats) or nil
	local round = type(tree) == "table" and type(tree.round) == "table" and tonumber(tree.round.age) or nil
	return ("relay here: quiet presence %s  |  drip %s  |  drip sent %s  |  own tree round %s"):format(quiet and "on" or "off",
		drip, sent, round and (Span(round) .. " ago") or "none")
end

-- The fallback's election and queue counts only. Its detailed stats contain peer names.
local function RelayFallbackLine()
	local F = ns.RelayFallback
	if type(F) ~= "table" or type(F.Stats) ~= "function" then return "fallback: not loaded" end
	local s = Try(F.Stats)
	if type(s) ~= "table" then return "fallback: unavailable" end
	local source = s.source == "list" and "list" or s.source == "rendezvous" and "rendezvous" or "unknown"
	local elected = type(s.elected) == "table" and #s.elected or 0
	local function N(value) return tonumber(value) or 0 end
	return ("fallback: source %s, candidates %d, asked %d, yes %d, no %d, no answer %d, elected %d, serving %s, held %d, dropped %d")
		:format(source, N(s.candidates), N(s.pinged), N(s.yes), N(s.no), N(s.none), elected,
			s.serving and "yes" or "no", N(s.held), N(s.holdDropped))
end

-- The census's sources: our realm group's guild reports (how many, how fresh, from which realms), and
-- each other realm group's numbers this account looked at or heard, newest first (six at most).
local function CensusLines()
	local out = {}
	local guilds = ns.rdb and ns.rdb.guilds
	local n, newest, oldest, from = 0, nil, nil, {}
	for _, g in pairs(type(guilds) == "table" and guilds or {}) do
		if type(g) == "table" then
			n = n + 1
			local t = tonumber(g.t)
			if t then
				if not newest or t > newest then newest = t end
				if not oldest or t < oldest then oldest = t end
			end
			local realm = type(g.from) == "string" and g.from or "old"
			from[realm] = (from[realm] or 0) + 1
		end
	end
	out[#out + 1] = Cap(("census: group %s: %d guild reports, newest %s, oldest %s  |  by realm %s"):format(tostring(ns.group or "?"), n,
		newest and Age(newest) or "-", oldest and Age(oldest) or "-", CountList(from)))
	-- (1.5.8) Each row's source (author, own, relay, witnessed, heard; "?" for none) and whether the
	-- "all servers" total counts it now (Data.Groups: our side's accepted rows), never who said it.
	local counted = {}
	local D = ns.Data
	local groups = type(D) == "table" and type(D.Groups) == "function" and Try(D.Groups) or nil
	for _, r in ipairs(type(groups) == "table" and type(groups.rows) == "table" and groups.rows or {}) do
		-- (Our own group's stored look: its live count stands in the total, "here".)
		if type(r) == "table" and (r.counted or r.ours) then counted[tostring(r.faction) .. "|" .. tostring(r.group)] = r.ours and "here" or true end
	end
	local SRC = { author = true, own = true, relay = true, witnessed = true, heard = true }
	local rows = {}
	for _, which in ipairs({ "groupCensus", "groupHeard" }) do
		local store = ns.db and ns.db[which]
		for key, e in pairs(type(store) == "table" and store or {}) do
			if type(e) == "table" and type(key) == "string" then
				rows[#rows + 1] = { key = key, how = which == "groupCensus" and "look" or "heard", t = tonumber(e.observed or e.t) or 0,
					people = tonumber(e.people or e.total), src = SRC[e.src] and e.src or "?",
					counts = which == "groupCensus" and counted[key] or false }
			end
		end
	end
	table.sort(rows, function(a, b) if a.t ~= b.t then return a.t > b.t end return a.key < b.key end)
	local parts = {}
	for i = 1, math.min(5, #rows) do
		local r = rows[i]
		parts[#parts + 1] = ("%s %s %s (%s) %s %s"):format(r.key, r.how, Age(r.t), r.people and tostring(r.people) or "?", r.src,
			r.counts == "here" and "here" or r.counts and "counted" or "uncounted")
	end
	if #rows > 5 then parts[#parts + 1] = "+" .. (#rows - 5) end
	out[#out + 1] = Cap("census: other groups " .. (#parts > 0 and table.concat(parts, ", ") or "none"))
	return out
end

-- The signed lists held here, by kind and age (no names: ns.PinsStatus says signed, code or none).
local function SignedLine()
	local t = type(ns.CouncilTitles) == "function" and Try(ns.CouncilTitles) or (ns.rdb and ns.rdb.councilTitles)
	local titles = "none"
	if type(t) == "table" and type(t.blob) == "string" then
		local Ch = ns.Church
		local apostles = type(Ch) == "table" and type(Ch.SignedApostles) == "function" and Try(Ch.SignedApostles) or nil
		local arbiters = type(ns.SignedArbiters) == "function" and Try(ns.SignedArbiters) or nil
		titles = ("v%s %s (apostles %s, arbiters %s)"):format(t.blob:match("^HT1~(%d+)~") or "?", t.at and Age(t.at) or "?",
			type(apostles) == "table" and tostring(#apostles) or "?", type(arbiters) == "table" and tostring(#arbiters) or "?")
	end
	local R = ns.Relay
	local rules = type(R) == "table" and type(R.Rules) == "function" and Try(R.Rules) or nil
	return ("signed: titles %s  |  relay rules rev %s  |  %s"):format(titles, type(rules) == "table" and tostring(rules.rev) or "?",
		tostring(ns.PinsStatus and Try(ns.PinsStatus) or "?"))
end

-- (1.5.8) The census's counters (Data.CensusStats: what it took, left unproven and refused since login,
-- kinds and reasons only), the relay tree's first line (whether this client is its guild's registrant),
-- and the guild rows this client could count: no player's or relay's name.
local function CensusMoreLines()
	local out, D = {}, ns.Data
	local st = type(D) == "table" and type(D.CensusStats) == "function" and Try(D.CensusStats) or nil
	out[#out + 1] = "census counters: " .. (type(st) == "table" and type(st.line) == "string" and st.line or "?")
	local T = ns.RelayTree
	local tree = type(T) == "table" and not T.missing and type(T.Stats) == "function" and Try(T.Stats) or nil
	local first = type(tree) == "table" and type(tree.lines) == "table" and tree.lines[1]
	out[#out + 1] = type(first) == "string" and first or "tree: not loaded"
	local n, newest = nil, nil
	if type(D) == "table" and type(D.GlobalDigest) == "function" then
		local ok, a, b = pcall(D.GlobalDigest)
		if ok then n, newest = tonumber(a), tonumber(b) end
	end
	local relayed, relayedNewest, keep = 0, nil, type(D) == "table" and tonumber(D.TOTAL_KEEP) or 86400
	local now = ns.Now and ns.Now() or time()
	local store = ns.rdb and ns.rdb.censusGlobal
	for _, e in pairs(type(store) == "table" and store or {}) do
		local t = type(e) == "table" and tonumber(e.observed)
		if t and now - t <= keep then
			relayed = relayed + 1
			if not relayedNewest or t > relayedNewest then relayedNewest = t end
		end
	end
	out[#out + 1] = ("census relayed: rows %d within a day, newest %s  |  countable guilds %s, newest %s"):format(relayed,
		relayedNewest and Age(relayedNewest) or "-", n and tostring(n) or "?", newest and newest > 0 and Age(newest) or "-")
	return out
end

function ns.DebugLines()
	local lines = { "debug (1.5.5):" }
	local function add(line) lines[#lines + 1] = Cap(tostring(line)) end
	add(Try(ns.InstallLine) or "install: ?")
	add(Try(ns.InstallFilesLine) or "install files: ?")
	add(Try(PiecesLine) or "pieces: ?")
	add(Try(RelayReporterLine) or "relay: ?")
	add(Try(RelayFallbackLine) or "fallback: unavailable")
	for _, line in ipairs(Try(CensusLines) or { "census: ?" }) do add(line) end
	add(Try(SignedLine) or "signed: ?")
	add("secret values left unread: " .. CountList(ns.SecretSkips and ns.SecretSkips() or nil))
	-- (1.5.8) Last, so the lines before them (signed: above all) are never the ones cut.
	for _, line in ipairs(Try(CensusMoreLines) or { "census counters: ?" }) do add(line) end
	-- Bounded in all: the lines past DEBUG_MAX are left out, said so.
	local size, out = 0, {}
	for _, line in ipairs(lines) do
		if size + #line + 1 > ns.DEBUG_MAX then out[#out + 1] = "(debug cut)" break end
		out[#out + 1] = line
		size = size + #line + 1
	end
	return out
end

function ns.StatusText()
	local lines = {}
	local function add(fmt, ...) lines[#lines + 1] = fmt:format(...) end
	local guild = GetGuildInfo("player")
	add("Olympus v%s  |  %s", ns.VERSION, ClientInfo())
	-- (1.1) The addon's language: the game's, when Olympus has lines for it (Locales.lua).
	add("language: %s", ns.LocaleReport and ns.LocaleReport() or "?")
	add("player %s  |  %s  |  guild %s  |  olympus member: %s", tostring(ns.me), tostring(ns.faction), tostring(guild), tostring(ns.IsMember()))
	-- (1.2.5.1: the Olympus Accord, Accord.lua: its version and state, never the BattleTag.)
	add("accord: %s", tostring(ns.Accord and ns.Accord.StatusLine and ns.Accord.StatusLine() or "?"))
	local realm, census = RealmLines()
	add("%s", realm)
	add("%s", census)
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
		-- (1.2.1: the sealed channel's name never: see Scrub.) (1.5.9) The guild's registrant beside its
		-- reporter (the one that registers it with its relay, so the census reaches it), each with the
		-- version its hello named. (Round 1's re-review) And the words taken on Olympus's leftover channels
		-- on Forever (Comm.Leftover: an older key's sealed channel or a later lane, still joined from an
		-- earlier session, where older clients broadcast their census), their names never.
		local function Version(v) return v and (" v" .. tostring(v)) or "" end
		add("channel %s = #%s  sealed=%s  leftover taken=%d  |  peers in guild=%d  |  reporter=%s%s (me: %s)  |  registrant=%s%s (me: %s)",
			c.sealed and "(sealed channel)" or ("'" .. tostring(c.channelName) .. "'"), tostring(c.channel), tostring(c.sealed),
			tonumber(c.leftover) or 0, c.peers,
			tostring(c.reporter), Version(c.reporterVersion), tostring(c.isReporter), tostring(c.registrant), Version(c.registrantVersion),
			tostring(c.isRegistrant))
		local here = Try(RelayHereLine) -- (1.5.9: a relay's own client alone)
		if here then add("%s", here) end
		add("sent=%d recv=%d reports=%d sendFails=%d badMsgs=%d queue=%d lastFail=%s lane=%d laneRefused=%d laneMoves=%d", c.sent, c.recv, c.reports, c.fails, c.bad, c.queue, tostring(c.lastFail), tonumber(c.lane) or 0, tonumber(c.laneRefused) or 0, tonumber(c.laneMoves) or 0)
		local types = {}
		for k, v in pairs(c.byType or {}) do types[#types + 1] = k .. "=" .. v end
		table.sort(types)
		add("received by type: %s  |  incomplete reports: %d waiting, %d dropped", #types > 0 and table.concat(types, " ") or "none", c.pending or 0, c.partial or 0)
		add("own echoes: %d  |  channel members: %s", c.echo or 0, tostring(ChannelMembers(c.channelName) or "unknown"))
		-- Who holds the channel as last seen, our seat on it, and what its owners did (Comm.lua).
		local o = c.guard
		if o then
			add("channel owner: %s (%s)  |  me: %s  |  watched: %s", tostring(o.owner or "unknown"),
				o.ownerAt and ns.Ago(o.ownerAt) or "not seen", o.role, tostring(o.watched))
			add("channel seen: %s  |  moderation=%s announce=%s", CountList(o.seen), tostring(o.moderation or "?"), tostring(o.announce or "?"))
			add("channel undo: password=%s banned=%d muted=%d  |  locked: %s", tostring(o.password), o.banned, o.muted,
				o.locked and ("%s, %d tries, next in %ds"):format(tostring(o.locked.why), o.locked.tries, o.locked.nextIn) or "no")
		end
		-- The chat channels by number: ours should come after the game's own (Comm.KeepLast).
		-- (1.2.1) Named: the game's own (zone channels, as Comm.KeepLast tells them) and ours as
		-- "Olympus"; any other is the player's own (a private channel, another addon's): "other".
		local ok, list = pcall(function() return { GetChannelList() } end)
		if ok and list and #list > 0 then
			local stride = type(list[3]) == "boolean" and 3 or 2
			local ours = ns.Comm.ChannelName and ns.Comm.ChannelName()
			local infoOf = C_ChatInfo and C_ChatInfo.GetChannelInfoFromIdentifier
			local parts = {}
			for i = 1, #list, stride do
				local name, shown = list[i + 1], "other"
				if type(name) == "string" and type(ours) == "string" and name:lower() == ours:lower() then
					shown = "Olympus"
				elseif type(name) == "string" and type(infoOf) == "function" then
					local okInfo, info = pcall(infoOf, name)
					if okInfo and type(info) == "table" and (tonumber(info.zoneChannelID) or 0) > 0 then shown = name end
				end
				parts[#parts + 1] = ("%s %s"):format(tostring(list[i]), shown)
			end
			add("chat channels: %s", table.concat(parts, ", "))
		end
		add("other channels dropped: %d  |  census asked %d (left out %d), answered %d  |  runner-up: %s  |  first channel msg: %s",
			c.otherChannel or 0, c.asked or 0, c.askSkipped or 0, c.answered or 0, tostring(c.runnerUp), tostring(c.chanArgs))
		for _, line in ipairs(NamesLines(c)) do add("%s", line) end
		for _, line in ipairs(TopologyLines(c)) do add("%s", line) end
		local ch = ns.Channels and ns.Channels.Stats()
		if ch then
			-- (moved, 1.1.1: lines not sent because the channel changed before they left, GitHub #34.)
			-- (secret, 1.5.5: chat events with a field that came as a secret value, skipped unread, Core.lua.)
			add("chat: sent=%d shown=%d hidden=%d lane=%d moved=%d muted=%s drops bad=%d dup=%d rate=%d flood=%d forged=%d unverified=%d rank=%d secret=%d",
				ch.sent, ch.shown, ch.hidden, c.chatQueue or 0, ch.moved or 0, #ch.muted > 0 and table.concat(ch.muted, ",") or "none",
				ch.bad, ch.dup, ch.rate, ch.flood, ch.forged, ch.unverified, (ch.rank or 0) + (ch.otherRank or 0), tonumber(ns.secretChatSkipped) or 0)
			if ns.Channels.WindowStatus then
				-- (1.5.5: a player's /oly bug said "gone: main window for now" for all three channels, and
				-- nothing said which chat windows his game had open: they are listed now, by name.)
				local open = {}
				if ns.Channels.OpenWindows then
					for _, w in ipairs(ns.Channels.OpenWindows()) do open[#open + 1] = '"' .. tostring(w.name):gsub("|", "||") .. '"' end
				end
				add("chat windows: %s  |  open: %s", ns.Channels.WindowStatus(), #open > 0 and table.concat(open, ", ") or "the main one alone")
			end
			-- (1.1) The pinned line this client holds: whose, of what rank, and how long it has left.
			if ns.Channels.PinStatus then add("pinned line: %s", ns.Channels.PinStatus()) end
		end
		-- What leaves this client about where the player is, and who reads the channel (0.9.1). (1.5.9: by
		-- the key, as the privacy questions say it, Comm.Audience: on Forever the channel joined is the
		-- public one whatever the key, and a key holder's chat lines go by the relay alone, ChatHall.On.)
		-- (1.5.9's review: on Forever, with a key, the public channel, the key's one effect said beside it.)
		add("privacy: zone and layer %s  |  channel %s  |  chat warning accepted: %s",
			ns.Layers and ns.Layers.SharingState and ns.Layers.SharingState() or "?", c.sealed and "sealed (key holders)"
				or (c.keyHeld and "public (anyone), key held: typed chat lines by the relay alone" or "public (anyone)"),
			ch and ch.warned and #ch.warned > 0 and table.concat(ch.warned, ",") or "none")
		if ns.Treasury and ns.Treasury.RealKeeper and ns.Treasury.RealKeeper() then
			local v = ns.Treasury.Consent()
			local b = ns.Treasury.BookOf and ns.Treasury.BookOf(ns.me)
			add("treasury keeper: book and bank %s (/oly treasurer on|off), book of %s opened at %s copper",
				v == true and "shared" or (v == false and "private" or "not chosen (private)"), tostring(b and b.epoch or "-"), tostring(b and b.opening or "-"))
		end
		if ns.faction == "Horde" then
			add("Horde King: %s, realm %s", tostring(ns.KingCharacter and ns.KingCharacter() or "none here"), tostring(ns.KingRealm and ns.KingRealm() or "?"))
		end
		-- (1.3.4) Where the King, the Treasurer and the author come from here: the signed list or the code's pins.
		if ns.PinsStatus then add("identities: %s", ns.PinsStatus()) end
		-- (1.1, Fern's #11: each off until answered, on the first-open page or its command.)
		local ri = ns.db.royalInspection
		add("royal inspection: %s (/oly inspection on|off)", ri == true and "taking part when sampled" or (ri == false and "not taking part" or "not chosen (not taking part)"))
		-- 1.1 (Fern's #29): an officer's findings shared with his guild's officers.
		if ns.Inspect.MayShare then
			add("patrol share: %s (/oly patrolshare on|off), %d of our officers' findings held", not ns.Inspect.Sharing() and "off"
				or (ns.Inspect.MayShare() and "on" or "on, not an officer"), ns.Inspect.SharedCount())
		end
		-- 1.1: the switch for all alert sounds, and the kinds silenced on their own.
		add("alerts: %s", ns.AlertStatus and ns.AlertStatus() or "?")
		add("author's roll call: %s (/oly rollcall on|off)", ns.Workshop and ns.Workshop.AnswerState and ns.Workshop.AnswerState() or "?")
		-- (1.1) The author's released version as his presence named it, and whether this client is behind it.
		add("%s", ns.Workshop and ns.Workshop.VersionLine and ns.Workshop.VersionLine() or "author's released version: ?")
		-- (1.1.2) The right-click menus' lines, and this session's version checks and asks.
		add("player menus: %s  |  versions: %s", ns.PlayerMenu and ns.PlayerMenu.StatusLine and ns.PlayerMenu.StatusLine() or "not loaded",
			ns.Versions and ns.Versions.StatusLine and ns.Versions.StatusLine() or "not loaded")
		add("olympus chats: %s (/oly chat on|off)  |  layer help: %s", ns.Channels and ns.Channels.ChatState and ns.Channels.ChatState() or "?",
			ns.db.layerHelp == true and "on" or (ns.db.layerHelp == false and "off" or "not chosen (off)"))
		-- (1.1: block terms, #31; the log of acts, #12: counts only, never the words or the entries.)
		local F = ns.Filter
		if F and not F.missing and F.Mine then
			add("block terms: %d yours, %d shared (%s)%s  |  acts log: %d entries", #F.Mine(), #F.SharedTerms(), F.SharedOn() and "used" or "ignored",
				F.CanEdit() and ", you edit the shared list" or "", ns.Chronicle and ns.Chronicle.Entries and #ns.Chronicle.Entries() or 0)
		end
		-- Olympus Link (0.9.10): the key's id and tier only, never the key. (1.4.0: its own addon,
		-- Olympus_Link; the loader says when it is not installed.)
		add("discord link: %s", ns.LinkLoader and ns.LinkLoader.StatusLine and ns.LinkLoader.StatusLine() or "not loaded")
		-- (1.5.4) The relay rules in force (Relay.lua): their revision, the deadline, the versions admitted.
		add("relay: %s", ns.Relay and ns.Relay.RulesLine and ns.Relay.RulesLine() or "not loaded")
		-- The Board (1.1): what this client holds and sends (the ch:G1, ch:G0, ch:GQ counts above).
		add("board: %s", ns.Board and ns.Board.StatusLine and ns.Board.StatusLine() or "not loaded")
		-- (1.4.0: the Board's group listings, counts only: ch:GL, ch:GM... above.)
		local G = ns.Groups
		add("board groups: %s", G and not G.missing and G.StatusLine and G.StatusLine() or "not loaded")
		add("the King's week: %s", ns.Week and ns.Week.StatusLine and ns.Week.StatusLine() or "not loaded")
	end
	local n = 0
	for _ in pairs(ns.rdb.guilds) do n = n + 1 end
	-- (1.2.1: the census keeps Data.MAX_GUILDS reports at most; how many went this session to make room.)
	add("cached guilds=%d (at most %s, %s let go)  |  map=%s  |  errors=%d  |  sessions=%d", n, tostring(ns.Data and ns.Data.MAX_GUILDS or "?"),
		tostring(ns.Data and ns.Data.Trimmed and ns.Data.Trimmed() or 0), tostring(ns.db.showMap), #ns.db.errors, ns.db.sessions or 0)
	add("map lib: %s  |  zones indexed=%d  |  tabs: %s", tostring(ns.Map and ns.Map.libOk), ns.Zones and ns.Zones.Count() or 0,
		ns.UI and ns.UI.tabTemplate and (ns.UI.tabTemplate .. " (" .. tostring(ns.UI.tabStyle) .. " spacing), window "
			.. tostring(ns.UI.WindowStyle and ns.UI.WindowStyle())) or "not built")
	-- (1.1) Zone names from the roster no map id matched, names only: a zone a new client added
	-- somewhere the index does not reach yet, shown as text in the census and left off the map.
	add("zones without a map id: %s", ns.Zones and ns.Zones.UnmappedLine and ns.Zones.UnmappedLine() or "?")
	-- Old Guild tab or new Communities window: which ones exist and got the Olympus button.
	add("guild UI: %s", ns.GuildFrameHook and ns.GuildFrameHook.StatusLine() or "not loaded")
	local seen = 0
	for _ in pairs(ns.rdb.seen or {}) do seen = seen + 1 end
	add("who: %s  |  guilds seen=%d", ns.Who and ns.Who.StatusLine() or "not loaded", seen)
	add("hop: %s", ns.Hop and ns.Hop.StatusLine and ns.Hop.StatusLine() or "not loaded")
	add("relay: %s", RelayLine()) -- (the review of the 1.5.4 candidate: RelayLine above)
	-- (1.0.0) The King as this client knows him: why his layer can or can't be asked for.
	add("king: %s", ns.Hop and ns.Hop.KingStatusLine and ns.Hop.KingStatusLine() or "not loaded")
	-- (1.0.0) The King's Steward as the signed titles list names him here, and the Hands held.
	add("steward: %s", ns.King and ns.King.StewardStatusLine and ns.King.StewardStatusLine() or "not loaded")
	-- (1.1) Net-off words this client holds (Moderation.lua).
	add("net-off: %s", ns.Moderation and ns.Moderation.StatusLine and ns.Moderation.StatusLine() or "not loaded")
	add("alt links: %s", ns.Alts and ns.Alts.StatusLine and ns.Alts.StatusLine() or "not loaded")
	add("realm key: %s", ns.Keys and ns.Keys.StatusLine and ns.Keys.StatusLine() or "not loaded")
	-- 1.1: the guilds the author's signed list makes Olympus guilds (our faction's), and whether ours is one.
	if ns.ApprovedGuilds then
		local list, guild = ns.ApprovedGuilds(), GetGuildInfo("player")
		add("approved guilds: %s%s", #list > 0 and table.concat(list, ", ") or "none", (guild and ns.IsApprovedGuild(guild))
			and ((ns.NamedOlympus(guild) and not ns.IsRemovedGuild(guild)) and "  |  ours is on it" or "  |  ours is Olympus by the list alone") or "")
	end
	add("borders: %s", ns.Borders and ns.Borders.StatusLine and ns.Borders.StatusLine() or "not loaded")
	add("nameplates: %s", ns.Nameplates and ns.Nameplates.StatusLine and ns.Nameplates.StatusLine() or "not loaded")
	add("chat marks: %s", ns.Borders and ns.Borders.ChatStatusLine and ns.Borders.ChatStatusLine() or "not loaded")
	-- 1.1.5: the guild masters' centurions and correspondents (Nominees.lua): his own, and the lists held.
	add("nominees: %s", ns.Nominees and ns.Nominees.StatusLine and ns.Nominees.StatusLine() or "not loaded")
	-- 1.2.4: the author's signed leadership list (Authority.lua), which other guilds' leaders need in the role rooms.
	add("signed leadership: %s", ns.Authority and type(ns.Authority.StatusLine) == "function" and ns.Authority.StatusLine() or "not loaded")
	add("letters: %s", ns.Letters and ns.Letters.StatusLine and ns.Letters.StatusLine() or "not loaded")
	-- The gamepad UI and what the game refused us this session; what its code reads, as now.
	local refused = type(ns.db.actionsBlocked) == "table" and ns.db.actionsBlocked or {}
	-- (1.2.1: the last one's version too: one kept from an older version is not this one's.)
	add("gamepad UI: %s  |  blocked this session: %d  |  blocked calls kept: %d%s", ns.GamepadUI() and "on" or "off", blocked, #refused,
		#refused > 0 and (" (last: %s, v%s)"):format(tostring(refused[#refused].func), tostring(refused[#refused].version or "?")) or "")
	-- (1.1.5) The gamepad gate (Gamepad.lua): the switches this session and what stays until a /reload.
	add("gamepad gate: %s", ns.Gate and type(ns.Gate.StatusLine) == "function" and ns.Gate.StatusLine() or "not loaded until the game restarts")
	if ns.GamepadUI() or blocked > 0 then
		local ok, line = pcall(ns.TaintProbe)
		add("%s", ok and line or ("taint: probe failed: " .. tostring(line)))
	end
	-- 1.2: other files' lines (the Blood Arena's, ArenaNet.lua), each fn(lines) adding its own; one
	-- that fails leaves a line saying so. /oly bug carries them too (ns.BuildBugReport reads this).
	for _, fn in ipairs(ns.statusLines) do
		local n = #lines
		local ok, err = pcall(fn, lines)
		if not ok then
			for i = #lines, n + 1, -1 do lines[i] = nil end
			add("status line failed: %s", tostring(err))
		end
	end
	return Scrub(table.concat(lines, "\n"))
end

function ns.RecentDiagnostics(kind)
	local db = ns.db or {}
	local out = {}
	if kind == "errors" then
		local errors = db.errors or {}
		for i = #errors, math.max(1, #errors - 11), -1 do
			local e = errors[i]
			out[#out + 1] = Cap(("[%dx] %s (%s .. %s, v%s): %s"):format(
				e.count or 1, tostring(e.where), tostring(e.first), tostring(e.last), tostring(e.version), tostring(e.msg)))
		end
	else
		local log = db.log or {}
		for i = #log, 1, -1 do
			local line = log[i]
			if type(line) == "string" then
				local lower = line:lower()
				if kind ~= "census" or lower:find("census", 1, true) or lower:find("relay", 1, true) or lower:find("lane", 1, true) then
					out[#out + 1] = Cap(line)
					if #out == 40 then break end
				end
			end
		end
	end
	return Scrub(#out > 0 and table.concat(out, "\n") or ns.L.RECENT_EMPTY)
end

function ns.BuildBugReport()
	local out = { "```" }
	-- (1.5.5) An install that does not fit this game, first: it explains every count below.
	local okI, install = pcall(ns.Install)
	if okI and type(install) == "table" and #install.problems > 0 then
		out[#out + 1] = ("INSTALL PROBLEM: %s (Olympus %s, client %s toc %s; the debug section's install line says more)"):format(
			table.concat(install.problems, ", "), tostring(install.version), tostring(install.client), tostring(install.toc))
	end
	-- The calls the game refused Olympus ("blocked from an action"), newest first. First in the
	-- report: a report sent in game stops at Workshop.BUG_MAX bytes, and this is the part that
	-- names what to fix.
	local refused = type(ns.db.actionsBlocked) == "table" and ns.db.actionsBlocked or {}
	-- (1.2.1: the heading only over this version's: an older version's calls alone, kept in the
	-- saved variables, made it head an empty list, as if this version had been blocked.)
	local current = false
	for _, b in ipairs(refused) do if b.version == ns.VERSION then current = true break end end
	if current then
		out[#out + 1] = "Blocked by the game:"
		-- This version's newest two, their stacks cut to 8 lines: the errors below must still fit.
		local shown = 0
		for i = #refused, 1, -1 do
			local b = refused[i]
			if shown >= 2 then break end
			if b.version == ns.VERSION then
				shown = shown + 1
				out[#out + 1] = ("[%dx] %s %s  (%s .. %s, v%s, %s)"):format(b.count or 1, tostring(b.event), tostring(b.func),
					tostring(b.first), tostring(b.last), tostring(b.version), b.gamepad and "gamepad UI" or "mouse and keyboard")
				if b.taint then out[#out + 1] = "  " .. b.taint end
				local n = 0
				for line in tostring(b.stack or ""):gmatch("[^\n]+") do
					n = n + 1
					if n > 8 then break end
					out[#out + 1] = "    " .. line
				end
			end
		end
		out[#out + 1] = ""
	end
	out[#out + 1] = ns.StatusText()
	out[#out + 1] = ""
	-- (1.5.5) The debug section, bounded (ns.DebugLines), after the status: a report sent in game
	-- stops at Workshop.BUG_MAX bytes, and the status it carried before 1.5.5 still comes first,
	-- whole (the section's DEBUG_MAX bytes before it cut as much of the status off).
	local okD, debug = pcall(ns.DebugLines)
	if okD and type(debug) == "table" then
		for _, line in ipairs(debug) do out[#out + 1] = line end
	else
		out[#out + 1] = "debug (1.5.5): failed: " .. tostring(debug)
	end
	out[#out + 1] = ""
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
	-- 1.5.8: the recruiting section (RecruitHandoff.lua's event log), last: the window shows it whole.
	local H = ns.Recruit and ns.Recruit.Handoff
	if H and H.BugLines then
		local okR, recruit = pcall(H.BugLines, 40)
		out[#out + 1] = ""
		if okR and type(recruit) == "table" then
			for _, line in ipairs(recruit) do out[#out + 1] = line end
		else
			out[#out + 1] = "Recruiting: failed: " .. tostring(recruit)
		end
	end
	out[#out + 1] = "```"
	-- (1.2.1) The log and the errors name the sealed channel too: scrubbed with the status.
	return Scrub(table.concat(out, "\n"))
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
