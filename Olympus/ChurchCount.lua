local ADDON, ns = ...
local L = ns.L

-- The Missionary Church of Olympus (1.1.6): counting the people the Church brings into Olympus,
-- the points, the rankings and the public view. Places and their trust are Church.lua's.
--
-- How a recruit is counted, with nobody doing anything:
-- - Reading the guild's log. A Church person's own client, a keeper's (1.5.5: the author's too), and
--   about two drawn clients of each guild where a Church person was heard over GUILD lately or (1.5.5)
--   whose roster holds one by their own book, read their own guild's event log every
--   READ_EVERY: QueryGuildEventLog(), then GUILD_EVENT_LOG_UPDATE, GetNumGuildEvents() and
--   GetGuildEventInfo(i) -> type, player1, player2, rank, years, months, days, hours ago (Forever's
--   Blizzard_Communities/GuildInfo.lua reads them the same way). Never in combat, never on the
--   King's screen, never while the game holds addon messages, at most every READ_GAP; no Blizzard
--   frame is opened or touched. An invite by a Church person followed by the invitee's join within
--   PAIR_HOURS is whispered to every keeper heard online (an outbox keeps it otherwise).
-- - Pending or confirmed. The recruiter's own report leaves a record pending; it is confirmed once a
--   client other than his, his linked alts' (Alts.Linked) and the recruit's reported the same pair
--   from its own read of the log, and the keeper can vouch for that client in the pair's guild
--   (1.2.1, VerifiedWitness: a whisper from anyone else is not taken, nor a plain guildmate's of a recruit
--   the keeper's own roster or log never showed; the keeper that vouched tells the others, Count.Push and
--   the catch-up). (A seen-check answer that places the recruit in the guild shows
--   he is there, not who invited him: it confirms a registration's arrival, never an invite.)
-- - New to Olympus. Every client keeps a memory of its own guild's roster (first and last day each
--   name was seen). The desk (Church.Desk) asks the channel about each new recruit once
--   (NS~1~q); clients that knew him answer by whisper. One seen in another Olympus guild in the
--   NEW_DAYS before his join, or in the same guild before the invite, is a transfer: never credited.
-- - Registered recruits ("I brought this player"): a Church person registers a name (1.2.1: dated when a
--   keeper hears it, and refused while another's invite holds that player); it counts when
--   that player shows up in an Olympus guild within REG_DAYS (a seen-check answer from another
--   client), and never for a player already in Olympus.
-- - One recruit counts for one person only: the earliest valid invite or registration, a
--   confirmed one before one only its recruiter's own client stands behind.
-- - Still in after STAY_DAYS: the desk asks again then (three tries).
--
-- Points, in game only (no gold or money anywhere): POINTS_JOIN for each confirmed recruit, dated
-- at his join; POINTS_STAY more when he is still in Olympus STAY_DAYS later, dated then. A person's
-- score is his own points plus SHARES of the OWN points of the missionaries under him: 25% of the
-- first level, 10% of the second, 5% of the third, nothing deeper, never compounded. So someone
-- below who brings more people in outscores the one above him. An Apostle's network score is the
-- same sum over his network. Windows: this week (Dues.WeekOf), the last 30 days, all time.
--
-- Who sees what: the numbers go only to the audience (Church.InAudience), by whisper from a
-- keeper; a person's detail only to himself, the Head, the Apostles, the High Council, the King
-- and the author. The public view: while the author's switch is open, the desk broadcasts the
-- rows of the people who chose to show theirs (off by default), and the author's client the top 3
-- of each ranking (Count.Top3; 1.2.3: the missionaries' is their crook, HonorsNet).
--
-- The wire (whole messages, version 1, dropped unread by clients before 1.1.6):
--   NV~1~w~<inviter>~<invitee>~<guild>~<invite hour36>~<join hour36>   a log pair  -> keepers
--   NV~1~g~<recruit>~<at36>   a registration   NV~1~x~<recruit>~<at36>   its withdrawal  -> keepers
--   NV~1~o~<0|1>~<at36>       my row in the public view (off by default)               -> keepers
--   NV~1~k~<h1,h2,...>   (1.2.1) a keeper's receipt for the reports it took (Comm.Hash36 of each text,
--                        RECEIPT_IDS at most) -> their reporter; clients before 1.2.1 drop it
--   NV~1~l~1             (1.2.1) a keeper refused some of this reporter's reports for now (Count.LATER): the
--                        ones he has not had a receipt for go to it again -> their reporter
--                        (neither ever to a keeper: one before 1.2.1 counts each against its budget for him)
--   NS~1~q~<id36>~<name>~<j|r|7>    the desk's seen-check, CHANNEL (j: new to Olympus? r: arrived for
--                                   a registration? 7: still in?)
--   NS~1~a~<id36>~<guild>~<first day36>~<last day36>~<now 0|1>   an answer from roster memory -> desk
--   NL~1~q~<since36>   a keeper asks another for the records changed after `since` (its clock)
--   NL~1~r~<recruit>~<recruiter>~<guild|->~<i|g>~<tc36>~<tj36|->~<flags>~<sources|->~<u36>
--       a record; flags: s own report, t transfer, a alt, x withdrawn, c new-check done, y/n still in
--       after 7 days, digits: tries; sources: up to two independent witnesses
--   NL~1~p~<person>~<0|1>~<at36>~<points>~<joins>~<stays>~<u36>   his public choice, his archive
--   NL~1~z~<recruit>~<recruiter>~<tj36>~<y 0|1>~<u36>   (1.2.1) a credited record a ledger archived to
--       make room, while a window still counts it (Count.TakeArchived); clients before 1.2.1 drop it
--   NL~1~e~<more 0|1>~<u36>   the end of a catch-up
--   Forever NL~2~q~<id>~<family:faction>~<u36>~<cutoff36|0>~<tie|-> starts a bounded, direct catch-up page.
--   NL~2~a~<id>, NL~2~d~<id>~<index>~<v1 row after its version>, NL~2~e~<id>~<count>~<more>~<u36>~<cutoff36>~<tie|->
--       acknowledge it, deliver rows and prove completeness before advancing the cursor.
--   NR~1~q~<a|m|c|u|me|p>~<w|m|a>~<person|->   an audience client asks a keeper (1.5.8 u: the recruiters,
--                        asked and answered for the author, the King and the High Council only, the
--                        author's keeper client asking too; before 1.5.8 a keeper drops it, and the
--                        page asks the next one)
--   NR~1~r~<list>~<window>~<rank>~<name>~<score*10>~<own*10>~<share*10>~<recruits>~<stays>~<network>~<pub>
--   NR~1~m~<me|p>~<window>~<person>~<line>~<a>~<b>~<c>~<d>   a detail line (Count.DetailLines)
--   NR~1~e~<what>~<window>~<person|->~<lines>~<asOf36>   the end of an answer
--   NR~1~p~<switch at36>~<a|m>~<rank>~<name>~<30 days*10>~<all*10>   public rows, CHANNEL
--   NR~1~n~<switch at36>~<a|m>~<rows>   the end of one list's public rows (0: none shows now), CHANNEL
--   NR~1~t~<at36>~<a1,a2,a3|->~<m1,m2,m3|->   the top 3 (last 30 days), CHANNEL and GUILD, taken from
--       the Head's, the King's or the author's client, and (1.3.4) a signed High Councillor's; worked
--       out by the author's alone (SendTop), said again as it is by the King's and the High Council's
--       (Count.RelayTop), never by an Apostle's (Apostles rank Apostles)

local Count = {}
ns.ChurchCount = Count
local Church = ns.Church

