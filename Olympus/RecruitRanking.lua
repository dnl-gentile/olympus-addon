local ADDON, ns = ...
local L = ns.L

-- 1.5.9, the recruiting ranking for everyone. The author, 2026-11-12: "O ranking para todo mundo",
-- and on the handoffs: "para pontuação... a redistribuição... devia contar menos pontos, tipo os
-- pontos da rede... Se a pessoa for convidada e aceitar entrar na guilda". Any Olympus member's
-- recruit counts once another player's addon confirms his join, not only the Church's people's, and
-- the member who passed that player on (a JOIN or a scanned player, RecruitHandoff.lua) gets a share
-- of it, as the Church's first network level does. The Church's own counting (ChurchCount.lua) stays
-- as it was: these records are of a type of their own, NE, kept apart from the Church's ledger. A
-- keeper of 1.5.4 to 1.5.8 has no handler for NE and drops it unread (Comm.lua), so a member's recruit
-- never mixes with the Apostles' records, and the Church's rankings never change by it.
--
-- How a recruit is counted, with nobody doing anything:
-- - The guild's log, read as the Church reads it (ChurchCount.Read). From 1.5.9 every Olympus guild
--   is read, drawn so that about two of its clients read (Count.MaybeRead, RR.ReadWanted), and an
--   invite followed by the invitee's join within Count.PAIR_HOURS is a pair (Count.OnPair).
-- - Who reports a pair: about two members of the guild and about two of its officers (RR.ELECT, a draw
--   on their own name and the pair's, the same on every client: the census names officers, so a keeper
--   in another guild can vouch for them), and always a keeper, a High Councillor or the guild's Church
--   correspondent. (Review of the 1.5.9 release: a member drawn reports only where a keeper is among his
--   guildmates; no other keeper can vouch for him.) The inviter's own client reports every pair of his (review of 1.5.9: it reads its log
--   as a Church person's does for OWN_READ_HOURS after it took an invite command to chat, and while a
--   name another member passed it waits); his report names the member who passed him that player, if
--   one did. The member who passed it says so himself when the name was taken (NE h, RecruitHandoff.lua).
--   Each report goes to the Church's keepers online (the Head, the Apostles, the author), whispered, and
--   waits in an outbox OUTBOX_DAYS while none takes it.
-- - Pending or confirmed (review of 1.5.9: one officer's or a correspondent's word made up recruits for
--   any name, and a guildmate's took a real recruit from his inviter). A keeper weighs each witness's
--   word (ChurchCount.VerifiedWitness first): strong from a keeper, the King or a High Councillor, or from
--   a guildmate of the keeper's own guild when the keeper's own read of the log saw that same invite
--   (ChurchCount.SawInvite); weak from anyone else it can vouch for (an officer as the census names him,
--   a correspondent, a guildmate whose invite its own log did not show). A strong word confirms a record
--   alone. A weak one confirms it only beside the inviter's own report, and one weak witness confirms
--   WEAK_DAY recruits a join day at most, the same on every keeper (RR.Credits): a name nobody's own
--   addon stands behind never ranks. The inviter's own report and the passer's are kept apart from the
--   ledger (OWN_MAX, OWN_DAYS): they only mark a record a witness made (s), and name who passed the
--   player on when both say the same (src). The keeper that weighed a word tells the others.
-- - One recruit counts once: a strong claim before a weak one, then the earliest: the same player invited
--   again later, by anyone and in any guild, is taken. Never an alt (Alts.Linked, either way,
--   ChurchCount.AltOf), nor a player a keeper's own roster memory saw in another Olympus guild in
--   Count.NEW_DAYS before his join, or in the same guild before the invite (a return); the keeper that
--   saw it tells the others. (A move out of a guild no keeper's addon saw is not caught: no other client's
--   word on where a player was can be checked.)
-- - Still in the guild STAY_DAYS after his join: the witnesses that reported the pair say so then (NE y),
--   and a keeper of that guild sees it on its own roster.
--
-- Points, in game only (the Church's numbers): the inviter POINTS_JOIN for each confirmed recruit, dated
-- at his join, and POINTS_STAY more when the recruit is still in STAY_DAYS later, dated then; the member
-- who passed that player on, SHARE of those points (the Church's first level, 25%), at the same dates.
-- Nothing for an invite whose player never joined. Windows: this week, the last 30 days, all time.
--
-- Who sees what: every Olympus member sees the ranking (Church > Ranking): the top RANK_ROWS rows and
-- his own, asked of a keeper online, and the last answer kept on his computer. (Review of 1.5.9: one
-- character could take most of a keeper's sending with its asks, and the Church's own answers came back
-- "busy". A keeper answers an asker whose ask names an Olympus guild that nothing it knows of him
-- contradicts, ANSWERS_PER times in ANSWER_WINDOW, ANSWERS_ALL askers in all, on a line queue of its own
-- that leaves the Church's room first; a member's asks start at a keeper his name picks.)
--
-- Kept on the keepers' computers (ns.rdb.recruits.led): each record RECORDS_DAYS after its join, then its
-- points fold into its people's all-time totals; RECORDS_MAX records at most. A recruit whose claim was
-- folded is not counted again for GONE_DAYS.
--
-- The wire (NE, whole messages, version 1, whispers only; clients before 1.5.9 drop them unread):
--   NE~1~w~<inviter>~<invitee>~<guild>~<invite hour36>~<join hour36>~<source|->   a log pair -> keepers
--       (the source: only in the inviter's own report, the member who passed him that player)
--   NE~1~h~<recruit>~<inviter>   the member who passed that player on, his own word -> keepers
--   NE~1~y~<inviter>~<invitee>~<guild>~<join hour36>~<1|0>   a witness's word, STAY_DAYS on -> keepers
--   NE~1~k~<h1,h2,...>   a keeper's receipt for the reports it took (Comm.Hash36 of each) -> reporter
--   NE~1~x~<h1,h2,...>   a keeper's refusal: a witness it can't vouch for; another keeper may -> reporter
--   NE~1~l~<h1,h2,...>   a keeper refused these for now: they go to it again later -> reporter
--   NE~1~r~<recruit>~<inviter>~<guild|->~<tc36>~<tj36|->~<flags|->~<witnesses|->~<source|->~<u36>
--       a record between keepers; flags: s the inviter's own report, a alt, t moved in or came back,
--       y still in after STAY_DAYS, n gone by then; witnesses: two at most, the strong ones first, a weak
--       one marked "!"
--   NE~1~p~<name>~<joins>~<stays>~<passed on>~<of them stayed>~<u36>   a person's folded totals
--   NE~1~g~<recruit>~<inviter>~<t36>   a claim folded into the totals: its recruit counts no more
--   NE~1~q~<id>~<since36>~<tie|->   a keeper asks another for what changed after its cursor
--   NE~1~d~<id>~<i>~<row>   a row of that answer (an r, p or g line without its "NE~1~")
--   NE~1~e~<id>~<rows>~<more 0|1>~<last36>~<tie|->   its end: the next cursor, once every row came
--   NE~1~a~<id>~<w|m|a>~<guild>   a member asks a keeper for the ranking (his own guild)
--   NE~1~o~<id>~<rank>~<name>~<score*100>~<own*100>~<share*100>~<joins>~<stays>~<passed on>   a row
--   NE~1~n~<id>~<rows>~<ranked>~<asOf36>~<pending>   its end (pending: the asker's own, unconfirmed)

local Church, Count = ns.Church, ns.ChurchCount
if type(Church) ~= "table" or type(Count) ~= "table" then return end

local RR = {}
ns.RecruitRanking = RR

RR.POINTS_JOIN, RR.POINTS_STAY, RR.STAY_DAYS = Count.POINTS_JOIN, Count.POINTS_STAY, Count.STAY_DAYS
RR.SHARE = Count.SHARES[1]
RR.PAIR_HOURS, RR.NEW_DAYS = Count.PAIR_HOURS, Count.NEW_DAYS
RR.EVIDENCE_DAYS = 14            -- a join older than this is no new evidence (the Church's REG_DAYS)
RR.RECORDS_MAX, RR.RECORDS_DAYS = 20000, 40 -- past 40 days a record counts in all time only: folded
RR.GONE_DAYS, RR.GONE_MAX, RR.PEOPLE_MAX = 120, 60000, 8000
RR.OUTBOX_MAX, RR.OUTBOX_DAYS, RR.RESEND_GAP, RR.RESEND_TRIES = 800, 7, 3600, 4
RR.RECEIPT_GAP, RR.RECEIPT_IDS = 5, 24
-- What a keeper takes from one sender an hour and a day; a witness only the census vouches for, or
-- the inviter's linked alt, against the smaller budget too (the Church's).
RR.EVIDENCE_HOUR, RR.EVIDENCE_DAY, RR.CENSUS_HOUR, RR.CENSUS_DAY = 300, 2000, 30, 100
RR.ELECT = 2                     -- members, and officers, who report one pair: about this many each
RR.SOURCES_MAX, RR.SOURCE_HOURS = 200, 72
RR.SEEN_MAX, RR.STAY_LATE = 800, 7
-- (Review of 1.5.9) The inviters' own reports and the passers' words, kept apart from the ledger: this
-- many of each at most, this many days. One weak witness's word confirms WEAK_DAY recruits a join day.
RR.OWN_MAX, RR.OWN_DAYS, RR.WEAK_DAY = 6000, 14, 25
RR.OWN_READ_HOURS = 3            -- the inviter's client reads its log this long after an invite command
-- (Review of 1.5.9: 25 rows were 27 whispers an answer, about 32 seconds of a keeper's sending.)
RR.RANK_ROWS = 10
RR.ASK_GAP, RR.RANK_REFRESH, RR.ASK_WINDOW = 60, 900, 120
RR.ANSWERS_PER, RR.ANSWERS_ALL, RR.ANSWER_WINDOW = 2, 8, 300
RR.CATCHUP_EVERY, RR.CATCHUP_LINES, RR.CATCHUP_RETRY, RR.CATCHUP_GAP = 1800, 120, 120, 4
RR.DUE_EVERY, RR.SETTLE_MAX, RR.SEND_ROOM = 600, 900, 20
-- The ranking's own line queue: QUEUE_MAX transfers, members' answers QUEUE_ASKS of them; it sends only
-- while Comm's queue keeps CHURCH_ROOM more free than the Church's own lines need (ChurchCount.SendLines).
RR.QUEUE_MAX, RR.QUEUE_ASKS, RR.CHURCH_ROOM = 6, 3, 10

RR.after = function(seconds, where, fn) ns.After(seconds, where, fn) end

local Key, B36, UnB36, WireName, CleanGuild = Church.Key, Church.B36, Church.UnB36, Church.WireName, Church.CleanGuild
local Clock, OwnGuild = Church.Clock, Church.OwnGuild
local DAY = 86400
local floor, max, min = math.floor, math.max, math.min
local NE = "NE~1~"

local stats = { pairs = 0, reported = 0, stays = 0, sent = 0, taken = 0, receipts = 0, pushed = 0, lines = 0, pages = 0,
	answers = 0, folded = 0, dropped = {} }
local function Drop(why)
	stats.dropped[why] = (stats.dropped[why] or 0) + 1
	return false, why
end
local function Day(t) return floor((tonumber(t) or 0) / DAY) end
local function Short(name) return name and ns.ShortName(ns.Normal(name)) or nil end
local function Off()
	local M = ns.Moderation
	return M and M.SelfOff and M.SelfOff() or nil
end
-- A keeper of these records: the Church's (the Head, the Apostles, the author), never the King's client,
-- which does no background ledger work (ChurchCount).
local function IsKeeper(name) return Church.IsKeeper(name or ns.me) and not Church.IsKing(name or ns.me) end
local function Room(n) return ns.Comm.QueueRoom() > RR.SEND_ROOM + (n or 0) end
local function Hundred(v) return floor((tonumber(v) or 0) * 100 + 0.5) end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and ns.Fold(a) == ns.Fold(b) end
-- A witness every keeper vouches for wherever he is: the signed (a keeper, the King, a High Councillor).
local function Signed(name)
	local who = ns.FullName(name)
	return Church.IsKeeper(who) or Church.IsKing(who) or (ns.IsHighCouncillor ~= nil and ns.IsHighCouncillor(who) == true)
end
-- A guildmate on this client's fresh roster.
local function Mate(name)
	local R = ns.Roster
	local fresh = R and R.Fresh and R.Fresh()
	return fresh ~= nil and fresh ~= false and R.RankOf ~= nil and R.RankOf(ns.FullName(name)) ~= nil
end

-- The keepers heard to take these records this session (any NE word of theirs): an older keeper drops
-- them unread, so a report goes to one not heard yet once, and a member's ask goes to one heard first.
local serving = {}
local function Serving(name) local k = Key(name) return k ~= nil and serving[k] ~= nil end

---------------------------------------------------------------------------
-- Saved data (ns.rdb.recruits, per realm group and faction)
---------------------------------------------------------------------------

local function Store()
	local r = ns.rdb
	if type(r) ~= "table" then return nil end
	if type(r.recruits) ~= "table" then r.recruits = {} end
	return r.recruits
end
local function Sub(key, make)
	local s = Store()
	if not s then return nil end
	if type(s[key]) ~= "table" then s[key] = make() end
	return s[key]
end
local function Out() return Sub("out", function() return {} end) end
local function Sources() return Sub("src", function() return {} end) end
local function Seen() return Sub("seen", function() return {} end) end
local function Views() return Sub("view", function() return {} end) end
local function Told() return Sub("told", function() return {} end) end

-- (Review of the 1.5.9 release) One account's characters of a realm group and faction share ns.rdb: the
-- reports waiting, the pairs seen as a witness and the names passed on are each its character's (by). A
-- keeper reads a report's sender as its reporter, so an inviter's own report his alt sent was the alt's
-- word (or refused), never his own. An entry saved before it named its character is the first one's to
-- take it.
local function Owned(e)
	local me = Key(ns.me)
	if type(e) ~= "table" or not me then return false end
	if e.by == nil then e.by = me end
	return e.by == me
end
-- (own: the inviters' own reports, hand: the passers' words, both by record id: kept apart from r.)
local function NewLedger() return { v = 1, n = 0, r = {}, p = {}, gone = {}, from = {}, caught = {}, own = {}, hand = {} } end
local function Led()
	local l = Sub("led", NewLedger)
	if l and (l.v ~= 1 or type(l.r) ~= "table" or type(l.p) ~= "table" or type(l.gone) ~= "table" or type(l.from) ~= "table") then
		Store().led = NewLedger()
		l = Store().led
	end
	if l then
		for _, k in ipairs({ "caught", "own", "hand" }) do if type(l[k]) ~= "table" then l[k] = {} end end
	end
	return l
end
RR.Led = Led

local rev = 0
local credits
local ranks = {}
local function Changed()
	rev = rev + 1
	credits, ranks = nil, {}
	ns.Fire("RECRUIT_RANKING_CHANGED")
end

---------------------------------------------------------------------------
-- Who passed this player to me (the inviter's client), and the pairs I saw (a witness's)
---------------------------------------------------------------------------

local function Bound(t, limit, field)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	if n <= limit then return end
	local list = {}
	for k, v in pairs(t) do list[#list + 1] = { k = k, at = type(v) == "table" and tonumber(v[field]) or 0 } end
	table.sort(list, function(a, b) if a.at ~= b.at then return a.at < b.at end return tostring(a.k) < tostring(b.k) end)
	for i = 1, #list - limit do t[list[i].k] = nil end
end

-- RecruitHandoff gave this client a name another member passed on (Recruit.TakeHandoff): kept SOURCE_HOURS,
-- so this client's own read of the log can name him in its report of the invite and the join.
function RR.HandedIn(name, by)
	local xk, bk = Key(name), Key(by)
	local src = Sources()
	if not xk or not bk or xk == bk or not src then return false end
	local now = Clock()
	for k, s in pairs(src) do
		if type(s) ~= "table" or now - (tonumber(s.at) or 0) > RR.SOURCE_HOURS * 3600 then src[k] = nil end
	end
	src[xk] = { n = Short(by), at = now, by = Key(ns.me) }
	Bound(src, RR.SOURCES_MAX, "at")
	return true
end

-- The member who passed this player on, for an invite at hour `ti`: handed in before it (the log's hours
-- may be one off either way: Count.Events), and no more than SOURCE_HOURS before.
function RR.SourceOf(recruit, ti)
	local s = (Sources() or {})[Key(recruit) or ""]
	if type(s) ~= "table" or type(s.n) ~= "string" or not Owned(s) then return nil end
	local at = tonumber(s.at) or 0
	if ti and (at > (ti + 2) * 3600 or at < ti * 3600 - RR.SOURCE_HOURS * 3600) then return nil end
	return s.n
end

-- A number in [0, 1) from a pair and a name, the same on every client: a member's draw for that pair.
function RR.score(id, name)
	local s = tostring(id) .. "|" .. tostring(Key(name) or "")
	local a, b = 5381, 52711
	for i = 1, #s do
		local c = s:byte(i)
		a = (a * 33 + c) % 2147483647
		b = (b * 31 + c * 7) % 2147483629
	end
	return ((a * 7919 + b) % 1000003) / 1000003
end

-- Officers of our guild online whose addon this client heard (about ELECT of them report a pair).
local function OfficersOnline()
	local R, V, n = ns.Roster, ns.Versions, 0
	for _, row in ipairs(R and R.online or {}) do
		if (tonumber(row.rankIndex) or 9) <= (ns.CAPTAIN_RANK or 1) then
			local name = ns.FullName(row.name)
			if not (V and V.HasOlympus) or V.HasOlympus(name) or Key(name) == Key(ns.me) then n = n + 1 end
		end
	end
	return max(1, n)
end

-- (Review of the 1.5.9 release) A keeper among this client's guildmates (its fresh roster, online or not;
-- never the King's client, which keeps no ledger): the only keeper that weighs a plain member's word
-- (ChurchCount.VerifiedWitness). Worked out once a roster.
local keeperHere = { generation = nil, guild = nil, found = false }
local function KeeperHere()
	local R = ns.Roster
	local fresh = R and R.Fresh and R.Fresh()
	local guild = OwnGuild()
	if not fresh or not guild or type(R.members) ~= "table" then return false end
	if keeperHere.generation == R.generation and keeperHere.guild == guild and R.generation ~= nil then return keeperHere.found end
	local found = false
	for _, row in ipairs(R.members) do
		local name = row.full or row.name
		if type(name) == "string" and IsKeeper(name) then found = true break end
	end
	keeperHere.generation, keeperHere.guild, keeperHere.found = R.generation, guild, found
	return found
end

-- Why this client reports a pair in its guild, or nil: one every keeper can vouch for, always; else drawn.
-- (Review of the 1.5.9 release: a plain member drawn where no keeper is among his guildmates reported each
-- pair to keepers that all refused it, and it waited 7 days while his client looked for a keeper every 2
-- minutes. He reports only where a keeper of his guild can weigh his word.)
local function Reporter(id, guild)
	if Church.IsKing(ns.me) then return nil end
	if IsKeeper(ns.me) then return "keeper" end
	if ns.IsHighCouncillor and ns.IsHighCouncillor(ns.FullName(ns.me)) == true then return "council" end
	local S = Church.State()
	if guild and S.corrOf[Key(ns.me) or ""] == ns.Fold(guild) then return "correspondent" end
	local officer = ns.Roster and ns.Roster.IsOfficer and ns.Roster.IsOfficer() == true
	local peers = officer and OfficersOnline() or max(1, (ns.Comm.PeerCount and ns.Comm.PeerCount()) or 1)
	if RR.score(id, ns.me) < min(1, RR.ELECT / peers) then
		if officer then return "officer" end
		if KeeperHere() then return "drawn" end
	end
	return nil
end
RR.Reporter = Reporter

-- A pair this client reported as a witness: its stay is told STAY_DAYS after the join (StayReports).
local function Remember(id, inviter, invitee, guild, tj)
	local seen, me = Seen(), Key(ns.me)
	local key = me and (id .. "|" .. me)
	if not seen or not key or seen[key] then return end
	seen[key] = { i = Short(inviter), n = Short(invitee), g = guild, h = tj, by = me }
	Bound(seen, RR.SEEN_MAX, "h")
end

---------------------------------------------------------------------------
-- Reports to the keepers (an outbox while none takes them)
---------------------------------------------------------------------------

-- (Review of the 1.5.9 release: one per text and character. The same pair seen by an inviter's alt as a
-- witness and by the inviter himself is one text, each its own report.)
local function Queue(text)
	local out, me = Out(), Key(ns.me)
	if not out or not me then return nil end
	for _, o in ipairs(out) do if type(o) == "table" and o.text == text and Owned(o) then return o end end
	if #out >= RR.OUTBOX_MAX then table.remove(out, 1) end
	local o = { text = text, h = ns.Comm.Hash36(text), at = Clock(), to = {}, by = me }
	out[#out + 1] = o
	return o
end

-- Each report of this character's to every keeper online that takes these (RESEND_TRIES times, RESEND_GAP
-- apart, until one sends its receipt), and once a login to a keeper not heard to take them yet. Another
-- character's wait for him. (Review of the 1.5.9 release: once in all, kept in the saved outbox: a report
-- tried with a keeper still on 1.5.8, who drops these unread, never went to him again after he updated. A
-- keeper's refusal, x, stays one.)
function RR.Flush()
	local out = Out()
	if not out or #out == 0 or Off() or (ns.ChatLocked and ns.ChatLocked()) then return 0 end
	local now, mine = Clock(), 0
	local login = ns.db and tonumber(ns.db.sessions) or 0
	for i = #out, 1, -1 do
		local o = out[i]
		if type(o) ~= "table" or type(o.text) ~= "string" or now - (tonumber(o.at) or 0) > RR.OUTBOX_DAYS * DAY then table.remove(out, i)
		else
			if type(o.to) ~= "table" then o.to = {} end
			if Owned(o) then mine = mine + 1 end
		end
	end
	if mine == 0 then return 0 end
	local keepers = {}
	for _, k in ipairs(Church.KeepersOnline(false)) do
		local kk = Key(k.name)
		if kk then keepers[#keepers + 1] = { name = k.name, key = kk, serving = serving[kk] ~= nil } end
	end
	if #keepers == 0 then
		Church.FindKeeper()
		return 0
	end
	local sent, me = 0, Key(ns.me)
	for _, o in ipairs(out) do
		if o.by == me then
			o.h = o.h or ns.Comm.Hash36(o.text)
			for _, k in ipairs(keepers) do
				local s = o.to[k.key]
				local tries = type(s) == "table" and tonumber(s.n) or 0
				if not k.serving and tries > 0 and tries < RR.RESEND_TRIES and s.l ~= login then tries = 0 end
				local limit = k.serving and RR.RESEND_TRIES or 1
				if tries < limit and (not s or now - (tonumber(s.w) or 0) >= RR.RESEND_GAP) then
					if not Room() then return sent end
					o.to[k.key] = { n = tries + 1, w = now, l = login }
					if ns.Comm.Whisper(k.name, o.text, nil, false, false, nil, { owner = RR }) then
						sent, stats.sent = sent + 1, stats.sent + 1
					end
				end
			end
		end
	end
	return sent
end

-- A report: a keeper takes its own at once (a keeper is a witness every keeper vouches for) and tells
-- the keepers online once; any other client queues it for them.
function RR.Report(text)
	if Off() or type(text) ~= "string" or #text > 255 then return false end
	stats.reported = stats.reported + 1
	if IsKeeper(ns.me) then
		local ok = RR.TakeEvidence(ns.me, text) == true
		if ok then
			for _, k in ipairs(Church.KeepersOnline(false)) do
				if not Room() then break end
				ns.Comm.Whisper(k.name, text, nil, false, false, nil, { owner = RR })
			end
		end
		return ok
	end
	Queue(text)
	RR.Flush()
	return true
end

-- A keeper's receipt (k): those reports leave the outbox (the keepers' catch-up carries them on). Its
-- refusal (x): those reports go to that keeper no more, and wait for another (one that can vouch for
-- this witness in its own guild). Only this character's: the keeper answered him.
local function TakeReceipt(sender, text)
	local kind, list = text:match("^NE~1~([kxl])~([0-9a-z,]+)$")
	if not list then return Drop("shape") end
	if not IsKeeper(sender) then return Drop("keeper") end
	local got, n = {}, 0
	for h in list:gmatch("[0-9a-z]+") do
		n = n + 1
		if n > RR.RECEIPT_IDS then break end
		got[h] = true
	end
	local out, k, now = Out() or {}, Key(sender), Clock()
	for i = #out, 1, -1 do
		local o = out[i]
		if type(o) == "table" and type(o.text) == "string" and got[o.h or ns.Comm.Hash36(o.text)] and Owned(o) then
			if kind == "k" then
				table.remove(out, i)
				stats.receipts = stats.receipts + 1
			elseif kind == "x" and type(o.to) == "table" then
				o.to[k] = { n = RR.RESEND_TRIES, w = now }
			end
			-- (l: refused for now. The report stays, and goes to that keeper again RESEND_GAP after it last
			-- did: hearing this word made him one that takes these, RESEND_TRIES sends.)
		end
	end
	return true
end

-- The receipts this keeper owes: for a report it took, or one no other try can change (k); for a witness
-- it cannot vouch for, a refusal (x: another keeper may); (review of 1.5.9) for a report refused for now (a
-- budget spent, a record or a roster not here yet), a later (l): before it, a reporter that had never heard
-- this keeper take these sent it once and never again. None to a keeper.
local owed, owing = {}, false
local FINAL = { shape = true, kind = true, times = true, self = true, recruit = true, guild = true, alt = true }
local LATER = { budget = true, roster = true, none = true, early = true }
local function SendReceipts()
	owing = false
	for k, r in pairs(owed) do
		for _, kind in ipairs({ "k", "x", "l" }) do
			local ids = r[kind]
			while #ids > 0 and Room() do
				local n = min(#ids, RR.RECEIPT_IDS)
				ns.Comm.Whisper(r.name, "NE~1~" .. kind .. "~" .. table.concat(ids, ",", 1, n), nil, false, false, nil, { owner = RR })
				for _ = 1, n do table.remove(ids, 1) end
			end
		end
		if #r.k == 0 and #r.x == 0 and #r.l == 0 then owed[k] = nil end
	end
	if next(owed) then owing = true; RR.after(RR.RECEIPT_GAP, "recruit ranking receipts", SendReceipts) end
end
function RR.Receipt(sender, text, ok, why)
	local kind = (ok == true or FINAL[why or ""]) and "k" or (why == "unverified" and "x") or (LATER[why or ""] and "l") or nil
	if not kind then return false end
	local k = Key(sender)
	if not k or k == Key(ns.me) or IsKeeper(sender) then return false end
	local r = owed[k]
	if not r then
		Church.Capped(owed, RR.PEOPLE_MAX)
		r = { name = ns.FullName(sender), k = {}, x = {}, l = {} }
		owed[k] = r
	end
	if #r[kind] >= RR.RECEIPT_IDS * 4 then return false end
	r[kind][#r[kind] + 1] = ns.Comm.Hash36(text)
	if not owing then owing = true; RR.after(RR.RECEIPT_GAP, "recruit ranking receipts", SendReceipts) end
	return true
end

---------------------------------------------------------------------------
-- What this client's own read of the log brings (ChurchCount.Process: every pair, any inviter)
---------------------------------------------------------------------------

-- (Review of the 1.5.9 release) This character's own pairs he reported, by id: each once. Another character
-- of his account may have read the log first (its events read are the account's too, ChurchCount.Process),
-- and his own read hands them in again (`again`).
local function FirstTell(id)
	local all, me = Told(), Key(ns.me)
	if not all or not me then return true end
	local mine = all[me]
	if type(mine) ~= "table" then mine = {}; all[me] = mine end
	local now = Clock()
	for k, e in pairs(mine) do
		if type(e) ~= "table" or now - (tonumber(e.at) or 0) > RR.EVIDENCE_DAYS * DAY then mine[k] = nil end
	end
	if mine[id] then return false end
	mine[id] = { at = now }
	Bound(mine, RR.SEEN_MAX, "at")
	return true
end

function RR.Pair(inviter, invitee, guild, ti, tj, again)
	if Off() or type(guild) ~= "string" or not ns.IsFederation(guild) then return false end
	local ik, xk, me = Key(inviter), Key(invitee), Key(ns.me)
	local g = CleanGuild(guild)
	if not ik or not xk or ik == xk or xk == me or not g or not ti or not tj then return false end
	if again and ik ~= me then return false end
	local id = xk .. ":" .. ik
	local function Text(source)
		return table.concat({ "NE~1~w", Short(inviter), Short(invitee), g, B36(ti), B36(tj), source or "-" }, "~")
	end
	-- (Review of 1.5.9) The inviter's own client reports every pair of his, not only one a member passed
	-- him: his word is what makes his recruit pending ("N of yours wait for another addon"), and what a
	-- weak witness's word needs beside it. It names the member who passed him that player, if one did.
	if ik == me then
		if not FirstTell(id) then return false end
		stats.pairs = stats.pairs + 1
		return RR.Report(Text(RR.SourceOf(invitee, ti)))
	end
	stats.pairs = stats.pairs + 1
	if not Reporter(id, guild) then return false end
	Remember(id, inviter, invitee, g, tj)
	return RR.Report(Text(nil))
end

-- (1.5.9) Whether this client should read its guild's log for these records (ChurchCount.MaybeRead):
-- "own" while a member's handoff waits for its invite and join (this client names him), and (review of
-- 1.5.9) OWN_READ_HOURS after this player took an invite command to chat (Recruit.LastInviteAt): his own
-- report of the join; "drawn" in any Olympus guild (the Church's draw: about two readers a guild), nil
-- otherwise.
function RR.ReadWanted()
	if Off() or not ns.IsMember() or Church.IsKing(ns.me) then return nil end
	local guild = OwnGuild()
	if not guild or not ns.IsFederation(guild) then return nil end
	local now = Clock()
	for _, s in pairs(Sources() or {}) do
		if type(s) == "table" and now - (tonumber(s.at) or 0) <= (RR.PAIR_HOURS + 2) * 3600 and Owned(s) then return "own" end
	end
	local R = ns.Recruit
	local invited = R and R.LastInviteAt and R.LastInviteAt()
	if invited and ns.Now() - invited <= RR.OWN_READ_HOURS * 3600 then return "own" end
	return "drawn"
end

-- (Review of 1.5.9) RecruitHandoff passed `name` on and the member `to` took it (his "A"): this client's
-- own word to the keepers. The member who passed a player on gets his share only when the inviter's own
-- report names him too: neither one's word alone makes a source.
function RR.HandedOut(name, to)
	local n, t = WireName(name), WireName(to)
	local xk, tk, me = Key(n), Key(t), Key(ns.me)
	if Off() or not xk or not tk or xk == tk or xk == me or tk == me then return false end
	return RR.Report(("NE~1~h~%s~%s"):format(Short(n), Short(t)))
end

-- A witness's stays: STAY_DAYS after each join it reported, whether its guild's roster holds the recruit,
-- up to STAY_LATE days later (a client away then tells nothing).
local function StayReports()
	local seen, now = Seen(), Clock()
	if not seen then return 0 end
	local guild = OwnGuild()
	local R = ns.Roster
	local fresh = R and R.Fresh and R.Fresh()
	local n = 0
	for id, s in pairs(seen) do
		local due = type(s) == "table" and tonumber(s.h) and s.h * 3600 + RR.STAY_DAYS * DAY
		if not due or now > due + RR.STAY_LATE * DAY then seen[id] = nil
		elseif now >= due and fresh and guild and ns.Fold(guild) == ns.Fold(s.g or "") and Owned(s) then
			Count.Remember(false)
			local f = Count.Fact(s.n)
			local here = f ~= nil and f.now == true and ns.Fold(f.guild) == ns.Fold(s.g)
			seen[id] = nil
			stats.stays = stats.stays + 1
			n = n + 1
			RR.Report(("NE~1~y~%s~%s~%s~%s~%s"):format(s.i, s.n, s.g, B36(s.h), here and "1" or "0"))
		end
	end
	return n
end
RR.StayReports = StayReports

---------------------------------------------------------------------------
-- The keepers' ledger
---------------------------------------------------------------------------

local function Witnesses(list)
	local out, seen = {}, {}
	for _, s in ipairs(list or {}) do if s and not seen[s] then seen[s], out[#out + 1] = true, s end end
	table.sort(out)
	while #out > 2 do table.remove(out) end
	return out
end

-- o into r (both of one recruit and inviter): the earliest times, every flag, the two smallest strong
-- witnesses and the two smallest weak ones, the stronger stay word, who passed the player on (as both
-- his and the inviter's own words said, a keeper's line or this keeper's side tables). The order they
-- come in makes no difference.
local function MergeRec(r, o)
	local changed = false
	local function Set(k, v) if r[k] ~= v then r[k], changed = v, true end end
	if o.tc and (not r.tc or o.tc < r.tc) then Set("tc", o.tc) end
	if o.tj and (not r.tj or o.tj < r.tj or (o.tj == r.tj and (o.g or "") < (r.g or ""))) then Set("tj", o.tj); Set("g", o.g) end
	if not r.g and o.g then Set("g", o.g) end
	for _, f in ipairs({ "s", "a", "t" }) do if o[f] and not r[f] then Set(f, 1) end end
	if o.y == 1 and r.y ~= 1 then Set("y", 1) elseif o.y == 0 and r.y == nil then Set("y", 0) end
	if o.src and (not r.src or (Key(o.src) or "") < (Key(r.src) or "")) then Set("src", o.src) end
	for _, f in ipairs({ "ws", "wk" }) do
		if o[f] then
			local all = {}
			for _, s in ipairs(r[f] or {}) do all[#all + 1] = s end
			for _, s in ipairs(o[f]) do all[#all + 1] = s end
			local list = Witnesses(all)
			if table.concat(list, ",") ~= table.concat(r[f] or {}, ",") then Set(f, #list > 0 and list or nil) end
		end
	end
	return changed
end

local function TooOld(r, now) return now - (r.tj or r.tc or 0) > RR.RECORDS_DAYS * DAY end

-- What this keeper's own client knows of the recruit: an alt of the inviter's (or of a character in Olympus
-- lately), or a player its roster memory saw in another Olympus guild in NEW_DAYS before his join, or in
-- the same guild before the invite (Count.Fact, the Church's seen-check's rule).
local function OwnFacts(r)
	local o = {}
	if not (r.n and r.bn) then return o end
	if Count.AltOf(r.n, r.bn) then o.a = 1 end
	Count.Remember(false)
	local f = Count.Fact(r.n)
	if f and r.tj and r.g then
		local joinDay = Day(r.tj)
		if ns.Fold(f.guild) ~= ns.Fold(r.g) then
			if ns.IsFederation(f.guild) and (f.first or 0) <= joinDay and (f.last or 0) >= joinDay - RR.NEW_DAYS then o.t = 1 end
		elseif r.tc and (f.first or 0) < Day(r.tc) - 1 then
			o.t = 1
		end
	end
	return o
end

local function Flags(r)
	local f = (r.s and "s" or "") .. (r.a and "a" or "") .. (r.t and "t" or "") .. (r.y == 1 and "y" or (r.y == 0 and "n" or ""))
	return f ~= "" and f or "-"
end
local function Time36(t) return B36(max(0, tonumber(t) or 0)) end
-- Two witnesses at most on the wire: the strong ones first, then the weak ones, each marked "!".
local function WitnessField(r)
	local out = {}
	for _, s in ipairs(r.ws or {}) do if #out < 2 then out[#out + 1] = s end end
	for _, s in ipairs(r.wk or {}) do if #out < 2 then out[#out + 1] = "!" .. s end end
	return #out > 0 and table.concat(out, ",") or "-"
end
function RR.RecordLine(id, r)
	return ("NE~1~r~%s~%s~%s~%s~%s~%s~%s~%s~%s"):format(Short(r.n) or "?", Short(r.bn) or "?", CleanGuild(r.g) or "-", Time36(r.tc),
		tonumber(r.tj) and Time36(r.tj) or "-", Flags(r), WitnessField(r), r.src and Short(r.src) or "-", Time36(r.u))
end
-- A saved record of the right shape (CheckSaved): its fields of the types this file writes.
local function ValidRecord(r)
	if type(r) ~= "table" or type(r.n) ~= "string" or type(r.bn) ~= "string" or type(r.tc) ~= "number" then return false end
	for f, kind in pairs({ tj = "number", g = "string", ws = "table", wk = "table", src = "string", u = "number", y = "number", s = "number" }) do
		if r[f] ~= nil and type(r[f]) ~= kind then return false end
	end
	return true
end

local function ParseRecord(text)
	local n, bn, g, tc, tj, flags, ws, src, u = tostring(text or ""):match("^NE~1~r~([^~]+)~([^~]+)~([^~]+)~([0-9a-z]+)~([0-9a-z%-]+)~([%a%-]+)~([^~]+)~([^~]+)~([0-9a-z]+)$")
	if not n then return nil end
	local recruit, inviter = WireName(n), WireName(bn)
	if not recruit or not inviter then return nil end
	local guild = g ~= "-" and CleanGuild(g) or nil
	if g ~= "-" and (not guild or not ns.IsFederation(guild)) then return nil end
	if not flags:match("^[satyn]*$") and flags ~= "-" then return nil end
	local rec = { n = Short(recruit), bn = Short(inviter), g = guild, tc = UnB36(tc), tj = tj ~= "-" and UnB36(tj) or nil,
		s = flags:find("s", 1, true) and 1 or nil, a = flags:find("a", 1, true) and 1 or nil, t = flags:find("t", 1, true) and 1 or nil,
		y = flags:find("y", 1, true) and 1 or (flags:find("n", 1, true) and 0 or nil) }
	if not rec.tc or (tj ~= "-" and not rec.tj) then return nil end
	if ws ~= "-" then
		local strong, weak = {}, {}
		for s in ws:gmatch("[^,]+") do
			local isWeak = s:sub(1, 1) == "!"
			local k = Key(WireName(isWeak and s:sub(2) or s))
			if not k then return nil end
			local list = isWeak and weak or strong
			list[#list + 1] = k
		end
		rec.ws = #strong > 0 and Witnesses(strong) or nil
		rec.wk = #weak > 0 and Witnesses(weak) or nil
	end
	if src ~= "-" then
		local name = WireName(src)
		if not name then return nil end
		rec.src = Short(name)
	end
	local ik, xk = Key(inviter), Key(recruit)
	if not ik or not xk or ik == xk then return nil end
	return xk .. ":" .. ik, rec, UnB36(u)
end
RR.ParseRecord = ParseRecord

-- The member who passed the player on, as the inviter's own report names him: never the inviter, the
-- recruit, nor a character linked to either (Alts.Linked).
local function ValidSource(src, inviter, invitee)
	local name = WireName(src)
	local sk = name and Key(name)
	if not sk or sk == Key(inviter) or sk == Key(invitee) then return nil end
	if Count.Linked(name, inviter) or Count.Linked(name, invitee) then return nil end
	return Short(name)
end
local function SourceKey(r)
	if not r.src then return nil end
	local sk = Key(r.src)
	if not sk or sk == Key(r.bn) or sk == Key(r.n) or Count.Linked(r.src, r.bn) or Count.Linked(r.src, r.n) then return nil end
	return sk
end

-- The people's totals: what this ledger folded itself (o*) and the most another keeper's line said (l*),
-- each read as the larger (the same claim folded on both counts once).
local TOTALS = { "j", "y", "h", "hy" }
local function Person(l, key, name)
	local p = l.p[key]
	if type(p) ~= "table" then
		p = { n = name }
		l.p[key] = p
	end
	if not p.n and name then p.n = name end
	return p
end
local function Totals(p)
	if type(p) ~= "table" then return 0, 0, 0, 0 end
	local function Of(f) return max(tonumber(p["o" .. f]) or 0, tonumber(p["l" .. f]) or 0) end
	return Of("j"), Of("y"), Of("h"), Of("hy")
end
RR.Totals = Totals

-- A credited claim into its people's totals (it ages out, or makes room), its recruit marked: no other
-- claim on him counts again for GONE_DAYS.
local function Fold(l, id, r, now)
	local xk, ik = id:match("^([^:]+):(.+)$")
	if not xk then return end
	local p = Person(l, ik, Short(r.bn))
	p.oj, p.oy, p.u = (tonumber(p.oj) or 0) + 1, (tonumber(p.oy) or 0) + (r.y == 1 and 1 or 0), now
	local sk = SourceKey(r)
	if sk then
		local s = Person(l, sk, Short(r.src))
		s.oh, s.ohy, s.u = (tonumber(s.oh) or 0) + 1, (tonumber(s.ohy) or 0) + (r.y == 1 and 1 or 0), now
	end
	l.gone[xk] = { t = now, i = ik, u = now }
	stats.folded = stats.folded + 1
end

-- (Review of 1.5.9) How strongly a claim stands: STRONG, a strong witness's word; WEAK, a weak witness's
-- beside the inviter's own report (within its witness's WEAK_DAY); else only one of them: pending.
local STRONG, WEAK, PENDING = 3, 2, 1
-- The claim that comes first on one recruit: the stronger, then the earliest invite, then the smaller id.
-- (A made-up claim dated earlier, on a weak witness's word, takes no recruit a strong word holds.)
local function Before(id, r, c, bid, b, bc)
	if c ~= bc then return c > bc end
	return (r.tc or 0) < (b.tc or 0) or ((r.tc or 0) == (b.tc or 0) and id < bid)
end

-- Per recruit, the claim that counts: credited (confirmed), pending (not yet: one witness's or its
-- inviter's word alone), taken (another claim holds him, or a folded one did), transfer, alt. The same
-- on every keeper holding the same records: a weak witness's day fills in the order of the joins.
function RR.Credits()
	if credits and credits.rev == rev then return credits end
	local l = Led()
	local states, winners, class, weak = {}, {}, {}, {}
	for id, r in pairs(l.r) do
		local xk = id:match("^([^:]+):")
		local state
		if not xk or not r.tj then state = "open"
		elseif r.t then state = "transfer"
		elseif r.a then state = "alt"
		elseif l.gone[xk] then state = "taken"
		else
			state = "valid"
			if r.ws and #r.ws > 0 then class[id] = STRONG
			else
				class[id] = PENDING
				if r.s and r.wk and #r.wk > 0 then weak[#weak + 1] = id end
			end
		end
		states[id] = state
	end
	table.sort(weak, function(a, b)
		local ta, tb = l.r[a].tj, l.r[b].tj
		if ta ~= tb then return ta < tb end
		return a < b
	end)
	local used = {}
	for _, id in ipairs(weak) do
		local r = l.r[id]
		local day = Day(r.tj)
		for _, w in ipairs(r.wk) do
			local k = w .. ":" .. day
			if (used[k] or 0) < RR.WEAK_DAY then
				used[k], class[id] = (used[k] or 0) + 1, WEAK
				break
			end
		end
	end
	for id, r in pairs(l.r) do
		if states[id] == "valid" then
			local xk = id:match("^([^:]+):")
			local bid = winners[xk]
			if not bid then winners[xk] = id
			elseif Before(id, r, class[id], bid, l.r[bid], class[bid]) then states[bid], winners[xk] = "taken", id
			else states[id] = "taken" end
		end
	end
	for _, id in pairs(winners) do states[id] = class[id] >= WEAK and "credited" or "pending" end
	credits = { rev = rev, states = states, winners = winners }
	return credits
end
function RR.StateOf(id) return RR.Credits().states[id] end

-- Room in a full ledger: the records that count for nothing first, then pending ones, then the credited
-- ones (folded), the oldest first, the id breaking ties; a fiftieth at once.
local LET_GO = { open = 1, transfer = 1, alt = 1, taken = 1, pending = 2, credited = 3 }
local function MakeRoom(l, now)
	local C = RR.Credits()
	local list = {}
	for id, r in pairs(l.r) do list[#list + 1] = { id = id, tier = LET_GO[C.states[id] or "open"] or 1, t = tonumber(r.tj or r.tc) or 0 } end
	table.sort(list, function(a, b)
		if a.tier ~= b.tier then return a.tier < b.tier end
		if a.t ~= b.t then return a.t < b.t end
		return a.id < b.id
	end)
	local go = #list - (RR.RECORDS_MAX - max(1, floor(RR.RECORDS_MAX / 50)))
	for i = 1, min(#list, go) do
		local id = list[i].id
		if C.states[id] == "credited" then Fold(l, id, l.r[id], now) end
		l.r[id] = nil
		l.n = max(0, (l.n or 0) - 1)
	end
	Changed()
end

-- A keeper's word on a record to the other keepers online (Comm's queue left room).
local function Push(id)
	local r = Led().r[id]
	if not r then return end
	local line = RR.RecordLine(id, r)
	for _, k in ipairs(Church.KeepersOnline(false)) do
		if not Room() then break end
		ns.Comm.Whisper(k.name, line, nil, false, false, nil, { owner = RR })
	end
	stats.pushed = stats.pushed + 1
end
RR.Push = Push

-- A record into this ledger (new, or merged); push: to the keepers online. A record new here is checked
-- against this keeper's own knowledge (OwnFacts), and what that finds goes to the others. fromLine: it
-- came in another keeper's line. True when it changed anything.
function RR.MergeIn(id, rec, push, fromLine)
	local l, now = Led(), Clock()
	local r = l.r[id]
	local changed, new = false, false
	if not r then
		local xk = id:match("^([^:]+):")
		if not xk or not (rec.tc or rec.tj) or TooOld(rec, now) then return false end
		local g = l.gone[xk]
		if g and type(g) == "table" and g.i and id == xk .. ":" .. g.i then return false end
		if (l.n or 0) >= RR.RECORDS_MAX then MakeRoom(l, now) end
		r = { n = rec.n, bn = rec.bn }
		l.r[id] = r
		l.n = (l.n or 0) + 1
		changed, new = true, true
	end
	if MergeRec(r, rec) then changed = true end
	local o = new and OwnFacts(r) or {}
	local know = (o.a and not r.a) or (o.t and not r.t)
	-- (Review of 1.5.9) What this keeper's side tables add: the inviter's own report (s), and who passed
	-- the player on once his own word and the inviter's agree (src). Told back to the keeper whose line
	-- lacked it (fromLine); the keepers online took those words themselves (the catch-up brings the rest).
	local own, hand = l.own[id], l.hand[id]
	if type(own) == "table" then
		o.s = 1
		if type(own.src) == "string" and type(hand) == "table" and Same(hand.by, own.src) then o.src = own.src end
	end
	local side = (o.s and not r.s) or (o.src and r.src ~= o.src)
	if know or side then
		if MergeRec(r, o) then changed, push = true, push or know or (side and fromLine == true) end
	end
	if changed then
		r.u = now
		Changed()
		if push then Push(id) end
	end
	return changed
end

-- (Review of 1.5.9) An inviter's own report or a passer's word into its side table (by record id), kept
-- OWN_DAYS, OWN_MAX at most (the oldest go first): never a record by itself. A record a witness made
-- already takes what it adds (RR.MergeIn).
local function Side(l, which, id, entry)
	local t = l[which]
	local old = t[id]
	if type(old) == "table" and old.src ~= nil and entry.src == nil then entry.src = old.src end
	t[id] = entry
	Bound(t, RR.OWN_MAX, "at")
	if l.r[id] then RR.MergeIn(id, {}, false) end
	Changed()
end

-- Budgets per sender: large for every report, small also for one only the census stands behind, an
-- inviter's own report and a passer's word.
local rates = {}
local function Budget(sender, now, large)
	local k = Key(sender)
	if not k then return false end
	k = large and k or (k .. ":small")
	local b = rates[k]
	local hour, day = floor(now / 3600), Day(now)
	if not b then Church.Capped(rates, RR.PEOPLE_MAX) end
	if not b or b.hour ~= hour then b = { hour = hour, n = 0, day = b and b.day or day, d = b and b.d or 0 }; rates[k] = b end
	if b.day ~= day then b.day, b.d = day, 0 end
	if b.n >= (large and RR.EVIDENCE_HOUR or RR.CENSUS_HOUR) or b.d >= (large and RR.EVIDENCE_DAY or RR.CENSUS_DAY) then return false end
	b.n, b.d = b.n + 1, b.d + 1
	return true
end

-- A report a keeper takes (a whisper, or this keeper's own read). True when taken.
function RR.TakeEvidence(sender, text)
	if not IsKeeper(ns.me) or Off() then return Drop("not keeper") end
	local kind = tostring(text or ""):match("^NE~1~(%a)~")
	if kind ~= "w" and kind ~= "y" and kind ~= "h" then return Drop("kind") end
	local now = Clock()
	local M = ns.Moderation
	if M and M.Hides and M.Hides(sender, nil) then return Drop("netoff") end
	if not Budget(sender, now, true) then return Drop("budget") end
	local sk = Key(sender)
	if kind == "w" then
		local inviter, invitee, guild, ti, tj, src = text:match("^NE~1~w~([^~]+)~([^~]+)~([^~]+)~([0-9a-z]+)~([0-9a-z]+)~([^~]+)$")
		inviter, invitee, guild, ti, tj = WireName(inviter), WireName(invitee), CleanGuild(guild), UnB36(ti), UnB36(tj)
		if not inviter or not invitee or not guild or not ti or not tj then return Drop("shape") end
		if not ns.IsFederation(guild) then return Drop("guild") end
		if tj < ti - 1 or tj > ti + RR.PAIR_HOURS then return Drop("times") end
		if tj * 3600 > now + 3600 or tj * 3600 < now - RR.EVIDENCE_DAYS * DAY then return Drop("times") end
		local ik, xk = Key(inviter), Key(invitee)
		if ik == xk then return Drop("self") end
		if sk == xk or Count.Linked(invitee, sender) then return Drop("recruit") end
		local l, id = Led(), xk .. ":" .. ik
		local ours = Same(OwnGuild(), guild)
		if sk == ik then
			-- (Review of 1.5.9) The inviter's own report: kept apart from the ledger, the smaller budget too
			-- (anyone can whisper one). It only marks a record a witness made, and names who passed him the
			-- player. In our own guild, only from a member our roster holds or held.
			if ours and not Mate(sender) then
				local f = Count.Fact(sender)
				if not (f and Same(f.guild, guild)) then return Drop("unverified") end
			end
			if not Budget(sender, now, false) then return Drop("budget") end
			stats.taken = stats.taken + 1
			Side(l, "own", id, { at = now, t = tj * 3600, src = src ~= "-" and ValidSource(src, inviter, invitee) or nil })
			return true
		end
		-- (An alt of the inviter's is his own word, not a witness's: nothing.)
		if Count.Linked(inviter, sender) then return Drop("alt") end
		local ok, how = Count.VerifiedWitness(sender, guild, invitee, tj)
		if not ok then return Drop(how or "unverified") end
		if how == "census" and not Budget(sender, now, false) then return Drop("budget") end
		-- (Review of 1.5.9) Strong: the signed anywhere, or a guildmate of ours for an invite our own read
		-- of the log saw by the same inviter (a guildmate's word otherwise named any inviter for a recruit
		-- our roster showed). Every other witness we vouch for is weak.
		local strong = Signed(sender) or (ours and Mate(sender) and Count.SawInvite(inviter, invitee, ti))
		stats.taken = stats.taken + 1
		-- (A keeper outside the pair's guild can't weigh a guildmate there: the one that did tells the others,
		-- on any change. A signed witness's word reaches every keeper online itself.)
		RR.MergeIn(id, { n = Short(invitee), bn = Short(inviter), g = guild, tc = ti * 3600, tj = tj * 3600,
			ws = strong and { sk } or nil, wk = (not strong) and { sk } or nil }, not Signed(sender))
		return true
	end
	if kind == "h" then
		-- (Review of 1.5.9) The member who passed a player on, his own word: kept apart from the ledger.
		local recruit, inviter = text:match("^NE~1~h~([^~]+)~([^~]+)$")
		recruit, inviter = WireName(recruit), WireName(inviter)
		if not recruit or not inviter or Key(recruit) == Key(inviter) then return Drop("shape") end
		if not ValidSource(sender, inviter, recruit) then return Drop("self") end
		if not Budget(sender, now, false) then return Drop("budget") end
		stats.taken = stats.taken + 1
		Side(Led(), "hand", Key(recruit) .. ":" .. Key(inviter), { at = now, by = Short(sender) })
		return true
	end
	local inviter, invitee, guild, tj, on = text:match("^NE~1~y~([^~]+)~([^~]+)~([^~]+)~([0-9a-z]+)~([01])$")
	inviter, invitee, guild, tj = WireName(inviter), WireName(invitee), CleanGuild(guild), UnB36(tj)
	if not inviter or not invitee or not guild or not tj then return Drop("shape") end
	local ik, xk = Key(inviter), Key(invitee)
	if ik == xk then return Drop("self") end
	if sk == ik or sk == xk or Count.Linked(inviter, sender) or Count.Linked(invitee, sender) then return Drop("recruit") end
	local id = xk .. ":" .. ik
	local r = Led().r[id]
	if not r or not r.tj then return Drop("none") end
	if math.abs(r.tj - tj * 3600) > 2 * 3600 then return Drop("times") end
	if now < r.tj + RR.STAY_DAYS * DAY - 3600 then return Drop("early") end
	local ok, how = Count.VerifiedWitness(sender, r.g or guild, invitee, floor(r.tj / 3600))
	if not ok then return Drop(how or "unverified") end
	if how == "census" and not Budget(sender, now, false) then return Drop("budget") end
	local y = on == "1" and 1 or 0
	if r.y == 1 or r.y == y then return true end
	stats.taken = stats.taken + 1
	RR.MergeIn(id, { y = y }, true)
	return true
end

-- A keeper's own checks, each DUE_EVERY: the stay of the recruits of its own guild on its own roster,
-- and (once a session for each record past its stay day) an alt link or a move learned since it came.
local rechecked, recheckedN = {}, 0
local function KeeperChecks()
	local l, now = Led(), Clock()
	local guild = OwnGuild()
	local R = ns.Roster
	local fresh = R and R.Fresh and R.Fresh()
	local C = RR.Credits()
	local done = {}
	for id, r in pairs(l.r) do
		local state = C.states[id]
		if r.tj and r.y == nil and (state == "credited" or state == "pending") and now >= r.tj + RR.STAY_DAYS * DAY then
			local o = {}
			if not rechecked[id] then
				if recheckedN >= RR.RECORDS_MAX then rechecked, recheckedN = {}, 0 end
				rechecked[id], recheckedN = true, recheckedN + 1
				o = OwnFacts(r)
			end
			if fresh and guild and r.g and ns.Fold(guild) == ns.Fold(r.g) then
				local f = Count.Fact(r.n)
				o.y = (f and f.now == true and ns.Fold(f.guild) == ns.Fold(r.g)) and 1 or 0
			end
			if o.y or (o.a and not r.a) or (o.t and not r.t) then done[#done + 1] = { id = id, o = o } end
		end
	end
	for _, d in ipairs(done) do RR.MergeIn(d.id, d.o, true) end
	return #done
end
RR.KeeperChecks = KeeperChecks

---------------------------------------------------------------------------
-- Lines between keepers: pushes, and the catch-up
---------------------------------------------------------------------------

local function LedgerScope()
	local group = ns.group
	if type(group) == "string" and group:match("^Forever%a+$") and ns.faction then return group .. ":" .. ns.faction end
end
local function LedgerPeer(name)
	local scope = LedgerScope()
	return scope == nil or ns.ForeverFamily(ns.RealmOf(name)) == ns.group
end

function RR.PersonLine(key, p)
	local j, y, h, hy = Totals(p)
	return ("NE~1~p~%s~%d~%d~%d~%d~%s"):format(Short(p.n) or key, j, y, h, hy, Time36(p.u))
end
local function GoneLine(xk, g)
	return ("NE~1~g~%s~%s~%s"):format(xk, tostring(g.i or "-"), Time36(g.t))
end

-- A keeper's line, checked again: witnesses that are the inviter, the recruit or linked to either go, and
-- so does a source that is; nothing dated ahead. (A keeper's line vouches for the rest.)
local function TakeLine(sender, text)
	if not IsKeeper(ns.me) or Off() then return Drop("not keeper") end
	if not IsKeeper(sender) then return Drop("keeper") end
	if not LedgerPeer(sender) then return Drop("scope") end
	local kind = text:match("^NE~1~(%a)~")
	local now = Clock()
	stats.lines = stats.lines + 1
	if kind == "r" then
		local id, rec = ParseRecord(text)
		if not id then return Drop("shape") end
		if (rec.tc or 0) > now + 3600 or (rec.tj and rec.tj > now + 3600) then return Drop("ahead") end
		for _, f in ipairs({ "ws", "wk" }) do
			if rec[f] then
				local list = {}
				for _, s in ipairs(rec[f]) do
					if s ~= Key(rec.bn) and s ~= Key(rec.n) and not Count.Linked(s, rec.bn) and not Count.Linked(s, rec.n) then list[#list + 1] = s end
				end
				rec[f] = #list > 0 and list or nil
			end
		end
		if rec.src and not ValidSource(rec.src, rec.bn, rec.n) then rec.src = nil end
		return RR.MergeIn(id, rec, false, true)
	elseif kind == "p" then
		local n, j, y, h, hy = text:match("^NE~1~p~([^~]+)~(%d+)~(%d+)~(%d+)~(%d+)~[0-9a-z]+$")
		local name = WireName(n)
		j, y, h, hy = tonumber(j), tonumber(y), tonumber(h), tonumber(hy)
		if not name or not j or y > j or hy > h or j > 100000 or h > 100000 then return Drop("shape") end
		local l = Led()
		local key = Key(name)
		if not l.p[key] then
			local count = 0
			for _ in pairs(l.p) do count = count + 1 end
			if count >= RR.PEOPLE_MAX then return Drop("full") end
		end
		local p = Person(l, key, Short(name))
		local changed = false
		for f, v in pairs({ j = j, y = y, h = h, hy = hy }) do
			if v > (tonumber(p["l" .. f]) or 0) then p["l" .. f], changed = v, true end
		end
		if changed then p.u = now; Changed() end
		return changed
	elseif kind == "g" then
		local xk, ik, t = text:match("^NE~1~g~([^~]+)~([^~]+)~([0-9a-z]+)$")
		t = UnB36(t)
		local recruit, inviter = WireName(xk), WireName(ik)
		if not recruit or not inviter or not t or t > now + 3600 then return Drop("shape") end
		xk, ik = Key(recruit), Key(inviter)
		if now - t > RR.GONE_DAYS * DAY then return false end
		local l = Led()
		local g = l.gone[xk]
		if type(g) == "table" and (tonumber(g.t) or 0) >= t then return false end
		-- (The same claim held here and credited: folded here too, so both ledgers' totals hold it once.)
		local id = xk .. ":" .. ik
		local r = l.r[id]
		if r and RR.Credits().states[id] == "credited" then
			Fold(l, id, r, now)
			l.r[id] = nil
			l.n = max(0, (l.n or 0) - 1)
		end
		-- (t: when it was folded, for its GONE_DAYS; u: when this ledger took it, for the catch-up's order.)
		l.gone[xk] = { t = max(t, type(g) == "table" and tonumber(g.t) or 0), i = ik, u = now }
		Changed()
		return true
	end
	return Drop("kind")
end
RR.TakeLine = TakeLine

-- (Review of 1.5.9) The ranking's own line transfers, one target each: { target, list, i, terminal }.
-- They took the Church's eight slots (ChurchCount.SendLines) and its answers came back "busy"; now they
-- wait in a queue of their own, and go only while Comm's queue keeps CHURCH_ROOM more free than the
-- Church's sends need, so the Church's go first. A keeper's catch-up page may take every slot, a
-- member's answer QUEUE_ASKS of them.
local outq, pumping = {}, false
local function LineRoom() return ns.Comm.QueueRoom() > RR.SEND_ROOM + RR.CHURCH_ROOM end
local function LinesEnd(o)
	if not o.terminal or not o.closed or o.pending > 0 or o.failed then return end
	local line = o.terminal
	o.terminal = nil
	local function Send()
		if LineRoom() and (not o.guard or o.guard()) then
			ns.Comm.Whisper(o.target, line, nil, false, false, nil, { owner = RR, guard = o.guard })
		end
	end
	if LineRoom() then Send() else RR.after(3, "recruit ranking terminal", Send) end
end
local function PumpOut()
	pumping = false
	while outq[1] and LineRoom() do
		local o = outq[1]
		if o.guard and not o.guard() then o.failed = true end
		while o.i <= #o.list and not o.failed and LineRoom() do
			local done
			if o.terminal then
				o.pending = o.pending + 1
				done = function(ok)
					o.pending = o.pending - 1
					if not ok then o.failed = true end
					LinesEnd(o)
				end
			end
			ns.Comm.Whisper(o.target, o.list[o.i], nil, false, false, done, { owner = RR, guard = o.guard })
			o.i = o.i + 1
		end
		if o.i <= #o.list and not o.failed then break end
		table.remove(outq, 1)
		o.closed = true
		LinesEnd(o)
	end
	if outq[1] then
		pumping = true
		RR.after(3, "recruit ranking lines", PumpOut)
	end
end
local function SendLines(target, list, terminal, guard, limit)
	if #list == 0 and not terminal then return true end
	if #outq >= (limit or RR.QUEUE_MAX) then return Drop("busy") end
	outq[#outq + 1] = { target = target, list = list, i = 1, terminal = terminal, pending = 0, guard = guard }
	if not pumping then PumpOut() end
	return true
end
RR.SendLines = SendLines
function RR.Queued() return #outq end

local catch = { settled = false, last = -math.huge, asked = {}, seq = 0 }
local served = {}

local function NewId()
	catch.seq = (catch.seq + 1) % 46656
	return B36(floor(Clock()) % 60466176) .. B36(catch.seq)
end

-- What changed after the cursor (u, then its row's id), CATCHUP_LINES at most, and the end that proves
-- the page whole: the asker moves its cursor only once every row of it came.
local function AnswerCatchUp(sender, text)
	if not IsKeeper(ns.me) or Off() then return Drop("not keeper") end
	if not IsKeeper(sender) or not LedgerPeer(sender) then return Drop("keeper") end
	local rid, since, tie = text:match("^NE~1~q~([0-9a-z]+)~([0-9a-z]+)~([^~]+)$")
	since = UnB36(since)
	if not rid or #rid > 12 or not since then return Drop("shape") end
	if tie == "-" then tie = nil elseif #tie > 80 or tie:find("[|%c]") then return Drop("shape") end
	local k, t = Key(sender), ns.Now()
	if t - (served[k] or -math.huge) < RR.CATCHUP_GAP then return Drop("ask rate") end
	if not served[k] then Church.Capped(served, Church.HEARD_MAX) end
	served[k] = t
	local l = Led()
	local list = {}
	local function After(u, sid) return u > since or (u == since and tie ~= nil and sid > tie) end
	for id, r in pairs(l.r) do
		local u = tonumber(r.u) or 0
		if After(u, "r:" .. id) then list[#list + 1] = { u = u, sid = "r:" .. id, id = id, v = r } end
	end
	for key, p in pairs(l.p) do
		local u = type(p) == "table" and tonumber(p.u) or 0
		if type(p) == "table" and After(u, "p:" .. key) then list[#list + 1] = { u = u, sid = "p:" .. key, id = key, v = p } end
	end
	for xk, g in pairs(l.gone) do
		local u = type(g) == "table" and (tonumber(g.u) or tonumber(g.t)) or 0
		if type(g) == "table" and g.i and After(u, "g:" .. xk) then list[#list + 1] = { u = u, sid = "g:" .. xk, id = xk, v = g } end
	end
	table.sort(list, function(a, b) if a.u ~= b.u then return a.u < b.u end return a.sid < b.sid end)
	local lines, n, last, lastSid = {}, 0, since, tie
	for i = 1, min(#list, RR.CATCHUP_LINES) do
		local e = list[i]
		local kind = e.sid:sub(1, 1)
		local line = kind == "r" and RR.RecordLine(e.id, e.v) or (kind == "p" and RR.PersonLine(e.id, e.v)) or GoneLine(e.id, e.v)
		local row = ("NE~1~d~%s~%d~%s"):format(rid, n + 1, line:sub(#NE + 1))
		-- (A row past the whisper's size can't go: the page leaves it out, and says so in its count.)
		if #row <= 255 then
			n = n + 1
			lines[n] = row
		else
			Drop("wire size")
		end
		last, lastSid = e.u, e.sid
	end
	local more = #list > RR.CATCHUP_LINES
	local terminal = ("NE~1~e~%s~%d~%s~%s~%s"):format(rid, n, more and "1" or "0", B36(last), lastSid or "-")
	stats.pages = stats.pages + 1
	local guard = function() return IsKeeper(ns.me) and not Off() end
	return SendLines(ns.FullName(sender), lines, terminal, guard)
end

local function AskPage(name, k)
	local l = Led()
	local cur = type(l.from[k]) == "table" and l.from[k] or {}
	local rid = NewId()
	catch.page = { k = k, name = name, rid = rid, at = ns.Now(), got = {}, n = 0 }
	return ns.Comm.Whisper(name, ("NE~1~q~%s~%s~%s"):format(rid, B36(tonumber(cur.t) or 0), cur.id or "-"), nil, false, false, nil, { owner = RR })
end

-- A keeper asks the keeper online it caught up from least lately for what changed (once it heard every
-- keeper online since its login, ChurchCount.SettledSinceLogin), every CATCHUP_EVERY, sooner while a page
-- goes on; one heard to take these records first, one never heard from once a session at most.
function RR.CatchUp(force)
	if not IsKeeper(ns.me) or Off() then return false end
	local t = ns.Now()
	if catch.page then
		if t - catch.page.at < RR.CATCHUP_RETRY then return false end
		catch.page = nil
	end
	if not force and t - catch.last < (catch.settled and RR.CATCHUP_EVERY or RR.CATCHUP_RETRY) then return false end
	if not Count.SettledSinceLogin() then return false end
	local l = Led()
	local pick, at
	for _, o in ipairs(Church.KeepersOnline(false)) do
		local k = Key(o.name)
		local asked = catch.asked[k]
		if k and LedgerPeer(o.name) and (serving[k] or not asked) then
			local seen = max(tonumber(l.caught[k]) or -math.huge, asked or -math.huge)
			if not pick or seen < at then pick, at = o, seen end
		end
	end
	if not pick then return false end
	local k = Key(pick.name)
	catch.last, catch.asked[k] = t, t
	return AskPage(pick.name, k)
end

local function TakePage(sender, text)
	local kind, rid, body = text:match("^NE~1~([de])~([0-9a-z]+)~(.+)$")
	local p = catch.page
	if not kind or not p or p.rid ~= rid or Key(sender) ~= p.k then return Drop("unasked") end
	if kind == "d" then
		local i, row = body:match("^(%d+)~(.+)$")
		i = tonumber(i)
		if not i or i < 1 or i > RR.CATCHUP_LINES or p.got[i] then return Drop("page") end
		p.got[i], p.n = true, p.n + 1
		p.at = ns.Now()
		local _, why = TakeLine(sender, NE .. row)
		return true, why
	end
	local n, more, last, tie = body:match("^(%d+)~([01])~([0-9a-z]+)~(.+)$")
	n, last = tonumber(n), UnB36(last)
	catch.page = nil
	if not n or not last or n > RR.CATCHUP_LINES then return Drop("page") end
	-- (A row lost on the way: the cursor stays, and the same page is asked again later.)
	if p.n ~= n then return Drop("incomplete page") end
	local l = Led()
	if n > 0 or more == "1" then l.from[p.k] = { t = last, id = tie ~= "-" and tie or nil } end
	if more == "1" then
		-- (The next page once the keeper takes another ask from us: CATCHUP_GAP.)
		RR.after(RR.CATCHUP_GAP + 1, "recruit ranking catch-up", function()
			if not catch.page and IsKeeper(ns.me) then catch.last, catch.asked[p.k] = ns.Now(), ns.Now(); AskPage(p.name, p.k) end
		end)
	else
		l.caught[p.k] = ns.Now()
		if not catch.settled then catch.settled = true; ns.Fire("RECRUIT_RANKING_CHANGED") end
	end
	return true
end

-- Caught up this session, or nobody to be behind of: once every keeper online was heard since the login
-- (ChurchCount.SettledSinceLogin), none online that takes these or was not asked yet, or SETTLE_MAX after
-- that at most. (Before, a keeper just logged in would answer its members from a ledger behind the others'.)
function RR.Settled()
	if catch.settled then return true end
	local online = Church.OnlineFor and Church.OnlineFor()
	if online == nil then return true end
	if not Count.SettledSinceLogin() then return false end
	if online >= Church.KEEPER_EVERY * Church.FRESH_FACTOR + RR.SETTLE_MAX then return true end
	for _, o in ipairs(Church.KeepersOnline(false)) do
		local k = Key(o.name)
		if k and (serving[k] or not catch.asked[k]) then return false end
	end
	return true
end

---------------------------------------------------------------------------
-- The ranking (a keeper's own ledger) and the members' asks
---------------------------------------------------------------------------

-- Every person with points in the window, best first: { rank, key, name, score, own, share, joins, stays,
-- passed, pending }. Worked out again when the ledger changed, else once a minute (the windows move).
function RR.Ranking(window)
	local now = Clock()
	local slot = floor(now / 60)
	local c = ranks[window]
	if c and c.rev == rev and c.slot == slot then return c.rows, c.byKey end
	local C, l = RR.Credits(), Led()
	local from = Count.WindowFrom(window, now)
	local agg = {}
	local function A(key, name)
		local a = agg[key]
		if not a then
			a = { key = key, name = name, own = 0, share = 0, joins = 0, stays = 0, passed = 0, pending = 0 }
			agg[key] = a
		end
		if not a.name and name then a.name = name end
		return a
	end
	for id, r in pairs(l.r) do
		local state = C.states[id]
		local by = Key(r.bn)
		if state == "credited" and by then
			local joined = r.tj >= from
			local stayed = r.y == 1 and r.tj + RR.STAY_DAYS * DAY >= from
			if joined or stayed then
				local a = A(by, Short(r.bn))
				local points = (joined and RR.POINTS_JOIN or 0) + (stayed and RR.POINTS_STAY or 0)
				a.own = a.own + points
				if joined then a.joins = a.joins + 1 end
				if stayed then a.stays = a.stays + 1 end
				local sk = SourceKey(r)
				if sk then
					local s = A(sk, Short(r.src))
					s.share = s.share + points * RR.SHARE
					if joined then s.passed = s.passed + 1 end
				end
			end
		elseif state == "pending" and by and r.s and r.tj >= from and not l.own[id] then
			-- (A record another keeper marked with the inviter's own report, not confirmed yet.)
			local a = A(by, Short(r.bn))
			a.pending = a.pending + 1
		end
	end
	-- (Review of 1.5.9) A member's pending recruits: the joins his own addon reported that no witness
	-- confirmed yet (no record, or one still pending).
	for id, o in pairs(l.own) do
		local ik = type(o) == "table" and (tonumber(o.t) or 0) >= from and id:match("^[^:]+:(.+)$")
		local state = ik and C.states[id]
		if ik and (state == nil or state == "pending") then
			local a = A(ik, nil)
			a.pending = a.pending + 1
		end
	end
	if window == "a" then
		for key, p in pairs(l.p) do
			local j, y, h, hy = Totals(p)
			if j > 0 or h > 0 then
				local a = A(key, Short(p.n))
				a.own = a.own + j * RR.POINTS_JOIN + y * RR.POINTS_STAY
				a.joins, a.stays = a.joins + j, a.stays + y
				a.share = a.share + (h * RR.POINTS_JOIN + hy * RR.POINTS_STAY) * RR.SHARE
				a.passed = a.passed + h
			end
		end
	end
	local rows, byKey = {}, {}
	for key, a in pairs(agg) do
		a.score = a.own + a.share
		a.name = a.name or key
		byKey[key] = a
		if a.score > 0 then rows[#rows + 1] = a end
	end
	table.sort(rows, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		if a.joins ~= b.joins then return a.joins > b.joins end
		if a.passed ~= b.passed then return a.passed > b.passed end
		return a.key < b.key
	end)
	for i, row in ipairs(rows) do row.rank = i end
	ranks[window] = { rev = rev, slot = slot, rows = rows, byKey = byKey }
	return rows, byKey
end

local WINDOWS = { w = true, m = true, a = true }
local answersTo = {}

local function RowText(rid, row)
	return ("NE~1~o~%s~%d~%s~%d~%d~%d~%d~%d~%d"):format(rid, row.rank, Short(row.name) or row.key, Hundred(row.score), Hundred(row.own),
		Hundred(row.share), row.joins, row.stays, row.passed)
end

-- (Review of 1.5.9) An asker this keeper places in an Olympus guild: the guild his ask names is one, and
-- nothing this keeper knows of him names another (its own roster; the guild his own Olympus messages
-- named, Moderation.GuildOf and Data.ClaimedGuild; his Church presence). Where the channel carries no
-- addon words (Forever), a keeper hears nothing of most members of other guilds: an asker it knows
-- nothing of is taken at his word. The rows are names and points, the load is bounded below.
local function Placed(sender, guild)
	if not guild or not ns.IsFederation(guild) then return false end
	local who = ns.FullName(sender)
	local R = ns.Roster
	if R and R.RankOf and R.RankOf(who) ~= nil then return Same(OwnGuild(), guild) end
	local M, D = ns.Moderation, ns.Data
	local heard = Church.Heard()[Key(who) or ""]
	local known = { M and M.GuildOf and M.GuildOf(who) or nil, D and D.ClaimedGuild and D.ClaimedGuild(who) or nil,
		type(heard) == "table" and heard.guild or nil }
	for i = 1, 3 do
		if type(known[i]) == "string" and known[i] ~= "" and not Same(known[i], guild) then return false end
	end
	return true
end
RR.Placed = Placed

-- A member's ask (anyone in Olympus: the ranking is everyone's): the top RANK_ROWS and his own row.
-- (Review of 1.5.9) ANSWERS_PER to one asker and ANSWERS_ALL to all in ANSWER_WINDOW, on this file's
-- own queue (SendLines): a busy keeper drops the ask, and the asker's page asks the next keeper.
local answeredAll = {}
local function Answer(sender, text)
	if not IsKeeper(ns.me) or Off() or not ns.IsMember() then return Drop("not keeper") end
	local rid, window, guild = text:match("^NE~1~a~([0-9a-z]+)~([wma])~([^~]+)$")
	if not rid or #rid > 12 then return Drop("shape") end
	if not LedgerPeer(sender) then return Drop("scope") end
	local M = ns.Moderation
	if M and M.Hides and M.Hides(sender, nil) then return Drop("netoff") end
	if not Placed(sender, CleanGuild(guild)) then return Drop("member") end
	if not RR.Settled() then return Drop("catching up") end
	local t, k = ns.Now(), Key(sender)
	if not k then return Drop("shape") end
	for i = #answeredAll, 1, -1 do if t - answeredAll[i] >= RR.ANSWER_WINDOW then table.remove(answeredAll, i) end end
	if #answeredAll >= RR.ANSWERS_ALL or #outq >= RR.QUEUE_ASKS then return Drop("busy") end
	if not answersTo[k] then Church.Capped(answersTo, RR.PEOPLE_MAX) end
	local h = answersTo[k] or {}
	answersTo[k] = h
	for i = #h, 1, -1 do if t - h[i] >= RR.ANSWER_WINDOW then table.remove(h, i) end end
	if #h >= RR.ANSWERS_PER then return Drop("ask rate") end
	local rows, byKey = RR.Ranking(window)
	local lines = {}
	for i, row in ipairs(rows) do
		if i <= RR.RANK_ROWS or row.key == k then lines[#lines + 1] = RowText(rid, row) end
	end
	local mine = byKey[k]
	lines[#lines + 1] = ("NE~1~n~%s~%d~%d~%s~%d"):format(rid, #lines, #rows, B36(Clock()), mine and mine.pending or 0)
	if not SendLines(ns.FullName(sender), lines, nil, function() return IsKeeper(ns.me) and not Off() end, RR.QUEUE_ASKS) then
		return false, "busy"
	end
	h[#h + 1], answeredAll[#answeredAll + 1] = t, t
	stats.answers = stats.answers + 1
	return true
end

local asks = {}

-- Asks a keeper online for the window's ranking: one heard to take these first, the next one after a
-- silent one; ASK_GAP apart, RANK_REFRESH after a complete answer (force: the Refresh button, still
-- ASK_GAP apart). The King's client asks only while his Church page shows it (ChurchView.PollRanking),
-- as for the Church's pages. (Review of 1.5.9: every member asked the first keeper by name. A member's
-- keepers start at a place his own name picks among those heard to take these: the asks spread.)
function RR.Ask(window, force)
	if not WINDOWS[window] or Off() or not ns.IsMember() then return false end
	local guild = CleanGuild(OwnGuild())
	if not guild or not ns.IsFederation(guild) then return false end
	local t, previous = ns.Now(), asks[window]
	if previous then
		local elapsed = t - previous.t
		if elapsed < RR.ASK_GAP then return false, "gap" end
		if previous.complete and not force and elapsed < RR.RANK_REFRESH then return false, "gap" end
	end
	local heard, others = {}, {}
	for _, o in ipairs(Church.KeepersOnline(false)) do
		local list = Serving(o.name) and heard or others
		list[#list + 1] = o
	end
	if #heard + #others == 0 then Church.FindKeeper(); return false, "no keeper" end
	local function ByKey(a, b) return (Key(a.name) or "") < (Key(b.name) or "") end
	table.sort(heard, ByKey)
	table.sort(others, ByKey)
	local keepers = {}
	local start = #heard > 0 and floor(RR.score(Key(ns.me) or "", "ask") * #heard) or 0
	for i = 1, #heard do keepers[i] = heard[(start + i - 1) % #heard + 1] end
	for _, o in ipairs(others) do keepers[#keepers + 1] = o end
	local first = 1
	if previous and not previous.complete then
		for i, o in ipairs(keepers) do if Key(o.name) == previous.k then first = i % #keepers + 1; break end end
	end
	local keeper = keepers[first]
	local a = { k = Key(keeper.name), rid = NewId(), t = t, expires = t + RR.ASK_WINDOW, rows = {}, seen = {} }
	asks[window] = a
	return ns.Comm.Whisper(keeper.name, ("NE~1~a~%s~%s~%s"):format(a.rid, window, guild), nil, false, false, nil, { owner = RR,
		guard = function() return asks[window] == a and ns.Now() < a.expires end })
end

local function TakeAnswerLine(sender, text)
	local kind, rid, body = text:match("^NE~1~([on])~([0-9a-z]+)~(.+)$")
	if not kind then return Drop("shape") end
	local window, a
	for w, x in pairs(asks) do if x.rid == rid then window, a = w, x end end
	if not a or a.complete or a.k ~= Key(sender) or ns.Now() >= a.expires then return Drop("unasked") end
	if kind == "o" then
		local rank, name, score, own, share, joins, stays, passed = body:match("^(%d+)~([^~]+)~(%d+)~(%d+)~(%d+)~(%d+)~(%d+)~(%d+)$")
		rank = tonumber(rank)
		local who = WireName(name)
		if not rank or rank < 1 or not who then return Drop("shape") end
		if a.seen[rank] or #a.rows > RR.RANK_ROWS + 1 then return Drop("page") end
		a.seen[rank] = true
		a.rows[#a.rows + 1] = { rank = rank, name = Short(who), key = Key(who), score = tonumber(score) / 100, own = tonumber(own) / 100,
			share = tonumber(share) / 100, joins = tonumber(joins), stays = tonumber(stays), passed = tonumber(passed) }
		return true
	end
	local n, ranked, asOf, pending = body:match("^(%d+)~(%d+)~([0-9a-z]+)~(%d+)$")
	n, ranked, asOf, pending = tonumber(n), tonumber(ranked), UnB36(asOf), tonumber(pending)
	local rows = a.rows
	a.rows, a.seen = {}, {}
	if not n or not asOf or n ~= #rows then return Drop("incomplete page") end
	if asOf > Clock() + Church.DATE_AHEAD then return Drop("page time") end
	local views = Views()
	local v = views and views[window]
	if type(v) == "table" and asOf < (tonumber(v.asOf) or 0) then return Drop("older page") end
	table.sort(rows, function(x, y) return x.rank < y.rank end)
	a.complete = true
	views[window] = { rows = rows, asOf = asOf, from = ns.ShortName(sender), ranked = ranked, pending = pending }
	ns.Fire("RECRUIT_RANKING_CHANGED")
	return true
end

local function Joins(rows)
	local n = 0
	for _, row in ipairs(rows or {}) do n = n + (tonumber(row.joins) or 0) end
	return n
end

-- What the page shows: a keeper's own ledger (another keeper's answer while it counts more: one behind
-- on its catch-up), else the last answer kept. Returns rows, as of, from another client, waiting, who
-- answered, this player's own row, how many are ranked, this player's pending recruits.
function RR.RankingView(window)
	local me = Key(ns.me)
	local a = asks[window]
	local waiting = a ~= nil and not a.complete and ns.Now() < a.expires
	local v = (Views() or {})[window]
	v = type(v) == "table" and type(v.rows) == "table" and v or nil
	if IsKeeper(ns.me) then
		local rows, byKey = RR.Ranking(window)
		if not (v and Joins(v.rows) > Joins(rows)) then
			local mine = byKey[me]
			return rows, Clock(), false, not RR.Settled(), nil, mine and mine.score > 0 and mine or nil, #rows, mine and mine.pending or 0
		end
	end
	if not v then return {}, nil, true, waiting, nil, nil, 0, 0 end
	local mine
	for _, row in ipairs(v.rows) do if row.key == me then mine = row end end
	return v.rows, v.asOf, true, waiting, v.from, mine, tonumber(v.ranked) or #v.rows, tonumber(v.pending) or 0
end

---------------------------------------------------------------------------
-- Receiving, upkeep
---------------------------------------------------------------------------

function RR.Receive(dist, sender, text)
	if type(text) ~= "string" or type(sender) ~= "string" then return end
	if dist ~= "WHISPER" then return Drop("lane") end
	if #text > 255 then return Drop("size") end
	local version, kind = text:match("^NE~([^~]+)~(%a)~")
	if version ~= "1" then return Drop("version") end
	sender = ns.FullName(sender)
	if IsKeeper(sender) then
		local k = Key(sender)
		if k then
			if not serving[k] then Church.Capped(serving, Church.HEARD_MAX) end
			serving[k] = ns.Now()
		end
	end
	if kind == "w" or kind == "y" or kind == "h" then
		local ok, why = RR.TakeEvidence(sender, text)
		RR.Receipt(sender, text, ok, why)
		return ok, why
	elseif kind == "k" or kind == "x" or kind == "l" then return TakeReceipt(sender, text)
	elseif kind == "r" or kind == "p" or kind == "g" then return TakeLine(sender, text)
	elseif kind == "q" then return AnswerCatchUp(sender, text)
	elseif kind == "d" or kind == "e" then return TakePage(sender, text)
	elseif kind == "a" then return Answer(sender, text)
	elseif kind == "o" or kind == "n" then return TakeAnswerLine(sender, text)
	end
	return Drop("kind")
end
ns.Comm.Handle("NE", function(dist, sender, text) RR.Receive(dist, sender, text) end)

-- Records past RECORDS_DAYS fold into their people's totals; marks past GONE_DAYS (GONE_MAX at most,
-- the oldest first) go. True when anything went.
function RR.Prune()
	local l, now = Led(), Clock()
	local C = RR.Credits()
	local changed = false
	for id, r in pairs(l.r) do
		if TooOld(r, now) then
			if C.states[id] == "credited" then Fold(l, id, r, now) end
			l.r[id] = nil
			l.n = max(0, (l.n or 0) - 1)
			changed = true
		end
	end
	-- (Review of 1.5.9) The inviters' own reports and the passers' words, OWN_DAYS.
	for _, which in ipairs({ "own", "hand" }) do
		for id, e in pairs(l[which]) do
			if type(e) ~= "table" or now - (tonumber(e.at) or 0) > RR.OWN_DAYS * DAY then l[which][id], changed = nil, true end
		end
	end
	local marks = {}
	for xk, g in pairs(l.gone) do
		local t = type(g) == "table" and tonumber(g.t) or nil
		if not t or now - t > RR.GONE_DAYS * DAY then l.gone[xk], changed = nil, true else marks[#marks + 1] = { k = xk, t = t } end
	end
	if #marks > RR.GONE_MAX then
		table.sort(marks, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.k < b.k end)
		for i = 1, #marks - RR.GONE_MAX do l.gone[marks[i].k] = nil end
		changed = true
	end
	if changed then Changed() end
	return changed
end

-- The saved data, checked once at load: a record that does not read back goes alone; the count is made again.
function RR.CheckSaved()
	local s = Store()
	if not s then return end
	local l = s.led
	if l ~= nil then
		if type(l) ~= "table" or l.v ~= 1 or type(l.r) ~= "table" or type(l.p) ~= "table" or type(l.gone) ~= "table" or type(l.from) ~= "table" then
			s.led = nil
		else
			local bad, n = {}, 0
			for id, r in pairs(l.r) do
				local ok, line = false, nil
				if ValidRecord(r) then ok, line = pcall(RR.RecordLine, id, r) end
				local pid = ok and ParseRecord(line) or nil
				if pid ~= id then bad[#bad + 1] = id else n = n + 1 end
			end
			for _, id in ipairs(bad) do l.r[id] = nil end
			l.n = n
			for k, p in pairs(l.p) do if type(p) ~= "table" then l.p[k] = nil end end
			if type(l.caught) ~= "table" then l.caught = {} end
			-- (Review of 1.5.9) The side tables: an entry of the wrong shape goes alone.
			for _, which in ipairs({ "own", "hand" }) do
				if type(l[which]) ~= "table" then l[which] = {} end
				for id, e in pairs(l[which]) do
					local ok = type(id) == "string" and id:find(":", 1, true) and type(e) == "table" and type(e.at) == "number"
						and (e.t == nil or type(e.t) == "number") and (e.src == nil or type(e.src) == "string")
						and (which == "own" or type(e.by) == "string")
					if not ok then l[which][id] = nil end
				end
			end
		end
	end
	for _, key in ipairs({ "out", "src", "seen", "view", "told" }) do
		if s[key] ~= nil and type(s[key]) ~= "table" then s[key] = nil end
	end
	if type(s.out) == "table" and #s.out > RR.OUTBOX_MAX then s.out = nil end
	Changed()
end

local lastDue, lastKeeperDue, nextPrune = -math.huge, -math.huge, nil
-- ChurchCount.Tick's, every Church.TICK: the outbox, the stays this client owes, and on a keeper the
-- catch-up, its own checks and its upkeep. Nothing on the King's client (no background ledger work).
function RR.Tick(now)
	if not ns.IsMember() or Off() or Church.IsKing(ns.me) then return end
	local t = ns.Now()
	if #(Out() or {}) > 0 then RR.Flush() end
	if t - lastDue >= RR.DUE_EVERY then
		lastDue = t
		StayReports()
	end
	if IsKeeper(ns.me) then
		RR.CatchUp(false)
		if t - lastKeeperDue >= RR.DUE_EVERY then
			lastKeeperDue = t
			KeeperChecks()
		end
		nextPrune = nextPrune or t + Count.PRUNE_AFTER
		if t >= nextPrune then nextPrune = t + 3600; RR.Prune() end
	end
end

function RR.Stats() return stats end

function RR.StatusLines()
	local l = Led()
	local p, g = 0, 0
	for _ in pairs(l.p) do p = p + 1 end
	for _ in pairs(l.gone) do g = g + 1 end
	local dropped = {}
	for why, n in pairs(stats.dropped) do dropped[#dropped + 1] = why .. "=" .. n end
	table.sort(dropped)
	local keepers, own, hand, waiting = 0, 0, 0, 0
	for _ in pairs(serving) do keepers = keepers + 1 end
	for _, o in ipairs(Out() or {}) do if type(o) == "table" and o.by == Key(ns.me) then waiting = waiting + 1 end end
	for _ in pairs(l.own) do own = own + 1 end
	for _ in pairs(l.hand) do hand = hand + 1 end
	return {
		("recruiting ranking (everyone): pairs read %d, reported %d, stays told %d, sent %d, outbox %d (%d of this character's), receipts %d"):format(
			stats.pairs, stats.reported, stats.stays, stats.sent, #(Out() or {}), waiting, stats.receipts),
		("ranking ledger %d records, %d people, %d marks, taken %d, pushed %d, lines %d, pages %d, answers %d, folded %d, keepers serving %d, settled %s"):format(
			l.n or 0, p, g, stats.taken, stats.pushed, stats.lines, stats.pages, stats.answers, stats.folded, keepers, tostring(RR.Settled())),
		("ranking side: inviters' own reports %d, passers' words %d, lines waiting %d"):format(own, hand, #outq),
		"ranking dropped: " .. (#dropped > 0 and table.concat(dropped, ", ") or "-"),
	}
end

function RR.ResetForTests()
	catch = { settled = false, last = -math.huge, asked = {}, seq = 0 }
	wipe(served); wipe(serving); wipe(answersTo); wipe(asks); wipe(rates); wipe(owed); wipe(rechecked)
	wipe(outq); wipe(answeredAll)
	keeperHere = { generation = nil, guild = nil, found = false }
	recheckedN, pumping = 0, false
	owing, lastDue, lastKeeperDue, nextPrune = false, -math.huge, -math.huge, nil
	stats.dropped = {}
	Changed()
end

ns.On("INIT", function() RR.CheckSaved() end)
