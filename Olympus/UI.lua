local ADDON, ns = ...
local L = ns.L

-- The Olympus window mirrors Blizzard's Guild window: same size and frame, a header,
-- column titles, a list, a detail box (like "Guild Message of the Day"), three buttons
-- and tabs along the bottom. Opened from the Guild window it docks right next to it, so
-- it reads as a continuation of that window. Created on first open.

local UI = {}
ns.UI = UI

local DEFAULT_W, DEFAULT_H = 338, 424
local DETAIL_H = 78
local main

local TABS = {
	{ key = "census", label = "TAB_CENSUS" },
	{ key = "realm", label = "TAB_REALM" },
	{ key = "decrees", label = "TAB_DECREES" },
	{ key = "heraldry", label = "TAB_HERALDRY" },
}

local function DecreeAction(kind)
	return function()
		if ns.Decree.CanSend(kind) then
			StaticPopup_Show("OLYMPUS_DECREE", ns.Decree.Label({ kind = kind }), nil, kind)
		else
			ns.Print(ns.Decree.CROWN_ONLY[kind] and L.CROWN_PREVIEW_NOTE or L.DECREE_PREVIEW_NOTE)
			ns.Decree.Preview(kind)
		end
	end
end

-- Three buttons per tab, like "Guild Information / Add Member / Guild Control".
local BUTTONS = {
	census = {
		{ "COPY_BTN", function() UI.ShowCopy(L.COPY_DISCORD, ns.Data.DiscordText()) end },
		{ "REFRESH", function() ns.Roster.RequestScan(true); ns.Print(L.REFRESHING) end },
		{ "REPORT_BUG", function() UI.ShowCopy(L.REPORT_BUG, ns.BuildBugReport()) end },
	},
	realm = {
		{ "EXPAND_ALL", function() ns.Views.ExpandAll(true); UI.Refresh() end },
		{ "COLLAPSE_ALL", function() ns.Views.ExpandAll(false); UI.Refresh() end },
		{ "COPY_BTN", function() UI.ShowCopy(L.COPY_DISCORD, ns.Data.DiscordText()) end },
	},
	decrees = {
		{ "ARMS_BTN", DecreeAction("ARMS") },
		{ "MUSTER_BTN", DecreeAction("MUSTER") },
		{ "ROYAL_BTN", DecreeAction("ROYAL") },
	},
	heraldry = {
		{ "PATROL_BTN", function() ns.Inspect.SetPatrol(not ns.Inspect.IsPatrolling()) end },
		{ "MARK_TARGET", function() ns.Inspect.MarkTarget() end },
		{ "COPY_BTN", function() UI.ShowCopy(L.INSPECT_TITLE, ns.Inspect.DiscordText()) end },
	},
}

-- Small extra buttons inside the detail box (only where needed).
local DETAIL_BUTTONS = {
	heraldry = {
		{ "SHAME_BTN", function() ns.Inspect.PublishShame() end },
		{ "HERALDRY_BTN", DecreeAction("HERALDRY") },
		{ "CLEAR", function() StaticPopup_Show("OLYMPUS_CLEAR_INSPECT") end },
	},
}

local function Button(parent, width, height)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, height or 22)
	if height and height < 22 then
		b:SetNormalFontObject("GameFontNormalSmall")
		b:SetHighlightFontObject("GameFontHighlightSmall")
		b:SetDisabledFontObject("GameFontDisableSmall")
	end
	return b
end

local function HostSize()
	if FriendsFrame and FriendsFrame.GetWidth then
		local w, h = FriendsFrame:GetWidth(), FriendsFrame:GetHeight()
		if w and w > 200 and h and h > 200 then return w, h end
	end
	return DEFAULT_W, DEFAULT_H
end

