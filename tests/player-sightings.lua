-- Voluntary, request-bound player sightings. These clients exercise the real module with a
-- queued transport so every authority, consent and location decision is checked again at send.
local base, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]player%-sightings%.lua$")) or "./"

local GLOBALS = { "UnitExists", "UnitIsPlayer", "UnitGUID", "UnitIsVisible", "UnitIsUnit", "UnitPosition", "UnitCanAttack", "UnitIsEnemy",
	"GetGuildInfo", "IsInInstance", "IsInGroup", "C_Map", "LibStub", "issecretvalue" }
local SECRET = {}

local function WithWorld(fn)
	local saved, current = {}, nil
	for _, name in ipairs(GLOBALS) do saved[name] = rawget(_G, name) end
	local world = { now = 1000, queue = {}, authorName = "Author-Realm" }
	local ok, err = pcall(function()
		local function Unit(unit) return current and current.units[unit] end
		UnitExists = function(unit) return Unit(unit) ~= nil end
		UnitIsPlayer = function(unit) local u = Unit(unit); return u and u.player == true or false end
		UnitGUID = function(unit) local u = Unit(unit); return u and u.guid or nil end
		UnitIsVisible = function(unit) local u = Unit(unit); return u and u.visible ~= false or false end
		UnitIsUnit = function(a, b) local ua, ub = Unit(a), Unit(b); return ua ~= nil and ua == ub end
			UnitCanAttack = function(source, unit) local u = source == "player" and Unit(unit); return u and u.hostile == true or false end
			UnitIsEnemy = UnitCanAttack
		UnitPosition = function(unit)
			local u = Unit(unit)
			if not u or not u.worldPosition then return nil end
			return u.worldY, u.worldX, 0, u.instanceID
		end
		-- The observed player's guild as the observer's game reads it (nil: no guild).
		GetGuildInfo = function(unit)
			if unit == "player" then return current and current.guild or nil end
			local u = Unit(unit)
			return u and u.guildName or nil
		end
		IsInInstance = function() return current and current.instance == true or false end
		IsInGroup = function() return current and current.inGroup == true or false end
		issecretvalue = function(value) return value == SECRET end
		C_Map = {
			GetBestMapForUnit = function(unit)
				if unit == "player" then return current and current.mapID or nil end
				local u = Unit(unit)
				if unit == "target" or unit == "mouseover" or unit:match("^nameplate%d+$") then
					return u and u.directPosition and u.mapID or nil
				end
				return u and u.mapID or nil
			end,
			GetMapInfo = function(mapID) return mapID and { mapType = 3 } or nil end,
			GetPlayerMapPosition = function(mapID, unit)
				local source = unit == "player" and current or Unit(unit)
				if not source or source.mapID ~= mapID or not source.x then return nil end
				local x, y = source.x, source.y
				return { GetXY = function() return x, y end }
			end,
		}
		LibStub = function(name)
			if name ~= "HereBeDragons-2.0" or not current then return nil end
			return {
				GetUnitWorldPosition = function(_, unit)
					local y, x, _, instance = UnitPosition(unit)
					return x, y, instance
				end,
				GetZoneCoordinatesFromWorldInstance = function(_, x, y, instance, mapID)
					if instance ~= current.instanceID or mapID ~= current.mapID then return nil end
					return x, y
				end,
			}
		end

		function world:As(client, call, ...)
			local previous = current
			current = client
			local values = { pcall(call, ...) }
			current = previous
			if not values[1] then error(values[2], 0) end
			return unpack(values, 2)
		end

		function world:Client(name, options)
			options = options or {}
			local client = {
				name = name .. "-Realm", guild = options.guild or "Olympus", mapID = 1453,
				x = 0.1234, y = 0.5676, layer = 42, instanceID = 1, units = {}, db = {}, handlers = {},
				events = {}, listeners = {}, authorized = {}, members = {}, sent = {}, printed = {},
				member = options.member ~= false, location = options.location ~= false,
			}
			local c = { L = base.L, db = client.db, me = client.name }
			client.ns = c
			c.Now = function() return world.now end
			c.Normal = function(value) return value end
			c.IsMember = function() return client.member end
			-- This fixture models approved participation separately from guild identity.
			client.participating, client.deniedPeers = true, {}
			c.SharedToolsHere = function() return client.participating == true end
			c.SharedPeerAllowed = function(sender)
				return c.SharedToolsHere() and type(sender) == "string"
					and client.deniedPeers[sender:lower()] ~= true
			end
			c.IsFederation = function(guild)
				return type(guild) == "string" and guild:lower():find("olympus", 1, true) ~= nil
			end
			c.UnitFullName = function(unit) local u = client.units[unit]; return u and u.name or nil end
			c.Moderation = {
				SelfOff = function() return client.netoff and { off = true } or nil end,
				IsIssuer = function(who) return client.authorized[type(who) == "string" and who:lower() or ""] == true end,
				Hides = function(who) return client.hidden and client.hidden[who:lower()] == true or false end,
			}
			c.Workshop = {
				IsAuthorName = function(who)
					return type(who) == "string" and who:lower() == world.authorName:lower()
				end,
			}
			c.Layers = {
				Sharing = function() return client.location == true end,
				Mine = function() return { mapID = client.mapID, zoneUID = client.layer, t = world.now } end,
			}
			c.Channels = {
				VerifiedLevel = function(sender, guild)
					local known = client.members[sender:lower()]
					return known == guild and 1 or 0, known == guild
				end,
				Admit = function(sender, guild, _, _, options)
					client.admitOptions = options
					if options and options.buckets and not options.buckets[sender] then
						options.buckets[sender] = { tokens = 6, t = world.now }
					end
					return client.members[sender:lower()] == guild
				end,
			}
			local function Queue(dist, target, msg, done, options)
				world.queue[#world.queue + 1] = { from = client, dist = dist, target = target,
					msg = msg, done = done, options = options }
				return true
			end
			c.Comm = {
				Handle = function(kind, call) client.handlers[kind] = call end,
				ChannelReady = function() return client.ready ~= false end,
				ChannelName = function() return client.channel or "OlympusNet" end,
				Send = function(dist, msg, _, _, _, done, options) return Queue(dist, nil, msg, done, options) end,
				Whisper = function(target, msg, _, _, _, done, options)
					if client.refuseWhisper then
						if done then done(false, "full") end
						return false
					end
					return Queue("WHISPER", target, msg, done, options)
				end,
				CancelQueued = function(owner, key, why)
					local count = 0
					for i = #world.queue, 1, -1 do
						local item = world.queue[i]
						if item.from == client and item.options and item.options.owner == owner and item.options.key == key then
							table.remove(world.queue, i); count = count + 1
							if item.done then item.done(false, why) end
						end
					end
					return count
				end,
			}
			c.Consent = { Register = function(item) client.consent = item; return true end }
			c.RegisterEvent = function(event, call) client.events[event] = call end
			c.On = function(event, call) client.listeners[event] = call end
			c.Fire = function(event, ...)
				client.fired = { event, ... }
				if client.listeners[event] then client.listeners[event](...) end
			end
			c.Every = function() end
			c.Print = function(message) client.printed[#client.printed + 1] = message end
			-- options.source: an older build's module (tests/fixtures), for the wire's compatibility.
			world:As(client, function() assert(loadfile(ROOT .. (options.source or "Olympus/PlayerSightings.lua")))("Olympus", c) end)
			return client
		end

		function world:Flush(from, recipient, index)
			local at
			for i, item in ipairs(self.queue) do if item.from == from then at = i; if not index or index == 1 then break end; index = index - 1 end end
			if not at then return false, "empty" end
			local item = table.remove(self.queue, at)
			local allowed, why = true, nil
			if item.options and item.options.permit then
				allowed, why = self:As(from, item.options.permit, item.options.owner, item.options.key,
					item.dist, item.target, item.msg)
			end
			if allowed and item.done then self:As(from, item.done, true) elseif item.done then self:As(from, item.done, false, why) end
			if not allowed then return false, why, item end
			from.sent[#from.sent + 1] = item
			if recipient then
				local handler = recipient.handlers.PS
				assert(handler, "recipient has PS handler")
				local received, receiveWhy = self:As(recipient, handler, item.dist, from.name, item.msg)
				return received, receiveWhy, item
			end
			return true, nil, item
		end

		fn(world)
	end)
	for _, name in ipairs(GLOBALS) do _G[name] = saved[name] end
	if not ok then error(err, 0) end
end

local function Authorize(client, who)
	client.authorized[(who or client.name):lower()] = true
end

local function Player(name, options)
	options = options or {}
	return { name = name, player = true, guid = options.guid or "Player-4619-00001234",
		visible = options.visible, directPosition = options.directPosition,
		hostile = options.hostile == true, guildName = options.guild,
		mapID = options.mapID, x = options.x, y = options.y, worldPosition = options.worldPosition,
		worldX = options.worldX, worldY = options.worldY, instanceID = options.instanceID }
end

local function StartAndDeliver(world, requester, observer, target)
	target = target or "Target-Realm"
	Authorize(requester)
	local started, id = world:As(requester, requester.ns.PlayerSightings.Start, target)
	eq(started, true)
	local delivered, why, query = world:Flush(requester, observer)
	eq(delivered, true, why)
	assert(query.msg:match("^PS~Q~1~%d+~" .. target:gsub("%-", "%%-") .. "$"), query.msg)
	return id, query
end

local function StartAreaAndDeliver(world, requester, observer, mapID)
	mapID = mapID or 1453
	Authorize(requester)
	local started, id = world:As(requester, requester.ns.PlayerSightings.StartArea, mapID)
	eq(started, true)
	local delivered, why, query = world:Flush(requester, observer)
	eq(delivered, true, why)
	assert(query.msg:match("^PS~A~1~%d+~" .. mapID .. "$"), query.msg)
	return id, query
end

test("player sightings: consent is explicit, off by default and has practical bounded lifetimes", function()
	WithWorld(function(world)
		local observer = world:Client("Observer")
		eq(observer.ns.PlayerSightings.Sharing(), false)
		-- (7: the wider area scope also reports not-hostile players outside Olympus guilds.)
		eq(observer.ns.PlayerSightings.CONSENT_VERSION, 7)
		eq(observer.consent.explicit, true)
		eq(observer.consent.adopt, false, "a direct upgrade must still show this new question once")
		eq(observer.consent.pending(), true)
		eq(observer.consent.get(), nil)
		eq(observer.ns.PlayerSightings.REQUEST_TTL, 10 * 60)
		eq(observer.ns.PlayerSightings.RESULT_TTL, 15 * 60)
		eq(observer.ns.PlayerSightings.RESULT_KEEP, 15 * 60)
		eq(observer.ns.PlayerSightings.RECENT_TTL, 15 * 60)
		eq(observer.ns.PlayerSightings.RECENT_MAX, 64)
		observer.db.playerSightings, observer.db.playerSightingsConsentVersion = true, 6
		eq(observer.ns.PlayerSightings.Sharing(), false, "the older answer does not silently allow the expanded requester session")
		eq(observer.consent.get(), nil); eq(observer.consent.pending(), true)
		eq(observer.consent.set(true), nil)
		eq(observer.ns.PlayerSightings.Sharing(), true)
		eq(observer.db.playerSightingsConsentVersion, 7)
		observer.consent.set(false)
		eq(observer.ns.PlayerSightings.Sharing(), false)
		local language = { L = {} }
		assert(loadfile(ROOT .. "Olympus/Locales/PlayerSightingsText.lua"))("Olympus", language)
		for _, words in ipairs({ "at most 64", "in memory", "up to 15 minutes", "never saved",
			"selected map ID", "five-minute hostile-area search", "at most six",
			"at most 48 distinct hostile players", "omits your identity and guild", "Authorize all",
			"A wider area search", "not an Olympus guild", "who have no guild", "never a member of your group",
			"labelled not hostile",
			"last-seen information, not continuous tracking" }) do
			assert(language.L.PLAYER_SIGHTINGS_CONSENT_TEXT:find(words, 1, true), "consent discloses: " .. words)
		end
	end)
end)

test("player sightings: exact target and signed requester are required at start and send time", function()
	WithWorld(function(world)
		local requester = world:Client("Requester")
		requester.privateRoster = { [requester.name:lower()] = true }
		eq(world:As(requester, requester.ns.PlayerSightings.Start, "Target-Realm"), false, "a private roster grants nothing")
		Authorize(requester)
		eq(select(2, world:As(requester, requester.ns.PlayerSightings.Start, "Target")), "target")
		eq(select(2, world:As(requester, requester.ns.PlayerSightings.Start, " Target-Realm")), "target")
		local started, id = world:As(requester, requester.ns.PlayerSightings.Start, "Target-Realm")
		eq(started, true)
		requester.authorized[requester.name:lower()] = nil
		eq(world:Flush(requester), false)
		eq(select(2, requester.ns.PlayerSightings.Status(id)), "not-found")
	end)
end)

test("player sightings: the pinned author can exercise the live requester path without gaining moderation authority", function()
	WithWorld(function(world)
		local requester, observer = world:Client("Author"), world:Client("Observer")
		eq(requester.ns.Moderation.IsIssuer(requester.name), false, "the author is not made a moderation issuer")
		observer.ns.PlayerSightings.SetSharing(true, true)
		observer.members[requester.name:lower()] = requester.guild
		local started, id = world:As(requester, requester.ns.PlayerSightings.Start, "Target-Realm")
		eq(started, true, "the pinned author can start the same bounded search")
		eq(world:Flush(requester, observer), true, "another client recognizes the pinned author request")
		eq(requester.ns.PlayerSightings.Cancel(id), true)
	end)
end)

test("player sightings: a visible non-group target returns the observer's precise encounter point", function()
	WithWorld(function(world)
		local requester, observer = world:Client("Requester"), world:Client("Observer")
		Authorize(observer, requester.name)
		observer.members[requester.name:lower()] = requester.guild
		requester.members[observer.name:lower()] = observer.guild
		observer.ns.PlayerSightings.SetSharing(true, true)
		local id = StartAndDeliver(world, requester, observer)
		eq(world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "focus"), false)
		observer.units.nameplate1 = Player("Target-Other")
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "nameplate1")), "unrequested")
		observer.units.nameplate1 = Player("Target-Realm")
		local seen, spot = world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "nameplate1")
		eq(seen, true); eq(spot.kind, "nearby"); eq(spot.x, 123); eq(spot.y, 568); eq(spot.layer, 42)
		eq(spot.accuracyYards, nil, "an encounter point has no invented yard radius")
		eq(#observer.sent, 0, "the observation is still queued and private")
		local delivered, why, answer = world:Flush(observer, requester)
		eq(delivered, true, why); eq(answer.dist, "WHISPER"); eq(answer.target, requester.name)
		assert(answer.msg:match("~1453~123~568~42~5~Target%-Realm~nearby$"), answer.msg)
		eq(select(2, world:As(requester, requester.ns.PlayerSightings.Receive,
			"WHISPER", observer.name, answer.msg)), "replay")
		local session = requester.ns.PlayerSightings.Session(id)
		eq(session.status, "waiting"); eq(#session.sightings, 1)
		eq(session.sightings[1].observer, observer.name)
		eq(session.sightings[1].observerGuild, observer.guild)
		assert(requester.admitOptions and requester.admitOptions.buckets,
			"player sightings use a private Channels.Admit bucket")
		eq(requester.admitOptions.where, "player sighting")
		eq(session.sightings[1].kind, "nearby")
		eq(session.sightings[1].x, 123); eq(session.sightings[1].y, 568)
		eq(session.sightings[1].accuracyYards, nil)
		eq(session.sightings[1].guid, nil, "no GUID crosses the module contract")
		eq(requester.fired[1], "PLAYER_SIGHTINGS_CHANGED")
	end)
end)

