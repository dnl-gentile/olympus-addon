local ADDON, ns = ...
local L = ns.L

-- The Olympus chats in the Olympus window (1.1.1): its Chat tab, right after the Realm (UI.lua's
-- TABS). The three chats ([Olympus], [Captains], [Lords]) like the chat pane of the Guild &
-- Communities window: the tabs' search box where the other tabs show the army's counts, the
-- channels the player reads where they have their column titles, each line whole in a bubble that
-- wraps (nothing to hover to read it) over the list's and the detail box's room, the 100 lines
-- Channels keeps per channel to scroll back through, a box to write in across the bottom where
-- they have their buttons (no Send button: Enter sends), and Olympus's marks by each name (the
-- King's crown, the High Council's mark, the Lords' and Captains' elite marks, Raiders and
-- Veterans bronze, the members' star, the Treasurer's coin, Stewards and Hands).
--
-- The first 1.1.1 build had it in a window of its own; the author wanted it inside the Olympus
-- window. UI.lua hands this file the window in use and where each part goes in its look
-- (ChatWindow.Attach), and the old window's calls stay as the ways to the tab: Open, Toggle and
-- Close (/ol, /olc or /oll alone, /oly talk, the minimap button's Shift-click, the Realm tab's
-- chats page) open the Olympus window on its Chat tab, on the channel asked for, and close it.
--
-- What it never does, whatever the input mode (mouse and keyboard, or Blizzard's gamepad UI):
-- - It never touches the game's chat boxes or windows: no script of theirs replaced or hooked,
--   and none opened from here (ChatFrame_OpenChat, ChatFrame_SendTell, ChatFrameUtil.*: they
--   write LAST_ACTIVE_CHAT_EDIT_BOX or CHAT_FOCUS_OVERRIDE, which the game's secure chat code
--   reads afterwards, so what the player types next runs tainted and /cast, /target, /use or
--   /click get blocked; with the gamepad UI that froze the game in 0.8.5). Every frame here is
--   Olympus's own. The Olympus tab of the game's chat (below) is made by the player, with the
--   game's own menu: Olympus only reads the game's chat windows to see it appear.
-- - Its box is Olympus's own EditBox: it never takes the keyboard by itself (SetAutoFocus(false)
--   the moment it is made, never SetFocus, never ns.Focus); the player clicks into it, with the
--   mouse or the gamepad cursor. Enter sends through Channels.Send and lets the keyboard go (as
--   the Communities box does), so movement keys go back to the game. It runs no command: a line
--   starting with "/" is kept and the player is told the game's chat box is where commands go.
-- - No game popup from it: the pinned line's takedown and a whisper go through ns.ShowDialog
--   (Olympus's own window with the gamepad UI); the Olympus window closes with Escape through
--   ns.EscapeCloses (nothing on UISpecialFrames with the gamepad UI: its X closes it there).
-- - Links in a line show their tooltip on hover (GameTooltip:SetHyperlink) and go into its own
--   box with a Shift-click; never SetItemRef, ChatEdit_InsertLink or HandleModifiedItemClick.
-- Nothing is drawn while the tab is hidden: a change marks it dirty and it redraws at most every
-- 0.2 s while shown (the census at most every 5 s).

local ChatWindow = {}
ns.ChatWindow = ChatWindow

local TAB = "chat"                                    -- its tab in the Olympus window (UI.lua)
local PILL_GAP = 4
local SEARCH_H = 20
local PAD = 8                                         -- inside a bubble
local HEADER_H = 16
local EDGE = 8                                        -- a bubble from the box's side
local SHARE = 0.82                                    -- a bubble's width, at most, of the box's
local BUBBLE_MIN = 180
local GAP_IN, GAP_OUT = 3, 10                         -- between bubbles of one writer, between writers
local GROUP_TIME = 300                                -- a pause this long starts a new header
local STICK_SLACK = 2
local THROTTLE, DATA_GAP = 0.2, 5
local LINE_H = 14                                     -- a line of text, where the client gives no height
local PIN_LINES, GUIDE_LINES = 3, 4
local MAX_NOTES = 5
local LOOK_GAP = 1                                    -- the Olympus tab awaited: the game's chat windows read this often
local GREY = "|cff9d9d9d"
local LINK_TIPS = { item = true, spell = true, enchant = true, quest = true } -- (the links Codec lets through)
local STAR = "|TInterface\\AddOns\\Olympus\\media\\borders\\star:14:14|t"
local SILVER = "nameplates-icon-elite-silver"
local BRONZE = "nameplates-icon-elite-gold"
local BRONZE_TINT = ":0:0:158:118:86" -- (Nameplates.BRONZE x 255)
local WHY = { moved = "CHATWIN_WHY_MOVED", late = "CHATWIN_WHY_LATE", failed = "CHATWIN_WHY_FAILED", left = "CHATWIN_WHY_LEFT" }
-- The pointer's arrow: the game's tutorial arrow (Blizzard_TutorialTemplates), else the chat
-- frame's own scroll-down arrow (Blizzard_SharedXML's dropdown and store templates use it).
local ARROW_ATLAS, ARROW_FILE = "NPE_ArrowDown", "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up"

