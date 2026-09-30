local ADDON, ns = ...
local L = ns.L

-- The Olympus chat window (1.1.1): the three Olympus chats ([Olympus], [Captains], [Lords]) in a
-- window of Olympus's own, like the chat pane of the Guild & Communities window and only that
-- pane: a tab per channel the player reads, each line whole in a bubble that wraps (nothing to
-- hover to read it), the 100 lines Channels keeps per channel to scroll back through, a box to
-- write in, and Olympus's marks by each name (the King's crown, the High Council's mark, the
-- Lords' and Captains' elite marks, Raiders and Veterans bronze, the members' star, the
-- Treasurer's coin, Stewards and Hands).
--
-- What it never does, whatever the input mode (mouse and keyboard, or Blizzard's gamepad UI):
-- - It never touches the game's chat boxes or windows: no script of theirs replaced or hooked,
--   and none opened from here (ChatFrame_OpenChat, ChatFrame_SendTell, ChatFrameUtil.*: they
--   write LAST_ACTIVE_CHAT_EDIT_BOX or CHAT_FOCUS_OVERRIDE, which the game's secure chat code
--   reads afterwards, so what the player types next runs tainted and /cast, /target, /use or
--   /click get blocked; with the gamepad UI that froze the game in 0.8.5). Every frame here is
--   Olympus's own.
-- - Its box is Olympus's own EditBox: it never takes the keyboard by itself (SetAutoFocus(false)
--   the moment it is made, never SetFocus, never ns.Focus); the player clicks into it, with the
--   mouse or the gamepad cursor. Enter sends through Channels.Send and lets the keyboard go (as
--   the Communities box does), so movement keys go back to the game. It runs no command: a line
--   starting with "/" is kept and the player is told the game's chat box is where commands go.
-- - No game popup from it: the pinned line's takedown and a whisper go through ns.ShowDialog
--   (Olympus's own window with the gamepad UI), and Escape closes it through ns.EscapeCloses
--   (nothing on UISpecialFrames with the gamepad UI: the X closes it there).
-- - Links in a line show their tooltip on hover (GameTooltip:SetHyperlink) and go into its own
--   box with a Shift-click; never SetItemRef, ChatEdit_InsertLink or HandleModifiedItemClick.
-- Nothing is drawn while it is hidden: a change marks it dirty and it redraws at most every 0.2 s
-- while shown (the census at most every 5 s). It never opens by itself.

local ChatWindow = {}
ns.ChatWindow = ChatWindow

local W, H = 440, 520                                 -- its size the first time
local MIN_W, MIN_H, MAX_W, MAX_H = 340, 300, 900, 1000
local HOME_X, HOME_Y = 320, 20                        -- the first time: right of the screen's centre
local TOP = 28                                        -- the channels' pills, under the title bar
local PILL_H, PILL_GAP = 22, 4
local SIDE = 10                                       -- the box of lines, from the window's sides
local INPUT_H, INPUT_BOTTOM = 28, 12
local BOX_BOTTOM = INPUT_BOTTOM + INPUT_H + 8
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
local PIN_LINES = 3
local MAX_NOTES = 5
local GREY = "|cff9d9d9d"
local LINK_TIPS = { item = true, spell = true, enchant = true, quest = true } -- (the links Codec lets through)
local STAR = "|TInterface\\AddOns\\Olympus\\media\\borders\\star:14:14|t"
local SILVER = "nameplates-icon-elite-silver"
local BRONZE = "nameplates-icon-elite-gold"
local BRONZE_TINT = ":0:0:158:118:86" -- (Nameplates.BRONZE x 255)
local WHY = { moved = "CHATWIN_WHY_MOVED", late = "CHATWIN_WHY_LATE", failed = "CHATWIN_WHY_FAILED", left = "CHATWIN_WHY_LEFT" }

local frame                  -- built on the first open
local tier                   -- the channel shown
local dirty, dataPending = false, false
local lastData = -math.huge
local unread = {}            -- tier -> lines from others since it was last looked at (while open)
local notes = {}             -- tier -> { { why, text } }: lines that were not sent, this session
local revealed = setmetatable({}, { __mode = "k" }) -- history entry -> shown despite the block terms
local stick, newCount = true, 0 -- the view follows the newest line; lines come while it doesn't
local lastAt = 0             -- the offset the view had last
local quiet = false          -- our own scrolling: not the player's
local acc = 0
local tipOwner

local function Grey(s) return GREY .. s .. "|r" end
local function Gold(s) return "|cffffd200" .. s .. "|r" end
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
-- Where it stands: ns.db.chatWin = { x, y, w, h, tier }, account-wide, the frame's bottom left
-- corner on the screen as a drag or a resize leaves it. Used only when it makes sense now:
-- finite numbers, a size within the bounds, and some of it on the screen.
---------------------------------------------------------------------------

local function Saved()
	local p = ns.db and ns.db.chatWin
	return type(p) == "table" and p or nil
end

local function Place()
	local p = Saved()
	if not p then return nil end
	local x, y, w, h = p.x, p.y, p.w, p.h
	if not (Finite(x) and Finite(y) and Finite(w) and Finite(h)) then return nil end
	if w < MIN_W or w > MAX_W or h < MIN_H or h > MAX_H then return nil end
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	if Finite(sw) and Finite(sh) and sw > 0 and sh > 0 and (x + w <= 0 or y + h <= 0 or x >= sw or y >= sh) then return nil end
	return x, y, w, h
end

local function SavePlace()
	if not frame or not ns.db then return end
	local l, b, w, h = frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
	if not (Finite(l) and Finite(b) and Finite(w) and Finite(h)) then return end
	local p = Saved() or {}
	p.x, p.y, p.w, p.h = math.floor(l + 0.5), math.floor(b + 0.5), math.floor(w + 0.5), math.floor(h + 0.5)
	ns.db.chatWin = p
end

local function Remember(t)
	if not ns.db then return end
	local p = Saved() or {}
	p.tier = t
	ns.db.chatWin = p
end

local function MarkDirty() dirty = true end

---------------------------------------------------------------------------
-- Scrolling: it follows the newest line (on opening, on a channel picked, after the player's own
-- line) until the player scrolls up; lines that come meanwhile show as "N new" at the bottom.
-- The client measures the scroll range a frame after the lines change (as UI.KeepPlace knows):
-- the offset is put at the end again then, while it follows.
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
	stick, newCount = true, 0
	if not frame then return end
	ToBottom()
	ShowNew()
end

-- The range measured again: at its end while the view follows.
local function Held()
	if not frame or not stick then return end
	local s = frame.scroll
	Quietly(function() s:SetVerticalScroll(s:GetVerticalScrollRange() or 0) end)
	lastAt = s:GetVerticalScroll() or 0
end

-- The player scrolled: at the end it follows again; up from where it was, it stays where he put it.
local function Scrolled()
	if quiet or not frame then return end
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

---------------------------------------------------------------------------
-- A name's header: one mark, the name, a tag, the guild (the same facts and trust rules as the
-- elite borders and nameplate marks: Borders.MarkOfName).
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
		if self.whisper then ns.SafeCall("chat window whisper", ns.UI.WhisperWindow, self.whisper) end
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
	b:SetScript("OnHyperlinkEnter", function(self, link) ns.SafeCall("chat window link", LinkTip, self, link) end)
	b:SetScript("OnHyperlinkLeave", function(self) Untip(self) end)
	b:SetScript("OnHyperlinkClick", function(_, _, text)
		if IsShiftKeyDown and IsShiftKeyDown() then ns.SafeCall("chat window link", InsertLink, text) end
	end)
	-- A line the block terms hide: a click shows it (this session).
	b:SetScript("OnMouseUp", function(self)
		if self.hidden and self.entry then
			revealed[self.entry] = true
			ns.SafeCall("chat window", Render)
		end
	end)
	return b