test("player sightings: a native observed-unit position takes precedence when WoW exposes it", function()
	WithWorld(function(world)
		local requester, observer = world:Client("Requester"), world:Client("Observer")
		Authorize(observer, requester.name)
		observer.members[requester.name:lower()] = requester.guild
		requester.members[observer.name:lower()] = observer.guild
		observer.ns.PlayerSightings.SetSharing(true, true)
		local id = StartAndDeliver(world, requester, observer)
		observer.x = nil -- a direct native target point does not depend on the observer fallback existing
		observer.units.target = Player("Target-Realm", { directPosition = true,
			guid = "Player-4619-00FEDCBA", mapID = 1453, x = 0.6114, y = 0.3886 })
		local seen, spot = world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target")
		eq(seen, true); eq(spot.kind, "exact-unit"); eq(spot.x, 611); eq(spot.y, 389)
		eq(spot.accuracyYards, 0)
		local delivered, why, answer = world:Flush(observer, requester)
		eq(delivered, true, why)
		assert(answer.msg:match("~5~Target%-Realm~exact%-unit~0$"), answer.msg)
		local result = requester.ns.PlayerSightings.Session(id).sightings[1]
		eq(result.kind, "exact-unit"); eq(result.accuracyYards, 0)
		eq(result.x, 611); eq(result.y, 389)
	end)
end)

