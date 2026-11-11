local ADDON, ns = ...

-- GUILD: "hello" pings so members with the addon know each other and elect one reporter.
-- CHANNEL (hidden "OlympusNet"): the elected reporter of each guild broadcasts its summary.
-- Chat lines of the channels (Channels.lua) ride the same hidden channel in a lane of their own.
-- One reporter per guild on each realm (1.0.0): on WoW: Forever each realm has an OlympusNet of
-- its own, while GUILD reaches a guild's members on every realm, so the election counts the
-- peers of our realm (see Electable).

local Comm = {}
ns.Comm = Comm
local Codec = ns.Codec

local HELLO_EVERY = 60
local PEER_WINDOW = 180  -- the election only trusts peers heard in the last 3 minutes
local COUNT_WINDOW = 720 -- quiet members say hello every 10 min: count them for 12
local BROADCAST_EVERY = 170
local SEND_INTERVAL = 1.2
local MAX_QUEUE = 60 -- (Comm.MAX_QUEUE below, for the tests; 1.5.0: a relay keys its forwards instead of widening this)
local CHAT_QUEUE = 6  -- chat parts waiting in their own lane (two long lines)
local CHAT_TTL = 30   -- a chat part that waited this long is dropped, not sent late
local GUARD_AFTER = 400  -- an elected reporter never heard reporting our guild for this long...
local GUARD_FOR = 30 * 60 -- ...is left out of the election for this long (see MaybeBroadcast)
local KEY_ASK_EVERY = 600 -- at most one key request this often while a sealed reporter is elected
local WITNESS_EVERY = 600 -- the runner-up of the election reports this often (see MaybeBroadcast)
local JOIN_BY = 15        -- seconds after login we join the channel at the latest (see JoinSoon)
local ASK_AFTER = 4       -- seconds after joining we ask the channel for the census (Q1)...
local ASK_SPREAD = 41     -- ...at a second drawn up to this much later (1.0.0: 4 to 45 s)...
local ASK_HELD = 30       -- ...unless someone else asked this recently (its answers reach us too)...
local ASK_AGAIN = 65      -- ...and once more this later, for the reporters that had just answered
local SHARED_FOR = 3600   -- our guild's report from a guildmate of another realm this recently: the channel is shared
local QUIET_TOTAL = 10    -- members of a guild who keep saying hello (Comm.Hello), whatever its realms...
local QUIET_MIN = 3       -- ...and at least this many on each realm
local ANSWER_GAP = BROADCAST_EVERY -- a reporter answers census requests at most this often
local WITNESS_ANSWER_GAP = 300     -- the runner-up at most this often
local ANSWER_MIN_AGE = 45 -- ...and only when its last report is at least this old
local MAX_KEYS = 20      -- distinct keys per diagnostic count (the rest count as "other")
local HEAL_GAP = 60      -- the same healing call on our channel at most this often (Comm.HealChannel)
local MAX_HURT = 20      -- banned or muted names kept per channel to let back in (oldest dropped)
local LOCKED_RETRY = { 60, 120, 300, 600 } -- a channel locked against us is tried again after these, then every 10 min
local HOLD_MAX = 600     -- 1.4.0: a message held this long without going out (a lockdown) is dropped (DropStale)

