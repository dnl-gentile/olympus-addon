local ADDON, ns = ...
local L = ns.L

-- Content of the four tabs. Each tab gives: column headers (optional), a list of lines,
-- a detail box (title + text, like the guild "Message of the Day" box) and three buttons.
-- The renderer draws lines with Blizzard fonts; a line is either
--   { text, right, indent, header, color, onClick, tooltip = function(tt) end }
-- or a table row { cols = { ... } } drawn with the tab's column layout. `key` (a player's
-- name) marks a line that opens a person: the HD window keeps it lit while it is open.
-- `input = { text, onChange = function(text) end }`: a text box after the line's text (the
-- Workshop's search, 0.9.9; the tabs' searches on top of their lists, 1.0.0), one per list,
-- with an "x" that empties it.

local Views = {}
ns.Views = Views

local ROW_H = 16
local ROW_H_HD = 20 -- the Guild & Communities roster's rows (CommunitiesMemberList.xml)
local ROW_H_INPUT = 24 -- a row with a text box (line.input): the box and its border
-- A table row's cells at most (line.cols): the Census's five (1.2.4: its average level), the others' four.
Views.MAX_COLS = 5
-- The in-page tabs' look (Views.DrawNav, the one component of the Realm's Guilds / Classes /
-- Races / Professions and of the Chat tab's destinations): white inactive words, gold selected
-- words and the same white underline at the strip's bottom. pad: a cell's room beside its words;
-- minPad: the least it keeps, its words too many for the strip, before any is cut (Views.DrawNav).
Views.SUBTAB_STYLE = {
	height = 24, labelY = -2, underlineHeight = 2, underlineY = 0, underlineInset = 3, pad = 8, minPad = 4,
	selected = { 1, 0.82, 0, 1 }, inactive = { 1, 1, 1, 1 }, underline = { 1, 1, 1, 1 },
}
local ROW_H_NAV = Views.SUBTAB_STYLE.height -- the Realm's Guilds / Classes / Races / Professions
local ITEM, ITEM_GAP = 30, 2 -- an item on an items row (line.items) without the game's button template (37 with it)
local ITEM_GAME = 37 -- the game's item button (ItemButtonTemplate)
Views.ITEM_SLOT = ITEM_GAME -- (1.2.4: the slot a grid that fits its room is laid out for, ProfileEdit.IconGrid)
local expanded = {}
local CROWN = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:13:13|t "
local ASSIST = "|TInterface\\GroupFrame\\UI-Group-AssistantIcon:12:12|t "

local function Green(s) return "|cff40ff40" .. s .. "|r" end
-- 1.1.2: a count's tooltip ends with why it can differ between players (Answers.lua, the bank's).
local function Why(tt, ...)
	local A = ns.Answers
	if A and type(A.WhyTip) == "function" then A.WhyTip(tt, ...) end
end
local function Grey(s) return "|cff9d9d9d" .. s .. "|r" end
local function Red(s) return "|cffff4040" .. s .. "|r" end
local function Gold(s) return "|cffffd200" .. s .. "|r" end
Views.Green, Views.Grey, Views.Red, Views.Gold = Green, Grey, Red, Gold

-- Names and guilds from other players' reports: shown as plain text, whatever they carry
-- (0.9.2; Comm.lua already strips every escape code from what arrives).
local Plain = ns.Codec.Plain

local function ClassColored(name, classFile)
	name = Plain(ns.CoverSwap(name))
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	return c and ("|c%s%s|r"):format(c.colorStr, name) or name
end
Views.ClassColored = ClassColored

-- `dim`: what an old report said (older than Data.FRESH), all grey, as its guild is in the tree.
-- `at`: (1.2.1) when an old report said he was online, nobody seeing him now: "online <age> ago".
local function Presence(online, days, dim, at)
	if online == nil and type(at) == "number" then
		local age = math.max(0, ns.Now() - at)
		return Grey(age >= 86400 and L.ONLINE_DAYS_AGO:format(math.floor(age / 86400)) or L.ONLINE_AGO:format(ns.Ago(at)))
	end
	if online then return (dim and Grey or Green)(L.ONLINE_NOW) end
	if not days or days < 1 then return Grey(L.OFFLINE_TODAY) end
	local d = math.floor(days)
	local text = L.OFFLINE_DAYS:format(d)
	if d >= (ns.db.warnDays or 3) then return (dim and Grey or Red)(text .. " !") end
	return Grey(text)
end

