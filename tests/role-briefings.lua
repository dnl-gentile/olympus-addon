-- The duty letters (RoleBriefings.lua): the King's letter for each office a character holds, the
-- guild master's checklist letter, the Apostles' launch letter and the launch letter. Nothing is
-- made, shown or said while the letters are not LIVE (the author's call: preview only, from the
-- Workshop and for the King); once LIVE, only real appointments make them, one per office and its
-- holder (a removal, a roster gap or a re-signed list never makes a second). The Church's and the
-- guild masters' are made here from the real Church (tests/church-world.lua) and the real Nominees;
-- the Throne's and the Treasury's sources are stood in. Every name is invented.
local ns, test, eq, extra = ...
local ROOT = assert(extra and extra.ROOT)
local ADDON = ROOT .. "Olympus/"
local H = extra

assert(loadfile(ADDON .. "Locales/RoleBriefingsText.lua"))("Olympus", ns)
assert(loadfile(ADDON .. "Locales/ArenaFightsText.lua"))("Olympus", ns)
local L = ns.L

local function Plain(s) return (tostring(s or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Text(lines)
	local out = {}
	for _, line in ipairs(lines or {}) do if type(line.text) == "string" then out[#out + 1] = Plain(line.text) end end
	return table.concat(out, "\n")
end
local function Row(lines, text)
	for _, line in ipairs(lines or {}) do
		if type(line.text) == "string" and Plain(line.text):find(text, 1, true) then return line end
	end
	return nil
end
-- A body's words as one line (the page wraps them into rows).
local function Flat(s) return (tostring(s or ""):gsub("%s+", " ")) end

-- The module in a namespace of its own over the harness's: its page list, its locale table (so the
-- launch letter it may register never reaches the harness's), the role sources `over` stands in.
local function Fresh(over)
	local c = setmetatable({ RealmPages = {}, db = {}, L = setmetatable({}, { __index = ns.L }) }, { __index = ns })
	for k, v in pairs(over or {}) do c[k] = v end
	c.On = c.On or function() end
	c.After = c.After or function() end
	assert(loadfile(ADDON .. "RoleBriefings.lua"))("Olympus", c)
	return c.RoleBriefings, c
end

-- The Throne's, the Treasury's and the Watch's sources stood in (the King, a Steward, a Hand, the
-- Treasurer and a keeper, a Watcher and a moderator); GetGuildInfo as options say.
local function WithRoles(options, fn)
	options = options or {}
	local saved = { guildInfo = GetGuildInfo }
	local rank, clock, opened, printed = options.rank == nil and 3 or options.rank, 2200000000, {}, {}
	local ok, err = pcall(function()
		GetGuildInfo = function() return options.guild or "Olympus II", "rank", rank end
		local RB, c = Fresh({
			IsMember = function() return options.member ~= false end,
			IsFederation = function(g) return type(g) == "string" and g:find("Olympus", 1, true) ~= nil end,
			IsKingGuild = function(g) return g == "Olympus" end,
			IsHighCouncillor = function() return options.council == true end,
			CouncilTitle = function() return options.councilDept and { title = "Marshal", dept = options.councilDept } or nil end,
			King = {
				IsKing = function() return options.king == true end,
				IsSteward = function() return options.steward == true end,
				IsHand = function() return options.hand == true end,
			},
			Workshop = { Visible = function() return options.author == true end },
			Watch = { CanRead = function() return options.watch == true end, CouncilDeskShown = function() return true end },
			WatchChat = { IsNamedWatcher = function() return options.watcher == true end, IsMod = function() return options.mod == true end },
			Treasury = { TreasurerPin = function() return options.pin end, RealKeeper = function() return options.keeper == true end },
			Church = { Role = function() return options.churchRole end, Place = function() return nil end, State = function() return { apostle = {}, corr = {}, corrOf = {} } end },
			Nominees = {
				RoleOf = function() return options.nomineeRole, options.department end,
				DepartmentName = function(d) return d end,
			},
			Borders = { OwnLookAllowed = function() return options.redCross == true end },
			UI = { SelectTab = function(tab) opened[#opened + 1] = "tab:" .. tostring(tab) return true end, Refresh = function() end,
				ShowCopy = function(title, text) opened[#opened + 1] = "copy:" .. tostring(text) end },
			Views = { ShowPage = function(page) opened[#opened + 1] = "page:" .. tostring(page) end },
			-- (1.4.4: the version letter's window takes a duty letter; see Brief.Window.)
			Letters = { ShowText = function(o) opened[#opened + 1] = "letter:" .. tostring(o and o.title) return true end },
			Now = function() clock = clock + 1 return clock end,
			Print = function(m) printed[#printed + 1] = tostring(m) end,
		})
		RB.LIVE = options.live ~= false
		fn(RB, c, { setRank = function(v) rank = v end, opened = opened, printed = printed, clock = function() return clock end,
			advance = function(s) clock = clock + s end })
	end)
	GetGuildInfo = saved.guildInfo
	if not ok then error(err, 0) end
end

---------------------------------------------------------------------------
-- LIVE: off, nothing by itself; the author and the King preview every letter
---------------------------------------------------------------------------

-- Review of the first duty letters: they had no gate, and every officer, guild master, councillor
-- and Church holder got them at the first login after the update, against the author's call of
-- 2026-10-20 (preview only, until he turns them on). Fails before: the scan made the letter.
test("role briefings: while not LIVE a real office makes no letter, no line in chat, no Realm link and no Church link; /oly duties says they are not out", function()
	WithRoles({ live = false, rank = 0, churchRole = "M" }, function(RB, c, w)
		eq(RB.LIVE, false)
		eq(RB.Scan(false), 0, "nothing made")
		eq(#RB.Letters(), 0)
		eq(type(c.db.roleBriefings), "nil", "nothing saved")
		eq(#w.printed, 0, "nothing said")
		eq(RB.Link(), nil, "no Realm link for a member")
		eq(RB.Has("missionary"), false, "so no Church > Mine link either")
		eq(RB.Slash(""), false)
		eq(w.printed[#w.printed], L.RB_NOT_LIVE)
		eq(#w.opened, 0, "no page opened")
	end)
	-- The shipped file: (changed on purpose, 1.4.0, the launch: the author turned them on; off until then.)
	local src = assert(io.open(ADDON .. "RoleBriefings.lua")):read("*a")
	assert(src:find("\nBrief.LIVE = true ", 1, true), "RoleBriefings.lua ships with Brief.LIVE = true for the launch")
end)

test("role briefings: the author and the King preview every letter from the Realm (and the Workshop); a preview saves, sends and marks nothing, and its buttons do nothing but copy the site", function()
	for _, who in ipairs({ { author = true }, { king = true, rank = 0, guild = "Olympus" } }) do
		local opts = { live = false, rank = who.rank, guild = who.guild, author = who.author, king = who.king }
		WithRoles(opts, function(RB, c, w)
			eq(RB.PreviewAllowed(), true)
			local link = assert(RB.Link(), "the Realm's link")
			eq(Plain(link.text):find(L.RB_LINK_PREVIEW, 1, true) ~= nil, true)
			local workshop = {}
			RB.WorkshopLines(workshop)
			eq(#workshop, 1); eq(workshop[1].noReport, true, "not in the Workshop's copy")
			local list = RB.Page()
			assert(Plain(list[1].text):match("^< "), "Back first")
			local previews = RB.PreviewList()
			eq(#previews, 26, "the launch, the guild master, the council and its six departments, 5 offices, 6 correspondents, 6 more")
			local seen = {}
			for _, x in ipairs(previews) do
				seen[x.kind] = true
				local row = assert(Row(list, "> " .. x.label), "listed: " .. x.label)
				row.onClick()
				local page = RB.Page()
				assert(Flat(Text(page)):find(Flat(L.RB_PREVIEW_LETTER), 1, true), x.label .. ": marked as a preview")
				eq(page[#page].text, L.HONOR_LETTER_SIGN, x.label .. ": signed by the King")
				for _, line in ipairs(page) do
					local t = Plain(line.text or "")
					if line.onClick and t:sub(1, 2) == "> " then
						eq(t, "> " .. L.LETTERS_COPY_LINK, x.label .. ": only the site's copy works in a preview: " .. t)
					end
				end
				page[1].onClick() -- Back to the list
			end
			for kind in pairs(RB.KINDS) do assert(seen[kind], "previewed: " .. kind) end
			eq(type(c.db.roleBriefings), "nil", "nothing saved")
			eq(#w.printed, 0, "nothing said")
			eq(#RB.Letters(), 0)
		end)
	end
	-- Anyone else: no preview, nor a way to one.
	WithRoles({ live = false, council = true }, function(RB)
		eq(RB.PreviewAllowed(), false); eq(RB.Preview("council"), false)
		local lines = {}
		RB.WorkshopLines(lines)
		eq(#lines, 0)
	end)
end)

---------------------------------------------------------------------------
-- The letters themselves: the King's voice, from the drafted texts
---------------------------------------------------------------------------

-- (The author's call of 2026-11-05: the first letters tried the streamer's voice and read as cheap.
-- Every letter is now a sober missive on parchment, medieval and objective: a salutation, the
-- charge, the mark, the rights, one rule; no jokes, no slang, no exclamation marks. Fails before:
-- "Okay, listen." and "Let's go!" opened and closed them.)
local CASUAL = { "Okay", "Hey,", "Let's go", "huge", "big deal", "No pressure", "Yeah", "Honestly", "cry wolf", "Nice.", "n't" }
-- The letter's first paragraph, "To ...," (the page wraps a long one over more than one row).
local function Salutation(page)
	local rows
	for _, line in ipairs(page) do
		local t = Plain(line.text or "")
		if not rows and t:match("^To ") then rows = {} end
		if rows then
			rows[#rows + 1] = t
			if line.gapAfter then
				local s = table.concat(rows, " ")
				return s:match(",$") and s or nil
			end
		end
	end
	return nil
end
test("role briefings: every letter is the King's, a sober missive signed - The King: a salutation, no exclamation marks, never the streamer's voice; the old neutral briefings and the Legate's design note are gone", function()
	WithRoles({ author = true, redCross = true }, function(RB)
		for _, x in ipairs(RB.PreviewList()) do
			RB.Preview(x.kind, x.dept)
			local page = RB.Page()
			local text = Text(page)
			eq(page[#page].text, "- The King", x.label)
			eq(text:lower():find("briefing", 1, true), nil, x.label .. ": no neutral briefing voice")
			eq(text:lower():find("centurion", 1, true), nil, x.label .. ": the wire's old name is never taught")
			eq(text:find("wingless", 1, true), nil, x.label .. ": no internal design note")
			assert(Salutation(page), x.label .. ": opens as a missive, with its salutation")
			eq(text:find("!", 1, true), nil, x.label .. ": no exclamation marks")
			for _, words in ipairs(CASUAL) do eq(text:find(words, 1, true), nil, x.label .. ": never the streamer's voice: " .. words) end
		end
		RB.Preview("legate")
		local legate = Flat(Text(RB.Page()))
		for _, words in ipairs({ "To a Legate of <", "up to 39 guildmates who agreed, 40 in all", "Nothing is done by itself: no guild invite, kick or promotion",
			"One rule: list only those who said yes." }) do
			assert(legate:find(words, 1, true), "the Legate's letter: " .. words)
		end
		RB.Preview("launch")
		local launch = Flat(Text(RB.Page()))
		assert(launch:find("The beta is ended. Olympus is live.", 1, true), launch)
		assert(launch:find("olympus.roachcouncil.com", 1, true), "the site in the words")
	end)
end)

test("role briefings: the launch letter's button copies the site's link in a copyable pop-up, in a preview too", function()
	WithRoles({ author = true }, function(RB, c, w)
		RB.Preview("launch")
		local button = assert(Row(RB.Page(), "> " .. L.LETTERS_COPY_LINK))
		button.onClick()
		eq(w.opened[#w.opened], "copy:https://olympus.roachcouncil.com/")
		eq(RB.SITE, "https://olympus.roachcouncil.com/")
	end)
end)

test("role briefings: a councillor's letter adds his department's paragraph; an Apostle's the red cross only when he may wear it", function()
	WithRoles({ council = true, councilDept = "Department of Heraldry" }, function(RB)
		eq(RB.Scan(true), 1)
		eq(RB.OpenKind("council"), true)
		local page = Flat(Text(RB.Page()))
		assert(page:find(Flat(L.RB_COUNCIL_BADGE .. " " .. L.RB_COUNCIL_HERALDRY), 1, true), page)
	end)
	WithRoles({ council = true }, function(RB)
		RB.Scan(true); RB.OpenKind("council")
		eq(Flat(Text(RB.Page())):find(L.RB_COUNCIL_BADGE, 1, true), nil, "no title, no department paragraph")
	end)
	for _, red in ipairs({ true, false }) do
		WithRoles({ churchRole = "A", redCross = red }, function(RB, c)
			-- (Named long after the letters went out: the naming letter, not the launch one.)
			c.db.roleBriefings = { rule = RB.RULE, entries = {}, active = {}, seq = 0, liveAt = 0 }
			eq(RB.Scan(true), 1)
			eq(RB.Letters()[1].kind, "apostle")
			RB.OpenKind("apostle")
			eq(Flat(Text(RB.Page())):find(Flat(L.RB_APOSTLE_RED), 1, true) ~= nil, red, "the red cross line")
		end)
	end
end)

-- Review of the first duty letters: the Legate's letter showed players an internal design note
-- (RB_LEGATE_3, "the former wingless bronze office frame is not the Legate identity"). Fails before:
-- it was the letter's last paragraph.
test("role briefings: a Legate's letter says his job, never the High Council's design notes", function()
	WithRoles({ nomineeRole = "centurion" }, function(RB)
		eq(RB.Scan(true), 1)
		eq(RB.OpenKind("legate"), true)
		local page = Flat(Text(RB.Page()))
		eq(page:find("wingless", 1, true), nil, "no design note")
		eq(page:find("identity", 1, true), nil, "no design note")
		assert(page:find("40", 1, true) and page:find("39", 1, true), page)
	end)
end)

test("role briefings: each office has its letter, title and buttons; a Justice correspondent gets his own letter, not the Watcher's; the King gets none", function()
	local scenarios = {
		{ key = "council", opts = { council = true } },
		{ key = "steward", opts = { steward = true } },
		{ key = "hand", opts = { hand = true } },
		{ key = "treasurer", opts = { pin = 1 } },
		{ key = "keeper", opts = { keeper = true } },
		{ key = "watcher", opts = { watcher = true } },
		{ key = "moderator", opts = { mod = true } },
		{ key = "legate", opts = { nomineeRole = "centurion" } },
		{ key = "correspondent", opts = { nomineeRole = "correspondent", department = "Department of War" } },
	}
	for _, scenario in ipairs(scenarios) do
		WithRoles(scenario.opts, function(RB)
			eq(RB.Scan(true), 1, scenario.key)
			eq(RB.Letters()[1].kind, scenario.key)
			assert(RB.OpenKind(scenario.key), scenario.key)
			local page = RB.Page()
			eq(Plain(page[2].text), RB.Title(RB.Letters()[1]), scenario.key .. ": its title")
			assert(#Text(page) > 300, scenario.key .. ": its words")
		end)
	end
	-- A treasurer's other pinned character is no keeper; a correspondent of War gets War's words.
	WithRoles({ pin = 2, keeper = true }, function(RB) eq(RB.Scan(true), 0) end)
	WithRoles({ nomineeRole = "correspondent", department = "Department of War" }, function(RB)
		RB.Scan(true); RB.OpenKind("correspondent")
		local page = RB.Page()
		eq(Plain(page[2].text), L.RB_CORR_WAR_TITLE)
		assert(Row(page, "> " .. L.RB_BTN_GUILD) and Row(page, "> " .. L.RB_BTN_WAR), "the Guild tab and the War Room")
	end)
	WithRoles({ nomineeRole = "correspondent", department = "Council of Justice", watcher = true }, function(RB)
		eq(RB.Scan(true), 1, "one letter: his correspondent's")
		eq(RB.Letters()[1].kind, "correspondent")
	end)
	WithRoles({ king = true, rank = 0, guild = "Olympus", council = true }, function(RB)
		eq(RB.Scan(true), 0, "the King signs them; he gets none")
	end)
	WithRoles({ council = true, mod = true }, function(RB)
		eq(RB.Scan(true), 1, "a councillor's own letter says what a moderator's would")
		eq(RB.Letters()[1].kind, "council")
	end)
end)

test("role briefings: once LIVE a new letter is said in one chat line and kept for rereading; Back leads to the list", function()
	WithRoles({ steward = true }, function(RB, c, w)
		eq(RB.Scan(false), 1)
		eq(w.printed[#w.printed], L.RB_READY:format(L.RB_STEWARD_TITLE))
		eq(RB.Scan(false), 0, "once")
		local link = assert(RB.Link())
		eq(Plain(link.text):find(L.RB_LINK, 1, true) ~= nil, true)
		eq(RB.Letters()[1].read, false)
		eq(RB.OpenKind("steward"), true)
		eq(w.opened[#w.opened], "letter:" .. L.RB_STEWARD_TITLE, "(1.4.4) opened in the version letter's window")
		eq(RB.Letters()[1].read, true, "read once opened")
		local page = RB.Page()
		eq(Plain(page[1].text), L.RB_BACK)
		page[1].onClick()
		assert(Row(RB.Page(), "> " .. L.RB_STEWARD_TITLE), "the list again, with the letter")
	end)
end)

-- 1.4.4 (the author's ask: a duty letter in a window of its own, like the version letter, not on
-- the Olympus window's page). Fails before: Open led to the Realm page alone.
test("role briefings: a letter opens in the version letter's window (Letters.ShowText): the page's title as the window's, the letter's title, its paragraphs, the King's signature and a button back to the page; a guild master's window carries his opening, grant and closing words; without that window, the page as before", function()
	WithRoles({ steward = true }, function(RB, c, w)
		eq(RB.Scan(false), 1)
		local shown
		c.Letters = { ShowText = function(o) shown = o return true end }
		eq(RB.OpenKind("steward"), true)
		assert(type(shown) == "table", "the window")
		eq(shown.head, L.RB_PAGE_TITLE); eq(shown.title, L.RB_STEWARD_TITLE); eq(shown.sign, L.HONOR_LETTER_SIGN)
		eq(shown.button, L.RB_BACK); eq(shown.onButton, RB.ShowPage, "its button: the page of every duty letter")
		local e = RB.Letters()[1]
		eq(shown.body, table.concat(RB.Body(e), "\n\n"), "the letter's paragraphs")
		assert(w.opened[#w.opened] ~= "page:rolebriefings", "not the page")
		eq(e.read, true)
		-- A guild master's window: the words round his checklist (the checklist stays on the page).
		local gm = RB.Window({ kind = "guildmaster", id = "gm" })
		eq(gm.title, L.RB_GM_TITLE); eq(gm.body, L.RB_GM_OPEN .. "\n\n" .. L.RB_GM_GET .. "\n\n" .. L.RB_GM_CLOSE)
		-- Without the window (an older Letters module): the page, as before.
		c.Letters = false
		eq(RB.Open(e.id), true)
		eq(w.opened[#w.opened], "page:rolebriefings", "the page")
	end)
end)

---------------------------------------------------------------------------
-- The real Church (tests/church-world.lua)
---------------------------------------------------------------------------

local World = assert(loadfile(ROOT .. "tests/church-world.lua"))(ns, ROOT)
-- A client of that world with the duty letters loaded into its own namespace, LIVE. The other role
-- sources are absent there, so only the Church's own state can make a letter.
local function ChurchLetters(w, cl)
	local c = cl.c
	c.RealmPages = {}
	c.King, c.Watch, c.Treasury, c.Nominees, c.WatchChat = {}, {}, {}, {}, {}
	c.db.roleBriefings = nil
	w:As(cl, function() assert(loadfile(ADDON .. "RoleBriefings.lua"))("Olympus", c) end)
	c.RoleBriefings.LIVE = true
	return c.RoleBriefings
end

-- Review of the first duty letters: an Apostle's letter was keyed on Church.Place().since, which is
-- the signed Apostles list's time for a signed Apostle, so every re-sign of that list made a second
-- letter for the same office. Fails before the fix: the re-signed list makes 1 more letter.
test("role briefings: an Apostle's letter is keyed on the office and its holder, so a re-signed Apostles list never duplicates it (real Church)", function()
	local apostle = "Aldric Vane-Realm"
	local w = World.New({ apostles = { apostle } })
	local cl = w:Client(apostle, { view = true })
	local RB = ChurchLetters(w, cl)
	eq(w:As(cl, cl.Church.Role, apostle), "A")
	eq(w:As(cl, RB.Scan, true), 1, "the Apostle's letter")
	-- The same Apostles signed again a day later: the signed place is re-dated, the office is not new.
	w.clock = w.clock + 86400
	w:SignedList({ apostle }, true, w.clock)
	eq(w:As(cl, function() return cl.Church.Place(apostle).since end), w.clock, "the re-sign re-dates the signed place")
	eq(w:As(cl, RB.Scan, true), 0, "the same Apostle in the same office: no second letter")
	eq(#w:As(cl, RB.Letters), 1)
end)

test("role briefings: an Apostle at the launch gets the Church's launch letter, one named later the naming letter; a missionary his letter naming his Apostle (real Church)", function()
	local A1, A2 = "Aldric Vane-Realm", "Bera Stone-Realm"
	local w = World.New({ apostles = { A1 } })
	local a1 = w:Client(A1, { view = true })
	local m1 = w:Client("Mira Wells", { view = true })
	local RB = ChurchLetters(w, a1)
	eq(w:As(a1, RB.Scan, true), 1)
	eq(w:As(a1, RB.Letters)[1].kind, "apostlelaunch", "an Apostle when the letters went out")
	eq(w:As(a1, RB.Has, "apostle"), true, "found as the Apostle's letter")
	-- A second Apostle signed after the launch's days, on an account whose letters went out then.
	w.clock = w.clock + (RB.LAUNCH_DAYS + 1) * 86400
	w:SignedList({ A1, A2 }, true, w.clock)
	local a2 = w:Client(A2, { view = true })
	local RB2 = ChurchLetters(w, a2)
	a2.c.db.roleBriefings = { rule = RB2.RULE, entries = {}, active = {}, seq = 0, liveAt = w.clock - (RB2.LAUNCH_DAYS + 1) * 86400 }
	eq(w:As(a2, RB2.Scan, true), 1)
	eq(w:As(a2, RB2.Letters)[1].kind, "apostle")
	-- A1 names a missionary: his letter names A1's network.
	w:Act(a1, a1.Church.NameMissionary, "Mira Wells")
	w:Presence()
	local RBm = ChurchLetters(w, m1)
	eq(w:As(m1, m1.Church.Role, m1.name), "M")
	eq(w:As(m1, RBm.Scan, true), 1)
	eq(w:As(m1, RBm.OpenKind, "missionary"), true)
	local page = Flat(Text(w:As(m1, RBm.Page)))
	assert(page:find("in " .. ns.DisplayName(A1) .. "'s network", 1, true), page)
	-- Church > Mine: the link to it, now that it exists.
	local lines = w:As(m1, m1.View.MineLines)
	local link = assert(Row(lines, L.RB_CHURCH_LETTER_LINK), "the Church's link")
	w:As(m1, link.onClick)
	eq(w:As(m1, RBm.Letters)[1].read, true, "the link opened it")
end)

test("role briefings: Church > Mine shows no letter link while the letters are not out (real Church)", function()
	local w = World.New({ apostles = { "Aldric Vane-Realm" } })
	local a1 = w:Client("Aldric Vane-Realm", { view = true })
	local RB = ChurchLetters(w, a1)
	RB.LIVE = false
	eq(w:As(a1, RB.Scan, true), 0)
	eq(Row(w:As(a1, a1.View.MineLines), L.RB_CHURCH_LETTER_LINK), nil)
end)

---------------------------------------------------------------------------
-- The real Nominees: the guild master's live checklist and his Guild tab
---------------------------------------------------------------------------

-- A guild master's client with the real Nominees.lua and the duty letters, LIVE (as
-- tests/nominees-durable.lua builds its client). The Church's correspondent, the Watchers, the
-- charter and the bank are read from stand-ins w can change.
local function GuildMaster(fn)
	local savedGuild, dialogs = GetGuildInfo, {}
	for k, v in pairs(StaticPopupDialogs) do dialogs[k] = v end
	local w = { now = 1800000000, guild = "Olympus Ember", rank = 0, prints = {}, calls = {}, corr = {}, watchers = {} }
	local function Call(what) return function(...) w.calls[#w.calls + 1] = table.concat({ what, ... }, ":") end end
	local c = setmetatable({ me = "Master-Realm", realm = "Realm", group = "RealmGroup", faction = "Alliance", db = {}, rdb = {}, RealmPages = {},
		L = setmetatable({}, { __index = ns.L }) }, { __index = ns })
	local ok, err = pcall(function()
		GetGuildInfo = function() return w.guild, "Master", w.rank end
		c.Now = function() return w.now end
		c.FullName = function(name, realm) return name and (name:find("-", 1, true) and name or name .. "-" .. (realm or "Realm")) end
		c.ShortName = function(name) return name and name:match("^[^-]+") end
		c.RealmOf = function(name) return name and name:match("%-([^%-]+)$") end
		c.IsMember = function() return c.IsFederation(w.guild) end
		c.IsKingGuild, c.KingGuildName = function(g) return g == "Olympus" end, function() return "Olympus" end
		c.KingCharacter = function() return "Pinned King-Realm" end
		c.IsKingCharacter = function(name) return c.FullName(name) == c.KingCharacter() end
		c.IsHighCouncillor = function() return false end
		c.King = { IsKing = function() return false end, Preview = function() return false end }
		c.Workshop, c.ViewAs = { Visible = function() return false end }, { Is = function() return false end, Previewing = function() return false end }
		c.Print = function(line) w.prints[#w.prints + 1] = line end
		c.Log, c.Fire, c.On, c.After = function() end, function() end, function() end, function() end
		c.ChatLocked, c.Quiet = function() return false end, function() return false end
		c.Data = { KnownRank = function() return nil end, Guild = function() return nil end }
		c.Comm = { Handle = function() end, Send = function() return true end }
		c.Roster = { guild = w.guild, group = c.group, faction = c.faction, complete = true, generation = 1, snapshotAt = w.now,
			byName = { [c.me] = 0, ["Peer-Realm"] = 3, ["Adept-Realm"] = 3 }, lastStats = { leader = "Master" } }
		c.Roster.RankOf = function(name) return c.Roster.byName[c.FullName(name)] end
		c.Roster.Fresh = function() return c.Roster end
		c.Church = { Role = function() return nil end, State = function() return { corr = w.corr, corrOf = {}, apostle = {} } end }
		c.WatchChat = { GuildList = function() return { names = w.watchers } end, IsNamedWatcher = function() return false end, IsMod = function() return false end }
		c.GuildCharter = { Ours = function() return w.charter end }
		c.Bank = { OwnGuildSnapshot = function() return w.bank end }
		c.Treasury = { OpenOwnGuild = Call("bank"), TreasurerPin = function() return nil end, RealKeeper = function() return false end }
		c.ChurchView = { Show = Call("church-show"), Ask = function(kind, data) w.calls[#w.calls + 1] = "church-ask:" .. kind .. ":" .. tostring(data and data.guild) end }
		c.Watch = { Show = Call("watch-show") }
		c.ShowDialog = Call("dialog")
		c.UI = { SelectTab = Call("tab"), Refresh = function() end }
		c.Views = { ShowPage = Call("page") }
		c.Letters = { ShowText = function(o) w.calls[#w.calls + 1] = "letter:" .. tostring(o and o.title) return true end }
		assert(loadfile(ADDON .. "Nominees.lua"))("Olympus", c)
		c.Nominees.Prompt = function(role, dept) w.calls[#w.calls + 1] = "prompt:" .. role .. (dept and (":" .. dept) or "") end
		assert(loadfile(ADDON .. "RoleBriefings.lua"))("Olympus", c)
		c.RoleBriefings.LIVE = true
		fn(w, c, c.RoleBriefings)
	end)
	GetGuildInfo = savedGuild
	for k in pairs(StaticPopupDialogs) do StaticPopupDialogs[k] = nil end
	for k, v in pairs(dialogs) do StaticPopupDialogs[k] = v end
	if not ok then error(err, 0) end
end

test("role briefings: a guild master's letter ticks each line from what he named (real Nominees), its buttons open each step, and his Guild tab reopens it with the count", function()
	GuildMaster(function(w, c, RB)
		eq(RB.Scan(true), 1)
		eq(RB.Letters()[1].kind, "guildmaster")
		eq(select(1, RB.GMProgress()), 0)
		eq(select(2, RB.GMProgress()), 8, "a Legate, six correspondents and the Church's")
		RB.OpenKind("guildmaster")
		local page = RB.Page()
		assert(Row(page, L.RB_GM_TODO:format(L.RB_GM_LEGATES:format(0, 25))), Text(page))
		assert(Row(page, L.RB_GM_TODO:format(L.RB_GM_WAR)))
		-- He names a Legate and his War correspondent, through the real Nominees.
		eq(c.Nominees.Name("centurion", "Peer"), true)
		eq(c.Nominees.Name("correspondent", "Adept", "Department of War"), true)
		w.corr[c.Fold(w.guild)] = { g = w.guild, n = "Adept" }
		w.watchers[1] = "Peer"
		w.charter = { purpose = "x" }
		page = RB.Page()
		assert(Row(page, L.RB_GM_DONE:format(L.RB_GM_LEGATES:format(1, 25))), Text(page))
		assert(Row(page, L.RB_GM_DONE:format(L.RB_GM_WAR)), "War's line ticked")
		assert(Row(page, L.RB_GM_TODO:format(L.RB_GM_TREASURY)), "the Treasury's still to do")
		assert(Row(page, L.RB_GM_DONE:format(L.RB_GM_CHURCH)), "the Church's, as the Church tab shows him")
		assert(Row(page, L.RB_GM_DONE:format(L.RB_GM_WATCHERS)) and Row(page, L.RB_GM_DONE:format(L.RB_GM_CHARTER)))
		assert(Row(page, L.RB_GM_TODO:format(L.RB_GM_BANK)))
		eq(select(1, RB.GMProgress()), 3)
		-- Each button opens its step.
		local function Click(label)
			local before = #w.calls
			local rows = {}
			for _, line in ipairs(page) do if Plain(line.text) == "> " .. label and line.onClick then rows[#rows + 1] = line end end
			rows[1].onClick()
			local out = {}
			for i = before + 1, #w.calls do out[#out + 1] = w.calls[i] end
			return table.concat(out, ","), rows
		end
		eq(Click(L.RB_GM_BTN_LEGATE), "tab:throne,prompt:centurion")
		local _, names = Click(L.RB_GM_BTN_NAME)
		eq(#names, 6, "a Name one for each department")
		names[2].onClick()
		eq(w.calls[#w.calls], "prompt:correspondent:Department of War")
		eq(Click(L.RB_GM_BTN_CHURCH), "tab:church,church-show:name,church-ask:correspondent:" .. w.guild)
		eq(Click(L.RB_GM_BTN_WATCHER), "watch-show:chat,tab:watch,dialog:OLYMPUS_WATCHCHAT_NAME:" .. L.WATCHCHAT_WATCHERS_ADD)
		eq(Click(L.RB_GM_BTN_WRITE), "tab:realm,page:guildcharter")
		eq(Click(L.RB_GM_BTN_OPEN), "bank")
		-- His Guild tab (King.Build hands it the tab's lines): the letter, with how many are named.
		local tab = { { text = "title" }, { text = "more" } }
		eq(RB.GuildTabLine(tab), true)
		eq(Plain(tab[2].text), "> " .. L.RB_GUILD_TAB_LINK:format(3, 8))
		RB.Reset()
		tab[2].onClick()
		eq(Plain(RB.Page()[2].text), L.RB_GM_TITLE, "it reopens his letter")
		-- Not his rank 0 any more (or not LIVE): no line.
		w.rank = 1
		eq(RB.GuildTabLine({}), false)
		w.rank = 0
		RB.LIVE = false
		eq(RB.GuildTabLine({}), false)
	end)
end)

test("role briefings: a Legate and a correspondent named by the real guild master's list get their letters once, and a heartbeat of the same list makes none", function()
	GuildMaster(function(w, c, RB)
		w.rank = 3
		c.Roster.byName[c.me] = 3
		c.Roster.byName["Boss-Realm"] = 0
		c.me = "Adept-Realm"
		c.Nominees.Handle("CHANNEL", "Boss-Realm", ("NM~1~%s~%d~1~1~%s"):format(w.guild, w.now, "c=Adept"))
		eq(c.Nominees.RoleOf("Adept", w.guild), "centurion")
		eq(RB.Scan(true), 1)
		eq(RB.Letters()[1].kind, "legate")
		c.Nominees.Handle("CHANNEL", "Boss-Realm", ("NM~1~%s~%d~1~1~%s"):format(w.guild, w.now + 1, "c=Adept;c=Peer"))
		eq(RB.Scan(true), 0, "another nominee's revision: no second letter")
		RB.OpenKind("legate")
		assert(Flat(Text(RB.Page())):find("To a Legate of <" .. w.guild .. ">,", 1, true))
		c.Nominees.Handle("CHANNEL", "Boss-Realm", ("NM~1~%s~%d~1~1~%s"):format(w.guild, w.now + 2, "d=Department of Heraldry=Adept"))
		eq(RB.Scan(true), 1, "his new office: its letter")
		eq(RB.Letters()[2].kind, "correspondent"); eq(RB.Letters()[2].dept, "Department of Heraldry")
	end)
end)

---------------------------------------------------------------------------
-- The launch letter: the launch version's letter, once LIVE
---------------------------------------------------------------------------

-- (1.4.0, the author's ask: the release writes its own launch letter, the dev's to the King and the
-- army, which RegisterLaunch keeps; this test is the fallback, a release with no letter of its own.)
test("role briefings: once LIVE, for a release with no letter of its own, the launch letter is the launch version's letter, signed by the King, its button copying the site's link in a pop-up; not before", function()
	H.WithUI(function()
		local copied
		local saved = { read = ns.db.lettersRead }
		local ok, err = pcall(function()
			local own = {} -- (a copy: Letters.lua reads its words with rawget)
			for k, v in pairs(ns.L) do own[k] = v end
			for _, k in ipairs({ "LETTER_1_4_0_TITLE", "LETTER_1_4_0", "LETTER_1_4_0_SIGNED", "LETTER_1_4_0_LINK" }) do own[k] = nil end
			local lns = setmetatable({ L = own, On = function() end, After = function() end,
				Every = function() return { Cancel = function() end } end,
				UI = setmetatable({ ShowCopy = function(title, text) copied = { title = title, text = text } end }, { __index = ns.UI or {} }) }, { __index = ns })
			assert(loadfile(ADDON .. "Letters.lua"))("Olympus", lns)
			local Lt = lns.Letters
			for i = #Lt.LIST, 1, -1 do if Lt.LIST[i] == "1.4.0" then table.remove(Lt.LIST, i) end end
			-- Not LIVE: the version letters are as they were. (Loaded without them, so the file's own LIVE,
			-- on since 1.4.0, registers nothing at load; then off.)
			local RB, rc = Fresh({ Letters = false, L = own })
			rc.Letters, RB.LIVE = Lt, false
			eq(RB.RegisterLaunch(), false)
			eq(Lt.Has(RB.LAUNCH_VERSION), false); eq(Lt.LIST[1] ~= RB.LAUNCH_VERSION, true)
			-- LIVE: it is that version's letter, first in the list.
			RB.LIVE = true
			eq(RB.RegisterLaunch(), true)
			eq(Lt.LIST[1], RB.LAUNCH_VERSION)
			eq(Lt.Has(RB.LAUNCH_VERSION), true)
			eq(RB.RegisterLaunch(), false, "registered once: the letter is that version's now")
			eq(Lt.LIST[2] ~= RB.LAUNCH_VERSION, true)
			ns.db.lettersRead = {}
			eq(Lt.Show(RB.LAUNCH_VERSION), true)
			local f = Lt.Frame()
			eq(f.title:GetText(), L.RB_LAUNCH_TITLE)
			eq(f.sign:GetText(), L.HONOR_LETTER_SIGN, "the King's signature, not the dev's")
			eq(f.link:IsShown(), true)
			f.link:Click()
			eq(copied and copied.text, RB.SITE, "the site's link in the copy pop-up")
			-- Another version's letter: the dev's signature and no link.
			eq(Lt.Show("1.3.3"), true)
			eq(f.sign:GetText(), L.LETTER_SIGNED)
			eq(f.link:IsShown(), false)
			Lt.ShowHistory()
			eq(f.link:IsShown(), false, "never on the list")
			Lt.Hide()
		end)
		ns.db.lettersRead = saved.read
		if not ok then error(err, 0) end
	end)
end)

-- The gamepad gate (the author's rule: nothing new reaches the game's own UI): the letter's new
-- button is a button of Olympus's own letter window, and its copy is Olympus's own pop-up, never one
-- of the game's popups, with the gamepad UI as with mouse and keyboard.
test("role briefings: with the gamepad UI the launch letter's copy button opens Olympus's own copy pop-up, never a popup of the game's", function()
	for _, gamepad in ipairs({ true, false }) do
		H.WithGamepadUI(gamepad, function(game)
			H.WithUI(function()
				local copied
				local saved = ns.db.lettersRead
				local ok, err = pcall(function()
					local own = {}
					for k, v in pairs(ns.L) do own[k] = v end
					local lns = setmetatable({ L = own, On = function() end, After = function() end,
						Every = function() return { Cancel = function() end } end,
						UI = setmetatable({ ShowCopy = function(title, text) copied = text end }, { __index = ns.UI or {} }) }, { __index = ns })
					assert(loadfile(ADDON .. "Letters.lua"))("Olympus", lns)
					local RB = Fresh({ Letters = lns.Letters, L = own })
					RB.LIVE = true
					RB.RegisterLaunch()
					ns.db.lettersRead = {}
					eq(lns.Letters.Show(RB.LAUNCH_VERSION), true)
					lns.Letters.Frame().link:Click()
					eq(copied, RB.SITE)
					eq(#game.shown, 0, "no popup of the game's")
					lns.Letters.Hide()
				end)
				ns.db.lettersRead = saved
				if not ok then error(err, 0) end
			end)
		end)
	end
end)

---------------------------------------------------------------------------
-- pt-BR
---------------------------------------------------------------------------

test("role briefings: every letter's words in pt-BR too, in the same sober voice, with the same placeholders", function()
	local pt, saved = { L = {} }, GetLocale
	GetLocale = function() return "ptBR" end
	local ok, err = pcall(function() assert(loadfile(ADDON .. "Locales/RoleBriefingsText.lua"))("Olympus", pt) end)
	GetLocale = saved
	assert(ok, err)
	local en = { L = {} }
	assert(loadfile(ADDON .. "Locales/RoleBriefingsText.lua"))("Olympus", en)
	local same = { RB_BTN_WATCH = true, RB_GM_WATCHERS = true, RB_WATCHER_TITLE = true, RB_LEGATE_TITLE = true, RB_PREVIEW_DEPT = true,
		RB_GM_DONE = true, RB_GM_TODO = true }
	local n = 0
	for key, text in pairs(en.L) do
		n = n + 1
		local p = pt.L[key]
		assert(type(p) == "string" and p ~= "", "pt-BR: " .. key)
		if not same[key] then assert(p ~= text, "pt-BR is its own: " .. key) end
		local _, a = text:gsub("%%[sd]", "")
		local _, b = p:gsub("%%[sd]", "")
		eq(b, a, "the same placeholders: " .. key)
	end
	assert(n > 100, "the words: " .. n)
	-- (2026-11-05: the same sober missive in pt-BR: a salutation, no exclamation marks, no slang.)
	for _, key in ipairs({ "RB_LAUNCH", "RB_COUNCIL", "RB_APOSTLE_LAUNCH", "RB_LEGATE", "RB_STEWARD", "RB_MISSIONARY" }) do
		assert(pt.L[key]:match("^A[os]* [^\n]*,\n\n"), "pt-BR opens as a missive: " .. key)
	end
	for key, text in pairs(pt.L) do
		eq(text:find("!", 1, true), nil, "pt-BR: no exclamation marks: " .. key)
		for _, words in ipairs({ "Olha", "E aí", "Bora", "Sério" }) do
			eq(text:find(words, 1, true), nil, "pt-BR: never the streamer's voice: " .. key .. ": " .. words)
		end
		-- (whole words, in any case: "compra entra" is no slang. A frontier cannot close after an accented
		-- letter, whose last byte is no %w, so "tá" and "tô" are matched by their own spacing.)
		local t = text:lower()
		for _, word in ipairs({ "pra", "pro" }) do
			eq(t:find("%f[%w]" .. word .. "%f[%W]"), nil, "pt-BR: never the streamer's voice: " .. key .. ": " .. word)
		end
		for _, word in ipairs({ "tá", "tô" }) do
			local hit = t:find(" " .. word .. " ", 1, true) or t:match("^" .. word .. " ") or t:find("\n" .. word .. " ", 1, true)
				or t:find(" " .. word .. "[.,\n]") or t:match("^" .. word .. "[.,]")
			eq(hit, nil, "pt-BR: never the streamer's voice: " .. key .. ": " .. word)
		end
	end
	assert(pt.L.RB_LAUNCH:find("olympus.roachcouncil.com", 1, true))
end)

test("role briefings: the 1.4.0 release writes its own launch letter (the dev's, to the King and the army): RegisterLaunch keeps it, LIVE or not; its own signature and the site's link to copy", function()
	H.WithUI(function()
		local copied
		local saved = { read = ns.db.lettersRead }
		local ok, err = pcall(function()
			local own = {}
			for k, v in pairs(ns.L) do own[k] = v end
			local lns = setmetatable({ L = own, On = function() end, After = function() end,
				Every = function() return { Cancel = function() end } end,
				UI = setmetatable({ ShowCopy = function(title, text) copied = { title = title, text = text } end }, { __index = ns.UI or {} }) }, { __index = ns })
			assert(loadfile(ADDON .. "Letters.lua"))("Olympus", lns)
			local Lt = lns.Letters
			local RB = Fresh({ Letters = Lt, L = own })
			eq(Lt.LIST[1], "1.5.3"); eq(Lt.LIST[11], "1.4.0"); eq(Lt.Has("1.4.0"), true) -- (1.4.1: the launch letter stays listed after the fix)
			RB.LIVE = false
			eq(RB.RegisterLaunch(), false, "not LIVE")
			RB.LIVE = true
			eq(RB.RegisterLaunch(), false, "LIVE: the release's own letter is kept")
			eq(own.LETTER_1_4_0_TITLE, L.LETTER_1_4_0_TITLE); eq(own.LETTER_1_4_0, L.LETTER_1_4_0)
			eq(Lt.LIST[11], "1.4.0"); eq(Lt.LIST[12] ~= "1.4.0", true, "listed once")
			ns.db.lettersRead = {}
			eq(Lt.Show("1.4.0"), true)
			local f = Lt.Frame()
			eq(f.title:GetText(), L.LETTER_1_4_0_TITLE)
			eq(Lt.Holds(), true, "shown, the version letter holds the screen (a duty letter waits)")
			-- (1.4.0, the author's ask: the launch letter's window has its own name, not "Olympus 1.4.0")
			eq(f.titleText, L.LETTER_1_4_0_HEAD, "the launch letter's own name on its window")
			eq(f.sign:GetText(), L.LETTER_1_4_0_SIGNED, "the dev's own signature")
			eq(f.link:IsShown(), true)
			f.link:Click()
			eq(copied and copied.text, RB.SITE, "the site's link in the copy pop-up")
			Lt.Hide()
			eq(Lt.Show("1.3.3"), true)
			eq(Lt.Frame().titleText, L.LETTER_TITLE:format("1.3.3"), "a letter without a name of its own keeps the release's")
			Lt.Hide()
		end)
		ns.db.lettersRead = saved.read
		if not ok then error(err, 0) end
	end)
end)

-- (1.4.0, the author's ask before the launch: "uma carta de cargo deve abrir, mas ela so deve esperar a
-- outra") A new duty letter opens by itself, never over the version letter: it waits while that letter
-- holds the screen, or the game is in combat, then the newest unread one opens, once.
test("role briefings: a new duty letter opens by itself once the version letter no longer holds the screen, never over it nor in combat; the newest unread opens once", function()
	WithRoles({ steward = true }, function(RB, c, w)
		local holds, timers, savedCombat = true, {}, InCombatLockdown
		c.Letters = { Holds = function() return holds end }
		c.After = function(_, _, fn) timers[#timers + 1] = fn end
		local function Run() local list = timers timers = {} for _, fn in ipairs(list) do fn() end end
		local function Opened() for _, o in ipairs(w.opened) do if o == "page:rolebriefings" then return true end end return false end
		local ok, err = pcall(function()
			eq(RB.Arrived(RB.Scan(false)), true, "a new letter: its opening waits")
			eq(RB.Arrived(1), false, "one waiting at a time")
			eq(#timers, 1)
			Run()
			eq(Opened(), false, "the version letter holds the screen: not over it")
			eq(#timers, 1, "it looks again a moment later")
			holds = false
			InCombatLockdown = function() return true end
			Run()
			eq(Opened(), false, "nor in combat")
			InCombatLockdown = function() return false end
			Run()
			eq(Opened(), true, "free: the duty letter opens")
			eq(RB.Letters()[#RB.Letters()].read, true, "and is read")
			eq(#timers, 0, "nothing more waits")
			w.opened[#w.opened + 1] = "-"
			eq(RB.OpenWhenFree(0), false, "a read one never reopens by itself")
			eq(RB.Arrived(0), false, "no new letter: nothing waits")
		end)
		InCombatLockdown = savedCombat
		if not ok then error(err, 0) end
	end)
end)
