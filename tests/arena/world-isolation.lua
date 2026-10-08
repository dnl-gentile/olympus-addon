local H = ...
local test, eq, World = H.test, H.eq, H.World

local function Protected(fn)
	local popups, slashes, savedPopups, savedSlashes = StaticPopupDialogs, SlashCmdList, {}, {}
	for k, v in pairs(popups) do savedPopups[k] = v end
	for k, v in pairs(slashes) do savedSlashes[k] = v end
	local ok, err = pcall(fn, popups, slashes, savedPopups, savedSlashes)
	StaticPopupDialogs, SlashCmdList = popups, slashes
	wipe(popups); wipe(slashes)
	for k, v in pairs(savedPopups) do popups[k] = v end
	for k, v in pairs(savedSlashes) do slashes[k] = v end
	assert(ok, err)
end

test("World isolation: client popup/slash registration survives nested calls and errors without changing the host", function()
	Protected(function(hostPopups, hostSlashes)
		local w = World.New()
		local a, b = w:Client("Lark Fenn"), w:Client("Willow Fern")
		w:As(a, function()
			eq(StaticPopupDialogs, a.popups, "client popup table")
			eq(SlashCmdList, a.slashes, "client slash table")
			StaticPopupDialogs.OLYMPUS_TEST_ONLY = { text = "a" }
			SlashCmdList.OLYMPUS_TEST_ONLY = function() return "a" end
			local ok = pcall(function()
				w:As(b, function()
					eq(StaticPopupDialogs, b.popups)
					eq(SlashCmdList, b.slashes)
					eq(StaticPopupDialogs.OLYMPUS_TEST_ONLY, nil)
					StaticPopupDialogs.OLYMPUS_TEST_ONLY = { text = "b" }
					SlashCmdList.OLYMPUS_TEST_ONLY = function() return "b" end
					error("expected nested failure")
				end)
			end)
			eq(ok, false)
			eq(StaticPopupDialogs, a.popups, "outer table restored on failure")
			eq(SlashCmdList.OLYMPUS_TEST_ONLY(), "a")
		end)
		eq(StaticPopupDialogs, hostPopups); eq(SlashCmdList, hostSlashes)
		eq(hostPopups.OLYMPUS_TEST_ONLY, nil); eq(hostSlashes.OLYMPUS_TEST_ONLY, nil)
		eq(a.popups.OLYMPUS_TEST_ONLY.text, "a"); eq(b.popups.OLYMPUS_TEST_ONLY.text, "b")
		eq(a.slashes.OLYMPUS_TEST_ONLY(), "a"); eq(b.slashes.OLYMPUS_TEST_ONLY(), "b")
	end)
end)

test("World isolation: reload keeps fresh client popup and slash callbacks without changing the host or another client", function()
	Protected(function(hostPopups, hostSlashes, savedPopups, savedSlashes)
		local hostMatch, hostSlash = hostPopups.OLYMPUS_ARENA_MATCH, hostSlashes.OLYMPUS
		local w = World.New()
		local a, b = w:Client("Lark Fenn"), w:Client("Willow Fern")
		local oldA, oldB = a.ns, b.ns
		local aPopup, bPopup = a.popups.OLYMPUS_ARENA_MATCH, b.popups.OLYMPUS_ARENA_MATCH
		local aSlash, bSlash = a.slashes.OLYMPUS, b.slashes.OLYMPUS
		assert(aPopup and bPopup and aSlash and bSlash, "real initial registrations")
		w:Logout(a); w:Login(a)
		assert(a.popups.OLYMPUS_ARENA_MATCH, "real popup survives a reload")
		assert(a.popups.OLYMPUS_ARENA_MATCH ~= aPopup, "reloaded popup belongs to the new namespace")
		assert(a.slashes.OLYMPUS ~= aSlash, "reloaded slash belongs to the new namespace")
		eq(b.popups.OLYMPUS_ARENA_MATCH, bPopup); eq(b.slashes.OLYMPUS, bSlash)
		w:Logout(b); w:Login(b)
		assert(b.popups.OLYMPUS_ARENA_MATCH and b.popups.OLYMPUS_ARENA_MATCH ~= bPopup)
		assert(b.slashes.OLYMPUS and b.slashes.OLYMPUS ~= bSlash)
		local calls = { a = 0, b = 0, old = 0 }
		oldA.SafeCall = function() calls.old = calls.old + 1 end
		oldB.SafeCall = oldA.SafeCall
		for _, c in ipairs({ a, b }) do
			local key = c == a and "a" or "b"
			c.ns.SafeCall = function(where)
				assert(where == "arena match yes" or where == "slash arena status", "actual callback dispatch")
				calls[key] = calls[key] + 1
			end
			w:As(c, function()
				eq(StaticPopupDialogs, c.popups); eq(SlashCmdList, c.slashes)
				StaticPopupDialogs.OLYMPUS_ARENA_MATCH.OnAccept({ data = {} })
				SlashCmdList.OLYMPUS("arena status")
			end)
		end
		eq(calls.a, 2); eq(calls.b, 2); eq(calls.old, 0, "no callbacks from the previous session")
		eq(StaticPopupDialogs, hostPopups); eq(SlashCmdList, hostSlashes)
		eq(hostPopups.OLYMPUS_ARENA_MATCH, hostMatch); eq(hostSlashes.OLYMPUS, hostSlash)
		for key, value in pairs(savedPopups) do eq(hostPopups[key], value, "host popup preserved") end
		for key, value in pairs(hostPopups) do eq(value, savedPopups[key], "no client popup added to host") end
		for key, value in pairs(savedSlashes) do eq(hostSlashes[key], value, "host slash preserved") end
		for key, value in pairs(hostSlashes) do eq(value, savedSlashes[key], "no client slash added to host") end
	end)
end)

test("World isolation: actual lazy companion popup stays with its client and cannot retain finished worlds through the host", function()
	Protected(function(hostPopups, hostSlashes)
		local saved = hostPopups.OLYMPUS_ARENA_CONFIRM
		local worlds = setmetatable({}, { __mode = "k" })
		local function Scenario()
			local w = World.New()
			local a = w:Client("Lark Fenn")
			worlds[w] = true
			w:As(a, function() H.LoadCompanion(a.ns) end)
			assert(a.popups.OLYMPUS_ARENA_CONFIRM, "real Kit.lua popup registered for its client")
			eq(StaticPopupDialogs, hostPopups); eq(SlashCmdList, hostSlashes)
			eq(hostPopups.OLYMPUS_ARENA_CONFIRM, saved, "lazy load must not register into the host")
		end
		Scenario()
		-- LuaJIT traces can briefly retain a completed scenario too; this assertion checks
		-- strong host registration, not the lifetime of the optimizing runtime's cache.
		if jit and jit.flush then jit.flush() end
		collectgarbage("collect")
		eq(next(worlds), nil, "the finished world has no strong host root")
	end)
end)