local function CreateMain()
	local ok, f = pcall(CreateFrame, "Frame", "OlympusFrame", UIParent, "PortraitFrameTemplate")
	if ok and f and f.CloseButton then
		f.hasPortrait = true
	else
		if ok and f then f:Hide() end
		ns.Log("PortraitFrameTemplate unavailable, using BasicFrameTemplateWithInset")
		f = CreateFrame("Frame", "OlympusFrameBasic", UIParent, "BasicFrameTemplateWithInset")
	end
	f:SetSize(HostSize())
	f:SetPoint("CENTER", 0, 40)
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self.docked = false
	end)
	f:Hide()
	tinsert(UISpecialFrames, f:GetName())

	if f.SetTitle then
		f:SetTitle(L.TITLE)
	elseif f.TitleText then
		f.TitleText:SetText(L.TITLE)
	elseif f.TitleContainer and f.TitleContainer.TitleText then
		f.TitleContainer.TitleText:SetText(L.TITLE)
	end
	if f.hasPortrait then
		local portrait = f.portrait or f.Portrait or (f.PortraitContainer and f.PortraitContainer.portrait)
		if portrait then
			portrait:SetTexture(ns.LOGO)
			portrait:SetTexCoord(0, 1, 0, 1)
			if portrait.SetMask and not portrait.olympusMasked then
				portrait.olympusMasked = pcall(portrait.SetMask, portrait, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
			end
		elseif f.SetPortraitToAsset then
			pcall(f.SetPortraitToAsset, f, ns.LOGO)
		end
	end

	-- One dark panel over the whole interior, like the Guild window (its inside is near
	-- black, not the lighter marble of the plain portrait frame).
	-- Same tones as the Guild window, measured from a screenshot: the header strip is a
	-- warm grey-brown, the list and everything below it is near black. Textures (not child
	-- frames) so they stay behind the window's own header text.
	local head = f:CreateTexture(nil, "BACKGROUND", nil, 7)
	head:SetPoint("TOPLEFT", 4, -24)
	head:SetPoint("TOPRIGHT", -6, -24)
	head:SetHeight(34)
	head:SetColorTexture(1, 1, 1, 1)
	if head.SetGradient and CreateColor then
		pcall(head.SetGradient, head, "VERTICAL", CreateColor(0.16, 0.145, 0.13, 1), CreateColor(0.09, 0.08, 0.07, 1))
	else
		head:SetColorTexture(0.14, 0.125, 0.11, 1)
	end
	local body = f:CreateTexture(nil, "BACKGROUND", nil, 7)
	body:SetPoint("TOPLEFT", 4, -58)
	body:SetPoint("BOTTOMRIGHT", -6, 32)
	body:SetColorTexture(0.051, 0.051, 0.051, 1)
	f.head, f.body = head, body

	-- Header row (where the Guild window has "Show Offline Members")
	local hx = f.hasPortrait and 62 or 12
	f.total = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.total:SetPoint("TOPLEFT", hx, -28)
	f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.sub:SetPoint("TOPLEFT", f.total, "BOTTOMLEFT", 0, -1)

	-- Column titles
	f.colHeader = CreateFrame("Frame", nil, f)
	f.colHeader:SetPoint("TOPLEFT", 8, -58)
	f.colHeader:SetPoint("TOPRIGHT", -28, -58)
	f.colHeader:SetHeight(20)
	f.colHeader.buttons = {}
	for c = 1, 4 do
		local b
		for _, template in ipairs({ "GuildFrameColumnHeaderTemplate", "WhoFrameColumnHeaderTemplate" }) do
			local okB, res = pcall(CreateFrame, "Button", "OlympusColumnHeader" .. c .. template, f.colHeader, template)
			if okB and res and res.GetFontString then b = res break end
		end
		if not b then
			b = CreateFrame("Button", nil, f.colHeader)
			b:SetNormalFontObject("GameFontNormalSmall")
			b:SetText(" ")
		end
		b:SetHeight(20)
		b:SetScript("OnClick", function(self)
			if self.sortKey then
				ns.Views.SortBy(self.sortKey)
				UI.Refresh()
			end
		end)
		f.colHeader.buttons[c] = b
	end

	-- List
	local scroll = CreateFrame("ScrollFrame", "OlympusScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("BOTTOMRIGHT", -30, 36 + DETAIL_H + 8)
	f.scroll = scroll
	f.views = {}
	for _, t in ipairs(TABS) do
		local v = CreateFrame("Frame", nil, scroll)
		v:SetSize(10, 10)
		v:Hide()
		f.views[t.key] = v
	end

	-- Detail box (like "Guild Message Of The Day")
	local okDetail, detail = pcall(CreateFrame, "Frame", nil, f, "InsetFrameTemplate")
	if not okDetail or not detail then detail = CreateFrame("Frame", nil, f) end
	detail:SetPoint("BOTTOMLEFT", 6, 36)
	detail:SetPoint("BOTTOMRIGHT", -6, 36)
	detail:SetHeight(DETAIL_H)
	f.detailTitle = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.detailTitle:SetPoint("TOPLEFT", 8, -6)
	f.detailTitle:SetPoint("TOPRIGHT", -8, -6)
	f.detailTitle:SetJustifyH("LEFT")
	f.detailText = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.detailText:SetPoint("TOPLEFT", f.detailTitle, "BOTTOMLEFT", 0, -3)
	f.detailText:SetPoint("RIGHT", -8, 0)
	f.detailText:SetJustifyH("LEFT")
	f.detailText:SetJustifyV("TOP")
	f.detailText:SetHeight(DETAIL_H - 26)
	f.detail = detail
	f.detailButtons = {}
	for i = 1, 3 do
		local b = Button(detail, 90, 18)
		if i == 1 then b:SetPoint("BOTTOMLEFT", 6, 5) else b:SetPoint("LEFT", f.detailButtons[i - 1], "RIGHT", 3, 0) end
		b:Hide()
		f.detailButtons[i] = b
	end

	-- Bottom buttons
	f.buttons = {}
	for i = 1, 3 do
		local b = Button(f, 10, 22)
		f.buttons[i] = b
	end

	-- Tabs
	f.tabs = {}
	for i, t in ipairs(TABS) do
		local okTab, tab = pcall(CreateFrame, "Button", f:GetName() .. "Tab" .. i, f, "CharacterFrameTabButtonTemplate")
		if not okTab or not tab then
			tab = Button(f, 80, 22)
		end
		tab:SetID(i)
		tab:SetText(L[t.label])
		if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
		if i == 1 then
			tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 10, 2)
		else
			tab:SetPoint("LEFT", f.tabs[i - 1], "RIGHT", -15, 0)
		end
		tab:SetScript("OnClick", function() UI.SelectTab(t.key) end)
		tab.key = t.key
		f.tabs[i] = tab
	end
	f.numTabs = #TABS

	local elapsed = 0
	f:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed > 5 then
			elapsed = 0
			UI.Refresh()
		end
	end)
	f:SetScript("OnShow", function() UI.Refresh() end)
	f:SetScript("OnHide", function() if personFrame then personFrame:Hide() end end)
	f:SetScript("OnSizeChanged", function() UI.Layout() end)
	return f
