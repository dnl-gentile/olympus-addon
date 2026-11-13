local ADDON, ns = ...

-- 1.5.5, provisional relays (Daniel, 2026-11-10: "se não tiver nenhum relay ou se não tiver nenhum
-- relay ao alcance de certas pessoas, automaticamente ele elicita relays aleatórios ... 2 ou 3 ... para
-- poder validar que os dados estão batendo ... eles têm menos força e menos validade do que os relays
-- principais. Mas se os relays principais não alcançam, eles funcionam como relays").
--
-- On Forever the relays are the signed list's characters (Relay.lua). When none of them is online or
-- answers (every one left out after a sweep), a guild's registrant (Comm.isRegistrant; the reporter
-- where no registrant is named) elects up to K provisional relays among the candidates a signed relay
-- published (RE~1~L, kept a week in the realm group's store), followed by the reporters its census
-- heard within a day. Each candidate answers yes while it has no signed relay, serves
-- fewer than PROVISIONAL_MAX guilds and is no quiet, net-off or modified client. A provisional relay
-- carries numbers, member weight only: it takes the words of the clients that whisper it first-hand
-- (hop "L"), sends its own census snapshots (CG) and carried totals (CX) to its registrants and to its
-- elected peers, and its peers' snapshots to its registrants (RO), so a registrant holds every
-- provisional relay's snapshot through one of them; a guild's row counts once two of them agree
-- (Data's witnesses). Each census report goes to two of them (Relay.Out). A registrant leaves out a
-- provisional relay whose snapshot misreports its own guild, or is the odd one out of three twice in
-- half an hour, and elects the next. A provisional relay sweeps the signed relays every DEAD_FOR and
-- stands down (Z) the moment one answers; whoever hears it sweeps at once. Nothing here is ever more
-- than a member's word: a provisional relay forwards no other origin's word but its peers' snapshots
-- and the author's signed looks (QA, which prove themselves).
--
--   RE~1~P                       registrant -> candidate: will you serve?
--   RE~1~Y~<serving>             candidate -> registrant: yes (how many guilds it serves)
--   RE~1~N[~<signed relay>]      candidate -> registrant: no (and a signed relay it reached, to ping)
--   RE~1~Z[~<signed relay>]      provisional relay -> its registrants and peers: a signed relay answered
--   RE~1~L~<made36>~<n1,n2,...>  a signed relay's candidates (on the channel, as its own word)
--   RO~<f>~<origin>~<word>       provisional relay -> registrant or peer, in Codec's pieces
-- Old clients have no handler for RE or RO and ignore them; a client updated without restarting the
-- game has no RelayFallback.lua (Core.lua's StandIn) and never elects or serves.

local F = {}
ns.RelayFallback = F

F.K = 3                   -- provisional relays a registrant elects, and asks at a time
F.PROVISIONAL_MAX = 40    -- guilds a provisional relay serves
F.CANDIDATES_KEEP = 7 * 86400
F.CANDIDATES_EVERY = 1800 -- the lead signed relay publishes its candidates this often
F.CANDIDATES_MAX = 8
F.CANDIDATES_BYTES = 190  -- a list word's bytes at most: its relay's labels around it keep it one whisper
F.RENDEZVOUS_TOP = 12     -- without a list: the reporters heard within RENDEZVOUS_FOR, the first by hash
F.RENDEZVOUS_FOR = 86400
F.DISSENT_WINDOW = 1800   -- two strikes within this leave a provisional relay out
F.DISSENT_STRIKES = 2
F.IDLE_FOR = 600          -- a provisional relay nobody asked or registered with this long stops serving
F.TICK = 5
F.DRIP_MAX = 160          -- whole transfers waiting in the provisional relay's own sender
F.PICKS_KEPT = 10
local NAME_MAX = 48
local SET_WAIT = 60
local SETS_MAX = 16

local stats = { pinged = 0, yes = 0, no = 0, none = 0, said = 0, refusedAsks = 0, lists = 0, listsRefused = 0,
	registered = 0, refused = 0, unserved = 0, dissents = 0, strikes = 0, standDowns = 0, zHeard = 0,
	roIn = 0, roOut = 0, roDropped = 0, dripDropped = 0, served = 0 }
local answers = {}      -- candidate (short, lower) -> { kind = "wait" | "Y" | "N" | "none", at, name, serving }
local serving           -- while this client is a provisional relay: { since, last, sweep, global }
local registrants = {}  -- guild (lower) -> { name, guild, t }
local drip = {}         -- the provisional relay's whole transfers: { name, word, batches, index, started }
local dripBusy = false
local sets = {}         -- own CG/CX and QA words in pieces: origin#id -> { n, got, pieces, last }
local picks = {}        -- Relay.Pick's last changes: { t, from, to, why }
local lastPick, lastWhy = false, nil
local strikes = {}      -- provisional relay (lower) -> times it was the odd one out
local rowsHeard = {}    -- guild (lower) -> provisional relay (lower) -> { total, observed, at }
local firstSeen = {}    -- (on a signed relay) registrant (lower) -> when its registration was first held
local lastPublish = -math.huge
local cache = { at = -math.huge }

local function Now() return ns.Now() end
local function Lower(s) return type(s) == "string" and s:lower() or "" end
local function Short(name) return type(name) == "string" and (ns.ShortName(name) or "") or "" end
local function Key(name) return Lower(Short(name)) end
local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function Hash(text) -- (Relay.lua's: the same order everywhere)
	local h = 5381
	for i = 1, #text do h = (h * 33 + text:byte(i)) % 2147483647 end
	return h
end
local function Quarantined(name)
	local B = ns.Builds
	return type(B) == "table" and not B.missing and type(B.Quarantined) == "function" and B.Quarantined(name) == true
end
-- The Forever family of a name's realm (ours for a name without one); nil off Forever.
local function Family(name)
	local realm = ns.RealmOf(ns.FullName(name or "") or "") or ns.realm
	return ns.ForeverFamily and ns.ForeverFamily(realm or "") or nil
end
local function Census(key, default)
	local D = ns.Data
	local v = type(D) == "table" and tonumber(D[key]) or nil
	return v or default
end

---------------------------------------------------------------------------
-- Candidates
---------------------------------------------------------------------------

local function Stored(now)
	local c = ns.rdb and ns.rdb.relayCandidates
	if type(c) ~= "table" or type(c.names) ~= "table" or type(c.made) ~= "number" then return nil end
	if now - c.made > F.CANDIDATES_KEEP or c.made > now + 300 then return nil end
	return c
end
-- The reporters our census heard within a day, the first RENDEZVOUS_TOP by a hash of
-- the name and the day (two clients that heard the same reporters ask the same ones).
local function Rendezvous(now)
	local list, seen = {}, {}
	local day = math.floor(now / 86400)
	local guilds = ns.rdb and ns.rdb.guilds
	for _, g in pairs(type(guilds) == "table" and guilds or {}) do
		local who = type(g) == "table" and g.reporterFull
		local short = type(who) == "string" and Short(who) or ""
		local key = short:lower()
		if short ~= "" and not seen[key] and #short <= NAME_MAX and not short:find("[~,|%c]")
			and now - (tonumber(g.t) or 0) <= F.RENDEZVOUS_FOR and not ns.Relay.IsRelay(short) then
			seen[key] = true
			list[#list + 1] = { name = short, score = Hash(key .. "#" .. day) }
		end
	end
	table.sort(list, function(a, b) if a.score ~= b.score then return a.score < b.score end return a.name < b.name end)
	local out = {}
	for i = 1, math.min(#list, F.RENDEZVOUS_TOP) do out[i] = list[i].name end
	return out
end
-- The candidates in order, where they came from ("list" or "rendezvous"), and the list held.
function F.Candidates(now)
	now = now or Now()
	local c = Stored(now)
	if not cache.list or now < cache.at or now - cache.at >= 60 then
		cache.list, cache.at, cache.combined = Rendezvous(now), now, nil
	end
	if not c or #c.names == 0 then return cache.list, "rendezvous", nil end
	if cache.held ~= c or not cache.combined then
		local names, seen = {}, {}
		-- Try the published list first. A recent reporter can take a seat if those candidates
		-- did not fill it, including when the saved list is still valid but everybody on it left.
		for _, source in ipairs({ c.names, cache.list }) do
			for _, name in ipairs(source) do
				local key = Key(name)
				if key ~= "" and not seen[key] then
					names[#names + 1], seen[key] = name, true
				end
			end
		end
		cache.held, cache.combined = c, names
	end
	return cache.combined, "list", c
end

-- A signed relay's list heard (its own word, on the channel: by its reporters' hand-over or across).
local function TakeList(sender, rest, now)
	local R = ns.Relay
	local made36, list = tostring(rest):match("^(%w+)~(.+)$")
	local made = made36 and tonumber(made36, 36)
	if not made or now - made > F.CANDIDATES_KEEP or made > now + 300 or not R.IsSignedRelay(sender)
		or not R.HopTrusted() or Family(sender) ~= Family(ns.me) then
		stats.listsRefused = stats.listsRefused + 1
		return false
	end
	local names, seen = {}, {}
	for name in (list .. ","):gmatch("([^,]*),") do
		if name == "" or #name > NAME_MAX or name:find("[~|%c]") or #names >= F.RENDEZVOUS_TOP then
			stats.listsRefused = stats.listsRefused + 1
			return false
		end
		if not seen[name:lower()] then seen[name:lower()], names[#names + 1] = true, name end
	end
	local held = Stored(now)
	if held and held.made >= made then return true end
	ns.rdb.relayCandidates = { made = made, names = names, from = Short(sender), t = now }
	stats.lists = stats.lists + 1
	ns.Log("relay fallback: %d candidates from %s", #names, Short(sender))
	return true
end

-- (On a signed relay.) When each registration was first held, for "registered at least 2 x
-- REGISTER_EVERY ago".
local function Sample(now)
	local live = {}
	for _, r in ipairs(ns.Relay.Reporters()) do
		local key = Key(r.name)
		live[key] = true
		firstSeen[key] = firstSeen[key] or now
	end
	for key in pairs(firstSeen) do if not live[key] then firstSeen[key] = nil end end
end
-- The lead signed relay (the first by name among itself and its live mesh peers) publishes its
-- candidates every CANDIDATES_EVERY as its own word: up to CANDIDATES_MAX of its tree-capable
-- registrants (a 1.5.5 client restarted since the update: it has this file too), registered at least
-- two REGISTER_EVERY, in the day's hash order, packed to CANDIDATES_BYTES. Nothing when none qualify.
function F.Publish(now, force)
	now = now or Now()
	local R = ns.Relay
	if not R.On() or not R.IsSignedRelay(ns.me) then return false end
	if not force and now - lastPublish < F.CANDIDATES_EVERY then return false end
	local mine = Key(ns.me)
	for _, n in ipairs(R.Names(false)) do
		if Key(n) < mine and R.IsSignedRelay(n) and R.MeshPeer(n) then return false end -- (not the lead)
	end
	local day, pool = math.floor(now / 86400), {}
	for _, r in ipairs(R.Reporters()) do
		local key = Key(r.name)
		local since = firstSeen[key]
		if key ~= mine and since and now - since >= 2 * R.REGISTER_EVERY and R.TreeCapable(r.name) and not Quarantined(r.name) then
			pool[#pool + 1] = { name = Short(r.name), score = Hash(key .. day) }
		end
	end
	if #pool == 0 then return false end
	table.sort(pool, function(a, b) if a.score ~= b.score then return a.score < b.score end return a.name < b.name end)
	local head = "RE~1~L~" .. ns.Codec.Base36(math.floor(now)) .. "~"
	local names = {}
	for _, p in ipairs(pool) do
		if #names >= F.CANDIDATES_MAX then break end
		if #head + #table.concat(names, ",") + (#names > 0 and 1 or 0) + #p.name > F.CANDIDATES_BYTES then break end
		names[#names + 1] = p.name
	end
	lastPublish = now
	return ns.Comm.Send("CHANNEL", head .. table.concat(names, ","), "relay candidates", false, false) ~= false
end

---------------------------------------------------------------------------
-- The election (a registrant's side)
---------------------------------------------------------------------------

-- Who elects: the guild's registrant; the reporter too when it carries the tree (its hello's "N"),
-- or where no registrant is named at all (a build without the tree lane's election).
function F.Elector()
	local C = ns.Comm
	if type(C) ~= "table" then return false end
	if C.isRegistrant == true then return true end
	if C.isReporter ~= true then return false end
	local T = ns.RelayTree
	return C.isRegistrant == nil or (type(T) == "table" and not T.missing)
end

local function WantsElection(now)
	local R = ns.Relay
	if type(R) ~= "table" or not R.On() or R.IsRelay(ns.me) then return false end
	if not serving and not F.Elector() then return false end
	return R.SignedLive(now) == 0
end

-- An answer still good: a wait until its timeout callback, a yes while it (or its ping's answer) is within
-- VERIFIED_FOR, a no or a silence DEAD_FOR (then the candidate is asked again). Our own yes holds
-- while we serve, and no longer: a client that stopped serving is no relay of its own words.
local function Fresh(a, now)
	local R = ns.Relay
	-- Several timeout callbacks can become due together. Let each close its own ask, so the
	-- first callback to re-run the election does not start a second ask in place of a due one.
	if a.kind == "wait" then return true end
	if a.kind == "Y" then
		if Key(a.name) == Key(ns.me) then return serving ~= nil end
		return now - math.max(a.at, R.AnsweredAt(a.name) or -math.huge) < R.VERIFIED_FOR
	end
	return now - a.at < R.DEAD_FOR
end

-- The provisional relays elected now: the first K yes in the candidates' order, none left out.
function F.Elected(now)
	now = now or Now()
	local R, out = ns.Relay, {}
	if type(R) ~= "table" then return out end
	for _, name in ipairs((F.Candidates(now))) do
		local a = answers[Key(name)]
		if a and a.kind == "Y" and Fresh(a, now) and not R.IsLeftOut(name) then
			out[#out + 1] = Short(name)
			if #out >= F.K then break end
		end
	end
	return out
end
function F.IsElected(name, now)
	local key = Key(name)
	if key == "" then return false end
	for _, n in ipairs(F.Elected(now)) do if Key(n) == key then return true end end
	return false
end
local function Peers(now)
	local out, mine = {}, Key(ns.me)
	for _, n in ipairs(F.Elected(now)) do if Key(n) ~= mine then out[#out + 1] = n end end
	return out
end

-- Whether this client may serve now: true; else false and a signed relay it reached (the asker pings it).
local function Prune(now)
	for g, r in pairs(registrants) do
		if now - r.t > ns.Relay.REPORTER_FOR then registrants[g] = nil end
	end
end
local function Serves(name)
	local key = Key(name)
	for _, r in pairs(registrants) do if Key(r.name) == key then return true end end
	return false
end
-- (asker: who asks; a guild we serve already is never refused for being one too many.)
local function Eligible(now, asker)
	local R = ns.Relay
	if R.IsRelay(ns.me) then return false, Short(ns.me) end
	local signed = R.SignedAnswered(now)
	if signed then return false, signed end
	Prune(now)
	if Count(registrants) >= F.PROVISIONAL_MAX and not Serves(asker) then return false end
	if ns.QuietPresence and ns.QuietPresence() then return false end
	local M = ns.Moderation
	if type(M) == "table" and not M.missing and type(M.SelfOff) == "function" and M.SelfOff() then return false end
	if not R.VersionOf(ns.VERSION) then return false end -- (a modified build)
	return true
end

local function Serve(now)
	if serving then serving.last = now return end
	serving = { since = now, last = now, sweep = now, global = -math.huge }
	stats.served = stats.served + 1
	ns.Log("relay: serving as a provisional relay")
	-- (Its own view of the signed relays first: those it never asked are pinged now, so it knows its
	-- peers once they are left out, and stands down at once when one answers.)
	ns.SafeCall("relay fallback sweep", ns.Relay.Sweep)
end
function F.Serving() return serving ~= nil end

local Elect
local function Ask(name, now)
	local key = Key(name)
	local a = { kind = "wait", at = now, name = Short(name) }
	answers[key] = a
	stats.pinged = stats.pinged + 1
	if key == Key(ns.me) then -- (ourselves: answered here)
		if Eligible(now, ns.me) then Serve(now); a.kind = "Y"; stats.yes = stats.yes + 1
		else a.kind = "N"; stats.no = stats.no + 1 end
		return
	end
	ns.Relay.Quiet(a.name)
	ns.Comm.Whisper(a.name, "RE~1~P", "relay elect " .. key, true)
	ns.After(ns.Relay.PING_WAIT, "relay elect", function()
		if answers[key] == a and a.kind == "wait" then
			a.kind, a.at = "none", Now()
			stats.none = stats.none + 1
			ns.SafeCall("relay elect", Elect, Now())
		end
	end)
end
-- Asks the candidates in order, K at a time, until K said yes (the left out and the modified skipped).
Elect = function(now)
	now = now or Now()
	if not WantsElection(now) then return end
	local R = ns.Relay
	local y, waiting = 0, 0
	for _, name in ipairs((F.Candidates(now))) do
		if y >= F.K then break end
		local key = Key(name)
		local a = answers[key]
		if R.IsLeftOut(name) or Quarantined(name) then
			-- (passed over: no answer to its ping, offline, disagreed, or a modified build)
		elseif a and Fresh(a, now) then
			if a.kind == "Y" then y = y + 1 elseif a.kind == "wait" then waiting = waiting + 1 end
		elseif y + waiting < F.K then
			Ask(name, now)
			local kind = answers[key] and answers[key].kind
			if kind == "Y" then y = y + 1 elseif kind == "wait" then waiting = waiting + 1 end
		end
	end
end
-- Relay.Out found nothing to pick: the election runs (or goes on) where this client elects.
function F.Want(now) Elect(now or Now()) end

local function Reply(to, text)
	ns.Relay.Quiet(to)
	ns.Comm.Whisper(Short(to), text, "relay elect answer " .. Key(to), true)
end
local function OnAsk(sender, now)
	local ok, signed = Eligible(now, sender)
	if ok then
		Serve(now)
		stats.said = stats.said + 1
		Reply(sender, "RE~1~Y~" .. Count(registrants))
	else
		stats.refusedAsks = stats.refusedAsks + 1
		Reply(sender, signed and ("RE~1~N~" .. Short(signed)) or "RE~1~N")
	end
	return true
end
local function OnYes(sender, rest, now)
	local a = answers[Key(sender)]
	if not a or a.kind ~= "wait" then return false end -- (only an answer we wait for)
	a.kind, a.at, a.serving = "Y", now, tonumber(rest) or 0
	stats.yes = stats.yes + 1
	ns.SafeCall("relay flush", ns.Relay.Flush) -- (what waited for a relay goes now)
	return true
end
local function Reconsider(name)
	local R = ns.Relay
	if type(name) == "string" and name ~= "" and R.IsSignedRelay(name) then R.Reconsider(name) end
end
local function OnNo(sender, rest, now)
	local a = answers[Key(sender)]
	if not a or a.kind == "N" then return false end
	a.kind, a.at = "N", now
	stats.no = stats.no + 1
	Reconsider(rest)
	Elect(now)
	return true
end
local function OnStandDown(sender, rest, now)
	local a = answers[Key(sender)]
	if not (a and a.kind == "Y") then return false end -- (only from a relay we elected)
	a.kind, a.at = "N", now
	stats.zHeard = stats.zHeard + 1
	Reconsider(rest)
	ns.Relay.Sweep()
	return true
end

---------------------------------------------------------------------------
-- Serving (a provisional relay's side)
---------------------------------------------------------------------------

-- Pieces of an own CG/CX or a QA word put together (head: the pattern its first piece starts with);
-- the whole word once its last piece is here, else nil.
local function Collect(origin, body, now, head, also)
	local id, i, n, part = body:match("^C(%w+):(%d+):(%d+):(.*)$")
	i, n = tonumber(i), tonumber(n)
	if not id or n < 1 or n > ns.Codec.MAX_CHUNKS or i < 1 or i > n then return nil end
	for k, s in pairs(sets) do if now - s.last > SET_WAIT then sets[k] = nil end end
	local key = Lower(origin) .. "#" .. id
	local s = sets[key]
	if not s then
		if i ~= 1 or not (part:match(head) or (also and part:match(also))) or Count(sets) >= SETS_MAX then return nil end
		s = { n = n, got = 0, pieces = {}, last = now }
		sets[key] = s
	end
	if s.n ~= n then sets[key] = nil return nil end
	if not s.pieces[i] then s.pieces[i], s.got, s.last = part, s.got + 1, now end
	if s.got < n then return nil end
	sets[key] = nil
	return table.concat(s.pieces)
end

-- Its own sender: one whole transfer at a time, as the queue has room (Relay's drip serves its
-- registered reporters alone). A newer copy of a word takes a waiting one's place.
-- (1.5.9's review) Every transfer here is census (its own CG and CX, its peers' CG, the author's QA:
-- Spread), and it waited for free room for its whole batch and went as an ordinary job: under a queue kept
-- busy by ordinary whispers none ever started (the offline harness, 10 registrants, three ordinary whispers
-- a pump, one more than it sends: no whisper to a registrant in 300 s), as the signed relay's drip did
-- before 1.5.9 (Relay.lua). Now it starts once Comm can make room for its batch by dropping the ordinary
-- whispers still waiting, and goes urgent, which nothing pushes out. No pace like the signed relay's: a
-- provisional relay carries no chat lane, its own words are a member's few, and while a batch goes three
-- of Comm's eight sends stay for the single ones (BATCH_SLOTS).
local function Wanted(name, now)
	return Serves(name) or F.IsElected(name, now)
end
local Pump
Pump = function()
	if dripBusy or not serving then return end
	while drip[1] do
		local d = drip[1]
		if not d.started and not Wanted(d.name, Now()) then
			table.remove(drip, 1)
		else
			local batch = d.batches[d.index]
			if ns.Comm.QueueRoom(true) < #batch then
				dripBusy = true
				ns.After(1, "relay provisional drip", function() dripBusy = false; Pump() end)
				return
			end
			d.started, dripBusy = true, true
			ns.Relay.Quiet(d.name)
			ns.Comm.SendBatch("WHISPER", batch, nil, Short(d.name), true, function(sent)
				if sent and d.index < #d.batches then
					d.index = d.index + 1
				else
					for i, x in ipairs(drip) do if x == d then table.remove(drip, i) break end end
					if sent then stats.roOut = stats.roOut + 1 end
				end
				dripBusy = false
				Pump()
			end)
			return
		end
	end
end
local function DripTo(name, word, batches)
	for _, d in ipairs(drip) do
		if d.name == name and d.word == word and not d.started then d.batches = batches return end
	end
	if #drip >= F.DRIP_MAX then
		for i, d in ipairs(drip) do
			if not d.started then table.remove(drip, i); stats.dripDropped = stats.dripDropped + 1; break end
		end
	end
	drip[#drip + 1] = { name = name, word = word, batches = batches, index = 1 }
end
-- A word to the registrants (and, toPeers, to the elected peers) as RO, never back to its origin or to
-- `except`; an own word to our own guild as well, as a relay hands its own words to its guild.
local function Spread(flag, origin, word, toPeers, except)
	local R, now = ns.Relay, Now()
	local batches = R.SetBatches(flag, origin, { word }, "RO")
	local tag = Key(origin) .. " " .. (word:match("^(%u%w~%d+~S)~") or word:sub(1, 2))
	local from = Key(origin)
	for _, r in pairs(registrants) do
		local key = Key(r.name)
		if r.name ~= ns.me and key ~= from and key ~= except then DripTo(Short(r.name), tag, batches) end
	end
	if toPeers then
		for _, p in ipairs(Peers(now)) do
			local key = Key(p)
			if key ~= from and key ~= except then DripTo(p, tag, batches) end
		end
	end
	if from == Key(ns.me) then R.HandOn(flag, origin, word) end
	Pump()
end

-- A guild's registration with this provisional relay: one guild per registrant, PROVISIONAL_MAX guilds.
local function Register(sender, rest, now)
	local R = ns.Relay
	local guild = rest:match("^(.-)~[^~]*$") or rest -- (RR~<guild>~<version>, 1.5.4's form, too)
	local who = ns.FullName(sender)
	if guild == "" or #guild > R.MAX_GUILD_NAME or guild:find("[~|%c]") or Quarantined(who) then
		stats.refused = stats.refused + 1
		return true
	end
	Prune(now)
	local key = guild:lower()
	for g, r in pairs(registrants) do
		if r.name == who and g ~= key then registrants[g] = nil end
	end
	if not registrants[key] and Count(registrants) >= F.PROVISIONAL_MAX then
		stats.refused = stats.refused + 1
		return true
	end
	if not registrants[key] or registrants[key].name ~= who then ns.Log("relay: %s registered with this provisional relay by %s", guild, tostring(sender)) end
	registrants[key] = { name = who, guild = guild, t = now }
	stats.registered = stats.registered + 1
	return true
end

-- Our own word (Relay.Pick names us while we serve): a census snapshot, carried totals or an
-- author's signed look to our registrants and peers; any other single word to our own guild alone.
local function Own(flag, origin, body, now)
	local R = ns.Relay
	local word = Collect(origin, body, now, "^C[GX]~", "^QA~")
	if not word and not body:match("^C%w+:%d+:%d+:") then word = body end
	if not word then return true end
	if word:match("^CG~%d+~S~") or word:match("^CX~") or word:match("^QA~") then
		Spread(flag, origin, word, true)
	elseif flag ~= "L" and word == body and not word:match("^RR~") and not R.GuildRoute(word)
		and not (R.NO_FORWARD[word:sub(1, 2)] and not word:match("^GV~1~[ARS]~")) then
		R.HandOn(flag, origin, word)
	end
	return true
end

-- Hop 1 at a client that is no signed relay (Relay.HandleIn hands it here): served while this client
-- is a provisional relay, else unheard (its sender's relay has gone: its ping finds another).
function F.HandleIn(dist, sender, text)
	local R = ns.Relay
	if dist ~= "WHISPER" or type(R) ~= "table" or not R.On() then return false end
	local flag, body = tostring(text):match("^RL~([LP])~(.*)$")
	if not flag then return false end
	if not serving then
		stats.unserved = stats.unserved + 1
		return true
	end
	local now = Now()
	local origin = ns.FullName(sender)
	local own = origin == ns.me
	if not own then serving.last = now end
	if body == "RP~" then
		if not own then
			R.Quiet(sender)
			ns.Comm.Whisper(sender, "RY~", "relay ack:" .. sender, true)
		end
		return true
	end
	local guild = body:match("^RR~(.+)$")
	if guild then return Register(sender, guild, now) end
	if own then return Own(flag, origin, body, now) end
	-- Another client's word: taken here, first-hand; an author's signed look (QA) alone goes on.
	local qa = Collect(origin, body, now, "^QA~") or (body:match("^QA~") and body) or nil
	R.TakeVia("L", sender, origin, body, flag == "L")
	if qa then Spread(flag, origin, qa, true, Key(sender)) end
	return true
end

---------------------------------------------------------------------------
-- Receiving RO (a registrant's or a peer's side), and dissent
---------------------------------------------------------------------------

-- Our guild's own report: { name, total, observed }, or nil.
local function OwnRow()
	local guild = GetGuildInfo and GetGuildInfo("player")
	local g = type(guild) == "string" and ns.rdb and type(ns.rdb.guilds) == "table" and ns.rdb.guilds[guild]
	if type(g) ~= "table" or g.mine ~= true then return nil end
	return { name = guild, total = tonumber(g.total) or 0, observed = math.floor(tonumber(g.st) or tonumber(g.t) or 0) }
end
-- A snapshot's rows: guild (lower) -> { name, total, observed }.
local function Rows(word)
	local ver, rest = word:match("^CG~(%d+)~S~%d+~(.*)$")
	if ver == "2" then rest = rest and rest:match("^[^~]*~[^~]*~(.*)$") end
	local out = {}
	for row in tostring(rest or ""):gmatch("[^;]+") do
		local name, total, observed = row:match("^([^,]+),(%d+),%d+,%d+,(%d+)$")
		if name then out[name:lower()] = { name = name, total = tonumber(total), observed = tonumber(observed) } end
	end
	return out
end
local function Differ(a, b)
	local big = math.max(a.total, b.total)
	return math.abs(a.total - b.total) > math.max(Census("WITNESS_SLACK", 5), Census("WITNESS_SHARE", 0.05) * big)
end
local function Disagrees(name, now, why)
	ns.Relay.LeaveOut(Short(name), "disagrees")
	local a = answers[Key(name)]
	if a then a.kind, a.at = "N", now end
	strikes[Key(name)] = nil
	stats.dissents = stats.dissents + 1
	ns.Log("relay fallback: %s disagrees (%s)", Short(name), why)
	Elect(now)
end
local function Strike(name, now)
	local key = Key(name)
	local list = strikes[key] or {}
	strikes[key] = list
	for i = #list, 1, -1 do if now - list[i] > F.DISSENT_WINDOW then table.remove(list, i) end end
	list[#list + 1] = now
	stats.strikes = stats.strikes + 1
	if #list >= F.DISSENT_STRIKES then Disagrees(name, now, "the odd one out of three") end
end
-- An elected provisional relay's own snapshot: against our own guild's report (a), and against the
-- other two elected relays' rows of each guild (b).
local function Check(origin, word, now)
	if not word:match("^CG~%d+~S~") or not F.IsElected(origin, now) then return end
	local rows = Rows(word)
	local own = OwnRow()
	local row = own and rows[own.name:lower()]
	if row and math.abs(row.observed - own.observed) <= Census("FRESH", 900) and Differ(row, own) then
		Disagrees(origin, now, "our own guild")
		return true
	end
	local okey, window, odd = Key(origin), Census("WITNESS_WINDOW", 1800), {}
	local elected = {}
	for _, n in ipairs(F.Elected(now)) do elected[Key(n)] = true end
	for g, r in pairs(rows) do
		local held = rowsHeard[g] or {}
		rowsHeard[g] = held
		held[okey] = { total = r.total, observed = r.observed, at = now }
		local three = {}
		for rk, x in pairs(held) do
			if now - x.at > window or not elected[rk] then held[rk] = nil
			elseif math.abs(x.observed - r.observed) <= window then three[#three + 1] = { key = rk, row = x } end
		end
		if not next(held) then rowsHeard[g] = nil end
		-- One relay's row against the two others', which agree with each other.
		if #three >= 3 then
			for i, x in ipairs(three) do
				local others = {}
				for j, y in ipairs(three) do if j ~= i then others[#others + 1] = y.row end end
				local agree = false
				for a = 1, #others do
					for b = a + 1, #others do
						if not Differ(others[a], others[b]) then agree = true end
					end
				end
				local alone = agree
				for _, y in ipairs(others) do if not Differ(x.row, y) then alone = false end end
				if alone then odd[x.key] = true end
			end
		end
	end
	for key in pairs(odd) do Strike(key, now) end
	return not F.IsElected(origin, now)
end

-- What a provisional relay carries, and nothing else (a changed client elected by chance could
-- otherwise speak for any origin, the King's crown or a verifier's decision): its own snapshot or
-- carried totals, an elected peer's snapshot, and an author's signed look (QA proves itself).
local function Carried(sender, origin, word, now)
	if word:match("^QA~") then return true end
	local snapshot = word:match("^CG~%d+~S~") ~= nil
	if Key(origin) == Key(sender) then return snapshot or word:match("^CX~") ~= nil end
	return snapshot and F.IsElected(origin, now)
end
-- RO heard: only from a provisional relay this client elected, and only what such a relay carries;
-- taken as from its origin (hop "O": nothing trusted comes this way) and handed to our guild once.
-- A serving relay hands a peer's snapshot and a QA on to its own registrants. A snapshot that made
-- its relay disagree (Check) goes no further than this client, where it is one witness.
function F.HandleRO(dist, sender, text)
	local R = ns.Relay
	if dist ~= "WHISPER" or type(R) ~= "table" or not R.On() then return false end
	local flag, origin, word = tostring(text):match("^RO~([LP])~([^~]+)~(.*)$")
	if not flag then return false end
	local now = Now()
	if not F.IsElected(sender, now) or not Carried(sender, origin, word, now) then
		stats.roDropped = stats.roDropped + 1
		return false
	end
	stats.roIn = stats.roIn + 1
	if not R.TakeVia("O", sender, origin, word, flag == "L") then return true end
	if Check(origin, word, now) then return true end
	R.HandOn("P", origin, word)
	if serving and Key(origin) ~= Key(ns.me) and (word:match("^CG~%d+~S~") or word:match("^QA~")) then
		Spread(flag, origin, word, false, Key(sender))
	end
	return true
end

---------------------------------------------------------------------------
-- Stand-down, the ticker, the RE handler
---------------------------------------------------------------------------

function F.StandDown(signed)
	if not serving then return false end
	local msg = "RE~1~Z" .. ((type(signed) == "string" and signed ~= "") and ("~" .. Short(signed)) or "")
	local told, mine = {}, Key(ns.me)
	local function Tell(name)
		local key = Key(name)
		if key == "" or key == mine or told[key] then return end
		told[key] = true
		ns.Relay.Quiet(Short(name))
		ns.Comm.Whisper(Short(name), msg, "relay stand down " .. key, true)
	end
	for _, r in pairs(registrants) do Tell(r.name) end
	for _, p in ipairs(Peers(Now())) do Tell(p) end
	serving = nil
	wipe(registrants); wipe(drip); wipe(sets)
	dripBusy = false
	answers[mine] = nil
	stats.standDowns = stats.standDowns + 1
	ns.Log("relay: the provisional relay stands down for %s", tostring(signed))
	return true
end
-- A relay answered our ping (Relay's Flush asks this first): a signed one ends our service.
function F.Answered()
	if not serving then return end
	local signed = ns.Relay.SignedAnswered(Now())
	if signed then F.StandDown(signed) end
end

function F.Tick(now)
	now = now or Now()
	local R = ns.Relay
	if type(R) ~= "table" or not R.On() then return end
	if R.IsRelay(ns.me) then
		if R.IsSignedRelay(ns.me) then Sample(now); F.Publish(now) end
		return
	end
	if serving then
		Prune(now)
		if now - serving.last >= F.IDLE_FOR and not next(registrants) then
			serving = nil
			wipe(drip); wipe(sets)
			dripBusy = false
			answers[Key(ns.me)] = nil
			ns.Log("relay: nobody uses this provisional relay: it stops serving")
		else
			if now - serving.sweep >= R.DEAD_FOR then serving.sweep = now; R.Sweep() end
			if now - serving.global >= R.GLOBAL_EVERY then
				serving.global = now
				local D = ns.Data
				if type(D) == "table" and type(D.SendGlobalCensus) == "function" then ns.SafeCall("relay fallback census", D.SendGlobalCensus) end
			end
		end
	end
	-- An elector whose signed relays' marks lapsed pings them again now (Relay.Sweep: once each, its
	-- pings' own guards), so one back online is found at once and a dead one is left out again within
	-- PING_WAIT, the provisional relays carrying on meanwhile.
	if not serving and next(answers) ~= nil and F.Elector() and R.SignedLive(now) > 0 and not R.SignedAnswered(now) then R.Sweep() end
	Elect(now)
	Pump()
end

function F.Handle(dist, sender, text)
	local R = ns.Relay
	if type(R) ~= "table" or not R.On() or type(sender) ~= "string" then return false end
	local kind, rest = tostring(text):match("^RE~1~(%u)~?(.*)$")
	if not kind then return false end
	local now = Now()
	if kind == "L" then return dist == "CHANNEL" and TakeList(sender, rest, now) end
	if dist ~= "WHISPER" then return false end
	if kind == "P" then return OnAsk(sender, now) end
	if kind == "Y" then return OnYes(sender, rest, now) end
	if kind == "N" then return OnNo(sender, rest, now) end
	if kind == "Z" then return OnStandDown(sender, rest, now) end
	return false
end

-- In fallback: no signed relay is live or answered, and this client serves or has elected one.
function F.Active()
	local R = ns.Relay
	if type(R) ~= "table" or not R.On() or R.IsRelay(ns.me) then return false end
	local now = Now()
	if R.SignedLive(now) > 0 then return false end
	return serving ~= nil or #F.Elected(now) > 0
end
-- The two elected relays a guild's census report goes to (its name's hash with each relay's).
function F.ReportTargets(guild, now)
	local list, g = F.Elected(now), Lower(guild)
	table.sort(list, function(a, b)
		local ha, hb = Hash(g .. "#" .. Key(a)), Hash(g .. "#" .. Key(b))
		if ha ~= hb then return ha < hb end
		return a < b
	end)
	return { list[1], list[2] }
end
function F.Registrants()
	local out = {}
	for _, r in pairs(registrants) do out[#out + 1] = { name = r.name, guild = r.guild, t = r.t } end
	table.sort(out, function(a, b) return a.guild < b.guild end)
	return out
end

-- Relay.Pick tells each change of its answer (the last PICKS_KEPT, for /oly bug).
function F.NotePick(name, why, now)
	if name == lastPick and why == lastWhy then return end
	picks[#picks + 1] = { t = now or Now(), from = lastPick or nil, to = name, why = why }
	if #picks > F.PICKS_KEPT then table.remove(picks, 1) end
	lastPick, lastWhy = name, why
end

-- The counters for /oly bug (Relay.BugLines' "fallback:" part): the table, and `line`, one line of it.
function F.Stats()
	local now, R = Now(), ns.Relay
	local list, source, held = F.Candidates(now)
	local hold = type(R) == "table" and type(R.HoldStats) == "function" and R.HoldStats() or {}
	Prune(now)
	local out = {
		candidates = #list, source = source, listAge = held and math.floor(now - held.made) or nil,
		listFrom = held and held.from or nil, pinged = stats.pinged, yes = stats.yes, no = stats.no, none = stats.none,
		elected = F.Elected(now), active = F.Active(), serving = serving ~= nil, registrants = Count(registrants),
		said = stats.said, refusedAsks = stats.refusedAsks, registered = stats.registered, refused = stats.refused,
		unserved = stats.unserved, drip = #drip, dripDropped = stats.dripDropped, dissents = stats.dissents,
		strikes = stats.strikes, standDowns = stats.standDowns, zHeard = stats.zHeard, roIn = stats.roIn,
		roOut = stats.roOut, roDropped = stats.roDropped, lists = stats.lists, listsRefused = stats.listsRefused,
		norelay = hold.norelay or 0, held = hold.held or 0, holdDropped = hold.dropped or 0, refusedOut = hold.refused or 0,
		picks = {},
	}
	local trail = {}
	for i, p in ipairs(picks) do
		out.picks[i] = { t = p.t, from = p.from, to = p.to, why = p.why }
		local at = type(date) == "function" and date("!%H:%M", p.t) or tostring(p.t)
		trail[#trail + 1] = ("%s %s>%s (%s)"):format(at, tostring(p.from or "-"), tostring(p.to or "-"), tostring(p.why))
	end
	out.line = ("fallback: cand %d %s%s; asked %d Y%d N%d -%d; elected %s; serving %s %d; dissent %d strike %d; down %d Z%d; RO in %d out %d drop %d; held %d norelay %d dropped %d; picks %s")
		:format(out.candidates, source, held and (" " .. math.floor(out.listAge / 60) .. "m " .. tostring(held.from)) or "",
		out.pinged, out.yes, out.no, out.none, #out.elected > 0 and table.concat(out.elected, ",") or "-",
		out.serving and "yes" or "no", out.registrants, out.dissents, out.strikes, out.standDowns, out.zHeard,
		out.roIn, out.roOut, out.roDropped, out.held, out.norelay, out.holdDropped, #trail > 0 and table.concat(trail, "; ") or "-")
	return out
end

function F.Reset() -- (tests: Relay.Reset calls it through Relay.ResetHooks)
	wipe(answers); wipe(registrants); wipe(drip); wipe(sets); wipe(picks); wipe(strikes); wipe(rowsHeard); wipe(firstSeen)
	serving, dripBusy, lastPick, lastWhy, lastPublish = nil, false, false, nil, -math.huge
	cache.list, cache.at, cache.held, cache.combined = nil, -math.huge, nil, nil
	for k in pairs(stats) do stats[k] = 0 end
	local R = ns.Relay
	if type(R) == "table" and type(R.ResetHold) == "function" then R.ResetHold() end
end
if type(ns.Relay) == "table" and type(ns.Relay.ResetHooks) == "table" then table.insert(ns.Relay.ResetHooks, F.Reset) end

ns.Comm.Handle("RE", function(...) F.Handle(...) end)
ns.Comm.Handle("RO", function(...) F.HandleRO(...) end)
ns.Comm.RelayPieces({ RO = true })

ns.On("LOGIN", function()
	local R = ns.Relay
	if type(R) ~= "table" or not R.On() then return end
	if ns.Every then ns.Every(F.TICK, "relay fallback", function() ns.SafeCall("relay fallback", F.Tick) end) end
end)