local panes = {}             -- Olympus window -> its Chat tab (each look's window has its own)
local frame                  -- the Chat tab in use (a pane of `host`)
local host                   -- the Olympus window it is in
local tier                   -- the channel shown
local dirty, dataPending = false, false
local lastData = -math.huge
local unread = {}            -- tier -> lines from others since it was last looked at (while open)
local notes = {}             -- tier -> { { why, text } }: lines that were not sent, this session
local revealed = setmetatable({}, { __mode = "k" }) -- history entry -> shown despite the block terms
local stick, newCount = true, 0 -- the view follows the newest line; lines come while it doesn't
local lastAt = 0             -- the offset the view had last
local want                   -- scrolled up: the offset that keeps the line read in its place
local quiet = false          -- our own scrolling: not the player's
local acc, lookAcc = 0, 0
local tipOwner
local pointer                -- the Olympus tab awaited: Olympus's own pointer by the game's chat tab
local watching = false       -- ... and the game's chat windows read until it is there

local function Grey(s) return GREY .. s .. "|r" end
local function Gold(s) return "|cffffd200" .. s .. "|r" end
local function Green(s) return "|cff40ff40" .. s .. "|r" end
local function Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function Label(t)
	local d = ns.Channels.TIERS[t]
	return d and L[d.label] or "?"
end
local function Colour(t)
	local d = ns.Channels.TIERS[t]
	return d and d.color or { 1, 1, 1 }
end
local function Hex(c)
	local function B(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
	return ("ff%02x%02x%02x"):format(B(c[1]), B(c[2]), B(c[3]))
end
local function Finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
-- The game's own words for its menus (its global strings, in the player's language), else ours.
local function GameWord(value, fallback)
	return type(value) == "string" and value ~= "" and value or fallback
end

-- The channels this rank reads, in their order.
local function Readable()
	local C, out = ns.Channels, {}
	for _, t in ipairs(C.ORDER or {}) do
		if C.CanUse(t) then out[#out + 1] = t end
	end
	return out
end

-- A text's width as the client draws it on one line, and its height at a width (the client wraps
-- it there; without the height a client gives, whole lines of LINE_H).
local function TextWidth(fs)
	if fs.GetUnboundedStringWidth then return fs:GetUnboundedStringWidth() or 0 end
	return fs:GetStringWidth() or 0
end
local function TextHeight(fs, width)
	if fs.GetStringHeight then
		local h = fs:GetStringHeight()
		if type(h) == "number" and h > 0 then return math.ceil(h) end
	end
	return math.max(1, math.ceil(TextWidth(fs) / math.max(1, width))) * LINE_H
end

local function Tip(owner, fill)
	GameTooltip:SetOwner(owner, "ANCHOR_TOP")
	fill(GameTooltip)
	GameTooltip:Show()
	tipOwner = owner
end
local function Untip(owner)
	if owner and GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

---------------------------------------------------------------------------
-- The channel last shown: ns.db.chatWin = { tier }, account-wide (the first 1.1.1 build kept its
-- window's place and size there too; the tab has neither).
---------------------------------------------------------------------------

local function Saved()
	local p = ns.db and ns.db.chatWin
	return type(p) == "table" and p or nil
end

local function Remember(t)
	if not ns.db then return end
	local p = Saved() or {}
	p.tier = t
	ns.db.chatWin = p
end

local function MarkDirty() dirty = true end

function ChatWindow.IsShown()
	return frame ~= nil and frame:IsShown() and host ~= nil and host:IsShown() and true or false
end
local function Shown() return ChatWindow.IsShown() end

---------------------------------------------------------------------------
-- Scrolling: it follows the newest line (on opening, on a channel picked, after the player's own
-- line, on a search typed) until the player scrolls up; lines that come meanwhile show as "N new"
-- at the bottom. The client measures the scroll range a frame after the lines change (as
-- UI.KeepPlace knows): the offset is put at the end again then, while it follows.
---------------------------------------------------------------------------

local function Quietly(fn)
	quiet = true
	local ok, err = pcall(fn)
	quiet = false
	if not ok then error(err, 0) end
end

local function ShowNew()
	if not frame then return end
	local b = frame.newPill
	if newCount > 0 and not stick and frame.scroll:IsShown() then
		b:SetText(L.CHATWIN_NEW_LINES:format(newCount))
		b:Show()
	else
		b:Hide()
	end
end

local function ToBottom()
	local s = frame.scroll
	local range = math.max(0, (frame.content:GetHeight() or 0) - (s:GetHeight() or 0))
	Quietly(function() s:SetVerticalScroll(range) end)
	lastAt = s:GetVerticalScroll() or 0
end

local function ScrollToBottom()
	stick, newCount, want = true, 0, nil
	if not frame then return end
	ToBottom()
	ShowNew()
end

-- The range measured again: at its end while the view follows; scrolled up, where the line read
-- stays in its place (Render's anchor, as far as the new range reaches).
local function Held()
	if not frame then return end
	local s = frame.scroll
	local range = s:GetVerticalScrollRange() or 0
	local to
	if stick then
		to = range
	elseif want then
		to = math.min(want, range)
	else
		return
	end
	Quietly(function() s:SetVerticalScroll(to) end)
	lastAt = s:GetVerticalScroll() or 0
end

-- The player scrolled: at the end it follows again; up from where it was, it stays where he put it.
local function Scrolled()
	if quiet or not frame then return end
	want = nil -- (his offset now, not the one a redraw worked out)
	local s = frame.scroll
	local range, at = s:GetVerticalScrollRange() or 0, s:GetVerticalScroll() or 0
	if range - at <= STICK_SLACK then
		stick, newCount = true, 0
	elseif at < lastAt - 0.5 then
		stick = false
	end
	lastAt = at
	ShowNew()
end

-- Scrolled up, the view is held by the lines it shows, not by pixels: at a channel's 100 lines
-- each new one drops the oldest (Channels' AddHistory), everything under it moves up by that
-- bubble, and an offset kept as it was would show other lines. Before a redraw: the bubbles from
-- the one at the view's top down, each with how far it sat from the view's top.
local function InView()
	local at = frame.scroll:GetVerticalScroll() or 0
	local out = {}
	for _, b in ipairs(frame.bubbles) do
		if b:IsShown() and b.entry and b.y and (#out > 0 or b.y + (b:GetHeight() or 0) > at) then
			out[#out + 1] = { entry = b.entry, delta = b.y - at }
		end
	end
	return out
end

-- After it: the first of them still drawn back where it was (the one read dropped: the next
-- one's place); none left, the top.
local function BackInView(was)
	local at = {}
	for _, b in ipairs(frame.bubbles) do
		if b:IsShown() and b.entry and b.y then at[b.entry] = b.y end
	end
	want = 0
	for _, v in ipairs(was) do
		if at[v.entry] then
			want = math.max(0, at[v.entry] - v.delta)
			break
		end
	end
	local s = frame.scroll
	Quietly(function() s:SetVerticalScroll(want) end)
	lastAt = s:GetVerticalScroll() or 0
end

---------------------------------------------------------------------------
-- A name's header: one mark, the name, a tag, the guild (Borders.MarkOfName: the elite borders'
-- and nameplate marks' rules, and a mark only where the guild the line names is proven).
---------------------------------------------------------------------------

local function AtlasMark(atlas, tint)
	local info = C_Texture and C_Texture.GetAtlasInfo
	if type(info) == "function" then
		local ok, v = pcall(info, atlas)
		if not ok or v == nil then return STAR end
	end
	return "|A:" .. atlas .. ":14:14" .. (tint or "") .. "|a"
end

local function NameText(e)
	local who = ns.FullName(e.sender)
	local guild = e.guild
	local B = ns.Borders
	local mark = B and type(B.MarkOfName) == "function" and B.MarkOfName(who, guild) or nil
	local council = ns.IsHighCouncillor(who) and not ns.CouncilMasked()
	local name = ns.Codec.Plain(ns.DisplayName(e.sender) or "?")
	local lead = ""
	if mark == "gold" then
		lead = "|T" .. ns.CROWN_ICON .. ":14:14|t " -- (the King's mark in chat is his crown)
	elseif council then
		lead = ns.CouncilMark(who) .. " "
	elseif mark == "silver" then
		lead = AtlasMark(SILVER) .. " "
	elseif mark == "bronze" then
		lead = AtlasMark(BRONZE, BRONZE_TINT) .. " "
	elseif mark == "member" then
		lead = STAR .. " "
	end
	if ns.IsTreasurer(who, guild) then lead = lead .. (ns.COIN:gsub(" $", "")) end
	if council then
		name = "|c" .. ns.HIGH_COUNCIL_COLOR .. name .. "|r"
	else
		local file = e.class and ns.CLASS_FILES[e.class]
		local c = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
		if c and c.colorStr then name = "|c" .. c.colorStr .. name .. "|r" end
	end
	-- The King's Stewards and Hands, by the rule the channels read them with (his guild's lines).
	local tag = ""
	local K = ns.King
	if ns.IsKingGuild(guild) and type(K) == "table" then
		if type(K.IsStewardName) == "function" and K.IsStewardName(who) then
			tag = " " .. Gold(L.CHATWIN_TAG_STEWARD)
		elseif type(K.IsHandName) == "function" and K.IsHandName(who) then
			tag = " " .. Gold(L.CHATWIN_TAG_HAND)
		end
	end
	return lead .. name .. tag .. " " .. Grey("<" .. ns.Codec.Plain(guild or "?") .. ">")
end

---------------------------------------------------------------------------
-- The box's parts: bubbles and grey rows, each from a pool (made once, reused on every redraw).
---------------------------------------------------------------------------

local function Content() return frame and frame.content end

local function Render() return ChatWindow.Render() end

local function InsertLink(text)
	local eb = frame and frame.input
	if not eb or not eb:IsShown() or type(text) ~= "string" then return end
	-- Olympus's own box, where its cursor is; the keyboard stays where it was.
	if eb.Insert then eb:Insert(text) else eb:SetText((eb:GetText() or "") .. text) end
end

local function LinkTip(owner, link)
	local kind = type(link) == "string" and link:match("^(%a+):")
	if not kind or not LINK_TIPS[kind] then return end
	GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
	if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
		GameTooltip:Show()
		tipOwner = owner
	else
		GameTooltip:Hide()
	end
end

local function NewBubble()
	local content = Content()
	local ok, b = pcall(CreateFrame, "Frame", nil, content, "BackdropTemplate")
	if not ok or not b then b = CreateFrame("Frame", nil, content) end
	if b.SetBackdrop then
		b:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
	else
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
	end
	b:EnableMouse(true)
	-- The header: the name is a button (a whisper), the time on the right.
	b.header = CreateFrame("Button", nil, b)
	b.header:SetHeight(HEADER_H)
	b.header:SetPoint("TOPLEFT", b, "TOPLEFT", PAD, -PAD)
	b.who = b.header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.who:SetPoint("LEFT", b.header, "LEFT", 0, 0)
	b.who:SetJustifyH("LEFT")
	b.who:SetWordWrap(false)
	b.time = b.header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.time:SetPoint("RIGHT", b.header, "RIGHT", 0, 0)
	b.header:SetScript("OnClick", function(self)
		if self.whisper then ns.SafeCall("chat tab whisper", ns.UI.WhisperWindow, self.whisper) end
	end)
	b.header:SetScript("OnEnter", function(self)
		if not self.whisper then return end
		Tip(self, function(tt)
			tt:AddLine(self.full or self.whisper, 1, 0.82, 0)
			tt:AddLine(L.CHATWIN_WHISPER_TIP:format(self.whisper), 0.6, 0.6, 0.6)
		end)
	end)
	b.header:SetScript("OnLeave", function(self) Untip(self) end)
	-- The line itself, whole: the player's chat font, wrapped at any width, never cut.
	b.body = b:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
	b.body:SetJustifyH("LEFT")
	if b.body.SetJustifyV then b.body:SetJustifyV("TOP") end
	b.body:SetWordWrap(true)
	if b.body.SetNonSpaceWrap then b.body:SetNonSpaceWrap(true) end
	b.body:SetTextColor(0.95, 0.95, 0.95)
	-- Its links: a tooltip on hover, into our own box with Shift.
	if b.SetHyperlinksEnabled then b:SetHyperlinksEnabled(true) end
	b:SetScript("OnHyperlinkEnter", function(self, link) ns.SafeCall("chat tab link", LinkTip, self, link) end)
	b:SetScript("OnHyperlinkLeave", function(self) Untip(self) end)
	b:SetScript("OnHyperlinkClick", function(_, _, text)
		if IsShiftKeyDown and IsShiftKeyDown() then ns.SafeCall("chat tab link", InsertLink, text) end
	end)
	-- A line the block terms hide: a click shows it (this session).
	b:SetScript("OnMouseUp", function(self)
		if self.hidden and self.entry then
			revealed[self.entry] = true
			ns.SafeCall("chat tab", Render)
		end
	end)
	return b
end

-- A grey row across the box: the kept note, a day, the empty channel, no match, a line that was
-- not sent.
local function NewRow()
	local r = CreateFrame("Button", nil, Content())
	r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
	r.text:SetJustifyH("CENTER")
	r.text:SetWordWrap(true)
	r:SetScript("OnClick", function(self) if self.onClick then ns.SafeCall("chat tab row", self.onClick) end end)
	return r
end

local function Row(i, text, y, width, onClick)
	local rows = frame.rows
	local r = rows[i] or NewRow()
	rows[i] = r
	local w = math.max(40, width - 2 * EDGE)
	r.text:SetText(text)
	r.text:SetWidth(w)
	local h = TextHeight(r.text, w)
	r:SetSize(w, h)
	r:ClearAllPoints()
	r:SetPoint("TOPLEFT", frame.content, "TOPLEFT", EDGE, -y)
	r.onClick = onClick
	r:EnableMouse(onClick ~= nil)
	r:Show()
	return h
end

local function Hint()
	if not frame then return end
	local eb = frame.input
	local empty = (eb:GetText() or "") == ""
	local focused = eb.HasFocus and eb:HasFocus() or false
	eb.hint:SetShown(empty and not focused)
end

-- A line that was not sent, back in the box (the keyboard stays where it is: no focus). Only into
-- an empty box: what the player is writing is never replaced; the note stays, and he is told.
local function PutBack(t, note)
	local eb = frame and frame.input
	if not eb or not eb:IsShown() then return end
	if Trim(eb:GetText()) ~= "" then
		ns.Print(L.CHATWIN_PUT_BACK_BUSY)
		return
	end
	local list = notes[t]
	if list then
		for i, n in ipairs(list) do
			if n == note then table.remove(list, i) break end
		end
		if #list == 0 then notes[t] = nil end
	end
	eb:SetText(note.text)
	Hint()
	Render()
end

-- A line this character wrote: sent from here (mine) under this name. The history is the realm
-- group's, shared by every character of the account (ns.rdb): a line another character of it
-- sent shows as that character's, with his name, guild and whisper, on the left.
local function Own(e)
	return e.mine and ns.Channels.IsMe(e.sender) and true or false
end

-- One line of the history in its bubble. Returns its height.
local function Bubble(i, e, start, y, maxInner, hides)
	local bubbles = frame.bubbles
	local b = bubbles[i] or NewBubble()
	bubbles[i] = b
	local mine = Own(e)
	local hidden = not mine and not revealed[e] and hides ~= nil and hides(e.text or "") or false
	b.entry, b.hidden, b.mine, b.y = e, hidden, mine, y
	local c = Colour(tier)
	local r, g, bl, a = 0.09, 0.09, 0.11, 0.92
	if mine then r, g, bl, a = c[1] * 0.28, c[2] * 0.28, c[3] * 0.28, 0.95 end
	if b.SetBackdropColor then
		b:SetBackdropColor(r, g, bl, a)
		if hidden then b:SetBackdropBorderColor(0.5, 0.5, 0.5, 1) else b:SetBackdropBorderColor(c[1], c[2], c[3], 1) end
	elseif b.bg then
		b.bg:SetColorTexture(r, g, bl, a)
	end
	-- The header, at a group's start.
	local headerW, timeW = 0, 0
	if start then
		b.who:SetText(mine and L.CHATWIN_YOU or NameText(e))
		b.time:SetText(Grey(date("%H:%M", tonumber(e.t) or 0)))
		timeW = math.ceil(TextWidth(b.time))
		headerW = math.ceil(TextWidth(b.who)) + 8 + timeW
		b.header.whisper = not mine and ns.TellName(e.sender) or nil
		b.header.full = not mine and (ns.Codec.Plain(ns.DisplayName(e.sender) or "?") .. "  <" .. ns.Codec.Plain(e.guild or "?") .. ">") or nil
		b.header:EnableMouse(not mine)
		b.header:Show()
	else
		b.header.whisper, b.header.full = nil, nil
		b.header:Hide()
	end
	b.body:SetText(hidden and Grey(L.CHATWIN_HIDDEN) or ns.Codec.SanitizeChat(e.text))
	local inner = math.min(maxInner, math.max(math.ceil(TextWidth(b.body)), headerW, 1))
	b.body:SetWidth(inner)
	local bodyH = TextHeight(b.body, inner)
	local top = PAD
	if start then
		b.header:SetWidth(inner)
		b.who:SetWidth(math.max(1, inner - timeW - 8))
		top = top + HEADER_H + 2
	end
	b.body:ClearAllPoints()
	b.body:SetPoint("TOPLEFT", b, "TOPLEFT", PAD, -top)
	local h = top + bodyH + PAD
	b:SetSize(inner + 2 * PAD, h)
	b:ClearAllPoints()
	if mine then
		b:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", -EDGE, -y)
	else
		b:SetPoint("TOPLEFT", frame.content, "TOPLEFT", EDGE, -y)
	end
	b:Show()
	return h
end

local function ContentWidth()
	local w = frame.scroll:GetWidth()
	if not Finite(w) or w <= 0 then w = (frame:GetWidth() or 338) - 20 - (frame.barRoom or 22) end
	return math.max(100, math.floor(w))
end

-- The lines the tab's search box keeps (Views.Query: folded, as every tab's search): whose
-- writer, guild or words hold it. A line the block terms hide is found by its writer and guild
-- alone (its words are not shown).
local function Searched(list, q, hides)
	if not q then return list end
	local out = {}
	local Plain = ns.Codec.Plain
	for _, e in ipairs(list) do
		local hidden = hides ~= nil and not Own(e) and not revealed[e] and hides(e.text or "")
		local words = not hidden and ns.Codec.SanitizeChat(e.text) or nil
		if ns.Holds(q, ns.DisplayName(e.sender) or "?", Plain(e.guild or ""), words) then out[#out + 1] = e end
	end
	return out
end

local function Query()
	local V = ns.Views
	return V and type(V.Query) == "function" and V.Query(TAB) or nil
end

local function DrawLines()
	local C = ns.Channels
	local all = C.History(tier)
	local width = ContentWidth()
	frame.content:SetWidth(width)
	local F = ns.Filter
	local hides = F and not F.missing and type(F.Hides) == "function" and F.Hides or nil
	local q = Query()
	local list = Searched(all, q, hides)
	local nb, nr = 0, 0
	local y = 6
	nr = nr + 1
	y = y + Row(nr, Grey(L.CHATWIN_KEPT:format(C.HISTORY or 100)), y, width) + 6
	if #all == 0 then
		nr = nr + 1
		y = y + 8 + Row(nr, Grey(L.CHATWIN_EMPTY:format(Label(tier))), y + 8, width)
	elseif #list == 0 then
		nr = nr + 1
		y = y + 8 + Row(nr, Grey(L.SEARCH_NO_MATCH), y + 8, width)
	end
	local maxInner = math.max(BUBBLE_MIN, math.floor(width * SHARE)) - 2 * PAD
	local prev, prevDay
	for _, e in ipairs(list) do
		local t = tonumber(e.t) or 0
		local day = date("%Y-%m-%d", t)
		local newDay = day ~= prevDay
		if newDay then
			if prev then y = y + GAP_OUT end
			nr = nr + 1
			y = y + Row(nr, Grey(day), y, width) + 4
			prevDay = day
		end
		local start = newDay or not prev or ns.FullName(prev.sender) ~= ns.FullName(e.sender)
			or Own(prev) ~= Own(e) or t - (tonumber(prev.t) or 0) > GROUP_TIME
		if prev and not newDay then y = y + (start and GAP_OUT or GAP_IN) end
		nb = nb + 1
		y = y + Bubble(nb, e, start, y, maxInner, hides)
		prev = e
	end
	-- The lines of ours that were not sent: a grey note each, a click puts one back in the box.
	local t = tier
	for _, note in ipairs(notes[t] or {}) do
		local key = WHY[note.why] or WHY.failed
		nr = nr + 1
		y = y + GAP_OUT
		y = y + Row(nr, Grey(L.CHATWIN_NOT_SENT:format(L[key]) .. " " .. L.CHATWIN_PUT_BACK), y, width, function() PutBack(t, note) end)
	end
	y = y + 8
	for i = nb + 1, #frame.bubbles do frame.bubbles[i]:Hide(); frame.bubbles[i].entry, frame.bubbles[i].y = nil, nil end
	for i = nr + 1, #frame.rows do frame.rows[i]:Hide(); frame.rows[i].onClick = nil end
	frame.content:SetHeight(math.max(1, y))
end

---------------------------------------------------------------------------
-- The top: the search box, a pill per channel, the pinned line, the way to the Olympus tab.
---------------------------------------------------------------------------

local function Paint(b)
	local c = Colour(b.tier)
	if b.selected then
		b.text:SetTextColor(c[1], c[2], c[3])
		b.line:SetColorTexture(c[1], c[2], c[3], 1)
		b.line:Show()
	else
		local v = b.hover and 1 or 0.6
		b.text:SetTextColor(v, v, v)
		b.line:Hide()
	end
end

-- The pills where the other tabs have their column titles.
local function PaintPills()
	local C = ns.Channels
	local at = frame.places.pills
	local x = at.left + 4
	for _, t in ipairs(C.ORDER) do
		local b = frame.pills[t]
		if C.CanUse(t) then
			local n = unread[t] or 0
			b.text:SetText(Label(t) .. (n > 0 and (" (" .. n .. ")") or ""))
			b:SetSize(math.ceil(TextWidth(b.text)) + 16, at.h)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, at.top)
			x = x + b:GetWidth() + PILL_GAP
			b.selected = t == tier
			Paint(b)
			b:Show()
		else
			b:Hide()
		end
	end
end

-- The room between the box's sides (a strip over it: the pinned line, the Olympus tab's line).
local function StripWidth()
	local box = frame.places.box
	return math.max(100, (frame:GetWidth() or 338) - box.left + box.right - 12)
end

local function Strip(s, y)
	local box = frame.places.box
	s:ClearAllPoints()
	s:SetPoint("TOPLEFT", frame, "TOPLEFT", box.left + 6, y - 3)
	s:SetPoint("TOPRIGHT", frame, "TOPRIGHT", box.right - 6, y - 3)
end

-- The pinned line (Channels.Pin), as the Realm tab's chats page shows it (Views.PinLine): its
-- words veiled until a click when the block terms hide them; a click takes it down when allowed.
-- Under the pills, at `y`. Returns the room it takes.
local function DrawPin(y)
	local C = ns.Channels
	local pin = frame.pin
	local p = C.Pin and C.Pin()
	if not p then
		pin.onClick, pin.tip = nil, nil
		pin:Hide()
		return 0
	end
	local who = ns.Codec.Plain(ns.DisplayName(p.sender) or "?")
	local mayTakeDown = C.CanTakeDown and C.CanTakeDown()
	local words, veiled = C.PinWords(p)
	pin.onClick = mayTakeDown and function() ns.ShowDialog("OLYMPUS_PIN_DOWN") end or nil
	if veiled then
		pin.onClick = function()
			p.revealed = true
			Render()
		end
	end
	pin.tip = function(tt)
		tt:AddLine(L.PIN_LABEL, 1, 0.82, 0)
		tt:AddLine(words, 1, 1, 1, true)
		local left = math.max(1, math.ceil(((tonumber(p.expires) or ns.Now()) - ns.Now()) / 60))
		tt:AddLine(L.PIN_TIP:format(who, ns.Codec.Plain(p.guild or "?"), ns.Ago(p.setAt), left), 0.7, 0.7, 0.7, true)
		if mayTakeDown and not veiled then tt:AddLine(L.PIN_DOWN_TIP, 0.25, 1, 0.25, true) end
	end
	pin.text:SetText(Gold(L.CHATWIN_PINNED .. ": ") .. (veiled and Grey(L.FILTER_WORDS_HIDDEN) or ("|cffffffff" .. words .. "|r"))
		.. "  " .. Grey(who))
	local width = StripWidth()
	pin.text:SetWidth(width)
	local h = math.min(TextHeight(pin.text, width), PIN_LINES * LINE_H)
	pin:SetHeight(h)
	Strip(pin, y)
	pin:Show()
	return h + 6
end

---------------------------------------------------------------------------
-- The Olympus tab of the game's chat, by the player's own hand (1.1.1, the author's ask: a button
-- for it). Olympus cannot make a chat window: the game's code for one (FCF_OpenNewWindow, and the
-- NAME_CHAT popup FCF_NewChatWindow shows) writes the chat's own tables and its last active box
-- from whoever runs it, and run from an addon it taints the chat box (/cast, /target, /use and
-- /click typed there get blocked; with the gamepad UI the game froze). So the line on the Chat
-- tab only shows the player where: Olympus's own small pointer, anchored by the game's main chat
-- tab (ours anchored to theirs; theirs only read), says right-click it, Create New Window, name
-- it Olympus. Then Olympus reads the game's chat windows (Channels.FindTab: GetChatWindowInfo and
-- the frames' own fields) when the game says they changed (UPDATE_CHAT_WINDOWS,
-- UPDATE_FLOATING_CHAT_WINDOWS: FloatingChatFrame.lua and ChatFrameOverrides.lua register them)
-- and every LOOK_GAP while the pointer or the tab shows; the moment a window named Olympus is
-- there it runs Channels.SetupTab (the chats go there, and it says so once) and the pointer goes.
-- With the gamepad UI the game's chat tabs work otherwise: no pointer, the steps as text.
---------------------------------------------------------------------------

local function TabReady()
	local C = ns.Channels
	return not C.missing and type(C.SetupTab) == "function" and type(C.TabState) == "function" and type(C.FindTab) == "function"
end

local function MainTabWord()
	local C = ns.Channels
	return type(C.MainTabName) == "function" and C.MainTabName() or L.CHATTAB_MAIN_TAB
end

-- The game's main chat tab (its frame's name and "Tab": ChatFrame1Tab, FloatingChatFrame.xml),
-- when it shows. Read only.
local function MainChatTab()
	local f = DEFAULT_CHAT_FRAME
	local name = type(f) == "table" and type(f.GetName) == "function" and f:GetName() or nil
	local tab = type(name) == "string" and _G[name .. "Tab"] or nil
	if type(tab) ~= "table" then tab = _G.ChatFrame1Tab end
	if type(tab) == "table" and type(tab.IsVisible) == "function" and tab:IsVisible() then return tab end
	return nil
end

local function StopWatching()
	watching, lookAcc = false, 0
	if pointer then pointer:Hide() end
end

-- The game's chat windows read: a window named Olympus there, the chats go to it (SetupTab, once).
local function Look()
	if not watching then return false end
	if not TabReady() then
		StopWatching()
		return false
	end
	local C = ns.Channels
	if not C.FindTab() then return false end
	-- (Awaited from the line's click: chosen or not before, it is set up now, and said once.)
	StopWatching()
	C.SetupTab()
	MarkDirty()
	if ns.UI and type(ns.UI.RefreshSoon) == "function" then ns.UI.RefreshSoon() end
	return true
end

local function MakePointer()
	local name = "OlympusChatTabPointer"
	local ok, p = pcall(CreateFrame, "Frame", name, UIParent, "BackdropTemplate")
	if not ok or not p then p = CreateFrame("Frame", name, UIParent) end
	p:Hide()
	if p.SetBackdrop then
		p:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		if p.SetBackdropColor then p:SetBackdropColor(0.05, 0.05, 0.06, 0.95) end
		if p.SetBackdropBorderColor then p:SetBackdropBorderColor(1, 0.82, 0, 1) end
	else
		local bg = p:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.05, 0.05, 0.06, 0.95)
	end
	p:SetFrameStrata("DIALOG")
	p:SetClampedToScreen(true)
	p:SetSize(240, 76)
	p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -9)
	p.title:SetText(L.CHATTAB_POINTER_TITLE)
	p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	p.text:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -27)
	p.text:SetWidth(220)
	p.text:SetJustifyH("LEFT")
	p.text:SetWordWrap(true)
	-- The arrow under it, down onto the tab.
	p.arrow = p:CreateTexture(nil, "OVERLAY")
	p.arrow:SetSize(32, 32)
	p.arrow:SetPoint("TOP", p, "BOTTOMLEFT", 26, 2)
	local atlas = C_Texture and C_Texture.GetAtlasInfo
	local okAtlas, info = false, nil
	if type(atlas) == "function" and type(p.arrow.SetAtlas) == "function" then okAtlas, info = pcall(atlas, ARROW_ATLAS) end
	if okAtlas and info ~= nil then p.arrow:SetAtlas(ARROW_ATLAS) else p.arrow:SetTexture(ARROW_FILE) end
	-- Its X: the pointer goes (the game's chat windows are still read when the game says they
	-- changed, and while the Chat tab shows).
	local okClose, close = pcall(CreateFrame, "Button", nil, p, "UIPanelCloseButton")
	if okClose and close then
		close:SetPoint("TOPRIGHT", p, "TOPRIGHT", 2, 2)
		close:SetScript("OnClick", function() p:Hide() end)
		p.CloseButton = close
	end
	p:SetScript("OnUpdate", function(_, elapsed)
		lookAcc = lookAcc + (tonumber(elapsed) or 0)
		if lookAcc < LOOK_GAP then return end
		lookAcc = 0
		ns.SafeCall("olympus tab", Look)
	end)
	ns.EscapeCloses(name)
	p:HookScript("OnShow", function(self) ns.EscapeCloses(self:GetName()) end)
	pointer = p
	return p