test("player sightings: a supported native world position converts on the current map and fails closed across instances", function()
	WithWorld(function(world)
		local requester, observer = world:Client("Requester"), world:Client("Observer")
		Authorize(observer, requester.name)
		observer.members[requester.name:lower()] = requester.guild
		requester.members[observer.name:lower()] = observer.guild
		observer.ns.PlayerSightings.SetSharing(true, true)
		local id = StartAndDeliver(world, requester, observer)
		observer.x = nil
		observer.units.target = Player("Target-Realm", { worldPosition = true,
			guid = "Player-4619-00FEDCBA", worldX = 0.4554, worldY = 0.7446, instanceID = 2 })
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target")), "position",
			"a world point from another instance is not converted into the current map")
		observer.units.target.instanceID = observer.instanceID
		local seen, spot = world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target")
		eq(seen, true); eq(spot.kind, "exact-unit"); eq(spot.x, 455); eq(spot.y, 745)
		local delivered, why, answer = world:Flush(observer, requester)
		eq(delivered, true, why)
		assert(answer.msg:match("~455~745~42~5~Target%-Realm~exact%-unit~0$"), answer.msg)
		local result = requester.ns.PlayerSightings.Session(id).sightings[1]
		eq(result.kind, "exact-unit"); eq(result.x, 455); eq(result.y, 745)
	end)
end)

test("player sightings: a later request receives bounded memory-only exact and encounter observations with their age", function()
	WithWorld(function(world)
		local requester, observer = world:Client("Requester"), world:Client("Observer")
		Authorize(observer, requester.name)
		observer.members[requester.name:lower()] = requester.guild
		requester.members[observer.name:lower()] = observer.guild
		observer.ns.PlayerSightings.SetSharing(true, true)

		observer.units.nameplate1 = Player("Exact-Realm", { directPosition = true,
			guid = "Player-4619-0000E001", mapID = 1453, x = 0.6114, y = 0.3886 })
		eq(world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "nameplate1"), false)
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "nameplate1")), "unrequested")
		observer.units.nameplate1 = Player("Nearby-Realm", { guid = "Player-4619-0000E002" })
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "nameplate1")), "unrequested")
		observer.units.nameplate1 = nil
		world.now = world.now + 37

		local exactId = StartAndDeliver(world, requester, observer, "exact-realm")
		local delivered, why, exact = world:Flush(observer, requester)
		eq(delivered, true, why)
		assert(exact.msg:match("~42~exact%-realm~exact%-unit~0$"), exact.msg)
		local exactResult = requester.ns.PlayerSightings.Session(exactId).sightings[1]
		eq(exactResult.kind, "exact-unit"); eq(exactResult.accuracyYards, 0)
		eq(exactResult.seenAt, 995, "wire age conservatively includes the maximum queue delay")

		local nearbyId = StartAndDeliver(world, requester, observer, "Nearby-Realm")
		delivered, why, exact = world:Flush(observer, requester)
		eq(delivered, true, why)
		assert(exact.msg:match("~42~Nearby%-Realm~nearby$"), exact.msg)
		local nearby = requester.ns.PlayerSightings.Session(nearbyId).sightings[1]
		eq(nearby.kind, "nearby", "the observer fallback is never promoted to exact in the cache")
		eq(nearby.accuracyYards, nil)
	end)
end)

test("player sightings: recent memory is cleared on consent, location and network opt-out and expires", function()
	for _, mode in ipairs({ "consent", "location", "network", "expiry" }) do
		WithWorld(function(world)
			local requester, observer = world:Client("Requester"), world:Client("Observer")
			Authorize(observer, requester.name)
			observer.members[requester.name:lower()] = requester.guild
			observer.ns.PlayerSightings.SetSharing(true, true)
			observer.units.nameplate1 = Player("Stale-Realm")
			eq(select(2, world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "nameplate1")), "unrequested")
			observer.units.nameplate1 = nil
			if mode == "consent" then
				observer.ns.PlayerSightings.SetSharing(false, true)
				observer.ns.PlayerSightings.SetSharing(true, true)
			elseif mode == "location" then
				observer.location = false
				world:As(observer, observer.ns.PlayerSightings.Tick)
				observer.location = true
			elseif mode == "network" then
				observer.netoff = true
				world:As(observer, observer.ns.PlayerSightings.Tick)
				observer.netoff = false
			else
				world.now = world.now + observer.ns.PlayerSightings.RECENT_TTL + 1
			end
			StartAndDeliver(world, requester, observer, "Stale-Realm")
			eq(#world.queue, 0, mode .. " removes the recent observation before a later query")
		end)
	end
end)

test("player sightings: recent memory evicts the oldest identity at its fixed capacity", function()
	WithWorld(function(world)
		local requester, observer = world:Client("Requester"), world:Client("Observer")
		Authorize(observer, requester.name)
		observer.members[requester.name:lower()] = requester.guild
		requester.members[observer.name:lower()] = observer.guild
		observer.ns.PlayerSightings.SetSharing(true, true)
		local first, newest
		for i = 1, observer.ns.PlayerSightings.RECENT_MAX + 1 do
			local a = string.char(65 + math.floor((i - 1) / 26))
			local b = string.char(65 + (i - 1) % 26)
			local name = "Target" .. a .. b .. "-Realm"
			first, newest = first or name, name
			observer.units.nameplate1 = Player(name, { guid = ("Player-4619-%08d"):format(i) })
			eq(select(2, world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "nameplate1")), "unrequested")
			world.now = world.now + 1
		end
		observer.units.nameplate1 = nil
		StartAndDeliver(world, requester, observer, first)
		eq(#world.queue, 0, "the 65th identity evicts the oldest of the 64 memory-only records")
		local newestId = StartAndDeliver(world, requester, observer, newest)
		eq(world:Flush(observer, requester), true, "the newest record is still answerable")
		eq(requester.ns.PlayerSightings.Session(newestId).sightings[1].target, newest)
	end)
end)

test("player sightings: one query prefers the newest observation and then the most precise live token", function()
	WithWorld(function(world)
		local requester, observer = world:Client("Requester"), world:Client("Observer")
		Authorize(observer, requester.name)
		observer.members[requester.name:lower()] = requester.guild
		requester.members[observer.name:lower()] = observer.guild
		observer.ns.PlayerSightings.SetSharing(true, true)
		observer.units.nameplate1 = Player("Target-Realm", { directPosition = true,
			guid = "Player-4619-0000CAFE", mapID = 1453, x = 0.2, y = 0.3 })
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "nameplate1")), "unrequested")
		observer.units.nameplate1 = nil
		world.now = world.now + 30
		observer.units.target = Player("Target-Realm", { guid = "Player-4619-0000CAFE" })
		observer.units.mouseover = Player("Target-Realm", { directPosition = true,
			guid = "Player-4619-0000BEEF", mapID = 1453, x = 0.7, y = 0.4 })
		local id = StartAndDeliver(world, requester, observer)
		eq(#world.queue, 1, "target, mouseover and cache coalesce to one private response")
		local ok, why, answer = world:Flush(observer, requester)
		eq(ok, true, why)
		assert(answer.msg:match("~700~400~42~5~Target%-Realm~exact%-unit~0$"), answer.msg)
		eq(requester.ns.PlayerSightings.Session(id).sightings[1].kind, "exact-unit")
	end)
end)

