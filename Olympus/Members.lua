local ADDON, ns = ...
local L = ns.L

-- Our own guild's members page (1.1), in the Realm tab like the chats. Asked for by Fern, of
-- Asmongold's moderators:
-- #38: the members offline 7, 14 or 30 days and more, with rank, class, level and last online,
--   from our own roster (Roster.Scan: the server's word, what the game's Guild window shows every
--   member). A player whose rank may remove members (CanGuildRemove, and only ranks below theirs,
--   as the game's own Guild window allows) removes one person per click: a question through
--   ns.ShowDialog, then the game's own call (C_GuildInfo.Uninvite) inside that click, with a short
--   gap between two removals. Nothing picks several at once: there is no kick-all.
-- Nothing here is sent, and nothing kept past the session.

local Members = {}
ns.Members = Members

local Plain = ns.Codec.Plain

Members.FILTERS = { 7, 14, 30 } -- days offline
Members.PAGE = 100              -- rows shown, then a page more per click
Members.REMOVE_GAP = 3          -- seconds between two removals

local page -- nil (the Realm's tree) or { filter, shown }
local lastRemove = -math.huge
local removed = {} -- [raw name] = true: removed this session (the roster drops them at its next scan)

function Members.Shown() return page ~= nil end
function Members.Filter() return page and page.filter end
-- Which page the Realm shows, for the window's place (UI.lua): another one starts at the top.
function Members.PageId() return page and ("members:" .. tostring(page.filter)) or nil end
-- The Realm's tree again, no redraw (Views.CloseChat, another tab).
function Members.Hide() page = nil end

function Members.Show(filter)
	if ns.Views and ns.Views.CloseChat then ns.Views.CloseChat() end
	page = { filter = filter or Members.FILTERS[1], shown = Members.PAGE }
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end
function Members.Close()
	page = nil
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

-- May we remove members at all (the game's word), and this one (a rank below ours, never the
-- guild master, never ourselves)?
function Members.CanRemove()
	return type(CanGuildRemove) == "function" and CanGuildRemove() and true or false
end
function Members.Removable(m)
	if type(m) ~= "table" or not m.raw or removed[m.raw] then return false end
	local rank = m.rankIndex
	return type(rank) == "number" and rank >= 1 and rank > ns.Roster.MyRank()
end

local function ClassName(m)
	local file = m.class and ns.CLASS_FILES[m.class]
	return file and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file] or "", file
end

-- "45 days ago", "5h ago": the game gives years, months, days and hours (Roster.lua).
function Members.LastOnline(days)
	days = days or 0
	if days >= 1 then return L.MEMBERS_LAST_DAYS:format(math.floor(days)) end
	return L.MEMBERS_LAST_HOURS:format(math.max(0, math.floor(days * 24)))
end

-- Asked from a row's click: the question, with who, rank and how long away.
function Members.AskRemove(m)
	if not (Members.CanRemove() and Members.Removable(m)) then return nil end
	local className = ClassName(m)
	local details = L.MEMBERS_REMOVE_DETAILS:format(Plain(m.rank or "?"), m.level or 0, className, Members.LastOnline(m.days))
	return ns.ShowDialog("OLYMPUS_GUILD_REMOVE", Plain(m.name), details, m)
end

-- The question answered: the game removes that one member. From the player's click only.
function Members.Remove(m)
	if not (Members.CanRemove() and Members.Removable(m)) then return false end
	local now = GetTime()
	if now - lastRemove < Members.REMOVE_GAP then
		ns.Print(L.MEMBERS_REMOVE_WAIT)
		return false
	end
	local uninvite = (C_GuildInfo and C_GuildInfo.Uninvite) or GuildUninvite
	if type(uninvite) ~= "function" then return false end
	lastRemove = now
	uninvite(m.raw)
	removed[m.raw] = true
	ns.Log("members: removed %s (%s, %.1f days offline)", tostring(m.raw), tostring(m.rank), m.days or 0)
	ns.Print(L.MEMBERS_REMOVED_LINE:format(Plain(m.name)))
	ns.Roster.RequestScan(true)
	ns.Fire("DATA_CHANGED")
	return true
end

function Members.ResetForTests() page, lastRemove = nil, -math.huge; wipe(removed) end

local function Row(m, canRemove)
	local V = ns.Views
	local className, file = ClassName(m)
	local gone = removed[m.raw]
	local removable = canRemove and Members.Removable(m)
	local person = { name = m.name, class = m.class, level = m.level, guild = GetGuildInfo("player"), rank = m.rank, online = m.online, days = m.days }
	return {
		key = m.name,
		text = V.ClassColored(m.name, file) .. "  " .. V.Grey(Plain(m.rank or "") .. (className ~= "" and ("  ·  " .. className) or "")),
		right = V.Grey(L.LEVEL_N:format(m.level or 0) .. "  ·  " .. Members.LastOnline(m.days))
			.. (gone and ("  " .. V.Grey(L.MEMBERS_REMOVED)) or removable and ("  " .. V.Red(L.MEMBERS_REMOVE)) or ""),
		onClick = not gone and function()
			if removable then return Members.AskRemove(m) end
			ns.UI.ShowPerson(person)
		end or nil,
		tooltip = function(tt)
			tt:AddLine(Plain(m.name), 1, 0.82, 0)
			tt:AddLine(Plain(m.rank or "") .. "  ·  " .. L.LEVEL_N:format(m.level or 0) .. " " .. className, 1, 1, 1)
			tt:AddLine(L.MEMBERS_LAST:format(Members.LastOnline(m.days)), 0.8, 0.8, 0.8)
			if removable then tt:AddLine(L.MEMBERS_REMOVE_TIP, 1, 0.4, 0.4, true) end
		end,
	}
end

-- The page's lines. `q`, the Realm's search (Views.Query): the members whose name, rank or class
-- holds it.
function Members.Lines(q)
	local V = ns.Views
	local lines = { { text = V.Gold(L.MEMBERS_BACK), onClick = Members.Close, gapAfter = true } }
	local guild = GetGuildInfo("player")
	local all = ns.Roster.members or {}
	if not (guild and ns.IsFederation(guild)) or #all == 0 then
		lines[#lines + 1] = { text = V.Grey(L.MEMBERS_NONE_YET) }
		return lines
	end
	local stats = ns.Roster.lastStats or {}
	local total = math.max(stats.numTotal or 0, #all)
	local counts, offline = {}, 0
	for _, f in ipairs(Members.FILTERS) do counts[f] = 0 end
	for _, m in ipairs(all) do
		if not m.online then
			offline = offline + 1
			for _, f in ipairs(Members.FILTERS) do
				if (m.days or 0) >= f then counts[f] = counts[f] + 1 end
			end
		end
	end
	lines[#lines + 1] = {
		header = true, text = "<" .. Plain(guild) .. ">",
		right = V.Grey(L.MEMBERS_COUNTS:format(ns.FormatNumber(total), ns.FormatNumber(math.max(0, 1000 - total)), ns.FormatNumber(counts[30] or 0))),
	}
	for _, f in ipairs(Members.FILTERS) do
		local on = page.filter == f
		lines[#lines + 1] = {
			text = on and V.Gold("> " .. L.MEMBERS_FILTER:format(f)) or ("   " .. L.MEMBERS_FILTER:format(f)),
			right = V.Grey(ns.FormatNumber(counts[f])),
			onClick = not on and function() Members.Show(f) end or nil,
		}
	end
	lines[#lines].gapAfter = true
	local canRemove = Members.CanRemove()
	lines[#lines + 1] = { text = V.Grey(canRemove and L.MEMBERS_REMOVE_HINT or L.MEMBERS_VIEW_HINT) }
	-- The game lists only who is online (its "Show offline members" unticked): say so.
	if offline == 0 and total > #all then lines[#lines + 1] = { text = V.Grey(L.MEMBERS_NO_OFFLINE) } end
	lines[#lines].gapAfter = true
	local list = {}
	for _, m in ipairs(all) do
		if not m.online and (m.days or 0) >= page.filter and (not q or ns.Holds(q, m.name, m.rank, (ClassName(m)))) then list[#list + 1] = m end
	end
	table.sort(list, function(a, b)
		if (a.days or 0) ~= (b.days or 0) then return (a.days or 0) > (b.days or 0) end
		return a.name < b.name
	end)
	local shown = math.min(#list, page.shown)
	for i = 1, shown do lines[#lines + 1] = Row(list[i], canRemove) end
	if #list > shown then
		lines[#lines + 1] = {
			text = V.Gold(L.SHOW_MORE:format(math.min(Members.PAGE, #list - shown), shown, #list)),
			onClick = function()
				page.shown = page.shown + Members.PAGE
				ns.UI.Refresh()
			end,
		}
	end
	if #list == 0 then lines[#lines + 1] = { text = V.Grey(q and L.SEARCH_NO_MATCH or L.MEMBERS_NONE) } end
	return lines
end

---------------------------------------------------------------------------
-- A Lord away (1.1, Fern's #39): one chat line when a guild's Lord crosses warnDays offline
-- (/oly warndays, 3 by default), instead of a red name in a list of twenty guilds. To our own
-- guild's officers about our Lord, from our roster (the server's word, GetGuildRosterLastOnline);
-- to the King, his Steward and his Hands (King.CanCommand) about every guild's Lord, from the
-- census (a report's leaderDays, aged by how old the report is: a guild that stopped reporting
-- is exactly the one to hear about; the census's word, which the line says). Once per crossing:
-- again only after that Lord came back. A line, never a popup or a sound, and nothing is done to
-- anyone: no kick, no transfer. Nothing is sent.
---------------------------------------------------------------------------

Members.LORD_LIST = 5 -- Lords named in one line to the Crown, the rest counted

function Members.WarnDays() return tonumber(ns.db and ns.db.warnDays) or 3 end

-- [guild] = the Lord we told about, while he stays away (saved where the client keeps saves).
local function Warned()
	ns.rdb.lordWarned = ns.rdb.lordWarned or {}
	return ns.rdb.lordWarned
end

-- Our Lord, from the roster just read (Roster.Scan's report `r`): officers only, not the Lord.
function Members.CheckOwnLord(r)
	if type(r) ~= "table" or not r.leader or not ns.IsFederation(r.guild) then return false end
	local warned, key = Warned(), "own:" .. r.guild
	local days = r.leaderOnline and 0 or (r.leaderDays or 0)
	if days < Members.WarnDays() then
		warned[key] = nil
		return false
	end
	local rank = ns.Roster.MyRank()
	if rank < 1 or rank > ns.CAPTAIN_RANK or warned[key] == r.leader then return false end
	warned[key] = r.leader
	ns.Print(L.LORD_AWAY_OWN:format(Plain(r.leader), math.floor(days), Members.WarnDays()))
	ns.Log("lord away: our Lord %s, %.1f days", tostring(r.leader), days)
	return true
end

-- Every other guild's Lord, from the census, for the Crown. Returns how many were named.
function Members.CheckLords(now)
	now = now or ns.Now()
	if not (ns.King and ns.King.CanCommand and ns.King.CanCommand()) then return 0 end
	local loginAt = ns.Comm and ns.Comm.loginAt
	if loginAt and now - loginAt < ns.Data.CROWN_AFTER then return 0 end -- the census rebuilding
	local warned, own, crossed = Warned(), GetGuildInfo("player"), {}
	for name, g in pairs(ns.rdb.guilds or {}) do
		local age = now - (type(g) == "table" and g.t or 0)
		if type(g) == "table" and not g.mine and name ~= own and g.leader and age <= ns.Data.KEEP and ns.IsFederation(name) then
			local days = g.leaderOnline and 0 or ((g.leaderDays or 0) + math.max(0, age) / 86400)
			if days < Members.WarnDays() then
				warned[name] = nil
			elseif warned[name] ~= g.leader then
				warned[name] = g.leader
				crossed[#crossed + 1] = { guild = name, lord = g.leader, days = days }
			end
		end
	end
	if #crossed == 0 then return 0 end
	table.sort(crossed, function(a, b)
		if a.days ~= b.days then return a.days > b.days end
		return a.guild < b.guild
	end)
	if #crossed == 1 then
		local c = crossed[1]
		ns.Print(L.LORD_AWAY_CROWN:format(Plain(c.lord), Plain(c.guild), math.floor(c.days)))
	else
		local parts = {}
		for i = 1, math.min(#crossed, Members.LORD_LIST) do
			local c = crossed[i]
			parts[#parts + 1] = L.LORD_AWAY_ENTRY:format(Plain(c.lord), Plain(c.guild), math.floor(c.days))
		end
		local more = #crossed > Members.LORD_LIST and (" " .. L.LORD_AWAY_MORE:format(#crossed - Members.LORD_LIST)) or ""
		ns.Print(L.LORD_AWAY_CROWN_MANY:format(#crossed, Members.WarnDays(), table.concat(parts, ", ")) .. more)
	end
	ns.Log("lord away: %d Lords past %d days", #crossed, Members.WarnDays())
	return #crossed
end

-- /oly warndays <n>: when a Lord or Captain counts as away (their name turns red, and the line).
function Members.SetWarnDays(text)
	local n = tonumber(text)
	if not n or n < 1 or n > 60 or n ~= math.floor(n) then
		ns.Print(L.WARNDAYS_USAGE:format(Members.WarnDays()))
		return false
	end
	ns.db.warnDays = n
	ns.Print(L.WARNDAYS_SET:format(n))
	ns.Fire("DATA_CHANGED")
	return true
end

ns.On("LOGIN", function()
	ns.Every(60, "lords away", function() Members.CheckLords() end)
end)

StaticPopupDialogs["OLYMPUS_GUILD_REMOVE"] = {
	text = L.MEMBERS_REMOVE_CONFIRM,
	button1 = L.MEMBERS_REMOVE,
	button2 = CANCEL or "Cancel",
	OnAccept = function(self, data) ns.SafeCall("guild remove", Members.Remove, data or (self and self.data)) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	showAlert = true,
	preferredIndex = 3,
}