end

-- Positions that depend on the window width (buttons, columns, list width).
function UI.Layout()
	if not main then return end
	local w = main:GetWidth()
	local bw = math.floor((w - 20) / 3)
	for i, b in ipairs(main.buttons) do
		b:SetWidth(bw)
		b:ClearAllPoints()
		if i == 1 then b:SetPoint("BOTTOMLEFT", 8, 8) else b:SetPoint("LEFT", main.buttons[i - 1], "RIGHT", 2, 0) end
	end
	local hasCols = ns.Views.COLUMNS[main.tab] ~= nil and main.tab == "census"
	main.colHeader:SetShown(hasCols)
	main.scroll:ClearAllPoints()
	main.scroll:SetPoint("TOPLEFT", 10, hasCols and -80 or -64)
	main.scroll:SetPoint("BOTTOMRIGHT", -30, 36 + DETAIL_H + 8)
	local listW = w - 42
	for _, v in pairs(main.views) do v:SetWidth(listW) end
	if hasCols then
		local layout = ns.Views.COLUMNS[main.tab]
		local x = 0
		for c, b in ipairs(main.colHeader.buttons) do
			local col = layout[c]
			if col then
				local width = math.floor(col.w * (listW + 4))
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", main.colHeader, "TOPLEFT", x, 0)
				if WhoFrameColumn_SetWidth then pcall(WhoFrameColumn_SetWidth, b, width) else b:SetWidth(width) end
				b:SetWidth(width)
				b:SetText(L[col.key])
				b.sortKey = col.sort
				b:Show()
				x = x + width - 2
			else
				b:Hide()
			end
		end
	end
