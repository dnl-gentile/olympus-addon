local ADDON, ns = ...
local L = ns.L

-- The dues (1.1, Fern's requests #36 and #37): one fixed amount of gold a week that members
-- send the Treasurer, counted from the treasury's own books (Treasury.lua) and never public.
-- - Every line of a keeper's book is stamped with its week (from one weekly reset to the next,
--   the client's own), and each book keeps every giver's sum per week (the last WEEKS_KEPT
--   weeks), kept by its own keeper's addon like the rest of the book.
-- - A gift's guild: the one the game shows on the other side of a trade, the Treasurer's own
--   roster for his guild, or the note a mail carries ("Olympus fund 2026-09-29 <Olympus II>", the
--   payer's own word: it only places the payer's own gold); otherwise "guild not known".
-- - The King sets one fixed amount, once (1 gold until he does): his word, or his Steward's in
--   his name, dated like the treasury's switches (the newest wins, the King's on the same
--   second). Their clients repeat it, and so does the Treasurer's, for members who never meet
--   them online. Never a share of anyone's gold or loot.
-- - Who sees what: the King, his Steward and the Treasurer see every guild (its members in the
--   census, how many paid this week, the gold in, the percentage) and, a click away, a guild's
--   players; each guild's Captains (and its Lord) see their own guild alone: each member's name,
--   last payment, gold this week, above or below the amount. The army's Treasury tab keeps the
--   King's three switches (the balance, the ranking, the book) and nothing of this.
-- - None of it goes on the Olympus channel (Fern's #36: every client on it receives the bytes,
--   and a switch that only hides them would make it a public list of who is short). The
--   Treasurer's addon works it out from his account's books and whispers it to whoever asks and
--   may see it: the King or his Steward (every guild), a guild's Captain (his own guild, his rank
--   by the Treasurer's roster or the census). Only the amount, which is the same for everyone,
--   is public.
-- - Nothing here ever turns anyone off (Fern's rule, #33): no census report, chat line, decree,
--   channel or feature of the addon waits on paying, for a guild or a player; a guild's Captains
--   may only remove members one click at a time, as the game's Guild window does (#34). No
--   access switch of the moderators' (1.1) may take anything from here.
--   T1~Y~<id>~<guild>~<copper>~<time>            the King's amount (his, or his Steward's; King.lua)
--   FK~<guild>~<copper>~<time>                   the Treasurer's client repeats it, with its time
--   FQ~<week>~<Guild, or * for every guild>      an ask to the Treasurer (a whisper)
--   FS~<id>~<week>~<copper>~<i>~<n>~<Guild:paid:copper:payers;...>   his answer, every guild (whispers, the King's and his Steward's)
--   FA~<id>~<week>~<copper>~<since>~<cut 0|1>~<Guild>~<i>~<n>~<Name:copper:hours,...,#code:copper:hours,...>
--                                                his answer, one guild's players (whispers)
--   (copper, since and hours in base 36; hours since each one's last payment. "#code": a player
--   who paid this week with no guild on it, by five letters of his name's hash, for the asker's
--   roster to find.)
-- Versions before 1.1 have no handler for F? messages and drop them; a Steward's T1~Y is logged
-- there as ignored.

local Dues = {}
ns.Dues = Dues

