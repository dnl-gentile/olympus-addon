local ADDON, ns = ...

-- Real WoW chat windows; only their plain-text input is routed through Channels.Send.
-- No changes to the wire protocol, global chat functions, or other windows' input.
local Tabs = {}
ns.ChatTabs = Tabs
local bindings = {}

local function WindowInfo(id)
	local info = FCF_GetChatWindowInfo or GetChatWindowInfo
	if info then return info(id) end
end

local function MaxWindows()
	return NUM_CHAT_WINDOWS or (Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatWindows) or 10
end

local function Active(frame)
	local name, _, _, _, _, _, shown = WindowInfo(frame:GetID())
	return name, shown or frame.isDocked
end

local function BoundFrame(tier)
	local binding = bindings[tier]
	if not binding then return nil end
	local name, active = Active(binding.frame)
	if active and name == binding.name then return binding.frame end
end

function Tabs.Frame(tier)
	if not ns.Channels.CanUse(tier) then return nil end
	return BoundFrame(tier)
end

local function ChatType(edit)
	if edit.GetChatType then return edit:GetChatType() end
	return edit:GetAttribute("chatType")
end

-- Keep WoW's real chat type for its command parser, but label the destination
-- used by our Enter handler. Never relabel explicit /say, whispers, or guild chat.
local function LabelInput(edit)
	local tier = edit.olympusTier
	if not tier or not BoundFrame(tier) or edit.olympusExplicit or ChatType(edit) ~= "SAY" then return end
	local header = edit.header or _G[edit:GetName() .. "Header"]
	if not header then return end
	local suffix = edit.headerSuffix or _G[edit:GetName() .. "HeaderSuffix"]
	local oldWidth = header:GetWidth() + (suffix and suffix:IsShown() and suffix:GetWidth() or 0)
	local left, right, top, bottom = edit:GetTextInsets()
	header:SetWidth(0)
	header:SetText(ns.L[ns.Channels.TIERS[tier].label] .. ": ")
	local width = header:GetStringWidth()
	local limit = edit:GetWidth() / 2
	header:SetWidth(math.min(width, limit))
	if suffix then
		if width > limit then suffix:Show() else suffix:Hide() end
	end
	local newWidth = header:GetWidth() + (suffix and suffix:IsShown() and suffix:GetWidth() or 0)
	edit:SetTextInsets(left - oldWidth + newWidth, right, top, bottom)
end

local function RefreshInput(edit)
	if edit.UpdateHeader then edit:UpdateHeader()
	elseif ChatEdit_UpdateHeader then ChatEdit_UpdateHeader(edit)
	else LabelInput(edit) end
end

local legacyHeaderHooked = false
local function Bind(frame, tier, name)
	bindings[tier] = { frame = frame, name = name }
	local edit = frame.editBox or _G[frame:GetName() .. "EditBox"]
	if not edit then return end
	edit.olympusTier = tier
	if edit.olympusHooked then return end
	local enter = edit:GetScript("OnEnterPressed")
	if not enter then return end
	edit.olympusHooked = true
	if hooksecurefunc then
		if edit.UpdateHeader then
			hooksecurefunc(edit, "UpdateHeader", LabelInput)
		elseif ChatEdit_UpdateHeader and not legacyHeaderHooked then
			hooksecurefunc("ChatEdit_UpdateHeader", LabelInput)
			legacyHeaderHooked = true
		end
	end
	edit:HookScript("OnShow", RefreshInput)
	-- Remember explicit commands before WoW strips /say, /whisper, etc. from the text.
	local changed = edit:GetScript("OnTextChanged")
	edit:SetScript("OnTextChanged", function(self, userInput, ...)
		if userInput and self:GetText() == "" then self.olympusExplicit = nil end
		if self:GetText():match("^%s*/") then self.olympusExplicit = true end
		if changed then changed(self, userInput, ...) end
		RefreshInput(self)
	end)
	edit:HookScript("OnHide", function(self) self.olympusExplicit = nil end)
	edit:SetScript("OnEnterPressed", function(self, ...)
		local current = self.olympusTier
		local text = self:GetText()
		if BoundFrame(current) == frame and not self.olympusExplicit
			and ChatType(self) == "SAY" and text:find("%S") and not text:match("^%s*/") then
			-- Let WoW execute the registered slash command and handle history/closing.
			-- Channels.Send still enforces membership, rank, mute and rate limits.
			self:SetText(ns.Channels.TIERS[current].slash .. " " .. text)
		end
		enter(self, ...)
		self.olympusExplicit = nil
	end)
