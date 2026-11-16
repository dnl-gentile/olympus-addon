local _, ns = ...
local R, L = ns.Recruit, ns.L
local P = {}
R.Panel = P
local current, owner, advanced
local promptOwner, promptAt
P.PROMPT_GAP = 15

local function Changed() ns.Fire("RECRUIT_CHANGED") end

local function Name(item) return item.scanned and item.full or item.name end
local function Key(item)
	local name = ns.FullName(Name(item))
	return ns.Fold(ns.splitNames and ns.ShortName(name) or name)
end

local function CloseDrafts()
	if not ns.Dialog or not ns.Dialog.Find then return end
	for _, id in ipairs({ "OLYMPUS_RECRUIT_INVITE_DRAFT", "OLYMPUS_RECRUIT_REPLY",
		"OLYMPUS_RECRUIT_OUTREACH", "OLYMPUS_RECRUIT_ANNOUNCEMENT", "OLYMPUS_RECRUIT_NETOFF" }) do
		local draft = ns.Dialog.Find(id)
		if draft then
			-- Closing the queue's reviews must not schedule a return to the old invite.
			if draft.data and draft.data.candidate then draft.data.candidate.inviteAfterWhisper = nil end
			draft:Hide()
		end
	end
end

-- A deliberate Start adopts the unified queue. Existing popup preferences are preserved
-- for the advanced controls; no background migration turns scanning on for a player.
function P.Start()
	if not R.IsWhisperRecruiting() and not R.EnableWhisperRecruiting() then return false end
	if not R.CanInvite() then return false end
	local saved = R.Preference(true)
	if not saved then return false end
	saved.panelQueue, saved.panelPaused, saved.offerAgain = true, nil, nil
	if ns.NoteUIAction then ns.NoteUIAction("recruit-start") end
	CloseDrafts()
	if R.Candidates then R.Candidates.SetEnabled(true) end
	Changed()
	R.PromptReplies()
	return true
end

function P.Pause()
	local saved = R.Preference()
	if not saved or not saved.panelQueue then return false end
	saved.panelPaused = true
	if ns.NoteUIAction then ns.NoteUIAction("recruit-pause") end
	CloseDrafts()
	Changed()
	return true
end

function P.Toggle()
	local saved = R.Preference()
	if saved and saved.panelQueue and not R.IsPaused() then return P.Pause() end
	return P.Start()
end

local function Joined(item)
	return ns.Roster.Fresh() and ns.Roster.RankOf(Name(item)) ~= nil
end

