local _, ns = ...
local F = {}
ns.FederationFugitives = F
local L = ns.L

-- An expulsion observation is not a federation decision. Accept only complete
-- current author-signed lists, scoped to this Forever region, ruleset and faction.
-- FUG1~region~group~faction~revision~issued~expires~names~signature
-- Names are exact game names with realms, separated by commas. A dash clears the list.
local DAY, MAX_NAMES, MAX_BLOB = 86400, 96, 8192
local cachedStore, cachedScope, cachedBlob, cached
local warned, warnedCount, auditQueued = {}, 0, false
local warnedInGroup = {}

local function Scope()
	local realm = ns.realm
	local region = type(realm) == "string" and realm:match("^CAMWOW(%u%u)%d+Realm%d+%a+$")
	local group = region and ns.ForeverFamily(realm)
	local faction = ns.faction
	if not group or group ~= ns.group or (faction ~= "Alliance" and faction ~= "Horde") then return nil end
	return region, group, faction
end

local function NameKey(name, region, group)
	if type(name) ~= "string" or ns.IsSecret(name) or #name > 96 then return nil end
	local person, realm = name:match("^([%a\128-\255]+ ?[%a\128-\255]*)%-([%w]+)$")
	if not person or realm:match("^CAMWOW(%u%u)%d+Realm%d+%a+$") ~= region then return nil end
	if ns.ForeverFamily(realm) ~= group then return nil end
	return ns.Fold(name)
end

local function Timestamp(n)
	n = type(n) == "string" and #n <= 10 and tonumber(n) or nil
	return n and n == math.floor(n) and n or nil
end

local function Read(blob, region, group, faction)
	if type(blob) ~= "string" or ns.IsSecret(blob) or #blob > MAX_BLOB then return nil end
	local body, signature = blob:match("^(FUG1~[^%c]+)~(%x+)$")
	if not body then return nil end
	local r, g, f, rev, issued, expires, names = body:match("^FUG1~(%u%u)~(%a+)~(%a+)~(%d+)~(%d+)~(%d+)~([^~]+)$")
	if r ~= region or g ~= group or f ~= faction then return nil end
	rev, issued, expires = Timestamp(rev), Timestamp(issued), Timestamp(expires)
	if not rev or rev < 1 or rev > 2147483647 or not issued or issued < 1577836800 or not expires
		or expires <= issued or expires - issued > 31 * DAY then return nil end
	local entries, count = {}, 0
	if names ~= "-" then
		for name in (names .. ","):gmatch("([^,]*),") do
			local key = NameKey(name, region, group)
			count = count + 1
			if not key or entries[key] or count > MAX_NAMES then return nil end
			entries[key] = true
		end
	end
	if not ns.Sign.Verify(body, signature) then return nil end
	return { revision = rev, issued = issued, expires = expires, entries = entries }
end

local function Clock()
	local now = ns.Data and ns.Data.ServerTime and ns.Data.ServerTime()
	return type(now) == "number" and not ns.IsSecret(now) and now >= 1577836800 and now or nil
end

local function Held(region, group, faction)
	local scope = region .. ":" .. group .. ":" .. faction
	local store = ns.db and ns.db.federationFugitives
	local blob = type(store) == "table" and store[scope] or nil
	if cachedStore ~= store or cachedScope ~= scope or cachedBlob ~= blob then
		cachedStore, cachedScope, cachedBlob = store, scope, blob
		cached = Read(blob, region, group, faction)
	end
	return cached, scope
end

function F.Import(blob)
	local region, group, faction = Scope()
	local now = Clock()
	if not region or not now or not ns.db then return false, "scope" end
	local held, scope = Held(region, group, faction)
	local list = Read(blob, region, group, faction)
	if not list or list.issued > now or list.expires <= now then return false, "invalid" end
	if held and list.revision <= held.revision then return false, "older" end
	local store = ns.db.federationFugitives
	if type(store) ~= "table" then store = {}; ns.db.federationFugitives = store end
	store[scope] = blob
	cachedStore, cachedScope, cachedBlob, cached = store, scope, blob, list
	ns.Fire("FEDERATION_FUGITIVES_CHANGED")
	return true
end

local function Live(now)
	local region, group, faction = Scope()
	if not region then return nil end
	local held = Held(region, group, faction)
	if held and held.issued <= now and now < held.expires then return held, region, group end
end

local function Matches(name, list, region, group)
	local key = NameKey(name, region, group)
	if not key then return false end
	if list.entries[key] then return true end
	for _, member in ipairs(ns.Alts.Linked(name)) do
		local linked = NameKey(member, region, group)
		if linked and list.entries[linked] then return true end
	end
	return false
end

-- Cross-guild use requires the destination's signed enrollment. A bare name is
-- not enough to identify a character for an enforcement decision.
function F.IsListed(name, guild)
	local now, program = Clock(), ns.FederationProgram
	if not now or not program or not program.IsEnrolled or not program.IsEnrolled(guild, now) then return false end
	local list, region, group = Live(now)
	return list ~= nil and Matches(name, list, region, group)
end

