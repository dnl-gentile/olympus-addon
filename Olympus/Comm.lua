local ADDON, ns = ...

-- GUILD: "hello" pings so members with the addon know each other and elect one reporter.
-- CHANNEL (hidden "OlympusNet"): the elected reporter of each guild broadcasts its summary.

local Comm = {}
ns.Comm = Comm
local Codec = ns.Codec

local HELLO_EVERY = 60
local PEER_WINDOW = 180  -- the election only trusts peers heard in the last 3 minutes
local COUNT_WINDOW = 720 -- quiet members say hello every 10 min: count them for 12
local BROADCAST_EVERY = 170
local SEND_INTERVAL = 1.2
local MAX_QUEUE = 60

local peers = {}
local queue = {}
local asm = Codec.NewAssembler()
local msgId = 0
local lastBroadcast = 0
local channelIndex = 0
local stats = { sent = 0, recv = 0, reports = 0, fails = 0, bad = 0, partial = 0, echo = 0, byType = {}, realms = {} }
local joinedName -- name of the channel we joined (set by Comm.JoinChannel)

function Comm.PeerCount()
	local now, n = ns.Now(), 0
	for _, t in pairs(peers) do
		if now - t <= COUNT_WINDOW then n = n + 1 end
	end
	return n
end

function Comm.Stats()
	return {
		channelName = joinedName, sealed = ns.rdb and ns.rdb.realmKey ~= nil,
		channel = channelIndex, peers = Comm.PeerCount(), reporter = Comm.reporterName,
		isReporter = Comm.isReporter, sent = stats.sent, recv = stats.recv, reports = stats.reports,
		fails = stats.fails, bad = stats.bad, queue = #queue, lastFail = stats.lastFail,
		partial = stats.partial, echo = stats.echo, byType = stats.byType, realms = stats.realms, pending = (function() local n = 0 for _ in pairs(asm.buf) do n = n + 1 end return n end)(),
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

local function IsSuccess(res)
	-- Older clients return a boolean, newer ones Enum.SendAddonMessageResult (0 = success).
	return res == nil or res == true or res == 0
end

local function Pump()
	if not queue[1] then return end
	if not ns.IsMember() then
		wipe(queue) -- outside an Olympus guild the addon sends nothing
		return
	end
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
	local target = dist == "CHANNEL" and channelIndex or nil
	table.remove(queue, index)
	local ok, res = pcall(C_ChatInfo.SendAddonMessage, ns.PREFIX, msg, dist, target)
	if ok and IsSuccess(res) then
		stats.sent = stats.sent + 1
	else
		stats.fails = stats.fails + 1
		stats.lastFail = ("%s %s"):format(dist, tostring(res))
		ns.Log("send failed on %s: %s", dist, tostring(res))
	end
end

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
	joinedName = name
	local id = GetChannelName(name)
	if id and id > 0 then
		if channelIndex ~= id then ns.Log("channel %s is #%d", name, id) end
		channelIndex = id
		HideChannelFromChat(name)
		return
	end
	ns.Log("joining channel %s%s", name, password and " (sealed)" or "")
	JoinChannelByName(name, password)
	ns.After(3, "channel check", function()
		channelIndex = GetChannelName(name) or 0
		ns.Log("channel %s -> #%d", name, channelIndex)
		HideChannelFromChat(name)
	end)
end

function Comm.ChannelName() return joinedName end

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
		if now - t <= PEER_WINDOW and name < (ns.me or "") then before = before + 1 end
	end
	if before >= 10 and now - lastHello < 600 then return end
	lastHello = now
	Enqueue("GUILD", "H1~" .. ns.VERSION, "hello")
end

function Comm.MaybeBroadcast(report)
	local now = ns.Now()
	-- Peers are keyed "Name-Realm" like ns.me, so every client compares the same strings.
	local best = Codec.PickReporter(ns.me, peers, now, PEER_WINDOW)
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
	-- Same-realm senders arrive without "-Realm": make every name "Name-Realm" once, here.
	sender = ns.FullName(sender)
	if not sender or sender == "" then return end
	if sender == ns.me then
		stats.echo = stats.echo + 1 -- our own message coming back (proves the channel works)
		return
	end
	if not ns.IsMember() then return end -- outside an Olympus guild the addon hears nothing
	if ns.db.blocked[sender:lower()] then return end
	stats.recv = stats.recv + 1
	local kind = (dist == "CHANNEL" and "ch:" or "g:") .. (text:match("^C%w+:") and "chunk" or text:sub(1, 2))
	stats.byType[kind] = (stats.byType[kind] or 0) + 1
	-- Which realms our messages come from answers whether the channel crosses realms.
	local realmKey = (dist == "CHANNEL" and "ch:" or "g:") .. (ns.RealmOf(sender) or "?")
	stats.realms[realmKey] = (stats.realms[realmKey] or 0) + 1
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
	end
end

ns.On("LOGIN", function()
	Comm.loginAt = ns.Now()
	C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
	-- No key yet? Ask our guild once (officers who have it answer).
	ns.After(20, "key request", function()
		if ns.IsMember() and not ns.rdb.realmKey then Enqueue("GUILD", "K0~", "keyreq") end
	end)
	ns.RegisterEvent("CHAT_MSG_ADDON", OnAddonMessage)
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
