-- 1.2, the fights part: the honours' messages and verification (HonorsNet.lua), the profile's word (AP), and the
-- verified frames and marks on the unit frames and nameplates (Borders.lua, Nameplates.lua), on
-- the test world. Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
local N = World.NAMES

local function Read(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end
local function HN(w, c) return W3.M(w, c, "HonorsNet") end
local function Prof(w, c) return W3.M(w, c, "ArenaProfile") end
-- A logout and a login: the release client, its save came back (Arena.Persists). Where it did not
-- (a first session, the Forever beta) the King's letter waits in the Edit's list (honors-letter.lua).
local function Kept(w, c)
	w:Logout(c)
	w:Login(c)
	W3.Rules(w, c)
	return c
end

-- A title fight won by `winner` (a vacant global belt: he holds it), as its public arbiter's AE
-- reaches `to` (the core keeps the title fights: no companion needed).
local function Belt(w, cast, winner, loser, to)
	local e = table.concat({ "1", "Fzz" .. winner.short:sub(1, 1):lower(), cast.arbiter.ns.Arena.B36(w.clock - 600), "A", "1",
		cast.arbiter.ns.Arena.GK(winner.guid), winner.short, "-", cast.arbiter.ns.Arena.GK(loser.guid), loser.short, "-", "1:0", "A", "K", "3c",
		cast.arbiter.ns.Arena.GK(cast.arbiter.guid), "prtb" }, "~")
	for _, c in ipairs(to) do
		w:As(c, function() c.ns.Arena.Inject("CHANNEL", cast.arbiter.name, "AE~L1~" .. e) end)
	end
end

print("HonorsNet: the level race (IL)")

-- (1.2.1, the security review: one census row of anyone else's vouched for a claim, so a forged
-- report could win a place. Two senders of the claimant's guild are asked now: the second report.)
test("1.2 the fights part: the level race (the design: the first to 20, 40, 60): a level-up claim goes 60 s after, is kept unvouched until two census senders of his guild list him there, then takes the place after CONFIRM_AFTER; a later claim never takes it; the place never moves", function()
	local w, cast = W3.New({ more = { { "young", "Brisa Vale", { level = 19 } }, { "late", "Corin Ash", { level = 19 } },
		{ "reporter", "Dovan Quell" }, { "reporter2", "Elsa Thornby" } } })
	local young, viewer = cast.young, cast.spectator
	-- (The race starts at the 1.2 release, after the test world's clock: here, a day before it.)
	viewer.ns.HonorsNet.RACE_START = w.clock - 86400
	-- The weight rule's exemption: PLAYER_LEVEL_UP only where a milestone can still be reached.
	eq(w:Events(young, true).PLAYER_LEVEL_UP, true)
	eq(w:Events(viewer, true).PLAYER_LEVEL_UP, nil, "a level 60: none")
	w:Fire(young, "PLAYER_LEVEL_UP", 20)
	w:Run(59)
	eq(#w:Sent{ from = young, type = "IL" }, 0)
	w:Run(1)
	eq(#w:Sent{ from = young, type = "IL", dist = "CHANNEL" }, 1, "60 s after")
	local s = viewer.ns.HonorsNet.Store()
	local claim
	for _, c in pairs(s.claims) do claim = c end
	eq(claim.level, 20); eq(claim.vouched, false)
	eq(#(s.levels[20] or {}), 0, "unvouched: no place")
	-- The census: another sender's report of her guild, her at 20: one row, no proof (1.2.1).
	W3.Report(viewer, "Olympus Vale", cast.reporter, { { name = "Brisa Vale", level = 20, class = "MA" } })
	w:As(viewer, function() viewer.ns.Fire("DATA_CHANGED") end)
	eq(claim.vouched, false, "one census row")
	-- Her guild's second sender, in his turn: vouched.
	W3.Report(viewer, "Olympus Vale", cast.reporter2, { { name = "Brisa Vale", level = 20, class = "MA" } })
	w:As(viewer, function() viewer.ns.Fire("DATA_CHANGED") end)
	eq(claim.vouched, true)
	eq(#(s.levels[20] or {}), 0, "vouched, still waiting CONFIRM_AFTER")
	w:Run(viewer.ns.Honors.CONFIRM_AFTER + 2)
	eq(s.levels[20][1].name, young.name, "first to 20")
	-- Held by her on every viewer that holds the same facts: the bronze comet.
	local held = HN(w, viewer).Holdings(young.name, young.guid)
	eq(held[1].key, "level-race-20"); eq(held[1].art, "comet-bronze")
	-- A later claimant: vouched too, never the place.
	w:Fire(cast.late, "PLAYER_LEVEL_UP", 20)
	w:Run(61)
	W3.Report(viewer, "Olympus Ash", cast.reporter, { { name = "Corin Ash", level = 20, class = "WA" } })
	w:As(viewer, function() viewer.ns.Fire("DATA_CHANGED") end)
	W3.Report(viewer, "Olympus Ash", cast.reporter2, { { name = "Corin Ash", level = 20, class = "WA" } })
	w:As(viewer, function() viewer.ns.Fire("DATA_CHANGED") end)
	w:Run(viewer.ns.Honors.CONFIRM_AFTER + 2)
	eq(#s.levels[20], 1); eq(s.levels[20][1].name, young.name, "the place never moves")
	-- The claim's report is the census's alone: the claimant's own report vouches for nothing.
	local own = W3.Report(viewer, "Olympus Solo", cast.late, { { name = "Corin Ash", level = 40 } })
	w:Fire(cast.late, "PLAYER_LEVEL_UP", 40)
	w:Run(61)
	eq(#(s.levels[40] or {}), 0)
	for _, c in pairs(s.claims) do if c.level == 40 then eq(c.vouched, false, "his own report") end end
	own.top = nil
	W3.NoErrors(w)
end)

test("1.2 the fights part: IL is never sent once the milestone's place is known here, nor from a character past the last milestone; an IL whose gk the game names for someone else is refused", function()
	local w, cast = W3.New({ more = { { "young", "Brisa Vale", { level = 39 } } } })
	local young = cast.young
	local s = young.ns.HonorsNet.Store(true)
	s.levels[40] = { { guid = "Player-9-00000001", name = "Someone Else-Emberfall", t = 1, place = 1 } }
	w:Fire(young, "PLAYER_LEVEL_UP", 40)
	w:Run(3700)
	eq(#w:Sent{ from = young, type = "IL" }, 0, "the place is known: nothing sent")
	-- A claim naming another's gk (the game says that GUID is another character).
	local viewer = cast.spectator
	viewer.globals.GetPlayerInfoByGUID = function(guid) return "Mage", "MAGE", "Human", "Human", 2, "Other Person", "" end
	w:As(viewer, function() viewer.ns.Arena.Inject("CHANNEL", young.name, "IL~L1~" .. table.concat({ viewer.ns.Arena.GK(young.guid), "k", "0" }, "~")) end)
	eq(viewer.ns.HonorsNet.Stats().refused.gk, 1)
	W3.NoErrors(w)
end)

-- 1.2.1 (the stutter players reported, measured on the owner's PC): every census report heard ran
-- the whole level race inside the game's message event, and the race worked out every name of every
-- report for every claim waiting (a release client keeps 200 claims for 7 days): a fifth of a second
-- and more, about once a second. H.Vouched looks the claimant up in a listing of the census by name
-- now, built again only when the rows change; a census change or an IL looks at the claims at once
-- and the race runs RACE_SOON later, once for a burst; a claim waiting CONFIRM_AFTER has one re-check.

-- Our own guild's roster on c (as Roster.lua answers RankOf: by full name), fresh, `n` members.
local function Members(c, n)
	local R = { members = {}, byName = {}, snapshotAt = c.ns.Now() }
	for i = 1, n do
		local full = ("Rowan%d Pell-%s"):format(i, c.realm)
		R.members[i] = { full = full, level = 60 }
		R.byName[full] = 3
	end
	function R.Fresh() return R end
	function R.RankOf(name) return type(name) == "string" and R.byName[c.ns.FullName(name)] or nil end
	rawset(c.ns, "Roster", R)
	return R
end

test("1.2.1 the level race: a census change with 200 claims waiting and 150 guilds' reports works out under 2,000 names, the change and its race together (it was some 170,000 each report); a change that moved no row lists the census no new", function()
	local w, cast = W3.New()
	local viewer = cast.spectator
	local net = HN(w, viewer)
	viewer.ns.HonorsNet.RACE_START = w.clock - 86400
	Members(viewer, 1000)
	local s = net.Store(true)
	s.vouchRule = net.VOUCH_RULE
	for i = 1, 150 do
		local top = {}
		for j = 1, 5 do top[j] = { name = ("Tamsin%d Row%d"):format(j, i), level = 60, class = "WA" } end
		W3.Report(viewer, ("Olympus Row %d"):format(i), { short = ("Odell%d Row"):format(i), name = ("Odell%d Row-%s"):format(i, viewer.realm) }, top)
	end
	-- 200 claims heard this hour, nobody listing them.
	for i = 1, 200 do
		local name = ("Lark%d Brook-%s"):format(i, viewer.realm)
		s.claims[name:lower() .. ":20"] = { gk = ("3e8.%08x"):format(i), name = name, level = 20, t = w.clock - i, heardLocal = w.clock - i, vouched = false }
	end
	local real, n = viewer.ns.FullName, 0
	viewer.ns.FullName = function(...) n = n + 1 return real(...) end
	w:As(viewer, function() viewer.ns.Fire("DATA_CHANGED") end)
	w:Run(6)
	local first = n
	assert(first < 2000, "one census change and its race: " .. first .. " names worked out")
	-- Nothing moved in the census: no new listing, and only the race's own names.
	local builds = net.ListingBuilds()
	n = 0
	w:As(viewer, function() viewer.ns.Fire("DATA_CHANGED") end)
	eq(net.ListingBuilds(), builds, "the census as it was: its listing kept")
	assert(n < 400, "a change that moved no row: " .. n .. " names (our roster asked of each claim waiting)")
	viewer.ns.FullName = real
	for _, c in pairs(s.claims) do eq(c.vouched, false, "nobody lists them") end
	W3.NoErrors(w)
end)

test("1.2.1 the level race: a claim's vouch is what it was with the census looked up by name: two senders of his one guild, not him, at or above the level, within 24 hours; never his own report, a level below, a day off, two guilds, a guild off the network; the rows as they stand", function()
	local w, cast = W3.New({ more = { { "claimant", "Brisa Vale", { level = 19 } }, { "f1", "Dovan Quell" }, { "f2", "Elsa Thornby" } } })
	local viewer, who = cast.spectator, cast.claimant
	local net = HN(w, viewer)
	local WINDOW = net.VOUCH_WINDOW
	-- A claim of hers, the census emptied first (each case its own reports).
	local function Claim(level, heard)
		for k in pairs(viewer.rdb.guilds) do viewer.rdb.guilds[k] = nil end
		heard = heard or w.clock
		return { gk = "3e8.0000abcd", name = who.name, level = level, t = heard, heardLocal = heard, vouched = false }
	end
	local function Row(guild, reporter, level, name)
		return W3.Report(viewer, guild, reporter, { { name = "Corin Ash", level = 60, class = "WA" }, { name = name or who.short, level = level, class = "MA" } })
	end
	local function Senders(c, guild)
		local out = {}
		for k in pairs(c.by and c.by[guild] or {}) do out[#out + 1] = k end
		table.sort(out)
		return table.concat(out, ",")
	end
	-- Two senders of her guild, one after the other (each report replaces the last).
	local c = Claim(20)
	Row("Olympus Vale", cast.f1, 20)
	eq(net.Vouched(c), false, "one sender")
	Row("Olympus Vale", cast.f2, 20)
	eq(net.Vouched(c), true, "her guild's second sender")
	eq(Senders(c, "olympus vale"), "dovan quell,elsa thornby")
	-- Her own report: never her proof.
	c = Claim(40)
	Row("Olympus Solo", who, 40)
	eq(net.Vouched(c), false, "her own report")
	eq(next(c.by), nil)
	-- A level below the claim's.
	c = Claim(40)
	Row("Olympus Low", cast.f1, 39)
	Row("Olympus Low", cast.f2, 39)
	eq(net.Vouched(c), false, "listed below it")
	-- Reports a day and more after the claim; at the day's very end, yes.
	c = Claim(20, w.clock - WINDOW - 1)
	Row("Olympus Late", cast.f1, 20)
	Row("Olympus Late", cast.f2, 20)
	eq(net.Vouched(c), false, "a day off")
	c = Claim(20, w.clock - WINDOW)
	Row("Olympus Edge", cast.f1, 20)
	eq(net.Vouched(c), false)
	Row("Olympus Edge", cast.f2, 20)
	eq(net.Vouched(c), true, "within the day")
	-- Two guilds, one sender each.
	c = Claim(60)
	Row("Olympus East", cast.f1, 60)
	Row("Olympus West", cast.f2, 60)
	eq(net.Vouched(c), false, "two guilds")
	-- A guild off the network (Data.NetOff, the harness's census here): its rows say nothing while it is.
	local D = viewer.ns.Data
	local netOff = D.NetOff
	D.NetOff = function(g) return g == "Olympus Off" or netOff(g) end
	c = Claim(20)
	Row("Olympus Off", cast.f1, 20)
	eq(net.Vouched(c), false)
	Row("Olympus Off", cast.f2, 20)
	eq(net.Vouched(c), false, "off the network")
	D.NetOff = netOff
	eq(net.Vouched(c), false, "back: one sender in its row now")
	Row("Olympus Off", cast.f1, 20)
	eq(net.Vouched(c), true, "and the other one's next report")
	-- Her name however a report spells it (no realm, another case), and a row changed where it stands.
	c = Claim(40)
	Row("Olympus Case", cast.f1, 40, who.short:upper())
	eq(net.Vouched(c), false)
	eq(Senders(c, "olympus case"), "dovan quell", "her short name in capitals")
	local r = Row("Olympus Case", cast.f2, 39, who.name)
	eq(net.Vouched(c), false, "39")
	r.top[2].level = 40
	eq(net.Vouched(c), true, "the row as it stands")
	-- Forever's split names: "First-Surname" is hers only where this client splits names.
	c = Claim(60)
	Row("Olympus Split", cast.f1, 60, "Brisa-Vale")
	Row("Olympus Split", cast.f2, 60, "Brisa-Vale")
	eq(net.Vouched(c), false, "not split: Brisa")
	eq(next(c.by), nil)
	viewer.ns.splitNames = true
	eq(net.Vouched(c), false, "split: Brisa Vale, one sender in the row")
	Row("Olympus Split", cast.f1, 60, "Brisa-Vale")
	eq(net.Vouched(c), true, "and the other one")
	viewer.ns.splitNames = nil
	W3.NoErrors(w)
end)

test("1.2.1 the level race: a burst of census changes (50 in a second) looks at the claims at once and runs the race once, RACE_SOON later; an IL runs none in its handler; each report with a DATA_CHANGED of its own, every sender of the burst is seen (the census's own burst, one DATA_CHANGED for it: the next test)", function()
	local w, cast = W3.New({ more = { { "young", "Brisa Vale", { level = 19 } } } })
	local viewer, young = cast.spectator, cast.young
	local net = HN(w, viewer)
	viewer.ns.HonorsNet.RACE_START = w.clock - 86400
	local runs = 0
	local race = viewer.ns.HonorsNet.RunRace
	viewer.ns.HonorsNet.RunRace = function(...) runs = runs + 1 return race(...) end
	w:Fire(young, "PLAYER_LEVEL_UP", 20)
	w:Run(60)
	local s = net.Store()
	local claim
	for _, c in pairs(s.claims) do claim = c end
	assert(claim, "her claim")
	eq(runs, 0, "no race inside the IL's handler")
	w:Run(net.RACE_SOON)
	eq(runs, 1, "the race RACE_SOON after")
	-- 50 reports of her guild within a second, each from another of its senders.
	runs = 0
	for i = 1, 50 do
		W3.Report(viewer, "Olympus Vale", { short = ("Hollis%d Quell"):format(i), name = ("Hollis%d Quell-%s"):format(i, viewer.realm) },
			{ { name = young.name, level = 20, class = "MA" } })
		w:As(viewer, function() viewer.ns.Fire("DATA_CHANGED") end)
		w:Run(0.02)
	end
	eq(runs, 0, "none inside the census's handler")
	eq(claim.vouched, true, "her guild's senders seen as they came")
	local kept = {}
	for k in pairs(claim.by["olympus vale"]) do kept[#kept + 1] = k end
	table.sort(kept)
	eq(table.concat(kept, ","), "hollis1 quell,hollis2 quell", "the first two (each replaced within the second): vouched, the rest not looked for")
	w:Run(net.RACE_SOON)
	eq(runs, 1, "one race for the burst")
	w:Run(viewer.ns.Honors.CONFIRM_AFTER)
	eq(s.levels[20] and s.levels[20][1] and s.levels[20][1].name, young.name, "first to 20")
	W3.NoErrors(w)
end)

test("1.2.1 the level race: a vouched claim waiting CONFIRM_AFTER has one re-check, when it is old enough (100 races leave one, not 100 timers of 601 s); the place then", function()
	local w, cast = W3.New({ more = { { "young", "Brisa Vale", { level = 20 } } } })
	local viewer, young = cast.spectator, cast.young
	local net = HN(w, viewer)
	viewer.ns.HonorsNet.RACE_START = w.clock - 86400
	local s = net.Store(true)
	s.vouchRule = net.VOUCH_RULE
	local gk = w:As(viewer, function() return viewer.ns.Arena.GK(young.guid) end)
	-- Heard 5 minutes ago, vouched since.
	s.claims[young.name:lower() .. ":20"] = { gk = gk, name = young.name, level = 20, t = w.clock - 300, heardLocal = w.clock - 300, vouched = true }
	for _ = 1, 100 do net.RunRace() end
	local function Waiting()
		local n = 0
		for _, t in ipairs(w:Timers(viewer)) do if t.where == "arena level race" then n = n + 1 end end
		return n
	end
	eq(Waiting(), 1, "one re-check")
	eq(#(s.levels[20] or {}), 0, "too fresh yet")
	w:Run(viewer.ns.Honors.CONFIRM_AFTER - 300 + 1)
	eq(s.levels[20] and s.levels[20][1] and s.levels[20][1].name, young.name, "the place once it is old enough")
	eq(Waiting(), 0)
	W3.NoErrors(w)
end)

-- (1.2.1) The census's own news: Data.Receive takes a report and DATA_CHANGED follows within
-- Data.NOTIFY_GAP, once for a burst. A guild's row is its newest report, and the race keeps each
-- sender it sees on a claim: a second report of one guild within the gap must not hide the first.

-- The viewer's own census: the real Data.lua in its namespace (the test world's clients read the
-- harness's). Its sightings go nowhere.
local function OwnCensus(w, c)
	return w:As(c, function()
		rawset(c.ns, "Who", { Listen = function() end })
		assert(loadfile(H.ADDON_DIR .. "Data.lua"))("Olympus", c.ns)
		return rawget(c.ns, "Data")
	end)
end
-- A report of `guild` from `sender` (a name) listing `top`, as the census's message gives it.
local function Heard(w, c, guild, sender, top, faction)
	return w:As(c, function()
		return c.ns.Data.Receive({ guild = guild, faction = faction or "Alliance", total = 20, online = 2, zones = {}, leader = "Corin Ash",
			officers = {}, top = top }, sender)
	end)
end

test("1.2.1 the level race: two senders of her guild heard through the census within Data.NOTIFY_GAP (the first one's row replaced before the burst's DATA_CHANGED) are both kept on her claim, which is vouched; her own report, a level below or a refused report vouch nothing; the place after CONFIRM_AFTER", function()
	local w, cast = W3.New({ more = { { "young", "Brisa Vale", { level = 19 } } } })
	local viewer, young = cast.spectator, cast.young
	local net = HN(w, viewer)
	viewer.ns.HonorsNet.RACE_START = w.clock - 86400
	local D = OwnCensus(w, viewer)
	w:Fire(young, "PLAYER_LEVEL_UP", 20)
	w:Run(60 + net.RACE_SOON)
	local s = net.Store()
	local claim
	for _, c in pairs(s.claims) do claim = c end
	assert(claim and not claim.vouched, "her claim, waiting")
	local realm = viewer.realm
	local f1, f2, f3 = "Dovan Quell-" .. realm, "Elsa Thornby-" .. realm, "Ivo Marsh-" .. realm
	local function Senders()
		local out = {}
		for k in pairs(claim.by and claim.by["olympus vale"] or {}) do out[#out + 1] = k end
		table.sort(out)
		return table.concat(out, ",")
	end
	-- Her own report, one listing her a level below, and one the census refuses (the other faction's).
	eq(Heard(w, viewer, "Olympus Solo", young.name, { { name = young.short, level = 20, class = "MA" } }), true)
	eq(Heard(w, viewer, "Olympus Vale", f3, { { name = young.short, level = 19, class = "MA" } }), true)
	eq(Heard(w, viewer, "Olympus Vale", "Hal Brenn-" .. realm, { { name = young.short, level = 20, class = "MA" } }, "Horde"), false)
	w:Run(D.NOTIFY_GAP)
	eq(Senders(), "", "nothing kept")
	eq(claim.vouched, false)
	-- Two senders of her guild, 0.3 s apart: the second report takes the first one's place in the census
	-- before the burst's DATA_CHANGED.
	eq(Heard(w, viewer, "Olympus Vale", f1, { { name = "Corin Ash", level = 60, class = "WA" }, { name = young.short, level = 20, class = "MA" } }), true)
	w:Run(0.3)
	eq(Heard(w, viewer, "Olympus Vale", f2, { { name = young.short, level = 21, class = "MA" } }), true)
	eq(viewer.rdb.guilds["Olympus Vale"].reporterFull, f2, "the first sender's row replaced")
	w:Run(D.NOTIFY_GAP)
	eq(Senders(), "dovan quell,elsa thornby", "both senders kept")
	eq(claim.vouched, true, "vouched")
	eq(#(s.levels[20] or {}), 0, "the race later")
	w:Run(net.RACE_SOON)
	w:Run(viewer.ns.Honors.CONFIRM_AFTER)
	eq(s.levels[20] and s.levels[20][1] and s.levels[20][1].name, young.name, "first to 20")
	W3.NoErrors(w)
end)

print("HonorsNet: the donors (ID) and the Oracle (IO)")

test("1.2 the fights part: ID only from the Treasurer's characters (or the King), sent whatever the Treasury's ranking says; the month's and all time's top 3 become the koi and the cornucopia; a later word replaces an older one", function()
	local w, cast = W3.New({ more = { { "treasurer", N.treasurer, { guild = World.KING_GUILD } } } })
	local tr, viewer = cast.treasurer, cast.spectator
	-- The Treasurer's book (the money part's Treasury.DonationRecords), and its ranking private.
	local now = w.clock
	rawset(tr.ns, "Treasury", { DonationRecords = function()
		return { { name = "Torvin Hale", money = 500000, t = now - 40 * 86400 }, { name = "Selka Drummond", money = 300000, t = now - 40 * 86400 },
			{ name = "Lida Fenn", money = 100000, t = now - 40 * 86400 } }
	end, RankingShown = function() return false end })
	eq(HN(w, tr).SendDonors(true), true)
	w:Run(0)
	eq(#w:Sent{ from = tr, type = "ID", dist = "CHANNEL" }, 1)
	eq(#w:Sent{ from = tr, type = "ID", dist = "GUILD" }, 1, "and his guild, on every realm")
	local d = HN(w, viewer).Donors()
	eq(d.all[1], cast.A.name); eq(d.all[3], cast.spectator.name)
	local held = HN(w, viewer).Holdings(cast.A.name)
	eq(held[1].key, "donor-top-1"); eq(held[1].art, "cornucopia-gold")
	-- From anyone else: refused.
	local body = table.concat({ viewer.ns.Arena.B36(now + 10), viewer.ns.Arena.B36(1), "-", "Wenna Crale" }, "~")
	w:As(viewer, function() viewer.ns.Arena.Inject("CHANNEL", N.bettor2, "ID~L1~" .. body) end)
	eq(HN(w, viewer).Donors().all[1], cast.A.name)
	eq(viewer.ns.HonorsNet.Stats().refused.sender, 1)
	W3.NoErrors(w)
end)

test("1.2 the fights part: IO only from a bank of this realm's T1~B; the month's three predictors are the ravens, held through the month after", function()
	local w, cast = W3.New({ more = { { "bank", N.bank } } })
	local ok = cast.king.Roles.SetBanks({ N.bank })
	eq(ok, true)
	w:Run(0)
	local viewer = cast.spectator
	local month = viewer.ns.Honors.MonthOf(w.clock) - 1
	local body = table.concat({ viewer.ns.Arena.B36(month), viewer.ns.Arena.B36(w.clock - 5), "Wenna Crale,Parric Stowe,Lida Fenn" }, "~")
	w:As(viewer, function() viewer.ns.Arena.Inject("CHANNEL", N.bettor2, "IO~L1~" .. body) end)
	eq(HN(w, viewer).Oracle(), nil, "not a bank")
	w:As(viewer, function() viewer.ns.Arena.Inject("CHANNEL", N.bank, "IO~L1~" .. body) end)
	eq(HN(w, viewer).Oracle().names[1], "Wenna Crale-Emberfall")
	local held = HN(w, viewer).Holdings(viewer.name)
	eq(held[1].key, "oracle-3"); eq(held[1].art, "raven-bronze")
	-- Worn, then gone with the clock alone when the month after ends: no word comes then, so what
	-- Verified keeps never outlives the hour.
	eq(Prof(w, viewer).SetPick("oracle-3"), true)
	eq(HN(w, viewer).Verified(viewer.name).frame, "oracle-3")
	while viewer.ns.Honors.MonthOf(w.clock) < month + 2 do w.clock = w.clock + 3600 end
	eq(HN(w, viewer).Verified(viewer.name).frame, "rank", "the ravens' month is over")
	W3.NoErrors(w)
end)

print("HonorsNet: verification, the switch-on, the King's letter")

test("1.2 the fights part: a far viewer sees a belt holder's picked frame once verified (the core's title fights, no ledger); the same pick on a non-holder shows his rank's frame (Verified falls back)", function()
	local w, cast = W3.New()
	local viewer = cast.spectator
	Belt(w, cast, cast.A, cast.B, { viewer, cast.A, cast.B })
	-- A picks the gryphon; his AP says it (sent in L whatever the live switch).
	eq(Prof(w, cast.A).SetPick("arena-champion", "arena-champion"), true)
	w:Run(0)
	local v = HN(w, viewer).Verified(cast.A.name, cast.A.guid)
	eq(v.frame, "arena-champion"); eq(v.title, "arena-champion"); eq(v.art, "gryphon-gold"); eq(v.shape, "winged"); eq(v.mark, "gryphon-gold")
	eq(HN(w, viewer).TitleText(v.title), "Arena Champion")
	-- B claims the same (his own client can't pick it: Choose refuses; a forged AP says it).
	eq(Prof(w, cast.B).SetPick("arena-champion", nil), false)
	w:As(viewer, function()
		viewer.ns.Arena.Inject("CHANNEL", cast.B.name, "AP~L1~" .. table.concat({ "-", "WA", "1", "2", "60", "0.0", "-", "0", "arena-champion", "arena-champion",
			viewer.ns.Arena.B36(w.clock) }, "~"))
	end)
	local vb = HN(w, viewer).Verified(cast.B.name, cast.B.guid)
	eq(vb.frame, "rank"); eq(vb.title, nil); eq(vb.mark, "rank")
	W3.NoErrors(w)
end)

test("1.2 the fights part: a newly earned honour switches on by itself and the King's letter comes (Olympus's own frame, queued, 'Wear it'); a locked pick stays as set; the letters stay to read again", function()
	local w, cast = W3.New()
	local A = Kept(w, cast.A)
	Kept(w, cast.B)
	Belt(w, cast, A, cast.B, { A })
	w:Run(3)
	local pick = A.ns.ArenaProfile.Pick()
	eq(pick.frame, "arena-champion", "switched on"); eq(pick.title, "arena-champion")
	eq(#w:Sent{ from = A, type = "AP" } >= 1, true, "and said")
	local letter = A.ns.HonorsNet.LetterFrame()
	eq(letter ~= nil and letter:IsShown(), true, "the King's letter")
	eq(letter.body:GetText():find("Arena Champion", 1, true) ~= nil, true)
	eq(A.ns.HonorsNet.LetterFamily("arena-champion"), "arena")
	for _, key in ipairs({ "arena-class-mage-2", "arena-race-orc-3", "donor-top-1", "donor-month-2", "level-race-40", "oracle-1", "guild-top-leader" }) do
		local text = w:As(A, A.ns.HonorsNet.LetterText, key)
		assert(text and text:find(A.ns.HonorsNet.TitleText(key), 1, true), key)
		for _, n in ipairs({ World.NAMES.king, World.NAMES.author }) do assert(not text:find(n:match("^%S+"), 1, true), "no real name") end
	end
	eq(w:As(A, A.ns.HonorsNet.CloseLetter, true), true)
	eq(letter:IsShown(), false)
	eq(#A.ns.HonorsNet.Letters(), 1); eq(A.ns.HonorsNet.Letters()[1].read, true)
	-- Locked: the pick stays; the letter still tells.
	local B = cast.B
	eq(Prof(w, B).SetLocked(true), true)
	Belt(w, cast, B, A, { B })
	w:Run(3)
	eq(B.ns.ArenaProfile.Pick().frame, "rank", "locked")
	eq(#B.ns.HonorsNet.QueuedLetters(), 1)
	W3.NoErrors(w)
end)

test("1.2 the fights part: AP only with a pick that is not the default or arena activity (the design): an idle client with the default pick sends none and runs no arena or honours timer; a picked frame goes at login and every hour", function()
	local w = World.New()
	local idle = w:Client("Lida Fenn")
	w:Run(3700)
	eq(#w:Sent{ from = idle, type = "AP" }, 0)
	eq(#w:Timers(idle, true), 0, "no arena timer")
	local events = w:ArenaWeight(idle).events
	eq(#events, 2, "only keeper gossip and logout are registered while idle: " .. table.concat(events, ","))
	eq(events[1], "GOSSIP_SHOW")
	eq(events[2], "PLAYER_LOGOUT")
	eq(idle.db.arenaProfile, nil, "nothing written")
	-- A pick (the rank's frame is the default: 'none' is not).
	local picker = w:Client("Parric Stowe")
	w:As(picker, function() picker.ns.ArenaProfile.SetPick("none", nil) end)
	w:Run(0)
	w:Logout(picker)
	w:Login(picker)
	w:Run(61)
	local sent = #w:Sent{ from = picker, type = "AP" }
	eq(sent >= 2, true, "at the change, and 60 s after login")
	w:Run(3600)
	eq(#w:Sent{ from = picker, type = "AP" }, sent + 1, "every hour")
	eq(#w:Timers(picker, true), 1, "its one timer")
	W3.NoErrors(w)
end)

print("Borders and Nameplates: the verified frame and mark")

-- The unit frames and a nameplate, stood in for on client c (as Forever 1.60 lays them out:
-- Blizzard_UnitFrame's containers, Blizzard_NamePlates' unit frames): every texture a container or
-- plate makes records its calls. Borders.lua and Nameplates.lua then load into c's namespace.
local function Frames(w, c)
	local rec = { textures = {}, noFile = {} }
	local function Texture(owner, sublevel)
		local t = { owner = owner, sublevel = sublevel, shown = true, calls = {} }
		local function Rec(m) t.calls[#t.calls + 1] = m end
		-- (A texture shows the last art it was given: a file or an atlas.)
		t.SetTexture = function(self, file) Rec("SetTexture") if rec.noFile[file] then return false end self.file, self.atlas = file, nil return true end
		t.SetAtlas = function(self, a) Rec("SetAtlas") self.atlas, self.file = a, nil end
		t.SetSize = function(self, x, y) Rec("SetSize") self.size = x .. "x" .. y end
		t.SetPoint = function(self, ...) Rec("SetPoint") end
		t.ClearAllPoints = function() Rec("ClearAllPoints") end
		t.SetTexCoord = function(self, ...) Rec("SetTexCoord") self.coord = table.concat({ ... }, " ") end
		t.SetDesaturated = function(self, value) Rec("SetDesaturated") self.desaturated = value end
		t.SetVertexColor = function(self, ...) Rec("SetVertexColor") self.color = table.concat({ ... }, " ") end
		t.Show = function(self) Rec("Show") self.shown = true end
		t.Hide = function(self) Rec("Hide") self.shown = false end
		t.IsShown = function(self) return self.shown end
		t.IsProtected = function() return false end
		rec.textures[#rec.textures + 1] = t
		return t
	end
	local function Container(label)
		return { label = label, CreateTexture = function(_, _, _, _, sublevel) return Texture(label, sublevel) end }
	end
	local g = c.globals
	g.TargetFrame = { TargetFrameContainer = Container("target"), CheckClassification = function() end }
	g.FocusFrame = { TargetFrameContainer = Container("focus"), CheckClassification = function() end }
	g.PlayerFrame = { PlayerFrameContainer = Container("player") }
	g.hooksecurefunc = function(t, key, post)
		if type(t) ~= "table" then return end
		local original = t[key]
		t[key] = function(...) local r = { original(...) } post(...) return unpack(r) end
	end
	g.C_Texture = { GetAtlasInfo = function() return {} end }
	g.InCombatLockdown = function() return rec.combat == true end
	-- The nameplate: nameplate1 is the target's player.
	local plate = { UnitFrame = { unit = "nameplate1", IsForbidden = function() return false end, CreateTexture = function() return Texture("plate") end,
		name = { GetJustifyH = function() return "CENTER" end, GetStringWidth = function() return 60 end, GetWidth = function() return 100 end,
			IsShown = function() return true end } }, IsForbidden = function() return false end }
	g.C_NamePlate = { GetNamePlateForUnit = function(u) if u == "nameplate1" then return plate end end, GetNamePlates = function() return { plate } end }
	for _, fn in ipairs({ "UnitExists", "UnitIsPlayer", "UnitGUID", "UnitFullName", "GetGuildInfo", "UnitName", "GetUnitName" }) do
		local base = g[fn]
		g[fn] = function(unit, ...) if unit == "nameplate1" then unit = "target" end return base(unit, ...) end
	end
	g.UnitIsUnit = function(a, b) return a == b end
	g.UnitIsFriend = function() return true end
	g.UnitCanAttack = function() return false end
	w:As(c, function()
		rawset(c.ns, "Borders", nil)
		rawset(c.ns, "Nameplates", nil)
		assert(loadfile(H.ADDON_DIR .. "Borders.lua"))("Olympus", c.ns)
		assert(loadfile(H.ADDON_DIR .. "Nameplates.lua"))("Olympus", c.ns)
	end)
	rec.B, rec.NP = W3.M(w, c, "Borders"), W3.M(w, c, "Nameplates")
	rec.plate = plate
	-- What a container shows now: its foreground file (an honour's), atlas (a rank's), or nil;
	-- never two. The metal underlay is separately observable at sublevel 2.
	function rec.Shown(owner)
		local found
		for _, t in ipairs(rec.textures) do
			if t.owner == owner and t.sublevel ~= 2 and t.shown then
				assert(not found, "two at once on " .. owner)
				found = t
			end
		end
		return found and (found.file or found.atlas) or nil
	end
	function rec.Underlay(owner)
		for _, t in ipairs(rec.textures) do if t.owner == owner and t.sublevel == 2 then return t end end
	end
	function rec.Count(owner)
		local n = 0
		for _, t in ipairs(rec.textures) do if t.owner == owner then n = n + 1 end end
		return n
	end
	return rec
end

test("1.2 the fights part: Borders and Nameplates show the verified honour's frame (its shape's one texture) and its mark; a non-holder's pick, his rank's; hidden with the gamepad UI and for anyone net-off; a file the client can't load falls back to the rank's frame", function()
	local w, cast = W3.New()
	local viewer = cast.spectator
	Belt(w, cast, cast.A, cast.B, { viewer, cast.A })
	eq(Prof(w, cast.A).SetPick("arena-champion", nil), true)
	w:Run(0)
	local r = Frames(w, viewer)
	cast.A.rank, cast.A.rankName = 0, "Guild Master" -- (his rank's frame: Max's bronze wings, a guild master's since 1.1.5)
	viewer.target = cast.A.name
	r.B.Refresh("target", true)
	eq(r.Shown("target"), "Interface\\AddOns\\Olympus\\media\\honors\\gryphon-gold", "the gryphon")
	-- (1.2.4, the author's call: no plain dragon under an honour, the portrait's own ring alone.)
	eq(r.Underlay("target").shown, false, "no metal underlay under an honour")
	r.NP.Added("nameplate1")
	eq(r.Shown("plate"), "Interface\\AddOns\\Olympus\\media\\honors\\gryphon-gold-mark", "its mark")
	-- B, no belt, and a forged pick of it: his rank's (1.1.5: the bronze wings of a guild master).
	cast.B.rank, cast.B.rankName = 0, "Guild Master"
	w:As(viewer, function()
		viewer.ns.Arena.Inject("CHANNEL", cast.B.name, "AP~L1~" .. table.concat({ "-", "WA", "1", "2", "60", "0.0", "-", "0", "arena-champion", "-",
			viewer.ns.Arena.B36(w.clock) }, "~"))
	end)
	viewer.target = cast.B.name
	r.B.Refresh("target", true)
	eq(r.Shown("target"), "Interface\\AddOns\\Olympus\\media\\borders\\bronze-winged", "his rank's frame")
	r.NP.RefreshAll(true)
	eq(r.Shown("plate"), "nameplates-icon-elite-gold", "his rank's mark (the bronze: the gold without colour)")
	-- The file missing: the rank's frame instead.
	viewer.target = cast.A.name
	r.noFile["Interface\\AddOns\\Olympus\\media\\honors\\gryphon-gold"] = true
	r.B.Refresh("target", true)
	eq(r.Shown("target"), "Interface\\AddOns\\Olympus\\media\\borders\\bronze-winged", "missing art: the rank's")
	r.noFile = {}
	r.B.Refresh("target", true)
	eq(r.Shown("target"), "Interface\\AddOns\\Olympus\\media\\honors\\gryphon-gold")
	-- Net-off: nothing (no border, no mark).
	local M = viewer.ns.Moderation
	local hides = M.Hides
	M.Hides = function(name) if name and name:find("Torvin", 1, true) then return { kind = "c" } end return hides(name) end
	r.B.Refresh("target", true)
	eq(r.Shown("target"), nil, "net-off: none")
	M.Hides = hides
	r.B.Refresh("target", true)
	-- The gamepad UI: every border hides.
	viewer.globals.C_InputInterfaceStyle = { GetCurrentStyle = function() return 1 end }
	viewer.globals.Enum = { InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 } }
	r.B.Refresh("target", true)
	eq(r.Shown("target"), nil, "the gamepad UI")
	W3.NoErrors(w)
end)

test("1.2 the fights part: an honour's nameplate mark the client can't load falls back to his rank's mark, as his frame does; the plate doesn't try the file again on every refresh, and the same honour over another rank gets that rank's mark", function()
	local w, cast = W3.New()
	local viewer = cast.spectator
	Belt(w, cast, cast.A, cast.B, { viewer, cast.A })
	eq(Prof(w, cast.A).SetPick("arena-champion", nil), true)
	w:Run(0)
	local r = Frames(w, viewer)
	cast.A.rank, cast.A.rankName = 0, "Guild Master" -- (his rank's mark: the bronze, a guild master's since 1.1.5)
	viewer.target = cast.A.name
	local file = "Interface\\AddOns\\Olympus\\media\\honors\\gryphon-gold-mark"
	r.noFile[file] = true
	r.NP.Added("nameplate1")
	eq(r.Shown("plate"), "nameplates-icon-elite-gold", "his rank's mark, not none")
	local tex
	for _, t in ipairs(r.textures) do if t.owner == "plate" then tex = t end end
	eq(tex.desaturated, true, "the bronze: the gold without colour")
	local tried = 0
	for _, m in ipairs(tex.calls) do if m == "SetTexture" then tried = tried + 1 end end
	eq(tried, 1, "the honour's file tried once")
	local calls = #tex.calls
	r.NP.RefreshAll()
	r.NP.RefreshAll()
	eq(#tex.calls, calls, "dressed already: nothing asked of the texture again")
	-- The same honour over a plain member's rank: the star, his own rank's mark.
	cast.A.rank, cast.A.rankName = 3, "Member"
	r.NP.RefreshAll(true)
	eq(r.Shown("plate"), "Interface\\AddOns\\Olympus\\media\\borders\\star", "the star")
	W3.NoErrors(w)
end)

test("1.2 the fights part review: a nameplate whose honour's mark can't load, next showing a player outside Olympus with that honour (no rank's mark to fall back to), never keeps the last player's rank mark", function()
	local w, cast = W3.New()
	local viewer = cast.spectator
	Belt(w, cast, cast.A, cast.B, { viewer, cast.A })
	eq(Prof(w, cast.A).SetPick("arena-champion", nil), true)
	w:Run(0)
	local r = Frames(w, viewer)
	cast.A.rank, cast.A.rankName = 0, "Guild Master" -- (1.1.5: a guild master's bronze)
	viewer.target = cast.A.name
	r.noFile["Interface\\AddOns\\Olympus\\media\\honors\\gryphon-gold-mark"] = true
	r.NP.Added("nameplate1")
	eq(r.Shown("plate"), "nameplates-icon-elite-gold", "a member's: his rank's mark")
	-- The plate's player now outside Olympus, his honour still verified: no rank's mark.
	cast.A.guild = "Ironforge Traders"
	eq(w:As(viewer, viewer.ns.Borders.MarkOf, "nameplate1"), nil, "no rank's mark")
	r.NP.RefreshAll(true)
	eq(r.Shown("plate"), nil, "not the last player's bronze")
	W3.NoErrors(w)
end)

test("1.2 the fights part: 80 honour picks make one texture per normalized family or winged shape per rig; with the textures made, a target change in combat re-textures them without SetPoint or SetSize", function()
	local w, cast = W3.New()
	local viewer = cast.spectator
	local r = Frames(w, viewer)
	cast.A.rank, cast.A.rankName = 0, "Guild Master" -- (1.1.5: a guild master's bronze)
	viewer.target = cast.A.name
	local current
	viewer.ns.HonorsNet.Verified = function() return current end
	local keys = {}
	for _, art in ipairs(viewer.ns.Honors.ArtFiles()) do keys[#keys + 1] = art end
	local picks = {}
	for _, k in ipairs({ "arena-champion", "arena-champion-2", "arena-champion-3", "guild-top-leader" }) do picks[#picks + 1] = k end
	for _, c in ipairs({ "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid" }) do
		picks[#picks + 1] = "arena-class-" .. c
		picks[#picks + 1] = "arena-class-" .. c .. "-2"
		picks[#picks + 1] = "arena-class-" .. c .. "-3"
	end
	for _, rc in ipairs({ "human", "dwarf", "nightelf", "gnome", "orc", "undead", "tauren", "troll" }) do
		picks[#picks + 1] = "arena-race-" .. rc
		picks[#picks + 1] = "arena-race-" .. rc .. "-2"
		picks[#picks + 1] = "arena-race-" .. rc .. "-3"
	end
	for n = 1, 3 do for _, f in ipairs({ "donor-top", "donor-month", "oracle" }) do picks[#picks + 1] = f .. "-" .. n end end
	for _, m in ipairs({ 20, 40, 60 }) do picks[#picks + 1] = "level-race-" .. m end
	while #picks < 80 do picks[#picks + 1] = picks[(#picks % 67) + 1] end
	-- (The rig made first, his rank's frame on it.)
	current = { frame = "rank", mark = "rank" }
	r.B.Refresh("target", true)
	local base = r.Count("target")
	eq(base, #viewer.ns.Borders.TIERS + 1, "the rank's frames and their shared underlay")
	local slots = {}
	for _, key in ipairs(picks) do
		local art, shape = viewer.ns.Honors.ArtOf(key)
		local family = art and art:match("^(.+)%-[^%-]+$")
		slots[shape == "plain" and family or shape] = true
		current = { frame = key, mark = art, art = art, shape = shape }
		r.B.Refresh("target", true)
		eq(r.Shown("target"), "Interface\\AddOns\\Olympus\\media\\honors\\" .. art, key)
	end
	local slotCount = 0
	for _ in pairs(slots) do slotCount = slotCount + 1 end
	eq(r.Count("target") - base, slotCount, "one texture for every normalized family, plus each unsized shape")
	-- In combat now: a new target's frame is only retextured.
	r.combat = true
	local marks = {}
	for _, t in ipairs(r.textures) do if t.owner == "target" then marks[t] = #t.calls end end
	for _, key in ipairs({ "arena-class-mage", "guild-top-leader", "oracle-2", "arena-champion" }) do
		local art, shape = viewer.ns.Honors.ArtOf(key)
		current = { frame = key, mark = art, art = art, shape = shape }
		r.B.Refresh("target", true)
	end
	for t, from in pairs(marks) do
		for i = from + 1, #t.calls do
			local m = t.calls[i]
			assert(m ~= "SetPoint" and m ~= "SetSize" and m ~= "ClearAllPoints", "in combat: " .. m)
		end
	end
	eq(r.Count("target") - base, slotCount, "nothing made in combat")
	W3.NoErrors(w)
end)

test("1.2 the fights part: the author's preview (Borders.SetPreview) takes an honour key: its frame round his own portrait (turned round, as a holder sees his own) and its mark on the plates; the Workshop's lines list one honour of each family", function()
	local w = World.New()
	local author = w:Client(N.author)
	local other = w:Client(N.fighterA)
	local r = Frames(w, author)
	author.target = other.name
	eq(r.B.SetPreview("arena-class-mage-2"), true)
	eq(r.B.Preview(), "arena-class-mage-2")
	r.B.Refresh("player", true)
	eq(r.Shown("player"), "Interface\\AddOns\\Olympus\\media\\honors\\mage-silver")
	local t
	for _, x in ipairs(r.textures) do if x.owner == "player" and x.shown then t = x end end
	eq(t.coord, "0.78125 0 0 0.78125", "turned round on his own frame")
	eq(t.size, "95x95", "the mage family's normalized box")
	r.NP.RefreshAll(true)
	eq(r.Shown("plate"), "Interface\\AddOns\\Olympus\\media\\honors\\mage-silver-mark")
	local lines = {}
	r.B.PreviewLines(lines)
	local listed = {}
	for _, l in ipairs(lines) do if l.text then listed[#listed + 1] = l.text end end
	local text = table.concat(listed, "\n")
	for _, key in ipairs({ "arena-champion", "donor-top-1", "level-race-60", "oracle-1", "guild-top-leader" }) do
		assert(text:find(key, 1, true), "a Workshop line for " .. key)
	end
	eq(r.B.SetPreview("off"), true)
	-- Anyone else: no preview (what /oly borders says).
	local rr = Frames(w, other)
	eq(rr.B.SetPreview("arena-champion"), false)
	W3.NoErrors(w)
end)

-- 1.2.1 (the author's ask): the new frames, a preview only. /oly borders test <key> shows each round
-- his own portrait as a holder sees his own, on its plain metal (the red cross on the black), and
-- its mark on the plates; nobody else can preview them, and nobody's real border changes.
test("1.2.1 the new frames: /oly borders test apostle-1/2/3, bones-1/2/3, arena-race-skyborn(-2/-3) and apostle-red show the cross, the charm, the owlcat and the red cross round the author's own portrait, and their marks", function()
	local w = World.New()
	local author = w:Client(N.author)
	local other = w:Client(N.fighterA)
	local r = Frames(w, author)
	author.target = other.name
	local MEDIA = "Interface\\AddOns\\Olympus\\media\\honors\\"
	local want = {
		{ "apostle-1", "cross-gold", "1 1 1 1" }, { "apostle-2", "cross-silver", "1 1 1 1" }, { "apostle-3", "cross-bronze" },
		{ "bones-1", "charm-gold" }, { "bones-2", "charm-silver" }, { "bones-3", "charm-bronze" },
		{ "arena-race-skyborn", "owlcat-gold" }, { "arena-race-skyborn-2", "owlcat-silver" }, { "arena-race-skyborn-3", "owlcat-bronze" },
		{ "apostle-red", "cross-red", "0.24 0.24 0.27 1" },
	}
	local SIZES = {
		["apostle-1"] = "110x110", ["apostle-2"] = "110x110", ["apostle-3"] = "110x110",
		["bones-1"] = "117x117", ["bones-2"] = "117x117", ["bones-3"] = "117x117",
		["arena-race-skyborn"] = "101x101", ["arena-race-skyborn-2"] = "101x101", ["arena-race-skyborn-3"] = "101x101",
		["apostle-red"] = "110x110",
	}
	for _, row in ipairs(want) do
		local key, art, color = row[1], row[2], row[3]
		eq(r.B.SetPreview(key), true, key)
		eq(r.B.Preview(), key)
		r.B.Refresh("player", true)
		eq(r.Shown("player"), MEDIA .. art, key)
		local t
		for _, x in ipairs(r.textures) do if x.owner == "player" and x.sublevel ~= 2 and x.shown then t = x end end
		eq(t.coord, "0.78125 0 0 0.78125", key .. ": the plain box, turned round on his own frame")
		-- The complete normalization gives every plain family its own box while keeping the
		-- portrait-centre alignment: tests/arena/honors-own-look.lua and tests/treasurer-dragon.lua.
		eq(t.size, SIZES[key], key)
		-- (1.2.4, the author's call: no plain dragon under any honour, the red cross's black one
		-- too; the portrait's own ring alone.)
		local under = r.Underlay("player")
		eq(under.shown, false, key .. ": no plain metal under it")
		r.NP.RefreshAll(true)
		eq(r.Shown("plate"), MEDIA .. art .. "-mark", key .. "'s mark")
	end
	eq(r.B.SetPreview("off"), true)
	-- Anyone else: no preview.
	local rr = Frames(w, other)
	eq(rr.B.SetPreview("apostle-red"), false)
	eq(rr.B.SetPreview("bones-1"), false)
	W3.NoErrors(w)
end)

-- 1.2 (the owner's ask, test build 33): every Olympus portrait identical to the player's own on his
-- unit frame. The core's windows that show his portrait with a frame (the King's letter, the
-- profile's Edit) drew their own: a square picture and the frame centred on it at a size of their
-- own. They are Borders.NewPortrait's now (HonorsNet.NewPortrait), as the Arena's portraits.
-- c's frames and their words keep where they were put (points[region][point] = SetPoint's
-- arguments), and SetPortraitTexture's calls (pictures).
local function Placed(c)
	local points, pictures = {}, {}
	local function Keep(region)
		rawset(region, "SetPoint", function(self, point, ...)
			points[self] = points[self] or {}
			points[self][point] = { point, ... }
		end)
		return region
	end
	local create = c.globals.CreateFrame
	c.globals.CreateFrame = function(...)
		local f = Keep(create(...))
		rawset(f, "CreateFontString", function(self) return Keep(World.NewFrame("FontString", nil, self)) end)
		return f
	end
	c.globals.SetPortraitTexture = function(tex, unit, square) pictures[#pictures + 1] = { tex = tex, unit = unit, square = square } end
	return points, pictures
end
local GRYPHON = "Interface\\AddOns\\Olympus\\media\\honors\\gryphon-gold"

test("1.2 the King's letter: his portrait drawn as his own on his unit frame (Borders.NewPortrait, his frame's 60 across, turned round): the honour won the very art round his own portrait, his picture square; the words clear of the art", function()
	local w, cast = W3.New()
	local A = Kept(w, cast.A)
	local r = Frames(w, A)
	local points, pictures = Placed(A)
	Belt(w, cast, A, cast.B, { A })
	w:Run(3)
	local letter = A.ns.HonorsNet.LetterFrame()
	eq(letter ~= nil and letter:IsShown(), true, "the King's letter")
	local rig = letter.rig
	assert(type(rig) == "table" and rig.container and rig.box and rig.underlay and not rig.plain, "Borders.NewPortrait's rig, not a drawing of the letter's own")
	eq(rig.size, 60, "his own frame's size"); eq(rig.mirror, true, "turned round, as round his own portrait")
	-- The frame he won on the rig's texture for its shape; his live picture square on its portrait.
	eq(rig.shown, "arena-champion"); eq(rig.honor.winged.texture, GRYPHON); eq(rig.honor.winged.shown, true)
	eq(letter.portrait, rig.portrait)
	local last = pictures[#pictures]
	eq(last.tex, rig.portrait); eq(last.unit, "player"); eq(last.square, true)
	-- The same art round his own portrait on his unit frame (the pick the honour switched on).
	r.B.Refresh("player", true)
	eq(r.Shown("player"), rig.honor.winged.texture)
	-- The words clear of the art (Borders.PortraitReach at 60: 37 left, 14 right, 20 up): inside the
	-- letter, below its head, the body right of it.
	eq(rig.reach.left, 37); eq(rig.reach.right, 14); eq(rig.reach.top, 20)
	local at, body = points[rig.slot].TOPLEFT, points[letter.body].TOPLEFT
	eq(at[2] - rig.reach.left >= 16, true, "inside the letter")
	eq(-at[3] - rig.reach.top >= 36, true, "below the head")
	eq(body[2] >= at[2] + 60 + rig.reach.right + 8, true, "the words right of the art")
	-- A letter for an honour this client has no art for: no frame on it (never another's art).
	w:As(A, A.ns.HonorsNet.CloseLetter, false)
	w:As(A, A.ns.HonorsNet.ShowLetter, "no-such-honour")
	eq(rig.shown, nil); eq(rig.honor.winged.shown, false)
	W3.NoErrors(w)
end)

-- 1.2.4: the panel's preview is "My profile"'s detail box now (the Olympus window's, UI.lua: made
-- with HonorsNet.NewPortrait, dressed by ProfileEdit.DressPortrait with the art the page gives).
-- The same assertions on that portrait; its place inside the detail box is UI.lua's, tested in
-- tests/run.lua (the Olympus window's own harness).
test("1.2 the profile's Edit: its preview is his portrait drawn as his own on his unit frame (Borders.NewPortrait): the honour picked, his rank's border for the rank's frame, nothing for none, each as round his own portrait (1.2.4: My profile's detail box, from the page's art)", function()
	local w, cast = W3.New()
	local A = cast.A
	local r = Frames(w, A)
	local _, pictures = Placed(A)
	Belt(w, cast, A, cast.B, { A })
	w:Run(3)
	w:As(A, A.ns.HonorsNet.CloseLetter, false)
	A.rank, A.rankName = 0, "Guild Master" -- (his rank's frame: Max's bronze wings, a guild master's since 1.1.5)
	W3.PageUI(w, A)
	eq(w:As(A, A.ns.ProfileEdit.Open), true)
	local rig = w:As(A, function() return A.ns.HonorsNet.NewPortrait(CreateFrame("Frame"), 42) end)
	assert(type(rig) == "table" and rig.container and rig.box and not rig.plain, "Borders.NewPortrait's rig")
	eq(rig.size, 42); eq(rig.mirror, true)
	-- The page's art, as UI.Refresh dresses the detail box's portrait with it.
	local function Draw()
		local _, _, _, _, art = w:As(A, A.ns.ProfileEdit.Page, { full = A.name }, {})
		return w:As(A, A.ns.ProfileEdit.DressPortrait, rig, art)
	end
	eq(Draw(), "honour")
	local last = pictures[#pictures]
	eq(last.tex, rig.portrait); eq(last.unit, "player"); eq(last.square, true)
	-- What his own portrait shows (his unit frame's rig) and what the preview shows: the same art.
	local function Preview()
		local tex = rig.shownTex
		return tex and tex.shown and tex.texture or nil
	end
	local function Own() r.B.Refresh("player", true) return r.Shown("player") end
	eq(rig.shown, "arena-champion"); eq(Preview(), GRYPHON); eq(Own(), GRYPHON)
	eq(w:As(A, A.ns.ProfileEdit.PickFrame, "rank"), true)
	eq(Draw(), "rank")
	eq(rig.shown, "bronze-elite", "his rank's border"); eq(Preview(), "Interface\\AddOns\\Olympus\\media\\borders\\bronze-winged"); eq(Own(), Preview())
	eq(w:As(A, A.ns.ProfileEdit.PickFrame, "none"), true)
	eq(Draw(), nil)
	eq(rig.shown, nil); eq(Preview(), nil); eq(Own(), nil)
	W3.NoErrors(w)
end)

test("1.2 the fights part: follows: a star on a fighter's profile, account-wide, 50 at most", function()
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local P = Prof(w, a)
	for i = 1, 50 do eq(P.Follow(("1a.%08x"):format(i), true, "F"), true) end
	local ok, why = P.Follow("1a.000000ff", true)
	eq(ok, false); eq(why, "full")
	eq(P.Follow("1a.00000001", false), true)
	eq(P.Follow("1a.000000ff", true), true)
	eq(P.Following("1a.000000ff"), true)
	eq(P.Follow("not a gk", true), false)
	W3.NoErrors(w)
end)

print("The honours' art and words")

test("1.2 the fights part: every art file the honours name ships in Olympus/media/honors: a 256 x 256 frame and a 32 x 32 mark, 32-bit uncompressed TGA with its footer (scripts/make-honors.py); nothing else there", function()
	local ns = { Honors = nil }
	assert(loadfile(H.ADDON_DIR .. "Honors.lua"))("Olympus", ns)
	ns.Honors.FRAMES_SHIPPED = nil -- (every family's frame: the machinery's tests; 1.2.0 wears the donors' alone)
	local dir = H.ADDON_DIR .. "media/honors/"
	local function Check(path, size)
		local s = Read(path)
		eq(#s, 18 + size * size * 4 + 26, path)
		local idlen, cmap, kind = s:byte(1), s:byte(2), s:byte(3)
		eq(idlen, 0) eq(cmap, 0) eq(kind, 2, path .. ": uncompressed true colour")
		eq(s:byte(13) + 256 * s:byte(14), size) eq(s:byte(15) + 256 * s:byte(16), size)
		eq(s:byte(17), 32) eq(s:byte(18), 8)
		eq(s:sub(-18), "TRUEVISION-XFILE.\0")
	end
	local want = {}
	for _, art in ipairs(ns.Honors.ArtFiles()) do
		Check(dir .. art .. ".tga", 256)
		Check(dir .. art .. "-mark.tga", 32)
		want[art .. ".tga"], want[art .. "-mark.tga"] = true, true
	end
	local p = io.popen('ls -1 "' .. dir .. '"')
	local n = 0
	for name in p:lines() do
		n = n + 1
		eq(want[name], true, "an honour's file: " .. name)
	end
	p:close()
	eq(n, 160, "67 frames and 67 marks, (1.2.1) the ten preview frames and their marks, and (1.2.3) the three crooks and theirs")
end)

test("1.2 the fights part: the words of fights and honours exist in English and pt-BR, the same keys (tables with the same entries); every title and letter the honours can name", function()
	local src = Read(H.ADDON_DIR .. "Locales/ArenaFightsText.lua")
	local head, tail = src:match("^(.-)\nif GetLocale and GetLocale%(%) == \"ptBR\" then(\n.*)$")
	local en, pt = {}, {}
	for k in head:gmatch("\nL%.([%w_]+)[ ,]") do en[k] = true end
	for k in tail:gmatch("\n\tL%.([%w_]+)[ ,]") do pt[k] = true end
	for k in pairs(en) do assert(pt[k], "pt-BR lacks " .. k) end
	for k in pairs(pt) do assert(en[k], "English lacks " .. k) end
	-- Both languages' tables, loaded: the same entries.
	local function Load(locale)
		local L = setmetatable({}, { __index = function(_, k) return k end })
		local saved = GetLocale
		GetLocale = function() return locale end
		local ok, err = pcall(function() assert(loadfile(H.ADDON_DIR .. "Locales/ArenaFightsText.lua"))("Olympus", { L = L }) end)
		GetLocale = saved
		assert(ok, err)
		return L
	end
	local E, P = Load("enUS"), Load("ptBR")
	for _, key in ipairs({ "HONOR_TITLES", "HONOR_LETTER", "HONOR_CLASS_NAMES", "HONOR_RACE_NAMES", "ARENA_CLASS_NAMES", "ARENA_RACE_NAMES" }) do
		for k in pairs(rawget(E, key)) do assert(rawget(P, key)[k], "pt-BR " .. key .. " lacks " .. tostring(k)) end
		for k in pairs(rawget(P, key)) do assert(rawget(E, key)[k], "English " .. key .. " lacks " .. tostring(k)) end
	end
	for _, list in ipairs({ "ARENA_EPI_A", "ARENA_EPI_N" }) do eq(#rawget(E, list), 32) eq(#rawget(P, list), 32) end
	-- Every key the code uses is defined.
	local used = {}
	for _, f in ipairs({ "ArenaFights", "ArenaLedger", "ArenaTourney", "ArenaProfile", "ProfileEdit", "HonorsNet" }) do
		local code = Read(H.ADDON_DIR .. f .. ".lua")
		for k in code:gmatch("L%.([A-Z][A-Z0-9_]+)") do used[k] = true end
	end
	for _, p in ipairs({ "TODAY", "WEEK", "MONTH", "ALL" }) do used["ARENA_PERIOD_" .. p] = true end
	for _, m in ipairs({ "GOLD", "SILVER", "BRONZE" }) do used["HONOR_METAL_" .. m] = true end
	used.ARENA_CONSENT_HISTORY, used.ARENA_CONSENT_HISTORY_TEXT = true, true
	-- (1.2.4: "My profile"'s Icons section reuses the council icon picker's words, which are the
	-- core's own, Locales.lua's: defined there counts; both languages are checked for every file by
	-- "every locale key the code names", tests/arena/net.lua.)
	local base = {}
	local saved = GetLocale
	GetLocale = function() return "enUS" end
	local ok, err = pcall(function() assert(loadfile(H.ADDON_DIR .. "Locales.lua"))("Olympus", base) end)
	-- (1.2.4: the history's Consent line, which ArenaProfile.lua names by its keys, is defined in
	-- ArenaHomeText.lua alone, the file that loads after this one and so always won: defined there
	-- counts. tests/arena/profile-edit.lua checks its words as the TOC loads them.)
	if ok then ok, err = pcall(function() assert(loadfile(H.ADDON_DIR .. "Locales/ArenaHomeText.lua"))("Olympus", base) end) end
	GetLocale = saved
	assert(ok, err)
	for k in pairs(used) do assert(rawget(E, k) ~= nil or rawget(base.L, k) ~= nil, "not defined: " .. k) end
end)
