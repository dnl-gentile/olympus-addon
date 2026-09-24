local ADDON, ns = ...
local L = ns.L

-- Layer hop: instead of begging in chat for an invite to someone's layer, a player asks the
-- addon. The ask goes out on the Olympus channel with the layer wanted (a zone and the zone
-- UID read from NPC GUIDs, see Layers.lua). Players on that layer who can invite answer the
-- asker alone, each only with a chance scaled to how many are there, so a crowded layer sends
-- a handful of offers instead of hundreds. The asker draws one at random, favouring players
-- outside a group and with fewer recent invites, so many askers spread over many helpers.
-- That helper gets "X wants to join your layer" (or invites at once, if they chose that) and
-- says no when they can't; no answer or a no, the asker tries the next offer. The invite is
-- accepted for the asker, the game moves them to the helper's layer, and their addon takes
-- them out of the group once it sees the move. The main use: joining the King's layer while
-- he is online. Players alone on his layer are asked once whether the addon may do all of it
-- for them (invite, and let the guest go after a while: the guest's addon leaves, since only
-- a click may remove someone from a group).
--   LQ~<id>~<mapID>~<zoneUID>    (channel) who on this layer can invite me?
--   LO~<id>~<group>~<load>       (whisper) I can: my group size (0 = none), my recent invites
--   LR~<id>                      (whisper) please invite me
--   LN~<id>                      (whisper) I can't now
--   LX~<id>                      (whisper) your time in my group is up: please leave it

local Hop = {}
ns.Hop = Hop

Hop.OFFERS = 6          -- offers wanted per ask, however crowded the layer
Hop.WINDOW = 3          -- seconds the asker collects offers before choosing
Hop.WAIT = 25           -- seconds a chosen helper has to invite
Hop.TRIES = 3           -- helpers asked in turn before giving up
Hop.ASK_GAP = 20        -- one ask every 20 seconds
Hop.JOIN_WAIT = 20      -- in the group this long without seeing the move: offer to leave anyway
Hop.HELP_GAP = 60       -- the same asker is answered once a minute
Hop.LAYER_FRESH = 600   -- our layer counts this long after the last NPC seen
Hop.RECENT = 600        -- invites counted in the load we announce
Hop.MAX_OFFERS = 30     -- offers kept per ask
Hop.GUEST_TIME = 90     -- a guest the addon invited on its own is let go after this long
Hop.PROMPT_EVERY = 10   -- how often we check whether we are alone on the King's layer

-- Swappable in tests.
Hop.random = math.random
Hop.after = function(seconds, where, fn) ns.After(seconds, where, fn) end

local ask             -- our own request in progress
local lastAsk = -math.huge
local offered = {}    -- [id .. asker] = t: offers we sent (a request must match one)
local answeredAt = {} -- [asker] = t
local pending         -- the request on screen: { from, id, t }
local recent = {}     -- times of our last invites
local stats = { asks = 0, offers = 0, requests = 0, invites = 0, noes = 0, joins = 0, moves = 0, releases = 0 }
local guests = {}     -- [short name] = { name, id, t, release }: players we invited for a hop
local kingMode        -- this session's answer to the King's layer window: auto, manual or no
local promptShown, lastPromptCheck = false, -math.huge

local function Changed() ns.Fire("HOP_CHANGED") end

---------------------------------------------------------------------------
-- Helping: who can invite
---------------------------------------------------------------------------

-- Group size (0 = none) and whether we can invite one more: alone, or the leader (or an
-- assistant of a raid) with a free seat. A full party can't: making it a raid is a click.
function Hop.GroupState()
	if not (IsInGroup and IsInGroup()) then return 0, true end
	local n = GetNumGroupMembers and GetNumGroupMembers() or 1
	local raid = IsInRaid and IsInRaid()
	local lead = UnitIsGroupLeader and UnitIsGroupLeader("player")
	if not lead and raid and UnitIsGroupAssistant then lead = UnitIsGroupAssistant("player") end
	return n, (lead and n < (raid and 40 or 5)) and true or false
end

local function Load()
	local now, n = ns.Now(), 0
	for i = #recent, 1, -1 do
		if now - recent[i] > Hop.RECENT then table.remove(recent, i) else n = n + 1 end
	end
	return n
end

-- The answer to the King's layer window: this session's, else the one kept with "Don't ask
-- me again" (auto, manual or no), else nil.
local function KingChoice() return kingMode or ns.db.hopKingChoice end

