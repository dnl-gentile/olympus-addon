local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]weekly%-brief%.lua$")) or "./"

local function Client(saved)
	local w = { clock = 1800000000, week = 100, guild = "Olympus Ember", sent = 0, entries = {}, history = {}, listeners = {} }
	local c = setmetatable({ me = "Brief Reader-Realm", faction = "Alliance", realm = "Realm", group = "Realm",
		rdb = saved or { guilds = {} }, db = { location = false, layerHelp = false }, Alts = false, Moderation = {} }, { __index = ns })
	w.c = c
	c.Now = function() return w.clock end
	c.IsMember = function() return true end
	c.On = function(event, fn) w.listeners[event] = fn end
	c.Fire, c.After, c.Every, c.RegisterEvent = function() end, function() end, function() end, function() end
	c.Comm = setmetatable({ loginAt = w.clock - 500, Handle = function() end,
		Send = function() w.sent = w.sent + 1 end, Whisper = function() w.sent = w.sent + 1 end }, { __index = ns.Comm })
	c.King = setmetatable({ Preview = function() return false end, Register = function() end }, { __index = ns.King })
	c.Dues = setmetatable({ Week = function() return w.week end }, { __index = ns.Dues })
	c.Week = { Entries = function() return w.entries end, DayLabel = function() return "Today" end, TimeLabel = function() return "20:00" end,
		Section = function() end }
	c.Vox = setmetatable({ State = function() return nil, w.history, w.shown end }, { __index = ns.Vox })
	c.Views = { ShowPage = function(key) w.page = key end, ShowBoard = function(on) w.board = on end }
	c.RealmPages = {}
	-- Constructors register their own dialogs; keep the harness's definitions for later tests.
	local dialogs = {}
	for k, v in pairs(StaticPopupDialogs) do dialogs[k] = v end
	for _, file in ipairs({ "Locales/WeeklyBriefText", "Data", "Treasury", "Board", "WeeklyBrief" }) do
		assert(loadfile(ROOT .. "Olympus/" .. file .. ".lua"))("Olympus", c)
	end
	for k in pairs(StaticPopupDialogs) do if not dialogs[k] then StaticPopupDialogs[k] = nil end end
	for k, v in pairs(dialogs) do StaticPopupDialogs[k] = v end
	function w:As(fn, ...)
		local old = GetGuildInfo
		GetGuildInfo = function() return self.guild, "Member", 3 end
		local result = { pcall(fn, ...) }
		GetGuildInfo = old
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
end)

test("Weekly public brief: spending requires current public permission and public book provenance, never private donor data", function()
	local w, c = Client()
	c.rdb.treasuryFlags = { balance = true }
	local from = "Pyralis Ashandar-Realm"
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
	w.guild, c.me = "Olympus", "Pyralis Ashandar-Realm"
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
