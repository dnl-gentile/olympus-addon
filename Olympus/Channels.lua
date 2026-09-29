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
local NOTICE_GAP = 60            -- at most one flood guard notice a minute...
local NOTICE_WAIT = 10           -- ...a few seconds after the first line held, to count the burst

-- Gold, teal and royal purple: none of them is a colour Blizzard's chat already uses.
local TIERS = {
	A = { level = 1, label = "CHAN_ALL",      slash = "/ol",  word = "olympus",  deny = "MEMBERS_ONLY",       color = { 0.90, 0.77, 0.36 } },
	C = { level = 2, label = "CHAN_CAPTAINS", slash = "/olc", word = "captains", deny = "CHAN_ONLY_CAPTAINS", color = { 0.35, 0.85, 0.85 } },
	L = { level = 3, label = "CHAN_LORDS",    slash = "/oll", word = "lords",    deny = "CHAN_ONLY_LORDS",    color = { 0.75, 0.50, 1.00 } },
}
Channels.TIERS, Channels.ORDER = TIERS, { "A", "C", "L" }
Channels.HISTORY = HISTORY

local stats = { sent = 0, shown = 0, hidden = 0, bad = 0, dup = 0, rate = 0, flood = 0, forged = 0, unverified = 0, rank = 0, ignored = 0 }
local seen = {}      -- "sender#id#text" -> time: every part is shown once
local buckets = {}   -- sender -> { tokens, t }
local recent = {}    -- tier -> { { t, sender } } of the lines shown in the last minute
local lastLog = {}   -- sender -> time of the last drop we logged
local lastSend = -math.huge
local mine = {}      -- "id#text" -> time: our own lines, shown when sent (their echo is not shown again)
local nextId = math.random(0, 9999)
local held = {}      -- tier -> lines the flood guard kept off the chat since its last notice
local heldSince      -- when the first of them was held
local lastNotice = -math.huge
local noticeTimer = false
local gone = {}      -- chosen window name (lower case) -> true once we said it is gone

local function Label(tier)
	return L[TIERS[tier].label]
end

