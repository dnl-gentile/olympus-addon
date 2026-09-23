local ADDON, ns = ...
local L = ns.L

ns.NAME = "Olympus"
ns.VERSION = "0.7.3"
ns.PREFIX = "OLYMPUS"        -- addon message prefix (max 16 chars)
ns.CHANNEL = "OlympusNet"    -- hidden chat channel shared by every Olympus guild
ns.ICON = "Interface\\AddOns\\Olympus\\media\\logo64"
ns.LOGO = "Interface\\AddOns\\Olympus\\media\\logo128"
ns.EMBLEM = "Interface\\AddOns\\Olympus\\media\\emblem128"
ns.COLOR = "ffe6c35c"

local DEFAULTS = {
	showMap = true,
	minimapAngle = 200,
	hideMinimap = false,
	debug = false,
	demo = false,          -- live data by default; /oly demo shows made-up data
	officerRank = 1,       -- rank index 1 (right below guild master) and above count as officers
	warnDays = 3,          -- leaders/officers offline this many days are flagged
	sharePosition = false, -- guildmate dots are disabled: positions are not live enough
	showMates = false,
	showDecrees = true,    -- show decree markers on the map
	sound = true,          -- alert sounds (throttled)
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

function ns.Now() return time() end

function ns.Print(msg)
	print("|c" .. ns.COLOR .. "Olympus:|r " .. tostring(msg))
end

function ns.FormatNumber(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local sign, digits = s:match("^(%-?)(%d+)$")
	if not digits then return s end
	local out = digits:reverse():gsub("(%d%d%d)", "%1" .. L.THOUSANDS):reverse()
	if out:sub(1, #L.THOUSANDS) == L.THOUSANDS then out = out:sub(#L.THOUSANDS + 1) end
	return sign .. out
end

function ns.Ago(t)
	if not t or t == 0 then return L.NEVER end
	local d = math.max(0, ns.Now() - t)
	if d < 60 then return L.AGO_SEC:format(d) end
	if d < 3600 then return L.AGO_MIN:format(math.floor(d / 60)) end
	return L.AGO_HOUR:format(math.floor(d / 3600))
end

function ns.ShortName(name)
	if not name then return nil end
	return (name:gsub("%-.*$", ""))
end

function ns.PlayerName()
	local name, realm = UnitFullName("player")
	if not realm or realm == "" then realm = GetNormalizedRealmName and GetNormalizedRealmName() or "" end
	if not name then return "?" end
	if realm and realm ~= "" then return name .. "-" .. realm end
	return name
end

-- HereBeDragons-Pins, only if it loaded completely (a half-loaded library means no map
-- features instead of an error on every refresh).
function ns.Pins()
	local pins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
	if pins and pins.AddWorldMapIconMap and pins.RemoveAllWorldMapIcons and pins.AddMinimapIconMap then return pins end
	return nil
end

-- Round logo button with the exact geometry of minimap buttons (LibDBIcon layout at 31px,
-- scaled to the requested size): gold tracking ring, dark disc, round logo.
function ns.MakeRoundButton(name, parent, size)
	local k = size / 31
	local b = CreateFrame("Button", name, parent)
	b:SetSize(size, size)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20 * k, 20 * k)
	bg:SetPoint("TOPLEFT", 7 * k, -5 * k)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ns.LOGO)
	icon:SetSize(17 * k, 17 * k)
	icon:SetPoint("TOPLEFT", 7 * k, -6 * k)
	if icon.SetMask then pcall(icon.SetMask, icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
	local ring = b:CreateTexture(nil, "OVERLAY")
	ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	ring:SetSize(53 * k, 53 * k)
	ring:SetPoint("TOPLEFT")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	b.icon = icon
	return b
end

-- One alert sound at most every 15 seconds, whatever triggers it.
local lastSound = 0
function ns.PlayAlert(kind)
	if not (ns.db and ns.db.sound) or not PlaySound or not SOUNDKIT then return end
	local now = GetTime()
	if now - lastSound < 15 then return end
	lastSound = now
	local id = kind == "soft" and (SOUNDKIT.READY_CHECK or SOUNDKIT.RAID_WARNING) or SOUNDKIT.RAID_WARNING
	if id then pcall(PlaySound, id) end
end

-- The Crown: guild masters of any Olympus guild, and the officers of the main "Olympus" guild.
function ns.IsCrownRank(guild, rankIndex)
	if not guild or not rankIndex then return false end
	if rankIndex == 0 then return true end
	return guild:lower() == "olympus" and rankIndex <= ((ns.db and ns.db.officerRank) or 1)
end

function ns.IsCrown()
	local guild, _, rankIndex = GetGuildInfo("player")
	return ns.IsFederation(guild) and ns.IsCrownRank(guild, rankIndex)
end

-- Fixed on purpose: only guilds with "Olympus" in their name belong to the realm.
local REALM_WORD = "olympus"
function ns.IsFederation(guild)
	if not guild or guild == "" then return false end
	return guild:lower():find(REALM_WORD, 1, true) ~= nil
end

-- The addon only works for members of an Olympus guild (demo data excepted).
function ns.IsMember()
	return IsInGuild() and ns.IsFederation(GetGuildInfo("player"))
end

---------------------------------------------------------------------------
-- Log (ring buffer in SavedVariables, readable from WTF/.../SavedVariables/Olympus.lua)
---------------------------------------------------------------------------

function ns.Log(fmt, ...)
	local msg
	if select("#", ...) > 0 then
		local ok, res = pcall(string.format, fmt, ...)
		msg = ok and res or tostring(fmt)
	else
		msg = tostring(fmt)
	end
	local db = ns.db
	if not db then return end
	local log = db.log
	log[#log + 1] = date("%m-%d %H:%M:%S ") .. msg
	while #log > 400 do table.remove(log, 1) end
	if db.debug then ns.Print("|cff999999" .. msg .. "|r") end
end

---------------------------------------------------------------------------
-- Internal callbacks and WoW events. Every handler runs protected so one bug
-- never breaks the rest of the addon; errors go to ns.CaptureError (Diagnostics.lua).
---------------------------------------------------------------------------

function ns.SafeCall(where, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and ns.CaptureError then ns.CaptureError(where, err) end
	return ok
end

local listeners = {}
function ns.On(name, fn)
	listeners[name] = listeners[name] or {}
	table.insert(listeners[name], fn)
end
function ns.Fire(name, ...)
	local l = listeners[name]
	if not l then return end
	for i = 1, #l do ns.SafeCall("callback " .. name, l[i], ...) end
end

local eventFrame = CreateFrame("Frame")
local handlers = {}
function ns.RegisterEvent(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		eventFrame:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end
eventFrame:SetScript("OnEvent", function(_, event, ...)
	local h = handlers[event]
	if not h then return end
	for i = 1, #h do ns.SafeCall("event " .. event, h[i], ...) end
end)

-- Timers that also run protected.
function ns.After(seconds, where, fn)
	C_Timer.After(seconds, function() ns.SafeCall(where, fn) end)
end
function ns.Every(seconds, where, fn)
	return C_Timer.NewTicker(seconds, function() ns.SafeCall(where, fn) end)
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------

ns.RegisterEvent("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	OlympusDB = OlympusDB or {}
	local db = OlympusDB
	for k, v in pairs(DEFAULTS) do
		if db[k] == nil then db[k] = v end
	end
	db.guilds = db.guilds or {}
	db.blocked = db.blocked or {}
	db.pattern = nil
	db.log = db.log or {}
	db.errors = db.errors or {}
	db.sessions = (db.sessions or 0) + 1
	-- v0.5: guildmate dots are retired, switch them off for existing installs too.
	if (db.configVersion or 0) < 2 then
		db.showMates, db.sharePosition = false, false
		db.configVersion = 2
	end
	ns.db = db
	ns.Log("---- session %d, v%s ----", db.sessions, ns.VERSION)
	ns.Fire("INIT")
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
	ns.me = ns.PlayerName()
	ns.Log("login as %s", ns.me)
	ns.Fire("LOGIN")
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function Help()
	ns.Print("v" .. ns.VERSION .. " commands:")
	print("  /oly - open/close the window")
	print("  /oly tabard - Heraldry Inspection tab")
	print("  /oly sound - turn alert sounds on/off")
	print("  /oly patrol - start/stop inspecting nearby Olympus members")
	print("  /oly mark [reason] - mark your target")
	print("  /oly map - show/hide zone counts on the world map")
	print("  /oly realm - the Realm tree (leaders, officers, ranks)")
	print("  /oly layers - layers & decrees")
	print("  /oly arms [text] | /oly muster [text] - decree (officers; 'test' = local preview)")
	print("  /oly mates - show/hide guildmates on map and minimap")
	print("  /oly share - share/stop sharing your position with your guild")
	print("  /oly officer <n> - ranks 1..n count as officers")
	print("  /oly demo - toggle demo data")
	print("  /oly bug - copy a bug report (errors + diagnostics)")
	print("  /oly status - print diagnostics in chat")
	print("  /oly key <secret> - officers: seal the Olympus channel with a shared secret")
	print("  /oly block <name> - ignore everything a player sends")
	print("  /oly layer - show the layer id of your target (test)")
	print("  /oly minimap - show/hide the minimap button")
	print("  /oly debug - verbose log in chat")
	print("  /oly reset - forget all cached guild reports")
end

SLASH_OLYMPUS1 = "/olympus"
SLASH_OLYMPUS2 = "/oly"
SlashCmdList.OLYMPUS = function(input)
	ns.SafeCall("slash " .. tostring(input), function()
		local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
		cmd = (cmd or ""):lower()
		if cmd == "" then
			ns.UI.Toggle()
		elseif cmd == "inspect" or cmd == "tabard" or cmd == "heraldry" then
			ns.UI.SelectTab("heraldry")
		elseif cmd == "sound" then
			ns.db.sound = not ns.db.sound
			ns.Print("sound = " .. tostring(ns.db.sound))
		elseif cmd == "patrol" then
			ns.Inspect.SetPatrol(not ns.Inspect.IsPatrolling())
		elseif cmd == "mark" then
			ns.Inspect.MarkTarget(rest)
		elseif cmd == "map" then
			ns.Map.SetEnabled(not ns.db.showMap)
		elseif cmd == "realm" or cmd == "tree" then
			ns.UI.SelectTab("realm")
		elseif cmd == "layers" or cmd == "decrees" then
			ns.UI.SelectTab("decrees")
		elseif cmd == "arms" or cmd == "muster" then
			local kind = cmd == "arms" and "ARMS" or "MUSTER"
			if rest == "test" or not ns.Roster.IsOfficer() then ns.Decree.Preview(kind) else ns.Decree.Send(kind, rest) end
		elseif cmd == "mates" then
			ns.Positions.SetEnabled(not ns.db.showMates)
		elseif cmd == "share" then
			ns.Positions.SetSharing(not ns.db.sharePosition)
		elseif cmd == "officer" then
			local n = tonumber(rest)
			if n then ns.db.officerRank = n end
			ns.Print("officerRank = " .. ns.db.officerRank .. " (0 = guild master)")
			ns.Roster.RequestScan(true)
		elseif cmd == "demo" then
			ns.Data.SetDemo(not ns.db.demo)
		elseif cmd == "bug" then
			ns.UI.ShowCopy(ns.L.REPORT_BUG, ns.BuildBugReport())
		elseif cmd == "status" then
			for line in ns.StatusText():gmatch("[^\n]+") do print("  " .. line) end
		elseif cmd == "key" then
			ns.Comm.SetRealmKey(rest)
		elseif cmd == "block" then
			if rest ~= "" then
				ns.db.blocked[ns.ShortName(rest):lower()] = true
				ns.Print("blocked " .. rest)
			end
		elseif cmd == "layer" then
			ns.PrintLayer()
		elseif cmd == "minimap" then
			ns.db.hideMinimap = not ns.db.hideMinimap
			ns.UI.UpdateMinimapButton()
		elseif cmd == "debug" then
			ns.db.debug = not ns.db.debug
			ns.Print("debug = " .. tostring(ns.db.debug))
		elseif cmd == "reset" then
			wipe(ns.db.guilds)
			ns.Fire("DATA_CHANGED")
			ns.Print("cache cleared")
		elseif cmd == "error" then
			error("test error from /oly error")   -- to check that bug capture works
		else
			Help()
		end
	end)
end