-- We are on the King's layer (Hop.King below).
local function OnKingLayer()
	local k = Hop.King()
	local mine = ns.Layers.Mine()
	return (k and k.zoneUID and mine and mine.mapID == k.mapID and mine.zoneUID == k.zoneUID) and true or false
end

-- Alone, or in a party of our hop guests only: the addon may invite on its own. Never into a
-- group of the player's friends.
local function OnlyGuests()
	if not (IsInGroup and IsInGroup()) then return true end
	if IsInRaid and IsInRaid() then return false end
	for i = 1, 4 do
		local name = UnitName and UnitName("party" .. i)
		if name and not guests[ns.ShortName(name)] then return false end
	end
	return true
end

-- Everyone helps unless they turned it off (/oly layerhelp off). Not the King: he is the one
-- everybody wants, and his screen is on stream.
function Hop.CanHelp(mapID, zoneUID)
	if ns.db.layerHelp == false or not ns.IsMember() then return false end
	if ns.King and ns.King.IsKing and ns.King.IsKing() then return false end
	local mine = ns.Layers.Mine()
	if not mine or mine.mapID ~= mapID or mine.zoneUID ~= zoneUID then return false end
	if ns.Now() - (mine.t or 0) > Hop.LAYER_FRESH then return false end
	-- "Can't right now" on the King's layer window.
	if KingChoice() == "no" and OnKingLayer() then return false end
	if (IsInInstance and IsInInstance()) or (InCombatLockdown and InCombatLockdown()) then return false end
	if pending or (ask and ask.phase ~= "done") then return false end
	local _, room = Hop.GroupState()
	return room
end

-- The chance to answer, so a crowded layer sends about OFFERS offers in all. Layers.lua sees
-- the officers and a 1 in 8 sample, so the crowd is a few times what it counts.
function Hop.Chance(mapID, zoneUID)
	local count = 1
	for _, layer in ipairs(ns.Layers.ForMap(mapID)) do
		if layer.zoneUID == zoneUID then count = layer.count end
	end
	return math.min(1, Hop.OFFERS / math.max(1, count * 4))
end

function Hop.HandleAsk(dist, sender, text)
	if dist ~= "CHANNEL" then return end
	local id, mapID, zoneUID = text:match("^LQ~(%d+)~(%d+)~(%d+)$")
	id, mapID, zoneUID = tonumber(id), tonumber(mapID), tonumber(zoneUID)
	if not id then return end
	sender = ns.FullName(sender)
	local now = ns.Now()
	if now - (answeredAt[sender] or -math.huge) < Hop.HELP_GAP then return end
	if not Hop.CanHelp(mapID, zoneUID) then return end
	if Hop.random() > Hop.Chance(mapID, zoneUID) then return end
	answeredAt[sender] = now
	offered[id .. sender] = now
	local group = Hop.GroupState()
	local load = Load()
	-- A random pause spreads the offers of a crowd over a couple of seconds.
	Hop.after(0.2 + Hop.random() * 2.3, "hop offer", function()
		ns.Comm.Whisper(sender, ("LO~%d~%d~%d"):format(id, group, load))
		stats.offers = stats.offers + 1
	end)
end

