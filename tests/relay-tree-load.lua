-- The relay's tree under load, with the game's timing (Olympus/RelayTree.lua). tests/relay-tree.lua
-- checks what the tree does with the wire settled between every step; this file checks how long it
-- takes, which is what decides whether a guild sees the census: a row is grey after Data.FRESH (15
-- minutes), a relay sends some 200 whispers a minute, any other client 50, and a round of the tree
-- ends when the next one's digest arrives.
--
-- What runs: the real Comm, Relay, RelayTree and Codec on every node (one signed relay and its
-- registrants, one guild each), nothing of them replaced.
-- What is simulated:
--   * the clock, in steps of Comm.SEND_INTERVAL (1.2 s). Every step each client's queue is pumped
--     once, as the game's ticker does it (Comm.Pump: four parts for a signed relay, one for anyone
--     else), every timer due runs at its delay, and what was sent arrives in that step;
--   * each registrant's client: it registers with the relay and says it takes the tree every
--     Relay.REGISTER_EVERY by its own queue (Relay.Register, RelayTree.Announce), its tree ticks
--     every RelayTree.TICK, it hands every snapshot to its guild over GUILD by the same queue, and
--     (reports) it sends a census report's worth of bytes through the relay every 170 s, two pieces,
--     the largest the relay's trickle hands on, so the trickle takes its part of the relay's sends;
--   * the relay's own census snapshot every Relay.GLOBAL_EVERY: realistic rows (names of the game's
--     24 letters at most, most of them "OLYMPUS ...", counts, an observation each), new every time;
--   * versions: a registrant on this change, one on 1.5.6 (tests/fixtures/relay-tree-1.5.6.lua: its
--     own RelayTree.lua) or one on 1.5.4 (tests/fixtures/relay-1.5.4.lua: no tree), and a relay on
--     this change or on 1.5.6;
--   * an outage: a part of the registrants offline for a while (a whisper to them is lost).
-- What is not: chat lines (the relay's chat lane, up to Relay.CHAT_PER_MIN of its sends), the signed
-- lists, the other relays' traffic, a relay in an instance, the server's delays and losses. All of
-- them take from the same sends, so a real relay does no better than these numbers.
--
-- What is measured, for every registrant: the snapshots it took (each byte for byte one the relay
-- made, or the run fails), the longest it went without a new one, and the oldest census it held.
--
-- The whole table (not part of the suite: some minutes with the JIT off):
--   OLYMPUS_TREE_LOAD=table luajit tests/run.lua
-- prints one line a case; OLYMPUS_TREE_LOAD_REGISTRANTS="30,60,92", OLYMPUS_TREE_LOAD_GUILDS=140,
-- OLYMPUS_TREE_LOAD_MINUTES=40 and OLYMPUS_TREE_LOAD_ROUND=<seconds> (RelayTree.TREE_ROUND_EVERY on
-- the relay) change its cases.
local ns, test, eq, extra = ...
local T0 = 1794000000
local FRESH = 15 * 60 -- (Data.FRESH)
local REPORT_EVERY = 170 -- (Comm's BROADCAST_EVERY)
local REPORT_BYTES = 385 -- a census report in two pieces: the largest the relay's trickle hands on (Relay.lua's ToReporters)

local function Lower(s) return tostring(s or ""):lower() end
local function Short(name) return ns.ShortName(name or "") or "" end

-- The same numbers every run: a Lehmer generator (its products stay within a double's 53 bits).
local function Random(seed)
	local s = seed % 2147483647
	if s <= 0 then s = s + 2147483646 end
	return function(n)
		s = (s * 48271) % 2147483647
		return s % n + 1
	end
end

-- Guild names as the census has them: the game's 24 letters at most, six in ten "OLYMPUS ...", three
-- "Olympus ...", one neither.
local SECOND = { "FORCES OF EVIL", "LEGION", "II", "ASCENDANT", "VANGUARD", "OF THE DAWN", "ETERNAL", "TITANS",
	"IRON GUARD", "NIGHT WATCH", "PRIME", "EXILES", "REBORN", "HIGH TABLE", "OUTRIDERS", "LXX", "OLD GUARD" }
local function GuildName(i)
	local word = SECOND[(i - 1) % #SECOND + 1]
	local turn = math.ceil(i / #SECOND)
	local tail = turn > 1 and (" " .. turn) or ""
	local style = i % 10
	if style == 9 then return ("Sons of Zeus %d"):format(i) end
	if style >= 6 then return "Olympus " .. word:sub(1, 1) .. word:sub(2):lower() .. tail end
	return "OLYMPUS " .. word .. tail
end
-- A character's name, two words as on Forever, no order of theirs following the order they register in.
local FIRST = { "Damned", "Silent", "Iron", "Pale", "Wild", "Grim", "Lost", "Bright", "Old", "Swift", "Dark", "Red",
	"Stone", "Ash", "Storm", "Quiet" }
local LAST = { "Reaper", "Warden", "Hunter", "Mender", "Walker", "Singer", "Breaker", "Keeper", "Rider", "Seer",
	"Baker", "Tanner", "Archer", "Smith", "Fisher", "Weaver" }
local function CharacterName(i)
	local a = (i * 7) % #FIRST + 1
	local b = (i * 11 + math.floor((i - 1) / #FIRST)) % #LAST + 1
	return ("%s %s%s"):format(FIRST[a], LAST[b], i > #FIRST * #LAST and tostring(i) or "")
end

-- A census snapshot of `guilds` rows made at `made`, as Data.GlobalCensusPayload writes one.
local function Snapshot(guilds, made)
	local rand, rows = Random(made), {}
	for i = 1, guilds do
		local total = 11 + rand(940)
		rows[i] = ("%s,%d,%d,%d,%d"):format(GuildName(i), total, rand(math.max(1, math.floor(total / 4))) - 1,
			99 + rand(500), made - rand(840))
	end
	return ("CG~2~S~%d~ForeverPvE~Alliance~"):format(made) .. table.concat(rows, ";")
end

local FIXTURES = extra.fixtures
local TREE = { new = extra.addon .. "RelayTree.lua", ["1.5.6"] = FIXTURES .. "relay-tree-1.5.6.lua" }

-- One run. o.registrants; o.guilds (rows of the snapshot); o.minutes (measured, after a warm-up of
-- three registrations); o.mix = { new =, ["1.5.6"] =, ["1.5.4"] = } (parts in a hundred of the
-- registrants on each version; all on this change by default); o.plain (those on this change say
-- nothing of the packed snapshot); o.relay ("new" or "1.5.6"); o.reports (false: no guild reports);
-- o.round (RelayTree.TREE_ROUND_EVERY on the relay); o.outage = { from, to, share } (seconds into the
-- measure, and the part in a hundred of the registrants offline between them).
local function Run(o)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild,
		chat = C_ChatInfo, time = GetTime }
	local STEP = ns.Comm.SEND_INTERVAL
	local w = { now = T0, timers = {}, nodes = {}, by = {}, id = 100, errors = {} }
	local out
	local function As(n, f, ...)
		C_ChatInfo = n.chat
		GetGuildInfo = function() return n.guild, "Member", 3 end
		return f(...)
	end
	local function Node(name, guild, version)
		local c, deliver, sent = extra.RelayWorld(name, guild, version == "1.5.4" and (FIXTURES .. "relay-1.5.4.lua") or nil)
		local n = { c = c, deliver = deliver, sent = sent, guild = guild, chat = C_ChatInfo, name = name, short = Short(name),
			version = version, online = true, took = {}, seen = 0, count = 0, longest = 0, oldest = 0,
			minute = -1, inMinute = 0, most = 0, whispers = 0, kinds = {}, guildDone = 0 }
		c.clock, c.realm = w.now, "Realm"
		c.Relay.PRESENT_REQUIRED_AT = T0 + 30 * 86400 -- (before the presentation's deadline: tests/relay-admit.lua has its own)
		c.rdb.council = { names = { ["tree relay"] = "Tree Relay" } }
		c.IsKingCharacter = function() return false end
		c.AuthorCharacters = function() return {} end
		c.db = { blocked = {} }
		c.Log = function() end
		-- An error the addon would have caught and kept for /oly bug: the run fails on it (Sound).
		c.CaptureError = function(where, problem) w.errors[#w.errors + 1] = ("%s (%s): %s"):format(tostring(where), n.short, tostring(problem)) end
		c.After = function(delay, _, f) w.timers[#w.timers + 1] = { at = w.now + (tonumber(delay) or 0), n = n, f = f } end
		c.Every = function() end
		-- What reaches the census on this node (Data.ReceiveGlobalCensus's place): every CG word it takes.
		c.Comm.Handle("CG", function(_, _, text) n.took[#n.took + 1] = text end)
		-- The census itself is not this file's: every node trusts the relay's census, and a guild's report,
		-- carried whole to where Comm would decode it, is of the size alone (it decodes to nothing).
		c.Data = { FRESH = FRESH, CensusTrusted = function(who) return Short(who) == "Tree Relay" end, DecodeReport = function() return nil end }
		c.Church = { IsLedgerRelay = function(who) return Short(who) == "Tree Relay" end }
		if version == "1.5.4" then c.RelayTree = false
		else As(n, function() assert(loadfile(TREE[version]))("Olympus", c) end) end
		w.nodes[#w.nodes + 1], w.by[Lower(n.short)] = n, n
		return n
	end
	local function Tree(n) return rawget(n.c, "RelayTree") or nil end

	-- What a node sent since the last look goes where it is addressed (a whisper to the node of that
	-- name, online; GUILD to nobody here: every registrant is alone in its guild) and is counted: its
	-- whispers a minute, and by kind.
	local function Kind(n, p)
		if p.dist ~= "WHISPER" then return "guild" end
		local msg = p.msg
		if msg:sub(1, 3) == "RF~" then return "piece" end
		if msg:sub(1, 3) == "RN~" then return "digest" end
		if n.relay then
			if msg:match("^C%w+:%d+:%d+:") or msg:sub(1, 3) == "RM~" then return "star" end
			return "other"
		end
		return "own"
	end
	local function Count(n, p)
		local kind = Kind(n, p)
		n.kinds[kind] = (n.kinds[kind] or 0) + 1
		if kind == "guild" then
			-- The last piece of a word over GUILD: the snapshot is with the guild (a snapshot is the one
			-- word a registrant hands its guild in more than three pieces here).
			local i, total = p.msg:match("^C%w+:(%d+):(%d+):")
			if i and i == total and tonumber(total) > 3 then n.guildDone = n.guildDone + 1 end
			return
		end
		local minute = math.floor((w.now - T0) / 60)
		if minute ~= n.minute then n.minute, n.inMinute = minute, 0 end
		n.inMinute, n.whispers = n.inMinute + 1, n.whispers + 1
		if n.inMinute > n.most then n.most = n.inMinute end
	end
	local lost = 0
	local function Carry()
		local moved = true
		while moved do
			moved = false
			for _, n in ipairs(w.nodes) do
				local sent = n.sent
				if sent[1] then
					moved = true
					local batch = {}
					for i = 1, #sent do batch[i], sent[i] = sent[i], nil end
					for _, p in ipairs(batch) do
						Count(n, p)
						if p.dist == "WHISPER" then
							local to = w.by[Lower(Short(p.target))]
							if to and to ~= n and to.online then As(to, to.deliver, "WHISPER", n.c.me, p.msg)
							else lost = lost + 1 end
						end
					end
				end
			end
		end
	end

	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetTime = function() return w.now end

		local R = Node("Tree Relay-Realm", "Olympus Relay", o.relay or "new")
		R.relay = true
		if o.round then Tree(R).TREE_ROUND_EVERY = o.round end
		local mix = o.mix or { new = 100 }
		local regs = {}
		for i = 1, o.registrants do
			local at = (i * 37) % 100
			local version = at < (mix.new or 0) and "new" or (at < (mix.new or 0) + (mix["1.5.6"] or 0) and "1.5.6" or "1.5.4")
			local m = Node(CharacterName(i) .. "-Realm", GuildName(i), version)
			if version == "new" and o.plain then Tree(m).READS = "" end
			As(m, m.deliver, "WHISPER", R.c.me, "RY~") -- (the relay answered its ping)
			regs[i] = m
		end

		-- What happens on its own clock, each registrant at its own moment of the period.
		local events = {}
		local function Each(period, first, f) events[#events + 1] = { at = w.now + first, period = period, f = f } end
		local reportId = 0
		for i, m in ipairs(regs) do
			local part = (i - 1) / #regs
			Each(R.c.Relay.REGISTER_EVERY, part * R.c.Relay.REGISTER_EVERY, function()
				if not m.online then return end
				As(m, m.c.Relay.Register, true)
				local T = Tree(m)
				if T then As(m, T.Announce, true) end
			end)
			if Tree(m) then
				Each(Tree(m).TICK, part * Tree(m).TICK, function() if m.online then As(m, Tree(m).Tick) end end)
			end
			if o.reports ~= false then
				Each(REPORT_EVERY, 60 + part * REPORT_EVERY, function()
					if not m.online then return end
					reportId = reportId + 1
					-- (As Comm.Broadcast sends one: its pieces as one batch on the channel, which is the relay here.)
					local report = ("R2~%s~%d~"):format(m.guild, reportId)
					report = report .. ("r"):rep(REPORT_BYTES - #report)
					As(m, m.c.Comm.SendBatch, "CHANNEL", m.c.Codec.Chunk(report, tostring(reportId % 1000)), nil, nil, false)
				end)
			end
		end
		Each(Tree(R).TICK, 0, function() As(R, Tree(R).Tick) end)

		local made, start, pieces, packedPieces
		local function Step()
			w.now = w.now + STEP
			for _, n in ipairs(w.nodes) do n.c.clock = w.now end
			local due = w.timers
			w.timers = {}
			for _, t in ipairs(due) do
				if t.at > w.now or not t.n.online then w.timers[#w.timers + 1] = t else As(t.n, t.f) end
			end
			for _, e in ipairs(events) do
				if e.at <= w.now then
					e.at = e.at + e.period
					e.f()
				end
			end
			for _, n in ipairs(w.nodes) do
				if n.online then As(n, n.c.Comm.Pump) end
			end
			Carry()
		end
		-- The warm-up: three registrations each, so that any registrant may be a seed (2 x REGISTER_EVERY).
		while w.now < T0 + 3 * R.c.Relay.REGISTER_EVERY do Step() end
		for _, n in ipairs(w.nodes) do n.most, n.inMinute, n.whispers, n.kinds, n.guildDone = 0, 0, 0, {}, 0 end
		lost = 0

		-- The measure: the relay's own snapshot every GLOBAL_EVERY, in pieces as Relay.Out hands its own
		-- client's words to it.
		made, start = {}, w.now
		for _, m in ipairs(regs) do m.last, m.seen = start, #m.took end
		local foreign, delays = 0, {}
		Each(R.c.Relay.GLOBAL_EVERY, STEP, function()
			local word = Snapshot(o.guilds, math.floor(w.now))
			made[word] = w.now
			pieces = math.ceil(#word / Tree(R).RF_DATA)
			local packed = ns.Codec.PackCensus and ns.Codec.PackCensus(word)
			packedPieces = packed and math.ceil(#packed / Tree(R).RF_DATA) or nil
			w.id = w.id + 1
			As(R, function()
				for _, p in ipairs(R.c.Codec.Chunk(word, tostring(w.id))) do R.c.Relay.HandleIn("WHISPER", R.c.me, "RL~P~" .. p) end
			end)
		end)
		local outage = o.outage
		local stop = start + o.minutes * 60
		while w.now < stop do
			if outage then
				local down = w.now - start >= outage.from and w.now - start < outage.to
				for i, m in ipairs(regs) do
					if (i * 53) % 100 < outage.share then m.online, m.wasOut = not down, true end
				end
			end
			Step()
			for _, m in ipairs(regs) do
				while m.seen < #m.took do
					m.seen = m.seen + 1
					local t = made[m.took[m.seen]]
					if not t then
						foreign = foreign + 1
					elseif not m.held or t > m.held then
						m.count = m.count + 1
						m.longest = math.max(m.longest, w.now - m.last)
						if m.held then m.oldest = math.max(m.oldest, w.now - m.held) end
						delays[#delays + 1] = w.now - t
						m.last, m.held = w.now, t
					end
				end
			end
		end

		-- The result: over the registrants that were never offline.
		local r = { registrants = #regs, guilds = o.guilds, minutes = o.minutes, pieces = pieces, packedPieces = packedPieces,
			foreign = foreign, lost = lost, errors = w.errors, fewest = math.huge, most = 0, snapshots = 0, never = 0, longest = 0, oldest = 0,
			measured = 0, by = {}, toGuild = 0 }
		for _, m in ipairs(regs) do
			if not m.wasOut then
				m.longest = math.max(m.longest, stop - m.last)
				if m.held then m.oldest = math.max(m.oldest, stop - m.held) else m.oldest = stop - start end
				r.measured = r.measured + 1
				r.fewest, r.most, r.snapshots = math.min(r.fewest, m.count), math.max(r.most, m.count), r.snapshots + m.count
				if m.count == 0 then r.never = r.never + 1 end
				r.longest, r.oldest = math.max(r.longest, m.longest), math.max(r.oldest, m.oldest)
				r.toGuild = r.toGuild + m.guildDone
				local v = r.by[m.version] or { n = 0, snapshots = 0, longest = 0, fewest = math.huge, never = 0 }
				r.by[m.version] = v
				v.n, v.snapshots = v.n + 1, v.snapshots + m.count
				v.longest, v.fewest = math.max(v.longest, m.longest), math.min(v.fewest, m.count)
				if m.count == 0 then v.never = v.never + 1 end
			end
		end
		table.sort(delays)
		r.delay = { median = delays[math.max(1, math.ceil(#delays / 2))] or 0, most = delays[#delays] or 0 }
		r.relay = { most = R.most, average = R.whispers / o.minutes, kinds = R.kinds,
			bound = math.floor(60 / STEP + 0.5) * R.c.Comm.PUMP_PARTS_RELAY, tree = Tree(R).Stats(), relay = R.c.Relay.Stats() }
		r.client = { most = 0, bound = math.floor(60 / STEP + 0.5), pieces = 0 }
		r.tree = { complete = 0, unpacked = 0, unreadable = 0, forged = 0, bad = 0, superseded = 0, repaired = 0, rqSent = 0 }
		for _, m in ipairs(regs) do
			r.client.most = math.max(r.client.most, m.most)
			r.client.pieces = math.max(r.client.pieces, m.kinds.piece or 0)
			local T = Tree(m)
			if T then
				local s = T.Stats()
				for key in pairs(r.tree) do r.tree[key] = r.tree[key] + (s[key] or 0) end
				local v = r.by[m.version]
				if v then v.unpacked, v.complete = (v.unpacked or 0) + (s.unpacked or 0), (v.complete or 0) + (s.complete or 0) end
			end
		end
		out = r
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo, GetTime =
		saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat, saved.time
	if not ok then error(err, 0) end
	return out
end

local function Minutes(seconds) return ("%.1f"):format(seconds / 60) end
-- One line of the table.
local function Line(label, r)
	local k = r.relay.kinds
	return ("| %s | %d | %d%s | %d / %.1f / %d | %d | %s | %s | %s / %s | %d (%d) | %d | %d + %d + %d |"):format(label, r.registrants,
		r.pieces, r.packedPieces and (" (" .. r.packedPieces .. ")") or "", r.fewest, r.snapshots / math.max(1, r.measured), r.most,
		r.never, Minutes(r.longest), Minutes(r.oldest), Minutes(r.delay.median), Minutes(r.delay.most),
		r.relay.most, math.floor(r.relay.average + 0.5), r.client.most,
		math.floor(((k.piece or 0) + (k.digest or 0)) / r.minutes + 0.5), math.floor((k.star or 0) / r.minutes + 0.5),
		math.floor((k.other or 0) / r.minutes + 0.5))
end

---------------------------------------------------------------------------
-- The suite's cases: small enough to run with every check, each a failure before this change.
---------------------------------------------------------------------------

-- The simulation itself: nobody sends faster than Comm lets it, and nothing but the relay's snapshots
-- is taken. (Every case below checks it.)
local function Sound(r)
	eq(r.errors[1], nil, "no error in any client")
	eq(r.foreign, 0, "every snapshot taken is, byte for byte, one the relay made")
	assert(r.relay.most <= r.relay.bound, ("the relay sent %d whispers in a minute, past its %d"):format(r.relay.most, r.relay.bound))
	assert(r.client.most <= r.client.bound, ("a registrant sent %d whispers in a minute, past its %d"):format(r.client.most, r.client.bound))
	eq(r.tree.forged, 0, "no digest failed")
	eq(r.tree.unreadable, 0, "no packed word failed to unpack")
end

-- Fails before: 92 registrants (the author's relay on 2026-11-10) took the 140-guild snapshot in 25
-- pieces each. The relay needed most of a round to seed it, a seed 30 s for every registrant of its
-- list, the next round's digest ended the round, and each seed served its list by name: the last
-- names of each list got no snapshot for half an hour and more.
test("relay tree under load: 92 registrants on one relay, a 140-guild snapshot every two minutes, every guild reporting: with the packed snapshot and the relay's order no registrant goes Data.FRESH without a new census", function()
	local r = Run({ registrants = 92, guilds = 140, minutes = 30 })
	Sound(r)
	assert(r.packedPieces and r.packedPieces <= r.pieces * 0.65, ("%s pieces packed of %d"):format(tostring(r.packedPieces), r.pieces))
	eq(r.never, 0, "every registrant took a snapshot")
	assert(r.longest < FRESH, ("a registrant went %s minutes without a new snapshot"):format(Minutes(r.longest)))
	assert(r.oldest < FRESH, ("a registrant held a census %s minutes old"):format(Minutes(r.oldest)))
	assert(r.tree.unpacked > 0 and r.tree.unpacked == r.tree.complete, "every transfer was the packed word, unpacked at its registrant")
	assert(r.toGuild >= r.snapshots - r.measured, ("%d of the %d snapshots taken went on to a guild"):format(r.toGuild, r.snapshots))
	local round = r.relay.tree.round
	assert(round and round.packed and round.packed.registrants == 92, "the relay's rounds were of the packed word, to every registrant")
end)

-- Fails before: the registrants a seed served last were the same in every round (its list sorted by
-- name), so on a relay whose seeds cannot finish a round some got no snapshot at all while others got
-- every one (20 of 120 in this run). The word as written here (no registrant says it reads the packed
-- one), so the order alone is measured.
test("relay tree under load: 120 registrants that take the word as written, more than a round reaches: a seed serves its list in the order the relay drew for the round, those the last round missed first, so no registrant is left out round after round", function()
	local r = Run({ registrants = 120, guilds = 140, minutes = 30, plain = true })
	Sound(r)
	eq(r.tree.unpacked, 0, "the word as written")
	eq(r.never, 0, "no registrant without a snapshot")
	assert(r.fewest >= 2, ("a registrant took %d snapshots in half an hour"):format(r.fewest))
end)

-- Fails before: no packed form (and a 1.5.6 registrant beside one on this change was served by name).
test("relay tree under load: one relay, registrants on this change, on 1.5.6 and on 1.5.4 together: each takes the snapshot in the form it reads, whole and the same bytes; the 1.5.6 ones never see a packed word", function()
	local r = Run({ registrants = 60, guilds = 140, minutes = 24, mix = { new = 55, ["1.5.6"] = 35, ["1.5.4"] = 10 } })
	Sound(r)
	local new, mid, old = r.by.new, r.by["1.5.6"], r.by["1.5.4"]
	assert(new and mid and old, "all three versions registered")
	eq(new.never + mid.never + old.never, 0, "every registrant took a snapshot")
	assert(new.unpacked > 0 and new.unpacked == new.complete, "this change's registrants took the packed word alone")
	assert(mid.complete > 0 and (mid.unpacked or 0) == 0, "the 1.5.6 registrants took the word as written by the tree")
	eq(r.tree.bad, 0, "no word a registrant could not read")
	eq(mid.never + old.never, 0, "and those on older versions took theirs")
	assert(new.longest < FRESH, ("a registrant on this change went %s minutes without a new snapshot"):format(Minutes(new.longest)))
end)

-- A relay still on 1.5.6 has no handler for RZ: it ignores it and sends the word as written to all.
test("relay tree under load: registrants on this change at a relay on 1.5.6: the relay ignores what they say they read and they take the word as written", function()
	local r = Run({ registrants = 40, guilds = 140, minutes = 16, relay = "1.5.6" })
	Sound(r)
	eq(r.relay.tree.bad, 0, "the 1.5.6 relay counted nothing malformed")
	eq(r.tree.unpacked, 0, "no packed word")
	assert(r.tree.complete > 0 and r.never == 0, "every registrant took the word as written")
end)

-- Seeds that go offline in the middle of their lists: what they did not serve is asked of the relay.
test("relay tree under load: a quarter of the registrants offline for five minutes, seeds among them: the others still take every form whole, and none goes Data.FRESH without a new census", function()
	local r = Run({ registrants = 60, guilds = 140, minutes = 26, outage = { from = 480, to = 780, share = 25 } })
	Sound(r)
	assert(r.measured < r.registrants and r.measured >= r.registrants * 0.6, "a part of the registrants was offline")
	eq(r.never, 0, "every registrant that stayed took a snapshot")
	assert(r.longest < FRESH, ("a registrant that stayed went %s minutes without a new snapshot"):format(Minutes(r.longest)))
end)

---------------------------------------------------------------------------
-- The whole table, on request (the top of the file).
---------------------------------------------------------------------------

if os.getenv("OLYMPUS_TREE_LOAD") == "table" then
	local minutes = tonumber(os.getenv("OLYMPUS_TREE_LOAD_MINUTES")) or 40
	local guilds = tonumber(os.getenv("OLYMPUS_TREE_LOAD_GUILDS")) or 140
	local round = tonumber(os.getenv("OLYMPUS_TREE_LOAD_ROUND"))
	local counts = {}
	for n in (os.getenv("OLYMPUS_TREE_LOAD_REGISTRANTS") or "30,60,92,120,170"):gmatch("%d+") do counts[#counts + 1] = tonumber(n) end
	local cases = {
		{ "relay and registrants on 1.5.6", { relay = "1.5.6", mix = { ["1.5.6"] = 100 } } },
		{ "registrants on 1.5.6", { mix = { ["1.5.6"] = 100 } } },
		{ "the word as written, the relay's order", { plain = true } },
		{ "the packed snapshot, the relay's order", {} },
		{ "half on 1.5.6, half on this change", { mix = { new = 50, ["1.5.6"] = 50 } } },
	}
	test("relay tree under load: the table", function()
		print(("\n%d guilds in the snapshot, %d minutes measured%s. Whispers a minute: the relay's most in any minute (its average), a registrant's most, and the relay's tree + star + other."):format(
			guilds, minutes, round and (", a round every " .. round .. " s at most") or ""))
		print("| case | registrants | pieces (packed) | snapshots each: fewest / average / most | never | longest wait (min) | oldest census held (min) | delivery: median / longest (min) | relay | registrant | relay's tree + star + other |")
		print("|---|---|---|---|---|---|---|---|---|---|---|")
		for _, n in ipairs(counts) do
			for _, case in ipairs(cases) do
				local o = { registrants = n, guilds = guilds, minutes = minutes, round = round }
				for key, value in pairs(case[2]) do o[key] = value end
				local r = Run(o)
				Sound(r)
				print(Line(case[1], r))
				-- (Where the registrants are of more than one version, a line for each.)
				local versions = {}
				for version in pairs(r.by) do versions[#versions + 1] = version end
				table.sort(versions)
				if #versions > 1 then
					for _, version in ipairs(versions) do
						local v = r.by[version]
						print(("| - of them on %s | %d | | %d / %.1f / | %d | %s | | | | | |"):format(version == "new" and "this change" or version,
							v.n, v.fewest, v.snapshots / v.n, v.never, Minutes(v.longest)))
					end
				end
			end
		end
	end)
end
