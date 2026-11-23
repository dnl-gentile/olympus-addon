local ADDON, ns = ...
local MapNames = {}
ns.MapNames = MapNames

-- Shared display names belong to a map id, never its localized roster name. Only the actual
-- King and the signed council publish them: no preview, author, Hand or guild-rank fallback.
-- The transport's authenticated origin is supplied by Comm, including Forever's trusted relay.
MapNames.MAX_TEXT, MapNames.MAX_PLACES = 96, 128
MapNames.MAX_MAP, MapNames.AHEAD = 5000, 120
MapNames.FIRST_DAY, MapNames.REPEAT, MapNames.PER_TICK = 1700000000, 30, 4
local cursor, heard = 0, {}
local function Clock() return math.floor((GetServerTime and GetServerTime()) or ns.Now()) end
local function Store()
	if not ns.rdb then return nil end
	if type(ns.rdb.mapNames) ~= "table" then ns.rdb.mapNames = {} end
	return ns.rdb.mapNames
end
local function Barred(name)
	local W = ns.WatchChat
	return W and not W.missing and W.Barred and W.Barred("powers", name) == true
end
function MapNames.IsEditor(name)
	if type(name) ~= "string" or name == "" then return false end
	if ns.IsKingCharacter(name) then return true end
	return ns.IsHighCouncillor(name) == true and not Barred(name)
end
function MapNames.CanEdit()
	return ns.IsMember() == true and ns.SharedToolsHere() and MapNames.IsEditor(ns.me)
end
function MapNames.ValidMap(id)
	return type(id) == "number" and id == math.floor(id) and id >= 1 and id <= MapNames.MAX_MAP
		and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id) ~= nil
end
-- A map label uses its numeric uiMapID. Artwork-only place names use a bounded point on
-- that map; the canvas has no native text object for those names to rename.
function MapNames.Place(key)
	if MapNames.ValidMap(key) then return key end
	if type(key) ~= "string" or #key > 24 then return nil end
	local map, x, y = key:match("^p(%d+):(%d+):(%d+)$")
	map, x, y = tonumber(map), tonumber(x), tonumber(y)
	if not MapNames.ValidMap(map) or not x or x > 1000 or not y or y > 1000 then return nil end
	if key ~= ("p%d:%d:%d"):format(map, x, y) then return nil end
	return map, x / 1000, y / 1000
end
function MapNames.Point(map, x, y)
	if not MapNames.ValidMap(map) or type(x) ~= "number" or type(y) ~= "number"
		or x ~= x or y ~= y or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
	return ("p%d:%d:%d"):format(map, math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5))
end
function MapNames.Original(key)
	local map, x, y = MapNames.Place(key)
	local info = map and C_Map.GetMapInfo(map)
	if not info then return nil end
	local name = ns.Codec.Plain(info.name)
	return x and ("%s (%.1f%%, %.1f%%)"):format(name, x * 100, y * 100) or name
end
-- Reject markup, wire delimiters and controls, rather than silently publishing different words.
-- UTF-8 is preserved; limits are bytes so one edit always fits one logged addon message.
function MapNames.Text(value, revert)
	if revert and value == "" then return "" end
	if type(value) ~= "string" or value == "" or #value > MapNames.MAX_TEXT
		or value:find("[%z\1-\31\127|~]") or value:match("^%s") or value:match("%s$") then return nil end
	if ns.Codec.Plain(value) ~= value then return nil end
	return value
end
local function Hidden(text)
	return text ~= "" and ns.Filter and ns.Filter.Hides and ns.Filter.Hides(text) == true
end
local function ValidEntry(id, e)
	return MapNames.Place(id) ~= nil and type(e) == "table" and type(e.at) == "number"
		and e.at == math.floor(e.at) and e.at >= MapNames.FIRST_DAY and e.at <= Clock() + MapNames.AHEAD
		and type(e.by) == "string" and #e.by > 0 and #e.by <= 100 and not e.by:find("[%z\1-\31\127|~]")
		and MapNames.Text(e.text, true) ~= nil
