-- Actual live, unstaked tables on separate fictional clients, then the real paced Comm queue.
local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local N = H.World.NAMES

local function Roster(w, c)
	local members = {}
	for _, p in ipairs(w.clients) do if p.guild == c.guild then members[#members + 1] = p end end
	c.globals.GetNumGuildMembers = function() return #members, #members end
	c.globals.GetGuildRosterInfo = function(i)
		local p = members[i]
		if p then return p.name, p.rankName, p.rank, 60, "Mage", "Elwynn Forest", "", "", true, "", "MAGE" end
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

local function Live(native)
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
	for _, c in ipairs({ a, b, s }) do Roster(w, c); if native ~= false then Native(w, c) end end
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

local function Watch(w, c, rooms)
	w:As(c, function()
		assert(loadfile(H.ADDON_DIR .. "Watch.lua"))("Olympus", c.ns)
		assert(loadfile(H.ADDON_DIR .. "WatchChat.lua"))("Olympus", c.ns)
		assert(loadfile(H.ADDON_DIR .. "ArenaChat.lua"))("Olympus", c.ns)
		assert(c.ns.ArenaChat.Open(rooms.players)); assert(c.ns.ArenaChat.Open(rooms.everyone))
	end)
end

test("Bones chat core: real WatchChat deletion keeps the registered surface's native replay hidden after dedupe expires", function()
	local w, a, b, _, _, rooms = Live()
	b.rank = 0; Roster(w, b); Watch(w, b, rooms)
	eq(w:As(b, b.ns.WatchChat.HoldsChat, rooms.players), true)
	eq(w:As(a, a.ns.ArenaChat.Send, rooms.players, "deleted actual words"), true); Drain(w, a)
	local e = w:As(b, b.ns.ArenaChat.Lines, rooms.players)[1]
	local id, text = e.id, e.text
	local deleted, why = w:As(b, b.ns.WatchChat.Delete, rooms.players, e, "actual guild moderation")
	eq(deleted, true, why); eq(e.del, true)
	eq(w:As(b, b.ns.WatchChat.Tombstoned, rooms.players, a.name, id, text), true)
	w.clock = w.clock + 121
	w:As(a, a.globals.C_ChatInfo.SendAddonMessageLogged, a.ns.PREFIX, "EC~L1~" .. rooms.players .. "~" .. id .. "~MA~" .. a.guild .. "~" .. text, "WHISPER", b.short)
	eq(#w:As(b, b.ns.ArenaChat.Lines, rooms.players), 0, "retained day-long real tombstone, not old 120s dedupe")
	eq(#b.ns.ArenaChat.Room(rooms.players).lines, 1, "no second stored replay")
end)

test("Bones chat core: even a known legacy arbiter table's Players audience is exactly the two players", function()
	local w, a, b, _, id, rooms = Live()
	local king = w:Find(N.king)
	eq(w:As(a, a.ns.ArenaRoles.IsArbiter, king.name, "L"), true, "real pinned King's existing arbiter role")
	-- A legacy known table model can carry an arbiter although current free-table creation
	-- needs none. The field cannot extend the requested two-player conversation audience.
	a.ns.FarkleTable.Get(id).arbiter = king.name
	b.ns.FarkleTable.Get(id).arbiter = king.name
	eq(#w:As(a, a.ns.ArenaChat.Party, w:As(a, a.ns.ArenaChat.Event, rooms.players)), 2)
	eq(w:As(a, a.ns.ArenaChat.MayRead, rooms.players, king.name), false)
	eq(w:As(a, a.ns.ArenaChat.MayRead, rooms.everyone, king.name), true)
	eq(w:As(a, a.ns.ArenaChat.Send, rooms.players, "two players only"), true); Drain(w, a)
	eq(Count(w, "EC"), 1); eq(w.sent[1].target, b.short)
end)

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

test("Bones chat core: rejected hostile EC keeps bounded room metadata without resetting rate or dedupe", function()
	local w, a, b, _, _, rooms = Live()
	local function NativeLine(kind, body)
		w:As(a, a.globals.C_ChatInfo.SendAddonMessageLogged, a.ns.PREFIX, kind .. "~L1~" .. body, "WHISPER", b.short)
	end
	local function Size(map) local n = 0 for _ in pairs(map) do n = n + 1 end return n end
	for i = 1, 1100 do NativeLine("EC", rooms.players .. "~" .. i .. "~MA~" .. a.guild .. "~hostile " .. i) end
	local r = b.ns.ArenaChat.Room(rooms.players)
	eq(#r.lines, 6, "actual Admit sender token bucket, not replacement test logic")
	eq(Size(r.seen) <= 512, true, "rejected unique messages are bounded")
	eq(r.buckets[a.name].tokens, 0)
	local first = a.name .. "#1#hostile 1"
	eq(r.seen[first], w.clock, "no clearing a live dedupe window to admit another sender")
	NativeLine("EC", rooms.players .. "~1~MA~" .. a.guild .. "~hostile 1")
	eq(#r.lines, 6); eq(r.buckets[a.name].tokens, 0)
	-- Expiry frees only old cache entries. A fully replenished legitimate author may speak again.
	w.clock = w.clock + 121
	NativeLine("EC", rooms.players .. "~1~MA~" .. a.guild .. "~hostile 1")
	eq(#r.lines, 7); eq(Size(r.seen), 1); eq(r.buckets[a.name].tokens, 5)
end)

test("Bones chat core: arbitrary canonical-host EM subjects are capped without expiring or evicting current mutes", function()
	local w, a, b, _, _, rooms = Live()
	for i = 1, 240 do
		-- Refill the real transport bucket rather than bypass its admission check.
		w.clock = w.clock + 0.5
		local who = "Guest" .. string.char(65 + math.floor(i / 26)) .. string.char(65 + i % 26) .. "-" .. a.realm
		w:As(a, a.globals.C_ChatInfo.SendAddonMessageLogged, a.ns.PREFIX, "EM~L1~" .. rooms.players .. "~" .. who .. "~1", "WHISPER", b.short)
	end
	local r, count = b.ns.ArenaChat.Room(rooms.players), 0
	for _ in pairs(r.muted) do count = count + 1 end
	eq(count, 100, "bounded mute identities, no eviction lets a muted author return")
	eq(r.muted[("GuestAB-" .. a.realm):lower()], true)
	w:As(a, a.globals.C_ChatInfo.SendAddonMessageLogged, a.ns.PREFIX, "EM~L1~" .. rooms.players .. "~GuestAB-" .. a.realm .. "~0", "WHISPER", b.short)
	eq(r.muted[("GuestAB-" .. a.realm):lower()], nil, "authorized lift still works at cap")
end)

test("Bones chat core: actual Concede sends the final existing state to its watcher before stopping relay", function()
	local w, a, b, s, id, rooms = Live(false)
	eq(w:As(s, s.ns.FarkleTable.ChatSpec, id).live, true)
	assert(w:As(a, a.ns.FarkleTable.Concede, id)); w:Run(3)
	eq(Count(w, "KN") >= 1, true, "closing existing notice")
	eq(Count(w, "KS") >= 1, true, "final existing watcher state")
	for _, c in ipairs({ a, b, s }) do
		eq(w:As(c, c.ns.ArenaChat.TableRooms, id), nil, c.name)
		eq(w:As(c, c.ns.ArenaChat.MayRead, rooms.everyone), false)
		eq(#w:As(c, c.ns.ArenaChat.Lines, rooms.everyone), 0)
	end
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