end

-- By the game's main chat tab (the screen's bottom left where it does not show). Never with the
-- gamepad UI.
local function ShowPointer()
	if ns.GamepadUI() then return nil end
	local p = pointer or MakePointer()
	p.text:SetText(L.CHATTAB_POINTER:format(GameWord(NEW_CHAT_WINDOW, L.CHATWIN_NEW)))
	p:SetHeight(math.max(76, 36 + TextHeight(p.text, 220)))
	p:ClearAllPoints()
	local tab = MainChatTab()
	if tab then
		p:SetPoint("BOTTOMLEFT", tab, "TOPLEFT", 0, 34)
	else
		p:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 32, 260)
	end
	lookAcc = 0
	p:Show()
	return p
end

-- The Chat tab's line (the player's click): a tab named Olympus there already, the chats go to
-- it at once; else the pointer shows and the game's chat windows are read until it is there.
-- Returns true when the chats went to it, false when it is awaited, nil when there is no way.
function ChatWindow.AddTab()
	if not TabReady() then return nil end
	local C = ns.Channels
	if C.TabState() == "open" then
		MarkDirty()
		return true
	end
	watching, lookAcc = true, 0
	if Look() then return true end
	ShowPointer()
	MarkDirty()
	return false
end
function ChatWindow.Watching() return watching end
function ChatWindow.Pointer() return pointer end -- (tests)

