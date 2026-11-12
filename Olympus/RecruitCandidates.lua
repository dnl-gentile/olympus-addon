local _, ns = ...
local L, R = ns.L, ns.Recruit
local Q = {}
R.Candidates = Q

-- Local observations for this recruiting session. WHO can offer a short-lived copy draft;
-- opening a popup automatically or reviewing a whisper needs a current friendly unit.
local MAX, LIVE_TTL, WHO_TTL, PROMPT_GAP = 24, 90, 30, 15
local rows, byName, byGUID = {}, {}, {}
local WHISPER_MINUTES = { 0, 2, 5, 10, 15, 30 }
local guild, prompts, timer
local whisperChoice, whisperAt = 1, nil
local raceFaction = {
	Human = "Alliance", Dwarf = "Alliance", Gnome = "Alliance", NightElf = "Alliance",
	Draenei = "Alliance", Worgen = "Alliance",
	Orc = "Horde", Troll = "Horde", Tauren = "Horde", Undead = "Horde", Scourge = "Horde",
	BloodElf = "Horde", Goblin = "Horde",
}
local blockingDrafts = { "OLYMPUS_RECRUIT_OUTREACH", "OLYMPUS_RECRUIT_REPLY",
	"OLYMPUS_RECRUIT_INVITE_DRAFT", "OLYMPUS_RECRUIT_NETOFF", "OLYMPUS_RECRUIT_ANNOUNCEMENT" }

local function LocalGuild()
	if R.IsWhisperRecruiting() and R.CanInvite() then return GetGuildInfo("player") end
end

function Q.Enabled() return guild ~= nil and guild == LocalGuild() end

local function Drop(index)
	local row = table.remove(rows, index)
	byName[row.key] = nil
	if row.guid then byGUID[row.guid] = nil end
end

local function Prune(now)
	for i = #rows, 1, -1 do
		local row = rows[i]
		if (not row.seen or now - row.seen >= LIVE_TTL) and (not row.who or now - row.who >= WHO_TTL) then Drop(i) end
	end
end

