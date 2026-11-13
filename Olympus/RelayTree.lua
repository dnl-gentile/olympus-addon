local ADDON, ns = ...

-- 1.5.5: the relay's census snapshot to its registrants as a tree. On Forever a relay hands each guild's
-- registrant (Comm.MaybeBroadcast: the first guildmate whose hello says N) the relay's whole census
-- snapshot by whisper, about 28 whispers for 140 guilds. The author's relay held 92 registrants on
-- 2026-11-10: some 2,600 whispers a round at 200 a minute, so no round ever finished and every guild
-- saw the census its own reporter heard. Where that star costs more than TREE_STAR_MAX whispers a round,
-- a relay the 1.5.5 census trusts (Data.CensusTrusted, a signed relay) sends the word whole to a few
-- registrants only, its seeds, and to every registrant a digest naming who forwards it:
--
--   RN~1~<tid>~<n>~<hash24>~<src>~<serve>   relay -> registrant: the word's SHA-256 (its first 12 bytes in
--                                           hex; tid its first 8 digits) in n pieces, src the seed that
--                                           sends it ("": the relay itself), serve the registrants a seed
--                                           forwards it to (plain names, comma separated, <= 255 bytes)
--   RF~1~<tid>~<i>~<n>~<data>               seed or relay -> registrant: bytes (i-1)*230+1 .. i*230
--   RQ~1~<tid>~<mask>                       registrant -> its seed, then the relay: the pieces missing,
--                                           "*" for all, else hex digits each for four pieces (digit d,
--                                           from 0, bit j: piece 4d+j+1), made with arithmetic alone
--   RC~1~<tid or ->                         registrant -> relay: it takes a tree (-), a transfer completed
--
-- A receiver takes the word, as from the relay, only once its digest matches (Relay.TakeVia, hop "T"),
-- and hands it to its guild (RG) as a reporter hands an RM. A seed can delay a word, never change it.
-- What a seed misses it asks the seed once and the relay once. Old clients (1.5.3, 1.5.4, and 1.5.5
-- before a restart, with this file's stand-in) never say RC, and still get the snapshot from the relay
-- as an RM batch (Relay.lua's ToReporters).
--
-- The packed snapshot. What a tree costs is the word's pieces: the relay sends them to each seed at
-- some 200 whispers a minute, and a seed to each registrant of its list at one whisper every 1.2 s,
-- before the next round's digest ends the round (tests/relay-tree-load.lua measures it). A census
-- snapshot packed by Codec.PackCensus is the same snapshot in about three fifths of the pieces,
-- nothing rounded, so a round reaches about as many more registrants. A registrant says its tree reads
-- that form beside its RC:
--
--   RZ~1~<letters>                          registrant -> relay: what its tree reads beside the word as
--                                           written (READS; "c": a packed census snapshot)
--
-- and a round is then two trees, each with its own digest, seeds and lists: the packed word among the
-- registrants that said so, the word as written among the others (1.5.6, which has no handler for RZ
-- at either end: a 1.5.6 relay ignores it and sends the word as written to all). The digest of a packed
-- word is the packed word's, and that is what a seed hands on; a receiver unpacks it once the digest
-- matches, takes the snapshot as the relay wrote it, byte for byte, and hands its guild that (RG), so
-- no guildmate ever sees the packed form. The seeds are shared between the two trees by their work.
local RelayTree = {}
ns.RelayTree = RelayTree

RelayTree.TREE_STAR_MAX = 600      -- whispers a round of the star may cost (registrants x pieces) before the tree takes over
RelayTree.TREE_ROUND_EVERY = 240   -- a relay starts a round at most this often...
RelayTree.RF_DATA = 230            -- bytes of the word in one RF whisper (its header 20 at most)
RelayTree.TREE_HOLD = 900          -- an assembly, a seed's copy and a relay's round are kept this long
RelayTree.DIGEST_WAIT = 120        -- RF pieces heard before their RN wait this long
RelayTree.TREE_PATIENCE = 300      -- no piece this long after the RN: the source is asked
RelayTree.GAP_WAIT = 60            -- no new piece this long: the source is asked
RelayTree.RELAY_REPAIR_AFTER = 120 -- no progress this long after the source was asked: the relay is asked
RelayTree.SEED_RESERVE = 15        -- places a seed keeps free in its send queue for its own words
RelayTree.SEEDS_MIN = 2
RelayTree.SEEDS_MAX = 16
RelayTree.RN_QUEUED = 8            -- digests in the relay's send queue at once
RelayTree.RN_BYTES = 255
RelayTree.UNKNOWN_PER_SENDER = 2   -- transfers a sender may open before their RN arrives
RelayTree.UNKNOWN_MAX = 8          -- and in all
RelayTree.ROUNDS_KEPT = 4          -- rounds a relay keeps for repairs
RelayTree.CAPABLE_MAX = 1000       -- registrants a relay keeps the word RC of
RelayTree.NAME_MAX = 60            -- bytes of a name on the wire
RelayTree.READS = "c"              -- what this client's tree reads beside the word as written (RZ)
RelayTree.READS_MAX = 16           -- letters of an RZ at most
RelayTree.TICK = 5
local LAST = 8 -- assemblies Stats shows

local stats = { rnGot = 0, complete = 0, repaired = 0, expired = 0, forged = 0, superseded = 0, rqSent = 0,
	rqAnswered = 0, rqRefused = 0, seedsServed = 0, seedRepairs = 0, seedWaits = 0, rounds = 0, deferred = 0,
	rnSent = 0, bad = 0, unknownDropped = 0, unpacked = 0, unreadable = 0 }
-- (on a relay)
local capable, capableN = {}, 0 -- registrant (short, lower) -> { name, t, since, done, doneAt }: its RC
local reads, readsN = {}, 0     -- registrant (short, lower) -> { f, t }: its RZ, the letters and when
local rounds = {}               -- tid -> { tid, hash, n, pieces, t, seeds, repaired, rt, k, left }
local lastRound, lastRoundAt = nil, -math.huge
local decision                  -- Offer's answer for the set ToReporters hands out now: { set, active }
local ownPieces                 -- RF pieces of the relay's own newest snapshot
local rnWaiting, rnQueued, rnIn, rnFeeding = {}, 0, {}, false -- digests waiting, and those in the send queue
-- (on a registrant)
local asm = {}                  -- tid -> { tid, n, hash, src, relay, t, pieces, got, last, from, stage, ... }
local orphans, orphanBy, orphanN = {}, {}, 0 -- pieces heard before their RN
local recent = {}               -- the last assemblies finished (Stats)
local announced = { t = -math.huge }
-- (on a seed)
local seedJobs, seedBusy = {}, false

local function Now() return ns.Now() end
local function Short(name) return type(name) == "string" and (ns.ShortName(name) or "") or "" end
local function Key(name) return Short(name):lower() end
local function On()
	local R = ns.Relay
	return type(R) == "table" and type(R.On) == "function" and R.On() == true
end
local function Hash(text)
	local h = 5381
	for i = 1, #text do h = (h * 33 + text:byte(i)) % 2147483647 end
	return h
end
local function Hex(bytes) return (bytes:gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end
-- The digest of a word: the first 12 bytes of its SHA-256, in hex.
local function Digest(word) return Hex(ns.Sign.SHA256(word):sub(1, 12)) end
local function Quiet(name)
	local R = ns.Relay
	if type(R) == "table" and type(R.Quiet) == "function" then R.Quiet(name) end
end

-- The pieces missing, as RQ names them: "*" when none came, else a hex digit for each four pieces.
local BIT = { 1, 2, 4, 8 }
function RelayTree.Mask(missing, n)
	local digits = {}
	for d = 1, math.ceil(n / 4) do digits[d] = 0 end
	for _, i in ipairs(missing) do
		if i >= 1 and i <= n then
			local d = math.floor((i - 1) / 4) + 1
			digits[d] = digits[d] + BIT[(i - 1) % 4 + 1]
		end
	end
	for d, v in ipairs(digits) do digits[d] = ("0123456789abcdef"):sub(v + 1, v + 1) end
	return table.concat(digits)
end
-- The pieces a mask names, in order (none for a mask that is not one).
function RelayTree.Unmask(mask, n)
	local out = {}
	if mask == "*" then
		for i = 1, n do out[i] = i end
		return out
	end
	for d = 1, #mask do
		local v = tonumber(mask:sub(d, d), 16)
		if not v then return {} end
		for j = 0, 3 do
			local i = (d - 1) * 4 + j + 1
			if i <= n and math.floor(v / BIT[j + 1]) % 2 == 1 then out[#out + 1] = i end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Capability: who takes a tree (RC). A registrant says so to its relay after each registration
-- (Comm.MaybeBroadcast), REGISTER_EVERY at most, and when a transfer completes; the relay keeps it
-- PRESENT_FOR (Relay.TreeCapable). A client that never said so is served as before.
---------------------------------------------------------------------------

function RelayTree.Capable(name)
	local c = capable[Key(name)]
	return c ~= nil and Now() - c.t < ns.Relay.PRESENT_FOR
end

-- Our relay is told we take a tree: to the relay picked and sure, at most every REGISTER_EVERY (force: now).
function RelayTree.Announce(force)
	if not On() then return false end
	local Relay = ns.Relay
	local relay, sure = Relay.Pick()
	if type(relay) ~= "string" or not sure or Key(relay) == Key(ns.me) then return false end
	local now = Now()
	if not force and announced.to == Key(relay) and now >= announced.t and now - announced.t < Relay.REGISTER_EVERY then return false end
	announced.to, announced.t = Key(relay), now
	Quiet(relay)
	local said = ns.Comm.Whisper(relay, "RC~1~-", "tree rc", false, false) ~= false
	-- What our tree reads beside the word as written (the top of the file), under a key of its own: a
	-- relay that has no handler for it (1.5.6) ignores it and sends the word as written.
	if RelayTree.READS ~= "" then ns.Comm.Whisper(relay, "RZ~1~" .. RelayTree.READS, "tree rz", false, false) end
	return said
end

-- (We are a relay.) What a registrant's tree reads (RZ), kept as its RC is: PRESENT_FOR past its last
-- word, CAPABLE_MAX registrants at most. It changes the form of what that registrant is sent, never
-- whether it is sent anything.
function RelayTree.Reads(name, letter)
	local e = reads[Key(name)]
	if not e then return false end
	local now = Now()
	return now >= e.t and now - e.t < ns.Relay.PRESENT_FOR and e.f:find(letter, 1, true) ~= nil
end
function RelayTree.HandleRZ(dist, sender, text)
	if dist ~= "WHISPER" or not On() or not ns.Relay.IsRelay(ns.me) then return false end
	local letters = tostring(text):match("^RZ~1~(%l+)$")
	if not letters or #letters > RelayTree.READS_MAX then
		stats.bad = stats.bad + 1
		return false
	end
	local key = Key(sender)
	if key == "" or key == Key(ns.me) then return false end
	local now = Now()
	if not reads[key] then
		if readsN >= RelayTree.CAPABLE_MAX then
			local oldest
			for k, x in pairs(reads) do
				if not oldest or x.t < reads[oldest].t then oldest = k end
			end
			if oldest then reads[oldest], readsN = nil, readsN - 1 end
		end
		readsN = readsN + 1
	end
	reads[key] = { f = letters, t = now }
	return true
end

-- (We are a relay.) A registrant's word that it takes a tree, or completed one.
function RelayTree.HandleRC(dist, sender, text)
	if dist ~= "WHISPER" or not On() or not ns.Relay.IsRelay(ns.me) then return false end
	local what = tostring(text):match("^RC~1~([%-%x]+)$")
	if not what or (what ~= "-" and not what:match("^%x%x%x%x%x%x%x%x$")) then
		stats.bad = stats.bad + 1
		return false
	end
	local key = Key(sender)
	if key == "" or key == Key(ns.me) then return false end
	local now = Now()
	local c = capable[key]
	if not c then
		if capableN >= RelayTree.CAPABLE_MAX then
			local oldest
			for k, x in pairs(capable) do
				if not oldest or x.t < capable[oldest].t then oldest = k end
			end
			if oldest then capable[oldest], capableN = nil, capableN - 1 end
		end
		c = { since = now }
		capable[key], capableN = c, capableN + 1
	elseif now < c.t or now - c.t >= ns.Relay.PRESENT_FOR then
		c.since = now -- (lapsed: its time counts again)
	end
	c.name, c.t = Short(sender), now
	if what ~= "-" then c.done, c.doneAt = what:lower(), now end
	return true
end

---------------------------------------------------------------------------
-- The relay's side: whether a census set goes as a tree (Offer, from Relay.lua's ToReporters), its
-- rounds, seeds and digests, and the repairs it answers.
---------------------------------------------------------------------------

-- The word a whole set carries, when it is a census snapshot (CG~1 or CG~2, "S"); else nil.
local function CensusWord(set)
	if type(set) ~= "table" or type(set[1]) ~= "string" then return nil end
	local parts = {}
	for i, body in ipairs(set) do
		local part = type(body) == "string" and body:match("^C%w+:%d+:%d+:(.*)$")
		if not part then return nil end
		parts[i] = part
	end
	local word = ns.Codec.Plain(table.concat(parts))
	return word:match("^CG~[12]~S~") and word or nil
end
local function Quarantined(name)
	local B = ns.Builds
	return type(B) == "table" and not B.missing and type(B.Quarantined) == "function" and B.Quarantined(name) == true
end
-- Whether the relay hands this registrant words now (the relay's admission, as for an RM).
local function Served(name, now)
	local Relay = ns.Relay
	local ok, yes = pcall(Relay.Admit, "RM", name, "RN~", now)
	if ok and yes == true then return true end
	return type(Relay.Exempt) == "function" and Relay.Exempt(name) == true
end
-- The registrants the tree serves now: fresh, tree-capable, served, not this relay's own client.
local function TreeRegistrants(now)
	local out, mine = {}, Key(ns.me)
	for _, r in ipairs(ns.Relay.Reporters()) do
		local key = Key(r.name)
		if key ~= mine and RelayTree.Capable(r.name) and not Quarantined(r.name) and Served(r.name, now) then
			out[#out + 1] = { name = r.name, key = key }
		end
	end
	return out
end
-- Whether the 1.5.5 receivers take this relay's word as the census's: its census trusted, a signed relay.
local function Trusted()
	local D, Relay = ns.Data, ns.Relay
	return type(D) == "table" and type(D.CensusTrusted) == "function" and D.CensusTrusted(ns.me) == true
		and type(Relay.IsSignedRelay) == "function" and Relay.IsSignedRelay(ns.me) == true
end
local function RNText(tid, n, hash, src, serve)
	return ("RN~1~%s~%d~%s~%s~%s"):format(tid, n, hash, src, serve)
end

-- The digests go out RN_QUEUED at a time, urgent, keyed by registrant (a newer one takes a waiting one's
-- place). One the queue refuses for want of room waits for the next tick, in its place.
local FeedRN
FeedRN = function()
	if rnFeeding then return end
	rnFeeding = true
	local list = rnWaiting
	while rnQueued < RelayTree.RN_QUEUED and list[1] and list == rnWaiting do
		local job, full = table.remove(list, 1), false
		if not rnIn[job.key] then rnQueued = rnQueued + 1 end
		rnIn[job.key] = true
		Quiet(job.name)
		ns.Comm.Whisper(job.name, job.text, "tree rn " .. job.key, true, false, function(sent, why)
			if rnIn[job.key] then rnIn[job.key], rnQueued = nil, math.max(0, rnQueued - 1) end
			if sent then
				stats.rnSent = stats.rnSent + 1
			elseif why == "full" and list == rnWaiting then
				table.insert(list, 1, job)
				full = true
			end
			if not rnFeeding then FeedRN() end
		end)
		if full then break end
	end
	rnFeeding = false
end

-- Whether the last round's seeds still wait for their copy in the relay's drip (no round meanwhile).
local function SeedsWaiting()
	if not lastRound then return false end
	for _, name in pairs(lastRound.seeds) do
		if ns.Relay.Dripping(name, "tree word") then return true end
	end
	return false
end

-- One form of the word as a tree among the registrants that read it: its pieces, k seeds, each seed's
-- list, the registrants no seed can serve (left), and the digest for every one (the seeds' first).
-- done: the transfers of the last round, for the registrants that completed theirs.
local function Plan(word, regs, k, now, done)
	local Relay = ns.Relay
	local n = math.ceil(#word / RelayTree.RF_DATA)
	local hash = Digest(word)
	local tid = hash:sub(1, 8)
	local pieces = {}
	for i = 1, n do
		pieces[i] = ("RF~1~%s~%d~%d~%s"):format(tid, i, n, word:sub((i - 1) * RelayTree.RF_DATA + 1, i * RelayTree.RF_DATA))
	end
	-- The seeds: k of the registrants registered (said RC) 2 x REGISTER_EVERY ago at least, those that
	-- completed the last round first, the rest by their name and this word's id (a round's own spread).
	local eligible, rest = {}, {}
	for _, r in ipairs(regs) do
		local c = capable[r.key]
		r.h = Hash(r.key .. tid)
		r.recent = c ~= nil and c.done ~= nil and done[c.done] == true
		if c and now - c.since >= 2 * Relay.REGISTER_EVERY then eligible[#eligible + 1] = r else rest[#rest + 1] = r end
	end
	table.sort(eligible, function(a, b)
		if a.recent ~= b.recent then return a.recent end
		if a.h ~= b.h then return a.h < b.h end
		return a.key < b.key
	end)
	local seeds = {}
	for i, r in ipairs(eligible) do
		if i <= k then seeds[#seeds + 1] = r else rest[#rest + 1] = r end
	end
	-- The lists: the registrants the last round did not reach (none of them said it completed) before
	-- those it did, so that the ones a seed had no time for come first in its next list.
	table.sort(rest, function(a, b)
		if a.recent ~= b.recent then return b.recent end
		if a.h ~= b.h then return a.h < b.h end
		return a.key < b.key
	end)
	-- Each seed's list, in turn, while its digest stays one whisper; the rest from the relay itself.
	local serve, size, base = {}, {}, #RNText(tid, n, hash, "", "")
	for i = 1, #seeds do serve[i], size[i] = {}, base end
	local srcOf, left, at = {}, {}, 0
	for _, r in ipairs(rest) do
		local short, placed = Short(r.name), false
		for _ = 1, #seeds do
			at = at % #seeds + 1
			local add = #short + (#serve[at] > 0 and 1 or 0)
			if #short <= RelayTree.NAME_MAX and size[at] + add <= RelayTree.RN_BYTES then
				serve[at][#serve[at] + 1], size[at] = short, size[at] + add
				srcOf[r.key], placed = Short(seeds[at].name), true
				break
			end
		end
		if not placed then left[#left + 1] = r end
	end
	local round = { tid = tid, hash = hash, n = n, pieces = pieces, t = now, seeds = {}, repaired = {}, rt = #regs, k = #seeds, left = #left }
	for _, s in ipairs(seeds) do round.seeds[s.key] = s.name end
	local first, others = {}, {}
	for i, s in ipairs(seeds) do first[i] = { name = s.name, key = s.key, text = RNText(tid, n, hash, "", table.concat(serve[i], ",")) } end
	for i, r in ipairs(rest) do others[i] = { name = r.name, key = r.key, text = RNText(tid, n, hash, srcOf[r.key] or "", "") } end
	return round, seeds, left, first, others
end

-- The packed form of a census snapshot of n pieces (Codec.PackCensus), where it is fewer pieces; else nil.
local function Packed(word, n)
	local Pack = ns.Codec.PackCensus
	local packed = type(Pack) == "function" and Pack(word) or nil
	if type(packed) ~= "string" or math.ceil(#packed / RelayTree.RF_DATA) >= n then return nil end
	return packed
end

-- A round: the word to the seeds whole (the front of the relay's drip), to the registrants no seed can
-- serve (after the drip's other transfers), and a digest to every one. At most each TREE_ROUND_EVERY,
-- never while the last round's seeds wait for theirs. Where some registrants read the packed form
-- (RelayTree.Reads), two trees: the packed word among them, the word as written among the others, the
-- round's seeds shared between the two by their work (SEEDS_MIN each at least), the packed tree's first.
local function Round(word, n, regs, now)
	if (now >= lastRoundAt and now - lastRoundAt < RelayTree.TREE_ROUND_EVERY) or SeedsWaiting() then
		stats.deferred = stats.deferred + 1
		return
	end
	local Relay = ns.Relay
	local forms = { { word = word, regs = regs } }
	local packed = Packed(word, n)
	if packed then
		local readers, others = {}, {}
		for _, r in ipairs(regs) do
			if RelayTree.Reads(r.name, "c") then readers[#readers + 1] = r else others[#others + 1] = r end
		end
		if #readers > 0 then
			forms = { { word = packed, regs = readers, packed = true } }
			if #others > 0 then forms[2] = { word = word, regs = others } end
		end
	end
	local k = math.max(RelayTree.SEEDS_MIN, math.min(RelayTree.SEEDS_MAX, math.ceil(2 * math.sqrt(#regs))))
	-- A tree's part of the seeds is its part of the work, registrants x pieces: a seed of the word as
	-- written needs about twice as long for each registrant of its list, so its list is half as long.
	local work = 0
	for _, f in ipairs(forms) do
		f.work = #f.regs * math.ceil(#f.word / RelayTree.RF_DATA)
		work = work + f.work
	end
	local done = lastRound and lastRound.tids or {}
	local all = { t = now, seeds = {}, tids = {}, rt = #regs, k = 0, left = 0 }
	local leftAll, first, others = {}, {}, {}
	for _, f in ipairs(forms) do
		local share = #forms == 1 and k or math.max(RelayTree.SEEDS_MIN, math.floor(k * f.work / work + 0.5))
		local round, seeds, left, firstRN, otherRN = Plan(f.word, f.regs, share, now, done)
		for _, s in ipairs(seeds) do
			Relay.DripTo(s.name, "tree word", { round.pieces }, { front = true })
			all.seeds[s.key] = s.name
		end
		for _, r in ipairs(left) do leftAll[#leftAll + 1] = { name = r.name, pieces = round.pieces } end
		for _, job in ipairs(firstRN) do first[#first + 1] = job end
		for _, job in ipairs(otherRN) do others[#others + 1] = job end
		rounds[round.tid], all.tids[round.tid] = round, true
		all.k, all.left = all.k + round.k, all.left + round.left
		if f.packed then all.packed = { tid = round.tid, n = round.n, registrants = round.rt }
		else all.tid, all.n = round.tid, round.n end
		ns.Log("relay tree: round %s%s, %d registrants, %d seeds, %d from the relay, %d pieces", round.tid,
			f.packed and " (packed)" or "", round.rt, round.k, round.left, round.n)
	end
	if not all.tid then all.tid, all.n = all.packed.tid, all.packed.n end
	for _, x in ipairs(leftAll) do Relay.DripTo(x.name, "tree word", { x.pieces }) end
	for _, job in ipairs(others) do first[#first + 1] = job end
	rnWaiting = first
	lastRound, lastRoundAt = all, now
	-- The rounds kept for repairs: those of the last ROUNDS_KEPT round times, within TREE_HOLD.
	local kept = {}
	for t, x in pairs(rounds) do
		if now - x.t >= RelayTree.TREE_HOLD or now < x.t then rounds[t] = nil else kept[#kept + 1] = x end
	end
	table.sort(kept, function(a, b) return a.t > b.t end)
	local times, lastT = 0, nil
	for _, x in ipairs(kept) do
		if x.t ~= lastT then times, lastT = times + 1, x.t end
		if times > RelayTree.ROUNDS_KEPT then rounds[x.tid] = nil end
	end
	stats.rounds = stats.rounds + 1
	FeedRN()
end

-- Whether a set goes as a tree to this registrant (true: nothing else goes to it). Decided once for each
-- set: a census snapshot, this relay trusted by the 1.5.5 census, and the star (tree-capable registrants x
-- pieces) costing more than TREE_STAR_MAX. Then the relay's own snapshot makes a round, and another
-- origin's needs nothing while those rounds run: the relay's own snapshot carries the trusted rows it
-- took. Else false: as before.
-- (1.5.9, an /oly bug of 2026-11-12: a member saw his own guild and one old report, about 1,100 of the
-- army.) Another origin's set was the tree's whether or not the relay made rounds of its own, and only its
-- own snapshot starts one: a relay whose own snapshot never goes (quiet presence: Data.SendGlobalCensus
-- says nothing) handed its tree-capable registrants no census at all. Another origin's set is the tree's
-- now only while the relay's last round is within TREE_HOLD; else the drip hands each registrant the set
-- its census trusts (Relay.lua's CensusFor), as before the tree.
local function Decide(d, set, own)
	local word = CensusWord(set)
	if not word or not Trusted() then return end
	local n = math.ceil(#word / RelayTree.RF_DATA)
	if n < 1 or n > ns.Codec.MAX_CHUNKS then return end
	if own then ownPieces = n end
	local now = Now()
	local regs = TreeRegistrants(now)
	if #regs * (ownPieces or n) <= RelayTree.TREE_STAR_MAX then return end
	if not own and not (lastRound and now >= lastRoundAt and now - lastRoundAt < RelayTree.TREE_HOLD) then return end
	d.active = true
	if own then Round(word, n, regs, now) end
end
function RelayTree.Offer(r, origin, set, flag, own)
	if type(r) ~= "table" or type(r.name) ~= "string" or type(set) ~= "table" or flag == "L" then return false end
	local d = decision
	if not d or d.set ~= set then
		d = { set = set, active = false }
		decision = d
		local ok, err = pcall(Decide, d, set, own == true)
		if not ok then
			d.active = false
			if ns.CaptureError then ns.CaptureError("relay tree", err) end
		end
	end
	return d.active == true and RelayTree.Capable(r.name)
end

-- (We are a relay.) A repair asked by a tree-capable registrant of ours: once a round, at the drip's front.
local function RelayRepair(round, sender, mask, now)
	local key, reg = Key(sender), nil
	for _, r in ipairs(ns.Relay.Reporters()) do
		if Key(r.name) == key then reg = r break end
	end
	if not reg or not RelayTree.Capable(reg.name) or Quarantined(reg.name) or not Served(reg.name, now)
		or round.repaired[key] or now - round.t >= RelayTree.TREE_HOLD then
		stats.rqRefused = stats.rqRefused + 1
		return false
	end
	local batch = {}
	for _, i in ipairs(RelayTree.Unmask(mask, round.n)) do batch[#batch + 1] = round.pieces[i] end
	if #batch == 0 then return false end
	round.repaired[key] = true
	stats.rqAnswered = stats.rqAnswered + 1
	return ns.Relay.DripTo(reg.name, "tree rq " .. round.tid, { batch }, { front = true })
end

---------------------------------------------------------------------------
-- A seed's side: its copy to the registrants of its list, one at a time, by a sender of its own (the
-- relay's drip serves its registrants alone), only while SEED_RESERVE places stay free in its queue.
---------------------------------------------------------------------------

local function SeedPump()
	if seedBusy then return end
	while seedJobs[1] and not (asm[seedJobs[1].tid] and asm[seedJobs[1].tid].rf) do table.remove(seedJobs, 1) end
	local job = seedJobs[1]
	if not job then return end
	if ns.Comm.QueueRoom() < #job.batch + RelayTree.SEED_RESERVE then
		seedBusy = true
		stats.seedWaits = stats.seedWaits + 1
		ns.After(1, "relay tree seed", function() seedBusy = false; SeedPump() end)
		return
	end
	table.remove(seedJobs, 1)
	seedBusy = true
	Quiet(job.name)
	ns.Comm.SendBatch("WHISPER", job.batch, nil, job.name, false, function(sent, why)
		seedBusy = false
		if sent then
			if job.repair then stats.seedRepairs = stats.seedRepairs + 1 else stats.seedsServed = stats.seedsServed + 1 end
		elseif (why == "full" or why == "dropped") and not job.retried then
			job.retried = true -- (pushed out of the queue before it began: once more)
			table.insert(seedJobs, 1, job)
		end
		SeedPump()
	end)
end

-- A registrant of our list asks its missing pieces: once each, while we hold the copy.
local function SeedRepair(a, sender, mask, now)
	local key = Key(sender)
	if not a.serve[key] or a.repairs[key] or now - a.t >= RelayTree.TREE_HOLD then
		stats.rqRefused = stats.rqRefused + 1
		return false
	end
	local batch = {}
	for _, i in ipairs(RelayTree.Unmask(mask, a.n)) do batch[#batch + 1] = a.rf[i] end
	if #batch == 0 then return false end
	a.repairs[key] = true
	stats.rqAnswered = stats.rqAnswered + 1
	table.insert(seedJobs, 1, { name = a.serve[key], tid = a.tid, batch = batch, repair = true })
	SeedPump()
	return true
end

---------------------------------------------------------------------------
-- A registrant's side: the assembly of a transfer, its check, and its repairs.
---------------------------------------------------------------------------

local function Missing(a, most)
	local out = {}
	if type(a.pieces) ~= "table" then return out end
	for i = 1, a.n do
		if not a.pieces[i] then
			out[#out + 1] = i
			if most and #out >= most then break end
		end
	end
	return out
end
local function Summary(a)
	local from = {}
	for who, k in pairs(a.from or {}) do from[#from + 1] = ("%s x%d"):format(who, k) end
	table.sort(from)
	return { tid = a.tid, got = a.got, n = a.n, missing = table.concat(Missing(a, 8), ","), from = table.concat(from, ", "),
		outcome = a.outcome or "open", t = a.t, relay = Short(a.relay), src = a.src }
end
local function Remember(a)
	recent[#recent + 1] = Summary(a)
	if #recent > LAST then table.remove(recent, 1) end
end
local function Finish(a, outcome, now)
	a.done, a.outcome = now, outcome
	Remember(a)
	a.pieces, a.rf = nil, nil
end

local function Ask(a, mask, to, now)
	a.asked, a.askedAt = true, now
	Quiet(to)
	ns.Comm.Whisper(Short(to), ("RQ~1~%s~%s"):format(a.tid, mask), "tree rq " .. a.tid, true, false)
	stats.rqSent = stats.rqSent + 1
	ns.Log("relay tree: %s %d/%d, pieces %s asked of %s", a.tid, a.got, a.n, mask, Short(to))
end
local function MaskOf(a)
	if a.got == 0 then return "*" end
	return RelayTree.Mask(Missing(a), a.n)
end

local function Piece(a, i, data, from, now)
	if a.pieces[i] then return end
	a.pieces[i], a.got, a.last = data, a.got + 1, now
	local who = Short(from)
	a.from[who] = (a.from[who] or 0) + 1
end

-- Every piece here: the word checked against its digest. A match is taken as the relay's word and handed
-- to our guild, and the relay told; a seed starts on its list. Else nothing takes it, the copy is counted
-- forged and asked whole of the relay, whose pieces alone count for it from then on.
local function Complete(a, now)
	local word = table.concat(a.pieces, "", 1, a.n)
	if Digest(word) ~= a.hash then
		stats.forged = stats.forged + 1
		local from = {}
		for who in pairs(a.from) do from[#from + 1] = who end
		table.sort(from)
		ns.Log("relay tree: %s from %s does not match its digest", a.tid, table.concat(from, ", "))
		a.pieces, a.got, a.from, a.relayOnly = {}, 0, {}, true
		if not a.askedAll then
			a.askedAll, a.stage = true, 2
			Ask(a, "*", a.relay, now)
		end
		return
	end
	local Relay = ns.Relay
	-- A packed census snapshot (the top of the file): the digest proved the packed word, and that is what
	-- a seed hands on; what is taken here and handed to our guild is the snapshot as the relay wrote it.
	-- One that does not unpack is nobody's word (a relay packs only what comes back byte for byte).
	local taken = word
	if word:sub(1, 3) == "CP~" then
		local Unpack = ns.Codec.UnpackCensus
		taken = type(Unpack) == "function" and Unpack(word) or nil
		if not taken then
			stats.unreadable = stats.unreadable + 1
			ns.Log("relay tree: %s is a packed word that does not unpack", a.tid)
			Finish(a, "unreadable", now)
			return
		end
		stats.unpacked = stats.unpacked + 1
	end
	a.done, a.outcome = now, a.asked and "repaired" or "complete"
	stats.complete = stats.complete + 1
	if a.asked then stats.repaired = stats.repaired + 1 end
	Remember(a)
	if Relay.TakeVia("T", a.relay, a.relay, taken) then Relay.HandOn("P", a.relay, taken) end
	Quiet(a.relay)
	ns.Comm.Whisper(Short(a.relay), "RC~1~" .. a.tid, "tree rc", false, false)
	if next(a.serve) then
		a.rf = {}
		for i = 1, a.n do a.rf[i] = ("RF~1~%s~%d~%d~%s"):format(a.tid, i, a.n, a.pieces[i]) end
		-- In the order the relay wrote the list, which it draws anew for each round (Plan: by each name and
		-- the word's id). Sorted by name here, the same registrants were last in every round, and a round
		-- ends at the next one's digest: on a relay too busy for its seeds to finish a round, the last of
		-- each list got no snapshot in any round (tests/relay-tree-load.lua).
		for _, key in ipairs(a.order) do seedJobs[#seedJobs + 1] = { name = a.serve[key], tid = a.tid, batch = a.rf } end
	end
	a.pieces = nil
	SeedPump()
end

local function DropOrphan(tid)
	local o = orphans[tid]
	if not o then return end
	orphans[tid], orphanN = nil, orphanN - 1
	for key in pairs(o.by) do
		orphanBy[key] = (orphanBy[key] or 1) - 1
		if orphanBy[key] <= 0 then orphanBy[key] = nil end
	end
end
-- A piece before its RN: kept DIGEST_WAIT, for UNKNOWN_PER_SENDER transfers of a sender, UNKNOWN_MAX in all.
local function Orphan(tid, i, n, data, sender, now)
	local key = Key(sender)
	local o = orphans[tid]
	if not o then
		if (orphanBy[key] or 0) >= RelayTree.UNKNOWN_PER_SENDER or orphanN >= RelayTree.UNKNOWN_MAX then
			stats.unknownDropped = stats.unknownDropped + 1
			return
		end
		o = { t = now, n = n, pieces = {}, from = {}, by = {} }
		orphans[tid], orphanN = o, orphanN + 1
	end
	if o.n ~= n then return end
	if not o.by[key] then
		if (orphanBy[key] or 0) >= RelayTree.UNKNOWN_PER_SENDER then
			stats.unknownDropped = stats.unknownDropped + 1
			return
		end
		o.by[key], orphanBy[key] = true, (orphanBy[key] or 0) + 1
	end
	if not o.pieces[i] then o.pieces[i], o.from[i] = data, sender end
end

-- A relay's digest (from a relay alone, as the server stamps it): one assembly per transfer.
function RelayTree.HandleRN(dist, sender, text)
	if dist ~= "WHISPER" or not On() then return false end
	if not ns.Relay.IsRelay(sender) then
		stats.bad = stats.bad + 1
		return false
	end
	local tid, n, hash, src, serve = tostring(text):match("^RN~1~(%x%x%x%x%x%x%x%x)~(%d+)~(%x+)~([^~]*)~([^~]*)$")
	n = tonumber(n)
	if not tid or not n or n < 1 or n > ns.Codec.MAX_CHUNKS or #hash ~= 24 or hash:sub(1, 8):lower() ~= tid:lower()
		or #src > RelayTree.NAME_MAX then
		stats.bad = stats.bad + 1
		return false
	end
	tid, hash = tid:lower(), hash:lower()
	local now = Now()
	stats.rnGot = stats.rnGot + 1
	if asm[tid] then return true end -- (the same transfer again)
	-- A newer word of this relay: its older transfers still open end here, and a seed stops serving them.
	local from = Key(sender)
	for _, x in pairs(asm) do
		if Key(x.relay) == from then
			if not x.done then
				Finish(x, "superseded", now)
				stats.superseded = stats.superseded + 1
			else
				x.rf = nil
			end
		end
	end
	local a = { tid = tid, n = n, hash = hash, src = src, relay = sender, t = now, pieces = {}, got = 0, from = {},
		stage = 0, serve = {}, order = {}, repairs = {} }
	for name in serve:gmatch("[^,]+") do
		local key = Key(name)
		if #name <= RelayTree.NAME_MAX and key ~= "" then
			if not a.serve[key] then a.order[#a.order + 1] = key end
			a.serve[key] = name
		end
	end
	asm[tid] = a
	local o = orphans[tid]
	if o then
		DropOrphan(tid)
		if o.n == n then
			for i, data in pairs(o.pieces) do Piece(a, i, data, o.from[i], now) end
		end
	end
	if a.got == a.n then Complete(a, now) end
	return true
end

-- A piece of a transfer, from anyone: its RN's digest decides.
function RelayTree.HandleRF(dist, sender, text)
	if dist ~= "WHISPER" or not On() then return false end
	local tid, i, n, data = tostring(text):match("^RF~1~(%x%x%x%x%x%x%x%x)~(%d+)~(%d+)~(.*)$")
	i, n = tonumber(i), tonumber(n)
	if not tid or not i or not n or n < 1 or n > ns.Codec.MAX_CHUNKS or i < 1 or i > n or #data < 1
		or #data > RelayTree.RF_DATA or (i < n and #data ~= RelayTree.RF_DATA) then
		stats.bad = stats.bad + 1
		return false
	end
	tid = tid:lower()
	local now = Now()
	local a = asm[tid]
	if not a then
		Orphan(tid, i, n, data, sender, now)
		return true
	end
	if a.done or a.n ~= n or (a.relayOnly and Key(sender) ~= Key(a.relay)) then return true end
	Piece(a, i, data, sender, now)
	if a.got == a.n then Complete(a, now) end
	return true
end

-- A repair asked of us: as the relay of the round, or as the seed of the asker.
function RelayTree.HandleRQ(dist, sender, text)
	if dist ~= "WHISPER" or not On() then return false end
	local tid, mask = tostring(text):match("^RQ~1~(%x%x%x%x%x%x%x%x)~([%x%*]+)$")
	if not tid or (mask ~= "*" and (mask:find("*", 1, true) or #mask > math.ceil(ns.Codec.MAX_CHUNKS / 4))) then
		stats.bad = stats.bad + 1
		return false
	end
	tid = tid:lower()
	local now = Now()
	if ns.Relay.IsRelay(ns.me) then
		local round = rounds[tid]
		if round then RelayRepair(round, sender, mask, now) end
		return true
	end
	local a = asm[tid]
	if a and a.rf then SeedRepair(a, sender, mask, now) end
	return true
end

-- Every TICK: repairs due (the source after TREE_PATIENCE with no piece, or GAP_WAIT without a new one;
-- the relay RELAY_REPAIR_AFTER later without progress), transfers past TREE_HOLD, pieces whose RN never
-- came, a relay's old rounds; and the digests and a seed's copies waiting.
function RelayTree.Tick()
	if not On() then return end
	local now = Now()
	for tid, a in pairs(asm) do
		if a.done then
			if now - a.t >= RelayTree.TREE_HOLD or now < a.t then asm[tid] = nil end
		elseif now - a.t >= RelayTree.TREE_HOLD or now < a.t then
			Finish(a, "expired", now)
			stats.expired = stats.expired + 1
		else
			local idle = (a.got == 0 and now - a.t >= RelayTree.TREE_PATIENCE)
				or (a.got > 0 and now - (a.last or a.t) >= RelayTree.GAP_WAIT)
			if a.stage == 0 and idle then
				local toSrc = a.src ~= "" and not a.relayOnly
				Ask(a, MaskOf(a), toSrc and a.src or a.relay, now)
				a.stage = toSrc and 1 or 2
			elseif a.stage == 1 and now - math.max(a.askedAt or a.t, a.last or a.t) >= RelayTree.RELAY_REPAIR_AFTER then
				Ask(a, MaskOf(a), a.relay, now)
				a.stage = 2
			end
		end
	end
	for tid, o in pairs(orphans) do
		if now - o.t >= RelayTree.DIGEST_WAIT or now < o.t then DropOrphan(tid) end
	end
	for tid, r in pairs(rounds) do
		if now - r.t >= RelayTree.TREE_HOLD or now < r.t then rounds[tid] = nil end
	end
	FeedRN()
	SeedPump()
end

---------------------------------------------------------------------------
-- /oly bug: RelayTree.Stats() (lane mesh's Relay.BugLines shows its lines).
---------------------------------------------------------------------------

function RelayTree.Stats()
	local now, out = Now(), {}
	for k, v in pairs(stats) do out[k] = v end
	local open, cap = 0, 0
	local last = {}
	for _, a in pairs(asm) do
		if not a.done then
			open = open + 1
			last[#last + 1] = Summary(a)
		end
	end
	for _, s in ipairs(recent) do last[#last + 1] = s end
	table.sort(last, function(a, b) return a.t > b.t end)
	while #last > LAST do table.remove(last) end
	local shown = {}
	for i, s in ipairs(last) do
		shown[i] = { tid = s.tid, got = s.got, n = s.n, missing = s.missing, from = s.from, outcome = s.outcome,
			relay = s.relay, src = s.src, t = s.t, age = math.floor(now - s.t) }
	end
	for _, c in pairs(capable) do
		if now - c.t < ns.Relay.PRESENT_FOR then cap = cap + 1 end
	end
	local readers = 0
	for _, e in pairs(reads) do
		if now >= e.t and now - e.t < ns.Relay.PRESENT_FOR then readers = readers + 1 end
	end
	out.readers = readers
	out.open, out.capable, out.orphans, out.rnWaiting, out.rnQueued, out.seedJobs = open, cap, orphanN, #rnWaiting, rnQueued, #seedJobs
	out.registrant = type(ns.Comm) == "table" and ns.Comm.isRegistrant == true
	out.last = shown
	if lastRound then
		out.round = { tid = lastRound.tid, n = lastRound.n, registrants = lastRound.rt, seeds = lastRound.k,
			fromRelay = lastRound.left, age = math.floor(now - lastRound.t), packed = lastRound.packed }
	end
	local lines = { ("tree: rn %d, complete %d, repaired %d, expired %d, forged %d, superseded %d; rq sent %d, answered %d, refused %d; served %d (+%d repairs, %d waits); rounds %d (deferred %d), capable %d, open %d, registrant %s")
		:format(out.rnGot, out.complete, out.repaired, out.expired, out.forged, out.superseded, out.rqSent, out.rqAnswered,
			out.rqRefused, out.seedsServed, out.seedRepairs, out.seedWaits, out.rounds, out.deferred, cap, open, tostring(out.registrant)) }
	if out.round then
		lines[#lines + 1] = ("tree round %s: %d pieces, %d registrants, %d seeds, %d from the relay, %ds ago")
			:format(out.round.tid, out.round.n, out.round.registrants, out.round.seeds, out.round.fromRelay, out.round.age)
		local p = out.round.packed
		if p then
			lines[#lines + 1] = ("tree round packed %s: %d pieces to %d of the registrants (%d read it)")
				:format(p.tid, p.n, p.registrants, readers)
		end
	end
	if out.unpacked > 0 or out.unreadable > 0 then
		lines[#lines + 1] = ("tree packed: unpacked %d, unreadable %d"):format(out.unpacked, out.unreadable)
	end
	for _, s in ipairs(shown) do
		lines[#lines + 1] = ("tree %s %d/%d missing [%s] from %s: %s, %ds"):format(s.tid, s.got, s.n, s.missing,
			s.from ~= "" and s.from or "-", s.outcome, s.age)
	end
	out.lines = lines
	return out
end

-- Tests: a clean slate (Relay.Reset runs it, Relay.ResetHooks).
function RelayTree.Reset()
	wipe(capable); wipe(rounds); wipe(rnIn); wipe(asm); wipe(orphans); wipe(orphanBy); wipe(recent); wipe(seedJobs)
	wipe(reads)
	capableN, orphanN, rnQueued, readsN = 0, 0, 0, 0
	lastRound, lastRoundAt, decision, ownPieces = nil, -math.huge, nil, nil
	rnWaiting, rnFeeding, seedBusy = {}, false, false
	announced.to, announced.t = nil, -math.huge
	for k in pairs(stats) do stats[k] = 0 end
end
if type(ns.Relay) == "table" and type(ns.Relay.ResetHooks) == "table" then
	table.insert(ns.Relay.ResetHooks, RelayTree.Reset)
end

ns.Comm.Handle("RN", function(...) RelayTree.HandleRN(...) end)
ns.Comm.Handle("RF", function(...) RelayTree.HandleRF(...) end)
ns.Comm.Handle("RQ", function(...) RelayTree.HandleRQ(...) end)
ns.Comm.Handle("RC", function(...) RelayTree.HandleRC(...) end)
ns.Comm.Handle("RZ", function(...) RelayTree.HandleRZ(...) end)

ns.On("LOGIN", function()
	if ns.Every then ns.Every(RelayTree.TICK, "relay tree", function() ns.SafeCall("relay tree", RelayTree.Tick) end) end
end)
