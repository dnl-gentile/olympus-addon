local ADDON, ns = ...
local L = ns.L
local Muster = {}
ns.OfficerMuster = Muster

-- Quiet officer calls, separate from player camps and the map's decrees. The normal logged
-- Olympus channel already separates factions; the envelope also binds the current realm group.
-- OM~1~P~<A|H>~<group>~<sequence>~<postedAt>~<guild>~<zoneID>~<title>
-- OM~1~E~<A|H>~<group>~<sequence>~<postedAt> : that poster ends the same call.
-- Nothing here publishes attendee names, coordinates, units, invites or new census records.
Muster.LIFE, Muster.REPEAT, Muster.GAP = 20 * 60, 300, 60
Muster.TITLE_MAX, Muster.MAX, Muster.FLOORS_MAX = 60, 20, 256
Muster.DATE_AHEAD, Muster.MAX_INT, Muster.RATE, Muster.RATE_ALL = 60, 2147483647, 6, 30
local rates, allRate, lastSent = {}, {}, -math.huge
local draft = { title = "" }
local function Clock() return ns.Data and ns.Data.ServerTime and ns.Data.ServerTime() or (GetServerTime and GetServerTime()) or ns.Now() end
local function Key(s) return ns.Fold(s) end
local function Count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function Int(n) return type(n) == "number" and n % 1 == 0 and n >= 1 and n <= Muster.MAX_INT end
local function Clean(s, max)
	return ns.Cut(tostring(s or ""):gsub("[~|%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""), max)
end
local function Field(s, max) return type(s) == "string" and s ~= "" and Clean(s, max) == s end
local function Faction() return ns.faction == "Horde" and "H" or (ns.faction == "Alliance" and "A" or nil) end
local function Group() return ns.group or (ns.GroupOf and ns.GroupOf(ns.realm)) end
local function Scope() local g, f = Group(), Faction(); return Field(g, 72) and f and (f .. "~" .. g) or nil end
local function Full(s)
	if not Field(s, 72) or s:find("[%^,]") then return nil end
	local full = ns.FullName(s)
	local realm = ns.RealmOf(full)
	if not realm or not ns.GroupOf or ns.GroupOf(realm) ~= Group() then return nil end
	return full
end
local function Zone(id)
	if not Int(id) or id > 999999 or not C_Map or not C_Map.GetMapInfo then return false end
	local info = C_Map.GetMapInfo(id)
	return type(info) == "table" and type(info.mapType) == "number" and info.mapType == 3
end
local function ZoneName(id) return ns.Zones.NameForKey("m" .. id) end
local function Authorized(by, guild)
	if not Full(by) or not Field(guild, 72) or not ns.IsFederation(guild) then return false end
	local WC, M, K = ns.WatchChat, ns.Moderation, ns.King
	if WC and not WC.missing and WC.Barred and WC.Barred("powers", by) then return false end
	if M and M.Hides and M.Hides(by, guild) then return false end
	if ns.IsKingCharacter and ns.IsKingCharacter(by) then return true end
	if K and not K.missing and ((K.IsStewardName and K.IsStewardName(by)) or (K.IsHandName and K.IsHandName(by))) then return true end
	local rank, source = ns.Data.AuthorizedRank(by, guild)
	return rank == 0 and (source == "roster" or source == "signed" or source == "pinned")
end
function Muster.CanPost()
	if not ns.IsMember() or not Scope() then return false end
	local V = ns.ViewAs
	if V and V.Previewing and V.Previewing() then return false end
	local guild = GetGuildInfo("player")
	return Authorized(ns.me, guild), guild
end
local function Store()
	local scope = Scope()
	if not scope or type(ns.rdb) ~= "table" then return nil end
	local s = ns.rdb.officerMuster
	if type(s) ~= "table" or s.v ~= 1 or s.scope ~= scope then
		s = { v = 1, scope = scope, active = {}, floors = {}, seq = 0 }
		ns.rdb.officerMuster = s
	end
	if type(s.active) ~= "table" then s.active = {} end
	if type(s.floors) ~= "table" then s.floors = {} end
	if not Int(s.seq) then s.seq = 0 end
	return s
end
local function Valid(row)
	return type(row) == "table" and Full(row.by) == row.by and row.scope == Scope() and Int(row.seq) and Int(row.at)
		and Field(row.guild, 72) and Field(row.title, Muster.TITLE_MAX) and Zone(row.zone)
end
local function Refresh()
	if ns.Views and ns.Views.PageShown and ns.Views.PageShown() == "officermuster" and ns.UI and ns.UI.RefreshSoon then ns.UI.RefreshSoon() end
end
local function Changed() ns.Fire("OFFICER_MUSTER_CHANGED"); Refresh() end
local function Headcount(row)
	return ns.Layers and ns.Layers.CountSharedInZone and ns.Layers.CountSharedInZone(row.zone) or 0
end
local function EndCall(s, key, row, reason, quiet)
	local floor = s.floors[key]
	if floor and floor.seq == row.seq and floor.ended then s.active[key] = nil; return false end
	if not floor or floor.seq <= row.seq then s.floors[key] = { seq = row.seq, at = row.at, ended = true } end
	s.active[key] = nil
	-- The independent persistent floor, not the Chronicle's retained rows, owns the once-only
	-- ending. Its original server-stamped author remains the attribution on expiry or role loss.
	if not quiet and ns.Chronicle and ns.Chronicle.Add then
		ns.Chronicle.Add("muster", row.by, L.OFFICER_MUSTER_ENDED:format(ZoneName(row.zone), Headcount(row), reason),
			{ id = "muster:" .. Faction() .. ":" .. key .. ":" .. row.seq, words = row.title })
	end
	Changed()
	return true
end
local function Prune(s)
	local now = Clock()
	for key, row in pairs(s.active) do
		if not Valid(row) or key ~= Key(row.by) or row.at > now + Muster.DATE_AHEAD then s.active[key] = nil
		elseif not Authorized(row.by, row.guild) then EndCall(s, key, row, nil, true)
		elseif now >= row.at + Muster.LIFE then EndCall(s, key, row, L.OFFICER_MUSTER_END_EXPIRED) end
	end
	for key, f in pairs(s.floors) do
		if type(f) ~= "table" or not Int(f.seq) or not Int(f.at) or now > f.at + Muster.LIFE + Muster.DATE_AHEAD then s.floors[key] = nil end
	end
	for key, list in pairs(rates) do if #list == 0 or ns.Now() - list[#list] >= 60 then rates[key] = nil end end
end
local function Rate(list, max)
	local now = ns.Now()
	for i = #list, 1, -1 do if now - list[i] >= 60 then table.remove(list, i) end end
	if #list >= max then return false end
	list[#list + 1] = now; return true
end
local function Budget(by)
	local key = Key(by)
	rates[key] = rates[key] or {}
	return Rate(rates[key], Muster.RATE) and Rate(allRate, Muster.RATE_ALL)
end
local function Encode(row, ending)
	local prefix = ("OM~1~%s~%s~%s~%d~%d"):format(ending and "E" or "P", Faction(), Group(), row.seq, row.at)
	return ending and prefix or (prefix .. ("~%s~%d~%s"):format(row.guild, row.zone, row.title))
end
local function Send(s, row, ending)
	local scope, by, key = Scope(), ns.me, Key(row.by)
	local msg = Encode(row, ending)
	if #msg > 255 then return false end
	return ns.Comm.Send("CHANNEL", msg, "officermuster:" .. key, false, true, nil, { guard = function()
		if ns.me ~= by or Scope() ~= scope or Clock() >= row.at + Muster.LIFE then return false end
		local can, guild = Muster.CanPost()
		if not can or guild ~= row.guild or Store() ~= s then return false end
		local floor = s.floors[key]
		if ending then return floor ~= nil and floor.seq == row.seq and floor.ended == true end
		return s.active[key] == row and Authorized(row.by, row.guild)
	end }) ~= false
end
function Muster.Handle(dist, sender, text)
	if dist ~= "CHANNEL" or type(text) ~= "string" or #text > 255 then return false, "shape" end
	local by = Full(sender)
	if not by then return false, "realm" end
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm.DeliveredLogged and not ns.Comm.DeliveredLogged() then return false, "unlogged" end
	local op, faction, group, seq, at, rest = text:match("^OM~1~([PE])~([AH])~([^~]+)~(%d+)~(%d+)(.*)$")
	seq, at = tonumber(seq), tonumber(at)
	if not op or faction ~= Faction() or group ~= Group() then return false, "scope" end
	local now = Clock()
	if not Int(seq) or not Int(at) then return false, "shape" end
	if at > now + Muster.DATE_AHEAD or now >= at + Muster.LIFE then return false, "time" end
	local row
	if op == "P" then
		local guild, zone, title = rest:match("^~([^~]+)~(%d+)~([^~]+)$")
		row = { by = by, scope = Scope(), seq = seq, at = at, guild = guild, zone = tonumber(zone), title = title }
		if not Valid(row) then return false, "shape" end
		if not Authorized(by, guild) then return false, "role" end
	elseif rest ~= "" then return false, "shape" end
	local s, key = Store(), Key(by)
	if not s then return false, "store" end
	Prune(s)
	local old, floor = s.active[key], s.floors[key]
	if op == "E" then
		if floor and floor.seq >= seq and floor.ended then return true, "repeat" end
		if not old or old.seq ~= seq or old.at ~= at then return false, "unknown" end
		return EndCall(s, key, old, L.OFFICER_MUSTER_END_WITHDRAWN)
	end
	if floor and seq <= floor.seq then
		if old and old.seq == seq and old.at == at and old.guild == row.guild and old.zone == row.zone and old.title == row.title then return true, "repeat" end
		return false, "older"
	end
	if floor and at - floor.at < Muster.GAP then return false, "rate" end
	if not floor and Count(s.floors) >= Muster.FLOORS_MAX then return false, "full" end
	if not old and Count(s.active) >= Muster.MAX then return false, "full" end
	if not Budget(by) then return false, "rate" end
	if old then EndCall(s, key, old, L.OFFICER_MUSTER_END_REPLACED) end
	s.active[key], s.floors[key] = row, { seq = seq, at = at }
	Changed(); return true
end
function Muster.Post(title, zone)
	local can, guild = Muster.CanPost()
	if not can then return false, "role" end
	title = Clean(title, Muster.TITLE_MAX)
	if not Field(title, Muster.TITLE_MAX) or not Zone(zone) then return false, "shape" end
	local s, key, at = Store(), Key(ns.me), math.floor(Clock())
	if not s then return false, "store" end
	Prune(s)
	local old, floor = s.active[key], s.floors[key]
	if floor and at - floor.at < Muster.GAP then return false, "rate" end
	if not floor and Count(s.floors) >= Muster.FLOORS_MAX then return false, "full" end
	if not old and Count(s.active) >= Muster.MAX then return false, "full" end
	local seq = math.max(at, s.seq + 1, floor and floor.seq + 1 or 1)
	if not Int(seq) then return false, "sequence" end
	local row = { by = ns.me, scope = Scope(), seq = seq, at = at, guild = guild, zone = zone, title = title }
	if not Send(s, row) then return false, "queue" end
	if old then EndCall(s, key, old, L.OFFICER_MUSTER_END_REPLACED) end
	s.seq, s.active[key], s.floors[key], lastSent = seq, row, { seq = seq, at = at }, ns.Now()
	Changed(); return true
end
function Muster.Withdraw()
	local can, guild = Muster.CanPost()
	if not can then return false, "role" end
	local s, key = Store(), ns.me and Key(ns.me)
	if s then Prune(s) end
	local row = s and key and s.active[key]
	if not row or not Valid(row) or row.guild ~= guild then return false, "absent" end
	if not Send(s, row, true) then return false, "queue" end
	return EndCall(s, key, row, L.OFFICER_MUSTER_END_WITHDRAWN)
end
function Muster.List()
	local s, out = Store(), {}
	if not s then return out end
	Prune(s)
	for _, row in pairs(s.active) do out[#out + 1] = row end
	table.sort(out, function(a, b) if a.at ~= b.at then return a.at > b.at end; return a.by < b.by end)
	return out
end
function Muster.Tick()
	local s = Store()
	if not s then return end
	Prune(s)
	local own = ns.me and s.active[Key(ns.me)]
	if own and ns.Now() - lastSent >= Muster.REPEAT and Send(s, own) then lastSent = ns.Now() end
	Refresh()
end
function Muster.Link()
	if not ns.IsMember() then return nil end
	return { text = "|cffffd200> " .. L.OFFICER_MUSTER_TITLE .. "|r", onClick = function() ns.Views.ShowPage("officermuster") end }
end
function Muster.Lines(q)
	if not ns.IsMember() then return {} end
	local lines = { { text = L.OFFICER_MUSTER_BACK, onClick = function() ns.Views.ShowPage(nil) end, gapAfter = true },
		{ header = true, text = L.OFFICER_MUSTER_TITLE }, { text = L.OFFICER_MUSTER_HINT }, { text = L.OFFICER_MUSTER_COUNTS_NOTE, gapAfter = true } }
	if not q and Muster.CanPost() then
		lines[#lines + 1] = { text = L.OFFICER_MUSTER_DRAFT, input = { text = draft.title, maxLetters = Muster.TITLE_MAX,
			onChange = function(text) draft.title = Clean(text, Muster.TITLE_MAX) end } }
		lines[#lines + 1] = { text = L.OFFICER_MUSTER_ZONE:format(draft.zone and ZoneName(draft.zone) or L.OFFICER_MUSTER_NO_ZONE) }
		lines[#lines + 1] = { text = L.OFFICER_MUSTER_USE_ZONE, onClick = function()
			local zone = ns.Layers.CurrentMap()
			if Zone(zone) then draft.zone = zone; Changed() end
		end }
		lines[#lines + 1] = { text = L.OFFICER_MUSTER_POST, onClick = function()
			local ok, why = Muster.Post(draft.title, draft.zone)
			if ok then draft = { title = "" }; Changed() else ns.Print(L.OFFICER_MUSTER_ERROR:format(why)) end
		end, gapAfter = true }
	end
	local shown = 0
	for _, row in ipairs(Muster.List()) do
		local title = row.title
		local F = ns.Filter
		if F and not F.missing and F.Hides and F.Hides(title) then title = L.FILTER_WORDS_HIDDEN_SHORT end
		local zone, who = ZoneName(row.zone), ns.DisplayName(row.by)
		if not q or ns.Holds(q, title, zone, who) then
			shown = shown + 1
			lines[#lines + 1] = { text = "|cffffd200" .. title .. "|r  —  " .. zone,
				right = L.OFFICER_MUSTER_OBSERVED:format(Headcount(row), math.max(0, math.ceil((row.at + Muster.LIFE - Clock()) / 60))) }
			lines[#lines + 1] = { indent = 1, text = L.OFFICER_MUSTER_BY:format(who) }
			if row.by == ns.me then lines[#lines + 1] = { indent = 1, text = L.OFFICER_MUSTER_END, onClick = Muster.Withdraw } end
		end
	end
	if shown == 0 then lines[#lines + 1] = { text = q and L.SEARCH_NO_MATCH or L.OFFICER_MUSTER_EMPTY } end
	return lines
end
ns.RealmPages = ns.RealmPages or {}
table.insert(ns.RealmPages, { key = "officermuster", Link = Muster.Link, Lines = Muster.Lines, tip = "OFFICER_MUSTER_TITLE" })
ns.Comm.Handle("OM", Muster.Handle)
for _, event in ipairs({ "DATA_CHANGED", "THRONE_CHANGED", "WATCH_CHANGED", "MODERATION_CHANGED" }) do
	ns.On(event, function() local s = Store(); if s then Prune(s) end; Refresh() end)
end
for _, event in ipairs({ "LAYERS_CHANGED", "LAYER_SHARING_CHANGED", "KING_LOCATION_CHANGED" }) do ns.On(event, Refresh) end
ns.On("LOGIN", function() ns.Every(30, "officer muster", Muster.Tick) end)
