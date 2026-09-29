local ADDON, ns = ...
local L = ns.L

-- The guild bank of <Olympus>, as its Treasury tab shows it: whoever of that guild opens the
-- bank with the addon on (the Treasurer, the King, an officer who may see it) takes a
-- snapshot of what it holds, tab by tab (item and count, the bank's gold), kept in the saved
-- variables with when it was taken. A keeper of the treasury's client (the Treasurer, the
-- King, a character the King named: Treasury.lua) sends its snapshot on the channel (T9, in
-- pieces), once he said yes to sharing, so the King and the army see the bank as a keeper
-- last saw it (the newest); anyone else's snapshot stays on their own screen. Nothing is ever
-- moved or touched in the bank.
--   T9~<guild>~<time>~<copper>~<tab name>;<id>x<count>,.<empty slots>,<id>x<count>...~<tab name>;...
-- (items in slot order; ".3" is three empty slots before the next one: the tab is drawn as
-- the bank shows it, slot by slot)
-- The bank's window opens on GUILDBANKFRAME_OPENED on older clients, and through the game's
-- interaction manager on the newer ones (WoW: Forever: PLAYER_INTERACTION_MANAGER_FRAME_SHOW
-- with the guild banker's type, 1.0): both are heard. Clients without a guild bank (Classic
-- Era) have none of the API: this file then only shows what a keeper sends, and the tab says
-- this client has no guild bank.

local Bank = {}
ns.Bank = Bank

Bank.SLOTS = 98            -- a guild bank tab (MAX_GUILDBANK_SLOTS_PER_TAB)
Bank.MAX_TABS = 8
Bank.MAX_ITEMS = 700       -- items sent or read, at most (6 full tabs are 588)
Bank.SHARE_GAP = 120       -- the Treasurer's client sends a changed bank this often at most
Bank.SHARE_REPEAT = 1800   -- and repeats it for late logins
Bank.REPORT_KEPT = 14 * 86400
Bank.SETTLE = 1.5          -- seconds after the last slot change before the bank is read
Bank.SETTLE_MAX = 6        -- ...but a bank that keeps changing is read this long after the first

local open = false
local queried = {}
local lastShare, lastSent = -math.huge, nil
local readPending = false
local firstChange, lastChange = 0, 0 -- the slot changes waiting to be read (GetTime)
local sharePending = false

-- (A tab's name ends at the first ";": only the message's separators and escapes go.)
local function Clean(s, n) return ns.Cut((tostring(s or ""):gsub("[~;|%c]", " ")), n) end
local function HasBank() return type(GetNumGuildBankTabs) == "function" and type(GetGuildBankItemInfo) == "function" end
Bank.HasAPI = HasBank

-- Our own snapshot (this character's guild's bank), and a keeper's as it reached us (while he
-- is one: a character the King took off the treasury no longer shows the bank).
function Bank.Own() return ns.rdb and ns.rdb.bank or nil end
function Bank.Report()
	local r = ns.rdb and ns.rdb.bankReport
	if type(r) ~= "table" then return nil end
	if ns.Now() - (tonumber(r.t) or 0) > Bank.REPORT_KEPT then
		ns.rdb.bankReport = nil
		return nil
	end
	if ns.Treasury and ns.Treasury.IsKeeperName and not ns.Treasury.IsKeeperName(r.by, r.guild) then return nil end
	return r
end
-- What the Treasury tab shows: the newest of the two, when ours is the King's guild's bank.
function Bank.Current()
	local own, report = Bank.Own(), Bank.Report()
	if own and not (own.guild and ns.IsKingGuild(own.guild)) then own = nil end
	if own and report then return (own.t or 0) >= (report.t or 0) and own or report end
	return own or report
end

