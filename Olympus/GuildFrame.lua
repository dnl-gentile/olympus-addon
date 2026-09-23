local ADDON, ns = ...
local L = ns.L

-- Hooks into Blizzard's own Guild window (Social > Guild) instead of replacing it: an
-- "Olympus" button in the guild frame opens our window docked to its right, on the
-- Realm tab. We never touch the Blizzard roster itself, so no taint and no breakage.

local GuildFrameHook = {}
ns.GuildFrameHook = GuildFrameHook

local button

local function Create()
	if button then return true end
	local host = GuildFrame
	if not host or not FriendsFrame then return false end
	-- Small button in the free corner of the header row, between the portrait and
	-- "Show Offline Members". Clicking again closes the docked window.
	button = ns.MakeRoundButton("OlympusGuildFrameButton", host, 26)
	button:SetPoint("TOPLEFT", FriendsFrame, "TOPLEFT", 62, -26)
	button:SetScript("OnClick", function()
		ns.SafeCall("guild frame button", function()
			if ns.UI.IsShown() and ns.UI.IsDocked() then ns.UI.CloseIfDocked() else ns.UI.OpenDocked(FriendsFrame, "census") end
		end)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L.TITLE, 1, 0.82, 0)
		GameTooltip:AddLine(L.GUILDFRAME_TIP, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	FriendsFrame:HookScript("OnHide", function() ns.UI.CloseIfDocked() end)
	host:HookScript("OnHide", function() ns.UI.CloseIfDocked() end)
	ns.Log("guild frame button added")
	return true
end

ns.On("LOGIN", function()
	if not Create() then
		ns.RegisterEvent("ADDON_LOADED", function(name)
			if name == "Blizzard_GuildUI" or name == "Blizzard_Communities" then Create() end
		end)
	end
end)
