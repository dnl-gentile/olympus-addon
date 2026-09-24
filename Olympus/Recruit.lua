local ADDON, ns = ...
local L = ns.L

-- "Join Olympus", for players who are NOT in an Olympus guild yet (the only thing the addon
-- does for them). It uses the game's own /who (Who.lua), which anyone can run, so it needs
-- no Olympus data at all: find Olympus members online, group them by guild, and whisper one
-- of them a ready-made request. No answer? Try someone else. Rate limited so nobody gets
-- spammed.

local Recruit = {}
ns.Recruit = Recruit

local ASK_COOLDOWN = 20

Recruit.found = {}      -- list of { name, guild, level, class, zone }
Recruit.asked = {}      -- [name] = time we whispered them
Recruit.replied = {}    -- [name] = their answer
Recruit.lastAsk = 0

-- Must be called from a click (the game requires a hardware event for /who). Each click
-- searches further once the game's 50 per search are not enough (see Who.lua).
function Recruit.Search()
	return ns.Who.Search()
end

-- Every answer: all the Olympus members found in this round of searches.
ns.Who.Listen(function(list)
	Recruit.found = list
	ns.Log("recruit: /who lists %d Olympus members", #list)
	ns.Fire("RECRUIT_CHANGED")
end)

-- Guilds seen online, biggest first: { name, online = n, members = {...} }
function Recruit.Guilds()
	local by, out = {}, {}
	for _, p in ipairs(Recruit.found) do
		local g = by[p.guild]
		if not g then
			g = { name = p.guild, members = {} }
			by[p.guild] = g
			out[#out + 1] = g
		end
		g.members[#g.members + 1] = p
	end
	table.sort(out, function(a, b)
		if #a.members ~= #b.members then return #a.members > #b.members end
		return a.name < b.name
	end)
	return out
end

-- The next member of that guild we have not asked yet (any guild if nil).
function Recruit.NextContact(guild)
	for _, p in ipairs(Recruit.found) do
		if (not guild or p.guild == guild) and not Recruit.asked[p.name] then return p end
	end
	return nil
end

function Recruit.Message(contact)
	local level = UnitLevel("player")
	local className = UnitClass("player") or ""
	return L.RECRUIT_MESSAGE:format(contact.guild, level, className)
end

-- Sends the (edited) request. Called from the popup's Send button, i.e. by the player.
function Recruit.Ask(contact, message)
	local now = GetTime()
	if now - Recruit.lastAsk < ASK_COOLDOWN then
		ns.Print(L.RECRUIT_WAIT:format(math.ceil(ASK_COOLDOWN - (now - Recruit.lastAsk))))
		return false
	end
	if not contact or not message or message == "" then return false end
	Recruit.lastAsk = now
	Recruit.asked[contact.name] = ns.Now()
	Recruit.lastContact = contact
	SendChatMessage(message:sub(1, 250), "WHISPER", nil, contact.name)
	ns.Log("recruit: asked %s <%s>", contact.name, contact.guild)
	ns.Fire("RECRUIT_CHANGED")
	return true
end

function Recruit.PromptNext(guild)
	local contact = Recruit.NextContact(guild)
	if not contact then
		ns.Print(#Recruit.found == 0 and L.RECRUIT_SEARCH_FIRST or L.RECRUIT_NOBODY_LEFT)
		return
	end
	StaticPopup_Show("OLYMPUS_RECRUIT", contact.name, contact.guild, contact)
end

-- The tone of the Join screen, in the spirit of Olympus: other guilds should not exist.
function Recruit.Roast()
	local guild = GetGuildInfo("player")
	if guild and guild ~= "" then
		return L.ROAST_GUILD:format(guild), L.ROAST_GUILD_SUB
	end
	return L.ROAST_NOGUILD, L.ROAST_NOGUILD_SUB
end

-- Once a day, a reminder in chat for players outside Olympus.
local function DailyNag()
	if ns.IsMember() then return end
	local today = date("%Y-%m-%d")
	if ns.db.lastNag == today then return end
	ns.db.lastNag = today
	local header, sub = Recruit.Roast()
	ns.Print("|cffff4040" .. header .. "|r " .. sub .. " |cffffd200/oly|r")
end

ns.On("LOGIN", function()
	ns.After(12, "daily nag", DailyNag)
	ns.RegisterEvent("CHAT_MSG_WHISPER", function(text, sender)
		local who = ns.ShortName(sender)
		for name in pairs(Recruit.asked) do
			if ns.ShortName(name) == who then
				Recruit.replied[name] = text
				ns.Print(L.RECRUIT_REPLIED:format(who))
				ns.Fire("RECRUIT_CHANGED")
				return
			end
		end
	end)
end)

StaticPopupDialogs["OLYMPUS_RECRUIT"] = {
	text = "%s  <%s>",
	button1 = SEND_LABEL or "Send",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 320,
	maxLetters = 250,
	OnShow = function(self, contact)
		local eb = self.editBox or self.EditBox
		if eb and contact then
			eb:SetText(Recruit.Message(contact))
			eb:HighlightText(0, 0)
			eb:SetFocus()
		end
	end,
	OnAccept = function(self, contact)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("recruit ask", Recruit.Ask, contact, eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		ns.SafeCall("recruit ask", Recruit.Ask, parent.data, self:GetText())
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}
