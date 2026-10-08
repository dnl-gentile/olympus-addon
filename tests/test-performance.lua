local test, eq, root = ...
local Performance = assert(loadfile((root or "./") .. "tests/performance.lua"))()

local function Fixture(options)
	local state = { kb = 10 * 1024, cpu = 20, wall = 40, lines = {}, flushes = 0, collections = 0 }
	options = options or {}
	options.output = {
		write = function(_, line) state.lines[#state.lines + 1] = line end,
		flush = function() state.flushes = state.flushes + 1 end,
	}
	options.clock, options.wall = function() return state.cpu end, function() return state.wall end
	options.memory = function(action)
		if action == "collect" then state.collections = state.collections + 1; state.kb = 12 * 1024
		else eq(action, "count"); return state.kb end
	end
	return Performance.New(options), state
end

test("Harness performance: optional BEGIN is flushed before the body and END measures the same case", function()
	local perf, state = Fixture({ profile = true })
	local measurement = perf:Start("an expensive case")
	eq(state.flushes, 1)
	assert(state.lines[1]:find("BEGIN 10.0 MiB an expensive case", 1, true))
	state.kb, state.cpu, state.wall = 15 * 1024, 22.5, 43
	perf:Finish(measurement)
	eq(state.flushes, 2); eq(state.collections, 0)
	assert(state.lines[2]:find("END cpu=2.500s wall=3s heap=15.0 MiB delta=+5.0 MiB an expensive case", 1, true))
end)

test("Harness performance: disabled diagnostics do not write or collect", function()
	local perf, state = Fixture()
	eq(perf:Start("quiet"), nil)
	state.kb = 256 * 1024
	perf:Finish(nil)
	eq(#state.lines, 0); eq(state.flushes, 0); eq(state.collections, 0)
end)

test("Harness performance: bounded collection only above the configured case-boundary high-water mark", function()
	local perf, state = Fixture({ profile = true, gcMB = 128 })
	local measurement = perf:Start("large")
	state.kb = 128 * 1024
	perf:Finish(measurement)
	eq(state.collections, 0)
	state.kb = 129 * 1024
	perf:Finish(measurement)
	eq(state.collections, 1)
	assert(state.lines[#state.lines]:find("GC cpu=0.000s heap=129.0 -> 12.0 MiB", 1, true))
	perf:Finish(nil)
	eq(state.collections, 1)
end)
