local ADDON, ns = ...
local L = ns.L

-- Read-only weekly facts, as this client heard them. No requests, new observations of players,
-- private ledger fields or sharing setters. Two local reset snapshots are enough for comparison.
local Brief = {}
ns.WeeklyBrief = Brief

local function Plain(s, n)
	return ns.Cut(tostring(s or ""):gsub("[|%c]", " "):gsub("%s+", " "), n or 160)
end
local function Number(n)
	return type(n) == "number" and n == n and n >= 0 and n < math.huge and math.floor(n) or nil
end
local function Store()
	if not ns.rdb then return nil end
	if type(ns.rdb.weeklyBrief) ~= "table" then ns.rdb.weeklyBrief = {} end
	local s = ns.rdb.weeklyBrief
	if type(s.weeks) ~= "table" then s.weeks = {} end
	for key, row in pairs(s.weeks) do
		if type(row) ~= "table" or not Number(row.total) or Number(row.total) ~= row.total
			or not Number(row.known) or Number(row.known) ~= row.known or row.known < 1
			or row.total > row.known * ns.Codec.GUILD_CAP or not Number(row.at)
			or type(row.coverage) ~= "string" or row.coverage == "" or #row.coverage > 16000 then s.weeks[key] = nil end
	end
	if type(s.vox) ~= "table" or type(s.vox.q) ~= "string" or type(s.vox.verdict) ~= "string" or not Number(s.vox.at) then s.vox = nil end
	return s
end
local function Week()
	return ns.Dues and ns.Dues.Week and ns.Dues.Week() or nil
