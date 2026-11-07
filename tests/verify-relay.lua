-- Real Comm + Relay + Verify path; only Blizzard's wire/timers are simulated.
local ns, test, eq, RelayWorld, ADDON_DIR = ...
local T0 = 1800000000
local GUILD, REVOKED = "Olympus Vanguard", "Olympus Embers"
local MASTER, HC = "Guild Master-Realm", "Max Ran-Realm"

local function World(fn)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo,
		inGuild = IsInGuild, chat = C_ChatInfo }
	local dialogs = {}; for k, v in pairs(StaticPopupDialogs) do dialogs[k] = v end
	local nodes, timers, now = {}, {}, T0
	GetChannelName = function() return 0 end
	ns.IsMember = function() return true end
	IsInGuild = function() return true end
	local function As(n, f, ...)
		C_ChatInfo = n.chat
		GetGuildInfo = function() return n.guild, "Member", 3 end
		return f(...)
	end
	local function Node(name, guild)
		local c, deliver, sent, _, pump, sentOf = RelayWorld(name, guild)
		local n = { c = c, deliver = deliver, sent = sent, pump = pump, sentOf = sentOf,
			guild = guild, chat = C_ChatInfo, cursor = 0 }
		c.clock, c.realm, c.RealmPages = now, "Realm", {}
		c.rdb.guilds = { [GUILD] = { leader = MASTER, realm = "Realm" },
			[REVOKED] = { leader = MASTER, realm = "Realm" } }
		c.IsHighCouncillor = function(who) return c.FullName(who) == HC end
		c.IsKingCharacter = function() return false end
		c.Workshop = { IsAuthorName = function() return false end }
		c.Fire, c.On = function() end, function() end
		c.UI = { Refresh = function() end }
		c.After = function(delay, _, f) timers[#timers + 1] = { at = now + delay, n = n, f = f } end
		c.Every = function() end
		As(n, function() assert(loadfile(ADDON_DIR .. "Verify.lua"))("Olympus", c) end)
		c.Verify.Clock = function() return now end
		c.Verify.random = function(a) return a end
		nodes[#nodes + 1] = n
		return n
	end
	local function Flush()
		for _ = 1, 30 do
			local moved = false
			for _, n in ipairs(nodes) do
				As(n, n.pump, 40)
				while n.cursor < #n.sent do
					n.cursor = n.cursor + 1
					local p = n.sent[n.cursor]
					for _, to in ipairs(nodes) do
						if to ~= n and ((p.dist == "WHISPER" and ns.ShortName(to.c.me) == ns.ShortName(p.target))
							or (p.dist == "GUILD" and to.guild == n.guild)) then
							As(to, to.deliver, p.dist, n.c.me, p.msg); moved = true
						end
					end
				end
			end
			if not moved then return end
		end
		error("verification wire did not settle")
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
	for k in pairs(StaticPopupDialogs) do StaticPopupDialogs[k] = dialogs[k] end
	if not ok then error(err, 0) end
end

test("verification recovery: a request crosses signed relays to the verifier and restores original decisions through the real wire", function()
	World(function(Node, As, Flush, Advance)
		local member = Node("New Member-Realm", GUILD)
		local hub = Node("Hildryn Payne-Realm", "Olympus Hearth")
		local verifier = Node(HC, "Olympus Crown")
		As(verifier, verifier.c.Verify.Observe)
		eq(As(verifier, verifier.c.Verify.Approve, GUILD, MASTER), true)
		eq(As(verifier, verifier.c.Verify.Approve, REVOKED, MASTER), true)
		Advance(1)
		eq(As(verifier, verifier.c.Verify.Revoke, REVOKED), true)
		Advance(3600)
		As(hub, hub.deliver, "WHISPER", HC, "RY~")
		As(hub, hub.deliver, "WHISPER", member.c.me, "RL~P~RR~" .. GUILD)
		As(member, member.deliver, "WHISPER", hub.c.me, "RY~")
		eq(As(member, member.c.Verify.Ask), true)
		Flush(); Advance(9)
		eq(As(member, member.c.Verify.Status, GUILD), "verified", "a different relay holds the approval")
		local entry = member.c.rdb.verify.list[ns.Fold(GUILD)]
		eq(entry.at, T0); eq(entry.by, HC, "snapshot retains the original verifier")
		eq(member.c.rdb.verify.start[ns.Fold(GUILD)].at, T0, "recovery never restarts grace")
		eq(member.c.rdb.verify.list[ns.Fold(REVOKED)].k, "R", "the revocation is recovered too")
		eq(#hub.sentOf("RM~P~" .. member.c.me .. "~GV~1~Q~"), 0, "asks never fan out to guild reporters")
		eq(#verifier.sentOf("RM~P~" .. member.c.me .. "~GV~1~Q~"), 0)
		eq(#verifier.sentOf("RX~P~" .. member.c.me .. "~GV~1~Q~"), 0, "no second across hop")
		-- A guildmate's forged cached row cannot become authority through the same relay.
		local forged = ("GV~1~S~%d~A,%d,%s,%s,%s"):format(T0 + 3610, T0 + 3610, REVOKED, MASTER, HC)
		local refused = member.c.Verify.Stats().refused
		As(hub, hub.deliver, "WHISPER", "Untrusted Member-Realm", "RL~P~" .. forged)
		Flush()
		eq(member.c.Verify.Stats().refused, refused + 1, "the forgery arrived and was rejected by authority, not packet loss")
		eq(member.c.rdb.verify.list[ns.Fold(REVOKED)].k, "R", "by=HC is not proof")
		-- Rebuilding census rows or returning to this realm's saved store keeps the word.
		local original = member.c.rdb
		original.guilds = {}
		eq(As(member, member.c.Verify.Status, GUILD), "verified")
		member.c.rdb = { guilds = {} }
		As(member, member.c.Verify.Observe)
		member.c.rdb = original
		eq(As(member, member.c.Verify.Status, GUILD), "verified")
	end)
end)

test("verification recovery: translated capabilities keep their logical lane, exact payload and owner through physical chunks", function()
	World(function(Node, As, Flush)
		local member = Node("New Member-Realm", GUILD)
		local hub = Node("Hildryn Payne-Realm", "Olympus Hearth")
		As(member, member.deliver, "WHISPER", hub.c.me, "RY~")
		local owner, allowed, calls, completions = {}, true, 0, {}
		local physical, whisper = nil, member.c.Comm.SendBatch
		member.c.Comm.SendBatch = function(dist, pieces, key, target, urgent, done, options)
			if dist == "WHISPER" then physical = { msg = pieces[1], target = target, options = options } end
			return whisper(dist, pieces, key, target, urgent, done, options)
		end
		local payload = "X1~" .. string.rep("x", 252) -- valid 255-byte word, RL envelope needs two parts
		local opts = { owner = owner, key = "bounded-capability", permit = function(o, key, dist, target, msg)
			calls = calls + 1
			eq(o, owner); eq(key, "bounded-capability"); eq(dist, "CHANNEL"); eq(target, nil); eq(msg, payload)
			return allowed
		end }
		local function Send()
			return As(member, member.c.Comm.Send, "CHANNEL", payload, nil, false, false,
				function(ok) completions[#completions + 1] = ok end, opts)
		end
		eq(Send(), true); eq(calls, 0, "the queued capability is checked at send time")
		assert(physical and physical.options.permit)
		eq(physical.options.key, "bounded-capability")
		local permit = physical.options.permit
		eq(permit({}, "bounded-capability", "WHISPER", physical.target, physical.msg), false)
		eq(permit(owner, "wrong-key", "WHISPER", physical.target, physical.msg), false)
		eq(permit(owner, "bounded-capability", "WHISPER", "Max Ran", physical.msg), false, "even another signed relay is outside this job")
		eq(permit(owner, "bounded-capability", "WHISPER", physical.target, "RL~P~X1~forged"), false)
		eq(permit(owner, "bounded-capability", "GUILD", physical.target, physical.msg), false)
		Flush()
		-- Pump checks an active batch before choosing it, and SendJob checks its
		-- actual next piece again (Comm.lua). Two wire pieces therefore give 3 checks.
		eq(completions[1], true); eq(calls, 3, "both pieces and the active-batch preflight retain the logical capability")
		eq(hub.c.Relay.Stats().delivered, 1)
		local before = #member.sent
		eq(Send(), true); allowed = false; Flush()
		eq(completions[2], false); eq(#member.sent, before, "revocation before pump sends no piece")
		allowed = true
		eq(Send(), true); eq(As(member, member.c.Comm.Cancel, owner), 2, "Cancel returns unsent pieces, not transfers"); Flush()
		eq(completions[3], false); eq(#member.sent, before, "the original owner still cancels the transfer")
		eq(Send(), true)
		member.c.rdb.council.names["hildryn payne"] = nil
		Flush(); eq(completions[4], false); eq(#member.sent, before, "a relay removed from the signed list cannot receive it")
	end)
end)

test("verification recovery: self-relay dispatch checks the original capability before forwarding", function()
	World(function(Node, As, Flush)
		local hub = Node("Hildryn Payne-Realm", "Olympus Hearth")
		As(hub, hub.deliver, "WHISPER", "Reporter One-Realm", "RL~P~RR~Olympus Reporters")
		local calls, outcome, owner = 0, nil, {}
		for _, logged in ipairs({ false, true }) do
		eq(As(hub, hub.c.Comm.Send, "CHANNEL", "X1~guarded", nil, false, logged,
			function(ok) outcome = ok end, { owner = owner, key = "self-check", permit = function(o, key, dist, target, msg)
				calls = calls + 1
				eq(o, owner); eq(key, "self-check"); eq(dist, "CHANNEL"); eq(target, nil); eq(msg, "X1~guarded")
				return false
			end }), true)
		Flush(); eq(outcome, false); eq(hub.c.Relay.Stats().forwarded, 0)
		end
		eq(calls, 2); eq(#hub.sent, 0, "neither self dispatch nor immediate logged guild copy bypasses the guard")
	end)
end)

test("verification recovery: waiting for a relay cannot bypass a revoked capability through channel fallback", function()
	World(function(Node, As, Flush)
		local member = Node("New Member-Realm", GUILD)
		local owner, allowed, carried, results = {}, false, 0, {}
		member.c.ChatHall = { Carry = function() carried = carried + 1; return true end }
		local function Send()
			return As(member, member.c.Comm.Send, "CHANNEL", "X1~held-capability", nil, false, false,
				function(ok) results[#results + 1] = ok end,
				{ owner = owner, key = "waiting", permit = function(o, key, dist, target, body)
					eq(o, owner); eq(key, "waiting"); eq(dist, "CHANNEL"); eq(target, nil); eq(body, "X1~held-capability")
					return allowed
				end })
		end
		eq(Send(), true); Flush()
		eq(results[1], false); eq(carried, 0); eq(member.c.Relay.Stats().pending, 0)
		allowed = true
		eq(Send(), true); eq(carried, 1); eq(member.c.Relay.Stats().pending, 1)
		allowed = false
		As(member, member.deliver, "WHISPER", "Hildryn Payne-Realm", "RY~"); Flush()
		eq(results[2], false); eq(carried, 1)
		eq(#member.sentOf("RL~P~X1~held-capability"), 0, "flush checks revocation again before the actual whisper")
	end)
end)

test("verification recovery: snapshot reservation rejects untrusted, malformed, oversized, repeated and mismatched fragments", function()
	World(function(Node, As, Flush, Advance)
		local hub = Node("Hildryn Payne-Realm", "Olympus Hearth")
		As(hub, hub.deliver, "WHISPER", "Reporter One-Realm", "RL~P~RR~Olympus Reporters")
		local function Send(origin, body) As(hub, hub.deliver, "WHISPER", origin, "RL~P~" .. body) end
		for i = 1, 4 do Send("Ordinary Member-Realm", "X1~" .. i) end
		Flush(); eq(hub.c.Relay.Stats().forwarded, 4)
		local head = "GV~1~S~" .. T0 .. "~"
		local first = head .. string.rep("x", ns.Codec.CHUNK - #head)
		local middle = string.rep("x", ns.Codec.CHUNK)
		Send("Ordinary Member-Realm", "Cu:1:3:" .. first)
		Send(HC, "Cm:1:3:" .. string.rep("x", ns.Codec.CHUNK))
		Send(HC, "Co:1:35:" .. first)
		Send(HC, "Cs:1:3:" .. first .. "x")
		Send(HC, "Cp:2:3:" .. middle)
		Flush(); eq(hub.c.Relay.Stats().forwarded, 4, "no unreserved fragment bypasses the exhausted trickle")
		-- (#76) A reserved snapshot is held until every piece is here, then goes to each reporter
		-- as one whole batch: `forwarded` counts that batch once, not each piece as it came.
		Send(HC, "Cg:1:3:" .. first); Flush()
		eq(hub.c.Relay.Stats().forwarded, 4, "a reserved piece waits for the rest of its set")
		Send(HC, "Cg:1:3:" .. first)
		Send(HC, "Cg:2:4:" .. middle)
		Send(HC, "Ch:1:3:" .. first)
		Flush(); eq(hub.c.Relay.Stats().forwarded, 4, "one id/total per origin; repeats do not reserve twice")
		Send(HC, "Cg:2:3:" .. middle); Send(HC, "Cg:3:3:tail"); Flush()
		eq(hub.c.Relay.Stats().forwarded, 5, "every admitted fragment can finish: the whole set, one batch")
		Advance(61)
		-- Exhaust the ordinary allowance again, then a new snapshot can reserve.
		for i = 5, 8 do Send("Ordinary Member-Realm", "X1~" .. i) end
		Send(HC, "Cn:1:3:" .. first); Flush()
		eq(hub.c.Relay.Stats().forwarded, 9, "a new transfer is eligible after the fixed window (its set still waits for the rest)")
	end)
end)

test("verification recovery: a larger trusted snapshot reaches reporters as a whole after crossing relays", function()
	World(function(Node, As, Flush, Advance)
		local member = Node("New Member-Realm", GUILD)
		local hub = Node("Hildryn Payne-Realm", "Olympus Hearth")
		local verifier = Node(HC, "Olympus Crown")
		for i = 1, 18 do eq(As(verifier, verifier.c.Verify.Approve, "Olympus Recovery " .. i, MASTER), true) end
		eq(As(verifier, verifier.c.Verify.Approve, GUILD, MASTER), true)
		Advance(3601)
		As(hub, hub.deliver, "WHISPER", HC, "RY~")
		As(hub, hub.deliver, "WHISPER", member.c.me, "RL~P~RR~" .. GUILD)
		As(member, member.deliver, "WHISPER", hub.c.me, "RY~")
		As(member, member.c.Verify.Ask); Flush(); Advance(9)
		eq(As(member, member.c.Verify.Status, GUILD), "verified", "all fragments are needed for a valid snapshot")
		eq(member.c.Verify.Digest(), 19, "every original approval is present")
		eq(member.c.rdb.verify.list[ns.Fold(GUILD)].at, T0)
	end)
end)

test("verification recovery: cross-relay asks are bounded, never sent to reporters or forwarded a second time", function()
	World(function(Node, As, Flush, Advance)
		local hub = Node("Hildryn Payne-Realm", "Olympus Hearth")
		local other = Node(HC, "Olympus Crown")
		As(hub, hub.deliver, "WHISPER", HC, "RY~")
		As(hub, hub.deliver, "WHISPER", "Reporter One-Realm", "RL~P~RR~Olympus Reporters")
		As(other, other.deliver, "WHISPER", "Reporter Two-Realm", "RL~P~RR~Olympus More")
		for i = 1, 8 do
			As(hub, hub.deliver, "WHISPER", "Asker " .. i .. "-Realm", "RL~P~GV~1~Q~0~0~0")
		end
		Flush()
		eq(#hub.sentOf("RX~P~"), 1, "one across request per cadence, not one per client")
		eq(#hub.sentOf("RM~"), 0); eq(#other.sentOf("RM~"), 0)
		eq(#other.sentOf("RX~"), 0, "incoming RX asks never circulate")
		As(hub, hub.c.Verify.Ask); Flush()
		eq(#hub.sentOf("RM~"), 0, "the relay's own ask stays off guild reporters too")
		Advance(301)
		As(hub, hub.deliver, "WHISPER", "Asker 1-Realm", "RL~P~GV~1~Q~0~0~0")
		Flush()
		eq(#hub.sentOf("RX~P~"), 2, "the same inventory can recover again after dedupe expiry")
		Advance(301)
		As(hub, hub.deliver, "WHISPER", "Asker 1-Realm", "RL~P~GV~1~Q~not-a-query")
		Flush(); eq(#hub.sentOf("RX~P~"), 2, "malformed asks never cross")
	end)
end)
