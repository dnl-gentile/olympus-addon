local H = ...
local test, eq, World = H.test, H.eq, H.World

local function Protected(fn)
	local popups, slashes, savedPopups, savedSlashes = StaticPopupDialogs, SlashCmdList, {}, {}
	for k, v in pairs(popups) do savedPopups[k] = v end
	for k, v in pairs(slashes) do savedSlashes[k] = v end
	local ok, err = pcall(fn, popups, slashes)
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
