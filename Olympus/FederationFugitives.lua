local _, ns = ...
local F = {}
ns.FederationFugitives = F
local L = ns.L

-- An expulsion observation is not a federation decision. Accept only complete
-- current author-signed lists, scoped to this Forever region, ruleset and faction.
-- FUG1~region~group~faction~revision~issued~expires~names~signature
-- Names are exact game names with realms, separated by commas. A dash clears the list.
local DAY, MAX_NAMES, MAX_BLOB = 86400, 96, 7400
local cachedStore, cachedScope, cachedBlob, cached
local warned, warnedCount, auditQueued = {}, 0, false
local warnedInGroup = {}
local pending, askedAt, answeredAt, replyUntil = nil, -math.huge, -math.huge, {}
local nextPeer, serial = 1, 0
local ASK_FOR, ASK_EVERY, REPLY_EVERY = 45, 120, 12
local reviewRequest, removalReview

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

local function Sharing(now)
	local program = ns.FederationProgram
	if now and ns.IsMember() and not ns.QuietPresence() and not ns.ChatLocked() and program and program.LocalEnrollment then
		return program.LocalEnrollment(now)
	end
end

local function Peer(name, own, guild, now)
	local region, group = Scope()
	if not region or not NameKey(name, region, group) or ns.Fold(name) == ns.Fold(ns.me) then return false end
	if ns.Fold(guild) == ns.Fold(own) then return ns.Roster.RankOf(name) ~= nil end
	local program = ns.FederationProgram
	local role = program.Role and program.Role(name, guild, now)
	return role == "official" or role == "caretaker"
end

