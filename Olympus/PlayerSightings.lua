local ADDON, ns = ...

-- A request-bound, voluntary last-seen network. It is deliberately not continuous tracking.
-- An authorized requester can enter one exact Name-Realm, or explicitly open a short hostile-player
-- area session for one zone/micro map. Observers answer only after the game itself exposes a player
-- as target, mouseover or a nameplate. The client remembers only
-- a bounded, memory-only last-seen record while both consent choices remain on. If WoW returns a
-- map or world position for that observed unit, the answer carries that native point. Otherwise,
-- if the same identity is a real party/raid unit, it tries that group token; the final fallback is
-- the observer's encounter point. Every point is serialized to 0.1% map.
--
--   PS~Q~1~<request>~<Name-Realm>                                  channel query
--   PS~C~1~<request>~<Name-Realm>                                  channel cancel
--   PS~R~1~<request>~<guild>~<map>~<x>~<y>~<layer>~<age>~<target>[~<kind>[~<yards>]]
--   PS~X~1~<request>~<Name-Realm>                                  private withdrawal
--   PS~A~1~<request>~<map>                                         channel hostile-area query
--   PS~D~1~<request>~<map>                                         channel hostile-area cancel
--   PS~S~1~<request>~<map>~outsiders                               channel area-scope extension
--   PS~B~1~<request>~<guild>~<map>~<x>~<y>~<layer>~<age>~<target>[~<kind>[~<yards>]][~o]
--   PS~W~1~<request>~<Name-Realm>                                  private area-row withdrawal
--
-- An area request is "hostile" (players the observer's client reports as attackable or enemy) unless
-- the requester follows its A with an S for the same request and map: "outsiders" also covers a
-- player the observer's client reports as not hostile when the guild that client reads for him is
-- not an Olympus guild, or he has none; never the observer, a member of the observer's group or an
-- Olympus guild's player. Builds before S ignore it (an unknown mode), so they keep answering only
-- hostile rows; a request with no S stays "hostile". Only a not-hostile B row carries the final
-- "~o", and only an S-extended request accepts one.
--
-- The requester's own client is an observer of its own area request too: a player its own game
-- shows it (at the start, and while the request lives) enters that request as an "own" row, with
-- no message sent and no sharing consent needed, since nothing leaves the client.
--
-- Q/C senders and R/X recipients are server-stamped by the addon channel. Q is accepted only
-- from Olympus's existing signed authority (Moderation.IsIssuer), or from the addon's pinned
-- author identity so the developer can exercise the same live path; a local guild roster never
-- grants either role. R and X go only to the exact requester whose live Q this observer accepted.

local Sightings = {}
ns.PlayerSightings = Sightings

Sightings.VERSION = 1
-- Version 6 also covers a visible, explicitly started hostile-area session. That session reports
-- only player units this client directly saw and never exposes the observer through the public API.
-- Version 7 covers the wider "outsiders" area scope (not-hostile players outside Olympus guilds).
Sightings.CONSENT_VERSION = 7
Sightings.GRID = 1                 -- thousandths, rounded to 0.1% of the map
Sightings.QUEUE_TTL = 5
Sightings.REQUEST_TTL = 10 * 60
Sightings.RESULT_TTL = 15 * 60
Sightings.RESULT_KEEP = 15 * 60
Sightings.RECENT_TTL = 15 * 60
Sightings.RECENT_MAX = 64
Sightings.AREA_REQUEST_TTL = 5 * 60
Sightings.AREA_MAX_PER_OBSERVER = 6
Sightings.AREA_MAX_RESULTS = 48
Sightings.AREA_SCOPES = { hostile = true, outsiders = true }
Sightings.LAYER_FRESH = 30
Sightings.MAX_ACTIVE = 3
Sightings.MAX_SESSIONS = 8
Sightings.MAX_REMOTE = 24
Sightings.MAX_RESULTS = 24
Sightings.MAX_QUEUED = 8
Sightings.MAX_SENT = 32
Sightings.REPLAY_MAX = 128
Sightings.RATE_SENDERS = 64
Sightings.RATE_WINDOW = 60
Sightings.QUERY_PER_SENDER = 3
Sightings.QUERY_GLOBAL = 20
Sightings.RESULT_PER_SENDER = 6
Sightings.RESULT_GLOBAL = 48

local requests, requestCount, activeCount = {}, 0, 0
local remotes, remoteCount = {}, 0
local queued, queuedCount = {}, 0
local sent, sentCount = {}, 0
local seenQueries, seenQueryCount = {}, 0
local seenResults, seenResultCount = {}, 0
local queryRates, queryRateCount = {}, 0
local resultRates, resultRateCount = {}, 0
local admitBuckets, admitBucketCount = {}, 0
local admitStats = {}
local recent, recentCount, recentEpoch = {}, 0, 0
local queryGlobal = { tokens = Sightings.QUERY_GLOBAL, t = 0 }
local resultGlobal = { tokens = Sightings.RESULT_GLOBAL, t = 0 }
local sequence = math.random and math.random(1, 99999) or 1
local responseSequence = 0
local AREA_CORROBORATION = 2 -- best row plus one bounded fallback for a later W withdrawal

local function Now() return ns.Now() end
local function Secret(...)
	if type(issecretvalue) ~= "function" then return false end
	for i = 1, select("#", ...) do if issecretvalue((select(i, ...))) then return true end end
	return false
end
local function Whole(n, low, high)
	if Secret(n) then return nil end
	local ok, value = pcall(tonumber, n)
	if not ok or Secret(value) then return nil end
	n = value
	return n and n == math.floor(n) and n >= low and n <= high and n or nil
end
local function Same(a, b)
	return type(a) == "string" and type(b) == "string" and a:lower() == b:lower()
end
local function Ask(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, value = pcall(fn, ...)
	if not ok or Secret(value) then return nil end
	return value
end
local function Changed(id, action)
	ns.Fire("PLAYER_SIGHTINGS_CHANGED", id, action)
end

-- Exact wire identity: unlike ns.FullName, this never supplies a missing realm. Forever may put
-- a surname in the name, so spaces are valid in the character part; wire separators are not.
local function Canonical(value)
	if Secret(value) or type(value) ~= "string" or value == "" or #value > 96
		or value:find("[~|%c]") or value:match("^%s") or value:match("%s$") then return nil end
	local ok, normal = pcall(ns.Normal, value)
	if not ok or Secret(normal) or type(normal) ~= "string" then return nil end
	local name, realm = normal:match("^([^%-]+)%-([^%-]+)$")
	if not name or not realm or name:find("  ", 1, true)
		or not name:match("^[%a\128-\255][%a\128-\255 ]*$")
		or not realm:match("^[%w\128-\255]+$") then return nil end
	return name .. "-" .. realm
end
Sightings.Canonical = Canonical

local function NetOff()
	local M = ns.Moderation
	if type(M) ~= "table" or M.missing or type(M.SelfOff) ~= "function" then return false end
	local ok, off = pcall(M.SelfOff)
	return not ok or (off ~= nil and off ~= false)
end
-- Quiet presence (1.2.5.1, Core.lua): this client observes and answers nothing, and withdraws
-- nothing either (Comm.QUIET_WORDS). This client's own requests, which are reads, still go.
local function Quiet() return ns.QuietPresence ~= nil and ns.QuietPresence() == true end

local function SignedRequester(value)
	if not ns.SharedPeerAllowed(value) then return nil end
	local name = Canonical(value)
	local M = ns.Moderation
	if not name or type(M) ~= "table" or M.missing or type(M.IsIssuer) ~= "function" then return nil end
	local ok, yes = pcall(M.IsIssuer, name)
	if not ok then return nil end
	if yes ~= true then
		local W = ns.Workshop
		if type(W) ~= "table" or W.missing or type(W.IsAuthorName) ~= "function" then return nil end
		local authorOK, author = pcall(W.IsAuthorName, name)
		if not authorOK or author ~= true then return nil end
	end
	if type(M.Hides) == "function" then
		local safe, hidden = pcall(M.Hides, name)
		if not safe or hidden then return nil end
	end
	return name
end

local function Sharing()
	return ns.SharedToolsHere() and type(ns.db) == "table" and ns.db.playerSightings == true
		and ns.db.playerSightingsConsentVersion == Sightings.CONSENT_VERSION
end
Sightings.Sharing = Sharing

local function LocationSharing()
	local L = ns.Layers
	if type(L) ~= "table" or L.missing or type(L.Sharing) ~= "function" then return false end
	local ok, on = pcall(L.Sharing)
	return ok and on == true
end

local function InInstance()
	if type(IsInInstance) ~= "function" then return false end
	local ok, inside = pcall(IsInInstance)
	return not ok or inside == true
end

local function GuardedComm()
	local C = ns.Comm
	return type(C) == "table" and type(C.Send) == "function" and type(C.Whisper) == "function"
		and type(C.CancelQueued) == "function" and C or nil
end

function Sightings.CanRequest()
	if not ns.SharedToolsHere() then return false, "federation" end
	if type(ns.IsMember) ~= "function" or ns.IsMember() ~= true or type(ns.me) ~= "string" then return false, "member" end
	if NetOff() then return false, "netoff" end
	if InInstance() then return false, "instance" end
	if not SignedRequester(ns.me) then return false, "authority" end
	local C = GuardedComm()
	if not C then return false, "transport" end
	if type(C.ChannelReady) ~= "function" or C.ChannelReady() ~= true then return false, "channel" end
	local channel = type(C.ChannelName) == "function" and C.ChannelName() or nil
	if type(channel) ~= "string" or channel == "" then return false, "channel" end
	return true
end

local function ObserverEligible()
	if type(ns.IsMember) ~= "function" or ns.IsMember() ~= true then return false, "member" end
	if NetOff() then return false, "netoff" end
	if Quiet() then return false, "quiet" end
	if not Sharing() then return false, "consent" end
	if not LocationSharing() then return false, "location" end
	if InInstance() then return false, "instance" end
	if not GuardedComm() then return false, "transport" end
	return true
end

local function Guild(value)
	if Secret(value) or type(value) ~= "string" or value == "" or #value > 48 or value:find("[~|%c]") then return nil end
	return type(ns.IsFederation) == "function" and ns.IsFederation(value) == true and value or nil
end

local function OwnGuild()
	if type(GetGuildInfo) ~= "function" then return nil end
	local ok, guild = pcall(GetGuildInfo, "player")
	return ok and Guild(guild) or nil
end

-- Results may come from any verified Olympus member. The guild in R is only a lookup key: the
-- local signed/census authority must independently bind that server-stamped sender to it.
local function VerifiedObserver(sender, guild, now)
	sender, guild = Canonical(sender), Guild(guild)
	if not sender or not guild or Same(sender, ns.me) or not ns.SharedPeerAllowed(sender, guild) then return nil end
	local M = ns.Moderation
	if type(M) == "table" and type(M.Hides) == "function" then
		local ok, hidden = pcall(M.Hides, sender, guild)
		if not ok or hidden then return nil end
	end
	local C = ns.Channels
	if type(C) ~= "table" or type(C.VerifiedLevel) ~= "function" then return nil end
	local ok, level, verified = pcall(C.VerifiedLevel, sender, guild)
	if not ok or type(level) ~= "number" or level < 1 or verified ~= true then return nil end
	if type(C.Admit) == "function" then
		local known = admitBuckets[sender] ~= nil
		if not known and admitBucketCount >= Sightings.RATE_SENDERS then return nil end
		local admitted = C.Admit(sender, guild, "", now, {
			level = 1, buckets = admitBuckets, stats = admitStats, where = "player sighting",
		})
		-- Channels.Admit creates a bucket before its final identity checks. Keep that failed sender
		-- out of this private lane's bounded registry, just as HopSightings does.
		if admitted ~= true and not known then admitBuckets[sender] = nil end
		if admitted ~= true then return nil end
		if not known and admitBuckets[sender] then admitBucketCount = admitBucketCount + 1 end
	end
	return sender, guild
end

local function Bucket(bucket, now, maximum)
	if type(bucket.t) ~= "number" or now < bucket.t or now - bucket.t > Sightings.RATE_WINDOW * 3 then
		bucket.tokens, bucket.t = maximum, now
	end
	local elapsed = math.max(0, now - bucket.t)
	bucket.tokens = math.min(maximum, (tonumber(bucket.tokens) or maximum) + elapsed * maximum / Sightings.RATE_WINDOW)
	bucket.t = now
	if bucket.tokens < 1 then return false end
	bucket.tokens = bucket.tokens - 1
	return true
end

local function SenderRate(list, count, key, now, maximum)
	local bucket = list[key]
	if not bucket then
		if count >= Sightings.RATE_SENDERS then
			local oldest
			for name, item in pairs(list) do if not oldest or item.t < list[oldest].t then oldest = name end end
			if not oldest or now - list[oldest].t <= Sightings.RATE_WINDOW * 3 then return false, count end
			list[oldest], count = nil, count - 1
		end
		bucket, count = { tokens = maximum, t = now }, count + 1
		list[key] = bucket
	end
	return Bucket(bucket, now, maximum), count
end

local function ReplayAdd(list, count, key, now)
	if list[key] then return false, count end
	if count >= Sightings.REPLAY_MAX then
		local oldest
		for wire, at in pairs(list) do if not oldest or at < list[oldest] then oldest = wire end end
		if oldest then list[oldest], count = nil, count - 1 end
	end
	list[key], count = now, count + 1
	return true, count
end

local function PruneBounded(now)
	for key, at in pairs(seenQueries) do
		if now - at > Sightings.RESULT_TTL * 3 then seenQueries[key], seenQueryCount = nil, seenQueryCount - 1 end
	end
	for key, at in pairs(seenResults) do
		if now - at > Sightings.RESULT_TTL * 3 then seenResults[key], seenResultCount = nil, seenResultCount - 1 end
	end
	for key, bucket in pairs(queryRates) do
		if now - bucket.t > Sightings.RATE_WINDOW * 3 then queryRates[key], queryRateCount = nil, queryRateCount - 1 end
	end
	for key, bucket in pairs(resultRates) do
		if now - bucket.t > Sightings.RATE_WINDOW * 3 then resultRates[key], resultRateCount = nil, resultRateCount - 1 end
	end
	for key, bucket in pairs(admitBuckets) do
		if type(bucket) ~= "table" or type(bucket.t) ~= "number" or now - bucket.t > Sightings.RATE_WINDOW * 3 then
			admitBuckets[key], admitBucketCount = nil, admitBucketCount - 1
		end
	end
end

local function OpenMap(mapID)
	if not Whole(mapID, 1, 9999999) or type(C_Map) ~= "table" or type(C_Map.GetMapInfo) ~= "function" then return false end
	local ok, info = pcall(C_Map.GetMapInfo, mapID)
	if not ok or type(info) ~= "table" or Secret(info.mapType) then return false end
	local T = type(Enum) == "table" and type(Enum.UIMapType) == "table" and Enum.UIMapType or {}
	return info.mapType == (T.Zone or 3) or info.mapType == (T.Micro or 5)
end

local function Grid(value)
	return math.max(0, math.min(1000, math.floor(value * 1000 / Sightings.GRID + 0.5) * Sightings.GRID))
end

local function ValidPoint(x, y)
	return not Secret(x, y) and type(x) == "number" and type(y) == "number"
		and x == x and y == y and x > -math.huge and x < math.huge and y > -math.huge and y < math.huge
		and x >= 0 and x <= 1 and y >= 0 and y <= 1 and not (x == 0 and y == 0)
end

-- Some supported clients expose a visible unit through UnitPosition even when their C_Map unit
-- method returns nil. Olympus already ships HereBeDragons for exactly this world-to-map conversion.
-- Use only the observer's current open zone/micro map and disallow out-of-bounds conversion, so a
-- different instance or an unsupported token fails closed instead of becoming an invented point.
local function WorldMapSpot(unit)
	if LibStub == nil or type(C_Map) ~= "table" or type(C_Map.GetBestMapForUnit) ~= "function" then return nil end
	local mapID = Ask(C_Map.GetBestMapForUnit, "player")
	if not OpenMap(mapID) then return nil end
	local okLib, hbd = pcall(function() return LibStub("HereBeDragons-2.0", true) end)
	if not okLib or type(hbd) ~= "table" or type(hbd.GetUnitWorldPosition) ~= "function"
		or type(hbd.GetZoneCoordinatesFromWorldInstance) ~= "function" then return nil end
	local okWorld, wx, wy, instance = pcall(hbd.GetUnitWorldPosition, hbd, unit)
	if not okWorld or Secret(wx, wy, instance) or type(wx) ~= "number" or type(wy) ~= "number"
		or type(instance) ~= "number" then return nil end
	local okMap, x, y = pcall(hbd.GetZoneCoordinatesFromWorldInstance, hbd, wx, wy, instance, mapID, false)
	if not okMap or not ValidPoint(x, y) then return nil end
	return mapID, Grid(x), Grid(y)
end

local function MapSpot(unit)
	if type(C_Map) == "table" and type(C_Map.GetBestMapForUnit) == "function"
		and type(C_Map.GetPlayerMapPosition) == "function" then
		local mapID = Ask(C_Map.GetBestMapForUnit, unit)
		if OpenMap(mapID) then
			local pos = Ask(C_Map.GetPlayerMapPosition, mapID, unit)
			if pos then
				local ok, x, y = pcall(function() return pos:GetXY() end)
				if ok and ValidPoint(x, y) then return mapID, Grid(x), Grid(y) end
			end
		end
	end
	return WorldMapSpot(unit)
end

local function LayerFor(mapID)
	local layer = 0
	local L = ns.Layers
	if type(L) == "table" and type(L.Mine) == "function" then
		local safe, mine = pcall(L.Mine)
		local now = Now()
		if safe and type(mine) == "table" and not Secret(mine.mapID, mine.zoneUID, mine.t)
			and mine.mapID == mapID and Whole(mine.zoneUID, 1, 2147483647)
			and type(mine.t) == "number" and now - mine.t >= 0 and now - mine.t <= Sightings.LAYER_FRESH then
			layer = mine.zoneUID
		end
	end
	return layer
end

local function Spot()
	local mapID, x, y = MapSpot("player")
	if not mapID then return nil end
	return mapID, x, y, LayerFor(mapID)
end

local function VisibleUnit(unit)
	if type(UnitIsVisible) ~= "function" then return true end
	return Ask(UnitIsVisible, unit) == true
end

local function UnitIdentity(unit, name, guid)
	if Ask(UnitExists, unit) ~= true or Ask(UnitIsPlayer, unit) ~= true or not VisibleUnit(unit) then return false end
	local unitGUID = Ask(UnitGUID, unit)
	local unitName = Canonical(Ask(ns.UnitFullName, unit))
	return type(unitGUID) == "string" and unitGUID == guid and unitName and Same(unitName, name)
end

-- A visually observed unit is never promoted to an exact point from its name alone. It must be
-- the same GUID and canonical identity as a native party/raid token; where available UnitIsUnit
-- must agree too. Only then do we ask WoW for that group token's position.
local function ExactGroupSpot(observedUnit, name, guid)
	local groups = { { "party", 4 }, { "raid", 40 } }
	for _, group in ipairs(groups) do
		for i = 1, group[2] do
			local token = group[1] .. i
			if UnitIdentity(token, name, guid) then
				local same = true
				if type(UnitIsUnit) == "function" then same = Ask(UnitIsUnit, observedUnit, token) == true end
				if same then
					local mapID, x, y = MapSpot(token)
					if mapID then return token, mapID, x, y end
				end
			end
		end
	end
	return nil
end

-- The observed GUID is one of the observer's party or raid members (the same native tokens that
-- ExactGroupSpot reads). Outside a group nothing is enumerated.
local function GroupMember(guid)
	if type(guid) ~= "string" then return false end
	if type(IsInGroup) == "function" and Ask(IsInGroup) ~= true then return false end
	for _, group in ipairs({ { "party", 4 }, { "raid", 40 } }) do
		for i = 1, group[2] do
			if Ask(UnitGUID, group[1] .. i) == guid then return true end
		end
	end
	return false
end

-- A not-hostile player the wider area scope may report: the guild this client's game reads for the
-- observed player is not an Olympus guild, or he has none, and he is not in the observer's group. A
-- secret or unreadable guild, or no federation check, fails closed.
local function Outsider(unit, guid)
	if type(GetGuildInfo) ~= "function" or type(ns.IsFederation) ~= "function" then return false end
	local ok, guild = pcall(GetGuildInfo, unit)
	if not ok or Secret(guild) or (guild ~= nil and type(guild) ~= "string") then return false end
	if type(guild) == "string" and guild ~= "" then
		local fine, federation = pcall(ns.IsFederation, guild)
		if not fine or (federation ~= false and federation ~= nil) then return false end
	end
	return not GroupMember(guid)
end

-- Whether an area request of this scope takes a row with these flags.
local function AreaTakes(remote, hostile, outsider)
	if hostile == true then return true end
	return remote.scope == "outsiders" and outsider == true
end

local RESPONSE_QUALITY = { nearby = 1, ["exact-group"] = 2, ["exact-unit"] = 3 }

local function PreferResponse(existing, seenAt, kind)
	if type(existing) ~= "table" then return true end
	local previousAt = tonumber(existing.seenAt) or -math.huge
	if seenAt ~= previousAt then return seenAt > previousAt end
	return (RESPONSE_QUALITY[kind] or 0) > (RESPONSE_QUALITY[existing.kind] or 0)
end

local function Snapshot(request)
	if type(request) ~= "table" then return nil end
	local n = 0
	local targets = {}
	for _, result in pairs(request.results) do
		local key = request.mode == "area" and type(result.target) == "string" and result.target:lower() or nil
		if not key or not targets[key] then n = n + 1; if key then targets[key] = true end end
	end
	return { id = request.id, mode = request.mode or "player", scope = request.mode == "area" and (request.scope or "hostile") or nil,
		target = request.target, mapID = request.mapID, status = request.phase, phase = request.phase,
		createdAt = request.createdAt, sentAt = request.sentAt, expiresAt = request.expiresAt,
		resultCount = n }
end

local function ResultCopy(result)
	local out = { requestId = result.requestId, target = result.target, reporter = result.reporter,
		observer = result.reporter, observerGuild = result.observerGuild,
		mapID = result.mapID, x = result.x, y = result.y, layer = result.layer,
		seenAt = result.seenAt, receivedAt = result.receivedAt, expiresAt = result.expiresAt,
		kind = result.kind or "nearby" }
	if result.accuracyYards ~= nil then out.accuracyYards = result.accuracyYards end
	return out
end

local function AreaResultCopy(result)
	local out = { requestId = result.requestId, target = result.target,
		mapID = result.mapID, x = result.x, y = result.y, layer = result.layer,
		seenAt = result.seenAt, receivedAt = result.receivedAt, expiresAt = result.expiresAt,
		kind = result.kind or "nearby", hostile = result.hostile ~= false }
	if result.accuracyYards ~= nil then out.accuracyYards = result.accuracyYards end
	-- This client's own observation: says nothing about any other member.
	if result.own == true then out.own = true end
	return out
end

local function ClearRecent()
	if recentCount == 0 then return false end
	recent, recentCount, recentEpoch = {}, 0, recentEpoch + 1
	return true
end

local function PruneRecent(now)
	for key, record in pairs(recent) do
		if type(record) ~= "table" or type(record.at) ~= "number" or now - record.at < 0
			or now - record.at > Sightings.RECENT_TTL then
			recent[key], recentCount = nil, recentCount - 1
		end
	end
end

local function Remember(target, mapID, x, y, layer, kind, accuracyYards, hostile, outsider, now)
	PruneRecent(now)
	local key = target:lower()
	if not recent[key] and recentCount >= Sightings.RECENT_MAX then
		local oldest
		for candidate, record in pairs(recent) do
			if not oldest or record.at < recent[oldest].at then oldest = candidate end
		end
		if oldest then recent[oldest], recentCount = nil, recentCount - 1 end
	end
	local record = { target = target, mapID = mapID, x = x, y = y, layer = layer, kind = kind,
		accuracyYards = accuracyYards, hostile = hostile == true, outsider = hostile ~= true and outsider == true,
		at = now, epoch = recentEpoch }
	if not recent[key] then recentCount = recentCount + 1 end
	recent[key] = record
	return record
end

local function DropQueued(job, why)
	if type(job) ~= "table" or job.cancelled then return false end
	job.cancelled = true
	if job.slot and queued[job.slot] == job then queued[job.slot], queuedCount = nil, queuedCount - 1 end
	local C = ns.Comm
	if type(C) == "table" and type(C.CancelQueued) == "function" then C.CancelQueued(Sightings, job.key, why or "cancelled") end
	return true
end

local function CancelQueuedFor(remote, why)
	local jobs = {}
	for _, job in pairs(queued) do if not remote or job.remote == remote then jobs[#jobs + 1] = job end end
	local changed = false
	for _, job in ipairs(jobs) do if DropQueued(job, why) then changed = true end end
	return changed
end

local function Withdrawal(key, answer)
	if answer.withdrawing then return false end
	-- Quiet presence: forgotten, not withdrawn; the requester's row expires on its own
	-- (RESULT_TTL) as after a logout.
	if Quiet() then
		if sent[key] == answer then
			sent[key], sentCount = nil, sentCount - 1
			if answer.mode == "area" then
				local remote = remotes[tostring(answer.requester):lower() .. ":" .. tostring(answer.id)]
				if remote then remote.sentCount = math.max(0, (remote.sentCount or 1) - 1) end
			end
		end
		return false
	end
	local C = GuardedComm()
	if not C then return false end
	answer.withdrawing = true
	local mode = answer.mode == "area" and "W" or "X"
	local msg = ("PS~%s~%d~%d~%s"):format(mode, Sightings.VERSION, answer.id, answer.target)
	local accepted = C.Whisper(answer.requester, msg, "psx:" .. key, true, false, function(sentOK)
		answer.withdrawing = nil
		if sentOK and sent[key] == answer then sent[key], sentCount = nil, sentCount - 1 end
	end, { owner = Sightings })
	if not accepted then answer.withdrawing = nil end
	return accepted and true or false
end

local function WithdrawAll()
	local changed = false
	for key, answer in pairs(sent) do
		answer.revoked, changed = true, true
		Withdrawal(key, answer)
	end
	return changed
end

local function ClearObserverState(why)
	local changed = CancelQueuedFor(nil, why)
	if WithdrawAll() then changed = true end
	if remoteCount > 0 then remotes, remoteCount, changed = {}, 0, true end
	if ClearRecent() then changed = true end
	return changed
end

function Sightings.SetSharing(on, silent)
	if type(ns.db) ~= "table" then return false, "state" end
	on = on == true
	ns.db.playerSightings = on
	ns.db.playerSightingsConsentVersion = Sightings.CONSENT_VERSION
	if not on then ClearObserverState("consent") end
	if not silent and ns.Print then ns.Print(on and ns.L.PLAYER_SIGHTINGS_ON or ns.L.PLAYER_SIGHTINGS_OFF) end
	Changed(nil, "sharing")
	return true
end

local function QueryPermit(request)
	if requests[request.id] ~= request or request.phase ~= "sending" then return false, "cancelled" end
	if Now() - request.queuedAt > Sightings.QUEUE_TTL then return false, "stale" end
	local ok, why = Sightings.CanRequest()
	if not ok then return false, why end
	local C = ns.Comm
	if not C.ChannelName or C.ChannelName() ~= request.channel then return false, "moved" end
	if request.mode == "area" then
		if not OpenMap(request.mapID) then return false, "map" end
	elseif Canonical(request.target) ~= request.target then
		return false, "target"
	end
	return true
end

local function SendCancel(request)
	local C = GuardedComm()
	if not C or not request.sentAt then return false end
	local mode, value = request.mode == "area" and "D" or "C",
		request.mode == "area" and request.mapID or request.target
	local msg = ("PS~%s~%d~%d~%s"):format(mode, Sightings.VERSION, request.id, tostring(value))
	return C.Send("CHANNEL", msg, "psc:" .. request.id, true, false, nil, { owner = Sightings }) and true or false
end

local function RemoveRequest(request, action, tell)
	if requests[request.id] ~= request then return false end
	requests[request.id], requestCount = nil, requestCount - 1
	if request.phase == "sending" or request.phase == "waiting" then activeCount = activeCount - 1 end
	if request.job then DropQueued(request.job, action or "cancelled") end
	if tell then SendCancel(request) end
	Changed(request.id, action or "cancelled")
	return true
end

-- The wider area scope follows the area query on the same channel once that query has gone: an
-- observer that never received the A has no request to widen, and one that cannot read S keeps
-- answering hostile rows. A failed S leaves the request hostile, so its snapshot stays honest.
local function SendScope(request)
	local C = GuardedComm()
	if not C or request.scope ~= "outsiders" then return false end
	local msg = ("PS~S~%d~%d~%d~%s"):format(Sightings.VERSION, request.id, request.mapID, request.scope)
	local key = "pss:" .. request.id
	local function Narrow(why)
		if requests[request.id] ~= request or request.scope ~= "outsiders" then return end
		request.scope = "hostile"
		Changed(request.id, why or "scope")
	end
	local accepted = C.Send("CHANNEL", msg, nil, true, false, function(sentOK)
		if not sentOK then Narrow("scope") end
	end, { owner = Sightings, key = key, permit = function(owner, permitKey, dist, recipient, permitMsg)
		if owner ~= Sightings or permitKey ~= key or dist ~= "CHANNEL" or recipient ~= nil or permitMsg ~= msg then
			return false, "target"
		end
		if requests[request.id] ~= request or request.phase ~= "waiting" then return false, "cancelled" end
		local ok, why = Sightings.CanRequest()
		if not ok then return false, why end
		if not C.ChannelName or C.ChannelName() ~= request.channel then return false, "moved" end
		return true
	end })
	if not accepted then Narrow("scope") end
	return accepted and true or false
end

local function StartRequest(mode, value, scope)
	local target, mapID
	if mode == "area" then
		mapID = Whole(value, 1, 9999999)
		if not mapID or not OpenMap(mapID) then return false, "map" end
		if Secret(scope) then return false, "scope" end
		if scope == nil then scope = "hostile" end
		if type(scope) ~= "string" or not Sightings.AREA_SCOPES[scope] then return false, "scope" end
	else
		target = Canonical(value)
		if not target or Same(target, ns.me) then return false, "target" end
		mode = "player"
	end
	local allowed, why = Sightings.CanRequest()
	if not allowed then return false, why end
	Sightings.Tick()
	if activeCount >= Sightings.MAX_ACTIVE or requestCount >= Sightings.MAX_SESSIONS then return false, "capacity" end
	local now = Now()
	sequence = sequence % 99999 + 1
	while requests[sequence] do sequence = sequence % 99999 + 1 end
	local C = GuardedComm()
	local request = { id = sequence, mode = mode, target = target, mapID = mapID,
		scope = mode == "area" and scope or nil, phase = "sending", createdAt = now,
		queuedAt = now, expiresAt = now + Sightings.QUEUE_TTL, channel = C.ChannelName(), results = {} }
	local msg = mode == "area" and ("PS~A~%d~%d~%d"):format(Sightings.VERSION, request.id, mapID)
		or ("PS~Q~%d~%d~%s"):format(Sightings.VERSION, request.id, target)
	local key = "psq:" .. request.id
	local job = { key = key, request = request, msg = msg }
	request.job = job
	requests[request.id], requestCount, activeCount = request, requestCount + 1, activeCount + 1
	local accepted = C.Send("CHANNEL", msg, nil, true, false, function(sentOK, sendWhy)
		if requests[request.id] ~= request or request.phase ~= "sending" then return end
		request.job = nil
		if not sentOK then
			return RemoveRequest(request, sendWhy or "send", false)
		end
		request.phase, request.sentAt, request.expiresAt = "waiting", Now(),
			Now() + (request.mode == "area" and Sightings.AREA_REQUEST_TTL or Sightings.REQUEST_TTL)
		if request.mode == "area" and request.scope == "outsiders" then SendScope(request) end
		Changed(request.id, "sent")
	end, { owner = Sightings, key = key, permit = function(owner, permitKey, dist, recipient, permitMsg)
		if owner ~= Sightings or permitKey ~= key or dist ~= "CHANNEL" or recipient ~= nil or permitMsg ~= msg then
			return false, "target"
		end
		return QueryPermit(request)
	end })
	if not accepted and requests[request.id] == request then RemoveRequest(request, "queue", false) end
	if accepted then Changed(request.id, "started") end
	if accepted and mode == "area" and requests[request.id] == request and Sightings.SeedOwnArea then
		Sightings.SeedOwnArea(request)
	end
	return accepted and true or false, accepted and request.id or "queue"
end

function Sightings.Start(target) return StartRequest("player", target) end
function Sightings.StartArea(mapID, scope) return StartRequest("area", mapID, scope) end

function Sightings.Cancel(id)
	id = Whole(id, 1, 99999)
	local request = id and requests[id]
	if not request then return false, "not-found" end
	RemoveRequest(request, "cancelled", request.phase == "waiting")
	return true
end

function Sightings.CancelArea(id)
	id = Whole(id, 1, 99999)
	local request = id and requests[id]
	if not request or request.mode ~= "area" then return false, "not-found" end
	RemoveRequest(request, "cancelled", request.phase == "waiting")
	return true
end

function Sightings.Status(id)
	if not ns.SharedToolsHere() then return nil, "federation" end
	Sightings.Tick()
	id = Whole(id, 1, 99999)
	local request = id and requests[id]
	return request and Snapshot(request) or nil, request and nil or "not-found"
end

-- API-facing aggregate. Status/Requests/Results remain the smaller internal contract; Session
-- merely joins the already-normalized copies so consumers never see the live request tables.
function Sightings.Session(id)
	if not ns.SharedToolsHere() then return nil, "federation" end
	Sightings.Tick()
	id = Whole(id, 1, 99999)
	local request = id and requests[id]
	if not request then return nil, "not-found" end
	local out = Snapshot(request)
	out.results, out.sightings = {}, {}
	for _, result in pairs(request.results) do out.results[#out.results + 1] = ResultCopy(result) end
	table.sort(out.results, function(a, b)
		if a.receivedAt ~= b.receivedAt then return a.receivedAt > b.receivedAt end
		return a.observer < b.observer
	end)
	for i, result in ipairs(out.results) do out.sightings[i] = result end
	return out
end

function Sightings.AreaSession(id)
	if not ns.SharedToolsHere() then return nil, "federation" end
	Sightings.Tick()
	id = Whole(id, 1, 99999)
	local request = id and requests[id]
	if not request or request.mode ~= "area" then return nil, "not-found" end
	local out, chosen = Snapshot(request), {}
	for _, result in pairs(request.results) do
		local key = result.target:lower()
		local previous = chosen[key]
		-- A full tie (same time and precision) goes to this client's own row: a network row's time
		-- is already rounded down by its serialized age, and pairs' order must not decide.
		local tie = previous and previous.seenAt == result.seenAt
			and (RESPONSE_QUALITY[previous.kind] or 0) == (RESPONSE_QUALITY[result.kind] or 0)
		if not previous or PreferResponse(previous, result.seenAt, result.kind) or (tie and result.own == true) then
			chosen[key] = result
		end
	end
	out.results, out.sightings = {}, {}
	for _, result in pairs(chosen) do out.results[#out.results + 1] = AreaResultCopy(result) end
	table.sort(out.results, function(a, b)
		if a.seenAt ~= b.seenAt then return a.seenAt > b.seenAt end
		return a.target < b.target
	end)
	for i, result in ipairs(out.results) do out.sightings[i] = result end
	return out
end

function Sightings.Requests()
	if not ns.SharedToolsHere() then return {} end
	Sightings.Tick()
	local out = {}
	for _, request in pairs(requests) do out[#out + 1] = Snapshot(request) end
	table.sort(out, function(a, b) if a.createdAt ~= b.createdAt then return a.createdAt > b.createdAt end return a.id < b.id end)
	return out
end

function Sightings.Results(id)
	if not ns.SharedToolsHere() then return {} end
	Sightings.Tick()
	id = Whole(id, 1, 99999)
	local request, out = id and requests[id], {}
	if not request then return out end
	for _, result in pairs(request.results) do out[#out + 1] = ResultCopy(result) end
	table.sort(out, function(a, b)
		if a.receivedAt ~= b.receivedAt then return a.receivedAt > b.receivedAt end
		return a.reporter < b.reporter
	end)
	return out
end

local function RemoteKey(requester, id) return requester:lower() .. ":" .. id end

local function ResponsePermit(job)
	if queued[job.slot] ~= job or job.cancelled then return false, "cancelled" end
	if remotes[job.remoteKey] ~= job.remote then return false, "cancelled" end
	local now = Now()
	if now - job.queuedAt > Sightings.QUEUE_TTL or now >= job.remote.expiresAt then return false, "stale" end
	local ok, why = ObserverEligible()
	if not ok then return false, why end
	local requester = SignedRequester(job.remote.requester)
	if not requester or not Same(requester, job.requester) then return false, "authority" end
	if job.cached then
		local record = job.cached
		if recent[job.target:lower()] ~= record or record.epoch ~= recentEpoch
			or now - record.at < 0 or now - record.at > Sightings.RECENT_TTL
			or not Same(record.target, job.target) or record.mapID ~= job.mapID or record.x ~= job.x
			or record.y ~= job.y or record.layer ~= job.layer or record.kind ~= job.kind
			or record.accuracyYards ~= job.accuracyYards
			or (job.remote.mode == "area" and (not AreaTakes(job.remote, record.hostile, record.outsider)
				or record.mapID ~= job.remote.mapID or (record.hostile == true) ~= job.hostile)) then
			return false, "stale"
		end
		return true
	end
	-- The send queue is asynchronous. A changed target/mouseover/nameplate must never inherit an
	-- observation made for its predecessor, even when the observer has not moved.
	if not UnitIdentity(job.unit, job.target, job.guid) then return false, "target" end
	-- A not-hostile area row is checked again as it leaves: still outside Olympus guilds and the group.
	if job.remote.mode == "area" and job.hostile == false and not Outsider(job.unit, job.guid) then return false, "target" end
	local mapID, x, y, layer
	if job.kind == "exact-unit" then
		mapID, x, y = MapSpot(job.unit)
		layer = mapID and LayerFor(mapID) or nil
	elseif job.kind == "exact-group" then
		if not UnitIdentity(job.groupUnit, job.target, job.guid) then return false, "target" end
		if type(UnitIsUnit) == "function" and Ask(UnitIsUnit, job.unit, job.groupUnit) ~= true then return false, "target" end
		mapID, x, y = MapSpot(job.groupUnit)
		layer = mapID and LayerFor(mapID) or nil
	else
		mapID, x, y, layer = Spot()
	end
	if mapID ~= job.mapID or x ~= job.x or y ~= job.y or layer ~= job.layer then return false, "moved" end
	return true
end

local function QueueResponse(remote, target, unit, guid, mapID, x, y, layer, kind, accuracyYards, groupUnit, seenAt, cached, hostile)
	local C = GuardedComm()
	if not C then return false, "transport" end
	local guild = OwnGuild()
	if not guild then return false, "guild" end
	local remoteKey = RemoteKey(remote.requester, remote.id)
	local area = remote.mode == "area"
	hostile = hostile ~= false
	if area and not hostile and remote.scope ~= "outsiders" then return false, "scope" end
	target = area and Canonical(target) or remote.target
	if not target then return false, "target" end
	if area and mapID ~= remote.mapID then return false, "map" end
	local sentKey = area and (remoteKey .. ":" .. target:lower()) or remoteKey
	local slot = (area and "psb:" or "psr:") .. sentKey
	local now = Now()
	seenAt = tonumber(seenAt) or now
	local previous = queued[slot]
	if sent[sentKey] or previous and not PreferResponse(previous, seenAt, kind) then return false, "replay" end
	-- Count both answers already sent and distinct rows waiting in Comm. A more precise replacement
	-- for an already queued target does not consume another slot, but a seventh target cannot wait
	-- behind the six-row observer cap and escape it later as callbacks drain the queue.
	if area and not previous
		and remote.sentCount + (remote.pendingCount or 0) >= Sightings.AREA_MAX_PER_OBSERVER then
		return false, "capacity"
	end
	if not previous and (queuedCount >= Sightings.MAX_QUEUED or sentCount >= Sightings.MAX_SENT) then return false, "capacity" end
	local age = math.ceil(math.max(0, now - seenAt)) + Sightings.QUEUE_TTL
	if age > Sightings.RECENT_TTL then return false, "stale" end
	local msg = ("PS~%s~%d~%d~%s~%d~%d~%d~%d~%d~%s~%s"):format(area and "B" or "R", Sightings.VERSION,
		remote.id, guild, mapID, x, y, layer, age, target, kind)
	if accuracyYards ~= nil then msg = msg .. "~" .. tostring(accuracyYards) end
	if area and not hostile then msg = msg .. "~o" end
	if #msg > 255 then return false, "size" end
	-- Each candidate has a distinct transport capability. Keep the prior valid answer live until
	-- Comm accepts its replacement; an immediate transport refusal must not erase the only answer.
	responseSequence = responseSequence + 1
	local key = slot .. ":" .. responseSequence
	local job = { key = key, slot = slot, sentKey = sentKey, remoteKey = remoteKey, remote = remote, requester = remote.requester,
		queuedAt = now, unit = unit, target = target, guid = guid, groupUnit = groupUnit, cached = cached,
		mapID = mapID, x = x, y = y, layer = layer, kind = kind, accuracyYards = accuracyYards,
		seenAt = seenAt, msg = msg, hostile = hostile }
	local accepted = C.Whisper(remote.requester, msg, nil, true, false, function(sentOK)
		if queued[slot] == job then
			queued[slot], queuedCount = nil, queuedCount - 1
			if area then remote.pendingCount = math.max(0, (remote.pendingCount or 1) - 1) end
		end
		if sentOK and sent[sentKey] == nil then
			-- The requester reconstructs seenAt as receive time minus the conservative serialized
			-- age, then expires the row at seenAt + RESULT_TTL. Use that same absolute lifetime for
			-- observer bookkeeping; an old cached row must not occupy MAX_SENT for another full TTL.
			local expiresAt = Now() - age + Sightings.RESULT_TTL
			if expiresAt > Now() then
				sent[sentKey], sentCount = { requester = remote.requester, id = remote.id, mode = remote.mode,
					target = target, expiresAt = expiresAt }, sentCount + 1
				if area then remote.sentCount = remote.sentCount + 1 end
			end
		end
	end, { owner = Sightings, key = key, permit = function(owner, permitKey, dist, recipient, permitMsg)
		if owner ~= Sightings or permitKey ~= key or dist ~= "WHISPER" or recipient ~= remote.requester
			or permitMsg ~= msg then return false, "target" end
		return ResponsePermit(job)
	end })
	if accepted then
		queued[slot] = job
		if previous then
			DropQueued(previous, "replaced")
		else
			queuedCount = queuedCount + 1
			if area then remote.pendingCount = (remote.pendingCount or 0) + 1 end
		end
	end
	return accepted and true or false, accepted and "ok" or "queue"
end

local function QueueRecent(remote)
	local now = Now()
	PruneRecent(now)
	local record = recent[remote.target:lower()]
	if not record then return false, "not-found" end
	return QueueResponse(remote, remote.target, nil, nil, record.mapID, record.x, record.y, record.layer,
		record.kind, record.accuracyYards, nil, record.at, record)
end

local function QueueAreaRecent(remote)
	local now, rows = Now(), {}
	PruneRecent(now)
	for _, record in pairs(recent) do
		if AreaTakes(remote, record.hostile, record.outsider) and record.mapID == remote.mapID then rows[#rows + 1] = record end
	end
	table.sort(rows, function(a, b) if a.at ~= b.at then return a.at > b.at end return a.target < b.target end)
	local queuedAny = false
	for i = 1, math.min(#rows, Sightings.AREA_MAX_PER_OBSERVER) do
		local record = rows[i]
		local ok = QueueResponse(remote, record.target, nil, nil, record.mapID, record.x, record.y, record.layer,
			record.kind, record.accuracyYards, nil, record.at, record, record.hostile == true)
		if ok then queuedAny = true end
	end
	return queuedAny
end

local function AllowedUnit(unit)
	return unit == "target" or unit == "mouseover" or type(unit) == "string" and unit:match("^nameplate%d+$") ~= nil
end

local function HostileUnit(unit)
	if type(UnitCanAttack) == "function" and Ask(UnitCanAttack, "player", unit) == true then return true end
	return type(UnitIsEnemy) == "function" and Ask(UnitIsEnemy, "player", unit) == true
end

-- This client's own live area requests. What the requester's own game shows it belongs in its own
-- session at once, with no other member and no network round trip: nothing about it leaves this
-- client, so it needs neither the sharing consent nor location sharing (the request itself already
-- needed the signed authority, CanRequest).
local function OwnAreaRequests()
	local list = {}
	for _, request in pairs(requests) do
		if request.mode == "area" and (request.phase == "sending" or request.phase == "waiting") then
			list[#list + 1] = request
		end
	end
	return list
end

-- One row per target for this client's own observation, under a key no reporter can have (a
-- reporter key starts with its canonical name). It obeys the same map, scope and target cap as a
-- network row; the newest of the two wins in AreaSession, as between two reporters.
local function AddOwnAreaRow(request, target, mapID, x, y, layer, kind, accuracyYards, hostile, outsider, seenAt)
	if request.mapID ~= mapID or not AreaTakes(request, hostile, outsider) then return false end
	local key = "\0own\0" .. target:lower()
	if not request.results[key] then
		local targets, count, known = {}, 0, false
		for _, result in pairs(request.results) do
			local resultTarget = type(result.target) == "string" and result.target:lower() or ""
			if resultTarget == target:lower() then known = true end
			if resultTarget ~= "" and not targets[resultTarget] then targets[resultTarget], count = true, count + 1 end
		end
		if not known and count >= Sightings.AREA_MAX_RESULTS then return false end
	elseif (request.results[key].seenAt or 0) > seenAt then
		return false
	end
	request.results[key] = { requestId = request.id, target = target, reporter = ns.me, own = true,
		mapID = mapID, x = x, y = y, layer = layer or 0, seenAt = seenAt, receivedAt = seenAt,
		expiresAt = seenAt + Sightings.RESULT_TTL, kind = kind or "nearby", accuracyYards = accuracyYards,
		hostile = hostile == true }
	Changed(request.id, "result")
	return true
end

-- ownOnly: only this client's own area requests take the observation (the scan when one starts);
-- no remote is answered and nothing is remembered.
local function Observe(unit, remember, ownOnly)
	local eligible, why = ObserverEligible()
	local own = OwnAreaRequests()
	if ownOnly then eligible, why = false, "own" end
	if not eligible and #own == 0 then return false, why end
	if not AllowedUnit(unit) then return false, "unit" end
	local exists, player = Ask(UnitExists, unit), Ask(UnitIsPlayer, unit)
	local guid = Ask(UnitGUID, unit)
	if exists ~= true or player ~= true or not VisibleUnit(unit)
		or type(guid) ~= "string" or not guid:match("^Player%-") then return false, "player" end
	local name = Ask(ns.UnitFullName, unit)
	name = Canonical(name)
	if not name or Same(name, ns.me) then return false, "identity" end
	local mapID, x, y, layer
	local kind, accuracyYards, groupUnit
	local directMap, directX, directY = MapSpot(unit)
	local exactUnit, exactMap, exactX, exactY
	if directMap then
		mapID, x, y, kind, accuracyYards = directMap, directX, directY, "exact-unit", 0
	else
		exactUnit, exactMap, exactX, exactY = ExactGroupSpot(unit, name, guid)
	end
	if not directMap and exactUnit then
		groupUnit, mapID, x, y, kind, accuracyYards = exactUnit, exactMap, exactX, exactY, "exact-group", 0
		layer = LayerFor(mapID)
	elseif directMap then
		layer = LayerFor(mapID)
	else
		mapID, x, y, layer = Spot()
		kind, accuracyYards = "nearby", nil
	end
	if not mapID then return false, "position" end
	local now, matched, queuedAny = Now(), false, false
	local hostile = HostileUnit(unit)
	local outsider = not hostile and Outsider(unit, guid)
	local ownAdded = false
	for _, request in ipairs(own) do
		if AddOwnAreaRow(request, name, mapID, x, y, layer, kind, accuracyYards, hostile, outsider, now) then ownAdded = true end
	end
	local point = { target = name, mapID = mapID, x = x, y = y, layer = layer, kind = kind, accuracyYards = accuracyYards }
	if not eligible then
		if ownAdded then return true, point end
		return false, #own > 0 and "unrequested" or why
	end
	if remember ~= false then Remember(name, mapID, x, y, layer, kind, accuracyYards, hostile, outsider, now) end
	local list = {}
	for _, remote in pairs(remotes) do list[#list + 1] = remote end
	for _, remote in ipairs(list) do
		if remotes[RemoteKey(remote.requester, remote.id)] == remote and now < remote.expiresAt
			and ((remote.mode == "area" and AreaTakes(remote, hostile, outsider) and mapID == remote.mapID)
				or (remote.mode ~= "area" and Same(name, remote.target))) then
			matched = true
			local ok = QueueResponse(remote, name, unit, guid, mapID, x, y, layer, kind, accuracyYards, groupUnit, now, nil, hostile)
			if ok then queuedAny = true end
		end
	end
	if not matched then
		if ownAdded then return true, point end
		return false, "unrequested"
	end
	return queuedAny, queuedAny and point or "replay"
end

function Sightings.ObserveUnit(unit, remember) return Observe(unit, remember, false) end

-- A new own area request starts with what this client already knows of that map: its bounded
-- recent memory (kept only while it shares) and every player its game shows it right now.
local function SeedOwnArea(request)
	local now = Now()
	PruneRecent(now)
	for _, record in pairs(recent) do
		AddOwnAreaRow(request, record.target, record.mapID, record.x, record.y, record.layer, record.kind,
			record.accuracyYards, record.hostile, record.outsider, record.at)
	end
	Observe("target", false, true)
	Observe("mouseover", false, true)
	for i = 1, 40 do
		local token = "nameplate" .. i
		if Ask(UnitExists, token) == true then Observe(token, false, true) end
	end
end
Sightings.SeedOwnArea = SeedOwnArea

local function ReceiveQuery(sender, text)
	local version, id, target = text:match("^PS~Q~(%d+)~(%d+)~([^~]+)$")
	version, id, target = Whole(version, 1, 9), Whole(id, 1, 99999), Canonical(target)
	if version ~= Sightings.VERSION or not id or not target then return false, "shape" end
	local eligible, why = ObserverEligible()
	if not eligible then return false, why end
	local requester = SignedRequester(sender)
	if not requester or Same(requester, ns.me) then return false, "authority" end
	local now = Now()
	PruneBounded(now)
	local wire = RemoteKey(requester, id) .. ":" .. target:lower()
	if seenQueries[wire] then return false, "replay" end
	local rate
	rate, queryRateCount = SenderRate(queryRates, queryRateCount, requester:lower(), now, Sightings.QUERY_PER_SENDER)
	if not rate or not Bucket(queryGlobal, now, Sightings.QUERY_GLOBAL) then return false, "rate" end
	local key = RemoteKey(requester, id)
	if remotes[key] then return false, "replay" end
	if remoteCount >= Sightings.MAX_REMOTE then return false, "capacity" end
	local added
	added, seenQueryCount = ReplayAdd(seenQueries, seenQueryCount, wire, now)
	if not added then return false, "replay" end
	local remote = { requester = requester, id = id, mode = "player", target = target, sentCount = 0, pendingCount = 0, receivedAt = now,
		expiresAt = now + Sightings.REQUEST_TTL }
	remotes[key], remoteCount = remote, remoteCount + 1
	-- Target and mouseover may already be visible at the instant the request arrives. Both are
	-- native unit observations; inaccessible units and guessed names remain impossible.
	Sightings.ObserveUnit("target", false)
	Sightings.ObserveUnit("mouseover", false)
	QueueRecent(remote)
	return true, "ok"
end

local function ReceiveAreaQuery(sender, text)
	local version, id, mapID = text:match("^PS~A~(%d+)~(%d+)~(%d+)$")
	version, id, mapID = Whole(version, 1, 9), Whole(id, 1, 99999), Whole(mapID, 1, 9999999)
	if version ~= Sightings.VERSION or not id or not mapID or not OpenMap(mapID) then return false, "shape" end
	local eligible, why = ObserverEligible()
	if not eligible then return false, why end
	local requester = SignedRequester(sender)
	if not requester or Same(requester, ns.me) then return false, "authority" end
	local now = Now()
	PruneBounded(now)
	local wire = RemoteKey(requester, id) .. ":area:" .. mapID
	if seenQueries[wire] then return false, "replay" end
	local rate
	rate, queryRateCount = SenderRate(queryRates, queryRateCount, requester:lower(), now, Sightings.QUERY_PER_SENDER)
	if not rate or not Bucket(queryGlobal, now, Sightings.QUERY_GLOBAL) then return false, "rate" end
	local key = RemoteKey(requester, id)
	if remotes[key] then return false, "replay" end
	if remoteCount >= Sightings.MAX_REMOTE then return false, "capacity" end
	local added
	added, seenQueryCount = ReplayAdd(seenQueries, seenQueryCount, wire, now)
	if not added then return false, "replay" end
	local remote = { requester = requester, id = id, mode = "area", mapID = mapID, sentCount = 0, pendingCount = 0,
		receivedAt = now, expiresAt = now + Sightings.AREA_REQUEST_TTL }
	remotes[key], remoteCount = remote, remoteCount + 1
	Sightings.ObserveUnit("target", false)
	Sightings.ObserveUnit("mouseover", false)
	QueueAreaRecent(remote)
	return true, "ok"
end

-- The requester widened its own live area request (SendScope). Only the same signed requester,
-- request and map, once; the observer then answers again from what it sees and remembers, within
-- the same six-row cap.
local function ReceiveAreaScope(sender, text)
	local version, id, mapID, scope = text:match("^PS~S~(%d+)~(%d+)~(%d+)~(%a+)$")
	version, id, mapID = Whole(version, 1, 9), Whole(id, 1, 99999), Whole(mapID, 1, 9999999)
	if version ~= Sightings.VERSION or not id or not mapID or scope ~= "outsiders" then return false, "shape" end
	local eligible, why = ObserverEligible()
	if not eligible then return false, why end
	local requester = SignedRequester(sender)
	if not requester or Same(requester, ns.me) then return false, "authority" end
	local remote = remotes[RemoteKey(requester, id)]
	if not remote or remote.mode ~= "area" or remote.mapID ~= mapID then return false, "not-found" end
	if remote.scope == scope then return false, "replay" end
	if Now() >= remote.expiresAt then return false, "stale" end
	remote.scope = scope
	Sightings.ObserveUnit("target", false)
	Sightings.ObserveUnit("mouseover", false)
	QueueAreaRecent(remote)
	return true, "ok"
end

local function RemoveRemote(remote, why)
	local key = RemoteKey(remote.requester, remote.id)
	if remotes[key] ~= remote then return false end
	remotes[key], remoteCount = nil, remoteCount - 1
	CancelQueuedFor(remote, why or "cancelled")
	return true
end

-- Once the server-stamped requester cancels, it has discarded this session and no withdrawal can
-- still be useful. Release the observer-global sent slots for exactly that requester/id instead of
-- letting cancelled rotations occupy MAX_SENT for the full result TTL. Natural expiry keeps them,
-- because a completed requester session can still hold those rows and needs a later opt-out W/X.
local function ForgetCancelledSent(remote)
	local removed = 0
	for key, answer in pairs(sent) do
		if answer.id == remote.id and Same(answer.requester, remote.requester) then
			sent[key], sentCount, removed = nil, sentCount - 1, removed + 1
		end
	end
	return removed
end

local function ReceiveCancel(sender, text)
	local version, id, target = text:match("^PS~C~(%d+)~(%d+)~([^~]+)$")
	version, id, target = Whole(version, 1, 9), Whole(id, 1, 99999), Canonical(target)
	local requester = Canonical(sender)
	if version ~= Sightings.VERSION or not id or not target or not requester then return false, "shape" end
	local remote = remotes[RemoteKey(requester, id)]
	if not remote or not Same(remote.target, target) then return false, "not-found" end
	RemoveRemote(remote, "cancelled")
	ForgetCancelledSent(remote)
	return true, "ok"
end

local function ReceiveAreaCancel(sender, text)
	local version, id, mapID = text:match("^PS~D~(%d+)~(%d+)~(%d+)$")
	version, id, mapID = Whole(version, 1, 9), Whole(id, 1, 99999), Whole(mapID, 1, 9999999)
	local requester = Canonical(sender)
	if version ~= Sightings.VERSION or not id or not mapID or not requester then return false, "shape" end
	local remote = remotes[RemoteKey(requester, id)]
	if not remote or remote.mode ~= "area" or remote.mapID ~= mapID then return false, "not-found" end
	RemoveRemote(remote, "cancelled")
	ForgetCancelledSent(remote)
	return true, "ok"
end

local function ReceiveResult(sender, text)
	local version, id, guild, mapID, x, y, layer, age, target, suffix =
		text:match("^PS~R~(%d+)~(%d+)~([^~]+)~(%d+)~(%d+)~(%d+)~(%d+)~(%d+)~([^~]+)(.*)$")
	if type(suffix) ~= "string" then return false, "shape" end
	version, id = Whole(version, 1, 9), Whole(id, 1, 99999)
	mapID, x, y = Whole(mapID, 1, 9999999), Whole(x, 0, 1000), Whole(y, 0, 1000)
	layer, age, target = Whole(layer, 0, 2147483647), Whole(age, 0, Sightings.RECENT_TTL), Canonical(target)
	local kind, accuracyYards = "nearby", nil
	if suffix ~= "" then
		local rawKind, rawAccuracy = suffix:match("^~([%a%-]+)~(%d+)$")
		if not rawKind then rawKind = suffix:match("^~([%a%-]+)$") end
		kind, accuracyYards = rawKind, rawAccuracy and Whole(rawAccuracy, 0, 100000) or nil
	end
	if version ~= Sightings.VERSION or not id or not Guild(guild) or not mapID or not x or not y or not layer
		or not age or not target or x % Sightings.GRID ~= 0 or y % Sightings.GRID ~= 0 or not OpenMap(mapID)
		or (kind ~= "nearby" and kind ~= "exact-group" and kind ~= "exact-unit")
		or ((kind == "exact-group" or kind == "exact-unit") and accuracyYards ~= 0)
		or (kind == "nearby" and accuracyYards ~= nil and accuracyYards < 1) then
		return false, "shape"
	end
	local request = requests[id]
	if not request or request.phase ~= "waiting" or not Same(request.target, target) then return false, "request" end
	local now = Now()
	PruneBounded(now)
	if now >= request.expiresAt or InInstance() or NetOff() or not SignedRequester(ns.me) then return false, "stale" end
	local reporter = Canonical(sender)
	local replay = reporter and (reporter:lower() .. ":" .. id .. ":" .. target:lower())
	if not replay then return false, "sender" end
	if seenResults[replay] then return false, "replay" end
	local rate
	rate, resultRateCount = SenderRate(resultRates, resultRateCount, reporter:lower(), now, Sightings.RESULT_PER_SENDER)
	if not rate then return false, "rate" end
	reporter, guild = VerifiedObserver(reporter, guild, now)
	if not reporter then return false, "unverified" end
	if not Bucket(resultGlobal, now, Sightings.RESULT_GLOBAL) then return false, "rate" end
	local n = 0
	for _ in pairs(request.results) do n = n + 1 end
	if n >= Sightings.MAX_RESULTS then return false, "capacity" end
	local added
	added, seenResultCount = ReplayAdd(seenResults, seenResultCount, replay, now)
	if not added then return false, "replay" end
	local seenAt = now - age
	request.results[reporter:lower()] = { requestId = id, target = request.target, reporter = reporter,
		observerGuild = guild,
		mapID = mapID, x = x, y = y, layer = layer, seenAt = seenAt, receivedAt = now,
		expiresAt = seenAt + Sightings.RESULT_TTL, kind = kind, accuracyYards = accuracyYards }
	Changed(id, "result")
	return true, "ok"
end

local function ReceiveAreaResult(sender, text)
	local version, id, guild, mapID, x, y, layer, age, target, suffix =
		text:match("^PS~B~(%d+)~(%d+)~([^~]+)~(%d+)~(%d+)~(%d+)~(%d+)~(%d+)~([^~]+)(.*)$")
	if type(suffix) ~= "string" then return false, "shape" end
	-- A not-hostile row of the wider scope ends in "~o", after its kind (and yards).
	local hostile = true
	if suffix:sub(-2) == "~o" then
		suffix, hostile = suffix:sub(1, -3), false
		if suffix == "" then return false, "shape" end
	end
	version, id = Whole(version, 1, 9), Whole(id, 1, 99999)
	mapID, x, y = Whole(mapID, 1, 9999999), Whole(x, 0, 1000), Whole(y, 0, 1000)
	layer, age, target = Whole(layer, 0, 2147483647), Whole(age, 0, Sightings.RECENT_TTL), Canonical(target)
	local kind, accuracyYards = "nearby", nil
	if suffix ~= "" then
		local rawKind, rawAccuracy = suffix:match("^~([%a%-]+)~(%d+)$")
		if not rawKind then rawKind = suffix:match("^~([%a%-]+)$") end
		kind, accuracyYards = rawKind, rawAccuracy and Whole(rawAccuracy, 0, 100000) or nil
	end
	if version ~= Sightings.VERSION or not id or not Guild(guild) or not mapID or not x or not y or not layer
		or not age or not target or x % Sightings.GRID ~= 0 or y % Sightings.GRID ~= 0 or not OpenMap(mapID)
		or (kind ~= "nearby" and kind ~= "exact-group" and kind ~= "exact-unit")
		or ((kind == "exact-group" or kind == "exact-unit") and accuracyYards ~= 0)
		or (kind == "nearby" and accuracyYards ~= nil and accuracyYards < 1) then
		return false, "shape"
	end
	local request = requests[id]
	if not request or request.mode ~= "area" or request.phase ~= "waiting" or request.mapID ~= mapID then
		return false, "request"
	end
	if not hostile and request.scope ~= "outsiders" then return false, "scope" end
	local now = Now()
	PruneBounded(now)
	if now >= request.expiresAt or InInstance() or NetOff() or not SignedRequester(ns.me) then return false, "stale" end
	local reporter = Canonical(sender)
	local replay = reporter and (reporter:lower() .. ":" .. id .. ":area:" .. target:lower())
	if not replay then return false, "sender" end
	if seenResults[replay] then return false, "replay" end
	local rate
	rate, resultRateCount = SenderRate(resultRates, resultRateCount, reporter:lower(), now, Sightings.RESULT_PER_SENDER)
	if not rate then return false, "rate" end
	reporter, guild = VerifiedObserver(reporter, guild, now)
	if not reporter then return false, "unverified" end
	if not Bucket(resultGlobal, now, Sightings.RESULT_GLOBAL) then return false, "rate" end
	-- AREA_MAX_RESULTS is a public-target cap, not a reporter-row cap. A crowd seeing the same
	-- prominent target must not consume all 48 slots and starve every other target for the rest of
	-- the session. Keep only the two strongest corroborating rows for one target: the best visible
	-- result plus one fallback that can survive the best reporter's later W withdrawal.
	local targets, same = {}, {}
	for key, result in pairs(request.results) do
		local resultTarget = type(result.target) == "string" and result.target:lower() or ""
		if resultTarget ~= "" then targets[resultTarget] = true end
		if resultTarget == target:lower() then same[#same + 1] = { key = key, result = result } end
	end
	local targetCount = 0
	for _ in pairs(targets) do targetCount = targetCount + 1 end
	if #same == 0 and targetCount >= Sightings.AREA_MAX_RESULTS then return false, "capacity" end
	local replace
	if #same >= AREA_CORROBORATION then
		local worst = same[1]
		for i = 2, #same do
			local row = same[i]
			if PreferResponse(row.result, worst.result.seenAt, worst.result.kind) then worst = row end
		end
		local candidateSeenAt = now - age
		if not PreferResponse(worst.result, candidateSeenAt, kind) then return false, "capacity" end
		replace = worst.key
	end
	local added
	added, seenResultCount = ReplayAdd(seenResults, seenResultCount, replay, now)
	if not added then return false, "replay" end
	local seenAt = now - age
	if replace then request.results[replace] = nil end
	request.results[reporter:lower() .. "\0" .. target:lower()] = { requestId = id, target = target,
		reporter = reporter, observerGuild = guild, mapID = mapID, x = x, y = y, layer = layer,
		seenAt = seenAt, receivedAt = now, expiresAt = seenAt + Sightings.RESULT_TTL,
		kind = kind, accuracyYards = accuracyYards, hostile = hostile }
	Changed(id, "result")
	return true, "ok"
end

local function ReceiveWithdrawal(sender, text)
	local version, id, target = text:match("^PS~X~(%d+)~(%d+)~([^~]+)$")
	version, id, target = Whole(version, 1, 9), Whole(id, 1, 99999), Canonical(target)
	local request, reporter = id and requests[id], Canonical(sender)
	if version ~= Sightings.VERSION or not request or not target or not reporter or not Same(request.target, target) then
		return false, "request"
	end
	local key = reporter:lower()
	if not request.results[key] then return false, "sender" end
	request.results[key] = nil
	Changed(id, "withdrawn")
	return true, "ok"
end

local function ReceiveAreaWithdrawal(sender, text)
	local version, id, target = text:match("^PS~W~(%d+)~(%d+)~([^~]+)$")
	version, id, target = Whole(version, 1, 9), Whole(id, 1, 99999), Canonical(target)
	local request, reporter = id and requests[id], Canonical(sender)
	if version ~= Sightings.VERSION or not request or request.mode ~= "area" or not target or not reporter then
		return false, "request"
	end
	local key = reporter:lower() .. "\0" .. target:lower()
	if not request.results[key] then return false, "sender" end
	request.results[key] = nil
	Changed(id, "withdrawn")
	return true, "ok"
end

function Sightings.Receive(dist, sender, text)
	if not ns.SharedToolsHere() then return false, "federation" end
	if Secret(dist, sender, text) or type(text) ~= "string" or type(sender) ~= "string" then return false, "secret" end
	local mode = text:match("^PS~([QCARXBDWS])~")
	if mode == "Q" or mode == "C" or mode == "A" or mode == "D" or mode == "S" then
		if dist ~= "CHANNEL" then return false, "lane" end
		if mode == "Q" then return ReceiveQuery(sender, text) end
		if mode == "C" then return ReceiveCancel(sender, text) end
		if mode == "A" then return ReceiveAreaQuery(sender, text) end
		if mode == "S" then return ReceiveAreaScope(sender, text) end
		return ReceiveAreaCancel(sender, text)
	elseif mode == "R" or mode == "X" or mode == "B" or mode == "W" then
		if dist ~= "WHISPER" then return false, "lane" end
		if mode == "R" then return ReceiveResult(sender, text) end
		if mode == "X" then return ReceiveWithdrawal(sender, text) end
		if mode == "B" then return ReceiveAreaResult(sender, text) end
		return ReceiveAreaWithdrawal(sender, text)
	end
	return false, "shape"
end

function Sightings.Tick()
	local now = Now()
	PruneBounded(now)
	PruneRecent(now)
	for key, answer in pairs(sent) do
		if type(answer.expiresAt) ~= "number" or now >= answer.expiresAt then
			sent[key], sentCount = nil, sentCount - 1
			if answer.mode == "area" then
				local remote = remotes[RemoteKey(answer.requester, answer.id)]
				if remote then remote.sentCount = math.max(0, (remote.sentCount or 1) - 1) end
			end
		elseif answer.revoked then
			Withdrawal(key, answer)
		end
	end
	local eligible = ObserverEligible()
	if not eligible and (remoteCount > 0 or queuedCount > 0 or sentCount > 0 or recentCount > 0) then ClearObserverState("private") end
	local expiredRemote = {}
	for _, remote in pairs(remotes) do if now >= remote.expiresAt then expiredRemote[#expiredRemote + 1] = remote end end
	for _, remote in ipairs(expiredRemote) do RemoveRemote(remote, "expired") end

	local list = {}
	for _, request in pairs(requests) do list[#list + 1] = request end
	for _, request in ipairs(list) do
		if requests[request.id] == request then
			local resultChanged = false
			for key, result in pairs(request.results) do
				if now >= result.expiresAt then request.results[key], resultChanged = nil, true end
			end
			if resultChanged then Changed(request.id, "results-expired") end
			if request.phase == "sending" and now - request.queuedAt > Sightings.QUEUE_TTL then
				RemoveRequest(request, "expired", false)
			elseif request.phase == "waiting" then
				local allowed = Sightings.CanRequest()
				if not allowed then
					RemoveRequest(request, "revoked", true)
				elseif now >= request.expiresAt then
					request.phase, request.expiresAt = "complete", now + Sightings.RESULT_KEEP
					activeCount = activeCount - 1
					Changed(request.id, "complete")
				end
			elseif request.phase == "complete" and now >= request.expiresAt then
				RemoveRequest(request, "expired", false)
			end
		end
	end
end

if ns.Consent and ns.Consent.Register then
	ns.Consent.Register({
		key = "playersightings", label = "PLAYER_SIGHTINGS_CONSENT", text = "PLAYER_SIGHTINGS_CONSENT_TEXT",
		shown = function() return ns.IsMember and ns.IsMember() == true end,
		get = function()
			if type(ns.db) ~= "table" or ns.db.playerSightingsConsentVersion ~= Sightings.CONSENT_VERSION then return nil end
			return ns.db.playerSightings
		end,
		set = function(on) Sightings.SetSharing(on) end,
		pending = function()
			return type(ns.db) ~= "table" or ns.db.playerSightingsConsentVersion ~= Sightings.CONSENT_VERSION
		end,
		-- This question did not exist in the older builds whose unanswered lines 1.2.3 can adopt as
		-- already shown. A direct upgrade must still open privacy for it once.
		explicit = true, adopt = false, version = Sightings.CONSENT_VERSION,
	})
end

ns.Comm.Handle("PS", function(...) return Sightings.Receive(...) end)
pcall(ns.RegisterEvent, "NAME_PLATE_UNIT_ADDED", function(unit) Sightings.ObserveUnit(unit) end)
pcall(ns.RegisterEvent, "PLAYER_TARGET_CHANGED", function() Sightings.ObserveUnit("target") end)
pcall(ns.RegisterEvent, "UPDATE_MOUSEOVER_UNIT", function() Sightings.ObserveUnit("mouseover") end)
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_GUILD_UPDATE", "CHANNEL_UI_UPDATE" }) do
	pcall(ns.RegisterEvent, event, function() Sightings.Tick() end)
end
ns.On("LAYER_SHARING_CHANGED", function() Sightings.Tick() end)
ns.On("NETOFF_CHANGED", function() Sightings.Tick() end)
ns.On("DATA_CHANGED", function() Sightings.Tick() end)
ns.On("LOGIN", function() ns.Every(1, "player sightings", Sightings.Tick) end)