-- release: the addon lets the guest go after GUEST_TIME (the helper chose that).
local function Invite(name, id, release)
	local target = ns.DisplayName(name)
	if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(target) elseif InviteUnit then InviteUnit(target) end
	guests[ns.ShortName(name)] = { name = name, id = id or 0, t = ns.Now(), release = release and true or false }
	recent[#recent + 1] = ns.Now()
	stats.invites = stats.invites + 1
	ns.Print(L.HOP_INVITING:format(target))
	ns.Log("hop: invited %s", tostring(name))
end

local function SayNo(name, id)
	ns.Comm.Whisper(name, ("LN~%d"):format(id))
	stats.noes = stats.noes + 1
end

-- A request answers one of our offers (anything else is ignored).
function Hop.HandleRequest(dist, sender, text)
	if dist ~= "WHISPER" then return end
	local id = tonumber(text:match("^LR~(%d+)$"))
	sender = ns.FullName(sender)
	local at = id and offered[id .. sender]
	if not at or ns.Now() - at > 120 then return end
	offered[id .. sender] = nil
	stats.requests = stats.requests + 1
	local _, room = Hop.GroupState()
	if not room or pending or (InCombatLockdown and InCombatLockdown()) then return SayNo(sender, id) end
	-- On its own ("Always invite", or "For Olympus!" on the King's layer): only while we are
	-- alone or with hop guests; in a group of our own we get the window.
	local auto = ns.db.layerAutoInvite or (KingChoice() == "auto" and OnKingLayer())
	if auto and OnlyGuests() then return Invite(sender, id, true) end
	pending = { from = sender, id = id, t = ns.Now() }
	ns.PlayAlert("soft")
	StaticPopup_Show("OLYMPUS_HOP_REQUEST", ns.DisplayName(sender), nil, pending)
	Changed()
end

local function Answer(data, invite, always)
	if not data or pending ~= data then return end
	pending = nil
	if always then
		ns.db.layerAutoInvite = true
		ns.Print(L.HOP_AUTO_ON)
	end
	if invite then Invite(data.from, data.id, always) else SayNo(data.from, data.id) end
	Changed()
end
Hop.Answer = Answer

StaticPopupDialogs["OLYMPUS_HOP_REQUEST"] = {
	text = L.HOP_REQUEST,
	button1 = L.HOP_INVITE,
	button2 = L.HOP_NOT_NOW,
	button3 = L.HOP_ALWAYS,
	OnAccept = function(self, data) ns.SafeCall("hop invite", Answer, data or self.data, true) end,
	OnAlt = function(self, data) ns.SafeCall("hop invite", Answer, data or self.data, true, true) end,
	-- Not now, Escape or the timeout: the asker moves on to someone else.
	OnCancel = function(self, data) ns.SafeCall("hop no", Answer, data or self.data, false) end,
	timeout = Hop.WAIT,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Asking
---------------------------------------------------------------------------

local function Finish(message)
	if not ask then return end
	ask.phase = "done"
	if message then ns.Print(message) end
	Changed()
end

-- Weighted draw: outside a group counts double, fewer recent invites counts more. Each asker
-- draws on its own, so a crowd of askers spreads over the helpers.
function Hop.Pick(offers, tried)
	local pool, total = {}, 0
	for name, o in pairs(offers) do
		if not tried[name] then
			local w = (o.group == 0 and 2 or 1) / (1 + o.load)
			pool[#pool + 1] = { o = o, w = w }
			total = total + w
		end
	end
	if #pool == 0 then return nil end
	table.sort(pool, function(a, b) return a.o.name < b.o.name end)
	local r = Hop.random() * total
	for _, p in ipairs(pool) do
		r = r - p.w
		if r <= 0 then return p.o end
	end
	return pool[#pool].o
end

function Hop.Next()
	if not ask or ask.phase == "done" then return end
	local o = ask.tries < Hop.TRIES and Hop.Pick(ask.offers, ask.tried)
	if not o then return Finish(ask.tries == 0 and L.HOP_NOBODY or L.HOP_GAVE_UP) end
	ask.tried[o.name] = true
	ask.tries = ask.tries + 1
	ask.helper, ask.phase, ask.asked = o.name, "requested", ns.Now()
	ns.Comm.Whisper(o.name, ("LR~%d"):format(ask.id))
	ns.Print(L.HOP_REQUESTED:format(ns.DisplayName(o.name)))
	Changed()
end

-- Ask for an invite to a layer (a zone and its zone UID), named for the messages.
function Hop.Ask(mapID, zoneUID, label)
	if not ns.IsMember() then return ns.Print(L.MEMBERS_ONLY) end
	if not mapID or not zoneUID then return ns.Print(L.HOP_NO_LAYER) end
	-- A zone UID only means something in its zone: the player must be there already.
	if ns.Layers.CurrentMap() ~= mapID then return ns.Print(L.HOP_OTHER_MAP:format(Hop.ZoneName(mapID))) end
	local mine = ns.Layers.Mine()
	if mine and mine.mapID == mapID and mine.zoneUID == zoneUID then return ns.Print(L.HOP_ALREADY) end
	if IsInGroup and IsInGroup() then return ns.Print(L.HOP_IN_GROUP) end
	local now = ns.Now()
	if ask and ask.phase ~= "done" then return ns.Print(L.HOP_BUSY) end
	if now - lastAsk < Hop.ASK_GAP then return ns.Print(L.HOP_WAIT:format(math.ceil(Hop.ASK_GAP - (now - lastAsk)))) end
	if not ns.Comm.ChannelReady() then return ns.Print(L.CHAN_NOT_READY) end
	lastAsk = now
	ask = {
		id = Hop.random(1, 99999), mapID = mapID, zoneUID = zoneUID, label = label or L.LAYER_UNKNOWN,
		t = now, phase = "asking", offers = {}, count = 0, tried = {}, tries = 0,
		from = mine and { mapID = mine.mapID, zoneUID = mine.zoneUID },
	}
	stats.asks = stats.asks + 1
	ns.Comm.Send("CHANNEL", ("LQ~%d~%d~%d"):format(ask.id, mapID, zoneUID))
	ns.Print(L.HOP_ASKING:format(ask.label))
	ns.Log("hop: ask %d for map %d zoneUID %d", ask.id, mapID, zoneUID)
	Changed()
end

function Hop.HandleOffer(dist, sender, text)
	if dist ~= "WHISPER" or not ask or ask.phase == "done" or ask.phase == "joined" then return end
	local id, group, load = text:match("^LO~(%d+)~(%d+)~(%d+)$")
	if tonumber(id) ~= ask.id then return end
	sender = ns.FullName(sender)
	if ask.offers[sender] or ask.count >= Hop.MAX_OFFERS then return end
	ask.offers[sender] = { name = sender, group = math.min(tonumber(group), 40), load = math.min(tonumber(load), 99), t = ns.Now() }
	ask.count = ask.count + 1
	Changed()
end

function Hop.HandleNo(dist, sender, text)
	if dist ~= "WHISPER" or not ask or ask.phase ~= "requested" then return end
	if tonumber(text:match("^LN~(%d+)$")) ~= ask.id or ns.FullName(sender) ~= ask.helper then return end
	Hop.Next()
end

-- The invite we asked for: accept it for the player (anyone else's invite is left alone).
function Hop.OnInvite(name)
	if not ask or ask.phase ~= "requested" or not ask.helper then return end
	if not name or ns.ShortName(name) ~= ns.ShortName(ask.helper) then return end
	local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible("PARTY_INVITE")
	if dialog then dialog.inviteAccepted = 1 end
	if AcceptGroup then AcceptGroup() end
	if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
	ask.phase = "accepted"
	ns.Log("hop: accepted the invite from %s", tostring(name))
	Changed()
end

local function LeaveGroup()
	if C_PartyInfo and C_PartyInfo.LeaveParty then C_PartyInfo.LeaveParty() elseif LeaveParty then LeaveParty() end
end

-- Out of the helper's group, the hop done (a layer stays after the group is left).
local function Leave(message)
	LeaveGroup()
	if StaticPopup_Hide then StaticPopup_Hide("OLYMPUS_HOP_LEAVE") end
	Finish(message)
end

-- No move seen after a while (no NPC around): the player decides.
local function OfferLeave()
	if not ask or ask.leaveShown then return end
	ask.leaveShown = true
	ns.PlayAlert("soft")
	StaticPopup_Show("OLYMPUS_HOP_LEAVE", L.HOP_MAYBE_MOVED)
end

StaticPopupDialogs["OLYMPUS_HOP_LEAVE"] = {
	text = "%s",
	button1 = L.HOP_LEAVE,
	button2 = L.HOP_STAY,
	OnAccept = function() ns.SafeCall("hop leave", function() LeaveGroup(); Finish(L.HOP_DONE) end) end,
	OnCancel = function() ns.SafeCall("hop stay", Finish) end,
	timeout = 60,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function Hop.OnRoster()
	if not ask then return end
	local grouped = IsInGroup and IsInGroup()
	if (ask.phase == "accepted" or ask.phase == "requested") and grouped then
		ask.phase, ask.joined = "joined", ns.Now()
		stats.joins = stats.joins + 1
		ns.Print(L.HOP_JOINED:format(ns.DisplayName(ask.helper or "?")))
		Changed()
	elseif ask.phase == "joined" and not grouped then
		Finish()
	end
end

-- In the group: the move shows as a new zone UID for our zone, or the one we asked for.
function Hop.OnLayer()
	if not ask or ask.phase ~= "joined" then return end
	local mine = ns.Layers.Mine()
	if not mine then return end
	local target = mine.mapID == ask.mapID and mine.zoneUID == ask.zoneUID
	local changed = ask.from and mine.mapID == ask.from.mapID and mine.zoneUID ~= ask.from.zoneUID
	if target or changed then
		stats.moves = stats.moves + 1
		Leave(L.HOP_MOVED_LEFT)
	end
end

-- The helper's addon lets us go (their guests stay GUEST_TIME at most).
function Hop.HandleRelease(dist, sender, text)
	if dist ~= "WHISPER" or not ask or ask.phase ~= "joined" or not ask.helper then return end
	if tonumber(text:match("^LX~(%d+)$")) ~= ask.id then return end
	if ns.ShortName(ns.FullName(sender)) ~= ns.ShortName(ask.helper) then return end
	Leave(L.HOP_RELEASED:format(ns.DisplayName(ask.helper)))
end

-- Helping on our own: the guests whose time is up are asked to leave (their addon does it).
local function ReleaseGuests(now)
	for short, g in pairs(guests) do
		if g.release and not g.released and now - g.t >= Hop.GUEST_TIME then
			g.released = true
			stats.releases = stats.releases + 1
			ns.Comm.Whisper(g.name, ("LX~%d"):format(g.id))
		end
		if now - g.t >= Hop.GUEST_TIME * 3 then guests[short] = nil end
	end
end

function Hop.Tick()
	local now = ns.Now()
	if pending and now - pending.t > Hop.WAIT + 5 then pending = nil end -- the popup is long gone
	ReleaseGuests(now)
	if now - lastPromptCheck >= Hop.PROMPT_EVERY then
		lastPromptCheck = now
		Hop.CheckKingPrompt()
	end
	if not ask or ask.phase == "done" then return end
	if ask.phase == "asking" then
		if now - ask.t >= Hop.WINDOW and ask.count > 0 then
			Hop.Next()
		elseif now - ask.t >= Hop.WINDOW * 2 then
			Finish(L.HOP_NOBODY)
		end
	elseif ask.phase == "requested" or ask.phase == "accepted" then
		if now - ask.asked >= Hop.WAIT then Hop.Next() end
	elseif ask.phase == "joined" and now - ask.joined >= Hop.JOIN_WAIT then
		OfferLeave()
	end
end

---------------------------------------------------------------------------
-- The King's layer
---------------------------------------------------------------------------

function Hop.ZoneName(mapID)
	return mapID and ns.Zones and ns.Zones.NameForKey and ns.Zones.NameForKey("m" .. mapID) or "?"
end

-- The King when he is online (leader of the guild named exactly "Olympus"), and his layer
-- when his addon announced it: { name, mapID, zoneUID }. The name is the one the army calls
-- him (ns.KING_NAME); his character's is only used to find his layer.
function Hop.King()
	local now = ns.Now()
	for name, g in pairs(ns.rdb.guilds or {}) do
		if type(name) == "string" and name:lower() == "olympus" and type(g) == "table" and g.leader then
			if not (now - (g.t or 0) <= ns.Data.FRESH and g.leaderOnline) then return nil end
			local where = ns.Layers.Of(ns.FullName(g.leader, g.realm or ns.realm))
			return { name = ns.KING_NAME or ns.ShortName(g.leader), mapID = where and where.mapID, zoneUID = where and where.zoneUID }
		end
	end
	return nil
end

function Hop.AskKing()
	local k = Hop.King()
	if not k then return ns.Print(L.HOP_KING_OFFLINE) end
	if not k.zoneUID then return ns.Print(L.HOP_KING_UNKNOWN:format(k.name)) end
	if ns.Layers.CurrentMap() ~= k.mapID then return ns.Print(L.HOP_KING_ELSEWHERE:format(k.name, Hop.ZoneName(k.mapID))) end
	Hop.Ask(k.mapID, k.zoneUID, L.LAYER_OF:format(k.name))
end

-- The lines on top of the Census and the Realm while the King is online (Views.lua): the
-- button, and under it where he is when that is not our zone.
function Hop.KingLines()
	local k = Hop.King()
	if not k or (ns.King and ns.King.IsKing and ns.King.IsKing()) then return {} end
	-- The size of a title, with the crown the map shows him with.
	local crown = "|T" .. ns.CROWN_ICON .. ":0|t "
	local mine = ns.Layers.Mine()
	if k.zoneUID and mine and mine.mapID == k.mapID and mine.zoneUID == k.zoneUID then
		return { { text = crown .. "|cff40ff40" .. L.HOP_KING_HERE:format(k.name) .. "|r", color = "GameFontNormal", gapAfter = true } }
	end
	local elsewhere = k.zoneUID and ns.Layers.CurrentMap() ~= k.mapID
	local busy = ask and ask.phase ~= "done"
	local line = {
		text = crown .. "|cffffd200" .. (busy and L.HOP_KING_BUSY or L.HOP_KING_LINE):format(k.name) .. "|r",
		color = "GameFontNormal",
		gapAfter = not elsewhere,
		onClick = function() Hop.AskKing() end,
		tooltip = function(tt)
			tt:AddLine(L.HOP_KING_LINE:format(k.name), 1, 0.82, 0)
			if not k.zoneUID then
				tt:AddLine(L.HOP_KING_UNKNOWN:format(k.name), 1, 1, 1, true)
			elseif elsewhere then
				tt:AddLine(L.HOP_KING_ELSEWHERE:format(k.name, Hop.ZoneName(k.mapID)), 1, 0.6, 0.2, true)
			else
				tt:AddLine(L.HOP_KING_TIP:format(k.name), 1, 1, 1, true)
			end
			local at = ns.King and ns.King.Location and ns.King.Location()
			if at then tt:AddLine(L.HOP_KING_WHERE:format(Hop.ZoneName(at.mapID)), 0.25, 1, 0.25, true) end
		end,
	}
	if not elsewhere then return { line } end
	return { line, { text = "|cffff9933" .. L.HOP_KING_GO:format(Hop.ZoneName(k.mapID)) .. "|r", indent = 1, gapAfter = true } }
end
function Hop.KingLine() return Hop.KingLines()[1] end

-- Alone on the King's layer: may the addon invite, and later let go, the players who want to
-- come? Asked once a login (never again with the box ticked). Not asked of the King, nor of
-- players who turned helping off or already invite on their own.
function Hop.CheckKingPrompt()
	if promptShown or KingChoice() or ns.db.layerHelp == false or ns.db.layerAutoInvite then return end
	if not ns.IsMember() or (ns.King and ns.King.IsKing and ns.King.IsKing()) then return end
	if (IsInGroup and IsInGroup()) or (IsInInstance and IsInInstance()) or (InCombatLockdown and InCombatLockdown()) then return end
	local mine = ns.Layers.Mine()
	if not mine or ns.Now() - (mine.t or 0) > Hop.LAYER_FRESH or not OnKingLayer() then return end
	promptShown = true
	ns.PlayAlert("soft")
	Hop.ShowKingPrompt()
end

function Hop.ChooseKing(choice)
	kingMode = choice
	local f = Hop.prompt
	if f then
		if f.check and f.check:GetChecked() then ns.db.hopKingChoice = choice end
		f.answered = true
		f:Hide()
	end
	if choice == "auto" then ns.Print(L.HOP_KING_AUTO:format(ns.KING_NAME or "?"))
	elseif choice == "no" then ns.Print(L.HOP_KING_NO)
	else ns.Print(L.HOP_KING_MANUAL) end
	Changed()
end

local function PromptButton(f, label, choice)
	local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	b:SetHeight(22)
	b:SetText(label)
	local fs = b:GetFontString()
	local textW = fs and (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()) or 100
	b:SetWidth(math.max(120, math.ceil(textW) + 28))
	b:SetScript("OnClick", function() ns.SafeCall("hop king choice", Hop.ChooseKing, choice) end)
	return b
end

-- A window like the game's own dialogs, with three answers and "Don't ask me again".
local function MakePrompt()
	local f = CreateFrame("Frame", "OlympusKingLayerPrompt", UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetPoint("TOP", UIParent, "TOP", 0, -135)
	local okBorder, border = pcall(CreateFrame, "Frame", nil, f, "DialogBorderTemplate")
	if not okBorder or not border then
		border = f:CreateTexture(nil, "BACKGROUND")
		border:SetColorTexture(0, 0, 0, 0.85)
	end
	border:SetAllPoints()
	f.text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	f.text:SetPoint("TOP", 0, -20)
	f.text:SetJustifyH("CENTER")
	f.buttons = {
		PromptButton(f, L.HOP_KING_PROMPT_YES, "auto"),
		PromptButton(f, L.HOP_KING_PROMPT_NO, "no"),
		PromptButton(f, L.HOP_KING_PROMPT_MANUAL, "manual"),
	}
	f.check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	f.check:SetSize(24, 24)
	f.checkLabel = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	f.checkLabel:SetPoint("LEFT", f.check, "RIGHT", 2, 1)
	f.checkLabel:SetText(L.HOP_KING_PROMPT_NEVER)
	-- Escape (or anything else closing it unanswered): the usual window per request, this login.
	f:SetScript("OnHide", function(self)
		if not self.answered then kingMode = kingMode or "manual" end
	end)
	if UISpecialFrames then table.insert(UISpecialFrames, "OlympusKingLayerPrompt") end
	return f
end

function Hop.ShowKingPrompt()
	Hop.prompt = Hop.prompt or MakePrompt()
	local f = Hop.prompt
	local total = 0
	for _, b in ipairs(f.buttons) do total = total + b:GetWidth() end
	total = total + 8 * (#f.buttons - 1)
	local width = math.max(400, total + 40)
	f:SetWidth(width)
	f.text:SetWidth(width - 48)
	f.text:SetText(L.HOP_KING_PROMPT:format(ns.KING_NAME or "?", ns.KING_NAME or "?"))
	local x = (width - total) / 2
	for i, b in ipairs(f.buttons) do
		b:ClearAllPoints()
		if i == 1 then b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 18) else b:SetPoint("LEFT", f.buttons[i - 1], "RIGHT", 8, 0) end
	end
	f.check:ClearAllPoints()
	f.check:SetPoint("BOTTOMLEFT", f.buttons[1], "TOPLEFT", -4, 6)
	f.check:SetChecked(false)
	local textH = f.text.GetStringHeight and f.text:GetStringHeight() or f.text:GetHeight()
	f:SetHeight(20 + math.max(40, textH or 0) + 12 + 24 + 6 + 22 + 18)
	f.answered = false
	f:Show()
end

-- What the Realm tab's layer rows show about an ask in progress for that layer.
function Hop.State() return ask end
function Hop.Stats() return stats end

function Hop.StatusLine()
	local s = stats
	local n = 0
	for _ in pairs(guests) do n = n + 1 end
	return ("help=%s auto=%s king=%s  |  asks=%d offers=%d requests=%d invites=%d noes=%d joins=%d moves=%d releases=%d guests=%d  |  now=%s"):format(
		tostring(ns.db.layerHelp ~= false), tostring(ns.db.layerAutoInvite == true), tostring(KingChoice() or "-"),
		s.asks, s.offers, s.requests, s.invites, s.noes, s.joins, s.moves, s.releases, n, ask and ask.phase or "-")
end

-- On again also forgets the King's layer answer: the window may ask again.
function Hop.SetHelp(on)
	ns.db.layerHelp = on
	if on then
		ns.db.hopKingChoice, kingMode, promptShown = nil, nil, false
	end
	ns.Print(on and L.HOP_HELP_ON or L.HOP_HELP_OFF)
end

function Hop.SetAuto(on)
	ns.db.layerAutoInvite = on
	ns.Print(on and L.HOP_AUTO_ON or L.HOP_AUTO_OFF)
end

-- Tests start from a clean state.
function Hop.Reset()
	ask, pending, lastAsk = nil, nil, -math.huge
	kingMode, promptShown, lastPromptCheck = nil, false, -math.huge
	wipe(offered); wipe(answeredAt); wipe(recent); wipe(guests)
	for k in pairs(stats) do stats[k] = 0 end
end

ns.Comm.Handle("LQ", function(...) Hop.HandleAsk(...) end)
ns.Comm.Handle("LO", function(...) Hop.HandleOffer(...) end)
ns.Comm.Handle("LR", function(...) Hop.HandleRequest(...) end)
ns.Comm.Handle("LN", function(...) Hop.HandleNo(...) end)
ns.Comm.Handle("LX", function(...) Hop.HandleRelease(...) end)

ns.On("LAYERS_CHANGED", function() ns.SafeCall("hop layer", Hop.OnLayer) end)

ns.On("LOGIN", function()
	ns.RegisterEvent("PARTY_INVITE_REQUEST", function(name) Hop.OnInvite(name) end)
	ns.RegisterEvent("GROUP_ROSTER_UPDATE", function() Hop.OnRoster() end)
	ns.Every(1, "hop", Hop.Tick)
end)
