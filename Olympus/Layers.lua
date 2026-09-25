local ADDON, ns = ...
local L = ns.L

-- Layers have no name in game. Like other layer addons we read the zone UID embedded in
-- NPC GUIDs (Creature-0-server-instance-zoneUID-npc-spawn): players who see the same
-- zoneUID in the same zone share a layer. Each addon user announces its layer and rank on
-- OlympusNet, and a layer is named after the highest ranked Olympus member on it:
-- "Asmongold's layer". Experimental until tested on a live realm.

local Layers = {}
ns.Layers = Layers

local ANNOUNCE_EVERY = 600
local MIN_GAP = 30
local EXPIRE = 2 * ANNOUNCE_EVERY + 60 -- a missed announce does not drop anyone

local mine          -- { mapID, zoneUID, t }
local lastAnnounce = 0
local seen = {}     -- [mapID][zoneUID]["Name-Realm"] = { rank, guild, t }
local where = {}    -- ["Name-Realm"] = { mapID, zoneUID }: each sender counts on one layer only

local function ZoneUIDFromGUID(guid)
	if not guid then return nil end
	local unitType, _, _, _, zoneUID = strsplit("-", guid)
	if unitType ~= "Creature" and unitType ~= "Vehicle" then return nil end
	return tonumber(zoneUID)
end

-- The zone we are in. A continent or the world (on a boat, a zeppelin, a flight, between
-- zones) is no zone: no layer reading there.
local function CurrentMap()
	local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if mapID and C_Map.GetMapInfo then
		local info = C_Map.GetMapInfo(mapID)
		if info and info.mapType and info.mapType <= 2 then return nil end
	end
	return mapID
end

local retryQueued = false

local function Announce(force)
	if not mine or not IsInGuild() then return end
	local now = ns.Now()
	if not force and now - lastAnnounce < ANNOUNCE_EVERY then return end
	if now - lastAnnounce < MIN_GAP then
		-- A layer change too soon after the last one: announced once the gap is over, so
		-- nobody (the King's hop above all) is sent to a layer we already left.
		if force and not retryQueued then
			retryQueued = true
			ns.After(MIN_GAP - (now - lastAnnounce) + 1, "layer announce retry", function()
				retryQueued = false
				Announce(true)
			end)
		end
		return
	end
	lastAnnounce = now
	local guild = GetGuildInfo("player")
	if not ns.IsFederation(guild) then return end
	-- With thousands of users only officers and a stable 1 in 8 sample announce, which is
	-- enough to see the layers and to name each one after its highest rank.
	if not ns.Roster.IsOfficer() and not Layers.InSample() then return end
	ns.Comm.Send("CHANNEL", ns.Codec.EncodeLayer(mine.mapID, mine.zoneUID, ns.Roster.MyRank(), guild), "layer")
end

-- Our layer does not follow every creature: some show another server's zone UID (a zone's
-- border, creatures from another shard), and a layer that flips back and forth every second
-- would spam the channel and fool the layer hop. A new one takes over only once two different
-- creatures show it and none of ours has been seen for HOLD seconds; at once when we have none
-- or entered another zone, and when it is the layer a hop is taking us to.
Layers.HOLD = 6
local pending        -- another layer seen meanwhile: { zoneUID, guids = { [guid] = true }, n }
local function Observe(unit)
	if IsInInstance() then return end
	local guid = UnitGUID(unit)
	local zoneUID = ZoneUIDFromGUID(guid)
	local mapID = CurrentMap()
	if not zoneUID or not mapID then return end
	local now = ns.Now()
	if mine and mine.mapID == mapID and mine.zoneUID == zoneUID then
		mine.t, mine.seenAt, pending = now, now, nil
		return
	end
	if mine and mine.mapID == mapID then
		local expMap, expUID = ns.Hop and ns.Hop.ExpectedLayer and ns.Hop.ExpectedLayer()
		if not (expMap == mapID and expUID == zoneUID) then
			if not pending or pending.zoneUID ~= zoneUID then pending = { zoneUID = zoneUID, guids = {}, n = 0 } end
			if not pending.guids[guid] then pending.guids[guid], pending.n = true, pending.n + 1 end
			if pending.n < 2 or now - (mine.seenAt or 0) < Layers.HOLD then return end
		end
	end
	pending = nil
	mine = { mapID = mapID, zoneUID = zoneUID, t = now, seenAt = now }
	ns.Log("layer: map %d zoneUID %d (%s)", mapID, zoneUID, tostring(unit))
	Announce(true)
	ns.Fire("LAYERS_CHANGED")
end

function Layers.Mine() return mine end
Layers.Observe = Observe -- tests
function Layers.Reset() mine, pending = nil, nil; wipe(seen); wipe(where) end -- tests