local function Candidates(own, now)
	local out, seen = {}, {}
	local function Add(name, guild)
		if not Peer(name, own, guild, now) then return end
		local key = ns.Fold(name)
		if seen[key] then return end
		seen[key] = true
		out[#out + 1] = { name = name, guild = guild }
	end
	local program = ns.FederationProgram
	local caretakers = program.Caretakers and program.Caretakers() or {}
	Add(caretakers[own], own)
	-- Only a named guild representative may cross a guild boundary. A local native
	-- guildmate can still receive a decision without having a signed staff role.
	if program.Role and program.Role(ns.me, own, now) then
		local guilds = {}
		for guild in pairs(caretakers) do guilds[#guilds + 1] = guild end
		table.sort(guilds)
		for _, guild in ipairs(guilds) do Add(caretakers[guild], guild) end
	end
	for _, name in ipairs(ns.Comm.Peers()) do Add(name, own) end
	return out
end

function F.Sync()
	local now = Clock()
	local own = Sharing(now)
	if not own or now - askedAt < ASK_FOR then return false end
	local peers = Candidates(own, now)
	if #peers == 0 or #own > 72 or own:find("[~%c]") then return false end
	if nextPeer > #peers then nextPeer = 1 end
	local peer = peers[nextPeer]
	nextPeer = nextPeer + 1
	local region, group, faction = Scope()
	local held = Held(region, group, faction)
	local rev = held and held.revision or 0
	serial = (serial + 1) % 1000
	local token = ("%d-%d"):format(now, serial)
	local body = ("FZ~1~Q~%s~%d~%s"):format(token, rev, own)
	local function Guard()
		local time = Clock()
		return Sharing(time) == own and Peer(peer.name, own, peer.guild, time)
	end
	if not ns.Comm.Whisper(peer.name, body, "fugitive request", false, false, nil, { guard = Guard }) then return false end
	pending, askedAt = { name = peer.name, guild = peer.guild, own = own, token = token, deadline = now + ASK_FOR }, now
	return true
end

function F.Receive(dist, sender, word)
	if dist ~= "WHISPER" or type(word) ~= "string" or ns.IsSecret(word) or #word > MAX_BLOB + 64 then return false end
	local now = Clock()
	local own = Sharing(now)
	if not own then return false end
	local op, token, body = word:match("^FZ~1~([QS])~(%d+%-%d+)~(.+)$")
	if not op or #token > 15 then return false end
	if op == "S" then
		if not pending or pending.token ~= token or pending.own ~= own or now >= pending.deadline
			or not Peer(sender, own, pending.guild, now) or ns.Fold(sender) ~= ns.Fold(pending.name) then return false end
		local ok = F.Import(body)
		if ok then pending = nil end
		return ok
	end
	local rev, guild = body:match("^(%d+)~([^~%c]+)$")
	rev = Timestamp(rev)
	if not rev or #guild > 72 or now - answeredAt < REPLY_EVERY or not Peer(sender, own, guild, now) then return false end
	local key = ns.Fold(sender)
	if (replyUntil[key] or 0) > now then return false end
	local live, region, group = Live(now)
	if not live or live.revision <= rev then return false end
	local _, scope = Held(region, group, ns.faction)
	local blob = ns.db.federationFugitives[scope]
	local function Guard()
		local time = Clock()
		return Sharing(time) == own and Peer(sender, own, guild, time) and Live(time) == live
	end
	serial = (serial + 1) % 1000
	local pieces = ns.Codec.Chunk("FZ~1~S~" .. token .. "~" .. blob, "F" .. serial)
	if not ns.Comm.SendBatch("WHISPER", pieces, "fugitive reply " .. key, sender, false, nil, { guard = Guard }) then return false end
	for who, expires in pairs(replyUntil) do if expires <= now then replyUntil[who] = nil end end
	replyUntil[key], answeredAt = now + ASK_EVERY, now
	return true
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

local function ReviewRoster()
	local now, program = Clock(), ns.FederationProgram
	local guild = Sharing(now)
	local role = guild and program.Role and program.Role(ns.me, guild, now)
	if role ~= "official" and role ~= "caretaker" then return end
	local roster = ns.Roster.Fresh()
	if roster and roster.guild == guild then return roster, guild end
end

-- A decision allows the usual attended removal only in the current guild.
-- Recheck both the signed list and the native row when the player confirms it.
function F.RemovalAllowed(record)
	if type(record) ~= "table" then return false end
	local roster, guild = ReviewRoster()
	if not roster or record.fugitiveGuild ~= guild or not F.IsListed(record.full, guild) then return false end
	for _, member in ipairs(roster.members or {}) do
		if member.full == record.full and member.raw == record.raw and member.rankIndex == record.rankIndex then return true end
	end
	return false
end

local function ReadRemovals()
	local _, guild = ReviewRoster()
	local count = ns.ChurchCount
	if not guild or not (count and count.Read) then return false end
	reviewRequest = { guild = guild, at = Clock() }
	if not count.Read() then reviewRequest = nil; return false end
	return true
end

local function ProcessRemovals(events)
	local request = reviewRequest
	if not request then return end
	reviewRequest = nil
	local _, guild = ReviewRoster()
	local now = Clock()
	if not guild or guild ~= request.guild or not now or now - request.at > 30 then return end
	local region, group = Scope()
	local rows, hour = {}, math.floor(now / 3600)
	for i = #events, 1, -1 do
		local e = events[i]
		if e.kind == "remove" and e.p2 and e.p1 and e.hour >= hour - 48 and e.hour <= hour then
			local role = e.removerExact and ns.FederationProgram.Role(e.p1, guild, now)
			if ns.Fold(guild) == "olympus prime" or role == "official" or role == "caretaker" then
				local exact = e.removedExact and NameKey(e.p2, region, group) ~= nil
				rows[#rows + 1] = { name = exact and e.p2 or ns.ShortName(e.p2),
					by = e.removerExact and e.p1 or ns.ShortName(e.p1), exact = exact, hour = e.hour }
				if #rows == 40 then break end
			end
		end
	end
	removalReview = { guild = guild, at = now, rows = rows }
	ns.Fire("DATA_CHANGED")
end

local function ReviewRemovalRows(lines, guild, q)
	if q then return end
	lines[#lines + 1] = { header = true, text = L.FUGITIVES_REMOVALS }
	lines[#lines + 1] = { text = L.FUGITIVES_READ_REMOVALS, onClick = ReadRemovals }
	local report = removalReview
	if not report or report.guild ~= guild or Clock() - report.at > 300 then return end
	if #report.rows == 0 then lines[#lines + 1] = { text = L.FUGITIVES_REMOVALS_EMPTY } end
	for _, row in ipairs(report.rows) do
		local label = L.FUGITIVES_REMOVAL_RECORD:format(ns.Codec.Plain(row.name), ns.Codec.Plain(row.by), ns.Ago(row.hour * 3600))
		lines[#lines + 1] = { text = label, indent = 1, right = not row.exact and ns.Views.Grey(L.FUGITIVES_CHECK_REALM) or nil,
			onClick = function()
				local _, current = ReviewRoster()
				if current == guild and removalReview == report and Clock() - report.at <= 300 then
					ns.UI.ShowCopy(L.FUGITIVES_REMOVALS, label .. "\n" .. ns.Codec.Plain(guild) .. "\n" .. L.FUGITIVES_REVIEW_ONLY)
				end
			end }
	end
end

local function ReviewLines(q)
	local V, M = ns.Views, ns.Members
	local lines = { { header = true, text = L.FUGITIVES_ROSTER } }
	local roster, guild = ReviewRoster()
	if not roster then return lines end
	local n = 0
	for _, member in ipairs(roster.members or {}) do
		if F.IsListed(member.full, guild) and (not q or ns.Fold(member.name):find(ns.Fold(q), 1, true)) then
			local record = { raw = member.raw, full = member.full, name = member.name, rankIndex = member.rankIndex,
				rank = member.rank, class = member.class, days = member.days, fugitiveGuild = guild }
			local removable = M.CanRemove() and M.Removable(record)
			lines[#lines + 1] = { text = ns.Codec.Plain(member.name), indent = 1,
				right = removable and V.Red(L.MEMBERS_REMOVE) or nil,
				onClick = removable and function()
					if F.RemovalAllowed(record) then M.AskRemove(record) end
				end or nil }
			n = n + 1
		end
	end
	if n == 0 then lines[#lines + 1] = { text = L.FUGITIVES_ROSTER_EMPTY } end
	ReviewRemovalRows(lines, guild, q)
	return lines
end

local function ReviewLink()
	if not ReviewRoster() then return nil end
	return { id = "fugitive-roster", text = ns.Views.Gold(L.FUGITIVES_ROSTER),
		onClick = function() if ReviewRoster() then ns.Views.ShowPage("fugitive-roster") end end }
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
	if rest == "sync" then
		ns.Print(F.Sync() and L.FUGITIVES_SYNC or L.FUGITIVES_SYNC_WAIT)
		return
	end
	if rest == "roster" then
		if ReviewRoster() then return ns.Views.ShowPage("fugitive-roster") end
		return ns.Print(L.FUGITIVES_ROSTER_UNAVAILABLE)
	end
	if rest == "appeal" then
		local court = ns.Court
		if ns.IsMember() and court and court.Current() and court.InMyZone() then return court.Seek() end
		return ns.Print(L.FUGITIVES_APPEAL)
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
ns.On("CHURCH_NATIVE_GUILD_LOG", ProcessRemovals)
ns.Comm.Handle("FZ", F.Receive)
ns.RealmPages = ns.RealmPages or {}
table.insert(ns.RealmPages, { key = "fugitive-roster", Link = ReviewLink, Lines = ReviewLines })
ns.On("LOGIN", function()
	ns.After(20, "fugitive first sync", F.Sync)
	ns.Every(ASK_EVERY, "fugitive sync", F.Sync)
end)
