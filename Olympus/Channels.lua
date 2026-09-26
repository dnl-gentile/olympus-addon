local ADDON, ns = ...
local L = ns.L

-- Chat channels of the federation, carried as M1 messages on the hidden Olympus channel:
--   [Olympus]  /ol   every member of every Olympus guild
--   [Captains] /olc  rank 0-1 of any Olympus guild
--   [Lords]    /oll  the Crown: guild masters and the officers of <Olympus>
-- Higher ranks also use the channels below theirs. Every addon client receives every line
-- (nothing is encrypted): each client shows a line only when its own rank is high enough
-- and the sender's rank is verified, never taken from the message. No WoW channel number.

local Channels = {}
ns.Channels = Channels
local Codec = ns.Codec

local SEND_GAP = 1.5             -- we send at most one line every 1.5 s
local BUCKET_SIZE = 6            -- per sender: a burst of 6 parts, then one every 1.2 s
local BUCKET_REFILL = 1.2        -- (an unmodified client never goes faster than that)
local MAX_SHOWN_PER_MINUTE = 60  -- flood guard per channel
local FAIR_SHARE = 10            -- once a channel is half full, no sender gets more lines than this a minute
local DEDUPE_WINDOW = 120
local HISTORY = 100              -- lines kept per channel
local LOG_GAP = 60               -- at most one "dropped" log line per sender per minute

-- Gold, teal and royal purple: none of them is a colour Blizzard's chat already uses.
local TIERS = {
	A = { level = 1, label = "CHAN_ALL",      slash = "/ol",  word = "olympus",  deny = "MEMBERS_ONLY",       color = { 0.90, 0.77, 0.36 } },
	C = { level = 2, label = "CHAN_CAPTAINS", slash = "/olc", word = "captains", deny = "CHAN_ONLY_CAPTAINS", color = { 0.35, 0.85, 0.85 } },
	L = { level = 3, label = "CHAN_LORDS",    slash = "/oll", word = "lords",    deny = "CHAN_ONLY_LORDS",    color = { 0.75, 0.50, 1.00 } },
}
Channels.TIERS, Channels.ORDER = TIERS, { "A", "C", "L" }

local stats = { sent = 0, shown = 0, hidden = 0, bad = 0, dup = 0, rate = 0, flood = 0, forged = 0, unverified = 0, rank = 0, ignored = 0 }
local seen = {}      -- "sender#id#text" -> time: every part is shown once
local buckets = {}   -- sender -> { tokens, t }
local recent = {}    -- tier -> { { t, sender } } of the lines shown in the last minute
local lastLog = {}   -- sender -> time of the last drop we logged
local lastSend = -math.huge
local mine = {}      -- "id#text" -> time: our own lines, shown when sent (their echo is not shown again)
local nextId = math.random(0, 9999)

local function Label(tier)
	return L[TIERS[tier].label]
end

local function Muted()
	ns.db.chatMute = ns.db.chatMute or {}
	return ns.db.chatMute
end

-- History is per realm, like the census.
local function Store(tier)
	ns.rdb.chat = ns.rdb.chat or {}
	local list = ns.rdb.chat[tier]
	if not list then
		list = {}
		ns.rdb.chat[tier] = list
	end
	return list
end

local function NextId()
	nextId = (nextId + 1) % 10000
	return nextId
end

---------------------------------------------------------------------------
-- Who may read and write what. Levels: 0 outside Olympus, 1 member, 2 Captain, 3 Lord.
---------------------------------------------------------------------------

function Channels.LevelOf(guild, rankIndex)
	if not ns.IsFederation(guild) then return 0 end
	-- To keep [Lords] for guild masters only, use rankIndex == 0 here instead of the Crown.
	if rankIndex and ns.IsCrownRank(guild, rankIndex) then return 3 end
	if rankIndex and rankIndex <= ns.CAPTAIN_RANK then return 2 end
	return 1
end

-- Our own rank always comes from the server.
function Channels.MyLevel()
	if not ns.IsMember() then return 0 end
	return Channels.LevelOf(GetGuildInfo("player"), ns.Roster.MyRank())
end

function Channels.CanUse(tier)
	local t = TIERS[tier]
	return t ~= nil and Channels.MyLevel() >= t.level
end