-- JOINs first, oldest first. A scan and a JOIN for the same character are one choice.
-- Kept records are the existing bounded request/candidate queues, never a second database.
function P.Queue()
	local result, seen = {}, {}
	local own, now = GetGuildInfo("player"), ns.Now()
	for _, req in ipairs(R.requests) do
		if req.guild == own and now - req.t <= R.REQUEST_TTL then
			seen[Key(req)] = true
			if not req.panelDone then result[#result + 1] = req end
		end
	end
	if R.Candidates then
		R.Candidates.EachRow(function(row)
			if not row.panelDone and not seen[Key(row)] and R.Candidates.Check(row, nil, true) then
				seen[Key(row)] = true
				result[#result + 1] = row
			end
		end)
	end
	return result
end

local function Busy()
	if not R.CanInvite() then return L.RECRUIT_NO_INVITE_SHORT end
	if R.IsPaused() then return L.RECRUIT_PANEL_PAUSED end
	if InCombatLockdown and InCombatLockdown() then return L.RECRUIT_PANEL_COMBAT end
	if ns.ChatLocked() or ns.QuietPresence() or ns.Quiet() then return L.RECRUIT_PANEL_BUSY end
	if R.AtInviteLimit() then return L.RECRUIT_PANEL_LIMIT:format(R.InviteLimitWait()) end
end

function P.Status(item)
	if Joined(item) then return "joined", L.RECRUIT_WHISPER_JOINED end
	if R.Declined(Name(item)) then return "declined", L.RECRUIT_PANEL_DECLINED end
	local busy = Busy()
	if busy then return "waiting", busy end
	local valid = item.scanned and R.Candidates.Check(item) or (not item.scanned and R.CurrentRequest(item))
	if not valid then return "stale", L.RECRUIT_PANEL_STALE end
	if item.invitePrepared then return "prepared", L.RECRUIT_PANEL_PREPARED end
	return "ready", item.scanned and L.RECRUIT_PANEL_DISCOVERED
		or (R.IsReply(item) and L.RECRUIT_WHISPER_REVIEW:format(item.guild) or L.RECRUIT_PANEL_JOIN)
end

function P.Current()
	local saved = R.Preference()
	if owner ~= saved then owner, current = saved, nil end
	local queue = P.Queue()
	-- Keep a prepared/current request visible until Next. A new JOIN takes priority over
	-- an untouched scan, but never replaces a draft the player is already using.
	if current and current.panelDone then current = nil end
	if current and current.scanned and not current.invitePrepared and queue[1] and not queue[1].scanned
		and not queue[1].invitePrepared and not R.CandidatePromptOpen(current) then current = nil end
	current = current or queue[1]
	return current, #queue
end

-- Returns prepared, displayed: a reply review or warning is displayed but not prepared.
function P.Prepare(item, automatic)
	if not item or item ~= P.Current() then return false end
	local state = P.Status(item)
	if state ~= "ready" and state ~= "prepared" then return false end
	local draft = ns.Dialog and ns.Dialog.Find and ns.Dialog.Find("OLYMPUS_RECRUIT_INVITE_DRAFT")
	if draft then
		if not draft.data or (draft.data.req ~= item and draft.data.candidate ~= item) then return false end
		-- Prepare is a deliberate click; an automatic popup itself never takes the keyboard.
		if not automatic and ns.Focus(draft.editBox) then draft.editBox:HighlightText() end
		return true
	end
	-- Ordinary outreach replies need review, even if their text is a refusal. Only the
	-- review's explicit Prepare click can turn one into an invite draft.
	if R.IsReply(item) and not item.invitePrepared then return false, R.ReviewReply(item) end
	local shown, warning
	if item.scanned then shown = R.CopyCandidateInvite(item, automatic)
	else shown, warning = R.Accept(item, automatic) end
	if shown then item.invitePrepared = true; Changed() end
	return shown == true, shown == true or warning == true
end

-- Automatic copy drafts are local to this recruiter. The existing scan ticker and
-- incoming JOIN retries drive them; no transport message or native invite.
-- Never replace an open draft, steal typing focus, or repeatedly prompt the same row.
function P.Prompt()
	local saved = R.Preference()
	if not saved or not saved.panelQueue or not R.IsWhisperRecruiting() or Busy() then return false end
	if not ns.Dialog or ns.Dialog.missing or ns.KeyboardFocus() then return false end
	if promptOwner ~= saved then promptOwner, promptAt = saved, nil end
	if promptAt and GetTime() - promptAt < P.PROMPT_GAP then return false end
	for _, id in ipairs({ "OLYMPUS_RECRUIT_INVITE_DRAFT", "OLYMPUS_RECRUIT_REPLY",
		"OLYMPUS_RECRUIT_OUTREACH", "OLYMPUS_RECRUIT_ANNOUNCEMENT", "OLYMPUS_RECRUIT_NETOFF" }) do
		if ns.Dialog.Find(id) then return false end
	end
	for _, item in ipairs(P.Queue()) do
		if not item.panelPrompted and not item.invitePrepared and P.Status(item) == "ready" then
			owner, current = saved, item
			local prepared, displayed = P.Prepare(item, true)
			if prepared or displayed then
				item.panelPrompted = true
				promptAt = GetTime()
				return true
			end
			-- A failed preparation remains available for a later retry.
			return false
		end
	end
	return false
end

function P.Next(item)
	if not item or item ~= P.Current() then return false end
	CloseDrafts()
	if item.scanned then R.Candidates.Skip(item) else item.panelDone = true end
	current = nil
	Changed()
	return true
end

function P.Lines()
	if not ns.IsMember() then return {} end
	if advanced then
		local lines = { { id = "recruit-panel-back", text = L.RECRUIT_PANEL_BACK, onClick = function()
			advanced = nil; Changed()
		end } }
		for _, line in ipairs(R.WhisperLines()) do lines[#lines + 1] = line end
		return lines
	end
	local V, on, saved = ns.Views, R.IsWhisperRecruiting(), R.Preference()
	local running = on and saved and saved.panelQueue and not R.IsPaused()
	local lines = {
		{ id = "recruit-section-recruiting", header = true, text = L.RECRUIT_SECTION_RECRUITING },
		{ id = "recruit-panel-toggle", text = V.Gold(running and L.RECRUIT_PANEL_PAUSE or L.RECRUIT_PANEL_START), onClick = P.Toggle },
	}
	local function Line(id, text, action)
		lines[#lines + 1] = { id = id, indent = 1, text = action and V.Gold(text) or V.Grey(text), onClick = action }
	end
	if not R.CanInvite() then
		Line("recruit-no-invite", L.RECRUIT_NO_INVITE_SHORT)
		return lines
	end
	local busy = Busy()
	local status = busy or (running and L.RECRUIT_PANEL_SCANNING or (on and L.RECRUIT_PANEL_LEGACY or L.RECRUIT_PANEL_IDLE))
	if not busy and running and ns.Who and ns.Who.IsPending() then status = L.RECRUIT_PANEL_SEARCHING end
	Line("recruit-panel-status", status)
	Line("recruit-panel-hint", ns.GamepadUI() and L.RECRUIT_PANEL_GAMEPAD or L.RECRUIT_PANEL_HINT)
	if on then
		local item, count = P.Current()
		Line("recruit-panel-count", L.RECRUIT_PANEL_COUNT:format(count))
		if item then
			local state, detail = P.Status(item)
			local reply = R.IsReply(item)
			Line("recruit-panel-current", (ns.DisplayName(Name(item)) or Name(item)) .. " — " .. (item.scanned and L.RECRUIT_PANEL_SCAN
				or (reply and L.RECRUIT_WHISPER_REVIEW:format(item.guild) or "JOIN")))
			Line("recruit-panel-detail", detail)
			if state == "ready" or state == "prepared" then
				Line("recruit-panel-prepare", reply and not item.invitePrepared and L.RECRUIT_WHISPER_REVIEW:format(item.guild)
					or L.RECRUIT_WHISPER_PREPARE_BUTTON, function() P.Prepare(item) end)
			end
			Line("recruit-panel-next", (item.invitePrepared or state == "joined") and L.RECRUIT_PANEL_NEXT or L.RECRUIT_PANEL_SKIP,
				function() P.Next(item) end)
		else Line("recruit-panel-empty", L.RECRUIT_PANEL_EMPTY) end
		if running and R.Candidates and R.Candidates.CanSearch() and not Busy() then
			Line("recruit-candidate-search", L.RECRUIT_CANDIDATE_SEARCH_MORE, function() R.Candidates.SearchMore(true) end)
		end
	end
	R.AnnouncementLines(lines, V, running)
	Line("recruit-panel-advanced", L.RECRUIT_PANEL_ADVANCED, function()
		-- Explicitly returning to the older controls restores their saved popup choices.
		local pref = R.Preference()
		if pref then pref.panelQueue, pref.panelPaused = nil, nil end
		advanced = true; Changed()
	end)
	return lines
end
