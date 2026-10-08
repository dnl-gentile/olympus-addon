-- Forever build 70205 exposes C_UnitAuras.GetPlayerAuraBySpellID; its aura field is spellId.
-- This is the player's own observation, not Board data or a remotely claimed campfire.
local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local CAMP = 1283391
local function FT(c) return c.ns.FarkleTable end
local function As(w, c, fn, ...) return w:As(c, fn, ...) end
local function Aura(c, kind)
	c.auraKind = kind
	c.secretReads = 0
	c.secretAura, c.secretSpell = setmetatable({}, { __index = function()
		c.secretReads = c.secretReads + 1; error("secret aura fields cannot be read")
	end }), {}
	c.globals.issecretvalue = function(v) return v == c.secretAura or v == c.secretSpell end
	if kind == "missing-api" then c.globals.C_UnitAuras = nil; return end
	if kind == "missing-method" then c.globals.C_UnitAuras = {}; return end
	c.globals.C_UnitAuras = { GetPlayerAuraBySpellID = function(spell)
		eq(spell, CAMP, "only the independently verified Forever campfire spell is queried")
		c.auraReads = (c.auraReads or 0) + 1
		if c.auraKind == "error" then error("aura unavailable") end
		if c.auraKind == "secret-aura" then return c.secretAura end
		if c.auraKind == "secret-spell" then return { spellId = c.secretSpell } end
		if c.auraKind == "other" then return { spellId = 12345 } end
		if c.auraKind == "camp" then return { spellId = CAMP } end
		return nil
	end }
end
local function Pair()
	local w = FW.New({ compliance = "shipped" })
	local a, b = w:Player(H.World.NAMES.fighterA), w:Player(H.World.NAMES.fighterB)
	for i, c in ipairs({ a, b }) do
		w:Stand(c.name, { cont = FW.ROAD.cont, wx = FW.ROAD.wx + (i - 1) * 3, wy = FW.ROAD.wy }, false)
		rawset(c.ns, "Board", nil)
		c.boardBefore = c.ns.Board -- World inherits a missing-feature proxy, not a real camp source
		Aura(c, "camp")
	end
	return w, a, b
