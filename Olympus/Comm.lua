local ADDON, ns = ...

-- GUILD: "hello" pings so members with the addon know each other and elect one reporter.
-- CHANNEL (hidden "OlympusNet"): the elected reporter of each guild broadcasts its summary.

local Comm = {}
ns.Comm = Comm
local Codec = ns.Codec

local HELLO_EVERY = 60
local PEER_WINDOW = 180 -- quiet members re-hello every 10 min; counted separately below
local BROADCAST_EVERY = 120
local SEND_INTERVAL = 1.2
local MAX_QUEUE = 60

local peers = {}
local queue = {}
local asm = Codec.NewAssembler()
local msgId = 0
local lastBroadcast = 0
local channelIndex = 0
local stats = { sent = 0, recv = 0, reports = 0, fails = 0, bad = 0 }

function Comm.PeerCount()
	local now, n = ns.Now(), 0
	for _, t in pairs(peers) do
		if now - t <= PEER_WINDOW then n = n + 1 end
	end
	return n
end

function Comm.Stats()
	return {
		channel = channelIndex, peers = Comm.PeerCount(), reporter = Comm.reporterName,
		isReporter = Comm.isReporter, sent = stats.sent, recv = stats.recv, reports = stats.reports,
		fails = stats.fails, bad = stats.bad, queue = #queue, lastFail = stats.lastFail,
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
	local item = queue[1]
	if not item then return end
	local dist, msg = item[1], item[2]
	local target
	if dist == "CHANNEL" then
		if channelIndex == 0 then return end -- wait until we joined
		target = channelIndex
	end
	table.remove(queue, 1)
	local ok, res = pcall(C_ChatInfo.SendAddonMessage, ns.PREFIX, msg, dist, target)
	if ok and IsSuccess(res) then
		stats.sent = stats.sent + 1
	else
		stats.fails = stats.fails + 1
		stats.lastFail = ("%s %s"):format(dist, tostring(res))
		ns.Log("send failed on %s: %s", dist, tostring(res))
	end
end

local function HideChannelFromChat()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local cf = _G["ChatFrame" .. i]
		if cf and ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, cf, ns.CHANNEL) end
	end
end

function Comm.JoinChannel()
	local id = GetChannelName(ns.CHANNEL)
	if id and id > 0 then
		if channelIndex ~= id then ns.Log("channel %s is #%d", ns.CHANNEL, id) end
		channelIndex = id
		HideChannelFromChat()
		return
	end
	ns.Log("joining channel %s", ns.CHANNEL)
	JoinChannelByName(ns.CHANNEL)
	ns.After(3, "channel check", function()
		channelIndex = GetChannelName(ns.CHANNEL) or 0
		ns.Log("channel %s -> #%d", ns.CHANNEL, channelIndex)
		HideChannelFromChat()
	end)
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
	-- Demo mode only changes what we display; our real roster is still reported.
	local now = ns.Now()
	Comm.reporterName = ns.ShortName(Codec.PickReporter(ns.me, peers, now, PEER_WINDOW))
	Comm.isReporter = Comm.reporterName == ns.ShortName(ns.me)
	if not Comm.isReporter or now - lastBroadcast < BROADCAST_EVERY then return end
	lastBroadcast = now
	msgId = (msgId + 1) % 1000
	local payload = Codec.EncodeReport(report)
	local chunks = Codec.Chunk(payload, tostring(msgId))
	for _, c in ipairs(chunks) do Enqueue("CHANNEL", c) end
	ns.Log("broadcast %s: %d bytes in %d chunks", report.guild, #payload, #chunks)
end

local function OnAddonMessage(prefix, text, dist, sender)
	if prefix ~= ns.PREFIX then return end
	if sender == ns.me or sender == ns.ShortName(ns.me) then return end -- our own echo
	stats.recv = stats.recv + 1
	local now = ns.Now()
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

ns.On("LOGIN", function()
	C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
	ns.RegisterEvent("CHAT_MSG_ADDON", OnAddonMessage)
	-- Join late so General/Trade/LocalDefense keep their usual numbers (/1, /2...).
	ns.After(15, "join channel", Comm.JoinChannel)
	ns.After(6, "hello", Comm.Hello)
	ns.Every(HELLO_EVERY, "hello ticker", Comm.Hello)
	ns.Every(SEND_INTERVAL, "send pump", Pump)
	ns.Every(60, "housekeeping", function()
		Codec.Gc(asm, ns.Now())
		if channelIndex == 0 or GetChannelName(ns.CHANNEL) == 0 then Comm.JoinChannel() end
	end)
end)
