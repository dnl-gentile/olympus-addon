local H = ...
local test, eq = H.test, H.eq
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)

local function Fights(w, c) return W3.M(w, c, "ArenaFights") end
local function Tourneys(w, c) return W3.M(w, c, "ArenaTourney") end
local function Fight(w, cast)
	return Fights(w, cast.arbiter).New({ A = cast.A.name, B = cast.B.name, markets = false })
end
local function Card(w, cast, title)
	return w:As(cast.king, cast.king.ns.ArenaFights.Card.New, title, w.clock)
end
local function Cards(c)
	local n = 0
	for _ in pairs(c.ns.Arena.Store("L").cards or {}) do n = n + 1 end
	return n
end

test("Arena record capacity: local fights refuse overflow without deleting active bouts, and reclaim an ended bout", function()
	local w, cast = W3.New()
	local f = Fights(w, cast.arbiter)
	f.KEEP = 2
	local first, second = assert(Fight(w, cast)), assert(Fight(w, cast))
	local overflow, why = Fight(w, cast)
	eq(overflow, nil); eq(why, "capacity")
	eq(#f.List(), 2); eq(f.Fight(first).st, "D"); eq(f.Fight(second).st, "D")
	eq(f.Void(first, "cancel"), true)
	local third = assert(Fight(w, cast))
	eq(#f.List(), 2); eq(f.Fight(first), nil); eq(f.Fight(second).st, "D"); eq(f.Fight(third).st, "D")
	W3.NoErrors(w)
end)

test("Arena record capacity: observer memory admits only its limit but accepts updates to known fights", function()
	local w, cast = W3.New()
	local source, observer = Fights(w, cast.arbiter), Fights(w, cast.spectator)
	observer.MEM_KEEP = 2
	local ids = {}
	for i = 1, 4 do ids[i] = assert(Fight(w, cast)); assert(source.Announce(ids[i])); w:Run(0) end
	eq(#observer.List(), 2); eq(observer.Fight(ids[3]), nil); eq(observer.Fight(ids[4]), nil)
	eq(source.Void(ids[1], "cancel"), true); w:Run(0)
	eq(observer.Fight(ids[1]).st, "V", "full memory still updates a retained fight")
	eq(source.Announce(ids[3]), true); w:Run(0)
	eq(#observer.List(), 2); eq(observer.Fight(ids[1]), nil)
	eq(observer.Fight(ids[2]).st, "A"); eq(observer.Fight(ids[3]).st, "A")
	eq(observer.Stats().refused.capacity >= 2, true)
	W3.NoErrors(w)
end)

test("Arena record capacity: loaded observer storage is bounded without discarding active records", function()
	local w, cast = W3.New()
	W3.Companion(w, cast.spectator)
	local source, observer = Fights(w, cast.arbiter), Fights(w, cast.spectator)
	observer.KEEP = 2
	local ids = {}
	for i = 1, 3 do ids[i] = assert(Fight(w, cast)); assert(source.Announce(ids[i])); w:Run(0) end
	eq(#observer.List(), 2); eq(observer.Fight(ids[3]), nil)
	eq(source.Void(ids[1], "cancel"), true); w:Run(0)
	eq(observer.Fight(ids[1]).st, "V")
	eq(#observer.List(), 2)
	W3.NoErrors(w)
end)

test("Arena record capacity: a retained fight still updates when migration would exceed the new store's limit", function()
	local w, cast = W3.New()
	local source, observer = Fights(w, cast.arbiter), Fights(w, cast.spectator)
	local ids = {}
	for i = 1, 3 do ids[i] = assert(Fight(w, cast)); assert(source.Announce(ids[i])); w:Run(0) end
	W3.Companion(w, cast.spectator)
	observer.KEEP = 2
	for i = 1, 2 do assert(source.Announce(ids[i])); w:Run(0) end
	eq(source.Void(ids[3], "cancel"), true); w:Run(0)
	eq(#observer.List(), 3, "loading the companion must not discard previously held active fights")
	eq(observer.Fight(ids[1]).st, "A"); eq(observer.Fight(ids[2]).st, "A")
	eq(observer.Fight(ids[3]).st, "V", "the existing session copy receives its result")
	local n = 0
	for _ in pairs(cast.spectator.ns.Arena.Heavy("L").fights) do n = n + 1 end
	eq(n, 2, "retaining the old copy does not overflow the destination")
	W3.NoErrors(w)
end)

test("Arena record capacity: full local cards reject new cards without sending or consuming their number", function()
	local w, cast = W3.New()
	cast.king.ns.ArenaFights.CARDS_KEEP = 2
	local first, second = assert(Card(w, cast, "First")), assert(Card(w, cast, "Second"))
	w:Run(0)
	local sent = #w:Sent{ from = cast.king, type = "AN" }
	local cid, why = Card(w, cast, "Overflow")
	eq(cid, nil); eq(why, "capacity"); eq(Cards(cast.king), 2)
	w:Run(0)
	eq(#w:Sent{ from = cast.king, type = "AN" }, sent)
	eq(cast.king.ns.Arena.Store("L").cardNo, 2)
	eq(cast.king.ns.ArenaFights.Card.Get(first).st, "P")
	eq(cast.king.ns.ArenaFights.Card.Get(second).st, "P")
	W3.NoErrors(w)
end)

test("Arena record capacity: ended cards use their own terminal states when reclaiming space", function()
	local w, cast = W3.New()
	cast.king.ns.ArenaFights.CARDS_KEEP = 2
	local first, second = assert(Card(w, cast, "First")), assert(Card(w, cast, "Second"))
	local fid = assert(w:As(cast.king, cast.king.ns.ArenaFights.Card.AddBout, first,
		{ A = cast.A.name, B = cast.B.name, arb = cast.arbiter.name, markets = false }))
	eq(Fights(w, cast.king).Void(fid, "cancel"), true)
	w:As(cast.king, cast.king.ns.ArenaFights.CardTick, cast.king.ns.ArenaFights.Card.Get(first), w.clock)
	eq(cast.king.ns.ArenaFights.Card.Get(first).st, "X")
	local third = assert(Card(w, cast, "Third"))
	eq(Cards(cast.king), 2); eq(cast.king.ns.ArenaFights.Card.Get(first), nil)
	eq(cast.king.ns.ArenaFights.Card.Get(second).st, "P"); eq(cast.king.ns.ArenaFights.Card.Get(third).no, 3)
	W3.NoErrors(w)
end)

test("Arena record capacity: local tournaments cap active records and reclaim cancelled records", function()
	local w, cast = W3.New()
	local t = Tourneys(w, cast.king)
	local ids = {}
	for i = 1, 10 do ids[i] = assert(t.New({ size = 4, markets = false })) end
	local overflow, why = t.New({ size = 4, markets = false })
	eq(overflow, nil); eq(why, "capacity"); eq(#t.All(), 10)
	eq(t.CloseRegistration(ids[1]), true)
	eq(t.StartDraw(ids[1]), false)
	eq(t.Find(ids[1]).st, "X")
	local nextID = assert(t.New({ size = 4, markets = false }))
	eq(#t.All(), 10); eq(t.Find(ids[1]), nil); eq(t.Find(ids[2]).st, "R"); eq(t.Find(nextID).st, "R")
	W3.NoErrors(w)
end)

test("Arena record capacity: incoming tournaments cap active records and continue known updates", function()
	local w, cast = W3.New()
	local source, observer = Tourneys(w, cast.king), Tourneys(w, cast.spectator)
	local ids = {}
	for i = 1, 10 do ids[i] = assert(source.New({ size = 4, markets = false })); w:Run(0) end
	-- A separate valid promoter has its own room; the observing client's room is already full.
	local extra = assert(Tourneys(w, cast.arbiter).New({ size = 4, markets = false })); w:Run(0)
	eq(#observer.All(), 10); eq(observer.Find(extra), nil)
	eq(source.CloseRegistration(ids[1]), true); w:Run(0)
	eq(observer.Find(ids[1]).st, "K", "the full store still takes known updates")
	eq(observer.Stats().refused.capacity, 1)
	W3.NoErrors(w)
end)
