local ADDON, ns = ...
local L = ns.L

-- The Olympus window mirrors Blizzard's (old) Guild window: same size and frame, a header,
-- column titles, a list, a detail box (like "Guild Message of the Day"), three buttons
-- and tabs along the bottom. Opened from the guild window (the old Guild tab or the new
-- Guild & Communities window, see GuildFrame.lua) it docks right next to it, so it reads
-- as a continuation of that window. Created on first open.

local UI = {}
ns.UI = UI

local DEFAULT_W, DEFAULT_H = 338, 424
local DETAIL_H = 78
local main
local personFrame -- the person details panel (created on first use, further below)

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

-- Buttons shown to players who are not in an Olympus guild.
local RECRUIT_BUTTONS = {
	{ "RECRUIT_FIND", function() ns.Recruit.Search() end },
	{ "RECRUIT_NEXT", function() ns.Recruit.PromptNext(ns.Recruit.lastContact and ns.Recruit.lastContact.guild) end },
}

-- Small extra buttons inside the detail box (only where needed).
local DETAIL_BUTTONS = {
	heraldry = {
		{ "SHAME_BTN", function() ns.Inspect.PublishShame() end },
		{ "HERALDRY_BTN", DecreeAction("HERALDRY") },
		{ "CLEAR", function() StaticPopup_Show("OLYMPUS_CLEAR_INSPECT") end },
	},
}

local function SetButtonFont(b, small)
	b:SetNormalFontObject(small and "GameFontNormalSmall" or "GameFontNormal")
	b:SetHighlightFontObject(small and "GameFontHighlightSmall" or "GameFontHighlight")
	b:SetDisabledFontObject(small and "GameFontDisableSmall" or "GameFontDisable")
end

local function Button(parent, width, height)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, height or 22)
	b.small = height and height < 22
	if b.small then SetButtonFont(b, true) end
	return b
end

-- Keeps a label inside its button (long translations, the narrow Forever window): it
-- drops to the small font, and is cut with "..." only if even that does not fit.
local function FitLabel(b)
	local fs = b:GetFontString()
	if not fs then return end
	SetButtonFont(b, b.small)
	fs:SetWidth(0)
	local room = b:GetWidth() - 12
	local textW = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
	if not b.small and textW > room then SetButtonFont(b, true) end
	if fs.SetWordWrap then fs:SetWordWrap(false) end
	fs:SetWidth(room)
end

-- The same for a one-line font string: the first of `fonts` the text fits `room` in, else
-- the last one, cut with "...". The string must be left-justified and not wrap.
local function FitText(fs, room, fonts)
	fs:SetWidth(0)
	for _, font in ipairs(fonts) do
		fs:SetFontObject(font)
		local textW = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
		if textW <= room then break end
	end
	fs:SetWidth(math.max(1, room))
end

-- Header lines end this far from the window's right edge: the big line keeps clear of
-- the close button column (24 wide on Forever, 32 on the Classic clients), the small one
-- sits lower and only keeps off the border.
local HEADER_RIGHT, SUB_RIGHT = 26, 8

-- Tabs. The tab template is the same atlas one on every client we support
-- (PanelTabButtonTemplate with LeftActive & co., also in Classic Era 1.15.9 and Anniversary
-- 2.5.6), but the code that sizes it is not. Classic's PanelTemplates_TabResize makes a tab
-- its text plus both end caps, which the old -15 overlap was made for. Mainline's (Forever)
-- makes it the text plus 20 (TAB_SIDES_PADDING), and Blizzard spaces those 3 apart
-- (PanelTemplates_AnchorTabs, which only ships with that code) with the first at x 5
-- (FriendsFrame): at -15 they pile up on each other.
function UI.TabStyle(tab)
	if tab and tab.LeftActive and PanelTemplates_AnchorTabs then return "mainline" end
	return "classic"
end