-- 1.2.1 (an officer: his guild master "has been online for hours" while the census showed him away).
-- A guild's report is its word when it was made; /who's is this quarter-hour's. Seen in that guild
-- by /who now (its own search when its row was opened, or the round), a Lord or Captain of another
-- guild is online whatever an old report said; otherwise a report older than Data.FRESH says what it
-- said, grey (Presence's `dim`), never in red as if it were today's; where it said online, he is not
-- known to be online now: nil, and when it said so (Presence's `at`), as Members.CheckLords counts him
-- away from then. Our own guild is our roster, the server's word. `e`: a guild of Data.Summary's
-- list; returns online, days, dim, at.
local roundIndex = {} -- the round's players as "<guild>\0<name folded>", made again when the round grows
function Views.SeenNow(guild, name)
	local W = ns.Who
	if not W or type(guild) ~= "string" or type(name) ~= "string" or name == "" then return false end
	local key = ns.Fold(ns.ShortName(name))
	for _, p in ipairs(W.GuildSeen and W.GuildSeen(guild) or {}) do
		if p.guild == guild and type(p.name) == "string" and ns.Fold(ns.ShortName(p.name)) == key then return true end
	end
	local sweep = W.sweep
	local round = sweep and sweep.started and GetTime() - sweep.started <= (W.ROUND_TTL or 900) and sweep.list
	if type(round) ~= "table" then return false end
	if roundIndex.list ~= round or roundIndex.n ~= #round then
		local set = {}
		for _, p in ipairs(round) do
			if type(p.guild) == "string" and type(p.name) == "string" then set[p.guild .. "\0" .. ns.Fold(ns.ShortName(p.name))] = true end
		end
		roundIndex = { list = round, n = #round, set = set }
	end
	return roundIndex.set[guild .. "\0" .. key] == true
end
function Views.PresenceNow(e, name, online, days)
	if type(e) ~= "table" or e.name == GetGuildInfo("player") then return online, days, false end
	if Views.SeenNow(e.name, name) then return true, 0, false end
	if e.fresh == false and online then
		return nil, nil, true, e.observed or (type(e.g) == "table" and tonumber(e.g.t) or nil)
	end
	return online, days, e.fresh == false
end

---------------------------------------------------------------------------
-- Column layouts, as fractions of the list width (so they follow the window size)
---------------------------------------------------------------------------

-- (1.2.4, the author's ask: the guild's average level in a column of its own, sorted by its title
-- like the others; its title is short, "Avg lvl" / "Nv. méd.". The Online column gives up some room,
-- its numbers being the smaller, and the Guild and Lord columns some; before, the four columns
-- were 0.40, 0.20, 0.16 and 0.24.)
-- (1.2.4's review: the Online and Avg lvl titles a little more room, from the Guild's, and the three
-- numbers' a short title each, `short`: a title wider than its column takes it, and one still too
-- wide is cut inside its own (UI.Layout), never drawn over the next; the German, Spanish and French
-- titles are longer. The old window's columns are then 90, 54, 45, 54 and 57 wide; the HD one's
-- 106, 64, 53, 64 and 67.)
Views.COLUMNS = {
	census = {
		{ key = "COL_GUILD", sort = "name", x = 0.00, w = 0.30 },
		{ key = "COL_MEMBERS", short = "COL_MEMBERS_SHORT", sort = "members", x = 0.30, w = 0.18, justify = "RIGHT" },
		{ key = "COL_ONLINE", short = "COL_ONLINE_SHORT", sort = "online", x = 0.48, w = 0.15, justify = "RIGHT" },
		{ key = "COL_AVG_LEVEL", short = "COL_AVG_LEVEL_SHORT", sort = "level", x = 0.63, w = 0.18, justify = "RIGHT" },
		{ key = "COL_LORD", sort = "lord", x = 0.81, w = 0.19 },
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
	for c = 1, Views.MAX_COLS do
		local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetWordWrap(false)
		r.cols[c] = fs
	end
	r.index = i
	if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
	r:SetScript("OnClick", function(self, button)
		if not self.line then return end
		-- A right-click on a row that names a player: the player menus' lines (PlayerMenu.OpenFor).
		if button == "RightButton" then
			local who = self.line.player
			if who and ns.PlayerMenu and ns.PlayerMenu.OpenFor then ns.PlayerMenu.OpenFor(self, who, self.line.offline) end
			return
		end
		-- HD: the person opened stays lit, like the roster's selected member.
		if content.style == "hd" and self.line.key then ns.SafeCall("view select", Views.Select, content, self.line.key) end
		-- Where the row was clicked, for the redraw its click causes (UI.lua keeps it in place):
		-- its place in the list, the list's offset then (the list is the scroll frame's child).
		-- A row with nothing to do on a click (a tooltip, a heading) causes no redraw.
		if self.line.onClick then
			local scroll = content:GetParent()
			local offset = scroll and scroll.GetVerticalScroll and scroll:GetVerticalScroll()
			content.click = { index = self.index, top = self.top or 0, lines = content.lineCount or 0, t = GetTime(),
				offset = type(offset) == "number" and offset or nil }
			ns.SafeCall("view click", self.line.onClick)
		end
		if ns.UI and ns.UI.Clicked then ns.UI.Clicked() end
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

-- An item's icon: the snapshot's, or the client's for the id.
local function ItemIcon(it)
	if it.icon then return it.icon end
	if GetItemInfoInstant then
		local ok, _, _, _, _, icon = pcall(GetItemInfoInstant, it.id)
		if ok and icon then return icon end
	end
	if C_Item and C_Item.GetItemIconByID then
		local ok, icon = pcall(C_Item.GetItemIconByID, it.id)
		if ok and icon then return icon end
	end
	return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- One slot of an items row: the game's own item button (ItemButtonTemplate: the slot, the
-- icon, the count, the quality border) where the client has it, the same made here where
-- not; the item's own tooltip on hover, like a bag's.
local function ItemButton(r, k)
	local ok, b = pcall(CreateFrame, "Button", nil, r, "ItemButtonTemplate")
	if ok and b and b.icon and SetItemButtonTexture then
		b.blizzard = true
		r.itemSize = ITEM_GAME
	else
		if ok and b then b:Hide() end
		b = CreateFrame("Button", nil, r)
		b:SetSize(ITEM, ITEM)
		b.slot = b:CreateTexture(nil, "BACKGROUND")
		b.slot:SetTexture("Interface\\Buttons\\UI-EmptySlot")
		b.slot:SetTexCoord(0.2, 0.8, 0.2, 0.8)
		b.slot:SetAllPoints()
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints()
		b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		b.count:SetPoint("BOTTOMRIGHT", -2, 2)
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		r.itemSize = r.itemSize or ITEM
	end
	b:RegisterForClicks("LeftButtonUp")
	b:SetScript("OnClick", function(self)
		-- 1.1: a grid whose line takes a click on an item (the Treasury's bank: a Lord or a
		-- Captain asks the treasury for it, Bank.lua), a plain click.
		local it = self.item
		local row = self.GetParent and self:GetParent()
		local line = row and row.line
		if it and not it.gone and line and line.onItem and not (IsShiftKeyDown and IsShiftKeyDown()) then
			return ns.SafeCall("view item", line.onItem, it)
		end
		-- Shift-click: the link into the chat box, as in a bag (not with the gamepad UI: its
		-- chat box would be blocked, see Dialog.lua).
		if not it or not IsShiftKeyDown or not IsShiftKeyDown() or not ns.Gate.Allowed("chat-box") or not ChatEdit_InsertLink then return end -- gp:chat-box
		local link = it.link
		if not link and GetItemInfo then local okInfo, _, l = pcall(GetItemInfo, it.id); if okInfo then link = l end end
		if link then
			ns.Gate.Used("chat-box") -- (the gate's: told at a switch to the gamepad UI)
			pcall(ChatEdit_InsertLink, link) -- gp:chat-box
		end
	end)
	b:SetScript("OnEnter", function(self)
		local it = self.item
		if not it then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local ok = false
		if it.link and GameTooltip.SetHyperlink then ok = pcall(GameTooltip.SetHyperlink, GameTooltip, it.link) end
		if not ok and it.id and GameTooltip.SetItemByID then ok = pcall(GameTooltip.SetItemByID, GameTooltip, it.id) end
		-- (1.2.4: a slot that is no item, an icon of "My profile"'s picker: its name, never "#nil".)
		if not ok then GameTooltip:AddLine(it.label or ("#" .. tostring(it.id)), 1, 1, 1) end
		if (it.n or 0) > 1 then GameTooltip:AddLine("x" .. it.n, 0.8, 0.8, 0.8) end
		if it.gone then GameTooltip:AddLine(L.BANK_GONE_SLOT, 1, 0.4, 0.4, true) end
		local row = self.GetParent and self:GetParent()
		local hint = not it.gone and row and row.line and row.line.itemHint
		if hint then GameTooltip:AddLine(hint, 0.6, 1, 0.6, true) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	r.items = r.items or {}
	r.items[k] = b
	return b
end

-- One button in an in-page navigation strip. These are ordinary addon buttons, not secure
-- actions: their clicks only select which already-known rows the page draws. The button is
-- handed to its item's onClick: a picker's list opens from it (the Chat tab's Race, Class, Arena).
local function NavButton(r, k)
	local style = Views.SUBTAB_STYLE
	local b = CreateFrame("Button", nil, r)
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.label:SetPoint("CENTER", 0, style.labelY)
	b.label:SetWordWrap(false)
	b.underline = b:CreateTexture(nil, "ARTWORK")
	b.underline:SetColorTexture(unpack(style.underline))
	b.underline:SetHeight(style.underlineHeight)
	b.underline:SetPoint("BOTTOMLEFT", style.underlineInset, style.underlineY)
	b.underline:SetPoint("BOTTOMRIGHT", -style.underlineInset, style.underlineY)
	b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	b:SetScript("OnClick", function(self)
		local item = self.item
		if item and item.onClick then ns.SafeCall("view navigation", item.onClick, self) end
		if ns.UI and ns.UI.Clicked then ns.UI.Clicked() end
	end)
	b:SetScript("OnEnter", function(self)
		local item = self.item
		if not (item and item.tooltip) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		ns.SafeCall("view navigation tooltip", item.tooltip, GameTooltip)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	r.nav = r.nav or {}
	r.nav[k] = b
	return b
end

-- How wide a font string's words are, whatever room its anchors give it.
local function StringWidth(fs)
	local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
	return tonumber(w) or 0
end

-- The mark after a picker's words (test33: the Chat tab's down triangle, U+25BE, was a box: the
-- game's fonts have no such glyph): the arrow of Forever's own friends list headers (Blizzard_FriendsFrame/Camelot/
-- FriendsFrame.xml, "friendslist-categorybutton-arrow-down"), as tall as the strip's small font,
-- else the arrow of the game's dropdown button (Blizzard_SharedXML/Mainline/
-- UIDropDownMenuTemplates.xml), a file every client carries. Never a character.
Views.PICKER_ATLAS = "friendslist-categorybutton-arrow-down"
Views.PICKER_FILE = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up"
function Views.PickerMark()
	local info = C_Texture and C_Texture.GetAtlasInfo
	local ok, found = false, nil
	if type(info) == "function" then ok, found = pcall(info, Views.PICKER_ATLAS) end
	if ok and type(found) == "table" then
		local h = 9
		local aw, ah = tonumber(found.width) or 0, tonumber(found.height) or 0
		local w = aw > 0 and ah > 0 and math.max(4, math.min(2 * h, math.floor(aw * h / ah + 0.5))) or h
		return ("|A:%s:%d:%d|a"):format(Views.PICKER_ATLAS, h, w)
	end
	return ("|T%s:12:12|t"):format(Views.PICKER_FILE)
end

-- Views.NavCells(words, width): each cell's width (whole pixels, `width` together) for labels whose
-- words are `words[k]` wide. Alike while every label and its pad fit an equal share (the Realm's
-- look); else by need, the room left shared by need, while every label and its pad fit; else the
-- pads shrink to minPad before a word is cut; else each label that fits a fair share keeps its
-- words whole and the long ones split what is left alike (water-filling): only they are cut. (The
-- review of test33: the cells shrank all by one ratio, and every label, "Guild" too, lost a pixel
-- or more to "...", a High Councillor's six destinations in the chat's strip.)
function Views.NavCells(words, width)
	local style = Views.SUBTAB_STYLE
	local n, cells = #words, {}
	if n == 0 then return cells end
	local total, alike = 0, true
	for k = 1, n do
		total = total + words[k] + style.pad
		if words[k] + style.pad > math.floor(width / n) then alike = false end
	end
	-- (`extra` spread over the cells, whole pixels, by `weight`, on top of `base`: the odd pixels
	-- where the equal cells always had them.)
	local function Spread(base, weight, extra)
		local sum, before = 0, 0
		for k = 1, n do sum = sum + weight[k] end
		for k = 1, n do
			local from, to = math.floor(before * extra / sum), math.floor((before + weight[k]) * extra / sum)
			cells[k] = base[k] + to - from
			before = before + weight[k]
		end
		return cells
	end
	local zero, one, natural = {}, {}, {}
	for k = 1, n do zero[k], one[k], natural[k] = 0, 1, words[k] + style.pad end
	if alike then return Spread(zero, one, width) end
	if total <= width then return Spread(zero, natural, width) end
	local fixed, left, pool, grew = {}, width, n, true
	while grew and pool > 0 do
		grew = false
		local share = left / pool
		for k = 1, n do
			local want = words[k] + style.minPad
			if not fixed[k] and want <= share then
				fixed[k], cells[k] = true, want
				left, pool, grew = left - want, pool - 1, true
			end
		end
	end
	if pool == 0 then -- (every label whole, its pad thinner: the room left alike)
		return Spread(cells, one, left)
	end
	local i = 0
	for k = 1, n do
		if not fixed[k] then
			i = i + 1
			cells[k] = math.floor(i * left / pool) - math.floor((i - 1) * left / pool)
		end
	end
	return cells
end

-- An in-page navigation strip in `holder` (a list row, or the Chat tab's strip), `width` wide and
-- SUBTAB_STYLE.height tall: the one component of the Realm's Guilds / Classes / Races /
-- Professions and of the Chat tab's destinations (test33, the owner's ask: the Chat tab's subtabs
-- as the Realm's, the same component, not a copy). `items`: { text, selected, onClick =
-- function(button), tooltip = function(tt), picker = true }; a picker opens a list of choices
-- from its button (the Chat tab's Race, Class and Arena): Views.PickerMark after its words. The
-- cells' widths: Views.NavCells. A label longer than its cell is cut ("...") inside it, never drawn
-- over the next cell. Returns the strip's height.
function Views.DrawNav(holder, items, width)
	local style = Views.SUBTAB_STYLE
	local words = {}
	for k, item in ipairs(items) do
		local b = holder.nav and holder.nav[k] or NavButton(holder, k)
		b.item = item
		b.label:SetFontObject("GameFontNormalSmall")
		b.label:SetText((item.text or "") .. (item.picker and (" " .. Views.PickerMark()) or ""))
		words[k] = math.ceil(StringWidth(b.label))
	end
	local cells, x = Views.NavCells(words, width), 0
	for k, item in ipairs(items) do
		local b = holder.nav[k]
		local w = cells[k]
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", x, 0)
		b:SetSize(w, ROW_H_NAV)
		x = x + w
		b.label:ClearAllPoints()
		if words[k] + style.minPad > w then
			b.label:SetPoint("LEFT", style.minPad / 2, style.labelY)
			b.label:SetPoint("RIGHT", -style.minPad / 2, style.labelY)
		else
			b.label:SetPoint("CENTER", 0, style.labelY)
		end
		b.label:SetJustifyH("CENTER")
		b.label:SetTextColor(unpack(item.selected and style.selected or style.inactive))
		b.underline:SetShown(item.selected == true)
		b:EnableMouse(item.onClick ~= nil or item.tooltip ~= nil)
		b:Show()
	end
	for k = #items + 1, #(holder.nav or {}) do holder.nav[k]:Hide() end
	return ROW_H_NAV
end

-- Page searches and tabs are fixed window chrome; forms and action choices stay in the body.
-- Census keeps its search in the list, so callers opt in to separating marked searches.
function Views.SplitPageNav(lines, separateSearch)
	local body, navigation, search = {}, {}, nil
	for _, line in ipairs(lines or {}) do
		if line.pageNav and line.nav then navigation[#navigation + 1] = line
		elseif separateSearch and line.pageSearch and line.input and not search then search = line
		else body[#body + 1] = line end
	end
	return body, navigation, search
end

-- A filter's open menu, one row per choice of `spec` (the selected one lit), as wide as its longest.
local function FillChoices(menu, spec)
	local menuWidth = 100
	for j, option in ipairs(spec.options) do
		local pick = menu.buttons[j]
		if not pick then
			pick = CreateFrame("Button", nil, menu)
			pick:SetPoint("TOPLEFT", 6, -6 - (j - 1) * 22)
			pick:SetPoint("TOPRIGHT", -6, -6 - (j - 1) * 22)
			pick:SetHeight(22)
			pick.label = pick:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			pick.label:SetPoint("LEFT", 8, 0)
			pick.label:SetPoint("RIGHT", -8, 0)
			pick.label:SetJustifyH("LEFT")
			local hl = pick:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.12)
			pick:SetScript("OnClick", function(button)
				menu:Hide()
				if button.choice and button.choice.onClick then ns.SafeCall("view filter", button.choice.onClick) end
			end)
			menu.buttons[j] = pick
		end
		pick.choice = option
		pick.label:SetText(option.text)
		pick.label:SetTextColor(unpack(option.selected and Views.SUBTAB_STYLE.selected or Views.SUBTAB_STYLE.inactive))
		menuWidth = math.max(menuWidth, math.ceil(StringWidth(pick.label)) + 28)
		pick:Show()
	end
	for j = #spec.options + 1, #menu.buttons do menu.buttons[j]:Hide() end
	menu:SetSize(menuWidth, 12 + #spec.options * 22)
end

-- The same filter offering the same choices (its label, each choice's words, in order).
local function SameChoices(a, b)
	if type(a) ~= "table" or type(b) ~= "table" or a.label ~= b.label or #(a.options or {}) ~= #(b.options or {}) then return false end
	for j, option in ipairs(a.options) do
		if option.text ~= b.options[j].text then return false end
	end
	return true
end

function Views.DrawFilters(holder, filters, width)
	holder.filters = holder.filters or {}
	local cell = math.floor(width / math.max(1, #filters))
	for i, filter in ipairs(filters) do
		local b = holder.filters[i]
		if not b then
			b = CreateFrame("Button", nil, holder, not filter.understated and "UIPanelButtonTemplate" or nil)
			if filter.understated then
				b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				b.label:SetPoint("LEFT", 6, 0)
				b.label:SetPoint("RIGHT", -6, 0)
				b.label:SetJustifyH("LEFT")
				b:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 0.82, 0) end)
				b:SetScript("OnLeave", function(self) self.label:SetTextColor(1, 1, 1) end)
			end
			b:SetScript("OnHide", function(self) if self.choices then self.choices:Hide() end end)
			b:SetScript("OnClick", function(self)
				local spec = self.filter
				if not spec then return end
				local menu = self.choices
				if menu and menu:IsShown() then menu:Hide(); return end
				for _, other in ipairs(holder.filters) do if other.choices then other.choices:Hide() end end
				if not menu then
					-- A dropdown, not another window. Keep it outside the scrolling body's clipping.
					local ok, made = pcall(CreateFrame, "Frame", nil, UIParent, "BackdropTemplate")
					menu = ok and made or CreateFrame("Frame", nil, UIParent)
					if menu.SetBackdrop then
						menu:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
							edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
							insets = { left = 3, right = 3, top = 3, bottom = 3 } })
						if menu.SetBackdropColor then menu:SetBackdropColor(0.06, 0.06, 0.07, 0.95) end
						if menu.SetBackdropBorderColor then menu:SetBackdropBorderColor(0.5, 0.5, 0.5, 1) end
					else
						local bg = menu:CreateTexture(nil, "BACKGROUND")
						bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.06, 0.07, 0.95)
					end
					menu:SetFrameStrata("DIALOG")
					menu:EnableMouse(true)
					if menu.SetClampedToScreen then menu:SetClampedToScreen(true) end
					menu.catcher = CreateFrame("Button", nil, UIParent)
					menu.catcher:SetFrameStrata("DIALOG")
					menu.catcher:SetAllPoints(UIParent)
					menu.catcher:SetScript("OnClick", function() menu:Hide() end)
					menu.catcher:Hide()
					menu:SetScript("OnHide", function() menu.catcher:Hide() end)
					menu.buttons = {}
					self.choices = menu
				end
				menu.catcher:SetFrameLevel((self:GetFrameLevel() or 1) + 30)
				menu:SetFrameLevel(menu.catcher:GetFrameLevel() + 1)
				menu:ClearAllPoints()
				menu:SetPoint(self.rightmost and "TOPRIGHT" or "TOPLEFT", self, self.rightmost and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, -2)
				FillChoices(menu, spec)
				menu.catcher:Show()
				menu:Show()
			end)
			holder.filters[i] = b
		end
		-- A reused row can belong to another page; its previous choices are no longer valid. (1.2.6: a
		-- redraw that changed none of them, a census word or a Church answer arriving, keeps the open
		-- menu, its rows this drawing's choices: it closed under the player's mouse, the author's
		-- report of 10-06, "eles ficam sumindo".)
		if b.choices and b.choices:IsShown() and SameChoices(b.filter, filter) then FillChoices(b.choices, filter)
		elseif b.choices then b.choices:Hide() end
		b.filter = filter
		b.rightmost = i == #filters
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", (i - 1) * cell + 2, -2)
		b:SetSize(math.max(1, cell - 4), 22)
		local label = (filter.understated and Grey(filter.label .. ":") or filter.label .. ":") .. " " .. filter.value .. " " .. Views.PickerMark()
		if b.label then b.label:SetText(label); b.label:SetTextColor(1, 1, 1) else b:SetText(label) end
		b:Show()
	end
	for i = #filters + 1, #holder.filters do holder.filters[i]:Hide() end
	return 28
end

-- A slot's item (nil: empty), drawn the way the game draws it.
local function SetSlot(b, it)
	b.item = it
	if b.blizzard then
		SetItemButtonTexture(b, it and ItemIcon(it) or nil)
		if SetItemButtonCount then SetItemButtonCount(b, it and it.n or 0) end
		if SetItemButtonQuality then
			local quality
			if it and GetItemInfo then
				local ok, _, _, q = pcall(GetItemInfo, it.link or it.id)
				if ok then quality = q end
			end
			pcall(SetItemButtonQuality, b, quality, it and (it.link or it.id) or nil)
		end
	else
		b.icon:SetTexture(it and ItemIcon(it) or nil)
		b.icon:SetShown(it ~= nil)
		b.count:SetText(it and (it.n or 0) > 1 and tostring(it.n) or "")
	end
	-- 1.1: a stack gone since the snapshot before (the Treasury's bank, Bank.Gone): faded and red,
	-- in the slot it sat in.
	local gone = it ~= nil and it.gone == true
	if b.icon.SetDesaturated then b.icon:SetDesaturated(gone) end
	if b.icon.SetVertexColor then
		if gone then b.icon:SetVertexColor(1, 0.35, 0.35) else b.icon:SetVertexColor(1, 1, 1) end
	end
	if b.SetAlpha then b:SetAlpha(gone and 0.6 or 1) end
	-- 1.2: a stack the Treasury's search led to (it.found), lit as the mouse lights a slot.
	if b.LockHighlight and b.UnlockHighlight then
		if it ~= nil and it.found == true and not gone then b:LockHighlight() else b:UnlockHighlight() end
	end
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

-- The "x" at the end of a box that holds text (1.0.0): a click empties it and lets go of the
-- keyboard. A button of its own, never a focus change.
local function ClearButton(eb)
	local x = CreateFrame("Button", nil, eb)
	x:SetSize(16, 16)
	x:SetPoint("RIGHT", eb, "RIGHT", -2, 0)
	x.label = x:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	x.label:SetPoint("CENTER", x, "CENTER", 0, 1)
	x.label:SetText("x")
	x:SetScript("OnClick", function()
		local input = eb.line and eb.line.input
		eb:SetText("")
		eb:ClearFocus()
		x:Hide()
		if input and input.onChange then ns.SafeCall("view input", input.onChange, "") end
	end)
	x:SetScript("OnEnter", function(self)
		self.label:SetTextColor(1, 1, 1)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L.SEARCH_CLEAR, 1, 0.82, 0)
		GameTooltip:Show()
	end)
	x:SetScript("OnLeave", function(self)
		self.label:SetTextColor(1, 0.82, 0)
		GameTooltip:Hide()
	end)
	x:Hide()
	return x
end

-- 1.2: an item dragged onto a box whose line takes items (line.input.items: the Treasury's search
-- over the Guild treasuries) puts its link there, as if pasted in, and the item goes back where it
-- was (ClearCursor). Olympus's own box alone: the game's Shift-click sends a link to the game's
-- boxes only, and Olympus hooks none of them (ChatFrameUtil.InsertLink). Never with the gamepad UI.
local function DropItem(eb)
	local input = eb.line and eb.line.input
	if not (input and input.items) or ns.GamepadUI() or type(GetCursorInfo) ~= "function" then return false end
	local kind, id, link = GetCursorInfo()
	if kind ~= "item" or not tonumber(id) then return false end
	if type(link) ~= "string" or not link:find("item:", 1, true) then link = "item:" .. math.floor(tonumber(id)) end
	if type(ClearCursor) == "function" then ClearCursor() end
	eb:SetText(link)
	return true
end
Views.DropItem = DropItem

-- The list's text box (line.input): one per list, made the first time a line asks for one and
-- moved onto that line's row at each redraw, so typing goes on while the list changes under it.
-- Like the council icon picker's filter, it never takes the keyboard by itself (the gamepad UI's
-- rule, ns.Focus): the player clicks into it; Enter, Escape or its list hiding let go of it.
local function InputBox(content)
	if content.input then return content.input end
	local ok, eb = pcall(CreateFrame, "EditBox", nil, content, "InputBoxTemplate")
	if not ok or not eb then eb = CreateFrame("EditBox", nil, content) end
	eb:SetAutoFocus(false)
	eb:Hide()
	eb:SetHeight(20)
	eb:SetMaxLetters(40)
	eb:SetFontObject("ChatFontNormal")
	eb:SetTextInsets(0, 18, 0, 0) -- (the typing stops short of the "x")
	eb.olympusBox = true
	eb.clear = ClearButton(eb)
	eb:SetScript("OnTextChanged", function(self)
		local text = self:GetText() or ""
		self.clear:SetShown(text ~= "")
		local input = self.line and self.line.input
		if input and input.onChange then ns.SafeCall("view input", input.onChange, text) end
	end)
	eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnHide", function(self) self:ClearFocus() end)
	eb:SetScript("OnReceiveDrag", function(self) ns.SafeCall("view input", DropItem, self) end)
	eb:SetScript("OnEnter", function(self)
		if not (self.line and self.line.tooltip) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		ns.SafeCall("view tooltip", self.line.tooltip, GameTooltip)
		GameTooltip:Show()
	end)
	eb:SetScript("OnLeave", function() GameTooltip:Hide() end)
	content.input = eb
	return eb
end

-- The box on `r`, the row of its line: after the line's text, to the row's end. Its text is set
-- only when it is not the line's already (what was typed stays, the cursor where it is).
local function PlaceInput(content, r)
	local eb = content.input
	if not r then
		if eb then
			eb.line = nil
			eb:Hide()
		end
		return
	end
	eb = InputBox(content)
	eb.line = r.line
	eb:ClearAllPoints()
	eb:SetPoint("LEFT", r.left, "RIGHT", 12, 0)
	eb:SetPoint("RIGHT", r, "RIGHT", -8, 0)
	eb:SetFrameLevel(r:GetFrameLevel() + 2)
	-- A search keeps 40 letters; a line may ask for more (1.2: a crafting request's details).
	eb:SetMaxLetters(math.max(1, math.min(255, math.floor(tonumber(r.line.input.maxLetters) or 40))))
	local text = tostring(r.line.input.text or "")
	if (eb:GetText() or "") ~= text then eb:SetText(text) end
	eb.clear:SetShown(text ~= "")
	eb:Show()
end

-- A row's two texts (line.text, line.right): the left one's words (a name, a game, a heading) keep
-- their room, and a right text too long for what is left is cut ("...") there. Before test33 the
-- right text was as wide as its words whatever they were, and the left one got the rest: the
-- Games tab's Arena and Wallet rows, their descriptions longer than the row, showed "." and ".."
-- where their icon and name are. A right text up to a third of the row keeps its words whole, as
-- before: a long name still gives way to a short count.
-- (1.2.4) A line with `rightWide` keeps its right text whole up to half the row: the Realm's guilds,
-- whose right text is their Lord's online or offline and their average level after it, a long
-- guild name and Lord giving way to both.
local RIGHT_INSET, RIGHT_GAP = 2, 6
local function FitRight(r, width, leftX, share)
	local rw = math.ceil(StringWidth(r.right))
	if rw == 0 then return end
	local room, lw = width - leftX - RIGHT_GAP - RIGHT_INSET, math.ceil(StringWidth(r.left))
	if lw + rw <= room then return end
	local keep = math.max(room - lw, math.min(rw, math.floor(room / (share or 3))))
	r.right:SetPoint("LEFT", r, "RIGHT", -RIGHT_INSET - keep, 0)
end

-- An items row's grid (line.items), for its buttons of `own` px in a list `width` wide: a slot's
-- cell, the step from one slot to the next, how many a row holds, the room between two and where
-- the first sits. As ever: the buttons' size, ITEM_GAP after each, from 4 px in. 1.2.4, line.gap
-- (with line.slot, a cell's size, and line.left, where the first cell starts): cells that many px
-- apart both ways, each button in the middle of its cell (the game's, 37, or ours, 30), "My
-- profile"'s Icons laid out for the room its window gives (ProfileEdit.IconGrid).
local function ItemGrid(line, own, width)
	local gap = tonumber(line.gap)
	local slot = gap and tonumber(line.slot) or own
	local step = slot + (gap or ITEM_GAP)
	local columns = line.columns or math.max(1, math.floor((width - 8) / step))
	return slot, step, columns, gap, tonumber(line.left) or 4
end
-- Its height: 2 px above its first row of slots, 2 below its last (the gap after it too, without line.gap).
local function GridHeight(rows, slot, step, gap)
	if gap then return rows * slot + (rows - 1) * gap + 4 end
	return rows * step + 4
end

-- A small meter beneath an ordinary row's numeric label. Own textures only; if a client lacks
-- color textures the existing white texture fallback is used, and the numeric label remains.
function Views.DrawMeter(r, meter, width, left)
	if type(meter) ~= "table" then if r.meterBack then r.meterBack:Hide(); r.meterFill:Hide() end return end
	if not r.meterBack then
		r.meterBack, r.meterFill = r:CreateTexture(nil, "BACKGROUND"), r:CreateTexture(nil, "ARTWORK")
		for _, texture in ipairs({ r.meterBack, r.meterFill }) do
			if texture.SetColorTexture then texture:SetColorTexture(1, 1, 1, 1) else texture:SetTexture("Interface\\Buttons\\WHITE8X8") end
		end
		r.meterBack:SetVertexColor(0.2, 0.2, 0.2, 0.7); r.meterFill:SetVertexColor(0.8, 0.62, 0.18, 0.9)
	end
	local value, total = tonumber(meter.value), tonumber(meter.total)
	local ratio = value and total and value == value and total == total and total > 0 and math.max(0, math.min(1, value / total)) or 0
	local size = math.max(1, width - left - RIGHT_INSET)
	for _, texture in ipairs({ r.meterBack, r.meterFill }) do
		texture:ClearAllPoints(); texture:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", left, 2); texture:SetHeight(4)
	end
	r.meterBack:SetWidth(size); r.meterBack:Show()
	r.meterFill:SetWidth(math.max(0.01, size * ratio)); r.meterFill:SetShown(ratio > 0)
end

-- CR-02 / KH-08 (the Census's own page, CensusStats.lua): a row that is a small chart of one
-- series (line.graph), drawn with plain textures only. graph = { n, values = { [i] = number or nil },
-- min, max (its scale), color = { r, g, b }, top, bottom (the scale's ends, written on its left),
-- left, right (under its first slot and its last), tips = { [i] = function(tt) }, tip = function(tt) }.
-- One slot per value across the row: a step line at its value with a faint fill under it, the last
-- slot (now) brighter, a slot with no value a dot on the baseline; each slot answers the mouse with
-- its own tooltip, the scale on its left with graph.tip (the whole series). The row itself takes no
-- mouse (its highlight would light the whole chart). The numbers stay in the text's own white and
-- grey, the series' colour on its marks alone; the grid lines are recessive.
Views.GRAPH_H, Views.GRAPH_GUTTER, Views.GRAPH_AXIS_H = 64, 46, 12
local function Paint(t, r, g, b, a)
	if t.SetColorTexture then t:SetColorTexture(1, 1, 1, 1) else t:SetTexture("Interface\\Buttons\\WHITE8X8") end
	t:SetVertexColor(r, g, b, a)
end
local function GraphLabel(holder, justify)
	local fs = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetJustifyH(justify)
	fs:SetWordWrap(false)
	fs:SetTextColor(0.62, 0.62, 0.62)
	return fs
end
-- A part of the chart that shows its own tooltip (b.tip), lit faintly under the mouse (`lit`).
local function TipButton(holder, lit)
	local b = CreateFrame("Button", nil, holder)
	if lit then
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		Paint(hl, 1, 1, 1, 0.08)
	end
	b:SetScript("OnEnter", function(self)
		local tip = self.tip
		if type(tip) ~= "function" then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		ns.SafeCall("graph tooltip", tip, GameTooltip)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end
local function GraphSlot(holder, k)
	local s = {}
	s.fill, s.cap, s.rise = holder:CreateTexture(nil, "BORDER"), holder:CreateTexture(nil, "ARTWORK"), holder:CreateTexture(nil, "ARTWORK")
	s.hit = TipButton(holder, true)
	holder.slots[k] = s
	return s
end
-- Its row's height: the plot, the labels under it and 4 px above.
function Views.GraphHeight(graph) return (tonumber(graph and graph.height) or Views.GRAPH_H) + Views.GRAPH_AXIS_H + 4 end
function Views.DrawGraph(r, graph, width)
	local holder = r.graph
	if type(graph) ~= "table" then
		if holder then holder:Hide() end
		return nil
	end
	if not holder then
		holder = CreateFrame("Frame", nil, r)
		holder:SetAllPoints(r)
		holder.grid = {}
		for k = 1, 3 do holder.grid[k] = holder:CreateTexture(nil, "BACKGROUND") end
		holder.top, holder.bottom = GraphLabel(holder, "RIGHT"), GraphLabel(holder, "RIGHT")
		holder.left, holder.right = GraphLabel(holder, "LEFT"), GraphLabel(holder, "RIGHT")
		holder.slots = {}
		holder.scale = TipButton(holder, false)
		r.graph = holder
	end
	holder:SetFrameLevel((r:GetFrameLevel() or 1) + 1)
	local plotH, axis, gutter = tonumber(graph.height) or Views.GRAPH_H, Views.GRAPH_AXIS_H, Views.GRAPH_GUTTER
	local x0 = gutter
	local plotW = math.max(10, width - x0 - RIGHT_INSET - 2)
	local base = axis -- the baseline's height from the row's bottom
	-- The grid: the scale's top, its middle and the baseline, faint.
	for k, at in ipairs({ plotH, plotH / 2, 0 }) do
		local t = holder.grid[k]
		Paint(t, 1, 1, 1, k == 3 and 0.22 or 0.07)
		t:ClearAllPoints()
		t:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", x0, base + at)
		t:SetSize(plotW, 1)
		t:Show()
	end
	holder.top:ClearAllPoints(); holder.top:SetPoint("RIGHT", holder, "BOTTOMLEFT", x0 - 4, base + plotH - 3)
	holder.bottom:ClearAllPoints(); holder.bottom:SetPoint("RIGHT", holder, "BOTTOMLEFT", x0 - 4, base + 4)
	holder.top:SetWidth(x0 - 4); holder.bottom:SetWidth(x0 - 4)
	holder.left:ClearAllPoints(); holder.left:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", x0, 0)
	holder.right:ClearAllPoints(); holder.right:SetPoint("BOTTOMRIGHT", holder, "BOTTOMLEFT", x0 + plotW, 0)
	holder.top:SetText(graph.top or ""); holder.bottom:SetText(graph.bottom or "")
	holder.left:SetText(graph.left or ""); holder.right:SetText(graph.right or "")
	holder.scale:ClearAllPoints()
	holder.scale:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, base)
	holder.scale:SetSize(x0 - 2, plotH)
	holder.scale.tip = type(graph.tip) == "function" and graph.tip or nil
	holder.scale:EnableMouse(holder.scale.tip ~= nil)
	local n = math.max(1, math.floor(tonumber(graph.n) or #(graph.values or {})))
	local lo, hi = tonumber(graph.min) or 0, tonumber(graph.max) or 1
	if hi <= lo then hi = lo + 1 end
	local color = type(graph.color) == "table" and graph.color or { 1, 0.82, 0 }
	local cr, cg, cb = tonumber(color[1]) or 1, tonumber(color[2]) or 1, tonumber(color[3]) or 1
	local slotW = plotW / n
	local function Y(v)
		local y = (v - lo) / (hi - lo) * plotH
		return math.max(0, math.min(plotH, y))
	end
	local before
	for k = 1, n do
		local s = holder.slots[k] or GraphSlot(holder, k)
		local v = graph.values and tonumber(graph.values[k]) or nil
		if v ~= v then v = nil end
		local x = x0 + (k - 1) * slotW
		local w = math.max(1, math.floor(x + slotW + 0.5) - math.floor(x + 0.5))
		local left = math.floor(x + 0.5)
		local latest = k == n
		for _, t in ipairs({ s.fill, s.cap, s.rise }) do t:ClearAllPoints() end
		if v then
			local y = Y(v)
			Paint(s.fill, cr, cg, cb, latest and 0.32 or 0.16)
			s.fill:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", left, base)
			s.fill:SetSize(w, math.max(1, y))
			s.fill:Show()
			Paint(s.cap, latest and math.min(1, cr + 0.2) or cr, latest and math.min(1, cg + 0.2) or cg, latest and math.min(1, cb + 0.2) or cb, latest and 1 or 0.85)
			s.cap:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", left, base + math.max(0, y - 1))
			s.cap:SetSize(w, 2)
			s.cap:Show()
			-- The step from the slot before, where both have a value.
			if before then
				local y0 = Y(before)
				local low, high = math.min(y0, y), math.max(y0, y)
				Paint(s.rise, cr, cg, cb, 0.85)
				s.rise:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", left - 1, base + math.max(0, low - 1))
				s.rise:SetSize(2, math.max(2, high - low + 2))
				s.rise:SetShown(high - low >= 1)
			else
				s.rise:Hide()
			end
		else
			-- No value: a dot on the baseline, so the slot still shows where it is.
			Paint(s.cap, 0.62, 0.62, 0.62, 0.6)
			s.cap:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", left + math.floor((w - 2) / 2), base)
			s.cap:SetSize(2, 2)
			s.cap:Show()
			s.fill:Hide(); s.rise:Hide()
		end
		before = v
		s.hit:ClearAllPoints()
		s.hit:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", left, base)
		s.hit:SetSize(w, plotH)
		s.hit.tip = type(graph.tips) == "table" and graph.tips[k] or nil
		s.hit:EnableMouse(s.hit.tip ~= nil)
		s.hit:Show()
	end
	for k = n + 1, #holder.slots do
		local s = holder.slots[k]
		s.fill:Hide(); s.cap:Hide(); s.rise:Hide(); s.hit:Hide()
	end
	holder:Show()
	return Views.GraphHeight(graph)
end

function Views.Render(content, lines, layout)
	local width = content:GetWidth()
	local hd = content.style == "hd"
	local rowH = hd and ROW_H_HD or ROW_H
	local y = -2
	local inputRow
	for i, line in ipairs(lines) do
		y = y - (line.spaceBefore or 0)
		local r = Row(content, i)
		r.line = line
		r.top = -y -- how far down the list the row starts (UI.lua keeps the list's place)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
		r:SetWidth(width)
		local height = rowH
		if line.primary then
			r.left:Hide()
			r.right:Hide()
			for c = 1, #r.cols do r.cols[c]:Hide() end
			if not r.primary then
				r.primary = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
				r.primary:SetPoint("CENTER")
				r.primary:SetScript("OnClick", function()
					if r.line and r.line.onClick then ns.SafeCall("primary action", r.line.onClick) end
				end)
			end
			r.primary:SetSize(math.max(1, math.min(width - 12, 220)), 26)
			r.primary:SetText(line.text or "")
			r.primary:SetEnabled(line.onClick ~= nil)
			r.primary:Show()
			height = 32
		elseif line.items then
			-- Items in a grid. line.slots and line.columns: a bank tab as the game draws it (every
			-- slot, empty ones too, items where they sit: it.s); without them, the items one after
			-- another, as many per row as fit. The row grows to hold them all.
			r.left:Hide()
			r.right:Hide()
			for c = 1, #r.cols do r.cols[c]:Hide() end
			if not (r.items and r.items[1]) then ItemButton(r, 1) end
			local own = r.itemSize or ITEM
			local slot, step, columns, gap, left = ItemGrid(line, own, width)
			local inset = math.floor((slot - own) / 2)
			local slots = line.slots or #line.items
			local bySlot = {}
			for k, it in ipairs(line.items) do
				local s = line.slots and tonumber(it.s) or k
				if s and s >= 1 and s <= slots then bySlot[s] = it end
			end
			for k = 1, slots do
				local b = r.items[k] or ItemButton(r, k)
				SetSlot(b, bySlot[k])
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", left + inset + ((k - 1) % columns) * step, -2 - inset - math.floor((k - 1) / columns) * step)
				b:Show()
			end
			for k = slots + 1, #r.items do r.items[k]:Hide() end
			height = GridHeight(math.ceil(math.max(1, slots) / columns), slot, step, gap)
		elseif line.filters then
			r.left:Hide()
			r.right:Hide()
			for c = 1, #r.cols do r.cols[c]:Hide() end
			height = Views.DrawFilters(r, line.filters, width)
		elseif line.nav then
			r.left:Hide()
			r.right:Hide()
			for c = 1, #r.cols do r.cols[c]:Hide() end
			height = Views.DrawNav(r, line.nav, width)
		elseif line.graph then
			r.left:Hide()
			r.right:Hide()
			for c = 1, #r.cols do r.cols[c]:Hide() end
			height = Views.DrawGraph(r, line.graph, width) or height
		elseif line.panel then
			-- 1.4.0: a host-owned frame in the row (the Board's Your group, Groups.DrawPanel): its
			-- function anchors it here and gives its height and the frame.
			r.left:Hide()
			r.right:Hide()
			for c = 1, #r.cols do r.cols[c]:Hide() end
			local ok, h, frame = pcall(line.panel, r, width) -- gp:board-panel
			height = ok and tonumber(h) or 0
			r.panelFrame = ok and frame or nil
		elseif line.cols then
			r.left:Hide()
			r.right:Hide()
			Views.LayoutColumns(r.cols, layout, width - 4, 4)
			for c = 1, #r.cols do r.cols[c]:SetText(line.cols[c] or "") end
			local a = line.dim and 0.45 or 1
			for c = 1, #r.cols do r.cols[c]:SetAlpha(a) end
		else
			for c = 1, #r.cols do r.cols[c]:Hide() end
			r.left:Show()
			r.right:Show()
			-- line.font: a font object by name (the Throne's dark ink on parchment), if the client has it.
			local font = line.font and _G[line.font] and line.font or nil -- gp:lookups
			r.left:SetFontObject(font or (line.header and "GameFontNormal" or (line.color or "GameFontHighlightSmall")))
			r.right:SetFontObject(font or "GameFontHighlightSmall")
			local leftX = 4 + (line.indent or 0) * 12
			r.left:ClearAllPoints()
			if r.center ~= line.center then
				r.left:SetJustifyH(line.center and "CENTER" or "LEFT")
				r.center = line.center
			end
			r.left:SetPoint("LEFT", leftX, line.meter and 4 or 0)
			r.left:SetText(line.text or "")
			r.right:SetText(line.right or "")
			r.right:ClearAllPoints()
			r.right:SetPoint("RIGHT", -RIGHT_INSET, line.meter and 4 or 0)
			-- A text box's line: its text as wide as it is, the box after it (PlaceInput).
			if line.center then
				r.left:SetPoint("RIGHT", r, "RIGHT", -leftX, 0)
			elseif line.input and not inputRow then
				inputRow, height = r, ROW_H_INPUT
			else
				r.left:SetPoint("RIGHT", r.right, "LEFT", -RIGHT_GAP, 0)
				FitRight(r, width, leftX, line.rightWide and 2 or 3)
			end
			if line.meter then height = height + 8 end
		end
		Views.DrawMeter(r, not line.items and not line.filters and not line.nav and not line.cols and not line.graph and line.meter or nil, width, 4 + (line.indent or 0) * 12)
		if not line.items then for k = 1, #(r.items or {}) do r.items[k]:Hide() end end
		if not line.primary and r.primary then r.primary:Hide() end
		if not line.nav then for k = 1, #(r.nav or {}) do r.nav[k]:Hide() end end
		if not line.filters then for k = 1, #(r.filters or {}) do r.filters[k]:Hide() end end
		if not line.graph and r.graph then r.graph:Hide() end
		-- (A panel's frame this row hosted before, now another line's: hidden, unless another row took it.)
		if not line.panel and r.panelFrame then
			if r.panelFrame:GetParent() == r then r.panelFrame:Hide() end
			r.panelFrame = nil
		end
		r:SetHeight(height)
		r:EnableMouse(not line.primary and (line.onClick ~= nil or line.tooltip ~= nil))
		if hd then
			r.stripe:SetShown(line.cols ~= nil or (line.onClick ~= nil and not line.center and not line.primary))
			if line.key and line.key == content.selectedKey then r:LockHighlight() else r:UnlockHighlight() end
		end
		r:Show()
		y = y - (line.header and height + 4 or height)
		if line.gapAfter then y = y - 6 end
	end
	for i = #lines + 1, #(content.rows or {}) do content.rows[i]:Hide() end
	PlaceInput(content, inputRow)
	content.lineCount = #lines
	content:SetHeight(-y + 8)
end

-- 1.2.4: how tall Render makes `lines` in a list `width` wide (hd: the HD look's rows), its room
-- above the first row and below the last included, measured without drawing: a page that fits its
-- window ("My profile"'s Icons, ProfileEdit.lua) asks it. An items row is measured as the game's
-- buttons (ITEM_GAME) unless line.gap gives its cells (line.slot). nil for a row of filters (its
-- buttons' height is theirs) or a panel (its frame's, 1.4.0).
function Views.LinesHeight(lines, hd, width)
	local rowH = hd and ROW_H_HD or ROW_H
	local y, input = 2, false
	for _, line in ipairs(lines or {}) do
		local height
		if line.primary then
			height = 32
		elseif line.items then
			local slot, step, columns, gap = ItemGrid(line, ITEM_GAME, tonumber(width) or 0)
			height = GridHeight(math.ceil(math.max(1, line.slots or #line.items) / columns), slot, step, gap)
		elseif line.filters or line.panel then
			return nil
		elseif line.nav then
			height = ROW_H_NAV
		elseif line.graph then
			height = Views.GraphHeight(line.graph)
		elseif line.input and not line.cols and not input then
			input, height = true, ROW_H_INPUT
		else
			height = rowH
		end
		y = y + (line.spaceBefore or 0) + height + (line.header and 4 or 0) + (line.gapAfter and 6 or 0)
	end
	return y + 8
end

-- The last row clicked in `content` ({ index, top, lines, t }: where it started, how many lines
-- the list had, when), once: taken by the redraw that follows (UI.lua).
function Views.TakeClick(content)
	local click = content.click
	content.click = nil
	return click
end

-- The id of a guild's row in the Realm tree (line.id): a tab opened on it shows it (UI.SelectTab).
function Views.GuildId(name) return "guild:" .. tostring(name) end

---------------------------------------------------------------------------
-- The tabs' searches (1.0.0): the Workshop's box (line.input) on top of the Census, the Realm,
-- the Tabards and the Treasury. What is typed stays with its tab for the session, never saved,
-- and changes only what the list shows: the copy for Discord, what is sent and what is kept are
-- the same whatever it holds. Nothing typed (or spaces only): the list as ever.
---------------------------------------------------------------------------

local filters = {} -- [tab] = the text in its box, as typed
local realmGroupOpen -- the Realm projection groups, declared here so the test reset below can clear them
local folded = {}  -- [guild name or COUNCIL_ROW] = true: opened by the search, closed by a click (until the text changes)
-- The Realm's search opens the guilds where it finds a Lord, a Captain or a member a page of
-- rows at a time (a first letter is in someone of nearly every guild: all of them opened would
-- be thousands of rows, as Expand all), the rest on a click; a new text, its first page.
Views.SEARCH_ROWS = 200
local searchRows = Views.SEARCH_ROWS

local function Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- A name as the search reads it (ns.Searchable) as its row shows it (Plain), and a /who name as
-- its row shows it (Views.MembersOf), kept: the Realm's search reads every Lord, Captain and
-- player seen at each letter typed and at each redraw, and a name reads the same each time.
-- Emptied past SEARCH_NAMES_KEPT, a long session's worth.
Views.SEARCH_NAMES_KEPT = 20000
local searchNames, seenNames, lookNames, namesKept = {}, {}, {}, 0
local function Kept()
	namesKept = namesKept + 1
	if namesKept > Views.SEARCH_NAMES_KEPT then
		wipe(searchNames)
		wipe(seenNames)
		wipe(lookNames)
		namesKept = 1
	end
end
local function SearchName(s)
	local k = searchNames[s]
	if not k then
		Kept()
		k = ns.Searchable(Plain(s))
		searchNames[s] = k
	end
	return k
end
local function SeenName(name)
	local shown = seenNames[name]
	if not shown then
		Kept()
		shown = ns.DisplayName(ns.FullName(name)) or ""
		seenNames[name] = shown
	end
	return shown
end
-- 1.2.1: the Census's search reads letters that look alike as one: l, I and 1, and 0 and O (a
-- guild's name may mix them, "OLYMPUS XIlI", and the player types what he sees). A folded text
-- (ns.Fold: I and O are i and o already) with l and 1 as i and 0 as o. CR-08 (the author's ask):
-- the Realm's search too, the same guilds of the same census, their Lords, Captains and members,
-- and the people of its classes, races and professions.
local function Lookalike(s) return (s:gsub("[l1]", "i"):gsub("0", "o")) end
-- Does `name` hold the Census's or the Realm's search `lq` (Lookalike of the query), as its row
-- shows it? Kept like SearchName.
local function LookHolds(lq, name)
	if type(name) ~= "string" or name == "" then return false end
	local k = lookNames[name]
	if not k then
		Kept()
		k = Lookalike(SearchName(name))
		lookNames[name] = k
	end
	return k:find(lq, 1, true) ~= nil
end
-- Does one of the texts hold `lq`, as ns.Holds but with look-alike letters as one?
local function CensusHolds(lq, ...)
	for i = 1, select("#", ...) do
		local s = select(i, ...)
		if type(s) == "string" and s ~= "" and Lookalike(ns.Searchable(s)):find(lq, 1, true) then return true end
	end
	return false
end

function Views.Filter(tab) return filters[tab] or "" end

-- The text a tab's list is filtered by, folded (ns.Fold), or nil when nothing is typed.
function Views.Query(tab)
	local text = Trim(filters[tab])
	if text == "" then return nil end
	return ns.Fold(text)
end

-- Typed into a tab's box: its list again, from its first page, and from its top when a search
-- starts (while the player goes on typing, the list stays where it is: UI.FilterChanged).
function Views.SetFilter(tab, text, hostTab)
	text = tostring(text or "")
	local before = filters[tab] or ""
	if text == before then return end
	filters[tab] = text ~= "" and text or nil
	if tab == "realm" then
		wipe(folded)
		searchRows = Views.SEARCH_ROWS
	end
	if tab == "treasury" and ns.Treasury and ns.Treasury.FirstPage then ns.Treasury.FirstPage() end
	if ns.UI and ns.UI.FilterChanged then ns.UI.FilterChanged(hostTab or tab, Trim(before) == "" and Trim(text) ~= "") end
end

-- Tests start from nothing typed.
function Views.ClearFilters()
	wipe(filters)
	wipe(folded)
	for _, groups in pairs(realmGroupOpen or {}) do wipe(groups) end
	searchRows = Views.SEARCH_ROWS
	wipe(searchNames)
	wipe(seenNames)
	wipe(lookNames)
	namesKept = 0
end

-- The box's line, on top of a tab's list; `tip`: what it finds there (L.SEARCH_TIP_...).
local function SearchLine(tab, tip, filterKey)
	local stored = filterKey or tab
	return {
		pageSearch = true, text = L.SEARCH, input = { text = Views.Filter(stored), onChange = function(text) Views.SetFilter(stored, text, tab) end },
		tooltip = function(tt)
			tt:AddLine(L.SEARCH, 1, 0.82, 0)
			tt:AddLine(L["SEARCH_TIP_" .. tip], 1, 1, 1, true)
		end,
	}
end

local function NoMatch() return { text = Grey(L.SEARCH_NO_MATCH) } end

---------------------------------------------------------------------------
-- The census's marks (1.1, Fern's #30): a row its senders disagree on (Data.Dispute: its leader
-- or officers, or its size), and, fainter, one a single sender stands behind. A game texture in
-- the row's text, so both windows and the gamepad UI show it; the tooltip says what it is.
---------------------------------------------------------------------------

Views.MARK_DISPUTED = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"
Views.MARK_SINGLE = "Interface\\Icons\\INV_Misc_QuestionMark"

-- The mark before a guild's name ("" for none), and what Data.Dispute found.
function Views.DisputeMark(g)
	local d = ns.Data.Dispute(g)
	if not d then return "", nil end
	return "|T" .. (d.disputed and Views.MARK_DISPUTED or Views.MARK_SINGLE) .. ":12:12|t ", d
end

-- What the mark says, a line each (nil: no mark), for tooltips and the gates' question.
function Views.DisputeLines(d)
	if not d then return nil end
	local out = {}
	if d.split then out[#out + 1] = L.DISPUTE_SPLIT end
	if d.outvoted then out[#out + 1] = L.DISPUTE_OUTVOTED end
	if d.sizes then
		out[#out + 1] = L.DISPUTE_SIZES:format(ns.FormatNumber(d.sizes[2].n), ns.DisplayName(d.sizes[2].sender) or "?",
			ns.FormatNumber(d.sizes[1].n), ns.DisplayName(d.sizes[1].sender) or "?")
	end
	if d.single then out[#out + 1] = L.DISPUTE_SINGLE:format(ns.DisplayName(d.single) or "?") end
	return out
end

local function DisputeTooltip(tt, d)
	local lines = Views.DisputeLines(d)
	if not lines then return end
	tt:AddLine(" ")
	tt:AddLine(d.disputed and L.DISPUTE_TITLE or L.DISPUTE_SINGLE_TITLE, 1, d.disputed and 0.4 or 0.82, d.disputed and 0.2 or 0)
	for _, text in ipairs(lines) do tt:AddLine(text, 1, 1, 1, true) end
	tt:AddLine(L.DISPUTE_TIP, 0.6, 0.6, 0.6, true)
end

-- Guild verification (Verify.lua): its mark before a guild's name ("" for none), and its tooltip line.
local function VerifyModule()
	local V = ns.Verify
	return type(V) == "table" and not V.missing and type(V.Mark) == "function" and V or nil
end
local function VerifyMark(name)
	local V = VerifyModule()
	return V and V.Mark(name) or ""
end

---------------------------------------------------------------------------
-- Shared tooltips
---------------------------------------------------------------------------

local function GuildTooltip(e)
	return function(tt)
		local g = e.g
		tt:AddLine("<" .. Plain(e.name) .. ">", 0.25, 1, 0.25)
		tt:AddDoubleLine(L.COL_MEMBERS, ns.FormatNumber(g.total), 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L.COL_ONLINE, ns.FormatNumber(g.online), 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L.LORD, Plain(g.leader or "?"), 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L.VACANCIES, ns.FormatNumber(math.max(0, 1000 - (g.total or 0))), 1, 0.82, 0, 1, 1, 1)
		-- (1.2.4: to the tenth as every client has it, Data.AvgLevelText: the Census's column too.)
		local avg = ns.Data.AvgLevelText(g)
		if avg then
			tt:AddDoubleLine(L.AVG_LEVEL, avg, 1, 0.82, 0, 1, 1, 1)
			local honors = ns.Honors
			if type(honors) == "table" and type(honors.GUILD_MIN_MEMBERS) == "number" then
				tt:AddLine(L.GUILD_AVG_HONOUR_MIN:format(honors.GUILD_MIN_MEMBERS), 0.6, 0.6, 0.6, true)
			end
		end
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
		tt:AddLine(L.REPORTED_BY:format(g.reporter or "?", ns.Ago(e.observed or g.t)), 0.6, 0.6, 0.6)
		if e.observed and g.t and g.t > e.observed then
			tt:AddLine(L.CENSUS_RECEIVED_AGE:format(ns.Ago(g.t)), 0.6, 0.6, 0.6)
		end
		if not e.fresh then tt:AddLine(L.STALE, 1, 0.4, 0.4) end
		DisputeTooltip(tt, ns.Data.Dispute(g))
		local V = VerifyModule()
		if V then V.Tooltip(tt, e.name) end
		-- (Ours is live from our roster; another guild's is its last report, 1.1.2's review.)
		Why(tt, not e.fresh and "count-grey-rows" or (g.mine and "count-own-guild-live" or "count-other-guild-report"))
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
		Why(tt, "count-army-lower")
	end
end

-- The census being rebuilt after login (1.1, Data.Rebuilding): two lines on top of the Census
-- and the Realm, in place of "No reports yet", until it is. Nothing else (no /who, no popup).
local function RebuildLines(lines)
	local heard = ns.Data.Rebuilding and ns.Data.Rebuilding()
	if not heard then return false end
	local function tip(tt)
		tt:AddLine(L.REBUILDING_SUB:format(heard), 1, 0.82, 0)
		tt:AddLine(L.REBUILDING_TIP, 1, 1, 1, true)
	end
	lines[#lines + 1] = { text = Gold(L.REBUILDING:format(heard)), tooltip = tip }
	lines[#lines + 1] = { text = Grey(L.REBUILDING_WAIT), tooltip = tip, gapAfter = true }
	return true
end
Views.RebuildLines = RebuildLines

-- The Olympus channel without a realm key (1.1, Comm.IsPublic): anyone who joins it by name reads
-- what is sent there. While it is so, one quiet grey line on top of the Census, the Realm and the
-- Olympus chats for the officers, who can seal it (its tooltip says what it means and how); the
-- others see only whether guildmates are already on the sealed channel (their hellos say so), and
-- /oly status. Nothing is sent, nothing changes.
local function PublicLines(lines)
	local C = ns.Comm
	if not (C and C.IsPublic and C.IsPublic()) then return false end
	local name = C.ChannelSpec and C.ChannelSpec() or ns.CHANNEL
	local officer = ns.Roster.IsOfficer()
	local function tip(tt)
		tt:AddLine(L.PUBLIC_NET_TITLE, 1, 0.82, 0)
		tt:AddLine(L.PUBLIC_NET_TIP:format(name), 1, 1, 1, true)
		if officer then tt:AddLine(L.PUBLIC_NET_OFFICER, 0.75, 0.75, 0.75, true) end
	end
	local before = #lines
	if officer then lines[#lines + 1] = { text = Grey(L.PUBLIC_NET:format(name)), tooltip = tip } end
	local sealed = C.SealedPeers and C.SealedPeers() or 0
	if sealed > 0 then lines[#lines + 1] = { text = Grey(L.PUBLIC_NET_SPLIT:format(sealed)), tooltip = tip } end
	if #lines == before then return false end
	lines[#lines].gapAfter = true
	return true
end
Views.PublicLines = PublicLines

-- 1.2.5.1: while the quiet presence is on (Core.lua), one line on top says so, its tooltip what it
-- holds back and what still goes.
local function QuietLine(lines)
	if not (ns.QuietPresence and ns.QuietPresence()) then return false end
	lines[#lines + 1] = { text = Gold(L.QUIET_PRESENCE_LINE), gapAfter = true, tooltip = function(tt)
		tt:AddLine(L.QUIET_PRESENCE_LINE, 1, 0.82, 0, true)
		tt:AddLine(L.QUIET_PRESENCE_TIP, 1, 1, 1, true)
	end }
	return true
end
Views.QuietLine = QuietLine

-- The pinned line (1.1, Channels.Pin): on top of the Olympus chats and the Realm, for everyone.
-- Its setter, or a higher rank, takes it down with a click (after a question). Words the
-- player's block terms hide (Channels.PinWords) show after a first click, as a decree's.
local function PinLine(lines)
	local C = ns.Channels
	local p = C and C.Pin and C.Pin()
	if not p then return false end
	local who = ns.DisplayName(p.sender) or "?"
	local mayTakeDown = C.CanTakeDown and C.CanTakeDown()
	local words, veiled = C.PinWords(p)
	local onClick = mayTakeDown and function() ns.ShowDialog("OLYMPUS_PIN_DOWN") end or nil
	if veiled then
		onClick = function()
			p.revealed = true
			if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
		end
	end
	lines[#lines + 1] = {
		text = Gold(L.PIN_LABEL .. ": ") .. (veiled and Grey(L.FILTER_WORDS_HIDDEN) or ("|cffffffff" .. words .. "|r")),
		right = Grey(who),
		onClick = onClick,
		tooltip = function(tt)
			tt:AddLine(L.PIN_LABEL, 1, 0.82, 0)
			tt:AddLine(words, 1, 1, 1, true)
			tt:AddLine(L.PIN_TIP:format(who, Plain(p.guild), ns.Ago(p.setAt), math.max(1, math.ceil((p.expires - ns.Now()) / 60))), 0.7, 0.7, 0.7, true)
			if mayTakeDown and not veiled then tt:AddLine(L.PIN_DOWN_TIP, 0.25, 1, 0.25, true) end
		end,
		gapAfter = true,
	}
	return true
end
Views.PinLine = PinLine

-- How far the round of /who searches got (Who.lua), as grey lines under a list.
local function WhoStatus(lines)
	for _, text in ipairs(ns.Who.StatusLines() or {}) do lines[#lines + 1] = { text = Grey(text) } end
end

---------------------------------------------------------------------------
-- Census
---------------------------------------------------------------------------

Views.sort = { key = "members", desc = true }

-- 1.2.4: a guild's average level as its rows show it (Data.AvgLevelText: to the tenth, as every
-- client has it). The Census's cell, "-" for none (no report of it yet, an older version's); and
-- in parentheses after another number or word (the Realm: its Lord's online or offline, the
-- free slots), the number white and its words grey, all grey for an old report; nothing for none.
local function AvgCell(g) return ns.Data.AvgLevelText(g) or Grey("-") end
local function AvgTag(g, dim)
	local text = ns.Data.AvgLevelText(g)
	if not text then return "" end
	local before, after = L.AVG_LEVEL_TAG:match("^(.-)%%s(.*)$")
	if dim or not before then return "  " .. Grey(L.AVG_LEVEL_TAG:format(text)) end
	return "  " .. Grey(before) .. text .. (after ~= "" and Grey(after) or "")
end
-- (1.2.4's review: the same words where other files list guilds by a count and break its ties by
-- the average level: the Throne's inspection, the map's pins.)
Views.AvgTag = AvgTag

local SORTERS = {
	name = function(e) return e.name:lower() end,
	members = function(e) return e.g.total or 0 end,
	online = function(e) return e.g.online or 0 end,
	level = function(e) return ns.Data.AvgTenths(e.g) or 0 end, -- (1.2.4; 0: none, last whichever way)
	lord = function(e) return (e.g.leader or ""):lower() end,
}

-- A first click on a count's title, the highest first (1.2.4: the average level's too); on a name's, A to Z.
function Views.SortBy(key)
	if Views.sort.key == key then
		Views.sort.desc = not Views.sort.desc
	else
		Views.sort = { key = key, desc = key == "members" or key == "online" or key == "level" }
	end
end

-- A reported guild's row: its name, members, online and Lord; a click opens it in the Realm,
-- whose box it empties: a search left there could miss that guild and show nothing of it.
local function CensusRow(e)
	local g = e.g
	local leader = g.leader and ((g.leaderOnline and "|cff40ff40" or "|cff9d9d9d") .. Plain(g.leader) .. "|r") or Grey("?")
	return {
		cols = { Views.DisputeMark(g) .. VerifyMark(e.name) .. Plain(e.name), ns.FormatNumber(g.total), Green(ns.FormatNumber(g.online)), AvgCell(g), leader },
		dim = not e.fresh,
		tooltip = GuildTooltip(e),
		onClick = function()
			-- Opened in the Realm, and the Realm opens on it (UI.KeepPlace), whatever its box held.
			Views.SetFilter("realm", "")
			expanded[e.name] = true
			ns.UI.SelectTab("realm", Views.GuildId(e.name))
		end,
	}
end

-- A guild seen with /who that nobody reports: grey, after every reported guild, and in no
-- total (Data.Summary keeps them apart). Members, average level and Lord are unknown.
local function SeenRow(e)
	local online = ns.FormatNumber(e.online) .. (e.capped and "+" or "")
	return { cols = { Grey(e.name), Grey("?"), Grey(online), Grey("?"), Grey(L.NO_ADDON) }, tooltip = SeenTooltip(e) }
end

-- The reported guilds in the order the column titles say, fresh reports first; `sort` (1.2.4's
-- review): another order of the same kind, { key, desc } (the Realm's own, Views.realmSort).
-- A tie, whichever way the column runs: the exact <OLYMPUS> first (Data.IsStandardBearer, as in
-- the default order: the author's ask), then the higher average level (1.2.4, the author's ask: one
-- of the first tie-breaks), then the name. The average level's own column: a guild without one last
-- whichever way, a tie the standard-bearer first, then the larger guild, then the name.
local function SortedGuilds(list, sort)
	sort = sort or Views.sort
	local key, desc = sort.key, sort.desc
	local get = SORTERS[key] or SORTERS.members
	local level = key == "level"
	local guilds = {}
	for i, e in ipairs(list) do guilds[i] = e end
	table.sort(guilds, function(a, b)
		-- The default Census order is the Realm's order exactly. Explicit column choices keep
		-- behaving as labelled by their header, including an ascending Members click.
		if key == "members" and desc then return ns.Data.GuildDefaultLess(a, b) end
		if a.fresh ~= b.fresh then return a.fresh end
		local va, vb = get(a), get(b)
		if level and (va == 0) ~= (vb == 0) then return vb == 0 end
		if va ~= vb then
			if desc then return va > vb end
			return va < vb
		end
		local ba, bb = ns.Data.IsStandardBearer(a.name), ns.Data.IsStandardBearer(b.name)
		if ba ~= bb then return ba end
		if level then
			local ta, tb = a.g.total or 0, b.g.total or 0
			if ta ~= tb then return ta > tb end
		else
			local la, lb = ns.Data.AvgTenths(a.g) or 0, ns.Data.AvgTenths(b.g) or 0
			if la ~= lb then return la > lb end
		end
		return a.name < b.name
	end)
	return guilds
end

-- The guilds with room (1000 members is the game's cap), most free slots first; `min`: at least
-- that many free. Fresh reports only: an old one's size may be gone.
function Views.OpenGuilds(s, min)
	local open = {}
	for _, e in ipairs(s.guilds) do
		local free = 1000 - (e.g.total or 0)
		if e.fresh and free > 0 and free >= (min or 1) then open[#open + 1] = { name = e.name, free = free, e = e } end
	end
	-- (1.2.4: as many free, the higher average level first, then the name.)
	return ns.Data.SortGuildCounts(open, "free")
end

-- How a count moved tonight (Data.ZoneTrend): "+120" green, "-30" red, "=" grey.
local function Trend(change)
	if not change then return nil end
	if change > 0 then return Green("+" .. ns.FormatNumber(change)) end
	if change < 0 then return Red("-" .. ns.FormatNumber(-change)) end
	return Grey("=")
end
Views.Trend = Trend

-- Tonight's count on this client (Data.SampleEvening), one grey line under the list, the zones in
-- its tooltip; nil before the first sample.
local function EveningLine()
	local e = ns.Data.Evening()
	if not e or e.samples == 0 then return nil end
	return {
		text = Grey(L.EVENING_LINE:format(ns.FormatNumber(e.peak or 0), date("%H:%M", e.peakAt or e.t), ns.FormatNumber(e.online or 0),
			date("%H:%M", e.since or e.t))),
		tooltip = function(tt)
			tt:AddLine(L.EVENING_TITLE, 1, 0.82, 0)
			tt:AddLine(L.EVENING_TIP:format(date("%H:%M", e.since or e.t)), 1, 1, 1, true)
			local zones = {}
			for key, z in pairs(e.zones) do
				if (z.now or 0) > 0 or (z.first or 0) > 0 then zones[#zones + 1] = { key = key, now = z.now or 0, change = (z.now or 0) - (z.first or 0) } end
			end
			table.sort(zones, function(a, b)
				if a.now ~= b.now then return a.now > b.now end
				return a.key < b.key
			end)
			if #zones > 0 then tt:AddLine(" ") end
			for i = 1, math.min(8, #zones) do
				local z = zones[i]
				tt:AddDoubleLine(ns.Zones.NameForKey(z.key), ns.FormatNumber(z.now) .. "  " .. Trend(z.change), 0.8, 0.8, 0.8, 1, 1, 1)
			end
			Why(tt, "count-differs-from-friend")
		end,
	}
end

-- A guild's line under a search's header (a zone's, Recruiting's): opens it in the Realm.
local function GuildLink(name, right, prefix)
	return {
		indent = 1, text = (prefix or "") .. Green("<" .. Plain(name) .. ">"), right = right,
		onClick = function()
			Views.SetFilter("realm", "")
			expanded[name] = true
			ns.UI.SelectTab("realm", Views.GuildId(name))
		end,
	}
end

-- The Census's search (1.1, Fern's #16): "recruiting" (or "free 50", L.SEARCH_RECRUITING_WORDS)
-- lists every guild with room, the gates' guild first; the least free slots it asks for, or 1.
local function RecruitQuery(q)
	local word, n = q:match("^(%S+)%s*(%d*)$")
	if not word then return nil end
	for w in ns.Fold(L.SEARCH_RECRUITING_WORDS):gmatch("[^,%s]+") do
		if w == word then return math.max(1, tonumber(n) or 1) end
	end
	return nil
end

local function RecruitingLines(lines, s, min)
	local open = Views.OpenGuilds(s, min)
	lines[#lines + 1] = { header = true, text = L.RECRUITING, right = Grey(L.SEARCH_RECRUITING_COUNT:format(#open)) }
	local gates = ns.Acts and ns.Acts.Gates and ns.Acts.Gates()
	local first
	for i, o in ipairs(open) do
		if gates and o.name == gates.guild then first = i end
	end
	if first then table.insert(open, 1, table.remove(open, first)) end
	for _, o in ipairs(open) do
		lines[#lines + 1] = GuildLink(o.name, L.FREE_SLOTS:format(ns.FormatNumber(o.free)) .. AvgTag(o.e.g),
			(gates and o.name == gates.guild and CROWN or "") .. Views.DisputeMark(o.e.g))
		-- (1.2.4's review: its free slots and average level kept whole up to half the row, a long
		-- name giving way, as the Realm's guilds; a third cut the average off.)
		lines[#lines].rightWide = true
	end
	if #open == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.ALL_FULL) } end
	lines[#lines].gapAfter = true
end

-- The zones whose name holds `lq` (the search, Lookalike), most soldiers first: each with its
-- count, how it moved tonight on this client, and its guilds there. Only what reporters who share
-- their zone count (the tip).
local function ZoneLines(lines, s, lq)
	for _, z in ipairs(s.zoneList) do
		local name = ns.Zones.NameForKey(z.key)
		if LookHolds(lq, name) then
			local _, change = ns.Data.ZoneTrend(z.key)
			local e = ns.Data.Evening()
			lines[#lines + 1] = {
				header = true, text = name .. "  " .. Gold(ns.FormatNumber(z.count)),
				right = change and (Trend(change) .. " " .. Grey(L.EVENING_SINCE:format(date("%H:%M", e.since or e.t)))) or nil,
				tooltip = function(tt)
					tt:AddLine(name, 1, 0.82, 0)
					tt:AddLine(L.SEARCH_ZONE_TIP, 1, 1, 1, true)
					Why(tt, "count-map-zones")
				end,
			}
			-- (1.2.4: as many there, the higher average level first, then the name; 1.2.4's review:
			-- its average level shown after its count, so that order is seen, both kept whole up to
			-- half the row.)
			local guilds = {}
			for guild, n in pairs(s.zoneGuilds[z.key] or {}) do guilds[#guilds + 1] = { name = guild, n = n } end
			ns.Data.SortGuildCounts(guilds, "n")
			for _, g in ipairs(guilds) do
				lines[#lines + 1] = GuildLink(g.name, ns.FormatNumber(g.n) .. AvgTag(ns.Data.Guild(g.name)))
				lines[#lines].rightWide = true
			end
			lines[#lines].gapAfter = true
		end
	end
end

-- The /who round's players by guild, for the Census's search.
local function CensusSwept()
	local out = {}
	local sweep = ns.Who and ns.Who.sweep
	for _, p in ipairs(sweep and sweep.list or {}) do
		if p.guild and p.name then
			out[p.guild] = out[p.guild] or {}
			table.insert(out[p.guild], p)
		end
	end
	return out
end

-- The players of a guild the Census's search finds, its Lord aside (his match shows the row
-- alone): its Captains, its highest levels (the report's top five) and who of it was seen online
-- (our roster for our own guild, /who's round for the others). Each once, as its row shows it.
-- (lq: the search, Lookalike)
Views.CENSUS_FOUND = 5 -- players listed under a guild's row, the rest counted
local function PlayersFound(e, lq, own, swept)
	local g, out, seen = e.g, {}, {}
	local function Add(p)
		local short = p.name and ns.ShortName(p.name)
		if not short or seen[short] or not LookHolds(lq, p.name) then return end
		seen[short] = true
		out[#out + 1] = p
	end
	for _, o in ipairs(g.officers or {}) do
		Add({ name = o.name, realm = g.realm, label = L.CAPTAIN, captain = true, level = o.level, class = o.class, zone = o.zone, online = o.online, days = o.days })
	end
	for _, p in ipairs(g.top or {}) do Add({ name = p.name, realm = g.realm, level = p.level, class = p.class }) end
	if e.name == own then
		for _, m in ipairs(ns.Roster.online or {}) do Add({ name = m.name, label = m.rank, level = m.level, class = m.class, zone = m.zone, online = true }) end
	else
		for _, p in ipairs(swept[e.name] or {}) do
			Add({ name = SeenName(p.name), level = p.level, class = ns.Roster.ClassCode(p.class), zone = p.zone and ns.Zones.KeyForName(p.zone), online = true })
		end
	end
	return out
end

local function PersonLine(e, p)
	return {
		key = p.name, player = p.name, offline = p.online == false, indent = 1,
		text = (p.captain and ASSIST or "") .. ClassColored(p.name, p.class and ns.CLASS_FILES[p.class]) .. (p.label and ("  " .. Grey(Plain(p.label))) or ""),
		right = p.level and Grey(L.LEVEL_N:format(p.level)) or nil,
		onClick = function()
			ns.UI.ShowPerson({ name = p.name, realm = p.realm, class = p.class, level = p.level, zone = p.zone, guild = e.name,
				rank = p.label, online = p.online, days = p.days })
		end,
	}
end

function Views.CensusConnectionLine(s)
	local relay, comm = ns.Relay, ns.Comm
	if not relay or not relay.On() or not comm or not comm.LaneStats then return end
	local lane = comm.LaneStats()
	local relayName, confirmed = relay.Pick()
	local newest = 0
	for _, row in ipairs(s.guilds) do
		if not row.g.mine then newest = math.max(newest, row.observed or 0) end
	end
	local state = confirmed and L.CENSUS_RELAY_READY or (relayName and L.CENSUS_RELAY_WAIT or L.CENSUS_RELAY_NONE)
	local age = newest > 0 and L.CENSUS_REMOTE_AGE:format(ns.Ago(newest)) or L.CENSUS_REMOTE_NONE
	local label = L.CENSUS_CONNECTION:format(lane.lane or 0, state, age)
	if lane.mismatch and lane.dominant then
		label = label .. " · " .. L.CENSUS_LANE_MISMATCH:format(lane.dominant)
	end
	return { id = "census-connection", text = (confirmed and newest > 0 and ns.Now() - newest <= ns.Data.FRESH and not lane.mismatch) and Grey(label) or Gold(label),
		onClick = function() ns.UI.ShowCopy("/oly status", ns.StatusText(), nil, { key = "status" }) end }
end

-- `q`, the search (Views.Query): "recruiting" (every guild with room), the zones whose name holds
-- it (1.1), then the guilds whose name or Lord holds it, and those where it finds a Captain, a
-- player of the top five or one seen online (under its row), the reported ones then the ones only
-- seen (by name: nobody knows their Lord), in the same order as ever. Letters that look alike
-- read as one (Lookalike, 1.2.1).
local function CensusLines(s, q)
	local lines = {}
	if q then
		local min = RecruitQuery(q)
		if min then RecruitingLines(lines, s, min) end
		local lq = Lookalike(q)
		ZoneLines(lines, s, lq)
		local own, swept = GetGuildInfo("player"), nil
		for _, e in ipairs(SortedGuilds(s.guilds)) do
			if CensusHolds(lq, Plain(e.name), e.g.leader and Plain(e.g.leader)) then
				lines[#lines + 1] = CensusRow(e)
			else
				swept = swept or CensusSwept()
				local found = PlayersFound(e, lq, own, swept)
				if #found > 0 then
					lines[#lines + 1] = CensusRow(e)
					for i = 1, math.min(#found, Views.CENSUS_FOUND) do lines[#lines + 1] = PersonLine(e, found[i]) end
					if #found > Views.CENSUS_FOUND then
						lines[#lines + 1] = { indent = 1, text = Grey(L.SEARCH_MORE_FOUND:format(#found - Views.CENSUS_FOUND)) }
					end
				end
			end
		end
		for _, e in ipairs(s.seen or {}) do
			if CensusHolds(lq, Plain(e.name)) then lines[#lines + 1] = SeenRow(e) end
		end
		if #lines == 0 then lines[1] = NoMatch() end
		return lines
	end
	QuietLine(lines)
	-- Our guild's verification (Verify.lua): its guild master's "GM verification pending", or its
	-- members' notice once it is overdue; a click opens it.
	local V = VerifyModule()
	local verification, verificationAt = V and V.Lines and V.Lines() or {}, #lines + 1
	for _, l in ipairs(verification) do lines[#lines + 1] = l end
	-- Recruits asking to join our guild (1.1, Recruit.lua): an officer's Invite and Decline.
	for _, l in ipairs(ns.Recruit and ns.Recruit.RequestLines and ns.Recruit.RequestLines(false) or {}) do lines[#lines + 1] = l end
	-- Clear party-invite whispers while the King is online (1.2.5.1): local, short-lived and
	-- manually verified. Nothing interrupts the game or trusts what the whisper claimed.
	for _, l in ipairs(ns.PartyGuard and ns.PartyGuard.Lines and ns.PartyGuard.Lines() or {}) do lines[#lines + 1] = l end
	-- The King's Agenda, for the whole army (King.lua).
	local a = ns.King and ns.King.Agenda and ns.King.Agenda()
	if a then
		lines[#lines + 1] = { text = Gold(L.THRONE_AGENDA_LINE:format(a.title, math.max(0, math.ceil((a.at - ns.Now()) / 60)), a.zone)), gapAfter = true }
	end
	-- The King holds court in our zone: one click asks for an audience (Court.lua).
	local court = ns.Court and ns.Court.Line and ns.Court.Line()
	if court then lines[#lines + 1] = court end
	-- While the King is online: one click asks for an invite to his layer (Hop.lua).
	for _, hop in ipairs(ns.Hop and ns.Hop.KingLines and ns.Hop.KingLines() or {}) do lines[#lines + 1] = hop end
	local kings = #lines -- (the King's lines above: "No reports yet" counts what comes below them)
	-- Above the guilds (1.1): the channel is public (who can read it), and right after login the
	-- census being rebuilt (said instead of "No reports yet").
	PublicLines(lines)
	local rebuilding = RebuildLines(lines)
	local top = #lines
	for _, e in ipairs(SortedGuilds(s.guilds)) do lines[#lines + 1] = CensusRow(e) end
	if #lines == top and kings == 0 and not rebuilding then lines[#lines + 1] = { text = Grey(L.EMPTY) } end
	for _, e in ipairs(s.seen or {}) do lines[#lines + 1] = SeenRow(e) end
	if #(s.seen or {}) > 0 then
		lines[#lines].gapAfter = true
		lines[#lines + 1] = { text = Grey(L.SEEN_HINT) }
	end
	-- Tonight's count on this client (1.1).
	local evening = EveningLine()
	if evening then
		lines[#lines].gapAfter = true
		lines[#lines + 1] = evening
	end
	WhoStatus(lines)
	local connection = Views.CensusConnectionLine(s)
	if connection then lines[#lines + 1] = connection end
	-- The addon's author online: Report a bug reaches him directly (Workshop.lua).
	local author = ns.Workshop and ns.Workshop.AuthorOnline and ns.Workshop.AuthorOnline() and ns.Workshop.AuthorName()
	if author then
		lines[#lines].gapAfter = true
		lines[#lines + 1] = { text = Grey(L.AUTHOR_ONLINE:format(ns.DisplayName(author))) }
	end
	-- This client is behind the author's version (1.1, his presence names it): one line, here alone.
	local behind = ns.Workshop and ns.Workshop.BehindLine and ns.Workshop.BehindLine()
	if behind then
		lines[#lines].gapAfter = true
		lines[#lines + 1] = behind
	end
	-- On the King's screen (including the author's preview), his verification desk follows the
	-- guilds and status lines. Build it above first to retain the existing empty-state counting.
	if ns.KingsScreen() then
		for _ = 1, #verification do table.remove(lines, verificationAt) end
		for _, l in ipairs(verification) do lines[#lines + 1] = l end
	end
	-- Record mode on (Record.lua, the Guinness attempt's witnesses): its line first; a click opens its
	-- status. Put in last, so the lines above count as before ("No reports yet").
	local record = ns.Record and ns.Record.Line and ns.Record.Line()
	if record then table.insert(lines, 1, record) end
	local recruit = ns.Recruit
	if recruit and recruit.CanEnableWhisperRecruiting and recruit.CanEnableWhisperRecruiting() then
		local at = record and 2 or 1
		table.insert(lines, at, { id = "census-recruit-hint", text = L.RECRUIT_CENSUS_HINT, center = true })
		table.insert(lines, at + 1, { id = "census-recruit-enable", text = L.RECRUIT_CENSUS_ENABLE,
			primary = true, onClick = recruit.EnableWhisperRecruiting, gapAfter = true })
	end
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
	local UI = ns.UI
	return title, text .. "\n" .. Grey(UI and UI.StatusLine and UI.StatusLine() or "")
end

---------------------------------------------------------------------------
-- The Realm
---------------------------------------------------------------------------

-- The King's guild: the one named exactly "Olympus" (the addon's King everywhere else, the
-- Throne, the layer hop). No such guild reporting: no King line, never another guild's Lord.
local function King(guilds)
	-- (1.5.5) On Forever's live realms its master is not the King (ns.KingIsMaster): the signed King's own line.
	if not ns.KingIsMaster() then return nil end
	for _, e in ipairs(guilds) do
		if ns.IsKingGuild(e.name) and e.g.leader then return e end
	end
	return nil
end

-- The members of a guild online now, besides its Lord and Captains: our own guild from our
-- roster, any other from /who (the round, and the guild's own search when its row was
-- opened, Who.SearchGuild). Reports carry no member lists: a thousand names per guild would
-- not fit on the channel. { name, level, class (code), zone (key), rank } each, by rank then
-- level.
-- `swept` (SweptByGuild): the round's players by guild, for a search through every guild at once.
Views.MAX_MEMBERS = 25
local allMembers = {} -- [guild] = true: its whole list shown ("... and N more" clicked)
function Views.MembersOf(guild, g, swept)
	local skip = {}
	if g and g.leader then skip[ns.ShortName(g.leader)] = true end
	for _, o in ipairs(g and g.officers or {}) do if o.name then skip[ns.ShortName(o.name)] = true end end
	local out, fromWho = {}, guild ~= GetGuildInfo("player")
	if not fromWho then
		for _, m in ipairs(ns.Roster.online or {}) do
			if not skip[ns.ShortName(m.name)] then out[#out + 1] = m end
		end
		return out, false
	end
	local sweep = ns.Who and ns.Who.sweep
	local own = ns.Who and ns.Who.GuildSeen and ns.Who.GuildSeen(guild)
	local round = swept and (swept[guild] or {}) or (sweep and sweep.list) or {}
	for _, source in ipairs({ own or {}, round }) do
		for _, p in ipairs(source) do
			local short = p.name and ns.ShortName(p.name)
			if p.guild == guild and short and not skip[short] then
				skip[short] = true -- each once, the guild's own search first
				out[#out + 1] = { name = ns.DisplayName(ns.FullName(p.name)), level = p.level, class = ns.Roster.ClassCode(p.class),
					zone = p.zone and ns.Zones.KeyForName(p.zone) }
			end
		end
	end
	table.sort(out, function(a, b)
		if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
		return a.name < b.name
	end)
	return out, true
end

---------------------------------------------------------------------------
-- The Realm tab's pages: in place of its tree, the Board and the pages modules list.
---------------------------------------------------------------------------

local REALM_MODES = { "guilds", "classes", "races", "professions" }
local realmMode = "guilds"
realmGroupOpen = { classes = {}, races = {}, professions = {} }
local boardShown = false -- the Board (Board.lua, 1.1) shown instead of the Realm tree
-- Pages of the Realm tab (1.1): a module lists one in ns.RealmPages (Loot.lua's loot notes):
-- { key, Link = function() return its link line, or nil end,
-- Lines = function(q) return its lines end, tip = what its search finds (L.SEARCH_TIP_...) }.
-- A link line opens it in place of the tree; beforeBoard places that link ahead of the Board.
local pageShown -- the page shown instead of the Realm tree, or nil

-- Another tab opened: the Realm opens on its tree again next time (our guild's members page, the
-- Board's and the other pages close, 1.1).
function Views.CloseChat()
	boardShown, pageShown = false, nil
	if ns.Members and ns.Members.Hide then ns.Members.Hide() end
end

-- The Realm's four roster projections. They are session UI state only: switching one never sends
-- a word, inspects a player or changes the underlying census/crafter reports.
function Views.RealmMode() return realmMode end
function Views.SetRealmMode(mode, quiet)
	local known = false
	for _, key in ipairs(REALM_MODES) do if key == mode then known = true break end end
	if not known then return false end
	if realmMode == mode then return true end
	realmMode = mode
	Views.CloseChat()
	if not quiet and ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
	return true
end

local function RealmPage(key)
	for _, p in ipairs(ns.RealmPages or {}) do
		if p.key == key then return p end
	end
	return nil
end
function Views.PageShown() return pageShown end
function Views.PageParchment()
	local page = realmMode == "guilds" and not boardShown and pageShown and RealmPage(pageShown)
	return type(page) == "table" and page.parchment == true
end
function Views.ShowPage(key)
	pageShown = RealmPage(key) and key or nil
	if pageShown then
		boardShown = false
		if ns.Members and ns.Members.Hide then ns.Members.Hide() end
	end
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end
-- The Board (1.1): a page of the Realm tab. Opened, it asks the channel once a session for the
-- flags up now (Board.Ask). `quiet`: no redraw (the tab is opened right after).
function Views.BoardShown() return boardShown end
function Views.ShowBoard(on, quiet)
	boardShown = on and true or false
	if boardShown then
		pageShown = nil
		if ns.Members and ns.Members.Hide then ns.Members.Hide() end
		if ns.Board and ns.Board.Ask then ns.SafeCall("board ask", ns.Board.Ask) end
	end
	if not quiet and ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

---------------------------------------------------------------------------
-- The High Council in the Realm (0.9.9, Max's): under the King and the Treasurer, the
-- moderators by department with their titles (Workshop.CouncilTree), for whoever may see them
-- (ns.CouncilVisible: until launch, the councillors and the author alone).
---------------------------------------------------------------------------

local COUNCIL_ROW = {} -- its open/closed key in `expanded`: no guild's name can be a table
-- The eye that shows the councillors' names on the King's screen (a game icon, Interface\Icons).
Views.EYE_ICON = "Interface\\Icons\\INV_Misc_Eye_01"

-- What the census knows of these names (a set of short names, lower case): each guild's Lord
-- and Captains from a fresh report, then who was seen online (our roster, /who), then the Lords
-- and Captains of older reports, the first found. (An old report last: days old, it must not
-- hide someone seen online now.) Short name -> a person as the rows open them, and the set of
-- those only an old report knows.
local function Known(s, wanted)
	local out, old = {}, {}
	local function Add(guild, p, stale)
		local key = type(p.name) == "string" and ns.ShortName(p.name):lower()
		if key and wanted[key] and not out[key] then
			p.guild = guild
			out[key], old[key] = p, stale or nil
		end
	end
	local function Reports(fresh)
		for _, e in ipairs(s.guilds) do
			local g = e.g
			if e.fresh == fresh then
				if g.leader then
					Add(e.name, { name = g.leader, realm = g.realm, class = g.leaderClass, level = g.leaderLevel, zone = g.leaderZone,
						rank = L.LORD, online = g.leaderOnline, days = g.leaderDays }, not fresh)
				end
				for _, o in ipairs(g.officers or {}) do
					Add(e.name, { name = o.name, realm = g.realm, class = o.class, level = o.level, zone = o.zone, rank = L.CAPTAIN,
						online = o.online, days = o.days }, not fresh)
				end
			end
		end
	end
	Reports(true)
	local mine = GetGuildInfo("player")
	for _, m in ipairs(mine and ns.Roster.online or {}) do
		Add(mine, { name = m.name, class = m.class, level = m.level, zone = m.zone, rank = m.rank, online = true })
	end
	-- (As Views.MembersOf reads /who: the guild's own search, then the round.)
	local sweep = ns.Who and ns.Who.sweep
	for _, e in ipairs(s.guilds) do
		local own = ns.Who and ns.Who.GuildSeen and ns.Who.GuildSeen(e.name)
		for _, source in ipairs({ own or {}, sweep and sweep.list or {} }) do
			for _, p in ipairs(source) do
				if p.guild == e.name and p.name then
					Add(e.name, { name = ns.DisplayName(ns.FullName(p.name)), level = p.level, class = ns.Roster.ClassCode(p.class),
						zone = p.zone and ns.Zones.KeyForName(p.zone), online = true })
				end
			end
		end
	end
	Reports(false)
	return out, old
end

local function Council(s) return "|c" .. ns.HIGH_COUNCIL_COLOR .. s .. "|r" end

-- `q`, the Realm's search (Views.Query): only the councillors whose name as their row shows it
-- holds it (on the King's stream, the first four characters: never what is hidden), under the
-- council's header (opened for it) and their department's; how many, 0 for none (nothing drawn).
local function CouncilLines(lines, s, q)
	local loose, depts = ns.Workshop.CouncilTree()
	local n = #loose
	for _, d in ipairs(depts) do n = n + #d.members end
	if n == 0 then return 0 end
	-- The King's screen (his stream): the names hidden until he clicks the eye, and hidden again
	-- on the next click (ns.CouncilMasked, Core.lua).
	local masked = ns.CouncilMasked()
	local function Hit(m)
		if not q then return true end
		local shown = masked and ns.MaskName(Plain(m.name)):sub(1, -5) or Plain(m.name)
		return ns.Holds(q, shown)
	end
	local hits = 0
	for _, m in ipairs(loose) do if Hit(m) then hits = hits + 1 end end
	for _, d in ipairs(depts) do for _, m in ipairs(d.members) do if Hit(m) then hits = hits + 1 end end end
	if q and hits == 0 then return 0 end
	local open = expanded[COUNCIL_ROW]
	if q then open = not folded[COUNCIL_ROW] end
	lines[#lines + 1] = {
		text = (open and "[-] " or "[+] ") .. ns.HIGH_COUNCIL_MARK .. " " .. Council(L.COUNCIL_CENSUS:format(n)),
		onClick = function()
			if q then
				folded[COUNCIL_ROW] = not folded[COUNCIL_ROW] or nil
			else
				expanded[COUNCIL_ROW] = not expanded[COUNCIL_ROW] or nil
			end
			ns.UI.Refresh()
		end,
		tooltip = function(tt)
			tt:AddLine(L.COUNCIL_CENSUS:format(n), 0.69, 0.28, 0.97)
			tt:AddLine(L.COUNCIL_CENSUS_TIP, 1, 1, 1, true)
		end,
	}
	if not open then return hits end
	if ns.KingsScreen() and not q then
		local label = masked and L.COUNCIL_NAMES_SHOW or L.COUNCIL_NAMES_HIDE
		lines[#lines + 1] = {
			indent = 1,
			text = "|T" .. Views.EYE_ICON .. ":0|t " .. Gold(label),
			onClick = function()
				local show = not ns.CouncilNamesShown()
				ns.SetCouncilNamesShown(show)
				if not show and ns.UI.CloseCouncilCards then ns.UI.CloseCouncilCards() end
				ns.UI.Refresh()
			end,
			tooltip = function(tt)
				tt:AddLine(label, 1, 0.82, 0)
				tt:AddLine(L.COUNCIL_NAMES_TIP, 1, 1, 1, true)
			end,
		}
	end
	local wanted = {}
	for _, m in ipairs(loose) do wanted[m.name:lower()] = true end
	for _, d in ipairs(depts) do for _, m in ipairs(d.members) do wanted[m.name:lower()] = true end end
	local known, old = Known(s, wanted)
	-- "<mark><own icon> Name - Title": where the census knows them, when they were last on, and a
	-- click opens what it knows. Hidden (the King's stream): "<mark> Name****", the title, where
	-- they are, and no click (the card would carry the whole name).
	local function Member(m, indent)
		local p = known[m.name:lower()]
		local person = p or { name = m.name }
		lines[#lines + 1] = {
			key = not masked and person.name or nil, player = not masked and person.name or nil, offline = person.online == false,
			indent = indent,
			text = (masked and (ns.HIGH_COUNCIL_MARK .. " " .. Council(ns.MaskName(Plain(m.name))))
					or (ns.CouncilMark(m.name) .. " " .. Council(Plain(m.name))))
				.. (m.title and (" - " .. Grey(Plain(m.title))) or ""),
			right = p and Presence(p.online, p.days, old[m.name:lower()]) or nil,
			onClick = not masked and function() ns.UI.ShowPerson(person) end or nil,
		}
	end
	for _, m in ipairs(loose) do if Hit(m) then Member(m, 1) end end
	for _, d in ipairs(depts) do
		local any = not q
		for _, m in ipairs(d.members) do any = any or Hit(m) end
		if any then
			local icon = ns.CouncilIconTexture(d.icon)
			lines[#lines + 1] = { indent = 1, text = (icon and ("|T" .. icon .. ":0|t ") or "") .. Gold(Plain(d.name)) }
			for _, m in ipairs(d.members) do if Hit(m) then Member(m, 2) end end
		end
	end
	return hits
end

-- The /who round's players by guild (Views.MembersOf's `swept`), in the round's order: the
-- search looks into every guild, and the round can list thousands.
local function SweptByGuild()
	local out = {}
	local sweep = ns.Who and ns.Who.sweep
	for _, p in ipairs(sweep and sweep.list or {}) do
		if p.guild then
			out[p.guild] = out[p.guild] or {}
			table.insert(out[p.guild], p)
		end
	end
	return out
end

-- The guilds where the Realm's search `lq` (Lookalike) finds a player seen online (Views.MembersOf's
-- sources: our roster for our own guild `own`, /who's round for the others), before any member list
-- is made: [guild] = true.
local function SeenHits(lq, own)
	local hit = {}
	local sweep = ns.Who and ns.Who.sweep
	for _, p in ipairs(sweep and sweep.list or {}) do
		local guild = p.guild
		if guild and guild ~= own and not hit[guild] and p.name and LookHolds(lq, SeenName(p.name)) then hit[guild] = true end
	end
	if own then
		for _, m in ipairs(ns.Roster.online or {}) do
			if LookHolds(lq, m.name) then
				hit[own] = true
				break
			end
		end
	end
	return hit
end

-- What of a guild the Realm's search finds, its name aside: its Lord, its Captains and the
-- members seen online (our roster, /who), each by name as its row shows it. `ctx`: the search
-- (lq: Lookalike of it, own, hits: SeenHits, swept: SweptByGuild once needed). The member list
-- (Views.MembersOf makes a table for each player and sorts them) is made only for a guild where
-- someone is found and only when `rows` (the guild will show): otherwise `n` counts a member found
-- as one.
local function GuildMatches(e, ctx, rows)
	local g, lq = e.g, ctx.lq
	local found = { lord = LookHolds(lq, g.leader), officers = {}, members = {}, all = {} }
	for _, o in ipairs(g.officers or {}) do
		if LookHolds(lq, o.name) then found.officers[#found.officers + 1] = o end
	end
	local seen = ctx.hits[e.name]
	if not seen and e.name ~= ctx.own then
		for _, p in ipairs(ns.Who and ns.Who.GuildSeen and ns.Who.GuildSeen(e.name) or {}) do
			if p.guild == e.name and p.name and LookHolds(lq, SeenName(p.name)) then
				seen = true
				break
			end
		end
	end
	if seen and rows then
		ctx.swept = ctx.swept or SweptByGuild()
		local members, fromWho = Views.MembersOf(e.name, g, ctx.swept)
		for _, m in ipairs(members) do
			if LookHolds(lq, m.name) then found.members[#found.members + 1] = m end
		end
		found.all, found.fromWho = members, fromWho
	end
	found.n = (found.lord and 1 or 0) + #found.officers + (rows and #found.members or seen and 1 or 0)
	return found
end

-- (1.2.4's review) The Realm's own order of its guilds: by default the shared order (Data.Summary's,
-- the Census's own by default), else by one of the Census's columns, a count the highest first, a
-- name A to Z, as a first click on its title; chosen on its own line above its guilds, the Realm
-- having no column titles, and never by a title clicked in the Census (the Realm followed it
-- unseen). The author's ask: its guilds sorted by their average level too.
Views.realmSort = "members"
Views.REALM_ORDERS = {
	{ key = "members", label = "COL_MEMBERS" }, { key = "online", label = "COL_ONLINE" }, { key = "level", label = "AVG_LEVEL" },
	{ key = "name", label = "COL_GUILD" }, { key = "lord", label = "COL_LORD" },
}
local function RealmOrder()
	for _, o in ipairs(Views.REALM_ORDERS) do if o.key == Views.realmSort then return o end end
	return Views.REALM_ORDERS[1]
end
-- `guilds` (Data.Summary's, in the shared order) in the Realm's order.
function Views.RealmOrdered(guilds)
	local key = RealmOrder().key
	if key == "members" then return guilds end
	return SortedGuilds(guilds, { key = key, desc = key ~= "name" and key ~= "lord" })
end
local function RealmOrderLine()
	local current, options = RealmOrder(), {}
	for _, o in ipairs(Views.REALM_ORDERS) do
		local key = o.key
		options[#options + 1] = { text = L[o.label], selected = key == current.key,
			onClick = key ~= current.key and function()
				Views.realmSort = key
				ns.UI.Refresh()
			end or nil }
	end
	return { id = "realm-order", filters = { { label = L.REALM_ORDER, value = L[current.label], options = options, understated = true } } }
end

-- `q`, the search (Views.Query): the High Council's names (for whoever may see it), then each
-- guild whose name holds it, whole, and each whose Lord, Captains or members seen do, opened on
-- those alone, the guilds and their people with look-alike letters as one, as in the Census
-- (Lookalike, CR-08); "No match" for none. The chats' link stays (the Chat tab it opens has a
-- search of its own). Nothing
-- else: the King's lines, the level race, recruiting and the layers show once it is emptied.
local function RealmLines(s, q)
	if boardShown and ns.Board and not ns.Board.missing and ns.Board.Lines then return ns.Board.Lines(q) end
	local page = pageShown and RealmPage(pageShown)
	if page then return page.Lines(q) end
	-- Our guild's members page (1.1, Members.lua).
	if ns.Members and ns.Members.Shown and ns.Members.Shown() then return ns.Members.Lines(q) end
	local lines = {}
	-- A councillor's mark and own icon after their name in the rows below (0.9.9), for whoever
	-- may see the council here; none on the King's screen while the names are hidden (his
	-- stream: a whole name next to the mark would give the councillor away).
	local councilShown = ns.CouncilVisible()
	local councilTagged = councilShown and not ns.CouncilMasked()
	local function Tag(name, home)
		local full = ns.FullName(name, home)
		if not councilTagged or not ns.IsHighCouncillor(full) then return "" end
		return " " .. ns.CouncilMark(full)
	end
	local function Mark(name, home, online)
		return ns.King and ns.King.RollCallMark and ns.King.RollCallMark(ns.FullName(name, home), online) or ""
	end
	-- The pinned line on top (1.1), for everyone; the quiet presence's under it (1.2.5.1).
	if not q then PinLine(lines) QuietLine(lines) end
	-- The King holds court in our zone (Court.lua), then his layer (Hop.lua).
	local court = not q and ns.Court and ns.Court.Line and ns.Court.Line()
	if court then lines[#lines + 1] = court end
	for _, hop in ipairs(not q and ns.Hop and ns.Hop.KingLines and ns.Hop.KingLines() or {}) do lines[#lines + 1] = hop end
	-- The King (and his Hands): Summon the Lords, and who answered (King.lua). While it is
	-- fresh, each Lord and Captain in the tree carries a ready-check mark.
	for _, l in ipairs(not q and ns.King and ns.King.RollCallLines and ns.King.RollCallLines() or {}) do lines[#lines + 1] = l end
	local king = not q and King(s.guilds)
	-- (1.4.5, the dev's ask: the signed King wears the crown whatever his rank; on Forever the King
	-- guild's master is not the King.) His name from the signed list; his presence when seen now
	-- (the King guild's /who, or our own guild's), else unknown.
	local signed = not q and type(ns.KingCharacter) == "function" and ns.KingCharacter() or nil
	-- (The built-in pin, unsigned, only names the King guild's master as ever: no line of its own.)
	if signed and not king and type(ns.KING_CHARACTER) == "table" and signed == ns.KING_CHARACTER[ns.faction or "Alliance"] then signed = nil end
	-- (1.5.4) /who first, as before; else his own word heard, a fresh report naming him its leader or
	-- a Captain, or our roster (Hop.SignedKingPresence). Nothing known: no word at all, never "offline
	-- today" (it showed for the whole army while he played: the dev's report, 2026-11-08).
	local function SignedPresence()
		local seen = (king and Views.SeenNow(king.name, signed)) or Views.SeenNow(GetGuildInfo("player") or "", signed)
		if seen then return true, 0, false end
		local H = ns.Hop
		if H and H.SignedKingPresence then return H.SignedKingPresence() end
		return nil, nil, false
	end
	local function SignedRight(on, days, dim, at)
		if on == nil and at == nil then return nil end
		return Presence(on, days, dim, at)
	end
	if signed and not king then
		lines[#lines + 1] = { header = true, text = CROWN .. L.KING .. ": " .. Gold(Plain(signed)), right = SignedRight(SignedPresence()) }
	end
	if king then
		local name, on, days, dim, at = king.g.leader, Views.PresenceNow(king, king.g.leader, king.g.leaderOnline, king.g.leaderDays)
		local right
		if signed and ns.ShortName(king.g.leader or "") ~= signed then
			name = signed; on, days, dim, at = SignedPresence()
			right = SignedRight(on, days, dim, at)
		else
			right = Presence(on, days, dim, at)
		end
		lines[#lines + 1] = {
			header = true,
			text = CROWN .. L.KING .. ": " .. Gold(Plain(name or "?")),
			right = right,
			tooltip = GuildTooltip(king),
		}
		-- The Treasurer of Olympus, under the King: when that guild's report has him (the
		-- Horde's <Olympus> and other realms' have no Treasurer of theirs).
		local t
		for _, o in ipairs(king.name:lower() == "olympus" and king.g.officers or {}) do -- (the Treasurer: <Olympus>, the Alliance's)
			if ns.IsTreasurer(o.name, king.name) then t = o end
		end
		if t then
			local on, days, dim, at = Views.PresenceNow(king, t.name, t.online, t.days)
			local person = { name = t.name, realm = king.g.realm, guild = king.name, class = t.class, level = t.level, zone = t.zone,
				rank = L.CAPTAIN, online = on, days = days }
			lines[#lines + 1] = {
				key = t.name, player = t.name, offline = not on,
				text = ns.COIN .. L.TREASURER .. ": " .. Gold(Plain(t.name)),
				right = Presence(on, days, dim, at),
				onClick = function() ns.UI.ShowPerson(person) end,
			}
			-- The treasury, when he shares it (Treasury.lua).
			local shared = ns.Treasury and ns.Treasury.RealmText and ns.Treasury.RealmText()
			if type(shared) == "string" then lines[#lines + 1] = { indent = 1, text = Grey(shared) } end
		end
	end
	-- 1.1: the treasury's keepers taking donations now (Treasury.lua), under the King and the Treasurer.
	for _, l in ipairs(not q and ns.Treasury and ns.Treasury.DonationLines and ns.Treasury.DonationLines() or {}) do lines[#lines + 1] = l end
	-- The High Council, under them (0.9.9).
	local found = councilShown and CouncilLines(lines, s, q) or 0
	-- Above the guilds (1.1): the channel is public (who can read it), and right
	-- after login the census being rebuilt (said instead of "No reports yet").
	local rebuilding = false
	if not q then
		local before = #lines
		PublicLines(lines)
		rebuilding = RebuildLines(lines)
		if #lines > before and lines[before] then lines[before].gapAfter = true end
	end
	-- The member's week, the Board and the Realm's other pages, one link each,
	-- close together with one gap after the last so the guilds stay in sight on the short list.
	local links, trailing = {}, {}
	for _, p in ipairs(not q and ns.RealmPages or {}) do
		local link = p.Link and p.Link()
		if link then
			local group = p.beforeBoard and links or trailing
			group[#group + 1] = link
		end
	end
	local board = not q and ns.Board and ns.Board.LinkLine and ns.Board.LinkLine()
	if board then links[#links + 1] = board end
	for _, link in ipairs(trailing) do links[#links + 1] = link end
	if #links > 0 then
		local prev = lines[#lines]
		if prev then prev.gapAfter = not prev.pageLink end
		for i, link in ipairs(links) do
			link.pageLink = true
			link.gapAfter = i == #links
			lines[#lines + 1] = link
		end
	end
	if #s.guilds == 0 and not q and not rebuilding then lines[#lines + 1] = { text = Grey(L.EMPTY) } end
	-- A guild's header and, opened, its rows. `only`: what the search found in it (GuildMatches),
	-- its rows alone under the headers they belong to; nil: all of them. `folds`: its click
	-- closes and opens what the search opened, instead of the guild itself.
	local function Guild(e, open, only, folds)
		local g = e.g
		local lordOn, lordDays, lordDim, lordAt = Views.PresenceNow(e, g.leader, g.leaderOnline, g.leaderDays)
		lines[#lines + 1] = {
			id = Views.GuildId(e.name),
			text = (open and "[-] " or "[+] ") .. Views.DisputeMark(g) .. Green("<" .. Plain(e.name) .. ">") .. " " .. Plain(g.leader or "?"),
			-- (1.2.4, the author's ask: its average level too, in parentheses after its Lord's online
			-- or offline, both kept whole up to half the row.)
			right = Presence(lordOn, lordDays, lordDim, lordAt) .. AvgTag(g, not e.fresh),
			rightWide = true,
			onClick = function()
				if folds then
					folded[e.name] = not folded[e.name] or nil
					return ns.UI.Refresh()
				end
				expanded[e.name] = not expanded[e.name] or nil
				-- Opened: a /who for that guild alone lists who of it is online (a click, so the
				-- game allows it). Our own guild is in our roster already.
				if expanded[e.name] and e.name ~= GetGuildInfo("player") then ns.SafeCall("guild who", ns.Who.SearchGuild, e.name) end
				ns.UI.Refresh()
			end,
			tooltip = GuildTooltip(e),
			color = e.fresh and "GameFontHighlightSmall" or "GameFontDisableSmall",
		}
		if not open then return end
		if g.leader and (not only or only.lord) then
			local lord = { name = g.leader, realm = g.realm, class = g.leaderClass, level = g.leaderLevel, zone = g.leaderZone,
				guild = e.name, rank = L.LORD, online = lordOn, days = lordDays }
			lines[#lines + 1] = {
				key = g.leader, player = g.leader, offline = not lordOn,
				indent = 1, text = Mark(g.leader, g.realm, lordOn) .. CROWN .. Gold(L.LORD) .. "  " .. ClassColored(g.leader, lord.class and ns.CLASS_FILES[lord.class])
					.. Tag(g.leader, g.realm),
				right = Presence(lordOn, lordDays, lordDim, lordAt),
				onClick = function() ns.UI.ShowPerson(lord) end,
			}
		end
		local officers = g.officers or {}
		local listed = only and only.officers or officers
		if #listed > 0 or not only then
			lines[#lines + 1] = { indent = 1, text = Gold(L.CAPTAINS:format(#officers)),
				-- (1.1.2: another guild's report names 30 Captains at most, Codec.lua.)
				tooltip = function(tt)
					local ours = e.name == GetGuildInfo("player")
					tt:AddLine(L.CAPTAINS:format(#officers), 1, 0.82, 0)
					tt:AddLine(ours and L.CAPTAINS_OWN_TIP or L.CAPTAINS_TIP, 1, 1, 1, true)
					Why(tt, ours and "count-own-guild-live" or "count-other-guild-report")
				end }
		end
		for _, o in ipairs(listed) do
			local on, days, dim, at = Views.PresenceNow(e, o.name, o.online, o.days)
			local person = { name = o.name, realm = g.realm, class = o.class, level = o.level, zone = o.zone, guild = e.name,
				rank = L.CAPTAIN, online = on, days = days }
			lines[#lines + 1] = {
				key = o.name, player = o.name, offline = not on,
				indent = 2, text = Mark(o.name, g.realm, on) .. ASSIST .. ClassColored(o.name, o.class and ns.CLASS_FILES[o.class])
					.. Tag(o.name, g.realm) .. (ns.IsTreasurer(o.name, e.name) and ("  " .. ns.COIN .. Grey(L.TREASURER)) or ""),
				right = (o.level and Grey(L.LEVEL_N:format(o.level)) .. "  " or "") .. Presence(on, days, dim, at),
				onClick = function() ns.UI.ShowPerson(person) end,
			}
		end
		if #officers == 0 and not only then lines[#lines + 1] = { indent = 2, text = Grey(L.NONE_REPORTED) } end
		-- Actual own-guild leaders only: reports from other guilds cannot manufacture
		-- squad authority or private room membership. Keep the guild's collapse/search.
		if e.name == GetGuildInfo("player") and ns.WarSquads then
			for _, line in ipairs(ns.WarSquads.Lines(q, 1, false)) do lines[#lines + 1] = line end
		end
		-- Everyone else online: our roster, or /who for other guilds.
		local members, fromWho
		if only then members, fromWho = only.all, only.fromWho else members, fromWho = Views.MembersOf(e.name, g) end
		listed = only and only.members or members
		if #listed > 0 or not only then
			lines[#lines + 1] = {
				indent = 1, text = Gold((fromWho and L.MEMBERS_SEEN or L.MEMBERS_ONLINE):format(#members)),
				tooltip = function(tt)
					tt:AddLine((fromWho and L.MEMBERS_SEEN or L.MEMBERS_ONLINE):format(#members), 1, 0.82, 0)
					tt:AddLine(fromWho and L.MEMBERS_SEEN_TIP or L.MEMBERS_ONLINE_TIP, 1, 1, 1, true)
					Why(tt, fromWho and "count-other-guild-seen-online" or "count-realm-online-now")
				end,
			}
		end
		-- (The search's members a page at a time too.)
		local shown = allMembers[e.name] and #listed or math.min(Views.MAX_MEMBERS, #listed)
		for i = 1, shown do
			local m = listed[i]
			local person = { name = m.name, class = m.class, level = m.level, zone = m.zone, guild = e.name, rank = m.rank, online = true }
			lines[#lines + 1] = {
				key = m.name, player = m.name,
				indent = 2, text = ClassColored(m.name, m.class and ns.CLASS_FILES[m.class]) .. Tag(m.name) .. (m.rank and ("  " .. Grey(m.rank)) or "")
					.. (ns.IsTreasurer(m.name, e.name) and ("  " .. ns.COIN .. Grey(L.TREASURER)) or ""),
				right = m.level and Grey(L.LEVEL_N:format(m.level)) or nil,
				onClick = function() ns.UI.ShowPerson(person) end,
			}
		end
		-- The rest on a click, and back again.
		if #listed > shown then
			lines[#lines + 1] = {
				indent = 2, text = Gold(L.MEMBERS_MORE:format(#listed - shown)),
				onClick = function() allMembers[e.name] = true; ns.UI.Refresh() end,
			}
		elseif allMembers[e.name] and #listed > Views.MAX_MEMBERS then
			lines[#lines + 1] = {
				indent = 2, text = Gold(L.MEMBERS_FEWER),
				onClick = function() allMembers[e.name] = nil; ns.UI.Refresh() end,
			}
		end
		if only then
			lines[#lines].gapAfter = true
			return
		end
		if #members == 0 then lines[#lines + 1] = { indent = 2, text = Grey(fromWho and L.MEMBERS_NONE_SEEN or L.MEMBERS_NONE) } end
		lines[#lines + 1] = { indent = 1, text = Gold(L.RANKS) }
		for i, rank in ipairs(g.ranks or {}) do
			lines[#lines + 1] = { indent = 2, text = ("%d. %s"):format(i, Plain(rank.name)), right = ns.FormatNumber(rank.count) }
		end
		if #(g.ranks or {}) == 0 then lines[#lines + 1] = { indent = 2, text = Grey(L.NONE_REPORTED) } end
		-- Our own guild's: a click lists them, by name (1.1, Members.lua).
		local own = g.mine and e.name == GetGuildInfo("player")
		lines[#lines + 1] = {
			indent = 1, gapAfter = true,
			text = own and Gold(L.INACTIVE_LINE:format(g.inactive7 or 0, g.inactive30 or 0) .. "  " .. L.MEMBERS_OPEN)
				or Grey(L.INACTIVE_LINE:format(g.inactive7 or 0, g.inactive30 or 0)),
			onClick = own and function() ns.Members.Show(7) end or nil,
			tooltip = own and function(tt)
				tt:AddLine(L.MEMBERS_TITLE, 1, 0.82, 0)
				tt:AddLine(L.MEMBERS_OPEN_TIP, 1, 1, 1, true)
			end or nil,
		}
	end
	-- (The guilds opened for a Lord, Captain or member found: `searchRows` of their rows, the
	-- guilds past them counted in `more`, shown on a click.)
	local ctx, rows, more
	if q then
		local own, lq = GetGuildInfo("player"), Lookalike(q)
		ctx, rows, more = { lq = lq, own = own, hits = SeenHits(lq, own) }, 0, 0
	end
	-- (1.2.4's review: in the Realm's own order, chosen on its line above its guilds; by default
	-- Data.Summary's own, the shared order, as before. A search's guilds in it too.)
	if not q and #s.guilds > 1 then lines[#lines + 1] = RealmOrderLine() end
	for _, e in ipairs(Views.RealmOrdered(s.guilds)) do
		if not q or LookHolds(ctx.lq, e.name) then
			-- (Found by its name: the guild as ever, opened or not.)
			if q then found = found + 1 end
			Guild(e, expanded[e.name])
		else
			local room = rows < searchRows
			local only = GuildMatches(e, ctx, room)
			if e.name == GetGuildInfo("player") and ns.WarSquads and #ns.WarSquads.Lines(q, 1, false) > 0 then only.n = only.n + 1 end
			if only.n > 0 then
				found = found + only.n
				if room then
					local before = #lines
					Guild(e, not folded[e.name], only, true)
					rows = rows + #lines - before
				else
					more = more + 1
				end
			end
		end
	end
	if q then
		if more > 0 then
			lines[#lines + 1] = {
				text = Gold(L.SEARCH_MORE_GUILDS:format(more)),
				onClick = function()
					searchRows = searchRows + Views.SEARCH_ROWS
					ns.UI.Refresh()
				end,
			}
		end
		if found == 0 then lines[#lines + 1] = NoMatch() end
		return lines
	end

	local racers, covered, expected = {}, 0, 0
	for _, e in ipairs(s.guilds) do
		if e.fresh and (e.g.total or 0) > 0 then
			expected = expected + 1
			if e.topLevels then
				covered = covered + 1
				for _, p in ipairs(e.topLevels) do
					racers[#racers + 1] = { name = p.name, realm = e.topRealm, level = p.level, class = p.class, guild = e.name }
				end
			end
		end
	end
	table.sort(racers, function(a, b)
		if a.level ~= b.level then return a.level > b.level end
		return a.name < b.name
	end)
	lines[#lines + 1] = { header = true, text = L.LEVEL_RACE }
	local rules = ns.RankingRules and ns.RankingRules.Link("realm-level", function() ns.RankingRules.OpenRealm("realm-level") end)
	if rules then lines[#lines + 1] = rules end
	if covered < expected then
		lines[#lines + 1] = { text = Grey(L.LEVEL_RACE_REPORTS_PENDING:format(covered, expected)), tooltip = function(tt)
			tt:AddLine(L.LEVEL_RACE_REPORTS_TIP, 0.8, 0.8, 0.8, true)
		end }
	elseif #racers == 0 then
		lines[#lines + 1] = { text = Grey(L.NONE_REPORTED) }
	end
	-- The top 100, shown 25 at a time (0.9.7): the window stays light.
	local shownRacers = math.min(#racers, Views.RACE_MAX, Views.raceShown)
	for i = 1, shownRacers do
		local p = racers[i]
		lines[#lines + 1] = {
			key = p.name,
			text = ("%d. %s  %s"):format(i, ClassColored(p.name, p.class and ns.CLASS_FILES[p.class]), Grey("<" .. Plain(p.guild) .. ">")),
			right = Gold(L.LEVEL_N:format(p.level)),
			onClick = function() ns.UI.ShowPerson({ name = p.name, realm = p.realm, class = p.class, level = p.level, guild = p.guild }) end,
		}
	end

	local total = math.min(#racers, Views.RACE_MAX)
	if total > shownRacers then
		lines[#lines + 1] = { text = Grey(L.SHOW_MORE:format(math.min(Views.RACE_PAGE, total - shownRacers), shownRacers, total)),
			onClick = function() Views.raceShown = Views.raceShown + Views.RACE_PAGE; ns.Fire("DATA_CHANGED") end }
	end

	local open = Views.OpenGuilds(s)
	-- (1.1.2's review: free slots are 1000 less the size of each guild's last report.)
	lines[#lines + 1] = { header = true, text = L.RECRUITING, tooltip = function(tt)
		tt:AddLine(L.RECRUITING, 1, 0.82, 0)
		Why(tt, "count-other-guild-report")
	end }
	-- The gates the King (or a Hand) opened: where new recruits go now (Acts.lua).
	local gates = ns.Acts and ns.Acts.Gates and ns.Acts.Gates()
	local commands = ns.King and (ns.King.CanCommand() or ns.King.Preview())
	if gates then
		local left = math.max(0, gates.at - ns.Now())
		lines[#lines + 1] = {
			text = CROWN .. Gold(L.GATES_LINE:format(gates.guild)),
			onClick = commands and function() ns.Acts.GatesClick(gates.guild) end or nil,
			tooltip = function(tt)
				tt:AddLine(L.GATES_LINE:format(gates.guild), 1, 0.82, 0, true)
				tt:AddLine(L.GATES_TIP:format(math.floor(left / 3600), math.floor(left % 3600 / 60)), 1, 1, 1, true)
				if commands and ns.Acts.CanClose() then tt:AddLine(L.GATES_CLOSE_TIP, 0.6, 0.6, 0.6, true) end
			end,
		}
	end
	if #open == 0 then lines[#lines + 1] = { text = Grey(L.ALL_FULL) } end
	-- The first RECRUIT_SHOWN, every one on a click (1.1, Fern's #16), and back.
	local shownOpen = Views.recruitAll and #open or math.min(Views.RECRUIT_SHOWN, #open)
	for i = 1, shownOpen do
		local name = open[i].name
		-- (Its census mark too, 1.1: the gates open on its size, Fern's #30.)
		local mark, d = Views.DisputeMark(open[i].e.g)
		lines[#lines + 1] = {
			text = mark .. Green("<" .. name .. ">"), right = L.FREE_SLOTS:format(ns.FormatNumber(open[i].free)) .. AvgTag(open[i].e.g),
			rightWide = true, -- (1.2.4's review: its average level kept whole, a long name giving way)
			-- The King and his Hands open a guild's gates from here.
			onClick = commands and function() ns.Acts.GatesClick(name) end or nil,
			tooltip = function(tt)
				tt:AddLine("<" .. name .. ">", 0.25, 1, 0.25)
				if commands then
					local closing = gates and gates.guild == name
					tt:AddLine(closing and (ns.Acts.CanClose() and L.GATES_CLOSE_TIP or L.GATES_ONLY_OPENER) or L.GATES_CLICK_TIP, 1, 1, 1, true)
				end
				DisputeTooltip(tt, d)
				Why(tt, "count-other-guild-report")
			end,
		}
	end
	if #open > Views.RECRUIT_SHOWN then
		lines[#lines + 1] = {
			text = Gold(Views.recruitAll and L.RECRUIT_SHOW_FEWER or L.RECRUIT_SHOW_ALL:format(#open)),
			onClick = function()
				Views.recruitAll = not Views.recruitAll or nil
				ns.UI.Refresh()
			end,
		}
	end
	-- Our do-not-contact flag (1.1, Fern's #20): recruits' Join screens skip us while it is on.
	local closed = ns.Recruit and ns.Recruit.NoContactMe and ns.Recruit.NoContactMe()
	lines[#lines + 1] = {
		text = Grey(closed and L.NOCONTACT_LINE_ON or L.NOCONTACT_LINE_OFF),
		onClick = function() ns.Recruit.SetNoContact(not closed) end,
		tooltip = function(tt)
			tt:AddLine(L.NOCONTACT_TITLE, 1, 0.82, 0)
			tt:AddLine(L.NOCONTACT_TIP, 1, 1, 1, true)
		end,
	}

	local mapID = ns.Layers.CurrentMap()
	local zone = mapID and ns.Zones.NameForKey("m" .. mapID) or "?"
	lines[#lines + 1] = { header = true, text = L.LAYERS_IN:format(zone) }
	local hop = ns.Hop.State()
	if hop and hop.phase ~= "done" then
		lines[#lines + 1] = { text = ns.Hop.ProgressText(), right = L.HOP_CANCEL_BUTTON,
			onClick = function() ns.Hop.Cancel() end,
			tooltip = function(tt) tt:AddLine(L.HOP_CANCEL_TIP, 1, 1, 1, true) end }
	else
		lines[#lines + 1] = { text = Gold(L.HOP_ANY_BUTTON),
			onClick = function() ns.Hop.Command("any") end,
			tooltip = function(tt) tt:AddLine(L.HOP_ANY_TIP, 1, 1, 1, true) end }
	end
	local layers = mapID and ns.Layers.ForMap(mapID) or {}
	if #layers == 0 then lines[#lines + 1] = { text = Grey(L.LAYERS_HINT) } end
	for _, layer in ipairs(layers) do
		local head = layer.head
		lines[#lines + 1] = {
			text = (layer.mine and Green("> ") or "   ") .. Gold(ns.Layers.Name(layer)) .. Grey(("  #%d"):format(layer.zoneUID)),
			right = L.LAYER_COUNT:format(layer.count),
			-- Another layer: one click asks the Olympus players there for an invite (Hop.lua). (1.5.4) One
			-- on another Forever sub-realm (layer.realm, its label in the name) ends with the relog step.
			onClick = not layer.mine and function() ns.Hop.Ask(mapID, layer.zoneUID, ns.Layers.Name(layer), layer.realm) end or nil,
			tooltip = function(tt)
				tt:AddLine(ns.Layers.Name(layer), 1, 0.82, 0)
				if head then tt:AddLine(("%s <%s>"):format(head.name, head.guild or "?"), 1, 1, 1) end
				if layer.mine then tt:AddLine(L.LAYER_YOU, 0.25, 1, 0.25) else tt:AddLine(L.HOP_ROW_TIP, 0.25, 1, 0.25, true) end
				if layer.realm then tt:AddLine(L.HOP_ROW_OTHER_REALM:format(ns.Layers.RealmLabel(layer.realm)), 1, 0.6, 0.2, true) end
				if layer.lastSeen then tt:AddLine(L.HOP_REPORT_AGE:format(ns.Ago(layer.lastSeen)), 0.6, 0.6, 0.6, true) end
				tt:AddLine(L.LAYER_EXPERIMENTAL, 0.6, 0.6, 0.6, true)
				-- (1.1.2: "~N with Olympus" is a sample: Layers.lua.)
				Why(tt, "count-layer-sample")
			end,
		}
	end
	return lines
end

-- One identity model for the Realm's class/race projections. Our own guild is complete from the
-- guild roster. Other guilds are necessarily partial: their reports name the Lord, Captains and
-- five highest-level members, and /who contributes only people actually seen online. Missing
-- fields remain missing; the Arena profile and crafter board are consented addon self-reports.
local function RealmPeople(s)
	local byKey, out = {}, {}
	local function Add(x)
		if type(x) ~= "table" or type(x.name) ~= "string" or x.name == "" then return nil end
		local full = ns.FullName(x.name, x.realm)
		local key = full:lower()
		local p = byKey[key]
		if not p then
			p = { full = full, name = ns.DisplayName(full), realm = ns.RealmOf(full), sources = {} }
			byKey[key], out[#out + 1] = p, p
		end
		-- (1.2.1: our roster is the server's word now, over any report; /who's only while it is this
		-- quarter-hour's, Views.SeenNow, and never over our roster: an hour-old round is no "online".)
		local who = x.source == "who"
		for _, field in ipairs({ "guild", "class", "race", "raceName", "level", "zone", "online", "days" }) do
			if p[field] == nil and x[field] ~= nil and not (who and (field == "online" or field == "days")) then p[field] = x[field] end
		end
		if x.rank and (p.rank == nil or x.rankExact) then p.rank, p.rankExact = x.rank, x.rankExact or nil end
		if x.source == "roster" and x.online ~= nil then p.online, p.days = x.online, x.days
		elseif who and not p.sources.roster and Views.SeenNow(x.guild, x.name) then p.online, p.days = true, 0 end
		if x.source then p.sources[x.source] = true end
		return p
	end

	for _, e in ipairs(s.guilds or {}) do
		local g = e.g or {}
		if g.leader then
			local on, days = Views.PresenceNow(e, g.leader, g.leaderOnline, g.leaderDays)
			Add({ name = g.leader, realm = g.realm, guild = e.name, class = g.leaderClass,
				level = g.leaderLevel, zone = g.leaderZone, rank = L.LORD, online = on, days = days, source = "report" })
		end
		for _, o in ipairs(g.officers or {}) do
			local on, days = Views.PresenceNow(e, o.name, o.online, o.days)
			Add({ name = o.name, realm = g.realm, guild = e.name, class = o.class, level = o.level,
				zone = o.zone, rank = L.CAPTAIN, online = on, days = days, source = "report" })
		end
		for _, top in ipairs(g.top or {}) do
			Add({ name = top.name, realm = g.realm, guild = e.name, class = top.class, level = top.level,
				rank = top.rank, source = "report" })
		end
	end

	local own = GetGuildInfo("player")
	for _, m in ipairs(ns.Roster.members or {}) do
		Add({ name = m.full or m.name, guild = own, class = m.class, race = m.race, raceName = m.raceName,
			level = m.level, rank = m.rank,
			rankExact = true, online = m.online, days = m.days, source = "roster" })
	end
	local seen = {}
	for _, e in ipairs(s.guilds or {}) do
		for _, p in ipairs(ns.Who and ns.Who.GuildSeen and ns.Who.GuildSeen(e.name) or {}) do
			if p.name and p.guild == e.name then
				local full = ns.FullName(p.name)
				if not seen[full:lower()] then
					seen[full:lower()] = true
					Add({ name = full, guild = e.name, class = ns.Roster.ClassCode(p.class), race = p.race,
						raceName = p.raceName, level = p.level, zone = p.zone and ns.Zones.KeyForName(p.zone),
						online = true, source = "who" })
				end
			end
		end
	end
	for _, p in ipairs(ns.Who and ns.Who.sweep and ns.Who.sweep.list or {}) do
		if p.name and p.guild then
			local full = ns.FullName(p.name)
			if not seen[full:lower()] then
				seen[full:lower()] = true
				Add({ name = full, guild = p.guild, class = ns.Roster.ClassCode(p.class), race = p.race,
					raceName = p.raceName, level = p.level, zone = p.zone and ns.Zones.KeyForName(p.zone),
					online = true, source = "who" })
			end
		end
	end

	for _, p in ipairs(out) do
		-- (CR-05) The race a /who answer showed earlier this session, for someone no list of the
		-- current round has (logged off since, or only in his guild's report): the game's word,
		-- before an Arena profile's self-report.
		if not p.race and ns.Who and ns.Who.RaceOf then
			local race, raceName = ns.Who.RaceOf(p.full)
			if race ~= nil then p.race, p.raceName = race, raceName end
		end
		local profile = ns.ArenaProfile and ns.ArenaProfile.Of and ns.ArenaProfile.Of(p.full)
		-- A private Arena profile may have been learned from a fight this client witnessed. It is
		-- not consent to surface those facts in the Realm; only its public flag (or our own profile)
		-- crosses that boundary.
		if type(profile) == "table" and (profile.pub == true or profile.own == true) then
			if not p.class then p.class = profile.class end
			if not p.level then p.level = profile.level end
			if not p.race then p.race = profile.race end
			p.profileAt = profile.heard or profile.t
			p.sources.profile = true
		end
		if ns.War and type(ns.War.RoleOf) == "function" then p.role = ns.War.RoleOf(p.full) end
	end
	return out, byKey
end

local function RealmClassName(code)
	local file = code and ns.CLASS_FILES[code]
	return (file and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file]) or code or L.REALM_UNKNOWN
end

local function RealmRaceName(id, knownName)
	if type(knownName) == "string" and knownName ~= "" then return knownName end
	if not id then return L.REALM_UNKNOWN end
	if type(id) == "string" and id ~= "" and tonumber(id) == nil then
		return (LOCALIZED_RACE_NAMES_MALE and LOCALIZED_RACE_NAMES_MALE[id]) or id
	end
	local fn = C_CreatureInfo and C_CreatureInfo.GetRaceInfo
	if type(fn) == "function" then
		local ok, info = pcall(fn, tonumber(id) or id)
		if ok and type(info) == "table" and type(info.raceName) == "string" and info.raceName ~= "" then return info.raceName end
	end
	return L.REALM_RACE_N:format(id)
end

-- Does the search `lq` (Lookalike of it; nil, none) find the person `p` of the group `group`? Each
-- text as its row shows it, look-alike letters as one, as the guilds' search (CR-08).
local function RealmPersonMatches(lq, p, group)
	if not lq then return true end
	return LookHolds(lq, p.name) or LookHolds(lq, p.full) or LookHolds(lq, p.guild) or LookHolds(lq, p.rank)
		or LookHolds(lq, p.role) or LookHolds(lq, group)
end

local function RealmPersonSort(a, b)
	local al, bl = tonumber(a.level) or -1, tonumber(b.level) or -1
	if al ~= bl then return al > bl end
	local an, bn = ns.Searchable(a.full or a.name or ""), ns.Searchable(b.full or b.name or "")
	if an ~= bn then return an < bn end
	return (a.full or "") < (b.full or "")
end

-- The person page (UI.ShowPerson) of one of RealmPeople's people.
local function RealmPersonPage(p)
	return { name = p.name or p.full, realm = p.realm, guild = p.guild, class = p.class, level = p.level,
		rank = p.rank, online = p.online, days = p.days, zone = p.zone }
end

-- 1.2: the person page of the player `name` names ("Name-Realm", or short on our realm) as the
-- Realm's people know him (RealmPeople: the census reports, our roster, /who), for the profile's
-- deep link (PlayerProfile.OpenName); nil when none of them knows him. It reads only what this
-- client holds and asks the game for nothing.
function Views.Person(name)
	if type(name) ~= "string" or name == "" then return nil end
	local _, byKey = RealmPeople(ns.Data.Summary())
	local p = byKey[tostring(ns.FullName(name)):lower()]
	return p and RealmPersonPage(p) or nil
end

local function RealmPersonLine(p, profession)
	local text = ClassColored(p.name or p.full or "?", p.class and ns.CLASS_FILES[p.class])
	if p.guild then text = text .. "  " .. Grey("<" .. Plain(p.guild) .. ">") end
	if p.rank then text = text .. "  " .. Gold(Plain(p.rank)) end
	if p.role then text = text .. "  " .. Grey(Plain(p.role)) end
	local right = p.level and L.LEVEL_N:format(p.level) or L.REALM_LEVEL_UNKNOWN
	if profession then right = right .. "  ·  " .. L.REALM_SKILL:format(profession.rank or 0, profession.max or 0) end
	return {
		key = p.full, player = p.full, offline = p.online == false, indent = 1, text = text, right = Grey(right),
		onClick = function() ns.UI.ShowPerson(RealmPersonPage(p)) end,
		tooltip = function(tt)
			tt:AddLine(p.name or p.full or "?", 1, 0.82, 0)
			if p.guild then tt:AddDoubleLine(L.COL_GUILD, Plain(p.guild), 1, 0.82, 0, 1, 1, 1) end
			if p.rank then tt:AddDoubleLine(L.REALM_GUILD_RANK, Plain(p.rank), 1, 0.82, 0, 1, 1, 1) end
			if p.role then tt:AddDoubleLine(L.REALM_OPERATIONAL_ROLE, Plain(p.role), 1, 0.82, 0, 1, 1, 1) end
			if profession then
				tt:AddDoubleLine(L.REALM_PROFESSION_SKILL, L.REALM_SKILL:format(profession.rank or 0, profession.max or 0), 1, 0.82, 0, 1, 1, 1)
				tt:AddLine(L.REALM_PROFESSION_SOURCE:format(ns.Ago(profession.t)), 0.6, 0.6, 0.6, true)
			elseif p.sources and p.sources.profile then
				tt:AddLine(L.REALM_PROFILE_SOURCE:format(ns.Ago(p.profileAt)), 0.6, 0.6, 0.6, true)
			end
		end,
	}
end

local function RealmGroupedLines(s, mode, q)
	local people, byKey = RealmPeople(s)
	local groups = {}
	local function Group(key, label)
		key = tostring(key or "unknown")
		local g = groups[key]
		if not g then g = { key = key, label = label or L.REALM_UNKNOWN, people = {} }; groups[key] = g end
		return g
	end
	if mode == "professions" then
		for _, c in ipairs(ns.Crafters and ns.Crafters.Board and ns.Crafters.Board() or {}) do
			local full = ns.FullName(c.name)
			local p = byKey[full:lower()]
			if not p then
				p = { full = full, name = ns.DisplayName(full), realm = ns.RealmOf(full), guild = c.guild, sources = { crafter = true } }
				byKey[full:lower()], people[#people + 1] = p, p
			end
			for _, profession in ipairs(c.profs or {}) do
				local professionKey = ns.Crafters.CanonicalProfessionKey(profession.key, profession.name)
				local professionName = ns.Crafters.ProfessionLabel(professionKey, profession.name)
				local copy = { rank = profession.rank, max = profession.max, t = c.t, key = profession.key, name = professionName }
				local g = Group(professionKey, professionName)
				g.people[#g.people + 1] = { person = p, profession = copy }
			end
		end
	else
		for _, p in ipairs(people) do
			local key, label
			if mode == "classes" then key, label = p.class or "unknown", RealmClassName(p.class)
			else
				label = RealmRaceName(p.race, p.raceName)
				key = p.race and ("race:" .. ns.Searchable(label)) or "unknown"
			end
			local g = Group(key, label)
			g.people[#g.people + 1] = { person = p }
		end
	end

	local ordered, lq = {}, q and Lookalike(q)
	for _, g in pairs(groups) do
		local matches = {}
		for _, entry in ipairs(g.people) do
			local p = entry.person
			if RealmPersonMatches(lq, p, g.label) or (entry.profession and LookHolds(lq, entry.profession.name)) then matches[#matches + 1] = entry end
		end
		if #matches > 0 then g.people = matches; ordered[#ordered + 1] = g end
	end
	table.sort(ordered, function(a, b)
		if a.key == "unknown" then return false end
		if b.key == "unknown" then return true end
		local al, bl = ns.Searchable(a.label), ns.Searchable(b.label)
		if al ~= bl then return al < bl end
		return a.key < b.key
	end)

	local lines = {}
	for _, g in ipairs(ordered) do
		table.sort(g.people, function(a, b) return RealmPersonSort(a.person, b.person) end)
		local open = q ~= nil or realmGroupOpen[mode][g.key] == true
		lines[#lines + 1] = {
			id = "realm:" .. mode .. ":" .. g.key,
			text = (open and "[-] " or "[+] ") .. Gold(L.REALM_GROUP:format(g.label, #g.people)),
			onClick = function()
				realmGroupOpen[mode][g.key] = not realmGroupOpen[mode][g.key] or nil
				ns.UI.Refresh()
			end,
			-- (CR-05) Races' Unknown says where a race comes from: the census carries none.
			tooltip = mode == "races" and g.key == "unknown" and function(tt)
				tt:AddLine(g.label, 1, 0.82, 0)
				tt:AddLine(L.REALM_RACE_UNKNOWN_TIP, 1, 1, 1, true)
			end or nil,
		}
		if open then for _, entry in ipairs(g.people) do lines[#lines + 1] = RealmPersonLine(entry.person, entry.profession) end end
	end
	if #lines == 0 then lines[1] = q and NoMatch() or { text = Grey(L.REALM_NO_KNOWN_DATA) } end
	return lines
end

local function RealmNavigation()
	local labels = { guilds = L.REALM_VIEW_GUILDS, classes = L.REALM_VIEW_CLASSES,
		races = L.REALM_VIEW_RACES, professions = L.REALM_VIEW_PROFESSIONS }
	local nav = {}
	for _, key in ipairs(REALM_MODES) do
		local mode = key
		nav[#nav + 1] = { text = labels[mode], selected = realmMode == mode,
			onClick = realmMode ~= mode and function() Views.SetRealmMode(mode) end or nil }
	end
	return { nav = nav, pageNav = true, id = "realm-navigation" }
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

-- (While a search is typed, the guilds it opened close and open with them.)
function Views.ExpandAll(on)
	for _, e in ipairs(ns.Data.Summary().guilds) do expanded[e.name], folded[e.name] = on or nil, not on or nil end
	expanded[COUNCIL_ROW], folded[COUNCIL_ROW] = on or nil, not on or nil -- (the High Council's too)
end

---------------------------------------------------------------------------
-- Decrees (layers + decrees)
---------------------------------------------------------------------------

-- Pages of the Decrees tab (2026-10-19, Daniel: the officer musters belong in the Decrees, not in
-- The Realm): a module lists one in ns.DecreePages, the shape of ns.RealmPages' ({ key, Link =
-- function() return its link line, or nil end, Lines = function(q) return its lines end, tip =
-- what its search finds, L.SEARCH_TIP_...}). Its link, under the royal decrees, opens it in place
-- of the tab's list; its Back line (ShowDecreePage(nil)) or another tab opened (UI.lua's ShowTab)
-- closes it. A page whose link he no longer gets (he left the guild) closes by itself.
local decreePageShown -- the page shown instead of the Decrees' list, or nil
local function DecreePage(key)
	for _, p in ipairs(ns.DecreePages or {}) do
		if p.key == key then return p end
	end
	return nil
end
local function DecreePageNow()
	local page = decreePageShown and DecreePage(decreePageShown)
	if page and page.Link and not page.Link() then page = nil end
	if not page then decreePageShown = nil end
	return page
end
function Views.DecreePageShown() return decreePageShown end
function Views.ShowDecreePage(key)
	decreePageShown = DecreePage(key) and key or nil
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end
function Views.CloseDecreePage() decreePageShown = nil end

local function DecreeLines(q)
	-- The shared army agenda owns this page's top: the King's current appointment and week,
	-- consented guild-calendar rows, and read-only Arena providers all keep the one Week identity,
	-- signup and cancellation model.  It moved here from the Realm's Board; do not fork it into a
	-- second event protocol.
	local lines = {}
	if ns.Week and ns.Week.Section then ns.Week.Section(lines, q) end
	-- What waits in an instance or on Busy follows the agenda (1.1, ns.Alert); then the King's
	-- writs, for whoever they are for (Acts.lua).
	for _, l in ipairs(ns.HeldLines()) do lines[#lines + 1] = l end
	for _, l in ipairs(ns.Acts and ns.Acts.WritLines and ns.Acts.WritLines() or {}) do lines[#lines + 1] = l end
	-- Net-off (1.4.0, the author: the hidden list left this page for The Watch, Moderation.Lines there):
	-- only the viewer's own notice, when a word hides him or his guild (the reason on hover), or his
	-- guild's timed word (its parchment again). A hidden officer cannot enter The Watch, so this
	-- line is where he reads why; nobody else's name shows here.
	for _, l in ipairs(ns.Moderation.SelfLines and ns.Moderation.SelfLines() or {}) do lines[#lines + 1] = l end
	local names, map = ns.MapNames, ns.Map
	if names and names.CanEdit and names.CanEdit() then
		local available = map and map.CanOpenNamesMap and map.CanOpenNamesMap()
		lines[#lines + 1] = { header = true, text = L.MAPNAME_TITLE }
		lines[#lines + 1] = { text = Grey(L.MAPNAME_DECREE_HELP) }
		lines[#lines + 1] = { text = Grey(L.MAPNAME_DECREE_LIMIT) }
		lines[#lines + 1] = { text = (available and Green or Grey)(L.MAPNAME_OPEN_MAP),
			onClick = available and map.OpenNamesMap or nil, mapNamesShortcut = true, gapAfter = true }
	end
	lines[#lines + 1] = { header = true, text = L.DECREES }
	local decrees = ns.Decree.Active()
	if #decrees == 0 then lines[#lines + 1] = { text = Grey(L.NO_DECREES), gapAfter = true } end
	for _, d in ipairs(decrees) do
		local color = d.kind == "ARMS" and Red or Gold
		-- 1.1 (#31): words the player's block terms hide, until a click shows them.
		local veiled = d.hidden and not d.revealed
		lines[#lines + 1] = {
			text = color(ns.Decree.Label(d)) .. "  " .. ns.Zones.NameForKey("m" .. d.mapID),
			right = Grey(ns.Ago(d.t)),
			tooltip = function(tt)
				tt:AddLine(ns.Decree.Label(d), 1, 0.25, 0.25)
				if d.text ~= "" then tt:AddLine(veiled and L.FILTER_WORDS_HIDDEN_SHORT or d.text, 1, 1, 1, true) end
				tt:AddLine(L.DECREE_BY:format(d.sender, d.guild, ns.Ago(d.t)), 0.7, 0.7, 0.7)
			end,
		}
		if d.text ~= "" and veiled then
			lines[#lines + 1] = { indent = 1, text = Grey(L.FILTER_WORDS_HIDDEN), onClick = function()
				d.revealed = true
				if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
			end }
		elseif d.text ~= "" then
			lines[#lines + 1] = { indent = 1, text = Grey('"' .. d.text .. '"') }
		end
	end
	-- The tab's pages (ns.DecreePages: the officer musters), one link each under the decrees, with
	-- one gap after the last; none while a search is typed.
	local links = {}
	for _, p in ipairs(not q and ns.DecreePages or {}) do
		local link = p.Link and p.Link()
		if link then links[#links + 1] = link end
	end
	if #links > 0 then
		local prev = lines[#lines]
		if prev then prev.gapAfter = true end
		for i, link in ipairs(links) do
			link.pageLink = true
			link.gapAfter = i == #links
			lines[#lines + 1] = link
		end
	end
	-- 1.1 (#31): a Vox Populi question the player's block terms hid, while it is open.
	local vox = ns.Vox and ns.Vox.HiddenQuestion and ns.Vox.HiddenQuestion()
	if vox then
		lines[#lines + 1] = { text = Grey(L.FILTER_VOX_HIDDEN), onClick = function() ns.Vox.Reveal() end }
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

-- The alerts' settings (1.1), at the bottom of the Decrees tab: held in an instance or on Busy,
-- or not; the alert sounds, the switch for all on the heading and one line per kind below. A
-- click turns one on or off (the same as /oly alerts, /oly sound [kind] on|off; with the gamepad
-- UI too: a click on a row, no text box, no popup).
local function SoundLines(lines)
	local all = ns.db.sound and true or false
	lines[#lines].gapAfter = true
	-- In an instance or on Busy: alerts held (the default) or shown (1.1, /oly alerts quiet|always).
	local always = ns.db.alertsAlways and true or false
	lines[#lines + 1] = {
		header = true,
		text = L.ALERTS_LINE,
		right = always and Gold(L.ALERTS_SHOWN) or Green(L.ALERTS_HELD),
		alerts = true, -- (tests)
		onClick = function() ns.AlertsSlash(always and "quiet" or "always") end,
		tooltip = function(tt)
			tt:AddLine(L.ALERTS_LINE, 1, 0.82, 0)
			tt:AddLine(L.ALERTS_TIP, 1, 1, 1, true)
		end,
		gapAfter = true,
	}
	lines[#lines + 1] = {
		header = true,
		text = L.SOUNDS_TITLE,
		right = all and Green(L.SOUND_ALL_ON) or Red(L.SOUND_ALL_OFF),
		onClick = function() ns.SoundSlash(all and "off" or "on") end,
		tooltip = function(tt)
			tt:AddLine(L.SOUNDS_TITLE, 1, 0.82, 0)
			tt:AddLine(L.SOUNDS_TIP, 1, 1, 1, true)
		end,
	}
	for _, kind in ipairs(ns.SOUND_KINDS) do
		local on = ns.SoundKindOn(kind)
		local state = on and (all and Green(L.SOUND_ON) or Grey(L.SOUND_ON)) or Red(L.SOUND_OFF)
		lines[#lines + 1] = {
			text = (all and "" or "|cff9d9d9d") .. ns.SoundLabel(kind) .. (all and "" or "|r") .. "  " .. Grey("(" .. kind .. ")"),
			right = state,
			sound = kind, -- (tests)
			onClick = function() ns.SoundSlash(kind .. (on and " off" or " on")) end,
			tooltip = function(tt)
				tt:AddLine(ns.SoundLabel(kind), 1, 0.82, 0)
				tt:AddLine(L.SOUND_KIND_TIP:format(kind), 1, 1, 1, true)
				if not all then tt:AddLine(L.SOUNDS_OFF, 1, 0.25, 0.25, true) end
			end,
		}
	end
end

-- What this player's decrees do (1.2.3, Decree.YouCan): another guild's master is told his Royal
-- decrees and Tabard inspections reach his guild alone, never that he is the Crown.
local function DecreeDetail()
	return L.DECREES_DETAIL_TITLE, ns.Decree.YouCan()
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

Views.RACE_MAX, Views.RACE_PAGE = 100, 25 -- the level race: its top 100, 25 at a time
Views.RECRUIT_SHOWN = 5 -- guilds with room shown in the Realm's Recruiting, the rest on a click (1.1)
Views.raceShown = Views.RACE_PAGE
Views.INSPECT_ROWS = 200 -- inspected players listed on the Tabards page

if ns.RankingRules then
	ns.RankingRules.Register("realm-level", {
		title = L.RANK_RULE_LEVEL_TITLE,
		icon = "Interface\\Icons\\Achievement_Level_60",
		allowed = function() return ns.IsMember() == true end,
		sections = function()
			return {
				{ topic = "score", text = L.RANK_RULE_LEVEL_SCORE },
				{ topic = "order", text = L.RANK_RULE_LEVEL_ORDER:format(Views.RACE_MAX, Views.RACE_PAGE) },
				{ topic = "evidence", text = L.RANK_RULE_LEVEL_EVIDENCE },
				{ topic = "visibility", text = L.RANK_RULE_LEVEL_VISIBILITY },
			}
		end,
	})
end

-- 1.1 (Fern's #28): the gear an officer's click kept (Inspect.InspectGear), newest first, the
-- players whose name or guild holds `q`: a click shows or hides the items, in their slots, each
-- with its own tooltip. Nothing added up, scored or compared. False when none shows.
Views.GEAR_ROWS = 50
local gearOpen = {}
local function GearLines(lines, q)
	local shown = {}
	for _, g in ipairs(ns.Inspect.GearList and ns.Inspect.GearList() or {}) do
		if not q or ns.Holds(q, ns.ShortName(g.name), g.guild) then shown[#shown + 1] = g end
	end
	if #shown == 0 then return false end
	lines[#lines + 1] = { header = true, text = L.GEAR_TITLE, right = Grey(tostring(#shown)) }
	for i = 1, math.min(#shown, Views.GEAR_ROWS) do
		local g = shown[i]
		local open = gearOpen[g.name] == true
		local n = 0
		for _ in pairs(g.items) do n = n + 1 end
		lines[#lines + 1] = {
			indent = 1, key = g.name,
			text = (open and "[-] " or "[+] ") .. ClassColored(ns.ShortName(g.name), g.class) .. "  " .. Grey("<" .. (g.guild or "?") .. ">"),
			right = Grey(L.GEAR_ITEMS:format(n) .. "  " .. ns.Ago(g.t)),
			onClick = function()
				gearOpen[g.name] = not open or nil
				if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
			end,
			tooltip = function(tt)
				tt:AddLine(ClassColored(g.name, g.class))
				tt:AddLine(L.GEAR_ROW_TIP:format(ns.ShortName(g.name), date("%Y-%m-%d %H:%M", g.t)), 1, 1, 1, true)
			end,
		}
		if open then
			local items = {}
			for slot = 1, 19 do
				local it = g.items[slot]
				local id = type(it) == "string" and tonumber(it:match("^item:(%d+)")) or nil
				if id then
					-- The game's link for it, once the client knows the item (its enchant and suffix kept).
					local link
					if GetItemInfo then
						local ok, _, l = pcall(GetItemInfo, it)
						if ok and type(l) == "string" then link = l end
					end
					items[#items + 1] = { id = id, link = link, s = slot }
				end
			end
			lines[#lines + 1] = { indent = 2, items = items, slots = 19 }
		end
	end
	if #shown > Views.GEAR_ROWS then lines[#lines + 1] = { indent = 1, text = Grey(L.AND_MORE:format(#shown - Views.GEAR_ROWS)) } end
	lines[#lines].gapAfter = true
	return true
end
function Views.CloseGear() wipe(gearOpen) end -- (tests)

-- `q`, the search (Views.Query): the untabarded and the inspected players whose name or guild
-- holds it, each list under its header, a page as ever; "No match" for none. Nothing else.
local function HeraldryLines(q)
	local s = ns.Inspect.Summary()
	-- The King (and his Hands): the Royal Inspection, and what the patrols reported (King.lua).
	local lines = {}
	for _, l in ipairs(not q and ns.King and ns.King.InspectionLines and ns.King.InspectionLines() or {}) do lines[#lines + 1] = l end
	-- The untabarded: the King sees his own list (and whether the army sees it); everyone else
	-- sees it only while he shares it.
	local king = ns.King and (ns.King.IsKing() or ns.King.Preview())
	local shame = ns.Inspect.Shame()
	if king then
		shame = { list = ns.Inspect.ShameList(), mine = true }
	end
	local players = s.players
	if q then
		local list = {}
		for _, p in ipairs(ns.Inspect.ShameOpen() and shame and shame.list or {}) do
			if ns.Holds(q, p.name, p.guild) then list[#list + 1] = p end
		end
		-- (Only a list with someone found in it, headed as ever.)
		shame = #list > 0 and { list = list, mine = shame.mine, by = shame.by, t = shame.t } or nil
		players = {}
		for _, p in ipairs(s.players) do
			if ns.Holds(q, ns.ShortName(p.name), p.guild) then players[#players + 1] = p end
		end
		if not shame and #players == 0 and not GearLines({}, q) then return { NoMatch() } end
	end
	if q and not shame then
		-- (The search found none of the untabarded: their header goes too.)
	elseif not ns.Inspect.ShameOpen() then
		-- Closed until the tabard rule is in force (Inspect.lua): a countdown.
		local left = ns.Inspect.ShameOpensIn()
		local wait = ("%dh %02dm"):format(math.floor(left / 3600), math.floor(left % 3600 / 60))
		lines[#lines + 1] = { header = true, text = Red(L.WALL_OF_SHAME), right = Grey(L.SHAME_OPENS:format(wait)) }
		lines[#lines].gapAfter = true
	elseif not (shame and #shame.list > 0) then
		-- A fresh empty publication is meaningful: the King published that nobody currently
		-- meets the evidence rule. It is not the same as no publication lease.
		local right = king and L.SHAME_EMPTY or (shame and L.UNTABARDED_PUBLISHED_EMPTY or L.UNTABARDED_NOT_SHARED)
		lines[#lines + 1] = { header = true, text = Red(L.WALL_OF_SHAME), right = Grey(right) }
		lines[#lines].gapAfter = true
	else
		local right = shame.mine and (ns.King.SharingUntabarded() and L.UNTABARDED_SHARED or L.UNTABARDED_ONLY_KING)
			or L.PUBLISHED_BY:format(shame.by, ns.Ago(shame.t))
		lines[#lines + 1] = { header = true, text = Red(L.WALL_OF_SHAME), right = Grey(right) }
		-- The King pardons with a click (Acts.lua); anyone else opens the person.
		for i = 1, math.min(12, #shame.list) do
			local p = shame.list[i]
			local pardon = king and ns.King.CleanName(p.name) ~= nil
			lines[#lines + 1] = { indent = 1, key = p.name, text = p.name .. "  " .. Grey("<" .. (p.guild or "?") .. ">"),
				onClick = pardon and function() ns.ShowDialog("OLYMPUS_PARDON", p.name, nil, p.name) end
					or function() ns.UI.ShowPerson({ name = p.name, guild = p.guild }) end,
				tooltip = pardon and function(tt)
					tt:AddLine(p.name, 1, 0.82, 0)
					tt:AddLine(L.PARDON_TIP, 1, 1, 1, true)
				end or nil }
		end
		if #shame.list > 12 then lines[#lines + 1] = { indent = 1, text = Grey(L.AND_MORE:format(#shame.list - 12)) } end
		lines[#lines].gapAfter = true
	end
	if not q then
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
	end
	-- 1.1: the gear officers' clicks kept.
	GearLines(lines, q)
	if q and #players == 0 then return lines end
	lines[#lines + 1] = { header = true, text = L.INSPECTED_PLAYERS }
	-- A line (and a frame) each: the first INSPECT_ROWS, marked and caught players first
	-- (Inspect.Summary), the rest counted.
	local rows = math.min(#players, Views.INSPECT_ROWS)
	for i = 1, rows do
		local p = players[i]
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
					name = ns.ShortName(p.name), realm = ns.RealmOf(p.name), class = code ~= "" and code or nil, level = p.level, guild = p.guild,
					tabard = (STATUS_TEXT[p.status or "UNKNOWN"] or STATUS_TEXT.UNKNOWN)(), note = p.note,
					onMark = function() ns.Inspect.ToggleMark(p.name) end,
				})
			end,
			tooltip = function(tt)
				tt:AddLine(ClassColored(p.name, p.class))
				tt:AddLine("<" .. (p.guild or "?") .. ">" .. (p.level and ("  lvl " .. p.level) or ""), 0.25, 1, 0.25)
				if p.note then tt:AddLine('"' .. p.note .. '"', 1, 0.5, 0.5, true) end
				-- 1.1 (Fern's #29): another officer of our guild found it.
				if p.shared and p.by then tt:AddLine(L.PATROLSHARE_BY:format(p.by), 0.6, 0.8, 1, true) end
				tt:AddLine(L.CLICK_MARK_PLAYER, 0.6, 0.6, 0.6)
			end,
		}
	end
	if #players > rows then lines[#lines + 1] = { text = Grey(L.AND_MORE:format(#players - rows)) } end
	return lines
end

local function HeraldryDetail()
	local s = ns.Inspect.Summary()
	local c = s.counts
	local text = ns.Inspect.IsPatrolling() and Green(L.PATROL_ON) or Grey(L.PATROL_HINT)
	-- 1.1 (Fern's #29): how many on the list our guild's other officers found.
	local shared = ns.Inspect.SharedCount and ns.Inspect.SharedCount() or 0
	if shared > 0 then text = text .. "\n" .. Grey(L.PATROLSHARE_COUNT:format(shared)) end
	return L.INSPECT_COUNTS:format(s.total, c.GUILD, c.NONE, c.OTHER), text
end

---------------------------------------------------------------------------
-- Join Olympus (what non-members see)
---------------------------------------------------------------------------

-- 1.1: a guild of Asmon's Olympus whose name the rule leaves out counts once the author's signed
-- list names it (ns.IsApprovedGuild): its first member pastes that list, from this screen too.
local function ApprovedHint(lines)
	local guild = IsInGuild() and GetGuildInfo("player")
	if type(guild) ~= "string" or guild == "" then return lines end
	if lines[#lines] then lines[#lines].gapAfter = true end
	-- (1.1.5: a guild the High Council removed is told so, and how to appeal.)
	local hint = ns.IsRemovedGuild(guild) and L.REMOVED_GUILD or L.APPROVED_JOIN_HINT
	lines[#lines + 1] = {
		text = Grey(hint:format(Plain(guild))),
		onClick = function() ns.ShowDialog("OLYMPUS_APPROVED_PASTE") end,
		tooltip = function(tt)
			tt:AddLine(hint:format(Plain(guild)), 1, 0.82, 0, true)
			tt:AddLine(L.APPROVED_PASTE_PROMPT, 1, 1, 1, true)
		end,
	}
	return lines
end

function Views.RecruitLines()
	local R = ns.Recruit
	local lines = { { header = true, text = L.RECRUIT_TITLE } }
	local guilds = R.Guilds()
	if #guilds == 0 then
		lines[#lines + 1] = { text = Grey(#R.found == 0 and not ns.Who.Searched() and L.RECRUIT_START or L.RECRUIT_NONE_FOUND) }
		return ApprovedHint(lines)
	end
	-- "Showing 50 of 312 online", and which levels the next click searches.
	WhoStatus(lines)
	if #lines > 1 then lines[#lines].gapAfter = true end
	-- Where to go: confirmed gates, optional corroborated affinity, then room. The player
	-- still chooses a click and the contact must have been found by this client's /who.
	if ns.GuildCharter then
		lines[#lines + 1] = { text = L.CHARTER_ORDER, gapAfter = true }
		lines[#lines + 1] = { text = L.CHARTER_FRIEND_CHOOSE,
			onClick = function() ns.GuildCharter.Prompt("friend") end, gapAfter = true }
	end
	local route = R.Route()
	if route and #R.RouteOrder(route) > 0 then
		lines[#lines + 1] = {
			header = true, text = L.RECRUIT_ROUTE_TITLE,
			tooltip = function(tt)
				tt:AddLine(L.RECRUIT_ROUTE_TITLE, 1, 0.82, 0)
				tt:AddLine(L.RECRUIT_ROUTE_TIP:format(ns.DisplayName(route.from) or "?"), 1, 1, 1, true)
			end,
		}
		for _, name in ipairs(R.RouteOrder(route)) do
			local e = route.byName[name]
			local gates = name == route.gates
			lines[#lines + 1] = {
				text = (gates and CROWN or "") .. Green("<" .. Plain(name) .. ">") .. (gates and ("  " .. Gold(L.RECRUIT_GATES)) or ""),
				right = (e and Grey(L.FREE_SLOTS:format(ns.FormatNumber(e.free))) .. "  " or "") .. Gold(L.RECRUIT_ASK),
				onClick = function() R.PromptNext(name) end,
				tooltip = function(tt)
					tt:AddLine("<" .. Plain(name) .. ">", 0.25, 1, 0.25)
					if gates then tt:AddLine(L.RECRUIT_GATES_TIP, 1, 1, 1, true) end
					tt:AddLine(L.RECRUIT_ROUTE_ASK_TIP, 1, 1, 1, true)
				end,
			}
		end
		lines[#lines].gapAfter = true
	end
	for _, g in ipairs(guilds) do
		lines[#lines + 1] = {
			text = (g.gates and CROWN or "") .. Green("<" .. g.name .. ">"),
			right = Grey(L.RECRUIT_ONLINE:format(#g.members)) .. (g.free and ("  " .. Grey(L.FREE_SLOTS:format(ns.FormatNumber(g.free)))) or "")
				.. "  " .. Gold(L.RECRUIT_ASK),
			onClick = function() R.PromptNext(g.name) end,
			tooltip = function(tt)
				tt:AddLine("<" .. g.name .. ">", 0.25, 1, 0.25)
				tt:AddLine(L.RECRUIT_ASK_TIP, 1, 1, 1, true)
			end,
		}
		if ns.GuildCharter then
			for _, row in ipairs(ns.GuildCharter.CardLines(g.name, true)) do lines[#lines + 1] = row end
		end
		for _, p in ipairs(g.members) do
			local state = ""
			local closed = R.NoContact(p.name)
			if closed then state = Grey(L.RECRUIT_STATE_DNC)
			elseif R.replied[p.name] then state = Green(L.RECRUIT_STATE_REPLIED)
			elseif R.asked[p.name] then state = Grey(L.RECRUIT_STATE_ASKED) end
			lines[#lines + 1] = {
				indent = 1,
				text = ClassColored(ns.ShortName(p.name), p.class) .. "  " .. Grey((p.level and L.LEVEL_N:format(p.level) or "") .. (p.zone and ("  " .. p.zone) or "")),
				right = state,
				-- (Not one who asked not to be contacted, 1.1.)
				onClick = not closed and function() R.Prompt(p) end or nil,
				tooltip = R.replied[p.name] and function(tt)
					tt:AddLine(ns.ShortName(p.name), 1, 0.82, 0)
					-- (A whisper: its links stay, like a chat line's; no other escape code, 0.9.2.)
					tt:AddLine('"' .. ns.Codec.SanitizeChat(R.replied[p.name]) .. '"', 1, 1, 1, true)
				end or nil,
			}
		end
		lines[#lines].gapAfter = true
	end
	return ApprovedHint(lines)
end

function Views.JoinLines(height)
	local R = ns.Recruit
	local searching, left, last, reminder, guilds = R.JoinStatus()
	local pending = searching or left > 0
	local status = searching and L.RECRUIT_SEARCHING
		or left > 0 and L.RECRUIT_JOIN_WAITING:format(left)
		or last and (R.replied[last.name] and L.RECRUIT_REPLIED:format(Plain(ns.ShortName(last.name))) or L.RECRUIT_JOIN_TIMEOUT)
		or ns.Who.Searched() and #R.found == 0 and L.RECRUIT_NONE_FOUND
		or L.RECRUIT_JOIN_HINT
	local lines = {
		{ text = L.RECRUIT_JOIN_TITLE, center = true, color = "GameFontNormalLarge", gapAfter = true,
			spaceBefore = guilds and 6 or math.max(6, math.floor(((height or 0) - 150) / 2)) },
		{ text = status, center = true, gapAfter = true },
		{ text = last and L.RECRUIT_JOIN_AGAIN or L.RECRUIT_JOIN_REQUEST, primary = true,
			onClick = not pending and R.RequestJoin or nil, gapAfter = true },
	}
	if last and left == 0 then
		lines[#lines + 1] = { text = Gold(reminder and L.RECRUIT_JOIN_REMINDER_ON or L.RECRUIT_JOIN_REMINDER_OFF),
			center = true, onClick = R.ToggleJoinReminder }
	end
	lines[#lines + 1] = { text = Gold(guilds and L.RECRUIT_JOIN_HIDE_GUILDS or L.RECRUIT_JOIN_SHOW_GUILDS),
		center = true, onClick = R.ToggleJoinGuilds }
	if guilds then
		lines[#lines + 1] = { text = Gold(L.RECRUIT_FIND), center = true, onClick = not pending and R.Search or nil, gapAfter = true }
		for _, line in ipairs(Views.RecruitLines()) do lines[#lines + 1] = line end
	end
	return lines
end

---------------------------------------------------------------------------
-- Entry point used by UI.lua
---------------------------------------------------------------------------

-- The search box on top of a list (1.0.0).
local function Searched(lines, tab, tip, filterKey)
	table.insert(lines, 1, SearchLine(tab, tip, filterKey))
	return lines
end

-- Each tab's lines, detail title and detail text. A tab missing here (a new one being
-- added) is an empty list.
local BUILD = {
	census = function(s)
		-- (CR-02 / KH-08: the census's own page, opened from the header's count, CensusStats.lua.)
		local stats = ns.CensusStats
		if type(stats) == "table" and not stats.missing and type(stats.Shown) == "function" and stats.Shown() then return stats.Build(s) end
		local title, text = CensusDetail(s)
		return Searched(CensusLines(s, Views.Query("census")), "census", "CENSUS"), title, text
	end,
	realm = function(s)
		local title, text = RealmDetail(s)
		local filterKey = realmMode == "guilds" and "realm" or ("realm:" .. realmMode)
		local q = Views.Query(filterKey)
		local lines = realmMode == "guilds" and RealmLines(s, q) or RealmGroupedLines(s, realmMode, q)
		table.insert(lines, 1, RealmNavigation())
		-- (One box for the tab: a page's lines are searched with it while it shows.)
		local members = ns.Members and ns.Members.Shown and ns.Members.Shown()
		local page = pageShown and RealmPage(pageShown)
		local V = ns.Verify
		if not q and V and V.SelfLine and (realmMode ~= "guilds" or not (boardShown or page or members)) then
			local verification = V.SelfLine()
			if verification then table.insert(lines, 2, verification) end
		end
		local tip = realmMode == "guilds" and (boardShown and "BOARD" or (page and page.tip) or members and "MEMBERS" or "REALM") or "REALM_PEOPLE"
		return Searched(lines, "realm", tip, filterKey), title, text
	end,
	decrees = function()
		local title, text = DecreeDetail()
		local q = Views.Query("decrees")
		-- (A page of the tab, ns.DecreePages: its lines in place of the list, the one box searching it.)
		local page = DecreePageNow()
		if page then return Searched(page.Lines(q) or {}, "decrees", page.tip or "LOG"), title, text end
		local lines = DecreeLines(q)
		-- 1.1 (#12): this client's log of the acts it saw; the box searches it and the week alone.
		if ns.Chronicle and not ns.Chronicle.missing then ns.Chronicle.AddLines(lines, q) end
		DecreeHelp(lines)
		SoundLines(lines)
		return Searched(lines, "decrees", "LOG"), title, text
	end,
	-- 1.2: no tab of its own: The Watch's Tabards section (Watch.lua) draws these lines, its search
	-- box redrawing The Watch.
	heraldry = function()
		local title, text = HeraldryDetail()
		return Searched(HeraldryLines(Views.Query("heraldry")), "watch", "HERALDRY", "heraldry"), title, text
	end,
	crafters = function()
		-- 1.2: while a request is being written, the page is its composer (its own search box).
		local requests = ns.CraftRequests
		if requests and requests.Composing and requests.Composing() and requests.ComposerLines then
			local lines, title, text = requests.ComposerLines()
			return lines or {}, title or L.CRAFT_REQUEST_COMPOSER, text or L.CRAFT_REQUEST_COMPOSER_ABOUT
		end
		local lines = ns.Crafters and ns.Crafters.Lines and ns.Crafters.Lines(Views.Query("crafters")) or {}
		return Searched(lines, "crafters", "CRAFTER"), L.CRAFTER_TITLE, L.CRAFTER_ABOUT
	end,
	throne = function(s)
		if not (ns.King and ns.King.Build) then return {}, nil, nil end
		local lines, title, text = ns.King.Build(s)
		return lines or {}, title, text
	end,
	vox = function()
		if not (ns.Vox and ns.Vox.Build) then return {}, nil, nil end
		local lines, title, text = ns.Vox.Build()
		return lines or {}, title, text
	end,
	-- (The box where a list of donors shows: the ranking, the book. Without it, nothing typed
	-- earlier filters what shows.)
	treasury = function()
		if not (ns.Treasury and ns.Treasury.Build) then return {}, nil, nil end
		local searched = ns.Treasury.Searchable and ns.Treasury.Searchable()
		local lines, title, text = ns.Treasury.Build(searched and Views.Query("treasury") or nil)
		lines = lines or {}
		if searched then
			-- 1.2: the Guild treasuries' box searches every bank too, and holds an item's link pasted
			-- in or an item dragged onto it (DropItem).
			local guilds = ns.Treasury.DirectoryShown and ns.Treasury.DirectoryShown()
			Searched(lines, "treasury", guilds and "TREASURY_GUILDS" or "TREASURY")
			if guilds and lines[1] and lines[1].input then lines[1].input.maxLetters, lines[1].input.items = 255, true end
		end
		return lines, title, text
	end,
	workshop = function()
		if not (ns.Workshop and ns.Workshop.Build) then return {}, nil, nil end
		local lines, title, text = ns.Workshop.Build()
		return lines or {}, title, text
	end,
	-- 1.1.1: the Chat tab. ChatWindow.lua draws it over this list; on a client updated without a
	-- restart (no ChatWindow.lua yet), the list says what to do.
	chat = function()
		local CW = ns.ChatWindow
		if type(CW) ~= "table" or CW.missing then return { { text = Grey(L.RESTART_NEEDED) } }, nil, nil end
		return {}, nil, nil
	end,
}

-- s (1.2.3): the census's summary the caller read a moment ago (UI.Refresh's, for the window's
-- header), else read here. The window's redraw summed the census twice, once for its header and
-- once for its tab, a few hundred KB each time on a big census.
function Views.Build(tab, s)
	local build = BUILD[tab]
	if not build then return {}, nil, nil end
	return build(s or ns.Data.Summary())
end

-- 1.2: another file's tab (UI.AddTab: the Blood Arena's, ArenaHome.lua): builder(s) returns its
-- lines, detail title and detail text, as the tabs above. Never one of these: false for a key
-- taken. A builder that fails shows an empty list (the error is kept, ns.SafeCall).
local registered = {} -- the keys Views.Register took
function Views.Register(key, builder)
	if type(key) ~= "string" or type(builder) ~= "function" or BUILD[key] then return false end
	BUILD[key] = function(s)
		local out
		ns.SafeCall("tab " .. key, function() out = { builder(s) } end)
		if not out then return {}, nil, nil end
		return out[1] or {}, out[2], out[3]
	end
	registered[key] = true
	return true
end
-- A tab Views.Register took, let go (the tests' clean-up; never one of the tabs above): true when
-- there was one.
function Views.Unregister(key)
	if not registered[key] then return false end
	registered[key], BUILD[key] = nil, nil
	return true
end

-- Kept for the tests: the Realm tree lines.
function Views.RealmLines() return RealmLines(ns.Data.Summary()) end
