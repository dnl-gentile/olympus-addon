-- The character-specific supplied Fox dragon is presentation, never council authority.
-- Exercise the actual Borders functions and the existing native-frame/input-mode harness.
local ns, test, eq, WithBorders, BorderUnit = ...
local REALM, NAME = "CAMWOWUS2Realm1PvE", "Akafoxslayer Thunderfury"
local WHO = NAME .. "-" .. REALM
local FILE = "Interface\\AddOns\\Olympus\\media\\borders\\fox-dragon"
local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\]run%.lua$") or "./"

local function WithFox(fn, setup)
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
local function Fox(extra)
	local fields = { realm = REALM }
	for key, value in pairs(extra or {}) do fields[key] = value end
	return BorderUnit(NAME, "Olympus II", "Member", 3, fields)
end

test("Fox dragon: exact Forever character gets supplied native target, focus, party and own portrait art without council authority", function()
	WithFox(function(w)
		local council = ns.rdb.council
		w.internal("LOGIN")
		w.target(Fox())
		eq(w.B.TierOf("target"), "fox-dragon")
		eq(w.shown("target"), "fox-dragon")
		local art = assert(w.shownTexture("target"))
		eq(art.file, FILE); eq(art.size, "108 108")
		eq(art.coord, "0 0.78125 0 0.78125")
		eq(art.color, nil, "no tint"); eq(art.desaturated, nil, "no desaturation")
		eq(w.underlayTexture("target").shown, false, "no second plain dragon underneath")
		w.units.focus = Fox(); w.fire("PLAYER_FOCUS_CHANGED")
		eq(w.shown("focus"), "fox-dragon")
		w.party(); w.units.party1 = Fox(); w.fire("GROUP_ROSTER_UPDATE")
		eq(w.shown("party1"), "fox-dragon")
		w.units.player = Fox(); w.fire("UNIT_NAME_UPDATE", "player")
		eq(w.shown("player"), "fox-dragon")
		eq(w.shownTexture("player").coord, "0.78125 0 0 0.78125", "native player frame mirrored")
		eq(ns.rdb.council, council, "cosmetic selection changes no signed role data")
		eq(w.ns.IsHighCouncillor(WHO), false, "name is not appointed High Council")
		eq(w.ns.IsKingCharacter(WHO), false, "name is not appointed King")
		eq(w.B.RoleBadgeOfName(WHO, "Olympus II"), nil, "no office badge granted")
	end)
end)

test("Fox dragon: no partial name, Classic namesake, outsider, other faction, cover or net-off inherits personal art", function()
	WithFox(function(w)
		w.internal("LOGIN")
		for _, unit in ipairs({
			BorderUnit("Akafoxslayer Foxslayer", "Olympus II", "Member", 3, { realm = REALM }),
			BorderUnit(NAME .. "x", "Olympus II", "Member", 3, { realm = REALM }),
			BorderUnit(NAME, "Wanderers", "Member", 3, { realm = REALM }),
			BorderUnit(NAME, nil, nil, nil, { realm = REALM }),
			Fox({ faction = "Horde" }),
			Fox({ realm = "ClassicRealm" }),
		}) do
			w.target(unit); eq(w.B.TierOf("target"), nil, "not the eligible native character")
		end
		ns.splitNames = nil; w.target(Fox()); eq(w.B.TierOf("target"), nil, "no cross-client name pin")
		ns.splitNames = true
		w.ns.Cover = { AliasOf = function() return "Covered" end, Version = function() return 1 end }
		w.target(Fox()); eq(w.B.TierOf("target"), nil, "cover suppresses personal identity")
		w.ns.Cover = nil
		w.ns.Moderation = { Hides = function() return true end }
		w.target(Fox()); eq(w.B.TierOf("target"), nil, "net-off hides it")
	end)
end)

