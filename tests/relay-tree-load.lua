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
-- What is not, unless a case asks (o.chat, o.peer): chat lines (the relay's chat lane, up to
-- Relay.CHAT_PER_MIN of its sends), the other relays' traffic; nor ever the signed lists, a relay in an
-- instance, the server's delays and losses. All of them take from the same sends, so a real relay does
-- no better than these numbers.
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
-- measure, and the part in a hundred of the registrants offline between them); o.pressure (1.5.9:
-- ordinary single whispers the relay is handed every step, from a minute before the measure, more than
-- it sends: its queue stays full of ordinary words, as the trickle and its own single words to every
-- reporter keep a busy relay's); o.lead (1.5.9: every this many seconds of the measure, the relay's own
-- word in pieces of one kind, which goes to each registrant by the drip, ahead of the census transfers
-- queued after it); (1.5.9's review) o.before (the o.pressure words all handed to the queue before the
-- relay's pump, none after); o.chat (every this many seconds of the measure, a chat line from one
-- registrant, by the relay's chat lane to every other one: r.chat counts the lines, their deliveries,
-- the slowest and the relay's chat whispers lost); o.peer (no snapshot of the relay's own, as under
-- quiet presence: a trusted peer relay's snapshot crosses to it every this many seconds instead);
-- o.look (every this many seconds of the measure, the author's signed look, QA, in pieces, which the relay
-- says and hands each registrant by the drip: r.look counts the looks, those a registrant missed and the
-- slowest to arrive); o.ownGuild (the relay registers its own guild with itself every REGISTER_EVERY, as
-- the reporter of the author's relay's guild does, and a guildmate takes what it hands its guild over
-- GUILD: r.ownGuild counts the relay's snapshots, those the guildmate took whole, the longest it went
-- without a new one, and the relay's GUILD whispers).
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
		local c, deliver, sent, heard = extra.RelayWorld(name, guild, version == "1.5.4" and (FIXTURES .. "relay-1.5.4.lua") or nil)
		local n = { c = c, deliver = deliver, sent = sent, heard = heard, guild = guild, chat = C_ChatInfo, name = name, short = Short(name),
			version = version, online = true, took = {}, seen = 0, count = 0, longest = 0, oldest = 0,
			minute = -1, inMinute = 0, most = 0, whispers = 0, kinds = {}, guildDone = 0 }
		c.clock, c.realm = w.now, "Realm"
		c.Relay.PRESENT_REQUIRED_AT = T0 + 30 * 86400 -- (before the presentation's deadline: tests/relay-admit.lua has its own)
		c.rdb.council = { names = { ["tree relay"] = "Tree Relay", ["tree peer"] = "Tree Peer" } }
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
		-- (o.lead) The relay's own word in pieces, as its registrant takes it: once each.
		n.leads = {}
		c.Comm.Handle("T1", function(_, _, text) n.leads[text] = true end)
		-- (o.look) The author's signed look (QA) the relay says, and when it first came here.
		n.looks = {}
		c.Comm.Handle("QA", function(_, _, text) n.looks[text] = n.looks[text] or w.now end)
		-- The census itself is not this file's: every node trusts the relay's census, and a guild's report,
		-- carried whole to where Comm would decode it, is of the size alone (it decodes to nothing).
		local function Trusted(who) return Short(who) == "Tree Relay" or Short(who) == "Tree Peer" end
		c.Data = { FRESH = FRESH, CensusTrusted = Trusted, DecodeReport = function() return nil end }
		c.Church = { IsLedgerRelay = Trusted }
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
	local mateOf = {} -- (o.ownGuild) a node -> its guildmate, who hears its GUILD words
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
						elseif p.dist == "GUILD" and mateOf[n] then
							As(mateOf[n], mateOf[n].deliver, "GUILD", n.c.me, p.msg)
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
		-- (o.ownGuild) The relay's guildmate: what the relay hands its guild over GUILD reaches it.
		local mate = o.ownGuild and Node("Relay Mate-Realm", "Olympus Relay", "new") or nil
		mateOf[R] = mate
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
		if mate then Each(R.c.Relay.REGISTER_EVERY, 0, function() As(R, R.c.Relay.Register, true) end) end

		local made, start, pieces, packedPieces
		local pressFrom, busy = T0 + 3 * R.c.Relay.REGISTER_EVERY - 60, 0
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
			-- (o.pressure) Ordinary words the relay hands its queue faster than it sends, half before its
			-- pump and half after (they arrive whenever the guilds speak): to a name nobody plays here
			-- (lost on the wire), each one new (no key: none takes another's place).
			local function Press(k)
				if not o.pressure or w.now < pressFrom then return end
				As(R, function()
					for _ = 1, k do
						busy = busy + 1
						R.c.Comm.Whisper("Busy Target-Realm", "X1~busy " .. busy, nil, false, false)
					end
				end)
			end
			local first = o.before and (o.pressure or 0) or math.floor((o.pressure or 0) / 2)
			Press(first)
			for _, n in ipairs(w.nodes) do
				if n.online then As(n, n.c.Comm.Pump) end
			end
			Press((o.pressure or 0) - first)
			Carry()
		end
		-- The warm-up: three registrations each, so that any registrant may be a seed (2 x REGISTER_EVERY).
		while w.now < T0 + 3 * R.c.Relay.REGISTER_EVERY do Step() end
		for _, n in ipairs(w.nodes) do n.most, n.inMinute, n.whispers, n.kinds, n.guildDone = 0, 0, 0, {}, 0 end
		lost = 0
		if mate then mate.seen, mate.takes = #mate.took, {} end

		-- The measure: the relay's own snapshot every GLOBAL_EVERY, in pieces as Relay.Out hands its own
		-- client's words to it.
		made, start = {}, w.now
		for _, m in ipairs(regs) do m.last, m.seen, m.heardSeen = start, #m.took, #m.heard end
		local foreign, delays, leadWords = 0, {}, {}
		Each(o.peer or R.c.Relay.GLOBAL_EVERY, STEP, function()
			local word = Snapshot(o.guilds, math.floor(w.now))
			made[word] = w.now
			pieces = math.ceil(#word / Tree(R).RF_DATA)
			local packed = ns.Codec.PackCensus and ns.Codec.PackCensus(word)
			packedPieces = packed and math.ceil(#packed / Tree(R).RF_DATA) or nil
			w.id = w.id + 1
			As(R, function()
				for _, p in ipairs(R.c.Codec.Chunk(word, tostring(w.id))) do
					-- (o.peer: the peer's snapshot as it crosses to the relay, RX; else the relay's own, RL.)
					if o.peer then R.c.Relay.HandleAcross("WHISPER", "Tree Peer-Realm", "RX~P~Tree Peer-Realm~" .. p)
					else R.c.Relay.HandleIn("WHISPER", R.c.me, "RL~P~" .. p) end
				end
			end)
		end)
		-- (o.lead) The relay's own word in pieces (the King's Hands, a ranking's repeat: Relay.lua's
		-- ToReporters keys it by its kind), new each time, to every registrant by the drip.
		if o.lead then
			Each(o.lead, STEP / 2, function()
				w.id = w.id + 1
				local word = ("T1~H~%d~"):format(w.id) .. ("h"):rep(560)
				leadWords[#leadWords + 1] = { word = word, at = w.now }
				As(R, function()
					for _, p in ipairs(R.c.Codec.Chunk(word, tostring(w.id))) do R.c.Relay.HandleIn("WHISPER", R.c.me, "RL~P~" .. p) end
				end)
			end)
		end
		-- (o.look) The author's signed look the relay's client says (Data.AttestPayload), new each time.
		local looks = {}
		if o.look then
			Each(o.look, STEP / 3, function()
				w.id = w.id + 1
				local t = math.floor(w.now)
				local word = ("QA~1~%s~CX~3~S~Carried Author-Realm~ForeverPvP~Alliance~13614,12900,30,%d~"):format(("s"):rep(86), t)
					.. ("Olympus Remembered %d,900,100,450,%d;"):format(w.id, t):rep(14)
				looks[#looks + 1] = { word = word, at = w.now }
				As(R, function()
					for _, p in ipairs(R.c.Codec.Chunk(word, tostring(w.id))) do R.c.Relay.HandleIn("WHISPER", R.c.me, "RL~P~" .. p) end
				end)
			end)
		end
		-- (o.chat) A chat line from one registrant after another, by the relay's chat lane to every other one.
		local lines, heardAt = {}, {}
		if o.chat then
			Each(o.chat, STEP / 4, function()
				local from = regs[(#lines % #regs) + 1]
				local text = ("M1~A~%s~%d~WL~line %d"):format(from.guild, #lines + 1, #lines + 1)
				lines[#lines + 1] = { at = w.now, text = text, from = from }
				As(R, R.c.Relay.HandleIn, "WHISPER", from.c.me, "RL~L~" .. text)
			end)
		end
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
			-- (o.ownGuild) When the guildmate took each of the relay's snapshots, whole.
			while mate and mate.seen < #mate.took do
				mate.seen = mate.seen + 1
				if made[mate.took[mate.seen]] then mate.takes[#mate.takes + 1] = { word = mate.took[mate.seen], at = w.now } end
			end
			for _, m in ipairs(regs) do
				-- (o.chat) When each line reached this registrant, the first time.
				while (m.heardSeen or 0) < #m.heard do
					m.heardSeen = (m.heardSeen or 0) + 1
					local text = m.heard[m.heardSeen].text
					if type(text) == "string" and text:sub(1, 3) == "M1~" then
						heardAt[text] = heardAt[text] or {}
						heardAt[text][m] = heardAt[text][m] or w.now
					end
				end
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

		-- (o.chat) Each line older than Relay.CHAT_LANE_TTL: the registrants it reached, and when the last one did.
		local chat = { lines = 0, missed = 0, slowest = 0, lost = R.c.Relay.Stats().chatLost or 0 }
		for _, line in ipairs(lines) do
			if stop - line.at >= R.c.Relay.CHAT_LANE_TTL then
				chat.lines = chat.lines + 1
				for _, m in ipairs(regs) do
					local got = m ~= line.from and heardAt[line.text] and heardAt[line.text][m]
					if m ~= line.from and not got then chat.missed = chat.missed + 1 end
					if got then chat.slowest = math.max(chat.slowest, got - line.at) end
				end
			end
		end
		-- (o.lead) The relay's own words in pieces older than five minutes: how many each registrant took, the
		-- fewest of any registrant, and the newest such word every registrant took.
		local lead = { words = 0, fewest = math.huge, newestToAll = nil }
		for _, x in ipairs(leadWords) do
			if stop - x.at >= 300 then
				lead.words = lead.words + 1
				local all = true
				for _, m in ipairs(regs) do if not m.leads[x.word] then all = false end end
				if all then lead.newestToAll = x.at - start end
			end
		end
		for _, m in ipairs(regs) do
			local k = 0
			for _, x in ipairs(leadWords) do if stop - x.at >= 300 and m.leads[x.word] then k = k + 1 end end
			lead.fewest = math.min(lead.fewest, k)
		end
		-- (o.look) Each look said at least two minutes before the end: who missed it, and the slowest arrival.
		local look = { words = 0, missed = 0, slowest = 0 }
		for _, x in ipairs(looks) do
			if stop - x.at >= 120 then
				look.words = look.words + 1
				for _, m in ipairs(regs) do
					local got = m.looks[x.word]
					if got then look.slowest = math.max(look.slowest, got - x.at) else look.missed = look.missed + 1 end
				end
			end
		end
		-- (o.ownGuild) The relay's snapshots, those its guildmate took whole (byte for byte, each once), the
		-- longest the guild went without a new one (from the measure's start to its end), and the relay's
		-- whispers over GUILD.
		local ownGuild
		if mate then
			ownGuild = { made = 0, took = 0, twice = 0, longest = 0, whispers = R.kinds.guild or 0 }
			for _ in pairs(made) do ownGuild.made = ownGuild.made + 1 end
			local last, once = start, {}
			for _, x in ipairs(mate.takes) do
				if once[x.word] then ownGuild.twice = ownGuild.twice + 1 else once[x.word], ownGuild.took = true, ownGuild.took + 1 end
				ownGuild.longest, last = math.max(ownGuild.longest, x.at - last), x.at
			end
			ownGuild.longest = math.max(ownGuild.longest, stop - last)
		end
		-- The result: over the registrants that were never offline.
		local r = { registrants = #regs, guilds = o.guilds, minutes = o.minutes, pieces = pieces, packedPieces = packedPieces,
			chat = chat, lead = lead, look = look, ownGuild = ownGuild,
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
		r.queue = { size = R.c.Comm.QueueSize(), room = R.c.Comm.QueueRoom() }
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

-- 1.5.9 (two /oly bug reports of 2026-11-12: no census piece came by the relay in a whole session, in
-- two guilds on two relays). The relay's drip started a census transfer only once its send queue had
-- free room for the whole batch, though Comm makes room by dropping the ordinary whispers still waiting,
-- and its batch then waited as an ordinary job, the first one a newer whisper pushed out: a queue kept
-- full by ordinary words (the trickle, the relay's own single words to every reporter) let no census
-- whisper out. And any other transfer at the front of the drip waiting for free room (the relay's own
-- word in pieces) held every census transfer behind it the same way. Fails before: the 1.5.4 registrant
-- takes no snapshot in five minutes, and none of the 30 tree registrants one in 25 minutes.
-- (1.5.9's review) And with every one of those ordinary words handed to the queue before the relay's pump
-- (before): a census batch waiting there as an ordinary job is pushed out every time; urgent, it stays.
-- Half before and half after, a non-urgent batch slipped through often enough to pass.
test("relay tree under load (1.5.9): ordinary words keep the relay's send queue full: a 1.5.4 registrant still takes the relay's whole census snapshot every round, with the relay's own word in pieces waiting at the front of its drip or not", function()
	for _, case in ipairs({ { lead = false }, { lead = 60 }, { lead = false, before = true }, { lead = 60, before = true } }) do
		local lead = case.lead
		local r = Run({ registrants = 1, guilds = 140, minutes = 5, mix = { ["1.5.4"] = 100 }, reports = false, pressure = 6, lead = lead or nil,
			before = case.before })
		Sound(r)
		local label = (lead and "with the relay's own word ahead" or "alone") .. (case.before and ", the words before the pump" or "")
		eq(r.never, 0, label .. ": the registrant took a snapshot")
		assert(r.fewest >= 2, ("%s: %d snapshots in five minutes, one each Relay.GLOBAL_EVERY"):format(label, r.fewest))
		assert(r.longest < 300, ("%s: %s minutes without a new snapshot"):format(label, Minutes(r.longest)))
		assert(r.queue.room <= 4, ("%s: the queue stayed full (%d free)"):format(label, r.queue.room))
	end
end)

test("relay tree under load (1.5.9): ordinary words keep the relay's send queue full: 30 tree-capable registrants each take the census, whole, within 25 minutes, the relay's own word in pieces waiting ahead of the tree's", function()
	local r = Run({ registrants = 30, guilds = 140, minutes = 25, pressure = 6, lead = 60 })
	Sound(r)
	assert(r.queue.room <= 4, ("the queue stayed full (%d free)"):format(r.queue.room))
	eq(r.never, 0, "every registrant took a snapshot")
	assert(r.tree.complete >= 30, ("%d transfers completed"):format(r.tree.complete))
	assert(r.longest < FRESH, ("a registrant went %s minutes without a new snapshot"):format(Minutes(r.longest)))
end)

-- 1.5.9's review: the drip's pace (Relay.lua). Sent urgent back to back, the census took about half the
-- relay's sends and five of every eight while one of its batches went: a busy chat lane lost lines it
-- delivered in 1.5.8. Now the drip goes at Relay.DRIP_PER_MIN while anything else waits, and the tree's
-- rounds wait for the 1.5.4 registrants' snapshots (RelayTree.lua's StarFirst). Fails before: 90 of the
-- chat whispers lost, the slowest line 306 s.
test("relay tree under load (1.5.9's review): the relay's own rounds, 90 registrants (ten on 1.5.4), a chat line every 45 s (120 chat whispers a minute) for 20 minutes: no chat whisper lost, every line reaches every registrant within two minutes, and every registrant takes a census within Data.FRESH", function()
	local r = Run({ registrants = 90, guilds = 140, minutes = 20, chat = 45, mix = { new = 90, ["1.5.4"] = 10 } })
	Sound(r)
	assert(r.chat.lines >= 20, ("%d chat lines measured"):format(r.chat.lines))
	eq(r.chat.lost, 0, "no chat whisper lost in the relay's chat lane")
	eq(r.chat.missed, 0, "every line reached every registrant")
	assert(r.chat.slowest < 120, ("a line reached its last registrant after %d s"):format(r.chat.slowest))
	eq(r.never, 0, "every registrant took a snapshot")
	assert(r.by["1.5.4"] and r.by["1.5.4"].never == 0, "the 1.5.4 registrants too")
	assert(r.longest < FRESH, ("a registrant went %s minutes without a new snapshot"):format(Minutes(r.longest)))
end)

-- 1.5.9's review (round 1's re-review): the chat lane at its peak. With the drip at its pace (Relay.DRIP_PER_MIN)
-- and the tree's digests, the acks and the King's words beside it, the chat lane kept some 110 of the
-- relay's 200 whispers a minute, under its own CHAT_PER_MIN of 160: a line every 40 s or faster waited
-- behind the census until its whispers aged out (CHAT_LANE_TTL), which 1.5.8 never let happen. Now the
-- drip starts no transfer while the chat lane's oldest whisper has waited Relay.DRIP_CHAT_AGE; at such a
-- peak the census is slower instead (the author's call: chat no worse than in 1.5.8). The relay is its own
-- guild's registrant, as the author's relay is. Fails before: 118 chat whispers lost, the slowest line 304 s.
test("relay tree under load (1.5.9's review): the relay's own rounds, 90 registrants (ten on 1.5.4), the relay its own guild's registrant, a chat line every 35 s (about 150 chat whispers a minute) for 30 minutes: no chat whisper lost, every line reaches every registrant, and every registrant still takes a census", function()
	local r = Run({ registrants = 90, guilds = 140, minutes = 30, chat = 35, mix = { new = 90, ["1.5.4"] = 10 }, ownGuild = true })
	Sound(r)
	assert(r.chat.lines >= 40, ("%d chat lines measured"):format(r.chat.lines))
	eq(r.chat.lost, 0, "no chat whisper lost in the relay's chat lane")
	eq(r.chat.missed, 0, "every line reached every registrant")
	eq(r.never, 0, "every registrant took a snapshot")
	assert(r.by["1.5.4"] and r.by["1.5.4"].never == 0, "the 1.5.4 registrants too")
end)

-- (T1 of the review) A relay that makes no round of its own (quiet presence: Data.SendGlobalCensus says
-- nothing) hands every registrant a peer's whole snapshot by the star: about 29 whispers each. Unpaced, that
-- took the relay's sends and the chat lane lost lines; paced, the chat keeps its share and the census is
-- slower, its bound here (about twice Data.FRESH, at 60 registrants) until such a relay's census goes by
-- the tree again, which is the author's decision (its own snapshot under quiet presence, or a round on a
-- peer's). Fails before: 225 chat whispers lost, the slowest line 306 s.
test("relay tree under load (1.5.9's review): a relay with no round of its own (a peer's snapshot every Relay.MESH_CROSS_EVERY), 60 registrants, a chat line every 30 s for 30 minutes: no chat whisper lost, and every registrant still takes a census, the slowest within twice Data.FRESH", function()
	local r = Run({ registrants = 60, guilds = 140, minutes = 30, peer = 300, chat = 30 })
	Sound(r)
	eq(r.relay.tree.rounds or 0, 0, "no round: the relay made no snapshot of its own")
	assert(r.chat.lines >= 40, ("%d chat lines measured"):format(r.chat.lines))
	eq(r.chat.lost, 0, "no chat whisper lost")
	eq(r.chat.missed, 0, "every line reached every registrant")
	assert(r.chat.slowest < 120, ("a line reached its last registrant after %d s"):format(r.chat.slowest))
	eq(r.never, 0, "every registrant took a snapshot")
	assert(r.longest < 2 * FRESH, ("a registrant went %s minutes without a new snapshot"):format(Minutes(r.longest)))
end)

-- (R2 and R4 of the review) The star, a busy chat lane, a queue kept full of ordinary words, and the relay's
-- own word in pieces to every registrant every minute, queued ahead of the census: the census transfers
-- go first, and the other ones keep a share of the drip (Relay.DRIP_OTHER_SHARE), so every registrant
-- takes both. Fails before: a registrant took none of the relay's words in pieces in 20 minutes.
test("relay tree under load (1.5.9's review): the star, 30 registrants, a chat line every 15 s, ordinary words keeping the queue full, the relay's own word in pieces every minute: every registrant takes the census and the relay's words in pieces, and no chat whisper is lost", function()
	local r = Run({ registrants = 30, guilds = 140, minutes = 20, peer = 120, chat = 15, lead = 60, pressure = 6 })
	Sound(r)
	eq(r.chat.lost, 0, "no chat whisper lost")
	eq(r.chat.missed, 0, "every line reached every registrant")
	eq(r.never, 0, "every registrant took a snapshot")
	assert(r.longest < 20 * 60, ("a registrant went %s minutes without a new snapshot"):format(Minutes(r.longest)))
	assert(r.lead.words >= 10, ("%d words in pieces measured"):format(r.lead.words))
	assert(r.lead.fewest >= 2, ("a registrant took %d of the relay's %d words in pieces"):format(r.lead.fewest, r.lead.words))
end)

-- (P2 of the review) The other servers' census, the author's signed look (QA, and CX, a realm group's
-- carried totals), makes room at once as a census transfer does, in the other transfers' turn, so a busy
-- queue no longer keeps it waiting for free room, and a newer look no longer takes the place of one that
-- never went. Fails before: with the pace alone, 2 of the 4 looks never reached the 1.5.4 registrant (each
-- waited for room until the next one replaced it); on 3dc2906e none did, and 27 of the 30 registrants'
-- looks were missed.
test("relay tree under load (1.5.9's review): ordinary words keep the relay's send queue full: the author's signed look the relay says reaches the 1.5.4 registrant every minute within a minute, and 30 tree-capable registrants every five minutes, beside the census", function()
	for _, case in ipairs({ { registrants = 1, mix = { ["1.5.4"] = 100 }, minutes = 6, look = 60, within = 60, words = 4 },
		{ registrants = 30, minutes = 12, look = 300, within = 300, words = 2 } }) do
		local r = Run({ registrants = case.registrants, mix = case.mix, guilds = 140, minutes = case.minutes, reports = false, pressure = 6,
			look = case.look })
		Sound(r)
		local label = ("%d registrants, a look every %d s"):format(case.registrants, case.look)
		assert(r.look.words >= case.words, ("%s: %d looks measured"):format(label, r.look.words))
		eq(r.look.missed, 0, label .. ": every registrant took every look")
		assert(r.look.slowest < case.within, ("%s: a look reached a registrant after %d s"):format(label, r.look.slowest))
		eq(r.never, 0, label .. ": and every registrant took the census")
	end
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
