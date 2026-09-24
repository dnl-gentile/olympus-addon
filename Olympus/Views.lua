local ADDON, ns = ...
local L = ns.L

-- Content of the four tabs. Each tab gives: column headers (optional), a list of lines,
-- a detail box (title + text, like the guild "Message of the Day" box) and three buttons.
-- The renderer draws lines with Blizzard fonts; a line is either
--   { text, right, indent, header, color, onClick, tooltip = function(tt) end }
-- or a table row { cols = { ... } } drawn with the tab's column layout. `key` (a player's
-- name) marks a line that opens a person: the HD window keeps it lit while it is open.

local Views = {}
ns.Views = Views

local ROW_H = 16
local ROW_H_HD = 20 -- the Guild & Communities roster's rows (CommunitiesMemberList.xml)
local expanded = {}
local CROWN = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:13:13|t "
local ASSIST = "|TInterface\\GroupFrame\\UI-Group-AssistantIcon:12:12|t "

local function Green(s) return "|cff40ff40" .. s .. "|r" end
local function Grey(s) return "|cff9d9d9d" .. s .. "|r" end
local function Red(s) return "|cffff4040" .. s .. "|r" end
local function Gold(s) return "|cffffd200" .. s .. "|r" end
Views.Green, Views.Grey, Views.Red, Views.Gold = Green, Grey, Red, Gold

local function ClassColored(name, classFile)
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	return c and ("|c%s%s|r"):format(c.colorStr, name) or name
end

local function Presence(online, days)
	if online then return Green(L.ONLINE_NOW) end
	if not days or days < 1 then return Grey(L.OFFLINE_TODAY) end
	local d = math.floor(days)
	local text = L.OFFLINE_DAYS:format(d)
	if d >= (ns.db.warnDays or 3) then return Red(text .. " !") end
	return Grey(text)
end

---------------------------------------------------------------------------
-- Column layouts, as fractions of the list width (so they follow the window size)
---------------------------------------------------------------------------

Views.COLUMNS = {
	census = {
		{ key = "COL_GUILD", sort = "name", x = 0.00, w = 0.40 },
		{ key = "COL_MEMBERS", sort = "members", x = 0.40, w = 0.20, justify = "RIGHT" },
		{ key = "COL_ONLINE", sort = "online", x = 0.60, w = 0.16, justify = "RIGHT" },
		{ key = "COL_LORD", sort = "lord", x = 0.76, w = 0.24 },
	},
	heraldry = {
		{ key = "COL_NAME", x = 0.00, w = 0.30 },
		{ key = "COL_GUILD", x = 0.30, w = 0.32 },
		{ key = "COL_TABARD", x = 0.63, w = 0.24 },
		{ key = "COL_WHEN", x = 0.87, w = 0.13, justify = "RIGHT" },
	},
}

---------------------------------------------------------------------------
-- Renderer
---------------------------------------------------------------------------

