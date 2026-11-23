local H = ...
local test, eq, World = H.test, H.eq, H.World
local K = assert(loadfile(H.ROOT .. "tests/arena/lib/craft-world.lua"))(H)

local function Access(c, state)
	c.ns.SharedToolsHere = function() return state.here ~= false end
	c.ns.SharedPeerAllowed = function(_, guild) return state.here ~= false and state.peer ~= false and guild ~= "Olympus Impostor" end
end

test("federation shared tools: Arena multiplayer send and native receive require participating peers", function()
	local w = World.New()
	local a, b = w:Client("Sage Owl"), w:Client("Wren Thistle")
	local sa, sb, received = {}, {}, 0
	Access(a, sa); Access(b, sb)
	w:As(b, function()
		b.ns.Comm.Handle("AF", b.ns.Arena.Handle("AF", function() received = received + 1 end))
	end)
	assert(a.Arena.Send("AF", "T", "first", { to = b.name }))
	w:Run(0)
	eq(received, 1)
	sb.peer = false
	assert(a.Arena.Send("AF", "T", "denied", { to = b.name }))
	w:Run(0)
	eq(received, 1, "a real sender stamp still needs participation proof")
	sa.here = false
	local ok, why = a.Arena.Send("AF", "T", "closed", { to = b.name })
	eq(ok, false); eq(why, "federation")
end)

test("federation shared tools: queued Arena messages recheck participation at dispatch", function()
	local w = World.New()
	local a, b = w:Client("Sage Owl"), w:Client("Wren Thistle")
	local state, held = {}, nil
	Access(a, state)
	w:As(a, function()
		local send = a.ns.Comm.Whisper
		a.ns.Comm.Whisper = function(_, _, _, _, _, _, options) held = options return true end
		local ok, err = pcall(function()
			assert(a.ns.Arena.Send("AF", "T", "queued", { to = b.name }))
			assert(held and type(held.guard) == "function", "Arena hands Comm a dispatch-time guard")
			eq(held.guard(), true)
			state.here = false
			eq(held.guard(), false)
		end)
		a.ns.Comm.Whisper = send
		if not ok then error(err, 0) end
	end)
end)

test("federation shared tools: honor identity remains available for control-plane bootstrap", function()
	local w = World.New()
	local a = w:Client("Sage Owl")
	Access(a, { here = false, peer = false })
	local ok, why = a.Arena.Send("IO", "L", "identity", { dist = "GUILD" })
	-- IO itself does not use the guild lane: it reaches its ordinary lane validation,
	-- proving that participation did not replace that existing protocol decision.
	eq(ok, false); eq(why, "guild-lane")
end)

test("federation shared tools: crafting refuses new work and forged peer guilds", function()
	local w = World.New({ compliance = "shipped" })
	local a, b = K.Client(w, "Sage Owl"), K.Client(w, "Wren Thistle")
	local sa, sb = {}, {}
	Access(a, sa); Access(b, sb)
	K.Recipes(w, b, { [14342] = "Mooncloth" })
	local r = K.Request(w, a, 14342, "Mooncloth", 2)
	assert(K.Rec(w, b, r.id), "participating peer sees the actual published card")
	sb.here = false
	local ok, why = b.Craft.Accept(r.id)
	eq(ok, false); eq(why, "federation")
	eq(K.Rec(w, b, r.id).claimPending, nil)
	sa.here = false
	ok, why = a.Craft.OpenComposer()
	eq(ok, false); eq(why, "federation")
	sa.here, sb.here = true, true
	local msg = w:As(a, function() return a.ns.CraftRequests.Card(r) end)
	sb.peer = false
	w:As(b, function()
		local accepted, reason = b.ns.CraftRequests.ReceiveSnapshot("CHANNEL", a.name, msg)
		eq(accepted, false); eq(reason, "federation", "rejected before the claimed guild can alter census identity")
	end)
end)

test("federation shared tools: crown coordinates are gated while the King's identity remains", function()
	local w = World.New()
	local king = w:Role("king")
	Access(king, { here = false })
	w:As(king, function()
		eq(king.ns.King.IsKing(), true)
		local ok, why = king.ns.King.EffectiveLocation()
		eq(ok, false); eq(why, "federation")
		eq(king.ns.King.IsKing(), true, "participation never removes royal authority")
	end)
end)

test("federation shared tools: multiplayer Bones refuses new games independently of local teaching", function()
	local w = World.New()
	local a, b = w:Client("Sage Owl"), w:Client("Wren Thistle")
	Access(a, { here = false })
	w:As(a, function()
		local ok, why = a.ns.FarkleTable.CanCreate({ guest = b.name })
		eq(ok, false); eq(why, "federation")
		-- A finished local lesson still has its ordinary state, not a network denial.
		eq(a.ns.FarkleTable.ActWhy({ role = "practice", game = { over = true } }), "over")
	end)
end)