Count.READ_EVERY, Count.READ_GAP, Count.EVENTS_MAX = 300, 60, 500
Count.PAIR_HOURS = 48
Count.CLAIM_KEEP = 7 * 86400
Count.MEMORY_MAX, Count.MEMORY_DAYS, Count.GUILDS_MAX = 2500, 120, 64
-- (1.2.1: invites remembered for their join, 1500, not 300, and the oldest go first: past 300 in two days
-- of a busy guild's, all of them went, and a join read after its invite was no pair.)
Count.EV_MAX, Count.EV_DAYS, Count.INV_MAX, Count.ATT_MAX, Count.ATT_DAYS = 3000, 8, 1500, 500, 14
-- (1.2.1: 1500 reports, not 40: each waits here until a keeper's receipt, NV k, a busy Apostle's day of
-- invites with them. One a keeper refused for now, NV l, goes to that keeper again RESEND_GAP after it last
-- did, RESEND_TRIES sends to each keeper at most.)
Count.OUTBOX_MAX, Count.OUTBOX_DAYS = 1500, 7
Count.RESEND_GAP, Count.RESEND_TRIES = 3600, 4
Count.RECEIPT_GAP, Count.RECEIPT_IDS = 5, 24
-- (1.2.1: 6000 records, not 2000. One Apostle alone held 1316 within days of the Church opening, and
-- a record must stay in the ledger for its 7-day stay check.)
Count.RECORDS_MAX, Count.RECORDS_DAYS, Count.PEOPLE_MAX = 6000, 120, 400
Count.MONTH_DAYS = 30 -- the "last 30 days" window (WindowFrom)
-- (1.2.1: the ledger's marks of what it let go are kept RECORDS_DAYS, as long as a keeper's line could
-- bring one back; this many at most only against a flood, far past a busy Church's 120 days.)
-- (1.2.3: not fewer. A full ledger lets go a record for each one it takes, a mark for each credited one
-- or transfer: a Church taking a few hundred a day makes tens of thousands in RECORDS_DAYS, and a mark
-- let go early lets its recruit count again. Count.Prune lists them only when they are past this many.)
Count.GONE_MAX = 100000
Count.REG_DAYS, Count.REG_OPEN, Count.REG_ALL = 14, 15, 300
Count.REG_CHECKS = { 0, 1, 3, 7, 14 }
Count.REG_LATE = 7  -- a registration's check the desk missed on its day still runs this many days later
-- What a keeper takes from one sender an hour and a day. (1.2.1: every report counts against the larger
-- budget, sized for an Apostle's several hundred invites a day, each reported by his own client and by his
-- guild's witnesses; one only the recruiter's alt stands behind against the smaller one too. 30 and 100
-- for everyone cost the busiest Apostle most of his confirmations.)
Count.EVIDENCE_HOUR, Count.EVIDENCE_DAY = 30, 100
Count.VERIFIED_HOUR, Count.VERIFIED_DAY = 300, 2000
Count.NEW_DAYS = 90
Count.CHECK_TTL, Count.CHECK_ANSWERS, Count.CHECKS_HOUR, Count.CHECKS_HEARD_HOUR = 600, 8, 30, 60
-- (1.2.3: the desk sends CHECKS_TICK checks a tick at most, so the hour's CHECKS_HOUR go out within five
-- minutes. Just logged in, it sent all thirty in its first tick, each with its own list of who may answer
-- walked from the 1,000-row roster: a fifth of a second and 5 MB of garbage on the author's laptop.)
Count.CHECKS_TICK = 3
-- (1.2.3) Which checks are due is looked for again when the ledger changed, else DUE_EVERY; the credits
-- are kept CREDITS_KEEP at most while the ledger does not change (Count.Credits).
Count.DUE_EVERY, Count.CREDITS_KEEP = 600, 600
-- (1.2.3) The ledger's first upkeep of a session, PRUNE_AFTER to PRUNE_AFTER + PRUNE_SPREAD after its first
-- tick (it came with the login's other work), then hourly.
Count.PRUNE_AFTER, Count.PRUNE_SPREAD = 300, 600
Count.STAY_DAYS, Count.STAY_TRIES = 7, 3
Count.POINTS_JOIN, Count.POINTS_STAY = 10, 5
Count.SHARES = { 0.25, 0.10, 0.05 }
Count.RANK_ROWS, Count.PUBLIC_ROWS = 25, 10
Count.PUBLIC_EVERY, Count.PUBLIC_FRESH, Count.TOP_EVERY = 1800, 7200, 1800
-- (1.3.4) The top 3's relays (Count.RelayTop): the first say TOP_FIRST after the first tick of a session,
-- then TOP_EVERY + TOP_GRACE after the last word heard (the same or a newer one) or said, TOP_JITTER at
-- random more; the King's TOP_KING_AFTER more again, so his goes last. (TOP_GRACE: the author's client
-- says its word every TOP_EVERY, a tick late at most: it speaks first, and no relay with it.) TOP_MAX_AGE:
-- a word older than this names nobody (Honors.CHURCH_MAX_AGE's).
Count.TOP_FIRST, Count.TOP_GRACE, Count.TOP_JITTER, Count.TOP_KING_AFTER, Count.TOP_MAX_AGE = 300, 120, 300, 480, 30 * 86400
Count.ASK_GAP, Count.ANSWERS_PER, Count.ANSWER_WINDOW = 60, 12, 300
Count.RANK_REFRESH = 300 -- a complete board needs fewer whispers than a failed first load
Count.CATCHUP_EVERY, Count.CATCHUP_LINES = 1800, 150
-- A silent active keeper is retried through another source after CATCHUP_RETRY, even after a
-- previous successful catch-up. A completed source sweeps the others; CATCHUP_REASK bounds each
-- source across those attempts and reloads.
Count.CATCHUP_RETRY, Count.CATCHUP_REASK = 120, 600
Count.CATCHUP_V2_MAX, Count.CATCHUP_LEGACY_WAIT = 150, 45
local LEDGER_WHISPER_BYTES = 255
-- (1.2.1) Just logged in, a keeper answers no audience ask, nor another keeper's catch-up ask, until its
-- first catch-up ends: its ledger missed what came while it was away. It waits to hear every keeper
-- online first (Count.SettledSinceLogin); with none heard by then, it is settled without one, else
-- SETTLE_MAX after that wait at most (Count.Settled). Nor does the desk send the public rows until
-- then (Count.SendPublic), and its own tab says it is catching up (Count.RankingView).
Count.SETTLE_MAX = 900
Count.SEND_ROOM = 20

Count.after = function(seconds, where, fn) ns.After(seconds, where, fn) end
Count.random = function(a, b) return math.random(a, b) end
Count.chance = function() return math.random() end

local Key, B36, UnB36, WireName, CleanGuild = Church.Key, Church.B36, Church.UnB36, Church.WireName, Church.CleanGuild
local Clock, OwnGuild = Church.Clock, Church.OwnGuild
local DAY = 86400

local stats = { reads = 0, events = 0, pairs = 0, sent = 0, queued = 0, taken = 0, checks = 0, answers = 0, dropped = {} }
local lastRead, lastReadTick, registered = -math.huge, -math.huge, false
local lastGeneration
local evidenceRate = {}     -- sender key -> { hour, n, day, d }
local checks, checkTimes, nextCheck = {}, {}, 0
local heardChecks = {}      -- keeper key -> { times }
local asks = {}             -- page -> the keeper asked, when, and rows staged for that reply
local answersTo = {}        -- asker key -> { times }
local catch = { asked = {}, last = -math.huge, heard = -math.huge, settled = false } -- heard: a line from the active keeper only
local lastPublic, lastTop, lastPublicAt = -math.huge, -math.huge, nil
local topHeard, topRelayAt = nil, nil -- (1.3.4) when the last same-or-newer top 3 was heard; our next relay
local outq = {}             -- line transfers waiting, one target each: { target, list, i }
local credits                -- cached per ledger revision
local ledRev = 0

local function Drop(why)
	stats.dropped[why] = (stats.dropped[why] or 0) + 1
	return false, why
end
local function Day(t) return math.floor((tonumber(t) or 0) / DAY) end
local function Short(name) return name and ns.ShortName(ns.Normal(name)) or nil end
local function Off()
	local M = ns.Moderation
	return M and M.SelfOff and M.SelfOff() or nil
end
local function Changed()
	ledRev = ledRev + 1
	credits = nil
	ns.Fire("CHURCH_COUNT_CHANGED")
end
Count.Changed = Changed
-- (1.2.3) What only the tab shows changed (an answer kept, the public rows): the ledger did not, and
-- its credits stay.
local function ViewChanged() ns.Fire("CHURCH_COUNT_CHANGED") end

---------------------------------------------------------------------------
-- Saved data (ns.rdb.church)
---------------------------------------------------------------------------

local function Sub(key, make)
	local c = Church.Store()
	if not c then return nil end
	if type(c[key]) ~= "table" then c[key] = make() end
	return c[key]
end
local function Mem() return Sub("mem", function() return { g = {}, n = {}, count = 0 } end) end
local function Ev() return Sub("ev", function() return { k = {}, n = 0 } end) end
local function Inv() return Sub("inv", function() return {} end) end
local function Att() return Sub("att", function() return {} end) end
local function Out() return Sub("out", function() return {} end) end
local function Claims() return Sub("claims", function() return {} end) end
local function Fills() return Sub("fill", function() return {} end) end
local function View() return Sub("view", function() return {} end) end
-- A keeper's ledger is led; any other client's copy of the keepers' word is copy. (One account's
-- characters of a realm group share ns.rdb: a council character's copy, which takes a council relay's
-- lines too, was its Apostle alt's ledger, and went from there to every keeper. A keeper reads no line
-- taken while not one.) Its credits are worked out again when the one read changes (a role taken or
-- lost this session). (Which one is looked for once a second at most, and again when the Church's state
-- or the data changed: Own, Credits, Arc and PublicOf read the ledger for each person of a ranking, and
-- asking for this client's role each time cost a 1,000-person ranking about a fifth of a second.)
local LEDGERS = { led = true, copy = true }
local ledWhich, ledAt
local function Led()
	local t = ns.Now()
	if t ~= ledAt or not ledWhich then
		ledAt = t
		local which = Church.IsKeeper(ns.me) and "led" or "copy"
		if which ~= ledWhich then ledWhich, ledRev, credits = which, ledRev + 1, nil end
	end
	local which = ledWhich
	-- (wv 2: its archive keeps each record's join, 1.2.1's Archive: a new ledger's from the start.)
	local l = Sub(which, function() return { v = 1, wv = 2, r = {}, p = {}, from = {} } end)
	if l and (l.v ~= 1 or type(l.r) ~= "table" or type(l.p) ~= "table" or type(l.from) ~= "table") then
		local c = Church.Store()
		c[which] = { v = 1, wv = 2, r = {}, p = {}, from = {} }
		l = c[which]
	end
	return l
end
Count.Led = Led
ns.On("CHURCH_CHANGED", function() ledAt = nil end)
ns.On("DATA_CHANGED", function() ledAt = nil end)
-- This character's own: { pub, pubAt, regs = { [key] = { n, at } }, inv = { [day] = n } }.
local function Mine()
	local me = Sub("me", function() return {} end)
	if not me then return nil end
	local k = Key(ns.me) or "?"
	if type(me[k]) ~= "table" then me[k] = { regs = {}, inv = {} } end
	local m = me[k]
	if type(m.regs) ~= "table" then m.regs = {} end
	if type(m.inv) ~= "table" then m.inv = {} end
	return m
end
Count.Mine = Mine

---------------------------------------------------------------------------
-- The roster memory: who this client saw in its own guild, and when
---------------------------------------------------------------------------

local function GuildIndex(mem, guild)
	for i, g in ipairs(mem.g) do if g == guild then return i end end
	if #mem.g >= Count.GUILDS_MAX then table.remove(mem.g, 1) end
	mem.g[#mem.g + 1] = guild
	return #mem.g
end
local function ReadMem(v)
	if type(v) ~= "string" then return nil end
	local gi, first, last = v:match("^(%d+):([0-9a-z]+):([0-9a-z]+)$")
	return tonumber(gi), UnB36(first), UnB36(last)
end

-- (1.2.3) The names already written today in this guild of this memory, each as it is there: every roster
-- scan, about every minute, wrote all thousand of them again the same. A new day, guild or memory starts
-- over; a name the bounding below lets go is written again.
local written = { keys = {} }

-- After each complete scan of our roster (once per generation): every member's first and last day.
function Count.Remember(force)
	local R = ns.Roster
	if not (R and R.complete == true and type(R.members) == "table") then return false end
	local guild = OwnGuild()
	if not guild or R.guild ~= guild or not ns.IsFederation(guild) then return false end
	if not force and R.generation == lastGeneration then return false end
	lastGeneration = R.generation
	local mem = Mem()
	local gi = GuildIndex(mem, guild)
	local today = Day(Clock())
	if written.day ~= today or written.gi ~= gi or written.mem ~= mem or written.n ~= mem.n then
		written = { day = today, gi = gi, mem = mem, n = mem.n, keys = {} }
	end
	local done = written.keys
	for _, row in ipairs(R.members) do
		local k = Key(row.full or row.name)
		if k and not done[k] then
			local g, first = ReadMem(mem.n[k])
			if not mem.n[k] then mem.count = mem.count + 1 end
			if g ~= gi or not first then first = today end
			mem.n[k] = gi .. ":" .. B36(first) .. ":" .. B36(today)
			done[k] = true
		end
	end
	-- Bounded: names not seen for MEMORY_DAYS go, then the oldest last days. (1.2.3: listed and sorted only
	-- past MEMORY_MAX; a name that goes is written again the next time it is seen.)
	if mem.count > Count.MEMORY_MAX or Count.random(1, 50) == 1 then
		local n = 0
		for k, v in pairs(mem.n) do
			local _, _, last = ReadMem(v)
			if not last or today - last > Count.MEMORY_DAYS then mem.n[k], done[k] = nil, nil else n = n + 1 end
		end
		if n > Count.MEMORY_MAX then
			local list = {}
			for k, v in pairs(mem.n) do
				local _, _, last = ReadMem(v)
				list[#list + 1] = { k = k, last = last }
			end
			table.sort(list, function(a, b) if a.last ~= b.last then return a.last > b.last end return a.k < b.k end)
			for i = Count.MEMORY_MAX + 1, #list do mem.n[list[i].k], done[list[i].k] = nil, nil end
		end
		mem.count = math.min(n, Count.MEMORY_MAX)
	end
	return true
end

-- What this client knows of a name: { guild, first, last, now } or nil.
function Count.Fact(name)
	local k = Key(name)
	local mem = k and Mem()
	local gi, first, last = ReadMem(mem and mem.n[k])
	if not gi or not mem.g[gi] then return nil end
	local now = false
	local R = ns.Roster
	if R and type(R.members) == "table" and R.guild == OwnGuild() and mem.g[gi] == OwnGuild() then
		for _, row in ipairs(R.members) do if Key(row.full or row.name) == k then now = true break end end
	end
	return { guild = mem.g[gi], first = first, last = last, now = now }
end

---------------------------------------------------------------------------
-- Reading the guild's log
---------------------------------------------------------------------------

-- A Church person heard over GUILD from a guildmate lately (his presence): our log is worth
-- reading, and his invites in it are worth reporting.
function Count.HeardPresence(dist, sender, role, guild)
	if dist ~= "GUILD" or not (role == "H" or role == "A" or role == "M" or role == "C") then
		if Church.IsKeeper(sender) and #Out() > 0 then Count.after(Count.random(2, 10), "church outbox", Count.Flush) end
		return
	end
	local claims, k = Claims(), Key(sender)
	if not claims or not k then return end
	if not claims[k] then
		local n = 0
		for _ in pairs(claims) do n = n + 1 end
		if n >= 100 then
			local oldest, at
			for key, t in pairs(claims) do if not at or t < at then oldest, at = key, t end end
			if oldest then claims[oldest] = nil end
		end
	end
	claims[k] = ns.Now()
	if Church.IsKeeper(sender) and #Out() > 0 then Count.after(Count.random(2, 10), "church outbox", Count.Flush) end
end

function Count.Claimed(name)
	local claims = Claims()
	local t = claims and claims[Key(name) or ""]
	return t ~= nil and ns.Now() - t <= Count.CLAIM_KEEP
end
local function AnyClaim()
	local now = ns.Now()
	for _, t in pairs(Claims() or {}) do if now - t <= Count.CLAIM_KEEP then return true end end
	return false
end

function Count.CanRead(now)
	if not ns.IsMember() then return false, "member" end
	if ns.KingsScreen and ns.KingsScreen() then return false, "king" end
	if InCombatLockdown and InCombatLockdown() then return false, "combat" end
	if ns.ChatLocked and ns.ChatLocked() then return false, "lockdown" end
	if type(QueryGuildEventLog) ~= "function" or type(GetNumGuildEvents) ~= "function" or type(GetGuildEventInfo) ~= "function" then
		return false, "api"
	end
	if now - lastRead < Count.READ_GAP then return false, "gap" end
	return true
end

-- Asks the server for the log (its answer comes as GUILD_EVENT_LOG_UPDATE). The event is
-- registered the first time, and it is the only one the Church registers.
function Count.Read()
	local now = ns.Now()
	local ok, why = Count.CanRead(now)
	if not ok then return false, why end
	if not registered then
		registered = true
		ns.RegisterEvent("GUILD_EVENT_LOG_UPDATE", function() Count.OnLogUpdate() end)
	end
	lastRead = now
	stats.reads = stats.reads + 1
	QueryGuildEventLog()
	return true
end

-- (1.5.5) A Church person of our guild by this client's own book: one its roster holds now. His own
-- client may never say so (one that holds a signed list older than the one naming him), and then no
-- presence of his is heard (HeardPresence). Read from the book's own tables (Role per row is slower).
function Count.PersonHere()
	local R = ns.Roster
	if not (R and R.complete == true and type(R.members) == "table") then return false end
	local guild = OwnGuild()
	if not guild or R.guild ~= guild then return false end
	local S = Church.State()
	for _, row in ipairs(R.members) do
		local k = Key(row.full or row.name)
		if k and (S.apostle[k] or (S.miss[k] and S.miss[k].valid) or S.corrOf[k]) then return true end
	end
	return false
end

-- Every READ_EVERY: a Church person's own client reads, and (1.5.5) a keeper's (the author's: a
-- keeper, no Church person); another client reads with a chance that makes about two reads per guild
-- (its addon users counted), and only where a Church person was heard over GUILD lately or (1.5.5)
-- its own roster holds one (PersonHere). (Before 1.5.5 an Apostle whose client held an older list
-- said nothing, so neither his guildmates' clients nor the author's read their log: nothing counted.)
function Count.MaybeRead(now)
	if now - lastReadTick < Count.READ_EVERY then return false end
	lastReadTick = now
	local keeper = Church.IsKeeper(ns.me) and not Church.IsKing(ns.me)
	if not keeper and not Church.IsPerson(ns.me) then
		if not AnyClaim() and not Count.PersonHere() then return false end
		local peers = math.max(1, (ns.Comm.PeerCount and ns.Comm.PeerCount()) or 1)
		if Count.chance() > math.min(1, 2 / peers) then return false end
	end
	return Count.Read()
end

local function EventName(raw)
	if type(raw) ~= "string" or raw == "" then return nil end
	return WireName(raw)
end

-- The log's events, oldest first, with the hour each happened (by the server's clock; the log
-- gives how long ago, so the same event read twice can differ by one hour).
function Count.Events()
	local n = tonumber(GetNumGuildEvents()) or 0
	local hourNow = math.floor(Clock() / 3600)
	local out = {}
	for i = 1, math.min(n, Count.EVENTS_MAX) do
		local kind, p1, p2, _, y, mo, d, h = GetGuildEventInfo(i)
		local a = EventName(p1)
		if type(kind) == "string" and a then
			local ago = ((tonumber(y) or 0) * 365 + (tonumber(mo) or 0) * 30 + (tonumber(d) or 0)) * 24 + (tonumber(h) or 0)
			out[#out + 1] = { kind = kind, p1 = a, p2 = EventName(p2), hour = hourNow - ago }
		end
	end
	local order = { invite = 1, join = 2 }
	table.sort(out, function(x, z)
		if x.hour ~= z.hour then return x.hour < z.hour end
		return (order[x.kind] or 3) < (order[z.kind] or 3)
	end)
	return out
end

local function SeenEvent(ev, sig, hour)
	return ev.k[sig .. ":" .. hour] or ev.k[sig .. ":" .. (hour - 1)] or ev.k[sig .. ":" .. (hour + 1)]
end

local function FillOf(guild, day)
	local fills = Fills()
	local g = ns.Fold(guild)
	if type(fills[g]) ~= "table" then fills[g] = {} end
	local f = fills[g]
	if type(f[day]) ~= "table" then f[day] = { j = 0, l = 0 } end
	for d in pairs(f) do if type(d) == "number" and d < day - 8 then f[d] = nil end end
	return f[day]
end

-- What one read brought: new events only (each kept EV_DAYS), invites remembered PAIR_HOURS for
-- the join after them, this player's own invites and the guild's joins and leaves counted here.
function Count.Process(events)
	local guild = OwnGuild()
	if not guild or not ns.IsFederation(guild) then return 0 end
	local ev, inv = Ev(), Inv()
	local today = Day(Clock())
	local meKey = Key(ns.me)
	local person = Church.IsPerson(ns.me)
	local found = 0
	for _, e in ipairs(events) do
		local sig = e.kind .. ":" .. (Key(e.p1) or "") .. ":" .. (Key(e.p2) or "")
		if not SeenEvent(ev, sig, e.hour) then
			ev.k[sig .. ":" .. e.hour], ev.n = today, ev.n + 1
			stats.events = stats.events + 1
			local day = Day(e.hour * 3600)
			if e.kind == "invite" and e.p2 then
				inv[Key(e.p2)] = { by = e.p1, h = e.hour }
				if person and Key(e.p1) == meKey then
					local m = Mine()
					m.inv[day] = (m.inv[day] or 0) + 1
				end
			elseif e.kind == "join" then
				FillOf(guild, day).j = FillOf(guild, day).j + 1
				local i = inv[Key(e.p1)]
				if i and e.hour >= i.h - 1 and e.hour <= i.h + Count.PAIR_HOURS then
					if Count.Pair(i.by, e.p1, guild, i.h, math.max(e.hour, i.h)) then found = found + 1 end
				end
			elseif e.kind == "quit" or e.kind == "remove" then
				FillOf(guild, day).l = FillOf(guild, day).l + 1
			end
		end
	end
	-- Bounds.
	if ev.n > Count.EV_MAX or Count.random(1, 20) == 1 then
		local n = 0
		for k, d in pairs(ev.k) do if today - d > Count.EV_DAYS then ev.k[k] = nil else n = n + 1 end end
		ev.n = n
		if n > Count.EV_MAX then wipe(ev.k); ev.n = 0 end
	end
	local hourNow = math.floor(Clock() / 3600)
	local kept = {}
	for k, i in pairs(inv) do
		if type(i) ~= "table" or type(i.h) ~= "number" or hourNow - i.h > Count.PAIR_HOURS + 1 then inv[k] = nil else kept[#kept + 1] = { k = k, h = i.h } end
	end
	if #kept > Count.INV_MAX then
		table.sort(kept, function(a, b) if a.h ~= b.h then return a.h < b.h end return a.k < b.k end)
		for j = 1, #kept - Count.INV_MAX do inv[kept[j].k] = nil end
	end
	return found
end

function Count.OnLogUpdate()
	if ns.KingsScreen and ns.KingsScreen() then return end
	Count.Process(Count.Events())
end

-- A pair seen: reported once (Att), when its inviter is a Church person this client knows.
function Count.Pair(inviter, invitee, guild, ti, tj)
	local ik, xk = Key(inviter), Key(invitee)
	if not ik or not xk or ik == xk then return false end
	if not (Church.IsPerson(inviter) or Count.Claimed(inviter)) then return false end
	local att = Att()
	local id = xk .. ":" .. ik
	if att[id] then return false end
	att[id] = Day(Clock())
	local n = 0
	for k, d in pairs(att) do if Day(Clock()) - d > Count.ATT_DAYS then att[k] = nil else n = n + 1 end end
	if n > Count.ATT_MAX then wipe(att); att[id] = Day(Clock()) end
	stats.pairs = stats.pairs + 1
	local g = CleanGuild(guild)
	if not g then return false end
	Count.SendEvidence(("NV~1~w~%s~%s~%s~%s~%s"):format(inviter, invitee, g, B36(ti), B36(tj)))
	return true
end

---------------------------------------------------------------------------
-- Evidence to the keepers (or the outbox while none is online)
---------------------------------------------------------------------------

-- A report into the outbox (once: the same text again is the same report). own: this keeper's own
-- ledger took it; it goes once to each keeper online now, and none online, it waits for no one (the
-- catch-up carries it).
local function Queue(text, own)
	local out = Out()
	for _, o in ipairs(out) do if type(o) == "table" and o.text == text then return o end end
	if own and #Church.KeepersOnline(false) == 0 then return nil end
	if #out >= Count.OUTBOX_MAX then table.remove(out, 1) end
	local o = { text = text, h = ns.Comm.Hash36(text), at = Clock(), to = {}, own = own or nil }
	out[#out + 1] = o
	stats.queued = stats.queued + 1
	return o
end

-- To every keeper heard online, this client's own keeper book first, through the outbox. True when it
-- went somewhere (or waits for a keeper's receipt).
function Count.SendEvidence(text)
	if Off() then return false end
	local took = false
	if Church.IsKeeper(ns.me) and not Church.IsKing(ns.me) then took = Count.TakeEvidence(ns.me, text) == true end
	Queue(text, took)
	Count.Flush()
	return took or #Church.KeepersOnline(false) > 0
end

-- Attempts to one keeper, persisted as { n = how many, w = when last }. An earlier build kept true.
local function SentTo(o, k)
	local s = o.to[k]
	if s == true then s = { n = 1, w = tonumber(o.w) or tonumber(o.at) or 0 }; o.to[k] = s end
	return type(s) == "table" and s or nil
end

-- A keeper's report its own ledger refused (its budget for itself spent, a missionary its book had not placed
-- yet): no keeper sends a keeper receipts (Count.Receipt), so its own ledger tries it again, RESEND_GAP apart
-- and RESEND_TRIES times. Taken, it goes once to each keeper online, as one taken at once does; else it goes.
local function RetryOwn(out, now)
	for i = #out, 1, -1 do
		local o = out[i]
		if not o.own and now - (tonumber(o.lw) or tonumber(o.at) or now) >= Count.RESEND_GAP then
			o.lt, o.lw = (tonumber(o.lt) or 0) + 1, now
			if Count.TakeEvidence(ns.me, o.text) == true then o.own, o.to = true, {}
			elseif o.lt >= Count.RESEND_TRIES then table.remove(out, i) end
		end
	end
end

-- An ordinary report stays until a keeper's receipt. A send API success or an NV l may itself
-- be lost, so an unacknowledged report retries with the same hourly and per-keeper limits.
-- A keeper's own accepted report goes once to each keeper online, with ledger catch-up as backup.
local sendingEvidence = {}
function Count.Flush()
	local out = Out()
	if not out or #out == 0 or Off() or (ns.ChatLocked and ns.ChatLocked()) then return 0 end
	local now = Clock()
	for i = #out, 1, -1 do
		local o = out[i]
		if type(o) ~= "table" or type(o.text) ~= "string" or now - (tonumber(o.at) or 0) > Count.OUTBOX_DAYS * DAY then table.remove(out, i)
		elseif type(o.to) ~= "table" then o.to = {} end
	end
	if Church.IsKeeper(ns.me) and not Church.IsKing(ns.me) then RetryOwn(out, now) end
	local keepers = {}
	for _, k in ipairs(Church.KeepersOnline(false)) do
		local kk = Key(k.name)
		if kk then keepers[#keepers + 1] = { name = k.name, key = kk } end
	end
	if #keepers == 0 and #out > 0 then Church.FindKeeper() end
	local sent = 0
	for _, o in ipairs(#keepers > 0 and out or {}) do
		o.h = o.h or ns.Comm.Hash36(o.text)
		for _, k in ipairs(keepers) do
			local s = SentTo(o, k.key)
			local attempts = s and tonumber(s.n) or 0
			local retry = s and not o.own and not sendingEvidence[s] and attempts < Count.RESEND_TRIES
				and now - (tonumber(s.w) or 0) >= Count.RESEND_GAP
			if not s or retry then
				if ns.Comm.QueueRoom() <= Count.SEND_ROOM then return sent end
				local attempt = { n = attempts + 1, w = now }
				o.to[k.key], sendingEvidence[attempt] = attempt, true
				local accepted = ns.Comm.Whisper(k.name, o.text, nil, false, false, function()
					sendingEvidence[attempt], attempt.w = nil, Clock()
				end, { owner = Count })
				if accepted then sent, stats.sent = sent + 1, stats.sent + 1 end
			end
		end
	end
	for i = #out, 1, -1 do if out[i].own then table.remove(out, i) end end
	return sent
end

-- A keeper's receipt (1.2.1): the reports it took leave the outbox (the catch-up carries them to the
-- other keepers).
function Count.TakeReceipt(sender, text)
	local list = tostring(text or ""):match("^NV~1~k~([0-9a-z,]+)$")
	if not list then return Drop("shape") end
	if not Church.IsKeeper(sender) or Church.IsKing(sender) then return Drop("keeper") end
	local got, n = {}, 0
	for h in list:gmatch("[0-9a-z]+") do
		n = n + 1
		if n > Count.RECEIPT_IDS then break end
		got[h] = true
	end
	local out, done = Out(), 0
	for i = #out, 1, -1 do
		local o = out[i]
		if type(o) == "table" and type(o.text) == "string" and got[o.h or ns.Comm.Hash36(o.text)] then table.remove(out, i); done = done + 1 end
	end
	stats.receipts = (stats.receipts or 0) + done
	return true
end

-- A keeper may still tell us it needs another try (NV l). The outbox also retries if that reply is lost.
function Count.TakeLater(sender, text)
	if not tostring(text or ""):match("^NV~1~l~%w+$") then return Drop("shape") end
	if not Church.IsKeeper(sender) or Church.IsKing(sender) then return Drop("keeper") end
	stats.later = (stats.later or 0) + 1
	return true
end

-- The receipts this keeper owes (1.2.1): reporter key -> { name, ids, later }, sent RECEIPT_GAP after the
-- first, RECEIPT_IDS to a line, leaving room in Comm's queue. A report refused for a reason another try
-- could change (Count.LATER) gets none: its reporter is told it may send it again (NV l), once a round.
local owed, owing = {}, false
local FINAL = { shape = true, kind = true, times = true, self = true, guild = true, held = true, taken = true }
-- (1.2.1) What a later try may change: a budget spent, a missionary this book does not place yet, a recruit
-- our roster does not show yet (VerifiedWitness), one not yet a Church person here.
Count.LATER = { budget = true, recruiter = true, roster = true, person = true }
local function SendReceipts()
	owing = false
	for k, r in pairs(owed) do
		while #r.ids > 0 and ns.Comm.QueueRoom() > Count.SEND_ROOM do
			local n = math.min(#r.ids, Count.RECEIPT_IDS)
			ns.Comm.Whisper(r.name, "NV~1~k~" .. table.concat(r.ids, ",", 1, n), nil, false, false, nil, { owner = Count })
			for _ = 1, n do table.remove(r.ids, 1) end
		end
		if r.later and #r.ids == 0 and ns.Comm.QueueRoom() > Count.SEND_ROOM then
			ns.Comm.Whisper(r.name, "NV~1~l~1", nil, false, false, nil, { owner = Count })
			r.later = nil
		end
		if #r.ids == 0 and not r.later then owed[k] = nil end
	end
	if next(owed) then owing = true; Count.after(Count.RECEIPT_GAP, "church receipts", SendReceipts) end
end
function Count.Receipt(sender, text, ok, why)
	local final = ok == true or FINAL[why or ""] == true
	if not final and not Count.LATER[why or ""] then return false end
	local k = Key(sender)
	if not k or k == Key(ns.me) then return false end
	-- (Never to a keeper: his reports need none, one his own ledger took goes once to each keeper online and
	-- one it refused it tries again itself, Count.Flush; and a keeper before 1.2.1 counted each line against
	-- its budget for us, then refused our own reports.)
	if Church.IsKeeper(sender) and not Church.IsKing(sender) then return false end
	local r = owed[k]
	if not r then
		Church.Capped(owed, Count.PEOPLE_MAX)
		r = { name = ns.FullName(sender), ids = {} }
		owed[k] = r
	end
	if final then
		if #r.ids >= Count.RECEIPT_IDS * 4 then return false end
		r.ids[#r.ids + 1] = ns.Comm.Hash36(text)
	else
		r.later = true
	end
	if not owing then owing = true; Count.after(Count.RECEIPT_GAP, "church receipts", SendReceipts) end
	return true
end
function Count.Owed() return owed end

---------------------------------------------------------------------------
-- The keepers' ledger
---------------------------------------------------------------------------

-- Two characters of one player (Alts.Linked, either way).
local function Linked(a, b)
	local A = ns.Alts
	if not (A and A.Linked) or not a or not b then return false end
	local ka, kb = Key(a), Key(b)
	for _, n in ipairs(A.Linked(ns.FullName(a)) or {}) do if Key(n) == kb then return true end end
	for _, n in ipairs(A.Linked(ns.FullName(b)) or {}) do if Key(n) == ka then return true end end
	return false
end
Count.Linked = Linked

-- An alt, never credited: the recruit is one of the recruiter's characters (Alts.Linked), or one of the
-- recruit's linked characters was in an Olympus guild in the last NEW_DAYS (this client's roster memory).
local function AltOf(recruit, recruiter)
	if Linked(recruit, recruiter) then return true end
	local A = ns.Alts
	local today = Day(Clock())
	for _, n in ipairs(A and A.Linked and A.Linked(ns.FullName(recruit)) or {}) do
		local f = Count.Fact(n)
		if f and f.last and today - f.last <= Count.NEW_DAYS then return true end
	end
	return false
end
Count.AltOf = AltOf

-- (1.2.1) A recruit this client saw in our guild itself: its roster memory has him there no earlier than the
-- day before his join (Count.Remember first, for its newest roster), or its own read of the log saw him join.
-- A name nobody's roster ever showed was no recruit: a guildmate's whisper of one made him one.
local function SeenHere(invitee, guild, tj)
	local xk = Key(invitee)
	if not xk or not tj then return false, "roster" end
	Count.Remember(false)
	local mem = Mem()
	local gi, _, last = ReadMem(mem and mem.n[xk])
	if gi and mem.g[gi] and ns.Fold(mem.g[gi]) == ns.Fold(guild) and (last or 0) >= Day(tj * 3600) - 1 then return true end
	local ev = Ev()
	if ev and type(ev.k) == "table" and SeenEvent(ev, "join:" .. xk .. ":", tj) then return true end
	return false, "roster"
end

-- (1.2.1) A witness this client can vouch for in the pair's guild, as the desk's seen-checks keep their
-- answers to (CheckRecipients): the signed (a keeper, the King, a High Councillor); that guild's
-- correspondent, named by its guild master (the book); in our own guild, a guildmate on our fresh roster (a
-- guildmate of ours reads our guild's log, never another's), for a recruit we saw there ourselves (SeenHere);
-- in another, one the Olympus chats verify for it (Channels.VerifiedLevel's verified word: its signed
-- leadership, or the census as they read it). A whisper alone vouches for nothing: anyone can send one.
-- Returns true and "census" for a witness only the census vouches for (the signed leadership not enforced:
-- two characters can make one), who has the smaller budget; false and why ("roster": a later try may pass).
local function VerifiedWitness(name, guild, invitee, tj)
	local who, mine = ns.FullName(name), OwnGuild()
	if not who or not guild then return false, "unverified" end
	local R = ns.Roster
	local fresh = R and R.Fresh and R.Fresh()
	local mate = fresh and R.RankOf and R.RankOf(who) ~= nil
	local ours = mine ~= nil and ns.Fold(mine) == ns.Fold(guild)
	if mate and not ours then return false, "unverified" end
	if Church.IsKeeper(who) or Church.IsKing(who) or (ns.IsHighCouncillor and ns.IsHighCouncillor(who) == true) then return true end
	local S = Church.State()
	local corr = S.corr[ns.Fold(guild)]
	-- (1.2.4: one whom only another guild's census names its master's correspondent, as any census-only
	-- witness: the smaller budget. Two characters can make that guild's master.)
	if corr and Key(corr.n) == Key(who) then return true, S.corrCensus and S.corrCensus[ns.Fold(guild)] and "census" or nil end
	if ours then
		if not fresh then return false, "roster" end
		if not mate then return false, "unverified" end
		return SeenHere(invitee, guild, tj)
	end
	local C = ns.Channels
	if type(C) ~= "table" or type(C.VerifiedLevel) ~= "function" then return false, "unverified" end
	local ok, level, verified = pcall(C.VerifiedLevel, who, guild)
	if not (ok and verified == true and (tonumber(level) or 0) >= 1) then return false, "unverified" end
	local A = ns.Authority
	local okE, enforced = pcall(function() return A and A.Enforced and A.Enforced() end)
	return true, not (okE and enforced) and "census" or nil
end
Count.VerifiedWitness = VerifiedWitness

local function Sources(list)
	local out, seen = {}, {}
	for _, s in ipairs(list or {}) do if s and not seen[s] then seen[s], out[#out + 1] = true, s end end
	table.sort(out)
	while #out > 2 do table.remove(out) end
	return out
end

-- Merges o into r (both records of one recruit and recruiter): the earliest times, every flag,
-- the two smallest independent sources, the strongest stay answer. Order makes no difference.
local function MergeRec(r, o)
	local changed = false
	local function Set(k, v) if r[k] ~= v then r[k], changed = v, true end end
	if o.tc and (not r.tc or o.tc < r.tc) then Set("tc", o.tc) end
	if o.tj and (not r.tj or o.tj < r.tj or (o.tj == r.tj and (o.g or "") < (r.g or ""))) then Set("tj", o.tj); Set("g", o.g) end
	if not r.g and o.g then Set("g", o.g) end
	for _, f in ipairs({ "s", "t", "a", "x", "c" }) do if o[f] and not r[f] then Set(f, 1) end end
	if o.kind == "i" and r.kind ~= "i" then Set("kind", "i") end
	if o.y == 1 and r.y ~= 1 then Set("y", 1) elseif o.y == 0 and r.y == nil then Set("y", 0) end
	if (o.q7 or 0) > (r.q7 or 0) then Set("q7", o.q7) end
	if (o.rq or 0) > (r.rq or 0) then Set("rq", o.rq) end
	local all = {}
	for _, s in ipairs(r.ws or {}) do all[#all + 1] = s end
	for _, s in ipairs(o.ws or {}) do all[#all + 1] = s end
	local ws = Sources(all)
	if table.concat(ws, ",") ~= table.concat(r.ws or {}, ",") then Set("ws", #ws > 0 and ws or nil) end
	return changed
end

local function TooOld(r, now)
	local t = r.tj or r.tc or 0
	return now - t > Count.RECORDS_DAYS * DAY
end

-- How long an archived join still counts in a window: a join in the last MONTH_DAYS, and the stay
-- STAY_DAYS after it.
local function WindowKeep() return (Count.MONTH_DAYS + Count.STAY_DAYS) * DAY end

-- 1.2.1, the archive by record: l.arc[recruiter][recruit] = { h = his join, t = when it came into this
-- archive, y = 1 still in after 7 days, l = 1 this ledger's all-time totals (p.ap, p.aj, p.ay) hold
-- it }, while a window still counts it (WindowKeep). Count.Own counts each in this week and the last
-- 30 days as the live record was counted; the catch-up carries them (NL z) to every keeper, and each
-- takes one once, by its id (Count.TakeArchived), so keepers converge on the same numbers whichever
-- of them let a record go.
local function Arc()
	local l = Led()
	if type(l.arc) ~= "table" then l.arc = {} end
	return l.arc
end
Count.Arc = Arc

-- A credited record's points folded into its recruiter's archive when it ages out or makes room,
-- and (1.2.1) the record itself into the archive while a window still counts it.
local function Archive(r, now, id)
	local l = Led()
	local by = Key(r.bn)
	if not by then return end
	now = now or Clock()
	local p = l.p[by] or { n = r.bn }
	l.p[by] = p
	p.ap = (p.ap or 0) + Count.POINTS_JOIN + (r.y == 1 and Count.POINTS_STAY or 0)
	p.aj = (p.aj or 0) + 1
	p.ay = (p.ay or 0) + (r.y == 1 and 1 or 0)
	p.u = Clock()
	local tj, xk = tonumber(r.tj), type(id) == "string" and id:match("^([^:]+):")
	if tj and xk and tj >= now - WindowKeep() then
		local arc = Arc()
		if type(arc[by]) ~= "table" then arc[by] = {} end
		arc[by][xk] = { h = tj, t = p.u, y = r.y == 1 and 1 or nil, l = 1 }
	end
end

-- What this ledger let go (1.2.1): "<recruit>:" -> when, for each recruit whose credited claim went
-- into the archive (no record of him is taken again, nor another claim on him: he would count twice,
-- or for two people), and "<recruit>:<recruiter>" -> when, for a record let go that counted for
-- nothing (a transfer, an alt, withdrawn: a copy that lost that word is never taken as new). Kept
-- RECORDS_DAYS, as long as a keeper's line could bring one back (Count.Prune; GONE_MAX against a flood).
local function Gone()
	local l = Led()
	if type(l.gone) ~= "table" then l.gone = {} end
	return l.gone
end
local function MarkGone(keys, now)
	local g = Gone()
	for _, k in ipairs(keys) do g[k] = now end
end

-- (1.2.1, once per ledger begun before it: what a full ledger archived then kept neither its join nor
-- a mark of its recruit. Each record it let go itself, its mark ("<recruit>:<recruiter>" -> when),
-- becomes its recruit's mark and, while a window still counts it, an archived record dated at the
-- hour it went, never before its join: such a recruit stays in the last 30 days at most the days
-- between his join and that hour longer than he should. Its all-time point is already this ledger's
-- (l). Marks only: a total another keeper's archive lent (Count.TakePerson) is not this ledger's to
-- date. A ledger of 1.2.1's first builds, wv 1, keeps the join hours it holds, p.wj and p.wy.)
local function WindowsFromGone(l, now)
	if (tonumber(l.wv) or 0) >= 2 then return end
	local old = l.wv == nil
	l.wv = 2
	if not old or type(l.gone) ~= "table" then return end
	local keep, marks = now - WindowKeep(), {}
	for id, t in pairs(l.gone) do
		local xk, by
		if type(id) == "string" then xk, by = id:match("^([^:]+):(.+)$") end
		if xk and type(t) == "number" then marks[#marks + 1] = { id = id, xk = xk, by = by, t = t } end
	end
	if type(l.arc) ~= "table" then l.arc = {} end
	for _, m in ipairs(marks) do
		l.gone[m.id] = nil
		l.gone[m.xk .. ":"] = math.max(tonumber(l.gone[m.xk .. ":"]) or 0, m.t)
		if type(l.p[m.by]) == "table" and m.t >= keep and m.t <= now + 3600 then
			if type(l.arc[m.by]) ~= "table" then l.arc[m.by] = {} end
			l.arc[m.by][m.xk] = l.arc[m.by][m.xk] or { h = math.floor(m.t / 3600) * 3600, t = now, l = 1 }
		end
	end
end

-- Room in a full ledger (1.2.1): first the records that count for nothing (withdrawn, transfers, alts,
-- claims another holds, expired registrations), then credited ones nothing can change any more (the
-- new-to-Olympus check done, the stay answered or its tries spent), then pending ones (a witness's
-- read brings one back), then the other credited ones, open registrations last: the oldest first in
-- each, the id breaking ties, so keepers holding the same records let the same ones go. A credited
-- one goes into the archive: no window's count drops. A fiftieth of the ledger goes at once, so the
-- ledger is sorted once for that many new records.
local LET_GO = { withdrawn = 1, transfer = 1, alt = 1, taken = 1, expired = 1, pending = 3, credited = 4, open = 5 }
local function MakeRoom(l, now, n)
	WindowsFromGone(l, now)
	local C = Count.Credits()
	local list = {}
	for id, r in pairs(l.r) do
		local state = C.states[id]
		local tier = LET_GO[state] or 1
		if state == "credited" and r.c and (r.y ~= nil or (r.q7 or 0) >= Count.STAY_TRIES) then tier = 2 end
		list[#list + 1] = { id = id, tier = tier, t = tonumber(r.tj or r.tc) or 0 }
	end
	table.sort(list, function(a, b)
		if a.tier ~= b.tier then return a.tier < b.tier end
		if a.t ~= b.t then return a.t < b.t end
		return a.id < b.id
	end)
	local keep = Count.RECORDS_MAX - math.max(1, math.floor(Count.RECORDS_MAX / 50))
	local marks = {}
	for i = 1, math.min(#list, n - keep) do
		local id = list[i].id
		local r, xk = l.r[id], id:match("^([^:]+):")
		if C.states[id] == "credited" then
			Archive(r, now, id)
			if xk then marks[#marks + 1] = xk .. ":" end
		elseif r.t or r.a or r.x then
			marks[#marks + 1] = id
		end
		l.r[id] = nil
	end
	MarkGone(marks, now)
end

-- An archived record's later word (1.2.1), from the desk's check or another keeper's line: proven to
-- count for nothing (a transfer, an alt, withdrawn), it leaves the windows (and the all-time totals of
-- the ledger that archived it), the only way a count goes down; still in after 7 days, its stay counts
-- (and is carried on, NL z). Anything else changes nothing. True when it changed. push (the desk's own
-- check): the word goes to the other keepers online as the record's line, as Count.Push sends one.
local function ArchivedNews(l, id, xk, by, a, rec, now, push)
	local p = type(l.p[by]) == "table" and l.p[by] or nil
	if rec.t or rec.a or rec.x then
		if a.l and p then
			p.ap = math.max(0, (p.ap or 0) - Count.POINTS_JOIN - (a.y == 1 and Count.POINTS_STAY or 0))
			p.aj = math.max(0, (p.aj or 0) - 1)
			if a.y == 1 then p.ay = math.max(0, (p.ay or 0) - 1) end
			p.u = now
		end
		l.arc[by][xk] = nil
		MarkGone({ id }, now)
		Changed()
		if push then
			local line = Count.RecordLine(id, { n = xk, bn = by, kind = "i", tc = a.h, tj = a.h, t = rec.t, a = rec.a, x = rec.x, c = 1, u = now })
			Count.ToRelays(line)
		end
		return true
	elseif rec.y == 1 and a.y ~= 1 then
		a.y, a.t = 1, now
		if a.l and p then p.ap, p.ay, p.u = (p.ap or 0) + Count.POINTS_STAY, (p.ay or 0) + 1, now end
		Changed()
		return true
	end
	return false
end

-- A record into the ledger (new, or merged). push: send it to the other keepers online (the desk's
-- own results; evidence reached them all already). True when it changed anything.
function Count.MergeIn(id, rec, push)
	local l = Led()
	local now = Clock()
	local r = l.r[id]
	local changed
	if not r then
		-- (A record past RECORDS_DAYS was archived: one coming back from another keeper is not taken;
		-- nor one this ledger archived to make room, nor another claim on its recruit, nor a record let
		-- go that counted for nothing, Gone. An archived one's later word still counts, ArchivedNews.)
		local g, xk, by = Gone(), id:match("^([^:]+):(.+)$")
		local set = xk and Arc()[by]
		local a = type(set) == "table" and set[xk] or nil
		if type(a) == "table" then return ArchivedNews(l, id, xk, by, a, rec, now, push) end
		if not (rec.tc or rec.tj) or TooOld(rec, now) or g[id] or (xk and g[xk .. ":"]) then return false end
		local n = 0
		for _ in pairs(l.r) do n = n + 1 end
		if n >= Count.RECORDS_MAX then MakeRoom(l, now, n) end
		r = { n = rec.n, bn = rec.bn, kind = rec.kind or "i" }
		l.r[id] = r
		changed = true
	end
	if MergeRec(r, rec) then changed = true end
	if changed then
		r.u = now
		Changed()
		if push then Count.Push(id) end
	end
	return changed
end

-- large: the larger budget (VERIFIED_HOUR, VERIFIED_DAY), every report's; else the smaller one.
local function Budget(sender, now, large)
	local k = Key(sender)
	if not k then return false end
	k = large and k or (k .. ":alt")
	local b = evidenceRate[k]
	local hour, day = math.floor(now / 3600), Day(now)
	if not b then Church.Capped(evidenceRate, Count.PEOPLE_MAX * 2) end
	if not b or b.hour ~= hour then b = { hour = hour, n = 0, day = b and b.day or day, d = b and b.d or 0 }; evidenceRate[k] = b end
	if b.day ~= day then b.day, b.d = day, 0 end
	if b.n >= (large and Count.VERIFIED_HOUR or Count.EVIDENCE_HOUR) or b.d >= (large and Count.VERIFIED_DAY or Count.EVIDENCE_DAY) then return false end
	b.n, b.d = b.n + 1, b.d + 1
	return true
end
Count.OverBudget = function() return evidenceRate end

-- A place held now, named no later than an hour after `t` (invites before his naming don't count;
-- the signed Apostles, the Head and the roots count from the list's own time; a missionary the
-- Head kept or moved, from when he first held his place: Place's since).
local function PlacedBy(name, t)
	if not Church.IsPerson(name) then return false end
	local p = Church.Place(name)
	local held = p and (p.since or p.at)
	if p and not p.signed and held and held > t + 3600 then return false end
	local S, k = Church.State(), Key(name)
	local gkey = S.corrOf[k]
	if not p and gkey and S.corr[gkey] and S.corr[gkey].at > t + 3600 then return false end
	return true
end

-- Open registrations of one person (kind g, no join yet, not withdrawn, not expired).
local function OpenRegs(by, now)
	local n, all = 0, 0
	for _, r in pairs(Led().r) do
		if r.kind == "g" and not r.tj and not r.x and now - (r.tc or 0) <= Count.REG_DAYS * DAY then
			all = all + 1
			if Key(r.bn) == by then n = n + 1 end
		end
	end
	return n, all
end

-- Evidence a keeper takes (from a whisper, or this client's own). True when taken.
function Count.TakeEvidence(sender, text)
	if not Church.IsKeeper(ns.me) or Church.IsKing(ns.me) then return Drop("not keeper") end
	local kind = tostring(text or ""):match("^NV~1~(%a)~")
	if not kind then return Drop("shape") end
	local now = Clock()
	local M = ns.Moderation
	if M and M.Hides and M.Hides(sender, nil) then return Drop("netoff") end
	if not Budget(sender, now, true) then return Drop("budget") end
	local sk = Key(sender)
	if kind == "w" then
		local inviter, invitee, guild, ti, tj = text:match("^NV~1~w~([^~]+)~([^~]+)~([^~]+)~([0-9a-z]+)~([0-9a-z]+)$")
		inviter, invitee, guild, ti, tj = WireName(inviter), WireName(invitee), CleanGuild(guild), UnB36(ti), UnB36(tj)
		if not inviter or not invitee or not guild or not ti or not tj then return Drop("shape") end
		if not ns.IsFederation(guild) then return Drop("guild") end
		if tj < ti - 1 or tj > ti + Count.PAIR_HOURS then return Drop("times") end
		if tj * 3600 > now + 3600 or tj * 3600 < now - Count.REG_DAYS * DAY then return Drop("times") end
		local ik, xk = Key(inviter), Key(invitee)
		if ik == xk then return Drop("self") end
		if not PlacedBy(inviter, ti * 3600) then return Drop("recruiter") end
		if sk == xk or Linked(invitee, sender) then return Drop("recruit") end
		local own = sk == ik
		local alt = not own and Linked(inviter, sender)
		-- (1.2.1: only a witness this keeper can vouch for confirms, VerifiedWitness. Any other whisperer
		-- counted as one: a single whisper credited a recruit, or took one from his real recruiter.)
		local independent, how = false, nil
		if not own and not alt then
			independent, how = VerifiedWitness(sender, guild, invitee, tj)
			if not independent then return Drop(how or "unverified") end
		end
		-- (A witness only the census vouches for, as one only the recruiter's alt stands behind: the smaller
		-- budget too. Two characters can make a census officer.)
		if (alt or how == "census") and not Budget(sender, now, false) then return Drop("budget") end
		stats.taken = stats.taken + 1
		local id = xk .. ":" .. ik
		local held = Led().r[id]
		local had = held ~= nil and held.ws ~= nil and #held.ws > 0
		Count.MergeIn(id, { n = Short(invitee), bn = Short(inviter), g = guild, kind = "i", tc = ti * 3600, tj = tj * 3600,
			s = own and 1 or nil, ws = independent and { sk } or nil, a = AltOf(invitee, inviter) and 1 or nil }, false)
		-- (A keeper outside the pair's guild can't vouch for a guildmate there: the one that did tells the
		-- keepers online at once, when the queue has room; the catch-up carries it otherwise. Our own
		-- report reaches them all itself: a keeper is signed.)
		local r = Led().r[id]
		if independent and not had and r and r.ws and sk ~= Key(ns.me)
			and ns.Comm.QueueRoom() > Count.SEND_ROOM + #Church.KeepersOnline(false) then Count.Push(id) end
		return true
	elseif kind == "g" or kind == "x" then
		local recruit, at = text:match("^NV~1~[gx]~([^~]+)~([0-9a-z]+)$")
		recruit, at = WireName(recruit), UnB36(at)
		if not recruit or not at then return Drop("shape") end
		-- (As old as the outbox keeps one while no keeper is online: OUTBOX_DAYS. Its own date is only its
		-- sender's word: a registration counts from when a keeper hears it, below.)
		if at > now + Church.DATE_AHEAD or at < now - Count.OUTBOX_DAYS * DAY then return Drop("times") end
		if not Church.IsPerson(sender) then return Drop("recruiter") end
		local xk = Key(recruit)
		if xk == sk then return Drop("self") end
		local id = xk .. ":" .. sk
		if kind == "x" then
			local r = Led().r[id]
			if not r or r.kind ~= "g" or r.tj then return Drop("none") end
			Count.MergeIn(id, { x = 1 }, false)
			return true
		end
		if Led().r[id] then return Drop("held") end
		local mine, all = OpenRegs(sk, now)
		if mine >= Count.REG_OPEN or all >= Count.REG_ALL then return Drop("full") end
		-- (1.2.1: refused, too, for one another's invite holds while it waits for its witness, and dated when this
		-- keeper hears it, never by its own word: one whispered "six days ago" after an invite took that recruit
		-- from his inviter, and made a player who came last week this registrant's recruit. A registration is
		-- "I brought him": made before he came. The outbox brings one within seconds while a keeper is online.)
		local c = Count.CreditOf(xk)
		if (c and (c.state == "credited" or c.state == "pending")) or Gone()[xk .. ":"] then return Drop("taken") end
		stats.taken = stats.taken + 1
		Count.MergeIn(id, { n = Short(recruit), bn = Short(sender), kind = "g", tc = math.max(at, now) }, false)
		if Church.IsDesk() then Count.QueueCheck(id, "r") end
		return true
	elseif kind == "o" then
		local on, at = text:match("^NV~1~o~([01])~([0-9a-z]+)$")
		at = UnB36(at)
		if not on or not at or at > now + Church.DATE_AHEAD then return Drop("shape") end
		if not Church.IsPerson(sender) then return Drop("person") end
		-- (1.2.1: taken, too, when this ledger holds that choice or a newer one: its receipt.)
		if Count.TakePerson(sk, { n = Short(sender), pub = on == "1", pat = at }) then return true end
		local p = Led().p[sk]
		if p and (tonumber(p.pat) or 0) >= at then return true end
		return Drop("full")
	end
	return Drop("kind")
end

-- A person's line (his public choice, his archive): the newest choice, the largest archive.
function Count.TakePerson(k, o)
	local l = Led()
	local p = l.p[k]
	local changed = false
	if not p then
		local n = 0
		for _ in pairs(l.p) do n = n + 1 end
		if n >= Count.PEOPLE_MAX then return false end
		p = { n = o.n }
		l.p[k] = p
		changed = true
	end
	if o.pat and (not p.pat or o.pat > p.pat) then p.pub, p.pat, changed = o.pub == true, o.pat, true end
	for _, f in ipairs({ "ap", "aj", "ay" }) do
		if (o[f] or 0) > (p[f] or 0) then p[f], changed = o[f], true end
	end
	if changed then p.u = Clock(); Changed() end
	return changed
end

-- A credited record another keeper archived (1.2.1, NL z): o = { h = its join, y = 1 still in after 7
-- days }. Taken once, by its id: held live here, it goes into this ledger's archive as its own (unless
-- this ledger knows it counts for nothing), its claim on that recruit kept over any other here; not
-- held, it counts here in the windows (its all-time point is in that keeper's person line, TakePerson).
-- Either way its recruit is marked (Gone): he counts once, whoever's ledger let him go.
function Count.TakeArchived(id, o)
	local l, now = Led(), Clock()
	local xk, by = tostring(id or ""):match("^([^:]+):(.+)$")
	if not xk or type(o) ~= "table" or type(o.h) ~= "number" then return false end
	if o.h < now - WindowKeep() or o.h > now + 3600 then return false end
	local arc = Arc()
	local a = type(arc[by]) == "table" and arc[by][xk] or nil
	if type(a) == "table" then return ArchivedNews(l, id, xk, by, a, { y = o.y }, now) end
	local g = Gone()
	if g[id] or g[xk .. ":"] then return false end
	local r = l.r[id]
	if r then
		local state = Count.Credits().states[id]
		if state == "withdrawn" or state == "transfer" or state == "alt" or state == "expired" then return false end
		if o.y == 1 then r.y = 1 end
		r.tj = r.tj or o.h
		Archive(r, now, id)
		l.r[id] = nil
	else
		if type(arc[by]) ~= "table" then arc[by] = {} end
		arc[by][xk] = { h = o.h, t = now, y = o.y == 1 and 1 or nil }
	end
	MarkGone({ xk .. ":" }, now)
	Changed()
	return true
end

---------------------------------------------------------------------------
-- Who is credited, the points and the rankings (on a keeper's client, from its own ledger)
---------------------------------------------------------------------------

-- Per recruit: the record the earliest valid claim makes his, and every record's state:
-- credited, pending (no independent source yet), open (a registration still waiting), taken
-- (another's claim holds him), transfer, alt, withdrawn, expired. A claim an independent client
-- confirmed comes before one only its own recruiter stands behind, then the earliest: a made-up
-- report dated earlier takes no recruit from the one the log and a witness show.
local function Confirmed(r) return r.ws ~= nil and #r.ws > 0 end
-- The claim that comes first on one recruit: a confirmed one, then the earliest, then the smaller id.
local function Before(id, r, bid, b)
	local conf, bconf = Confirmed(r), Confirmed(b)
	return (conf and not bconf) or (conf == bconf and ((r.tc or 0) < (b.tc or 0) or ((r.tc or 0) == (b.tc or 0) and id < bid)))
end

-- { states = id -> state, winners = "<recruit>:" -> the id his claim is, byPerson = person key -> the
-- ids of his records, r = the records }. (1.2.3: kept while the ledger is the same, until the first open
-- registration reaches REG_DAYS and CREDITS_KEEP at most, nothing else in it depends on the time; built
-- in one pass over the ids, no table for each record: every minute's 1,932 records cost 30 ms and over
-- 1 MB of garbage on the author's laptop, the same result each time.)
function Count.Credits()
	local now = Clock()
	local recs = Led().r
	local c = credits
	if c and c.rev == ledRev and c.r == recs and now >= c.at and now <= c.til then return c end
	local states, byPerson, winners, G = {}, {}, {}, Gone()
	local til = now + Count.CREDITS_KEEP
	for id, r in pairs(recs) do
		local xc = id:match("^[^:]+:")
		if xc then
			local by = Key(r.bn)
			if by then
				local list = byPerson[by]
				if not list then list = {}; byPerson[by] = list end
				list[#list + 1] = id
			end
			local state
			if r.x then state = "withdrawn"
			elseif r.t then state = "transfer"
			elseif r.a then state = "alt"
			elseif r.kind == "g" and not r.tj then
				state = now - (r.tc or 0) <= Count.REG_DAYS * DAY and "open" or "expired"
				local ends = (r.tc or 0) + Count.REG_DAYS * DAY
				if state == "open" and ends < til then til = ends end
			elseif r.kind == "g" and r.tj > (r.tc or 0) + Count.REG_DAYS * DAY then state = "expired"
			else state = "valid" end
			if state == "valid" or state == "open" then
				-- (1.2.1: a recruit the archive counts already, Gone, is no live claim's: he counts once.)
				local bid = winners[xc]
				if G[xc] ~= nil then state = "taken"
				elseif not bid then winners[xc] = id
				elseif Before(id, r, bid, recs[bid]) then states[bid], winners[xc] = "taken", id
				else state = "taken" end
			end
			states[id] = state
		end
	end
	for _, id in pairs(winners) do
		if states[id] == "valid" then states[id] = Confirmed(recs[id]) and "credited" or "pending" end
	end
	credits = { rev = ledRev, at = now, til = til, r = recs, states = states, winners = winners, byPerson = byPerson }
	return credits
end

-- The claim a recruit counts for: { id, r, state }, or nil.
function Count.CreditOf(recruitKey)
	local C = Count.Credits()
	local id = C.winners[(recruitKey or "") .. ":"]
	if not id then return nil end
	return { id = id, r = C.r[id], state = C.states[id] }
end
function Count.StateOf(id) return Count.Credits().states[id] end

local function WindowFrom(window, now)
	if window == "w" then
		local D = ns.Dues
		if D and D.WeekOf and D.WeekStart then return D.WeekStart(D.WeekOf(now)) end
		return now - 7 * DAY
	elseif window == "m" then
		return now - Count.MONTH_DAYS * DAY
	end
	return -math.huge
end
Count.WindowFrom = WindowFrom

-- A person's own numbers in a window: points, recruits credited, still in after 7 days, pending,
-- transfers, taken, by guild (live records), and archived (the joins and stays of the archive, whose
-- guilds it does not keep).
function Count.Own(key, window)
	local now = Clock()
	local from = WindowFrom(window, now)
	local C = Count.Credits()
	local out = { points = 0, joins = 0, stays = 0, pending = 0, transfers = 0, taken = 0, open = 0, guilds = {},
		archived = { joins = 0, stays = 0 } }
	for _, id in ipairs(C.byPerson[key or ""] or {}) do
		local r = C.r[id]
		do
			local state = C.states[id]
			if state == "credited" then
				if r.tj >= from then
					out.points, out.joins = out.points + Count.POINTS_JOIN, out.joins + 1
					local g = r.g or "?"
					out.guilds[g] = out.guilds[g] or { joins = 0, stays = 0 }
					out.guilds[g].joins = out.guilds[g].joins + 1
				end
				if r.y == 1 and r.tj + Count.STAY_DAYS * DAY >= from then
					out.points, out.stays = out.points + Count.POINTS_STAY, out.stays + 1
					local g = r.g or "?"
					out.guilds[g] = out.guilds[g] or { joins = 0, stays = 0 }
					out.guilds[g].stays = out.guilds[g].stays + 1
				end
			elseif state == "pending" and (r.tj or 0) >= from then out.pending = out.pending + 1
			elseif state == "transfer" or state == "alt" then out.transfers = out.transfers + 1
			elseif state == "taken" then out.taken = out.taken + 1
			elseif state == "open" then out.open = out.open + 1 end
		end
	end
	-- (1.2.1: the recruits archived to make room still count where their join does, Archive. All time:
	-- the archive's totals, which another keeper's person line can raise (TakePerson), never fewer than
	-- the archived records this ledger holds, so all time is never below the last 30 days.)
	local p = Led().p[key or ""]
	p = type(p) == "table" and p or nil
	local set = Arc()[key or ""]
	local aj, ay = 0, 0
	for _, a in pairs(type(set) == "table" and set or {}) do
		if type(a) == "table" and type(a.h) == "number" then
			if window == "a" or a.h >= from then aj = aj + 1 end
			if a.y == 1 and (window == "a" or a.h + Count.STAY_DAYS * DAY >= from) then ay = ay + 1 end
		end
	end
	if window == "a" then
		local ap = aj * Count.POINTS_JOIN + ay * Count.POINTS_STAY
		if p then ap, aj, ay = math.max(ap, p.ap or 0), math.max(aj, p.aj or 0), math.max(ay, p.ay or 0) end
		out.points = out.points + ap
	else
		out.points = out.points + aj * Count.POINTS_JOIN + ay * Count.POINTS_STAY
		-- (1.2.1's first builds kept the archive's join hours by the hour, p.wj and p.wy, WindowsFromGone.)
		for hour, n in pairs(p and type(p.wj) == "table" and p.wj or {}) do
			if type(hour) == "number" and type(n) == "number" and hour >= from then
				out.points, aj = out.points + n * Count.POINTS_JOIN, aj + n
			end
		end
		for hour, n in pairs(p and type(p.wy) == "table" and p.wy or {}) do
			if type(hour) == "number" and type(n) == "number" and hour + Count.STAY_DAYS * DAY >= from then
				out.points, ay = out.points + n * Count.POINTS_STAY, ay + n
			end
		end
	end
	out.joins, out.stays = out.joins + aj, out.stays + ay
	out.archived.joins, out.archived.stays = aj, ay
	return out
end

-- A person's score: own points plus the shares of the own points of the levels under him.
-- Returns score, own, share, { level1, level2, level3 } (each level's share), network recruits.
function Count.Score(key, window, cache)
	cache = cache or {}
	local function OwnOf(k)
		if not cache[k] then cache[k] = Count.Own(k, window) end
		return cache[k]
	end
	local own = OwnOf(key)
	local levels, share = { 0, 0, 0 }, 0
	local frontier = { key }
	for level = 1, #Count.SHARES do
		local nextFrontier = {}
		for _, k in ipairs(frontier) do
			for _, child in ipairs(Church.Children(k)) do
				nextFrontier[#nextFrontier + 1] = child.key
				levels[level] = levels[level] + OwnOf(child.key).points * Count.SHARES[level]
			end
		end
		share = share + levels[level]
		frontier = nextFrontier
	end
	-- The whole network's recruits, every level (an Apostle's growth).
	local net, queue, seen = own.joins, {}, { [key] = true }
	for _, child in ipairs(Church.Children(key)) do queue[#queue + 1] = child.key end
	local i = 1
	while i <= #queue and i <= Church.MISSIONARIES_MAX do
		local k = queue[i]
		i = i + 1
		if not seen[k] then
			seen[k] = true
			net = net + OwnOf(k).joins
			for _, child in ipairs(Church.Children(k)) do queue[#queue + 1] = child.key end
		end
	end
	return own.points + share, own.points, share, levels, net, own
end

local function PublicOf(key)
	local p = Led().p[key]
	return p and p.pub == true or false
end

-- (1.5.8) The recruiters ranking, list u: the author's characters, the King and the High Council
-- see it until it opens to everyone. Any keeper serves it from its own ledger, as the other lists.
function Count.CanSeeRecruiters(name)
	if type(name) ~= "string" or name == "" then return false end
	return Church.IsAuthor(name) or Church.IsKing(name)
		or (ns.IsHighCouncillor and ns.IsHighCouncillor(ns.FullName(name)) == true) or false
end

-- Everyone this ledger credits with a recruit, whatever his place in the Church now: his own points
-- only (Count.Own), POINTS_JOIN for each confirmed recruit and POINTS_STAY more when that recruit is
-- still in Olympus STAY_DAYS later, the same direct points an Apostle earns, and no share of anyone
-- else's. Only a credited claim counts: a report only its recruiter's client stands behind, an open
-- registration, a transfer, an alt or a recruit another claim took never do. The archive's joins
-- count too: its records (another keeper's, Count.TakeArchived, come with no person line) and its
-- totals. A recruiter with only a stay in the window is listed, as the missionaries' ranking does.
-- (A person line Count.Prune made holds his folded key as his name: the Church's own spelling first.)
local function RecruiterName(key, name)
	if type(name) == "string" and name ~= "" and Key(name) ~= name then return Short(name) end
	local S = Church.State()
	local place = Church.Place(key)
	local corr = S.corrOf[key] and S.corr[S.corrOf[key]]
	return (place and Short(place.n)) or (corr and Short(corr.n)) or Short(name) or key
end
local function RecruiterRanking(window)
	local C, l = Count.Credits(), Led()
	local rows, seen = {}, {}
	local function Add(key, name)
		if not key or seen[key] then return end
		seen[key] = true
		local o = Count.Own(key, window)
		if o.joins <= 0 and o.points <= 0 then return end
		rows[#rows + 1] = { key = key, name = RecruiterName(key, name), score = o.points, own = o.points, share = 0,
			joins = o.joins, stays = o.stays, net = o.joins, pub = PublicOf(key) }
	end
	for key, ids in pairs(C.byPerson) do
		local r = C.r[ids[1]]
		Add(key, r and r.bn)
	end
	for key, p in pairs(l.p) do Add(key, type(p) == "table" and p.n or nil) end
	for key in pairs(Arc()) do Add(key, nil) end
	table.sort(rows, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		if a.joins ~= b.joins then return a.joins > b.joins end
		return a.key < b.key
	end)
	for i, row in ipairs(rows) do row.rank = i end
	return rows
end

-- A ranking on this keeper's own ledger: list a (Apostles), m (missionaries), c (correspondents);
-- window w, m, a. Rows: { rank, key, name, role, score, own, share, levels, joins, stays, net, pub }.
function Count.Ranking(list, window)
	if list == "u" then return RecruiterRanking(window) end
	-- The invitation wire has no guild/day evidence. It must never masquerade as fullness.
	if list == "c" then return {} end
	local S = Church.State()
	local rows, cache = {}, {}
	local function Add(k, n, role)
		local score, own, share, levels, net, o = Count.Score(k, window, cache)
		rows[#rows + 1] = { key = k, name = Short(n), role = role, score = score, own = own, share = share, levels = levels,
			joins = o.joins, stays = o.stays, net = net, pub = PublicOf(k) }
	end
	if list == "a" then
		for _, k in ipairs(S.order) do Add(k, S.apostle[k].n, "A") end
	elseif list == "m" then
		for k, m in pairs(S.miss) do if m.valid then Add(k, m.n, "M") end end
	elseif list == "c" then
		for _, c in pairs(S.corr) do
			local k = Key(c.n)
			if k and not S.apostle[k] and not (S.miss[k] and S.miss[k].valid) then Add(k, c.n, "C") end
		end
	end
	table.sort(rows, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		if a.own ~= b.own then return a.own > b.own end
		return a.key < b.key
	end)
	local me = Key(ns.me)
	local out = {}
	for i, row in ipairs(rows) do
		row.rank = i
		if list == "a" or row.score > 0 or row.joins > 0 or row.key == me then out[#out + 1] = row end
	end
	return out
end

-- The top 3 of the Apostles and of the missionaries over the last 30 days, among the people who
-- show their row publicly (D8): { a = { names }, m = { names } }.
function Count.ComputeTop3()
	local out = {}
	for _, list in ipairs({ "a", "m" }) do
		local names = {}
		for _, row in ipairs(Count.Ranking(list, "m")) do
			if row.pub and row.score > 0 and #names < 3 then names[#names + 1] = row.name end
		end
		out[list] = names
	end
	return out
end

---------------------------------------------------------------------------
-- Seen-checks (the desk's)
---------------------------------------------------------------------------

local queued, queuedSet, openSet = {}, {}, {}
function Count.QueueCheck(id, why)
	local k = id .. ":" .. why
	if queuedSet[k] or openSet[k] or #queued >= Count.RECORDS_MAX then return end
	queuedSet[k] = true
	queued[#queued + 1] = { id = id, why = why }
end

-- Which checks each record needs now: j once for a new join, r on the registration's days (one
-- the desk missed, the 14th day's too, runs later, up to REG_LATE days past the last; its answer
-- still needs the player's arrival within REG_DAYS), 7 on the days after STAY_DAYS (STAY_TRIES).
local function DueChecks(now)
	local C
	for id, r in pairs(Led().r) do
		if r.tj and not r.c and not r.t and not r.a and not r.x then Count.QueueCheck(id, "j")
		elseif r.kind == "g" and not r.tj and not r.t and not r.x then
			local nextDay = Count.REG_CHECKS[(r.rq or 0) + 1]
			local age = now - (r.tc or now)
			if nextDay and age >= nextDay * DAY and age <= (Count.REG_DAYS + Count.REG_LATE) * DAY then Count.QueueCheck(id, "r") end
		elseif r.y == nil and (r.q7 or 0) < Count.STAY_TRIES and r.tj and now >= r.tj + (Count.STAY_DAYS + (r.q7 or 0)) * DAY then
			-- (1.2.3: the credits only for a record whose stay check is due; one with no join has none.)
			C = C or Count.Credits()
			local state = C.states[id]
			if state == "credited" or state == "pending" then Count.QueueCheck(id, "7") end
		end
	end
end

local function CloseCheck(c)
	checks[c.cid] = nil
	openSet[c.rid .. ":" .. c.why] = nil
	local l = Led()
	local r = l.r[c.rid]
	if not r then return end
	local xk = c.rid:match("^([^:]+):")
	local o = {}
	local function Independent(a)
		local k = Key(a.from)
		return k ~= Key(r.bn) and k ~= xk and not Linked(r.bn, a.from)
	end
	if c.why == "j" then
		o.c = 1
		if AltOf(r.n, r.bn) then o.a = 1 end
		-- (A guildmate's roster places the recruit in the guild, not the invite: an invite pair is
		-- confirmed only by another client's own log read, Count.TakeEvidence. A registration's
		-- arrival is a roster's word by design: those answers confirm it, here and at the r check.)
		local ws = {}
		for _, a in ipairs(c.answers) do
			if ns.Fold(a.guild) ~= ns.Fold(r.g or "") then
				if a.first <= Day(r.tj) and a.last >= Day(r.tj) - Count.NEW_DAYS then o.t = 1 end
			elseif a.first < Day(r.tc) - 1 then
				o.t = 1
			elseif r.kind == "g" and Independent(a) then
				ws[#ws + 1] = Key(a.from)
			end
		end
		if #ws > 0 then o.ws = ws end
	elseif c.why == "r" then
		o.rq = (r.rq or 0) + 1
		local regDay = Day(r.tc)
		for _, a in ipairs(c.answers) do
			if a.first < regDay - 1 and (a.now or a.last >= regDay - Count.NEW_DAYS) then
				o.t = 1
			elseif a.now and a.first >= regDay - 1 and a.first <= regDay + Count.REG_DAYS then
				o.tj, o.g = a.first * DAY + DAY / 2, a.guild
				if Independent(a) then o.ws = { Key(a.from) } end
			end
		end
		if o.t then o.tj, o.g, o.ws = nil, nil, nil elseif o.tj then o.c = 1 end
	elseif c.why == "7" then
		o.q7 = (r.q7 or 0) + 1
		local now, left = false, false
		for _, a in ipairs(c.answers) do
			if a.now then now = true elseif a.last < Day(Clock()) - 1 then left = true end
		end
		if now then o.y = 1 elseif left and o.q7 >= Count.STAY_TRIES then o.y = 0 end
	end
	Count.MergeIn(c.rid, o, true)
end
Count.CloseCheck = CloseCheck

-- A channel check is public, but its id grants no right to fill the desk's answer slots. Keep
-- the ordinary members our fresh roster names and the authenticated keepers/council already
-- heard when it goes out. Signed keepers of other guilds may relay their own roster facts.
local function CheckRecipients()
	local out = {}
	local R = ns.Roster
	if R and R.Fresh and R.Fresh() then
		for _, row in ipairs(R.members or {}) do
			local k = Key(row.full or row.name)
			if k then out[k] = "roster" end
		end
	end
	for _, h in pairs(Church.Heard()) do
		local k = Key(h.name)
		if k then
			if Church.IsKeeper(h.name) then out[k] = "keeper"
			elseif Church.IsKing(h.name) then out[k] = "king"
			elseif ns.IsHighCouncillor(ns.FullName(h.name)) then out[k] = "council" end
		end
	end
	return out
end

local function ExpectedAnswer(c, sender)
	local kind = c.expected and c.expected[Key(sender)]
	if kind == "roster" then
		local R = ns.Roster
		return R and R.Fresh and R.Fresh() and R.RankOf(ns.FullName(sender)) ~= nil
	elseif kind == "keeper" then return Church.IsKeeper(sender)
	elseif kind == "king" then return Church.IsKing(sender)
	elseif kind == "council" then return ns.IsHighCouncillor(ns.FullName(sender)) == true end
	return false
end

-- The desk's work each tick: due checks out within CHECKS_HOUR, CHECKS_TICK a tick, open ones closed
-- after CHECK_TTL. (1.2.3: the due ones looked for when the ledger changed, else DUE_EVERY; the checks
-- of one tick share one list of who may answer, read only.)
local dueRev, dueAt = nil, -math.huge
function Count.DeskTick(now)
	local t = ns.Now()
	for _, c in pairs(checks) do
		if t - c.sent >= Count.CHECK_TTL then CloseCheck(c) end
	end
	if not Church.IsDesk() or Church.IsKing(ns.me) or Off() then return end
	if dueRev ~= ledRev or now - dueAt >= Count.DUE_EVERY or now < dueAt then
		dueRev, dueAt = ledRev, now
		DueChecks(now)
	end
	for i = #checkTimes, 1, -1 do if t - checkTimes[i] >= 3600 then table.remove(checkTimes, i) end end
	local expected, n = nil, 0
	while #queued > 0 and n < Count.CHECKS_TICK and #checkTimes < Count.CHECKS_HOUR and ns.Comm.QueueRoom() > Count.SEND_ROOM do
		local q = table.remove(queued, 1)
		queuedSet[q.id .. ":" .. q.why] = nil
		local r = Led().r[q.id]
		if r then
			openSet[q.id .. ":" .. q.why] = true
			nextCheck = (nextCheck + 1) % 1679616
			local cid = B36(nextCheck)
			expected = expected or CheckRecipients()
			checks[cid] = { cid = cid, rid = q.id, why = q.why, sent = t, answers = {}, from = {}, expected = expected }
			checkTimes[#checkTimes + 1] = t
			stats.checks, n = stats.checks + 1, n + 1
			ns.Comm.Send("CHANNEL", ("NS~1~q~%s~%s~%s"):format(cid, r.n, q.why), nil, false, false)
		end
	end
end

-- A check heard (from a keeper): answered from this client's roster memory, drawn so that about two
-- clients of each guild answer, after a moment.
function Count.TakeCheck(sender, text)
	local cid, name, why = tostring(text or ""):match("^NS~1~q~([0-9a-z]+)~([^~]+)~([jr7])$")
	name = WireName(name)
	if not cid or not name then return Drop("shape") end
	if not Church.IsKeeper(sender) then return Drop("keeper") end
	if ns.KingsScreen and ns.KingsScreen() then return false, "king" end
	if Off() then return false, "netoff" end
	local t, k = ns.Now(), Key(sender)
	if not heardChecks[k] then Church.Capped(heardChecks, Count.PEOPLE_MAX) end
	local h = heardChecks[k] or {}
	heardChecks[k] = h
	for i = #h, 1, -1 do if t - h[i] >= 3600 then table.remove(h, i) end end
	if #h >= Count.CHECKS_HEARD_HOUR then return Drop("check rate") end
	h[#h + 1] = t
	local fact = Count.Fact(name)
	if not fact then return false, "unknown" end
	local peers = math.max(1, (ns.Comm.PeerCount and ns.Comm.PeerCount()) or 1)
	if Count.chance() > math.min(1, 2 / peers) then return false, "drawn" end
	local g = CleanGuild(fact.guild)
	if not g then return false, "guild" end
	local text2 = ("NS~1~a~%s~%s~%s~%s~%s"):format(cid, g, B36(fact.first), B36(fact.last), fact.now and "1" or "0")
	local who = ns.FullName(sender)
	Count.after(Count.random(1, 8), "church check answer", function()
		ns.Comm.Whisper(who, text2, nil, false, false, nil, { owner = Count })
	end)
	return true
end

-- An answer to one of our open checks: one per sender, CHECK_ANSWERS at most.
function Count.TakeAnswer(sender, text)
	local cid, guild, first, last, now = tostring(text or ""):match("^NS~1~a~([0-9a-z]+)~([^~]+)~([0-9a-z]+)~([0-9a-z]+)~([01])$")
	guild, first, last = CleanGuild(guild), UnB36(first), UnB36(last)
	if not cid or not guild or not first or not last then return Drop("shape") end
	local c = checks[cid]
	if not c then return Drop("no check") end
	if not ns.IsFederation(guild) then return Drop("guild") end
	local M = ns.Moderation
	if M and M.Hides and M.Hides(sender, nil) then return Drop("netoff") end
	if not ExpectedAnswer(c, sender) then return Drop("unasked") end
	local k = Key(sender)
	if c.from[k] then return Drop("twice") end
	if #c.answers >= Count.CHECK_ANSWERS then return Drop("enough") end
	c.from[k] = true
	c.answers[#c.answers + 1] = { from = ns.FullName(sender), guild = guild, first = first, last = last, now = now == "1" }
	stats.answers = stats.answers + 1
	if #c.answers >= Count.CHECK_ANSWERS then CloseCheck(c) end
	return true
end

function Count.OpenChecks() return checks end

---------------------------------------------------------------------------
-- The ledger between keepers
---------------------------------------------------------------------------

local function Flags(r)
	local f = (r.s and "s" or "") .. (r.t and "t" or "") .. (r.a and "a" or "") .. (r.x and "x" or "") .. (r.c and "c" or "")
		.. (r.y == 1 and "y" or (r.y == 0 and "n" or "")) .. tostring(math.min(9, r.q7 or 0)) .. tostring(math.min(9, r.rq or 0))
	return f
end

function Count.RecordLine(id, r, shortNames)
	local n, bn = r.n, r.bn
	if shortNames then n, bn = Short(n), Short(bn) end
	return ("NL~1~r~%s~%s~%s~%s~%s~%s~%s~%s~%s"):format(n, bn, CleanGuild(r.g) or "-", r.kind == "g" and "g" or "i", B36(r.tc or 0),
		r.tj and B36(r.tj) or "-", Flags(r), r.ws and table.concat(r.ws, ",") or "-", B36(r.u or 0))
end

local function ParseRecord(text)
	local n, bn, g, kind, tc, tj, flags, ws, u = tostring(text or ""):match("^NL~1~r~([^~]+)~([^~]+)~([^~]+)~([ig])~([0-9a-z]+)~([0-9a-z%-]+)~([%w]*)~([^~]+)~([0-9a-z]+)$")
	if not n then return nil end
	local recruit, recruiter = WireName(n), WireName(bn)
	if not recruit or not recruiter then return nil end
	local guild = g ~= "-" and CleanGuild(g) or nil
	if g ~= "-" and (not guild or not ns.IsFederation(guild)) then return nil end
	local q7, rq = flags:match("(%d)(%d)$")
	local rec = { n = Short(recruit), bn = Short(recruiter), g = guild, kind = kind, tc = UnB36(tc), tj = tj ~= "-" and UnB36(tj) or nil,
		s = flags:find("s", 1, true) and 1 or nil, t = flags:find("t", 1, true) and 1 or nil, a = flags:find("a", 1, true) and 1 or nil,
		x = flags:find("x", 1, true) and 1 or nil, c = flags:find("c", 1, true) and 1 or nil,
		y = flags:find("y", 1, true) and 1 or (flags:find("n", 1, true) and 0 or nil), q7 = tonumber(q7), rq = tonumber(rq) }
	if not rec.tc or (tj ~= "-" and not rec.tj) then return nil end
	if ws ~= "-" then
		local list = {}
		for s in ws:gmatch("[^,]+") do
			local k = Key(WireName(s))
			if not k then return nil end
			list[#list + 1] = k
		end
		rec.ws = Sources(list)
	end
	return Key(recruit) .. ":" .. Key(recruiter), rec, UnB36(u)
end
Count.ParseRecord = ParseRecord

function Count.PersonLine(k, p)
	return ("NL~1~p~%s~%s~%s~%d~%d~%d~%s"):format(p.n or k, p.pub and "1" or "0", B36(p.pat or 0), p.ap or 0, p.aj or 0, p.ay or 0, B36(p.u or 0))
end

-- An archived record (1.2.1): its recruit's and recruiter's keys stand for their names.
function Count.ArchiveLine(xk, by, a)
	return ("NL~1~z~%s~%s~%s~%s~%s"):format(xk, by, B36(math.max(0, math.floor(a.h))), a.y == 1 and "1" or "0", B36(tonumber(a.t) or 0))
end

-- The transfers waiting go out one after another, leaving room in Comm's queue.
local pumping = false
local function LedgerEnd(o)
	if not o.terminal or not o.closed or o.pending > 0 or o.failed then return end
	local line = o.terminal
	o.terminal = nil
	local function Send()
		if ns.Comm.QueueRoom() > Count.SEND_ROOM and (not o.guard or o.guard()) then
			ns.Comm.Whisper(o.target, line, nil, false, false, nil, { owner = Count, guard = o.guard })
		end
	end
	if ns.Comm.QueueRoom() > Count.SEND_ROOM then Send() else Count.after(3, "church ledger terminal", Send) end
end

local function PumpOut()
	pumping = false
	while outq[1] and ns.Comm.QueueRoom() > Count.SEND_ROOM do
		local o = outq[1]
		if o.guard and not o.guard() then o.failed = true end
		while o.i <= #o.list and not o.failed and ns.Comm.QueueRoom() > Count.SEND_ROOM do
			local done
			if o.terminal then
				o.pending = o.pending + 1
				done = function(ok)
					o.pending = o.pending - 1
					if not ok then o.failed = true end
					LedgerEnd(o)
				end
			end
			ns.Comm.Whisper(o.target, o.list[o.i], nil, false, false, done, { owner = Count, guard = o.guard })
			o.i = o.i + 1
		end
		if o.i <= #o.list and not o.failed then break end
		table.remove(outq, 1)
		o.closed = true
		LedgerEnd(o)
	end
	if outq[1] then
		pumping = true
		Count.after(3, "church lines", PumpOut)
	end
end

local function SendLines(target, list, terminal, guard)
	if #list == 0 and not terminal then return true end
	if #outq >= 8 then return Drop("busy") end
	outq[#outq + 1] = { target = target, list = list, i = 1, terminal = terminal, pending = 0, guard = guard }
	if not pumping then PumpOut() end
	return true
end
Count.SendLines = SendLines

-- A ledger line to every keeper online, then to the council relays online while Comm's queue has
-- room past SEND_ROOM. (Sent to every relay alike, with room wanted for each before a push, a council
-- or King client online cost the other keepers a keeper's word; a 1.2.5.1 councillor drops the line
-- anyway.) Never to the King's client: as in 1.2.5.1, it does no background Church work.
function Count.ToRelays(line)
	for _, k in ipairs(Church.KeepersOnline(false)) do ns.Comm.Whisper(k.name, line, nil, false, false, nil, { owner = Count }) end
	for _, k in ipairs(Church.LedgerRelaysOnline(false)) do
		if not Church.IsKeeper(k.name) and not Church.IsKing(k.name) then
			if ns.Comm.QueueRoom() <= Count.SEND_ROOM then break end
			ns.Comm.Whisper(k.name, line, nil, false, false, nil, { owner = Count })
		end
	end
end

-- A keeper's verified result to the keepers and the trusted ledger relays online (Count.ToRelays).
-- Relays retain the exact same record; they do not create Church evidence.
function Count.Push(id)
	local r = Led().r[id]
	if not r then return end
	Count.ToRelays(Count.RecordLine(id, r))
end

local function LedgerScope()
	local group = ns.group
	if type(group) == "string" and group:match("^Forever%a+$") and ns.faction then return group .. ":" .. ns.faction end
end

local function LedgerPeer(name, scope)
	return scope ~= nil and LedgerScope() == scope and ns.ForeverFamily(ns.RealmOf(name)) == ns.group
end

local function LedgerAccess(name)
	if not Church.IsLedgerRelay(ns.me) or not Church.IsLedgerRelay(name) then return false, "relay" end
	if Church.IsKing(ns.me) or Church.IsKing(name) then return false, "king" end
	if Church.IsKeeper(ns.me) and not Church.IsKeeper(name) then return false, "keeper" end
	return true
end

local function SendCatchUp(name, k, since, tie, legacy, cutoff, replay)
	catch.page = nil
	local scope, ledger = LedgerScope(), catch.ledger
	if scope and not LedgerPeer(name, scope) then return false end
	local function Guard()
		return catch.active == k and catch.ledger == ledger and Led() == ledger and not Off()
			and LedgerScope() == scope and LedgerAccess(name)
	end
	if legacy or not scope then
		return ns.Comm.Whisper(name, "NL~1~q~" .. B36(since), nil, false, false, nil, { owner = Count, guard = Guard })
	end
	catch.seq = (catch.seq or 0) + 1
	catch.salt = catch.salt or Count.random(0, 2147483647)
	local id = B36(Clock()) .. B36(catch.salt) .. B36(catch.seq)
	local page = { k = k, id = id, scope = scope, since = since, tie = tie, cutoff = cutoff, replay = replay,
		slots = {}, keys = {}, count = 0, high = 0 }
	catch.page = page
	local text = ("NL~2~q~%s~%s~%s~%s~%s"):format(id, scope, B36(since), B36(cutoff or 0), tie or "-")
	return ns.Comm.Whisper(name, text, nil, false, false, function(ok)
		if not ok or catch.page ~= page then return end
		page.sent = true
		catch.last = ns.Now()
		if replay then return end -- replay only runs with a known v2 peer
		Count.after(Count.CATCHUP_LEGACY_WAIT, "church legacy catch-up", function()
			if catch.page ~= page or page.modern or not Guard() then return end
			if type(ledger.nl2) == "table" and ledger.nl2[k] then return end
			SendCatchUp(name, k, ledger.from[k] or 0, nil, true)
		end)
	end, { owner = Count, guard = function()
		return catch.page == page and Guard()
	end })
end

local function EndReplay(replay, result)
	catch.active, catch.page = nil, nil
	catch.last, catch.heard = replay.last, replay.heard
	replay.result = result
end

-- A keeper can revisit recent records a pre-v2 transfer skipped. This is a separate
-- read of already verified records, so neither its scope nor its progress changes a normal cursor.
function Count.ReplayRecent()
	local scope, now = LedgerScope(), ns.Now()
	if not scope or not Church.IsKeeper(ns.me) or Church.IsKing(ns.me) or Off() or catch.active then return false end
	if now - (catch.replay and catch.replay.at or -math.huge) < Count.CATCHUP_REASK then return false end
	local l = Led()
	for _, peer in ipairs(Church.KeepersOnline(false)) do
		local k = Key(peer.name)
		if type(l.nl2) == "table" and l.nl2[k] and LedgerPeer(peer.name, scope) then
			local replay = { at = now, last = catch.last, heard = catch.heard, pages = 0, result = "waiting" }
			catch.ledger, catch.active, catch.last, catch.heard = l, k, now, -math.huge
			if not SendCatchUp(peer.name, k, math.max(0, Clock() - 7 * DAY), nil, false, nil, replay) then
				EndReplay(replay, "unsent")
				return false
			end
			catch.replay = replay
			return true
		end
	end
	return false
end

-- A keeper asks another for what changed since its last catch-up from him: the one asked or caught
-- up from least lately, the desk first (1.2.1: each keeper online in turn. Asking only the first,
-- nobody ever asked one further down the list, and the records only he held, taken while he was the
-- only keeper online, never reached the others). When a catch-up from each last completed is saved,
-- Led().caught, and when each was last asked, Led().asked: with whom it asked kept only for the
-- session, every /reload began with the first by name again, one more each half hour, and a keeper
-- far down the list was never caught up from; with only the completed ones saved, a keeper that
-- never answered (a busy desk) was asked first in every session. One whose last catch-up brought
-- something but was cut short before its end is asked first again (TakeLine clears his ask).
-- A keeper asks only keepers: it takes ledger lines from no other relay (Count.TakeLine). A council
-- relay asks only while no keeper is online, its pages asking a keeper then (Count.Ask), and never
-- the King's client, which, as in 1.2.5.1, does no background Church work: it asks for none either.
-- Just logged in, it waits until every keeper online has been heard (SettledSinceLogin, as the desk
-- does before it speaks for its switch): at once, the first keeper heard was the one asked, whatever
-- the saved turn said, and the next catch-up came CATCHUP_EVERY later. Completed sources now sweep
-- the other keepers promptly; an active paged response stays with its source until completion or
-- CATCHUP_RETRY of silence. Each source still waits at least CATCHUP_REASK between fresh attempts.
function Count.CatchUp(force, sweep)
	if not Church.IsLedgerRelay(ns.me) or Church.IsKing(ns.me) or Off() then return false end
	local l = Led()
	-- A character can change role without reloading. A request for the council copy
	-- must never commit a cursor in the keeper's separate ledger, or the reverse.
	if catch.ledger and catch.ledger ~= l then
		if catch.page and catch.page.replay then EndReplay(catch.page.replay, "interrupted") end
		catch.active, catch.page, catch.last, catch.heard = nil, nil, -math.huge, -math.huge
		catch.ledger, catch.asked, catch.settled = l, {}, false
	end
	local t = ns.Now()
	local retry = catch.active ~= nil and t - math.max(catch.last, catch.heard) >= Count.CATCHUP_RETRY
	if catch.page and catch.page.replay then
		if not retry and not force then return false end
		EndReplay(catch.page.replay, "interrupted")
	end
	if sweep and catch.active ~= nil then return false end
	local rotating = sweep or catch.rotate
	if not force and (((not rotating and t - catch.last < Count.CATCHUP_EVERY) and not retry)
		or not Count.SettledSinceLogin()) then return false end
	local list = Church.KeepersOnline(false)
	if not Church.IsKeeper(ns.me) then
		if #list > 0 then return false end
		list = Church.LedgerRelaysOnline(false)
	end
	local caught = type(l.caught) == "table" and l.caught or {}
	local asked = type(l.asked) == "table" and l.asked or {}
	local soon = rotating or (not force and t - catch.last < Count.CATCHUP_EVERY)
	local scope = LedgerScope()
	local k, at
	for _, o in ipairs(list) do
		local rk = Key(o.name)
		local lastAsked = math.max(tonumber(asked[rk]) or -math.huge, catch.asked[rk] or -math.huge)
		if not Church.IsKing(o.name) and (not scope or LedgerPeer(o.name, scope))
			and not (soon and t - lastAsked < Count.CATCHUP_REASK) then
			local seen = math.max(tonumber(caught[rk]) or -math.huge, tonumber(asked[rk]) or -math.huge, catch.asked[rk] or -math.huge)
			if not k or seen < at then k, at = o, seen end
		end
	end
	if not k then
		-- The active keeper may have disappeared before answering. Do not leave its name behind:
		-- if a keeper becomes available later, the next ordinary tick must be allowed to choose it
		-- instead of waiting CATCHUP_EVERY on an impossible active request.
		if retry then
			-- Preserve `last` and the per-target ask stamp. Clearing those let an ordinary Tick select
			-- the same one silent keeper again on every frame. `rotate` permits a newly visible/different
			-- keeper immediately, while CATCHUP_REASK still bounds the silent keeper itself.
			catch.active, catch.heard, catch.rotate, catch.page = nil, -math.huge, true, nil
		end
		return false
	end
	local rk = Key(k.name)
	catch.last = t
	catch.active, catch.ledger = rk, l
	catch.heard = -math.huge
	catch.rotate = false
	catch.asked[rk] = t
	if type(l.asked) ~= "table" then l.asked = {} end
	l.asked[rk] = t
	SendCatchUp(k.name, rk, l.from[rk] or 0)
	return true
end

-- The records and the person lines changed after `since`, in one order (their time, then their
-- id), CATCHUP_LINES a round. A round ends only between two different times: the next round asks
-- for what is newer than the last one sent, so nothing of the same second is left behind (if
-- more than a round share one second, they all go in this one). The last round ends a second before
-- this one at the latest: a record changed later in this second has that time too, and the next
-- catch-up, asking for what is newer than the end, never took it. A keeper answers keepers only (as
-- in 1.2.5.1, Count.TakeLine), and none while its own first catch-up goes on (Count.Settled): two
-- keepers just logged in each took the other's ledger, behind a third's, for a catch-up, and
-- answered pages from it until the next one, half an hour later. Unanswered, the one asking asks the
-- next keeper (Count.CatchUp).
function Count.AnswerCatchUp(sender, since, request, tie, cutoff)
	local allowed, why = LedgerAccess(sender)
	if not allowed then return Drop(why) end
	if Church.IsKeeper(ns.me) and not Count.Settled() then return Drop("catching up") end
	local l, scope = Led(), LedgerScope()
	local function Guard()
		return Led() == l and LedgerScope() == scope and (not scope or LedgerPeer(sender, scope))
			and not Off() and LedgerAccess(sender)
	end
	local list = {}
	local ceiling = cutoff or math.huge
	local function AfterCursor(at, id)
		return at <= ceiling and (at > since or (tie and at == since and id > tie))
	end
	for id, r in pairs(l.r) do if AfterCursor(r.u or 0, id) then list[#list + 1] = { id = id, r = r, u = r.u or 0 } end end
	-- (1.2.1: the archived records too, each before the person line of the same second: "}" < "~".)
	for by, set in pairs(Arc()) do
		for xk, a in pairs(type(set) == "table" and set or {}) do
			local id = "}" .. xk .. ":" .. by
			if type(a) == "table" and type(a.h) == "number" and AfterCursor(tonumber(a.t) or 0, id) then
				list[#list + 1] = { id = id, z = true, xk = xk, by = by, a = a, u = tonumber(a.t) or 0 }
			end
		end
	end
	for k, p in pairs(l.p) do if AfterCursor(p.u or 0, "~" .. k) then list[#list + 1] = { id = "~" .. k, k = k, p = p, u = p.u or 0 } end end
	table.sort(list, function(a, b) if a.u ~= b.u then return a.u < b.u end return a.id < b.id end)
	local cut = math.min(#list, Count.CATCHUP_LINES)
	if request then cut = math.min(cut, Count.CATCHUP_V2_MAX)
	elseif cut < #list then
		local after = list[cut + 1].u
		local j = cut
		while j >= 1 and list[j].u == after do j = j - 1 end
		if j >= 1 then cut = j else
			while cut < #list and list[cut + 1].u == after do cut = cut + 1 end
		end
	end
	local lines, last = {}, since
	for i = 1, cut do
		local e = list[i]
		local row = (e.r and Count.RecordLine(e.id, e.r, request ~= nil)) or (e.z and Count.ArchiveLine(e.xk, e.by, e.a)) or Count.PersonLine(e.k, e.p)
		lines[i] = request and ("NL~2~d~%s~%d~%s"):format(request, i, row:sub(6)) or row
		-- Preflight the complete page against the actual Comm.Whisper limit. One bad saved
		-- row must not emit a terminal that certifies the rows on either side of it.
		if request and #lines[i] > LEDGER_WHISPER_BYTES then return Drop("wire size") end
		last = e.u
	end
	local more = cut < #list
	if request then
		local nextTie = more and list[cut + 1].u == last and list[cut].id or "-"
		local terminal = ("NL~2~e~%s~%d~%s~%s~%s~%s"):format(request, cut, more and "1" or "0", B36(last), B36(cutoff), nextTie)
		return SendLines(ns.FullName(sender), lines, terminal, Guard)
	end
	if not more then last = math.min(last, Clock() - 1) end
	-- A failed native row must not advance the recipient's cursor past a record it could not receive.
	local terminal = ("NL~1~e~%s~%s"):format(more and "1" or "0", B36(last))
	return SendLines(ns.FullName(sender), lines, terminal, Guard)
end

-- (1.2.1) Person lines refused while this book did not place their person yet (a naming it has not
-- heard yet, just logged in): tried again each tick, LATER_KEEP at most and LATER_MAX of them, as
-- Church.lua's acts wait for their actor's place (Church.RetryPending).
Count.LATER_MAX, Count.LATER_KEEP = 200, 1800
local later, retrying = {}, false
local function Later(sender, text)
	if retrying then return end
	local ledger = Led()
	for _, l in ipairs(later) do if l.ledger == ledger and l.text == text then return end end
	if #later >= Count.LATER_MAX then table.remove(later, 1) end
	later[#later + 1] = { sender = sender, text = text, t = ns.Now(), ledger = ledger }
end
function Count.RetryLater()
	if #later == 0 then return 0 end
	local list, t, ledger, taken = later, ns.Now(), Led(), 0
	later, retrying = {}, true
	for _, l in ipairs(list) do
		if t - l.t <= Count.LATER_KEEP then
			if l.ledger == ledger then
				local ok, why = Count.TakeLine(l.sender, l.text)
				if ok then taken = taken + 1 elseif why == "person" then later[#later + 1] = l end
			else
				later[#later + 1] = l
			end
		end
	end
	retrying = false
	return taken
end
function Count.LaterLines() return later end

-- (1.2.1) A keeper's record line, checked again as its evidence was: a recruit who is not his recruiter,
-- nothing dated ahead, and witnesses who are neither the recruiter, the recruit nor a character linked to
-- either (those go). A keeper's line vouches for the rest, which only a keeper of the pair's guild can
-- check (VerifiedWitness). (Not the recruiter's place: one removed and named again later holds an
-- older record every keeper took; refused on one, the keepers' numbers would part.)
local function RecheckRecord(id, rec)
	local xk, by = id:match("^([^:]+):(.+)$")
	if not xk or xk == by then return Drop("self") end
	local now = Clock()
	if (rec.tc or 0) > now + 3600 or (rec.tj and rec.tj > now + 3600) then return Drop("ahead") end
	if rec.ws then
		local ws = {}
		for _, s in ipairs(rec.ws) do
			if s ~= by and s ~= xk and not Linked(s, rec.bn) and not Linked(s, rec.n) then ws[#ws + 1] = s end
		end
		rec.ws = #ws > 0 and ws or nil
	end
	return true
end

local function FinishCatchUp(sender, more, u, tie, page)
	local k, l = Key(sender), Led()
	local before = l.from[k] or 0
	local replay = page and page.replay
	if replay then
		replay.pages = replay.pages + 1
		if not more then EndReplay(replay, "complete"); return true end
	else
		l.from[k] = math.max(before, tie and u - 1 or u)
	end
	if not more then
		if not catch.settled then catch.settled = true; ViewChanged() end
		if catch.active == k then catch.active, catch.page = nil, nil end
		if type(l.caught) ~= "table" then l.caught = {} end
		l.caught[k] = ns.Now()
		Count.after(1, "church catch-up sweep", function()
			if catch.active == nil then Count.CatchUp(false, true) end
		end)
		return true
	end
	if not replay and l.from[k] > before and type(l.asked) == "table" then l.asked[k] = nil end
	if catch.active == k then
		local who = ns.FullName(sender)
		Count.after(5, "church catch-up", function()
			if catch.active ~= k or catch.page ~= page or catch.ledger ~= l or Led() ~= l then return end
			local now = ns.Now()
			catch.last = now
			if not replay then catch.asked[k] = now end
			SendCatchUp(who, k, page and u or (Led().from[k] or 0), tie, not page, page and page.terminal.cutoff, replay)
		end)
	end
	return true
end

local function LedgerTie(tie)
	if tie == "-" then return nil, true end
	if #tie > 62 or tie:gsub("^~", ""):find("[~|%c]") then return nil, false end
	return tie, true
end

local function CatchRowId(row)
	local kind, first, second = row:match("^([rpz])~([^~]+)~([^~]+)~")
	local name = first and WireName(first)
	if not name then return nil end
	if kind == "p" then return "~" .. Key(name) end
	local recruiter = WireName(second)
	if not recruiter then return nil end
	return (kind == "z" and "}" or "") .. Key(name) .. ":" .. Key(recruiter)
end

local function ProvePage(sender, page)
	local e = page.terminal
	if not e or page.count ~= e.count then return true end
	if page.high ~= e.count or (e.count > 0 and (page.slots[e.count].at ~= e.at
		or (e.tie and page.slots[e.count].key ~= e.tie))) then return Drop("page") end
	page.complete = true
	return FinishCatchUp(sender, e.more, e.at, e.tie, page)
end

local function RowBefore(a, b)
	return a.at < b.at or (a.at == b.at and a.key < b.key)
end

local function TakeCatchPage(sender, text)
	local scope, k = LedgerScope(), Key(sender)
	if not LedgerPeer(sender, scope) or not k or Off() then return Drop("scope") end
	if #text > LEDGER_WHISPER_BYTES then return Drop("wire size") end
	local kind, id, body = text:match("^NL~2~([qde])~([0-9a-z]+)~(.+)$")
	if not id then id, kind = text:match("^NL~2~a~([0-9a-z]+)$"), "a" end
	if not id or #id > 16 then return Drop("shape") end
	if kind == "q" then
		local theirs, since, cutoff, tie = body:match("^([^~]+)~([0-9a-z]+)~([0-9a-z]+)~(.+)$")
		if theirs ~= scope then return Drop("scope") end
		since, cutoff = UnB36(since), UnB36(cutoff)
		local latest = Clock() - 1
		if cutoff == 0 then cutoff = latest end
		local nextTie, valid = LedgerTie(tie)
		if not valid or not since or not cutoff or since > cutoff or cutoff > latest then return Drop("shape") end
		catch.serve = catch.serve or {}
		local now = ns.Now()
		if now - (catch.serve[k] or -math.huge) < 4 then return Drop("ask rate") end
		if not catch.serve[k] then Church.Capped(catch.serve, Church.HEARD_MAX) end
		catch.serve[k] = now
		if ns.Comm.QueueRoom() > Count.SEND_ROOM then
			ns.Comm.Whisper(ns.FullName(sender), "NL~2~a~" .. id, nil, false, false, nil, { owner = Count })
		end
		return Count.AnswerCatchUp(sender, since, id, nextTie, cutoff)
	end
	local page = catch.page
	if not page or not page.sent or page.complete or catch.active ~= k or page.k ~= k
		or page.scope ~= scope or page.id ~= id or catch.ledger ~= Led() then return Drop("unasked") end
	if not page.modern then
		local l = Led()
		if type(l.nl2) ~= "table" then l.nl2 = {} end
		if not l.nl2[k] then Church.Capped(l.nl2, Church.HEARD_MAX) end
		l.nl2[k], page.modern = true, true
	end
	if kind == "a" then catch.heard = ns.Now(); return true end
	if kind == "e" then
		local n, more, at, cutoff, tie = body:match("^(%d+)~([01])~([0-9a-z]+)~([0-9a-z]+)~(.+)$")
		if not n then return Drop("shape") end
		n, more, at, cutoff = tonumber(n), more == "1", UnB36(at), UnB36(cutoff)
		local nextTie, valid = LedgerTie(tie)
		if not valid or not at or not cutoff or at < page.since or at > cutoff or cutoff > Clock()
			or (page.cutoff and cutoff ~= page.cutoff) or n > Count.CATCHUP_V2_MAX
			or page.high > n or (nextTie and not more) or (n == 0 and (more or at ~= page.since))
			or (more and at == page.since and (not page.tie or (nextTie and nextTie <= page.tie))) then return Drop("page") end
		if page.terminal then return Drop("duplicate") end
		page.terminal = { count = n, more = more, at = at, tie = nextTie, cutoff = cutoff }
	else
		local i, row = body:match("^(%d+)~(.+)$")
		i = tonumber(i)
		local rowId = row and CatchRowId(row)
		local at = row and UnB36(row:match("~([0-9a-z]+)$"))
		if not i or i < 1 or i > Count.CATCHUP_V2_MAX or (page.terminal and i > page.terminal.count)
			or not rowId or not at or at > (page.cutoff or Clock()) or at < page.since
			or (at == page.since and (not page.tie or rowId <= page.tie)) then return Drop("page") end
		if page.slots[i] or page.keys[rowId] then return Drop("duplicate") end
		local slot, previous, following = { key = rowId, at = at }, page.slots[i - 1], page.slots[i + 1]
		if (previous and not RowBefore(previous, slot)) or (following and not RowBefore(slot, following)) then return Drop("page") end
		local _, why = Count.TakeLine(sender, "NL~1~" .. row)
		if why and why ~= "person" then return false, why end
		page.slots[i], page.keys[rowId] = slot, true
		page.count, page.high = page.count + 1, math.max(page.high, i)
	end
	catch.heard = ns.Now()
	return ProvePage(sender, page)
end

-- (As in 1.2.5.1: the King's client neither asks for a catch-up nor answers one, and holds no copy.
-- On a keeper, every line only from a keeper: a council relay holds copies of the keepers' word and
-- is no source of it. Taken from one, any council or King client could add records and raise the
-- counts every keeper shows. Its asks for a catch-up too: a council client asks only council relays,
-- while no keeper is online (Count.CatchUp); answered here, every ask cost the keeper a round of up to
-- CATCHUP_LINES whispers.)
function Count.TakeLine(sender, text)
	local kind = tostring(text or ""):match("^NL~1~(%a)~")
	local allowed, why = LedgerAccess(sender)
	if not allowed then return Drop(why) end
	local scope = LedgerScope()
	if scope and not LedgerPeer(sender, scope) then return Drop("scope") end
	if type(text) == "string" and text:sub(1, 5) == "NL~2~" then return TakeCatchPage(sender, text) end
	-- (A line from one asked for a catch-up: his answer is coming, Count.CatchUp asks no other yet.)
	if kind ~= "q" and catch.active == Key(sender) and not catch.page then catch.heard = ns.Now() end
	if kind == "q" then
		local since = UnB36(text:match("^NL~1~q~([0-9a-z]+)$"))
		if not since then return Drop("shape") end
		return Count.AnswerCatchUp(sender, since)
	end
	if kind == "r" then
		local id, rec = ParseRecord(text)
		if not id then return Drop("shape") end
		local ok, why = RecheckRecord(id, rec)
		if not ok then return false, why end
		return Count.MergeIn(id, rec, false)
	elseif kind == "p" then
		local n, pub, pat, ap, aj, ay = text:match("^NL~1~p~([^~]+)~([01])~([0-9a-z]+)~(%d+)~(%d+)~(%d+)~[0-9a-z]+$")
		local name = WireName(n)
		if not name then return Drop("shape") end
		-- (1.2.1: a Church person's line, or one this ledger holds; a choice not dated ahead, which would
		-- outlast every later choice of his own; archive totals that add up: stays within joins, points
		-- within what they make.)
		pat, ap, aj, ay = UnB36(pat), tonumber(ap), tonumber(aj), tonumber(ay)
		if not Church.IsPerson(name) and not Led().p[Key(name)] then Later(sender, text) return Drop("person") end
		if not pat or pat > Clock() + Church.DATE_AHEAD then return Drop("ahead") end
		if not (ap and aj and ay) or ay > aj or ap > aj * Count.POINTS_JOIN + ay * Count.POINTS_STAY then return Drop("totals") end
		return Count.TakePerson(Key(name), { n = Short(name), pub = pub == "1", pat = pat, ap = ap, aj = aj, ay = ay })
	elseif kind == "z" then
		local n, bn, h, y = text:match("^NL~1~z~([^~]+)~([^~]+)~([0-9a-z]+)~([01])~[0-9a-z]+$")
		local recruit, recruiter = WireName(n), WireName(bn)
		h = UnB36(h)
		if not recruit or not recruiter or not h or Key(recruit) == Key(recruiter) then return Drop("shape") end
		return Count.TakeArchived(Key(recruit) .. ":" .. Key(recruiter), { h = h, y = y == "1" and 1 or nil })
	elseif kind == "e" then
		local more, u = text:match("^NL~1~e~([01])~([0-9a-z]+)$")
		u = UnB36(u)
		local k = Key(sender)
		if not u or not catch.asked[k] or catch.ledger ~= Led() then return Drop("unasked") end
		if scope and (catch.active ~= k or catch.page) then return Drop("unasked") end
		return FinishCatchUp(sender, more == "1", u)
	end
	return Drop("kind")
end

---------------------------------------------------------------------------
-- Asking a keeper for the numbers, and answering
---------------------------------------------------------------------------

local WHATS = { a = true, m = true, c = true, u = true, me = true, p = true }
local WINDOWS = { w = true, m = true, a = true }

-- May `asker` see `person`'s detail? Himself, the Head, the Apostles, the High Council, the King
-- and the author (D4).
function Count.MaySeeDetail(asker, person)
	if Key(asker) == Key(person) then return Church.InAudience(asker) end
	local role = Church.Role(asker)
	return role == "W" or role == "K" or role == "H" or role == "A" or role == "N"
end

-- A person's detail lines: { kind, a, b, c, d } (s: score own/l1/l2/l3; j: joins, pending, stays,
-- transfers; t: taken, open registrations; g: a guild's joins and stays; r: a registration).
function Count.DetailLines(key, window)
	local score, own, share, levels, net, o = Count.Score(key, window)
	local lines = {
		{ "s", own, levels[1], levels[2], levels[3] },
		{ "j", o.joins, o.pending, o.stays, o.transfers },
		{ "t", o.taken, o.open, net, score },
	}
	local guilds = {}
	for g, v in pairs(o.guilds) do guilds[#guilds + 1] = { g = g, j = v.joins, s = v.stays } end
	table.sort(guilds, function(a, b) if a.j ~= b.j then return a.j > b.j end return a.g < b.g end)
	for i = 1, math.min(5, #guilds) do lines[#lines + 1] = { "g", guilds[i].g, guilds[i].j, guilds[i].s, 0 } end
	-- (1.2.1: the archive's, which keeps no guild, as its own line "-": the lines add up to the joins.)
	if o.archived.joins > 0 or o.archived.stays > 0 then lines[#lines + 1] = { "g", "-", o.archived.joins, o.archived.stays, 0 } end
	local C = Count.Credits()
	local regs = {}
	for id, r in pairs(Led().r) do
		if r.kind == "g" and Key(r.bn) == key then regs[#regs + 1] = { n = r.n, tc = r.tc or 0, state = C.states[id] or "?" } end
	end
	table.sort(regs, function(a, b) return a.tc > b.tc end)
	for i = 1, math.min(Count.REG_OPEN, #regs) do lines[#lines + 1] = { "r", regs[i].n, regs[i].tc, regs[i].state, 0 } end
	return lines, share
end

local function Ten(v) return math.floor((tonumber(v) or 0) * 10 + 0.5) end

local function RowText(list, window, row)
	return ("NR~1~r~%s~%s~%d~%s~%d~%d~%d~%d~%d~%d~%s"):format(list, window, row.rank, row.name, Ten(row.score), Ten(row.own), Ten(row.share),
		row.joins, row.stays, row.net, row.pub and "1" or "0")
end

-- Caught up since this session began, or no other keeper online to be behind of; either only once
-- every keeper online has been heard (Count.SettledSinceLogin: just logged in, it has heard none, and
-- its ledger may be behind every one of them), and SETTLE_MAX after that at most. (The first catch-up
-- waits for the same, so SETTLE_MAX counted from the login left it 240 of its 900 seconds: a desk with
-- a long catch-up answered pages from a ledger still behind.)
function Count.Settled()
	if catch.settled then return true end
	local online = Church.OnlineFor and Church.OnlineFor()
	if online == nil then return true end
	if not Count.SettledSinceLogin() then return false end
	if online >= Church.KEEPER_EVERY * Church.FRESH_FACTOR + Count.SETTLE_MAX then return true end
	return #Church.KeepersOnline(false) == 0
end

function Count.Answer(sender, what, window, person)
	if not Church.IsKeeper(ns.me) or Church.IsKing(ns.me) or Off() then return Drop("not keeper") end
	if not Church.InAudience(sender) then return Drop("audience") end
	local guard
	if what == "u" then
		guard = function()
			return Church.IsKeeper(ns.me) and Count.CanSeeRecruiters(sender) and not Off()
		end
		if not guard() then return Drop("audience") end
	end
	-- (1.2.1: a desk just logged in held a ledger behind the others': every audience page asking it
	-- took its smaller numbers over the ones it had. Unanswered, a page keeps its last answer.)
	if not Count.Settled() then return Drop("catching up") end
	local t, k = ns.Now(), Key(sender)
	if not answersTo[k] then Church.Capped(answersTo, Count.PEOPLE_MAX) end
	local h = answersTo[k] or {}
	answersTo[k] = h
	for i = #h, 1, -1 do if t - h[i] >= Count.ANSWER_WINDOW then table.remove(h, i) end end
	if #h >= Count.ANSWERS_PER then return Drop("ask rate") end
	h[#h + 1] = t
	local lines = {}
	local who = person
	if what == "a" or what == "m" or what == "c" or what == "u" then
		local rows = Count.Ranking(what, window)
		for i, row in ipairs(rows) do
			if i <= Count.RANK_ROWS or row.key == k then lines[#lines + 1] = RowText(what, window, row) end
		end
		who = "-"
	else
		if what == "me" then who = Short(sender) end
		local name = WireName(who)
		if not name or not Count.MaySeeDetail(sender, name) then return Drop("detail") end
		for _, d in ipairs(Count.DetailLines(Key(name), window)) do
			lines[#lines + 1] = ("NR~1~m~%s~%s~%s~%s~%s~%s~%s~%s"):format(what, window, Short(name), d[1], tostring(d[2]), tostring(Ten(d[3]) / 10),
				tostring(d[4]), tostring(Ten(d[5]) / 10))
		end
		who = Short(name)
	end
	lines[#lines + 1] = ("NR~1~e~%s~%s~%s~%d~%s"):format(what, window, who, #lines, B36(Clock()))
	return SendLines(ns.FullName(sender), lines, nil, guard)
end

-- Asks the desk (or another keeper online) for a page's numbers; a keeper computes them itself. A
-- High Council or King relay asks too: computed from its own copy, its pages showed a ledger far
-- behind the keepers' (a 1.2.5.1 keeper answers its page, not its catch-up). And an audience page
-- that asked the first relay online asked the author before the Apostles.
function Count.Ask(what, window, person, force)
	if not WHATS[what] or not WINDOWS[window] then return false end
	if what == "u" and not Count.CanSeeRecruiters(ns.me) then return false, "audience" end
	-- (1.5.8: the recruiters list is asked of another keeper too, even by one: the author's own ledger
	-- held two recruiters while the Apostles' held more. Count.RankingView shows the larger.)
	if Church.IsKeeper(ns.me) and not Church.IsKing(ns.me) and what ~= "u" then return false, "local" end
	if not Church.InAudience(ns.me) or Off() then return false, "audience" end
	local pk = what == "me" and Key(ns.me) or (person and Key(person)) or "-"
	local key = what .. ":" .. window .. ":" .. tostring(pk)
	local t, previous = ns.Now(), asks[key]
	if previous then
		local elapsed = t - (previous.sent or previous.t)
		if previous.complete then
			local gap = (what == "a" or what == "m" or what == "u") and Count.RANK_REFRESH or Count.ASK_GAP
			if not force and elapsed < gap then return false, "gap" end
		elseif elapsed < Count.ASK_GAP or (previous.rows and t < previous.expires
			and (not previous.sent or t - (previous.progress or previous.sent) < Count.ASK_GAP)) then
			return false, "gap"
		end
	end
	local keepers = Church.KeepersOnline(false)
	if #keepers == 0 then Church.FindKeeper(); return false, "no keeper" end
	-- Prefer the next keeper when an answer stalls. NR~1 carries no request identifier, so
	-- do not ask one for this page again until its previous answer ends or expires.
	local first = 1
	if previous and not previous.complete then
		for i, k in ipairs(keepers) do
			if Key(k.name) == previous.k then first = i % #keepers + 1; break end
		end
	end
	local open = previous and previous.open or {}
	for k, expires in pairs(open) do if t >= expires then open[k] = nil end end
	local keeper, keeperKey
	for i = 0, #keepers - 1 do
		local candidate = keepers[(first + i - 1) % #keepers + 1]
		local ck = Key(candidate.name)
		if not open[ck] then keeper, keeperKey = candidate, ck; break end
	end
	if not keeper then return false, "gap" end
	local a = { k = keeperKey, t = t, expires = t + Church.ASKED_WINDOW, rows = {}, seen = {}, open = open }
	local sent = ns.Comm.Whisper(keeper.name, ("NR~1~q~%s~%s~%s"):format(what, window, person and Short(person) or "-"),
		nil, false, false, function(ok)
			if not ok then a.rows, a.seen = nil, nil; return end
			a.sent = ns.Now()
			a.expires = a.sent + Church.ASKED_WINDOW
			open[keeperKey] = a.expires
		end, { owner = Count, guard = function()
			return asks[key] == a and ns.Now() < a.expires and (what ~= "u" or Count.CanSeeRecruiters(ns.me))
		end })
	if not sent then return false, "queue" end
	if not previous then Church.Capped(asks, Count.PEOPLE_MAX) end
	asks[key] = a
	return true
end

-- Accept only the active request from the keeper this client asked for that page.
local function Asked(sender, key)
	local a = asks[key]
	if a and a.rows and a.sent and a.k == Key(sender) and ns.Now() < a.expires then return a end
end

local function StageAnswer(a, key, row, limit)
	if a.seen[key] then return false, "duplicate" end
	if #a.rows >= limit then a.overflow = true; return Drop("shape") end
	a.seen[key] = true
	a.progress = ns.Now()
	a.rows[#a.rows + 1] = row
	return true
end

function Count.TakeAnswerLine(sender, text)
	if not Church.IsKeeper(sender) then return Drop("keeper") end
	if not Church.InAudience(ns.me) or Off() then return Drop("audience") end
	local kind = text:match("^NR~1~(%a)~")
	if kind == "r" then
		local list, window, rank, name, score, own, share, joins, stays, net, pub =
			text:match("^NR~1~r~([amcu])~([wma])~(%d+)~([^~]+)~(%d+)~(%d+)~(%d+)~(%d+)~(%d+)~(%d+)~([01])$")
		rank = tonumber(rank)
		if not list or not WireName(name) or not rank or rank < 1 then return Drop("shape") end
		if list == "u" and not Count.CanSeeRecruiters(ns.me) then return Drop("audience") end
		local a = Asked(sender, list .. ":" .. window .. ":-")
		if not a then return Drop("unasked") end
		return StageAnswer(a, rank, { rank = rank, name = Short(WireName(name)), key = Key(name), score = tonumber(score) / 10,
			own = tonumber(own) / 10, share = tonumber(share) / 10, joins = tonumber(joins), stays = tonumber(stays),
			net = tonumber(net), pub = pub == "1" }, Count.RANK_ROWS + 1)
	elseif kind == "m" then
		local what, window, person, line, a, b, c, d = text:match("^NR~1~m~(%a+)~([wma])~([^~]+)~(%a)~([^~]*)~([^~]*)~([^~]*)~([^~]*)$")
		if not what or not WireName(person) then return Drop("shape") end
		local request = Asked(sender, what .. ":" .. window .. ":" .. Key(person))
		if not request then return Drop("unasked") end
		local function Num(v) return tonumber(v) or v end
		return StageAnswer(request, text, { line, Num(a), Num(b), Num(c), Num(d) }, 40)
	elseif kind == "e" then
		local what, window, person, n, asOf = text:match("^NR~1~e~(%a+)~([wma])~([^~]+)~(%d+)~([0-9a-z]+)$")
		if not what then return Drop("shape") end
		if what == "u" and not Count.CanSeeRecruiters(ns.me) then return Drop("audience") end
		local pk = person == "-" and "-" or Key(person)
		local key = what .. ":" .. window .. ":" .. tostring(pk)
		local a = Asked(sender, key)
		if not a then return Drop("unasked") end
		local rows = a.rows
		a.open[a.k] = nil
		a.rows, a.seen = nil, nil
		if a.overflow or #rows ~= tonumber(n) then return Drop("incomplete page") end
		local view = View()
		asOf = UnB36(asOf)
		if not asOf or asOf <= 0 or asOf > Clock() + Church.DATE_AHEAD then return Drop("page time") end
		if view[key] and asOf < (tonumber(view[key].asOf) or 0) then return Drop("older page") end
		if what == "a" or what == "m" or what == "c" or what == "u" then
			table.sort(rows, function(left, right) return left.rank < right.rank end)
		end
		a.complete = true
		view[key] = { rows = rows, asOf = asOf, from = Church.Key(sender) and ns.ShortName(sender) }
		ViewChanged()
		return true
	end
	return Drop("kind")
end

-- What the tab shows: a keeper's own numbers, else the last answer kept. rows (ranking) or lines
-- (detail), the time they are as of, whether they came from another client, and (a keeper's own)
-- whether its first catch-up still goes on (Count.Settled): just logged in, they showed as live the
-- ledger it had before, the recruits that came while it was away missing. A council relay shows its
-- own copy only with no answer kept and no keeper online to ask; the King's client, which keeps none
-- (Count.TakeLine), never.
local function OwnCopy() return Church.IsLedgerRelay(ns.me) and not Church.IsKing(ns.me) and #Church.KeepersOnline(false) == 0 end
local function RecruitsIn(rows)
	local n = 0
	for _, row in ipairs(rows or {}) do n = n + (tonumber(row.joins) or 0) end
	return n
end
function Count.RankingView(list, window)
	if list == "u" and not Count.CanSeeRecruiters(ns.me) then return {}, nil, false end
	if list == "c" then return ns.ChurchFullness.Ranking(), Clock(), false end
	local key = list .. ":" .. window .. ":-"
	if Church.IsKeeper(ns.me) and not Church.IsKing(ns.me) then
		local rows = Count.Ranking(list, window)
		-- (1.5.8) The recruiters list: another keeper's answer while it counts more recruits than this
		-- ledger does (one whose catch-up never finished held a few); this ledger's own otherwise.
		local v, a = list == "u" and (View() or {})[key], asks[key]
		if v and RecruitsIn(v.rows) > RecruitsIn(rows) then
			return v.rows, v.asOf, true, a and not a.complete and ns.Now() < a.expires, v.from
		end
		return rows, Clock(), false, not Count.Settled()
	end
	local v, a = View()[key], asks[key]
	if not v and OwnCopy() then return Count.Ranking(list, window), Clock(), false end
	return v and v.rows or {}, v and v.asOf, true, a and not a.complete and ns.Now() < a.expires, v and v.from
end
function Count.DetailView(person, window)
	local k = Key(person)
	if Church.IsKeeper(ns.me) and not Church.IsKing(ns.me) then
		local lines = Count.DetailLines(k, window)
		return lines, Clock(), false, not Count.Settled()
	end
	local what = k == Key(ns.me) and "me" or "p"
	local v = View()[what .. ":" .. window .. ":" .. tostring(k)]
	if not v and OwnCopy() then return Count.DetailLines(k, window), Clock(), false end
	return v and v.rows or {}, v and v.asOf, true, nil, v and v.from
end

---------------------------------------------------------------------------
-- The player's own: registrations, his public row
---------------------------------------------------------------------------

function Count.Register(input)
	if not Church.IsPerson(ns.me) then return ns.Print(L.CHURCH_NO_RIGHTS) end
	local name = Church.InputName(input)
	if not name then return ns.Print(L.CHURCH_WHO) end
	if Key(name) == Key(ns.me) then return ns.Print(L.CHURCH_NO_SELF) end
	local m = Mine()
	local now = Clock()
	local open = 0
	for k, r in pairs(m.regs) do
		if now - (r.at or 0) > Count.REG_DAYS * DAY then m.regs[k] = nil else open = open + 1 end
	end
	if m.regs[Key(name)] then return ns.Print(L.CHURCH_REG_HELD:format(ns.DisplayName(name))) end
	if open >= Count.REG_OPEN then return ns.Print(L.CHURCH_REG_FULL:format(Count.REG_OPEN)) end
	m.regs[Key(name)] = { n = Short(name), at = now }
	Count.SendEvidence(("NV~1~g~%s~%s"):format(name, B36(now)))
	ns.Print(L.CHURCH_REGISTERED:format(ns.DisplayName(name), Count.REG_DAYS))
	Changed()
	return true
end

function Count.Withdraw(input)
	local name = WireName(input)
	local m = Mine()
	if not name or not m.regs[Key(name)] then return ns.Print(L.CHURCH_WHO) end
	m.regs[Key(name)] = nil
	Count.SendEvidence(("NV~1~x~%s~%s"):format(name, B36(Clock())))
	Changed()
	return true
end

function Count.PublicRow() local m = Mine() return m and m.pub == true or false end
function Count.SetPublicRow(on)
	if not Church.IsPerson(ns.me) then return ns.Print(L.CHURCH_NO_RIGHTS) end
	local m = Mine()
	m.pub, m.pubAt = on == true, Clock()
	Count.SendEvidence(("NV~1~o~%s~%s"):format(on and "1" or "0", B36(m.pubAt)))
	ns.Print(on and L.CHURCH_ROW_SHOWN or L.CHURCH_ROW_HIDDEN)
	Changed()
	return true
end

-- This player's invites (his own log reads, never sent) and, for a correspondent, his guild's
-- joins and leaves (his own log reads) and members (his roster): this week and in all.
function Count.Local()
	local m = Mine()
	local now = Clock()
	local week = Day(WindowFrom("w", now))
	local out = { invWeek = 0, invAll = 0, joins = 0, leaves = 0, members = nil }
	for day, n in pairs(m.inv) do
		out.invAll = out.invAll + n
		if day >= week then out.invWeek = out.invWeek + n end
	end
	local guild = OwnGuild()
	local fills = Fills()
	for day, f in pairs(guild and fills[ns.Fold(guild)] or {}) do
		if type(day) == "number" and day >= week and type(f) == "table" then out.joins, out.leaves = out.joins + (f.j or 0), out.leaves + (f.l or 0) end
	end
	local R = ns.Roster
	if R and R.guild == guild and type(R.members) == "table" then out.members = #R.members end
	return out
end

---------------------------------------------------------------------------
-- The public view and the top 3
---------------------------------------------------------------------------

-- Just logged in, a keeper holds the switch it saved: it waits until every keeper online has been
-- heard (their presence carries a close it missed: Church.TakePresence) before it speaks for it.
local function SettledSinceLogin()
	local online = Church.OnlineFor and Church.OnlineFor()
	return online == nil or online >= Church.KEEPER_EVERY * Church.FRESH_FACTOR
end
Count.SettledSinceLogin = SettledSinceLogin

-- The desk while the author's switch is open: the opted-in rows of the two rankings (last 30 days
-- and all time), PUBLIC_EVERY apart and as soon as it opens; each list ends with its count of rows
-- (NR n), so a client drops the rows of people who no longer show theirs, an empty list too. Just
-- logged in, only once its first catch-up ended (Count.Settled, as for the pages): the rows it sent
-- from the ledger it had before were every client's for PUBLIC_EVERY.
function Count.SendPublic(now)
	local open, at = Church.Public()
	if not open or not Church.IsDesk() or Church.IsKing(ns.me) or Off() or not SettledSinceLogin() or not Count.Settled() then return false end
	local t = ns.Now()
	if lastPublicAt == at and t - lastPublic < Count.PUBLIC_EVERY then return false end
	-- (1.5.4) Both rankings' rows as one list (Comm.SendList): the same rows in the same order, and
	-- where the relay carries the channel one word to every reporter whole, where one by one they
	-- reached a reporter one to four of twenty-two (Comm.lua); where the channel works each row goes
	-- as before. One list, not one a ranking: the relay admits one list of a kind from an origin each
	-- Relay.LIST_EVERY, and the second of a pair sent together took the first's place or was refused.
	local rows = {}
	for _, list in ipairs({ "a", "m" }) do
		local all = {}
		for _, row in ipairs(Count.Ranking(list, "a")) do all[row.key] = row.score end
		local n = 0
		for _, row in ipairs(Count.Ranking(list, "m")) do
			if row.pub and n < Count.PUBLIC_ROWS then
				n = n + 1
				rows[#rows + 1] = ("NR~1~p~%s~%s~%d~%s~%d~%d"):format(B36(at), list, n, row.name, Ten(row.score), Ten(all[row.key] or 0))
			end
		end
		rows[#rows + 1] = ("NR~1~n~%s~%s~%d"):format(B36(at), list, n)
	end
	-- (Its rows go together: only with room for all of them, the list's pieces or its rows one by
	-- one, past what the chat and the census keep.)
	if ns.Comm.QueueRoom() < Count.SEND_ROOM + ns.Comm.ListRoom("NR", rows) then return false end
	if not ns.Comm.SendList("NR", rows) then return false end
	lastPublic, lastPublicAt = t, at
	return true
end

function Count.TakePublicRow(sender, text)
	local at, list, rank, name, s30, sall = tostring(text or ""):match("^NR~1~p~([0-9a-z]+)~([am])~(%d+)~([^~]+)~(%d+)~(%d+)$")
	at, rank = UnB36(at), tonumber(rank)
	if not at or not WireName(name) or not rank or rank < 1 or rank > Count.PUBLIC_ROWS then return Drop("shape") end
	if not Church.IsKeeper(sender) then return Drop("keeper") end
	local open, held = Church.Public()
	if not open or at ~= held then return Drop("closed") end
	local c = Church.Store()
	local v = c.pubView
	if type(v) ~= "table" or v.at ~= at then v = { at = at, a = {}, m = {} }; c.pubView = v end
	if rank == 1 then v[list] = {} end
	v[list][rank] = { name = Short(WireName(name)), s30 = tonumber(s30) / 10, sall = tonumber(sall) / 10 }
	v.t = ns.Now()
	ViewChanged()
	return true
end

-- The end of one list's rows in a round: how many it had. Rows past it go (all of them for 0).
function Count.TakePublicCount(sender, text)
	local at, list, n = tostring(text or ""):match("^NR~1~n~([0-9a-z]+)~([am])~(%d+)$")
	at, n = UnB36(at), tonumber(n)
	if not at or not n or n > Count.PUBLIC_ROWS then return Drop("shape") end
	if not Church.IsKeeper(sender) then return Drop("keeper") end
	local open, held = Church.Public()
	if not open or at ~= held then return Drop("closed") end
	local c = Church.Store()
	local v = c.pubView
	if type(v) ~= "table" or v.at ~= at then v = { at = at, a = {}, m = {} }; c.pubView = v end
	if n == 0 then v[list] = {} else for rank in pairs(v[list]) do if type(rank) ~= "number" or rank > n then v[list][rank] = nil end end end
	v.t = ns.Now()
	ViewChanged()
	return true
end

-- The public rows held, while the switch is open and they are fresh: { a = rows, m = rows } or nil.
function Count.PublicView()
	local open, at = Church.Public()
	local c = Church.Store()
	local v = c and c.pubView
	if not open or type(v) ~= "table" or v.at ~= at or ns.Now() - (v.t or 0) > Count.PUBLIC_FRESH then return nil end
	return v
end

-- The author's client (a keeper): the top 3, while the switch is open, at once when it changes and
-- TOP_EVERY apart otherwise (D8). A closed switch ends it on every client (Count.Top3). (1.2.3: the
-- author's alone in fact. SendTop takes a root of H or W, but the Head is the King (Church.IsHead),
-- whose root is K, and the King's client is no keeper (Count.Tick leaves him out): TakeTop still takes
-- the King's word. So the top 3, and the missionaries' crooks, move only while the author's client
-- is online with the ranking open; 30 days after its last word no client shows a crook. 1.3.4: the
-- King's and the High Council's clients say its last word again, Count.RelayTop, so it reaches the
-- clients that never were online with the author's; still worked out by his alone.)
-- (1.2.3: worked out again only when what it is made of may have changed: the ledger, the book, the
-- hour (the last 30 days move on), the top 3 held; and when TOP_EVERY sends it anyway. It was every tick,
-- every person's numbers, only to find it the same.)
local topFrom = {}
function Count.SendTop(now)
	local root = Church.RootCode(ns.me)
	if (root ~= "H" and root ~= "W") or not Church.IsKeeper(ns.me) or Off() or not SettledSinceLogin() then return false end
	if not Church.Public() then return false end
	local t = ns.Now()
	local S, held, hour = Church.State(), Count.Top3(), math.floor(Clock() / 3600)
	local f = topFrom
	if f.led == ledRev and f.rev == S.rev and f.listAt == S.listAt and f.blob == S.blob and f.hour == hour and f.held == held
		and t - lastTop < Count.TOP_EVERY then return false end
	topFrom = { led = ledRev, rev = S.rev, listAt = S.listAt, blob = S.blob, hour = hour, held = held }
	local top = Count.ComputeTop3()
	local same = held and table.concat(held.apostles, ",") == table.concat(top.a, ",") and table.concat(held.missionaries, ",") == table.concat(top.m, ",")
	if same and t - lastTop < Count.TOP_EVERY then return false end
	lastTop = t
	local at = Clock()
	local text = ("NR~1~t~%s~%s~%s"):format(B36(at), #top.a > 0 and table.concat(top.a, ",") or "-", #top.m > 0 and table.concat(top.m, ",") or "-")
	Count.TakeTop(ns.me, text)
	topFrom.held = Count.Top3()
	ns.Comm.Send("CHANNEL", text, "church-top", false, false)
	if OwnGuild() then ns.Comm.Send("GUILD", text, "church-top-guild", false, false) end
	return true
end

-- (1.3.4, the owner's ask before the launch: every ranking shows on every client.) Who says the top 3
-- again, as it is: the King's character and the signed High Council, never the author (his client
-- works it out, SendTop: it relays nobody's word) nor an Apostle who is not of the Council (Apostles
-- rank Apostles: the cross). A client that never was online with the author's took no top 3 before,
-- and showed nobody's cross or crook.
function Count.IsTopRelay(name)
	if type(name) ~= "string" or name == "" or Church.IsAuthor(name) then return false end
	return Church.IsKing(name) or ns.IsHighCouncillor(ns.FullName(name)) == true
end

function Count.TakeTop(sender, text)
	local at, a, m = tostring(text or ""):match("^NR~1~t~([0-9a-z]+)~([^~]+)~([^~]+)$")
	at = UnB36(at)
	if not at then return Drop("shape") end
	local root = Church.RootCode(sender)
	if root ~= "H" and root ~= "K" and root ~= "W" and not Count.IsTopRelay(sender) then return Drop("root") end
	if at > Clock() + Church.DATE_AHEAD then return Drop("ahead") end
	local function Names(s)
		local out = {}
		if s == "-" then return out end
		for n in s:gmatch("[^,]+") do
			local name = WireName(n)
			if not name then return nil end
			if #out < 3 then out[#out + 1] = Short(name) end
		end
		return out
	end
	local apostles, missionaries = Names(a), Names(m)
	if not apostles or not missionaries then return Drop("shape") end
	local c = Church.Store()
	local held = c.top
	local heldAt = type(held) == "table" and (tonumber(held.at) or 0) or nil
	-- (1.3.4) The same word or a newer one heard from another client: our relay waits again (RelayTop).
	if Key(sender) ~= Key(ns.me) and (not heldAt or at >= heldAt) then topHeard, topRelayAt = ns.Now(), nil end
	if heldAt and heldAt >= at then return false, "older" end
	-- (1.3.4: the word itself kept too, for a relay to say it again as it came, its own time with it.)
	c.top = { at = at, by = Church.Key(sender) and ns.ShortName(ns.FullName(sender)), apostles = apostles, missionaries = missionaries,
		text = text }
	ns.Fire("CHURCH_TOP_CHANGED")
	return true
end

-- (1.3.4) A relay's client (Count.IsTopRelay): the newest top 3 it holds, as it came (its time, its
-- names), on CHANNEL and GUILD, while the public ranking is open and the word is no older than
-- TOP_MAX_AGE: TOP_EVERY + TOP_GRACE after the last word it heard (the same or a newer one) or said,
-- TOP_JITTER at random more, the King's TOP_KING_AFTER later still. A word heard meanwhile starts its
-- wait again: no relay speaks while the author's client says it, and the relays online say it about once
-- a TOP_EVERY between them (the first of them; the others heard it), the King's only when none of the
-- Council's did. A relay never makes a word newer: its time is the one it came with, and every client
-- keeps the newest (TakeTop).
function Count.RelayTop(now)
	if not Count.IsTopRelay(ns.me) or Off() then return false end
	local t = ns.Now()
	local function Wait() return (Church.IsKing(ns.me) and Count.TOP_KING_AFTER or 0) + Count.random(0, Count.TOP_JITTER) end
	if not topRelayAt then
		topRelayAt = topHeard and (topHeard + Count.TOP_EVERY + Count.TOP_GRACE + Wait()) or (t + Count.TOP_FIRST + Wait())
	end
	if t < topRelayAt then return false end
	topRelayAt = t + Count.TOP_EVERY + Count.TOP_GRACE + Wait()
	local top = Count.Top3()
	local at = top and tonumber(top.at)
	if not at or Clock() - at > Count.TOP_MAX_AGE then return false, "none" end
	local text = type(top.text) == "string" and top.text or nil
	local ta = text and UnB36(text:match("^NR~1~t~([0-9a-z]+)~[^~]+~[^~]+$"))
	if ta ~= at then
		-- (A top 3 kept before 1.3.4 has no word: the same time and names.)
		text = ("NR~1~t~%s~%s~%s"):format(B36(at), #top.apostles > 0 and table.concat(top.apostles, ",") or "-",
			#top.missionaries > 0 and table.concat(top.missionaries, ",") or "-")
	end
	ns.Comm.Send("CHANNEL", text, "church-top", false, false)
	if OwnGuild() then ns.Comm.Send("GUILD", text, "church-top-guild", false, false) end
	return true
end

-- The newest top 3 a trusted client published: { at, by, apostles = { names }, missionaries =
-- { names } }, or nil. (1.2.3: HonorsNet reads the missionaries', their crook; the Apostles' cross
-- still waits.)
function Count.Top3()
	local c = Church.Store()
	local t = c and c.top
	if type(t) ~= "table" or type(t.apostles) ~= "table" or type(t.missionaries) ~= "table" then return nil end
	if not Church.Public() then return nil end
	return t
end
Church.Top3 = function() return Count.Top3() end

---------------------------------------------------------------------------
-- Receiving, and upkeep
---------------------------------------------------------------------------

function Count.Receive(kind, dist, sender, text)
	if type(text) ~= "string" or type(sender) ~= "string" then return end
	local version = text:match("^%u%u~([^~]+)~")
	if version ~= "1" and not (kind == "NL" and version == "2") then return Drop("version") end
	sender = ns.FullName(sender)
	if kind == "NV" then
		if dist ~= "WHISPER" then return Drop("lane") end
		if text:match("^NV~1~k~") then return Count.TakeReceipt(sender, text) end
		if text:match("^NV~1~l~") then return Count.TakeLater(sender, text) end
		local ok, why = Count.TakeEvidence(sender, text)
		Count.Receipt(sender, text, ok, why)
		return ok, why
	elseif kind == "NS" then
		local k = text:match("^NS~1~(%a)~")
		if k == "q" then
			if dist ~= "CHANNEL" then return Drop("lane") end
			return Count.TakeCheck(sender, text)
		elseif k == "a" then
			if dist ~= "WHISPER" then return Drop("lane") end
			return Count.TakeAnswer(sender, text)
		end
		return Drop("kind")
	elseif kind == "NL" then
		if dist ~= "WHISPER" then return Drop("lane") end
		return Count.TakeLine(sender, text)
	elseif kind == "NR" then
		local k = text:match("^NR~1~(%a)~")
		if k == "q" then
			if dist ~= "WHISPER" then return Drop("lane") end
			local what, window, person = text:match("^NR~1~q~(%a+)~([wma])~([^~]+)$")
			if not what or not WHATS[what] then return Drop("shape") end
			return Count.Answer(sender, what, window, person ~= "-" and person or nil)
		elseif k == "r" or k == "m" or k == "e" then
			if dist ~= "WHISPER" then return Drop("lane") end
			return Count.TakeAnswerLine(sender, text)
		elseif k == "p" then
			if dist ~= "CHANNEL" then return Drop("lane") end
			return Count.TakePublicRow(sender, text)
		elseif k == "n" then
			if dist ~= "CHANNEL" then return Drop("lane") end
			return Count.TakePublicCount(sender, text)
		elseif k == "t" then
			if dist ~= "CHANNEL" and dist ~= "GUILD" then return Drop("lane") end
			return Count.TakeTop(sender, text)
		end
		return Drop("kind")
	end
end

ns.Comm.Handle("NV", function(dist, sender, text) Count.Receive("NV", dist, sender, text) end)
ns.Comm.Handle("NS", function(dist, sender, text) Count.Receive("NS", dist, sender, text) end)
ns.Comm.Handle("NL", function(dist, sender, text) Count.Receive("NL", dist, sender, text) end)
ns.Comm.Handle("NR", function(dist, sender, text) Count.Receive("NR", dist, sender, text) end)

-- Records past RECORDS_DAYS fold into their recruiter's archive; registrations past REG_DAYS stay
-- (shown as expired) until then. (1.2.3: the ledger counts as changed only when something went, and
-- the marks of what it let go are listed only when they are over GONE_MAX.)
local WINDOW_HOURS = { "wj", "wy" }
function Count.Prune()
	local l = Led()
	local now = Clock()
	local C, changed = nil, false
	for id, r in pairs(l.r) do
		if TooOld(r, now) then
			C = C or Count.Credits() -- (before the first record goes: the claims as they were)
			if C.states[id] == "credited" then Archive(r, now, id) end
			l.r[id] = nil
			changed = true
		end
	end
	-- (1.2.1: archived records no window counts any more go; their person's all-time totals are first
	-- made at least the archive's, so all time stays as it was.)
	local keep = now - WindowKeep() - 3600
	for by, set in pairs(Arc()) do
		if type(set) ~= "table" then l.arc[by], changed = nil, true else
			local aj, ay, old = 0, 0, false
			for xk, a in pairs(set) do
				if type(a) ~= "table" or type(a.h) ~= "number" then set[xk], changed = nil, true else
					aj, ay = aj + 1, ay + (a.y == 1 and 1 or 0)
					if a.h < keep then old = true end
				end
			end
			if old then
				local p = type(l.p[by]) == "table" and l.p[by] or { n = by }
				l.p[by] = p
				local ap = aj * Count.POINTS_JOIN + ay * Count.POINTS_STAY
				if (p.ap or 0) < ap or (p.aj or 0) < aj or (p.ay or 0) < ay then
					p.ap, p.aj, p.ay, p.u = math.max(p.ap or 0, ap), math.max(p.aj or 0, aj), math.max(p.ay or 0, ay), Clock()
				end
				for xk, a in pairs(set) do if a.h < keep then set[xk] = nil end end
				changed = true
			end
			if next(set) == nil then l.arc[by], changed = nil, true end
		end
	end
	-- (What it let go, Gone: RECORDS_DAYS, then GONE_MAX at most, the oldest first.)
	local g, n = Gone(), 0
	for k, t in pairs(g) do
		if type(t) ~= "number" or now - t > Count.RECORDS_DAYS * DAY then g[k], changed = nil, true else n = n + 1 end
	end
	if n > Count.GONE_MAX then
		local marks = {}
		for k, t in pairs(g) do marks[#marks + 1] = { k = k, t = t } end
		table.sort(marks, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.k < b.k end)
		for i = 1, #marks - Count.GONE_MAX do g[marks[i].k] = nil end
		changed = true
	end
	for _, p in pairs(l.p) do
		for _, f in ipairs(WINDOW_HOURS) do
			local t = type(p) == "table" and p[f]
			if type(t) == "table" then
				for hour in pairs(t) do if type(hour) ~= "number" or hour < keep then t[hour], changed = nil, true end end
				if next(t) == nil then p[f], changed = nil, true end
			end
		end
	end
	if changed then Changed() end
	return changed
end

function Count.CheckSaved()
	local c = Church.Store()
	if not c then return end
	for which in pairs(LEDGERS) do
		local l = c[which]
		if l ~= nil then
			local ok = type(l) == "table" and l.v == 1 and type(l.r) == "table" and type(l.p) == "table" and type(l.from) == "table"
			if ok then
				-- (1.2.1: a record that fails goes alone. One record of a guild this build no longer counts as
				-- Olympus took the whole ledger with it, and the catch-up then refilled it from another keeper's,
				-- maybe smaller, one.)
				local bad = {}
				for id, r in pairs(l.r) do
					local okLine, line = pcall(Count.RecordLine, id, r)
					local pid, rec = ParseRecord(okLine and line or "")
					if pid ~= id or not rec then bad[#bad + 1] = id end
				end
				for _, id in ipairs(bad) do l.r[id] = nil end
				if #bad > 0 then ns.Log("church ledger (%s): %d saved records dropped at load", which, #bad) end
				WindowsFromGone(l, Clock())
				if l.caught ~= nil and type(l.caught) ~= "table" then l.caught = nil end
				if l.asked ~= nil and type(l.asked) ~= "table" then l.asked = nil end
			end
			if not ok then c[which] = nil end
		end
	end
	for _, key in ipairs({ "mem", "ev", "inv", "att", "claims", "fill", "view", "me" }) do
		if c[key] ~= nil and type(c[key]) ~= "table" then c[key] = nil end
	end
	c.rcpt = nil -- (an earlier 1.2.1 build's keepers heard with receipts: the outbox counts each keeper's sends now)
	if type(c.out) == "table" and #c.out > Count.OUTBOX_MAX then c.out = nil end
	Changed()
end

local nextPruneCount, settledShown
function Count.Tick(now)
	now = now or ns.Now()
	Count.Remember(false)
	Count.MaybeRead(now)
	if #(Out() or {}) > 0 then Count.Flush() end
	if Church.IsLedgerRelay(ns.me) then Count.CatchUp(false) end
	if Church.IsKeeper(ns.me) and not Church.IsKing(ns.me) then
		-- (Settled at SETTLE_MAX, or with no keeper online: its tab no longer says it is catching up.)
		local settled = Count.Settled()
		if settledShown == false and settled then ViewChanged() end
		settledShown = settled
		Count.DeskTick(Clock())
		Count.RetryLater()
		Count.SendPublic(now)
		Count.SendTop(now)
		nextPruneCount = nextPruneCount or now + Count.random(Count.PRUNE_AFTER, Count.PRUNE_AFTER + Count.PRUNE_SPREAD)
		if now >= nextPruneCount then nextPruneCount = now + 3600; Count.Prune() end
	end
	-- (1.3.4) The King's and the High Council's: the top 3 said again (a keeper of the Council's too).
	Count.RelayTop(now)
	if ns.ChurchView and ns.ChurchView.PollRanking then ns.ChurchView.PollRanking() end
end

function Count.Stats() return stats end

function Count.StatusLines()
	local l = Led()
	local n, p = 0, 0
	for _ in pairs(l.r) do n = n + 1 end
	for _ in pairs(l.p) do p = p + 1 end
	local archived, marks = 0, 0
	for _, set in pairs(Arc()) do for _ in pairs(type(set) == "table" and set or {}) do archived = archived + 1 end end
	for _ in pairs(Gone()) do marks = marks + 1 end
	local mem = Mem()
	local open = 0
	for _ in pairs(checks) do open = open + 1 end
	local dropped = {}
	for why, k in pairs(stats.dropped) do dropped[#dropped + 1] = why .. "=" .. k end
	table.sort(dropped)
	local lines = {
		("log reads %d, events %d, pairs %d, evidence sent %d, outbox %d, receipts %d, refused for now %d, memory %d names"):format(stats.reads,
			stats.events, stats.pairs, stats.sent, #(Out() or {}), stats.receipts or 0, stats.later or 0, mem and mem.count or 0),
		("ledger %d records, %d people, %d archived, %d let go; checks sent %d, open %d, answers %d"):format(n, p, archived, marks,
			stats.checks, open, stats.answers),
		"count dropped: " .. (#dropped > 0 and table.concat(dropped, ", ") or "-"),
	}
	if catch.replay then lines[#lines + 1] = ("recent ledger check: %s (%d complete pages)"):format(catch.replay.result, catch.replay.pages) end
	return lines
end

ns.On("INIT", function() Count.CheckSaved() end)
ns.On("DATA_CHANGED", function() Count.Remember(false) end)