test("Fox dragon: internal portrait and native chat head need proven Olympus membership; rank marks remain unchanged", function()
	WithFox(function(w)
		w.ns.Roster = { RankOf = function(who) if ns.Fold(ns.FullName(who)) == ns.Fold(WHO) then return 3 end end }
		w.internal("LOGIN")
		eq(w.B.TierOfName(WHO, "Olympus II"), "fox-dragon")
		eq(w.B.TierOfName(WHO, "Olympus Elsewhere"), nil, "a caller's unproven guild claim grants no cosmetic")
		eq(w.B.TierOfName(WHO, nil), nil, "no membership proof")
		eq(w.B.MarkOfName(WHO, "Olympus II"), "member", "custom art never masquerades as council rank")
		local head, council, drawn = w.B.ChatName(WHO)
		assert(head and head:find(FILE, 1, true), "native chat uses supplied dragon head")
		assert(head:find(":256:256:2:74:18:67|t", 1, true), "crop of same portrait texture")
		eq(council, false); eq(drawn, "fox")
		ChatFrameUtil = { AddSenderNameFilter = function() end }
		w.B.ChatRefresh()
		local decorated = assert(w.B.ChatFilter("CHAT_MSG_GUILD", NAME, "hello", WHO))
		assert(decorated:find(FILE, 1, true), "custom dragon is visible in native guild chat")
		w.ns.Roster = { RankOf = function() end }; w.B.ChatForget()
		eq(w.B.TierOfName(WHO, "Olympus II"), nil, "removed roster proof clears internal portrait")
		eq(w.B.ChatName(WHO), false, "removed proof gives no custom chat mark")
	end)
end)

test("Fox dragon: gamepad login touches no native frames, switches park art and native chat, then restore through existing gates", function()
	WithFox(function(w)
		w.ns.Roster = { RankOf = function(who) if ns.Fold(ns.FullName(who)) == ns.Fold(WHO) then return 3 end end }
		ChatFrameUtil = { AddSenderNameFilter = function() end }
		w.style = 1; w.internal("LOGIN"); w.target(Fox())
		eq(#w.textures, 0); eq(#w.hooks, 0)
		eq(w.B.ChatFilter("CHAT_MSG_GUILD", NAME, "hello", WHO), nil)
		w.style = 0; w.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 0, 1)
		eq(w.shown("target"), "fox-dragon")
		assert(w.B.ChatFilter("CHAT_MSG_GUILD", NAME, "hello", WHO))
		w.style = 1; w.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 1, 0)
		eq(w.shown("target"), nil)
		eq(w.B.ChatFilter("CHAT_MSG_GUILD", NAME, "hello", WHO), nil)
		w.style = 0; w.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 0, 1)
		eq(w.shown("target"), "fox-dragon")
		w.ns.db.borders = false; w.B.RefreshAll(true)
		eq(w.shown("target"), nil)
	end)
end)

test("Fox dragon: missing supplied texture falls back at native silver offsets without assigning a council role", function()
	for _, failure in ipairs({ true, "error" }) do
		WithFox(function(w)
			w.internal("LOGIN"); w.target(Fox())
			local art = assert(w.shownTexture("target"))
			eq(art.file, nil)
			eq(art.atlas, "ui-hud-unitframe-target-portraiton-boss-rare-silver")
			eq(art.point, "TOPRIGHT TargetFrame.TargetFrameContainer TOPRIGHT 0 1", "fitted PNG offsets do not move the native fallback")
			eq(w.ns.IsHighCouncillor(WHO), false)
		end, function(w) w.noFile[FILE] = failure end)
	end
end)

test("Fox dragon: original supplied PNG is retained outside package, and the generated texture has alpha and a clear portrait opening", function()
	local function Read(path)
		local file = assert(io.open(ROOT .. path, "rb")); local data = file:read("*a"); file:close(); return data
	end
	local png = Read("media/borders/src/fox-dragon.png")
	eq(png:sub(1, 8), "\137PNG\r\n\26\n")
	local function U32(data, i) local a,b,c,d=data:byte(i,i+3); return ((a*256+b)*256+c)*256+d end
	eq(U32(png,17),1254); eq(U32(png,21),1254); eq(png:byte(26),6)
	local tga = Read("Olympus/media/borders/fox-dragon.tga")
	local function U16(i) return tga:byte(i)+256*tga:byte(i+1) end
	eq(tga:byte(3),2); eq(U16(13),256); eq(U16(15),256); eq(tga:byte(17),32)
	local function Alpha(x,y) return tga:byte(19+(255-y)*256*4+x*4+3) end
	eq(Alpha(80,95),0,"portrait opening stays transparent")
	local visible=0
	for y=0,255 do for x=0,255 do
		local a=Alpha(x,y)
		if x>=200 or y>=200 then eq(a,0,"transparent canvas outside complete supplied art")
		elseif a>0 then visible=visible+1 end
	end end
	assert(visible>20000,"the complete dragon and lightning are present")
end)