end
local function Errors(w)
	for _, c in ipairs(w.clients) do eq(#c.errors, 0, table.concat(c.errors, "; ")) end
end
local function Agree(w, a, b)
	local id = assert(As(w, a, FT(a).Create, { guest = b.name, target = 2000, secs = 120 }))
	w:Run(0); assert(As(w, b, FT(b).Answer, id, true)); w:Run(0)
	eq(FT(a).Get(id).state, "agreed")
	return id
end
local function Playing(w, a, b)
	local id = Agree(w, a, b)
	w:Group({ a, b }); w:Run(2)
	eq(FT(a).Get(id).state, "open"); eq(FT(b).Get(id).state, "open")
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	assert(As(w, a, FT(a).Roll, id)); assert(As(w, b, FT(b).Roll, id)); w:Run(0)
	eq(FT(a).Get(id).state, "play"); eq(FT(b).Get(id).state, "play")
	return id
end

test("Bones campfire: own native aura qualifies New Table without a Board camp or privacy change, not the first lesson", function()
	local w, a, b = Pair()
	local location, help = a.ns.db.shareLocation, a.ns.db.layerHelp
	eq(As(w, a, FT(a).CanOpen), true)
	eq(As(w, a, FT(a).CanCreate, { guest = b.name, target = 2000 }), true)
	assert((a.auraReads or 0) > 0)
	eq(rawget(a.ns, "Board"), nil); eq(a.ns.Board, a.boardBefore)
	eq(a.ns.db.shareLocation, location); eq(a.ns.db.layerHelp, help)
	As(w, a, function() FT(a).Opts().innkeeperLearned = nil end)
	local ok, why = As(w, a, FT(a).CanCreate, { guest = b.name, target = 2000 })
	eq(ok, false); eq(why, "training")
	local id; id, why = As(w, a, FT(a).Practice, { target = 2000 })
	eq(id, nil); eq(why, "training_inn", "a physical camp never impersonates the innkeeper lesson")
	Errors(w)
end)

test("Bones campfire: absent, unrelated, secret, throwing and missing aura APIs never admit a road table", function()
	local w, a, b = Pair()
	for _, kind in ipairs({ "none", "other", "secret-aura", "secret-spell", "error", "missing-api", "missing-method" }) do
		Aura(a, kind)
		eq(As(w, a, FT(a).CanOpen), false, kind)
		eq(As(w, a, FT(a).CanCreate, { guest = b.name, target = 2000 }), false, kind)
		eq(a.secretReads, 0, "secret aura is rejected before indexing its fields")
	end
	Aura(a, "camp"); a.instance = true
	eq(As(w, a, FT(a).CanOpen), false, "no campfire venue inside an instance")
	eq(As(w, a, FT(a).CanCreate, { guest = b.name, target = 2000 }), false)
	Errors(w)
end)

test("Bones campfire: the guest independently needs its own aura at acceptance and again at the actual opening handshake", function()
	local w, a, b = Pair()
	local id = assert(As(w, a, FT(a).Create, { guest = b.name, target = 2000, secs = 120 }))
	w:Run(0); Aura(b, "none")
	eq(As(w, b, FT(b).CanAnswer, id, true), false, "the host's real aura cannot authorize the guest")
	eq(As(w, b, FT(b).CanAnswer, id, false), true)
	Aura(b, "camp"); assert(As(w, b, FT(b).Answer, id, true)); w:Run(0)
	w:Group({ a, b }); assert(As(w, a, FT(a).Open, id))
	local send = w.SendNow
	w.SendNow = function(self, from, item)
		if from == a and item.msg:sub(1, 2) == "KG" then
			Aura(b, "none"); self.SendNow = send
		end
		return send(self, from, item)
	end
	w:Run(0)
	eq(FT(b).Get(id).state, "agreed"); eq(FT(b).Get(id).game, nil)
	eq(As(w, b, FT(b).Roll, id), false, "a stale host opening never starts the guest outside its own camp")
	Errors(w)
end)

test("Bones campfire: real free T peers still need a party and ten-yard proximity, then share the same game", function()
	local w, a, b = Pair()
	local id = Agree(w, a, b)
	eq(As(w, a, FT(a).TavernStart, b.name), false, "no party yet")
	w:Stand(b.name, { cont = FW.ROAD.cont, wx = FW.ROAD.wx + 11, wy = FW.ROAD.wy }, false)
	w:Group({ a, b }); w:Run(2)
	local ok, why = As(w, a, FT(a).TavernStart, b.name)
	eq(ok, false); eq(why, "far"); eq(FT(a).Get(id).state, "agreed")
	w:Stand(b.name, { cont = FW.ROAD.cont, wx = FW.ROAD.wx + 3, wy = FW.ROAD.wy }, false)
	-- Open's failed distance check cleared needGroup: that is a rejected start, not a retry
	-- scheduled every second. Exercise the actual new attempt after moving into range.
	assert(As(w, a, FT(a).Open, id)); w:Run(0)
	for _, c in ipairs({ a, b }) do
		local t = FT(c).Get(id)
		eq(t.state, "open"); eq(t.mode, "T"); eq(t.camp, true); eq(t.campfire, true); eq(t.inn, nil)
		eq(rawget(c.ns, "Board"), nil); eq(c.ns.Board, c.boardBefore)
		eq(As(w, c, c.ns.Arena.Counts, t.mode), false)
	end
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	assert(As(w, a, FT(a).Roll, id)); assert(As(w, b, FT(b).Roll, id)); w:Run(0)
	eq(FT(a).Get(id).state, "play"); eq(FT(b).Get(id).state, "play")
	eq(table.concat(FT(a).Get(id).game.events, "|"), table.concat(FT(b).Get(id).game.events, "|"))
	w:Logout(a); w:Login(a); FW.Extend(w, a); Aura(a, "camp"); w:Group({ a, b })
	local restored = assert(FT(a).Get(id), "actual saved table survives namespace reload")
	eq(restored.campfire, true); eq(restored.camp, true); eq(restored.inn, nil)
	Aura(a, "none")
	eq(As(w, a, FT(a).Away, restored, restored.seat), true, "reload retains the physical camp's own-aura departure rule")
	Errors(w)
end)

test("Bones campfire: losing own aura pauses before an action, return clears it, physical departure retains the existing grace", function()
	local w, a, b = Pair()
	local id = Playing(w, a, b)
	local ta, tb = FT(a).Get(id), FT(b).Get(id)
	Aura(a, "none"); w:Run(2)
	eq(As(w, a, FT(a).Away, ta, ta.seat), true)
	local v = As(w, a, FT(a).View, id)
	assert(v.awayLeft and v.awayLeft > 0 and v.awayLeft <= FT(a).TAVERN_GRACE)
	local events, rolls = #ta.game.events, #w:Rolls(a.name)
	eq(As(w, a, FT(a).Roll, id), false)
	eq(#ta.game.events, events); eq(#w:Rolls(a.name), rolls, "no early native roll while away")
	w:Run(3); eq(ta.game.over, false); eq(tb.game.over, false)
	Aura(a, "camp"); w:Run(2); eq(As(w, a, FT(a).View, id).awayLeft, nil)
	w:Stand(b.name, { cont = FW.ROAD.cont, wx = FW.ROAD.wx + 60, wy = FW.ROAD.wy }, false)
	w:Run(2); eq(As(w, a, FT(a).View, id).clock.paused, "tavern")
	w:Run(3); eq(ta.game.over, false)
	w:Run(FT(a).TAVERN_GRACE + 2)
	eq(ta.game.over, true); eq(ta.game.winner, ta.seat); eq(tb.game.winner, ta.seat)
	Errors(w)
end)

test("Bones campfire: unknown own aura cannot establish departure or trigger a forfeit", function()
	local w, a, b = Pair()
	local id = Playing(w, a, b)
	local ta, tb = FT(a).Get(id), FT(b).Get(id)
	for _, kind in ipairs({ "secret-aura", "secret-spell", "error", "missing-api", "missing-method" }) do
		Aura(a, kind)
		eq(As(w, a, FT(a).Away, ta, ta.seat), false, kind .. " is unknown, not an observed absence")
		w:Run(2); eq(As(w, a, FT(a).View, id).awayLeft, nil)
	end
	w:Run(FT(a).TAVERN_GRACE + 2)
	eq(ta.game.over, false); eq(tb.game.over, false)
	Errors(w)
end)
