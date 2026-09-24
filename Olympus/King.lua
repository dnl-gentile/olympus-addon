local ADDON, ns = ...
local L = ns.L

-- The Throne: a fifth tab for the King alone (the guild master of the guild named exactly
-- "Olympus" of his faction). What he sends goes out on the Olympus channel as T1 messages,
-- and every client checks that the sender really is that guild master (Data.KnownRank:
-- his own guildmates from their roster, everyone else from the census vote). Answers go
-- back to him alone (T2, T3 as whispered addon messages).
--   T1~S~<id>~<guild>                      Summon the Lords (roll call)
--   T1~I~<id>~<guild>                      Royal Inspection: every addon patrols 2 minutes
--   T1~A~<id>~<guild>~<minutes>~<zone>~<title>   The King's Agenda (resent every 5 min)
--   T1~X~<id>~<guild>                      Agenda cancelled
--   T2~<id>~<P|B>~<guild>                  a Lord's answer to the roll call
--   T3~<id>~<guild>~<ok>~<none>~<other>~<name:guild,...>   an inspection report

local King = {}
ns.King = King

King.SUMMON_OPEN = 60        -- the popup stays this long
King.SUMMON_GAP = 60         -- one roll call a minute at most (sent or accepted)
King.INSPECT_TIME = 120      -- each addon patrols this long
King.INSPECT_GAP = 600       -- one Royal Inspection every 10 minutes at most
King.AGENDA_RESEND = 300     -- the King's client repeats the agenda for late logins
King.MAX_NAMES = 6           -- violators per inspection report (message size)

King.mode = "letter"         -- what the tab shows: letter, summon, inspect, agenda
local summon, inspect        -- the King's own roll call / inspection in progress
local agenda                 -- the agenda everyone sees: { id, title, at, zone, by }
local lastSummonSeen, lastInspectSeen, inspecting = -math.huge, -math.huge, nil
local lastSummonSent, lastInspectSent = -math.huge, -math.huge

---------------------------------------------------------------------------
-- Who
---------------------------------------------------------------------------

function King.IsKing()
	if not ns.IsMember() then return false end
	local guild, _, rank = GetGuildInfo("player")
	return type(guild) == "string" and guild:lower() == "olympus" and rank == 0
end

-- The author's test build (Dev.lua, never published) shows the tab without the powers:
-- nothing it does reaches anyone.
function King.Preview()
	local dev = ns.devThrone
	if type(dev) == "table" then dev = dev[UnitName and UnitName("player") or ""] == true end
	return dev == true and not King.IsKing()
end
function King.Visible() return King.IsKing() or King.Preview() end

local function KingSender(sender, guild)
	return type(guild) == "string" and guild:lower() == "olympus" and ns.Data.KnownRank(sender, guild) == 0
end

local function Changed() ns.Fire("THRONE_CHANGED") end

local function Warn(text, loud)
	ns.Print("|cffffd200" .. text .. "|r")
	if RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 0.82, b = 0 })
	end
	ns.PlayAlert(loud and "loud" or "soft")
end

local function NewId() return math.random(1, 99999) end

-- Our tabard, checked the way a patrol checks others (level 15+ only: the Olympus rule).
local function OwnTabard()
	local level = UnitLevel and UnitLevel("player") or 0
	if level > 0 and level < (ns.Inspect.MIN_LEVEL or 15) then return nil end
	local item = GetInventoryItemID and GetInventoryItemID("player", INVSLOT_TABARD or 19)
	return ns.Inspect.Classify(item, true)
end

---------------------------------------------------------------------------
-- Summon the Lords
---------------------------------------------------------------------------

function King.Summon()
	King.mode = "summon"
	local now = ns.Now()
	if King.Preview() then
		summon = { id = 0, t = now, answers = {}, preview = true }
		ns.Print(L.THRONE_PREVIEW_NOTE)
		return Changed()
	end
	if not King.IsKing() then return end
	if now - lastSummonSent < King.SUMMON_GAP then
		ns.Print(L.THRONE_WAIT:format(math.ceil(King.SUMMON_GAP - (now - lastSummonSent))))
		return Changed()
	end
	lastSummonSent = now
	summon = { id = NewId(), t = now, answers = {} }
	ns.Comm.Send("CHANNEL", ("T1~S~%d~%s"):format(summon.id, GetGuildInfo("player")))
	ns.Log("throne: summon %d", summon.id)
	Changed()
end