-- The anchor of tab i (prev is tab i - 1) under `frame`.
function UI.TabAnchor(style, i, frame, prev)
	if style == "mainline" then
		if i == 1 then return "TOPLEFT", frame, "BOTTOMLEFT", 5, 2 end
		return "TOPLEFT", prev, "TOPRIGHT", 3, 0
	end
	if i == 1 then return "TOPLEFT", frame, "BOTTOMLEFT", 10, 2 end
	return "LEFT", prev, "RIGHT", -15, 0
end

-- Blizzard's Issue Reporter (Blizzard_PTRFeedback, only on beta and PTR clients such as
-- the Forever beta) is a small draggable box with a bug button under it, by default at the
-- bottom centre of the screen: right over the buttons and tabs of our window at its
-- default place. It is Blizzard's, so it is never moved or hidden: our window steps up.
local ISSUE_GAP = 4

-- A region's rect in screen pixels, or nil if it is not laid out.
local function ScreenRect(region)
	if type(region) ~= "table" or not region.GetRect then return nil end
	local left, bottom, width, height = region:GetRect()
	if not left or not bottom or not width or not height then return nil end
	local s = region.GetEffectiveScale and region:GetEffectiveScale() or 1
	return { left = left * s, bottom = bottom * s, right = (left + width) * s, top = (bottom + height) * s }
end

local function Union(a, b)
	if not a then return b end
	if not b then return a end
	return { left = math.min(a.left, b.left), bottom = math.min(a.bottom, b.bottom),
		right = math.max(a.right, b.right), top = math.max(a.top, b.top) }
end

-- How far up a window must go to clear an obstacle (screen rects, pixels): nil when they
-- do not overlap, or when that would push the window's top past screenTop (it stays put).
function UI.ClearUp(win, obstacle, screenTop, gap)
	if not win or not obstacle or not screenTop then return nil end
	if win.left >= obstacle.right or win.right <= obstacle.left then return nil end
	if win.bottom >= obstacle.top or win.top <= obstacle.bottom then return nil end
	local dy = obstacle.top + (gap or 0) - win.bottom
	if win.top + dy > screenTop then return nil end
	return dy
end

-- The Issue Reporter's screen rect with its border, bug button and info button, if shown.
local function IssueReporterRect()
	local r = _G.PTR_IssueReporter
	if type(r) ~= "table" or not r.IsVisible or not r:IsVisible() then return nil end
	local rect
	for _, part in ipairs({ r, r.Border, r.Body, r.ReportBug, r.InfoButton }) do
		if type(part) == "table" and part.IsVisible and part:IsVisible() then rect = Union(rect, ScreenRect(part)) end
	end
	return rect
end

-- Moves `frame` (held by one anchor) up just enough that `parts`, what it covers on screen
-- (the frame, the tabs hanging below it), clear the Issue Reporter. Called when the frame
-- shows, never continuously. Returns true if the frame was not laid out yet.
local function StepAboveIssueReporter(frame, parts)
	local obstacle = IssueReporterRect()
	if not obstacle or not frame:IsShown() or frame:GetNumPoints() ~= 1 then return end
	local win
	for _, part in ipairs(parts) do
		if part:IsShown() then win = Union(win, ScreenRect(part)) end
	end
	if not ScreenRect(frame) then return true end
	local screen = ScreenRect(UIParent)
	local dy = screen and UI.ClearUp(win, obstacle, screen.top, ISSUE_GAP)
	if not dy then return end
	local point, rel, relPoint, x, y = frame:GetPoint(1)
	frame:ClearAllPoints()
	frame:SetPoint(point, rel, relPoint, x, y + dy / frame:GetEffectiveScale())
	ns.Log("%s moved up %d to clear the Issue Reporter", tostring(frame:GetName()), math.floor(dy + 0.5))
end

-- Runs a check now, and once more on the next frame if the frame had no rect yet (a
-- window shown the moment it was made).
local function ClearOfIssueReporter(check)
	if check() and C_Timer and C_Timer.After then
		C_Timer.After(0, function() ns.SafeCall("issue reporter", check) end)
	end
end

