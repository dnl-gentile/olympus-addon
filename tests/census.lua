-- Census boundaries and alt membership revisions. Loaded by tests/run.lua.
local ns, test, eq, extra = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]census%.lua$")) or "./"
local Codec = ns.Codec

local function Decode(fields)
	fields.guild = fields.guild or "Olympus Test"
	return Codec.DecodeReport(Codec.EncodeReport(fields))
end

test("census: a zero-member report cannot contribute online members", function()
	local r = assert(Decode({ total = 0, online = 10000 }))
	eq(r.online, 0)
	eq(Decode({ total = 0, online = 10000, zones = { m1453 = 10000 } }), nil)
end)
test("census: zone, class and level distributions cannot exceed online members", function()
	for _, field in ipairs({ "zones", "classes", "levels" }) do
		local counts = field == "levels" and { 3, 3 } or { a = 3, b = 3 }
		local r = { total = 10, online = 5, [field] = counts }
		eq(Decode(r), nil, field .. ": individually plausible counts, impossible sum")
	end
	eq(Decode({ total = 1000, online = 5000, zones = { m1453 = 10000 } }), nil)
end)

test("census: partial, privacy-suppressed and older reports keep their wire contract", function()
	local r = assert(Decode({ total = 100, online = 20, zones = { m1453 = 3 }, classes = { WA = 2 }, levels = { 1, 1 } }))
	eq(r.online, 20); eq(r.zones.m1453, 3); eq(r.classes.WA, 2); eq(r.levels[1], 1)
	local hidden = Codec.Shareable(r, false, nil)
	local d = assert(Decode(hidden))
	eq(next(d.zones), nil); eq(d.online, 20)
	local old = assert(Codec.DecodeReport("R1~Olympus~10~2~Boss~1~2~m1453=2~WA=2~0,2,0,0,0,0,0"))
	eq(old.online, 2); eq(old.zones.m1453, 2)
	local clamped = assert(Decode({ total = 10, online = 20 }))
	eq(clamped.online, 10, "the existing online clamp remains")
end)