function F.Whisper(name)
	local now, program = Clock(), ns.FederationProgram
	if not now or not program or not program.LocalEnrollment or not program.LocalEnrollment(now) or ns.KingsScreen() then return false end
	local list, region, group = Live(now)
	if not list then return false end
	local key = NameKey(name, region, group)
	if not key or warned[key] or warnedCount >= 256 or not Matches(name, list, region, group) then return false end
	warned[key], warnedCount = true, warnedCount + 1
	ns.Print(L.FUGITIVES_WHISPER)
	return true
end

local function VisibleList()
	local now, program = Clock(), ns.FederationProgram
	if not now or not program or not program.LocalEnrollment or not program.LocalEnrollment(now)
		or ns.KingsScreen() or ns.ChatLocked() then return nil end
	return Live(now)
end

function F.Visible(name)
	local list, region, group = VisibleList()
	return list ~= nil and Matches(name, list, region, group)
end

local function CheckGroup()
	local list, region, group = VisibleList()
	if not list then return end
	local present, newMatch = {}, false
	for _, member in ipairs(ns.Groups.GroupMembers()) do
		local key = NameKey(member.name, region, group)
		if key and Matches(member.name, list, region, group) then
			present[key] = true
			newMatch = newMatch or not warnedInGroup[key]
		end
	end
	warnedInGroup = present
	if newMatch then ns.Print(L.FUGITIVES_PARTY) end
end

function F.Audit()
	local now, program = Clock(), ns.FederationProgram
	if not now or not program or not program.LocalEnrollment or not program.Role or ns.KingsScreen() or ns.ChatLocked()
		or ns.Dialog.missing then return false end
	local guild = program.LocalEnrollment(now)
	local role = guild and program.Role(ns.me, guild, now)
	if role ~= "official" and role ~= "caretaker" then return false end
	local list, region, group = Live(now)
	if not list or not next(list.entries) then return false end
	local roster = ns.Roster.Fresh()
	if not roster or roster.guild ~= guild then return false end
	local scope, day = table.concat({ region, group, ns.faction, guild, ns.me }, ":"), math.floor(now / DAY)
	local notices = ns.db.federationFugitiveAudits
	if type(notices) == "table" and notices[scope] == day then return false end
	local names = {}
	for name in pairs(roster.byName) do
		if Matches(name, list, region, group) then names[#names + 1] = name end
	end
	if #names == 0 then return false end
	table.sort(names)
	local shown = {}
	for i = 1, math.min(#names, 10) do shown[i] = ns.Codec.Plain(names[i]) end
	if #names > #shown then shown[#shown + 1] = L.FUGITIVES_REMAINDER:format(#names - #shown) end
	local frame = ns.Dialog.Show("OLYMPUS_FUGITIVES_AUDIT", L.FUGITIVES_AUDIT:format(table.concat(shown, ", ")))
	if not frame then return false end
	if type(notices) ~= "table" then notices = {}; ns.db.federationFugitiveAudits = notices end
	for key, old in pairs(notices) do
		if old ~= day then notices[key] = nil end
	end
	notices[scope] = day
	return true
end

local function AuditSoon()
	if auditQueued then return end
	auditQueued = true
	ns.After(3, "fugitive roster audit", function()
		auditQueued = false
		F.Audit()
	end)
end

function F.Paste(text)
	if type(text) ~= "string" or ns.IsSecret(text) or #text > MAX_BLOB + 32 then return false end
	local ok = F.Import(text:match("^%s*(.-)%s*$"))
	ns.Print(ok and L.FUGITIVES_IMPORTED or L.FUGITIVES_REFUSED)
	return ok
end

function F.Slash(rest)
	if rest == "paste" then
		if ns.Dialog.missing then ns.Print(L.RESTART_NEEDED); return false end
		return ns.Dialog.Show("OLYMPUS_FUGITIVES_PASTE")
	end
	ns.Print(L.FUGITIVES_HELP)
end

StaticPopupDialogs["OLYMPUS_FUGITIVES_AUDIT"] = {
	text = "%s", button1 = OKAY or "OK", timeout = 0, hideOnEscape = true,
}
StaticPopupDialogs["OLYMPUS_FUGITIVES_PASTE"] = {
	text = L.FUGITIVES_PASTE, button1 = OKAY or "OK", button2 = CANCEL or "Cancel",
	hasEditBox = true, editBoxWidth = 320, maxLetters = MAX_BLOB, timeout = 0, hideOnEscape = true,
	OnAccept = function(frame)
		local box = frame.editBox or frame.EditBox
		if box then F.Paste(box:GetText()) end
	end,
}

ns.RegisterEvent("CHAT_MSG_WHISPER", function(_, name) F.Whisper(name) end)
ns.RegisterEvent("CHAT_MSG_WHISPER_INFORM", function(_, name) F.Whisper(name) end)
ns.RegisterEvent("GUILD_ROSTER_UPDATE", AuditSoon)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", AuditSoon)
ns.On("FEDERATION_FUGITIVES_CHANGED", AuditSoon)
ns.On("GROUPS_ROSTER", CheckGroup)