end

-- A grey row across the box: the kept note, a day, the empty channel, a line that was not sent.
local function NewRow()
	local r = CreateFrame("Button", nil, Content())
	r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
	r.text:SetJustifyH("CENTER")
	r.text:SetWordWrap(true)
	r:SetScript("OnClick", function(self) if self.onClick then ns.SafeCall("chat window row", self.onClick) end end)
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

-- A line that was not sent, back in the box (the keyboard stays where it is: no focus).
local function PutBack(t, note)
	local list = notes[t]
	if list then
		for i, n in ipairs(list) do
			if n == note then table.remove(list, i) break end
		end
		if #list == 0 then notes[t] = nil end
	end
	if frame and frame.input:IsShown() then
		frame.input:SetText(note.text)
		Hint()
	end
	Render()
end

-- One line of the history in its bubble. Returns its height.
local function Bubble(i, e, start, y, maxInner, hides)
	local bubbles = frame.bubbles
	local b = bubbles[i] or NewBubble()
	bubbles[i] = b
	local mine = e.mine and true or false
	local hidden = not mine and not revealed[e] and hides ~= nil and hides(e.text or "") or false
	b.entry, b.hidden, b.mine = e, hidden, mine
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
	if not Finite(w) or w <= 0 then w = (frame:GetWidth() or W) - 2 * SIDE - 8 - (frame.barRoom or 22) end
	return math.max(100, math.floor(w))
