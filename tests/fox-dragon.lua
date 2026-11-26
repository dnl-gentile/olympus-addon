-- Rank visuals have no character-specific override. Exercise the former exact-name case
-- through the real Borders APIs and the native-frame/input-mode harness.
local ns, test, eq, WithBorders, BorderUnit = ...
local REALM, NAME = "CAMWOWUS2Realm1PvE", "Akafoxslayer Thunderfury"
local WHO = NAME .. "-" .. REALM
local REMOVED = "Interface\\AddOns\\Olympus\\media\\borders\\fox-dragon"
local SILVER = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver-Winged"
local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\]run%.lua$") or "./"

local function WithMember(fn, setup)
	local saved = { realm = ns.realm, group = ns.group, cfu = ChatFrameUtil }
	local ok, err = pcall(function()
		ns.realm, ns.group = REALM, ns.GroupOf(REALM)
		WithBorders(fn, function(w)
			ns.splitNames = true
			w.units.player = BorderUnit("Tester", "Olympus II", "Member", 3, { realm = REALM })
			ns.me = "Tester-" .. REALM
			if setup then setup(w) end
		end)
	end)
	ns.realm, ns.group, ChatFrameUtil = saved.realm, saved.group, saved.cfu
	if not ok then error(err, 0) end
end
local function Member(extra)
	local fields = { realm = REALM }
	for key, value in pairs(extra or {}) do fields[key] = value end
	return BorderUnit(NAME, "Olympus II", "Member", 3, fields)
end
local function Council(w)
	-- The existing border harness models the already-validated council list. The visual
	-- selection must consume it, never add the character to it by a cosmetic name pin.
	ns.rdb.council.names[NAME:lower()] = true
end
local function NoRemovedTexture(w)
	for _, tex in ipairs(w.textures) do assert(tex.file ~= REMOVED, "removed art is never allocated") end
end

test("Role defaults: former personal identity uses standard High Council silver on target, focus, party and own portrait", function()
	WithMember(function(w)
		local council = ns.rdb.council
		w.internal("LOGIN"); w.target(Member())
		eq(w.B.TierOf("target"), "silver-elite")
		eq(w.shown("target"), "silver-elite")
		eq(w.shownTexture("target").atlas, SILVER)
		eq(w.shownTexture("target").file, nil)
		w.units.focus = Member(); w.fire("PLAYER_FOCUS_CHANGED")
		eq(w.shown("focus"), "silver-elite")
		w.party(); w.units.party1 = Member(); w.fire("GROUP_ROSTER_UPDATE")
		eq(w.shown("party1"), "silver-elite")
		w.units.player = Member(); w.fire("UNIT_NAME_UPDATE", "player")
		eq(w.shown("player"), "silver-elite")
		eq(w.B.MarkOf("target"), "silver", "the normal rank mark")
		eq(ns.rdb.council, council, "rendering preserves the existing signed role data")
		eq(w.ns.IsHighCouncillor(WHO), true)
		eq(w.ns.IsKingCharacter(WHO), false)
		NoRemovedTexture(w)
	end, Council)
end)

test("Role defaults: an exact character name without a council appointment grants no frame or authority", function()
	WithMember(function(w)
		local council = ns.rdb.council
		w.internal("LOGIN"); w.target(Member())
		eq(w.B.TierOf("target"), nil)
		eq(w.shown("target"), nil)
		w.units.focus = Member(); w.fire("PLAYER_FOCUS_CHANGED")
		eq(w.shown("focus"), nil)
		w.party(); w.units.party1 = Member(); w.fire("GROUP_ROSTER_UPDATE")
		eq(w.shown("party1"), nil)
		w.units.player = Member(); w.fire("UNIT_NAME_UPDATE", "player")
		eq(w.shown("player"), nil)
		eq(w.B.MarkOf("target"), "member")
		eq(ns.rdb.council, council)
		eq(w.ns.IsHighCouncillor(WHO), false)
		eq(w.ns.IsKingCharacter(WHO), false)
		eq(w.B.RoleBadgeOfName(WHO, "Olympus II"), nil)
		NoRemovedTexture(w)
	end)
end)

test("Role defaults: internal portrait and native chat use standard High Council silver and retain the appointment", function()
	WithMember(function(w)
		w.internal("LOGIN")
		eq(w.B.TierOfName(WHO, "Olympus II"), "silver-elite")
		eq(w.B.MarkOfName(WHO, "Olympus II"), "silver")
		local rig = w.B.Rig(w.container("StandardCouncilPortrait"), true, true)
		w.B.ShowTier(rig, w.B.TierOfName(WHO, "Olympus II"))
		eq(w.shownOn("StandardCouncilPortrait"), "silver-elite")
		local head, council, drawn = w.B.ChatName(WHO)
		assert(head and head:find("nameplates-icon-elite-silver", 1, true), "native chat uses the standard silver rank mark")
		eq(head:find(REMOVED, 1, true), nil)
		eq(council, true); eq(drawn, "silver")
		ChatFrameUtil = { AddSenderNameFilter = function() end }
		w.B.ChatRefresh()
		local decorated = assert(w.B.ChatFilter("CHAT_MSG_GUILD", NAME, "hello", WHO))
		assert(decorated:find("nameplates-icon-elite-silver", 1, true), "guild chat keeps the standard council mark")
		eq(decorated:find(REMOVED, 1, true), nil)
		eq(w.ns.IsHighCouncillor(WHO), true)
		NoRemovedTexture(w)
	end, Council)
end)

