local _, ns = ...
local R, L = ns.Recruit, ns.L
local F = {}
R.Filters = F

local function Level(value)
	if ns.IsSecret(value) then return end
	local n = tonumber(value)
	if n and n >= 1 and n <= 255 and n == math.floor(n) then return n end
end

function F.Cap()
	local ok, value = pcall(function() return GetMaxPlayerLevel and GetMaxPlayerLevel() end)
	return ok and Level(value) or 60
end

function F.Class(value)
	if ns.IsSecret(value) or type(value) ~= "string" then return end
	for code, file in pairs(ns.CLASS_FILES) do
		if value == file or value == code
			or (LOCALIZED_CLASS_NAMES_MALE and value == LOCALIZED_CLASS_NAMES_MALE[file]) then return file end
	end
end

function F.Settings()
	local pref = R.FilterPreference()
	local f = pref and type(pref.filters) == "table" and pref.filters or {}
	return Level(f.min), Level(f.max), type(f.classes) == "table" and f.classes or nil
end

function F.Allows(item)
	local low, high, classes = F.Settings()
	local level, class = Level(item.level), F.Class(item.class)
	if (low or high) and not level then return false, L.RECRUIT_FILTER_UNKNOWN, "unknown" end
	if level and ((low and level < low) or (high and level > high)) then return false, L.RECRUIT_FILTER_LEVEL_OUT, "level" end
	if classes then
		if not class then return false, L.RECRUIT_FILTER_UNKNOWN, "unknown" end
		if classes[class] ~= true then return false, L.RECRUIT_FILTER_CLASS_OUT, "class" end
	end
	return true
end

-- Read only existing native observations; no inspect, network request or native UI touch.
function F.ReadUnit(unit)
	local okLevel, level = pcall(UnitLevel, unit)
	local okClass, _, class = pcall(UnitClass, unit)
	return okLevel and Level(level) or nil, okClass and F.Class(class) or nil
end

local function CloseExcluded()
	if not ns.Dialog or not ns.Dialog.Find then return end
	for _, id in ipairs({ "OLYMPUS_RECRUIT_INVITE_DRAFT", "OLYMPUS_RECRUIT_OUTREACH", "OLYMPUS_RECRUIT_NETOFF" }) do
		local draft = ns.Dialog.Find(id)
		local data = draft and draft.data
		local item = data and (data.candidate or data.req)
		if item and not F.Allows(item) then
			item.inviteAfterWhisper = nil
			draft:Hide()
		end
	end
end

local function Changed()
	CloseExcluded()
	ns.Fire("RECRUIT_CHANGED")
	R.PromptReplies()
end

local function Edit(expected)
	local pref = R.FilterPreference(true)
	if not pref or (expected and pref ~= expected) then return end
	if type(pref.filters) ~= "table" then pref.filters = {} end
	return pref.filters
end

function F.SetLevels(text, expected)
	if type(text) ~= "string" then return false end
	text = text:match("^%s*(.-)%s*$")
	local low, high
	if text ~= "" then
		low, high = text:match("^(%d+)%s*%-%s*(%d+)$")
		if not low and text:match("^%d+$") then low, high = text, text end
		low, high = Level(low), Level(high)
		if not low or not high or low > high or high > F.Cap() then return false end
	end
	local f = Edit(expected)
	if not f then return false end
	f.min, f.max = low, high
	Changed()
	return true
end

-- nil means every class, {} means none. Copy allowlists so old UI closures cannot mutate them.
function F.SetClasses(classes, expected)
	local clean
	if classes ~= nil then
		if type(classes) ~= "table" then return false end
		clean = {}
		for file, enabled in pairs(classes) do
			if enabled == true then
				local class = F.Class(file)
				if not class then return false end
				clean[class] = true
			end
		end
	end
	local f = Edit(expected)
	if not f then return false end
	f.classes = clean
	Changed()
	return true
end

function F.ToggleClass(file, expected)
	if not F.Class(file) then return false end
	local _, _, old = F.Settings()
	local classes = {}
	for _, class in pairs(ns.CLASS_FILES) do classes[class] = old == nil or old[class] == true end
	classes[file] = not classes[file]
	return F.SetClasses(classes, expected)
end

local function SameName(a, b)
	if ns.splitNames then a, b = ns.ShortName(a), ns.ShortName(b) end
	return ns.Fold(a) == ns.Fold(b)
end