end

local function DrawLines()
	local C = ns.Channels
	local list = C.History(tier)
	local width = ContentWidth()
	frame.content:SetWidth(width)
	local nb, nr = 0, 0
	local y = 6
	nr = nr + 1
	y = y + Row(nr, Grey(L.CHATWIN_KEPT:format(C.HISTORY or 100)), y, width) + 6
	if #list == 0 then
		nr = nr + 1
		y = y + 8 + Row(nr, Grey(L.CHATWIN_EMPTY:format(Label(tier))), y + 8, width)
	end
	local F = ns.Filter
	local hides = F and not F.missing and type(F.Hides) == "function" and F.Hides or nil
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
			or (prev.mine and true or false) ~= (e.mine and true or false) or t - (tonumber(prev.t) or 0) > GROUP_TIME
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
	for i = nb + 1, #frame.bubbles do frame.bubbles[i]:Hide(); frame.bubbles[i].entry = nil end
	for i = nr + 1, #frame.rows do frame.rows[i]:Hide(); frame.rows[i].onClick = nil end
	frame.content:SetHeight(math.max(1, y))
end

---------------------------------------------------------------------------
-- The top: a pill per channel, the pinned line.
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

local function PaintPills()
	local C = ns.Channels
	local x = 10
	for _, t in ipairs(C.ORDER) do
		local b = frame.pills[t]
		if C.CanUse(t) then
			local n = unread[t] or 0
			b.text:SetText(Label(t) .. (n > 0 and (" (" .. n .. ")") or ""))
			b:SetWidth(math.ceil(TextWidth(b.text)) + 16)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -TOP)
			x = x + b:GetWidth() + PILL_GAP
			b.selected = t == tier
			Paint(b)
			b:Show()
		else
			b:Hide()
		end
	end
end

-- The pinned line (Channels.Pin), as the Realm tab's chats page shows it (Views.PinLine): its
-- words veiled until a click when the block terms hide them; a click takes it down when allowed.
-- Returns the room it takes.
local function DrawPin()
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
	local width = math.max(100, (frame:GetWidth() or W) - 24)
	pin.text:SetWidth(width)
	local h = math.min(TextHeight(pin.text, width), PIN_LINES * LINE_H)
	pin:SetHeight(h)
	pin:Show()
	return h + 6
end

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

-- The chats on (lines, box) or off on this client (the choice, and a way to it).
local function ShowParts(on)
	frame.scroll:SetShown(on)
	frame.off:SetShown(not on)
	frame.input:SetShown(on)
	frame.send:SetShown(on)
	if not on then frame.newPill:Hide() end
end

