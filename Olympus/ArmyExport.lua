local ADDON, ns = ...

-- An attended, aggregate-only export of this character's own guild roster.  The browser receiver
-- for it is not live yet, so the one release switch below stays false: all protocol and roster
-- code is testable, but /oly army cannot lead a player to a dead receiver.  Turning it on is a
-- separate release decision after the receiver and real-client acceptance tests are complete.
local ACTIVATION_ENABLED = false

local Army = {}
ns.ArmyExport = Army

Army.PROTOCOL = "OLCS2"
Army.FORMAT = "olympus-stat-observation-v2"
Army.ADDON_VERSION = "0.2.0"
Army.MAX_PAYLOAD = 1023
Army.FRAME_CHUNK_BYTES = 75
Army.MAX_FRAMES = 14
Army.MAX_FRAME_BYTES = 191
Army.MAX_REPORTED_CHARACTERS = 1000
Army.SCAN_TIMEOUT = 15
Army.FRAME_SECONDS = 1.25

local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
local CLASS_INDEX = {}
for i, name in ipairs(CLASSES) do CLASS_INDEX[name:upper()] = i end

local OFFICIAL = { olympus = "Olympus" }
for _, roman in ipairs({ "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x" }) do
	OFFICIAL["olympus " .. roman] = "Olympus " .. roman:upper()
end

local function Public(value, kind)
	if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
	if kind and type(value) ~= kind then return nil end
	return value
end

local function Integer(value, low, high)
	value = Public(value, "number")
	if not value or value ~= math.floor(value) or value < low or value > high then return nil end
	return value
end

local function JsonString(value)
	value = tostring(value or "")
	return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
		local b = c:byte()
		if c == "\\" then return "\\\\" end
		if c == '"' then return '\\"' end
		if c == "\b" then return "\\b" end
		if c == "\f" then return "\\f" end
		if c == "\n" then return "\\n" end
		if c == "\r" then return "\\r" end
		if c == "\t" then return "\\t" end
		return ("\\u%04x"):format(b)
	end) .. '"'
end

local function JsonValue(value)
	if value == nil then return "null" end
	if type(value) == "number" then return tostring(value) end
	return JsonString(value)
end

local function JsonArray(values)
	if type(values) ~= "table" then return "null" end
	local out = {}
	for i = 1, #values do out[i] = tostring(values[i]) end
	return "[" .. table.concat(out, ",") .. "]"
end

local function FoldGuild(name)
	if type(name) ~= "string" then return nil end
	name = name:match("^%s*(.-)%s*$")
	return name ~= "" and name:lower() or nil
end

function Army.OfficialGuild(name)
	return OFFICIAL[FoldGuild(name) or ""] ~= nil
end

function Army.CanonicalGuild(name)
	return OFFICIAL[FoldGuild(name) or ""]
end

local function RealmGroup(value)
	value = Public(value, "string")
	if not value or #value < 1 or #value > 96 or value:find("[%z\1-\31\127|]")
		or value:match("^%s") or value:match("%s$") then return nil end
	return value
end

function Army.ValidateNonce(nonce)
	if type(nonce) ~= "string" then return nil end
	nonce = nonce:match("^%s*(.-)%s*$")
	if #nonce ~= 32 or nonce:find("[^0-9a-fA-F]") then return nil end
	return nonce:lower()
end

function Army.Active()
	return ACTIVATION_ENABLED
end

-- The receiver accepts one exact product identity.  Never guess one from a friendly name or a
-- census report: Core owns the realm-group identity and the native client owns guild/faction.
function Army.Scope()
	local inGuild = type(IsInGuild) == "function" and IsInGuild()
	local guild = inGuild and type(GetGuildInfo) == "function" and Public(GetGuildInfo("player"), "string") or nil
	local faction = ns.faction or (type(UnitFactionGroup) == "function" and Public(UnitFactionGroup("player"), "string"))
	local group = RealmGroup(ns.group)
	guild = Army.CanonicalGuild(guild)
	if not guild then return nil, "official-guild" end
	if faction ~= "Alliance" then return nil, "alliance" end
	if not group then return nil, "realm-group" end
	return { guild = guild, faction = faction, realmGroup = group }
