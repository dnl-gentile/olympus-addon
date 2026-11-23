-- A native chat-filter installer can fail before it registers the callback. Run the real
-- Accord and Relay installers in fresh namespaces so their session state and test callbacks
-- never leak into the harness's clients. This reproduces recovery after that error, not the
-- cause of a particular player's no-player lines.
local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]quiet%-filter%-recovery%.lua$")) or "./"
local NAME = "Offline Player-Realm"

local function Scene(api, fn)
	local saved = { add = rawget(_G, "ChatFrame_AddMessageEventFilter"), util = rawget(_G, "ChatFrameUtil"),
		time = GetTime, err = rawget(_G, "ERR_CHAT_PLAYER_NOT_FOUND_S"), secret = rawget(_G, "issecretvalue") }
	local ok, err = pcall(function()
		local w = { mono = 910000, calls = 0, filters = {}, fail = true, lineID = 8000, frame = {} }
		GetTime = function() return w.mono end
		ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
		issecretvalue = nil
		local function Add(event, callback)
			w.calls = w.calls + 1
			if w.fail then error("native filter registration failed") end
			w.filters[#w.filters + 1] = { event = event, fn = callback }
			-- The native installer has no success return value.
		end
		ChatFrame_AddMessageEventFilter = api == "global" and Add or nil
		ChatFrameUtil = api == "ChatFrameUtil" and { AddMessageEventFilter = Add } or nil
		local client = setmetatable({ splitNames = true, rdb = {}, On = function() end,
			Comm = setmetatable({ Handle = function() end, RelayPieces = function() end }, { __index = ns.Comm }) }, { __index = ns })
		assert(loadfile(ROOT .. "Olympus/Accord.lua"))("Olympus", client)
		assert(loadfile(ROOT .. "Olympus/Relay.lua"))("Olympus", client)
		function w.Line(callback)
			w.lineID = w.lineID + 1
			return callback(w.frame, "CHAT_MSG_SYSTEM", ERR_CHAT_PLAYER_NOT_FOUND_S:format(client.TellName(NAME)),
				"", "", "", "", "", 0, 0, "", 0, w.lineID)
		end
		fn(w, client)
	end)
	ChatFrame_AddMessageEventFilter, ChatFrameUtil, GetTime, ERR_CHAT_PLAYER_NOT_FOUND_S, issecretvalue =
		saved.add, saved.util, saved.time, saved.err, saved.secret
	local replaced = GamepadStyle(nil)
	if not ok then error(err, 0) end
	eq(replaced, nil, "the actual gamepad gate and input-style test are preserved")
	eq(rawget(_G, "ChatFrame_AddMessageEventFilter"), saved.add, "the harness's native installer restored")
	eq(rawget(_G, "ChatFrameUtil"), saved.util, "the harness's original filter table restored")
end

for _, kind in ipairs({ "Accord", "Relay" }) do
	for _, api in ipairs({ "global", "ChatFrameUtil" }) do
		test("quiet filter recovery: " .. kind .. " retries a native error via " .. api .. ", accepts nil success and preserves gamepad and whisper rules", function()
			Scene(api, function(w, client)
				local A, R = client.Accord, client.Relay
				local Install = kind == "Accord" and function() A.Quiet(NAME) end or R.QuietLines
				local callback = kind == "Accord" and A.QuietLine or R.QuietLine
				GamepadStyle(true)
				Install()
				eq(w.calls, 0, "a gamepad login never registers a filter")
				GamepadStyle(false)
				Install()
				eq(w.calls, 1, "the native installer was tried")
				eq(#w.filters, 0, "the native error registered nothing")
				GamepadStyle(true)
				Install()
				eq(w.calls, 1, "a retry still respects the gate")
				GamepadStyle(false)
				w.fail = false
				Install()
				eq(w.calls, 2, "the next allowed attempt retries the native installer")
				eq(#w.filters, 1, "recovery registers the callback")
				eq(w.filters[1].event, "CHAT_MSG_SYSTEM")
				eq(w.filters[1].fn, callback, "the actual addon's callback")
				Install()
				eq(w.calls, 2, "nil success counts as installed: never registered twice")

				A.Tried(NAME)
				eq(w.Line(callback), true, "a fresh addon whisper's line is hidden")
				eq(w.Line(callback), false, "the player's own next whisper's line shows")
				A.Tried(NAME)
				w.mono = w.mono + A.QUIET + 1
				eq(w.Line(callback), false, "a mark expires after its ten seconds")
				local refused = A.Tried(NAME)
				A.Untried(refused, A.REFUSED_GRACE)
				w.mono = w.mono + A.REFUSED_GRACE + 1
				eq(w.Line(callback), false, "a refused whisper's mark expires after two seconds")
				A.Tried(NAME)
				local line = ERR_CHAT_PLAYER_NOT_FOUND_S:format(client.TellName(NAME))
				issecretvalue = function(value) return value == line end
				eq(w.Line(callback), false, "a secret line is left to the game")
				issecretvalue = nil
				eq(w.Line(callback), true, "reading a secret line did not consume a mark")

				A.Tried(NAME)
				GamepadStyle(true)
				local calls = w.calls
				Install()
				eq(w.calls, calls, "switching to the gamepad UI adds nothing")
				eq(w.Line(callback), false, "the installed callback is inert with the gamepad UI")
				GamepadStyle(false)
				Install()
				eq(w.calls, calls, "switching back reuses the installed callback")
				eq(w.Line(callback), true, "switching back restores the fresh mark's filter")
			end)
		end)
	end
end

test("quiet filter recovery: teardown restores the original native filter entries after a failing scene", function()
	local add, util = rawget(_G, "ChatFrame_AddMessageEventFilter"), rawget(_G, "ChatFrameUtil")
	local ok, err = pcall(Scene, "global", function() error("intentional scene failure") end)
	eq(ok, false)
	assert(tostring(err):find("intentional scene failure", 1, true), tostring(err))
	eq(rawget(_G, "ChatFrame_AddMessageEventFilter"), add)
	eq(rawget(_G, "ChatFrameUtil"), util)
end)