test("player sightings: a refused better replacement leaves the prior queued answer intact", function()
	WithWorld(function(world)
		local requester, observer = world:Client("Requester"), world:Client("Observer")
		Authorize(observer, requester.name)
		observer.members[requester.name:lower()] = requester.guild
		requester.members[observer.name:lower()] = observer.guild
		observer.ns.PlayerSightings.SetSharing(true, true)
		local id = StartAndDeliver(world, requester, observer)
		observer.units.target = Player("Target-Realm", { guid = "Player-4619-0000CAFE" })
		eq(world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target"), true)
		eq(#world.queue, 1)
		observer.refuseWhisper = true
		observer.units.mouseover = Player("Target-Realm", { directPosition = true,
			guid = "Player-4619-0000BEEF", mapID = 1453, x = 0.7, y = 0.4 })
		eq(world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "mouseover"), false)
		eq(#world.queue, 1, "the rejected replacement did not cancel the accepted nearby answer")
		observer.refuseWhisper = false
		local delivered, why, answer = world:Flush(observer, requester)
		eq(delivered, true, why)
		assert(answer.msg:match("~123~568~42~5~Target%-Realm~nearby$"), answer.msg)
		eq(requester.ns.PlayerSightings.Session(id).sightings[1].kind, "nearby")
	end)
end)

test("player sightings: receiving a query does not itself add the visible unit to recent memory", function()
	WithWorld(function(world)
		local requester, observer = world:Client("Requester"), world:Client("Observer")
		Authorize(observer, requester.name)
		observer.members[requester.name:lower()] = requester.guild
		observer.ns.PlayerSightings.SetSharing(true, true)
		observer.units.target = Player("Target-Realm")
		local id = StartAndDeliver(world, requester, observer)
		eq(#world.queue, 1, "the current target can answer the live query")
		eq(requester.ns.PlayerSightings.Cancel(id), true)
		eq(world:Flush(requester, observer), true, "the cancellation removes the queued live answer")
		eq(#world.queue, 0)
		observer.units.target = nil
		StartAndDeliver(world, requester, observer)
		eq(#world.queue, 0, "a query-triggered live read did not populate recent memory")
	end)
end)

test("player sightings: an observed exact group identity returns WoW's group-unit position", function()
	WithWorld(function(world)
		local requester, observer = world:Client("Requester"), world:Client("Observer")
		Authorize(observer, requester.name)
		observer.members[requester.name:lower()] = requester.guild
		requester.members[observer.name:lower()] = observer.guild
		observer.ns.PlayerSightings.SetSharing(true, true)
		local id = StartAndDeliver(world, requester, observer)
		local target = Player("Target-Realm", { guid = "Player-4619-00ABCDEF", mapID = 1453, x = 0.7774, y = 0.2226 })
		observer.units.nameplate1, observer.units.party1 = target, target
		local seen, spot = world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "nameplate1")
		eq(seen, true); eq(spot.kind, "exact-group"); eq(spot.x, 777); eq(spot.y, 223)
		eq(spot.accuracyYards, 0)
		local delivered, why, answer = world:Flush(observer, requester)
		eq(delivered, true, why)
		assert(answer.msg:match("~1453~777~223~42~5~Target%-Realm~exact%-group~0$"), answer.msg)
		local result = requester.ns.PlayerSightings.Session(id).sightings[1]
		eq(result.kind, "exact-group"); eq(result.accuracyYards, 0)
		eq(result.x, 777); eq(result.y, 223)
	end)
end)

test("player sightings: queue-time consent, visibility, identity, position and authority are revalidated", function()
	WithWorld(function(world)
		local requester, observer = world:Client("Requester"), world:Client("Observer")
		Authorize(observer, requester.name); observer.members[requester.name:lower()] = requester.guild
		observer.ns.PlayerSightings.SetSharing(true, true)
		StartAndDeliver(world, requester, observer)
		observer.units.target = Player("Target-Realm")
		eq(world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target"), true)
		observer.location = false
		eq(world:Flush(observer), false); eq(#observer.sent, 0)
		observer.location = true
		eq(world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target"), true)
		observer.units.target.visible = false
		eq(world:Flush(observer), false); eq(#observer.sent, 0)
		observer.units.target = Player("Target-Realm")
		eq(world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target"), true)
		observer.units.target = Player("Other-Realm", { guid = "Player-4619-00BADBAD" })
		eq(world:Flush(observer), false); eq(#observer.sent, 0)
		observer.units.target = Player("Target-Realm")
		eq(world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target"), true)
		observer.authorized[requester.name:lower()] = nil
		eq(world:Flush(observer), false); eq(#observer.sent, 0)
	end)
end)

test("player sightings: an exact group answer is dropped if the same group unit moves before send", function()
	WithWorld(function(world)
		local requester, observer = world:Client("Requester"), world:Client("Observer")
		Authorize(observer, requester.name); observer.members[requester.name:lower()] = requester.guild
		observer.ns.PlayerSightings.SetSharing(true, true)
		StartAndDeliver(world, requester, observer)
		local target = Player("Target-Realm", { guid = "Player-4619-00ABCDEF", mapID = 1453, x = 0.7, y = 0.2 })
		observer.units.target, observer.units.raid1 = target, target
		eq(world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target"), true)
		target.x = 0.71
		eq(world:Flush(observer), false); eq(#observer.sent, 0)
	end)
end)

test("player sightings: opt-out cancels queued answers and withdraws a live private result", function()
	WithWorld(function(world)
		local requester, observer = world:Client("Requester"), world:Client("Observer")
		Authorize(observer, requester.name); observer.members[requester.name:lower()] = requester.guild
		requester.members[observer.name:lower()] = observer.guild
		observer.ns.PlayerSightings.SetSharing(true, true)
		local id = StartAndDeliver(world, requester, observer)
		observer.units.mouseover = Player("Target-Realm")
		eq(world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "mouseover"), true)
		observer.ns.PlayerSightings.SetSharing(false, true)
		eq(#world.queue, 0, "the queued answer was removed")
		eq(observer.ns.PlayerSightings.SetSharing(true, true), true)
		local liveId = StartAndDeliver(world, requester, observer, "Other-Realm")
		observer.units.target = Player("Other-Realm")
		eq(world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target"), true)
		eq(world:Flush(observer, requester), true)
		eq(#requester.ns.PlayerSightings.Results(id), 0, "the first cancelled answer never arrived")
		eq(#requester.ns.PlayerSightings.Results(liveId), 1)
		observer.ns.PlayerSightings.SetSharing(false, true)
		local ok, why, withdrawal = world:Flush(observer, requester)
		eq(ok, true, why); assert(withdrawal.msg:match("^PS~X~1~%d+~Other%-Realm$"), withdrawal.msg)
		eq(#requester.ns.PlayerSightings.Results(liveId), 0)
	end)
end)

test("player sightings: malformed, secret, wrong-lane, instance and unverified data fail closed", function()
	WithWorld(function(world)
		local requester = world:Client("Requester")
		Authorize(requester)
		local started, id = world:As(requester, requester.ns.PlayerSightings.Start, "Target-Realm")
		eq(started, true); eq(world:Flush(requester), true)
		eq(select(2, requester.ns.PlayerSightings.Receive("WHISPER", "Observer-Realm", "PS~Q~1~9~Target-Realm")), "lane")
		eq(select(2, requester.ns.PlayerSightings.Receive("WHISPER", "Observer-Realm", "PS~R~bad")), "shape")
		eq(select(2, requester.ns.PlayerSightings.Receive("WHISPER", "Observer-Realm", SECRET)), "secret")
		local wire = ("PS~R~1~%d~Olympus~1453~123~568~42~0~Target-Realm"):format(id)
		local tooOld = wire:gsub("~42~0~", "~42~" .. (requester.ns.PlayerSightings.RECENT_TTL + 1) .. "~")
		for _, malformed in ipairs({
			wire .. "~gps", wire .. "~exact-unit", wire .. "~exact-group", wire .. "~exact-group~5", wire .. "~nearby~0",
			wire .. "~nearby~-1", wire .. "~nearby~many", tooOld,
		}) do
			eq(select(2, world:As(requester, requester.ns.PlayerSightings.Receive,
				"WHISPER", "Observer-Realm", malformed)), "shape", malformed)
		end
		eq(select(2, world:As(requester, requester.ns.PlayerSightings.Receive, "WHISPER", "Observer-Realm", wire)), "unverified")
		requester.members["observer-realm"] = "Olympus"
		requester.instance = true
		eq(select(2, world:As(requester, requester.ns.PlayerSightings.Receive, "WHISPER", "Observer-Realm", wire)), "stale")
		requester.instance = false
		world.now = world.now + requester.ns.PlayerSightings.REQUEST_TTL
		eq(select(2, world:As(requester, requester.ns.PlayerSightings.Receive, "WHISPER", "Observer-Realm", wire)), "stale")
	end)
	WithWorld(function(world)
		local observer = world:Client("Observer")
		Authorize(observer, "Leader-Realm")
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.Receive,
			"CHANNEL", "Leader-Realm", "PS~Q~1~1~Target-Realm")), "consent")
		observer.ns.PlayerSightings.SetSharing(true, true)
		observer.location = false
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.Receive,
			"CHANNEL", "Leader-Realm", "PS~Q~1~2~Target-Realm")), "location")
		observer.location, observer.netoff = true, true
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.Receive,
			"CHANNEL", "Leader-Realm", "PS~Q~1~3~Target-Realm")), "netoff")
	end)
end)

test("player sightings: an explicit area session returns only directly observed hostile players on that map", function()
	WithWorld(function(world)
		local requester, observer = world:Client("Requester"), world:Client("Observer")
		Authorize(observer, requester.name); observer.members[requester.name:lower()] = requester.guild
		requester.members[observer.name:lower()] = observer.guild
		observer.ns.PlayerSightings.SetSharing(true, true)

		observer.units.target = Player("Hostile One-Realm", { hostile = true })
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target")), "unrequested")
		observer.units.target = Player("Friendly One-Realm")
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target")), "unrequested")
		observer.units.target = Player("Other Map-Realm", { hostile = true, directPosition = true,
			mapID = 1429, x = 0.2, y = 0.3 })
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target")), "unrequested")

		local id = StartAreaAndDeliver(world, requester, observer, 1453)
		eq(world:Flush(observer, requester), true)
		local state = requester.ns.PlayerSightings.AreaSession(id)
		eq(state.mode, "area"); eq(state.scope, "hostile"); eq(state.mapID, 1453)
		eq(#state.sightings, 1)
		eq(state.sightings[1].target, "Hostile One-Realm")
		eq(state.sightings[1].kind, "nearby")
		eq(state.sightings[1].observer, nil, "area copies omit the observer")
		eq(state.sightings[1].observerGuild, nil, "area copies omit the observer guild")

		observer.units.nameplate1 = Player("Hostile Exact-Realm", { hostile = true, directPosition = true,
			mapID = 1453, x = 0.45, y = 0.55, guid = "Player-4619-00002222" })
		eq(world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "nameplate1"), true)
		eq(world:Flush(observer, requester), true)
		state = requester.ns.PlayerSightings.AreaSession(id)
		eq(#state.sightings, 2)
		local exact
		for _, row in ipairs(state.sightings) do if row.target == "Hostile Exact-Realm" then exact = row end end
		assert(exact, "the live hostile observation")
		eq(exact.kind, "exact-unit"); eq(exact.accuracyYards, 0); eq(exact.x, 450); eq(exact.y, 550)
	end)
end)

test("player sightings: area cache, observer answers and requester aggregate stay bounded", function()
	WithWorld(function(world)
		local requester, observer = world:Client("Requester"), world:Client("Observer")
		Authorize(observer, requester.name); observer.members[requester.name:lower()] = requester.guild
		requester.members[observer.name:lower()] = observer.guild
		observer.ns.PlayerSightings.SetSharing(true, true)
		local names = { "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India" }
		for i, name in ipairs(names) do
			observer.units.target = Player("Enemy " .. name .. "-Realm", { hostile = true, guid = ("Player-4619-%08d"):format(i) })
			world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target")
			world.now = world.now + 1
		end
		observer.units.target = nil
		local id = StartAreaAndDeliver(world, requester, observer)
		eq(#world.queue, observer.ns.PlayerSightings.AREA_MAX_PER_OBSERVER,
			"the six-row cap includes answers still pending in Comm")
		observer.units.target = Player("Enemy Juliet-Realm", { hostile = true, guid = "Player-4619-00000099" })
		local queued, why = world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target")
		eq(queued, false); eq(why, "replay", "the public observer result does not reveal queue pressure")
		eq(#world.queue, observer.ns.PlayerSightings.AREA_MAX_PER_OBSERVER,
			"a seventh live target cannot enter while six distinct rows are pending")
		local delivered = 0
		while world:Flush(observer, requester) do delivered = delivered + 1 end
		eq(delivered, observer.ns.PlayerSightings.AREA_MAX_PER_OBSERVER)
		eq(#requester.ns.PlayerSightings.AreaSession(id).sightings,
			observer.ns.PlayerSightings.AREA_MAX_PER_OBSERVER)
		eq(observer.ns.PlayerSightings.AREA_MAX_PER_OBSERVER, 6)
		eq(observer.ns.PlayerSightings.AREA_MAX_RESULTS, 48)
	end)
end)

test("player sightings: many reporters for one area target cannot starve a distinct target", function()
	WithWorld(function(world)
		local requester = world:Client("Requester")
		Authorize(requester)
		local started, id = world:As(requester, requester.ns.PlayerSightings.StartArea, 1453)
		eq(started, true)
		eq(world:Flush(requester), true, "the area query enters its waiting phase")
		local famous = ("PS~B~1~%d~Olympus~1453~123~568~42~0~Famous Enemy-Realm~nearby"):format(id)
		for i = 1, 48 do
			local a = string.char(65 + math.floor((i - 1) / 26))
			local b = string.char(65 + (i - 1) % 26)
			local reporter = "Observer" .. a .. b .. "-Realm"
			requester.members[reporter:lower()] = requester.guild
			local ok, why = world:As(requester, requester.ns.PlayerSightings.Receive,
				"WHISPER", reporter, famous)
			if i <= 2 then eq(ok, true, why) else eq(ok, false); eq(why, "capacity") end
		end
		local raw = requester.ns.PlayerSightings.Results(id)
		eq(#raw, 2, "corroboration for one target has a bounded fallback")
		eq(#requester.ns.PlayerSightings.AreaSession(id).sightings, 1,
			"the public area view still has one row for the repeated target")
		world.now = world.now + requester.ns.PlayerSightings.RATE_WINDOW + 1
		local distinctReporter = "ObserverBX-Realm"
		requester.members[distinctReporter:lower()] = requester.guild
		local distinct = ("PS~B~1~%d~Olympus~1453~321~654~42~0~Distinct Enemy-Realm~nearby"):format(id)
		local ok, why = world:As(requester, requester.ns.PlayerSightings.Receive,
			"WHISPER", distinctReporter, distinct)
		eq(ok, true, why)
		eq(#requester.ns.PlayerSightings.AreaSession(id).sightings, 2,
			"duplicate reporters cannot consume the 48 distinct-target slots")
	end)
end)

test("player sightings: area cancellation and consent withdrawal stop and remove area rows", function()
	WithWorld(function(world)
		local requester, observer = world:Client("Requester"), world:Client("Observer")
		Authorize(observer, requester.name); observer.members[requester.name:lower()] = requester.guild
		requester.members[observer.name:lower()] = observer.guild
		observer.ns.PlayerSightings.SetSharing(true, true)
		local id = StartAreaAndDeliver(world, requester, observer)
		observer.units.target = Player("Enemy-Realm", { hostile = true })
		eq(world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target"), true)
		eq(world:Flush(observer, requester), true)
		eq(#requester.ns.PlayerSightings.AreaSession(id).sightings, 1)
		observer.ns.PlayerSightings.SetSharing(false, true)
		local ok, why, withdrawal = world:Flush(observer, requester)
		eq(ok, true, why); assert(withdrawal.msg:match("^PS~W~1~%d+~Enemy%-Realm$"), withdrawal.msg)
		eq(#requester.ns.PlayerSightings.AreaSession(id).sightings, 0)
		eq(world:As(requester, requester.ns.PlayerSightings.CancelArea, id), true)
		local delivered, cancelWhy, cancel = world:Flush(requester, observer)
		eq(delivered, false); eq(cancelWhy, "not-found", "the observer already removed the remote on opt-out")
		assert(cancel.msg:match("^PS~D~1~%d+~1453$"), cancel.msg)
	end)
end)

test("player sightings: accepted cancellation releases sent capacity for later bounded area sessions", function()
	WithWorld(function(world)
		local requester, observer = world:Client("Requester"), world:Client("Observer")
		Authorize(observer, requester.name); observer.members[requester.name:lower()] = requester.guild
		requester.members[observer.name:lower()] = observer.guild
		observer.ns.PlayerSightings.SetSharing(true, true)
		for i, name in ipairs({ "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot" }) do
			observer.units.target = Player("Enemy " .. name .. "-Realm", { hostile = true,
				guid = ("Player-4619-%08d"):format(i) })
			world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target")
			world.now = world.now + 1
		end
		observer.units.target = nil
		local total = 0
		for _ = 1, 6 do
			local id = StartAreaAndDeliver(world, requester, observer)
			for _ = 1, observer.ns.PlayerSightings.AREA_MAX_PER_OBSERVER do
				local delivered, why = world:Flush(observer, requester)
				eq(delivered, true, why); total = total + 1
			end
			eq(world:As(requester, requester.ns.PlayerSightings.CancelArea, id), true)
			eq(world:Flush(requester, observer), true, "the D cancellation reaches the observer")
			world.now = world.now + observer.ns.PlayerSightings.RATE_WINDOW + 1
		end
		eq(total, 36, "cancelled sessions do not consume the observer-global 32-row sent cap")
	end)
end)

test("player sightings: an old cached answer consumes sent capacity only until its serialized row expires", function()
	WithWorld(function(world)
		local requester, observer = world:Client("Requester"), world:Client("Observer")
		Authorize(observer, requester.name); observer.members[requester.name:lower()] = requester.guild
		requester.members[observer.name:lower()] = observer.guild
		observer.ns.PlayerSightings.SetSharing(true, true)
		observer.units.nameplate1 = Player("Old Enemy-Realm", { hostile = true,
			guid = "Player-4619-0000A6ED" })
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "nameplate1")), "unrequested")
		observer.units.nameplate1 = nil
		world.now = world.now + observer.ns.PlayerSightings.RECENT_TTL
			- observer.ns.PlayerSightings.QUEUE_TTL - 1
		local id = StartAreaAndDeliver(world, requester, observer)
		eq(world:Flush(observer, requester), true)
		local state = requester.ns.PlayerSightings.AreaSession(id)
		eq(#state.sightings, 1)
		eq(state.sightings[1].expiresAt - world.now, 1,
			"the serialized age leaves one second on the requester row")
		world.now = world.now + 2
		world:As(observer, observer.ns.PlayerSightings.Tick)
		world:As(requester, requester.ns.PlayerSightings.Tick)
		eq(#requester.ns.PlayerSightings.AreaSession(id).sightings, 0)
		for i, suffix in ipairs({ "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot" }) do
			observer.units.target = Player("Fresh " .. suffix .. "-Realm", { hostile = true,
				guid = ("Player-4619-%08d"):format(700 + i) })
			local queued, why = world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target")
			eq(queued, true, why)
		end
		eq(#world.queue, observer.ns.PlayerSightings.AREA_MAX_PER_OBSERVER,
			"expiry releases both global sent capacity and the active area's observer slot")
		observer.ns.PlayerSightings.SetSharing(false, true)
		eq(#world.queue, 0, "the expired cached answer no longer occupies sent state or needs a withdrawal")
	end)
end)

test("player sightings: malformed, unauthorized and wrong-map area traffic fails closed", function()
	WithWorld(function(world)
		local requester, observer = world:Client("Requester"), world:Client("Observer")
		Authorize(requester); Authorize(observer, requester.name)
		observer.ns.PlayerSightings.SetSharing(true, true)
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.Receive,
			"WHISPER", requester.name, "PS~A~1~1~1453")), "lane")
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.Receive,
			"CHANNEL", "Unknown-Realm", "PS~A~1~1~1453")), "authority")
		local started, id = world:As(requester, requester.ns.PlayerSightings.StartArea, 1453)
		eq(started, true); eq(world:Flush(requester), true)
		requester.members[observer.name:lower()] = observer.guild
		local wrongMap = ("PS~B~1~%d~Olympus~1429~123~568~42~0~Enemy-Realm~nearby"):format(id)
		eq(select(2, world:As(requester, requester.ns.PlayerSightings.Receive,
			"WHISPER", observer.name, wrongMap)), "request")
		eq(select(2, world:As(requester, requester.ns.PlayerSightings.StartArea, 0)), "map")
		local secretStarted, secretWhy = world:As(requester, requester.ns.PlayerSightings.StartArea, SECRET)
		eq(secretStarted, false); eq(secretWhy, "map", "a secret map value fails closed without conversion")
	end)
end)

-- The wider "outsiders" area scope (an S after the A) and its compatibility with the build before it.
local HOSTILE_ONLY_BUILD = "tests/fixtures/player-sightings-area-hostile.lua"

local function AreaPair(world, options)
	options = options or {}
	local requester = world:Client("Requester", options.requester)
	local observer = world:Client("Observer", options.observer)
	Authorize(requester)
	Authorize(observer, requester.name); observer.members[requester.name:lower()] = requester.guild
	requester.members[observer.name:lower()] = observer.guild
	observer.ns.PlayerSightings.SetSharing(true, true)
	return requester, observer
end

local seenGUID = 0
local function Remembered(world, observer, name, options)
	options = options or {}
	seenGUID = seenGUID + 1
	options.guid = options.guid or ("Player-4619-%08d"):format(5000 + seenGUID)
	observer.units.target = Player(name, options)
	local _, why = world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target")
	observer.units.target = nil
	world.now = world.now + 1
	return why, options.guid
end

local function Drain(world, from, to)
	local msgs = {}
	while true do
		local delivered, why, item = world:Flush(from, to)
		if not item then break end
		eq(delivered, true, why)
		msgs[#msgs + 1] = item.msg
	end
	return msgs
end

local function AreaRows(requester, id)
	local out, n = {}, 0
	for _, row in ipairs(requester.ns.PlayerSightings.AreaSession(id).sightings) do out[row.target], n = row, n + 1 end
	return out, n
end

test("player sightings: the outsiders area scope adds not-hostile players outside Olympus guilds, never an Olympus guild, the observer or the group", function()
	WithWorld(function(world)
		local requester, observer = AreaPair(world)
		eq(Remembered(world, observer, "Hostile Rider-Realm", { hostile = true }), "unrequested")
		eq(Remembered(world, observer, "Lone Walker-Realm"), "unrequested", "no guild")
		eq(Remembered(world, observer, "Far Trader-Realm", { guild = "Silver Hand" }), "unrequested")
		eq(Remembered(world, observer, "Ember Friend-Realm", { guild = "Olympus Ember" }), "unrequested")
		observer.inGroup = true
		observer.units.party1 = Player("Party Friend-Realm", { guild = "Silver Hand", guid = "Player-4619-00000444" })
		eq(Remembered(world, observer, "Party Friend-Realm", { guild = "Silver Hand", guid = "Player-4619-00000444" }), "unrequested")
		observer.units.target = Player(observer.name, { guid = "Player-4619-00000001" })
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target")), "identity", "never the observer")
		observer.units.target = nil

		local started, id = world:As(requester, requester.ns.PlayerSightings.StartArea, 1453, "outsiders")
		eq(started, true)
		eq(requester.ns.PlayerSightings.AreaSession(id).scope, "outsiders")
		local delivered, why, query = world:Flush(requester, observer)
		eq(delivered, true, why)
		assert(query.msg:match("^PS~A~1~%d+~1453$"), "the area query itself is unchanged: " .. query.msg)
		local widened, widenWhy, scope = world:Flush(requester, observer)
		eq(widened, true, widenWhy)
		eq(scope.msg, ("PS~S~1~%d~1453~outsiders"):format(id), "the scope follows the query")
		eq(scope.dist, "CHANNEL")
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.Receive, "CHANNEL", requester.name, scope.msg)), "replay",
			"one widening per request")
		local msgs = Drain(world, observer, requester)
		eq(#msgs, 3, "the hostile row from the query, then the two outsiders from memory")
		for _, msg in ipairs(msgs) do
			if msg:find("Hostile Rider", 1, true) then eq(msg:find("~o$"), nil, msg)
			else assert(msg:find("~nearby~o$"), "a not-hostile row is labelled on the wire: " .. msg) end
		end
		local rows, n = AreaRows(requester, id)
		eq(n, 3)
		eq(rows["Hostile Rider-Realm"].hostile, true)
		eq(rows["Lone Walker-Realm"].hostile, false, "an unguilded player is an outsider")
		eq(rows["Far Trader-Realm"].hostile, false)
		eq(rows["Ember Friend-Realm"], nil, "an Olympus guild's player is never reported")
		eq(rows["Party Friend-Realm"], nil, "the observer's group is never reported")
		eq(rows[observer.name], nil)

		-- Live: a native exact point keeps its kind and yards before the label.
		observer.units.nameplate1 = Player("Exact Stranger-Realm", { guild = "Silver Hand", directPosition = true,
			mapID = 1453, x = 0.3, y = 0.4, guid = "Player-4619-00000555" })
		eq(world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "nameplate1"), true)
		msgs = Drain(world, observer, requester)
		eq(#msgs, 1); assert(msgs[1]:find("~exact%-unit~0~o$"), msgs[1])
		rows = AreaRows(requester, id)
		eq(rows["Exact Stranger-Realm"].hostile, false); eq(rows["Exact Stranger-Realm"].kind, "exact-unit")
		eq(rows["Exact Stranger-Realm"].accuracyYards, 0)
		-- Checked again as it leaves: a player who joined the group meanwhile is not sent.
		observer.units.target = Player("Late Joiner-Realm", { guild = "Silver Hand", guid = "Player-4619-00000777" })
		eq(world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target"), true)
		observer.units.party2 = Player("Late Joiner-Realm", { guild = "Silver Hand", guid = "Player-4619-00000777" })
		local sent, sentWhy = world:Flush(observer, requester)
		eq(sent, false); eq(sentWhy, "target")
		eq(AreaRows(requester, id)["Late Joiner-Realm"], nil)
	end)
	WithWorld(function(world)
		local requester, observer = AreaPair(world)
		for i = 1, 4 do
			Remembered(world, observer, "Hostile " .. string.char(64 + i) .. "-Realm", { hostile = true })
			Remembered(world, observer, "Outsider " .. string.char(64 + i) .. "-Realm", { guild = "Silver Hand" })
		end
		local started = world:As(requester, requester.ns.PlayerSightings.StartArea, 1453, "outsiders")
		eq(started, true)
		eq(world:Flush(requester, observer), true); eq(world:Flush(requester, observer), true)
		eq(#Drain(world, observer, requester), observer.ns.PlayerSightings.AREA_MAX_PER_OBSERVER,
			"the wider scope shares the same six-row observer cap")
	end)
end)

test("player sightings: a default area request stays hostile-only, and either side on the build before the scope still answers hostile rows", function()
	WithWorld(function(world)
		local requester, observer = AreaPair(world)
		Remembered(world, observer, "Lone Walker-Realm")
		Remembered(world, observer, "Hostile Rider-Realm", { hostile = true })
		local id = StartAreaAndDeliver(world, requester, observer)
		eq(requester.ns.PlayerSightings.AreaSession(id).scope, "hostile")
		eq(world:Flush(requester), false, "no widening follows a default request")
		local msgs = Drain(world, observer, requester)
		eq(#msgs, 1); eq(msgs[1]:find("~o$"), nil)
		local rows, n = AreaRows(requester, id)
		eq(n, 1); eq(rows["Hostile Rider-Realm"].hostile, true)
		observer.units.target = Player("Live Walker-Realm", { guid = "Player-4619-00000888" })
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target")), "unrequested",
			"a hostile request takes no not-hostile player live either")
		local forged = ("PS~B~1~%d~Olympus~1453~123~568~42~0~Lone Walker-Realm~nearby~o"):format(id)
		eq(select(2, world:As(requester, requester.ns.PlayerSightings.Receive, "WHISPER", observer.name, forged)), "scope",
			"a not-hostile row for a hostile request is refused")
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.Receive, "CHANNEL", requester.name,
			("PS~S~1~%d~1429~outsiders"):format(id))), "not-found", "a widening for another map")
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.Receive, "CHANNEL", requester.name,
			("PS~S~1~%d~1453~everyone"):format(id))), "shape")
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.Receive, "WHISPER", requester.name,
			("PS~S~1~%d~1453~outsiders"):format(id))), "lane")
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.Receive, "CHANNEL", "Unknown-Realm",
			("PS~S~1~%d~1453~outsiders"):format(id))), "authority")
		eq(select(2, world:As(requester, requester.ns.PlayerSightings.StartArea, 1453, "everyone")), "scope")
		eq(select(2, world:As(requester, requester.ns.PlayerSightings.StartArea, 1453, SECRET)), "scope")
	end)
	-- A widened request reaching an observer on the older build: it drops the S and answers hostile rows.
	WithWorld(function(world)
		local requester, observer = AreaPair(world, { observer = { source = HOSTILE_ONLY_BUILD } })
		Remembered(world, observer, "Lone Walker-Realm")
		Remembered(world, observer, "Hostile Rider-Realm", { hostile = true })
		local started, id = world:As(requester, requester.ns.PlayerSightings.StartArea, 1453, "outsiders")
		eq(started, true)
		eq(world:Flush(requester, observer), true, "the older build takes the unchanged query")
		local widened, why = world:Flush(requester, observer)
		eq(widened, false); eq(why, "shape", "the older build ignores the S")
		local msgs = Drain(world, observer, requester)
		eq(#msgs, 1); eq(msgs[1]:find("~o$"), nil)
		local rows, n = AreaRows(requester, id)
		eq(n, 1); eq(rows["Hostile Rider-Realm"].hostile, true)
	end)
	-- An older requester's area query reaching this build: no S ever comes, so only hostile rows.
	WithWorld(function(world)
		local requester, observer = AreaPair(world, { requester = { source = HOSTILE_ONLY_BUILD } })
		Remembered(world, observer, "Lone Walker-Realm")
		Remembered(world, observer, "Hostile Rider-Realm", { hostile = true })
		local id = StartAreaAndDeliver(world, requester, observer)
		local msgs = Drain(world, observer, requester)
		eq(#msgs, 1); eq(msgs[1]:find("~o$"), nil)
		eq(#requester.ns.PlayerSightings.AreaSession(id).sightings, 1, "the older requester parses the row")
	end)
end)

test("player sightings: replay, sender rate, cancellation and expiry are bounded", function()
	WithWorld(function(world)
		local observer = world:Client("Observer")
		observer.ns.PlayerSightings.SetSharing(true, true)
		Authorize(observer, "Leader-Realm")
		for id = 1, 3 do
			eq(observer.ns.PlayerSightings.Receive("CHANNEL", "Leader-Realm", ("PS~Q~1~%d~Target-Realm"):format(id)), true)
		end
		eq(select(2, observer.ns.PlayerSightings.Receive("CHANNEL", "Leader-Realm", "PS~Q~1~1~Target-Realm")), "replay")
		eq(select(2, observer.ns.PlayerSightings.Receive("CHANNEL", "Leader-Realm", "PS~Q~1~4~Target-Realm")), "rate")
	end)
	WithWorld(function(world)
		local observer = world:Client("Observer")
		observer.ns.PlayerSightings.SetSharing(true, true)
		for id = 1, observer.ns.PlayerSightings.QUERY_GLOBAL + 1 do
			local leader = "Leader" .. string.char(64 + id) .. "-Realm"
			Authorize(observer, leader)
			local ok, why = observer.ns.PlayerSightings.Receive("CHANNEL", leader,
				("PS~Q~1~%d~Target-Realm"):format(id))
			if id <= observer.ns.PlayerSightings.QUERY_GLOBAL then eq(ok, true, why)
			else eq(why, "rate") end
		end
	end)
	WithWorld(function(world)
		local requester = world:Client("Requester")
		Authorize(requester)
		local started, id = world:As(requester, requester.ns.PlayerSightings.Start, "Target-Realm")
		eq(started, true); eq(world:Flush(requester), true)
		eq(requester.ns.PlayerSightings.Cancel(id), true)
		eq(select(2, requester.ns.PlayerSightings.Session(id)), "not-found")
		eq(world:Flush(requester), true, "drain the private session's channel cancellation")
		local _, nextId = requester.ns.PlayerSightings.Start("Target-Realm")
		eq(world:Flush(requester), true)
		world.now = world.now + requester.ns.PlayerSightings.REQUEST_TTL
		requester.ns.PlayerSightings.Tick()
		eq(requester.ns.PlayerSightings.Session(nextId).status, "complete")
		world.now = world.now + requester.ns.PlayerSightings.RESULT_KEEP
		requester.ns.PlayerSightings.Tick()
		eq(select(2, requester.ns.PlayerSightings.Session(nextId)), "not-found")
	end)
end)

-- 1.2.5.1, the quiet presence (Core.lua's ns.QuietPresence): an observer that has it on observes and
-- answers nothing and withdraws nothing (what it answered before expires at the requester, as after
-- a logout); a requester that has it on still sends its own request, a read.
test("player sightings: quiet presence answers and withdraws nothing, its own request still goes, and it answers again once off", function()
	WithWorld(function(world)
		local requester, observer = world:Client("Requester"), world:Client("Observer")
		for _, c in ipairs({ requester, observer }) do c.ns.QuietPresence = function() return c.quiet == true end end
		Authorize(observer, requester.name); observer.members[requester.name:lower()] = requester.guild
		requester.members[observer.name:lower()] = observer.guild
		observer.ns.PlayerSightings.SetSharing(true, true)
		-- An answer delivered before it began.
		local id = StartAndDeliver(world, requester, observer)
		observer.units.target = Player("Target-Realm")
		eq(world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target"), true)
		eq(world:Flush(observer, requester), true)
		eq(#requester.ns.PlayerSightings.Results(id), 1)
		-- On: no withdrawal of it, no new observation, no answer to a new request.
		observer.quiet = true
		world:As(observer, observer.ns.PlayerSightings.Tick)
		eq(world:Flush(observer), false, "nothing queued, not even a withdrawal")
		eq(#requester.ns.PlayerSightings.Results(id), 1, "the requester's row stays until it expires")
		observer.units.mouseover = Player("Target-Realm")
		eq(select(2, world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "mouseover")), "quiet")
		requester.quiet = true
		local started = world:As(requester, requester.ns.PlayerSightings.Start, "Other-Realm")
		eq(started, true)
		local received, why, query = world:Flush(requester, observer)
		assert(query and query.msg:match("^PS~Q~1~%d+~Other%-Realm$"), "a quiet requester's own request still leaves")
		eq(received, false); eq(why, "quiet", "a quiet observer takes none")
		eq(world:Flush(observer), false)
		-- Off: it answers again.
		observer.quiet = false
		local laterId = StartAndDeliver(world, requester, observer, "Later-Realm")
		observer.units.target = Player("Later-Realm")
		eq(world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target"), true)
		eq(world:Flush(observer, requester), true)
		eq(#requester.ns.PlayerSightings.Results(laterId), 1)
	end)
end)

test("player sightings: the requester's own sightings enter its own area request with no other member and nothing sent", function()
	WithWorld(function(world)
		-- A security member alone on the map, without the sharing consent: what its own game shows
		-- still belongs in its own request (the Stormwind report: someone on screen, nothing marked).
		local requester = world:Client("Requester")
		Authorize(requester)
		eq(requester.ns.PlayerSightings.Sharing(), false)
		requester.units.nameplate3 = Player("Early Horde-Realm", { hostile = true, guid = "Player-4619-00003001" })
		local started, id = world:As(requester, requester.ns.PlayerSightings.StartArea, 1453, "outsiders")
		eq(started, true)
		local rows, n = AreaRows(requester, id)
		eq(n, 1, "a player already on screen when the request starts")
		eq(rows["Early Horde-Realm"].own, true)
		eq(rows["Early Horde-Realm"].hostile, true)
		eq(rows["Early Horde-Realm"].kind, "nearby")
		eq(rows["Early Horde-Realm"].x, 123); eq(rows["Early Horde-Realm"].y, 568)
		eq(rows["Early Horde-Realm"].observer, nil)

		requester.units.target = Player("Exact Stranger-Realm", { guild = "Silver Hand", directPosition = true,
			mapID = 1453, x = 0.3, y = 0.4, guid = "Player-4619-00003002" })
		eq(world:As(requester, requester.ns.PlayerSightings.ObserveUnit, "target"), true)
		requester.units.mouseover = Player("Ember Friend-Realm", { guild = "Olympus Ember", guid = "Player-4619-00003003" })
		world:As(requester, requester.ns.PlayerSightings.ObserveUnit, "mouseover")
		requester.units.nameplate4 = Player("Far Horde-Realm", { hostile = true, directPosition = true,
			mapID = 1429, x = 0.2, y = 0.2, guid = "Player-4619-00003004" })
		world:As(requester, requester.ns.PlayerSightings.ObserveUnit, "nameplate4")
		rows, n = AreaRows(requester, id)
		eq(n, 2)
		eq(rows["Exact Stranger-Realm"].hostile, false, "an outsider, in the scope that asked for one")
		eq(rows["Exact Stranger-Realm"].kind, "exact-unit"); eq(rows["Exact Stranger-Realm"].own, true)
		eq(rows["Ember Friend-Realm"], nil, "an Olympus guild's player is never a row")
		eq(rows["Far Horde-Realm"], nil, "another map stays out")

		local sentBefore = #world.queue
		for _, item in ipairs(world.queue) do assert(not item.msg:find("^PS~B~"), "nothing answers on the wire: " .. item.msg) end
		eq(sentBefore <= 2, true, "only the query and its scope are queued")
		world.now = world.now + requester.ns.PlayerSightings.RESULT_TTL + 1
		world:As(requester, requester.ns.PlayerSightings.Tick)
		eq(requester.ns.PlayerSightings.AreaSession(id), nil, "the request and its own rows expire on the usual clock")
	end)
	WithWorld(function(world)
		-- The hostile scope keeps outsiders out of own rows too, and an observer's network rows still
		-- arrive beside them.
		local requester, observer = AreaPair(world)
		local id = StartAreaAndDeliver(world, requester, observer, 1453)
		requester.units.target = Player("Lone Walker-Realm", { guid = "Player-4619-00003005" })
		world:As(requester, requester.ns.PlayerSightings.ObserveUnit, "target")
		requester.units.target = Player("Seen Twice-Realm", { hostile = true, guid = "Player-4619-00003006" })
		eq(world:As(requester, requester.ns.PlayerSightings.ObserveUnit, "target"), true)
		-- The same moment from the network: its serialized age is rounded up by QUEUE_TTL, so it
		-- reads as the same second. A tie goes to the own row, whatever order pairs walks them in.
		observer.units.target = Player("Seen Twice-Realm", { hostile = true, guid = "Player-4619-00003006" })
		world.now = world.now + requester.ns.PlayerSightings.QUEUE_TTL
		eq(world:As(observer, observer.ns.PlayerSightings.ObserveUnit, "target"), true)
		eq(world:Flush(observer, requester), true)
		local rows, n = AreaRows(requester, id)
		eq(n, 1, "one row per target")
		eq(rows["Lone Walker-Realm"], nil)
		eq(rows["Seen Twice-Realm"].own, true, "a tie keeps the own row")
		eq(rows["Seen Twice-Realm"].observer, nil)
	end)
end)


test("player sightings: participation withdrawal rejects signed requesters and retained result access", function()
	WithWorld(function(world)
		local requester = world:Client("Requester")
		Authorize(requester)
		requester.participating = false
		local ok, why = world:As(requester, requester.ns.PlayerSightings.CanRequest)
		eq(ok, false); eq(why, "federation")
		eq(world:As(requester, requester.ns.PlayerSightings.Start, "Target-Realm"), false)
		eq(#world.queue, 0)
		requester.participating = true
		requester.deniedPeers[requester.name:lower()] = true
		ok, why = world:As(requester, requester.ns.PlayerSightings.CanRequest)
		eq(ok, false); eq(why, "authority", "participation is distinct from a signed requester role")
		requester.deniedPeers[requester.name:lower()] = nil
		eq(world:As(requester, requester.ns.PlayerSightings.CanRequest), true)
		requester.participating = false
		eq(requester.ns.PlayerSightings.Session(1), nil)
		eq(#requester.ns.PlayerSightings.Results(1), 0)
	end)
end)
