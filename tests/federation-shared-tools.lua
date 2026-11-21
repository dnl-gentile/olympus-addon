-- Exercise the real consumers: enrollment is separate from Olympus identity and
-- is checked again when a saved card, pending answer or queued word is used.
local ns, test, eq, H = ...
local function WithAccess(fn)
	local here, peer = ns.SharedToolsHere, ns.SharedPeerAllowed
	local state = { here = true, peer = true }
	ns.SharedToolsHere = function() return state.here end
	ns.SharedPeerAllowed = function() return state.here and state.peer end
	local ok, err = pcall(fn, state)
	ns.SharedToolsHere, ns.SharedPeerAllowed = here, peer
	if not ok then error(err, 0) end
end

test("federation shared tools: real Core policy helper keeps no-policy compatibility", function()
	H.WithBoard(function(_, B)
		H.AsSoldier()
		local old, active, enrolled = ns.FederationProgram, false, false
		ns.FederationProgram = { Active = function() return active end,
			LocalEnrollment = function() return enrolled and "Olympus II" or nil end }
		local ok, err = pcall(function()
			eq(ns.SharedToolsHere(), true)
			eq(B.Ready(), true, "the absence of an active program preserves the old protocol")
			active = true
			eq(ns.SharedToolsHere(), false)
			local yes, why = B.Ready()
			eq(yes, false); eq(why, "federation")
			enrolled = true
			eq(ns.SharedToolsHere(), true); eq(B.Ready(), true)
		end)
		ns.FederationProgram = old
		if not ok then error(err, 0) end
	end)
end)

test("federation shared tools: Board is closed without changing membership", function()
	H.WithBoard(function(w, B)
		H.AsSoldier()
		WithAccess(function(s)
			eq(ns.IsMember(), true)
			s.here = false
			local ok, why = B.Ready()
			eq(ok, false); eq(why, "federation")
			eq(B.Ask(), false)
			eq(#w.sent, 0)
			eq(ns.IsMember(), true, "guild identity survives shared-tools restriction")
		end)
	end)
end)

test("federation shared tools: Board rejects unapproved peers and hides retained cards", function()
	H.WithBoard(function(_, B)
		H.AsSoldier()
		WithAccess(function(s)
			local msg = B.Encode({ id = "a7", guild = "Olympus III", flag = "R", level = 30, class = "WA", every = 10, age = 0, note = "" })
			s.peer = false
			B.HandlePost("CHANNEL", "Visitor-Realm", msg)
			eq(#B.List(), 0, "a guild claimed inside the packet is not enrollment proof")
			s.peer = true
			B.HandlePost("CHANNEL", "Visitor-Realm", msg)
			eq(#B.List(), 1)
			s.peer = false
			eq(#B.List(), 0, "previously retained data is hidden after peer revocation")
		end)
	end)
end)

test("federation shared tools: queued Board publication rechecks participation", function()
	H.WithBoard(function(_, B)
		H.AsSoldier()
		WithAccess(function(s)
			local send, held = ns.Comm.Send
			ns.Comm.Send = function(_, _, _, _, _, _, options) held = options return true end
			local ok, err = pcall(function()
				B.Raise("R", "")
				assert(held and type(held.guard) == "function", "publication has a dispatch-time policy guard")
				eq(held.guard(), true)
				s.here = false
				eq(held.guard(), false)
			end)
			ns.Comm.Send = send
			if not ok then error(err, 0) end
		end)
	end)
end)

test("federation shared tools: Layers preserve local detection but do not share closed tools", function()
	H.WithHop(function(w, Hop)
		WithAccess(function(s)
			s.here = false
			ns.db.shareLocation = true
			w.see(7)
			assert(ns.Layers.Mine(), "native layer observation remains local")
			eq(ns.Layers.Sharing(), false)
			eq(#w.sent, 0, "no location announced")
			eq(Hop.CanHelp(1453, 7), false)
			eq(Hop.Member("Guildmate-Realm"), false, "even a real guildmate is not entitled to closed shared tools")
		end)
	end)
end)

test("federation shared tools: Layers reject unapproved positions and filter old positions", function()
	H.WithHop(function(_, _)
		WithAccess(function(s)
			local layer = { guild = "Olympus III", mapID = 1453, zoneUID = 9 }
			s.peer = false
			ns.Layers.Receive("Visitor-Realm", layer)
			eq(#ns.Layers.ForMap(1453), 0)
			s.peer = true
			ns.Layers.Receive("Visitor-Realm", layer)
			eq(#ns.Layers.ForMap(1453), 1)
			s.here = false
			eq(#ns.Layers.ForMap(1453), 0)
		end)
	end)
end)

test("federation shared tools: Groups bind listings to approved actors and hide revoked listings", function()
	H.WithBoard(function()
		H.AsSoldier()
		local G = ns.Groups
		G.Reset()
		WithAccess(function(s)
			local msg = G.Encode({ id = "m", guild = "Olympus III", kind = "D", target = "SM", level = 30,
				need = "113", size = 1, every = 10, age = 0 })
			s.peer = false
			G.HandlePost("CHANNEL", "Visitor-Realm", msg)
			eq(#G.List(), 0)
			s.peer = true
			G.HandlePost("CHANNEL", "Visitor-Realm", msg)
			eq(#G.List(), 1); eq(G.Count(), 1)
			s.peer = false
			eq(#G.List(), 0); eq(G.Count(), 0)
			local ok, why = G.Apply("Visitor-Realm", "H", "")
			eq(ok, false); eq(why, "federation")
		end)
		G.Reset()
	end)
end)

test("federation shared tools: native guild position handler requires enrollment", function()
	H.WithBoard(function()
		WithAccess(function(s)
			local handlers = {}
			local c = setmetatable({ Pins = function() end, On = function() end,
				Comm = { Handle = function(kind, fn) handlers[kind] = fn end } }, { __index = ns })
			assert(loadfile(H.ADDON_DIR .. "Positions.lua"))("Olympus", c)
			local msg = ns.Codec.EncodePosition(1453, 0.4, 0.6, "WA")
			s.peer = false
			handlers.P1("GUILD", "Guildmate-Realm", msg)
			eq(c.Positions.Count(), 0)
			s.peer = true
			handlers.P1("GUILD", "Guildmate-Realm", msg)
			eq(c.Positions.Count(), 1)
			s.here = false
			eq(c.Positions.Count(), 0, "a retained map dot is hidden on withdrawal")
		end)
	end)
end)

test("federation shared tools: war actions, map edits and sighting requests refuse closed tools", function()
	H.WithBoard(function()
		H.AsSoldier()
		WithAccess(function(s)
			s.here = false
			local ok, why = ns.War.SetRoles("healer support")
			eq(ok, false); eq(why, "federation")
			eq(ns.War.Ask(true), false)
			eq(ns.MapNames.CanEdit(), false)
			local c = setmetatable({ On = function() end, RegisterEvent = function() end,
				Consent = { Register = function() end }, Comm = { Handle = function() end } }, { __index = ns })
			assert(loadfile(H.ADDON_DIR .. "PlayerSightings.lua"))("Olympus", c)
			assert(loadfile(H.ADDON_DIR .. "HopSightings.lua"))("Olympus", c)
			ok, why = c.PlayerSightings.CanRequest()
			eq(ok, false); eq(why, "federation")
			ok, why = c.HopSightings.Request({})
			eq(ok, false); eq(why, "federation")
		end)
	end)
end)