local function Add(full, name, now)
	local key = ns.Fold(full)
	local row = byName[key]
	if row then return row end
	Prune(now)
	if #rows >= MAX then Drop(1) end
	row = { key = key, full = full, name = name }
	rows[#rows + 1], byName[key] = row, row
	return row
end

local function Change()
	ns.Fire("RECRUIT_CHANGED")
end

local function Quiet()
	return ns.ChatLocked() or ns.QuietPresence() or ns.Quiet() or (InCombatLockdown and InCombatLockdown())
end

local function Hidden(full)
	local M = ns.Moderation
	return M and M.Hidden and M.Hidden(full) ~= nil
end

local function Remember(unit)
	local name, guid, _, full = R.ReadCandidateUnit(unit)
	if not name or Hidden(full) then return end
	local now = GetTime()
	local prior = byGUID[guid]
	if prior and prior.full ~= full then return end
	local row = Add(full, name, now)
	if row.guid and row.guid ~= guid then return end
	byGUID[guid] = row
	local changed = not row.seen or row.guid ~= guid
	row.guid, row.seen = guid, now
	if unit == "target" then row.target = true else row.plate = unit end
	return changed
end

local function Observe(unit)
	if Q.Enabled() and not Quiet() and Remember(unit) then Change() end
end

local function WhoFaction(race)
	if type(race) ~= "string" then return end
	local faction = raceFaction[race:gsub("%s", "")]
	if faction then return faction end
	local localized = LOCALIZED_RACE_NAMES_MALE
	if localized then
		for key, side in pairs(raceFaction) do if localized[key] == race then return side end end
	end
end

function Q.ObserveWho(name, rawGuild, race)
	if type(name) ~= "string" or type(rawGuild) ~= "string" or not Q.Enabled() or Quiet() then return end
	local full = ns.FullName(ns.Normal(name))
	local key = ns.Fold(full)
	if rawGuild ~= "" then
		if byName[key] then
			for i, row in ipairs(rows) do if row.key == key then Drop(i); Change(); break end end
		end
		return
	end
	local realm = full:match("%-([^%-]+)$")
	local command = R.CandidateCommandName(full)
	if not realm or not ns.InGroup(realm) or WhoFaction(race) ~= ns.faction or not command
		or key == ns.Fold(ns.me) or Hidden(full) then return end
	local now = GetTime()
	local row = Add(full, command, now)
	local first = not row.who
	row.who = now
	if first then Change() end
end

local function UnitMatches(row, unit)
	if not unit then return false end
	local name, guid, _, full = R.ReadCandidateUnit(unit)
	return name == row.name and guid == row.guid and full == row.full
end

-- Returns a live unit token when the caller needs one, or true for a fresh WHO-only
-- command draft. None of these checks means the invitation has been sent.
function Q.Check(row, live)
	if type(row) ~= "table" or byName[row.key] ~= row or not Q.Enabled() or Quiet() or Hidden(row.full) then return end
	if row.seen and GetTime() - row.seen < LIVE_TTL then
		if UnitMatches(row, row.plate) then return row.plate end
		if row.target and UnitMatches(row, "target") then return "target" end
	end
	-- A stale sighting cannot fall back to WHO: the known token may now name a
	-- player who joined a guild. Re-observe them, or use a fresh WHO-only entry.
	if not live and not row.guid and row.who and GetTime() - row.who < WHO_TTL then return true end
end

function Q.Reset()
	if timer then timer.Cancel(); timer = nil end
	guild, prompts = nil, nil
	whisperChoice, whisperAt = 1, nil
	wipe(rows); wipe(byName); wipe(byGUID)
	if ns.Dialog and ns.Dialog.Find then
		for _, which in ipairs({ "OLYMPUS_RECRUIT_INVITE_DRAFT", "OLYMPUS_RECRUIT_OUTREACH" }) do
			local draft = ns.Dialog.Find(which)
			if draft and draft.data and draft.data.candidate then draft:Hide() end
		end
	end
end

local function Tick()
	if not Q.Enabled() then Q.Reset(); Change(); return end
	local before, now, quiet = #rows, GetTime(), Quiet()
	if not quiet then
		-- A stationary nameplate can stay visible longer than a reminder interval.
		-- Recheck only the exact unit tokens already kept in the bounded queue.
		for _, row in ipairs(rows) do
			if row.guid and (UnitMatches(row, row.plate) or (row.target and UnitMatches(row, "target"))) then
				row.seen = now
			end
		end
	end
	Prune(now)
	if #rows ~= before then Change() end
	local whisperDue = whisperAt and now >= whisperAt
	if (not prompts and not whisperDue) or quiet or not ns.Dialog or ns.Dialog.missing then return end
	for _, which in ipairs(blockingDrafts) do if ns.Dialog.Find(which) then return end end
	if whisperDue then
		for _, row in ipairs(rows) do
			if not row.whisperPrompted and R.PromptCandidateWhisper(row) then
				row.whisperPrompted = true
				whisperAt = now + WHISPER_MINUTES[whisperChoice] * 60
				return
			end
		end
	end
	if not prompts then return end
	for _, row in ipairs(rows) do
		if not row.prompted and Q.Check(row, true) and R.CopyCandidateInvite(row, true) then
			row.prompted = true
			return
		end
	end
end

local function ChangeWhisperReminder()
	whisperChoice = whisperChoice % #WHISPER_MINUTES + 1
	local minutes = WHISPER_MINUTES[whisperChoice]
	whisperAt = minutes > 0 and GetTime() + minutes * 60 or nil
	Change()
end

local function Toggle()
	if guild then Q.Reset(); Change(); return end
	guild = LocalGuild()
	if not guild then return end
	timer = ns.Every(PROMPT_GAP, "recruit candidates", Tick)
	if not Quiet() then
		Remember("target")
		for i = 1, ns.API and ns.API.NAMEPLATE_MAX or 200 do Remember("nameplate" .. i) end
	end
	Change()
end

function Q.Lines(lines, V)
	if not LocalGuild() then return end
	local on = Q.Enabled()
	lines[#lines + 1] = { id = "recruit-candidate-toggle", text = (on and V.Green or V.Grey)(on and L.RECRUIT_CANDIDATES_ON or L.RECRUIT_CANDIDATES_OFF),
		onClick = Toggle }
	if not on then return end
	lines[#lines + 1] = { id = "recruit-candidate-prompts", indent = 1,
		text = (prompts and V.Green or V.Grey)(prompts and L.RECRUIT_CANDIDATE_PROMPTS_ON or L.RECRUIT_CANDIDATE_PROMPTS_OFF),
		onClick = function() prompts = not prompts; Change() end }
	lines[#lines + 1] = { id = "recruit-candidate-whisper-reminder", indent = 1,
		text = whisperAt and V.Green(L.RECRUIT_CANDIDATE_WHISPER_EVERY:format(WHISPER_MINUTES[whisperChoice]))
			or V.Grey(L.RECRUIT_CANDIDATE_WHISPER_OFF), onClick = ChangeWhisperReminder }
	Prune(GetTime())
	if #rows == 0 then lines[#lines + 1] = { indent = 1, text = V.Grey(L.RECRUIT_CANDIDATE_EMPTY) } end
	for _, row in ipairs(rows) do
		local display = ns.DisplayName(row.full) or row.name
		local label = row.guid and L.RECRUIT_CANDIDATE_SEEN or L.RECRUIT_CANDIDATE_WHO
		lines[#lines + 1] = { indent = 1, text = V.Gold(label:format(display)),
			onClick = function() if R.CopyCandidateInvite(row) then row.prompted = true end end }
		if row.guid then
			lines[#lines + 1] = { indent = 2, text = V.Grey(L.RECRUIT_CANDIDATE_WHISPER),
				onClick = function() if R.PromptCandidateWhisper(row) then row.whisperPrompted = true end end }
		end
	end
end

ns.RegisterEvent("PLAYER_TARGET_CHANGED", function() Observe("target") end)
pcall(ns.RegisterEvent, "NAME_PLATE_UNIT_ADDED", function(unit)
	if type(unit) == "string" and not ns.IsSecret(unit) and unit:match("^nameplate%d+$") then Observe(unit) end
end)