-- 1.1 (Fern's #11): the Olympus chats are the player's choice, on the first-open page
-- (Consent.lua) or /oly chat on|off. Off until they answer (ns.db.addonChat is nil until then,
-- account-wide), and off after a No: this client neither sends nor shows [Olympus], [Captains]
-- or [Lords]. A line that arrives is dropped before anything keeps it (no history, nothing to
-- the Realm tab or a companion through the bridge); the client still sits in the channel, for
-- the census.
function Channels.ChatOn() return ns.db ~= nil and ns.db.addonChat == true end
function Channels.ChatState()
	local v = ns.db and ns.db.addonChat
	return v == true and "on" or (v == false and "off" or "not chosen (off)")
end
function Channels.SetChatOn(on)
	ns.db.addonChat = on and true or false
	ns.Print(on and L.CHAT_ON_MSG or L.CHAT_OFF_MSG)
	ns.Fire("CHAT_CHANGED")
end
local offHinted = false -- a line dropped while unanswered: said once a session
function Channels.ResetOffHint() offHinted = false end -- tests

local function Muted()
	ns.db.chatMute = ns.db.chatMute or {}
	return ns.db.chatMute
end

-- The channels whose warning the player accepted before their first line there. Account-wide.
local function Warned()
	ns.db.chatWarned = ns.db.chatWarned or {}
	return ns.db.chatWarned
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
-- Verified, the rank index it was read from too (0: the guild master; the King's Crown: 0).
function Channels.VerifiedLevel(sender, guild)
	local who = ns.FullName(sender)
	local rank = ns.Roster.RankOf(who)
	local mine = GetGuildInfo("player")
	if mine and guild:lower() == mine:lower() then
		if guild ~= mine then return 0, false end -- our name spelled another way (names ignore case)
		if rank then return Channels.LevelOf(guild, rank), true, rank end
		if ns.Roster.byName == nil then return 1, false end -- roster not read yet
		return 0, false -- not in our roster: not one of us
	end
	if rank then return 0, false end -- a guildmate of ours speaking for another guild
	-- The King by his pinned name (the server stamps it), never by a census vote, his Steward (the
	-- signed titles list, King.IsStewardName) and the Hands the King's list or a Steward's own
	-- names (King.IsHandName): of his Crown for his guild here, outside it (1.0.0).
	if ns.IsKingGuild(guild) and (ns.IsKingCharacter(who)
		or (ns.King ~= nil and (ns.King.IsStewardName(who) or ns.King.IsHandName(who)))) then
		return Channels.LevelOf(guild, 0), true, 0
	end
	if not ns.Data.ClaimGuild(who, guild) then return 0, false end
	local known = ns.Data.KnownRank(who, guild)
	if known == nil then return 1, false end
	return Channels.LevelOf(guild, known), true, known
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
	-- The High Council (the moderators, Core.lua): the fixed mark, their own icon after it if
	-- they picked one (0.9.9), and their colour. For everyone, as in 0.9.8, but the King while
	-- the councillors' names are hidden on his screen (his stream, ns.CouncilMasked): a plain line.
	if ns.IsHighCouncillor(sender) and not ns.CouncilMasked() then
		name = ns.CouncilMark(sender) .. "|c" .. ns.HIGH_COUNCIL_COLOR .. ns.DisplayName(sender) .. "|r"
	end
	-- The Treasurer: the gold coin he carries in tooltips and the census (0.9.9).
	if ns.IsTreasurer(sender, guild) then name = ns.COIN:gsub(" $", "") .. name end
	return "[" .. Label(tier) .. "] |Hplayer:" .. (ns.TellName(sender) or "?") .. "|h[" .. name .. "]|h <"
		.. tostring(guild or "?"):gsub("|", "||") .. ">: " .. Codec.SanitizeChat(text)
end

---------------------------------------------------------------------------
-- The chat window each channel shows in (/oly chatwindow). Output only: Olympus adds its lines
-- to the window the player chose as it adds them to the main one, and never touches a window's
-- edit box, tabs or dock. (Replacing the chat box's scripts, or opening a window from addon
-- code, runs Blizzard's chat code tainted: /cast, /use or /target typed there get blocked.)
-- The player makes the tab in the game and picks it here. The choice is the window's name, per
-- character like the game's own chat windows, looked up each time a line is shown: a window
-- closed or renamed sends its lines back to the main window, with one notice. (Checking the
-- window at print time and falling back to the main one comes from RoyLeviGit's pull request
-- #20, "native chat tabs".)
---------------------------------------------------------------------------

local function MaxWindows()
	local c = Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatWindows
	return tonumber(NUM_CHAT_WINDOWS) or tonumber(c) or 10
end

-- Chat window i: its frame, its name, whether it is open (shown, or docked behind another tab:
-- the game counts a docked tab not selected as not shown) and whether it is the combat log,
-- which clears and refills itself (a line of ours there would vanish).
local function WindowAt(i)
	local f = _G["ChatFrame" .. i]
	if type(f) ~= "table" or type(f.AddMessage) ~= "function" then return nil end
	local info = GetChatWindowInfo or FCF_GetChatWindowInfo
	local name, shown
	if type(info) == "function" then
		local ok, n, _, _, _, _, _, s = pcall(info, i)
		if ok then name, shown = n, s end
	end
	if type(name) ~= "string" or name == "" then name = type(f.name) == "string" and f.name ~= "" and f.name or nil end
	local combat = false
	if type(IsCombatLog) == "function" then
		local ok, res = pcall(IsCombatLog, f)
		combat = ok and res and true or false
	end
	return f, name, (shown or f.isDocked) and true or false, combat
end

-- The open chat window called `name` (in any case): its frame, number and name as the game has it.
function Channels.FindWindow(name)
	if type(name) ~= "string" or name == "" then return nil end
	local want = name:lower()
	for i = 1, MaxWindows() do
		local f, wname, open, combat = WindowAt(i)
		if f and open and not combat and wname and wname:lower() == want then return f, i, wname end
	end
	return nil
end

local function Quoted(name)
	return '"' .. tostring(name):gsub("|", "||") .. '"'
end

-- This character's choices: tier -> window name.
local function Chosen()
	local all = ns.db and ns.db.chatWindows
	local list = type(all) == "table" and ns.me and all[ns.me]
	return type(list) == "table" and list or nil
end

-- The frame a channel's lines go to: its chosen window while it is open, else the main one.
function Channels.Frame(tier)
	local chosen = Chosen()
	local name = chosen and chosen[tier]
	if type(name) == "string" then
		local f = Channels.FindWindow(name)
		local key = name:lower()
		if f then
			gone[key] = nil
			return f
		end
		if not gone[key] then
			gone[key] = true
			ns.Print(L.CHATWIN_GONE:format(Quoted(name)))
		end
	end
	return DEFAULT_CHAT_FRAME
end

-- A line of ours ("Olympus: ...") in frame f, what ns.Print writes in the main window.
local function Say(f, msg)
	if not f or f == DEFAULT_CHAT_FRAME then return ns.Print(msg) end
	f:AddMessage("|c" .. ns.COLOR .. "Olympus:|r " .. tostring(msg))
end

-- "[Olympus] main window, [Captains] "Olympus"" for /oly chatwindow and /oly status.
function Channels.WindowStatus()
	local chosen = Chosen() or {}
	local parts = {}
	for _, tier in ipairs(Channels.ORDER) do
		local name = chosen[tier]
		local where = L.CHATWIN_MAIN_NAME
		if type(name) == "string" then
			where = Quoted(name) .. (Channels.FindWindow(name) and "" or " " .. L.CHATWIN_GONE_TAG)
		end
		parts[#parts + 1] = "[" .. Label(tier) .. "] " .. where
	end
	return table.concat(parts, ", ")
end

-- A window by number or by name: frame, name, or nil and why ("combat").
local function PickWindow(word)
	local n = tonumber(word)
	if n and n == math.floor(n) and n >= 1 and n <= MaxWindows() then
		local f, name, open, combat = WindowAt(n)
		if f and open and name then
			if combat then return nil, nil, "combat" end
			return f, name
		end
		return nil
	end
	local f, _, name = Channels.FindWindow(word)
	if f then return f, name end
	-- (The combat log is left out of FindWindow: say why rather than "not found".)
	for k = 1, MaxWindows() do
		local cf, cname, open, combat = WindowAt(k)
		if cf and open and combat and cname and cname:lower() == tostring(word):lower() then return nil, nil, "combat" end
	end
	return nil
end

local MAIN_WORDS = { main = true, default = true, principal = true }
local ALL_WORDS = { all = true, todos = true }

-- /oly chatwindow <number | name | main> [olympus | captains | lords]
function Channels.ChooseWindow(input)
	input = tostring(input or ""):match("^%s*(.-)%s*$")
	if input == "" then
		ns.Print(L.CHATWIN_NOW:format(Channels.WindowStatus()))
		ns.Print(L.CHATWIN_USAGE)
		return false
	end
	if not ns.me then return false end
	-- The whole text first (a window may be called "Olympus Lords"), then a channel at its end.
	local target, tiers = input, Channels.ORDER
	if not MAIN_WORDS[input:lower()] and not PickWindow(input) then
		local head, last = input:match("^(.-)%s+(%S+)$")
		if head and head ~= "" then
			if ALL_WORDS[last:lower()] then
				target = head
			elseif Channels.TierForWord(last) then
				target, tiers = head, { Channels.TierForWord(last) }
			end
		end
	end
	local f, name, why
	if not MAIN_WORDS[target:lower()] then
		f, name, why = PickWindow(target)
		if not f then
			if why == "combat" then
				ns.Print(L.CHATWIN_COMBATLOG)
			else
				local open = {}
				for i = 1, MaxWindows() do
					local wf, wname, isOpen, combat = WindowAt(i)
					if wf and isOpen and not combat and wname then open[#open + 1] = i .. " " .. Quoted(wname) end
				end
				local menu = type(NEW_CHAT_WINDOW) == "string" and NEW_CHAT_WINDOW ~= "" and NEW_CHAT_WINDOW or L.CHATWIN_NEW
				ns.Print(L.CHATWIN_NOT_FOUND:format(Quoted(target), #open > 0 and table.concat(open, ", ") or "-", menu))
			end
			return false
		end
		if f == DEFAULT_CHAT_FRAME then name = nil end -- the main window: nothing to remember
	end
	ns.db.chatWindows = type(ns.db.chatWindows) == "table" and ns.db.chatWindows or {}
	local list = type(ns.db.chatWindows[ns.me]) == "table" and ns.db.chatWindows[ns.me] or {}
	ns.db.chatWindows[ns.me] = list
	local labels = {}
	for _, tier in ipairs(tiers) do
		list[tier] = name
		labels[#labels + 1] = "[" .. Label(tier) .. "]"
	end
	if next(list) == nil then ns.db.chatWindows[ns.me] = nil end
	if next(ns.db.chatWindows) == nil then ns.db.chatWindows = nil end
	wipe(gone)
	if not name then
		ns.Print(L.CHATWIN_MAIN:format(table.concat(labels, ", ")))
		return true
	end
	local msg = L.CHATWIN_SET:format(table.concat(labels, ", "), Quoted(name))
	ns.Print(msg)
	Say(f, msg) -- and in that window, to show where they land
	return true
end

-- A plain AddMessage on the channel's chat window (what print does on the main one): nothing
-- of Blizzard's is replaced or hooked.
local function Show(tier, sender, guild, class, text)
	local f = Channels.Frame(tier)
	if not f then return end
	local c = TIERS[tier].color
	f:AddMessage(Channels.FormatLine(tier, sender, guild, class, text), c[1], c[2], c[3])
end

local function AddHistory(tier, e)
	local list = Store(tier)
	list[#list + 1] = { t = ns.Now(), sender = e.sender, guild = e.guild, class = e.class, text = e.text, mine = e.mine }
	while #list > HISTORY do table.remove(list, 1) end
end

-- Every line kept goes through here, whether it is then shown, muted or held back by the flood
-- guard: into the history the Realm tab shows (CHAT_CHANGED) and, from someone else, already
-- checked and sanitized, to a companion reading along (CHAT_LINE, for
-- OlympusBridge.RegisterChatObserver). The mute and the flood guard only decide what this chat
-- frame shows.
local function Keep(tier, sender, guild, class, text, mine)
	AddHistory(tier, { sender = sender, guild = guild, class = class, text = text, mine = mine or nil })
	ns.Fire("CHAT_CHANGED", tier)
	if not mine then ns.Fire("CHAT_LINE", tier, sender, text) end
end

local function Accept(tier, sender, guild, class, text, mine)
	Keep(tier, sender, guild, class, text, mine)
	if Muted()[tier] then return false, "muted" end
	Show(tier, sender, guild, class, text)
	stats.shown = stats.shown + 1
	return true, "ok"
end

-- The lines of a channel we may read (for a future Channels view, with CHAT_CHANGED). None
-- while the chats are off on this client (1.1): lines kept before that don't show either.
function Channels.History(tier)
	if not Channels.CanUse(tier) or not Channels.ChatOn() then return {} end
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
	-- The chats off on this client (1.1): nothing leaves. Never answered: the page asks.
	if not Channels.ChatOn() then
		if ns.db.addonChat == nil then
			ns.Print(L.CHAT_OFF_UNANSWERED)
			if ns.Consent and ns.Consent.Ask then ns.Consent.Ask("chat") end
		else
			ns.Print(L.CHAT_OFF)
		end
		return false, "off"
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
	-- The first line in each channel waits for the player's OK: nothing is private there, and
	-- they are told so before anything leaves (Channels.Confirm sends it).
	if not Warned()[tier] then
		ns.ShowDialog("OLYMPUS_CHAT_PRIVACY", Label(tier), ns.Comm.Audience(), { tier = tier, text = text })
		return false, "confirm"
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

-- The warning's answer, with the line it held (with the gamepad UI too: it rides in the
-- window's data). Send: that channel counts as warned and the line goes through Channels.Send
-- again, every check with it. Cancel, Escape or another window taking its place: not sent.
function Channels.Confirm(data, send)
	if type(data) ~= "table" or not TIERS[data.tier] or data.answered then return end
	data.answered = true
	if not send then
		ns.Print(L.CHAN_WARN_NOT_SENT)
		return
	end
	Warned()[data.tier] = true
	return Channels.Send(data.tier, data.text)
end

StaticPopupDialogs["OLYMPUS_CHAT_PRIVACY"] = {
	text = L.CHAN_WARN_ASK,
	button1 = SEND_LABEL or "Send",
	button2 = CANCEL or "Cancel",
	OnAccept = function(self, data) ns.SafeCall("chat warning", Channels.Confirm, data or (self and self.data), true) end,
	OnCancel = function(self, data) ns.SafeCall("chat warning", Channels.Confirm, data or (self and self.data), false) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

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

-- What the flood guard kept off the chat is said, never silent: at most one line a minute,
-- "[Olympus] 12, [Captains] 3", where most of those lines would have shown, telling where they
-- are and how many lines the history keeps. Called on each line held, by a timer once the
-- notice is due, and by the housekeeping. Returns true when it printed.
function Channels.FloodNotice(now)
	now = now or GetTime()
	if not heldSince then return false end
	local due = math.max(heldSince + NOTICE_WAIT, lastNotice + NOTICE_GAP)
	if now < due then
		if not noticeTimer then
			noticeTimer = true
			ns.After(due - now + 0.1, "flood notice", function()
				Channels.FloodNotice()
				noticeTimer = false
			end)
		end
		return false
	end
	local parts, most, where = {}, 0, nil
	for _, tier in ipairs(Channels.ORDER) do
		local n = held[tier]
		if n then
			parts[#parts + 1] = "[" .. Label(tier) .. "] " .. n
			if n > most then most, where = n, tier end
		end
	end
	wipe(held)
	heldSince, lastNotice = nil, now
	if not where then return false end
	Say(Channels.Frame(where), L.CHAN_FLOOD_NOTICE:format(table.concat(parts, ", "), HISTORY))
	return true
end

local function Held(tier, now)
	held[tier] = (held[tier] or 0) + 1
	heldSince = heldSince or now
	Channels.FloodNotice(now)
end

-- Returns shown, reason.
function Channels.Receive(dist, sender, text, now)
	if dist ~= "CHANNEL" then return false, "dist" end
	-- The chats off on this client (1.1): dropped before anything reads or keeps the line.
	if not Channels.ChatOn() then
		stats.off = (stats.off or 0) + 1
		if ns.db and ns.db.addonChat == nil and not offHinted and ns.IsMember() then
			offHinted = true
			ns.Print(L.CHAT_OFF_UNANSWERED)
		end
		return false, "off"
	end
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
	-- 1.1 (#31): a line the player's block terms hide (Filter.lua) stays off the chat frame. It is
	-- kept, for the Realm tab's "N lines hidden" and its click to show them, and a companion reading
	-- the chats still gets it: the filter only decides what this player sees. Nothing else happens
	-- to its sender (no ignore, no block): their next line shows.
	local F = ns.Filter
	if F and not F.missing and F.Hides(m.text) then
		stats.filtered = (stats.filtered or 0) + 1
		Keep(m.tier, sender, m.guild, m.class, m.text, false)
		return false, "filtered"
	end
	-- A muted channel only goes to history, so it takes nothing from the flood guard. A line
	-- the guard keeps off the chat frame still goes to the history (the Realm tab's chats stay
	-- whole for everyone, and a companion hears it), and the player is told (Channels.FloodNotice).
	if not Muted()[m.tier] and Flooded(m.tier, sender, now) then
		stats.flood = stats.flood + 1
		Keep(m.tier, sender, m.guild, m.class, m.text, false)
		Held(m.tier, now)
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
-- The pinned line (1.1): one short line on top of the Olympus chats and the Realm, for every
-- member, lighter than a writ (no parchment, nothing to acknowledge, no popup, no sound): a raid
-- move or a gates change that has to stay on screen. Not a second decree system: one line, the
-- setter's own words, typed by a person.
-- Who pins: the King (his pinned name), his Stewards and Hands (for his guild, on their word, as
-- their decrees), and the Lords every client can check alike: the guild masters of the Olympus
-- guilds (VerifiedLevel, as a [Lords] line's rank: our roster for our own guild, the census for
-- the others). The officers of <Olympus> are Lords on its own members' clients alone
-- (ns.IsCrownRank), and a pin is one line for the whole army: they pin as his Hands, never as
-- Lords, so no client shows a line the others drop.
-- One line for the whole channel. A newer pin takes the place of one of its own rank or lower:
-- the King's newer pin always wins, a Steward's or a Hand's never replaces the King's, a Lord's
-- never replaces theirs. It ends PIN_TIME after it was set, or when its setter or a higher rank
-- takes it down (the King anyone's, his Stewards and Hands a Lord's; a Lord only his own). A
-- higher rank's takedown names the pin it takes down (its id), once a minute at most from each
-- sender, and every takedown says in chat who took the line down. The setter's client repeats it
-- every PIN_RESEND for late logins (a pin replaced there is no longer its to repeat), with how
-- long it has left and how long ago it was set: a repeat never makes a pin newer. Its words go
-- out with the logged API (the server keeps them, so abuse can be reported), plain text, PIN_MAX
-- bytes at most; a sender's new pin once a minute at most, and the Lords' together PIN_FLOOD a
-- minute on each client.
--   N1~<id>~<guild>~<seconds left>~<seconds since set>~<text>     a pin
--   N1~<id>~<guild>~0~0~        taken down (<id>: the pin's; <guild>: the sender's own)
-- Clients before 1.1 know no N1 and drop it unread.
---------------------------------------------------------------------------

Channels.PIN_MAX = 100         -- bytes of a pinned line
Channels.PIN_TIME = 2 * 3600   -- a pin ends this long after it was set
Channels.PIN_RESEND = 300      -- the setter's client repeats it this often
Channels.PIN_GAP = 60          -- a sender's new pin at most this often (taken a little sooner: queues)
Channels.PIN_FLOOD = 3         -- the Lords' new pins taken a minute, whoever sends them
Channels.PIN_KING, Channels.PIN_CROWN, Channels.PIN_LORD = 3, 2, 1

local pin            -- the pinned line: { id, sender, guild, text, rank, setAt, expires, mine, sentAt }
local lastPinSet = -math.huge
local lastPinDown = -math.huge -- when we last took down someone else's pin
local pinFrom = {}   -- [sender] = when a new pin of theirs was last taken
local downFrom = {}  -- [sender] = when their takedown of someone else's pin was last taken
local lordPins = {}  -- times of the Lords' new pins taken, the last minute

-- Plain text: no escape code, separator or control byte; spaces tidied; PIN_MAX bytes at most.
function Channels.CleanPin(text)
	text = tostring(text or ""):gsub("[|~%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return (ns.Cut(text, Channels.PIN_MAX):gsub("%s+$", ""))
end

-- The rank `sender` pins with for `guild`: PIN_KING, PIN_CROWN (a Steward or a Hand, for the
-- King's guild), PIN_LORD (its guild master), or nil for anyone else. Never the rank a message
-- claims. An officer of <Olympus> is no Lord here even on its own members' clients: the others'
-- drop his pin, and the army would not see one line.
function Channels.PinRank(sender, guild)
	if type(sender) ~= "string" or type(guild) ~= "string" or not ns.IsFederation(guild) then return nil end
	local K = ns.King
	if ns.IsKingGuild(guild) then
		if ns.IsKingCharacter(sender) then return Channels.PIN_KING end
		if K and ((K.IsStewardName and K.IsStewardName(sender)) or (K.IsHandName and K.IsHandName(sender))) then return Channels.PIN_CROWN end
	end
	local level, verified, rankIndex = Channels.VerifiedLevel(sender, guild)
	if verified and level >= TIERS.L.level and rankIndex == 0 then return Channels.PIN_LORD end
	return nil
end

-- Our own rank, as the others' clients will see it (Channels.PinRank), and the guild our pin
-- names: a Steward or a Hand pins for the King's guild; a guild master by our own rank (the
-- server's), never the officers of <Olympus> (Lords on its own members' clients alone).
local function MyPin()
	local K = ns.King
	if K and K.IsKing and K.IsKing() and ns.IsKingCharacter(ns.me) then return Channels.PIN_KING, GetGuildInfo("player") end
	if K and ((K.IsSteward and K.IsSteward()) or (K.IsHand and K.IsHand())) then return Channels.PIN_CROWN, ns.KingGuildName() end
	if ns.IsMember() and ns.Roster.MyRank() == 0 and Channels.MyLevel() >= TIERS.L.level then return Channels.PIN_LORD, GetGuildInfo("player") end
	return nil
end
function Channels.CanPin() return MyPin() ~= nil end

local function PinChanged()
	ns.Fire("PIN_CHANGED")
	if ns.UI and ns.UI.RefreshSoon then ns.UI.RefreshSoon() end
end

-- The pinned line while it lasts, else nil.
function Channels.Pin(now)
	now = now or ns.Now()
	if pin and now >= pin.expires then
		pin = nil
		PinChanged()
	end
	return pin
end

local function SendPin(p, now, down)
	local msg
	if down then
		msg = ("N1~%d~%s~0~0~"):format(p.id, p.guild)
	else
		msg = ("N1~%d~%s~%d~%d~%s"):format(p.id, p.guild, math.max(1, math.floor(p.expires - now)),
			math.max(0, math.floor(now - p.setAt)), p.text)
	end
	p.sentAt = now
	-- (One waiting at most: a newer one takes its place in the queue. Logged: its words.)
	ns.Comm.Send("CHANNEL", msg, "pin", nil, true)
end

-- /oly pin <text>, or the chat page's "Pin a line": up for PIN_TIME, for the whole channel.
function Channels.SetPin(text, now)
	now = now or ns.Now()
	local rank, guild = MyPin()
	if not rank then
		ns.Print(L.PIN_ONLY)
		return false, "rank"
	end
	text = Channels.CleanPin(text)
	if #text < 3 then
		ns.Print(L.PIN_USAGE)
		return false, "empty"
	end
	if Locked() then
		ns.Print(L.CHAN_LOCKDOWN)
		return false, "lockdown"
	end
	if not ns.Comm.ChannelReady() then
		ns.Print(L.CHAN_NOT_READY)
		return false, "ready"
	end
	if now - lastPinSet < Channels.PIN_GAP then
		ns.Print(L.PIN_WAIT:format(math.ceil(Channels.PIN_GAP - (now - lastPinSet))))
		return false, "fast"
	end
	local current = Channels.Pin(now)
	if current and not current.mine and current.rank > rank then
		ns.Print(L.PIN_OUTRANKED:format(ns.DisplayName(current.sender) or "?"))
		return false, "outranked"
	end
	lastPinSet = now
	pin = { id = math.random(1, 99999), sender = ns.me, guild = guild, text = text, rank = rank, setAt = now,
		expires = now + Channels.PIN_TIME, mine = true }
	SendPin(pin, now)
	ns.Print(L.PIN_DONE:format(text))
	PinChanged()
	return true, "ok"
end

-- Ours: set here, or one of ours this client heard (our name, as the server stamped it).
local function Ours(p) return p.mine or Channels.IsMe(p.sender) end

-- Can we take the pinned line down: ours, or of a lower rank than ours.
function Channels.CanTakeDown(now)
	local p = Channels.Pin(now)
	if not p then return false end
	if Ours(p) then return true end
	local rank = MyPin()
	return rank ~= nil and rank > p.rank
end

-- /oly pin off, or the pinned line's click: taken down for the whole channel. Someone else's:
-- named by its id, once a minute at most (as the others' clients take it, HandlePin).
function Channels.TakeDownPin(now)
	now = now or ns.Now()
	local p = Channels.Pin(now)
	if not p then
		ns.Print(L.PIN_NONE)
		return false, "none"
	end
	if not Channels.CanTakeDown(now) then
		ns.Print(L.PIN_NOT_YOURS)
		return false, "rank"
	end
	local own = Ours(p)
	if not own then
		if now - lastPinDown < Channels.PIN_GAP then
			ns.Print(L.PIN_DOWN_WAIT:format(math.ceil(Channels.PIN_GAP - (now - lastPinDown))))
			return false, "fast"
		end
		lastPinDown = now
	end
	local _, guild = MyPin()
	SendPin({ id = p.id, guild = own and p.guild or guild }, now, true)
	pin = nil
	ns.Print(L.PIN_TAKEN_DOWN)
	PinChanged()
	return true, "ok"
end

-- Every minute: our own pin again for late logins, every PIN_RESEND while it lasts.
function Channels.RepeatPin(now)
	now = now or ns.Now()
	local p = Channels.Pin(now)
	if p and p.mine and now - (p.sentAt or -math.huge) >= Channels.PIN_RESEND then SendPin(p, now) end
end

-- Returns taken, reason.
function Channels.HandlePin(dist, sender, text, now)
	if dist ~= "CHANNEL" then return false, "dist" end
	now = now or ns.Now()
	sender = ns.FullName(sender)
	local id, guild, left, age, body = tostring(text):match("^N1~(%d+)~([^~]*)~(%d+)~(%d+)~(.*)$")
	id, left, age = tonumber(id), tonumber(left), tonumber(age)
	-- (A guild's name: 24 letters at most, not bytes, as every other message reads it: Codec.LongGuild.)
	if not id or not guild or guild == "" or Codec.LongGuild(guild) or guild:find("%c") then return false, "bad" end
	if Ignored(sender) then return false, "ignored" end
	-- Its words come through the logged API, as a chat line's (dropped otherwise, where this
	-- client has both).
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm.DeliveredLogged and not ns.Comm.DeliveredLogged() then
		return false, "unlogged"
	end
	local rank = Channels.PinRank(sender, guild)
	if not rank then
		ns.Log("pin from %s <%s> ignored: not the King, his Stewards or Hands, or a Lord we can verify", sender, guild)
		return false, "rank"
	end
	local current = Channels.Pin(now)
	body = Channels.CleanPin(body)
	if body == "" or left == 0 then
		-- Its setter's takes his line down (whichever of his we show); a higher rank's, the pin it
		-- names, once a minute at most from each. A Lord takes down no other Lord's pin.
		if not current then return false, "nothing" end
		local own = current.sender == sender
		if not own then
			if current.id ~= id or rank <= current.rank then return false, "nothing" end
			if now - (downFrom[sender] or -math.huge) < Channels.PIN_GAP * 0.75 then return false, "fast" end
			downFrom[sender] = now
		end
		pin = nil
		local who = ns.DisplayName(sender) or "?"
		Say(DEFAULT_CHAT_FRAME, "|cffffd200" .. (own and L.PIN_DOWN_OWN:format(who, Codec.Plain(guild))
			or L.PIN_DOWN_BY:format(who, Codec.Plain(guild), ns.DisplayName(current.sender) or "?")) .. "|r")
		ns.Log("pin of %s <%s> taken down by %s <%s> (rank %d)", current.sender, current.guild, sender, guild, rank)
		PinChanged()
		return true, "down"
	end
	left, age = math.min(left, Channels.PIN_TIME), math.min(age, Channels.PIN_TIME)
	-- The pin we hold, said again: only its end, never later than it was.
	if current and current.sender == sender and current.id == id then
		current.expires = math.min(current.expires, now + left)
		return true, "repeat"
	end
	local setAt = now - age
	-- A higher rank's stays; of the same rank, the one set last.
	if current and (current.rank > rank or (current.rank == rank and current.setAt > setAt)) then return false, "older" end
	if now - (pinFrom[sender] or -math.huge) < Channels.PIN_GAP * 0.75 then return false, "fast" end
	if rank == Channels.PIN_LORD then
		for i = #lordPins, 1, -1 do if now - lordPins[i] > 60 then table.remove(lordPins, i) end end
		if #lordPins >= Channels.PIN_FLOOD then return false, "flood" end
		lordPins[#lordPins + 1] = now
	end
	pinFrom[sender] = now
	pin = { id = id, sender = sender, guild = guild, text = body, rank = rank, setAt = setAt, expires = now + left }
	Say(DEFAULT_CHAT_FRAME, "|cffffd200" .. L.PIN_NEW:format(ns.DisplayName(sender) or "?", Codec.Plain(guild), body) .. "|r")
	ns.Log("pin from %s <%s> (rank %d)", sender, guild, rank)
	PinChanged()
	return true, "ok"
end
ns.Comm.Handle("N1", function(dist, sender, text) Channels.HandlePin(dist, sender, text) end)

-- For /oly status.
function Channels.PinStatus(now)
	local p = Channels.Pin(now)
	if not p then return "none" end
	local ranks = { [3] = "the King", [2] = "Steward or Hand", [1] = "Lord" }
	return ("by %s <%s> (%s)%s, ends in %dm"):format(ns.DisplayName(p.sender) or "?", Codec.Plain(p.guild), ranks[p.rank] or "?",
		p.mine and ", ours" or "", math.ceil((p.expires - (now or ns.Now())) / 60))
end

function Channels.ResetPin() pin, lastPinSet, lastPinDown = nil, -math.huge, -math.huge; wipe(pinFrom); wipe(downFrom); wipe(lordPins) end -- tests

StaticPopupDialogs["OLYMPUS_PIN"] = {
	text = L.PIN_ASK,
	button1 = L.PIN_BUTTON,
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 260,
	maxLetters = Channels.PIN_MAX,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then
			eb:SetText("")
			eb:SetFocus()
		end
	end,
	OnAccept = function(self)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("pin", Channels.SetPin, eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		ns.SafeCall("pin", Channels.SetPin, self:GetText())
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_PIN_DOWN"] = {
	text = L.PIN_DOWN_ASK,
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function() ns.SafeCall("pin down", Channels.TakeDownPin) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- /oly pin <text> | off | (nothing: what is pinned, and how).
function Channels.PinCommand(rest)
	rest = tostring(rest or ""):match("^%s*(.-)%s*$")
	local word = rest:lower()
	if word == "off" or word == "down" then return Channels.TakeDownPin() end
	if rest == "" then
		local p = Channels.Pin()
		if p then
			ns.Print(L.PIN_NOW:format(ns.DisplayName(p.sender) or "?", Codec.Plain(p.guild), math.ceil((p.expires - ns.Now()) / 60), p.text))
		else
			ns.Print(L.PIN_NONE)
		end
		ns.Print(L.PIN_USAGE)
		return false
	end
	return Channels.SetPin(rest)
end

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
	Channels.FloodNotice(now) -- (in case its timer never came)
end

function Channels.Stats()
	local out = {}
	for k, v in pairs(stats) do out[k] = v end
	local muted, warned = {}, {}
	for _, tier in ipairs(Channels.ORDER) do
		if Muted()[tier] then muted[#muted + 1] = tier end
		if Warned()[tier] then warned[#warned + 1] = tier end
	end
	out.muted, out.warned = muted, warned
	return out
end

ns.On("INIT", function()
	-- (0.9.1: the warning comes before the first line in each channel, Channels.Confirm.)
	ns.db.chatNoticeShown = nil
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
	-- Our pinned line again for late logins (1.1), every PIN_RESEND while it lasts.
	ns.Every(60, "pin repeat", function() Channels.RepeatPin() end)
end)

SLASH_OLYMPUSALL1, SLASH_OLYMPUSCAPTAINS1, SLASH_OLYMPUSLORDS1 = "/ol", "/olc", "/oll"
SlashCmdList.OLYMPUSALL = function(msg) ns.SafeCall("slash /ol", Channels.Send, "A", msg) end
SlashCmdList.OLYMPUSCAPTAINS = function(msg) ns.SafeCall("slash /olc", Channels.Send, "C", msg) end
SlashCmdList.OLYMPUSLORDS = function(msg) ns.SafeCall("slash /oll", Channels.Send, "L", msg) end