function ChatWindow.Render()
	dirty = false
	if not frame then return end
	local C = ns.Channels
	local tiers = Readable()
	-- A rank that reads none of the channels any more (out of Olympus): the window goes.
	if #tiers == 0 then
		frame:Hide()
		return
	end
	if not tier or not C.CanUse(tier) then
		tier = tiers[1]
		Remember(tier)
	end
	PaintPills()
	local pinH = DrawPin()
	frame.box:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE, -(TOP + PILL_H + 6 + pinH))
	local on = C.ChatOn()
	ShowParts(on)
	if not on then
		frame.off.text:SetText(L.CHATWIN_OFF)
		return
	end
	DrawInput()
	DrawLines()
	if stick then ToBottom() end
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
	if frame and frame:IsShown() then
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
		local ok, why = ns.Channels.Send(tier, text)
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

---------------------------------------------------------------------------
-- The window, made once
---------------------------------------------------------------------------

local function OnUpdate(_, elapsed)
	acc = acc + (tonumber(elapsed) or 0)
	if acc < THROTTLE then return end
	acc = 0
	if dataPending and GetTime() - lastData >= DATA_GAP then
		dataPending, lastData, dirty = false, GetTime(), true
	end
	-- A rank that no longer reads this channel (a demotion, out of the guild): drawn again at once.
	if tier and not ns.Channels.CanUse(tier) then dirty = true end
	if dirty then ns.SafeCall("chat window", Render) end
end

