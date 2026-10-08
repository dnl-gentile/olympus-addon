local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]main%-key%.lua$") or "./"

local function World(fn)
	local names = { "CreateFrame", "GetBindingAction", "SetOverrideBindingClick", "ClearOverrideBindings", "InCombatLockdown", "issecretvalue" }
	local saved = {}; for _, name in ipairs(names) do saved[name] = _G[name] end
	local w = { events = {}, listeners = {}, member = true, calls = {}, bindings = {}, savedBindings = {}, toggles = 0 }
	local c = setmetatable({ db = {}, On = function(event, f) w.listeners[event] = f end,
		RegisterEvent = function(event, f) w.events[event] = f end, IsMember = function() return w.member end,
		UI = { Toggle = function() w.toggles = w.toggles + 1 end } }, { __index = ns })
	c.Gate = { Allowed = function(id) eq(id, "main-key"); return not w.pad end,
		Hooks = function(id, hooks) eq(id, "main-key"); w.hooks = hooks end,
		Install = function(id) eq(id, "main-key"); if not w.pad then w.hooks.install() end end }
	InCombatLockdown = function() return w.combat == true end
	issecretvalue = function(value) return value == w.secret and w.secret ~= nil end
	GetBindingAction = function(key, overrides)
		if w.readError then error("binding unavailable") end
		if w.secret then return w.secret end
		return overrides and (w.other or (w.bindings[key] and "CLICK OlympusMainKey:LeftButton")) or w.savedBindings[key] or ""
	end
	CreateFrame = function(_, name)
		eq(name, "OlympusMainKey")
		local b = { scripts = {} }; w.button = b
		function b:RegisterForClicks(...) self.clicks = table.concat({ ... }, ",") end
		function b:SetScript(event, f) self.scripts[event] = f end
		return b
	end
	SetOverrideBindingClick = function(owner, priority, key, button, click)
		assert(not w.combat, "no protected binding change in combat")
		w.calls[#w.calls + 1] = "set"; w.bindings[key] = owner
		eq(priority, false); eq(button, "OlympusMainKey"); eq(click, "LeftButton")
		if w.reentrant then w.events.UPDATE_BINDINGS() end
	end
	ClearOverrideBindings = function(owner)
		assert(not w.combat, "no protected binding change in combat")
		w.calls[#w.calls + 1] = "clear"
		for key, value in pairs(w.bindings) do if value == owner then w.bindings[key] = nil end end
	end
	local ok, err = pcall(function()
		assert(loadfile(ROOT .. "Olympus/MainKey.lua"))("Olympus", c)
		fn(c.MainKey, w, c)
	end)
	for _, name in ipairs(names) do _G[name] = saved[name] end
	if not ok then error(err, 0) end
end

test("Main Y shortcut: a free key toggles the actual UI entry on press only, without saving a binding", function()
	World(function(k, w)
		w.listeners.LOGIN(); eq(k.Held(), true); eq(w.button.clicks, "AnyDown")
		w.button.scripts.OnClick(w.button, "LeftButton", true); eq(w.toggles, 1)
		w.button.scripts.OnClick(w.button, "LeftButton", false); eq(w.toggles, 1)
		w.button.scripts.OnClick(w.button, "LeftButton", true); eq(w.toggles, 2)
		eq(w.savedBindings.Y, nil); eq(#w.calls, 1)
		w.events.UPDATE_BINDINGS(); eq(#w.calls, 1, "unchanged state does not rebind")
	end)
end)

test("Main Y shortcut: saved actions and other addons' overrides are never replaced", function()
	for _, kind in ipairs({ "base", "override" }) do
		World(function(k, w)
			if kind == "base" then w.savedBindings.Y = "TOGGLEACHIEVEMENT" else w.other = "CLICK OtherOwner:LeftButton" end
			w.listeners.LOGIN(); eq(k.Held(), false); eq(#w.calls, 0); eq(w.button, nil)
			if kind == "base" then w.savedBindings.Y = nil else w.other = nil end
			w.events.UPDATE_BINDINGS(); eq(k.Held(), true)
			w.savedBindings.Y = "TOGGLEQUESTLOG"; w.events.UPDATE_BINDINGS()
			eq(k.Held(), false); eq(w.savedBindings.Y, "TOGGLEQUESTLOG")
			w.button.scripts.OnClick(w.button, "LeftButton", true); eq(w.toggles, 0)
		end)
	end
end)

test("Main Y shortcut: disabled or nonmembers retain their choice and cannot trigger a stale callback", function()
	World(function(k, w, c)
		k.SetEnabled(false); w.listeners.LOGIN(); eq(k.Held(), false); eq(c.db.mainKeyOff, true)
		k.SetEnabled(true); eq(k.Held(), true); eq(c.db.mainKeyOff, nil)
		local other = {}; w.bindings.F8 = other
		w.member = false; w.events.PLAYER_GUILD_UPDATE(); eq(k.Held(), false); eq(w.bindings.F8, other)
		w.button.scripts.OnClick(w.button, "LeftButton", true); eq(w.toggles, 0)
		w.member = true; w.events.PLAYER_GUILD_UPDATE(); eq(k.Held(), true)
	end)
end)

test("Main Y shortcut: gamepad login is inert and both switches release or restore only its own owner", function()
	World(function(k, w)
		w.pad = true; w.listeners.LOGIN(); eq(#w.calls, 0); eq(w.button, nil)
		w.pad = false; w.hooks.install(); eq(k.Held(), true)
		local callback = w.button.scripts.OnClick
		w.pad = true; w.hooks.park(); eq(k.Held(), false)
		callback(w.button, "LeftButton", true); w.events.UPDATE_BINDINGS(); eq(w.toggles, 0); eq(#w.calls, 2)
		w.pad = false; w.hooks.install(); eq(k.Held(), true); eq(#w.calls, 3)
	end)
end)

test("Main Y shortcut: combat defers a binding change and a disabled or gamepad stale click remains inert", function()
	World(function(k, w)
		w.combat = true; w.listeners.LOGIN(); eq(#w.calls, 0)
		w.combat = false; w.events.PLAYER_REGEN_ENABLED(); eq(k.Held(), true)
		w.combat = true; k.SetEnabled(false); eq(k.Held(), true); eq(#w.calls, 1)
		w.button.scripts.OnClick(w.button, "LeftButton", true); eq(w.toggles, 0)
		w.pad = true; w.hooks.park(); w.combat = false; w.events.PLAYER_REGEN_ENABLED()
		eq(k.Held(), false); eq(#w.calls, 2)
		w.pad = false; k.SetEnabled(true); eq(k.Held(), true)
		w.combat = true; w.savedBindings.Y = "TOGGLEQUESTLOG"; w.events.UPDATE_BINDINGS()
		w.button.scripts.OnClick(w.button, "LeftButton", true); eq(w.toggles, 0)
		w.combat = false; w.events.PLAYER_REGEN_ENABLED(); eq(k.Held(), false)
	end)
end)

test("Main Y shortcut: missing, restricted or failed binding reads fail closed; binding events may be synchronous", function()
	for _, kind in ipairs({ "missing", "error", "secret" }) do
		World(function(k, w)
			if kind == "missing" then GetBindingAction = nil elseif kind == "error" then w.readError = true else w.secret = {} end
			w.listeners.LOGIN(); eq(k.Held(), false); eq(#w.calls, 0)
		end)
	end
	World(function(k, w)
		w.reentrant = true; w.listeners.LOGIN(); eq(k.Held(), true); eq(#w.calls, 1)
	end)
end)