for _, event in ipairs({ "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS" }) do
	ns.RegisterEvent(event, function() if watching then Look() end end)
end

-- The line under the pills while the Olympus tab is not there: a click adds it (above); awaited,
-- the steps. Returns the room it takes.
local function DrawGuide(y)
	local g = frame.guide
	local C = ns.Channels
	if not TabReady() or not C.ChatOn() or C.TabState() == "open" then
		g:Hide()
		return 0
	end
	local text
	if watching then
		text = Grey(L.CHATS_TAB_STEPS:format(MainTabWord(), GameWord(NEW_CHAT_WINDOW, L.CHATWIN_NEW)))
	else
		text = Green("+ " .. L.CHATS_TAB_ADD)
	end
	g.text:SetText(text)
	local width = StripWidth()
	g.text:SetWidth(width)
	local h = math.min(TextHeight(g.text, width), GUIDE_LINES * LINE_H)
	g:SetHeight(h)
	Strip(g, y)
	g:Show()
	return h + 6
end

---------------------------------------------------------------------------
-- The box to write in, and the search box.
---------------------------------------------------------------------------

-- The box: the channel's label on its left, a grey hint while empty (the moderators' word when
-- they took us off).
local function DrawInput()
	local eb = frame.input
	eb.label:SetText("|c" .. Hex(Colour(tier)) .. "[" .. Label(tier) .. "]:|r")
	local lw = math.ceil(TextWidth(eb.label))
	eb:SetTextInsets(lw + 6, 6, 0, 0)
	local M = ns.Moderation
	local off = M and type(M.SelfOff) == "function" and M.SelfOff() or nil
	local hint
	if off and type(M.YouText) == "function" then
		hint = M.YouText(off)
	else
		local public = ns.Comm and type(ns.Comm.IsPublic) == "function" and ns.Comm.IsPublic()
		hint = L.CHATWIN_PLACEHOLDER:format(Label(tier)) .. (public and L.CHATWIN_PUBLIC or "")
	end
	eb.hint:SetText(hint)
	eb.hint:ClearAllPoints()
	eb.hint:SetPoint("LEFT", eb, "LEFT", lw + 6, 0)
	eb.hint:SetPoint("RIGHT", eb, "RIGHT", -6, 0)
	Hint()
