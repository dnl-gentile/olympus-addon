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
local EXPIRE = 10 * 60

local mine          -- { mapID, zoneUID, t }
local lastAnnounce = 0
local seen = {}     -- [mapID][zoneUID][sender] = { rank, guild, t }

local function ZoneUIDFromGUID(guid)
	if not guid then return nil end
	local unitType, _, _, _, zoneUID = strsplit("-", guid)
	if unitType ~= "Creature" and unitType ~= "Vehicle" then return nil end
	return tonumber(zoneUID)
end

local function CurrentMap()
	return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
end

local function Announce(force)
	if not mine or not IsInGuild() then return end
	local now = ns.Now()
	if not force and now - lastAnnounce < ANNOUNCE_EVERY then return end
	if now - lastAnnounce < MIN_GAP then return end
	lastAnnounce = now
	local guild = GetGuildInfo("player")
	if not ns.IsFederation(guild) then return end
	-- With thousands of users only officers and a stable 1 in 8 sample announce, which is
	-- enough to see the layers and to name each one after its highest rank.
	if not ns.Roster.IsOfficer() and not Layers.InSample() then return end
	ns.Comm.Send("CHANNEL", ns.Codec.EncodeLayer(mine.mapID, mine.zoneUID, ns.Roster.MyRank(), guild), "layer")
end

local function Observe(unit)
	if IsInInstance() then return end
	local zoneUID = ZoneUIDFromGUID(UnitGUID(unit))
	local mapID = CurrentMap()
	if not zoneUID or not mapID then return end
	local changed = not mine or mine.zoneUID ~= zoneUID or mine.mapID ~= mapID
	mine = { mapID = mapID, zoneUID = zoneUID, t = ns.Now() }
	if changed then
		ns.Log("layer: map %d zoneUID %d", mapID, zoneUID)
		Announce(true)
		ns.Fire("LAYERS_CHANGED")
	end
end

function Layers.Mine() return mine end

function Layers.InSample()
	local h = 0
	for i = 1, #(ns.me or "") do h = (h * 31 + ns.me:byte(i)) % 1000003 end
	return h % 8 == 0
end

function Layers.Receive(sender, l)
	if not ns.IsFederation(l.guild) then return end
	seen[l.mapID] = seen[l.mapID] or {}
	seen[l.mapID][l.zoneUID] = seen[l.mapID][l.zoneUID] or {}
	seen[l.mapID][l.zoneUID][ns.ShortName(sender)] = { rank = l.rank, guild = l.guild, t = ns.Now() }
	ns.Fire("LAYERS_CHANGED")
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
	-- Demo layers follow you to whatever zone you are in.
	if ns.db.demo and ns.demoLayers then source = { [mapID] = ns.demoLayers } end
	local sizes = {}
	for _, e in ipairs(ns.Data.Summary().guilds) do sizes[e.name] = e.g.total or 0 end
	local now, out = ns.Now(), {}
	for zoneUID, members in pairs(source[mapID] or {}) do
		local best, count = nil, 0
		for name, m in pairs(members) do
			if now - m.t <= EXPIRE then
				count = count + 1
				local cand = { name = name, rank = m.rank, guild = m.guild }
				if not best or Better(cand, best, sizes) then best = cand end
			end
		end
		local isMine = mine and mine.mapID == mapID and mine.zoneUID == zoneUID
		if isMine then
			count = count + 1
			local me = { name = ns.ShortName(ns.me), rank = ns.Roster.MyRank(), guild = GetGuildInfo("player") or "" }
			if not best or Better(me, best, sizes) then best = me end
		end
		if count > 0 then
			out[#out + 1] = { zoneUID = zoneUID, count = count, head = best, mine = isMine }
		end
	end
	if mine and mine.mapID == mapID and not (source[mapID] and source[mapID][mine.zoneUID]) then
		out[#out + 1] = {
			zoneUID = mine.zoneUID, count = 1, mine = true,
			head = { name = ns.ShortName(ns.me), rank = ns.Roster.MyRank(), guild = GetGuildInfo("player") or "" },
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

function Layers.BuildDemo()
	local now = ns.Now()
	local function crowd(n, head, headRank, headGuild)
		local t = { [head] = { rank = headRank, guild = headGuild, t = now } }
		for i = 1, n do t["Soldier" .. i .. head] = { rank = 5, guild = "Olympus II", t = now } end
		return t
	end
	ns.demoLayers = {
		[4101] = crowd(38, "Asmongold", 0, "Olympus"),
		[4102] = crowd(21, "Zeuslord", 0, "Olympus II"),
		[4103] = crowd(9, "Owlwise", 1, "Olympus Athena"),
	}
end

ns.Comm.Handle("L1", function(dist, sender, text)
	if dist ~= "CHANNEL" then return end
	local l = ns.Codec.DecodeLayer(text)
	if l then Layers.Receive(sender, l) end
end)

ns.On("LOGIN", function()
	if ns.db.demo then Layers.BuildDemo() end
	ns.RegisterEvent("PLAYER_TARGET_CHANGED", function() Observe("target") end)
	ns.RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() Observe("mouseover") end)
	ns.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(unit) Observe(unit) end)
	ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function() mine = nil; ns.Fire("LAYERS_CHANGED") end)
	ns.Every(60, "layer announce", function() Announce(false) end)
end)

ns.On("DEMO_CHANGED", function(on)
	if on then Layers.BuildDemo() end
	ns.Fire("LAYERS_CHANGED")
end)