end
local function Census()
	local D = ns.Data
	if not D or not D.Summary or (D.Rebuilding and D.Rebuilding() ~= nil) then return nil end
	local summary, names, own, sizes = D.Summary(), {}, GetGuildInfo("player"), {}
	for _, e in ipairs(summary.guilds or {}) do
		local size = e.counted and type(e.g) == "table" and Number(e.g.total)
		if size then names[#names + 1] = e.name; sizes[e.name] = math.min(size, ns.Codec.GUILD_CAP) end
	end
	if #names == 0 or not Number(summary.total) then return nil end
	table.sort(names)
	local rank
	if sizes[own] then
		rank = 1
		for _, size in pairs(sizes) do if size > sizes[own] then rank = rank + 1 end end
	end
	return { total = Number(summary.total), known = #names, coverage = table.concat(names, "|"),
		at = ns.Now(), rank = rank, guild = own }
end

local function PublicResult(s)
	local V = ns.Vox
	if not V or not V.State or (ns.King and ns.King.Preview and ns.King.Preview()) then return end
	local poll, history, shown = V.State()
	local candidates = {}
	for _, h in ipairs(history or {}) do candidates[#candidates + 1] = h end
	if poll and poll.closed and not poll.preview then candidates[#candidates + 1] = poll end
	if shown and shown.counts and not shown.hidden then candidates[#candidates + 1] = shown end
	for _, h in ipairs(candidates) do
		-- Guild/Hand/member-only questions never belong to a public summary.
		if h.to == "E" and not h.hidden and type(h.q) == "string" and type(h.answers) == "table"
			and type(h.counts) == "table" and Number(h.voters) then
			local at = Number(h.resultsAt or h.t or h.at)
			if at and (not s.vox or at > (tonumber(s.vox.at) or 0)) then
				s.vox = { q = Plain(h.q), verdict = Plain(V.Verdict(h.answers, h.counts, h.voters, h.multi)), at = at }
			end
		end
	end
end

function Brief.Capture()
	if not ns.IsMember() then return nil end
	local week, s = Week(), Store()
	if not Number(week) or Number(week) ~= week or not s then return nil end
	for key in pairs(s.weeks) do
		if key ~= week and key ~= week - 1 then s.weeks[key] = nil end
	end
	local c = Census()
	if c then s.weeks[week] = { total = c.total, known = c.known, coverage = c.coverage, at = c.at } end
	PublicResult(s)
	return s.weeks[week], s.weeks[week - 1], c
end

function Brief.Link()
	return { text = "|cffffd200> " .. L.BRIEF_TITLE .. "|r", gapAfter = true,
		onClick = function() ns.Views.ShowPage("weeklybrief") end }
end

function Brief.Lines(q)
	local now, prior, census = Brief.Capture()
	local lines = {
		{ text = L.BRIEF_BACK, onClick = function() ns.Views.ShowBoard(true) end, gapAfter = true },
		{ header = true, text = L.BRIEF_TITLE }, { text = L.BRIEF_NOTE, gapAfter = true },
	}
	local function Row(label, value)
		if not q or ns.Holds(q, label, value) then lines[#lines + 1] = { text = label, right = value } end
	end
	local size = type(now) == "table" and Number(now.total)
	Row(L.BRIEF_ARMY, size and tostring(size) or L.BRIEF_UNKNOWN)
	if size and Number(now.known) and Number(now.at) then
		Row(L.BRIEF_COVERAGE:format(now.known, ns.Ago(now.at)), "")
	end
	local before = type(prior) == "table" and Number(prior.total)
	local comparable = size and before and type(now.coverage) == "string" and now.coverage == prior.coverage
	Row(L.BRIEF_PREVIOUS, comparable and ("%+d"):format(size - before) or L.BRIEF_UNKNOWN)
	Row(L.BRIEF_RANK, census and census.rank and L.BRIEF_RANK_VALUE:format(census.rank, census.known) or L.BRIEF_UNKNOWN)
	lines[#lines + 1] = { header = true, text = L.WEEK_TITLE }
	local entries = ns.Week and ns.Week.Entries and ns.Week.Entries() or {}
	for _, e in ipairs(entries) do
		local text = Plain(e.title) .. "  " .. ns.Week.DayLabel(e.at) .. " " .. ns.Week.TimeLabel(e.at)
		if not q or ns.Holds(q, text) then lines[#lines + 1] = { indent = 1, text = text } end
	end
	if #entries == 0 then lines[#lines + 1] = { text = L.BRIEF_NO_WEEK } end
	local s, F = Store(), ns.Filter
	local v = s and type(s.vox) == "table" and s.vox or nil
	local result = v and Plain(v.q) .. " - " .. Plain(v.verdict) or L.BRIEF_UNKNOWN
	if v and F and F.Hides and (F.Hides(v.q) or F.Hides(v.verdict)) then result = L.FILTER_WORDS_HIDDEN_SHORT end
	Row(L.BRIEF_VOX, result)
	local T = ns.Treasury
	if T and T.PublicShows and T.PublicShows("balance") then
		local copper, books
		if T.PublicSpending then copper, books = T.PublicSpending() end
		Row(L.BRIEF_SPENDING, copper and L.BRIEF_SPENDING_VALUE:format(T.Coins(copper), books) or L.BRIEF_UNKNOWN)
	end
	return lines
end

local function Companion()
	local layers = ns.Layers
	if not layers or not layers.Sharing or not layers.Sharing() then return L.BRIEF_LOCATION_PRIVATE end
	local mine = layers.Mine and layers.Mine()
	local map = layers.CurrentMap and layers.CurrentMap()
	if not mine or mine.mapID ~= map or not layers.ForMap then return L.BRIEF_UNKNOWN end
	local guild = GetGuildInfo("player")
	for _, layer in ipairs(layers.ForMap(map)) do
		local h = layer.head
		if h and h.guild ~= guild and ns.IsFederation(h.guild) then
			return Plain(h.name, 64) .. " <" .. Plain(h.guild, 40) .. ">"
		end
	end
	return L.BRIEF_UNKNOWN -- not an assertion that no sister guild member is there
end

local function PersonalValues()
	local now, nextEntry = ns.Now()
	for _, e in ipairs(ns.Week and ns.Week.Entries and ns.Week.Entries() or {}) do
		if e.at >= now and (not nextEntry or e.at < nextEntry.at) then nextEntry = e end
	end
	local nextText = L.BRIEF_NONE
	if nextEntry then
		local role = ns.Week.MySignup and ns.Week.MySignup(nextEntry.id)
		local signup = role and L.BRIEF_SIGNED:format(Plain(L["SIGN_ROLE_" .. role] or role, 40)) or L.BRIEF_UNSIGNED
		nextText = Plain(nextEntry.title, 60) .. " - " .. ns.Week.DayLabel(nextEntry.at) .. " " .. ns.Week.TimeLabel(nextEntry.at) .. "; " .. signup
	end
	local open = {}
	local C = ns.Court
	if C and ((C.Current and C.Current()) or (C.Holding and C.Holding())) then open[#open + 1] = L.BRIEF_COURT_OPEN end
	if ns.Vox and ns.Vox.State then
		local poll, _, shown = ns.Vox.State()
		if (poll and not poll.closed and not poll.preview and poll.at >= now)
			or (shown and not shown.counts and shown.at >= now) then open[#open + 1] = L.BRIEF_VOX_OPEN end
	end
	local R = ns.Roster and ns.Roster.Fresh and ns.Roster.Fresh()
	local online = R and type(R.online) == "table" and tostring(#R.online) or L.BRIEF_UNKNOWN
	return { nextText, #open > 0 and table.concat(open, ", ") or L.BRIEF_NONE, online, Companion(), L.BRIEF_PAYMENT_UNKNOWN }
end

function Brief.PersonalLines()
	local values = PersonalValues()
	return { L.BRIEF_NEXT:format(values[1]), L.BRIEF_OPEN:format(values[2]), L.BRIEF_ONLINE:format(values[3]),
		L.BRIEF_COMPANION:format(values[4]), L.BRIEF_PAYMENT }
end

local INK, TITLE = "QuestFont", "QuestTitleFont"
Brief.PAPER_WRAP = 44
local function PaperLine(text, font, extra)
	local line = { text = text, font = font or INK }
	for key, value in pairs(extra or {}) do line[key] = value end
	return line
end
local function Paragraph(lines, text, font, extra)
	local row = ""
	for word in tostring(text or ""):gmatch("%S+") do
		if row ~= "" and #row + 1 + #word > Brief.PAPER_WRAP then
			lines[#lines + 1] = PaperLine(row, font)
			row = word
		else row = row == "" and word or row .. " " .. word end
	end
	if row ~= "" then lines[#lines + 1] = PaperLine(row, font, extra) end
end
function Brief.PersonalLink()
	if not ns.IsMember() then return nil end
	return { text = "|cffffd200> " .. L.BRIEF_PERSONAL_TITLE .. "|r", gapAfter = true,
		onClick = function() ns.Views.ShowPage("personalbrief") end }
end

-- A member's reopenable Realm page in the main window, not a royal tool or a popup.
-- The same five held facts use the existing parchment fonts, without depending on the King.
function Brief.PersonalPage(q)
	if not ns.IsMember() then return {} end
	local lines = { PaperLine(L.BRIEF_PERSONAL_BACK, INK, { gapAfter = true,
		onClick = function() ns.Views.ShowPage(nil) end }),
		PaperLine(L.BRIEF_PERSONAL_TITLE, TITLE, { gapAfter = true }) }
	Paragraph(lines, L.BRIEF_PERSONAL_NOTE, INK, { gapAfter = true })
	local titles = { L.BRIEF_NEXT_TITLE, L.BRIEF_OPEN_TITLE, L.BRIEF_ONLINE_TITLE, L.BRIEF_COMPANION_TITLE, L.BRIEF_PAYMENT_TITLE }
	for index, value in ipairs(PersonalValues()) do
		if not q or ns.Holds(q, titles[index], value) then
			Paragraph(lines, tostring(index) .. ". " .. titles[index], TITLE)
			Paragraph(lines, value, INK, { gapAfter = true })
		end
	end
	return lines
end

-- No new outer tab or automatic navigation: the existing Board offers this Realm page.
ns.RealmPages = ns.RealmPages or {}
table.insert(ns.RealmPages, { key = "weeklybrief", Lines = Brief.Lines, tip = "BRIEF_NOTE" })
table.insert(ns.RealmPages, { key = "personalbrief", Link = Brief.PersonalLink, Lines = Brief.PersonalPage,
	tip = "BRIEF_PERSONAL_NOTE", parchment = true })
ns.On("LOGIN", function()
	ns.After(210, "weekly brief snapshot", Brief.Capture) -- after the ordinary census rebuild
	ns.Every(60, "weekly brief snapshot", Brief.Capture)
end)
