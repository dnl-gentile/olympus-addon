local ADDON, ns = ...
local L = ns.L

-- A public guild card, written only by its current master. GC is the master's own logged
-- channel word. QC/QD are bounded recruitment whispers; two queried members must report the
-- exact same card before it affects Join. A reported card grants no rank or contact authority.
local Charter = {}
ns.GuildCharter = Charter
Charter.LIFE = 7 * 86400
Charter.EVERY = 300
Charter.PURPOSE_MAX, Charter.NIGHTS_MAX = 48, 24
Charter.MAX, Charter.ANSWER_MAX = 150, 3
Charter.ASK_WAIT, Charter.REPORT_LIFE = 60, 600
Charter.ANSWER_EACH, Charter.ANSWERS_PER_MINUTE = 60, 10
local held, reports, asked, answered, answerTimes = {}, {}, {}, {}, {}
local lastSent, sending = -math.huge, false
local LANGUAGES = { enUS = true, enGB = true, ptBR = true, deDE = true, frFR = true,
	esES = true, esMX = true, ruRU = true, koKR = true, zhCN = true, zhTW = true }
local function Clock() return math.floor((GetServerTime and GetServerTime()) or ns.Now()) end
local function Key(name) return type(name) == "string" and ns.FullName(ns.Normal(name)) or nil end
local function Faction() return ns.faction == "Horde" and "H" or "A" end
local function Clean(s, limit)
	return ns.Cut(tostring(s or ""):gsub("[~|%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""), limit)
end
local function Field(s, limit)
	return type(s) == "string" and #s <= limit and not s:find("[~|%c]") and Clean(s, limit) == s
end
local function RealmOK(name)
	return type(name) == "string" and ns.GroupOf(ns.RealmOf(name) or ns.realm) == ns.GroupOf(ns.realm)
end
local function Changed()
	ns.Fire("REALM_PAGE_CHANGED", "guildcharter")
	ns.Fire("RECRUIT_CHANGED")
end
function Charter.IsMaster()
	if not ns.IsMember() then return false end
	local guild, _, rank = GetGuildInfo("player")
	return rank == 0 and type(guild) == "string" and ns.IsFederation(guild), guild
end
local function Authorized(by, guild)
	if not RealmOK(by) or not ns.IsFederation(guild) then return false end
	if ns.Moderation and ns.Moderation.Hides and ns.Moderation.Hides(by, guild) then return false end
	local rank, source, support = ns.Data.AuthorizedRank(by, guild)
	return rank == 0 and (source ~= "census" or ((support or 0) >= 2 and ns.Data.Dispute(ns.Data.Guild(guild)) == nil))
end
local function Classes(input)
	local list, set = {}, {}
	for word in tostring(input or ""):gmatch("[^,%s]+") do
		local code = ns.Roster.ClassCode(word:upper())
		if not ns.CLASS_FILES[code] or set[code] then return nil end
		set[code], list[#list + 1] = true, code
		if #list > 12 then return nil end
	end
	table.sort(list)
	return table.concat(list, ",")
end
local function Valid(c)
	local now = Clock()
	return type(c) == "table" and Field(c.guild, 40) and c.guild ~= "" and ns.IsFederation(c.guild)
		and Field(c.by, 64) and c.by ~= "" and Key(c.by) == c.by and RealmOK(c.by)
		and c.faction == Faction() and type(c.rev) == "number" and c.rev % 1 == 0
		and c.rev > now - Charter.LIFE and c.rev <= now + 60
		and LANGUAGES[c.language] == true and Field(c.wanted, 35) and Classes(c.wanted) == c.wanted
		and Field(c.nights, Charter.NIGHTS_MAX) and Field(c.purpose, Charter.PURPOSE_MAX)
end
function Charter.Encode(c, kind)
	if not Valid(c) then return nil end
	local fields = { kind or "GC", "1", c.faction, c.guild }
	if kind == "QD" then fields[#fields + 1] = c.by end
	for _, value in ipairs({ tostring(c.rev), c.language, c.wanted, c.nights, c.purpose }) do fields[#fields + 1] = value end
	local msg = table.concat(fields, "~")
	return #msg <= 250 and msg or nil
end
function Charter.Parse(text, sender)
	if type(text) ~= "string" or #text > 250 then return nil end
	local f, guild, by, rev, language, wanted, nights, purpose
	if text:sub(1, 3) == "QD~" then
		f, guild, by, rev, language, wanted, nights, purpose = text:match("^QD~1~([AH])~([^~]+)~([^~]+)~(%d+)~([^~]+)~([^~]*)~([^~]*)~([^~]*)$")
	else
		f, guild, rev, language, wanted, nights, purpose = text:match("^GC~1~([AH])~([^~]+)~(%d+)~([^~]+)~([^~]*)~([^~]*)~([^~]*)$")
		by = Key(sender)
	end
	local c = { faction = f, guild = guild, by = by, rev = tonumber(rev), language = language,
		wanted = wanted, nights = nights, purpose = purpose }
	return Valid(c) and c or nil
end
function Charter.Ours()
	local master, guild = Charter.IsMaster()
	local c = ns.rdb and ns.rdb.guildCharterOwn and ns.rdb.guildCharterOwn[ns.me]
	return master and Valid(c) and c.guild == guild and c.by == ns.me and c or nil
end
local function Known(guild)
	local mine = Charter.Ours()
	if mine and mine.guild == guild then return mine end
	local c = type(guild) == "string" and held[guild:lower()]
	if c and Valid(c) and Authorized(c.by, c.guild) then return c end
	if guild then held[guild:lower()] = nil end
end
function Charter.Get(guild)
	local c = Known(guild)
	return c and c.purpose ~= "" and c or nil
end
function Charter.Handle(dist, sender, text)
	if dist ~= "CHANNEL" or not ns.IsMember() then return false end
	local c = Charter.Parse(text, sender)
	if not c or not Authorized(c.by, c.guild) then return false end
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm.DeliveredLogged and not ns.Comm.DeliveredLogged() then return false end
	local key, old = c.guild:lower(), held[c.guild:lower()]
	if old and old.by == c.by and old.rev >= c.rev then return false end
	if not old then
		local n = 0
		for g in pairs(held) do if Known(g) then n = n + 1 end end
		if n >= Charter.MAX then return false end
	end
	held[key] = c
	Changed()
	return true
end
function Charter.Send(force)
	local c, now = Charter.Ours(), ns.Now()
	if not c or now - lastSent < 10 or (not force and now - lastSent < Charter.EVERY) then return false end
	local msg = Charter.Encode(c)
	if not msg then return false end
	lastSent = now
	return ns.Comm.Send("CHANNEL", msg, "guildcharter", false, true, nil, {
		guard = function() return Charter.Ours() == c end,
	})
end
local function SendSoon()
	if sending then return end
	sending = true
	ns.After(math.max(3, 10 - (ns.Now() - lastSent)), "guild charter", function()
		sending = false
		Charter.Send(true)
	end)
end
function Charter.SetField(field, input, expectedGuild)
	local master, guild = Charter.IsMaster()
	if not master or (expectedGuild and expectedGuild ~= guild) then return false end
	local old = Charter.Ours()
	local c = { guild = guild, by = ns.me, faction = Faction(), rev = math.max(Clock(), (old and old.rev or 0) + 1),
		language = old and old.language or (LANGUAGES[GetLocale()] and GetLocale() or "enUS"),
		wanted = old and old.wanted or "", nights = old and old.nights or "", purpose = old and old.purpose or "" }
	if field == "purpose" then c.purpose = Clean(input, Charter.PURPOSE_MAX)
	elseif field == "nights" then c.nights = Clean(input, Charter.NIGHTS_MAX)
	elseif field == "language" then if not LANGUAGES[input] then ns.Print(L.CHARTER_LANGUAGE_HINT); return false end; c.language = input
	elseif field == "wanted" then c.wanted = Classes(input); if not c.wanted then ns.Print(L.CHARTER_CLASSES_HINT); return false end
	else return false end
	if not Charter.Encode(c) then return false end
	ns.rdb.guildCharterOwn = type(ns.rdb.guildCharterOwn) == "table" and ns.rdb.guildCharterOwn or {}
	ns.rdb.guildCharterOwn[ns.me] = c
	Changed(); SendSoon()
	return true
end
function Charter.Ask(name)
	if ns.IsMember() then return false end
	name = Key(name)
	if not name or not RealmOK(name) then return false end
	local now = ns.Now()
	for source, at in pairs(asked) do if now - at > Charter.ASK_WAIT then asked[source] = nil end end
	if asked[name] and now - asked[name] < Charter.ASK_WAIT then return false end
	local n = 0; for _ in pairs(asked) do n = n + 1 end
	if n >= 3 or not ns.Comm.WhisperOutside(ns.TellName(name), "QC~1~" .. Faction()) then return false end
	asked[name] = now
	return true
end
function Charter.HandleAsk(dist, sender, text)
	if dist ~= "WHISPER" or text ~= "QC~1~" .. Faction() or not ns.IsMember() or not RealmOK(sender) then return false end
	local now, source = ns.Now(), Key(sender)
	for who, at in pairs(answered) do if now - at >= Charter.ANSWER_EACH then answered[who] = nil end end
	for i = #answerTimes, 1, -1 do if now - answerTimes[i] >= 60 then table.remove(answerTimes, i) end end
	if answered[source] or #answerTimes >= Charter.ANSWERS_PER_MINUTE then return false end
	answered[source], answerTimes[#answerTimes + 1] = now, now
	local cards, own = {}, Charter.Ours()
	if own then cards[#cards + 1] = own end
	for guild in pairs(held) do
		local c = Known(guild)
		if c and (not own or c.guild ~= own.guild) then cards[#cards + 1] = c end
	end
	table.sort(cards, function(a, b)
		if (a == own) ~= (b == own) then return a == own end
		return a.guild < b.guild
	end)
	for i = 1, math.min(#cards, Charter.ANSWER_MAX) do
		local c, msg = cards[i], Charter.Encode(cards[i], "QD")
		if msg then ns.Comm.Whisper(sender, msg, "charter " .. source .. " " .. c.guild, false, true, nil, {
			guard = function() return ns.IsMember() and Known(c.guild) == c end,
		}) end
	end
	return true
end
local function PruneReports()
	local now = ns.Now()
	for guild, sources in pairs(reports) do
		for source, entry in pairs(sources) do
			if now - entry.at > Charter.REPORT_LIFE or not Valid(entry.card) then sources[source] = nil end
		end
		if next(sources) == nil then reports[guild] = nil end
	end
end
function Charter.Reported(guild)
	PruneReports()
	local sources = type(guild) == "string" and reports[guild:lower()]
	local body, card, n = nil, nil, 0
	for _, entry in pairs(sources or {}) do
		local word = Charter.Encode(entry.card, "QD")
		if body and word ~= body then return nil end -- conflicting issuer/revision/body: unknown
		body, card, n = word, entry.card, n + 1
	end
	return n >= 2 and card.purpose ~= "" and card or nil
end
function Charter.OnReported(sender, text)
	if ns.IsMember() then return false end
	local source, now = Key(sender), ns.Now()
	if not source or not asked[source] or now - asked[source] > Charter.ASK_WAIT then return false end
	local found
	for _, p in ipairs(ns.Recruit and ns.Recruit.found or {}) do if Key(p.name) == source then found = true; break end end
	if not found then return false end
	local c = Charter.Parse(text)
	if not c then return false end
	PruneReports()
	local key = c.guild:lower()
	if not reports[key] then
		local n = 0; for _ in pairs(reports) do n = n + 1 end
		if n >= Charter.ANSWER_MAX * 3 then return false end
		reports[key] = {}
	end
	local old = reports[key][source]
	if old and old.card.by == c.by and old.card.rev > c.rev then return false end
	reports[key][source] = { card = c, at = now }
	Changed()
	if not Charter.Reported(c.guild) and ns.Recruit.ConfirmCharters then ns.Recruit.ConfirmCharters() end
	return true
end
function Charter.Affinity(guild, found)
	local c = ns.IsMember() and Charter.Get(guild) or Charter.Reported(guild)
	if not c then return { 0, 0, 0 }, nil end
	local _, class = UnitClass("player")
	local wanted = Classes(class or "")
	local classFit = wanted and wanted ~= "" and ("," .. c.wanted .. ","):find("," .. wanted .. ",", 1, true) ~= nil
	local friend, friendFit = ns.db and ns.db.recruitFriend, false
	for _, p in ipairs(found or {}) do
		if friend and p.guild == guild and Key(p.name) == friend then friendFit = true; break end
	end
	return { c.language:sub(1, 2) == GetLocale():sub(1, 2) and 1 or 0, classFit and 1 or 0, friendFit and 1 or 0 }, c
end
function Charter.SetFriend(input)
	local friend = Clean(input, 64)
	if friend == "" then ns.db.recruitFriend = nil
	elseif not Field(friend, 64) or not RealmOK(friend) then return false
	else ns.db.recruitFriend = Key(friend) end
	Changed()
	return true
end
function Charter.Prompt(field)
	if field == "friend" then return ns.Dialog.Show("OLYMPUS_CHARTER_FIELD", L.CHARTER_FRIEND, nil, { field = field }) end
	local master, guild = Charter.IsMaster()
	if not master then return nil end
	return ns.Dialog.Show("OLYMPUS_CHARTER_FIELD", L["CHARTER_" .. field:upper()], nil, { field = field, guild = guild })
end
function Charter.Confirm(data, text)
	if type(data) ~= "table" then return false end
	if data.field == "friend" then return Charter.SetFriend(text) end
	return Charter.SetField(data.field, text, data.guild)
end
StaticPopupDialogs["OLYMPUS_CHARTER_FIELD"] = {
	text = L.CHARTER_EDIT, button1 = L.CHARTER_SAVE, button2 = CANCEL or "Cancel",
	hasEditBox = true, editBoxWidth = 260, maxLetters = 64, maxBytes = 65,
	OnShow = function(self, data)
		data = data or self.data
		local c, eb = Charter.Ours(), self.editBox or self.EditBox
		if eb and data then
			eb:SetText(data.field == "friend" and (ns.db.recruitFriend or "") or (c and c[data.field] or ""))
			ns.Focus(eb)
		end
	end,
	OnAccept = function(self, data)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("guild charter", Charter.Confirm, data or self.data, eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		ns.SafeCall("guild charter", Charter.Confirm, parent.data, self:GetText()); parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
function Charter.CardLines(guild, reported)
	local c = reported and Charter.Reported(guild) or Charter.Get(guild)
	if not c then return { { indent = 1, text = L.CHARTER_UNKNOWN } } end
	local titles = {}
	for code in c.wanted:gmatch("[^,]+") do
		local file = ns.CLASS_FILES[code]
		titles[#titles + 1] = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file] or file
	end
	local purpose, nights = c.purpose, c.nights
	if ns.Filter and ns.Filter.Hides then
		if ns.Filter.Hides(purpose) then purpose = L.FILTER_WORDS_HIDDEN_SHORT end
		if ns.Filter.Hides(nights) then nights = L.FILTER_WORDS_HIDDEN_SHORT end
	end
	return {
		{ indent = 1, text = (reported and L.CHARTER_REPORTED or L.CHARTER_BY):format(ns.DisplayName(c.by), ns.Ago(c.rev)) },
		{ indent = 1, text = L.CHARTER_PURPOSE .. ": " .. purpose },
		{ indent = 1, text = L.CHARTER_LANGUAGE .. ": " .. c.language },
		{ indent = 1, text = L.CHARTER_NIGHTS .. ": " .. (nights ~= "" and nights or L.CHARTER_UNSPECIFIED) },
		{ indent = 1, text = L.CHARTER_WANTED .. ": " .. (#titles > 0 and table.concat(titles, ", ") or L.CHARTER_UNSPECIFIED) },
	}
end
function Charter.Link()
	if not ns.IsMember() then return nil end
	return { text = "|cffffd200> " .. L.CHARTER_TITLE .. "|r", onClick = function() ns.Views.ShowPage("guildcharter") end }
end
function Charter.Letter(guild)
	local c = Charter.Get(guild)
	if not ns.IsMember() or not c or c.by == ns.me or c.guild == GetGuildInfo("player") then return false end
	if ns.Recruit and ns.Recruit.NoContact(c.by) then return false end
	return ns.UI.WhisperText(ns.TellName(c.by), L.CHARTER_LETTER_TEXT:format(c.guild, GetGuildInfo("player") or "?"))
end
function Charter.Lines()
	if not ns.IsMember() then return {} end
	local master, guild = Charter.IsMaster()
	local lines = { { text = L.CHARTER_BACK, onClick = function() ns.Views.ShowPage(nil) end, gapAfter = true },
		{ header = true, text = L.CHARTER_TITLE }, { text = L.CHARTER_HINT, gapAfter = true } }
	for _, row in ipairs(Charter.CardLines(guild)) do lines[#lines + 1] = row end
	if master then
		for _, field in ipairs({ "purpose", "language", "nights", "wanted" }) do
			local f = field
			lines[#lines + 1] = { text = "> " .. L.CHARTER_EDIT_FIELD:format(L["CHARTER_" .. f:upper()]), onClick = function() Charter.Prompt(f) end }
		end
		lines[#lines + 1] = { text = "> " .. L.CHARTER_WITHDRAW, onClick = function() Charter.SetField("purpose", "", guild) end }
	end
	local others = {}
	for key in pairs(held) do
		local c = Charter.Get(key)
		if c and c.guild ~= guild then others[#others + 1] = c end
	end
	table.sort(others, function(a, b) return a.guild < b.guild end)
	for _, c in ipairs(others) do
		local destination = c.guild
		lines[#lines + 1] = { header = true, text = "<" .. destination .. ">" }
		for _, row in ipairs(Charter.CardLines(destination)) do lines[#lines + 1] = row end
		lines[#lines + 1] = { text = "> " .. L.CHARTER_LETTER, gapAfter = true,
			onClick = function() Charter.Letter(destination) end }
	end
	return lines
end
function Charter.ResetForTests()
	held, reports, asked, answered, answerTimes = {}, {}, {}, {}, {}
	lastSent, sending = -math.huge, false
end
ns.RealmPages = ns.RealmPages or {}
table.insert(ns.RealmPages, { key = "guildcharter", Link = Charter.Link, Lines = Charter.Lines, tip = "CHARTER_HINT" })
ns.Comm.Handle("GC", Charter.Handle)
ns.Comm.Handle("QC", Charter.HandleAsk)
ns.On("LOGIN", function() ns.Every(Charter.EVERY, "guild charter", function() Charter.Send() end) end)