function F.UpdateRequest(name, level, class)
	if type(name) ~= "string" or not R.IsWhisperRecruiting() or not R.CandidateCommandName(name) then return end
	level, class = Level(level), F.Class(class)
	local changed
	for _, req in ipairs(R.requests) do
		if R.CurrentRequest(req) and SameName(req.name, ns.FullName(name)) then
			-- New incomplete metadata never erases a previously known value.
			if level and req.level ~= level then req.level, changed = level, true end
			if class and req.class ~= class then req.class, changed = class, true end
		end
	end
	if changed then Changed() end
end

function F.HasRequests()
	if not R.IsWhisperRecruiting() then return false end
	for _, req in ipairs(R.requests) do if not req.panelDone and R.CurrentRequest(req) then return true end end
	return false
end

function F.CheckRequest(req)
	if not R.CurrentRequest(req) or ns.GamepadUI() or not ns.Who or not ns.Who.Search then return false end
	if ns.ChatLocked() or ns.QuietPresence() or ns.Quiet() or (InCombatLockdown and InCombatLockdown()) then return false end
	local name = R.CandidateCommandName(req.name)
	if not name then return false end
	if ns.Who.IsPending() then ns.Print(L.RECRUIT_CANDIDATE_SEARCH_WAIT); return false end
	local sent = ns.Who.Search(true, nil, nil, ('n-"%s"'):format(name)) == true
	if not sent then ns.Print(L.RECRUIT_CANDIDATE_SEARCH_WAIT) end
	return sent
end

local function Observe(unit)
	if not F.HasRequests() then return end
	local name, _, _, full = R.ReadCandidateUnit(unit)
	if name then
		local level, class = F.ReadUnit(unit)
		F.UpdateRequest(full, level, class)
	end
end
ns.RegisterEvent("PLAYER_TARGET_CHANGED", function() Observe("target") end)
pcall(ns.RegisterEvent, "UPDATE_MOUSEOVER_UNIT", function() Observe("mouseover") end)

StaticPopupDialogs["OLYMPUS_RECRUIT_FILTER_LEVELS"] = {
	text = L.RECRUIT_FILTER_LEVEL_PROMPT, button1 = L.RECRUIT_FILTER_SAVE, button2 = CANCEL or "Cancel",
	hasEditBox = true, editBoxWidth = 180, maxLetters = 12,
	OnShow = function(self, data)
		local low, high = F.Settings()
		self.editBox:SetText(low and ("%d-%d"):format(low, high or F.Cap()) or "")
		ns.Focus(self.editBox)
	end,
	OnAccept = function(self, data)
		if not F.SetLevels(self.editBox:GetText(), data) then ns.Print(L.RECRUIT_FILTER_INVALID:format(F.Cap())); return true end
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		if F.SetLevels(self:GetText(), parent.data) then parent:Hide()
		else ns.Print(L.RECRUIT_FILTER_INVALID:format(F.Cap())) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function F.Lines(lines, V)
	local pref = R.FilterPreference(true)
	if not pref then return end
	local low, high, classes = F.Settings()
	lines[#lines + 1] = { id = "recruit-filter-title", header = true, text = L.RECRUIT_FILTER_TITLE }
	lines[#lines + 1] = { indent = 1, text = V.Grey(L.RECRUIT_FILTER_HINT) }
	lines[#lines + 1] = { id = "recruit-filter-level", indent = 1,
		text = V.Gold(L.RECRUIT_FILTER_LEVELS:format(low and ("%d-%d"):format(low, high or F.Cap()) or L.RECRUIT_FILTER_ALL)),
		onClick = function()
			if R.FilterPreference() == pref then ns.Dialog.Show("OLYMPUS_RECRUIT_FILTER_LEVELS", nil, nil, pref) end
		end }
	lines[#lines + 1] = { id = "recruit-filter-all", indent = 1, text = V.Gold(L.RECRUIT_FILTER_ALL_CLASSES),
		onClick = function() F.SetClasses(nil, pref) end }
	lines[#lines + 1] = { id = "recruit-filter-none", indent = 1, text = V.Gold(L.RECRUIT_FILTER_NO_CLASSES),
		onClick = function() F.SetClasses({}, pref) end }
	local files = {}
	for _, file in pairs(ns.CLASS_FILES) do files[#files + 1] = file end
	table.sort(files)
	for _, file in ipairs(files) do
		local selected = classes == nil or classes[file] == true
		local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file] or file
		lines[#lines + 1] = { id = "recruit-filter-class-" .. file, indent = 1,
			text = (selected and V.Green or V.Grey)((selected and "[x] " or "[ ] ") .. name),
			onClick = function() F.ToggleClass(file, pref) end }
	end
end
