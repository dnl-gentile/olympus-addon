-- Actual live, unstaked tables on separate fictional clients, then the real paced Comm queue.
local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local N = H.World.NAMES

local function Roster(w, c)
	c.globals.GetNumGuildMembers = function() return #w.clients, #w.clients end
	c.globals.GetGuildRosterInfo = function(i)
		local p = w.clients[i]
		if p then return p.name, "Member", 3, 60, "Mage", "Elwynn Forest", "", "", true, "", "MAGE" end
	end
	w:As(c, function()
		assert(loadfile(H.ADDON_DIR .. "Roster.lua"))("Olympus", c.ns)
		assert(c.ns.Roster.Scan()); assert(c.ns.Roster.Fresh())
	end)
end

local function Native(w, c)
	local handlers, login = c.comm.handlers
	local function Deliver(logged, prefix, text, dist, target)
		w.sent[#w.sent + 1] = { from = c.name, msg = text, dist = dist, target = target, logged = logged }
		for _, peer in ipairs(w:Recipients(c, dist, target)) do
			if peer.realComm then
				w:Fire(peer, logged and "CHAT_MSG_ADDON_LOGGED" or "CHAT_MSG_ADDON", prefix, text, dist, c.name, target, nil, 7, peer.ns.Comm.ChannelName())
			else
				local fn = peer.comm.handlers[text:sub(1, 2)]
				if fn then
					local old = w.logged; w.logged = logged
					w:As(peer, fn, dist, c.name, text); w.logged = old
				end
			end
		end
		return 0
	end
	c.globals.GetChannelName = function() return 7, "Olympus" end
	c.globals.C_ChatInfo = {
		RegisterAddonMessagePrefix = function() return true end,
		SendAddonMessage = function(...) return Deliver(false, ...) end,
		SendAddonMessageLogged = function(...) return Deliver(true, ...) end,
	}
	w:As(c, function()
		local on, after, every = c.ns.On, c.ns.After, c.ns.Every
		c.ns.On = function(event, fn) if event == "LOGIN" then login = fn end end
		assert(loadfile(H.ADDON_DIR .. "Comm.lua"))("Olympus", c.ns)
		c.ns.On = on
		for kind, fn in pairs(handlers) do c.ns.Comm.Handle(kind, fn) end
		c.ns.After, c.ns.Every = function() end, function() end
		assert(login); login(); c.ns.Comm.JoinChannel()
		c.ns.After, c.ns.Every = after, every
	end)
	c.realComm = true
end

local function Live()
	local w = FW.New()
	local king = w:Role("king", { companion = { state = "missing" } })
	local a, b, s = w:Player(N.fighterA), w:Player(N.fighterB), w:Player(N.bettor1)
	assert(king.Roles.SetSettings({ live = 1 })); w:Run(0)
	for _, c in ipairs({ a, b, s }) do c.Arena.SetRules(true) end
	w:Group({ a, b }); w:AtInn(a.name, b.name)
	local id = assert(w:As(a, a.ns.FarkleTable.Create, { guest = b.name, target = 2000, secs = 120 }))
	w:Run(0); assert(w:As(b, b.ns.FarkleTable.Answer, id, true)); w:Run(0)
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	w:As(a, a.ns.FarkleTable.Roll, id); w:As(b, b.ns.FarkleTable.Roll, id); w:Run(0)
	assert(w:As(s, s.ns.FarkleTable.Watch, id)); w:Run(0)
	for _, c in ipairs({ a, b, s }) do Roster(w, c); Native(w, c) end
	local rooms = assert(w:As(a, a.ns.ArenaChat.TableRooms, id))
	for _, c in ipairs({ a, b, s }) do assert(w:As(c, c.ns.ArenaChat.Open, rooms.everyone)) end
	w.sent = {}
	return w, a, b, s, id, rooms
end

local function Drain(w, ...)
	for _ = 1, 8 do
		w.clock = w.clock + 1.2
		for _, c in ipairs({ ... }) do w:As(c, c.ns.Comm.Pump) end
	end
end
local function Count(w, kind)
	local n = 0
	for _, p in ipairs(w.sent) do if p.msg:sub(1, 2) == kind then n = n + 1 end end
	return n
end

test("Bones chat core: real two-player Players whispers and verified ordinary-member Everyone on the public logged lane", function()
	local w, a, b, s, id, rooms = Live()
	eq(#id <= 16, true); eq(#rooms.everyone <= 20, true)
	eq(w:As(s, s.ns.ArenaChat.MayRead, rooms.players), false)
	eq(w:As(s, s.ns.ArenaChat.Open, rooms.players), nil)
	eq(w:As(a, a.ns.ArenaChat.Send, rooms.players, "Players only"), true)
	Drain(w, a)
	eq(#w:As(b, b.ns.ArenaChat.Lines, rooms.players), 1)
	eq(#w:As(s, s.ns.ArenaChat.Lines, rooms.players), 0)
	eq(s.ns.ArenaChat.Room(rooms.players), nil, "spectator never allocates private lines")
	for _, p in ipairs(w.sent) do eq(p.dist, "WHISPER"); eq(p.target, b.short); eq(p.logged, true) end
	w.sent = {}
	eq(w:As(s, s.ns.ArenaChat.MaySend, rooms.everyone), true, "ordinary member, not officer")
	eq(w:As(s, s.ns.ArenaChat.Send, rooms.everyone, "Everyone cheers"), true)
	Drain(w, s)
	for _, c in ipairs({ a, b, s }) do
		eq(#w:As(c, c.ns.ArenaChat.Lines, rooms.everyone), 1, table.concat(c.errors, "\n"))
		eq(w:As(c, c.ns.ArenaChat.Lines, rooms.everyone)[1].chat, rooms.everyone)
	end
	eq(Count(w, "EC"), 1); eq(w.sent[1].dist, "CHANNEL"); eq(w.sent[1].logged, true)
end)

test("Bones chat core: unknown, private spectator injection, unverified census and wrong public lanes never allocate", function()
	local w, a, b, s, _, rooms = Live()
	local function Inject(c, room, dist, sender, id)
		return w:As(c, c.ns.ArenaChat.OnChat, dist, sender, "L", room .. "~" .. id .. "~MA~" .. a.guild .. "~untrusted")
	end
	-- Invoke through the real logged delivery so the test probes authorization, not the logging gate.
	w:As(a, a.ns.Comm.Whisper, s.name, "EC~L1~" .. rooms.players .. "~120~MA~" .. a.guild .. "~private injection", nil, false, true)
	Drain(w, a)
	eq(s.ns.ArenaChat.Room(rooms.players), nil)
	eq(w:As(s, s.ns.ArenaChat.Open, "Knotknown:all"), nil)
	eq(s.ns.ArenaChat.Room("Knotknown:all"), nil)
	eq(Inject(s, rooms.everyone, "GUILD", a.name, 122), false)
	w:As(a, a.ns.Comm.Send, "GUILD", "EC~L1~" .. rooms.everyone .. "~123~MA~" .. a.guild .. "~wrong lane", nil, false, true)
	Drain(w, a); eq(#w:As(s, s.ns.ArenaChat.Lines, rooms.everyone), 0)
	s.ns.Roster.complete = false
	eq(w:As(s, s.ns.ArenaChat.MaySend, rooms.everyone), false, "claim or census cannot replace fresh same-guild proof")
	eq(w:As(s, s.ns.ArenaChat.Send, rooms.players, "spectator"), false)
end)

test("Bones chat core: real delayed Comm queue cancels revoked rules, ended table and spectator audience before native send", function()
	for _, revoke in ipairs({ "rules", "end", "spectators", "member", "audience", "lane" }) do
		local w, a, _, _, id, rooms = Live()
		local room = revoke == "spectators" and rooms.everyone or rooms.players
		eq(w:As(a, a.ns.ArenaChat.Send, room, "queued then revoked"), true)
		eq(Count(w, "EC"), 0, "not yet native")
		if revoke == "rules" then a.Arena.SetRules(false)
		elseif revoke == "end" then a.ns.FarkleTable.Get(id).closed = true
		elseif revoke == "spectators" then a.ns.FarkleTable.Get(id).noWatch = true
		elseif revoke == "member" then a.guild = nil
		elseif revoke == "audience" then a.ns.FarkleTable.Get(id).guest = N.bettor2
		else a.ns.FarkleTable.Get(id).mode = "T" end
		Drain(w, a); eq(Count(w, "EC"), 0, revoke)
	end
end)

test("Bones chat core: native version1 drops unknown suffixes and mixed-protocol envelopes without leaking private lines", function()
	local w, a, b, s, _, rooms = Live()
	w:As(a, a.ns.Comm.Whisper, b.name, "EC~L2~" .. rooms.players .. "~140~MA~" .. a.guild .. "~unsupported protocol", nil, false, true)
	w:As(a, a.ns.Comm.Whisper, s.name, "EC~L1~" .. rooms.players .. ":players~141~MA~" .. a.guild .. "~invented room", nil, false, true)
	Drain(w, a)
	eq(#w:As(b, b.ns.ArenaChat.Lines, rooms.players), 0)
	eq(s.ns.ArenaChat.Room(rooms.players .. ":players"), nil)
	-- A pre-feature client resolves EC rooms only through the existing EventOf registry:
	-- Everyone is not an event ID, while the unchanged Players ID remains understood.
	eq(w:As(b, b.Arena.EventOf, rooms.everyone), nil)
	eq(w:As(b, b.Arena.EventOf, rooms.players).kind, "farkle")
end)

test("Bones chat core: slow mode, sender mutes, deleted lines and public net-off remain enforced", function()
	local w, a, b, s, _, rooms = Live()
	eq(w:As(a, a.ns.ArenaChat.Send, rooms.players, "first"), true)
	local ok, why = w:As(a, a.ns.ArenaChat.Send, rooms.players, "too fast")
	eq(ok, false); eq(why, "fast")
	Drain(w, a)
	eq(w:As(a, a.ns.ArenaChat.Mute, rooms.everyone, s.name, true), true)
	Drain(w, a)
	eq(w:As(s, s.ns.ArenaChat.MaySend, rooms.everyone), false)
	local entry = w:As(b, b.ns.ArenaChat.Lines, rooms.players)[1]
	entry.del = true
	eq(#w:As(b, b.ns.ArenaChat.Lines, rooms.players), 0)
	-- The actual moderation gate stays in the send path; there is no embed bypass.
	s.ns.WatchChat = { SelfTimeout = function() return true end }
	local allowed, reason = w:As(s, s.ns.ArenaChat.MaySend, rooms.everyone)
	eq(allowed, false); eq(reason, "timeout")
end)

test("Bones chat core: real Comm queue rejection does not claim a local delivered line", function()
	local w, a, _, _, _, rooms = Live()
	w:As(a, function()
		while a.ns.Comm.ChatRoom() > 0 do assert(a.ns.Comm.SendChat("EC~L1~other~1~MA~" .. a.guild .. "~filler")) end
	end)
	eq(w:As(a, a.ns.ArenaChat.Send, rooms.everyone, "not admitted"), false)
	eq(#w:As(a, a.ns.ArenaChat.Lines, rooms.everyone), 0)
end)