end

StaticPopupDialogs["OLYMPUS_DECREE"] = {
	text = "%s",
	button1 = ACCEPT or "Accept",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	maxLetters = 100,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then eb:SetText("") eb:SetFocus() end
	end,
	OnAccept = function(self, kind)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("decree send", ns.Decree.Send, kind, eb and eb:GetText() or "")
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		ns.SafeCall("decree send", ns.Decree.Send, parent.data, self:GetText())
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_CLEAR_INSPECT"] = {
	text = "Olympus: clear every inspection result?",
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function() ns.SafeCall("clear inspect", ns.Inspect.Clear) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function SetButtons(list, defs)
	for i, b in ipairs(list) do
		local def = defs and defs[i]
		if def then
			local label = L[def[1]]
			if def[1] == "PATROL_BTN" then label = ns.Inspect.IsPatrolling() and L.PATROL_STOP or L.PATROL_START end
			b:SetText(label)
			b:SetScript("OnClick", function() ns.SafeCall("button " .. def[1], def[2]) end)
			local tip = rawget(L, def[1] .. "_TIP")
			b:SetScript("OnEnter", tip and function(self)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:AddLine(label, 1, 0.82, 0)
				GameTooltip:AddLine(tip, 1, 1, 1, true)
				GameTooltip:Show()
			end or nil)
			b:SetScript("OnLeave", function() GameTooltip:Hide() end)
			b:Show()
		else
			b:Hide()
		end
	end
end

function UI.SelectTab(key)
	main = main or CreateMain()
	main.tab = key
	for k, v in pairs(main.views) do v:SetShown(k == key) end
	main.scroll:SetScrollChild(main.views[key])
	main.scroll:SetVerticalScroll(0)
	for i, tab in ipairs(main.tabs) do
		if tab.key == key then
			if PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, tab) end
			main.selectedTab = i
		elseif PanelTemplates_DeselectTab then
			pcall(PanelTemplates_DeselectTab, tab)
		end
	end
	UI.Layout()
	if not main:IsShown() then main:Show() end
	UI.Refresh()
end

function UI.Refresh()
	if not main or not main:IsShown() then return end
	ns.SafeCall("ui refresh", function()
		local s = ns.Data.Summary()
		local F = ns.FormatNumber
		main.total:SetText(L.ARMY_TOTAL:format(F(s.total)))
		main.sub:SetText(L.ARMY_SUB:format(F(s.online), s.fresh, ns.Ago(s.newest)))
		local lines, title, text = ns.Views.Build(main.tab)
		ns.Views.Render(main.views[main.tab], lines, ns.Views.COLUMNS[main.tab])
		main.detailTitle:SetText(title or "")
		main.detailText:SetText(text or "")
		SetButtons(main.buttons, BUTTONS[main.tab])
		SetButtons(main.detailButtons, DETAIL_BUTTONS[main.tab])
		local hasDetailButtons = DETAIL_BUTTONS[main.tab] ~= nil
		main.detailText:SetHeight(DETAIL_H - (hasDetailButtons and 46 or 26))
	end)
end

-- Open glued to the right of a Blizzard window (the Guild window), same size, and
-- close together with it.
function UI.OpenDocked(host, tab)
	main = main or CreateMain()
	main:SetSize(host:GetWidth(), host:GetHeight())
	main:ClearAllPoints()
	main:SetPoint("TOPLEFT", host, "TOPRIGHT", -2, 0)
	main.docked = true
	UI.SelectTab(tab or main.tab or "census")
end

function UI.CloseIfDocked()
	if main and main.docked and main:IsShown() then main:Hide() end
end

---------------------------------------------------------------------------
-- Person panel: like the member details the Guild window opens, docked to our window.
-- person = { name, class (code), level, zone (key), guild, rank (label), online, days,
--            note, tabard (status), onMark (function, tabards tab only) }
---------------------------------------------------------------------------

local personFrame

local function Whisper(name)
	if ChatFrame_SendTell then ChatFrame_SendTell(name) else ChatFrame_OpenChat("/w " .. name .. " ") end
