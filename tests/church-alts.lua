-- 1.6.0, the Church's credit for a linked alt's recruits, end to end: one player, an Apostle and his
-- guild's master, links eight alts on three sub-realms of a WoW: Forever ruleset (one more on the other
-- ruleset, and a ninth character, never linked) and recruits on them in three guilds; keepers of 1.6.0
-- and of 1.5.9 (tests/fixtures/*-1.5.9.lua: that release's ChurchCount, RecruitRanking and Alts; its other
-- Church files are this tree's, unchanged since), witnesses in each guild. The real Church, ChurchCount,
-- RecruitRanking and Alts files in every client (tests/church-world.lua); one character of an account
-- online at a time, every login a fresh session over the account's saved variables. The channel is the
-- harness's own, perfect unless a test loses the alt claims on it (World.lost: Forever's relays at their
-- worst). Every name is invented.
-- Run alone: luajit tests/run.lua "church alts"
local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]church%-alts%.lua$")) or "./"
local FIXTURES = ROOT .. "tests/fixtures/"
local World = assert(loadfile(ROOT .. "tests/church-world.lua"))(ns, ROOT)
local Key = World.Key

local R1, R2, R3, RP = "CAMWOWUS1Realm1PvE", "CAMWOWUS1Realm2PvE", "CAMWOWUS1Realm3PvE", "CAMWOWUS1Realm1PvP"
local G1, G2, G3 = World.GUILD, World.GUILD2, "Olympus Dawn"
local MAIN = "Corvin Ashdale-" .. R1

-- Core.lua's name helpers read the harness's own realm, ruleset and faction: each client runs with its
-- own there, so FullName, RealmOf and GroupOf answer as they do on that client in game.
local function Pack(...) return { n = select("#", ...), ... } end
local baseAs = World.As
function World:As(cl, fn, ...)
	local r, g, f = ns.realm, ns.group, ns.faction
	ns.realm, ns.group, ns.faction = cl.ns.realm, cl.ns.group, cl.ns.faction
	local out = Pack(pcall(baseAs, self, cl, fn, ...))
	ns.realm, ns.group, ns.faction = r, g, f
	if not out[1] then error(out[2], 0) end
	return unpack(out, 2, out.n)
end

local function RealmOf(full) return full:match("%-(.+)$") end
local function Plain(full) return full:match("^[^%-]+") end

-- A client. opts: guild, rank, db, rdb, legacy (1.5.9's ChurchCount, RecruitRanking and Alts).
local function MakeClient(w, full, opts)
	opts = opts or {}
	local cl = w:Client(full, { guild = opts.guild, rank = opts.rank, old = opts.legacy or nil, rdb = opts.rdb })
	local c = cl.ns
	c.realm, c.group, c.faction = RealmOf(full), ns.ForeverFamily(RealmOf(full)), "Alliance"
	c.Roster.group = c.group
	if opts.db then c.db = opts.db end
	-- The census's word on another guild's officers (Channels.VerifiedLevel): rank 1 or 0 there.
	c.Channels.VerifiedLevel = function(who, guild)
		local o = w.byKey[Key(who)] or (w.offline and w.offline[Key(who)])
		if o and o.guild and guild and ns.Fold(o.guild) == ns.Fold(guild) and (o.rank or 3) <= 1 then return 1, true end
		return 0, false
	end
	if opts.legacy then
		w:As(cl, function()
			assert(loadfile(ROOT .. "Olympus/RankingRules.lua"))("Olympus", c)
			assert(loadfile(ROOT .. "Olympus/ChatRooms.lua"))("Olympus", c)
			assert(loadfile(ROOT .. "Olympus/Church.lua"))("Olympus", c)
			assert(loadfile(FIXTURES .. "church-count-1.5.9.lua"))("Olympus", c)
			assert(loadfile(ROOT .. "Olympus/ChurchFullness.lua"))("Olympus", c)
			assert(loadfile(FIXTURES .. "recruit-ranking-1.5.9.lua"))("Olympus", c)
		end)
		c.Church.after = function(seconds, _, fn) w:Later(cl, seconds, fn) end
		c.ChurchCount.after = c.Church.after
		c.RecruitRanking.after = c.Church.after
		cl.RR = c.RecruitRanking
		c.Church.random = function(a) return a end
		c.ChurchCount.random = function(a) return a end
		c.Church.chance = function() return 0 end
		c.ChurchCount.chance = function() return 0 end
		c.ChatRooms.Reset()
		cl.Church, cl.Count, cl.View = c.Church, c.ChurchCount, c.ChurchView
	end
	local before = #(cl.listeners.LOGIN or {})
	local popup = StaticPopupDialogs.OLYMPUS_ALT_CONFIRM
	w:As(cl, function() assert(loadfile(opts.legacy and (FIXTURES .. "alts-1.5.9.lua") or (ROOT .. "Olympus/Alts.lua")))("Olympus", c) end)
	cl.altPopup = StaticPopupDialogs.OLYMPUS_ALT_CONFIRM
	StaticPopupDialogs.OLYMPUS_ALT_CONFIRM = popup
	-- Alts.lua's own login round (its claim, its question): run at each login of an account's character.
	cl.altsLogin = {}
	for i = before + 1, #(cl.listeners.LOGIN or {}) do cl.altsLogin[#cl.altsLogin + 1] = cl.listeners.LOGIN[i] end
	cl.Alts = c.Alts
	cl.legacy = opts.legacy
	return cl
end

-- One player's account: db account-wide, rdb one per ruleset; one character online at a time.
local function NewAccount() return { db = { chatRooms = true, addonChat = true, myCharacters = {} }, rdbs = {}, chars = {} } end
local function AddChar(w, acct, full, guild, rank)
	acct.chars[Key(full)] = { full = full, guild = guild, rank = rank or 3 }
	acct.db.myCharacters[full:lower()] = true
	w.members[guild] = w.members[guild] or {}
	table.insert(w.members[guild], full)
	w.offline = w.offline or {}
	w.offline[Key(full)] = { guild = guild, rank = rank or 3 }
	w:RefreshRosters()
end
local function Logout(w, acct)
	local cl = acct.current
	if not cl then return end
	cl.online = false
	for i = #w.clients, 1, -1 do if w.clients[i] == cl then table.remove(w.clients, i) end end
	for i = #w.timers, 1, -1 do if w.timers[i].cl == cl then table.remove(w.timers, i) end end
	w.byKey[cl.key] = nil
	local ch = acct.chars[cl.key]
	if ch.guild then table.insert(w.members[ch.guild], ch.full) end
	acct.current = nil
	w:RefreshRosters()
end
local function Login(w, acct, full, opts)
	Logout(w, acct)
	local ch = assert(acct.chars[Key(full)], full)
	local list = w.members[ch.guild] or {}
	for i = #list, 1, -1 do if list[i] == ch.full then table.remove(list, i) end end
	local family = ns.ForeverFamily(RealmOf(ch.full))
	acct.rdbs[family] = acct.rdbs[family] or {}
	local cl = MakeClient(w, ch.full, { guild = ch.guild, rank = ch.rank, db = acct.db, rdb = acct.rdbs[family], legacy = opts and opts.legacy })
	acct.current = cl
	for _, fn in ipairs(cl.altsLogin) do w:As(cl, fn) end
	-- (Within a few minutes of a login a client has heard every Church presence that reaches it: the
	-- keepers' every KEEPER_EVERY, over GUILD and the channel.)
	w:Presence()
	return cl
end

local function Join(w, guild, name)
	w.members[guild] = w.members[guild] or {}
	table.insert(w.members[guild], name)
	w:RefreshRosters()
end
local function StateOf(w, k, recruit, by) return (w:As(k, k.Count.StateOf, Key(recruit) .. ":" .. Key(by))) end
local function Joins(w, k, who) return w:As(k, k.Count.Own, Key(who), "a").joins end
local function Score(w, k, who) return (w:As(k, k.Count.Score, Key(who), "a")) end
local function Tenth(v) return math.floor(v * 10 + 0.5) / 10 end
local function RRJoins(w, k, who)
	local _, byKey = w:As(k, k.RR.Ranking, "a")
	local a = byKey and byKey[Key(who)]
	return a and a.joins or 0
end
local function Fresh(w, list) for _, k in ipairs(list) do w:As(k, k.Count.Changed) end end
-- Every keeper asks the others for a catch-up, until nothing moves.
local function Converge(w, keepers, rounds)
	for _ = 1, rounds or 4 do
		for _, k in ipairs(keepers) do if k.online then w:As(k, k.Count.CatchUp, true) end end
		w:Run(200)
		w:Tick()
		w:Run(200)
	end
end
local function Slash(w, cl, text) return w:As(cl, cl.Alts.Slash, text) end
local function Printed(cl, text)
	for i = #cl.printed, 1, -1 do if cl.printed[i] == text then return true end end
	return false
end
local function LinkedOn(w, k, name)
	local g = (w:As(k, k.Alts.Group, name))
	if not g and k.Alts.GroupByGuildName then g = (w:As(k, k.Alts.GroupByGuildName, name)) end
	return g and g.main or nil
end
local function CountLinked(w, k, list)
	local n = 0
	for _, a in ipairs(list) do if LinkedOn(w, k, a) == MAIN then n = n + 1 end end
	return n
end
-- An alt logs in, is asked (Alts.ASK_AFTER) and says yes in the dialog; its claim goes at LOGIN_AFTER.
local function Confirm(w, acct, full)
	local cl = Login(w, acct, full)
	w:Run(16)
	local d = cl.dialogs[#cl.dialogs]
	local asked = d ~= nil and d.which == "OLYMPUS_ALT_CONFIRM"
	if asked then w:As(cl, cl.altPopup.OnAccept) end
	w:Run(60)
	return cl, asked
end
local function LastClaim(w, cl)
	for i = #w.sent, 1, -1 do
		local e = w.sent[i]
		if e.from == cl and e.msg:sub(1, 3) == "AL~" then return e.msg end
	end
end
local function Named(claim)
	local list = {}
	for n in tostring(claim):match("~([^~]*)$"):gmatch("[^,]+") do list[#list + 1] = n end
	return list
end

-- Corvin Ashdale (an Apostle, the master of Olympus Ember) and his characters.
local A = {
	flint = "Ardo Flint-" .. R1, gale = "Ardo Gale-" .. R2, brook = "Ardo Brook-" .. R2, crest = "Ardo Crest-" .. R3,
	dune = "Ardo Dune-" .. R3, frost = "Ardo Frost-" .. R2, glen = "Ardo Glen-" .. R3, heath = "Ardo Heath-" .. R1,
	marsh = "Ardo Marsh-" .. R2, -- a ninth character of his, never linked
}
local EIGHT = { "flint", "gale", "brook", "crest", "dune", "frost", "glen", "heath" }

---------------------------------------------------------------------------
-- Linking: the steps the README gives, the wire, /reload and relog
---------------------------------------------------------------------------

test("1.6.0 Church alts: eight alts on three sub-realms linked by their plain names; a ninth offered before the last yes, and one on the other ruleset, refused; the claim names all eight to keepers of both versions; /reload and relog keep them", function()
	local w = World.New({ apostles = { MAIN, "Eda Marsh-" .. R2, "Dara Holt-" .. R3 } })
	local eda = MakeClient(w, "Eda Marsh-" .. R2, { guild = G1 })
	local dara = MakeClient(w, "Dara Holt-" .. R3, { guild = G2, legacy = true })
	local acct = NewAccount()
	AddChar(w, acct, MAIN, G1, 0)
	local guilds = { G1, G1, G2, G2, G2, G1, G3, G1 }
	local alts = {}
	for i, n in ipairs(EIGHT) do alts[i] = A[n]; AddChar(w, acct, A[n], guilds[i]) end
	local OTHER = "Ardo Rook-" .. RP
	AddChar(w, acct, OTHER, "Olympus Storm")
	AddChar(w, acct, A.marsh, G1)
	w:Run(60)
	w:Presence()

	-- /oly alt add First Surname on the main for each, all before any yes: the ninth too (an offer is
	-- no link), and the character on the other ruleset by its full name.
	local sm = Login(w, acct, MAIN)
	for _, a in ipairs(alts) do eq(Slash(w, sm, "add " .. Plain(a)), true, a) end
	eq(Slash(w, sm, "add " .. Plain(A.marsh)), true, "the ninth offered")
	eq(Slash(w, sm, "add " .. OTHER), true)
	for _, a in ipairs(alts) do
		local _, asked = Confirm(w, acct, a)
		eq(asked, true, "asked on " .. a)
		eq(acct.db.alts.links[a:lower()] ~= nil, true, "linked: " .. a)
	end
	local other, askedOther = Confirm(w, acct, OTHER)
	eq(askedOther, true)
	eq(Printed(other, ns.L.ALT_OTHER_CENSUS), true, "another ruleset is another census")
	local ninth, askedNinth = Confirm(w, acct, A.marsh)
	eq(askedNinth, true)
	eq(Printed(ninth, ns.L.ALT_FULL:format(8)), true, "the ninth yes is refused")
	local links = 0
	for _ in pairs(acct.db.alts.links) do links = links + 1 end
	eq(links, 8)
	sm = Login(w, acct, MAIN)
	eq(Slash(w, sm, "add Ardo Tenth"), false)
	eq(Printed(sm, ns.L.ALT_FULL:format(8)), true)

	-- The main's claim, at his login: all eight in one message, every name with its sub-realm (it fits).
	w:Run(61)
	local claim = LastClaim(w, sm)
	eq(#claim <= 250, true, "one message")
	local named = Named(claim)
	eq(#named, 8, claim)
	local short = {}
	for _, n in ipairs(named) do if not n:find("-", 1, true) then short[#short + 1] = n end end
	table.sort(short)
	eq(table.concat(short, ","), "Ardo Flint,Ardo Heath", "short on the main's own sub-realm, the others with theirs")
	eq(#w:As(sm, sm.Alts.MyGroup), 9)
	eq(next(acct.db.alts.offers), nil, "no offer left waiting")
	eq(CountLinked(w, eda, alts), 8, "a 1.6.0 keeper links all eight")
	eq(CountLinked(w, dara, alts), 8, "a 1.5.9 keeper too: the claim fits with its sub-realms")
	eq(LinkedOn(w, eda, A.marsh), nil)

	-- /reload on the main (a fresh session over the same saved variables), a relog of an alt, and a
	-- keeper's own /reload (its claims are saved, rdb.altClaims; its Alts.lua anew).
	sm = Login(w, acct, MAIN)
	w:Run(61)
	eq(#w:As(sm, sm.Alts.MyGroup), 9, "after /reload")
	local gale = Login(w, acct, A.gale)
	w:Run(61)
	eq(#gale.dialogs, 0, "a relogged alt is not asked again")
	eq(LastClaim(w, gale):match("~([^~]*)$"), MAIN, "its claim names its main")
	local saved = eda.ns.rdb.altClaims
	w:As(eda, function() assert(loadfile(ROOT .. "Olympus/Alts.lua"))("Olympus", eda.ns) end)
	eda.Alts = eda.ns.Alts
	eq(eda.ns.rdb.altClaims, saved)
	eq(CountLinked(w, eda, alts), 8, "after the keeper's /reload")
end)

test("1.6.0 Church alts: eight alts with long names, all on other sub-realms: the claim names all eight in one message, a 1.6.0 client links all eight, a 1.5.9 client those that kept their sub-realm", function()
	local w = World.New({ apostles = { MAIN, "Eda Marsh-" .. R2, "Dara Holt-" .. R3 } })
	local eda = MakeClient(w, "Eda Marsh-" .. R2, { guild = G1 })
	local dara = MakeClient(w, "Dara Holt-" .. R3, { guild = G2, legacy = true })
	local acct = NewAccount()
	AddChar(w, acct, MAIN, G1, 0)
	local alts = { "Wynn Copperfield-" .. R2, "Wynn Ravenscroft-" .. R3, "Wynn Hollowmere-" .. R2, "Wynn Kettleburn-" .. R3,
		"Wynn Stonebridge-" .. R2, "Wynn Ashworth-" .. R3, "Wynn Duskwater-" .. R2, "Wynn Millbrook-" .. R3 }
	for _, a in ipairs(alts) do AddChar(w, acct, a, "Olympus Ironwood Keep") end
	w:Run(60)
	local sm = Login(w, acct, MAIN)
	for _, a in ipairs(alts) do eq(Slash(w, sm, "add " .. Plain(a)), true, a) end
	for _, a in ipairs(alts) do Confirm(w, acct, a) end
	sm = Login(w, acct, MAIN)
	w:Run(61)
	local claim = LastClaim(w, sm)
	eq(#claim <= 250, true, "one message")
	local named, realms = Named(claim), 0
	for _, n in ipairs(named) do if n:find("-", 1, true) then realms = realms + 1 end end
	eq(#named, 8, claim)
	eq(realms < 8, true, "the last ones plain")
	eq(CountLinked(w, eda, alts), 8, "1.6.0: each plain name found by that alt's own claim")
	eq(CountLinked(w, dara, alts), realms, "1.5.9: the names with their sub-realm")
end)

-- The groups a client holds (Alts.StatusLine's count) and the claims it keeps, by key.
local function GroupsOn(w, k) return tonumber((w:As(k, k.Alts.StatusLine)):match("^(%d+) players linked here")) end
local function ClaimKeys(k)
	local list = {}
	for key in pairs(k.ns.rdb.altClaims or {}) do list[#list + 1] = key end
	table.sort(list)
	return table.concat(list, ",")
end

-- WoW: Forever stamps a guildmate's word over GUILD with the reader's own sub-realm (World.New's stamp:
-- Comm.PeerRealm, Layers.lua, measured), and a Church group's claims go over GUILD too (Alts.Send). Filed
-- under that stamp, each guild copy was a second claimant beside the claim's channel copy at a guildmate
-- on another sub-realm: a phantom group of the main and the alts that share his sub-realm (the census's
-- total one short for each of them in the guild, Alts.Duplicates), none found by a plain name from the
-- guild log (GroupByGuildName), and the plain names of an overflowing claim each matched two claims, so a
-- keeper there linked five alts of eight. Fails before: two groups, four duplicates, 5 of 8.
test("1.6.0 Church alts: a Church group's claims over GUILD, stamped with each reader's own sub-realm, are filed under the sub-realm each hello named: one group counted once at guildmates on other sub-realms, all eight of an overflowing claim linked; a guild copy whose hello is not heard is left to the other routes", function()
	-- Corvin and Ardo Flint on Realm1, Ardo Gale on Realm2, Ardo Crest on Realm3, all in Olympus Ember; there
	-- Eda (a keeper) and Wren on Realm2, Tobin on Realm3.
	local w = World.New({ apostles = { MAIN, "Eda Marsh-" .. R2 }, stamp = true })
	local eda = MakeClient(w, "Eda Marsh-" .. R2, { guild = G1 })
	local wren = MakeClient(w, "Wren Hollow-" .. R2, { guild = G1 })
	local tobin = MakeClient(w, "Tobin Reed-" .. R3, { guild = G1 })
	local acct = NewAccount()
	local three = { A.flint, A.gale, A.crest }
	AddChar(w, acct, MAIN, G1, 0)
	for _, a in ipairs(three) do AddChar(w, acct, a, G1) end
	w:Run(60)
	w:Presence()
	local sm = Login(w, acct, MAIN)
	for _, a in ipairs(three) do Slash(w, sm, "add " .. Plain(a)) end
	for _, a in ipairs(three) do Confirm(w, acct, a) end
	sm = Login(w, acct, MAIN)
	w:Run(61)
	Logout(w, acct)
	w:Run(30)
	local want = { MAIN:lower(), A.crest:lower(), A.flint:lower(), A.gale:lower() }
	table.sort(want)
	want = table.concat(want, ",")
	for _, k in ipairs({ eda, wren, tobin }) do
		eq(ClaimKeys(k), want, "each claim under its own sub-realm, on " .. k.name)
		eq(GroupsOn(w, k), 1, "one group on " .. k.name)
		eq(w:As(k, k.Alts.Duplicates, { [G1:lower()] = true }), 3, "four characters in Olympus Ember, one player, on " .. k.name)
		for _, name in ipairs({ "Ardo Flint", "Ardo Gale", "Ardo Crest", Plain(MAIN) }) do
			local g = w:As(k, k.Alts.GroupByGuildName, name)
			eq(g and g.main, MAIN, name .. " by the guild log's plain name, on " .. k.name)
		end
	end
	-- A guild copy from a guildmate whose hello this client has not heard: nowhere to file it, left to the
	-- channel's copy (here lost: Forever's relays at their worst) and to his next guild copy, once his hello
	-- is heard. Ula joins Olympus Ember on Realm3 with no claim kept.
	local ula = MakeClient(w, "Ula Fenn-" .. R3, { guild = G1 })
	w.lost = { AL = true }
	w.noHello = { [Key(A.flint)] = true }
	local flint = Login(w, acct, A.flint)
	w:Run(61)
	eq(LastClaim(w, flint):match("^AL~%d+~(%u)~"), "A", "its claim went out")
	eq(ClaimKeys(ula), "", "nothing filed under the reader's own sub-realm")
	w.noHello = nil
	w:As(flint, flint.Alts.Send, true)
	w:Run(1)
	eq(ClaimKeys(ula), A.flint:lower(), "his next guild copy, under the sub-realm his hello named")

	-- An overflowing claim: eight alts with long names on Realm3, four of them in Eda's guild, the main in
	-- Olympus Vale. Its last four names travel plain (Wire); each is found by that alt's one claim.
	local w2 = World.New({ apostles = { MAIN, "Eda Marsh-" .. R2 }, stamp = true })
	local eda2 = MakeClient(w2, "Eda Marsh-" .. R2, { guild = G1 })
	local acct2 = NewAccount()
	AddChar(w2, acct2, MAIN, G2, 0)
	local alts = { "Wynn Copperfield-" .. R3, "Wynn Ravenscroft-" .. R3, "Wynn Hollowmere-" .. R3, "Wynn Kettleburn-" .. R3,
		"Wynn Stonebridge-" .. R3, "Wynn Ashworth-" .. R3, "Wynn Duskwater-" .. R3, "Wynn Millbrook-" .. R3 }
	for i, a in ipairs(alts) do AddChar(w2, acct2, a, i % 2 == 0 and G1 or "Olympus Ironwood Keep") end
	w2:Run(60)
	local sm2 = Login(w2, acct2, MAIN)
	for _, a in ipairs(alts) do Slash(w2, sm2, "add " .. Plain(a)) end
	for _, a in ipairs(alts) do Confirm(w2, acct2, a) end
	sm2 = Login(w2, acct2, MAIN)
	w2:Run(61)
	local named = Named(LastClaim(w2, sm2))
	local plain = 0
	for _, n in ipairs(named) do if not n:find("-", 1, true) then plain = plain + 1 end end
	eq(#named, 8)
	eq(plain > 0, true, "some names plain")
	eq(CountLinked(w2, eda2, alts), 8, "all eight linked at a keeper on another sub-realm")
	eq(GroupsOn(w2, eda2), 1)
end)

---------------------------------------------------------------------------
-- The credit: an Apostle main, keepers of both versions, witnesses in three guilds
---------------------------------------------------------------------------

-- The world: the keepers Eda (1.6.0, the main's guild), Bera (1.6.0), Dara (1.5.9, the main's guild) and
-- Cass (1.5.9); the witnesses Wren (Olympus Ember), Tobin (Olympus Vale) and Ola (an officer of Olympus
-- Dawn, whom the census vouches for). Ardo Frost was named a missionary under the main before 1.6.0.
-- opts: noEda (no other 1.6.0 keeper in the main's guild), keepersAway (none at all there), officers
-- (Ardo Heath and Ardo Marsh officers of Olympus Ember), lost (no alt claim reaches anyone on the channel).
local function ChurchWorld(opts)
	opts = opts or {}
	local apostles = { MAIN, "Bera Stone-" .. R3, "Dara Holt-" .. R3, "Cass Vale-" .. R1 }
	if not opts.noEda then table.insert(apostles, 2, "Eda Marsh-" .. R2) end
	local w = World.New({ apostles = apostles })
	if opts.lost then w.lost = { AL = true } end
	local K = {}
	local away = opts.keepersAway
	if not opts.noEda then K.eda = MakeClient(w, "Eda Marsh-" .. R2, { guild = away and G2 or G1 }) end
	K.bera = MakeClient(w, "Bera Stone-" .. R3, { guild = G2 })
	K.dara = MakeClient(w, "Dara Holt-" .. R3, { guild = away and G3 or G1, legacy = true })
	K.cass = MakeClient(w, "Cass Vale-" .. R1, { guild = G3, legacy = true })
	local W = {
		wren = MakeClient(w, "Wren Hollow-" .. R2, { guild = G1 }),
		tobin = MakeClient(w, "Tobin Reed-" .. R1, { guild = G2 }),
		ola = MakeClient(w, "Ola Pike-" .. R2, { guild = G3, rank = 1 }),
	}
	local acct = NewAccount()
	AddChar(w, acct, MAIN, G1, 0)
	local guilds = { flint = G1, gale = G1, brook = G2, crest = G2, dune = G2, frost = G1, glen = G3, heath = G1, marsh = G1 }
	for n, full in pairs(A) do
		AddChar(w, acct, full, guilds[n], (opts.officers and (n == "heath" or n == "marsh")) and 1 or 3)
	end
	w:Presence()
	local sm = Login(w, acct, MAIN)
	w:Act(sm, sm.Church.NameMissionary, Plain(A.frost))
	w:Run(8 * 3600)
	w:Presence()
	return w, K, W, acct
end
local function Keepers(K)
	local out = {}
	for _, n in ipairs({ "eda", "bera", "dara", "cass" }) do if K[n] then out[#out + 1] = K[n] end end
	return out
end
-- Links the alts as the README says: the offers on the main, a yes on each alt, the main again.
local function LinkAll(w, acct, names)
	local sm = Login(w, acct, MAIN)
	for _, n in ipairs(names) do Slash(w, sm, "add " .. Plain(A[n])) end
	for _, n in ipairs(names) do Confirm(w, acct, A[n]) end
	sm = Login(w, acct, MAIN)
	w:Run(61)
	return sm
end
-- An alt's session: it invites; the recruit joins ten minutes later (unless joinLater); the guild's
-- addons read the log. short: the log names the inviter plain.
local function Recruit(w, acct, alt, guild, recruit, opts)
	opts = opts or {}
	local cl = Login(w, acct, alt)
	w:Run(61)
	w:LogEvent(guild, "invite", opts.short and Plain(alt) or alt, recruit, 0)
	if not opts.joinLater then
		w:Run(600)
		w:LogEvent(guild, "join", recruit, nil, 0)
		Join(w, guild, recruit)
	end
	w:Run(301)
	w:Tick()
	w:Run(30)
	return cl
end
local function Twice(w, list)
	for _, k in ipairs(list) do
		local per = {}
		for id, st in pairs(w:As(k, k.Count.Credits).states) do
			if st == "credited" then local x = id:match("^([^:]+):"); per[x] = (per[x] or 0) + 1 end
		end
		for x, n in pairs(per) do eq(n, 1, k.name .. ": credited twice: " .. x) end
	end
end

test("1.6.0 Church alts: the recruits of linked alts in three guilds count once for the Apostle main on every keeper; a link after the recruit, a link removed, an unlinked character, an alt that is a missionary itself", function()
	local w, K, W, acct = ChurchWorld()
	local keepers = Keepers(K)
	local seven = { "flint", "gale", "brook", "crest", "frost", "glen", "heath" }
	LinkAll(w, acct, seven)
	for _, k in ipairs(keepers) do
		local list = {}
		for _, n in ipairs(seven) do list[#list + 1] = A[n] end
		eq(CountLinked(w, k, list), 7, "the links on " .. k.name)
	end
	Logout(w, acct)
	w:Run(700)

	-- Ardo Dune recruits before her link (Tobin sees it); the linked alts recruit; Ardo Marsh, never linked.
	Recruit(w, acct, A.dune, G2, "Reed Recruit-" .. R1, { short = true })
	eq(StateOf(w, K.bera, "Reed Recruit", MAIN), nil, "not linked yet: nothing for the main")
	Recruit(w, acct, A.flint, G1, "Nova Recruit-" .. R2, { short = true })
	Recruit(w, acct, A.gale, G1, "Lark Recruit-" .. R3)
	Recruit(w, acct, A.brook, G2, "Moth Recruit-" .. R1, { short = true })
	Recruit(w, acct, A.crest, G2, "Pike Recruit-" .. R2)
	Recruit(w, acct, A.frost, G1, "Sage Recruit-" .. R3, { short = true })
	Recruit(w, acct, A.glen, G3, "Tern Recruit-" .. R1, { short = true })
	Recruit(w, acct, A.marsh, G1, "Yarrow Recruit-" .. R1, { short = true })
	Logout(w, acct)
	w:Run(700)
	for _, r in ipairs({ "Nova", "Lark", "Moth", "Pike", "Tern" }) do
		for _, k in ipairs(keepers) do eq(StateOf(w, k, r .. " Recruit", MAIN), "credited", r .. " on " .. k.name) end
	end
	for _, k in ipairs(keepers) do
		eq(StateOf(w, k, "Yarrow Recruit", MAIN), nil, "an unlinked character's recruit, on " .. k.name)
		-- The alt that is a missionary itself: 1.6.0 keepers give her recruit to the main, 1.5.9 ones to her.
		eq(StateOf(w, k, "Sage Recruit", MAIN), k.legacy and "taken" or "credited", "Sage on " .. k.name)
		eq(StateOf(w, k, "Sage Recruit", A.frost), k.legacy and "credited" or "taken", "Sage (the missionary) on " .. k.name)
	end

	-- Ardo Dune's link, the main's claim with eight, a later read: her earlier recruit counts now.
	local sm = Login(w, acct, MAIN)
	Slash(w, sm, "add " .. Plain(A.dune))
	Confirm(w, acct, A.dune)
	w:Run(301)
	w:Tick()
	sm = Login(w, acct, MAIN)
	w:Run(61)
	w:Run(301)
	w:Tick()
	eq(StateOf(w, K.bera, "Reed Recruit", MAIN), "credited", "linked after her recruit, a later read")
	eq(StateOf(w, K.eda, "Reed Recruit", MAIN), "credited")

	-- The main online: the catch-ups. Every keeper counts each recruit once; the main's own Mine page.
	local all = { sm, K.eda, K.bera, K.dara, K.cass }
	Converge(w, all, 4)
	Fresh(w, all)
	for _, k in ipairs({ sm, K.eda, K.bera }) do
		eq(Joins(w, k, MAIN), 7, "1.6.0, joins on " .. k.name)
		eq(Tenth(Score(w, k, MAIN)), 70, "1.6.0, score on " .. k.name)
		eq(Joins(w, k, A.frost), 0)
	end
	for _, k in ipairs({ K.dara, K.cass }) do
		eq(Joins(w, k, MAIN), 6, "1.5.9, joins on " .. k.name)
		eq(Tenth(Score(w, k, MAIN)), 62.5, "1.5.9: 60, and a quarter of his missionary's 10, on " .. k.name)
		eq(Joins(w, k, A.frost), 1)
	end
	local j
	for _, l in ipairs(w:As(sm, sm.Count.DetailView, MAIN, "a") or {}) do if l[1] == "j" then j = l[2] end end
	eq(j, 7, "the main's Mine page")
	-- The ranking for everyone lists each character on its own (the main's request was his score).
	for _, k in ipairs(keepers) do
		for _, n in ipairs({ "flint", "gale", "brook", "crest", "dune", "frost", "glen", "marsh" }) do
			eq(RRJoins(w, k, A[n]), 1, "Everyone, " .. A[n] .. " on " .. k.name)
		end
		eq(RRJoins(w, k, MAIN), 0)
	end

	-- Ardo Glen's link removed on the main: her recruit before stays his; one after is nobody's.
	sm = Login(w, acct, MAIN)
	eq(Slash(w, sm, "remove " .. Plain(A.glen)), true)
	w:Run(61)
	eq(LinkedOn(w, K.bera, A.glen), nil)
	eq(LinkedOn(w, W.ola, A.glen), nil)
	Recruit(w, acct, A.glen, G3, "Vale Recruit-" .. R2, { short = true })
	Logout(w, acct)
	w:Run(700)
	sm = Login(w, acct, MAIN)
	all[1] = sm
	Converge(w, all, 3)
	Fresh(w, all)
	eq(StateOf(w, K.bera, "Vale Recruit", MAIN), nil)
	eq(StateOf(w, K.eda, "Vale Recruit", MAIN), nil)
	eq(StateOf(w, K.bera, "Tern Recruit", MAIN), "credited")
	for _, k in ipairs({ sm, K.eda, K.bera }) do eq(Joins(w, k, MAIN), 7, "final, " .. k.name) end
	for _, k in ipairs({ K.dara, K.cass }) do eq(Joins(w, k, MAIN), 6, "final, " .. k.name) end
	Twice(w, all)
end)

test("1.6.0 Church alts: a character of the main's own account is no witness: a linked alt's read leaves the recruit pending, an unlinked character's read reports nothing", function()
	-- No keeper in the main's guild (a keeper's own read of the log is a witness of its own); Ardo Heath
	-- and Ardo Marsh are officers there, whom the census vouches for to keepers elsewhere.
	local w, K, W, acct = ChurchWorld({ keepersAway = true, officers = true })
	W.wren.online = false
	LinkAll(w, acct, EIGHT)
	Logout(w, acct)
	w:Run(700)
	-- Ardo Flint invites and logs off before the join; a linked alt of the account reads the join first.
	Recruit(w, acct, A.flint, G1, "Wisp Recruit-" .. R3, { short = true, joinLater = true })
	Logout(w, acct)
	w:LogEvent(G1, "join", "Wisp Recruit-" .. R3, nil, 0)
	Join(w, G1, "Wisp Recruit-" .. R3)
	Recruit(w, acct, A.heath, G1, "Nobody Here-" .. R1, { joinLater = true })
	Logout(w, acct)
	w:Run(700)
	eq(StateOf(w, K.eda, "Wisp Recruit", MAIN), "pending", "the account's linked alt: the recruiter's own side")
	Converge(w, Keepers(K), 2)
	for _, k in ipairs(Keepers(K)) do eq(StateOf(w, k, "Wisp Recruit", MAIN), "pending", "after the catch-ups, on " .. k.name) end
	-- Again, the account's unlinked character the first to read the join: with the inviter plain in the
	-- log, then with his sub-realm.
	for _, short in ipairs({ true, false }) do
		local recruit = (short and "Ivy" or "Holly") .. " Recruit-" .. R3
		Recruit(w, acct, A.flint, G1, recruit, { short = short, joinLater = true })
		Logout(w, acct)
		w:LogEvent(G1, "join", recruit, nil, 0)
		Join(w, G1, recruit)
		local marsh = Login(w, acct, A.marsh)
		w:Run(301)
		w:Tick()
		w:Run(30)
		for _, kind in ipairs({ "NV", "NE" }) do
			for _, e in ipairs(w:Sent(marsh, kind, "WHISPER", "w")) do
				assert(not e.msg:find(Plain(recruit), 1, true), kind .. " from the unlinked character: " .. e.msg)
			end
		end
		Logout(w, acct)
		w:Run(700)
		eq(StateOf(w, K.eda, Plain(recruit), MAIN) ~= "credited", true, recruit)
		eq(StateOf(w, K.bera, Plain(recruit), MAIN) ~= "credited", true, recruit)
	end
end)

test("1.6.0 Church alts: with no other 1.6.0 keeper in the main's guild, a guildmate's word waits for the main, then counts", function()
	local w, K, W, acct = ChurchWorld({ noEda = true })
	LinkAll(w, acct, EIGHT)
	Logout(w, acct)
	w:Run(700)
	Recruit(w, acct, A.flint, G1, "Nova Recruit-" .. R2, { short = true })
	Logout(w, acct)
	w:Run(700)
	eq(StateOf(w, K.bera, "Nova Recruit", MAIN), "pending", "the alt's own word; nobody here can vouch for Wren")
	w:Run(4 * 3600)
	w:Tick()
	eq(StateOf(w, K.bera, "Nova Recruit", MAIN), "pending", "four hours later")
	local sm = Login(w, acct, MAIN)
	w:Run(30)
	w:Tick()
	w:Run(60)
	Converge(w, { sm, K.bera, K.dara, K.cass }, 2)
	Fresh(w, { sm, K.bera, K.dara, K.cass })
	eq(StateOf(w, sm, "Nova Recruit", MAIN), "credited", "the main's own keeper vouches for his guildmate")
	eq(StateOf(w, K.bera, "Nova Recruit", MAIN), "credited")
	eq(StateOf(w, K.dara, "Nova Recruit", MAIN), "credited", "a 1.5.9 keeper, by the catch-up")
end)

test("1.6.0 Church alts: a missionary main's linked alts on other sub-realms count for her on every keeper, her Apostle takes his quarter, her Mine page shows them", function()
	local w, K, W = ChurchWorld()
	local facct = NewAccount()
	local FAYE = "Faye Lumen-" .. R2
	AddChar(w, facct, FAYE, G2)
	AddChar(w, facct, "Faye Glow-" .. R1, G2)
	AddChar(w, facct, "Faye Ashwood-" .. R3, G1)
	local fm = Login(w, facct, FAYE)
	w:Act(K.bera, K.bera.Church.NameMissionary, "Faye Lumen")
	w:Run(8 * 3600)
	w:Presence()
	Slash(w, fm, "add Faye Glow")
	Slash(w, fm, "add Faye Ashwood")
	Confirm(w, facct, "Faye Glow-" .. R1)
	Confirm(w, facct, "Faye Ashwood-" .. R3)
	fm = Login(w, facct, FAYE)
	w:Run(61)
	Logout(w, facct)
	w:Run(700)
	Recruit(w, facct, "Faye Glow-" .. R1, G2, "Opal Recruit-" .. R3, { short = true })
	Recruit(w, facct, "Faye Ashwood-" .. R3, G1, "Quartz Recruit-" .. R1)
	Logout(w, facct)
	w:Run(700)
	Converge(w, Keepers(K), 3)
	Fresh(w, Keepers(K))
	for _, k in ipairs(Keepers(K)) do
		eq(Joins(w, k, FAYE), 2, "joins on " .. k.name)
		local _, _, share = w:As(k, k.Count.Score, Key("Bera Stone"), "a")
		eq(Tenth(share), 5, "her Apostle's quarter on " .. k.name)
	end
	fm = Login(w, facct, FAYE)
	w:Run(30)
	w:Presence()
	eq(w:As(fm, fm.Count.Ask, "me", "a"), true)
	w:Run(30)
	w:Run(30)
	local j
	for _, l in ipairs(w:As(fm, fm.Count.DetailView, FAYE, "a") or {}) do if l[1] == "j" then j = l[2] end end
	eq(j, 2, "her Mine page")
end)

-- WoW: Forever's relays at their worst: no claim said on the channel reaches anyone (World.lost). The
-- claims go over GUILD and by whisper to the keepers online (Alts.Send), and a guildmate reports an
-- alt's pair on the alt's own claim (ChurchCount.Pair). A 1.5.9 keeper takes neither route: it gets the
-- 1.6.0 keepers' records in its catch-up.
test("1.6.0 Church alts: with no alt claim through the channel, the recruits of linked alts in three guilds still count once for the main on the keepers", function()
	local w, K, W, acct = ChurchWorld({ lost = true })
	local seven = { "flint", "gale", "brook", "crest", "frost", "glen", "heath" }
	LinkAll(w, acct, seven)
	local list = {}
	for _, n in ipairs(seven) do list[#list + 1] = A[n] end
	eq(CountLinked(w, K.eda, list), 7, "a 1.6.0 keeper holds every link: both claims by whisper")
	eq(CountLinked(w, K.bera, list), 7)
	eq(CountLinked(w, K.dara, list), 0, "a 1.5.9 keeper hears no claim")
	Logout(w, acct)
	w:Run(700)
	Recruit(w, acct, A.flint, G1, "Nova Recruit-" .. R2, { short = true })
	Recruit(w, acct, A.brook, G2, "Moth Recruit-" .. R1, { short = true })
	Recruit(w, acct, A.crest, G2, "Pike Recruit-" .. R2)
	Recruit(w, acct, A.glen, G3, "Tern Recruit-" .. R1, { short = true })
	Logout(w, acct)
	w:Run(700)
	for _, r in ipairs({ "Nova", "Moth", "Pike", "Tern" }) do
		eq(StateOf(w, K.eda, r .. " Recruit", MAIN), "credited", r .. " on Eda")
		eq(StateOf(w, K.bera, r .. " Recruit", MAIN), "credited", r .. " on Bera")
	end
	local sm = Login(w, acct, MAIN)
	local all = { sm, K.eda, K.bera, K.dara, K.cass }
	Converge(w, all, 4)
	Fresh(w, all)
	for _, k in ipairs(all) do eq(Joins(w, k, MAIN), 4, "joins on " .. k.name) end
	Twice(w, all)
end)

-- An alt that leaves its main on its own side (/oly alt remove <main> there) says so with a "-" claim.
-- Its Church role is none (the role was its main's), so that claim went on the channel alone, which
-- Forever's relays may lose at their worst (World.lost): the keepers, who hold a Church group's claims by
-- whisper, kept the link and credited its later recruits to its former main until his next claim. Fails
-- before: the keepers still link it after the removal, and its next recruit counts for the main.
test("1.6.0 Church alts: an alt that leaves its main on its own side says so over GUILD and to the keepers online, once: with no alt claim through the channel, the keepers drop the link at once and its next recruit is not its former main's", function()
	local w, K, W, acct = ChurchWorld({ lost = true })
	LinkAll(w, acct, { "flint", "brook", "crest" })
	-- The keepers hold both claims (by whisper); Tobin, her guildmate, her own claim alone (over GUILD), on
	-- which a witness reports her recruits (ChurchCount's ClaimedMain).
	for _, k in ipairs({ K.eda, K.bera }) do eq(LinkedOn(w, k, A.brook), MAIN, "linked before, on " .. k.name) end
	eq(w:As(W.tobin, W.tobin.Alts.ClaimedMain, A.brook), MAIN)
	Logout(w, acct)
	w:Run(700)
	-- Ardo Brook (Olympus Vale) takes herself out of the group.
	local brook = Login(w, acct, A.brook)
	w:Run(61)
	w:ClearSent()
	eq(Slash(w, brook, "remove " .. Plain(MAIN)), true)
	w:Run(61)
	for _, k in ipairs({ K.eda, K.bera }) do eq(LinkedOn(w, k, A.brook), nil, "dropped at once, on " .. k.name) end
	eq(w:As(W.tobin, W.tobin.Alts.ClaimedMain, A.brook), nil, "her guildmate too")
	eq(LinkedOn(w, K.eda, A.flint), MAIN, "the others stay")
	-- Her "-" claims by route (any session of hers).
	local function Withdrawals(dist)
		local n = 0
		for _, e in ipairs(w:Sent(nil, "AL", dist)) do
			if e.from.name == A.brook and e.msg:match("^AL~%d+~%-~") then n = n + 1 end
		end
		return n
	end
	eq(Withdrawals("CHANNEL"), 1)
	eq(Withdrawals("GUILD"), 1, "to her guild")
	local told = Withdrawals("WHISPER")
	eq(told > 0, true, "to the keepers online")
	-- Said once: not again in a later round (the minute's ticker, Alts.Send), nor at her next login.
	w:Run(brook.Alts.EVERY + 100)
	w:As(brook, brook.Alts.Send, false)
	w:Run(1)
	Recruit(w, acct, A.brook, G2, "Wolf Recruit-" .. R1, { short = true })
	eq(Withdrawals("CHANNEL"), 1, "once")
	eq(Withdrawals("GUILD"), 1, "once")
	eq(Withdrawals("WHISPER"), told, "once to each keeper")
	Logout(w, acct)
	w:Run(700)
	for _, k in ipairs({ K.eda, K.bera }) do eq(StateOf(w, k, "Wolf Recruit", MAIN), nil, "not the former main's, on " .. k.name) end
end)
