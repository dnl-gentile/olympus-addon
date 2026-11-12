local ADDON, ns = ...
local L = ns.L

-- 1.2.4, the shared records (the author's ask, 2026-10-12: rankings "acumulativas, propagar pela
-- rede e serem relateadas por todo mundo que tenha essa informação, tipo P2P"). A game or a duel
-- that counts is a record: its two players' signed halves, under an id that never changes. Every
-- client that holds a record keeps it and tells it to whoever lacks it; the rankings are worked out
-- from what a client holds; a month is closed by the author's signed seal, and only a seal ever
-- lets a record go.
--
-- Records (ns.rdb.records[letter], the core's saved data, per realm group and faction): a type
-- registers itself (Records.Register: FarkleTable "b", the Bones games; ArenaLedger "d", the duels)
-- with how to read its records (Read: the id, the time, what it says, its signed parts), what to do
-- with one taken here (Took: its ranking takes it), with one whose id another record holds already
-- with another result (Conflict: neither counts), the month's totals (Totals) and a seal's (Sealed).
--   days   = { [server day] = { [id] = body } }: the records, a grow-only union. The same id again
--            is left out; the same id saying another result is a conflict (clash), kept for review
--            and counted nowhere.
--   clash  = { [id] = { body, ... } }
--   pend   = { [id] = { b = body, d = day, at, by } }: a record one of whose players' keys this
--            client does not hold yet: kept (PENDING_MAX, the oldest heard going only when full) and
--            taken once the key arrives.
--   seals  = { [month] = { s = the signed seal, h = its totals' hash, n, at, r = the totals once
--            this client holds them } }
--   drafts = { [month] = { r, h, n, at } }: this client's own totals of a closed month (SEAL_AFTER
--            after its end): the author's seal request, and what any client compares a seal with.
--   keys (ns.rdb.records.keys) = { [player, lower case] = { k = his newest key, o = older ones,
--            g = gk, at } }: the ranking keys this client heard from their own players.
-- A record counts only when each of its parts is signed with the key its own player declared to
-- this client first-hand (RK, the server stamps the sender; or his own half heard from him, the
-- types' pins), or when two different live holders attest that exact record after validating it
-- with those first-hand keys. Each holder's RV is signed with the key it declares first-hand to
-- the receiver. One relay can therefore never invent a player's identity, while two independent
-- holders let the durable network outlive the two original players' sessions.
--
-- Anti-entropy. Every DIGEST_EVERY (a round, on the server's clock: the same on every client) each
-- holder has a slot for each type it holds (R.Slot: no draw; the King's after everyone's, none for
-- the author's character or a client whose quiet presence is on, R.Bar), spread over the army's
-- size (DigestWindow). At its slot it sends a digest of what it holds: each day's count and the
-- sum of its ids' short hashes, the newest days plus rotating older days, and rotating sealed
-- months' totals hashes; unless ELECT other holders' digests heard this round already told every
-- day and month it would, the same (Covered: a holder of what nobody else told always tells it).
-- That is looked at again when the digest leaves the records' low lane. About ELECT + N·L/W
-- digests a type a round, for N holders, a delay L and a window W. A client whose day differs
-- asks for it (RA, with the PREFIX-character
-- prefixes of the ids it holds of that day), ASK_DAYS days a digest at most, the newest first; a
-- client that holds what the digest lacks sends its own digest at its slot a few seconds later
-- (PUSH_GAP apart at most; not when ELECT digests heard meanwhile told all it would). The holders
-- whose digest named that day made it ask, and answer first, ANSWER_MIN to ANSWER_MIN +
-- ANSWER_SPREAD later; any other holder only as a fallback, FALLBACK_MIN and more later, when the
-- body or WITNESSES validations still had not come (OnAsk); none within ANSWER_GAP of its own last
-- answer of that day, none past its budget (BUDGET jobs a BUDGET_EVERY, ASKER_JOBS of them for one
-- asker). Every answer goes on the arena's low lane (a message a second at most, while Comm's
-- queue has room), the newest days first, on the channel: whoever lacks the same takes it too.
--
-- The seal (the author's, signed as the council lists are, scripts/council-sign.py seal): SEAL_AFTER
-- after a month ends each client works its totals out (a draft); `/oly arena records` shows them
-- as the author's seal requests, and the signed seal is pasted back (`/oly arena records seal`).
-- A client whose totals say the same hash keeps its own; any other takes the seal's totals (RT,
-- from any holder) once they hash to it. Once a month is sealed, its records older than
-- COMPACT_DAYS go and its totals stay for good. No seal: nothing is deleted.
--
-- Messages (numbers in base 36 unless said):
--   RK gk~pk~t~sig                         a player's ranking key (sig: "OLYK1|<Name-Realm>|gk|pk|t")
--   RD letter~day.n.sum,...~month.hash8,...  a digest
--   RA letter~d~day~prefixes                 an ask for a day's records (the prefixes it holds)
--   RA letter~s~month~hash8|-                an ask for a month's seal and its totals
--   RA letter~w~day~prefixes                 an ask for validations alone (RV) of records it holds, waiting
--   RA letter~x~day~scope~hash~id            Forever mesh only: direct ask for one exact pending record's RV
--   RR letter~body                           a record
--   RV letter~hash~t~pk~sig                  a live holder's validation of that exact record
--   RS RS1~at~group~faction~letter~month~n~hash~sig   a seal (decimal; sig: RSA, Sign.lua)
--   RT letter~month~hash8~i~k~rows           a seal's totals, part i of k ("Name-Realm,games,won,lost;...")
local Records = {}
ns.Records = Records
local R = Records

R.TYPES = {}             -- [letter] = the type's spec (Register)
R.DIGEST_EVERY = 600     -- a round: each holder's digest of each type once at most, at its slot
R.DIGEST_WINDOW_MIN, R.DIGEST_WINDOW_MAX = 120, 480 -- a round's slots spread over the army's size, within these
R.ELECT = 2              -- other holders' digests that told all ours would: ours stays home
R.HEARD_MAX = 2000       -- digest facts (day.n.sum, month.hash8) remembered per type, for that
R.PUSH_MIN, R.PUSH_WINDOW = 2, 30 -- our digest to one that lacks something: this long after it, by slot
R.DIGEST_DAYS = 70       -- record-days per digest, bounded on the wire
R.DIGEST_RECENT = 3      -- newest days always; older unsealed days rotate through the remaining slots
R.DIGEST_MONTHS = 24     -- ...and the newest sealed months
R.ASK_DAYS = 3           -- days asked for from one digest at most
R.ASK_GAP = 300          -- a day asked for again from here this long after at the soonest
R.ASK_SPREAD = 20        -- an ask a digest set off waits score × this; heard asks that asked for all ours would merge it
R.ANSWER_GAP = 60        -- one answer per day this often (anyone's)
R.ANSWER_MIN, R.ANSWER_SPREAD = 1, 6 -- a holder whose digest named it answers this long after the ask...
R.ANSWER_WINDOW = 120    -- ...a digest of ours that went this recently (or goes while the ask waits)
R.FALLBACK_MIN = 30      -- any other holder of it: this long after the ask at the soonest, if nothing came
R.FALLBACK_SPREAD_MIN, R.FALLBACK_SPREAD_MAX = 30, 240 -- ...spread over half the army, within these
R.BUDGET, R.BUDGET_EVERY = 30, 600 -- jobs (a digest, a push, an answer) this client sends at most, this long
R.ASKER_JOBS = 10        -- ...of them for one asker's asks
R.RV_HEARD_MAX = 2000    -- records whose validations heard are remembered per type (who, when)
R.PUSH_GAP = 120         -- our own digest sent back to one that lacks something, this often at most
R.OUT_MAX = 400          -- messages waiting on the low lane at most
R.FROM_DAY_MAX = 500     -- new records (kept or waiting for a key) one relayer brings in a server day
R.PENDING_MAX = 500      -- records waiting for a key
R.PENDING_EACH = 24      -- ...from one relayer, so one peer cannot evict everybody else's
R.CHECKS_MAX = 20        -- records whose signatures are checked at once (FarkleTable's HALVES_CHECKS)
R.CHECKS_EACH = 4        -- ...from one relayer, leaving active verifier slots for other peers
R.WAIT_MAX = 200         -- ...and waiting for their turn
R.WAIT_EACH = 8          -- ...from one relayer, preserving room for independent peers
R.LATER = 30             -- the signature queue full: checked again this much later
R.KEYS_MAX = 5000        -- players' keys kept
R.KEYS_EACH = 3          -- keys of one player kept (a new account key after a wiped saved data)
R.KEY_DELAY, R.KEY_SPREAD = 30, 60 -- a player named in records declares his key this long after login
R.KEY_EVERY = 3600       -- ...and again this often while online
R.LOAD_DELAY = 10        -- this long after login: each type's own records taken in, the pins
R.PREFIX = 16            -- 64 bits of SHA-256 over the stable id and result (not signature bytes)
R.AHEAD = 120            -- a record's time this far ahead of the clock at most
R.CLASH_EACH = 3         -- other bodies kept for one id in conflict
R.BODY_MAX = 1200
R.SEAL_AFTER = 7 * 86400 -- a month's totals worked out this long after it ends
R.COMPACT_DAYS = 62      -- a sealed month's records older than this go (the totals stay)
R.SEAL_ROWS_MAX = 5000
R.CHUNK = 3000           -- bytes of totals in one RT at most
R.ASM_TTL = 7200         -- bounded signed totals can take an hour on Comm's paced low lane
R.ASM_MAX = 8
R.CHECK_DAY_MAX = 1000   -- attempted checks per relay, reserved before asynchronous verification
R.CONTROL_MAX = 256     -- remembered remote day/month requests, per type
R.ASK_PREFIX_MAX = 350   -- 5,600 bytes, below Arena's 6,600-byte assembly limit
R.WITNESSES = 2          -- distinct live, first-hand keyed holders required to relay identity
R.WITNESS_FRESH = 86400  -- an attestation is about what its sender still holds now, not old gossip
R.KING_AFTER = 60        -- the King's turn: this long after every other holder's latest (R.Slot)
R.DISCOVERY_RETRY = 90   -- a ranking view's ask for digests (RH): no digest of its types heard this long after, once more...
R.DISCOVERY_MAX = 2      -- ...this many a session at most
R.DISCOVERY_GAP = 60     -- a holder's reply round of a type at most this often, whoever asked
R.DISCOVERY_MIN = 1      -- ...its slots from this long after the ask, over the round's window (R.DigestWindow)
R.random = math.random

local floor, max, min = math.floor, math.max, math.min
local stats = { refused = {}, kept = 0, again = 0, pending = 0, clash = 0, sent = 0, asked = 0, answered = 0, digests = 0, keys = 0, witnessed = 0, sealed = 0, compacted = 0 }
local function Count(why) stats.refused[why] = (stats.refused[why] or 0) + 1 return false, why end
function R.Stats() return stats end

local function A() return ns.Arena end
local function Now() return A().Now() end
local function B36(n) return A().B36(n) end
local function N36(s, lo, hi) return A().N(s, lo, hi) end
local function Low(name)
	if type(name) ~= "string" or name == "" then return nil end
	return ns.FullName(name):lower()
end
local function Same(a, b) return Low(a) ~= nil and Low(a) == Low(b) end
local function Me() return ns.me end

-- 1.4.0, who relays and when (the same on every client, no draw):
--   R.Score(topic, name): a number in [0, 1) from SHA-256 of the topic and the name: a holder's
--     place in one election (a round's digests, an answer), another for each topic.
--   R.Bar(name): "never" for the author's character (the core's Borders.IsDevName: no arena file
--     names him) and for this client while its quiet presence is on (any word it sent would say it
--     is online); "last" for the King, whose client is never the first to relay; nil for everyone
--     else. The author's own signed words (his key, a seal he pastes) are not relays and still go.
--   R.Slot(topic, name, base, window, widest): when that holder's turn comes: base + its score
--     times the window; the King's after the widest window any client may use, plus KING_AFTER
--     (each client works its window out from what it sees of the army: his own may be narrower);
--     nil for a holder that never relays.
function R.Score(topic, name)
	local bytes = ns.Sign.SHA256(tostring(topic) .. "|" .. (Low(name) or ""))
	local a, b, c, d = bytes:byte(1, 4)
	return (((a * 256 + b) * 256 + c) * 256 + d) / 4294967296
end
function R.Bar(name)
	name = name or Me()
	local B = ns.Borders
	if type(B) == "table" and type(B.IsDevName) == "function" and type(name) == "string" and B.IsDevName(ns.FullName(name)) == true then return "never" end
	if Same(name, Me()) and type(ns.QuietPresence) == "function" and ns.QuietPresence() == true then return "never" end
	local Roles = ns.ArenaRoles
	if type(Roles) == "table" and type(Roles.IsKing) == "function" and Roles.IsKing(name) == true then return "last" end
	return nil
end
function R.Slot(topic, name, base, window, widest)
	local bar = R.Bar(name)
	if bar == "never" then return nil end
	if bar == "last" then return base + max(window, widest or window) + R.KING_AFTER end
	return base + R.Score(topic, name) * window
end
-- This client relays nothing now (R.Bar).
local function Barred() return R.Bar(Me()) == "never" end

-- The month of server time t (Honors.MonthOf's numbering: year * 12 + month - 1, UTC).
local function DaysFromCivil(y, m, d)
	y = m <= 2 and y - 1 or y
	local era = floor(y / 400)
	local yoe = y - era * 400
	local mp = m > 2 and m - 3 or m + 9
	local doy = floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end
function R.MonthOf(t)
	local H = ns.Honors
	if type(H) == "table" and type(H.MonthOf) == "function" then return H.MonthOf(t) end
	local d = date("!*t", floor(tonumber(t) or 0))
	return d.year * 12 + d.month - 1
end
-- When month n starts (server time, UTC).
function R.MonthStart(n)
	n = floor(tonumber(n) or 0)
	return DaysFromCivil(floor(n / 12), n % 12 + 1, 1) * 86400
end

-- An id's short hash (32 bits: two of Comm's Hash36 accumulators) and its prefix.
function R.Short(id)
	local h1, h2 = 5381, 52711
	for i = 1, #id do
		local c = id:byte(i)
		h1 = (h1 * 33 + c) % 2147483647
		h2 = (h2 * 31 + c * 7) % 2147483647
	end
	return (h1 % 1048576) * 4096 + h2 % 4096
end
local PREFIX_SPAN = 36 ^ R.PREFIX
function R.Prefix(n)
	local s = B36(n % PREFIX_SPAN)
	return ("0"):rep(R.PREFIX - #s) .. s
end
-- The two players an id names ("<game>:<player>:<player>", lower case).
local function Players(id)
	local a, b = tostring(id):match("^[^:]+:([^:]+):([^:]+)$")
	return a, b
end
local function Names(id, low)
	local a, b = Players(id)
	return low ~= nil and (a == low or b == low)
end

---------------------------------------------------------------------------
-- The store and its index
---------------------------------------------------------------------------

local function Root(make)
	local Ar = A()
	if not Ar or Ar.Sim() or type(ns.rdb) ~= "table" then return nil end
	local root = ns.rdb.records
	if type(root) ~= "table" then
		if not make then return nil end
		root = { v = 2 }
		ns.rdb.records = root
	end
	local side = tostring(ns.faction or "Alliance")
	-- Preserve the unreleased flat store when upgrading it, in its original client's faction.
	if root.v == 1 then
		local legacy = {}
		for k, v in pairs(root) do if k ~= "v" then legacy[k] = v end end
		root[side], root.v = legacy, 2
	end
	local s = root[side]
	if type(s) ~= "table" then
		if not make then return nil end
		s = {} root[side] = s
	end
	if type(s.keys) ~= "table" then s.keys = {} end
	return s
end
local function Store(letter, make)
	if not R.TYPES[letter] then return nil end
	local s = Root(make)
	local t = s and s[letter]
	if type(t) ~= "table" then
		if not (s and make) then return nil end
		t = {}
		s[letter] = t
	end
	for _, k in ipairs({ "days", "clash", "pend", "seals", "drafts" }) do
		if type(t[k]) ~= "table" then t[k] = {} end
	end
	return t
end
R.Store = Store

-- [letter] = { store, ids = { [id] = day }, dig = { [day] = { n, x } }, per = { [day] = { [player] = n } } },
-- worked out from the store at the first need.
local idx = {}
local function Add(x, d, id, body)
	if x.ids[id] then return end
	x.ids[id] = d
	local g = x.dig[d]
	if not g then g = { n = 0, x = 0 } x.dig[d] = g end
	local hash = R.Short(R.Fingerprint(x.letter, body, true))
	x.hash[id] = hash
	g.n, g.x = g.n + 1, (g.x + hash) % 4294967296
	local per = x.per[d]
	if per then
		local a, b = Players(id)
		if a then per[a] = (per[a] or 0) + 1 end
		if b then per[b] = (per[b] or 0) + 1 end
	end
end
local function Remove(x, d, id)
	if x.ids[id] ~= d then return end
	x.ids[id] = nil
	local g = x.dig[d]
	if g then
		g.n, g.x = g.n - 1, (g.x - (x.hash[id] or 0)) % 4294967296
		if g.n <= 0 then x.dig[d] = nil end
	end
	x.per[d] = nil
	x.hash[id] = nil
end
local function Index(letter)
	local s = Store(letter)
	local x = idx[letter]
	if x and x.store == s then return x end
	x = { letter = letter, store = s, ids = {}, hash = {}, dig = {}, per = {} }
	idx[letter] = x
	if s then
		for d, list in pairs(s.days) do
			if type(d) ~= "number" or type(list) ~= "table" then s.days[d] = nil
			else
				for id, body in pairs(list) do
					Add(x, d, id, body)
					for _, other in ipairs(s.clash[id] or {}) do
						local g = x.dig[d]
						g.n, g.x = g.n + 1, (g.x + R.Short(R.Fingerprint(letter, other, true))) % 4294967296
					end
				end
			end
		end
	end
	return x
end
-- A day's records per player (a type's DAY_MAX).
local function PerDay(x, s, d)
	local per = x.per[d]
	if per then return per end
	per = {}
	for id in pairs(s.days[d] or {}) do
		local a, b = Players(id)
		if a then per[a] = (per[a] or 0) + 1 end
		if b then per[b] = (per[b] or 0) + 1 end
	end
	x.per[d] = per
	return per
end

-- A seal whose totals this client holds (adopted), its month's old records then gone.
local function Adopted(seal) return type(seal) == "table" and type(seal.r) == "string" and type(seal.h) == "string" end
local function CompactBefore() return floor((Now() - R.COMPACT_DAYS * 86400) / 86400) end
local function Compacted(s, d)
	return s ~= nil and d < CompactBefore() and Adopted(s.seals[R.MonthOf(d * 86400)])
end

function R.Has(letter, id) return Index(letter).ids[id] ~= nil end
-- The records held of a type (tests, the status): their number, and the days.
function R.Count(letter)
	local n = 0
	for _ in pairs(Index(letter).ids) do n = n + 1 end
	return n
end
function R.Body(letter, id)
	local d = Index(letter).ids[id]
	local s = d and Store(letter)
	return s and s.days[d] and s.days[d][id] or nil
end
local fingerprints = {}
function R.Fingerprint(letter, body, save)
	local cache = fingerprints[letter]
	if cache and cache[body] then return cache[body] end
	local spec = R.TYPES[letter]
	local ok, rec = pcall(spec.Read, body)
	local text = ok and rec and (rec.id .. "|" .. tostring(rec.content)) or body
	local hash = (ns.Sign.SHA256(text):sub(1, 8):gsub(".", function(c) return ("%02x"):format(c:byte()) end))
	if save then cache = cache or {} fingerprints[letter] = cache cache[body] = hash end
	return hash
end
function R.Bodies(letter, first, last)
	local s, out = Store(letter), {}
	for d, list in pairs(s and s.days or {}) do
		if (not first or d >= first) and (not last or d <= last) then
			for id, body in pairs(list) do if not s.clash[id] then out[#out + 1] = body end end
		end
	end
	return out
end
function R.ContainsMonth(letter, month)
	local x = Index(letter)
	for d = floor(R.MonthStart(month) / 86400), floor(R.MonthStart(month + 1) / 86400) - 1 do
		if x.dig[d] and x.dig[d].n > 0 then return true end
	end
	return false
end
function R.Pending(letter)
	local s = Store(letter)
	local n = 0
	for _ in pairs(s and s.pend or {}) do n = n + 1 end
	return n
end
function R.Clashes(letter)
	local s = Store(letter)
	local out = {}
	for id in pairs(s and s.clash or {}) do out[#out + 1] = id end
	table.sort(out)
	return out
end
-- Whether any record of a type names that player (the key declaration's reason).
local function Named(low)
	if not low then return false end
	for letter in pairs(R.TYPES) do
		for id in pairs(Index(letter).ids) do if Names(id, low) then return true end end
		local s = Store(letter)
		for id, p in pairs(s and s.pend or {}) do if Names(p.id or id, low) then return true end end
	end
	return false
end

---------------------------------------------------------------------------
-- Keys: each player's own word (RK) or his own half heard from him (the types' pins)
---------------------------------------------------------------------------

local Take -- (below)
local Unpend -- (below)
local function KeyShape(pk64) return type(pk64) == "string" and #pk64 == 43 and pk64:find("^[%w%-_]+$") ~= nil end
local function Raw(text, len)
	local Ed = ns.Ed25519
	local ok, r = pcall(function() return type(text) == "string" and type(Ed) == "table" and Ed.FromB64 and Ed.FromB64(text) or nil end)
	return ok and type(r) == "string" and #r == len and r or nil
end
local function B64(raw)
	local Ed = ns.Ed25519
	return type(raw) == "string" and type(Ed) == "table" and Ed.ToB64 and Ed.ToB64(raw) or nil
end
local function Hex(bytes) return (tostring(bytes):gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end
local function RecordHash(letter, body) return Hex(ns.Sign.SHA256(tostring(letter) .. "|" .. tostring(body))) end
R.RecordHash = RecordHash

-- The keys this client holds for a player: a set { [pk base64url] = true }, or nil.
function R.KeysOf(name)
	local low = Low(name)
	if not low then return nil end
	local out
	local root = Root(false)
	local k = root and root.keys[low]
	if type(k) == "table" then
		if KeyShape(k.k) then out = out or {} out[k.k] = true end
		for _, v in ipairs(type(k.o) == "table" and k.o or {}) do if KeyShape(v) then out = out or {} out[v] = true end end
	end
	-- (a claim Debts verified: the wallet's, ZT; none while the Wallet is off)
	local D = ns.Debts
	if type(D) == "table" and type(D.KeyOf) == "function" then
		local ok, raw = pcall(D.KeyOf, name)
		local v = ok and type(raw) == "string" and #raw == 32 and B64(raw) or nil
		if v then out = out or {} out[v] = true end
	end
	return out
end
function R.HasKey(name, pk64)
	local set = KeyShape(pk64) and R.KeysOf(name)
	return set ~= nil and set[pk64] == true
end
function R.KeyOf(name)
	local root = Root(false)
	local k = root and root.keys[Low(name) or ""]
	return type(k) == "table" and KeyShape(k.k) and k.k or nil
end

-- A player's key, heard from him (his RK whose signature held, or his own half: the types' pins).
-- True when new for him. quiet: no records looked at again (the caller does it once, RecheckPending).
function R.Pin(name, pk64, gk, quiet)
	local low = Low(name)
	if not low or not KeyShape(pk64) then return false end
	local root = Root(true)
	if not root then return false end
	local k = root.keys[low]
	if type(k) == "table" and k.k == pk64 then
		k.at = Now()
		return false
	end
	if type(k) ~= "table" then
		local n, oldest, at = 0, nil, nil
		for key, v in pairs(root.keys) do
			n = n + 1
			local t = type(v) == "table" and tonumber(v.at) or 0
			if not at or t < at then oldest, at = key, t end
		end
		if n >= R.KEYS_MAX and oldest then root.keys[oldest] = nil end
		k = {}
		root.keys[low] = k
	end
	local old = {}
	if KeyShape(k.k) then old[1] = k.k end
	for _, v in ipairs(type(k.o) == "table" and k.o or {}) do
		if v ~= pk64 and KeyShape(v) and #old < R.KEYS_EACH - 1 then old[#old + 1] = v end
	end
	k.k, k.o, k.g, k.at = pk64, old, type(gk) == "string" and gk or k.g, Now()
	stats.keys = stats.keys + 1
	if not quiet then Unpend(low) end
	return true
end

local function KeyText(name, gk, pk64, t) return ("OLYK1|%s|%s|%s|%s"):format(ns.FullName(name), gk, pk64, t) end
local keySentAt
-- This player's ranking key on the channel (RK, signed with it): once a session after login when
-- records name him, again KEY_EVERY while online, never from a player no record names. Never while
-- this client's quiet presence is on (1.4.0): it says the character is online; the next tick after
-- it is off declares it.
local function Quiet() return type(ns.QuietPresence) == "function" and ns.QuietPresence() == true end
local cross = {}
local function KeyBody()
	if Quiet() then return false end
	local D = ns.Debts
	if type(D) ~= "table" or type(D.MyKey) ~= "function" or type(D.Sign) ~= "function" then return false end
	local ok, gk, pk = pcall(D.MyKey)
	if not ok or not gk or type(pk) ~= "string" or #pk ~= 32 then return false end
	local pk64, t = B64(pk), B36(Now())
	local signed, sig = pcall(D.Sign, KeyText(Me(), gk, pk64, t))
	if not signed or type(sig) ~= "string" or #sig ~= 64 then return false end
	R.Pin(Me(), pk64, gk, true)
	return table.concat({ gk, pk64, t, B64(sig) }, "~")
end
function R.SendKey()
	local body = KeyBody()
	if not body then return false end
	keySentAt = Now()
	return A().Send("RK", "L", body, { dist = "CHANNEL", key = "records key", low = true }) == true
end
local keyDue = false
local function KeyLater()
	if keySentAt or keyDue then return end
	keyDue = true
	ns.After(R.KEY_DELAY + R.random() * R.KEY_SPREAD, "records key", function()
		keyDue = false
		if not keySentAt then R.SendKey() end
	end)
end

local function OnKey(dist, sender, mode, body)
	if mode ~= "L" or (dist ~= "CHANNEL" and dist ~= "WHISPER") then return Count("lane") end
	local gk, pk64, t, sig64 = A().Fields(body, 4)
	local at = N36(t, 0, 4294967295)
	if not sig64 or not KeyShape(pk64) or #sig64 ~= 86 or not A().GuidOf(gk) or not at or at > Now() + R.AHEAD then return Count("key-shape") end
	sender = ns.FullName(sender)
	if R.HasKey(sender, pk64) then
		local root = Root(false)
		local k = root and root.keys[Low(sender)]
		if type(k) == "table" and k.k == pk64 then k.at = Now() end
		if cross.KeyArrived then cross.KeyArrived(sender, pk64) end
		return
	end
	local pk, sig = Raw(pk64, 32), Raw(sig64, 64)
	if not pk or not sig then return Count("key-shape") end
	local claim = KeyText(sender, gk, pk64, t)
	A().Check("rk " .. sig64 .. " " .. claim, { pk = pk, msg = claim, sig = sig }, function(good)
		if good then
			R.Pin(sender, pk64, gk)
			if cross.KeyArrived then cross.KeyArrived(sender, pk64) end
		elseif good == false then Count("key-signature") end
	end)
end
ns.Comm.Handle("RK", ns.Arena.Handle("RK", OnKey))

local function WitnessText(name, letter, hash, t, pk64)
	return ("OLYV1|%s|%s|%s|%s|%s"):format(ns.FullName(name), letter, hash, t, pk64)
end

---------------------------------------------------------------------------
-- Taking a record
---------------------------------------------------------------------------

local ticker
local ScheduleRounds -- (below)
-- The records clock, and this holder's slots in the next rounds (from its first round on).
local function EnsureTicker()
	if ticker or not Root(false) then return end
	ticker = ns.Every(R.DIGEST_EVERY, "records", function() R.Tick() end)
	ScheduleRounds()
end

-- Records one relayer brought in today: [sender lower] = n (memory, one server day).
local from, attempts, fromDay = {}, {}, -1
local function FromCount(sender, add)
	local d = floor(Now() / 86400)
	if d ~= fromDay then from, attempts, fromDay = {}, {}, d end
	local k = Low(sender) or "?"
	if add then from[k] = (from[k] or 0) + 1 end
	return from[k] or 0
end

local checking, checkingBy, inflight, waitq = {}, {}, 0, {}
local PumpWait -- (below)

local function Clash(letter, s, rec, body)
	local list = s.clash[rec.id]
	if type(list) ~= "table" then list = {} s.clash[rec.id] = list end
	for _, b in ipairs(list) do if b == body then return false, "conflict" end end
	if #list < R.CLASH_EACH then
		list[#list + 1] = body
		local x = Index(letter)
		local d = x.ids[rec.id]
		local g = d and x.dig[d]
		if g then g.n, g.x = g.n + 1, (g.x + R.Short(R.Fingerprint(letter, body, true))) % 4294967296 end
	end
	s.drafts[R.MonthOf(rec.t)] = nil
	local originalDay = Index(letter).ids[rec.id]
	if originalDay then s.drafts[R.MonthOf(originalDay * 86400)] = nil end
	stats.clash = stats.clash + 1
	local spec = R.TYPES[letter]
	if spec.Conflict then ns.SafeCall("records conflict", spec.Conflict, rec) end
	ns.Fire("RECORDS_CHANGED", letter)
	return false, "conflict"
end

local function Pend(letter, s, rec, body, d, sender)
	local key = rec.id .. "|" .. A().Hash36(body, 8)
	if s.pend[key] then return false, "pending" end
	local by = Low(sender) or "?"
	local n, same, oldest, at = 0, 0, nil, nil
	for id, p in pairs(s.pend) do
		n = n + 1
		if type(p) == "table" and p.by == by then same = same + 1 end
		local t = type(p) == "table" and tonumber(p.at) or 0
		if not at or t < at then oldest, at = id, t end
	end
	if same >= R.PENDING_EACH then return Count("pending-sender") end
	if n >= R.PENDING_MAX and oldest then
		s.pend[oldest] = nil
		Count("pending-out")
	end
	s.pend[key] = { id = rec.id, b = body, d = d, at = Now(), by = by }
	stats.pending = stats.pending + 1
	EnsureTicker()
	return false, "pending"
end

-- A record checked (each signature good): kept, told to its type, our key declared if it names us.
local function Keep(letter, rec, body, sender, how)
	local s = Store(letter, true)
	local x = Index(letter)
	if not s then return false, "store" end
	local d = floor(rec.t / 86400)
	if Compacted(s, d) then return false, "sealed" end
	-- All mutation, including conflicts, is after both signatures and their identity pins held.
	for _, p in ipairs(rec.parts) do if not R.HasKey(p.name, p.pk64) then return Count("pin") end end
	local held = x.ids[rec.id]
	if held then
		local hb = s.days[held] and s.days[held][rec.id]
		local ok, old = pcall(R.TYPES[letter].Read, hb)
		if hb == body or (ok and old and old.content == rec.content) then
			if R.Accepted then R.Accepted(letter, d) end
			return false, "again"
		end
		if how == "relay" then FromCount(sender, true) end
		return Clash(letter, s, rec, body)
	end
	if s.clash[rec.id] then return Clash(letter, s, rec, body) end
	-- Recheck quotas here: checks may have been started before any of their callbacks completed.
	if how == "relay" and FromCount(sender) >= R.FROM_DAY_MAX then return Count("flood") end
	local cap = tonumber(R.TYPES[letter].DAY_MAX)
	local a, b = Players(rec.id)
	local per = PerDay(x, s, d)
	if cap and ((a and (per[a] or 0) >= cap) or (b and (per[b] or 0) >= cap)) then return Count("full") end
	s.days[d] = s.days[d] or {}
	s.days[d][rec.id] = body
	Add(x, d, rec.id, body)
	for key, p in pairs(s.pend) do if key == rec.id or p.id == rec.id then s.pend[key] = nil end end
	s.drafts[R.MonthOf(rec.t)] = nil -- a late valid record invalidates an unsigned draft
	if how == "relay" then FromCount(sender, true) end
	stats.kept = stats.kept + 1
	if R.Accepted then R.Accepted(letter, d) end
	EnsureTicker()
	if Names(rec.id, Low(Me())) then KeyLater() end
	local spec = R.TYPES[letter]
	if spec.Took then ns.SafeCall("records took", spec.Took, rec, how, body) end
	ns.Fire("RECORDS_CHANGED", letter)
	return true
end

-- Each part's signature through the arena's queue (Arena.Check), CHECKS_MAX records at once; the
-- rest wait their turn (WAIT_MAX), and a full queue tries again LATER.
local function Check(letter, rec, body, sender, how)
	local key = letter .. "|" .. rec.id
	if checking[key] then return false, "checking" end
	local by = Low(sender) or "?"
	local function Queue()
		local same = 0
		for _, w in ipairs(waitq) do if (Low(w[3]) or "?") == by then same = same + 1 end end
		if same >= R.WAIT_EACH then return Count("busy-sender") end
		if #waitq >= R.WAIT_MAX then return Count("busy") end
		waitq[#waitq + 1] = { letter, body, sender, how }
		return false, "waiting"
	end
	if inflight >= R.CHECKS_MAX or (checkingBy[by] or 0) >= R.CHECKS_EACH then
		return Queue()
	end
	checking[key] = by
	checkingBy[by] = (checkingBy[by] or 0) + 1
	inflight = inflight + 1
	local left, bad, later = #rec.parts, false, false
	for _, p in ipairs(rec.parts) do
		A().Check("rec " .. p.sig64 .. A().Hash36(p.msg, 8), { pk = p.pk, msg = p.msg, sig = p.sig }, function(ok)
			if ok == nil then later = true elseif not ok then bad = true end
			left = left - 1
			if left > 0 then return end
			checking[key] = nil
			checkingBy[by] = math.max(0, (checkingBy[by] or 1) - 1)
			if checkingBy[by] == 0 then checkingBy[by] = nil end
			inflight = inflight - 1
			if bad then
				Count("signature")
			elseif later then
				local _, why = Queue()
				if why == "waiting" then
					A().After(R.LATER, "records later", function() PumpWait() end)
					return -- a full verifier must not synchronously retry its own deferred work
				end
			else
				Keep(letter, rec, body, sender, how)
			end
			PumpWait()
		end)
	end
	return true, "checking"
end
PumpWait = function()
	-- Examine each queued row at most once in this pass. A sender already at CHECKS_EACH is
	-- appended again by Check; a bounded pass reaches another sender behind it without spinning.
	local remaining = #waitq
	while remaining > 0 and waitq[1] and inflight < R.CHECKS_MAX do
		remaining = remaining - 1
		local w = table.remove(waitq, 1)
		Take(w[1], w[2], w[3], w[4])
	end
end

-- A record of type letter heard from sender. how: "self" (this client's own module made it from
-- halves it heard), "relay" (RR), "pending" (its key arrived). Returns ok, why, and its day.
local PinWitnessed -- below, with the verified witness cache
Take = function(letter, body, sender, how)
	local spec = R.TYPES[letter]
	if not spec then return Count("type") end
	if type(body) ~= "string" or #body > R.BODY_MAX then return Count("shape") end
	local ok, rec, why = pcall(spec.Read, body)
	if not ok or type(rec) ~= "table" then return Count(ok and (why or "shape") or "read") end
	if type(rec.id) ~= "string" or type(rec.t) ~= "number" or type(rec.parts) ~= "table" or not rec.parts[1] then return Count("shape") end
	if rec.t > Now() + R.AHEAD then return Count("time") end
	local d = floor(rec.t / 86400)
	local s = Store(letter, true)
	if not s then return Count("store") end
	local x = Index(letter)
	if Compacted(s, d) then return false, "sealed", d end
	local held = x.ids[rec.id]
	if held then
		local hb = s.days[held] and s.days[held][rec.id]
		if hb == body then stats.again = stats.again + 1 return false, "again", d end
		local okHeld, hr = pcall(spec.Read, hb)
		if okHeld and type(hr) == "table" and hr.content == rec.content then stats.again = stats.again + 1 return false, "again", d end
	end
	if how == "relay" and FromCount(sender) >= R.FROM_DAY_MAX then return Count("flood") end
	local cap = tonumber(spec.DAY_MAX)
	if cap and not held then
		local per = PerDay(x, s, d)
		local a, b = Players(rec.id)
		if (a and (per[a] or 0) >= cap) or (b and (per[b] or 0) >= cap) then return Count("full") end
	end
	for _, p in ipairs(rec.parts) do
		local keys = R.KeysOf(p.name)
		if not keys and PinWitnessed(letter, body, rec) then keys = R.KeysOf(p.name) end
		if not keys then
			if how == "relay" then FromCount(sender, true) end
			local _, w = Pend(letter, s, rec, body, d, sender)
			return false, w, d
		end
		if not keys[p.pk64] then return Count("pin") end
	end
	if how == "relay" then
		FromCount(sender)
		local key = Low(sender) or "?"
		if (attempts[key] or 0) >= R.CHECK_DAY_MAX then return Count("checks-full") end
		attempts[key] = (attempts[key] or 0) + 1
	end
	local started, w = Check(letter, rec, body, sender, how)
	return started, w, d
end
R.Take = function(...) return Take(...) end

-- The records waiting for a key that names this player, taken again (his key just came).
Unpend = function(low)
	for letter in pairs(R.TYPES) do
		local s = Store(letter)
		if s then
			local list = {}
			for id, p in pairs(s.pend) do
				if type(p) ~= "table" or type(p.b) ~= "string" then s.pend[id] = nil
				elseif not low or Names(p.id or id, low) then list[#list + 1] = { id = id, p = p } end
			end
			table.sort(list, function(a, b) return (tonumber(a.p.at) or 0) < (tonumber(b.p.at) or 0) end)
			for _, e in ipairs(list) do Take(letter, e.p.b, e.p.by or "?", "pending") end
		end
	end
end
function R.RecheckPending() Unpend(nil) end

---------------------------------------------------------------------------
-- Telling: the digest, the ask, the answer (anti-entropy)
---------------------------------------------------------------------------

local function Users()
	local C, K = ns.Comm, ns.King
	local users = 1
	if type(C) == "table" and type(C.PeerCount) == "function" then
		local ok, n = pcall(C.PeerCount, true)
		if ok and tonumber(n) then users = tonumber(n) + 1 end
	end
	if type(K) == "table" and type(K.AddonsOnline) == "function" then
		local ok, n = pcall(K.AddonsOnline)
		if ok and tonumber(n) then users = max(users, tonumber(n)) end
	end
	return users
end
-- A round's slots spread over this many seconds: the army's size as this client sees it, within
-- DIGEST_WINDOW_MIN and _MAX (each client's own: the King's turn comes after the widest).
function R.DigestWindow() return max(R.DIGEST_WINDOW_MIN, min(R.DIGEST_WINDOW_MAX, Users())) end

-- What waits on the low lane: { kind, k (what makes it the same), body, day }, the newest days first.
-- A body may be a function that makes it when its turn comes (a validation's signature: one a
-- message, never a whole day's signed at once on one frame); one that makes nothing is skipped.
-- A relay (every item but the author's own pasted seal: own) is looked at again when its turn
-- comes: nothing leaves a client barred since (R.Bar: its quiet presence turned on meanwhile).
local outq, outSet = {}, {}
local function Producer()
	while true do
		local item = table.remove(outq, 1)
		if not item then return nil end
		outSet[item.k] = nil
		local body, extra = item.body, nil
		if not item.own and Barred() then
			body = nil
		elseif type(body) == "function" then
			local ok, made, more = pcall(body)
			body, extra = ok and made or nil, ok and type(more) == "table" and more or nil
		end
		if type(body) == "string" then
			stats.sent = stats.sent + 1
			return { item.kind, "L", body, { dist = "CHANNEL", done = extra and extra.done } }
		end
	end
end
local function Out(kind, k, body, day, own)
	if outSet[k] then return false end
	if #outq >= R.OUT_MAX then return Count("out-full") end
	outSet[k] = true
	local item = { kind = kind, k = k, body = body, day = day or math.huge, own = own and true or nil }
	local at = #outq + 1
	for i, o in ipairs(outq) do
		if (o.day or 0) < item.day then at = i break end
	end
	table.insert(outq, at, item)
	A().Later("records", Producer)
	return true
end
function R.OutSize() return #outq end

-- A holder's signed validation follows its fresh key declaration. It is queued beside the record
-- on the low lane and binds the full body hash, so it cannot be reused for another result.
-- (keyed: the caller declared the key once for its whole answer. The signature is made when the
-- validation's turn on the low lane comes, one a message: an answer of a day's records never
-- signs them all, and the key with each, on one frame.)
-- (1.4.0, since: the ask's time. When its turn comes it stays home if WITNESSES other holders'
-- validations of that record were heard since that ask: what was heard before an ask never
-- silences an answer to it (a validation the asker refused, its sender's key not yet with it,
-- must not keep the next ask from fresh ones). One already waiting takes the newest ask's time.)
local witnessSince = {} -- [the RV's Out key] = the newest ask's time it answers
local function WitnessBody(letter, hash, pk64, sign)
	local t = B36(Now())
	local signed, sig = pcall(sign, WitnessText(Me(), letter, hash, t, pk64))
	if not signed or type(sig) ~= "string" or #sig ~= 64 then return nil end
	return table.concat({ letter, hash, t, pk64, B64(sig) }, "~")
end
function R.SendWitness(letter, body, day, keyed, hash, since)
	if not R.TYPES[letter] or type(body) ~= "string" or Barred() then return false end
	local okRecord, rec = pcall(R.TYPES[letter].Read, body)
	local heldDay = okRecord and type(rec) == "table" and Index(letter).ids[rec.id]
	local held = heldDay and Store(letter) and Store(letter).days[heldDay]
	if not (held and held[rec.id] == body) then return false end
	local D = ns.Debts
	if type(D) ~= "table" or type(D.MyKey) ~= "function" or type(D.Sign) ~= "function" then return false end
	local ok, gk, pk = pcall(D.MyKey)
	if not ok or not gk or type(pk) ~= "string" or #pk ~= 32 then return false end
	local pk64 = B64(pk)
	hash = hash or RecordHash(letter, body)
	-- Repeated asks may come from clients that were absent for the last declaration.
	if not keyed then R.SendKey() end
	local k = "v" .. letter .. hash .. (Low(Me()) or "?")
	since = tonumber(since)
	local queued = outSet[k] == true
	if since then witnessSince[k] = max(witnessSince[k] or since, since) end
	local ok = Out("RV", k, function()
		local after = witnessSince[k]
		witnessSince[k] = nil
		if after and R.WitnessesSince(letter, hash, after) >= R.WITNESSES then
			stats.witnessCovered = (stats.witnessCovered or 0) + 1
			return nil
		end
		return WitnessBody(letter, hash, pk64, D.Sign)
	end, day)
	if not ok and not queued then witnessSince[k] = nil end
	return ok
end

local lastDigest = {}
local heard, digestSerial, roundHeard, roundDue = {}, {}, {}, {} -- (the rounds, below)
local digestHeard = {}   -- [letter] = true: another holder's digest of that type heard this session (R.Discover)
local mySent = {}        -- [letter] = { at, days = { [day] = true }, months = { [month] = true } }: our last digest
local jobsAt, askerJobs = {}, {} -- the budget: when our jobs went (all of them; [asker] = an asker's)
local heardBody = {}     -- [letter] = { [Hash36 of a record's body] = when an RR of it was heard }
local lag = { n = 0, sum = 0, max = 0 } -- seconds from a digest's slot to the wire (Comm sent it)
local askedAt, heardAsk, answeredAt, heardRecordAt, answering, askCursor, witnessedAt = {}, {}, {}, {}, {}, {}, {}
local asking = {} -- one day request in transport per letter, until its send completes
local function Per(t, letter)
	local x = t[letter]
	if not x then x = {} t[letter] = x end
	local n, oldest, at = 0, nil, math.huge
	for k, v in pairs(x) do n = n + 1 if type(v) == "number" and v < at then oldest, at = k, v end end
	if n >= R.CONTROL_MAX and oldest then x[oldest] = nil end
	return x
end
function R.Accepted(letter, day) Per(heardRecordAt, letter)[day] = Now() end

-- This client's digest of a type: "letter~day.n.sum,...~month.hash8,...", or nil when it holds
-- nothing of it.
function R.DigestBody(letter)
	local s = Store(letter)
	if not s then return nil end
	local x = Index(letter)
	local days = {}
	for d in pairs(x.dig) do days[#days + 1] = d end
	table.sort(days, function(a, b) return a > b end)
	local selected, nextPage = {}, 0
	local head = min(#days, R.DIGEST_RECENT, R.DIGEST_DAYS)
	for i = 1, head do selected[#selected + 1] = days[i] end
	local older = #days - head
	local room = min(older, R.DIGEST_DAYS - head)
	if room > 0 then
		local page = (x.digestPage or 0) % older
		for i = 0, room - 1 do selected[#selected + 1] = days[head + 1 + (page + i) % older] end
		if older > room then nextPage = (page + room) % older end
	end
	table.sort(selected, function(a, b) return a > b end)
	local parts = {}
	for _, day in ipairs(selected) do
		local g = x.dig[day]
		parts[#parts + 1] = B36(day) .. "." .. B36(g.n) .. "." .. B36(g.x)
	end
	local months = {}
	for m, seal in pairs(s.seals) do if type(m) == "number" and Adopted(seal) then months[#months + 1] = m end end
	table.sort(months, function(a, b) return a > b end)
	local mparts, nextMonthPage = {}, 0
	if months[1] then
		mparts[1] = B36(months[1]) .. "." .. s.seals[months[1]].h:sub(1, 8)
		local olderMonths = #months - 1
		local slots = min(olderMonths, R.DIGEST_MONTHS - 1)
		if slots > 0 then
			local page = (x.digestMonthPage or 0) % olderMonths
			for i = 0, slots - 1 do
				local month = months[2 + (page + i) % olderMonths]
				mparts[#mparts + 1] = B36(month) .. "." .. s.seals[month].h:sub(1, 8)
			end
			if olderMonths > slots then nextMonthPage = (page + slots) % olderMonths end
		end
	end
	if not parts[1] and not mparts[1] then return nil end
	return letter .. "~" .. table.concat(parts, ",") .. "~" .. table.concat(mparts, ","), nextPage, nextMonthPage
end
-- 1.4.0, the rounds (no draw). A digest's facts: "d<day>.<n>.<sum>" and "m<month>.<hash8>" (a
-- list), and its days and months (sets).
local function DigestFacts(days, months)
	local facts, dset, mset = {}, {}, {}
	for item in (tostring(days or "") .. ","):gmatch("([^,]*),") do
		local d, n, h = item:match("^([0-9a-z]+)%.([0-9a-z]+)%.([0-9a-z]+)$")
		d, n, h = N36(d, 0, 400000), N36(n, 0, 1000000), N36(h, 0, 4294967295)
		if d and n and h and not dset[d] then
			dset[d] = true
			facts[#facts + 1] = ("d%d.%d.%d"):format(d, n, h)
		end
	end
	for item in (tostring(months or "") .. ","):gmatch("([^,]*),") do
		local m, h8 = item:match("^([0-9a-z]+)%.(%x+)$")
		m = N36(m, 0, 100000)
		if m and h8 and #h8 == 8 and not mset[m] then
			mset[m] = true
			facts[#facts + 1] = ("m%d.%s"):format(m, h8:lower())
		end
	end
	return facts, dset, mset
end
R.DigestFacts = DigestFacts

-- The answer budget: one more job (a digest, a push, or an answer to `asker`'s ask) within BUDGET
-- a BUDGET_EVERY, and ASKER_JOBS of them for one asker (one client cannot spend every holder's
-- budget). Spent only for a job that goes (Spend); CanSpend only looks.
local function Recent(list, now)
	while list[1] and now - list[1] >= R.BUDGET_EVERY do table.remove(list, 1) end
	return #list
end
local function CanSpend(asker)
	local now = Now()
	if Recent(jobsAt, now) >= R.BUDGET then return false, "budget" end
	local list = asker and askerJobs[asker]
	if list and Recent(list, now) >= R.ASKER_JOBS then return false, "asker" end
	return true
end
local function Spend(asker)
	local ok, why = CanSpend(asker)
	if not ok then
		stats[why] = (stats[why] or 0) + 1
		return false
	end
	local now = Now()
	jobsAt[#jobsAt + 1] = now
	if asker then
		local list = askerJobs[asker]
		if not list then
			local n, oldest, at = 0, nil, math.huge
			for k, l in pairs(askerJobs) do
				n = n + 1
				local last = l[#l] or -math.huge
				if last < at then oldest, at = k, last end
			end
			if n >= R.CONTROL_MAX and oldest then askerJobs[oldest] = nil end
			list = {}
			askerJobs[asker] = list
		end
		list[#list + 1] = now
	end
	return true
end
-- (CanSpend, counted in the stats when there is no room: an ask past it is not even waited on.)
local function Room(asker)
	local ok, why = CanSpend(asker)
	if not ok then stats[why] = (stats[why] or 0) + 1 end
	return ok
end
function R.Budget() return R.BUDGET - Recent(jobsAt, Now()) end

-- A digest of ours went out: what it told (the asks it makes us answer first), the push's gap.
-- An answer of ours waiting as a fallback for a day or month it named comes forward: the ask was
-- made before our digest went, and it is ours to answer first now.
local Promote -- (below)
local function Told(letter, body)
	local now = Now()
	lastDigest[letter] = now
	stats.digests = stats.digests + 1
	local _, days, months = A().Fields(body, 3)
	local _, dset, mset = DigestFacts(days, months)
	mySent[letter] = { at = now, days = dset, months = mset }
	Promote(letter)
end
function R.SendDigest(letter)
	if Barred() then return false end
	local body, nextPage, nextMonthPage = R.DigestBody(letter)
	if not body then return false end
	local sent = A().Send("RD", "L", body, { dist = "CHANNEL", key = "records digest " .. letter, low = true }) == true
	-- A full transport queue must not silently skip a historical page.
	if sent then
		Told(letter, body)
		local x = Index(letter)
		x.digestPage, x.digestMonthPage = nextPage, nextMonthPage
	end
	return sent
end

-- Another holder's digest heard: for each of its facts the ELECT newest distinct senders that told
-- it (when, and the digests heard so far: an order finer than the clock's second). Bounded by
-- HEARD_MAX facts a type; a fact over that is not remembered (which silences nothing).
local function Heard(letter, by, facts, now, serial)
	local h = heard[letter]
	if not h then h = { n = 0, items = {}, pruned = -math.huge } heard[letter] = h end
	for _, fact in ipairs(facts) do
		local list = h.items[fact]
		if not list then
			if h.n >= R.HEARD_MAX and now - h.pruned >= 60 then
				h.pruned = now
				for k, l in pairs(h.items) do
					if now - l[1].at > 2 * R.DIGEST_EVERY then h.items[k], h.n = nil, h.n - 1 end
				end
			end
			if h.n >= R.HEARD_MAX then stats.heardFull = (stats.heardFull or 0) + 1 return end
			list = {}
			h.items[fact], h.n = list, h.n + 1
		end
		for i = #list, 1, -1 do if list[i].by == by then table.remove(list, i) end end
		table.insert(list, 1, { by = by, at = now, serial = serial })
		while #list > R.ELECT do list[#list] = nil end
	end
end
-- Whether this client's digest of a type would tell nothing new: each day and month it would name
-- told, the same, by ELECT other holders heard since `since` (server time) or after digest `serial`.
-- A digest that lacks anything this client holds, or says another count, silences nothing: a
-- holder of the only copy of a record always tells it.
local function Covered(letter, since, serial)
	local body = R.DigestBody(letter)
	if not body then return true end
	local _, days, months = A().Fields(body, 3)
	local facts = DigestFacts(days, months)
	local h = heard[letter]
	if not (h and facts[1]) then return false end
	for _, fact in ipairs(facts) do
		local n = 0
		for _, e in ipairs(h.items[fact] or {}) do
			if (serial and e.serial > serial) or (not serial and e.at >= since) then n = n + 1 end
		end
		if n < R.ELECT then return false end
	end
	return true
end
R.Covered = Covered
-- Distinct holders whose digest of a type (with any fact) this client heard this round.
function R.RoundHeard(letter)
	local x = roundHeard[letter]
	return x and x.r == floor(Now() / R.DIGEST_EVERY) and x.n or 0
end
function R.Lag() return lag end

-- Our digest through the records' own low lane (as the answers go): `covered` is asked again when
-- its turn comes (Comm's queue may hold it a while, and other holders' digests arrive meanwhile).
-- Its page advances once it left.
local function QueueDigest(letter, covered, slotAt)
	return Out("RD", "D|" .. letter, function()
		if covered and covered() then stats.covered = (stats.covered or 0) + 1 return nil end
		local body, nextPage, nextMonthPage = R.DigestBody(letter)
		if not body or not Spend() then return nil end
		Told(letter, body)
		return body, { done = function(sent)
			if not sent then return end
			if slotAt then
				local l = max(0, Now() - slotAt)
				lag.n, lag.sum, lag.max = lag.n + 1, lag.sum + l, max(lag.max, l)
			end
			local x = Index(letter)
			x.digestPage, x.digestMonthPage = nextPage, nextMonthPage
		end }
	end, math.huge)
end
-- A round's digest of a type, at this holder's slot (round r: from r * DIGEST_EVERY): not when
-- ours went this round already (a push).
local function RoundDigest(letter, round, slotAt)
	local since = round * R.DIGEST_EVERY
	local function covered() return Barred() or (lastDigest[letter] or -math.huge) >= since or Covered(letter, since) end
	if covered() then stats.covered = (stats.covered or 0) + 1 return end
	QueueDigest(letter, covered, slotAt)
end
-- This holder's slots in this round and the next two (the clock's ticks come a period apart, the
-- first one a random part of a period later), for each type it holds anything of.
ScheduleRounds = function()
	local now = Now()
	local r = floor(now / R.DIGEST_EVERY)
	for letter in pairs(R.TYPES) do
		local s = Store(letter)
		local due = roundDue[letter]
		if not due then due = {} roundDue[letter] = due end
		for round in pairs(due) do if round < r then due[round] = nil end end
		if s and (next(Index(letter).dig) or next(s.seals)) then
			for round = r, r + 2 do
				if not due[round] then
					local at = R.Slot("RD|" .. letter .. "|" .. round, Me(), round * R.DIGEST_EVERY, R.DigestWindow(), R.DIGEST_WINDOW_MAX)
					if at and at >= now then
						due[round] = true
						ns.After(at - now, "records round " .. letter, function()
							local d = roundDue[letter]
							if not (d and d[round]) then return end
							d[round] = nil
							RoundDigest(letter, round, at)
						end)
					end
				end
			end
		end
	end
end

-- An ask for one day's records: the prefixes of the ids this client holds of it. (A read: it goes
-- even while this client's quiet presence is on, as Comm.QUIET_WORDS lets a read go and
-- Treasury.Ask its first ask; what this client would tell or answer stays home, R.Bar.)
local function HeldPrefixes(letter, d)
	local s = Store(letter)
	local held = {}
	for id, body in pairs(s and s.days[d] or {}) do
		held[#held + 1] = R.Fingerprint(letter, body)
		for _, other in ipairs(s.clash[id] or {}) do held[#held + 1] = R.Fingerprint(letter, other) end
	end
	-- (and the ones waiting here for a key: their bodies are here already)
	for id, p in pairs(s and s.pend or {}) do
		if type(p) == "table" and tonumber(p.d) == d then held[#held + 1] = R.Fingerprint(letter, p.b) end
	end
	return held
end
local function AskBody(letter, d, remoteCount)
	local held = HeldPrefixes(letter, d)
	table.sort(held)
	-- Large days are requested in hash buckets. The packet and the receiver's scan stay bounded;
	-- repeated requests advance the bucket rather than repeatedly sending a truncated prefix list.
	local bucket, nextCursor = "", nil
	if max(#held, tonumber(remoteCount) or 0) > R.ASK_PREFIX_MAX then
		local width = max(#held, tonumber(remoteCount) or 0) > R.ASK_PREFIX_MAX * 16 and 2 or 1
		local cursors = Per(askCursor, letter)
		local value = cursors[d] or 0
		local span = 16 ^ width
		bucket = ("%0" .. width .. "x"):format(value % span)
		nextCursor = value + 1
		local selected = {}
		for _, prefix in ipairs(held) do if prefix:sub(1, width) == bucket and #selected < R.ASK_PREFIX_MAX then selected[#selected + 1] = prefix end end
		held = selected
	end
	return letter .. "~d~" .. B36(d) .. "~" .. (bucket ~= "" and bucket .. ":" or "") .. table.concat(held), nextCursor
end

local function BeginAsk(letter, d, remoteCount)
	local pending = Per(asking, letter)
	if pending[d] then return nil end
	local body, nextCursor = AskBody(letter, d, remoteCount)
	local ticket = {}
	pending[d] = ticket
	return body, function(sent)
		if asking[letter] ~= pending or pending[d] ~= ticket then return end
		pending[d] = nil
		if not sent then return end
		Per(askedAt, letter)[d] = Now()
		if nextCursor then Per(askCursor, letter)[d] = nextCursor end
		stats.asked = stats.asked + 1
		R.AskWitness(letter, d)
	end
end
function R.Ask(letter, d, remoteCount)
	local body, done = BeginAsk(letter, d, remoteCount)
	if not body then return false end
	local sent = A().Send("RA", "L", body, { dist = "CHANNEL", key = "records ask " .. letter .. d, low = true, done = done }) == true
	if not sent then done(false) end
	return sent
end

-- 1.4.0, an ask a digest set off waits its turn: score("RA|letter|day|round") × ASK_SPREAD (every
-- client that heard the digest lacks the same, and each asked at once: a hundred late clients, a
-- hundred asks of one day). Its turn come, it leaves through the records' low lane and is looked at
-- once more when it leaves: it stays home when what the digest told came meanwhile, or when an ask
-- heard since asked for all ours would (it named no record this client lacks, in no bucket: the
-- answers go on the channel, to everyone). Its validations-alone ask (R.AskWitness) likewise, when
-- a heard one named every record this client waits on.
local askWait = {} -- [letter] = { [day] = { at, n, x (the digest's count and sum), covered, witnessCovered } }
local function AskTurn(letter, d)
	local waits = askWait[letter]
	if not (waits and waits[d]) then return end
	local k = "A|" .. letter .. d
	if outSet[k] then return end -- (one waiting already serves this one)
	local ok = Out("RA", k, function()
		local e = waits[d]
		waits[d] = nil
		if not e then return nil end
		local g = Index(letter).dig[d]
		if e.covered or (g and g.n == e.n and g.x == e.x) then
			stats.askMerged = (stats.askMerged or 0) + 1
			if not e.witnessCovered then R.AskWitness(letter, d) end
			return nil
		end
		local body, done = BeginAsk(letter, d, e.n)
		return body, { done = done }
	end, d)
	if not ok then waits[d] = nil end
end
local function QueueAsk(letter, d, n, x, now)
	if asking[letter] and asking[letter][d] then return false end
	local waits = askWait[letter]
	if not waits then waits = {} askWait[letter] = waits end
	local e = waits[d]
	if e and now - e.at < R.ASK_GAP then return false end
	waits[d] = { at = now, n = n, x = x }
	local delay = R.Score("RA|" .. letter .. "|" .. d .. "|" .. floor(now / R.DIGEST_EVERY), Me()) * R.ASK_SPREAD
	ns.After(delay, "records ask " .. letter, function() AskTurn(letter, d) end)
	return true
end
-- A heard ask of day d (its bucket, its prefixes) or validations-alone ask (its set of prefixes):
-- whether it asked for all ours would.
local function MergeAsk(letter, d, bucket, rest)
	local e = askWait[letter] and askWait[letter][d]
	if not e or e.covered or bucket ~= "" then return end
	local mine = {}
	for _, p in ipairs(HeldPrefixes(letter, d)) do mine[p] = true end
	for i = 1, #rest, R.PREFIX do if not mine[rest:sub(i, i + R.PREFIX - 1)] then return end end
	e.covered = true
end
local function MergeWitnessAsk(letter, d, wanted)
	local e = askWait[letter] and askWait[letter][d]
	if not e or e.witnessCovered then return end
	local s = Store(letter)
	for _, p in pairs(s and s.pend or {}) do
		if type(p) == "table" and tonumber(p.d) == d and type(p.b) == "string" and not wanted[R.Fingerprint(letter, p.b)] then return end
	end
	e.witnessCovered = true
end

-- (1.2.6) The records of that day waiting here, whose bodies are here already, named again for
-- the live holders' validations alone (RV, never the bodies again). The ask above lists them as
-- held, so no holder answers them there; and the two validations that admit them are heard in
-- this session only: one holder alone for the first answer, a validation heard before its
-- holder's key, or a reload left them short, and they waited for good. Asked with each ask of
-- their day until they are kept. (Clients before 1.2.6 do not know "w" and take it for nothing.)
function R.AskWitness(letter, d)
	local s = Store(letter)
	local list, seen = {}, {}
	for _, p in pairs(s and s.pend or {}) do
		if type(p) == "table" and tonumber(p.d) == d and type(p.b) == "string" then
			local prefix = R.Fingerprint(letter, p.b)
			if not seen[prefix] then seen[prefix] = true list[#list + 1] = prefix end
		end
	end
	if not list[1] then return false end
	if cross.Ask then cross.Ask(letter, d) end
	table.sort(list)
	while #list > R.ASK_PREFIX_MAX do list[#list] = nil end
	return A().Send("RA", "L", letter .. "~w~" .. B36(d) .. "~" .. table.concat(list), { dist = "CHANNEL", key = "records witness ask " .. letter .. d, low = true }) == true
end

local AskSeal -- (below)
local function OnDigest(dist, sender, mode, body)
	if mode ~= "L" or dist ~= "CHANNEL" then return Count("lane") end
	if type(body) ~= "string" or #body > 6000 then return Count("shape") end
	local letter, days, months = A().Fields(body, 3)
	if not (letter and R.TYPES[letter]) then return Count("type") end
	local now = Now()
	-- What it told, for this round's and the pushes' "already told" (Covered): a digest with no
	-- fact counts for nothing.
	local facts, by = DigestFacts(days, months), Low(sender)
	if facts[1] and by then
		digestHeard[letter] = true
		digestSerial[letter] = (digestSerial[letter] or 0) + 1
		Heard(letter, by, facts, now, digestSerial[letter])
		local r = floor(now / R.DIGEST_EVERY)
		local rh = roundHeard[letter]
		if not rh or rh.r ~= r then rh = { r = r, n = 0, by = {} } roundHeard[letter] = rh end
		if not rh.by[by] and rh.n < R.CONTROL_MAX then rh.by[by], rh.n = true, rh.n + 1 end
	end
	local s = Store(letter)
	local x = Index(letter)
	local listed, nListed, newest, need, counts, sums, push = {}, 0, -math.huge, {}, {}, {}, false
	for item in (days .. ","):gmatch("([^,]*),") do
		local d, n, h = item:match("^([0-9a-z]+)%.([0-9a-z]+)%.([0-9a-z]+)$")
		d, n, h = N36(d, 0, 400000), N36(n, 0, 1000000), N36(h, 0, 4294967295)
		if d and n and h and not listed[d] then
			listed[d], nListed = true, nListed + 1
			newest = max(newest, d)
			if not Compacted(s, d) then
				local g = x.dig[d]
				local mn, mx = g and g.n or 0, g and g.x or 0
				if mn ~= n or mx ~= h then
					if n > 0 then need[#need + 1] = d counts[d], sums[d] = n, h end
					if mn > 0 then push = true end
				end
			end
		end
	end
	-- A full page rotates older days; their omission says nothing about the peer's
	-- inventory. Only a newer day (the newest days are always named), or an omission
	-- from a short, complete inventory establishes that a push is useful.
	for d in pairs(x.dig) do
		if not listed[d] and (d > newest or nListed < R.DIGEST_DAYS) then push = true break end
	end
	table.sort(need, function(a, b) return a > b end)
	local asks = 0
	for _, d in ipairs(need) do
		if asks >= R.ASK_DAYS then break end
		if now - (Per(askedAt, letter)[d] or -math.huge) >= R.ASK_GAP and now - (Per(heardAsk, letter)[d] or -math.huge) >= R.ANSWER_GAP
			and QueueAsk(letter, d, counts[d], sums[d], now) then
			asks = asks + 1
		end
	end
	-- Sealed months: one held elsewhere and not here (or another seal of it) asked for.
	local mlisted, nMonths, newestMonth = {}, 0, -math.huge
	for item in (tostring(months or "") .. ","):gmatch("([^,]*),") do
		local m, h8 = item:match("^([0-9a-z]+)%.(%x+)$")
		m = N36(m, 0, 100000)
		if m and h8 and #h8 == 8 and not mlisted[m] then
			mlisted[m] = true
			nMonths, newestMonth = nMonths + 1, max(newestMonth, m)
			local seal = s and s.seals[m]
			if not (Adopted(seal) and seal.h:sub(1, 8) == h8:lower()) then AskSeal(letter, m) end
		end
	end
	for m, seal in pairs(s and s.seals or {}) do
		if Adopted(seal) and not mlisted[m] and (m > newestMonth or nMonths < R.DIGEST_MONTHS) then push = true break end
	end
	-- It lacks what this client holds: our own digest, at our slot a few seconds later (R.Slot:
	-- the King's after everyone's), unless ELECT other holders' digests heard meanwhile told all
	-- ours would (Covered; one that lacks the same as this one silences nothing).
	if push and s and now - (lastDigest[letter] or -math.huge) >= R.PUSH_GAP and not answering["digest" .. letter] then
		local at = R.Slot("RP|" .. letter .. "|" .. floor(now / R.DIGEST_EVERY), Me(), R.PUSH_MIN, R.PUSH_WINDOW, R.PUSH_WINDOW)
		if at then
			answering["digest" .. letter] = true
			local serial = digestSerial[letter] or 0
			local function covered() return Barred() or Covered(letter, nil, serial) end
			A().After(at, "records push " .. letter, function()
				answering["digest" .. letter] = nil
				if covered() then stats.covered = (stats.covered or 0) + 1 return end
				QueueDigest(letter, covered, Now())
			end)
		end
	end
end
ns.Comm.Handle("RD", ns.Arena.Handle("RD", OnDigest))

-- 1.5.2, discovery (RH). A client that holds nothing sends nothing at its login (the weight rule):
-- it learns what the holders hold from their rounds, a round and its window later. When the player
-- first opens a ranking view in a session (the Games tab's rankings, the crafting ranking), it asks
-- for the digests of the types it heard none of this session ("RH~L1~1~<letters>~<request>"), once; and once
-- more DISCOVERY_RETRY later if still none came: DISCOVERY_MAX a session. Not while its quiet
-- presence is on (an ask would say it is online). A client that heard a digest of a type asks for
-- none of it: a holder that logged in more than a round ago asks for nothing.
-- Each holder answers with a reply round of its own of that type, as a round's digest: at its slot,
-- DISCOVERY_MIN + score("RH|letter|minute") × the round's window (the King's after the widest; the
-- author's and a quiet client's never), staying home once ELECT other holders' digests heard since
-- the ask told all its own would. One reply round of a type a DISCOVERY_GAP, whoever asked: an ask
-- heard while a round waits makes the digests heard before it count for nothing (its asker may not
-- have heard them) and never puts a slot later.
local discoveryPending, discoveryRetry, discoverySent = nil, nil, 0
local replyRound, replyStarted = {}, {} -- [letter] = { base, at } (the round waiting); [letter] = when the last began
local function SendDiscovery()
	if discoveryPending or discoveryRetry or discoverySent >= R.DISCOVERY_MAX or Quiet() then return false end
	local list = {}
	for letter in pairs(R.TYPES) do if not digestHeard[letter] then list[#list + 1] = letter end end
	if not list[1] then return false end
	table.sort(list)
	-- Relay remembers origin+body for five minutes. A bounded per-attempt tag keeps the
	-- ninety-second retry distinct while copies of that same request still deduplicate.
	local request = A().B36(Now()) .. "." .. tostring(discoverySent + 1)
	local pending = {}
	discoveryPending = pending
	local function Done(sent)
		if discoveryPending ~= pending then return end
		discoveryPending = nil
		if not sent then return end
		discoverySent = discoverySent + 1
		stats.discovery = discoverySent
		if discoverySent >= R.DISCOVERY_MAX then return end
		discoveryRetry = pending
		ns.After(R.DISCOVERY_RETRY, "records discovery", function()
			if discoveryRetry ~= pending then return end
			discoveryRetry = nil
			SendDiscovery()
		end)
	end
	if A().Send("RH", "L", "1~" .. table.concat(list) .. "~" .. request,
		{ dist = "CHANNEL", key = "records discovery", low = true, done = Done }) ~= true then
		Done(false)
		return false
	end
	return true
end
-- The player opened a ranking view: start the ask or try again if transport dropped it.
function R.Discover()
	local recovered = cross.Ask and cross.Ask()
	return SendDiscovery() or recovered == true
end
local function ReplyRound(letter, now)
	local s = Store(letter)
	if not (s and (next(Index(letter).dig) or next(s.seals))) then return end
	if now - (replyStarted[letter] or -math.huge) < R.DISCOVERY_GAP then return end
	local at = R.Slot("RH|" .. letter .. "|" .. floor(now / 60), Me(), now + R.DISCOVERY_MIN, R.DigestWindow(), R.DIGEST_WINDOW_MAX)
	if not at then return end
	replyStarted[letter] = now
	stats.replyRounds = (stats.replyRounds or 0) + 1
	local due = replyRound[letter]
	if due and due.at > now then
		due.base = now
		if at >= due.at then return end
		due.at = at
	else
		due = { base = now, at = at }
		replyRound[letter] = due
	end
	ns.After(at - now, "records reply " .. letter, function()
		if replyRound[letter] ~= due or Now() < due.at then return end
		replyRound[letter] = nil
		local since = due.base
		local function covered() return Barred() or (lastDigest[letter] or -math.huge) >= since or Covered(letter, since) end
		if covered() then stats.covered = (stats.covered or 0) + 1 return end
		QueueDigest(letter, covered, due.at)
	end)
end
local function OnDiscovery(dist, sender, mode, body)
	if mode ~= "L" or dist ~= "CHANNEL" then return Count("lane") end
	if type(body) ~= "string" or #body > 64 then return Count("shape") end
	local version, letters, request = A().Fields(body, 3)
	if not version then version, letters = A().Fields(body, 2) end -- older two-field asks
	if request and (#request > 14 or not request:match("^[0-9a-z]+%.[12]$")) then return Count("shape") end
	if version ~= "1" or type(letters) ~= "string" or letters == "" or #letters > 32 or letters:find("[^%w]") then return Count("shape") end
	stats.discoveryHeard = (stats.discoveryHeard or 0) + 1
	if Barred() then return end
	local now = Now()
	for letter in letters:gmatch(".") do
		if R.TYPES[letter] then ReplyRound(letter, now) end
	end
end
ns.Comm.Handle("RH", ns.Arena.Handle("RH", OnDiscovery))

local SendSeal -- (below)

-- 1.4.0, who answers an ask (no draw). First, the holders whose digest named that day (or sealed
-- month) within ANSWER_WINDOW, the asks' reason: ANSWER_MIN + score × ANSWER_SPREAD after it (and
-- a holder whose digest goes while the ask waits comes forward, Promote). Then any other holder of
-- it (for validations alone, of that exact record): FALLBACK_MIN + score × half the army (within
-- FALLBACK_SPREAD_MIN and _MAX), the King after the widest, the author's character and a client
-- whose quiet presence is on never (R.Slot). When its turn comes a holder sends only what nobody
-- sent since the ask: a record's body that no RR brought, a validation while fewer than WITNESSES
-- other holders' were heard (a primary that logged out, or a digest whose sender never answers,
-- leaves it to the next turn); nothing at all past its budget (Spend). Each body and validation is
-- looked at again when it leaves the low lane (a validation: against those heard since the ask,
-- R.SendWitness).
local function Primary(letter, field, what)
	local m = mySent[letter]
	return m ~= nil and Now() - m.at <= R.ANSWER_WINDOW and m[field][what] == true
end
local function AnswerTopic(letter, kind, what, now) return ("RQ|%s|%s|%s|%d"):format(letter, kind, tostring(what), floor(now / R.DIGEST_EVERY)) end
-- (The King's turn comes after the widest fallback and after the widest round: a holder whose
-- digest goes late in its round comes forward then, Promote.)
local function AnswerDelay(topic, primary)
	if primary and R.Bar(Me()) == nil then return R.Slot(topic, Me(), R.ANSWER_MIN, R.ANSWER_SPREAD) end
	local spread = max(R.FALLBACK_SPREAD_MIN, min(R.FALLBACK_SPREAD_MAX, Users() / 2))
	return R.Slot(topic, Me(), R.FALLBACK_MIN, spread, max(R.FALLBACK_SPREAD_MAX, R.DIGEST_WINDOW_MAX - R.FALLBACK_MIN))
end
-- An answer job waits under answering[key] = { letter, field, what, topic, name, at, fire }: on the
-- game's own timer (a fallback's wait is minutes long; the arena's ticker need not run meanwhile).
-- Its fire does nothing once the job is no longer the one waiting (answered, brought forward and
-- fired, or a newer one).
local function Wait(key, letter, field, what, now, kind, name, fire)
	local topic = AnswerTopic(letter, kind, what, now)
	local delay = AnswerDelay(topic, Primary(letter, field, what))
	if not delay then return false end
	local job = { letter = letter, field = field, what = what, topic = topic, name = name, at = Now() + delay }
	job.fire = function()
		if answering[key] ~= job then return end
		answering[key] = nil
		if not Barred() then fire() end
	end
	answering[key] = job
	ns.After(delay, name, job.fire)
	return true
end
Promote = function(letter)
	if R.Bar(Me()) ~= nil then return end
	local now = Now()
	for _, job in pairs(answering) do
		if type(job) == "table" and job.letter == letter and Primary(letter, job.field, job.what) and job.at > now + R.ANSWER_MIN + R.ANSWER_SPREAD then
			local delay = R.Slot(job.topic, Me(), R.ANSWER_MIN, R.ANSWER_SPREAD)
			if delay then
				job.at = now + delay
				ns.After(delay, job.name, job.fire)
			end
		end
	end
end

-- Verified, session-only validations by record and sender. Receipt time suppresses repeat answers;
-- the signed time bounds how long a witness can establish a record's missing identity keys.
local rvHeard = {} -- [letter] = { n, pruned, items = { [hash] = { at, by = { [sender] = { heard, signed } } } } }
local RV_SENDERS = 8
local function HeardWitness(letter, hash, by, now, signed)
	local r = rvHeard[letter]
	if not r then r = { n = 0, pruned = -math.huge, items = {} } rvHeard[letter] = r end
	local e = r.items[hash]
	if not e then
		if r.n >= R.RV_HEARD_MAX and now - r.pruned >= 60 then
			r.pruned = now
			for k, v in pairs(r.items) do if now - v.at > R.DIGEST_EVERY then r.items[k], r.n = nil, r.n - 1 end end
		end
		if r.n >= R.RV_HEARD_MAX then stats.rvFull = (stats.rvFull or 0) + 1 return end
		e = { at = now, by = {}, n = 0 }
		r.items[hash], r.n = e, r.n + 1
	end
	if not e.by[by] then
		if e.n >= RV_SENDERS then
			local oldest, at
			for k, v in pairs(e.by) do if not at or v.heard < at then oldest, at = k, v.heard end end
			e.by[oldest], e.n = nil, e.n - 1
		end
		e.n = e.n + 1
	end
	local previous = e.by[by]
	e.by[by], e.at = { heard = now, signed = max(signed, previous and previous.signed or signed) }, now
end
-- Distinct holders whose validation of that record (its RecordHash) was heard here since `since`.
function R.WitnessesSince(letter, hash, since)
	local r = rvHeard[letter]
	local e = r and r.items[hash]
	local n = 0
	for _, v in pairs(e and e.by or {}) do if v.heard >= since then n = n + 1 end end
	return n
end

local function WitnessQuorum(letter, hash, now)
	local r = rvHeard[letter]
	local e = r and r.items[hash]
	local n = 0
	for _, v in pairs(e and e.by or {}) do
		if now - v.signed <= R.WITNESS_FRESH then n = n + 1 end
	end
	return n >= R.WITNESSES
end

PinWitnessed = function(letter, body, rec)
	if not rvHeard[letter] or not WitnessQuorum(letter, RecordHash(letter, body), Now()) then return false end
	for _, part in ipairs(rec.parts) do
		local keys = R.KeysOf(part.name)
		if keys and not keys[part.pk64] then return false end
	end
	for _, part in ipairs(rec.parts) do
		if not R.HasKey(part.name, part.pk64) then R.Pin(part.name, part.pk64, nil, true) end
	end
	stats.witnessed = stats.witnessed + 1
	return true
end

-- A relay may already hold the record, while the two confirmations were heard in
-- different relay pockets. Ask at most two current signed peers for one exact record.
-- A reply uses only first-hand RK and RV and never enters the mesh or guild fan-out.
local CROSS_GAP, CROSS_REPLY_GAP, CROSS_WAIT = 600, 30, 120
local function CrossScope()
	local relay, arena = ns.Relay, A()
	if not relay or type(relay.On) ~= "function" or not relay.On()
		or type(relay.IsSignedRelay) ~= "function" or not relay.IsSignedRelay(Me()) or not ns.IsMember()
		or type(ns.realm) ~= "string" or Barred() or arena.Off() or arena.Sim() or arena.TestBuild() then return nil end
	local region = ns.realm:match("^CAMWOW(%u%u)")
	if region and ns.ForeverFamily(ns.realm) == ns.group and ns.faction then
		return region .. ":" .. ns.group .. ":" .. ns.faction
	end
end

local function CrossPeer(name)
	if not name or not ns.Relay.MeshPeer(name) or not ns.Relay.AtLeast(ns.Relay.RelayVersion(name), "1.5.8") then return nil end
	local realm = ns.RealmOf(ns.FullName(name))
	if ns.ForeverFamily(realm) ~= ns.group or realm:sub(1, 8) ~= ns.realm:sub(1, 8) then return nil end
	local moderation = ns.Moderation
	if moderation and not moderation.missing and moderation.Hides and moderation.Hides(name) then return nil end
	return ns.ShortName(name):lower()
end

local function CrossWhisper(name, kind, body, guard, done)
	local arena = A()
	local function Allowed()
		return not arena.Blocked() and not arena.Refusal(kind, "L") and guard()
	end
	if ns.Comm.QueueRoom() < 4 or not Allowed() then return false end
	return ns.Comm.Whisper(name, kind .. "~L" .. arena.PROTO .. "~" .. body, nil, false, false, done, { owner = R, guard = Allowed })
end

local function CrossDay(d, now)
	return type(d) == "number" and d >= floor(now / 86400) - R.DIGEST_DAYS and d <= floor((now + R.AHEAD) / 86400)
end

function cross.Ask(letter, day)
	local scope, now = CrossScope(), Now()
	if not scope or now - (cross.askedAt or -math.huge) < CROSS_GAP then return false end
	local first, nextRow
	for kind in pairs(letter and { [letter] = true } or R.TYPES) do
		local s = Store(kind)
		for key, p in pairs(s and s.pend or {}) do
			if type(p) == "table" and type(p.id) == "string" and #p.id <= 120 and not p.id:find("[~|%c]")
				and type(p.b) == "string" and CrossDay(p.d, now) and (not day or day == p.d) then
				local cursor = kind .. ":" .. key
				if not first or cursor < first.cursor then first = { kind = kind, row = p, cursor = cursor, store = s.pend, key = key } end
				if cursor > (cross.cursor or "") and (not nextRow or cursor < nextRow.cursor) then
					nextRow = { kind = kind, row = p, cursor = cursor, store = s.pend, key = key }
				end
			end
		end
	end
	local row = nextRow or first
	if not row then return false end
	local peers, king = {}, nil
	for _, name in ipairs(ns.Relay.Names(false, true)) do
		if CrossPeer(name) then
			local bar = R.Bar(name)
			if bar == "last" then king = name elseif not bar then peers[#peers + 1] = name end
		end
	end
	if #peers < 2 and king then peers[#peers + 1] = king end
	if #peers == 0 then return false end
	local p, kind = row.row, row.kind
	local q = { hash = RecordHash(kind, p.b), letter = kind, expires = now + CROSS_WAIT, peers = {}, early = {} }
	cross.pending = q
	local request = table.concat({ kind, "x", B36(p.d), scope, q.hash, p.id }, "~")
	local any = false
	local count, offset = min(2, #peers), (cross.peerOffset or 0) % #peers
	for i = 1, count do
		local name = peers[(offset + i - 1) % #peers + 1]
		local key = CrossPeer(name)
		if key and CrossWhisper(name, "RA", request, function()
			return cross.pending == q and row.store[row.key] == p and Now() < q.expires
				and CrossScope() == scope and CrossPeer(name) == key
		end, function(sent)
			if sent then q.peers[key] = true stats.crossAsked = (stats.crossAsked or 0) + 1 end
		end) then any = true end
	end
	if any then cross.cursor, cross.askedAt, cross.peerOffset = row.cursor, now, offset + count end
	return any
end

local function OnCrossAsk(letter, day, rest, sender)
	local scope, now = CrossScope(), Now()
	local peer = scope and CrossPeer(sender)
	local theirs, hash, id = A().Fields(rest, 3)
	local d = N36(day, 0, 400000)
	if not scope or not peer or theirs ~= scope or not CrossDay(d, now) or not hash or #hash ~= 64
		or not hash:match("^%x+$") or not id or #id > 120 or id:find("[~|%c]") then return false end
	local replies = cross.replies or {}
	if now - (cross.repliedAt or -math.huge) < CROSS_REPLY_GAP or now - (replies[peer] or -math.huge) < CROSS_GAP then return false end
	local s = Store(letter)
	local held = s and s.days[d]
	local record = held and held[id]
	if type(record) ~= "string" or s.clash[id] or RecordHash(letter, record) ~= hash then return false end
	local function Allowed()
		return Now() - now < CROSS_WAIT and CrossScope() == scope and CrossPeer(sender) == peer
			and s.days[d] == held and held[id] == record and not s.clash[id]
	end
	local key = KeyBody()
	if not key then return false end
	local _, pk64 = A().Fields(key, 4)
	if not CrossWhisper(sender, "RK", key, Allowed, function(sent)
		if not sent or not Allowed() then return end
		local witness = WitnessBody(letter, hash, pk64, ns.Debts.Sign)
		if witness then
			CrossWhisper(sender, "RV", witness, Allowed, function(ok)
				if ok then stats.crossAnswered = (stats.crossAnswered or 0) + 1 end
			end)
		end
	end) then return false end
	for name, at in pairs(replies) do if now - at >= CROSS_GAP then replies[name] = nil end end
	replies[peer], cross.replies, cross.repliedAt = now, replies, now
	return true
end

local function OnAsk(dist, sender, mode, body)
	if dist == "WHISPER" and mode == "L" then
		if type(body) ~= "string" or #body > 248 then return Count("shape") end
		local letter, kind, day, rest = A().Fields(body, 4)
		if R.TYPES[letter] and kind == "x" then return OnCrossAsk(letter, day, rest, sender) end
	end
	if mode ~= "L" or dist ~= "CHANNEL" then return Count("lane") end
	if type(body) ~= "string" or #body > 9000 then return Count("shape") end
	local letter, kind, what, rest = A().Fields(body, 4)
	if not (letter and R.TYPES[letter]) or not rest then return Count("type") end
	local now = Now()
	local s = Store(letter)
	local asker = Low(sender) or "?"
	if kind == "d" then
		local d = N36(what, 0, 400000)
		local bucket, prefixes = rest:match("^([0-9a-z]+):(.*)$")
		if bucket then if #bucket > 2 then return Count("shape") end rest = prefixes else bucket = "" end
		if not d or #rest % R.PREFIX ~= 0 or #rest > R.ASK_PREFIX_MAX * R.PREFIX or rest:find("[^0-9a-z]") then return Count("shape") end
		Per(heardAsk, letter)[d] = now
		-- (an ask of ours waiting for its turn: merged when this one asked for all it would)
		MergeAsk(letter, d, bucket, rest)
		-- A barred client (R.Bar: the author's, or one whose quiet presence is on) answers no ask.
		if Barred() then return end
		local list = s and s.days[d]
		if not list or not next(list) then return end
		local has = {}
		for i = 1, #rest, R.PREFIX do has[rest:sub(i, i + R.PREFIX - 1)] = true end
		local missing = {}
		for id, record in pairs(list) do
			local prefix = R.Fingerprint(letter, record)
			if prefix:sub(1, #bucket) == bucket and not has[prefix] then missing[#missing + 1] = { id, record } end
			for _, other in ipairs(s.clash[id] or {}) do
				prefix = R.Fingerprint(letter, other)
				if prefix:sub(1, #bucket) == bucket and not has[prefix] then missing[#missing + 1] = { id, other } end
			end
		end
		if not missing[1] then return end
		local key = "d" .. letter .. d
		if answering[key] or now - (Per(answeredAt, letter)[d] or -math.huge) < R.ANSWER_GAP or not Room(asker) then return end
		Wait(key, letter, "days", d, now, "d", "records answer " .. key, function()
			table.sort(missing, function(a, b) return a[1] < b[1] end)
			local held = s.days[d] or {}
			local jobs = {}
			for _, item in ipairs(missing) do
				if held[item[1]] then
					local record = item[2]
					local mark, hash = A().Hash36(record, 8), RecordHash(letter, record)
					local body = (Per(heardBody, letter)[mark] or -math.huge) < now
					-- A second holder still sends independent validation when another already
					-- supplied the body. That is the quorum that transfers identity safely.
					local witness = R.WitnessesSince(letter, hash, now) < R.WITNESSES
					if body or witness then jobs[#jobs + 1] = { id = item[1], record = record, mark = mark, hash = hash, body = body, witness = witness } end
				end
			end
			if not jobs[1] or not Spend(asker) then return end
			Per(answeredAt, letter)[d] = Now()
			stats.answered = stats.answered + 1
			local keyed = false
			for _, j in ipairs(jobs) do
				if j.body then
					local record, mark = j.record, j.mark
					Out("RR", letter .. j.id .. mark, function()
						-- (another holder's copy of it heard since the ask: ours stays home)
						if (Per(heardBody, letter)[mark] or -math.huge) >= now then return nil end
						return letter .. "~" .. record
					end, d)
				end
				if j.witness then
					-- (The key declared once for the whole answer, not once a record.)
					if not keyed then R.SendKey() keyed = true end
					R.SendWitness(letter, j.record, d, true, j.hash, now)
				end
			end
		end)
	elseif kind == "w" then
		-- (1.2.6) Validations alone, for records of that day the asker holds and still waits on
		-- (R.AskWitness): a holder of exactly that record signs its own, never sends the body.
		local d = N36(what, 0, 400000)
		if not d or #rest % R.PREFIX ~= 0 or #rest > R.ASK_PREFIX_MAX * R.PREFIX or rest:find("[^0-9a-z]") then return Count("shape") end
		local wanted, bodies = {}, {}
		for i = 1, #rest, R.PREFIX do wanted[rest:sub(i, i + R.PREFIX - 1)] = true end
		MergeWitnessAsk(letter, d, wanted)
		if Barred() then return end
		local list = s and s.days[d]
		if not list or not next(list) then return end
		for id, record in pairs(list) do
			if wanted[R.Fingerprint(letter, record)] then bodies[#bodies + 1] = { id, record } end
		end
		if not bodies[1] then return end
		local key = "w" .. letter .. d
		if answering[key] or now - (Per(witnessedAt, letter)[d] or -math.huge) < R.ANSWER_GAP or not Room(asker) then return end
		Wait(key, letter, "days", d, now, "w", "records witness " .. key, function()
			table.sort(bodies, function(a, b) return a[1] < b[1] end)
			local jobs = {}
			for _, item in ipairs(bodies) do
				local hash = RecordHash(letter, item[2])
				if R.WitnessesSince(letter, hash, now) < R.WITNESSES then jobs[#jobs + 1] = { item[2], hash } end
			end
			if not jobs[1] or not Spend(asker) then return end
			Per(witnessedAt, letter)[d] = Now()
			R.SendKey()
			for _, j in ipairs(jobs) do R.SendWitness(letter, j[1], d, true, j[2], now) end
		end)
	elseif kind == "s" then
		local m = tonumber(N36(what, 0, 100000))
		local seal = m and s and s.seals[m]
		-- (The author's client answers no seal ask either: his paste sent it, R.TakeSeal.)
		if Barred() or not Adopted(seal) or (rest ~= "-" and seal.h:sub(1, 8) == rest:lower()) then return end
		local key = "s" .. letter .. m
		if answering[key] or now - (Per(answeredAt, letter)["s" .. m] or -math.huge) < R.ANSWER_GAP or not Room(asker) then return end
		Wait(key, letter, "months", m, now, "s", "records answer " .. key, function()
			-- (the seal heard since the ask, or sent by us: answered)
			if (Per(answeredAt, letter)["s" .. m] or -math.huge) >= now or not Spend(asker) then return end
			SendSeal(letter, m)
		end)
	end
end
ns.Comm.Handle("RA", ns.Arena.Handle("RA", OnAsk))

local function Hidden(sender)
	local M = ns.Moderation
	return M ~= nil and not M.missing and M.Hides ~= nil and M.Hides(sender) == true
end
local function OnRecord(dist, sender, mode, body)
	if mode ~= "L" or (dist ~= "CHANNEL" and dist ~= "WHISPER") then return Count("lane") end
	if Hidden(sender) then return Count("hidden") end
	local letter, rest = A().Fields(body, 2)
	if not (letter and R.TYPES[letter]) or not rest then return Count("type") end
	-- (an answer heard: another holder's copy of that body stays home, OnAsk)
	Per(heardBody, letter)[A().Hash36(rest, 8)] = Now()
	local _, _, day = Take(letter, rest, sender, "relay") -- cancellation follows actual verification in Keep
	if day then R.Accepted(letter, day) end
end
ns.Comm.Handle("RR", ns.Arena.Handle("RR", OnRecord))

local function OnWitness(dist, sender, mode, body)
	if mode ~= "L" or (dist ~= "CHANNEL" and dist ~= "WHISPER") then return Count("lane") end
	if Hidden(sender) then return Count("hidden") end
	local letter, hash, t, pk64, sig64 = A().Fields(body, 5)
	local at = N36(t, 0, 4294967295)
	if not (letter and R.TYPES[letter]) or type(hash) ~= "string" or #hash ~= 64 or not hash:find("^%x+$")
		or not at or at > Now() + R.AHEAD or Now() - at > R.WITNESS_FRESH
		or not KeyShape(pk64) or type(sig64) ~= "string" or #sig64 ~= 86 then return Count("witness-shape") end
	hash, sender = hash:lower(), ns.FullName(sender)
	if not R.HasKey(sender, pk64) then
		-- The native key declaration may still be in the signature verifier. Keep one
		-- matching reply per requested peer until that first-hand key is actually pinned.
		local q = cross.pending
		local peer = q and dist == "WHISPER" and CrossScope() and CrossPeer(sender)
		if q and peer and q.peers[peer] and Now() < q.expires and q.letter == letter and q.hash == hash then
			q.early[peer] = { sender = sender, pk = pk64, body = body }
			return
		end
		return Count("witness-key")
	end
	local pk, sig = Raw(pk64, 32), Raw(sig64, 64)
	if not pk or not sig then return Count("witness-shape") end
	local claim = WitnessText(sender, letter, hash, t, pk64)
	A().Check("rv " .. sig64 .. " " .. claim, { pk = pk, msg = claim, sig = sig }, function(good)
		if good ~= true then if good == false then Count("witness-signature") end return end
		local now = Now()
		local by = Low(sender)
		if ns.splitNames and ns.ForeverFamily(ns.RealmOf(sender)) == ns.group then
			by = ns.ShortName(sender):lower() -- different native realm stamps are still one Forever character
		end
		HeardWitness(letter, hash, by, now, at)
		if not WitnessQuorum(letter, hash, now) then return end
		local s = Store(letter)
		for _, pending in pairs(s and s.pend or {}) do
			if type(pending) == "table" and type(pending.b) == "string" and RecordHash(letter, pending.b) == hash then
				Take(letter, pending.b, pending.by or sender, "pending")
			end
		end
	end)
end
ns.Comm.Handle("RV", ns.Arena.Handle("RV", OnWitness))

function cross.KeyArrived(sender, pk64)
	local q = cross.pending
	local peer = q and CrossScope() and CrossPeer(sender)
	local early = q and peer and q.early[peer]
	if early and Now() < q.expires and early.sender == sender and early.pk == pk64 and R.HasKey(sender, pk64) then
		q.early[peer] = nil
		OnWitness("WHISPER", sender, "L", early.body)
	end
end

---------------------------------------------------------------------------
-- The seal (the author's, signed as the council lists are)
---------------------------------------------------------------------------

local function HashOf(text) return Hex(ns.Sign.SHA256(text)) end
R.HashOf = HashOf

-- A month's totals as the seal hashes them: "Name-Realm,games,won,lost" (decimal) by name, ";" apart.
function R.RowsText(rows)
	local list = {}
	for _, r in ipairs(type(rows) == "table" and rows or {}) do
		local name = type(r) == "table" and type(r.name) == "string" and ns.FullName(r.name) or nil
		local g, w, l = r and tonumber(r.games), r and tonumber(r.won), r and tonumber(r.lost)
		if name and not name:find("[,;~|]") and g and w and l then
			list[#list + 1] = { k = name:lower(), s = ("%s,%d,%d,%d"):format(name, floor(g), floor(w), floor(l)) }
		end
	end
	table.sort(list, function(a, b) return a.k < b.k end)
	local out, seen = {}, {}
	for _, x in ipairs(list) do
		if not seen[x.k] then seen[x.k] = true out[#out + 1] = x.s end
	end
	return table.concat(out, ";"), #out
end
function R.ReadRows(text)
	local out = {}
	for part in (tostring(text or "") .. ";"):gmatch("([^;]*);") do
		local name, g, w, l = part:match("^([^,]+),(%d+),(%d+),(%d+)$")
		if name then out[#out + 1] = { name = name, games = tonumber(g), won = tonumber(w), lost = tonumber(l) } end
	end
	return out
end

local function EncodeRows(letter, rows)
	local spec = R.TYPES[letter]
	if spec and type(spec.RowsText) == "function" then return spec.RowsText(rows) end
	return R.RowsText(rows)
end
local function DecodeRows(letter, text)
	local spec = R.TYPES[letter]
	if spec and type(spec.ReadRows) == "function" then return spec.ReadRows(text) end
	return R.ReadRows(text)
end

-- This client's totals of a closed month (a draft), worked out once SEAL_AFTER after it ended: one
-- month a tick at most. The months its records name.
function R.Drafts(force)
	local now = Now()
	for letter, spec in pairs(R.TYPES) do
		local s = Store(letter)
		if s and spec.Totals then
			local months = {}
			for d in pairs(s.days) do months[R.MonthOf(d * 86400)] = true end
			local list = {}
			for m in pairs(months) do
				if (force or now >= R.MonthStart(m + 1) + R.SEAL_AFTER) and m < R.MonthOf(now) and not s.drafts[m] and not Adopted(s.seals[m]) then
					list[#list + 1] = m
				end
			end
			table.sort(list)
			if list[1] then
				local m = list[1]
				local ok, rows = pcall(spec.Totals, m)
				local text, n = EncodeRows(letter, ok and rows or {})
				s.drafts[m] = { r = text, h = HashOf(text), n = n, at = now }
				if not force then return m end
			end
		end
	end
end
-- The seal requests the author signs: one line per closed month drafted and not sealed here.
function R.SealRequests()
	local out = {}
	for letter in pairs(R.TYPES) do
		local s = Store(letter)
		local months = {}
		for m, d in pairs(s and s.drafts or {}) do if type(d) == "table" and not Adopted(s.seals[m]) then months[#months + 1] = m end end
		table.sort(months)
		for _, m in ipairs(months) do
			local d = s.drafts[m]
			out[#out + 1] = ("RS1~%d~%s~%s~%s~%d~%d~%s"):format(Now(), tostring(ns.group or ns.realm), tostring(ns.faction or "Alliance"), letter, m, d.n, d.h)
		end
	end
	return out
end

local asm = {} -- [letter .. month] = { h8, k, parts, got, at }
local Adopt -- (below)
-- A signed seal (the text scripts/council-sign.py seal prints). how: "paste" (the author's, in
-- game), "relay" (RS). True when taken.
function R.TakeSeal(text, sender, how)
	if type(text) ~= "string" or #text > 900 then return Count("seal-shape") end
	text = text:match("^%s*(.-)%s*$")
	local signed, at, group, faction, letter, m, n, h, sig = text:match("^(RS1~(%d+)~([^~]+)~(%a+)~(%l)~(%d+)~(%d+)~(%x+))~(%x+)$")
	at, m, n = tonumber(at), tonumber(m), tonumber(n)
	if not (signed and at and m and n) or not R.TYPES[letter] or #h ~= 64 or n > R.SEAL_ROWS_MAX then return Count("seal-shape") end
	if group ~= tostring(ns.group or ns.realm) or faction ~= tostring(ns.faction or "Alliance") then return Count("seal-group") end
	if m >= R.MonthOf(Now()) or at > Now() + 86400 then return Count("seal-time") end
	local s = Store(letter, true)
	if not s then return Count("store") end
	local held = s.seals[m]
	if type(held) == "table" and (tonumber(held.at) or 0) >= at then return false, "held" end
	if not (ns.Sign.Plausible(sig) and ns.Sign.Verify(signed, sig)) then return Count("seal-signature") end
	h = h:lower()
	s.seals[m] = { s = text, h = h, n = n, at = at }
	stats.sealed = stats.sealed + 1
	EnsureTicker()
	-- Our own totals, when they hash the same: kept; else the seal's, from whoever holds them.
	local d = s.drafts[m]
	local rows = type(d) == "table" and d.h == h and d.r or nil
	if not rows then
		local spec = R.TYPES[letter]
		local ok, list = pcall(spec.Totals or function() return {} end, m)
		local mine = EncodeRows(letter, ok and list or {})
		if HashOf(mine) == h then rows = mine end
	end
	if rows then Adopt(letter, m, rows) else AskSeal(letter, m) end
	-- (The author's paste is where a seal starts, his own signed word: it goes even from his client,
	-- which relays nothing else, R.Bar. Only the answers to seal asks are relays.)
	if how == "paste" and Adopted(s.seals[m]) then SendSeal(letter, m, true) end
	return true
end
-- A seal's totals held: the type's months take them (the month's list for good), and the month's
-- old records go.
Adopt = function(letter, m, rows)
	local s = Store(letter, true)
	local seal = s and s.seals[m]
	if not seal or #rows > R.SEAL_ROWS_MAX * 100 or HashOf(rows) ~= seal.h then return false end
	local parsed = DecodeRows(letter, rows)
	local canonical, n = EncodeRows(letter, parsed)
	if canonical ~= rows or n ~= seal.n then return false end
	seal.r = rows
	s.drafts[m] = nil
	asm[letter .. m] = nil
	local spec = R.TYPES[letter]
	if spec.Sealed then ns.SafeCall("records sealed", spec.Sealed, m, DecodeRows(letter, rows), seal) end
	R.Compact(letter)
	ns.Fire("RECORDS_CHANGED", letter)
	return true
end
function R.Sealed(letter, m)
	local s = Store(letter)
	local seal = s and s.seals[m]
	if not Adopted(seal) then return nil end
	return DecodeRows(letter, seal.r), seal
end
-- The seal and its totals on the low lane (an answer, the author's paste: own).
SendSeal = function(letter, m, own)
	local s = Store(letter)
	local seal = s and s.seals[m]
	if not Adopted(seal) then return false end
	Per(answeredAt, letter)["s" .. m] = Now()
	Out("RS", "s" .. letter .. m, seal.s, math.huge, own)
	local chunks, cur, size = {}, {}, 0
	for part in (seal.r .. ";"):gmatch("([^;]*);") do
		if part ~= "" then
			if size + #part + 1 > R.CHUNK and cur[1] then
				chunks[#chunks + 1] = table.concat(cur, ";")
				cur, size = {}, 0
			end
			cur[#cur + 1] = part
			size = size + #part + 1
		end
	end
	chunks[#chunks + 1] = table.concat(cur, ";")
	for i, c in ipairs(chunks) do
		Out("RT", "t" .. letter .. m .. "." .. i, table.concat({ letter, B36(m), seal.h:sub(1, 8), B36(i), B36(#chunks), c }, "~"), math.huge, own)
	end
	return true
end
local askedSeal, heardSealAsk = {}, {}
AskSeal = function(letter, m)
	local key, now = letter .. m, Now()
	if now - (askedSeal[key] or -math.huge) < R.ASK_GAP or now - (heardSealAsk[key] or -math.huge) < R.ANSWER_GAP then return false end
	askedSeal[key] = now
	local s = Store(letter)
	local seal = s and s.seals[m]
	return A().Send("RA", "L", ("%s~s~%s~%s"):format(letter, B36(m), Adopted(seal) and seal.h:sub(1, 8) or "-"),
		{ dist = "CHANNEL", key = "records seal ask " .. key, low = true }) == true
end

local function OnSeal(dist, sender, mode, body)
	if mode ~= "L" or (dist ~= "CHANNEL" and dist ~= "WHISPER") then return Count("lane") end
	local m = tonumber(tostring(body):match("^RS1~%d+~[^~]+~%a+~%l~(%d+)~"))
	local letter = tostring(body):match("^RS1~%d+~[^~]+~%a+~(%l)~")
	local accepted = R.TakeSeal(body, sender, "relay")
	local s = letter and R.TYPES[letter] and Store(letter)
	local held = s and s.seals[m]
	if accepted or (held and held.s == body) then
		Per(answeredAt, letter)["s" .. m] = Now()
		heardSealAsk[letter .. m] = Now()
	end
end
ns.Comm.Handle("RS", ns.Arena.Handle("RS", OnSeal))

local function OnTotals(dist, sender, mode, body)
	if mode ~= "L" or (dist ~= "CHANNEL" and dist ~= "WHISPER") then return Count("lane") end
	local letter, m, h8, i, k, rows = A().Fields(body, 6)
	m, i, k = N36(m, 0, 100000), N36(i, 1, 200), N36(k, 1, 200)
	if not (letter and R.TYPES[letter] and m and i and k and h8 and rows) or #h8 ~= 8 or not h8:find("^%x+$") or i > k or #rows > R.CHUNK then return Count("shape") end
	Per(answeredAt, letter)["s" .. m] = Now()
	local s = Store(letter)
	local seal = s and s.seals[m]
	if type(seal) ~= "table" or Adopted(seal) or seal.h:sub(1, 8) ~= h8:lower() then return end
	-- A forged chunk from another holder cannot occupy an honest holder's assembly slots.
	local key, now = letter .. m .. ":" .. (Low(sender) or "?"), Now()
	local a = asm[key]
	if not a or a.h8 ~= h8 or a.k ~= k or now - a.at > R.ASM_TTL then
		local n = 0
		for id, part in pairs(asm) do if now - part.at > R.ASM_TTL then asm[id] = nil else n = n + 1 end end
		if not a and n >= R.ASM_MAX then return Count("totals-full") end
		a = { h8 = h8, k = k, parts = {}, got = 0, at = now }
		asm[key] = a
	end
	if not a.parts[i] then a.parts[i], a.got = rows, a.got + 1 end
	if a.got < k then return end
	asm[key] = nil
	local text = table.concat(a.parts, ";", 1, k)
	if not Adopt(letter, m, text) then Count("seal-rows") end
end
ns.Comm.Handle("RT", ns.Arena.Handle("RT", OnTotals))

-- A sealed month's records older than COMPACT_DAYS go (its totals stay); nothing else ever does.
-- The number gone.
function R.Compact(letter)
	local s = Store(letter)
	if not s then return 0 end
	local x = Index(letter)
	local n = 0
	for d, list in pairs(s.days) do
		if Compacted(s, d) then
			for id, body in pairs(type(list) == "table" and list or {}) do
				Remove(x, d, id)
				if fingerprints[letter] then
					fingerprints[letter][body] = nil
					for _, other in ipairs(s.clash[id] or {}) do fingerprints[letter][other] = nil end
				end
				n = n + 1
			end
			s.days[d] = nil
			x.dig[d] = nil
		end
	end
	for id, p in pairs(s.pend) do
		if type(p) == "table" and tonumber(p.d) and Compacted(s, tonumber(p.d)) then s.pend[id] = nil end
	end
	stats.compacted = stats.compacted + n
	return n
end

---------------------------------------------------------------------------
-- The clock, the login, the slash
---------------------------------------------------------------------------

-- Every DIGEST_EVERY while this client holds anything: its slots in the next rounds (its digests),
-- its key again, a month's draft, the sealed months' old records, the records waiting their turn.
function R.Tick()
	ScheduleRounds()
	-- (A key held back while the quiet presence was on goes at the first tick after it.)
	if not keyDue and (not keySentAt or Now() - keySentAt >= R.KEY_EVERY) and Named(Low(Me())) then R.SendKey() end
	R.Drafts()
	for letter in pairs(R.TYPES) do R.Compact(letter) end
	PumpWait()
end

-- A type's records (FarkleTable "b", ArenaLedger "d"): spec = { Read(body) -> { id, t, content,
-- parts = { { name, pk64, pk, sig64, sig, msg } } } | nil, why; Took(rec, how); Conflict(rec);
-- Totals(month) -> { { name, games, won, lost } }; Sealed(month, rows, seal); Mine() -> bodies of
-- its own records to take in at login; Pins() -> { [player] = pk base64url } heard first-hand;
-- Has() -> whether this client holds anything of it; DAY_MAX: records naming one player a day }.
function R.Register(letter, spec)
	if type(letter) ~= "string" or not letter:find("^%l$") or type(spec) ~= "table" or type(spec.Read) ~= "function" then return false end
	R.TYPES[letter] = spec
	idx[letter] = nil
	return true
end

-- After login: each type's own records and first-hand pins taken in, the records waiting for a
-- key looked at again, the sealed months' old records gone, the clock started, our key declared
-- when records name us.
function R.Load()
	for letter, spec in pairs(R.TYPES) do
		if spec.Pins then
			local ok, list = pcall(spec.Pins)
			for name, pk in pairs(ok and type(list) == "table" and list or {}) do R.Pin(name, pk, nil, true) end
		end
		if spec.Mine then
			local ok, list = pcall(spec.Mine)
			for _, body in ipairs(ok and type(list) == "table" and list or {}) do Take(letter, body, Me(), "self") end
		end
	end
	R.RecheckPending()
	for letter in pairs(R.TYPES) do R.Compact(letter) end
	EnsureTicker()
	if Named(Low(Me())) then KeyLater() end
end
-- The weight rule (the design): a client that holds nothing of the records loads nothing, runs no
-- timer and sends nothing at login. It still takes every RD, RA, RR and RV it hears (their handlers
-- are registered at load), so a late login receives the rankings from any holder's digest (Tick,
-- DIGEST_EVERY, at each holder's slot, R.Slot), even while both original players are offline.
-- The holders' signed, validated relay is that path, never an empty client's own call.
ns.On("LOGIN", function()
	local any = Root(false) ~= nil
	for _, spec in pairs(R.TYPES) do
		if not any and spec.Has then
			local ok, has = pcall(spec.Has)
			any = ok and has == true
		end
	end
	if any then ns.After(R.LOAD_DELAY, "records load", R.Load) end
end)

-- `/oly arena records`: what this client holds, and the author's seal requests, in a window to copy
-- from; `/oly arena records seal`: the box to paste a signed seal in.
function R.StatusText()
	local lines = { L.RECORDS_TITLE }
	local letters = {}
	for letter in pairs(R.TYPES) do letters[#letters + 1] = letter end
	table.sort(letters)
	for _, letter in ipairs(letters) do
		local s = Store(letter)
		local sealed = 0
		for _, seal in pairs(s and s.seals or {}) do if Adopted(seal) then sealed = sealed + 1 end end
		lines[#lines + 1] = L.RECORDS_LINE:format(L["RECORDS_TYPE_" .. letter] or letter, R.Count(letter), R.Pending(letter), #R.Clashes(letter), sealed)
	end
	local keys = 0
	for _ in pairs((Root(false) or {}).keys or {}) do keys = keys + 1 end
	lines[#lines + 1] = L.RECORDS_KEYS:format(keys)
	-- (1.4.0: the network's counters, for the in-game checks: this round, the digests of each type
	-- heard in it, the answers sent, the budget left, the discovery asks sent; the delay from a
	-- digest's slot to the wire.)
	local heardNow = {}
	for _, letter in ipairs(letters) do heardNow[#heardNow + 1] = letter .. " " .. R.RoundHeard(letter) end
	lines[#lines + 1] = L.RECORDS_NET:format(floor(Now() / R.DIGEST_EVERY), table.concat(heardNow, ", "), stats.answered, R.Budget(), R.BUDGET, discoverySent)
	lines[#lines + 1] = L.RECORDS_LAG:format(lag.n, lag.n > 0 and lag.sum / lag.n or 0, lag.max)
	R.Drafts(true)
	local req = R.SealRequests()
	if req[1] then
		lines[#lines + 1] = ""
		lines[#lines + 1] = L.RECORDS_REQUESTS
		for _, r in ipairs(req) do lines[#lines + 1] = r end
	end
	return table.concat(lines, "\n")
end
function R.Paste(text)
	local ok = R.TakeSeal(text, Me(), "paste")
	ns.Print(ok and L.RECORDS_SEAL_TAKEN or L.RECORDS_SEAL_BAD)
	return ok
end
function R.Slash(args)
	if tostring(args or ""):lower():match("^%s*seal") then return ns.ShowDialog("OLYMPUS_RECORDS_SEAL") end
	local text = R.StatusText()
	local UI = ns.UI
	if type(UI) == "table" and type(UI.ShowCopy) == "function" then return UI.ShowCopy(L.RECORDS_TITLE, text, nil, { key = "records" }) end
	for line in text:gmatch("[^\n]+") do ns.Print(line) end
end
ns.Arena.Slash("records", function(args) R.Slash(args) end, L.RECORDS_HELP)

StaticPopupDialogs["OLYMPUS_RECORDS_SEAL"] = {
	text = L.RECORDS_SEAL_PROMPT,
	button1 = OKAY or "OK",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 320,
	maxLetters = 900,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then eb:SetText("") end
	end,
	OnAccept = function(self)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("records seal", R.Paste, eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		local text = self:GetText()
		self:GetParent():Hide()
		ns.SafeCall("records seal", R.Paste, text)
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- Tests only: a clean state (a new world's client starts clean anyway).
function R.Reset()
	for key in pairs(cross) do if type(cross[key]) ~= "function" then cross[key] = nil end end
	idx, checking, checkingBy, inflight, waitq = {}, {}, {}, 0, {}
	outq, outSet = {}, {}
	lastDigest, askedAt, heardAsk, answeredAt, heardRecordAt, answering, askCursor, witnessedAt = {}, {}, {}, {}, {}, {}, {}, {}
	asking = {}
	heard, digestSerial, roundHeard, roundDue = {}, {}, {}, {}
	lag = { n = 0, sum = 0, max = 0 }
	mySent, jobsAt, askerJobs, heardBody, rvHeard, witnessSince = {}, {}, {}, {}, {}, {}
	askWait = {}
	digestHeard, discoveryPending, discoveryRetry, discoverySent, replyRound, replyStarted = {}, nil, nil, 0, {}, {}
	askedSeal, heardSealAsk, asm = {}, {}, {}
	from, attempts, fromDay = {}, {}, -1
	keySentAt, keyDue = nil, false
	fingerprints = {}
	if ticker and ticker.Cancel then ticker.Cancel() end
	ticker = nil
end