end
-- Keep revoked authors' entries and permanent revert tombstones within the same fixed bound.
-- They remain replay barriers, but neither display nor relay while their author lacks authority.
function MapNames.Prune()
	local S = Store()
	if not S then return end
	local ids = {}
	for id, e in pairs(S) do
		if not ValidEntry(id, e) then S[id] = nil else ids[#ids + 1] = id end
	end
	table.sort(ids, function(a, b)
		if S[a].at ~= S[b].at then return S[a].at > S[b].at end
		return tostring(a) < tostring(b)
	end)
	for i = MapNames.MAX_PLACES + 1, #ids do S[ids[i]] = nil end
	for id in pairs(heard) do if not S[id] then heard[id] = nil end end
end
function MapNames.Name(id, original)
	local S = ns.rdb and ns.rdb.mapNames
	local e = type(S) == "table" and S[id]
	if ns.IsMember() and ns.SharedToolsHere() and ValidEntry(id, e) and e.text ~= "" and MapNames.IsEditor(e.by) and not Hidden(e.text) then return e.text end
	return original or MapNames.Original(id)
end
function MapNames.Entries()
	if not ns.SharedToolsHere() then return {} end
	local out = {}
	for key, e in pairs(Store() or {}) do
		if ValidEntry(key, e) and MapNames.IsEditor(e.by) and e.text ~= "" and not Hidden(e.text) then
			out[#out + 1] = { key = key, text = e.text }
		end
	end
	table.sort(out, function(a, b) return tostring(a.key) < tostring(b.key) end)
	return out
end
local function Count(S) local n = 0 for _ in pairs(S) do n = n + 1 end return n end
local function Wire(id, e) return table.concat({ "MN", "1", id, e.at, e.by, e.text }, "~") end
local function Same(a, b)
	return a == b or (type(a) == "table" and type(b) == "table" and a.at == b.at and a.by == b.by and a.text == b.text)
end
local function Newer(a, b)
	if type(b) ~= "table" then return true end
	if a.at ~= b.at then return a.at > b.at end
	if a.by ~= b.by then return a.by > b.by end
	return a.text > b.text
end
local function RecentlyHeard(id) return heard[id] and ns.Now() - heard[id] < MapNames.REPEAT * 2 end
local function Send(id, e, direct)
	return ns.Comm.Send("CHANNEL", Wire(id, e), "mapname:" .. id, direct == true, true, nil, {
		owner = "mapnames", guard = function()
			local S = Store()
			return MapNames.CanEdit() and S and Same(S[id], e) and MapNames.IsEditor(e.by) and not Hidden(e.text)
				and (direct == true or not RecentlyHeard(id))
		end,
	})
end
-- A preview is local only. A changed entry, withdrawn authority or newly blocked text invalidates
-- it before the explicit confirmation, so an older open editor cannot silently replace a new edit.
function MapNames.Preview(id, value, revert)
	if not MapNames.CanEdit() then return nil, ns.L.MAPNAME_DENIED end
	if not MapNames.Place(id) then return nil, ns.L.MAPNAME_BAD_PLACE end
	local text = MapNames.Text(revert and "" or value, revert)
	if text == nil or Hidden(text) then return nil, ns.L.MAPNAME_BAD_TEXT end
	local S = Store()
	if not S then return nil, ns.L.MAPNAME_DENIED end
	if not S[id] and Count(S) >= MapNames.MAX_PLACES then return nil, ns.L.MAPNAME_FULL end
	local e = S[id]
	local old = type(e) == "table" and { at = e.at, by = e.by, text = e.text } or nil
	return { id = id, text = text, before = old, original = MapNames.Original(id), shown = text ~= "" and text or (type(id) == "string" and ns.L.MAPNAME_ARTWORK or MapNames.Original(id)) }
end
function MapNames.Confirm(preview)
	if type(preview) ~= "table" then return false, ns.L.MAPNAME_CHANGED end
	local checked, err = MapNames.Preview(preview.id, preview.text, preview.text == "")
	if not checked then return false, err end
	if not Same(checked.before, preview.before) then return false, ns.L.MAPNAME_CHANGED end
	local S = Store()
	local at = math.max(Clock(), (S[preview.id] and S[preview.id].at or 0) + 1)
	if at > Clock() + MapNames.AHEAD then return false, ns.L.MAPNAME_CHANGED end
	local e = { at = at, by = ns.FullName(ns.me), text = preview.text }
	if #Wire(preview.id, e) > 255 then return false, ns.L.MAPNAME_BAD_TEXT end
	S[preview.id] = e
	Send(preview.id, e, true)
	ns.Fire("MAP_NAMES_CHANGED")
	return true
end
function MapNames.Receive(dist, sender, message)
	if not ns.SharedPeerAllowed(sender) then return false end
	if dist ~= "CHANNEL" or not ns.IsMember() or not MapNames.IsEditor(sender)
		or type(message) ~= "string" or #message > 255 then return false end
	local id, at, author, text = message:match("^MN~1~([^~]+)~(%d+)~([^~]+)~([^~]*)$")
	id, at = tonumber(id) or id, tonumber(at)
	local e = { at = at, by = author, text = text }
	if not ValidEntry(id, e) or not MapNames.IsEditor(author) then return false end
	local S = Store()
	if not S or (not S[id] and Count(S) >= MapNames.MAX_PLACES) then return false end
	if Same(e, S[id]) then heard[id] = ns.Now(); return false end
	if not Newer(e, S[id]) then return false end
	heard[id] = ns.Now()
	-- Filtering is checked again at every display and relay. Keep a hidden valid revision so an
	-- older allowed name cannot overwrite it; removing a personal filter can reveal it later.
	S[id] = e
	ns.Fire("MAP_NAMES_CHANGED")
	return true
end
ns.Comm.Handle("MN", MapNames.Receive)

-- Four single messages per tick, rotating through the bounded persisted set. Late logins catch
-- up from current editors without another fan-out request; quiet presence suppresses repeats.
-- A matching record heard from another editor suppresses our copy for two ticks, including
-- copies already queued. The suppression map is bounded by the same persisted keys.
function MapNames.Tick()
	if not MapNames.CanEdit() or (ns.QuietPresence and ns.QuietPresence()) then return 0 end
	MapNames.Prune()
	local S, ids = Store(), {}
	for id, e in pairs(S or {}) do
		if MapNames.IsEditor(e.by) and not Hidden(e.text) then ids[#ids + 1] = id end
	end
	table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
	if #ids == 0 then cursor = 0 return 0 end
	local sent = 0
	for _ = 1, #ids do
		cursor = cursor % #ids + 1
		local id = ids[cursor]
		if not RecentlyHeard(id) and Send(id, S[id]) then sent = sent + 1 end
		if sent >= MapNames.PER_TICK then break end
	end
	return sent
end
ns.On("LOGIN", function()
	MapNames.Prune()
	ns.Every(MapNames.REPEAT, "map names", MapNames.Tick)
end)
