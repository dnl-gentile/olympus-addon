local ADDON, ns = ...

-- A session-only shortcut. The player's saved bindings and other addons' overrides stay
-- theirs: Y is borrowed only while both the base binding and the override slot are empty.
local Key = {}
ns.MainKey = Key
local BUTTON, ACTION = "OlympusMainKey", "CLICK OlympusMainKey:LeftButton"
local button, held, pending, syncing

local function Combat()
	if type(InCombatLockdown) ~= "function" then return true end
	local ok, locked = pcall(InCombatLockdown)
	return not ok or locked ~= false
end

function Key.Enabled() return type(ns.db) == "table" and ns.db.mainKeyOff ~= true end

local function Available() -- gp:main-key
	if not ns.Gate.Allowed("main-key") then return false end
	if type(GetBindingAction) ~= "function" then return false end
	for _, overrides in ipairs({ false, true }) do
		local ok, action = pcall(GetBindingAction, "Y", overrides)
		if not ok or (type(issecretvalue) == "function" and issecretvalue(action))
			or type(action) ~= "string" or (action ~= "" and not (overrides and held and action == ACTION)) then return false end
	end
	return true
end

local function Release() -- gp:main-key!undo
	if not held then pending = nil; return true end
	if Combat() then pending = true; return false end
	if type(ClearOverrideBindings) ~= "function" then return false end
	local ok = pcall(ClearOverrideBindings, button)
	if ok then held, pending = nil, nil end
	return ok
end

function Key.Press(_, _, down) -- gp:main-key
	if not ns.Gate.Allowed("main-key") then return end
	if down == false or not Key.Enabled() or not ns.IsMember() or not Available() then return end
	if ns.UI and ns.UI.Toggle then ns.UI.Toggle() end
end

function Key.Refresh() -- gp:main-key
	if not ns.Gate.Allowed("main-key") then return end
	if syncing then return end
	if Combat() then pending = true; return end
	syncing = true
	if not Key.Enabled() or not ns.IsMember() or not Available() then
		Release()
	elseif not held and type(SetOverrideBindingClick) == "function" then
		if not button then
			button = CreateFrame("Button", BUTTON, UIParent)
			button:RegisterForClicks("AnyDown")
			button:SetScript("OnClick", Key.Press)
		end
		held = pcall(SetOverrideBindingClick, button, false, "Y", BUTTON, "LeftButton") or nil
	end
	syncing, pending = nil, nil
end

function Key.SetEnabled(on)
	if type(ns.db) ~= "table" or type(on) ~= "boolean" then return false end
	ns.db.mainKeyOff = not on or nil
	if ns.Gate.Allowed("main-key") then Key.Refresh() else Release() end
	return true
end

function Key.Slash(text)
	text = tostring(text or ""):lower()
	if text == "on" or text == "off" then Key.SetEnabled(text == "on") end
	ns.Print(ns.L.MAINKEY_STATUS:format(Key.Enabled() and ns.L.MAINKEY_ON or ns.L.MAINKEY_OFF))
end

function Key.Held() return held == true end
ns.Gate.Hooks("main-key", { now = true, install = Key.Refresh, park = Release })
ns.On("LOGIN", function() ns.Gate.Install("main-key") end)
ns.RegisterEvent("UPDATE_BINDINGS", Key.Refresh)
ns.RegisterEvent("PLAYER_GUILD_UPDATE", Key.Refresh)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if pending then
		if ns.Gate.Allowed("main-key") then Key.Refresh() else Release() end
	end
end)
