local ADDON, ns = ...
local L = ns.L

-- The Treasury of Olympus, kept by the Treasurer (ns.TREASURER of the guild OLYMPUS, see
-- ns.IsTreasurer). His client keeps the book: gold he receives by trade or mail is a donation,
-- gold he gives by trade or mail a payment. What he earns playing is his: the treasury is the
-- book (an opening balance, plus what came in, less what went out), never his character's
-- gold. A trade where he gave items for the gold is a sale, one where he got items for his
-- gold a purchase: both go in the book as not counted, and a click on a line counts it (or
-- stops counting it). The auction house's and the game's mail is no donation.
-- His addon sends the treasury on the channel by itself (every few minutes and after a change):
-- the balance, the totals, the ranking of donors and the latest lines of the book. The King
-- sees all of it; what the rest of the army sees is the King's choice, three switches (the
-- balance, the ranking, the book), and with any of them on the Treasury tab appears for every
-- member with the addon. (The channel is readable by anyone on it: the switches choose what
-- the addon shows, they don't hide the numbers.)
--   T7~<guild>~<balance>~<all in>~<all out>~<week in>~<donors this week>~<Name:copper,...>~<i|o:copper:Name:m|t:time,...>
--   T1~T~<id>~<guild>~<balance 0|1><ranking 0|1><book 0|1>        the King's switches (King.lua)

local Treasury = {}
ns.Treasury = Treasury

Treasury.MAX = 500           -- lines kept in the book (the sums are kept apart)
Treasury.DAYS_KEPT = 8       -- days of sums kept (today and the week)
Treasury.SHARE_EVERY = 300   -- the Treasurer's client repeats the treasury for late logins
Treasury.SHARE_GAP = 60      -- and sends a change once a minute at most
Treasury.FLAGS_EVERY = 300   -- the King's client repeats his switches
Treasury.REPORT_KEPT = 7 * 86400 -- a treasury not heard of for a week is dropped
Treasury.RANK_SENT = 10      -- donors in the ranking sent
Treasury.BOOK_SENT = 15      -- latest lines of the book sent
Treasury.BOOK_SHOWN = 40     -- lines of his own book the Treasurer sees
Treasury.MAX_COPPER = 2147483647

Treasury.mode = "summary"    -- what the tab shows: summary or book

local trade                  -- the trade window open: { name, got, gave, gotItems, gaveItems }
local mailOut                -- a mail with gold on its way: { to, money }
local report                 -- the Treasurer's last treasury: { balance, allIn, allOut, week, donors, rank, book, t, from }
local lastShare, sharePending = -math.huge, false
local lastFlagsSent = -math.huge
local taken = {}             -- [mail] = when its gold was taken (a few seconds)

local function Grey(s) return "|cff9d9d9d" .. s .. "|r" end
local function Gold(s) return "|cffffd200" .. s .. "|r" end
local function Green(s) return "|cff40ff40" .. s .. "|r" end
local function Red(s) return "|cffff6060" .. s .. "|r" end

local function Book()
	ns.rdb.treasury = ns.rdb.treasury or {}
	return ns.rdb.treasury
end
local function DayKey(t) return date and date("%Y-%m-%d", t) or tostring(math.floor(t / 86400)) end

-- 12g 30s 5c, with the coin icons when the client has them (a minus sign when negative).
function Treasury.Coins(copper)
	copper = math.floor(tonumber(copper) or 0)
	local sign = copper < 0 and "-" or ""
	copper = math.abs(copper)
	if GetCoinTextureString then
		local ok, s = pcall(GetCoinTextureString, copper)
		if ok and s then return sign .. s end
	end
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 then parts[#parts + 1] = s .. "s" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
	return sign .. table.concat(parts, " ")
end
-- Gold alone, for the big numbers: "12,345g".
function Treasury.GoldText(copper)
	copper = math.floor(tonumber(copper) or 0)
	return (copper < 0 and "-" or "") .. ns.FormatNumber(math.floor(math.abs(copper) / 10000)) .. "g"
end
-- For Discord: plain text.
local function Plain(copper)
	copper = math.floor(tonumber(copper) or 0)
	local sign = copper < 0 and "-" or ""
	copper = math.abs(copper)
	local g, s = math.floor(copper / 10000), math.floor(copper / 100) % 100
	return sign .. (g > 0 and ("%sg %ds"):format(ns.FormatNumber(g), s) or ("%ds %dc"):format(s, copper % 100))
end

---------------------------------------------------------------------------
-- Who
---------------------------------------------------------------------------

-- The Treasurer himself (or the author's "Treasurer's view", from the Workshop).
function Treasury.IsTreasurer()
	if ns.IsMember() and ns.IsTreasurer(ns.me, GetGuildInfo("player")) then return true end
	return Treasury.DevView()
end
function Treasury.DevView()
	return ns.db and ns.db.devTreasurerView == true and ns.Workshop and ns.Workshop.Visible and ns.Workshop.Visible() or false
end
function Treasury.SetDevView(on)
	ns.db.devTreasurerView = on and true or nil
	ns.Print(on and L.DEV_TREASURER_VIEW_NOW_ON or L.DEV_TREASURER_VIEW_NOW_OFF)
	ns.Fire("DATA_CHANGED")
end

local function IsKingView() return ns.King.IsKing() or ns.King.Preview() end

-- The King's switches: what the army sees (every client keeps the King's last word).
local FLAGS = { "balance", "ranking", "book" }
function Treasury.Flags()
	local f = ns.rdb and ns.rdb.treasuryFlags
	return type(f) == "table" and f or {}
end
function Treasury.Shows(what) return Treasury.Flags()[what] == true end
function Treasury.AnyShown()
	for _, k in ipairs(FLAGS) do if Treasury.Shows(k) then return true end end
	return false
end

-- Who has the tab: the Treasurer, the King (where a Treasurer can be, or once a treasury came;
-- the author's view always), and every member once the King shows the army something.
function Treasury.Visible()
	if Treasury.IsTreasurer() or ns.King.Preview() then return true end
	if ns.King.IsKing() then return (ns.splitNames and ns.faction ~= "Horde") or Treasury.Report() ~= nil end
	return ns.IsMember() and Treasury.AnyShown() and Treasury.Report() ~= nil
end

---------------------------------------------------------------------------
-- The book (the Treasurer's client)
---------------------------------------------------------------------------

-- The sums, whatever the book keeps: all time (in, out, each donor's), and per day (in, out,
-- each donor's) for today and the week. Rebuilt from the book once (0.8.3 kept no donors).
local function Sums()
	local s = ns.rdb.treasurySums
	if type(s) ~= "table" or s.version ~= 2 then
		s = { version = 2, allIn = 0, allOut = 0, byDonor = {}, days = {} }
		ns.rdb.treasurySums = s
		for _, e in ipairs(Book()) do
			if not e.excluded then
				if e.out then s.allOut = s.allOut + e.money else
					s.allIn = s.allIn + e.money
					s.byDonor[e.name] = (s.byDonor[e.name] or 0) + e.money
				end
			end
		end
	end
	return s
end

-- An entry into the sums (sign 1) or out of them (sign -1).
local function Count(e, sign)
	local s = Sums()
	local copper = e.money * sign
	local now = ns.Now()
	local key = DayKey(e.t)
	local day = s.days[key]
	if not day and sign > 0 and now - e.t <= Treasury.DAYS_KEPT * 86400 then
		day = { inn = 0, out = 0, by = {} }
		s.days[key] = day
	end
	if e.out then
		s.allOut = s.allOut + copper
		if day then day.out = day.out + copper end
	else
		s.allIn = s.allIn + copper
		s.byDonor[e.name] = (s.byDonor[e.name] or 0) + copper
		if s.byDonor[e.name] <= 0 then s.byDonor[e.name] = nil end
		if day then
			day.inn = day.inn + copper
			day.by[e.name] = (day.by[e.name] or 0) + copper
			if day.by[e.name] <= 0 then day.by[e.name] = nil end
		end
	end
	local oldest = DayKey(now - Treasury.DAYS_KEPT * 86400)
	for k in pairs(s.days) do if k < oldest then s.days[k] = nil end end
end

function Treasury.Opening() return tonumber(ns.rdb and ns.rdb.treasuryOpening) or 0 end

-- The treasury: the opening balance, plus what came in, less what went out (counted lines).
function Treasury.Balance()
	local s = Sums()
	return Treasury.Opening() + s.allIn - s.allOut
end

-- out: a payment. o: { excluded = true, kind = "sale"|"purchase", quiet = true }.
function Treasury.Record(name, copper, how, out, o)
	o = o or {}
	copper = math.floor(tonumber(copper) or 0)
	if copper <= 0 or type(name) ~= "string" or name == "" then return end
	local book = Book()
	Sums() -- (built from the book as it was, before this line joins it)
	local who = ns.DisplayName(ns.Normal(name)) or name
	local e = { name = who, money = copper, how = how, t = ns.Now(), out = out or nil, excluded = o.excluded or nil, kind = o.kind }
	book[#book + 1] = e
	while #book > Treasury.MAX do table.remove(book, 1) end
	if not e.excluded then Count(e, 1) end
	-- The King (and the army) see it soon (once a minute at most).
	Treasury.Share()
	if not o.quiet then
		if e.excluded then
			ns.Print((e.kind == "sale" and L.TREASURY_SALE or L.TREASURY_PURCHASE):format(who, Treasury.Coins(copper)))
		else
			ns.Print((out and L.TREASURY_PAID or L.TREASURY_DONATION):format(who, Treasury.Coins(copper)))
			if not out then ns.PlayAlert("soft") end
		end
	end
	ns.Fire("TREASURY_CHANGED")
	return e
end

-- A line of the book counted, or no longer (the Treasurer's click: a sale that was a
-- donation, a payment that was his own).
function Treasury.Toggle(e)
	if not Treasury.IsTreasurer() or type(e) ~= "table" then return end
	e.excluded = not e.excluded or nil
	Count(e, e.excluded and -1 or 1)
	Treasury.Share()
	ns.Fire("TREASURY_CHANGED")
end

-- "12345", "12345g", "12345g 50s", "50s 20c": copper, or nil.
function Treasury.ParseGold(text)
	text = tostring(text or ""):lower():gsub(",", ""):gsub("%.", "")
	local g = tonumber(text:match("(%d+)%s*g")) or 0
	local s = tonumber(text:match("(%d+)%s*s")) or 0
	local c = tonumber(text:match("(%d+)%s*c")) or 0
	if g == 0 and s == 0 and c == 0 then
		local plain = tonumber(text:match("^%s*(%d+)%s*$"))
		if not plain then return nil end
		g = plain
	end
	return math.min(g * 10000 + s * 100 + c, Treasury.MAX_COPPER)
end

function Treasury.SetOpening(input)
	if not Treasury.IsTreasurer() then return ns.Print(L.TREASURY_ONLY) end
	local copper = Treasury.ParseGold(input)
	if not copper then return ns.Print(L.TREASURY_OPENING_USAGE) end
	ns.rdb.treasuryOpening = copper
	ns.Print(L.TREASURY_OPENING_SET:format(Treasury.Coins(copper)))
	Treasury.Share()
	ns.Fire("TREASURY_CHANGED")
end

-- Trades: what each side put in, as the window last showed it (read again once complete, it
-- can say 0), counted when the game says the trade is complete.
local function AnyItem(info)
	if not info then return false end
	for i = 1, 6 do
		local name = info(i)
		if name and name ~= "" then return true end
	end
	return false
end
function Treasury.TradeMoney()
	if not trade then return end
	if GetTargetTradeMoney then trade.got = tonumber(GetTargetTradeMoney()) or trade.got end
	if GetPlayerTradeMoney then trade.gave = tonumber(GetPlayerTradeMoney()) or trade.gave end
	trade.gaveItems = AnyItem(GetTradePlayerItemInfo)
	trade.gotItems = AnyItem(GetTradeTargetItemInfo)
end

function Treasury.TradeShow()
	if not Treasury.IsTreasurer() then return end
	local name = ns.UnitFullName and ns.UnitFullName("NPC") or (UnitName and UnitName("NPC"))
	trade = name and { name = name, got = 0, gave = 0 } or nil
end

function Treasury.Info(a, b)
	-- Classic passes (type, message), older clients the message alone.
	local msg = type(b) == "string" and b or a
	if not trade or msg ~= ERR_TRADE_COMPLETE then return end
	local done = trade
	trade = nil
	-- Gold for his items: a sale, his. His gold for items: a purchase, his. Not counted
	-- unless he says so (a click on the line).
	if done.got > 0 then
		Treasury.Record(done.name, done.got, "trade", nil, done.gaveItems and { excluded = true, kind = "sale" } or nil)
	end
	if done.gave > 0 then
		Treasury.Record(done.name, done.gave, "trade", true, done.gotItems and { excluded = true, kind = "purchase" } or nil)
	end
end

-- Mail sent with gold: counted once the game says it went.
function Treasury.MailSending(to)
	if not Treasury.IsTreasurer() then return end
	local money = GetSendMailMoney and tonumber(GetSendMailMoney()) or 0
	mailOut = money > 0 and type(to) == "string" and to ~= "" and { to = to, money = money } or nil
end
function Treasury.MailSent()
	local m = mailOut
	mailOut = nil
	if m then Treasury.Record(m.to, m.money, "mail", true) end
end

-- The game's own mail (the auction house, cash on delivery): not from a player. Their
-- subjects are the client's format strings, "%s" standing for the item.
local SYSTEM_SUBJECTS = { "AUCTION_OUTBID_MAIL_SUBJECT", "AUCTION_SOLD_MAIL_SUBJECT", "AUCTION_WON_MAIL_SUBJECT",
	"AUCTION_REMOVED_MAIL_SUBJECT", "AUCTION_EXPIRED_MAIL_SUBJECT", "COD_PAYMENT" }
local systemPatterns
local function SystemMail(subject)
	if type(subject) ~= "string" then return false end
	if not systemPatterns or #systemPatterns == 0 then
		systemPatterns = {}
		for _, key in ipairs(SYSTEM_SUBJECTS) do
			local f = _G[key]
			if type(f) == "string" and f ~= "" then
				local p = f:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", ".+"):gsub("%%%%d", "%%d+")
				systemPatterns[#systemPatterns + 1] = "^" .. p .. "$"
			end
		end
	end
	for _, p in ipairs(systemPatterns) do
		if subject:find(p) then return true end
	end
	return false
end

-- A donation by mail is counted when the Treasurer takes its gold (the money button, or a
-- mail addon's "open all": TakeInboxMoney, AutoLootMailItem), read from the mail just before
-- the game empties it. Two clicks on the same mail before the server answers count once.
function Treasury.MailTaking(i)
	if not Treasury.IsTreasurer() or not GetInboxHeaderInfo or type(i) ~= "number" then return end
	local _, _, sender, subject, money, _, _, _, _, wasReturned, _, canReply, isGM = GetInboxHeaderInfo(i)
	money = tonumber(money) or 0
	local invoice = GetInboxInvoiceInfo and GetInboxInvoiceInfo(i)
	if money <= 0 or type(sender) ~= "string" or sender == "" or isGM or wasReturned or invoice
		or canReply == false or SystemMail(subject) then return end
	local key = ("%d|%s|%s|%d"):format(i, sender, tostring(subject or ""), money)
	local now = GetTime and GetTime() or ns.Now()
	for k, t in pairs(taken) do if now - t >= 5 then taken[k] = nil end end
	if taken[key] then return end
	taken[key] = now
	Treasury.Record(sender, money, "mail")
end

-- The sums: today, this week (today and the 6 days before), all time; the givers of the
-- week and of all time, most generous first.
function Treasury.Totals()
	local now = ns.Now()
	local s = Sums()
	local t = { todayIn = 0, todayOut = 0, weekIn = 0, weekOut = 0, allIn = s.allIn, allOut = s.allOut, givers = {}, ranking = {} }
	local by = {}
	for back = 0, 6 do
		local day = s.days[DayKey(now - back * 86400)]
		if day then
			t.weekIn, t.weekOut = t.weekIn + day.inn, t.weekOut + day.out
			if back == 0 then t.todayIn, t.todayOut = day.inn, day.out end
			for name, copper in pairs(day.by) do
				local g = by[name]
				if not g then
					g = { name = name, money = 0 }
					by[name] = g
					t.givers[#t.givers + 1] = g
				end
				g.money = g.money + copper
			end
		end
	end
	for name, copper in pairs(s.byDonor) do t.ranking[#t.ranking + 1] = { name = name, money = copper } end
	local function Most(a, b)
		if a.money ~= b.money then return a.money > b.money end
		return a.name < b.name
	end
	table.sort(t.givers, Most)
	table.sort(t.ranking, Most)
	return t
end

---------------------------------------------------------------------------
-- Sharing: the Treasurer's treasury, and everyone's copy of it
---------------------------------------------------------------------------

-- Only the real Treasurer's client sends (never the author's view).
local function CanSend() return ns.IsMember() and ns.IsTreasurer(ns.me, GetGuildInfo("player")) end

local function Clean(name) return (tostring(name or ""):gsub("[~:,|%c]", "")) end

function Treasury.Message()
	local t = Treasury.Totals()
	local rank = {}
	for i = 1, math.min(Treasury.RANK_SENT, #t.ranking) do
		rank[#rank + 1] = ("%s:%d"):format(Clean(t.ranking[i].name), math.min(t.ranking[i].money, Treasury.MAX_COPPER))
	end
	local lines, book = {}, Book()
	for i = #book, 1, -1 do
		local e = book[i]
		if not e.excluded then
			lines[#lines + 1] = ("%s:%d:%s:%s:%d"):format(e.out and "o" or "i", math.min(e.money, Treasury.MAX_COPPER), Clean(e.name),
				e.how == "mail" and "m" or "t", e.t or 0)
			if #lines >= Treasury.BOOK_SENT then break end
		end
	end
	local balance = math.max(-Treasury.MAX_COPPER, math.min(Treasury.Balance(), Treasury.MAX_COPPER))
	return ("T7~%s~%d~%d~%d~%d~%d~%s~%s"):format(GetGuildInfo("player") or "", balance, math.min(t.allIn, Treasury.MAX_COPPER),
		math.min(t.allOut, Treasury.MAX_COPPER), math.min(t.weekIn, Treasury.MAX_COPPER), #t.givers, table.concat(rank, ","), table.concat(lines, ","))
end

function Treasury.Share(force)
	if not CanSend() then return end
	local now = ns.Now()
	-- A change inside the gap goes out once the gap is over, not never.
	if not force and now - lastShare < Treasury.SHARE_GAP then
		if not sharePending then
			sharePending = true
			ns.After(lastShare + Treasury.SHARE_GAP - now, "treasury share", function()
				sharePending = false
				Treasury.Share(true)
			end)
		end
		return
	end
	lastShare = now
	local msg = Treasury.Message()
	if #msg <= 250 then ns.Comm.Send("CHANNEL", msg, "treasury") else ns.Comm.SendChunked(msg) end
end

local function Num(s)
	local n = tonumber(s) or 0
	return math.max(-Treasury.MAX_COPPER, math.min(n, Treasury.MAX_COPPER))
end

function Treasury.HandleReport(dist, sender, text)
	if dist ~= "CHANNEL" then return end
	local guild, rest = text:match("^T7~([^~]*)~(.*)$")
	if not guild then return end
	-- The Treasurer himself: that name, in the guild OLYMPUS, confirmed there by our roster or
	-- the census.
	if not ns.IsTreasurer(sender, guild) then return end
	if not (ns.Roster.RankOf(sender) or ns.Data.KnownRank(sender, guild, true)) then return end
	local balance, allIn, allOut, week, donors, rank, book = rest:match("^(%-?%d+)~(%d+)~(%d+)~(%d+)~(%d+)~([^~]*)~(.*)$")
	if not balance then return end -- (0.8.3's treasury, the Treasurer's own gold: not read)
	local r = { balance = Num(balance), allIn = Num(allIn), allOut = Num(allOut), week = Num(week),
		donors = math.min(tonumber(donors) or 0, 9999), rank = {}, book = {}, t = ns.Now(), from = ns.FullName(sender) }
	for name, copper in rank:gmatch("([^,:]+):(%d+)") do
		local clean = ns.King.CleanName(name)
		if clean and #r.rank < Treasury.RANK_SENT then r.rank[#r.rank + 1] = { name = clean, money = Num(copper) } end
	end
	for kind, copper, name, how, when in book:gmatch("([io]):(%d+):([^:,]+):([mt]):(%d+)") do
		local clean = ns.King.CleanName(name)
		if clean and #r.book < Treasury.BOOK_SENT then
			r.book[#r.book + 1] = { out = kind == "o" or nil, money = Num(copper), name = clean, how = how == "m" and "mail" or "trade",
				t = math.min(tonumber(when) or 0, ns.Now()) }
		end
	end
	report = r
	-- Kept across sessions: the army sees the treasury as last heard.
	ns.rdb.treasuryReport = r
	ns.Fire("TREASURY_CHANGED")
	ns.Fire("DATA_CHANGED") -- the tab may appear
end
ns.Comm.Handle("T7", function(...) Treasury.HandleReport(...) end)

function Treasury.Report()
	if not report and type(ns.rdb and ns.rdb.treasuryReport) == "table" and ns.rdb.treasuryReport.rank then report = ns.rdb.treasuryReport end
	if report and ns.Now() - (tonumber(report.t) or 0) > Treasury.REPORT_KEPT then
		report = nil
		if ns.rdb then ns.rdb.treasuryReport = nil end
	end
	return report
end

---------------------------------------------------------------------------
-- The King's switches: what the army sees
---------------------------------------------------------------------------

local function FlagDigits(f)
	local d = {}
	for i, k in ipairs(FLAGS) do d[i] = f[k] and "1" or "0" end
	return table.concat(d)
end

function Treasury.SendFlags(force)
	if not ns.King.IsKing() or type(ns.rdb and ns.rdb.treasuryFlags) ~= "table" then return end
	local now = ns.Now()
	if not force and now - lastFlagsSent < Treasury.FLAGS_EVERY then return end
	lastFlagsSent = now
	ns.Comm.Send("CHANNEL", ("T1~T~%d~%s~%s"):format(ns.King.NewId(), GetGuildInfo("player") or "", FlagDigits(Treasury.Flags())), "treasuryflags")
end

-- The King's switch (the author's Asmond's view: on his screen only).
function Treasury.SetFlag(what, on)
	if not IsKingView() then return ns.Print(L.THRONE_ONLY_KING) end
	local f = {}
	for _, k in ipairs(FLAGS) do f[k] = Treasury.Shows(k) end
	f[what] = on and true or false
	f.t = ns.Now()
	ns.rdb.treasuryFlags = f
	ns.Print(L["TREASURY_FLAG_" .. what:upper() .. (on and "_ON" or "_OFF")])
	if ns.King.Preview() then ns.Print(L.THRONE_PREVIEW_NOTE) else Treasury.SendFlags(true) end
	ns.Fire("TREASURY_CHANGED")
	ns.Fire("DATA_CHANGED")
end

local function OnFlags(sender, id, rest)
	local b, r, k = tostring(rest or ""):match("^([01])([01])([01])$")
	if not b then return end
	local f = { balance = b == "1", ranking = r == "1", book = k == "1", t = ns.Now(), from = ns.FullName(sender) }
	local was = FlagDigits(Treasury.Flags())
	ns.rdb.treasuryFlags = f
	if FlagDigits(f) ~= was then
		ns.Fire("TREASURY_CHANGED")
		ns.Fire("DATA_CHANGED") -- the tab appears or goes
	end
end
ns.King.Register("T", OnFlags)

ns.On("LOGIN", function()
	ns.RegisterEvent("TRADE_SHOW", function() ns.SafeCall("treasury trade", Treasury.TradeShow) end)
	for _, event in ipairs({ "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED" }) do
		ns.RegisterEvent(event, function() ns.SafeCall("treasury trade", Treasury.TradeMoney) end)
	end
	ns.RegisterEvent("UI_INFO_MESSAGE", function(a, b) ns.SafeCall("treasury trade", Treasury.Info, a, b) end)
	-- The window closes before or after the "trade complete" message, depending on the client:
	-- this trade is forgotten a little later (not the next one, opened meanwhile).
	ns.RegisterEvent("TRADE_CLOSED", function()
		local closing = trade
		ns.After(2, "treasury trade", function() if trade == closing then trade = nil end end)
	end)
	if hooksecurefunc then
		if SendMail then hooksecurefunc("SendMail", function(to) ns.SafeCall("treasury mail", Treasury.MailSending, to) end) end
		if TakeInboxMoney then hooksecurefunc("TakeInboxMoney", function(i) ns.SafeCall("treasury mail", Treasury.MailTaking, i) end) end
		if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", function(i) ns.SafeCall("treasury mail", Treasury.MailTaking, i) end) end
	end
	ns.RegisterEvent("MAIL_SEND_SUCCESS", function() ns.SafeCall("treasury mail", Treasury.MailSent) end)
	ns.RegisterEvent("MAIL_FAILED", function() mailOut = nil end)
	-- The treasury and the King's switches, repeated for late logins.
	ns.Every(60, "treasury share", function()
		if ns.Now() - lastShare >= Treasury.SHARE_EVERY then Treasury.Share(true) end
		Treasury.SendFlags()
	end)
	ns.After(30, "treasury share", function()
		Treasury.Share(true)
		Treasury.SendFlags(true)
	end)
end)

---------------------------------------------------------------------------
-- What the tab shows
---------------------------------------------------------------------------

-- A paragraph in short grey rows (the list's rows are one line each).
local function Para(lines, text)
	local row = ""
	for word in tostring(text or ""):gmatch("%S+") do
		if row ~= "" and #row + 1 + #word > 58 then
			lines[#lines + 1] = { text = Grey(row) }
			row = word
		else
			row = row == "" and word or (row .. " " .. word)
		end
	end
	if row ~= "" then lines[#lines + 1] = { text = Grey(row) } end
	return lines
end

function Treasury.Show(mode)
	Treasury.mode = mode
	ns.Fire("TREASURY_CHANGED")
end

-- Who looks at the tab: the Treasurer (his book), the King (the treasury, all of it), a member
-- (what the King shows).
function Treasury.Role()
	if Treasury.IsTreasurer() then return "treasurer" end
	if IsKingView() then return "king" end
	return "member"
end

-- What a role may see: everything for the Treasurer and the King, the King's switches for
-- the army.
function Treasury.MaySee(what)
	local role = Treasury.Role()
	return role ~= "member" or Treasury.Shows(what)
end

local function RankLines(lines, rank)
	lines[#lines + 1] = { header = true, text = L.TREASURY_RANKING }
	if #rank == 0 then lines[#lines + 1] = { text = Grey(L.TREASURY_NONE) } end
	for i, g in ipairs(rank) do
		if i > Treasury.RANK_SENT then break end
		lines[#lines + 1] = { indent = 1, text = (i <= 3 and Gold or tostring)(("%d. %s"):format(i, g.name)), right = Treasury.Coins(g.money) }
	end
end

local function BookRow(e, clickable)
	local how = e.how == "mail" and L.TREASURY_MAIL or L.TREASURY_TRADE
	local label = (e.out and L.TREASURY_TO or L.TREASURY_FROM):format(e.name)
	local note = e.excluded and (e.kind == "sale" and L.TREASURY_KIND_SALE or e.kind == "purchase" and L.TREASURY_KIND_PURCHASE or L.TREASURY_NOT_COUNTED) or nil
	local amount = Treasury.Coins(e.money)
	return {
		indent = 1,
		text = (e.excluded and Grey(label) or label) .. "  " .. Grey("(" .. how .. ", " .. ns.Ago(e.t) .. (note and (", " .. note) or "") .. ")"),
		right = e.excluded and Grey(amount) or (e.out and Red("-" .. amount) or Green("+" .. amount)),
		onClick = clickable and function() Treasury.Toggle(e) end or nil,
		tooltip = clickable and function(tt)
			tt:AddLine(label, 1, 0.82, 0)
			tt:AddLine(e.excluded and L.TREASURY_CLICK_COUNT or L.TREASURY_CLICK_UNCOUNT, 1, 1, 1, true)
		end or nil,
	}
end

-- The book: in and out, newest first. The Treasurer's own (every line, a click counts it or
-- not), or the lines his treasury last carried.
local function BookLines(role)
	local lines = { { text = Gold("< " .. L.TREASURY_TITLE), onClick = function() Treasury.Show("summary") end, gapAfter = true } }
	lines[#lines + 1] = { header = true, text = L.TREASURY_BOOK }
	if role == "treasurer" then
		Para(lines, L.TREASURY_BOOK_HOW)
		lines[#lines].gapAfter = true
		local book = Book()
		if #book == 0 then lines[#lines + 1] = { text = Grey(L.TREASURY_NONE) } end
		for i = #book, math.max(1, #book - Treasury.BOOK_SHOWN + 1), -1 do lines[#lines + 1] = BookRow(book[i], true) end
		return lines
	end
	local r = Treasury.Report()
	if not r or #r.book == 0 then lines[#lines + 1] = { text = Grey(L.TREASURY_NONE) } end
	for _, e in ipairs(r and r.book or {}) do lines[#lines + 1] = BookRow(e, false) end
	return lines
end

local function SummaryLines(role)
	local lines = { { header = true, text = L.TREASURY_TITLE } }
	local balance, allIn, allOut, week, donors, rank, asOf
	if role == "treasurer" then
		Para(lines, L.TREASURY_HOW)
		lines[#lines].gapAfter = true
		local t = Treasury.Totals()
		balance, allIn, allOut, week, donors, rank = Treasury.Balance(), t.allIn, t.allOut, t.weekIn, #t.givers, t.ranking
	else
		local r = Treasury.Report()
		if not r then
			Para(lines, L.TREASURY_WAIT:format(ns.TREASURER))
			return lines
		end
		balance, allIn, allOut, week, donors, rank, asOf = r.balance, r.allIn, r.allOut, r.week, r.donors, r.rank, r.t
	end
	if Treasury.MaySee("balance") then
		lines[#lines + 1] = { text = Gold(L.TREASURY_BALANCE), right = Treasury.Coins(balance) }
		lines[#lines + 1] = { text = L.TREASURY_IN_OUT, right = Green("+" .. Treasury.Coins(allIn)) .. "  " .. Red("-" .. Treasury.Coins(allOut)) }
		lines[#lines + 1] = { text = L.TREASURY_WEEK:format(donors), right = Green("+" .. Treasury.Coins(week)) }
		if role == "treasurer" then
			lines[#lines + 1] = { text = Grey(L.TREASURY_OPENING:format(Treasury.Coins(Treasury.Opening()))),
				onClick = function() StaticPopup_Show("OLYMPUS_TREASURY_OPENING") end,
				tooltip = function(tt) tt:AddLine(L.TREASURY_OPENING_TIP, 1, 1, 1, true) end }
		end
		if asOf then lines[#lines + 1] = { text = Grey(L.TREASURY_AS_OF:format(ns.TREASURER, ns.Ago(asOf))) } end
		lines[#lines].gapAfter = true
	end
	if Treasury.MaySee("ranking") then
		RankLines(lines, rank)
		lines[#lines].gapAfter = true
	end
	if Treasury.MaySee("book") then
		lines[#lines + 1] = { text = Gold("> " .. L.TREASURY_BOOK), onClick = function() Treasury.Show("book") end, gapAfter = true }
	end
	-- The King: what the army sees now (the switches are the buttons in the box).
	if role == "king" then
		local shown = {}
		for _, k in ipairs(FLAGS) do if Treasury.Shows(k) then shown[#shown + 1] = L["TREASURY_PART_" .. k:upper()] end end
		lines[#lines + 1] = { text = Grey(#shown > 0 and L.TREASURY_ARMY_SEES:format(table.concat(shown, ", ")) or L.TREASURY_ARMY_SEES_NOTHING) }
	end
	return lines
end

function Treasury.Build()
	local role = Treasury.Role()
	if Treasury.mode == "book" and not Treasury.MaySee("book") then Treasury.mode = "summary" end
	local lines = Treasury.mode == "book" and BookLines(role) or SummaryLines(role)
	local detail = role == "treasurer" and L.TREASURY_DETAIL_TREASURER or role == "king" and L.TREASURY_DETAIL_KING or L.TREASURY_DETAIL_MEMBER
	return lines, L.TAB_TREASURY, detail
end

-- For Discord.
function Treasury.DiscordText()
	local out = { ("**%s**"):format(L.TREASURY_TITLE) }
	local balance, week, donors, rank
	if Treasury.IsTreasurer() then
		local t = Treasury.Totals()
		balance, week, donors, rank = Treasury.Balance(), t.weekIn, #t.givers, t.ranking
	else
		local r = Treasury.Report()
		if not r then return "" end
		balance, week, donors, rank = r.balance, r.week, r.donors, r.rank
	end
	if Treasury.MaySee("balance") then
		out[#out + 1] = L.TREASURY_BALANCE .. ": " .. Plain(balance)
		out[#out + 1] = L.TREASURY_WEEK:format(donors) .. ": +" .. Plain(week)
	end
	if Treasury.MaySee("ranking") then
		for i = 1, math.min(Treasury.RANK_SENT, #rank) do out[#out + 1] = ("%d. %s - %s"):format(i, rank[i].name, Plain(rank[i].money)) end
	end
	return table.concat(out, "\n")
end

-- The King's Throne Room: the treasury as the Treasurer last sent it, a click from its tab.
function Treasury.ThroneLines()
	local Line, INK, TITLE = ns.King.Line, ns.King.INK, ns.King.TITLE
	local lines = { Line(L.TREASURY_TITLE, TITLE) }
	local open = function() if ns.UI and ns.UI.SelectTab then ns.UI.SelectTab("treasury") end end
	local r = Treasury.Report()
	if r then
		lines[#lines + 1] = Line(L.TREASURY_BALANCE .. ": " .. Treasury.Coins(r.balance), INK)
		lines[#lines + 1] = Line(L.TREASURY_WEEK:format(r.donors) .. ": +" .. Treasury.Coins(r.week), INK)
		lines[#lines + 1] = Line(L.TREASURY_AS_OF:format(ns.TREASURER, ns.Ago(r.t)), INK)
	else
		ns.King.Para(lines, L.TREASURY_WAIT:format(ns.TREASURER), INK)
	end
	lines[#lines].gapAfter = true
	lines[#lines + 1] = Line("> " .. L.TREASURY_OPEN, INK, { onClick = open })
	return lines
end

-- Next to the soldiers on top of the window (the Throne and the Treasury tabs): the treasury's
-- balance, for the Treasurer, the King, and the army when the King shows it.
function Treasury.HeaderText()
	local copper
	if Treasury.IsTreasurer() then copper = Treasury.Balance()
	elseif IsKingView() or Treasury.Shows("balance") then
		local r = Treasury.Report()
		copper = r and r.balance
	end
	if not copper then return nil end
	return "|TInterface\\MoneyFrame\\UI-GoldIcon:0|t " .. Treasury.GoldText(copper)
end

-- Under the Treasurer in the Realm, for everyone, when the King shows the balance.
function Treasury.RealmText()
	if not Treasury.Shows("balance") then return nil end
	if CanSend() then return L.TREASURY_REALM:format(Treasury.GoldText(Treasury.Balance()), ns.Ago(ns.Now())) end
	local r = Treasury.Report()
	if not r then return nil end
	return L.TREASURY_REALM:format(Treasury.GoldText(r.balance), ns.Ago(r.t))
end

StaticPopupDialogs["OLYMPUS_TREASURY_OPENING"] = {
	text = L.TREASURY_OPENING_PROMPT,
	button1 = OKAY or "OK",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 200,
	maxLetters = 24,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then eb:SetText(""); eb:SetFocus() end
	end,
	OnAccept = function(self)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("treasury opening", Treasury.SetOpening, eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		ns.SafeCall("treasury opening", Treasury.SetOpening, self:GetText())
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- Tests start from a clean state.
function Treasury.Reset()
	trade, mailOut, report, lastShare, sharePending, lastFlagsSent = nil, nil, nil, -math.huge, false, -math.huge
	wipe(taken)
	Treasury.mode = "summary"
	if ns.rdb then ns.rdb.treasuryReport = nil end
end