end

-- The search box shows what the tab's search holds (Views keeps it for the session, as each tab's).
local function DrawSearch()
	local V = ns.Views
	local text = V and type(V.Filter) == "function" and V.Filter(TAB) or ""
	local sb = frame.search
	if (sb:GetText() or "") ~= text then sb:SetText(text) end
	sb.clear:SetShown(text ~= "")
end

-- The chats on (lines, box, search) or off on this client (the choice, and a way to it).
local function ShowParts(on)
	frame.scroll:SetShown(on)
	frame.off:SetShown(not on)
	frame.input:SetShown(on)
	frame.search:SetShown(on)
	frame.searchLabel:SetShown(on)
	if not on then
		frame.newPill:Hide()
		frame.guide:Hide()
	end
end

function ChatWindow.Render()
	dirty = false
	if not frame or not frame.places then return end
	local C = ns.Channels
	local tiers = Readable()
	-- A rank that reads none of the channels any more (out of Olympus): the tab goes, and the
	-- window with it on the Census (UI.Refresh).
	if #tiers == 0 then
		frame:Hide()
		if ns.UI and type(ns.UI.Refresh) == "function" then ns.SafeCall("chat tab", ns.UI.Refresh) end
		return
	end
	if not tier or not C.CanUse(tier) then
		tier = tiers[1]
		Remember(tier)
	end
	PaintPills()
	local box = frame.places.box
	local y = box.top
	y = y - DrawPin(y)
	local on = C.ChatOn()
	if on then y = y - DrawGuide(y) end
	frame.box:SetPoint("TOPLEFT", frame, "TOPLEFT", box.left, y)
	ShowParts(on)
	if not on then
		-- As the Realm tab says it (its chats' line, CONSENT_CHAT_TEXT), with the choice a click away.
		frame.off.text:SetText(L.CHATWIN_OFF .. "\n\n" .. L.CONSENT_CHAT_TEXT)
		return
	end
	DrawSearch()
	DrawInput()
	local was = not stick and InView() or nil
	DrawLines()
	if stick then
		want = nil
		ToBottom()
	elseif was and #was > 0 then
		BackInView(was)
	else
		want = nil -- (no line in view: the offset stays as the player left it)
	end
	ShowNew()
end

---------------------------------------------------------------------------
-- Writing: Olympus's own box, through Channels.Send (every check and refusal is Send's).
---------------------------------------------------------------------------

