local ADDON, ns = ...
local L = ns.L

-- Group listings on the Board (1.2): a leader lists a group for a dungeon, a raid, PvP or a quest,
-- with the roles it still needs; a player applies with one role and a short note; the leader
-- invites or declines from the same page. The Board's flags stay what they are (Board.lua): a
-- player looking for a group raises a flag, a group looking for players is listed here. The
-- Board's page shows one section at a time (its strip: Flags, Dungeons, Raids, PvP, Quests).
-- The invite is the game's own (C_PartyInfo.InviteUnit), from the leader's click on an
-- applicant's Invite; nothing invites anyone by itself, and nothing joins a queue.
--   GL~<id>~<guild>~<kind>~<target>~<level>~<class>~<need>~<size>~<min>~<zone>~<every>~<age>~<title>~<note>
--       id      1-2 base-36 characters, new for each listing and kept by its refreshes
--       kind    D dungeon, R raid, P PvP, Q quest
--       target  D, R and P: a place's key (Groups.PLACES; one this version doesn't know shows
--               as "Other"); Q: the quest's ID in the leader's log, or 0 for a name the
--               leader typed (an elite, a rare, a quest not in his log: its title is that name)
--       level   the leader's, 1-99; class the chats' two-letter code, or empty
--       need    three characters, tanks, healers and damage: a digit 0-9 (how many still
--               wanted) or "+" (any number)
--       size    how many are in the leader's group now, 1-40
--       min     the lowest level that may apply, 2-99, or empty for any
--       zone    a quest's zone as the leader's log (or his map, for a typed name) says it,
--               ZONE_MAX bytes at most; empty for the other kinds
--       every   minutes to its next refresh (EVERY_MIN-EVERY_MAX: 5 while few groups are up, so
--               a leader who left is gone from every Board within about 12 minutes); age:
--               minutes since it was listed
--       title   a quest's title as the leader's log has it (empty for the other kinds)
--       note    the leader's own words, Board.NOTE_MAX bytes at most, the last field
--   The listing goes with the logged API whenever it carries words (a note or a quest's title).
--   GX~<id>                                         lowered by its leader
--   GM~<id>~<more>~<name>:<class>:<role>,...        who else is in the leader's group, after
--                                                   its GL and whenever it changes: a name, the
--                                                   class code, the role when an application
--                                                   said it (else empty); `more` not listed
--                                                   (a raid's names past one message)
--   GA~<id>~<guild>~<role>~<level>~<class>~<note>   an application, whispered to the leader
--                                                   (role T, H or D; the note logged)
--   GW~<id>                                         an application withdrawn (whispered)
--   GR~<id>~<answer>                                the leader's answer, whispered: I invited,
--                                                   D declined, F the listing closed
-- The Board's ask (GQ, Board.lua) is answered with our listing too. Clients before 1.2 have no
-- handler for these: they leave them unread, and their Board is unchanged.
-- What applies to a flag applies here (Board.lua): Olympus guilds only, our own guild's names
-- from our roster, one guild per sender, a name the moderators took off (net-off) neither lists
-- nor applies, an ignored player's listings and applications are left out.

local Groups = {}
ns.Groups = Groups

Groups.KINDS = { "D", "R", "P", "Q" } -- in the order the page's strip shows them
Groups.KIND = { D = true, R = true, P = true, Q = true }
Groups.ROLES = { "T", "H", "D" }
Groups.ROLE = { T = 1, H = 2, D = 3 } -- a role's place in `need`
Groups.MAX = 150             -- listings kept; past it, the one ending soonest goes
Groups.LIST_GAP = 30         -- seconds between two new listings of ours
Groups.LISTS_PER_HOUR = 6
Groups.UPDATE_GAP = 15       -- seconds between two sends of the same listing (an invite changes it)
Groups.LIFETIME = 60 * 60    -- a listing is lowered an hour after it went up...
Groups.QUEST_LIFE = 30 * 60  -- ...a quest's after half an hour
Groups.SLACK = 5 * 60
Groups.NEW_ID_GAP = 20
Groups.LOWERED_TTL = 10 * 60
Groups.TITLE_MAX = 40
Groups.APPLY_GAP = 20        -- seconds between two applications to the same leader
Groups.APPLIES_OPEN = 5      -- applications of ours waiting at once
Groups.APPLICANTS_MAX = 30   -- applications our listing keeps
Groups.CLOSE_TELLS = 10      -- applicants told when our listing closes
Groups.SIZE = { D = 5, Q = 5, R = 40, P = 40 }
-- What a click on a role's need steps through, by kind.
Groups.STEPS = { D = "01234", Q = "01234", R = "012345+", P = "012345+" }
Groups.DEFAULT_NEED = { D = "113", Q = "012", R = "+++", P = "0++" }
Groups.MIN_STEPS = { 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 58, 60 } -- a minimum level's click steps (and the place's own)
Groups.MEMBERS_MAX = 39      -- names a GM may list
Groups.EVERY_MIN, Groups.EVERY_MAX = 5, 30 -- minutes between a listing's refreshes, by how many are up
Groups.ZONE_MAX = 30         -- bytes of a quest's zone
Groups.INVITE_WAIT = 120     -- seconds an invite waits for its player to join before its role is wanted again

-- The places a listing names (WoW: Forever's, as its players know them; a key is never shown).
-- min: the level the place is usually run from (the composer sorts by it). A key this version
-- doesn't know (a later one's place) shows as "Other"; so do OD, OR and OP.
Groups.PLACES = {
	{ key = "RFC", kind = "D", name = "Ragefire Chasm", min = 13 },
	{ key = "THANES", kind = "D", name = "Hall of Thanes", min = 13 },
	{ key = "RUINS", kind = "D", name = "Ruins of Lordaeron", min = 15 },
	{ key = "DM", kind = "D", name = "Deadmines", min = 16 },
	{ key = "WC", kind = "D", name = "Wailing Caverns", min = 17 },
	{ key = "SFK", kind = "D", name = "Shadowfang Keep", min = 18 },
	{ key = "BFD", kind = "D", name = "Blackfathom Deeps", min = 22 },
	{ key = "STOCK", kind = "D", name = "Stockade", min = 23 },
	{ key = "RFK", kind = "D", name = "Razorfen Kraul", min = 24 },
	{ key = "EXCAV", kind = "D", name = "Excavation Site", min = 24 },
	{ key = "GNOME", kind = "D", name = "Gnomeregan", min = 25 },
	{ key = "DALA", kind = "D", name = "City of Dalaran", min = 28 },
	{ key = "SM", kind = "D", name = "Scarlet Monastery", min = 30 },
	{ key = "RFD", kind = "D", name = "Razorfen Downs", min = 34 },
	{ key = "ULDA", kind = "D", name = "Uldaman", min = 35 },
	{ key = "DROWN", kind = "D", name = "Drowned City", min = 35 },
	{ key = "KROL", kind = "D", name = "Krol'dok Stronghold", min = 40 },
	{ key = "MARA", kind = "D", name = "Maraudon", min = 42 },
	{ key = "ZF", kind = "D", name = "Zul'Farrak", min = 42 },
	{ key = "ST", kind = "D", name = "Sunken Temple", min = 45 },
	{ key = "ALCAZ", kind = "D", name = "Alcaz Prison", min = 48 },
	{ key = "BRD", kind = "D", name = "Blackrock Depths", min = 52 },
	{ key = "BRS", kind = "D", name = "Blackrock Spire", min = 53 },
	{ key = "DIRE", kind = "D", name = "Dire Maul", min = 54 },
	{ key = "BLACKM", kind = "D", name = "Blackmaw Hold", min = 55 },
	{ key = "STRAT", kind = "D", name = "Stratholme", min = 55 },
	{ key = "SCHOLO", kind = "D", name = "Scholomance", min = 57 },
	{ key = "SHAPER", kind = "D", name = "Shaper's Terrace", min = 58 },
	{ key = "OD", kind = "D", min = 99 },
	{ key = "ZG", kind = "R", name = "Zul'Gurub", min = 58 },
	{ key = "AQ20", kind = "R", name = "Ruins of Ahn'Qiraj", min = 58 },
	{ key = "MC", kind = "R", name = "Molten Core", min = 60 },
	{ key = "ONY", kind = "R", name = "Onyxia's Lair", min = 60 },
	{ key = "BWL", kind = "R", name = "Blackwing Lair", min = 60 },
	{ key = "AQ40", kind = "R", name = "Temple of Ahn'Qiraj", min = 60 },
	{ key = "NAXX", kind = "R", name = "Naxxramas", min = 60 },
	{ key = "BARROW", kind = "R", name = "Barrow Deeps", min = 60 },
	{ key = "HYJAL", kind = "R", name = "Hyjal Summit", min = 60 },
	{ key = "OR", kind = "R", min = 99 },
	{ key = "WSG", kind = "P", name = "Warsong Gulch", min = 10 },
	{ key = "DARK", kind = "P", name = "Darkspear Island", min = 10 },
	{ key = "AB", kind = "P", name = "Arathi Basin", min = 20 },
	{ key = "AV", kind = "P", name = "Alterac Valley", min = 51 },
	{ key = "WPVP", kind = "P", name = "World PvP", min = 1 },
	{ key = "HILLS", kind = "P", name = "Hillsbrad / Tarren Mill", min = 20 },
	{ key = "BRM", kind = "P", name = "Blackrock Mountain", min = 50 },
	{ key = "SILI", kind = "P", name = "Silithus", min = 55 },
	{ key = "EPL", kind = "P", name = "Eastern Plaguelands", min = 55 },
	{ key = "OP", kind = "P", min = 99 },
}
local placeByKey = {}
for _, p in ipairs(Groups.PLACES) do placeByKey[p.key] = p end

-- Swappable in tests.
Groups.after = function(seconds, where, fn) ns.After(seconds, where, fn) end
Groups.random = math.random

local posts = {}       -- [Name-Realm] = { sender, id, guild, kind, target, level, class, need, size, every, title, note, raisedAt, heardAt, firstSeen }
local lastNewId = {}   -- [Name-Realm] = when its last new id was taken
local lowered = {}     -- ["Name-Realm#id"] = when it was lowered
local own              -- our listing: { id, kind, target, title, need, note, raisedAt, sentAt, every, dirty }
local applicants = {}  -- to our listing: [Name-Realm] = { name, guild, role, level, class, note, at, state }
local apps = {}        -- ours: [leader] = { id, role, at, state, kind, target, title }
local pending = {}     -- our invites waiting for their player to join: [Name-Realm] = { role, at }
local roles = {}       -- our group's members' roles, as they joined or as we set them: [Name-Realm] = role
local filters = {}     -- the page's filters by section: [kind] = "all"... and filters.looking
local rosterPending = false -- (a roster check waiting: GROUP_ROSTER_UPDATE comes in bursts)
local usedIds = {}
local lastList, lists = -math.huge, {}
local view = "flags"   -- the Board's section shown: "flags" (Board.lua's page) or a kind
local opened           -- the card (a leader's name) or applicant opened, its actions under it
local compose          -- the listing being made: { kind, target, title, need }

local function Gold(s) return "|cffffd200" .. s .. "|r" end
local function Grey(s) return "|cff9d9d9d" .. s .. "|r" end
local function Green(s) return "|cff40ff40" .. s .. "|r" end

-- A change of what this screen shows (a card opened, the composer stepped): redrawn at once.
local function Redraw()
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

local changePending = false
local function Changed()
	if changePending then return end
	changePending = true
	Groups.after(1, "groups changed", function()
		changePending = false
		ns.Fire("BOARD_CHANGED")
	end)
end

---------------------------------------------------------------------------
-- The messages
---------------------------------------------------------------------------

-- Words as they may travel and show: one line, no escape code, no separator, n bytes at most.
local function Clean(s, n)
	s = tostring(s or ""):gsub("[%c|~]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return ns.Cut(s, n)
end
function Groups.CleanTitle(s) return Clean(s, Groups.TITLE_MAX) end
local function CleanGuild(s) return (tostring(s or ""):gsub("[~|%c]", "")) end
local function LongGuild(guild)
	return #guild > 72 or select(2, guild:gsub("[^\128-\191]", "")) > 24
end

local function Life(kind) return kind == "Q" and Groups.QUEST_LIFE or Groups.LIFETIME end
Groups.Life = Life

local function ValidNeed(need)
	return type(need) == "string" and need:find("^[0-9+][0-9+][0-9+]$") ~= nil
end
local function ValidTarget(kind, target)
	if kind == "Q" then return target:find("^%d%d?%d?%d?%d?%d?%d?$") ~= nil and (target == "0" or tonumber(target) > 0) end
	return target:find("^[%u%d][%u%d]?[%u%d]?[%u%d]?[%u%d]?[%u%d]?$") ~= nil
end

-- A minimum level as it travels: 2-99, or nil (anyone may apply).
local function CleanMin(min)
	min = tonumber(min)
	if not min then return nil end
	min = math.floor(min)
	return min >= 2 and min <= 99 and min or nil
end
Groups.CleanMin = CleanMin

function Groups.CleanZone(s) return Clean(s, Groups.ZONE_MAX) end

function Groups.Encode(e)
	return ("GL~%s~%s~%s~%s~%d~%s~%s~%d~%s~%s~%d~%d~%s~%s"):format(e.id, CleanGuild(e.guild), e.kind, tostring(e.target),
		math.floor(tonumber(e.level) or 1), tostring(e.class or ""), e.need, math.max(1, math.min(40, math.floor(tonumber(e.size) or 1))),
		tostring(CleanMin(e.min) or ""), e.kind == "Q" and Groups.CleanZone(e.zone) or "", e.every, math.max(0, math.floor(tonumber(e.age) or 0)), e.kind == "Q" and Groups.CleanTitle(e.title) or "", ns.Board.CleanNote(e.note))
end

-- The GL as a table, or nil for anything malformed. Fields past the note are left for later versions.
function Groups.Decode(s)
	if type(s) ~= "string" then return nil end
	local id, guild, kind, target, level, class, need, size, min, zone, every, age, title, rest =
		s:match("^GL~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~?(.*)$")
	if not id or not id:find("^[0-9a-z][0-9a-z]?$") or not Groups.KIND[kind] then return nil end
	if guild == "" or LongGuild(guild) or not ValidTarget(kind, target) or not ValidNeed(need) then return nil end
	level, size = tonumber(level:match("^%d%d?$") or ""), tonumber(size:match("^%d%d?$") or "")
	every, age = tonumber(every:match("^%d%d?$") or ""), tonumber(age:match("^%d%d?%d?$") or "")
	if not level or level < 1 or not size or size < 1 or size > 40 then return nil end
	if not every or every < Groups.EVERY_MIN or every > Groups.EVERY_MAX then return nil end
	if not age or age * 60 > Life(kind) then return nil end
	if class ~= "" and not class:find("^%u%u$") then return nil end
	if min ~= "" and not (min:find("^%d%d?$") and CleanMin(min)) then return nil end
	title = kind == "Q" and Groups.CleanTitle(title) or ""
	if kind == "Q" and target == "0" and title == "" then return nil end -- (a typed name is its title)
	return { id = id, guild = guild, kind = kind, target = target, level = level, class = class, need = need, size = size,
		min = CleanMin(min), zone = kind == "Q" and Groups.CleanZone(zone) or "", every = every, age = age, title = title, note = ns.Board.CleanNote(rest:match("^[^~]*")) }
end

-- Who else is in a group: { { name, class, role } }, as one GM of 250 bytes at most (the names
-- that don't fit are counted in `more`).
function Groups.EncodeMembers(id, list)
	local parts, more, len = {}, 0, 0
	local head = ("GM~%s~"):format(id)
	for _, m in ipairs(list or {}) do
		local name = tostring(m.name or ""):gsub("[~,:|%c]", "")
		local entry = ("%s:%s:%s"):format(name, tostring(m.class or ""):match("^%u%u$") or "", Groups.ROLE[m.role] and m.role or "")
		-- (room for the separator and for `more`, three digits at most)
		if name ~= "" and #parts < Groups.MEMBERS_MAX and #head + 3 + len + #entry + 1 <= 250 then
			parts[#parts + 1] = entry
			len = len + #entry + 1
		else
			more = more + 1
		end
	end
	return head .. more .. "~" .. table.concat(parts, ",")
end
function Groups.DecodeMembers(s)
	if type(s) ~= "string" then return nil end
	local id, more, rest = s:match("^GM~([0-9a-z][0-9a-z]?)~(%d%d?%d?)~([^~]*)")
	if not id then return nil end
	local list = {}
	for entry in rest:gmatch("[^,]+") do
		local name, class, role = entry:match("^([^:]+):(%u?%u?):([THD]?)$")
		if not name or #name > 60 or (class ~= "" and #class ~= 2) then return nil end
		if #list >= Groups.MEMBERS_MAX then return nil end
		list[#list + 1] = { name = name, class = class, role = role ~= "" and role or nil }
	end
	return { id = id, more = tonumber(more), members = list }
end

function Groups.EncodeApply(id, guild, role, level, class, note)
	return ("GA~%s~%s~%s~%d~%s~%s"):format(id, CleanGuild(guild), role, math.floor(tonumber(level) or 1), tostring(class or ""), ns.Board.CleanNote(note))
end
function Groups.DecodeApply(s)
	if type(s) ~= "string" then return nil end
	local id, guild, role, level, class, rest = s:match("^GA~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~?(.*)$")
	if not id or not id:find("^[0-9a-z][0-9a-z]?$") or not Groups.ROLE[role] then return nil end
	if guild == "" or LongGuild(guild) then return nil end
	level = tonumber(level:match("^%d%d?$") or "")
	if not level or level < 1 then return nil end
	if class ~= "" and not class:find("^%u%u$") then return nil end
	return { id = id, guild = guild, role = role, level = level, class = class, note = ns.Board.CleanNote(rest:match("^[^~]*")) }
end

---------------------------------------------------------------------------
-- What a listing says
---------------------------------------------------------------------------

function Groups.KindLabel(kind) return L["GROUPS_KIND_" .. tostring(kind)] or tostring(kind) end
function Groups.RoleLabel(role) return L["GROUPS_ROLE_" .. tostring(role)] or tostring(role) end

-- Where a listing is for: a place's name, a quest's title, or "Other".
function Groups.Target(kind, target, title)
	if kind == "Q" then
		title = Groups.CleanTitle(title)
		return title ~= "" and title or L.GROUPS_QUEST_UNNAMED
	end
	local p = placeByKey[target]
	return p and p.kind == kind and p.name or L.GROUPS_OTHER
end

-- What one role of `need` says, or nil when that role is not wanted.
local function NeedOf(need, role)
	local c = need:sub(Groups.ROLE[role], Groups.ROLE[role])
	if c == "0" or c == "" then return nil end
	return c
end
function Groups.Wants(need, role) return NeedOf(need, role) ~= nil end

-- "Tank, Healer, Damage x3" ("+": any number), or that nothing is wanted now.
function Groups.NeedText(need)
	local parts = {}
	for _, role in ipairs(Groups.ROLES) do
		local c = NeedOf(need, role)
		if c then
			local label = Groups.RoleLabel(role)
			parts[#parts + 1] = c == "+" and (label .. " +") or (c == "1" and label) or (label .. " x" .. c)
		end
	end
	return #parts > 0 and table.concat(parts, ", ") or L.GROUPS_NEED_NONE
end

local function SizeText(kind, size)
	return Groups.SIZE[kind] == 5 and ("%d/5"):format(size) or L.GROUPS_SIZE:format(size)
end

---------------------------------------------------------------------------
-- The listings as this client holds them
---------------------------------------------------------------------------

local function Expires(e)
	local life = Life(e.kind)
	return math.min(e.raisedAt + life, e.firstSeen + life + Groups.SLACK, e.heardAt + (2 * e.every + 2) * 60)
end

local function Off(sender, guild)
	local M = ns.Moderation
	return M and M.Hides ~= nil and M.Hides(sender, guild) ~= nil
end

local function Ignored(sender)
	local api = C_FriendList and C_FriendList.IsIgnored
	if not api then return false end
	local ok, res = pcall(api, ns.DisplayName(sender))
	return ok and res == true
end

local function Prune(now)
	for key, e in pairs(posts) do
		if now >= Expires(e) then
			posts[key] = nil
			lowered[e.sender .. "#" .. e.id] = now
		elseif Off(e.sender, e.guild) then
			posts[key] = nil
		end
	end
	for key, t in pairs(lowered) do
		if now - t > Groups.LOWERED_TTL then lowered[key] = nil end
	end
	-- Our applications to listings that are gone go with them.
	for leader, a in pairs(apps) do
		local e = posts[leader]
		if not e or e.id ~= a.id then apps[leader] = nil end
	end
end

-- How many listings (of a kind, or all) are up now, and the one ending soonest.
function Groups.Count(kind, now)
	now = now or ns.Now()
	local n, soonest, which = 0, nil, nil
	for key, e in pairs(posts) do
		if now < Expires(e) and (not kind or e.kind == kind) and not Off(e.sender, e.guild) then
			n = n + 1
			local x = Expires(e)
			if not soonest or x < soonest then soonest, which = x, key end
		end
	end
	return n, which
end

-- The quest log, read when asked (never in the background): { id, title, level, group }, the
-- group quests first. Classic's GetQuestLogTitle (title, level, suggestedGroup, isHeader, ...,
-- questID as its 8th value), else C_QuestLog.GetInfo where a client has it.
function Groups.QuestLog()
	local out = {}
	local count = 0
	if GetNumQuestLogEntries then
		local ok, n = pcall(GetNumQuestLogEntries)
		if ok then count = tonumber(n) or 0 end
	elseif C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
		local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
		if ok then count = tonumber(n) or 0 end
	end
	count = math.min(count, 200)
	local zone = ""
	for i = 1, count do
		local title, level, group, header, id
		if GetQuestLogTitle then
			local ok, t, lv, g, h, _, _, _, qid = pcall(GetQuestLogTitle, i)
			if ok then title, level, group, header, id = t, lv, g, h, qid end
		elseif C_QuestLog and C_QuestLog.GetInfo then
			local ok, info = pcall(C_QuestLog.GetInfo, i)
			if ok and type(info) == "table" then
				title, level, group, header, id = info.title, info.level, info.suggestedGroup, info.isHeader, info.questID
			end
		end
		if type(title) == "string" and title ~= "" and (header == true or header == 1) then
			zone = Groups.CleanZone(title) -- (a header: the zone of the quests under it)
		elseif type(title) == "string" and title ~= "" and tonumber(id) and tonumber(id) > 0 then
			out[#out + 1] = { id = math.floor(tonumber(id)), title = Groups.CleanTitle(title), level = tonumber(level) or 0, zone = zone,
				group = (tonumber(group) or 0) > 1 or (type(group) == "string" and group ~= "") }
		end
	end
	table.sort(out, function(a, b)
		if a.group ~= b.group then return a.group end
		if a.level ~= b.level then return a.level < b.level end
		return a.title < b.title
	end)
	return out
end
-- The zone we are in, as a quest's zone travels.
function Groups.CurrentZone()
	local z = GetRealZoneText and GetRealZoneText() or (GetZoneText and GetZoneText()) or ""
	return Groups.CleanZone(type(z) == "string" and z or "")
end

local function InLog(target)
	for _, q in ipairs(Groups.QuestLog()) do if tostring(q.id) == tostring(target) then return true end end
	return false
end

-- The listings of a kind (all when none), newest first; for quests, the ones in our log first.
function Groups.List(kind, now)
	now = now or ns.Now()
	Prune(now)
	local out, have = {}, {}
	for _, e in pairs(posts) do
		if not kind or e.kind == kind then out[#out + 1] = e end
	end
	if kind == "Q" and #out > 0 then
		for _, q in ipairs(Groups.QuestLog()) do have[tostring(q.id)] = true end
	end
	table.sort(out, function(a, b)
		local ha, hb = have[a.target] or false, have[b.target] or false
		if ha ~= hb then return ha end
		if a.raisedAt ~= b.raisedAt then return a.raisedAt > b.raisedAt end
		return a.sender < b.sender
	end)
	return out
end

-- Whether a guild's name is the sender's own: our guild's from our roster, another from its claim.
local function Claimed(sender, guild)
	local mine = GetGuildInfo("player")
	if mine and guild == mine then return ns.Roster.RankOf(sender) ~= nil end
	return ns.Data.ClaimGuild(sender, guild) and true or false
end

-- Words through the logged API: a message with words sent without it, where this client has
-- both, keeps none of them (as the Board's notes).
local function UnloggedWords()
	return C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm.DeliveredLogged and not ns.Comm.DeliveredLogged()
end

-- A GL from the channel, or whispered in answer to the Board's ask.
function Groups.HandlePost(dist, sender, text)
	local now = ns.Now()
	if dist == "WHISPER" then
		local askAt = ns.Board.AskedAt and ns.Board.AskedAt()
		if not askAt or now - askAt > ns.Board.ANSWER_WINDOW then return end
	elseif dist ~= "CHANNEL" then
		return
	end
	local e = Groups.Decode(text)
	if not e or not ns.IsFederation(e.guild) then return end
	sender = ns.FullName(sender)
	if sender == ns.me or Ignored(sender) then return end
	if Off(sender, e.guild) then
		if posts[sender] then posts[sender] = nil Changed() end
		return
	end
	if not Claimed(sender, e.guild) then return end
	if (e.note ~= "" or e.title ~= "") and UnloggedWords() then
		ns.Log("group listing from %s shown without its words: not sent with the logged API", sender)
		e.note, e.title = "", ""
	end
	Prune(now)
	if lowered[sender .. "#" .. e.id] then return end
	local old = posts[sender]
	local raisedAt = now - e.age * 60
	if old and old.id == e.id then
		for _, k in ipairs({ "guild", "kind", "target", "level", "class", "need", "size", "min", "zone", "every", "title", "note" }) do old[k] = e[k] end
		old.raisedAt, old.heardAt = math.min(old.raisedAt, raisedAt), now
		return Changed()
	end
	if lastNewId[sender] and now - lastNewId[sender] < Groups.NEW_ID_GAP then return end
	if not old then
		local n, soonest = Groups.Count(nil, now)
		if n >= Groups.MAX and soonest then posts[soonest] = nil end
	end
	lastNewId[sender] = now
	e.sender, e.raisedAt, e.heardAt, e.firstSeen = sender, raisedAt, now, now
	posts[sender] = e
	Changed()
end

function Groups.HandleLower(dist, sender, text)
	if dist ~= "CHANNEL" then return end
	local id = text:match("^GX~([0-9a-z][0-9a-z]?)$")
	if not id then return end
	sender = ns.FullName(sender)
	lowered[sender .. "#" .. id] = ns.Now()
	local e = posts[sender]
	if e and e.id == id then
		posts[sender] = nil
		lastNewId[sender] = nil
		if apps[sender] and apps[sender].id == id then apps[sender] = nil end
		Changed()
	end
end

-- Who else is in a listed group (GM), from its leader: after his GL, on the channel or whispered
-- in answer to our ask. A name the moderators took off, or one we ignore, is left out.
function Groups.HandleMembers(dist, sender, text)
	local now = ns.Now()
	if dist == "WHISPER" then
		local askAt = ns.Board.AskedAt and ns.Board.AskedAt()
		if not askAt or now - askAt > ns.Board.ANSWER_WINDOW then return end
	elseif dist ~= "CHANNEL" then
		return
	end
	local m = Groups.DecodeMembers(text)
	if not m then return end
	sender = ns.FullName(sender)
	local e = posts[sender]
	if not e or e.id ~= m.id then return end
	local list = {}
	for _, x in ipairs(m.members) do
		local M = ns.Moderation
		local hidden = M and M.Hides and M.Hides(x.name, nil, true)
		if not hidden and not Ignored(x.name) then list[#list + 1] = x end
	end
	e.members, e.more = list, m.more
	Changed()
end

---------------------------------------------------------------------------
-- Our listing
---------------------------------------------------------------------------

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function NewId(now)
	for id, t in pairs(usedIds) do if now - t > Groups.LOWERED_TTL then usedIds[id] = nil end end
	local id
	for _ = 1, 9 do
		local n = Groups.random(1, 36 * 36 - 1)
		local hi, lo = math.floor(n / 36), n % 36
		id = (hi > 0 and B36:sub(hi + 1, hi + 1) or "") .. B36:sub(lo + 1, lo + 1)
		if not usedIds[id] then break end
	end
	usedIds[id] = now
	return id
end

local function GroupSize()
	local n = GetNumGroupMembers and tonumber(GetNumGroupMembers()) or 0
	return math.max(1, math.min(40, n))
end

-- Who else is in our group now: { name, class, role }, the role from an application we invited
-- (the game says no role here). raid1..N with a raid (ourselves among them), else party1..4.
function Groups.GroupMembers()
	local out = {}
	local raid = IsInRaid and IsInRaid()
	local n = GetNumGroupMembers and tonumber(GetNumGroupMembers()) or 0
	if n <= 1 or not UnitName then return out end
	for i = 1, raid and n or (n - 1) do
		local unit = (raid and "raid" or "party") .. i
		local name, realm = UnitName(unit)
		if type(name) == "string" and name ~= "" then
			local full = ns.FullName(ns.Normal(name), type(realm) == "string" and realm ~= "" and realm or nil)
			if full ~= ns.me then
				local a = applicants[full]
				local level = UnitLevel and tonumber(UnitLevel(unit)) or nil
				out[#out + 1] = { name = full, class = ns.Roster.ClassCode(UnitClass and select(2, UnitClass(unit))):match("^%u%u$") or "",
					level = level and level > 0 and level or nil,
					role = roles[full] or (a and a.state == "invited" and a.role) or nil }
			end
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end
local function MembersSig(list)
	local parts = {}
	for _, m in ipairs(list) do parts[#parts + 1] = m.name .. ":" .. m.class .. ":" .. (m.role or "") end
	return table.concat(parts, ",")
end

local function MyClass() return ns.Board.MyClass and ns.Board.MyClass() or "" end
local function MyLevel() return ns.Board.MyLevel and ns.Board.MyLevel() or 1 end

local function Message(p, now)
	return Groups.Encode({ id = p.id, guild = GetGuildInfo("player"), kind = p.kind, target = p.target, level = MyLevel(), class = MyClass(),
		need = p.need, size = GroupSize(), min = p.min, zone = p.zone, every = p.every, age = math.floor((now - p.raisedAt) / 60), title = p.title, note = p.note })
end
Groups.Message = Message

local function Words(p) return p.note ~= "" or (p.kind == "Q" and (p.title or "") ~= "") end

-- Our listing and the applications to it are kept for a /reload (per character).
local function Save()
	if not ns.rdb then return end
	local all = type(ns.rdb.groups) == "table" and ns.rdb.groups or {}
	local mine
	if own then
		local list = {}
		for name, a in pairs(applicants) do
			list[name] = { guild = a.guild, role = a.role, level = a.level, class = a.class, note = a.note, at = a.at, state = a.state }
		end
		mine = { id = own.id, kind = own.kind, target = own.target, title = own.title, need = own.need, note = own.note, min = own.min, zone = own.zone,
			raisedAt = own.raisedAt, sentAt = own.sentAt, every = own.every, applicants = list }
	end
	all[ns.me or "?"] = mine
	ns.rdb.groups = next(all) and all or nil
end

function Groups.Restore(now)
	now = now or ns.Now()
	local all = ns.rdb and ns.rdb.groups
	local p = type(all) == "table" and all[ns.me or "?"]
	if type(p) ~= "table" or own then return end
	local fine = type(p.id) == "string" and p.id:find("^[0-9a-z][0-9a-z]?$") and Groups.KIND[p.kind] and type(p.target) == "string"
		and ValidTarget(p.kind, p.target) and not (p.target == "0" and Groups.CleanTitle(p.title) == "") and ValidNeed(p.need) and tonumber(p.raisedAt) and tonumber(p.sentAt) and tonumber(p.every)
	if fine and now - p.raisedAt < Life(p.kind) and now < p.sentAt + (2 * p.every + 2) * 60 then
		own = { id = p.id, kind = p.kind, target = p.target, title = Groups.CleanTitle(p.title), need = p.need, note = ns.Board.CleanNote(p.note),
			min = CleanMin(p.min), zone = p.kind == "Q" and Groups.CleanZone(p.zone) or "",
			raisedAt = p.raisedAt, sentAt = p.sentAt, every = p.every }
		usedIds[p.id] = now
		for name, a in pairs(type(p.applicants) == "table" and p.applicants or {}) do
			if type(name) == "string" and type(a) == "table" and Groups.ROLE[a.role] then
				applicants[name] = { name = name, guild = tostring(a.guild or ""), role = a.role, level = tonumber(a.level) or 1,
					class = tostring(a.class or ""), note = ns.Board.CleanNote(a.note), at = tonumber(a.at) or now, state = a.state == "invited" and "invited" or "new" }
			end
		end
	end
	Save()
end

local function QueueKey(p) return "group" .. p.id end

-- Our GM: who else is in our group, sent after our GL while there is anyone (and once more
-- when the last one leaves).
local function SendMembers(p)
	local list = Groups.GroupMembers()
	local sig = MembersSig(list)
	p.membersSig = sig
	if #list == 0 and not p.membersSent then return end
	p.membersSent = #list > 0
	ns.Comm.Send("CHANNEL", Groups.EncodeMembers(p.id, list), "groupm" .. p.id)
end

-- Minutes between a listing's refreshes: EVERY_MIN while few are up, up to EVERY_MAX when the
-- Board is full (12 seconds a listing), so the channel carries about the same whatever the crowd.
function Groups.Interval(n)
	n = n or Groups.Count()
	return math.max(Groups.EVERY_MIN, math.min(Groups.EVERY_MAX, math.ceil(n * 12 / 60)))
end

local function Send(p, now)
	-- (Inside an instance the game holds addon messages: it goes once we are out, Tick.)
	if ns.ChatLocked() then p.dirty = true return end
	p.every = Groups.Interval(Groups.Count(nil, now))
	p.sentAt, p.dirty = now, nil
	ns.Comm.Send("CHANNEL", Message(p, now), QueueKey(p), nil, Words(p))
	SendMembers(p)
	Save()
end

-- A new listing: ours replaces the one we had (its GX first, as a flag's G0).
function Groups.Post(kind, target, title, need, note, min, zone)
	if not Groups.KIND[kind] or not ValidNeed(need) then return false, "listing" end
	target = tostring(target or "")
	if not ValidTarget(kind, target) then return false, "target" end
	if kind == "Q" and target == "0" and Groups.CleanTitle(title) == "" then return false, "target" end
	local ok, why = ns.Board.Ready()
	if not ok then return false, why end
	local now = ns.Now()
	if now - lastList < Groups.LIST_GAP then
		ns.Print(L.GROUPS_WAIT:format(math.ceil(Groups.LIST_GAP - (now - lastList))))
		return false, "wait"
	end
	for i = #lists, 1, -1 do if now - lists[i] >= 3600 then table.remove(lists, i) end end
	if #lists >= Groups.LISTS_PER_HOUR then
		ns.Print(L.GROUPS_HOURLY:format(Groups.LISTS_PER_HOUR))
		return false, "hourly"
	end
	if not own and Groups.Count(nil, now) >= Groups.MAX then
		ns.Print(L.BOARD_FULL)
		return false, "full"
	end
	lastList = now
	lists[#lists + 1] = now
	if own then Groups.Close(true) end
	own = { id = NewId(now), kind = kind, target = target, title = kind == "Q" and Groups.CleanTitle(title) or "", need = need,
		note = ns.Board.CleanNote(note), min = CleanMin(min), zone = kind == "Q" and Groups.CleanZone(zone) or "", raisedAt = now }
	wipe(applicants)
	compose = nil
	Send(own, now)
	ns.Print(L.GROUPS_LISTED:format(Groups.Target(own.kind, own.target, own.title)))
	Changed()
	return true
end

-- Lowered by us: its GX, and the applicants still waiting told it closed (a few at most).
function Groups.Close(quiet)
	if not own then return false end
	local p = own
	ns.Comm.Send("CHANNEL", "GX~" .. p.id, QueueKey(p))
	local told = 0
	for name, a in pairs(applicants) do
		if a.state == "new" and told < Groups.CLOSE_TELLS then
			told = told + 1
			ns.Comm.Whisper(name, ("GR~%s~F"):format(p.id))
		end
	end
	own = nil
	wipe(applicants)
	wipe(pending)
	opened = nil
	Save()
	if not quiet then ns.Print(L.GROUPS_CLOSED) end
	Changed()
	return true
end

function Groups.Mine() return own end
function Groups.Applicants()
	local out = {}
	for _, a in pairs(applicants) do out[#out + 1] = a end
	table.sort(out, function(a, b)
		if a.at ~= b.at then return a.at < b.at end
		return a.name < b.name
	end)
	return out
end

-- Our listing as the Board's ask is answered with it (Board.lua): the message, and whether it goes logged.
function Groups.AnswerMessage(now)
	if not own then return nil end
	local list = Groups.GroupMembers()
	return Message(own, now or ns.Now()), Words(own), #list > 0 and Groups.EncodeMembers(own.id, list) or nil
end

-- A change of our listing (an invite took a role) goes out soon: at once unless it just went.
local function Update(now)
	if not own then return end
	if now - (own.sentAt or -math.huge) >= Groups.UPDATE_GAP then Send(own, now) else own.dirty = true end
end

-- An application to our listing, whispered.
function Groups.HandleApply(dist, sender, text)
	if dist ~= "WHISPER" or not own then return end
	local a = Groups.DecodeApply(text)
	if not a or a.id ~= own.id or not ns.IsFederation(a.guild) then return end
	if own.min and a.level < own.min then return end -- (their addon refuses it first)
	sender = ns.FullName(sender)
	if sender == ns.me or Ignored(sender) or Off(sender, a.guild) or not Claimed(sender, a.guild) then return end
	if a.note ~= "" and UnloggedWords() then a.note = "" end
	local now = ns.Now()
	local old = applicants[sender]
	if old and now - old.at < Groups.APPLY_GAP then return end
	if not old then
		local n = 0
		for _ in pairs(applicants) do n = n + 1 end
		if n >= Groups.APPLICANTS_MAX then return end
	end
	applicants[sender] = { name = sender, guild = a.guild, role = a.role, level = a.level, class = a.class, note = a.note, at = now,
		state = old and old.state == "invited" and "invited" or "new" }
	-- (A sound of its own, the "groups" switch of /oly sound; once for each new applicant.)
	if not old then ns.PlayAlert("soft", "groups") end
	Save()
	ns.Print(L.GROUPS_APPLICANT:format(ns.DisplayName(sender) or sender, Groups.RoleLabel(a.role), Groups.Target(own.kind, own.target, own.title)))
	Changed()
end

function Groups.HandleWithdraw(dist, sender, text)
	if dist ~= "WHISPER" or not own then return end
	local id = text:match("^GW~([0-9a-z][0-9a-z]?)$")
	sender = ns.FullName(sender)
	if id and id == own.id and applicants[sender] then
		applicants[sender] = nil
		if opened == sender then opened = nil end
		Save()
		Changed()
	end
end

-- Whether we may invite now: not while another player leads our group.
local function MayInvite()
	if IsInGroup and IsInGroup() and UnitIsGroupLeader and not UnitIsGroupLeader("player") then
		ns.Print(L.GROUPS_NOT_LEADER)
		return false
	end
	return true
end

-- The game's invite, from the leader's click (the gp:roster-actions entry: never otherwise).
local function GameInvite(name) -- gp:roster-actions
	local target = ns.TellName(name) or name
	if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(target) elseif InviteUnit then InviteUnit(target) end -- gp:roster-actions
end

-- The leader's click on Invite (as the role they applied for): the game's invite and the applicant
-- told. The role comes off what the listing needs when they join (Groups.CheckJoins), not before:
-- an invite declined or let lapse leaves the role wanted.
function Groups.Invite(name)
	local a = applicants[name]
	if not own or not a then return false end
	if not MayInvite() then return false, "leader" end
	GameInvite(name)
	a.state = "invited"
	pending[name] = { role = a.role, at = ns.Now() }
	ns.Comm.Whisper(name, ("GR~%s~I"):format(own.id))
	ns.Print(L.GROUPS_INVITED:format(ns.DisplayName(name) or name, Groups.RoleLabel(a.role)))
	opened = nil
	Save()
	Changed()
	return true
end

function Groups.Pending() return pending end

-- One of a role found: the need's count goes down by one ("+", any number, stays).
local function TakeRole(role)
	local i = Groups.ROLE[role]
	if not own or not i then return end
	local c = own.need:sub(i, i)
	if c:find("^[1-9]$") then own.need = own.need:sub(1, i - 1) .. tostring(tonumber(c) - 1) .. own.need:sub(i + 1) end
end

-- Who of our invites joined (their role taken off the need, their application done), and whose
-- invite lapsed (INVITE_WAIT: their role wanted again, their application waiting again).
function Groups.CheckJoins(now)
	now = now or ns.Now()
	local here = {}
	for _, m in ipairs(Groups.GroupMembers()) do here[m.name] = true end
	if not next(here) then wipe(roles) end -- (no group: no roles to keep)
	if not own then wipe(pending) return end
	local changed = false
	for name, p in pairs(pending) do
		if here[name] then
			pending[name] = nil
			roles[name] = p.role
			applicants[name] = nil
			TakeRole(p.role)
			changed = true
			ns.Print(L.GROUPS_JOINED:format(ns.DisplayName(name) or name, Groups.RoleLabel(p.role)))
		elseif now - p.at >= Groups.INVITE_WAIT then
			pending[name] = nil
			if applicants[name] then applicants[name].state = "new" end
			changed = true
			ns.Print(L.GROUPS_NOT_JOINED:format(ns.DisplayName(name) or name, Groups.RoleLabel(p.role)))
		end
	end
	if not changed then return end
	if own.need == "000" then
		ns.Print(L.GROUPS_FILLED)
		Groups.Close(true)
		return
	end
	Update(now)
	Save()
	Changed()
end

-- The leader changes what the listing needs (a member switched roles, a friend came from the chat):
-- a click steps one role, as in the composer; it goes out with the listing's next send.
local function Cycle(kind, c)
	local steps = Groups.STEPS[kind]
	local at = steps:find(c, 1, true) or 0
	local i = at % #steps + 1
	return steps:sub(i, i)
end
function Groups.StepOwnNeed(role)
	local i = Groups.ROLE[role]
	if not own or not i then return end
	own.need = own.need:sub(1, i - 1) .. Cycle(own.kind, own.need:sub(i, i)) .. own.need:sub(i + 1)
	Update(ns.Now())
	Save()
	Redraw()
end
-- A member's role as the leader sets it (Tank, Healer, Damage, none, in turn): shown on the
-- group's card on every Board (the GM). The game says no role here.
function Groups.SetMemberRole(name, role)
	if role == nil then
		local cur = roles[name]
		role = cur == nil and "T" or cur == "T" and "H" or cur == "H" and "D" or nil
	end
	roles[name] = Groups.ROLE[role] and role or nil
	if own then Update(ns.Now()) end
	Redraw()
end

function Groups.Decline(name)
	local a = applicants[name]
	if not own or not a then return false end
	ns.Comm.Whisper(name, ("GR~%s~D"):format(own.id))
	applicants[name] = nil
	pending[name] = nil
	opened = nil
	Save()
	Changed()
	return true
end

---------------------------------------------------------------------------
-- Our applications
---------------------------------------------------------------------------

function Groups.Applied(leader) return apps[leader] end

function Groups.Apply(leader, role, note)
	local e = posts[leader]
	if not e then ns.Print(L.GROUPS_GONE) return false, "gone" end
	if not Groups.ROLE[role] or not Groups.Wants(e.need, role) then ns.Print(L.GROUPS_ROLE_FULL) return false, "role" end
	if e.min and MyLevel() < e.min then ns.Print(L.GROUPS_TOO_LOW:format(e.min)) return false, "level" end
	local ok, why = ns.Board.Ready()
	if not ok then return false, why end
	local now = ns.Now()
	local old = apps[leader]
	if old and now - old.at < Groups.APPLY_GAP then
		ns.Print(L.GROUPS_WAIT:format(math.ceil(Groups.APPLY_GAP - (now - old.at))))
		return false, "wait"
	end
	if not old then
		local n = 0
		for _, a in pairs(apps) do if a.state == "sent" then n = n + 1 end end
		if n >= Groups.APPLIES_OPEN then ns.Print(L.GROUPS_TOO_MANY:format(Groups.APPLIES_OPEN)) return false, "many" end
	end
	note = ns.Board.CleanNote(note)
	ns.Comm.Whisper(leader, Groups.EncodeApply(e.id, GetGuildInfo("player"), role, MyLevel(), MyClass(), note), nil, nil, note ~= "")
	apps[leader] = { id = e.id, role = role, at = now, state = "sent", kind = e.kind, target = e.target, title = e.title }
	ns.Print(L.GROUPS_APPLIED:format(Groups.RoleLabel(role), Groups.Target(e.kind, e.target, e.title), ns.DisplayName(leader) or leader))
	Changed()
	return true
end

function Groups.Withdraw(leader)
	local a = apps[leader]
	if not a then return false end
	ns.Comm.Whisper(leader, "GW~" .. a.id)
	apps[leader] = nil
	ns.Print(L.GROUPS_WITHDRAWN)
	Changed()
	return true
end

-- The leader's answer to our application: only from the leader we applied to, for that listing.
function Groups.HandleAnswer(dist, sender, text)
	if dist ~= "WHISPER" then return end
	local id, answer = text:match("^GR~([0-9a-z][0-9a-z]?)~([IDF])$")
	if not id then return end
	sender = ns.FullName(sender)
	local a = apps[sender]
	if not a or a.id ~= id then return end
	local where, who = Groups.Target(a.kind, a.target, a.title), ns.DisplayName(sender) or sender
	if answer == "I" then
		a.state = "invited"
		ns.Print(L.GROUPS_YOU_INVITED:format(who, where))
	elseif answer == "D" then
		apps[sender] = nil
		ns.Print(L.GROUPS_YOU_DECLINED:format(who, where))
	else
		apps[sender] = nil
		ns.Print(L.GROUPS_YOU_CLOSED:format(who, where))
	end
	Changed()
end

---------------------------------------------------------------------------
-- Every 30 seconds: our listing refreshed, sent after a change, or lowered at its end.
---------------------------------------------------------------------------

function Groups.Tick(now)
	now = now or ns.Now()
	Groups.CheckJoins(now)
	if own then
		if not ns.IsMember() then
			own = nil
			wipe(applicants)
			Save()
			Changed()
		elseif now - own.raisedAt >= Life(own.kind) then
			Groups.Close(true)
			ns.Print(L.GROUPS_ENDED)
		elseif Groups.SIZE[own.kind] == 5 and GroupSize() >= 5 then
			-- A party is five: full however it filled (invites from the chat too), it comes down.
			Groups.Close(true)
			ns.Print(L.GROUPS_FILLED)
		elseif not own.dirty and MembersSig(Groups.GroupMembers()) ~= (own.membersSig or "") then
			-- Someone joined or left: the listing (its size) and its GM go again soon.
			Update(now)
		elseif own.dirty and now - (own.sentAt or -math.huge) >= Groups.UPDATE_GAP then
			Send(own, now)
		elseif now - (own.sentAt or -math.huge) >= own.every * 60 then
			Send(own, now)
		end
	end
	Prune(now)
end

---------------------------------------------------------------------------
-- The page: the Board's strip, and a kind's section (Board.Lines calls these)
---------------------------------------------------------------------------

function Groups.View() return view end
function Groups.Showing() return Groups.KIND[view] and true or false end
function Groups.Show(kind, quiet)
	view = Groups.KIND[kind] and kind or "flags"
	opened = nil
	if compose and compose.kind ~= view then compose = nil end
	if not quiet and ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

-- The strip: Flags, then each kind with how many listings it has.
function Groups.NavLine()
	local nav = { { text = L.GROUPS_TAB_FLAGS, selected = view == "flags",
		onClick = view ~= "flags" and function() Groups.Show("flags") end or nil } }
	for _, kind in ipairs(Groups.KINDS) do
		local n = Groups.Count(kind)
		local k = kind
		nav[#nav + 1] = { text = L["GROUPS_TAB_" .. kind] .. (n > 0 and (" (" .. n .. ")") or ""), selected = view == kind,
			onClick = view ~= kind and function() Groups.Show(k) end or nil,
			tooltip = function(tt) tt:AddLine(L["GROUPS_TAB_" .. k], 1, 0.82, 0); tt:AddLine(L.GROUPS_TAB_TIP, 1, 1, 1, true) end }
	end
	return { nav = nav, id = "board-sections" }
end

local function Colored(name, class)
	local file = class and class ~= "" and ns.CLASS_FILES[class]
	local c = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
	name = ns.Codec.Plain(name)
	return c and c.colorStr and ("|c%s%s|r"):format(c.colorStr, name) or name
end

local function ClassName(class)
	local file = class ~= "" and ns.CLASS_FILES[class]
	return file and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file] or nil
end

local function Note(s)
	if not s or s == "" or ns.KingsScreen() then return "" end
	return '  "' .. s .. '"'
end

local function Hit(q, e)
	if not q then return true end
	return ns.Holds(q, Groups.Target(e.kind, e.target, e.title), ns.DisplayName(e.sender), ns.Codec.Plain(e.guild), Groups.NeedText(e.need),
		(Note(e.note)))
end
Groups.Hit = Hit

-- What a listing needs, short enough for its row: "1T 1H 3D" ("T+": any number), or "full".
function Groups.NeedShort(need)
	local parts = {}
	for _, role in ipairs(Groups.ROLES) do
		local c = NeedOf(need, role)
		if c then parts[#parts + 1] = c == "+" and (L["GROUPS_SHORT_" .. role] .. "+") or (c .. L["GROUPS_SHORT_" .. role]) end
	end
	return #parts > 0 and table.concat(parts, " ") or L.GROUPS_FULL
end

-- Our own listing as the list shows it (first, marked as ours), with our group as it is now.
function Groups.OwnEntry()
	if not own then return nil end
	return { sender = ns.me, id = own.id, guild = GetGuildInfo("player") or "", kind = own.kind, target = own.target, title = own.title,
		level = MyLevel(), class = MyClass(), need = own.need, size = GroupSize(), min = own.min, zone = own.zone or "", note = own.note,
		raisedAt = own.raisedAt, members = Groups.GroupMembers(), mine = true }
end

-- Whether we could join a group: of its minimum level, and it still needs someone.
local function CanJoin(e) return not (e.min and MyLevel() < e.min) and e.need ~= "000" end

-- Who is in a group: the names its leader's GM gave (ours: our group as it is), each with its
-- class, its level when we know it and its role when an application or the leader said it.
function Groups.MembersTip(tt, e)
	local list = e.members or {}
	if #list == 0 and (e.more or 0) == 0 then return end
	tt:AddLine(L.GROUPS_IN_GROUP, 1, 0.82, 0)
	for _, m in ipairs(list) do
		local class = ClassName(m.class)
		local bits = {}
		if m.role then bits[#bits + 1] = Groups.RoleLabel(m.role) end
		if m.level then bits[#bits + 1] = L.LEVEL_N:format(m.level) end
		if class then bits[#bits + 1] = class end
		tt:AddLine(Colored(ns.DisplayName(m.name) or m.name, m.class) .. (#bits > 0 and ("  " .. Grey(table.concat(bits, ", "))) or ""), 1, 1, 1)
	end
	if (e.more or 0) > 0 then tt:AddLine(Grey(L.GROUPS_MORE:format(e.more)), 1, 1, 1) end
end

-- A listing in full, on hover: where, its leader, what it needs, its minimum, zone and note, who is in it.
function Groups.ListingTip(tt, e)
	local who = ns.DisplayName(e.sender) or "?"
	tt:AddLine(Groups.KindLabel(e.kind) .. ": " .. Groups.Target(e.kind, e.target, e.title), 1, 0.82, 0)
	local class = ClassName(e.class)
	tt:AddLine(("%s <%s>  %s"):format(who, ns.Codec.Plain(e.guild), L.LEVEL_N:format(e.level)) .. (class and ("  " .. class) or ""), 1, 1, 1)
	tt:AddLine(L.GROUPS_NEEDS:format(Groups.NeedText(e.need)) .. "  (" .. SizeText(e.kind, e.size) .. ")", 1, 1, 1, true)
	if e.min then tt:AddLine(L.GROUPS_MIN_TIP:format(e.min), 1, 1, 1, true) end
	if e.kind == "Q" and (e.zone or "") ~= "" then tt:AddLine(L.GROUPS_ZONE:format(e.zone), 1, 1, 1, true) end
	if e.kind == "Q" and InLog(e.target) then tt:AddLine(L.GROUPS_IN_LOG, 0.25, 1, 0.25) end
	if e.note ~= "" and not ns.KingsScreen() then tt:AddLine('"' .. e.note .. '"', 1, 1, 1, true) end
	Groups.MembersTip(tt, e)
	tt:AddLine(e.mine and L.GROUPS_OWN_TIP or L.GROUPS_CARD_TIP, 0.6, 0.6, 0.6, true)
end

-- A listing's row: where and its leader; on the right what it needs, its minimum, size and age.
-- A click opens its card under it; the mouse over it shows it in full.
function Groups.Card(e)
	local who = ns.DisplayName(e.sender) or "?"
	local where = Groups.Target(e.kind, e.target, e.title)
	local key = e.mine and "own" or e.sender
	local have = e.kind == "Q" and InLog(e.target) and ("  " .. Green(L.GROUPS_IN_LOG)) or ""
	return {
		indent = 1,
		text = Gold("[" .. where .. "]") .. " " .. Colored(who, e.class) .. (e.mine and ("  " .. Green(L.GROUPS_YOUR_GROUP)) or "") .. have,
		right = Gold(Groups.NeedShort(e.need)) .. "  " .. (e.min and (Grey(L.GROUPS_MIN_SHORT:format(e.min)) .. "  ") or "")
			.. SizeText(e.kind, e.size) .. "  " .. Grey(ns.Ago(e.raisedAt)),
		onClick = function() opened = opened ~= key and key or nil; Redraw() end,
		tooltip = function(tt) Groups.ListingTip(tt, e) end,
	}
end

-- What we can do with someone else's listing: apply with a role it needs (of its minimum level),
-- or see our application and withdraw it; whisper its leader.
local function CardActions(lines, e)
	local a = apps[e.sender]
	if a then
		local state = a.state == "invited" and L.GROUPS_APP_INVITED or L.GROUPS_APP_SENT
		lines[#lines + 1] = { indent = 2, text = Green(state:format(Groups.RoleLabel(a.role))),
			right = Grey(ns.Ago(a.at)) }
		lines[#lines + 1] = { indent = 2, text = Gold("> " .. L.GROUPS_WITHDRAW), onClick = function() Groups.Withdraw(e.sender) end }
	elseif e.min and MyLevel() < e.min then
		lines[#lines + 1] = { indent = 2, text = Grey(L.GROUPS_TOO_LOW:format(e.min)) }
	else
		for _, role in ipairs(Groups.ROLES) do
			if Groups.Wants(e.need, role) then
				local r = role
				lines[#lines + 1] = { indent = 2, text = Gold("> " .. L.GROUPS_APPLY_AS:format(Groups.RoleLabel(role))),
					onClick = function() Groups.PromptApply(e.sender, r) end,
					tooltip = function(tt) tt:AddLine(L.GROUPS_APPLY_AS:format(Groups.RoleLabel(r)), 1, 0.82, 0); tt:AddLine(L.GROUPS_APPLY_TIP, 1, 1, 1, true) end }
			end
		end
	end
	lines[#lines + 1] = { indent = 2, text = Gold("> " .. L.GROUPS_WHISPER:format(ns.DisplayName(e.sender) or "?")),
		onClick = function() ns.Board.Whisper(e.sender) end }
end

-- A member's row (the group card, our roster): name in their class's colour; role, level, class.
local function MemberRow(m, indent)
	local class = ClassName(m.class)
	local bits = {}
	if m.level then bits[#bits + 1] = L.LEVEL_N:format(m.level) end
	if class then bits[#bits + 1] = class end
	return { indent = indent, text = Colored(ns.DisplayName(m.name) or m.name, m.class) .. (#bits > 0 and ("  " .. Grey(table.concat(bits, ", "))) or ""),
		right = m.role and Green(Groups.RoleLabel(m.role)) or Grey(L.GROUPS_ROLE_UNSET) }
end

-- The group card, under its opened row: its leader, needs, minimum, zone, note and members, then
-- what we can do (ours: managed under Your group).
local function CardLines(lines, e)
	local who = ns.DisplayName(e.sender) or "?"
	local class = ClassName(e.class)
	local function Add(text, right) lines[#lines + 1] = { indent = 2, text = text, right = right } end
	Add(L.GROUPS_CARD_LEADER:format(Colored(who, e.class), ns.Codec.Plain(e.guild)), Grey(L.LEVEL_N:format(e.level) .. (class and ("  " .. class) or "")))
	Add(L.GROUPS_NEEDS:format(Groups.NeedText(e.need)), SizeText(e.kind, e.size))
	if e.min then Add(L.GROUPS_MIN_TIP:format(e.min)) end
	if e.kind == "Q" and (e.zone or "") ~= "" then Add(L.GROUPS_ZONE:format(e.zone)) end
	if e.note ~= "" and not ns.KingsScreen() then Add('"' .. e.note .. '"') end
	local list = e.members or {}
	if #list > 0 or (e.more or 0) > 0 then
		Add(Gold(L.GROUPS_IN_GROUP))
		for _, m in ipairs(list) do lines[#lines + 1] = MemberRow(m, 3) end
		if (e.more or 0) > 0 then lines[#lines + 1] = { indent = 3, text = Grey(L.GROUPS_MORE:format(e.more)) } end
	end
	if e.mine then Add(Grey(L.GROUPS_MANAGE_ABOVE)) return end
	CardActions(lines, e)
end

-- An application in full, on hover: who, their guild, level and class, the role, the note, when.
function Groups.ApplicantTip(tt, a)
	local who = ns.DisplayName(a.name) or a.name
	local class = ClassName(a.class)
	tt:AddLine(L.GROUPS_APPLIED_AS:format(Colored(who, a.class), Groups.RoleLabel(a.role)), 1, 0.82, 0)
	tt:AddLine(("<%s>  %s"):format(ns.Codec.Plain(a.guild), L.LEVEL_N:format(a.level)) .. (class and ("  " .. class) or ""), 1, 1, 1)
	if a.note ~= "" and not ns.KingsScreen() then tt:AddLine('"' .. a.note .. '"', 1, 1, 1, true) end
	tt:AddLine(ns.Ago(a.at), 0.6, 0.6, 0.6)
	if Groups.GearTip then Groups.GearTip(tt, a) end
	tt:AddLine(L.GROUPS_APPLICANT_TIP, 0.6, 0.6, 0.6, true)
end

-- An applicant to our listing: their role, name, level; a click opens their card (Invite as the
-- role they applied for, Decline, Whisper).
local function ApplicantLines(lines, a)
	local who = ns.DisplayName(a.name) or a.name
	local waiting = pending[a.name]
	lines[#lines + 1] = { indent = 1,
		text = Green(Groups.RoleLabel(a.role)) .. "  " .. Colored(who, a.class) .. "  " .. Grey(L.LEVEL_N:format(a.level)),
		right = (waiting and (Green(L.GROUPS_STATE_INVITED) .. "  ") or "") .. Grey(ns.Ago(a.at)),
		onClick = function() opened = opened ~= a.name and a.name or nil; Redraw() end,
		tooltip = function(tt) Groups.ApplicantTip(tt, a) end }
	if opened == a.name then
		if a.note ~= "" and not ns.KingsScreen() then lines[#lines + 1] = { indent = 2, text = '"' .. a.note .. '"' } end
		if Groups.GearLines then Groups.GearLines(lines, a) end
		if not waiting then
			lines[#lines + 1] = { indent = 2, text = Gold("> " .. L.GROUPS_INVITE_AS:format(Groups.RoleLabel(a.role))), onClick = function() Groups.Invite(a.name) end }
		end
		lines[#lines + 1] = { indent = 2, text = Gold("> " .. L.GROUPS_DECLINE), onClick = function() Groups.Decline(a.name) end }
		lines[#lines + 1] = { indent = 2, text = Gold("> " .. L.GROUPS_WHISPER:format(who)), onClick = function() ns.Board.Whisper(a.name) end }
	end
end

-- Our listing under Your group: it in short (its card on hover), what keeps it from going out or
-- us from inviting, what it needs (a click changes it), our group with its roles, the invites
-- waiting, Lower, then the applications.
local function OwnLines(lines)
	local e = Groups.OwnEntry()
	local where = Groups.Target(own.kind, own.target, own.title)
	lines[#lines + 1] = { indent = 1, text = Green(L.GROUPS_MINE:format(where)),
		right = Gold(Groups.NeedShort(own.need)) .. "  " .. SizeText(own.kind, e.size) .. "  " .. Grey(ns.Ago(own.raisedAt)),
		tooltip = function(tt) Groups.ListingTip(tt, e) end }
	if ns.ChatLocked() then lines[#lines + 1] = { indent = 1, text = "|cffff8040" .. L.GROUPS_LOCKED .. "|r" } end
	if IsInGroup and IsInGroup() and UnitIsGroupLeader and not UnitIsGroupLeader("player") then
		lines[#lines + 1] = { indent = 1, text = "|cffff8040" .. L.GROUPS_NOT_LEADER .. "|r" }
	end
	if Groups.SIZE[own.kind] ~= 5 and e.size >= 5 and not (IsInRaid and IsInRaid()) then
		lines[#lines + 1] = { indent = 1, text = "|cffff8040" .. L.GROUPS_CONVERT .. "|r" }
	end
	for _, role in ipairs(Groups.ROLES) do
		local r = role
		local v = own.need:sub(Groups.ROLE[r], Groups.ROLE[r])
		lines[#lines + 1] = { indent = 1, text = L.GROUPS_WANTED:format(Groups.RoleLabel(r), Gold(v == "+" and L.GROUPS_ANY or v)),
			right = Grey(L.GROUPS_CLICK_CHANGE), onClick = function() Groups.StepOwnNeed(r) end,
			tooltip = function(tt) tt:AddLine(L.GROUPS_EDIT_NEED, 1, 0.82, 0); tt:AddLine(L.GROUPS_EDIT_NEED_TIP, 1, 1, 1, true) end }
	end
	if #e.members > 0 then
		lines[#lines + 1] = { indent = 1, text = Gold(L.GROUPS_ROSTER:format(#e.members + 1)) }
		for _, m in ipairs(e.members) do
			local row = MemberRow(m, 2)
			local name = m.name
			row.onClick = function() Groups.SetMemberRole(name) end
			row.tooltip = function(tt) tt:AddLine(ns.DisplayName(name) or name, 1, 0.82, 0); tt:AddLine(L.GROUPS_SET_ROLE_TIP, 1, 1, 1, true) end
			lines[#lines + 1] = row
		end
	end
	for name, p in pairs(pending) do
		lines[#lines + 1] = { indent = 1, text = Grey(L.GROUPS_PENDING:format(ns.DisplayName(name) or name, Groups.RoleLabel(p.role))), right = Grey(ns.Ago(p.at)) }
	end
	lines[#lines + 1] = { indent = 1, text = Gold("> " .. L.GROUPS_LOWER), onClick = function() Groups.Close() end,
		tooltip = function(tt) tt:AddLine(L.GROUPS_LOWER, 1, 0.82, 0); tt:AddLine(L.GROUPS_LOWER_TIP, 1, 1, 1, true) end }
	local list = Groups.Applicants()
	lines[#lines + 1] = { header = true, text = L.GROUPS_APPLICANTS:format(#list) }
	for _, a in ipairs(list) do ApplicantLines(lines, a) end
	if #list == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.GROUPS_NO_APPLICANTS) } end
end

-- A row of filters (the Board's strip, smaller in purpose): `key` the section's, options { id, label }.
local function FilterLine(key, options)
	local cur = filters[key] or "all"
	local nav = {}
	for _, o in ipairs(options) do
		local id = o[1]
		nav[#nav + 1] = { text = o[2], selected = cur == id,
			onClick = cur ~= id and function() filters[key] = id; opened = nil; Redraw() end or nil }
	end
	return { nav = nav, id = "board-filter-" .. key }
end
function Groups.Filter(key) return filters[key] or "all" end
function Groups.SetFilter(key, id) filters[key] = id end

local function PassGroup(e, f)
	if f == "join" then return CanJoin(e) end
	if f == "log" then return InLog(e.target) end
	if f == "zone" then return (e.zone or "") ~= "" and e.zone == Groups.CurrentZone() end
	return true
end

-- The composer: where, then the roles wanted, then the dialog with the note.
function Groups.StepNeed(role)
	if not compose then return end
	local i = Groups.ROLE[role]
	compose.need = compose.need:sub(1, i - 1) .. Cycle(compose.kind, compose.need:sub(i, i)) .. compose.need:sub(i + 1)
	Redraw()
end
function Groups.Compose(kind)
	compose = Groups.KIND[kind] and { kind = kind, need = Groups.DEFAULT_NEED[kind] } or nil
	Redraw()
end
function Groups.Composing() return compose end
-- A place's own level is the composer's first minimum; a quest's and an unknown place's, none.
local function PlaceMin(kind, target)
	local p = kind ~= "Q" and placeByKey[target]
	return p and p.kind == kind and p.min > 1 and p.min < 99 and p.min or nil
end
function Groups.ChooseTarget(target, title, zone)
	if not compose then return end
	compose.target, compose.title, compose.zone = target, title, zone
	compose.min = target and PlaceMin(compose.kind, target) or nil
	Redraw()
end
-- The minimum level's click: none, then each step up to 60 (the place's own level among them).
function Groups.MinSteps(kind, target)
	local steps, seen = { false }, {}
	local own = PlaceMin(kind, target)
	for _, v in ipairs(Groups.MIN_STEPS) do
		if own and own < v and not seen[own] then steps[#steps + 1], seen[own] = own, true end
		if not seen[v] then steps[#steps + 1], seen[v] = v, true end
	end
	if own and not seen[own] then steps[#steps + 1] = own end
	return steps
end
function Groups.StepMin()
	if not compose or not compose.target then return end
	local steps = Groups.MinSteps(compose.kind, compose.target)
	local at = 1
	for i, v in ipairs(steps) do if v == (compose.min or false) then at = i end end
	compose.min = steps[at % #steps + 1] or nil
	Redraw()
end
-- A quest by a name the leader types (an elite, a rare, one not in his log): its dialog.
function Groups.PromptName()
	if not compose or compose.kind ~= "Q" then return end
	return ns.ShowDialog("OLYMPUS_GROUPS_NAME", nil, nil, { quest = true })
end
function Groups.ConfirmName(data, name)
	if type(data) ~= "table" or data.answered then return end
	data.answered = true
	name = Groups.CleanTitle(name)
	if name == "" or not compose or compose.kind ~= "Q" then return end
	Groups.ChooseTarget("0", name, Groups.CurrentZone())
	return true
end

local function ComposerLines(lines, kind)
	local c = compose
	if c.target then
		lines[#lines + 1] = { indent = 1, text = L.GROUPS_WHERE:format(Gold(Groups.Target(kind, c.target, c.title))),
			right = Grey(L.GROUPS_CHANGE), onClick = function() Groups.ChooseTarget(nil, nil) end }
		for _, role in ipairs(Groups.ROLES) do
			local r = role
			local v = c.need:sub(Groups.ROLE[r], Groups.ROLE[r])
			lines[#lines + 1] = { indent = 1, text = L.GROUPS_WANTED:format(Groups.RoleLabel(r), Gold(v == "+" and L.GROUPS_ANY or v)),
				right = Grey(L.GROUPS_CLICK_CHANGE), onClick = function() Groups.StepNeed(r) end }
		end
		lines[#lines + 1] = { indent = 1, text = L.GROUPS_MIN_LINE:format(Gold(c.min and tostring(c.min) or L.GROUPS_MIN_NONE)),
			right = Grey(L.GROUPS_CLICK_CHANGE), onClick = function() Groups.StepMin() end,
			tooltip = function(tt) tt:AddLine(L.GROUPS_MIN_LINE:format(c.min and tostring(c.min) or L.GROUPS_MIN_NONE), 1, 0.82, 0); tt:AddLine(L.GROUPS_MIN_LINE_TIP, 1, 1, 1, true) end }
		lines[#lines + 1] = { indent = 1, text = Gold("> " .. L.GROUPS_POST), onClick = function() Groups.PromptList() end,
			tooltip = function(tt) tt:AddLine(L.GROUPS_POST, 1, 0.82, 0); tt:AddLine(L.GROUPS_POST_TIP, 1, 1, 1, true) end }
	else
		lines[#lines + 1] = { indent = 1, text = Grey(L.GROUPS_CHOOSE) }
		if kind == "Q" then
			lines[#lines + 1] = { indent = 2, text = Gold("> " .. L.GROUPS_TYPE_NAME), onClick = function() Groups.PromptName() end,
				tooltip = function(tt) tt:AddLine(L.GROUPS_TYPE_NAME, 1, 0.82, 0); tt:AddLine(L.GROUPS_TYPE_NAME_TIP, 1, 1, 1, true) end }
			local log = Groups.QuestLog()
			for _, quest in ipairs(log) do
				local qq = quest
				lines[#lines + 1] = { indent = 2, text = Gold("> " .. quest.title),
					right = Grey((quest.group and (L.GROUPS_GROUP_QUEST .. "  ") or "") .. L.LEVEL_N:format(quest.level)),
					onClick = function() Groups.ChooseTarget(tostring(qq.id), qq.title, qq.zone) end }
			end
			if #log == 0 then lines[#lines + 1] = { indent = 2, text = Grey(L.GROUPS_NO_QUESTS) } end
		else
			for _, p in ipairs(Groups.PLACES) do
				if p.kind == kind then
					local key = p.key
					lines[#lines + 1] = { indent = 2, text = Gold("> " .. Groups.Target(kind, key)),
						right = p.min < 99 and Grey(L.GROUPS_FROM_LEVEL:format(p.min)) or nil,
						onClick = function() Groups.ChooseTarget(key) end }
				end
			end
		end
	end
	lines[#lines + 1] = { indent = 1, text = Grey("> " .. L.GROUPS_CANCEL), onClick = function() Groups.Compose(nil) end }
end

-- A kind's section of the Board: what it is, our group (or how to list one) with its applications,
-- the groups listed (ours first) with their filters, then the players looking.
function Groups.Lines(lines, q)
	local kind = view
	if not q then
		lines[#lines + 1] = { indent = 0, text = Grey(L.GROUPS_EXPLAIN), gapAfter = true }
		lines[#lines + 1] = { header = true, text = L.GROUPS_YOURS,
			tooltip = function(tt) tt:AddLine(L.GROUPS_YOURS, 1, 0.82, 0); tt:AddLine(L.GROUPS_YOURS_TIP, 1, 1, 1, true) end }
		if own and own.kind == kind then
			OwnLines(lines)
		elseif own then
			local k = own.kind
			lines[#lines + 1] = { indent = 1, text = Grey(L.GROUPS_MINE_ELSEWHERE:format(Groups.KindLabel(k))),
				onClick = function() Groups.Show(k) end }
		elseif compose and compose.kind == kind then
			ComposerLines(lines, kind)
		else
			lines[#lines + 1] = { indent = 1, text = Gold("> " .. L.GROUPS_LIST:format(Groups.KindLabel(kind))),
				onClick = function() Groups.Compose(kind) end,
				tooltip = function(tt) tt:AddLine(L.GROUPS_LIST:format(Groups.KindLabel(kind)), 1, 0.82, 0); tt:AddLine(L.GROUPS_LIST_TIP, 1, 1, 1, true) end }
		end
		lines[#lines].gapAfter = true
	end
	local f = filters[kind] or "all"
	local shown = {}
	local mine = own and own.kind == kind and Groups.OwnEntry() or nil
	if mine and Hit(q, mine) then shown[#shown + 1] = mine end
	for _, e in ipairs(Groups.List(kind)) do
		if Hit(q, e) and PassGroup(e, f) then shown[#shown + 1] = e end
	end
	lines[#lines + 1] = { header = true, text = L.GROUPS_UP:format(#shown) }
	local options = { { "all", L.GROUPS_FILTER_ALL }, { "join", L.GROUPS_FILTER_JOIN } }
	if kind == "Q" then
		options[#options + 1] = { "log", L.GROUPS_FILTER_LOG }
		options[#options + 1] = { "zone", L.GROUPS_FILTER_ZONE }
	end
	lines[#lines + 1] = FilterLine(kind, options)
	for _, e in ipairs(shown) do
		lines[#lines + 1] = Groups.Card(e)
		if opened == (e.mine and "own" or e.sender) then CardLines(lines, e) end
	end
	if #shown == 0 then
		local askAt = ns.Board.AskedAt and ns.Board.AskedAt()
		lines[#lines + 1] = { indent = 1, text = Grey((q or f ~= "all") and L.SEARCH_NO_MATCH or (askAt and ns.Now() - askAt < 30 and L.BOARD_GATHERING or L.GROUPS_EMPTY)) }
	end
	-- 1.2: the players whose flag looks for this kind, the ones fitting our group first.
	Groups.LookingLines(lines, kind, q)
	return lines
end

---------------------------------------------------------------------------
-- A flag for several places and roles (1.2: Board.lua carries them after the flag's note)
---------------------------------------------------------------------------

local flagCompose -- { roles = { T = true... }, picks = { D = { any, keys = { [key] = true } } }, open = kind }

-- "Any dungeon, Warsong Gulch, Arathi Basin": a flag's picks by name (Board.ParsePicks' list).
function Groups.PicksText(list)
	local out = {}
	for _, p in ipairs(list or {}) do
		if p.any then out[#out + 1] = L["GROUPS_ANY_" .. p.kind]
		else for _, key in ipairs(p.keys or {}) do out[#out + 1] = Groups.Target(p.kind, key) end end
	end
	return table.concat(out, ", ")
end

function Groups.FlagComposing() return flagCompose ~= nil end
function Groups.ComposeFlag(on)
	flagCompose = on and { roles = {}, picks = {} } or nil
	Redraw()
end
function Groups.FlagRole(role)
	if not flagCompose or not Groups.ROLE[role] then return end
	flagCompose.roles[role] = not flagCompose.roles[role] or nil
	Redraw()
end
function Groups.FlagOpen(kind)
	if not flagCompose then return end
	flagCompose.open = flagCompose.open ~= kind and kind or nil
	Redraw()
end
local function PickCount()
	local n = 0
	for _, p in pairs(flagCompose.picks) do for _ in pairs(p.keys or {}) do n = n + 1 end end
	return n
end
-- A click on a place (or on "Any <kind>", which stands for all of them).
function Groups.FlagPick(kind, key)
	if not flagCompose then return end
	local p = flagCompose.picks[kind] or { keys = {} }
	flagCompose.picks[kind] = p
	if key == "*" then
		p.any, p.keys = not p.any or nil, {}
	elseif p.keys[key] then
		p.keys[key] = nil
	else
		if PickCount() >= ns.Board.PICKS_MAX then ns.Print(L.GROUPS_FLAG_PICKS_MAX:format(ns.Board.PICKS_MAX)) return end
		p.any, p.keys[key] = nil, true
	end
	if not p.any and not next(p.keys) then flagCompose.picks[kind] = nil end
	Redraw()
end
-- The flag the composer makes: its kind (the first picked), roles and picks, or nil while it has none.
function Groups.FlagExtra()
	if not flagCompose then return nil end
	local list = {}
	for _, kind in ipairs(ns.Board.PICK_KINDS) do
		local p = flagCompose.picks[kind]
		if p and p.any then list[#list + 1] = { kind = kind, any = true }
		elseif p then
			local keys = {}
			for _, place in ipairs(Groups.PLACES) do if place.kind == kind and p.keys[place.key] then keys[#keys + 1] = place.key end end
			list[#list + 1] = { kind = kind, keys = keys }
		end
	end
	local roles = ""
	for _, r in ipairs(Groups.ROLES) do if flagCompose.roles[r] then roles = roles .. r end end
	if #list == 0 then return nil end
	return list[1].kind, { roles = roles, picks = ns.Board.PicksString(list) }
end

local function Check(on, text) return (on and Green("[x] ") or Grey("[  ] ")) .. text end

function Groups.FlagComposerLines(lines)
	local c = flagCompose
	lines[#lines + 1] = { indent = 1, text = Grey(L.GROUPS_FLAG_ROLES) }
	for _, role in ipairs(Groups.ROLES) do
		local r = role
		lines[#lines + 1] = { indent = 2, text = Check(c.roles[r], Groups.RoleLabel(r)), onClick = function() Groups.FlagRole(r) end }
	end
	lines[#lines + 1] = { indent = 1, text = Grey(L.GROUPS_FLAG_WHERE:format(ns.Board.PICKS_MAX)) }
	for _, kind in ipairs(ns.Board.PICK_KINDS) do
		local k = kind
		local p = c.picks[k]
		local n = 0
		for _ in pairs(p and p.keys or {}) do n = n + 1 end
		local state = p and p.any and L["GROUPS_ANY_" .. k] or (n > 0 and L.GROUPS_FLAG_PICKED:format(n)) or L.GROUPS_FLAG_NONE
		lines[#lines + 1] = { indent = 2, text = Gold((c.open == k and "- " or "+ ") .. L["GROUPS_TAB_" .. k]) .. "  " .. state,
			onClick = function() Groups.FlagOpen(k) end }
		if c.open == k then
			lines[#lines + 1] = { indent = 3, text = Check(p and p.any, L["GROUPS_ANY_" .. k]), onClick = function() Groups.FlagPick(k, "*") end }
			for _, place in ipairs(Groups.PLACES) do
				if place.kind == k and place.min < 99 then
					local key = place.key
					lines[#lines + 1] = { indent = 3, text = Check(p and p.keys and p.keys[key], place.name),
						right = Grey(L.GROUPS_FROM_LEVEL:format(place.min)), onClick = function() Groups.FlagPick(k, key) end }
				end
			end
		end
	end
	local flag, extra = Groups.FlagExtra()
	if flag then
		lines[#lines + 1] = { indent = 1, text = Gold("> " .. L.GROUPS_FLAG_RAISE), onClick = function() ns.Board.Prompt(flag, nil, extra) end,
			tooltip = function(tt) tt:AddLine(L.GROUPS_FLAG_RAISE, 1, 0.82, 0); tt:AddLine(L.BOARD_RAISE_TIP, 1, 1, 1, true) end }
	else
		lines[#lines + 1] = { indent = 1, text = Grey(L.GROUPS_FLAG_PICK_ONE) }
	end
	lines[#lines + 1] = { indent = 1, text = Grey("> " .. L.GROUPS_CANCEL), onClick = function() Groups.ComposeFlag(false) end }
end

-- The flags on the Board that look for a kind: a plain flag of that kind, or one whose picks
-- name it. (No flag looks for a quest.)
local function FlagPick(e, kind)
	local list = ns.Board.ParsePicks(e.picks)
	if not list then return e.flag == kind and { kind = kind, any = true } or nil end
	for _, p in ipairs(list) do if p.kind == kind then return p end end
	return nil
end
-- Whether a flag fits our listing: it looks for our place (or anything of its kind), plays a role
-- we still need, and is of our minimum level. A flag that names no roles never fits for sure.
function Groups.Fits(e, mine)
	mine = mine or own
	if not mine then return false end
	local p = FlagPick(e, mine.kind)
	if not p then return false end
	if not p.any then
		local found = false
		for _, key in ipairs(p.keys or {}) do if key == mine.target then found = true end end
		if not found then return false end
	end
	if mine.min and (tonumber(e.level) or 0) < mine.min then return false end
	local roles = ns.Board.CleanRoles(e.roles)
	if roles == "" then return false end
	for r in roles:gmatch(".") do if Groups.Wants(mine.need, r) then return true end end
	return false
end

function Groups.Looking(kind)
	local out = {}
	if kind == "Q" then return out end
	for _, e in ipairs(ns.Board.List("flag")) do
		if FlagPick(e, kind) then out[#out + 1] = e end
	end
	table.sort(out, function(a, b)
		local fa, fb = Groups.Fits(a), Groups.Fits(b)
		if fa ~= fb then return fa end
		return a.raisedAt > b.raisedAt
	end)
	return out
end

-- The roles we could invite a flag's player as: the ones their flag names (all, when it names
-- none) that our listing still needs.
function Groups.InviteRoles(e)
	local out = {}
	if not own then return out end
	local plays = ns.Board.CleanRoles(e.roles)
	for _, r in ipairs(Groups.ROLES) do
		if (plays == "" or plays:find(r, 1, true)) and Groups.Wants(own.need, r) then out[#out + 1] = r end
	end
	return out
end

-- Our click on Invite as a role under a flag (our listing of its kind up): the game's invite; the
-- role comes off the need when they join (Groups.CheckJoins).
function Groups.InviteFlag(name, role)
	if not own or not Groups.ROLE[role] then return false end
	if not MayInvite() then return false, "leader" end
	GameInvite(name)
	pending[name] = { role = role, at = ns.Now() }
	ns.Print(L.GROUPS_INVITED:format(ns.DisplayName(name) or name, Groups.RoleLabel(role)))
	opened = nil
	Redraw()
	return true
end

local function PassLooking(e, f)
	if f == "fits" then return Groups.Fits(e) end
	if Groups.ROLE[f] then return ns.Board.CleanRoles(e.roles):find(f, 1, true) ~= nil end
	return true
end

function Groups.LookingLines(lines, kind, q)
	if kind == "Q" then return end
	local f = filters.looking or "all"
	local list = {}
	for _, e in ipairs(Groups.Looking(kind)) do if PassLooking(e, f) then list[#list + 1] = e end end
	lines[#lines].gapAfter = true
	lines[#lines + 1] = { header = true, text = L.GROUPS_LOOKING:format(#list),
		tooltip = function(tt) tt:AddLine(L.GROUPS_LOOKING:format(#list), 1, 0.82, 0); tt:AddLine(L.GROUPS_LOOKING_TIP, 1, 1, 1, true) end }
	lines[#lines + 1] = FilterLine("looking", { { "all", L.GROUPS_FILTER_ALL }, { "fits", L.GROUPS_FITS }, { "T", L.GROUPS_ROLE_T },
		{ "H", L.GROUPS_ROLE_H }, { "D", L.GROUPS_ROLE_D } })
	local found = 0
	for _, e in ipairs(list) do
		if not q or ns.Board.Hit(q, e) then
			found = found + 1
			local card = ns.Board.Card(e)
			card.indent = 1
			local key = "flag:" .. e.sender
			if Groups.Fits(e) then card.text = card.text .. "  " .. Green(L.GROUPS_FITS) end
			card.onClick = function() opened = opened ~= key and key or nil; Redraw() end
			lines[#lines + 1] = card
			if opened == key then
				if own and own.kind == kind and not pending[e.sender] then
					for _, r in ipairs(Groups.InviteRoles(e)) do
						local role = r
						lines[#lines + 1] = { indent = 2, text = Gold("> " .. L.GROUPS_INVITE_AS:format(Groups.RoleLabel(role))),
							onClick = function() Groups.InviteFlag(e.sender, role) end }
					end
				elseif pending[e.sender] then
					lines[#lines + 1] = { indent = 2, text = Grey(L.GROUPS_PENDING:format(ns.DisplayName(e.sender) or "?", Groups.RoleLabel(pending[e.sender].role))) }
				end
				lines[#lines + 1] = { indent = 2, text = Gold("> " .. L.GROUPS_WHISPER:format(ns.DisplayName(e.sender) or "?")),
					onClick = function() ns.Board.Whisper(e.sender) end }
			end
		end
	end
	if found == 0 then lines[#lines + 1] = { indent = 1, text = Grey((q or f ~= "all") and L.SEARCH_NO_MATCH or L.GROUPS_LOOKING_EMPTY) } end
end

---------------------------------------------------------------------------
-- The dialogs: what goes out, and a note (optional)
---------------------------------------------------------------------------

function Groups.PromptList(note)
	local c = compose
	if not c or not c.target then return end
	local what = ("%s: %s  (%s)"):format(Groups.KindLabel(c.kind), Groups.Target(c.kind, c.target, c.title), L.GROUPS_NEEDS:format(Groups.NeedText(c.need)))
		.. (c.min and ("  " .. L.GROUPS_MIN_TIP:format(c.min)) or "")
	return ns.ShowDialog("OLYMPUS_GROUPS_LIST", what, ns.Comm.Audience(), { kind = c.kind, target = c.target, title = c.title, need = c.need,
		min = c.min, zone = c.zone, note = ns.Board.CleanNote(note) })
end

function Groups.ConfirmList(data, note)
	if type(data) ~= "table" or data.answered then return end
	data.answered = true
	return Groups.Post(data.kind, data.target, data.title, data.need, note, data.min, data.zone)
end

function Groups.PromptApply(leader, role, note)
	local e = posts[leader]
	if not e then return ns.Print(L.GROUPS_GONE) end
	local what = L.GROUPS_APPLY_WHAT:format(Groups.RoleLabel(role), Groups.Target(e.kind, e.target, e.title), ns.DisplayName(leader) or leader)
	return ns.ShowDialog("OLYMPUS_GROUPS_APPLY", what, ns.Comm.Audience(), { leader = leader, role = role, note = ns.Board.CleanNote(note) })
end

function Groups.ConfirmApply(data, note)
	if type(data) ~= "table" or data.answered then return end
	data.answered = true
	return Groups.Apply(data.leader, data.role, note)
end

local function NoteDialog(text, button, confirm, where)
	return {
		text = text,
		button1 = button,
		button2 = CANCEL or "Cancel",
		hasEditBox = true,
		editBoxWidth = 260,
		maxLetters = ns.Board.NOTE_MAX,
		maxBytes = ns.Board.NOTE_MAX + 1,
		OnShow = function(self, data)
			local eb = self.editBox or self.EditBox
			data = data or self.data
			if eb then eb:SetText(type(data) == "table" and data.note or "") eb:SetFocus() end
		end,
		OnAccept = function(self, data)
			local eb = self.editBox or self.EditBox
			ns.SafeCall(where, confirm, data or self.data, eb and eb:GetText())
		end,
		EditBoxOnEnterPressed = function(self)
			local parent = self:GetParent()
			ns.SafeCall(where, confirm, parent.data, self:GetText())
			parent:Hide()
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
end
StaticPopupDialogs["OLYMPUS_GROUPS_LIST"] = NoteDialog(L.GROUPS_LIST_ASK, L.GROUPS_LIST_BTN, function(...) return Groups.ConfirmList(...) end, "groups list")
do
	local name = NoteDialog(L.GROUPS_NAME_ASK, L.GROUPS_NAME_BTN, function(...) return Groups.ConfirmName(...) end, "groups name")
	name.maxLetters, name.maxBytes = Groups.TITLE_MAX, Groups.TITLE_MAX + 1
	StaticPopupDialogs["OLYMPUS_GROUPS_NAME"] = name
end
StaticPopupDialogs["OLYMPUS_GROUPS_APPLY"] = NoteDialog(L.GROUPS_APPLY_ASK, L.GROUPS_APPLY_BTN, function(...) return Groups.ConfirmApply(...) end, "groups apply")

---------------------------------------------------------------------------
-- /oly group [dungeon | raid | pvp | quest | off]
---------------------------------------------------------------------------

Groups.WORDS = { d = "D", dungeon = "D", dungeons = "D", masmorra = "D", r = "R", raid = "R", raids = "R", raide = "R",
	p = "P", pvp = "P", jxj = "P", q = "Q", quest = "Q", quests = "Q", missao = "Q", ["miss\195\163o"] = "Q" }
function Groups.Slash(rest)
	local word = ns.Fold((tostring(rest or ""):match("^(%S*)")))
	if word == "off" then
		if not Groups.Close() then ns.Print(L.GROUPS_NONE_UP) end
		return
	end
	local kind = word == "" and (own and own.kind or "D") or Groups.WORDS[word]
	if not kind then return ns.Print(L.HELP_GROUPS) end
	Groups.Show(kind, true)
	ns.Board.Open()
end

-- /oly status
function Groups.StatusLine()
	local n = 0
	for _ in pairs(applicants) do n = n + 1 end
	local open = 0
	for _ in pairs(apps) do open = open + 1 end
	return ("groups %d  |  mine: %s  |  applicants %d  |  my applications %d"):format((Groups.Count()),
		own and ("%s %s %s, every %d min"):format(own.kind, own.target, ns.Ago(own.raisedAt), own.every or 0) or "none", n, open)
end

-- Tests start from nothing.
function Groups.Reset()
	wipe(posts); wipe(lastNewId); wipe(lowered); wipe(applicants); wipe(apps); wipe(usedIds); wipe(lists)
	wipe(pending); wipe(roles); wipe(filters)
	rosterPending = false
	own, opened, compose, view, flagCompose = nil, nil, nil, "flags", nil
	lastList = -math.huge
	changePending = false
	if ns.rdb then ns.rdb.groups = nil end
end

ns.Comm.Handle("GL", function(...) Groups.HandlePost(...) end)
ns.Comm.Handle("GX", function(...) Groups.HandleLower(...) end)
ns.Comm.Handle("GM", function(...) Groups.HandleMembers(...) end)
ns.Comm.Handle("GA", function(...) Groups.HandleApply(...) end)
ns.Comm.Handle("GW", function(...) Groups.HandleWithdraw(...) end)
ns.Comm.Handle("GR", function(...) Groups.HandleAnswer(...) end)

-- Someone joined or left our group: our invites checked a second later (the event comes in bursts).
ns.RegisterEvent("GROUP_ROSTER_UPDATE", function()
	if rosterPending then return end
	rosterPending = true
	Groups.after(1, "groups roster", function()
		rosterPending = false
		ns.SafeCall("groups joins", Groups.CheckJoins)
		Changed()
	end)
end)

ns.On("LOGIN", function()
	Groups.Restore()
	ns.Every(30, "groups", function() Groups.Tick() end)
end)
