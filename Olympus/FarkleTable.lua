local ADDON, ns = ...
local L = ns.L

-- 1.2, the Blood Arena: FarkleTable.lua, the table of Bones (the rules' "Farkle": the code
-- keeps its Farkle names and K... types, the screens say "Bones").
--
-- What it owns (the design: the Bones tables, as amended):
--   - the protocol (K...), every table message whispered to each other participant (the players
--     and the arbiter; the design), KS and KN on the channel for a public table;
--   - the witnessing: every die is the server's /roll, which each client at the table reads in its
--     own CHAT_MSG_SYSTEM (ArenaParse.Roll) and hands to FarkleRules.Apply; nothing a client says
--     about a roll is believed, and scores are never sent;
--   - the clocks (the turn timer, HIC!'s own, the combat pause of the design, the tavern pause of
--     the design), the handshake, resync (KQ, KR) and the divergence rule of the design;
--   - the stake glue (the design: direct o/o, arbiter t/t or w/w, the King w/w), against the
--     documented interfaces of Stakes, Wallet, Markets, Debts and ArenaMoney;
--   - the tavern rule (the design; 1.1.6: a tavern or a camp, for every game that counts, staked or
--     not): played in one party, within about 10 yd, both at one inn (IsResting and Places.InnAt by
--     position), at a Forever campfire each player can read locally, or by a Board camp one of
--     the two dropped in their zone; checked throughout: someone walks off, the game pauses; gone
--     past TAVERN_GRACE, he forfeits. Practice against the House and rehearsals play anywhere;
--   - spectators (the design): a player who allows them announces the table (KN) and relays its state
--     (KS) to the watchers; watching never feeds settlement. Allowed unless a player says no (the
--     owner's call, 2026-10-04); the host's no closes the table to watchers for everyone at it
--     (KG's trailing flag), his guest and its arbiter too. Each player's yes or no is kept in the
--     live record, so a /reload keeps announcing the table (1.2.3). A game against the House is
--     never announced (nothing of practice is sent: the House's dice are this client's own);
--   - what counts (1.2.3, the owner's decision 1): a free game between players (no gold, the only
--     kind 1.2.x allows) counts for the history and the ranking whatever the King's live switch,
--     which stays off and is the 2.0 bets' alone; a test build's never (FreeCounts). Both players'
--     clients must count it (each says so: "c" on KI and KA): against a test build or a 1.2.2
--     client, it is a rehearsal on both sides. Its records are the live realm's (L), its messages
--     keep the mode the table was made in;
--   - the Bones ranking (1.2.3, Best: the month's best players, the honours' source): each player's
--     client signs its half of a game that counts with his account's key and publishes it as the
--     game ends (KN "e" with the result, on the channel and to the other player); each player says
--     both halves again at later logins, spaced; a client counts the game only when both players'
--     halves agree, within the ledger's caps and never between one owner's characters (the
--     halves' rules: TakeHalf, below);
--   - the crowd's bets (2026-10-04): at a public arbiter's table whose host let watchers in and
--     the crowd bet, the arbiter opens a winner market (Markets' MW) when the table opens; the game
--     waits for its lock (his KH), then he declares it as he settles (the same agreement and
--     grace), or voids it when the table never plays out. Never at a table whose stakes are in the
--     wallet (its own FK market); the stakes stay out of the crowd's sheet;
--   - the hiccup (the design): the drunk lines of the game read on CHAT_MSG_SYSTEM (DRUNK_MESSAGE_*), the
--     levels the opponent's client witnessed (KK's level field), the gap rule, the arbiter's floor
--     (KL), the dispute flag of direct mode (KE's ld), HIC! with its own clock;
--   - practice against the House (/oly farkle practice), with the rules' hints on the board when
--     the player asks to learn (opts.learn, 1.1.6), the self-test (/oly farkle test), the tester
--     log (/oly farkle log);
--   - the games' ledger (1.1.6, the owner's ask 2026-10-05): every game that ended, between players
--     (staked or not) or against the House, goes to ArenaLedger.Played (its AY: the auditors, the
--     King's character, a High Councillor, a signed arbiter with "+a", the author's own character's
--     entry among them, get every game; each player keeps his own), and Bones's own history
--     keeps the table's details (History, MyGames).
-- The screens are the companion's (Olympus_Arena/FarkleBoard.lua): this file fires FARKLE_TABLE
-- (id, state) and FARKLE_EVENT (id, info) and answers View(id).
--
-- The weight rule (the design): until a table involves this client, it holds only its Comm.Handle
-- entries. CHAT_MSG_SYSTEM and the combat events are registered on the first table and return at
-- once while nothing is live; the one arena ticker drives the clocks only while a table is.
--
-- API (the design):
--   Create(opts) -> id | nil, why     opts = { guest, stake (copper, whole silver; 0: no stake),
--     target (2000|5000|10000), secs (30-120), mode "d"|"a", arbiter, src "o"|"t"|"w",
--     hic (false: a sober table), spectators (false: no watchers; default: they may come), crowd (true: the crowd
--     may bet on the winner; with spectators, an arbiter, never the wallet's stakes), rehearsal,
--     from (the match id of the design) }
--   Answer(id, yes, src, o)           the guest's answer (o.hic false: he asks for a sober table;
--                                     o.spectators false: he relays to nobody)
--   AskArbiter(id, name), AnswerArbiter(id, yes)
--   Roll(id), Keep(mask, act, id), Hiccup(id), Concede(id), Void(id), Sit()
--   Live() -> the table this character plays, View(id) -> the screens' model, Tables(),
--   LiveTables() (the watchable ones: { id, p1, p2, arbiter, official, target, map, by, at, mode,
--   wire }, mode L where the announcing player says his game counts, wire the mode its messages
--   travel in), Watchable(name) -> the id of the live table that player
--   sits at, Watch(id), StopWatching(id), Practice(opts), SelfTest()
--   Counted(id) -> whether that table's game counts (decision 1, above)
--   Best(mode, opts) -> the month's Bones ranking (1.2.3, ArenaHome's Data.GamesRanking("bones"),
--     the honours' source): { { name, key, games, won, lost, at, place } }, most wins first; a tie
--     goes to fewer games, then to who reached his wins first (at: his last counted win), then by
--     name. mode "L" (the games that count; any other mode: none). opts = { month (Honors.MonthOf's
--     number; default this month), offset (the realm clock's, as Honors.MonthOf takes it) }. A
--     game counts when both players' halves agree (the same id, seats, winner, scores, how it
--     ended, steps and transcript hash, their starts within HALF_SKEW), its winner a player, its
--     two players never one owner's (Debts.SameOwner) nor hidden here; then the ledger's caps
--     (ArenaLedger's MIN_RATED_DUR, DAY_MAX, PAIR_MAX in PAIR_DAYS) in the order this client came
--     to hold each game; void games never. (1.2.4) A second value, held: the games both halves
--     agree on that this client holds and that month's list reads (before the caps and the
--     hides): that month's, and the PAIR_DAYS before it, whose games the pair cap counts. Past
--     HALVES_MAX the oldest go first, so a closed month's only falls as this client prunes what
--     its list reads (HonorsNet then keeps the charm's list as it stood).
--   Halves(id) -> what this client holds of a game's halves (the tests'), Pin(name) -> the key it
--     holds for a player, RepeatHalves() (at login)
--   the fill actions Pay(id), PayFee(id), PayStake(id), Payout(id), Refund(id), Change(id)
--   Agreement(id) -> the KE agreement a bank settles an FK market on (the design)
--   ReadDrunk(text) -> "self" | name, level; DrunkReadable()
--   History(mode) -> this character's games of a mode, newest first; MyGames() -> both modes'
--   LedgerRecord(t, g) -> the games' ledger's record of a table that ended (ArenaLedger.Played's)
-- It registers Arena.Events for K, and the actions farkle.*.
-- Messages (the design; numbers in base 36):
--   KI id~d|a~stake~2|5|10~arbiter|-~hostSrc~secs~hic~salt4[~token][~iou][~c]  host -> guest
--   KA id~1|0~guestSrc|reason~hic[~token][~iou][~c]                             guest -> host
--   KO id~host~guest~stake~target~srcs~secs~hic[~crowd[~c]]                     host -> arbiter
--      (c, 1.2.3: the sender's client counts the free game, decision 1; KO's: both players' do)
--   KP id~1|0~reason                                                            arbiter -> host, guest
--   KG id~digest8~host~guest~arbiter|-~target~secs~hic[~crowd[~watch]]          host -> the others
--      (crowd 1|0; watch 0: the host keeps watchers out, every relayer of the table goes quiet)
--   KY id~o~chain8                                                              each participant
--   KH id~0|1~0|1~t|w                                                           arbiter (w: host too)
--   KK id~step~mask~r|b~chain8[~lvl]                                            the current player
--   KT id~step~t|c|a|v|p|g~1|2~chain8~f                                         per claim (p: a combat
--        report, f its state; g: gone from the tavern past the grace, a forfeit)
--   KL id~seat~turn~lvl                                                         the arbiter's floor
--   KE id~1|2|v|x~s1~s2~steps~hash8~ld[~sig]                                   each participant
--   KQ id~fromStep                                                              a participant or watcher
--   KR id~step~code,code,...                                                    the answer to our KQ
--   KS id~s1~s2~cur~turnPts~left~dice[.mask]~phase~step~lv~sk                   the relay (a public
--        arbiter on the channel; a player who allows watchers)
--   KN id~p1~p2~arbiter|-~target~mapID|-~o|e~winner|-                           the announcement
--      ...~o~-~c: (1.2.3) the announcing player's game counts (decision 1)
--      ...~e~winner~s1~s2~how~steps~hash8~end~began~seat~pk|-~sig|-: (1.2.3) a player's half of a
--      game that counts (seat: whose, 1 the host's), on the channel and to the other player
--      (must-deliver), both halves again at each player's later logins (the ranking's word; an
--      older client reads its first eight fields, the end of the table). pk: the half's player's
--      account key, sig: its signature over "OLYB1|" and every field before pk (base64url)
--   KD id~p|r~copper~t|m                                                        payer, payee
--   (The games' ledger's record of a finished game is ArenaLedger's AY.)
local FarkleTable = {}
ns.FarkleTable = FarkleTable
local FT = FarkleTable

FT.INVITE_TTL = 60        -- an invitation (KI) lives this long
FT.GUEST_GAP = 30         -- one invitation per sender to a guest this often
FT.HANDSHAKE = 30         -- every participant's KY within this after one's own
FT.AGREED_WAIT = 120      -- an accepted table opens (the party, the arbiter) within this, or it closes
FT.STAKES_WAIT = 300      -- held stakes within this, or the table closes and refunds
FT.GRACE = 300            -- held and wallet stakes settle this long after the arbiter's KE (the design)
FT.SECS, FT.SECS_MIN, FT.SECS_MAX = 60, 30, 120 -- the turn timer, a phase each
FT.CLICK_MARGIN = 5       -- the acting player's own client stops at secs - 5
FT.CLAIM_MARGIN = 5       -- the judge claims at secs + 5
FT.HIC_CLICK, FT.HIC_CLAIM = 10, 20 -- HIC!'s own clock (the design): the button until 10 s, the claim at 20 s
FT.COMBAT_MAX = 120       -- the clock pauses for combat this long in one game at most
FT.TAVERN_GRACE = 60      -- away from the table this long: a forfeit (the design)
FT.TAVERN_YARDS = 10      -- how far from the table's spot a player may stand
FT.TAVERN_SLACK = 5       -- ...and the few yards a turn in one's chair takes
FT.TAVERN_DIST = 3        -- CheckInteractDistance's index for about 10 yd (duel range)
FT.RESYNC_WAIT = 4        -- a message ahead of what this client wrote waits this long, then KQ
FT.RESYNC_GAP = 10        -- one KQ per table this often
FT.FLOOR_AGE = 8          -- the arbiter floors a level he saw at least this long before a decision
FT.FLOOR_GAP = 10         -- one KL per seat this often
FT.ARBITRATE_MAX = 3      -- tables one arbiter holds at once
FT.WATCH_WHISPER = 3      -- up to this many watchers get the relay by whisper, then the channel
FT.WATCHERS_MAX = 40      -- watchers a table keeps
FT.WATCH_TTL = 150        -- a watcher who has not asked again for this long is dropped
FT.WATCH_ASK = 60         -- a watcher asks again this often
FT.NOTICE_EVERY = 60      -- KN every minute while the table is open
FT.NOTICES_MAX = 100      -- the live tables' notices (KN) this client keeps at once, the oldest heard going first
FT.NOTICES_EACH = FT.ARBITRATE_MAX -- ...from one sender (a public arbiter holds that many tables), his oldest going first
FT.KEEP_NOTICE = 259200   -- a public table's event kept this long where its crowd's market involves the client
-- 1.2.3, the Bones ranking (Best) and its halves (KN "e" with the result)
FT.HALF_SKEW = 600        -- the two halves' starts within this many seconds of each other
FT.HALVES_DAYS = 62       -- games kept this long (the month's and the last, the honours' closed one)
FT.HALVES_MAX = 2000      -- games this client keeps, the ones with a single half going first
FT.HALVES_OPEN_MAX = 50   -- games with a single half one sender may have opened here at once
-- (1.2.4, the author's ask: nothing of the rankings erased early) A game with a single half (or two
-- that differ) is kept as long as its month's games (it was 7 days: the other half heard on the
-- 8th never counted).
FT.HALVES_OPEN_DAYS = FT.HALVES_DAYS
FT.HALVES_DAY_KEEP = 20   -- agreed games kept per player and server day (Best counts DAY_MAX of them)
FT.HALVES_REPEAT = 5      -- this player's own games said again at a login (both halves), the newest first...
-- ...each at as many later logins, this long after its last telling (1.2.4: 8 over about 14 days,
-- 1.2.3's three within a day reached nobody away for a weekend)...
FT.HALVES_REPEAT_GAPS = { 3600, 21600, 72000, 86400, 172800, 259200, 259200, 345600 }
FT.HALVES_REPEAT_DELAY = 45  -- ...from this long after the login
-- (1.2.4) A game of his whose other half never came here: the other player asked for it (KN "h"),
-- at as many of this player's logins as HALVES_ASKS, HALVES_ASK_GAP apart.
FT.HALVES_ASKS, FT.HALVES_ASK_GAP = 8, 3600
FT.HALVES_CHECKS = 20     -- relayed halves whose signature is checked at once
FT.KEYS_MAX = 2000        -- players' keys (pins) kept
-- The ledger's caps (ArenaLedger's, read there when it is loaded): a counted game lasts this long
-- at least, a player counts this many in a server day, a pair this many in PAIR_DAYS days.
FT.RANK_CAPS = { MIN_RATED_DUR = 15, DAY_MAX = 10, PAIR_MAX = 3, PAIR_DAYS = 7 }
FT.ROLL_WAIT = 6          -- a Roll click with no /roll line after this asks for a typed /roll
FT.KR_CODES = 20          -- event codes in one KR
FT.LOG_MAX = 200          -- the tester log's lines
FT.HIST_MAX, FT.TX_MAX, FT.TX_EVENTS, FT.TX_DAYS = 100, 10, 600, 7
-- How a game ended (FarkleRules' reason), in the games' ledger (ArenaLedger's AY) and the history.
FT.WHY = { target = "t", cap = "c", concede = "o", forfeit = "f", void = "v" }
FT.WHY_OF = { t = "target", c = "cap", o = "concede", f = "forfeit", v = "void" }
FT.HOUSE_PAUSE = { think = 0.6, bank = 0.85, next = 0.35, farkle = 1.6, roll = 0.45 } -- the House's pace (the lab's)
FT.REASONS = { b = true, d = true, l = true, n = true, a = true, g = true, c = true, x = true, m = true, t = true, r = true, s = true, p = true, v = true, k = true, o = true, f = true,
	i = true } -- (1.2.1, "i": the guest turned Bones invitations off; an older host reads it as "d")
-- (1.2.1, a player's report: "I don't wanna play bones every time I go to an inn. Or ever.")
FT.INVITES_BURST = 2      -- invitations from this many different players...
FT.INVITES_WINDOW = 600   -- ...within this many seconds: one question, stop receiving them?

-- The stake sources by kind (the design): direct o/o; arbiter t/t or w/w; the King w/w.
FT.SOURCES = { d = { o = true }, a = { t = true, w = true } }

-- (agreed: the invitation accepted, the table not yet open: the host waits for the party or the
-- arbiter, the guest and the arbiter for KG. It is live: it ticks, keeps its player busy, and
-- expires after AGREED_WAIT.)
local LIVE = { invite = true, asked = true, agreed = true, open = true, stakes = true, play = true, ["end"] = true }
local PLAYING = { open = true, stakes = true, play = true }

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function A() return ns.Arena end
local function R() return ns.FarkleRules end
local function Api(mod, fn)
	local m = rawget(ns, mod) or ns[mod]
	local f = type(m) == "table" and m[fn]
	return type(f) == "function" and f or nil
end
local function Call(mod, fn, ...)
	local f = Api(mod, fn)
	if not f then return nil end
	local ok, a, b, c = pcall(f, ...)
	if not ok then ns.Log("farkle: %s.%s failed: %s", mod, fn, tostring(a)) return nil end
	return a, b, c
end
-- The compliance gate (Compliance.lua): a stake, the crowd's bets on a table, their payments only
-- where it allows them (1.1.6: nowhere; a game without a stake, and the House's, always plays).
local function Wagers(kind) return Call("Compliance", "Allows", kind, "bones") == true end
FT.Wagers = Wagers
-- Arbiters only where a wager may happen (Compliance.Arbiters; 1.1.6: none, so a table is its two
-- players' alone and no ask to hold one is taken).
local function Arbiters() return Call("Compliance", "Arbiters") == true end
FT.Arbiters = Arbiters
-- Decision 1 (1.2.3, the owner's): a free game (no gold) counts for the history and the ranking
-- whatever the King's live switch (ArenaRoles' live, which stays off: it is the 2.0 bets' alone);
-- a test build's never, nor the sim's. The duels' lane gives this switch in ArenaNet/Compliance;
-- until that is merged, this local helper says the same, and it is the one line to point there.
local function FreeCounts() return not A().Sim() and not A().TestBuild() end
-- The King's live switch, as this client has his word.
local function LiveOn()
	local Ro = ns.ArenaRoles
	return type(Ro) == "table" and type(Ro.Live) == "function" and Ro.Live() == true
end
local function Clock() return GetTime and GetTime() or ns.Now() end
local function Now() return A().Now() end
local function B36(n) return A().B36(n) end
local function N36(s, lo, hi) return A().N(s, lo, hi) end
local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

local function Split(body)
	local out = {}
	if type(body) ~= "string" then return out end
	for part in (body .. "~"):gmatch("([^~]*)~") do out[#out + 1] = part end
	return out
end

local function Full(name)
	if type(name) ~= "string" or name == "" then return nil end
	return ns.FullName(ns.Normal(name))
end
local function Same(a, b)
	local x, y = Full(a), Full(b)
	return x ~= nil and y ~= nil and x:lower() == y:lower()
end
local function Me() return ns.me end
FT.Same = Same

-- The name a roll line or a drunk line gives is the name the server writes: "First Surname" on
-- our realms, "First Surname-Realm" from elsewhere (Treasury.NotFound compares the same way).
local function LineIs(said, player)
	if type(said) ~= "string" or type(player) ~= "string" then return false end
	local s = said:lower()
	local full = Full(said)
	if full and full:lower() == player:lower() then return true end
	return (ns.TellName(player) or ""):lower() == s or (ns.DisplayName(player) or ""):lower() == s
end
FT.LineIs = LineIs

-- Copper as "12g 34s" (the table's amounts are whole silver).
function FT.Money(c)
	c = floor(tonumber(c) or 0)
	local g, s = floor(c / 10000), floor(c / 100) % 100
	if g > 0 and s > 0 then return ("%dg %ds"):format(g, s) end
	if g > 0 then return ("%dg"):format(g) end
	return ("%ds"):format(s)
end

---------------------------------------------------------------------------
-- The tester log (the design): every roll parse with its time against the decision it followed,
-- every resync; 200 lines, account-wide, in /oly bug and in a copy box.
---------------------------------------------------------------------------

local function LogBox()
	if not ns.db then return nil end
	local box = ns.db.farkleLog
	if type(box) ~= "table" or type(box.lines) ~= "table" then
		box = { on = type(box) == "table" and box.on == true or false, lines = {} }
		ns.db.farkleLog = box
	end
	return box
end
function FT.LogOn() local b = LogBox() return b ~= nil and b.on == true end
function FT.Note(fmt, ...)
	local b = LogBox()
	if not b or not b.on then return end
	local ok, text = pcall(string.format, fmt, ...)
	b.lines[#b.lines + 1] = ("%s %s"):format(date and date("%H:%M:%S") or tostring(Now()), ok and text or tostring(fmt))
	while #b.lines > FT.LOG_MAX do table.remove(b.lines, 1) end
end
function FT.SetLog(on)
	local b = LogBox()
	if not b then return false end
	b.on = on and true or false
	return true
end

---------------------------------------------------------------------------
-- Storage (the design): Arena.Store(mode).farkle[Name-Realm] = { live, arb, opts } in the
-- core, the history and transcripts under the same key in the companion's (Arena.Heavy).
---------------------------------------------------------------------------

local function Key() return (Me() or "?"):lower() end
local function Mine(mode)
	local s = A().Store(mode)
	if type(s) ~= "table" then return nil end
	if type(s.farkle) ~= "table" then s.farkle = {} end
	local m = s.farkle[Key()]
	if type(m) ~= "table" then m = { arb = {}, opts = {} } s.farkle[Key()] = m end
	if type(m.arb) ~= "table" then m.arb = {} end
	if type(m.opts) ~= "table" then m.opts = {} end
	return m
end
-- The same, read only (nothing created: a client that never played keeps no Bones data,
-- and no rehearsal store is made at login).
local function Peek(mode)
	if mode == "T" and not A().Sim() and (type(ns.rdb) ~= "table" or type(ns.rdb.arenaTest) ~= "table") then return nil end
	local s = A().Store(mode)
	local m = type(s) == "table" and type(s.farkle) == "table" and s.farkle[Key()]
	return type(m) == "table" and m or nil
end
local function Heavy(mode)
	local h = A().Heavy(mode)
	if type(h) ~= "table" then return nil end
	if type(h.farkle) ~= "table" then h.farkle = {} end
	local m = h.farkle[Key()]
	if type(m) ~= "table" then m = { hist = {}, tx = {} } h.farkle[Key()] = m end
	if type(m.hist) ~= "table" then m.hist = {} end
	if type(m.tx) ~= "table" then m.tx = {} end
	return m
end
function FT.Opts()
	local m = Mine("L")
	return m and m.opts or {}
end
function FT.TrainingComplete()
	local m = Peek("L")
	return m ~= nil and type(m.opts) == "table" and m.opts.innkeeperLearned == true
end
function FT.CanPlayPlayers()
	return FT.TrainingComplete()
end
function FT.History(mode)
	local h = Heavy(mode or "L")
	return h and h.hist or {}
end
-- The same, read only (nothing made: a client that never played keeps nothing).
local function PeekHeavy(mode)
	local h = A().Heavy(mode)
	local m = type(h) == "table" and type(h.farkle) == "table" and h.farkle[Key()]
	return type(m) == "table" and type(m.hist) == "table" and m or nil
end
-- A peer game can finish before the load-on-demand companion's saved data is attached.
-- Its compact own ledger survives in the core; recover only its recorded facts for this read,
-- never manufacture a transcript or write back into either saved store.
local function HistoryRecord(r)
	if type(r) ~= "table" or r.g ~= "b" or (r.mode ~= "L" and r.mode ~= "T")
		or type(r.id) ~= "string" or r.id == "" or type(r.p1) ~= "string" or type(r.p2) ~= "string"
		or type(r.t) ~= "number" or type(r.s1) ~= "number" or type(r.s2) ~= "number"
		or (r.w ~= "1" and r.w ~= "2" and r.w ~= "v") then return nil end
	local seat = Same(r.p1, Me()) and 1 or (Same(r.p2, Me()) and 2 or nil)
	if not seat and not Same(r.arb, Me()) then return nil end
	local kind, stake, target, hash
	if type(r.x) == "string" then kind, stake, target, hash = r.x:match("^([ad])%.([0-9a-z]+)%.(%d+)%.[0-9a-z]+%.([0-9a-f]+)$") end
	local entry = { id = r.id, t = r.t, host = r.p1, guest = r.p2, arb = r.arb,
		seat = seat, opp = seat and (seat == 1 and r.p2 or r.p1) or nil,
		res = r.w == "v" and "V" or (not seat and "D" or (r.w == tostring(seat) and "W" or "L")),
		s1 = r.s1, s2 = r.s2, why = r.how, reh = r.mode == "T" or nil }
	if kind then
		entry.mode, entry.stake, entry.target, entry.hash8 = kind, N36(stake, 0), R().TARGET_BY_CODE[tonumber(target)], hash
	end
	return entry
end
-- This character's games of both modes, newest first (the screens' "Your games"): the live realm's
-- and the rehearsals', where every game goes while the King's live switch is off (1.1.6's case).
function FT.MyGames()
	local all, seen = {}, {}
	for _, mode in ipairs({ "L", "T" }) do
		local m = PeekHeavy(mode)
		for i, e in ipairs(m and m.hist or {}) do
			if type(e) == "table" then
				all[#all + 1] = { e = e, t = tonumber(e.t) or 0, i = i, mode = mode }
				if type(e.id) == "string" then seen[mode .. ":" .. e.id] = true end
			end
		end
	end
	local ledger = Call("ArenaLedger", "MyGames")
	for i, r in ipairs(type(ledger) == "table" and ledger or {}) do
		local e = HistoryRecord(r)
		if e and not seen[r.mode .. ":" .. e.id] then
			seen[r.mode .. ":" .. e.id] = true
			all[#all + 1] = { e = e, t = e.t, i = FT.HIST_MAX + i, mode = r.mode }
		end
	end
	-- (each list is newest first: within one second, its own order)
	table.sort(all, function(a, b)
		if a.t ~= b.t then return a.t > b.t end
		if a.mode ~= b.mode then return a.mode < b.mode end
		return a.i < b.i
	end)
	local out, count = {}, { L = 0, T = 0 }
	for _, x in ipairs(all) do
		if count[x.mode] < FT.HIST_MAX then
			out[#out + 1] = x.e; count[x.mode] = count[x.mode] + 1
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Tables in memory
---------------------------------------------------------------------------

local tables = {}      -- [id] = t: every table this client plays, arbitrates, watches or practises
local invitedBy = {}   -- [sender, lower case] = when he last invited us (a guest takes one per GUEST_GAP)
local notices = {}     -- [id] = the latest KN heard (the live tables list)
local practiceN = 0
FT.busy = function() return false end -- the board: true while its dice are still moving (the House waits)

function FT.Get(id) return tables[id] end
function FT.Tables()
	local out = {}
	for _, t in pairs(tables) do out[#out + 1] = t end
	table.sort(out, function(a, b) return (a.created or 0) < (b.created or 0) end)
	return out
end
local function IsPlayer(t, name) return Same(t.players[1], name) or Same(t.players[2], name) end
local function SeatOf(t, name)
	if Same(t.players[1], name) then return 1 end
	if Same(t.players[2], name) then return 2 end
	return nil
end
-- The table this character plays now (host or guest, not yet closed), or nil.
function FT.Live()
	for _, t in pairs(tables) do
		if (t.role == "host" or t.role == "guest") and LIVE[t.state] then return t end
	end
	return nil
end
local function Arbitrating()
	local n = 0
	for _, t in pairs(tables) do if t.role == "arbiter" and LIVE[t.state] then n = n + 1 end end
	return n
end
-- The participants a table's messages go to: the players and the arbiter, not this client.
local function Others(t)
	local out = {}
	for _, name in ipairs({ t.host, t.guest, t.arbiter }) do
		if name and not Same(name, Me()) then out[#out + 1] = name end
	end
	return out
end
local function Send(t, kind, body, to, o)
	o = o or {}
	local opts = { to = to, urgent = o.urgent, must = o.must, key = o.key, low = o.low, obligation = o.obligation }
	return A().Send(kind, t.mode, body, opts)
end
local function SendAll(t, kind, body, o)
	for _, name in ipairs(Others(t)) do Send(t, kind, body, name, o) end
end

---------------------------------------------------------------------------
-- The group, units, the tavern (the design)
---------------------------------------------------------------------------

local function UnitOf(name)
	if Same(name, Me()) then return "player" end
	local raid = IsInRaid and IsInRaid()
	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	local last = raid and n or (n - 1)
	for i = 1, last do
		local unit = (raid and "raid" or "party") .. i
		local u = ns.UnitFullName(unit)
		if u and Same(u, name) then return unit end
	end
	return nil
end
FT.UnitOf = UnitOf
function FT.InGroup(name) return UnitOf(name) ~= nil end
function FT.GroupDist()
	if IsInRaid and IsInRaid() then return "RAID" end
	if IsInGroup and IsInGroup() then return "PARTY" end
	return nil
end

-- A unit's world position ({ cont, wx, wy }, UnitPosition's order: north, then west), or nil where
-- the client gives none or a secret.
local function Position(unit)
	if not unit or not UnitPosition then return nil end
	local ok, y, x, _, inst = pcall(UnitPosition, unit)
	if not ok or Secret(y) or Secret(x) or Secret(inst) then return nil end
	if type(y) ~= "number" or type(x) ~= "number" or type(inst) ~= "number" then return nil end
	return { cont = inst, wx = y, wy = x }
end
FT.Position = Position
local function Near(unit)
	if not unit or not CheckInteractDistance then return nil end
	local ok, yes = pcall(CheckInteractDistance, unit, FT.TAVERN_DIST)
	if not ok or Secret(yes) then return nil end
	return yes and true or false
end
local function Resting()
	if not IsResting then return nil end
	local ok, yes = pcall(IsResting)
	if not ok or Secret(yes) then return nil end
	return yes and true or false
end
local function InnAt(pos)
	local P = ns.Places
	if not pos or type(P) ~= "table" then return nil end
	return P.InnAt(pos.cont, pos.wx, pos.wy)
end

-- Resting in a city alone is not a tavern. Only a mapped inn with a keeper qualifies.
-- Read the gossip unit, never the player's target, for its localized name.
local keeperNames = {}
function FT.Innkeeper(requireNPC)
	if Resting() ~= true then return nil end
	local inn = InnAt(Position("player"))
	if not inn or type(inn.npc) ~= "number" or not inn.innkeeper then return nil end
	local name = keeperNames[inn.id] or inn.innkeeper
	local guid = UnitGUID and UnitGUID("npc")
	if Secret(guid) then return nil end
	local npc = type(guid) == "string" and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
	if requireNPC and npc ~= inn.npc then return nil end
	if npc == inn.npc and UnitName then
		local said = UnitName("npc")
		if not Secret(said) and type(said) == "string" and said ~= "" then name = said; keeperNames[inn.id] = said end
	end
	return name, inn.id
end

local keeperVoices = {}
local KEEPER_RACES = { Human = true, Dwarf = true, Gnome = true, NightElf = true, Orc = true, Tauren = true,
	Troll = true, Scourge = true, Goblin = true, BloodElf = true, Draenei = true, Pandaren = true }
-- A voice follows only a race the client read from this inn's actual gossip unit.
-- The session cache lets the lesson retain it after the NPC conversation closes.
function FT.InnkeeperVoice()
	local inn = InnAt(Position("player"))
	if not inn or type(inn.npc) ~= "number" then return nil end
	if not UnitGUID then return keeperVoices[inn.id] end
	local ok, guid = pcall(UnitGUID, "npc")
	if not ok or Secret(guid) then return nil end
	if guid == nil then return keeperVoices[inn.id] end
	local npc = type(guid) == "string" and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
	if npc ~= inn.npc or not UnitRace then return nil end
	local read, _, race = pcall(UnitRace, "npc")
	if not read or Secret(race) or type(race) ~= "string" or not KEEPER_RACES[race] then return nil end
	keeperVoices[inn.id] = race
	return race
end

-- Forever's own Campfire Nearby aura, not the old Cooking Fire spell or a retained camp benefit.
-- Build 70205: Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua:395-409.
-- Read only this player's aura: another player's word never grants a venue, and nothing here
-- posts a Board camp or changes location consent. Unknown/restricted reads are not absences.
function FT.CampfireNearby()
	local C = C_UnitAuras
	if type(C) ~= "table" or type(C.GetPlayerAuraBySpellID) ~= "function" then return nil end
	local ok, aura = pcall(C.GetPlayerAuraBySpellID, 1283391)
	if not ok or Secret(aura) then return nil end
	if aura == nil then return false end
	if type(aura) ~= "table" or Secret(aura.spellId) or type(aura.spellId) ~= "number" then return nil end
	return aura.spellId == 1283391
end

-- A camp either player explicitly posted on the Board, in this client's current zone.
local function CampFor(a, b)
	local Bd = ns.Board
	if type(Bd) ~= "table" or not Bd.CampOf then return nil end
	if IsInInstance and IsInInstance() then return nil end
	local zone = ns.Layers and ns.Layers.CurrentMap and ns.Layers.CurrentMap() or nil
	if not zone then return nil end
	for _, name in ipairs({ a, b }) do
		local camp = name and Bd.CampOf(name)
		if camp and tonumber(camp.zone) == tonumber(zone) then return camp end
	end
	return nil
end
FT.CampFor = CampFor

local function TableCamp(a, b)
	if A().InInstance() then return nil end
	if FT.CampfireNearby() == true then return { campfire = true } end
	return CampFor(a, b)
end

function FT.CanOpen()
	if A().Sim() then return true end
	if A().Blocked() then return false end
	if Resting() == true and InnAt(Position("player")) then return true end
	if FT.CampfireNearby() == true then return true end
	if CampFor(Me(), Me()) then return true end
	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	local raid = IsInRaid and IsInRaid()
	for i = 1, raid and n or math.max(0, n - 1) do
		local peer = ns.UnitFullName((raid and "raid" or "party") .. i)
		if peer and CampFor(Me(), peer) then return true end
	end
	return false
end

-- The place rule (the design's tavern rule, 1.1.6 with camps): a game between players that counts
-- is played at a tavern or at a camp. Both in one party, within about 10 yd of each other, and
-- either both resting at the same inn, near a real Forever campfire (checked independently by
-- each participant at opening), or by a Board camp in their zone. Returns ok, why, the inn
-- (nil at a camp), the spot (the middle of the two) and the
-- camp. why: "group", "rest" (neither at an inn nor by a camp), "inn" (at an inn, not the same
-- one, no camp), "far", "unknown".
function FT.TavernStart(other)
	local unit = UnitOf(other)
	if not unit or unit == "player" then return false, "group" end
	local resting = Resting() == true
	local camp = TableCamp(Me(), other)
	if not resting and not camp then return false, "rest" end
	local me, them = Position("player"), Position(unit)
	if not me or not them then return false, "unknown" end
	local near = Near(unit)
	local d = ns.Places.Dist(me, them)
	local far = near == false or (near == nil and (not d or d > FT.TAVERN_YARDS))
	local spot = { cont = me.cont, wx = (me.wx + them.wx) / 2, wy = (me.wy + them.wy) / 2 }
	if resting then
		local inn, theirs = InnAt(me), InnAt(them)
		if inn and theirs and theirs.id == inn.id then
			if far then return false, "far" end
			return true, nil, inn, spot
		end
		if not camp then return false, "inn" end
	end
	if far then return false, "far" end
	return true, nil, nil, spot, camp
end

-- Where a table that counts is played (TavernStart's place on this client): t.inn, or t.camp, and
-- t.spot. Nothing set where the place cannot be read here.
local function SetPlace(t, other)
	local ok, _, inn, spot, camp = FT.TavernStart(other)
	if not ok then return end
	t.inn, t.camp, t.spot = inn and inn.id or nil, (not inn and camp) and true or nil, spot
	t.campfire = not inn and camp and camp.campfire or nil
end

-- A seat is away when this client can see it is: its position off the table's inn or its spot,
-- or (this player himself, at an inn) no longer resting. What cannot be seen counts as present.
local function Away(t, seat)
	if not (t.inn or t.camp) or not t.spot then return false end
	local name = t.players[seat]
	local unit = UnitOf(name)
	if not unit then return true end -- (left the group: gone from the table)
	if t.inn and unit == "player" and Resting() == false then return true end
	if t.campfire and unit == "player" and FT.CampfireNearby() == false then return true end
	-- (by position only: CheckInteractDistance, the start's check, says two players are apart,
	-- never which of them walked off)
	local pos = Position(unit)
	if not pos then return false end
	if t.inn then
		local inn = InnAt(pos)
		if not inn or inn.id ~= t.inn then return true end
	end
	local d = ns.Places.Dist(pos, t.spot)
	return d ~= nil and d > FT.TAVERN_YARDS + FT.TAVERN_SLACK
end
FT.Away = Away

---------------------------------------------------------------------------
-- The drunk lines (the design): the game's own DRUNK_MESSAGE_* globals, read when parsing
-- (another addon may blank them), plain and item forms, the grammar tokens resolved, the most
-- literal match wins and a tie is left unread (drunk/client.md 2.5).
---------------------------------------------------------------------------

local DRUNK = {}
for _, who in ipairs({ "SELF", "OTHER" }) do
	for n = 1, 4 do
		DRUNK[#DRUNK + 1] = { key = "DRUNK_MESSAGE_" .. who .. n, self = who == "SELF", level = n - 1 }
		DRUNK[#DRUNK + 1] = { key = "DRUNK_MESSAGE_ITEM_" .. who .. n, self = who == "SELF", level = n - 1, item = true }
	end
end
FT.DRUNK_KEYS = DRUNK

-- Every spelling a format may arrive in: raw, and with koKR's |1a;b; and frFR's |2 resolved.
local function Spellings(fmt)
	local out = { fmt }
	local function Expand(list, pattern, choices)
		local res = {}
		for _, f in ipairs(list) do
			res[#res + 1] = f
			if f:find(pattern) then for _, c in ipairs(choices(f)) do res[#res + 1] = c end end
		end
		return res
	end
	local function ResolveAll(f)
		local a, b = f:match("|1([^;]*);([^;]*);")
		if not a then return { f } end
		local res = {}
		for _, pick in ipairs({ a, b }) do
			for _, g in ipairs(ResolveAll((f:gsub("|1[^;]*;[^;]*;", (pick:gsub("%%", "%%%%")), 1)))) do res[#res + 1] = g end
		end
		return res
	end
	out = Expand(out, "|1[^;]*;[^;]*;", ResolveAll)
	out = Expand(out, "|2 ", function(f) return { (f:gsub("|2 ", "de ")), (f:gsub("|2 ", "d'")) } end)
	return out
end
local function Literal(fmt) return #(fmt:gsub("%%s", "")) end

-- Every DRUNK_MESSAGE_* global there and not blank (a blank one: another addon hides the lines).
function FT.DrunkReadable()
	for _, k in ipairs(DRUNK) do
		local v = rawget(_G, k.key)
		if type(v) ~= "string" or v == "" then return false end
	end
	return true
end

-- Practice observes only this player's lines; either self form can identify each level.
local function OwnDrunkReadable()
	for n = 1, 4 do
		local plain = rawget(_G, "DRUNK_MESSAGE_SELF" .. n)
		local item = rawget(_G, "DRUNK_MESSAGE_ITEM_SELF" .. n)
		if not ((type(plain) == "string" and plain ~= "") or (type(item) == "string" and item ~= "")) then return false end
	end
	return true
end

-- A drunk line: "self" (this player's own "You feel ...") or the name it gives, and the level
-- (0 sober .. 3 completely smashed); nil when it is none, or ambiguous.
function FT.ReadDrunk(text)
	if type(text) ~= "string" or Secret(text) then return nil end
	local P = ns.ArenaParse
	if type(P) ~= "table" then return nil end
	local best, bestLen, tie
	for _, k in ipairs(DRUNK) do
		local fmt = rawget(_G, k.key)
		if type(fmt) == "string" and fmt ~= "" then
			for _, f in ipairs(Spellings(fmt)) do
				local args = P.Scan(f, text)
				if args then
					local len = Literal(f)
					if not best or len > bestLen then best, bestLen, tie = { k = k, args = args }, len, false
					elseif len == bestLen and best.k ~= k then tie = true end
				end
			end
		end
	end
	if not best or tie then return nil end
	if best.k.self then return "self", best.k.level end
	local name = best.args[1]
	if type(name) ~= "string" or name == "" then return nil end
	return name, best.k.level
end

---------------------------------------------------------------------------
-- Events and screens
---------------------------------------------------------------------------

local function Changed(t, state)
	ns.Fire("FARKLE_TABLE", t.id, state or t.state)
	A().Changed()
end
local function Emit(t, info)
	info.id = t.id
	ns.Fire("FARKLE_EVENT", t.id, info)
end

-- A line on the table's own log (the board shows the latest), with its kind for the colour.
local function Say(t, key, ...)
	t.log = t.log or {}
	local fmt = L[key] or key
	local ok, text = pcall(string.format, fmt, ...)
	t.log[#t.log + 1] = { text = ok and text or fmt, key = key, at = Now() }
	while #t.log > 60 do table.remove(t.log, 1) end
end

---------------------------------------------------------------------------
-- Involvement and the clocks
---------------------------------------------------------------------------

local watching = false -- CHAT_MSG_SYSTEM and the combat events are registered
local Tick, OnSystem, OnCombat -- (below)

local function Watch()
	if watching then return end
	watching = true
	ns.RegisterEvent("CHAT_MSG_SYSTEM", function(text) OnSystem(text) end)
	ns.RegisterEvent("PLAYER_REGEN_DISABLED", function() OnCombat(true) end)
	ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() OnCombat(false) end)
end
FT.Watching = function() return watching end

local function Involve(t, on)
	A().Involve("table:" .. t.id, on)
	local any = false
	for _, x in pairs(tables) do if LIVE[x.state] or x.role == "watch" or x.role == "practice" and not x.closed then any = true end end
	if any then
		Watch()
		A().Every(1, "farkle", function() Tick() end)
	else
		A().Every(1, "farkle", nil)
	end
end

-- The phase clock of the seat to act: when its phase started here (this client's own GetTime,
-- from the line or message that began it), less the pauses since.
local function ClockKey(t)
	local g = t.game
	if not g or g.over then return nil end
	local who, phase = R().Expect(g)
	if not who then return nil end
	return who .. ":" .. phase .. ":" .. g.step, who, phase
end
local function ResetClock(t)
	local key, who, phase = ClockKey(t)
	if not key then t.clock = nil return end
	if t.clock and t.clock.key == key then return end
	t.clock = { key = key, seat = who, phase = phase, start = Clock(), paused = 0 }
end
-- Seconds used of the phase so far (the pauses left out).
local function Used(t)
	local c = t.clock
	if not c then return 0 end
	local paused = c.paused
	if c.pausedAt then paused = paused + (Clock() - c.pausedAt) end
	return max(0, Clock() - c.start - paused)
end
-- The phase's limits: when the actor's own client stops, when the judge claims.
local function Limits(t)
	local c = t.clock
	if c and c.phase == "hiccup" then return FT.HIC_CLICK, FT.HIC_CLAIM end
	return t.secs - FT.CLICK_MARGIN, t.secs + FT.CLAIM_MARGIN
end
FT.Used, FT.Limits = Used, Limits

-- Why the clock stands still now: "combat" (a player reported it, 120 s a game at most),
-- "tavern" (a player is away from the table, the design), or nil.
local function PauseWhy(t)
	if t.away then
		for _, since in pairs(t.away) do if since then return "tavern" end end
	end
	if t.combat then
		-- (120 s of combat a game at most: the time already paused, and this stretch so far)
		local now = Clock()
		for _, since in pairs(t.combat) do
			if since and (t.combatUsed or 0) + (now - since) < FT.COMBAT_MAX then return "combat" end
		end
	end
	return nil
end
local function UpdatePause(t)
	local c = t.clock
	if not c then return end
	local why = PauseWhy(t)
	local now = Clock()
	if why and not c.pausedAt then
		c.pausedAt, c.pauseWhy = now, why
	elseif not why and c.pausedAt then
		c.paused = c.paused + (now - c.pausedAt)
		c.pausedAt, c.pauseWhy = nil, nil
	elseif why then
		c.pauseWhy = why
	end
end

---------------------------------------------------------------------------
-- History and transcripts
---------------------------------------------------------------------------

local PARTICIPANT = { host = true, guest = true, arbiter = true }
-- Whether this client counts a free game in T: no gold, the live switch off, a release (decision 1,
-- FreeCounts). T while the switch is on is a rehearsal asked for (the create panel's box).
local function FreeOffer(t)
	return t.mode == "T" and (t.stake or 0) == 0 and not LiveOn() and FreeCounts()
end
-- Whether a game between players counts (history, ranking), on the client of one who sits at it
-- (a player, its arbiter): its mode L (the live switch on), or a free game in T that both players'
-- clients count (FreeOffer here, and the other's word: t.free, the "c" of his KI or KA, the host's
-- KO for the arbiter). A test build's never, nor a 1.2.2 client's, which says no "c": the game is
-- then a rehearsal on both sides, never counted on one alone. Never the House's.
local function GameCounts(t)
	if type(t) ~= "table" or not PARTICIPANT[t.role] or not (t.host and t.guest) then return false end
	if A().Counts(t.mode) then return true end
	return t.free == true and FreeOffer(t)
end
-- ...on a player's client (the one with a half to give).
local function Counted(t) return GameCounts(t) and (t.role == "host" or t.role == "guest") end
FT.Counted = function(id) local t = tables[id] return t ~= nil and Counted(t) end
-- The mode a game's records go in (the games' ledger, Bones's history): L where it counts, so a
-- free game of 1.2.x is the live realm's and no rehearsal's, on its players' and its arbiter's
-- clients alike; else the table's own.
local function RecordMode(t) return GameCounts(t) and "L" or t.mode end
-- The games' ledger's record of a table that ended (ArenaLedger.Played's), or nil: a game between
-- players (b) for its players and its arbiter, the House's (h, or p with the rules' hints) for
-- the one who played it. Every participant of a game between players says the same: who, the
-- result, the scores, how it ended and the detail (kind, stake, target, steps, the transcript's
-- hash); the time and the length are each one's own clock.
function FT.LedgerRecord(t, g)
	if type(t) ~= "table" or type(g) ~= "table" or not g.over then return nil end
	local w = (g.reason == "void" or not g.winner) and "v" or tostring(g.winner)
	local rec = { t = Now(), dur = t.began and max(0, Now() - t.began) or 0, w = w, s1 = g.scores[1], s2 = g.scores[2],
		how = FT.WHY[g.reason] or "v" }
	if t.role == "practice" then
		t.ledgerId = t.ledgerId or Call("ArenaLedger", "SoloId")
		if not t.ledgerId then return nil end
		rec.id, rec.g, rec.p1 = t.ledgerId, t.learn and "p" or "h", Me()
		rec.x = tostring(R().TARGET_CODE[t.target] or 0)
		return rec
	end
	if not PARTICIPANT[t.role] or not (t.host and t.guest) then return nil end
	local hash = R().Hash(g)
	if type(hash) ~= "string" then return nil end
	rec.id, rec.g, rec.p1, rec.p2, rec.arb = t.id, "b", Full(t.host), Full(t.guest), t.arbiter and Full(t.arbiter) or nil
	rec.x = table.concat({ t.kind == "a" and "a" or "d", B36(t.stake or 0), tostring(R().TARGET_CODE[t.target] or 0), B36(g.step), hash:lower() }, ".")
	return rec
end
local function Ledger(t, g)
	local rec = FT.LedgerRecord(t, g)
	if rec then Call("ArenaLedger", "Played", RecordMode(t), rec) end
end

local function Keep(t)
	if t.kept or t.role == "watch" then return end
	t.kept = true
	local g = t.own or t.game
	if not g then return end
	-- (the games' ledger's record, whether or not the companion's saved data is loaded)
	Ledger(t, g)
	local mode = RecordMode(t)
	local h = Heavy(mode)
	if not h then return end
	local seat = t.seat
	local res
	if g.reason == "void" or not g.winner then res = "V"
	elseif seat then res = g.winner == seat and "W" or "L"
	else res = "D" end
	local opp = seat and t.players[3 - seat] or nil
	local entry = { id = t.id, t = Now(), opp = opp, arb = t.arbiter, mode = t.kind, src = seat and t.src[seat] or nil,
		stake = t.stake, target = t.target, res = res, s1 = g.scores[1], s2 = g.scores[2], hash8 = R().Hash(g),
		reh = mode == "T" or nil, practice = t.role == "practice" or nil, learn = t.learn or nil, ld = t.ld,
		seat = seat, host = t.host, guest = t.guest, why = FT.WHY[g.reason] }
	table.insert(h.hist, 1, entry)
	while #h.hist > FT.HIST_MAX do table.remove(h.hist) end
	local events = {}
	for i = 1, min(#g.events, FT.TX_EVENTS) do events[i] = g.events[i] end
	h.tx[t.id] = { t = Now(), head = g.head, events = events }
	local ids = {}
	for id, x in pairs(h.tx) do ids[#ids + 1] = { id = id, t = tonumber(x.t) or 0 } end
	table.sort(ids, function(a, b) return a.t > b.t end)
	for i = FT.TX_MAX + 1, #ids do h.tx[ids[i].id] = nil end
end

---------------------------------------------------------------------------
-- The Bones ranking's halves (1.2.3, the owner's decision 2: a game counts only when both players'
-- clients said the same result, each its own signed half, as a direct duel's two halves)
---------------------------------------------------------------------------
-- Each player's client signs its half of a game that counts with his account's key (Debts.Sign,
-- the key his IOUs and results sign with) and publishes it as the game ends (KN "e" with the
-- result: on the channel, and to the other player must-deliver). It keeps its own half and the
-- other player's signed one, and says both again at later logins, spaced (RepeatHalves), so a
-- member who was away hears the game from either player. Every client keeps what it hears, for
-- Best. A half is taken:
--   - from its own player (the server stamps the sender); the key it carries is then this
--     client's key for him (his pin);
--   - relayed on the channel by the game's other player, only when it carries the key this client
--     holds for its player (his claim Debts verified, else his pin) and its signature is good
--     (checked in Ed25519.lua's time slices): nobody can say another player's half;
--   - by whisper only where this client sits at the game (the other player's half of its own).
-- Each player's first half of a game stays: a later one that says another result is refused
-- ("changed"), and once both agree the game is fixed ("conflict" for any other word on it). A
-- game is kept under its id and its seats (the host first, as the table has them), so a word
-- naming other seats under that id is another game, which never spoils the real one. The two
-- agree when they say the same result (winner, scores, how it ended, steps, transcript hash) and
-- started within HALF_SKEW: the start is the one time both clients share whatever happens after
-- the game (a player away at its end finishes it later, on his return).
-- Kept per realm group and faction (the channel's) in the core's saved data, made only to keep
-- one, small (an agreed game is one line):
--   ns.rdb.bonesRank[faction] = {
--     open = { [id:p1:p2] = { id, p1, p2, got, first, by = { [player, lower case] = word } } }:
--       a game with a single half, or two that differ (or past HALVES_DAY_KEEP: full); word =
--       "w.s1.s2.how.steps.hash8|began|end" (numbers in base 36, times server time, its sender's),
--     done = { [id:p1:p2] = "w|t|dur|at|w.s1.s2.how.steps.hash8|p1|p2" }: both halves agree; t the
--       game's time (the earlier end, never before the later start), dur the longer of the two
--       lengths (a loser cannot shorten it under the ledger's minimum), at when this client first
--       held both (the caps' order),
--     keys = { [player, lower case] = his key, base64url } (the pins),
--     own = { [id:p1:p2] = { t, mode, mine, theirs, n, last, asks, askedAt } }: this player's own
--       games: his signed half and the other's (their bodies), the repeats said (n) and the last
--       telling (last); (1.2.4) the asks for the other's half (asks) and the last (askedAt),
--     months = { [monthNo] = { n, at, rows = { { name, games, won, lost }, ... } } }: (1.2.4) each
--       closed month's list, kept for good (HV.Archive) }

-- (The halves' helpers and state are one table's fields: this file's main chunk is near Lua 5.1's
-- 200 locals.)
local HV = {}
local function Low(name) local f = Full(name) return f and f:lower() or nil end
local function RankStore(make)
	if A().Sim() or type(ns.rdb) ~= "table" then return nil end
	local s = ns.rdb.bonesRank
	if type(s) ~= "table" then
		if not make then return nil end
		s = { v = 2 }
		ns.rdb.bonesRank = s
	end
	local side = tostring(ns.faction or "Alliance")
	local b = s[side]
	if type(b) ~= "table" then
		if not make then return nil end
		b = {}
		s[side] = b
	end
	for _, k in ipairs({ "open", "done", "keys", "own", "months" }) do
		if type(b[k]) ~= "table" then b[k] = {} end
	end
	b.games = nil -- (the layout of 1.2.3's unreleased drafts: heard again)
	return b
end
HV.gen = 0 -- a game kept or changed: Best works its list out again
-- HV.held = { b, n, day }: the games held (open and done) and the agreed ones per player and day,
-- worked out at the first need
local function HalfKey(id, p1, p2) return ("%s:%s:%s"):format(id, Low(p1) or "?", Low(p2) or "?") end

-- The result a half says, the part both must say alike; a word as the store keeps it.
function HV.Said(h) return table.concat({ h.w, B36(h.s1), B36(h.s2), h.how, B36(h.steps), h.hash }, ".") end
function HV.Word(h) return ("%s|%s|%s"):format(HV.Said(h), B36(h.began), B36(h.t)) end
function HV.ReadWord(s)
	if type(s) ~= "string" then return nil end
	local said, began, fin = s:match("^([^|]+)|([0-9a-z]+)|([0-9a-z]+)$")
	began, fin = said and N36(began, 0), said and N36(fin, 0)
	if not (began and fin) then return nil end
	return said, began, fin
end
function HV.DoneLine(r)
	return table.concat({ r.w, B36(r.t), B36(r.dur), B36(r.at), r.said, r.p1, r.p2 }, "|")
end
function HV.ReadDone(s)
	if type(s) ~= "string" then return nil end
	local w, t, dur, at, said, p1, p2 = s:match("^([12])|([0-9a-z]+)|([0-9a-z]+)|([0-9a-z]+)|([^|]+)|([^|]+)|([^|]+)$")
	t, dur, at = w and N36(t, 0), w and N36(dur, 0), w and N36(at, 0)
	if not (t and dur and at) then return nil end
	return { w = w, t = t, dur = dur, at = at, said = said, p1 = p1, p2 = p2 }
end
function HV.Held(b)
	if HV.held and HV.held.b == b then return HV.held end
	HV.held = { b = b, n = 0, day = {} }
	for _ in pairs(b.open) do HV.held.n = HV.held.n + 1 end
	for _, s in pairs(b.done) do
		HV.held.n = HV.held.n + 1
		local r = HV.ReadDone(s)
		if r then
			local d = floor(r.t / 86400)
			for _, name in ipairs({ r.p1, r.p2 }) do
				local k = (Low(name) or "?") .. "|" .. d
				HV.held.day[k] = (HV.held.day[k] or 0) + 1
			end
		end
	end
	return HV.held
end

-- The game both halves agree on: { w, t (the earlier end, never before the later start), dur (the
-- longer of the two lengths), said }, or nil.
function HV.Agreed(e)
	if type(e) ~= "table" or type(e.by) ~= "table" then return nil end
	local sa, ba, ea = HV.ReadWord(e.by[Low(e.p1) or ""])
	local sb, bb, eb = HV.ReadWord(e.by[Low(e.p2) or ""])
	if not sa or sa ~= sb then return nil end
	local w = sa:match("^([12])%.")
	if not w or abs(ba - bb) > FT.HALF_SKEW then return nil end
	local start = max(ba, bb)
	local t = max(min(ea, eb), start)
	return { w = w, t = t, dur = min(86400, max(0, ea - ba, eb - bb)), said = sa }
end

function HV.B64(raw) local Ed = ns.Ed25519 return type(Ed) == "table" and Ed.ToB64 and Ed.ToB64(raw) or nil end
function HV.Raw(text, len)
	local Ed = ns.Ed25519
	local ok, r = pcall(function() return type(text) == "string" and type(Ed) == "table" and Ed.FromB64 and Ed.FromB64(text) or nil end)
	return ok and type(r) == "string" and #r == len and r or nil
end
-- The key this client holds for a player (base64url): his claim Debts verified (his GUID's), else
-- the one his own halves carried here (his pin); nil when none.
function HV.PinOf(b, name)
	local raw = Call("Debts", "KeyOf", name)
	if type(raw) == "string" and #raw == 32 then return HV.B64(raw) end
	local k = b and b.keys[Low(name) or ""]
	return type(k) == "string" and k or nil
end

-- This player's own game: his half (mine) and the other player's signed one (theirs), for the repeats.
function HV.KeepOwn(b, key, h, mine)
	local o = b.own[key]
	if type(o) ~= "table" then
		o = { t = h.t, mode = h.mode == "L" and "L" or "T", n = 0 }
		b.own[key] = o
	end
	if mine and type(o.mine) ~= "string" then
		-- (its end is the game's first telling: the repeats' clock starts there)
		o.mine, o.t, o.last, o.mode = h.body, h.t, Now(), h.mode == "L" and "L" or "T"
	elseif not mine and h.pk and h.sig and type(o.theirs) ~= "string" then
		o.theirs = h.body
	end
end

local PruneHalves -- (below)
-- (1.2.4) A game both halves agree on, each signed: a record of the shared records (Records.lua),
-- which any holder tells whoever lacks it. Its two halves' bodies, the host's seat first.
function HV.RecordBody(a, b) return a .. "^" .. b end
function HV.ToRecords(e)
	local bodies = type(e) == "table" and type(e.bodies) == "table" and e.bodies or nil
	local a, b = bodies and bodies[Low(e.p1) or ""], bodies and bodies[Low(e.p2) or ""]
	if type(a) ~= "string" or type(b) ~= "string" then return false end
	return Call("Records", "Take", "b", HV.RecordBody(a, b), Me(), "self") == true
end
-- A half h = { id, p1, p2, seat (whose: 1 the host's, 2 the guest's), w, s1, s2, how, steps, hash,
-- t (its end), began, tc, mode, pk, sig, core, body } heard from sender (its player, or the game's
-- other player relaying it, its signature checked; mine: this client's own, never refused for the
-- flood rule): true (and "again" when it was held already), or false and why. trusted (1.2.4): a
-- half of a record the shared records took (Records.lua: its key the one its player declared here,
-- its signature checked), whoever told it: taken as its own player's.
local function TakeHalf(sender, h, mine, trusted)
	local p1, p2, by = Low(h.p1), Low(h.p2), Low(sender)
	local who = h.seat == 1 and p1 or (h.seat == 2 and p2 or nil)
	if trusted then by = who end
	if not p1 or not p2 or p1 == p2 or not who or not by or (by ~= p1 and by ~= p2) then return false, "sender" end
	local now = Now()
	local cut = now - FT.HALVES_DAYS * 86400
	if h.t > now + 60 or h.t < cut or h.began > h.t or h.began < cut then return false, "time" end
	local b = RankStore(true)
	if not b then return false, "store" end
	local key = HalfKey(h.id, h.p1, h.p2)
	-- (1.2.4: two records of this game saying two results, each signed by both players: neither counts)
	if type(b.clash) == "table" and b.clash[key] then return false, "conflict" end
	local said = HV.Said(h)
	local me = Low(Me())
	-- (this player's own game, one his client knows: his half and the other's, for his repeats)
	local ownGame = (me == p1 or me == p2) and (b.own[key] ~= nil or tables[h.id] ~= nil)
	-- (an agreed game is fixed: its word again, or a conflict)
	local done = HV.ReadDone(b.done[key])
	if done then
		if done.said ~= said then return false, "conflict" end
		if ownGame then HV.KeepOwn(b, key, h, who == me) end
		return true, "again"
	end
	local e = b.open[key]
	if type(e) == "table" and type(e.by) == "table" and e.by[who] ~= nil then
		-- (each player's first half stays: an honest client never says another)
		if HV.ReadWord(e.by[who]) ~= said then return false, "changed" end
		if h.pk and h.sig and not (type(e.bodies) == "table" and e.bodies[who]) then
			e.bodies = type(e.bodies) == "table" and e.bodies or {}
			e.bodies[who] = h.body
		end
		if ownGame then HV.KeepOwn(b, key, h, who == me) end
		return true, "again"
	end
	local hd = HV.Held(b)
	if type(e) ~= "table" or type(e.by) ~= "table" then
		if not mine then
			local opened = 0
			for _, x in pairs(b.open) do if type(x) == "table" and x.first == by then opened = opened + 1 end end
			if opened >= FT.HALVES_OPEN_MAX then return false, "flood" end
		end
		e = { id = h.id, p1 = Full(h.p1), p2 = Full(h.p2), got = now, first = by, by = {} }
		b.open[key] = e
		hd.n = hd.n + 1
	end
	e.by[who] = HV.Word(h)
	-- (1.2.4: a signed half's body, kept until the game agrees: the shared records' record)
	if h.pk and h.sig then
		e.bodies = type(e.bodies) == "table" and e.bodies or {}
		e.bodies[who] = h.body
	end
	-- (a player's own word carries his key: this client's for him from now on, and the shared
	-- records' key for him too)
	if by == who and h.pk and not trusted then
		b.keys[who] = h.pk
		Call("Records", "Pin", who, h.pk)
	end
	if ownGame then HV.KeepOwn(b, key, h, who == me) end
	local ok = not e.full and HV.Agreed(e)
	if ok then
		local d = floor(ok.t / 86400)
		local ka, kb = p1 .. "|" .. d, p2 .. "|" .. d
		if (hd.day[ka] or 0) >= FT.HALVES_DAY_KEEP or (hd.day[kb] or 0) >= FT.HALVES_DAY_KEEP then
			e.full = true -- (kept as heard, never counted: its players' day is full here)
		else
			b.open[key] = nil
			b.done[key] = HV.DoneLine({ w = ok.w, t = ok.t, dur = ok.dur, at = now, said = ok.said, p1 = e.p1, p2 = e.p2 })
			hd.day[ka], hd.day[kb] = (hd.day[ka] or 0) + 1, (hd.day[kb] or 0) + 1
			HV.ToRecords(e)
		end
	end
	HV.gen = HV.gen + 1
	if hd.n > FT.HALVES_MAX then PruneHalves(b) end
	return true
end

-- Games past HALVES_DAYS out (by their time), single halves past HALVES_OPEN_DAYS; past
-- HALVES_MAX, the games with a single half go first (the oldest heard), only then the oldest
-- agreed: no flood of unanswered words ever pushes a counted game out. The pins of players no game
-- here names go past KEYS_MAX.
PruneHalves = function(b)
	-- (1.2.4) Each closed month's list kept first, for good: its games go below.
	HV.Archive(b)
	local now = Now()
	local cut, openCut = now - FT.HALVES_DAYS * 86400, now - FT.HALVES_OPEN_DAYS * 86400
	local open, done = {}, {}
	for key, e in pairs(b.open) do
		if type(e) ~= "table" or type(e.by) ~= "table" or (tonumber(e.got) or 0) < openCut then b.open[key] = nil
		else open[#open + 1] = { key = key, t = tonumber(e.got) or 0 } end
	end
	for key, s in pairs(b.done) do
		local r = HV.ReadDone(s)
		if not r or r.t < cut then b.done[key] = nil else done[#done + 1] = { key = key, t = r.t } end
	end
	for key, o in pairs(b.own) do
		if type(o) ~= "table" or (tonumber(o.t) or 0) < cut then b.own[key] = nil end
	end
	-- (past HALVES_MAX, down to nine tenths of it: a full store is not sorted again at every word)
	local over = #open + #done > FT.HALVES_MAX and #open + #done - floor(FT.HALVES_MAX * 0.9) or 0
	if over > 0 then
		local function Older(x, y) if x.t ~= y.t then return x.t < y.t end return x.key < y.key end
		table.sort(open, Older)
		local n = min(over, #open)
		for i = 1, n do b.open[open[i].key] = nil end
		over = over - n
		if over > 0 then
			-- (1.2.4) Agreed games about to go, the oldest: the ones the last month's list reads,
			-- whose top 3 hold the Bones' charm all this month. The honours keep that list as it
			-- stands first (HonorsNet's BONES_PRUNING, at once), whether anything asked for it yet.
			ns.Fire("BONES_PRUNING")
			table.sort(done, Older)
			for i = 1, min(over, #done) do b.done[done[i].key] = nil end
		end
	end
	local keys = {}
	for k, v in pairs(b.keys) do
		if type(v) ~= "string" then b.keys[k] = nil else keys[#keys + 1] = k end
	end
	if #keys > FT.KEYS_MAX then
		local named = { [Low(Me()) or ""] = true }
		for _, e in pairs(b.open) do named[Low(e.p1) or ""], named[Low(e.p2) or ""] = true, true end
		for _, s in pairs(b.done) do
			local r = HV.ReadDone(s)
			if r then named[Low(r.p1) or ""], named[Low(r.p2) or ""] = true, true end
		end
		table.sort(keys)
		local n = #keys
		for _, k in ipairs(keys) do
			if n <= FT.KEYS_MAX then break end
			if not named[k] then b.keys[k] = nil n = n - 1 end
		end
	end
	HV.held = nil
	HV.gen = HV.gen + 1
end

-- This player's half of a table that ended, or nil: a game that counts (Counted), with a winner;
-- signed with his account's key where he has one (an unsigned half counts from him alone, and is
-- never relayed).
function HV.HalfCore(h)
	return ("%s~%s~%s~-~%d~-~e~%s~%s~%s~%s~%s~%s~%s~%s~%d"):format(h.id, h.p1, h.p2, tonumber(h.tc) or 5, h.w, B36(h.s1), B36(h.s2), h.how,
		B36(h.steps), h.hash, B36(h.t), B36(h.began), h.seat)
end
local function OwnHalf(t)
	local g = t.own or t.game
	if not g or not g.over or not g.winner or g.reason == "void" or not Counted(t) or (t.seat ~= 1 and t.seat ~= 2) then return nil end
	local hash = R().Hash(g)
	if type(hash) ~= "string" then return nil end
	local now = Now()
	local began = min(now, tonumber(t.began) or tonumber(t.created) or now)
	local h = { id = t.id, p1 = Full(t.host), p2 = Full(t.guest), seat = t.seat, w = tostring(g.winner), s1 = g.scores[1], s2 = g.scores[2],
		how = FT.WHY[g.reason] or "v", steps = g.step, hash = hash:lower(), t = now, began = began, tc = R().TARGET_CODE[t.target] or 5,
		mode = t.mode }
	h.core = HV.HalfCore(h)
	local D = ns.Debts
	if type(D) == "table" and type(D.MyKey) == "function" and type(D.Sign) == "function" then
		local ok, gk, pk = pcall(D.MyKey)
		if ok and gk and type(pk) == "string" and #pk == 32 then
			local signed, sig = pcall(D.Sign, "OLYB1|" .. h.core)
			if signed and type(sig) == "string" and #sig == 64 then h.pk, h.sig = HV.B64(pk), HV.B64(sig) end
		end
	end
	h.body = h.core .. "~" .. (h.pk or "-") .. "~" .. (h.sig or "-")
	return h
end

-- What this client holds of a game's halves (the tests'): { { id, p1, p2, agreed, by (a game with
-- a single half or two that differ: { [player] = { said, w, began, t } }), and for an agreed one
-- w, t, dur, at, said } }, one per seats named.
function FT.Halves(id)
	local b = RankStore(false)
	local out = {}
	if not b then return out end
	for _, e in pairs(b.open) do
		if type(e) == "table" and e.id == id and type(e.by) == "table" then
			local by = {}
			for who, s in pairs(e.by) do
				local said, began, fin = HV.ReadWord(s)
				if said then by[who] = { said = said, w = said:match("^(%d)"), began = began, t = fin } end
			end
			out[#out + 1] = { id = e.id, p1 = e.p1, p2 = e.p2, by = by, agreed = false, full = e.full }
		end
	end
	for key, s in pairs(b.done) do
		local r = key:match("^([^:]+):") == id and HV.ReadDone(s)
		if r then out[#out + 1] = { id = id, p1 = r.p1, p2 = r.p2, agreed = true, w = r.w, t = r.t, dur = r.dur, at = r.at, said = r.said } end
	end
	return out
end
function FT.Pin(name) return HV.PinOf(RankStore(false), name) end

-- The calendar month of server time t, as the honours number it (Honors.MonthOf: the same UTC
-- month without it).
local function MonthOf(t, offset)
	local f = Api("Honors", "MonthOf")
	if f then
		local ok, n = pcall(f, t, offset)
		if ok and type(n) == "number" then return n end
	end
	if type(offset) == "function" then offset = offset(t) end
	local d = date and date("!*t", floor((tonumber(t) or 0) + (tonumber(offset) or 0)))
	return type(d) == "table" and (d.year * 12 + d.month - 1) or 0
end

-- (1.2.4, the author's ask: rankings are never erased.) Each closed month's list, kept for good in
-- months[monthNo] = { n (the games its list read: Best's second value), at, rows = { { name, games,
-- won, lost }, ... } } as this client works it out: at a login's prune, and before agreed games go
-- past HALVES_MAX. Its games themselves go after HALVES_DAYS. Worked out again while as many games
-- as it read, or more, are still held (a game heard late; a player hidden here); fewer (pruned), the
-- list kept stands (HonorsNet's KeptBones rule).
function HV.Archive(b)
	local now = MonthOf(Now())
	local seen = {}
	for _, s in pairs(b.done) do
		local r = HV.ReadDone(s)
		local m = r and MonthOf(r.t)
		if m and m < now then seen[m] = true end
	end
	for m in pairs(seen) do
		local rows, n = FT.Best("L", { month = m })
		n = tonumber(n) or 0
		local kept = b.months[m]
		if type(rows) == "table" and n > 0 and not (type(kept) == "table" and (kept.sealed or (tonumber(kept.n) or 0) > n)) then
			local out = {}
			for i, r in ipairs(rows) do out[i] = { name = r.name, games = r.games, won = r.won, lost = r.lost } end
			b.months[m] = { n = n, at = Now(), rows = out }
		end
	end
end

-- (1.2.4) A month's list: the one kept (months) when it read more games than this client holds of
-- that month now (they went past HALVES_DAYS), else Best's: { month, rows (each { name, key, games,
-- won, lost, place }), champion (its first, with a win; nil), kept (true: the list kept) }. A name
-- moderation hides or this player blocked is left out of a kept list too, as Best leaves it out.
function FT.Month(month)
	month = tonumber(month)
	if not month then return nil end
	local b = RankStore(false)
	local kept = b and b.months[month]
	local rows, n
	if type(kept) == "table" and (kept.sealed or (month < MonthOf(Now() - FT.HALVES_DAYS * 86400)
		and not (ns.Records and not ns.Records.missing and ns.Records.ContainsMonth and ns.Records.ContainsMonth("b", month)))) then
		-- (a month past what the store holds: its games are gone, its kept list is all there is. The
		-- review: Best read every game held again for each month kept, and the months add up for good.)
		rows, n = {}, 0
	else
		rows, n = FT.Best("L", { month = month })
	end
	local out = { month = month, rows = rows or {} }
	-- (1.2.4: a month the author's seal closed, Records.lua: its totals, whatever this client holds)
	if type(kept) == "table" and type(kept.rows) == "table" and (kept.sealed or (tonumber(kept.n) or 0) > (tonumber(n) or 0)) then
		out.rows, out.kept, out.sealed = {}, true, kept.sealed == true or nil
		for _, r in ipairs(kept.rows) do
			if type(r) == "table" and type(r.name) == "string" and not HV.RankHides(r.name) then
				out.rows[#out.rows + 1] = { name = r.name, key = Low(r.name), games = tonumber(r.games) or 0, won = tonumber(r.won) or 0,
					lost = tonumber(r.lost) or 0, place = #out.rows + 1 }
			end
		end
	end
	local first = out.rows[1]
	out.champion = first and (tonumber(first.won) or 0) >= 1 and first.name or nil
	return out
end
-- (1.2.4) The months this client holds a list of (kept, or games of), the newest first.
function FT.Months()
	local b = RankStore(false)
	if not b then return {} end
	local set = {}
	for m in pairs(b.months) do if type(m) == "number" then set[m] = true end end
	for _, s in pairs(b.done) do
		local r = HV.ReadDone(s)
		if r then set[MonthOf(r.t)] = true end
	end
	local out = {}
	for m in pairs(set) do out[#out + 1] = m end
	table.sort(out, function(x, y) return x > y end)
	return out
end
-- (1.2.4) A player's Bones for his profile (PagesPlayer's stats.bones): the games and wins every
-- month's list here counts for him (FT.Month: the ranking's own count, caps and all), or nil.
-- (Every player's at once, each month read once, kept until Best's would be worked out again: a
-- portrait on each row of a list asks for its player's card, and the months kept add up for good.)
HV.stats = {} -- { ctx, totals = { [name, lower case] = { games, won } } }
function FT.PlayerStats(name)
	local k = Low(name)
	if not k then return nil end
	local ctx = HV.Context()
	if HV.stats.ctx ~= ctx or type(HV.stats.totals) ~= "table" then
		local totals = {}
		for _, m in ipairs(FT.Months()) do
			local x = FT.Month(m)
			for _, r in ipairs(x and x.rows or {}) do
				local rk = r.key or Low(r.name)
				if rk then
					local t = totals[rk]
					if not t then t = { games = 0, won = 0 } totals[rk] = t end
					t.games, t.won = t.games + (tonumber(r.games) or 0), t.won + (tonumber(r.won) or 0)
				end
			end
		end
		HV.stats = { ctx = ctx, totals = totals }
	end
	local t = HV.stats.totals[k]
	return t and t.games > 0 and { games = t.games, won = t.won } or nil
end

-- After a login: this player's own games of this month and the last said again on the channel (the
-- low lane), both halves (his and the other's signed one), the newest first, HALVES_REPEAT games
-- at most. Each game is said again at as many later logins as HALVES_REPEAT_GAPS has, each at
-- least that long after its last telling (the first an hour after its end): a /reload or a login
-- soon after the game spends nothing, and the members away then hear it at a later one. A repeat
-- counts once it went (the send's done). Returns how many games went.
HV.repeating = {} -- [key] = true while its repeat waits to go
function FT.RepeatHalves()
	local b = RankStore(false)
	if not b then return 0 end
	local now = Now()
	local month = MonthOf(now)
	local list = {}
	for key, o in pairs(b.own) do
		local n = type(o) == "table" and (tonumber(o.n) or 0) or nil
		local gap = n and FT.HALVES_REPEAT_GAPS[n + 1]
		if gap and type(o.mine) == "string" and not HV.repeating[key] and MonthOf(tonumber(o.t) or 0) >= month - 1
			and now - (tonumber(o.last) or tonumber(o.t) or 0) >= gap then
			list[#list + 1] = { key = key, o = o }
		end
	end
	table.sort(list, function(x, y)
		local tx, ty = tonumber(x.o.t) or 0, tonumber(y.o.t) or 0
		if tx ~= ty then return tx > ty end
		return x.key > y.key
	end)
	local sent = 0
	for _, x in ipairs(list) do
		if sent >= FT.HALVES_REPEAT then break end
		local o, key = x.o, x.key
		local id = key:match("^([^:]+):")
		local mode = o.mode == "L" and "L" or "T"
		local lane = A().Lane(mode, true)
		local ok = lane and A().Send("KN", mode, o.mine, { dist = lane, low = true, key = "farklen " .. id .. " mine", done = function(went)
			HV.repeating[key] = nil
			if went then o.n, o.last = (tonumber(o.n) or 0) + 1, Now() end
		end })
		if ok == true then
			HV.repeating[key] = true
			sent = sent + 1
			if type(o.theirs) == "string" then A().Send("KN", mode, o.theirs, { dist = lane, low = true, key = "farklen " .. id .. " theirs" }) end
		end
	end
	HV.AskHalves(b, now)
	return sent
end

-- (1.2.4) This player's games whose other half never came here (the other's client lost it at the
-- end: a crash, a whisper given up), this month's and the last: the other player asked for it by a
-- must-deliver whisper (KN "h": the game's id, seats and target, nothing else), HALVES_REPEAT at
-- most a login, each at as many logins as HALVES_ASKS, HALVES_ASK_GAP apart (an ask counts once it
-- went). His client answers with his own signed half (HV.Answer). The number asked.
HV.asking, HV.answered = {}, {}
function HV.AskHalves(b, now)
	local month = MonthOf(now)
	local n = 0
	for key, o in pairs(b.own) do
		if n >= FT.HALVES_REPEAT then break end
		if type(o) == "table" and type(o.mine) == "string" and type(o.theirs) ~= "string" and not HV.asking[key]
			and (tonumber(o.asks) or 0) < FT.HALVES_ASKS and MonthOf(tonumber(o.t) or 0) >= month - 1
			and now - (tonumber(o.askedAt) or tonumber(o.t) or 0) >= FT.HALVES_ASK_GAP then
			local f = Split(o.mine)
			local seat, p1, p2 = tonumber(f[16] or ""), A().Name(f[2] or ""), A().Name(f[3] or "")
			local other = seat == 1 and p2 or (seat == 2 and p1) or nil
			if type(f[1]) == "string" and #f[1] <= 16 and f[1]:find("^K[0-9a-z]+$") and p1 and p2 and other then
				local mode = o.mode == "L" and "L" or "T"
				local ok = A().Send("KN", mode, ("%s~%s~%s~-~%s~-~h"):format(f[1], p1, p2, f[5] or "5"), { to = other, must = true,
					key = "farklen " .. f[1] .. " ask", done = function(went)
						HV.asking[key] = nil
						if went then o.asks, o.askedAt = (tonumber(o.asks) or 0) + 1, Now() end
					end })
				if ok == true then
					HV.asking[key] = true
					n = n + 1
				end
			end
		end
	end
	return n
end
-- (1.2.4) The other player of this player's own game asks for his half (KN "h", whispered): his
-- own signed one, kept with the game (own.mine), back to him alone, once a session per game.
function HV.Answer(sender, id, p1, p2)
	local b = RankStore(false)
	local key = HalfKey(id, p1, p2)
	local o = b and b.own[key]
	if type(o) ~= "table" or type(o.mine) ~= "string" or HV.answered[key] then return false end
	local f = Split(o.mine)
	local seat = tonumber(f[16] or "")
	local other = seat == 1 and f[3] or (seat == 2 and f[2]) or nil
	if not other or not Same(sender, other) then return false end
	HV.answered[key] = true
	return A().Send("KN", o.mode == "L" and "L" or "T", o.mine, { to = sender, must = true, key = "farklen " .. id .. " answer" }) == true
end

-- Pruned at login and while involved: transcripts past 7 days, history past its cap.
function FT.Prune()
	local b = RankStore(false)
	if b then PruneHalves(b) end
	for _, mode in ipairs({ "L", "T" }) do
		local h = Heavy(mode)
		if h then
			local cut = Now() - FT.TX_DAYS * 86400
			for id, x in pairs(h.tx) do if type(x) ~= "table" or (tonumber(x.t) or 0) < cut then h.tx[id] = nil end end
			while #h.hist > FT.HIST_MAX do table.remove(h.hist) end
		end
		-- (the public tables' events kept for their crowd's markets, KeepNotice)
		local m = Peek(mode)
		if m and type(m.kept) == "table" then
			local cut = Now() - FT.KEEP_NOTICE
			for id, k in pairs(m.kept) do if type(k) ~= "table" or (tonumber(k.at) or 0) < cut then m.kept[id] = nil end end
		end
	end
end

---------------------------------------------------------------------------
-- The live record, kept so a /reload finds its table (the design); on the beta it is gone at login,
-- and the table is found again from the next message about it. (1.2.3: with each player's yes or no
-- to watchers, spec: without it a reloaded player stopped announcing his table, ignored a watcher's
-- ask, and his Play again opened the next table closed to watchers for both players; and with
-- when the game began, its length in the games' ledger and the ranking's halves.)
---------------------------------------------------------------------------

local RECORD = { "id", "mode", "role", "host", "guest", "arbiter", "kind", "stake", "cur", "target", "secs", "hic", "hiccupRule", "salt",
	"state", "created", "inn", "camp", "campfire", "spot", "first", "crowd", "crowdOpen", "crowdLock", "noWatch", "bankRolls", "began", "free" }
-- (1.2.4) A free game of a release (in T while the live switch is off: FreeOffer, so it may count)
-- keeps its record in the live realm's store, never the rehearsals' (arenaTest), which a rehearsal's
-- word or `test clear` empties mid-game; the other store's record of the table goes.
local function Save(t)
	if t.role == "watch" or t.role == "practice" then return end
	local where = (t.mode == "T" and FreeOffer(t)) and "L" or t.mode
	local m = Mine(where)
	if not m then return end
	for _, other in ipairs({ "L", "T" }) do
		local o = other ~= where and Peek(other) or nil
		if o and t.role == "arbiter" and type(o.arb) == "table" then o.arb[t.id] = nil
		elseif o and t.role ~= "arbiter" and type(o.live) == "table" and o.live.id == t.id then o.live = nil end
	end
	local rec
	if LIVE[t.state] then
		rec = {}
		for _, k in ipairs(RECORD) do rec[k] = t[k] end
		rec.src = { t.src[1], t.src[2] }
		local spec = type(t.spec) == "table" and t.spec or {}
		rec.spec = { spec[1] == true, spec[2] == true }
		rec.events = t.game and t.game.events or nil
	end
	if t.role == "arbiter" then m.arb[t.id] = rec else m.live = rec end
end

---------------------------------------------------------------------------
-- The game: the agreed fields, the head line, applying what was witnessed
---------------------------------------------------------------------------

-- The agreed fields in the head line (the arbiter gets no salt: KO carries none; the salt is in
-- the digest alone, so a spectator cannot recover the stake from KG).
local function HicCode(t) return t.hic and (t.hiccupRule == "bones2" and 2 or 1) or 0 end
local function Terms(t)
	return table.concat({ t.kind, t.cur or "g", tostring(t.stake or 0), t.arbiter and t.arbiter:lower() or "-",
		(t.src[1] or "-") .. (t.src[2] or "-"), tostring(t.secs), tostring(HicCode(t)), t.mode }, ";")
end
local function Fields(t)
	return { target = t.target, players = { t.players[1], t.players[2] }, id = t.id, terms = Terms(t), hiccup = t.hic == true,
		first = t.first, hiccupRule = t.hic and t.hiccupRule or nil }
end
local function Digest(t)
	return A().Hash36(table.concat({ t.salt or "", t.id, Terms(t), t.host:lower(), t.guest:lower(), tostring(t.target) }, "|"), 8)
end
FT.Digest = Digest

local function NewGame(t)
	local g, why = R().New(Fields(t))
	if not g then ns.Log("farkle %s: no game (%s)", t.id, tostring(why)) return nil end
	t.game, t.own = g, g
	t.began = t.began or Now() -- (the games' ledger's length)
	return g
end

local Progress, Finished, SendState, SendNotice -- (below)

-- The events one Apply wrote (a decision can take the lines held behind it, a turn's end the next
-- player's lines ahead of it), each as the board animates it: its code, seat, dice (a roll), the
-- dice set aside and their points (a decision: positions of the roll before it), its level; and
-- after the last, what the turn waits for.
local function Written(t, from, how, before)
	local g = t.game
	local dice = before.dice
	local out = {}
	for i = from + 1, g.step do
		-- The rules canonically order an opening pair once both server lines are
		-- known. Animate the line just observed, not the reordered pair's tail.
		local code = i == from + 1 and before.opening or g.events[i]
		local ev = R().Event(code) or {}
		local info = { t = ev.t, seat = ev.p, code = code, step = i, how = i == from + 1 and how or "held", relayed = ev.relayed or nil, lvl = ev.lvl }
		if ev.t == "R" then
			info.k, info.value = ev.k, ev.value
			info.dice = R().Decode(ev.value, ev.k)
			info.farkle = info.dice and R().Farkle(info.dice) or nil
			-- Eligibility was captured before a bust hands the turn to the other seat.
			if ev.p == before.rollSeat and ev.value == before.rollValue and ev.k == before.rollK then
				info.hicAttempted = info.farkle and before.hicEligible or nil
				before.hicEligible = nil
			end
			dice = info.dice
		elseif ev.t == "K" then
			local _, list = R().Mask(ev.mask)
			info.mask, info.act = list, ev.act
			local faces = {}
			for j, p in ipairs(list or {}) do faces[j] = dice and dice[p] end
			info.faces, info.points = faces, R().Score(faces)
		elseif ev.t == "H" or ev.t == "O" then
			info.value = ev.value
		end
		-- the turn this event ended (the board's row line: "Banked 450", "Bones: lost 300")
		local last = g.last
		if last and last.who == ev.p then
			if ev.t == "K" and ev.act == "b" and last.how == "bank" then info.banked = last.points end
			if (ev.t == "R" or ev.t == "H") and last.how == "farkle" then info.lost = last.lost end
		end
		out[#out + 1] = info
	end
	local last = out[#out]
	if last then
		last.last = true
		last.hiccupDue = g.turn.phase == "hiccup"
		last.turnPoints, last.current, last.over = g.turn.points, g.current, g.over
		last.scores = { g.scores[1], g.scores[2] }
		last.lastTurn = g.last
		last.hot = g.turn.hot
		for seat = 1, 2 do
			if g.shakes and before.shakes and g.shakes[seat] > before.shakes[seat] then last.shaken = seat end
		end
	end
	return out
end

-- Hands one event to the rules for both records (the table's and, where they are apart, this
-- client's own witnessed one), then moves the table on. how: "seen" (this client witnessed it),
-- "relayed" (a resync), "message" (a decision or claim that came in), "mine" (this client's own
-- decision or claim), "house" (practice).
local function Apply(t, ev, how)
	local g = t.game
	if not g or g.over then return nil, "over" end
	local before = { dice = g.turn.dice, step = g.step, shakes = g.shakes and { g.shakes[1], g.shakes[2] } }
	if ev.t == "O" then before.opening = R().Code(ev) end
	if ev.t == "R" and ev.p == g.current and g.hiccupRule == "bones2" then
		before.rollSeat, before.rollValue, before.rollK = ev.p, ev.value, ev.k
		local _, chance, left = R().Level(g, ev.p)
		before.hicEligible = chance and chance > 0 and left and left > 0 or nil
	end
	local ok, note = R().Apply(g, ev)
	if t.own ~= g and t.own and not t.own.over then R().Apply(t.own, ev) end
	if not ok then return nil, note end
	-- a line held (W3, or the next player's line ahead of the turn's end) shows once it is taken
	for _, info in ipairs(Written(t, before.step, how, before)) do Emit(t, info) end
	if ev.t == "K" or ev.t == "T" or ev.t == "A" or ev.t == "F" then t.lastDecisionAt = Clock() end
	ResetClock(t)
	Save(t)
	Progress(t)
	return ok, note
end
FT.Apply = function(id, ev, how)
	local t = tables[id]
	if not t then return nil, "table" end
	return Apply(t, ev, how)
end

---------------------------------------------------------------------------
-- Witnessing: the server's roll lines (the design), each client its own
---------------------------------------------------------------------------

local selftest -- { at } while /oly farkle test waits for the line
local lastSelfTest

-- A roll line of a player of this table, as this client saw it.
local function Witness(t, seat, value, lo, hi)
	local g = t.game
	if not g or g.over then return end
	local ev
	local k = R().RangeK(lo, hi)
	if k then
		ev = { t = "R", p = seat, k = k, value = value }
	elseif lo == 1 and hi == R().OPENING then
		if g.open then ev = { t = "O", p = seat, value = value }
		elseif g.hiccup and g.hiccupRule ~= "bones2" then ev = { t = "H", p = seat, value = value }
		else return end
	else
		return
	end
	-- A smaller roll after our bank can reach the witness before the bank (W4).
	-- Remember only our actual server lines, so a relay cannot invent that exception.
	if seat == t.seat and ev.t == "R" and ev.k < R().DICE and g.current ~= seat then
		local ordinal, last = 0, nil
		for _, code in ipairs(g.events) do
			local choice = R().Event(code)
			if choice and choice.t == "K" and choice.p == seat then ordinal, last = ordinal + 1, choice end
		end
		if last and last.act == "b" then
			t.bankRolls = t.bankRolls or {}
			t.bankRolls[ordinal] = R().Code(ev)
			for index in pairs(t.bankRolls) do if index <= ordinal - 32 then t.bankRolls[index] = nil end end
			Save(t) -- the rejected server line still proves W4 after a reload
		end
	end
	local since = t.lastDecisionAt and (Clock() - t.lastDecisionAt) or nil
	local ok, note = Apply(t, ev, "seen")
	FT.Note("%s %s %d-%d %d: %s%s", t.id, t.players[seat] or "?", lo, hi, value, ok and (note or "ok") or ("refused " .. tostring(note)),
		since and (" %.1fs after the last decision"):format(since) or "")
	if seat == t.seat then
		t.rolling = nil
		if not ok and note ~= "held" then Changed(t) end
	end
end

-- The drunk line of a player (the design): this client's news of the other player since its own last
-- decision, its own "You feel", or (the arbiter) his view of either seat.
local function Drunk(t, who, level)
	if not t.hic or not t.game or not PLAYING[t.state] then return end
	local now = Clock()
	if who == "self" then
		if not t.seat then return end
		t.self = { level = level, at = now }
		if t.role == "practice" then t.news = { level = level, at = now } end
		Emit(t, { t = "drunk", seat = t.seat, level = level, self = true })
		return
	end
	local seat = SeatOf(t, who)
	if not seat then return end
	if t.role == "arbiter" then
		t.views = t.views or {}
		local was = t.views[seat] and t.views[seat].level
		t.views[seat] = { level = level, at = now }
		if was ~= level and t.floorOn and t.floorOn[seat] then FT.Floor(t, seat, level) end
	elseif seat ~= t.seat then
		t.news = { level = level, at = now }
	end
	Emit(t, { t = "drunk", seat = seat, level = level })
end

OnSystem = function(text)
	if type(text) ~= "string" then return end
	local any = selftest ~= nil
	for _, t in pairs(tables) do if t.game and not t.game.over then any = true break end end
	if not any then return end
	if Secret(text) or A().Lockdown() then
		for _, t in pairs(tables) do if t.game and not t.game.over and not t.blind then t.blind = true Changed(t) end end
		return
	end
	local AP = ns.ArenaParse
	local name, value, lo, hi = AP.Roll(text)
	if name then
		if selftest and LineIs(name, Me()) and lo == 1 and hi == 46656 then FT.SelfTestLine(name, value, lo, hi) end
		for _, t in pairs(tables) do
			if t.game and not t.game.over and t.role ~= "watch" then
				for seat = 1, 2 do
					local p = t.players[seat]
					if p and (t.role ~= "practice" or seat == 1) and LineIs(name, p) then
						t.blind = nil
						Witness(t, seat, value, lo, hi)
					end
				end
			end
		end
		return
	end
	local who, level = FT.ReadDrunk(text)
	if who then
		for _, t in pairs(tables) do Drunk(t, who, level) end
	end
end
FT.OnSystem = function(text) return OnSystem(text) end

---------------------------------------------------------------------------
-- Moving a table on: the handshake, stakes, pending messages, the end
---------------------------------------------------------------------------

local TryPending, Resync -- (below)

-- This client's view of the other seat's drunk level to write into its next decision (the design): only
-- when it differs from the recorded one; nothing seen, nothing sent.
local function NewsFor(t, seat)
	local g = t.game
	if not t.hic or not g or not t.news then return nil end
	local lvl = t.news.level
	if lvl == g.level[3 - seat] then return nil end
	return lvl
end

-- The direct mode's dispute flag (the design): a turn of this player that began below his own "You feel"
-- level, where the line was at least FLOOR_AGE older than the opponent's last decision and no
-- /reload or tavern pause of his own came since.
local function TurnBegan(t)
	local g = t.game
	if not t.hic or t.kind ~= "d" or not t.seat or not g or g.current ~= t.seat then return end
	local key = g.turns[t.seat]
	if t.flagged == key then return end
	t.flagged = key
	local s = t.self
	if not s or not t.lastDecisionAt or s.at > t.lastDecisionAt - FT.FLOOR_AGE then return end
	if t.pausedSince and s.at < t.pausedSince then return end
	local lvl = R().Level(g, t.seat)
	if lvl and lvl < s.level then
		t.ld = (t.ld or 0) + 1
		t.lower = true
		Emit(t, { t = "lower", seat = t.seat, level = s.level, recorded = lvl })
	end
end

Progress = function(t)
	local g = t.game
	if not g then return end
	-- the opening decided: this client's KY (the design)
	if t.state == "open" and not g.open and not t.sentKY then
		t.sentKY = true
		t.openStep = g.step
		t.kyAt = Clock()
		if t.role ~= "practice" then SendAll(t, "KY", ("%s~o~%s"):format(t.id, R().ChainAt(g, g.step)), { urgent = true }) end
		t.kys = t.kys or {}
		t.kys[Me():lower()] = R().ChainAt(g, g.step)
	end
	if t.state == "open" and t.sentKY then
		local all = true
		for _, name in ipairs(Others(t)) do if not t.kys[Full(name):lower()] then all = false end end
		if all then
			for name, chain in pairs(t.kys) do
				if chain ~= R().ChainAt(g, t.openStep) then
					t.state = "aborted"
					t.why = "chain"
					Say(t, "FARKLE_LOG_ABORT_CHAIN", ns.DisplayName(name))
					Finished(t)
					return
				end
			end
			FT.StakesStep(t)
		end
	end
	if g.over and PLAYING[t.state] then
		t.state = "end"
		return Finished(t)
	end
	if t.state == "play" then
		TurnBegan(t)
		if TryPending then TryPending(t) end
		if SendState then SendState(t) end
		if t.role == "practice" then FT.PracticeStep(t) end
	end
	Changed(t)
end

---------------------------------------------------------------------------
-- Stakes (the design): none (practice, direct o/o, a rehearsal),
-- held by the arbiter (t: the parties trade him), or in the wallet (w: an FK market the arbiter
-- opens, each player backs his own seat, the bank holds).
---------------------------------------------------------------------------

local function Staked(t) return (t.stake or 0) > 0 end
-- The guild's fee on a direct game: the rate of the money won, the loser's stake (the design,
-- ArenaMath.Direct), rounded down to the copper.
function FT.DirectFee(copper)
	local M = ns.ArenaMath
	local d = M and M.Direct and M.Direct(copper, copper, { feeBp = ns.ArenaRoles.Settings().feeBp })
	return d and d.guildFee or 0
end
local function Real(t) return Staked(t) and A().Counts(t.mode) end
-- Stakes someone holds before the first throw: real ones, traded to the arbiter (t) or held from
-- the wallets (w). A rehearsal's (not Real) are never traded, nor a direct table's.
local function Holds(t) return Real(t) and (t.src[1] == "t" or t.src[1] == "w") end
local function Ref(t) return "F" .. t.id end
local function GK(name)
	local unit = UnitOf(name)
	local guid = unit and UnitGUID and UnitGUID(unit)
	if Secret(guid) then return nil end
	return guid and A().GK(guid) or nil
end

local function Play(t)
	t.state = "play"
	t.stakesAt = nil
	ResetClock(t)
	Save(t)
	Changed(t)
	TurnBegan(t)
end

-- The crowd's bets (2026-10-04): the winner market a public arbiter opens at a table whose host
-- let the crowd bet (KO's and KG's crowd), never beside the wallet's stakes. Its lock holds the
-- game: the arbiter's KH waits for it, and every client of the table waits for his KH.
local function CrowdAllowed(t)
	return t.crowd == true and t.arbiter ~= nil and t.src[1] ~= "w" and ns.ArenaRoles.IsPublicArbiter(t.arbiter, t.mode) == true
end
FT.CrowdAllowed = function(id) local t = tables[id] return t ~= nil and CrowdAllowed(t) end
-- On the arbiter's client, once, as the table opens: true when the market went out.
function FT.OpenCrowd(t)
	if t.role ~= "arbiter" or not t.crowd or t.crowdOpen ~= nil then return t.crowdOpen == true end
	if not CrowdAllowed(t) then
		t.crowdOpen, t.crowdWhy = false, "crowd"
		return false
	end
	local lockAt = Now() + A().OpenMin(true)
	local ok, why = Call("Markets", "Open", t.id, { markets = { { type = "MW" } }, mode = t.mode, lockAt = lockAt })
	t.crowdOpen = ok == true
	t.crowdLock = t.crowdOpen and lockAt or nil
	t.crowdWhy = not t.crowdOpen and tostring(why or "markets") or nil
	Save(t)
	return t.crowdOpen
end
-- When the crowd's bets close: the arbiter's own lock, else the sheet this client heard; nil when
-- there are none.
local function CrowdLock(t)
	if t.crowdLock then return t.crowdLock end
	if not t.crowd or t.role == "arbiter" then return nil end
	local sheet = Call("Markets", "Sheet", t.id)
	return type(sheet) == "table" and tonumber(sheet.lockAt) or nil
end
-- The crowd's market ends with the table: its winner, or void (X: a void game, W: none played).
local function CrowdResult(t, side)
	if t.role ~= "arbiter" or t.crowdOpen ~= true or t.crowdDone then return end
	t.crowdDone = true
	if side == "1" or side == "2" then Call("Markets", "Declare", t.id, { [1] = side })
	else Call("Markets", "Void", t.id, "*", side == "v" and "X" or "W") end
end

function FT.StakesStep(t)
	if t.state ~= "open" then return end
	-- (a crowd table waits for its arbiter's KH: the bets close before the first throw)
	local crowd = t.crowd == true and t.arbiter ~= nil
	if not crowd and not Holds(t) then return Play(t) end
	t.state = "stakes"
	t.stakesAt = Clock()
	-- (the wait grows by the bets' window: the lock this client knows, else, on a player's client
	-- that has not heard the sheet yet, the longest the arbiter may have given it at KG)
	local lock = CrowdLock(t)
	local window = lock and max(0, lock - Now()) or 0
	if crowd and t.role ~= "arbiter" then window = max(window, A().OpenMin(true)) end
	t.stakesWait = FT.STAKES_WAIT + window
	if Real(t) and t.src[1] == "w" then FT.WalletStakes(t) end
	Save(t)
	Changed(t)
end

-- The wallet's stakes: the arbiter opens the table's FK market (whispered to the players and the
-- bank, the design); each player backs his own seat with the stake; everyone reads the book.
function FT.WalletStakes(t)
	if t.role == "arbiter" and not t.marketOpen then
		t.marketOpen = true
		Call("Markets", "Open", t.id, { kind = "FK", private = true, parties = { t.host, t.guest }, stake = { t.stake, t.stake },
			cur = t.cur, mode = t.mode, lockAt = Now() + FT.STAKES_WAIT, markets = { { idx = 1, type = "FK" } } })
	end
	if t.seat and not t.bet then
		t.bet = true
		Call("Markets", "Bet", t.id, 1, tostring(t.seat), floor(t.stake / 100))
	end
end

-- Held stakes as the stakeholder shows them: { [1] = copper, [2] = copper }.
local function Holdings(t)
	if t.src[1] == "t" then
		local held = Call("Stakes", "Held", t.id)
		if type(held) == "table" then return { tonumber(held.A) or 0, tonumber(held.B) or 0 } end
		return { 0, 0 }
	end
	local view = Call("Markets", "View", t.id)
	local out = { 0, 0 }
	local m = type(view) == "table" and type(view.markets) == "table" and view.markets[1]
	for _, o in ipairs(m and m.outcomes or {}) do
		local seat = tonumber(o.o)
		if seat == 1 or seat == 2 then out[seat] = tonumber(o.pool) or 0 end
	end
	return out
end
FT.Holdings = function(id) local t = tables[id] return t and Holdings(t) or { 0, 0 } end

local function StakesTick(t)
	if t.state ~= "stakes" then return end
	-- (a crowd table whose stakes nobody holds, a rehearsal's: only the bets' lock is waited for)
	local both = true
	if Holds(t) then
		local h = Holdings(t)
		t.held = { h[1] >= t.stake, h[2] >= t.stake }
		both = t.held[1] and t.held[2]
	end
	-- (the crowd's bets still open: the arbiter's KH waits for their lock)
	local lock = t.role == "arbiter" and CrowdLock(t) or nil
	local betting = lock ~= nil and Now() < lock
	-- the arbiter says it (KH); a wallet's holds every client also reads itself in the book: a KH
	-- alone never convinces it (the design). Stakes traded to the arbiter are in his book only.
	if both and t.role == "arbiter" and not t.sentKH and not betting then
		t.sentKH = true
		SendAll(t, "KH", ("%s~1~1~%s"):format(t.id, t.src[1]), { urgent = true })
	end
	if t.role == "arbiter" and both and not betting then return Play(t) end
	if t.role ~= "arbiter" and t.kh and t.kh[1] and t.kh[2] and (t.src[1] == "t" or both) then return Play(t) end
	if Clock() - (t.stakesAt or Clock()) > (t.stakesWait or FT.STAKES_WAIT) then
		t.state = "aborted"
		t.why = "stakes"
		Say(t, "FARKLE_LOG_STAKES_LATE")
		if t.role == "arbiter" and Real(t) then
			if t.src[1] == "t" then Call("Stakes", "Result", t.id, "V") elseif t.src[1] == "w" then Call("Markets", "Void", t.id, "*", "S") end
		end
		Finished(t)
	end
end

---------------------------------------------------------------------------
-- The end: KE, the agreement, the settlement (the design)
---------------------------------------------------------------------------

local function Result(g)
	if not g or not g.over then return "x" end
	if g.reason == "void" or not g.winner then return "v" end
	return tostring(g.winner)
end
local function KEBody(t)
	local g = t.own or t.game
	local body = ("%s~%s~%s~%s~%s~%s~%s"):format(t.id, Result(g), B36(g.scores[1]), B36(g.scores[2]), B36(g.step), R().Hash(g),
		B36(t.kind == "d" and (t.ld or 0) or 0))
	-- a staked direct game's KE carries the player's signed result (the design)
	if t.kind == "d" and Real(t) and t.seat and g.over and g.winner then
		local sig = Call("Debts", "SignResult", t.id, 1, GK(t.players[g.winner]) or "-", GK(t.players[3 - g.winner]) or "-")
		if type(sig) == "string" and not sig:find("~", 1, true) then body = body .. "~" .. sig end
	end
	return body
end

-- The KEs heard for a table (this client's own too): the agreement a held or wallet stake needs
-- (the design): the arbiter's KE and at least one player's, the same record.
function FT.Agreement(id)
	local t = tables[id]
	if not t or not t.ke then return nil end
	local arb = t.arbiter and t.ke[Full(t.arbiter):lower()]
	local out = { at = arb and arb.at or nil }
	if not t.arbiter then
		if not t.host or not t.guest then return out end
		local a, b = t.ke[Full(t.host):lower()], t.ke[Full(t.guest):lower()]
		out.agreed = a ~= nil and b ~= nil and a.hash == b.hash and a.res == b.res
		out.result = out.agreed and a.res or nil
		return out
	end
	if not arb then return out end
	for _, p in ipairs({ t.host, t.guest }) do
		local k = t.ke[Full(p):lower()]
		if k and k.hash == arb.hash and k.res == arb.res then out.agreed, out.result = true, arb.res end
	end
	out.arbiter = arb.res
	return out
end

local Settle -- (below)

Finished = function(t)
	local g = t.game
	if t.role == "practice" then
		if t.closed then return end
		t.closed = true
		Keep(t)
		if t.inn and select(2, FT.Innkeeper()) == t.inn and not A().Sim() and g and g.over and g.winner and (g.reason == "target" or g.reason == "cap") and not FT.TrainingComplete() then
			FT.Opts().innkeeperLearned = true
			ns.Fire("BONES_LEARNED", t.guest)
		end
		Involve(t, false)
		Changed(t, "end")
		return
	end
	-- Progress returns here before its ordinary SendState. Tell existing watchers and the
	-- notice lane the game is over before settlement stops the relay's involvement. (1.2.3: a game
	-- that counts ends with this player's half of it, the ranking's word: the notice lane carries
	-- it, whether or not the table let watchers in.)
	if t.state == "end" and g and g.over then
		if t.half == nil then t.half = OwnHalf(t) or false end
		if SendState then SendState(t) end
		if SendNotice then SendNotice(t) end
	end
	if t.state == "end" and not t.sentKE and g then
		t.sentKE = true
		local body = KEBody(t)
		t.ke = t.ke or {}
		t.ke[Me():lower()] = { res = Result(t.own or g), hash = R().Hash(t.own or g), at = Clock(), mine = true }
		SendAll(t, "KE", body, { must = true })
		-- the bank settles a wallet table: it hears every KE too
		if t.src[1] == "w" and Real(t) then
			local bank = Call("Markets", "View", t.id)
			local to = type(bank) == "table" and bank.bank
			if type(to) == "string" and to ~= "" then Send(t, "KE", body, to, { must = true }) end
		end
		Keep(t)
		-- (this player's half, kept here and told the other player for sure: his own client counts
		-- the game once both halves agree, whatever the channel lost)
		if t.half and not t.halfSent then
			t.halfSent = true
			TakeHalf(Me(), t.half, true)
			local other = t.seat and t.players[3 - t.seat]
			if other then Send(t, "KN", t.half.body, other, { must = true }) end
		end
		t.endAt = Clock()
		if t.from then Call("ArenaMatch", "Ended", t.from) end
	end
	if t.state ~= "end" then
		-- aborted, declined, expired: nothing to settle (the crowd's bets go back: none played)
		if t.from then Call("ArenaMatch", "Ended", t.from) end
		CrowdResult(t, "x")
		t.closed = true
	end
	Save(t)
	Involve(t, LIVE[t.state] == true)
	Changed(t)
	if t.state == "end" then Settle(t) end
end

-- The settlement, once it may go (the design). Direct o/o: the loser's own record makes
-- his obligation (Stakes.Direct); the winner fills the fee from the gold he receives. Held (t):
-- the arbiter's lines only when his KE agrees with a player's, after the grace. Wallet (w): the
-- arbiter declares the FK market then; the bank checks the same agreement (Agreement).
Settle = function(t)
	if t.settled or t.state ~= "end" then return end
	local g = t.game
	-- (the arbiter of a crowd's market settles it as he would stakes: the same agreement and grace)
	local crowd = t.role == "arbiter" and t.crowdOpen == true and not t.crowdDone
	if (not Real(t) and not crowd) or not g.over then
		t.settled = true
		t.state = "closed"
		Save(t)
		Involve(t, false)
		Changed(t)
		return
	end
	local winner = g.winner
	if t.kind == "d" then
		t.settled = true
		t.lines = {}
		if winner and t.seat then
			if winner ~= t.seat then
				Call("Stakes", "Direct", { id = Ref(t), loser = Me(), winner = t.players[winner], copper = t.stake, kind = "farkle" })
				t.lines[#t.lines + 1] = { kind = "pay", to = t.players[winner], copper = t.stake, action = "Pay" }
			else
				t.lines[#t.lines + 1] = { kind = "fee", copper = FT.DirectFee(t.stake), action = "PayFee", when = "received" }
			end
		end
		local ag = FT.Agreement(t.id)
		if ag and ag.agreed == false and t.ke[Full(t.players[3 - (t.seat or 1)]):lower()] then
			Call("Debts", "Disputed", Ref(t), { kind = "farkle", table = t.id, mine = R().Hash(t.own or g) })
		end
		Changed(t)
		return
	end
	-- held or wallet: the arbiter's KE and a player's must agree, then the grace
	local ag = FT.Agreement(t.id)
	if not ag or not ag.agreed then
		if ag and ag.arbiter and t.role ~= "arbiter" then t.holdWhy = "disagree" end
		return
	end
	if Clock() - (ag.at or Clock()) < FT.GRACE then t.graceUntil = (ag.at or Clock()) + FT.GRACE return end
	t.settled = true
	local side = ag.result == "1" and "A" or (ag.result == "2" and "B" or "V")
	if t.role == "arbiter" then
		if Real(t) and t.src[1] == "t" then
			Call("Stakes", "Result", t.id, side)
			t.lines = Call("Stakes", "Lines", t.id)
		elseif Real(t) then
			-- (a void game voids the FK market, code X: Declare takes a winner, a bare "V" was no
			-- result at all and left the stakes locked)
			if side == "V" then Call("Markets", "Void", t.id, "*", "X") else Call("Markets", "Declare", t.id, { [1] = ag.result }) end
		end
		CrowdResult(t, ag.result)
	end
	t.state = "closed"
	Save(t)
	Involve(t, false)
	Changed(t)
end

---------------------------------------------------------------------------
-- Resync (KQ, KR) and the divergence rule (the design)
---------------------------------------------------------------------------

-- The seat whose act a step records: the seat to act before it (the roller of an opening roll, the
-- conceding seat), the arbiter for a floor.
local function ActorAt(t, step, code)
	local ev = R().Event(code or "")
	if not ev then return nil end
	if ev.t == "L" then return "arbiter" end
	if ev.t == "O" or ev.t == "C" then return ev.p end
	local g = R().Replay(Fields(t), { unpack(t.game.events, 1, step - 1) })
	return g and g.current or ev.p
end

-- A table rebuilt from codes: the lines held in the old one taken again, in the server's order.
local function Rebuild(t, codes, both)
	local old = t.game
	local g, why = R().Replay(Fields(t), codes)
	if not g then ns.Log("farkle %s: rebuild refused (%s)", t.id, tostring(why)) return false end
	local held = {}
	for _, line in ipairs(old.queue or {}) do held[#held + 1] = { line = line, p = old.current } end
	for _, line in ipairs(old.ahead or {}) do held[#held + 1] = { line = line, p = old.current and (3 - old.current) or nil } end
	table.sort(held, function(a, b) return (a.line.seq or 0) < (b.line.seq or 0) end)
	for _, h in ipairs(held) do
		if h.p then R().Apply(g, { t = h.line.t, p = h.p, k = h.line.k, value = h.line.value, relayed = h.line.relayed }) end
	end
	-- the pending floors of the old game stay
	g.pending = old.pending
	t.game = g
	if both then t.own = g end
	ResetClock(t)
	Save(t)
	Emit(t, { t = "rebuild", step = g.step })
	return true
end

-- A KR's codes against this client's own record: a relayed event fills only what this client did
-- not see; one where it wrote its own is compared, never applied over it (the design). A difference is a
-- split; the divergence rule decides who keeps his record (the design):
--   direct: the seat that did NOT act at that step keeps his (his witnessing decides); the actor
--   takes the other's record from there; the dispute is recorded against the actor;
--   an arbiter's table: the arbiter's record stands; a player takes it to play on, but his KE
--   carries his own witnessed record (a player's agreeing KE is his acceptance);
--   a late floor (KL) is no dispute: the arbiter's record is taken whole.
local function TakeRelay(t, from, fromStep, codes)
	local g = t.game
	local mine = g.events
	local split
	for i, code in ipairs(codes) do
		local step = fromStep + i
		local own = mine[step]
		if own then
			if (own:gsub("%*$", "")) ~= (code:gsub("%*$", "")) then split = step break end
		elseif step == g.step + 1 then
			local ev = R().Event(code)
			if not ev then break end
			if ev.t == "R" or ev.t == "O" or ev.t == "H" then ev.relayed = true end
			local ok = Apply(t, ev, "relayed")
			if not ok then split = step break end
			g = t.game
			mine = g.events
		end
	end
	if not split then return true end
	local isArb = t.arbiter and Same(from, t.arbiter)
	local ours = mine[split]
	local actor = ActorAt(t, split, ours)
	local codesFrom = {}
	for i = 1, split - 1 do codesFrom[i] = mine[i] end
	for i = split - fromStep, #codes do codesFrom[#codesFrom + 1] = codes[i] end
	if t.lateFloor and isArb then
		t.lateFloor = nil
		Rebuild(t, codesFrom, true)
		return true
	end
	t.disputed = { step = split, with = from, actor = actor }
	if t.kind == "d" then
		if actor == t.seat then
			-- (recorded here too: the other client may not see the split once this one has
			-- taken its record)
			t.disputedAgainst = Me()
			Call("Debts", "Disputed", Ref(t), { kind = "farkle", table = t.id, against = Full(Me()), step = split, mine = R().Hash(g), self = true })
			Rebuild(t, codesFrom, true)
			Say(t, "FARKLE_LOG_TOOK_RECORD", ns.DisplayName(from))
		else
			t.disputedAgainst = from
			Call("Debts", "Disputed", Ref(t), { kind = "farkle", table = t.id, against = Full(from), step = split, mine = R().Hash(g) })
			Say(t, "FARKLE_LOG_DISPUTE", ns.DisplayName(from))
		end
	elseif isArb and t.role ~= "arbiter" then
		Rebuild(t, codesFrom, false)
		Say(t, "FARKLE_LOG_ARBITER_RECORD")
	end
	Changed(t)
	return false
end

Resync = function(t, to, fromStep)
	local now = Clock()
	t.resync = t.resync or {}
	if t.resync.at and now - t.resync.at < FT.RESYNC_GAP then return false end
	t.resync.at = now
	t.resync.to, t.resync.from = Full(to), fromStep
	FT.Note("%s resync: KQ to %s from step %d", t.id, tostring(to), fromStep)
	return Send(t, "KQ", ("%s~%s"):format(t.id, B36(fromStep)), to, { urgent = true })
end
-- Whom a lagging client asks: the arbiter, else the opponent (the design).
local function Asked(t)
	if t.arbiter and not Same(t.arbiter, Me()) then return t.arbiter end
	return t.seat and t.players[3 - t.seat] or t.host
end

---------------------------------------------------------------------------
-- Decisions and claims that arrive (KK, KT, KL): applied when their step comes (a roll line they
-- follow may still be on its way), a gap resynced, a chain that differs resynced and compared.
---------------------------------------------------------------------------

local function Pend(t, item)
	t.pending = t.pending or {}
	item.at = Clock()
	t.pending[#t.pending + 1] = item
end

local ApplyItem, FloorCheck -- (below)

TryPending = function(t)
	if not t.pending or not t.pending[1] then return end
	local again = true
	while again do
		again = false
		for i, item in ipairs(t.pending) do
			local g = t.game
			if item.notBefore and Clock() < item.notBefore then
				-- (a claim this client's own clock does not agree with yet)
			elseif item.step == g.step or item.kind == "KL" then
				table.remove(t.pending, i)
				ApplyItem(t, item)
				again = true
				break
			elseif item.step < g.step then
				table.remove(t.pending, i)
				again = true
				break
			end
		end
	end
end

local function Wait(t, item)
	Pend(t, item)
	return "waiting"
end

ApplyItem = function(t, item)
	local g = t.game
	if item.awaySeat then
		local since = t.away and t.away[item.awaySeat]
		if not since or not Away(t, item.awaySeat) or Clock() - since < FT.TAVERN_GRACE then return end
	end
	if item.kind == "KL" then
		local ok, why = R().Floor(g, item.seat, item.turn, item.lvl)
		if t.own ~= g and t.own then R().Floor(t.own, item.seat, item.turn, item.lvl) end
		if not ok and why == "late" then
			t.lateFloor = true
			local hand = g.handed or g.step
			Resync(t, t.arbiter, math.max(0, math.min(hand, g.step) - 1))
		end
		Save(t)
		return
	end
	if item.chain ~= R().ChainAt(g, item.step) then
		-- the same step, another record: compare the two (KQ from a little before it)
		return Resync(t, item.from, math.max(0, item.step - 2))
	end
	local ok, note = Apply(t, item.ev, "message")
	if not ok then
		FT.Note("%s %s from %s refused: %s", t.id, item.kind, tostring(item.from), tostring(note))
		if note == "turn" or note == "roll" then Resync(t, item.from, math.max(0, g.step - 1)) end
	elseif item.kind == "KK" and t.role == "arbiter" then
		FloorCheck(t, item.ev.p, item.arrived)
	end
end

-- A decision or claim for a step: now, or waiting for its step.
local function Offer(t, item)
	local g = t.game
	if not g then return end
	if item.step > g.step then return Wait(t, item) end
	if item.step < g.step then
		-- behind us: our record holds more; a different chain at its step, or another event
		-- than ours after it, is a split (compared through a resync)
		local ours = g.events[item.step + 1]
		local code = R().Code(item.ev)
		if item.chain ~= R().ChainAt(g, item.step) or (ours and code and ours:gsub("%*$", "") ~= code) then
			Resync(t, item.from, math.max(0, item.step - 2))
		end
		return
	end
	ApplyItem(t, item)
end

---------------------------------------------------------------------------
-- The clock's work (the one arena ticker, while a table is live)
---------------------------------------------------------------------------

local function Claim(t, kind, seat)
	local g = t.game
	local step = g.step
	local chain = R().ChainAt(g, step)
	local ev
	if kind == "t" then ev = { t = "T", p = seat }
	elseif kind == "a" then ev = { t = "A", p = seat }
	elseif kind == "g" then ev = { t = "C", p = seat }
	elseif kind == "v" then ev = { t = "V" } end
	-- a timeout that is the third in a row is written A by the rules: the claim says so too
	if kind == "t" and g.turn.phase ~= "hiccup" and g.timeouts[seat] + 1 >= R().TIMEOUTS then kind, ev = "a", { t = "A", p = seat } end
	local ok = Apply(t, ev, "mine")
	-- (a void names no seat: the message carries 1, which its receivers read past)
	if ok then SendAll(t, "KT", ("%s~%s~%s~%d~%s~%d"):format(t.id, B36(step), kind, seat or 1, chain, t.inCombat and 1 or 0), { urgent = true }) end
	return ok
end

-- The judge of the clock: the arbiter's client with an arbiter; else the waiting player's.
local function Judge(t, seat)
	if t.role == "practice" or t.role == "watch" then return false end
	if t.arbiter then return t.role == "arbiter" end
	return t.seat ~= nil and t.seat ~= seat
end

local function TavernTick(t)
	if not (t.inn or t.camp) or t.state ~= "play" then return end
	local now = Clock()
	t.away = t.away or {}
	for seat = 1, 2 do
		local away = Away(t, seat)
		if away and not t.away[seat] then
			t.away[seat] = now
			if seat == t.seat then t.pausedSince = now end
			Say(t, "FARKLE_LOG_AWAY", ns.DisplayName(t.players[seat]))
			Emit(t, { t = "away", seat = seat })
		elseif not away and t.away[seat] then
			t.away[seat] = nil
			if seat == t.seat then t.awayWarned = nil end
			Emit(t, { t = "back", seat = seat })
		end
		-- One local warning per departure, even with the board closed. Defer loading the
		-- companion in combat; its countdown still comes from the original departure.
		if seat == t.seat and t.away[seat] and t.awayWarned ~= t.away[seat]
			and not (InCombatLockdown and InCombatLockdown()) then
			if FT.ShowUI("away", t.id) then t.awayWarned = t.away[seat] end
		end
		if t.away[seat] and now - t.away[seat] >= FT.TAVERN_GRACE and Judge(t, seat) and not t.game.over then
			Say(t, "FARKLE_LOG_GONE", ns.DisplayName(t.players[seat]))
			Claim(t, "g", seat)
		end
	end
end

-- The gap rule (the design): each second, a player this client cannot see (UnitIsConnected and
-- UnitIsVisible on his unit) is sober in its news until his next line.
local function GapTick(t)
	-- (practice: the other seat is the House, no unit; the player's own lines are the news there)
	if not t.hic or t.state ~= "play" or t.role == "practice" then return end
	for seat = 1, 2 do
		if seat ~= t.seat then
			local unit = UnitOf(t.players[seat])
			local gone = not unit
			if unit then
				local okC, c = pcall(UnitIsConnected or function() return true end, unit)
				local okV, v = pcall(UnitIsVisible or function() return true end, unit)
				if (okC and not Secret(c) and not c) or (okV and not Secret(v) and not v) then gone = true end
			end
			if gone then
				if t.role == "arbiter" then
					t.views = t.views or {}
					local was = t.views[seat] and t.views[seat].level
					if was ~= 0 then
						t.views[seat] = { level = 0, at = Clock() }
						if t.floorOn and t.floorOn[seat] then FT.Floor(t, seat, 0) end
					end
				elseif not t.news or t.news.level ~= 0 then
					t.news = { level = 0, at = Clock() }
				end
			end
		end
	end
end

local function ClockTick(t)
	local g = t.game
	if t.state ~= "play" or not g or g.over then return end
	ResetClock(t)
	UpdatePause(t)
	local c = t.clock
	if not c or c.pausedAt then return end
	local _, claim = Limits(t)
	if Used(t) >= claim and Judge(t, c.seat) then
		Say(t, c.phase == "hiccup" and "FARKLE_LOG_HIC_MISSED" or "FARKLE_LOG_TIMEOUT", ns.DisplayName(t.players[c.seat]))
		Claim(t, "t", c.seat)
	end
end

local function PendingTick(t)
	if not t.pending or not t.pending[1] then return end
	local now = Clock()
	for _, item in ipairs(t.pending) do
		if now - item.at >= FT.RESYNC_WAIT and item.kind ~= "KL" and not item.notBefore then
			Resync(t, Asked(t), t.game.step)
			break
		end
	end
end

local function InviteTick(t)
	if t.state == "invite" and Clock() - (t.invitedAt or Clock()) > FT.INVITE_TTL then
		t.state = "expired"
		Say(t, t.role == "host" and "FARKLE_LOG_NO_ANSWER" or "FARKLE_LOG_EXPIRED")
		Finished(t)
		return true
	end
	if t.state == "agreed" and Clock() - (t.agreedAt or Clock()) > FT.AGREED_WAIT then
		t.state = "expired"
		t.why = "x"
		Say(t, "FARKLE_LOG_NEVER_OPENED")
		Finished(t)
		return true
	end
	if t.state == "asked" and Clock() - (t.askedAt or Clock()) > FT.INVITE_TTL then
		t.state = "expired"
		Say(t, "FARKLE_LOG_NO_ARBITER")
		Finished(t)
		return true
	end
	if t.state == "open" and t.kyAt and Clock() - t.kyAt > FT.HANDSHAKE then
		local missing
		for _, name in ipairs(Others(t)) do if not t.kys[Full(name):lower()] then missing = name end end
		if missing then
			t.state = "aborted"
			t.why = "handshake"
			Say(t, "FARKLE_LOG_ABORT_ROLLS", ns.DisplayName(missing))
			Finished(t)
			return true
		end
	end
	if t.state == "open" and not t.sentKY and t.openedAt and Clock() - t.openedAt > FT.HANDSHAKE + t.secs then
		local g = t.game
		local missing = g and ((not g.opening[1] and t.players[1]) or (not g.opening[2] and t.players[2])) or t.guest
		t.state = "aborted"
		t.why = "opening"
		Say(t, "FARKLE_LOG_ABORT_ROLLS", ns.DisplayName(missing))
		Finished(t)
		return true
	end
	if t.state == "open" and t.game and t.game.ties >= R().OPENING_TIES then
		t.state = "aborted"
		t.why = "ties"
		Say(t, "FARKLE_LOG_ABORT_TIES")
		Finished(t)
		return true
	end
	return false
end

Tick = function()
	local now = Clock()
	for id, t in pairs(tables) do
		if t.role == "watch" then
			if now - (t.askedAt or 0) >= FT.WATCH_ASK and t.relayer then
				t.askedAt = now
				A().Send("KQ", t.mode or "L", ("%s~0"):format(id), { to = t.relayer })
			end
		elseif LIVE[t.state] then
			-- the host's table opens by itself once the other player (and the arbiter) joined the party
			if t.role == "host" and t.state == "agreed" and t.needGroup and FT.InGroup(t.guest) and (not t.arbiter or FT.InGroup(t.arbiter)) then
				FT.Open(t.id)
			end
			if not InviteTick(t) then
				if t.state == "stakes" then StakesTick(t) end
				TavernTick(t)
				GapTick(t)
				ClockTick(t)
				PendingTick(t)
				TryPending(t)
				if t.klDue then
					for seat, lvl in pairs(t.klDue) do
						if FT.Floor(t, seat, lvl) then t.klDue[seat] = nil end
					end
				end
				if t.state == "end" and not t.settled then Settle(t) end
				if SendNotice then SendNotice(t) end
				if t.watchers then
					for name, at in pairs(t.watchers) do if now - at > FT.WATCH_TTL then t.watchers[name] = nil end end
				end
			end
		end
	end
end
FT.Tick = function() return Tick() end

-- Combat (the design): the board closes (the companion's); this player's clock pauses while he
-- reports it (KT p), 120 s a game at most, and the opponent's board says why.
OnCombat = function(on)
	for _, t in pairs(tables) do
		if t.seat and t.state == "play" and t.game and not t.game.over and t.role ~= "practice" then
			t.inCombat = on or nil
			local g = t.game
			SendAll(t, "KT", ("%s~%s~p~%d~%s~%d"):format(t.id, B36(g.step), t.seat, R().ChainAt(g, g.step), on and 1 or 0), { urgent = true })
			FT.CombatReport(t, t.seat, on)
		end
	end
end
function FT.CombatReport(t, seat, on)
	t.combat = t.combat or {}
	local now = Clock()
	if on and not t.combat[seat] then
		t.combat[seat] = now
	elseif not on and t.combat[seat] then
		t.combatUsed = (t.combatUsed or 0) + (now - t.combat[seat])
		t.combat[seat] = nil
	end
	UpdatePause(t)
	Emit(t, { t = "combat", seat = seat, on = on and true or false })
	Changed(t)
end

---------------------------------------------------------------------------
-- The arbiter's floor (the design, KL)
---------------------------------------------------------------------------

-- The arbiter's client, after a decision of seat q reached it: the other seat's level left below
-- what the arbiter saw at least FLOOR_AGE before, a floor from that seat's turn after next; then
-- a floor whenever his view of that seat changes.
FloorCheck = function(t, q, arrived)
	if t.role ~= "arbiter" or not t.hic then return end
	local p = 3 - q
	local g = t.game
	local v = t.views and t.views[p]
	if not v then return end
	local lvl = R().Level(g, p)
	if v.level > lvl and ((arrived or Clock()) - v.at) >= FT.FLOOR_AGE then
		t.floorOn = t.floorOn or {}
		t.floorOn[p] = true
		FT.Floor(t, p, v.level)
	end
end
function FT.Floor(t, seat, lvl)
	local g = t.game
	if not g or g.over or t.role ~= "arbiter" then return false end
	t.klAt = t.klAt or {}
	if t.klAt[seat] and Clock() - t.klAt[seat] < FT.FLOOR_GAP then
		t.klDue = t.klDue or {}
		t.klDue[seat] = lvl
		return false
	end
	t.klAt[seat] = Clock()
	-- the seat's turn after next: his next is the one handed to him and not yet rolled, or the
	-- one after the turn he is playing
	local playing = not g.open and g.current == seat and (g.turn.rolls or 0) > 0
	local turn = g.turns[seat] + (playing and 1 or 0) + 2
	R().Floor(g, seat, turn, lvl)
	SendAll(t, "KL", ("%s~%d~%s~%d"):format(t.id, seat, B36(turn), lvl), { urgent = true })
	return true
end

---------------------------------------------------------------------------
-- The relay: a public table's state on the channel (KS, KN), and a player's to his watchers
-- (the design: batched through Comm's dedupe key; the channel when many watch)
---------------------------------------------------------------------------

local function StateBody(t)
	local g = t.game
	local turn = g.turn
	local dice = ""
	for _, d in ipairs(turn.dice or {}) do dice = dice .. d end
	if turn.kept and #turn.kept > 0 then dice = dice .. "." .. table.concat(turn.kept) end
	if dice == "" then dice = "-" end
	local phase = g.over and "over" or (g.open and "open" or turn.phase)
	local lv, sk = "00", "22"
	if g.hiccup then
		local l1, _, s1 = R().Level(g, 1)
		local l2, _, s2 = R().Level(g, 2)
		lv, sk = tostring(l1) .. tostring(l2), tostring(s1) .. tostring(s2)
	end
	return ("%s~%s~%s~%s~%s~%s~%s~%s~%s~%s~%s"):format(t.id, B36(g.scores[1]), B36(g.scores[2]), tostring(g.current or 0),
		B36(turn.points), tostring(turn.left or 0), dice, phase, B36(g.step), lv, sk)
end
local function Public(t) return t.arbiter ~= nil and ns.ArenaRoles.IsPublicArbiter(t.arbiter, t.mode) end
FT.Public = function(id) local t = tables[id] return t ~= nil and Public(t) end
local function Relayer(t)
	if t.noWatch then return false end
	if t.role == "arbiter" then return Public(t) end
	return t.seat ~= nil and t.spec and t.spec[t.seat] == true
end

SendState = function(t)
	if not Relayer(t) or not t.game then return end
	local body = StateBody(t)
	if body == t.lastState then return end
	t.lastState = body
	local n = 0
	for _ in pairs(t.watchers or {}) do n = n + 1 end
	if (t.role == "arbiter" and Public(t)) or n > FT.WATCH_WHISPER then
		A().Send("KS", t.mode, body, { dist = A().Lane(t.mode, true), key = "farkle " .. t.id })
	else
		for name in pairs(t.watchers or {}) do A().Send("KS", t.mode, body, { to = name, key = "farkle " .. t.id }) end
	end
end

-- The announcement (KN): a relayer's open table every NOTICE_EVERY, then its end. Never a game
-- against the House: practice sends nothing (the House's dice are this client's own, nobody could
-- witness them), so a member at an innkeeper is in nobody's live tables, by design: training is no
-- table to watch. (1.2.3: an open table whose game counts says so, "c"; the end of a game that
-- counts is this player's half, whether or not the table let watchers in.)
SendNotice = function(t)
	if not t.game or t.role == "practice" then return end
	local g = t.game
	if g.over and t.half == nil then t.half = OwnHalf(t) or false end
	local half = g.over and t.half or nil
	if not half and not Relayer(t) then return end
	local now = Clock()
	local state = g.over and "e" or "o"
	local winner = g.over and g.winner and tostring(g.winner) or "-"
	local key = state .. winner
	if t.noticeKey == key and t.noticeAt and now - t.noticeAt < FT.NOTICE_EVERY then return end
	t.noticeKey, t.noticeAt = key, now
	local body
	if half then
		body = half.body
	else
		local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
		body = ("%s~%s~%s~%s~%s~%s~%s~%s"):format(t.id, t.host, t.guest, t.arbiter or "-", tostring(R().TARGET_CODE[t.target] or 5),
			type(map) == "number" and B36(map) or "-", state, winner)
		if state == "o" and Counted(t) then body = body .. "~c" end
	end
	A().Send("KN", t.mode, body, { dist = A().Lane(t.mode, true), key = "farklen " .. t.id })
end

---------------------------------------------------------------------------
-- Creating a table (the host), answering (the guest), asking an arbiter
---------------------------------------------------------------------------

local function Settings() return ns.ArenaRoles.Settings() end
local function Salt()
	local out = {}
	for i = 1, 4 do local d = math.random(0, 35) out[i] = ("0123456789abcdefghijklmnopqrstuvwxyz"):sub(d + 1, d + 1) end
	return table.concat(out)
end

-- Why this client may not stake now (the design's "Staked" switch asks this too): rules, persistence for
-- o and t, a debtor, the cap.
function FT.StakeWhy(src, stake, arbiter)
	if not Wagers("stake") then return "compliance" end
	if not A().RulesAccepted() then return "rules" end
	if (src == "o" or src == "t") and not A().Persists() then return "persist" end
	local blocked = Call("Debts", "Blocked", Me())
	if blocked then return "debtor" end
	local cur = ns.ArenaRoles.Currency()
	if cur == "p" and src ~= "w" then return "points" end
	if stake then
		if stake < (Settings().minBet or 1000) then return "min" end
		if stake % 100 ~= 0 then return "silver" end
		if src == "o" then
			local cap = Call("Standing", "Cap", "direct", Me())
			if cap ~= nil and stake > (tonumber(cap) or 0) then return "cap" end
			if stake > (Settings().directMax or 500000) then return "cap" end
		elseif src == "t" and arbiter then
			if 2 * stake > ns.ArenaRoles.ArbiterCap(arbiter) then return "cap" end
		end
	end
	return nil
end

-- The checks a new table passes on the host's client (the design's KI).
function FT.CanCreate(opts)
	if type(opts) ~= "table" then return false, "opts" end
	if not ns.SharedToolsHere() or (opts.guest and not ns.SharedPeerAllowed(opts.guest)) then return false, "federation" end
	if not FT.CanPlayPlayers() then return false, "training" end
	local guest = Full(opts.guest)
	if not guest or Same(guest, Me()) then return false, "guest" end
	if FT.Live() then return false, "busy" end
	local M = ns.Moderation
	if M and not M.missing and M.SelfOff and M.SelfOff() then return false, "netoff" end
	if ns.Arena and ns.Arena.Sanctioned and ns.Arena.Sanctioned() then return false, "sanction" end -- (1.1.6)
	if InCombatLockdown and InCombatLockdown() then return false, "combat" end
	if A().Blocked() then return false, "instance" end
	local stake = floor(tonumber(opts.stake) or 0)
	local kind = opts.mode == "a" and "a" or "d"
	if kind == "a" and not Arbiters() then return false, "compliance" end
	if stake > 0 then
		local src = opts.src or (kind == "d" and "o" or "t")
		if not FT.SOURCES[kind][src] then return false, "source" end
		if kind == "a" then
			if not opts.arbiter then return false, "arbiter" end
			if ns.ArenaRoles.IsKing(opts.arbiter) and src ~= "w" then return false, "king" end
		end
		local why = FT.StakeWhy(src, stake, opts.arbiter)
		if why then return false, why end
		if Call("Debts", "SameOwner", Me(), guest) then return false, "alts" end
	end
	-- T can be the release's automatic free mode: it still needs a real venue.
	-- A free invitation may precede the party; opening checks both players together.
	if not A().Sim() and A().NewMode(opts.rehearsal) == "L" then
		local ok, twhy = FT.TavernStart(guest)
		if not ok then return false, "tavern-" .. tostring(twhy) end
	elseif not FT.CanOpen() then
		return false, "tavern-rest"
	end
	-- The crowd's bets: only where watchers come and an arbiter judges, never beside the wallet's
	-- stakes (their FK market is the table's own sheet).
	if opts.crowd == true then
		if not Wagers("bet") then return false, "compliance" end
		if kind ~= "a" or opts.spectators ~= true then return false, "crowd" end
		if stake > 0 and (opts.src or "t") == "w" then return false, "crowd" end
	end
	local target = tonumber(opts.target) or R().TARGET
	if not R().TARGET_CODE[target] then return false, "target" end
	local secs = floor(tonumber(opts.secs) or FT.SECS)
	if secs < FT.SECS_MIN or secs > FT.SECS_MAX then return false, "secs" end
	return true
end

function FT.Create(opts)
	local ok, why = FT.CanCreate(opts)
	if not ok then return nil, why end
	local stake = floor(tonumber(opts.stake) or 0)
	local kind = opts.mode == "a" and "a" or "d"
	local id = A().NewId("K", function(x) return tables[x] ~= nil end)
	local guest = Full(opts.guest)
	local t = {
		id = id, role = "host", host = Me(), guest = guest, arbiter = kind == "a" and Full(opts.arbiter) or nil, kind = kind,
		stake = stake, cur = ns.ArenaRoles.Currency(), target = tonumber(opts.target) or R().TARGET, secs = floor(tonumber(opts.secs) or FT.SECS),
		hic = opts.hic ~= false and FT.DrunkReadable(), hiccupRule = "bones2", salt = Salt(), src = { stake > 0 and (opts.src or (kind == "d" and "o" or "t")) or "-" },
		spec = { opts.spectators ~= false, false }, mode = A().NewMode(opts.rehearsal), created = Now(), invitedAt = Clock(), state = "invite",
		from = opts.from, seat = 1, log = {}, crowd = opts.crowd == true or nil,
	}
	t.players = { t.host, t.guest }
	if not A().Sim() then SetPlace(t, guest) end
	tables[id] = t
	local token, iou = "", ""
	if kind == "d" and stake > 0 and A().Counts(t.mode) then
		local tok = Call("Standing", "Token")
		local io = Call("Debts", "Iou", Ref(t), guest, stake)
		token = type(tok) == "string" and tok or ""
		iou = type(io) == "string" and io or ""
	end
	local body = ("%s~%s~%s~%d~%s~%s~%s~%d~%s"):format(id, kind, B36(stake), R().TARGET_CODE[t.target], t.arbiter or "-", t.src[1],
		B36(t.secs), HicCode(t), t.salt)
	-- (1.2.3: "c", this client counts the free game, decision 1: the guest's counts it only then)
	local free = FreeOffer(t)
	if token ~= "" or iou ~= "" or free then body = body .. "~" .. token .. "~" .. iou end
	if free then body = body .. "~c" end
	Send(t, "KI", body, guest, { urgent = true })
	Say(t, "FARKLE_LOG_INVITED", ns.DisplayName(guest))
	Involve(t, true)
	Save(t)
	Changed(t)
	return id
end

-- The guest's answer, from his popup's click.
function FT.CanAnswer(id, yes, src)
	local t = tables[id]
	if not t or t.role ~= "guest" or t.state ~= "invite" then return false, "gone" end
	if not yes then return true end
	if not ns.SharedPeerAllowed(t.host) then return false, "federation" end
	if not FT.CanPlayPlayers() then return false, "training" end
	if Staked(t) then
		src = src or (t.kind == "d" and "o" or t.src[1])
		if not FT.SOURCES[t.kind][src] then return false, "source" end
		if t.kind == "a" and src ~= t.src[1] then return false, "mixed" end
		local why = FT.StakeWhy(src, t.stake, t.arbiter)
		if why then return false, why end
	end
	if not A().Sim() and t.mode == "L" then
		local ok, twhy = FT.TavernStart(t.host)
		if not ok then return false, "tavern-" .. tostring(twhy) end
	elseif not FT.CanOpen() then
		return false, "tavern-rest"
	end
	if InCombatLockdown and InCombatLockdown() then return false, "combat" end
	return true
end

local function Refuse(t, sender, reason)
	A().Send("KA", t and t.mode or "L", ("%s~0~%s~0"):format(t and t.id or "?", reason), { to = sender, urgent = true })
end

function FT.Answer(id, yes, src, o)
	o = o or {}
	local t = tables[id]
	if not t then return false, "gone" end
	local ok, why = FT.CanAnswer(id, yes, src)
	if not ok then return false, why end
	if not yes then
		t.state = "declined"
		Refuse(t, t.host, o.reason or "d")
		Say(t, "FARKLE_LOG_DECLINED_ME")
		Finished(t)
		return true
	end
	src = Staked(t) and (src or (t.kind == "d" and "o" or t.src[1])) or "-"
	t.src[2] = src
	t.hic = t.hic and o.hic ~= false and FT.DrunkReadable()
	t.spec[2] = o.spectators ~= false
	if not A().Sim() then SetPlace(t, t.host) end
	local token, iou = "", ""
	if t.kind == "d" and Staked(t) and A().Counts(t.mode) then
		local tok = Call("Standing", "Token")
		local io = Call("Debts", "Iou", Ref(t), t.host, t.stake)
		token = type(tok) == "string" and tok or ""
		iou = type(io) == "string" and io or ""
	end
	local body = ("%s~1~%s~%d"):format(t.id, src, HicCode(t))
	-- (1.2.3: "c", this client counts the free game too: the host's counts it only then)
	local free = FreeOffer(t)
	if token ~= "" or iou ~= "" or free then body = body .. "~" .. token .. "~" .. iou end
	if free then body = body .. "~c" end
	t.state = "agreed"

	t.agreedAt = t.agreedAt or Clock()
	t.answeredAt = Clock()
	Send(t, "KA", body, t.host, { urgent = true })
	Say(t, "FARKLE_LOG_ACCEPTED_ME", ns.DisplayName(t.host))
	Save(t)
	Changed(t)
	return true
end

function FT.AskArbiter(id, name)
	local t = tables[id]
	if not t or t.role ~= "host" or (t.state ~= "asked" and t.state ~= "agreed") then return false, "state" end
	name = Full(name)
	if not name then return false, "name" end
	if name ~= t.arbiter then
		-- a new arbiter: the same agreed terms but him (the King needs the wallet on both sides)
		if ns.ArenaRoles.IsKing(name) and t.src[1] ~= "w" then return false, "king" end
		t.arbiter = name
	end
	t.state, t.askedAt = "asked", Clock()
	local body = ("%s~%s~%s~%s~%d~%s~%s~%d"):format(t.id, t.host, t.guest, B36(t.stake), R().TARGET_CODE[t.target],
		(t.src[1] or "-") .. (t.src[2] or "-"), B36(t.secs), HicCode(t))
	-- (1.2.3: "c", both players' clients count the free game: the arbiter's records it so too)
	local free = GameCounts(t)
	if t.crowd or free then body = body .. "~" .. (t.crowd and "1" or "0") end
	if free then body = body .. "~c" end
	Send(t, "KO", body, name, { urgent = true })
	Say(t, "FARKLE_LOG_ASKED_ARBITER", ns.DisplayName(name))
	Changed(t)
	return true
end

function FT.AnswerArbiter(id, yes)
	local t = tables[id]
	if not t or t.role ~= "arbiter" or t.state ~= "asked" then return false, "gone" end
	local reason = "-"
	if yes then
		if Arbitrating() > FT.ARBITRATE_MAX then yes, reason = false, "b" end
		if yes and Real(t) and t.src[1] == "t" then
			local okOpen, why = Call("Stakes", "Open", { id = t.id, kind = "farkle", A = { name = t.host, gk = GK(t.host) },
				B = { name = t.guest, gk = GK(t.guest) }, stake = { A = t.stake, B = t.stake }, arbiter = Me() })
			if okOpen == false then yes, reason = false, tostring(why or "l"):sub(1, 1) end
		end
	end
	local body = ("%s~%d~%s~%d"):format(t.id, yes and 1 or 0, yes and "-" or (reason == "-" and "d" or reason), HicCode(t))
	Send(t, "KP", body, t.host, { urgent = true })
	Send(t, "KP", body, t.guest, { urgent = true })
	if not yes then
		t.state = "declined"
		Finished(t)
		return true
	end
	t.state = "agreed"

	t.agreedAt = t.agreedAt or Clock()
	Changed(t)
	return true
end

-- The host opens the table (KG): both players in one party (with the arbiter), the terms agreed.
local function Open(t)
	if t.role ~= "host" then return end
	if not FT.InGroup(t.guest) or (t.arbiter and not FT.InGroup(t.arbiter)) then
		t.needGroup = true
		Say(t, "FARKLE_LOG_GROUP_FIRST", ns.DisplayName(t.guest))
		Changed(t)
		return false
	end
	t.needGroup = nil
	if not A().Sim() then
		local ok, why = FT.TavernStart(t.guest)
		if not ok then
			t.tavernWhy = why
			Say(t, "FARKLE_LOG_TAVERN_" .. tostring(why):upper())
			Changed(t)
			return false
		end
		SetPlace(t, t.guest)
		t.tavernWhy = nil
	end
	local body = ("%s~%s~%s~%s~%s~%d~%s~%d"):format(t.id, Digest(t), t.host, t.guest, t.arbiter or "-", R().TARGET_CODE[t.target], B36(t.secs),
		HicCode(t))
	-- (the crowd's word, then the host's no to watchers: both trailing, sent only when they say something)
	local crowd = t.crowd and t.arbiter and "1" or "0"
	if t.spec[1] == false then body = body .. "~" .. crowd .. "~0" elseif crowd == "1" then body = body .. "~1" end
	t.noWatch = t.spec[1] == false or nil
	SendAll(t, "KG", body, { urgent = true })
	FT.Begin(t)
	return true
end
FT.Open = function(id) local t = tables[id] return t and Open(t) end

-- Every participant builds the same game at KG (phase "open": the opening rolls).
function FT.Begin(t)
	if not NewGame(t) then t.state = "aborted" Finished(t) return end
	t.state = "open"
	t.kys = {}
	t.openedAt = Clock()
	Say(t, "FARKLE_LOG_OPEN")
	Involve(t, true)
	Save(t)
	Changed(t)
	-- a relayer announces its table; then its arbiter opens the crowd's bets (heard after the table)
	if SendNotice then SendNotice(t) end
	if t.crowd and t.role == "arbiter" then FT.OpenCrowd(t) end
end

---------------------------------------------------------------------------
-- The player's own moves
---------------------------------------------------------------------------

local function Mine2(id)
	local t = id and tables[id] or FT.Live()
	if not t then
		for _, x in pairs(tables) do if x.role == "practice" and not x.closed then t = x end end
	end
	return t
end

-- Why this player may not act now (the board greys its buttons with it).
function FT.ActWhy(t)
	if not t or not t.game then return "table" end
	if t.role ~= "practice" and not ns.SharedToolsHere() then return "federation" end
	local g = t.game
	if g.over then return "over" end
	if t.role == "practice" and t.inn and select(2, FT.Innkeeper()) ~= t.inn then return "training_inn" end
	if t.state ~= "play" and not (t.state == "open" and g.open) and t.role ~= "practice" then return "state" end
	local who, phase = R().Expect(g)
	if g.open then
		if g.opening[t.seat] then return "wait" end
		return nil, "open"
	end
	if who ~= t.seat then return "turn" end
	if t.clock and t.clock.pausedAt then return t.clock.pauseWhy or "paused" end
	local click = Limits(t)
	if t.role ~= "practice" and Used(t) >= click then return "late" end
	-- (a line of his own held behind his decision never stops the decision: it is taken after it)
	return nil, phase
end

-- Roll: the dice left (1-6^k), the opening's 1-100, or HIC!'s 1-100 (the design), each the player's own
-- /roll through RandomRoll, read back from the server's line like everyone else's.
function FT.Roll(id) -- gp:arena-clicks
	local t = Mine2(id)
	local why, phase = FT.ActWhy(t)
	if why then return false, why end
	local g = t.game
	local lo, hi
	if phase == "open" or phase == "hiccup" then lo, hi = 1, R().OPENING
	elseif phase == "roll" or phase == "decide" then lo, hi = 1, R().RANGES[g.turn.left]
	else return false, "phase" end
	t.rolling = { at = Clock(), hi = hi }
	local ok, err = pcall(RandomRoll, lo, hi)
	if not ok then
		t.rolling.refused = true
		FT.Note("%s RandomRoll(%d, %d) refused: %s", t.id, lo, hi, tostring(err))
	end
	Emit(t, { t = "rolling", seat = t.seat, hi = hi, refused = not ok or nil })
	Changed(t)
	return true, hi
end
function FT.Hiccup(id)
	local t = Mine2(id)
	if t and t.hiccupRule == "bones2" then return false, "phase" end
	return FT.Roll(id)
end

-- Keep & roll ("r") or Bank ("b"): the dice set aside (positions of the last roll) and the act,
-- written here at once and whispered (KK) to the others; a roll follows the "r" (the board's own
-- click: RandomRoll).
function FT.Keep(mask, act, id)
	local t = Mine2(id)
	local why, phase = FT.ActWhy(t)
	if why then return false, why end
	if phase ~= "keep" then return false, "phase" end
	local text, list = R().Mask(mask)
	if not text then return false, "dice" end
	act = act == "b" and "b" or "r"
	local g = t.game
	local step, chain = g.step, R().ChainAt(g, g.step)
	-- (practice: the House never drinks, and the player's own "You feel" waits for the House's
	-- next decision, which writes it: his own decisions write no level and keep that news)
	local practice = t.role == "practice"
	local lvl = not practice and NewsFor(t, t.seat) or nil
	local ok, note = Apply(t, { t = "K", p = t.seat, mask = list, act = act, lvl = lvl }, "mine")
	if not ok then return false, note end
	if not practice then t.news = nil end
	if t.role ~= "practice" then
		SendAll(t, "KK", ("%s~%s~%s~%s~%s%s"):format(t.id, B36(step), text, act, chain, lvl and ("~" .. lvl) or ""), { urgent = true })
	end
	return true, note
end

function FT.Concede(id)
	local t = Mine2(id)
	if not t or not t.game or t.game.over or not t.seat then return false, "table" end
	local g = t.game
	local step, chain = g.step, R().ChainAt(g, g.step)
	local ok = Apply(t, { t = "C", p = t.seat }, "mine")
	if ok and t.role ~= "practice" then
		SendAll(t, "KT", ("%s~%s~c~%d~%s~%d"):format(t.id, B36(step), t.seat, chain, t.inCombat and 1 or 0), { urgent = true })
	end
	return ok and true or false
end

-- A void: the arbiter's, or both players' before any result (the design's ZT v).
function FT.Void(id)
	local t = Mine2(id)
	if not t or not t.game or t.game.over then return false, "table" end
	local g = t.game
	if t.role == "arbiter" or t.role == "practice" then
		if t.role == "arbiter" then Claim(t, "v") else Apply(t, { t = "V" }, "mine") end
		return true
	end
	t.voteVoid = true
	SendAll(t, "KT", ("%s~%s~v~%d~%s~0"):format(t.id, B36(g.step), t.seat, R().ChainAt(g, g.step)), { urgent = true })
	if t.otherVoid then Apply(t, { t = "V" }, "mine") end
	Changed(t)
	return true
end

-- "Sit down" (the design): the game's /sit, the player's own click; flavour, never required.
function FT.Sit() -- gp:arena-clicks
	if DoEmote then return pcall(DoEmote, "SIT") end
	return false
end

-- The party invite for the table (the player's click; the game's own invite, as Hop does).
function FT.Invite(name) -- gp:arena-clicks
	name = Full(name)
	if not name then return false end
	local target = ns.TellName(name)
	if C_PartyInfo and C_PartyInfo.InviteUnit then return pcall(C_PartyInfo.InviteUnit, target) end
	if InviteUnit then return pcall(InviteUnit, target) end
	return false
end

---------------------------------------------------------------------------
-- The fill actions (the design's ArenaMoney): never a transfer; with the gamepad UI they
-- only print what to send.
---------------------------------------------------------------------------

local function Subject(t, kind)
	local test = t.mode == "T" and "TEST " or ""
	if kind == "fee" then return ("Arena fee %s%s"):format(test, Ref(t)) end
	return ("Arena %s %s%s"):format(kind, test, Ref(t))
end
FT.Subject = function(id, kind) local t = tables[id] return t and Subject(t, kind) end

local function Line(t, kind)
	for _, l in ipairs(t.lines or {}) do if l.kind == kind then return l end end
	return nil
end
function FT.Pay(id)
	local t = tables[id]
	local l = t and Line(t, "pay")
	if not l then return false, "line" end
	return Call("ArenaMoney", "FillTrade", l.copper - (l.paid or 0))
end
function FT.PayFee(id)
	local t = tables[id]
	local l = t and Line(t, "fee")
	if not l then return false, "line" end
	local to = ns.ArenaRoles.FeeReceiver()
	if not to then return false, "receiver" end
	-- the 6% of the money won (the design): of what came from the loser so far, never more
	-- than the stake's
	local fee = FT.DirectFee(min(t.received or 0, t.stake))
	if fee <= 0 then return false, "nothing" end
	return Call("ArenaMoney", "FillMail", to, Subject(t, "fee"), fee)
end
function FT.PayStake(id)
	local t = tables[id]
	if not t or t.state ~= "stakes" or t.src[t.seat or 0] ~= "t" then return false, "state" end
	if 2 * t.stake > ns.ArenaRoles.ArbiterCap(t.arbiter) then return false, "cap" end
	return Call("ArenaMoney", "FillTrade", t.stake)
end
local function StakeLine(t, kind)
	for _, l in ipairs(type(t.lines) == "table" and t.lines or {}) do
		if l.kind == kind and type(l.fill) == "function" then return pcall(l.fill) end
	end
	return false, "line"
end
function FT.Payout(id) local t = tables[id] return t and StakeLine(t, "payout") end
function FT.Refund(id) local t = tables[id] return t and StakeLine(t, "refund") end
function FT.Change(id) local t = tables[id] return t and StakeLine(t, "change") end

-- Money the watcher (ArenaMoney) saw: a direct game's payment between the two players, both
-- sides' receipts (KD); the creditor's "r" clears the debtor's obligation.
local function OnMoney(r)
	if type(r) ~= "table" or r.kind ~= "trade" then return end
	for _, t in pairs(tables) do
		if t.kind == "d" and t.settled and Real(t) and t.seat and t.game and t.game.winner then
			local other = t.players[3 - t.seat]
			if Same(r.partner, other) then
				if t.game.winner == t.seat and (r.got or 0) > 0 then
					t.received = (t.received or 0) + r.got
					Send(t, "KD", ("%s~r~%s~t"):format(t.id, B36(r.got)), other, { urgent = true })
				elseif t.game.winner ~= t.seat and (r.gave or 0) > 0 then
					local l = Line(t, "pay")
					if l then l.paid = (l.paid or 0) + r.gave end
					Send(t, "KD", ("%s~p~%s~t"):format(t.id, B36(r.gave)), other, { urgent = true })
				end
				Changed(t)
			end
		end
	end
end
FT.OnMoney = OnMoney
local subscribed = false
local function Subscribe()
	if subscribed then return end
	local f = Api("ArenaMoney", "Subscribe")
	if f then subscribed = true pcall(f, OnMoney) end
end

---------------------------------------------------------------------------
-- The handlers (each a literal Comm.Handle through Arena.Handle, the design)
---------------------------------------------------------------------------

local function ValidId(id) return type(id) == "string" and #id <= 16 and id:find("^K[0-9a-z]+$") ~= nil end
local function Hides(sender)
	local M = ns.Moderation
	if M and not M.missing and M.Hides and M.Hides(sender) then return true end
	-- (1.1.6: a sanctioned player's invitations, tables and moves, WatchChat.Barred.)
	if ns.Arena and ns.Arena.Sanctioned and ns.Arena.Sanctioned(sender) then return true end
	local blocked = ns.db and ns.db.blocked
	return type(blocked) == "table" and blocked[Full(sender):lower()] ~= nil
end

---------------------------------------------------------------------------
-- (1.2.1) Fewer pop-ups: Bones invitations and the innkeeper's offer, each with its switch
---------------------------------------------------------------------------
-- Invitations from other players are on until the player says No (ns.db.bonesInvites: nil on,
-- true kept after the question, false off; the privacy page's line, /oly farkle invites). Off,
-- each is refused quietly with "i", which the inviter's table names; a matched partner's still
-- comes (the player searched). From INVITES_BURST different players within INVITES_WINDOW, one
-- question in place of the invitation's own pop-up asks whether to stop them: answered, never
-- again; dismissed, not again this session.
-- The innkeeper's offer (ns.db.bonesKeeper: false hides it; the privacy page's line, /oly farkle
-- keeper) is the quiet line in his conversation (InnkeeperGossip.lua). Where that line cannot show
-- (the gamepad UI, a changed NPC panel) his Olympus window opens only after the player asked for
-- him on the Bones page (WantKeeper), never by itself at each visit. The ask has no time limit
-- (the walk to an inn has none) and is kept in this character's Bones options through a /reload:
-- it serves the next conversation with a mapped innkeeper where his offer shows, and brings that
-- offer back once with the switch off too (the player asked; an untrained one could not train).
local invitesSeen = {}    -- [sender, lower case] = when his invitation was last shown or told
local invitesAsked = false -- the question came this session

function FT.InvitesOn() return not (type(ns.db) == "table" and ns.db.bonesInvites == false) end
-- Off: every invitation still waiting for this player's answer is refused the same way. silent:
-- no chat line (a restore, Backup.NOES).
function FT.SetInvites(on, silent)
	if type(ns.db) ~= "table" then return false end
	ns.db.bonesInvites = on and true or false
	if not on then
		for _, t in pairs(tables) do
			if t.role == "guest" and t.state == "invite" then
				t.state = "declined"
				Refuse(t, t.host, "i")
				Say(t, "FARKLE_LOG_DECLINED_ME")
				Finished(t)
			end
		end
	end
	if not silent then ns.Print(on and L.FARKLE_INVITES_ON or L.FARKLE_INVITES_OFF) end
	A().Changed()
	return true
end
function FT.KeeperOffer() return not (type(ns.db) == "table" and ns.db.bonesKeeper == false) end
-- Off: an ask made before it is dropped (the No came after it).
function FT.SetKeeperOffer(on, silent)
	if type(ns.db) ~= "table" then return false end
	ns.db.bonesKeeper = on and true or false
	if not on then
		FT.WantKeeper(false)
		if ns.InnkeeperGossip and ns.InnkeeperGossip.Park then ns.InnkeeperGossip.Park() end
	end
	if not silent then ns.Print(on and L.FARKLE_KEEPER_OFFER_ON or L.FARKLE_KEEPER_OFFER_OFF) end
	return true
end
-- The player asked for the innkeeper (the Bones page): his next conversation shows the offer.
function FT.WantKeeper(on)
	if on == false then
		local m = Peek("L")
		if m and type(m.opts) == "table" then m.opts.keeperAsked = nil end
		return
	end
	local m = Mine("L")
	if m then m.opts.keeperAsked = true end
end
function FT.KeeperWanted()
	local m = Peek("L")
	return m ~= nil and type(m.opts) == "table" and m.opts.keeperAsked == true
end

-- The different players whose invitations reached this player within INVITES_WINDOW, his own
-- counted now.
local function InvitesFrom(key)
	local now = Clock()
	invitesSeen[key] = now
	local n = 0
	for k, at in pairs(invitesSeen) do
		if now - at > FT.INVITES_WINDOW then invitesSeen[k] = nil else n = n + 1 end
	end
	return n
end
-- The newest invitation still waiting, in its own pop-up.
local function ShowWaiting()
	local newest
	for id, t in pairs(tables) do
		if t.role == "guest" and t.state == "invite" and (not newest or (t.invitedAt or 0) > (tables[newest].invitedAt or 0)) then newest = id end
	end
	if newest then FT.ShowUI("invite", newest) end
end
-- The question, once (true: it shows in place of the invitation's pop-up).
local function AskStop(n)
	if invitesAsked or n < FT.INVITES_BURST or type(ns.db) ~= "table" or ns.db.bonesInvites ~= nil then return false end
	invitesAsked = true
	ns.Alert("arena", "soft", { what = L.CONSENT_BONES_INVITES, key = "farkle-invites",
		open = function() return type(ns.db) == "table" and ns.db.bonesInvites == nil end,
		show = function() ns.ShowDialog("OLYMPUS_BONES_INVITES", L.FARKLE_INVITES_ASK:format(n)) end })
	return true
end
function FT.InvitesAnswer(stop, clicked)
	if stop then return FT.SetInvites(false) end
	if clicked and type(ns.db) == "table" then ns.db.bonesInvites = true end
	ShowWaiting()
	return true
end
StaticPopupDialogs["OLYMPUS_BONES_INVITES"] = {
	text = "%s",
	button1 = L.FARKLE_INVITES_STOP,
	button2 = L.FARKLE_INVITES_KEEP,
	OnAccept = function() ns.SafeCall("bones invitations", FT.InvitesAnswer, true, true) end,
	-- Keep them: kept, never asked again; another popup's place: not answered, the invitation shown.
	OnCancel = function(_, _, reason) ns.SafeCall("bones invitations", FT.InvitesAnswer, false, reason == "clicked") end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	-- Escape only closes it, answering nothing (the game's StaticPopup_CallEscapeHandler would call
	-- OnCancel with "clicked", a Keep them for good); the invitation waits on the Bones page.
	noCancelOnEscape = true,
	preferredIndex = 3,
	buttonHeight = 24,
	textFont = "GameFontHighlightMed2",
}
-- Their lines on the privacy page: on until the player says No, so they never open it by themselves.
if ns.Consent and ns.Consent.Register then
	local function Shown() return ns.IsMember() == true and not A().Off() end
	ns.Consent.Register({ key = "bonesInvites", label = "CONSENT_BONES_INVITES", text = "CONSENT_BONES_INVITES_TEXT", shown = Shown,
		get = function() return FT.InvitesOn() end, set = function(on) FT.SetInvites(on) end, pending = function() return false end })
	ns.Consent.Register({ key = "bonesKeeper", label = "CONSENT_BONES_KEEPER", text = "CONSENT_BONES_KEEPER_TEXT", shown = Shown,
		get = function() return FT.KeeperOffer() end, set = function(on) FT.SetKeeperOffer(on) end, pending = function() return false end })
end

-- KI: an invitation to this client (the design).
local function OnInvite(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local f = Split(body)
	local id, kind, stake, tcode, arb, hostSrc, secs, hic, salt, token, iou = f[1], f[2], N36(f[3] or "", 0, A().COPPER_MAX), tonumber(f[4] or ""),
		f[5], f[6], N36(f[7] or "", FT.SECS_MIN, FT.SECS_MAX), f[8], f[9], f[10], f[11]
	if not ValidId(id) or (kind ~= "d" and kind ~= "a") or not stake or not R().TARGET_BY_CODE[tcode] or not secs
		or (hic ~= "0" and hic ~= "2") or type(salt) ~= "string" or not salt:find("^[0-9a-z][0-9a-z][0-9a-z][0-9a-z]$") then return end
	if Hides(sender) or tables[id] then return end
	local arbiter = arb ~= "-" and A().Name(arb) or nil
	if kind == "a" and not arbiter then return end
	-- (A table that waits on an arbiter: never while there are none.)
	if kind == "a" and not Arbiters() then ns.Log("farkle %s: an arbiter's invitation dropped (compliance)", tostring(id)) return end
	if stake > 0 and not FT.SOURCES[kind][hostSrc] then return end
	-- (A staked invitation, a modified client's too: never taken while the gate says no.)
	if stake > 0 and not Wagers("stake") then ns.Log("farkle %s: a staked invitation dropped (compliance)", tostring(id)) return end
	-- one invitation per sender every GUEST_GAP; one live table: others are declined silently
	local key = Full(sender):lower()
	local now = Clock()
	local t = { id = id, mode = mode, role = "guest", host = Full(sender), guest = Me(), arbiter = arbiter, kind = kind, stake = stake,
		cur = ns.ArenaRoles.Currency(), target = R().TARGET_BY_CODE[tcode], secs = secs, hic = hic == "2", hiccupRule = "bones2", salt = salt,
		src = { stake > 0 and hostSrc or "-" }, spec = { false, false }, created = Now(), invitedAt = now, state = "invite", seat = 2, log = {},
		free = f[12] == "c" or nil } -- (1.2.3: the host's client counts the free game, decision 1)
	t.players = { t.host, t.guest }
	-- (1.2.1: invitations off: refused quietly, the host told why, "i"; a matched partner's comes.)
	if not FT.InvitesOn() and Call("ArenaMatch", "MatchedWith", sender) ~= true then return Refuse(t, sender, "i") end
	if invitedBy[key] and now - invitedBy[key] < FT.GUEST_GAP then return Refuse(t, sender, "b") end
	invitedBy[key] = now
	-- (1.2.0: his first game with an innkeeper still to play: he is told so, and the host why, "f".)
	if not FT.CanPlayPlayers() then
		ns.Print(L.FARKLE_INVITED_NOT_TRAINED:format(ns.DisplayName(sender) or "?"))
		Refuse(t, sender, "f")
		AskStop(InvitesFrom(key))
		return
	end
	if FT.Live() then return Refuse(t, sender, "b") end
	if (InCombatLockdown and InCombatLockdown()) or A().Blocked() then return Refuse(t, sender, "c") end
	if stake > 0 then
		if stake % 100 ~= 0 or stake < (Settings().minBet or 1000) then return Refuse(t, sender, "l") end
		if Call("Debts", "SameOwner", Me(), sender) then return Refuse(t, sender, "a") end
		if Call("Debts", "Blocked", sender) then return Refuse(t, sender, "n") end
		if (hostSrc == "o" or hostSrc == "t") and not A().Persists() then return Refuse(t, sender, "g") end
		if kind == "a" and ns.ArenaRoles.IsKing(arbiter) and hostSrc ~= "w" then return Refuse(t, sender, "k") end
		if kind == "d" and A().Counts(mode) then
			-- the host's standing token and IOU (the design): checked by the money package
			if (token or "") == "" or Call("Standing", "CheckToken", token) == false then return Refuse(t, sender, "l") end
			if (iou or "") ~= "" and Call("Debts", "CheckIou", iou) == false then return Refuse(t, sender, "n") end
			t.token, t.iou = token, iou
		end
	end
	-- a matched player's terms hold (the design)
	if Api("ArenaMatch", "Vet") then
		local yes, from = Call("ArenaMatch", "Vet", sender, "b", stake)
		if yes == false then return Refuse(t, sender, "m") end
		if yes == true and type(from) == "string" then t.from = from end
	end
	tables[id] = t
	Involve(t, true)
	Say(t, "FARKLE_LOG_INVITE_FROM", ns.DisplayName(sender))
	Changed(t, "invite")
	-- (1.2.1: the second player's within the window: the question instead; it waits on the Bones
	-- page, and Keep them shows it.)
	if not t.from and AskStop(InvitesFrom(key)) then return end
	-- the popup is Olympus's own (the companion's), raised as an arena alert
	ns.Alert("arena", "soft", { text = L.FARKLE_ALERT_INVITE:format(ns.DisplayName(sender)), key = "farkle-invite " .. id,
		open = function() local x = tables[id] return x ~= nil and x.state == "invite" end,
		show = function() FT.ShowUI("invite", id) end })
end
ns.Comm.Handle("KI", ns.Arena.Handle("KI", OnInvite))

-- KA: the guest's answer (the host's client).
local function OnAnswer(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local f = Split(body)
	local t = tables[f[1] or ""]
	if not t or t.role ~= "host" or t.state ~= "invite" or not Same(sender, t.guest) or t.mode ~= mode then return end
	if Clock() - t.invitedAt > FT.INVITE_TTL then return end
	if f[2] ~= "1" then
		t.state = "declined"
		t.why = FT.REASONS[f[3]] and f[3] or "d"
		Say(t, "FARKLE_LOG_DECLINED", ns.DisplayName(sender), L["FARKLE_WHY_" .. t.why:upper()] or t.why)
		Finished(t)
		return
	end
	local src, hic = f[3], f[4]
	if (hic ~= "0" and hic ~= "2") or (hic == "2" and HicCode(t) ~= 2) then return end
	if Staked(t) then
		if not FT.SOURCES[t.kind][src] or (t.kind == "a" and src ~= t.src[1]) then Refuse(t, sender, "s") t.state = "declined" Finished(t) return end
		if t.kind == "d" and A().Counts(t.mode) then
			if (f[5] or "") == "" or Call("Standing", "CheckToken", f[5]) == false then t.state = "declined" t.why = "l" Finished(t) return end
			t.token, t.iou = f[5], f[6]
		end
	else
		src = "-"
	end
	t.src[2] = src
	t.hic = t.hic and hic == "2"
	-- (1.2.3: the guest's client counts the free game, decision 1; an older client's or a test
	-- build's answer says no "c", and neither side counts it)
	t.free = f[7] == "c" or nil
	Say(t, "FARKLE_LOG_ACCEPTED", ns.DisplayName(sender))
	if t.kind == "a" then
		t.state = "agreed"

		t.agreedAt = t.agreedAt or Clock()
		return FT.AskArbiter(t.id, t.arbiter)
	end
	t.state = "agreed"

	t.agreedAt = t.agreedAt or Clock()
	Open(t)
	Changed(t)
end
ns.Comm.Handle("KA", ns.Arena.Handle("KA", OnAnswer))

-- KO: asked to hold a table (the arbiter's client, the design).
local function OnOfficiate(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local f = Split(body)
	local id, host, guest, stake, tcode, srcs, secs, hic = f[1], A().Name(f[2] or ""), A().Name(f[3] or ""), N36(f[4] or "", 0, A().COPPER_MAX),
		tonumber(f[5] or ""), f[6], N36(f[7] or "", FT.SECS_MIN, FT.SECS_MAX), f[8]
	if not ValidId(id) or not host or not guest or not stake or not R().TARGET_BY_CODE[tcode] or not secs or type(srcs) ~= "string" or #srcs ~= 2
		or (hic ~= "0" and hic ~= "2") then return end
	if not Same(sender, host) or Hides(sender) then return end
	-- (Asked to hold a table: no arbiters while no wager may happen.)
	if not Arbiters() then ns.Log("farkle %s: an ask to arbitrate dropped (compliance)", tostring(id)) return end
	-- (Asked to hold stakes or the crowd's bets: never while the gate says no.)
	if (stake > 0 and not Wagers("stake")) or (f[9] == "1" and not Wagers("bet")) then
		ns.Log("farkle %s: a staked or betting table's ask dropped (compliance)", tostring(id))
		return
	end
	local t = { id = id, mode = mode, role = "arbiter", host = host, guest = guest, arbiter = Me(), kind = "a", stake = stake, cur = ns.ArenaRoles.Currency(),
		target = R().TARGET_BY_CODE[tcode], secs = secs, hic = hic == "2", hiccupRule = "bones2", src = { srcs:sub(1, 1), srcs:sub(2, 2) }, spec = { false, false },
		created = Now(), state = "asked", askedAt = Clock(), log = {}, crowd = f[9] == "1" or nil,
		free = f[10] == "c" or nil } -- (1.2.3: both players' clients count the free game, the host says)
	t.players = { host, guest }
	local function No(reason)
		A().Send("KP", mode, ("%s~0~%s"):format(id, reason), { to = host, urgent = true })
		A().Send("KP", mode, ("%s~0~%s"):format(id, reason), { to = guest, urgent = true })
	end
	if tables[id] then return end
	if not ns.ArenaRoles.IsArbiter(Me(), mode) then return No("n") end
	if IsPlayer(t, Me()) or Call("Debts", "SameOwner", Me(), host) or Call("Debts", "SameOwner", Me(), guest) then return No("a") end
	if Arbitrating() >= FT.ARBITRATE_MAX or FT.Live() then return No("b") end
	if ns.ArenaRoles.IsKing(Me()) and stake > 0 and srcs ~= "ww" then return No("k") end
	if stake > 0 and srcs == "tt" and 2 * stake > ns.ArenaRoles.ArbiterCap(Me()) then return No("l") end
	if stake > 0 and srcs ~= "tt" and srcs ~= "ww" then return No("s") end
	tables[id] = t
	Involve(t, true)
	Changed(t, "asked")
	ns.Alert("arena", "soft", { text = L.FARKLE_ALERT_ARBITER:format(ns.DisplayName(host), ns.DisplayName(guest)), key = "farkle-arb " .. id,
		open = function() local x = tables[id] return x ~= nil and x.state == "asked" end,
		show = function() FT.ShowUI("arbiter", id) end })
end
ns.Comm.Handle("KO", ns.Arena.Handle("KO", OnOfficiate))

-- KP: the arbiter's answer (the host and the guest).
local function OnOfficiateAnswer(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local f = Split(body)
	local t = tables[f[1] or ""]
	if not t or not t.arbiter or not Same(sender, t.arbiter) or t.mode ~= mode then return end
	if f[2] ~= "1" then
		if t.state == "asked" or t.state == "agreed" then
			t.state = t.role == "host" and "agreed" or t.state
			t.arbiterNo = f[3]
			Say(t, "FARKLE_LOG_ARBITER_NO", ns.DisplayName(sender))
			Changed(t)
		end
		return
	end
	-- Old arbiters did not validate KO's hiccup marker. Their KP must not activate new rules.
	if t.hic and f[4] ~= tostring(HicCode(t)) then return end
	t.arbiterYes = true
	if t.role == "host" and t.state == "asked" then
		t.state = "agreed"

		t.agreedAt = t.agreedAt or Clock()
		Open(t)
	end
	Changed(t)
end
ns.Comm.Handle("KP", ns.Arena.Handle("KP", OnOfficiateAnswer))

-- KG: the table opens (every participant builds the game; the receiver must be in our group).
local function OnGo(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local f = Split(body)
	local t = tables[f[1] or ""]
	if not t or t.mode ~= mode or not Same(sender, t.host) then return end
	-- A valid host/digest is not this client's consent. Both guest and arbiter must have
	-- accepted locally before KG can change terms, create a game, or start its clocks.
	if t.state ~= "agreed" then return end
	if t.role ~= "guest" and t.role ~= "arbiter" then return end
	if not FT.InGroup(sender) then return end
	if f[8] ~= tostring(HicCode(t)) then return end
	-- (the crowd's bets: the arbiter has the host's word from KO, the guest from here; a table with
	-- them is not joined while the compliance gate says no)
	if f[9] == "1" and not Wagers("bet") then ns.Log("farkle %s: KG with the crowd's bets dropped (compliance)", t.id) return end
	if f[9] == "1" then t.crowd = true end
	-- (the host keeps watchers out: nobody at the table relays, his guest's yes or not)
	if f[10] == "0" then t.noWatch = true end
	-- (the arbiter has no salt: KO gave him the terms themselves)
	if t.role == "guest" and f[2] ~= Digest(t) then
		ns.Log("farkle %s: KG digest differs", t.id)
		t.state = "aborted"
		t.why = "terms"
		Say(t, "FARKLE_LOG_ABORT_TERMS")
		Finished(t)
		return
	end
	if not A().Sim() and t.role == "guest" then
		local ok, why = FT.TavernStart(t.host)
		if not ok then
			t.tavernWhy = why
			Say(t, "FARKLE_LOG_TAVERN_" .. tostring(why):upper())
			-- (no KY from here: the host aborts after the handshake's wait)
			Changed(t)
			return
		end
		SetPlace(t, t.host)
		t.tavernWhy = nil
	elseif not A().Sim() and t.role == "arbiter" then
		if not FT.CanOpen() then return end
		local a, b = Position(UnitOf(t.host)), Position(UnitOf(t.guest))
		local inn = InnAt(a)
		if a and b then
			local spot = { cont = a.cont, wx = (a.wx + b.wx) / 2, wy = (a.wy + b.wy) / 2 }
			if inn then t.inn, t.spot = inn.id, spot
			else
				local camp = TableCamp(t.host, t.guest)
				if camp then t.camp, t.campfire, t.spot = true, camp.campfire, spot end
			end
		end
	end
	FT.Begin(t)
end
ns.Comm.Handle("KG", ns.Arena.Handle("KG", OnGo))

-- KY: a participant saw both opening rolls (the handshake).
local function OnReady(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local f = Split(body)
	local t = tables[f[1] or ""]
	if not t or t.mode ~= mode or t.state ~= "open" or f[2] ~= "o" then return end
	if not (IsPlayer(t, sender) or (t.arbiter and Same(sender, t.arbiter))) then return end
	t.kys = t.kys or {}
	t.kys[Full(sender):lower()] = f[3]
	Progress(t)
end
ns.Comm.Handle("KY", ns.Arena.Handle("KY", OnReady))

-- KH: the stakes are held (the arbiter; every client checks the holdings itself too).
local function OnHeld(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local f = Split(body)
	local t = tables[f[1] or ""]
	if not t or t.mode ~= mode or t.state ~= "stakes" or not t.arbiter or not Same(sender, t.arbiter) then return end
	t.kh = { f[2] == "1", f[3] == "1", f[4] }
	StakesTick(t)
end
ns.Comm.Handle("KH", ns.Arena.Handle("KH", OnHeld))

-- KK: the current player's decision.
local function OnDecision(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local f = Split(body)
	local t = tables[f[1] or ""]
	if not t or t.mode ~= mode or not t.game or t.role == "watch" then return end
	local seat = SeatOf(t, sender)
	if not seat then return end
	local step = N36(f[2] or "", 0, 5000)
	local _, list = R().Mask(f[3] or "")
	local act, chain, lvl = f[4], f[5], f[6] and tonumber(f[6]) or nil
	if not step or not list or (act ~= "r" and act ~= "b") or type(chain) ~= "string" then return end
	if lvl ~= nil and (not t.hic or lvl < 0 or lvl > 3 or lvl ~= floor(lvl)) then return end
	Offer(t, { kind = "KK", from = sender, step = step, chain = chain, arrived = Clock(), ev = { t = "K", p = seat, mask = list, act = act, lvl = lvl } })
end
ns.Comm.Handle("KK", ns.Arena.Handle("KK", OnDecision))

-- KT: a claim (a timeout, a concession, a forfeit, a void, a combat report, gone from the tavern).
local function OnClaim(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local f = Split(body)
	local t = tables[f[1] or ""]
	if not t or t.mode ~= mode or not t.game or t.role == "watch" then return end
	local step, kind, seat, chain, flag = N36(f[2] or "", 0, 5000), f[3], tonumber(f[4] or ""), f[5], f[6]
	if not step or (seat ~= 1 and seat ~= 2) or type(chain) ~= "string" then return end
	local senderSeat = SeatOf(t, sender)
	local fromArbiter = t.arbiter and Same(sender, t.arbiter)
	if kind == "p" then
		if senderSeat ~= seat then return end
		return FT.CombatReport(t, seat, flag == "1")
	end
	local ev
	if kind == "c" then
		if senderSeat ~= seat then return end
		ev = { t = "C", p = seat }
	elseif kind == "t" or kind == "a" or kind == "g" then
		-- the judge: the arbiter, else the waiting player (never about himself)
		if t.arbiter then if not fromArbiter then return end elseif senderSeat ~= 3 - seat then return end
		ev = kind == "g" and { t = "C", p = seat } or { t = kind == "a" and "A" or "T", p = seat }
		-- A departure needs this client's own observation for the full grace, including
		-- when an early claim waits or the player returns before it can be applied.
		if kind == "g" then
			local since = t.away and t.away[seat]
			if not since or not Away(t, seat) then return end
			local left = FT.TAVERN_GRACE - (Clock() - since)
			if left > 0 then
				return Pend(t, { kind = "KT", from = sender, step = step, chain = chain, ev = ev,
					awaySeat = seat, notBefore = Clock() + left })
			end
		else
			ResetClock(t)
			local click = Limits(t)
			if t.clock and t.clock.seat == seat and Used(t) < click then
				return Pend(t, { kind = "KT", from = sender, step = step, chain = chain, ev = ev, notBefore = Clock() + (click - Used(t)) })
			end
		end
	elseif kind == "v" then
		if fromArbiter then ev = { t = "V" }
		elseif senderSeat then
			t.otherVoid = true
			if t.voteVoid then ev = { t = "V" } else Changed(t) return end
		else return end
	else
		return
	end
	Offer(t, { kind = "KT", from = sender, step = step, chain = chain, ev = ev, awaySeat = kind == "g" and seat or nil })
end
ns.Comm.Handle("KT", ns.Arena.Handle("KT", OnClaim))

-- KL: the arbiter's floor (the design), on a hiccup table only.
local function OnFloor(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local f = Split(body)
	local t = tables[f[1] or ""]
	if not t or t.mode ~= mode or not t.game or not t.hic or not t.arbiter or not Same(sender, t.arbiter) or t.role == "arbiter" then return end
	local seat, turn, lvl = tonumber(f[2] or ""), N36(f[3] or "", 1, 1000), tonumber(f[4] or "")
	if (seat ~= 1 and seat ~= 2) or not turn or not lvl or lvl < 0 or lvl > 3 or lvl ~= floor(lvl) then return end
	ApplyItem(t, { kind = "KL", from = sender, seat = seat, turn = turn, lvl = lvl })
end
ns.Comm.Handle("KL", ns.Arena.Handle("KL", OnFloor))

-- KE: a participant's result (compared with ours; the agreement of the design). The bank of a wallet
-- table hears it too.
local function OnEnd(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local f = Split(body)
	local id = f[1] or ""
	local t = tables[id]
	local res, hash = f[2], f[6]
	if (res ~= "1" and res ~= "2" and res ~= "v" and res ~= "x") or type(hash) ~= "string" or not hash:find("^%x%x%x%x%x%x%x%x$") then return end
	if not t then
		-- the bank of a wallet table keeps its KEs: who the arbiter and the players are it reads
		-- from the table's FK market sheet (its opener, the arbiter, and its parties), never from
		-- a KE
		if not ValidId(id) or not Call("Markets", "Has", id) then return end
		local v = Call("Markets", "View", id)
		local arb = type(v) == "table" and type(v.opener) == "string" and A().Name(v.opener) or nil
		local parties = type(v) == "table" and type(v.parties) == "table" and v.parties or {}
		local host, guest = A().Name(parties[1] or ""), A().Name(parties[2] or "")
		if not arb or not host or not guest then return end
		t = { id = id, mode = mode, role = "bank", state = "end", ke = {}, created = Now(), arbiter = arb, host = host, guest = guest,
			players = { host, guest }, src = {}, spec = {}, log = {} }
		tables[id] = t
	end
	if t.mode ~= mode then return end
	local who = Full(sender):lower()
	if not (IsPlayer(t, sender) or (t.arbiter and Same(sender, t.arbiter))) then return end
	t.ke = t.ke or {}
	t.ke[who] = { res = res, hash = hash, s1 = N36(f[3] or "", 0), s2 = N36(f[4] or "", 0), steps = N36(f[5] or "", 0), ld = N36(f[7] or "", 0, 5000) or 0,
		sig = f[8], at = Clock() }
	if t.arbiter and Same(sender, t.arbiter) then t.ke[who].arbiter = true end
	if t.role == "bank" then
		local ag = FT.Agreement(id)
		if ag and ag.agreed then ns.Fire("FARKLE_AGREED", id, ag.result) end
		return
	end
	local mine = t.ke[Me():lower()]
	if mine and mine.hash ~= hash then
		t.differs = t.differs or {}
		t.differs[who] = true
		Say(t, "FARKLE_LOG_KE_DIFFERS", ns.DisplayName(sender))
	end
	if t.state == "end" and not t.settled then Settle(t) end
	Changed(t)
end
ns.Comm.Handle("KE", ns.Arena.Handle("KE", OnEnd))

-- KQ: a participant fell behind (or a watcher asks to watch): the events from a step.
local function OnResync(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local f = Split(body)
	local t = tables[f[1] or ""]
	if not t or t.mode ~= mode or not t.game then return end
	local from = N36(f[2] or "", 0, 5000)
	if not from then return end
	local participant = IsPlayer(t, sender) or (t.arbiter and Same(sender, t.arbiter))
	if not participant then
		-- a watcher (the design): a player who allowed watchers, or a public table's arbiter
		if not Relayer(t) then return end
		t.watchers = t.watchers or {}
		local n = 0
		for _ in pairs(t.watchers) do n = n + 1 end
		if not t.watchers[Full(sender):lower()] and n >= FT.WATCHERS_MAX then return end
		t.watchers[Full(sender):lower()] = Clock()
		t.lastState = nil
		SendState(t)
		return
	end
	t.answered = t.answered or {}
	local key = Full(sender):lower()
	if t.answered[key] and Clock() - t.answered[key] < FT.RESYNC_GAP then return end
	t.answered[key] = Clock()
	local g = t.game
	local codes = {}
	for i = from + 1, g.step do codes[#codes + 1] = (g.events[i]:gsub("%*$", "")) end
	local i, step = 1, from
	repeat
		local part = {}
		for j = i, min(#codes, i + FT.KR_CODES - 1) do part[#part + 1] = codes[j] end
		Send(t, "KR", ("%s~%s~%s"):format(t.id, B36(step), table.concat(part, ",")), sender, { urgent = true })
		step = step + #part
		i = i + FT.KR_CODES
	until i > #codes
end
ns.Comm.Handle("KQ", ns.Arena.Handle("KQ", OnResync))

-- KR: the answer to our KQ (its rolls marked relayed; compared where we wrote our own).
local function OnReplay(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local f = Split(body)
	local t = tables[f[1] or ""]
	if not t or t.mode ~= mode or not t.game or not t.resync or not Same(t.resync.to, sender) then return end
	local step = N36(f[2] or "", 0, 5000)
	if not step then return end
	local codes = {}
	for code in (f[3] or ""):gmatch("[^,]+") do codes[#codes + 1] = code end
	if #codes > FT.KR_CODES or table.concat(codes, ",") ~= (f[3] or "") then return end
	-- Replay also reads saved historical penalties. A live relay must never introduce one,
	-- even through a divergent record: reject the whole batch before applying any prefix.
	local senderSeat = SeatOf(t, sender)
	local fromArbiter = t.arbiter and Same(sender, t.arbiter)
	local choices, seenChoices = { {}, {} }, { 0, 0 }
	for i, own in ipairs(t.game.events) do
		local ev = R().Event(own)
		if ev and ev.t == "K" then
			local list = choices[ev.p]
			list[#list + 1] = own
			if i <= step then seenChoices[ev.p] = seenChoices[ev.p] + 1 end
		end
	end
	for i, code in ipairs(codes) do
		local ev = R().Event(code)
		if not ev or ev.t == "F" or (ev.t == "H" and t.game.hiccupRule == "bones2") then return end
		-- A peer may witness our server rolls, but cannot choose our dice or bank for us.
		-- Previously recorded decisions can travel in an honest prefix; new or changed
		-- decisions belong to the sending seat (or the table's arbiter).
		local own = t.game.events[step + i]
		local matches = own and own:gsub("%*$", "") == code:gsub("%*$", "")
		if ev.t == "K" then
			seenChoices[ev.p] = seenChoices[ev.p] + 1
			local choice = choices[ev.p][seenChoices[ev.p]]
			-- Witnessed server rolls can shift event indexes (W4). Compare each seat's
			-- decisions in their own order, rather than at the same transcript step.
			local following = R().Event(codes[i + 1] or "")
			local bankRoll = ev.p == t.seat and t.bankRolls and t.bankRolls[seenChoices[ev.p]]
			-- At a packet boundary the next part carries the roll; our local server
			-- observation already proves the bank must read as rolling on.
			local witnessed = choice and choice:gsub(":b", ":r", 1) == code and bankRoll
				and (not following or (following.t == "R" and following.p == ev.p
					and bankRoll == R().Code({ t = "R", p = following.p, k = following.k, value = following.value })))
			if choice ~= code and not witnessed and (ev.p == t.seat or (not fromArbiter and ev.p ~= senderSeat)) then return end
		end
		-- A concession is the named player's decision too. The only other way to
		-- concede our seat is an observed departure after the same local grace as KT.
		if ev.t == "C" and ev.p == t.seat and not matches then
			local since = t.away and t.away[ev.p]
			if not since or not Away(t, ev.p) or Clock() - since < FT.TAVERN_GRACE then return end
		end
	end
	FT.Note("%s resync: KR from %s, %d events from step %d", t.id, tostring(sender), #codes, step)
	TakeRelay(t, sender, step, codes)
	t.resync.at = nil
	TryPending(t)
	Changed(t)
end
ns.Comm.Handle("KR", ns.Arena.Handle("KR", OnReplay))

-- KS: a relayed state (a public table's arbiter on the channel, or a player to his watchers).
local function OnState(dist, sender, mode, body)
	local f = Split(body)
	local id = f[1] or ""
	local t = tables[id]
	local n = notices[id]
	if not ValidId(id) then return end
	local ok = false
	if n and n.official and Same(sender, n.arbiter) and ns.ArenaRoles.IsPublicArbiter(sender, mode) then ok = true end
	if n and not n.official and (Same(sender, n.p1) or Same(sender, n.p2)) then ok = true end
	if not ok then return end
	if not t or t.role ~= "watch" then return end
	local digits = f[7] or "-"
	local faces, kept = digits:match("^(%d*)%.?(%d*)$")
	local dice = {}
	for d in (faces or ""):gmatch("%d") do dice[#dice + 1] = tonumber(d) end
	local keptList = {}
	for d in (kept or ""):gmatch("%d") do keptList[#keptList + 1] = tonumber(d) end
	local lv, sk = f[10] or "00", f[11] or "22"
	local s = { s1 = N36(f[2] or "", 0) or 0, s2 = N36(f[3] or "", 0) or 0, cur = tonumber(f[4] or "") or 0, turnPts = N36(f[5] or "", 0) or 0,
		left = tonumber(f[6] or "") or 0, dice = dice, kept = keptList, phase = f[8] or "roll", step = N36(f[9] or "", 0) or 0,
		lv = { tonumber(lv:sub(1, 1)) or 0, tonumber(lv:sub(2, 2)) or 0 }, sk = { tonumber(sk:sub(1, 1)) or 0, tonumber(sk:sub(2, 2)) or 0 },
		by = Full(sender), at = Now() }
	if t.snap and s.step < t.snap.step then return end
	t.prev, t.snap = t.snap, s
	Emit(t, { t = "state", state = s, prev = t.prev })
	Changed(t)
end
ns.Comm.Handle("KS", ns.Arena.Handle("KS", OnState))

-- Room for a new table's notice from this sender (1.2.1: anyone may announce a table naming
-- himself, so made-up ids grew the list without end): FT.NOTICES_EACH from him at most and
-- FT.NOTICES_MAX in all, the oldest heard going first (a live table's KN comes again every
-- minute, so it is not the oldest for long). A table this client watches or sits at keeps its
-- notice and takes none of its sender's room (a fan who watched three of one host's games, never
-- pressing Stop watching, still hears his next); it counts towards FT.NOTICES_MAX. false: no room
-- (every notice that could go is such a table's). (heard: the order notices were last heard in,
-- so two in the same second still have an oldest)
local heard = 0
local function NoticeRoom(sender)
	local by = (Full(sender) or ""):lower()
	local his, all, hisOldest, oldest = 0, 0, nil, nil
	for id, n in pairs(notices) do
		all = all + 1
		local free = tables[id] == nil
		if free and (n.by or ""):lower() == by then
			his = his + 1
			if not hisOldest or n.heard < notices[hisOldest].heard then hisOldest = id end
		end
		if free and (not oldest or n.heard < notices[oldest].heard) then oldest = id end
	end
	if his >= FT.NOTICES_EACH then
		notices[hisOldest] = nil
	elseif all >= FT.NOTICES_MAX then
		if not oldest then return false end
		notices[oldest] = nil
	end
	return true
end

-- A half in a KN's fields (1.2.3: the end of a game that counts, its result, start and seat after
-- the end's eight fields, then its key and signature, "-" for none), or nil when it is none or out
-- of shape.
local function NoticeHalf(f, id, p1, p2, mode)
	if #f ~= 18 then return nil end
	local w, how, hash, seat = f[8], f[11], f[13], tonumber(f[16] or "")
	if (w ~= "1" and w ~= "2") or not FT.WHY_OF[how or ""] or how == "v" or (seat ~= 1 and seat ~= 2) then return nil end
	if type(hash) ~= "string" or not hash:find("^%x%x%x%x%x%x%x%x$") then return nil end
	local s1, s2 = N36(f[9] or "", 0, 1000000), N36(f[10] or "", 0, 1000000)
	local steps, t, began = N36(f[12] or "", 1, 5000), N36(f[14] or "", 0, 4294967295), N36(f[15] or "", 0, 4294967295)
	if not (s1 and s2 and steps and t and began) then return nil end
	local pk, sig = f[17], f[18]
	if pk == "-" and sig == "-" then
		pk, sig = nil, nil
	elseif not (#pk == 43 and pk:find("^[%w%-_]+$") and #sig == 86 and sig:find("^[%w%-_]+$")) then
		return nil
	end
	return { id = id, p1 = p1, p2 = p2, seat = seat, w = w, s1 = s1, s2 = s2, how = how, steps = steps, hash = hash:lower(), t = t, began = began,
		tc = tonumber(f[5] or ""), mode = mode, pk = pk, sig = sig, core = table.concat(f, "~", 1, 16), body = table.concat(f, "~") }
end

-- Relayed halves' signatures, checked in Ed25519.lua's time slices, HALVES_CHECKS at once (a relay
-- past them is dropped: its players say the game again at later logins). cb(good) once known.
HV.checking, HV.checks = {}, 0
function HV.CheckSig(key, pk, msg, sig, cb)
	local Ed = ns.Ed25519
	if HV.checking[key] or HV.checks >= FT.HALVES_CHECKS or not pk or not sig or type(Ed) ~= "table" or type(Ed.Run) ~= "function" then return false end
	HV.checking[key], HV.checks = true, HV.checks + 1
	local started = Ed.Run(function() return Ed.Verify(pk, msg, sig) end, function(ok, res)
		HV.checking[key], HV.checks = nil, HV.checks - 1
		cb(ok == true and res == true)
	end)
	if not started then HV.checking[key], HV.checks = nil, HV.checks - 1 end
	return started == true
end
-- Whether this client holds a word of that half's player on its game already (the same or not: a
-- relay can then change nothing, and needs no check).
function HV.HeldAlready(b, h)
	if not b then return false end
	local key = HalfKey(h.id, h.p1, h.p2)
	if b.done[key] ~= nil then return true end
	local e, who = b.open[key], Low(h.seat == 1 and h.p1 or h.p2)
	return type(e) == "table" and type(e.by) == "table" and e.by[who or ""] ~= nil
end
-- A half heard (KN "e"): its own player's taken at once; the game's other player's relay only on
-- the channel, with the key this client holds for the half's player and its signature good.
local function HearHalf(dist, sender, h)
	local player = h.seat == 1 and h.p1 or h.p2
	if Same(sender, player) then return TakeHalf(sender, h) end
	if dist ~= "CHANNEL" then return false, "lane" end
	local b = RankStore(false)
	if HV.HeldAlready(b, h) then return TakeHalf(sender, h) end
	local pin = HV.PinOf(b, player)
	-- (1.2.4: or any key the half's player declared to this client himself, RK: the shared records')
	if not (pin and h.pk == pin) and Call("Records", "HasKey", player, h.pk) == true then pin = h.pk end
	if not pin or h.pk ~= pin or not h.sig then return false, "pin" end
	local ok = HV.CheckSig(h.body, HV.Raw(pin, 32), "OLYB1|" .. h.core, HV.Raw(h.sig, 64), function(good)
		if good then TakeHalf(sender, h) end
	end)
	return ok, ok and "checking" or "busy"
end

-- KN: a table announced (a public arbiter's, raising the alert; or a player's who allows watchers).
-- (1.2.3: or a player's half of a game that counts, the ranking's word: on the channel, its own
-- player's or relayed by the game's other player; or whispered by the other player of this
-- client's own game, never to a client not at the game: what every member counts, every member
-- can hear. Kept whether or not the table was listed here.)
local function OnNotice(dist, sender, mode, body)
	local f = Split(body)
	local id = f[1] or ""
	if not ValidId(id) then return end
	local p1, p2, arb = A().Name(f[2] or ""), A().Name(f[3] or ""), f[4] ~= "-" and A().Name(f[4] or "") or nil
	if not p1 or not p2 then return end
	local official = arb ~= nil and Same(sender, arb) and ns.ArenaRoles.IsPublicArbiter(sender, mode)
	if not official and not (Same(sender, p1) or Same(sender, p2)) then return end
	if Hides(sender) then return end
	-- (1.2.4: the other player of this player's game asks for his half: whispered alone, answered so)
	if f[7] == "h" then
		if dist == "WHISPER" and not arb then HV.Answer(sender, id, p1, p2) end
		return
	end
	local half = f[7] == "e" and not arb and NoticeHalf(f, id, p1, p2, mode) or nil
	if half and (dist ~= "WHISPER" or Same(Me(), p1) or Same(Me(), p2)) then HearHalf(dist, sender, half) end
	-- (a whisper brings a half alone: the live list is the channel's)
	if dist == "WHISPER" then return end
	local was = notices[id]
	-- (the end of a table never listed here: nothing to take off the list, nothing to keep)
	if f[7] == "e" and not was and not official then return end
	if not was and not NoticeRoom(sender) then return end
	notices[id] = { id = id, p1 = p1, p2 = p2, arbiter = arb, official = official, target = R().TARGET_BY_CODE[tonumber(f[5] or "")] or 5000,
		map = N36(f[6] or "", 1), state = f[7] == "e" and "e" or "o", winner = tonumber(f[8] or ""), by = Full(sender), mode = mode, at = Now(),
		heard = heard + 1, counts = f[7] ~= "e" and f[9] == "c" or nil }
	heard = heard + 1
	if official and not was then ns.Fire("FARKLE_PUBLIC", id, "open") end
	FT.KeepNotice(notices[id])
	A().Changed()
end
ns.Comm.Handle("KN", ns.Arena.Handle("KN", OnNotice))

-- A public table's event, kept where its crowd's market involves this client (the bank, a bettor:
-- Markets.Involved). KN stops as the table closes, which is when its arbiter declares, and every
-- rev of the sheet needs the event (Markets.CheckSheet): a bank that reloads or comes back then
-- still knows it. Players and arbiter only, never a stake; KEEP_NOTICE at most (FT.Prune); never on
-- a client the market does not involve (the weight rule).
function FT.KeepNotice(n)
	if type(n) ~= "table" or not (n.official and n.arbiter) then return false end
	local rec = Call("Markets", "Find", n.id, n.mode)
	if type(rec) ~= "table" or Call("Markets", "Involved", rec) ~= true then return false end
	local m = Mine(n.mode)
	if not m then return false end
	if type(m.kept) ~= "table" then m.kept = {} end
	local k = m.kept[n.id]
	if type(k) == "table" and k.p1 == n.p1 and k.p2 == n.p2 and k.arbiter == n.arbiter then return true end
	m.kept[n.id] = { p1 = n.p1, p2 = n.p2, arbiter = n.arbiter, at = Now() }
	return true
end
-- The kept event as a notice (official: only a public arbiter's is kept), or nil.
local function KeptNotice(id)
	for _, mode in ipairs({ "L", "T" }) do
		local m = Peek(mode)
		local k = m and type(m.kept) == "table" and m.kept[id]
		if type(k) == "table" and type(k.p1) == "string" and type(k.p2) == "string" and type(k.arbiter) == "string" then
			return { id = id, p1 = k.p1, p2 = k.p2, arbiter = k.arbiter, official = true, mode = mode }
		end
	end
	return nil
end

-- KD: a payment's receipt (the design): the creditor's "r" clears the debtor's obligation.
local function OnReceipt(dist, sender, mode, body)
	if dist ~= "WHISPER" then return end
	local f = Split(body)
	local t = tables[f[1] or ""]
	if not t or t.mode ~= mode or not t.seat or not IsPlayer(t, sender) then return end
	local copper = N36(f[3] or "", 1, A().COPPER_MAX)
	if not copper or (f[4] ~= "t" and f[4] ~= "m") then return end
	if f[2] == "r" and t.game and t.game.winner and t.game.winner ~= t.seat and Same(sender, t.players[t.game.winner]) then
		Call("Debts", "Paid", Ref(t), copper, f[4])
		local l = Line(t, "pay")
		if l then l.cleared = (l.cleared or 0) + copper end
		Changed(t)
	elseif f[2] == "p" then
		t.theyPaid = (t.theyPaid or 0) + copper
		Changed(t)
	end
end
ns.Comm.Handle("KD", ns.Arena.Handle("KD", OnReceipt))

---------------------------------------------------------------------------
-- Watching (the design): the live tables from the notices; a watcher asks the relayer (KQ) and gets KS
---------------------------------------------------------------------------

-- (1.2.3: each row a copy of its notice, mode L where the announcing player says his game counts,
-- so the screens give it no rehearsal's tag; wire: the mode its messages travel in, which Watch
-- uses from the notice itself.)
function FT.LiveTables()
	local out = {}
	local cut = Now() - 3 * FT.NOTICE_EVERY
	for id, n in pairs(notices) do
		if n.state == "o" and n.at >= cut then
			local row = {}
			for k, v in pairs(n) do row[k] = v end
			row.wire, row.mode = n.mode, n.counts and "L" or n.mode
			out[#out + 1] = row
		end
	end
	table.sort(out, function(a, b)
		if a.official ~= b.official then return a.official end
		return a.at > b.at
	end)
	return out
end

function FT.Watch(id)
	local n = notices[id]
	if not n then return false, "gone" end
	if tables[id] and tables[id].role ~= "watch" then return false, "mine" end
	local relayer = n.official and n.arbiter or n.by
	local t = tables[id] or { id = id, mode = n.mode, role = "watch", players = { n.p1, n.p2 }, host = n.p1, guest = n.p2, arbiter = n.arbiter,
		target = n.target, created = Now(), src = {}, spec = {}, log = {}, official = n.official }
	t.relayer, t.askedAt = relayer, Clock()
	tables[id] = t
	A().Involve("watch:" .. id, true)
	Watch()
	A().Every(1, "farkle", function() Tick() end)
	A().Send("KQ", n.mode, ("%s~0"):format(id), { to = relayer })
	Changed(t, "watch")
	return true
end
-- The live table a player sits at that this client may watch (its players allow watchers, or its
-- arbiter is public: it is in the live list), or nil: the right-click "Watch Bones" (D).
function FT.Watchable(name)
	if type(name) ~= "string" then return nil end
	for _, n in ipairs(FT.LiveTables()) do
		if Same(n.p1, name) or Same(n.p2, name) then return n.id end
	end
	return nil
end
function FT.StopWatching(id)
	local t = tables[id]
	if not t or t.role ~= "watch" then return false end
	tables[id] = nil
	A().Involve("watch:" .. id, false)
	A().Changed()
	return true
end

---------------------------------------------------------------------------
-- The Bones ranking (1.2.3): the month's best players from the games both players' halves agree on
-- (the halves above), the honours' source (ArenaHome's Data.GamesRanking("bones"))
---------------------------------------------------------------------------

-- The ledger's caps, ArenaLedger's own where it is loaded (FT.RANK_CAPS otherwise).
local function RankCap(k)
	local LG = rawget(ns, "ArenaLedger") or ns.ArenaLedger
	return type(LG) == "table" and tonumber(LG[k]) or FT.RANK_CAPS[k]
end
-- Who the ranking leaves out here: a name moderation hides, one this player blocked. (A timeout
-- from the games, Arena.Sanctioned, stops his play, not his games played: they stay.)
function HV.RankHides(name)
	local M = ns.Moderation
	if M and not M.missing and M.Hides and M.Hides(name) then return true end
	local blocked = ns.db and ns.db.blocked
	return type(blocked) == "table" and blocked[Low(name) or ""] ~= nil
end
-- What Best's list rests on besides the games: a moderation word or a verified key heard (who is
-- hidden, who is one owner's: Debts.SameOwner), the alt links (Alts.Version), the blocked list.
HV.word = 0
for _, event in ipairs({ "NETOFF_CHANGED", "NETOFF_TIMED_CHANGED", "ARENA_KEY" }) do
	ns.On(event, function() HV.word = HV.word + 1 end)
end
function HV.Context()
	local Alts = ns.Alts
	local alts = type(Alts) == "table" and type(Alts.Version) == "function" and Alts.Version() or 0
	local blocked = 0
	for _ in pairs(type(ns.db) == "table" and type(ns.db.blocked) == "table" and ns.db.blocked or {}) do blocked = blocked + 1 end
	return ("%d:%d:%s:%d"):format(HV.gen, HV.word, tostring(alts), blocked)
end
-- [month] = { ctx, rows }: worked out again only when a game, a moderation word, a key, an alt
-- link or the blocked list changed (no clock: an open Games tab costs nothing while none did).
local bestCache = {}
function FT.Best(mode, opts)
	opts = type(opts) == "table" and opts or {}
	if (mode or "L") ~= "L" then return {} end
	local b = RankStore(false)
	if not b then return {} end
	local month = tonumber(opts.month) or MonthOf(Now(), opts.offset)
	local ctx = HV.Context()
	-- (opts.all, 1.2.4: the month's totals for its seal, Records.lua: nobody left out for being
	-- hidden or blocked here, a view of this client's own; never kept as the list)
	local keep = opts.offset == nil and not opts.all
	local cached = keep and bestCache[month]
	if cached and cached.ctx == ctx then return cached.rows, cached.held end
	-- every game both halves agree on, its players hidden by nobody here and never one owner's
	-- characters (the alt check, Debts.SameOwner); held (1.2.4): the agreed games the month's list
	-- reads, whoever played: the month's own and the PAIR_DAYS before it (the pair cap's)
	local games, hidden, same, held = {}, {}, {}, 0
	local minDur, dayMax, pairMax, pairSecs = RankCap("MIN_RATED_DUR"), RankCap("DAY_MAX"), RankCap("PAIR_MAX"), RankCap("PAIR_DAYS") * 86400
	local function Hidden(name, k)
		if opts.all then return false end
		if hidden[k] == nil then hidden[k] = HV.RankHides(name) end
		return hidden[k]
	end
	local done = {}
	for key, value in pairs(b.done) do done[key] = value end
	local records = ns.Records
	if records and not records.missing and records.Bodies and records.MonthStart then
		for _, body in ipairs(records.Bodies("b", floor(records.MonthStart(month) / 86400) - RankCap("PAIR_DAYS"), floor(records.MonthStart(month + 1) / 86400))) do
			local rec = FT.ReadRecord(body)
			if rec and not done[rec.id] then done[rec.id] = HV.DoneLine(rec.done) end
		end
	end
	for key, s in pairs(done) do
		local r = HV.ReadDone(s)
		if r and (MonthOf(r.t, opts.offset) == month or MonthOf(r.t + pairSecs, opts.offset) == month) then held = held + 1 end
		local a, c = r and Low(r.p1), r and Low(r.p2)
		if a and c and a ~= c and not Hidden(r.p1, a) and not Hidden(r.p2, c) then
			local pk = a < c and (a .. "|" .. c) or (c .. "|" .. a)
			if same[pk] == nil then same[pk] = Call("Debts", "SameOwner", r.p1, r.p2) == true end
			if not same[pk] then
				games[#games + 1] = { key = key, p1 = r.p1, p2 = r.p2, a = a, c = c, pk = pk, w = r.w, t = r.t, dur = r.dur, at = r.at }
			end
		end
	end
	-- the ledger's caps, as ArenaLedger.Counted applies them to rated fights, over every game held
	-- (the last days of the month before count towards the pair's), in the order this client came to
	-- hold both halves of each (its time breaking a tie): a game told late may be capped itself, but
	-- never pushes out one counted before it (games dated back into a day already counted); a game's
	-- day, pair window and month are its own time's. Then the month's games alone.
	table.sort(games, function(x, y)
		if x.at ~= y.at then return x.at < y.at end
		if x.t ~= y.t then return x.t < y.t end
		return x.key < y.key
	end)
	local day, pairs_, rows, byKey = {}, {}, {}, {}
	for _, x in ipairs(games) do
		local d = floor(x.t / 86400)
		local da, dc = x.a .. "|" .. d, x.c .. "|" .. d
		local ok = x.dur >= minDur and (day[da] or 0) < dayMax and (day[dc] or 0) < dayMax
		if ok then
			local recent = 0
			for _, at in ipairs(pairs_[x.pk] or {}) do if abs(x.t - at) < pairSecs then recent = recent + 1 end end
			ok = recent < pairMax
		end
		if ok then
			day[da], day[dc] = (day[da] or 0) + 1, (day[dc] or 0) + 1
			pairs_[x.pk] = pairs_[x.pk] or {}
			table.insert(pairs_[x.pk], x.t)
			if MonthOf(x.t, opts.offset) == month then
				for seat, name in ipairs({ x.p1, x.p2 }) do
					local k = seat == 1 and x.a or x.c
					local r = byKey[k]
					if not r then
						r = { name = name, key = k, games = 0, won = 0, lost = 0 }
						byKey[k], rows[#rows + 1] = r, r
					end
					r.games = r.games + 1
					if x.w == tostring(seat) then r.won, r.at = r.won + 1, max(r.at or 0, x.t) else r.lost = r.lost + 1 end
				end
			end
		end
	end
	-- most wins; a tie to fewer games, then to who reached his wins first, then by name
	table.sort(rows, function(x, y)
		if x.won ~= y.won then return x.won > y.won end
		if x.games ~= y.games then return x.games < y.games end
		local ax, ay = x.at or math.huge, y.at or math.huge
		if ax ~= ay then return ax < ay end
		return x.key < y.key
	end)
	for i, r in ipairs(rows) do r.place = i end
	if keep then bestCache[month] = { ctx = ctx, rows = rows, held = held } end
	return rows, held
end

---------------------------------------------------------------------------
-- Practice against the House (the design): the player's own server rolls, the House's local dice
-- (marked simulated), FarkleRules.HouseMove. Nothing is sent.
---------------------------------------------------------------------------

-- In a lesson, show each scoring set before the lone 1s and 5s. Runs and other picks
-- that cannot be split for the same points stay together; the decision itself is unchanged.
local function HouseLessonGroups(dice, pick)
	local faces, byFace, groups = {}, {}, {}
	for _, p in ipairs(pick) do
		local face = dice[p]
		faces[#faces + 1] = face
		byFace[face] = byFace[face] or {}
		byFace[face][#byFace[face] + 1] = p
	end
	for face = 1, 6 do
		local positions = byFace[face]
		if positions and #positions >= 3 then groups[#groups + 1] = positions end
	end
	for face = 1, 6 do
		local positions = byFace[face]
		if positions and #positions < 3 then
			for _, p in ipairs(positions) do groups[#groups + 1] = { p } end
		end
	end
	local total = 0
	for _, group in ipairs(groups) do
		local part = {}
		for _, p in ipairs(group) do part[#part + 1] = dice[p] end
		local points = R().Score(part)
		if not points then return { pick } end
		total = total + points
	end
	if total ~= R().Score(faces) then return { pick } end
	return groups
end

local function HouseStep(t)
	if t.closed or not t.game or t.game.over then t.houseDue = nil; return end
	if t.inn and select(2, FT.Innkeeper()) ~= t.inn then
		return ns.After(1, "Bones keeper waits", function() HouseStep(t) end)
	end
	if FT.busy(t.id) then return ns.After(0.2, "farkle house", function() HouseStep(t) end) end
	local g = t.game
	local who, phase = R().Expect(g)
	if who ~= 2 then t.houseDue = nil; return end
	local gen = t.gen
	local function Later(sec, fn)
		local function Continue()
			if t.gen ~= gen or t.closed then return end
			if t.inn and select(2, FT.Innkeeper()) ~= t.inn then
				return ns.After(1, "Bones keeper waits", Continue)
			end
			if FT.busy(t.id) then return ns.After(0.2, "farkle house", Continue) end
			fn()
		end
		ns.After(sec, "farkle house", Continue)
	end
	if phase == "keep" then
		local pick, act = R().HouseMove(g)
		if not pick then t.houseDue = nil; return end
		local function Keep()
			-- a decision the House makes writes the player's own level (the design: his "You feel" lines count here)
			local lvl = NewsFor(t, 2)
			t.houseDue = nil
			Apply(t, { t = "K", p = 2, mask = pick, act = act, lvl = lvl }, "house")
			t.news = nil
		end
		if t.learn then
			local groups, shown, index = HouseLessonGroups(g.turn.dice, pick), {}, 0
			local function Consider()
				index = index + 1
				for _, p in ipairs(groups[index]) do shown[#shown + 1] = p end
				local mask = {}
				for i, p in ipairs(shown) do mask[i] = p end
				Emit(t, { t = "consider", seat = 2, mask = mask })
				return Later(1.4, index < #groups and Consider or Keep)
			end
			return Later(1, Consider)
		end
		Emit(t, { t = "consider", seat = 2, mask = pick })
		return Later(FT.HOUSE_PAUSE.think, Keep)
	end
	if phase == "roll" or phase == "decide" then
		local left = g.turn.left
		Emit(t, { t = "rolling", seat = 2, hi = R().RANGES[left] })
		return Later(FT.HOUSE_PAUSE.roll, function()
			local value = math.random(1, R().RANGES[left])
			t.houseDue = nil
			Apply(t, { t = "R", p = 2, k = left, value = value }, "house")
		end)
	end
	if phase == "hiccup" then
		-- (the House never drinks: this does not come; a roll decides it anyway)
		return Later(FT.HOUSE_PAUSE.roll, function()
			t.houseDue = nil
			Apply(t, { t = "H", p = 2, value = math.random(1, R().OPENING) }, "house")
		end)
	end
end

-- The House's next move, once: after the player's own move (Progress) and its own.
function FT.PracticeStep(t)
	if t.closed or not t.game then return end
	if t.game.over then return Finished(t) end
	local who = R().Expect(t.game)
	if who == 2 and not t.houseDue then
		t.houseDue = true
		local gen = t.gen
		ns.After(FT.HOUSE_PAUSE.next, "farkle house", function()
			if t.gen == gen and not t.closed then HouseStep(t) end
		end)
	end
end

function FT.Practice(opts)
	opts = opts or {}
	local keeper, inn = FT.Innkeeper()
	if not keeper and not A().Sim() then return nil, "training_inn" end
	if InCombatLockdown and InCombatLockdown() then return nil, "combat" end
	for _, x in pairs(tables) do if x.role == "practice" and not x.closed then x.closed = true x.gen = (x.gen or 0) + 1 tables[x.id] = nil end end
	if FT.Live() and not opts.force then return nil, "busy" end
	practiceN = practiceN + 1
	local target = tonumber(opts.target) or R().TARGET
	if not FT.TrainingComplete() and not A().Sim() then target = R().TARGETS[1] end
	if not R().TARGET_CODE[target] then return nil, "target" end
	local id = "P" .. B36(practiceN)
	local first = opts.first
	if first ~= 1 and first ~= 2 then
		local o = FT.Opts()
		if opts.learn == true or not FT.TrainingComplete() then first = 2
		else first = o.practiceFirst == 1 and 2 or 1 end
		o.practiceFirst = first
	end
	local t = { id = id, role = "practice", mode = "T", host = Me(), guest = keeper or L.FARKLE_HOUSE, inn = inn, kind = "d", stake = 0, target = target,
		secs = FT.SECS, hic = OwnDrunkReadable(), hiccupRule = "bones2", src = { "-", "-" }, spec = { false, false }, created = Now(), state = "play", seat = 1,
		first = first, gen = 1, log = {}, learn = (opts.learn == true or not FT.TrainingComplete()) or nil }
	t.players = { Me(), t.guest }
	if not NewGame(t) then return nil, "rules" end
	tables[id] = t
	Involve(t, true)
	Watch()
	Changed(t, "play")
	FT.PracticeStep(t)
	return id
end

-- Closes a practice (the board's X, or a new one).
function FT.Close(id)
	local t = tables[id]
	if not t then return false end
	if t.role == "practice" then
		t.closed = true
		t.gen = (t.gen or 0) + 1
		tables[id] = nil
		Involve(t, false)
		A().Changed()
		return true
	end
	if not LIVE[t.state] then
		tables[id] = nil
		A().Involve("table:" .. id, false)
		A().Changed()
		return true
	end
	return false
end

---------------------------------------------------------------------------
-- The self-test (/oly farkle test): one /roll 46656, read back
---------------------------------------------------------------------------

function FT.SelfTest() -- gp:arena-clicks
	selftest = { at = Clock() }
	Watch()
	A().Involve("farkle:test", true)
	A().After(20, "farkle:test", function()
		if selftest then
			selftest = nil
			lastSelfTest = { none = true, at = Now() }
			ns.Print(L.FARKLE_TEST_NONE)
		end
		A().Involve("farkle:test", false)
	end)
	local ok = pcall(RandomRoll, 1, 46656)
	if not ok then ns.Print(L.FARKLE_TEST_REFUSED) end
	ns.Print(L.FARKLE_TEST_ASKED)
	return ok
end
function FT.SelfTestLine(name, value, lo, hi)
	selftest = nil
	A().Involve("farkle:test", false)
	local dice = R().Decode(value, 6) or {}
	local matched = LineIs(name, Me())
	lastSelfTest = { name = name, value = value, lo = lo, hi = hi, dice = dice, match = matched, at = Now() }
	local text = L.FARKLE_TEST_RESULT:format(name, lo, hi, value, table.concat(dice, " "), matched and L.FARKLE_YES or L.FARKLE_NO, tostring(Me()))
	ns.Print(text)
	if ns.UI and ns.UI.ShowCopy then ns.SafeCall("farkle test copy", ns.UI.ShowCopy, L.FARKLE_TEST_TITLE, text) end
	return lastSelfTest
end
function FT.LastSelfTest() return lastSelfTest end

---------------------------------------------------------------------------
-- The screens' model
---------------------------------------------------------------------------

function FT.View(id)
	local t = id and tables[id] or FT.Live()
	if not t then
		for _, x in pairs(tables) do if x.role == "practice" and not x.closed then t = x end end
	end
	if not t then return nil end
	local v = { id = t.id, role = t.role, mode = t.mode, kind = t.kind, stake = t.stake or 0, cur = t.cur, target = t.target, secs = t.secs,
		hic = t.hic, hiccupRule = t.hiccupRule, state = t.state, arbiter = t.arbiter, players = { t.players[1], t.players[2] }, seat = t.seat, src = t.src, spec = t.spec,
		public = t.arbiter ~= nil and ns.ArenaRoles.IsPublicArbiter(t.arbiter, t.mode) or false, log = t.log, blind = t.blind,
		needGroup = t.needGroup, tavernWhy = t.tavernWhy, why = t.why, disputed = t.disputed, lower = t.lower, ld = t.ld,
		lines = t.lines, held = t.held, settled = t.settled, holdWhy = t.holdWhy, graceUntil = t.graceUntil, rehearsal = A().Sim() and t.mode == "T" and t.role ~= "practice",
		practice = t.role == "practice", learn = t.learn == true, watching = t.role == "watch", relayer = t.relayer, received = t.received, rolling = t.rolling,
		crowd = t.crowd == true, crowdOpen = t.crowdOpen, crowdWhy = t.crowdWhy, crowdLock = CrowdLock(t), noWatch = t.noWatch == true,
		crowdWait = t.state == "stakes" and t.crowd == true and not Holds(t) or nil }
	-- (the bets' seconds left, when this client knows their lock)
	if v.crowdWait and v.crowdLock then v.crowdLeft = max(0, floor(v.crowdLock - Now())) end
	if t.role == "watch" then
		v.snap, v.prev = t.snap, t.prev
		return v
	end
	local g = t.game
	if not g then return v end
	v.game = g
	v.scores = { g.scores[1], g.scores[2] }
	v.over, v.winner, v.reason = g.over, g.winner, g.reason
	v.current, v.open = g.current, g.open
	v.turn = g.turn
	v.final, v.sudden, v.capped = g.final, g.sudden, g.capped
	v.round = min(g.turns[1], g.turns[2]) + 1
	local who, phase, left = R().Expect(g)
	v.expect = { who = who, phase = phase, left = left }
	if g.hiccup then
		v.levels = {}
		for seat = 1, 2 do
			local lvl, pct, shakes = R().Level(g, seat)
			local wins, total
			if g.hiccupRule == "bones2" then wins, total, pct = R().HiccupTurnOdds(g, seat) end
			v.levels[seat] = { level = lvl, pct = pct, shakes = shakes, wins = wins, total = total }
		end
		v.feel = t.self and t.self.level or nil
	end
	if t.clock and t.state == "play" then
		local click, claim = Limits(t)
		v.clock = { seat = t.clock.seat, phase = t.clock.phase, used = Used(t), click = click, claim = claim, paused = t.clock.pauseWhy }
	end
	v.away = t.away
	if t.state == "play" and not g.over and t.seat and t.away and t.away[t.seat] then
		v.awayLeft = max(0, math.ceil(FT.TAVERN_GRACE - (Clock() - t.away[t.seat])))
	end
	v.combat = t.combat
	v.actWhy = select(1, FT.ActWhy(t))
	return v
end

---------------------------------------------------------------------------
-- The companion's screens: loaded on demand (never in combat), then asked to show
---------------------------------------------------------------------------

function FT.ShowUI(what, id, extra)
	local ok = A().LoadUI()
	if not ok then
		if what == "invite" then local t = tables[id] if t then ns.Print(L.FARKLE_INVITE_LINE:format(ns.DisplayName(t.host))) end end
		return false
	end
	local ui = A().ui
	if what == "innkeeper" and type(ui) == "table" and type(ui.Innkeeper) == "function" then
		ns.SafeCall("Bones innkeeper", ui.Innkeeper, extra)
		return true
	end
	if type(ui) == "table" and type(ui.Farkle) == "function" then
		ns.SafeCall("farkle board", ui.Farkle, what, id, extra)
		return true
	end
	return false
end

-- Prefer an opt-in local row inside a compatible native panel. Its capability checks retain
-- the separate Olympus dialogue on clients whose native layout is unavailable, opened only
-- once the player asked for the innkeeper (1.2.1: FT.KeeperWanted, never at each visit).
pcall(ns.RegisterEvent, "GOSSIP_SHOW", function()
	if not ns.IsMember() or FT.Live() or not (FT.KeeperOffer() or FT.KeeperWanted()) then return end
	if ns.InnkeeperGossip then ns.InnkeeperGossip.OnShow(); return end
	local keeper = FT.Innkeeper(true)
	if keeper and FT.KeeperWanted() then FT.WantKeeper(false); FT.ShowUI("innkeeper", nil, keeper) end
end)

---------------------------------------------------------------------------
-- Actions (every screen button goes through Arena.Can/Do), the events registry, the command
---------------------------------------------------------------------------

local A0 = ns.Arena
A0.Action("farkle.create", function(opts) return FT.CanCreate(opts) end, function(opts) return FT.Create(opts) end)
A0.Action("farkle.answer", function(id, yes, src) return FT.CanAnswer(id, yes, src) end, function(id, yes, src, o) return FT.Answer(id, yes, src, o) end)
A0.Action("farkle.arbitrate", nil, function(id, yes) return FT.AnswerArbiter(id, yes) end)
A0.Action("farkle.ask", nil, function(id, name) return FT.AskArbiter(id, name) end)
A0.Action("farkle.open", nil, function(id) return FT.Open(id) end)
A0.Action("farkle.roll", function(id) local why = FT.ActWhy(Mine2(id)) return why == nil, why end, function(id) return FT.Roll(id) end)
A0.Action("farkle.keep", nil, function(mask, act, id) return FT.Keep(mask, act, id) end)
A0.Action("farkle.concede", nil, function(id) return FT.Concede(id) end)
A0.Action("farkle.void", nil, function(id) return FT.Void(id) end)
A0.Action("farkle.practice", nil, function(opts) return FT.Practice(opts) end)
A0.Action("farkle.watch", function(id) return notices[id] ~= nil, "gone" end, function(id) return FT.Watch(id) end)
A0.Action("farkle.stopwatching", nil, function(id) return FT.StopWatching(id) end)
A0.Action("farkle.sit", nil, function() return FT.Sit() end)
A0.Action("farkle.invite", nil, function(name) return FT.Invite(name) end)
A0.Action("farkle.staked", function(src, stake, arbiter)
	local why = FT.StakeWhy(src or "o", stake, arbiter)
	return why == nil, why
end, function() return true end)
for _, fill in ipairs({ "Pay", "PayFee", "PayStake", "Payout", "Refund", "Change" }) do
	A0.Action("farkle." .. fill:lower(), nil, function(id) return FT[fill](id) end)
end

-- Chat derives its audience from this live table model, never from an EC's claimed public flag
-- or a kept historical market notice. No new wire fields or spectator permission are granted.
function FT.ChatSpec(id)
	if not ValidId(id) then return nil end
	local t, n = tables[id], notices[id]
	if t and (t.role == "practice" or t.role == "bank") then return nil end
	if not t and not n then return nil end
	local watch = not t or t.role == "watch"
	local live, spectators, host, guest, arbiter, mode
	if watch then
		if not n or n.at < Now() - 3 * FT.NOTICE_EVERY or n.state ~= "o" then return nil end
		if n.official and not ns.ArenaRoles.IsPublicArbiter(n.arbiter, n.mode) then return nil end
		if not n.official and not (Same(n.by, n.p1) or Same(n.by, n.p2)) then return nil end
		host, guest, arbiter, mode = n.p1, n.p2, n.arbiter, n.mode
		live = not (t and t.snap and t.snap.phase == "over")
		spectators = live
	else
		host, guest, arbiter, mode = t.host, t.guest, t.arbiter, t.mode
		live = PLAYING[t.state] == true and not t.closed and not (t.game and t.game.over)
		spectators = live and t.noWatch ~= true
	end
	if not host or not guest or Same(host, guest) then return nil end
	if arbiter and not ns.ArenaRoles.IsArbiter(arbiter, mode) then arbiter = nil end
	return { id = id, host = host, guest = guest, arbiter = arbiter, mode = mode,
		live = live == true, spectators = spectators == true, model = t or n }
end

A0.Events.Register("K", function(eid)
	local t = tables[eid]
	if not t then
		-- a public table this client only heard announced (its KN from a public arbiter), or kept
		-- for its crowd's market (KeepNotice): its players and its arbiter, the event that market
		-- is on; never a stake
		local n = notices[eid]
		if n then FT.KeepNotice(n) else n = KeptNotice(eid) end
		if not (n and n.official and n.arbiter) then return nil end
		return { kind = "farkle", opener = n.arbiter, fighters = { A = { name = n.p1 }, B = { name = n.p2 } }, public = true, mode = n.mode }
	end
	return { kind = "farkle", opener = t.arbiter or t.host, fighters = { A = { name = t.host, gk = GK(t.host) }, B = { name = t.guest, gk = GK(t.guest) } },
		public = t.arbiter ~= nil and ns.ArenaRoles.IsPublicArbiter(t.arbiter, t.mode) or false, mode = t.mode, stake = t.stake, cur = t.cur,
		lockAt = t.stakesAt and (Now() + FT.STAKES_WAIT) or nil }
end)

local function ShowLog()
	local b = LogBox()
	local lines = b and b.lines or {}
	local text = #lines > 0 and table.concat(lines, "\n") or L.FARKLE_LOG_EMPTY
	if ns.UI and ns.UI.ShowCopy then ns.UI.ShowCopy(L.FARKLE_LOG_TITLE, text) else ns.Print(text) end
end

A0.Slash("farkle", function(args)
	local sub, rest = tostring(args or ""):match("^(%S*)%s*(.-)$")
	sub = (sub or ""):lower()
	if sub == "test" then return FT.SelfTest() end
	if sub == "practice" then
		local target = tonumber(rest)
		if target and target < 100 then target = target * 1000 end
		return FT.ShowUI("practice", nil, { target = target })
	end
	if sub == "log" then
		local on = rest:lower()
		if on == "on" or on == "off" then
			FT.SetLog(on == "on")
			return ns.Print(on == "on" and L.FARKLE_LOG_ON or L.FARKLE_LOG_OFF)
		end
		if on == "clear" then local b = LogBox() if b then b.lines = {} end return ns.Print(L.FARKLE_LOG_CLEARED) end
		return ShowLog()
	end
	if sub == "chatrolls" then
		local o = FT.Opts()
		o.chatRolls = rest:lower() ~= "off"
		FT.ChatFilter()
		return ns.Print(o.chatRolls and L.FARKLE_CHATROLLS_ON or L.FARKLE_CHATROLLS_OFF)
	end
	-- (1.2.1) The two switches of the privacy page's Bones lines.
	if sub == "invites" or sub == "keeper" then
		local on = rest:lower()
		local set, get = sub == "invites" and FT.SetInvites or FT.SetKeeperOffer, sub == "invites" and FT.InvitesOn or FT.KeeperOffer
		if on == "on" or on == "off" then return set(on == "on") end
		return ns.Print(sub == "invites" and (get() and L.FARKLE_INVITES_ON or L.FARKLE_INVITES_OFF)
			or (get() and L.FARKLE_KEEPER_OFFER_ON or L.FARKLE_KEEPER_OFFER_OFF))
	end
	if sub == "rules" or sub == "help" then return FT.ShowUI("guide") end
	if sub == "" or sub == "open" then return FT.ShowUI("board") end
	ns.Print(L.FARKLE_USAGE)
end, L.FARKLE_HELP)

-- The roll lines stay in chat by default, as public proof; "chatrolls off" hides only this
-- table's players' Bones lines from the chat frames, never the addon's own reading of them.
local filtering = false
function FT.ChatFilter()
	local o = FT.Opts()
	-- (gp:system-filters: registered only where the gate allows, never removed: from its first line
	-- it does nothing with the gamepad UI.)
	if not ns.Gate.Allowed("system-filters") then return end
	if o.chatRolls ~= false or filtering or type(ChatFrame_AddMessageEventFilter) ~= "function" then return end -- gp:system-filters
	filtering = true
	pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_SYSTEM", function(_, _, text) -- gp:system-filters
		if not ns.Gate.Allowed("system-filters") then return false end
		if FT.Opts().chatRolls ~= false or type(text) ~= "string" or Secret(text) then return false end
		local name, _, lo, hi = ns.ArenaParse.Roll(text)
		if not name or lo ~= 1 or not (R().RangeK(lo, hi) or hi == R().OPENING) then return false end
		for _, t in pairs(tables) do
			if t.game and not t.game.over and (LineIs(name, t.players[1] or "") or LineIs(name, t.players[2] or "")) then return true end
		end
		return false
	end)
end

-- /oly status and /oly bug: the live table, the self-test's last result, the tester log.
if type(ns.statusLines) == "table" then
	table.insert(ns.statusLines, function(lines)
		local t = FT.Live()
		local test = lastSelfTest
		local testText = test and (test.none and L.FARKLE_STATUS_TEST_NONE or L.FARKLE_STATUS_TEST:format(test.value or 0, test.match and L.FARKLE_YES or L.FARKLE_NO)) or L.FARKLE_STATUS_TEST_NEVER
		local b = LogBox()
		lines[#lines + 1] = L.FARKLE_STATUS:format(t and (t.id .. " " .. tostring(t.state)) or L.ARENA_NOTHING, testText,
			b and b.on and L.FARKLE_STATUS_LOG_ON:format(#b.lines) or L.FARKLE_STATUS_LOG_OFF)
		if b and b.on then
			for i = max(1, #b.lines - 9), #b.lines do lines[#lines + 1] = "  " .. b.lines[i] end
		end
	end)
end

---------------------------------------------------------------------------
-- Login: a table found in the saved data picks up again (the rules replay its events; a resync
-- asks the others for what came since), and pruning.
---------------------------------------------------------------------------

function FT.Load()
	for _, mode in ipairs({ "L", "T" }) do
		local m = Peek(mode)
		local recs = {}
		if m and type(m.live) == "table" then recs[#recs + 1] = m.live end
		for _, rec in pairs(m and m.arb or {}) do if type(rec) == "table" then recs[#recs + 1] = rec end end
		for _, rec in ipairs(recs) do
			if ValidId(rec.id) and not tables[rec.id] and LIVE[rec.state]
				and (not rec.hic or rec.hiccupRule == "bones2") then
				local t = {}
				for _, k in ipairs(RECORD) do t[k] = rec[k] end
				t.src = type(rec.src) == "table" and { rec.src[1], rec.src[2] } or {}
				t.players = { t.host, t.guest }
				-- (each player's word on watchers, as saved; a record of 1.2.2 and before has none:
				-- nobody relays from it, as then)
				local spec = type(rec.spec) == "table" and rec.spec or {}
				t.spec = { spec[1] == true, spec[2] == true }
				t.log = {}
				t.seat = SeatOf(t, Me())
				tables[t.id] = t
				if rec.events and PLAYING[rec.state] then
					local g = R().Replay(Fields(t), rec.events)
					if g then
						t.game, t.own = g, g
						t.reloaded = true
						t.pausedSince = Clock()
						Resync(t, Asked(t), g.step)
					else
						tables[t.id] = nil
					end
				end
				if tables[t.id] then Involve(t, true) end
			end
		end
	end
	FT.Prune()
	Subscribe()
	-- (1.2.3: this player's own games of the ranking said again a little after the login, both
	-- halves, for the members who were away when they ended; nothing where he has none)
	local b = RankStore(false)
	if b and next(b.own) then ns.After(FT.HALVES_REPEAT_DELAY + math.random(0, 30), "bones halves", FT.RepeatHalves) end
end
ns.On("LOGIN", function() ns.SafeCall("farkle load", FT.Load) end)

-- (1.2.4) This character's own halves of the games that count, for /oly backup (Backup.lua): [key]
-- = { t, mode, mine }, his own signed half alone (the other's comes back from its player: HV.AskHalves),
-- of this month and the last (the games his client says again and asks for), the newest
-- OWN_BACKUP_MAX (the review: a text past Backup.MAX is refused whole at the restore, and his games
-- of 62 days had no bound); nil when none.
FT.OWN_BACKUP_MAX = 400
function FT.OwnBackup()
	local b = RankStore(false)
	if not b then return nil end
	local list, cut, me, month = {}, Now() - FT.HALVES_DAYS * 86400, Low(Me()), MonthOf(Now())
	for key, o in pairs(b.own) do
		local f = type(o) == "table" and type(o.mine) == "string" and Split(o.mine) or nil
		local seat = f and tonumber(f[16] or "")
		local mine = f and (seat == 1 and f[2] or (seat == 2 and f[3])) or nil
		local t = tonumber(type(o) == "table" and o.t) or 0
		if mine and Low(mine) == me and t >= cut and MonthOf(t) >= month - 1 then
			list[#list + 1] = { key = key, t = t, x = { t = t, mode = o.mode == "L" and "L" or "T", mine = o.mine } }
		end
	end
	table.sort(list, function(x, y)
		if x.t ~= y.t then return x.t > y.t end
		return x.key > y.key
	end)
	local out = {}
	for i = 1, math.min(#list, FT.OWN_BACKUP_MAX) do out[list[i].key] = list[i].x end
	return next(out) and out or nil
end
-- (1.2.4) Those taken back after a wiped saved data (Backup.ApplyArena): each this player's own
-- half (his seat's, his name), taken as his own word, its game kept for his repeats and his ask for
-- the other's half; a game held here already is left as it is. The number taken.
function FT.RestoreOwn(list)
	if type(list) ~= "table" then return 0 end
	local n = 0
	for key, x in pairs(list) do
		local f = type(x) == "table" and type(x.mine) == "string" and #x.mine <= 600 and Split(x.mine) or nil
		local p1, p2 = f and A().Name(f[2] or ""), f and A().Name(f[3] or "")
		local mode = type(x) == "table" and x.mode == "L" and "L" or "T"
		local h = f and p1 and p2 and type(f[1]) == "string" and f[1]:find("^K[0-9a-z]+$") and #f[1] <= 16 and NoticeHalf(f, f[1], p1, p2, mode) or nil
		if h and Same(h.seat == 1 and h.p1 or h.p2, Me()) and HalfKey(h.id, h.p1, h.p2) == key then
			local b = RankStore(true)
			if b and b.own[key] == nil then
				b.own[key] = { t = h.t, mode = mode, n = 0 }
				if TakeHalf(Me(), h, true) then
					local o = b.own[key]
					o.mine, o.t, o.last = h.body, h.t, h.t
					n = n + 1
				else
					b.own[key] = nil
				end
			end
		end
	end
	return n
end

-- Tests only: forget every table (a new world's client starts clean anyway).
function FT.Reset()
	for id, t in pairs(tables) do A().Involve("table:" .. id, false) end
	tables, invitedBy, notices = {}, {}, {}
	bestCache, HV.held, HV.repeating, HV.checking, HV.checks = {}, nil, {}, {}, 0
	HV.asking, HV.answered, HV.stats = {}, {}, {}
	selftest, lastSelfTest = nil, nil
	invitesSeen, invitesAsked = {}, false
end
FT._ = { tables = function() return tables end, notices = function() return notices end, Split = Split, Terms = Terms, Fields = Fields }

-- Two original KN halves, never an unsigned summary. RK binds their keys to the server's sender.
function FT.ReadRecord(body)
	local left, right = tostring(body):match("^([^^]+)%^([^^]+)$")
	if not left then return nil, "shape" end
	local halves = {}
	for seat, value in ipairs({ left, right }) do
		local f = Split(value)
		local p1, p2 = A().Name(f[2] or ""), A().Name(f[3] or "")
		local h = ValidId(f[1] or "") and p1 and p2 and NoticeHalf(f, f[1], p1, p2, "L")
		if not h or h.seat ~= seat or not h.pk or not h.sig or h.began > h.t then return nil, "half" end
		halves[seat] = h
	end
	local a, b = halves[1], halves[2]
	if a.id ~= b.id or not Same(a.p1, b.p1) or not Same(a.p2, b.p2) or Same(a.p1, a.p2) or a.pk == b.pk then return nil, "pair" end
	local agreed = HV.Agreed({ p1 = a.p1, p2 = a.p2, by = { [Low(a.p1)] = HV.Word(a), [Low(a.p2)] = HV.Word(b) } })
	if not agreed then return nil, "result" end
	local parts = {}
	for seat, h in ipairs(halves) do
		local pk, sig = HV.Raw(h.pk, 32), HV.Raw(h.sig, 64)
		if not pk or not sig then return nil, "key" end
		parts[seat] = { name = seat == 1 and h.p1 or h.p2, pk64 = h.pk, sig64 = h.sig, pk = pk, sig = sig, msg = "OLYB1|" .. h.core }
	end
	agreed.p1, agreed.p2, agreed.at = a.p1, a.p2, agreed.t
	return { id = HalfKey(a.id, a.p1, a.p2), t = agreed.t, content = agreed.said .. "|" .. agreed.t .. "|" .. agreed.dur, parts = parts, done = agreed }
end
if ns.Records and ns.Records.Register then
	ns.Records.Register("b", {
		Read = FT.ReadRecord, DAY_MAX = FT.HALVES_DAY_KEEP,
		Took = function(rec)
			local b = RankStore(true)
			if b and not (b.clash and b.clash[rec.id]) then
				b.done[rec.id] = b.done[rec.id] or HV.DoneLine(rec.done)
				HV.held, bestCache = nil, {} HV.gen = HV.gen + 1
			end
		end,
		Conflict = function(rec)
			local b = RankStore(true)
			if b then
				b.clash = b.clash or {} b.clash[rec.id] = true
				b.done[rec.id], b.open[rec.id] = nil, nil
				for month, kept in pairs(b.months) do if not kept.sealed then b.months[month] = nil end end
				HV.held, bestCache = nil, {} HV.gen = HV.gen + 1
			end
		end,
		Totals = function(month) return FT.Best("L", { month = month, all = true }) end,
		Sealed = function(month, rows)
			local b = RankStore(true)
			if b then b.months[month] = { sealed = true, rows = rows, at = Now(), n = #rows } end
		end,
		Pins = function() return (RankStore(false) or {}).keys or {} end,
		Mine = function()
			local out = {}
			for _, e in pairs((RankStore(false) or {}).own or {}) do
				-- This store holds counted games only. A free release game still
				-- travels in T while the King's live switch is off; its wire mode
				-- must not prevent recovery of the two original signed results.
				if e.mine and e.theirs then
					local f = Split(e.mine)
					out[#out + 1] = f[16] == "1" and HV.RecordBody(e.mine, e.theirs) or HV.RecordBody(e.theirs, e.mine)
				end
			end
			return out
		end,
		Has = function() local b = RankStore(false) return b ~= nil and next(b.own) ~= nil end,
	})
end
