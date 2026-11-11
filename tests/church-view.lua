-- 1.1.6, the Missionary Church of Olympus: the tab, its pages, the dialogs (Olympus's own window
-- under the gamepad UI), the right-click line, the words in both languages, the README.
-- Run alone: luajit tests/run.lua "1.1.6 Church"
local ns, test, eq, extra = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]church%-view%.lua$")) or "./"
local World = assert(loadfile(ROOT .. "tests/church-world.lua"))(ns, ROOT)
local Key = World.Key
local L = ns.L

local A1, A2 = "Aldric Vane-Realm", "Bera Stone-Realm"

local function Cast()
	local w = World.New({ apostles = { A1, A2 } })
	local c = {
		author = w:Client(World.AUTHOR, { view = true }), king = w:Client(World.KING, { view = true }), head = w:Client(World.HEAD, { view = true }),
		councillor = w:Client(World.COUNCILLOR, { view = true }),
		a1 = w:Client(A1, { view = true }), a2 = w:Client(A2, { view = true }),
		m1 = w:Client("Mira Wells", { view = true }), member = w:Client("Plain Member", { view = true }),
		gm = w:Client("Ember Master", { view = true, rank = 0 }), other = w:Client("Vale Member", { view = true, guild = World.GUILD2 }),
	}
	w:Act(c.a1, c.a1.Church.NameMissionary, "Mira Wells")
	w:Presence()
	return w, c
end

