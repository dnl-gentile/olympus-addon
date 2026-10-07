local ns, test, eq, H = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]weekly%-brief%.lua$")) or "./"

local function Client(saved, savedDB)
	local w = { clock = 1800000000, week = 100, guild = "Olympus Ember", sent = 0, entries = {}, history = {}, listeners = {}, popups = {}, timers = {} }
	local c = setmetatable({ me = "Brief Reader-Realm", faction = "Alliance", realm = "Realm", group = "Realm",
		rdb = saved or { guilds = {} }, db = savedDB or { location = false, layerHelp = false }, Alts = false, Moderation = {} }, { __index = ns })
	w.c = c
	c.Now = function() return w.clock end
	c.IsMember = function() return true end
	-- This world's pinned Treasurer is invented; only this exact character and guild qualify.
	c.TREASURER, c.TREASURER_REALM, c.TREASURER_CHARACTERS = "Tamsin Ledger", "Realm", { "Tamsin Ledger" }
	c.IsTreasurer = function(name, guild) return ns.FullName(name) == "Tamsin Ledger-Realm" and guild == "Olympus" end
	c.IsTreasurerMail = function() return false end
	c.On = function(event, fn) w.listeners[event] = fn end
	c.Fire, c.RegisterEvent = function() end, function() end
	c.After = function(seconds, key, fn) w.timers[key] = { seconds = seconds, fn = fn } end
	c.Every = function(seconds, key, fn) w.timers[key] = { seconds = seconds, fn = fn, repeating = true } end
	c.Comm = setmetatable({ loginAt = w.clock - 500, Handle = function() end,
		Send = function() w.sent = w.sent + 1 end, Whisper = function() w.sent = w.sent + 1 end }, { __index = ns.Comm })
	c.King = setmetatable({ Preview = function() return false end, Register = function() end }, { __index = ns.King })
	c.Dues = setmetatable({ Week = function() return w.week end }, { __index = ns.Dues })
	c.Week = { Entries = function() return w.entries end, DayLabel = function() return "Today" end, TimeLabel = function() return "20:00" end,
		Section = function() end }
	c.Vox = setmetatable({ State = function() return nil, w.history, w.shown end }, { __index = ns.Vox })
	c.Consent = { Waiting = function() return w.waiting == true end, NoticeDue = function() return w.notice == true end,
		Frame = function() return { IsShown = function() return w.privacy == true end } end }
	c.Letters = { Frame = function() return nil end }
	c.Layers = { Sharing = function() return false end }
	c.Views = { ShowPage = function(key) w.page = key end, ShowBoard = function(on) w.board = on end }
	c.RealmPages = {}
	-- Constructors register their own dialogs; keep the harness's definitions for later tests.
	local dialogs = {}
	for k, v in pairs(StaticPopupDialogs) do dialogs[k] = v end
	for _, file in ipairs({ "Locales/WeeklyBriefText", "Data", "Treasury", "Board", "WeeklyBrief" }) do
		assert(loadfile(ROOT .. "Olympus/" .. file .. ".lua"))("Olympus", c)
	end
	w.panelDefinition = StaticPopupDialogs.OLYMPUS_WEEKLY_BRIEF
	c.ShowDialog = function(which, text, _, data)
		if w.blockedDialog then return nil end
		local f = { data = data, text = text, shown = true }
		function f:Hide() self.shown = false end
		w.popups[#w.popups + 1] = f
		assert(w.panelDefinition.OnShow)(f, data)
		return f
	end
	for k in pairs(StaticPopupDialogs) do if not dialogs[k] then StaticPopupDialogs[k] = nil end end
	for k, v in pairs(dialogs) do StaticPopupDialogs[k] = v end
	function w:As(fn, ...)
		local old = { guild = GetGuildInfo, combat = InCombatLockdown, instance = IsInInstance, dnd = UnitIsDND,
			secret = issecretvalue, panel = StaticPopupDialogs.OLYMPUS_WEEKLY_BRIEF }
		GetGuildInfo = function() return self.guild, "Member", 3 end
		InCombatLockdown = function() return self.combat == true end
		IsInInstance = function() return self.instance == true end
		UnitIsDND = function() return self.secretDND or self.busy == true end
		issecretvalue = function(value) return self.secretDND ~= nil and value == self.secretDND end
		StaticPopupDialogs.OLYMPUS_WEEKLY_BRIEF = self.panelDefinition
		local result = { pcall(fn, ...) }
		GetGuildInfo, InCombatLockdown, IsInInstance, UnitIsDND = old.guild, old.combat, old.instance, old.dnd
		issecretvalue, StaticPopupDialogs.OLYMPUS_WEEKLY_BRIEF = old.secret, old.panel
		if not result[1] then error(result[2], 0) end
		return unpack(result, 2)
	end
	function w:Guild(name, size, age)
		c.rdb.guilds[name] = { total = size, online = 1, t = self.clock - (age or 0), zones = {} }
	end
	return w, c
end
local function Value(lines, label)
	for _, row in ipairs(lines) do if row.text == label then return row.right end end
end
local function Text(lines)
	local out = {}
	for _, row in ipairs(lines) do out[#out + 1] = row.text .. " " .. (row.right or "") end
	return table.concat(out, "\n")
end

test("Weekly personal brief: Close uses Olympus's localized label without requiring a native global", function()
	local w, c = Client()
	c.L = setmetatable({ LETTERS_CLOSE = "Fechar" }, { __index = c.L })
	local constructor = assert(loadfile(ROOT .. "Olympus/WeeklyBrief.lua"))
	setfenv(constructor, setmetatable({}, { __index = function(_, key)
		assert(key ~= "CLOSE", "the brief must not require an unverified native CLOSE global")
		return _G[key]
	end }))
	local previous = StaticPopupDialogs.OLYMPUS_WEEKLY_BRIEF
	local ok, err = pcall(constructor, "Olympus", c)
	local definition = StaticPopupDialogs.OLYMPUS_WEEKLY_BRIEF
	StaticPopupDialogs.OLYMPUS_WEEKLY_BRIEF = previous
	assert(ok, err)
	eq(definition.button1, "Fechar", "the player's locale, not a hard-coded English fallback")
	eq(w.sent, 0)
end)

test("Weekly public brief: actual census snapshots survive reload, compare one reset only, and never invent absent zeroes", function()
	local w, c = Client()
	local lines = w:As(c.WeeklyBrief.Lines)
	eq(Value(lines, c.L.BRIEF_ARMY), c.L.BRIEF_UNKNOWN)
	eq(Value(lines, c.L.BRIEF_PREVIOUS), c.L.BRIEF_UNKNOWN)
	w:Guild(w.guild, 100); w:Guild("Olympus Vale", 120)
	lines = w:As(c.WeeklyBrief.Lines)
	eq(Value(lines, c.L.BRIEF_ARMY), "220")
	eq(Value(lines, c.L.BRIEF_RANK), c.L.BRIEF_RANK_VALUE:format(2, 2))
	local saved = c.rdb
	w, c = Client(saved); w.week = 101; w.clock = w.clock + 7 * 86400
	w:Guild(w.guild, 110); w:Guild("Olympus Vale", 120)
	lines = w:As(c.WeeklyBrief.Lines)
	eq(Value(lines, c.L.BRIEF_PREVIOUS), "+10", "last reset's saved observation, not the current roster retroactively")
	w.week = 103; lines = w:As(c.WeeklyBrief.Lines)
	eq(Value(lines, c.L.BRIEF_PREVIOUS), c.L.BRIEF_UNKNOWN, "a missed reset is not last week")
	eq(saved.weeklyBrief.weeks[100], nil); eq(saved.weeklyBrief.weeks[101], nil)
	eq(w.sent, 0); eq(c.db.location, false); eq(c.db.layerHelp, false)
end)

test("Weekly personal brief: five read-only lines use held sources, sharing stays off, and missing payment proof stays unknown", function()
	local w, c = Client()
	w.entries = { { id = 7, title = "Raid night", at = w.clock + 3600 } }
	c.Week.MySignup = function(id) return id == 7 and "H" or nil end
	c.Court = { Current = function() return { id = 2 } end }
	w.shown = { q = "Private question", to = "H", at = w.clock + 60 }
	c.Roster = { Fresh = function() return { online = { {}, {}, {} } } end }
	local rows = w:As(c.WeeklyBrief.PersonalLines)
	eq(#rows, 5)
	assert(rows[1]:find("Raid night", 1, true)); assert(rows[1]:find(c.L.BRIEF_SIGNED:match("^(.-)%%s"), 1, true))
	assert(rows[2]:find("Court", 1, true) and rows[2]:find("Vox Populi", 1, true))
	eq(rows[3], c.L.BRIEF_ONLINE:format("3"))
	eq(rows[4], c.L.BRIEF_COMPANION:format(c.L.BRIEF_LOCATION_PRIVATE))
	eq(rows[5], c.L.BRIEF_PAYMENT)
	assert(not table.concat(rows, "\n"):find("Private question", 1, true), "status is not a copy of a restricted question's words")
	eq(w.sent, 0); eq(c.db.location, false); eq(c.db.layerHelp, false)
	-- Both sides already share location. This reads a fresh layer's already-held head only,
	-- never scans a unit, turns on sharing or asks the other player for new data.
	c.Layers = { Sharing = function() return true end, Mine = function() return { mapID = 1453 } end,
		CurrentMap = function() return 1453 end,
		ForMap = function() return { { head = { name = "Nera Vale", guild = "Olympus Vale" } } } end }
	assert(w:As(c.WeeklyBrief.PersonalLines)[4]:find("Nera Vale", 1, true))
	c.Layers.Sharing = function() return false end
	eq(w:As(c.WeeklyBrief.PersonalLines)[4], c.L.BRIEF_COMPANION:format(c.L.BRIEF_LOCATION_PRIVATE), "opt-out takes effect immediately")
	eq(w.sent, 0)
end)

test("Weekly personal brief: the parchment page wraps five labeled sections without sending or exposing private sources", function()
	local w, c = Client()
	local title = "An exceptionally long gathering title that must remain readable across several rows of the parchment"
	w.entries = { { id = 17, title = title, at = w.clock + 60 } }
	c.Court = { Current = function() return { words = "Private audience note" } end }
	w.shown = { q = "Private question", to = "H", at = w.clock + 60 }
	c.rdb.privateLedger = { donor = "Private donor", amount = 900000 }
	local page = assert(c.WeeklyBrief.PersonalPage, "actual personal parchment builder")
	local rows = w:As(page)
	eq(rows[1].text, c.L.BRIEF_PERSONAL_TITLE); eq(rows[1].font, c.King.TITLE)
	local headings = { c.L.BRIEF_NEXT_TITLE, c.L.BRIEF_OPEN_TITLE, c.L.BRIEF_ONLINE_TITLE, c.L.BRIEF_COMPANION_TITLE, c.L.BRIEF_PAYMENT_TITLE }
	local sections, bodies = {}, {}
	for _, row in ipairs(rows) do
		eq(row.right, nil, "long values never compete for a narrow right column")
		eq(#row.text <= c.King.WRAP, true, "paragraph fits the existing Throne wrapping limit")
		if row.font == c.King.TITLE and row.text:match("^%d%.") then sections[#sections + 1] = row.text end
		if row.font == c.King.INK and row.gapAfter then bodies[#bodies + 1] = row.text end
	end
	eq(#sections, 5); eq(#bodies, 6, "intro plus five spaced section bodies")
	for index, heading in ipairs(headings) do
		eq(sections[index], tostring(index) .. ". " .. heading)
	end
	local text = Text(rows):gsub("%s+", " ")
	assert(text:find(c.Cut(title, 60), 1, true), "the same held title as the weekly notice survives paragraph wrapping")
	assert(text:find(c.L.BRIEF_LOCATION_PRIVATE, 1, true))
	assert(text:find(c.L.BRIEF_PAYMENT_UNKNOWN, 1, true))
	assert(not text:find("Private", 1, true), "private questions, audience words and donor records are not copied")
	eq(w.sent, 0); eq(c.db.location, false); eq(c.db.layerHelp, false)
	eq(c.db.weeklyBriefShown, nil, "manual reading does not consume the automatic notice")
	eq(c.rdb.weeklyBrief, nil, "personal reading does not capture or mutate public snapshots")
end)

test("Weekly personal brief: actual Throne home opens and reopens its personal parchment while Board and access rules stay separate", function()
	assert(H.WithThrone and H.AsKing and H.WithUI, "real Throne navigation fixture wired")
	H.WithUI(function()
		H.WithThrone(function(royal, K)
			H.AsKing()
			local w, c = Client()
			c.King = K
			local held, mode = ns.WeeklyBrief, K.mode
			ns.WeeklyBrief = c.WeeklyBrief
			local ok, err = pcall(function()
				K.Show("home")
				local function Link()
					for _, row in ipairs(K.Build()) do if row.text == "> " .. c.L.BRIEF_PERSONAL_TITLE then return row end end
					return assert(nil, "personal page link on the real eligible Throne home")
				end
				Link().onClick(); eq(K.mode, "personalbrief")
				local rows, tab = K.Build()
				eq(tab, c.L.TAB_THRONE); eq(rows[1].text, "< " .. c.L.THRONE_ROOM)
				eq(rows[2].text, c.L.BRIEF_PERSONAL_TITLE)
				local ui = assert(H.LoadUI, "actual isolated UI loader")()
				for _, gamepad in ipairs({ false, true }) do
					H.WithGamepadUI(gamepad, function()
						ui.SelectTab("throne")
						eq(ui.PageId(), "throne/personalbrief")
						local frame = OlympusFrame or OlympusFrameHD or OlympusFrameBasic or OlympusFrameHDBasic
						eq(frame.parchment:IsShown(), true, "the existing Throne parchment in both input modes")
					end)
				end
				rows[1].onClick(); eq(K.mode, "home")
				Link().onClick(); eq(K.Build()[2].text, c.L.BRIEF_PERSONAL_TITLE, "reopenable within the same reset")
				c.WeeklyBrief.Link().onClick(); eq(w.page, "weeklybrief", "public summary remains on Realm/Board")
				eq(K.mode, "personalbrief", "public navigation does not rename the personal subpage")
				eq(w.sent, 0); eq(#royal.sent, 0); eq(#royal.whispered, 0)
				eq(c.db.location, false); eq(c.db.layerHelp, false)
				local me = ns.me
				local memberOK, memberErr = pcall(function()
					ns.me = c.me
					w:As(function()
						eq(K.TabVisible(), false, "ordinary member gains no Throne access")
						local denied, guildTab = K.Build()
						eq(#denied, 0); eq(guildTab, c.L.TAB_GUILD, "existing Guild routing still wins before personal submode")
					end)
				end)
				ns.me = me
				if not memberOK then error(memberErr, 0) end
			end)
			ns.WeeklyBrief, K.mode = held, mode
			if not ok then error(err, 0) end
		end)
	end)
end)

test("Weekly personal brief: the actual Portuguese parchment keeps five readable localized sections and the existing notice", function()
	local w, c = Client()
	c.L = setmetatable({}, { __index = c.L }) -- this fictional client's locale, not the harness's shared strings
	local locale, definition = GetLocale, StaticPopupDialogs.OLYMPUS_WEEKLY_BRIEF
	GetLocale = function() return "ptBR" end
	local ok, err = pcall(function()
		assert(loadfile(ROOT .. "Olympus/Locales/WeeklyBriefText.lua"))("Olympus", c)
		assert(loadfile(ROOT .. "Olympus/WeeklyBrief.lua"))("Olympus", c)
		local rows, sections = w:As(c.WeeklyBrief.PersonalPage), 0
		eq(rows[1].text, "Sua semana, em cinco linhas")
		for _, row in ipairs(rows) do
			eq(row.right, nil); eq(#row.text <= c.King.WRAP, true)
			if row.font == c.King.TITLE and row.text:match("^%d%.") then sections = sections + 1 end
		end
		eq(sections, 5)
		local text = Text(rows):gsub("%s+", " ")
		assert(text:find("Sua contribuição", 1, true))
		assert(text:find(c.L.BRIEF_PAYMENT_UNKNOWN, 1, true))
		eq(#w:As(c.WeeklyBrief.PersonalLines), 5, "notice retains its existing five-line format")
		eq(w.sent, 0); eq(c.db.location, false)
	end)
	GetLocale, StaticPopupDialogs.OLYMPUS_WEEKLY_BRIEF = locale, definition
	if not ok then error(err, 0) end
end)

test("Weekly personal brief: privacy, combat, instance and Busy precede a once-per-reset persistent dismissal", function()
	local w, c = Client()
	for _, key in ipairs({ "waiting", "notice", "privacy", "combat", "instance", "busy" }) do
		w[key] = true
		eq(w:As(c.WeeklyBrief.TryPersonal), false, key)
		w[key] = false
	end
	c.db.alertsAlways = true; w.busy = true
	eq(w:As(c.WeeklyBrief.TryPersonal), false, "alerts always does not override Busy for the weekly panel")
	w.busy = false; w.secretDND = {}
	eq(w:As(c.WeeklyBrief.TryPersonal), false, "secret Busy is never tested as a public boolean")
	w.secretDND = nil; w.blockedDialog = true
	eq(w:As(c.WeeklyBrief.TryPersonal), false, "a dialog that never showed is not marked read")
	eq(c.db.weeklyBriefShown[c.me], nil)
	w.blockedDialog = false
	eq(w:As(c.WeeklyBrief.TryPersonal), true); eq(#w.popups, 1)
	w.popups[1]:Hide()
	eq(w:As(c.WeeklyBrief.TryPersonal), false, "closing stays closed this reset")
	local saved, db = c.rdb, c.db
	w, c = Client(saved, db)
	eq(w:As(c.WeeklyBrief.TryPersonal), false, "actual module reload retains the per-character shown reset")
	w.week = 101
	eq(w:As(c.WeeklyBrief.TryPersonal), true); eq(#w.popups, 1)
	c.me = "Another Reader-Realm"
	eq(w:As(c.WeeklyBrief.TryPersonal), true, "another character has its own local weekly view")
	eq(w.sent, 0); eq(c.db.location, false); eq(c.db.layerHelp, false)
end)

test("Weekly personal brief: gamepad uses the real Olympus dialog and Close preserves the shown reset", function()
	assert(H and H.WithUI and H.WithGamepadUI, "weekly brief UI helpers wired")
	H.WithUI(function()
		H.WithGamepadUI(true, function(game)
			local w, c = Client()
			c.ShowDialog = ns.ShowDialog
			eq(w:As(c.WeeklyBrief.TryPersonal), true)
			local f = assert(ns.Dialog.Find("OLYMPUS_WEEKLY_BRIEF"))
			eq(f.editBox:IsShown(), false, "no edit box takes the keyboard")
			f.buttons[1]:Click(); eq(f:IsShown(), false)
			eq(w:As(c.WeeklyBrief.TryPersonal), false)
			eq(#game.shown, 0, "never the native game popup with Blizzard's gamepad UI")
		end)
	end)
end)

test("Weekly personal brief: actual login callback schedules the privacy-first weekly panel, not a raid warning", function()
	local w, c = Client()
	w:As(w.listeners.LOGIN)
	local timer = assert(w.timers["personal weekly brief"], "weekly panel is scheduled by the actual login callback")
	eq(timer.seconds, 60); eq(timer.repeating, true)
	w.waiting = true
	w:As(timer.fn); eq(#w.popups, 0)
	w.waiting = false
	w:As(timer.fn); eq(#w.popups, 1)
	w:As(timer.fn); eq(#w.popups, 1, "the next tick is silent in the same reset")
	eq(w.sent, 0)
end)

test("Weekly public brief: rebuilding, stale own guild, ties and changed report coverage remain explicit", function()
	local w, c = Client()
	w:Guild(w.guild, 100); w:Guild("Olympus Vale", 100)
	c.Comm.loginAt = w.clock
	eq(Value(w:As(c.WeeklyBrief.Lines), c.L.BRIEF_ARMY), c.L.BRIEF_UNKNOWN)
	c.Comm.loginAt = w.clock - 500
	eq(Value(w:As(c.WeeklyBrief.Lines), c.L.BRIEF_RANK), c.L.BRIEF_RANK_VALUE:format(1, 2))
	w.week = 101; c.rdb.guilds["Olympus Vale"] = nil
	eq(Value(w:As(c.WeeklyBrief.Lines), c.L.BRIEF_PREVIOUS), c.L.BRIEF_UNKNOWN, "missing guild is not army shrinkage")
	w:Guild(w.guild, 100, c.Data.TOTAL_KEEP + 1); w:Guild("Olympus Vale", 120)
	eq(Value(w:As(c.WeeklyBrief.Lines), c.L.BRIEF_RANK), c.L.BRIEF_UNKNOWN, "stale own roster cannot establish a rank")
end)

test("Weekly public brief: Board opens the existing Realm page, which is read-only and searchable", function()
	local w, c = Client()
	w:Guild(w.guild, 100)
	w.entries = { { title = "Public raid night", at = w.clock + 3600 } }
	local link
	for _, row in ipairs(w:As(c.Board.Lines)) do if row.text:find(c.L.BRIEF_TITLE, 1, true) then link = row end end
	assert(link and link.onClick, "a public summary entry on the existing Board")
	link.onClick(); eq(w.page, "weeklybrief")
	local page = c.RealmPages[1]
	eq(page.key, "weeklybrief"); eq(page.Link, nil, "no extra outer tab or Realm tree entry")
	local lines = w:As(page.Lines)
	assert(Text(lines):find("Public raid night", 1, true))
	lines[1].onClick(); eq(w.board, true)
	local found = w:As(page.Lines, "public raid")
	assert(Text(found):find("Public raid night", 1, true))
	eq(Value(found, c.L.BRIEF_ARMY), nil, "search matches only the facts it asks for")
	eq(w.sent, 0)
end)

test("Weekly public brief: only public Vox results persist, restricted questions and filtered words never leak", function()
	local w, c = Client()
	w.history = { { q = "Private guild vote", to = "G", answers = { "Yes", "No" }, counts = { 1, 0 }, voters = 1, t = w.clock } }
	w.shown = { q = "Private Hand vote", to = "H", answers = { "Yes", "No" }, counts = { 1, 0 }, voters = 1, at = w.clock }
	local lines = w:As(c.WeeklyBrief.Lines)
	eq(Value(lines, c.L.BRIEF_VOX), c.L.BRIEF_UNKNOWN); eq(c.rdb.weeklyBrief.vox, nil)
	w.shown = { q = "Public raid vote", to = "E", answers = { "Yes", "No" }, counts = { 1, 0 }, voters = 1, resultsAt = w.clock }
	assert(Value(w:As(c.WeeklyBrief.Lines), c.L.BRIEF_VOX):find("Public raid vote", 1, true))
	w.shown = nil; w.history = {}
	assert(Value(w:As(c.WeeklyBrief.Lines), c.L.BRIEF_VOX):find("Public raid vote", 1, true), "last public result survives the next question")
	for _, audience in ipairs({ "H", "M", "G" }) do
		w.shown = { q = "Private replacement", to = audience, answers = { "Yes", "No" }, counts = { 1, 0 }, voters = 1, resultsAt = w.clock + 1 }
		assert(not Value(w:As(c.WeeklyBrief.Lines), c.L.BRIEF_VOX):find("Private replacement", 1, true))
		eq(c.rdb.weeklyBrief.vox.q, "Public raid vote", "audience downgrade cannot replace the cache with private words")
	end
	c.Filter = { Hides = function() return true end }
	eq(Value(w:As(c.WeeklyBrief.Lines), c.L.BRIEF_VOX), c.L.FILTER_WORDS_HIDDEN_SHORT)
	assert(not Text(w:As(c.WeeklyBrief.Lines)):find("Private", 1, true))
end)

test("Weekly public brief: malformed saved snapshots and result records stay unknown rather than becoming facts", function()
	local w, c = Client()
	c.rdb.weeklyBrief = { weeks = {
		[100] = { total = 22, known = -1, coverage = "same", at = w.clock },
		[99] = { total = math.huge, known = 2, coverage = "same", at = w.clock },
		["hostile"] = true,
	}, vox = true }
	local lines = w:As(c.WeeklyBrief.Lines)
	eq(Value(lines, c.L.BRIEF_ARMY), c.L.BRIEF_UNKNOWN)
	eq(Value(lines, c.L.BRIEF_PREVIOUS), c.L.BRIEF_UNKNOWN)
	eq(Value(lines, c.L.BRIEF_VOX), c.L.BRIEF_UNKNOWN)
	eq(next(c.rdb.weeklyBrief.weeks), nil); eq(c.rdb.weeklyBrief.vox, nil)
	c.rdb.weeklyBrief.weeks[100] = { known = 1, coverage = "same", at = w.clock }
	eq(Value(w:As(c.WeeklyBrief.Lines), c.L.BRIEF_ARMY), c.L.BRIEF_UNKNOWN, "missing counts are not usable snapshots")
	c.rdb.weeklyBrief.weeks[100] = { total = 22.5, known = 1, coverage = "same", at = w.clock }
	c.rdb.weeklyBrief.weeks[99.5] = { total = 1, known = 1, coverage = "same", at = w.clock }
	eq(Value(w:As(c.WeeklyBrief.Lines), c.L.BRIEF_ARMY), c.L.BRIEF_UNKNOWN, "fractional count is not silently rounded into a fact")
	eq(next(c.rdb.weeklyBrief.weeks), nil, "fractional week keys cannot grow an unbounded history between the two resets")
end)

test("Weekly public brief: spending requires current public permission and public book provenance, never private donor data", function()
	local w, c = Client()
	c.rdb.treasuryFlags = { balance = true }
	local from = "Tamsin Ledger-Realm"
	c.rdb.treasuryReports = { [from] = { epoch = c.Treasury.EPOCH, guild = "Olympus", allOut = 500,
		rank = { { name = "Private payer", money = 900000 } } } }
	eq(w:As(c.Treasury.PublicSpending), nil, "a private/full report does not establish public provenance")
	eq(Value(w:As(c.WeeklyBrief.Lines), c.L.BRIEF_SPENDING), c.L.BRIEF_UNKNOWN)
	c.rdb.treasuryReports[from].part = { balance = true }
	local copper, books = w:As(c.Treasury.PublicSpending)
	eq(copper, 500); eq(books, 1)
	local text = Text(w:As(c.WeeklyBrief.Lines))
	assert(not text:find("Private payer", 1, true)); assert(not text:find("900000", 1, true))
	c.rdb.treasuryFlags.balance = false
	eq(w:As(c.Treasury.PublicSpending), nil)
	eq(Value(w:As(c.WeeklyBrief.Lines), c.L.BRIEF_SPENDING), nil, "revoking disclosure removes the line immediately")
	c.rdb.treasuryFlags.balance = true; c.rdb.treasuryReports[from].part = { ranking = true }
	eq(w:As(c.Treasury.PublicSpending), nil, "ranking alone never discloses spending")
	c.rdb.treasuryReports[from] = nil
	c.rdb.treasuryReports["Pretender-Realm"] = { epoch = c.Treasury.EPOCH, guild = "Olympus", allOut = 1, part = { balance = true } }
	eq(w:As(c.Treasury.PublicSpending), nil, "a forged keeper grants no source provenance")
end)

test("Weekly public brief: an own keeper book contributes only while its real sharing consent remains on", function()
	local w, c = Client()
	w.guild, c.me = "Olympus", "Tamsin Ledger-Realm"
	c.rdb.treasuryFlags = { balance = true }
	local b = w:As(c.Treasury.BookOf, c.me, true)
	b.sums = { version = 3, allIn = 0, allOut = 345, transIn = 0, transOut = 0,
		byDonor = {}, days = {}, itemsIn = {}, weeks = {} }
	c.db.treasurerShares = false
	eq(w:As(c.Treasury.PublicSpending), nil)
	c.db.treasurerShares = true
	local copper, books = w:As(c.Treasury.PublicSpending)
	eq(copper, 345); eq(books, 1)
	c.db.treasurerShares = false
	eq(w:As(c.Treasury.PublicSpending), nil, "revocation does not leave a cached public amount")
end)
