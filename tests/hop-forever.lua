-- The layer hop on WoW: Forever, where an addon's channel words are never delivered and every
-- channel word goes by a relay (Relay.lua): the real Comm.lua, Relay.lua and Hop.lua, with the
-- measured Forever facts (the server stamps each sender with the reader's own sub-realm, the guild
-- roster names every member bare).
local ns, test, eq, extra = ...

-- (1.5.4: the relog step's tests stub the group and the party's names too, and Hop.lua's load
-- writes every one of its dialogs into the game's table: all of them kept.)
local GLOBALS = { "GetChannelName", "GetGuildInfo", "IsInGuild", "IsInGroup", "IsInRaid", "GetNumGroupMembers",
	"UnitFullName", "GetUnitName", "UnitName", "UnitIsGroupLeader", "UnitIsGroupAssistant", "C_PartyInfo", "AcceptGroup",
	"StaticPopup_Show", "StaticPopup_Hide", "StaticPopup_FindVisible", "InCombatLockdown", "IsInInstance" }
local DIALOGS = { "OLYMPUS_HOP_REQUEST", "OLYMPUS_HOP_REQUEST_RELOG", "OLYMPUS_HOP_REQUEST_SISTER", "OLYMPUS_HOP_LEAVE", "OLYMPUS_HOP_CONFIRM", "OLYMPUS_HOP_RELOG" }
local function Saved()
	local s = { member = ns.IsMember, realm = ns.realm, globals = {}, dialogs = {} }
	for _, g in ipairs(GLOBALS) do s.globals[g] = _G[g] end
	for _, d in ipairs(DIALOGS) do s.dialogs[d] = StaticPopupDialogs[d] end
	return s
end
local function Restore(s)
	ns.IsMember, ns.realm = s.member, s.realm
	for _, g in ipairs(GLOBALS) do _G[g] = s.globals[g] end
	for _, d in ipairs(DIALOGS) do StaticPopupDialogs[d] = s.dialogs[d] end
	C_ChatInfo = nil
end

-- Each relay world points the game's send API at its own list (RelayWorld): back to this one.
local function Bind(sent)
	C_ChatInfo.SendAddonMessage = function(_, msg, dist, target) sent[#sent + 1] = { msg = msg, dist = dist, target = target, logged = false } return 0 end
	C_ChatInfo.SendAddonMessageLogged = function(_, msg, dist, target) sent[#sent + 1] = { msg = msg, dist = dist, target = target, logged = true } return 0 end
end

-- Hop.lua in a relay world's namespace, its surroundings stubbed as tests/hop.lua does.
-- w.db (1.5.4): the saved variables to load with (a relog's), else fresh ones; w.realms: the sub-realm
-- each guildmate's hello named, by his short name (Layers.RealmOf, stubbed), ours or unknown when
-- absent; w.layers: what Layers.ForMap lists; w.confirm: keep the experimental hop's first-ask window
-- (every other test here is of what follows it).
local function LoadHop(cns, w)
	w.printed, w.byName, w.popups, w.hidden = {}, {}, {}, {}
	w.realms = w.realms or {}
	cns.db = w.db or { layerHelp = true, blocked = {} }
	cns.L = ns.L
	cns.Print = function(msg) w.printed[#w.printed + 1] = tostring(msg) end
	cns.Fire, cns.Log, cns.PlayAlert = function() end, function() end, function() end
	cns.ShowDialog = function(which, a, b, data) w.popups[#w.popups + 1] = { name = which, arg = a, data = data } end
	cns.HideDialog = function(which) w.hidden[#w.hidden + 1] = which end
	cns.SafeCall = function(label, f, ...) local ok, why = pcall(f, ...) if not ok then error(label .. ": " .. tostring(why)) end end
	cns.Alert = function(_, _, alert) if alert.open() then alert.show() end end
	cns.GamepadUI = function() return false end
	cns.QuietPresence = function() return w.quiet == true end
	cns.Moderation = { Blocks = function() return false end, Hides = function() return nil end,
		SelfOff = function() return nil end, GuildOf = function() return nil end }
	cns.Roster = { RankOf = function(name) return w.byName[ns.FullName(name)] end, MyRank = function() return 3 end,
		IsOfficer = function() return false end }
	cns.Layers = { CurrentMap = function() return 1453 end, Sharing = function() return true end,
		ForMap = function() return w.layers or {} end, EVIDENCE_WINDOW = 15,
		Mine = function() return { mapID = 1453, zoneUID = w.zoneUID or 7, t = cns.clock, confirmedAt = cns.clock } end,
		RealmOf = function(name) return w.realms[ns.ShortName(ns.FullName(name))] end,
		RealmLabel = function(realm) return type(realm) == "string" and (realm:match("(Realm%d+)") or realm) or "?" end,
		Name = function(layer) return ns.L.LAYER_OF:format(layer.head and layer.head.name or "?") .. (layer.realm and (" [" .. layer.realm:match("(Realm%d+)") .. "]") or "") end }
	cns.Data = { Summary = function() return { guilds = {} } end }
	assert(loadfile(extra.addon .. "Hop.lua"))("Olympus", cns)
	cns.Hop.after = function(_, _, fn) fn() end
	cns.Hop.random = function(a) if a then return 1 end return 0 end
	if not w.confirm and cns.Hop.confirmed then cns.Hop.confirmed.same, cns.Hop.confirmed.other = true, true end
end

-- The game's group as the relog step reads it: w.group members, party1.. named in w.party.
local function StubGroup(w)
	IsInGroup = function() return (w.group or 0) > 0 end
	IsInRaid = function() return false end
	GetNumGroupMembers = function() return w.group or 0 end
	UnitIsGroupLeader, UnitIsGroupAssistant = function() return false end, function() return false end
	UnitFullName = function(unit)
		if unit == "player" then return "Asker", "Name" end
		local name = w.party and w.party[unit]
		if name then return name, nil end
	end
	GetUnitName = function(unit) return w.party and w.party[unit] end
	UnitName = GetUnitName
	InCombatLockdown, IsInInstance = function() return false end, function() return false end
	w.accepted, w.left, w.invited = 0, 0, {}
	AcceptGroup = function() w.accepted = w.accepted + 1 end
	C_PartyInfo = { InviteUnit = function(name) w.invited[#w.invited + 1] = name end, LeaveParty = function() w.left = w.left + 1 end }
	StaticPopup_Show, StaticPopup_Hide, StaticPopup_FindVisible = function() end, function() end, function() return nil end
end

local function Printed(w, text)
	for _, line in ipairs(w.printed) do if line:find(text, 1, true) then return true end end
	return false
end
local function Popups(w, name)
	local n = 0
	for _, p in ipairs(w.popups) do if p.name == name then n = n + 1 end end
	return n
end
-- A saved-variables round trip: plain data alone, in a new table (what a restart or a /reload gives back).
local function Reloaded(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do
		assert(type(v) == "string" or type(v) == "number" or type(v) == "boolean" or type(v) == "table", "saved variables hold plain data")
		out[k] = Reloaded(v)
	end
	return out
end

local REALM5, REALM1 = "CAMWOWUS2Realm5PvE", "CAMWOWUS2Realm1PvE"

-- The asker's world on REALM5, asked for the layer `realm` names (nil: one here), the helper's offer
-- taken, his request sent and his invite accepted: ready for the group.
local function Asked(realm)
	ns.realm = REALM5
	local O, odeliver, osent, _, opump, osentOf = extra.RelayWorld("Asker Name-" .. REALM5, "Olympus II")
	local w = { realms = { ["Helper One"] = realm }, party = {}, group = 0 }
	LoadHop(O, w)
	StubGroup(w)
	w.byName["Helper One-" .. REALM5], w.byName["Near Mate-" .. REALM5] = 3, 3
	O.Hop.Ask(1453, 9, "Layer of someone", realm)
	opump()
	local rg = osentOf("RG~P~Asker Name~LQ~")
	eq(#rg, 1, "the ask goes to the guild")
	local id = O.Hop.State().id
	odeliver("WHISPER", "Helper One", ("LO~%d~0~0"):format(id))
	eq(O.Hop.State().count, 1, "the helper's offer is taken")
	O.clock = O.clock + O.Hop.WINDOW
	O.Hop.Tick()
	opump()
	eq(#osentOf("LR~"), 1, "his invite asked for")
	O.Hop.OnInvite("Helper One")
	eq(w.accepted, 1, "a guildmate's invite is accepted for the player")
	return O, w, odeliver, osent, opump, osentOf
end

test("Forever layer hop: the ask goes to the asker's own guild at once over GUILD, by his plain name, and to no relay; a 1.5.3 guildmate on another sub-realm offers by whisper", function()
	local s = Saved()
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end -- (Forever: the channel delivers nothing; the relay carries it)
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		IsInGroup, IsInRaid = function() return false end, function() return false end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		-- The asker, on one sub-realm.
		ns.realm = "CAMWOWUS2Realm5PvE"
		local O, odeliver, osent, _, opump, osentOf = extra.RelayWorld("Asker Name-CAMWOWUS2Realm5PvE", "Olympus II")
		local ow = {}
		LoadHop(O, ow)
		ow.byName["Helper One-CAMWOWUS2Realm5PvE"] = 3
		O.Hop.Ask(1453, 9, "Layer of someone")
		opump()
		local rg = osentOf("RG~")
		eq(#rg, 1, "the ask goes to the guild at once")
		eq(rg[1].dist, "GUILD"); eq(rg[1].msg, ("RG~P~Asker Name~LQ~%d~1453~9"):format(O.Hop.State().id))
		eq(#osentOf("RL~"), 0, "no relay pinged, nothing whispered to one")
		eq(O.Relay.Stats().pending, 0, "nothing held for a relay")
		eq(O.Hop.State().phase, "asking", "the offers' window starts once the guild copy left")
		-- The helper, a guildmate on another sub-realm, with 1.5.3's Hop.lua and Relay.lua: the server
		-- names the asker bare, and the roster files him under the helper's own sub-realm.
		ns.realm = "CAMWOWUS2Realm1PvE"
		local H, hdeliver, _, _, hpump, hsentOf = extra.RelayWorld("Helper One-CAMWOWUS2Realm1PvE", "Olympus II")
		local hw = {}
		LoadHop(H, hw)
		hw.zoneUID = 9
		hw.byName["Asker Name-CAMWOWUS2Realm1PvE"] = 3
		hdeliver("GUILD", "Asker Name", rg[1].msg)
		hpump()
		local lo = hsentOf("LO~")
		eq(#lo, 1, "the guildmate on the asked layer offers"); eq(lo[1].dist, "WHISPER"); eq(lo[1].target, "Asker Name")
		-- Back at the asker: the offer is a guildmate's, and his request goes to him by whisper.
		ns.realm = "CAMWOWUS2Realm5PvE"
		Bind(osent)
		odeliver("WHISPER", "Helper One", lo[1].msg)
		eq(O.Hop.State().count, 1, "the offer is taken")
		O.clock = O.clock + O.Hop.WINDOW
		O.Hop.Tick()
		opump()
		local lr = osentOf("LR~")
		eq(#lr, 1); eq(lr[1].target, "Helper One"); eq(lr[1].dist, "WHISPER")
		eq(#osentOf("RL~"), 0, "the whole hop used no relay")
	end)
	Restore(s)
	if not ok then error(err, 0) end
end)

test("Forever layer hop: the King-sighting query goes to the guild alone, a layer word to the guild at once and still to the relay; a word that is no hop's goes by the relay alone, as before", function()
	local s = Saved()
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		ns.realm = "CAMWOWUS2Realm5PvE"
		local O, odeliver, osent, _, opump, osentOf = extra.RelayWorld("Asker Name-CAMWOWUS2Realm5PvE", "Olympus II")
		eq(O.Comm.Send("CHANNEL", "LY~Q~1~4~77~1453"), true)
		opump()
		eq(#osentOf("RG~P~Asker Name~LY~Q~1~4~77~1453"), 1, "the sighting query to the guild")
		eq(O.Relay.Stats().pending, 0, "and not held for a relay")
		eq(O.Comm.Send("CHANNEL", "L1~1453~7~3~Olympus II", "layer"), true)
		opump()
		local rg = osentOf("RG~P~Asker Name~L1~")
		eq(#rg, 1, "the layer to the guild at once"); eq(rg[1].dist, "GUILD")
		eq(O.Relay.Stats().pending, 1, "and held for the relay, as before")
		odeliver("WHISPER", "Max Ran", "RY~")
		opump()
		eq(#osentOf("RL~P~L1~1453~7~3~Olympus II"), 1, "then to the relay")
		eq(#osentOf("RG~P~Asker Name~L1~"), 1, "the guild no second time")
		wipe(osent)
		eq(O.Comm.Send("CHANNEL", "X1~census"), true)
		opump()
		eq(#osentOf("RG~"), 0, "any other word: the relay alone")
		eq(#osentOf("RL~P~X1~census"), 1)
	end)
	Restore(s)
	if not ok then error(err, 0) end
end)

test("Forever layer hop: quiet presence or net-off turned on while the guild copy waits keeps it home; a guarded ask whose guard fails is not sent", function()
	local s = Saved()
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		ns.realm = "CAMWOWUS2Realm5PvE"
		local O, _, osent, _, opump, osentOf = extra.RelayWorld("Asker Name-CAMWOWUS2Realm5PvE", "Olympus II")
		local quiet, blocked = false, false
		O.QuietPresence = function() return quiet end
		O.Moderation = { Blocks = function(msg) return blocked and msg:find("^L1~") ~= nil end }
		eq(O.Comm.Send("CHANNEL", "L1~1453~7~3~Olympus II", "layer"), true)
		quiet = true
		opump()
		eq(#osentOf("RG~"), 0, "quiet presence since: the layer stays home")
		quiet = false
		eq(O.Comm.Send("CHANNEL", "L1~1453~8~3~Olympus II", "layer"), true)
		blocked = true
		opump()
		eq(#osentOf("RG~"), 0, "net-off since: the layer stays home")
		blocked = false
		local allowed, told = false, nil
		eq(O.Comm.Send("CHANNEL", "LQ~3~1453~9", nil, true, nil, function(sent) told = sent end,
			{ owner = "ask", guard = function() return allowed end }), true)
		opump()
		eq(#osentOf("RG~P~Asker Name~LQ~"), 0, "the ask's own guard refused it at the send")
		eq(told, false, "and its sender is told")
	end)
	Restore(s)
	if not ok then error(err, 0) end
end)

-- Layers.lua in a relay world's namespace, on the Forever family: what a guildmate counts.
local function LoadLayers(W)
	W.group = "ForeverPvE"
	W.IsFederation = function(g) return type(g) == "string" and g:find("Olympus", 1, true) ~= nil end
	W.Moderation = { Hides = function() return nil end, Blocks = function() return false end }
	W.Hop = { HeardKing = function() end }
	W.Fire = function() end
	assert(loadfile(extra.addon .. "Layers.lua"))("Olympus", W)
end

test("Forever layer hop: sister-guild fallback is bounded, scoped and requires both players to confirm", function()
	local s = Saved()
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		IsInGuild = function() return true end
		ns.IsMember = function() return true end
		ns.realm = REALM5
		local asker, helper = "Asker Name-" .. REALM5, "Helper One-" .. REALM5
		local ow, hw = {}, { zoneUID = 9 }
		local O, odeliver, osent, _, opump, osentOf = extra.RelayWorld(asker, "Olympus II")
		O.faction = "Alliance"
		LoadLayers(O)
		local realLayers = O.Layers
		LoadHop(O, ow)
		local hopLayers = O.Layers
		O.Layers = realLayers
		for _, k in ipairs({ "Mine", "CurrentMap", "Sharing", "RealmOf" }) do O.Layers[k] = hopLayers[k] end
		O.Data.KnownRank = function() return nil end
		local peerGuild, verified = {}, {}
		O.Moderation.GuildOf = function(name) return peerGuild[name] end
		O.Channels = { VerifiedLevel = function(name, _, readOnly)
			eq(readOnly, true, "no guild binding is created by an ask")
			return 1, verified[name] == true
		end }
		StubGroup(ow)
		local function Observe(name, guild, valid, zoneUID)
			peerGuild[name], verified[name] = guild, valid
			O.Layers.Receive(name, { mapID = 1453, zoneUID = zoneUID or 9, guild = guild })
		end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		Observe("Stale Peer-" .. REALM5, "Olympus III", true)
		O.clock = O.clock + 1300
		Observe("Own Guild-" .. REALM5, "Olympus II", true)
		Observe("Unverified Peer-" .. REALM5, "Olympus III", false)
		ow.realms["Other Realm"] = REALM1
		Observe("Other Realm-" .. REALM5, "Olympus III", true)
		Observe("Other Layer-" .. REALM5, "Olympus III", true, 42)
		Observe("Changed Layer-" .. REALM5, "Olympus III", true)
		Observe(helper, "Olympus III", true)
		Observe("Spare One-" .. REALM5, "Olympus III", true)
		Observe("Spare Two-" .. REALM5, "Olympus III", true)
		Bind(osent)
		O.Hop.Ask(1453, 9, "Another layer")
		opump()
		eq(#osentOf("RG~P~Asker Name~LQ~"), 1)
		eq(#osentOf("LQ~"), 0, "only the asker's guild is asked first")
		local id = O.Hop.State().id
		O.clock = O.clock + O.Hop.NOBODY
		O.Hop.Tick()
		Observe("Changed Layer-" .. REALM5, "Olympus III", true, 42)
		opump()
		local lq = osentOf("LQ~")
		eq(#lq, 2, "at most three queued asks, one now on another layer stays home")
		eq(lq[1].dist, "WHISPER"); eq(lq[1].target, "Helper One")
		eq(lq[1].msg, ("LQ~%d~1453~9~%s~%s"):format(id, O.faction, REALM5))
		eq(lq[2].target, "Spare One")
		eq(#osentOf("RL~"), 0, "no new relay fanout")
		local H, hdeliver, hsent, _, hpump, hsentOf = extra.RelayWorld(helper, "Olympus III")
		H.faction = "Alliance"
		LoadHop(H, hw)
		hw.sharing = true
		H.Layers.Sharing = function() return hw.sharing end
		H.Moderation.GuildOf = function(name) return name == asker and "Olympus II" or nil end
		local recognized = false
		H.Channels = { VerifiedLevel = function(name) return 1, recognized and name == asker end }
		H.Hop.Trusted = function() return true end
		H.db.layerAutoInvite = true
		GetGuildInfo = function() return "Olympus III", "Member", 3 end
		StubGroup(hw)
		hdeliver("WHISPER", "Asker Name", lq[1].msg)
		recognized = true
		hdeliver("WHISPER", "Asker Name", lq[1].msg:gsub(REALM5, REALM1))
		hw.sharing = false
		hdeliver("WHISPER", "Asker Name", lq[1].msg)
		hpump()
		eq(#hsentOf("LO~"), 0, "unknown members, wrong realms and private helpers do not offer")
		hw.sharing = true
		hdeliver("WHISPER", "Asker Name", lq[1].msg)
		hpump()
		local lo = hsentOf("LO~")
		eq(#lo, 1); eq(lo[1].target, "Asker Name")
		eq(H.Hop.Crowd(1453, 9, H.clock), 0, "direct fallback is not a public crowd signal")
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		Bind(osent)
		odeliver("WHISPER", "Spare Two", lo[1].msg)
		eq(O.Hop.State().count, 0, "an unasked peer cannot volunteer for the private fallback")
		odeliver("WHISPER", "Helper One", lo[1].msg)
		eq(O.Hop.State().count, 1)
		O.clock = O.clock + O.Hop.WINDOW
		O.Hop.Tick()
		opump()
		local lr = osentOf("LR~")
		eq(#lr, 1); eq(lr[1].target, "Helper One")
		GetGuildInfo = function() return "Olympus III", "Member", 3 end
		Bind(hsent)
		hdeliver("WHISPER", "Asker Name", lr[1].msg)
		eq(#hw.invited, 0, "even a trusted requester needs manual confirmation in a sister guild")
		eq(Popups(hw, "OLYMPUS_HOP_REQUEST_SISTER"), 1)
		local dialog = StaticPopupDialogs.OLYMPUS_HOP_REQUEST_SISTER
		eq(dialog.button3, nil, "no Always invite shortcut")
		dialog.OnAccept(nil, hw.popups[#hw.popups].data)
		eq(#hw.invited, 1)
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		StubGroup(ow)
		O.Hop.Trusted = function() return true end
		O.Hop.OnInvite("Helper One")
		eq(ow.accepted, 0, "the requester still answers Blizzard's invite")
		O.Hop.Cancel()
		O.clock = O.clock + O.Hop.ASK_GAP
		O.Hop.Ask(1453, 9, "A layer in another realm", REALM1)
		opump()
		O.clock = O.clock + O.Hop.NOBODY
		O.Hop.Tick()
		opump()
		eq(#osentOf("LQ~"), 2, "cross-sub-realm requests stay guild-only")
	end)
	Restore(s)
	if not ok then error(err, 0) end
end)

-- The players a world counts on the layer the word below names (Layers.ForMap) and its muster
-- head count there (Layers.CountSharedInZone).
local LAYER = "L1~1453~7~3~Olympus II"
local function Counted(W)
	local n = 0
	for _, layer in ipairs(W.Layers.ForMap(1453)) do if layer.zoneUID == 7 then n = layer.count end end
	return n, W.Layers.CountSharedInZone(1453)
end

-- The review of the 1.5.4 candidate: a layer word (L1, L0: Relay.GUILD_TOO) reaches the origin's
-- guildmates as his own copy over GUILD, naming him plain, and as the relay's copy, which the relay's
-- client stamps with its own sub-realm. Every guildmate off the relay's sub-realm counted him twice,
-- and a reporter handed the relay's copy to the guild again. Fails before. (The same review, mixed
-- versions: the relay's copy names him plain on the wire too, as his own copy does. A 1.5.3 client
-- keys Seen and Layers by the name as written, so the two copies agreeing is what keeps it from
-- counting him twice; the test after this one runs one. Fails before on the wire's name.)
test("Forever layer hop: a layer word heard as the origin's guild copy and as the relay's copy counts him once, at the reporter and at guildmates on a third sub-realm, either copy first; a reporter that had the guild copy hands the relay's to nobody", function()
	local s = Saved()
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		-- The origin, on Realm5: his layer to his guild at once, then to the relay once it answers.
		ns.realm = "CAMWOWUS2Realm5PvE"
		local O, odeliver, _, _, opump, osentOf = extra.RelayWorld("Asker Name-CAMWOWUS2Realm5PvE", "Olympus II")
		eq(O.Comm.Send("CHANNEL", LAYER, "layer"), true)
		opump()
		odeliver("WHISPER", "Max Ran", "RY~")
		opump()
		local guildCopy, rl = osentOf("RG~P~Asker Name~L1~")[1], osentOf("RL~P~L1~")[1]
		assert(guildCopy and rl and rl.target == "Max Ran", "the guild copy, and the relay's")
		-- The relay, Max Ran, on Realm3 in another guild, with Olympus II's reporter registered.
		ns.realm = "CAMWOWUS2Realm3PvE"
		local X, xdeliver, _, _, xpump, xsentOf = extra.RelayWorld("Max Ran-CAMWOWUS2Realm3PvE", "Olympus Zeus")
		xdeliver("WHISPER", "Rep Orter", "RL~P~RR~Olympus II")
		xdeliver("WHISPER", "Asker Name", rl.msg)
		xpump()
		local rm = xsentOf("RM~")[1]
		eq(rm and rm.msg, "RM~P~Asker Name~" .. LAYER, "the relay's copy names him plain, as his own guild copy does")
		-- The reporter, on Realm7, has the guild copy first: one player, and the relay's copy to nobody.
		ns.realm = "CAMWOWUS2Realm7PvE"
		local R, rdeliver, _, _, rpump, rsentOf = extra.RelayWorld("Rep Orter-CAMWOWUS2Realm7PvE", "Olympus II")
		LoadLayers(R)
		rdeliver("GUILD", "Asker Name", guildCopy.msg)
		rdeliver("WHISPER", "Max Ran", rm.msg)
		rpump()
		eq(#rsentOf("RG~"), 0, "the reporter had the guild copy: no second hand-over to the guild")
		local n, muster = Counted(R)
		eq(n, 1, "the reporter counts him once"); eq(muster, 1, "and musters him once")
		-- Had the relay's copy reached the reporter first, he hands it to the guild once, as before,
		-- and the guild copy after it counts nobody more.
		local R2, r2deliver, _, _, r2pump, r2sentOf = extra.RelayWorld("Rep Orter-CAMWOWUS2Realm7PvE", "Olympus II")
		LoadLayers(R2)
		r2deliver("WHISPER", "Max Ran", rm.msg)
		r2deliver("GUILD", "Asker Name", guildCopy.msg)
		r2pump()
		local handed = r2sentOf("RG~")
		eq(#handed, 1, "the relay's copy handed to the guild once")
		eq(handed[1].msg, "RG~P~Asker Name~" .. LAYER, "handed on by the name on the wire: plain")
		n, muster = Counted(R2)
		eq(n, 1, "relay's copy first: counted once"); eq(muster, 1)
		-- Guildmates on a third sub-realm hear his guild copy and the reporter's, either first: once.
		ns.realm = "CAMWOWUS2Realm1PvE"
		for _, guildFirst in ipairs({ true, false }) do
			local B, bdeliver = extra.RelayWorld("Bee Mate-CAMWOWUS2Realm1PvE", "Olympus II")
			LoadLayers(B)
			local copies = { { "Asker Name", guildCopy.msg }, { "Rep Orter", handed[1].msg } }
			if not guildFirst then copies[1], copies[2] = copies[2], copies[1] end
			for _, copy in ipairs(copies) do bdeliver("GUILD", copy[1], copy[2]) end
			local which = guildFirst and "his guild copy first" or "the reporter's copy first"
			n, muster = Counted(B)
			eq(n, 1, which .. ": a guildmate on a third sub-realm counts him once")
			eq(muster, 1, which .. ": and musters him once")
		end
	end)
	Restore(s)
	if not ok then error(err, 0) end
end)

-- The review of the 1.5.4 candidate, mixed versions: most players run 1.5.3 for days after the
-- release, and a 1.5.3 client (tests/fixtures/relay-1.5.3.lua, its own Relay.lua on this Comm and
-- Layers, which 1.5.3 shares) takes a word once by the origin's name as written, with no dedupe by
-- the short name. So the relay's copy of a layer word must name him as his own guild copy does, plain:
-- stamped with the relay's sub-realm it was a second member of the layer at every 1.5.3 guildmate on
-- another sub-realm, renewed with each L1, and a 1.5.3 reporter handed it to the guild after the
-- origin's own. Fails before (the reporter hands the stamped copy on, the guildmate counts two).
test("Forever layer hop: a 1.5.4 relay on another sub-realm, a 1.5.3 reporter and a 1.5.3 guildmate running their own Relay.lua: the member counts once at the 1.5.3 guildmate, either copy first", function()
	local s = Saved()
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local OLD = extra.fixtures .. "relay-1.5.3.lua"
		-- The origin, on Realm5, on 1.5.4: his layer to his guild at once, then to the relay once it answers.
		ns.realm = "CAMWOWUS2Realm5PvE"
		local O, odeliver, _, _, opump, osentOf = extra.RelayWorld("Lay Erman-CAMWOWUS2Realm5PvE", "Olympus II")
		eq(O.Comm.Send("CHANNEL", LAYER, "layer"), true)
		opump()
		odeliver("WHISPER", "Max Ran", "RY~")
		opump()
		local guildCopy, rl = osentOf("RG~P~Lay Erman~L1~")[1], osentOf("RL~P~L1~")[1]
		assert(guildCopy and rl and rl.target == "Max Ran", "the guild copy, and the relay's")
		-- The relay, Max Ran, on Realm7 in another guild, on 1.5.4, with Olympus II's reporter registered.
		ns.realm = "CAMWOWUS2Realm7PvE"
		local X, xdeliver, _, _, xpump, xsentOf = extra.RelayWorld("Max Ran-CAMWOWUS2Realm7PvE", "Olympus Zeus")
		xdeliver("WHISPER", "Rep Orter", "RL~P~RR~Olympus II")
		xdeliver("WHISPER", "Lay Erman", rl.msg)
		xpump()
		local rm = xsentOf("RM~")[1]
		assert(rm and rm.target == "Rep Orter", "the relay's copy to the guild's reporter")
		eq(X.Relay.Stats().delivered, 1, "the relay's own client took the word once")
		-- The reporter and the guildmates, on Realm5 with the origin, still on 1.5.3.
		ns.realm = "CAMWOWUS2Realm5PvE"
		for _, guildFirst in ipairs({ true, false }) do
			local which = guildFirst and "the guild copy first" or "the relay's copy first"
			local R, rdeliver, _, _, rpump, rsentOf = extra.RelayWorld("Rep Orter-CAMWOWUS2Realm5PvE", "Olympus II", OLD)
			local copies = { { "GUILD", "Lay Erman", guildCopy.msg }, { "WHISPER", "Max Ran", rm.msg } }
			if not guildFirst then copies[1], copies[2] = copies[2], copies[1] end
			for _, copy in ipairs(copies) do rdeliver(copy[1], copy[2], copy[3]) end
			rpump()
			local handed = rsentOf("RG~")
			-- A 1.5.3 guildmate hears the origin's own copy and whatever his reporter handed on.
			local G, gdeliver = extra.RelayWorld("Gil Mate-CAMWOWUS2Realm5PvE", "Olympus II", OLD)
			LoadLayers(G)
			gdeliver("GUILD", "Lay Erman", guildCopy.msg)
			for _, h in ipairs(handed) do gdeliver("GUILD", "Rep Orter", h.msg) end
			local n, muster = Counted(G)
			eq(n, 1, which .. ": a 1.5.3 guildmate counts him once")
			eq(muster, 1, which .. ": and musters him once")
			eq(G.Relay.Stats().delivered, 1, which .. ": the 1.5.3 guildmate took the word once")
			eq(#handed, guildFirst and 0 or 1, which .. ": the 1.5.3 reporter hands the relay's copy on only when it came first")
			eq(R.Relay.Stats().delivered, 1, which .. ": the 1.5.3 reporter took the word once")
		end
	end)
	Restore(s)
	if not ok then error(err, 0) end
end)

test("Forever layer hop: a relay in the origin's guild, its own guild's reporter, that had the guild copy hands the relay's copy to nobody and (1.5.5) keeps it on its island: another client's layer word crosses to no relay", function()
	local s = Saved()
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		ns.realm = "CAMWOWUS2Realm3PvE"
		local X, xdeliver, xsent, _, xpump, xsentOf = extra.RelayWorld("Max Ran-CAMWOWUS2Realm3PvE", "Olympus II")
		LoadLayers(X)
		xdeliver("WHISPER", "Hildryn Payne", "RY~") -- (the other relay answered...)
		xdeliver("WHISPER", "Hildryn Payne", "RJ~1~0~0") -- (...and joined the mesh: what crosses goes to it)
		X.Relay.HandleIn("WHISPER", X.me, "RL~P~RR~Olympus II") -- (its own client is its guild's reporter)
		xpump()
		eq(X.Relay.Stats().reporters, 1)
		wipe(xsent)
		xdeliver("GUILD", "Asker Name", "RG~P~Asker Name~" .. LAYER)
		xdeliver("WHISPER", "Asker Name", "RL~P~" .. LAYER)
		xpump()
		eq(#xsentOf("RG~"), 0, "no second hand-over to the guild")
		-- (1.5.5) Only a closed set crosses (tests/relay-mesh.lua): a client's layer word reaches its own
		-- guild over GUILD and this relay's guilds; the other relays' guilds have no use for it.
		eq(#xsentOf("RX~"), 0, "not across")
		eq((Counted(X)), 1, "and counts him once")
	end)
	Restore(s)
	if not ok then error(err, 0) end
end)

---------------------------------------------------------------------------
-- (1.5.4) The hop across Forever's sub-realms. The dev, 2026-11-08: "O layer hop só funciona no mesmo
-- realm, mas tem como ir lá: precisa estar no grupo, deslogar e logar", and a logout alone does not
-- always do it, closing the game does. Fail before: Hop.Ask took no sub-realm, a helper elsewhere
-- was taken, the join waited for an NPC that could never come, and nothing survived the relog.
---------------------------------------------------------------------------

test("Forever layer hop: a hop to a layer on our own sub-realm is as before: the helper's invite accepted, the layer confirmed by two NPCs, the group left, nothing kept for a relog and no relog window", function()
	local s = Saved()
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local O, w = Asked(nil)
		w.group, w.party.party1 = 2, "Helper One"
		w.zoneUID = 9 -- (two creatures around show the layer asked for: Layers.Mine's confirmedAt)
		O.Hop.OnRoster()
		eq(O.Hop.State().phase, "done", "joined, confirmed and left in one go")
		eq(w.left, 1, "the group left once")
		assert(Printed(w, ns.L.HOP_JOINED:format("Helper One")), "the join said")
		assert(Printed(w, ns.L.HOP_MOVED_LEFT), "the move said")
		eq(O.db.hopPending, nil, "nothing kept for a relog")
		eq(Popups(w, "OLYMPUS_HOP_RELOG"), 0, "no relog window")
		eq(O.Hop.Stats().moves, 1)
	end)
	Restore(s)
	if not ok then error(err, 0) end
end)

test("Forever layer hop: a guildmate's layer word is filed under the sub-realm his hello named, apart from a same-UID layer here and shown with that sub-realm's label, by either copy of his word; one whose hello named ours, or none, counts here", function()
	local s = Saved()
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		ns.realm = "CAMWOWUS2Realm7PvE"
		local R, rdeliver, _, _, rpump = extra.RelayWorld("Rep Orter-CAMWOWUS2Realm7PvE", "Olympus II")
		LoadLayers(R)
		-- The hellos: Bee Mate plays on Realm1, Cee Mate on ours, Dee Mate's version names none.
		rdeliver("GUILD", "Bee Mate", "H1~1.5.4~CAMWOWUS2Realm1PvE~s")
		rdeliver("GUILD", "Cee Mate", "H1~1.5.4~CAMWOWUS2Realm7PvE~s")
		rdeliver("GUILD", "Dee Mate", "H1~0.9.8")
		eq(R.Comm.PeerRealm("Bee Mate"), "CAMWOWUS2Realm1PvE", "the hello's realm, by the plain name")
		eq(R.Comm.PeerRealm("Dee Mate"), nil, "a version that names none")
		eq(R.Layers.RealmOf("Bee Mate-CAMWOWUS2Realm7PvE"), "CAMWOWUS2Realm1PvE", "another sub-realm of ours")
		eq(R.Layers.RealmOf("Cee Mate"), nil, "ours"); eq(R.Layers.RealmOf("Dee Mate"), nil, "not known: counted here")
		eq(R.Layers.RealmLabel("CAMWOWUS2Realm1PvE"), "Realm1")
		for _, who in ipairs({ "Bee Mate", "Cee Mate", "Dee Mate" }) do rdeliver("GUILD", who, "RG~P~" .. who .. "~" .. LAYER) end
		rpump()
		local rows = R.Layers.ForMap(1453)
		eq(#rows, 2, "two layers of UID 7: ours and Realm1's")
		eq(rows[1].zoneUID, 7); eq(rows[1].realm, nil); eq(rows[1].count, 2, "Cee and Dee here")
		eq(rows[2].zoneUID, 7); eq(rows[2].realm, "CAMWOWUS2Realm1PvE"); eq(rows[2].count, 1, "Bee there")
		assert(R.Layers.Name(rows[2]):find("[Realm1]", 1, true), R.Layers.Name(rows[2]))
		assert(not R.Layers.Name(rows[1]):find("[", 1, true), R.Layers.Name(rows[1]))
		local of = R.Layers.Of("Bee Mate")
		eq(of and of.zoneUID, 7); eq(of and of.realm, "CAMWOWUS2Realm1PvE", "where he is, with his sub-realm")
		eq(R.Layers.CountSharedInZone(1453), 3, "the muster counts the three")
		-- The relay's copy of Bee Mate's word, stamped with the relay's own sub-realm, first: the same
		-- layer; his own copy after it counts nobody more.
		local R2, r2deliver, _, _, r2pump = extra.RelayWorld("Rep Orter-CAMWOWUS2Realm7PvE", "Olympus II")
		LoadLayers(R2)
		r2deliver("GUILD", "Bee Mate", "H1~1.5.4~CAMWOWUS2Realm1PvE~s")
		r2deliver("WHISPER", "Max Ran", "RM~P~Bee Mate-CAMWOWUS2Realm3PvE~" .. LAYER)
		r2deliver("GUILD", "Bee Mate", "RG~P~Bee Mate~" .. LAYER)
		r2pump()
		rows = R2.Layers.ForMap(1453)
		eq(#rows, 1, "one layer"); eq(rows[1].realm, "CAMWOWUS2Realm1PvE", "filed under his sub-realm"); eq(rows[1].count, 1, "once")
	end)
	Restore(s)
	if not ok then error(err, 0) end
end)

test("Forever layer hop: 'already there' is said only for a layer on our own sub-realm, the same UID on another sub-realm is asked for; /oly hop <uid>@<label> names a listed layer there, the bare UID the one here", function()
	local s = Saved()
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		ns.realm = REALM5
		local O, _, osent, _, opump, osentOf = extra.RelayWorld("Asker Name-" .. REALM5, "Olympus II")
		local w = {}
		LoadHop(O, w)
		StubGroup(w)
		w.zoneUID = 7 -- (our own layer)
		O.Hop.Ask(1453, 7, "Our layer")
		opump()
		assert(Printed(w, ns.L.HOP_ALREADY), "the same UID here: already there")
		eq(#osentOf("RG~"), 0, "nothing asked")
		O.Hop.Ask(1453, 7, "Their layer [Realm1]", REALM1)
		opump()
		eq(#osentOf("RG~P~Asker Name~LQ~"), 1, "the same UID on Realm1 is another layer: asked")
		eq(O.Hop.State().realm, REALM1, "the ask carries the sub-realm")
		O.Hop.Cancel()
		O.clock = O.clock + O.Hop.ASK_GAP
		wipe(osent)
		-- The list's rows by the command: "9" is the one here, "9@realm1" the one there.
		local head = { name = "Some One", rank = 3, guild = "Olympus II" }
		w.layers = { { zoneUID = 9, head = head, count = 1, lastSeen = O.clock },
			{ zoneUID = 9, realm = REALM1, head = head, count = 1, lastSeen = O.clock } }
		O.Hop.Command("9@realm1")
		opump()
		eq(O.Hop.State() and O.Hop.State().realm, REALM1, "the labelled row")
		eq(#osentOf("RG~P~Asker Name~LQ~"), 1)
		O.Hop.Cancel()
		O.clock = O.clock + O.Hop.ASK_GAP
		O.Hop.Command("9")
		eq(O.Hop.State() and O.Hop.State().realm, nil, "the bare UID: the row here")
		O.Hop.Cancel()
		O.clock = O.clock + O.Hop.ASK_GAP
		w.printed = {}
		O.Hop.Command("9@realm2")
		assert(Printed(w, ns.L.HOP_NO_ALTERNATIVE), "a label no row has")
		eq(O.Hop.State().phase, "done", "nothing asked")
	end)
	Restore(s)
	if not ok then error(err, 0) end
end)

test("Forever layer hop: in the helper's group on another sub-realm no NPC confirms the move: the hop is kept in the saved variables and the relog window shows; an offer from a helper here is not taken, the layer's UID seen here leaves nothing, and leaving the group ends it with a line", function()
	local s = Saved()
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local O, w, odeliver = Asked(REALM1)
		odeliver("WHISPER", "Near Mate", ("LO~%d~0~0"):format(O.Hop.State().id))
		eq(O.Hop.State().count, 1, "a helper on our own sub-realm is no helper for a layer on Realm1")
		eq(O.Hop.Stats().elsewhere, 1)
		w.group, w.party.party1 = 2, "Helper One"
		w.zoneUID = 9 -- (the creatures around show UID 9: ours, on our old sub-realm, not the layer asked for)
		O.Hop.OnRoster()
		eq(O.Hop.State().phase, "relog", "the relog step")
		eq(w.left, 0, "the group is not left")
		local p = O.db.hopPending
		assert(type(p) == "table", "the hop kept in the saved variables")
		eq(p.me, "Asker Name"); eq(p.helper, "Helper One"); eq(p.mapID, 1453); eq(p.zoneUID, 9)
		eq(p.realm, REALM1); eq(p.from, REALM5); eq(p.t, O.clock); eq(p.id, O.Hop.State().id)
		eq(Popups(w, "OLYMPUS_HOP_RELOG"), 1, "the relog window")
		eq(w.popups[#w.popups].arg, "Helper One")
		assert(Printed(w, ns.L.HOP_JOINED_RELOG:format("Helper One")), "the chat line says where he is")
		O.Hop.OnLayer()
		eq(w.left, 0, "UID 9 here is not the layer there: nothing confirmed, nothing left")
		for _ = 1, 5 do O.clock = O.clock + 1; O.Hop.Tick() end
		eq(O.Hop.State().phase, "relog", "still waiting for the logout")
		assert(not Printed(w, ns.L.HOP_RELOG_STILL), "no 'still on your old server' before a relog")
		eq(O.Hop.ProgressText(), ns.L.HOP_PROGRESS_RELOG:format("Helper One"))
		-- The player leaves the group himself: the hop ends with a line, nothing more.
		w.group, w.party.party1 = 0, nil
		O.Hop.OnRoster()
		eq(O.Hop.State().phase, "done"); eq(O.db.hopPending, nil, "the kept hop is over")
		assert(Printed(w, ns.L.HOP_RELOG_NO_GROUP:format("Helper One")), "and said")
		eq(w.left, 0, "never left for him")
		eq(w.hidden[#w.hidden], "OLYMPUS_HOP_RELOG", "the window closed")
	end)
	Restore(s)
	if not ok then error(err, 0) end
end)

test("Forever layer hop: the relog window's Leave group leaves the group and ends the kept hop; OK, Escape, a timeout or another window taking its place leave the group alone", function()
	local s = Saved()
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local O, w = Asked(REALM1)
		w.group, w.party.party1 = 2, "Helper One"
		O.Hop.OnRoster()
		local a = O.Hop.State()
		eq(a.phase, "relog")
		local def = StaticPopupDialogs.OLYMPUS_HOP_RELOG
		eq(def.noCancelOnEscape, true, "Escape is no Leave group")
		def.OnAccept(nil, a)
		def.OnCancel(nil, a, "override"); def.OnCancel(nil, a, "timeout"); def.OnCancel(nil, a)
		eq(w.left, 0, "nothing of that leaves"); eq(O.Hop.State().phase, "relog"); assert(O.db.hopPending, "the hop kept")
		def.OnCancel(nil, a, "clicked")
		eq(w.left, 1, "Leave group leaves"); eq(O.Hop.State().phase, "done"); eq(O.db.hopPending, nil, "and the kept hop is over")
		assert(Printed(w, ns.L.HOP_DONE))
		def.OnCancel(nil, a, "clicked")
		eq(w.left, 1, "an old window leaves nothing more")
	end)
	Restore(s)
	if not ok then error(err, 0) end
end)

test("Forever layer hop: the kept hop survives a restart (a fresh load from the saved table): back in the game on the helper's sub-realm and still in his group, the layer is confirmed by two NPCs and the group left", function()
	local s = Saved()
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local O, w = Asked(REALM1)
		w.group, w.party.party1 = 2, "Helper One"
		O.Hop.OnRoster()
		eq(O.Hop.State().phase, "relog")
		local saved = Reloaded(O.db)
		-- The game closed and opened again two minutes later, the character on Realm1 now.
		ns.realm = REALM1
		local O2 = extra.RelayWorld("Asker Name-" .. REALM1, "Olympus II")
		local w2 = { db = saved, party = { party1 = "Helper One" }, group = 2 }
		LoadHop(O2, w2)
		StubGroup(w2)
		O2.clock = O.clock + 120
		eq(O2.Hop.Resume(), true, "the kept hop taken up")
		local a = O2.Hop.State()
		eq(a.phase, "relog"); eq(a.realm, REALM1); eq(a.mapID, 1453); eq(a.zoneUID, 9)
		eq(a.helper, "Helper One-" .. REALM1, "the helper as the game names him here")
		w2.zoneUID = 9 -- (two creatures show the layer: Layers.Mine's confirmedAt)
		O2.Hop.Tick()
		assert(Printed(w2, ns.L.HOP_RELOG_ARRIVED:format("Helper One")), "arrived on his sub-realm")
		eq(O2.Hop.State().phase, "done", "confirmed by the creatures and left")
		eq(w2.left, 1, "the group left once"); eq(O2.db.hopPending, nil, "the kept hop is over")
		eq(O2.Hop.Stats().arrived, 1); eq(O2.Hop.Stats().moves, 1)
		assert(Printed(w2, ns.L.HOP_MOVED_LEFT))
	end)
	Restore(s)
	if not ok then error(err, 0) end
end)

test("Forever layer hop: back in the game on the old sub-realm (a logout alone did not move the player) and still in the helper's group: one line says to close the game and open it again, the hop waits and /oly hop status names both servers; the window over, it ends with a line and the group is left alone", function()
	local s = Saved()
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local O, w = Asked(REALM1)
		w.group, w.party.party1 = 2, "Helper One"
		O.Hop.OnRoster()
		local saved = Reloaded(O.db)
		-- A logout and login (or a /reload) a minute later, the character still on Realm5.
		local O3 = extra.RelayWorld("Asker Name-" .. REALM5, "Olympus II")
		local w3 = { db = saved, party = { party1 = "Helper One" }, group = 2 }
		LoadHop(O3, w3)
		StubGroup(w3)
		O3.clock = O.clock + 60
		eq(O3.Hop.Resume(), true)
		local function Still()
			local n = 0
			for _, line in ipairs(w3.printed) do if line == ns.L.HOP_RELOG_STILL then n = n + 1 end end
			return n
		end
		O3.Hop.Tick()
		eq(O3.Hop.State().phase, "relog", "the hop waits on")
		eq(Still(), 1, "told once to close the game and open it again")
		w3.zoneUID = 9
		O3.Hop.OnLayer()
		eq(w3.left, 0, "UID 9 on the old sub-realm confirms nothing")
		for _ = 1, 3 do O3.clock = O3.clock + 1; O3.Hop.Tick() end
		eq(Still(), 1, "said once"); assert(O3.db.hopPending, "the hop kept")
		O3.Hop.Command("status")
		assert(Printed(w3, "Realm1") and Printed(w3, "Realm5"), "the status names the layer's server and ours")
		-- The window passes: over, with a line, the group left alone.
		O3.clock = saved.hopPending.t + O3.Hop.RELOG_WINDOW + 1
		O3.Hop.Tick()
		eq(O3.Hop.State().phase, "done"); eq(O3.db.hopPending, nil); eq(w3.left, 0)
		assert(Printed(w3, ns.L.HOP_RELOG_EXPIRED:format(15)), "the line")
	end)
	Restore(s)
	if not ok then error(err, 0) end
end)

test("Forever layer hop: back in the game out of the helper's group (past the first seconds), or in another group, the kept hop ends with a line and nothing is left; another character's kept hop is left to him; one past its window is dropped at login", function()
	local s = Saved()
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local O, w = Asked(REALM1)
		w.group, w.party.party1 = 2, "Helper One"
		O.Hop.OnRoster()
		local saved = Reloaded(O.db)
		ns.realm = REALM1
		-- Not grouped: the group may show a moment after the login; past the grace it is over.
		local O4 = extra.RelayWorld("Asker Name-" .. REALM1, "Olympus II")
		local w4 = { db = Reloaded(saved), group = 0 }
		LoadHop(O4, w4); StubGroup(w4)
		O4.clock = O.clock + 60
		eq(O4.Hop.Resume(), true)
		O4.Hop.Tick()
		eq(O4.Hop.State().phase, "relog", "the first seconds: the group may still come")
		O4.clock = O4.clock + O4.Hop.RELOG_GRACE
		O4.Hop.Tick()
		eq(O4.Hop.State().phase, "done"); eq(O4.db.hopPending, nil); eq(w4.left, 0)
		assert(Printed(w4, ns.L.HOP_RELOG_NO_GROUP:format("Helper One")))
		-- Another group: over at once, never left.
		local O5 = extra.RelayWorld("Asker Name-" .. REALM1, "Olympus II")
		local w5 = { db = Reloaded(saved), group = 2, party = { party1 = "Some Friend" } }
		LoadHop(O5, w5); StubGroup(w5)
		O5.clock = O.clock + 60
		eq(O5.Hop.Resume(), true)
		O5.Hop.Tick()
		eq(O5.Hop.State().phase, "done", "a friend's group is not the hop's"); eq(O5.db.hopPending, nil); eq(w5.left, 0)
		-- Another character of the account: his, while its window lasts.
		local O6 = extra.RelayWorld("Alt Character-" .. REALM1, "Olympus II")
		local w6 = { db = Reloaded(saved) }
		LoadHop(O6, w6); StubGroup(w6)
		O6.clock = O.clock + 60
		eq(O6.Hop.Resume(), false); assert(O6.db.hopPending, "kept for the character it is of"); eq(O6.Hop.State(), nil)
		-- Past its window at login: dropped, with the line.
		local O7 = extra.RelayWorld("Asker Name-" .. REALM1, "Olympus II")
		local w7 = { db = Reloaded(saved) }
		LoadHop(O7, w7); StubGroup(w7)
		O7.clock = saved.hopPending.t + O7.Hop.RELOG_WINDOW + 1
		eq(O7.Hop.Resume(), false); eq(O7.db.hopPending, nil); eq(O7.Hop.State(), nil)
		assert(Printed(w7, ns.L.HOP_RELOG_EXPIRED:format(15)))
	end)
	Restore(s)
	if not ok then error(err, 0) end
end)

test("Forever layer hop, the helper's side: a guest whose hello names another sub-realm is said to arrive after a relog and kept RELOG_WINDOW instead of GUEST_TIME, his window says so; a guest from here is kept GUEST_TIME, as before", function()
	local s = Saved()
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		ns.realm = REALM1
		local H, hdeliver, hsent, _, hpump, hsentOf = extra.RelayWorld("Helper One-" .. REALM1, "Olympus II")
		local hw = { realms = { ["Asker Name"] = REALM5, ["Other Asker"] = REALM5 }, party = {}, group = 0 }
		LoadHop(H, hw)
		StubGroup(hw)
		hw.zoneUID = 9
		for _, who in ipairs({ "Asker Name", "Other Asker", "Near Mate" }) do hw.byName[who .. "-" .. REALM1] = 3 end
		H.db.layerAutoInvite = true
		hdeliver("GUILD", "Asker Name", "RG~P~Asker Name~LQ~42~1453~9")
		hpump()
		eq(#hsentOf("LO~42~"), 1, "the offer")
		hdeliver("WHISPER", "Asker Name", "LR~42")
		eq(#hw.invited, 1, "invited on his own (Always invite)"); eq(hw.invited[1], "Asker Name")
		assert(Printed(hw, ns.L.HOP_INVITING_RELOG:format("Asker Name", 15)), "told he arrives after a relog and stays up to 15 minutes")
		hw.group, hw.party.party1 = 2, "Asker Name"
		H.clock = H.clock + H.Hop.GUEST_TIME + 1
		H.Hop.Tick(); hpump()
		eq(#hsentOf("LX~"), 0, "not let go after GUEST_TIME")
		H.clock = H.clock + H.Hop.RELOG_WINDOW
		H.Hop.Tick(); hpump()
		eq(#hsentOf("LX~42"), 1, "let go after RELOG_WINDOW")
		-- A guest from our own sub-realm: GUEST_TIME, as before.
		hw.group, hw.party.party1 = 0, nil
		hdeliver("GUILD", "Near Mate", "RG~P~Near Mate~LQ~44~1453~9")
		hpump()
		hdeliver("WHISPER", "Near Mate", "LR~44")
		eq(#hw.invited, 2); assert(Printed(hw, ns.L.HOP_INVITING:format("Near Mate")), "the usual line")
		hw.group, hw.party.party1 = 2, "Near Mate"
		H.clock = H.clock + H.Hop.GUEST_TIME + 1
		H.Hop.Tick(); hpump()
		eq(#hsentOf("LX~44"), 1, "let go after GUEST_TIME")
		-- With the window: the one that names the relog, for an asker on another sub-realm.
		H.db.layerAutoInvite = nil
		hw.group, hw.party.party1 = 0, nil
		H.clock = H.clock + H.Hop.HELP_GAP
		hdeliver("GUILD", "Other Asker", "RG~P~Other Asker~LQ~43~1453~9")
		hpump()
		eq(#hsentOf("LO~43~"), 1)
		hdeliver("WHISPER", "Other Asker", "LR~43")
		eq(Popups(hw, "OLYMPUS_HOP_REQUEST_RELOG"), 1, "the window with the relog line"); eq(Popups(hw, "OLYMPUS_HOP_REQUEST"), 0)
		eq(hw.popups[#hw.popups].data.other, REALM5)
		StaticPopupDialogs.OLYMPUS_HOP_REQUEST_RELOG.OnAccept(nil, hw.popups[#hw.popups].data)
		eq(#hw.invited, 3, "Invite from it invites"); eq(hw.invited[3], "Other Asker")
		assert(Printed(hw, ns.L.HOP_INVITING_RELOG:format("Other Asker", 15)))
	end)
	Restore(s)
	if not ok then error(err, 0) end
end)

test("Forever layer hop: the experimental hop's window at the first ask of a session: Ask sends it, Cancel sends nothing and the window comes back; answered, no window for that kind again this session; a layer on another sub-realm has its own window, once", function()
	local s = Saved()
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		ns.realm = REALM5
		local O, _, osent, _, opump, osentOf = extra.RelayWorld("Asker Name-" .. REALM5, "Olympus II")
		local w = { confirm = true }
		LoadHop(O, w)
		StubGroup(w)
		local def = StaticPopupDialogs.OLYMPUS_HOP_CONFIRM
		O.Hop.Ask(1453, 9, "Layer of someone")
		opump()
		eq(Popups(w, "OLYMPUS_HOP_CONFIRM"), 1, "the window first"); eq(w.popups[1].arg, ns.L.HOP_CONFIRM_SAME)
		eq(#osentOf("RG~"), 0, "nothing asked yet"); eq(O.Hop.State(), nil)
		def.OnCancel(nil, w.popups[1].data, "clicked")
		opump()
		eq(#osentOf("RG~"), 0, "Cancel sends nothing"); eq(O.Hop.State(), nil)
		O.Hop.Ask(1453, 9, "Layer of someone")
		eq(Popups(w, "OLYMPUS_HOP_CONFIRM"), 2, "asked again: the window again")
		def.OnAccept(nil, w.popups[2].data)
		opump()
		eq(#osentOf("RG~P~Asker Name~LQ~"), 1, "Ask sends it"); eq(O.Hop.State().phase, "asking")
		O.Hop.Cancel()
		O.clock = O.clock + O.Hop.ASK_GAP
		wipe(osent)
		O.Hop.Ask(1453, 9, "Layer of someone")
		opump()
		eq(Popups(w, "OLYMPUS_HOP_CONFIRM"), 2, "no window again this session"); eq(#osentOf("RG~P~Asker Name~LQ~"), 1)
		O.Hop.Cancel()
		O.clock = O.clock + O.Hop.ASK_GAP
		wipe(osent)
		O.Hop.Ask(1453, 9, "Their layer [Realm1]", REALM1)
		opump()
		eq(Popups(w, "OLYMPUS_HOP_CONFIRM"), 3, "a layer on another sub-realm: its own window"); eq(w.popups[3].arg, ns.L.HOP_CONFIRM_OTHER)
		eq(#osentOf("RG~"), 0, "nothing asked yet")
		def.OnAccept(nil, w.popups[3].data)
		opump()
		eq(#osentOf("RG~P~Asker Name~LQ~"), 1); eq(O.Hop.State().realm, REALM1)
		O.Hop.Cancel()
		O.clock = O.clock + O.Hop.ASK_GAP
		O.Hop.Ask(1453, 9, "Their layer [Realm1]", REALM1)
		eq(Popups(w, "OLYMPUS_HOP_CONFIRM"), 3, "once")
	end)
	Restore(s)
	if not ok then error(err, 0) end
end)

test("Forever layer hop: every entry point says experimental (the King's line, the layer list's ask, a row's tip, /oly hop), and the relog's lines exist, in English, Portuguese and the five languages", function()
	local function Load(code)
		local lns, saved = {}, GetLocale
		GetLocale = function() return code end
		local ok, err = pcall(function()
			assert(loadfile(extra.addon .. "Locales.lua"))("Olympus", lns)
			for _, f in ipairs({ "deDE", "esES", "frFR", "itIT", "ruRU" }) do assert(loadfile(extra.addon .. "Locales/" .. f .. ".lua"))("Olympus", lns) end
		end)
		GetLocale = saved
		if not ok then error(err, 0) end
		return lns.L
	end
	local en = Load("enUS")
	for code, word in pairs({ enUS = "experimental", ptBR = "experimental", deDE = "experimentell", esES = "experimental",
		frFR = "expérimental", itIT = "sperimentale", ruRU = "экспериментально" }) do
		local L = Load(code)
		for _, key in ipairs({ "HOP_KING_LINE", "HOP_ANY_BUTTON", "HOP_ROW_TIP", "HELP_HOP" }) do
			assert(type(L[key]) == "string" and L[key]:find(word, 1, true), code .. " " .. key .. ": " .. tostring(L[key]))
		end
		for _, key in ipairs({ "HOP_CONFIRM_SAME", "HOP_CONFIRM_OTHER", "HOP_CONFIRM_ASK", "HOP_CONFIRM_CANCEL", "HOP_RELOG", "HOP_RELOG_OK",
			"HOP_JOINED_RELOG", "HOP_RELOG_STILL", "HOP_RELOG_ARRIVED", "HOP_RELOG_EXPIRED", "HOP_RELOG_NO_GROUP", "HOP_PROGRESS_RELOG",
			"HOP_REQUEST_RELOG", "HOP_INVITING_RELOG", "HOP_ROW_OTHER_REALM", "HOP_STATUS_RELOG" }) do
			assert(type(L[key]) == "string" and L[key] ~= "", code .. " " .. key)
			-- (The OK button reads OK in most of them.)
			if code ~= "enUS" and key ~= "HOP_RELOG_OK" then assert(L[key] ~= en[key], code .. " translates " .. key) end
		end
	end
end)
