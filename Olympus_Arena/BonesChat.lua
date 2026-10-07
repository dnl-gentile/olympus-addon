local _, own = ...; local ns = own.host; if not ns then return end
local UI, L = own.ArenaUI, ns.L
local Chat = {}; UI.BonesChat = Chat
local panel, candidate, board, id, selected
local preview -- UI-only provider: no real room, participant, history or send authority
local states = {} -- table -> independent session-only tab drafts and collapsed state
local used = 0
local function State() return preview and preview.state or id and states[id] end
local function Rooms()
	if preview then return preview.rooms end
	local A = ns.ArenaChat
	return id and A and A.TableRooms and A.TableRooms(id) or nil
end
local function Room()
	local rooms = Rooms()
	return rooms and rooms[selected] or nil
end
local function Readable(room)
	if preview then return room == preview.rooms.players or room == preview.rooms.everyone end
	local A = ns.ArenaChat
	return room and A and A.MayRead and A.MayRead(room) == true or false
end
local function Writable()
	if preview then return true end -- show the real composer; its Enter handler below never sends
	local A, room = ns.ArenaChat, Room()
	return Readable(room) and A.MaySend(room) == true
end
function Chat.Select(tab)
	local rooms, s = Rooms(), State()
	if not s or not rooms or not Readable(rooms[tab]) then return false end
	selected, s.tab = tab, tab
	panel.conversation.input:ClearFocus()
	panel.conversation.input:SetText(s.drafts[tab] or "")
	panel.conversation.search:ClearFocus()
	panel.conversation.search:SetText(s.searches[tab] or "")
	Chat.Refresh(true); panel.conversation:Render(true)
	return true
end
local function Build(parent)
	-- Keep a failed optional construction hidden and unpublished. A later real module load
	-- retries with the same candidate; board callbacks never see a half-built conversation.
	local p = candidate
	if not p then
		p = CreateFrame("Frame", "OlympusArenaBonesChat", parent)
		p:Hide()
		p:SetPoint("TOPLEFT", parent, "TOPRIGHT", 8, 0); p:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", 8, 0)
		p.ground = ns.ChatWindow.BodyInset(p) -- native chat ground under Search, tabs and footer, never the world
		p.ground:SetAllPoints(p); p.ground:SetFrameLevel(p:GetFrameLevel())
		p.ground:Hide()
		-- The table's existing footer gap: no extra side bar is needed to keep Show chat accessible.
		p.toggle = UI.Kit.Button(parent, 110, 24, "", function()
			local s = State(); if not s then return end
			s.collapsed = not s.collapsed; Chat.Refresh(true)
		end)
		p.toggle:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 146, 16)
		p.toggle:Hide()
		p.strip = CreateFrame("Frame", nil, p)
		p.strip:SetPoint("TOPLEFT", 0, -28); p.strip:SetHeight(24)
		candidate = p
	end
	local conversation = ns.ChatWindow.CreateEmbedded(p, {
		maxBytes = ns.ArenaChat.TEXT_MAX,
		room = Room, maySend = Writable,
		label = function() return selected == "players" and L.BONES_CHAT_PLAYERS or L.BONES_CHAT_EVERYONE end,
		lines = function() if preview then return {} end local room = Room(); return Readable(room) and ns.ArenaChat.Lines(room) or {} end,
		send = function(text) if preview then return false, "preview" end if not Writable() then return false, "room" end return ns.ArenaChat.Send(Room(), text) end,
		changed = function(text) local s = State(); if s and selected then s.drafts[selected] = text end end,
		searchChanged = function(text) local s = State(); if s and selected then s.searches[selected] = text end end,
		nextTab = function() Chat.Select(selected == "players" and "everyone" or "players") end,
	})
	if not conversation then return false end
	conversation:SetAllPoints(p)
	p.strip:SetFrameLevel(conversation.bodyInset:GetFrameLevel() + 2)
	p.conversation = conversation
	-- Revalidate the room while its panel is visible (including its collapsed toggle), never
	-- wake an idle companion. Parent hides also run OnHide and cancel this own ticker.
	p:SetScript("OnShow", function(self)
		self.toggle:Show()
		if self.refreshTicker then return end
		self.refreshTicker = C_Timer.NewTicker(1, function()
			ns.SafeCall("bones chat", Chat.Refresh)
		end)
	end)
	p:SetScript("OnHide", function(self)
		self.toggle:Hide()
		if self.refreshTicker then self.refreshTicker:Cancel(); self.refreshTicker = nil end
		self.conversation.input:ClearFocus()
		if preview then Chat.HidePreview() end
	end)
	panel, candidate = p, nil
	return true