-- 1.2.3, the memory peaks on the owner's PC: about 40 census reports a minute were each decoded and
-- voted from scratch. A sender's report again but for its time (field 25) is now its row again.
-- Data.lua in a namespace of its own (its claims, kept reports and revision fresh), its DATA_CHANGED
-- fires, timers, log lines and decodes counted here, the clock the test's.
local function CensusWorld()
	local w = { fires = 0, timers = {}, logs = {}, decodes = 0, clock = 2000000000, on = {}, events = {} }
	local codec = setmetatable({
		DecodeReport = function(s) w.decodes = w.decodes + 1 return Codec.DecodeReport(s) end,
	}, { __index = Codec })
	local dns = setmetatable({
		rdb = { guilds = {}, seen = {} },
		Codec = codec,
		Who = { Listen = function() end },
		On = function(name, fn) w.on[name] = w.on[name] or {}; table.insert(w.on[name], fn) end,
		RegisterEvent = function(event, fn) w.events[event] = w.events[event] or {}; table.insert(w.events[event], fn) end,
		Every = function() end,
		Fire = function(name) if name == "DATA_CHANGED" then w.fires = w.fires + 1 end end,
		After = function(seconds, where, fn) w.timers[#w.timers + 1] = { seconds = seconds, where = where, fn = fn } end,
		Now = function() return w.clock end,
		Log = function(fmt, ...)
			local ok, line = pcall(string.format, fmt, ...)
			w.logs[#w.logs + 1] = ok and line or fmt
		end,
	}, { __index = ns })
	assert(loadfile(ROOT .. "Olympus/Data.lua"))("Olympus", dns)
	w.ns, w.D = dns, dns.Data
	function w.Run()
		local due = w.timers
		w.timers = {}
		for _, t in ipairs(due) do t.fn() end
		return #due
	end
	function w.Fire(name, ...) for _, fn in ipairs(w.on[name] or {}) do fn(...) end end
	return w
end

-- 1.5.4 (the review of #81 and #82): a full-size snapshot plus the relay's label was 35 pieces, one
-- past MAX_CHUNKS, so a relay sent it in two batches that a newer snapshot could split.
test("global census (1.5.4): a full snapshot leaves room for a relay's label, so wrapped once it fits one envelope", function()
	local source = CensusWorld()
	local relay = "Council-Realm"
	source.ns.Church = { IsLedgerRelay = function(name) return name == relay end }
	source.ns.Alts = nil
	source.ns.me = relay
	for i = 1, 200 do
		source.ns.rdb.guilds[("Olympus Guild Number %03d"):format(i)] = {
			total = 900 + i, online = 70, avgLevel = 46.2, t = source.clock, st = source.clock, zones = {},
		}
	end
	local C, D = source.ns.Codec, source.D
	local label = "RM~P~Developus Olympicus-CAMWOWUS2Realm1PvE~"
	eq(type(D.GLOBAL_SEND_BYTES) == "number" and D.GLOBAL_SEND_BYTES + #label <= C.CHUNK * C.MAX_CHUNKS, true,
		"the largest snapshot built, with a relay's label, is one envelope")
	local bound = D.GLOBAL_SEND_BYTES
	D.GLOBAL_SEND_BYTES = 1000 -- (a small bound shows the builder keeps to it)
	local payload = assert(D.GlobalCensusPayload())
	D.GLOBAL_SEND_BYTES = bound
	eq(#payload <= 1000 and #payload > 900, true, "the builder keeps to the send bound: " .. #payload)
end)

test("global census: a trusted holder restores normalized guild counts to a late client without granting census authority", function()
	local source, late = CensusWorld(), CensusWorld()
	local relay = "Council-Realm"
	for _, w in ipairs({ source, late }) do
		w.ns.Church = { IsLedgerRelay = function(name) return name == relay end }
		w.ns.Alts = nil
	end
	source.ns.me = relay
	source.ns.rdb.guilds["Olympus Dawn"] = {
		total = 987, online = 73, avgLevel = 46.2, t = source.clock, st = source.clock,
		leader = "Real Leader", officers = { { name = "Real Officer" } }, zones = { m1453 = 10 },
	}
	local payload = assert(source.D.GlobalCensusPayload())
	assert(payload:find("Olympus Dawn,987,73,462", 1, true), "the trusted snapshot carries normalized counts")
	assert(late.D.ReceiveGlobalCensus("CHANNEL", relay, payload))
	eq(next(late.ns.rdb.guilds), nil, "a relay never becomes an authoritative census report")
	local s = late.D.Summary()
	eq(s.characters, 987); eq(s.total, 987); eq(s.online, 73); eq(#s.guilds, 1)
	eq(s.guilds[1].name, "Olympus Dawn"); eq(s.guilds[1].g.relayed, true)
	eq(s.guilds[1].g.leader, nil, "leadership is deliberately not relayed as census authority")
	late.ns.Church.IsLedgerRelay = function() return false end
	-- 1.4.0 (the author's witness rule, 10-20 and 11-03): a snapshot of someone who is not a trusted
	-- relay is no longer refused outright; each of its rows is that person's witness. One witness
	-- alone changes nothing, here a newer, larger size of the guild.
	local lone = ("CG~1~S~%d~Olympus Dawn,999,80,462,%d"):format(late.clock, late.clock + 60)
	eq(late.D.ReceiveGlobalCensus("CHANNEL", "Stranger-Realm", lone), true, "a stranger's snapshot is heard as his witness")
	eq(late.D.Summary().characters, 987, "one witness alone moves nothing")
end)

test("global census: merging a full relayed census uses bounded guild-name lookups", function()
	local w = CensusWorld()
	local relay, rows = "Council-Realm", {}
	w.ns.Church = { IsLedgerRelay = function(name) return name == relay end }
	for i = 1, 150 do
		rows[i] = ("Olympus Guild %03d,100,10,200,%d"):format(i, w.clock)
	end
	w.ns.rdb.guilds["OLYMPUS GUILD 001"] = { total = 90, online = 1, t = w.clock - 1 }
	assert(w.D.ReceiveGlobalCensus("CHANNEL", relay, ("CG~1~S~%d~%s"):format(w.clock, table.concat(rows, ";"))))
	local lower, folds = string.lower, 0
	string.lower = function(s)
		if type(s) == "string" and s:find("^[Oo][Ll][Yy][Mm][Pp][Uu][Ss] [Gg][Uu][Ii][Ll][Dd] ") then folds = folds + 1 end
		return lower(s)
	end
	local ok, s = pcall(w.D.Summary)
	string.lower = lower
	assert(ok, s)
	eq(s.characters, 15000, "the newer relayed row replaces the differently spelled direct row")
	eq(#s.guilds, #rows, "one row per guild")
	assert(folds <= 15 * #rows, "too many guild-name folds for one summary: " .. folds)
end)

test("global census: an ordinary late client may ask a trusted holder for the public snapshot", function()
	local holder = CensusWorld()
	local relay, sent = "Council-Realm", 0
	holder.ns.me = relay
	holder.ns.Church = { IsLedgerRelay = function(name) return name == relay end }
	holder.ns.Comm = setmetatable({
		SendChunked = function(payload)
			assert(payload:find("^CG~1~S~"), "the scheduled answer is a census snapshot")
			sent = sent + 1
			return true
		end,
	}, { __index = holder.ns.Comm })
	holder.ns.rdb.guilds["Olympus Dawn"] = {
		total = 987, online = 73, avgLevel = 46.2, t = holder.clock, st = holder.clock,
	}
	assert(holder.D.ReceiveGlobalCensus("CHANNEL", "Latecomer-Realm", "CG~1~Q~2000000000"),
		"an ordinary requester is admitted because a query grants no authority")
	eq(holder.Run(), 1, "one randomized answer is queued")
	eq(sent, 1, "the trusted holder broadcasts its normalized snapshot")
	eq(holder.D.ReceiveGlobalCensus("CHANNEL", "Bad~Name", "CG~1~Q~2000000000"), false,
		"malformed senders are still refused")
end)

-- 10-20 (the lead's audit): the snapshot went to the transport as a keyed job with no permit, which
-- Comm's NormalizeOptions refuses ("guard"), so no trusted holder's snapshot ever left; the tests
-- above stubbed SendChunked and never saw it. Here the real transport (FreshComm, Comm.lua) takes it.
test("global census: a trusted holder's snapshot really reaches the transport's queue and the channel, piece by piece, and stops when his trust goes", function()
	local FreshComm = assert(extra and extra.FreshComm, "tests/run.lua hands FreshComm to this file")
	local saved = { info = C_ChatInfo, channel = GetChannelName, time = GetTime }
	local ok, err = pcall(function()
		local holder = CensusWorld()
		local relay, trusted = "Council-Realm", true
		holder.ns.me = relay
		holder.ns.Church = { IsLedgerRelay = function(name) return trusted and name == relay end }
		holder.ns.Alts = nil
		-- Enough guilds for a snapshot of several pieces.
		for i = 1, 30 do
			holder.ns.rdb.guilds[("Olympus Dawn %02d"):format(i)] = { total = 900 + i, online = 70, avgLevel = 46.2, t = holder.clock, st = holder.clock }
		end
		local cns = FreshComm()
		local C = cns.Comm
		local sent = {}
		C_ChatInfo.SendAddonMessage = function(_, msg, dist) sent[#sent + 1] = { dist = dist, msg = msg } return true end
		GetChannelName = function() return 5 end
		C.JoinChannel()
		holder.ns.Comm = C
		local payload = assert(holder.D.GlobalCensusPayload())
		local pieces = ns.Codec.Chunk(payload, "1")
		assert(#pieces > 1, "a snapshot of several pieces")
		eq(C.QueueSize(), 0)
		eq(holder.D.SendGlobalCensus(), true, "the transport takes the snapshot")
		eq(C.QueueSize(), #pieces, "every piece waits in the send queue")
		local clock = 1000
		GetTime = function() return clock end
		for _ = 1, #pieces * 2 do clock = clock + 2; C.Pump() end
		eq(C.QueueSize(), 0, "all of it went")
		eq(#sent, #pieces, "one channel message per piece")
		for i, m in ipairs(sent) do
			eq(m.dist, "CHANNEL", "on the Olympus channel")
			eq(m.msg, pieces[i], "piece " .. i .. " as Codec.Chunk cut it")
		end
		-- His trust gone mid-way: the permit, asked before each piece, sends no more of it.
		sent = {}
		eq(holder.D.SendGlobalCensus(), true)
		C.Pump()
		eq(#sent, 1, "the first piece went")
		trusted = false
		for _ = 1, #pieces * 2 do clock = clock + 2; C.Pump() end
		eq(#sent, 1, "no piece after his trust went")
		eq(C.QueueSize(), 0, "the rest dropped, not left waiting")
		-- 1.4.0: a member that is no trusted relay may answer too (the witness path, tested below);
		-- a client that is neither sends nothing.
		holder.ns.IsMember = function() return false end
		eq(holder.D.SendGlobalCensus(), false, "a client neither trusted nor a member sends no snapshot")
		eq(C.QueueSize(), 0)
	end)
	C_ChatInfo, GetChannelName, GetTime = saved.info, saved.channel, saved.time
	if not ok then error(err, 0) end
end)

-- 1.4.0, the witnesses (the author, 10-20: "uma pessoa vale uma testemunha... confirmado com 1
-- moderador ou 2+ pessoas concordando", 30 minutes, max(5, 5%); and 11-03: "se múltiplas pessoas me
-- mandam números com os mesmos dados, eu vou confiar"). A world with no trusted relay at all, as on a
-- launch realm before any list is signed for it.
local function WitnessWorld()
	local w = CensusWorld()
	w.ns.Church = { IsLedgerRelay = function() return false end }
	w.ns.Alts = nil
	w.ns.me = "Late-Realm"
	w.ns.IsMember = function() return true end
	return w
end
local function Snapshot(w, rows)
	local out = {}
	for _, r in ipairs(rows) do out[#out + 1] = ("%s,%d,%d,%d,%d"):format(r[1], r[2], r[3] or 50, r[4] or 300, r[5] or w.clock) end
	return ("CG~1~S~%d~%s"):format(w.clock, table.concat(out, ";"))
end

test("global census (1.4.0): two people's agreeing rows confirm a guild on a client that never heard its reporter; one alone does not", function()
	local w = WitnessWorld()
	eq(w.D.ReceiveGlobalCensus("CHANNEL", "First-Realm", Snapshot(w, { { "Olympus Dawn", 640 } })), true)
	eq(w.D.Summary().characters, 0, "one witness")
	eq(w.D.ReceiveGlobalCensus("CHANNEL", "Second-Realm", Snapshot(w, { { "Olympus Dawn", 644, 50, 300, w.clock - 600 } })), true)
	local s = w.D.Summary()
	eq(s.characters, 640, "two people agree (within 5 and half an hour): the newer of the two is taken")
	eq(s.guilds[1].g.relayed, true, "shown as a relayed row, never as the guild's own report")
	eq(w.D.GlobalWitnesses("Olympus Dawn"), 2)
	eq(next(w.ns.rdb.guilds), nil, "no census authority comes of it")
end)

test("global census (1.4.0): rows that disagree in size or time, and one person's two characters, confirm nothing", function()
	local w = WitnessWorld()
	w.D.ReceiveGlobalCensus("CHANNEL", "First-Realm", Snapshot(w, { { "Olympus Dawn", 640 } }))
	w.D.ReceiveGlobalCensus("CHANNEL", "Second-Realm", Snapshot(w, { { "Olympus Dawn", 700 } }))
	eq(w.D.Summary().characters, 0, "640 and 700 are more than max(5, 5%) apart")
	local far = WitnessWorld()
	far.D.ReceiveGlobalCensus("CHANNEL", "First-Realm", Snapshot(far, { { "Olympus Dawn", 640, 50, 300, far.clock } }))
	far.D.ReceiveGlobalCensus("CHANNEL", "Second-Realm", Snapshot(far, { { "Olympus Dawn", 640, 50, 300, far.clock - 31 * 60 } }))
	eq(far.D.Summary().characters, 0, "observed more than half an hour apart")
	local alts = WitnessWorld()
	alts.ns.Alts = { Group = function(name)
		if name == "Main-Realm" or name == "Alt-Realm" then return { main = "Main-Realm", members = {} } end
	end }
	alts.D.ReceiveGlobalCensus("CHANNEL", "Main-Realm", Snapshot(alts, { { "Olympus Dawn", 640 } }))
	alts.D.ReceiveGlobalCensus("CHANNEL", "Alt-Realm", Snapshot(alts, { { "Olympus Dawn", 640 } }))
	eq(alts.D.Summary().characters, 0, "a player's alt is the same witness as his main")
	alts.D.ReceiveGlobalCensus("CHANNEL", "Other-Realm", Snapshot(alts, { { "Olympus Dawn", 641 } }))
	eq(alts.D.Summary().characters, 641, "a second person confirms it")
end)

test("global census (1.4.0): our own direct row is one witness, so one member's newer agreeing row moves the guild forward", function()
	local w = WitnessWorld()
	w.ns.rdb.guilds["Olympus Dawn"] = { total = 640, online = 40, avgLevel = 30, t = w.clock - 1200, st = w.clock - 1200 }
	w.D.ReceiveGlobalCensus("CHANNEL", "First-Realm", Snapshot(w, { { "Olympus Dawn", 646, 41 } }))
	local s = w.D.Summary()
	eq(s.characters, 646, "ours (20 minutes old) and his agree: his newer row is shown")
	w.D.ReceiveGlobalCensus("CHANNEL", "Second-Realm", Snapshot(w, { { "Olympus Dawn", 900, 41 } }))
	eq(w.D.Summary().characters, 646, "a lone row far from every other changes nothing")
end)

test("global census (1.4.0): a late client ends with the same totals as the members it heard, whatever the order", function()
	local rows = { { "Olympus Dawn", 640 }, { "Olympus Dusk", 980 }, { "Olympus Noon", 12, 5 } }
	local function Total(order)
		local w = WitnessWorld()
		for _, who in ipairs(order) do w.D.ReceiveGlobalCensus("CHANNEL", who, Snapshot(w, rows)) end
		return w.D.Summary().characters
	end
	eq(Total({ "First-Realm", "Second-Realm" }), 1632)
	eq(Total({ "Second-Realm", "First-Realm", "Third-Realm" }), 1632)
	-- Agreeing rows of the same time but slightly different sizes: every client shows the same one.
	local function Shown(order)
		local w = WitnessWorld()
		for _, e in ipairs(order) do w.D.ReceiveGlobalCensus("CHANNEL", e[1], Snapshot(w, { { "Olympus Dawn", e[2] } })) end
		return w.D.Summary().characters
	end
	eq(Shown({ { "First-Realm", 640 }, { "Second-Realm", 643 } }), 643)
	eq(Shown({ { "Second-Realm", 643 }, { "First-Realm", 640 } }), 643)
	eq(Shown({ { "Third-Realm", 641 }, { "Second-Realm", 643 }, { "First-Realm", 640 } }), 643)
end)

test("global census (1.4.0): an ask carries what its client holds; a member answers one behind it, late and announced, and holds back after two answers or a trusted one", function()
	local function Holder()
		local w = WitnessWorld()
		w.ns.me = "Holder-Realm"
		w.sent = {}
		w.ns.Comm = {
			Send = function(dist, text) w.sent[#w.sent + 1] = { kind = "send", dist = dist, text = text } return true end,
			SendChunked = function(payload, _, dist) w.sent[#w.sent + 1] = { kind = "chunked", dist = dist, text = payload } return true end,
		}
		w.ns.rdb.guilds["Olympus Dawn"] = { total = 640, online = 40, avgLevel = 30, t = w.clock, st = w.clock }
		w.ns.rdb.guilds["Olympus Dusk"] = { total = 980, online = 70, avgLevel = 31, t = w.clock, st = w.clock }
		return w
	end
	-- What the ask says.
	local asker = Holder()
	asker.D.AskGlobalCensus()
	eq(asker.sent[1].text, ("CG~1~Q~%d~2~%d"):format(asker.clock, asker.clock), "two guilds, the newest observed now")
	-- Behind: answered after the members' delay, a claim first, then the snapshot.
	local h = Holder()
	eq(h.D.ReceiveGlobalCensus("CHANNEL", "Latecomer-Realm", ("CG~1~Q~%d~0~0"):format(h.clock)), true)
	eq(#h.timers, 1, "one answer scheduled")
	assert(h.timers[1].seconds >= h.D.MEMBER_ANSWER_AFTER, "a member answers after the trusted relays' 2-9 s")
	h.Run()
	eq(#h.sent, 2)
	eq(h.sent[1].text, ("CG~1~C~%d"):format(h.clock), "the claim first")
	assert(h.sent[2].text:find("^CG~1~S~"), "then the snapshot")
	assert(h.sent[2].text:find("Olympus Dawn,640,40,300", 1, true) and h.sent[2].text:find("Olympus Dusk,980,70,310", 1, true))
	-- Not behind: no answer.
	local even = Holder()
	even.D.ReceiveGlobalCensus("CHANNEL", "Latecomer-Realm", ("CG~1~Q~%d~2~%d"):format(even.clock, even.clock))
	eq(#even.timers, 0, "the asker holds as much: nothing to send")
	-- A 1.3.3 ask says nothing of what it holds: answered.
	local old = Holder()
	old.D.ReceiveGlobalCensus("CHANNEL", "Latecomer-Realm", ("CG~1~Q~%d"):format(old.clock))
	eq(#old.timers, 1)
	-- Two answers heard meanwhile (two claims): it holds back.
	local quiet = Holder()
	quiet.D.ReceiveGlobalCensus("CHANNEL", "Latecomer-Realm", ("CG~1~Q~%d~0~0"):format(quiet.clock))
	quiet.D.ReceiveGlobalCensus("CHANNEL", "First-Realm", ("CG~1~C~%d"):format(quiet.clock))
	quiet.D.ReceiveGlobalCensus("CHANNEL", "Second-Realm", ("CG~1~C~%d"):format(quiet.clock))
	quiet.Run()
	eq(#quiet.sent, 0, "two members answered already")
	-- One trusted answer heard meanwhile: it holds back too.
	local relayed = Holder()
	relayed.ns.Church.IsLedgerRelay = function(name) return name == "Council-Realm" end
	relayed.D.ReceiveGlobalCensus("CHANNEL", "Latecomer-Realm", ("CG~1~Q~%d~0~0"):format(relayed.clock))
	relayed.D.ReceiveGlobalCensus("CHANNEL", "Council-Realm", Snapshot(relayed, { { "Olympus Dawn", 640 } }))
	relayed.Run()
	eq(#relayed.sent, 0, "a trusted relay answered")
	-- Our own claim or ask echoed back by the channel is not someone else's.
	local echo = Holder()
	echo.D.ReceiveGlobalCensus("CHANNEL", "Latecomer-Realm", ("CG~1~Q~%d~0~0"):format(echo.clock))
	echo.D.ReceiveGlobalCensus("CHANNEL", "Holder-Realm", ("CG~1~C~%d"):format(echo.clock))
	echo.D.ReceiveGlobalCensus("CHANNEL", "Holder-Realm", ("CG~1~C~%d"):format(echo.clock))
	echo.Run()
	eq(#echo.sent, 2, "its own echoes do not hold it back")
	-- Quiet presence, or not a member: no answer.
	local hidden = Holder()
	hidden.ns.QuietPresence = function() return true end
	hidden.D.ReceiveGlobalCensus("CHANNEL", "Latecomer-Realm", ("CG~1~Q~%d~0~0"):format(hidden.clock))
	eq(#hidden.timers, 0)
	eq(hidden.D.SendGlobalCensus(), false)
end)

test("global census (1.4.0): asks at login, again after GLOBAL_ASK_AGAIN, then every half hour", function()
	local w = WitnessWorld()
	local every
	w.ns.Every = function(seconds, where, fn) every = { seconds = seconds, where = where } end
	w.ns.Comm = { Handle = function() end }
	w.Fire("INIT")
	local delays = {}
	for _, t in ipairs(w.timers) do if t.where:find("global census ask") then delays[#delays + 1] = t.seconds end end
	table.sort(delays)
	eq(#delays, 2)
	eq(delays[1], 20)
	eq(delays[2], 20 + w.D.GLOBAL_ASK_AGAIN)
	eq(every and every.seconds, 30 * 60)
end)

-- 1.4.0, every server's numbers (CX): a world on a launch realm group.
local function GroupWorld(me)
	local w = WitnessWorld()
	w.ns.me = me or "Late-Realm"
	w.ns.db = {}
	w.ns.group, w.ns.faction = "Launchpve", "Alliance"
	w.sent = {}
	w.ns.Comm = {
		Send = function(dist, text) w.sent[#w.sent + 1] = text return true end,
		SendChunked = function(payload) w.sent[#w.sent + 1] = payload return true end,
	}
	return w
end
local function Say(w, rows)
	local out = {}
	for _, r in ipairs(rows) do out[#out + 1] = ("%s|%s|%d|%d|%d|%d"):format(r[1], r[2] or "Alliance", r[3], r[4] or r[3], r[5] or 3, r[6] or w.clock) end
	return ("CX~1~S~%d~%s"):format(w.clock, table.concat(out, ";"))
end

test("census scope: legacy relay-stamped mixed counts remain saved but cannot populate the local census or renew its snapshot", function()
	local w = GroupWorld()
	w.ns.group, w.ns.realm = "ForeverPvP", "CAMWOWUS1Realm8PvP"
	local r = w.ns.rdb
	r.guilds["Olympus Local"] = { total = 182, online = 8, t = w.clock, from = w.ns.realm }
	r.censusGlobal = { foreign = { name = "Olympus Foreign", total = 900, online = 20, avg10 = 200,
		observed = w.clock - 60, by = "Relay-" .. w.ns.realm } }
	r.censusWitness = { foreign = { witness = { total = 900, observed = w.clock - 60 } } }
	r.verify = { list = { untouched = { state = "A", at = w.clock - 200 } }, starts = { untouched = w.clock - 800 } }
	local verdict, legacy = r.verify, r.censusGlobal.foreign
	w.ns.db.realms = { ForeverPvP = r }
	local pve = { guilds = { ["Olympus Valid"] = { total = 6967, from = "CAMWOWUS1Realm1PvE", t = w.clock - 30 } },
		censusGlobal = { old = { name = "Olympus Valid", total = 6967, observed = w.clock - 60 } } }
	-- Use seven real-sized guilds, each independently scoped, to substantiate the other snapshot.
	pve.guilds = {}
	for i = 1, 7 do pve.guilds["Olympus Valid " .. i] = { total = i == 7 and 967 or 1000, from = "CAMWOWUS1Realm1PvE", t = w.clock - 30 } end
	w.ns.db.realms.ForeverPvE = pve
	w.ns.db.groupCensus = { ["Alliance|ForeverPvP"] = { group = "ForeverPvP", faction = "Alliance", characters = 13614,
		people = 13614, guilds = 92, observed = w.clock - 300, src = "own" },
		["Alliance|ForeverPvE"] = { group = "ForeverPvE", faction = "Alliance", characters = 6967,
		people = 6967, guilds = 7, observed = w.clock - 60, src = "own" } }
	w.ns.db.groupDetails = { ["Alliance|ForeverPvP"] = { group = "ForeverPvP", faction = "Alliance", observed = w.clock,
		rows = { foreign = legacy }, source = "own" } }
	w.ns.Comm.loginAt = w.clock
	w.Fire("INIT")
	local s = w.D.Summary()
	eq(s.characters, 182); eq(#s.guilds, 1); eq(s.snapshot, nil)
	eq(s.history.characters, 13614); eq(s.history.unscoped, true)
	eq(r.censusUnscoped.global.foreign, legacy, "the original bytes stay available, without inferred scope")
	eq(r.verify, verdict); eq(r.verify.starts.untouched, w.clock - 800)
	eq(#w.D.GroupGuilds("ForeverPvP"), 0)
	eq(w.D.Groups(s).characters, 7149, "the independently substantiated other origin remains in the all-server sum")
	eq(w.ns.db.groupCensus["Alliance|ForeverPvE"].observed, w.clock - 60)
	w.ns.group = "ForeverPvE"
	eq(w.D.GroupCensusPayload(), nil, "the mislabeled historical aggregate cannot travel")
	eq(w.D.SayGroupDetails(), false)
	w.D.MigrateCensusScope()
	eq(r.censusUnscoped.global.foreign, legacy, "migration is idempotent")
end)

test("census scope: scoped count snapshots reject another ruleset and legacy unsourced counts even from a trusted forwarder", function()
	local source, pvp, pve = GroupWorld(), GroupWorld(), GroupWorld()
	for _, w in ipairs({ source, pvp, pve }) do w.ns.Church.IsLedgerRelay = function() return true end end
	source.ns.group, pvp.ns.group, pve.ns.group = "ForeverPvE", "ForeverPvP", "ForeverPvE"
	source.ns.rdb.guilds["Olympus Foreign"] = { total = 640, online = 40, t = source.clock,
		from = "CAMWOWUS1Realm1PvE", home = "CAMWOWAU1Realm1PvE" }
	local wire = assert(source.D.GlobalCensusPayload())
	assert(wire:find("CG~2~S~", 1, true))
	eq(pvp.D.ReceiveGlobalCensus("CHANNEL", "Trusted-Realm", wire), false)
	eq(pvp.D.ReceiveGlobalCensus("CHANNEL", "Trusted-Realm", Snapshot(pvp, { { "Olympus Foreign", 640 } })), false)
	eq(pvp.D.Summary().characters, 0)
	assert(pve.D.ReceiveGlobalCensus("CHANNEL", "Trusted-Realm", wire))
	eq(pve.D.Summary().characters, 640)
	eq(pve.ns.rdb.censusGlobal["olympus foreign"].scope, "ForeverPvE")
	eq(next(pve.ns.rdb.guilds), nil, "counts never become authority")
end)

test("census overflow: scoped snapshots cover row and byte overflow at the existing receiver cadences", function()
	for _, byteLimited in ipairs({ false, true }) do
		local source, tree, mesh, foreign = GroupWorld("Trusted-Realm"), GroupWorld(), GroupWorld(), GroupWorld()
		for _, w in ipairs({ source, tree, mesh, foreign }) do
			w.ns.group = "ForeverPvP"
			w.ns.Church.IsLedgerRelay = function(name) return name == source.ns.me end
		end
		foreign.ns.group = "ForeverPvE"
		local D, start, guilds = source.D, source.clock, {}
		local count = byteLimited and 45 or 245
		if byteLimited then D.GLOBAL_SEND_BYTES = 1000 end
		for i = 1, count do
			local name = ("Olympus Unit %03d%s"):format(i, byteLimited and ("X"):rep(i % 8) or "")
			guilds[i] = name
			source.ns.rdb.guilds[name] = { total = 100, online = 10, avgLevel = 30, t = start - i, st = start - i,
				from = "CAMWOWUS1Realm8PvP" }
		end
		local maxBytes = D.GLOBAL_SEND_BYTES
		if not byteLimited then
			local header = ("CG~2~S~%d~ForeverPvP~Alliance~"):format(start)
			local row = ("%s,100,10,300,%d;"):format(guilds[1], start - 1)
			maxBytes = #header + D.GLOBAL_MAX_ROWS * #row - 1
		end
		for tick = 0, 39 do
			source.clock = start + tick * 120
			local wire = assert(D.GlobalCensusPayload())
			assert(#wire <= maxBytes, "overflow keeps the original transfer budget")
			assert(wire:find(guilds[1] .. ",", 1, true), "the freshest guild always has space")
			assert(not foreign.D.ReceiveGlobalCensus("CHANNEL", source.ns.me, wire))
			for _, target in ipairs({ { tree, 2 }, { mesh, 3 } }) do
				local w, every = target[1], target[2]
				w.clock = source.clock
				if tick % every == 0 then assert(w.D.ReceiveGlobalCensus("CHANNEL", source.ns.me, wire)) end
			end
		end
		for _, w in ipairs({ tree, mesh }) do
			eq(w.D.Summary().characters, 100 * count, "overflow guilds arrive without erasing other rows")
			eq(next(w.ns.rdb.guilds), nil, "counts grant no guild authority")
			for i, name in ipairs(guilds) do
				local row = w.ns.rdb.censusGlobal[name:lower()]
				eq(row.observed, start - i, "relay receipt never renews the observation")
			end
		end
	end
end)

test("census observed freshness: a late direct report ages like its relayed copy", function()
	local direct, relayed = GroupWorld("Trusted-Realm"), GroupWorld()
	local realm = "CAMWOWUS1Realm8PvP"
	for _, w in ipairs({ direct, relayed }) do
		w.ns.group, w.ns.realm = "ForeverPvP", realm
		w.ns.Church.IsLedgerRelay = function(name) return name == direct.ns.me end
	end
	local D, at = direct.D, direct.clock
	local function Receive(guild, sender, stamp)
		local r = assert(Decode({ guild = guild, total = 100, online = 10, zones = { m1453 = 10 }, from = realm, st = stamp }))
		assert(D.Receive(r, sender .. "-" .. realm))
		eq(r.t, at, "receive time remains available separately")
		return r
	end
	Receive("Olympus Old", "Older", at - D.FRESH - 1)
	Receive("Olympus Ancient", "Ancient", at - D.TOTAL_KEEP - 1)
	assert(relayed.D.ReceiveGlobalCensus("CHANNEL", direct.ns.me, assert(D.GlobalCensusPayload())))
	for _, w in ipairs({ direct, relayed }) do
		local s = w.D.Summary()
		eq(s.characters, 100, "a day-old observation is no longer counted even if just received")
		eq(s.online, 0, "a late observation does not make old online figures live")
		eq(s.fresh, 0)
		eq(s.newest, 0)
		eq(next(s.zones), nil)
		eq(s.guilds[1].fresh, false)
	end
	Receive("Olympus Legacy", "Legacy", nil)
	Receive("Olympus Ahead", "Ahead", at + 1200)
	local s = D.Summary()
	eq(s.characters, 300)
	eq(s.online, 20, "an unstamped report still uses receipt time")
	eq(s.fresh, 2)
	eq(s.newest, at, "a future stamp cannot extend the receipt-based age")
end)

test("census scope: explicit foreign observation and guild home never enter local summary, votes or outbound counts", function()
	local w = GroupWorld()
	w.ns.group, w.ns.realm = "ForeverPvP", "CAMWOWUS1Realm8PvP"
	local r = assert(Decode({ guild = "Olympus Foreign", total = 640, online = 40, from = "CAMWOWUS1Realm1PvE" }))
	eq(w.D.Receive(r, "Witness-" .. w.ns.realm), false)
	local legacy = assert(Decode({ guild = "Olympus Foreign", total = 640, online = 40 }))
	eq(w.D.Receive(legacy, "Witness-CAMWOWUS1Realm1PvE"), false, "the native sender scope also rejects old reports lacking from")
	eq(next(w.ns.rdb.guilds), nil)
	w.ns.rdb.guilds["Olympus Foreign"] = { total = 640, online = 40, t = w.clock,
		from = w.ns.realm, heardOn = w.ns.realm, home = "CAMWOWUS1Realm1PvE" }
	eq(w.D.Summary().characters, 0)
	eq(w.D.GlobalDigest(), 0)
	assert(not w.D.GlobalCensusPayload():find("Olympus Foreign", 1, true))
end)

test("census scope: portable observations reach a virgin opposite-ruleset client through ordinary holders without multiplying witnesses", function()
	for _, pair in ipairs({ { "PvE", "PvP" }, { "PvP", "PvE" } }) do
		local source = GroupWorld("Original-CAMWOWUS1Realm1" .. pair[1])
		source.ns.group, source.ns.realm = "Forever" .. pair[1], "CAMWOWUS1Realm1" .. pair[1]
		source.ns.rdb.guilds["Olympus Origin"] = { total = 640, online = 40, t = source.clock - 600, from = source.ns.realm,
			leader = "Private Leader", officers = { "Private Officer" }, zones = { private = 30 } }
		assert(source.D.RecordGroupCensus())
		local original = assert(source.D.PortablePayload())
		assert(not original:find("Private", 1, true)); assert(not original:find("private", 1, true))
		local first, second, virgin = GroupWorld("CarrierA-Realm"), GroupWorld("CarrierB-Realm"), GroupWorld("New-Realm")
		for _, w in ipairs({ first, second, virgin }) do
			w.ns.group, w.ns.realm = "Forever" .. pair[2], "CAMWOWEU1Realm1" .. pair[2]
			w.ns.rdb.guilds["Olympus Local"] = { total = 100, online = 10, t = w.clock, from = w.ns.realm }
		end
		assert(first.D.ReceiveGroupCensus("CHANNEL", "Traveller-Realm", original))
		local hop = assert(first.D.PortablePayload())
		eq(hop, original, "receipt never rewrites observer, scope, date or counts")
		assert(second.D.ReceiveGroupCensus("CHANNEL", first.ns.me, hop))
		assert(virgin.D.ReceiveGroupCensus("CHANNEL", second.ns.me, assert(second.D.PortablePayload())))
		assert(virgin.D.ReceiveGroupCensus("CHANNEL", first.ns.me, hop))
		local summary, all = virgin.D.Summary(), virgin.D.Groups()
		eq(summary.characters, 100); eq(#summary.guilds, 1)
		eq(all.characters, 100, "two forwards of one original never manufacture a validated count")
		eq(#all.rows, 2); eq(all.rows[2].characters, 640); eq(all.rows[2].counted, false)
		eq(all.rows[2].observed, source.clock - 600); eq(all.rows[2].validation, "reported")
		local detail = virgin.D.GroupGuilds(source.ns.group)
		eq(#detail, 1); eq(detail[1].characters, 640); eq(detail[1].counted, false)
		local reload = GroupWorld("Reload-Realm")
		reload.ns.db, reload.ns.group = virgin.ns.db, virgin.ns.group
		eq(reload.D.PortablePayload(), original, "the same provenance survives reload")
		reload.clock = source.clock + reload.D.GROUP_KEEP + 1
		eq(reload.D.PortablePayload(), nil, "forwarding never renews the original observation")
	end
end)

test("census scope: a validated scoped snapshot restores an empty login immediately and a complete newer snapshot can lower the count", function()
	local source, late = GroupWorld("Trusted-Realm"), GroupWorld()
	for _, w in ipairs({ source, late }) do
		w.ns.group = "ForeverPvP"
		w.ns.Church.IsLedgerRelay = function(name) return name == "Trusted-Realm" end
	end
	source.ns.rdb.guilds["Olympus Dawn"] = { total = 640, online = 40, t = source.clock - 100, from = "CAMWOWUS1Realm8PvP" }
	source.ns.rdb.guilds["Olympus Dusk"] = { total = 360, online = 30, t = source.clock - 100, from = "CAMWOWUS1Realm8PvP" }
	late.ns.Comm.loginAt = late.clock
	assert(late.D.ReceiveGlobalCensus("CHANNEL", source.ns.me, assert(source.D.GlobalCensusPayload())))
	eq(late.D.Summary().characters, 1000); eq(#late.D.Summary().guilds, 2)
	eq(next(late.ns.rdb.guilds), nil, "foreground counts never create guild authority")
	assert(late.D.RecordGroupCensus())
	late.ns.rdb.censusGlobal = {}
	local saved = late.D.Summary()
	eq(saved.characters, 1000); eq(saved.snapshot.observed, source.clock - 100)
	late.ns.rdb.guilds["Olympus Dawn"] = { total = 500, online = 40, t = source.clock - 200, from = "CAMWOWUS1Realm8PvP" }
	late.ns.rdb.guilds["Olympus Dusk"] = { total = 300, online = 30, t = source.clock - 200, from = "CAMWOWUS1Realm8PvP" }
	eq(late.D.Summary().characters, 1000, "complete but older coverage cannot replace a newer saved census")
	late.ns.rdb.guilds = {}
	source.clock = source.clock + 60
	source.ns.rdb.guilds["Olympus Dawn"].total, source.ns.rdb.guilds["Olympus Dawn"].t = 600, source.clock
	source.ns.rdb.guilds["Olympus Dusk"].total, source.ns.rdb.guilds["Olympus Dusk"].t = 300, source.clock
	late.clock = source.clock
	assert(late.D.ReceiveGlobalCensus("CHANNEL", source.ns.me, assert(source.D.GlobalCensusPayload())))
	eq(late.D.Summary().characters, 900); eq(late.D.Summary().snapshot, nil)
end)

test("census Top Levels: fresh same-scope player details survive a newer count-only snapshot", function()
	local w, realm = GroupWorld(), "CAMWOWUS1Realm8PvP"
	local relay = "Council-" .. realm
	w.ns.group, w.ns.realm = "ForeverPvP", realm
	w.ns.Church.IsLedgerRelay = function(name) return name == relay end
	assert(loadfile(ROOT .. "Olympus/Views.lua"))("Olympus", w.ns)
	local function Detail(name, at, home)
		return { total = 90, online = 10, t = w.clock - 10, st = at, from = home, realm = home,
			top = { { name = name, level = 40, class = "WA" } } }
	end
	local guilds = w.ns.rdb.guilds
	guilds["OLYMPUS DAWN"] = Detail("Fresh Scout", w.clock - 10, realm)
	guilds["Olympus Dusk"] = Detail("Stale Scout", w.clock - w.D.FRESH - 1, realm)
	guilds["Olympus Noon"] = Detail("Foreign Scout", w.clock - 10, "CAMWOWUS1Realm8PvE")
	local rows = {}
	for i, guild in ipairs({ "Olympus Dawn", "Olympus Dusk", "Olympus Noon" }) do
		rows[i] = ("%s,100,10,400,%d"):format(guild, w.clock)
	end
	local wire = ("CG~2~S~%d~ForeverPvP~Alliance~%s"):format(w.clock, table.concat(rows, ";"))
	assert(w.D.ReceiveGlobalCensus("CHANNEL", relay, wire))
	local s = w.D.Summary()
	eq(s.characters, 300, "newer accepted counts still win")
	for _, e in ipairs(s.guilds) do eq(e.g.top, nil, "the count-only row acquires no rank authority") end
	local function Read()
		local players, note = {}, nil
		local label = w.ns.L.LEVEL_RACE_REPORTS_PENDING
		local expected = label and label:format(1, 3)
		for _, line in ipairs(w.ns.Views.RealmLines()) do
			if line.key then players[line.key] = true end
			if expected and line.text and line.text:find(expected, 1, true) then note = line end
		end
		return players, note
	end
	local players, note = Read()
	assert(players["Fresh Scout"], "a fresh in-scope top player survives the count-only relay update")
	eq(players["Stale Scout"], nil, "receipt time cannot make an old player report fresh")
	eq(players["Foreign Scout"], nil, "another ruleset cannot fill the missing detail")
	assert(note and note.tooltip, "players are told that only one guild has recent level data")
	local explanation
	note.tooltip({ AddLine = function(_, line) explanation = line end })
	assert(explanation and explanation:find("/oly bug", 1, true), "the tooltip includes the reporting command")
	guilds["Olympus Dusk"] = Detail("New Scout", w.clock - 5, realm)
	guilds["Olympus Noon"] = Detail("Local Scout", w.clock - 5, realm)
	players, note = Read()
	assert(players["New Scout"] and players["Local Scout"], "fresh details fill the gaps")
	eq(note, nil, "complete coverage removes the pending label")
end)

-- 1.5.4 (the dev's account store of 2026-11-07, replayed through 1.5.3: in 45 minutes his PvE client
-- said 21 carried looks, each another player's one-guild look, and never its own 19-guild look of
-- PvP). Fails before: the carrier walked every observer's look of an origin, and a newer one stood
-- for the origin until its window closed, so the account's own complete look was skipped each time.
test("census carry: a carrier says one look per origin, its own account's first, never every observer's look of it", function()
	local w = GroupWorld("Zed Own-CAMWOWUS1Realm8PvP")
	w.ns.group, w.ns.realm = "ForeverPvP", "CAMWOWUS1Realm8PvP"
	for i = 1, 19 do w.ns.rdb.guilds["Olympus Pvp " .. i] = { total = 190 + i, online = 20, t = w.clock - 60, from = w.ns.realm } end
	assert(w.D.RecordGroupCensus())
	local own = assert(w.D.PortablePayload())
	-- An hour later, on PvE: two other players' newer one-guild looks of PvP heard (their names sort first).
	w.ns.me, w.ns.group, w.ns.realm, w.ns.rdb.guilds = "Carrier-CAMWOWUS2Realm1PvE", "ForeverPvE", "CAMWOWUS2Realm1PvE", {}
	w.clock = w.clock + 3600
	for i, who in ipairs({ "Abe One-CAMWOWUS1Realm6PvP", "Bob Two-CAMWOWUS1Realm4PvP" }) do
		assert(w.D.ReceiveGroupCensus("CHANNEL", "Some Carrier-CAMWOWUS2Realm1PvE",
			("CX~3~S~%s~ForeverPvP~Alliance~%d,%d,1,%d~"):format(who, 100 * i, 100 * i, w.clock - 600 + 60 * i)))
	end
	w.sent = {}
	for _ = 1, 27 do -- the turns of one half-hour window
		w.D.SayGroupCensus()
		w.clock = w.clock + w.D.GROUP_SEND_GAP
	end
	local carried = {}
	for _, p in ipairs(w.sent) do if p:match("^CX~3~") then carried[#carried + 1] = p end end
	eq(carried[1], own, "the account's own complete look is the one said")
	eq(#carried, 1, "one look for the origin in its window, not one per observer")
end)

test("census groups (1.4.0): our own look at our realm group is kept and carried to another group, where it is said; ours is never said where everyone sees it live", function()
	local w = GroupWorld("Traveller-Realm")
	w.ns.rdb.guilds["Olympus Dawn"] = { total = 640, online = 40, avgLevel = 30, t = w.clock, st = w.clock }
	eq(w.D.RecordGroupCensus(), true)
	local kept = w.ns.db.groupCensus["Alliance|Launchpve"]
	eq(kept.characters, 640); eq(kept.src, "own"); eq(kept.guilds, 1)
	eq(w.D.GroupCensusPayload(), nil, "on its own group: nothing to say")
	-- The same account on another group (a PvP character): it says the PvE group's numbers there.
	w.ns.group = "Launchpvp"
	w.clock = w.clock + 600
	local said = w.D.GroupCensusPayload()
	-- (1.5.4) Commas, not the "|" of 1.4.0: Comm's OnAddonMessage drops every received "|" (0.9.2), so
	-- no client ever parsed a 1.4.0 row (the dev's stores hold no "relay" or "witnessed" group row).
	eq(said, ("CX~1~S~%d~Launchpve,Alliance,640,640,1,%d"):format(w.clock, w.clock - 600))
	eq(Codec.Plain(said), said, "the row survives the receiver's escape-code filter")
	eq(w.D.SayGroupCensus(), true)
	-- One other traveller is insufficient for everyone else on this channel: our independent
	-- observation must still leave, even though we can already corroborate it locally.
	w.D.ReceiveGroupCensus("CHANNEL", "Other-Realm", Say(w, { { "Launchpve", "Alliance", 641, 641, 1, w.clock - 600 } }))
	assert(w.D.GroupCensusPayload(), "one traveller must not suppress the second confirmation")
	w.D.ReceiveGroupCensus("CHANNEL", "Third-Realm", Say(w, { { "Launchpve", "Alliance", 641, 641, 1, w.clock - 600 } }))
	eq(w.D.GroupCensusPayload(), nil, "two independent travellers already heard here")
end)

test("census continuity: one claimant and its snapshot do not suppress a second independent global answer", function()
	local w = GroupWorld("Holder-Realm")
	w.ns.rdb.guilds["Olympus Dawn"] = { total = 640, online = 40, avgLevel = 30, t = w.clock }
	w.D.ReceiveGlobalCensus("CHANNEL", "Late-Realm", ("CG~1~Q~%d~0~0"):format(w.clock))
	w.D.ReceiveGlobalCensus("CHANNEL", "First-Realm", ("CG~1~C~%d"):format(w.clock))
	w.D.ReceiveGlobalCensus("CHANNEL", "First-Realm", Snapshot(w, { { "Olympus Dawn", 640 } }))
	w.Run()
	eq(#w.sent, 2, "claim plus body is one person, so this holder supplies the second answer")
end)

test("census continuity: the same character on two Forever sub-realms is only one witness", function()
	local w = GroupWorld()
	local payload = Say(w, { { "Launchpvp", "Alliance", 3000, 2500 } })
	w.D.ReceiveGroupCensus("CHANNEL", "Traveller-CAMWOWUS1Realm1PvE", payload)
	w.D.ReceiveGroupCensus("CHANNEL", "Traveller-CAMWOWUS2Realm5PvE", payload)
	eq(w.D.Groups().characters, 0)
	w.D.ReceiveGroupCensus("CHANNEL", "Other-CAMWOWUS2Realm5PvE", payload)
	eq(w.D.Groups().characters, 3000)
end)

test("census continuity: cross-ruleset origins normalize before voting and never enter local authority", function()
	local w = GroupWorld()
	w.ns.group = "ForeverPvP"
	w.D.ReceiveGroupCensus("CHANNEL", "First-Realm", Say(w, { { "CAMWOWUS1Realm1PvE", "Alliance", 3000, 2500 } }))
	w.D.ReceiveGroupCensus("CHANNEL", "Second-Realm", Say(w, { { "ForeverPvE", "Alliance", 3000, 2500 } }))
	local g = w.D.Groups()
	eq(g.characters, 0, "legacy forwards lack independent original observations"); eq(#g.rows, 1); eq(g.rows[1].group, "ForeverPvE")
	eq(next(w.ns.rdb.guilds), nil)
	w.D.ReceiveGroupCensus("CHANNEL", "Third-Realm", Say(w, { { "CAMWOWUS1Realm1PvP", "Alliance", 9000 } }))
	w.D.ReceiveGroupCensus("CHANNEL", "Fourth-Realm", Say(w, { { "CAMWOWUS1Realm1PvP", "Alliance", 9000 } }))
	eq(w.D.Groups().characters, 0, "a sub-realm alias cannot smuggle our own aggregate in")
	w.D.ReceiveGroupCensus("CHANNEL", "First-Realm", Say(w, { { "CAMWOWUS1Realm1PvP+CAMWOWUS1Realm1PvE", "Alliance", 9000 } }))
	eq(#w.D.Groups().rows, 1, "a mixed-ruleset origin is invalid")
	w.ns.db.groupCensus["Alliance|CAMWOWUS1Realm1PvE"] = { group = "CAMWOWUS1Realm1PvE", faction = "Alliance",
		characters = 3001, people = 2501, guilds = 3, observed = w.clock + 1, src = "own" }
	w.clock = w.clock + w.D.FRESH + 2
	w.ns.db.groupCensus["Alliance|CAMWOWUS1Realm1PvE"].observed = w.clock
	eq(w.D.GroupCensusPayload(), nil, "legacy saved aliases cannot become new observer claims")
	local groups = w.D.Groups()
	eq(#groups.rows, 1); eq(groups.rows[1].group, "ForeverPvE")
end)

test("census continuity: recording a cached census preserves observation time and login displays its retained origin", function()
	local w = GroupWorld()
	w.ns.rdb.guilds["Olympus Dawn"] = { total = 640, online = 40, avgLevel = 30, t = w.clock - 600 }
	w.ns.rdb.guilds["Olympus Dusk"] = { total = 360, online = 30, avgLevel = 30, t = w.clock - 300 }
	assert(w.D.RecordGroupCensus())
	local kept = w.ns.db.groupCensus["Alliance|Launchpve"]
	eq(kept.observed, w.clock - 600, "sampling never makes old reports newly observed")
	w.ns.rdb.guilds = {}
	w.ns.Comm.loginAt = w.clock
	local empty = w.D.Summary()
	eq(empty.characters, 1000); eq(empty.online, 0); eq(#empty.guilds, 0)
	eq(empty.snapshot.observed, kept.observed); eq(empty.snapshot.group, "Launchpve"); eq(empty.live.characters, 0)
	eq(w.D.RecordGroupCensus(empty), false, "a fallback cannot renew itself")
	w.ns.rdb.guilds["Olympus Dawn"] = { total = 630, online = 20, t = w.clock }
	local partial = w.D.Summary()
	eq(partial.characters, 1000); eq(partial.live.characters, 630); eq(partial.online, 20)
	local groups = w.D.Groups(partial)
	eq(groups.characters, 1000); eq(#groups.rows, 1); eq(groups.rows[1].src, "own"); eq(groups.rows[1].observed, kept.observed)
	w.ns.rdb.guilds["Olympus Dusk"] = { total = 350, online = 10, t = w.clock }
	local rebuilt = w.D.Summary()
	eq(rebuilt.characters, 980); eq(rebuilt.snapshot, nil, "complete fresh rows reconcile a real lower count")
	w.ns.rdb.guilds = {}
	w.clock = w.clock + w.D.REBUILD_FOR + 1
	eq(w.D.Summary().snapshot.observed, kept.observed, "an incomplete rebuild keeps its dated snapshot")
	w.clock = kept.observed + w.D.TOTAL_KEEP + 1
	local stale = w.D.Summary()
	eq(stale.snapshot, nil); eq(stale.characters, 0)
	eq(stale.history.characters, 1000); eq(stale.history.counted, false, "an expired count remains separate historical information")
end)

test("census continuity: an extra older counted guild cannot veto complete newer coverage", function()
	local w = GroupWorld()
	w.ns.rdb.guilds["Olympus Dawn"] = { total = 640, online = 40, t = w.clock - 600 }
	w.ns.rdb.guilds["Olympus Dusk"] = { total = 360, online = 30, t = w.clock - 300 }
	assert(w.D.RecordGroupCensus())
	w.ns.Comm.loginAt = w.clock
	w.ns.rdb.guilds["Olympus Dawn"] = { total = 630, online = 20, t = w.clock }
	w.ns.rdb.guilds["Olympus Dusk"] = { total = 350, online = 10, t = w.clock }
	w.ns.rdb.guilds["Olympus Ash"] = { total = 120, online = 5, t = w.clock - w.D.FRESH - 1 }
	local s = w.D.Summary()
	eq(s.characters, 1100, "all counted rows contribute their actual totals after newer coverage is complete")
	eq(s.total, 1100); eq(s.snapshot, nil); eq(#s.guilds, 3)
	eq(s.online, 30, "the older guild contributes no online presence")
end)

test("census continuity: older counted guilds cannot fill a gap in newer coverage", function()
	local w = GroupWorld()
	w.ns.rdb.guilds["Olympus Dawn"] = { total = 640, online = 40, t = w.clock - 600 }
	w.ns.rdb.guilds["Olympus Dusk"] = { total = 360, online = 30, t = w.clock - 300 }
	assert(w.D.RecordGroupCensus())
	w.ns.Comm.loginAt = w.clock
	w.ns.rdb.guilds["Olympus Dawn"] = { total = 630, online = 20, t = w.clock }
	w.ns.rdb.guilds["Olympus Dusk"] = nil
	w.ns.rdb.guilds["Olympus Ash"] = { total = 120, online = 5, t = w.clock - w.D.FRESH - 1 }
	local s = w.D.Summary()
	eq(s.characters, 1000, "incomplete newer coverage still shows the retained census")
	eq(s.snapshot.guilds, 2); eq(s.snapshot.observed, w.clock - 600)
	eq(s.live.characters, 750); eq(s.live.guilds, 2, "live coverage still includes every counted guild")
	eq(s.online, 20)
end)

test("census continuity: an incomplete saved view also carries current partial totals from original observations", function()
	local w = GroupWorld()
	local at = w.clock
	w.ns.rdb.guilds["Olympus Dawn"] = { total = 640, online = 40, t = at - 600 }
	w.ns.rdb.guilds["Olympus Dusk"] = { total = 360, online = 30, t = at - 300 }
	assert(w.D.RecordGroupCensus())
	w.ns.Comm.loginAt = at
	w.clock = at + w.D.REBUILD_FOR + 1
	w.ns.rdb.guilds["Olympus Dawn"] = { total = 630, online = 20, t = w.clock }
	w.ns.rdb.guilds["Olympus Dusk"] = nil
	w.ns.rdb.guilds["Olympus Ash"] = { total = 120, online = 5, t = w.clock, st = at - w.D.FRESH }
	local s = w.D.Summary()
	eq(s.characters, 1000, "saved population stays visible while coverage is incomplete")
	eq(s.snapshot.observed, at - 600)
	eq(s.live.guilds, 2, "the last-day partial sum still includes the older guild")
	eq(s.live.freshGuilds, 1, "receiving a stale report now does not make its observation fresh")
	eq(s.live.freshCharacters, 630)
	w.ns.rdb.guilds["Olympus Dawn"].total = 620
	s = w.D.Summary()
	eq(s.characters, 1000); eq(s.live.freshCharacters, 620, "live movement appears before every guild is heard")
	w.ns.rdb.guilds["Olympus Dusk"] = { total = 350, online = 10, t = w.clock }
	s = w.D.Summary()
	eq(s.snapshot, nil, "complete coverage releases the saved view")
	eq(s.characters, 1090)
end)

test("census continuity: incoming origins and witnesses are bounded and retain no authority or private fields", function()
	local w = GroupWorld()
	for i = 1, w.D.GROUP_MAX + 30 do
		w.D.ReceiveGroupCensus("CHANNEL", "First-Realm", Say(w, { { "Origin" .. i, "Alliance", 3000, 2500, 3, w.clock - i } }))
	end
	local g = w.D.Groups()
	eq(#g.rows, w.D.GROUP_MAX)
	eq(g.characters, 0)
	for i = 1, w.D.WITNESS_MAX + 4 do
		w.D.ReceiveGroupCensus("CHANNEL", "Traveller" .. i .. "-Realm", Say(w, { { "Launchpvp", "Alliance", math.floor(3000 * 1.4 ^ i) } }))
	end
	eq(w.D.Groups().characters, 0, "disagreeing travellers never establish a count")
	eq(next(w.ns.rdb.guilds), nil)
	eq(w.D.ReceiveGroupCensus("CHANNEL", "First-Realm", string.rep("x", w.D.GLOBAL_MAX_BYTES + 1)), false)
	for i = 1, w.D.MAX_GUILDS + 20 do
		w.D.ReceiveGlobalCensus("CHANNEL", "First-Realm", Snapshot(w, { { "Olympus Invented " .. i, 640 } }))
	end
	local count = 0
	for _ in pairs(w.ns.rdb.censusWitness) do count = count + 1 end
	eq(count, w.D.MAX_GUILDS, "unconfirmed local-origin guild names are bounded too")
	w.ns.Church.IsLedgerRelay = function() return true end
	for i = 1, w.D.MAX_GUILDS + 20 do
		w.D.ReceiveGlobalCensus("CHANNEL", "Council-Realm", Snapshot(w, { { "Olympus Invented " .. i, 640 } }))
	end
	count = 0
	for _ in pairs(w.ns.rdb.censusGlobal) do count = count + 1 end
	eq(count, w.D.MAX_GUILDS, "trusted cached rows have the same hard bound")
end)

test("census continuity: legacy guild details cannot turn two forwarding clients into independent originals", function()
	local w = GroupWorld()
	w.ns.group = "ForeverPvP"
	local wire = ("CX~2~S~%d~ForeverPvE~Alliance~Olympus Dawn,640,40,300,%d"):format(w.clock, w.clock - 600)
	assert(w.D.ReceiveGroupCensus("CHANNEL", "First-Realm", wire))
	assert(w.D.ReceiveGroupCensus("CHANNEL", "Second-Realm", wire))
	eq(#w.D.GroupGuilds("ForeverPvE"), 0, "missing original provenance is not replaced by the latest sender")
	eq(w.D.Summary().characters, 0); eq(w.D.Groups().characters, 0)
	eq(next(w.ns.rdb.guilds), nil); eq(next(w.ns.rdb.censusGlobal or {}), nil)
end)

test("census continuity: trusted guild detail preserves newest observations and bounds malformed origins", function()
	local w = GroupWorld()
	w.ns.Church.IsLedgerRelay = function(name) return name == "Council-Realm" end
	local function Capsule(group, observed, total)
		return ("CX~2~S~%d~%s~Alliance~Olympus Dawn,%d,40,300,%d"):format(w.clock, group, total or 640, observed or w.clock)
	end
	assert(w.D.ReceiveGroupCensus("CHANNEL", "Council-Realm", Capsule("Launchpvp", w.clock - 60)))
	eq(w.D.GroupGuilds("Launchpvp")[1].source, "relay")
	assert(w.D.ReceiveGroupCensus("CHANNEL", "Council-Realm", Capsule("Launchpvp", w.clock - 120, 600)))
	eq(w.D.GroupGuilds("Launchpvp")[1].characters, 640)
	eq(w.D.GroupGuilds("Launchpvp")[1].observed, w.clock - 60, "relay receipt does not renew observation")
	eq(w.D.ReceiveGroupCensus("CHANNEL", "Council-Realm", Capsule("CAMWOWUS1Realm1PvP+CAMWOWUS1Realm1PvE")), false)
	eq(w.D.ReceiveGroupCensus("CHANNEL", "Council-Realm", Capsule("ClassicBetaPvP")), false)
	eq(w.D.ReceiveGroupCensus("WHISPER", "Council-Realm", Capsule("Launchpvp")), false)
	for i = 1, w.D.GROUP_DETAIL_MAX + 3 do
		assert(w.D.ReceiveGroupCensus("CHANNEL", "Council-Realm", Capsule("Origin" .. i, w.clock - i)))
	end
	local count = 0
	for _ in pairs(w.ns.db.groupDetails) do count = count + 1 end
	eq(count, w.D.GROUP_DETAIL_MAX)
	local bad = Capsule("Launchpvp") .. ";Olympus Dawn,640,40,300," .. w.clock
	eq(w.D.ReceiveGroupCensus("CHANNEL", "Council-Realm", bad), false, "duplicate guild rows do not slip through")
end)

test("census continuity: both carried snapshot versions respect quiet presence at the transport boundary", function()
	local quiet = ns.QuietPresence
	ns.QuietPresence = function() return true end
	local ok, err = pcall(function()
		eq(ns.Comm.QuietHolds("CX~1~S~2000000000~Foreign|Alliance|640|600|1|2000000000"), true)
		eq(ns.Comm.QuietHolds("CX~2~S~2000000000~Foreign~Alliance~Olympus Dawn,640,40,300,2000000000"), true)
	end)
	ns.QuietPresence = quiet
	if not ok then error(err, 0) end
end)

test("census groups (1.4.0): another group's numbers: a moderator's alone, two people agreeing, or one person's listed grey and never counted; ours and the beta's never taken", function()
	local w = GroupWorld()
	w.D.ReceiveGroupCensus("CHANNEL", "First-Realm", Say(w, { { "Launchpvp", "Alliance", 3000, 2500 } }))
	local g = w.D.Groups()
	eq(g.characters, 0, "one person: not counted")
	eq(#g.rows, 1); eq(g.rows[1].counted, false); eq(g.rows[1].src, "heard")
	w.D.ReceiveGroupCensus("CHANNEL", "Second-Realm", Say(w, { { "Launchpvp", "Alliance", 3100, 2600, 3, w.clock - 3600 } }))
	g = w.D.Groups()
	eq(g.characters, 3000, "two people agree (an hour apart, within 10%): the newer is counted")
	eq(g.rows[1].src, "witnessed")
	-- A moderator's alone, newer.
	w.ns.Church.IsLedgerRelay = function(name) return name == "Council-Realm" end
	w.clock = w.clock + 60
	w.D.ReceiveGroupCensus("CHANNEL", "Council-Realm", Say(w, { { "Launchpvp", "Alliance", 3050, 2550 } }))
	eq(w.D.Groups().characters, 3050)
	-- Far apart in size: no agreement.
	local far = GroupWorld()
	far.D.ReceiveGroupCensus("CHANNEL", "First-Realm", Say(far, { { "Launchpvp", "Alliance", 3000 } }))
	far.D.ReceiveGroupCensus("CHANNEL", "Second-Realm", Say(far, { { "Launchpvp", "Alliance", 3500 } }))
	eq(far.D.Groups().characters, 0)
	-- Our own group as someone else says it: we count it live, never from a word.
	local ours = GroupWorld()
	ours.D.ReceiveGroupCensus("CHANNEL", "First-Realm", Say(ours, { { "Launchpve", "Alliance", 9000 } }))
	ours.D.ReceiveGroupCensus("CHANNEL", "Second-Realm", Say(ours, { { "Launchpve", "Alliance", 9000 } }))
	eq(next(ours.ns.db.groupCensus or {}), nil); eq(next(ours.ns.db.groupHeard or {}), nil)
	-- The beta's realms, on a launch realm: neither taken nor listed.
	local beta = GroupWorld()
	beta.D.ReceiveGroupCensus("CHANNEL", "First-Realm", Say(beta, { { "ClassicBetaPvP+ClassicBetaPvP2", "Alliance", 80000 } }))
	beta.D.ReceiveGroupCensus("CHANNEL", "Second-Realm", Say(beta, { { "ClassicBetaPvP+ClassicBetaPvP2", "Alliance", 80000 } }))
	eq(#beta.D.Groups().rows, 0)
	-- Malformed or out of bounds: refused.
	eq(beta.D.ReceiveGroupCensus("CHANNEL", "First-Realm", ("CX~1~S~%d~Bad|Elves|10|10|1|%d"):format(beta.clock, beta.clock)), true)
	eq(#beta.D.Groups().rows, 0, "an unknown faction is no row")
	eq(beta.D.ReceiveGroupCensus("CHANNEL", "First-Realm", ("CX~1~S~%d~Launchpvp|Alliance|10|11|1|%d"):format(beta.clock, beta.clock)), true)
	eq(#beta.D.Groups().rows, 0, "more people than characters is no row")
	eq(beta.D.ReceiveGroupCensus("WHISPER", "First-Realm", Say(beta, { { "Launchpvp", "Alliance", 10 } })), false, "the channel only")
end)

-- 1.5.4 (the dev, 2026-11-08: "só para diferenciar, para não cruzar os dados"): each side's numbers
-- apart. The account-wide store keeps both sides' rows (an account that plays both sees its Horde
-- rows on the Horde), but a side's page sums and lists its own alone, says its own alone (CX1, CX2)
-- and gives the Companion its own (tests/bridge-people.lua). Fails before: the Alliance page summed
-- the Horde row and listed it "(Horde)", the payload carried it (a trusted account that plays both
-- sides said its Horde look to the Alliance network), and both sides' details were said.
test("census groups (1.5.4): the Horde apart: a side lists, sums and says its own rows alone; the other side's stay kept for its own characters", function()
	local w = GroupWorld("Zed Own-CAMWOWUS1Realm8PvP")
	w.ns.group, w.ns.realm = "ForeverPvP", "CAMWOWUS1Realm8PvP"
	w.ns.Church = { IsLedgerRelay = function() return true end } -- (a Forever family's row travels from a trusted client alone)
	w.ns.QuietPresence = function() return false end
	local t = w.clock - 600
	w.ns.db.groupCensus = {
		["Alliance|ForeverPvE"] = { group = "ForeverPvE", faction = "Alliance", characters = 7000, people = 6500, guilds = 7, observed = t, src = "own" },
		["Horde|ForeverPvE"] = { group = "ForeverPvE", faction = "Horde", characters = 3000, people = 2800, guilds = 3, observed = t, src = "own" },
	}
	local g = w.D.Groups()
	eq(g.characters, 7000, "the Alliance sums its own row alone"); eq(g.people, 6500)
	eq(#g.rows, 1); eq(g.rows[1].faction, "Alliance"); eq(g.factions.Horde, nil); eq(g.factions.Alliance.characters, 7000)
	local said = assert(w.D.GroupCensusPayload(), "its own row is said")
	assert(said:find("~ForeverPvE,Alliance,7000,6500,7,", 1, true), said)
	assert(not said:find("Horde", 1, true), "the Horde row is not said on the Alliance: " .. said)
	-- The same account on a Horde character: the reverse; the Alliance row stays kept.
	w.ns.faction = "Horde"
	g = w.D.Groups()
	eq(g.characters, 3000, "the Horde sums its own row alone"); eq(g.people, 2800)
	eq(#g.rows, 1); eq(g.rows[1].faction, "Horde"); eq(g.factions.Alliance, nil)
	said = assert(w.D.GroupCensusPayload())
	assert(said:find("~ForeverPvE,Horde,3000,2800,3,", 1, true), said)
	assert(not said:find("Alliance", 1, true), "the Alliance row is not said on the Horde: " .. said)
	eq(w.ns.db.groupCensus["Alliance|ForeverPvE"].characters, 7000, "the other side's row stays kept")
	eq(w.ns.db.groupCensus["Horde|ForeverPvE"].characters, 3000)
	-- The details (CX2; groups off Forever, as a Forever family's details never travel): a side's own
	-- capsules alone, however many turns.
	w.ns.group, w.ns.realm = "Launchpve", "Launchpve"
	w.ns.db.groupDetails = {
		["Alliance|Launchpvp"] = { group = "Launchpvp", faction = "Alliance", observed = w.clock, source = "own",
			rows = { dawn = { name = "Olympus Dawn", total = 640, online = 20, avg10 = 300, observed = w.clock } } },
		["Horde|Launchpvp"] = { group = "Launchpvp", faction = "Horde", observed = w.clock, source = "own",
			rows = { dusk = { name = "Mudhutters Dusk", total = 400, online = 10, avg10 = 200, observed = w.clock } } },
	}
	local function Said(side)
		w.sent = {}
		for _ = 1, 3 do assert(w.D.SayGroupDetails(), side .. ": its own capsule is said") end
		local own, other = 0, 0
		for _, p in ipairs(w.sent) do
			if p:find("~Launchpvp~" .. side .. "~", 1, true) then own = own + 1 else other = other + 1 end
		end
		eq(other, 0, side .. ": the other side's capsule is never said (" .. table.concat(w.sent, " | ") .. ")")
		eq(own, 3)
	end
	Said("Horde")
	w.ns.faction = "Alliance"
	Said("Alliance")
end)

test("census groups (1.4.0): Data.BetaOnLaunch: what the account noted on the beta's realm group, or before 1.4.0 (no group), never applies on a launch group; everything applies on the beta's", function()
	local D, BETA = ns.Data, "ClassicBetaPvP+ClassicBetaPvP2"
	eq(D.BetaOnLaunch(BETA, "Launchpvp"), true, "the beta's, on a launch group")
	eq(D.BetaOnLaunch("ClassicBetaPvP2", "Launchpvp+Launchpve"), true, "one of its realms")
	eq(D.BetaOnLaunch(nil, "Launchpvp"), true, "noted before 1.4.0: the beta's")
	eq(D.BetaOnLaunch("", "Launchpvp"), true)
	eq(D.BetaOnLaunch("Launchpvp", "Launchpvp"), false, "a launch group's own")
	eq(D.BetaOnLaunch("Launchpve", "Launchpvp"), false, "another launch group's: not the beta's")
	eq(D.BetaOnLaunch(nil, BETA), false, "on the beta everything applies")
	eq(D.BetaOnLaunch("Launchpvp", "ClassicBetaPvP"), false)
	eq(D.BetaOnLaunch(BETA, nil), true, "our group not known yet: the beta's stays out")
end)

test("census groups (1.4.0): our own look is kept at logout only after the census was rebuilt, never a half-heard count", function()
	local w = GroupWorld()
	local onLogout
	w.ns.RegisterEvent = function(event, fn) if event == "PLAYER_LOGOUT" then onLogout = fn end end
	w.Fire("LOGIN")
	assert(onLogout, "a logout handler")
	w.ns.rdb.guilds["Olympus Dawn"] = { total = 640, online = 40, avgLevel = 30, t = w.clock, st = w.clock }
	w.ns.SafeCall = function(_, fn, ...) return fn(...) end
	w.ns.Comm = { loginAt = w.clock - 60 }
	onLogout()
	eq(w.ns.db.groupCensus, nil, "a minute after login: not kept")
	w.ns.Comm.loginAt = w.clock - w.D.CROWN_AFTER - 1
	onLogout()
	eq(w.ns.db.groupCensus["Alliance|Launchpve"].characters, 640)
end)

-- Two values alike, tables compared value by value whatever their identity; the first difference.
local function Alike(a, b, path)
	if type(a) ~= "table" or type(b) ~= "table" then
		if a ~= b then return ("%s: %s, not %s"):format(path, tostring(a), tostring(b)) end
		return nil
	end
	for k, v in pairs(a) do
		local diff = Alike(v, b[k], path .. "." .. tostring(k))
		if diff then return diff end
	end
	for k in pairs(b) do
		if a[k] == nil then return path .. "." .. tostring(k) .. ": missing" end
	end
	return nil
end

-- A report's text as its sender's client sends it (Comm.Broadcast), with its own server time.
local function ReportText(fields, st)
	local r = {}
	for k, v in pairs(fields) do r[k] = v end
	r.st = st
	return Codec.EncodeReport(r)
end
local function Echo(changes)
	local r = { guild = "Olympus Echo", total = 40, online = 6, leader = "Echoboss", leaderOnline = true, users = 3,
		zones = { m1453 = 2, m1429 = 1 }, classes = { WA = 2, PR = 1 }, levels = { 0, 0, 0, 0, 0, 1, 2 },
		ranks = { { name = "Boss", count = 1 }, { name = "Captain", count = 2 }, { name = "Member", count = 37 } },
		officers = { { name = "Echocapt", online = true, days = 0, class = "WA", level = 60, zone = "m1453" } },
		leaderDays = 0, inactive7 = 3, inactive30 = 9, avgLevel = 41.5,
		top = { { name = "Echoboss", level = 60, class = "WA" }, { name = "Echocapt", level = 60, class = "WA" } },
		leaderClass = "WA", leaderLevel = 60, leaderZone = "m1453", from = "Realm", home = "Realm",
		versions = { ["1.2.2"] = 3 }, cap = "a", pres = { "k3a" } }
	for k, v in pairs(changes or {}) do r[k] = v end
	return r
end

test("census (1.2.3): a sender's report again but for its time is not decoded, and the census is what decoding every report made it: rows, votes, marks, DATA_CHANGED, Revision and the log (a fixture of 22 reports)", function()
	-- The same reports to two clients: one through Data.DecodeReport (as Comm.lua hears them now),
	-- one decoding each (Codec.DecodeReport, as 1.2.2's Comm.lua did). After every report both
	-- censuses are alike in every field of every row.
	local P, P2 = Echo(), Echo({ online = 5, zones = { m1453 = 2 }, levels = { 0, 0, 0, 0, 0, 1, 1 } })
	local Q = Echo({ leader = "Usurper", top = { { name = "Usurper", level = 60, class = "WA" } } })
	local X = Echo({ guild = "Olympus Tide", leader = "Tideboss", officers = {}, top = {} })
	local Y = Echo({ guild = "Olympus Tide", leader = "Tidefake", officers = {}, top = {} })
	local OTHER = Echo({ guild = "OLYMPUS ECHO" }) -- (the stored key's other spelling: one more vote)
	-- { seconds after the first report, sender, report, its server time, what to look for }
	local steps = {
		{ 0, "Tidea-Realm", X }, { 1, "Tideb-Realm", X }, -- (votes that will be 30 minutes old later)
		{ 10, "Echoa-Realm", P }, -- a new row
		{ 190, "Echoa-Realm", P, again = true }, -- the same but for its time: not decoded
		{ 190, "Echoa-Realm", P, again = true }, -- within NOTIFY_GAP: its row told before it is taken again
		{ 370, "Echob-Realm", P }, -- another sender of the guild: his row
		{ 550, "Echoa-Realm", P }, -- decoded again: the row is the other sender's
		{ 730, "Echoa-Realm", P2 }, -- changed: decoded
		{ 910, "Echoa-Realm", P2, again = true },
		{ 911, "Echoc-Realm", Q }, -- outvoted: the row stays, marked
		{ 1000, "Tidec-Realm", X }, { 1001, "Tided-Realm", X }, -- the row Tided's
		{ 1002, "Tidee-Realm", Y }, { 1003, "Tidef-Realm", Y }, { 1004, "Tideg-Realm", Y }, -- outvoted, kept as votes
		{ 1090, "Echoa-Realm", P2, again = true }, -- the outvoted mark goes as a new report's would
		{ 1091, "Echoe-Realm", OTHER }, -- another spelling: a vote on the row, taken, its text not kept
		{ 1270, "Echoe-Realm", OTHER },
		{ 1802, "Tided-Realm", X, again = true }, -- the first two votes gone (VOUCH_TTL): outvoted, its row kept
		{ 1803, "Tided-Realm", X, again = true },
		{ 1950, "Tided-Realm", X, again = true }, -- its row older than FRESH: taken
		{ 1990, "Echoa-Realm", P2 }, -- the row is the other spelling's sender's
	}
	local now, old = CensusWorld(), CensusWorld()
	local start, last = now.clock, now.clock
	for i, step in ipairs(steps) do
		local sender = step[2]
		local decodes = now.decodes
		local revNow, revOld = now.D.Revision(), old.D.Revision()
		now.clock, old.clock = start + step[1], start + step[1]
		if now.clock > last then now.Run(); old.Run() end -- (a second gone: the waiting timer ran)
		last = now.clock
		local text = ReportText(step[3], 1000 + step[1])
		local rNow = now.D.DecodeReport(text, sender)
		local takenNow = rNow ~= nil and now.D.Receive(rNow, sender)
		local takenOld = old.D.Receive(assert(Codec.DecodeReport(text)), sender)
		local label = "report " .. i .. " (" .. sender .. ")"
		eq(now.decodes - decodes, step.again and 0 or 1, label .. ": decoded")
		eq(takenNow, takenOld, label .. ": taken")
		eq(now.D.Revision() - revNow, old.D.Revision() - revOld, label .. ": revisions")
		eq(now.fires, old.fires, label .. ": DATA_CHANGED"); eq(#now.timers, #old.timers, label .. ": timers")
		eq(Alike(now.ns.rdb.guilds, old.ns.rdb.guilds, "guilds"), nil, label)
		eq(table.concat(now.logs, "\n"), table.concat(old.logs, "\n"), label .. ": log")
		for _, guild in ipairs({ "Olympus Echo", "Olympus Tide" }) do
			eq(Alike(now.D.Dispute(now.D.Guild(guild), now.clock), old.D.Dispute(old.D.Guild(guild), old.clock), "dispute"), nil, label .. " " .. guild)
		end
		eq(now.D.ClaimedGuild(sender), old.D.ClaimedGuild(sender), label .. ": claim")
	end
	-- What the fixture went through, so neither census was alike by having nothing in it.
	local echo, tide = now.ns.rdb.guilds["Olympus Echo"], now.ns.rdb.guilds["Olympus Tide"]
	eq(echo.reporterFull, "Echoa-Realm"); eq(echo.online, 5); eq(echo.st, 1000 + 1990)
	eq(tide.reporterFull, "Tided-Realm"); eq(tide.t, start + 1950); eq(tide.st, 1000 + 1950)
	assert(tide.vouch["Tidee-Realm"] and not tide.vouch["Tidea-Realm"], "the outvoted senders' votes kept, the old ones gone")
	assert(old.logs[1] and table.concat(old.logs, "\n"):find("is not what the other senders say", 1, true), "an outvoted report logged")
	eq(now.D.Repeats(), 2, "the two rows' senders' reports kept, the replaced ones' gone")
	-- Its row gone another way (a reset): decoded, and the kept reports go with the next tick.
	wipe(now.ns.rdb.guilds)
	now.D.Housekeeping()
	eq(now.D.Repeats(), 0)
	local decodes = now.decodes
	now.clock = now.clock + 180
	assert(now.D.Receive(assert(now.D.DecodeReport(ReportText(P2, 1), "Echoa-Realm")), "Echoa-Realm"))
	eq(now.decodes - decodes, 1, "a reset store: decoded")
end)

test("census (1.2.3): Codec.ReportTime finds field 25 where Codec.DecodeReport reads it, nil without one", function()
	for _, st in ipairs({ 0, 35, 1799999999, 36 ^ 8 - 1, false }) do
		local text = ReportText(Echo(), st or nil)
		local at, stop, t = Codec.ReportTime(text)
		eq(t, Codec.DecodeReport(text).st, tostring(st))
		eq(text:sub(at + 1, stop - 1), st and Codec.Base36(st) or "")
		eq(select(2, text:sub(1, at):gsub("~", "")), 24, "the 24 fields before it")
	end
	-- The last field (fields 26 and 27 left out).
	local short = table.concat(Codec.Split(ReportText(Echo(), 99), "~"), "~", 1, 25)
	local at, stop, t = Codec.ReportTime(short)
	eq(stop, #short + 1); eq(t, 99); eq(Codec.DecodeReport(short).st, 99); eq(at, #short - 2)
	eq(Codec.ReportTime("R1~Olympus~10~2~Boss~1~2~m1453=2~WA=2~0,2,0,0,0,0,0"), nil, "older versions: no field 25")
	eq(Codec.ReportTime(("~"):rep(30) .. ("x"):rep(Codec.CHUNK * Codec.MAX_CHUNKS)), nil, "a text DecodeReport refuses by its length")
	eq(Codec.ReportTime(nil), nil)
end)

test("census (1.2.3): through Comm's own handler a reporter's report again but for its time is its row, not decoded; changed, after another sender's, or after a reset, decoded", function()
	local FreshComm = assert(extra and extra.FreshComm, "tests/run.lua hands FreshComm to this file")
	local savedGuilds, savedDecode, savedNow = ns.rdb.guilds, Codec.DecodeReport, ns.Now
	local ok, err = pcall(function()
		local cns, _, Report = FreshComm()
		local decodes, clock = 0, 2000000000
		Codec.DecodeReport = function(s) decodes = decodes + 1 return savedDecode(s) end
		ns.Now = function() return clock end
		ns.rdb.guilds = {}
		local P, P2 = Echo({ guild = "Olympus Combo" }), Echo({ guild = "Olympus Combo", online = 5 })
		local function Send(sender, r, st)
			local copy = {}
			for k, v in pairs(r) do copy[k] = v end
			copy.st = st
			Report(sender, copy)
		end
		Send("Combo One-Realm", P, 1)
		eq(decodes, 1)
		local row = ns.rdb.guilds["Olympus Combo"]
		eq(row.reporterFull, "Combo One-Realm"); eq(row.st, 1)
		clock = clock + 180
		Send("Combo One-Realm", P, 2)
		eq(decodes, 1, "the same but for its time: not decoded")
		eq(ns.rdb.guilds["Olympus Combo"], row, "its row")
		eq(row.t, clock); eq(row.st, 2); eq(row.vouch["Combo One-Realm"].t, clock, "its vote's time new")
		clock = clock + 180
		Send("Combo Two-Realm", P, 3)
		eq(decodes, 2, "another sender: decoded"); eq(ns.rdb.guilds["Olympus Combo"].reporterFull, "Combo Two-Realm")
		clock = clock + 180
		Send("Combo One-Realm", P, 4)
		eq(decodes, 3, "his report after another sender's: decoded")
		clock = clock + 180
		Send("Combo One-Realm", P, 5)
		eq(decodes, 3)
		Send("Combo One-Realm", P2, 6)
		eq(decodes, 4, "changed: decoded"); eq(ns.rdb.guilds["Olympus Combo"].online, 5)
		ns.rdb.guilds = {} -- (/oly reset)
		Send("Combo One-Realm", P2, 7)
		eq(decodes, 5, "a reset store: decoded"); eq(ns.rdb.guilds["Olympus Combo"].st, 7)
		eq(cns.Comm.Stats().reports, 7, "every report counted")
		local lines = 0
		for _, line in ipairs(ns.db.log) do
			if line:find("report Olympus Combo from Combo", 1, true) then lines = lines + 1 end
		end
		eq(lines, 7, "every report taken logged as before")
	end)
	Codec.DecodeReport, ns.rdb.guilds, ns.Now = savedDecode, savedGuilds, savedNow
	if not ok then error(err, 0) end
end)

test("census (1.2.3): the reports kept are one per row: another sender's report of the guild, Data.Trim or a reset lets them go", function()
	local w = CensusWorld()
	local D = w.D
	local function Hear(sender, r, st)
		w.clock = w.clock + 1
		return D.Receive(assert(D.DecodeReport(ReportText(r, st), sender)), sender)
	end
	D.MAX_GUILDS = 3
	for k = 1, 3 do assert(Hear("Keeper" .. k .. "-Realm", Echo({ guild = "Olympus Keep " .. k }), k)) end
	eq(D.Repeats(), 3)
	assert(Hear("Keeper9-Realm", Echo({ guild = "Olympus Keep 1" }), 9))
	eq(D.Repeats(), 3, "the guild's other sender: his report kept, the first one's gone")
	assert(Hear("Keeper4-Realm", Echo({ guild = "Olympus Keep 4" }), 4))
	eq(w.ns.rdb.guilds["Olympus Keep 2"], nil, "the report heard longest ago went (Data.Trim)")
	eq(D.Repeats(), 3, "and its sender's with it")
	local decodes = w.decodes
	assert(Hear("Keeper2-Realm", Echo({ guild = "Olympus Keep 2" }), 5))
	eq(w.decodes - decodes, 1, "his row gone: decoded")
	-- A guild quiet for FRESH: its sender's report goes at the next tick; the others stay.
	w.clock = w.clock + D.FRESH - 1
	assert(Hear("Keeper4-Realm", Echo({ guild = "Olympus Keep 4" }), 6))
	w.clock = w.clock + 2
	D.Housekeeping()
	eq(D.Repeats(), 1, "the one heard within FRESH")
	decodes = w.decodes
	assert(Hear("Keeper4-Realm", Echo({ guild = "Olympus Keep 4" }), 7))
	eq(w.decodes - decodes, 0)
	w.ns.rdb = { guilds = {}, seen = {} } -- (another realm's store)
	D.Housekeeping()
	eq(D.Repeats(), 0)
end)

test("census (1.2.3): votes past VOUCH_TTL leave the rows at INIT and at logout, the others kept; what counts the votes reads as before", function()
	local w = CensusWorld()
	local D, now = w.D, w.clock
	local function Rows()
		local ranks = { ["Oldboss-Realm"] = 0, ["Oldcapt-Realm"] = 1 }
		local function Vote(age) return { t = now - age, sig = "Oldboss-Realm=0,Oldcapt-Realm=1", ranks = ranks, n = 30 } end
		return {
			["Olympus Old"] = { guild = "Olympus Old", t = now - 100, leader = "Oldboss", officers = { { name = "Oldcapt" } },
				realm = "Realm", heardOn = "Realm", total = 30, reporterFull = "Fresh One-Realm",
				vouch = { ["Fresh One-Realm"] = Vote(60), ["Fresh Two-Realm"] = Vote(D.VOUCH_TTL), ["Stale-Realm"] = Vote(D.VOUCH_TTL + 1),
					["Broken-Realm"] = "x" } },
			["Olympus Gone"] = { guild = "Olympus Gone", t = now - 7200, leader = "Goneboss", realm = "Realm", heardOn = "Realm",
				total = 10, vouch = { ["Long Ago-Realm"] = Vote(7200) } },
		}
	end
	local function Check(how)
		local g = w.ns.rdb.guilds["Olympus Old"]
		assert(g.vouch["Fresh One-Realm"] and g.vouch["Fresh Two-Realm"], how .. ": the votes still counted stay")
		eq(g.vouch["Stale-Realm"], nil, how); eq(g.vouch["Broken-Realm"], nil, how)
		eq(w.ns.rdb.guilds["Olympus Gone"].vouch, nil, how .. ": a row whose votes are all past it keeps none")
	end
	w.ns.rdb.guilds = Rows()
	local dispute, rank = D.Dispute(w.ns.rdb.guilds["Olympus Old"], now), { D.KnownRank("Oldcapt-Realm", "Olympus Old") }
	eq(rank[1], 1, "(the fixture's officer, vouched by the two fresh votes)")
	w.Fire("INIT")
	Check("INIT")
	eq(Alike(D.Dispute(w.ns.rdb.guilds["Olympus Old"], now), dispute, "dispute"), nil)
	eq(Alike({ D.KnownRank("Oldcapt-Realm", "Olympus Old") }, rank, "rank"), nil)
	w.ns.rdb.guilds = Rows()
	eq(w.events.PLAYER_LOGOUT, nil, "registered at login")
	w.Fire("LOGIN")
	eq(#w.events.PLAYER_LOGOUT, 1)
	w.events.PLAYER_LOGOUT[1]()
	Check("logout")
end)

test("census (1.2.3): a claim CLAIM_TTL old keeps only its guild: Data.ClaimedGuild still answers it for the session however many senders were heard, and another guild may be claimed", function()
	local w = CensusWorld()
	local D = w.D
	local t0 = w.clock
	eq(D.ClaimGuild("Mover-Realm", "Olympus Alpha"), true)
	w.clock = t0 + D.CLAIM_TTL - 1
	D.Housekeeping()
	eq(D.ClaimGuild("Mover-Realm", "Olympus Beta"), false, "still bound")
	w.clock = t0 + D.CLAIM_TTL
	D.Housekeeping()
	eq(D.ClaimedGuild("Mover-Realm"), "Olympus Alpha", "his guild still answered (the game's chat marks)")
	eq(D.ClaimGuild("Mover-Realm", "Olympus Beta"), true, "after CLAIM_TTL quiet")
	eq(D.ClaimedGuild("Mover-Realm"), "Olympus Beta")
	eq(D.ClaimGuild("Mover-Realm", "Olympus Alpha"), false, "and now bound to the new one")
	-- The King's client on a stream hears thousands of senders (chat lines, census reports, board
	-- posts, listings). Every old claim still answers, as in 1.2.2, however many: the council copy of
	-- a report from one quiet since (Watch.CouncilReporter) and the bronze mark of a guild master
	-- quiet since (Borders.ChatGuilds) need it. One that binds still binds.
	local heard = 5000
	for k = 1, heard do eq(D.ClaimGuild("Quiet" .. k .. "-Realm", "Olympus Quiet"), true) end
	w.clock = w.clock + D.CLAIM_TTL
	eq(D.ClaimGuild("Loud-Realm", "Olympus Loud"), true)
	for _ = 1, 3 do -- (a few minute ticks)
		D.Housekeeping()
		w.clock = w.clock + 60
	end
	local lost = 0
	for k = 1, heard do
		if D.ClaimedGuild("Quiet" .. k .. "-Realm") ~= "Olympus Quiet" then lost = lost + 1 end
	end
	eq(lost, 0, "old claims still answered past thousands of senders")
	eq(D.ClaimedGuild("Mover-Realm"), "Olympus Beta")
	eq(D.ClaimedGuild("Loud-Realm"), "Olympus Loud")
	eq(D.ClaimGuild("Loud-Realm", "Olympus Other"), false, "still bound")
	eq(D.ClaimGuild("Quiet1-Realm", "Olympus Other"), true, "an old claim binds nobody")
	eq(D.ClaimedGuild("Quiet1-Realm"), "Olympus Other")
	eq(D.ClaimedGuild("Quiet2-Realm"), "Olympus Quiet")
end)

-- The source Alts module, with only identity/state/event/transport boundaries supplied by
-- this scene. Claims, revisions, grouping and duplicate counts all run through Alts.lua.
local function WithAlts(fn)
	local savedGuild, savedDialog = GetGuildInfo, StaticPopupDialogs.OLYMPUS_ALT_CONFIRM
	local w = { now = 1800000000, guild = "Olympus Old" }
	GetGuildInfo = function() return w.guild end
	local function Client(me, own)
		local c = setmetatable({ me = me, realm = "Realm", db = {}, rdb = {}, sent = {}, timers = {}, events = {}, callbacks = {}, changes = 0 }, { __index = ns })
		c.Now = function() return w.now end
		c.Data = { ServerTime = c.Now }
		c.IsMember = function() return type(w.guild) == "string" and w.guild:find("Olympus", 1, true) ~= nil end
		c.On = function(event, cb) c.callbacks[event] = cb end
		c.RegisterEvent = function(event, cb) c.events[event] = cb end
		c.After = function(delay, label, cb) c.timers[#c.timers + 1] = { delay = delay, label = label, cb = cb } end
		c.Every = function() end
		c.Fire = function(event) if event == "DATA_CHANGED" then c.changes = c.changes + 1 end end
		c.Log = function() end
		c.Moderation = { Character = function() end }
		c.Comm = {
			Handle = function() end,
			Send = function(dist, msg) c.sent[#c.sent + 1] = { dist = dist, msg = msg } end,
		}
		if own then
			c.db.alts = {
				at = w.now - 10,
				links = { ["alt guy-realm"] = { name = "Alt Guy-Realm", main = "Main Guy-Realm", at = w.now - 10 } },
				guilds = { ["alt guy-realm"] = "Olympus Old", ["main guy-realm"] = "Olympus Main" },
			}
		end
		assert(loadfile(ROOT .. "Olympus/Alts.lua"))("Olympus", c)
		function c.Run(delay)
			local pending = c.timers
			c.timers = {}
			for _, timer in ipairs(pending) do
				if timer.delay <= delay then timer.cb() else c.timers[#c.timers + 1] = timer end
			end
		end
		return c
	end
	local ok, err = pcall(function() fn(w, Client) end)
	GetGuildInfo, StaticPopupDialogs.OLYMPUS_ALT_CONFIRM = savedGuild, savedDialog
	if not ok then error(err, 0) end
end

local function Revision(msg) return assert(tonumber(msg:match("^AL~(%d+)~"))) end
local function GuildOf(alts, name)
	for _, member in ipairs(assert(alts.Group(name)).members) do
		if member.name == name then return member.guild end
	end
	error("missing group member " .. name)
end

-- 1.4.0 (the author, 11-03: "os números do beta não devem ser utilizados"): this account's links
-- are account-wide, so the beta's came along to the launch realms; matched by guild name alone, a
-- beta pair in guilds named like launch guilds took people off the launch count.
test("alts (1.4.0): this account's links of another realm group (the beta's, on a launch realm) take nobody off here", function()
	WithAlts(function(w, Client)
		local c = Client("Main Guy-Realm", true)
		local counted = { ["olympus old"] = true, ["olympus main"] = true }
		c.group = "Realm"
		eq(c.Alts.Duplicates(counted), 1, "on its own group the pair is one person")
		assert(c.Alts.Group("Alt Guy-Realm"), "and a group")
		-- (A character of the launch realm: its realm and its group are both the launch realm's. A
		-- character of our own realm is always ours, so the realm moves with the group.)
		c.realm, c.group = "Launchrealm", "Launchrealm"
		eq(c.Alts.Duplicates(counted), 0, "on another realm group, nobody taken off")
		eq(c.Alts.Group("Alt Guy-Realm"), nil, "and no group shown")
		c.group = nil
		eq(c.Alts.Duplicates(counted), 1, "no group known yet: as before")
	end)
end)

test("alts: a live guild change revises and sends the claim, refreshing both clients' counts", function()
	WithAlts(function(w, Client)
		local c, peer = Client("Alt Guy-Realm", true), Client("Watcher-Realm")
		peer.Alts.Handle("CHANNEL", "Main Guy-Realm", ("AL~%d~M~Olympus Main~Alt Guy"):format(w.now - 10))
		assert(c.Alts.Send(false))
		local old = c.sent[1].msg
		peer.Alts.Handle("CHANNEL", c.me, old)
		eq(GuildOf(c.Alts, c.me), "Olympus Old")
		eq(GuildOf(peer.Alts, c.me), "Olympus Old")
		eq(peer.Alts.Duplicates({ ["olympus main"] = true, ["olympus old"] = true }), 1)
		w.guild = "Olympus New"
		assert(c.events.PLAYER_GUILD_UPDATE, "membership changes are observed")("player")
		c.Run(2)
		eq(#c.sent, 2, "a guild change does not wait thirty minutes")
		local changed = c.sent[2].msg
		assert(Revision(changed) > Revision(old), "a changed guild has a newer revision")
		eq(GuildOf(c.Alts, c.me), "Olympus New", "own cached group invalidated")
		peer.Alts.Handle("CHANNEL", c.me, changed)
		eq(GuildOf(peer.Alts, c.me), "Olympus New")
		eq(peer.Alts.Duplicates({ ["olympus main"] = true, ["olympus old"] = true }), 0)
		eq(peer.Alts.Duplicates({ ["olympus main"] = true, ["olympus new"] = true }), 1)
		peer.Alts.Handle("CHANNEL", c.me, old)
		eq(GuildOf(peer.Alts, c.me), "Olympus New", "a delayed old claim cannot undo the move")
		local revision = c.db.alts.at
		c.events.PLAYER_GUILD_UPDATE("player"); c.Run(2)
		eq(c.db.alts.at, revision); eq(#c.sent, 2, "an unchanged guild produces no extra send")
	end)
end)

test("alts: login refresh revises a saved guild before the first claim", function()
	WithAlts(function(w, Client)
		local c = Client("Alt Guy-Realm", true)
		local old = c.db.alts.at
		w.guild = "Olympus New"
		c.callbacks.LOGIN()
		c.Run(10)
		assert(c.db.alts.at > old, "login membership change increments the wire revision")
		eq(GuildOf(c.Alts, c.me), "Olympus New")
		eq(#c.sent, 0, "login still waits for its channel before sending")
		c.Run(c.Alts.LOGIN_AFTER)
		eq(#c.sent, 1)
		eq(Revision(c.sent[1].msg), c.db.alts.at)
		assert(c.sent[1].msg:find("~Olympus New~", 1, true))
	end)
end)

test("alts: leaving updates local membership without sending outside Olympus; rejoining advances again", function()
	WithAlts(function(w, Client)
		local c = Client("Alt Guy-Realm", true)
		assert(c.Alts.Send(true))
		local old = c.db.alts.at
		w.guild = nil
		assert(c.events.PLAYER_GUILD_UPDATE)("player"); c.Run(2)
		eq(GuildOf(c.Alts, c.me), nil)
		assert(c.db.alts.at > old)
		eq(#c.sent, 1, "no network claim outside Olympus")
		local left = c.db.alts.at
		w.guild = "Olympus New"
		c.events.PLAYER_GUILD_UPDATE("target"); c.Run(2)
		eq(c.db.alts.at, left, "another unit's event leaves this character alone")
		c.events.PLAYER_GUILD_UPDATE("player"); c.Run(2)
		assert(c.db.alts.at > left, "even multiple changes in one second are ordered")
		eq(#c.sent, 2)
	end)
end)

test("alts: the send path records a newly observed guild even without a delivered event", function()
	WithAlts(function(w, Client)
		local c = Client("Alt Guy-Realm", true)
		assert(c.Alts.Send(false))
		local old = Revision(c.sent[1].msg)
		w.guild = "Olympus New"
		assert(c.Alts.Send(false), "a new guild overrides the ordinary repeat interval")
		assert(Revision(c.sent[2].msg) > old)
		eq(c.db.alts.guilds["alt guy-realm"], "Olympus New")
		eq(c.Alts.Send(false), false, "repeats remain paced")
	end)
end)