-- Our window at its own place (never docked or dragged) steps above the Issue Reporter.
local function MainClearOfIssueReporter()
	if not main or main.docked or main.movedByPlayer then return end
	local parts = { main }
	for _, tab in ipairs(main.tabs) do parts[#parts + 1] = tab end
	return StepAboveIssueReporter(main, parts)
end

-- The Social window's size, which is the old Guild window's (the Guild tab fills it).
local function SocialSize()
	if FriendsFrame and FriendsFrame.GetWidth then
		local w, h = FriendsFrame:GetWidth(), FriendsFrame:GetHeight()
		if w and w > 200 and h and h > 200 then return w, h end
	end
	return DEFAULT_W, DEFAULT_H
end

-- Size when docked to a host of hostW x hostH, next to a Social window of baseW x baseH.
-- The old Guild tab lends its whole size, as it always did. The new guild windows only
-- lend their height (the Communities window is 814 wide maximized, 322 minimized): the
-- width stays the Social window's, the width our list is laid out for.
function UI.DockSize(hostW, hostH, heightOnly, baseW, baseH)
	baseW, baseH = baseW or DEFAULT_W, baseH or DEFAULT_H
	local okW, okH = hostW and hostW > 200, hostH and hostH > 200
	if heightOnly then return baseW, okH and hostH or baseH end
	if okW and okH then return hostW, hostH end
	return baseW, baseH
end

-- Size of a new window: as if docked to the guild window in use (GuildFrame.lua knows
-- which), else the Social window's.
local function HostSize()
	local hook = ns.GuildFrameHook
	local host = hook and hook.ActiveHost and hook.ActiveHost()
	if host and host.dock and host.dock.GetWidth then
		return UI.DockSize(host.dock:GetWidth(), host.dock:GetHeight(), host.heightOnly, SocialSize())
	end
	return SocialSize()
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
		self.movedByPlayer = true -- where the player puts it, it stays
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
	-- Like the Guild window: the frame keeps its own mottled grey texture, and the list
	-- (with its column headers) sits in a dark mottled box with a border, the same box
	-- style as the detail box below (Blizzard's inset). Created early so later frames
	-- (column headers, list) draw on top of it.
	local okBox, box = pcall(CreateFrame, "Frame", nil, f, "InsetFrameTemplate")
	if okBox and box then
		box:SetPoint("TOPLEFT", 6, -56)
		box:SetPoint("BOTTOMRIGHT", -6, 36 + DETAIL_H + 4)
		f.listBox = box
	end

	-- Header row (where the Guild window has "Show Offline Members")
	-- One line each, kept inside the window by FitHeader (long texts, the narrow window).
	local hx = f.hasPortrait and 62 or 12
	f.headerX = hx
	f.total = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.total:SetPoint("TOPLEFT", hx, -28)
	f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.sub:SetPoint("TOPLEFT", f.total, "BOTTOMLEFT", 0, -1)
	for _, fs in ipairs({ f.total, f.sub }) do
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
	end

	-- Column titles
	f.colHeader = CreateFrame("Frame", nil, f)
	f.colHeader:SetPoint("TOPLEFT", 8, -58)
	f.colHeader:SetPoint("TOPRIGHT", -28, -58)
	f.colHeader:SetHeight(20)
	if f.listBox then f.colHeader:SetFrameLevel(f.listBox:GetFrameLevel() + 2) end
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
	if f.listBox then scroll:SetFrameLevel(f.listBox:GetFrameLevel() + 2) end
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
		-- Tab templates differ between clients (Classic has CharacterFrameTabButtonTemplate,
		-- newer clients like Forever have PanelTabButtonTemplate). Use the first that really
		-- builds a tab; otherwise fall back to a plain button and mark selection ourselves.
		local tab
		for n, template in ipairs({ "PanelTabButtonTemplate", "CharacterFrameTabButtonTemplate", "TabButtonTemplate" }) do
			local name = f:GetName() .. "Tab" .. n .. "_" .. i
			local okTab, res = pcall(CreateFrame, "Button", name, f, template)
			if okTab and res and (res.Left or res.LeftActive or _G[name .. "Left"] or _G[name .. "LeftDisabled"]) then
				tab = res
				UI.tabTemplate = template
				break
			elseif okTab and res then
				res:Hide()
			end
		end
		if not tab then
			tab = Button(f, 80, 22)
			tab.isFallback = true
			UI.tabTemplate = "fallback"
		end
		tab:SetID(i)
		tab:SetText(L[t.label])
		if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
		UI.tabStyle = UI.TabStyle(tab)
		tab:SetPoint(UI.TabAnchor(UI.tabStyle, i, f, f.tabs[i - 1]))
		tab:SetScript("OnClick", function() ns.SafeCall("tab " .. t.key, UI.SelectTab, t.key) end)
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
	f:SetScript("OnShow", function()
		UI.Refresh()
		ns.SafeCall("issue reporter", ClearOfIssueReporter, MainClearOfIssueReporter)
	end)
	f:SetScript("OnHide", function() if personFrame then personFrame:Hide() end end)
	f:SetScript("OnSizeChanged", function() UI.Layout() end)
	return f
end

-- The bottom buttons share the window width: three on a tab, two on the Join screen.
local function LayoutButtons()
	local shown = {}
	for _, b in ipairs(main.buttons) do
		if b:IsShown() then shown[#shown + 1] = b end
	end
	if #shown == 0 then shown = main.buttons end
	local bw = math.floor((main:GetWidth() - 16 - 2 * (#shown - 1)) / #shown)
	for i, b in ipairs(shown) do
		b:SetWidth(bw)
		b:ClearAllPoints()
		if i == 1 then b:SetPoint("BOTTOMLEFT", 8, 8) else b:SetPoint("LEFT", shown[i - 1], "RIGHT", 2, 0) end
		FitLabel(b)
	end
end

local function FitHeader()
	local room = main:GetWidth() - main.headerX
	FitText(main.total, room - HEADER_RIGHT, { "GameFontNormalLarge", "GameFontNormal" })
	FitText(main.sub, room - SUB_RIGHT, { "GameFontHighlightSmall" })
end

-- Positions that depend on the window width (buttons, columns, list width) and on
-- membership (the Join screen has no column titles).
function UI.Layout()
	if not main then return end
	local w = main:GetWidth()
	LayoutButtons()
	FitHeader()
	main.layoutLocked = not ns.IsMember()
	local hasCols = not main.layoutLocked and ns.Views.COLUMNS[main.tab] ~= nil and main.tab == "census"
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
			FitLabel(b)
		else
			b:Hide()
		end
	end
	if list == main.buttons then LayoutButtons() end
end

function UI.SelectTab(key)
	main = main or CreateMain()
	main.tab = key
	for k, v in pairs(main.views) do v:SetShown(k == key) end
	main.scroll:SetScrollChild(main.views[key])
	main.scroll:SetVerticalScroll(0)
	for i, tab in ipairs(main.tabs) do
		if tab.isFallback then
			-- Plain buttons: the selected one stays lit and uses white text.
			if tab.key == key then
				tab:LockHighlight()
				tab:SetNormalFontObject("GameFontHighlight")
				main.selectedTab = i
			else
				tab:UnlockHighlight()
				tab:SetNormalFontObject("GameFontNormal")
			end
		elseif tab.key == key then
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
		main.sub:SetText(L.ARMY_SUB:format(F(s.online), s.fresh, ns.Ago(s.newest)) .. "  ·  " .. (GetRealmName and GetRealmName() or ""))
		-- Outside an Olympus guild nothing but the Join Olympus screen is shown.
		local locked = not ns.IsMember()
		-- Joined or left a guild while the window is open: lay it out again.
		if locked ~= main.layoutLocked then UI.Layout() end
		local lines, title, text
		if locked then
			-- Not an Olympus member yet: the only thing on offer is joining one.
			lines = ns.Views.RecruitLines()
			title, text = L.MEMBERS_ONLY, L.MEMBERS_ONLY_HINT
			local header, sub = ns.Recruit.Roast()
			main.total:SetText(header)
			main.sub:SetText(sub)
		else
			lines, title, text = ns.Views.Build(main.tab)
		end
		FitHeader()
		ns.Views.Render(main.views[main.tab], lines, not locked and ns.Views.COLUMNS[main.tab] or nil)
		main.detailTitle:SetText(title or "")
		main.detailText:SetText(text or "")
		SetButtons(main.buttons, locked and RECRUIT_BUTTONS or BUTTONS[main.tab])
		for _, tab in ipairs(main.tabs) do tab:SetShown(not locked) end
		SetButtons(main.detailButtons, not locked and DETAIL_BUTTONS[main.tab] or nil)
		local hasDetailButtons = not locked and DETAIL_BUTTONS[main.tab] ~= nil
		main.detailText:SetHeight(DETAIL_H - (hasDetailButtons and 46 or 26))
	end)
end

-- Open glued to the right of a Blizzard window (the guild window the button was clicked
-- in), sized by UI.DockSize, and close together with it (GuildFrame.lua hooks that).
function UI.OpenDocked(host, tab, heightOnly)
	main = main or CreateMain()
	main.host, main.heightOnly = host, heightOnly
	main:SetSize(UI.DockSize(host:GetWidth(), host:GetHeight(), heightOnly, SocialSize()))
	main:ClearAllPoints()
	main:SetPoint("TOPLEFT", host, "TOPRIGHT", -2, 0)
	main.docked = true
	UI.SelectTab(tab or main.tab or "census")
end

-- The host was resized while we are docked to it (the Communities window can be
-- minimized and maximized): take its new height.
function UI.FollowHost(host)
	if main and main.docked and main.host == host then
		main:SetSize(UI.DockSize(host:GetWidth(), host:GetHeight(), main.heightOnly, SocialSize()))
	end
end

-- Closes the window if it is docked: to `host` when given, to anything otherwise.
function UI.CloseIfDocked(host)
	if main and main.docked and main:IsShown() and (host == nil or main.host == host) then main:Hide() end
end

---------------------------------------------------------------------------
-- Person panel: like the member details the Guild window opens, docked to our window.
-- person = { name, class (code), level, zone (key), guild, rank (label), online, days,
--            note, tabard (status), onMark (function, tabards tab only) }
---------------------------------------------------------------------------

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
	-- Guild window + our window + this card can run past the right edge (the Communities
	-- window alone is 814 wide).
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:Hide()
	tinsert(UISpecialFrames, "OlympusPersonFrame")
	f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.name:SetPoint("TOPLEFT", 14, -32)
	f.name:SetPoint("TOPRIGHT", -14, -32)
	f.name:SetJustifyH("LEFT")
	f.name:SetWordWrap(false) -- a long Name-Realm is fitted (UI.ShowPerson), not wrapped over the lines below
	if f.TitleText then
		-- "<guild name>", centred: kept clear of the close button on both sides.
		f.TitleText:SetWidth(f:GetWidth() - 64)
		f.TitleText:SetWordWrap(false)
	end
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
		FitLabel(b)
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
	FitText(f.name, f:GetWidth() - 28, { "GameFontNormalLarge", "GameFontNormal" })
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
	-- Placed again on every show, so it can step above the Issue Reporter every time.
	ns.SafeCall("issue reporter", ClearOfIssueReporter, function() return StepAboveIssueReporter(f, { f }) end)
end

function UI.IsShown() return main and main:IsShown() end
function UI.DockedTo() return main and main.docked and main.host or nil end

function UI.StatusLine()
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
ns.On("RECRUIT_CHANGED", function() UI.Refresh() end)

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
		ns.SafeCall("minimap click", function()
			if button == "RightButton" then ns.Map.SetEnabled(not ns.db.showMap) else UI.Toggle() end
		end)
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