end
function Chat.Refresh(force)
	if not panel then return end
	if preview and not (ns.Arena.Sim() and ns.Arena.MaySim()) then Chat.HidePreview(); return end
	local rooms, s = Rooms(), State()
	local available = rooms and (Readable(rooms.players) or Readable(rooms.everyone))
	if not available or not board:IsShown() then
		panel:Hide(); panel.toggle:Hide(); if Chat.layout then Chat.layout(0) end
		return
	end
	if not Readable(rooms[selected]) then
		selected = Readable(rooms.players) and "players" or "everyone"
		s.tab = selected; panel.conversation.input:ClearFocus(); panel.conversation.input:SetText(s.drafts[selected] or "")
		panel.conversation.search:ClearFocus(); panel.conversation.search:SetText(s.searches[selected] or "")
	end
	local A, room = ns.ArenaChat, Room()
	if not preview and room and not A.IsOpen(room) then A.Open(room) end
	-- This child inherits the table's actual scale. The combined standalone window is fitted by
	-- the board; width stays bounded, not a chat window covering the player's dice.
	local width = 280
	panel:SetWidth(s.collapsed and 0 or width)
	panel.strip:SetWidth(width)
	panel.toggle:SetText(s.collapsed and L.BONES_CHAT_EXPAND or L.BONES_CHAT_COLLAPSE)
	panel.strip:SetShown(not s.collapsed); panel.conversation:SetShown(not s.collapsed)
	panel.ground:SetShown(not s.collapsed)
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
	panel:Show(); panel.toggle:Show(); if Chat.layout then Chat.layout(s.collapsed and 0 or width + 8) end
end
function Chat.Attach(parent, tableId, live, layout)
	if preview then
		-- The simulation's real practice board keeps its normal refresh path. It has no real
		-- table to attach; a real live table or a different/ended simulation clears the preview.
		if not live and parent == preview.parent and ns.Arena.Sim() and ns.Arena.MaySim() then Chat.Refresh(); return end
		Chat.HidePreview()
	end
	board, Chat.layout = parent, layout
	local C, V = ns.ChatWindow, ns.Views
	-- Core's restart stand-ins have callable no-op methods, but cannot create a conversation.
	if type(C) ~= "table" or C.missing == true or type(C.CreateEmbedded) ~= "function"
		or type(V) ~= "table" or V.missing == true or type(V.DrawNav) ~= "function" then
		id = nil
		if panel then Chat.Hide() elseif Chat.layout then Chat.layout(0) end
		return
	end
	local A = ns.ArenaChat
	if not live or type(tableId) ~= "string" or not A or not A.TableRooms or not A.TableRooms(tableId) then
		id = nil; if panel then Chat.Refresh() end return
	end
	if not panel and not Build(parent) then
		id = nil; if Chat.layout then Chat.layout(0) end
		return
	end
	if id ~= tableId then
		id = tableId; states[id] = states[id] or { drafts = {}, searches = {}, collapsed = false }
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
		panel.conversation.search:ClearFocus()
		panel.conversation.search:SetText(selected and states[id].searches[selected] or "")
		Chat.Refresh()
	else Chat.Refresh() end
end
function Chat.HidePreview()
	if not preview then return false end
	preview, id, selected = nil, nil, nil
	if panel then
		panel.conversation.input:SetText(""); panel.conversation.search:SetText("")
		panel:Hide(); panel.toggle:Hide()
	end
	if Chat.layout then Chat.layout(0) end
	return true
end
function Chat.Preview(parent, layout)
	if not (ns.Arena.Sim() and ns.Arena.MaySim()) then return false, "who" end
	local C, V = ns.ChatWindow, ns.Views
	if type(C) ~= "table" or C.missing == true or type(C.CreateEmbedded) ~= "function"
		or type(V) ~= "table" or V.missing == true or type(V.DrawNav) ~= "function" then return false, "missing" end
	if type(parent) ~= "table" or type(parent.IsShown) ~= "function" or not parent:IsShown() then return false, "window" end
	Chat.HidePreview()
	board, Chat.layout = parent, layout
	if not panel and not Build(parent) then return false, "missing" end
	preview = { parent = parent, rooms = { players = {}, everyone = {} },
		state = { drafts = {}, searches = {}, tab = "players", collapsed = false } }
	id, selected = nil, "players"
	panel.conversation.input:ClearFocus(); panel.conversation.search:ClearFocus()
	panel.conversation.input:SetText(""); panel.conversation.search:SetText("")
	Chat.Refresh(true)
	return true
end
function Chat.Hide()
	if Chat.HidePreview() then return end
	if panel then panel:Hide(); panel.toggle:Hide(); panel.conversation.input:ClearFocus(); if Chat.layout then Chat.layout(0) end end
end
function Chat.Frame() return panel end
ns.On("ARENA_CHAT", function(room) if panel and panel:IsShown() and room == Room() then Chat.Refresh(true) end end)
ns.On("WATCHCHAT_CHANGED", function() if panel and panel:IsShown() then Chat.Refresh(true) end end)
ns.On("FILTER_CHANGED", function() if panel and panel:IsShown() then Chat.Refresh(true) end end)
ns.On("CHAT_SETTINGS_CHANGED", function() if panel and panel:IsShown() then Chat.Refresh(true) end end)
-- The existing input-style event is optional on older clients. Both switches relinquish only
-- this own box's keyboard focus; no binding, game chat box or shared focus global is touched.
pcall(ns.RegisterEvent, "INPUT_DEVICE_INTERFACE_TRANSITION", function()
	if panel then panel.conversation.input:ClearFocus(); panel.conversation.search:ClearFocus() end
end)