local function Texts(lines)
	local out = {}
	for _, line in ipairs(lines or {}) do
		if line.text then out[#out + 1] = line.text end
		if line.right then out[#out + 1] = line.right end
		for _, col in ipairs(line.cols or {}) do out[#out + 1] = col end
		for _, item in ipairs(line.nav or {}) do out[#out + 1] = item.text end
	end
	return table.concat(out, "\n")
end
local function Find(lines, text)
	for _, line in ipairs(lines or {}) do
		if (line.text and line.text:find(text, 1, true)) or (line.cols and line.cols[1] and line.cols[1]:find(text, 1, true)) then return line end
	end
	return nil
end
-- A confirmed recruit in every keeper's ledger (what the log, the witnesses and the keepers' catch-up make).
local function GiveAll(w, c, by, recruit)
	for _, k in ipairs({ c.head, c.a1, c.a2, c.author }) do
		w:As(k, k.Count.MergeIn, Key(recruit) .. ":" .. Key(by), { n = recruit, bn = ns.ShortName(by), g = World.GUILD, kind = "i",
			tc = w.clock - 7200, tj = w.clock - 3600, ws = { "wes brook" } }, false)
	end
end
local function Pages(w, cl) return table.concat(w:As(cl, cl.View.Pages), ",") end
local function Build(w, cl, page)
	if page then cl.View.page = page end
	return w:As(cl, cl.View.Build)
end

-- (1.4.0: the link is to the King's letter for that place, and only once it was made for him, which
-- needs the letters out: RoleBriefings.Has. The cherry-picked link showed whenever the role held,
-- and opened nothing while no letter existed.)
test("Church Mine: an appointed Missionary can reopen his letter from the King, once it exists", function()
	local w, c = Cast()
	local opened, has = nil, true
	c.m1.c.RoleBriefings = { Has = function(kind) return has and kind == "missionary" end, OpenKind = function(kind) opened = kind return true end }
	local lines = Build(w, c.m1, "mine")
	local link = Find(lines, L.RB_CHURCH_LETTER_LINK)
	assert(link and link.onClick, Texts(lines))
	w:As(c.m1, link.onClick)
	eq(opened, "missionary")
	-- No letter made (the letters not out yet): no link.
	has = false
	eq(Find(Build(w, c.m1, "mine"), L.RB_CHURCH_LETTER_LINK), nil)
	-- An ordinary member has no appointment letter manufactured for them.
	has = true
	c.member.c.RoleBriefings = c.m1.c.RoleBriefings
	eq(Find(Build(w, c.member, "mine"), L.RB_CHURCH_LETTER_LINK), nil)
end)

test("1.5.6 Church rank recovery: the King's visible page tries another keeper after a silent desk", function()
	local w, c = Cast()
	local king = c.king
	king.View.page, king.View.list, king.View.window = "ranking", "m", "m"
	local page = "church/"
	king.c.UI.IsShown = function() return true end
	king.c.UI.PageId = function() return page end
	c.a1.handlers.NR = nil
	GiveAll(w, c, "Mira Wells", "New Recruit")
	w:ClearSent()
	local lines = Build(w, king)
	assert(Find(lines, L.CHURCH_ASOF_WAITING), Texts(lines))
	w:Run(king.Count.ASK_GAP)
	local sent = w:Sent(king, "NR", "WHISPER", "q")
	eq(#sent, 1)
	eq(Key(sent[1].target), Key(A1), "the first request still goes to the desk")
	w:Tick({ king })
	sent = w:Sent(king, "NR", "WHISPER", "q")
	eq(#sent, 2, "the visible page retries without a click")
	eq(Key(sent[2].target), Key(A2), "a present but silent desk does not block the other keeper")
	eq(#(w:As(king, king.Count.RankingView, "m", "m")), 1)
	lines = Build(w, king)
	assert(Find(lines, L.CHURCH_DESK:format("Bera Stone")), Texts(lines))
	eq(Find(lines, L.CHURCH_ASOF_WAITING), nil, "a complete answer ends the waiting label")
	w:Run(king.Count.ASK_GAP)
	w:Tick({ king })
	eq(#w:Sent(king, "NR", "WHISPER", "q"), 2, "a complete page refreshes less often")
	page = "realm/guilds"
	w:Run(king.Count.ASK_GAP)
	w:Tick({ king })
	eq(#w:Sent(king, "NR", "WHISPER", "q"), 2, "the King's client stops polling when he leaves Church")
end)

test("1.2.4 Church ranking rules: the highlighted in-window page preserves the exact list and time window on Back", function()
	local w = World.New()
	local c = w:Client(World.AUTHOR, { view = true })
	c.View.page, c.View.list, c.View.window = "ranking", "m", "w"
	local lines = Build(w, c)
	local link
	for _, line in ipairs(lines) do if line.id == "ranking-rules:church-score" then link = line break end end
	assert(link and link.onClick, Texts(lines))
	w:As(c, link.onClick)
	eq(c.View.page, "rules")
	lines = Build(w, c)
	eq(lines[1].id, "ranking-rules-back")
	assert(Texts(lines):gsub("\n", " "):find(L.RANK_RULE_CHURCH_SCORE:format(c.Count.POINTS_JOIN, c.Count.STAY_DAYS, c.Count.POINTS_STAY, 25, 10, 5), 1, true), Texts(lines))
	w:As(c, lines[1].onClick)
	eq(c.View.page, "ranking")
	eq(c.View.list, "m")
	eq(c.View.window, "w")
end)

test("1.2.4 Church fullness ranking rules: the private link opens in place and Back restores the fullness list", function()
	local w = World.New()
	local c = w:Client(World.AUTHOR, { view = true })
	c.View.page, c.View.list, c.View.window = "ranking", "c", "a"
	local lines = Build(w, c)
	local link
	for _, line in ipairs(lines) do if line.id == "ranking-rules:church-fullness" then link = line break end end
	assert(link and link.onClick, Texts(lines))
	w:As(c, link.onClick)
	eq(c.View.page, "rules")
	lines = Build(w, c)
	eq(lines[1].id, "ranking-rules-back")
	local prose = Texts(lines):gsub("\n", " ")
	assert(prose:find(L.CHURCH_FULLNESS_RULE, 1, true), prose)
	assert(prose:find(L.RANK_RULE_CHURCH_FULLNESS_VISIBILITY, 1, true), prose)
	w:As(c, lines[1].onClick)
	eq(c.View.page, "ranking")
	eq(c.View.list, "c")
	eq(c.View.window, "a")
	lines = Build(w, c)
	w:As(c, assert((function()
		for _, line in ipairs(lines) do if line.id == "ranking-rules:church-fullness" then return line.onClick end end
	end)()))
	local inAudience = c.Church.InAudience
	c.Church.InAudience = function() return false end
	lines = Build(w, c)
	eq(c.View.page, "people", "loss of the private Church audience closes the rules page")
	for _, line in ipairs(lines) do
		assert(line.id ~= "ranking-rules-back" and line.id ~= "ranking-rules:church-fullness", "private rules remained discoverable")
	end
	c.Church.InAudience = inAudience
end)

test("1.2.4 Church correspondence: guild representation uses observed days and never invents historical fullness from census", function()
	local w, c = Cast()
	eq(w:Act(c.gm, c.gm.Church.NameCorrespondent, "Plain Member"), true)
	c.author.View.list = "c"
	c.author.c.Data = { Guild = function(guild) if guild == World.GUILD then return { total = 951 } end end }
	local lines = Build(w, c.author, "ranking")
	local row
	for _, line in ipairs(lines) do if line.capacityGuild == World.GUILD then row = line end end
	assert(row and row.player == "Plain Member-Realm", "the guild's actual appointed correspondent")
	assert(row.text:find(World.GUILD, 1, true), "represents the guild, not invitation points")
	eq(row.cols, nil, "no invitation score or invented streak column")
	assert(Texts(lines):find(L.CHURCH_FULLNESS_RULE, 1, true), "explicit observation and unknown-day policy")
	eq(row.fullness.days, nil, "a census snapshot invents no zero or streak")
	eq(row.right, L.CHURCH_CAPACITY_UNKNOWN)
	eq(#lines[2].filters, 1, "fullness is an ongoing streak, not invitation week/month filters")
	local tip = {}
	row.tooltip({ AddLine = function(_, text) tip[#tip + 1] = text end })
	assert(table.concat(tip, "\n"):find(L.CHURCH_FULLNESS_TIP, 1, true), "client-evidence limitation")
	-- With no census record, the same valid appointment remains visible without a fabricated count.
	c.author.c.Data.Guild = function() return nil end
	lines = Build(w, c.author, "ranking")
	for _, line in ipairs(lines) do if line.capacityGuild == World.GUILD then row = line end end
	tip = {}; row.tooltip({ AddLine = function(_, text) tip[#tip + 1] = text end })
	eq(row.fullness.days, nil)
end)

test("Church discoverability: missionaries are the third visible group with existing appointment action", function()
	local w, c = Cast()
	local lines = Build(w, c.a1, "people")
	local apostleAt, correspondentAt, missionaryAt, personAt
	for i, line in ipairs(lines) do
		if line.text == L.CHURCH_APOSTLES:format(3, 12) then apostleAt = i end
		if line.text == L.CHURCH_CORRESPONDENTS:format(0) then correspondentAt = i end
		if line.text == L.CHURCH_MISSIONARIES:format(1) then missionaryAt = i end
		if line.player == "Mira Wells-Realm" then personAt = i end
	end
	assert(apostleAt and correspondentAt and missionaryAt and personAt, Texts(lines))
	assert(apostleAt < correspondentAt and correspondentAt < missionaryAt and missionaryAt < personAt)
	eq(c.a1.View.open[Key(A1)], nil, "missionaries visible without expanding Apostle")
	local signed = {}
	local state = w:As(c.a1, c.a1.Church.State)
	for _, line in ipairs(lines) do if line.key and state.apostle[line.key] then signed[#signed + 1] = line.key end end
	eq(table.concat(signed, ","), table.concat(state.order, ","), "original signed ordering unchanged")
	local name = Find(lines, L.CHURCH_NAME_MISSIONARY:format(11, 12))
	assert(name and name.onClick, "existing authorized naming duty surfaced beside group")
	name.onClick(); local dialog = c.a1.dialogs[#c.a1.dialogs]
	eq(dialog.which, "OLYMPUS_CHURCH_NAME"); eq(dialog.data.kind, "missionary")
	eq(w:Act(c.a1, c.a1.View.Submit, dialog.data, "Fresh Face"), true)
	eq(w:As(c.member, c.member.Church.Role, "Fresh Face-Realm"), "M")
	lines = Build(w, c.member, "people")
	eq(Find(lines, L.CHURCH_NAME_MISSIONARY:format(10, 12)), nil, "ordinary member gets no appointment action")
end)

test("Church publication authority UI: actual King/council switches, no preview action", function()
	local w, c = Cast()
	for _, publisher in ipairs({ c.king, c.councillor }) do
		local switch = Find(Build(w, publisher, "ranking"), L.CHURCH_PUBLIC_SWITCH)
		assert(switch and switch.onClick, "actual publisher sees the existing switch")
		w:Act(publisher, switch.onClick)
		eq(w:As(c.member, c.member.Church.Public), true)
		w:Act(publisher, switch.onClick)
		eq(w:As(c.member, c.member.Church.Public), false)
	end
	c.author.c.ViewAs = { missing = false, Previewing = function() return true end, Role = function() return "councillor" end }
	eq(Find(Build(w, c.author, "ranking"), L.CHURCH_PUBLIC_SWITCH), nil, "simulation does not expose action")
	eq(Find(Build(w, c.a1, "ranking"), L.CHURCH_PUBLIC_SWITCH), nil, "Apostle alone gets no switch")
end)

test("1.1.6 Church member view: people and invites, no naming or personal results, and explicit previews override the author's real role", function()
	local w, c = Cast()
	eq(Pages(w, c.member), "people,invites")
	eq(Pages(w, c.councillor), "ranking,people,name,invites")
	eq(Pages(w, c.author), "ranking,people,name,review,invites")
	eq(Pages(w, c.head), "ranking,mine,people,name,invites", "legacy marked Apostle has no root review page")
	local role = "member"
	c.author.c.ViewAs = { Available = function() return true end, Previewing = function() return true end,
		Role = function() return role end }
	eq(Pages(w, c.author), "people")
	local inviteLines = Build(w, c.author, "invites")
	eq(c.author.View.page, "people", "an explicit preview cannot operate the live invite tools")
	eq(Find(inviteLines, L.RECRUIT_WHISPER_OFF), nil)
	local lines = Build(w, c.author, "review")
	eq(c.author.View.page, "people", "a stale staff page returns to the member's page")
	eq(Find(lines, L.CHURCH_ACT_NAME_APOSTLE), nil)
	eq(Find(lines, L.CHURCH_REGISTER:format(0, c.author.Count.REG_OPEN)), nil)
	local before = #w.sent
	eq(w:As(c.author, c.author.View.Submit, { kind = "apostle" }, "Preview Pick"), false)
	eq(#w.sent, before, "a stale preview callback sends nothing")
	role = "councillor"
	eq(Pages(w, c.author), "ranking,people,name")
	role = "king"
	eq(Pages(w, c.author), "ranking,people,name,review")
end)

test("1.1.6 member view: a legacy throne preview cannot expose Royal Inspection in an explicit member preview", function()
	local saved = { view = ns.ViewAs, king = ns.King.IsKing, dev = ns.devThrone, db = ns.db.devKingView }
	local ok, err = pcall(function()
		ns.King.IsKing = function() return false end
		ns.devThrone, ns.db.devKingView = true, nil
		ns.ViewAs = { Is = function() return false end, Previewing = function() return true end, Role = function() return "member" end }
		eq(ns.King.Preview(), false)
		eq(#ns.King.InspectionLines(), 0)
	end)
	ns.ViewAs, ns.King.IsKing, ns.devThrone, ns.db.devKingView = saved.view, saved.king, saved.dev, saved.db
	if not ok then error(err, 0) end
end)

test("1.1.6 Church: everyone sees the people, private numbers and duties follow the actual role, public rankings follow publication", function()
	local w, c = Cast()
	eq(#c.a1.tabs, 1); eq(c.a1.tabs[1].key, "church"); eq(c.a1.tabs[1].after, "crafters")
	local function Visible(cl) return w:As(cl, cl.tabs[1].visible) end
	for _, cl in ipairs({ c.author, c.king, c.head, c.councillor, c.a1, c.m1 }) do eq(Visible(cl), true, cl.name) end
	eq(Visible(c.member), true); eq(Visible(c.other), true)
	eq(Visible(c.gm), true, "a guild master: to name his guild's correspondent")
	eq(Pages(w, c.gm), "people,name,invites")
	eq(Pages(w, c.m1), "ranking,mine,people,name,invites")
	eq(Pages(w, c.councillor), "ranking,people,name,invites", "a councillor names Apostles, has no personal results")
	eq(Pages(w, c.author), "ranking,people,name,review,invites")
	-- The public view opens the Public page to everyone else.
	GiveAll(w, c, "Mira Wells", "R Aa")
	w:Act(c.m1, c.m1.Count.SetPublicRow, true)
	w:Act(c.author, c.author.Church.SetPublic, true)
	w:Tick()
	eq(Visible(c.member), true)
	eq(Pages(w, c.member), "people,public,invites")
	local lines = Build(w, c.member, "public")
	assert(Find(lines, "Mira Wells"), Texts(lines))
	-- Closing the public ranking leaves the people, never private numbers.
	w:Act(c.author, c.author.Church.SetPublic, false)
	local empty, title, text = Build(w, c.member)
	assert(#empty > 0); eq(title, L.CHURCH_TITLE); eq(text, L.CHURCH_PEOPLE_DETAIL)
	eq(c.member.View.page, "people")
end)

test("1.1.6 Church: the Ranking page: the two rankings and the correspondents, three windows, columns, the viewer's own line with how his score is made", function()
	local w, c = Cast()
	local K = c.a1
	GiveAll(w, c, "Mira Wells", "R Aa"); GiveAll(w, c, A1, "R Ab")
	K.View.list, K.View.window = "a", "w"
	local lines = Build(w, K, "ranking")
	eq(lines[1].id, "church-navigation"); eq(lines[1].pageNav, true)
	eq(lines[2].id, "church-filters"); eq(#lines[2].filters, 2)
	local row = Find(lines, "Aldric Vane")
	eq(row.cols[2], "12.5", "10 own + 25% of Mira's 10"); eq(row.cols[3], L.CHURCH_SPLIT:format("10", "2.5"))
	assert(Texts(lines):find(L.CHURCH_BREAKDOWN:format("10", "2.5", "0", "0"), 1, true), "his own line's breakdown")
	K.View.list = "m"
	lines = Build(w, K)
	eq(Find(lines, "Mira Wells").cols[2], "10")
	-- A missionary's client (not a keeper) asks, then shows the answer with its time and the desk's name.
	c.m1.View.list, c.m1.View.window = "m", "w"
	Build(w, c.m1, "ranking")
	w:Run(30)
	lines = Build(w, c.m1, "ranking")
	assert(Find(lines, "Mira Wells"), Texts(lines))
	assert(Texts(lines):find(L.CHURCH_DESK:format("Aldric Vane"), 1, true), "who answered: the alphabetically first Apostle desk, never Asmongold")
	-- The ranking's rows open a detail for authorized viewers: Mira may open her own, not Aldric's.
	eq(Find(lines, "Mira Wells").onClick ~= nil, true)
	c.m1.View.list = "a"
	Build(w, c.m1)
	w:Run(30)
	lines = Build(w, c.m1)
	eq(Find(lines, "Aldric Vane").onClick, nil)
end)

test("1.1.6 Church: page tabs and Who/When filters stay distinct and filter choices update the results", function()
	local w, c = Cast()
	local K = c.a1
	GiveAll(w, c, "Mira Wells", "R Aa")
	K.View.list, K.View.window = "a", "w"
	local lines = Build(w, K, "ranking")
	eq(lines[1].pageNav, true)
	local who, when = lines[2].filters[1], lines[2].filters[2]
	eq(who.label, L.CHURCH_FILTER_WHO); eq(when.label, L.CHURCH_FILTER_WHEN)
	eq(#who.options, 3); eq(#when.options, 3)
	eq(who.value, L.CHURCH_LIST_APOSTLES); eq(when.value, L.CHURCH_WINDOW_WEEK)
	local before = #w.sent
	w:As(K, who.options[2].onClick)
	w:As(K, when.options[3].onClick)
	eq(K.View.list, "m"); eq(K.View.window, "a")
	eq(#w.sent, before, "changing local filters sends no role mutation")
	lines = Build(w, K)
	eq(lines[2].filters[1].value, L.CHURCH_LIST_MISSIONARIES)
	eq(lines[2].filters[2].value, L.CHURCH_WINDOW_ALL)
	eq(Find(lines, "Mira Wells").cols[2], "10")
	local mine = Build(w, K, "mine")
	eq(#mine[2].filters, 1); eq(mine[2].filters[1].label, L.CHURCH_FILTER_WHEN)
	local people = Build(w, K, "people")
	for _, line in ipairs(people) do eq(line.filters, nil, "People has no ranking filters") end
end)

test("1.1.6 Church: Mine, People, Name and Review: each one's numbers, the tree with its marks, the naming quotas, the review for roots", function()
	local w, c = Cast()
	local mine = Build(w, c.m1, "mine")
	assert(Texts(mine):find(L.CHURCH_PLACE_MISSIONARY:format("Aldric Vane", "Aldric Vane"), 1, true), Texts(mine))
	assert(Find(mine, L.CHURCH_MY_ROW), "the public row switch")
	-- People: the Head, the Apostles, the networks (opened by a click), the actions a viewer may take.
	local people = Build(w, c.a1, "people")
	assert(Texts(people):find("Corin Ash", 1, true))
	local aldric = Find(people, "Aldric Vane")
	aldric.onClick()
	people = Build(w, c.a1, "people")
	assert(Find(people, "Mira Wells"), "his network under him")
	assert(Find(people, L.CHURCH_ACT_NAME_UNDER:format("Aldric Vane")), "he may name under himself")
	people = Build(w, c.m1, "people")
	eq(Find(people, L.CHURCH_ACT_REMOVE:format("Aldric Vane")), nil, "a missionary removes no Apostle")
	-- Name: the quotas; the root's guild list; a guild master's own line.
	local name = Build(w, c.a1, "name")
	assert(Find(name, L.CHURCH_NAME_MISSIONARY:format(11, 12)), Texts(name))
	name = Build(w, c.author, "name")
	assert(Find(name, L.CHURCH_NAME_APOSTLE:format(9, 12)), Texts(name)) -- (two and the Head)
	assert(Find(name, World.GUILD2), "every Olympus guild, each with its correspondent")
	name = Build(w, c.gm, "name")
	local line = Find(name, L.CHURCH_NAME_CORRESPONDENT:format(World.GUILD))
	assert(line and line.onClick)
	line.onClick()
	eq(c.gm.dialogs[#c.gm.dialogs].which, "OLYMPUS_CHURCH_NAME")
	eq(c.gm.dialogs[#c.gm.dialogs].data.kind, "correspondent")
	-- Review: roots only; an adopted missionary shows there with keep and move.
	w:Act(c.m1, c.m1.Church.NameMissionary, "Nils Ford")
	w:Act(c.a1, c.a1.Church.Remove, "M", "Mira Wells")
	eq(Pages(w, c.a1):find("review", 1, true), nil)
	local review = Build(w, c.author, "review")
	local nils = Find(review, "Nils Ford")
	assert(nils, Texts(review))
	nils.onClick()
	review = Build(w, c.author, "review")
	assert(Find(review, L.CHURCH_ACT_KEEP)); assert(Find(review, L.CHURCH_ACT_MOVE))
end)

test("1.1.6 Church: the dialogs: a name typed names, a Yes confirms; under the gamepad UI they open in Olympus's own window, never the game's popup", function()
	local w, c = Cast()
	-- With mouse and keyboard, through ns.ShowDialog (here the world's stand-in): the data says what it does.
	w:As(c.a1, c.a1.View.Ask, "missionary")
	local d = c.a1.dialogs[#c.a1.dialogs]
	eq(d.which, "OLYMPUS_CHURCH_NAME"); eq(d.data.kind, "missionary")
	w:Act(c.a1, c.a1.View.Submit, d.data, "Fresh Face")
	eq(w:As(c.member, c.member.Church.Role, "Fresh Face-Realm"), "M")
	w:As(c.a1, c.a1.View.AskConfirm, "remove", { role = "M", name = "Fresh Face-Realm" })
	d = c.a1.dialogs[#c.a1.dialogs]
	eq(d.which, "OLYMPUS_CHURCH_CONFIRM")
	w:Act(c.a1, c.a1.View.Confirm, d.data)
	eq(w:As(c.member, c.member.Church.Role, "Fresh Face-Realm"), nil)
	-- The real ns.ShowDialog under the gamepad UI: Dialog.lua's window, the game's popup untouched. (One
	-- client with the tab here: the dialogs' definitions are the game's global table, the last loaded's.)
	if not (extra and extra.WithGamepadUI and extra.WithUI) then return end
	w = World.New({ apostles = { A1 } })
	c = { member = w:Client("Plain Member"), a1 = w:Client(A1, { view = true }) }
	extra.WithUI(function()
		extra.WithGamepadUI(true, function(game)
			rawset(c.a1.c, "ShowDialog", nil)
			local f = w:As(c.a1, c.a1.View.Ask, "missionary")
			eq(#game.shown, 0, "never StaticPopup_Show")
			assert(f and ns.Dialog.Find("OLYMPUS_CHURCH_NAME") == f, "Olympus's own window")
			eq(f.editBox:IsShown(), true)
			f.editBox:SetText("Pad Player")
			w:As(c.a1, function() f.buttons[1]:Click() end)
			w:Flush()
			eq(w:As(c.member, c.member.Church.Role, "Pad Player-Realm"), "M", "named from the gamepad window")
		end)
		extra.WithGamepadUI(false, function(game)
			local which = w:As(c.a1, c.a1.View.AskConfirm, "remove", { role = "M", name = "Pad Player-Realm" })
			eq(game.shown[1] and game.shown[1].which, "OLYMPUS_CHURCH_CONFIRM", "mouse and keyboard: the game's popup")
			_ = which
		end)
	end)
end)

test("1.1.6 Church: the right-click line: an Apostle or a missionary names a missionary, a root an Apostle; nobody else, never under the gamepad UI", function()
	local w, c = Cast()
	local function Lines(cl, target)
		local menu = { buttons = {} }
		function menu.Button(text, fn, _, _, enabled) menu.buttons[#menu.buttons + 1] = { text = text, fn = fn, enabled = enabled } end
		w:As(cl, cl.View.MenuLines, { name = target }, menu)
		return menu.buttons
	end
	eq(#Lines(c.member, "Some Body-Realm"), 0)
	eq(Lines(c.councillor, "Some Body-Realm")[1].text, L.CHURCH_MENU_APOSTLE)
	local b = Lines(c.a1, "Some Body-Realm")
	eq(#b, 1); eq(b[1].text, L.CHURCH_MENU_MISSIONARY)
	b[1].fn()
	eq(c.a1.dialogs[#c.a1.dialogs].which, "OLYMPUS_CHURCH_CONFIRM")
	eq(#Lines(c.a1, "Mira Wells-Realm"), 0, "one who holds a place already")
	local r = Lines(c.author, "Some Body-Realm")
	eq(r[#r].text, L.CHURCH_MENU_APOSTLE)
	-- Through the real PlayerMenu: with the gamepad UI on, no line at all.
	if not (extra and extra.WithGamepadUI) then return end
	ns.PlayerMenu.Add("church-test", function(target, menu) w:As(c.a1, c.a1.View.MenuLines, target, menu) end, 40)
	local ok, err = pcall(function()
		extra.WithGamepadUI(true, function()
			local root = setmetatable({}, { __index = function() return function() error("a line under the gamepad UI") end end })
			eq(ns.PlayerMenu.Build("PLAYER", root, { name = "Some Body" }), 0)
		end)
	end)
	ns.PlayerMenu.Add("church-test", nil)
	if not ok then error(err, 0) end
end)

-- 1.2.4 (an Apostle's report on 1.2.3: "can't name missionaries anymore"). One parent's ten
-- (Church.NAMES_PER, the same since 1.2.0, with no time window: only a removal frees a place) left
-- him nothing to read: the Name page's header went dead, the People page's line and the
-- right-click line vanished, and only /oly church name said why, with no count. Each way to name
-- now says he has named 10 of 10, the most one may, and what frees a place.
test("1.2.4 Church: an Apostle at his ten is told why and how many he named, wherever he names from", function()
	local w, c = Cast()
	local per = c.a1.Church.NAMES_PER
	for i = 1, per - 1 do w:Run(11); eq(w:Act(c.a1, c.a1.Church.NameMissionary, "Kid Number" .. ("a"):rep(i)), true, i) end
	eq(w:As(c.a1, c.a1.Church.Rights).missionary, 0, "Mira Wells and nine more: his ten")
	-- The Name page: the header with none left, then the reason with his count, and what frees a place.
	local name = Build(w, c.a1, "name")
	local header = Find(name, L.CHURCH_NAME_MISSIONARY:format(0, per))
	assert(header, Texts(name))
	eq(header.onClick, nil, "no dialog for an eleventh")
	assert(Find(name, L.CHURCH_QUOTA_LINE:format(per, per)), Texts(name))
	assert(Find(name, L.CHURCH_QUOTA_HOW), Texts(name))
	-- The People page: the missionaries' group and his own row say so instead of losing the line.
	local people = Build(w, c.a1, "people")
	assert(Find(people, L.CHURCH_QUOTA_LINE:format(per, per)), Texts(people))
	Find(people, "Aldric Vane").onClick()
	people = Build(w, c.a1, "people")
	eq(Find(people, L.CHURCH_ACT_NAME_UNDER:format("Aldric Vane")), nil, "no naming line past his ten")
	local full = Find(people, L.CHURCH_ACT_UNDER_FULL:format("Aldric Vane", per, per))
	assert(full and full.onClick == nil, Texts(people))
	-- The right-click line stays, greyed, with his count; its tooltip says what he can do.
	local menu = { buttons = {} }
	function menu.Button(text, fn, _, tip, enabled) menu.buttons[#menu.buttons + 1] = { text = text, fn = fn, tip = tip, enabled = enabled } end
	w:As(c.a1, c.a1.View.MenuLines, { name = "Some Body-Realm" }, menu)
	eq(#menu.buttons, 1)
	eq(menu.buttons[1].text, L.CHURCH_MENU_MISSIONARY_FULL:format(per, per))
	eq(menu.buttons[1].enabled, false)
	eq(menu.buttons[1].tip, L.CHURCH_NO_QUOTA_SELF:format(per, per))
	-- /oly church name: refused, with his count and what frees a place; nobody is named.
	eq(w:Act(c.a1, c.a1.Church.Slash, "name Kid Eleven"), false)
	eq(w:Printed(c.a1), L.CHURCH_NO_QUOTA_SELF:format(per, per))
	eq(w:As(c.member, c.member.Church.Role, "Kid Eleven-Realm"), nil)
	-- The author naming under him is told it is that Apostle's ten, not his own.
	eq(w:Act(c.author, c.author.Church.NameMissionary, "Kid Twelve", A1), false)
	eq(w:Printed(c.author), L.CHURCH_NO_QUOTA_UNDER:format("Aldric Vane", per, per))
	-- The words on the page (in both languages: the test below) carry both numbers.
	assert(L.CHURCH_QUOTA_LINE:format(per, per):find(tostring(per) .. "[^%d]+" .. tostring(per)), L.CHURCH_QUOTA_LINE)
	-- A removal frees a place at once: the page offers the naming again, without the reason.
	w:Run(61)
	eq(w:Act(c.a1, c.a1.Church.Remove, "M", "Kid Numbera"), true)
	name = Build(w, c.a1, "name")
	local again = Find(name, L.CHURCH_NAME_MISSIONARY:format(1, per))
	assert(again and again.onClick, Texts(name))
	eq(Find(name, L.CHURCH_QUOTA_HOW), nil)
	menu.buttons = {}
	w:As(c.a1, c.a1.View.MenuLines, { name = "Some Body-Realm" }, menu)
	eq(menu.buttons[1].text, L.CHURCH_MENU_MISSIONARY)
	eq(menu.buttons[1].enabled, true)
end)

-- A line's tooltip as the game would show it: its lines, one under the other.
local function TipText(tooltip)
	local out = {}
	tooltip({ AddLine = function(_, text) out[#out + 1] = tostring(text) end })
	return table.concat(out, "\n")
end

-- 1.2.4 (the same report, its review): the Church's total (Church.MISSIONARIES_MAX, 300 since
-- 1.1.6) refuses every naming of a missionary at once (Church.MayAct, after the namer's own ten),
-- whatever his own count. The Name page still offered "Name a missionary (9 of 10 left)" and its
-- dialog, the People page and the right-click line too, and the refusal said only "That list is
-- full.". Each way to name now says the Church holds its total, with the number, and what frees a place.
test("1.2.4 Church: at the Church's total an Apostle with places of his own left is told the Church is full, with its count", function()
	local w, c = Cast()
	local Ch, per = c.a1.Church, c.a1.Church.NAMES_PER
	local saved = Ch.MISSIONARIES_MAX
	local ok, err = pcall(function()
		-- (The total lowered on his client, as the limits test in tests/church.lua does: Mira Wells holds its one place.)
		Ch.MISSIONARIES_MAX = 1
		Ch.Changed()
		local r = w:As(c.a1, Ch.Rights)
		eq(r.missionary, per - 1, "his own ten is not the cause")
		local text = L.CHURCH_FULL_LINE:format(1) .. " " .. L.CHURCH_FULL_HOW
		-- The Name page: his own count in the header, nothing to click, the Church's total and what frees a place.
		local name = Build(w, c.a1, "name")
		local header = Find(name, L.CHURCH_NAME_MISSIONARY:format(per - 1, per))
		assert(header, Texts(name))
		eq(header.onClick, nil, "no dialog the Church would refuse")
		eq(TipText(header.tooltip), L.CHURCH_MISSIONARY .. "\n" .. text)
		assert(Find(name, L.CHURCH_FULL_LINE:format(1)), Texts(name))
		assert(Find(name, L.CHURCH_FULL_HOW), Texts(name))
		eq(Find(name, L.CHURCH_QUOTA_HOW), nil, "not his ten")
		-- The People page: the group's line and his own row's, greyed, nothing to click.
		local people = Build(w, c.a1, "people")
		assert(Find(people, L.CHURCH_FULL_LINE:format(1)), Texts(people))
		eq(Find(people, L.CHURCH_NAME_MISSIONARY:format(per - 1, per)), nil, Texts(people))
		Find(people, "Aldric Vane").onClick()
		people = Build(w, c.a1, "people")
		local under = Find(people, L.CHURCH_ACT_NAME_UNDER:format("Aldric Vane"))
		assert(under and under.onClick == nil, Texts(people))
		eq(TipText(under.tooltip), L.CHURCH_MISSIONARY .. "\n" .. text)
		-- The right-click line stays, greyed; its tooltip and its click say why.
		local menu = { buttons = {} }
		function menu.Button(label, fn, _, tip, enabled) menu.buttons[#menu.buttons + 1] = { text = label, fn = fn, tip = tip, enabled = enabled } end
		w:As(c.a1, c.a1.View.MenuLines, { name = "Some Body-Realm" }, menu)
		eq(#menu.buttons, 1)
		eq(menu.buttons[1].text, L.CHURCH_MENU_MISSIONARY)
		eq(menu.buttons[1].enabled, false)
		eq(menu.buttons[1].tip, text)
		-- /oly church name: refused with the Church's total, not "That list is full."; nobody is named.
		local before = #w.sent
		eq(w:Act(c.a1, Ch.Slash, "name Kid Eleven"), false)
		eq(w:Printed(c.a1), text)
		eq(#w.sent, before, "nothing sent")
		eq(w:As(c.member, c.member.Church.Role, "Kid Eleven-Realm"), nil)
		-- A place in the total again: the naming comes back.
		Ch.MISSIONARIES_MAX = saved
		Ch.Changed()
		name = Build(w, c.a1, "name")
		local again = Find(name, L.CHURCH_NAME_MISSIONARY:format(per - 1, per))
		assert(again and again.onClick, Texts(name))
		eq(Find(name, L.CHURCH_FULL_HOW), nil)
	end)
	Ch.MISSIONARIES_MAX = saved
	Ch.Changed()
	if not ok then error(err, 0) end
end)

-- 1.2.4 (the review): two namings under one parent at the same moment, his own tenth and a root's
-- under him, each refused by the clients that heard the other first, both reach every book through
-- the keepers' pages, which take an entry without the quota (Church.TakeEntry): one entry more than
-- his ten, the later holding no place (the tree's "quota"), the next freed place its own. His words
-- said "You have named 11 of 10"; they count his ten, as many as the People page shows under him.
test("1.2.4 Church: two namings at once past his ten: his words say his ten, never one more", function()
	local w, c = Cast()
	local per = c.a1.Church.NAMES_PER
	for i = 1, per - 2 do w:Run(11); eq(w:Act(c.a1, c.a1.Church.NameMissionary, "Kid Number" .. ("a"):rep(i)), true, i) end
	w:Run(11)
	-- Neither heard before the other went.
	eq(w:As(c.a1, c.a1.Church.NameMissionary, "Kid Mine"), true)
	eq(w:As(c.author, c.author.Church.NameMissionary, "Kid Root", A1), true)
	w:Flush()
	for _ = 1, 4 do w:Run(700); w:Presence(); w:Run(130); w:Tick(); w:Run(130) end
	local S = w:As(c.a1, c.a1.Church.State)
	eq(S.named[Key(A1)], per + 1, "both entries in his book")
	eq(#w:As(c.a1, c.a1.Church.Children, Key(A1)), per, "ten hold a place")
	local quota = L.CHURCH_NO_QUOTA_SELF:format(per, per)
	local name = Build(w, c.a1, "name")
	assert(Find(name, L.CHURCH_QUOTA_LINE:format(per, per)), Texts(name))
	eq(Find(name, L.CHURCH_QUOTA_LINE:format(per + 1, per)), nil, Texts(name))
	local people = Build(w, c.a1, "people")
	Find(people, "Aldric Vane").onClick()
	people = Build(w, c.a1, "people")
	assert(Find(people, L.CHURCH_QUOTA_LINE:format(per, per)), Texts(people))
	assert(Find(people, L.CHURCH_ACT_UNDER_FULL:format("Aldric Vane", per, per)), Texts(people))
	local menu = { buttons = {} }
	function menu.Button(label, fn, _, tip, enabled) menu.buttons[#menu.buttons + 1] = { text = label, tip = tip, enabled = enabled } end
	w:As(c.a1, c.a1.View.MenuLines, { name = "Some Body-Realm" }, menu)
	eq(menu.buttons[1].text, L.CHURCH_MENU_MISSIONARY_FULL:format(per, per))
	eq(menu.buttons[1].tip, quota)
	eq(w:Act(c.a1, c.a1.Church.Slash, "name Kid Eleven"), false)
	eq(w:Printed(c.a1), quota)
	eq(w:Act(c.author, c.author.Church.NameMissionary, "Kid Twelve", A1), false)
	eq(w:Printed(c.author), L.CHURCH_NO_QUOTA_UNDER:format("Aldric Vane", per, per))
	-- The status window (for the author to read) keeps the book's own count, and how many hold a place.
	local status = table.concat(w:As(c.a1, c.a1.Church.StatusLines), "\n")
	assert(status:find(("named %d of %d (0 left), %d holding a place"):format(per + 1, per, per), 1, true), status)
	-- One of his removed: the one waiting takes the place freed, and he is still at his ten.
	w:Run(61)
	eq(w:Act(c.a1, c.a1.Church.Remove, "M", "Kid Numbera"), true)
	eq(#w:As(c.a1, c.a1.Church.Children, Key(A1)), per)
	eq(w:As(c.a1, c.a1.Church.Rights).missionary, 0)
	assert(Find(Build(w, c.a1, "name"), L.CHURCH_QUOTA_LINE:format(per, per)))
end)

test("1.1.6 Church: the Church chat button opens the Chat tab on the Church's room; /oly church status opens a window to copy from", function()
	local w, c = Cast()
	w:As(c.m1, c.m1.View.OpenChat)
	eq(c.m1.chatOpened, true); eq(c.m1.chatRoom, "church")
	w:As(c.member, c.member.View.OpenChat)
	eq(c.member.chatRoom, nil)
	w:As(c.a1, c.a1.Church.Slash, "status")
	eq(c.a1.copied.title, L.CHURCH_TITLE)
	assert(c.a1.copied.text:find("role A", 1, true), c.a1.copied.text)
	w:Act(c.a1, c.a1.Church.Slash, "name Slash Pick")
	eq(w:As(c.member, c.member.Church.Role, "Slash Pick-Realm"), "M")
end)

test("1.1.6 Church: every word the Church shows is in English and pt-BR, with the same format codes", function()
	local function Load(locale)
		local savedLocale = GetLocale
		GetLocale = function() return locale end
		local t = { L = {} }
		local ok, err = pcall(function()
			assert(loadfile(ROOT .. "Olympus/Locales/ChurchText.lua"))("Olympus", t)
			assert(loadfile(ROOT .. "Olympus/Locales/ChurchFullnessText.lua"))("Olympus", t)
		end)
		GetLocale = savedLocale
		if not ok then error(err, 0) end
		return t.L
	end
	local en, pt = Load("enUS"), Load("ptBR")
	local function Codes(s) local out = {} for code in tostring(s):gmatch("%%[%a%%]") do out[#out + 1] = code end return table.concat(out) end
	local used = {}
	for _, file in ipairs({ "Church.lua", "ChurchCount.lua", "ChurchView.lua" }) do
		local f = assert(io.open(ROOT .. "Olympus/" .. file))
		local src = f:read("*a")
		f:close()
		for key in src:gmatch("L%.(CHURCH_[%u%d_]+)") do used[key] = true end
		for key in src:gmatch('"(CHURCH_[%u%d_]+)"') do used[key] = true end
	end
	used.TAB_CHURCH = true
	for _, k in ipairs({ "CHURCH_RANKING_A", "CHURCH_RANKING_M", "CHURCH_RANKING_C", "CHURCH_WHY_FULL", "CHURCH_WHY_DEEP", "CHURCH_WHY_QUOTA",
		"CHURCH_WHY_CHAIN", "CHURCH_NO_HOLDS", "CHURCH_NO_QUOTA", "CHURCH_NO_DEEP" }) do used[k] = true end
	for key in pairs(used) do
		if key:sub(-1) ~= "_" and key ~= "CHURCH_CHANGED" and key ~= "CHURCH_COUNT_CHANGED" and key ~= "CHURCH_PUBLIC_CHANGED" and key ~= "CHURCH_TOP_CHANGED" and key ~= "CHURCH_FULLNESS_CHANGED" then
			assert(rawget(en, key), "English: " .. key)
			assert(rawget(pt, key), "pt-BR: " .. key)
			eq(Codes(pt[key]), Codes(en[key]), "codes: " .. key)
		end
	end
	for key in pairs(en) do assert(rawget(pt, key), "pt-BR has " .. key) end
end)

test("1.1.6 Church: the README and the CurseForge page tell of the Church in the same words; the page's ? has its answers", function()
	local function Read(p) local f = assert(io.open(ROOT .. p)) local s = f:read("*a") f:close() return s end
	local PHRASES = { "### The Missionary Church of Olympus (1.1.6)", "the Twelve Apostles", "**Name as missionary**", "**pending**",
		"**confirmed**", "**new to Olympus**", "**Register a recruit**", "25% of those you named, 10% of theirs", "off by", "`/oly church`" }
	local sections = {}
	for _, path in ipairs({ "README.md", "docs/CURSEFORGE.md" }) do
		local doc = Read(path):gsub("%s+", " ")
		for _, phrase in ipairs(PHRASES) do assert(doc:find(phrase, 1, true), path .. ": " .. phrase) end
		sections[#sections + 1] = doc:match("### The Missionary Church of Olympus %(1%.1%.6%)(.-)###")
	end
	assert(sections[1] and sections[1] ~= "")
	eq(sections[1], sections[2], "the same words on both pages")
	-- The tab's "?" (Answers.PAGES.church) names answers the bank has.
	local w = World.New({})
	local cl = w:Client("Some One", { view = true })
	local page = cl.c.Answers.PAGES.church
	eq(page[1], "feat-church"); eq(page[2], "feat-church-count")
	local bank = Read("Olympus/AnswerBank.lua")
	assert(bank:find('"feat-church"', 1, true) and bank:find('"feat-church-count"', 1, true))
end)

-- (1.2.4, the author's ask: the Church's Name page said "none" for every other guild: its master's
-- naming was taken on no client outside his guild, and nothing kept it.) Fails before: Olympus Vale's
-- row on the author's Name page read "none" with its master online, and after.
test("1.2.4 Church: the root's Name page shows each guild's correspondent its master named, with that guild offline and after a reload", function()
	local w, c = Cast()
	local vgm = w:Client("Vale Master", { view = true, guild = World.GUILD2, rank = 0 })
	local function Census(rank)
		w.census[ns.Fold(World.GUILD2) .. ":" .. Key(vgm.name)] = rank
		for _, cl in ipairs(w.clients) do if cl.Church and cl.online then w:As(cl, cl.ns.Fire, "DATA_CHANGED") end end
	end
	local function Row(cl)
		local line = Find(Build(w, cl, "name"), World.GUILD2)
		return tostring(line and line.right)
	end
	Census(0)
	eq(w:Act(vgm, vgm.Church.NameCorrespondent, "Vale Helper"), true)
	assert(Row(c.author):find("Vale Helper", 1, true), Row(c.author))
	assert(Find(Build(w, c.author, "people"), L.CHURCH_CORRESPONDENTS:format(1)), "the People page counts him")
	-- His guild logs off; the author reloads eight hours later.
	vgm.online, c.other.online = false, false
	Census(nil)
	w:Run(8 * 3600)
	c.author.online = false
	local author = w:Client(World.AUTHOR, { view = true, rdb = c.author.ns.rdb })
	w:As(author, author.ns.Fire, "INIT")
	assert(Row(author):find("Vale Helper", 1, true), "after a reload, his guild offline: " .. Row(author))
	assert(Find(Build(w, author, "people"), L.CHURCH_CORRESPONDENTS:format(1)), "still counted")
end)