end

local function MaskTotal(n)
	if n >= 1 and n <= 4 then return "few" end
	return n
end

local function MaskOnline(total, online)
	if total >= 1 and total <= 4 then return nil end
	if online >= 1 and online <= 4 then return "few" end
	local offline = total - online
	if offline >= 1 and offline <= 4 then return nil end
	return online
end

local function SafeDistribution(values, total)
	local sum = 0
	for i = 1, #values do
		local n = values[i]
		if type(n) ~= "number" or n < 0 or n ~= math.floor(n) or (n >= 1 and n <= 4) then return nil end
		sum = sum + n
	end
	return sum == total and values or nil
end

-- Rows are transient native roster observations.  Names and GUIDs are deliberately ignored here;
-- only the marginal counts below can reach the payload.  One unsupported level/class/rank withholds
-- that complete distribution instead of rejecting the otherwise useful total.
function Army.Aggregate(rows)
	if type(rows) ~= "table" then return nil, "rows" end
	if #rows < 1 or #rows > Army.MAX_REPORTED_CHARACTERS then return nil, "roster-count" end
	local classes, levels, ranks = {}, {}, {}
	for i = 1, #CLASSES do classes[i] = 0 end
	for i = 1, 7 do levels[i] = 0 end
	for i = 1, 10 do ranks[i] = 0 end
	local total, online = 0, 0
	local classesValid, levelsValid, ranksValid = true, true, true
	for _, row in ipairs(rows) do
		if type(row) ~= "table" then return nil, "row" end
		total = total + 1
		if row.online == true then online = online + 1 end
		local ci = type(row.classFile) == "string" and CLASS_INDEX[row.classFile:upper()] or nil
		if ci then classes[ci] = classes[ci] + 1 else classesValid = false end
		local level = Integer(row.level, 1, 255)
		local li = level and (level == 60 and 7 or (level <= 59 and math.floor(level / 10) + 1 or nil))
		if li then levels[li] = levels[li] + 1 else levelsValid = false end
		local rank = Integer(row.rankIndex, 0, 9)
		if rank then ranks[rank + 1] = ranks[rank + 1] + 1 else ranksValid = false end
	end
	return {
		reportedCharacters = MaskTotal(total),
		online = MaskOnline(total, online),
		classes = classesValid and SafeDistribution(classes, total) or nil,
		levels = levelsValid and SafeDistribution(levels, total) or nil,
		ranks = ranksValid and SafeDistribution(ranks, total) or nil,
	}, nil
end

-- Canonical JSON for the .198 OLCS2 receiver: both object key orders and every literal are part of
-- the protocol.  receivedAt is the same attended native observation as the root's observedAt; a
-- later browser receipt time belongs to the receiver, never to invented addon state.
function Army.Payload(meta, rows)
	if type(meta) ~= "table" or meta.faction ~= "Alliance" then return nil, "scope" end
	local guild, realmGroup = Army.CanonicalGuild(meta.guild), RealmGroup(meta.realmGroup)
	if not guild or not realmGroup then return nil, "scope" end
	local observedAt = Integer(meta.observedAt, 1, 4102444800)
	if not observedAt then return nil, "time" end
	local a, why = Army.Aggregate(rows)
	if not a then return nil, why end
	local guild = table.concat({
		'{"name":', JsonString(guild),
		',"receivedAt":', tostring(observedAt),
		',"reportedCharacters":', JsonValue(a.reportedCharacters),
		',"online":', JsonValue(a.online),
		',"classes":', JsonArray(a.classes),
		',"levels":', JsonArray(a.levels),
		',"ranks":', JsonArray(a.ranks), "}"
	})
	local payload = table.concat({
		'{"format":', JsonString(Army.FORMAT),
		',"scope":"own-guild"',
		',"source":"volunteer-client"',
		',"sourceVerified":false',
		',"membershipProof":false',
		',"addonVersion":', JsonString(Army.ADDON_VERSION),
		',"realmGroup":', JsonString(realmGroup),
		',"faction":"Alliance"',
		',"observedAt":', tostring(observedAt),
		',"guilds":[', guild, "]}"
	})
	if #payload > Army.MAX_PAYLOAD then return nil, "payload-too-large" end
	return payload, a
