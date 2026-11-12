local ADDON, ns = ...
local L = ns.L

-- Layers have no name in game. Like other layer addons we read the zone UID embedded in
-- NPC GUIDs (Creature-0-server-instance-zoneUID-npc-spawn): players who see the same
-- zoneUID in the same zone share a layer. Each addon user announces its layer and rank on
-- OlympusNet, and a layer is named after the highest ranked Olympus member on it:
-- "Asmongold's layer". Experimental until tested on a live realm.
--
-- (1.5.4) WoW: Forever splits a realm group into sub-realms (CAMWOWUS2Realm1PvE, ...Realm5PvE),
-- and a layer is a copy of a zone inside one of them: the same zone UID on another sub-realm is
-- another layer, which a group invite alone does not reach (the dev, 2026-11-08: "o layer hop só
-- funciona no mesmo realm, mas tem como ir lá: precisa estar no grupo, deslogar e logar"). So on
-- Forever a layer is (zone, zone UID, sub-realm): a guildmate's word is filed under the sub-realm
-- his hello named (Comm.PeerRealm; the server stamps his word with the reader's own sub-realm,
-- never his), apart from a same-UID layer here, and shows with that sub-realm's label. A sender
-- whose sub-realm is not known counts here, as before.

local Layers = {}
ns.Layers = Layers

local ANNOUNCE_EVERY = 600
local MIN_GAP = 30
local EXPIRE = 2 * ANNOUNCE_EVERY + 60 -- a missed announce does not drop anyone
-- The King's layer goes with his crown (King.lua), which he repeats every 20 seconds: his
-- client repeats his layer about once a minute, not every ten, so a player who just logged in
-- or reloaded can ask to join him a minute later, not ten (1.0.0). One client, one message a
-- minute. (Just under the minute of the ticker below, whose seconds may come a little early.)
Layers.KING_EVERY = 55

local mine          -- { mapID, zoneUID, t }
local lastAnnounce = 0
local sentAt        -- when our layer last went out (Layers.SentAt: /oly status)
-- A layer's key under its map: the zone UID (a number) for one on our own sub-realm, and
-- "<zoneUID>@<sub-realm>" for one on another sub-realm of our Forever family (1.5.4).
local seen = {}     -- [mapID][key]["Name-Realm"] = { rank, guild, t }
local where = {}    -- ["Name-Realm"] = { mapID, key, zoneUID, realm }: each sender counts on one layer only
local lastFire, fireQueued = -math.huge, false -- LAYERS_CHANGED for the announcements (Receive)

local function LayerKey(zoneUID, realm)
	if realm then return zoneUID .. "@" .. realm end
	return zoneUID
end
-- A layer's zone UID and sub-realm (nil: ours) from its key.
local function SplitKey(key)
	if type(key) == "number" then return key, nil end
	local uid, realm = tostring(key):match("^(%d+)@(.+)$")
	return tonumber(uid) or tonumber(key), realm
end

-- (1.5.4) The sub-realm a layer word's sender plays on, when it is another of our Forever family
-- than ours: the one his last hello named (Comm.PeerRealm). nil for ours, for one not known (his
-- hello not heard yet, or an older version's that names none: counted here, as before) and off
-- Forever, where a realm group's realms share their layers and the stamp on a name is the realm.
function Layers.RealmOf(sender)
	if not ns.splitNames then return nil end
	local C = ns.Comm
	local realm = type(C) == "table" and type(C.PeerRealm) == "function" and C.PeerRealm(sender) or nil
	if type(realm) ~= "string" or realm == "" or realm == ns.realm then return nil end
	return realm
end

-- The short label a sub-realm shows with ("Realm5" for CAMWOWUS2Realm5PvE; another realm as it is).
function Layers.RealmLabel(realm)
	if type(realm) ~= "string" then return "?" end
	return realm:match("(Realm%d+)") or realm
end

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

-- Our zone and layer go out only with the player's yes (0.9.1): without a realm key the
-- Olympus channel is public. Off until they answer (ns.db.shareLocation is nil until then,
-- account-wide): no layer announcement, and the census they send names nobody's zone
-- (Comm.Broadcast). The King's is his crown on the map (the Throne) alone (0.9.2): his zone
-- and layer go out while it is on, never otherwise, whatever he answered to the question.
function Layers.Sharing()
	local K = ns.King
	if K and K.IsKing and K.IsKing() then return (K.SharingLocation and K.SharingLocation()) and true or false end
	return ns.db.shareLocation == true
end

local function Announces() return Layers.Sharing() end

-- Sharing turned off (the player's answer, the King's crown): our layer leaves every screen at
-- once (0.9.2), not when it expires. Clients before 0.9.2 keep it until then (EXPIRE).
local announced = false
function Layers.Withdraw()
	-- Quiet presence (Core.lua): nothing goes, not even this; the layer we announced expires on the
	-- other clients (EXPIRE) as after a logout.
	if not announced or (ns.QuietPresence and ns.QuietPresence()) then return end
	announced = false
	ns.Comm.Send("CHANNEL", "L0~", "layer")
end

local retryQueued = false

local function Announce(force)
	if not mine or not IsInGuild() or not Announces() then return end
	-- Quiet presence (Core.lua): our layer is not announced (nor our zone: Comm.Hello, Comm.Broadcast).
	if ns.QuietPresence and ns.QuietPresence() then return end
	local now = ns.Now()
	local K = ns.King
	local every = (K and K.IsKing and K.IsKing()) and Layers.KING_EVERY or ANNOUNCE_EVERY
	if not force and now - lastAnnounce < every then return end
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
	-- enough to see the layers and to name each one after its highest rank. (The King is an
	-- officer: his crown's layer always goes.)
	if not ns.Roster.IsOfficer() and not Layers.InSample() then return end
	ns.Comm.Send("CHANNEL", ns.Codec.EncodeLayer(mine.mapID, mine.zoneUID, ns.Roster.MyRank(), guild), "layer")
	announced, sentAt = true, now
end
function Layers.SentAt() return announced and sentAt or nil end

-- Our layer does not follow every creature: some show another server's zone UID (a zone's
-- border, creatures from another shard), and a layer that flips back and forth every second
-- would spam the channel and fool the layer hop. A new one takes over only once two different
-- creatures show it and none of ours has been seen for HOLD seconds; at once when we have none
-- or entered another zone, and when it is the layer a hop is taking us to.
Layers.HOLD = 6
Layers.EVIDENCE_WINDOW = 15 -- two distinct NPCs within this window before an automatic hop departure
local pending        -- another layer seen meanwhile: { zoneUID, guids = { [guid] = true }, n }
local function Observe(unit)
	if IsInInstance() then return end
	local guid = UnitGUID(unit)
	local zoneUID = ZoneUIDFromGUID(guid)
	local mapID = CurrentMap()
	if not zoneUID or not mapID then return end
	local now = ns.Now()
	if mine and mine.mapID == mapID and mine.zoneUID == zoneUID then
		if not mine.firstAt or now - mine.firstAt > Layers.EVIDENCE_WINDOW then
			mine.firstGUID, mine.firstAt, mine.confirmedAt = guid, now, nil
		elseif mine.firstGUID ~= guid then
			mine.confirmedAt = now
		end
		mine.t, mine.seenAt, pending = now, now, nil
		return
	end
	if mine and mine.mapID == mapID then
		local expMap, expUID
		if ns.Hop and ns.Hop.ExpectedLayer then expMap, expUID = ns.Hop.ExpectedLayer() end
		if not (expMap == mapID and expUID == zoneUID) then
			if not pending or pending.zoneUID ~= zoneUID or now - pending.t > Layers.EVIDENCE_WINDOW then
				pending = { zoneUID = zoneUID, guids = {}, n = 0, t = now }
			end
			if not pending.guids[guid] then pending.guids[guid], pending.n = true, pending.n + 1 end
			if pending.n < 2 or now - (mine.seenAt or 0) < Layers.HOLD then return end
		end
	end
	local confirmed = pending and pending.zoneUID == zoneUID and pending.n >= 2
		and now - pending.t <= Layers.EVIDENCE_WINDOW
	pending = nil
	mine = { mapID = mapID, zoneUID = zoneUID, t = now, seenAt = now,
		firstGUID = guid, firstAt = now, confirmedAt = confirmed and now or nil }
	ns.Log("layer: map %d zoneUID %d (%s)", mapID, zoneUID, tostring(unit))
	Announce(true)
	ns.Fire("LAYERS_CHANGED")
end

function Layers.Mine() return mine end
Layers.Observe = Observe -- tests
-- The King turned his crown on (King.ToggleLocation): his layer goes out now, not when the next
-- announcement is due (up to ten minutes when he had shown it before hiding it, 1.0.0).
function Layers.AnnounceNow() Announce(true) end
-- Quiet presence turned off (Core.lua): our layer at once, when we share it.
ns.On("QUIET_PRESENCE_CHANGED", function(on) if on == false then Announce(true) end end)
local asked = false -- the sharing question was put to the player this session
function Layers.Reset() mine, pending, asked = nil, nil, false; wipe(seen); wipe(where); lastFire, fireQueued = -math.huge, false; lastAnnounce, announced, sentAt = 0, false, nil end -- tests

-- The player's answer: on, our layer goes out at once; either way our guild's reporter learns
-- it from our hello (it names our zone only while we share, Comm.SharesZone).
-- privateTransition is Core's atomic entrance into quiet presence: withdraw the old layer while
-- it can still leave, but do not finish with a hello or wake broadcasters until quiet is active.
function Layers.SetSharing(on, privateTransition)
	ns.db.shareLocation = on and true or false
	ns.Print(on and L.LOCATION_ON or L.LOCATION_OFF)
	if privateTransition ~= true then ns.Comm.Hello(true) end
	if on then Announce(true) else Layers.Withdraw() end
	-- Taking donations (1.1): the zone in it follows the answer at once.
	if privateTransition ~= true and ns.Treasury and ns.Treasury.DonationsMoved then ns.Treasury.DonationsMoved() end
	if privateTransition ~= true then ns.Fire("LAYER_SHARING_CHANGED", on and true or false) end
	return true
end

function Layers.SharingState()
	local v = ns.db.shareLocation
	return v == true and "on" or (v == false and "off" or "not chosen (off)")
end

-- Asked once a session until answered: never in combat or an instance (asked later), never
-- again once answered. What goes out, and who reads it, are in the question itself.
StaticPopupDialogs["OLYMPUS_LOCATION_CHOICE"] = {
	text = L.LOCATION_ASK,
	button1 = L.LOCATION_SHARE,
	button2 = L.LOCATION_KEEP,
	OnAccept = function() ns.SafeCall("location choice", Layers.SetSharing, true) end,
	-- Keep private is a no. Pushed out by another window, or Escape: no answer, asked next login.
	OnCancel = function(_, _, reason)
		if reason == "clicked" then ns.SafeCall("location choice", Layers.SetSharing, false) end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	-- Escape (pressed for anything else too: the game's escape closes popups first) is no
	-- answer (0.9.2): asked again next session; only the buttons record a choice.
	noCancelOnEscape = true,
	preferredIndex = 3,
}

function Layers.AskChoice()
	if asked or ns.db.shareLocation ~= nil or not ns.IsMember() then return false end
	-- (The King's answer is his crown on the Throne.)
	if ns.King and ns.King.IsKing and ns.King.IsKing() then return false end
	if (InCombatLockdown and InCombatLockdown()) or (IsInInstance and IsInInstance()) then return false end
	-- 1.1 (#11): the first-open page is the first question, this one on it (once a session there);
	-- this popup only while Consent.lua is not loaded (updated without a restart).
	if ns.Consent and not ns.Consent.missing then return ns.Consent.Ask("location") == true end
	asked = true
	ns.ShowDialog("OLYMPUS_LOCATION_CHOICE", ns.Comm.Audience())
	return true
end

-- Where a player last announced their layer: { mapID, zoneUID, t, realm } while fresh, else nil
-- (realm, 1.5.4: the sub-realm of our Forever family it is on when not ours, Layers.RealmOf).
-- The census and the channel may write a name with different realms: short names match too,
-- unless `exact` (the King's: nobody else's announcement may pass for his).
function Layers.Of(name, exact)
	if type(name) ~= "string" then return nil end
	if name == ns.me then return mine end
	local short, now = ns.ShortName(name), ns.Now()
	for sender, w in pairs(where) do
		if sender == name or (not exact and ns.ShortName(sender) == short) then
			local m = seen[w[1]] and seen[w[1]][w[2]] and seen[w[1]][w[2]][sender]
			if m and now - m.t <= EXPIRE then return { mapID = w[1], zoneUID = w[3], t = m.t, realm = w[4] } end
		end
	end
	return nil
end

-- The local sub-realm only. Layer hop verifies guild membership before contacting a peer.
function Layers.HopPeers(mapID, zoneUID)
	local peers, now = {}, ns.Now()
	for name, member in pairs((seen[mapID] and seen[mapID][zoneUID]) or {}) do
		if name ~= ns.me and member.t <= now and now - member.t <= EXPIRE then
			peers[#peers + 1] = { name = name, guild = member.guild, t = member.t }
		end
	end
	table.sort(peers, function(a, b)
		if a.t ~= b.t then return a.t > b.t end
		return a.name < b.name
	end)
	return peers
end

function Layers.InSample()
	local h = 0
	for i = 1, #(ns.me or "") do h = (h * 31 + ns.me:byte(i)) % 1000003 end
	return h % 8 == 0
end

-- The King's character as Hop.King reads it: the one pinned by name (1.0.0: his own messages, on
-- whatever realm the server names), or the leader of his guild the census names.
local function FromKing(sender)
	if ns.IsKingCharacter(sender) then return true end
	for name, g in pairs(ns.KingIsMaster() and ns.rdb.guilds or {}) do -- (1.5.5: never on Forever's live realms)
		if ns.IsKingGuild(name) and type(g) == "table" and g.leader then
			local full = ns.FullName(g.leader, g.realm or ns.realm)
			if full == sender and ns.Data.KnownRank(full, name, true) == 0 then return true end
		end
	end
	return false
end

-- With thousands of users an announcement arrives every few seconds, each one a redraw of the
-- Census, the Realm and the Decrees: at once for our zone (the layers the Realm tab lists) and
-- for the King's layer (his line tops the Census), the rest at most once every FIRE_GAP.
Layers.FIRE_GAP = 5
local function FireNow()
	lastFire = ns.Now()
	ns.Fire("LAYERS_CHANGED")
end
-- The last change still to show (0.9.3): a change that comes while a fire is queued is shown
-- by it, even when an urgent fire went out in between.
local changedAt = -math.huge
local function FireSoon()
	changedAt = ns.Now()
	if fireQueued then return end
	local wait = Layers.FIRE_GAP - (ns.Now() - lastFire)
	if wait <= 0 then return FireNow() end
	fireQueued = true
	ns.After(wait, "layers changed", function()
		fireQueued = false
		if lastFire <= changedAt then FireNow() end -- (a fire since the last change showed it already)
	end)
end

function Layers.Receive(sender, l)
	if not ns.IsFederation(l.guild) then return end
	sender = ns.FullName(sender)
	-- 1.1: a name the moderators took off (net-off, Moderation.lua): no layer of theirs, and the
	-- one they announced before goes.
	if ns.Moderation.Hides and ns.Moderation.Hides(sender, l.guild) then return Layers.Forget(sender) end
	-- The King's own layer tells where he plays (1.0.0, Konig's review: Hop.King), whatever a report says.
	if ns.Hop and ns.Hop.HeardKing then ns.Hop.HeardKing(sender) end
	local old = where[sender]
	local here = CurrentMap()
	local urgent = (here and (l.mapID == here or (old and old[1] == here))) or FromKing(sender)
	if old and seen[old[1]] and seen[old[1]][old[2]] then seen[old[1]][old[2]][sender] = nil end
	-- (1.5.4) On another sub-realm of our Forever family (his hello's word): a layer of its own.
	local realm = Layers.RealmOf(sender)
	local key = LayerKey(l.zoneUID, realm)
	where[sender] = { l.mapID, key, l.zoneUID, realm }
	seen[l.mapID] = seen[l.mapID] or {}
	seen[l.mapID][key] = seen[l.mapID][key] or {}
	-- The rank written in the message is not trusted: only verified Lords and Captains
	-- (or ranks from our own roster) can give a layer its name.
	local rank = ns.Data.KnownRank(sender, l.guild) or 9
	seen[l.mapID][key][sender] = { rank = rank, guild = l.guild, t = ns.Now() }
	if urgent then FireNow() else FireSoon() end
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

-- Layers seen in a zone, each with its name, head count and whether we are on it; realm (1.5.4):
-- the sub-realm of our Forever family a layer is on when not ours (nil here), a same-UID layer
-- there apart from one here. Our own layer is always on our sub-realm.
function Layers.ForMap(mapID)
	local source = seen
	local sizes = {}
	for _, e in ipairs(ns.Data.Summary().guilds) do sizes[e.name] = e.g.total or 0 end
	local now, out = ns.Now(), {}
	for key, members in pairs(source[mapID] or {}) do
		local zoneUID, realm = SplitKey(key)
		local best, count, lastSeen = nil, 0, 0
		for name, m in pairs(members) do
			-- (1.1: never a name the moderators took off since, Moderation.lua.)
			if now - m.t <= EXPIRE and not (ns.Moderation.Hides and ns.Moderation.Hides(name, m.guild)) then
				count = count + 1
				lastSeen = math.max(lastSeen, m.t)
				local cand = { name = ns.DisplayName(name), rank = m.rank, guild = m.guild }
				if not best or Better(cand, best, sizes) then best = cand end
			end
		end
		local isMine = mine and mine.mapID == mapID and realm == nil and mine.zoneUID == zoneUID
		if isMine then
			count = count + 1
			lastSeen = math.max(lastSeen, mine.t or 0)
			local me = { name = ns.DisplayName(ns.me), rank = ns.Roster.MyRank(), guild = GetGuildInfo("player") or "" }
			if not best or Better(me, best, sizes) then best = me end
		end
		if count > 0 then
			out[#out + 1] = { zoneUID = zoneUID, realm = realm, count = count, head = best, mine = isMine, lastSeen = lastSeen }
		end
	end
	if mine and mine.mapID == mapID and not (source[mapID] and source[mapID][mine.zoneUID]) then
		out[#out + 1] = {
			zoneUID = mine.zoneUID, count = 1, mine = true, lastSeen = mine.t,
			head = { name = ns.DisplayName(ns.me), rank = ns.Roster.MyRank(), guild = GetGuildInfo("player") or "" },
		}
	end
	table.sort(out, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		if a.zoneUID ~= b.zoneUID then return a.zoneUID < b.zoneUID end
		-- (The same UID here and on another sub-realm: ours first, then by the sub-realm's name.)
		if (a.realm == nil) ~= (b.realm == nil) then return a.realm == nil end
		return (a.realm or "") < (b.realm or "")
	end)
	return out
end

-- A zone-only observation count for officer musters, not a census or a list of names. ForMap
-- intentionally shows our own layer even while private; that local exception is never counted
-- here without sharing consent. Remote records are only the existing opt-in L1 observations.
function Layers.CountSharedInZone(mapID)
	local now, count, counted = ns.Now(), 0, {}
	local ownKey = ns.Fold(ns.FullName(ns.me) or "")
	local group = ns.group or ns.GroupOf(ns.realm)
	for _, members in pairs(seen[mapID] or {}) do
		for name, m in pairs(members) do
			local key = ns.Fold(name)
			if key ~= ownKey and not counted[key] and now >= m.t and now - m.t <= EXPIRE
				and ns.GroupOf(ns.RealmOf(name) or ns.realm) == group
				and not (ns.Moderation.Hides and ns.Moderation.Hides(name, m.guild)) then
				counted[key], count = true, count + 1
			end
		end
	end
	if Layers.Sharing() and mine and mine.mapID == mapID and now >= mine.t and now - mine.t <= EXPIRE
		and ns.GroupOf(ns.RealmOf(ns.me) or ns.realm) == group then
		count = count + 1
	end
	return count
end

-- A layer's name; one on another sub-realm (1.5.4) with that sub-realm's label after it,
-- "Someone's layer [Realm5]", wherever the name shows (the Realm tab, /oly hop list, the ask).
function Layers.Name(layer)
	if not layer or not layer.head then return L.LAYER_UNKNOWN end
	local name = L.LAYER_OF:format(layer.head.name)
	if layer.realm then return name .. " [" .. Layers.RealmLabel(layer.realm) .. "]" end
	return name
end

function Layers.CurrentMap() return CurrentMap() end

-- A sender that stopped sharing: gone from every layer at once (0.9.2). Their own word about
-- themselves only: the sender name is the server's.
function Layers.Forget(sender)
	sender = ns.FullName(sender)
	local old = where[sender]
	if not old then return end
	where[sender] = nil
	if seen[old[1]] and seen[old[1]][old[2]] then seen[old[1]][old[2]][sender] = nil end
	FireNow()
end
ns.Comm.Handle("L0", function(dist, sender) if dist == "CHANNEL" then Layers.Forget(sender) end end)

ns.Comm.Handle("L1", function(dist, sender, text)
	if dist ~= "CHANNEL" then return end
	local l = ns.Codec.DecodeLayer(text)
	if l then Layers.Receive(sender, l) end
end)

-- Every minute: layers nobody repeated leave, ours goes out again when due (the King's every
-- minute while his crown shows, anyone else's every ten), and the sharing question is asked
-- when it can be.
function Layers.Tick()
	Prune()
	Announce(false)
	Layers.AskChoice()
end

ns.On("LOGIN", function()
	ns.RegisterEvent("PLAYER_TARGET_CHANGED", function() Observe("target") end)
	ns.RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() Observe("mouseover") end)
	ns.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(unit) Observe(unit) end)
	ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function() mine, pending = nil, nil; ns.Fire("LAYERS_CHANGED") end)
	ns.Every(60, "layer announce", Layers.Tick)
	-- Once the login settled (our officers hand out the realm key in the first seconds, and
	-- the question names the channel's state); then on the minute until it could be asked.
	ns.After(45, "location choice", Layers.AskChoice)
end)