-- The level a sender really has, and whether it was verified. Our own guild: from our
-- roster. Other guilds: from that guild's fresh report (leader or officer), and a sender
-- speaks for one guild only (Data.ClaimGuild). Returns 0 when the guild claim is false.
function Channels.VerifiedLevel(sender, guild)
	local who = ns.FullName(sender)
	local rank = ns.Roster.RankOf(who)
	local mine = GetGuildInfo("player")
	if mine and guild:lower() == mine:lower() then
		if guild ~= mine then return 0, false end -- our name spelled another way (names ignore case)
		if rank then return Channels.LevelOf(guild, rank), true end
		if ns.Roster.byName == nil then return 1, false end -- roster not read yet
		return 0, false -- not in our roster: not one of us
	end
	if rank then return 0, false end -- a guildmate of ours speaking for another guild
	if not ns.Data.ClaimGuild(who, guild) then return 0, false end
	local known = ns.Data.KnownRank(who, guild)
	if known == nil then return 1, false end
	return Channels.LevelOf(guild, known), true
end

---------------------------------------------------------------------------
-- Display and history
---------------------------------------------------------------------------

-- "[Captains] [Name] <Guild>: text". The name is a player link, like in any chat line, so a
-- click opens the usual whisper and menu (to the name the server finds, ns.TellName). The
-- text is sanitized again here: history comes from the SavedVariables too.
function Channels.FormatLine(tier, sender, guild, class, text)
	local name = ns.DisplayName(sender) or "?"
	local file = class and ns.CLASS_FILES[class]
	local color = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
	if color and color.colorStr then name = "|c" .. color.colorStr .. name .. "|r" end
	return "[" .. Label(tier) .. "] |Hplayer:" .. (ns.TellName(sender) or "?") .. "|h[" .. name .. "]|h <"
		.. tostring(guild or "?"):gsub("|", "||") .. ">: " .. Codec.SanitizeChat(text)
end

-- A plain AddMessage on the default chat frame (what print does): nothing of Blizzard's is
-- replaced or hooked.
local function Show(tier, sender, guild, class, text)
	local f = DEFAULT_CHAT_FRAME
	if not f then return end
	local c = TIERS[tier].color
	f:AddMessage(Channels.FormatLine(tier, sender, guild, class, text), c[1], c[2], c[3])
end

