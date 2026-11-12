local _, ns = ...
local L, R = ns.L, ns.Recruit
local Q = {}
R.Candidates = Q

-- Local observations for this recruiting session. A fresh WHO result (from a /who the player
-- ran) or a current friendly unit can open the copy draft, by hand or as the timed popup;
-- reviewing a whisper needs a current friendly unit. The game itself refuses an invite to a
-- player who joined a guild since the /who.
local MAX, LIVE_TTL, WHO_TTL, PROMPT_GAP = 24, 90, 180, 15
local rows, byName, byGUID = {}, {}, {}
local guild, prompts, timer
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
	row = { key = key, full = full, name = name, scanned = true }
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

-- (1.5.8) A scanned player another member may still invite instead: current, and his command
-- not yet taken to chat here.
function Q.Passable(row)
	return type(row) == "table" and byName[row.key] == row and not row.invitePrepared and Q.Check(row) ~= nil
end

-- The next scanned player the Pass button (or the invite limit) gave to the automatic offers.
function Q.Overflow(skip)
	local H = R.Handoff
	for _, row in ipairs(rows) do
		if row.passWanted and not (H and H.State(row)) and Q.Passable(row) and not R.CandidatePromptOpen(row)
			and not (skip and skip(row)) then return row end
	end
end

-- Each scanned player, for the invite limit's release (Recruit.ReleaseLimited).
function Q.EachRow(fn)
	for _, row in ipairs(rows) do fn(row) end
end

function Q.Reset()
	if timer then timer.Cancel(); timer = nil end
	guild, prompts = nil, nil
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
	-- (1.5.8, the author's ask) Only the invite popup comes on its own; a whisper is its
	-- "Whisper them first" button's, or the list's.
	if not prompts or quiet or not ns.Dialog or ns.Dialog.missing then return end
	for _, which in ipairs(blockingDrafts) do if ns.Dialog.Find(which) then return end end
	-- (1.5.8) At the invite limit with the automatic offers on, new sightings go to other members.
	local H = R.Handoff
	local overflow = H and H.AutoOn() and R.AtInviteLimit()
	for _, row in ipairs(rows) do
		if not row.prompted and not row.passWanted and not (H and (H.State(row) or H.Taken(row))) and Q.Check(row) then
			if overflow then
				-- (Not marked prompted: once the limit clears it pops up here, unless a member took it.)
				H.Overflow(row)
			elseif R.CopyCandidateInvite(row, true) then
				row.prompted = true
				return
			end
		end
	end
end

local function Start(listOnly)
	guild = LocalGuild()
	if not guild then return false end
	-- The invite popups come with the scan; the player can keep it to the list instead.
	prompts = not listOnly
	timer = ns.Every(PROMPT_GAP, "recruit candidates", Tick)
	if not Quiet() then
		Remember("target")
		for i = 1, ns.API and ns.API.NAMEPLATE_MAX or 200 do Remember("nameplate" .. i) end
	end
	Change()
	return true
end

-- The player's switches are saved with this character's recruiting choice.
local function Save(field, value)
	local saved = R.Preference and R.Preference(true)
	if saved then saved[field] = value end
end

local function Toggle()
	if guild then Q.Reset(); Save("scan", nil); Change(); return end
	if Start() then Save("scan", true); Save("scanListOnly", nil) end
end

function Q.Restore(saved)
	if guild or type(saved) ~= "table" or saved.scan ~= true then return end
	Start(saved.scanListOnly == true)
end

function Q.Lines(lines, V)
	if not LocalGuild() then return end
	local on = Q.Enabled()
	lines[#lines + 1] = { id = "recruit-candidate-toggle", text = (on and V.Green or V.Grey)(on and L.RECRUIT_CANDIDATES_ON or L.RECRUIT_CANDIDATES_OFF),
		onClick = Toggle }
	if not on then return end
	lines[#lines + 1] = { id = "recruit-candidate-prompts", indent = 1,
		text = (prompts and V.Green or V.Grey)(prompts and L.RECRUIT_CANDIDATE_PROMPTS_ON or L.RECRUIT_CANDIDATE_PROMPTS_OFF),
		onClick = function() prompts = not prompts; Save("scanListOnly", not prompts or nil); Change() end }
	Prune(GetTime())
	if #rows == 0 then lines[#lines + 1] = { indent = 1, text = V.Grey(L.RECRUIT_CANDIDATE_EMPTY) } end
	for _, row in ipairs(rows) do
		local display = ns.DisplayName(row.full) or row.name
		local label = row.guid and L.RECRUIT_CANDIDATE_SEEN or L.RECRUIT_CANDIDATE_WHO
		local state = R.Handoff and R.Handoff.State(row)
		if state then
			local ref = row.handoff
			label = (state == "assigned" and L.RECRUIT_HANDOFF_DONE or L.RECRUIT_HANDOFF_PENDING)
				:format(ns.DisplayName(ref.peer) or ref.peer, ref.to)
			lines[#lines + 1] = { indent = 1, text = V.Grey(display .. " - " .. label) }
		elseif row.passWanted then
			lines[#lines + 1] = { indent = 1, text = V.Grey(L.RECRUIT_CANDIDATE_PASSING:format(display)),
				onClick = function() if R.CopyCandidateInvite(row) then row.prompted = true end end }
		else
			lines[#lines + 1] = { indent = 1, text = V.Gold(label:format(display)),
				onClick = function() if R.CopyCandidateInvite(row) then row.prompted = true end end }
		end
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

-- 1.5.8 (the author's ask): the Census offer's switch, the scan on (with its popups) or off as
-- asked, saved as the Church's own switch saves it. Returns whether it scans now.
function Q.SetEnabled(on)
	if on and not Q.Enabled() then
		if guild then Toggle() end -- (another guild's leftover goes off first)
		Toggle()
	elseif not on and guild then
		Toggle()
	end
	return Q.Enabled()
end
