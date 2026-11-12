-- The Realm tab's pages (ns.RealmPages) in the Olympus window: the page modules, Views.lua and
-- UI.lua (H.LoadUI) in a client of their own over the harness's namespace, drawn on the
-- harness's stand-in frames (H.WithUI) and clicked row by row as the player clicks them.
local ns, test, eq, H = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]realm%-pages%.lua$")) or "./"

-- The supported clients' quest fonts (tests/fixtures/forever-api.lua lists both): the dark ink
-- the parchment pages ask for (line.font). The harness's toolkit has only the game's list fonts.
local INK = { QuestFont = true, QuestTitleFont = true }

-- The client: every module with a Realm page, in Olympus.toc's order, its own registry, locale
-- words and saved data; the harness's census, roster and the rest under it. Nothing it loads
-- registers with the harness (its events, comm handlers and dialogs are its own or put back).
-- The author's Workshop is open (the King's letters' previews are his alone: HonorsNet.PreviewKeys).
-- (ProfileEdit's "myprofile" entry is a link alone, no page: it opens the person page, whose Back
-- is UI.BackFromPlayerProfile; tests/arena/profile-edit.lua has it.)
local function Client()
	local w = { clock = 1800000000, sent = 0, timers = {} }
	local c = setmetatable({ RealmPages = {}, L = setmetatable({}, { __index = ns.L }) }, { __index = ns })
	w.c = c
	c.Now = function() return w.clock end
	c.On, c.RegisterEvent = function() end, function() end
	c.After = function(seconds, key, fn) w.timers[key] = { seconds = seconds, fn = fn } end
	c.Every = c.After
	c.Comm = setmetatable({ Handle = function() end, HandleOutside = function() end,
		Send = function() w.sent = w.sent + 1; return true end, Whisper = function() w.sent = w.sent + 1; return true end }, { __index = ns.Comm })
	c.Arena = { Handle = function() end, Action = function() end } -- (HonorsNet's handlers: no arena here)
	c.Workshop = setmetatable({ Visible = function() return true end }, { __index = ns.Workshop })
	local dialogs = {}
	for k, v in pairs(StaticPopupDialogs) do dialogs[k] = v end
	for _, file in ipairs({ "Locales/WeeklyBriefText", "Locales/GuildCharterText", "Locales/OfficerMusterText", "Locales/ArenaFightsText",
		"RankingRules", "Loot", "War", "GuildCharter", "Views", "WeeklyBrief", "Carry", "OfficerMuster", "Honors", "HonorsNet",
		"Locales/RoleBriefingsText", "RoleBriefings" }) do
		assert(loadfile(ROOT .. "Olympus/" .. file .. ".lua"))("Olympus", c)
	end
	for k in pairs(StaticPopupDialogs) do if not dialogs[k] then StaticPopupDialogs[k] = nil end end
	for k, v in pairs(dialogs) do StaticPopupDialogs[k] = v end
	return w, c
end

-- The Olympus window over that client (UI.lua's own namespace, its Views the client's), opened on
-- the Realm tab as an ordinary member of an Olympus guild; fn(ui, frame, w, c). The quest fonts
-- and the saved data the pages write are put back after.
local function WithRealm(fn)
	H.WithUI(function()
		local db, rdb = {}, {}
		for k in pairs(ns.db) do db[k] = true end
		for k in pairs(ns.rdb) do rdb[k] = true end
		QuestFont, QuestTitleFont = { font = "QuestFont" }, { font = "QuestTitleFont" }
		local ok, err = pcall(function()
			GetGuildInfo = function() return "Olympus II", "Member", 3 end
			local w, c = Client()
			local ui, uns = H.LoadUI()
			uns.Views, c.UI = c.Views, ui
			ui.SelectTab("realm")
			local frame = OlympusFrame or OlympusFrameHD or OlympusFrameBasic or OlympusFrameHDBasic
			assert(frame and frame:IsShown(), "the Olympus window")
			fn(ui, frame, w, c)
		end)
		QuestFont, QuestTitleFont = nil, nil
		for k in pairs(ns.db) do if not db[k] then ns.db[k] = nil end end
		for k in pairs(ns.rdb) do if not rdb[k] then ns.rdb[k] = nil end end
		if not ok then error(err, 0) end
	end)
end

-- The rows the window drew in the Realm's list now (Views.Render: content.lineCount of them).
local function Rows(frame)
	local content, out = frame.views.realm, {}
	for i = 1, content.lineCount or 0 do
		local r = content.rows[i]
		if r and r:IsShown() and r.line then out[#out + 1] = r end
	end
	return out
end
local function Plain(s) return (tostring(s or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- The drawn row whose words hold `text`.
local function RowWith(frame, text)
	for _, r in ipairs(Rows(frame)) do
		if Plain(r.line.text):find(text, 1, true) then return r end
	end
	return nil
end

-- 2026-10-19, the author on the King's letters page in the Realm: "O King's Letters tá com as
-- letras brancas em cima do parchment, não dá para ler direito. É melhor preta ou cinza escuro."
-- Fails before: the page sat on the window's parchment (parchment = true) with its title in the
-- list's gold header font and every other row in its white (GameFontHighlightSmall), the note one
-- row far wider than the page.
test("King's letters page on the Realm's parchment: every row of the honour letters' previews in the dark quest ink, the title in QuestTitleFont, the note wrapped to the page; the Realm's other rows keep the list's fonts", function()
	WithRealm(function(ui, frame, w, c)
		local L, HN = c.L, c.HonorsNet
		local link = assert(RowWith(frame, "> " .. L.HONOR_LETTER_PREVIEW_HEAD), "the Realm's link to the page")
		eq(INK[link.left.font], nil, "the link itself is a row of the Realm's list, off the parchment")
		link:Click()
		eq(ui.PageId(), "realm/honorletters")
		eq(frame.parchment:IsShown(), true, "the page lies on the window's parchment")
		local rows, letters, note = Rows(frame), 0, {}
		assert(#rows > 3, "the page drawn")
		for _, r in ipairs(rows) do
			local text = r.line.text or ""
			assert(INK[r.left.font], ("dark ink, not %s: %s"):format(tostring(r.left.font), text))
			assert(INK[r.right.font], "its right column too: " .. text)
			eq(text:find("|c", 1, true), nil, "no colour of its own over the ink: " .. text)
			if text:sub(1, 2) == "> " then letters = letters + 1
			elseif text ~= L.HONOR_LETTER_PREVIEW_HEAD and not r.line.onClick then
				assert(#text <= HN.PAGE_WRAP, "a row of the note fits the page: " .. text)
				note[#note + 1] = text
			end
		end
		local title = assert(RowWith(frame, L.HONOR_LETTER_PREVIEW_HEAD))
		eq(title.left.font, "QuestTitleFont", "the page's title")
		eq(table.concat(note, " "), (L.HONOR_LETTER_PREVIEW_NOTE:gsub("%s+", " ")), "the whole note, wrapped")
		eq(letters, #HN.PreviewKeys(), "every family's letter listed")
		-- The Realm again: no parchment, and its rows in the list's own fonts.
		c.Views.ShowPage(nil)
		eq(ui.PageId(), "realm/guilds"); eq(frame.parchment:IsShown(), false)
		link = assert(RowWith(frame, "> " .. L.HONOR_LETTER_PREVIEW_HEAD))
		eq(INK[link.left.font], nil, "the Realm's list is unchanged")
	end)
end)

-- 2026-10-19, the author on the same page: "E essa página está sem botão de voltar. Eu clico
-- nela, eu tenho que clicar em classes, depois de novo para poder voltar." While a page shows, the
-- Realm's Guilds button is the one selected and does nothing: a page without a Back of its own has
-- no way out but another view and Guilds again. Every page the Realm's modules register is opened
-- as the player opens it (its own row in the Realm; the level race's rules link for the rules page;
-- the Board's link for the weekly summary) and its first drawn row must be its Back, which leads
-- where it was opened from: the Realm's guilds (the weekly summary: the Board). Fails before on
-- the King's letters (honorletters) and Carried history (carry) pages, which had none.
test("Realm pages: every page of the Realm tab has a Back as its first row and it returns to the Realm overview, the King's letters' and Carried history's too", function()
	WithRealm(function(ui, frame, w, c)
		local brief = ns.WeeklyBrief -- (the harness's Board links the brief of the namespace it was loaded in)
		local ok, err = pcall(function()
			ns.WeeklyBrief = c.WeeklyBrief
			local L = c.L
			local FROM = { weeklybrief = "board" }
			-- The row a page is opened from, in what the window shows now.
			local function Opener(page)
				if page.key == "ranking-rules" then
					for _, r in ipairs(Rows(frame)) do if r.line.id == "ranking-rules:realm-level" then return r end end
					return nil
				end
				if page.key == "weeklybrief" then return RowWith(frame, Plain(c.WeeklyBrief.Link().text)) end
				local link = page.Link and page.Link()
				return link and RowWith(frame, Plain(link.text))
			end
			local seen = {}
			for _, page in ipairs(c.RealmPages) do
				local key, from = page.key, "realm/" .. (FROM[page.key] or "guilds")
				seen[key] = true
				c.Views.ShowBoard(FROM[key] == "board")
				c.Views.ShowPage(nil)
				eq(ui.PageId(), from, key .. ": where it is opened from")
				local opener = assert(Opener(page), key .. ": its link on " .. from)
				opener:Click()
				eq(ui.PageId(), "realm/" .. key, key .. ": opened")
				local back = Rows(frame)[1]
				assert(back and back.line.onClick, key .. ": a first row to click")
				assert(Plain(back.line.text):match("^< "), key .. ": its first row is Back, not " .. tostring(back.line.text))
				if page.parchment then assert(INK[back.left.font], key .. ": its Back in the parchment's ink") end
				back:Click()
				eq(ui.PageId(), from, key .. ": Back leads where it was opened from")
				eq(frame.parchment ~= nil and frame.parchment:IsShown(), false, key .. ": the parchment goes with its page")
			end
			-- The pages of the modules loaded (a page added to them later is checked the same way).
			-- (1.4.0: the duty letters' page, its link the author's preview while the letters are not out.)
			for _, key in ipairs({ "ranking-rules", "loot", "war", "guildcharter", "weeklybrief", "personalbrief", "carry", "honorletters", "rolebriefings" }) do
				assert(seen[key], key .. " registered and checked")
			end
			-- The two that had none, word for word, in English and pt-BR.
			eq(L.HONOR_LETTER_PREVIEW_BACK, "< Back to the Realm"); eq(L.CARRY_BACK, "< Back to the Realm")
			for _, pair in ipairs({ { "Locales/ArenaFightsText", "HONOR_LETTER_PREVIEW_BACK" }, { "Locales/CarryText", "CARRY_BACK" } }) do
				local pt, saved = {}, GetLocale
				GetLocale = function() return "ptBR" end
				local loaded, why = pcall(function() assert(loadfile(ROOT .. "Olympus/" .. pair[1] .. ".lua"))("Olympus", { L = pt }) end)
				GetLocale = saved
				assert(loaded, why)
				eq(pt[pair[2]], "< Voltar ao Reino", pair[2] .. " in pt-BR")
			end
		end)
		ns.WeeklyBrief = brief
		if not ok then error(err, 0) end
	end)
end)