test("Role defaults: ordinary native chat still requires membership proof and never upgrades an exact name", function()
	WithMember(function(w)
		w.ns.Roster = { RankOf = function(who) if ns.Fold(ns.FullName(who)) == ns.Fold(WHO) then return 3 end end }
		w.internal("LOGIN")
		eq(w.B.TierOfName(WHO, "Olympus II"), nil)
		eq(w.B.MarkOfName(WHO, "Olympus II"), "member")
		local head, council, drawn = w.B.ChatName(WHO)
		eq(head, w.B.CHAT_STAR); eq(council, false); eq(drawn, "member")
		ChatFrameUtil = { AddSenderNameFilter = function() end }
		w.B.ChatRefresh()
		eq(w.B.ChatFilter("CHAT_MSG_GUILD", NAME, "hello", WHO), nil, "ordinary guild senders have no dragon prefix")
		w.ns.Roster = { RankOf = function() end }; w.B.ChatForget()
		eq(w.B.MarkOfName(WHO, "Olympus II"), nil)
		eq(w.B.ChatName(WHO), false, "no native membership proof")
		NoRemovedTexture(w)
	end)
end)

test("Role defaults: cover and net-off still hide the standard rank without removing the council appointment", function()
	WithMember(function(w)
		w.ns.Roster = { RankOf = function(who) if ns.Fold(ns.FullName(who)) == ns.Fold(WHO) then return 3 end end }
		w.internal("LOGIN"); w.target(Member())
		eq(w.shown("target"), "silver-elite")
		w.ns.Cover = { AliasOf = function() return "Covered" end, Version = function() return 1 end }
		w.target(Member()); eq(w.B.TierOf("target"), nil)
		eq(w.B.ChatName(WHO), w.B.CHAT_STAR, "a covered member has no council prefix")
		eq(w.ns.IsHighCouncillor(WHO), true, "cover does not revoke signed authority")
		w.ns.Cover = nil
		w.ns.Moderation = { Hides = function() return true end }
		w.target(Member()); eq(w.B.TierOf("target"), nil)
		eq(w.B.ChatName(WHO), false)
		eq(w.ns.IsHighCouncillor(WHO), true, "visual suppression does not rewrite the role list")
		NoRemovedTexture(w)
	end, Council)
end)

test("Role defaults: gamepad login and both input switches preserve the gates and restore standard silver only", function()
	WithMember(function(w)
		ChatFrameUtil = { AddSenderNameFilter = function() end }
		w.style = 1; w.internal("LOGIN"); w.target(Member())
		eq(#w.textures, 0); eq(#w.hooks, 0)
		eq(w.B.ChatFilter("CHAT_MSG_GUILD", NAME, "hello", WHO), nil)
		w.style = 0; w.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 0, 1)
		eq(w.shown("target"), "silver-elite")
		assert(w.B.ChatFilter("CHAT_MSG_GUILD", NAME, "hello", WHO))
		w.style = 1; w.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 1, 0)
		eq(w.shown("target"), nil)
		eq(w.B.ChatFilter("CHAT_MSG_GUILD", NAME, "hello", WHO), nil)
		w.style = 0; w.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 0, 1)
		eq(w.shown("target"), "silver-elite")
		w.ns.db.borders = false; w.B.RefreshAll(true)
		eq(w.shown("target"), nil)
		NoRemovedTexture(w)
	end, Council)
end)

test("Role defaults: removed art is absent from runtime catalog and chat previews while its source stays outside the addon", function()
	WithMember(function(w)
		for _, tier in ipairs(w.B.TIERS) do assert(tier.name ~= "fox-dragon", "no removed tier in active catalogs") end
		eq(w.B.ChatMarkText("fox"), nil)
		eq(w.B.ChatLegendText("fox"), nil)
	end)
	local runtime = io.open(ROOT .. "Olympus/media/borders/fox-dragon.tga", "rb")
	if runtime then runtime:close() end
	eq(runtime, nil, "retired texture is not shipped")
	local source = assert(io.open(ROOT .. "media/borders/src/fox-dragon.png", "rb"))
	local signature = source:read(8); source:close()
	eq(signature, "\137PNG\r\n\26\n", "the original source is retained outside the addon package")
end)