local function Select(t)
	local C = ns.Channels
	local d = C.TIERS[t]
	if not d then return end
	if not C.CanUse(t) then
		ns.Print(L[d.deny]:format(L[d.label]))
		return
	end
	tier = t
	unread[t] = nil
	Remember(t)
	if Shown() then
		stick, newCount = true, 0
		Render()
		ScrollToBottom()
	end
end

local function NextTier()
	local tiers = Readable()
	if #tiers < 2 then return end
	local at = 1
	for i, t in ipairs(tiers) do
		if t == tier then at = i end
	end
	Select(tiers[at % #tiers + 1])
end

local function Submit()
	if not frame or not tier then return end
	local eb = frame.input
	local text = Trim(eb:GetText())
	if text == "" then
		eb:SetText("")
	elseif text:sub(1, 1) == "/" then
		-- This box runs no command and never hands one to the game: the text stays, nothing is sent.
		ns.Print(L.CHATWIN_NO_SLASH:format(Label(tier)))
	else
		-- keepMute: a channel muted in chat stays muted there (this tab shows it all the same).
		local ok, why = ns.Channels.Send(tier, text, nil, true)
		-- Sent, or held by the privacy warning (it sends the line on the player's OK): the box
		-- empties. Refused: the text stays (Send said why).
		if ok or why == "confirm" then
			eb:SetText("")
			if ok then notes[tier] = nil end
			ScrollToBottom()
			MarkDirty()
		end
	end
	-- (As the Communities box: the keyboard goes back to the game.)
	eb:ClearFocus()
	Hint()
end

-- Typed in the search box: the tab's search (Views.SetFilter, kept with the tab for the session),
-- the lines drawn again from the newest match.
local function SearchChanged(sb)
	local V = ns.Views
	local text = sb:GetText() or ""
	sb.clear:SetShown(text ~= "")
	if not V or type(V.SetFilter) ~= "function" or text == V.Filter(TAB) then return end
	V.SetFilter(TAB, text)
	stick, newCount, want = true, 0, nil
	MarkDirty()
end

---------------------------------------------------------------------------
-- The tab, made once for each Olympus window
---------------------------------------------------------------------------

local function OnUpdate(_, elapsed)
	local step = tonumber(elapsed) or 0
	acc = acc + step
	if watching then
		lookAcc = lookAcc + step
		if lookAcc >= LOOK_GAP and not (pointer and pointer:IsShown()) then
			lookAcc = 0
			ns.SafeCall("olympus tab", Look)
		end
	end
	if acc < THROTTLE then return end
	acc = 0
	if dataPending and GetTime() - lastData >= DATA_GAP then
		dataPending, lastData, dirty = false, GetTime(), true
	end
	-- A rank that no longer reads this channel (a demotion, out of the guild): drawn again at once.
	if tier and not ns.Channels.CanUse(tier) then dirty = true end
	if dirty then ns.SafeCall("chat tab", Render) end
end

local function MakePill(f, t)
	local b = CreateFrame("Button", nil, f)
	b.tier = t
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	b.text:SetPoint("CENTER", b, "CENTER", 0, 1)
	b.line = b:CreateTexture(nil, "ARTWORK")
	b.line:SetHeight(2)
	b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 4, 1)
	b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 1)
	b:SetScript("OnClick", function(self) ns.SafeCall("chat tab channel", Select, self.tier) end)
	b:SetScript("OnEnter", function(self)
		self.hover = true
		Paint(self)
		Tip(self, function(tt)
			tt:AddLine("[" .. Label(self.tier) .. "]", 1, 0.82, 0)
			-- The tab shows a channel muted in chat (/oly mute is about the chat frame).
			local muted = ns.db and type(ns.db.chatMute) == "table" and ns.db.chatMute[self.tier]
			if muted then tt:AddLine(L.CHATWIN_MUTED_TIP, 0.7, 0.7, 0.7, true) end
		end)
	end)
	b:SetScript("OnLeave", function(self)
		self.hover = nil
		Paint(self)
		Untip(self)
	end)
	return b
end

local function Button(parent, text, width)
	local ok, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
	if not ok or not b then
		b = CreateFrame("Button", nil, parent)
		b:SetNormalFontObject("GameFontNormal")
	end
	b:SetSize(width, 22)
	b:SetText(text)
	return b
end

-- A strip over the lines (the pinned line, the Olympus tab's line): a button with wrapped text.
local function StripButton(p, lines)
	local s = CreateFrame("Button", nil, p)
	s.text = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	s.text:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0)
	s.text:SetJustifyH("LEFT")
	s.text:SetWordWrap(true)
	if s.text.SetMaxLines then s.text:SetMaxLines(lines) end
	s:SetScript("OnEnter", function(self) if self.tip then Tip(self, self.tip) end end)
	s:SetScript("OnLeave", function(self) Untip(self) end)
	s:Hide()
	return s
end

-- The "x" at the end of the search box, as every tab's (Views.lua): empties it and lets go of the
-- keyboard. A button of its own, never a focus change.
local function ClearButton(sb)
	local x = CreateFrame("Button", nil, sb)
	x:SetSize(16, 16)
	x:SetPoint("RIGHT", sb, "RIGHT", -2, 0)
	x.label = x:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	x.label:SetPoint("CENTER", x, "CENTER", 0, 1)
	x.label:SetText("x")
	x:SetScript("OnClick", function()
		sb:SetText("")
		sb:ClearFocus()
		ns.SafeCall("chat tab search", SearchChanged, sb)
	end)
	x:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L.SEARCH_CLEAR, 1, 0.82, 0)
		GameTooltip:Show()
	end)
	x:SetScript("OnLeave", function() GameTooltip:Hide() end)
	x:Hide()
	return x