local function AddHistory(tier, e)
	local list = Store(tier)
	list[#list + 1] = { t = ns.Now(), sender = e.sender, guild = e.guild, class = e.class, text = e.text, mine = e.mine }
	while #list > HISTORY do table.remove(list, 1) end
end

local function Accept(tier, sender, guild, class, text, mine)
	AddHistory(tier, { sender = sender, guild = guild, class = class, text = text, mine = mine or nil })
	ns.Fire("CHAT_CHANGED", tier)
	if Muted()[tier] then return false, "muted" end
	Show(tier, sender, guild, class, text)
	stats.shown = stats.shown + 1
	return true, "ok"
end

-- The lines of a channel we may read (for a future Channels view, with CHAT_CHANGED).
function Channels.History(tier)
	if not Channels.CanUse(tier) then return {} end
	return Store(tier)
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

local function Locked()
	return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() and true or false
end

-- Returns ok, reason. Every refusal tells the player why.
function Channels.Send(tier, text, now)
	local t = TIERS[tier]
	if not t then return false, "tier" end
	if not ns.IsMember() then
		ns.Print(L.MEMBERS_ONLY)
		return false, "member"
	end
	if not Channels.CanUse(tier) then
		ns.Print(L[t.deny]:format(Label(tier)))
		return false, "rank"
	end
	text = Codec.SanitizeChat(text)
	if text == "" then
		ns.Print(L.CHAN_USAGE:format(t.slash, Label(tier)))
		return false, "empty"
	end
	if Locked() then
		ns.Print(L.CHAN_LOCKDOWN)
		return false, "lockdown"
	end
	now = now or GetTime()
	if now - lastSend < SEND_GAP then
		ns.Print(L.CHAN_TOO_FAST)
		return false, "fast"
	end
	if not ns.Comm.ChannelReady() then
		ns.Print(L.CHAN_NOT_READY)
		return false, "ready"
	end
	local guild = GetGuildInfo("player")
	local class = ns.Roster.ClassCode(UnitClass and select(2, UnitClass("player")))
	-- Classes without a 2 letter code travel without a class (the decoder only takes 2 letters).
	if not class:match("^%u%u$") then class = "" end
	local parts, cut = Codec.SplitChat(text, Codec.ChatBudget(guild, class), Codec.CHAT_PARTS)
	if ns.Comm.ChatRoom() < #parts then
		ns.Print(L.CHAN_BUSY)
		return false, "busy"
	end
	if cut then ns.Print(L.CHAN_TRUNCATED) end
	if Muted()[tier] then
		Muted()[tier] = nil
		ns.Print(L.CHAN_UNMUTED:format(Label(tier)))
	end
	lastSend = now
	local failed = false
	for _, part in ipairs(parts) do
		local function done(sent)
			if not sent then
				if not failed then ns.Print(L.CHAN_SEND_FAILED:format(Label(tier))) end
				failed = true
				return
			end
			stats.sent = stats.sent + 1
			Accept(tier, ns.me, guild, class ~= "" and class or nil, part, true) -- our echo: exactly what the others see
			if not ns.db.chatNoticeShown then
				ns.db.chatNoticeShown = true
				ns.Print(L.CHAN_NOTICE)
			end
		end
		local id = NextId()
		-- Kept a while: when this line comes back from the channel it is ours, whatever form
		-- the server gave our name in (a line shown twice to its author otherwise).
		mine[id .. "#" .. Codec.SanitizeChat(part)] = now
		local msg = Codec.EncodeChat(tier, guild, id, class, part)
		if not msg or ns.Comm.SendChat(msg, done) == false then done(false) end
	end
	return true, "ok"
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local function LogDrop(sender, m, reason, now)
	if lastLog[sender] and now - lastLog[sender] < LOG_GAP then return end
	lastLog[sender] = now
	ns.Log("chat [%s] from %s <%s> dropped: %s", m.tier, sender, m.guild, reason)
end

local function Ignored(sender)
	local api = C_FriendList and C_FriendList.IsIgnored
	if not api then return false end
	local ok, res = pcall(api, ns.DisplayName(sender))
	return ok and res == true
end

-- Flood guard per channel, so [Olympus] traffic never silences [Captains] or [Lords]. Once a
-- channel is half full, a sender who already had FAIR_SHARE lines in it waits: one or two
-- spammers can't take the whole minute from everyone else.
local function Flooded(tier, sender, now)
	local list = recent[tier] or {}
	recent[tier] = list
	local mine = 0
	for i = #list, 1, -1 do
		if now - list[i].t > 60 then
			table.remove(list, i)
		elseif list[i].sender == sender then
			mine = mine + 1
		end
	end
	if #list >= MAX_SHOWN_PER_MINUTE or (#list >= MAX_SHOWN_PER_MINUTE / 2 and mine >= FAIR_SHARE) then return true end
	list[#list + 1] = { t = now, sender = sender }
	return false
end

-- Returns shown, reason.
function Channels.Receive(dist, sender, text, now)
	if dist ~= "CHANNEL" then return false, "dist" end
	now = now or GetTime()
	sender = ns.FullName(sender)
	local m = Codec.DecodeChat(text)
	if not m or not ns.IsFederation(m.guild) then
		stats.bad = stats.bad + 1
		return false, "bad"
	end
	local level = TIERS[m.tier].level
	-- Above our rank: not shown, not kept, not logged.
	if Channels.MyLevel() < level then
		stats.hidden = stats.hidden + 1
		return false, "tier"
	end
	if Ignored(sender) then
		stats.ignored = stats.ignored + 1
		return false, "ignored"
	end
	-- The server stamps the sender, so this key can't be forged. The text is part of it: ids
	-- start again at random after a /reload, and a reused id must not hide a new line.
	local key = sender .. "#" .. m.id .. "#" .. m.text
	-- Our own line coming back (already shown when sent): the same id and text, from a name
	-- that is ours however it is written ("First-Surname", "First Surname", with a realm or not).
	local own = mine[m.id .. "#" .. m.text]
	if own and now - own < DEDUPE_WINDOW and Channels.IsMe(sender) then
		stats.dup = stats.dup + 1
		return false, "own"
	end
	if seen[key] and now - seen[key] < DEDUPE_WINDOW then
		stats.dup = stats.dup + 1
		return false, "dup"
	end
	seen[key] = now
	local b = buckets[sender]
	if not b then
		b = { tokens = BUCKET_SIZE, t = now }
		buckets[sender] = b
	end
	b.tokens = math.min(BUCKET_SIZE, b.tokens + (now - b.t) / BUCKET_REFILL)
	b.t = now
	if b.tokens + 1e-6 < 1 then -- (tolerance: a sender exactly on time must not lose to rounding)
		stats.rate = stats.rate + 1
		LogDrop(sender, m, "rate", now)
		return false, "rate"
	end
	b.tokens = b.tokens - 1
	local have, verified = Channels.VerifiedLevel(sender, m.guild)
	if have < level then
		local reason = have == 0 and "forged" or (verified and "rank" or "unverified")
		stats[reason] = stats[reason] + 1
		LogDrop(sender, m, reason, now)
		return false, reason
	end
	-- A muted channel only goes to history, so it takes nothing from the flood guard. A line
	-- the guard keeps off the chat frame still goes to the history (the Realm tab's chats stay
	-- whole for everyone).
	if not Muted()[m.tier] and Flooded(m.tier, sender, now) then
		stats.flood = stats.flood + 1
		AddHistory(m.tier, { sender = sender, guild = m.guild, class = m.class, text = m.text })
		ns.Fire("CHAT_CHANGED", m.tier)
		return false, "flood"
	end
	return Accept(m.tier, sender, m.guild, m.class, m.text, false)
end

-- Our name however the server writes it: lower case, our realm left out (a namesake on a
-- connected realm is another player), a hyphen between first name and surname read as the
-- space it stands for ("Faladori Elskylance" stays another).
local function Letters(name)
	name = tostring(name or "")
	local base, realm = name:match("^(.+)%-([^%-]+)$")
	if realm and (realm == ns.realm or realm == ns.CurrentRealm()) then name = base end
	name = name:lower():gsub("'", ""):gsub("[%s%-]+", " ")
	return (name:match("^%s*(.-)%s*$"))
end
function Channels.IsMe(sender)
	if not ns.me or not sender then return false end
	return sender == ns.me or Letters(ns.Normal(sender)) == Letters(ns.me)
end

-- Players' text must come through the logged API (the server keeps it, so abuse can be
-- reported): a line sent with the plain one is dropped, where the client has both.
ns.Comm.Handle("M1", function(dist, sender, text)
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm.DeliveredLogged and not ns.Comm.DeliveredLogged() then
		stats.unlogged = (stats.unlogged or 0) + 1
		return
	end
	Channels.Receive(dist, sender, text)
end)

---------------------------------------------------------------------------
-- Mute, housekeeping, commands
---------------------------------------------------------------------------

local WORDS = {
	all = "A", a = "A", olympus = "A", todos = "A",
	captains = "C", captain = "C", c = "C", capitaes = "C", ["capitães"] = "C",
	lords = "L", lord = "L", l = "L", lordes = "L",
}
function Channels.TierForWord(w)
	return WORDS[(tostring(w or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))]
end

-- A muted channel stays out of chat but keeps its history. Account-wide.
function Channels.ToggleMute(word)
	local tier = Channels.TierForWord(word)
	if not tier then
		ns.Print(L.CHAN_MUTE_USAGE)
		return
	end
	local muted = Muted()
	if muted[tier] then
		muted[tier] = nil
		ns.Print(L.CHAN_UNMUTED:format(Label(tier)))
	else
		muted[tier] = true
		ns.Print(L.CHAN_MUTED:format(Label(tier), TIERS[tier].word))
	end
end

function Channels.Prune(now)
	now = now or GetTime()
	local n = 0
	for k, t in pairs(seen) do
		if now - t > DEDUPE_WINDOW then seen[k] = nil else n = n + 1 end
	end
	if n > 1000 then wipe(seen) end
	for k, t in pairs(mine) do
		if now - t > DEDUPE_WINDOW then mine[k] = nil end
	end
	for k, b in pairs(buckets) do
		if now - b.t > 60 then buckets[k] = nil end
	end
	for k, t in pairs(lastLog) do
		if now - t > LOG_GAP then lastLog[k] = nil end
	end
end

function Channels.Stats()
	local out = {}
	for k, v in pairs(stats) do out[k] = v end
	local muted = {}
	for _, tier in ipairs(Channels.ORDER) do
		if Muted()[tier] then muted[#muted + 1] = tier end
	end
	out.muted = muted
	return out
end

ns.On("INIT", function()
	local chat = ns.rdb.chat
	if chat == nil then return end
	if type(chat) ~= "table" then
		ns.rdb.chat = nil
		return
	end
	for tier, list in pairs(chat) do
		if not TIERS[tier] or type(list) ~= "table" then
			chat[tier] = nil
		else
			while #list > HISTORY do table.remove(list, 1) end
		end
	end
end)

ns.On("LOGIN", function()
	ns.Every(60, "chat housekeeping", Channels.Prune)
end)

SLASH_OLYMPUSALL1, SLASH_OLYMPUSCAPTAINS1, SLASH_OLYMPUSLORDS1 = "/ol", "/olc", "/oll"
SlashCmdList.OLYMPUSALL = function(msg) ns.SafeCall("slash /ol", Channels.Send, "A", msg) end
SlashCmdList.OLYMPUSCAPTAINS = function(msg) ns.SafeCall("slash /olc", Channels.Send, "C", msg) end
SlashCmdList.OLYMPUSLORDS = function(msg) ns.SafeCall("slash /oll", Channels.Send, "L", msg) end