local function OnSummon(king, id)
	local now = ns.Now()
	if now - lastSummonSeen < King.SUMMON_GAP then return end
	if not ns.IsMember() or ns.Roster.MyRank() > ns.CAPTAIN_RANK then return end
	lastSummonSeen = now
	ns.PlayAlert("soft")
	StaticPopup_Show("OLYMPUS_KING_SUMMON", ns.DisplayName(king), nil, { king = king, id = id })
end

local function Answer(data, word)
	if not data or not data.king then return end
	ns.Comm.Whisper(data.king, ("T2~%d~%s~%s"):format(data.id, word, GetGuildInfo("player") or ""))
end

StaticPopupDialogs["OLYMPUS_KING_SUMMON"] = {
	text = L.THRONE_SUMMONED,
	button1 = L.THRONE_PRESENT,
	button2 = L.THRONE_BUSY,
	OnAccept = function(self, data) ns.SafeCall("throne answer", Answer, data or self.data, "P") end,
	OnCancel = function(self, data, reason)
		if reason == "clicked" then ns.SafeCall("throne answer", Answer, data or self.data, "B") end
	end,
	timeout = King.SUMMON_OPEN,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- The Lords and Captains the census knows online, answered or not: { name, guild, rank }.
local function LordsOnline()
	local out = {}
	for _, e in ipairs(ns.Data.Summary().guilds) do
		local g = e.g
		if e.fresh then
			local home = g.realm or ns.realm
			if g.leader and g.leaderOnline then out[#out + 1] = { name = ns.FullName(g.leader, home), guild = e.name, rank = 0 } end
			for _, o in ipairs(g.officers or {}) do
				if o.online then out[#out + 1] = { name = ns.FullName(o.name, home), guild = e.name, rank = 1 } end
			end
		end
	end
	return out
end

function King.HandleAnswer(dist, sender, text)
	if dist ~= "WHISPER" or not summon or summon.preview then return end
	local id, word, guild = text:match("^T2~(%d+)~([PB])~(.*)$")
	if tonumber(id) ~= summon.id or ns.Now() - summon.t > 300 then return end
	sender = ns.FullName(sender)
	guild = guild:gsub("|", ""):sub(1, 24) -- shown on the King's screen (the stream): no escape codes
	local rank = ns.IsFederation(guild) and ns.Data.KnownRank(sender, guild) or nil
	summon.answers[sender] = { word = word, guild = guild, verified = rank ~= nil and rank <= ns.CAPTAIN_RANK, t = ns.Now() }
	Changed()
end
ns.Comm.Handle("T2", function(...) King.HandleAnswer(...) end)

---------------------------------------------------------------------------
-- Royal Inspection
---------------------------------------------------------------------------

function King.Inspect()
	King.mode = "inspect"
	local now = ns.Now()
	if King.Preview() then
		ns.Print(L.THRONE_PREVIEW_NOTE)
		inspect = { id = 0, t = now, reports = {}, preview = true }
		King.RunInspection(nil, 0) -- our own patrol only, reported to ourselves
		return Changed()
	end
	if not King.IsKing() then return end
	if now - lastInspectSent < King.INSPECT_GAP then
		ns.Print(L.THRONE_WAIT:format(math.ceil(King.INSPECT_GAP - (now - lastInspectSent))))
		return Changed()
	end
	lastInspectSent = now
	inspect = { id = NewId(), t = now, reports = {} }
	ns.Comm.Send("CHANNEL", ("T1~I~%d~%s"):format(inspect.id, GetGuildInfo("player")))
	ns.Log("throne: inspection %d", inspect.id)
	King.RunInspection(ns.me, inspect.id) -- the King patrols too
	Changed()
end

-- Every addon (the King's too): a raid warning, a patrol of INSPECT_TIME, then a report to
-- the King of what it saw (and our own tabard).
function King.RunInspection(king, id)
	if inspecting or not ns.IsMember() then return end
	local start = ns.Now()
	inspecting = { king = king, id = id, start = start, wasOn = ns.Inspect.IsPatrolling() }
	Warn(L.THRONE_INSPECT_WARN, true)
	if not inspecting.wasOn then ns.Inspect.SetPatrol(true) end
	ns.After(King.INSPECT_TIME, "royal inspection", function()
		local run = inspecting
		inspecting = nil
		if not run then return end
		if not run.wasOn and ns.Inspect.IsPatrolling() then ns.Inspect.SetPatrol(false) end
		local ok, none, other, names = 0, 0, 0, {}
		for name, p in pairs(ns.Inspect.Players()) do
			if (p.t or 0) >= run.start then
				if p.status == "GUILD" then ok = ok + 1
				elseif p.status == "NONE" or p.status == "OTHER" then
					if p.status == "NONE" then none = none + 1 else other = other + 1 end
					if #names < King.MAX_NAMES then names[#names + 1] = (ns.DisplayName(name) or "?") .. ":" .. (p.guild or "?") .. ":" .. (p.status == "NONE" and "N" or "O") end
				end
			end
		end
		local own = OwnTabard()
		if own == "GUILD" then ok = ok + 1 elseif own == "NONE" then none = none + 1 elseif own == "OTHER" then other = other + 1 end
		local guild = GetGuildInfo("player") or ""
		local msg = ("T3~%d~%s~%d~%d~%d~%s"):format(run.id or 0, guild, ok, none, other, table.concat(names, ","))
		if run.king == ns.me or not run.king then
			King.ReceiveReport(ns.me, msg) -- ours (the King's, or the preview's)
		else
			ns.Comm.Whisper(run.king, msg:sub(1, 250))
		end
	end)
end

local function OnInspect(king, id)
	local now = ns.Now()
	if now - lastInspectSeen < King.INSPECT_GAP then return end
	lastInspectSeen = now
	King.RunInspection(king, id)
end

function King.ReceiveReport(sender, text)
	if not inspect then return end
	local id, guild, ok, none, other, names = text:match("^T3~(%d+)~([^~]*)~(%d+)~(%d+)~(%d+)~(.*)$")
	if not id or tonumber(id) ~= inspect.id or ns.Now() - inspect.t > 900 then return end
	local list = {}
	for entry in names:gmatch("[^,]+") do
		local n, g, s = entry:match("^([^:]+):([^:]*):([NO])$")
		if n and #list < King.MAX_NAMES then
			list[#list + 1] = { name = n:gsub("|", ""):sub(1, 48), guild = g:gsub("|", ""):sub(1, 24), status = s == "N" and "NONE" or "OTHER" }
		end
	end
	sender = ns.FullName(sender)
	if not inspect.reports[sender] then
		local count = 0
		for _ in pairs(inspect.reports) do count = count + 1 end
		if count >= 300 then return end -- one report per sender, and a few hundred at most
	end
	inspect.reports[sender] = { guild = guild:gsub("|", ""):sub(1, 24), ok = math.min(tonumber(ok) or 0, 200),
		none = math.min(tonumber(none) or 0, 200), other = math.min(tonumber(other) or 0, 200), names = list }
	Changed()
end

function King.HandleReport(dist, sender, text)
	if dist ~= "WHISPER" or not King.IsKing() then return end
	King.ReceiveReport(sender, text)
end
ns.Comm.Handle("T3", function(...) King.HandleReport(...) end)

-- The violators the inspection found go on the King's own list, then the usual Wall of Shame.
function King.PublishShame()
	if not inspect then return end
	for _, r in pairs(inspect.reports) do
		for _, v in ipairs(r.names) do ns.Inspect.AddReported(v.name, v.guild, v.status) end
	end
	if King.Preview() then
		ns.Print(L.THRONE_PREVIEW_NOTE)
		return
	end
	ns.Inspect.PublishShame()
end

---------------------------------------------------------------------------
-- The King's Agenda
---------------------------------------------------------------------------

local function ZoneName()
	return (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
end

local function Clean(s, n) return (tostring(s or ""):gsub("[~|\n]", " "):sub(1, n)) end

-- "30 Raid on Crossroads": minutes first, then the title.
function King.ParseAgenda(input)
	local minutes, title = tostring(input or ""):match("^%s*(%d+)%s+(.-)%s*$")
	minutes = tonumber(minutes)
	if not minutes or minutes < 1 or minutes > 720 or title == "" then return nil end
	return minutes, Clean(title, 60)
end

function King.SetAgenda(input)
	local minutes, title = King.ParseAgenda(input)
	if not minutes then
		ns.Print(L.THRONE_AGENDA_USAGE)
		return false
	end
	local now = ns.Now()
	local mine = { id = NewId(), title = title, at = now + minutes * 60, zone = Clean(ZoneName(), 40), by = ns.me, mine = true }
	if King.Preview() then
		agenda = mine
		ns.Print(L.THRONE_PREVIEW_NOTE)
		return Changed() or true
	end
	if not King.IsKing() then return false end
	agenda = mine
	King.SendAgenda()
	Warn(L.THRONE_AGENDA_SET:format(title, minutes, mine.zone))
	Changed()
	return true
end

function King.SendAgenda()
	if not agenda or not agenda.mine or King.Preview() then return end
	local left = math.ceil((agenda.at - ns.Now()) / 60)
	if left < 1 then return end
	ns.Comm.Send("CHANNEL", ("T1~A~%d~%s~%d~%s~%s"):format(agenda.id, GetGuildInfo("player") or "", left, agenda.zone, agenda.title), "agenda")
end

function King.CancelAgenda()
	if not agenda then return end
	if agenda.mine and not King.Preview() then
		ns.Comm.Send("CHANNEL", ("T1~X~%d~%s"):format(agenda.id, GetGuildInfo("player") or ""), "agenda")
	end
	agenda = nil
	Changed()
end

function King.Agenda()
	if agenda and agenda.at < ns.Now() - 600 then agenda = nil end -- over for 10 minutes
	return agenda
end

local function OnAgenda(king, id, rest)
	local minutes, zone, title = rest:match("^(%d+)~([^~]*)~(.*)$")
	minutes = tonumber(minutes)
	if not minutes or minutes < 1 or minutes > 720 or title == "" then return end
	local known = agenda and agenda.id == id
	agenda = { id = id, title = Clean(title, 60), at = ns.Now() + minutes * 60, zone = Clean(zone, 40), by = king }
	if not known then Warn(L.THRONE_AGENDA_SET:format(agenda.title, minutes, agenda.zone)) end
	Changed()
end

function King.HandleCommand(dist, sender, text)
	if dist ~= "CHANNEL" then return end
	local kind, id, guild, rest = text:match("^T1~(%a)~(%d+)~([^~]*)~?(.*)$")
	if not kind then return end
	if not KingSender(sender, guild) then
		ns.Log("throne %s from %s ignored: not the King of %s", kind, sender, tostring(guild))
		return
	end
	id = tonumber(id)
	if kind == "S" then OnSummon(sender, id)
	elseif kind == "I" then OnInspect(sender, id)
	elseif kind == "A" then OnAgenda(sender, id, rest)
	elseif kind == "X" and agenda and agenda.id == id then
		agenda = nil
		Changed()
	end
end
ns.Comm.Handle("T1", function(...) King.HandleCommand(...) end)

ns.On("LOGIN", function()
	ns.Every(60, "agenda", function()
		local a = King.Agenda()
		if not a then return end
		local left = a.at - ns.Now()
		-- Reminders for everyone, and the King's client repeats it for late logins.
		for _, mark in ipairs({ 600, 60 }) do
			if left <= mark and left > mark - 60 then Warn(L.THRONE_AGENDA_SOON:format(a.title, math.max(1, math.ceil(left / 60)), a.zone)) end
		end
		if a.mine and (not a.sentAt or ns.Now() - a.sentAt >= King.AGENDA_RESEND) then
			a.sentAt = ns.Now()
			King.SendAgenda()
		end
		Changed()
	end)
end)

StaticPopupDialogs["OLYMPUS_KING_AGENDA"] = {
	text = L.THRONE_AGENDA_PROMPT,
	button1 = OKAY or "OK",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 260,
	maxLetters = 70,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then eb:SetText("30 "); eb:SetFocus() end
	end,
	OnAccept = function(self)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("agenda", King.SetAgenda, eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		ns.SafeCall("agenda", King.SetAgenda, self:GetText())
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function King.AgendaPrompt()
	King.mode = "agenda"
	StaticPopup_Show("OLYMPUS_KING_AGENDA")
	Changed()
end

---------------------------------------------------------------------------
-- What the tab shows (parchment, dark text: line.font)
---------------------------------------------------------------------------

local INK, TITLE = "QuestFont", "QuestTitleFont"

local function Line(text, font, extra)
	local l = { text = text, font = font or INK }
	for k, v in pairs(extra or {}) do l[k] = v end
	return l
end

function King.LetterLines()
	local lines = {}
	for part in (L.THRONE_LETTER .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = Line(part, part:find("^%*") and TITLE or INK)
		if part:find("^%*") then lines[#lines].text = part:sub(2) end
	end
	return lines
end

local function SummonLines()
	local lines = { Line(L.THRONE_SUMMON_TITLE, TITLE) }
	if not summon then
		lines[#lines + 1] = Line(L.THRONE_SUMMON_HINT)
		return lines
	end
	local present, busy = {}, {}
	for name, a in pairs(summon.answers) do
		local row = Line(("%s <%s>%s"):format(ns.DisplayName(name), a.guild, a.verified and "" or " (?)"), INK)
		if a.word == "P" then present[#present + 1] = row else busy[#busy + 1] = row end
	end
	lines[#lines + 1] = Line(L.THRONE_PRESENT_N:format(#present), INK, { header = true, font = TITLE })
	for _, r in ipairs(present) do r.indent = 1; lines[#lines + 1] = r end
	lines[#lines + 1] = Line(L.THRONE_BUSY_N:format(#busy), INK, { header = true, font = TITLE })
	for _, r in ipairs(busy) do r.indent = 1; lines[#lines + 1] = r end
	local silent = {}
	for _, lord in ipairs(LordsOnline()) do
		if not summon.answers[lord.name] and lord.name ~= ns.me then silent[#silent + 1] = lord end
	end
	lines[#lines + 1] = Line(L.THRONE_SILENT_N:format(#silent), INK, { header = true, font = TITLE })
	for _, lord in ipairs(silent) do lines[#lines + 1] = Line(("%s <%s>"):format(ns.DisplayName(lord.name), lord.guild), INK, { indent = 1 }) end
	return lines
end

local function AgendaLines()
	local lines = { Line(L.THRONE_AGENDA_TITLE, TITLE) }
	local a = King.Agenda()
	if a then
		lines[#lines + 1] = Line(L.THRONE_AGENDA_LINE:format(a.title, math.max(0, math.ceil((a.at - ns.Now()) / 60)), a.zone))
	else
		lines[#lines + 1] = Line(L.THRONE_AGENDA_NONE)
	end
	return lines
end

local function InspectLines()
	local lines = { Line(L.THRONE_INSPECT_TITLE, TITLE) }
	if not inspect then
		lines[#lines + 1] = Line(L.THRONE_INSPECT_HINT)
		return lines
	end
	local ok, bad, reporters, byGuild, names = 0, 0, 0, {}, {}
	for _, r in pairs(inspect.reports) do
		reporters = reporters + 1
		ok, bad = ok + r.ok, bad + r.none + r.other
		local g = byGuild[r.guild] or { ok = 0, bad = 0 }
		g.ok, g.bad = g.ok + r.ok, g.bad + r.none + r.other
		byGuild[r.guild] = g
		for _, v in ipairs(r.names) do names[#names + 1] = v end
	end
	local total = ok + bad
	local left = inspect.t + King.INSPECT_TIME + 10 - ns.Now()
	if left > 0 then lines[#lines + 1] = Line(L.THRONE_INSPECT_RUNNING:format(math.ceil(left))) end
	lines[#lines + 1] = Line(L.THRONE_INSPECT_SUMMARY:format(reporters, total, total > 0 and math.floor(ok * 100 / total + 0.5) or 0))
	for guild, g in pairs(byGuild) do
		local n = g.ok + g.bad
		lines[#lines + 1] = Line(("%s: %d%%  (%d/%d)"):format(guild, n > 0 and math.floor(g.ok * 100 / n + 0.5) or 0, g.ok, n), INK, { indent = 1 })
	end
	if #names > 0 then
		lines[#lines + 1] = Line(L.THRONE_VIOLATORS:format(#names), INK, { header = true, font = TITLE })
		for _, v in ipairs(names) do
			lines[#lines + 1] = Line(("%s <%s>  %s"):format(v.name, v.guild, v.status == "NONE" and L.TABARD_NONE or L.TABARD_OTHER), INK, { indent = 1 })
		end
	end
	return lines
end

-- For Views.Build("throne"): lines, detail title, detail text.
function King.Build(s)
	local lines
	if King.mode == "summon" then lines = SummonLines()
	elseif King.mode == "inspect" then lines = InspectLines()
	elseif King.mode == "agenda" then lines = AgendaLines()
	else lines = King.LetterLines() end
	return lines, L.TAB_THRONE, L.THRONE_YOU_ARE_KING
end

function King.Show(mode)
	King.mode = mode
	Changed()
end

-- For tests.
function King.State() return { summon = summon, inspect = inspect, agenda = agenda, inspecting = inspecting } end
function King.Reset()
	summon, inspect, agenda, inspecting = nil, nil, nil, nil
	lastSummonSeen, lastInspectSeen, lastSummonSent, lastInspectSent = -math.huge, -math.huge, -math.huge, -math.huge
	King.mode = "letter"
end
