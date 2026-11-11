-- Guild verification between relays (1.5.4). Real Comm + Relay + Verify path; only Blizzard's wire
-- and timers are simulated. Unlike tests/verify-relay.lua, no relay is ever handed an "RY~" it did not
-- earn: on Forever a relay's own client counts itself as answered (Relay.Pick), so it never pings or
-- sweeps the other relays and never learns one of them answered. Every verifier (the King, the High
-- Council, the author) is a relay, so before this fix each relay was an island for verification:
-- an approval reached the verifier's own reporters and guild only, and a relay's own ask reached
-- nobody. A member's sweep answer ("RY~" from its relay) and its guild's registration ("RR") are what
-- a real member's client sends, so they are delivered here as the wire would.
local ns, test, eq, RelayWorld, ADDON_DIR = ...
local T0 = 1800000000
local GUILD, OTHER = "Olympus Vanguard", "Olympus Embers"
local MASTER = "Guild Master-Realm"
local HC, HUB = "Max Ran-Realm", "Hildryn Payne-Realm" -- both on the signed list, so both relays

local function World(fn, hubVerifies)
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
			guild = guild, chat = C_ChatInfo, cursor = 0, logs = {} }
		-- (The review of the 1.5.4 candidate.) The node's log lines, as /oly bug prints them (ns.Log).
		c.Log = function(fmt, ...) local ok, msg = pcall(string.format, fmt, ...) n.logs[#n.logs + 1] = ok and msg or tostring(fmt) end
		c.clock, c.realm, c.RealmPages = now, "Realm", {}
		-- (1.5.4) T0 is a date past the code's presentation deadline: this world runs before it (its
		-- registrations are handed to the relays by hand, bare, ahead of any member's presentation).
		-- The presentation and the deadline have their own suite (tests/relay-admit.lua).
		c.Relay.PRESENT_REQUIRED_AT = T0 + 30 * 86400
		c.rdb.guilds = { [GUILD] = { leader = MASTER, realm = "Realm" }, [OTHER] = { leader = MASTER, realm = "Realm" } }
		c.IsHighCouncillor = function(who)
			local full = c.FullName(who)
			return full == HC or (hubVerifies == true and full == HUB)
		end
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
		for _ = 1, 60 do
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

-- A member of `guild` whose sweep its relay answered and whose guild registered there.
local function Member(Node, As, name, guild, relay)
	local m = Node(name, guild)
	As(m, m.deliver, "WHISPER", relay.c.me, "RY~")
	As(relay, relay.deliver, "WHISPER", m.c.me, "RL~P~RR~" .. guild)
	return m
end

local function Count(n, prefix, target)
	local k = 0
	for _, p in ipairs(n.sent) do
		if p.msg:sub(1, #prefix) == prefix and (target == nil or ns.ShortName(p.target or "") == ns.ShortName(target)) then k = k + 1 end
	end
	return k
end

test("verify mesh: a verifier relay's approval reaches every other relay and the guilds registered there, live", function()
	World(function(Node, As, Flush, Advance)
		local hub = Node(HUB, "Olympus Hearth")
		local verifier = Node(HC, "Olympus Crown")
		local member = Member(Node, As, "New Member-Realm", GUILD, hub)
		eq(As(verifier, verifier.c.Verify.Approve, GUILD, MASTER), true)
		Flush(); Advance(10)
		eq(Count(verifier, "RL~P~RP~") + Count(hub, "RL~P~RP~"), 0, "relays never ping one another (Relay.Pick counts our own client)")
		eq(As(hub, hub.c.Verify.Status, GUILD), "verified", "the other relay holds the approval")
		eq(As(member, member.c.Verify.Status, GUILD), "verified", "a guild registered with another relay holds it")
		local e = member.c.rdb.verify.list[ns.Fold(GUILD)]
		eq(e.by, HC, "the verifier is never replaced by a relay"); eq(e.at, T0)
		eq(As(verifier, verifier.c.Verify.Revoke, GUILD), true)
		Flush(); Advance(10)
		eq(member.c.rdb.verify.list[ns.Fold(GUILD)].k, "R", "a revocation travels the same way")
	end)
end)

test("verify mesh: a relay that was offline when the approval was made (the dev's client) recovers it with its own ask, then answers its own clients", function()
	World(function(Node, As, Flush, Advance)
		local verifier = Node(HC, "Olympus Crown")
		As(verifier, verifier.c.Verify.Observe)
		eq(As(verifier, verifier.c.Verify.Approve, GUILD, MASTER), true)
		Flush(); Advance(3600)
		local hub = Node(HUB, "Olympus Hearth") -- logs in an hour later, a verifier itself
		eq(As(hub, hub.c.Verify.Status, GUILD) ~= "verified", true)
		eq(As(hub, hub.c.Verify.Ask), true)
		Flush(); Advance(10); Advance(10)
		eq(As(hub, hub.c.Verify.Status, GUILD), "verified", "the relay's own ask reached the verifier relay")
		local e = hub.c.rdb.verify.list[ns.Fold(GUILD)]
		eq(e.at, T0, "the original time"); eq(e.by, HC, "the original verifier")
		eq(hub.c.rdb.verify.start[ns.Fold(GUILD)].at, T0, "recovery never restarts the grace")
		-- Its own clients next: a member whose guild is registered with the hub asks it.
		local member = Member(Node, As, "Hub Client-Realm", GUILD, hub)
		eq(As(member, member.c.Verify.Ask), true)
		Flush(); Advance(10); Advance(10)
		eq(As(member, member.c.Verify.Status, GUILD), "verified", "the relay now answers its own clients")
		eq(member.c.rdb.verify.list[ns.Fold(GUILD)].by, HC)
	end, true)
end)

test("verify mesh: a member that was offline recovers an approval its own relay cannot answer for", function()
	World(function(Node, As, Flush, Advance)
		local hub = Node(HUB, "Olympus Hearth") -- a relay that is no verifier here: it never answers
		local verifier = Node(HC, "Olympus Crown")
		eq(As(verifier, verifier.c.Verify.Approve, GUILD, MASTER), true)
		Flush(); Advance(3600)
		local member = Member(Node, As, "New Member-Realm", GUILD, hub)
		local guildmate = Node("Late Guildmate-Realm", GUILD)
		eq(As(member, member.c.Verify.Ask), true)
		Flush(); Advance(10); Advance(10)
		eq(As(member, member.c.Verify.Status, GUILD), "verified", "the ask crossed to the verifier relay")
		eq(member.c.rdb.verify.list[ns.Fold(GUILD)].at, T0)
		eq(As(guildmate, guildmate.c.Verify.Status, GUILD), "verified", "the member hands the answer to its guild once")
	end)
end)

test("verify mesh: a missed startup snapshot is requested once more after the relay window", function()
	World(function(Node, As, Flush, Advance)
		local hub = Node(HUB, "Olympus Relay")
		local member = Member(Node, As, "Late Member-Realm", "Olympus Late", hub)
		As(member, member.c.Verify.Login)
		Advance(member.c.Verify.ASK_AFTER)
		eq(Count(member, "RL~P~GV~1~Q~"), 1)
		eq(As(member, member.c.Verify.Status, GUILD), "pending")

		-- The verifier reconnects after the member's first ask with its saved decision.
		local hc = Node(HC, "Olympus Council")
		As(hc, hc.c.Verify.Handle, "CHANNEL", HC, "GV~1~A~" .. T0 .. "~" .. GUILD .. "~" .. MASTER)
		Advance(member.c.Verify.STARTUP_RETRY)
		eq(Count(member, "RL~P~GV~1~Q~"), 2, "the missed startup ask is retried before the periodic ask")
		Advance(10)
		eq(As(member, member.c.Verify.Status, GUILD), "verified")
		Advance(220)
		eq(Count(member, "RL~P~GV~1~Q~"), 2, "startup recovery is bounded")
	end)
end)

test("verify mesh: bounded: verification never makes relays forward everything to each other, an answer is one transfer to the asker", function()
	World(function(Node, As, Flush, Advance)
		local hub = Node(HUB, "Olympus Hearth")
		local verifier = Node(HC, "Olympus Crown")
		local reporters = {}
		for i = 1, 6 do reporters[i] = Member(Node, As, "Reporter " .. i .. "-Realm", "Olympus Guild " .. i, i <= 3 and hub or verifier) end
		for i = 1, 12 do eq(As(verifier, verifier.c.Verify.Approve, "Olympus Recovery " .. i, MASTER), true) end
		Flush(); Advance(10)
		Advance(3600)
		local late = Member(Node, As, "Late Member-Realm", GUILD, hub)
		eq(As(late, late.c.Verify.Ask), true)
		Flush(); Advance(10); Advance(10)
		eq(late.c.Verify.Digest() >= 12, true, "the late member holds every approval")
		-- The answer went to the asker alone, as one bounded transfer: no reporter of either relay got it.
		local function Answer(n, to)
			local k = 0
			for _, p in ipairs(n.sent) do
				if ns.ShortName(p.target or "") == ns.ShortName(to) and (p.msg:find("^RM~P~[^~]+~GV~1~S~") or p.msg:find("^CR%d+:%d+:%d+:")) then k = k + 1 end
			end
			return k
		end
		for _, r in ipairs(reporters) do
			eq(Answer(hub, r.c.me) + Answer(verifier, r.c.me), 0, "no snapshot fan-out to " .. r.c.me)
		end
		local pieces = Answer(verifier, late.c.me)
		eq(pieces >= 1 and pieces <= ns.Codec.MAX_CHUNKS, true, "one transfer to the asker: " .. pieces .. " pieces")
		-- After all this verification traffic, an ordinary word a client hands the hub still does not
		-- cross to the other relay: verification must never switch on relay-to-relay forwarding of
		-- every word (the census alone would be ~140 words a minute times every other relay).
		local before = Count(hub, "RX~", verifier.c.me)
		As(hub, hub.deliver, "WHISPER", "Some Client-Realm", "RL~P~X1~ordinary")
		Flush()
		eq(Count(hub, "RX~", verifier.c.me), before, "an ordinary word never crosses because of verification traffic")
		-- A word that claims to be an approval from someone who is no verifier never crosses relays
		-- (its own relay's guilds refuse it, as in 1.5.2); a verifier's own does, once.
		local rw = Count(hub, "RW~")
		As(hub, hub.deliver, "WHISPER", "Forger Here-Realm", ("RL~L~GV~1~A~%d~%s~%s"):format(T0 + 3700, OTHER, MASTER))
		Flush()
		eq(Count(hub, "RW~"), rw, "a forged approval does not cross relays")
		eq(late.c.rdb.verify.list[ns.Fold(OTHER)], nil, "and no guild takes it")
	end)
end)

-- The review of the 1.5.4 candidate: a verifier's client answered an ask whose origin was a relay's
-- name on that relay's own gap (Verify.RELAY_ANSWER_GAP, 900 s), and an ask's origin is only a word
-- in a guild's hand-over (RG), a relay's RM or RX. One guildmate naming each relay in turn got the
-- whole store sent once per relay named, and the real relay's own ask was then ignored for 900 s.
-- Only an ask that came across from the relay itself (RW, its name stamped by the server) has the
-- relay's own gap now. Each fails before.
local OTHER_RELAYS = { "Hildryn Payne", "Relay Three", "Relay Four", "Relay Five" }
local function Answers(n)
	local k = 0
	for _, p in ipairs(n.sent) do
		if p.msg:find("^R[WM]~P~[^~]+~GV~1~S~") then k = k + 1 end
	end
	return k
end

test("verify mesh: asks a guildmate hands over (RG) naming relays as their origin get at most one answer each ANSWER_GAP, never one per relay named", function()
	World(function(Node, As, Flush, Advance)
		local verifier = Node(HC, "Olympus Crown")
		for _, n in ipairs(OTHER_RELAYS) do verifier.c.rdb.council.names[n:lower()] = n end -- (all signed relays)
		eq(As(verifier, verifier.c.Verify.Approve, GUILD, MASTER), true)
		Flush(); Advance(3600)
		local before = Answers(verifier)
		local function Burst(tag)
			for i, relay in ipairs(OTHER_RELAYS) do
				eq(verifier.c.Relay.IsRelay(relay), true, relay .. " is a signed relay")
				As(verifier, verifier.deliver, "GUILD", "Forger Mate-Realm", ("RG~P~%s~GV~1~Q~0~0~%d"):format(relay, tag * 10 + i))
			end
			Flush(); Advance(10); Advance(10)
		end
		Burst(1)
		eq(Answers(verifier) - before, 1, "one answer for the whole burst, not one per relay it named")
		Advance(60)
		Burst(2)
		eq(Answers(verifier) - before, 1, "none more within ANSWER_GAP")
		Advance(verifier.c.Verify.ANSWER_GAP)
		Burst(3)
		eq(Answers(verifier) - before, 2, "one more once ANSWER_GAP passed")
	end)
end)

test("verify mesh: a relay's own ask that came across (RW) is answered after a guildmate's burst of asks named that relay", function()
	World(function(Node, As, Flush, Advance)
		local verifier = Node(HC, "Olympus Crown")
		eq(As(verifier, verifier.c.Verify.Approve, GUILD, MASTER), true)
		Flush(); Advance(3600)
		for i = 1, 3 do
			As(verifier, verifier.deliver, "GUILD", "Forger Mate-Realm", ("RG~P~Hildryn Payne~GV~1~Q~0~0~%d"):format(i))
		end
		Flush(); Advance(10); Advance(10)
		local hub = Node(HUB, "Olympus Hearth") -- logs in now: a relay that missed the approval
		eq(As(hub, hub.c.Verify.Status, GUILD) ~= "verified", true)
		eq(As(hub, hub.c.Verify.Ask), true)
		Flush(); Advance(10); Advance(10)
		eq(As(hub, hub.c.Verify.Status, GUILD), "verified", "its own ask is answered: the forged ones never took its gap")
		eq(hub.c.rdb.verify.list[ns.Fold(GUILD)].by, HC)
	end)
end)

test("verify mesh: a relay whose answer the verifier's client could not send is answered on its next ask, well before RELAY_ANSWER_GAP", function()
	World(function(Node, As, Flush, Advance)
		local verifier = Node(HC, "Olympus Crown")
		eq(As(verifier, verifier.c.Verify.Approve, GUILD, MASTER), true)
		Flush(); Advance(3600)
		local hub = Node(HUB, "Olympus Hearth")
		local direct = verifier.c.Relay.Direct
		verifier.c.Relay.Direct = function() return false end -- (the answer refused: a full queue, say)
		local ok, err = pcall(function()
			eq(As(hub, hub.c.Verify.Ask), true)
			-- (Refused through every retry: ANSWER_RETRIES, ANSWER_RETRY_EVERY apart.)
			Flush()
			for _ = 1, 2 + verifier.c.Verify.ANSWER_RETRIES do Advance(verifier.c.Verify.ANSWER_RETRY_EVERY + 1) end
		end)
		verifier.c.Relay.Direct = direct
		if not ok then error(err, 0) end
		eq(As(hub, hub.c.Verify.Status, GUILD) ~= "verified", true, "the refused answer never left")
		-- Its next ask, once its own relay and the verifier's no longer hold the first (Relay.SEEN_FOR).
		Advance(hub.c.Relay.SEEN_FOR + 1)
		eq(As(hub, hub.c.Verify.Ask), true)
		Flush(); Advance(10); Advance(10)
		eq(As(hub, hub.c.Verify.Status, GUILD), "verified", "answered, not ignored for RELAY_ANSWER_GAP")
	end)
end)

-- The review of the 1.5.4 candidate: a whole store is up to MAX_CHUNKS pieces in one urgent transfer,
-- and a relay's queue (MAX_QUEUE parts) refused a second one asked for in the same seconds: that
-- asker got nothing until its next ask, half an hour later. A refused answer is tried again a few
-- seconds later (ANSWER_RETRY_EVERY), while the first goes out. Fails before (one asker holds none).
test("verify mesh: a client's ask and a relay's ask answered in the same seconds, each with a whole store (two are more than the queue holds), both reach their askers", function()
	World(function(Node, As, Flush, Advance)
		local verifier = Node(HC, "Olympus Crown")
		for i = 1, 130 do eq(As(verifier, verifier.c.Verify.Approve, ("Olympus Recovery %03d"):format(i), MASTER), true) end
		Flush(); Advance(3600)
		local payload, rows = As(verifier, verifier.c.Verify.Payload)
		local pieces = #verifier.c.Codec.Chunk("RM~P~" .. HC .. "~" .. payload, "1")
		eq(2 * pieces > verifier.c.Comm.MAX_QUEUE, true, ("two answers of %d pieces are more than the queue holds at once"):format(pieces))
		-- Both log in now, missing the approvals, and ask in the same moment.
		local hub = Node(HUB, "Olympus Hearth")
		local member = Member(Node, As, "Crown Client-Realm", GUILD, verifier)
		eq(As(member, member.c.Verify.Ask), true)
		eq(As(hub, hub.c.Verify.Ask), true)
		Flush()
		for _ = 1, 4 do Advance(verifier.c.Verify.ANSWER_RETRY_EVERY + 1) end
		eq(member.c.Verify.Digest() >= rows, true, "the client holds the store")
		eq(hub.c.Verify.Digest() >= rows, true, "the relay holds the store")
	end)
end)

-- The review of the 1.5.4 candidate: where answers go to the one client that asked (Relay.Direct, on
-- Forever), a snapshot a verifier's client hears went to someone else (another verifier's answer to its
-- own ask, a hand-over in its own guild), never to the client whose ask it is answering. Taken as
-- "coverage" it dropped that answer, the first one or a refused one's retry, and the client's guild got
-- nothing until a later ask. Coverage holds on the channel alone. Each fails before (the member holds none).
local function Covered(Node, As, Flush, Advance, quiet)
	local hub = Node(HUB, "Olympus Hearth")
	eq(As(hub, hub.c.Verify.Approve, OTHER, MASTER), true) -- before the verifier logs in: it lacks this one
	Flush(); Advance(10)
	local verifier = Node(HC, "Olympus Crown")
	for i = 1, 12 do eq(As(verifier, verifier.c.Verify.Approve, ("Olympus Recovery %03d"):format(i), MASTER), true) end
	Flush(); Advance(3600)
	eq(verifier.c.rdb.verify.list[ns.Fold(OTHER)], nil, "the verifier lacks the hub's earlier approval")
	local member = Member(Node, As, "Cov Client-Realm", GUILD, verifier)
	if quiet then -- a client's ask crossed a moment ago (one each VERIFY_ASK_EVERY): the member's stays here
		local n, newest, sum, fp = As(verifier, verifier.c.Verify.Digest)
		As(verifier, verifier.deliver, "WHISPER", "Earlier Client-Realm", ("RL~P~GV~1~Q~%d~%d~%d~%s"):format(n, newest, sum, fp))
		Flush(); Advance(10)
	end
	return hub, verifier, member
end

test("verify mesh: another verifier's answer to the verifier's own ask, heard while a client's answer waits its 2-9 s, never drops that answer", function()
	World(function(Node, As, Flush, Advance)
		local _, verifier, member = Covered(Node, As, Flush, Advance, true)
		verifier.c.Verify.random = function(_, b) return b end -- the client's answer at 9 s; the hub answers at 2 s
		eq(As(member, member.c.Verify.Ask), true)
		eq(As(verifier, verifier.c.Verify.Ask), true) -- its own half-hourly ask, in the same seconds
		Flush()
		for _ = 1, 8 do Advance(6) end
		eq(verifier.c.rdb.verify.list[ns.Fold(OTHER)] ~= nil, true, "the hub's answer reached the verifier first")
		eq(member.c.Verify.Digest() >= verifier.c.Verify.Digest(), true, "the member holds the store")
	end, true)
end)

test("verify mesh: a refused answer is tried again although another verifier's answer to the verifier's own ask came meanwhile", function()
	World(function(Node, As, Flush, Advance)
		local _, verifier, member = Covered(Node, As, Flush, Advance, true)
		local direct, refused = verifier.c.Relay.Direct, 0
		verifier.c.Relay.Direct = function(target, ...) -- (the first answer refused: a full queue, say)
			if ns.ShortName(target) == ns.ShortName(member.c.me) and refused == 0 then refused = 1 return false end
			return direct(target, ...)
		end
		local ok, err = pcall(function()
			eq(As(member, member.c.Verify.Ask), true)
			eq(As(verifier, verifier.c.Verify.Ask), true)
			Flush()
			for _ = 1, 2 + verifier.c.Verify.ANSWER_RETRIES do Advance(verifier.c.Verify.ANSWER_RETRY_EVERY + 1) end
		end)
		verifier.c.Relay.Direct = direct
		if not ok then error(err, 0) end
		eq(refused, 1, "the first answer was refused")
		eq(verifier.c.rdb.verify.list[ns.Fold(OTHER)] ~= nil, true, "the hub's answer reached the verifier before the retry")
		eq(member.c.Verify.Digest() >= verifier.c.Verify.Digest(), true, "the member holds the store: the retry went")
	end, true)
end)

test("verify mesh: a hand-over in the verifier's own guild, heard while a client of another guild waits its answer, never drops that answer", function()
	World(function(Node, As, Flush, Advance)
		local hub, verifier, member = Covered(Node, As, Flush, Advance)
		local mate = Member(Node, As, "Crown Mate-Realm", "Olympus Crown", hub) -- the verifier's guild picked the hub
		verifier.c.Verify.random = function(_, b) return b end
		eq(As(mate, mate.c.Verify.Ask), true)     -- to the hub, which answers it (and hands it to the verifier's guild)
		eq(As(member, member.c.Verify.Ask), true) -- to the verifier; it crosses, and the busy hub ignores it
		Flush()
		for _ = 1, 8 do Advance(6) end
		eq(verifier.c.rdb.verify.list[ns.Fold(OTHER)] ~= nil, true, "the verifier heard its guild's hand-over")
		eq(member.c.Verify.Digest() >= verifier.c.Verify.Digest(), true, "the member holds the store")
	end, true)
end)

local function Logged(n, line) -- how many lines of the node's log read exactly so
	local k = 0
	for _, l in ipairs(n.logs) do if l == line then k = k + 1 end end
	return k
end

-- The review of the 1.5.4 candidate: the path above left no copyable trace. Relay.Stats() returned
-- neither verifyAcross nor direct, no line of the log named an ask crossing (ToRelays), an RW heard
-- (HandleVerify) or a direct answer (Verify.SendSnapshot, Relay.Direct), and no line of /oly status
-- or /oly bug read Relay.Stats() or Verify.Stats(). A relay's log turns over the lines /oly bug
-- prints in seconds, so the counters are in a status line too (Diagnostics.lua's relay line).
test("verify mesh: an ask that crossed (RW), the RW heard and the direct answer leave a log line each, and /oly status and /oly bug count them", function()
	World(function(Node, As, Flush, Advance)
		local verifier = Node(HC, "Olympus Crown")
		As(verifier, verifier.c.Verify.Observe)
		eq(As(verifier, verifier.c.Verify.Approve, GUILD, MASTER), true)
		Flush(); Advance(3600)
		local hub = Node(HUB, "Olympus Hearth") -- the dev's relay client, an hour later
		eq(As(hub, hub.c.Verify.Ask), true)
		Flush(); Advance(10); Advance(10)
		eq(As(hub, hub.c.Verify.Status, GUILD), "verified")
		local hs, vs = hub.c.Relay.Stats(), verifier.c.Relay.Stats()
		eq(hs.verifyAcross, 1, "the hub's ask crossed once"); eq(hs.direct, 0, "and it answered nobody")
		eq(vs.direct, 1, "the verifier answered direct once"); eq(vs.verifyAcross, 1, "its approval crossed (to the hub, then offline)")
		eq(Logged(hub, "relay: " .. HUB .. "'s word (GV~1~Q) across to 1 relays"), 1, "the asker logs its ask crossing")
		eq(Logged(hub, "relay: RW GV~1~S from " .. HC .. ", origin " .. HC), 1, "and the answer heard")
		eq(Logged(verifier, "relay: RW GV~1~Q from " .. HUB .. ", origin " .. HUB), 1, "the verifier logs the ask heard")
		local _, rows = As(verifier, verifier.c.Verify.Payload)
		eq(Logged(verifier, ("verify: answer (%d rows) to %s"):format(rows, HUB)), 1, "and its direct answer")
		-- The counters in /oly status and /oly bug, read from the modules the client loaded.
		local had = { relay = rawget(ns, "Relay"), verify = rawget(ns, "Verify") }
		ns.Relay, ns.Verify = verifier.c.Relay, verifier.c.Verify
		local ok, err = pcall(function()
			local counted = "verify across 1  direct 1  asked 0  answered 1  unsent 0"
			local status = As(verifier, ns.StatusText)
			assert(status:find("\nrelay: ", 1, true) and status:find(counted, 1, true), status)
			assert(As(verifier, ns.BuildBugReport):find(counted, 1, true), "in /oly bug too")
			ns.Relay, ns.Verify = hub.c.Relay, hub.c.Verify
			-- (1.5.4, with the relays' presentation) /oly status has a second "relay:" line, the rules and
			-- the deadline (Relay.lua); the counts are on the relay line that carries them.
			local line
			for l in As(hub, ns.StatusText):gmatch("\n(relay: [^\n]*)") do if l:find("verify across", 1, true) then line = l end end
			assert(line and line:find("verify across 1  direct 0  asked 1  answered 0  unsent 0", 1, true), tostring(line))
		end)
		ns.Relay, ns.Verify = had.relay, had.verify
		if not ok then error(err, 0) end
	end, true)
end)
