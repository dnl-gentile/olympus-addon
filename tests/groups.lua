local ns, test, eq, H = ...
local WithBoard, AsSoldier = H.WithBoard, H.AsSoldier

print("Groups.lua: group listings on the Board, applications, invites")

-- The Board's harness (tests/run.lua's WithBoard), with the groups' own state cleared before and
-- after, their redraw at once, and the game's invite and group state stubbed.
local function WithGroups(fn)
	WithBoard(function(w, B)
		local G = ns.Groups
		local saved = { after = G.after, random = G.random, party = C_PartyInfo, invite = InviteUnit, members = GetNumGroupMembers,
			inGroup = IsInGroup, leader = UnitIsGroupLeader, count = GetNumQuestLogEntries, title = GetQuestLogTitle,
			unitName = UnitName, unitClass = UnitClass, inRaid = IsInRaid }
		local ok, err = pcall(function()
			G.Reset()
			w.invited = {}
			G.after = function(_, _, f) return f() end
			G.random = function(a) return a or 0 end
			C_PartyInfo = { InviteUnit = function(name) w.invited[#w.invited + 1] = name end }
			InviteUnit = nil
			-- (The game's party units: w.party = { { name, realm, class file } }, ourselves not among them.)
			w.party = {}
			GetNumGroupMembers = function() return w.members or (#w.party > 0 and #w.party + 1 or 0) end
			IsInGroup = function() return GetNumGroupMembers() > 0 end
			IsInRaid = function() return false end
			local playerClass = UnitClass
			UnitName = function(unit)
				local m = w.party[tonumber(tostring(unit):match("^party(%d)$") or "")]
				if m then return m[1], m[2] end
				return nil
			end
			UnitClass = function(unit)
				local m = w.party[tonumber(tostring(unit):match("^party(%d)$") or "")]
				if m then return m[3], m[3] end
				return playerClass(unit)
			end
			UnitIsGroupLeader = function() return not w.notLeader end
			w.quests = {}
			w.sounds = 0
			saved.alert = ns.PlayAlert
			ns.PlayAlert = function(tone, kind) if kind == "groups" then w.sounds = w.sounds + 1 end return true end
			GetNumQuestLogEntries = function() return #w.quests end
			GetQuestLogTitle = function(i)
				local q = w.quests[i]
				if not q then return nil end
				return q.title, q.level, q.group or 0, q.header or false, false, false, 0, q.id
			end
			fn(w, G, B)
		end)
		G.after, G.random, C_PartyInfo, InviteUnit, GetNumGroupMembers = saved.after, saved.random, saved.party, saved.invite, saved.members
		IsInGroup, UnitIsGroupLeader, GetNumQuestLogEntries, GetQuestLogTitle = saved.inGroup, saved.leader, saved.count, saved.title
		UnitName, UnitClass, IsInRaid = saved.unitName, saved.unitClass, saved.inRaid
		if saved.alert then ns.PlayAlert = saved.alert end
		G.Reset()
		if not ok then error(err, 0) end
	end)
end

-- A listing as another player's addon sends it.
local function Listing(id, guild, kind, target, need, age, note, title, every)
	return ns.Groups.Encode({ id = id, guild = guild, kind = kind, target = target, level = 30, class = "WA", need = need or "113",
		size = 2, every = every or 10, age = age or 0, title = title, note = note })
end
local function Texts(lines)
	local out = {}
	for _, l in ipairs(lines) do out[#out + 1] = tostring(l.text) .. " | " .. tostring(l.right or "") end
	return table.concat(out, "\n")
end
local function Line(lines, text)
	for _, l in ipairs(lines) do if l.text and l.text:find(text, 1, true) then return l end end
	return nil
end
-- A tooltip's lines, as text.
local function Tip(line)
	local out = {}
	line.tooltip({ AddLine = function(_, text) out[#out + 1] = tostring(text) end })
	return table.concat(out, "\n")
end
local function LastWhisper(w) return w.whispered[#w.whispered] end
local function Sent(w, prefix)
	for i = #w.sent, 1, -1 do if w.sent[i].msg:sub(1, #prefix) == prefix then return w.sent[i] end end
	return nil
end

test("1.2 groups: a listing's message, its checks, its words made safe; later fields are left for later versions", function()
	local G = ns.Groups
	local msg = G.Encode({ id = "a7", guild = "Olympus II", kind = "D", target = "DM", level = 18, class = "PR", need = "103", size = 2,
		every = 10, age = 3, note = " need |cffff0000heals|r~now " })
	eq(msg, "GL~a7~Olympus II~D~DM~18~PR~103~2~~~10~3~~need cffff0000heals r now")
	local e = G.Decode(msg)
	eq(e.kind, "D"); eq(e.target, "DM"); eq(e.need, "103"); eq(e.size, 2); eq(e.age, 3); eq(e.title, ""); eq(e.note, "need cffff0000heals r now")
	-- A quest carries its title (cut at 40 bytes); another kind's title is never read.
	e = G.Decode(G.Encode({ id = "q", guild = "Olympus II", kind = "Q", target = "1234", level = 30, need = "012", size = 1, every = 10, age = 0,
		title = "The Defias Brotherhood " .. string.rep("x", 40) }))
	eq(e.target, "1234"); eq(#e.title, 40)
	eq(G.Decode("GL~a~Olympus II~D~DM~18~PR~113~1~~~10~0~smuggled~hi").title, "", "a dungeon has no title")
	eq(G.Decode("GL~a~Olympus II~R~MC~60~PR~+++~12~~~10~0~~hi~future").note, "hi", "fields after the note: later versions'")
	-- An unknown place of a later version still shows, as Other.
	e = G.Decode("GL~a~Olympus II~D~NEWDG~18~PR~113~1~~~10~0~~")
	eq(G.Target(e.kind, e.target, e.title), ns.L.GROUPS_OTHER)
	eq(G.Target("D", "MC"), ns.L.GROUPS_OTHER, "a raid's key is no dungeon")
	for _, bad in ipairs({
		"GL~ABC~Olympus II~D~DM~18~PR~113~1~~~10~0~~", "GL~a~Olympus II~X~DM~18~PR~113~1~~~10~0~~", "GL~a~Olympus II~D~dm~18~PR~113~1~~~10~0~~",
		"GL~a~Olympus II~Q~DM~18~PR~113~1~~~10~0~~", "GL~a~Olympus II~Q~0~18~PR~113~1~~~10~0~~", "GL~a~Olympus II~D~DM~18~PR~11~1~~~10~0~~",
		"GL~a~Olympus II~D~DM~18~PR~1a3~1~~~10~0~~", "GL~a~Olympus II~D~DM~0~PR~113~1~~~10~0~~", "GL~a~Olympus II~D~DM~18~Pr~113~1~~~10~0~~",
		"GL~a~Olympus II~D~DM~18~PR~113~0~~~10~0~~", "GL~a~Olympus II~D~DM~18~PR~113~41~~~10~0~~", "GL~a~Olympus II~D~DM~18~PR~113~1~~~31~0~~",
		"GL~a~Olympus II~D~DM~18~PR~113~1~~~10~61~~", "GL~a~Olympus II~Q~12~18~PR~113~1~~~10~31~~", "GL~a~~D~DM~18~PR~113~1~~~10~0~~",
		"GL~a~Olympus II~D~DM~18~PR~113~1~~~10", "G1~a~Olympus II~D~42~PR~10~3~~", 42 }) do
		eq(G.Decode(bad), nil, tostring(bad))
	end
	-- 1.2: a minimum level (2-99, or empty for any); a quest by a typed name (its target 0, its
	-- title the name; never without one).
	e = G.Decode(G.Encode({ id = "m", guild = "Olympus II", kind = "D", target = "SM", level = 30, need = "113", size = 1, every = 10, age = 0, min = 30 }))
	eq(e.min, 30)
	eq(G.Decode(G.Encode({ id = "m", guild = "Olympus II", kind = "D", target = "SM", level = 30, need = "113", size = 1, every = 10, age = 0, min = 1 })).min, nil, "1: anyone")
	for _, bad in ipairs({ "1", "100", "ab", "5x" }) do
		eq(G.Decode("GL~a~Olympus II~D~DM~18~PR~113~1~" .. bad .. "~~10~0~~"), nil, "min " .. bad)
	end
	e = G.Decode(G.Encode({ id = "t", guild = "Olympus II", kind = "Q", target = "0", level = 30, need = "012", size = 1, every = 10, age = 0, title = "Mor'Ladim" }))
	eq(e.target, "0"); eq(G.Target(e.kind, e.target, e.title), "Mor'Ladim")
	-- A quest's zone (cut at 30 bytes, made safe); another kind's never read; every 5 to 30 minutes.
	e = G.Decode(G.Encode({ id = "z", guild = "Olympus II", kind = "Q", target = "176", level = 11, need = "012", size = 1, every = 5, age = 0,
		title = "Kill Hogger", zone = "Elwynn |cffff0000Forest~" .. string.rep("x", 40) }))
	eq(e.every, 5); eq(#e.zone, 30); assert(e.zone:find("^Elwynn cffff0000Forest"), e.zone)
	eq(G.Decode("GL~a~Olympus II~D~DM~18~PR~113~1~~Elwynn~10~0~~").zone, "", "a dungeon has no zone")
	eq(G.Decode("GL~a~Olympus II~D~DM~18~PR~113~1~~~4~0~~"), nil, "every 4: too often")
	eq(G.NeedShort("113"), "1T 1H 3D"); eq(G.NeedShort("0++"), "H+ D+"); eq(G.NeedShort("000"), ns.L.GROUPS_FULL)
	-- Who else is in a group (GM): names, classes, roles when known; a raid's past 250 bytes counted.
	local m = G.DecodeMembers(G.EncodeMembers("a7", { { name = "Brenna Stoutheart-Realm", class = "PR", role = "H" }, { name = "Cora-Other", class = "MA" } }))
	eq(m.id, "a7"); eq(m.more, 0); eq(#m.members, 2)
	eq(m.members[1].name, "Brenna Stoutheart-Realm"); eq(m.members[1].role, "H"); eq(m.members[2].role, nil); eq(m.members[2].class, "MA")
	local many = {}
	for i = 1, 39 do many[i] = { name = ("Raider Number%02d-SomeLongRealm"):format(i), class = "WA", role = "D" } end
	local gm = G.EncodeMembers("zz", many)
	assert(#gm <= 250, "one message: " .. #gm)
	m = G.DecodeMembers(gm)
	eq(#m.members + m.more, 39, "every name listed or counted")
	assert(m.more > 0)
	eq(G.EncodeMembers("a7", { { name = "Bad~Name,x:y|z", class = "PR" } }), "GM~a7~0~BadNamexyz:PR:", "no separator travels in a name")
	eq(G.DecodeMembers("GM~a7~0~Name:Pr:"), nil); eq(G.DecodeMembers("GM~a7~0~Name:PR:X"), nil); eq(G.DecodeMembers("GM~a7~x~"), nil)
	eq(#G.DecodeMembers("GM~a7~0~").members, 0, "nobody else: the list emptied")
	-- The longest it gets: one message.
	local worst = G.Encode({ id = "zz", guild = string.rep("\195\169", 24), kind = "Q", target = "9999999", level = 60, class = "WA", need = "+++",
		size = 40, min = 60, zone = string.rep("\195\169", 15), every = 30, age = 29, title = string.rep("\195\169", 30), note = string.rep("\195\169", 30) })
	assert(#worst <= 250, "one message: " .. #worst)
	assert(G.Decode(worst), "the longest decodes")
	-- An application: a role, the applicant's level and class, a note.
	local a = G.DecodeApply(G.EncodeApply("a7", "Olympus Zeus", "H", 31, "PR", "|cff00ff00hi~"))
	eq(a.role, "H"); eq(a.level, 31); eq(a.note, "cff00ff00hi")
	eq(G.DecodeApply("GA~a7~Olympus Zeus~X~31~PR~"), nil, "no such role")
	eq(G.DecodeApply("GA~a7~~T~31~PR~"), nil, "no guild")
	-- What a need says.
	eq(G.NeedText("113"), "Tank, Healer, Damage x3")
	eq(G.NeedText("0++"), "Healer +, Damage +")
	eq(G.NeedText("000"), ns.L.GROUPS_NEED_NONE)
	-- A 1.1 client's Board reads none of it: GL is no flag.
	eq(ns.Board.Decode(msg), nil)
end)

test("1.2 groups: the Board's strip; the flags page is as it was; a leader lists a dungeon group (where, roles, a note logged)", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		B.HandlePost("CHANNEL", "Aldric-Realm", ns.Board.Encode({ id = "f1", guild = "Olympus Zeus", flag = "R", level = 30, class = "WA", every = 10, age = 0, note = "lf raid" }))
		-- The Flags section first: the strip, then the Board's page as before.
		local lines = B.Lines()
		assert(lines[2].nav, "the strip under the way back")
		eq(#lines[2].nav, 5); eq(lines[2].nav[1].text, ns.L.GROUPS_TAB_FLAGS); eq(lines[2].nav[1].selected, true)
		assert(Line(lines, "lf raid"), "the flags as before")
		assert(Line(lines, ns.L.BOARD_RAISE:format(ns.L.BOARD_FLAG_D)), "raising a flag as before")
		-- Dungeons: nothing listed; the way to list one.
		lines[2].nav[2].onClick()
		eq(G.View(), "D")
		lines = B.Lines()
		assert(not Line(lines, "lf raid"), "no flags here")
		assert(Line(lines, ns.L.GROUPS_EMPTY), Texts(lines))
		Line(lines, ns.L.GROUPS_LIST:format(ns.L.GROUPS_KIND_D)).onClick()
		-- Where: the dungeons, by level.
		lines = B.Lines()
		local dm = Line(lines, "> Deadmines")
		assert(dm and dm.right:find(ns.L.GROUPS_FROM_LEVEL:format(16), 1, true), Texts(lines))
		assert(not Line(lines, "Molten Core"), "no raid among the dungeons")
		dm.onClick()
		-- The roles: a click steps each one; damage from 3 to 4, then round to 0 and 1.
		lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_WHERE:format("|cffffd200Deadmines|r")), Texts(lines))
		local dmg = Line(lines, ns.L.GROUPS_WANTED:format(ns.L.GROUPS_ROLE_D, "|cffffd2003|r"))
		assert(dmg, Texts(lines))
		dmg.onClick(); dmg.onClick(); dmg.onClick()
		eq(G.Composing().need, "111")
		Line(B.Lines(), ns.L.GROUPS_WANTED:format(ns.L.GROUPS_ROLE_T, "|cffffd2001|r")).onClick()
		eq(G.Composing().need, "211")
		-- Post: the dialog says what goes out and to whom, before anything does.
		eq(#w.sent, 0, "nothing sent while composing")
		Line(B.Lines(), ns.L.GROUPS_POST).onClick()
		local p = w.popups[#w.popups]
		eq(p.name, "OLYMPUS_GROUPS_LIST")
		assert(p.a:find("Deadmines", 1, true) and p.a:find(ns.L.GROUPS_NEEDS:format("Tank x2, Healer, Damage"), 1, true), p.a)
		eq(p.b, ns.Comm.Audience())
		G.ConfirmList(p.data, "  bring |cffffffffwater ")
		G.ConfirmList(p.data, "twice") -- (Enter and the button both answer: once)
		local s = Sent(w, "GL~")
		eq(s.dist, "CHANNEL"); eq(s.logged, true, "a note goes logged")
		local e = G.Decode(s.msg)
		eq(e.kind, "D"); eq(e.target, "DM"); eq(e.need, "211"); eq(e.note, "bring cffffffffwater"); eq(e.guild, "Olympus II"); eq(e.size, 1)
		eq(#w.sent, 1, "one listing")
		eq(G.Mine().id, e.id)
		lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_MINE:format("Deadmines")), Texts(lines))
		assert(Line(lines, ns.L.GROUPS_NO_APPLICANTS))
		-- Raids say ours is under Dungeons.
		G.Show("R", true)
		assert(Line(B.Lines(), ns.L.GROUPS_MINE_ELSEWHERE:format(ns.L.GROUPS_KIND_D)))
		-- A second listing waits LIST_GAP; one without a note goes plain.
		eq(select(2, G.Post("R", "MC", nil, "+++", "")), "wait")
		w.clock = w.clock + G.LIST_GAP
		assert(G.Post("R", "MC", nil, "+++", ""))
		eq(w.sent[#w.sent - 1].msg, "GX~" .. e.id, "the old one comes down first")
		eq(w.sent[#w.sent].logged, false)
		eq(G.Mine().kind, "R")
	end)
end)

test("1.2 groups: others' listings on the Board, by kind; only Olympus guilds, never an ignored or netted-off player; lowered at once", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		G.HandlePost("CHANNEL", "Aldric-Realm", Listing("a1", "Olympus Zeus", "D", "SFK", "103", 2, "lfm sfk"))
		G.HandlePost("CHANNEL", "Brenna-Realm", Listing("b1", "Olympus Zeus", "R", "MC", "+++", 0))
		G.HandlePost("CHANNEL", "Outsider-Realm", Listing("c1", "Horde Guild", "D", "DM"))
		G.HandlePost("CHANNEL", "Troll-Realm", Listing("t1", "Olympus Zeus", "D", "DM"))
		G.HandlePost("GUILD", "Cora-Realm", Listing("g1", "Olympus Zeus", "D", "DM"))
		G.HandlePost("WHISPER", "Dora-Realm", Listing("d1", "Olympus Zeus", "D", "DM"))
		eq(#G.List("D"), 1); eq(#G.List("R"), 1); eq(#G.List(), 2)
		G.Show("D", true)
		local lines = B.Lines()
		-- (1.2 review: the row holds where and who; what it needs, short, on the right where it is never
		-- cut; the rest, the note too, in its tooltip and its card.)
		local card = Line(lines, "[Shadowfang Keep]")
		assert(card, Texts(lines))
		assert(card.text:find("Aldric", 1, true), card.text)
		assert(card.right:find("1T 3D", 1, true) and card.right:find("2/5", 1, true), card.right)
		local tip = Tip(card)
		assert(tip:find(ns.L.GROUPS_NEEDS:format("Tank, Damage x3"), 1, true) and tip:find("lfm sfk", 1, true), tip)
		eq(lines[2].nav[2].text, ns.L.GROUPS_TAB_D .. " (1)")
		eq(lines[2].nav[3].text, ns.L.GROUPS_TAB_R .. " (1)")
		-- The Realm's link counts them.
		assert(B.LinkLine().right:find(ns.L.GROUPS_LINK:format(2), 1, true))
		-- The search reads where, who and the note.
		assert(Line(B.Lines(ns.Fold("shadowfang")), "[Shadowfang Keep]"))
		assert(Line(B.Lines(ns.Fold("lfm")), "[Shadowfang Keep]"), "the note is searched though not shown on the row")
		assert(not Line(B.Lines(ns.Fold("molten")), "[Shadowfang Keep]"))
		-- A refresh updates it in place; its words without the logged API are dropped.
		w.logged = false
		G.HandlePost("CHANNEL", "Aldric-Realm", Listing("a1", "Olympus Zeus", "D", "SFK", "003", 3, "lfm sfk"))
		eq(G.List("D")[1].need, "003"); eq(G.List("D")[1].note, "")
		w.logged = true
		-- Lowered: gone, and a late refresh of it doesn't bring it back.
		G.HandleLower("CHANNEL", "Aldric-Realm", "GX~a1")
		eq(#G.List("D"), 0)
		G.HandlePost("CHANNEL", "Aldric-Realm", Listing("a1", "Olympus Zeus", "D", "SFK", "003", 4))
		eq(#G.List("D"), 0, "a lowered id stays down")
		-- Its hour over, a listing leaves; a quest's after half an hour.
		G.HandlePost("CHANNEL", "Cora-Realm", Listing("q1", "Olympus Zeus", "Q", "555", "012", 25, nil, "Kill Hogger"))
		eq(#G.List("Q"), 1)
		w.clock = w.clock + 6 * 60
		eq(#G.List("Q"), 0, "half an hour for a quest")
		eq(#G.List("R"), 1)
		w.clock = w.clock + 55 * 60
		eq(#G.List("R"), 0, "an hour for the rest, refreshed or not")
	end)
end)

test("1.2 groups: apply with a role the group needs (the note logged, to the leader alone); withdraw; the leader's answers", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		G.HandlePost("CHANNEL", "Aldric-Realm", Listing("a1", "Olympus Zeus", "D", "SFK", "103", 0))
		G.Show("D", true)
		Line(B.Lines(), "Shadowfang Keep").onClick()
		local lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_APPLY_AS:format(ns.L.GROUPS_ROLE_T)), Texts(lines))
		assert(not Line(lines, ns.L.GROUPS_APPLY_AS:format(ns.L.GROUPS_ROLE_H)), "no healer wanted: no healer's button")
		Line(lines, ns.L.GROUPS_WHISPER:format("Aldric")).onClick()
		eq(w.told[#w.told], "Aldric", "the whisper is the player's own")
		eq(#w.whispered, 0)
		Line(lines, ns.L.GROUPS_APPLY_AS:format(ns.L.GROUPS_ROLE_T)).onClick()
		local p = w.popups[#w.popups]
		eq(p.name, "OLYMPUS_GROUPS_APPLY")
		eq(p.a, ns.L.GROUPS_APPLY_WHAT:format(ns.L.GROUPS_ROLE_T, "Shadowfang Keep", "Aldric"))
		G.ConfirmApply(p.data, "prot war, 25")
		local wh = LastWhisper(w)
		eq(wh.to, "Aldric-Realm"); eq(wh.logged, true)
		local a = G.DecodeApply(wh.msg)
		eq(a.id, "a1"); eq(a.role, "T"); eq(a.guild, "Olympus II"); eq(a.note, "prot war, 25"); eq(a.level, 42); eq(a.class, "PR")
		eq(#w.sent, 0, "nothing on the channel")
		lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_APP_SENT:format(ns.L.GROUPS_ROLE_T)), Texts(lines))
		-- A role the group doesn't need is refused; so is a second application too soon.
		eq(select(2, G.Apply("Aldric-Realm", "H")), "role")
		eq(select(2, G.Apply("Aldric-Realm", "D")), "wait")
		-- An answer from anyone but that leader, or for another listing, changes nothing.
		G.HandleAnswer("WHISPER", "Brenna-Realm", "GR~a1~I")
		G.HandleAnswer("WHISPER", "Aldric-Realm", "GR~zz~I")
		G.HandleAnswer("CHANNEL", "Aldric-Realm", "GR~a1~I")
		eq(G.Applied("Aldric-Realm").state, "sent")
		G.HandleAnswer("WHISPER", "Aldric-Realm", "GR~a1~I")
		eq(G.Applied("Aldric-Realm").state, "invited")
		assert(Line(B.Lines(), ns.L.GROUPS_APP_INVITED:format(ns.L.GROUPS_ROLE_T)))
		-- Withdrawn: the leader is told.
		Line(B.Lines(), ns.L.GROUPS_WITHDRAW).onClick()
		eq(LastWhisper(w).msg, "GW~a1"); eq(G.Applied("Aldric-Realm"), nil)
		-- Declined, and a listing lowered, end an application.
		w.clock = w.clock + G.APPLY_GAP
		assert(G.Apply("Aldric-Realm", "D"))
		G.HandleAnswer("WHISPER", "Aldric-Realm", "GR~a1~D")
		eq(G.Applied("Aldric-Realm"), nil)
		w.clock = w.clock + G.APPLY_GAP
		assert(G.Apply("Aldric-Realm", "D"))
		G.HandleLower("CHANNEL", "Aldric-Realm", "GX~a1")
		eq(G.Applied("Aldric-Realm"), nil)
		-- Five applications waiting at most.
		for i = 1, 6 do
			G.HandlePost("CHANNEL", "Lead" .. i .. "-Realm", Listing("l" .. i, "Olympus Zeus", "D", "DM", "113", 0))
		end
		for i = 1, 5 do assert(G.Apply("Lead" .. i .. "-Realm", "D")) end
		eq(select(2, G.Apply("Lead6-Realm", "D")), "many")
	end)
end)

test("1.2 groups: the leader's applicants (a sound, details on hover); Invite as their role is the game's invite by click; the role comes off when they join, back when they don't; the last role closes the listing", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		assert(G.Post("D", "DM", nil, "112", "lfm"))
		local id = G.Mine().id
		G.HandleApply("WHISPER", "Aldric-Realm", G.EncodeApply(id, "Olympus Zeus", "T", 20, "WA", "prot"))
		G.HandleApply("WHISPER", "Brenna-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 19, "MA", ""))
		G.HandleApply("WHISPER", "Cora-Realm", G.EncodeApply(id, "Olympus Zeus", "H", 18, "PR", ""))
		-- Not for this listing, not whispered, not of an Olympus guild, ignored: nothing.
		G.HandleApply("WHISPER", "Dora-Realm", G.EncodeApply("zz", "Olympus Zeus", "D", 19, "MA", ""))
		G.HandleApply("CHANNEL", "Dora-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 19, "MA", ""))
		G.HandleApply("WHISPER", "Dora-Realm", G.EncodeApply(id, "Horde Guild", "D", 19, "MA", ""))
		G.HandleApply("WHISPER", "Troll-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 19, "MA", ""))
		eq(#G.Applicants(), 3)
		eq(w.sounds, 3, "a sound for each new applicant")
		G.HandleApply("WHISPER", "Aldric-Realm", G.EncodeApply(id, "Olympus Zeus", "T", 20, "WA", "prot"))
		eq(w.sounds, 3, "none for the same one again")
		G.Show("D", true)
		local lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_APPLICANTS:format(3)), Texts(lines))
		local tank = Line(lines, "Aldric")
		assert(tank and tank.text:find(ns.L.GROUPS_ROLE_T, 1, true), Texts(lines))
		local tip = Tip(tank)
		assert(tip:find(ns.L.GROUPS_ROLE_T, 1, true) and tip:find("Olympus Zeus", 1, true) and tip:find("prot", 1, true), tip)
		-- Nothing invites until the leader clicks Invite as their role.
		eq(#w.invited, 0)
		tank.onClick()
		lines = B.Lines()
		Line(lines, "> " .. ns.L.GROUPS_INVITE_AS:format(ns.L.GROUPS_ROLE_T)).onClick()
		eq(w.invited[1], "Aldric")
		eq(LastWhisper(w).to, "Aldric-Realm"); eq(LastWhisper(w).msg, "GR~" .. id .. "~I")
		eq(G.Mine().need, "112", "not before they join")
		assert(Line(B.Lines(), ns.L.GROUPS_PENDING:format("Aldric", ns.L.GROUPS_ROLE_T)), Texts(B.Lines()))
		-- He joins: the tank comes off, his application is done, the listing goes out again.
		w.party = { { "Aldric", "", "WARRIOR" } }
		G.CheckJoins()
		eq(G.Mine().need, "012", "the tank is found")
		eq(#G.Applicants(), 2)
		w.clock = w.clock + G.UPDATE_GAP
		G.Tick()
		eq(G.Decode(Sent(w, "GL~").msg).need, "012", "every Board hears it")
		-- His role shows in our roster; a click changes it (a role switch), and the leader edits the need.
		local row = Line(B.Lines(), "Aldric")
		eq(row.right, "|cff40ff40" .. ns.L.GROUPS_ROLE_T .. "|r")
		row.onClick()
		eq(G.GroupMembers()[1].role, "H")
		Line(B.Lines(), ns.L.GROUPS_WANTED:format(ns.L.GROUPS_ROLE_T, "|cffffd2000|r")).onClick()
		eq(G.Mine().need, "112", "the leader wants a tank again")
		Line(B.Lines(), ns.L.GROUPS_WANTED:format(ns.L.GROUPS_ROLE_H, "|cffffd2001|r")).onClick()
		eq(G.Mine().need, "122")
		G.StepOwnNeed("H"); G.StepOwnNeed("H"); G.StepOwnNeed("H")
		eq(G.Mine().need, "102", "round to 0")
		G.StepOwnNeed("T")
		eq(G.Mine().need, "202")
		G.StepOwnNeed("T"); G.StepOwnNeed("T"); G.StepOwnNeed("T")
		eq(G.Mine().need, "002")
		G.Mine().need = "012"
		-- Declined: told, and off the list.
		G.Decline("Brenna-Realm")
		eq(LastWhisper(w).msg, "GR~" .. id .. "~D")
		eq(#G.Applicants(), 1, "Aldric joined, Brenna declined: Cora waits")
		-- Not the group's leader: no invite, and the player is told why.
		w.members, w.notLeader = 2, true
		eq(select(2, G.Invite("Cora-Realm")), "leader")
		eq(#w.invited, 1)
		w.members, w.notLeader = nil, false
		-- Cora is invited and never comes: two minutes later her role is wanted again, her application waits.
		G.Invite("Cora-Realm")
		w.clock = w.clock + G.INVITE_WAIT
		G.CheckJoins()
		eq(G.Mine().need, "012"); eq(G.Pending()["Cora-Realm"], nil)
		assert(w.printed[#w.printed]:find(ns.L.GROUPS_NOT_JOINED:format("Cora", ns.L.GROUPS_ROLE_H), 1, true), w.printed[#w.printed])
		w.clock = w.clock + 1
		G.Invite("Cora-Realm")
		w.party = { { "Aldric", "", "WARRIOR" }, { "Cora", "", "PRIEST" } }
		G.CheckJoins()
		eq(G.Mine().need, "002")
		-- The last of them: the listing closes, its GX goes, and the ones still waiting are told.
		w.clock = w.clock + G.APPLY_GAP
		G.HandleApply("WHISPER", "Dora-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 19, "MA", ""))
		G.HandleApply("WHISPER", "Eda-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 19, "MA", ""))
		G.HandleApply("WHISPER", "Finn-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 19, "MA", ""))
		G.Invite("Dora-Realm"); G.Invite("Eda-Realm")
		assert(G.Mine(), "still listed while they haven't joined")
		w.party = { { "Aldric", "", "WARRIOR" }, { "Cora", "", "PRIEST" }, { "Dora", "", "MAGE" } }
		G.CheckJoins()
		eq(G.Mine().need, "001")
		w.party = { { "Aldric", "", "WARRIOR" }, { "Cora", "", "PRIEST" }, { "Dora", "", "MAGE" }, { "Eda", "", "MAGE" } }
		G.CheckJoins()
		eq(G.Mine(), nil, "every role found: lowered")
		eq(Sent(w, "GX~").msg, "GX~" .. id)
		eq(LastWhisper(w).to, "Finn-Realm"); eq(LastWhisper(w).msg, "GR~" .. id .. "~F")
		-- A party of five, however it filled, takes its listing down; a raid's doesn't.
		w.clock = w.clock + G.LIST_GAP
		w.party = {}
		w.members = 4
		assert(G.Post("D", "DM", nil, "001", ""))
		G.Tick()
		assert(G.Mine(), "four: still listed")
		w.members = 5
		G.Tick()
		eq(G.Mine(), nil, "five: lowered")
		w.clock = w.clock + G.LIST_GAP
		assert(G.Post("R", "MC", nil, "+++", ""))
		G.Tick()
		assert(G.Mine(), "a raid of five goes on")
	end)
end)

test("1.2 groups: the Board's ask is answered with our listing; it survives a /reload; it ends after its hour; /oly group", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		assert(G.Post("R", "MC", nil, "+++", ""))
		local id = G.Mine().id
		-- Someone opens the Board: holders answer with their flag, and ours with the listing.
		B.HandleAsk("CHANNEL", "Asker-Realm", "GQ~")
		for _, t in ipairs(w.later) do if t.where == "board answer" then t.fn() end end
		local wh = LastWhisper(w)
		eq(wh.to, "Asker-Realm"); eq(G.Decode(wh.msg).id, id)
		-- A whispered listing is taken only after our own ask.
		G.HandlePost("WHISPER", "Brenna-Realm", Listing("b1", "Olympus Zeus", "D", "DM"))
		eq(#G.List("D"), 0)
		ns.Comm.joinedAt = w.clock - 60
		assert(B.Ask())
		G.HandlePost("WHISPER", "Brenna-Realm", Listing("b1", "Olympus Zeus", "D", "DM"))
		eq(#G.List("D"), 1)
		-- A /reload keeps our listing and its applicants.
		G.HandleApply("WHISPER", "Aldric-Realm", G.EncodeApply(id, "Olympus Zeus", "H", 60, "PR", "hi"))
		local saved = ns.rdb.groups
		G.Reset()
		ns.rdb.groups = saved
		G.Restore()
		eq(G.Mine().id, id); eq(#G.Applicants(), 1); eq(G.Applicants()[1].note, "hi")
		-- Repeated every interval, lowered after its hour.
		local before = #w.sent
		w.clock = w.clock + 10 * 60
		G.Tick()
		eq(#w.sent, before + 1)
		w.clock = w.clock + 50 * 60
		G.Tick()
		eq(G.Mine(), nil)
		eq(w.sent[#w.sent].msg, "GX~" .. id)
		-- /oly group opens the Board on a kind; off lowers ours.
		B.Slash("group", "raid")
		eq(G.View(), "R"); eq(ns.Views.BoardShown(), true)
		B.Slash("lfg", "")
		eq(G.View(), "flags", "/oly lfg: the flags")
		B.Slash("group", "off")
		B.Slash("group", "nonsense")
		assert(w.printed[#w.printed]:find("/oly group", 1, true), w.printed[#w.printed])
		G.Show("flags", true)
	end)
end)

test("1.2 groups: a quest from our own log, its title with it; quests we have come first", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		w.quests = { { title = "Elwynn Forest", header = true }, { title = "Kill Hogger", level = 11, id = 176, group = 3 },
			{ title = "Wolves Across the Border", level = 6, id = 33 } }
		G.Show("Q", true)
		Line(B.Lines(), ns.L.GROUPS_LIST:format(ns.L.GROUPS_KIND_Q)).onClick()
		local lines = B.Lines()
		assert(not Line(lines, "> Elwynn Forest"), "a header is no quest")
		local hogger = Line(lines, "> Kill Hogger")
		assert(hogger and hogger.right:find(ns.L.GROUPS_GROUP_QUEST, 1, true), Texts(lines))
		hogger.onClick()
		Line(B.Lines(), ns.L.GROUPS_POST).onClick()
		G.ConfirmList(w.popups[#w.popups].data, "")
		local s = Sent(w, "GL~")
		eq(s.logged, true, "a title is words: logged")
		local e = G.Decode(s.msg)
		eq(e.target, "176"); eq(e.title, "Kill Hogger")
		-- Others' quests: the ones in our log first, marked.
		G.HandlePost("CHANNEL", "Aldric-Realm", Listing("a1", "Olympus Zeus", "Q", "999", "012", 0, nil, "Other Quest"))
		w.clock = w.clock + 1
		G.HandlePost("CHANNEL", "Brenna-Realm", Listing("b1", "Olympus Zeus", "Q", "33", "012", 0, nil, "Wolves Across the Border"))
		local list = G.List("Q")
		eq(list[1].sender, "Brenna-Realm")
		assert(G.Card(list[1]).text:find(ns.L.GROUPS_IN_LOG, 1, true))
		assert(not G.Card(list[2]).text:find(ns.L.GROUPS_IN_LOG, 1, true))
	end)
end)

test("1.2 groups: English and Portuguese for every string; the help names /oly group", function()
	local pt = {}
	local saved = GetLocale
	GetLocale = function() return "ptBR" end
	local ok, err = pcall(function() assert(loadfile(H.ADDON_DIR .. "Locales.lua"))("Olympus", pt) end)
	GetLocale = saved
	if not ok then error(err, 0) end
	local n = 0
	for key, en in pairs(ns.L) do
		if type(key) == "string" and key:find("^GROUPS_") then
			n = n + 1
			local br = rawget(pt.L, key)
			assert(type(en) == "string" and en ~= "", "English " .. key)
			assert(type(br) == "string" and br ~= "", "pt-BR " .. key)
			local function Args(s) local out = {} for a in s:gmatch("%%%a") do out[#out + 1] = a end return table.concat(out) end
			eq(Args(br), Args(en), key .. ": format arguments")
		end
	end
	assert(n > 60, "the strings: " .. n)
	assert(ns.L.HELP_GROUPS:find("/oly group", 1, true))
end)

test("1.2 groups: a minimum level: the composer starts at the place's own, a click steps it; under it no apply, and the leader takes none", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		G.Show("D", true)
		G.Compose("D")
		G.ChooseTarget("SM")
		eq(G.Composing().min, 30, "Scarlet Monastery's own level")
		local line = Line(B.Lines(), ns.L.GROUPS_MIN_LINE:format("|cffffd20030|r"))
		assert(line, Texts(B.Lines()))
		line.onClick()
		eq(G.Composing().min, 35)
		for _ = 1, 7 do G.StepMin() end -- (40, 45, 50, 55, 58, 60, then none)
		eq(G.Composing().min, nil, "past 60: none")
		G.StepMin()
		eq(G.Composing().min, 10)
		G.Composing().min = 40
		Line(B.Lines(), ns.L.GROUPS_POST).onClick()
		local p = w.popups[#w.popups]
		assert(p.a:find(ns.L.GROUPS_MIN_TIP:format(40), 1, true), p.a)
		G.ConfirmList(p.data, "")
		eq(G.Decode(Sent(w, "GL~").msg).min, 40)
		-- A level 41 applicant is taken; a level 39 one isn't (its addon would have refused it).
		local id = G.Mine().id
		G.HandleApply("WHISPER", "Low-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 39, "WA", ""))
		G.HandleApply("WHISPER", "High-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 41, "WA", ""))
		eq(#G.Applicants(), 1); eq(G.Applicants()[1].name, "High-Realm")
		-- Someone else's group from level 50: the card says so, and we (42) can't apply.
		G.HandlePost("CHANNEL", "Aldric-Realm", G.Encode({ id = "a1", guild = "Olympus Zeus", kind = "D", target = "BRD", level = 55, class = "WA",
			need = "113", size = 1, min = 50, every = 10, age = 0 }))
		local card = Line(B.Lines(), "[Blackrock Depths]")
		assert(card.right:find(ns.L.GROUPS_MIN_SHORT:format(50), 1, true), card.right)
		assert(Tip(card):find(ns.L.GROUPS_MIN_TIP:format(50), 1, true))
		card.onClick()
		local lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_TOO_LOW:format(50)), Texts(lines))
		assert(not Line(lines, ns.L.GROUPS_APPLY_AS:format(ns.L.GROUPS_ROLE_T)), "no apply under the minimum")
		local before = #w.whispered
		eq(select(2, G.Apply("Aldric-Realm", "T")), "level")
		eq(#w.whispered, before, "nothing sent")
	end)
end)

test("1.2 groups: a quest by a typed name (an elite, a rare): its dialog, then the roles; it travels as quest 0 with the name", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		G.Show("Q", true)
		Line(B.Lines(), ns.L.GROUPS_LIST:format(ns.L.GROUPS_KIND_Q)).onClick()
		local lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_NO_QUESTS), "an empty log says so")
		Line(lines, ns.L.GROUPS_TYPE_NAME).onClick()
		local p = w.popups[#w.popups]
		eq(p.name, "OLYMPUS_GROUPS_NAME")
		eq(G.ConfirmName(p.data, "   "), nil, "no name: still choosing")
		p.data.answered = nil
		G.ConfirmName(p.data, "Mor'Ladim |cff00ff00now")
		eq(G.Composing().target, "0"); eq(G.Composing().title, "Mor'Ladim cff00ff00now"); eq(G.Composing().min, nil, "no minimum for a quest")
		Line(B.Lines(), ns.L.GROUPS_POST).onClick()
		G.ConfirmList(w.popups[#w.popups].data, "")
		local s = Sent(w, "GL~")
		eq(s.logged, true)
		local e = G.Decode(s.msg)
		eq(e.target, "0"); eq(e.title, "Mor'Ladim cff00ff00now")
		eq(select(2, G.Post("Q", "0", "", "012", "")), "target", "never without a name")
		-- On another Board it shows by its name, and is never "in your log".
		G.HandlePost("CHANNEL", "Aldric-Realm", (s.msg:gsub("Olympus II", "Olympus Zeus")))
		local card = G.Card(G.List("Q")[1])
		assert(card.text:find("[Mor'Ladim cff00ff00now]", 1, true) and not card.text:find(ns.L.GROUPS_IN_LOG, 1, true), card.text)
	end)
end)

test("1.2 groups: who is in a listed group: the leader's GM after the listing, with the roles he invited; on hover; again when it changes", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		assert(G.Post("D", "DM", nil, "113", ""))
		eq(Sent(w, "GM~"), nil, "alone: no GM")
		local id = G.Mine().id
		G.HandleApply("WHISPER", "Brenna Stoutheart-Realm", G.EncodeApply(id, "Olympus Zeus", "H", 20, "PR", ""))
		G.Invite("Brenna Stoutheart-Realm")
		-- She and a friend from the chat join; the next tick sends the listing and who is in it.
		w.party = { { "Brenna Stoutheart", "", "PRIEST" }, { "Cora", "Other", "MAGE" } }
		w.clock = w.clock + G.UPDATE_GAP
		G.Tick()
		local gm = Sent(w, "GM~")
		assert(gm, "a GM")
		eq(gm.logged, nil, "names, not words")
		local m = G.DecodeMembers(gm.msg)
		eq(m.id, id); eq(#m.members, 2)
		eq(m.members[1].name, "Brenna Stoutheart-Realm"); eq(m.members[1].role, "H"); eq(m.members[1].class, "PR")
		eq(m.members[2].name, "Cora-Other"); eq(m.members[2].role, nil); eq(m.members[2].class, "MA")
		eq(G.Decode(Sent(w, "GL~").msg).size, 3)
		-- Another Board shows them in the card's tooltip.
		local gl = Sent(w, "GL~").msg
		-- (A reader of another Olympus guild: the leader's guild by its claim.)
		GetGuildInfo = function() return "Olympus Zeus", "Member", 3 end
		ns.me = "Reader-Realm"
		G.HandleMembers("CHANNEL", "Soldier-Realm", gm.msg)
		eq(#G.List("D"), 0, "a GM before its listing is nothing")
		G.HandlePost("CHANNEL", "Soldier-Realm", gl)
		G.HandleMembers("GUILD", "Soldier-Realm", gm.msg)
		G.HandleMembers("CHANNEL", "Other-Realm", gm.msg)
		eq(G.List("D")[1].members, nil, "only its leader's, only on the channel")
		G.HandleMembers("CHANNEL", "Soldier-Realm", gm.msg)
		G.Show("D", true)
		local tip = Tip(Line(B.Lines(), "[Deadmines]"))
		assert(tip:find(ns.L.GROUPS_IN_GROUP, 1, true) and tip:find("Brenna Stoutheart", 1, true) and tip:find(ns.L.GROUPS_ROLE_H, 1, true)
			and tip:find("Cora-Other", 1, true), tip)
		-- An ignored name is left out.
		G.HandleMembers("CHANNEL", "Soldier-Realm", G.EncodeMembers(id, { { name = "Troll-Realm", class = "WA" } }))
		eq(#G.List("D")[1].members, 0)
		-- Back on the leader's client: Cora leaves; the GM goes again, she isn't in it.
		AsSoldier()
		w.party = { { "Brenna Stoutheart", "", "PRIEST" } }
		w.clock = w.clock + 30
		G.Tick()
		w.clock = w.clock + G.UPDATE_GAP
		G.Tick()
		m = G.DecodeMembers(Sent(w, "GM~").msg)
		eq(#m.members, 1)
		-- The Board's ask is answered with the GM too.
		B.HandleAsk("CHANNEL", "Asker-Realm", "GQ~")
		for _, t in ipairs(w.later) do if t.where == "board answer" then t.fn() end end
		eq(LastWhisper(w).to, "Asker-Realm"); assert(LastWhisper(w).msg:find("^GM~"), LastWhisper(w).msg)
	end)
end)

test("1.2 flags for several places: roles and picks after the note (a 1.1 Board reads the plain flag); matching players in each group section", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		-- The composer on the flags page: roles, then places by kind, Any for a whole kind.
		local lines = B.Lines()
		Line(lines, ns.L.GROUPS_FLAG_MULTI).onClick()
		lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_FLAG_PICK_ONE), "nothing to raise yet")
		assert(not Line(lines, ns.L.BOARD_RAISE:format(ns.L.BOARD_FLAG_D)), "the one-click flags wait")
		G.FlagRole("T"); G.FlagRole("H")
		Line(B.Lines(), "+ " .. ns.L.GROUPS_TAB_D).onClick()
		Line(B.Lines(), "Shadowfang Keep").onClick()
		Line(B.Lines(), "Deadmines").onClick()
		G.FlagOpen("P")
		Line(B.Lines(), ns.L.GROUPS_ANY_P).onClick()
		-- Eight places at most.
		G.FlagOpen("R")
		for _, key in ipairs({ "ZG", "AQ20", "MC", "ONY", "BWL", "AQ40", "NAXX" }) do G.FlagPick("R", key) end
		assert(w.printed[#w.printed]:find(ns.L.GROUPS_FLAG_PICKS_MAX:format(8), 1, true), w.printed[#w.printed])
		G.FlagPick("R", "*")
		G.FlagPick("R", "*")
		Line(B.Lines(), ns.L.GROUPS_FLAG_RAISE).onClick()
		local p = w.popups[#w.popups]
		eq(p.name, "OLYMPUS_BOARD_RAISE")
		eq(p.a, "Deadmines, Shadowfang Keep, " .. ns.L.GROUPS_ANY_P .. "  (" .. ns.L.GROUPS_ROLE_T .. ", " .. ns.L.GROUPS_ROLE_H .. ")")
		B.Confirm(p.data, "any time tonight")
		local s = Sent(w, "G1~")
		local plain = B.Encode({ id = B.Mine().id, guild = "Olympus II", flag = "D", level = 42, class = "PR", every = s.msg:match("^G1~[^~]*~[^~]*~[^~]*~[^~]*~[^~]*~(%d+)"),
			age = 0, note = "any time tonight" })
		eq(s.msg, plain .. "~TH~D:DM,SFK;P:*", "the flag as before, then its roles and picks")
		eq(G.FlagComposing(), false, "raised: the composer closes")
		assert(Line(B.Lines(), ns.L.BOARD_MINE:format("Deadmines, Shadowfang Keep, " .. ns.L.GROUPS_ANY_P)), Texts(B.Lines()))
		-- Read back: a flag with roles and picks; malformed ones are the plain flag.
		local e = B.Decode(s.msg)
		eq(e.flag, "D"); eq(e.roles, "TH"); eq(e.picks, "D:DM,SFK;P:*"); eq(e.note, "any time tonight")
		eq(B.Decode(plain .. "~TH~R:MC").picks, "", "its first pick must be its own kind")
		eq(B.Decode(plain .. "~XX~D:dm").roles, ""); eq(B.Decode(plain .. "~XX~D:dm").picks, "")
		eq(B.Decode(plain .. "~T~P:*;D:DM").picks, "", "kinds in order")
		eq(B.ParsePicks("D:A,B,C,D,E,F,G,H,I"), nil, "nine places")
		-- Someone else's: on the flags page by name and roles; in Dungeons and PvP, not in Raids.
		B.HandlePost("CHANNEL", "Aldric-Realm", s.msg:gsub("^G1~[^~]*", "G1~a1"):gsub("Olympus II", "Olympus Zeus"))
		B.HandlePost("CHANNEL", "Brenna-Realm", B.Encode({ id = "b1", guild = "Olympus Zeus", flag = "R", level = 60, class = "PR", every = 10, age = 0 }))
		local card = Line(B.Lines(), "Aldric")
		assert(card.text:find("[Deadmines, Shadowfang Keep, " .. ns.L.GROUPS_ANY_P .. "]", 1, true) and card.text:find(ns.L.GROUPS_ROLE_T .. ", " .. ns.L.GROUPS_ROLE_H, 1, true), card.text)
		eq(#G.Looking("D"), 1); eq(#G.Looking("P"), 1); eq(#G.Looking("R"), 1); eq(G.Looking("R")[1].sender, "Brenna-Realm", "a plain raid flag")
		eq(#G.Looking("Q"), 0)
		-- With our Deadmines group needing a tank, Aldric fits, first, and Invite is the game's invite.
		B.Lower(true)
		assert(G.Post("D", "DM", nil, "103", "", 16))
		G.Show("D", true)
		lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_LOOKING:format(1)), Texts(lines))
		local looking = Line(lines, "Aldric")
		assert(looking.text:find(ns.L.GROUPS_FITS, 1, true), looking.text)
		looking.onClick()
		Line(B.Lines(), "> " .. ns.L.GROUPS_INVITE).onClick()
		eq(w.invited[#w.invited], "Aldric")
		-- A Stockade group doesn't fit him (not among his dungeons); a raid section has no invite without a raid listed.
		eq(G.Fits(G.Looking("D")[1], { kind = "D", target = "STOCK", need = "103" }), false)
		eq(G.Fits(G.Looking("D")[1], { kind = "D", target = "DM", need = "003" }), false, "no role of his wanted")
		eq(G.Fits(G.Looking("D")[1], { kind = "D", target = "DM", need = "103", min = 50 }), false, "under the minimum")
		G.Show("R", true)
		Line(B.Lines(), "Brenna").onClick()
		eq(Line(B.Lines(), "> " .. ns.L.GROUPS_INVITE), nil)
		assert(Line(B.Lines(), ns.L.GROUPS_WHISPER:format("Brenna")))
		G.Show("flags", true)
	end)
end)

test("1.2 groups: our own group shows in the list, marked, with its card and our roster on hover; someone else's card in full; the notices", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		assert(G.Post("D", "SFK", nil, "103", "bring food", 18))
		w.party = { { "Brenna Stoutheart", "", "PRIEST" } }
		G.SetMemberRole("Brenna Stoutheart-Realm", "H")
		G.Show("D", true)
		local lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_UP:format(1)), "ours counts in the list")
		local mine = Line(lines, ns.L.GROUPS_YOUR_GROUP)
		assert(mine and mine.text:find("[Shadowfang Keep]", 1, true), Texts(lines))
		assert(mine.right:find("1T 3D", 1, true) and mine.right:find(ns.L.GROUPS_MIN_SHORT:format(18), 1, true) and mine.right:find("2/5", 1, true), mine.right)
		local tip = Tip(mine)
		assert(tip:find("bring food", 1, true) and tip:find(ns.L.GROUPS_IN_GROUP, 1, true) and tip:find("Brenna Stoutheart", 1, true)
			and tip:find(ns.L.GROUPS_ROLE_H, 1, true) and tip:find(ns.L.GROUPS_OWN_TIP, 1, true), tip)
		-- The Your group line has the same card on hover.
		assert(Tip(Line(lines, ns.L.GROUPS_MINE:format("Shadowfang Keep"))):find("Brenna Stoutheart", 1, true))
		mine.onClick()
		lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_MANAGE_ABOVE) and not Line(lines, ns.L.GROUPS_APPLY_AS:format(ns.L.GROUPS_ROLE_T)), Texts(lines))
		-- Someone else's group: its card has its leader, needs, minimum, note and members, then Apply.
		G.HandlePost("CHANNEL", "Aldric-Realm", G.Encode({ id = "a1", guild = "Olympus Zeus", kind = "D", target = "DM", level = 20, class = "WA",
			need = "011", size = 2, min = 16, every = 5, age = 0, note = "chill run" }))
		G.HandleMembers("CHANNEL", "Aldric-Realm", G.EncodeMembers("a1", { { name = "Cora-Realm", class = "MA", role = "D" } }))
		Line(B.Lines(), "[Deadmines]").onClick()
		lines = B.Lines()
		for _, want in ipairs({ ns.L.GROUPS_CARD_LEADER:format("Aldric", "Olympus Zeus"), ns.L.GROUPS_NEEDS:format("Healer, Damage"),
			ns.L.GROUPS_MIN_TIP:format(16), '"chill run"', ns.L.GROUPS_IN_GROUP, "Cora", ns.L.GROUPS_APPLY_AS:format(ns.L.GROUPS_ROLE_H) }) do
			assert(Line(lines, want), want .. "\n" .. Texts(lines))
		end
		-- The notices: in an instance, not our group's leader, a raid's party of five.
		local savedLocked = ns.ChatLocked
		ns.ChatLocked = function() return true end
		local before = #w.sent
		w.clock = w.clock + 10 * 60
		G.Tick()
		eq(#w.sent, before, "nothing goes from an instance")
		assert(Line(B.Lines(), ns.L.GROUPS_LOCKED))
		ns.ChatLocked = savedLocked
		G.Tick()
		eq(#w.sent > before, true, "it goes once we are out")
		w.notLeader = true
		assert(Line(B.Lines(), ns.L.GROUPS_NOT_LEADER))
		w.notLeader = false
		w.clock = w.clock + G.LIST_GAP
		assert(G.Post("R", "MC", nil, "+++", ""))
		G.Show("R", true)
		assert(not Line(B.Lines(), ns.L.GROUPS_CONVERT))
		w.party = { { "A", "", "MAGE" }, { "B", "", "MAGE" }, { "C", "", "MAGE" }, { "D", "", "MAGE" } }
		assert(Line(B.Lines(), ns.L.GROUPS_CONVERT), "five in a party: convert to a raid")
	end)
end)

test("1.2 groups: filters (I can join, in my log, my zone; players by fit and role); a flag's player invited as a role their flag names", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		G.HandlePost("CHANNEL", "Aldric-Realm", G.Encode({ id = "a1", guild = "Olympus Zeus", kind = "D", target = "BRD", level = 55, class = "WA",
			need = "113", size = 1, min = 50, every = 5, age = 0 }))
		G.HandlePost("CHANNEL", "Brenna-Realm", G.Encode({ id = "b1", guild = "Olympus Zeus", kind = "D", target = "SM", level = 40, class = "PR",
			need = "113", size = 1, min = 30, every = 5, age = 0 }))
		G.HandlePost("CHANNEL", "Cora-Realm", G.Encode({ id = "c1", guild = "Olympus Zeus", kind = "D", target = "RFC", level = 15, class = "MA",
			need = "000", size = 5, every = 5, age = 0 }))
		G.Show("D", true)
		local lines = B.Lines()
		local strip
		for _, l in ipairs(lines) do if l.id == "board-filter-D" then strip = l end end
		assert(strip and strip.nav[1].selected, "the filters, All first")
		strip.nav[2].onClick()
		eq(G.Filter("D"), "join")
		lines = B.Lines()
		assert(Line(lines, "[Scarlet Monastery]"), Texts(lines))
		assert(not Line(lines, "[Blackrock Depths]"), "level 50 and up: not us (42)")
		assert(not Line(lines, "[Ragefire Chasm]"), "full")
		-- Quests: in my log; my zone.
		w.quests = { { title = "Elwynn Forest", header = true }, { title = "Kill Hogger", level = 11, id = 176, group = 3 } }
		G.HandlePost("CHANNEL", "Dora-Realm", G.Encode({ id = "d1", guild = "Olympus Zeus", kind = "Q", target = "176", level = 12, class = "MA",
			need = "012", size = 1, every = 5, age = 0, title = "Kill Hogger", zone = "Elwynn Forest" }))
		G.HandlePost("CHANNEL", "Eda-Realm", G.Encode({ id = "e1", guild = "Olympus Zeus", kind = "Q", target = "0", level = 30, class = "MA",
			need = "012", size = 1, every = 5, age = 0, title = "Mor'Ladim", zone = "Duskwood" }))
		G.Show("Q", true)
		G.SetFilter("Q", "log")
		lines = B.Lines()
		assert(Line(lines, "[Kill Hogger]") and not Line(lines, "[Mor'Ladim]"), Texts(lines))
		local savedZone = GetRealZoneText
		GetRealZoneText = function() return "Duskwood" end
		G.SetFilter("Q", "zone")
		lines = B.Lines()
		assert(Line(lines, "[Mor'Ladim]") and not Line(lines, "[Kill Hogger]"), Texts(lines))
		GetRealZoneText = savedZone
		assert(Tip(Line(lines, "[Mor'Ladim]")):find(ns.L.GROUPS_ZONE:format("Duskwood"), 1, true))
		-- Players looking, by fit and role; invited as a role their flag names and we need.
		local function Flagged(id, name, roles, picks)
			B.HandlePost("CHANNEL", name, B.Encode({ id = id, guild = "Olympus Zeus", flag = "D", level = 40, class = "PR", every = 10, age = 0, roles = roles, picks = picks }))
		end
		Flagged("f1", "Tanky-Realm", "T", "D:SM")
		Flagged("f2", "Heals-Realm", "H", "D:*")
		Flagged("f3", "Quiet-Realm", "", nil)
		assert(G.Post("D", "SM", nil, "103", "", 30))
		G.Show("D", true)
		G.SetFilter("looking", "fits")
		lines = B.Lines()
		assert(Line(lines, "Tanky") and not Line(lines, "Heals") and not Line(lines, "Quiet"), Texts(lines))
		G.SetFilter("looking", "H")
		lines = B.Lines()
		assert(Line(lines, "Heals") and not Line(lines, "Tanky"), Texts(lines))
		G.SetFilter("looking", "all")
		eq(table.concat(G.InviteRoles(G.Looking("D")[1]), ""), "T", "Tanky: tank only")
		local quiet
		for _, e in ipairs(G.Looking("D")) do if e.sender == "Quiet-Realm" then quiet = e end end
		eq(table.concat(G.InviteRoles(quiet), ""), "TD", "a flag naming no role: any role we need")
		Line(B.Lines(), "Tanky").onClick()
		lines = B.Lines()
		eq(Line(lines, "> " .. ns.L.GROUPS_INVITE_AS:format(ns.L.GROUPS_ROLE_D)), nil, "not as a role he doesn't play")
		Line(lines, "> " .. ns.L.GROUPS_INVITE_AS:format(ns.L.GROUPS_ROLE_T)).onClick()
		eq(w.invited[#w.invited], "Tanky")
		eq(G.Mine().need, "103", "until he joins")
		w.party = { { "Tanky", "", "WARRIOR" } }
		G.CheckJoins()
		eq(G.Mine().need, "003")
		eq(G.GroupMembers()[1].role, "T", "his role, as he was invited")
	end)
end)

test("1.2 groups: a listing repeats every 5 minutes while few are up (up to 30 when the Board is full), and leaves every Board about 12 minutes after its leader went quiet", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		eq(G.Interval(0), 5); eq(G.Interval(40), 8); eq(G.Interval(150), 30)
		assert(G.Post("D", "DM", nil, "113", ""))
		eq(G.Decode(Sent(w, "GL~").msg).every, 5)
		AsSoldier("Reader")
		GetGuildInfo = function() return "Olympus Zeus", "Member", 3 end
		G.HandlePost("CHANNEL", "Soldier-Realm", Sent(w, "GL~").msg)
		eq(#G.List("D"), 1)
		w.clock = w.clock + 11 * 60
		eq(#G.List("D"), 1, "two refreshes missed: still there at 11 minutes")
		w.clock = w.clock + 60
		eq(#G.List("D"), 0, "gone at 12")
	end)
end)