local function MakePill(f, t)
	local b = CreateFrame("Button", nil, f)
	b:SetHeight(PILL_H)
	b.tier = t
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	b.text:SetPoint("CENTER", b, "CENTER", 0, 1)
	b.line = b:CreateTexture(nil, "ARTWORK")
	b.line:SetHeight(2)
	b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 4, 1)
	b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 1)
	b:SetScript("OnClick", function(self) ns.SafeCall("chat window channel", Select, self.tier) end)
	b:SetScript("OnEnter", function(self)
		self.hover = true
		Paint(self)
		Tip(self, function(tt)
			tt:AddLine("[" .. Label(self.tier) .. "]", 1, 0.82, 0)
			-- The window shows a channel muted in chat (/oly mute is about the chat frame).
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

local function Build()
	if frame then return frame end
	local ok, f = pcall(CreateFrame, "Frame", "OlympusChatWindow", UIParent, "BasicFrameTemplateWithInset")
	if not ok or not f then
		f = CreateFrame("Frame", "OlympusChatWindow", UIParent)
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.05, 0.05, 0.06, 0.95)
		local okClose, close = pcall(CreateFrame, "Button", nil, f, "UIPanelCloseButton")
		if okClose and close then
			close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
			close:SetScript("OnClick", function() f:Hide() end)
			f.CloseButton = close
		end
	end
	f:Hide() -- (nothing in it shown, nor its box, before it is ready)
	frame = f
	-- Its X hides it itself: the template's button would call HideUIPanel, which does nothing in
	-- combat (CheckProtectedFunctionsAllowed) for a window that is not one of the game's panels.
	f.onCloseCallback = function()
		f:Hide()
		return false
	end
	f.bubbles, f.rows, f.pills = {}, {}, {}
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:SetResizable(true)
	if f.SetResizeBounds then
		f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
	else
		if f.SetMinResize then f:SetMinResize(MIN_W, MIN_H) end
		if f.SetMaxResize then f:SetMaxResize(MAX_W, MAX_H) end
	end
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		ns.SafeCall("chat window place", SavePlace)
	end)
	local x, y, w, h = Place()
	f:ClearAllPoints()
	if x then
		f:SetSize(w, h)
		f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
	else
		f:SetSize(W, H)
		f:SetPoint("CENTER", UIParent, "CENTER", HOME_X, HOME_Y)
	end
	if f.TitleText then
		f.TitleText:SetText(L.CHATWIN_TITLE)
	elseif f.SetTitle then
		f:SetTitle(L.CHATWIN_TITLE)
	elseif f.TitleContainer and f.TitleContainer.TitleText then
		f.TitleContainer.TitleText:SetText(L.CHATWIN_TITLE)
	end
	ns.EscapeCloses(f:GetName())

	-- The channels.
	for _, t in ipairs(ns.Channels.ORDER) do f.pills[t] = MakePill(f, t) end

	-- The pinned line.
	f.pin = CreateFrame("Button", nil, f)
	f.pin:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -(TOP + PILL_H + 4))
	f.pin:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -(TOP + PILL_H + 4))
	f.pin.text = f.pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.pin.text:SetPoint("TOPLEFT", f.pin, "TOPLEFT", 0, 0)
	f.pin.text:SetJustifyH("LEFT")
	f.pin.text:SetWordWrap(true)
	if f.pin.text.SetMaxLines then f.pin.text:SetMaxLines(PIN_LINES) end
	f.pin:SetScript("OnClick", function(self) if self.onClick then ns.SafeCall("chat window pin", self.onClick) end end)
	f.pin:SetScript("OnEnter", function(self) if self.tip then Tip(self, self.tip) end end)
	f.pin:SetScript("OnLeave", function(self) Untip(self) end)
	f.pin:Hide()

	-- The box of lines (the Communities chat pane's inset), its scroll frame and its lines.
	local okBox, box = pcall(CreateFrame, "Frame", nil, f, "InsetFrameTemplate")
	if not okBox or not box then
		box = CreateFrame("Frame", nil, f)
		local bg = box:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.4)
	end
	box:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE, -(TOP + PILL_H + 6))
	box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SIDE, BOX_BOTTOM)
	f.box = box
	local okScroll, scroll = pcall(CreateFrame, "ScrollFrame", "OlympusChatWindowScroll", box, "ScrollFrameTemplate")
	f.barRoom = 22 -- (the thin bar sits 6 past the frame's right edge)
	if not okScroll or not scroll or not scroll.ScrollBar then
		if okScroll and scroll then scroll:Hide() end
		scroll = CreateFrame("ScrollFrame", "OlympusChatWindowScrollOld", box, "UIPanelScrollFrameTemplate")
		f.barRoom = 28
	end
	scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -f.barRoom, 4)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(10, 10)
	scroll:SetScrollChild(content)
	f.scroll, f.content = scroll, content
	scroll:HookScript("OnScrollRangeChanged", function() ns.SafeCall("chat window place", Held) end)
	scroll:HookScript("OnVerticalScroll", function() ns.SafeCall("chat window scrolled", Scrolled) end)
	scroll:HookScript("OnMouseWheel", function() ns.SafeCall("chat window scrolled", Scrolled) end)

	-- "N new": the lines that came while the player looks further up; a click goes down to them.
	f.newPill = Button(box, "", 96)
	f.newPill:SetPoint("BOTTOM", box, "BOTTOM", -(f.barRoom / 2), 8)
	f.newPill:SetFrameLevel((scroll:GetFrameLevel() or 1) + 5)
	f.newPill:SetScript("OnClick", function() ns.SafeCall("chat window new", ScrollToBottom) end)
	f.newPill:Hide()

	-- The chats off on this client: the choice's page (Consent.lua, Olympus's own frame).
	f.off = CreateFrame("Frame", nil, box)
	f.off:SetAllPoints(box)
	f.off.text = f.off:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.off.text:SetPoint("TOPLEFT", f.off, "TOPLEFT", 20, -40)
	f.off.text:SetPoint("TOPRIGHT", f.off, "TOPRIGHT", -20, -40)
	f.off.text:SetWordWrap(true)
	f.off.button = Button(f.off, L.CHATWIN_OFF_BUTTON, 110)
	f.off.button:SetPoint("TOP", f.off.text, "BOTTOM", 0, -14)
	f.off.button:SetScript("OnClick", function() ns.SafeCall("chat window choice", ns.Consent.Show) end)
	f.off:Hide()

	-- The box to write in: Olympus's own, never focused but by the player's click.
	local eb = CreateFrame("EditBox", "OlympusChatWindowInput", f)
	eb:SetAutoFocus(false)
	eb.olympusBox = true
	eb:SetFontObject("ChatFontNormal")
	eb:SetMaxBytes(ns.Codec.CHAT_PARTS * 210 + 1) -- (three parts; Channels.Send splits the line and says when it cuts)
	if eb.SetAltArrowKeyMode then eb:SetAltArrowKeyMode(false) end
	eb:SetHeight(INPUT_H)
	eb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", SIDE + 14, INPUT_BOTTOM)
	eb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -106, INPUT_BOTTOM)
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
	eb:SetScript("OnEnterPressed", function() ns.SafeCall("chat window send", Submit) end)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnTabPressed", function() ns.SafeCall("chat window channel", NextTier) end)
	eb:SetScript("OnTextChanged", function() ns.SafeCall("chat window box", Hint) end)
	eb:SetScript("OnEditFocusGained", function() ns.SafeCall("chat window box", Hint) end)
	eb:SetScript("OnEditFocusLost", function() ns.SafeCall("chat window box", Hint) end)
	eb:SetScript("OnHide", function(self) self:ClearFocus() end)
	f.input = eb
	f.send = Button(f, SEND_LABEL or "Send", 70)
	f.send:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26, INPUT_BOTTOM + 3)
	f.send:SetScript("OnClick", function() ns.SafeCall("chat window send", Submit) end)

	-- The grip: bottom right, as the game's chat windows have it.
	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function(_, button) if button == nil or button == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end end)
	grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		ns.SafeCall("chat window place", SavePlace)
		MarkDirty()
	end)
	f.grip = grip

	f:HookScript("OnShow", function(self) ns.EscapeCloses(self:GetName()) end)
	f:HookScript("OnHide", function()
		eb:ClearFocus()
		Untip(tipOwner)
	end)
	f:HookScript("OnSizeChanged", MarkDirty)
	f:SetScript("OnUpdate", OnUpdate)
	return f
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------