-- Where a player last announced their layer: { mapID, zoneUID, t } while fresh, else nil.
-- The census and the channel may write a name with different realms: short names match too,
-- unless `exact` (the King's: nobody else's announcement may pass for his).
function Layers.Of(name, exact)
	if type(name) ~= "string" then return nil end
	if name == ns.me then return mine end
	local short, now = ns.ShortName(name), ns.Now()
	for sender, w in pairs(where) do
		if sender == name or (not exact and ns.ShortName(sender) == short) then
			local m = seen[w[1]] and seen[w[1]][w[2]] and seen[w[1]][w[2]][sender]
			if m and now - m.t <= EXPIRE then return { mapID = w[1], zoneUID = w[2], t = m.t } end
		end
	end
	return nil
end

function Layers.InSample()
	local h = 0
	for i = 1, #(ns.me or "") do h = (h * 31 + ns.me:byte(i)) % 1000003 end
	return h % 8 == 0
end

function Layers.Receive(sender, l)
	if not ns.IsFederation(l.guild) then return end
	sender = ns.FullName(sender)
	local old = where[sender]
	if old and seen[old[1]] and seen[old[1]][old[2]] then seen[old[1]][old[2]][sender] = nil end
	where[sender] = { l.mapID, l.zoneUID }
	seen[l.mapID] = seen[l.mapID] or {}
	seen[l.mapID][l.zoneUID] = seen[l.mapID][l.zoneUID] or {}
	-- The rank written in the message is not trusted: only verified Lords and Captains
	-- (or ranks from our own roster) can give a layer its name.
	local rank = ns.Data.KnownRank(sender, l.guild) or 9
	seen[l.mapID][l.zoneUID][sender] = { rank = rank, guild = l.guild, t = ns.Now() }
	ns.Fire("LAYERS_CHANGED")
end

local function Prune()
	local now = ns.Now()
	for mapID, layers in pairs(seen) do
		for zoneUID, members in pairs(layers) do
			for name, m in pairs(members) do
				if now - m.t > EXPIRE then
					members[name] = nil
					where[name] = nil
				end
			end
			if not next(members) then layers[zoneUID] = nil end
		end
		if not next(layers) then seen[mapID] = nil end
	end
end

-- Seniority: rank first (0 = guild master), then the bigger guild, then name.
local function Better(a, b, sizes)
	if a.rank ~= b.rank then return a.rank < b.rank end
	local sa, sb = sizes[a.guild] or 0, sizes[b.guild] or 0
	if sa ~= sb then return sa > sb end
	return a.name < b.name
end

-- Layers seen in a zone, each with its name, head count and whether we are on it.
function Layers.ForMap(mapID)
	local source = seen
	local sizes = {}
	for _, e in ipairs(ns.Data.Summary().guilds) do sizes[e.name] = e.g.total or 0 end
	local now, out = ns.Now(), {}
	for zoneUID, members in pairs(source[mapID] or {}) do
		local best, count = nil, 0
		for name, m in pairs(members) do
			if now - m.t <= EXPIRE then
				count = count + 1
				local cand = { name = ns.DisplayName(name), rank = m.rank, guild = m.guild }
				if not best or Better(cand, best, sizes) then best = cand end
			end
		end
		local isMine = mine and mine.mapID == mapID and mine.zoneUID == zoneUID
		if isMine then
			count = count + 1
			local me = { name = ns.DisplayName(ns.me), rank = ns.Roster.MyRank(), guild = GetGuildInfo("player") or "" }
			if not best or Better(me, best, sizes) then best = me end
		end
		if count > 0 then
			out[#out + 1] = { zoneUID = zoneUID, count = count, head = best, mine = isMine }
		end
	end
	if mine and mine.mapID == mapID and not (source[mapID] and source[mapID][mine.zoneUID]) then
		out[#out + 1] = {
			zoneUID = mine.zoneUID, count = 1, mine = true,
			head = { name = ns.DisplayName(ns.me), rank = ns.Roster.MyRank(), guild = GetGuildInfo("player") or "" },
		}
	end
	table.sort(out, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.zoneUID < b.zoneUID
	end)
	return out
end

function Layers.Name(layer)
	if not layer or not layer.head then return L.LAYER_UNKNOWN end
	return L.LAYER_OF:format(layer.head.name)
end

function Layers.CurrentMap() return CurrentMap() end

ns.Comm.Handle("L1", function(dist, sender, text)
	if dist ~= "CHANNEL" then return end
	local l = ns.Codec.DecodeLayer(text)
	if l then Layers.Receive(sender, l) end
end)

ns.On("LOGIN", function()
	ns.RegisterEvent("PLAYER_TARGET_CHANGED", function() Observe("target") end)
	ns.RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() Observe("mouseover") end)
	ns.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(unit) Observe(unit) end)
	ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function() mine, pending = nil, nil; ns.Fire("LAYERS_CHANGED") end)
	ns.Every(60, "layer announce", function()
		Prune()
		Announce(false)
	end)
end)

