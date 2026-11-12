-- 1.5.5, the author as the census's trusted distributor (the author, 11-10: "garantir que os números
-- do PVP que estão saindo de mim vão chegar em todo mundo ... eu sou a pessoa mais confiável ...
-- deveria estar distribuindo para todo mundo"). On Forever a whisper reaches its own family alone, so
-- the PvP numbers reach PvE only in what a player's client carries when he logs in there: the author's
-- own look among them. 1.5.4 trusted the Church's ledger relays alone (Data.lua's GlobalTrusted), so the
-- author's rows stayed witness rows and his carried look stayed "reported". Every name here is made up.
-- Loaded by tests/run.lua after tests/relay-lists.lua.
local ns, test, eq, extra = ...
local ROOT = assert(extra and extra.ROOT, "tests/run.lua hands ROOT to this file")

local PVE, PVP = "CAMWOWUS2Realm1PvE", "CAMWOWUS1Realm8PvP"
-- The launch pins by family (Relay.LAUNCH_PINS): the author's PvE character first, then another
-- launch character that is no author; on PvP both are the author's (Relay.LAUNCH_AUTHOR).
local AUTHOR_PVE, AUTHOR_PVP = "Quill Penwright", "Quill Duelist"
local PINS = { ForeverPvE = { AUTHOR_PVE, "Crown Bearer" }, ForeverPvP = { AUTHOR_PVP, "Quill Lancer" } }
local AUTHOR = AUTHOR_PVE .. "-" .. PVE
local COUNCIL = { ["Sage Ledger"] = true, ["Sage Warden"] = true } -- signed councillors: relays and ledger relays
local PIN = "Coin Keeper" -- an unsigned Treasurer code pin: a relay, never a signed one
local LISTENER = "Late Listener-" .. PVE

local function PvP(g)
	for _, r in ipairs(g.rows) do if r.group == "ForeverPvP" and r.faction == "Alliance" then return r end end
end
local function Row(g, group)
	for _, r in ipairs(g.rows) do if r.group == group and r.faction == "Alliance" then return r end end
end

