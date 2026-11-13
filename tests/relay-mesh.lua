-- 1.5.5: the mesh between the signed relays (Relay.lua: Relay.Mesh, RJ, Relay.MeshPeer, what crosses,
-- the staff words by RW, the trust of the hop, /oly bug's lines). On WoW: Forever every live relay was an
-- island: a relay's own client counts itself as answered (Relay.Pick), so it never pinged another one,
-- none learned that another answered, and Across reached nobody; the author's census and his words
-- reached only the guilds registered with the relay that heard them. Real Comm and Relay on every
-- client; only Blizzard's wire and timers are simulated (as tests/verify-mesh.lua). Fake names only.
-- Every test here is named "relay mesh (1.5.5): ..." and fails without the mesh.
local ns, test, eq, extra = ...
local RelayWorld = extra.RelayWorld
local T0 = 1794100000
local A_NAME, B_NAME, C_NAME = "Max Ran-Realm", "Hildryn Payne-Realm", "Third Relay-Realm" -- all three signed (the council)

-- Clients of one realm group, their whispers and guild words carried by Flush, their timers by Advance.
local function World(fn)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo }
	local nodes, timers, now = {}, {}, T0
	GetChannelName = function() return 0 end
	ns.IsMember = function() return true end
	IsInGuild = function() return true end
	local function As(n, f, ...)
		C_ChatInfo = n.chat
		GetGuildInfo = function() return n.guild, "Member", 3 end
		return f(...)
	end
	-- relayFile (1.5.9): another release's Relay.lua (tests/fixtures/relay-1.5.8.lua: a mesh peer on 1.5.8).
	local function Node(name, guild, relayFile)
		local c, deliver, sent, heard, pump = RelayWorld(name, guild, relayFile)
		local n = { c = c, deliver = deliver, sent = sent, heard = heard, pump = pump, guild = guild,
			chat = C_ChatInfo, cursor = 0, got = {}, logs = {} }
		c.Log = function(fmt, ...) local ok, msg = pcall(string.format, fmt, ...) n.logs[#n.logs + 1] = ok and msg or tostring(fmt) end
		c.clock, c.realm = now, "Realm"
		c.rdb.council.names["third relay"] = "Third Relay"
		c.Relay.PRESENT_REQUIRED_AT = T0 + 30 * 86400 -- (every client served: the presentation has its own suite)
		c.IsKingCharacter = function() return false end
		c.After = function(delay, _, f) timers[#timers + 1] = { at = now + delay, n = n, f = f } end
		c.Every = function() end
		-- What each client takes, of the kinds these tests send (as if heard on the channel).
		for _, kind in ipairs({ "CG", "D1", "V4", "TA", "CX", "RE", "T1" }) do
			c.Comm.Handle(kind, function(dist, sender, text) n.got[#n.got + 1] = { dist = dist, sender = sender, text = text } end)
		end
		nodes[#nodes + 1] = n
		return n
	end
	local function Flush()
		for _ = 1, 80 do
			local moved = false
			for _, n in ipairs(nodes) do
				As(n, n.pump, 40)
				while n.cursor < #n.sent do
					n.cursor = n.cursor + 1
					local p = n.sent[n.cursor]
					for _, to in ipairs(nodes) do
						if to ~= n and ((p.dist == "WHISPER" and ns.ShortName(to.c.me) == ns.ShortName(p.target or ""))
							or (p.dist == "GUILD" and to.guild == n.guild)) then
							As(to, to.deliver, p.dist, n.c.me, p.msg); moved = true
						end
					end
				end
			end
			if not moved then return end
		end
		error("the relay wire did not settle")
	end
	local function Advance(seconds)
		now = now + seconds
		for _, n in ipairs(nodes) do n.c.clock = now end
		local due = timers; timers = {}
		for _, t in ipairs(due) do
			if t.at <= now then As(t.n, t.f) else timers[#timers + 1] = t end
		end
		Flush()
	end
	local ok, err = pcall(fn, Node, As, Flush, Advance)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end

-- The node's sends that start with prefix (to target, when named).
local function Count(n, prefix, target)
	local k = 0
	for _, p in ipairs(n.sent) do
		if p.msg:sub(1, #prefix) == prefix and (target == nil or ns.ShortName(p.target or "") == ns.ShortName(target)) then k = k + 1 end
	end
	return k
end
-- What the node took of this text (the kinds World records), or nil.
local function Took(n, text)
	for _, g in ipairs(n.got) do if g.text == text then return g end end
end
-- A word of exactly `pieces` full pieces.
local function Word(head, pieces) return (head .. ("x"):rep(ns.Codec.CHUNK * pieces)):sub(1, ns.Codec.CHUNK * pieces) end
-- A relay's own word in pieces, as Relay.Out hands its own client's words to it.
local function Own(n, As, word, id)
	for _, p in ipairs(ns.Codec.Chunk(word, id)) do As(n, n.c.Relay.HandleIn, "WHISPER", n.c.me, "RL~P~" .. p) end
end
-- A client's word in pieces, whispered to relay n.
local function From(n, As, sender, word, id)
	for _, p in ipairs(ns.Codec.Chunk(word, id)) do As(n, n.deliver, "WHISPER", sender, "RL~P~" .. p) end
end
local function Register(relay, As, member, guild) As(relay, relay.deliver, "WHISPER", member, "RL~P~RR~" .. guild) end
local function Mesh(n, As) if n.c.Relay.Mesh then return As(n, n.c.Relay.Mesh) end end

test("relay mesh (1.5.6): answered mesh-capable bridges are preferred to public 1.5.5, which remains a fallback", function()
	World(function(Node, As)
		local m = Node("Bridge Picker-Realm", "Olympus Pick")
		local R = m.c.Relay
		As(m, m.deliver, "WHISPER", A_NAME, "RY~1.5.5")
		eq(As(m, R.Pick), ns.ShortName(A_NAME), "the older bridge still carries words when it is the only answer")
		As(m, m.deliver, "WHISPER", B_NAME, "RY~1.5.6")
		for i = 1, 64 do
			m.guild = "Olympus Mixed Bridge " .. i
			eq(As(m, R.Pick), ns.ShortName(B_NAME), "guild " .. i .. " uses the bridge with the recovered mesh")
		end
		As(m, R.LeaveOut, B_NAME, "offline in the mixed-version simulation")
		eq(As(m, R.Pick), ns.ShortName(A_NAME), "losing the new bridge restores the answered older fallback")
	end)
end)

test("relay mesh: default published versions admit the release and its test builds while explicit relay rules retain their authority", function()
	World(function(Node)
		local m = Node("Release Member-Realm", "Olympus Release")
		local R = m.c.Relay
		eq(R.Published("1.5.9"), true)
		eq(R.Published("1.5.9-test.1"), true)
		eq(R.Published("1.5.8"), true, "the previous public release remains admitted")
		eq(R.Published("1.5.10"), false, "a future unpublished release is not admitted")
		m.c.rdb.relayRules = { rev = 1, on = true, at = T0, versions = { "1.5.5" } }
		eq(R.Published("1.5.9"), false, "a retained author-issued version list still takes precedence")
		eq(R.Published("1.5.5"), true)
	end)
end)

test("relay mesh (1.5.5): two signed relays mesh after Relay.Mesh(): each is the other's mesh peer, and one relay's own census snapshot reaches the other relay's registrant whole", function()
	World(function(Node, As, Flush, Advance)
		local a, b = Node(A_NAME, "Olympus Alpha"), Node(B_NAME, "Olympus Beta")
		local reg = Node("Reg One-Realm", "Olympus Gamma")
		Register(b, As, reg.c.me, "Olympus Gamma")
		Mesh(a, As); Mesh(b, As)
		Flush(); Advance(a.c.Relay.PING_WAIT + 1)
		eq(As(a, a.c.Relay.MeshPeer, B_NAME), true, "B is A's mesh peer")
		eq(As(b, b.c.Relay.MeshPeer, A_NAME), true, "A is B's mesh peer")
		eq(Count(a, "RJ~1~", B_NAME) >= 1 and Count(b, "RJ~1~", A_NAME) >= 1, true, "each told the other (RJ)")
		local word = Word(("CG~2~S~%d~ForeverPvE~Alliance~"):format(T0), 3)
		Own(a, As, word, "61")
		Flush(); Advance(2)
		local took = Took(reg, word)
		assert(took, "the other relay's registrant holds A's own snapshot, whole")
		eq(took.sender, A_NAME, "under its origin, the relay that made it")
	end)
end)

test("relay mesh (1.5.5): only a closed set crosses to a mesh peer: no client's report pieces, no member's snapshot; the relay's own snapshot once a MESH_CROSS_EVERY; a chat line; and nothing to a relay that answered a ping but never sent RJ", function()
	World(function(Node, As, Flush, Advance)
		local a, b, c = Node(A_NAME, "Olympus Alpha"), Node(B_NAME, "Olympus Beta"), Node(C_NAME, "Olympus Gamma")
		c.c.Comm.Handle("RJ", nil) -- (a 1.5.4 relay: it answers a ping, and has no handler for RJ)
		Mesh(a, As); Mesh(b, As)
		Flush(); Advance(a.c.Relay.PING_WAIT + 1)
		eq(As(a, a.c.Relay.MeshPeer, B_NAME), true)
		assert(a.c.Relay.RelayVersion("Third Relay"), "C answered A's ping")
		eq(As(a, a.c.Relay.MeshPeer, C_NAME), false, "but never joined the mesh: no mesh peer")
		local base = Count(a, "RX~", B_NAME)
		From(a, As, "Rep Orter-Realm", Word("R2~", 3), "71")
		From(a, As, "Mem Ber-Realm", Word(("CG~1~S~%d~"):format(T0), 30), "72")
		Flush(); Advance(2)
		eq(Count(a, "RX~", B_NAME), base, "a client's report and a member's 30-piece snapshot stay on A's island")
		local s1 = Word(("CG~2~S~%d~ForeverPvE~Alliance~one"):format(T0), 3)
		Own(a, As, s1, "73"); Flush(); Advance(2)
		local once = Count(a, "RX~", B_NAME) - base
		eq(once > 0, true, "A's own snapshot crosses")
		assert(Took(b, s1), "and B takes it whole")
		local s2 = Word(("CG~2~S~%d~ForeverPvE~Alliance~two"):format(T0), 3)
		Own(a, As, s2, "74"); Flush(); Advance(2)
		eq(Count(a, "RX~", B_NAME) - base, once, "a second one within MESH_CROSS_EVERY does not")
		Advance(a.c.Relay.MESH_CROSS_EVERY)
		local s3 = Word(("CG~2~S~%d~ForeverPvE~Alliance~three"):format(T0), 3)
		Own(a, As, s3, "75"); Flush(); Advance(2)
		eq(Count(a, "RX~", B_NAME) - base, 2 * once, "the next one, MESH_CROSS_EVERY later, does")
		assert(Took(b, s3) and not Took(b, s2), "B holds the first and the third")
		As(a, a.deliver, "WHISPER", "Chat Ter-Realm", "RL~L~M1~A~Olympus Alpha~1~~hello across")
		Flush()
		eq(Count(a, "RX~L~Chat Ter-Realm~M1~", B_NAME), 1, "a chat line crosses")
		As(a, a.c.Relay.HandleIn, "WHISPER", a.c.me, "RL~L~D1~1~a logged decree")
		Flush()
		eq(Count(a, "RW~L~" .. A_NAME .. "~D1~1~a logged decree", B_NAME), 1, "A's own logged staff word goes by RW")
		eq(Count(a, "RX~L~" .. A_NAME .. "~D1~"), 0, "and not by RX as well")
		eq(Count(a, "RX~", C_NAME), 0, "nothing ever crosses to the relay that never sent RJ")
	end)
end)

test("relay mesh (1.5.5): a relay's own staff words (T1 but the crown, D1, V4, TA, CX, RE) go to every other signed relay by RW, answered or not, and past the trickle to each one's registrants, never further; the crown never as RW; one naming another origin is dropped", function()
	World(function(Node, As, Flush)
		local a, b, c = Node(A_NAME, "Olympus Alpha"), Node(B_NAME, "Olympus Beta"), Node(C_NAME, "Olympus Gamma")
		local reg = Node("Reg One-Realm", "Olympus Delta")
		Register(b, As, reg.c.me, "Olympus Delta")
		for i = 1, 6 do As(b, b.deliver, "WHISPER", "Some Client-Realm", "RL~P~X1~filler " .. i) end
		Flush()
		assert(b.c.Relay.Stats().trickled > 0, "the registrant's trickle is spent")
		local look = ("CX~1~S~%d~ForeverPvP,Alliance,10,10,1,%d"):format(T0, T0)
		local words = { "T1~C~1~call", "D1~1~a decree", "V4~1.5.5~1", "TA~1~an ask", look, "RE~1~L~1~Cand One,Cand Two",
			ns.Codec.Chunk(look .. ";as Comm.SendChunked cuts it", "9")[1] }
		for _, w in ipairs(words) do As(a, a.c.Relay.HandleIn, "WHISPER", a.c.me, "RL~P~" .. w) end
		As(a, a.c.Relay.HandleIn, "WHISPER", a.c.me, "RL~P~T1~P~1~OLYMPUS~1453~420~510")
		Flush()
		for _, w in ipairs(words) do
			eq(Count(a, "RW~P~" .. A_NAME .. "~" .. w, B_NAME), 1, "to B by RW: " .. w)
			eq(Count(a, "RW~P~" .. A_NAME .. "~" .. w, C_NAME), 1, "and to C: " .. w)
			local taken = w:match("^C%w+:1:1:(.*)$") or w -- (a word in one piece is taken whole)
			assert(Took(b, taken) and Took(c, taken), "each takes it: " .. w)
			eq(Count(b, "RM~P~" .. A_NAME .. "~" .. w, "Reg One"), 1, "B's registrant has it past the trickle: " .. w)
			assert(Took(reg, taken), "and takes it: " .. w)
		end
		eq(Count(a, "RW~P~" .. A_NAME .. "~T1~P~"), 0, "the crown never as RW")
		eq(Count(b, "RW~") + Count(b, "RX~") + Count(c, "RW~") + Count(c, "RX~"), 0, "neither sends any of it on")
		eq(As(b, b.c.Relay.MeshPeer, A_NAME), false, "RW makes nobody a mesh peer")
		local dropped = b.c.Relay.Stats().dropped
		As(b, b.deliver, "WHISPER", A_NAME, "RW~P~" .. C_NAME .. "~D1~1~forged")
		Flush()
		eq(Took(b, "D1~1~forged"), nil, "a staff word naming another origin than its sender is not taken")
		eq(Count(b, "RM~P~" .. C_NAME .. "~D1~1~forged"), 0, "nor handed on")
		eq(b.c.Relay.Stats().dropped, dropped + 1)
	end)
end)

test("relay mesh (1.5.5): an unsigned Treasurer code pin is transport alone: no RX is taken from it, and a word it carries comes by no trusted hop (Relay.HopTrusted)", function()
	World(function(Node, As, Flush)
		local b = Node(B_NAME, "Olympus Beta")
		local reg = Node("Reg One-Realm", "Olympus Delta")
		b.c.TreasurerPins = function() return { "Coin Keeper-Realm" }, false end
		Register(b, As, reg.c.me, "Olympus Delta")
		eq(b.c.Relay.IsRelay("Coin Keeper"), true, "a relay (the code's pin)")
		eq(b.c.Relay.IsSignedRelay("Coin Keeper"), false, "but no signed one")
		eq(b.c.Relay.IsSignedRelay(A_NAME), true, "a councillor's is")
		local dropped = b.c.Relay.Stats().dropped
		As(b, b.deliver, "WHISPER", "Coin Keeper-Realm", "RX~P~Far Origin-Realm~X1~by the pin")
		Flush()
		eq(#b.heard, 0, "its RX is not taken"); eq(Count(b, "RM~"), 0, "nor handed to the registrant")
		eq(b.c.Relay.Stats().dropped, dropped + 1)
		As(b, b.deliver, "WHISPER", A_NAME, "RX~P~Far Origin-Realm~X1~by a signed relay")
		Flush()
		eq(#b.heard, 1, "a signed relay's is"); eq(Count(b, "RM~P~Far Origin-Realm~X1~by a signed relay", "Reg One"), 1)
		local trusted = {}
		b.c.Comm.Handle("D1", function() trusted[#trusted + 1] = tostring(b.c.Relay.HopTrusted()) end)
		local hops = { { "M", "Coin Keeper-Realm" }, { "M", A_NAME }, { "X", "Coin Keeper-Realm" }, { "X", A_NAME },
			{ "T", "Coin Keeper-Realm" }, { "O", A_NAME }, { "G", "Coin Keeper-Realm" }, { "W", A_NAME } }
		for i, h in ipairs(hops) do As(b, b.c.Relay.TakeVia, h[1], h[2], "Far Origin-Realm", "D1~" .. i) end
		eq(table.concat(trusted, ","), "false,true,false,true,false,false,true,true",
			"M, X and T trusted from a signed relay alone; O never; the others as before")
		eq(b.c.Relay.HopTrusted(), true, "no hop (a direct call): trusted")
	end)
end)

test("relay mesh (1.5.5): a relay's own census claim (CG~n~C~) and ask (CG~n~Q~) are heard there alone, never fanned out to its registrants; its own snapshot still is", function()
	World(function(Node, As, Flush)
		local a = Node(A_NAME, "Olympus Alpha")
		local reg = Node("Reg One-Realm", "Olympus Delta")
		Register(a, As, reg.c.me, "Olympus Delta")
		As(a, a.c.Relay.HandleIn, "WHISPER", a.c.me, ("RL~P~CG~2~C~%d"):format(T0))
		As(a, a.c.Relay.HandleIn, "WHISPER", a.c.me, ("RL~P~CG~1~Q~%d~0~0"):format(T0))
		Flush()
		eq(Count(a, "RM~"), 0, "neither the claim nor the ask reaches a registrant")
		local snap = ("CG~2~S~%d~ForeverPvE~Alliance~Olympus Delta,100,10,30,%d"):format(T0, T0)
		As(a, a.c.Relay.HandleIn, "WHISPER", a.c.me, "RL~P~" .. snap)
		Flush()
		eq(Count(a, "RM~P~" .. A_NAME .. "~" .. snap, "Reg One"), 1, "its own snapshot still does")
		assert(Took(reg, snap))
	end)
end)

test("relay mesh (1.5.5): a fresh registration from a tree-capable registrant keeps its guild over a later one from a guildmate that is not; past REPORTER_FOR the other takes it", function()
	World(function(Node, As)
		local a = Node(A_NAME, "Olympus Alpha")
		a.c.Relay.TreeCapable = function(name) return ns.ShortName(name or "") == "Tree Mate" end
		local function Holder()
			for _, r in ipairs(a.c.Relay.Reporters()) do if r.guild == "Olympus Pair" then return ns.ShortName(r.name) end end
		end
		Register(a, As, "Tree Mate-Realm", "Olympus Pair")
		eq(Holder(), "Tree Mate")
		a.c.clock = a.c.clock + 60
		Register(a, As, "Plain Mate-Realm", "Olympus Pair")
		eq(Holder(), "Tree Mate", "a guildmate that is not tree-capable does not take a fresh tree-capable registration's place")
		a.c.clock = a.c.clock + a.c.Relay.REPORTER_FOR + 1
		Register(a, As, "Plain Mate-Realm", "Olympus Pair")
		eq(Holder(), "Plain Mate", "once that registration is stale, it does")
		Register(a, As, "Tree Mate-Realm", "Olympus Pair")
		eq(Holder(), "Tree Mate", "a tree-capable one takes any registration's place, as every one did")
	end)
end)

test("relay mesh (1.5.5): while the relays carry the channel (Relay.On), the lane never moves (InvalidChannel x LANE_AFTER, a Lord's hello) and no census ask (Q1) is said; off Forever the lane moves as before", function()
	local saved = { channel = GetChannelName, join = JoinChannelByName, leave = LeaveChannelByName, member = ns.IsMember,
		guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo }
	local ok, err = pcall(function()
		local indexes = { OlympusNet = 5, OlympusNet1 = 6, OlympusNet2 = 7 }
		GetChannelName = function(name) return indexes[name] or 0 end
		JoinChannelByName, LeaveChannelByName = function() end, function() end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		for _, forever in ipairs({ true, false }) do
			local R, deliver, sent = RelayWorld("Lane Keeper-Realm", "Olympus II")
			R.Roster = setmetatable({ RankOf = function(name) return name == "Lord-Realm" and 0 or nil end }, { __index = ns.Roster })
			if not forever then R.splitNames = false end
			eq(R.Relay.On(), forever)
			-- No relay to pick (both left out): only off Forever does a channel word become a native job.
			R.Relay.LeaveOut("Max Ran"); R.Relay.LeaveOut("Hildryn Payne")
			eq(R.Relay.Pick(), nil)
			C_ChatInfo.SendAddonMessage = function(_, msg, dist, target)
				sent[#sent + 1] = { msg = msg, dist = dist, target = target }
				return dist == "CHANNEL" and 7 or 0
			end
			local C = R.Comm
			C.JoinChannel()
			for i = 1, C.LANE_AFTER do C.Send("CHANNEL", "Y" .. i .. "~r"); C.Pump() end
			eq(C.Lane(), forever and 0 or 1, forever and "refusals never move the lane while the relays carry it" or "off Forever: the next lane")
			deliver("GUILD", "Lord-Realm", "H1~1.4.1~Realm~p~z~b~L2")
			eq(C.Lane(), forever and 0 or 2, forever and "nor a Lord's hello" or "off Forever: a Lord's lane is taken")
			local before = #sent
			C.AskCensus(true)
			for _ = 1, 5 do C.Pump() end
			local asked = 0
			for i = before + 1, #sent do if sent[i].msg:find("Q1~", 1, true) then asked = asked + 1 end end
			eq(asked, forever and 0 or 1, forever and "no census ask while the relays carry the channel" or "off Forever: asked")
		end
	end)
	GetChannelName, JoinChannelByName, LeaveChannelByName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo =
		saved.channel, saved.join, saved.leave, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end)

test("relay mesh (1.5.5): an author's launch character the signed list does not name makes the relay rules and hands them out, and a relay takes them from him", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local PVP = "CAMWOWUS1Realm8PvP"
		local function PvP(me, pins)
			local R, deliver, sent = RelayWorld(me .. "-" .. PVP, "Olympus II")
			R.realm = PVP
			R.Relay.LAUNCH_PINS = { ForeverPvP = pins }
			R.Relay.LAUNCH_AUTHOR = { ForeverPvP = { "Pin Author" } } -- (fake pins: the code's are real names)
			local said = {}
			R.Print = function(m) said[#said + 1] = m end
			return R, deliver, sent, said
		end
		local D, _, dsent = PvP("Pin Author", { "Pin Author" })
		eq(D.Relay.IsLaunchAuthor(D.me), true)
		eq(D.Relay.Slash("rules on 2026-11-16 1.5.4,1.5.5"), true, "he makes the rules")
		local r = D.rdb.relayRules
		eq(r.rev, 1); eq(table.concat(r.versions, ","), "1.5.4,1.5.5"); eq(r.from, "Pin Author")
		for _ = 1, 20 do D.Comm.Pump() end
		local ru
		for _, p in ipairs(dsent) do if p.msg:find("^RU~1~1~") and p.target == "Max Ran" then ru = p.msg end end
		assert(ru, "and hands them to the relays")
		eq(D.Relay.SendRules(true), true, "again at login and every RULES_EVERY")
		-- A relay whose pins name none of his characters (no relay to it) takes them from him.
		local R, rdeliver = PvP("Max Ran", {})
		eq(R.Relay.IsRelay(D.me), false)
		rdeliver("WHISPER", D.me, ru)
		eq(R.Relay.Rules().rev, 1, "taken from him"); eq(R.Relay.Rules().from, "Pin Author")
		-- Anyone else is told only the author makes them.
		local O, _, _, said = PvP("Some Player", { "Pin Author" })
		eq(O.Relay.Slash("rules off"), false); eq(said[#said], ns.L.RELAY_RULES_AUTHOR)
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end)

test("relay mesh (1.5.5): /oly bug's relay lines (Relay.BugLines): the relay, the mesh and the queue within the bytes asked, whatever of the tree, the census counters and the fallback is missing or fails", function()
	World(function(Node, As, Flush, Advance)
		local a, b = Node(A_NAME, "Olympus Alpha"), Node(B_NAME, "Olympus Beta")
		Mesh(a, As); Mesh(b, As)
		Flush(); Advance(a.c.Relay.PING_WAIT + 1)
		local function Bytes(lines) local k = 0 for _, l in ipairs(lines) do k = k + #l + 1 end return k end
		local function Find(lines, prefix) for _, l in ipairs(lines) do if l:sub(1, #prefix) == prefix then return l end end end
		local lines = As(a, a.c.Relay.BugLines, 1500)
		assert(Bytes(lines) <= 1500, "within the bytes: " .. Bytes(lines))
		assert(Find(lines, "relay: "), "the relay line")
		assert(Find(lines, "mesh: ") and Find(lines, "mesh: "):find("Hildryn Payne", 1, true), "the mesh line names the peer")
		assert(Find(lines, "queue: "), "the queue line")
		-- Missing modules, a stand-in (a client that updated without restarting), one that fails: lines
		-- for each, and the rest still there.
		a.c.RelayTree = false
		a.c.RelayFallback = setmetatable({ missing = true }, { __index = function() return function() end end })
		a.c.Data = {}
		lines = As(a, a.c.Relay.BugLines, 1500)
		assert(Find(lines, "relay: ") and Find(lines, "mesh: ") and Find(lines, "queue: "), "the relay's own lines")
		assert(Find(lines, "tree: ") and Find(lines, "fallback: ") and Find(lines, "census: "), "a line for each other part")
		a.c.RelayTree = { Stats = function() error("broken stats") end }
		a.c.Data = { CensusStats = function() local t = {} for i = 1, 400 do t["counter" .. i] = i end return t end }
		lines = As(a, a.c.Relay.BugLines, 1500)
		assert(Find(lines, "tree: ") and Find(lines, "tree: "):find("broken stats", 1, true), "the failure named")
		assert(Bytes(lines) <= 1500, "a long part cut within the bytes: " .. Bytes(lines))
		lines = As(a, a.c.Relay.BugLines, 300)
		assert(Bytes(lines) <= 300 and Find(lines, "relay: "), "fewer bytes: the relay line first")
		eq(Bytes(As(a, a.c.Relay.BugLines)) <= 1500, true, "1500 bytes when none are named")
	end)
end)

-- 1.5.8 (the author, 11-12: "não tá redistribuindo na rede"). Fails before: the author's signed look (QA,
-- two pieces) a relay's client said reached that relay's own guilds alone (Across took no QA), so the
-- PvP look left every other relay's guilds when the author logged off.
test("relay mesh (1.5.8): a relay's own signed look (QA) crosses to a mesh peer whole and reaches its registrant whole past the trickle; a member's QA stays on its relay's island", function()
	World(function(Node, As, Flush, Advance)
		local a, b = Node(A_NAME, "Olympus Alpha"), Node(B_NAME, "Olympus Beta")
		local reg = Node("Reg One-Realm", "Olympus Gamma")
		for _, n in ipairs({ a, b, reg }) do
			n.c.Comm.Handle("QA", function(dist, sender, text) n.got[#n.got + 1] = { dist = dist, sender = sender, text = text } end)
		end
		Register(b, As, reg.c.me, "Olympus Gamma")
		Mesh(a, As); Mesh(b, As)
		Flush(); Advance(a.c.Relay.PING_WAIT + 1)
		eq(As(a, a.c.Relay.MeshPeer, B_NAME), true)
		-- The registrant's trickle spent: a word in pieces through it reaches him whole or not at all.
		for i = 1, 6 do As(b, b.deliver, "WHISPER", "Some Client-Realm", "RL~P~X1~filler " .. i) end
		Flush()
		local base = Count(a, "RX~", B_NAME)
		local member = Word("QA~1~" .. ("m"):rep(86) .. "~CX~3~S~", 2)
		From(a, As, "Mem Ber-Realm", member, "81")
		Flush(); Advance(2)
		eq(Count(a, "RX~", B_NAME), base, "a member's QA is not sent across")
		local qa = Word("QA~1~" .. ("s"):rep(86) .. "~CX~3~S~", 2)
		Own(a, As, qa, "82")
		Flush(); Advance(2)
		eq(Count(a, "RX~", B_NAME) - base > 0, true, "A's own QA crosses to its mesh peer")
		assert(Took(b, qa), "B's client takes it whole")
		local took = Took(reg, qa)
		assert(took, "B's registrant takes it whole")
		eq(took.sender, A_NAME, "under its origin, the relay that said it")
		-- A's census snapshot right after its look (within SNAPSHOT_WINDOW): the look takes no place of it.
		local cg = Word(("CG~2~S~%d~ForeverPvE~Alliance~after the look"):format(T0), 3)
		Own(a, As, cg, "83")
		Flush(); Advance(2)
		assert(Took(b, cg), "B's client takes A's snapshot")
		assert(Took(reg, cg), "and B's registrant takes it whole, past the trickle, though A's look came just before")
	end)
end)

-- 1.5.9 (the census items left from 1.5.8). Fails before: Across took a signed look (QA) only in two or
-- more pieces, so a look with no guild rows (one piece) reached the guilds of the relay that said it alone.
test("relay mesh (1.5.9): a relay's own one-piece signed look (QA) crosses to a mesh peer, one on 1.5.8 too, and reaches its registrant past the trickle; a member's stays on its relay's island", function()
	World(function(Node, As, Flush, Advance)
		local a, b = Node(A_NAME, "Olympus Alpha"), Node(B_NAME, "Olympus Beta")
		local reg = Node("Reg One-Realm", "Olympus Gamma")
		for _, n in ipairs({ a, b, reg }) do
			n.c.Comm.Handle("QA", function(dist, sender, text) n.got[#n.got + 1] = { dist = dist, sender = sender, text = text } end)
		end
		Register(b, As, reg.c.me, "Olympus Gamma")
		Mesh(a, As); Mesh(b, As)
		Flush(); Advance(a.c.Relay.PING_WAIT + 1)
		eq(As(a, a.c.Relay.MeshPeer, B_NAME), true)
		-- The registrant's trickle spent: only a word past it reaches him now.
		for i = 1, 6 do As(b, b.deliver, "WHISPER", "Some Client-Realm", "RL~P~X1~filler " .. i) end
		Flush()
		local base = Count(a, "RX~", B_NAME)
		local member = Word("QA~1~" .. ("m"):rep(86) .. "~CX~3~S~", 1)
		eq(#ns.Codec.Chunk(member, "90"), 1, "a look with no guild rows is one piece")
		From(a, As, "Mem Ber-Realm", member, "91")
		Flush(); Advance(2)
		eq(Count(a, "RX~", B_NAME), base, "a member's one-piece QA is not sent across")
		local qa = Word("QA~1~" .. ("s"):rep(86) .. "~CX~3~S~", 1)
		Own(a, As, qa, "92")
		Flush(); Advance(2)
		eq(Count(a, "RX~", B_NAME) - base > 0, true, "A's own one-piece QA crosses to its mesh peer")
		assert(Took(b, qa), "B's client takes it")
		local took = Took(reg, qa)
		assert(took, "B's registrant takes it, past the spent trickle")
		eq(took.sender, A_NAME, "under its origin, the relay that said it")
	end)
	-- Mixed versions: a mesh peer still on 1.5.8 takes the one-piece look A sends across, as it takes the
	-- pieces of a longer one, and hands it to its registrant past the trickle.
	World(function(Node, As, Flush, Advance)
		local a, b = Node(A_NAME, "Olympus Alpha"), Node(B_NAME, "Olympus Beta", extra.fixtures .. "relay-1.5.8.lua")
		local reg = Node("Reg One-Realm", "Olympus Gamma")
		for _, n in ipairs({ a, b, reg }) do
			n.c.Comm.Handle("QA", function(dist, sender, text) n.got[#n.got + 1] = { dist = dist, sender = sender, text = text } end)
		end
		Register(b, As, reg.c.me, "Olympus Gamma")
		Mesh(a, As); Mesh(b, As)
		Flush(); Advance(a.c.Relay.PING_WAIT + 1)
		eq(As(a, a.c.Relay.MeshPeer, B_NAME), true, "the 1.5.8 relay is a mesh peer")
		eq(b.c.Relay.MAX_SIGNED_LOOKS, nil, "(B runs 1.5.8's Relay.lua)")
		for i = 1, 6 do As(b, b.deliver, "WHISPER", "Some Client-Realm", "RL~P~X1~filler " .. i) end
		Flush()
		local qa = Word("QA~1~" .. ("t"):rep(86) .. "~CX~3~S~", 1)
		Own(a, As, qa, "89")
		Flush(); Advance(2)
		assert(Took(b, qa), "the 1.5.8 relay's client takes it")
		local took = Took(reg, qa)
		assert(took, "and its registrant, past the spent trickle")
		eq(took.sender, A_NAME)
	end)
end)

-- 1.5.9. Fails before: the signed looks in flight (QA, a slot of each relay's own) counted toward the
-- census snapshots' MAX_RELAYS slots: with every relay's look open, a relay's census snapshot found no
-- slot and went piece by piece through the registrant's spent trickle, whole or not at all.
test("relay mesh (1.5.9): signed looks in flight (QA) have their own budget: with every relay's look open, a relay's census snapshot still reaches a registrant whole; the looks' budget holds", function()
	World(function(Node, As, Flush, Advance)
		local a, b, c = Node(A_NAME, "Olympus Alpha"), Node(B_NAME, "Olympus Beta"), Node(C_NAME, "Olympus Delta")
		local reg = Node("Reg One-Realm", "Olympus Gamma")
		Register(b, As, reg.c.me, "Olympus Gamma")
		Mesh(a, As); Mesh(b, As); Mesh(c, As)
		Flush(); Advance(a.c.Relay.PING_WAIT + 1)
		b.c.Relay.MAX_RELAYS = 3 -- (the three relays this realm group knows, one census slot each)
		eq(#b.c.Relay.Names(true), 3, "every relay still known")
		for i = 1, 6 do As(b, b.deliver, "WHISPER", "Some Client-Realm", "RL~P~X1~filler " .. i) end
		Flush()
		-- Each relay's own look open at B: the first of its two pieces, the second still on its way.
		local function FirstPiece(tag, id) return ns.Codec.Chunk(Word("QA~1~" .. tag:rep(86) .. "~CX~3~S~", 2), id)[1] end
		As(b, b.deliver, "WHISPER", A_NAME, "RX~P~" .. A_NAME .. "~" .. FirstPiece("a", "93"))
		As(b, b.deliver, "WHISPER", C_NAME, "RX~P~" .. C_NAME .. "~" .. FirstPiece("c", "94"))
		As(b, b.c.Relay.HandleIn, "WHISPER", b.c.me, "RL~P~" .. FirstPiece("b", "95"))
		-- A's census snapshot, whole, across to B.
		local cg = Word(("CG~2~S~%d~ForeverPvE~Alliance~beside three looks"):format(T0), 3)
		for _, p in ipairs(ns.Codec.Chunk(cg, "96")) do As(b, b.deliver, "WHISPER", A_NAME, "RX~P~" .. A_NAME .. "~" .. p) end
		Flush(); Advance(2)
		assert(Took(reg, cg), "B's registrant takes A's snapshot whole, past the trickle, with three looks open")
		-- The looks' own budget: past it, a look gets no slot (its pieces take the spent trickle).
		reg.c.Comm.Handle("QA", function(dist, sender, text) reg.got[#reg.got + 1] = { dist = dist, sender = sender, text = text } end)
		Advance(b.c.Relay.SET_WAIT + 1) -- (the open looks lapse)
		for i = 1, 6 do As(b, b.deliver, "WHISPER", "Some Client-Realm", "RL~P~X1~filler again " .. i) end
		Flush()
		b.c.Relay.MAX_SIGNED_LOOKS = 1
		As(b, b.deliver, "WHISPER", C_NAME, "RX~P~" .. C_NAME .. "~" .. FirstPiece("d", "97"))
		local function Whole(tag, id)
			local word = Word("QA~1~" .. tag:rep(86) .. "~CX~3~S~", 2)
			for _, p in ipairs(ns.Codec.Chunk(word, id)) do As(b, b.deliver, "WHISPER", A_NAME, "RX~P~" .. A_NAME .. "~" .. p) end
			Flush(); Advance(2)
			return word
		end
		eq(Took(reg, Whole("e", "98")), nil, "a look past the looks' budget gets no slot")
		b.c.Relay.MAX_SIGNED_LOOKS = 2
		assert(Took(reg, Whole("f", "99")), "within it, a look reaches the registrant whole")
	end)
end)
