-- A census word this client drops on purpose still moves a counter (GitHub #91).
--
-- On a scoped realm family (Forever) only the group-and-faction form of CG is usable, so a
-- protocol-1 snapshot or claim is dropped at the door. Both exits used to be a bare `return false`:
-- nothing taken, nothing refused, nothing logged. On live that made hundreds of arriving pieces
-- read exactly like an empty wire -- `cg t0 w0 l0 r0` either way -- and the census looked silent
-- while it was in fact discarding complete snapshots. The drop is right; the silence was not.
local ns, test, eq = ...
local D = ns.Data

local NOW = 1700000000

local function With(group, fn)
	local saved = { group = ns.group, now = ns.Now, global = ns.rdb.censusGlobal, me = ns.me }
	ns.group, ns.me = group, "Mine-Realm"
	ns.rdb.censusGlobal = {}
	ns.Now = function() return NOW end
	local ok, err = pcall(fn)
	ns.group, ns.Now, ns.rdb.censusGlobal, ns.me = saved.group, saved.now, saved.global, saved.me
	if not ok then error(err, 0) end
end

local function Cg() return (D.CensusStats() or {}).cg or {} end

local function Snapshot(ver)
	return ("CG~%d~S~%d~%s"):format(ver, NOW, ("Olympus Quiet,100,10,400,%d"):format(NOW - 60))
end

test("a protocol-1 snapshot dropped on a scoped group is counted, not silent", function()
	With("ForeverPvE", function()
		-- The counters run for the whole session, so only the change across the call means anything.
		local was = { skipped = Cg().skipped or 0, refused = Cg().refused or 0, trusted = Cg().trusted or 0 }
		eq(D.ReceiveGlobalCensus("CHANNEL", "Someone-Realm", Snapshot(1)), false, "dropped")
		eq((Cg().skipped or 0) - was.skipped, 1, "the drop moved the skipped counter")
		eq((Cg().refused or 0) - was.refused, 0, "not a refusal: the sender did nothing wrong")
		eq((Cg().trusted or 0) - was.trusted, 0, "and nothing was taken")
		eq(next(ns.rdb.censusGlobal), nil, "no row kept")
	end)
end)

test("a protocol-1 claim dropped on a scoped group is counted too", function()
	With("ForeverPvE", function()
		local before = Cg().skipped or 0
		eq(D.ReceiveGlobalCensus("CHANNEL", "Someone-Realm", ("CG~1~C~%d~"):format(NOW)), false, "dropped")
		eq((Cg().skipped or 0) - before, 1, "the claim's drop moved the counter as well")
	end)
end)

-- The reason reaches /oly bug, so a reader can tell "dropped on purpose" from "nothing arrived".
test("the drop's reason is kept and shown in the counters line", function()
	With("ForeverPvE", function()
		D.ReceiveGlobalCensus("CHANNEL", "Someone-Realm", Snapshot(1))
		local st = D.CensusStats()
		eq(type(st.line), "string")
		assert(st.line:find("cg t%d+ w%d+ l%d+ r%d+ s%d+"), "the line carries a skipped field: " .. tostring(st.line))
		assert(st.line:find("cg:proto", 1, true), "and names the reason: " .. tostring(st.line))
		local found
		for _, r in ipairs(st.last or {}) do if r.kind == "cg" and r.why == "proto" then found = true end end
		assert(found, "the reason is in the kept list too")
	end)
end)

-- An unscoped group still takes protocol 1: the drop is about the realm family, not the version.
test("an unscoped group is unaffected", function()
	With("Whitemane", function()
		local before = Cg().skipped or 0
		D.ReceiveGlobalCensus("CHANNEL", "Someone-Realm", Snapshot(1))
		eq((Cg().skipped or 0) - before, 0, "nothing skipped where the group is not scoped")
	end)
end)
