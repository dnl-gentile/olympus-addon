-- Production Data -> Comm chunk queue -> Relay envelopes -> native send API.
local ns, test, eq, extra = ...

test("relay admission: unwrapping a relay's own word pays once, while native packets and different origins keep their limits", function()
	local saved = { member = ns.IsMember, chat = C_ChatInfo, time = GetTime }
	local ok, err = pcall(function()
		ns.IsMember = function() return true end
		GetTime = function() return 0 end
		local O, deliver, _, heard = extra.RelayWorld("Late-Realm", "Olympus II")
		O.db = { blocked = {} }
		local caught
		O.CaptureError = function(_, err) caught = err end
		local relay, other = "Max Ran-Realm", "Hildryn Payne-Realm"
		for i = 1, 61 do deliver("WHISPER", relay, "RM~P~" .. relay .. "~X1~own " .. i) end
		eq(#heard, 60, "the 60 native envelopes each pay once; the 61st is refused")
		O.Comm.ResetAdmission()
		for i = 1, 60 do deliver("WHISPER", relay, "RM~P~Origin-Realm~X1~forwarded " .. i) end
		eq(#heard, 120)
		for i = 1, 60 do deliver("WHISPER", other, "RM~P~Origin-Realm~X1~another route " .. i) end
		eq(#heard, 120, "another relay cannot bypass the forwarded origin's exhausted budget")
		O.Comm.ResetAdmission()
		O.Comm.Handle("X1", function() error("handler failure") end)
		deliver("WHISPER", relay, "RM~P~" .. relay .. "~X1~error")
		assert(caught and caught:find("handler failure", 1, true))
		for _ = 1, 59 do assert(O.Comm.Admit(relay, 0)) end
		local calls = 0
		O.Comm.Handle("X1", function() calls = calls + 1 end)
		O.Comm.Inject("CHANNEL", relay, "X1~outside the admitted call", false)
		eq(calls, 0, "a handler error cannot leave an admission exemption behind")
	end)
	ns.IsMember, C_ChatInfo, GetTime = saved.member, saved.chat, saved.time
	if not ok then error(err, 0) end
end)

test("census scope relay: a queue-sized current-group snapshot crosses relays and reaches late reporters whole", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo,
		inGuild = IsInGuild, chat = C_ChatInfo, time = GetTime, serverTime = GetServerTime,
		number = GetNumGuildMembers, row = GetGuildRosterInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		local started = 1794160000
		local guild, clock = "OLYMPUS PLATINUM", started
		GetGuildInfo = function() return guild, "Member", 3 end
		GetTime = function() return clock end
		GetServerTime = function() return math.floor(clock) end
		GetNumGuildMembers = function() return 108, 6 end
		local function Census(N)
			N.clock = clock
			N.group, N.faction, N.db = "ForeverPvE", "Alliance", { blocked = {} }
			N.rdb.guilds, N.rdb.seen = {}, {}
			N.Church = { IsLedgerRelay = N.Relay.IsRelay }
			N.QuietPresence = function() return false end
			assert(loadfile(extra.addon .. "Data.lua"))("Olympus", N)
			N.Comm.Handle("CG", N.Data.ReceiveGlobalCensus)
		end
		local R, rdeliver, sent = extra.RelayWorld("Max Ran-CAMWOWUS2Realm1PvE", "OLYMPUS PLATINUM")
		Census(R)
		local api = C_ChatInfo
		local total, online = 0, 0
		local names = { "Olympus Dawn", "KNIGHTS OF OLYMPUS", "olympus dusk" }
		for i = 1, 161 do
			guild = names[i] or (i == 161 and "Other Adventurers" or ("Olympus Guild Number %03d"):format(i))
			local O, odeliver, osent, _, opump = extra.RelayWorld("Reporter" .. i .. "-Realm", guild)
			Census(O)
			O.realm = "CAMWOWUS2Realm1PvE"
			GetGuildRosterInfo = function(row)
				return row == 1 and O.me or "Member" .. row .. "-Realm", "Member", row == 1 and 0 or 3,
					30, "Warrior", "Stormwind City", "", "", row <= 6, 0, "WARRIOR"
			end
			assert(loadfile(extra.addon .. "Roster.lua"))("Olympus", O)
			local report = assert(O.Roster.Scan())
			eq(O.Roster.complete, true); eq(report.total, 108); eq(report.online, 6)
			O.Data.SetLocal(report)
			odeliver("WHISPER", R.me, "RY~")
			O.Comm.Broadcast(report); opump(100)
			guild = "OLYMPUS PLATINUM"
			for _, p in ipairs(osent) do
				if p.target == "Max Ran" then rdeliver("WHISPER", O.me, p.msg) end
			end
			if i <= 160 then total, online = total + 108, online + 6 end
			-- A second reporter and a repeated relay copy still describe the same roster.
			if i == 1 then
				for _, sender in ipairs({ "Second-Realm", O.me }) do
					for _, p in ipairs(osent) do if p.target == "Max Ran" then rdeliver("WHISPER", sender, p.msg) end end
				end
			end
			C_ChatInfo = api
			for _ = 1, 100 do R.Comm.Pump() end -- finish presentation replies before the snapshot
		end
		eq(R.Data.Summary().characters, total); eq(#R.Data.Summary().guilds, 160)
		eq(R.rdb.guilds["Other Adventurers"], nil, "a non-federation roster is excluded")
		C_ChatInfo = api
		rdeliver("WHISPER", "Hildryn Payne-CAMWOWUS2Realm7PvE", "RY~")
		rdeliver("WHISPER", "Hildryn Payne-CAMWOWUS2Realm7PvE", "RJ~1~0~0") -- (1.5.5: a mesh peer, tests/relay-mesh.lua)
		eq(R.Relay.Pick(), "Max Ran", "the snapshot's origin is its own relay")
		local payload = R.Data.GlobalCensusPayload()
		eq(#R.Codec.Chunk(payload, "17"), 34, "exercise the live report's 34-part size")
		assert(2 * #R.Codec.Chunk(payload, "17") > R.Comm.MAX_QUEUE,
			"the snapshot's separately wrapped relay pieces exceed the send queue")
		local timers = {}
		R.After = function(delay, label, fn)
			if label == "relay drip" then timers[#timers + 1] = { at = clock + delay, fn = fn } end
		end
		for i = 1, R.Comm.MAX_QUEUE - 2 do
			assert(R.Comm.Whisper("Busy-Realm", "X1~control " .. i, nil, true))
		end
		assert(R.Data.SendGlobalCensus())
		for _ = 1, 100 do
			clock = clock + 1.2; R.clock = clock
			local due = timers; timers = {}
			for _, timer in ipairs(due) do
				if timer.at <= clock then timer.fn() else timers[#timers + 1] = timer end
			end
			R.Comm.Pump()
			assert(R.Comm.QueueSize() <= R.Comm.MAX_QUEUE, "the existing send bound stays in force")
		end
		local S, sdeliver, forwarded = extra.RelayWorld("Hildryn Payne-CAMWOWUS2Realm7PvE", "OLYMPUS PLATINUM")
		Census(S)
		local admit, refused = S.Comm.Admit, 0
		S.Comm.Admit = function(...)
			local yes = admit(...)
			if not yes then refused = refused + 1 end
			return yes
		end
		for i = 1, 3 do sdeliver("WHISPER", "Late" .. i .. "-Realm", "RL~P~RR~Olympus Late " .. i) end
		-- Replay native sends at the sender's pace, through Comm and both relay envelopes.
		clock = started
		for _, p in ipairs(sent) do
			clock = clock + 0.3; S.clock = clock
			if p.target == "Hildryn Payne" then sdeliver("WHISPER", R.me, p.msg) end
		end
		eq(refused, 0, "one bounded snapshot must fit receive admission at the relay's send pace")
		eq(S.Data.Summary().characters, total, "the second relay receives every guild, not a partial snapshot")
		for _ = 1, 100 do clock = clock + 1.2; S.clock = clock; S.Comm.Pump() end
		for i = 1, 3 do
			local L, ldeliver = extra.RelayWorld("Late" .. i .. "-Realm", "OLYMPUS PLATINUM")
			Census(L)
			L.Data.SetLocal({ guild = "OLYMPUS PLATINUM", total = 108, online = 6, zones = {} })
			eq(L.Data.Summary().characters, 108, "the late client initially sees only its own roster")
			for _, p in ipairs(forwarded) do
				clock = clock + 0.3; L.clock = clock
				if p.target == "Late" .. i then
					ldeliver("WHISPER", S.me, p.msg)
					ldeliver("WHISPER", R.me, p.msg) -- the same original through another signed relay
				end
			end
			local summary = L.Data.Summary()
			eq(summary.characters, total + 108, "a late current-group client counts every roster once")
			eq(summary.online, online + 6); eq(#summary.guilds, 161)
			local children = {}
			for _, row in ipairs(summary.guilds) do
				eq(children[row.name:lower()], nil, "one child row per actual guild")
				children[row.name:lower()] = true
				eq(row.g.total, 108); eq(row.g.online, 6)
			end
			for _, name in ipairs(names) do assert(children[name:lower()], name .. " remains a separate child") end
		end
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo, GetTime, GetServerTime, GetNumGuildMembers, GetGuildRosterInfo =
		saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat, saved.time, saved.serverTime, saved.number, saved.row
	-- Roster.Scan caches the rows it last read. Restore the harness's native fixture so this
	-- isolated transport case cannot change what later status tests inspect.
	pcall(ns.Roster.Scan)
	if not ok then error(err, 0) end
end)

-- A real queue and relay with deterministic elapsed time; native sends remain rate limited.
local function WithTransfer(fn)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo,
		inGuild = IsInGuild, chat = C_ChatInfo, time = GetTime }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local R, deliver, sent = extra.RelayWorld("Max Ran-CAMWOWUS2Realm1PvE", "Olympus II")
		GetTime = function() return R.clock end
		local timers = {}
		R.After = function(delay, label, f)
			if label == "relay drip" then timers[#timers + 1] = { at = R.clock + delay, f = f } end
		end
		local function Run(pumps)
			for _ = 1, pumps do
				R.clock = R.clock + 1.2
				local due = timers; timers = {}
				for _, t in ipairs(due) do
					if t.at <= R.clock then t.f() else timers[#timers + 1] = t end
				end
				local before = #sent
				R.Comm.Pump()
				assert(#sent - before <= 4, "the native pump keeps its four-message rate limit")
				assert(R.Comm.QueueSize() <= R.Comm.MAX_QUEUE, "the native queue remains bounded")
			end
		end
		fn(R, deliver, sent, Run)
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo, GetTime =
		saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat, saved.time
	if not ok then error(err, 0) end
end

local function TransferWord(R, head, pieces)
	return (head .. ("x"):rep(R.Codec.CHUNK * pieces)):sub(1, R.Codec.CHUNK * pieces)
end
-- (1.5.5) A peer's RJ: a mesh peer, the only relay sent RX (tests/relay-mesh.lua). meshFor: the mesh's
-- window as long as this, for a test about the verification's own window.
local function Mesh(R, peer, meshFor)
	if meshFor then R.Relay.MESH_FOR = meshFor end
	R.Relay.HandleMesh("WHISPER", peer, "RJ~1~0~0")
end
local function OfferTransfer(R, word, id, origin)
	for _, p in ipairs(R.Codec.Chunk(word, id)) do
		R.Relay.HandleIn("WHISPER", origin or R.me, "RL~P~" .. p)
	end
end
-- Decode every native envelope and assert that no transfer which sent a piece lost its tail.
local function TransferWords(R, sent, kind)
	local outer, inner, words, pieces = {}, {}, {}, {}
	for _, p in ipairs(sent) do
		outer[p.target] = outer[p.target] or R.Codec.NewAssembler()
		local envelope = p.msg:sub(1, 3) == kind .. "~" and p.msg or R.Codec.Feed(outer[p.target], "relay", p.msg, 0)
		local origin, body
		if envelope then origin, body = envelope:match("^" .. kind .. "~P~([^~]+)~(.*)$") end
		if body then
			inner[p.target] = inner[p.target] or R.Codec.NewAssembler()
			local id, index, count = body:match("^C(%w+):(%d+):(%d+):")
			local word = body
			if id then
				local key = p.target .. " " .. origin .. " " .. id
				local transfer = pieces[key] or { count = tonumber(count), got = {} }
				pieces[key], transfer.got[tonumber(index)] = transfer, true
				word = R.Codec.Feed(inner[p.target], origin, body, 0)
			end
			if word then
				words[p.target] = words[p.target] or {}
				words[p.target][word] = (words[p.target][word] or 0) + 1
			end
		end
	end
	for key, transfer in pairs(pieces) do
		local count = 0
		for _ in pairs(transfer.got) do count = count + 1 end
		eq(count, transfer.count, "every started transfer stays whole: " .. key)
	end
	return words
end

test("relay keeps each pending Arena record fragment distinct", function()
	WithTransfer(function(R, _, sent, Run)
		R.Relay.HandleIn("WHISPER", "Late-Realm", "RL~P~RR~Olympus Late")
		local parts = {
			"EP~L1~abc~1~2~" .. ("RD~L1~" .. string.rep("x", 220)):sub(1, 220),
			"EP~L1~abc~2~2~" .. string.rep("y", 56),
			"EP~L1~abd~1~2~" .. ("RD~L1~" .. string.rep("a", 220)):sub(1, 220),
			"EP~L1~abd~2~2~" .. string.rep("b", 56),
		}
		for _, part in ipairs(parts) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. part) end
		Run(12)
		local words = TransferWords(R, sent, "RM").Late or {}
		for _, part in ipairs(parts) do eq(words[part], 1, "every Arena fragment reaches the reporter once") end
	end)
end)

test("relay admission hardening: an ordinary or nested native handler cannot reuse the envelope's token", function()
	WithTransfer(function(R, deliver)
		R.db = { blocked = {} }
		local origin, other = "Hildryn Payne-Realm", "Other-Realm"
		local calls = 0
		R.Comm.Handle("X1", function(_, sender, text)
			calls = calls + 1
			if text == "X1~outer" then
				deliver("WHISPER", sender, "X1~native reentry")
				R.Comm.Inject("CHANNEL", sender, "X1~nested injection")
				R.Comm.Inject("CHANNEL", other, "X1~different origin")
			end
		end)
		for _ = 1, 59 do assert(R.Comm.Admit(origin, R.clock)) end
		for _ = 1, 60 do assert(R.Comm.Admit(other, R.clock)) end
		deliver("WHISPER", origin, "RM~P~" .. origin .. "~X1~outer")
		eq(calls, 1, "only the admitted envelope's own word gets its token")
		R.Comm.ResetAdmission()
		calls = 0
		for _ = 1, 59 do assert(R.Comm.Admit(origin, R.clock)) end
		for _ = 1, 60 do assert(R.Comm.Admit(other, R.clock)) end
		deliver("WHISPER", origin, "X1~outer")
		eq(calls, 1, "an ordinary handler has no relay envelope admission to lend")
		R.Comm.Inject("CHANNEL", origin, "X1~after return")
		eq(calls, 1, "the exemption does not survive the call stack")
	end)
end)

test("relay transfer hardening: verification expires between batches, but only an entirely waiting transfer is dropped", function()
	WithTransfer(function(R, _, sent, Run)
		R.Relay.HandleAck("WHISPER", "Hildryn Payne-Realm", "RY~")
		Mesh(R, "Hildryn Payne-Realm", R.Relay.VERIFIED_FOR)
		R.clock = R.clock + R.Relay.VERIFIED_FOR - 2
		local word = TransferWord(R, "CG~2~S~1~ForeverPvE~Alliance~", 34)
		OfferTransfer(R, word, "810")
		Run(1) -- first batch starts before verification expires
		assert(#sent > 0)
		Run(100)
		eq((TransferWords(R, sent, "RX")["Hildryn Payne"] or {})[word], 1)
	end)
	WithTransfer(function(R, _, sent, Run)
		R.Relay.HandleAck("WHISPER", "Hildryn Payne-Realm", "RY~")
		Mesh(R, "Hildryn Payne-Realm", R.Relay.VERIFIED_FOR)
		R.clock = R.clock + R.Relay.VERIFIED_FOR - 2
		for i = 1, R.Comm.QueueRoom() do assert(R.Comm.Whisper("Busy-Realm", "X1~" .. i, nil, true)) end
		OfferTransfer(R, TransferWord(R, "CG~2~S~1~ForeverPvE~Alliance~", 34), "811")
		Run(100)
		eq(next(TransferWords(R, sent, "RX")), nil, "expiry before the first batch drops the complete transfer")
	end)
end)

test("relay transfer hardening: signed RX progress survives sixty seconds while idle and absolute expiry remain bounded", function()
	for _, mode in ipairs({ "progress", "absolute", "idle", "duplicate" }) do
		WithTransfer(function(R, _, sent, Run)
			local origin = "Hildryn Payne-CAMWOWUS2Realm7PvE"
			R.Relay.HandleIn("WHISPER", "Late-Realm", "RL~P~RR~Olympus Late")
			local word = TransferWord(R, "CG~2~S~1~ForeverPvE~Alliance~", mode == "progress" and 34 or 10)
			local parts = R.Codec.Chunk(word, "820")
			local function Part(i)
				R.Relay.HandleAcross("WHISPER", origin, "RX~P~" .. origin .. "~" .. parts[i])
			end
			Part(1)
			if mode == "duplicate" then R.clock = R.clock + 50; Part(1); R.clock = R.clock + 11 end
			for i = 2, #parts do
				if mode == "progress" then R.clock = R.clock + 3
				elseif mode == "absolute" then R.clock = R.clock + 40
				elseif mode == "idle" and i == 2 then R.clock = R.clock + R.Relay.SET_WAIT + 1 end
				Part(i)
			end
			Run(100)
			-- Expired sets may use the ordinary trickle, but must never produce a whole snapshot.
			local outer, inner, got = R.Codec.NewAssembler(), R.Codec.NewAssembler(), false
			for _, p in ipairs(sent) do
				if p.target == "Late" then
					local rm = p.msg:sub(1, 3) == "RM~" and p.msg or R.Codec.Feed(outer, "relay", p.msg, 0)
					local body = rm and rm:match("^RM~P~[^~]+~(.*)$")
					if body and (body == word or R.Codec.Feed(inner, origin, body, 0) == word) then got = true end
				end
			end
			eq(got, mode == "progress", mode .. ": only continuing progress inside the absolute age completes")
		end)
	end
end)

local function AcrossDepth(R)
	for _, line in ipairs(R.Relay.BugLines(4096)) do
		local count = line:match("drip=%d+ waiting %((%d+) across%)")
		if count then return tonumber(count) end
	end
	error("the across queue depth must be reported")
end

test("relay transfer hardening: flood bounds count whole transfers globally and per peer, keeping the active tail and current census", function()
	for _, peers in ipairs({ 1, 6 }) do
		WithTransfer(function(R, _, sent, Run)
			for i = 1, peers do
				local name = "Peer " .. i
				R.rdb.council.names[name:lower()] = name
				R.Relay.HandleAck("WHISPER", name .. "-Realm", "RY~")
				Mesh(R, name .. "-Realm")
			end
			local first = TransferWord(R, "CX~1~S~First~", 34)
			OfferTransfer(R, first, "830")
			Run(1) -- flood only after the first batch has actually started
			for i = 1, 20 do
				OfferTransfer(R, TransferWord(R, "CX~" .. (i % 3 + 1) .. "~S~Mail " .. i .. "~", 34), tostring(830 + i))
				local origin = "Origin " .. i
				R.rdb.council.names[origin:lower()] = origin
				OfferTransfer(R, TransferWord(R, "CG~2~S~1~ForeverPvE~Alliance~" .. i, 34), tostring(860 + i), origin .. "-Realm")
			end
			local otherWork = AcrossDepth(R)
			assert(otherWork <= R.Relay.ACROSS_MAX, "the flood never expands the across queue")
			local newest = TransferWord(R, "CG~2~S~2~ForeverPvE~Alliance~", 34)
			OfferTransfer(R, newest, "899")
			assert(AcrossDepth(R) <= R.Relay.ACROSS_MAX, "CG waits without overflowing the queue")
			Run(250)
			local words, total, firstSent = TransferWords(R, sent, "RX"), 0, 0
			for i = 1, peers do
				local got, count = words["Peer " .. i] or {}, 0
				for _, copies in pairs(got) do count = count + copies end
				assert(count <= R.Relay.ACROSS_PER_PEER + 1, "only one new census after that peer's bounded earlier work")
				eq(got[newest], 1, "the current census reaches every peer after the flood")
				firstSent = firstSent + (got[first] or 0)
				total = total + count
			end
			eq(firstSent, 1, "the started transfer survives all evictions")
			eq(total, otherWork + peers, "earlier admitted work drains before one new census per peer")
			eq(AcrossDepth(R), 0)
			eq(R.Comm.QueueSize(), 0)
		end)
	end
end)

test("census RX fairness: a busy mesh sends the newest whole snapshot to the King and peers beyond the queue cap", function()
	WithTransfer(function(R, _, sent, Run)
		local king = "Zed Crown"
		R.KingCharacter = function() return king end
		R.IsKingCharacter = function(name) return R.ShortName(name) == king end
		local peers = { king }
		for i = 1, R.Relay.ACROSS_MAX + 3 do
			local name = ("Peer %02d"):format(i)
			R.rdb.council.names[name:lower()] = name
			peers[#peers + 1] = name
		end
		for _, name in ipairs(peers) do Mesh(R, name .. "-Realm") end
		Run(10) -- send the RJ replies before filling the normal queue
		for i = 1, R.Comm.QueueRoom() do assert(R.Comm.Whisper("Busy-Realm", "X1~" .. i, nil, true)) end
		local first = TransferWord(R, "CG~2~S~1~ForeverPvE~Alliance~", 3)
		local latest = TransferWord(R, "CG~2~S~2~ForeverPvE~Alliance~", 3)
		OfferTransfer(R, first, "921")
		OfferTransfer(R, latest, "922") -- no snapshot's first batch has entered the full native queue
		local start = #sent
		Run(100)
		local firstPeer
		for i = start + 1, #sent do
			if R.ShortName(sent[i].target or "") ~= "Busy" then firstPeer = sent[i].target; break end
		end
		eq(firstPeer, king, "the King's pending census gets the first across turn")
		local words = TransferWords(R, sent, "RX")
		for _, name in ipairs(peers) do
			eq((words[name] or {})[latest], 1, name .. " receives the latest whole word")
			eq((words[name] or {})[first], nil, "a waiting obsolete copy was replaced")
		end
		local early = TransferWord(R, "CG~2~S~3~ForeverPvE~Alliance~", 3)
		OfferTransfer(R, early, "923")
		Run(40)
		words = TransferWords(R, sent, "RX")
		for _, name in ipairs(peers) do eq(words[name][early], nil, name .. " stays under the existing cadence") end
	end)
end)

test("census RX fairness: a queued local snapshot stays home when presence becomes private before it starts", function()
	WithTransfer(function(R, _, sent, Run)
		Mesh(R, "Hildryn Payne-Realm")
		Run(10)
		for i = 1, R.Comm.QueueRoom() do assert(R.Comm.Whisper("Busy-Realm", "X1~" .. i, nil, true)) end
		local word = TransferWord(R, "CG~2~S~1~ForeverPvE~Alliance~", 3)
		OfferTransfer(R, word, "924")
		eq(AcrossDepth(R), 1)
		R.QuietPresence = function() return true end
		Run(100)
		eq(TransferWords(R, sent, "RX")["Hildryn Payne"], nil)
		eq(AcrossDepth(R), 0)
	end)
end)

test("relay transfer hardening: a full bound never evicts the sole in-flight transfer", function()
	for _, bound in ipairs({ "ACROSS_MAX", "ACROSS_PER_PEER" }) do
		WithTransfer(function(R, _, sent, Run)
			R.Relay[bound] = 1
			R.Relay.HandleAck("WHISPER", "Hildryn Payne-Realm", "RY~")
			Mesh(R, "Hildryn Payne-Realm")
			local first = TransferWord(R, "CX~1~S~First~", 34)
			OfferTransfer(R, first, "910")
			Run(1)
			OfferTransfer(R, TransferWord(R, "CX~2~S~Second~", 34), "911")
			Run(100)
			local got, count = TransferWords(R, sent, "RX")["Hildryn Payne"] or {}, 0
			for _ in pairs(got) do count = count + 1 end
			eq(count, 1, bound .. ": refuse new work when no complete waiting transfer can be evicted")
			eq(got[first], 1)
		end)
	end
end)

test("relay transfer hardening: shrinking replacements replace whole waiting copies without splicing an active tail", function()
	WithTransfer(function(R, _, sent, Run)
		R.Relay.HandleAck("WHISPER", "Hildryn Payne-Realm", "RY~")
		Mesh(R, "Hildryn Payne-Realm")
		R.Relay.MESH_CROSS_EVERY = 0 -- (1.5.5: each of its snapshots may cross; this test is about the drip)
		local first = TransferWord(R, "CG~2~S~1~ForeverPvE~Alliance~", 34)
		OfferTransfer(R, first, "901")
		Run(1)
		OfferTransfer(R, TransferWord(R, "CG~2~S~2~ForeverPvE~Alliance~", 34), "902")
		local newest = TransferWord(R, "CG~2~S~3~ForeverPvE~Alliance~", 2)
		OfferTransfer(R, newest, "903")
		Run(100)
		local got, count = TransferWords(R, sent, "RX")["Hildryn Payne"] or {}, 0
		for _ in pairs(got) do count = count + 1 end
		eq(count, 2); eq(got[first], 1); eq(got[newest], 1)
	end)
end)

test("census scope relay: count snapshots and portable observations drain through the actual relay while revoked capabilities stop", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local O, deliver, sent, _, pump = extra.RelayWorld("Original-Realm", "Olympus II")
		local relay = O.Relay.Pick()
		deliver("WHISPER", relay .. "-Realm", "RY~")
		O.group, O.faction, O.db = "ForeverPvP", "Alliance", {}
		O.rdb.guilds, O.rdb.seen = {}, {}
		local trusted = true
		O.Church = { IsLedgerRelay = function() return trusted end }
		O.QuietPresence = function() return false end
		assert(loadfile(extra.addon .. "Data.lua"))("Olympus", O)
		O.rdb.guilds["Olympus Dawn"] = { total = 640, online = 40, t = O.clock, from = "CAMWOWUS1Realm8PvP" }
		local function Contains(needle, since)
			for i = (since or 0) + 1, #sent do
				if sent[i].msg:find(needle, 1, true) then
					eq(sent[i].dist, "WHISPER"); eq(sent[i].target, relay)
					return true
				end
			end
			return false
		end
		assert(O.Data.SendGlobalCensus())
		pump(100)
		assert(Contains("CG~2~S~"), "accepted global snapshot must actually leave the native whisper API")
		assert(O.Data.RecordGroupCensus())
		O.group = "ForeverPvE" -- a carried PvP observation is sent after travelling to another origin
		assert(O.Data.SayGroupCensus())
		pump(100)
		assert(Contains("CX~3~S~"), "portable observation must leave through the same guarded relay route")
		O.group = "ForeverPvP"
		O.db.groupDetails["Alliance|Other"] = { group = "Other", faction = "Alliance", observed = O.clock,
			rows = { dawn = { name = "Olympus Dawn", total = 640, online = 40, avg10 = 300, observed = O.clock } } }
		assert(O.Data.SayGroupDetails())
		pump(100)
		assert(Contains("CX~2~S~"), "compatible detail transport also retains its logical channel capability")
		local before = #sent
		assert(O.Data.SendGlobalCensus())
		trusted = false
		pump(100)
		eq(Contains("CG~2~S~", before), false, "losing original trust cancels the queued snapshot")
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end)

local function ScheduledCarry(rejectFirst)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo,
		inGuild = IsInGuild, chat = C_ChatInfo, random = math.random }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local O, deliver, sent, _, pump = extra.RelayWorld("Carrier-Realm", "Olympus II")
		local relay = O.Relay.Pick()
		deliver("WHISPER", relay .. "-Realm", "RY~")
		local timers, init, start, stamped = {}, {}, O.clock, 0
		O.group, O.faction, O.db = "ForeverPvE", "Alliance", { blocked = {} }
		O.rdb.guilds, O.rdb.seen = {}, {}
		O.Church = { IsLedgerRelay = function() return false end }
		O.QuietPresence = function() return false end
		O.On = function(event, fn) if event == "INIT" then init[#init + 1] = fn end end
		O.After = function(delay, label, fn)
			if label == "census groups" then timers[#timers + 1] = { at = O.clock + delay, fn = fn } end
		end
		O.Every = function(delay, label, fn)
			if label == "census groups" then timers[#timers + 1] = { at = O.clock + delay, fn = fn, every = delay } end
		end
		assert(loadfile(extra.addon .. "Data.lua"))("Olympus", O)
		for _, rules in ipairs({ "PvE", "PvP", "RP" }) do
			O.group, O.me = "Forever" .. rules, "Observer" .. rules .. "-Realm"
			O.rdb.guilds = { ["Olympus " .. rules] = { total = 100, online = 10, t = O.clock - 60,
				from = "CAMWOWUS1Realm1" .. rules } }
			assert(O.Data.RecordGroupCensus())
		end
		O.group, O.me, O.rdb.guilds = "ForeverPvE", "Carrier-Realm", {}
		math.random = function(a, b) return b or a end -- latest allowed first send
		local attempts, refused = {}, 0
		local send = O.Comm.SendChunked
		O.Comm.SendChunked = function(payload, ...)
			if payload:match("^CX~3~") then
				attempts[#attempts + 1] = payload
				if rejectFirst and refused == 0 then refused = 1; return false end
			end
			return send(payload, ...)
		end
		for _, fn in ipairs(init) do fn() end
		local function Advance(to)
			while true do
				table.sort(timers, function(a, b) return a.at < b.at end)
				local t = timers[1]
				if not t or t.at > to then break end
				table.remove(timers, 1); O.clock = t.at; t.fn()
				if t.every then t.at = O.clock + t.every; timers[#timers + 1] = t end
				pump(100)
				for i = stamped + 1, #sent do sent[i].at = O.clock end
				stamped = #sent
			end
			O.clock = to
		end
		Advance(start + 40)
		eq(#attempts, 1, "INIT attempts the first foreign origin within 40 seconds")
		assert(not attempts[1]:find("~ForeverPvE~", 1, true), "the local origin never consumes the first slot")
		Advance(start + (rejectFirst and 170 or 105))
		eq(#attempts, rejectFirst and 3 or 2, "foreign origins drain at 65-second intervals")
		if rejectFirst then eq(attempts[1], attempts[2], "a rejected queue admission does not skip the origin") end
		local last = #attempts
		Advance(start + 1799)
		eq(#attempts, last, "unchanged origins are not repeated within their 30-minute window")
		Advance(start + 2000)
		assert(#attempts > last, "the next bounded window permits a refresh")
		-- Feed actual native packets through the relay into a client that never visited either origin.
		local R, rdeliver, rsent, _, rpump = extra.RelayWorld(relay .. "-Realm", "Olympus Relay")
		rdeliver("WHISPER", "Late-Realm", "RL~P~RR~Olympus Late")
		for _, p in ipairs(sent) do
			if p.target == relay and p.at and p.at <= start + 170 and p.msg:find("CX~3~", 1, true) then
				R.clock = p.at; rdeliver("WHISPER", "Carrier-Realm", p.msg); rpump(100)
			end
		end
		local L, ldeliver = extra.RelayWorld("Late-Realm", "Olympus Late")
		L.group, L.faction, L.db = "ForeverPvE", "Alliance", { blocked = {} }
		L.rdb.guilds, L.rdb.seen = {}, {}
		assert(loadfile(extra.addon .. "Data.lua"))("Olympus", L)
		L.Comm.Handle("CX", L.Data.ReceiveGroupCensus)
		for _, p in ipairs(rsent) do if p.target == "Late" then ldeliver("WHISPER", R.me, p.msg) end end
		local all = L.Data.Groups()
		eq(#all.rows, 2, "both never-visited origins arrive through the actual relay")
		for _, row in ipairs(all.rows) do
			eq(row.characters, 100); eq(row.observed, start - 60); eq(row.counted, false)
		end
		eq(L.Data.Summary().characters, 0, "foreign observations never change local authority or current census")
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo, math.random =
		saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat, saved.random
	if not ok then error(err, 0) end
end

test("census carry schedule: INIT delivers two foreign origins promptly without repeating unchanged observations", function()
	ScheduledCarry(false)
end)
test("census carry schedule: rejected admission retries the same origin before progressing without a send storm", function()
	ScheduledCarry(true)
end)

test("census scope relay: two large ordinary-origin observations cross the same reporter budget as complete atomic aggregates", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local function Census(N)
			N.group, N.faction, N.db = "ForeverPvP", "Alliance", { blocked = {} }
			N.rdb.guilds, N.rdb.seen = {}, {}
			N.Church = { IsLedgerRelay = function() return false end }
			N.QuietPresence = function() return false end
			assert(loadfile(extra.addon .. "Data.lua"))("Olympus", N)
			N.Comm.Handle("CX", N.Data.ReceiveGroupCensus)
		end
		local carrier = "Carrier" .. string.rep("x", 70) .. "-Realm"
		local O, odeliver, osent, _, opump = extra.RelayWorld(carrier, "Olympus II")
		local relay = O.Relay.Pick()
		odeliver("WHISPER", relay .. "-Realm", "RY~")
		Census(O)
		for _, rules in ipairs({ "PvE", "RP" }) do
			O.group, O.me = "Forever" .. rules, "Observer" .. rules .. "-Realm"
			for i = 1, 20 do
				O.rdb.guilds["Olympus Lengthy Guild " .. i] = { total = 50, online = 10, t = O.clock - 60,
					from = "CAMWOWUS1Realm1" .. rules }
			end
			assert(O.Data.RecordGroupCensus())
			local fullBytes = 0
			for _, guild in ipairs(O.Data.GroupGuilds(O.group)) do fullBytes = fullBytes + #guild.name + 24 end
			assert(fullBytes > 4 * O.Codec.CHUNK, "the full detail source originally exceeds the ordinary trickle")
		end
		O.group, O.me = "ForeverPvP", carrier
		for _ = 1, 2 do
			assert(#O.Data.PortablePayload() <= O.Codec.CHUNK, "complete aggregate and partial detail must fit one logical chunk")
		end
		assert(O.Data.SayGroupCensus()); assert(O.Data.SayGroupCensus()); opump(100)
		local R, rdeliver, rsent, _, rpump = extra.RelayWorld(relay .. "-Realm", "Olympus Relay")
		Census(R)
		rdeliver("WHISPER", "Late-Realm", "RL~P~RR~Olympus Late")
		for _, packet in ipairs(osent) do if packet.target == relay then rdeliver("WHISPER", O.me, packet.msg) end end
		rpump(100)
		local L, ldeliver = extra.RelayWorld("Late-Realm", "Olympus Late")
		Census(L)
		local pieces = 0
		for _, packet in ipairs(rsent) do
			if packet.target == "Late" then pieces = pieces + 1; ldeliver("WHISPER", R.me, packet.msg) end
		end
		eq(pieces, R.Relay.REPORTER_RATE, "both two-envelope origins fit the unchanged four-piece budget")
		local all = L.Data.Groups()
		eq(#all.rows, 2, "the second origin cannot strand the first observation mid-transfer")
		for _, row in ipairs(all.rows) do
			eq(row.characters, 1000); eq(row.guilds, 20); eq(row.observed, O.clock - 60)
			eq(row.counted, false, "carriers do not manufacture authenticated originals")
			assert(#L.Data.GroupGuilds(row.group) < 20, "only explicitly partial guild details fit beside the full aggregate")
		end
		eq(L.Data.Summary().characters, 0)
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end)

test("census scope relay: a multi-part scoped snapshot survives the relay fanout and restores an empty reporter", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local function Census(N)
			N.group, N.faction, N.db = "ForeverPvP", "Alliance", { blocked = {} }
			N.rdb.guilds, N.rdb.seen = {}, {}
			N.Church = { IsLedgerRelay = function() return true end }
			N.QuietPresence = function() return false end
			assert(loadfile(extra.addon .. "Data.lua"))("Olympus", N)
			N.Comm.Handle("CG", N.Data.ReceiveGlobalCensus)
		end
		local O, odeliver, osent, _, opump = extra.RelayWorld("Original-Realm", "Olympus II")
		local relay = O.Relay.Pick()
		odeliver("WHISPER", relay .. "-Realm", "RY~")
		Census(O)
		local total = 0
		for i = 1, 12 do
			O.rdb.guilds["Olympus Origin Guild " .. i] = { total = 50 + i, online = 10, t = O.clock - 60, from = "CAMWOWUS1Realm8PvP" }
			total = total + 50 + i
		end
		assert(#O.Data.GlobalCensusPayload() > O.Codec.CHUNK, "exercise several independently relayed chunks")
		assert(O.Data.SendGlobalCensus()); opump(100)
		local R, rdeliver, rsent, _, rpump = extra.RelayWorld(relay .. "-Realm", "Olympus Relay")
		Census(R)
		for _, packet in ipairs(osent) do
			if packet.target == relay then rdeliver("WHISPER", O.me, packet.msg) end
		end
		eq(R.Data.Summary().characters, total, "the receiving relay assembles every original count")
		rdeliver("WHISPER", "Late-Realm", "RL~P~RR~Olympus Late")
		assert(R.Data.SendGlobalCensus()); rpump(100)
		local L, ldeliver = extra.RelayWorld("Late-Realm", "Olympus Late")
		Census(L)
		L.Comm.loginAt = L.clock
		for _, packet in ipairs(rsent) do
			if packet.target == "Late" then ldeliver("WHISPER", R.me, packet.msg) end
		end
		eq(L.Data.Summary().characters, total, "all parts reach the reporter before any local rebuild")
		eq(#L.Data.Summary().guilds, 12); eq(next(L.rdb.guilds), nil)
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end)

-- 1.5.4 (the dev, 2026-11-08: "O censo não tá fazendo a retransmissão dos dados do PVP ... tá na
-- minha conta, para mim mostra os dados, eu olhei a conta do Asmon e de várias outras pessoas, não
-- mostra para ninguém"). Fails before: 1.5.2 left every Forever family out of CX 1 and marked any
-- Forever row it heard unproven, and a carried CX 3 counts only from its own observer, who is on the
-- other family by definition. No client counted another family unless its own account played there;
-- the README's "when a moderator says it" never happened for the launch's families.
test("census family trust: a trusted relay's own look at the other family counts on a client that never played there, through the actual relay; an ordinary carrier's stays reported", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local function Census(N)
			N.faction, N.db = "Alliance", { blocked = {} }
			N.rdb.guilds, N.rdb.seen = {}, {}
			N.Church = { IsLedgerRelay = function(name)
				local short = ns.ShortName(name or "")
				return short == "Hildryn Payne" or short == "Max Ran" -- two signed councillors
			end }
			N.QuietPresence = function() return false end
			assert(loadfile(extra.addon .. "Data.lua"))("Olympus", N)
			N.Comm.Handle("CX", N.Data.ReceiveGroupCensus)
		end
		-- The signed relay's account: one of its PvP characters counted 19 PvP guilds...
		local D, _, dsent, _, dpump = extra.RelayWorld("Pvp Alt-CAMWOWUS1Realm8PvP", "Olympus Relay")
		Census(D)
		D.group = "ForeverPvP"
		local total = 0
		for i = 1, 19 do
			D.rdb.guilds["Olympus Pvp " .. i] = { total = 190 + i, online = 20, t = D.clock - 60, from = "CAMWOWUS1Realm8PvP" }
			total = total + 190 + i
		end
		assert(D.Data.RecordGroupCensus())
		-- ...and it now plays the signed relay on PvE, where a guild's reporter registered with it.
		D.me, D.group, D.rdb.guilds = "Hildryn Payne-CAMWOWUS2Realm1PvE", "ForeverPvE", {}
		D.Relay.HandleIn("WHISPER", "Kay Near-CAMWOWUS2Realm1PvE", "RL~P~RR~Olympus Near")
		for _ = 1, 3 do
			D.Data.SayGroupCensus()
			dpump(100)
			D.clock = D.clock + D.Data.GROUP_SEND_GAP
		end
		local K, kdeliver = extra.RelayWorld("Kay Near-CAMWOWUS2Realm1PvE", "Olympus Near")
		Census(K)
		K.group, K.clock = "ForeverPvE", D.clock
		for _, p in ipairs(dsent) do if tostring(p.target):find("^Kay Near") then kdeliver("WHISPER", D.me, p.msg) end end
		local function PvP(g)
			for _, r in ipairs(g.rows) do if r.group == "ForeverPvP" and r.faction == "Alliance" then return r end end
		end
		local g = K.Data.Groups()
		local row = assert(PvP(g), "the PvP row reaches the PvE reporter through the relay")
		eq(row.characters, total); eq(row.guilds, 19)
		eq(row.counted, true, "a trusted relay's own look counts alone (1.4.0: a moderator's alone)")
		eq(row.src, "relay")
		eq(g.characters, total, "and enters the all-server total"); eq(g.kinds.pvp and g.kinds.pvp.characters, total)
		eq(K.Data.Summary().characters, 0, "it never becomes the PvE census")
		-- An ordinary carrier's newer one-guild look, by CX 1 or CX 3, stays reported: it neither
		-- counts nor replaces the trusted count.
		K.clock = K.clock + 60
		K.Data.ReceiveGroupCensus("CHANNEL", "Plain Carrier-CAMWOWUS2Realm1PvE",
			("CX~1~S~%d~ForeverPvP,Alliance,151,151,1,%d"):format(K.clock, K.clock - 30))
		K.Data.ReceiveGroupCensus("CHANNEL", "Plain Carrier-CAMWOWUS2Realm1PvE",
			("CX~3~S~Other Pvp-CAMWOWUS1Realm6PvP~ForeverPvP~Alliance~151,151,1,%d~"):format(K.clock - 20))
		g = K.Data.Groups()
		row = assert(PvP(g))
		eq(row.characters, total); eq(row.counted, true); eq(g.characters, total)
		-- Another councillor whose own PvP character saw only its own guild: newer, trusted, and still
		-- not the family's count while the 19-guild look counts.
		K.Data.ReceiveGroupCensus("CHANNEL", "Max Ran-CAMWOWUS2Realm1PvE",
			("CX~1~S~%d~ForeverPvP,Alliance,151,151,1,%d"):format(K.clock, K.clock - 10))
		row = assert(PvP(K.Data.Groups()))
		eq(row.characters, total, "a trusted one-guild look does not replace a counted 19-guild look")
		-- The same word from an ordinary sender never counts (the 1.5.2 rule, unchanged).
		local U, udeliver = extra.RelayWorld("Una Far-CAMWOWUS2Realm1PvE", "Olympus Far")
		Census(U)
		U.group, U.clock = "ForeverPvE", K.clock
		U.Church.IsLedgerRelay = function() return false end
		for _, p in ipairs(dsent) do if tostring(p.target):find("^Kay Near") then udeliver("WHISPER", D.me, p.msg) end end
		local u = U.Data.Groups()
		eq(u.characters, 0, "the same words from a sender this client does not trust stay reported")
		eq(assert(PvP(u)).counted, false)
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end)

-- The review of the 1.5.4 candidate, beside the test above: clients of a Forever realm group's PvE
-- family whose Data.lua trusts the two signed councillors, as there.
local function FamilyWorld(fn)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local function Client(me, guild)
			local N = extra.RelayWorld(me, guild)
			N.faction, N.db = "Alliance", { blocked = {} }
			N.rdb.guilds, N.rdb.seen = {}, {}
			N.Church = { IsLedgerRelay = function(name)
				local short = ns.ShortName(name or "")
				return short == "Hildryn Payne" or short == "Max Ran"
			end }
			N.QuietPresence = function() return false end
			assert(loadfile(extra.addon .. "Data.lua"))("Olympus", N)
			N.group = "ForeverPvE"
			return N
		end
		fn(Client)
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	if not ok then error(err, 0) end
end
local function PvP(g)
	for _, r in ipairs(g.rows) do if r.group == "ForeverPvP" and r.faction == "Alliance" then return r end end
end
local function Look(N, from, characters, guilds, observed)
	return N.Data.ReceiveGroupCensus("CHANNEL", from,
		("CX~1~S~%d~ForeverPvP,Alliance,%d,%d,%d,%d"):format(N.clock, characters, characters, guilds, observed))
end

-- Fails before: the one-guild look was kept for being newer, and the older 19-guild look was refused
-- for being older, so the family's count was one guild's until a newer full look came.
test("census family trust: a trusted one-guild look of the family heard before an older trusted 19-guild look ends with the 19-guild look counted", function()
	FamilyWorld(function(Client)
		local K = Client("Kay Near-CAMWOWUS2Realm1PvE", "Olympus Near")
		local t0 = K.clock
		Look(K, "Max Ran-CAMWOWUS2Realm1PvE", 151, 1, t0 - 10)
		eq(assert(PvP(K.Data.Groups())).guilds, 1, "alone, the one-guild look is what is held")
		Look(K, "Hildryn Payne-CAMWOWUS2Realm1PvE", 3800, 19, t0 - 600)
		local row = assert(PvP(K.Data.Groups()))
		eq(row.guilds, 19, "the older 19-guild look replaces it"); eq(row.characters, 3800)
		eq(row.counted, true); eq(row.src, "relay")
		K.clock = t0 + 60
		Look(K, "Max Ran-CAMWOWUS2Realm1PvE", 151, 1, K.clock - 5)
		eq(assert(PvP(K.Data.Groups())).guilds, 19, "and the one-guild look, newer again, does not take its place back")
	end)
end)

-- Fails before: the refused look was noted as heard first (groupHeard), which keeps this client from
-- saying any look of the family not newer than it, so the councillor stopped saying its own.
test("census family trust: a councillor's own 19-guild look of the other family is still said after a newer trusted one-guild look of it was refused", function()
	FamilyWorld(function(Client)
		local D = Client("Pvp Alt-CAMWOWUS1Realm8PvP", "Olympus Relay")
		D.group = "ForeverPvP"
		for i = 1, 19 do D.rdb.guilds["Olympus Pvp " .. i] = { total = 190 + i, online = 20, t = D.clock - 60, from = "CAMWOWUS1Realm8PvP" } end
		assert(D.Data.RecordGroupCensus())
		D.me, D.group, D.rdb.guilds = "Hildryn Payne-CAMWOWUS2Realm1PvE", "ForeverPvE", {}
		assert(tostring(D.Data.GroupCensusPayload()):find("~ForeverPvP,Alliance,", 1, true), "its own look is said")
		D.clock = D.clock + 30 * 60
		Look(D, "Max Ran-CAMWOWUS2Realm1PvE", 151, 1, D.clock - 10)
		local row = assert(PvP(D.Data.Groups()))
		eq(row.guilds, 19, "the newer one-guild look is refused"); eq(row.src, "own")
		local said = D.Data.GroupCensusPayload()
		assert(tostring(said):find("~ForeverPvP,Alliance,", 1, true), "and its own 19-guild look is still said: " .. tostring(said))
	end)
end)

-- Fails before: a trusted client said every family row it held in its trusted name, a row it took
-- from someone else as well (in the session it took it in, what it heard kept it quiet; in a later
-- one nothing did), so a forged row it took would travel on as a councillor's own word.
test("census family trust: a councillor that took a row of the family from someone else does not say it, in a later session either", function()
	FamilyWorld(function(Client)
		local D = Client("Hildryn Payne-CAMWOWUS2Realm1PvE", "Olympus Relay")
		local t0 = D.clock
		Look(D, "Max Ran-CAMWOWUS2Realm1PvE", 3800, 19, t0 - 600)
		local row = assert(PvP(D.Data.Groups()))
		eq(row.counted, true); eq(row.src, "relay", "taken from the other councillor")
		eq(D.Data.GroupCensusPayload(), nil, "not said in its name")
		-- A later session (a reload): the row is still held, and still not said.
		assert(loadfile(extra.addon .. "Data.lua"))("Olympus", D)
		D.clock = t0 + 60
		eq(assert(PvP(D.Data.Groups())).src, "relay", "still held")
		eq(D.Data.GroupCensusPayload(), nil, "nor in a later session")
	end)
end)

-- Fails before: on Forever a whisper arrives with the sender's bare name and the relay's client stamps
-- its own sub-realm on the origin (Relay.lua's HandleIn), so a councillor's own look came back to her
-- from her guild's reporter as "Hildryn Payne-<the relay's sub-realm>": past the self check (whole
-- names), trusted by her short name, noted as heard (groupHeard), and her own look was never said
-- again that session (once per login instead of every half hour; a relay's own client is not
-- affected, its origin being ns.me, which Comm drops as an echo). The same echo of her global census
-- snapshot (CG) passed the self check there and its rows were taken as another councillor's.
test("census family trust: a councillor's own look of the other family heard back stamped with the relay's sub-realm is still said again, and her own global snapshot so stamped is taken from nobody", function()
	FamilyWorld(function(Client)
		local D = Client("Pvp Alt-CAMWOWUS1Realm8PvP", "Olympus Relay")
		D.group = "ForeverPvP"
		for i = 1, 19 do D.rdb.guilds["Olympus Pvp " .. i] = { total = 190, online = 10, t = D.clock - 60, from = "CAMWOWUS1Realm8PvP" } end
		assert(D.Data.RecordGroupCensus())
		D.me, D.group, D.rdb.guilds = "Hildryn Payne-CAMWOWUS2Realm1PvE", "ForeverPvE", {}
		D.clock = D.clock + 600
		local said = assert(D.Data.GroupCensusPayload(), "her own look is said")
		eq(D.Data.ReceiveGroupCensus("CHANNEL", "Hildryn Payne-CAMWOWUS2Realm3PvE", said), true, "her own word back, stamped by the relay")
		eq(assert(PvP(D.Data.Groups())).src, "own", "her own look is still her own")
		D.clock = D.clock + 31 * 60
		local again = D.Data.GroupCensusPayload()
		assert(tostring(again):find("~ForeverPvP,Alliance,3610,3610,19,", 1, true), "said again half an hour later: " .. tostring(again))
		-- The same look from the other councillor is his word, and keeps her quiet as before.
		eq(D.Data.ReceiveGroupCensus("CHANNEL", "Max Ran-CAMWOWUS2Realm3PvE", again), true)
		D.clock = D.clock + 31 * 60
		eq(D.Data.GroupCensusPayload(), nil, "another councillor's same look: heard, not said over")
		-- Her own global snapshot back the same way: taken from nobody (before: a row by "Hildryn
		-- Payne-CAMWOWUS2Realm3PvE", as another councillor's word).
		eq(D.Data.ReceiveGlobalCensus("CHANNEL", "Hildryn Payne-CAMWOWUS2Realm3PvE",
			("CG~2~S~%d~ForeverPvE~Alliance~Olympus Near,100,10,30,%d"):format(D.clock, D.clock - 60)), true)
		eq((D.rdb.censusGlobal or {})["olympus near"], nil, "nothing taken from her own echo")
	end)
end)
