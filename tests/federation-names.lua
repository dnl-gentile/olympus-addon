-- 1.6.0: a guild whose name sets Olympus as a comparison counted as an Olympus guild (reported on
-- 2026-11-15, asking twice to take the guild out of the addon; Core.lua's name rule, its 1.6.0 note).
-- This is what it meets with mixed versions, through each client's own Comm, Relay and Data (a
-- verifier's client and the Join page apart): who of its members reports it, who counts it, what a
-- relay passes on, and what a client that counted it keeps after its update. Every name is made up.
-- A 1.5.9 client here is this release's code with 1.5.9's name rule (tests/fixtures/names-1.5.9.lua),
-- the one part of it that decides which guilds count; the 1.6.0 candidate before this change read the
-- same rule, so "before" is both.
-- Loaded by tests/run.lua after tests/census-relay.lua.
local ns, test, eq, extra = ...
local OLD = extra.fixtures .. "names-1.5.9.lua"
local PVE = "CAMWOWUS2Realm1PvE"
local RIVAL, DAWN, KNIGHTS, EMBERS = "Stronger Than Olympus", "Olympus Dawn", "Knights of Olympus", "Olympus Embers"
local RELAY = "Max Ran" -- (a signed relay of RelayWorld's list)

-- Clients of one Forever realm group, each a RelayWorld node (its own Comm and Relay) with its own Data.lua,
-- whose INIT runs as at login, and its own Roster.lua over the roster the world gives it. The world's
-- GetGuildInfo answers for the client acting (As). Node(short, guild, version, size, saved): version
-- "1.5.9" reads that release's name rule; saved, the saved variables of an earlier session's client
-- (its db and rdb).
local function World(fn)
	local saved = { channel = GetChannelName, guild = GetGuildInfo, inGuild = IsInGuild, chat = C_ChatInfo, time = GetTime,
		serverTime = GetServerTime, number = GetNumGuildMembers, row = GetGuildRosterInfo }
	local clock, acting = 1794160000, nil
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		IsInGuild = function() return true end
		GetGuildInfo = function() return acting and acting.guild, "Member", 3 end
		GetTime = function() return clock end
		GetServerTime = function() return math.floor(clock) end
		GetNumGuildMembers = function() return acting and acting.size or 0, 6 end
		GetGuildRosterInfo = function(row)
			local n = acting
			return row == 1 and n.N.me or (n.short:gsub(" ", "") .. row .. "-" .. PVE), "Member", row == 1 and 0 or 3,
				30, "Warrior", "Stormwind City", "", "", row <= 6, 0, "WARRIOR"
		end
		local function As(n, f, ...)
			local was = acting
			acting, C_ChatInfo = n, n.chat
			local out = { f(...) }
			acting = was
			return unpack(out)
		end
		local function Node(short, guild, version, size, saved)
			local n = { short = short, guild = guild, version = version, size = size }
			acting = n
			local N, deliver, sent, _, pump = extra.RelayWorld(short .. "-" .. PVE, guild)
			n.N, n.deliver, n.sent, n.pump, n.chat = N, deliver, sent, pump, C_ChatInfo
			N.clock, N.realm, N.group, N.faction = clock, PVE, ns.ForeverFamily(PVE), "Alliance"
			if saved then
				N.db, N.rdb = saved.N.db, saved.N.rdb
			else
				N.db = { blocked = {} }
				N.rdb.guilds, N.rdb.seen = {}, {}
			end
			N.Church = { IsLedgerRelay = N.Relay.IsRelay }
			N.QuietPresence = function() return false end
			if version == "1.5.9" then assert(loadfile(OLD))("Olympus", N) end
			local init, on = {}, N.On
			N.On = function(name, f) if name == "INIT" then init[#init + 1] = f else on(name, f) end end
			assert(loadfile(extra.addon .. "Data.lua"))("Olympus", N)
			N.On = on
			for _, f in ipairs(init) do f() end
			assert(loadfile(extra.addon .. "Roster.lua"))("Olympus", N)
			acting = nil
			return n
		end
		fn(Node, As)
	end)
	GetChannelName, GetGuildInfo, IsInGuild, C_ChatInfo, GetTime, GetServerTime, GetNumGuildMembers, GetGuildRosterInfo =
		saved.channel, saved.guild, saved.inGuild, saved.chat, saved.time, saved.serverTime, saved.number, saved.row
	-- Roster.Scan caches the rows it last read: the harness's own roster back for the tests after.
	pcall(ns.Roster.Scan)
	if not ok then error(err, 0) end
end

-- A client's census as its window shows it: { guilds = n, characters = n, rival = its row or nil }, the
-- rival being RIVAL or the guild named.
local function Census(n, As, rival)
	local s = As(n, n.N.Data.Summary)
	local out = { guilds = #s.guilds, characters = s.characters }
	for _, e in ipairs(s.guilds) do if e.name == (rival or RIVAL) then out.rival = e end end
	return out
end
local function Carries(payload, rival) return payload ~= nil and payload:find(rival or RIVAL, 1, true) ~= nil end

-- A relay of Olympus Dawn; a member of the rival guild on 1.5.9 and one on 1.6.0; the masters of two
-- Olympus guilds, one on each version. Each reads its roster and sends its census as the game would carry
-- it (by whisper to the relay); the relay hands each word to the guilds' registered reporters, then its
-- snapshot. versions: { relay, rival59, rival60, knights, embers }, and guild: the rival's name (RIVAL
-- if none).
local function Run(Node, As, v)
	local rival = v.guild or RIVAL
	local R = Node(RELAY, DAWN, v.relay, 200)
	local A = Node("Rival Lead", rival, v.rival59, 120)
	local B = Node("Rival Member", rival, v.rival60, 120)
	local K = Node("Knight Lead", KNIGHTS, v.knights, 150)
	local E = Node("Ember Lead", EMBERS, v.embers, 90)
	local out = { member = {}, sent = {} }
	for _, n in ipairs({ A, B, K, E }) do
		out.member[n.short] = As(n, n.N.IsMember)
		-- The guild's registrant tells the relay it reports for its guild (as Relay.Register words it).
		if out.member[n.short] then As(R, R.deliver, "WHISPER", n.N.me, "RL~P~RR~" .. n.guild) end
	end
	for _, n in ipairs({ R, A, B, K, E }) do
		As(n, function()
			local report = n.N.Roster.Scan()
			n.N.Data.SetLocal(report)
			if n ~= R then n.deliver("WHISPER", R.N.me, "RY~") end -- (its relay answered its ping)
			local before = #n.sent
			n.N.Comm.Broadcast(report)
			n.pump(100)
			local pieces = 0
			for i = before + 1, #n.sent do
				local p = n.sent[i]
				if n ~= R and p.target == RELAY then
					pieces = pieces + 1
					As(R, R.deliver, "WHISPER", n.N.me, p.msg)
				end
			end
			out.sent[n.short] = pieces
		end)
	end
	As(R, R.pump, 200)
	out.relay, out.snapshot = Census(R, As, rival), As(R, R.N.Data.GlobalCensusPayload)
	-- What the relay handed each reporter, then its snapshot as it reaches them (hop M).
	for _, n in ipairs({ K, E }) do
		for _, p in ipairs(R.sent) do
			if p.dist == "WHISPER" and ns.ShortName(p.target or "") == n.short then As(n, n.deliver, "WHISPER", R.N.me, p.msg) end
		end
		As(n, n.N.Relay.TakeVia, "M", R.N.me, R.N.me, out.snapshot)
		out[n.short] = Census(n, As, rival)
	end
	out.nodes = { R = R, A = A, B = B, K = K, E = E }
	return out
end

-- Fails before: a 1.6.0 client took the rival guild for an Olympus guild as 1.5.9 does (its member sent
-- its census, the relay and the 1.6.0 master counted it, the relay's snapshot carried it).
test("federation names (1.6.0): a guild named as a comparison through a relay with 1.5.9 and 1.6.0 clients: its 1.6.0 member sends nothing, 1.6.0 clients and a 1.6.0 relay's snapshot leave it out; 1.5.9 clients still count it while a 1.5.9 member reports it", function()
	World(function(Node, As)
		local OLDS = { relay = "1.5.9", rival59 = "1.5.9", rival60 = "1.5.9", knights = "1.5.9", embers = "1.5.9" }
		-- Before: every client on the one rule (1.5.9, and the 1.6.0 candidate before this change).
		local before = Run(Node, As, OLDS)
		eq(before.member["Rival Member"], true, "before: the rival's member was an Olympus member")
		eq(before.sent["Rival Lead"], 3); eq(before.sent["Rival Member"], 3, "before: its census sent (3 pieces)")
		eq(before.relay.guilds, 4); eq(before.relay.characters, 560, "before: 200 + 120 + 150 + 90")
		assert(before.relay.rival, "before: the relay counted it")
		eq(Carries(before.snapshot), true, "before: the relay's snapshot carried it")
		eq(before["Knight Lead"].guilds, 4); eq(before["Knight Lead"].characters, 560); assert(before["Knight Lead"].rival)
		eq(before["Ember Lead"].guilds, 4); eq(before["Ember Lead"].characters, 560); assert(before["Ember Lead"].rival)
		-- After, the relay on 1.6.0.
		local after = Run(Node, As, { relay = "1.6.0", rival59 = "1.5.9", rival60 = "1.6.0", knights = "1.6.0", embers = "1.5.9" })
		eq(after.member["Rival Lead"], true, "its 1.5.9 member still takes himself for one")
		eq(after.member["Rival Member"], false, "its 1.6.0 member: no Olympus member")
		eq(after.sent["Rival Lead"], 3); eq(after.sent["Rival Member"], 0, "nothing of the 1.6.0 member's goes out")
		eq(after.sent["Knight Lead"], 3); eq(after.sent["Ember Lead"], 3, "the Olympus guilds report as before")
		eq(after.relay.guilds, 3); eq(after.relay.characters, 440, "200 + 150 + 90"); eq(after.relay.rival, nil)
		eq(Carries(after.snapshot), false, "a 1.6.0 relay's snapshot leaves it out")
		eq(after["Knight Lead"].guilds, 3); eq(after["Knight Lead"].characters, 440); eq(after["Knight Lead"].rival, nil)
		eq(after["Ember Lead"].guilds, 4, "a 1.5.9 client still counts it: the relay handed it the 1.5.9 member's census")
		eq(after["Ember Lead"].characters, 560); assert(after["Ember Lead"].rival)
		-- After, the relay still on 1.5.9: its snapshot carries the guild, and a 1.6.0 client leaves it out.
		local mixed = Run(Node, As, { relay = "1.5.9", rival59 = "1.5.9", rival60 = "1.6.0", knights = "1.6.0", embers = "1.5.9" })
		eq(mixed.sent["Rival Member"], 0)
		assert(mixed.relay.rival, "a 1.5.9 relay counts it"); eq(Carries(mixed.snapshot), true)
		eq(mixed["Knight Lead"].guilds, 3); eq(mixed["Knight Lead"].characters, 440)
		eq(mixed["Knight Lead"].rival, nil, "neither the handed report nor the snapshot's row")
		eq(mixed["Ember Lead"].guilds, 4); assert(mixed["Ember Lead"].rival)
	end)
end)

-- A verifier's client (Verify.lua in a namespace of its own over the harness's, as tests/verify.lua's
-- world loads it), whose census and saved words hold both guilds, the rival (RIVAL or the guild named)
-- approved: its list and its answer (GV~S), and whether the approval is still held once the client's
-- session tick prunes its saved words (Verify.Prune, which drops an approval of no Olympus guild).
local function Verifier(version, rival)
	rival = rival or RIVAL
	local now = 1800000000
	local dialogs = {}
	for k, v in pairs(StaticPopupDialogs) do dialogs[k] = v end
	local c = setmetatable({ me = "Max Ran-Realm", realm = "Realm", L = setmetatable({}, { __index = ns.L }), RealmPages = {},
		rdb = { guilds = { [rival] = { leader = "Rival Lead", realm = "Realm", total = 120, online = 9, t = now },
			[DAWN] = { leader = "Dawn Lead", realm = "Realm", total = 200, online = 6, t = now } },
			verify = { seen = {}, told = {}, requests = {},
				list = { [ns.Fold(rival)] = { k = "A", at = now - 1800, guild = rival, gm = "Rival Lead-Realm", by = "Max Ran-Realm" } },
				start = { [ns.Fold(rival)] = { at = now - 3600, guild = rival, by = "Max Ran-Realm", last = now },
					[ns.Fold(DAWN)] = { at = now - 3600, guild = DAWN, by = "Max Ran-Realm", last = now } } } } }, { __index = ns })
	c.Fire, c.On, c.RegisterEvent, c.Print = function() end, function() end, function() end, function() end
	c.After, c.Every, c.Now = function() end, function() return { Cancel = function() end } end, function() return now end
	c.UI = { Refresh = function() end }
	c.Comm = { Handle = function() end, Send = function() return true end, SendChunked = function() return true end }
	local savedGuild, savedIn = GetGuildInfo, IsInGuild
	GetGuildInfo, IsInGuild = function() return DAWN, "Member", 3 end, function() return true end -- (the verifier's own guild)
	local ok, out = pcall(function()
		if version == "1.5.9" then assert(loadfile(OLD))("Olympus", c) end
		assert(loadfile(extra.addon .. "Locales/VerifyText.lua"))("Olympus", c)
		assert(loadfile(extra.addon .. "Verify.lua"))("Olympus", c)
		c.Verify.Clock = function() return now end
		local pending, verified = c.Verify.Pending(now)
		local names = {}
		for _, e in ipairs(pending) do names[#names + 1] = e.guild .. ":" .. e.status end
		for _, e in ipairs(verified) do names[#names + 1] = e.guild .. ":" .. e.status end
		table.sort(names)
		local answer = c.Verify.Payload(now)
		c.Verify.Prune(now)
		return { list = table.concat(names, ","), answer = answer, approved = c.rdb.verify.list[ns.Fold(rival)] ~= nil }
	end)
	GetGuildInfo, IsInGuild = savedGuild, savedIn
	for k in pairs(StaticPopupDialogs) do StaticPopupDialogs[k] = dialogs[k] end
	if not ok then error(out, 0) end
	return out
end

-- Fails before: 1.6.0 kept counting it after the update.
test("federation names (1.6.0): a client that counted such a guild drops it once on 1.6.0: its census rows and totals, the rows it passes on, a new report of it; the saved row waits out its week unseen; the verifiers' list and answer, the Join page's /who list and route", function()
	World(function(Node, As)
		-- A session on 1.5.9: the rival's census reached the Knights' master, handed on by a 1.5.9 relay with
		-- its snapshot.
		local first = Run(Node, As, { relay = "1.5.9", rival59 = "1.5.9", rival60 = "1.5.9", knights = "1.5.9", embers = "1.5.9" })
		local K, A = first.nodes.K, first.nodes.A
		assert(first["Knight Lead"].rival, "counted on 1.5.9")
		local rdb = K.N.rdb
		assert(type(rdb.guilds[RIVAL]) == "table" and type(rdb.censusGlobal[RIVAL:lower()]) == "table", "held direct and relayed")
		-- The update: the same character's next login on 1.6.0, with its saved variables.
		local K2 = Node("Knight Lead", KNIGHTS, "1.6.0", 150, K)
		local after = Census(K2, As)
		eq(after.rival, nil); eq(after.guilds, 3); eq(after.characters, 440, "the other guilds as they were")
		eq(rdb.censusGlobal[RIVAL:lower()], nil, "the relayed row went at login")
		local row = rdb.guilds[RIVAL]
		eq(type(row), "table", "the saved direct row waits out Data.KEEP, shown nowhere")
		eq(Carries(As(K2, K2.N.Data.GlobalCensusPayload)), false, "nor passed on")
		-- A minute later the relay hands it the rival's 1.5.9 member's next census and its own (Olympus
		-- Dawn's): the Dawn's is taken, the rival's refused.
		local R = first.nodes.R
		local t, dawn = row.t, rdb.guilds[DAWN].t
		K2.N.clock = K2.N.clock + 60
		for i, n in ipairs({ A, R }) do
			n.N.clock = K2.N.clock
			local report = As(n, n.N.Roster.Scan)
			for _, piece in ipairs(ns.Codec.Chunk(ns.Codec.EncodeReport(report), "7" .. i)) do
				As(K2, K2.N.Relay.TakeVia, "M", R.N.me, n.N.me, piece)
			end
		end
		eq(rdb.guilds[DAWN].t, dawn + 60, "the Dawn's census taken")
		eq(rdb.guilds[RIVAL].t, t, "the rival's refused"); eq(Census(K2, As).rival, nil)
	end)
	local v59, v60 = Verifier("1.5.9"), Verifier("1.6.0")
	eq(v59.list, DAWN .. ":pending," .. RIVAL .. ":verified", "before: on the verifiers' list, approved")
	eq(v59.answer:find(RIVAL, 1, true) ~= nil, true, "before: its approval and start in a verifier's answer")
	eq(v59.approved, true, "before: its approval held")
	eq(v60.list, DAWN .. ":pending", "after: off the list")
	eq(v60.answer:find(RIVAL, 1, true), nil, "after: neither its approval nor its start in the answer")
	eq(v60.approved, false, "after: its approval dropped at the next tick")
	-- A member's route answer (J2) naming it, on the Join page of this harness's client: before its update
	-- (1.5.9's rule) and after it.
	local old = setmetatable({}, { __index = ns })
	assert(loadfile(OLD))("Olympus", old)
	local current = { IsFederation = ns.IsFederation, NamedOlympus = ns.NamedOlympus }
	local function OnRule(rule)
		ns.IsFederation, ns.NamedOlympus = rule.IsFederation, rule.NamedOlympus
	end
	local J2 = ("J2~y~~0~%s=880=Rival Lead;%s=800=Dawn Lead"):format(RIVAL, DAWN)
	local function Routed()
		local names = {}
		for _, e in ipairs(ns.Recruit.ParseRoute(J2).list) do names[#names + 1] = e.name end
		return table.concat(names, ",")
	end
	OnRule(old)
	local ok, routed = pcall(Routed)
	OnRule(current)
	if not ok then error(routed, 0) end
	eq(routed, RIVAL .. "," .. DAWN, "before: a route to it on the Join page")
	eq(Routed(), DAWN, "after: no route to it")
	-- The Join page's /who: a search for Olympus lists the rival's members too (its name holds the word);
	-- the page lists the Olympus guilds' alone.
	extra.WithWho(function(server)
		local function Found()
			local names = {}
			for _, g in ipairs(ns.Recruit.Guilds()) do names[#names + 1] = g.name end
			table.sort(names)
			return table.concat(names, ",")
		end
		local rows = { { "Rival Lead", RIVAL, 30, "WARRIOR" }, { "Rival Member", RIVAL, 22, "MAGE" }, { "Dawn Lead", DAWN, 40, "PRIEST" } }
		OnRule(old)
		local okWho, errWho = pcall(function()
			eq(ns.Recruit.Search(), true)
			server.Answer(rows)
			eq(Found(), DAWN .. "," .. RIVAL, "before: the rival on the Join page")
			eq(ns.Data.Seen()[RIVAL] ~= nil, true, "and among the census's /who sightings")
		end)
		OnRule(current)
		if not okWho then error(errWho, 0) end
		-- The next session (the update): the round of /who searches starts again; the sightings are saved.
		ns.Who.Reset()
		ns.Recruit.found = {}
		server.Click()
		server.Answer(rows)
		eq(Found(), DAWN, "after: the Olympus guild alone")
		local s = ns.Data.Summary()
		for _, e in ipairs(s.seen) do assert(e.name ~= RIVAL, "after: no sighting of it listed") end
	end)
end)

-- 1.6.0, the review of the rule above: a guild whose name only looks like one counts as on 1.5.9. Here a
-- word glued in front that only starts like "no" or "than" ("NoobOlympus", "ThanosOlympus": Olympus does
-- not start at the O after it), and a "than" with another word before Olympus, its own phrase ("Older Than
-- Time Olympus"). Each takes the rival's place in Run (its members on 1.5.9 and 1.6.0, the relay and the
-- Knights' master on 1.6.0, the Embers' on 1.5.9), then a 1.6.0 verifier that approved it.
-- Fails before: 1.6.0 shut such a guild out as it does the rival (its 1.6.0 member no member and silent,
-- the relay and the 1.6.0 master without it, its approval dropped).
local LOOKALIKES = { "NoobOlympus", "ThanosOlympus", "Older Than Time Olympus" }
local function Counted(Node, As, guild)
	local r = Run(Node, As, { guild = guild, relay = "1.6.0", rival59 = "1.5.9", rival60 = "1.6.0", knights = "1.6.0", embers = "1.5.9" })
	local function Seen(c) return ("%d guilds %d characters%s"):format(c.guilds, c.characters, c.rival and " with it" or "") end
	return ("members %s/%s, sent %d/%d; relay %s, its snapshot with it %s; 1.6.0 master %s; 1.5.9 master %s"):format(
		tostring(r.member["Rival Lead"]), tostring(r.member["Rival Member"]), r.sent["Rival Lead"], r.sent["Rival Member"],
		Seen(r.relay), tostring(Carries(r.snapshot, guild)), Seen(r["Knight Lead"]), Seen(r["Ember Lead"]))
end
test("federation names (1.6.0): a guild whose name only looks like a comparison or a denial (NoobOlympus, ThanosOlympus, Older Than Time Olympus) counts through a relay with 1.5.9 and 1.6.0 clients as on 1.5.9: both its members report, the relay, its snapshot and every client count it, a 1.6.0 verifier keeps its approval", function()
	local seen = {}
	World(function(Node, As)
		for _, guild in ipairs(LOOKALIKES) do seen[guild] = Counted(Node, As, guild) end
	end)
	for _, guild in ipairs(LOOKALIKES) do
		local v = Verifier("1.6.0", guild)
		local list = { guild .. ":verified", DAWN .. ":pending" }
		table.sort(list)
		eq(("%s; verifier's list %s, approval held %s, in its answer %s"):format(seen[guild], v.list, tostring(v.approved),
			tostring(v.answer:find(guild, 1, true) ~= nil)),
			"members true/true, sent 3/3; relay 4 guilds 560 characters with it, its snapshot with it true; "
			.. "1.6.0 master 4 guilds 560 characters with it; 1.5.9 master 4 guilds 560 characters with it; "
			.. "verifier's list " .. table.concat(list, ",") .. ", approval held true, in its answer true", guild)
	end
end)