Dues.WEEK = 7 * 86400
Dues.RESET_US = 486000       -- Tuesday 15:00 UTC (the US realms' reset) where the client can't say
Dues.AMOUNT = 10000          -- 1 gold a week, until the King sets his amount
Dues.MAX_AMOUNT = 10000000   -- 1000 gold at most
Dues.WEEKS_KEPT = 5          -- weeks of each giver's sums a book keeps (this one and the 4 before)
Dues.AMOUNT_EVERY = 300      -- the King's, his Steward's and the Treasurer's clients repeat the amount
Dues.WORD_ANSWER = 30        -- an older amount heard: answered with the newer one this often at most
Dues.ASK_EVERY = 300         -- a client asks the Treasurer for one list this often at most
Dues.ANSWER_GAP = 300        -- the Treasurer's client answers one asker's list this often at most
Dues.HEARD_FOR = 600         -- the Treasurer counts as online this long after his addon was last heard
Dues.PACE = 1.5              -- seconds between two whispers of an answer (the channel's queue sends one each 1.2)
Dues.ROOM = 250              -- bytes in one whisper
Dues.MAX_PIECES = 60         -- whispers of one guild's named players at most
Dues.MAX_CODE_PIECES = 15    -- ...and of its players with no guild on their payment
Dues.MAX_OUTBOX = 300        -- whispers waiting on the Treasurer's client at most
Dues.PAGE = 25               -- rows shown, 25 more a click

Dues.shown = nil             -- the guild opened on the dues page (nil: the page's own list)

local MAX_COPPER = 2147483647
local anchor                 -- the week's start, seconds into a week of the server's clock
local lastAmountSent, lastRepeat, lastOlder = -math.huge, -math.huge, -math.huge
local heardAt, heardName = -math.huge, nil   -- the Treasurer's addon as last heard (FK, FS, FA)
local asked = {}             -- [what] = when this client last asked for it
local answered = {}          -- the Treasurer's client: [asker|what] = when it last answered
local outbox = {}            -- the Treasurer's client: whispers waiting their turn { to, msg, key }
local answers = {}           -- [guild lower] = one guild's list as it came (FA)
local summary                -- every guild, as it came (FS)
local shownRows = Dues.PAGE

local function Grey(s) return "|cff9d9d9d" .. s .. "|r" end
local function Gold(s) return "|cffffd200" .. s .. "|r" end
local function Green(s) return "|cff40ff40" .. s .. "|r" end
local function Red(s) return "|cffff6060" .. s .. "|r" end
local function Coins(copper) return ns.Treasury.Coins(copper) end
local function GoldText(copper) return ns.Treasury.GoldText(copper) end

-- The server's clock, the same on every client.
local function Clock() return GetServerTime and GetServerTime() or ns.Now() end

local function B36(n) return ns.Codec.Base36(math.max(0, math.floor(tonumber(n) or 0))) end
local function N36(s)
	if type(s) ~= "string" or #s > 8 or not s:find("^[0-9a-z]+$") then return nil end
	return tonumber(s, 36)
end

-- A paragraph in short rows, grey unless said.
local function Para(lines, text, color)
	color = color or Grey
	local row = ""
	for word in tostring(text or ""):gmatch("%S+") do
		if row ~= "" and #row + 1 + #word > 58 then
			lines[#lines + 1] = { text = color(row) }
			row = word
		else
			row = row == "" and word or (row .. " " .. word)
		end
	end
	if row ~= "" then lines[#lines + 1] = { text = color(row) } end
	return lines
end

---------------------------------------------------------------------------
-- The week
---------------------------------------------------------------------------

-- Where the week starts: the client's own weekly reset (the server's clock plus the time left
-- to it, rounded to the hour it falls on: every client of a region works out the same one), or
-- the US realms' where the client can't say.
function Dues.Anchor()
	if anchor then return anchor end
	local f = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset
	local ok, left = false, nil
	if f then ok, left = pcall(f) end
	left = ok and tonumber(left) or nil
	if left and left > 0 and left <= Dues.WEEK then
		anchor = (math.floor((Clock() + left) / 3600 + 0.5) * 3600) % Dues.WEEK
	else
		anchor = Dues.RESET_US
	end
	return anchor
end
function Dues.WeekOf(t) return math.floor(((tonumber(t) or 0) - Dues.Anchor()) / Dues.WEEK) end
function Dues.Week() return Dues.WeekOf(Clock()) end
function Dues.WeekStart(week) return Dues.Anchor() + week * Dues.WEEK end
-- The day a week starts on, as the note writes it (UTC): "2026-09-29".
function Dues.DateLabel(week)
	local ok, s = pcall(date, "!%Y-%m-%d", Dues.WeekStart(week))
	return ok and s or tostring(week)
end

-- A player however a name reaches us (a book's "Name", a sender's "Name-Realm", a roster's):
-- lower case, no realm (Forever's names are one across a realm group).
function Dues.Key(name)
	if type(name) ~= "string" or name == "" then return nil end
	local short = ns.ShortName(ns.Normal(name))
	return short ~= "" and short:lower() or nil
end
-- Five letters of a name's hash: a player who paid with no guild on it, found by the asker's
-- roster. Two names can share one: someone then shows as paid, never someone who paid as not.
function Dues.Code(key) return type(key) == "string" and ns.Comm.Hash36(key):sub(-5) or nil end

-- The mail's note, as the payer's click writes it (#35): "Olympus fund <week's first day> <Guild>".
function Dues.Note(week, guild)
	local note = "Olympus fund " .. Dues.DateLabel(week or Dues.Week())
	if type(guild) == "string" and guild ~= "" then note = note .. " <" .. guild .. ">" end
	return note
end
-- A mail's subject read as such a note: its week (this one or the one before, else nil) and its
-- guild (an Olympus guild's name, else nil). Anything else: nil.
function Dues.ReadNote(subject, week)
	if type(subject) ~= "string" then return nil end
	local day, rest = subject:match("^%s*Olympus fund (%d%d%d%d%-%d%d%-%d%d)(.*)$")
	if not day then return nil end
	week = week or Dues.Week()
	local wk
	for _, w in ipairs({ week, week - 1 }) do
		if Dues.DateLabel(w) == day then wk = w end
	end
	local guild = rest:match("^%s*<([^>]+)>%s*$")
	return wk, guild and ns.King.CleanGuild(guild) or nil
end

---------------------------------------------------------------------------
-- Who
---------------------------------------------------------------------------

-- The treasury is <Olympus>'s, on the Treasurer's realm group (WoW: Forever's, whose names have
-- a surname: ns.splitNames, as the King's view of the treasury, Treasury.Visible), on the Alliance.
function Dues.Available()
	if ns.faction == "Horde" or not ns.splitNames or not ns.IsMember() then return false end
	return ns.GroupOf(ns.realm or "") == ns.GroupOf(ns.TREASURER_REALM)
end
-- The King, his Steward, the author's Asmon's view: the amount is theirs to set.
local function KingView() return ns.King.IsKing() or ns.King.IsSteward() or ns.King.Preview() end
Dues.KingView = KingView
-- The Treasurer himself (or the author's Treasurer's view): his books are the dues' ledger.
function Dues.IsTreasurer() return ns.Treasury.IsTreasurer() == true end
-- Who sees the dues: the King and his Steward, the Treasurer, and each guild's Captains and Lord.
function Dues.Sees()
	if not Dues.Available() then return false end
	return KingView() or Dues.IsTreasurer() or ns.Roster.IsOfficer() or false
end
-- Every guild's, or only our own.
local function SeesAll() return KingView() or Dues.IsTreasurer() end

-- A sender the King's word comes from (by name: the server sets it), or his Steward.
local function KingOrSteward(name) return ns.IsKingCharacter(name) or ns.King.IsStewardName(name) end
-- A Captain (or the Lord) of `guild`: by our own roster when it is our guild, else by the census.
local function CaptainOf(name, guild)
	local own = ns.IsMember() and GetGuildInfo("player")
	local rank
	if own and own:lower() == guild:lower() then rank = ns.Roster.RankOf(name) else rank = ns.Data.KnownRank(name, guild) end
	return rank ~= nil and rank <= ns.CAPTAIN_RANK
end

---------------------------------------------------------------------------
-- The King's amount
---------------------------------------------------------------------------

local function Word()
	local w
	if ns.King.Preview() then w = ns.db and ns.db.previewDuesAmount else w = ns.rdb and ns.rdb.duesAmount end
	return type(w) == "table" and tonumber(w.copper) and w or nil
end
-- The amount a week, in copper: the King's, 1 gold until he sets one.
function Dues.Amount()
	local w = Word()
	return w and math.floor(w.copper) or Dues.AMOUNT
end

-- The King's client and his Steward's repeat his word (nothing before one of them gives it).
function Dues.SendAmount(force)
	local w = ns.rdb and ns.rdb.duesAmount
	if not ns.King.SetsLists() or type(w) ~= "table" or not tonumber(w.at) or not tonumber(w.copper) then return false end
	local now = ns.Now()
	if not force and now - lastAmountSent < Dues.AMOUNT_EVERY then return false end
	lastAmountSent = now
	ns.Comm.Send("CHANNEL", ("T1~Y~%d~%s~%d~%d"):format(ns.King.NewId(), GetGuildInfo("player") or "", w.copper, w.at), "duesamount")
	return true
end

-- The King (or his Steward) sets it: one amount for everyone, dated (the author's Asmon's view:
-- its own, on his screen alone).
function Dues.SetAmount(input)
	if not KingView() then return ns.Print(L.THRONE_ONLY_KING) end
	local copper = ns.Treasury.ParseGold(input)
	if not copper or copper < 1 or copper > Dues.MAX_AMOUNT then return ns.Print(L.DUES_AMOUNT_USAGE:format(Coins(Dues.MAX_AMOUNT))) end
	local prev = Word()
	local w = { copper = copper, at = math.max(math.floor(Clock()), (prev and tonumber(prev.at) or 0) + 1), from = ns.me, t = ns.Now() }
	ns.Print(L.DUES_AMOUNT_SET:format(Coins(copper)))
	if ns.King.Preview() then
		ns.db.previewDuesAmount = w
		ns.Print(L.THRONE_PREVIEW_NOTE)
	else
		ns.rdb.duesAmount = w
		Dues.SendAmount(true)
	end
	ns.Fire("TREASURY_CHANGED")
	return true
end

-- His word (or his Steward's, or the Treasurer's copy of it): taken when newer than ours (a time
-- ahead of the server's clock by King.DATE_AHEAD at most), the King's own on the same second.
-- An older one heard on the King's or his Steward's client is answered with the newer one.
function Dues.TakeAmount(copper, at, sender)
	copper, at = tonumber(copper), tonumber(at)
	if not copper or not at or copper < 1 or copper > Dues.MAX_AMOUNT or copper % 1 ~= 0 then return false end
	if at > Clock() + ns.King.DATE_AHEAD then return false end
	local kept = ns.rdb.duesAmount
	if not ns.Treasury.Replaces(kept, at, sender) then
		if type(kept) == "table" and at < (tonumber(kept.at) or 0) and ns.King.SetsLists() and ns.Now() - lastOlder >= Dues.WORD_ANSWER then
			lastOlder = ns.Now()
			Dues.SendAmount(true)
		end
		return false
	end
	local was = type(kept) == "table" and tonumber(kept.copper) or nil
	ns.rdb.duesAmount = { copper = copper, at = at, from = ns.FullName(sender), t = ns.Now() }
	if was ~= copper then
		if ns.King.IsKing() and ns.King.IsStewardName(sender) then ns.Print(L.STEWARD_SET_DUES:format(ns.King.StewardLabel(sender), Coins(copper))) end
		ns.Fire("TREASURY_CHANGED")
	end
	return true
end
ns.King.Register("Y", function(sender, id, rest)
	local copper, at = tostring(rest or ""):match("^(%d+)~(%d+)$")
	if copper and #copper <= 10 and #at <= 12 then Dues.TakeAmount(copper, at, sender) end
end)

local function Heard(sender) heardAt, heardName = ns.Now(), ns.FullName(sender) end

-- The Treasurer's client repeats the King's word, with its time (members who never meet the King
-- online get it too).
function Dues.Repeat(force)
	local w = ns.rdb and ns.rdb.duesAmount
	if ns.faction == "Horde" or type(w) ~= "table" or not tonumber(w.at) or not tonumber(w.copper) then return false end
	if not (ns.IsMember() and ns.IsTreasurer(ns.me, GetGuildInfo("player"))) then return false end
	local now = ns.Now()
	if not force and now - lastRepeat < Dues.AMOUNT_EVERY then return false end
	lastRepeat = now
	ns.Comm.Send("CHANNEL", ("FK~%s~%d~%d"):format(GetGuildInfo("player") or "", w.copper, w.at), "duesrepeat")
	return true
end
function Dues.HandleRepeat(dist, sender, text)
	if dist ~= "CHANNEL" or type(text) ~= "string" or ns.faction == "Horde" then return end
	local guild, copper, at = text:match("^FK~([^~]*)~(%d+)~(%d+)$")
	if not guild or not ns.IsTreasurer(sender, guild) then return end
	Heard(sender)
	if #copper <= 10 and #at <= 12 then Dues.TakeAmount(copper, at, sender) end
end
ns.Comm.Handle("FK", function(...) Dues.HandleRepeat(...) end)

-- The Treasurer's addon online: heard in the last HEARD_FOR (his amount, an answer, his book).
-- Returns online, his name as the server wrote it, when he was last heard.
function Dues.TreasurerOnline()
	local last, name = heardAt, heardName
	local reports = ns.rdb and ns.rdb.treasuryReports
	if type(reports) == "table" then
		for from, r in pairs(reports) do
			if type(r) == "table" and not r.relayed and ns.Treasury.TreasurerPin(from) == 1 and (tonumber(r.t) or 0) > last then
				last, name = tonumber(r.t), from
			end
		end
	end
	return ns.Now() - last <= Dues.HEARD_FOR, name or ns.FullName(ns.TREASURER, ns.TREASURER_REALM), last
end

---------------------------------------------------------------------------
-- The books: each line's week, each giver's sum per week (Treasury.lua calls these)
---------------------------------------------------------------------------

-- A line as it goes in a book (Treasury.Record): its week (the server's clock; a mail's note's
-- week when it names this one or the one before), and a gift's guild: the game's word on the
-- other side of a trade, the keeper's roster for his own guild's members, else the mail's note.
function Dues.Stamp(e, name, o)
	if type(e) ~= "table" then return end
	o = type(o) == "table" and o or {}
	local week = Dues.Week()
	e.wk = week
	if e.out or e.item or e.kind == "transfer" or (tonumber(e.money) or 0) <= 0 then return end
	local noted, claimed = Dues.ReadNote(o.note, week)
	if noted then e.wk = noted end
	local guild, verified = ns.King.CleanGuild(o.guild), true
	if not guild and ns.IsMember() and ns.Roster.RankOf(ns.FullName(ns.Normal(name))) then guild = GetGuildInfo("player") end
	if not guild then guild, verified = claimed, false end
	if guild then e.guild, e.gv = guild, verified or nil end
end

-- A counted gift into its giver's sum for its week (copper < 0: out of it), while the week is
-- one of the WEEKS_KEPT; older weeks are dropped.
function Dues.WeekAdd(s, e, copper)
	if type(s) ~= "table" or type(e) ~= "table" or e.item or e.out or e.kind == "transfer" then return end
	copper = math.floor(tonumber(copper) or 0)
	local key = Dues.Key(e.name)
	if not key or copper == 0 then return end
	local now = Dues.Week()
	local wk = tonumber(e.wk) or Dues.WeekOf(e.t)
	if type(s.weeks) ~= "table" then s.weeks = {} end
	for w in pairs(s.weeks) do
		if type(w) ~= "number" or w < now - (Dues.WEEKS_KEPT - 1) then s.weeks[w] = nil end
	end
	if wk < now - (Dues.WEEKS_KEPT - 1) or wk > now + 1 then return end
	local week = s.weeks[wk]
	if not week then
		if copper < 0 then return end
		week = {}
		s.weeks[wk] = week
	end
	local p = week[key]
	if not p then
		if copper < 0 then return end
		p = { n = e.name, c = 0, t = 0 }
		week[key] = p
	end
	p.c = math.max(0, math.min(p.c + copper, MAX_COPPER))
	if copper > 0 then
		p.n = e.name
		if (tonumber(e.t) or 0) > p.t then p.t = tonumber(e.t) end
	end
	if e.guild and (e.gv or not p.gv) then p.g, p.gv = e.guild, e.gv or nil end
	if p.c <= 0 then week[key] = nil end
end

-- A book's sums from before 1.1: its weeks from the lines it still keeps.
function Dues.Backfill(s, lines)
	if type(s) ~= "table" then return end
	s.weeks = {}
	for _, e in ipairs(type(lines) == "table" and lines or {}) do
		if type(e) == "table" and not e.excluded then Dues.WeekAdd(s, e, e.money) end
	end
end

---------------------------------------------------------------------------
-- The ledger: the Treasurer's account's books (his own and his mail character's)
---------------------------------------------------------------------------

local function LedgerBooks()
	local out = {}
	if not ns.rdb then return out end
	ns.Treasury.Migrate()
	local books = ns.rdb.treasuryBooks
	local dev = ns.Treasury.DevView() and Dues.Key(ns.me)
	for _, b in pairs(type(books) == "table" and books or {}) do
		if type(b) == "table" and b.epoch == ns.Treasury.EPOCH and type(b.lines) == "table" and type(b.name) == "string"
			and (ns.Treasury.TreasurerPin(b.name) or (dev and Dues.Key(b.name) == dev)) then
			out[#out + 1] = b
		end
	end
	return out
end

-- A guild for a player: the server's word over a note's, the latest week's otherwise.
local function Better(p, wk, x)
	if not p.g then return false end
	if not x.g then return true end
	if p.gv and not x.gv then return true end
	if x.gv and not p.gv then return false end
	return wk >= (x.gw or -math.huge)
end

-- The week's ledger, from the Treasurer's account's books: { week, amount, since, players =
-- { [key] = { n, c = copper this week, last = last payment, g = guild, gv } }, guilds = { [guild
-- lower, "" for none] = { name, paid, copper, payers } } }.
function Dues.Ledger(week)
	week = week or Dues.Week()
	local amount = Dues.Amount()
	local players, since = {}, nil
	for _, b in ipairs(LedgerBooks()) do
		local opened = tonumber(b.openedAt or b.opened)
		if opened and (not since or opened < since) then since = opened end
		local s = ns.Treasury.SumsOf(b)
		for wk, list in pairs(type(s.weeks) == "table" and s.weeks or {}) do
			if type(wk) == "number" and wk <= week and wk > week - Dues.WEEKS_KEPT and type(list) == "table" then
				for key, p in pairs(list) do
					local x = players[key]
					if not x then
						x = { n = p.n, c = 0, last = 0 }
						players[key] = x
					end
					if wk == week then x.c = math.min(x.c + (tonumber(p.c) or 0), MAX_COPPER) end
					if (tonumber(p.t) or 0) > x.last then x.last, x.n = tonumber(p.t), p.n or x.n end
					if Better(p, wk, x) then x.g, x.gv, x.gw = p.g, p.gv, wk end
				end
			end
		end
	end
	-- The Treasurer's own guild's members, by his roster (the server's word).
	local own = ns.IsMember() and GetGuildInfo("player")
	if own then
		for _, x in pairs(players) do
			if ns.Roster.RankOf(ns.FullName(ns.Normal(x.n))) then x.g, x.gv = own, true end
		end
	end
	local guilds = {}
	for _, x in pairs(players) do
		if x.c > 0 then
			local gk = x.g and x.g:lower() or ""
			local row = guilds[gk]
			if not row then
				row = { name = x.g, paid = 0, copper = 0, payers = 0 }
				guilds[gk] = row
			end
			row.copper = math.min(row.copper + x.c, MAX_COPPER)
			row.payers = row.payers + 1
			if x.c >= amount then row.paid = row.paid + 1 end
		end
	end
	return { week = week, amount = amount, since = since, players = players, guilds = guilds, t = ns.Now(), complete = true }
end

-- A guild's members, as the census has them (ours from our roster), or nil.
function Dues.Members(guild)
	local g = type(guild) == "string" and ns.Data.Guild(guild)
	local n = g and tonumber(g.total)
	if (not n or n <= 0) and ns.IsMember() and type(guild) == "string" and guild:lower() == tostring(GetGuildInfo("player")):lower() then
		n = GetNumGuildMembers and tonumber((GetNumGuildMembers())) or nil
	end
	if not n or n <= 0 then return nil end
	return math.min(n, ns.Codec.GUILD_CAP)
end

---------------------------------------------------------------------------
-- The Treasurer's answers, by whisper to whoever may see them
---------------------------------------------------------------------------

-- His client answers: the Treasurer himself, sharing his book (his yes), on the Alliance.
function Dues.Answers()
	if ns.faction == "Horde" or not ns.IsMember() then return false end
	return ns.IsTreasurer(ns.me, GetGuildInfo("player")) and ns.Treasury.CanSend() == true
end

-- rows cut in pieces of one whisper each (head(i, n) is each one's start), `max` pieces at most:
-- the pieces, and the place in `rows` of the first row left out (nil: none).
local function Pieces(head, rows, sep, max)
	local room = Dues.ROOM - #head(999, 999)
	local pieces, cur, len = {}, {}, 0
	for i, r in ipairs(rows) do
		if #cur > 0 and len + #sep + #r > room then
			pieces[#pieces + 1] = table.concat(cur, sep)
			cur, len = {}, 0
			if max and #pieces >= max then return pieces, i end
		end
		len = len + (#cur > 0 and #sep or 0) + #r
		cur[#cur + 1] = r
	end
	if #cur > 0 then pieces[#pieces + 1] = table.concat(cur, sep) end
	return pieces, nil
end

-- Every guild: its players who paid this week, how many paid the amount, the gold in.
function Dues.SummaryMessages(led, id)
	local rows, list = {}, {}
	for key, row in pairs(led.guilds) do list[#list + 1] = { key = key, row = row } end
	table.sort(list, function(a, b)
		if a.row.copper ~= b.row.copper then return a.row.copper > b.row.copper end
		return a.key < b.key
	end)
	for _, x in ipairs(list) do
		rows[#rows + 1] = ("%s:%d:%s:%d"):format(x.key == "" and "?" or x.row.name, x.row.paid, B36(x.row.copper), x.row.payers)
	end
	local function Head(i, n) return ("FS~%d~%d~%s~%d~%d~"):format(id, led.week, B36(led.amount), i, n) end
	local pieces = Pieces(Head, rows, ";", 99)
	if #pieces == 0 then pieces[1] = "" end
	local out = {}
	for i, p in ipairs(pieces) do out[i] = Head(i, #pieces) .. p end
	return out
end

-- One guild's players: each one who paid in the weeks kept (his gold this week, the hours since
-- his last payment), and the players who paid this week with no guild on it, by code. A list cut
-- to MAX_PIECES says so when it left out anyone who paid this week.
function Dues.GuildMessages(led, guild, id)
	local want, now = guild:lower(), ns.Now()
	local named, coded = {}, {}
	for key, x in pairs(led.players) do
		if x.g and x.g:lower() == want then
			local name = ns.King.CleanName(x.n)
			if name then named[#named + 1] = { name = name, c = x.c, last = x.last } end
		elseif not x.g and x.c > 0 then
			coded[#coded + 1] = { code = Dues.Code(key), c = x.c, last = x.last }
		end
	end
	local function Order(a, b)
		if (a.c > 0) ~= (b.c > 0) then return a.c > 0 end
		if a.last ~= b.last then return a.last > b.last end
		return tostring(a.name or a.code) < tostring(b.name or b.code)
	end
	table.sort(named, Order)
	table.sort(coded, Order)
	local function Hours(last) return B36(math.floor(math.max(0, now - (last or now)) / 3600)) end
	local nameRows, codeRows = {}, {}
	for i, x in ipairs(named) do nameRows[i] = ("%s:%s:%s"):format(x.name, B36(x.c), Hours(x.last)) end
	for i, x in ipairs(coded) do codeRows[i] = ("#%s:%s:%s"):format(x.code, B36(x.c), Hours(x.last)) end
	local head = ("FA~%d~%d~%s~%s~%%d~%s~%%d~%%d~"):format(id, led.week, B36(led.amount), B36(led.since or 0), guild)
	local function Head(i, n, cut) return head:format(cut or 0, i, n) end
	local pieces, leftOut = Pieces(Head, nameRows, ",", Dues.MAX_PIECES)
	local codePieces, codesLeftOut = Pieces(Head, codeRows, ",", Dues.MAX_CODE_PIECES)
	-- Cut: whether anyone who paid this week was left out (only then may a member missing from
	-- the list have paid). The rows come those who paid this week first.
	local cut = ((leftOut and named[leftOut].c > 0) or codesLeftOut) and 1 or 0
	for _, p in ipairs(codePieces) do pieces[#pieces + 1] = p end
	if #pieces == 0 then pieces[1] = "" end
	local out = {}
	for i, p in ipairs(pieces) do out[i] = Head(i, #pieces, cut) .. p end
	return out
end

local function Queue(to, msgs, tag)
	if #outbox + #msgs > Dues.MAX_OUTBOX then return false end
	for i, msg in ipairs(msgs) do outbox[#outbox + 1] = { to = to, msg = msg, key = ("dues %s %s %d"):format(to, tag, i) } end
	Dues.Pump() -- (the first one at once, the rest a whisper every PACE)
	return true
end
function Dues.Pump()
	local item = table.remove(outbox, 1)
	if item then ns.Comm.Whisper(item.to, item.msg, item.key) end
end

-- An ask (a whisper): every guild from the King or his Steward; a guild's list from them, or
-- from that guild's Captain or Lord. This week's or last week's. Each asker's list once every
-- ANSWER_GAP.
function Dues.HandleAsk(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" or not Dues.Answers() then return end
	local week, what = text:match("^FQ~(%d+)~([^~]+)$")
	week = tonumber(week)
	local now = Dues.Week()
	if not week or (week ~= now and week ~= now - 1) then return end
	local all = what == "*"
	if not all then what = ns.King.CleanGuild(what) end
	if not what then return end
	if not (KingOrSteward(sender) or (not all and CaptainOf(sender, what))) then
		return ns.Log("dues ask from %s for %s refused: not the King, his Steward nor its Captain", tostring(sender), tostring(what))
	end
	local key = ns.FullName(sender) .. "|" .. what:lower() .. "|" .. week
	if ns.Now() - (answered[key] or -math.huge) < Dues.ANSWER_GAP then return end
	local led = Dues.Ledger(week)
	local id = math.random(1, 99999)
	local msgs = all and Dues.SummaryMessages(led, id) or Dues.GuildMessages(led, what, id)
	if Queue(sender, msgs, all and "*" or what) then answered[key] = ns.Now() end
end
ns.Comm.Handle("FQ", function(...) Dues.HandleAsk(...) end)

-- This client asks for a list (on its page, once every ASK_EVERY), while the Treasurer's addon is
-- online. The Treasurer's own client works it out itself.
function Dues.Ask(what, force)
	if Dues.IsTreasurer() or type(what) ~= "string" or not Dues.Available() then return false end
	local online, name = Dues.TreasurerOnline()
	if not online then return false end
	local now = ns.Now()
	if not force and now - (asked[what:lower()] or -math.huge) < Dues.ASK_EVERY then return false end
	asked[what:lower()] = now
	ns.Comm.Whisper(name, ("FQ~%d~%s"):format(Dues.Week(), what), "duesask " .. what:lower())
	return true
end

-- Pieces of an answer, from the Treasurer himself (his pinned name: the server sets it).
local function FromTreasurer(dist, sender) return dist == "WHISPER" and ns.Treasury.TreasurerPin(sender) == 1 end

function Dues.HandleSummary(dist, sender, text)
	if type(text) ~= "string" or not FromTreasurer(dist, sender) or not KingView() then return end
	local id, week, amount, i, n, body = text:match("^FS~(%d+)~(%d+)~([0-9a-z]+)~(%d+)~(%d+)~(.*)$")
	id, week, amount, i, n = tonumber(id), tonumber(week), N36(amount), tonumber(i), tonumber(n)
	if not (id and week and amount and i and n) or i < 1 or i > n or n > 99 then return end
	Heard(sender)
	if not summary or summary.id ~= id then
		summary = { id = id, week = week, amount = amount, n = n, got = {}, count = 0, guilds = {}, t = ns.Now() }
	end
	if summary.got[i] then return end
	summary.got[i], summary.count = true, summary.count + 1
	for row in body:gmatch("[^;]+") do
		local name, paid, copper, payers = row:match("^([^:]+):(%d+):([0-9a-z]+):(%d+)$")
		copper = N36(copper)
		local guild = name == "?" and "" or (name and ns.King.CleanGuild(name))
		if guild and copper then
			summary.guilds[guild:lower()] = { name = guild ~= "" and guild or nil, paid = math.min(tonumber(paid), ns.Codec.GUILD_CAP),
				copper = math.min(copper, MAX_COPPER), payers = math.min(tonumber(payers), ns.Codec.GUILD_CAP) }
		end
	end
	ns.Fire("TREASURY_CHANGED")
end
ns.Comm.Handle("FS", function(...) Dues.HandleSummary(...) end)

function Dues.HandleGuild(dist, sender, text)
	if type(text) ~= "string" or not FromTreasurer(dist, sender) then return end
	local id, week, amount, since, cut, guild, i, n, body = text:match("^FA~(%d+)~(%d+)~([0-9a-z]+)~([0-9a-z]+)~([01])~([^~]+)~(%d+)~(%d+)~(.*)$")
	id, week, amount, since, i, n = tonumber(id), tonumber(week), N36(amount), N36(since), tonumber(i), tonumber(n)
	guild = guild and ns.King.CleanGuild(guild)
	if not (id and week and amount and since and guild and i and n) or i < 1 or i > n or n > Dues.MAX_PIECES + Dues.MAX_CODE_PIECES then return end
	-- Only our own guild's, unless ours is the King's view.
	local own = ns.IsMember() and GetGuildInfo("player")
	if not (KingView() or (own and own:lower() == guild:lower())) then return end
	Heard(sender)
	local key = guild:lower()
	local a = answers[key]
	if not a or a.id ~= id then
		a = { id = id, week = week, amount = amount, since = since > 0 and since or nil, cut = cut == "1", n = n, got = {}, count = 0,
			rows = {}, codes = {}, t = ns.Now(), guild = guild }
		answers[key] = a
	end
	if a.got[i] then return end
	a.got[i], a.count = true, a.count + 1
	for row in body:gmatch("[^,]+") do
		local code, c, h = row:match("^#([0-9a-z]+):([0-9a-z]+):([0-9a-z]+)$")
		if code then
			c, h = N36(c), N36(h)
			if c and h and #code == 5 then a.codes[code] = { c = math.min(c, MAX_COPPER), last = a.t - h * 3600 } end
		else
			local name
			name, c, h = row:match("^([^:]+):([0-9a-z]+):([0-9a-z]+)$")
			local clean = name and ns.King.CleanName(name)
			c, h = N36(c), N36(h)
			if clean and c and h then a.rows[Dues.Key(clean)] = { n = clean, c = math.min(c, MAX_COPPER), last = a.t - h * 3600 } end
		end
	end
	ns.Fire("TREASURY_CHANGED")
end
ns.Comm.Handle("FA", function(...) Dues.HandleGuild(...) end)

---------------------------------------------------------------------------
-- What the page shows
---------------------------------------------------------------------------

-- A guild's list as this client has it, for this week: { rows = { [key] = { n, c, last } },
-- codes, amount, since, complete, cut, count, n, t, mine }, or nil. The Treasurer's own client
-- from his books (every player, whatever the guild); anyone else as the Treasurer sent it.
local function GuildData(guild)
	if Dues.IsTreasurer() then
		local led = Dues.Ledger()
		-- (His own guild's roster finds every player, whatever guild his gift carries.)
		local want, own = guild:lower(), tostring(GetGuildInfo("player")):lower()
		local rows = {}
		for key, x in pairs(led.players) do
			if want == own or (x.g and x.g:lower() == want) then rows[key] = x end
		end
		return { rows = rows, codes = {}, amount = led.amount, since = led.since, complete = true, t = led.t, mine = true }
	end
	Dues.Ask(guild)
	local a = answers[guild:lower()]
	if not a or a.week ~= Dues.Week() then return nil end
	return { rows = a.rows, codes = a.codes, amount = a.amount, since = a.since, complete = a.count >= a.n, cut = a.cut, count = a.count, n = a.n, t = a.t }
end

-- A member's week: "above", "below" or "unknown" (the list not whole, or cut and he is not on
-- it), his gold this week and his last payment.
function Dues.Standing(data, key)
	local r = data.rows[key]
	if not r and data.codes then r = data.codes[Dues.Code(key)] end
	local c, last = r and r.c or 0, r and r.last or nil
	if c >= data.amount then return "above", c, last end
	if not data.complete or (data.cut and not r) then return "unknown", c, last end
	return "below", c, last
end

-- Where the list stands, when it is not here yet or not whole.
local function Waiting(lines, data)
	if data and data.complete then return end
	if data then
		lines[#lines + 1] = { text = Grey(L.DUES_RECEIVING:format(data.count or 0, data.n or 0)) }
		return
	end
	local online, _, last = Dues.TreasurerOnline()
	Para(lines, online and L.DUES_ASKING or L.DUES_OFFLINE:format(ns.Ago(last > 0 and last or 0)))
end

-- Whose list it is and from when (a list from the Treasurer's addon: how old; his book's start).
local function Source(lines, data)
	if not data then return end
	if not data.mine then lines[#lines + 1] = { text = Grey(L.DUES_AS_OF:format(ns.Ago(data.t))) } end
	if data.since then Para(lines, L.DUES_SINCE:format(date and date("%Y-%m-%d", data.since) or tostring(data.since))) end
	if data.cut then Para(lines, L.DUES_CUT) end
end

-- When a payment was: "3h ago", "12d ago" past two days.
local function When(t)
	local d = ns.Now() - (tonumber(t) or 0)
	if d >= 2 * 86400 then return L.DUES_DAYS_AGO:format(math.floor(d / 86400)) end
	return ns.Ago(t)
end

local STANDING = { above = function() return Green(L.DUES_ABOVE) end, below = function() return Red(L.DUES_BELOW) end,
	unknown = function() return Grey(L.DUES_UNKNOWN) end }

-- A player's row: name, gold this week and above or below; his last payment in its tooltip.
local function PlayerRow(name, state, c, last, amount, extra)
	local row = { indent = 1, text = name .. (extra and ("  " .. Grey(extra)) or ""), right = (c > 0 and Coins(c) or Grey("0")) .. "  " .. STANDING[state](),
		tooltip = function(tt)
			tt:AddLine(name, 1, 0.82, 0)
			tt:AddLine(L.DUES_MEMBER_TIP:format(last and last > 0 and When(last) or L.DUES_LAST_NONE, Coins(c), Coins(amount)), 1, 1, 1, true)
		end }
	-- The last payment on the row too (the Treasurer no longer scrolls his book for it).
	if last and last > 0 then row.text = row.text .. "  " .. Grey("(" .. When(last) .. ")") end
	return row
end

-- Our own guild's roster as the server gives it: { raw, name, key, rank, rankName, level }.
function Dues.Roster()
	local out = {}
	local total = GetNumGuildMembers and tonumber((GetNumGuildMembers())) or 0
	for i = 1, math.min(total or 0, ns.Codec.GUILD_CAP) do
		local name, rankName, rankIndex, level = GetGuildRosterInfo(i)
		if type(name) == "string" and name ~= "" then
			local full = ns.FullName(ns.Normal(name))
			out[#out + 1] = { raw = name, name = ns.DisplayName(full) or name, key = Dues.Key(name), rank = tonumber(rankIndex) or 9,
				rankName = rankName, level = tonumber(level) or 0 }
		end
	end
	return out
end

local ORDER = { below = 1, unknown = 2, above = 3 }

---------------------------------------------------------------------------
-- A seat cleared (#34): our own guild's roster filtered to who is under the amount this week,
-- one member picked, one click on the game's own removal (as the Guild window's Remove). Only
-- where the player's rank can already remove members, and only that member: no removing
-- several at once, nothing at the weekly reset or on any timer, never another guild.
---------------------------------------------------------------------------

Dues.filter = nil            -- "unpaid": our roster shows only who is under the amount this week
Dues.picked = nil            -- the member picked on our roster (his key), for the Remove line

-- The player's rank may remove members: the game says so (a client that can't say: no).
function Dues.CanRemove()
	if not IsInGuild() or type(CanGuildRemove) ~= "function" then return false end
	local ok, can = pcall(CanGuildRemove)
	return ok and can and true or false
end
-- This member may be removed by this click: our roster's, below our own rank (as the game allows,
-- never ourselves), and under the amount this week on a whole list.
local function Removable(m, state)
	return state == "below" and Dues.CanRemove() and m.rank > ns.Roster.MyRank() and m.key ~= Dues.Key(ns.me)
end

-- The confirm's answer (a click, a hardware event: the removal is the game's own call, made in
-- it). Checked again first: still our roster's, below our rank, under the amount on the list.
function Dues.Remove(data)
	if type(data) ~= "table" or type(data.key) ~= "string" then return false end
	local who = data.name or data.key
	if not Dues.CanRemove() then ns.Print(L.DUES_REMOVE_CANT) return false end
	local m
	for _, r in ipairs(Dues.Roster()) do if r.key == data.key then m = r break end end
	if not m or m.rank <= ns.Roster.MyRank() or m.key == Dues.Key(ns.me) then ns.Print(L.DUES_REMOVE_GONE:format(who)) return false end
	local list = GuildData(GetGuildInfo("player"))
	if not list or Dues.Standing(list, m.key) ~= "below" then ns.Print(L.DUES_REMOVE_PAID:format(who)) return false end
	local ok = false
	if C_GuildInfo and type(C_GuildInfo.Uninvite) == "function" then
		ok = pcall(C_GuildInfo.Uninvite, m.raw)
	elseif type(GuildUninvite) == "function" then
		ok = pcall(GuildUninvite, m.raw)
	end
	ns.Log("dues: remove %s %s", tostring(m.raw), ok and "asked" or "failed")
	ns.Print(ok and L.DUES_REMOVED:format(m.name) or L.DUES_REMOVE_FAILED:format(m.name))
	if ok then
		Dues.picked = nil
		if ns.Roster.RequestScan then ns.Roster.RequestScan(true) end
		ns.Fire("TREASURY_CHANGED")
	end
	return ok
end

StaticPopupDialogs["OLYMPUS_DUES_REMOVE"] = {
	text = L.DUES_REMOVE_CONFIRM,
	button1 = L.DUES_REMOVE_YES,
	button2 = CANCEL or "Cancel",
	OnAccept = function(self, data) ns.SafeCall("dues remove", Dues.Remove, data or (self and self.data)) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- Our own guild: every member (the roster), his last payment, his gold this week, above or below;
-- filtered to those under the amount (#34), a click picks one, and the picked one's Remove line.
local function OwnGuildLines(lines, q)
	local guild = GetGuildInfo("player")
	local data = GuildData(guild)
	local roster, rows, above, below = Dues.Roster(), {}, 0, 0
	local amount = data and data.amount or Dues.Amount()
	for _, m in ipairs(roster) do
		local state, c, last = "unknown", 0, nil
		if data and m.key then state, c, last = Dues.Standing(data, m.key) end
		if state == "above" then above = above + 1 elseif state == "below" then below = below + 1 end
		if ns.Holds(q, m.name) and (Dues.filter ~= "unpaid" or state == "below") then rows[#rows + 1] = { m = m, state = state, c = c, last = last } end
	end
	table.sort(rows, function(a, b)
		if a.state ~= b.state then return ORDER[a.state] < ORDER[b.state] end
		return a.m.name < b.m.name
	end)
	lines[#lines + 1] = { header = true, text = "<" .. tostring(guild) .. ">", right = Grey(L.DUES_OWN_COUNT:format(above, #roster, Coins(amount))) }
	Waiting(lines, data)
	Source(lines, data)
	local unpaid = Dues.filter == "unpaid"
	lines[#lines + 1] = { text = Gold("> " .. (unpaid and L.DUES_FILTER_ALL:format(#roster) or L.DUES_FILTER_UNPAID:format(below))),
		onClick = function()
			Dues.filter = not unpaid and "unpaid" or nil
			shownRows = Dues.PAGE
			ns.Fire("TREASURY_CHANGED")
		end,
		tooltip = function(tt) tt:AddLine(L.DUES_FILTER_TIP, 1, 1, 1, true) end }
	if #rows == 0 then lines[#lines + 1] = { text = Grey(q and L.SEARCH_NO_MATCH or L.DUES_NONE) } end
	for i = 1, math.min(#rows, shownRows) do
		local r = rows[i]
		local row = PlayerRow(r.m.name, r.state, r.c, r.last, amount, r.m.rankName)
		local picked = Dues.picked ~= nil and Dues.picked == r.m.key
		if picked then row.text = Gold("> ") .. row.text end
		row.key = "dues member " .. tostring(r.m.key)
		row.onClick = function()
			Dues.picked = not picked and r.m.key or nil
			ns.Fire("TREASURY_CHANGED")
		end
		local tip = row.tooltip
		row.tooltip = function(tt)
			tip(tt)
			tt:AddLine(picked and L.DUES_UNPICK_TIP or L.DUES_PICK_TIP, 0.6, 1, 0.6, true)
		end
		lines[#lines + 1] = row
		-- The picked member, when this click may remove him: the one Remove line, under him.
		if picked and Removable(r.m, r.state) then
			local m = r.m
			lines[#lines + 1] = { indent = 2, key = "dues remove " .. tostring(m.key), text = Red(L.DUES_REMOVE:format(m.name)),
				onClick = function()
					ns.ShowDialog("OLYMPUS_DUES_REMOVE", m.name, Coins(r.c) .. " / " .. Coins(amount), { key = m.key, name = m.name })
				end,
				tooltip = function(tt)
					tt:AddLine(L.DUES_REMOVE:format(m.name), 1, 0.82, 0)
					tt:AddLine(L.DUES_REMOVE_TIP, 1, 1, 1, true)
				end }
		end
	end
	if #rows > shownRows then
		lines[#lines + 1] = { indent = 1, text = Grey(L.SHOW_MORE:format(math.min(Dues.PAGE, #rows - shownRows), shownRows, #rows)),
			onClick = function() shownRows = shownRows + Dues.PAGE; ns.Fire("TREASURY_CHANGED") end }
	end
end

-- Another guild (the King's and the Treasurer's view): its players who paid in the weeks kept.
local function GuildLines(lines, guild, q)
	local data = GuildData(guild)
	local amount = data and data.amount or Dues.Amount()
	lines[#lines + 1] = { header = true, text = "<" .. guild .. ">", right = Grey(L.DUES_MEMBERS:format(tostring(Dues.Members(guild) or "?"))) }
	Waiting(lines, data)
	Source(lines, data)
	if not data then return end
	local rows = {}
	for key, r in pairs(data.rows) do
		if ns.Holds(q, r.n) then rows[#rows + 1] = { key = key, r = r, state = Dues.Standing(data, key) } end
	end
	table.sort(rows, function(a, b)
		if a.state ~= b.state then return ORDER[a.state] < ORDER[b.state] end
		return tostring(a.r.n) < tostring(b.r.n)
	end)
	if #rows == 0 then lines[#lines + 1] = { text = Grey(q and L.SEARCH_NO_MATCH or L.DUES_NONE) } end
	for i = 1, math.min(#rows, shownRows) do
		local r = rows[i]
		lines[#lines + 1] = PlayerRow(r.r.n, r.state, r.r.c, r.r.last, amount)
	end
	if #rows > shownRows then
		lines[#lines + 1] = { indent = 1, text = Grey(L.SHOW_MORE:format(math.min(Dues.PAGE, #rows - shownRows), shownRows, #rows)),
			onClick = function() shownRows = shownRows + Dues.PAGE; ns.Fire("TREASURY_CHANGED") end }
	end
	local codes = 0
	for _ in pairs(data.codes or {}) do codes = codes + 1 end
	if codes > 0 then Para(lines, L.DUES_UNPLACED:format(codes)) end
end

-- Every guild (the King's and the Treasurer's view): its members, how many paid this week, the
-- gold in, the percentage. A click opens its players.
local function TableLines(lines, q)
	local led, complete
	if Dues.IsTreasurer() then
		led, complete = Dues.Ledger(), true
	else
		Dues.Ask("*")
		if summary and summary.week == Dues.Week() then led, complete = summary, summary.count >= summary.n end
	end
	lines[#lines + 1] = { header = true, text = L.DUES_GUILDS, right = Grey(L.DUES_GUILDS_COLS) }
	if not led then
		Waiting(lines, nil)
		return
	end
	if not complete then lines[#lines + 1] = { text = Grey(L.DUES_RECEIVING:format(led.count or 0, led.n or 0)) } end
	local rows, seen = {}, {}
	for key, row in pairs(led.guilds) do
		if key ~= "" then
			seen[key] = true
			rows[#rows + 1] = { name = row.name, paid = row.paid, copper = row.copper, payers = row.payers }
		end
	end
	for _, e in ipairs(ns.Data.Summary().guilds) do
		if e.counted and not seen[e.name:lower()] then
			seen[e.name:lower()] = true
			rows[#rows + 1] = { name = e.name, paid = 0, copper = 0, payers = 0 }
		end
	end
	local own = GetGuildInfo("player")
	if own and ns.IsFederation(own) and not seen[own:lower()] then rows[#rows + 1] = { name = own, paid = 0, copper = 0, payers = 0 } end
	for _, r in ipairs(rows) do r.members = Dues.Members(r.name) end
	table.sort(rows, function(a, b)
		if a.copper ~= b.copper then return a.copper > b.copper end
		if (a.members or 0) ~= (b.members or 0) then return (a.members or 0) > (b.members or 0) end
		return a.name < b.name
	end)
	local shown = 0
	for _, r in ipairs(rows) do
		if ns.Holds(q, r.name) then
			shown = shown + 1
			local pct = r.members and (math.floor(r.paid * 100 / r.members + 0.5) .. "%") or "?"
			lines[#lines + 1] = { indent = 1, key = "dues " .. r.name:lower(), text = "<" .. r.name .. ">",
				right = L.DUES_GUILD_ROW:format(tostring(r.members or "?"), r.paid, GoldText(r.copper), pct),
				onClick = function() Dues.Open(r.name) end,
				tooltip = function(tt)
					tt:AddLine("<" .. r.name .. ">", 1, 0.82, 0)
					tt:AddLine(L.DUES_GUILD_TIP:format(tostring(r.members or "?"), r.paid, Coins(led.amount), Coins(r.copper), r.payers), 1, 1, 1, true)
				end }
		end
	end
	if shown == 0 then lines[#lines + 1] = { text = Grey(q and L.SEARCH_NO_MATCH or L.DUES_NONE) } end
	local loose = led.guilds[""]
	if loose and loose.payers > 0 and not q then
		lines[#lines + 1] = { indent = 1, text = Grey(L.DUES_NO_GUILD), right = Grey(L.DUES_NO_GUILD_ROW:format(loose.payers, GoldText(loose.copper))),
			tooltip = function(tt) tt:AddLine(L.DUES_NO_GUILD_TIP, 1, 1, 1, true) end }
	end
end

-- The dues page (Treasury.Build, mode "dues"): lines, title, detail. `q`, the tab's search.
function Dues.Build(q)
	local lines = { { text = Gold("< " .. (Dues.shown and SeesAll() and L.DUES_ALL_GUILDS or L.TREASURY_TITLE)), onClick = function() Dues.Back() end, gapAfter = true } }
	local amount = Dues.Amount()
	lines[#lines + 1] = { header = true, text = L.DUES_TITLE:format(Dues.DateLabel(Dues.Week())), right = L.DUES_A_WEEK:format(Coins(amount)) }
	Para(lines, L.DUES_PRIVATE)
	lines[#lines].gapAfter = true
	if KingView() then
		lines[#lines + 1] = { text = Gold("> " .. L.DUES_SET_AMOUNT:format(Coins(amount))), gapAfter = true,
			onClick = function() ns.ShowDialog("OLYMPUS_DUES_AMOUNT") end,
			tooltip = function(tt) tt:AddLine(L.DUES_SET_AMOUNT_TIP, 1, 1, 1, true) end }
	end
	local own = GetGuildInfo("player")
	if not SeesAll() or (Dues.shown and own and Dues.shown:lower() == own:lower()) then
		OwnGuildLines(lines, q)
	elseif Dues.shown then
		GuildLines(lines, Dues.shown, q)
	else
		TableLines(lines, q)
	end
	return lines, L.TAB_TREASURY, L.DUES_DETAIL
end

-- On top of the Treasury tab's summary: the button that fills in a member's own payment (#35),
-- and the way to the dues for whoever may see them.
function Dues.SummaryLines(lines)
	if Dues.Pays() then
		local amount = Dues.Amount()
		lines[#lines + 1] = { text = Gold(L.DUES_SEND:format(Coins(amount))), gapAfter = not Dues.Sees(), onClick = function() Dues.SendDues() end,
			tooltip = function(tt)
				tt:AddLine(L.DUES_SEND:format(Coins(amount)), 1, 0.82, 0)
				tt:AddLine(L.DUES_SEND_TIP:format(ns.DisplayName(Dues.MailTo()), Coins(amount), Dues.Note(Dues.Week(), GetGuildInfo("player"))), 1, 1, 1, true)
			end }
	end
	if not Dues.Sees() then return end
	lines[#lines + 1] = { text = Gold("> " .. L.DUES_LINK:format(Coins(Dues.Amount()))), gapAfter = true, onClick = function() Dues.Open() end,
		tooltip = function(tt) tt:AddLine(L.DUES_LINK_TIP, 1, 1, 1, true) end }
end

---------------------------------------------------------------------------
-- The payer's click (#35): it fills in his mail or his trade, he presses Send or Trade
---------------------------------------------------------------------------

-- Who sends the dues: a member on the Treasurer's side, not a keeper (a keeper's gold to him is
-- the treasury's own moving, never a gift).
function Dues.Pays() return Dues.Available() and not ns.Treasury.IsKeeper() end

-- Where the mail goes: the Treasurer's mail character, pinned by name (where he asked the
-- treasury's mail to go; his book counts it), never a name heard on the channel.
function Dues.MailTo()
	local mail
	for _, pin in ipairs(ns.TREASURER_CHARACTERS or {}) do
		if pin ~= ns.TREASURER then mail = pin break end
	end
	return ns.FullName(mail or ns.TREASURER, ns.TREASURER_REALM)
end

local function Shown(frame) return type(frame) == "table" and frame.IsShown and frame:IsShown() and true or false end

-- The mail being written: the recipient, the note and the gold, sent as money (never cash on
-- delivery). Nothing is sent: the player presses Send.
local function FillMail(to, amount, note)
	SendMailNameEditBox:SetText(ns.TellName(to))
	if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText(note) end
	if SendMailRadioButton_OnClick then
		SendMailRadioButton_OnClick(1)
	elseif SendMailSendMoneyButton and SendMailCODButton then
		SendMailSendMoneyButton:SetChecked(true)
		SendMailCODButton:SetChecked(false)
	end
	MoneyInputFrame_SetCopper(SendMailMoney, amount)
	ns.Print(L.DUES_SEND_MAIL_FILLED:format(ns.DisplayName(to), Coins(amount), note))
	return "mail"
end

-- The trade with the Treasurer: its gold, the game's own call (the trade window follows it).
-- Nothing is given: the player presses Trade. Where the game refuses the addon that call, it is
-- said once (ADDON_ACTION_BLOCKED, below) and from then on the amount is only told.
local function FillTrade(amount, name)
	local set = C_TradeInfo and C_TradeInfo.SetTradeMoney or SetTradeMoney
	if not set or (ns.db and ns.db.duesTradeBlocked) then
		ns.Print(L.DUES_SEND_TRADE_TYPE:format(Coins(amount), ns.DisplayName(name)))
		return "type"
	end
	local ok = pcall(set, amount)
	if not ok then
		ns.Print(L.DUES_SEND_TRADE_TYPE:format(Coins(amount), ns.DisplayName(name)))
		return "type"
	end
	ns.Print(L.DUES_SEND_TRADE_FILLED:format(Coins(amount), ns.DisplayName(name)))
	return "trade"
end

-- The click: the amount, to the Treasurer, with the note (the fund and the week, and the guild,
-- which a mail has no other way to carry). An open trade with the Treasurer or his mail
-- character: its gold; the mailbox on its Send Mail tab: the mail. Nothing opens by itself, the
-- mailbox's or the trade's opening fills nothing, and nothing is ever sent or given by the
-- addon. With the gamepad UI nothing of the game's windows is touched (its code there is the
-- game's own, see Dialog.lua): the line says what to send.
function Dues.SendDues()
	if not Dues.Pays() then return false end
	local amount, to = Dues.Amount(), Dues.MailTo()
	local note = Dues.Note(Dues.Week(), GetGuildInfo("player"))
	if ns.GamepadUI() then
		ns.Print(L.DUES_SEND_GAMEPAD:format(Coins(amount), ns.DisplayName(to), note))
		return "gamepad"
	end
	local money = GetMoney and tonumber(GetMoney()) or nil
	if Shown(TradeFrame) then
		local name = ns.UnitFullName and ns.UnitFullName("NPC") or (UnitName and UnitName("NPC"))
		if not (type(name) == "string" and ns.Treasury.TreasurerPin(ns.FullName(ns.Normal(name)))) then
			ns.Print(L.DUES_SEND_TRADE_OTHER:format(tostring(name and ns.DisplayName(name) or "?")))
			return "other"
		end
		if money and money < amount then ns.Print(L.DUES_SEND_NOT_ENOUGH:format(Coins(amount))) return "short" end
		return FillTrade(amount, name)
	end
	if Shown(SendMailFrame) and SendMailNameEditBox and SendMailMoney and MoneyInputFrame_SetCopper then
		if money and money < amount then ns.Print(L.DUES_SEND_NOT_ENOUGH:format(Coins(amount))) return "short" end
		return FillMail(to, amount, note)
	end
	if Shown(MailFrame) then
		ns.Print(L.DUES_SEND_OPEN_TAB)
		return "tab"
	end
	ns.Print(L.DUES_SEND_HOW:format(ns.DisplayName(to), Coins(amount)))
	return "closed"
end

-- The game refused the trade's gold to the addon: said once, never tried again.
for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
	ns.RegisterEvent(event, function(addon, func)
		if addon ~= ADDON or not tostring(func):find("TradeMoney", 1, true) or not ns.db or ns.db.duesTradeBlocked then return end
		ns.db.duesTradeBlocked = true
		ns.Print(L.DUES_SEND_TRADE_BLOCKED)
	end)
end

-- The page (a guild's players: that guild).
function Dues.Open(guild)
	Dues.shown = guild
	shownRows = Dues.PAGE
	ns.Treasury.Show("dues")
end
function Dues.Back()
	if Dues.shown and SeesAll() then return Dues.Open(nil) end
	Dues.shown = nil
	ns.Treasury.Show("summary")
end

StaticPopupDialogs["OLYMPUS_DUES_AMOUNT"] = {
	text = L.DUES_AMOUNT_PROMPT,
	button1 = OKAY or "OK",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 160,
	maxLetters = 24,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then
			local copper = Dues.Amount()
			local g, s = math.floor(copper / 10000), math.floor(copper / 100) % 100
			eb:SetText(s > 0 and ("%dg %ds"):format(g, s) or tostring(g))
			ns.Focus(eb)
		end
	end,
	OnAccept = function(self)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("dues amount", Dues.SetAmount, eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		ns.SafeCall("dues amount", Dues.SetAmount, self:GetText())
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

ns.On("LOGIN", function()
	ns.After(30, "dues amount", function()
		Dues.SendAmount(true)
		Dues.Repeat(true)
	end)
	ns.Every(60, "dues amount", function()
		Dues.SendAmount()
		Dues.Repeat()
	end)
	ns.Every(Dues.PACE, "dues answers", Dues.Pump)
end)

-- Tests start from a clean state.
function Dues.Reset()
	anchor = nil
	lastAmountSent, lastRepeat, lastOlder = -math.huge, -math.huge, -math.huge
	heardAt, heardName, summary = -math.huge, nil, nil
	wipe(asked); wipe(answered); wipe(outbox); wipe(answers)
	Dues.shown, shownRows, Dues.filter, Dues.picked = nil, Dues.PAGE, nil, nil
	if ns.rdb then ns.rdb.duesAmount = nil end
	if ns.db then ns.db.previewDuesAmount, ns.db.duesTradeBlocked = nil, nil end
end
function Dues.Outbox() return outbox end
