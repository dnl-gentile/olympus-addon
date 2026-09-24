local ADDON, ns = ...

-- GUILD: "hello" pings so members with the addon know each other and elect one reporter.
-- CHANNEL (hidden "OlympusNet"): the elected reporter of each guild broadcasts its summary.
-- Chat lines of the channels (Channels.lua) ride the same hidden channel in a lane of their own.

local Comm = {}
ns.Comm = Comm
local Codec = ns.Codec

local HELLO_EVERY = 60
local PEER_WINDOW = 180  -- the election only trusts peers heard in the last 3 minutes
local COUNT_WINDOW = 720 -- quiet members say hello every 10 min: count them for 12
local BROADCAST_EVERY = 170
local SEND_INTERVAL = 1.2
local MAX_QUEUE = 60
local CHAT_QUEUE = 6  -- chat parts waiting in their own lane (two long lines)
local CHAT_TTL = 30   -- a chat part that waited this long is dropped, not sent late
local GUARD_AFTER = 400  -- an elected reporter never heard reporting our guild for this long...
local GUARD_FOR = 30 * 60 -- ...is left out of the election for this long (see MaybeBroadcast)
local KEY_ASK_EVERY = 600 -- at most one key request this often while a sealed reporter is elected
local MAX_KEYS = 20      -- distinct keys per diagnostic count (the rest count as "other")

local peers = {}
local queue = {}
local chatQueue = {}  -- chat lines (Channels.lua): { msg, done, t }
local lastWasChat = false
local asm = Codec.NewAssembler()
local msgId = 0
local lastBroadcast = 0
local channelIndex = 0
local stats = { sent = 0, recv = 0, reports = 0, fails = 0, bad = 0, partial = 0, echo = 0, byType = {},
	raw = { ch = {}, g = {} }, rawSample = {}, reportRealms = {} }
local joinedName -- name of the channel we joined (set by Comm.JoinChannel)
local peerRealm = {} -- guild peer -> realm from its hello, "old" for versions that send none
local peerSealed = {} -- guild peer -> "s" (on the sealed channel) or "p" (public), from its hello
-- Short name -> last time we heard it report our guild on the channel. Short: the server may
-- send a name with its realm over GUILD and without it over CHANNEL (names are region-unique
-- on the realmless client).
local heardOwn = {}
local benched = {}   -- guild peer -> time it may be elected again
local watch          -- { name, since }: the peer we elected while we are on the channel
local lastKeyAsk     -- when MaybeBroadcast last asked our guild for the key

-- count[key] + 1, with at most MAX_KEYS distinct keys (senders choose some of them).
local function Count(t, key)
	if t[key] == nil then
		local n = 0
		for _ in pairs(t) do n = n + 1 end
		if n >= MAX_KEYS then key = "other" end
	end
	t[key] = (t[key] or 0) + 1
end

function Comm.PeerCount()
	local now, n = ns.Now(), 0
	for _, t in pairs(peers) do
		if now - t <= COUNT_WINDOW then n = n + 1 end
	end
	return n
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
	return {
		channelName = joinedName, sealed = ns.rdb and ns.rdb.realmKey ~= nil,
		channel = channelIndex, peers = Comm.PeerCount(), reporter = Comm.reporterName,
		isReporter = Comm.isReporter, sent = stats.sent, recv = stats.recv, reports = stats.reports,
		fails = stats.fails, bad = stats.bad, queue = #queue, chatQueue = #chatQueue, lastFail = stats.lastFail,
		partial = stats.partial, echo = stats.echo, byType = stats.byType, pending = (function() local n = 0 for _ in pairs(asm.buf) do n = n + 1 end return n end)(),
		raw = stats.raw, rawSample = stats.rawSample, reportRealms = stats.reportRealms, shared = ns.rdb and ns.rdb.shared,
		peerRealms = PeerRealms(now), heardOwn = lastOwn and ns.DisplayName(lastOwn), heardOwnAt = lastOwn and lastOwnAt,
		benched = out,
	}
end

