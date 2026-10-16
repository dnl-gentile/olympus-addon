-- 1.2.4: the Olympus API for other addons (Olympus/API.lua, docs/API.md) on the test world: the
-- privacy page's line for each addon, what a granted addon reads (copies of the pages' own rows,
-- field by field), its callbacks, and what never leaves. Every name is invented.
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

-- Another addon the game has installed on that client: its TOC's Title, loaded.
local function Install(c, name, title)
	c.addonsBase = c.addonsBase or c.globals.C_AddOns
	c.addons = c.addons or {}
	c.addons[name:lower()] = title or name
	local base = c.addonsBase
	c.globals.C_AddOns = setmetatable({
		IsAddOnLoaded = function(n)
			if type(n) == "string" and c.addons[n:lower()] then return true end
			return base.IsAddOnLoaded(n)
		end,
		GetAddOnMetadata = function(n, field)
			if type(n) == "string" and c.addons[n:lower()] then return field == "Title" and c.addons[n:lower()] or nil end
			return base.GetAddOnMetadata(n, field)
		end,
	}, { __index = base })
end

-- API.lua (and its words) loaded into the client as the TOC loads it, after the boards it reads:
-- with Wanted.lua too (the core's board, which the world's clients do not load), its tab kept off
-- the harness's window. The global OlympusAPI is the client's (c.OlympusAPI), the host's put back.
local function LoadAPI(w, c, wanted)
	local was = rawget(_G, "OlympusAPI")
	w:As(c, function()
		if wanted ~= false then
			local ui = rawget(c.ns, "UI")
			rawset(c.ns, "UI", { AddTab = function() end })
			assert(loadfile(H.ADDON_DIR .. "Wanted.lua"))("Olympus", c.ns)
			rawset(c.ns, "UI", ui)
		end
		assert(loadfile(H.ADDON_DIR .. "Locales/APIText.lua"))("Olympus", c.ns)
		assert(loadfile(H.ADDON_DIR .. "API.lua"))("Olympus", c.ns)
	end)
	c.OlympusAPI = rawget(_G, "OlympusAPI")
	rawset(_G, "OlympusAPI", was)
	assert(c.OlympusAPI and c.OlympusAPI ~= was, "the client's own OlympusAPI")
	return c.ns.API
end

-- A handle's method, run as its client.
local function Do(w, c, handle, method, ...)
	return w:As(c, handle[method], handle, ...)
end