end

local function Invite(name)
	if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(name) elseif InviteUnit then InviteUnit(name) end
end

local function Who(name)
	local query = ('n-"%s"'):format(name)
	if C_FriendList and C_FriendList.SendWho then C_FriendList.SendWho(query) elseif SendWho then SendWho(query) end
end

local function CreatePersonFrame()
	local f = CreateFrame("Frame", "OlympusPersonFrame", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(230, 210)
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:Hide()
	tinsert(UISpecialFrames, "OlympusPersonFrame")
	f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.name:SetPoint("TOPLEFT", 14, -32)
	f.name:SetPoint("TOPRIGHT", -14, -32)
	f.name:SetJustifyH("LEFT")
	f.lines = {}
	for i = 1, 6 do
		local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("TOPLEFT", 14, -54 - (i - 1) * 15)
		fs:SetPoint("RIGHT", -14, 0)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
		f.lines[i] = fs
	end
	local function Btn(label, x, y, w)
		local b = Button(f, w, 22)
		b:SetPoint("BOTTOMLEFT", x, y)
		b:SetText(label)
		return b
	end
	f.whisper = Btn(L.WHISPER, 10, 34, 104)
	f.invite = Btn(L.INVITE, 116, 34, 104)
	f.who = Btn(L.WHO, 10, 10, 104)
	f.mark = Btn(L.MARK_BTN, 116, 10, 104)
	f.whisper:SetScript("OnClick", function() ns.SafeCall("whisper", Whisper, f.person.name) end)
	f.invite:SetScript("OnClick", function() ns.SafeCall("invite", Invite, f.person.name) end)
	f.who:SetScript("OnClick", function() ns.SafeCall("who", Who, f.person.name) end)
	f.mark:SetScript("OnClick", function()
		if f.person.onMark then ns.SafeCall("mark", f.person.onMark) end
		f:Hide()
	end)
	return f
end

function UI.ShowPerson(p)
	if not p or not p.name then return end
	personFrame = personFrame or CreatePersonFrame()
	local f = personFrame
	f.person = p
	local file = p.class and ns.CLASS_FILES[p.class] or p.class
	local color = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
	f.name:SetText(color and ("|c%s%s|r"):format(color.colorStr, p.name) or p.name)
	if f.TitleText then f.TitleText:SetText(p.guild and ("<" .. p.guild .. ">") or L.TITLE) end
	local className = (file and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file]) or ""
	local rows = {}
	if p.level or className ~= "" then rows[#rows + 1] = (p.level and (L.LEVEL_N:format(p.level) .. " ") or "") .. className end
	if p.rank then rows[#rows + 1] = "|cffffd200" .. p.rank .. "|r" end
	if p.online then
		rows[#rows + 1] = "|cff40ff40" .. L.ONLINE_NOW .. "|r" .. (p.zone and ("  -  " .. ns.Zones.NameForKey(p.zone)) or "")
	elseif p.online == false then
		rows[#rows + 1] = "|cff9d9d9d" .. ((p.days or 0) >= 1 and L.OFFLINE_DAYS:format(math.floor(p.days)) or L.OFFLINE_TODAY) .. "|r"
	end
	if p.tabard then rows[#rows + 1] = L.TABARD .. ": " .. p.tabard end
	if p.note then rows[#rows + 1] = '|cffff8080"' .. p.note .. '"|r' end
	for i, fs in ipairs(f.lines) do fs:SetText(rows[i] or "") end
	f.mark:SetShown(p.onMark ~= nil)
	f.invite:SetEnabled(p.online ~= false)
	f.whisper:SetEnabled(p.online ~= false)
	f:ClearAllPoints()
	if main and main:IsShown() then
		f:SetPoint("TOPLEFT", main, "TOPRIGHT", -2, -28)
	else
		f:SetPoint("CENTER")
	end
	f:Show()
end

function UI.IsShown() return main and main:IsShown() end
function UI.IsDocked() return main and main.docked end

function UI.StatusLine()
	if ns.db.demo then return L.STATUS_DEMO end
	local guild = GetGuildInfo("player")
	if not guild then return L.STATUS_NOGUILD end
	if not ns.IsFederation(guild) then return L.STATUS_NOTFED:format(guild) end
	local c = ns.Comm
	local users = c.PeerCount() + 1
	if c.isReporter or not c.reporterName then return L.STATUS_REPORTER:format(guild, users) end
	return L.STATUS_PEER:format(guild, c.reporterName, users)
end

function UI.Toggle()
	if main and main:IsShown() then
		main:Hide()
		return
	end
	UI.SelectTab(main and main.tab or "census")
end

ns.On("DATA_CHANGED", function() UI.Refresh() end)
ns.On("MAP_TOGGLED", function() UI.Refresh() end)
ns.On("INSPECT_CHANGED", function() if main and main.tab == "heraldry" then UI.Refresh() end end)
ns.On("LAYERS_CHANGED", function() if main and main.tab == "decrees" then UI.Refresh() end end)
ns.On("DECREES_CHANGED", function() UI.Refresh() end)

---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Copy box (Discord text, bug report)
---------------------------------------------------------------------------

local copyFrame
function UI.ShowCopy(title, text)
	if not copyFrame then
		local f = CreateFrame("Frame", "OlympusCopyFrame", UIParent, "BasicFrameTemplateWithInset")
		f:SetSize(520, 340)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		f:SetMovable(true)
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		tinsert(UISpecialFrames, "OlympusCopyFrame")
		local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		hint:SetPoint("BOTTOM", 0, 10)
		hint:SetText(L.COPY_HINT)
		local scroll = CreateFrame("ScrollFrame", "OlympusCopyScroll", f, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 12, -30)
		scroll:SetPoint("BOTTOMRIGHT", -30, 28)
		local eb = CreateFrame("EditBox", nil, scroll)
		eb:SetMultiLine(true)
		eb:SetFontObject(ChatFontNormal)
		eb:SetWidth(470)
		eb:SetHeight(280)
		eb:SetAutoFocus(false)
		eb:SetScript("OnEscapePressed", function() f:Hide() end)
		eb:SetScript("OnTextChanged", function(self, userInput)
			if userInput then -- read only
				self:SetText(f.text or "")
				self:HighlightText()
			end
		end)
		scroll:SetScrollChild(eb)
		f.eb = eb
		copyFrame = f
	end
	if copyFrame.TitleText then copyFrame.TitleText:SetText(title) end
	copyFrame.text = text
	copyFrame.eb:SetText(text)
	copyFrame:Show()
	copyFrame.eb:SetFocus()
	copyFrame.eb:HighlightText()
end

---------------------------------------------------------------------------
-- Minimap button (drag around the minimap, angle is saved)
---------------------------------------------------------------------------

local minimapButton

local function PositionMinimapButton()
	local angle = math.rad(ns.db.minimapAngle or 200)
	local radius = (Minimap:GetWidth() / 2) + 10
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function CreateMinimapButton()
	local b = ns.MakeRoundButton("OlympusMinimapButton", Minimap, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")

	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" then ns.Map.SetEnabled(not ns.db.showMap) else UI.Toggle() end
	end)
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			ns.db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
			PositionMinimapButton()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnEnter", function(self)
		local s = ns.Data.Summary()
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L.TITLE, 1, 0.82, 0)
		GameTooltip:AddLine(L.ARMY_TOTAL:format(ns.FormatNumber(s.total)), 1, 1, 1)
		GameTooltip:AddLine(L.ARMY_SUB:format(ns.FormatNumber(s.online), s.fresh, ns.Ago(s.newest)), 0.8, 0.8, 0.8)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L.MINIMAP_LEFT, 0.6, 0.6, 0.6)
		GameTooltip:AddLine(L.MINIMAP_RIGHT, 0.6, 0.6, 0.6)
		GameTooltip:AddLine(L.MINIMAP_DRAG, 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

function UI.UpdateMinimapButton()
	minimapButton = minimapButton or CreateMinimapButton()
	PositionMinimapButton()
	minimapButton:SetShown(not ns.db.hideMinimap)
end

ns.On("LOGIN", function()
	UI.UpdateMinimapButton()
	ns.Log("ui ready")
end)
