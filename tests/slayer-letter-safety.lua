-- Exercise HonorsNet's actual receipt queue, window and OnHide callback. The scene supplies
-- player state and an isolated saved profile; Wanted supplies the real receipt key and words.
-- These reproduce lifecycle gaps, not the cause of a particular player's report.
local ns, test, eq, extra = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]slayer%-letter%-safety%.lua$")) or "./"
local WithUI = assert(extra.WithUI)

local function Scene(fn)
	WithUI(function()
		local saved = { combat = InCombatLockdown, instance = IsInInstance, dnd = UnitIsDND, secret = issecretvalue,
			always = ns.db.alertsAlways, popups = {} }
		for k, v in pairs(StaticPopupDialogs) do saved.popups[k] = v end
		local ok, err = pcall(function()
			local w = { combat = false, inside = false, busy = false, events = {}, timers = {}, printed = {}, tabs = {}, clock = 100000 }
			InCombatLockdown = function() return w.combat end
			IsInInstance = function() return w.inside, w.inside and "arena" or "none" end
			UnitIsDND = function() return w.busy end
			ns.db.alertsAlways = nil
			ns.ResetHeld()
			GamepadStyle(false)
			local profile = { letters = {}, lettered = {} }
			local c = setmetatable({ db = { honorLetters = 1 }, rdb = {}, RealmPages = {}, Borders = { missing = true },
				King = {}, IsKingCharacter = function() return false end, On = function() end,
				Comm = { Handle = function() end }, Consent = {}, Letters = {},
				Arena = { B36 = tostring, N = tonumber, Now = function() return w.clock end,
					Persists = function() return true end, Handle = function(_, callback) return callback end, Action = function() end },
				ArenaProfile = { Mine = function() return profile end }, Honors = { ArtOf = function() end },
				Print = function(text) w.printed[#w.printed + 1] = text end,
				After = function(seconds, label, callback) w.timers[#w.timers + 1] = { seconds = seconds, label = label, fn = callback } end,
				RegisterEvent = function(event, callback)
					w.events[event] = w.events[event] or {}
					w.events[event][#w.events[event] + 1] = callback
				end }, { __index = ns })
			c.L = setmetatable({}, { __index = ns.L })
			assert(loadfile(ROOT .. "Olympus/Locales/ArenaFightsText.lua"))("Olympus", c)
			c.UI = setmetatable({ IsShown = function() return w.window == true end,
				SelectTab = function(key) w.tabs[#w.tabs + 1] = key end }, { __index = ns.UI })
			assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
			assert(loadfile(ROOT .. "Olympus/HonorsNet.lua"))("Olympus", c)
			w.H, w.profile, w.client = c.HonorsNet, profile, c
			function w.Fire(event)
				for _, callback in ipairs(w.events[event] or {}) do callback() end
			end
			function w.Key(digest)
				return assert(c.Wanted.Bounty.LetterKey({ digest = digest or "00000000000a1b2c", points = 210, level = 60, hl = 60 },
					{ victims = { {}, {} }, bounty = 90 }, "Grimtooth Gorefang-Realm"))
			end
			function w.Shown()
				local f = w.H.LetterFrame()
				return f ~= nil and f:IsShown() == true
			end
			fn(w)
		end)
		InCombatLockdown, IsInInstance, UnitIsDND, issecretvalue, ns.db.alertsAlways =
			saved.combat, saved.instance, saved.dnd, saved.secret, saved.always
		for k in pairs(StaticPopupDialogs) do if not saved.popups[k] then StaticPopupDialogs[k] = nil end end
		for k, v in pairs(saved.popups) do StaticPopupDialogs[k] = v end
		ns.ResetHeld()
		GamepadStyle(nil)
		if not ok then error(err, 0) end
	end)
end

local function Unread(w, key, count)
	eq(#w.H.QueuedLetters(), count or 1, "the pending queue is preserved")
	eq(#w.profile.letters, count or 1, "the saved receipts are preserved")
	for _, record in ipairs(w.profile.letters) do eq(record.read, nil, "parking is not reading: " .. record.key) end
	eq(w.H.QueuedLetters()[1].key, key, "the oldest receipt is still first")
	eq(w.profile.lettered[key], nil, "no per-kill honour mark is created")
end

test("slayer letter safety: a visible receipt parks on combat without answering OnHide and resumes once after combat", function()
	Scene(function(w)
		local H, key = w.H, w.Key()
		H.QueueLetter(key, nil, true)
		local f = assert(H.LetterFrame())
		eq(w.Shown(), true)
		local text = f.body:GetText()
		w.combat = true
		w.Fire("PLAYER_REGEN_DISABLED")
		eq(w.Shown(), false, "combat must park the already-visible receipt")
		Unread(w, key)
		eq(H.WindowShown(), false, "opening Olympus in combat cannot bring it back")
		w.combat = false
		w.Fire("PLAYER_REGEN_ENABLED")
		eq(w.Shown(), true); eq(f.key, key); eq(f.body:GetText(), text)
		w.Fire("PLAYER_REGEN_ENABLED")
		Unread(w, key)
		H.CloseLetter(false)
		eq(w.profile.letters[1].read, true, "the player's Later still answers it")
		eq(#H.QueuedLetters(), 0)
		w.Fire("PLAYER_REGEN_ENABLED")
		eq(w.Shown(), false, "an answered receipt never returns")
	end)
end)

for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
	test("slayer letter safety: a visible receipt parks when entering an arena via " .. event .. " and waits through combat ending there", function()
		Scene(function(w)
			local H, key = w.H, w.Key()
			H.QueueLetter(key, nil, true)
			w.inside = true
			w.Fire(event)
			eq(w.Shown(), false, "arena entry must park the already-visible receipt")
			Unread(w, key)
			w.Fire("PLAYER_REGEN_ENABLED")
			eq(H.WindowShown(), false, "a general window click cannot open the receipt in the arena")
			eq(w.Shown(), false, "between rounds still counts as an instance")
			w.inside = false
			w.Fire(event)
			eq(w.Shown(), true); eq(H.LetterFrame().key, key)
			Unread(w, key)
		end)
	end)
end

test("slayer letter safety: new and explicitly requested receipts cannot bypass an arena even with alerts always enabled", function()
	Scene(function(w)
		local H, key = w.H, w.Key()
		w.inside, ns.db.alertsAlways = true, true
		eq(ns.Quiet(), nil, "the ordinary alert preference is deliberately overridden")
		H.QueueLetter(key, nil, true)
		eq(w.Shown(), false, "show-now delivery is still deferred in an arena")
		eq(H.WindowShown(), false)
		Unread(w, key)
		w.inside = false
		w.Fire("ZONE_CHANGED_NEW_AREA")
		eq(w.Shown(), true)
		H.CloseLetter(false)
		w.inside = true
		eq(H.ShowLetter(key), false, "the profile's explicit request cannot bypass arena safety")
		eq(w.Shown(), false)
		w.inside = false
		w.Fire("PLAYER_ENTERING_WORLD")
		eq(w.Shown(), true)
		eq(H.LetterFrame().key, key)
	end)
end)

test("slayer letter safety: closing another letter inside an arena cannot promote its pending Slayer receipt", function()
	Scene(function(w)
		local H, key = w.H, w.Key()
		H.QueueLetter(H.APOLOGY_KEY, nil, true)
		H.QueueLetter(key, nil, true)
		eq(H.LetterFrame().key, H.APOLOGY_KEY)
		w.inside = true
		w.Fire("ZONE_CHANGED_NEW_AREA")
		eq(w.Shown(), true, "the unrelated manually readable family keeps its existing behavior")
		H.CloseLetter(false)
		eq(w.Shown(), false, "the next receipt must not inherit the first letter's click")
		eq(#H.QueuedLetters(), 1); eq(H.QueuedLetters()[1].key, key)
		eq(w.profile.letters[1].read, true); eq(w.profile.letters[2].read, nil)
		w.inside = false
		w.Fire("ZONE_CHANGED_NEW_AREA")
		eq(w.Shown(), true); eq(H.LetterFrame().key, key)
	end)
end)

test("slayer letter safety: multiple unread receipts keep order while the combat retry waits for Busy to end", function()
	Scene(function(w)
		local H, key = w.H, w.Key()
		local second = w.Key("00000000000a1b2d")
		H.QueueLetter(key, nil, true)
		H.QueueLetter(second, nil, true)
		w.combat = true
		w.Fire("PLAYER_REGEN_DISABLED")
		eq(w.Shown(), false)
		Unread(w, key, 2)
		eq(#w.timers, 0, "parking adds no polling loop or repeated notifications")
		w.combat, w.busy = false, true
		w.Fire("PLAYER_REGEN_ENABLED")
		w.Fire("PLAYER_REGEN_ENABLED")
		eq(w.Shown(), false, "the combat exit does not bypass Busy")
		eq(#ns.Held(), 1, "one held alert covers both receipts")
		Unread(w, key, 2)
		w.busy = false
		eq(ns.ReleaseHeld(), true)
		eq(w.Shown(), true); eq(H.LetterFrame().key, key)
		H.CloseLetter(false)
		eq(H.LetterFrame().key, second); eq(w.profile.letters[2].read, nil)
		H.CloseLetter(false)
		eq(w.profile.letters[1].read, true); eq(w.profile.letters[2].read, true)
		eq(#H.QueuedLetters(), 0)
	end)
end)

test("slayer letter safety: missing combat API still checks instances and unreadable client state waits", function()
	Scene(function(w)
		local H, key = w.H, w.Key()
		InCombatLockdown, w.inside = nil, true
		H.QueueLetter(key, nil, true)
		eq(w.Shown(), false, "an absent optional combat API does not skip the instance check")
		Unread(w, key)
		IsInInstance = function() error("instance state unavailable") end
		eq(H.WindowShown(), false, "an API error waits instead of opening or dropping the receipt")
		local secret = {}
		IsInInstance = function() return secret end
		issecretvalue = function(value) return value == secret end
		eq(H.WindowShown(), false, "a secret instance state is never compared")
		Unread(w, key)
		IsInInstance = function() return false end
		w.Fire("PLAYER_ENTERING_WORLD")
		eq(w.Shown(), true, "a later readable safe state resumes the same receipt")
	end)
end)

test("slayer letter safety: gamepad input at login and across both switches keeps a parked receipt waiting for the next window click", function()
	Scene(function(w)
		local H, key = w.H, w.Key()
		GamepadStyle(true)
		H.QueueLetter(key)
		eq(w.Shown(), false, "a gamepad login waits for a click")
		eq(H.WindowShown(), true)
		GamepadStyle(false)
		w.combat = true
		w.Fire("PLAYER_REGEN_DISABLED")
		eq(w.Shown(), false)
		GamepadStyle(true)
		w.combat = false
		w.Fire("PLAYER_REGEN_ENABLED")
		eq(w.Shown(), false, "the combat retry cannot keep an earlier click alive")
		Unread(w, key)
		eq(H.WindowShown(), true, "the next actual click opens it")
		w.inside = true
		w.Fire("PLAYER_ENTERING_WORLD")
		eq(w.Shown(), false)
		w.inside = false
		w.Fire("PLAYER_ENTERING_WORLD")
		eq(w.Shown(), false, "leaving an arena does not seize gamepad focus")
		GamepadStyle(false)
		w.Fire("ZONE_CHANGED_NEW_AREA")
		eq(w.Shown(), true, "mouse retry can display the pending receipt")
		H.CloseLetter(true)
		eq(#w.tabs, 1); eq(w.tabs[1], "wanted", "Slayers still opens the Wanted tab")
	end)
end)