-- Opens on `want` (a channel: "A", "C", "L"), else the one last shown if still readable, else
-- the first this rank reads. Never takes the keyboard.
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
	Build()
	local p = Saved()
	local last = p and p.tier
	local pick = d and want or (C.TIERS[last] and C.CanUse(last) and last) or Readable()[1]
	Remember(pick)
	tier = pick
	unread = {}
	stick, newCount = true, 0
	frame:Show()
	Render()
	ScrollToBottom()
	return frame
end

function ChatWindow.Close()
	if frame then frame:Hide() end
end

-- Shown on that channel (or none named): closed. Shown on another: that one. Hidden: opened.
function ChatWindow.Toggle(want)
	if frame and frame:IsShown() then
		if want == nil or want == tier then
			frame:Hide()
			return nil
		end
		Select(want)
		return frame
	end
	return ChatWindow.Open(want)
end

function ChatWindow.IsShown() return frame ~= nil and frame:IsShown() and true or false end
function ChatWindow.Tier() return tier end
function ChatWindow.Frame() return frame end

-- (Tests: a fresh session.)
function ChatWindow.Reset()
	if frame then frame:Hide() end
	frame, tier, tipOwner = nil, nil, nil
	dirty, dataPending, lastData = false, false, -math.huge
	unread, notes = {}, {}
	revealed = setmetatable({}, { __mode = "k" })
	stick, newCount, lastAt, quiet, acc = true, 0, 0, false, 0
end

---------------------------------------------------------------------------
-- What changes it
---------------------------------------------------------------------------

local function Shown() return frame ~= nil and frame:IsShown() end

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

-- Its saved place, kept only as numbers and a channel's letter.
ns.On("INIT", function()
	local p = ns.db.chatWin
	if p == nil then return end
	if type(p) ~= "table" then
		ns.db.chatWin = nil
		return
	end
	local clean = {}
	if Finite(p.x) and Finite(p.y) and Finite(p.w) and Finite(p.h) then clean.x, clean.y, clean.w, clean.h = p.x, p.y, p.w, p.h end
	if type(p.tier) == "string" and ns.Channels.TIERS[p.tier] then clean.tier = p.tier end
	ns.db.chatWin = next(clean) and clean or nil
end)