local peers = {}
-- Two priorities, each with single messages and whole transfers. Intrusive lists keep
-- the pump, keyed replacement and removal O(1); capacity still counts unsent messages.
local lanes = { {}, {}, {}, {} } -- urgent single/batch, ordinary single/batch
local keyed, owned = {}, {}
local queueSize, ordinarySize, sequence = 0, 0, 0
local active, batchSlot
local refusedInRow, waitUntil = 0, -math.huge -- 1.4.0: the game's "not now" in a row, and the pump's wait after it (SendNow)
local heldSince -- 1.4.0: when the pump began holding the queue (a lockdown, RETRY_WAIT), until it sends again
local SyncGuild
-- Five fragments, two chat opportunities and one urgent opportunity in eight slots:
-- 30 pieces finish within 55.2 s; six waiting chat pieces within 28.8 s at 1.2 s/slot.
local BATCH_SLOTS = { "part", "part", "chat", "part", "chat", "part", "part", "urgent" }
local chatQueue = {}  -- chat lines (Channels.lua): { msg, done, t, channel } (channel: the one it was written for, GitHub #34)
local lastWasChat = false
local asm = Codec.NewAssembler()
local guildAsm = Codec.NewAssembler() -- pieces over GUILD (1.0.0)...
local outsiderAsm = Codec.NewAssembler()
local whisperAsm = Codec.NewAssembler() -- private signed-authority answers (1.2)
local GUILD_PIECES = { HS = true, HT = true, XB = true, WZ = true, WU = true }
local WHISPER_PIECES = { H2 = true } -- ...and over WHISPER (1.4.3: the relay's RL and RM too, Comm.RelayPieces)
-- 1.4.3: the relay (Relay.lua) names the kinds its pieces carry over GUILD and WHISPER.
function Comm.RelayPieces(kinds)
	for k in pairs(kinds or {}) do GUILD_PIECES[k], WHISPER_PIECES[k] = true, true end
end
local function RelayOn() local R = ns.Relay return type(R) == "table" and R.On() == true and R.Pick() ~= nil end -- ...put together for these types alone: signed lists, loot, War recovery and bounded squad assignments
local msgId = 0
local lastBroadcast = 0
local early -- { every, due }: the report due then went out early, as a census answer (see Q1)
local channelIndex = 0
local stats = { sent = 0, recv = 0, reports = 0, fails = 0, bad = 0, partial = 0, echo = 0, byType = {},
	raw = { ch = {}, g = {} }, rawSample = {}, reportRealms = {}, otherChannel = 0, asked = 0, answered = 0, askSkipped = 0,
	chatMoved = 0 }
local deliveredLogged = false -- true while a CHAT_MSG_ADDON_LOGGED message is being handled
local lastAnswer = -math.huge
local askTries = 0 -- census requests tried while the channel was not joined (Comm.AskCensus)
local heardAsk = -math.huge -- someone else's census request last heard on our channel (Comm.AskCensus)
local askedAgain = false    -- the second census request is on its way, or went (Comm.AskCensus)
local joinedName -- name of the channel we joined (set by Comm.JoinChannel)
-- 1.4.1: the channel lane (declared here: SendNow and Comm.Stats, above the lane's own code, use them).
local laneRefused, laneProbe = 0, false
local Lane
-- Lanes refused by the game stay bad for this session. Crowd correction waits after every move,
-- whether refusal-, officer- or crowd-driven, before it may choose another lane.
local laneBad, laneMovedAt = {}, -math.huge
local peerRealm = {} -- guild peer -> realm from its hello, "old" for versions that send none
local peerVersion = {} -- guild peer -> the addon version its hello named
local peerSealed = {} -- guild peer -> "s" (on the sealed channel) or "p" (public), from its hello
local peerLane = {}   -- guild peer -> its channel lane when not the first (1.4.1), from its hello
local peerLaneUsable = {} -- guild peer -> true/false for a present valid/invalid lane field (lane 0 is valid)
local peerRelay = {}  -- guild peer -> true when its hello says it carries the relay (1.4.3)
local peerZone = {} -- guild peer -> true when its hello says it shares its zone (0.9.1, Comm.SharesZone)
local peerBank = {} -- guild peer -> true while its hello says it is an arena bank on duty (1.2, Electable)
-- Short name -> last time we heard it report our guild on the channel. Short: the server may
-- send a name with its realm over GUILD and without it over CHANNEL (names are region-unique
-- on the realmless client).
local heardOwn = {}
local benched = {}   -- guild peer -> time it may be elected again
local watch          -- { name, since }: the peer we elected while we are on the channel
local lastKeyAsk     -- when MaybeBroadcast last asked our guild for the key
-- 1.0.0: when our channel last carried our guild's report from a guildmate whose hello named
-- another realm (Comm.ElectsAcrossRealms). This session's alone, never saved.
local crossedAt = -math.huge
local peerGuild = GetGuildInfo("player")
local guildChangedAt = 0
local guildSession, lastHello = 0, 0
-- Quiet presence (1.2.5.1, Core.lua) is on: see Comm.QUIET_WORDS.
local function Quiet() return ns.QuietPresence ~= nil and ns.QuietPresence() == true end

-- count[key] + 1, with at most MAX_KEYS distinct keys (senders choose some of them).
local function Count(t, key)
	if t[key] == nil then
		local n = 0
		for _ in pairs(t) do n = n + 1 end
		if n >= MAX_KEYS then key = "other" end
	end
	t[key] = (t[key] or 0) + 1
end

-- Our guild's addon users counted now, on every realm; sameRealm (1.0.0): those whose hello
-- named our realm alone.
function Comm.PeerCount(sameRealm)
	local now, n = ns.Now(), 0
	for name, t in pairs(peers) do
		if now - t <= COUNT_WINDOW and (not sameRealm or peerRealm[name] == ns.realm) then n = n + 1 end
	end
	return n
end

-- 1.1: our guild's addon users heard lately (by their hello), by name (Loot.lua draws its officers'
-- turns to answer an ask from them).
function Comm.Peers()
	local now, out = ns.Now(), {}
	for name, t in pairs(peers) do
		if now - t <= PEER_WINDOW then out[#out + 1] = name end
	end
	table.sort(out)
	return out
end

-- The addon versions of our guild's users counted now, ours included: { ["0.8.2"] = 3 }.
-- Rides in our report (field 24) for the author's Workshop.
function Comm.PeerVersions()
	local now, out = ns.Now(), { [ns.VERSION] = 1 }
	for name, t in pairs(peers) do
		if now - t <= COUNT_WINDOW then
			local v = peerVersion[name] or "?"
			out[v] = (out[v] or 0) + 1
		end
	end
	return out
end

-- 1.1.2 (Versions.lua, the right-click menus): one guildmate's addon version as their last hello
-- named it ("?" for a hello whose version we can't read), and when that was; nil when none was
-- heard this session. By the whole name first, else by the short name folded (the roster, a menu
-- and guild messages may write the realm apart, as SharesZone reads them). Never pruned: an old
-- hello still says which version they ran then (the caller shows how long ago).
function Comm.PeerVersion(name)
	if type(name) ~= "string" or name == "" then return nil end
	local full = ns.FullName(ns.Normal(name))
	if peers[full] then return peerVersion[full] or "?", peers[full] end
	local short = ns.Fold(ns.ShortName(full))
	local version, at
	for peer, t in pairs(peers) do
		if ns.Fold(ns.ShortName(peer)) == short and (not at or t > at) then version, at = peerVersion[peer] or "?", t end
	end
	return version, at
end

-- (1.5.4, the layer hop across Forever's sub-realms) The realm this guildmate's last hello named
-- (H1's second field), and when it was heard; nil when none was heard this session or his version
-- names none ("old"). By the whole name first, else by the short name folded, the newest: on
-- Forever the server stamps a guildmate's words with the reader's own sub-realm, never his, so his
-- hello is the one word that says where he plays (Layers.RealmOf, Hop.SubRealmOf).
function Comm.PeerRealm(name)
	if type(name) ~= "string" or name == "" then return nil end
	local full = ns.FullName(ns.Normal(name))
	local peer, at = nil, nil
	if peers[full] then
		peer, at = full, peers[full]
	else
		local short = ns.Fold(ns.ShortName(full))
		for candidate, t in pairs(peers) do
			if ns.Fold(ns.ShortName(candidate)) == short and (not at or t > at) then peer, at = candidate, t end
		end
	end
	local realm = peer and peerRealm[peer]
	if type(realm) ~= "string" or realm == "old" then return nil end
	return realm, at
end

-- Guild peers counted now, by the realm their hello named.
local function PeerRealms(now)
	local out = {}
	for name, t in pairs(peers) do
		if now - t <= COUNT_WINDOW then Count(out, peerRealm[name] or "old") end
	end
	return out
end

function Comm.Stats()
	local now = ns.Now()
	local lastOwn, lastOwnAt = nil, 0
	for name, t in pairs(heardOwn) do
		if t > lastOwnAt then lastOwn, lastOwnAt = name, t end
	end
	local out = {}
	for name, t in pairs(benched) do
		if t > now then out[#out + 1] = ns.DisplayName(name) end
	end
	table.sort(out)
	local r = Comm.lastReport
	return {
		channelName = joinedName, sealed = ns.rdb and ns.rdb.realmKey ~= nil,
		channel = channelIndex, peers = Comm.PeerCount(), reporter = Comm.reporterName,
		isReporter = Comm.isReporter, sent = stats.sent, recv = stats.recv, reports = stats.reports,
		fails = stats.fails, bad = stats.bad, queue = queueSize, chatQueue = #chatQueue, chatMoved = stats.chatMoved, lastFail = stats.lastFail,
		partial = stats.partial, echo = stats.echo, byType = stats.byType, otherChannel = stats.otherChannel,
		chanArgs = stats.chanArgs, asked = stats.asked, answered = stats.answered, runnerUp = Comm.isRunnerUp, pending = (function() local n = 0 for _ in pairs(asm.buf) do n = n + 1 end return n end)(),
		raw = stats.raw, rawSample = stats.rawSample, reportRealms = stats.reportRealms, shared = ns.rdb and ns.rdb.shared,
		peerRealms = PeerRealms(now), heardOwn = lastOwn and ns.DisplayName(lastOwn), heardOwnAt = lastOwn and lastOwnAt,
		benched = out, guard = Comm.GuardStats and Comm.GuardStats(), askSkipped = stats.askSkipped,
		-- 1.0.0: whom the election counts (our realm's peers, or every realm's on a shared channel),
		-- how many before us keep us quiet, our guild's realms, and what our report's new fields say.
		electAll = Comm.ElectsAcrossRealms(now), quietAfter = Comm.QuietAfter(now), presence = Comm.PresenceRealms(now),
		-- 1.2.5.1: quiet presence on, and how many of our words it held (Comm.QuietHolds).
		quietPresence = Quiet(), quietHeld = stats.quiet or 0,
		-- (1.5.4) Words dropped at the door from clients marked as modified builds (Builds.lua).
		quarantined = stats.quarantined or 0,
		-- 1.4.0: the game's "not now" (a throttle, a lockdown): sends kept for another try, sends
		-- held back by a lockdown, and whether the queue is held now.
		retried = stats.retried or 0, lockHeld = stats.locked or 0, held = heldSince ~= nil,
		reportSt = r and r.st, reportCap = r and r.cap, reportPres = r and r.pres,
		-- 1.4.1: the channel lane we are on, refusals counted towards the next, moves made.
		lane = Lane(), laneRefused = laneRefused, laneMoves = stats.lanes or 0,
		peerLanes = (function() local n = {} for name, l in pairs(peerLane) do n[#n + 1] = ns.DisplayName(name) .. ":" .. l end table.sort(n) return n end)(),
		-- 1.5.4: lists heard (Comm.SendList's envelope), the words they carried, lists dropped whole.
		lists = stats.lists or 0, listWords = stats.listWords or 0, listsBad = stats.listsBad or 0, listsSplit = stats.listsSplit or 0,
	}
end

local function Unlink(job)
	local lane = job.lane
	if not lane then return end
	if not job.urgent then ordinarySize = ordinarySize - (#job.parts - job.i + 1) end
	if job.prev then job.prev.next = job.next else lane.first = job.next end
	if job.next then job.next.prev = job.prev else lane.last = job.prev end
	job.lane, job.prev, job.next = nil, nil, nil
end

local function Detach(job)
	if job.finished then return end
	Unlink(job)
	if active == job then active, batchSlot = nil, nil end
	queueSize = queueSize - (#job.parts - job.i + 1)
	if job.key and keyed[job.key] == job then keyed[job.key] = nil end
	if job.owner then
		local jobs = owned[job.owner]
		if jobs then jobs[job] = nil; if not next(jobs) then owned[job.owner] = nil end end
	end
	job.finished = true
end

-- Always detach before notifying: callbacks may cancel or enqueue other jobs.
local function Done(job, sent, why)
	local done = job.done
	job.done = nil
	if done then ns.SafeCall("send done", done, sent, why) end
end
local function Finish(job, sent, why)
	if job.finished then return end
	Detach(job)
	Done(job, sent, why)
end
local function Earlier(a, b)
	if not a then return b end
	if not b then return a end
	return a.seq < b.seq and a or b
end

-- Cancel one bounded owner set. Snapshot and detach before callbacks: a callback may enqueue
-- replacement work without becoming part of the cancellation that triggered it.
local function CancelWhere(owner, guardKey, exact, why)
	local jobs = owner ~= nil and owned[owner]
	if not jobs then return 0 end
	local dropped, count = {}, 0
	for job in pairs(jobs) do
		if not exact or job.guardKey == guardKey then
			dropped[#dropped + 1] = job
			count = count + #job.parts - job.i + 1
		end
	end
	-- `owned` is a set, so its iteration order changes as unrelated modules allocate tables.
	-- Cancellation callbacks keep the queue's observable admission order.
	table.sort(dropped, function(a, b) return a.seq < b.seq end)
	for _, job in ipairs(dropped) do Detach(job) end
	for _, job in ipairs(dropped) do Done(job, false, why or "cancelled") end
	return count
end
function Comm.Cancel(owner)
	return CancelWhere(owner, nil, false, "cancelled")
end
-- Compatibility with v1.2's guarded queue: cancel exactly one owner/key capability while
-- preserving other work from the same owner, including an active whole transfer.
function Comm.CancelQueued(owner, guardKey, why)
	if owner == nil or guardKey == nil then return 0 end
	return CancelWhere(owner, guardKey, true, why or "cancelled")
end
local function DropQueue(why)
	local dropped = {}
	if active then dropped[#dropped + 1] = active end
	for _, lane in ipairs(lanes) do
		local job = lane.first
		while job do dropped[#dropped + 1] = job; job = job.next end
	end
	for _, job in ipairs(dropped) do Detach(job) end
	for _, job in ipairs(dropped) do Done(job, false, why) end
end

-- Accept both the transport lifecycle's owner/guard options and v1.2's capability guard:
-- { owner, key, permit(owner, key, dist, target, msg) }. Malformed capabilities fail closed.
local function NormalizeOptions(options)
	if options == nil then return nil end
	if type(options) ~= "table" then return false end
	local capability = options.key ~= nil or options.permit ~= nil
	if capability and (options.owner == nil or options.key == nil or type(options.permit) ~= "function") then return false end
	if options.guard ~= nil and type(options.guard) ~= "function" then return false end
	if not capability and options.owner == nil and options.guard == nil then return false end
	return {
		owner = options.owner, guard = options.guard,
		guardKey = capability and options.key or options.guardKey,
		permit = options.permit,
	}
end

-- (1.5.5) Where the relay carries the channel (Forever), whether a relay answers now or not: there
-- the channel delivers nothing, so no word goes on it (Enqueue, SendChatPart).
local function Forever() local R = ns.Relay return type(R) == "table" and R.On() == true end
-- A callback told once, whoever tells it (Relay.Out holds a word and tells it later).
local function Once(done)
	if done == nil then return nil end
	local told = false
	return function(...)
		if told then return end
		told = true
		return done(...)
	end
end
local function Enqueue(dist, parts, key, target, urgent, logged, done, options)
	SyncGuild()
	-- 1.4.3: on Forever the channel delivers nothing; what was for it goes to our relay by whisper
	-- (Relay.Out, which comes back here as WHISPER jobs). (1.5.5) Always, relay or none: Relay.Out
	-- holds it for one (HOLD_FOR), our guild hearing a single word at once, and tells its callback once.
	-- 1.5.4 made a channel job when no relay could be picked (lost), and when Relay.Out refused a word,
	-- with the callback it had told already.
	if dist == "CHANNEL" and Forever() and not (options and options.relayed) then
		local once = Once(done)
		if ns.Relay.Out(parts, logged, once, key, urgent, options) then return true end
		if once then ns.SafeCall("send done", once, false, "norelay") end
		return false
	end
	local job = { dist = dist, parts = parts, i = 1, key = key, target = target,
		urgent = urgent and true or false, logged = logged == true, done = done,
		owner = options and options.owner, guard = options and options.guard,
		guardKey = options and options.guardKey, permit = options and options.permit,
		guild = GetGuildInfo("player"), at = GetTime() }
	local dropped = {}
	local previous = key and keyed[key]
	-- A transfer already in flight remains whole. A waiting keyed job keeps the legacy
	-- coalescing contract: the newest payload/options replace it, a supplied callback replaces
	-- the old callback, and no callback keeps the one already waiting.
	local replace = previous and previous ~= active and not previous.started
	local replaced = replace and (#previous.parts - previous.i + 1) or 0
	-- Preflight without dropping anyone: an impossible large admission must leave
	-- unrelated queued work intact. Pending ordinary jobs are the only evictable ones.
	if queueSize - ordinarySize - replaced + #parts > MAX_QUEUE then
		Done(job, false, "full")
		return false
	end
	-- 1.4.0 (the queue's audit): the newest payload takes the waiting one's place in line, its
	-- sequence: a message re-sent on a timer behind a busy queue was put back at the end each time
	-- and never reached the front (a 15 s position stopped going out once 13 waited ahead of it).
	local seat
	if replace then
		if job.done == nil then job.done = previous.done end
		previous.done = nil
		seat = previous.seq
		Detach(previous)
	end
	while queueSize + #parts > MAX_QUEUE do
		-- Never discard an urgent job or a transfer that has already begun.
		local old = Earlier(lanes[3].first, lanes[4].first)
		if not old then break end
		Detach(old)
		dropped[#dropped + 1] = old
	end
	local accepted = queueSize + #parts <= MAX_QUEUE
	if accepted then
		local lane = lanes[(job.urgent and 1 or 3) + (#parts > 1 and 1 or 0)]
		if seat then
			-- (Each lane stays in sequence order: in after the last job ahead of its seat.)
			job.seq = seat
			local ahead = lane.last
			while ahead and ahead.seq > seat do ahead = ahead.prev end
			job.lane, job.prev = lane, ahead
			if ahead then job.next = ahead.next else job.next = lane.first end
			if job.next then job.next.prev = job else lane.last = job end
			if ahead then ahead.next = job else lane.first = job end
		else
			sequence = sequence + 1
			job.seq = sequence
			job.lane, job.prev = lane, lane.last
			if lane.last then lane.last.next = job else lane.first = job end
			lane.last = job
		end
		queueSize = queueSize + #parts
		if not job.urgent then ordinarySize = ordinarySize + #parts end
		if key then keyed[key] = job end
		if job.owner then
			local jobs = owned[job.owner] or {}
			owned[job.owner], jobs[job] = jobs, true
		end
	end
	-- Capacity eviction remains a terminal drop. Keyed coalescing above deliberately transfers
	-- only the currently registered callback, matching the queue's existing public contract.
	for _, old in ipairs(dropped) do Done(old, false, "dropped") end
	if not accepted then Done(job, false, "full") end
	return accepted
end

-- Other modules send small messages through here and register a handler per type.
--   Comm.Send("GUILD" | "CHANNEL", msg, dedupeKey, urgent, logged)
--   Comm.Handle("P1", function(dist, sender, text) ... end)
-- logged (1.0.0): a player's own words (a decree's), sent with the logged API where the client
-- has it (SendNow), as chat lines are: the server keeps them, so abuse can be reported.
--
-- The top-level types (the first two bytes, then "~"), one module each (1.1): a type registered
-- twice goes to the module loaded last, and the other never hears it again (the 1.1 review: the
-- loot notes and the census's route ask had one type). Pick a new one here first; tests/run.lua
-- fails on a type two files register, or one missing here.
--   Before any handler, here: K0 K1 (the realm key), H1 (hello), R1 R2 (census reports), and
--   C<id>:<n>:<of>: (pieces)
--   Comm.lua Q1 | Positions P1 | Layers L0 L1 | Hop LN LO LQ LR LX | HopSightings LY | Decree D1 | Channels M1 | ChatRooms M2
--   Inspect S1 U0 U1 | TabardsV2 U2 U3 U4 | King T1 T2 T3 | Court T4 T5 | Acts T6 T7 | Treasury T8 TB TE TQ TR TX
--   Bank T9 | Vox Y1 Y3 | Loot X1 XQ XB | Crafters W0 W1 WA WL WQ WR
--   Workshop HA HI HK HQ HR HS HT V1 V2 V3 V4 V5 V6 | Olympus Link (its own addon, Olympus_Link) DA DB DC DE DK DR DV DW
--   Authority H2 H3
--   GuildCharter GC (master's public card), QC (outsider's bounded ask), QD (corroborated Join card)
--   OfficerMuster OM (bounded, zone-only officer gathering, logged)
--   Other 1.1 work: Recruit J1 J3 | Alts AL | Filter BW | Dues FA FB FC FD FQ FS FU
--   Board G0 G1 GQ | Groups GA GL GM GR GW GX | Keys K3 K4 K5 K7 K8 | Channels N1 | Moderation O1 | ProfileEffects FX | The Watch MW | Treasury TA TD TW
--   Bank TL TN TO TS | Week Y2 | Wanted WS WY W4 W5, and 1.2.3's WK (a member's own kill or death,
--   and a reviewer's relay of one) WV (a reviewer's removal or void), and 1.2.4's W7 (a member's
--   avenged ask at login: digests of the Horde players his open deaths name). Reserved: J2 (#20's route
--   answer), FK (a 1.1 build's copy of the dues' amount from the Treasurer's client, read by nobody
--   now), WX (1.2.0 to 1.2.2's evidence whispered to a reviewer, read by nobody now).
--   Bank UP UQ UG (the guild keeper's grant, reader's ask and own-guild snapshot).
--   1.2 guild operations: War WZ (GUILD only; its bounded recovery snapshot may be chunked).
--   1.2, the King's minimap arrow: KingArrow K6 (the switch's lease, logged).
--   1.2, crafting requests: CraftRequests CQ (the board card, logged) CR (a claim and the parties'
--   words) CJ (the request's private chat) CK (the mediated rail, the review and the guild's fees
--   on direct sales: the parties' words to the fee desk, its answers, the debtors for the King),
--   all logged.
--   1.2, the Blood Arena (each one enveloped, <type>~<mode>1~<body>, and registered through
--   Arena.Handle): ArenaNet EP | ArenaChat EC EM | ArenaTest ER EH | Wallet ZH ZE ZN ZG ZD ZK ZC
--   ZW ZS ZQ ZL ZJ | Debts ZT ZX ZY ZR ZF | Stakes ZA ZV | Markets BM BO BS BK BV | MarketBank BF |
--   ArenaFights AF AG AC AW AR AS AN | ArenaLedger AE AB AQ AV AH AY AX | ArenaTourney AT AD |
--   ArenaProfile AP | HonorsNet IL ID IO | FarkleTable KI KA KO KP KG KY KH KK KT KE KQ KR KS KN KD |
--   ArenaMatch AM | Lottery LW | ArenaRoles AU | Records RK RD RA RR RV RS RT RH.
--   (The Lottery's: a day's bank publishes that day's winners for the Games tab's rankings.)
--   FarkleTable also registers KL at runtime (the design: the arbiter's floor under a drunk level),
--   without extending this legacy inventory.
--   (ArenaLedger's last two: 1.1.6's, a finished game's record, any game, from its players to the auditors, the games'
--   ledger; 1.2.3's, a fighter's signed half of a direct duel, the rankings' two halves.)
--   (Records', 1.2.4: the shared records of the games and duels that count, any holder's; 1.2.6's
--   last one, a live holder's signed validation of one record, so two holders relay it once both
--   original players are offline.)
--   (The King's arena words are kinds of the King's type, King.Register in ArenaRoles.lua.)
--   1.1.2, the right-click menus: Versions V7 V8 V9 | Workshop VR (the author asks for a bug report).
--   1.1.5, the guild masters' centurions and correspondents: Nominees NM (a list in parts, never chunked;
--   1.2.4: for the King's guild only the empty list the King's or a councillor's client sends to end
--   1.1.5's list of its centurions on older clients).
--   1.1.6, moderation: Moderation O2 (a guild's word with notice) | The Watch MR (the players' reports).
--   1.2, The Watch's judgments: Judgment MJ (a case to the King, the High Council's votes, his final
--   word; logged whispers between an officer's or a councillor's client and the King's).
--   1.1.6, the Missionary Church: Church NB NK | ChurchCount NV NS NL NR (whole messages, version 1).
--   1.1.6, chat moderation: WatchChat MD (lines deleted, recent lines deleted, timeouts and their
--   lifts, a guild master's Watchers, the Olympus moderators, a target's own word, appeals and their
--   answers, a case's decision told to its player; logged, over GUILD or the channel).
--   The chat warnings: ChatStrikes MS (from a third warning, the player's own report of the lines his
--   client refused to the moderation team, and its decisions; logged whispers only).
--   1.1.6, the War Room's squads: WarSquads WU (a guild's squad assignments, over GUILD) SC (a squad's chat, logged whispers).
--   1.2.4, voluntary Campaign VG (the King's public aggregate and keepers' private reports).
--   1.2.4, JusticeTasks JT (original signatures; private recovery by actual King, Council and verified author).
--   1.2.4, Carry XC (bounded consented historical quotes to the destination guild master, private only).
--   1.2.4, Dues FP FR (a payer's private receipt ask and the pinned Treasurer's observed receipt).
--   1.2.4, ChurchFullness NF (private coverage recovery between a current nominee and the guild desk).
--   1.2.6, global census CG (trusted anti-entropy snapshots; counts only, never census authority).
--   1.4.0, every server's census CX (a realm group's totals, carried to the other groups by players who were there).
--     1.5.2: version 2 adds bounded counts-only guild detail under its original group and faction.
--   1.5.2, MapNames MN (shared place labels from the King or signed High Council).
--   1.2.5, PlayerSightings PS (request-bound queries; private last-seen answers and withdrawals).
--   1.2.5.1, the Olympus Accord: Accord BT BQ (the first, a player's BattleTag to a moderation team
--   member who asked, a logged whisper; the second, that member's ask, on the Olympus channel).
--   Cover MC (a moderator's cover name, from their own client, over the channel and GUILD).
--   TagFollow TF (a sanction that follows a BattleTag: a code of it, the character, the kind; logged,
--   on the Olympus channel).
--   1.4.0, PrivatePresence PP (Private presence on or off, to the player's own guild over GUILD only).
--   Verify GV (guild verification: a verifier's approval or revocation of a guild and its master,
--   logged; any member's ask; a verifier's client's answer with the words and the guilds' starts).
--   1.4.3, Relay RL RM RG RY RX (Relay.lua: what the channel carried, by whisper where Forever delivers
--   nothing on it: origin to relay, relay to each guild's reporter, reporter to its guild over GUILD,
--   the relay's answer to a ping, and 1.4.6 a relay's copy to the other relays); 1.5.4 RW (guild
--   verification between relays alone: a verifier's decision, an ask, an answer to a relay's ask).
--   1.5.4, Relay RI RU (Relay.lua: a client's presentation of its version to a relay, and the relay
--   rules the author's client makes and the relays keep and hand on).
--   1.5.4, lists: Comm LS (words of one kind packed as one word where the relay carries the channel,
--   Comm.SendList: the Church's public rows, the guild masters' nominees, the shared block terms;
--   each receiver hands the words inside to their own handler, one by one, as if each had come on
--   its own).
--   1.5.4, modified builds: Builds BD (a guild master's, an officer's or a councillor's sighting of a
--   client whose version is no release, over GUILD and on the channel; the record the right-click
--   menu and /oly builds show, and the lock on such a client's words).
--   1.5.5, RelayTree RN RF RQ RC | Relay RJ RB | RelayFallback RE RO | Data QA
local handlers = {}
local dispatchSender, injectedSender
local function Dispatch(handler, dist, sender, text)
	local previous = dispatchSender
	local kind = text:sub(1, 2)
	-- Only a relay envelope can lend its admission to its own origin while unwrapped.
	dispatchSender = ((dist == "WHISPER" and (kind == "RL" or kind == "RM" or kind == "RX" or kind == "RW"))
		or (dist == "GUILD" and kind == "RG")) and sender or nil
	local ok, err = pcall(handler, dist, sender, text)
	dispatchSender = previous
	if not ok then error(err, 0) end
end
-- 1.1 (Moderation.lua): a client the moderators took off (net-off) sends none of what they hide.
local function Held(msg)
	local M = ns.Moderation
	return M ~= nil and not M.missing and M.Blocks(msg) == true
end
-- Quiet presence (1.2.5.1, Core.lua): while it is on, no word that says this character is online,
-- or where it is, leaves this client. Each module leaves its own out (the hello, the census report,
-- the layer...); these words are held here too, on the whole message a module hands over (Send,
-- Whisper, SendChunked, and Arena.Send for the arena's) and again on each part as the queue sends
-- it, so what waited in the queue when it began stays home too. A census report goes in pieces
-- that name no type: Comm.Broadcast holds it itself. Nothing says it went quiet: no withdrawal goes
-- either, and what was told before expires on the other clients as after a logout. A read (a
-- census, sighting or layer request) and a chat line the player types still go. The words a
-- player's own click posts (a muster call, a decree, a list he changed) go too; only their timed
-- repeats stay home, each in its module (King.lua, KingArrow.lua, Acts.lua, OfficerMuster.lua).
Comm.QUIET_WORDS = {
	"^H1~",         -- the hello
	"^P1~",         -- a dot on the guildmates' maps (Positions.lua)
	"^L[01]~",      -- a layer announced or taken back (Layers.lua)
	"^L[ON]~",      -- a layer-hop offer, or its "not now" (Hop.lua)
	"^LY~[RX]~",    -- an answer about the King's layer, or its withdrawal (HopSightings.lua)
	"^PS~[RBXW]~",  -- a player-sighting answer, or its withdrawal (PlayerSightings.lua)
	"^T1~[PQ]~",    -- the King's crown on the map, or its removal (King.lua)
	"^T1~o~",       -- (1.5.4) the King's presence (King.lua)
	"^CG~%d+~S~",   -- a global census snapshot (Data.lua)
	"^CX~%d+~S~",   -- carried origin totals or guild detail (Data.lua)
	"^V[248]~",     -- a roll call's answer, the author's presence, a version check's answer (Workshop.lua, Versions.lua)
	"^NK~1~[pqa]~", -- the Church's presence and direct keeper discovery (Church.lua)
	"^D[VW]~",      -- Olympus Link's confirmer and watcher presence (its own addon, Olympus_Link, when installed)
	-- The arena auditors' and fee receiver's hello, and an auditor's whispered check of a bank
	-- snapshot (ZQ~<mode>~H~<epoch>~<seq>, Wallet.CheckSnapshot), which marks him as heard too: a
	-- check held back is not sent again, and the bank prunes at the next snapshot (Wallet.lua).
	"^ZQ~%u%d+~H~",
	"^T1~[CZ]~",    -- the King's court where he stands, or its closing (Court.lua)
	"^WS~[RSX]~",   -- a Wanted reviewer's lease or its No, a sighting, or its taking back (Wanted.lua)
	"^H[AK]~",      -- a councillor's "available for help", or his "got it" to an ask (Workshop.lua)
	"^TD~",         -- a keeper's "taking donations", with his zone (Treasury.lua)
	"^ZV~%u%d+~",   -- an arbiter's availability, with his zone (Stakes.lua)
	"^U[234]~",     -- the King's tabard collector lease, and the tabard reports whispered to it (TabardsV2.lua)
	"^FX~",         -- a profile presentation or its session: heartbeats, stop and close (ProfileEffects.lua)
	"^W[01AL]~",    -- a crafter's listing or its removal, his answer to an ask, his recipe list (Crafters.lua)
}
local function QuietHolds(msg)
	if type(msg) ~= "string" or not Quiet() then return false end
	for _, pattern in ipairs(Comm.QUIET_WORDS) do
		if msg:find(pattern) then
			stats.quiet = (stats.quiet or 0) + 1
			return true
		end
	end
	return false
end
Comm.QuietHolds = QuietHolds
local function Refuse(done, why)
	if done then ns.SafeCall("send done", done, false, why) end
	return false
end
local SEND_DISTS = { GUILD = true, CHANNEL = true, PARTY = true, RAID = true }
-- done runs exactly once, including rejection. options.owner permits cancellation;
-- options.guard, or options.permit for a capability guard, is rechecked before each game send.
function Comm.Send(dist, msg, key, urgent, logged, done, options)
	options = NormalizeOptions(options)
	if options == false then return Refuse(done, "guard") end
	if not SEND_DISTS[dist] then return Refuse(done, "target") end
	if type(msg) ~= "string" or #msg > 255 then return Refuse(done, "size") end
	-- Keep the public completion contract: GUILD without a game guild is "guild"; a
	-- non-Olympus character on another distribution is "left".
	if dist == "GUILD" and not IsInGuild() then return Refuse(done, "guild") end
	if not ns.IsMember() then return Refuse(done, "left") end
	if Held(msg) then return Refuse(done, "held") end
	if QuietHolds(msg) then return Refuse(done, "quiet") end
	return Enqueue(dist, { msg }, key, nil, urgent, logged, done, options)
end
-- An addon message to one player only (answers to the King, Throne tab). logged (1.1): a
-- player's own words (a Board note), with the logged API, as Comm.Send. done: see Enqueue.
function Comm.Whisper(target, msg, key, urgent, logged, done, options)
	options = NormalizeOptions(options)
	if options == false then return Refuse(done, "guard") end
	if type(target) ~= "string" or target == "" then return Refuse(done, "target") end
	if type(msg) ~= "string" or #msg > 255 then return Refuse(done, "size") end
	if not ns.IsMember() then return Refuse(done, "left") end
	if Held(msg) then return Refuse(done, "held") end
	if QuietHolds(msg) then return Refuse(done, "quiet") end
	return Enqueue("WHISPER", { msg }, key, target, urgent, logged, done, options)
end
-- A bounded whole transfer: accept all pieces or none, finish once after their send
-- APIs succeed (not a remote receipt). A failed piece cancels its unsent tail.
function Comm.SendBatch(dist, pieces, key, target, urgent, done, options)
	options = NormalizeOptions(options)
	if options == false then return Refuse(done, "guard") end
	if dist == "GUILD" and not IsInGuild() then return Refuse(done, "guild") end
	if not ns.IsMember() then return Refuse(done, "left") end
	if not SEND_DISTS[dist] and dist ~= "WHISPER" then return Refuse(done, "target") end
	if dist == "WHISPER" and (type(target) ~= "string" or target == "") then return Refuse(done, "target") end
	if type(pieces) ~= "table" or #pieces < 1 or #pieces > Codec.MAX_CHUNKS then return Refuse(done, "size") end
	local copy = {}
	for i = 1, #pieces do
		local msg = pieces[i]
		if type(msg) ~= "string" or #msg > 255 then return Refuse(done, "size") end
		if Held(msg) then return Refuse(done, "held") end
		if QuietHolds(msg) then return Refuse(done, "quiet") end
		copy[i] = msg
	end
	return Enqueue(dist, copy, key, target, urgent, false, done, options)
end
function Comm.Handle(msgType, fn)
	handlers[msgType] = fn
end
-- 1.1: [key] = fn(dist, sender, text), handed every piece heard over GUILD or the channel while set.
Comm.pieceHooks = {}
-- Long payloads (> 255 bytes) go through the same chunking as reports; urgent ones (a
-- question to the army) ahead of the census, their pieces still in order. On the channel, or
-- over GUILD (1.0.0), where only the types in GUILD_PIECES are put together again. key (1.5.4,
-- Comm.SendList): a newer payload of the key takes a waiting one's place, as Comm.Send's does.
function Comm.SendChunked(payload, urgent, dist, done, options, key)
	dist = dist == "GUILD" and "GUILD" or "CHANNEL"
	if type(payload) ~= "string" then return Refuse(done, "size") end
	if Held(payload) then return Refuse(done, "held") end
	if QuietHolds(payload) then return Refuse(done, "quiet") end
	if options ~= nil and type(options) ~= "table" then return Refuse(done, "guard") end
	msgId = (msgId + 1) % 1000
	local guard = options and options.guard
	local guarded = {
		owner = options and options.owner,
		key = options and options.key,
		permit = options and options.permit,
		guardKey = options and options.guardKey,
		guard = function()
		return not Held(payload) and not QuietHolds(payload) and (not guard or guard() == true)
	end }
	return Comm.SendBatch(dist, Codec.Chunk(payload, tostring(msgId)), key, nil, urgent, done, guarded)
end

-- (1.5.4) A list of words of one kind as one word. The Church's public rows first (Count.SendPublic:
-- up to 22 rows of two rankings, every half hour): on Forever each row went by the relay on its own, and
-- there another client's words pass a reporter's trickle one by one, keyed by their type in the
-- relay's queue (a newer row took the waiting row's place), so a reporter got one to four rows of the
-- 22, and the Church's scores were wrong in every guild but the desk's. The rows now go packed in one
-- chunked word, LS, which the relay collects whole and hands to each reporter whole, within bounds
-- (Relay.lua, ListSet); every receiver splits it and hands each row to its own handler as if it had
-- come on its own from the same sender, so what each handler trusts (the Church's keeper) is asked
-- where it always was. Where the channel works (Relay.On() false) each word goes as before, one
-- channel message each: nothing changes on those realms, and no older client reads a list. The
-- guild masters' nominees (NM, Nominees.Send) and the shared block terms (BW, Filter.SendAll) go
-- the same way; another list is one line for its sender and one in Relay.LIST_KINDS.
--   LS~1~<kind>~<n>~<word>`<word>...   kind: the words' own type (two letters); n: how many
-- The separator is the backtick, plain text: Comm takes every control byte and the escape mark out
-- of each message as it arrives (Codec.Plain, 0.9.2), before the pieces are put together, so the
-- unit separator (\30) never reached a handler; the byte 255 of the first cut travels in the game's
-- guild messages (measured in game) but that its whispers carry it, which carry the relay's lists,
-- could not be shown before the release. No name or guild name has a backtick (the game allows
-- neither), the block terms are letters and digits (Filter.Term), and a list with one in a word goes
-- word by word, as any list past the bounds.
Comm.LIST_SEP = "`"
Comm.LIST_MAX = 64        -- words in one list at most
Comm.LIST_WORD_MAX = 255  -- bytes of one word at most (a channel message's)
-- The list as one word, or nil and why: a kind that is not a type (or a list's), no words, too many,
-- a word that is not a string, empty, too long, of another kind, or holding the separator.
function Comm.PackList(kind, words)
	if type(kind) ~= "string" or not kind:match("^%u%w$") or kind == "LS" then return nil, "kind" end
	if type(words) ~= "table" or #words < 1 then return nil, "empty" end
	if #words > Comm.LIST_MAX then return nil, "count" end
	for _, word in ipairs(words) do
		if type(word) ~= "string" or #word == 0 or #word > Comm.LIST_WORD_MAX then return nil, "size" end
		if word:sub(1, 3) ~= kind .. "~" then return nil, "mixed" end
		if word:find(Comm.LIST_SEP, 1, true) then return nil, "separator" end
	end
	return ("LS~1~%s~%d~%s"):format(kind, #words, table.concat(words, Comm.LIST_SEP))
end
-- The kind and the words of a list heard, or nil and why: the same bounds, a count that does not
-- match its words, a word of another kind.
function Comm.UnpackList(text)
	if type(text) ~= "string" then return nil, "shape" end
	local kind, n, body = text:match("^LS~1~(%u%w)~(%d+)~(.*)$")
	n = tonumber(n)
	if not kind or kind == "LS" or not n or n < 1 or n > Comm.LIST_MAX then return nil, "shape" end
	local words = Codec.Split(body, Comm.LIST_SEP)
	if #words ~= n then return nil, "count" end
	for _, word in ipairs(words) do
		if #word == 0 or #word > Comm.LIST_WORD_MAX or word:sub(1, 3) ~= kind .. "~" then return nil, "word" end
	end
	return kind, words
end
-- Whether the list goes as one word here: where the relay carries the channel, and within the
-- relay's pieces (Relay.LIST_MAX_PIECES) and LIST_MAX words. Else its words go one by one, as
-- before 1.5.4 (a guild master's longest list of nominees with realms in every name, the block
-- terms' fullest list): sent whole that way, never cut short, and counted (listsSplit).
local function OneWord(kind, words)
	if not RelayOn() then return nil end
	local text, why = Comm.PackList(kind, words)
	if not text then return nil, why end
	local R = ns.Relay
	local most = type(R) == "table" and tonumber(R.LIST_MAX_PIECES) or 10
	if math.ceil(#text / Codec.CHUNK) > most then return nil, "pieces" end
	return text
end
-- How many places in the queue the list takes here: its pieces as one word, or one for each word
-- (Count.SendPublic keeps the census's room past them).
function Comm.ListRoom(kind, words)
	local text = OneWord(kind, words)
	if text then return math.ceil(#text / Codec.CHUNK) end
	return type(words) == "table" and #words or 0
end
-- Sends the list: as one chunked LS word where the relay carries the channel (Comm.SendChunked,
-- never urgent), else each word as one channel message, as before. options as Comm.Send's; key:
-- as the words were keyed before (Nominees "nominees", Filter "filterterms"), word i by key .. i,
-- the list word by key itself, so a newer list takes a waiting one's place. True when every word
-- was handed to the queue; false and why when the list is refused (no words, a word of another
-- kind or with the separator).
function Comm.SendList(kind, words, options, key)
	local _, why = Comm.PackList(kind, words)
	if why == "kind" or why == "empty" or why == "mixed" then return false, why end
	local text, split = OneWord(kind, words)
	if text then return Comm.SendChunked(text, false, "CHANNEL", nil, options, key) == true end
	if split then
		stats.listsSplit = (stats.listsSplit or 0) + 1
		ns.Log("list %s: %d words (%s): one by one, past what the relay carries as one", kind, #words, split)
	end
	local all = true
	for i, word in ipairs(words) do
		if not Comm.Send("CHANNEL", word, key and (key .. i) or nil, false, false, nil, options) then all = false end
	end
	return all
end
-- A list heard: its words to their own handler, one by one, as if each had come on its own from the
-- same sender, so each handler asks of the sender what it always asked (the Church's rows: the
-- keeper). The sender paid the admission above once, for the whole list, and its words do not pay
-- again (a full list is more than ADMIT_BURST). Bounds: the declared kind alone, one with a handler,
-- LIST_MAX words of LIST_WORD_MAX bytes each, never a list in a list; anything else is dropped whole
-- and counted (Comm.Stats: lists, listWords, listsBad). On the channel alone, where lists are sent.
Comm.Handle("LS", function(dist, sender, text)
	local kind, words = Comm.UnpackList(text)
	local handler = kind and handlers[kind]
	if dist ~= "CHANNEL" or not handler then
		stats.listsBad = (stats.listsBad or 0) + 1
		return
	end
	stats.lists = (stats.lists or 0) + 1
	for _, word in ipairs(words) do
		stats.listWords = (stats.listWords or 0) + 1
		Count(stats.byType, "ch:" .. kind)
		ns.SafeCall("list word", handler, dist, sender, word)
	end
end)
function Comm.ChannelReady()
	return channelIndex > 0 or RelayOn()
end
-- Messages waiting to go out, one each SEND_INTERVAL (chat lines apart).
function Comm.QueueSize()
	return queueSize
end
-- How many more fit before the oldest waiting message is dropped (1.1: the King's key rotation
-- hands out no more than that, Keys.lua).
function Comm.QueueRoom()
	return MAX_QUEUE - queueSize
end

-- Chat lines wait in a short lane of their own: they never go through Enqueue, so they can
-- never push report chunks out of MAX_QUEUE. done(sent, why) is called once the part went out
-- (true) or was dropped (false, why): "moved" the channel changed before it left (a new realm
-- key), "late" it waited CHAT_TTL, "failed" the game refused it, "left" we are out of an Olympus
-- guild. Each part carries the channel it was written for, and never goes out on another one
-- (GitHub #34: a line typed for one channel's audience is not sent to the next). line (1.1.1):
-- any value the parts of one line share, for Comm.DropLine. guard is checked now and again at
-- the actual game send, like Comm.Send's options.guard. Returns false when the lane is full,
-- guard refuses, or while we are on no channel.
function Comm.SendChat(msg, done, line, guard)
	if not (joinedName or RelayOn()) or #chatQueue >= CHAT_QUEUE or Held(msg) then return false end
	if guard ~= nil then
		if type(guard) ~= "function" then return false end
		local ok, valid = pcall(guard)
		if not ok or valid ~= true then return false end
	end
	-- (1.5.0) Where the game delivers the player's typed text and not the hidden message
	-- (Forever), a tier's line goes as his own text in the joined channel too (ChatHall.lua):
	-- the same channel hears it at once, every other lane and guild by the hidden way below.
	local H = ns.ChatHall
	if type(H) == "table" and H.On() then pcall(H.Send, msg) end
	chatQueue[#chatQueue + 1] = { msg = msg, done = done, t = GetTime(), channel = joinedName, line = line, guard = guard }
	return true
end
function Comm.ChatRoom()
	return CHAT_QUEUE - #chatQueue
end
-- The parts of chat line `line` still in the lane leave it unsent, each done(false, why) (1.1.1:
-- once one part of a line did not go out, Channels.Send drops the rest, so no one reads a line
-- without its start). Returns how many.
function Comm.DropLine(line, why)
	if line == nil then return 0 end
	local kept, dropped = {}, {}
	for _, item in ipairs(chatQueue) do
		if item.line == line then dropped[#dropped + 1] = item else kept[#kept + 1] = item end
	end
	if #dropped == 0 then return 0 end
	wipe(chatQueue)
	for i, item in ipairs(kept) do chatQueue[i] = item end
	for _, item in ipairs(dropped) do
		if item.done then ns.SafeCall("chat drop", item.done, false, why) end
	end
	return #dropped
end

local function IsSuccess(res)
	-- Older clients return a boolean, newer ones Enum.SendAddonMessageResult (0 = success).
	return res == nil or res == true or res == 0
end

-- 1.4.0 (the queue's audit: a chat lockdown lost every waiting job, one refusal a tick, and one
-- throttled piece ended a whole transfer). The game's answers that mean "not now":
-- Enum.SendAddonMessageResult's AddonMessageThrottle (3), ChannelThrottle (8), GeneralError (9)
-- and AddOnMessageLockdown (11). The job keeps its place and the whole pump waits, longer after
-- each refusal in a row (RETRY_WAIT); a job refused RETRY_MAX times for a throttle or an error
-- ends as before. A lockdown never counts against a job: nothing leaves while it lasts
-- (ns.ChatLocked, C_ChatInfo.InChatMessagingLockdown where the client has it), and a transfer
-- already begun still ends "late" past its receivers' 60 seconds. Any other answer (an offline
-- target, 12; an old client's false) ends the job at once, as before.
local LOCKDOWN = 11
local RETRYABLE = { [3] = true, [8] = true, [9] = true, [LOCKDOWN] = true }
local RETRY_WAIT = { 2, 4, 8, 15, 30 } -- seconds the pump waits after 1, 2, 3, 4, 5+ refusals in a row
local RETRY_MAX = 5
-- (Named apart from the channel guard's Locked further down, a different thing.)
local function InLockdown() return ns.ChatLocked ~= nil and ns.ChatLocked() == true end

-- Player text goes through the logged API, Blizzard's function for plain text payloads
-- (receivers get CHAT_MSG_ADDON_LOGGED). Clients without it use the usual one.
local function SendNow(dist, msg, logged, whisperTo)
	-- (1.4.0: during a chat lockdown the game refuses it anyway: no call, no failure logged.)
	if InLockdown() then
		stats.locked = (stats.locked or 0) + 1
		return false, LOCKDOWN
	end
	-- (A whisper goes to the name the server finds: ns.TellName. Group distributions have no target.)
	local target = dist == "CHANNEL" and channelIndex or (dist == "WHISPER" and ns.TellName(whisperTo) or nil)
	local send = logged and C_ChatInfo.SendAddonMessageLogged or C_ChatInfo.SendAddonMessage
	local ok, res = pcall(send, ns.PREFIX, msg, dist, target)
	if ok and IsSuccess(res) then
		stats.sent = stats.sent + 1
		refusedInRow = 0
		-- (1.5.4, the dev's live report: "No player named <a reporter> is currently playing" kept
		-- filling his chat.) The server's line answers the whisper that actually went, and a whisper
		-- can wait in the queue (a relay's batch behind thirty reporters' turns) far longer than the
		-- quiet window opened when it was handed in. The window opens again now, whoever sent it.
		if dist == "WHISPER" then
			local A = ns.Accord
			if type(A) == "table" and type(A.Quiet) == "function" then pcall(A.Quiet, whisperTo) end
		end
		if dist == "CHANNEL" then laneRefused = 0 end -- (1.4.1: the channel takes our words)
		return true
	end
	if ok and RETRYABLE[res] then
		refusedInRow = refusedInRow + 1
		waitUntil = GetTime() + RETRY_WAIT[math.min(refusedInRow, #RETRY_WAIT)]
	end
	-- (1.4.1) InvalidChannel on the channel we are on (its number still ours): counted towards the
	-- next lane; the census is asked again a moment later, so the count settles within seconds
	-- whatever else this client has to say. Not while we are off it (a stale number says nothing).
	if ok and res == 7 and dist == "CHANNEL" and channelIndex > 0 and joinedName
		and (GetChannelName(joinedName) or 0) == channelIndex then
		laneRefused = laneRefused + 1
		if laneRefused >= Comm.LANE_AFTER then
			laneBad[Lane()] = true
			Comm.NextLane(("InvalidChannel x%d on %s"):format(laneRefused, joinedName))
		elseif not laneProbe then
			laneProbe = true
			ns.After(Comm.LANE_PROBE, "channel probe", function() laneProbe = false Comm.AskCensus(true) end)
		end
	end
	stats.fails = stats.fails + 1
	stats.lastFail = ("%s %s"):format(dist, tostring(res))
	ns.Log("send failed on %s: %s", dist, tostring(res))
	-- Preserve newer clients' numeric result for Arena retry policy. Older clients return
	-- false on refusal; that remains a normal "failed" outcome, while a thrown call is "error".
	if ok then return false, res end
	return false, "error"
end

-- The Join screen's own addon whispers (1.1, Fern's #20, Recruit.lua): outside an Olympus guild
-- the addon sends nothing else, and these only: J1 (which guild should I ask? to a member /who
-- found), J3 (my request, with the whisper the player sends himself), and QC (a bounded
-- charter request to that same queried member), straight to that one player, never through the queue (Pump sends nothing for a
-- non-member). A member of an Olympus guild sends neither.
local OUTSIDE_TYPES = { J1 = true, J3 = true, QC = true }
function Comm.WhisperOutside(target, msg)
	-- (1.2.5.1: a member who has not accepted the Olympus Accord yet sends none of these either.)
	if ns.InOlympusGuild() or type(target) ~= "string" or target == "" or type(msg) ~= "string" then return false end
	if not OUTSIDE_TYPES[msg:sub(1, 2)] or msg:sub(3, 3) ~= "~" or #msg > 255 then return false end
	return SendNow("WHISPER", msg, false, target)
end
-- It hears J2 route answers and QD charter cards there, only by whisper. Recruit and
-- GuildCharter each check the queried sender and their bounded response window.
local outsideHandler
function Comm.HandleOutside(fn) outsideHandler = fn end

-- Every chat part still waiting is dropped, and its sender is told why (Comm.SendChat).
local function DropChat(why)
	local items = {}
	for i, item in ipairs(chatQueue) do items[i] = item end
	wipe(chatQueue)
	if why == "moved" then stats.chatMoved = stats.chatMoved + #items end
	for _, item in ipairs(items) do
		if item.done then ns.SafeCall("chat drop", item.done, false, why) end
	end
end

-- Peer elections, delayed reports and queued work belong to one guild session.
-- An Olympus-to-Olympus move keeps the channel, but must not keep that session.
SyncGuild = function()
	local guild = GetGuildInfo("player")
	if guild == peerGuild then return end
	peerGuild = guild
	guildSession = guildSession + 1
	guildAsm, outsiderAsm, whisperAsm = Codec.NewAssembler(), Codec.NewAssembler(), Codec.NewAssembler()
	wipe(peers); wipe(peerRealm); wipe(peerVersion); wipe(peerSealed); wipe(peerZone); wipe(peerBank)
	wipe(peerLane); wipe(peerLaneUsable); wipe(peerRelay)
	wipe(heardOwn); wipe(benched)
	watch, lastKeyAsk, early = nil, nil, nil
	crossedAt, lastBroadcast, lastAnswer = -math.huge, 0, -math.huge
	Comm.isReporter, Comm.isRunnerUp, Comm.reporterName, Comm.lastReport = nil, nil, nil, nil
	guildChangedAt = ns.Now()
	lastHello, Comm.lastKeyAnswer = 0, nil
	askTries, heardAsk, askedAgain = 0, -math.huge, false
	stats.asked, stats.askSkipped = 0, 0
	-- Moving between Olympus guilds invalidates the old guild session; leaving the
	-- federation keeps the established public completion reason, "left".
	DropQueue(ns.IsMember() and "guild" or "left")
	DropChat("left")
end

-- GitHub #34: the chat parts written for another channel than the one we are on now are dropped
-- ("moved"), the others keep their place. Comm.JoinChannel drops the lane when the channel
-- changes; this second guard holds whatever path changed joinedName. The same channel given
-- another number by the game is no move (Pump follows its number).
local function DropMoved()
	local kept, moved = {}, {}
	for _, item in ipairs(chatQueue) do
		if item.channel == joinedName then kept[#kept + 1] = item else moved[#moved + 1] = item end
	end
	if #moved == 0 then return end
	wipe(chatQueue)
	for i, item in ipairs(kept) do chatQueue[i] = item end
	stats.chatMoved = stats.chatMoved + #moved
	for _, item in ipairs(moved) do
		if item.done then ns.SafeCall("chat drop", item.done, false, "moved") end
	end
end

-- The common path reads lane heads directly; only a missing channel needs to
-- walk past its blocked messages to find guild traffic or a whisper.
local function Ready(lane)
	local job = lane.first
	while job and job.dist == "CHANNEL" and channelIndex <= 0 do job = job.next end
	return job
end
local function NextJob(singles)
	if singles then return Ready(lanes[1]) or Ready(lanes[3]) end
	local urgent = Earlier(Ready(lanes[1]), Ready(lanes[2]))
	if urgent then return urgent end
	return Earlier(Ready(lanes[3]), Ready(lanes[4]))
end
local function Valid(job, now)
	if job.guild ~= GetGuildInfo("player") then return false, "guild" end
	if job.started then
		if now - job.started >= (#job.parts > 30 and 70 or 60) then return false, "late" end
		if job.dist == "CHANNEL" and (job.channel ~= joinedName or channelIndex <= 0) then return false, "moved" end
	end
	if job.guard then
		local ok, valid, why = pcall(job.guard)
		if not ok then
			if ns.CaptureError then pcall(ns.CaptureError, "send guard", valid) end
			return false, "guard-error"
		end
		if valid ~= true then return false, why or "invalid" end
	end
	if job.permit then
		local ok, valid, why = pcall(job.permit, job.owner, job.guardKey, job.dist, job.target, job.parts[job.i])
		if not ok then
			if ns.CaptureError then pcall(ns.CaptureError, "send permit", valid) end
			return false, "guard-error"
		end
		if valid ~= true then return false, why or "cancelled" end
	end
	if Held(job.parts[job.i]) then return false, "held" end
	if QuietHolds(job.parts[job.i]) then return false, "quiet" end
	return true
end
local function SendJob(job, now)
	local valid, why = Valid(job, now)
	if job.finished then return false end
	if not valid then Finish(job, false, why); return false end
	if #job.parts > 1 and not job.started then
		Unlink(job)
		job.started, job.channel = now, joinedName
		active, batchSlot = job, 2 -- this send is the first fragment slot
	end
	local sent, why = SendNow(job.dist, job.parts[job.i], job.logged, job.target)
	if not sent then
		-- (1.4.0: "not now" keeps the job in its place, RETRY_MAX tries for a throttle or an error.)
		if RETRYABLE[why] then
			if why ~= LOCKDOWN then job.tries = (job.tries or 0) + 1 end
			if (job.tries or 0) < RETRY_MAX then
				stats.retried = (stats.retried or 0) + 1
				return true
			end
		end
		Finish(job, false, why or "failed")
		return true -- a game API was called: do not spend another slot this tick
	end
	if job.lane and not job.urgent then ordinarySize = ordinarySize - 1 end
	job.i = job.i + 1
	queueSize = queueSize - 1
	if job.i > #job.parts then Finish(job, true) end
	return true
end
local function SendChatPart()
	lastWasChat = true
	local item = table.remove(chatQueue, 1)
	if item.guard then
		local ok, valid, why = pcall(item.guard)
		if not ok then
			if ns.CaptureError then pcall(ns.CaptureError, "chat send guard", valid) end
			why = "guard-error"
		elseif valid ~= true then
			why = why or "invalid"
		else
			why = nil
		end
		if why then
			if item.done then ns.SafeCall("chat sent", item.done, false, why) end
			return
		end
	end
	-- (1.4.3) On Forever a chat line goes by the relay, logged at hop 1. (1.5.5) Never on the channel
	-- there, relay or none (Relay.Out: our guild has it at once, the line waits for a relay); its
	-- callback hears how it went once, when it left or was dropped ("norelay" past HOLD_FOR).
	if Forever() then
		local once = Once(item.done)
		if not ns.Relay.Out({ item.msg }, true, once, nil, true) and once then ns.SafeCall("chat sent", once, false, "norelay") end
		return
	end
	local sent = SendNow("CHANNEL", item.msg, true)
	if item.done then ns.SafeCall("chat sent", item.done, sent, (not sent) and "failed" or nil) end
end

-- The jobs not begun that waited HOLD_MAX or more (only after the pump held them: a lockdown).
-- Their done hears "dropped", as for a full queue's eviction: what must be delivered (the arena's
-- obligations, ArenaNet's retries) is offered again by its module, the rest is no longer news.
local function DropStale(now)
	local stale = {}
	for _, lane in ipairs(lanes) do
		local job = lane.first
		while job do
			if not job.started and job.at and now - job.at >= HOLD_MAX then stale[#stale + 1] = job end
			job = job.next
		end
	end
	table.sort(stale, function(a, b) return a.seq < b.seq end)
	for _, job in ipairs(stale) do Detach(job) end
	for _, job in ipairs(stale) do Done(job, false, "dropped") end
	return #stale
end

local function PumpOnce()
	SyncGuild()
	if queueSize == 0 and not chatQueue[1] then return end
	if not ns.IsMember() then
		DropQueue("left")
		DropChat("left")
		return
	end
	-- The game can reuse a departed channel's numeric ID for a different audience.
	if channelIndex > 0 and joinedName and GetChannelName then
		local id = GetChannelName(joinedName) or 0
		if id ~= channelIndex then
			ns.Log("channel %s is now #%d (was #%d)", joinedName, id, channelIndex)
			channelIndex = id
		end
	end
	if chatQueue[1] then DropMoved() end
	local now = GetTime()
	while chatQueue[1] and now - chatQueue[1].t > CHAT_TTL do
		local item = table.remove(chatQueue, 1)
		if item.done then ns.SafeCall("chat drop", item.done, false, "late") end
	end
	-- 1.4.0: nothing leaves during a chat lockdown (the jobs wait in their places), nor before the
	-- wait after the game's last "not now" is over (RETRY_WAIT). Once the hold is over, what waited
	-- HOLD_MAX or more and has not begun is dropped (DropStale).
	if InLockdown() or now < waitUntil then
		heldSince = heldSince or now
		return
	end
	if heldSince then
		heldSince = nil
		DropStale(now)
	end
	-- Invalid jobs consume no network slot. Bound the pass even if a callback adds work.
	for _ = 1, MAX_QUEUE do
		if active then
			local current = active
			local valid, why = Valid(current, now)
			if not valid then Finish(current, false, why) end
		end
		local chat = chatQueue[1] and (channelIndex > 0 or RelayOn()) -- (1.4.3: the relay carries the chat too)
		local job
		if active then
			local slot = BATCH_SLOTS[batchSlot]
			batchSlot = batchSlot % #BATCH_SLOTS + 1
			if slot == "chat" and chat then SendChatPart(); return end
			if slot ~= "part" then job = NextJob(true) end
			if not job and slot ~= "part" and chat then SendChatPart(); return end
			job = job or active
		else
			job = NextJob(false)
			-- Outside a transfer, retain the existing chat/report alternation.
			if chat and not (lastWasChat and job) then SendChatPart(); return end
		end
		if not job then return end
		lastWasChat = false
		if SendJob(job, now) then return end
	end
end
-- One part a pump as ever; a relay's client (Relay.lua: it forwards every word to every guild's
-- reporter and the other relays) PUMP_PARTS_RELAY a pump (1.5.0: at one part every 1.2 s the
-- dev's relay fell behind, whole reports and the signed lists waited and fell out of the queue;
-- four parts a pump is 3.3 a second, under the server's limit of ten).
Comm.PUMP_PARTS_RELAY = 4
-- (1.5.5) A serving provisional relay (RelayFallback.lua) PUMP_PARTS_PROVISIONAL: 100 whispers a
-- minute for its registrants' snapshots, half a signed relay's.
Comm.PUMP_PARTS_PROVISIONAL = 2
local function Pump()
	local R = ns.Relay
	local parts = 1
	if type(R) == "table" and R.On() then
		if R.IsRelay(ns.me) then parts = Comm.PUMP_PARTS_RELAY
		elseif type(R.ServingProvisional) == "function" and R.ServingProvisional() then parts = Comm.PUMP_PARTS_PROVISIONAL end
	end
	for _ = 1, parts do
		if queueSize == 0 and not chatQueue[1] then return end
		PumpOnce()
	end
end
Comm.Pump = Pump -- for tests

---------------------------------------------------------------------------
-- The shared channel. Without a key it is the public "OlympusNet". With a realm key (set by
-- an officer with /oly key, then passed to guildmates over GUILD messages, which the server
-- only delivers to members of that guild) the channel gets a name derived from the key and
-- the key as its password: outsiders can neither find it nor join it, edited code or not.
---------------------------------------------------------------------------

local function Hash36(text)
	local h1, h2 = 5381, 52711
	for i = 1, #text do
		local c = text:byte(i)
		h1 = (h1 * 33 + c) % 2147483647
		h2 = (h2 * 31 + c * 7) % 2147483647
	end
	local digits, out, n = "0123456789abcdefghijklmnopqrstuvwxyz", "", h1 * 1000 + (h2 % 1000)
	for _ = 1, 8 do
		local d = n % 36
		out = digits:sub(d + 1, d + 1) .. out
		n = math.floor(n / 36)
	end
	return out
end
Comm.Hash36 = Hash36

-- 1.4.1 (launch night, 2026-11-04: on WoW: Forever the game refused every send on "OlympusNet"
-- with InvalidChannel (7) while we were on it, and any other channel, new or old, took them; the
-- whole army was on that one channel and no guild heard another). The channel lane: the name a
-- client joins is the usual one, then the usual one with 1, 2 ... LANE_MAX after it. A client moves
-- to the next lane by itself once the game refused LANE_AFTER sends in a row on the channel it is on
-- (SendNow), and asks the census again there: every client refused moves the same way, so the army
-- meets again on the next lane with nobody typing anything. The lane is kept per realm group
-- (ns.rdb.channelLane), so a /reload comes back to the lane that works. A guildmate's hello names
-- his lane (H1's sixth field): one from a Lord or Captain of our guild naming a higher lane moves us
-- too (TakeLane: an officer can already move the guild with a key, SetRealmKey), anyone else's is
-- noted alone (/oly status). The sealed channel's name takes the lane the same way.
Comm.LANE_AFTER = 3
Comm.LANE_MAX = 9
Comm.LANE_PROBE = 5 -- seconds after a refusal before the census is asked again, to settle it
-- Quiet clients say hello every 10 minutes, so 15 minutes admits one delayed round but not old
-- sessions. Five peers, at least two thirds of all usable reports and a two-peer lead make a lane
-- clearly dominant; the five-minute settle period prevents a changing crowd from making us flap.
Comm.CROWD_MIN = 5
Comm.CROWD_SHARE = 2 / 3
Comm.CROWD_LEAD = 2
Comm.CROWD_RECENT = 15 * 60
Comm.CROWD_SETTLE = 5 * 60
Lane = function()
	local n = ns.rdb and tonumber(ns.rdb.channelLane) or 0
	if n ~= n or n < 0 or n > Comm.LANE_MAX then return 0 end
	return math.floor(n)
end
Comm.Lane = Lane
local function LaneName(base) return base .. (Lane() > 0 and tostring(Lane()) or "") end

-- Each faction has its own channel (and sealed name), so the Horde and the Alliance never
-- mix their census, chat or decrees, whether or not the game shares channel names between them.
function Comm.ChannelSpec()
	local horde = ns.faction == "Horde"
	local key = ns.rdb and ns.rdb.realmKey
	if key and key ~= "" then return LaneName((horde and "OlyH" or "Oly") .. Hash36(key)), key end
	return LaneName(horde and ns.CHANNEL_HORDE or ns.CHANNEL), nil
end
-- To lane n (TakeLane: a higher one a guild officer's hello names) or the next one (NextLane): the
-- old channel is left and the new one joined (JoinChannel), the census asked there 10 s on.
-- (1.5.5) Refusal and officer moves stay upward-only and frozen while Relay.On(): otherwise they
-- can split a guild whose remaining clients did not move. A crowd correction is the exception: it
-- rejoins a decisive split, so it may move down or up and may run while the relay carries traffic.
local function MoveLane(n, why, crowd)
	if not ns.rdb then return false end
	n = tonumber(n)
	if not n or n ~= n or n ~= math.floor(n) or n < 0 or n > Comm.LANE_MAX or n == Lane() then return false end
	if n < Lane() and not crowd then return false end
	local R = ns.Relay
	if not crowd and type(R) == "table" and type(R.On) == "function" and R.On() == true then return false end
	if laneBad[n] then return false end
	local was = Lane()
	ns.rdb.channelLane = n
	laneMovedAt = ns.Now()
	laneRefused, laneProbe = 0, false
	stats.lanes = (stats.lanes or 0) + 1
	ns.Log("channel lane %d -> %d (%s)", was, Lane(), tostring(why))
	if ns.IsMember() then Comm.JoinChannel() end
	return true
end
function Comm.NextLane(why) return MoveLane(Lane() + 1, why or "refused") end
function Comm.LaneStats() return { lane = Lane(), refused = laneRefused, moves = stats.lanes or 0 } end

-- A lane belongs to this realm's custom-channel domain. Another realm's guild hello crosses realms
-- even when its OlympusNet does not; count it only after this session proved the channel itself is
-- shared (ElectsAcrossRealms). The server-stamped sender realm and the hello must both agree.
local function PeerOnOurChannelRealm(name)
	local realm, stamped = peerRealm[name], ns.RealmOf(name)
	return (realm == nil or realm == "old" or realm == ns.realm)
		and (stamped == nil or stamped == ns.realm)
end

-- Recent same-guild hellos carrying R are the only lane reports whose protocol includes usable
-- lane data. Ties choose the lower lane deterministically, though a tie can never pass CrowdClear.
function Comm.CrowdLane(now)
	now = now or ns.Now()
	local count, total, shared = {}, 0, Comm.ElectsAcrossRealms(now)
	for name, t in pairs(peers) do
		if peerRelay[name] and peerLaneUsable[name] and type(t) == "number"
			and t <= now and now - t <= Comm.CROWD_RECENT and (shared or PeerOnOurChannelRealm(name)) then
			local lane = peerLane[name] or 0
			count[lane] = (count[lane] or 0) + 1
			total = total + 1
		end
	end
	local best, bestN, runnerN = nil, 0, 0
	for lane = 0, Comm.LANE_MAX do
		local n = count[lane] or 0
		if n > bestN then runnerN, best, bestN = bestN, lane, n
		elseif n > runnerN then runnerN = n end
	end
	return best, bestN, total, count, runnerN
end

local function CrowdClear(best, n, total, runner)
	return best ~= nil and total > 0 and n >= Comm.CROWD_MIN
		and n / total >= Comm.CROWD_SHARE and n - runner >= Comm.CROWD_LEAD
end

function Comm.FollowCrowd(now)
	now = now or ns.Now()
	if now - laneMovedAt < Comm.CROWD_SETTLE then return false end
	local best, n, total, _, runner = Comm.CrowdLane(now)
	if not CrowdClear(best, n, total, runner) or best == Lane() or laneBad[best] then return false end
	return MoveLane(best, ("crowd: %d of %d peers on lane %d"):format(n, total, best), true)
end

-- An officer may still lead the existing safe upward move, except away from a clear healthy crowd.
function Comm.TakeLane(n, who)
	local best, count, total, _, runner = Comm.CrowdLane()
	if CrowdClear(best, count, total, runner) and not laneBad[best] and best ~= tonumber(n) then return false end
	return MoveLane(n, tostring(who) .. "'s hello")
end

local function HideChannelFromChat(name) -- gp:chat-channels
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local cf = _G["ChatFrame" .. i]
		if cf and ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, cf, name) end
	end
end

---------------------------------------------------------------------------
-- The channel's owner. Our hidden channel is an ordinary custom chat channel: the first
-- player in owns it, and when the owner leaves WoW hands it (and a moderator's seat) to
-- another member, so any player with the addon can end up owning it. An owner could /password
-- it (nobody who logs in afterwards gets in, and the network dies as people relog), /ban or
-- /ckick players (the King, the Treasurer), make a friend /moderator or give it away with
-- /owner. Olympus never uses these powers against anyone. It follows the channel's notices,
-- tells a player who was handed the channel what that means, and while the channel is ours it
-- only undoes harm (Comm.HealChannel). A channel locked against us is tried again, slower and
-- slower (Comm.JoinChannel). There is no other name to flee to: whoever locks one name can
-- squat any name we could predict as easily, and clients on different names would split the
-- army. We keep knocking on the same door until an honest owner opens it.
---------------------------------------------------------------------------

-- What we know of the channel named `name`, from its notices: a new record when we move to
-- another channel (the realm key arrived).
local function NewGuard(name)
	return { name = name, mine = {}, banned = {}, muted = {}, seen = {} }
end
local guard = NewGuard(nil)
local told = {}          -- role -> true once the player was told this session
local toldLocked = false -- ...and about a channel locked against us
local healAt = {}        -- healing call -> when it was last made (HEAL_GAP)
local healPending, rolePending = false, false
local healRefused = false -- the game refused one of these calls to addons: no more this session
local joinTries = 0      -- JoinChannelByName calls: one failed join counts once, however many notices say so

local function GuardFor(name)
	if guard.name ~= name then guard = NewGuard(name) end
	return guard
end

-- Our channel, whatever form a notice gives its name ("OlympusNet" or "5. OlympusNet").
local function OurChannel(...)
	local ours = joinedName or Comm.ChannelSpec()
	if type(ours) ~= "string" then return nil end
	for i = 1, select("#", ...) do
		local n = select(i, ...)
		if type(n) == "string" and n ~= "" and n:gsub("^%d+%.%s*", ""):lower() == ours:lower() then return ours end
	end
	return nil
end

local function IsMe(name)
	if type(name) ~= "string" or name == "" or not ns.me then return false end
	if ns.Channels and ns.Channels.IsMe then return ns.Channels.IsMe(name) end
	return ns.FullName(ns.Normal(name)) == ns.me
end

-- A name the way the server finds it again (ns.TellName), or nil.
local function ServerName(name)
	if type(name) ~= "string" or name == "" then return nil end
	return ns.TellName(name)
end

-- list[name] = when, at most MAX_HURT names (the oldest goes).
local function Remember(list, name, now)
	name = ServerName(name)
	if not name then return end
	local n, oldest = 0, nil
	for k, t in pairs(list) do
		n = n + 1
		if not oldest or t < list[oldest] then oldest = k end
	end
	if not list[name] and n >= MAX_HURT then list[oldest] = nil end
	list[name] = now
end

local function Mine(g) return g.mine.owner or g.mine.moderator end

-- 1.4.0 (the HealChannel spam a player reported): a name we saw banned is let back in only while
-- nothing says that player is offline. The server answers an unban of an offline name with "No
-- player named ... is currently playing" in the player's chat, so these names wait instead: one
-- the server already named so this session (Treasury.Unavailable, which any whisper's reply
-- fills), or a member of our own guild that a fresh roster scan shows offline. The roster's own
-- freshness gate (Roster.Fresh) keeps an old guild's rows out of it.
local OFFLINE_RECHECK = 300 -- names left waiting are looked at again this often while the channel is ours
local function OfflineMembers()
	local R = ns.Roster
	local fresh = R and type(R.Fresh) == "function" and R.Fresh(OFFLINE_RECHECK)
	if not fresh or type(fresh.members) ~= "table" then return nil end
	local out
	for _, row in ipairs(fresh.members) do
		if type(row) == "table" and row.online == false and type(row.full) == "string" then
			local name = ServerName(row.full)
			if name then
				out = out or {}
				out[name:lower()] = true
			end
		end
	end
	return out
end
local function KnownOffline(name, offline)
	local T = ns.Treasury
	if type(T) == "table" and type(T.Unavailable) == "function" and T.Unavailable(name) == true then return true end
	return offline ~= nil and offline[name:lower()] == true
end

-- One healing call, protected, the same one at most every HEAL_GAP: "done", "failed",
-- "later" (too soon: try again) or "missing" (this client has no such function).
local function HealCall(what, fn, ...)
	if type(fn) ~= "function" or healRefused then return "missing" end
	local now = ns.Now()
	if now - (healAt[what] or -math.huge) < HEAL_GAP then return "later" end
	healAt[what] = now
	local ok, err = pcall(fn, ...)
	ns.Log("channel %s: %s%s", tostring(guard.name), what, ok and "" or (" failed: " .. tostring(err)))
	return ok and "done" or "failed"
end

local function HealSoon(delay)
	if healPending then return end
	healPending = true
	ns.After(delay or 2, "channel heal", function()
		healPending = false
		Comm.HealChannel()
	end)
end

-- Names seen banned but known offline (KnownOffline) are looked at again later, on a timer of
-- their own: a heal due sooner (a notice's) is never held behind it.
local recheckPending = false
local function RecheckSoon()
	if recheckPending then return end
	recheckPending = true
	ns.After(OFFLINE_RECHECK, "channel heal recheck", function()
		recheckPending = false
		Comm.HealChannel()
	end)
end

-- Only while the channel is ours (owner or moderator), only to undo harm, never against
-- anyone: the password it should have (none on the public channel, the key on the sealed
-- one), no moderation, and whoever we saw banned or muted while we were on it let back in.
-- 1.4.0: only the names we saw banned (the Treasurer and the King too: never one we did not see
-- banned, which only made the server name every offline one in the chat), and none while it is
-- known offline (KnownOffline). Only for the channel we are meant to be on: what we saw on
-- another one (the public channel once we have a key) changes nothing.
-- What someone does with the channel from our own client is not undone here: the next owner's
-- client does it.
function Comm.HealChannel()
	local g = guard
	local name, key = Comm.ChannelSpec()
	if not name or g.name ~= name or not Mine(g) or not ns.IsMember() then return end
	if type(GetChannelName) ~= "function" or (GetChannelName(name) or 0) == 0 then return end
	local later = false
	local function Do(what, fn, ...)
		local r = HealCall(what, fn, ...)
		if r == "later" then later = true end
		return r
	end
	-- The password: after a change we saw, or when the channel came to us and we had not
	-- watched it since we joined (a /reload forgets what was seen before it).
	if g.password or g.unwatched then
		if Do("password " .. (key and "back to the key" or "cleared"), SetChannelPassword, name, key or "") ~= "later" then
			g.password, g.unwatched = nil, nil
		end
	end
	-- Moderation is switched over, not set: only when we know it is on, once for each time we
	-- saw it turned on. (Today's clients have no ChannelModerate: nobody can turn it on either.)
	if g.moderationOn and Do("moderation off", ChannelModerate, name) ~= "later" then g.moderationOn = nil end
	local unban = {}
	for who in pairs(g.banned) do unban[#unban + 1] = who end
	table.sort(unban)
	local offline = unban[1] and OfflineMembers() or nil
	local away = false
	for _, who in ipairs(unban) do
		if KnownOffline(who, offline) then
			away = true -- kept in g.banned: let back in once nothing says he is offline
		elseif Do("unban " .. who, ChannelUnban, name, who) ~= "later" then
			g.banned[who] = nil
		end
	end
	if away then RecheckSoon() end
	-- (No ChannelUnmute in today's clients either: kept for one that has it.)
	for who in pairs(g.muted) do
		if Do("unmute " .. who, ChannelUnmute, name, who) ~= "later" then g.muted[who] = nil end
	end
	if later then HealSoon(HEAL_GAP) end
end

-- Handed the channel (owner or moderator): the player is told once a session what that
-- means, then the heal runs. A moment later, so an owner's two notices make one line.
local function RoleGiven(g)
	if rolePending then return end
	rolePending = true
	ns.After(2, "channel role", function()
		rolePending = false
		if guard ~= g or not Mine(g) then return end
		local role = g.mine.owner and "owner" or "moderator"
		if not told[role] then
			told[role] = true
			if role == "owner" then told.moderator = true end
			ns.Print("|cffffd200" .. (role == "owner" and ns.L.CHANNEL_OWNER_YOU or ns.L.CHANNEL_MODERATOR_YOU):format(g.name) .. "|r")
		end
		Comm.HealChannel()
	end)
end

-- Joining failed: a password or a ban. The player is told once a session; the next try waits
-- LOCKED_RETRY (see Comm.JoinChannel).
local function Locked(g, why, now)
	local lock = g.locked
	if not lock then
		lock = { why = why, tries = 0, since = now }
		g.locked = lock
		if not toldLocked then
			toldLocked = true
			ns.Print("|cffffd200" .. ns.L.CHANNEL_LOCKED:format(g.name) .. "|r")
		end
	end
	lock.why = why
	if lock.try == joinTries then return end
	lock.try = joinTries
	lock.tries = lock.tries + 1
	lock.nextAt = now + LOCKED_RETRY[math.min(lock.tries, #LOCKED_RETRY)]
	ns.Log("channel %s locked against us (%s, try %d): next try in %ds", g.name, why, lock.tries, lock.nextAt - now)
end

-- In again after being locked out: the census missed in the meantime is asked for.
local function Unlocked(g)
	if not g.locked then return end
	ns.Log("channel %s open to us again after %d tries", g.name, g.locked.tries)
	g.locked = nil
	askTries = 0
	ns.After(Comm.AskWait(), "census request", Comm.AskCensus)
end

-- CHAT_MSG_CHANNEL_NOTICE and CHAT_MSG_CHANNEL_NOTICE_USER: (notice type, player, language,
-- "5. OlympusNet", second player, flags, zone channel id, channel number, "OlympusNet", ...).
-- With two players (banned, kicked, unbanned) the first is the one it happened to and the
-- second who did it. Only our channel's notices count.
function Comm.OnChannelNotice(notice, player, _, channelName, player2, _, _, _, baseName)
	-- Forever may hand these over as secret values while chat is locked down: nothing to read.
	-- (1.5.5: the channel's names too, which OurChannel reads.)
	if ns.Secret("channel notice", notice, player, player2, channelName, baseName) then return end
	if type(notice) ~= "string" then return end
	local name = OurChannel(baseName, channelName)
	if not name then return end
	local g, now = GuardFor(name), ns.Now()
	player = type(player) == "string" and player ~= "" and player or nil
	player2 = type(player2) == "string" and player2 ~= "" and player2 or nil
	if notice == "YOU_JOINED" or notice == "YOU_CHANGED" then
		g.watched = true -- in from the start: every change after this reaches us
		Unlocked(g)
	elseif notice == "YOU_LEFT" or notice == "SUSPENDED" then
		g.mine, g.watched = {}, nil -- whoever leaves gives the channel away
	elseif notice == "WRONG_PASSWORD" or notice == "BANNED" then
		Locked(g, notice, now)
	elseif notice == "OWNER_CHANGED" or notice == "CHANNEL_OWNER" then
		if notice == "OWNER_CHANGED" then Count(g.seen, "owner") end
		g.owner, g.ownerAt = player, now
		if not IsMe(player) then
			g.mine.owner = nil
		elseif not g.mine.owner then
			g.mine.owner = true
			g.unwatched = not g.watched or nil
			RoleGiven(g)
		end
	elseif notice == "SET_MODERATOR" or notice == "UNSET_MODERATOR" then
		if not IsMe(player) then
			if notice == "SET_MODERATOR" then Count(g.seen, "moderator") end -- a seat handed to someone else
		elseif notice == "UNSET_MODERATOR" then
			g.mine.moderator = nil
		elseif not g.mine.moderator then
			g.mine.moderator = true
			RoleGiven(g)
		end
	elseif notice == "PASSWORD_CHANGED" then
		Count(g.seen, "password")
		if not IsMe(player) then g.password = { by = player, t = now } end
	elseif notice == "MODERATION_ON" or notice == "MODERATION_OFF" then
		Count(g.seen, "moderation")
		g.moderation = notice == "MODERATION_ON" and "on" or "off"
		g.moderationOn = notice == "MODERATION_ON" and not IsMe(player) or nil
	elseif notice == "ANNOUNCEMENTS_ON" or notice == "ANNOUNCEMENTS_OFF" then
		g.announce = notice == "ANNOUNCEMENTS_ON" and "on" or "off"
	elseif notice == "PLAYER_BANNED" or notice == "PLAYER_KICKED" then
		Count(g.seen, notice == "PLAYER_BANNED" and "ban" or "kick")
		if IsMe(player) then
			g.mine, g.watched = {}, nil
		elseif notice == "PLAYER_BANNED" and not IsMe(player2) then
			Remember(g.banned, player, now)
		end
	elseif notice == "PLAYER_UNBANNED" then
		local who = ServerName(player)
		if who then g.banned[who] = nil end
	elseif notice == "UNSET_SPEAK" or notice == "UNSET_VOICE" then
		Count(g.seen, "mute")
		Remember(g.muted, player, now)
	elseif notice == "SET_SPEAK" or notice == "SET_VOICE" then
		local who = ServerName(player)
		if who then g.muted[who] = nil end
	elseif notice == "MUTED" then
		Count(g.seen, "we muted") -- we may not speak there
	else
		return
	end
	ns.Log("channel %s: %s %s%s", name, notice, tostring(player or "-"), player2 and (" by " .. player2) or "")
	if Mine(g) then HealSoon() end
end

-- Blizzard's own password prompt for our channel: the same as a wrong password.
function Comm.OnPasswordRequest(channel)
	local name = OurChannel(channel)
	if name then Locked(GuardFor(name), "WRONG_PASSWORD", ns.Now()) end
end

-- None of the calls above is marked protected, but should the game ever refuse one to addons,
-- the first refusal ends healing for the session: never a string of "blocked" warnings.
function Comm.OnActionRefused(addon, func)
	if addon ~= ADDON or type(func) ~= "string" then return end
	if func:find("SetChannelPassword", 1, true) or func:find("ChannelUn", 1, true) or func:find("ChannelModerate", 1, true) then
		healRefused = true
		ns.Log("channel healing off for this session: the game refused %s", func)
	end
end

-- For /oly status: the channel's owner as last seen, our seat, what was seen.
function Comm.GuardStats()
	local g, now = guard, ns.Now()
	local function Size(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
	return {
		name = g.name, owner = g.owner, ownerAt = g.ownerAt,
		role = g.mine.owner and "owner" or (g.mine.moderator and "moderator" or "member"),
		moderation = g.moderation, announce = g.announce, seen = g.seen, watched = g.watched == true,
		banned = Size(g.banned), muted = Size(g.muted), password = g.password ~= nil,
		locked = g.locked and { why = g.locked.why, tries = g.locked.tries, nextIn = math.max(0, (g.locked.nextAt or now) - now) },
	}
end

function Comm.JoinChannel()
	if not ns.IsMember() then return end
	local name, password = Comm.ChannelSpec()
	if joinedName and joinedName ~= name then
		-- Another channel (the realm key arrived or changed). The chat lines still waiting were
		-- written for the old one's audience: dropped, never sent on this one, and their writer is
		-- told (GitHub #34). Votes heard on the old one don't count here, and its reporters have
		-- not heard our census request.
		DropChat("moved")
		if ns.Data and ns.Data.ForgetVotes then ns.Data.ForgetVotes() end
		askTries = 0
		heardAsk = -math.huge -- (the answers to an ask heard there went there)
		ns.After(10, "census request", Comm.AskCensus)
	end
	if joinedName and joinedName ~= name and GetChannelName(joinedName) > 0 then
		LeaveChannelByName(joinedName) -- the key changed: leave the old channel -- gp:chat-channels
		channelIndex = 0
	end
	if joinedName ~= name then watch, laneRefused = nil, 0 end -- another channel: the election guard starts again
	joinedName = name
	local id = GetChannelName(name)
	if id and id > 0 then
		if channelIndex ~= id then ns.Log("channel %s is #%d", name, id) end
		channelIndex = id
		HideChannelFromChat(name)
		return
	end
	-- Locked against us (a password or a ban): not before the next try is due (Locked).
	local lock = guard.name == name and guard.locked
	if lock and ns.Now() < (lock.nextAt or 0) then return end
	joinTries = joinTries + 1
	ns.Log("joining channel %s%s", name, password and " (sealed)" or "")
	watch = nil -- time off this channel says nothing about what we hear on it (election guard)
	JoinChannelByName(name, password) -- gp:chat-channels
	ns.After(3, "channel check", function()
		channelIndex = GetChannelName(name) or 0
		if channelIndex > 0 and guard.name == name then Unlocked(guard) end
		Comm.joinedAt = ns.Now()
		ns.SafeCall("channel last", Comm.KeepLast)
		ns.Log("channel %s -> #%d", name, channelIndex)
		HideChannelFromChat(name)
		-- (1.4.1) One census request as a probe once we are on it: a client with nothing else to
		-- say still learns whether the game takes its words here (SendNow's lane count).
		if channelIndex > 0 then ns.After(Comm.LANE_PROBE, "channel probe", function() Comm.AskCensus(true) end) end
	end)
end

function Comm.ChannelName() return joinedName end
function Comm.ChannelIndex() return channelIndex end -- (1.5.0: the chat hall writes its text there)
Comm.MAX_QUEUE = MAX_QUEUE
function Comm.DeliveredLogged() return deliveredLogged end

-- Who can read the channel, as the privacy questions tell the player (Layers, Channels):
-- anyone without a realm key, whoever holds the key with one.
function Comm.Audience()
	return (ns.rdb and ns.rdb.realmKey) and ns.L.CHANNEL_SEALED or ns.L.CHANNEL_PUBLIC
end

-- The channel is public (1.1): no realm key, so anyone who joins it by name reads what is sent
-- there. nil outside an Olympus guild (the addon is on no channel there).
function Comm.IsPublic()
	if not ns.IsMember() then return nil end
	return not (ns.rdb and ns.rdb.realmKey)
end

-- Our guild's addon users on the sealed channel now, as their hellos say (1.1: while we are on
-- the public one, they are on another channel than ours).
function Comm.SealedPeers()
	local now, n = ns.Now(), 0
	for name, t in pairs(peers) do
		if now - t <= COUNT_WINDOW and peerSealed[name] == "s" then n = n + 1 end
	end
	return n
end

-- No key? Ask our guild (officers who have it answer, over GUILD).
function Comm.RequestKey()
	if ns.IsMember() and ns.rdb and not ns.rdb.realmKey then Enqueue("GUILD", { "K0~" }, "keyreq") end
end

-- /oly key <secret>: officers seal the channel; guildmates receive the key automatically.
function Comm.SetRealmKey(secret)
	if not ns.IsMember() or not ns.Roster.IsOfficer() then
		ns.Print(ns.L.KEY_OFFICERS_ONLY)
		return
	end
	secret = (secret or ""):gsub("[~|\n]", "")
	if #secret < 6 then
		ns.Print(ns.L.KEY_TOO_SHORT)
		return
	end
	local was = ns.rdb.realmKey
	ns.rdb.realmKey = secret
	-- 1.1 (Keys.lua): dated now, so our guild's 1.1 clients take it over a key the King rotated
	-- before; the key it replaces named with it (a plain K1 of that one no longer pulls them back).
	-- 1.4.0: that K8 alone; no plain K1, which every older version reads.
	if ns.Keys.Typed then ns.Keys.Typed(secret, was) end
	ns.Print(ns.L.KEY_SET)
	Comm.JoinChannel()
end

---------------------------------------------------------------------------
-- Realms (1.0.0). WoW: Forever's PvP and PvP 2 each have an OlympusNet of their own, and a
-- guild has members on both: a reporter on one realm is never heard on the other one's
-- channel, and a guild that elected a single reporter was missing from the other realm's
-- census (older versions left that reporter out after GUARD_AFTER unheard, one name at a time).
-- So each realm elects its own reporter among the peers whose hello names that realm, and
-- those whose realm we don't know (versions before 0.7.11), unless the server stamps another
-- realm on their name (see Electable). While our guild's report, sent by a guildmate of another
-- realm, reaches our channel (the channel is shared: Comm.ElectsAcrossRealms), one reporter for
-- all, as before.
---------------------------------------------------------------------------

-- A realm's code in our report (field 27): three letters or digits.
function Comm.RealmCode(realm)
	return Hash36(tostring(realm)):sub(1, 3)
end

-- The realms our guild's addon users play on now (hellos counted within COUNT_WINDOW), ours
-- included, sorted by name.
function Comm.PresenceRealms(now)
	now = now or ns.Now()
	local set, out = { [tostring(ns.realm)] = true }, {}
	for name, t in pairs(peers) do
		local realm = peerRealm[name]
		if now - t <= COUNT_WINDOW and realm and realm ~= "old" then set[realm] = true end
	end
	for realm in pairs(set) do out[#out + 1] = realm end
	table.sort(out)
	return out
end

-- The same as codes, sorted, each once: `pres`, field 27 of our report.
function Comm.Presence(now)
	local out, seen = {}, {}
	for _, realm in ipairs(Comm.PresenceRealms(now)) do
		local code = Comm.RealmCode(realm)
		if not seen[code] then seen[code], out[#out + 1] = true, code end
	end
	table.sort(out)
	return out
end

-- Does our guild have addon users online on another realm than ours?
function Comm.SpansRealms(now)
	return #Comm.PresenceRealms(now) > 1
end

-- Our census reaches no other role than reporting yet: "a" in field 26 of our report (the
-- census layer's clients will say "b" or "c").
Comm.CAPABILITY = "a"

-- Our channel crosses realms: our guild's report, sent by a guildmate whose hello over GUILD
-- (where the server vouches for our guild) named another realm, was heard on it within
-- SHARED_FOR, in this session. Every realm's peers hear one reporter there then, and the
-- election counts them all. Nothing else proves it: the realm a report names (field 21, `from`;
-- ns.rdb.shared in /oly status) is whatever its sender wrote, and anyone on the public channel
-- may send one; a flag saved by an earlier session proves nothing of this one.
function Comm.ElectsAcrossRealms(now)
	return (now or ns.Now()) - crossedAt <= SHARED_FOR
end

-- The realm, not ours, that the hello of this guildmate named (counted now), or nil. The channel
-- may send a name of another realm without it (see heardOwn): matched by the short name then,
-- unless the full name is a peer of its own. Only a realm the server stamped on the hello's
-- sender too (1.0.0, Konig's review of 1.0.0): a guildmate of our realm whose hello named another
-- one, sending our guild's report on our channel, made our election cross realms, and our guild's
-- reporter then played on another realm's channel, off our realm's census.
local function OtherRealm(name, now)
	local t, realm = peers[name], peerRealm[name]
	if t and now - t <= COUNT_WINDOW and realm and realm ~= "old" and realm ~= ns.realm and ns.RealmOf(name) == realm then
		return realm
	end
end
local function PeerOfOtherRealm(sender, now)
	if peers[sender] then return OtherRealm(sender, now) end
	local short = ns.ShortName(sender)
	for name in pairs(peers) do
		local realm = ns.ShortName(name) == short and OtherRealm(name, now)
		if realm then return realm end
	end
end

-- In a full guild, 1000 members saying hello every minute would be ~16 messages per second.
-- Only names that could win the reporter election need to keep talking: once this many
-- members that sort before us (and may be elected with us) are known, we go quiet (still one
-- hello per 10 minutes to be counted). With a reporter per realm (1.0.0), each realm keeps its
-- share of the QUIET_TOTAL talking, QUIET_MIN at least.
function Comm.QuietAfter(now)
	if Comm.ElectsAcrossRealms(now) then return QUIET_TOTAL end
	return math.max(QUIET_MIN, math.ceil(QUIET_TOTAL / #Comm.PresenceRealms(now)))
end

-- (1.5.5) Guild peer -> true when its hello says it takes the relay's tree ("N", its 8th field:
-- RelayTree.lua loaded). The first such peer is our guild's registrant (MaybeBroadcast).
local peerTree = {}
local function TreeLoaded()
	local T = ns.RelayTree
	return type(T) == "table" and not T.missing
end

-- force: now, whatever the above (the player changed what the hello says).
function Comm.Hello(force)
	SyncGuild()
	if not IsInGuild() then return end
	-- Quiet presence (Core.lua): no hello at all, forced or not; our guildmates' clients age us out
	-- (COUNT_WINDOW) as after a logout, and we are never elected.
	if Quiet() then return end
	local now, before, beforeTree = ns.Now(), 0, 0
	for name, t in pairs(Comm.Electable(now)) do
		if now - t <= PEER_WINDOW and name < (ns.me or "") then
			before = before + 1
			if peerTree[name] then beforeTree = beforeTree + 1 end
		end
	end
	-- (1.5.5) A client that takes the relay's tree talks on while fewer guildmates with N than that sort
	-- before it: it may be our registrant (MaybeBroadcast), and a quiet one is past PEER_WINDOW there.
	local quietAfter = Comm.QuietAfter(now)
	local talk = before < quietAfter or (TreeLoaded() and beforeTree < quietAfter)
	if not force and not talk and now - lastHello < 600 then return end
	lastHello = now
	-- Our realm rides along: guildmates on another realm show in /oly status (topology). So does
	-- our channel: without the key we can't hear a reporter on the sealed one (MaybeBroadcast).
	-- And "z" when we share our zone (0.9.1): our guild's reporter may name it then, never
	-- otherwise. Older versions read the fields before it and ignore the rest.
	local sealed = ns.rdb and ns.rdb.realmKey and "s" or "p"
	-- The fields after it: "z" (our zone shared), "b" (an arena bank on duty), and (1.4.1) "L<n>",
	-- our channel lane when it is not the first. Empty ones at the end are left out, as before.
	-- (1.5.5) "N" after "R": this client takes the relay's tree (RelayTree.lua; a 1.5.5 client updated
	-- without restarting the game has its stand-in, and says nothing). Older versions never read it.
	local tail = { ns.Layers and ns.Layers.Sharing and ns.Layers.Sharing() and "z" or "", Comm.BankOnDuty() and "b" or "",
		Lane() > 0 and ("L" .. Lane()) or "", "R", TreeLoaded() and "N" or "" } -- (1.4.3: "R", this client carries the relay)
	while #tail > 0 and tail[#tail] == "" do tail[#tail] = nil end
	local extra = #tail > 0 and ("~" .. table.concat(tail, "~")) or ""
	Enqueue("GUILD", { "H1~" .. ns.VERSION .. "~" .. tostring(ns.realm) .. "~" .. sealed .. extra }, "hello")
end

-- An arena bank on duty leaves census reporting to a guildmate so event traffic and
-- thirty-piece census transfers do not contend for the same sender.
function Comm.BankOnDuty()
	local A = ns.Arena
	return type(A) == "table" and type(A.OnDuty) == "function" and A.OnDuty("bank") == true
end

-- Does this guildmate share their zone (their hello says so, or it is us and we do)? By the
-- short name the roster gives, like heardOwn: the roster and guild messages may write the
-- realm apart. Only while they are counted (COUNT_WINDOW): quiet peers say hello every 10 min.
function Comm.SharesZone(name)
	if type(name) ~= "string" or name == "" then return false end
	local short = ns.ShortName(ns.Normal(name)):lower()
	if ns.me and short == ns.ShortName(ns.me):lower() then
		return ns.Layers and ns.Layers.Sharing and ns.Layers.Sharing() or false
	end
	local now = ns.Now()
	for peer, t in pairs(peers) do
		if peerZone[peer] and now - t <= COUNT_WINDOW and ns.ShortName(peer):lower() == short then return true end
	end
	return false
end

-- The peers that may be elected (1.0.0): those on our realm and those of a realm we don't know
-- (a hello without one: "old", on no other realm by the server's stamp), or every realm's while
-- the channel is shared (see Realms, above); never one left out by the guard below. The
-- runner-up is drawn from the same pool.
-- The server's stamp on a peer's name counts first, whatever its hello says (1.0.0, Konig's
-- review of 1.0.0): a guildmate the server places on PvP 2 whose hello named no realm, or one
-- we can't read ("old"), was elected on ours, never heard on our channel, and our guild was off
-- our realm's census while the guard left him out (GUARD_AFTER), then his next alt. A peer of
-- another realm by the server's stamp is left out here unless the channel is shared; "old"
-- stays what the runner-up's pick reads it as (a version that sends no runner-up report).
local function Electable(now)
	local all, pool = Comm.ElectsAcrossRealms(now), {}
	for name, t in pairs(peers) do
		local ours = PeerOnOurChannelRealm(name)
		-- (1.4.1, launch night: a guild's 1.4.0 clients, stuck on the first lane, were elected by name
		-- and reported into a channel nobody heard, while its guildmates on the next lane kept quiet.)
		-- Only a peer on our lane: his hello names it (none named: the first lane).
		local sameLane = peerLaneUsable[name] ~= false and (peerLane[name] or 0) == Lane()
		-- (1.4.3) Where the relay carries the channel, only a peer that carries it too can report.
		local relayed = ns.Relay and ns.Relay.On()
		local carries = not relayed or peerRelay[name] == true
		-- (1.5.4) And such a peer whatever his sub-realm or lane: the relay reads neither, and GUILD
		-- reaches the whole guild. Counting them split one guild into a reporter per sub-realm and
		-- lane, each reporting the same roster and each taking the relay's registration from the
		-- others (the dev's relay: 9 members of one guild registered in turn).
		if relayed and carries then ours, sameLane = true, true end
		-- (1.5.4) Never a client marked as a modified build (Builds.lua): no relay takes its
		-- registration and nobody takes its reports, so an election that chose it reported to nobody.
		local B = ns.Builds
		local locked = B ~= nil and not B.missing and B.Quarantined(name) == true
		if (benched[name] or 0) <= now and (all or ours) and not peerBank[name] and sameLane and carries and not locked then pool[name] = t end
	end
	return pool
end
Comm.Electable = Electable

-- When our last report counts as sent, for a sender reporting every `every` seconds: a census
-- answer sends the next due report early (Q1 below), and the one after it then waits a full
-- period from when the answered one was due. Answers move reports forward, never add one.
local function LastReport(every)
	if early and early.every == every and early.due > lastBroadcast then return early.due end
	return lastBroadcast
end

-- (1.5.5) Our guild's registrant: the first by name of the peers that may be elected whose hello says N,
-- ourselves too when we take the tree; nil when none does (then the reporter registers, as before).
local function Registrant(pool, now)
	local first = TreeLoaded() and ns.me or nil
	for name, t in pairs(pool) do
		if peerTree[name] and now - t <= PEER_WINDOW and (not first or name < first) then first = name end
	end
	return first
end

function Comm.MaybeBroadcast(report)
	SyncGuild()
	local now = ns.Now()
	-- Quiet presence (Core.lua) too: neither the reporter nor its runner-up, so no report and no
	-- census answer (Q1) of ours says we are online.
	if Comm.BankOnDuty() or Quiet() then
		Comm.isReporter, Comm.isRunnerUp, Comm.isRegistrant, watch = false, false, false, nil
		Comm.lastReport = report
		return
	end
	-- Peers are keyed "Name-Realm" like ns.me, so every client compares the same strings.
	local pool = Electable(now)
	local best = Codec.PickReporter(ns.me, pool, now, PEER_WINDOW)
	-- Rollout guard: a peer that wins the election but never reports (an old or broken
	-- version, or one that is not on the channel) keeps our guild off everyone's census.
	-- Elected for GUARD_AFTER while we are on the channel and never heard reporting our guild
	-- there, it is left out for GUARD_FOR and the next one is elected (maybe us).
	-- A reporter on the sealed channel is not ours to judge while we have no key: we can't hear
	-- it, and its reports reach the guilds they should. We ask for the key instead.
	local deaf = best ~= ns.me and peerSealed[best] == "s" and not (ns.rdb and ns.rdb.realmKey)
	if deaf then
		watch = nil
		if now - (lastKeyAsk or Comm.loginAt or 0) >= KEY_ASK_EVERY then
			lastKeyAsk = now
			Comm.RequestKey()
		end
	-- (1.4.5) Where the relay carries the channel (Forever), the channel itself delivers nothing, so
	-- a reporter is never "heard" there: every client benched its guild's reporter in turn and
	-- elected itself (the dev's log, 2026-11-05: a new reporter every minute). No guard there.
	elseif best ~= ns.me and channelIndex > 0 and not RelayOn() then
		if not watch or watch.name ~= best then watch = { name = best, since = now } end
		if now - math.max(watch.since, heardOwn[ns.ShortName(best)] or 0) >= GUARD_AFTER then
			benched[best] = now + GUARD_FOR
			ns.Log("reporter %s never heard in %ds: left out of the election for %dm", best, GUARD_AFTER, GUARD_FOR / 60)
			pool[best], watch = nil, nil
			best = Codec.PickReporter(ns.me, pool, now, PEER_WINDOW)
		end
	else
		watch = nil
	end
	Comm.isReporter = best == ns.me
	Comm.reporterName = ns.DisplayName(best)
	Comm.lastReport = report
	-- (1.5.5) Only the registrant registers our guild with its relay (Relay.Register), and tells it we
	-- take the tree (RelayTree.Announce): a reporter without N leaves both to it while it is known. An
	-- older reporter still registers (its own code); a relay keeps the registration that takes the tree.
	local registrant = Registrant(pool, now)
	local relayed = ns.Relay and ns.Relay.On()
	Comm.isRegistrant = (registrant or best) == ns.me
	Comm.registrantName = ns.DisplayName(registrant or best)
	if Comm.isRegistrant and relayed then
		ns.SafeCall("relay register", ns.Relay.Register)
		if TreeLoaded() and type(ns.RelayTree.Announce) == "function" then ns.SafeCall("relay tree", ns.RelayTree.Announce) end
	end
	-- The runner-up of the election reports too, every WITNESS_EVERY: a report never proves
	-- its own sender's rank, so other guilds trust a reporter who leads the guild (or is an
	-- officer) only once a second sender names them (Data.KnownRank).
	local second
	if not Comm.isReporter then
		-- Only a peer that can back the reporter: on 0.7.11 or later (older ones never send a
		-- runner-up report) and on the same channel as the reporter (sealed or public).
		local rest = {}
		for name, t in pairs(pool) do
			if name ~= best and peerRealm[name] ~= "old" and (peerSealed[name] == nil or peerSealed[name] == peerSealed[best]) then
				rest[name] = t
			end
		end
		second = Codec.PickReporter(ns.me, rest, now, PEER_WINDOW)
	end
	-- Only while the reporter is heard on our channel: the point is to back an active one.
	Comm.isRunnerUp = second == ns.me and best ~= nil and now - (heardOwn[ns.ShortName(best)] or -math.huge) <= 2 * BROADCAST_EVERY
	-- (1.5.5) With no signed relay (Relay.InFallback: the fallback relays, RelayFallback.lua), a reporter
	-- without N sends our report where nobody hears it: its registrant reports our guild too, as often.
	local dual = Comm.isRegistrant and not Comm.isReporter and best ~= nil and not peerTree[best] and relayed
		and type(ns.Relay.InFallback) == "function" and ns.Relay.InFallback() == true
	local every = (Comm.isReporter or dual) and BROADCAST_EVERY or (Comm.isRunnerUp and WITNESS_EVERY or nil)
	if not every or now - LastReport(every) < every then return end
	-- Right after login we don't know our guildmates yet and would wrongly think we are the
	-- reporter: wait one hello round first.
	if now - math.max(Comm.loginAt or 0, guildChangedAt) < HELLO_EVERY + 10 then return end
	Comm.Broadcast(report)
end

function Comm.Broadcast(report)
	-- 1.1: our guild is off the Olympus network (net-off, Moderation.lua): its census stays home.
	local M = ns.Moderation
	if M and not M.missing and M.OwnGuildOff() then
		if not Comm.heldReport then ns.Log("census of %s not sent: the guild is off the network", tostring(report and report.guild)) end
		Comm.heldReport = true
		return
	end
	Comm.heldReport = nil
	-- Quiet presence (Core.lua): no census of ours, which would say we are online (its pieces name no
	-- type for QuietHolds: held here, and by the guard below for one already on its way).
	if Quiet() then return end
	lastBroadcast = ns.Now()
	msgId = (msgId + 1) % 1000
	-- Where people are goes out only with their yes (0.9.1): nothing of it unless we share our
	-- own zone, and then the counts per zone and the zones of the leader and officers who
	-- share theirs. Our own window keeps the whole report (it never leaves this client).
	local sharing = ns.Layers and ns.Layers.Sharing and ns.Layers.Sharing()
	local payload = Codec.EncodeReport(Codec.Shareable(report, sharing, sharing and Comm.SharesZone or nil))
	local chunks = Codec.Chunk(payload, tostring(msgId))
	Comm.SendBatch("CHANNEL", chunks, nil, nil, false, nil, { guard = function()
		local current = ns.Moderation
		if current and not current.missing and current.OwnGuildOff() then return false end
		if Quiet() then return false end
		return not sharing or (ns.Layers and ns.Layers.Sharing and ns.Layers.Sharing()) == true
	end })
	ns.Log("broadcast %s: %d bytes in %d chunks", report.guild, #payload, #chunks)
end

-- The census on request. The Forever beta client saves addon data but never loads it back, so
-- every login starts with an empty census: we ask the channel (Q1), and each guild's reporter
-- sends its report right away instead of within 3 minutes. Bounded: a reporter answers at
-- most once every ANSWER_GAP, and only if its last report is ANSWER_MIN_AGE old. A reporter
-- that had just answered someone else stays quiet, so we ask once more ASK_AGAIN later, unless
-- a report came meanwhile (the reporters are answering; the quiet ones report on their own
-- within BROADCAST_EVERY).
-- Tries again a little later while the channel is not joined yet (at most 3 times), and once
-- more after the channel changes (the realm key arrived).
-- After a server restart thousands log in within minutes (1.0.0): each asks at a second of its
-- own (Comm.AskWait), and leaves its ask out when someone else asked within ASK_HELD, since
-- every guild's answer to that ask reaches the whole channel. A left-out ask counts as ours for
-- the second one: asked ASK_AGAIN later unless a report came.
function Comm.AskCensus(force)
	if not ns.IsMember() then return end
	-- (1.5.5) Not while the relays carry the channel (Relay.On): a relay keeps the ask to itself (Q1 is
	-- never fanned out), and every guild's report reaches its relay on the reporter's own clock.
	local R = ns.Relay
	if type(R) == "table" and type(R.On) == "function" and R.On() == true then return end
	if not Comm.ChannelReady() then
		askTries = askTries + 1
		if askTries < 3 then ns.After(20, "census request", Comm.AskCensus) end
		return
	end
	-- Login and a guild change can both ask within seconds: once a minute is enough. (1.4.1:
	-- force, the lane's probe: asked whatever was heard or asked before, to see the game's answer.)
	local now = ns.Now()
	if not force and Comm.lastAsk and now - Comm.lastAsk < 60 then return end
	Comm.lastAsk = now
	if not force and now - heardAsk < ASK_HELD then
		stats.askSkipped = stats.askSkipped + 1
	else
		stats.asked = stats.asked + 1
		Enqueue("CHANNEL", { "Q1~" }, "censusreq")
	end
	if not askedAgain then
		askedAgain = true
		local heard = stats.reports
		ns.After(ASK_AGAIN, "census request", function()
			if stats.reports > heard then return end
			Comm.AskCensus()
		end)
	end
end

-- When our census request goes, seconds after we joined the channel: ASK_AFTER to
-- ASK_AFTER + ASK_SPREAD (1.0.0; swappable in tests).
Comm.random = math.random
function Comm.AskWait()
	return ASK_AFTER + Comm.random() * ASK_SPREAD
end

-- We join as soon as the game's own channels are in (General is /1 for two seconds), so
-- General/Trade/LocalDefense keep their usual numbers (/1, /2...), and at JOIN_BY whatever
-- happens. The census request follows (Comm.AskWait), once the channel has its number.
function Comm.JoinSoon(t, seenAt)
	local _, first = GetChannelName(1)
	if first and first ~= "" then seenAt = seenAt or t end
	if t >= JOIN_BY or (seenAt and t - seenAt >= 2) then
		Comm.JoinChannel()
		ns.After(Comm.AskWait(), "census request", Comm.AskCensus)
		return
	end
	ns.After(1, "join channel", function() Comm.JoinSoon(t + 1, seenAt) end)
end

-- For tests: the channel we joined.
function Comm.JoinedName() return joinedName end
function Comm.SetJoinedForTest(name) joinedName = name end

-- Our hidden channel after the game's own. Joined before them (a slow login), it took /1 and
-- pushed General to /2, Trade to /3: moved past each of the game's channels numbered after
-- it, they get their usual numbers back. The player's own channels and other addons' keep
-- theirs.
function Comm.KeepLast()
	if not joinedName or not GetChannelList then return end
	local swap = C_ChatInfo and C_ChatInfo.SwapChatChannelsByChannelIndex -- gp:chat-channels
	local infoOf = C_ChatInfo and C_ChatInfo.GetChannelInfoFromIdentifier
	if not swap or not infoOf then return end
	local ours = GetChannelName(joinedName) or 0
	if ours <= 0 then return end
	local list = { GetChannelList() }
	local stride = type(list[3]) == "boolean" and 3 or 2 -- (id, name, disabled) or (id, name)
	local after = {}
	for i = 1, #list, stride do
		local id = tonumber(list[i])
		local ok, info = pcall(infoOf, list[i + 1])
		-- The game's channels (General, Trade...) are zone channels; custom ones are not.
		if id and id > ours and ok and type(info) == "table" and (tonumber(info.zoneChannelID) or 0) > 0 then after[#after + 1] = id end
	end
	if #after == 0 then return end
	table.sort(after)
	local at = ours
	for _, id in ipairs(after) do
		if not pcall(swap, at, id) then break end
		at = id
	end
	channelIndex = GetChannelName(joinedName) or channelIndex
	ns.Log("channel %s moved from #%d to #%d", joinedName, ours, channelIndex)
end

-- Right after login we may think we are the reporter only because we have not heard our
-- guildmates yet (see MaybeBroadcast): no answers then.
local function Settled(now)
	return now - math.max(Comm.loginAt or 0, guildChangedAt) >= HELLO_EVERY + 10
end

-- The reporter answers, and the runner-up too (a little later): a client that just logged in
-- then has two senders' word on each guild at once, which the Crown needs (Data.KnownRank).
-- Every login asks, so with thousands of players requests never stop: an answer is the next
-- due report sent early (LastReport), and the reporter still sends one report per
-- BROADCAST_EVERY, the runner-up one per WITNESS_EVERY, however many ask.
Comm.Handle("Q1", function(dist, sender, text)
	if dist ~= "CHANNEL" then return end
	heardAsk = ns.Now() -- (our own ask waits on it: Comm.AskCensus)
	if not Comm.lastReport or not (Comm.isReporter or Comm.isRunnerUp) then return end
	local now = ns.Now()
	local every = Comm.isReporter and BROADCAST_EVERY or WITNESS_EVERY
	local gap = Comm.isReporter and ANSWER_GAP or WITNESS_ANSWER_GAP
	if not Settled(now) or now - lastAnswer < gap or now - LastReport(every) < ANSWER_MIN_AGE then return end
	lastAnswer = now
	stats.answered = stats.answered + 1
	-- A short random delay spreads the answers of every guild.
	local delay = Comm.isReporter and math.random(1, 8) or math.random(9, 16)
	local session = guildSession
	ns.After(delay, "census answer", function()
		SyncGuild()
		if session ~= guildSession then return end
		local later = ns.Now()
		if not (Comm.isReporter or Comm.isRunnerUp) or not Comm.lastReport or not Settled(later) then return end
		local period = Comm.isReporter and BROADCAST_EVERY or WITNESS_EVERY
		local last = LastReport(period)
		if later - last < ANSWER_MIN_AGE then return end
		Comm.Broadcast(Comm.lastReport)
		early = { every = period, due = last + period }
	end)
end)

-- Admission (0.9.3): one sender gets ADMIT_BURST messages at once and ADMIT_RATE a second
-- after that, whatever they are (a census report is 30 pieces at most, every 3 minutes); past
-- it their messages are dropped unread. At most ADMIT_SENDERS senders are tracked (the ones
-- quiet for a minute are forgotten first), so the table itself stays small.
Comm.ADMIT_BURST = 60
Comm.ADMIT_RATE = 2
Comm.ADMIT_SENDERS = 3000
local admit, admitCount = {}, 0
local admitFirst, admitLast -- oldest/latest activity, including throttled messages
local function TouchAdmission(b)
	if admitLast == b then return end
	if b.prev then b.prev.next = b.next elseif admitFirst == b then admitFirst = b.next end
	if b.next then b.next.prev = b.prev end
	b.prev, b.next = admitLast, nil
	if admitLast then admitLast.next = b else admitFirst = b end
	admitLast = b
end
-- now is the monotonic GetTime clock, shared by all admission calls.
function Comm.Admit(sender, now)
	local b = admit[sender]
	if not b then
		if admitCount >= Comm.ADMIT_SENDERS then
			-- Calls use a monotonic clock, so the head alone decides whether any sender
			-- is idle. Reuse one expired slot; never scan the whole table on a miss.
			b = admitFirst
			if not b or now - b.t <= 60 then stats.admitted = (stats.admitted or 0) + 1 return false end
			admitFirst = b.next
			if admitFirst then admitFirst.prev = nil else admitLast = nil end
			admit[b.name], admitCount = nil, admitCount - 1
			b.prev, b.next = nil, nil
		else
			b = {}
		end
		b.name, b.tokens, b.t = sender, Comm.ADMIT_BURST, now
		admit[sender], admitCount = b, admitCount + 1
	end
	b.tokens = math.min(Comm.ADMIT_BURST, b.tokens + (now - b.t) * Comm.ADMIT_RATE)
	b.t = now
	TouchAdmission(b)
	if b.tokens < 1 then
		stats.throttled = (stats.throttled or 0) + 1
		return false
	end
	b.tokens = b.tokens - 1
	return true
end
function Comm.ResetAdmission() wipe(admit); admitCount, admitFirst, admitLast = 0, nil, nil end

-- A client outside any Olympus guild (1.1): over its own guild it puts together the pieces of the
-- author's signed titles list alone (HT), which names the approved guilds (ns.IsApprovedGuild):
-- the members of such a guild have nothing else to learn it from. Nothing else is read, kept or
-- answered; a blocked sender, and one past the admission budget, are dropped as ever, and the list
-- is checked like any other (Workshop.TakeTitles: the signature, the budgets of checks).
function Comm.Outsider(sender, text)
	SyncGuild()
	if not IsInGuild() or type(text) ~= "string" or not text:match("^C%w+:") then return end
	if ns.db.blocked[sender:lower()] or not Comm.Admit(sender, GetTime()) then return end
	stats.outsider = (stats.outsider or 0) + 1
	local full = Codec.Feed(outsiderAsm, sender, text, ns.Now())
	if full and full:sub(1, 3) == "HT~" and handlers.HT then handlers.HT("GUILD", sender, full) end
end
function Comm.ResetOutsider() outsiderAsm = Codec.NewAssembler() end -- (tests)

local function OnAddonMessage(prefix, text, dist, sender, target, zoneChannelID, localID, channelName)
	local admittedSender = injectedSender
	injectedSender = nil -- one Inject invocation only, never a reentrant native packet
	-- (1.5.5) A value the client keeps secret (a chat lockdown) is never compared or read: the prefix
	-- first (every addon's messages come here: a secret one can't be told ours, so it is not counted
	-- in /oly bug), then what ours carries (counted).
	if ns.Secret(nil, prefix) or prefix ~= ns.PREFIX then return end
	if ns.Secret("addon message", text, dist, sender, target, localID, channelName) then return end
	if type(sender) ~= "string" or sender == "" or type(text) ~= "string" then return end
	SyncGuild()
	-- Nothing another player sends reaches a screen, a tooltip, the map, a popup or a copy box
	-- with an escape code in it (0.9.2): every message but a chat line loses its "|" and its
	-- control bytes here, before the pieces are put together or any handler reads it (a census
	-- report, a layer, a decree, the King's word, a hello...). No message of ours needs either
	-- (a bug report travels with its pipes as "!" and its line breaks as "\n"). A chat line
	-- keeps the links Codec.SanitizeChat allows, and nothing else (Channels.lua).
	if text:sub(1, 3) ~= "M1~" and text:sub(1, 3) ~= "M2~" then text = Codec.Plain(text) end
	-- Only our channel counts: an outsider in any other channel we sit in could otherwise
	-- reach us there, past the sealed channel. Clients that don't give the number pass.
	if dist == "CHANNEL" then
		if not stats.chanArgs then
			stats.chanArgs = ("localID=%s name=%s target=%s"):format(tostring(localID), tostring(channelName), tostring(target))
		end
		if type(localID) == "number" and localID > 0 and localID ~= channelIndex then
			-- Our number may be stale (just after a /reload, or the channel moved): ask again.
			local name = joinedName or Comm.ChannelSpec()
			local id = name and GetChannelName and GetChannelName(name) or 0
			if id and id > 0 and joinedName then channelIndex = id end
			if id ~= localID then
				stats.otherChannel = stats.otherChannel + 1
				return
			end
		end
	end
	-- The sender as the server sent it: which realms get a suffix tells the realms apart.
	local lane, rawRealm = dist == "CHANNEL" and "ch" or "g", sender:match("%-(.+)$")
	Count(stats.raw[lane], rawRealm or "bare")
	local sample = stats.rawSample[lane]
	if not sample or (rawRealm and not sample:find("-", 1, true)) then stats.rawSample[lane] = sender end
	-- Same-realm senders arrive without "-Realm": make every name "Name-Realm" once, here
	-- (and Forever's "First-Surname" the server's "First Surname": ns.Normal).
	sender = ns.FullName(ns.Normal(sender))
	if sender == ns.me then
		stats.echo = stats.echo + 1 -- our own message coming back (proves the channel works)
		return
	end
	if not ns.IsMember() then
		-- Outside an Olympus guild the addon hears nothing of the army, but for two things (1.1): the
		-- Join screen's route/card answers, J2 and QD, whispered by a member it asked, and the
		-- author's signed titles list over its own guild, which may make that guild an Olympus guild
		-- (Comm.Outsider). (1.2.5.1) In an Olympus guild before the Olympus Accord is accepted
		-- (Accord.lua) the titles list alone: such a member asked nobody for a route.
		local outsideType = text:sub(1, 3)
		if dist == "WHISPER" and (outsideType == "J2~" or outsideType == "QD~") and outsideHandler and not ns.InOlympusGuild()
			and not ns.db.blocked[sender:lower()] and Comm.Admit(sender, GetTime()) then
			ns.SafeCall("join route", outsideHandler, sender, text)
		end
		if dist == "GUILD" then Comm.Outsider(sender, text) end
		return
	end
	if ns.db.blocked[sender:lower()] then return end
	-- (1.5.4) A client marked as a modified build (Builds.lua) is locked out here, as a blocked one is:
	-- nothing of its reaches a handler, the census or the relay, but its hello and its version answer,
	-- which clear the mark when they name a release. Our own client is never marked.
	local B = ns.Builds
	if B and not B.missing and B.Quarantined(sender) then
		B.Heard(sender) -- (online: the author's update ask may go to it, Builds.Prompt)
		if not B.Passes(text) then
			stats.quarantined = (stats.quarantined or 0) + 1
			return
		end
	end
	-- A relay's own word was already admitted with its envelope. Unwrapping it on this
	-- same call stack must not spend a second token; a different forwarded origin still does.
	if sender ~= admittedSender and not Comm.Admit(sender, GetTime()) then return end
	stats.recv = stats.recv + 1
	-- Olympus Link (0.9.10; 1.4.0 its own addon, Olympus_Link): a High Councillor's addon waiting to
	-- hear the author (Link.HeardFrom)
	-- sees who speaks; only while it waits: otherwise nil, and no message pays for it.
	local hook = Comm.senderHook
	if hook then ns.SafeCall("link author", hook, sender, dist) end
	local kind = (dist == "CHANNEL" and "ch:" or "g:") .. (text:match("^C%w+:") and "chunk" or text:sub(1, 2))
	Count(stats.byType, kind) -- (unknown prefixes fold into "other": a flood of them stays small)
	local now = ns.Now()
	-- Realm key, only over GUILD (server-verified guildmates) and only from our officers.
	if dist == "GUILD" and text:sub(1, 3) == "K1~" then
		local rank = ns.Roster.RankOf(sender)
		if rank and rank <= ns.CAPTAIN_RANK then
			local key = text:sub(4)
			if key ~= "" and key ~= ns.rdb.realmKey then
				-- 1.1 (Keys.lua): a key a newer one replaced here (the King's rotation, an officer's
				-- 1.1 /oly key) no longer comes back without an epoch; any other still does.
				if ns.Keys.TakesLegacy and ns.Keys.TakesLegacy(key) == false then
					ns.Log("realm key from officer %s ignored: a key a newer one replaced", sender)
				else
					ns.rdb.realmKey = key
					ns.Log("realm key received from officer %s", sender)
					Comm.JoinChannel()
				end
			end
		end
		return
	end
	if dist == "GUILD" and text:sub(1, 3) == "K0~" then
		-- A guildmate asks for the key: officers who have it answer (at most once a minute).
		if ns.rdb.realmKey and ns.Roster.IsOfficer() and now - (Comm.lastKeyAnswer or 0) > 60 then
			Comm.lastKeyAnswer = now
			local session = guildSession
			local function MayAnswer()
				return session == guildSession and ns.IsMember() and ns.Roster.IsOfficer() and ns.rdb.realmKey ~= nil
			end
			ns.After(math.random(1, 5), "key answer", function()
				SyncGuild()
				if not MayAnswer() then return end
				-- 1.1 (Keys.lua): with its epoch (and the keys it replaced). 1.4.0: as K8 alone, no plain
				-- K1: an older version asking gets no key (Keys.lua, 1.4.0).
				local k3 = ns.Keys.HandOutMessage and ns.Keys.HandOutMessage()
				if type(k3) == "string" then Enqueue("GUILD", { k3 }, "key3", nil, nil, nil, nil, { guard = MayAnswer }) end
			end)
		end
		return
	end
	if dist == "GUILD" and text:sub(1, 3) == "H1~" then
		if not peers[sender] then ns.Log("peer %s (%s)", sender, text:sub(4)) end
		peers[sender] = now
		-- The realm the hello names, unless the server stamped another one than ours on its sender:
		-- then the server's (1.0.0, Konig's review of 1.0.0: a guildmate's hello naming our realm
		-- from another one was elected our realm's reporter, never heard on our channel).
		local named, stamped = Codec.RealmField(text:match("^H1~[^~]*~([^~]+)")) or "old", ns.RealmOf(sender)
		if named ~= "old" and stamped and stamped ~= ns.realm then named = stamped end
		peerRealm[sender] = named
		local version = text:match("^H1~([^~]+)")
		peerVersion[sender] = version and (version:match("^%d+%.%d+%.%d+$") or version:match("^%d+%.%d+%.%d+%.%d+$")) and version or "?"
		-- (1.5.4) The version as the hello says it, to the builds' record (Builds.lua): a form that is
		-- no release marks a modified build and locks its words out; a release clears the mark.
		local B = ns.Builds
		if B and not B.missing then B.Hello(sender, version or "", now) end
		local sealed = text:match("^H1~[^~]*~[^~]*~([^~]*)")
		peerSealed[sender] = (sealed == "s" or sealed == "p") and sealed or nil
		peerZone[sender] = text:match("^H1~[^~]*~[^~]*~[^~]*~([^~]*)") == "z" or nil
		peerBank[sender] = text:match("^H1~[^~]*~[^~]*~[^~]*~[^~]*~([^~]*)") == "b" or nil
		-- (1.4.1) His channel lane, and ours after it when a Lord or Captain of our guild is ahead.
		-- Relay-capable clients carry an explicit sixth field: empty is lane 0; malformed or
		-- out-of-range values name no usable lane and never become a crowd vote.
		local laneField = text:match("^H1~[^~]*~[^~]*~[^~]*~[^~]*~[^~]*~([^~]*)")
		local lane
		if laneField == "" then
			lane = 0
		elseif laneField then
			local digits = laneField:match("^L(%d+)$")
			local candidate = tonumber(digits)
			if candidate and laneField == "L" .. tostring(candidate) and candidate <= Comm.LANE_MAX then lane = candidate end
		end
		peerLane[sender] = lane and lane > 0 and lane or nil
		if laneField == nil then peerLaneUsable[sender] = nil else peerLaneUsable[sender] = lane ~= nil end
		peerRelay[sender] = text:match("^H1~[^~]*~[^~]*~[^~]*~[^~]*~[^~]*~[^~]*~([^~]*)") == "R" or nil -- (1.4.3)
		peerTree[sender] = text:match("^H1~[^~]*~[^~]*~[^~]*~[^~]*~[^~]*~[^~]*~[^~]*~N") ~= nil or nil -- (1.5.5)
		if lane and lane > Lane() then
			local rank = ns.Roster and ns.Roster.RankOf and ns.Roster.RankOf(sender)
			if type(rank) == "number" and rank <= (ns.CAPTAIN_RANK or 2) then Comm.TakeLane(lane, sender) end
		end
		return
	end
	local handler = handlers[text:sub(1, 2)]
	if handler and text:sub(3, 3) == "~" then
		Dispatch(handler, dist, sender, text)
		return
	end
	-- A piece, while the High Council's lists wait to answer an ask (1.0.0, Workshop.lua: an answer
	-- heard beginning holds ours back); nil otherwise, and no piece pays for it.
	local pieceHook = Comm.pieceHook
	if pieceHook and (dist == "GUILD" or dist == "CHANNEL") then ns.SafeCall("list piece", pieceHook, dist, sender, text) end
	-- 1.1: other modules' waiting answers the same way (Loot.lua's), each set only while it waits.
	if next(Comm.pieceHooks) ~= nil and (dist == "GUILD" or dist == "CHANNEL") then
		for key, fn in pairs(Comm.pieceHooks) do ns.SafeCall(key .. " piece", fn, dist, sender, text) end
	end
	if dist == "GUILD" then
		-- Pieces over GUILD (1.0.0): the High Council's lists cross to guildmates on other realms.
		-- Only those are put together; versions before 1.0.0 put nothing together from GUILD.
		local full = Codec.Feed(guildAsm, sender, text, now)
		local whole = full and full:sub(1, 2)
		if whole and GUILD_PIECES[whole] and full:sub(3, 3) == "~" and handlers[whole] then Dispatch(handlers[whole], dist, sender, full) end
		return
	end
	if dist == "WHISPER" then
		-- H2 is the only long private payload. It carries an independently signed authority part;
		-- Authority.lua still checks the route, signature, complete-set digest and replay boundary.
		local full = Codec.Feed(whisperAsm, sender, text, now)
		local kind = full and full:sub(1, 2)
		if kind and WHISPER_PIECES[kind] and full:sub(3, 3) == "~" and handlers[kind] then Dispatch(handlers[kind], dist, sender, full) end
		return
	end
	if dist == "CHANNEL" then
		local full = Codec.Feed(asm, sender, text, now)
		if not full then return end
		local fullHandler = handlers[full:sub(1, 2)]
		if fullHandler and full:sub(3, 3) == "~" then
			-- Put together from pieces: whether it came logged is known of the piece that ended it
			-- alone, so the whole never counts as logged (1.0.0). A chat line or a decree's words
			-- in plain pieces with an empty last piece logged were shown; no version sends either
			-- in pieces (Comm.SendChat, Comm.Send), so such a decree shows without its words and
			-- such a line is dropped (Decree.lua, Channels.lua).
			deliveredLogged = false
			Dispatch(fullHandler, dist, sender, full)
			return
		end
		-- (1.2.3) Its sender's last report again but for its time: that report's row, not decoded.
		local r = ns.Data.DecodeReport(full, sender)
		if not r then
			stats.bad = stats.bad + 1
			ns.Log("bad report from %s: %s", sender, full:sub(1, 80))
			return
		end
		stats.reports = stats.reports + 1
		-- A report naming another realm: the channel may cross realms (/oly status). Its sender
		-- wrote that realm, so it never turns the election (Comm.ElectsAcrossRealms).
		Count(stats.reportRealms, r.from or "old")
		if r.from and r.from ~= ns.realm then ns.rdb.shared = { realm = r.from, to = ns.realm, t = now } end
		-- Our guild's reporter is heard: the election guard (MaybeBroadcast) leaves it in.
		local own = GetGuildInfo("player")
		if own and r.guild:lower() == own:lower() then
			local short = ns.ShortName(sender)
			heardOwn[short] = now
			for name in pairs(benched) do
				if ns.ShortName(name) == short then benched[name] = nil end
			end
			-- Sent by a guildmate of another realm: our channel crosses realms (1.0.0).
			if PeerOfOtherRealm(sender, now) then crossedAt = now end
		end
		if ns.Data.Receive(r, sender) then
			ns.Log("report %s from %s: %d members, %d online", r.guild, sender, r.total, r.online)
		end
	end
end

-- Outside an Olympus guild the addon stays out of the channel (called when the guild changes).
-- Joining is left to the housekeeping ticker, so we never jump ahead of General/Trade at login.
function Comm.CheckMembership()
	SyncGuild()
	if ns.IsMember() then
		-- Joined an Olympus guild after login: ask for the census once we are on the channel.
		if stats.asked + stats.askSkipped == 0 then
			askTries = 0
			Comm.AskCensus()
		end
		return
	end
	if joinedName and GetChannelName(joinedName) > 0 then
		LeaveChannelByName(joinedName) -- gp:chat-channels
		ns.Log("left channel %s: not in an Olympus guild", joinedName)
		joinedName, channelIndex = nil, 0
	end
	DropQueue("left")
	DropChat("left")
end

-- Quiet presence turned off (Core.lua): our hello at once, so our guildmates count us again (the
-- census we may report follows at its own pace, MaybeBroadcast).
ns.On("QUIET_PRESENCE_CHANGED", function(on)
	if on == false and ns.IsMember() then Comm.Hello(true) end
end)

ns.On("LOGIN", function()
	Comm.loginAt = ns.Now()
	C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
	-- No key yet? Ask our guild once (officers who have it answer).
	ns.After(20, "key request", Comm.RequestKey)
	ns.RegisterEvent("CHAT_MSG_ADDON", OnAddonMessage)
	-- 1.4.3: a message the relay carried, taken as if it had come on the channel from its origin
	-- (Relay.lua); logged as its origin sent it.
	function Comm.Inject(dist, sender, text, logged)
		local was, previous = deliveredLogged, injectedSender
		deliveredLogged = logged == true
		injectedSender = dispatchSender
		local ok, err = pcall(OnAddonMessage, ns.PREFIX, text, dist, sender)
		deliveredLogged, injectedSender = was, previous
		if not ok and ns.CaptureError then pcall(ns.CaptureError, "relay inject", err) end
		return ok
	end
	-- Chat lines come through the logged API (the server keeps them, so they can be reported).
	ns.RegisterEvent("CHAT_MSG_ADDON_LOGGED", function(...)
		deliveredLogged = true
		local ok, err = pcall(OnAddonMessage, ...)
		deliveredLogged = false
		if not ok then error(err, 0) end
	end)
	-- Who holds our channel and what is done with it (the channel's owner, above).
	ns.RegisterEvent("CHAT_MSG_CHANNEL_NOTICE", Comm.OnChannelNotice)
	ns.RegisterEvent("CHAT_MSG_CHANNEL_NOTICE_USER", Comm.OnChannelNotice)
	ns.RegisterEvent("CHANNEL_PASSWORD_REQUEST", Comm.OnPasswordRequest)
	ns.RegisterEvent("ADDON_ACTION_BLOCKED", Comm.OnActionRefused)
	ns.RegisterEvent("ADDON_ACTION_FORBIDDEN", Comm.OnActionRefused)
	ns.After(3, "join channel", function() Comm.JoinSoon(3) end)
	ns.After(6, "hello", Comm.Hello)
	ns.Every(HELLO_EVERY, "hello ticker", Comm.Hello)
	ns.Every(SEND_INTERVAL, "send pump", Pump)
	ns.Every(60, "housekeeping", function()
		local dropped, sample = Codec.Gc(asm, ns.Now())
		Codec.Gc(guildAsm, ns.Now())
		Codec.Gc(outsiderAsm, ns.Now())
		Codec.Gc(whisperAsm, ns.Now())
		if dropped > 0 then
			stats.partial = stats.partial + dropped
			ns.Log("incomplete report dropped: %s", tostring(sample))
		end
		if channelIndex == 0 or GetChannelName(joinedName or (Comm.ChannelSpec())) == 0 then Comm.JoinChannel() end
		ns.SafeCall("follow crowd lane", Comm.FollowCrowd)
	end)
	-- The game joins its own channels (General, Trade...) after ours on a slow login: ours
	-- moves behind them once the list settles.
	-- Only in the minutes after we joined: later changes are the player's.
	local lastPending = false
	ns.RegisterEvent("CHANNEL_UI_UPDATE", function()
		if lastPending or ns.Now() - (Comm.joinedAt or 0) > 180 then return end
		lastPending = true
		ns.After(2, "channel last", function()
			lastPending = false
			Comm.KeepLast()
		end)
	end)
end)