end

function Army.Frames(payload, nonce)
	nonce = Army.ValidateNonce(nonce)
	if not nonce then return nil, "nonce" end
	if type(payload) ~= "string" or #payload < 1 or #payload > Army.MAX_PAYLOAD then return nil, "payload" end
	local Ed, Sign = ns.Ed25519, ns.Sign
	if type(Ed) ~= "table" or type(Ed.ToB64) ~= "function" or type(Sign) ~= "table" or type(Sign.SHA256) ~= "function" then
		return nil, "crypto"
	end
	local digest = Ed.ToB64(Sign.SHA256(payload))
	if #digest ~= 43 then return nil, "digest" end
	local total = math.ceil(#payload / Army.FRAME_CHUNK_BYTES)
	if total > Army.MAX_FRAMES then return nil, "too-many-frames" end
	local out = {}
	for part = 1, total do
		-- Each part encodes its own 75-byte raw slice.  Seventy-five is divisible by three, so
		-- concatenating the unpadded base64url chunks also recovers the whole encoding exactly.
		local at = (part - 1) * Army.FRAME_CHUNK_BYTES + 1
		local chunk = Ed.ToB64(payload:sub(at, at + Army.FRAME_CHUNK_BYTES - 1))
		if #chunk < 1 or #chunk > 100 then return nil, "frame-chunk" end
		local frame = ("%s|%s|%s|%03d|%03d|%s"):format(Army.PROTOCOL, nonce, digest, part, total, chunk)
		if #frame > Army.MAX_FRAME_BYTES then return nil, "frame-too-large" end
		out[part] = frame
	end
	return out, digest
end

function Army.Matrix(frame, pause)
	if type(frame) ~= "string" or #frame > Army.MAX_FRAME_BYTES or not frame:find("^OLCS2|", 1) then return nil, "frame" end
	local encoder = ns.QREncode
	if type(encoder) ~= "table" or type(encoder.qrcode) ~= "function" then return nil, "encoder" end
	local ok, matrix = encoder.qrcode(frame, 1, nil, pause) -- level L; a maximum frame fits QR version 8
	if not ok or type(matrix) ~= "table" or #matrix > 49 then return nil, "qr" end
	return matrix
end

local function Monotonic()
	if type(GetTimePreciseSec) == "function" then return tonumber(GetTimePreciseSec()) or 0 end
	if type(GetTime) == "function" then return tonumber(GetTime()) or 0 end
	return 0
end

local function RequestRoster()
	local fn = C_GuildInfo and type(C_GuildInfo.GuildRoster) == "function" and C_GuildInfo.GuildRoster
		or type(GuildRoster) == "function" and GuildRoster
	if not fn then return false end
	return pcall(fn)
end

local function OfflineShown()
	if type(GetGuildRosterShowOffline) ~= "function" then return nil end
	local ok, shown = pcall(GetGuildRosterShowOffline)
	if not ok then return nil end
	return Public(shown, "boolean")
end

-- Read only the currently displayed native roster after the caller requested offline rows.  The
-- player's exact native GUID must occur once; a same-named row is not membership proof.
function Army.ReadRoster(expected)
	if type(expected) ~= "table" or type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then
		return nil, "api"
	end
	if OfflineShown() ~= true then
		return nil, "show-offline"
	end
	local scope, why = Army.Scope()
	if not scope then return nil, why end
	if scope.guild ~= expected.guild or scope.faction ~= expected.faction or scope.realmGroup ~= expected.realmGroup then return nil, "scope-changed" end
	local playerGUID = type(UnitGUID) == "function" and Public(UnitGUID("player"), "string") or nil
	if not playerGUID or playerGUID ~= expected.playerGUID then return nil, "player-changed" end
	local total, reportedOnline = GetNumGuildMembers()
	total = Integer(total, 1, Army.MAX_REPORTED_CHARACTERS)
	reportedOnline = total and Integer(reportedOnline, 0, total) or nil
	if not total then return nil, "roster-count" end
	if not reportedOnline then return nil, "native-online" end
	local rows, own, onlineCount = {}, 0, 0
	local seenGUID, seenName = {}, {}
	for i = 1, total do
		local name, _, rankIndex, level, _, _, _, _, online, _, classFile, _, _, _, _, _, guid = GetGuildRosterInfo(i)
		name, guid, online = Public(name, "string"), Public(guid, "string"), Public(online, "boolean")
		if not name or name == "" or not guid or guid == "" or online == nil then return nil, "roster-incomplete" end
		local foldedName = name:lower()
		if seenGUID[guid] or seenName[foldedName] then
			return nil, guid == playerGUID and "own-guid-duplicate" or "roster-duplicate"
		end
		seenGUID[guid], seenName[foldedName] = true, true
		if online then onlineCount = onlineCount + 1 end
		if guid == playerGUID then
			if not online then return nil, "own-guid-offline" end
			own = own + 1
		end
		rows[i] = {
			level = Integer(level, 1, 255), rankIndex = Integer(rankIndex, 0, 255),
			classFile = Public(classFile, "string"), online = online,
		}
	end
	if #rows ~= total or own ~= 1 then return nil, own == 0 and "own-guid-missing" or "own-guid-duplicate" end
	local endTotal, endOnline = GetNumGuildMembers()
	endTotal = Integer(endTotal, 1, Army.MAX_REPORTED_CHARACTERS)
	endOnline = endTotal and Integer(endOnline, 0, endTotal) or nil
	if not endTotal then return nil, "roster-count" end
	if not endOnline then return nil, "native-online" end
	if endTotal ~= total then return nil, "roster-changed" end
	if endOnline ~= reportedOnline then return nil, "online-changed" end
	if onlineCount ~= reportedOnline then return nil, "online-mismatch" end
	if OfflineShown() ~= true then return nil, "show-offline" end
	local endScope, endWhy = Army.Scope()
	if not endScope then return nil, endWhy end
	if endScope.guild ~= expected.guild or endScope.faction ~= expected.faction
		or endScope.realmGroup ~= expected.realmGroup then return nil, "scope-changed" end
	local endGUID = type(UnitGUID) == "function" and Public(UnitGUID("player"), "string") or nil
	if not endGUID or endGUID ~= playerGUID then return nil, "player-changed" end
	return rows
end

local pending, serial, frame = nil, 0, nil

local function RestoreOffline(p)
	if p and p.changedOffline and type(SetGuildRosterShowOffline) == "function" then
		pcall(SetGuildRosterShowOffline, p.offlineBefore)
		RequestRoster()
	end
end

local function Cancel(reason)
	local p = pending
	if not p then return false end
	pending = nil
	RestoreOffline(p)
	if reason then ns.Print("Army QR export stopped: " .. reason .. ".") end
	return true
end

function Army.Cancel(reason) return Cancel(reason) end

local function Render(f, matrix, part, total)
	local rects = ns.Link.Rects(matrix)
	local modules, quiet = #matrix, ns.Link.QUIET or 4
	local px, screenH = ns.Link.PixelSize(f)
	local allModules = modules + quiet * 2
	local modulePixels = ns.Link.ModulePixels(allModules, screenH, math.ceil(118 / px))
	local module = modulePixels * px
	local size = allModules * module
	f.canvas:SetSize(size, size)
	f:SetSize(math.max(420, size + 48), size + 118)
	for i, rect in ipairs(rects) do
		local t = f.modules[i]
		if not t then
			t = f.canvas:CreateTexture(nil, "ARTWORK")
			t:SetColorTexture(0, 0, 0, 1)
			f.modules[i] = t
		end
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", f.canvas, "TOPLEFT", (quiet + rect.x) * module, -(quiet + rect.y) * module)
		t:SetSize(rect.w * module, rect.h * module)
		t:Show()
	end
	for i = #rects + 1, #f.modules do f.modules[i]:Hide() end
	f.part:SetText(("Frame %d of %d"):format(part, total))
end

local function StopRotation(f)
	f.rotation = (f.rotation or 0) + 1
	if f.timer and f.timer.Cancel then f.timer:Cancel() end
	f.timer, f.making = nil, nil
end

local function ClearWindow(f)
	StopRotation(f)
	f.frames = nil
	if f.part then f.part:SetText("") end
	for _, texture in ipairs(f.modules or {}) do texture:Hide() end
end

local function CloseWindow()
	if not frame then return end
	if frame:IsShown() then frame:Hide() else ClearWindow(frame) end
end

function Army.Close() CloseWindow() end

local function MakeWindow()
	local f = ns.Window("OlympusArmyExportFrame", nil, { title = "Army snapshot", inset = false }) -- gp:lookups
	f:SetFrameStrata("DIALOG")
	f:SetPoint("CENTER")
	f:Hide()
	f.canvas = CreateFrame("Frame", nil, f) -- gp:lookups
	f.canvas:SetPoint("TOP", f, "TOP", 0, -44)
	f.canvas.bg = f.canvas:CreateTexture(nil, "BACKGROUND")
	f.canvas.bg:SetAllPoints()
	f.canvas.bg:SetColorTexture(1, 1, 1, 1)
	f.modules = {}
	f.part = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	f.part:SetPoint("TOP", f.canvas, "BOTTOM", 0, -10)
	f.hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	f.hint:SetPoint("TOP", f.part, "BOTTOM", 0, -6)
	f.hint:SetText("Keep the scanner open until every frame is received.")
	f:SetScript("OnHide", ClearWindow)
	return f
end

local function Later(seconds, fn)
	if C_Timer and type(C_Timer.NewTimer) == "function" then return C_Timer.NewTimer(seconds, fn) end
	if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(seconds, fn) end
	return nil
end

local function ShowPart(f, token, part)
	if not f:IsShown() or f.rotation ~= token or f.making then return end
	local text = f.frames[part]
	f.making = part
	local Ed = ns.Ed25519
	local queued = Ed.Run(function() return Army.Matrix(text, Ed.Pause) end, function(ok, matrix)
		if f.rotation ~= token then return end
		f.making = nil
		if not ok or type(matrix) ~= "table" then
			StopRotation(f)
			return ns.Print("Army QR export could not draw a frame.")
		end
		Render(f, matrix, part, #f.frames)
		f.timer = Later(Army.FRAME_SECONDS, function()
			if f:IsShown() and f.rotation == token then ShowPart(f, token, part % #f.frames + 1) end
		end)
	end)
	if not queued then
		f.making = nil
		ns.Print("Army QR export is busy. Try again in a moment.")
	end
end

function Army.ShowFrames(frames)
	if type(frames) ~= "table" or #frames == 0 then return false end
	frame = frame or MakeWindow()
	StopRotation(frame)
	frame.frames = frames
	frame.rotation = frame.rotation + 1
	local token = frame.rotation
	frame:Show()
	ShowPart(frame, token, 1)
	return true
end

function Army.Window() return frame end -- tests and acceptance diagnostics

local function Finish(id)
	local p = pending
	if not p or p.id ~= id or not p.updated then return false end
	if type(InCombatLockdown) == "function" and InCombatLockdown() then return Cancel("combat started") end
	local elapsed = Monotonic() - p.started
	if elapsed < 0 or elapsed > Army.SCAN_TIMEOUT then return Cancel("the roster timed out") end
	local serverNow = type(GetServerTime) == "function" and Integer(GetServerTime(), 1, 4102444800) or nil
	if not serverNow or serverNow < p.serverStarted or serverNow - p.serverStarted > Army.SCAN_TIMEOUT + 2 then
		return Cancel("the observation time changed")
	end
	local rows, why = Army.ReadRoster(p.scope)
	if not rows then
		if why == "roster-incomplete" or why == "roster-count" or why == "native-online"
			or why == "roster-duplicate" or why == "own-guid-missing" or why == "own-guid-duplicate"
			or why == "own-guid-offline" or why == "roster-changed" or why == "online-changed"
			or why == "online-mismatch" or why == "show-offline" then
			return false, why -- another roster update may finish the native snapshot
		end
		return Cancel("the roster was refused"), why
	end
	local payload, aggregate = Army.Payload({ guild = p.scope.guild, faction = p.scope.faction,
		realmGroup = p.scope.realmGroup, observedAt = serverNow }, rows)
	rows = nil
	if not payload then return Cancel("the aggregate was refused") end
	local frames = Army.Frames(payload, p.nonce)
	if not frames then return Cancel("the frames were refused") end
	pending = nil
	RestoreOffline(p)
	Army.ShowFrames(frames)
	return true, aggregate
end

function Army.Start(nonce)
	if not ACTIVATION_ENABLED then return false, "inactive" end
	-- A new attended attempt supersedes any old display even when its new input is refused.
	CloseWindow()
	if pending then return false, "pending" end
	nonce = Army.ValidateNonce(nonce)
	if not nonce then return false, "nonce" end
	if type(InCombatLockdown) == "function" and InCombatLockdown() then return false, "combat" end
	local scope, why = Army.Scope()
	if not scope then return false, why end
	local guid = type(UnitGUID) == "function" and Public(UnitGUID("player"), "string") or nil
	local serverNow = type(GetServerTime) == "function" and Integer(GetServerTime(), 1, 4102444800) or nil
	if not guid or not serverNow then return false, "identity" end
	if type(GetGuildRosterShowOffline) ~= "function" then return false, "show-offline-api" end
	serial = serial + 1
	local shown = OfflineShown()
	if shown ~= true and shown ~= false then return false, "show-offline-api" end
	if shown == false and type(SetGuildRosterShowOffline) ~= "function" then return false, "show-offline-api" end
	-- Bind the exact native identity into the private expected-scope snapshot used at completion.
	-- The public scope helper deliberately contains no character identity.
	local expected = { guild = scope.guild, faction = scope.faction, realmGroup = scope.realmGroup, playerGUID = guid }
	pending = { id = serial, nonce = nonce, scope = expected, started = Monotonic(),
		serverStarted = serverNow, offlineBefore = shown, changedOffline = shown == false }
	if shown == false and type(SetGuildRosterShowOffline) == "function" then
		local ok = pcall(SetGuildRosterShowOffline, true)
		if not ok then Cancel() return false, "show-offline-api" end
	end
	if not RequestRoster() then Cancel() return false, "api" end
	local id = serial
	ns.After(Army.SCAN_TIMEOUT, "army export timeout", function()
		if pending and pending.id == id then Cancel("the roster timed out") end
	end)
	return true
end

function Army.Slash(rest)
	if not ACTIVATION_ENABLED then
		return ns.Print("Army QR export is not available in this build.")
	end
	local ok, why = Army.Start(rest)
	if ok then return end
	local text = why == "nonce" and "Paste the 32-character nonce from the attended browser: /oly army <nonce>."
		or why == "combat" and "Leave combat before making an Army snapshot."
		or why == "pending" and "The Army snapshot is already reading the roster."
		or "Army QR export is available only to an Alliance member of an official Olympus guild."
	ns.Print(text)
end

ns.RegisterEvent("GUILD_ROSTER_UPDATE", function()
	if not pending then return end
	pending.updated = true
	Finish(pending.id)
end)
local function StopForTransition(reason)
	CloseWindow()
	Cancel(reason)
end
ns.RegisterEvent("PLAYER_LOGOUT", function() StopForTransition("the world changed") end)
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function() StopForTransition("the world changed") end)
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function() StopForTransition("combat started") end)
ns.RegisterEvent("PLAYER_GUILD_UPDATE", function(unit)
	if unit and unit ~= "player" then return end
	StopForTransition("the guild changed")
end)
-- Forever's extracted API does not declare this event, while Era/TBC clients may provide it.
-- Register it only where the client accepts it; PLAYER_ENTERING_WORLD is the portable fallback.
pcall(ns.RegisterEvent, "PLAYER_LEAVING_WORLD", function() StopForTransition("the world changed") end)