-- Rows follow the look of the window they are in (content.style, see UI.lua): the old one's,
-- or the HD one's like the Guild & Communities roster (20 tall, its row background on the
-- rows that can be clicked, its gold bar under the mouse and under the person open).
local function Row(content, i)
	content.rows = content.rows or {}
	local r = content.rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, content)
	if content.style == "hd" then
		r:SetHeight(ROW_H_HD)
		r.stripe = r:CreateTexture(nil, "BACKGROUND")
		r.stripe:SetAllPoints()
		r.stripe:SetTexture("Interface\\GuildFrame\\GuildFrame")
		r.stripe:SetTexCoord(0.36230469, 0.38183594, 0.95898438, 0.99804688)
		r:SetHighlightTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar", "ADD")
	else
		r:SetHeight(ROW_H)
		local hl = r:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		hl:SetBlendMode("ADD")
		hl:SetAlpha(0.35)
	end
	r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.left:SetJustifyH("LEFT")
	r.left:SetWordWrap(false)
	r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.right:SetPoint("RIGHT", -2, 0)
	r.right:SetJustifyH("RIGHT")
	r.right:SetWordWrap(false)
	r.cols = {}
	for c = 1, 4 do
		local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetWordWrap(false)
		r.cols[c] = fs
	end
	r:SetScript("OnClick", function(self)
		if not self.line then return end
		-- HD: the person opened stays lit, like the roster's selected member.
		if content.style == "hd" and self.line.key then ns.SafeCall("view select", Views.Select, content, self.line.key) end
		if self.line.onClick then ns.SafeCall("view click", self.line.onClick) end
		if ns.UI.Clicked then ns.UI.Clicked() end
	end)
	r:SetScript("OnEnter", function(self)
		if not (self.line and self.line.tooltip) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		ns.SafeCall("view tooltip", self.line.tooltip, GameTooltip)
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	content.rows[i] = r
	return r
end

function Views.LayoutColumns(fontStrings, layout, width, offset)
	for c, fs in ipairs(fontStrings) do
		local col = layout and layout[c]
		if col then
			fs:ClearAllPoints()
			fs:SetPoint("LEFT", (offset or 0) + col.x * width, 0)
			fs:SetWidth(col.w * width - 4)
			fs:SetJustifyH(col.justify or "LEFT")
			fs:Show()
		else
			fs:Hide()
		end
	end
end

-- The row whose line has `key` stays lit (nil: none). HD rows only.
function Views.Select(content, key)
	content.selectedKey = key
	for _, r in ipairs(content.rows or {}) do
		if key and r.line and r.line.key == key then r:LockHighlight() else r:UnlockHighlight() end
	end
end

function Views.ClearSelection(content) Views.Select(content, nil) end

function Views.Render(content, lines, layout)
	local width = content:GetWidth()
	local hd = content.style == "hd"
	local rowH = hd and ROW_H_HD or ROW_H
	local y = -2
	for i, line in ipairs(lines) do
		local r = Row(content, i)
		r.line = line
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
		r:SetWidth(width)
		if line.cols then
			r.left:Hide()
			r.right:Hide()
			Views.LayoutColumns(r.cols, layout, width - 4, 4)
			for c = 1, 4 do r.cols[c]:SetText(line.cols[c] or "") end
			local a = line.dim and 0.45 or 1
			for c = 1, 4 do r.cols[c]:SetAlpha(a) end
		else
			for c = 1, 4 do r.cols[c]:Hide() end
			r.left:Show()
			r.right:Show()
			-- line.font: a font object by name (the Throne's dark ink on parchment), if the client has it.
			local font = line.font and _G[line.font] and line.font or nil
			r.left:SetFontObject(font or (line.header and "GameFontNormal" or (line.color or "GameFontHighlightSmall")))
			r.right:SetFontObject(font or "GameFontHighlightSmall")
			r.left:ClearAllPoints()
			r.left:SetPoint("LEFT", 4 + (line.indent or 0) * 12, 0)
			r.left:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
			r.left:SetText(line.text or "")
			r.right:SetText(line.right or "")
		end
		r:EnableMouse(line.onClick ~= nil or line.tooltip ~= nil)
		if hd then
			r.stripe:SetShown(line.cols ~= nil or line.onClick ~= nil)
			if line.key and line.key == content.selectedKey then r:LockHighlight() else r:UnlockHighlight() end
		end
		r:Show()
		y = y - (line.header and rowH + 4 or rowH)
		if line.gapAfter then y = y - 6 end
	end
	for i = #lines + 1, #(content.rows or {}) do content.rows[i]:Hide() end
	content:SetHeight(-y + 8)
end

---------------------------------------------------------------------------
-- Shared tooltips
---------------------------------------------------------------------------

local function GuildTooltip(e)
	return function(tt)
		local g = e.g
		tt:AddLine("<" .. e.name .. ">", 0.25, 1, 0.25)
		tt:AddDoubleLine(L.COL_MEMBERS, ns.FormatNumber(g.total), 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L.COL_ONLINE, ns.FormatNumber(g.online), 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L.LORD, g.leader or "?", 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L.VACANCIES, ns.FormatNumber(math.max(0, 1000 - (g.total or 0))), 1, 0.82, 0, 1, 1, 1)
		if g.avgLevel and g.avgLevel > 0 then tt:AddDoubleLine(L.AVG_LEVEL, ("%.1f"):format(g.avgLevel), 1, 0.82, 0, 1, 1, 1) end
		tt:AddDoubleLine(L.INACTIVE_30, ns.FormatNumber(g.inactive30 or 0), 1, 0.82, 0, 1, 1, 1)
		local classes = {}
		for code, n in pairs(g.classes or {}) do classes[#classes + 1] = { code, n } end
		table.sort(classes, function(a, b) return a[2] > b[2] end)
		if #classes > 0 then
			local parts = {}
			for _, c in ipairs(classes) do
				local file = ns.CLASS_FILES[c[1]]
				local label = (file and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file]) or c[1]
				parts[#parts + 1] = ClassColored(label .. " " .. c[2], file)
			end
			tt:AddLine(" ")
			for i = 1, #parts, 3 do tt:AddLine(table.concat({ parts[i], parts[i + 1], parts[i + 2] }, "   ")) end
		end
		local zones = {}
		for key, n in pairs(g.zones or {}) do zones[#zones + 1] = { key, n } end
		table.sort(zones, function(a, b) return a[2] > b[2] end)
		if #zones > 0 then
			tt:AddLine(" ")
			for i = 1, math.min(5, #zones) do
				tt:AddDoubleLine(ns.Zones.NameForKey(zones[i][1]), ns.FormatNumber(zones[i][2]), 0.8, 0.8, 0.8, 1, 1, 1)
			end
		end
		tt:AddLine(" ")
		tt:AddLine(L.REPORTED_BY:format(g.reporter or "?", ns.Ago(g.t)), 0.6, 0.6, 0.6)
		if not e.fresh then tt:AddLine(L.STALE, 1, 0.4, 0.4) end
	end
end

-- A guild only /who has seen: all we know is how many of it were online.
local function SeenTooltip(e)
	return function(tt)
		tt:AddLine("<" .. e.name .. ">", 0.6, 0.6, 0.6)
		tt:AddDoubleLine(L.SEEN_ONLINE, ns.FormatNumber(e.online) .. (e.capped and "+" or ""), 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L.SEEN_WHEN, ns.Ago(e.t), 1, 0.82, 0, 1, 1, 1)
		tt:AddLine(" ")
		tt:AddLine(L.SEEN_TIP, 0.8, 0.8, 0.8, true)
		if e.capped then tt:AddLine(L.SEEN_CAPPED_TIP, 0.8, 0.8, 0.8, true) end
	end
end

-- How far the round of /who searches got (Who.lua), as grey lines under a list.
local function WhoStatus(lines)
	for _, text in ipairs(ns.Who.StatusLines() or {}) do lines[#lines + 1] = { text = Grey(text) } end
end

---------------------------------------------------------------------------
-- Census
---------------------------------------------------------------------------

Views.sort = { key = "members", desc = true }

local SORTERS = {
	name = function(e) return e.name:lower() end,
	members = function(e) return e.g.total or 0 end,
	online = function(e) return e.g.online or 0 end,
	lord = function(e) return (e.g.leader or ""):lower() end,
}

function Views.SortBy(key)
	if Views.sort.key == key then
		Views.sort.desc = not Views.sort.desc
	else
		Views.sort = { key = key, desc = key == "members" or key == "online" }
	end
end

local function CensusLines(s)
	local lines = {}
	-- The King's Agenda, for the whole army (King.lua).
	local a = ns.King and ns.King.Agenda and ns.King.Agenda()
	if a then
		lines[#lines + 1] = { text = Gold(L.THRONE_AGENDA_LINE:format(a.title, math.max(0, math.ceil((a.at - ns.Now()) / 60)), a.zone)), gapAfter = true }
	end
	local get = SORTERS[Views.sort.key] or SORTERS.members
	local guilds = {}
	for i, e in ipairs(s.guilds) do guilds[i] = e end
	table.sort(guilds, function(a, b)
		if a.fresh ~= b.fresh then return a.fresh end
		local va, vb = get(a), get(b)
		if va == vb then return a.name < b.name end
		if Views.sort.desc then return va > vb end
		return va < vb
	end)
	for _, e in ipairs(guilds) do
		local g = e.g
		local leader = g.leader and ((g.leaderOnline and "|cff40ff40" or "|cff9d9d9d") .. g.leader .. "|r") or Grey("?")
		lines[#lines + 1] = {
			cols = { e.name, ns.FormatNumber(g.total), Green(ns.FormatNumber(g.online)), leader },
			dim = not e.fresh,
			tooltip = GuildTooltip(e),
			onClick = function()
				expanded[e.name] = true
				ns.UI.SelectTab("realm")
			end,
		}
	end
	if #lines == 0 then lines[1] = { text = Grey(L.EMPTY) } end
	-- Guilds seen with /who that nobody reports: grey, after every reported guild, and in no
	-- total (Data.Summary keeps them apart). Members and Lord are unknown.
	for _, e in ipairs(s.seen or {}) do
		local online = ns.FormatNumber(e.online) .. (e.capped and "+" or "")
		lines[#lines + 1] = { cols = { Grey(e.name), Grey("?"), Grey(online), Grey(L.NO_ADDON) }, tooltip = SeenTooltip(e) }
	end
	if #(s.seen or {}) > 0 then
		lines[#lines].gapAfter = true
		lines[#lines + 1] = { text = Grey(L.SEEN_HINT) }
	end
	WhoStatus(lines)
	return lines
end

local function CensusDetail(s)
	local where = {}
	for i = 1, math.min(6, #s.zoneList) do
		local z = s.zoneList[i]
		where[#where + 1] = ns.Zones.NameForKey(z.key) .. " " .. Gold(ns.FormatNumber(z.count))
	end
	local text = #where > 0 and table.concat(where, "  ·  ") or L.NO_ZONES
	local conts = {}
	if ns.Map.ContinentTotals then
		local totals = ns.Map.ContinentTotals(s)
		for id, n in pairs(totals) do conts[#conts + 1] = { name = ns.Zones.NameForKey("m" .. id), n = n } end
		table.sort(conts, function(a, b) return a.n > b.n end)
	end
	local title = L.WHERE
	if #conts > 0 then
		local parts = {}
		for _, c in ipairs(conts) do parts[#parts + 1] = c.name .. " " .. ns.FormatNumber(c.n) end
		title = L.WHERE .. ":  |cffffffff" .. table.concat(parts, "  ·  ") .. "|r"
	end
	return title, text .. "\n" .. Grey(ns.UI.StatusLine())
end

---------------------------------------------------------------------------
-- The Realm
---------------------------------------------------------------------------

local function King(guilds)
	for _, e in ipairs(guilds) do
		if e.name:lower() == "olympus" and e.g.leader then return e end
	end
	return guilds[1]
end

local function RealmLines(s)
	local lines = {}
	local king = King(s.guilds)
	if king then
		lines[#lines + 1] = {
			header = true,
			text = CROWN .. L.KING .. ": " .. Gold(king.g.leader or "?"),
			right = Presence(king.g.leaderOnline, king.g.leaderDays),
			tooltip = GuildTooltip(king),
		}
	end
	if #s.guilds == 0 then lines[#lines + 1] = { text = Grey(L.EMPTY) } end
	for _, e in ipairs(s.guilds) do
		local g = e.g
		local open = expanded[e.name]
		lines[#lines + 1] = {
			text = (open and "[-] " or "[+] ") .. Green("<" .. e.name .. ">") .. " " .. (g.leader or "?"),
			right = Presence(g.leaderOnline, g.leaderDays),
			onClick = function()
				expanded[e.name] = not expanded[e.name] or nil
				ns.UI.Refresh()
			end,
			tooltip = GuildTooltip(e),
			color = e.fresh and "GameFontHighlightSmall" or "GameFontDisableSmall",
		}
		if open then
			if g.leader then
				local lord = { name = g.leader, class = g.leaderClass, level = g.leaderLevel, zone = g.leaderZone,
					guild = e.name, rank = L.LORD, online = g.leaderOnline, days = g.leaderDays }
				lines[#lines + 1] = {
					key = g.leader,
					indent = 1, text = CROWN .. Gold(L.LORD) .. "  " .. ClassColored(g.leader, lord.class and ns.CLASS_FILES[lord.class]),
					right = Presence(g.leaderOnline, g.leaderDays),
					onClick = function() ns.UI.ShowPerson(lord) end,
				}
			end
			local officers = g.officers or {}
			lines[#lines + 1] = { indent = 1, text = Gold(L.CAPTAINS:format(#officers)) }
			for _, o in ipairs(officers) do
				local person = { name = o.name, class = o.class, level = o.level, zone = o.zone, guild = e.name,
					rank = L.CAPTAIN, online = o.online, days = o.days }
				lines[#lines + 1] = {
					key = o.name,
					indent = 2, text = ASSIST .. ClassColored(o.name, o.class and ns.CLASS_FILES[o.class]),
					right = (o.level and Grey(L.LEVEL_N:format(o.level)) .. "  " or "") .. Presence(o.online, o.days),
					onClick = function() ns.UI.ShowPerson(person) end,
				}
			end
			if #officers == 0 then lines[#lines + 1] = { indent = 2, text = Grey(L.NONE_REPORTED) } end
			lines[#lines + 1] = { indent = 1, text = Gold(L.RANKS) }
			for i, rank in ipairs(g.ranks or {}) do
				lines[#lines + 1] = { indent = 2, text = ("%d. %s"):format(i, rank.name), right = ns.FormatNumber(rank.count) }
			end
			if #(g.ranks or {}) == 0 then lines[#lines + 1] = { indent = 2, text = Grey(L.NONE_REPORTED) } end
			lines[#lines + 1] = { indent = 1, text = Grey(L.INACTIVE_LINE:format(g.inactive7 or 0, g.inactive30 or 0)), gapAfter = true }
		end
	end

	local racers = {}
	for _, e in ipairs(s.guilds) do
		if e.fresh then
			for _, p in ipairs(e.g.top or {}) do racers[#racers + 1] = { name = p.name, level = p.level, class = p.class, guild = e.name } end
		end
	end
	table.sort(racers, function(a, b)
		if a.level ~= b.level then return a.level > b.level end
		return a.name < b.name
	end)
	lines[#lines + 1] = { header = true, text = L.LEVEL_RACE }
	if #racers == 0 then lines[#lines + 1] = { text = Grey(L.NONE_REPORTED) } end
	for i = 1, math.min(10, #racers) do
		local p = racers[i]
		lines[#lines + 1] = {
			key = p.name,
			text = ("%d. %s  %s"):format(i, ClassColored(p.name, p.class and ns.CLASS_FILES[p.class]), Grey("<" .. p.guild .. ">")),
			right = Gold(L.LEVEL_N:format(p.level)),
			onClick = function() ns.UI.ShowPerson({ name = p.name, class = p.class, level = p.level, guild = p.guild }) end,
		}
	end

	local open = {}
	for _, e in ipairs(s.guilds) do
		local free = 1000 - (e.g.total or 0)
		if e.fresh and free > 0 then open[#open + 1] = { name = e.name, free = free } end
	end
	table.sort(open, function(a, b) return a.free > b.free end)
	lines[#lines + 1] = { header = true, text = L.RECRUITING }
	if #open == 0 then lines[#lines + 1] = { text = Grey(L.ALL_FULL) } end
	for i = 1, math.min(5, #open) do
		lines[#lines + 1] = { text = Green("<" .. open[i].name .. ">"), right = L.FREE_SLOTS:format(ns.FormatNumber(open[i].free)) }
	end

	local mapID = ns.Layers.CurrentMap()
	local zone = mapID and ns.Zones.NameForKey("m" .. mapID) or "?"
	lines[#lines + 1] = { header = true, text = L.LAYERS_IN:format(zone) }
	local layers = mapID and ns.Layers.ForMap(mapID) or {}
	if #layers == 0 then lines[#lines + 1] = { text = Grey(L.LAYERS_HINT) } end
	for _, layer in ipairs(layers) do
		local head = layer.head
		lines[#lines + 1] = {
			text = (layer.mine and Green("> ") or "   ") .. Gold(ns.Layers.Name(layer)) .. Grey(("  #%d"):format(layer.zoneUID)),
			right = L.LAYER_COUNT:format(layer.count),
			tooltip = function(tt)
				tt:AddLine(ns.Layers.Name(layer), 1, 0.82, 0)
				if head then tt:AddLine(("%s <%s>"):format(head.name, head.guild or "?"), 1, 1, 1) end
				if layer.mine then tt:AddLine(L.LAYER_YOU, 0.25, 1, 0.25) end
				tt:AddLine(L.LAYER_EXPERIMENTAL, 0.6, 0.6, 0.6, true)
			end,
		}
	end
	return lines
end

local function RealmDetail(s)
	local lords, captains, inactive = 0, 0, 0
	for _, e in ipairs(s.guilds) do
		if e.fresh then
			lords = lords + 1
			captains = captains + #(e.g.officers or {})
			inactive = inactive + (e.g.inactive30 or 0)
		end
	end
	return L.TAB_REALM, L.REALM_DETAIL:format(lords, captains, ns.FormatNumber(inactive)) .. "\n" .. Grey(L.CLICK_EXPAND)
end

function Views.ExpandAll(on)
	for _, e in ipairs(ns.Data.Summary().guilds) do expanded[e.name] = on or nil end
end

---------------------------------------------------------------------------
-- Decrees (layers + decrees)
---------------------------------------------------------------------------

local function DecreeLines()
	local lines = {}
	lines[#lines + 1] = { header = true, text = L.DECREES }
	local decrees = ns.Decree.Active()
	if #decrees == 0 then lines[#lines + 1] = { text = Grey(L.NO_DECREES), gapAfter = true } end
	for _, d in ipairs(decrees) do
		local color = d.kind == "ARMS" and Red or Gold
		lines[#lines + 1] = {
			text = color(ns.Decree.Label(d)) .. "  " .. ns.Zones.NameForKey("m" .. d.mapID),
			right = Grey(ns.Ago(d.t)),
			tooltip = function(tt)
				tt:AddLine(ns.Decree.Label(d), 1, 0.25, 0.25)
				if d.text ~= "" then tt:AddLine(d.text, 1, 1, 1, true) end
				tt:AddLine(L.DECREE_BY:format(d.sender, d.guild, ns.Ago(d.t)), 0.7, 0.7, 0.7)
			end,
		}
		if d.text ~= "" then lines[#lines + 1] = { indent = 1, text = Grey('"' .. d.text .. '"') } end
	end

	return lines
end

local function DecreeHelp(lines)
	lines[#lines + 1] = { header = true, text = L.DECREE_HELP_TITLE }
	for _, k in ipairs({ "ARMS", "MUSTER", "ROYAL", "HERALDRY" }) do
		local who = ns.Decree.CROWN_ONLY[k] and L.WHO_CROWN or L.WHO_CAPTAINS
		lines[#lines + 1] = { text = Gold(L["HELP_" .. k .. "_NAME"]) .. "  " .. Grey("(" .. who .. ")") }
		lines[#lines + 1] = { indent = 1, text = Grey(L["HELP_" .. k]) }
	end
end

local function DecreeDetail()
	local who
	if ns.IsCrown() then who = L.YOU_ARE_CROWN
	elseif ns.Roster.IsOfficer() then who = L.YOU_ARE_OFFICER
	else who = L.YOU_ARE_SOLDIER end
	return L.DECREES_DETAIL_TITLE, who
end

---------------------------------------------------------------------------
-- Heraldry (tabard inspection + Wall of Shame)
---------------------------------------------------------------------------

local STATUS_TEXT = {
	GUILD = function() return Green(L.TABARD_OK) end,
	NONE = function() return Red(L.TABARD_NONE) end,
	OTHER = function() return Gold(L.TABARD_OTHER) end,
	UNKNOWN = function() return Grey(L.TABARD_UNKNOWN) end,
	UNCHECKED = function() return Grey(L.TABARD_UNCHECKED) end,
	YOUNG = function() return Grey(L.TABARD_YOUNG) end,
}

local function HeraldryLines()
	local s = ns.Inspect.Summary()
	local lines = {}
	local shame = ns.Inspect.Shame()
	if not ns.Inspect.ShameOpen() then
		-- Closed until the tabard rule is in force (Inspect.lua): a countdown.
		local left = ns.Inspect.ShameOpensIn()
		local wait = ("%dh %02dm"):format(math.floor(left / 3600), math.floor(left % 3600 / 60))
		lines[#lines + 1] = { header = true, text = Red(L.WALL_OF_SHAME), right = Grey(L.SHAME_OPENS:format(wait)) }
		lines[#lines].gapAfter = true
	elseif not (shame and #shame.list > 0) then
		-- Always there, so everyone knows it exists: empty until the Crown publishes one.
		lines[#lines + 1] = { header = true, text = Red(L.WALL_OF_SHAME), right = Grey(L.SHAME_EMPTY) }
		lines[#lines].gapAfter = true
	else
		lines[#lines + 1] = { header = true, text = Red(L.WALL_OF_SHAME), right = Grey(L.PUBLISHED_BY:format(shame.by, ns.Ago(shame.t))) }
		for i = 1, math.min(12, #shame.list) do
			local p = shame.list[i]
			lines[#lines + 1] = { indent = 1, key = p.name, text = p.name .. "  " .. Grey("<" .. (p.guild or "?") .. ">"),
				onClick = function() ns.UI.ShowPerson({ name = p.name, guild = p.guild }) end }
		end
		if #shame.list > 12 then lines[#lines + 1] = { indent = 1, text = Grey(L.AND_MORE:format(#shame.list - 12)) } end
		lines[#lines].gapAfter = true
	end
	lines[#lines + 1] = { header = true, text = L.GUILDS }
	for i = 1, math.min(8, #s.guilds) do
		local g = s.guilds[i]
		lines[#lines + 1] = {
			text = (g.marked and Red("! ") or "") .. Green("<" .. g.name .. ">"),
			right = L.GUILD_BAD:format(g.bad, g.total),
			onClick = function() ns.Inspect.ToggleGuildMark(g.name) end,
			tooltip = function(tt) tt:AddLine("<" .. g.name .. ">", 0.25, 1, 0.25); tt:AddLine(L.CLICK_MARK_GUILD, 0.8, 0.8, 0.8) end,
		}
	end
	if #s.guilds == 0 then lines[#lines + 1] = { text = Grey(L.INSPECT_EMPTY) } end
	lines[#lines].gapAfter = true
	lines[#lines + 1] = { header = true, text = L.INSPECTED_PLAYERS }
	for _, p in ipairs(s.players) do
		lines[#lines + 1] = {
			key = p.name,
			cols = {
				(p.marked and Red("! ") or "") .. ClassColored(ns.ShortName(p.name), p.class),
				Grey(p.guild and ("<" .. p.guild .. ">") or ""),
				(STATUS_TEXT[p.status or "UNKNOWN"] or STATUS_TEXT.UNKNOWN)(),
				Grey(ns.Ago(p.t)),
			},
			onClick = function()
				local code = ns.Roster.ClassCode(p.class)
				ns.UI.ShowPerson({
					name = ns.ShortName(p.name), class = code ~= "" and code or nil, level = p.level, guild = p.guild,
					tabard = (STATUS_TEXT[p.status or "UNKNOWN"] or STATUS_TEXT.UNKNOWN)(), note = p.note,
					onMark = function() ns.Inspect.ToggleMark(p.name) end,
				})
			end,
			tooltip = function(tt)
				tt:AddLine(ClassColored(p.name, p.class))
				tt:AddLine("<" .. (p.guild or "?") .. ">" .. (p.level and ("  lvl " .. p.level) or ""), 0.25, 1, 0.25)
				if p.note then tt:AddLine('"' .. p.note .. '"', 1, 0.5, 0.5, true) end
				tt:AddLine(L.CLICK_MARK_PLAYER, 0.6, 0.6, 0.6)
			end,
		}
	end
	return lines
end

local function HeraldryDetail()
	local s = ns.Inspect.Summary()
	local c = s.counts
	return L.INSPECT_COUNTS:format(s.total, c.GUILD, c.NONE, c.OTHER),
		(ns.Inspect.IsPatrolling() and Green(L.PATROL_ON) or Grey(L.PATROL_HINT))
end

---------------------------------------------------------------------------
-- Join Olympus (what non-members see)
---------------------------------------------------------------------------

function Views.RecruitLines()
	local R = ns.Recruit
	local lines = { { header = true, text = L.RECRUIT_TITLE } }
	local guilds = R.Guilds()
	if #guilds == 0 then
		lines[#lines + 1] = { text = Grey(#R.found == 0 and not ns.Who.Searched() and L.RECRUIT_START or L.RECRUIT_NONE_FOUND) }
		return lines
	end
	-- "Showing 50 of 312 online", and which levels the next click searches.
	WhoStatus(lines)
	if #lines > 1 then lines[#lines].gapAfter = true end
	for _, g in ipairs(guilds) do
		lines[#lines + 1] = {
			text = Green("<" .. g.name .. ">"),
			right = Grey(L.RECRUIT_ONLINE:format(#g.members)) .. "  " .. Gold(L.RECRUIT_ASK),
			onClick = function() R.PromptNext(g.name) end,
			tooltip = function(tt)
				tt:AddLine("<" .. g.name .. ">", 0.25, 1, 0.25)
				tt:AddLine(L.RECRUIT_ASK_TIP, 1, 1, 1, true)
			end,
		}
		for _, p in ipairs(g.members) do
			local state = ""
			if R.replied[p.name] then state = Green(L.RECRUIT_STATE_REPLIED)
			elseif R.asked[p.name] then state = Grey(L.RECRUIT_STATE_ASKED) end
			lines[#lines + 1] = {
				indent = 1,
				text = ClassColored(ns.ShortName(p.name), p.class) .. "  " .. Grey((p.level and L.LEVEL_N:format(p.level) or "") .. (p.zone and ("  " .. p.zone) or "")),
				right = state,
				onClick = function() StaticPopup_Show("OLYMPUS_RECRUIT", p.name, p.guild, p) end,
				tooltip = R.replied[p.name] and function(tt)
					tt:AddLine(ns.ShortName(p.name), 1, 0.82, 0)
					tt:AddLine('"' .. R.replied[p.name] .. '"', 1, 1, 1, true)
				end or nil,
			}
		end
		lines[#lines].gapAfter = true
	end
	return lines
end

---------------------------------------------------------------------------
-- Entry point used by UI.lua
---------------------------------------------------------------------------

-- Each tab's lines, detail title and detail text. A tab missing here (a new one being
-- added) is an empty list.
local BUILD = {
	census = function(s)
		local title, text = CensusDetail(s)
		return CensusLines(s), title, text
	end,
	realm = function(s)
		local title, text = RealmDetail(s)
		return RealmLines(s), title, text
	end,
	decrees = function()
		local title, text = DecreeDetail()
		local lines = DecreeLines()
		DecreeHelp(lines)
		return lines, title, text
	end,
	heraldry = function()
		local title, text = HeraldryDetail()
		return HeraldryLines(), title, text
	end,
	throne = function(s)
		if not (ns.King and ns.King.Build) then return {}, nil, nil end
		local lines, title, text = ns.King.Build(s)
		return lines or {}, title, text
	end,
}

function Views.Build(tab)
	local build = BUILD[tab]
	if not build then return {}, nil, nil end
	return build(ns.Data.Summary())
end

-- Kept for the tests: the Realm tree lines.
function Views.RealmLines() return RealmLines(ns.Data.Summary()) end
