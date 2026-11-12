-- 1.5.5, the provisional relays (RelayFallback.lua) and Forever's no-channel rule (Relay.Out, Comm.lua).
-- With every relay of the signed list left out, a guild's registrant elects provisional relays among
-- the candidates a signed relay published (RE~1~L); census reports go to two of them; they carry
-- member-weight numbers to their registrants (RO) and stand down for any signed relay; and nothing
-- goes on Forever's channel, which delivers nothing there. Real Comm + Relay + RelayFallback (+ Data
-- where the census is asked); only Blizzard's wire and timers are simulated, as tests/verify-mesh.lua
-- does. Every name here is made up.
local ns, test, eq, extra = ...
local RelayWorld, ADDON = extra.RelayWorld, extra.addon
local T0 = 1800000000
local SIG1, SIG2 = "Sig Alpha", "Sig Beta" -- the signed list's relays here (the council's names)
local HOLD = 600 -- Relay.HOLD_FOR

local function World(fn)
	local saved = { channel = GetChannelName, join = JoinChannelByName, member = ns.IsMember, guild = GetGuildInfo,
		inGuild = IsInGuild, chat = C_ChatInfo, time = GetTime, server = GetServerTime }
	local dialogs = {}; for k, v in pairs(StaticPopupDialogs) do dialogs[k] = v end
	local W = { nodes = {}, timers = {}, now = T0, channel = {} }
	function W.CheckSignatures()
		local Ed, frames = ns.Ed25519, {}
		W.edAfter = Ed.after
		Ed.Reset()
		Ed.after = function(fn) frames[#frames + 1] = fn end
		return function(n)
			while #frames > 0 do W.As(n, table.remove(frames, 1)) end
		end
	end
	GetChannelName = function() return 5 end -- (joined: Forever's channel takes our words and delivers none)
	JoinChannelByName = function() end
	ns.IsMember = function() return true end
	IsInGuild = function() return true end
	GetTime = function() return W.now end
	GetServerTime = function() return math.floor(W.now) end
	function W.As(n, f, ...)
		C_ChatInfo = n.chat
		GetGuildInfo = function() return n.guild, "Member", 3 end
		return f(...)
	end
	-- A node's census (Data.lua), as tests/census-relay.lua loads it.
	local function Census(n)
		local N = n.c
		N.group, N.faction, N.db = "Realm", "Alliance", { blocked = {} }
		N.rdb.guilds, N.rdb.seen = {}, {}
		N.Church = { IsLedgerRelay = function(name) return N.Relay.IsRelay(name) end }
		N.QuietPresence = function() return false end
		W.As(n, function() assert(loadfile(ADDON .. "Data.lua"))("Olympus", N) end)
		N.Comm.Handle("CG", N.Data.ReceiveGlobalCensus)
	end
	-- opts.registrant: its guild's registrant (an elector); opts.census: Data.lua loaded.
	function W.Node(name, guild, opts)
		opts = opts or {}
		local c, deliver, sent, heard, pump = RelayWorld(name .. "-Realm", guild)
		local n = { c = c, name = name, deliver = deliver, sent = sent, heard = heard, pump = pump, guild = guild,
			chat = C_ChatInfo, cursor = 0, logs = {} }
		c.rdb.council = { names = { [SIG1:lower()] = SIG1, [SIG2:lower()] = SIG2 }, realm = "Realm" }
		c.clock, c.realm = W.now, "Realm"
		-- (T0 is past the presentation deadline; the presentation has its own suite, tests/relay-admit.lua.)
		c.Relay.PRESENT_REQUIRED_AT = T0 + 30 * 86400
		c.Log = function(fmt, ...) local ok, msg = pcall(string.format, fmt, ...) n.logs[#n.logs + 1] = ok and msg or tostring(fmt) end
		c.After = function(delay, _, f) W.timers[#W.timers + 1] = { at = W.now + delay, n = n, f = f } end
		c.Every = function() end
		if opts.census then Census(n) end
		W.As(n, function()
			-- (A base without RelayFallback.lua fails here.)
			assert(loadfile(ADDON .. "RelayFallback.lua"), "Olympus/RelayFallback.lua")("Olympus", c)
			c.Relay.Reset()
			c.Comm.JoinChannel()
		end)
		c.Comm.isRegistrant = opts.registrant or nil
		W.nodes[#W.nodes + 1] = n
		return n
	end
	-- Every node's queue pumped and its whispers and guild words delivered, until nothing moves. A
	-- channel word is noted (W.channel) and reaches nobody, as on Forever.
	function W.Flush()
		for _ = 1, 200 do
			local moved = false
			for _, n in ipairs(W.nodes) do
				W.As(n, n.pump, 40)
				while n.cursor < #n.sent do
					n.cursor = n.cursor + 1
					local p = n.sent[n.cursor]
					if p.dist == "CHANNEL" then W.channel[#W.channel + 1] = p end
					for _, to in ipairs(W.nodes) do
						if to ~= n and ((p.dist == "WHISPER" and ns.ShortName(to.c.me) == ns.ShortName(p.target or ""))
							or (p.dist == "GUILD" and to.guild == n.guild)) then
							W.As(to, to.deliver, p.dist, n.c.me, p.msg); moved = true
						end
					end
				end
			end
			if not moved then return end
		end
		error("the wire did not settle")
	end
	-- Time passes in steps: due timers, each node's RelayFallback.Tick (its ticker in game), the wire.
	function W.Advance(seconds, step)
		local target = W.now + seconds
		step = step or seconds
		repeat
			W.now = math.min(target, W.now + step)
			for _, n in ipairs(W.nodes) do n.c.clock = W.now end
			local due = W.timers
			W.timers = {}
			for _, t in ipairs(due) do
				if t.at <= W.now then W.As(t.n, t.f) else W.timers[#W.timers + 1] = t end
			end
			for _, n in ipairs(W.nodes) do
				local F = rawget(n.c, "RelayFallback")
				if type(F) == "table" and type(F.Tick) == "function" then W.As(n, F.Tick) end
			end
			W.Flush()
		until W.now >= target
	end
	-- Every signed relay left out on a node (no answer to its ping, or offline).
	function W.LeaveOut(n)
		W.As(n, function() n.c.Relay.LeaveOut(SIG1, "test"); n.c.Relay.LeaveOut(SIG2, "test") end)
	end
	-- A signed relay's candidates list, as a guildmate hands it on (RG): what a registrant holds.
	function W.GiveList(n, names, made)
		local word = "RE~1~L~" .. ns.Codec.Base36(math.floor(made or W.now)) .. "~" .. table.concat(names, ",")
		W.As(n, n.deliver, "GUILD", "Guild Mate-Realm", "RG~P~" .. SIG1 .. "-Realm~" .. word)
	end
	function W.Sent(n, prefix, target)
		local out = {}
		for _, p in ipairs(n.sent) do
			if p.msg:sub(1, #prefix) == prefix and (target == nil or ns.ShortName(p.target or "") == target) then out[#out + 1] = p end
		end
		return out
	end
	function W.Elected(n) return table.concat(W.As(n, n.c.RelayFallback.Elected) or {}, ",") end
	local ok, err = pcall(fn, W)
	if W.edAfter then ns.Ed25519.Reset(); ns.Ed25519.after = W.edAfter end
	GetChannelName, JoinChannelByName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo, GetTime, GetServerTime =
		saved.channel, saved.join, saved.member, saved.guild, saved.inGuild, saved.chat, saved.time, saved.server
	for k in pairs(StaticPopupDialogs) do StaticPopupDialogs[k] = dialogs[k] end
	if not ok then error(err, 0) end
end

-- Handlers that note what a node took and how it came (Relay.ViaProvisional while it is handled).
local function Watch(n, kinds, take)
	local got = {}
	for _, kind in ipairs(kinds) do
		n.c.Comm.Handle(kind, function(dist, sender, text)
			got[#got + 1] = { kind = kind, dist = dist, sender = sender, text = text, via = n.c.Relay.ViaProvisional() }
			if take then return take(dist, sender, text) end
		end)
	end
	return function(kind, text)
		local k = 0
		for _, g in ipairs(got) do
			if g.kind == kind and (text == nil or g.text == text) then k = k + 1 end
		end
		return k, got
	end
end

test("1.5.5 fallback: with every relay left out and no provisional one, a channel word never goes on the channel: our guild has a single word at once (RG), it waits for a relay and its done hears 'norelay' once after HOLD_FOR; a chat line the same", function()
	World(function(W)
		local m = W.Node("Lone Member", "Olympus Lonely")
		local mate = W.Node("Lone Mate", "Olympus Lonely")
		local heard = Watch(mate, { "X1", "M1" })
		W.LeaveOut(m)
		local calls = {}
		W.As(m, m.c.Comm.Send, "CHANNEL", "X1~nobody to carry it", nil, false, false, function(sent, why) calls[#calls + 1] = { sent, why } end)
		local lines = {}
		W.As(m, m.c.Comm.SendChat, "M1~a line typed", function(sent, why) lines[#lines + 1] = { sent, why } end)
		W.Flush()
		eq(#W.channel, 0, "nothing on Forever's channel")
		eq((heard("X1", "X1~nobody to carry it")), 1, "the single word reached our guild at once")
		eq((heard("M1", "M1~a line typed")), 1, "the chat line reached our guild at once")
		eq(#calls, 0, "held: its done waits"); eq(#lines, 0)
		W.Advance(HOLD - 40, 10)
		eq(#calls, 0, "still held before HOLD_FOR"); eq(#lines, 0)
		W.Advance(80, 10)
		eq(m.c.Relay.HOLD_FOR, HOLD)
		eq(#calls, 1, "told once"); eq(calls[1][1], false); eq(calls[1][2], "norelay")
		eq(#lines, 1, "the line's done told once"); eq(lines[1][1], false); eq(lines[1][2], "norelay")
		W.Advance(120, 10)
		eq(#calls, 1, "never twice"); eq(#lines, 1)
		eq(#W.channel, 0, "and nothing on the channel since")
		eq(m.c.RelayFallback.Stats().norelay, 2, "both counted")
		eq((heard("X1")), 1, "the guild's copy went once")
	end)
end)

test("1.5.5 fallback: three registrants holding one candidates list elect the same three in its order; one that never answers is skipped after PING_WAIT; a full one answers N and the next is used", function()
	World(function(W)
		local c1 = W.Node("Cand One", "Olympus Uno")
		local c3 = W.Node("Cand Three", "Olympus Tres")
		local c4 = W.Node("Cand Four", "Olympus Quatro")
		local c5 = W.Node("Cand Five", "Olympus Cinco")
		local electors = {}
		for i, g in ipairs({ "Olympus Ashes", "Olympus Birch", "Olympus Cedar" }) do
			electors[i] = W.Node("Elector " .. ({ "Ann", "Bob", "Cid" })[i], g, { registrant = true })
		end
		-- Cand Three serves 40 guilds already (someone elected it before): full.
		W.As(c3, c3.deliver, "WHISPER", "Early Elector-Realm", "RE~1~P")
		for i = 1, 40 do W.As(c3, c3.deliver, "WHISPER", ("Rep%02d Far-Realm"):format(i), "RL~P~RR~Olympus Far " .. i) end
		eq(c3.c.RelayFallback.Stats().registrants, 40)
		local list = { "Cand One", "Cand Two", "Cand Three", "Cand Four", "Cand Five" } -- Cand Two is offline
		for _, e in ipairs(electors) do W.GiveList(e, list); W.LeaveOut(e) end
		W.Advance(1)
		for _, e in ipairs(electors) do
			eq(#W.Sent(e, "RE~1~P", "Cand Two"), 1, "the silent one asked once")
			eq(W.Elected(e), "Cand One,Cand Four", "the full one passed over, the next asked")
		end
		eq(#W.Sent(c3, "RE~1~N"), 3, "the full one answered N to each")
		W.Advance(c1.c.Relay.PING_WAIT + 1)
		for _, e in ipairs(electors) do
			eq(W.Elected(e), "Cand One,Cand Four,Cand Five", "the same three, in the list's order")
			eq(#W.Sent(e, "RE~1~P", "Cand Five"), 1)
			eq(e.c.RelayFallback.Stats().none, 1, "one no-answer")
		end
		eq(c1.c.RelayFallback.Serving(), true); eq(c4.c.RelayFallback.Serving(), true); eq(c5.c.RelayFallback.Serving(), true)
	end)
end)

test("fallback: an unreachable saved candidate list gives way to fresh census reporters without losing its reachable first choice", function()
	World(function(W)
		local first = W.Node("First Choice", "Olympus First")
		local a = W.Node("Recent Reporter", "Olympus Recent")
		local b = W.Node("Other Reporter", "Olympus Other")
		local e = W.Node("Elector Reach", "Olympus Reach", { registrant = true })
		e.c.rdb.guilds = {
			[first.guild] = { reporterFull = first.c.me, t = W.now },
			[a.guild] = { reporterFull = a.c.me, t = W.now },
			[b.guild] = { reporterFull = b.c.me, t = W.now },
			["Olympus Stale"] = { reporterFull = "Stale Reporter-Realm", t = W.now - 86401 },
		}
		W.GiveList(e, { first.name, "Offline One", "Offline Two" })
		W.LeaveOut(e)
		W.Advance(1)
		eq(W.Elected(e), first.name, "the saved candidates get the first try")
		eq(#W.Sent(e, "RE~1~P", a.name) + #W.Sent(e, "RE~1~P", b.name), 0, "wait for the first candidates to answer")
		W.Advance(e.c.Relay.PING_WAIT + 2)
		local elected = W.As(e, e.c.RelayFallback.Elected)
		eq(#elected, 3, "the two fresh reporters fill the seats the offline names could not")
		eq(elected[1], first.name, "the reachable signed-list candidate keeps its seat")
		eq(#W.Sent(e, "RE~1~P", first.name), 1, "the name in both sources is asked only once")
		eq(#W.Sent(e, "RE~1~P", "Offline One") + #W.Sent(e, "RE~1~P", "Offline Two"), 2, "simultaneously due timeouts close both asks before either can be retried")
		eq(#W.Sent(e, "RE~1~P", "Stale Reporter"), 0, "an old report cannot supply a candidate")
		eq(#W.channel, 0, "the election does not use Forever's channel")
	end)
end)

-- The world of the next tests: three provisional relays every registrant elects, all serving.
local PROV = { "Prov One", "Prov Two", "Prov Three" }
local function Provisional(W, opts)
	opts = opts or {}
	local ps = {}
	for i, name in ipairs(PROV) do ps[i] = W.Node(name, "Olympus Prov " .. i, { registrant = true, census = opts.census }) end
	return ps
end
local function Elect(W, all, list)
	list = list or PROV
	for _, n in ipairs(all) do W.GiveList(n, list); W.LeaveOut(n) end
	W.Advance(1)
	W.Advance(1)
	local first = { list[1], list[2], list[3] }
	for _, n in ipairs(all) do eq(W.Elected(n), table.concat(first, ","), n.name .. " elected the list's first three") end
end
local function CensusReport(W, guild, total)
	return { guild = guild, total = total, online = 4, zones = {}, classes = {}, levels = { 0, 0, 0, 0, 0, 0, 0 },
		leader = "", from = "Realm", st = math.floor(W.now), faction = "Alliance" }
end

test("1.5.5 fallback: a guild's census report reaches two provisional relays first-hand; a receiver counts its row once two provisional snapshots agree, never from one", function()
	World(function(W)
		local ps = Provisional(W, { census = true })
		local e = W.Node("Report Ann", "Olympus Tiller", { registrant = true })
		local rx = W.Node("Watcher Bo", "Olympus Rook", { registrant = true, census = true })
		local all = { ps[1], ps[2], ps[3], e, rx }
		Elect(W, all)
		W.As(rx, rx.c.Relay.Register, true)
		W.Flush()
		W.As(e, e.c.Comm.Broadcast, CensusReport(W, "Olympus Tiller", 60))
		W.Flush()
		eq(#W.channel, 0, "no report on the channel")
		local holders = {}
		for _, p in ipairs(ps) do
			local g = p.c.rdb.guilds["Olympus Tiller"]
			if g then holders[#holders + 1] = p; eq(g.total, 60) end
		end
		eq(#holders, 2, "dual-homed: two provisional relays hold the report first-hand")
		eq(rx.c.Data.GlobalWitnesses("Olympus Tiller"), nil, "nothing yet")
		W.As(holders[1], holders[1].c.Data.SendGlobalCensus)
		W.Flush()
		eq(rx.c.Data.GlobalWitnesses("Olympus Tiller"), nil, "one provisional snapshot is one witness: not counted")
		W.As(holders[2], holders[2].c.Data.SendGlobalCensus)
		W.Flush()
		eq(rx.c.Data.GlobalWitnesses("Olympus Tiller"), 2, "two provisional snapshots agree: counted")
		eq(#W.channel, 0)
	end)
end)

test("1.5.5 fallback: a provisional relay whose snapshot misreports the receiver's own guild is left out, and the next candidate is elected", function()
	World(function(W)
		local ps = Provisional(W)
		local spare = W.Node("Prov Four", "Olympus Prov 4", { registrant = true })
		local rx = W.Node("Watcher Cy", "Olympus Rook", { registrant = true })
		local list = { PROV[1], PROV[2], PROV[3], "Prov Four" }
		Elect(W, { ps[1], ps[2], ps[3], spare, rx }, list)
		-- Our own report: 50 members, now.
		rx.c.rdb.guilds = { ["Olympus Rook"] = { guild = "Olympus Rook", total = 50, online = 5, t = W.now, st = W.now, mine = true } }
		-- Prov Two's snapshot (carried by Prov One, our relay's peer) says 80.
		local word = ("CG~1~S~%d~Olympus Rook,80,5,300,%d;Olympus Other,20,2,300,%d"):format(W.now, W.now - 60, W.now - 60)
		W.As(rx, rx.deliver, "WHISPER", PROV[1] .. "-Realm", "RO~P~" .. PROV[2] .. "-Realm~" .. word)
		eq(W.As(rx, rx.c.Relay.IsLeftOut, PROV[2]), true, "the relay that made it is left out")
		eq(rx.c.RelayFallback.Stats().dissents, 1)
		W.Advance(1)
		eq(W.Elected(rx), "Prov One,Prov Three,Prov Four", "the next candidate elected")
		-- A row that agrees (within max(5, 5%)), or one observed long before our own report, is no dissent.
		local fine = ("CG~1~S~%d~Olympus Rook,53,5,300,%d"):format(W.now, W.now)
		W.As(rx, rx.deliver, "WHISPER", PROV[1] .. "-Realm", "RO~P~" .. PROV[3] .. "-Realm~" .. fine)
		local old = ("CG~1~S~%d~Olympus Rook,10,1,300,%d"):format(W.now + 1, W.now - 3600)
		W.As(rx, rx.deliver, "WHISPER", PROV[1] .. "-Realm", "RO~P~" .. "Prov Four-Realm~" .. old)
		eq(rx.c.RelayFallback.Stats().dissents, 1, "no second dissent")
		eq(W.Elected(rx), "Prov One,Prov Three,Prov Four")
	end)
end)

test("1.5.5 fallback: when a signed relay answers, the provisional relay says Z to its registrants and peers and stops serving; they sweep at once and pick the signed relay", function()
	World(function(W)
		local ps = Provisional(W)
		local e = W.Node("Elector Dee", "Olympus Dawn", { registrant = true })
		Elect(W, { ps[1], ps[2], ps[3], e })
		W.As(e, e.c.Relay.Register, true)
		W.Flush()
		local relay = W.As(e, e.c.Relay.Pick)
		local p
		for _, x in ipairs(ps) do if x.name == relay then p = x end end
		assert(p, "the registrant's pick is a provisional relay: " .. tostring(relay))
		eq(W.As(p, p.c.RelayFallback.Stats).registrants >= 1, true)
		-- The registrant's own marks, and the other provisional relays', run longer than its relay's (the
		-- server named them offline later): its relay alone sweeps when its marks lapse.
		W.Advance(300)
		W.LeaveOut(e)
		for _, x in ipairs(ps) do if x ~= p then W.LeaveOut(x) end end
		local sig = W.Node(SIG1, "Olympus Signed") -- online now
		W.Advance(e.c.Relay.DEAD_FOR - 300 + 10, 5)
		eq(p.c.RelayFallback.Serving(), false, "serving stopped")
		assert(#W.Sent(p, "RE~1~Z~" .. SIG1, e.name) >= 1, "Z to its registrant, naming the signed relay")
		for _, x in ipairs(ps) do
			if x ~= p then assert(#W.Sent(p, "RE~1~Z", x.name) >= 1, "Z to its peer " .. x.name) end
		end
		assert(#W.Sent(e, "RL~P~RP~", SIG1) >= 1, "the registrant pinged the signed relay at once")
		eq(W.As(e, e.c.Relay.Pick), SIG1, "and picks it")
		eq(select(2, W.As(e, e.c.Relay.Pick)), true)
		eq(p.c.RelayFallback.Stats().standDowns, 1)
		eq(W.As(e, e.c.Relay.IsLeftOut, SIG1), false)
		eq(#W.channel, 0)
		eq(sig.c.Relay.IsRelay(sig.c.me), true)
	end)
end)

test("1.5.5 fallback: a provisional relay forwards its own CG and CX, its peers' CG and QA; T1, GV, MN, O1 and another player's CX are delivered there only", function()
	World(function(W)
		local ps = Provisional(W)
		local r = W.Node("Member Eve", "Olympus Elm", { registrant = true })
		local mate = W.Node("Elm Mate", "Olympus Elm")
		Elect(W, { ps[1], ps[2], ps[3], r })
		-- The registrant registers with Prov One alone (its pick), whatever its guild's hash.
		r.c.Relay.Pick = function() return PROV[1], true end
		W.As(r, r.c.Relay.Register, true)
		W.Flush()
		eq(ps[1].c.RelayFallback.Stats().registrants, 1, "the member's guild")
		local atR = Watch(r, { "CG", "CX", "QA", "T1", "GV", "MN", "O1" })
		local atP = Watch(ps[1], { "T1", "GV", "MN", "O1", "CX", "QA" })
		local atPeer = Watch(ps[2], { "CG", "CX" })
		local atMate = Watch(mate, { "T1" })
		local made = math.floor(W.now)
		W.As(ps[1], ps[1].c.Comm.Send, "CHANNEL", ("CG~1~S~%d~Olympus Prov 1,12,3,300,%d"):format(made, made))
		W.As(ps[1], ps[1].c.Comm.Send, "CHANNEL", ("CX~1~S~%d~own totals"):format(made))
		W.As(ps[2], ps[2].c.Comm.Send, "CHANNEL", ("CG~1~S~%d~Olympus Prov 2,14,3,300,%d"):format(made, made))
		W.Flush()
		eq((atR("CG")), 2, "its own CG and its peer's, to its registrant")
		eq((atR("CX")), 1, "its own CX too")
		eq((atPeer("CG")), 1, "its own CG to its peers")
		eq((atPeer("CX")), 1, "its own CX to its peers")
		eq(#W.Sent(ps[1], "RO~P~" .. PROV[2] .. "-Realm~", PROV[2]), 0, "a peer's own word never goes back to it")
		eq(#W.Sent(ps[1], "RO~P~" .. PROV[2] .. "-Realm~CG~", PROV[3]), 0, "nor to the other peers: they have it")
		-- The member's words: QA goes on; the rest is heard at the provisional relay alone.
		local before = #W.Sent(ps[1], "RO~")
		for _, w in ipairs({ "T1~P~1~2~3", "GV~1~A~1~2~3", "MN~1~a~b", "O1~x~y", "CX~1~S~1~member totals" }) do
			W.As(r, r.c.Comm.Send, "CHANNEL", w)
		end
		W.Flush()
		eq((atP("T1")), 1); eq((atP("GV")), 1); eq((atP("MN")), 1); eq((atP("O1")), 1); eq((atP("CX")), 1, "heard there")
		eq(#W.Sent(ps[1], "RO~") - before, 0, "and handed on to nobody")
		eq((atMate("T1", "T1~P~1~2~3")), 1, "the member's own single word reached its guild at once (RG): no provisional relay hands it on")
		W.As(r, r.c.Comm.Send, "CHANNEL", "QA~1~signed look")
		W.Flush()
		eq((atP("QA")), 1, "QA heard there")
		eq(#W.Sent(ps[1], "RO~P~Member Eve-Realm~QA~", PROV[2]), 1, "QA from anyone goes on: to its peers")
		eq((atR("T1")) + (atR("GV")) + (atR("MN")) + (atR("O1")), 0, "nothing of the staff's kinds came back by RO")
		eq(#W.channel, 0)
	end)
end)

test("1.5.6 fallback: a serving relay carries its own single and saved chunked QA to registrants, peers and its guild", function()
	World(function(W)
		local ps = Provisional(W, { census = true })
		local r = W.Node("Attest Reader", "Olympus Reader", { registrant = true, census = true })
		local mate = W.Node("Prov Mate", "Olympus Prov 1")
		Elect(W, { ps[1], ps[2], ps[3], r })
		r.c.Relay.Pick = function() return PROV[1], true end
		W.As(r, r.c.Relay.Register, true); W.Flush()
		local frames = W.CheckSignatures()
		local atR, atPeer, atMate = Watch(r, { "QA" }, r.c.Data.ReceiveAttest), Watch(ps[2], { "QA" }), Watch(mate, { "QA" })
		local p = ps[1]
		eq(W.As(p, p.c.Relay.Pick), p.name, "the serving relay takes its actual self route")
		local single = "QA~1~single carried look"
		eq(W.As(p, p.c.Comm.Send, "CHANNEL", single), true)
		W.Flush()
		eq((atR("QA", single)), 1, "an own single QA reaches the registrant")
		eq((atPeer("QA", single)), 1, "and its elected peer")
		eq((atMate("QA", single)), 1, "and its own guild once")
		-- A previously checked author's look saved account-wide and carried from another family.
		local seed, Ed = string.rep("\23", 32), ns.Ed25519
		local pk = Ed.PublicKey(seed)
		local observed = math.floor(W.now) - 60
		p.c.AUTHOR_ATTEST_PK = Ed.ToB64(pk)
		r.c.AUTHOR_ATTEST_PK = Ed.ToB64(pk)
		local function SavedLook(details, at)
			local wire = ("CX~3~S~Carried Author-CAMWOWUS1Realm8PvP~ForeverPvP~Alliance~13614,12900,30,%d~%s"):format(at, details)
			local text = "QA~1~" .. Ed.ToB64(Ed.Sign(seed, "OLYQA1|" .. wire, pk)) .. "~" .. wire
			p.c.db.groupAttest = { ["Alliance|ForeverPvP"] = { text = text, group = "ForeverPvP", faction = "Alliance", observed = at } }
			return text
		end
		local shortQA = SavedLook("", observed)
		eq(#ns.Codec.Chunk(shortQA, "short"), 1, "a saved look without guild details fits one piece")
		eq(W.As(p, p.c.Data.SayGroupCensus), true)
		W.Flush()
		eq((atR("QA", shortQA)), 1); eq((atPeer("QA", shortQA)), 1); eq((atMate("QA", shortQA)), 1)
		frames(r)
		eq(r.c.Data.CensusStats().qa.verified, 1, "the receiver verifies the saved signature")
		local qa = SavedLook(("Olympus Remembered,900,100,450,%d;Olympus Recalled,700,50,400,%d"):format(observed + 1, observed + 1), observed + 1)
		eq(#ns.Codec.Chunk(qa, "test"), 2, "the actual author's look needs multiple pieces")
		eq(W.As(p, p.c.Data.SayGroupCensus), true, "the real census sender accepts the saved look")
		W.Flush()
		eq((atR("QA", qa)), 1, "all pieces reach the registrant as one unchanged QA")
		eq((atPeer("QA", qa)), 1, "and the elected peer")
		eq((atMate("QA", qa)), 1, "and its own guild once")
		frames(r)
		eq(r.c.Data.CensusStats().qa.verified, 2, r.c.Data.CensusStats().line)
		local function Foreign()
			for _, row in ipairs(W.As(r, r.c.Data.Groups).rows) do if row.group == "ForeverPvP" then return row end end
		end
		local row = assert(Foreign(), "the authenticated foreign census is accepted")
		eq(row.counted, true); eq(row.src, "author"); eq(row.characters, 13614); eq(row.observed, observed + 1)
		eq(W.As(p, p.c.Data.AttestPayload, W.now, true), nil, "the normal per-origin repeat window still applies")
		local forged = qa:gsub("13614,12900,30,", "13615,12900,30,", 1)
		eq(W.As(p, p.c.Comm.SendChunked, forged, false, "CHANNEL"), true)
		W.Flush(); frames(r)
		eq(r.c.Data.CensusStats().qa.verified, 2, "a provisional route grants no signature authority")
		eq(r.c.Data.CensusStats().last[1].why, "signature")
		eq(Foreign().characters, 13614, "the forged copy cannot replace the accepted count")
		eq(#W.Sent(ps[2], "RO~P~" .. p.c.me .. "~", p.name), 0, "no peer sends the look back to its origin")
		eq(#W.channel, 0, "nothing leaks onto Forever's channel")
	end)
end)

test("1.5.6 fallback: own QA keeps send guards and chunk bounds, and other private or unsupported words never spread", function()
	World(function(W)
		local ps = Provisional(W)
		local r = W.Node("Guard Reader", "Olympus Guard", { registrant = true })
		Elect(W, { ps[1], ps[2], ps[3], r })
		r.c.Relay.Pick = function() return PROV[1], true end
		W.As(r, r.c.Relay.Register, true); W.Flush()
		local kinds = { "QA", "T1", "GV", "MN", "O1", "X1" }
		local atR, atPeer = Watch(r, kinds), Watch(ps[2], kinds)
		local p, calls = ps[1], {}
		W.As(p, p.c.Comm.SendChunked, "QA~1~guarded " .. string.rep("x", 250), false, "CHANNEL",
			function(sent, why) calls[#calls + 1] = { sent, why } end,
			{ owner = p.c.RelayFallback, key = "guarded-qa", permit = function() return false, "held" end })
		W.Flush()
		eq(#calls, 1); eq(calls[1][1], false); eq(calls[1][2], "held")
		W.As(p, p.c.RelayFallback.HandleIn, "WHISPER", p.c.me, "RL~P~Cbad:1:" .. (ns.Codec.MAX_CHUNKS + 1) .. ":QA~1~too many")
		W.As(p, p.c.RelayFallback.HandleIn, "WHISPER", p.c.me, "RL~P~Ctail:2:2:QA~1~no first piece")
		for _, word in ipairs({ "T1~P~1~2~3", "GV~1~A~1~2~3", "MN~1~a~b", "O1~x~y", "X1~unsupported" }) do
			W.As(p, p.c.Comm.Send, "CHANNEL", word)
			W.As(p, p.c.Comm.SendChunked, word .. string.rep("x", 250), false, "CHANNEL")
		end
		W.Flush()
		for _, kind in ipairs(kinds) do
			eq((atR(kind)), 0, kind .. " was not forwarded to a registrant")
			eq((atPeer(kind)), 0, kind .. " was not forwarded to a peer")
		end
		eq(#W.channel, 0)
	end)
end)

test("1.5.5 fallback: a provisional relay keeps 40 registrations at most, and sends 2 parts a pump", function()
	World(function(W)
		local p = W.Node("Prov Busy", "Olympus Busy")
		W.As(p, p.deliver, "WHISPER", "Some Elector-Realm", "RE~1~P")
		eq(p.c.RelayFallback.Serving(), true, "serving once it said yes")
		for i = 1, 41 do W.As(p, p.deliver, "WHISPER", ("Rep%02d Near-Realm"):format(i), "RL~P~RR~Olympus Near " .. i) end
		eq(p.c.RelayFallback.Stats().registrants, 40, "the 41st guild is refused")
		W.As(p, p.deliver, "WHISPER", "Some Elector-Realm", "RE~1~P")
		eq(#W.Sent(p, "RE~1~N"), 0, "not yet pumped")
		local q = W.Node("Plain Member", "Olympus Busy")
		for _, n in ipairs({ p, q }) do
			W.As(n, function() for i = 1, 6 do n.c.Comm.Whisper("Some One", "X1~" .. i) end end)
		end
		local pn, qn = #p.sent, #q.sent
		W.As(p, p.c.Comm.Pump); W.As(q, q.c.Comm.Pump)
		eq(#p.sent - pn, p.c.Comm.PUMP_PARTS_PROVISIONAL, "a serving provisional relay: its parts a pump")
		eq(p.c.Comm.PUMP_PARTS_PROVISIONAL, 2)
		eq(#q.sent - qn, 1, "anyone else: one")
		W.Flush()
		eq(#W.Sent(p, "RE~1~N"), 1, "a full one answers N")
		-- A guild it serves already is never one too many: its registrant's ask still gets a yes.
		W.As(p, p.deliver, "WHISPER", "Rep01 Near-Realm", "RE~1~P")
		W.Flush()
		eq(#W.Sent(p, "RE~1~Y~40", "Rep01 Near"), 1, "yes to a guild it serves")
		eq(#W.Sent(p, "RE~1~N"), 1)
	end)
end)

test("1.5.5 fallback: Pick prefers the pinned relay, then an answered signed relay that named the preferred release, then any answered signed one, then an unsigned code pin", function()
	World(function(W)
		local m = W.Node("Picky Member", "Olympus Pick")
		local R = m.c.Relay
		m.c.TreasurerPins = function() return { "Pin Gamma" }, false end
		R.IsSignedRelay = function(name) return R.IsRelay(name) and ns.ShortName(name) ~= "Pin Gamma" end
		eq(R.IsRelay("Pin Gamma"), true, "the code's pin is one of the relays")
		W.As(m, m.deliver, "WHISPER", "Pin Gamma-Realm", "RY~")
		eq(W.As(m, R.Pick), "Pin Gamma", "the only answer: the pin, as transport")
		W.As(m, m.deliver, "WHISPER", SIG1 .. "-Realm", "RY~1.5.4")
		eq(W.As(m, R.Pick), SIG1, "an answered signed relay over the unsigned pin")
		W.As(m, m.deliver, "WHISPER", SIG2 .. "-Realm", "RY~" .. R.PREFER_VERSION)
		eq(W.As(m, R.Pick), SIG2, "one that named the preferred release over one that named 1.5.4")
		R.PinnedRelay = function() return SIG1 end
		eq(W.As(m, R.Pick), SIG1, "the pinned relay first, once it answered")
		R.PinnedRelay = function() return "Not Answered" end
		eq(W.As(m, R.Pick), SIG2, "a pinned relay that never answered is passed over")
		local picks = m.c.RelayFallback.Stats().picks
		assert(#picks >= 3, "the pick history keeps the changes")
		eq(picks[#picks].to, SIG2)
	end)
end)

test("1.5.5 fallback: RO from a sender that is not an elected provisional relay is dropped; words taken from RO run with Relay.ViaProvisional() true and go on to the guild; an elected one carries nothing but snapshots, carried totals and QA", function()
	World(function(W)
		local ps = Provisional(W)
		local rx = W.Node("Watcher Fay", "Olympus Fjord", { registrant = true })
		local mate = W.Node("Fjord Mate", "Olympus Fjord")
		Elect(W, { ps[1], ps[2], ps[3], rx })
		local atRx = Watch(rx, { "CX", "T1", "GV" })
		local atMate = Watch(mate, { "CX" })
		W.As(rx, rx.deliver, "WHISPER", "Stranger Somebody-Realm", "RO~P~Stranger Somebody-Realm~CX~1~S~1~forged")
		eq((atRx("CX")), 0, "not from an elected provisional relay: dropped")
		eq(rx.c.RelayFallback.Stats().roDropped, 1)
		W.As(rx, rx.deliver, "WHISPER", PROV[2] .. "-Realm", "RO~P~" .. PROV[2] .. "-Realm~CX~1~S~1~carried")
		W.Flush()
		local n, got = atRx("CX", "CX~1~S~1~carried")
		eq(n, 1, "taken from an elected one")
		eq(got[1].via, true, "while it is handled, Relay.ViaProvisional() is true")
		eq(rx.c.Relay.ViaProvisional(), false, "and false after")
		eq((atMate("CX", "CX~1~S~1~carried")), 1, "handed to the guild once")
		-- An elected relay speaking for another origin, or carrying a staff word of its own: dropped.
		W.As(rx, rx.deliver, "WHISPER", PROV[2] .. "-Realm", "RO~P~Crowned Someone-Realm~T1~P~1~2~3")
		W.As(rx, rx.deliver, "WHISPER", PROV[2] .. "-Realm", "RO~P~" .. PROV[2] .. "-Realm~GV~1~A~1~2~3")
		W.As(rx, rx.deliver, "WHISPER", PROV[2] .. "-Realm", "RO~P~Some Member-Realm~CX~1~S~1~not its own")
		eq((atRx("T1")) + (atRx("GV")), 0, "no staff word by a provisional relay")
		eq((atRx("CX", "CX~1~S~1~not its own")), 0, "nor another player's totals")
		eq(rx.c.RelayFallback.Stats().roDropped, 4)
		eq(#W.channel, 0)
	end)
end)

test("1.5.5 fallback: a provisional relay whose row of a guild is the odd one out of three twice within half an hour is left out; once is a strike alone", function()
	World(function(W)
		local ps = Provisional(W)
		local spare = W.Node("Prov Four", "Olympus Prov 4", { registrant = true })
		local rx = W.Node("Watcher Gil", "Olympus Rook", { registrant = true })
		Elect(W, { ps[1], ps[2], ps[3], spare, rx }, { PROV[1], PROV[2], PROV[3], "Prov Four" })
		local function Round(totals, origins)
			local made = math.floor(W.now)
			for i, total in ipairs(totals) do
				local word = ("CG~1~S~%d~Olympus Other,%d,3,300,%d"):format(made + i, total, made - 30)
				W.As(rx, rx.deliver, "WHISPER", PROV[1] .. "-Realm", "RO~P~" .. (origins or PROV)[i] .. "-Realm~" .. word)
			end
		end
		Round({ 30, 31, 60 })
		eq(rx.c.RelayFallback.Stats().strikes, 1, "Prov Three alone against two that agree: a strike")
		eq(W.As(rx, rx.c.Relay.IsLeftOut, PROV[3]), false, "one strike leaves nobody out")
		W.Advance(500, 50) -- (within half an hour, and before the signed relays' marks lapse)
		Round({ 30, 30, 59 })
		eq(rx.c.RelayFallback.Stats().strikes, 2)
		eq(W.As(rx, rx.c.Relay.IsLeftOut, PROV[3]), true, "the second within half an hour: left out")
		W.Advance(1)
		eq(W.Elected(rx), "Prov One,Prov Two,Prov Four", "the next candidate elected")
		-- Three elected that disagree all round: nobody is the odd one out.
		Round({ 10, 40, 80 }, { PROV[1], PROV[2], "Prov Four" })
		eq(rx.c.RelayFallback.Stats().strikes, 2, "no strike")
		eq(W.Elected(rx), "Prov One,Prov Two,Prov Four")
	end)
end)

test("1.5.5 fallback: the lead signed relay publishes its tree-capable registrants of 2 x REGISTER_EVERY as candidates (RE~1~L), which its registrants keep for a week; a relay with a live mesh peer before it by name publishes nothing", function()
	World(function(W)
		local sig = W.Node(SIG1, "Olympus Signed")
		local members = {}
		for i, name in ipairs({ "Tree Ann", "Tree Bob", "Old Cid" }) do
			members[i] = W.Node(name, "Olympus Tree " .. i)
		end
		-- The tree lane's capability (RelayTree.lua): the two "Tree" members carry it, the old one not.
		sig.c.RelayTree = { Capable = function(name) return ns.ShortName(name):find("^Tree ") ~= nil end }
		local function Register()
			for _, m in ipairs(members) do
				W.As(m, m.deliver, "WHISPER", SIG1 .. "-Realm", "RY~")
				W.As(sig, sig.deliver, "WHISPER", m.c.me, "RL~P~RR~" .. m.guild)
			end
		end
		Register()
		W.Advance(1)
		eq(#W.Sent(sig, "RM~P~" .. SIG1 .. "-Realm~RE~1~L~"), 0, "registered too lately: nothing yet")
		for _ = 1, 4 do W.Advance(sig.c.Relay.REGISTER_EVERY / 2); Register() end
		W.Advance(5)
		local word
		for _, p in ipairs(W.Sent(sig, "RM~P~" .. SIG1 .. "-Realm~RE~1~L~")) do word = p.msg end
		assert(word, "published to its reporters")
		local names = word:match("~RE~1~L~%w+~(.*)$")
		eq(#names <= sig.c.RelayFallback.CANDIDATES_BYTES, true)
		local listed = {}
		for n in (names .. ","):gmatch("([^,]*),") do listed[#listed + 1] = n end
		table.sort(listed)
		eq(table.concat(listed, ","), "Tree Ann,Tree Bob", "the tree-capable registrants alone")
		local held = members[1].c.rdb.relayCandidates
		eq(type(held) == "table" and #held.names, 2, "a registrant keeps the list")
		eq(held.from, SIG1)
		eq(table.concat((W.As(members[1], members[1].c.RelayFallback.Candidates)), ","), names, "its candidates, in the list's order")
		local again = #W.Sent(sig, "RM~P~" .. SIG1 .. "-Realm~RE~1~L~")
		W.Advance(60)
		eq(#W.Sent(sig, "RM~P~" .. SIG1 .. "-Realm~RE~1~L~"), again, "once each CANDIDATES_EVERY")
		-- A list a week old is passed over.
		W.As(members[1], function() members[1].c.clock = W.now + members[1].c.RelayFallback.CANDIDATES_KEEP + 1 end)
		eq(select(2, W.As(members[1], members[1].c.RelayFallback.Candidates, members[1].c.clock)), "rendezvous")
		members[1].c.clock = W.now
		-- Another signed relay (by name after the lead, a live mesh peer of it) publishes nothing.
		local beta = W.Node(SIG2, "Olympus Signed Two")
		beta.c.RelayTree = sig.c.RelayTree
		beta.c.Relay.MeshPeer = function(name) return ns.ShortName(name) == SIG1 end
		eq(W.As(beta, beta.c.RelayFallback.Publish, W.now, true), false, "not the lead")
		-- A list from anyone but a signed relay is refused.
		W.As(members[2], members[2].deliver, "GUILD", "Guild Mate-Realm", "RG~P~Some Member-Realm~RE~1~L~" .. ns.Codec.Base36(W.now + 1) .. "~Evil One")
		eq(members[2].c.rdb.relayCandidates.names[1] ~= "Evil One", true, "not a signed relay's word")
	end)
end)

test("1.5.5 fallback: with no candidates list, the candidates are the reporters heard within a day, the same first twelve by the day's hash for any client that heard them", function()
	World(function(W)
		local a = W.Node("Rendez Ann", "Olympus Rv One")
		local b = W.Node("Rendez Bob", "Olympus Rv Two")
		local rows = {}
		for i = 1, 20 do
			rows["Olympus Row " .. i] = { guild = "Olympus Row " .. i, reporterFull = ("Reporter%02d Row-Realm"):format(i), t = W.now - 60 * i }
		end
		rows["Olympus Stale"] = { guild = "Olympus Stale", reporterFull = "Stale Reporter-Realm", t = W.now - 2 * 86400 }
		rows["Olympus Sig"] = { guild = "Olympus Sig", reporterFull = SIG1 .. "-Realm", t = W.now }
		a.c.rdb.guilds, b.c.rdb.guilds = rows, rows
		local la, from = W.As(a, a.c.RelayFallback.Candidates)
		local lb = W.As(b, b.c.RelayFallback.Candidates)
		eq(from, "rendezvous")
		eq(#la, 12, "the first twelve")
		eq(table.concat(la, ","), table.concat(lb, ","), "the same for both")
		for _, n in ipairs(la) do
			assert(n ~= "Stale Reporter", "a reporter not heard within a day is no candidate")
			assert(n ~= SIG1, "a signed relay is no provisional candidate")
		end
	end)
end)

test("1.5.5 fallback: a provisional relay nobody uses stops serving after IDLE_FOR, and is then no relay of its own words until its own election makes it serve again", function()
	World(function(W)
		local solo = W.Node("Prov Solo", "Olympus Solo", { registrant = true })
		W.Node("Prov Alt", "Olympus Alt")
		W.Node("Prov Bis", "Olympus Bis")
		Elect(W, { solo }, { "Prov Solo", "Prov Alt", "Prov Bis" })
		eq(solo.c.RelayFallback.Serving(), true, "it elected itself first")
		W.Advance(solo.c.RelayFallback.IDLE_FOR, 5)
		eq(solo.c.RelayFallback.Serving(), false, "idle: no longer serving")
		eq(W.Elected(solo), "Prov Alt,Prov Bis", "and no longer its own provisional relay")
		W.Advance(solo.c.Relay.PING_WAIT + 10, 5)
		eq(solo.c.RelayFallback.Serving(), true, "its own election asked it again")
		eq(W.Elected(solo), "Prov Solo,Prov Alt,Prov Bis")
		W.As(solo, solo.c.Comm.Send, "CHANNEL", "X1~its own word")
		W.Flush()
		eq(solo.c.RelayFallback.Stats().unserved, 0, "no word of its own was swallowed")
	end)
end)
