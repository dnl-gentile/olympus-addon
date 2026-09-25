local ADDON, ns = ...
local L = ns.L

-- The Treasury of Olympus, kept by the Treasurer (ns.TREASURER of the guild OLYMPUS, see
-- ns.IsTreasurer). His client keeps the book: gold he receives by trade or mail is a donation,
-- gold he gives by trade or mail a payment, and his character's gold is the treasury. When he
-- shares it (a button, off until he turns it on), his addon sends the balance, the week's
-- donations and the most generous on the channel every few minutes, and every client checks
-- it comes from the Treasurer himself. The King sees it on his Treasury tab and next to the
-- soldiers on the Throne; everyone sees the balance under the Treasurer in the Realm.
--   T7~<guild>~<balance>~<today in>~<week in>~<donors this week>~<Name:copper,...>  (top 5, copper)
--   T7~<guild>~off                                                                  (not shared)
-- The auction house's and the game's mail is no donation.

local Treasury = {}
ns.Treasury = Treasury

Treasury.MAX = 500           -- lines kept in the book (the sums are kept apart: Days)
Treasury.DAYS_KEPT = 8       -- days of sums kept (today and the week)
Treasury.SHARE_EVERY = 300   -- the Treasurer's client repeats the report for late logins
Treasury.SHARE_GAP = 60      -- and sends a change of balance once a minute at most
Treasury.REPORT_KEPT = 2 * 3600  -- a report not repeated this long is dropped
Treasury.MAX_COPPER = 2147483647

local trade                  -- the trade window open: { name, got, gave }
local mailOut                -- a mail with gold on its way: { to, money }
local report                 -- the Treasurer's last report: { balance, today, week, donors, top, t, from }
local lastShare = -math.huge

local function Grey(s) return "|cff9d9d9d" .. s .. "|r" end
local function Gold(s) return "|cffffd200" .. s .. "|r" end
local function Green(s) return "|cff40ff40" .. s .. "|r" end
local function Red(s) return "|cffff6060" .. s .. "|r" end

local function Book()
	ns.rdb.treasury = ns.rdb.treasury or {}
	return ns.rdb.treasury
