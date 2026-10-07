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
		if type(row) ~= "table" or not Number(row.total) or not Number(row.known) or row.known < 1
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
	if type(week) ~= "number" or not s then return nil end
	for key in pairs(s.weeks) do
		if type(key) ~= "number" or key < week - 1 or key > week then s.weeks[key] = nil end
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
	local result = v and Plain(v.q) .. " — " .. Plain(v.verdict) or L.BRIEF_UNKNOWN
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

-- No new outer tab or automatic navigation: the existing Board offers this Realm page.
ns.RealmPages = ns.RealmPages or {}
table.insert(ns.RealmPages, { key = "weeklybrief", Lines = Brief.Lines, tip = "BRIEF_NOTE" })
ns.On("LOGIN", function()
	ns.After(210, "weekly brief snapshot", Brief.Capture) -- after the ordinary census rebuild
	ns.Every(60, "weekly brief snapshot", Brief.Capture)
end)