-- Clients of one Forever family, each a RelayWorld node (its own Comm and Relay) with its own Data.lua,
-- whose INIT runs as at login (the census's handlers, QA among them). Ed25519's jobs wait for Frames().
local function World(fn)
	local Ed = ns.Ed25519
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild,
		chat = C_ChatInfo, after = Ed.after }
	local frames = {}
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		Ed.Reset()
		Ed.after = function(f) frames[#frames + 1] = f end
		-- opts.pk: this client's ns.AUTHOR_ATTEST_PK (none: empty); opts.file: another release's Data.lua.
		-- Returns the client and its deliver(dist, sender, text): the real handlers (RM, RG...) hear it.
		local function Node(me, opts)
			opts = opts or {}
			local N, deliver = extra.RelayWorld(me, "Olympus II")
			local realm = ns.RealmOf(me)
			N.realm, N.group, N.faction = realm, ns.ForeverFamily(realm), "Alliance"
			N.db, N.rdb.guilds, N.rdb.seen = { blocked = {} }, {}, {}
			local council = {}
			for name in pairs(COUNCIL) do council[name:lower()] = name end
			N.rdb.council = { names = council }
			N.Relay.LAUNCH_PINS = PINS
			N.Relay.LAUNCH_AUTHOR = { ForeverPvE = { PINS.ForeverPvE[1] }, ForeverPvP = PINS.ForeverPvP }
			N.TreasurerPins = function() return { PIN .. "-" .. PVE }, false end
			N.Church = { IsLedgerRelay = function(name) return COUNCIL[ns.ShortName(name or "")] == true end }
			N.QuietPresence = function() return false end
			N.AUTHOR_ATTEST_PK = opts.pk or ""
			local init, on = {}, N.On
			N.On = function(name, f) if name == "INIT" then init[#init + 1] = f else on(name, f) end end
			assert(loadfile(opts.file or (extra.addon .. "Data.lua")))("Olympus", N)
			N.On = on
			for _, f in ipairs(init) do f() end
			return N, deliver
		end
		local function Frames()
			local n = 0
			while #frames > 0 do
				table.remove(frames, 1)()
				n = n + 1
				assert(n < 100000, "the jobs never end")
			end
			return n
		end
		fn(Node, Frames)
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild, C_ChatInfo = saved.channel, saved.member, saved.guild, saved.inGuild, saved.chat
	Ed.after = saved.after
	Ed.Reset()
	if not ok then error(err, 0) end
end

-- Relay.HopTrusted's body is the relay mesh's (the design, 3a): false for a word an unsigned code pin
-- carries. Its step-0 stub trusts every hop, so here the pin's own verdict alone is set; every other
-- hop asks the real one.
local function PinUntrusted(N)
	local real = N.Relay.HopTrusted
	N.Relay.HopTrusted = function()
		local _, by = N.Relay.Hop()
		if by and ns.ShortName(by) == PIN then return false end
		return real()
	end
end

-- A word in Codec's pieces, each handed on by `via` over `hop` from `origin`.
local function Carry(N, hop, via, origin, word, id)
	for _, piece in ipairs(ns.Codec.Chunk(word, id or "41")) do N.Relay.TakeVia(hop, via, origin, piece) end
end

-- Fails before: the author is no Church ledger relay, so his CX 1 rows were unproven everywhere.
test("census author (1.5.5): the author's CX 1 rows a signed relay hands on count as the author's; an unsigned code pin's or a provisional relay's copy stays reported", function()
	World(function(Node)
		local function Word(N) return ("CX~1~S~%d~ForeverPvP,Alliance,13614,12900,30,%d"):format(N.clock, N.clock - 600) end
		local A = Node(LISTENER)
		eq(A.Relay.TakeVia("M", "Sage Ledger", AUTHOR, Word(A)), true, "delivered")
		local g = A.Data.Groups()
		local row = assert(PvP(g), "the row is held")
		eq(row.src, "author"); eq(row.counted, true); eq(row.characters, 13614); eq(row.observed, A.clock - 600)
		eq(g.characters, 13614, "in the all-server total")
		-- The newest observation wins, kept as it was observed.
		A.Relay.TakeVia("M", "Sage Ledger", AUTHOR, ("CX~1~S~%d~ForeverPvP,Alliance,13000,12000,30,%d"):format(A.clock, A.clock - 900))
		eq(assert(PvP(A.Data.Groups())).characters, 13614, "an older look does not replace a newer one")
		A.clock = A.clock + 60
		A.Relay.TakeVia("M", "Sage Ledger", AUTHOR, ("CX~1~S~%d~ForeverPvP,Alliance,13700,13000,30,%d"):format(A.clock, A.clock - 30))
		row = assert(PvP(A.Data.Groups()))
		eq(row.characters, 13700); eq(row.observed, A.clock - 30, "never re-stamped"); eq(row.src, "author")
		-- The same word carried by an unsigned code pin: a relay, but no signed one.
		local B = Node(LISTENER)
		PinUntrusted(B)
		eq(B.Relay.IsRelay(PIN), true, "the pin is a relay")
		B.Relay.TakeVia("M", PIN, AUTHOR, Word(B))
		row = assert(PvP(B.Data.Groups()))
		eq(row.counted, false, "an unsigned pin proves no origin"); eq(row.src, "heard")
		-- And by a provisional relay (RO): member weight, never a trusted origin's word.
		local C = Node(LISTENER)
		C.Relay.TakeVia("O", "Pro Visional-" .. PVE, AUTHOR, Word(C))
		row = assert(PvP(C.Data.Groups()))
		eq(row.counted, false, "a provisional relay carries no author"); eq(row.src, "heard")
		-- Nobody else's word on the same hop becomes the author's.
		local D = Node(LISTENER)
		D.Relay.TakeVia("M", "Sage Ledger", "Plain Member-" .. PVE, Word(D))
		eq(assert(PvP(D.Data.Groups())).counted, false, "a member's family row stays reported")
		eq(D.Data.CensusTrusted("Plain Member-" .. PVE), false)
		eq(D.Data.CensusTrusted(AUTHOR), true); eq(D.Data.CensusTrusted("Crown Bearer-" .. PVE), false, "the other PvE pin is no author")
		eq(D.Data.CensusTrusted(AUTHOR_PVP .. "-" .. PVP), true); eq(D.Data.CensusTrusted("Sage Warden-" .. PVE), true)
	end)
end)

-- Fails before: a CX 3 look counted only from its own observer, so the author's client carrying his
-- PvP character's look to PvE was "reported" like anyone's.
test("census author (1.5.5): the author's carried look whose observer is his PvP pin counts; a member forwarding it, or the author carrying someone else's look, stays unproven", function()
	World(function(Node)
		local function Look(N, observer) return ("CX~3~S~%s~ForeverPvP~Alliance~13614,12900,30,%d~"):format(observer, N.clock - 900) end
		local A = Node(LISTENER)
		A.Relay.TakeVia("M", "Sage Ledger", AUTHOR, Look(A, AUTHOR_PVP .. "-" .. PVP))
		local row = assert(PvP(A.Data.Groups()))
		eq(row.src, "author"); eq(row.counted, true); eq(row.characters, 13614); eq(row.observed, A.clock - 900)
		-- A member forwards the very same look.
		local B = Node(LISTENER)
		B.Relay.TakeVia("M", "Sage Ledger", "Plain Member-" .. PVE, Look(B, AUTHOR_PVP .. "-" .. PVP))
		row = assert(PvP(B.Data.Groups()))
		eq(row.counted, false, "a forwarder is no observer"); eq(row.src, "heard")
		-- The author carries another observer's look: his client would launder it.
		local C = Node(LISTENER)
		C.Relay.TakeVia("M", "Sage Ledger", AUTHOR, Look(C, "Other Observer-" .. PVP))
		row = assert(PvP(C.Data.Groups()))
		eq(row.counted, false, "another observer's look stays unproven"); eq(row.src, "heard")
		-- A look of another family whose observer is an author character of PvP: no author look of that family.
		local D = Node(LISTENER)
		D.Relay.TakeVia("M", "Sage Ledger", AUTHOR, ("CX~3~S~%s-%s~ForeverRP~Alliance~2000,1900,8,%d~"):format(AUTHOR_PVP, PVP, D.clock - 900))
		local rp = assert(Row(D.Data.Groups(), "ForeverRP"))
		eq(rp.counted, false, "the observer must be an author character of the look's own family"); eq(rp.src, "heard")
	end)
end)

-- The guild detail follows the same original observation as its aggregate, including a refresh.
local function DetailLook(observed, total)
	return ("CX~3~S~%s-%s~ForeverPvP~Alliance~%d,%d,1,%d~Olympus Detail,%d,10,250,%d")
		:format(AUTHOR_PVP, PVP, total, total, observed, total, observed)
end

local function CheckAuthorDetailRefresh(Node, Frames, signed)
	local Ed, seed = ns.Ed25519, string.rep("\31", 32)
	local pk = signed and Ed.PublicKey(seed) or nil
	local R = Node(LISTENER, { pk = pk and Ed.ToB64(pk) or nil })
	local t = R.clock
	local firstObserved, newerObserved = t - R.Data.TOTAL_KEEP + 30, t - 10
	local first, newer = DetailLook(firstObserved, 800), DetailLook(newerObserved, 900)
	local function Hear(wire, id)
		if signed then
			local qa = "QA~1~" .. Ed.ToB64(Ed.Sign(seed, "OLYQA1|" .. wire, pk)) .. "~" .. wire
			Carry(R, "M", "Sage Ledger", "Plain Member-" .. PVE, qa, id)
			Frames()
			return qa
		end
		Carry(R, "M", "Sage Ledger", AUTHOR, wire, id)
	end
	local firstQA = Hear(first, "71")
	local detail = assert(R.Data.GroupGuilds("ForeverPvP")[1])
	eq(detail.characters, 800); eq(detail.source, "author"); eq(detail.observed, firstObserved)
	R.clock = t + 60
	local newerQA = Hear(newer, "72")
	local aggregate = assert(PvP(R.Data.Groups()))
	eq(aggregate.characters, 900); eq(aggregate.observed, newerObserved)
	detail = assert(R.Data.GroupGuilds("ForeverPvP")[1])
	eq(detail.characters, 900, "new author details follow the refreshed aggregate")
	eq(detail.observed, newerObserved, "the author's original date survives receipt")
	eq(detail.source, "author"); eq(detail.counted, true, "the replaced first look's age cannot expire newer details")
	if signed then
		eq(R.Data.CensusStats().qa.verified, 2, "both author signatures were actually verified")
		assert(R.Data.ReceiveAttest("CHANNEL", "Another Carrier-" .. PVE, firstQA))
		assert(R.Data.ReceiveAttest("CHANNEL", "Another Carrier-" .. PVE, newerQA))
	else
		assert(R.Data.ReceivePortable(AUTHOR, first))
		assert(R.Data.ReceivePortable(AUTHOR, newer))
	end
	assert(R.Data.ReceivePortable("Plain Member-" .. PVE, DetailLook(R.clock - 1, 990)))
	detail = assert(R.Data.GroupGuilds("ForeverPvP")[1])
	eq(detail.characters, 900, "older, repeated and unproven looks cannot replace the author detail")
	eq(detail.observed, newerObserved, "a replay never renews the observation")
end

test("census author details: a newer trusted carried look refreshes author guild details and their original expiry", function()
	World(function(Node, Frames) CheckAuthorDetailRefresh(Node, Frames, false) end)
end)

test("census author details: a newer verified QA refreshes author guild details without replay or carrier upgrades", function()
	World(function(Node, Frames) CheckAuthorDetailRefresh(Node, Frames, true) end)
end)

test("census author details: a newer author look cannot replace this account's own guild-detail evidence", function()
	World(function(Node)
		local R = Node(LISTENER)
		local t = R.clock
		R.group, R.realm, R.me = "ForeverPvP", PVP, "Local Observer-" .. PVP
		R.rdb.guilds["Olympus Detail"] = { total = 875, online = 10, avgLevel = 25, t = t - 100, st = t - 100,
			from = PVP, faction = "Alliance" }
		assert(R.Data.CaptureGroupDetails(R.Data.Summary(), t))
		R.group, R.realm, R.me, R.rdb.guilds = "ForeverPvE", PVE, LISTENER, {}
		Carry(R, "M", "Sage Ledger", AUTHOR, DetailLook(t - 1, 900), "73")
		local detail = assert(R.Data.GroupGuilds("ForeverPvP")[1])
		eq(detail.source, "own"); eq(detail.characters, 875)
		eq(detail.observed, t - 100, "newer author data cannot relabel or renew stronger own evidence")
	end)
end)

-- Fails before: the author's client said no Forever row at all (not trusted), and a councillor's client
-- heard the author (groupHeard) but never said his row, so old clients counted nothing of it.
test("census author (1.5.5): the author's client says every family row it counts, never a heard or hand-over one; a councillor re-says his rows for old clients, not those taken over RG; a 1.5.4 receiver counts that copy", function()
	World(function(Node)
		local A = Node(AUTHOR)
		local t = A.clock
		local function Kept(group, characters, observed, src, extra)
			local e = { group = group, faction = "Alliance", characters = characters, people = characters - 10, guilds = 5,
				observed = observed, src = src, by = "Someone-" .. PVE, w = src == "witnessed" and 2 or 1 }
			for k, v in pairs(extra or {}) do e[k] = v end
			A.db.groupCensus["Alliance|" .. group] = e
		end
		A.db.groupCensus = {}
		Kept("ForeverPvP", 13614, t - 600, "own")
		Kept("ForeverRP", 2000, t - 700, "relay")
		Kept("ForeverRPPvP", 900, t - 800, "witnessed")
		Kept("ForeverHardcore", 700, t - 900, "author")
		Kept("ForeverSeasonal", 500, t - 1000, "author", { rg = true })
		Kept("ForeverEvent", 400, t - 3 * 86400, "own") -- kept, no longer counted (Data.GROUP_COUNT)
		A.db.groupHeard = { ["Alliance|ForeverFresh"] = { group = "ForeverFresh", faction = "Alliance", characters = 300,
			people = 300, guilds = 2, observed = t - 300, src = "heard", by = "Plain Member-" .. PVE, w = 0 } }
		local said = assert(A.Data.GroupCensusPayload(), "the author's client says its family rows")
		for _, want in ipairs({ "ForeverPvP,Alliance,13614,13604,5," .. (t - 600), "ForeverRP,Alliance,2000,1990,5," .. (t - 700),
			"ForeverRPPvP,Alliance,900,890,5," .. (t - 800), "ForeverHardcore,Alliance,700,690,5," .. (t - 900) }) do
			assert(said:find(want, 1, true), "said with its own observed time: " .. want .. " in " .. said)
		end
		for _, never in ipairs({ "ForeverSeasonal", "ForeverEvent", "ForeverFresh" }) do
			assert(not said:find(never, 1, true), never .. " is never said: " .. said)
		end
		-- A councillor's client hears the author's row on a stamped hop: it says it again for the clients
		-- that trust only the Church's ledger relays (1.5.4), though it heard the author say it.
		local H, hdeliver = Node("Sage Warden-" .. PVE)
		local word = ("CX~1~S~%d~ForeverPvP,Alliance,13614,12900,30,%d"):format(H.clock, H.clock - 600)
		hdeliver("WHISPER", "Sage Ledger", "RM~P~" .. AUTHOR .. "~" .. word) -- (a signed relay's RM: Relay.HandleRelayed)
		eq(assert(PvP(H.Data.Groups())).src, "author")
		local resaid = assert(H.Data.GroupCensusPayload(), "the councillor re-says the author's row")
		assert(resaid:find("ForeverPvP,Alliance,13614,12900,30," .. (H.clock - 600), 1, true), resaid)
		-- A row of the author's it took over RG (a guildmate's hand-over: Relay.HandleGuild) counts on its
		-- page, never in its word.
		hdeliver("GUILD", "Guild Mate-" .. PVE, "RG~P~" .. AUTHOR .. "~" .. ("CX~1~S~%d~ForeverRP,Alliance,2000,1900,8,%d"):format(H.clock, H.clock - 650))
		local rp = assert(Row(H.Data.Groups(), "ForeverRP"))
		eq(rp.counted, true, "shown and counted here"); eq(rp.src, "author")
		resaid = assert(H.Data.GroupCensusPayload())
		assert(not resaid:find("ForeverRP", 1, true), "never re-said: " .. resaid)
		-- The same row again on a stamped hop: said from then on.
		hdeliver("WHISPER", "Sage Ledger", "RM~P~" .. AUTHOR .. "~" .. ("CX~1~S~%d~ForeverRP,Alliance,2000,1900,8,%d"):format(H.clock - 1, H.clock - 650))
		local stamped = assert(H.Data.GroupCensusPayload())
		assert(stamped:find("ForeverRP,Alliance,2000,1900,8," .. (H.clock - 650), 1, true), "said once a stamped hop brought it: " .. stamped)
		-- Another ledger relay saying the same row keeps it quiet: a 1.5.4 client counted that word.
		H.Data.ReceiveGroupCensus("CHANNEL", "Sage Ledger-" .. PVE, ("CX~1~S~%d~ForeverPvP,Alliance,13614,12900,30,%d"):format(H.clock, H.clock - 600))
		local quiet = tostring(H.Data.GroupCensusPayload())
		assert(not quiet:find("ForeverPvP", 1, true), "a ledger relay said it already: " .. quiet)
		-- A 1.5.4 client (its own Data.lua, tests/fixtures/data-1.5.4.lua) counts the councillor's copy...
		local O = Node("Old Listener-" .. PVE, { file = ROOT .. "tests/fixtures/data-1.5.4.lua" })
		eq(O.Data.ReceiveGroupCensus("CHANNEL", "Sage Warden-" .. PVE, resaid), true)
		local old = assert(PvP(O.Data.Groups()))
		eq(old.counted, true, "the ledger relay's copy counts on a 1.5.4 client"); eq(old.characters, 13614)
		-- ...and nothing of the author's own word.
		local O2 = Node("Old Listener-" .. PVE, { file = ROOT .. "tests/fixtures/data-1.5.4.lua" })
		O2.Data.ReceiveGroupCensus("CHANNEL", AUTHOR, word)
		eq(assert(PvP(O2.Data.Groups())).counted, false, "1.5.4 counts no author")
	end)
end)

-- Fails before: no client said a Forever family's capsule (its guilds), and none was taken from anyone.
test("census author (1.5.5): the author's client says its own capsule of a family's guilds; a listener takes it as his, from him alone", function()
	World(function(Node)
		local A = Node(AUTHOR_PVP .. "-" .. PVP)
		for i = 1, 12 do A.rdb.guilds["Olympus Pvp " .. i] = { total = 300 + i, online = 10, t = A.clock - 60, from = PVP } end
		assert(A.Data.RecordGroupCensus())
		-- He logs into PvE: his client says his PvP capsule there.
		A.me, A.group, A.realm, A.rdb.guilds = AUTHOR, "ForeverPvE", PVE, {}
		local said = {}
		A.Comm.SendChunked = function(payload) said[#said + 1] = payload return true end
		eq(A.Data.SayGroupDetails(), true)
		local capsule = said[1]
		assert(capsule and capsule:match("^CX~2~S~%d+~ForeverPvP~Alliance~Olympus Pvp"), "his own capsule: " .. tostring(capsule))
		local R = Node(LISTENER)
		Carry(R, "M", "Sage Ledger", AUTHOR, capsule, "61")
		local guilds = R.Data.GroupGuilds("ForeverPvP", "Alliance")
		eq(#guilds, 12, "every guild of his look"); eq(guilds[1].name, "Olympus Pvp 12"); eq(guilds[1].characters, 312)
		eq(guilds[1].source, "author"); eq(guilds[1].counted, true)
		-- The same capsule from anyone else is ignored, as every family's capsule was.
		local M = Node(LISTENER)
		Carry(M, "M", "Sage Ledger", "Plain Member-" .. PVE, capsule, "62")
		eq(#M.Data.GroupGuilds("ForeverPvP", "Alliance"), 0, "a member's copy proves nothing")
		-- A councillor's client never says its own family capsule: only the author's does.
		local H = Node("Sage Warden-" .. PVP)
		for i = 1, 12 do H.rdb.guilds["Olympus Pvp " .. i] = { total = 300 + i, online = 10, t = H.clock - 60, from = PVP } end
		assert(H.Data.RecordGroupCensus())
		H.me, H.group, H.realm, H.rdb.guilds = "Sage Warden-" .. PVE, "ForeverPvE", PVE, {}
		H.Comm.SendChunked = function() error("nothing to say") end
		eq(H.Data.SayGroupDetails(), false)
	end)
end)

-- Fails before: the author's CG rows were one witness's.
test("census author (1.5.5): the author's CG 2 rows on a signed relay's hop stand alone; a member's still need a second witness; a councillor never puts a hand-over row in its own snapshot", function()
	World(function(Node)
		local function Snapshot(N, rows, made)
			local out = {}
			for _, r in ipairs(rows) do out[#out + 1] = ("%s,%d,%d,%d,%d"):format(r[1], r[2], r[3] or 40, r[4] or 300, r[5]) end
			return ("CG~2~S~%d~ForeverPvE~Alliance~%s"):format(made or N.clock, table.concat(out, ";"))
		end
		local R = Node(LISTENER)
		R.Relay.TakeVia("M", "Sage Ledger", AUTHOR, Snapshot(R, { { "Olympus Dawn", 640, 40, 300, R.clock - 60 } }))
		local s = R.Data.Summary()
		eq(s.characters, 640, "the author's row stands alone"); eq(#s.guilds, 1); eq(s.guilds[1].g.relayed, true)
		eq(R.Data.GlobalWitnesses("Olympus Dawn"), 1)
		-- A member's row: one witness; a second agreeing person confirms it.
		local M = Node(LISTENER)
		M.Relay.TakeVia("M", "Sage Ledger", "Plain Member-" .. PVE, Snapshot(M, { { "Olympus Dawn", 640, 40, 300, M.clock - 60 } }))
		eq(M.Data.Summary().characters, 0, "one member is one witness")
		M.Relay.TakeVia("M", "Sage Ledger", "Second Member-" .. PVE, Snapshot(M, { { "Olympus Dawn", 642, 40, 300, M.clock - 30 } }))
		eq(M.Data.Summary().characters, 642, "two agreeing people confirm it")
		-- The author's row unproven on its hop: an unsigned pin's.
		local U = Node(LISTENER)
		PinUntrusted(U)
		U.Relay.TakeVia("M", PIN, AUTHOR, Snapshot(U, { { "Olympus Dawn", 640, 40, 300, U.clock - 60 } }))
		eq(U.Data.Summary().characters, 0, "an unsigned pin's copy is one witness")
		-- A councillor takes the author's row over RG (a guildmate's hand-over, Relay.HandleGuild): counted,
		-- never in its own snapshot.
		local H, hdeliver = Node("Sage Warden-" .. PVE)
		hdeliver("GUILD", "Guild Mate-" .. PVE, "RG~P~" .. AUTHOR .. "~" .. Snapshot(H, { { "Olympus Dusk", 510, 30, 280, H.clock - 120 } }))
		eq(H.Data.Summary().characters, 510, "shown and counted")
		local own = assert(H.Data.GlobalCensusPayload())
		assert(not own:find("Olympus Dusk", 1, true), "a hand-over row is not in a trusted holder's snapshot: " .. own)
		-- The same row on a stamped hop (a signed relay's RM, Relay.HandleRelayed): now its own word.
		hdeliver("WHISPER", "Sage Ledger", "RM~P~" .. AUTHOR .. "~" .. Snapshot(H, { { "Olympus Dusk", 510, 30, 280, H.clock - 120 } }, H.clock - 1))
		own = assert(H.Data.GlobalCensusPayload())
		assert(own:find("Olympus Dusk,510,30,280," .. (H.clock - 120), 1, true), "said once a stamped hop brought it: " .. own)
	end)
end)

-- Fails before: there was no signed look; a member's copy of the author's look was "reported".
test("census author (1.5.5): the author's signed look (QA) counts as his whoever carries it, even a provisional relay; a changed byte, an empty key or another account's key gives nothing", function()
	World(function(Node, Frames)
		local Ed = ns.Ed25519
		local seed, other = string.rep("\23", 32), string.rep("\5", 32)
		local PK = Ed.ToB64(Ed.PublicKey(seed))
		-- The account key (Debts.lua's ns.db.arenaKey) and its signer, counted.
		local function Account(N, keySeed)
			local pk = Ed.PublicKey(keySeed)
			N.db.arenaKey = { seed = Ed.ToB64(keySeed), pk = Ed.ToB64(pk), at = 1, claims = {} }
			local calls = { n = 0 }
			N.Debts = { Sign = function(msg) calls.n = calls.n + 1; return Ed.Sign(keySeed, msg, pk) end }
			return calls
		end
		local function PvPCensus(N)
			for i = 1, 30 do N.rdb.guilds["Olympus Pvp " .. i] = { total = 400 + i, online = 20, t = N.clock - 60, from = PVP } end
			return 30 * 400 + 465
		end
		-- The author's PvP character records its look; his account holds the key.
		local A = Node(AUTHOR_PVP .. "-" .. PVP, { pk = PK })
		local calls = Account(A, seed)
		local total = PvPCensus(A)
		assert(A.Data.RecordGroupCensus())
		eq(calls.n, 1, "its own look signed once"); eq(A.Data.CensusStats().qa.signed, 1)
		assert(A.Data.RecordGroupCensus())
		eq(calls.n, 1, "the same look is not signed again")
		-- He logs into PvE: his client says the signed look there.
		A.me, A.group, A.realm, A.rdb.guilds = AUTHOR, "ForeverPvE", PVE, {}
		local said = {}
		A.Comm.SendChunked = function(payload) said[#said + 1] = payload return true end
		A.clock = A.clock + 60
		eq(A.Data.SayGroupCensus(), true)
		local qa = said[1]
		assert(qa and qa:match("^QA~1~[%w%-_]+~CX~3~S~" .. AUTHOR_PVP .. "%-" .. PVP .. "~ForeverPvP~Alliance~"), "the signed look: " .. tostring(qa))
		eq(#qa:match("^QA~1~([^~]+)~"), 86, "the signature")
		eq(#ns.Codec.Chunk(qa, "1"), 2, "two pieces")
		-- A member carries it to a listener: the author's.
		local R = Node(LISTENER, { pk = PK })
		Carry(R, "M", "Sage Ledger", "Plain Member-" .. PVE, qa)
		eq(PvP(R.Data.Groups()), nil, "checked off the frame")
		assert(Frames() > 0, "checked in Ed25519's jobs")
		local row = assert(PvP(R.Data.Groups()), "taken once checked")
		eq(row.src, "author"); eq(row.counted, true); eq(row.characters, total)
		eq(R.Data.CensusStats().qa.verified, 1)
		-- Heard again: taken from the memo, no second check.
		Carry(R, "M", "Sage Ledger", "Second Member-" .. PVE, qa, "42")
		eq(Frames(), 0, "one check per distinct word"); eq(R.Data.CensusStats().qa.verified, 1)
		-- Through a provisional relay too.
		local P = Node(LISTENER, { pk = PK })
		Carry(P, "O", "Pro Visional-" .. PVE, "Plain Member-" .. PVE, qa)
		Frames()
		eq(assert(PvP(P.Data.Groups())).src, "author", "self-checking: any carrier")
		-- One changed byte: refused.
		local forged = qa:gsub("~Alliance~" .. total .. ",", "~Alliance~" .. (total + 1) .. ",", 1)
		assert(forged ~= qa)
		local F = Node(LISTENER, { pk = PK })
		Carry(F, "M", "Sage Ledger", "Plain Member-" .. PVE, forged)
		Frames()
		eq(PvP(F.Data.Groups()), nil, "nothing taken of a forged look")
		local fs = F.Data.CensusStats()
		eq(fs.qa.refused, 1); eq(fs.qa.verified, 0); eq(fs.last[1].why, "signature")
		-- At most Data.ATTEST_JOBS checks of ours wait at once (Ed25519's queue is the arena's too): a word
		-- past them is refused, and taken when it is heard again.
		local B = Node(LISTENER, { pk = PK })
		Carry(B, "M", "Sage Ledger", "Plain Member-" .. PVE, forged, "43")
		Carry(B, "M", "Sage Ledger", "Plain Member-" .. PVE, (qa:gsub("~Alliance~" .. total .. ",", "~Alliance~" .. (total + 2) .. ",", 1)), "44")
		Carry(B, "M", "Sage Ledger", "Second Member-" .. PVE, qa, "45")
		eq(B.Data.CensusStats().last[1].why, "busy", "a third word while two wait")
		Frames()
		eq(PvP(B.Data.Groups()), nil, "the two forged words refused, the real one not yet checked")
		Carry(B, "M", "Sage Ledger", "Second Member-" .. PVE, qa, "46")
		Frames()
		eq(assert(PvP(B.Data.Groups())).src, "author", "heard again: checked and taken")
		-- An empty constant: nothing taken...
		local E = Node(LISTENER, { pk = "" })
		Carry(E, "M", "Sage Ledger", "Plain Member-" .. PVE, qa)
		eq(Frames(), 0, "nothing checked")
		eq(PvP(E.Data.Groups()), nil); eq(E.Data.CensusStats().qa.refused, 1)
		-- ...and nothing signed.
		local A2 = Node(AUTHOR_PVP .. "-" .. PVP, { pk = "" })
		local calls2 = Account(A2, seed)
		PvPCensus(A2)
		assert(A2.Data.RecordGroupCensus())
		eq(calls2.n, 0, "an empty constant signs nothing"); eq(A2.Data.CensusStats().qa.signed, 0)
		-- Another account's key never signs, nor does a client with no key (none is made for it).
		local A3 = Node(AUTHOR_PVP .. "-" .. PVP, { pk = PK })
		local calls3 = Account(A3, other)
		PvPCensus(A3)
		assert(A3.Data.RecordGroupCensus())
		eq(calls3.n, 0, "another account's key signs nothing")
		local A4 = Node(AUTHOR_PVP .. "-" .. PVP, { pk = PK })
		local calls4 = Account(A4, seed)
		A4.db.arenaKey = nil
		PvPCensus(A4)
		assert(A4.Data.RecordGroupCensus())
		eq(calls4.n, 0, "no key, no signature"); eq(A4.db.arenaKey, nil, "and no key made")
		-- A holder says the checked word once per origin a window, unless a newer one was heard in it.
		local saidR = {}
		R.Comm.SendChunked = function(payload) saidR[#saidR + 1] = payload return true end
		R.Data.SayGroupCensus()
		for _, p in ipairs(saidR) do assert(not p:match("^QA~"), "just heard: not said again yet") end
		R.clock = R.clock + R.Data.GROUP_SAY_EVERY + 1
		saidR = {}
		R.Data.SayGroupCensus()
		eq(saidR[1], qa, "the holder says the checked word half an hour later")
		saidR = {}
		R.clock = R.clock + R.Data.GROUP_SEND_GAP
		R.Data.SayGroupCensus()
		for _, p in ipairs(saidR) do assert(not p:match("^QA~"), "once a window") end
	end)
end)

-- Fails before: the label had no key ("author" mapped to nothing) in either map or any language.
test("census author (1.5.5): the census page names the author's word in both its maps, in all seven languages", function()
	assert(loadfile(ROOT .. "Olympus/Locales/CensusStatsText.lua"))("Olympus", ns)
	local L = ns.L
	assert(rawget(L, "CENSUS_STATS_SRC_AUTHOR"), "the English line")
	local T0 = os.time({ year = 2026, month = 11, day = 10, hour = 15, min = 0, sec = 0 })
	local cns = setmetatable({
		rdb = {},
		Data = setmetatable({
			Summary = function() return { characters = 0, total = 0, online = 0, guilds = {} } end,
			Groups = function() return { characters = 500, people = 480, kinds = {}, regions = {}, factions = {},
				rows = { { group = "ForeverPvP", faction = "Alliance", characters = 500, people = 480, guilds = 3,
					observed = T0 - 600, src = "author", counted = true, ours = false } } } end,
			GroupGuilds = function() return { { name = "Olympus Dawn", characters = 500, observed = T0 - 600, source = "author", counted = true } } end,
		}, { __index = ns.Data }),
		Now = function() return T0 end,
		Comm = { loginAt = T0 - 86400, Send = function() end, SendChunked = function() end },
		On = function() end,
		Every = function() end,
	}, { __index = ns })
	assert(loadfile(ROOT .. "Olympus/CensusStats.lua"))("Olympus", cns)
	local CS = cns.CensusStats
	local function Tip(line)
		local tip = {}
		line.tooltip({ AddLine = function(_, text) tip[#tip + 1] = text end, AddDoubleLine = function() end })
		return table.concat(tip, "\n")
	end
	local census = cns.Data.Summary()
	local lines = {}
	CS.ServerLines(lines, census, T0)
	local server
	for _, line in ipairs(lines) do if line.onClick then server = line end end
	assert(server, "the server's line")
	assert(Tip(server):find(L.CENSUS_STATS_SRC_AUTHOR, 1, true), "the server's tooltip names the author's word")
	server.onClick()
	lines = {}
	CS.ServerLines(lines, census, T0)
	local detail
	for _, line in ipairs(lines) do if line.text == "Olympus Dawn" then detail = line end end
	assert(detail, "the guild's line")
	assert(Tip(detail):find(L.CENSUS_STATS_SRC_AUTHOR, 1, true), "the guild's tooltip names the author's word")
	server.onClick() -- (closed again)
	-- Every language the addon speaks, each as the game loads it.
	local function Words(code)
		local lns, saved = {}, GetLocale
		GetLocale = function() return code end
		local ok, err = pcall(function()
			assert(loadfile(ROOT .. "Olympus/Locales.lua"))("Olympus", lns)
			assert(loadfile(ROOT .. "Olympus/Locales/CensusStatsText.lua"))("Olympus", lns)
			if code ~= "enUS" and code ~= "ptBR" then assert(loadfile(ROOT .. "Olympus/Locales/" .. code .. ".lua"))("Olympus", lns) end
		end)
		GetLocale = saved
		if not ok then error(err, 0) end
		return lns.L
	end
	local english = Words("enUS").CENSUS_STATS_SRC_AUTHOR
	eq(english, L.CENSUS_STATS_SRC_AUTHOR)
	for _, code in ipairs({ "ptBR", "deDE", "esES", "frFR", "itIT", "ruRU" }) do
		local text = Words(code).CENSUS_STATS_SRC_AUTHOR
		assert(type(text) == "string" and text ~= "" and text ~= "CENSUS_STATS_SRC_AUTHOR", code .. " has the line")
		assert(text ~= english, code .. " translates it")
	end
end)

-- Fails before: a provisional relay's snapshot held every row it had heard, others' hand-overs and the
-- global rows among them, at member weight on two hops.
test("census author (1.5.5): a serving provisional relay's snapshot holds only the rows it heard first-hand, never the global ones", function()
	World(function(Node)
		local P = Node("Pro Visional-" .. PVE)
		local id = 60
		local function Report(how, via, sender, guild, total)
			id = id + 1
			local r = { guild = guild, total = total, online = 20, leader = "Lead " .. guild:match("(%a+)$"), zones = {}, from = PVE, avgLevel = 30 }
			for _, piece in ipairs(ns.Codec.Chunk(ns.Codec.EncodeReport(r), tostring(id))) do P.Relay.TakeVia(how, via, sender, piece) end
		end
		-- A reporter whispers its guild's report to it (first-hand); another guild's report comes as a
		-- guildmate's hand-over; the author's snapshot brings a global row.
		Report("L", "Dawn Reporter-" .. PVE, "Dawn Reporter-" .. PVE, "Olympus Dawn", 500)
		Report("G", "Guild Mate-" .. PVE, "Dusk Reporter-" .. PVE, "Olympus Dusk", 400)
		P.Relay.TakeVia("M", "Sage Ledger", AUTHOR, ("CG~2~S~%d~ForeverPvE~Alliance~Olympus Noon,300,10,250,%d"):format(P.clock, P.clock - 60))
		P.Data.SetLocal({ guild = "Olympus II", total = 90, online = 9, zones = {} })
		eq(P.rdb.guilds["Olympus Dawn"].fh, true, "taken first-hand"); eq(P.rdb.guilds["Olympus Dusk"].fh, nil)
		eq(P.Data.Summary().characters, 1290, "all four counted here")
		-- Not serving: a member's snapshot, as before (its own direct rows and the confirmed ones).
		local before = assert(P.Data.GlobalCensusPayload())
		for _, name in ipairs({ "Olympus Dawn", "Olympus Dusk", "Olympus Noon", "Olympus II" }) do assert(before:find(name, 1, true), name .. ": " .. before) end
		-- Serving as a provisional relay (the fallback's word): first-hand rows alone.
		P.Relay.ServingProvisional = function() return true end
		local serving = assert(P.Data.GlobalCensusPayload())
		assert(serving:find("Olympus Dawn,500,20,300,", 1, true), serving)
		assert(serving:find("Olympus II,90,9,", 1, true), "its own roster is first-hand: " .. serving)
		assert(not serving:find("Olympus Dusk", 1, true), "no hand-over: " .. serving)
		assert(not serving:find("Olympus Noon", 1, true), "no global row: " .. serving)
	end)
end)

-- Fails before: nothing counted what the census took, refused or left unproven (Data.CensusStats).
test("census author (1.5.5): Data.CensusStats counts the rows trusted, witnessed, lone, heard and unproven, the looks, the signed looks and the last refusals", function()
	World(function(Node, Frames)
		local Ed = ns.Ed25519
		local seed = string.rep("\31", 32)
		local pk = Ed.PublicKey(seed)
		local PK = Ed.ToB64(pk)
		local R = Node(LISTENER, { pk = PK })
		local t = R.clock
		local function CX(rows) return ("CX~1~S~%d~%s"):format(t, rows) end
		-- CX 1: the author's, a councillor's, a member's family row, a member's lone row of a plain realm group
		-- and two people agreeing on another; one malformed word.
		R.Relay.TakeVia("M", "Sage Ledger", AUTHOR, CX(("ForeverPvP,Alliance,13614,12900,30,%d"):format(t - 600)))
		R.Relay.TakeVia("M", "Sage Ledger", "Sage Warden-" .. PVE, CX(("ForeverRP,Alliance,2000,1900,8,%d"):format(t - 600)))
		R.Relay.TakeVia("M", "Sage Ledger", "Plain Member-" .. PVE, CX(("ForeverHardcore,Alliance,700,690,4,%d"):format(t - 600)))
		R.Relay.TakeVia("M", "Sage Ledger", "Plain Member-" .. PVE, CX(("Oldrealm,Alliance,640,640,1,%d"):format(t - 600)))
		R.Relay.TakeVia("M", "Sage Ledger", "Plain Member-" .. PVE, CX(("Newrealm,Alliance,300,300,1,%d"):format(t - 600)))
		R.Relay.TakeVia("M", "Sage Ledger", "Second Member-" .. PVE, CX(("Newrealm,Alliance,301,301,1,%d"):format(t - 500)))
		eq(R.Data.ReceiveGroupCensus("CHANNEL", "Plain Member-" .. PVE, "CX~1~S~x~nothing"), false)
		-- CX 3: the author's carried look, a member's forward, an observer's own look.
		R.Relay.TakeVia("M", "Sage Ledger", AUTHOR, ("CX~3~S~%s-%s~ForeverPvP~Alliance~13700,13000,30,%d~"):format(AUTHOR_PVP, PVP, t - 300))
		R.Relay.TakeVia("M", "Sage Ledger", "Plain Member-" .. PVE, ("CX~3~S~Other Observer-%s~ForeverPvP~Alliance~13000,13000,30,%d~"):format(PVP, t - 200))
		R.Relay.TakeVia("M", "Sage Ledger", "Visitor-" .. PVE, ("CX~3~S~Visitor-%s~Oldrealm~Alliance~650,650,1,%d~"):format(PVE, t - 100))
		-- CG 2: the author's row, a member's lone row, two agreeing members, one malformed snapshot.
		local function CG(rows) return ("CG~2~S~%d~ForeverPvE~Alliance~%s"):format(t, rows) end
		R.Relay.TakeVia("M", "Sage Ledger", AUTHOR, CG(("Olympus Dawn,640,40,300,%d"):format(t - 60)))
		R.Relay.TakeVia("M", "Sage Ledger", "Plain Member-" .. PVE, CG(("Olympus Dusk,500,40,300,%d"):format(t - 60)))
		R.Relay.TakeVia("M", "Sage Ledger", "Plain Member-" .. PVE, CG(("Olympus Noon,300,10,250,%d"):format(t - 60)))
		R.Relay.TakeVia("M", "Sage Ledger", "Second Member-" .. PVE, CG(("Olympus Noon,301,10,250,%d"):format(t - 30)))
		eq(R.Data.ReceiveGlobalCensus("CHANNEL", "Plain Member-" .. PVE, CG("Olympus Bad,x")), false)
		-- QA: one signed look checked, one forged refused.
		local wire = ("CX~3~S~%s-%s~ForeverRPPvP~Alliance~900,890,5,%d~"):format(AUTHOR_PVP, PVP, t - 400)
		local sig = Ed.ToB64(Ed.Sign(seed, "OLYQA1|" .. wire, pk))
		Carry(R, "M", "Sage Ledger", "Plain Member-" .. PVE, "QA~1~" .. sig .. "~" .. wire, "51")
		Carry(R, "M", "Sage Ledger", "Plain Member-" .. PVE, "QA~1~" .. sig .. "~" .. wire:gsub("900,890", "990,890"), "52")
		Frames()
		local s = R.Data.CensusStats()
		eq(s.cx.author, 1); eq(s.cx.trusted, 1); eq(s.cx.unproven, 1); eq(s.cx.heard, 2, "the lone rows"); eq(s.cx.witnessed, 1)
		eq(s.cx.refused, 1)
		eq(s.cx3.author, 1); eq(s.cx3.unproven, 1); eq(s.cx3.direct, 1)
		eq(s.cg.trusted, 1); eq(s.cg.lone, 2); eq(s.cg.witnessed, 1); eq(s.cg.refused, 1)
		eq(s.qa.verified, 1); eq(s.qa.refused, 1); eq(s.qa.signed, 0)
		eq(#s.last, 3, "the refusals, newest first"); eq(s.last[1].kind, "qa"); eq(s.last[1].why, "signature")
		eq(s.last[2].kind, "cg"); eq(s.last[3].kind, "cx")
		assert(type(s.line) == "string" and s.line:find("cx a1 t1", 1, true), "one line for /oly bug: " .. tostring(s.line))
		-- The checked look counted as the author's; the copy is a copy (changing it changes nothing here).
		eq(assert(Row(R.Data.Groups(), "ForeverRPPvP")).src, "author")
		s.cx.author = 99
		eq(R.Data.CensusStats().cx.author, 1)
		-- At most the last five refusals.
		for i = 1, 7 do R.Data.ReceiveGroupCensus("CHANNEL", "Plain Member-" .. PVE, "CX~1~S~x~" .. i) end
		eq(#R.Data.CensusStats().last, 5)
	end)
end)

-- 1.5.8 (the author, 11-12: "ele deveria redistribuir esses dados enquanto não tivessem dados novos na
-- rede"). Fails before: another origin's accepted look left the "all servers" total GROUP_COUNT (48 h)
-- after it was observed, on every client at once, and its holders stopped saying it then too.
test("census author (1.5.8): another origin's accepted look keeps counting, dated, past two days until a newer accepted look replaces it; its holders keep saying it", function()
	World(function(Node)
		local DAY = 86400
		local L = Node(LISTENER)
		L.clock = 20 * DAY
		local seen = L.clock - 600
		L.Relay.TakeVia("M", "Sage Ledger", AUTHOR, ("CX~1~S~%d~ForeverPvP,Alliance,5498,5400,24,%d"):format(L.clock, seen))
		eq(assert(PvP(L.Data.Groups())).counted, true, "counted when heard")
		L.clock = L.clock + 3 * DAY -- past GROUP_COUNT, inside GROUP_KEEP
		local g = L.Data.Groups()
		local row = assert(PvP(g), "still listed")
		eq(row.counted, true, "still counted with no newer look"); eq(row.observed, seen, "dated as it was observed")
		eq(row.src, "author")
		local here = 0
		for _, r in ipairs(g.rows) do if r.ours and r.counted then here = here + r.characters end end
		eq(g.characters, here + 5498, "in the all-server total")
		-- A newer accepted look of the origin replaces it, even one covering fewer guilds now that the held
		-- one is past the two days in which a wider look is kept against a narrow one.
		L.Relay.TakeVia("M", "Sage Ledger", AUTHOR, ("CX~1~S~%d~ForeverPvP,Alliance,4100,4000,9,%d"):format(L.clock, L.clock - 60))
		row = assert(PvP(L.Data.Groups()))
		eq(row.characters, 4100, "the newer look replaces it"); eq(row.observed, L.clock - 60); eq(row.counted, true)
		-- An older look never takes its place back.
		L.Relay.TakeVia("M", "Sage Ledger", AUTHOR, ("CX~1~S~%d~ForeverPvP,Alliance,5498,5400,24,%d"):format(L.clock, seen))
		eq(assert(PvP(L.Data.Groups())).characters, 4100)
		-- The author's client says the newest look it holds however old it is, and a councillor re-says the
		-- author's (for the clients that trust only the Church's ledger relays).
		local A = Node(AUTHOR)
		A.clock = 20 * DAY
		A.db.groupCensus = { ["Alliance|ForeverPvP"] = { group = "ForeverPvP", faction = "Alliance", characters = 5498,
			people = 5400, guilds = 24, observed = A.clock - 3 * DAY, src = "own", by = AUTHOR_PVP .. "-" .. PVP, w = 1 } }
		local said = tostring(A.Data.GroupCensusPayload())
		assert(said:find("ForeverPvP,Alliance,5498,5400,24," .. (A.clock - 3 * DAY), 1, true), "the author says it: " .. said)
		local H = Node("Sage Warden-" .. PVE)
		H.clock = 20 * DAY
		H.db.groupCensus = { ["Alliance|ForeverPvP"] = { group = "ForeverPvP", faction = "Alliance", characters = 5498,
			people = 5400, guilds = 24, observed = H.clock - 3 * DAY, src = "author", by = AUTHOR, w = 1 } }
		local resaid = tostring(H.Data.GroupCensusPayload())
		assert(resaid:find("ForeverPvP,Alliance,5498,5400,24," .. (H.clock - 3 * DAY), 1, true), "the councillor re-says it: " .. resaid)
		-- Past GROUP_KEEP (seven days) it is gone, as before: nothing older is listed or said.
		L.clock = L.clock + 8 * DAY
		eq(PvP(L.Data.Groups()), nil, "a look older than GROUP_KEEP is dropped")
	end)
end)
