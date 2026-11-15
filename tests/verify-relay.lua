-- Real Comm + Relay + Verify path; only Blizzard's wire/timers are simulated.
local ns, test, eq, RelayWorld, ADDON_DIR = ...
local T0 = 1800000000
local GUILD, REVOKED = "Olympus Vanguard", "Olympus Embers"
local MASTER, HC = "Guild Master-Realm", "Max Ran-Realm"
local FIXTURES = (ADDON_DIR:match("^(.*)Olympus/$") or "./") .. "tests/fixtures/"

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
		GetGuildInfo = function() return n.guild, n.rank == 0 and "Guild Master" or "Member", n.rank or 3 end
		return f(...)
	end
	-- opts (1.6.0, the guild's hand-over): rank (0: its guild master), old (a client still on 1.5.9: its
	-- Relay.lua and Verify.lua as that release ships them, tests/fixtures/, and a hello naming 1.5.9).
	local function Node(name, guild, opts)
		opts = opts or {}
		local c, deliver, sent, _, pump, sentOf = RelayWorld(name, guild, opts.old and (FIXTURES .. "relay-1.5.9.lua") or nil)
		local n = { c = c, deliver = deliver, sent = sent, pump = pump, sentOf = sentOf,
			guild = guild, rank = opts.rank, chat = C_ChatInfo, cursor = 0 }
		if opts.old then c.VERSION = "1.5.9" end
		c.clock, c.realm, c.RealmPages = now, "Realm", {}
		-- (1.5.4) T0 is a date past the code's presentation deadline: this world runs before it (its
		-- registrations are handed to the relays by hand, bare, ahead of any member's presentation).
		-- The presentation and the deadline have their own suite (tests/relay-admit.lua).
		c.Relay.PRESENT_REQUIRED_AT = T0 + 30 * 86400
		c.rdb.guilds = { [GUILD] = { leader = MASTER, realm = "Realm" },
			[REVOKED] = { leader = MASTER, realm = "Realm" } }
		c.IsHighCouncillor = function(who) return c.FullName(who) == HC end
		c.IsKingCharacter = function() return false end
		c.Workshop = { IsAuthorName = function() return false end }
		c.Fire, c.On = function() end, function() end
		c.UI = { Refresh = function() end }
		c.After = function(delay, _, f) timers[#timers + 1] = { at = now + delay, n = n, f = f } end
		c.Every = function() end
		c.L = setmetatable({}, { __index = ns.L })
		As(n, function()
			assert(loadfile(ADDON_DIR .. "Locales/VerifyText.lua"))("Olympus", c)
			assert(loadfile(opts.old and (FIXTURES .. "verify-1.5.9.lua") or (ADDON_DIR .. "Verify.lua")))("Olympus", c)
		end)
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
	local ok, err = pcall(fn, Node, As, Flush, Advance, function() return now end)
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

test("verification recovery: the Watch resends an original approval across relays only to its own guild", function()
	World(function(Node, As, Flush, Advance)
		local member = Node("New Member-Realm", GUILD)
		local guildmate = Node("Guild Mate-Realm", GUILD)
		local other = Node("Other Member-Realm", REVOKED)
		local hub = Node("Hildryn Payne-Realm", "Olympus Hearth")
		local verifier = Node(HC, "Olympus Crown")
		As(hub, hub.deliver, "WHISPER", member.c.me, "RL~P~RR~" .. GUILD)
		As(hub, hub.deliver, "WHISPER", other.c.me, "RL~P~RR~" .. REVOKED)
		As(verifier, verifier.c.Verify.Observe)
		local decision = ("GV~1~A~%d~%s~%s"):format(T0, GUILD, MASTER)
		eq(As(verifier, verifier.c.Verify.Handle, "CHANNEL", HC, decision), true)
		local start = As(verifier, verifier.c.Verify.Start, GUILD)
		Advance(1)
		for i = 1, hub.c.Relay.REPORTER_RATE do
			As(hub, hub.deliver, "WHISPER", "Ordinary Member-Realm", "RL~P~X1~" .. i)
		end
		Flush()
		As(hub, hub.deliver, "WHISPER", "Ordinary Member-Realm", "RL~P~X1~spent")
		Flush()
		eq(#hub.sentOf("RM~P~Ordinary Member-Realm~X1~spent"), 0, "the ordinary allowance is spent")
		assert(As(member, member.c.Verify.Status, GUILD) ~= "verified")
		eq(As(verifier, verifier.c.Verify.ResendApproval, GUILD), true)
		Flush()
		local status, info = As(member, member.c.Verify.Status, GUILD)
		eq(status, "verified"); eq(info.entry.at, T0); eq(info.entry.by, HC); eq(info.entry.gm, MASTER)
		eq(As(guildmate, guildmate.c.Verify.Status, GUILD), "verified", "the reporter handed it to the guild")
		eq(As(verifier, verifier.c.Verify.Start, GUILD), start)
		assert(As(other, other.c.Verify.Status, GUILD) ~= "verified", "the other guild did not receive this row")
		eq(As(verifier, verifier.c.Verify.ResendApproval, GUILD), false, "clicking repeatedly does not resend")

		-- The sender still thinks the approval holds, but the receiving relay knows a newer revocation.
		member.c.rdb.verify.list[ns.Fold(GUILD)] = nil
		eq(As(hub, hub.c.Verify.Handle, "CHANNEL", HC, ("GV~1~R~%d~%s~%s"):format(T0 + 1, GUILD, MASTER)), true)
		Advance(verifier.c.Verify.RESEND_GAP + 1)
		eq(As(verifier, verifier.c.Verify.ResendApproval, GUILD), true)
		Flush()
		assert(As(member, member.c.Verify.Status, GUILD) ~= "verified", "a relay with a revocation does not forward a stale approval")
		local _, relay = As(hub, hub.c.Verify.Status, GUILD)
		eq(relay.revoked.at, T0 + 1)
	end)
end)

test("verification recovery: the Watch polls one reporter for a fresh native guild master without updating authority", function()
	World(function(Node, As, Flush, Advance)
		local reporter = Node("Town Herald-Realm", GUILD)
		local stranger = Node("Unknown-Realm", GUILD)
		local verifier = Node(HC, "Olympus Crown")
		for _, n in ipairs({ reporter, stranger, verifier }) do n.c.group, n.c.faction = "Realm", "Alliance" end
		local row = verifier.c.rdb.guilds[GUILD]
		row.t, row.reporterFull = T0, reporter.c.me
		local scans, fresh = 0, true
		local roster = { guild = GUILD, generation = 3, byName = { [MASTER] = 0 } }
		roster.Fresh = function() if fresh then return roster end end
		roster.RequestScan = function(force) eq(force, true); scans = scans + 1 end
		reporter.c.Roster = roster
		local printed = {}
		verifier.c.Print = function(text) printed[#printed + 1] = text end
		As(reporter, reporter.deliver, "WHISPER", stranger.c.me, "GV~1~M~1800000000-1~Alliance~" .. GUILD)
		As(reporter, reporter.deliver, "WHISPER", HC, "GV~1~M~1800000000-1~Horde~" .. GUILD)
		eq(scans, 0, "a non-verifier or wrong faction cannot request a roster scan")
		eq(As(verifier, verifier.c.Verify.PollGuild, GUILD), true)
		eq(As(verifier, verifier.c.Verify.PollGuild, GUILD), false, "only one pending poll")
		Flush()
		eq(scans, 1)
		eq(#verifier.sentOf("GV~1~M~"), 1, "the poll uses one private whisper")
		eq(verifier.sentOf("GV~1~M~")[1].target, "Town Herald")
		local response = "GV~1~N~1800000000-1~Alliance~" .. GUILD .. "~Wrong Master-Realm"
		As(verifier, verifier.deliver, "WHISPER", stranger.c.me, response)
		assert(not table.concat(printed, " "):find("Wrong Master", 1, true), "a matching request ID is insufficient")
		Advance(5)
		eq(#reporter.sentOf("GV~1~N~"), 0, "the earlier complete scan is insufficient")
		roster.generation, roster.byName = 4, { ["New Master-Realm"] = 0 }
		Advance(5)
		eq(#reporter.sentOf("GV~1~N~"), 1)
		assert(table.concat(printed, " "):find("New Master is the guild master reported by Town Herald", 1, true))
		eq(As(verifier, verifier.c.Verify.GuildMaster, GUILD), MASTER, "a poll does not replace stored authority")
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
		-- (1.5.4) No channel text while waiting for a relay at all: Forever blocked that timer send
		-- (ChatHall.lua says why). The held message is still checked again at the flush below.
		eq(Send(), true); eq(carried, 0); eq(member.c.Relay.Stats().pending, 1)
		allowed = false
		As(member, member.deliver, "WHISPER", "Hildryn Payne-Realm", "RY~"); Flush()
		eq(results[2], false); eq(carried, 0)
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
		-- (1.5.4) Asks cross as RW to every relay not left out (RX reached only relays that had
		-- answered our pings, which a relay never sends on Forever: tests/verify-mesh.lua).
		local function Asks() return #hub.sentOf("RW~P~Asker") end
		eq(Asks(), 1, "one across request per cadence, not one per client")
		local function ToReporter(n, name)
			local k = 0
			for _, p in ipairs(n.sent) do if p.msg:find("^RM~") and ns.ShortName(p.target or "") == ns.ShortName(name) then k = k + 1 end end
			return k
		end
		eq(#hub.sentOf("RM~"), 0); eq(ToReporter(other, "Reporter Two-Realm"), 0, "nor to the other relay's reporters")
		eq(#other.sentOf("RX~") + #other.sentOf("RW~P~Asker"), 0, "incoming asks never circulate")
		As(hub, hub.c.Verify.Ask); Flush()
		eq(#hub.sentOf("RM~"), 0, "the relay's own ask stays off guild reporters too")
		Advance(301)
		As(hub, hub.deliver, "WHISPER", "Asker 1-Realm", "RL~P~GV~1~Q~0~0~0")
		Flush()
		eq(Asks(), 2, "the same inventory can recover again after dedupe expiry")
		Advance(301)
		As(hub, hub.deliver, "WHISPER", "Asker 1-Realm", "RL~P~GV~1~Q~not-a-query")
		Flush(); eq(Asks(), 2, "malformed asks never cross")
	end)
end)

---------------------------------------------------------------------------
-- (1.6.0) The guild's hand-over (Verify.lua): a guild master who was away when his guild was approved,
-- or on a new computer, gets the approval his guildmates hold from them, with no verifier online (a
-- guild master's report: "GM verification pending" on his old PC and a new laptop, while his
-- guildmates' Census showed the guild verified). A guild master still on 1.5.9 too: his client reads
-- the Watch's one-row resend that a guildmate hands the guild (hop 3), as tests/fixtures/ ship 1.5.9.
---------------------------------------------------------------------------

-- A node whose pop-ups, chat lines and log lines (/oly bug's) are kept (n.copies, n.printed, n.logs), on
-- a realm group with a verifier (Verify.VerifierHere: the signed council's names), so an unverified
-- guild master is told at login.
local function Ready(n)
	n.copies, n.printed, n.logs = {}, {}, {}
	n.c.UI.ShowCopy = function(title, text, _, opts) n.copies[#n.copies + 1] = { title = title, text = text, opts = opts } return {} end
	n.c.Print = function(m) n.printed[#n.printed + 1] = tostring(m) end
	n.c.Log = function(fmt, ...)
		local ok, msg = pcall(string.format, fmt, ...)
		n.logs[#n.logs + 1] = ok and msg or tostring(fmt)
	end
	n.c.Workshop.CouncilNames = function() return { "Max Ran" } end
	return n
end

local function Find(list, needle)
	for _, s in ipairs(list) do if tostring(s):find(needle, 1, true) then return s end end
	return nil
end

-- HC's approval of GUILD with MASTER at `at`, as each node heard it then.
local function Approved(As, at, ...)
	for _, n in ipairs({ ... }) do
		eq(As(n, n.c.Verify.Handle, "CHANNEL", HC, ("GV~1~A~%d~%s~%s"):format(at, GUILD, MASTER)), true)
	end
end

-- `seconds` of play, `step` at a time: the timers and the wire (Advance), and every 60 s each node's
-- minute (Verify.Tick, which its ticker runs in game from the login on).
local function Play(Advance, As, nodes, seconds, step)
	step = step or 10
	local done = 0
	while done < seconds do
		Advance(step)
		done = done + step
		if done % 60 == 0 then for _, n in ipairs(nodes) do As(n, n.c.Verify.Tick) end end
	end
end

-- The guild hand-overs a node sent: an approval's one-row resend over GUILD, as hop 3 from its verifier.
local function HandOvers(n)
	local k = 0
	for _, p in ipairs(n.sent) do
		if p.dist == "GUILD" and p.msg:find("^RG~P~[^~]+~GV~1~S~%d+~A,%d+,[^,;~]+,[^,;~]+,[^,;~]+;$") then k = k + 1 end
	end
	return k
end

-- (The review of the hand-over) The answers with a newer revocation a node sent: one row, no final
-- semicolon, over GUILD as hop 3 from its verifier.
local function Revocations(n)
	local k = 0
	for _, p in ipairs(n.sent) do
		if p.dist == "GUILD" and p.msg:find("^RG~P~[^~]+~GV~1~S~%d+~R,%d+,[^,;~]+,[^,;~]+,[^,;~]+$") then k = k + 1 end
	end
	return k
end

-- HC's revocation of GUILD (approved with MASTER) at `at`, as each node heard it then.
local function Revoked(As, at, ...)
	for _, n in ipairs({ ... }) do
		eq(As(n, n.c.Verify.Handle, "CHANNEL", HC, ("GV~1~R~%d~%s~%s"):format(at, GUILD, MASTER)), true)
	end
end

-- Fails before 1.6.0: nobody but a verifier's client answers his ask, and none is online; he stays
-- pending (expected verified, got pending) and is shown "GM verification pending" two minutes in.
test("verify guild hand-over: a fresh-install guild master gets the approval his guildmate holds, no verifier online, before his notice", function()
	World(function(Node, As, Flush, Advance)
		local hub = Node("Hildryn Payne-Realm", "Olympus Hearth") -- (a signed relay that verifies nothing)
		local mate = Ready(Node("Guild Mate-Realm", GUILD))
		local master = Ready(Node(MASTER, GUILD, { rank = 0 }))
		-- A day ago HC approved the guild with its guild master, who was away; his guildmate heard it. He
		-- logs in on a new computer, nothing held, and HC is offline (no client of his here).
		Approved(As, T0, mate)
		Advance(86400)
		eq(master.c.rdb.verify, nil, "a fresh install holds no verification")
		As(master, master.deliver, "WHISPER", hub.c.me, "RY~") -- (his relay answered his ping: his own ask goes to it)
		As(mate, mate.c.Verify.Login)
		As(master, master.c.Verify.Login)
		Play(Advance, As, { mate, master }, 120) -- (his notice is due at his first minute past NOTICE_AFTER)
		local status, info = As(master, master.c.Verify.Status, GUILD)
		eq(status, "verified", "his guild handed him its approval")
		eq(info.entry.at, T0); eq(info.entry.by, HC, "the original approval and verifier: nothing approved anew")
		eq(info.entry.gm, MASTER)
		eq(#master.copies, 0, "no \"GM verification pending\" pop-up")
		assert(not Find(master.printed, "GM verification pending"), "nor its chat line")
		As(master, master.c.Verify.Slash, "status")
		assert(Find(master.printed, ("<%s> is verified: guild master Guild Master, approved by Max Ran"):format(GUILD)),
			"/oly verify status says verified")
		eq(master.c.Verify.Stats().guildAsked, 1, "he asked his guild once")
		assert(Find(mate.logs, "handed to the guild (asked)"), "an answer to his ask")
		eq(HandOvers(mate), 1, "one hand-over, over GUILD")
		eq(#mate.sentOf("RG~P~Max Ran~GV~1~S~"), 1, "named from its verifier, as hop 3 names an origin")
		eq(#mate.sentOf("RL~P~GV~1~S~"), 0, "nothing of it to a relay")
		eq(#hub.sentOf("RM~P~Max Ran~GV~1~S~"), 0, "nor from one")
	end)
end)

test("verify guild hand-over: a fresh-install member hearing it still asks for the whole store at its login's retry", function()
	World(function(Node, As, Flush, Advance)
		local hub = Node("Hildryn Payne-Realm", "Olympus Hearth")
		local mate = Ready(Node("Guild Mate-Realm", GUILD))
		local master = Ready(Node(MASTER, GUILD, { rank = 0 }))
		local cold = Ready(Node("Cold Member-Realm", GUILD)) -- (a new computer too, not the guild master)
		Approved(As, T0, mate)
		Advance(3600)
		for _, n in ipairs({ master, cold }) do As(n, n.deliver, "WHISPER", hub.c.me, "RY~") end
		for _, n in ipairs({ mate, master, cold }) do As(n, n.c.Verify.Login) end
		Play(Advance, As, { mate, master, cold }, 120)
		eq(As(cold, cold.c.Verify.Status, GUILD), "verified", "it took its guild's hand-over too")
		eq(#cold.sentOf("RL~P~GV~1~Q~"), 1, "its login's ask")
		Play(Advance, As, { mate, master, cold }, cold.c.Verify.STARTUP_RETRY + cold.c.Verify.STARTUP_SPREAD, 60)
		eq(#cold.sentOf("RL~P~GV~1~Q~"), 2, "one guild's row is no answer: the login's retry still asks for the whole store")
	end)
end)

test("verify guild hand-over: a guild master still on 1.5.9 is handed the approval at his login by a 1.6.0 guildmate", function()
	World(function(Node, As, Flush, Advance)
		local mate = Ready(Node("Guild Mate-Realm", GUILD))
		local master = Ready(Node(MASTER, GUILD, { rank = 0, old = true }))
		eq(master.c.Verify.GuildAsk, nil, "(1.5.9's Verify.lua)"); eq(master.c.Relay.ToOwnGuild, nil, "(and Relay.lua)")
		Approved(As, T0, mate)
		As(mate, mate.c.Verify.Login)
		Play(Advance, As, { mate }, mate.c.Verify.GUILD_LOGIN_GAP + 60, 60) -- (the guildmate hears the guild; its master is away)
		eq(HandOvers(mate), 0, "nothing while the guild master is away")
		-- He logs in: his hello (6 s after his login in game) names 1.5.9, a client that never asks its guild.
		As(master, master.c.Comm.Hello, true); Flush()
		As(master, master.c.Verify.Login)
		Play(Advance, As, { mate, master }, 120)
		local status, info = As(master, master.c.Verify.Status, GUILD)
		eq(status, "verified", "the 1.5.9 client takes its guild's hand-over")
		eq(info.entry.at, T0); eq(info.entry.by, HC)
		eq(#master.copies, 0, "no pop-up")
		As(master, master.c.Verify.Slash, "status")
		assert(Find(master.printed, ("<%s> is verified"):format(GUILD)), "/oly verify status (1.5.9's) says verified")
		eq(#master.sentOf("GV~1~G~"), 0, "1.5.9 asks no guild")
		eq(HandOvers(mate), 1)
		assert(Find(mate.logs, "handed to the guild (login)"), "at his login")
		-- A relog within GUILD_LOGIN_GAP is no login: his saved data kept what he had.
		Play(Advance, As, { mate, master }, 300, 60)
		As(master, master.c.Comm.Hello, true); Flush()
		Play(Advance, As, { mate, master }, 120)
		eq(HandOvers(mate), 1, "one hand-over for one login")
	end)
end)

-- The hellos' times are the guildmate's computer clock (Comm's), the hand-overs' the server's: a clock
-- set 20 minutes off took every hello for one heard long ago, and no login was ever seen.
test("verify guild hand-over: a guildmate whose computer clock is off still sees its 1.5.9 guild master's login", function()
	World(function(Node, As, Flush, Advance)
		local mate = Ready(Node("Guild Mate-Realm", GUILD))
		local master = Ready(Node(MASTER, GUILD, { rank = 0, old = true }))
		mate.c.Now = function() return mate.c.clock - 1200 end -- (its clock 20 minutes behind the server's)
		Approved(As, T0, mate)
		As(mate, mate.c.Verify.Login)
		Play(Advance, As, { mate }, mate.c.Verify.GUILD_LOGIN_GAP + 60, 60)
		As(master, master.c.Comm.Hello, true); Flush()
		As(master, master.c.Verify.Login)
		Play(Advance, As, { mate, master }, 120)
		eq(As(master, master.c.Verify.Status, GUILD), "verified")
		assert(Find(mate.logs, "handed to the guild (login)"), "at his login")
	end)
end)

test("verify guild hand-over: a verified 1.6.0 guild master's login costs his guild nothing: he asks only while not verified", function()
	World(function(Node, As, Flush, Advance)
		local mate = Ready(Node("Guild Mate-Realm", GUILD))
		local master = Ready(Node(MASTER, GUILD, { rank = 0 }))
		Approved(As, T0, mate, master)
		As(mate, mate.c.Verify.Login)
		Play(Advance, As, { mate }, mate.c.Verify.GUILD_LOGIN_GAP + 60, 60)
		As(master, master.c.Comm.Hello, true); Flush() -- (his hello names 1.6.0: he would ask himself)
		As(master, master.c.Verify.Login)
		Play(Advance, As, { mate, master }, 120)
		eq(As(master, master.c.Verify.Status, GUILD), "verified")
		eq(#master.sentOf("GV~1~G~"), 0, "no ask")
		eq(HandOvers(mate), 0, "no hand-over at his login")
		Play(Advance, As, { mate, master }, mate.c.Verify.GUILD_SHARE_EVERY, 60)
		eq(HandOvers(mate), 0, "nor once a turn")
	end)
end)

-- (The review of the hand-over) A guild master who logs in before the guildmate holding his approval: his
-- login's ask and its retry went before it came. Fails before: he asked nothing more for half an hour (this
-- world runs no half-hourly ask: never), expected 3 asks, got 2, and stayed pending.
test("verify guild hand-over: a guild master who logs in before his guildmates asks again when a 1.6.0 guildmate comes online", function()
	World(function(Node, As, Flush, Advance)
		local master = Ready(Node(MASTER, GUILD, { rank = 0 })) -- (alone online: a node hears the guild once made)
		Advance(3600)
		As(master, master.c.Verify.Login)
		Play(Advance, As, { master }, 360)
		eq(master.c.Verify.Stats().guildAsked, 2, "his login's ask and its retry, with nobody there to answer")
		eq(#master.copies, 1, "told once at his login: nobody held the approval then")
		-- A 1.5.9 guildmate comes online: one that never answers is no reason to ask.
		local old = Ready(Node("Old Mate-Realm", GUILD, { old = true }))
		As(old, old.c.Comm.Hello, true); Flush()
		Play(Advance, As, { master, old }, 60, 60)
		eq(master.c.Verify.Stats().guildAsked, 2, "a 1.5.9 guildmate's hello asks nothing")
		-- The guildmate holding the approval (HC's of a day before) logs in, a minute after that.
		local holder = Ready(Node("Guild Mate-Realm", GUILD))
		Approved(As, T0, holder)
		As(holder, holder.c.Verify.Login)
		As(holder, holder.c.Comm.Hello, true); Flush()
		Play(Advance, As, { master, holder, old }, 120, 60)
		eq(master.c.Verify.Stats().guildAsked, 2, "not within GUILD_ASK_GAP of his last ask (the retry)...")
		Play(Advance, As, { master, holder, old }, 120)
		eq(master.c.Verify.Stats().guildAsked, 3, "...then, the guildmate's first hello still counted: he asked his guild again")
		local status, info = As(master, master.c.Verify.Status, GUILD)
		eq(status, "verified", "his guildmate handed him the approval")
		eq(info.entry.at, T0); eq(info.entry.by, HC)
		eq(HandOvers(holder), 1); assert(Find(holder.logs, "handed to the guild (asked)"), "an answer to his ask")
		eq(#master.copies, 1, "no second pop-up")
		-- Verified, he asks nothing more, whoever comes online.
		local late = Ready(Node("Late Mate-Realm", GUILD))
		As(late, late.c.Comm.Hello, true); Flush()
		Play(Advance, As, { master, holder, old, late }, 300, 60)
		eq(master.c.Verify.Stats().guildAsked, 3)
	end)
end)

test("verify guild hand-over: a guild master nobody holds an approval for asks again as 1.6.0 guildmates come online, GUILD_ASK_GAP apart at most, once for each", function()
	World(function(Node, As, Flush, Advance, Now)
		local master = Ready(Node(MASTER, GUILD, { rank = 0 }))
		local V = master.c.Verify
		Advance(3600)
		As(master, V.Login)
		Play(Advance, As, { master }, 600, 60)
		eq(V.Stats().guildAsked, 2, "his login's ask and its retry")
		local times, last = {}, V.Stats().guildAsked
		local function Minute()
			Play(Advance, As, { master }, 60, 60)
			if V.Stats().guildAsked > last then times[#times + 1], last = Now(), V.Stats().guildAsked end
		end
		-- A 1.6.0 guildmate holding nothing comes online every minute for twenty minutes.
		local mates = {}
		for i = 1, 20 do
			mates[i] = Node(("Late Mate%02d-Realm"):format(i), GUILD)
			As(mates[i], mates[i].c.Comm.Hello, true); Flush()
			Minute()
		end
		for _ = 1, V.GUILD_ASK_GAP / 60 do Minute() end
		assert(#times >= 4, "he asked again as they came: " .. #times)
		for i = 2, #times do assert(times[i] - times[i - 1] >= V.GUILD_ASK_GAP, "asks GUILD_ASK_GAP apart at most") end
		-- Their hellos again, each guildmate heard already: no ask.
		local before = V.Stats().guildAsked
		for minute = 1, 12 do
			Play(Advance, As, { master }, 60, 60)
			if minute == 10 then for _, m in ipairs(mates) do As(m, m.c.Comm.Hello, true) end Flush() end
		end
		eq(V.Stats().guildAsked, before, "a guildmate heard already is no reason to ask again")
	end)
end)

test("verify guild hand-over: a guild master whose guildmates are all on 1.5.9 falls back to a verifier's answer, as before", function()
	World(function(Node, As, Flush, Advance)
		local hub = Node("Hildryn Payne-Realm", "Olympus Hearth")
		local one = Ready(Node("Guild Mate-Realm", GUILD, { old = true }))
		local two = Ready(Node("Second Mate-Realm", GUILD, { old = true }))
		local master = Ready(Node(MASTER, GUILD, { rank = 0 }))
		eq(one.c.Verify.HandleGuildAsk, nil, "(1.5.9's Verify.lua)")
		Approved(As, T0, one, two)
		Advance(3600)
		As(master, master.deliver, "WHISPER", hub.c.me, "RY~")
		As(one, one.c.Verify.Login); As(two, two.c.Verify.Login)
		As(master, master.c.Verify.Login)
		Play(Advance, As, { master, one, two }, 120)
		eq(#master.sentOf("GV~1~G~"), 1, "he asked his guild")
		eq(HandOvers(one) + HandOvers(two), 0, "a 1.5.9 guildmate never answers it")
		assert(As(master, master.c.Verify.Status, GUILD) ~= "verified", "no verifier online: still pending, as before")
		eq(#master.copies, 1, "and told so at login, as before")
		-- A verifier comes online: the guild master's next ask (the login's retry) is answered, as before.
		local verifier = Ready(Node(HC, "Olympus Crown"))
		verifier.c.rdb.guilds[GUILD] = { leader = MASTER, realm = "Realm" }
		Approved(As, T0, verifier)
		As(hub, hub.deliver, "WHISPER", HC, "RY~")
		Play(Advance, As, { master, one, two, verifier }, 600)
		eq(As(master, master.c.Verify.Status, GUILD), "verified", "a verifier's answer, today's path")
		eq(master.c.rdb.verify.list[ns.Fold(GUILD)].by, HC)
		eq(HandOvers(one) + HandOvers(two), 0)
	end)
end)

test("verify guild hand-over: a guildmate hands nothing over when its census names another guild master, nor to an ask from anyone else", function()
	World(function(Node, As, Flush, Advance)
		local mate = Ready(Node("Guild Mate-Realm", GUILD))
		local master = Ready(Node(MASTER, GUILD, { rank = 0 }))
		Approved(As, T0, mate)
		mate.c.rdb.guilds[GUILD].leader = "Other Lord" -- (its own roster names another guild master now)
		Advance(3600)
		As(mate, mate.c.Verify.Login); As(master, master.c.Verify.Login)
		Play(Advance, As, { mate, master }, 120)
		eq(#master.sentOf("GV~1~G~"), 1, "the guild master asked")
		eq(HandOvers(mate), 0, "an approval naming a guild master its census does not see stays home")
		assert(As(master, master.c.Verify.Status, GUILD) ~= "verified")
		-- Its census names no guild master (its roster not read yet): it cannot tell, it hands nothing over.
		mate.c.rdb.guilds[GUILD].leader = nil
		As(mate, mate.deliver, "GUILD", MASTER, ("GV~1~G~%s~0"):format(GUILD))
		Play(Advance, As, { mate }, 60)
		eq(HandOvers(mate), 0, "no guild master seen, no hand-over")
		-- Its census names him again: an ask from a guildmate who is not the guild master is not answered...
		mate.c.rdb.guilds[GUILD].leader = "Guild Master"
		As(mate, mate.deliver, "GUILD", "Pretender Mate-Realm", ("GV~1~G~%s~0"):format(GUILD))
		Play(Advance, As, { mate }, 60)
		eq(HandOvers(mate), 0, "only the guild master it sees asks")
		-- ...nor one naming another guild, nor one that holds a word as new...
		As(mate, mate.deliver, "GUILD", MASTER, ("GV~1~G~%s~0"):format(REVOKED))
		As(mate, mate.deliver, "GUILD", MASTER, ("GV~1~G~%s~%d"):format(GUILD, T0))
		Play(Advance, As, { mate }, 60)
		eq(HandOvers(mate), 0)
		-- ...his own ask is.
		As(mate, mate.deliver, "GUILD", MASTER, ("GV~1~G~%s~0"):format(GUILD))
		Play(Advance, As, { mate, master }, 60)
		eq(HandOvers(mate), 1)
		eq(As(master, master.c.Verify.Status, GUILD), "verified")
	end)
end)

test("verify guild hand-over: a newer revocation wins: a guildmate holding one hands nothing over, a guild master holding one refuses a stale approval", function()
	World(function(Node, As, Flush, Advance, Now)
		local mate = Ready(Node("Guild Mate-Realm", GUILD))
		local master = Ready(Node(MASTER, GUILD, { rank = 0 }))
		local revoked = ("GV~1~R~%d~%s~%s"):format(T0 + 60, GUILD, MASTER)
		Approved(As, T0, mate)
		eq(As(mate, mate.c.Verify.Handle, "CHANNEL", HC, revoked), true)
		Advance(3600)
		As(mate, mate.c.Verify.Login); As(master, master.c.Verify.Login)
		Play(Advance, As, { mate, master }, 120)
		eq(#master.sentOf("GV~1~G~"), 1)
		eq(HandOvers(mate), 0, "a guildmate whose newest word is a revocation hands over nothing")
		-- (The review of the hand-over) It answers his ask with the revocation instead: he holds it now.
		eq(Revocations(mate), 1, "its answer is the revocation")
		local status, info = As(master, master.c.Verify.Status, GUILD)
		assert(status ~= "verified")
		eq(info.revoked and info.revoked.at, T0 + 60, "the guild master holds the revocation, from his guildmate")
		-- A guildmate that missed it still holds the approval.
		local stale = Ready(Node("Stale Mate-Realm", GUILD))
		Approved(As, T0, stale)
		As(stale, stale.deliver, "GUILD", MASTER, ("GV~1~G~%s~%d"):format(GUILD, T0 + 60))
		Play(Advance, As, { stale }, 60)
		eq(HandOvers(stale), 0, "his ask names the revocation he holds: nothing older answers it")
		-- A stale hand-over all the same (one the guildmate's client would make): refused.
		local row = ("RG~P~Max Ran~GV~1~S~%d~A,%d,%s,Guild Master,Max Ran;"):format(Now(), T0, GUILD)
		local delivered = master.c.Relay.Stats().delivered
		As(master, master.deliver, "GUILD", stale.c.me, row)
		eq(master.c.Relay.Stats().delivered, delivered + 1, "it reached his Verify (hop 3), not lost on the way")
		status, info = As(master, master.c.Verify.Status, GUILD)
		assert(status ~= "verified", "the newer revocation stands")
		eq(info.revoked.at, T0 + 60)
	end)
end)

-- (The review of the hand-over.) A guildmate that missed a revocation still holds the approval it revoked,
-- and hands that over. Fails before: nothing answered it, a guild master on a fresh install took the revoked
-- approval (expected the revocation, got verified), and so did a fresh guildmate, which handed it on later.
test("verify guild hand-over: a stale hand-over is answered with the newer revocation: a fresh 1.6.0 guild master and a fresh guildmate end revoked", function()
	World(function(Node, As, Flush, Advance)
		local stale = Ready(Node("Stale Mate-Realm", GUILD)) -- (away when HC revoked the approval)
		local aware = Ready(Node("Aware Mate-Realm", GUILD))
		local fresh = Ready(Node("Fresh Mate-Realm", GUILD)) -- (a new computer)
		local master = Ready(Node(MASTER, GUILD, { rank = 0 })) -- (a new computer too)
		local all = { stale, aware, fresh, master }
		Approved(As, T0, stale, aware)
		Revoked(As, T0 + 60, aware)
		Advance(3600)
		for _, n in ipairs(all) do As(n, n.c.Verify.Login) end
		Play(Advance, As, all, 120)
		for _, n in ipairs({ master, fresh, stale }) do
			local status, info = As(n, n.c.Verify.Status, GUILD)
			assert(status ~= "verified", n.c.me .. " keeps the revoked approval")
			eq(info.revoked and info.revoked.at, T0 + 60, n.c.me .. " holds the revocation")
			eq(info.revoked.by, HC, "its original verifier")
			eq(info.revoked.gm, MASTER)
		end
		eq(master.c.Verify.Stats().guildAsked, 1, "the guild master asked his guild")
		eq(HandOvers(stale), 1, "the guildmate that missed the revocation handed the old approval over")
		eq(Revocations(aware), 1, "the guildmate holding the revocation answered with it")
		eq(#aware.sentOf("RG~P~Max Ran~GV~1~S~"), 1, "named from its verifier, as hop 3 names an origin")
		eq(#aware.sentOf("RL~P~GV~1~S~"), 0, "nothing of it to a relay")
		-- One guild's word alone is no answer to the fresh guildmate's own ask: its login's retry still asks.
		Play(Advance, As, all, fresh.c.Verify.STARTUP_RETRY + fresh.c.Verify.STARTUP_SPREAD, 60)
		eq(fresh.c.Verify.Stats().asked, 2, "the login's retry asked for the whole store")
		-- The stale guildmate gone, the guild master asks again (naming the revocation he holds) and the
		-- fresh guildmate hears a guildmate's ask that holds nothing: the old approval is handed on by nobody.
		stale.guild = "Olympus Elsewhere"
		Play(Advance, As, all, master.c.Verify.GUILD_WINDOW, 60)
		eq(As(master, master.c.Verify.GuildAsk), true)
		As(fresh, fresh.deliver, "GUILD", MASTER, ("GV~1~G~%s~0"):format(GUILD))
		Play(Advance, As, all, 60)
		eq(HandOvers(fresh) + HandOvers(aware), 0, "nobody hands the revoked approval on")
		assert(As(master, master.c.Verify.Status, GUILD) ~= "verified")
		assert(As(fresh, fresh.c.Verify.Status, GUILD) ~= "verified")
	end)
end)

-- The same at a 1.5.9 guild master's login (handed by the stale guildmate, unasked), his client and a fresh
-- 1.5.9 guildmate's reading the answer as any snapshot's row. Fails before: he took the revoked approval.
test("verify guild hand-over: a stale hand-over at a 1.5.9 guild master's login is answered with the newer revocation: he and a fresh 1.5.9 guildmate end revoked", function()
	World(function(Node, As, Flush, Advance)
		local stale = Ready(Node("Stale Mate-Realm", GUILD))
		local aware = Ready(Node("Aware Mate-Realm", GUILD))
		local fresh = Ready(Node("Fresh Mate-Realm", GUILD, { old = true }))
		local master = Ready(Node(MASTER, GUILD, { rank = 0, old = true }))
		Approved(As, T0, stale, aware)
		Revoked(As, T0 + 60, aware)
		for _, n in ipairs({ stale, aware }) do As(n, n.c.Verify.Login) end
		Play(Advance, As, { stale, aware }, stale.c.Verify.GUILD_LOGIN_GAP + 60, 60)
		As(fresh, fresh.c.Verify.Login)
		As(master, master.c.Comm.Hello, true); Flush()
		As(master, master.c.Verify.Login)
		Play(Advance, As, { stale, aware, fresh, master }, 120)
		for _, n in ipairs({ master, fresh, stale }) do
			local status, info = As(n, n.c.Verify.Status, GUILD)
			assert(status ~= "verified", n.c.me .. " keeps the revoked approval")
			eq(info.revoked and info.revoked.at, T0 + 60, n.c.me .. " holds the revocation")
		end
		eq(HandOvers(stale), 1); assert(Find(stale.logs, "handed to the guild (login)"), "at his login")
		eq(Revocations(aware), 1)
		assert(Find(aware.logs, ("<%s>'s revocation (%s, %d) handed to the guild (stale)"):format(GUILD, HC, T0 + 60)),
			"an answer to the stale hand-over")
	end)
end)

test("verify guild hand-over: a guild answers a stale hand-over once, and again for another one heard within GUILD_WINDOW", function()
	World(function(Node, As, Flush, Advance, Now)
		local master = Ready(Node(MASTER, GUILD, { rank = 0 }))
		local aware, all = {}, { master }
		for i = 1, 8 do
			aware[i] = Ready(Node(("Aware Mate%02d-Realm"):format(i), GUILD))
			all[#all + 1] = aware[i]
		end
		local stale = Ready(Node("Stale Mate-Realm", GUILD))
		all[#all + 1] = stale
		local function Total() local k = 0 for _, n in ipairs(all) do k = k + Revocations(n) end return k end
		Approved(As, T0, stale, unpack(aware))
		Revoked(As, T0 + 60, unpack(aware))
		Advance(3600)
		-- Everyone logs in at once and hears his ask (each draws the same wait here: the send's guard
		-- alone keeps the answer to one, and the stale guildmate, hearing it first, gives its own up).
		for _, n in ipairs(all) do As(n, n.c.Verify.Login) end
		Play(Advance, As, all, 120)
		local _, info = As(master, master.c.Verify.Status, GUILD)
		eq(info.revoked and info.revoked.at, T0 + 60, "the guild master holds the revocation")
		eq(Total(), 1, "one answer for the whole guild")
		eq(HandOvers(stale), 0, "the stale guildmate heard the revocation before its turn: it handed nothing over")
		-- Another guildmate that missed it (just logged in) hands the old approval over within GUILD_WINDOW
		-- of that answer: answered too, once.
		local row = ("RG~P~Max Ran~GV~1~S~%d~A,%d,%s,Guild Master,Max Ran;"):format(Now(), T0, GUILD)
		for _, n in ipairs(all) do As(n, n.deliver, "GUILD", "Second Stale-Realm", row) end
		Play(Advance, As, all, 60)
		eq(Total(), 2, "GUILD_WINDOW, which the stale hand-over set, does not hold the answer back")
		assert(As(master, master.c.Verify.Status, GUILD) ~= "verified")
		-- A hand-over as new as the revocation's second is stale too (a revocation stands over an approval
		-- of the same second); a newer approval is no stale one, and nobody answers it.
		Play(Advance, As, all, 60)
		row = ("RG~P~Max Ran~GV~1~S~%d~A,%d,%s,Guild Master,Max Ran;"):format(Now(), T0 + 60, GUILD)
		for _, n in ipairs(all) do As(n, n.deliver, "GUILD", "Second Stale-Realm", row) end
		Play(Advance, As, all, 60)
		eq(Total(), 3)
		row = ("RG~P~Max Ran~GV~1~S~%d~A,%d,%s,Guild Master,Max Ran;"):format(Now(), T0 + 120, GUILD)
		for _, n in ipairs(all) do As(n, n.deliver, "GUILD", "New Approval-Realm", row) end
		Play(Advance, As, all, 60)
		eq(Total(), 3, "a newer approval is taken, not answered")
		eq(As(master, master.c.Verify.Status, GUILD), "verified")
	end)
end)

-- Fails before 1.6.0 (hop 3 took an approval's resend for any guild): another guild's approval verified.
test("verify guild hand-over: a hand-over naming another guild is refused, and a member of another guild never answers", function()
	World(function(Node, As, Flush, Advance, Now)
		local mate = Ready(Node("Guild Mate-Realm", GUILD))
		local outsider = Ready(Node("Far Away-Realm", REVOKED)) -- (another guild's member, holding GUILD's approval)
		local master = Ready(Node(MASTER, GUILD, { rank = 0 }))
		Approved(As, T0, outsider)
		-- A guildmate's client hands its guild another guild's approval (REVOKED's census names Guild
		-- Master too): no guildmate takes it.
		local forged = ("RG~P~Max Ran~GV~1~S~%d~A,%d,%s,Guild Master,Max Ran;"):format(Now(), T0, REVOKED)
		As(mate, mate.deliver, "GUILD", "Forger Mate-Realm", forged)
		As(master, master.deliver, "GUILD", "Forger Mate-Realm", forged)
		assert(As(mate, mate.c.Verify.Status, REVOKED) ~= "verified", "another guild's approval is not taken over GUILD")
		assert(As(master, master.c.Verify.Status, REVOKED) ~= "verified")
		eq(mate.c.Relay.Stats().dropped, 1)
		-- The guild master asks: the member of another guild neither hears it (GUILD) nor answers a copy, nor
		-- hands GUILD's approval to its own guild.
		As(outsider, outsider.c.Verify.Login); As(master, master.c.Verify.Login)
		Play(Advance, As, { outsider, master }, 120)
		As(outsider, outsider.deliver, "GUILD", MASTER, ("GV~1~G~%s~0"):format(GUILD))
		Play(Advance, As, { outsider, master }, 60)
		eq(HandOvers(outsider), 0)
		assert(As(master, master.c.Verify.Status, GUILD) ~= "verified")
	end)
end)

test("verify guild hand-over: a guild logging in all at once makes one hand-over, and one each GUILD_WINDOW at most", function()
	World(function(Node, As, Flush, Advance)
		local master = Ready(Node(MASTER, GUILD, { rank = 0 }))
		local mates, all = {}, { master }
		for i = 1, 24 do
			mates[i] = Ready(Node(("Guild Mate%02d-Realm"):format(i), GUILD))
			all[#all + 1] = mates[i]
		end
		local function Total() local k = 0 for _, m in ipairs(mates) do k = k + HandOvers(m) end return k end
		local function Asked() for _, m in ipairs(mates) do As(m, m.deliver, "GUILD", MASTER, ("GV~1~G~%s~0"):format(GUILD)) end end
		Approved(As, T0, unpack(mates))
		Advance(3600)
		-- A realm restart: everyone logs in at once, every guildmate holds the approval, all hear his ask
		-- (each draws the same wait here: the send's guard alone keeps it to one).
		for _, m in ipairs(mates) do As(m, m.c.Verify.Login) end
		As(master, master.c.Verify.Login)
		Play(Advance, As, all, 120)
		eq(As(master, master.c.Verify.Status, GUILD), "verified")
		eq(Total(), 1, "one hand-over for the whole guild")
		-- His ask again within the window (a client asking over and over): nothing more until it ends.
		Asked()
		Play(Advance, As, all, 60)
		eq(Total(), 1, "none within GUILD_WINDOW")
		Play(Advance, As, all, master.c.Verify.GUILD_WINDOW, 60)
		Asked()
		Play(Advance, As, all, 60)
		eq(Total(), 2, "one more past it")
	end)
end)

-- In game a hand-over takes a second or so to reach the guild: every holder whose wait ends within it
-- answers too. Each wait is drawn over a window as wide as the 1.6.0 guildmates heard (in seconds), so
-- about one of them answers before the others hear it, a dozen holders or two hundred. (This world's
-- draws take their least value: here the send's guard alone keeps it to one, the test above.)
test("verify guild hand-over: the wait widens with the 1.6.0 guildmates heard, so about one answers before the others hear it", function()
	World(function(Node, As, Flush, Advance)
		local mate = Ready(Node("Guild Mate-Realm", GUILD))
		local V = mate.c.Verify
		Approved(As, T0, mate)
		local drawn
		V.random = function(a, b) drawn = { a, b } return a end
		local function Ask() -- (his ask, then past GUILD_WINDOW for the next)
			drawn = nil
			As(mate, mate.deliver, "GUILD", MASTER, ("GV~1~G~%s~0"):format(GUILD))
			local wait = drawn
			Play(Advance, As, { mate }, V.GUILD_WINDOW + 60, 60)
			return wait[2] - wait[1]
		end
		local function Hellos(from, to, version)
			for i = from, to do As(mate, mate.deliver, "GUILD", ("Peer Number%03d-Realm"):format(i), "H1~" .. version .. "~Realm~p") end
		end
		eq(Ask(), V.GUILD_ANSWER_MAX - V.GUILD_ANSWER_MIN, "alone: GUILD_ANSWER_MIN to _MAX")
		Hellos(1, 40, "1.6.0"); Hellos(41, 80, "1.5.9")
		eq(Ask(), 41 * V.GUILD_ANSWER_PER_PEER, "a second more for each guildmate on 1.6.0, itself included; none for older ones")
		Hellos(81, 280, "1.6.0")
		eq(Ask(), V.GUILD_ANSWER_SPREAD, "GUILD_ANSWER_SPREAD at most")
		eq(HandOvers(mate), 3)
	end)
end)

test("verify guild hand-over: guildmates logging in after a 1.5.9 guild master hand nothing over at their logins, then one each GUILD_SHARE_EVERY", function()
	World(function(Node, As, Flush, Advance)
		local master = Ready(Node(MASTER, GUILD, { rank = 0, old = true }))
		As(master, master.c.Comm.Hello, true); Flush()
		As(master, master.c.Verify.Login)
		Play(Advance, As, { master }, 300, 60)
		local mates, all = {}, { master }
		for i = 1, 12 do
			mates[i] = Ready(Node(("Guild Mate%02d-Realm"):format(i), GUILD))
			all[#all + 1] = mates[i]
		end
		local function Total() local k = 0 for _, m in ipairs(mates) do k = k + HandOvers(m) end return k end
		Approved(As, T0, unpack(mates))
		for _, m in ipairs(mates) do As(m, m.c.Verify.Login) end
		-- His hello every ten minutes (a quiet client's), the guildmates listening from their login.
		local share = mates[1].c.Verify.GUILD_SHARE_EVERY / 60
		for minute = 1, share - 1 do
			Play(Advance, As, all, 60, 60)
			if minute % 10 == 0 then As(master, master.c.Comm.Hello, true); Flush() end
		end
		eq(Total(), 0, "none at their logins, nor at his hellos before they heard the guild a whole turn")
		assert(As(master, master.c.Verify.Status, GUILD) ~= "verified")
		for minute = share, 2 * share - 1 do
			Play(Advance, As, all, 60, 60)
			if minute % 10 == 0 then As(master, master.c.Comm.Hello, true); Flush() end
		end
		eq(Total(), 1, "one hand-over in a turn, for the whole guild")
		eq(As(master, master.c.Verify.Status, GUILD), "verified")
		local turn = false
		for _, m in ipairs(mates) do turn = turn or Find(m.logs, "handed to the guild (turn)") ~= nil end
		assert(turn, "its turn, not a login")
		Play(Advance, As, all, 60, 60)
		As(master, master.c.Comm.Hello, true); Flush()
		Play(Advance, As, all, 120, 60)
		eq(Total(), 2, "the next turn's")
	end)
end)

-- (1.6.0) GPT's probe of 11-14 (dist/claude-recovery: six guild masters asking at login, one verifier
-- online: two of six held their approval after ten minutes, the verifier's ANSWER_GAP the bound), each
-- guild with one 1.6.0 guildmate that holds its approval: all six have it before their notice is due.
local function SixMasters(throughHub)
	local out = {}
	World(function(Node, As, Flush, Advance, Now)
		local hub = throughHub and Node("Hildryn Payne-Realm", "Olympus Hearth") or nil
		local verifier = Ready(Node(HC, "Olympus Crown"))
		local masters, all = {}, { verifier }
		for i = 1, 6 do
			local g, gm = ("Olympus Banner %d"):format(i), ("Banner Lord%d-Realm"):format(i)
			local m = Ready(Node(gm, g, { rank = 0 }))
			local mate = Ready(Node(("Banner Mate%d-Realm"):format(i), g))
			for _, x in ipairs({ verifier, m, mate, hub }) do x.c.rdb.guilds[g] = { leader = gm, realm = "Realm", total = 400 } end
			for _, x in ipairs({ verifier, mate }) do
				eq(As(x, x.c.Verify.Handle, "CHANNEL", HC, ("GV~1~A~%d~%s~%s"):format(T0, g, gm)), true)
			end
			if hub then As(hub, hub.deliver, "WHISPER", gm, "RL~P~RR~" .. g) end -- (each guild master reports for his guild)
			masters[i] = { n = m, g = g }
			all[#all + 1], all[#all + 1] = m, mate
			As(mate, mate.c.Verify.Login)
		end
		Advance(1)
		local start = Now()
		for _, m in ipairs(masters) do
			As(m.n, m.n.deliver, "WHISPER", (hub or verifier).c.me, "RY~")
			As(m.n, m.n.c.Verify.Login)
		end
		local got, slowest = 0, 0
		for _ = 1, 60 do
			Play(Advance, As, all, 10, 5)
			for _, m in ipairs(masters) do
				if not m.at and As(m.n, m.n.c.Verify.Status, m.g) == "verified" then
					m.at = Now() - start
					got, slowest = got + 1, math.max(slowest, m.at)
				end
			end
		end
		local told = 0
		for _, m in ipairs(masters) do told = told + #m.n.copies end
		out = { got = got, slowest = slowest, told = told, answered = verifier.c.Verify.Stats().answered }
	end)
	return out
end

test("verify guild hand-over: six guild masters at login on a verifier's relay all have their approval before their notice, from their guildmates", function()
	local r = SixMasters(false)
	eq(r.got, 6, "guild masters holding their approval within ten minutes")
	eq(r.told, 0, "none shown \"GM verification pending\"")
	assert(r.slowest < 90, "the slowest within NOTICE_AFTER: " .. tostring(r.slowest) .. " s")
end)

test("verify guild hand-over: six guild masters at login on a relay that is no verifier all have their approval before their notice, from their guildmates", function()
	local r = SixMasters(true)
	eq(r.got, 6)
	eq(r.told, 0)
	assert(r.slowest < 90, "the slowest within NOTICE_AFTER: " .. tostring(r.slowest) .. " s")
end)

test("verify guild hand-over: off Forever (the channel carries verification) a guild master asks no guild and nothing is handed over", function()
	World(function(Node, As, Flush, Advance)
		local mate = Ready(Node("Guild Mate-Realm", GUILD))
		local master = Ready(Node(MASTER, GUILD, { rank = 0 }))
		for _, n in ipairs({ mate, master }) do n.c.rdb.relayOff = true end
		Approved(As, T0, mate)
		Advance(3600)
		As(mate, mate.c.Verify.Login); As(master, master.c.Verify.Login)
		Play(Advance, As, { mate, master }, 120)
		eq(master.c.Verify.Stats().guildAsked, 0, "no ask to the guild")
		eq(#master.sentOf("GV~1~G~"), 0)
		As(mate, mate.deliver, "GUILD", MASTER, ("GV~1~G~%s~0"):format(GUILD))
		Play(Advance, As, { mate, master }, 60)
		eq(HandOvers(mate), 0, "and no hand-over")
	end)
end)