end

local function Build(h)
	if panes[h] then return panes[h] end
	local base = (h.GetName and h:GetName() or "Olympus") .. "Chat"
	local p = CreateFrame("Frame", base, h)
	p:Hide() -- (nothing in it shown, nor its box, before it is ready)
	panes[h] = p
	p.host = h
	p:SetAllPoints(h)
	p.bubbles, p.rows, p.pills = {}, {}, {}

	-- The search, where the other tabs show the army's counts.
	p.searchLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	p.searchLabel:SetText(L.SEARCH)
	local okSearch, sb = pcall(CreateFrame, "EditBox", nil, p, "InputBoxTemplate")
	if not okSearch or not sb then sb = CreateFrame("EditBox", nil, p) end
	sb:SetAutoFocus(false)
	sb.olympusBox = true
	sb:SetHeight(SEARCH_H)
	sb:SetMaxLetters(40)
	sb:SetFontObject("ChatFontNormal")
	sb:SetTextInsets(0, 18, 0, 0) -- (the typing stops short of the "x")
	sb.clear = ClearButton(sb)
	sb:SetScript("OnTextChanged", function(self) ns.SafeCall("chat tab search", SearchChanged, self) end)
	sb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	sb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	sb:SetScript("OnHide", function(self) self:ClearFocus() end)
	sb:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L.SEARCH, 1, 0.82, 0)
		GameTooltip:AddLine(L.SEARCH_TIP_CHAT, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	sb:SetScript("OnLeave", function() GameTooltip:Hide() end)
	p.search = sb

	-- The channels, where the other tabs have their column titles.
	for _, t in ipairs(ns.Channels.ORDER) do p.pills[t] = MakePill(p, t) end

	-- The pinned line.
	p.pin = StripButton(p, PIN_LINES)
	p.pin:SetScript("OnClick", function(self) if self.onClick then ns.SafeCall("chat tab pin", self.onClick) end end)

	-- The way to the Olympus tab of the game's chat.
	p.guide = StripButton(p, GUIDE_LINES)
	p.guide:SetScript("OnClick", function()
		ns.SafeCall("olympus tab", function()
			if watching then ShowPointer() else ChatWindow.AddTab() end
			Render()
		end)
	end)
	p.guide.tip = function(tt)
		tt:AddLine(L.CHATS_TAB_ADD, 1, 0.82, 0)
		tt:AddLine(L.CHATS_TAB_ADD_TIP, 1, 1, 1, true)
	end

	-- The box of lines (the Communities chat pane's inset), its scroll frame and its lines: over
	-- the list's and the detail box's room.
	local okBox, box = pcall(CreateFrame, "Frame", nil, p, "InsetFrameTemplate")
	if not okBox or not box then
		box = CreateFrame("Frame", nil, p)
		local bg = box:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.4)
	end
	p.box = box
	local okScroll, scroll = pcall(CreateFrame, "ScrollFrame", base .. "Scroll", box, "ScrollFrameTemplate")
	p.barRoom = 22 -- (the thin bar sits 6 past the frame's right edge)
	if not okScroll or not scroll or not scroll.ScrollBar then
		if okScroll and scroll then scroll:Hide() end
		scroll = CreateFrame("ScrollFrame", base .. "ScrollOld", box, "UIPanelScrollFrameTemplate")
		p.barRoom = 28
	end
	scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -p.barRoom, 4)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(10, 10)
	scroll:SetScrollChild(content)
	p.scroll, p.content = scroll, content
	scroll:HookScript("OnScrollRangeChanged", function() ns.SafeCall("chat tab place", Held) end)
	scroll:HookScript("OnVerticalScroll", function() ns.SafeCall("chat tab scrolled", Scrolled) end)
	scroll:HookScript("OnMouseWheel", function() ns.SafeCall("chat tab scrolled", Scrolled) end)

	-- "N new": the lines that came while the player looks further up; a click goes down to them.
	p.newPill = Button(box, "", 96)
	p.newPill:SetPoint("BOTTOM", box, "BOTTOM", -(p.barRoom / 2), 8)
	p.newPill:SetFrameLevel((scroll:GetFrameLevel() or 1) + 5)
	p.newPill:SetScript("OnClick", function() ns.SafeCall("chat tab new", ScrollToBottom) end)
	p.newPill:Hide()

	-- The chats off on this client: the choice's page (Consent.lua, Olympus's own frame).
	p.off = CreateFrame("Frame", nil, box)
	p.off:SetAllPoints(box)
	p.off.text = p.off:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	p.off.text:SetPoint("TOPLEFT", p.off, "TOPLEFT", 16, -24)
	p.off.text:SetPoint("TOPRIGHT", p.off, "TOPRIGHT", -16, -24)
	p.off.text:SetWordWrap(true)
	p.off.button = Button(p.off, L.CHATWIN_OFF_BUTTON, 110)
	p.off.button:SetPoint("TOP", p.off.text, "BOTTOM", 0, -14)
	p.off.button:SetScript("OnClick", function() ns.SafeCall("chat tab choice", ns.Consent.Show) end)
	p.off:Hide()

	-- The box to write in, across the bottom where the other tabs have their buttons: Olympus's
	-- own, never focused but by the player's click, and no Send button (Enter sends).
	local eb = CreateFrame("EditBox", base .. "Input", p)
	eb:SetAutoFocus(false)
	eb.olympusBox = true
	eb:SetFontObject("ChatFontNormal")
	eb:SetMaxBytes(ns.Codec.CHAT_PARTS * 210 + 1) -- (three parts; Channels.Send splits the line and says when it cuts)
	if eb.SetAltArrowKeyMode then eb:SetAltArrowKeyMode(false) end
	-- The Communities box's border art (CommunitiesChatEditBoxTemplate).
	local left = eb:CreateTexture(nil, "BACKGROUND")
	left:SetTexture("Interface\\ChatFrame\\UI-ChatInputBorder-Left2")
	left:SetSize(32, 32)
	left:SetPoint("LEFT", eb, "LEFT", -10, 0)
	local right = eb:CreateTexture(nil, "BACKGROUND")
	right:SetTexture("Interface\\ChatFrame\\UI-ChatInputBorder-Right2")
	right:SetSize(32, 32)
	right:SetPoint("RIGHT", eb, "RIGHT", 10, 0)
	local mid = eb:CreateTexture(nil, "BACKGROUND")
	mid:SetTexture("Interface\\ChatFrame\\UI-ChatInputBorder-Mid2")
	if mid.SetHorizTile then mid:SetHorizTile(true) end
	mid:SetHeight(32)
	mid:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
	mid:SetPoint("TOPRIGHT", right, "TOPLEFT", 0, 0)
	eb.label = eb:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
	eb.label:SetPoint("LEFT", eb, "LEFT", 0, 0)
	eb.hint = eb:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
	eb.hint:SetTextColor(0.5, 0.5, 0.5)
	eb.hint:SetJustifyH("LEFT")
	eb.hint:SetWordWrap(false)
	eb:SetScript("OnEnterPressed", function() ns.SafeCall("chat tab send", Submit) end)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnTabPressed", function() ns.SafeCall("chat tab channel", NextTier) end)
	eb:SetScript("OnTextChanged", function() ns.SafeCall("chat tab box", Hint) end)
	eb:SetScript("OnEditFocusGained", function() ns.SafeCall("chat tab box", Hint) end)
	eb:SetScript("OnEditFocusLost", function() ns.SafeCall("chat tab box", Hint) end)
	eb:SetScript("OnHide", function(self) self:ClearFocus() end)
	p.input = eb

	p:HookScript("OnHide", function()
		eb:ClearFocus()
		sb:ClearFocus()
		Untip(tipOwner)
	end)
	-- The window resized (docked to a guild window that grew): the lines wrap again.
	p:HookScript("OnSizeChanged", MarkDirty)
	if h.HookScript then h:HookScript("OnSizeChanged", MarkDirty) end
	p:SetScript("OnUpdate", OnUpdate)
	return p