end
-- The sums, whatever the book keeps: all time, and per day (in, out, and each giver's).
local function Sums()
	local s = ns.rdb.treasurySums
	if type(s) ~= "table" then
		s = { allIn = 0, allOut = 0, days = {} }
		ns.rdb.treasurySums = s
	end
	return s
end
local function DayKey(t) return date and date("%Y-%m-%d", t) or tostring(math.floor(t / 86400)) end

-- 12g 30s 5c, with the coin icons when the client has them.
function Treasury.Coins(copper)
	copper = math.floor(tonumber(copper) or 0)
	if GetCoinTextureString then
		local ok, s = pcall(GetCoinTextureString, copper)
		if ok and s then return s end
	end
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 then parts[#parts + 1] = s .. "s" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
	return table.concat(parts, " ")
end
-- Gold alone, for the big numbers: "12,345g".
function Treasury.GoldText(copper)
	return ns.FormatNumber(math.floor((tonumber(copper) or 0) / 10000)) .. "g"
end
-- For Discord: plain text.
local function Plain(copper)
	local g, s = math.floor(copper / 10000), math.floor(copper / 100) % 100
	return g > 0 and ("%sg %ds"):format(ns.FormatNumber(g), s) or ("%ds %dc"):format(s, copper % 100)
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
-- The King sees it where a Treasurer can be (Forever's Alliance <Olympus>), or once a report
-- came; the author's view always.
function Treasury.Visible()
	if Treasury.IsTreasurer() or ns.King.Preview() then return true end
	return ns.King.IsKing() and (ns.splitNames and ns.faction ~= "Horde" or Treasury.Report() ~= nil)
end

function Treasury.SetDevView(on)
	ns.db.devTreasurerView = on and true or nil
	ns.Print(on and L.DEV_TREASURER_VIEW_NOW_ON or L.DEV_TREASURER_VIEW_NOW_OFF)
	ns.Fire("DATA_CHANGED")
end

---------------------------------------------------------------------------
-- The book (the Treasurer's client)
---------------------------------------------------------------------------

-- out: a payment (gold given). quiet: in the book without a chat line.
function Treasury.Record(name, copper, how, out, quiet)
	copper = math.floor(tonumber(copper) or 0)
	if copper <= 0 or type(name) ~= "string" or name == "" then return end
	local book = Book()
	local who = ns.DisplayName(ns.Normal(name)) or name
	local now = ns.Now()
	book[#book + 1] = { name = who, money = copper, how = how, t = now, out = out or nil }
	while #book > Treasury.MAX do table.remove(book, 1) end
	local sums = Sums()
	local key = DayKey(now)
	local day = sums.days[key] or { inn = 0, out = 0, by = {} }
	sums.days[key] = day
	if out then
		sums.allOut, day.out = sums.allOut + copper, day.out + copper
	else
		sums.allIn, day.inn = sums.allIn + copper, day.inn + copper
		day.by[who] = (day.by[who] or 0) + copper
	end
	-- Only the last days' sums are kept.
	local oldest = DayKey(now - Treasury.DAYS_KEPT * 86400)
	for k in pairs(sums.days) do if k < oldest then sums.days[k] = nil end end
	-- The King sees it soon (once a minute at most).
	Treasury.Share()
	if not quiet then
		ns.Print((out and L.TREASURY_PAID or L.TREASURY_DONATION):format(who, Treasury.Coins(copper)))
		if not out then ns.PlayAlert("soft") end
	end
	ns.Fire("TREASURY_CHANGED")
end

-- Trades: what each side put in, as the window last showed it (read again once complete, it
-- can say 0), counted when the game says the trade is complete.
function Treasury.TradeMoney()
	if not trade then return end
	if GetTargetTradeMoney then trade.got = tonumber(GetTargetTradeMoney()) or trade.got end
	if GetPlayerTradeMoney then trade.gave = tonumber(GetPlayerTradeMoney()) or trade.gave end
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
	if done.got > 0 then Treasury.Record(done.name, done.got, "trade") end
	if done.gave > 0 then Treasury.Record(done.name, done.gave, "trade", true) end
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

-- A donation by mail is counted when the Treasurer takes its gold (the money button, or
-- a mail addon's "open all": TakeInboxMoney, AutoLootMailItem), read from the mail just
-- before the game empties it. Two clicks on the same mail before the server answers count
-- once.
local taken = {}   -- [mail] = when its gold was taken (a few seconds)
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
-- week, most generous first.
function Treasury.Totals()
	local now = ns.Now()
	local sums = Sums()
	local t = { todayIn = 0, todayOut = 0, weekIn = 0, weekOut = 0, allIn = sums.allIn, allOut = sums.allOut, givers = {} }
	local today = DayKey(now)
	local by = {}
	for back = 0, 6 do
		local day = sums.days[DayKey(now - back * 86400)]
		if day then
			t.weekIn, t.weekOut = t.weekIn + day.inn, t.weekOut + day.out
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
	local d = sums.days[today]
	if d then t.todayIn, t.todayOut = d.inn, d.out end
	table.sort(t.givers, function(a, b)
		if a.money ~= b.money then return a.money > b.money end
		return a.name < b.name
	end)
	return t
end

function Treasury.Balance()
	return GetMoney and tonumber(GetMoney()) or 0
end

---------------------------------------------------------------------------
-- Sharing: the Treasurer's report, and everyone else's copy of it
---------------------------------------------------------------------------

function Treasury.Sharing() return ns.db.treasuryShare == true end

-- Only the real Treasurer's client sends (never the author's view).
local function CanSend() return ns.IsMember() and ns.IsTreasurer(ns.me, GetGuildInfo("player")) end

local sharePending = false
function Treasury.Share(force)
	if not CanSend() or not Treasury.Sharing() then return end
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
	local t = Treasury.Totals()
	local top, len = {}, 0
	for i = 1, math.min(5, #t.givers) do
		local g = t.givers[i]
		local part = ("%s:%d"):format(g.name:gsub("[~:,|]", ""), g.money)
		if len + #part > 110 then break end
		top[#top + 1] = part
		len = len + #part + 1
	end
	ns.Comm.Send("CHANNEL", ("T7~%s~%d~%d~%d~%d~%s"):format(GetGuildInfo("player") or "", math.min(Treasury.Balance(), Treasury.MAX_COPPER),
		math.min(t.todayIn, Treasury.MAX_COPPER), math.min(t.weekIn, Treasury.MAX_COPPER), #t.givers, table.concat(top, ",")), "treasury")
end

function Treasury.SetSharing(on)
	if not CanSend() and not Treasury.DevView() then return ns.Print(L.TREASURY_ONLY) end
	ns.db.treasuryShare = on and true or nil
	ns.Print(on and L.TREASURY_SHARE_ON or L.TREASURY_SHARE_OFF)
	if on then
		Treasury.Share(true)
	elseif CanSend() then
		ns.Comm.Send("CHANNEL", ("T7~%s~off"):format(GetGuildInfo("player") or ""), "treasury")
	end
	ns.Fire("TREASURY_CHANGED")
end

local function Num(s) return math.min(math.max(tonumber(s) or 0, 0), Treasury.MAX_COPPER) end

function Treasury.HandleReport(dist, sender, text)
	if dist ~= "CHANNEL" then return end
	local guild, rest = text:match("^T7~([^~]*)~(.*)$")
	if not guild then return end
	-- The Treasurer himself: that name, in the guild OLYMPUS, confirmed there by our roster or
	-- the census.
	if not ns.IsTreasurer(sender, guild) then return end
	if not (ns.Roster.RankOf(sender) or ns.Data.KnownRank(sender, guild, true)) then return end
	if rest == "off" then
		report, ns.rdb.treasuryReport = nil, nil
		return ns.Fire("TREASURY_CHANGED")
	end
	local balance, today, week, donors, top = rest:match("^(%d+)~(%d+)~(%d+)~(%d+)~(.*)$")
	if not balance then return end
	local list = {}
	for name, copper in top:gmatch("([^,:]+):(%d+)") do
		local clean = ns.King.CleanName(name)
		if clean and #list < 5 then list[#list + 1] = { name = clean, money = Num(copper) } end
	end
	report = { balance = Num(balance), today = Num(today), week = Num(week), donors = math.min(tonumber(donors) or 0, 9999),
		top = list, t = ns.Now(), from = ns.FullName(sender) }
	-- Kept across a /reload, as long as a report lasts.
	ns.rdb.treasuryReport = report
	ns.Fire("TREASURY_CHANGED")
end
ns.Comm.Handle("T7", function(...) Treasury.HandleReport(...) end)

function Treasury.Report()
	if not report and type(ns.rdb and ns.rdb.treasuryReport) == "table" then report = ns.rdb.treasuryReport end
	if report and ns.Now() - (tonumber(report.t) or 0) > Treasury.REPORT_KEPT then
		report = nil
		if ns.rdb then ns.rdb.treasuryReport = nil end
	end
	return report
end

ns.On("LOGIN", function()
	ns.RegisterEvent("TRADE_SHOW", function() ns.SafeCall("treasury trade", Treasury.TradeShow) end)
	ns.RegisterEvent("TRADE_MONEY_CHANGED", function() ns.SafeCall("treasury trade", Treasury.TradeMoney) end)
	ns.RegisterEvent("TRADE_ACCEPT_UPDATE", function() ns.SafeCall("treasury trade", Treasury.TradeMoney) end)
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
	-- The Treasurer's balance changed: the report goes out (once a minute at most), and it is
	-- repeated for late logins.
	ns.RegisterEvent("PLAYER_MONEY", function()
		ns.SafeCall("treasury share", Treasury.Share)
		if Treasury.IsTreasurer() then ns.Fire("TREASURY_CHANGED") end
	end)
	ns.Every(Treasury.SHARE_EVERY, "treasury share", function() Treasury.Share(true) end)
	ns.After(30, "treasury share", function() Treasury.Share(true) end)
end)

---------------------------------------------------------------------------
-- What the tabs show
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

local function Ledger(lines)
	local book = Book()
	lines[#lines + 1] = { header = true, text = L.TREASURY_LATEST }
	if #book == 0 then lines[#lines + 1] = { text = Grey(L.TREASURY_NONE) } end
	for i = #book, math.max(1, #book - 19), -1 do
		local e = book[i]
		local how = e.how == "mail" and L.TREASURY_MAIL or L.TREASURY_TRADE
		lines[#lines + 1] = {
			indent = 1,
			text = (e.out and L.TREASURY_TO or L.TREASURY_FROM):format(e.name) .. "  " .. Grey("(" .. how .. ", " .. ns.Ago(e.t) .. ")"),
			right = e.out and Red("-" .. Treasury.Coins(e.money)) or Green("+" .. Treasury.Coins(e.money)),
		}
	end
end

-- The Treasury tab: the Treasurer's book, or (the King) the Treasurer's report.
function Treasury.Build()
	local lines = { { header = true, text = L.TREASURY_TITLE } }
	if Treasury.IsTreasurer() then
		Para(lines, L.TREASURY_HOW)
		lines[#lines].gapAfter = true
		local t = Treasury.Totals()
		lines[#lines + 1] = { text = Gold(L.TREASURY_BALANCE), right = Treasury.Coins(Treasury.Balance()) }
		lines[#lines + 1] = { text = L.TREASURY_TODAY, right = Green("+" .. Treasury.Coins(t.todayIn)) .. "  " .. Red("-" .. Treasury.Coins(t.todayOut)) }
		lines[#lines + 1] = { text = L.TREASURY_WEEK:format(#t.givers), right = Green("+" .. Treasury.Coins(t.weekIn)) .. "  " .. Red("-" .. Treasury.Coins(t.weekOut)) }
		lines[#lines + 1] = { text = L.TREASURY_ALL, right = Green("+" .. Treasury.Coins(t.allIn)) .. "  " .. Red("-" .. Treasury.Coins(t.allOut)) }
		lines[#lines + 1] = {
			text = Treasury.Sharing() and Green(L.TREASURY_SHARED) or Grey(L.TREASURY_NOT_SHARED), gapAfter = true,
			onClick = function() Treasury.SetSharing(not Treasury.Sharing()) end,
			tooltip = function(tt) tt:AddLine(L.TREASURY_SHARE_TIP, 1, 1, 1, true) end,
		}
		lines[#lines + 1] = { header = true, text = L.TREASURY_GIVERS }
		if #t.givers == 0 then lines[#lines + 1] = { text = Grey(L.TREASURY_NONE) } end
		for i = 1, math.min(10, #t.givers) do
			lines[#lines + 1] = { indent = 1, text = ("%d. %s"):format(i, t.givers[i].name), right = Treasury.Coins(t.givers[i].money) }
		end
		lines[#lines].gapAfter = true
		Ledger(lines)
		return lines, L.TAB_TREASURY, L.TREASURY_DETAIL_TREASURER
	end
	local r = Treasury.Report()
	if not r then
		Para(lines, L.TREASURY_WAIT:format(ns.TREASURER))
		return lines, L.TAB_TREASURY, L.TREASURY_DETAIL_KING
	end
	lines[#lines + 1] = { text = Gold(L.TREASURY_BALANCE), right = Treasury.Coins(r.balance) }
	lines[#lines + 1] = { text = L.TREASURY_TODAY, right = Green("+" .. Treasury.Coins(r.today)) }
	lines[#lines + 1] = { text = L.TREASURY_WEEK:format(r.donors), right = Green("+" .. Treasury.Coins(r.week)) }
	lines[#lines + 1] = { text = Grey(L.TREASURY_AS_OF:format(ns.TREASURER, ns.Ago(r.t))), gapAfter = true }
	lines[#lines + 1] = { header = true, text = L.TREASURY_GIVERS }
	if #r.top == 0 then lines[#lines + 1] = { text = Grey(L.TREASURY_NONE) } end
	for i, g in ipairs(r.top) do
		lines[#lines + 1] = { indent = 1, text = ("%d. %s"):format(i, g.name), right = Treasury.Coins(g.money) }
	end
	return lines, L.TAB_TREASURY, L.TREASURY_DETAIL_KING
end

-- For Discord.
function Treasury.DiscordText()
	local out = { ("**%s**"):format(L.TREASURY_TITLE) }
	if Treasury.IsTreasurer() then
		local t = Treasury.Totals()
		out[#out + 1] = L.TREASURY_BALANCE .. ": " .. Plain(Treasury.Balance())
		out[#out + 1] = L.TREASURY_WEEK:format(#t.givers) .. ": +" .. Plain(t.weekIn)
		for i = 1, math.min(10, #t.givers) do out[#out + 1] = ("%d. %s - %s"):format(i, t.givers[i].name, Plain(t.givers[i].money)) end
	else
		local r = Treasury.Report()
		if not r then return "" end
		out[#out + 1] = L.TREASURY_BALANCE .. ": " .. Plain(r.balance)
		out[#out + 1] = L.TREASURY_WEEK:format(r.donors) .. ": +" .. Plain(r.week)
		for i, g in ipairs(r.top) do out[#out + 1] = ("%d. %s - %s"):format(i, g.name, Plain(g.money)) end
	end
	return table.concat(out, "\n")
end

-- The King's Throne Room: the treasury as the Treasurer last shared it, a click from its tab.
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

-- Next to the soldiers on top of the window (the Throne and the Treasury tabs): the
-- Treasurer's balance on his own client, the one he shared on the King's.
function Treasury.HeaderText()
	local copper
	if Treasury.IsTreasurer() then copper = Treasury.Balance()
	elseif ns.King.IsKing() or ns.King.Preview() then
		local r = Treasury.Report()
		copper = r and r.balance
	end
	if not copper then return nil end
	return "|TInterface\\MoneyFrame\\UI-GoldIcon:0|t " .. Treasury.GoldText(copper)
end

-- Under the Treasurer in the Realm, for everyone: the balance he shares.
function Treasury.RealmText()
	-- The Treasurer's own message never comes back to him: his copy is his balance.
	if CanSend() and Treasury.Sharing() then return L.TREASURY_REALM:format(Treasury.GoldText(Treasury.Balance()), ns.Ago(ns.Now())) end
	local r = Treasury.Report()
	if not r then return nil end
	return L.TREASURY_REALM:format(Treasury.GoldText(r.balance), ns.Ago(r.t))
end

-- Tests start from a clean state.
function Treasury.Reset()
	trade, mailOut, report, lastShare, sharePending = nil, nil, nil, -math.huge, false
	wipe(taken)
	if ns.rdb then ns.rdb.treasuryReport = nil end
end