-- The bank as the client holds it now, every tab we may see (once the server sent them).
function Bank.Read()
	if not HasBank() then return nil end
	local n = tonumber(GetNumGuildBankTabs()) or 0
	if n == 0 then return nil end
	local snap = { t = ns.Now(), guild = GetGuildInfo("player"), by = ns.me, money = GetGuildBankMoney and (tonumber(GetGuildBankMoney()) or 0) or 0, tabs = {} }
	local total = 0
	for tab = 1, math.min(n, Bank.MAX_TABS) do
		local name, icon, viewable = GetGuildBankTabInfo(tab)
		if viewable and queried[tab] then
			local items = {}
			for slot = 1, Bank.SLOTS do
				local texture, count = GetGuildBankItemInfo(tab, slot)
				count = tonumber(count) or 0
				if texture and count > 0 and total < Bank.MAX_ITEMS then
					local link = GetGuildBankItemLink and GetGuildBankItemLink(tab, slot)
					local id = link and tonumber(link:match("item:(%d+)"))
					if id then
						items[#items + 1] = { id = id, n = count, icon = texture, link = link, s = slot }
						total = total + 1
					end
				end
			end
			snap.tabs[#snap.tabs + 1] = { name = Clean(name ~= "" and name or tostring(tab), 30), icon = icon, items = items, i = tab }
		end
	end
	if #snap.tabs == 0 then return nil end
	return snap, total
end

-- Only a real keeper's client sends (never the author's view), with his yes (0.9.3).
local function CanSend() return ns.Treasury and ns.Treasury.CanSend and ns.Treasury.CanSend() end

-- What one message may carry (the channel's pieces), a little short of it.
local function Room() return (ns.Codec.CHUNK or 220) * (ns.Codec.MAX_CHUNKS or 30) - 40 end

-- kind: "T9" (a keeper's snapshot of the King's guild's bank) unless said; "TS" (1.1: a sister
-- guild's, for the King, his Stewards and his Hands alone) leaves the tabs' names out.
function Bank.Message(snap, kind)
	snap = snap or Bank.Own()
	if not snap then return nil end
	kind = kind or "T9"
	local parts = { kind, Clean(snap.guild, 40), tostring(math.floor(snap.t or ns.Now())), tostring(math.floor(snap.money or 0)) }
	local room, total = Room(), 0
	for _, tab in ipairs(snap.tabs) do
		local items, pos = {}, 1
		for k, it in ipairs(tab.items) do
			if total >= Bank.MAX_ITEMS then break end
			local slot = tonumber(it.s) or pos
			if slot > pos then items[#items + 1] = "." .. (slot - pos) end
			items[#items + 1] = ("%dx%d"):format(it.id, math.min(it.n, 99999))
			pos = slot + 1
			total = total + 1
		end
		parts[#parts + 1] = (kind == "TS" and "" or Clean(tab.name, 30)) .. ";" .. table.concat(items, ",")
	end
	local msg = table.concat(parts, "~")
	-- Past what the channel carries in one go: the last tabs are left out (it is rare: six
	-- full tabs fit).
	while #msg > room and #parts > 5 do
		parts[#parts] = nil
		msg = table.concat(parts, "~")
	end
	return msg
end

-- Our own snapshot of the King's guild's bank as a keeper's client whispers it (1.1), or nil.
function Bank.PrivateMessage()
	if not CanSend() then return nil end
	local snap = Bank.Own()
	if not snap or not (snap.guild and ns.IsKingGuild(snap.guild)) then return nil end
	return Bank.Message(snap)
end

-- 1.1: on the channel only while the King shows the army the book (the bank goes with it); by
-- whisper otherwise, to the King, his Stewards and the keepers heard online (Treasury.Private:
-- each gets a snapshot once, the next one when it changed).
function Bank.Share(force)
	if not CanSend() then return false end
	local snap = Bank.Own()
	if not snap or not (snap.guild and ns.IsKingGuild(snap.guild)) then return false end
	local now = ns.Now()
	local msg = Bank.Message(snap)
	if not msg then return false end
	if not ns.Treasury.PublicShows("book") then
		local n = 0
		for _, name in ipairs(ns.Treasury.Online()) do
			if ns.Treasury.Private(name, "T9", msg) then n = n + 1 end
		end
		return n > 0
	end
	if not force and msg == lastSent and now - lastShare < Bank.SHARE_REPEAT then return false end
	if not force and now - lastShare < Bank.SHARE_GAP then
		-- Changed within the gap: sent once it is over (the snapshot as it is then).
		if not sharePending then
			sharePending = true
			ns.After(Bank.SHARE_GAP - (now - lastShare) + 1, "bank share", function()
				sharePending = false
				Bank.Share()
			end)
		end
		return false
	end
	lastShare, lastSent = now, msg
	if #msg <= 250 then ns.Comm.Send("CHANNEL", msg, "bank") else ns.Comm.SendChunked(msg) end
	return true
end

-- A keeper's snapshot (from a keeper alone, by his name, speaking for the King's guild: no
-- census vote, which forged ones could turn against him). The newest one is kept: a keeper
-- repeating an older snapshot doesn't replace a newer one of another's.
-- A snapshot's tabs as a message writes them ("<name>;<id>x<n>,.<gap>,...~..."): each item where it
-- sits, MAX_TABS and MAX_ITEMS at most. noNames: "Tab n" for each (a sister guild's: TS).
local function ReadTabs(rest, noNames)
	local tabs, total = {}, 0
	for part in (rest .. "~"):gmatch("([^~]*)~") do
		local name, items = part:match("^([^;]*);(.*)$")
		if name and #tabs < Bank.MAX_TABS then
			local tab, pos = { name = noNames and ns.L.BANK_SISTER_TAB:format(#tabs + 1) or ns.Cut(name, 30), items = {} }, 1
			for entry in items:gmatch("[^,]+") do
				local gap = entry:match("^%.(%d+)$")
				local id, n = entry:match("^(%d+)x(%d+)$")
				if gap then
					pos = pos + tonumber(gap)
				elseif id and total < Bank.MAX_ITEMS and pos <= Bank.SLOTS then
					tab.items[#tab.items + 1] = { id = tonumber(id), n = math.min(tonumber(n), 99999), s = pos }
					pos = pos + 1
					total = total + 1
				end
			end
			tabs[#tabs + 1] = tab
		end
	end
	return tabs
end

function Bank.HandleReport(dist, sender, text)
	-- (1.1: by whisper too, put together by Treasury.HandlePrivate, to the King, a Steward or a keeper.)
	if dist ~= "CHANNEL" and not (dist == "WHISPER" and ns.Treasury.IsInsider()) then return end
	local guild, when, money, rest = text:match("^T9~([^~]*)~(%d+)~(%d+)~(.*)$")
	if not guild or not ns.IsKingGuild(guild) then return end
	if not (ns.Treasury and ns.Treasury.IsKeeperName and ns.Treasury.IsKeeperName(sender, guild)) then return end
	local now = ns.Now()
	local r = { t = math.min(tonumber(when) or now, now), guild = guild, by = ns.FullName(sender), money = math.min(tonumber(money) or 0, 2147483647), tabs = ReadTabs(rest) }
	if #r.tabs == 0 then return end
	local kept = ns.rdb.bankReport
	if type(kept) == "table" and (tonumber(kept.t) or 0) > r.t and not (ns.Treasury.SameChar and ns.Treasury.SameChar(kept.by, r.by)) then return end
	-- (1.1: the snapshot it replaces, of another visit, is what "gone since" compares with.)
	if type(kept) == "table" and tonumber(kept.t) ~= r.t and kept.guild == r.guild then ns.rdb.bankReportPrev = kept end
	ns.rdb.bankReport = r
	ns.Fire("TREASURY_CHANGED")
	ns.Fire("DATA_CHANGED")
end
ns.Comm.Handle("T9", function(...) Bank.HandleReport(...) end)
ns.Treasury.OnPrivate("T9", { from = function(s) return ns.Treasury.KeeperByName(s) end, to = function() return ns.Treasury.IsInsider() end,
	handle = function(...) Bank.HandleReport(...) end })

-- A tab asked for whose slots never arrived reads empty, just like a tab that is: an empty
-- read never replaces the items the last snapshot of that tab held (same guild, same tab),
-- unless the tab is the one on screen (the game loaded it, the player sees it empty), or that
-- tab was already kept once (empty twice in a row: it is). The kept tab is marked `kept`.
-- Each opening of the bank is a visit (0.9.2): a tab kept in this visit is kept again in it,
-- however many reads it takes; only a later visit that reads it empty again empties it (a tab
-- kept by 0.9.1, `kept == true`, counts as kept in an earlier visit).
local visit = 0
function Bank.Keep(snap, prev)
	if not snap or type(prev) ~= "table" or prev.guild ~= snap.guild or type(prev.tabs) ~= "table" then return snap end
	local shown = type(GetCurrentGuildBankTab) == "function" and tonumber((GetCurrentGuildBankTab())) or nil
	for k, tab in ipairs(snap.tabs) do
		if #tab.items == 0 and tab.i ~= shown then
			for _, old in ipairs(prev.tabs) do
				local same = (old.i and old.i == tab.i) or (not old.i and old.name == tab.name)
				if same and type(old.items) == "table" and #old.items > 0 and (not old.kept or old.kept == visit) then
					snap.tabs[k] = { name = tab.name, icon = tab.icon, i = tab.i, items = old.items, kept = visit }
					break
				end
			end
		end
	end
	return snap
end

local function ReadNow()
	if not open and not HasBank() then return end
	local old = ns.rdb.bank
	local snap = Bank.Keep(Bank.Read(), old)
	if not snap then return end
	-- (1.1: the last snapshot of an earlier visit is what "gone since" compares with.)
	snap.visit = visit
	if type(old) == "table" and old.visit ~= visit and old.guild == snap.guild then ns.rdb.bankPrev = old end
	ns.rdb.bank = snap
	ns.Fire("TREASURY_CHANGED")
	Bank.Share()
	Bank.ShareSister()
end

-- The bank open: every tab we may see is asked for (the game loads the one shown alone), and
-- once the slots settle (SETTLE after the last change, SETTLE_MAX after the first at most) the
-- snapshot is taken (and sent, the Treasurer's).
local function Settle()
	lastChange = GetTime()
	if readPending then return end
	readPending, firstChange = true, lastChange
	local function Check()
		local wait = math.min(lastChange + Bank.SETTLE, firstChange + Bank.SETTLE_MAX) - GetTime()
		if wait > 0.05 then return ns.After(wait, "bank read", Check) end
		readPending = false
		ReadNow()
	end
	ns.After(Bank.SETTLE, "bank read", Check)
end

function Bank.Opened()
	if not HasBank() or not ns.IsMember() then return end
	open = true
	visit = math.max(ns.Now(), visit + 1) -- (a number no earlier visit has: kept tabs carry theirs)
	wipe(queried)
	local n = tonumber(GetNumGuildBankTabs()) or 0
	for tab = 1, math.min(n, Bank.MAX_TABS) do
		local _, _, viewable = GetGuildBankTabInfo(tab)
		if viewable then
			queried[tab] = true
			if QueryGuildBankTab then pcall(QueryGuildBankTab, tab) end
		end
	end
	Settle()
	-- (1.1: a sister guild's treasurer is asked once a session whether the King sees his bank.)
	Bank.AskSister()
end
function Bank.Changed() if open then Settle() end end
function Bank.Closed()
	if not open then return end
	Settle()
	open = false
end

-- The newer clients' interaction manager (WoW: Forever): the guild banker's window opens and
-- closes with the others; only its type is ours. A client that also says GUILDBANKFRAME_OPENED
-- opens one visit, not two (whichever came first).
local function GuildBanker(kind)
	local want = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker or 10
	return tonumber(kind) == want
end
local openedAt = -math.huge
local function OpenedOnce()
	local now = GetTime and GetTime() or 0
	if open and now - openedAt < 1 then return end
	openedAt = now
	Bank.Opened()
end
function Bank.InteractionShow(kind) if GuildBanker(kind) then OpenedOnce() end end
function Bank.InteractionHide(kind) if GuildBanker(kind) then Bank.Closed() end end

ns.On("LOGIN", function()
	if not HasBank() then return end
	local events = {
		GUILDBANKFRAME_OPENED = OpenedOnce,
		GUILDBANKBAGSLOTS_CHANGED = Bank.Changed,
		GUILDBANK_UPDATE_TABS = Bank.Changed,
		GUILDBANK_UPDATE_MONEY = Bank.Changed,
		GUILDBANKFRAME_CLOSED = Bank.Closed,
		PLAYER_INTERACTION_MANAGER_FRAME_SHOW = Bank.InteractionShow,
		PLAYER_INTERACTION_MANAGER_FRAME_HIDE = Bank.InteractionHide,
	}
	for event, fn in pairs(events) do
		pcall(ns.RegisterEvent, event, function(...) ns.SafeCall("bank " .. event, fn, ...) end)
	end
	-- Repeated for late logins (a keeper's), while the bank is not open.
	ns.Every(300, "bank share", function() if not open then Bank.Share() end end)
end)

---------------------------------------------------------------------------
-- 1.1: the bank's search, what left it since the last visit, and the sister guilds' banks
-- (asked by Fern, a moderator on Asmon's team: finding one item in eight tabs is slow, and a
-- missing stack is either a withdrawal nobody noted or theft). Counts only: the game's bank log
-- (who took what) is never read, and nothing in any bank is ever moved.
---------------------------------------------------------------------------

-- The snapshot before `cur` (the same guild's, older: of an earlier visit, ours or a keeper's),
-- which "gone since" compares with; nil when none.
function Bank.Previous(cur)
	if type(cur) ~= "table" or not ns.rdb then return nil end
	local best
	for _, key in ipairs({ "bankPrev", "bankReportPrev", "bank", "bankReport" }) do
		local s = ns.rdb[key]
		if type(s) == "table" and s ~= cur and s.guild == cur.guild and type(s.tabs) == "table" and (tonumber(s.t) or 0) < (tonumber(cur.t) or 0)
			and (not best or (tonumber(s.t) or 0) > (tonumber(best.t) or 0)) then
			best = s
		end
	end
	return best
end

-- The stacks gone since `prev`: each item's count summed over the tabs both snapshots hold
-- (matched by the tab's number, by its name when one has none; a tab not seen is no theft), a
-- tab kept from an earlier read left out (its items were not seen then). A stack moved to
-- another tab both hold is not gone. { { id, n, tabs = { name, ... } }, ... }, the most first;
-- and ghosts[tab index in cur] = { { id, n, s, gone = true } }: the slots of `cur` those stacks
-- sat in, empty now (the grid shows them faded).
function Bank.Gone(cur, prev)
	local out, ghosts = {}, {}
	if type(cur) ~= "table" or type(prev) ~= "table" or type(cur.tabs) ~= "table" or type(prev.tabs) ~= "table" then return out, ghosts end
	local before, now, where = {}, {}, {}
	for ci, tab in ipairs(cur.tabs) do
		local old
		for _, o in ipairs(prev.tabs) do
			if (tab.i and o.i and o.i == tab.i) or ((not tab.i or not o.i) and o.name == tab.name) then old = o break end
		end
		if old and not tab.kept and not old.kept and type(old.items) == "table" and type(tab.items) == "table" then
			local here = {}
			for _, it in ipairs(tab.items) do
				now[it.id] = (now[it.id] or 0) + (tonumber(it.n) or 0)
				if it.s then here[it.s] = true end
			end
			for _, it in ipairs(old.items) do
				before[it.id] = (before[it.id] or 0) + (tonumber(it.n) or 0)
				where[it.id] = where[it.id] or {}
				table.insert(where[it.id], { tab = ci, name = tab.name, s = it.s, n = tonumber(it.n) or 0, empty = it.s ~= nil and not here[it.s] })
			end
		end
	end
	for id, n in pairs(before) do
		local gone = n - (now[id] or 0)
		if gone > 0 then
			local tabs, seen, left = {}, {}, gone
			for _, w in ipairs(where[id]) do
				if not seen[w.name] then seen[w.name] = true tabs[#tabs + 1] = w.name end
				if w.empty and left > 0 then
					ghosts[w.tab] = ghosts[w.tab] or {}
					table.insert(ghosts[w.tab], { id = id, n = math.min(w.n, left), s = w.s, gone = true })
					left = left - math.min(w.n, left)
				end
			end
			out[#out + 1] = { id = id, n = gone, tabs = tabs }
		end
	end
	table.sort(out, function(a, b)
		if a.n ~= b.n then return a.n > b.n end
		return a.id < b.id
	end)
	return out, ghosts
end

-- The stacks of a snapshot whose item (its name as this client knows it, or its number) holds
-- the search `q` (folded: Views.Query): { { id, n, tabs = { name, ... }, stacks }, ... }, the most
-- first. An item this client never saw finds by its number until the game names it.
function Bank.Find(snap, q)
	local out, byId = {}, {}
	if type(snap) ~= "table" or type(snap.tabs) ~= "table" or not q or q == "" then return out end
	local Name = ns.Treasury and ns.Treasury.ItemName or tostring
	for _, tab in ipairs(snap.tabs) do
		for _, it in ipairs(type(tab.items) == "table" and tab.items or {}) do
			if ns.Holds(q, Name(it.id), tostring(it.id)) then
				local x = byId[it.id]
				if not x then
					x = { id = it.id, n = 0, tabs = {}, stacks = 0, seen = {} }
					byId[it.id] = x
					out[#out + 1] = x
				end
				x.n, x.stacks = x.n + (tonumber(it.n) or 0), x.stacks + 1
				if not x.seen[tab.name] then x.seen[tab.name] = true x.tabs[#x.tabs + 1] = tab.name end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.n ~= b.n then return a.n > b.n end
		return a.id < b.id
	end)
	return out
end

-- Sister guilds' banks: an Olympus guild other than the King's, whose treasurer (its guild
-- master or an officer, by the server's own roster) says yes, has its snapshot whispered to the
-- King, his Stewards and his Hands alone, never on the channel (the whole army would see another
-- guild's stock), when their addon asks (TA, Treasury.lua) and when it changes:
--   TS~<guild>~<time>~<copper>~;<id>x<count>,.<gap>,...~;...   in pieces (Treasury.Private): the
--   tabs' names left out (a name another guild typed never reaches the King's screen, his stream:
--   "Tab 1", "Tab 2"); TS~<guild>~0~0~ withdraws it (his no)
-- Taken only from a Lord or Captain of that guild as our roster or its census confirms (the
-- census can be gamed: a snapshot is its sender's word, shown with his name), kept in memory
-- alone, SISTERS_MAX guilds at most.
Bank.SISTERS_MAX = 20
local sisters, sisterCount = {}, 0   -- [guild, lower case] = { guild, by, t, money, tabs, heard }
local sisterHeard = {}               -- [Name-Realm] = when the King, a Steward or a Hand asked
local sisterAsked = false

-- The King, his Steward, his Hands: who may see them (their names, which the server stamps).
local function SisterViewer(name)
	if type(name) ~= "string" or name == "" then return false end
	return ns.IsKingCharacter(name) or ns.King.IsStewardName(name) or ns.King.IsHandName(name)
end
function Bank.SeesSisters() return ns.King.IsKing() or ns.King.IsSteward() or ns.King.IsHand() end
-- A Hand's client asks for them too (TA): the King's and a Steward's ask anyway.
function Bank.AsksSisters() return ns.King.IsHand() end

-- A Lord or Captain of `guild`, as our roster (our own guild) or that guild's census says.
function Bank.LordOrCaptain(sender, guild)
	if type(sender) ~= "string" or type(guild) ~= "string" or guild == "" then return false end
	local rank = ns.Data.KnownRank(ns.FullName(sender), guild)
	return rank ~= nil and rank <= ns.CAPTAIN_RANK
end

-- This character is its guild's treasurer for this: the guild master or an officer (the server's
-- rank), of an Olympus guild that is not the King's.
function Bank.SisterTreasurer()
	if not ns.IsMember() or not ns.me then return false end
	local guild, _, rank = GetGuildInfo("player")
	rank = tonumber(rank)
	return type(guild) == "string" and not ns.IsKingGuild(guild) and rank ~= nil and rank <= ns.CAPTAIN_RANK
end
local function SisterKey() return tostring(ns.FullName(ns.me) or ""):lower() end
-- His yes (true), his no (false), or nil until he answers: per character.
function Bank.SisterConsent()
	local t = ns.db and ns.db.sisterBankShares
	if type(t) ~= "table" then return nil end
	return t[SisterKey()]
end

-- Our own guild's snapshot as it is whispered (TS), with his yes; nil otherwise.
function Bank.SisterMessage()
	if not Bank.SisterTreasurer() or Bank.SisterConsent() ~= true then return nil end
	local snap, guild = Bank.Own(), GetGuildInfo("player")
	if type(snap) ~= "table" or snap.guild ~= guild then return nil end
	return Bank.Message(snap, "TS")
end

-- To the King, a Steward or a Hand who asked within Treasury.AUDIENCE_FRESH (each gets a
-- snapshot once, the next when it changed).
function Bank.ShareSister()
	local msg = Bank.SisterMessage()
	if not msg then return 0 end
	local n, now = 0, ns.Now()
	for name, t in pairs(sisterHeard) do
		if now - t <= ns.Treasury.AUDIENCE_FRESH and SisterViewer(name) and ns.Treasury.Private(name, "TS", msg) then n = n + 1 end
	end
	return n
end

-- The King, a Steward or a Hand asked (TA): our guild's bank goes to him (fresh: he holds none).
function Bank.HeardAsk(sender, fresh)
	if not SisterViewer(sender) then return end
	sisterHeard[ns.FullName(sender)] = ns.Now()
	if fresh then ns.Treasury.ForgetSent(sender, "TS") end
	local msg = Bank.SisterMessage()
	if msg then ns.Treasury.Private(sender, "TS", msg) end
end
function Bank.NotFound(Is) for name in pairs(sisterHeard) do if Is(name) then sisterHeard[name] = nil end end end

function Bank.SetSisterConsent(on)
	if not Bank.SisterTreasurer() then return ns.Print(L.BANK_SISTER_ONLY) end
	ns.db.sisterBankShares = type(ns.db.sisterBankShares) == "table" and ns.db.sisterBankShares or {}
	ns.db.sisterBankShares[SisterKey()] = on and true or false
	ns.Print(on and L.BANK_SISTER_ON or L.BANK_SISTER_OFF)
	if on then return Bank.ShareSister() end
	-- His no: taken back from the screens it reached (the ones his addon whispered).
	local guild, now = GetGuildInfo("player"), ns.Now()
	for name, t in pairs(sisterHeard) do
		if now - t <= ns.Treasury.AUDIENCE_FRESH then ns.Comm.Whisper(name, ("TS~%s~0~0~"):format(Clean(guild, 40)), "sisterbank " .. name) end
		ns.Treasury.ForgetSent(name, "TS")
	end
end

StaticPopupDialogs["OLYMPUS_SISTER_BANK"] = {
	text = L.BANK_SISTER_ASK,
	button1 = L.BANK_SISTER_YES,
	button2 = L.BANK_SISTER_NO,
	OnAccept = function() ns.SafeCall("sister bank", Bank.SetSisterConsent, true) end,
	OnCancel = function(_, _, reason)
		if reason == "clicked" then ns.SafeCall("sister bank", Bank.SetSisterConsent, false) end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	noCancelOnEscape = true, -- Escape is no answer: asked again next session
	preferredIndex = 3,
}
-- Asked once a session, when he opens his guild's bank, until he answers (never in combat).
function Bank.AskSister()
	if sisterAsked or not Bank.SisterTreasurer() or Bank.SisterConsent() ~= nil then return false end
	if InCombatLockdown and InCombatLockdown() then return false end
	sisterAsked = true
	ns.ShowDialog("OLYMPUS_SISTER_BANK", GetGuildInfo("player") or "?")
	return true
end

-- A sister guild's snapshot (TS), on the King's, a Steward's or a Hand's client: from a Lord or
-- Captain of that guild (our roster or its census), the newest kept, in memory alone.
function Bank.HandleSister(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" or not Bank.SeesSisters() then return end
	local guild, when, money, rest = text:match("^TS~([^~]*)~(%d+)~(%d+)~?(.*)$")
	guild = guild and ns.King.CleanGuild(guild)
	if not guild or ns.IsKingGuild(guild) or not Bank.LordOrCaptain(sender, guild) then return end
	local key, now = guild:lower(), ns.Now()
	when = tonumber(when)
	if when == 0 then
		if sisters[key] then sisters[key], sisterCount = nil, sisterCount - 1 end
		ns.Fire("TREASURY_CHANGED")
		return
	end
	local r = { guild = guild, by = ns.FullName(sender), t = math.min(when, now), money = math.min(tonumber(money) or 0, 2147483647),
		tabs = ReadTabs(rest, true), heard = now }
	if #r.tabs == 0 then return end
	local kept = sisters[key]
	if kept and kept.t > r.t then return end
	if not kept then
		if sisterCount >= Bank.SISTERS_MAX then
			local oldest
			for k, x in pairs(sisters) do if not oldest or x.heard < sisters[oldest].heard then oldest = k end end
			sisters[oldest], sisterCount = nil, sisterCount - 1
		end
		sisterCount = sisterCount + 1
	end
	sisters[key] = r
	ns.Fire("TREASURY_CHANGED")
	ns.Fire("DATA_CHANGED") -- (a Hand's tab may appear)
end
ns.Comm.Handle("TS", function(...) Bank.HandleSister(...) end)
ns.Treasury.OnPrivate("TS", { from = function() return true end, to = function() return Bank.SeesSisters() end,
	handle = function(...) Bank.HandleSister(...) end })

-- The sister guilds' banks this client holds, by guild name (the King's, a Steward's, a Hand's).
function Bank.Sisters()
	local out = {}
	if not Bank.SeesSisters() then return out end
	for _, x in pairs(sisters) do out[#out + 1] = x end
	table.sort(out, function(a, b) return a.guild:lower() < b.guild:lower() end)
	return out
end

-- Tests start from a clean state.
function Bank.Reset()
	open, readPending, lastShare, lastSent = false, false, -math.huge, nil
	firstChange, lastChange, sharePending, openedAt = 0, 0, false, -math.huge
	wipe(queried)
	wipe(sisters); wipe(sisterHeard)
	sisterCount, sisterAsked = 0, false
	if ns.rdb then ns.rdb.bank, ns.rdb.bankReport, ns.rdb.bankPrev, ns.rdb.bankReportPrev = nil, nil, nil, nil end
end
function Bank.SetOpenForTest(on, tabs) open = on; wipe(queried); for _, t in ipairs(tabs or {}) do queried[t] = true end end
