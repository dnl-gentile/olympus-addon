local _, ns = ...

-- A small native player-tooltip addition, inspired by PrettyTooltip's compact
-- unit details (MIT; https://github.com/FallenShard/PrettyTooltip). No external
-- code, fonts or artwork are bundled. Blizzard keeps its text, owner and anchor.
local P = {}; ns.PlayerTooltip = P
local L, GATE = ns.L, "player-tooltip"
local held, hooked, window

local function Secret(value)
	return type(issecretvalue) == "function" and issecretvalue(value) == true
end
local function Plain(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, value = pcall(fn, ...)
	if not ok or Secret(value) then return nil end
	return value
end
function P.Options()
	local o = type(ns.db) == "table" and type(ns.db.playerTooltip) == "table" and ns.db.playerTooltip or {}
	local scale = tonumber(o.scale) or 100
	if scale ~= scale then scale = 100 end
	return { details = o.details ~= false, colors = o.colors ~= false, scale = math.max(80, math.min(140, scale)) }
end

-- A hidden/cleared native tooltip and a gamepad switch all return the scale we
-- borrowed. Never touch native names, fonts, anchors, health bars or ownership.
function P.Restore() -- gp:player-tooltip!undo
	local old = held
	held = nil
	if old and old.scale then
		local current = Plain(old.tooltip.GetScale, old.tooltip)
		if current == old.applied then old.tooltip:SetScale(old.scale) end
	end
end

function P.Set(key, value)
	if type(ns.db) ~= "table" then return false end
	if key == "scale" then
		if type(value) ~= "number" or value ~= value or value < 80 or value > 140 then return false end
	elseif (key ~= "details" and key ~= "colors") or type(value) ~= "boolean" then return false end
	ns.db.playerTooltip = type(ns.db.playerTooltip) == "table" and ns.db.playerTooltip or {}
	ns.db.playerTooltip[key] = value
	P.Restore()
	return true
end

function P.Apply(tooltip, unit, name, guild) -- gp:player-tooltip
	if not ns.Gate.Allowed(GATE) then return false end
	if tooltip ~= GameTooltip or Secret(unit) or Secret(name) or Secret(guild)
		or type(unit) ~= "string" or type(name) ~= "string" or not ns.IsMember() then return false end
	if Plain(tooltip.IsForbidden, tooltip) == true or Plain(InCombatLockdown) == true then return false end
	-- A player's cover and the council's private identities keep the same policy
	-- as the existing tooltip additions. No inferred role or cached guild rank.
	if ns.Inspect.CoverOf(name) or (ns.CouncilMasked() and ns.IsHighCouncillor(name)) then return false end
	local moderation = ns.Moderation
	if name ~= ns.me and type(moderation) == "table" and type(moderation.Hides) == "function" and moderation.Hides(name, guild) then return false end
	local o = P.Options()
	if not o.details then return false end
	if held and (held.tooltip ~= tooltip or held.name ~= name) then P.Restore() end
	if not held then held = { tooltip = tooltip, name = name } end
	if o.scale ~= 100 and not held.scale and type(tooltip.GetScale) == "function" and type(tooltip.SetScale) == "function" then
		local scale = Plain(tooltip.GetScale, tooltip)
		if type(scale) == "number" and scale > 0 and scale < math.huge then
			held.scale, held.applied = scale, scale * o.scale / 100
			tooltip:SetScale(held.applied)
		end
	end
	if not held.fugitive and ns.FederationFugitives and ns.FederationFugitives.Visible(name) then
		tooltip:AddLine(L.FUGITIVES_TAG, 1, 0.62, 0.32)
		held.fugitive = true
	end
	if held.line or type(guild) ~= "string" or not ns.IsFederation(guild) then return true end
	local liveGuild, rank = GetGuildInfo(unit)
	if Secret(liveGuild) or Secret(rank) or liveGuild ~= guild or type(rank) ~= "string" or rank == "" then return true end
	local text = ns.Codec.Plain(guild) .. " · " .. ns.Codec.Plain(rank)
	local r, g, b = 1, 0.82, 0
	if o.colors then
		local _, class = UnitClass(unit)
		if not Secret(class) and type(class) == "string" then
			local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
			if color and not Secret(color.r) and not Secret(color.g) and not Secret(color.b)
				and type(color.r) == "number" and type(color.g) == "number" and type(color.b) == "number" then r, g, b = color.r, color.g, color.b end
		end
	end
	tooltip:AddLine(text, r, g, b)
	held.line = true
	return true
end

local function Install() -- gp:player-tooltip!hook
	if not ns.Gate.Allowed(GATE) then return end
	if hooked or not GameTooltip or type(GameTooltip.HookScript) ~= "function" then return end
	hooked = true
	GameTooltip:HookScript("OnHide", function() -- gp:player-tooltip!undo
		P.Restore()
	end)
	GameTooltip:HookScript("OnTooltipCleared", function() -- gp:player-tooltip!undo
		P.Restore()
	end)
end
ns.Gate.Hooks(GATE, { install = Install, park = P.Restore, leftover = function() return held ~= nil end })
ns.On("LOGIN", function()
	ns.Gate.Install(GATE)
	ns.RegisterEvent("PLAYER_REGEN_DISABLED", P.Restore)
end)

-- Olympus's own panel; no native settings frame or borrowed controls.
function P.OpenSettings()
	if not ns.IsMember() then return false end
	if not window then
		local f = ns.Window("OlympusPlayerTooltipOptions", nil, { title = L.PLAYER_TOOLTIP_SETTINGS, inset = false })
		f:SetSize(390, 400); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
		local note = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		note:SetPoint("TOPLEFT", 24, -45); note:SetWidth(342); note:SetJustifyH("LEFT"); note:SetText(L.PLAYER_TOOLTIP_DESC)
		f.checks = {}
		for i, item in ipairs({ { "details", L.PLAYER_TOOLTIP_DETAILS }, { "colors", L.PLAYER_TOOLTIP_COLORS } }) do
			local key = item[1]
			local button = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
			button:SetPoint("TOPLEFT", 22, -95 - (i - 1) * 32); button:SetSize(28, 28)
			local label = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
			label:SetPoint("LEFT", button, "RIGHT", 4, 0); label:SetText(item[2])
			button:SetScript("OnClick", function(self) P.Set(key, self:GetChecked() == true) end)
			f.checks[key] = button
		end
		f.size = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		f.size:SetPoint("TOPLEFT", 24, -174)
		for i, item in ipairs({ { "-", -10 }, { "+", 10 } }) do
			local delta = item[2]
			local button = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
			button:SetSize(36, 28); button:SetPoint("TOPRIGHT", -68 + (i - 1) * 40, -166); button:SetText(item[1])
			button:SetScript("OnClick", function()
				P.Set("scale", math.max(80, math.min(140, P.Options().scale + delta)))
				f.size:SetText(L.PLAYER_TOOLTIP_SIZE:format(P.Options().scale))
			end)
		end
		-- 1.5.5 (a contributor's ask): Olympus's lines in the game's right-click menus, on or off
		-- (PlayerMenu.SetEnabled, the same switch as /oly menus), and when that takes effect.
		local head = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		head:SetPoint("TOPLEFT", 24, -214); head:SetText(L.PLAYERMENU_SETTING)
		local menus = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
		menus:SetPoint("TOPLEFT", 22, -236); menus:SetSize(28, 28)
		local menusLabel = menus:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		menusLabel:SetPoint("LEFT", menus, "RIGHT", 4, 0); menusLabel:SetWidth(300); menusLabel:SetJustifyH("LEFT")
		menusLabel:SetText(L.PLAYERMENU_SETTING_LABEL)
		menus:SetScript("OnClick", function(self)
			local PM = ns.PlayerMenu
			if PM and PM.SetEnabled then PM.SetEnabled(self:GetChecked() == true) end
		end)
		local menusNote = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		menusNote:SetPoint("TOPLEFT", 24, -270); menusNote:SetWidth(342); menusNote:SetJustifyH("LEFT")
		menusNote:SetText(L.PLAYERMENU_SETTING_NOTE)
		f.menus, f.menusNote = menus, menusNote
		local footer = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		footer:SetPoint("BOTTOMLEFT", 24, 28); footer:SetWidth(342); footer:SetJustifyH("LEFT"); footer:SetText(L.PLAYER_TOOLTIP_NEXT)
		window = f
	end
	local o = P.Options()
	for key, button in pairs(window.checks) do button:SetChecked(o[key]) end
	window.menus:SetChecked(not (ns.PlayerMenu and ns.PlayerMenu.Enabled and not ns.PlayerMenu.Enabled()))
	window.size:SetText(L.PLAYER_TOOLTIP_SIZE:format(o.scale))
	window:Show(); window:Raise()
	return window
end