local function Enqueue(dist, msg, key)
	if key then
		for _, item in ipairs(queue) do
			if item[3] == key then
				item[2] = msg
				return
			end
		end
	end
	if #queue >= MAX_QUEUE then table.remove(queue, 1) end
	queue[#queue + 1] = { dist, msg, key }
end

-- Other modules send small messages through here and register a handler per type.
--   Comm.Send("GUILD" | "CHANNEL", msg, dedupeKey)
--   Comm.Handle("P1", function(dist, sender, text) ... end)
local handlers = {}
function Comm.Send(dist, msg, key)
	if dist == "GUILD" and not IsInGuild() then return end
	Enqueue(dist, msg, key)
end
function Comm.Handle(msgType, fn)
	handlers[msgType] = fn
end
-- Long payloads (> 255 bytes) go through the same chunking as reports.
function Comm.SendChunked(payload)
	msgId = (msgId + 1) % 1000
	for _, c in ipairs(Codec.Chunk(payload, tostring(msgId))) do Enqueue("CHANNEL", c) end
end
function Comm.ChannelReady()
	return channelIndex > 0
end

-- Chat lines wait in a short lane of their own: they never go through Enqueue, so they can
-- never push report chunks out of MAX_QUEUE. done(sent) is called once the part went out
-- (or was dropped). Returns false when the lane is full.
function Comm.SendChat(msg, done)
	if #chatQueue >= CHAT_QUEUE then return false end
	chatQueue[#chatQueue + 1] = { msg = msg, done = done, t = GetTime() }
	return true
end
function Comm.ChatRoom()
	return CHAT_QUEUE - #chatQueue
end

local function IsSuccess(res)
	-- Older clients return a boolean, newer ones Enum.SendAddonMessageResult (0 = success).
	return res == nil or res == true or res == 0
end

-- Player text goes through the logged API, Blizzard's function for plain text payloads
-- (receivers get CHAT_MSG_ADDON_LOGGED). Clients without it use the usual one.
local function SendNow(dist, msg, logged)
	local target = dist == "CHANNEL" and channelIndex or nil
	local send = logged and C_ChatInfo.SendAddonMessageLogged or C_ChatInfo.SendAddonMessage
	local ok, res = pcall(send, ns.PREFIX, msg, dist, target)
	if ok and IsSuccess(res) then
		stats.sent = stats.sent + 1
		return true
	end
	stats.fails = stats.fails + 1
	stats.lastFail = ("%s %s"):format(dist, tostring(res))
	ns.Log("send failed on %s: %s", dist, tostring(res))
	return false
end

-- Every chat part still waiting is dropped, and its sender is told.
local function DropChat()
	local items = {}
	for i, item in ipairs(chatQueue) do items[i] = item end
	wipe(chatQueue)
	for _, item in ipairs(items) do
		if item.done then ns.SafeCall("chat drop", item.done, false) end
	end
end

local function Pump()
	if not queue[1] and not chatQueue[1] then return end
	if not ns.IsMember() then
		wipe(queue) -- outside an Olympus guild the addon sends nothing
		DropChat()
		return
	end
	local now = GetTime()
	while chatQueue[1] and now - chatQueue[1].t > CHAT_TTL do
		local item = table.remove(chatQueue, 1)
		if item.done then ns.SafeCall("chat drop", item.done, false) end
	end
	-- Chat goes first, but while reports wait it takes at most every other slot: an idle lane
	-- sends a line within 1.2 s, and the total rate stays one message per SEND_INTERVAL.
	if chatQueue[1] and channelIndex > 0 and not (lastWasChat and queue[1]) then
		lastWasChat = true
		local item = table.remove(chatQueue, 1)
		local sent = SendNow("CHANNEL", item.msg, true)
		if item.done then ns.SafeCall("chat sent", item.done, sent) end
		return
	end
	lastWasChat = false
	-- Channel messages wait until we joined; guild messages behind them go out meanwhile.
	local index
	for i, item in ipairs(queue) do
		if item[1] ~= "CHANNEL" or channelIndex > 0 then
			index = i
			break
		end
	end
	if not index then return end
	local dist, msg = queue[index][1], queue[index][2]
	table.remove(queue, index)
	SendNow(dist, msg, false)
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

function Comm.ChannelSpec()
	local key = ns.rdb and ns.rdb.realmKey
	if key and key ~= "" then return "Oly" .. Hash36(key), key end
	return ns.CHANNEL, nil
end

local function HideChannelFromChat(name)
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local cf = _G["ChatFrame" .. i]
		if cf and ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, cf, name) end
	end
end

function Comm.JoinChannel()
	if not ns.IsMember() then return end
	local name, password = Comm.ChannelSpec()
	if joinedName and joinedName ~= name and GetChannelName(joinedName) > 0 then
		LeaveChannelByName(joinedName) -- the key changed: leave the old channel
		channelIndex = 0
	end
	if joinedName ~= name then watch = nil end -- another channel: the election guard starts again
	joinedName = name
	local id = GetChannelName(name)
	if id and id > 0 then
		if channelIndex ~= id then ns.Log("channel %s is #%d", name, id) end
		channelIndex = id
		HideChannelFromChat(name)
		return
	end
	ns.Log("joining channel %s%s", name, password and " (sealed)" or "")
	watch = nil -- time off this channel says nothing about what we hear on it (election guard)
	JoinChannelByName(name, password)
	ns.After(3, "channel check", function()
		channelIndex = GetChannelName(name) or 0
		ns.Log("channel %s -> #%d", name, channelIndex)
		HideChannelFromChat(name)
	end)
end

function Comm.ChannelName() return joinedName end

-- No key? Ask our guild (officers who have it answer, over GUILD).
function Comm.RequestKey()
	if ns.IsMember() and ns.rdb and not ns.rdb.realmKey then Enqueue("GUILD", "K0~", "keyreq") end
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
	ns.rdb.realmKey = secret
	Enqueue("GUILD", "K1~" .. secret, "key")
	ns.Print(ns.L.KEY_SET)
	Comm.JoinChannel()
end

-- In a full guild, 1000 members saying hello every minute would be ~16 messages per second.
-- Only names that could win the reporter election need to keep talking: once 10 members
-- that sort before us are known, we go quiet (still one hello per 10 minutes to be counted).
local lastHello = 0
function Comm.Hello()
	if not IsInGuild() then return end
	local now, before = ns.Now(), 0
	for name, t in pairs(peers) do
		if now - t <= PEER_WINDOW and name < (ns.me or "") and (benched[name] or 0) <= now then before = before + 1 end
	end
	if before >= 10 and now - lastHello < 600 then return end
	lastHello = now
	-- Our realm rides along: guildmates on another realm show in /oly status (topology). So does
	-- our channel: without the key we can't hear a reporter on the sealed one (MaybeBroadcast).
	local sealed = ns.rdb and ns.rdb.realmKey and "s" or "p"
	Enqueue("GUILD", "H1~" .. ns.VERSION .. "~" .. tostring(ns.realm) .. "~" .. sealed, "hello")
end

-- The peers that may be elected: every one, but those left out by the guard below.
local function Electable(now)
	local pool = {}
	for name, t in pairs(peers) do
		if (benched[name] or 0) <= now then pool[name] = t end
	end
	return pool
end

function Comm.MaybeBroadcast(report)
	local now = ns.Now()
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
	elseif best ~= ns.me and channelIndex > 0 then
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
	if not Comm.isReporter or now - lastBroadcast < BROADCAST_EVERY then return end
	-- Right after login we don't know our guildmates yet and would wrongly think we are the
	-- reporter: wait one hello round first.
	if now - (Comm.loginAt or 0) < HELLO_EVERY + 10 then return end
	lastBroadcast = now
	msgId = (msgId + 1) % 1000
	local payload = Codec.EncodeReport(report)
	local chunks = Codec.Chunk(payload, tostring(msgId))
	for _, c in ipairs(chunks) do Enqueue("CHANNEL", c) end
	ns.Log("broadcast %s: %d bytes in %d chunks", report.guild, #payload, #chunks)
end

local function OnAddonMessage(prefix, text, dist, sender)
	if prefix ~= ns.PREFIX then return end
	if type(sender) ~= "string" or sender == "" then return end
	-- The sender as the server sent it: which realms get a suffix tells the realms apart.
	local lane, rawRealm = dist == "CHANNEL" and "ch" or "g", sender:match("%-(.+)$")
	Count(stats.raw[lane], rawRealm or "bare")
	local sample = stats.rawSample[lane]
	if not sample or (rawRealm and not sample:find("-", 1, true)) then stats.rawSample[lane] = sender end
	-- Same-realm senders arrive without "-Realm": make every name "Name-Realm" once, here.
	sender = ns.FullName(sender)
	if sender == ns.me then
		stats.echo = stats.echo + 1 -- our own message coming back (proves the channel works)
		return
	end
	if not ns.IsMember() then return end -- outside an Olympus guild the addon hears nothing
	if ns.db.blocked[sender:lower()] then return end
	stats.recv = stats.recv + 1
	local kind = (dist == "CHANNEL" and "ch:" or "g:") .. (text:match("^C%w+:") and "chunk" or text:sub(1, 2))
	stats.byType[kind] = (stats.byType[kind] or 0) + 1
	local now = ns.Now()
	-- Realm key, only over GUILD (server-verified guildmates) and only from our officers.
	if dist == "GUILD" and text:sub(1, 3) == "K1~" then
		local rank = ns.Roster.RankOf(sender)
		if rank and rank <= ns.CAPTAIN_RANK then
			local key = text:sub(4)
			if key ~= "" and key ~= ns.rdb.realmKey then
				ns.rdb.realmKey = key
				ns.Log("realm key received from officer %s", sender)
				Comm.JoinChannel()
			end
		end
		return
	end
	if dist == "GUILD" and text:sub(1, 3) == "K0~" then
		-- A guildmate asks for the key: officers who have it answer (at most once a minute).
		if ns.rdb.realmKey and ns.Roster.IsOfficer() and now - (Comm.lastKeyAnswer or 0) > 60 then
			Comm.lastKeyAnswer = now
			ns.After(math.random(1, 5), "key answer", function() Enqueue("GUILD", "K1~" .. ns.rdb.realmKey, "key") end)
		end
		return
	end
	if dist == "GUILD" and text:sub(1, 3) == "H1~" then
		if not peers[sender] then ns.Log("peer %s (%s)", sender, text:sub(4)) end
		peers[sender] = now
		peerRealm[sender] = Codec.RealmField(text:match("^H1~[^~]*~([^~]+)")) or "old"
		local sealed = text:match("^H1~[^~]*~[^~]*~([^~]*)")
		peerSealed[sender] = (sealed == "s" or sealed == "p") and sealed or nil
		return
	end
	local handler = handlers[text:sub(1, 2)]
	if handler and text:sub(3, 3) == "~" then
		handler(dist, sender, text)
		return
	end
	if dist == "CHANNEL" then
		local full = Codec.Feed(asm, sender, text, now)
		if not full then return end
		local fullHandler = handlers[full:sub(1, 2)]
		if fullHandler and full:sub(3, 3) == "~" then
			fullHandler(dist, sender, full)
			return
		end
		local r = Codec.DecodeReport(full)
		if not r then
			stats.bad = stats.bad + 1
			ns.Log("bad report from %s: %s", sender, full:sub(1, 80))
			return
		end
		stats.reports = stats.reports + 1
		-- A report from a reporter on another realm proves the channel crosses realms.
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
		end
		if ns.Data.Receive(r, sender) then
			ns.Log("report %s from %s: %d members, %d online", r.guild, sender, r.total, r.online)
		end
	end
end

-- Outside an Olympus guild the addon stays out of the channel (called when the guild changes).
-- Joining is left to the housekeeping ticker, so we never jump ahead of General/Trade at login.
function Comm.CheckMembership()
	if ns.IsMember() then return end
	if joinedName and GetChannelName(joinedName) > 0 then
		LeaveChannelByName(joinedName)
		ns.Log("left channel %s: not in an Olympus guild", joinedName)
		joinedName, channelIndex = nil, 0
		wipe(queue)
		DropChat()
	end
end

ns.On("LOGIN", function()
	Comm.loginAt = ns.Now()
	C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
	-- No key yet? Ask our guild once (officers who have it answer).
	ns.After(20, "key request", Comm.RequestKey)
	ns.RegisterEvent("CHAT_MSG_ADDON", OnAddonMessage)
	ns.RegisterEvent("CHAT_MSG_ADDON_LOGGED", OnAddonMessage) -- chat lines (same payload)
	-- Join late so General/Trade/LocalDefense keep their usual numbers (/1, /2...).
	ns.After(15, "join channel", Comm.JoinChannel)
	ns.After(6, "hello", Comm.Hello)
	ns.Every(HELLO_EVERY, "hello ticker", Comm.Hello)
	ns.Every(SEND_INTERVAL, "send pump", Pump)
	ns.Every(60, "housekeeping", function()
		local dropped, sample = Codec.Gc(asm, ns.Now())
		if dropped > 0 then
			stats.partial = stats.partial + dropped
			ns.Log("incomplete report dropped: %s", tostring(sample))
		end
		if channelIndex == 0 or GetChannelName(joinedName or ns.CHANNEL) == 0 then Comm.JoinChannel() end
	end)
end)
