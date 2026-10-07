local _, own = ...; local ns = own.host; if not ns then return end
local UI, L = own.ArenaUI, ns.L
local Chat = {}; UI.BonesChat = Chat
local panel, board, id, selected
local states = {} -- table -> independent session-only tab drafts and collapsed state
local used = 0
local function State() return id and states[id] end
local function Rooms()
	local A = ns.ArenaChat
	return id and A and A.TableRooms and A.TableRooms(id) or nil
end
local function Room()
	local rooms = Rooms()
	return rooms and rooms[selected] or nil
end
local function Readable(room)
	local A = ns.ArenaChat
	return room and A and A.MayRead and A.MayRead(room) == true or false
end
local function Writable()
	local A, room = ns.ArenaChat, Room()
	return Readable(room) and A.MaySend(room) == true
end
function Chat.Select(tab)
	local rooms, s = Rooms(), State()
	if not s or not rooms or not Readable(rooms[tab]) then return false end
	selected, s.tab = tab, tab
	panel.conversation.input:ClearFocus()
	panel.conversation.input:SetText(s.drafts[tab] or "")
	Chat.Refresh(true); panel.conversation:Render(true)
	return true
end
local function Build(parent)
	panel = CreateFrame("Frame", "OlympusArenaBonesChat", parent)
	panel:SetPoint("TOPLEFT", parent, "TOPRIGHT", 8, 0); panel:SetHeight(400)
	panel.toggle = CreateFrame("Button", nil, panel)
	panel.toggle:SetSize(90, 24); panel.toggle:SetPoint("TOPLEFT")
	panel.toggle.text = panel.toggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	panel.toggle.text:SetAllPoints()
	panel.toggle:SetScript("OnClick", function()
		local s = State(); if not s then return end
		s.collapsed = not s.collapsed; Chat.Refresh(true)
	end)
	panel.strip = CreateFrame("Frame", nil, panel)
	panel.strip:SetPoint("TOPLEFT", 0, -24); panel.strip:SetHeight(24)
	local wash = panel.strip:CreateTexture(nil, "BACKGROUND")
	wash:SetAllPoints(); wash:SetColorTexture(0.35, 0.35, 0.37, 1)
	panel.conversation = ns.ChatWindow.CreateEmbedded(panel, {
		maxBytes = ns.ArenaChat.TEXT_MAX,
		room = Room, maySend = Writable,
		label = function() return selected == "players" and L.BONES_CHAT_PLAYERS or L.BONES_CHAT_EVERYONE end,
		lines = function() local room = Room(); return Readable(room) and ns.ArenaChat.Lines(room) or {} end,
		send = function(text) if not Writable() then return false, "room" end return ns.ArenaChat.Send(Room(), text) end,
		changed = function(text) local s = State(); if s and selected then s.drafts[selected] = text end end,
		nextTab = function() Chat.Select(selected == "players" and "everyone" or "players") end,
	})
	panel.conversation:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -48)
	panel.conversation:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
	panel:Hide()
end
function Chat.Refresh(force)
	if not panel then return end
	local rooms, s = Rooms(), State()
	local available = rooms and (Readable(rooms.players) or Readable(rooms.everyone))
	if not available or not board:IsShown() then
		panel:Hide(); if Chat.layout then Chat.layout(0) end
		return
	end
	if not Readable(rooms[selected]) then
		selected = Readable(rooms.players) and "players" or "everyone"
		s.tab = selected; panel.conversation.input:ClearFocus(); panel.conversation.input:SetText(s.drafts[selected] or "")
	end
	local A, room = ns.ArenaChat, Room()
	if room and not A.IsOpen(room) then A.Open(room) end
	-- This child inherits the table's actual scale. The combined standalone window is fitted by
	-- the board; width stays bounded, not a chat window covering the player's dice.
	local width = 280
	panel:SetWidth(s.collapsed and 90 or width)
	panel.strip:SetWidth(width)
	panel.toggle.text:SetText(s.collapsed and L.BONES_CHAT_EXPAND or L.BONES_CHAT_COLLAPSE)
	panel.strip:SetShown(not s.collapsed); panel.conversation:SetShown(not s.collapsed)
	if not s.collapsed then
		local tabs = {}
		for _, tab in ipairs({ "players", "everyone" }) do
			if Readable(rooms[tab]) then
				local choice = tab
				tabs[#tabs + 1] = { text = tab == "players" and L.BONES_CHAT_PLAYERS or L.BONES_CHAT_EVERYONE,
					selected = selected == tab, onClick = function() Chat.Select(choice) end }
			end
		end
		ns.Views.DrawNav(panel.strip, tabs, width)
		local write = Writable()
		if force or panel.lastRoom ~= room or panel.lastWrite ~= write then panel.conversation:Render() end
		panel.lastRoom, panel.lastWrite = room, write
	else panel.conversation.input:ClearFocus() end
	panel:Show(); if Chat.layout then Chat.layout(panel:GetWidth() + 8) end
end
function Chat.Attach(parent, tableId, live, layout)
	if not ns.ChatWindow or not ns.ChatWindow.CreateEmbedded or not ns.Views or not ns.Views.DrawNav then return end
	board, Chat.layout = parent, layout
	local A = ns.ArenaChat
	if not live or type(tableId) ~= "string" or not A or not A.TableRooms or not A.TableRooms(tableId) then
		id = nil; if panel then Chat.Refresh() end return
	end
	if not panel then Build(parent) end
	if id ~= tableId then
		id = tableId; states[id] = states[id] or { drafts = {}, collapsed = false }
		used = used + 1; states[id].used = used
		local count, oldest, stamp = 0
		for key, s in pairs(states) do
			count = count + 1
			if key ~= id and (not stamp or s.used < stamp) then oldest, stamp = key, s.used end
		end
		if oldest and count > (ns.ArenaChat.ROOMS_MAX or 10) then states[oldest] = nil end
		selected = states[id].tab
		panel.conversation.input:ClearFocus()
		panel.conversation.input:SetText(selected and states[id].drafts[selected] or "")
		Chat.Refresh()
	else Chat.Refresh() end
end
function Chat.Hide() if panel then panel:Hide(); panel.conversation.input:ClearFocus(); if Chat.layout then Chat.layout(0) end end end
function Chat.Frame() return panel end
ns.On("ARENA_CHAT", function(room) if panel and panel:IsShown() and room == Room() then Chat.Refresh(true) end end)
ns.On("WATCHCHAT_CHANGED", function() if panel and panel:IsShown() then Chat.Refresh(true) end end)
ns.On("FILTER_CHANGED", function() if panel and panel:IsShown() then Chat.Refresh(true) end end)
ns.On("CHAT_SETTINGS_CHANGED", function() if panel and panel:IsShown() then Chat.Refresh(true) end end)
ns.Every(1, "bones chat", function() if panel and board:IsShown() then Chat.Refresh() end end)
-- The existing input-style event is optional on older clients. Both switches relinquish only
-- this own box's keyboard focus; no binding, game chat box or shared focus global is touched.
pcall(ns.RegisterEvent, "INPUT_DEVICE_INTERFACE_TRANSITION", function()
	if panel then panel.conversation.input:ClearFocus() end
end)