end

function Tabs.Open(tier)
	tier = tier or "A"
	if not ns.Channels.CanUse(tier) then
		ns.Print("That Olympus chat is not available to your rank.")
		return false
	end
	if InCombatLockdown and InCombatLockdown() then
		ns.Print("Open Olympus chat tabs after combat.")
		return false
	end
	local frame = Tabs.Frame(tier)
	if not frame then
		if not FCF_OpenNewWindow then
			ns.Print("Chat tabs are unavailable on this client; use " .. ns.Channels.TIERS[tier].slash .. ".")
			return false
		end
		-- Older clients recycle an occupied window when all slots are full.
		local free = false
		for id = 3, MaxWindows() do
			local candidate = _G["ChatFrame" .. id]
			if candidate then
				local _, active = Active(candidate)
				local builtin = IsBuiltinChatWindow and IsBuiltinChatWindow(candidate)
				if not active and not builtin and not candidate.isTemporary then free = true; break end
			end
		end
		if not free then ns.Print("Close an unused chat window before opening an Olympus tab."); return false end
		local name = ns.L[ns.Channels.TIERS[tier].label]
		frame = FCF_OpenNewWindow(name, true)
		if not frame then return false end
		Bind(frame, tier, name)
		ns.db.chatTabs = ns.db.chatTabs or {}
		ns.db.chatTabs[ns.me] = ns.db.chatTabs[ns.me] or {}
		ns.db.chatTabs[ns.me][tier] = { id = frame:GetID(), name = name }
		frame:AddMessage("Type here to speak in [" .. ns.L[ns.Channels.TIERS[tier].label] .. "]. Explicit slash commands work normally.")
	end
	local edit = frame.editBox or _G[frame:GetName() .. "EditBox"]
	if edit then
		if edit.SetChatType then edit:SetChatType("SAY") else edit:SetAttribute("chatType", "SAY") end
		if edit.SetStickyType then edit:SetStickyType("SAY") else edit:SetAttribute("stickyType", "SAY") end
		edit.olympusExplicit = nil
		RefreshInput(edit)
	end
	if FCF_SelectDockFrame and frame.isDocked then FCF_SelectDockFrame(frame) end
	if edit and ChatFrameUtil and ChatFrameUtil.SetLastActiveWindow then ChatFrameUtil.SetLastActiveWindow(edit)
	elseif ChatEdit_SetLastActiveWindow and edit then ChatEdit_SetLastActiveWindow(edit) end
	return true
end

function Tabs.Restore()
	local saved = ns.db.chatTabs and ns.db.chatTabs[ns.me]
	for tier, entry in pairs(saved or {}) do
		if ns.Channels.TIERS[tier] and type(entry) == "table" and type(entry.id) == "number" then
			local frame = _G["ChatFrame" .. entry.id]
			if frame then
				local name, active = Active(frame)
				if active and name == entry.name then
					local label = ns.L[ns.Channels.TIERS[tier].label]
					if name == "Olympus - " .. label and FCF_SetWindowName then
						FCF_SetWindowName(frame, label)
						name, entry.name = label, label
					end
					Bind(frame, tier, name)
				end
			end
		end
	end
end

ns.On("LOGIN", function() ns.After(1, "restore chat tabs", Tabs.Restore) end)
SLASH_OLYMPUSCHAT1 = "/olychat"
SlashCmdList.OLYMPUSCHAT = function(text)
	local tier = text:match("^%s*$") and "A" or ns.Channels.TierForWord(text)
	if not tier then ns.Print("Usage: /olychat [olympus|captains|lords]"); return end
	ns.SafeCall("open chat tab", Tabs.Open, tier)
end
