-- 1.5.5: the relay's census snapshot to its registrants as a tree (Olympus/RelayTree.lua). On Forever a
-- relay handed each guild's registrant its whole census snapshot by whisper, some 28 whispers each: 92
-- registrants on the author's relay on 2026-11-10, far more than its queue sends in a round, so no
-- round ever finished. A relay the 1.5.5 census trusts now sends the snapshot whole to a few
-- registrants (the seeds, RF) and to every registrant a digest (RN) naming the seed that forwards it;
-- each receiver checks the whole word against the digest before anything takes it, and asks for what is
-- missing (RQ), the seed first and the relay after. RC says a client takes the tree, and that a transfer
-- completed. A registrant that never said so (1.5.4, or 1.5.5 before a restart) keeps one census snapshot
-- as an RM batch, the origin's set its census trusts. Real Comm + Relay + RelayTree on every node;
-- Blizzard's wire and timers are simulated (the routing of tests/verify-mesh.lua).
local ns, test, eq, extra = ...
local T0 = 1794000000
local FRESH = 15 * 60 -- (Data.FRESH)

local function Lower(s) return tostring(s or ""):lower() end
local function Short(name) return ns.ShortName(name or "") or "" end
local function Hex(bytes) return (bytes:gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end
-- The transfer id the relay gives a word: the first 8 hex digits of its SHA-256.
local function Tid(word) return Hex(ns.Sign.SHA256(word):sub(1, 4)) end

-- A census snapshot of `guilds` rows made at `made` (140 rows: about 6.3 KB, 28 RF whispers).
local function Snapshot(guilds, made, tag)
	local rows = {}
	for i = 1, guilds do rows[i] = ("Olympus %s Guild %03d,%d,40,300,%d"):format(tag or "Tree", i, 600 + i % 50, made - 60) end
	return ("CG~2~S~%d~ForeverPvE~Alliance~"):format(made) .. table.concat(rows, ";")
end

-- Nodes on one wire. A node's whispers reach the node of that plain name, its GUILD words its guildmates;
-- each node keeps its own C_ChatInfo (its sends), and timers run as the world's clock moves.
local function World(fn)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild,
		chat = C_ChatInfo, time = GetTime }
	local w = { nodes = {}, relays = {}, authors = {}, timers = {}, now = T0, id = 100 }
	GetChannelName = function() return 0 end
	ns.IsMember = function() return true end
	IsInGuild = function() return true end
	GetTime = function() return w.now end
	function w.As(n, f, ...)
		C_ChatInfo = n.chat
		GetGuildInfo = function() return n.guild, "Member", 3 end
		return f(...)
	end
	-- opts.old: a 1.5.4 client (no RelayTree.lua; opts.relayFile its Relay.lua). opts.tree: another
	-- version's RelayTree.lua (a 1.5.6 client). opts.packed: it says it reads the packed snapshot (RZ).
	function w.Node(name, guild, opts)
		opts = opts or {}
		local c, deliver, sent, _, pump = extra.RelayWorld(name, guild, opts.relayFile)
		local n = { c = c, deliver = deliver, sent = sent, pump = pump, guild = guild, chat = C_ChatInfo, cursor = 0,
			got = {}, name = name, short = Short(name) }
		c.clock, c.realm = w.now, "Realm"
		c.Relay.PRESENT_REQUIRED_AT = T0 + 30 * 86400 -- (before the presentation's deadline: tests/relay-admit.lua has its own)
		c.rdb.council = { names = {} }
		for _, r in ipairs(w.relays) do c.rdb.council.names[Lower(r)] = r end
		c.IsKingCharacter = function() return false end
		c.AuthorCharacters = function() return w.authors end
		c.db = { blocked = {} }
		c.Log = function() end
		c.After = function(delay, _, f) w.timers[#w.timers + 1] = { at = w.now + delay, n = n, f = f } end
		c.Every = function() end
		-- What reaches the census on this node (Data.ReceiveGlobalCensus's place): every CG word it takes.
		c.Comm.Handle("CG", function(dist, sender, text) n.got[#n.got + 1] = { dist = dist, sender = sender, text = text } end)
		if opts.old then c.RelayTree = false
		else w.As(n, function() assert(loadfile(opts.tree or (extra.addon .. "RelayTree.lua")))("Olympus", c) end) end
		-- The tests above the packed snapshot's are of the word as written, the tree of a registrant that
		-- reads nothing else (1.5.6): a node says it reads the packed snapshot only where a test asks (packed).
		if not opts.old and not opts.tree and not opts.packed then c.RelayTree.READS = "" end
		w.nodes[#w.nodes + 1] = n
		return n
	end
	-- A relay whose census trusts `trusted` and whose Church takes `ledger` as its ledger relays (short names).
	function w.Trust(n, trusted, ledger)
		n.c.Data = { FRESH = FRESH, CensusTrusted = function(name) return trusted[Short(name)] == true end }
		n.c.Church = { IsLedgerRelay = function(name) return ledger[Short(name)] == true end }
	end
	function w.Tree(n) return rawget(n.c, "RelayTree") end
	-- Every node pumps its queue and the wire carries what it sent, until nothing moves. route(p, from, to)
	-- may drop a message (false) or carry another text in its place (a string).
	function w.Flush(route)
		for _ = 1, 400 do
			local moved = false
			for _, n in ipairs(w.nodes) do
				if not n.offline then
					w.As(n, n.pump, 40)
					while n.cursor < #n.sent do
						n.cursor = n.cursor + 1
						moved = true
						local p = n.sent[n.cursor]
						for _, to in ipairs(w.nodes) do
							if to ~= n and not to.offline and ((p.dist == "WHISPER" and to.short == Short(p.target))
								or (p.dist == "GUILD" and to.guild == n.guild)) then
								local msg = p.msg
								if route then
									local r = route(p, n, to)
									if r == false then msg = nil elseif type(r) == "string" then msg = r end
								end
								if msg then w.As(to, to.deliver, p.dist, n.c.me, msg) end
							end
						end
					end
				end
			end
			if not moved then return end
		end
		error("the wire did not settle")
	end
	-- The clock moves `seconds`, `step` at a time: the timers due run, each node's tree ticks, the wire flushes.
	function w.Advance(seconds, route, step)
		local target = w.now + seconds
		while w.now < target do
			w.now = math.min(target, w.now + (step or 1))
			for _, n in ipairs(w.nodes) do n.c.clock = w.now end
			local due = w.timers
			w.timers = {}
			for _, t in ipairs(due) do
				if t.at <= w.now and not t.n.offline then w.As(t.n, t.f) else w.timers[#w.timers + 1] = t end
			end
			for _, n in ipairs(w.nodes) do
				local T = w.Tree(n)
				if type(T) == "table" and not n.offline then w.As(n, T.Tick) end
			end
			w.Flush(route)
		end
	end
	-- A registration at relay R from m (as its RR arrives there), and m telling R it takes a tree (RC).
	function w.Register(m, R)
		w.As(R, R.deliver, "WHISPER", m.c.me, "RL~P~RR~" .. m.guild)
		local T = w.Tree(m)
		if type(T) == "table" and T.Announce then w.As(m, T.Announce, true) end
		w.Flush()
	end
	-- A registrant of R: R answered its ping, and it registered there.
	function w.Registrant(name, guild, R, opts)
		local m = w.Node(name, guild, opts)
		w.As(m, m.deliver, "WHISPER", R.c.me, "RY~")
		w.Register(m, R)
		return m
	end
	-- The relay's own snapshot, in pieces as Relay.Out hands its own client's words to it.
	function w.Own(R, word)
		w.id = w.id + 1
		w.As(R, function()
			for _, p in ipairs(R.c.Codec.Chunk(word, tostring(w.id))) do R.c.Relay.HandleIn("WHISPER", R.c.me, "RL~P~" .. p) end
		end)
	end
	-- Another relay's snapshot crossing to R (RX), in its pieces.
	function w.Cross(R, H, word)
		w.id = w.id + 1
		w.As(R, function()
			for _, p in ipairs(R.c.Codec.Chunk(word, tostring(w.id))) do
				R.c.Relay.HandleAcross("WHISPER", H.c.me, "RX~P~" .. H.c.me .. "~" .. p)
			end
		end)
	end
	local ok, err = pcall(fn, w)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo, GetTime =
		saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat, saved.time
	if not ok then error(err, 0) end
end

-- Messages node n sent after `from` that start with `prefix` (to `target` alone when named).
local function Count(n, prefix, from, target)
	local k = 0
	for i = (from or 0) + 1, #n.sent do
		local p = n.sent[i]
		if p.msg:sub(1, #prefix) == prefix and (not target or Short(p.target) == Short(target)) then k = k + 1 end
	end
	return k
end
-- How many times node n's census took `word` (from `sender` alone when named).
local function Got(n, word, sender)
	local k = 0
	for _, g in ipairs(n.got) do
		if g.text == word and (not sender or g.sender == sender) then k = k + 1 end
	end
	return k
end
-- Whether node n handed `word` of `origin` to its guild (RG, in its pieces).
local function HandedToGuild(n, origin, word)
	local asm = n.c.Codec.NewAssembler()
	for _, p in ipairs(n.sent) do
		if p.dist == "GUILD" then
			local full = p.msg:match("^C%w+:") and n.c.Codec.Feed(asm, "guild", p.msg, 0) or p.msg
			if full == "RG~P~" .. origin .. "~" .. word then return true end
		end
	end
	return false
end
-- One relay, its registrants (1.5.5 unless `old` says otherwise), every one capable and registered
-- 2 x REGISTER_EVERY before the snapshot (so any may be a seed), the relay trusted by the 1.5.5 census.
local function TreeWorld(w, count, guildOf)
	w.relays = { "Tree Relay" }
	local R = w.Node("Tree Relay-Realm", "Olympus Relay")
	w.Trust(R, { ["Tree Relay"] = true }, { ["Tree Relay"] = true })
	local regs = {}
	for i = 1, count do
		regs[i] = w.Registrant(("Reg Number%02d-Realm"):format(i), guildOf and guildOf(i) or ("Olympus Tree %02d"):format(i), R)
	end
	w.Advance(400, nil, 20)
	for _, m in ipairs(regs) do w.Register(m, R) end -- (renewed within REPORTER_FOR)
	return R, regs
end

-- Fails before: every registrant got the snapshot from the relay itself, 28 or 29 whispers each (an RM
-- batch), so 40 registrants cost the relay some 1,160 whispers a round.
test("relay tree (1.5.5): one relay, 40 tree-capable registrants and a 140-guild snapshot: each verifies the same word and hands it to its guild; the relay sends 40 RN and the whole word to k seeds alone, no RM", function()
	World(function(w)
		local R, regs = TreeWorld(w, 40)
		local word = Snapshot(140, w.now)
		local n = math.ceil(#word / 230)
		eq(n, 28, "a 140-guild snapshot is 28 RF whispers")
		local mark = #R.sent
		w.Own(R, word)
		w.Advance(600, nil, 2)
		local k = math.max(2, math.min(16, math.ceil(2 * math.sqrt(40))))
		eq(Count(R, "RN~", mark), 40, "one digest to each registrant")
		eq(Count(R, "RF~", mark), k * n, ("the word whole to %d seeds alone"):format(k))
		local other = 0
		for i = mark + 1, #R.sent do
			local p = R.sent[i]
			if p.dist == "WHISPER" and Short(p.target):match("^Reg Number") and not (p.msg:match("^RN~") or p.msg:match("^RF~")) then other = other + 1 end
		end
		eq(other, 0, "no RM batch, nor anything else, to a tree registrant")
		for i, m in ipairs(regs) do
			eq(Got(m, word, R.c.me), 1, "registrant " .. i .. " takes the word once, from the relay")
			eq(#m.got, 1, "and no other word")
			eq(HandedToGuild(m, R.c.me, word), true, "registrant " .. i .. " hands it to its guild")
			eq(w.Tree(m).Stats().complete, 1)
		end
		eq(w.Tree(R).Stats().rounds, 1)
	end)
end)

-- Fails before: no tree. A seed (registered long ago) serves a receiver registered just now (never a seed).
local function Pair(w)
	w.relays = { "Tree Relay" }
	local R = w.Node("Tree Relay-Realm", "Olympus Relay")
	w.Trust(R, { ["Tree Relay"] = true }, { ["Tree Relay"] = true })
	local S = w.Registrant("Seed Alpha-Realm", "Olympus Seed", R)
	w.Advance(400, nil, 20)
	w.Register(S, R)
	local X = w.Registrant("Late Receiver-Realm", "Olympus Late", R)
	-- (Two registrants: under the star's threshold, which has a test of its own; the tree is what is tested.)
	w.Tree(R).TREE_STAR_MAX = 0
	return R, S, X
end

test("relay tree (1.5.5): a seed that drops pieces 5 and 17 is asked for them with the right mask and the receiver completes; with the seed offline the relay is asked; Stats shows got/needed/missing/from/outcome", function()
	for _, offline in ipairs({ false, true }) do
		World(function(w)
			local R, S, X = Pair(w)
			local word = Snapshot(140, w.now)
			local n, tid = math.ceil(#word / 230), Tid(word)
			local dropped = 0
			local function Route(p, from, to)
				if from == S and to == X and dropped < 2 then
					local i = p.msg:match("^RF~1~%x+~(%d+)~")
					if i == "5" or i == "17" then dropped = dropped + 1 return false end
				end
			end
			w.Own(R, word)
			w.Advance(10, Route)
			eq(dropped, 2, "the seed's pieces 5 and 17 never arrived")
			local st = w.Tree(X).Stats().last[1]
			eq(st.tid, tid); eq(st.got, n - 2); eq(st.n, n); eq(st.missing, "5,17")
			assert(st.from:find("Seed Alpha", 1, true), "from the seed: " .. tostring(st.from))
			eq(st.outcome, "open")
			if offline then S.offline = true end
			local mark = #X.sent
			-- Four pieces a hex digit: piece 5 is digit 1's first, 17 digit 4's.
			local ask = ("RQ~1~%s~%s"):format(tid, "0100100" .. ("0"):rep(math.ceil(n / 4) - 7))
			w.Advance(65)
			eq(Count(X, ask, mark, "Seed Alpha"), 1, "no new piece for GAP_WAIT: the seed is asked for 5 and 17")
			if offline then
				eq(Got(X, word), 0, "the seed is gone")
				w.Advance(125)
				eq(Count(X, ask, mark, "Tree Relay"), 1, "no progress RELAY_REPAIR_AFTER later: the relay is asked")
			else
				eq(Count(X, "RQ~", mark, "Tree Relay"), 0, "the seed answered: the relay is never asked")
			end
			eq(Got(X, word, R.c.me), 1, "complete, the word checked against its digest")
			st = w.Tree(X).Stats().last[1]
			eq(st.got, n); eq(st.missing, ""); eq(st.outcome, "repaired")
			assert(st.from:find(offline and "Tree Relay" or "Seed Alpha", 1, true), "repaired by: " .. tostring(st.from))
			eq(w.Tree(X).Stats().repaired, 1)
		end)
	end
end)

test("relay tree (1.5.5): a seed that alters one byte of the word fails the digest: counted as forged, the whole word asked of the relay; nothing takes the altered word", function()
	World(function(w)
		local R, S, X = Pair(w)
		local word = Snapshot(140, w.now)
		local tid = Tid(word)
		local altered
		local function Route(p, from, to)
			if from == S and to == X and not altered then
				local head, data = p.msg:match("^(RF~1~%x+~3~%d+~)(.*)$")
				if head then
					altered = head .. data:sub(1, -2) .. (data:sub(-1) == "1" and "2" or "1")
					return altered
				end
			end
		end
		local mark = #X.sent
		w.Own(R, word)
		w.Advance(30, Route)
		assert(altered, "the seed's third piece was changed on its way")
		eq(w.Tree(X).Stats().forged, 1, "counted as forged")
		eq(Count(X, ("RQ~1~%s~*"):format(tid), mark, "Tree Relay"), 1, "the whole word asked of the relay")
		eq(Got(X, word, R.c.me), 1, "the relay's copy completes it")
		eq(#X.got, 1, "the census never saw the altered word")
		eq(w.Tree(X).Stats().last[1].outcome, "repaired")
	end)
end)

-- Fails before: the relay keyed each origin's snapshot apart, so a registrant got every origin's, and a
-- 1.5.4 registrant on the author's relay got the author's own rows, which its census counts as a mere
-- witness's (only the Church's ledger relays are trusted there), beside the council's.
test("relay tree (1.5.5): a registrant that never sent RC (1.5.4's Relay.lua) gets one census snapshot as an RM batch; on the author's relay holding a council set at most FRESH old, the council's set; past FRESH the relay's own", function()
	World(function(w)
		w.relays = { "Tree Council" }
		w.authors = { "Tree Author" }
		local A = w.Node("Tree Author-Realm", "Olympus Author")
		local H = w.Node("Tree Council-Realm", "Olympus Council")
		-- The author's relay: trusted by the 1.5.5 census (lane trust), not one of the Church's ledger relays.
		w.Trust(A, { ["Tree Author"] = true, ["Tree Council"] = true }, { ["Tree Council"] = true })
		local O = w.Registrant("Old Registrant-Realm", "Olympus Old", A, { old = true, relayFile = extra.fixtures .. "relay-1.5.4.lua" })
		local N = w.Registrant("New Registrant-Realm", "Olympus New", A) -- (tree-capable; two registrants keep the tree off)
		local council = Snapshot(30, w.now - 60, "Council")
		w.Cross(A, H, council)
		w.Flush()
		eq(Got(O, council, H.c.me), 1, "the council's set reaches the 1.5.4 registrant, put together by its own Relay.lua")
		local own = Snapshot(30, w.now, "Author")
		w.Own(A, own)
		w.Flush()
		eq(Got(O, own), 0, "the author's own set does not reach the 1.5.4 registrant while the council's is fresh")
		eq(#O.got, 1, "nor is the council's sent to it again")
		eq(Got(N, council, H.c.me), 1); eq(Got(N, own, A.c.me), 1, "a 1.5.5 registrant gets the newest set its census trusts")
		w.Advance(FRESH + 60, nil, 30)
		w.Register(O, A); w.Register(N, A)
		local later = Snapshot(30, w.now, "Author")
		w.Own(A, later)
		w.Flush()
		eq(Got(O, later, A.c.me), 1, "the council's set past FRESH: the relay's own")
		eq(#O.got, 2)
	end)
end)

test("relay tree (1.5.5): a crossed census set and the relay's own, waiting for one registrant, leave one transfer, the newest: the registrant gets one snapshot", function()
	World(function(w)
		w.relays = { "Tree Relay", "Tree Peer" }
		local R = w.Node("Tree Relay-Realm", "Olympus Relay")
		local P = w.Node("Tree Peer-Realm", "Olympus Peer")
		local both = { ["Tree Relay"] = true, ["Tree Peer"] = true }
		w.Trust(R, both, both)
		local X = w.Registrant("Busy Registrant-Realm", "Olympus Busy", R, { old = true, relayFile = extra.fixtures .. "relay-1.5.4.lua" })
		-- The relay's queue full: what it hands the registrant waits in the drip.
		w.As(R, function() for i = 1, R.c.Comm.MAX_QUEUE do R.c.Comm.Whisper("Busy Target-Realm", "X1~busy " .. i, nil, true) end end)
		eq(R.c.Comm.QueueRoom(), 0)
		local crossed = Snapshot(30, w.now - 30, "Peer")
		local own = Snapshot(30, w.now, "Relay")
		w.Cross(R, P, crossed)
		w.Own(R, own)
		w.Advance(120)
		eq(#X.got, 1, "one census snapshot, not two")
		eq(Got(X, own, R.c.me), 1, "the newest, the relay's own")
	end)
end)

-- Fails before: no registrant is ever tree-capable, and no snapshot ever goes as a tree.
test("relay tree (1.5.5): 30 tree-capable registrants and a 7-piece snapshot stay on the star (RM, no RN); a 28-piece snapshot takes the tree", function()
	World(function(w)
		local R, regs = TreeWorld(w, 30)
		for _, m in ipairs(regs) do eq(R.c.Relay.TreeCapable(m.c.me), true, m.name .. " said RC") end
		local small = Snapshot(34, w.now)
		eq(math.ceil(#small / 230), 7)
		local mark = #R.sent
		w.Own(R, small)
		w.Advance(60, nil, 2)
		eq(Count(R, "RN~", mark), 0, "30 x 7 = 210 whispers: the star")
		for _, m in ipairs(regs) do eq(Got(m, small, R.c.me), 1, m.name .. " gets it as an RM batch") end
		local big = Snapshot(140, w.now)
		mark = #R.sent
		w.Own(R, big)
		w.Advance(10)
		eq(Count(R, "RN~", mark), 30, "30 x 28 = 840 whispers: the tree")
	end)
end)

test("relay tree (1.5.5): a second own snapshot within TREE_ROUND_EVERY starts no round; a transfer in flight is never put behind a repair nor evicted; a seed keeps 15 queue places free", function()
	World(function(w)
		local R, S, X = Pair(w)
		local T = w.Tree(R)
		-- Every RF batch the seed hands its queue, with the places left beside it.
		local rooms, send = {}, S.c.Comm.SendBatch
		S.c.Comm.SendBatch = function(dist, pieces, key, target, ...)
			if dist == "WHISPER" and type(pieces) == "table" and tostring(pieces[1]):match("^RF~") then
				rooms[#rooms + 1] = S.c.Comm.QueueRoom() - #pieces
			end
			return send(dist, pieces, key, target, ...)
		end
		local first = Snapshot(140, w.now)
		local n = math.ceil(#first / 230)
		local mark = #R.sent
		w.Own(R, first)
		w.Advance(60)
		eq(Count(R, "RN~", mark), 2); eq(T.Stats().rounds, 1)
		eq(Got(X, first, R.c.me), 1, "the seed served the receiver")
		assert(#rooms > 0, "the seed served from its queue")
		for _, room in ipairs(rooms) do eq(room >= 15, true, "a seed's batch leaves 15 places free: " .. room) end
		assert(w.Tree(S).Stats().seedWaits >= 1, "the seed waited for room behind its own guild's copy")
		-- 120 s after the round: no other round.
		w.Advance(60, nil, 5)
		mark = #R.sent
		w.Own(R, Snapshot(140, w.now))
		w.Advance(10)
		eq(Count(R, "RN~", mark), 0, "a second own snapshot within TREE_ROUND_EVERY: no round")
		eq(T.Stats().rounds, 1); eq(T.Stats().deferred, 1)
		-- Past TREE_ROUND_EVERY: a round. Its seed's transfer begins; a repair asked then waits behind it.
		w.Advance(120, nil, 5)
		w.Register(S, R); w.Register(X, R)
		local third = Snapshot(140, w.now)
		mark = #R.sent
		w.Own(R, third)
		w.As(R, R.pump, 1)
		assert(Count(R, "RF~", mark, "Seed Alpha") > 0, "the seed's transfer is in flight")
		w.As(R, R.deliver, "WHISPER", X.c.me, ("RQ~1~%s~*"):format(Tid(third)))
		w.As(R, function() for i = 1, 40 do R.c.Comm.Whisper("Busy Target-Realm", "X1~urgent " .. i, nil, true) end end)
		w.Advance(30)
		eq(Count(R, "RN~", mark), 2, "past TREE_ROUND_EVERY: a round")
		eq(T.Stats().rounds, 2)
		local repairing, behind = false, 0
		for i = mark + 1, #R.sent do
			local p = R.sent[i]
			if p.msg:match("^RF~") then
				if Short(p.target) == "Late Receiver" then repairing = true
				elseif Short(p.target) == "Seed Alpha" and repairing then behind = behind + 1 end
			end
		end
		eq(repairing, true, "the repair went")
		eq(behind, 0, "the transfer in flight is never put behind the repair")
		eq(Count(R, "RF~", mark, "Seed Alpha"), n, "nor evicted: each of its pieces once")
		eq(Got(S, third, R.c.me), 1)
		-- One repair a registrant a round: the same ask again is refused.
		local repaired = Count(R, "RF~", mark, "Late Receiver")
		w.As(R, R.deliver, "WHISPER", X.c.me, ("RQ~1~%s~*"):format(Tid(third)))
		w.Advance(5)
		eq(Count(R, "RF~", mark, "Late Receiver"), repaired, "a second repair of the round: nothing")
		assert(T.Stats().rqRefused >= 1)
	end)
end)

-- Fails before: the reporter registered whatever its guildmates were, so where the reporter was a 1.5.4
-- client its guild never got a tree.
test("relay tree (1.5.5): the registrant is the first guildmate whose hello says N: only it registers with the relay, the reporter only while no N guildmate is known; in fallback it reports for a reporter without N", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus Reg", "Member", 3 end
		local ours = { guild = "Olympus Reg", total = 100, online = 10, zones = {} }
		local OLD, NEW = "H1~1.5.4~Realm~p~~~~R", "H1~1.5.5~Realm~p~~~~R~N"
		-- A 1.5.5 client; tree: RelayTree.lua loaded (else the stand-in of a client updated without a restart).
		local function Client(me, tree)
			local c, deliver = extra.FreshComm()
			c.me, c.splitNames, c.rdb = me, true, {}
			local s = { registered = 0, broadcasts = 0, fallback = false, announced = 0, sent = {} }
			-- (The relay, as Comm asks it: our census report reaches Relay.Out, counted here.)
			c.Relay = { On = function() return true end, Pick = function() return "Some Relay", true end,
				IsRelay = function() return false end, InFallback = function() return s.fallback end,
				Register = function() s.registered = s.registered + 1 return true end,
				Out = function(parts)
					if type(parts) == "table" and tostring(parts[1]):match("^C%w+:1:%d+:R[12]~") then s.broadcasts = s.broadcasts + 1 end
					return true
				end }
			c.RelayTree = tree and { Announce = function() s.announced = s.announced + 1 end }
				or setmetatable({ missing = true }, { __index = function() return function() end end })
			c.Comm.loginAt = c.clock - 1000
			C_ChatInfo.SendAddonMessage = function(_, msg, dist) s.sent[#s.sent + 1] = { msg = msg, dist = dist } return 0 end
			return c, deliver, s
		end
		-- An old reporter and a guildmate with N: the guildmate registers (and tells its relay it takes a tree).
		local M, mdeliver, ms = Client("Mid Member-Realm", true)
		mdeliver("GUILD", "Aaa Old-Realm", OLD)
		M.Comm.MaybeBroadcast(ours)
		eq(M.Comm.isReporter, false, "the old client sorts first: our guild's reporter")
		eq(M.Comm.isRegistrant, true, "the first with N: the registrant")
		eq(ms.registered, 1, "the registrant registers"); eq(ms.announced, 1)
		eq(ms.broadcasts, 0, "and reports nothing while no fallback runs")
		M.Comm.Hello(true)
		for _ = 1, 5 do M.Comm.Pump() end
		assert(tostring(ms.sent[#ms.sent].msg):match("~R~N$"), "its hello says N: " .. tostring(ms.sent[#ms.sent].msg))
		-- A 1.5.5 guildmate without RelayTree.lua, neither reporter nor registrant: nothing.
		local C, cdeliver, cs = Client("Ccc Plain-Realm", false)
		cdeliver("GUILD", "Aaa Old-Realm", OLD)
		cdeliver("GUILD", "Mid Member-Realm", NEW)
		C.Comm.MaybeBroadcast(ours)
		eq(C.Comm.isRegistrant, false); eq(cs.registered, 0)
		C.Comm.Hello(true)
		for _ = 1, 5 do C.Comm.Pump() end
		assert(tostring(cs.sent[#cs.sent].msg):match("~R$"), "no N without RelayTree.lua: " .. tostring(cs.sent[#cs.sent].msg))
		-- A reporter without N does not register while an N guildmate is known; alone, it does.
		local P, pdeliver, ps = Client("Abb First-Realm", false)
		pdeliver("GUILD", "Mid Member-Realm", NEW)
		P.Comm.MaybeBroadcast(ours)
		eq(P.Comm.isReporter, true); eq(P.Comm.isRegistrant, false); eq(ps.registered, 0, "the N guildmate registers, not the reporter")
		local Q, qdeliver, qs = Client("Abc Alone-Realm", false)
		qdeliver("GUILD", "Zzz Old-Realm", OLD)
		Q.Comm.MaybeBroadcast(ours)
		eq(Q.Comm.isReporter, true); eq(Q.Comm.isRegistrant, true); eq(qs.registered, 1, "no N guildmate known: the reporter registers")
		-- In fallback the registrant reports for its reporter without N, every BROADCAST_EVERY.
		ms.fallback = true
		M.Comm.MaybeBroadcast(ours)
		eq(ms.broadcasts, 1, "in fallback, the registrant reports for its old reporter")
		M.Comm.MaybeBroadcast(ours)
		eq(ms.broadcasts, 1, "not again within BROADCAST_EVERY")
		M.clock = M.clock + 170
		M.Comm.MaybeBroadcast(ours)
		eq(ms.broadcasts, 2, "again a BROADCAST_EVERY later")
		-- A reporter with N reports itself: its registrant (itself) does not report for it.
		local K, kdeliver, ks = Client("Kay Later-Realm", true)
		kdeliver("GUILD", "Aaa New-Realm", NEW)
		ks.fallback = true
		K.Comm.MaybeBroadcast(ours)
		eq(K.Comm.isRegistrant, false); eq(ks.registered, 0); eq(ks.broadcasts, 0)
		-- Ten old guildmates sort before us: without N we go quiet (a hello each 10 minutes), with N we
		-- talk on, since we may be the registrant and a quiet hello is past PEER_WINDOW.
		for _, tree in ipairs({ false, true }) do
			local Z, zdeliver, zs = Client("Zed Last-Realm", tree)
			for i = 1, 10 do zdeliver("GUILD", ("Aaa Old%02d-Realm"):format(i), OLD) end
			local hellos = 0
			for _ = 1, 3 do
				Z.Comm.Hello()
				for _ = 1, 5 do Z.Comm.Pump() end
				Z.clock = Z.clock + 60
				for i = 1, 10 do zdeliver("GUILD", ("Aaa Old%02d-Realm"):format(i), OLD) end
			end
			for _, p in ipairs(zs.sent) do if p.msg:match("^H1~") then hellos = hellos + 1 end end
			eq(hellos, tree and 3 or 1, tree and "with N: a hello each minute" or "without N: quiet after the first")
		end
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end)

test("relay tree (1.5.5): a 34-piece transfer missing pieces 33 and 34 asks for them with the mask 000000003 (four pieces a hex digit, no bit library); pieces before their RN wait, two unknown transfers a sender; past TREE_HOLD it expires", function()
	World(function(w)
		w.relays = { "Tree Relay" }
		local R = w.Node("Tree Relay-Realm", "Olympus Relay")
		local X = w.Registrant("Mask Receiver-Realm", "Olympus Mask", R)
		local T = w.Tree(X)
		local hash = ("ab"):rep(12)
		local tid = hash:sub(1, 8)
		-- Two pieces of it come before its digest, from a seed: they wait for it.
		for i = 1, 2 do w.As(X, X.deliver, "WHISPER", "Some Seed-Realm", ("RF~1~%s~%d~34~%s"):format(tid, i, ("x"):rep(230))) end
		-- The same sender's pieces of two more unknown transfers: the second is one too many.
		w.As(X, X.deliver, "WHISPER", "Some Seed-Realm", ("RF~1~%s~1~2~%s"):format("cdcdcdcd", ("y"):rep(230)))
		w.As(X, X.deliver, "WHISPER", "Some Seed-Realm", ("RF~1~%s~1~2~%s"):format("efefefef", ("z"):rep(230)))
		eq(T.Stats().unknownDropped, 1, "at most two unknown transfers a sender")
		eq(T.Stats().orphans, 2)
		w.As(X, X.deliver, "WHISPER", "Some Seed-Realm", ("RN~1~%s~34~%s~~"):format(tid, hash))
		eq(T.Stats().bad, 1, "a digest from no relay is refused")
		w.As(X, X.deliver, "WHISPER", R.c.me, ("RN~1~%s~34~%s~~"):format(tid, hash))
		eq(T.Stats().last[1].got, 2, "the pieces that came first are its own")
		eq(T.Stats().orphans, 1, "the other unknown transfer still waits")
		for i = 3, 32 do w.As(X, X.deliver, "WHISPER", R.c.me, ("RF~1~%s~%d~34~%s"):format(tid, i, ("x"):rep(230))) end
		local st = T.Stats().last[1]
		eq(st.got, 32); eq(st.n, 34); eq(st.missing, "33,34")
		local mark = #X.sent
		w.Advance(65)
		eq(Count(X, ("RQ~1~%s~000000003"):format(tid), mark, "Tree Relay"), 1, "pieces 33 and 34: digit 8, 1 + 2")
		eq(table.concat(T.Unmask("000000003", 34), ","), "33,34")
		eq(table.concat(T.Unmask("0100100", 28), ","), "5,17")
		w.Advance(60)
		eq(T.Stats().orphans, 0, "past DIGEST_WAIT the unknown transfer's piece is gone")
		w.Advance(900, nil, 30)
		eq(T.Stats().expired, 1); eq(T.Stats().last[1].outcome, "expired")
	end)
end)

---------------------------------------------------------------------------
-- The packed census snapshot (Codec.PackCensus; RZ) and the order a seed serves its list in.
-- tests/relay-tree-load.lua measures what they buy, with the game's timing.
---------------------------------------------------------------------------

local OLD_TREE = extra.fixtures .. "relay-tree-1.5.6.lua"
-- Whether any node sent `target` a whisper that starts with `prefix`.
local function AnyTo(w, prefix, target)
	for _, n in ipairs(w.nodes) do
		if Count(n, prefix, 0, target.c.me) > 0 then return true end
	end
	return false
end

-- Fails before: no packed form; every registrant took the word as written, 28 pieces.
test("relay tree: the packed snapshot: registrants that said RZ take the packed word under its own digest, in fewer pieces; those that did not, and 1.5.6 clients, the word as written; every one takes the same snapshot byte for byte and hands its guild the snapshot as written; the seeds are shared by the work", function()
	World(function(w)
		w.relays = { "Tree Relay" }
		local R = w.Node("Tree Relay-Realm", "Olympus Relay")
		w.Trust(R, { ["Tree Relay"] = true }, { ["Tree Relay"] = true })
		local regs = {}
		for i = 1, 40 do
			-- 24 that read the packed snapshot, 8 on 1.5.6 (their own RelayTree.lua), 8 that say nothing of it.
			local opts = (i <= 24 and { packed = true }) or (i <= 32 and { tree = OLD_TREE }) or nil
			regs[i] = w.Registrant(("Reg Number%02d-Realm"):format(i), ("Olympus Tree %02d"):format(i), R, opts)
		end
		w.Advance(400, nil, 20)
		for _, m in ipairs(regs) do w.Register(m, R) end
		for i, m in ipairs(regs) do eq(w.Tree(R).Reads(m.c.me, "c"), i <= 24, m.name .. ": what the relay holds of its RZ") end
		eq(w.Tree(R).Stats().readers, 24)
		local word = Snapshot(140, w.now)
		local packed = ns.Codec.PackCensus(word)
		local n, np = math.ceil(#word / 230), math.ceil(#packed / 230)
		eq(n, 28)
		assert(np <= 17, ("the packed snapshot is %d pieces"):format(np))
		local tidW, tidP = Tid(word), Tid(packed)
		local mark = #R.sent
		w.Own(R, word)
		w.Advance(600, nil, 2)
		eq(Count(R, "RN~1~" .. tidP, mark), 24, "the packed word's digest to each registrant that reads it")
		eq(Count(R, "RN~1~" .. tidW, mark), 16, "the digest of the word as written to each of the others")
		-- The seeds: 13 for 40 registrants (2 x sqrt), each tree's part its part of registrants x pieces.
		local workP, workW = 24 * np, 16 * n
		local kP = math.max(2, math.floor(13 * workP / (workP + workW) + 0.5))
		local kW = math.max(2, math.floor(13 * workW / (workP + workW) + 0.5))
		eq(Count(R, "RF~1~" .. tidP, mark), kP * np, ("the packed word whole to %d seeds"):format(kP))
		eq(Count(R, "RF~1~" .. tidW, mark), kW * n, ("the word as written whole to %d seeds"):format(kW))
		for i, m in ipairs(regs) do
			eq(Got(m, word, R.c.me), 1, m.name .. " takes the snapshot as the relay wrote it, once")
			eq(#m.got, 1, "and no other word")
			eq(HandedToGuild(m, R.c.me, word), true, m.name .. " hands its guild the snapshot as written")
			eq(AnyTo(w, "RF~1~" .. (i <= 24 and tidW or tidP), m), false, m.name .. " is sent no piece of the other form")
			eq(AnyTo(w, "RN~1~" .. (i <= 24 and tidW or tidP), m), false, "nor its digest")
			local s = w.Tree(m).Stats()
			eq(s.complete, 1)
			eq(s.unpacked or 0, i <= 24 and 1 or 0)
			eq(s.forged, 0)
		end
		local round = w.Tree(R).Stats().round
		eq(round.registrants, 40)
		eq(round.seeds, kP + kW)
		eq(round.packed.tid, tidP); eq(round.packed.n, np); eq(round.packed.registrants, 24)
		eq(round.tid, tidW, "the round's line names the word as written, the packed one beside it")
	end)
end)

-- Fails before: no RZ, no packed form.
test("relay tree: the packed snapshot: an RZ is kept PRESENT_FOR and no longer, a malformed one counted and without effect, none taken by a client that is no relay; a snapshot Codec cannot give back byte for byte goes as written; a packed word that does not unpack is taken by nobody and handed on to nobody", function()
	World(function(w)
		w.relays = { "Tree Relay" }
		local R = w.Node("Tree Relay-Realm", "Olympus Relay")
		w.Trust(R, { ["Tree Relay"] = true }, { ["Tree Relay"] = true })
		local S = w.Registrant("Seed Alpha-Realm", "Olympus Seed", R, { packed = true })
		w.Advance(400, nil, 20)
		w.Register(S, R)
		local X = w.Registrant("Late Receiver-Realm", "Olympus Late", R, { packed = true })
		local T = w.Tree(R)
		T.TREE_STAR_MAX = 0 -- (two registrants: the tree is what is tested)
		eq(T.Reads(S.c.me, "c"), true); eq(T.Reads(X.c.me, "c"), true)
		eq(T.Reads(S.c.me, "d"), false, "a letter it did not say")
		eq(T.Reads("Nobody Known", "c"), false)
		-- Malformed: counted, and what the relay holds stays.
		local bad = T.Stats().bad
		for _, text in ipairs({ "RZ~1~", "RZ~1~C", "RZ~1~c1", "RZ~2~c", "RZ~1~" .. ("c"):rep(17), "RZ~1~c~x" }) do
			eq(w.As(R, T.HandleRZ, "WHISPER", X.c.me, text), false, text)
		end
		eq(T.Stats().bad, bad + 6)
		eq(T.Reads(X.c.me, "c"), true)
		eq(w.As(R, T.HandleRZ, "GUILD", X.c.me, "RZ~1~c"), false, "by whisper alone")
		eq(w.As(S, w.Tree(S).HandleRZ, "WHISPER", X.c.me, "RZ~1~c"), false, "a client that is no relay keeps none")
		eq(w.Tree(S).Reads(X.c.me, "c"), false)

		-- A snapshot Codec cannot give back (a count past two base-36 digits): as written to both.
		local odd = Snapshot(140, w.now) .. (";Olympus Vast,1296,40,300,%d"):format(w.now - 60)
		eq(ns.Codec.PackCensus(odd), nil)
		w.Own(R, odd)
		w.Advance(60, nil, 2)
		eq(Got(S, odd, R.c.me), 1); eq(Got(X, odd, R.c.me), 1)
		eq(w.Tree(S).Stats().unpacked, 0); eq(w.Tree(X).Stats().unpacked, 0)
		eq(T.Stats().round.packed, nil, "no packed tree in that round")

		-- A packed word that does not unpack (no relay sends one: PackCensus checks every word it packs):
		-- its digest matches, and nobody takes it, hands it to its guild or serves it.
		w.Advance(T.TREE_ROUND_EVERY, nil, 20)
		w.Register(S, R); w.Register(X, R)
		local broken = "CP~1~2~" .. tostring(w.now) .. "~ForeverPvE~Alliance~no row"
		R.c.Codec = setmetatable({ PackCensus = function() return broken end }, { __index = ns.Codec })
		local word = Snapshot(140, w.now)
		local served, took = Count(S, "RF~"), #S.got
		w.Own(R, word)
		w.Advance(60, nil, 2)
		R.c.Codec = nil
		eq(Count(R, "RN~1~" .. Tid(broken)), 2, "the round went out as the packed word")
		eq(w.Tree(S).Stats().unreadable, 1, "the seed counts it")
		eq(#S.got, took, "and takes nothing")
		eq(HandedToGuild(S, R.c.me, broken), false)
		eq(Count(S, "RF~"), served, "nor serves its list")
		local lines = table.concat(w.Tree(S).Stats().lines, "\n")
		assert(lines:find("tree packed: unpacked 0, unreadable 1", 1, true), lines)

		-- The next snapshot packs again; then nothing is heard of what S reads for PRESENT_FOR: forgotten.
		w.Advance(T.TREE_ROUND_EVERY, nil, 20)
		w.Register(S, R); w.Register(X, R)
		local good = Snapshot(140, w.now)
		w.Own(R, good)
		w.Advance(60, nil, 2)
		eq(Got(S, good, R.c.me), 1); eq(Got(X, good, R.c.me), 1)
		eq(w.Tree(S).Stats().unpacked, 1); eq(w.Tree(X).Stats().unpacked, 1)
		assert(table.concat(T.Stats().lines, "\n"):find("tree round packed " .. Tid(ns.Codec.PackCensus(good)), 1, true),
			"the relay's /oly bug names the packed round")
		w.Tree(S).READS = "" -- (S says RC from here on, and nothing of what it reads)
		w.Advance(R.c.Relay.PRESENT_FOR, nil, 60)
		for _, m in ipairs({ S, X }) do
			w.As(m, m.deliver, "WHISPER", R.c.me, "RY~") -- (the relay answers its ping again)
			w.Register(m, R)
		end
		eq(T.Reads(S.c.me, "c"), false, "forgotten")
		eq(T.Reads(X.c.me, "c"), true, "X said it again with its registration")
		eq(T.Stats().readers, 1)
	end)
end)

-- Fails before: a seed sorted its list by name, so the same registrants were last in every round.
test("relay tree: a seed serves its list in the order the relay wrote it in the digest; the relay writes the registrants its last round did not reach first", function()
	World(function(w)
		-- The seed's side: a digest whose list is in no order of the names.
		w.relays = { "Tree Relay" }
		local R = w.Node("Tree Relay-Realm", "Olympus Relay")
		local S = w.Registrant("Seed Alpha-Realm", "Olympus Seed", R)
		local word = Snapshot(20, w.now)
		local n = math.ceil(#word / 230)
		local hash = Hex(ns.Sign.SHA256(word):sub(1, 12))
		local list = { "Zoe Last", "Abe First", "Mid Dle", "Bea Second" }
		w.As(S, S.deliver, "WHISPER", R.c.me, ("RN~1~%s~%d~%s~~%s"):format(hash:sub(1, 8), n, hash, table.concat(list, ",")))
		for i = 1, n do
			w.As(S, S.deliver, "WHISPER", R.c.me, ("RF~1~%s~%d~%d~%s"):format(hash:sub(1, 8), i, n, word:sub((i - 1) * 230 + 1, i * 230)))
		end
		w.Advance(60, nil, 2)
		local order, seen = {}, {}
		for _, p in ipairs(S.sent) do
			if p.dist == "WHISPER" and p.msg:match("^RF~") and not seen[p.target] then
				seen[p.target] = true
				order[#order + 1] = p.target
			end
		end
		eq(table.concat(order, ","), table.concat(list, ","), "the relay's order")
	end)
	World(function(w)
		-- The relay's side: 40 registrants; in the first round ten of them get no piece from their seed.
		local R, regs = TreeWorld(w, 40)
		local missed, names, count = {}, {}, 0
		local first = Snapshot(140, w.now)
		local function Route(p, from, to)
			if not p.msg:match("^RF~") or from == R then return end
			if missed[to] == nil then
				missed[to] = count < 10
				if missed[to] then count = count + 1 end
			end
			if missed[to] then return false end
		end
		w.Own(R, first)
		w.Advance(120, Route, 2)
		eq(count, 10)
		for m, yes in pairs(missed) do
			if yes then
				names[Short(m.c.me)] = true
				eq(Got(m, first), 0, m.name .. " missed the round")
			end
		end
		w.Advance(w.Tree(R).TREE_ROUND_EVERY, Route, 20)
		for _, m in ipairs(regs) do w.Register(m, R) end
		local mark = #R.sent
		local second = Snapshot(140, w.now)
		w.Own(R, second)
		w.Advance(120, nil, 2)
		local placed = 0
		for i = mark + 1, #R.sent do
			local serve = R.sent[i].msg:match("^RN~1~%x+~%d+~%x+~~(.+)$")
			if serve then
				local reached = false
				for name in serve:gmatch("[^,]+") do
					if names[name] then
						placed = placed + 1
						eq(reached, false, name .. " comes before every registrant the last round reached, in its seed's list")
					else
						reached = true
					end
				end
			end
		end
		eq(placed, 10, "none of them is a seed, each is in a list")
		for _, m in ipairs(regs) do eq(Got(m, second, R.c.me), 1, m.name .. " takes the second round's") end
	end)
end)
