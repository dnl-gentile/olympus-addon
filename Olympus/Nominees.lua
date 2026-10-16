local ADDON, ns = ...
local L = ns.L

-- The guild masters' nominees (1.1.5, the author's ask after the High Council's yes): the guild
-- master of an Olympus guild names, from Olympus, up to MAX_CENTURIONS centurions and one
-- correspondent per department of the High Council (the named departments of the council's signed
-- titles list, MAX_DEPTS at most): MAX people in all, members of his own guild. The addon holds the
-- caps (an eleventh centurion, a second correspondent for a department, someone named twice, a
-- name outside his roster: each refused with its reason), so nobody has to count them by hand.
-- Correspondents retain their guild-verified border. A Legate appointment itself grants no
-- special portrait border: the native guild rank and separately earned honours still apply.
--
-- Where (1.1.5, the author's call on seeing the page): a tab of its own, in the Throne's place
-- (King.lua's Build; UI.lua's "throne" key). A guild master of an Olympus guild (not the King's)
-- has it as his Guild tab, his guild's page: the King's Hands page's look and flow (King.lua's HandsLines, the
-- Throne's parchment and ink), a title, a one-line hint, "+ Name a centurion (your target, or type
-- a name)", his list with a click that takes the title back (asked first), the departments'
-- correspondents (the role picker: a line per department, a click names its correspondent) and the
-- note on how the army learns his list. And
-- `/oly nominees [centurion <name> | correspondent <n> <name> | remove <name>]` (alone: the tab).
--
-- The current manual rank is Legate. Existing centurion/c wire and save keys are compatibility
-- aliases, not a different role. The King's guild has manual appointments too, by the actual
-- King or a signed High Councillor; a council seat alone never appoints its holder. No automatic
-- retirement or deletion of the earlier manual lists. No correspondents in the King's guild.
--
-- How it travels, as the King's list of Hands (King.lua): the guild master's own client keeps his
-- list (ns.rdb.nominees, under his character) and sends it on the Olympus channel a few seconds
-- after each change and every EVERY seconds while he is online. Every client takes it only from
-- that guild's master as the census proves him, the very proof the borders ask for a guild
-- master's bronze (Borders.lua's Facts): our own guild's from our roster (the server's word),
-- another guild's from its census report, two senders naming him guild master, one of them
-- someone else (Data.KnownRank). The sender is the name the server stamps, so nobody can send it
-- for him. A list from anyone else is refused, and never takes the place of the real one. Each
-- client keeps the last accepted list even after its master stopped repeating it, and drops it
-- when the census or our roster authoritatively shows he is no longer that
-- guild's master (another one proven, or his own rank below it), or when his new list names nobody.
-- (1.2.4, the author's ask: "if the GM isn't online ... it has to be kept": no age-only expiry; the
-- lists heard are saved, ns.rdb.nomineesHeard, SAVED_MAX at most, put back after a logout or a
-- /reload (Restore). Until 1.2.3 they were kept in memory, 6 hours: a guild master offline
-- since the evening, or a /reload, left his guild with no centurion, no correspondent, no department.)
--   NM~1~<guild>~<rev>~<i>~<n>~<entry>;<entry>;...
-- One list in n parts (i of n), each one addon message of PART bytes at most, put together by
-- their <rev> (the time of his last change); an entry is c=<Name[-Realm]> (a centurion) or
-- d=<department>=<Name[-Realm]> (that department's correspondent), a name without a realm his
-- own realm's. Bounded on every side: MAX_PARTS parts, the caps above (the first ones kept), each
-- name and each department once, a department's name of DEPT_LEN bytes. No part is ever chunked:
-- clients before 1.1.5 have no handler for NM and leave each part unread, nothing counted bad
-- (Comm.lua). Version 1: a client takes the parts of its own version alone.
-- The gamepad UI: the borders and marks it gives are off there, as every border (Borders.lua), and
-- its name boxes are Olympus's own dialogs (ns.ShowDialog), never the game's popups.
-- /oly status: his own list, and the lists held here (Nominees.StatusLine).

local Nominees = {}
ns.Nominees = Nominees

-- The High Council's departments (the author's names, 1.1.5): the correspondents' roles, one each
-- per guild, and (1.2.4) the Chat page's department rooms (ChatRooms.lua builds them from this list:
-- each one's room id, the names the signed titles list has given it, and its label's locale key, in
-- English until translated). A department added here is one line: its correspondents, its room
-- and its place on the guild master's page follow. (ns.DEPARTMENT_LIST is the same list: a test's
-- stand-in for this file keeps ChatRooms.lua's rooms.)
Nominees.DEPARTMENT_LIST = {
	{ name = "Federal Treasury", room = "dept:treasury", aliases = { "federal treasury", "treasury" }, label = "CHATROOM_DEPT_TREASURY" },
	{ name = "Department of War", room = "dept:war", aliases = { "department of war", "war" }, label = "CHATROOM_DEPT_WAR" },
	{ name = "Council of Justice", room = "dept:justice", aliases = { "council of justice", "justice" }, label = "CHATROOM_DEPT_JUSTICE" },
	{ name = "Association of Artisanry", room = "dept:citizenry", aliases = { "association of artisanry", "association of citizenry", "artisanship" }, label = "CHATROOM_DEPT_ARTISANRY" },
	{ name = "Department of Heraldry", room = "dept:heritage", aliases = { "department of heraldry", "department of heritage", "heritage", "heraldry", "outreach" }, label = "CHATROOM_DEPT_HERITAGE" },
	{ name = "The Missionary Church of Olympus", room = "dept:church", aliases = { "the missionary church of olympus" }, label = "CHATROOM_DEPT_CHURCH" },
}
ns.DEPARTMENT_LIST = Nominees.DEPARTMENT_LIST
Nominees.DEPARTMENTS = {}
for i, d in ipairs(Nominees.DEPARTMENT_LIST) do Nominees.DEPARTMENTS[i] = d.name end