-- The UI-side contract, kept deliberately generic here: it records the opaque owner slot API.lua
-- routes and behaves like the window host without creating a frame in these API tests.
local function SurfaceHost(c)
	c.ns.UI = c.ns.UI or {}
	c.ns.UI.API_SURFACE_LIMIT = 1
	local state = { calls = {}, surfaces = {}, open = {}, count = 0 }
	local function Called(op, owner, spec)
		state.calls[#state.calls + 1] = { op = op, owner = owner, spec = spec }
	end
	function c.ns.UI.RegisterAPISurface(owner, spec)
		Called("register", owner, spec)
		if state.surfaces[owner] then return false, "registered" end
		if state.count >= c.ns.UI.API_SURFACE_LIMIT then return false, "surface-full" end
		if type(spec) ~= "table" then return false, "invalid-spec" end
		if type(spec.label) ~= "string" or spec.label == "" or #spec.label > 96 then return false, "invalid-label" end
		local icon = spec.icon
		if not ((type(icon) == "string" and icon ~= "") or (type(icon) == "number" and icon > 0)) then
			return false, "invalid-icon"
		end
		if type(spec.build) ~= "function" then return false, "invalid-build" end
		state.surfaces[owner] = spec
		state.count = state.count + 1
		return true
	end
	function c.ns.UI.OpenAPISurface(owner)
		Called("open", owner)
		if not state.surfaces[owner] then return false, "unregistered" end
		state.open[owner] = true
		return true
	end
	function c.ns.UI.ToggleAPISurface(owner)
		Called("toggle", owner)
		if not state.surfaces[owner] then return false, "unregistered" end
		state.open[owner] = not state.open[owner]
		return true
	end
	function c.ns.UI.RefreshAPISurface(owner)
		Called("refresh", owner)
		if not state.surfaces[owner] then return false, "unregistered" end
		return true
	end
	function c.ns.UI.IsAPISurfaceOpen(owner)
		Called("shown", owner)
		if not state.surfaces[owner] then return false, "unregistered" end
		return state.open[owner] == true
	end
	return state
end

local function Keys(t)
	local out = {}
	for k in pairs(t or {}) do out[#out + 1] = tostring(k) end
	table.sort(out)
	return table.concat(out, ",")
end

-- The Wanted store as Wanted.lua keeps it (ns.rdb.wanted): one Horde player with an open bounty,
-- the deaths that made it (a member's name and where he died), a claim, a sighting, who added
-- him; one taken off; two Slayers, one with a GUID.
local SECRET = { victim = "Orla Weft-Emberfall", zone = "Lakeshire Docks", sighting = "Redridge Canyons", by = "Hidden Reviewer-Emberfall",
	slayerGuid = "Player-4001-0BADF00D", source = "evidence-source-x" }
local HORDE = { name = "Grashk Bloodfen-Emberfall", guid = "Player-4002-00C0FFEE" }
local function PlantWanted(w, c)
	local W = c.ns.Wanted
	local month = w:As(c, W.MonthNow)
	local at = w.clock - 600
	c.rdb.wanted = {
		version = W.VERSION, scoreVersion = W.SCORE_VERSION, group = c.ns.group, faction = c.ns.faction, seq = 3, aliases = {}, slayerAliases = {}, baseSlayers = {},
		evidence = {}, seen = {}, seenOrder = {}, recent = {}, audit = {}, voids = {},
		targets = {
			["g:" .. HORDE.guid] = { key = "g:" .. HORDE.guid, name = HORDE.name, realm = "Emberfall", guid = HORDE.guid, active = true,
				addedAt = at, addedBy = SECRET.by, source = SECRET.source, current = 42, lifetimeKills = 3, cycle = 2, openSince = at, lastDeath = at,
				lastSighting = { zone = SECRET.sighting, at = at, precision = "consented", evidence = "SELF_DEATH" }, victimOverflow = 0,
				victims = { { id = "v1", name = SECRET.victim, zone = SECRET.zone, at = at, evidence = "SELF_DEATH", precision = "approximate", points = 42 } },
				claims = { { id = "c1", slayer = N.fighterA, points = 70, cycle = 1, at = at, evidence = "PARTY_KILL", level = 60 } } },
			["g:Player-4002-00000BAD"] = { key = "g:Player-4002-00000BAD", name = "Morka Gutrend-Emberfall", guid = "Player-4002-00000BAD",
				active = false, removedBy = SECRET.by, removedAt = at, current = 0, lifetimeKills = 0, cycle = 1, victims = {}, claims = {} },
		},
		slayers = {
			["g:" .. SECRET.slayerGuid] = { key = "g:" .. SECRET.slayerGuid, name = N.fighterA, guid = SECRET.slayerGuid, total = 70, claims = 1,
				reachedAt = at, lastAt = at, months = { [month] = 70 }, monthAt = { [month] = at }, monthClaims = { [month] = 1 } },
			["n:selka drummond-emberfall"] = { key = "n:selka drummond-emberfall", name = N.fighterB, total = 20, claims = 1,
				reachedAt = at, lastAt = at, months = { [month - 1] = 20 }, monthAt = { [month - 1] = at }, monthClaims = { [month - 1] = 1 } },
		},
	}
end

-- A world with the King, the Treasurer, two fighters and a member (Lida Fenn, the viewer) whose
-- client has the API; the Treasurer's word names the donors (Lida third, all time).
local function Setup(opts)
	opts = opts or {}
	local w, cast = W3.New({ world = opts.world, more = { { "treasurer", N.treasurer, { guild = World.KING_GUILD } } } })
	local viewer = cast.spectator
	local now = w.clock
	-- Only donor presentation is synthetic. Keep the real Treasury behind this overlay:
	-- the client's live Dues ticker still reads its DevView, Book and native pin methods.
	local treasury = cast.treasurer.ns.Treasury
	rawset(cast.treasurer.ns, "Treasury", setmetatable({ DonationRecords = function()
		return { { name = "Torvin Hale", money = 500000, t = now - 40 * 86400 }, { name = "Selka Drummond", money = 300000, t = now - 40 * 86400 },
			{ name = "Lida Fenn", money = 100000, t = now - 40 * 86400 } }
	end, RankingShown = function() return false end }, { __index = treasury }))
	eq(W3.M(w, cast.treasurer, "HonorsNet").SendDonors(true), true)
	w:Run(0)
	local API = LoadAPI(w, viewer, opts.wanted)
	if opts.wanted ~= false then PlantWanted(w, viewer) end
	return w, cast, viewer, API
end

-- The client's privacy page line for an addon key.
local function Line(w, c, key)
	for _, item in ipairs(w:As(c, c.ns.Consent.Items)) do if item.key == key then return item end end
	return nil
end

print("The Olympus API (1.2.4)")

test("1.2.4 the API: donor fixture overrides preserve the actual Treasury and native Dues tickers", function()
	local w, cast = Setup()
	w:Run(61)
	W3.NoErrors(w)
	w:As(cast.treasurer, function()
		local T = cast.treasurer.ns.Treasury
		eq(T.DonationRecords()[3].name, "Lida Fenn", "only the intended donor presentation is synthetic")
		eq(T.RankingShown(), false)
		local book = T.Book()
		assert(book and book.duesNativeTracking, "the actual pinned character's ticker starts its native tracker")
		eq(book.duesNativeTracking.issuer, cast.treasurer.name)
		eq(book.duesNativeTracking.pin, T.TreasurerPin(cast.treasurer.name))
	end)
end)

test("1.2.4 the API: VERSION and Has; Register only for an installed addon, once a session, never Olympus's own name; an unregistered addon has no way in", function()
	local w, cast, viewer, API = Setup()
	SurfaceHost(viewer)
	local O = viewer.OlympusAPI
	eq(O.VERSION, 1)
	eq(O.SURFACE_LIMIT, 1)
	eq(API.VERSION, 1)
	eq(API.SURFACE_LIMIT, O.SURFACE_LIMIT)
	for _, f in ipairs({ "wanted", "rankings", "rankings.slayers", "rankings.donors", "rankings.church", "rankings.games", "profile", "callbacks",
		"ui.surface", "WANTED_CHANGED", "RANKINGS_CHANGED", "PROFILE_CHANGED", "PERMISSION_CHANGED" }) do
		eq(w:As(viewer, O.Has, f), true, f)
	end
	eq(w:As(viewer, O.Has, "census"), false, "no census feature"); eq(w:As(viewer, O.Has, nil), false)
	-- The global itself is read-only: an addon cannot replace Register for the others.
	local ok = pcall(function() O.Register = function() end end)
	eq(ok, false, "OlympusAPI is read-only")
	eq(getmetatable(O), false, "its metatable is locked")
	-- Nothing but Register gives a way in: no data function on the global.
	eq(O.GetWanted, nil); eq(O.GetRankings, nil); eq(O.GetProfile, nil); eq(O.On, nil); eq(O.RegisterSurface, nil); eq(O.UI, nil)
	eq(w:As(viewer, function() return rawget(_G, "OlympusUI") end), nil, "no second UI global")
	local h, why = w:As(viewer, O.Register, "MissingAddon")
	eq(h, nil); eq(why, "unknown", "a name the game has not installed")
	eq(select(2, w:As(viewer, O.Register, "Olympus")), "self")
	eq(select(2, w:As(viewer, O.Register, "olympus_arena")), "self")
	eq(select(2, w:As(viewer, O.Register, 42)), "name")
	eq(select(2, w:As(viewer, O.Register, "")), "name")
	eq(select(2, w:As(viewer, O.Register, "Bad|cffName")), "name")
	Install(viewer, "MapPins", "|cff33ff99Map|r Pins |TInterface\\Icons\\X:0|t")
	local api = w:As(viewer, O.Register, "MapPins")
	assert(type(api) == "table", "the installed addon's handle")
	eq(Do(w, viewer, api, "Name"), "MapPins")
	-- Its handle is its own and read-only; dot calls work as colon calls.
	eq(pcall(function() api.GetWanted = function() return {} end end), false, "the handle is read-only")
	eq(pcall(function() api.RegisterSurface = function() return true end end), false, "the surface methods are read-only too")
	eq(w:As(viewer, api.Status), "pending")
	h, why = w:As(viewer, O.Register, "mappins")
	eq(h, nil); eq(why, "taken", "a second Register of that name this session gets nothing")
	-- The privacy page's line: the addon's title, plain (its colour and texture codes gone).
	local item = Line(w, viewer, "api:mappins")
	assert(item, "its line on the privacy page")
	eq(item.explicit, true, "its own line is explicit, while the clearly labelled Authorize all may answer it")
	eq(item.label(), viewer.ns.L.API_CONSENT_LABEL:format("Map Pins"))
	eq(item.text, "API_CONSENT_TEXT")
	-- MAX_ADDONS a session.
	for i = 1, API.MAX_ADDONS - 1 do Install(viewer, "Extra" .. i) eq(type(w:As(viewer, O.Register, "Extra" .. i)), "table") end
	Install(viewer, "OneTooMany")
	eq(select(2, w:As(viewer, O.Register, "OneTooMany")), "full")
	W3.NoErrors(w)
end)

test("1.2.4 the API: one shared UI surface, opaque ownership, retry after rejection, and lifecycle calls routed to its owner", function()
	local w, cast, viewer = Setup()
	local host = SurfaceHost(viewer)
	local O = viewer.OlympusAPI
	Install(viewer, "MapPins", "Map Pins")
	Install(viewer, "BountyBoard", "Bounty Board")
	local first = w:As(viewer, O.Register, "MapPins")
	local second = w:As(viewer, O.Register, "BountyBoard")

	for _, method in ipairs({ "OpenSurface", "ToggleSurface", "RefreshSurface", "IsSurfaceOpen" }) do
		local ok, why = Do(w, viewer, first, method)
		eq(ok, false, method); eq(why, "unregistered", method)
	end
	eq(#host.calls, 0, "nothing reaches UI before that handle registers its surface")

	local ok, why = Do(w, viewer, first, "RegisterSurface", { label = "" })
	eq(ok, false); eq(why, "invalid-label", "host validation is returned")
	eq(Do(w, viewer, first, "RegisterSurface", { label = "Map tools", icon = "Interface\\Icons\\INV_Misc_Map_01", build = function() end }), true,
		"a rejected specification does not consume the handle's one surface")
	local firstOwner = host.calls[2].owner
	assert(type(firstOwner) == "string" and firstOwner ~= "", "an internal owner slot")
	for _, private in ipairs({ "MapPins", "mappins", "api:mappins" }) do
		eq(firstOwner:lower():find(private:lower(), 1, true), nil, "the owner does not identify its caller")
	end
	eq(first.surfaceOwner, nil, "the owner is not exposed by the handle")
	local calls = #host.calls
	ok, why = Do(w, viewer, first, "RegisterSurface", { label = "Another page" })
	eq(ok, false); eq(why, "registered"); eq(#host.calls, calls, "a second surface is refused before UI")

	ok, why = Do(w, viewer, second, "RegisterSurface", {
		label = "Bounty tools", icon = "Interface\\Icons\\INV_Misc_Note_01", build = function() end,
	})
	eq(ok, false); eq(why, "surface-full", "data handles remain available after the one shared surface slot is used")
	local secondOwner = host.calls[#host.calls].owner
	assert(secondOwner ~= firstOwner, "each handle is still assigned a different opaque owner slot")
	for _, private in ipairs({ "BountyBoard", "bountyboard", "api:bountyboard" }) do
		eq(secondOwner:lower():find(private:lower(), 1, true), nil, "the refused owner's slot does not identify its caller")
	end

	eq(Do(w, viewer, first, "IsSurfaceOpen"), false)
	eq(Do(w, viewer, first, "OpenSurface"), true)
	eq(Do(w, viewer, first, "IsSurfaceOpen"), true)
	eq(select(2, Do(w, viewer, second, "IsSurfaceOpen")), "unregistered", "the refused handle owns no surface")
	eq(Do(w, viewer, first, "RefreshSurface"), true)
	eq(Do(w, viewer, first, "ToggleSurface"), true)
	eq(Do(w, viewer, first, "IsSurfaceOpen"), false)
	for _, call in ipairs(host.calls) do
		assert(call.owner == firstOwner or call.owner == secondOwner, "every call carries an assigned owner")
	end
	W3.NoErrors(w)
end)

test("1.2.4 the API: UI surfaces work while data consent is pending or refused; data reads remain blocked", function()
	local w, cast, viewer = Setup()
	SurfaceHost(viewer)
	local O, C = viewer.OlympusAPI, viewer.Consent
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, O.Register, "MapPins")
	eq(Do(w, viewer, api, "Status"), "pending")
	eq(Do(w, viewer, api, "RegisterSurface", { label = "Map tools", icon = "Interface\\Icons\\INV_Misc_Map_01", build = function() end }), true)
	eq(Do(w, viewer, api, "OpenSurface"), true)
	eq(Do(w, viewer, api, "IsSurfaceOpen"), true)
	local data, why = Do(w, viewer, api, "GetProfile")
	eq(data, nil); eq(why, "pending", "surface access does not grant data access")

	eq(w:As(viewer, C.Choose, "api:mappins", false), true)
	eq(Do(w, viewer, api, "Status"), "refused")
	eq(Do(w, viewer, api, "RefreshSurface"), true)
	eq(Do(w, viewer, api, "ToggleSurface"), true)
	eq(Do(w, viewer, api, "IsSurfaceOpen"), false)
	data, why = Do(w, viewer, api, "GetWanted")
	eq(data, nil); eq(why, "refused", "refused data stays blocked")
	W3.NoErrors(w)
end)

test("1.2.4 the API: nothing before a deliberate authorization nor after No; Keep current choices grants nothing and Authorize all grants visible pending lines", function()
	local w, cast, viewer, API = Setup()
	local O, C = viewer.OlympusAPI, viewer.Consent
	-- Every line the page had shown already (the player closed it): no question waits.
	w:As(viewer, function() C.Show() C.Hide() end)
	eq(w:As(viewer, C.Waiting), false)
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, O.Register, "MapPins")
	local told = {}
	eq(Do(w, viewer, api, "On", "PERMISSION_CHANGED", function(event, status) told[#told + 1] = event .. ":" .. tostring(status) end), true)
	eq(w:As(viewer, C.Waiting), true, "a new question: the addon's line")
	eq(w:As(viewer, C.Ask, "login"), true, "the page opens by itself for it")
	w:As(viewer, C.Hide)
	eq(w:As(viewer, C.Ask, "login"), false, "once: closed unanswered, it never opens by itself again for it")
	for _, m in ipairs({ "GetWanted", "GetRankings", "GetProfile" }) do
		local data, why = Do(w, viewer, api, m)
		eq(data, nil, m); eq(why, "pending", m)
	end
	-- The secondary action closes without granting this explicit line.
	w:As(viewer, function() C.Show() C.KeepCurrent() end)
	eq(Do(w, viewer, api, "Status"), "pending", "Keep current choices grants nothing")
	eq(Do(w, viewer, api, "GetWanted"), nil)
	eq(#told, 0)
	-- No: nothing, and the addon is told.
	eq(w:As(viewer, C.Choose, "api:mappins", false), true)
	eq(Do(w, viewer, api, "Status"), "refused")
	local data, why = Do(w, viewer, api, "GetProfile")
	eq(data, nil); eq(why, "refused")
	eq(told[1], "PERMISSION_CHANGED:refused")
	-- Yes: it reads.
	eq(w:As(viewer, C.Choose, "api:mappins", true), true)
	eq(Do(w, viewer, api, "Status"), "granted")
	eq(told[2], "PERMISSION_CHANGED:granted")
	assert(type(Do(w, viewer, api, "GetWanted")) == "table", "granted: the Wanted rows")
	eq(viewer.db.apiAddons.mappins.on, true); eq(viewer.db.apiAddons.mappins.v, API.CONSENT_VERSION)
	-- Another addon is asked on its own: the first one's Yes is not its.
	Install(viewer, "BountyBoard", "Bounty Board")
	local other = w:As(viewer, O.Register, "BountyBoard")
	eq(Do(w, viewer, other, "Status"), "pending")
	eq(Do(w, viewer, other, "GetWanted"), nil)
	w:As(viewer, function() C.Show() C.AuthorizePending() end)
	eq(Do(w, viewer, other, "Status"), "granted", "Authorize all deliberately grants the visible pending addon")
	-- The next session: the account's answer stands, and the page asks nothing again for it.
	w:Logout(viewer); w:Login(viewer)
	W3.Rules(w, viewer)
	Install(viewer, "MapPins", "Map Pins")
	LoadAPI(w, viewer)
	PlantWanted(w, viewer)
	api = w:As(viewer, viewer.OlympusAPI.Register, "MapPins")
	eq(Do(w, viewer, api, "Status"), "granted", "kept for the account")
	eq(w:As(viewer, viewer.Consent.Answer, "api:mappins"), true)
	eq(w:As(viewer, viewer.Consent.Waiting), false, "asked once, for good")
	-- A Yes given for what an older API gave is asked again.
	viewer.db.apiAddons.mappins.v = API.CONSENT_VERSION - 1
	eq(Do(w, viewer, api, "Status"), "pending")
	eq(Do(w, viewer, api, "GetWanted"), nil)
	W3.NoErrors(w)
end)

test("1.2.4 the API: a granted addon gets copies of exactly what the pages show: the Wanted rows, the Slayers boards, the donors' and the Church's top three, the published games; its own profile; outside an Olympus guild, only that", function()
	local w, cast, viewer, API = Setup()
	local O, C = viewer.OlympusAPI, viewer.Consent
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, O.Register, "MapPins")
	w:As(viewer, C.Choose, "api:mappins", true)
	-- Wanted: the active entry alone (the taken-off one stays off), the fields its row shows.
	local rows = Do(w, viewer, api, "GetWanted")
	eq(#rows, 1)
	eq(Keys(rows[1]), "bounty,cycle,guid,kills,name,place")
	eq(rows[1].name, HORDE.name); eq(rows[1].guid, HORDE.guid); eq(rows[1].bounty, 42); eq(rows[1].kills, 3); eq(rows[1].cycle, 2); eq(rows[1].place, 1)
	-- What the Wanted tab lists, the same order: Wanted.Targets (the page's own call).
	local page = w:As(viewer, viewer.ns.Wanted.Targets, true)
	eq(page[1].name, rows[1].name); eq(page[1].current, rows[1].bounty)
	-- Rankings: every kind; the Slayers' month and all time, as the tab's boards.
	local r = Do(w, viewer, api, "GetRankings")
	-- (Review of 1.2.4: no donors while the King keeps the Treasury's ranking from the army, the
	-- default; this test asked for them at once before.)
	eq(Keys(r), "games,slayers")
	eq(Keys(r.slayers), "all,month")
	eq(#r.slayers.month, 1); eq(r.slayers.month[1].name, N.fighterA); eq(r.slayers.month[1].points, 70)
	eq(Keys(r.slayers.month[1]), "claims,name,place,points")
	eq(#r.slayers.all, 2); eq(r.slayers.all[2].name, N.fighterB); eq(r.slayers.all[2].place, 2)
	eq(r.slayers.signed, nil, "no signed top three held")
	eq(r.donors, nil, "the Treasury's ranking kept from the army: no donors (below once shown)")
	-- The games: none the King kept to the staff.
	eq(Keys(r.games), "")
	eq(Do(w, viewer, api, "GetRankings", "games").lottery, nil)
	-- The Church's top three while its public ranking is open (ChurchCount.Top3), nothing else of it.
	rawset(viewer.ns, "ChurchCount", { Top3 = function()
		return { at = w.clock, by = "Keeper Name", apostles = { N.bettor2 }, missionaries = { N.bettor3, viewer.name } }
	end })
	local church = Do(w, viewer, api, "GetRankings", "church")
	eq(Keys(church), "apostles,missionaries"); eq(church.missionaries[2], viewer.name); eq(church.apostles[1], N.bettor2)
	rawset(viewer.ns, "ChurchCount", { Top3 = function() return nil end })
	eq(Do(w, viewer, api, "GetRankings", "church"), nil, "closed: nothing")
	eq(select(2, Do(w, viewer, api, "GetRankings", "census")), "kind")
	-- Lottery history is private even with a prior public ranking word.
	viewer.db.lotteryWinners = { L = { e1 = { at = w.clock - 3600, rows = { { name = N.bettor3, beast = 7, amount = 25000 } } } } }
	eq(W3.M(w, cast.king, "ArenaHome").SetRankingsPublic(true, "lottery"), false)
	assert(W3.M(w, cast.king, "ArenaRoles").Publish("lottery", true)) -- an older client's word
	w:Run(1)
	eq(w:As(viewer, viewer.ns.ArenaHome.RankingsPublic, "lottery"), false, "never a public Lottery ranking")
	local games = Do(w, viewer, api, "GetRankings", "games")
	eq(games.lottery, nil, "private saved winners are never exported")
	eq(viewer.db.lotteryWinners.L.e1.rows[1].name, N.bettor3, "the history is retained")
	-- The profile: his guild, rank and role, the frame and title his profile shows.
	local p = Do(w, viewer, api, "GetProfile")
	eq(Keys(p), "frame,guild,member,name,rank,rankIndex,role")
	eq(p.member, true); eq(p.name, viewer.name); eq(p.guild, World.GUILD); eq(p.rank, "Member"); eq(p.rankIndex, 3); eq(p.role, "member")
	eq(p.frame, "rank"); eq(p.title, nil)
	-- His pick: the all-time donors' frame he holds (third), and its title.
	eq(W3.M(w, viewer, "ArenaProfile").SetPick("donor-top-3", "donor-top-3"), true)
	p = Do(w, viewer, api, "GetProfile")
	eq(p.frame, "donor-top-3"); eq(p.title, w:As(viewer, viewer.ns.HonorsNet.TitleText, "donor-top-3"))
	assert(type(p.title) == "string" and p.title ~= "", "the title's words")
	-- The King's own: his role.
	LoadAPI(w, cast.king, false)
	Install(cast.king, "MapPins", "Map Pins")
	local kapi = w:As(cast.king, cast.king.OlympusAPI.Register, "MapPins")
	w:As(cast.king, cast.king.Consent.Choose, "api:mappins", true)
	eq(Do(w, cast.king, kapi, "GetProfile").role, "king")
	eq(Do(w, cast.king, kapi, "GetProfile").rankIndex, 0)
	-- Outside an Olympus guild: that he is in none, and nothing else.
	viewer.guild = nil
	p = Do(w, viewer, api, "GetProfile")
	eq(Keys(p), "member"); eq(p.member, false)
	local none, why = Do(w, viewer, api, "GetWanted")
	eq(none, nil); eq(why, "guild")
	eq(select(2, Do(w, viewer, api, "GetRankings")), "guild")
	viewer.guild = World.GUILD
	-- The donors' top three once the King shows the army the Treasury's ranking: the names the
	-- Treasurer's word gave every client (this world wears every family's frame: the month's too).
	W3.M(w, cast.king, "Treasury").SetFlag("ranking", true)
	w:Run(1)
	r = Do(w, viewer, api, "GetRankings")
	eq(Keys(r), "donors,games,slayers")
	eq(Keys(r.donors), "all,month")
	eq(r.donors.all[1], cast.A.name); eq(r.donors.all[3], viewer.name)
	W3.NoErrors(w)
end)

-- (1.2.4, the author's report: "many with 0 points, 0 kills on the Most Wanted list": they are not
-- on it any more, and the API reads the tab's list.)
test("1.2.4 the API: GetWanted lists what the Wanted tab lists: a Horde player with 0 points and 0 kills (one a member killed who killed none of ours) is left out, though his entry and its claim stay", function()
	local w, cast, viewer, API = Setup()
	local O, C = viewer.OlympusAPI, viewer.Consent
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, O.Register, "MapPins")
	w:As(viewer, C.Choose, "api:mappins", true)
	local at = w.clock - 300
	viewer.rdb.wanted.targets["g:Player-4002-0000F00D"] = { key = "g:Player-4002-0000F00D", name = "Prey Only-Emberfall",
		guid = "Player-4002-0000F00D", active = true, addedAt = at, source = "PARTY_KILL", current = 0, lifetimeKills = 0, cycle = 2,
		openSince = at, victimOverflow = 0, victims = {},
		claims = { { id = "c2", slayer = N.fighterA, points = 50, cycle = 1, at = at, evidence = "PARTY_KILL", level = 25 } } }
	eq(#w:As(viewer, viewer.ns.Wanted.Targets, true), 2, "both entries on the ledger")
	local rows = Do(w, viewer, api, "GetWanted")
	eq(#rows, 1, "only the one wanted"); eq(rows[1].guid, HORDE.guid)
	local page = w:As(viewer, viewer.ns.Wanted.Targets, "listed")
	eq(#page, 1); eq(page[1].guid, rows[1].guid, "the tab's list")
	W3.NoErrors(w)
end)

test("1.2.4 the API Lottery privacy: even an older ArenaHome exposing a public Lottery word cannot export saved winners", function()
	local w, cast, viewer = Setup()
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, viewer.OlympusAPI.Register, "MapPins")
	w:As(viewer, viewer.Consent.Choose, "api:mappins", true)
	viewer.db.lotteryWinners = { L = { old = { at = w.clock - 10, rows = { { name = N.bettor3, beast = 7, amount = 25000 } } } } }
	-- This is the verified old ArenaHome contract, whose per-game publish word exposed Lottery.
	viewer.ns.ArenaHome.RankingsPublic = function(game) return game == "lottery" end
	local result = Do(w, viewer, api, "GetRankings", "games")
	eq(result.lottery, nil, "the API itself enforces private Lottery history")
	eq(viewer.db.lotteryWinners.L.old.rows[1].name, N.bettor3, "the private record survives")
	W3.NoErrors(w)
end)

test("1.2.4 the API: every table is the addon's own copy: changing it changes nothing of Olympus's, nor what the next call or another addon gets", function()
	local w, cast, viewer, API = Setup()
	local O, C = viewer.OlympusAPI, viewer.Consent
	Install(viewer, "MapPins", "Map Pins")
	Install(viewer, "BountyBoard", "Bounty Board")
	local a = w:As(viewer, O.Register, "MapPins")
	local b = w:As(viewer, O.Register, "BountyBoard")
	w:As(viewer, C.Choose, "api:mappins", true)
	w:As(viewer, C.Choose, "api:bountyboard", true)
	-- (The donors come only while the King shows the army the Treasury's ranking: review of 1.2.4.)
	W3.M(w, cast.king, "Treasury").SetFlag("ranking", true)
	w:Run(1)
	local rows = Do(w, viewer, a, "GetWanted")
	rows[1].bounty, rows[1].name, rows[1].guid = 99999, "Someone Else", "Player-1-00000001"
	rows[2] = { name = "Injected" }
	local r = Do(w, viewer, a, "GetRankings")
	r.slayers.all[1].points = 1
	table.remove(r.slayers.all, 2)
	r.donors.all[1] = "Mallory"
	local p = Do(w, viewer, a, "GetProfile")
	p.guild, p.role, p.frame = "Other", "king", "donor-top-1"
	-- Olympus's own: as before.
	local t = viewer.rdb.wanted.targets["g:" .. HORDE.guid]
	eq(t.current, 42); eq(t.name, HORDE.name); eq(t.guid, HORDE.guid)
	local s = viewer.rdb.wanted.slayers["g:" .. SECRET.slayerGuid]
	eq(s.total, 70)
	eq(w:As(viewer, viewer.ns.HonorsNet.Donors).all[1], cast.A.name)
	eq(#w:As(viewer, viewer.ns.Wanted.Targets, true), 1)
	-- The next call, and the other addon: the true rows.
	for _, h in ipairs({ a, b }) do
		local again = Do(w, viewer, h, "GetWanted")
		eq(#again, 1); eq(again[1].bounty, 42); eq(again[1].name, HORDE.name)
		local rr = Do(w, viewer, h, "GetRankings")
		eq(#rr.slayers.all, 2); eq(rr.slayers.all[1].points, 70); eq(rr.donors.all[1], cast.A.name)
		local pp = Do(w, viewer, h, "GetProfile")
		eq(pp.guild, World.GUILD); eq(pp.role, "member"); eq(pp.frame, "rank")
	end
	assert(Do(w, viewer, a, "GetWanted") ~= Do(w, viewer, a, "GetWanted"), "a fresh table each call")
	W3.NoErrors(w)
end)

test("1.2.4 the API: rate-limited per addon (RATE_MAX calls a RATE_WINDOW), the others unaffected; Status and On cost nothing", function()
	local w, cast, viewer, API = Setup()
	local O, C = viewer.OlympusAPI, viewer.Consent
	Install(viewer, "MapPins", "Map Pins")
	Install(viewer, "BountyBoard", "Bounty Board")
	local a = w:As(viewer, O.Register, "MapPins")
	local b = w:As(viewer, O.Register, "BountyBoard")
	w:As(viewer, C.Choose, "api:mappins", true)
	w:As(viewer, C.Choose, "api:bountyboard", true)
	for i = 1, API.RATE_MAX do assert(type(Do(w, viewer, a, i % 2 == 0 and "GetWanted" or "GetProfile")) == "table", "call " .. i) end
	for _ = 1, 30 do Do(w, viewer, a, "Status") end
	local data, why = Do(w, viewer, a, "GetWanted")
	eq(data, nil); eq(why, "busy", "past the rate")
	assert(type(Do(w, viewer, b, "GetWanted")) == "table", "another addon's own rate")
	local logged = 0
	for _, l in ipairs(viewer.log) do if l:find("api: MapPins asked more than", 1, true) then logged = logged + 1 end end
	eq(logged, 1, "said once in the log")
	w:Run(API.RATE_WINDOW)
	assert(type(Do(w, viewer, a, "GetWanted")) == "table", "the next window")
	-- (Review of 1.2.4) An addon polling past the rate window after window: still that one line, not
	-- one a window (they filled the log's ring and the last lines /oly bug copies).
	for window = 1, 6 do
		local busy = 0
		for _ = 1, API.RATE_MAX + 5 do
			if select(2, Do(w, viewer, a, "GetProfile")) == "busy" then busy = busy + 1 end
		end
		assert(busy >= 5, "window " .. window .. ": past the rate (" .. busy .. ")")
		w:Run(API.RATE_WINDOW)
	end
	local function Lines(name)
		local n = 0
		for _, l in ipairs(viewer.log) do if l:find("api: " .. name .. " asked more than", 1, true) then n = n + 1 end end
		return n
	end
	eq(Lines("MapPins"), 1, "once a session, however many windows")
	-- The other addon's own line, once too.
	for _ = 1, 2 * API.RATE_MAX do Do(w, viewer, b, "GetProfile") end
	w:Run(API.RATE_WINDOW)
	for _ = 1, 2 * API.RATE_MAX do Do(w, viewer, b, "GetProfile") end
	eq(Lines("BountyBoard"), 1); eq(Lines("MapPins"), 1)
	W3.NoErrors(w)
end)

test("1.2.4 the API: callbacks fire on a change, once a burst settles, only when what the call returns changed, never in combat nor for an addon without a Yes; an erroring callback is contained, logged, dropped after three errors", function()
	local w, cast, viewer, API = Setup()
	local O, C = viewer.OlympusAPI, viewer.Consent
	Install(viewer, "MapPins", "Map Pins")
	Install(viewer, "BountyBoard", "Bounty Board")
	Install(viewer, "Quiet", "Quiet")
	local a = w:As(viewer, O.Register, "MapPins")
	local b = w:As(viewer, O.Register, "BountyBoard")
	local q = w:As(viewer, O.Register, "Quiet")
	w:As(viewer, C.Choose, "api:mappins", true)
	w:As(viewer, C.Choose, "api:bountyboard", true)
	-- (The donors' frame Lida holds switches on by itself the first time her honours are looked at,
	-- Honors.Update: a real change of her profile. Looked at once here, before anyone listens.)
	w:As(viewer, viewer.ns.HonorsNet.Refresh)
	eq(Do(w, viewer, a, "GetProfile").frame, "donor-top-3", "her new honour, switched on by itself")
	local got, bad, good, quiet, profiles, rankings = {}, 0, {}, 0, {}, {}
	eq(Do(w, viewer, a, "On", "WANTED_CHANGED", function(event, rows) got[#got + 1] = { event = event, rows = rows } rows[1].bounty = -1 end), true)
	eq(Do(w, viewer, a, "On", "NOT_AN_EVENT", function() end), false)
	eq(Do(w, viewer, b, "On", "WANTED_CHANGED", function() bad = bad + 1 error("addon bug") end), true)
	eq(Do(w, viewer, b, "On", "WANTED_CHANGED", function(_, rows) good[#good + 1] = rows end), true)
	eq(Do(w, viewer, q, "On", "WANTED_CHANGED", function() quiet = quiet + 1 end), true, "an addon without a Yes may listen")
	eq(Do(w, viewer, a, "On", "PROFILE_CHANGED", function(_, p) profiles[#profiles + 1] = p end), true)
	eq(Do(w, viewer, a, "On", "RANKINGS_CHANGED", function(_, r) rankings[#rankings + 1] = r end), true)
	local function Fire(event) w:As(viewer, viewer.ns.Fire, event) end
	local t = viewer.rdb.wanted.targets["g:" .. HORDE.guid]
	-- A burst of changes: told once, DISPATCH_DELAY after (the bounty, and a Slayer's points).
	t.current = 50
	viewer.rdb.wanted.slayers["g:" .. SECRET.slayerGuid].total = 75
	for _ = 1, 5 do Fire("WANTED_CHANGED") end
	eq(#got, 0, "not at once")
	w:Run(API.DISPATCH_DELAY)
	eq(#got, 1, "once for the burst")
	eq(got[1].event, "WANTED_CHANGED"); eq(got[1].rows[1].bounty, -1, "the addon's own copy, changed by it")
	eq(#good, 1); eq(good[1][1].bounty, 50, "the other addon's copy: untouched by the first")
	eq(bad, 1); eq(quiet, 0, "nothing without a Yes")
	eq(t.current, 50, "Olympus's own: untouched")
	local failed = 0
	for _, l in ipairs(viewer.log) do if l:find("api: BountyBoard's WANTED_CHANGED callback failed", 1, true) then failed = failed + 1 end end
	eq(failed, 1, "the error in the log, with the addon's name")
	eq(#viewer.errors, 0, "never Olympus's error report")
	eq(#rankings, 1, "the Slayers boards are told too (a Wanted change)")
	eq(rankings[1].slayers.all[1].points, 75)
	-- The same rows again: nothing to tell.
	Fire("WANTED_CHANGED")
	w:Run(API.DISPATCH_DELAY)
	eq(#got, 1, "no change: no call")
	-- In combat: it waits.
	viewer.combat = true
	t.lifetimeKills = 4
	Fire("WANTED_CHANGED")
	w:Run(API.DISPATCH_DELAY)
	eq(#got, 1, "in combat: not yet")
	viewer.combat = false
	w:Run(API.COMBAT_RETRY)
	eq(#got, 2, "after combat"); eq(got[2].rows[1].kills, 4)
	-- The failing callback goes after three errors; the others stay.
	t.current = 51
	Fire("WANTED_CHANGED")
	w:Run(API.DISPATCH_DELAY)
	eq(bad, 3)
	t.current = 52
	Fire("WANTED_CHANGED")
	w:Run(API.DISPATCH_DELAY)
	eq(bad, 3, "dropped"); eq(#good, 4); eq(#got, 4)
	local dropped = false
	for _, l in ipairs(viewer.log) do if l:find("api: BountyBoard's WANTED_CHANGED callback dropped", 1, true) then dropped = true end end
	eq(dropped, true)
	-- PROFILE_CHANGED: the pick (HONORS_CHANGED) changes the frame; a census change alone does not.
	Fire("DATA_CHANGED")
	w:Run(API.DISPATCH_DELAY)
	eq(#profiles, 0, "the profile did not change")
	eq(W3.M(w, viewer, "ArenaProfile").SetPick("rank"), true)
	w:Run(API.DISPATCH_DELAY)
	eq(#profiles, 1); eq(profiles[1].frame, "rank", "her rank's frame again")
	-- Off: no more calls; a No: none either.
	eq(Do(w, viewer, a, "Off", "WANTED_CHANGED"), true)
	t.current = 53
	Fire("WANTED_CHANGED")
	w:Run(API.DISPATCH_DELAY)
	eq(#got, 4, "off"); eq(#good, 5)
	w:As(viewer, C.Choose, "api:bountyboard", false)
	t.current = 54
	Fire("WANTED_CHANGED")
	w:Run(API.DISPATCH_DELAY)
	eq(#good, 5, "after the No: nothing")
	eq(quiet, 0)
	W3.NoErrors(w)
end)

test("1.2.4 the API: no secret ever comes back: not the realm key nor the sealed channel's name, the account key, a victim, a place, who added or took off an entry, a member's GUID", function()
	local w, cast, viewer, API = Setup()
	local O, C = viewer.OlympusAPI, viewer.Consent
	viewer.rdb.realmKey = "rk-Secret-0123456789"
	local channel = "Oly" .. H.ns.Comm.Hash36(viewer.rdb.realmKey)
	w:As(viewer, viewer.ns.Debts.MyKey)
	local seed, pk = viewer.db.arenaKey and viewer.db.arenaKey.seed, viewer.db.arenaKey and viewer.db.arenaKey.pk
	assert(type(seed) == "string" and #seed > 8, "the account's key")
	rawset(viewer.ns, "ChurchCount", { Top3 = function() return { at = w.clock, by = SECRET.by, apostles = { N.bettor2 }, missionaries = { N.bettor3 } } end })
	viewer.db.lotteryWinners = { L = { e1 = { at = w.clock - 3600, rows = { { name = N.bettor3, beast = 7, amount = 25000, sig = SECRET.source } } } } }
	for _, game in ipairs({ "arena", "bones", "lottery" }) do W3.M(w, cast.king, "ArenaHome").SetRankingsPublic(true, game) end
	w:Run(1)
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, O.Register, "MapPins")
	local told = {}
	for _, e in ipairs(API.EVENTS) do Do(w, viewer, api, "On", e, function(event, data) told[#told + 1] = { event, data } end) end
	w:As(viewer, C.Choose, "api:mappins", true)
	viewer.rdb.wanted.targets["g:" .. HORDE.guid].current = 43
	for _, e in ipairs({ "WANTED_CHANGED", "HONORS_CHANGED", "CHURCH_TOP_CHANGED", "ARENA_CHANGED", "DATA_CHANGED" }) do w:As(viewer, viewer.ns.Fire, e) end
	w:Run(API.DISPATCH_DELAY)
	assert(#told >= 2, "callbacks told: " .. #told)
	local out = { Do(w, viewer, api, "GetWanted"), Do(w, viewer, api, "GetRankings"), Do(w, viewer, api, "GetProfile"), Do(w, viewer, api, "Status"), told }
	local strings = {}
	local function Walk(v, depth)
		assert(depth < 12, "no cycle")
		if type(v) == "table" then
			for k, x in pairs(v) do Walk(k, depth + 1) Walk(x, depth + 1) end
		elseif type(v) == "string" then
			strings[#strings + 1] = v
		else
			assert(v == nil or type(v) == "number" or type(v) == "boolean", "plain data only: " .. type(v))
		end
	end
	Walk(out, 0)
	assert(#strings > 10, "the returns were read: " .. #strings)
	local all = table.concat(strings, "\n"):lower()
	for what, s in pairs({ key = viewer.rdb.realmKey, channel = channel, seed = seed, pk = pk, victim = SECRET.victim, zone = SECRET.zone,
		sighting = SECRET.sighting, by = SECRET.by, slayerGuid = SECRET.slayerGuid, source = SECRET.source }) do
		eq(all:find(s:lower(), 1, true), nil, what .. " never comes back")
	end
	assert(all:find(HORDE.guid:lower(), 1, true), "the Horde player's GUID is his row's")
	W3.NoErrors(w)
end)

test("1.2.4 the API: read-only by its source: no send, no message, no window, no game event, no timer at load; the TOC loads it after the boards it reads", function()
	local src = Read(H.ADDON_DIR .. "API.lua"):gsub("%-%-[^\n]*", "")
	for _, word in ipairs({ "Comm.", "SendChatMessage", "SendAddonMessage", "Whisper", "Send(", "Decree", "ShowDialog", "StaticPopup", "CreateFrame",
		"RegisterEvent", "ns.Every", "SetCVar", "ns.Print", "_G[", "hooksecurefunc" }) do
		eq(src:find(word, 1, true), nil, "API.lua uses " .. word)
	end
	local toc, at, n = Read(H.ADDON_DIR .. "Olympus.toc"), {}, 0
	for line in toc:gmatch("[^\r\n]+") do n = n + 1; at[line] = n end
	assert(at["API.lua"], "API.lua in the TOC")
	for _, f in ipairs({ "Consent.lua", "Wanted.lua", "Roster.lua", "King.lua" }) do assert(at[f] < at["API.lua"], "after " .. f) end
	assert(at["API.lua"] < at["ArenaMath.lua"], "a core file, before the Arena's load tail")
	assert(at["Locales\\APIText.lua"] and at["Locales\\APIText.lua"] < at["Core.lua"], "its words with the other locales")
	-- An idle client with the API loaded: no event, timer or frame of its own.
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local events, timers, frames = 0, #w:Timers(a), #a.frames
	for _ in pairs(w:Events(a)) do events = events + 1 end
	LoadAPI(w, a, false)
	local after = 0
	for _ in pairs(w:Events(a)) do after = after + 1 end
	eq(after, events, "no game event"); eq(#w:Timers(a), timers, "no timer"); eq(#a.frames, frames, "no frame")
	w:As(a, a.ns.Fire, "WANTED_CHANGED")
	eq(#w:Timers(a), timers, "a change with nobody listening: no timer either")
end)

test("1.2.4 the API: its words in English and pt-BR; docs/API.md names every method and event; the README and the CurseForge page say the same", function()
	local L = H.ns.L
	local src = Read(H.ADDON_DIR .. "Locales/APIText.lua")
	local head, tail = src:match("^(.-)\nif GetLocale and GetLocale%(%) == \"ptBR\" then(\n.*)$")
	local en, pt = {}, {}
	for k in head:gmatch("\nL%.([%w_]+) =") do en[k] = true end
	for k in tail:gmatch("\n\tL%.([%w_]+) =") do pt[k] = true end
	eq(Keys(en), "API_CONSENT_LABEL,API_CONSENT_TEXT"); eq(Keys(pt), Keys(en))
	for _, word in ipairs({ "location", "census", "keys", "sends nothing", "Authorize all" }) do
		assert(src:find(word, 1, true), "the line says: " .. word)
	end
	-- (Review of 1.2.4) Its promises are Olympus's own: it never promised for the other addon that it
	-- sends nothing, and says that what that addon does with what it read is its own.
	eq(head:find("it sends nothing for you", 1, true), nil, "no promise for the other addon")
	eq(tail:find("ele não envia nada por você", 1, true), nil, "no promise for the other addon (pt-BR)")
	for _, word in ipairs({ "Olympus lets it read", "no way to send anything for you", "up to that addon", "addons you trust" }) do
		assert(head:find(word, 1, true), "the line says: " .. word)
	end
	for _, word in ipairs({ "o Olympus permite", "não lhe dá meio de enviar nada por você", "é com ele", "em que você confia" }) do
		assert(tail:find(word, 1, true), "the pt-BR line says: " .. word)
	end
	local doc = Read(H.ROOT .. "docs/API.md")
	local api = Read(H.ADDON_DIR .. "API.lua")
	for m in api:gmatch("\nfunction METHODS%.(%u%a+)%(") do assert(doc:find(":" .. m .. "(", 1, true), "docs/API.md: " .. m) end
	for e in api:match("API%.EVENTS = (%b{})"):gmatch('"([%u_]+)"') do assert(doc:find(e, 1, true), "docs/API.md: " .. e) end
	for _, f in ipairs({ "OlympusAPI.VERSION", "OlympusAPI.SURFACE_LIMIT", "OlympusAPI.Has", "OlympusAPI.Register", "## OptionalDeps: Olympus", "/oly privacy" }) do
		assert(doc:find(f, 1, true), "docs/API.md: " .. f)
	end
	for _, word in ipairs({ '"ui.surface"', "one client-owned page", "availableWhenLocked", 'style = "old" or "hd"',
		"OlympusAPI.SURFACE_LIMIT", '"surface-full"', "works while the answer is pending or refused",
		"contains no addon name, consent key or" }) do
		assert(doc:find(word, 1, true), "docs/API.md surface contract: " .. word)
	end
	local sections = {}
	for _, path in ipairs({ "README.md", "docs/CURSEFORGE.md" }) do
		local page = Read(H.ROOT .. path)
		local s = page:match("\n### Other addons: the Olympus API %(1%.2%.4%)\n(.-)\n##")
		assert(s and s ~= "", path .. ": the section")
		assert(s:find("docs/API.md", 1, true), path .. ": its link")
		-- (Review of 1.2.4) Olympus's promise, and the other addon's doing its own.
		eq(s:find("nothing is sent for you", 1, true), nil, path .. ": no promise for the other addon")
		for _, word in ipairs({ "Olympus sends nothing for it", "no way to send anything for", "up to it", "addons you trust",
			"while he shows the Treasury's ranking", "one such page per session", "data handles still work",
			"data answer is pending or refused", "hosting it grants no Olympus data" }) do
			assert(s:find(word, 1, true), path .. ": " .. word)
		end
		local privacy = page:match("\n%*%*What waits for your yes%.%*%*(.-)\n\n")
		assert(privacy and privacy:find("Olympus sends nothing for it, and what it does with what it read is its own", 1, true), path .. ": the privacy section")
		eq(page:find("it reads on your computer alone", 1, true), nil, path .. ": no promise for the other addon")
		sections[#sections + 1] = s
	end
	eq(sections[1], sections[2], "the same words on both pages")
end)

-- Every string in a return, for what must never be in it.
local function Strings(v, out, depth)
	out, depth = out or {}, depth or 0
	assert(depth < 12, "no cycle")
	if type(v) == "table" then
		for k, x in pairs(v) do Strings(k, out, depth + 1) Strings(x, out, depth + 1) end
	elseif type(v) == "string" then
		out[#out + 1] = v:lower()
	end
	return out
end
local function NoName(v, names, what)
	local all = table.concat(Strings(v), "\n")
	for _, n in ipairs(names) do eq(all:find(n:lower(), 1, true), nil, what .. ": " .. n) end
end

-- (Review of 1.2.4) GetRankings gave the donors' top three of the month and of all time whatever
-- the King's switch: while he keeps the Treasury's ranking from the army (the default) no page
-- lists them. (1.2.4, after the borders lane: the month's koi is worn, so its three come too while
-- the ranking shows; a build without the koi gives none.) In a world as the release ships it (its frames,
-- Honors.FRAMES_SHIPPED), without the Wanted boards (so every name in a return is a donor's).
test("1.2.4 the API: the donors' top three only while the King shows the army the Treasury's ranking, never by the staff's view; the month's only in a build that wears its koi (1.2.4 does)", function()
	local w, cast, viewer, API = Setup({ wanted = false, world = { compliance = "shipped" } })
	local O, C = viewer.OlympusAPI, viewer.Consent
	eq(w:As(viewer, viewer.ns.Honors.FrameShipped, { family = "donor-month" }), true, "1.2.4 wears the koi")
	eq(w:As(viewer, viewer.ns.Honors.FrameShipped, { family = "donor-top" }), true)
	eq(w:As(viewer, viewer.ns.Treasury.PublicShows, "ranking"), false, "the King's switch: off until he turns it")
	local word = w:As(viewer, viewer.ns.HonorsNet.Donors)
	eq(#word.all, 3, "the Treasurer's word reached this client")
	local names = {}
	for _, n in ipairs(word.all) do names[#names + 1] = n end
	for _, n in ipairs(word.month or {}) do names[#names + 1] = n end
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, O.Register, "MapPins")
	w:As(viewer, C.Choose, "api:mappins", true)
	local told = {}
	eq(Do(w, viewer, api, "On", "RANKINGS_CHANGED", function(_, r) told[#told + 1] = r end), true)
	-- (The world settles first: the honours' first look and the words of the login are told, so the
	-- King's switch is the only change below.)
	w:Run(60)
	local base = #told
	-- Off: no donor's name comes back, by kind or with every ranking.
	local d, why = Do(w, viewer, api, "GetRankings", "donors")
	eq(d, nil, "the ranking kept from the army: no donors"); eq(why, nil)
	local r = Do(w, viewer, api, "GetRankings")
	eq(r.donors, nil)
	NoName(r, names, "every ranking")
	for _, t in ipairs(told) do NoName(t, names, "a callback") end
	-- The King sees the ranking on his own Treasury tab: his addon gets no more (never a staff view).
	LoadAPI(w, cast.king, false)
	Install(cast.king, "MapPins", "Map Pins")
	local kapi = w:As(cast.king, cast.king.OlympusAPI.Register, "MapPins")
	w:As(cast.king, cast.king.Consent.Choose, "api:mappins", true)
	eq(w:As(cast.king, cast.king.ns.Treasury.MaySee, "ranking"), true, "his tab shows it")
	eq(Do(w, cast.king, kapi, "GetRankings", "donors"), nil, "his addon: no donors either")
	NoName(Do(w, cast.king, kapi, "GetRankings"), names, "the King's addon")
	w:Run(60)
	eq(#told, base, "nothing changed")
	-- He shows the army the ranking: the all-time three, which head it, and the month's (its koi worn).
	W3.M(w, cast.king, "Treasury").SetFlag("ranking", true)
	w:Run(1)
	eq(w:As(viewer, viewer.ns.Treasury.PublicShows, "ranking"), true, "every client heard the King")
	d = Do(w, viewer, api, "GetRankings", "donors")
	eq(Keys(d), "all,month", "the month's too: its koi is worn")
	eq(table.concat(d.month, ","), table.concat(word.month or {}, ","))
	eq(table.concat(d.all, ","), table.concat(word.all, ","))
	-- A listener is told when the switch turns (Olympus's TREASURY_CHANGED), and when it turns back:
	-- then no name again.
	w:Run(API.DISPATCH_DELAY)
	eq(#told, base + 1, "told of the switch"); eq(table.concat(told[base + 1].donors.all, ","), table.concat(word.all, ","))
	w:Run(60)
	eq(#told, base + 1, "nothing else")
	W3.M(w, cast.king, "Treasury").SetFlag("ranking", false)
	w:Run(1)
	w:Run(API.DISPATCH_DELAY)
	eq(#told, base + 2, "told of it turning back"); eq(told[base + 2].donors, nil)
	NoName(told[base + 2], names, "the callback")
	eq(Do(w, viewer, api, "GetRankings", "donors"), nil)
	-- A build that does not wear the month's koi gives the all-time three alone.
	W3.M(w, cast.king, "Treasury").SetFlag("ranking", true)
	w:Run(1)
	viewer.ns.Honors.FRAMES_SHIPPED = { ["donor-top"] = true }
	d = Do(w, viewer, api, "GetRankings", "donors")
	eq(Keys(d), "all", "no koi: no month")
	W3.NoErrors(w)
end)

-- (Review of 1.2.4) 1.2.3's adoption took every line still waiting in an account's first session
-- with the record (1.2.2's saved data: the games notice shown, no record of the lines) as asked,
-- an addon's too, which no build before 1.2.4 asked: updating from 1.2.2 straight to 1.2.4, the
-- page never opened by itself for it. 1.2.1's lines stay taken as asked.
test("1.2.4 the API: an account updating from 1.2.2 is asked about an addon by itself once, after the login's wait; the old lines stay as 1.2.3 took them", function()
	local w, cast, viewer, API = Setup({ wanted = false })
	if viewer.Consent.Frame() then viewer.Consent.Frame():Hide() end
	viewer.db.consentNotices, viewer.db.consentAsked, viewer.db.consentAdopt = { games = true }, nil, nil
	viewer.db.apiAddons = nil
	local function Session()
		w:Logout(viewer)
		w:Login(viewer)
		W3.Rules(w, viewer)
		Install(viewer, "MapPins", "Map Pins")
		LoadAPI(w, viewer, false)
		-- The other addon registers as it loads, before the login's wait is over.
		local api = w:As(viewer, viewer.OlympusAPI.Register, "MapPins")
		assert(type(api) == "table", "its handle")
		return api, viewer.Consent
	end
	local api, C = Session()
	local old = {}
	for _, item in ipairs(w:As(viewer, C.Pending)) do
		if item.key ~= "api:mappins" then old[#old + 1] = item.key end
	end
	assert(#old > 0, "lines 1.2.2 left unanswered")
	w:Run(C.LOGIN_WAIT + 1)
	local page = C.Frame()
	assert(page and page:IsShown(), "the page opens by itself for the addon's line")
	eq(viewer.db.consentAsked["api:mappins"], API.CONSENT_VERSION, "shown: asked")
	for _, key in ipairs(old) do assert(viewer.db.consentAsked[key] ~= nil, key .. ": taken as asked, as 1.2.3 does") end
	page:Hide()
	eq(w:As(viewer, C.Ask, "login"), false, "once")
	eq(Do(w, viewer, api, "Status"), "pending", "nothing answered for him")
	-- The next session: never again by itself.
	api, C = Session()
	w:Run(C.LOGIN_WAIT + 125)
	eq(C.Frame() == nil or not C.Frame():IsShown(), true, "the next session: not again")
	eq(Do(w, viewer, api, "Status"), "pending")
	W3.NoErrors(w)
end)

-- (Review of 1.2.4) docs/API.md's examples, run as another addon runs them: the data events come
-- only on a change, so the title example set the title only once it changed, never at the Yes.
test("1.2.4 the API: docs/API.md's title example shows the player's title on his Yes and at load once granted", function()
	local w, cast, viewer, API = Setup({ wanted = false })
	local code = Read(H.ROOT .. "docs/API.md"):match("\nShowing the player's own title in your frame.-\n```lua\n(.-)```")
	assert(code, "the example")
	eq(W3.M(w, viewer, "ArenaProfile").SetPick("donor-top-3", "donor-top-3"), true)
	local title = w:As(viewer, viewer.ns.HonorsNet.TitleText, "donor-top-3")
	assert(type(title) == "string" and title ~= "", "his title's words")
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, viewer.OlympusAPI.Register, "MapPins")
	local function Load()
		local shown = {}
		local frame = { title = { SetText = function(_, text) shown[#shown + 1] = text end } }
		local fn = assert(loadstring(code, "=docs/API.md"))
		setfenv(fn, setmetatable({ api = api, MyFrame = frame }, { __index = _G }))
		w:As(viewer, fn)
		return shown
	end
	local shown = Load()
	eq(shown[#shown] or "", "", "before the Yes: no title")
	w:As(viewer, viewer.Consent.Choose, "api:mappins", true)
	eq(shown[#shown], title, "his title, on his Yes")
	eq(Load()[1], title, "already granted: at load")
	W3.NoErrors(w)
end)