end

-- Where the tab's parts go in its window, from UI.lua (offsets from the window's corners, for
-- its look): places = { search = { left, right, top }, pills = { left, top, h },
-- box = { left, right, top, bottom }, input = { left, right, y, h } }. The box's top moves down
-- under the pinned line and the Olympus tab's line (Render).
local function Place(p, places)
	if p.places == places then return end
	p.places = places
	local s, box, input = places.search, places.box, places.input
	p.searchLabel:ClearAllPoints()
	p.searchLabel:SetPoint("TOPLEFT", p, "TOPLEFT", s.left, s.top - 4)
	local lw = math.ceil(TextWidth(p.searchLabel))
	p.search:ClearAllPoints()
	p.search:SetPoint("TOPLEFT", p, "TOPLEFT", s.left + lw + 12, s.top)
	p.search:SetPoint("TOPRIGHT", p, "TOPRIGHT", s.right, s.top)
	p.box:ClearAllPoints()
	p.box:SetPoint("TOPLEFT", p, "TOPLEFT", box.left, box.top)
	p.box:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", box.right, box.bottom)
	local eb = p.input
	eb:ClearAllPoints()
	eb:SetHeight(input.h)
	eb:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", input.left + 10, input.y)
	eb:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", input.right - 10, input.y)
end

---------------------------------------------------------------------------
-- The tab in its window (UI.lua), and the ways to it
---------------------------------------------------------------------------

-- The channel it opens on: the one it showed, else the one last shown, else the first readable.
local function Pick()
	local C = ns.Channels
	if tier and C.TIERS[tier] and C.CanUse(tier) then return tier end
	local p = Saved()
	local last = p and p.tier
	if C.TIERS[last] and C.CanUse(last) then return last end
	return Readable()[1]
end

-- UI.lua, when window `h` shows its Chat tab (and on its redraws after): the tab in it, placed as
-- `places` says. Opening (it was not showing): the newest lines, unread counts from zero. Never
-- takes the keyboard.
function ChatWindow.Attach(h, places)
	if not h or type(places) ~= "table" then return nil end
	local p = Build(h)
	frame, host = p, h
	Place(p, places)
	if not p:IsShown() then
		tier = Pick()
		if tier then Remember(tier) end
		unread = {}
		stick, newCount, want, acc = true, 0, nil, 0
		p:Show()
		Render()
		ScrollToBottom()
	end
	return p
end

-- Another tab, or the window closed: the tab goes (its boxes let go of the keyboard).
function ChatWindow.Detach(h)
	local p = h and panes[h]
	if p and p:IsShown() then p:Hide() end
end

-- The Olympus window on its Chat tab, on `want` (a channel: "A", "C", "L"), else the one last
-- shown if still readable, else the first this rank reads. Never takes the keyboard.
function ChatWindow.Open(want)
	local C = ns.Channels
	if C.missing then
		ns.Print(L.RESTART_NEEDED)
		return nil
	end
	if C.MyLevel() == 0 then
		ns.Print(L.MEMBERS_ONLY)
		return nil
	end
	local d = want ~= nil and C.TIERS[want] or nil
	if d and not C.CanUse(want) then
		ns.Print(L[d.deny]:format(L[d.label]))
		return nil
	end
	if Shown() then
		if d and want ~= tier then Select(want) end
		return frame
	end
	if d then
		tier = want
		Remember(want)
	end
	local UI = ns.UI
	if not UI or type(UI.SelectTab) ~= "function" then return nil end
	UI.SelectTab(TAB)
	if not Shown() then return nil end
	ScrollToBottom()
	return frame
end

-- The Olympus window closed, when it shows the Chat tab.
function ChatWindow.Close()
	if Shown() then host:Hide() end
end

-- Shown on that channel (or none named): the window closes. Shown on another: that one. Else:
-- the window on the Chat tab.
function ChatWindow.Toggle(want)
	if Shown() then
		if want == nil or want == tier then
			host:Hide()
			return nil
		end
		Select(want)
		return frame
	end
	return ChatWindow.Open(want)
end

function ChatWindow.Tier() return tier end
function ChatWindow.Frame() return frame end -- (the tab, in its window)
function ChatWindow.Window() return host end -- (the Olympus window it is in)

-- (Tests: a fresh session.)
function ChatWindow.Reset()
	for _, p in pairs(panes) do p:Hide() end
	panes = {}
	frame, host, tier, tipOwner = nil, nil, nil, nil
	dirty, dataPending, lastData = false, false, -math.huge
	unread, notes = {}, {}
	revealed = setmetatable({}, { __mode = "k" })
	stick, newCount, lastAt, quiet, acc, want = true, 0, 0, false, 0, nil
	StopWatching()
	pointer = nil
end

---------------------------------------------------------------------------
-- What changes it
---------------------------------------------------------------------------

ns.On("CHAT_CHANGED", function(t)
	if t == nil or t == tier then MarkDirty() end
end)
ns.On("CHAT_LINE", function(t)
	if not Shown() or not ns.Channels.TIERS[t] then return end
	if t ~= tier then
		unread[t] = (unread[t] or 0) + 1
	elseif not stick then
		newCount = newCount + 1
	end
	MarkDirty()
end)
for _, event in ipairs({ "PIN_CHANGED", "FILTER_CHANGED", "NETOFF_CHANGED", "COUNCIL_MASK_CHANGED", "CONSENT_CHANGED" }) do
	ns.On(event, MarkDirty)
end
-- The marks follow the census, at most once every DATA_GAP seconds.
ns.On("DATA_CHANGED", function()
	if Shown() then dataPending = true end
end)
-- A line of ours that did not leave (Channels.lua: the channel changed before it went, it waited
-- too long, the game refused it, we left Olympus): a note in its channel, to put it back.
ns.On("CHAT_SEND_FAILED", function(t, why, text)
	if not ns.Channels.TIERS[t] or type(text) ~= "string" or text == "" then return end
	local list = notes[t] or {}
	notes[t] = list
	list[#list + 1] = { why = WHY[why] and why or "failed", text = text }
	while #list > MAX_NOTES do table.remove(list, 1) end
	MarkDirty()
end)

-- The channel last shown, kept only as a channel's letter (the first 1.1.1 build's window place
-- and size go).
ns.On("INIT", function()
	local p = ns.db.chatWin
	if p == nil then return end
	local t = type(p) == "table" and p.tier
	ns.db.chatWin = type(t) == "string" and ns.Channels.TIERS[t] and { tier = t } or nil
end)