Nominees.MAX_CENTURIONS = 25 -- current Legates cap; old public name/wire retained for compatibility
Nominees.MAX_LEGATES = Nominees.MAX_CENTURIONS
Nominees.MAX_DEPTS = #Nominees.DEPARTMENTS
Nominees.MAX = Nominees.MAX_CENTURIONS + Nominees.MAX_DEPTS
Nominees.EVERY = 300          -- his client repeats the list for late logins
Nominees.FRESH = 30 * 86400   -- finite legacy compatibility constant, NOT accepted-list expiry
Nominees.SAVED_MAX = 300      -- (1.2.4) the lists heard the saved variables keep (the census's guilds, Data.MAX_GUILDS), the newest heard; our own guild's always
Nominees.REV_QUIET = 6 * 60 * 60 -- (1.2.4) a master's list of an older revision is his word again once the one held went this long unheard
Nominees.SEND_AFTER = 3       -- several changes in a row go out as one list
Nominees.PART = 250           -- bytes in one part (one addon message)
Nominees.MAX_PARTS = Nominees.MAX
Nominees.PART_WAIT = 60       -- the parts of one list wait this long for the rest
Nominees.DEPT_LEN = 40
Nominees.WIRE = "1"           -- the message's version

local lists = {}   -- [guild, lower case] = { guild, by, rev, at, entries = { { role, dept, name } }, set = { [name, lower case] = entry } }
-- (1.2.4) The saved variables the lists heard were last put back from (Restore, at the first
-- look after a login or a /reload; Nominees.Reset(true) forgets it, as a /reload does).
local restoredFrom, Restore
local function Lists()
	if restoredFrom ~= ns.rdb and Restore then Restore() end
	return lists
end
local pending = {} -- [sender] = { guild, rev, n, parts = { [i] = body }, got, t }: a list's parts as they come
local version = 0  -- one more at each change of what any list counts for (Borders.Changed)
local lastSent, sendPending = -math.huge, false
local sentOnce = false -- his list went out this session (then an empty one goes out too)
-- Main manual-list repeat pacing. An editor's accepted newer copy is adopted, not auto-retired.
local lastMainSent, mainHeardAt, mainSendPending = -math.huge, -math.huge, false

function Nominees.Version() return version end
local function Bump() version = version + 1 end

---------------------------------------------------------------------------
-- Names, guilds, departments
---------------------------------------------------------------------------

local function Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function Revision(v)
	v = tonumber(v)
	return v and v == v and v >= 0 and v <= 4294967295 and v == math.floor(v) and v or nil
end

-- A character's name as the server writes it ("First Surname-Realm"; a name without a realm is
-- `realm`'s, ours when none), or nil if it can't be one: letters only (Forever's first name and
-- surname), the realm letters and digits.
local function Person(s, realm)
	s = Trim(ns.Normal(Trim(s)))
	local short, theirs = s:match("^([^%-]+)%-([^%-]+)$")
	short = short or s
	if #short > 30 or not short:match("^[%a\128-\255]+ ?[%a\128-\255]*$") then return nil end
	if theirs and (#theirs > 40 or not theirs:match("^[%w\128-\255]+$")) then return nil end
	return ns.FullName(short, theirs or realm)
end
Nominees.Person = Person

-- A name typed, as our roster spells it (the server's): whatever its case, and (anyRealm: typed
-- without one) on another realm when only one member carries it. nil when our roster has nobody
-- of that name.
local function RosterName(name, anyRealm)
	if type(name) ~= "string" then return nil end
	if ns.Roster.RankOf(name) ~= nil then return name end
	local byName = ns.Roster.byName
	if type(byName) ~= "table" then return nil end
	local low, short = name:lower(), ns.ShortName(name):lower()
	local found, twice
	for full in pairs(byName) do
		if type(full) == "string" then
			if full:lower() == low then return full end
			if anyRealm and ns.ShortName(full):lower() == short then
				twice = found ~= nil
				found = found or full
			end
		end
	end
	return not twice and found or nil
end

-- An Olympus guild's name as a list may give it, or nil.
local function GuildName(s)
	s = tostring(s or ""):gsub("[%c|]", "")
	if s == "" or #s > 24 or not s:match("^[%w\128-\255 ]+$") or not ns.IsFederation(s) then return nil end
	return s
end

-- A department's name as the lists carry it: no separator of theirs, DEPT_LEN bytes at most.
local function DeptName(s)
	s = Trim(tostring(s or ""):gsub("[%c|~;=]", ""))
	if s == "" or #s > Nominees.DEPT_LEN then return nil end
	if s:lower() == "association of citizenry" or s:lower() == "association of artisanry" then return "Association of Artisanry" end
	if s:lower() == "department of heritage" or s:lower() == "department of heraldry" or s:lower() == "heraldry" or s:lower() == "heritage" then return "Department of Heraldry" end
	return s
end
Nominees.DepartmentName = DeptName

-- (Nominees.DEPARTMENTS, the departments' names, comes from Nominees.DEPARTMENT_LIST above. The
-- signed titles list names only the departments that have councillors.)
Nominees.SHIPPED_DEPARTMENTS = Nominees.DEPARTMENTS
function Nominees.Departments()
	local out = {}
	for i, name in ipairs(Nominees.DEPARTMENTS) do
		if i <= Nominees.MAX_DEPTS then out[#out + 1] = name end
	end
	return out
end
local function IsDept(dept)
	if type(dept) ~= "string" then return nil end
	dept = DeptName(dept)
	if not dept then return nil end
	for _, d in ipairs(Nominees.Departments()) do
		if d:lower() == dept:lower() then return d end
	end
	return nil
end

-- A role as a line says it: "centurion", "correspondent for Events".
function Nominees.RoleLabel(role, dept)
	if role == "correspondent" then return L.NOMINEE_ROLE_CORRESPONDENT:format(dept or "?") end
	return L.NOMINEE_ROLE_CENTURION
end
local DEPT_DUTY = {
	["Federal Treasury"] = "NOMINEES_DUTY_TREASURY",
	["Department of War"] = "NOMINEES_DUTY_WAR",
	["Council of Justice"] = "NOMINEES_DUTY_JUSTICE",
	["Association of Artisanry"] = "NOMINEES_DUTY_ARTISANRY",
	["Department of Heraldry"] = "NOMINEES_DUTY_HERALDRY",
	["The Missionary Church of Olympus"] = "NOMINEES_DUTY_CHURCH",
}
function Nominees.DepartmentHelp(dept)
	local key = DEPT_DUTY[DeptName(dept)]
	return key and L[key] or nil
end

---------------------------------------------------------------------------
-- Who is the guild's master
---------------------------------------------------------------------------

-- This character is the guild master of an Olympus guild (the server's rank), and that guild.
local function RealMaster()
	if ns.IsMember() ~= true then return false end
	local guild, _, rank = GetGuildInfo("player")
	-- (The King's own guild has no centurions or correspondents: the author's call.)
	if type(guild) == "string" and ns.IsKingGuild and ns.IsKingGuild(guild) then return false end
	return rank == 0 and type(guild) == "string", guild
end

-- The author's "guild master's view" (1.1.5, his ask: his character is no guild master): from the
-- Workshop, his section shows as a guild master's would, to see and try it. Nothing it does is
-- sent (Nominees.Send refuses it): what he names stays on his screen. Since 1.2 it is View as's
-- "Guild Master" (ViewAs.lua): that preview drives it, and /oly nominees view picks it there.
local function ViewAsGM()
	local V = ns.ViewAs
	return type(V) == "table" and not V.missing and type(V.Is) == "function" and V.Is("gm") == true
end
function Nominees.DevView()
	if RealMaster() then return false end
	if ViewAsGM() then return true end
	return ns.db ~= nil and ns.db.devGMView == true and ns.Workshop ~= nil and ns.Workshop.Visible ~= nil
		and ns.Workshop.Visible() == true
end
function Nominees.SetDevView(on)
	local V = ns.ViewAs
	if type(V) == "table" and not V.missing and type(V.Available) == "function" and V.Available() == true
		and type(V.Set) == "function" and (on or ViewAsGM()) then
		V.Set(on and "gm" or "my") -- (it clears the old switch, ns.db.devGMView, and redraws)
	else
		ns.db.devGMView = on and true or false
		ns.Fire("DATA_CHANGED")
	end
	ns.Print(on and ns.L.DEV_GM_VIEW_NOW_ON or ns.L.DEV_GM_VIEW_NOW_OFF)
end

function Nominees.IsMaster()
	local real, guild = RealMaster()
	if real then return real, guild end
	if Nominees.DevView() then return true, GetGuildInfo("player") or "Olympus" end
	return false
end

-- The King's own guild: its centurions are the High Council (1.2.4), nobody's list.
local function IsMain(guild) return type(guild) == "string" and ns.IsKingGuild(guild) == true end
Nominees.IsMain = IsMain
function Nominees.MainGuild() return ns.KingGuildName() end

-- `sender` is `guild`'s master as Borders proves the bronze: our own guild's from our roster (the
-- server's), another guild's from its census (two senders naming him, one of them someone else).
-- The King's guild's (1.1.5's list, from an older client: Retired below): the King's character or
-- a signed High Councillor.
local function Proven(sender, guild)
	if IsMain(guild) then return ns.IsKingCharacter(sender) == true or ns.IsHighCouncillor(sender) == true end
	local mine = GetGuildInfo("player")
	if mine and guild == mine then return ns.Roster.RankOf(sender) == 0 end
	if mine and guild:lower() == mine:lower() then return false end -- (our guild spelled another way)
	local rank, named = ns.Data.KnownRank(sender, guild)
	return rank == 0 and (named or 0) >= 2
end
Nominees.Proven = Proven

-- He is no longer that guild's master, as far as this client can tell: our roster gives him
-- another rank or names another guild master; another guild's census proves another one, or gives
-- him another rank. Nothing known (a census gone quiet): not that.
local function Deposed(l)
	if l.main then
		if ns.IsKingCharacter(l.by) or ns.IsHighCouncillor(l.by) then return false end
		local c = ns.rdb and ns.rdb.council
		return type(c) == "table" and type(c.names) == "table" -- missing council: unknown, not removal
	end
	local mine = GetGuildInfo("player")
	if mine and l.guild:lower() == mine:lower() then
		local rank = ns.Roster.RankOf(l.by)
		if rank ~= nil then return rank ~= 0 end
		local stats = ns.Roster.lastStats
		local lead = ns.Roster.guild == mine and type(stats) == "table" and stats.leader or nil
		return type(lead) == "string" and ns.FullName(lead):lower() ~= l.by:lower()
	end
	local rank = ns.Data.KnownRank(l.by, l.guild)
	if rank ~= nil and rank ~= 0 then return true end
	local g = ns.Data.Guild(l.guild)
	if type(g) == "table" and type(g.leader) == "string" then
		local lead = ns.FullName(g.leader, g.realm)
		if lead:lower() ~= l.by:lower() then
			local other, named = ns.Data.KnownRank(lead, l.guild)
			if other == 0 and (named or 0) >= 2 then return true end
		end
	end
	return false
end

---------------------------------------------------------------------------
-- The guild master's own list (his client's alone)
---------------------------------------------------------------------------

-- His saved list for the guild he leads now, made when `make` (nil when he leads none).
-- { guild, rev, list = { { r = "c" | "d", d = department, n = "Name-Realm" }, ... } }
local function Saved(make)
	local master, guild = Nominees.IsMaster()
	if not master or not ns.rdb or not ns.me then return nil end
	local all = ns.rdb.nominees
	local s = type(all) == "table" and all[ns.me] or nil
	if type(s) ~= "table" or s.guild ~= guild or type(s.list) ~= "table" then
		if not make then return nil end
		if type(all) ~= "table" then all = {}; ns.rdb.nominees = all end
		s = { guild = guild, rev = ns.Now(), list = {} }
		all[ns.me] = s
	end
	return s
end

-- His entries as they count (a correspondent's department still one of the council's), in
-- order: { { role, dept, name } }; and the ones that do not (their department gone).
local function OwnEntries(s)
	local out, stale, c, depts = {}, {}, 0, {}
	for _, e in ipairs(s and s.list or {}) do
		if type(e) == "table" and type(e.n) == "string" then
			if e.r == "c" and c < Nominees.MAX_CENTURIONS then
				c = c + 1
				out[#out + 1] = { role = "centurion", name = e.n }
			elseif e.r == "d" then
				local dept = IsDept(e.d)
				if dept and not depts[dept:lower()] then
					depts[dept:lower()] = true
					out[#out + 1] = { role = "correspondent", dept = dept, name = e.n }
				else
					stale[#stale + 1] = { role = "correspondent", dept = tostring(e.d or "?"), name = e.n }
				end
			end
		end
	end
	return out, stale
end

---------------------------------------------------------------------------
-- The King's manual Legates (legacy centurion save/wire identifiers)
---------------------------------------------------------------------------

-- Council authority permits manual naming; it does not itself appoint the councillor. A preview
-- edits only its own local sample. Earlier manual saves and the unchanged c= wire are retained.

-- The King's character, or a signed High Councillor: the clients older ones take that list from.
function Nominees.MainEditor()
	if ns.IsMember() ~= true then return false end
	local K = ns.King
	local V = ns.ViewAs
	if not K or (K.Preview and K.Preview()) or (V and V.Previewing and V.Previewing())
		or (V and V.Available and V.Available() and V.Role and V.Role() ~= "my") then return false end
	return (type(K.IsKing) == "function" and K.IsKing() == true) or ns.IsHighCouncillor(ns.me) == true
end
function Nominees.MainPreview()
	local K = ns.King
	return K and K.Preview and K.Preview() == true and ns.Workshop and ns.Workshop.Visible and ns.Workshop.Visible() == true or false
end
function Nominees.MainNames() return Nominees.MainEditor() or Nominees.MainPreview() end

local function MainStore(make)
	local preview = Nominees.MainPreview()
	local db = preview and ns.db or (Nominees.MainEditor() and ns.rdb) or nil
	if not db then return nil end
	local field = preview and "previewMainNominees" or "mainNominees"
	local s = db[field]
	if type(s) ~= "table" or type(s.list) ~= "table" then
		if not make then return nil end
		s = { rev = 0, list = {} }; db[field] = s
	end
	return s, preview
end
local function MainEntries(s)
	local out, seen = {}, {}
	for _, e in ipairs(s and s.list or {}) do
		local name = type(e) == "table" and e.r == "c" and Person(e.n) or nil
		if name and not seen[name:lower()] and #out < Nominees.MAX_CENTURIONS then
			seen[name:lower()] = true; out[#out + 1] = { role = "centurion", name = name }
		end
	end
	return out
end

-- Whom the Throne shows them to as the King's centurions, and /oly nominees names nobody for: the
-- King, a councillor, and the author's preview of the King (King.Preview).
local function KingsSide()
	local K = ns.King
	if type(K) == "table" and type(K.Preview) == "function" and K.Preview() == true then return true end
	return Nominees.MainEditor()
end

-- Legacy API name; only the manually appointed names, in appointment order.
function Nominees.KingsCenturions()
	local out = {}
	local l = Nominees.ListOf(Nominees.MainGuild())
	for _, e in ipairs(l and l.entries or {}) do if e.role == "centurion" then out[#out + 1] = e.name end end
	return out
end
Nominees.KingsLegates = Nominees.KingsCenturions

-- The list that counts for `guild` here: his own on the guild master's client; else the one
-- heard from its master. Silence is not revocation. Main appointments have the same getter, but
-- their actual pinned King/signed council issuer is checked independently of the census.
local function ListOf(guild)
	if type(guild) ~= "string" or guild == "" then return nil end
	if IsMain(guild) then
		local s, preview = MainStore(false)
		if not s and ns.rdb and type(ns.rdb.mainNominees) == "table" then s = ns.rdb.mainNominees end
		local by = s and (s.by or (Nominees.MainEditor() and ns.me))
		if s and Revision(s.rev) and (preview or (type(by) == "string" and Proven(by, guild))) then
			local entries, set = MainEntries(s), {}
			for _, e in ipairs(entries) do set[e.name:lower()] = e end
			return { guild = guild, by = by or ns.me, rev = s.rev, at = s.at, entries = entries, set = set, own = true, main = true }
		end
	end
	local master, mine = Nominees.IsMaster()
	if master and mine == guild then
		local entries = OwnEntries(Saved(false))
		local set = {}
		for _, e in ipairs(entries) do set[e.name:lower()] = e end
		return { guild = guild, by = ns.me, entries = entries, set = set, own = true }
	end
	local key = guild:lower()
	local l = Lists()[key]
	if not l then return nil end
	if Deposed(l) then
		-- A positively observed issuer change is a revocation, not a temporary hidden view. Drop
		-- the accepted snapshot too, or an older master returning could resurrect his old list.
		lists[key] = nil; Nominees.Keep(key, nil); Bump()
		local notices = ns.db and ns.db.legateNotices
		local notice = type(notices) == "table" and ns.me and notices[ns.FullName(ns.me):lower()]
		if type(notice) == "table" and notice.guild == guild then notice.active = false end
		return nil
	end
	if l.main and not Proven(l.by, guild) then return nil end
	return l
end
Nominees.ListOf = ListOf

-- Whom `guild`'s master named `who` (Borders.lua): "centurion", or "correspondent" and its
-- department; nil for nobody. A lookup.
function Nominees.RoleOf(who, guild)
	if type(who) ~= "string" or who == "" then return nil end
	local l = ListOf(guild)
	local e = l and l.set[ns.FullName(who):lower()]
	if not e then return nil end
	return e.role, e.dept and DeptName(e.dept)
end

-- Operational duties require our own live guild roster, not the census used for a border.
-- Recheck the list's master on every use so revocation does not wait for the pruning timer.
function Nominees.IsCorrespondent(who, guild, dept)
	if type(who) ~= "string" or type(dept) ~= "string" or not ns.IsMember() then return false end
	local mine = GetGuildInfo and GetGuildInfo("player")
	local R = ns.Roster
	if type(guild) ~= "string" or guild ~= mine or not ns.IsFederation(guild)
		or not R or R.complete ~= true or R.guild ~= guild or R.group ~= ns.group or R.faction ~= ns.faction
		or type(R.byName) ~= "table" or type(R.RankOf) ~= "function" or type(R.snapshotAt) ~= "number"
		or type(R.generation) ~= "number" or R.generation < 1 then return false end
	local age = ns.Now() - R.snapshotAt
	if age < 0 or age > (R.AUTHORITY_FRESH or 600) then return false end
	local full = ns.FullName(who)
	if R.RankOf(full) == nil then return false end
	local list = ListOf(guild)
	if not list or type(list.by) ~= "string" or R.RankOf(ns.FullName(list.by)) ~= 0 then return false end
	local role, department = Nominees.RoleOf(full, guild)
	return role == "correspondent" and department == DeptName(dept)
end

function Nominees.Correspondent(guild, dept)
	local list = ListOf(guild)
	for _, entry in ipairs(list and list.entries or {}) do
		if Nominees.IsCorrespondent(entry.name, guild, dept) then return entry.name end
	end
	return nil
end

function Nominees.OwnDepartment(who)
	local guild = GetGuildInfo and GetGuildInfo("player")
	for _, dept in ipairs(Nominees.Departments()) do
		if Nominees.IsCorrespondent(who or ns.me, guild, dept) then return dept, guild end
	end
	return nil
end

function Nominees.GuildAccess()
	local V, guild = ns.ViewAs, GetGuildInfo and GetGuildInfo("player")
	if V and V.Available and V.Available() and V.Role and V.Role() ~= "my" then
		return V.Role() == "gm" or V.Role() == "correspondent", guild
	end
	local master, mine = Nominees.IsMaster()
	if master then return true, mine end
	local dept = Nominees.OwnDepartment()
	return dept ~= nil, guild
end

-- Its parts, each one addon message: NM~1~<guild>~<rev>~<i>~<n>~<entries>.
local function Wire(name)
	return ns.RealmOf(name) == ns.realm and ns.ShortName(name) or name
end
-- The old label is the existing NM wire key; older clients must still read this department.
local function WireDept(dept) return DeptName(dept) == "Department of Heraldry" and "Department of Heritage" or dept end
function Nominees.Parts(guild, rev, entries)
	rev = Revision(rev)
	if not GuildName(guild) or not rev then return {} end
	local head = ("NM~%s~%s~%d~"):format(Nominees.WIRE, guild, rev)
	local countText = tostring(Nominees.MAX_PARTS)
	local room = Nominees.PART - #head - #(countText .. "~" .. countText .. "~")
	local bodies, body = {}, ""
	for i, e in ipairs(entries) do
		if i > Nominees.MAX then break end
		local text = e.role == "centurion" and ("c=" .. Wire(e.name)) or ("d=" .. WireDept(e.dept) .. "=" .. Wire(e.name))
		if body ~= "" and #body + 1 + #text > room then
			bodies[#bodies + 1], body = body, ""
		end
		body = body == "" and text or (body .. ";" .. text)
	end
	if body ~= "" or #bodies == 0 then bodies[#bodies + 1] = body end
	local out = {}
	for i, b in ipairs(bodies) do out[i] = ("%s%d~%d~%s"):format(head, i, #bodies, b) end
	return out
end

-- His list goes out (force: now; else once EVERY), from the guild master's client alone. Nobody
-- named yet, nothing sent; named and then all removed, the empty list (everyone drops it).
function Nominees.Send(force)
	if not RealMaster() then return false end -- (the author's view sends nothing)
	local s = Saved(false)
	if not s then return false end
	local now = ns.Now()
	if not force and now - lastSent < Nominees.EVERY then return false end
	local entries = OwnEntries(s)
	if #entries == 0 and not sentOnce then return false end
	lastSent, sentOnce = now, true
	for i, part in ipairs(Nominees.Parts(s.guild, tonumber(s.rev) or now, entries)) do
		ns.Comm.Send("CHANNEL", part, "nominees" .. i)
	end
	return true
end

local function SendSoon()
	if sendPending then return end
	sendPending = true
	ns.After(Nominees.SEND_AFTER, "nominees send", function()
		sendPending = false
		Nominees.Send(true)
	end)
end

local function Changed()
	Bump()
	ns.Fire("DATA_CHANGED")
end

-- Quiet, local duty notice for this character's accepted appointment. Never opens a window or
-- invites anyone. Missing/incomplete roster proof waits for the existing minute tick. One current
-- stamp per character, 50 characters at most; heartbeat/reload cannot repeat the same revision.
Nominees.NOTICES_MAX = 50
Nominees.NOTICE_RULE = 2 -- the High Council's role-badge change, shown once to existing appointments too
function Nominees.AppointmentNotice(l)
	local V, K = ns.ViewAs, ns.King
	if Nominees.DevView() or (K and K.Preview and K.Preview()) or (V and V.Previewing and V.Previewing())
		or (V and V.Available and V.Available() and V.Role and V.Role() ~= "my") then return false end
	if type(l) ~= "table" or not ns.db or not ns.me or not Revision(l.rev) then return false end
	local guild = GetGuildInfo("player")
	if guild ~= l.guild or not ns.IsMember() or not Proven(l.by, guild) then return false end
	local key = ns.FullName(ns.me):lower()
	local all = ns.db.legateNotices
	local old = type(all) == "table" and all[key] or nil
	local e = l.set and l.set[key]
	if not e or (e.role ~= "centurion" and e.role ~= "correspondent") then
		if type(old) == "table" and old.guild == guild then old.active = false end
		return false
	end
	-- A different player's appointment or an authorized relay of the same roster is not a new
	-- appointment of us. An office/department change, an actual removal/reappointment, or this
	-- notice policy's first run re-arms it; ordinary heartbeats and relays do not.
	if type(old) == "table" and old.guild == guild and old.active == true and old.role == e.role
		and old.dept == e.dept and old.rule == Nominees.NOTICE_RULE then return false end
	local R = ns.Roster
	if not R or not R.Fresh or not R.Fresh() or not R.RankOf
		or R.RankOf(ns.FullName(ns.me)) == nil or (ns.ChatLocked and ns.ChatLocked())
		or (ns.Quiet and ns.Quiet()) then return false end
	if type(all) ~= "table" then all = {}; ns.db.legateNotices = all end
	all[key] = { guild = guild, by = l.by, rev = l.rev, at = ns.Now(), active = true,
		role = e.role, dept = e.dept, rule = Nominees.NOTICE_RULE }
	local keys = {}
	for name, x in pairs(all) do keys[#keys + 1] = { name = name, at = type(x) == "table" and tonumber(x.at) or 0 } end
	table.sort(keys, function(a, b)
		if (a.name == key) ~= (b.name == key) then return a.name == key end
		return (a.at or 0) > (b.at or 0)
	end)
	for i = Nominees.NOTICES_MAX + 1, #keys do all[keys[i].name] = nil end
	local by = ns.DisplayName(l.by) or l.by
	if e.role == "centurion" then
		ns.Print(L.NOMINEES_LEGATE_APPOINTED:format(by, guild, L.NOMINEES_LEGATE_DUTY, L.NOMINEES_BADGE_DECISION))
	else
		ns.Print(L.NOMINEES_CORRESPONDENT_APPOINTED:format(by, e.dept or "?", guild, L.NOMINEES_CORRESPONDENT_DUTY, L.NOMINEES_BADGE_DECISION))
	end
	return true
end

-- The guild master names someone: role "centurion", or "correspondent" with a department.
-- Refused, with its reason, past the caps, outside his roster, twice, or for himself.
function Nominees.Name(role, input, dept)
	if role == "legate" or role == "legatus" or role == "legado" then role = "centurion" end
	local s = Saved(false)
	local master, guild = Nominees.IsMaster()
	if not master then return false, ns.Print(L.NOMINEES_ONLY_MASTER) end
	local raw = Trim(input)
	if raw == "" and UnitIsPlayer and UnitIsPlayer("target") then raw = ns.UnitFullName("target") or "" end
	local name = Person(raw)
	if not name then return false, ns.Print(L.NOMINEES_WHO) end
	-- His own guild's members alone, as his roster has them (the server's), in its spelling.
	local member = ns.Roster.guild == guild and RosterName(name, not ns.RealmOf(Trim(ns.Normal(raw)))) or nil
	if name:lower() == tostring(ns.me):lower() or (member and member:lower() == tostring(ns.me):lower()) then
		return false, ns.Print(L.NOMINEES_SELF)
	end
	if not member then return false, ns.Print(L.NOMINEES_NOT_MEMBER:format(ns.DisplayName(name))) end
	name = member
	local entries = OwnEntries(s)
	for _, e in ipairs(entries) do
		if e.name:lower() == name:lower() then
			return false, ns.Print(L.NOMINEES_ALREADY:format(ns.DisplayName(name), Nominees.RoleLabel(e.role, e.dept)))
		end
	end
	local entry
	if role == "centurion" then
		local c = 0
		for _, e in ipairs(entries) do if e.role == "centurion" then c = c + 1 end end
		if c >= Nominees.MAX_CENTURIONS then return false, ns.Print(L.NOMINEES_FULL:format(Nominees.MAX_CENTURIONS)) end
		entry = { r = "c", n = name }
	elseif role == "correspondent" then
		local d = IsDept(dept)
		if not d then return false, ns.Print(L.NOMINEES_NO_DEPT:format(tostring(dept or "?"))) end
		for _, e in ipairs(entries) do
			if e.role == "correspondent" and e.dept:lower() == d:lower() then
				return false, ns.Print(L.NOMINEES_DEPT_TAKEN:format(d, ns.DisplayName(e.name)))
			end
		end
		entry = { r = "d", d = d, n = name }
	else
		return false
	end
	s = Saved(true)
	-- (A correspondent whose department is gone gives his place up to the new one.)
	local _, stale = OwnEntries(s)
	if entry.r == "d" and #stale > 0 then
		local kept = {}
		for _, e in ipairs(s.list) do
			if not (e.r == "d" and not IsDept(e.d)) then kept[#kept + 1] = e end
		end
		s.list = kept
	end
	s.list[#s.list + 1] = entry
	s.rev = math.max(ns.Now(), (tonumber(s.rev) or 0) + 1)
	ns.Print(L.NOMINEES_ADDED:format(ns.DisplayName(name), Nominees.RoleLabel(role, entry.d)))
	ns.Log("nominees: %s named %s (%s)", tostring(ns.me), name, role .. (entry.d and (" " .. entry.d) or ""))
	SendSoon()
	Changed()
	return true
end

-- The guild master removes one of his own (by name; typed without a realm, the one he named of
-- that name on another realm too, when only one).
function Nominees.Remove(input)
	local s = Saved(false)
	if not s then return false, ns.Print(L.NOMINEES_ONLY_MASTER) end
	local raw = Trim(input)
	local name = Person(raw)
	local at, short, others = nil, name and ns.ShortName(name):lower(), {}
	for i, e in ipairs(s.list) do
		if type(e) == "table" and type(e.n) == "string" and name then
			if e.n:lower() == name:lower() then at = i break end
			if ns.ShortName(e.n):lower() == short then others[#others + 1] = i end
		end
	end
	if not at and #others == 1 and not ns.RealmOf(Trim(ns.Normal(raw))) then at = others[1] end
	local e = at and s.list[at]
	if not e then return false, ns.Print(L.NOMINEES_NOT_NAMED:format(ns.DisplayName(name) or raw)) end
	table.remove(s.list, at)
	s.rev = math.max(ns.Now(), (tonumber(s.rev) or 0) + 1)
	local dept = e.r == "d" and tostring(e.d or "?") or nil
	ns.Print(L.NOMINEES_REMOVED:format(ns.DisplayName(e.n), Nominees.RoleLabel(dept and "correspondent" or "centurion", dept)))
	ns.Log("nominees: %s removed %s", tostring(ns.me), e.n)
	SendSoon()
	Changed()
	return true
end

-- Kept as an inert compatibility entry point: installing this build never retires manual data.
function Nominees.Retire() return false end

function Nominees.SendMain(force)
	if not Nominees.MainEditor() then return false end
	local s = MainStore(false)
	local rev = s and Revision(s.rev)
	if not rev or rev <= 0 or not Proven(s.by or ns.me, Nominees.MainGuild()) then return false end
	local now = ns.Now()
	if not force and now - math.max(lastMainSent, mainHeardAt) < Nominees.EVERY then return false end
	local entries = MainEntries(s)
	-- An explicit empty snapshot is a revocation too; keep repeating it for late clients.
	lastMainSent = now
	for i, part in ipairs(Nominees.Parts(Nominees.MainGuild(), rev, entries)) do
		ns.Comm.Send("CHANNEL", part, "mainnominees" .. i)
	end
	return true
end
local function SendMainSoon()
	if mainSendPending then return end
	mainSendPending = true
	ns.After(Nominees.SEND_AFTER, "main nominees send", function()
		mainSendPending = false; Nominees.SendMain(true)
	end)
end
function Nominees.NameMain(input)
	if not Nominees.MainNames() then return false, ns.Print(L.NOMINEES_ONLY_MAIN) end
	local guild, raw = Nominees.MainGuild(), Trim(input)
	if raw == "" and UnitIsPlayer and UnitIsPlayer("target") then raw = ns.UnitFullName("target") or "" end
	local name = Person(raw)
	if not name then return false, ns.Print(L.NOMINEES_WHO) end
	if IsMain(ns.Roster.guild) then
		local member = RosterName(name, not ns.RealmOf(Trim(ns.Normal(raw))))
		if not member then return false, ns.Print(L.NOMINEES_MAIN_NOT_MEMBER:format(ns.DisplayName(name), guild)) end
		name = member
	end
	if name:lower() == tostring(ns.me):lower() then return false, ns.Print(L.NOMINEES_MAIN_SELF) end
	local entries = MainEntries(MainStore(false))
	for _, e in ipairs(entries) do
		if e.name:lower() == name:lower() then return false, ns.Print(L.NOMINEES_MAIN_ALREADY:format(ns.DisplayName(name), guild)) end
	end
	if #entries >= Nominees.MAX_CENTURIONS then return false, ns.Print(L.NOMINEES_MAIN_FULL:format(guild, Nominees.MAX_CENTURIONS)) end
	local s, preview = MainStore(true)
	local kept = {}
	for _, e in ipairs(entries) do kept[#kept + 1] = { r = "c", n = e.name } end
	kept[#kept + 1] = { r = "c", n = name }
	s.list, s.by, s.at = kept, ns.me, ns.Now()
	s.rev = math.max(ns.Now(), (Revision(s.rev) or 0) + 1)
	ns.Print(L.NOMINEES_MAIN_ADDED:format(ns.DisplayName(name), guild))
	if not preview then SendMainSoon() end
	Changed()
	return true
end
function Nominees.RemoveMain(input)
	if not Nominees.MainNames() then return false, ns.Print(L.NOMINEES_ONLY_MAIN) end
	local s, preview = MainStore(false)
	local raw, name = Trim(input), Person(input)
	local entries, at, others = MainEntries(s), nil, {}
	for i, e in ipairs(entries) do
		if name and e.name:lower() == name:lower() then at = i; break end
		if name and ns.ShortName(e.name):lower() == ns.ShortName(name):lower() then others[#others + 1] = i end
	end
	if not at and #others == 1 and not ns.RealmOf(Trim(ns.Normal(raw))) then at = others[1] end
	if not at then return false, ns.Print(L.NOMINEES_MAIN_NOT_NAMED:format(ns.DisplayName(name) or raw, Nominees.MainGuild())) end
	local gone, kept = entries[at].name, {}
	for i, e in ipairs(entries) do if i ~= at then kept[#kept + 1] = { r = "c", n = e.name } end end
	s.list, s.by, s.at = kept, ns.me, ns.Now()
	s.rev = math.max(ns.Now(), (Revision(s.rev) or 0) + 1)
	ns.Print(L.NOMINEES_MAIN_REMOVED:format(ns.DisplayName(gone), Nominees.MainGuild()))
	if not preview then SendMainSoon() end
	Changed()
	return true
end

---------------------------------------------------------------------------
-- Heard: a guild master's list
---------------------------------------------------------------------------

-- A list's entries from its parts, its caps held (the first ones kept), or nil when it can't be one.
local function Read(parts, n, realm, main)
	local entries, set, c, depts = {}, {}, 0, {}
	for i = 1, n do
		for entry in tostring(parts[i] or ""):gmatch("[^;]+") do
			local kind, a, b = entry:match("^(%a)=([^=]*)=?([^=]*)$")
			local e
			if kind == "c" and b == "" and c < Nominees.MAX_CENTURIONS then
				local name = Person(a, realm)
				if name and not set[name:lower()] then
					c = c + 1
					e = { role = "centurion", name = name }
				end
			elseif kind == "d" and b ~= "" and not main then -- (none for the King's guild: 1.1.5)
				local dept, name = DeptName(a), Person(b, realm)
				local count = 0
				for _ in pairs(depts) do count = count + 1 end
				if dept and name and not set[name:lower()] and not depts[dept:lower()] and count < Nominees.MAX_DEPTS then
					depts[dept:lower()] = true
					e = { role = "correspondent", dept = dept, name = name }
				end
			end
			if e then
				entries[#entries + 1] = e
				set[e.name:lower()] = e
			end
		end
	end
	return entries, set
end

-- What a list names, as text, to tell a new one from a repeat.
local function Signature(l)
	local out = { l.by:lower() }
	for _, e in ipairs(l.entries) do out[#out + 1] = (e.dept or "") .. "=" .. e.name:lower() end
	return table.concat(out, ";")
end

-- A whole list from a proven guild master: kept (a repeat refreshes it), or dropped when it names
-- nobody. This client is told when it is named, or no longer.
local function Take(sender, guild, rev, entries, set)
	local key = guild:lower()
	local old = Lists()[key]
	-- (An older one, late. 1.2.4, the review: only while the one held is still being repeated, as when it
	-- lasted 6 hours: a master on another computer, its saved copy of his list older, is his word again,
	-- not refused for the 30 days a list is now kept.)
	if old and old.by == sender and rev < (old.rev or 0) and ns.Now() - old.at <= Nominees.REV_QUIET then return end
	local mine = GetGuildInfo("player")
	local was = old and old.set[tostring(ns.me):lower()]
	local l = { guild = guild, by = sender, rev = rev, at = ns.Now(), entries = entries, set = set }
	if #entries == 0 then
		lists[key] = nil
	else
		lists[key] = l
	end
	Nominees.Keep(key, #entries > 0 and l or nil)
	local noticed = Nominees.AppointmentNotice(l)
	local now = #entries > 0 and set[tostring(ns.me):lower()] or nil
	if mine and guild == mine then
		if now and not noticed and not (was and was.role == now.role and was.dept == now.dept) then
			ns.Print(L.NOMINEES_YOU:format(ns.DisplayName(sender) or "?", Nominees.RoleLabel(now.role, now.dept), guild))
		elseif was and not now then
			ns.Print(L.NOMINEES_NO_LONGER:format(Nominees.RoleLabel(was.role, was.dept), guild))
		end
	end
	if not old or #entries == 0 or Signature(old) ~= Signature(l) then
		ns.Log("nominees: <%s>'s list from %s, %d named", guild, sender, #entries)
		Changed()
	end
end

-- An explicit empty main snapshot is retained too, so an older appointment cannot resurrect it.
local function TakeMain(sender, guild, rev, entries, set)
	local key = guild:lower()
	local old = ListOf(guild) or Lists()[key]
	if old and rev < (Revision(old.rev) or 0) then
		if Nominees.MainEditor() then SendMainSoon() end
		return
	end
	local l = { guild = guild, by = sender, rev = rev, at = ns.Now(), entries = entries, set = set, main = true }
	if old and rev == old.rev and Signature(old) ~= Signature(l) then return end
	local changed = not old or Signature(old) ~= Signature(l)
	lists[key] = l
	Nominees.Keep(key, l)
	Nominees.AppointmentNotice(l)
	if Nominees.MainEditor() then
		local saved = {}
		for _, e in ipairs(entries) do saved[#saved + 1] = { r = "c", n = e.name } end
		ns.rdb.mainNominees = { rev = rev, by = sender, at = l.at, list = saved }
		mainHeardAt = ns.Now()
	end
	if changed then Changed() end
end

-- A part of a list, from the channel: only from that guild's master (Proven), put together with
-- the rest of its parts.
function Nominees.Handle(dist, sender, text)
	if dist ~= "CHANNEL" or type(sender) ~= "string" or type(text) ~= "string" or #text > 255 then return end
	local wire, guild, rev, i, n, body = text:match("^NM~(%d+)~([^~]*)~(%d+)~(%d+)~(%d+)~([^~]*)$")
	if wire ~= Nominees.WIRE then return end -- (another version's: not ours to read)
	guild, rev, i, n = GuildName(guild), Revision(rev), tonumber(i), tonumber(n)
	if not guild or not rev or not i or not n or i < 1 or n < 1 or i > n or n > Nominees.MAX_PARTS then return end
	sender = ns.FullName(sender)
	if not Proven(sender, guild) then
		return ns.Log("nominees: <%s>'s list from %s refused: not its guild master here", guild, sender)
	end
	local now = ns.Now()
	local p = pending[sender]
	if not p or p.guild ~= guild or p.rev ~= rev or p.n ~= n or now - p.t > Nominees.PART_WAIT then
		p = { guild = guild, rev = rev, n = n, parts = {}, got = 0, t = now }
		pending[sender] = p
	end
	if not p.parts[i] then
		p.parts[i], p.got = body, p.got + 1
	end
	if p.got < n then return end
	pending[sender] = nil
	local main = IsMain(guild)
	local entries, set = Read(p.parts, n, ns.RealmOf(sender), main)
	if main then return TakeMain(sender, guild, rev, entries, set) end
	Take(sender, guild, rev, entries, set)
end
ns.Comm.Handle("NM", function(...) Nominees.Handle(...) end)

-- (1.2.4) A list heard, as the saved variables keep it (ns.rdb.nomineesHeard, by guild in lower case:
-- { g = guild, by = its master, rev, at = when last heard, main, body = its entries as a part carries
-- them, each name with its realm }), or none (l nil). SAVED_MAX at most: the one heard longest ago goes,
-- never our own guild's.
function Nominees.Keep(key, l)
	local r = ns.rdb
	if type(r) ~= "table" or type(key) ~= "string" then return end
	local store = r.nomineesHeard
	if not l then
		if type(store) == "table" then store[key] = nil end
		return
	end
	if type(store) ~= "table" then store = {}; r.nomineesHeard = store end
	local body = {}
	for _, e in ipairs(l.entries) do
		body[#body + 1] = e.role == "centurion" and ("c=" .. e.name) or ("d=" .. tostring(WireDept(e.dept)) .. "=" .. e.name)
	end
	local new = store[key] == nil
	store[key] = { g = l.guild, by = l.by, rev = l.rev, at = l.at, main = l.main and true or nil, body = table.concat(body, ";") }
	if not new then return end
	-- (The review: our own guild's list is never the one let go, for its members' Guild tab and bronze.)
	local mine = GetGuildInfo("player")
	mine = type(mine) == "string" and mine:lower() or nil
	local n, oldest, oldAt = 0, nil, nil
	for k, s in pairs(store) do
		n = n + 1
		local at = type(s) == "table" and tonumber(s.at) or -math.huge
		if k ~= mine and (not oldAt or at < oldAt) then oldest, oldAt = k, at end
	end
	if n > Nominees.SAVED_MAX and oldest then store[oldest], lists[oldest] = nil, nil end
end

-- (1.2.4) The lists heard before this login or /reload, put back from the saved variables, each one
-- read again as a list that came (Read: the same caps, names and departments), regardless of age and
-- its guild still an Olympus guild; anything else there is let go. Each was taken from its guild's master
-- when it came; Nominees.Prune drops one whose master the census or our roster deposes, as any list.
Restore = function()
	restoredFrom = ns.rdb
	local store = type(ns.rdb) == "table" and ns.rdb.nomineesHeard or nil
	if type(store) ~= "table" then return end
	local now, any = ns.Now(), false
	for key, s in pairs(store) do
		local l
		if type(key) == "string" and type(s) == "table" and type(s.g) == "string" and type(s.by) == "string"
			and type(s.body) == "string" and #s.body <= Nominees.MAX_PARTS * Nominees.PART and not lists[key] then
			local guild, by, rev, at = GuildName(s.g), Person(s.by), Revision(s.rev), tonumber(s.at)
			local main = guild ~= nil and IsMain(guild)
			if guild and guild:lower() == key and by and rev and at and at == at and at >= 0 and at <= now + 60
				and (s.main == true) == main then
				local entries, set = Read({ s.body }, 1, ns.RealmOf(by), main)
				if #entries > 0 or main then
					l = { guild = guild, by = by, rev = rev, at = at, entries = entries, set = set, main = main or nil }
				end
			end
		end
		if l then
			lists[key], any = l, true
		elseif not lists[key] then
			store[key] = nil
		end
	end
	-- The live and restored cache share the same finite capacity; keep our own guild first.
	local keys, mine = {}, GetGuildInfo("player")
	mine = type(mine) == "string" and mine:lower() or nil
	for key, l in pairs(lists) do keys[#keys + 1] = { key = key, at = l.at or 0 } end
	table.sort(keys, function(a, b)
		if (a.key == mine) ~= (b.key == mine) then return a.key == mine end
		if a.at ~= b.at then return a.at > b.at end
		return a.key < b.key
	end)
	for i = Nominees.SAVED_MAX + 1, #keys do lists[keys[i].key], store[keys[i].key] = nil, nil end
	if any then Bump() end
end

-- What Deposed reads for a list: our roster for our own guild; another guild's census row as it
-- stands (its time and votes, as Borders.Changed reads them). Asked again only when these change
-- (DATA_CHANGED comes with every census report heard).
local function DeposedInputs(l)
	if l.main then
		local c = ns.rdb and ns.rdb.council
		return c, type(c) == "table" and c.names or nil, ns.KingCharacter()
	end
	local mine = GetGuildInfo("player")
	if mine and l.guild:lower() == mine:lower() then return ns.Roster.byName, ns.Roster.lastStats, mine end
	local guilds = ns.rdb and ns.rdb.guilds
	local g = type(guilds) == "table" and guilds[l.guild] or nil
	return g, type(g) == "table" and g.t or nil, type(g) == "table" and g.vouch or nil
end

-- Lists whose master is no longer that guild's master, and incomplete parts
-- left waiting: dropped. Returns whether a list went.
function Nominees.Prune()
	local now, gone = ns.Now(), false
	for key, l in pairs(Lists()) do
		local a, b, c = DeposedInputs(l)
		local fresh = l.ia ~= a or l.ib ~= b or l.ic ~= c or not l.asked
		if fresh then l.ia, l.ib, l.ic, l.asked = a, b, c, true end
		if fresh and Deposed(l) then
			lists[key], gone = nil, true
			Nominees.Keep(key, nil)
			ns.Log("nominees: <%s>'s list dropped: %s is no longer its guild master", l.guild, l.by)
		end
	end
	for sender, p in pairs(pending) do
		if now - p.t > Nominees.PART_WAIT then pending[sender] = nil end
	end
	if gone then Bump() end
	return gone
end

---------------------------------------------------------------------------
-- The pages: a guild master's Guild tab, the King's guild's centurions on the Throne (King.lua), and
-- the command
---------------------------------------------------------------------------

-- The guild master's own list, as his Guild tab shows it: { entries, stale }; nil for anyone else
-- (the Guild tab is his alone).
function Nominees.Ours()
	if not Nominees.IsMaster() then return nil end
	local entries, stale = OwnEntries(Saved(false))
	return { entries = entries, stale = stale }
end

-- How many he has named.
function Nominees.Count()
	local o = Nominees.Ours()
	return o and #o.entries or 0
end

-- The name box: a centurion or a department's correspondent of his guild.
function Nominees.Prompt(role, dept, main)
	if main then
		if not Nominees.MainNames() then return ns.Print(L.NOMINEES_ONLY_MAIN) end
		return ns.ShowDialog("OLYMPUS_NOMINEE", L.NOMINEE_ROLE_CENTURION, Nominees.MainGuild(), { role = "centurion", main = true })
	end
	local master, guild = Nominees.IsMaster()
	if not master then return ns.Print(L.NOMINEES_ONLY_MASTER) end
	return ns.ShowDialog("OLYMPUS_NOMINEE", Nominees.RoleLabel(role, dept), guild, { role = role, dept = dept })
end
-- Asked before a title is taken back (the box's data: his own's name).
function Nominees.AskRemove(e, main)
	if type(e) ~= "table" then return nil end
	if main then
		if not Nominees.MainNames() then return nil end
		return ns.ShowDialog("OLYMPUS_NOMINEE_REMOVE", ns.DisplayName(e.name), L.NOMINEES_MAIN_ROLE:format(Nominees.MainGuild()), { name = e.name, main = true })
	end
	if not Nominees.IsMaster() then return nil end
	return ns.ShowDialog("OLYMPUS_NOMINEE_REMOVE", ns.DisplayName(e.name), Nominees.RoleLabel(e.role, e.dept), e.name)
end
local function Taken(data, text)
	data = type(data) == "table" and data or {}
	if data.main then return Nominees.NameMain(text) end
	return Nominees.Name(data.role, text, data.dept)
end
local function TakenBack(data)
	if type(data) == "table" and data.main then return Nominees.RemoveMain(data.name) end
	if type(data) ~= "string" then return false end
	return Nominees.Remove(data)
end

-- The Throne's look (King.lua's Line, Para: dark ink on the parchment), as the Hands page's.
local function Ink() local K = ns.King return K.Line, K.INK, K.TITLE, K.Para end

-- A named one's line: a click takes the title back (asked first), when this client may.
local function Row(e, text, editable, roster, main)
	local Line, INK = Ink()
	local name = ns.DisplayName(e.name)
	return Line(text or name, INK, {
		key = name, indent = 1,
		right = roster and ns.Roster.RankOf(e.name) == nil and ns.Views.Grey(L.NOMINEES_NOT_IN_ROSTER) or nil,
		onClick = editable and function() Nominees.AskRemove(e, main) end or nil,
		tooltip = function(tt)
			tt:AddLine(name, 1, 0.82, 0)
			tt:AddLine(Nominees.RoleLabel(e.role, e.dept), 1, 1, 1, true)
			if e.role == "centurion" and L.NOMINEES_LEGATE_DUTY then tt:AddLine(L.NOMINEES_LEGATE_DUTY, 1, 1, 1, true) end
			local duty = e.role == "correspondent" and Nominees.DepartmentHelp(e.dept)
			if duty then tt:AddLine(duty, 1, 1, 1, true) end
			if editable then tt:AddLine(L.NOMINEES_CLICK_REMOVE, 0.6, 0.6, 0.6, true) end
		end,
	})
end

-- "+ Name a centurion (your target, or type a name)", its count; greyed when full (its click says why).
local function AddLine(count, main)
	local Line, _, TITLE = Ink()
	local full = count >= Nominees.MAX_CENTURIONS
	local add = "+ " .. L.NOMINEES_ADD_CENTURION
	local function Full() return main and L.NOMINEES_MAIN_FULL:format(Nominees.MainGuild(), Nominees.MAX_CENTURIONS) or L.NOMINEES_FULL:format(Nominees.MAX_CENTURIONS) end
	return Line(full and ns.Views.Grey(add) or add, TITLE, {
		right = ("%d/%d"):format(count, Nominees.MAX_CENTURIONS),
		onClick = function()
			if full then return ns.Print(Full()) end
			Nominees.Prompt("centurion", nil, main)
		end,
		tooltip = function(tt)
			tt:AddLine(L.NOMINEES_ADD_CENTURION, 1, 0.82, 0)
			tt:AddLine(full and Full() or L.NOMINEES_CLICK_NAME, 1, 1, 1, true)
			if L.NOMINEES_LEGATE_DUTY then tt:AddLine(L.NOMINEES_LEGATE_DUTY, 1, 1, 1, true) end
		end,
	})
end

-- The guild master's section, as the King's Hands page (King.lua's HandsLines): a title, a
-- one-line hint, "+ Name a centurion (your target, or type a name)", his centurions (a click takes
-- the title back, asked first), then the correspondents' departments, one line each (the role
-- picker: a click names that department's correspondent, or takes the title back), and the note
-- on how the army learns his list. Nothing for anyone but him.
function Nominees.PageLines(lines)
	local o = Nominees.Ours()
	if not o then return lines end
	local Line, INK, TITLE, Para = Ink()
	lines[#lines + 1] = Line(L.NOMINEES_TITLE, TITLE)
	Para(lines, L.NOMINEES_HINT, INK, { gapAfter = true })
	-- The centurions.
	local centurions = {}
	for _, e in ipairs(o.entries) do if e.role == "centurion" then centurions[#centurions + 1] = e end end
	lines[#lines + 1] = AddLine(#centurions)
	for _, e in ipairs(centurions) do lines[#lines + 1] = Row(e, nil, true, true) end
	if #centurions == 0 then lines[#lines + 1] = Line(L.NOMINEES_NONE, INK, { indent = 1 }) end
	lines[#lines].gapAfter = true
	-- The correspondents: a line per department, its correspondent or a click to name one.
	local depts = Nominees.Departments()
	local byDept, named = {}, 0
	for _, e in ipairs(o.entries) do
		if e.role == "correspondent" then
			byDept[e.dept:lower()] = e
			named = named + 1
		end
	end
	lines[#lines + 1] = Line(L.NOMINEES_CORRESPONDENTS, TITLE, { right = ("%d/%d"):format(named, #depts) })
	for _, d in ipairs(depts) do
		local e = byDept[d:lower()]
		if e then
			lines[#lines + 1] = Row(e, d .. ": " .. ns.DisplayName(e.name), true, true)
		else
			lines[#lines + 1] = Line(d .. ": " .. L.NOMINEES_ADD_CORRESPONDENT, INK, { indent = 1,
				onClick = function() Nominees.Prompt("correspondent", d) end,
				tooltip = function(tt)
					tt:AddLine(Nominees.RoleLabel("correspondent", d), 1, 0.82, 0)
					local duty = Nominees.DepartmentHelp(d)
					if duty then tt:AddLine(duty, 1, 1, 1, true) end
					tt:AddLine(L.NOMINEES_CLICK_NAME, 1, 1, 1, true)
				end })
		end
	end
	-- (His own whose department the council's list no longer has: they count for nothing, sent to nobody.)
	for _, e in ipairs(o.stale) do
		local row = Row(e, e.dept .. ": " .. ns.DisplayName(e.name), true, true)
		row.right = ns.Views.Grey(L.NOMINEES_DEPT_GONE)
		lines[#lines + 1] = row
	end
	if #depts == 0 then lines[#lines + 1] = Line(L.NOMINEES_NO_DEPTS, INK, { indent = 1 }) end
	lines[#lines].gapAfter = true
	return Para(lines, L.NOMINEES_NOTE, INK)
end

-- A guild master's Guild tab (1.1.5): the tab in the Throne's place, his guild's page (King.Build).
function Nominees.GuildLines()
	local allowed, guild = Nominees.GuildAccess()
	if not allowed then return {} end
	local Line, INK, TITLE, Para = Ink()
	local V = ns.ViewAs
	local preview = V and V.Available and V.Available() and V.Role and V.Role() ~= "my"
	local master = preview and V.Role() == "gm" or not preview and Nominees.IsMaster()
	local dept = not preview and Nominees.OwnDepartment() or nil
	local lines = { Line(L.GUILD_TAB_TITLE:format(tostring(guild)), TITLE, { gapAfter = true }) }
	if master then Nominees.PageLines(lines) end
	-- Sharing a complete reset observation is the actual guild master's own opt-in,
	-- never a preview or a correspondent's power. The helper rechecks again on click.
	if not preview and master and ns.DuesRosterCheckpoints then ns.DuesRosterCheckpoints.GuildLines(lines) end
	Para(lines, L.GUILD_DEPARTMENT_SCOPE:format(tostring(guild)), INK, { gapAfter = true })
	local routes = { ["Federal Treasury"] = "treasury", ["Department of War"] = "war", ["Council of Justice"] = "watch",
		["Association of Artisanry"] = "crafters", ["Department of Heraldry"] = "decrees", ["The Missionary Church of Olympus"] = "church" }
	for _, department in ipairs(Nominees.Departments()) do
		if master or preview or dept == department then
			local name = not preview and Nominees.Correspondent(guild, department) or nil
			lines[#lines + 1] = Line(department, TITLE)
			lines[#lines + 1] = Line(name and L.GUILD_DEPARTMENT_NAMED:format(ns.DisplayName(name)) or L.GUILD_DEPARTMENT_EMPTY, INK, { indent = 1 })
			local route = routes[department]
			if department == "Association of Artisanry" then
				Para(lines, L.GUILD_DEPARTMENT_LIMITED, INK, { indent = 1 })
			elseif department == "The Missionary Church of Olympus" then
				Para(lines, L.GUILD_DEPARTMENT_CHURCH, INK, { indent = 1 })
			end
			if route then lines[#lines + 1] = Line(L.GUILD_DEPARTMENT_OPEN, INK, { indent = 1,
				onClick = not preview and function()
					local current = ns.ViewAs
					if current and current.Previewing and current.Previewing() then return end
					if not Nominees.IsMaster() and not Nominees.IsCorrespondent(ns.me, guild, department) then return end
					if route == "war" then if ns.War and ns.War.Show then ns.War.Show() end
					elseif route == "treasury" then if ns.Treasury and ns.Treasury.OpenOwnGuild then ns.Treasury.OpenOwnGuild() end
					else if route == "watch" and ns.Watch then ns.Watch.Show("chat") end; ns.UI.SelectTab(route) end
				end or nil }) end
			lines[#lines].gapAfter = true
		end
	end
	if preview then for _, row in ipairs(lines) do row.onClick = nil end end
	return lines
end

-- Manual main appointments are public nominations, not an automatically exposed council roster.
function Nominees.MainLines(lines)
	local Line, INK, TITLE, Para = Ink()
	local guild, mine = Nominees.MainGuild(), GetGuildInfo("player")
	local preview, editable = Nominees.MainPreview(), Nominees.MainNames()
	lines[#lines + 1] = Line(L.NOMINEES_MAIN_TITLE:format(guild), TITLE)
	Para(lines, L.NOMINEES_MAIN_HINT, INK, { gapAfter = true })
	local l = ListOf(guild)
	local entries = l and l.entries or {}
	if editable then lines[#lines + 1] = AddLine(#entries, true) end
	local S, R = ns.WarSquads, ns.Roster
	local ours = IsMain(mine) and type(R) == "table" and type(R.Fresh) == "function" and R.Fresh() ~= nil
		and type(S) == "table" and not S.missing and type(S.Leaders) == "function" and type(S.Get) == "function"
	local squads = {}
	if ours then
		for _, e in ipairs(S.Leaders()) do squads[ns.ShortName(e.name):lower()] = e end
	end
	if #entries == 0 then
		lines[#lines + 1] = Line(L.NOMINEES_MAIN_NONE, INK, { indent = 1 })
	else
		for _, e in ipairs(entries) do
			local row = Row(e, nil, editable, IsMain(R.guild), true)
			if ours then
				local leader = squads[ns.ShortName(e.name):lower()]
				local squad = leader and S.Get(leader.name)
				if squad then row.right = L.SQUAD_COUNT:format(squad.count or 0) end
			end
			lines[#lines + 1] = row
		end
	end
	if IsMain(mine) or preview then
		lines[#lines + 1] = Line(L.NOMINEES_MAIN_WAR, INK, { indent = 1,
			onClick = not preview and function() if ns.War and ns.War.Show then ns.War.Show() end end or nil })
	end
	lines[#lines].gapAfter = true
	Para(lines, L.NOMINEES_MAIN_NOTE:format(guild, type(S) == "table" and S.MAX_SOLDIERS or 39), INK)
	if preview then for _, row in ipairs(lines) do row.onClick = nil end end
	return lines
end

-- /oly status: a guild master's own list, and the lists this client holds, each its master's
-- (five named, the rest counted).
function Nominees.StatusLine()
	local out, held = {}, {}
	local o = Nominees.Ours()
	if o then out[1] = ("yours %d of %d"):format(#o.entries, Nominees.MAX) end
	for _, l in pairs(Lists()) do
		held[#held + 1] = l
	end
	table.sort(held, function(a, b) return a.guild < b.guild end)
	for i, l in ipairs(held) do
		if i > 5 then out[#out + 1] = ("and %d more"):format(#held - 5) break end
		out[#out + 1] = ("<%s> %d by %s (heard %s)"):format(l.guild, #l.entries, ns.DisplayName(l.by) or "?", ns.Ago(l.at))
	end
	return #out > 0 and table.concat(out, ", ") or "none"
end

-- `/oly nominees [centurion <name> | correspondent <n> <name> | remove <name>]`: alone, the tab
-- (a guild master's Guild tab; the Throne, with the King's centurions, for the King's people).
-- A guild master names in his own guild; the King, a councillor and the King preview are told that the
-- High Council are the King's centurions, nobody named (1.2.4). Anyone else is told whose it is.
function Nominees.Slash(rest)
	rest = Trim(rest)
	local verb, arg = rest:match("^(%S*)%s*(.-)$")
	verb = (verb or ""):lower()
	-- The author's guild master's view (his alone: anyone else gets the usual answer below).
	if verb == "view" and ns.Workshop and ns.Workshop.Visible and ns.Workshop.Visible() then
		Nominees.SetDevView(not Nominees.DevView())
		if Nominees.DevView() then verb = "" else return end
	end
	local master = Nominees.IsMaster()
	local kings = not master and KingsSide()
	if verb == "" then
		local K = ns.King
		if not (K and K.TabVisible and K.TabVisible()) then return ns.Print(L.NOMINEES_ONLY_MASTER) end
		K.mode = "home" -- (the Throne Room, or his Guild tab: never the King's Hands page)
		if ns.UI and ns.UI.SelectTab then ns.UI.SelectTab("throne") end
		return
	end
	local centurion = verb == "legate" or verb == "legatus" or verb == "legado" or verb == "centurion" or verb == "centuriao" or verb == "centurião"
	local remove = verb == "remove" or verb == "remover"
	if kings and centurion then return Nominees.NameMain(arg) end
	if kings and remove then return Nominees.RemoveMain(arg) end
	if centurion then return Nominees.Name("centurion", arg) end
	if (verb == "correspondent" or verb == "correspondente") and (master or not kings) then
		local n, name = arg:match("^(%d+)%s*(.-)$")
		local d = n and Nominees.Departments()[tonumber(n)]
		if not d then
			local list = {}
			for i, dept in ipairs(Nominees.Departments()) do list[#list + 1] = ("%d %s"):format(i, dept) end
			return ns.Print(L.NOMINEES_DEPTS:format(#list > 0 and table.concat(list, ", ") or L.NOMINEES_NONE))
		end
		return Nominees.Name("correspondent", name, d)
	end
	if remove then return Nominees.Remove(arg) end
	ns.Print(L.NOMINEES_USAGE)
end

StaticPopupDialogs["OLYMPUS_NOMINEE"] = {
	text = L.NOMINEES_PROMPT,
	button1 = OKAY or "OK",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 240,
	maxLetters = 60,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then
			local target = UnitIsPlayer and UnitIsPlayer("target") and ns.UnitFullName("target")
			eb:SetText(target and ns.DisplayName(target) or "")
			ns.Focus(eb)
		end
	end,
	OnAccept = function(self, data)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("name nominee", Taken, data or (self and self.data), eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		ns.SafeCall("name nominee", Taken, parent.data, self:GetText())
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_NOMINEE_REMOVE"] = {
	text = L.NOMINEES_REMOVE_CONFIRM,
	button1 = L.NOMINEES_REMOVE_BTN,
	button2 = CANCEL or "Cancel",
	OnAccept = function(self, data) ns.SafeCall("remove nominee", TakenBack, data or (self and self.data)) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- Before Borders.lua's and Nameplates.lua's (this file loads first): a list whose master was
-- deposed by the census or roster just heard is gone when they work their borders out again.
ns.On("DATA_CHANGED", function() Nominees.Prune() end)

-- Existing minute tick: eligible manual lists repeat, verified deposed issuers are pruned, and
-- a duty notice held for quiet/roster conditions gets another local opportunity. Silence drops none.
function Nominees.Minute()
	Nominees.Send()
	Nominees.SendMain()
	if Nominees.Prune() then ns.Fire("DATA_CHANGED") end
	local guild = GetGuildInfo("player")
	Nominees.AppointmentNotice(ListOf(guild))
end
ns.On("LOGIN", function() ns.Every(60, "nominees", Nominees.Minute) end)

-- Tests start from a clean state: the lists heard, saved ones too. (1.2.4) reload: the session's alone,
-- as a /reload forgets it: the next look puts the saved lists back.
function Nominees.Reset(reload)
	wipe(lists); wipe(pending)
	restoredFrom = nil
	if not reload and type(ns.rdb) == "table" then ns.rdb.nomineesHeard = nil end
	lastSent, sendPending, sentOnce = -math.huge, false, false
	lastMainSent, mainHeardAt, mainSendPending = -math.huge, -math.huge, false
	Bump()
end
