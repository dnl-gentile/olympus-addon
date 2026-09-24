local ADDON, ns = ...
local L = ns.L

-- The Workshop: the addon author's own tab (his character alone, ns.AUTHOR), to see how the
-- addon does across the army and to help the players who run it.
--   * Installs and versions per guild, from the reports every guild sends anyway (field 24:
--     the versions of the guild's addon users, counted by its reporter from their hellos).
--   * A roll call on demand: each addon answers with its version, client, window and what
--     works (V1/V2); when the army is large, only a share of them answers.
--   * A report to copy for Discord.
--   * "Please update", to a player on an old version: a fixed text, nothing else (V3).
--   * The author's presence (V4): players can send him their bug report from the Report a
--     bug window (V5), and nowhere else.
-- Only the character named ns.AUTHOR can send V1, V3 and V4, and only he receives V2 and V5.
-- Forever names (first name and surname) are unique across its realm group, and on the
-- Classic realms no name has a space: nobody else can carry his. Receivers answer a roll call
-- once per ROLL_GAP, and show "please update" once per UPDATE_GAP, only when really behind.
--   V1~<id>~<share 1-100>                                              (channel)
--   V2~<id>~<version>~<guild>~<client>~<window>~<flags>~<errors>~<level>~<class>   (whisper)
--   V3~<latest version>                                                (whisper)
--   V4~<version>                                                       (channel)
--   V5~<id>~<i>~<n>~<piece>                                            (whisper)

local Workshop = {}
ns.Workshop = Workshop

Workshop.ROLL_GAP = 30 * 60     -- a client answers one roll call in this long
Workshop.ROLL_EVERY = 5 * 60    -- the author asks at most this often
Workshop.ROLL_OPEN = 5 * 60     -- answers count this long after the ask
Workshop.ROLL_SPREAD = 30       -- answers are spread over this many seconds
Workshop.ROLL_TARGET = 300      -- answers wanted, however large the army (the share)
Workshop.MAX_ANSWERS = 3000
Workshop.UPDATE_GAP = 10 * 60   -- "please update" at most this often, both ways
Workshop.PRESENCE_EVERY = 10 * 60
Workshop.PRESENCE_FRESH = 15 * 60
Workshop.BUG_GAP = 10 * 60      -- a player sends one bug report in this long
Workshop.BUG_MAX = 4000         -- bytes of a bug report
Workshop.PIECE = 200
Workshop.MAX_PIECES = 25
Workshop.MAX_REPORTS = 30
Workshop.MAX_SHOWN = 30
Workshop.MAX_ASK = 15           -- "please update" whispers per click (the send queue holds 60)

-- Swappable in tests.
Workshop.random = math.random
Workshop.after = function(seconds, where, fn) ns.After(seconds, where, fn) end

local roll            -- the author's roll call: { id, t, share, answers = { [sender] = answer }, count }
local reports = {}    -- bug reports received: { from, t, text }, newest last
local pieces = {}     -- [sender#id] = { n, got, parts, t }
local bugsFrom = {}   -- [sender] = times of their reports this hour
local asked = {}      -- [sender] = when we last asked them to update
local lastRoll, lastRollAnswer, lastUpdateShown, lastBug = -math.huge, -math.huge, -math.huge, -math.huge
local authorAt, authorName -- the author's last presence, and his full name
local changePending = false

local function Changed()
	if changePending then return end
	changePending = true
	Workshop.after(1, "workshop changed", function()
		changePending = false
		ns.Fire("WORKSHOP_CHANGED")
	end)
end

---------------------------------------------------------------------------
-- Who is who
---------------------------------------------------------------------------

local function IsAuthorName(name)
	return type(name) == "string" and ns.ShortName(name) == ns.AUTHOR
end

function Workshop.IsAuthor() return IsAuthorName(ns.me) end

-- The author's test characters (Dev.lua, never published) see the tab too: nothing it sends
-- goes anywhere but the test bench's log (DevTest.lua), or is ignored by everyone.
function Workshop.Preview()
	local dev = ns.devWorkshop
	if type(dev) == "table" then dev = dev[UnitName and UnitName("player") or ""] == true end
	return dev == true and not Workshop.IsAuthor()
end

function Workshop.Visible() return Workshop.IsAuthor() or Workshop.Preview() end

-- The author is online (his presence was heard lately), and not us.
function Workshop.AuthorOnline()
	if Workshop.IsAuthor() or not authorAt then return false end
	return ns.Now() - authorAt <= Workshop.PRESENCE_FRESH
end
function Workshop.AuthorName() return authorName end

---------------------------------------------------------------------------
-- Versions
---------------------------------------------------------------------------

-- "0.8.2" -> { 0, 8, 2 }; anything else -> nil.
local function Parts(v)
	local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.(%d+)$")
	if not a then return nil end
	return { tonumber(a), tonumber(b), tonumber(c) }
end

-- a is newer than b.
function Workshop.Newer(a, b)
	local x, y = Parts(a), Parts(b)
	if not x or not y then return false end
	for i = 1, 3 do
		if x[i] ~= y[i] then return x[i] > y[i] end
	end
	return false
end

-- The newest version anyone has: ours, a report's, or a roll call answer's.
function Workshop.Latest()
	local best = ns.VERSION
	for _, g in pairs(ns.rdb and ns.rdb.guilds or {}) do
		if type(g) == "table" then
			for v in pairs(g.versions or {}) do
				if Workshop.Newer(v, best) then best = v end
			end
		end
	end
	for _, a in pairs(roll and roll.answers or {}) do
		if Workshop.Newer(a.version, best) then best = a.version end
	end
	return best
end

---------------------------------------------------------------------------
-- This client, as a roll call answer tells it
---------------------------------------------------------------------------

local function Clean(s, max)
	return (tostring(s or ""):gsub("[~|%c]", "")):sub(1, max or 40)
end

-- Which game: by the interface number (Forever 1.60, Era 1.15, Anniversary 2.5).
function Workshop.Client()
	local toc = select(4, GetBuildInfo())
	toc = tonumber(toc) or 0
	if toc >= 16000 and toc < 20000 then return "Forever" end
	if toc >= 20000 and toc < 30000 then return "Anniversary" end
	if toc >= 10000 and toc < 16000 then return "Era" end
	return tostring(toc)
end

-- Letters for what works here: c channel joined, r our guild's reporter, k sealed channel,
-- m map library, p map markers on.
function Workshop.Flags()
	local f = {}
	if ns.Comm.ChannelReady() then f[#f + 1] = "c" end
	if ns.Comm.isReporter then f[#f + 1] = "r" end
	if ns.rdb and ns.rdb.realmKey then f[#f + 1] = "k" end
	if ns.Pins and ns.Pins() then f[#f + 1] = "m" end
	if ns.db and ns.db.showMap then f[#f + 1] = "p" end
	return table.concat(f)
end

local function Answer(id)
	local level = UnitLevel and UnitLevel("player") or 0
	local class = UnitClass and select(2, UnitClass("player"))
	local window = ns.UI and ns.UI.Style and ns.UI.Style() or "?"
	return ("V2~%d~%s~%s~%s~%s~%s~%d~%d~%s"):format(id, Clean(ns.VERSION, 12), Clean(GetGuildInfo("player") or "", 40),
		Workshop.Client(), Clean(window, 8), Workshop.Flags(), #(ns.allErrors or {}), level or 0, ns.Roster.ClassCode(class))
end

---------------------------------------------------------------------------
-- Roll call
---------------------------------------------------------------------------

-- How many of the army answer: all of it while small, a share of it once large.
function Workshop.Share(users)
	users = tonumber(users) or 0
	if users <= Workshop.ROLL_TARGET then return 100 end
	return math.max(5, math.min(100, math.ceil(Workshop.ROLL_TARGET * 100 / users)))
end

-- The addon users the reports count, over every fresh guild.
function Workshop.ReportedUsers()
	local n, now = 0, ns.Now()
	for name, g in pairs(ns.rdb and ns.rdb.guilds or {}) do
		if type(g) == "table" and ns.IsFederation(name) and now - (g.t or 0) <= ns.Data.FRESH then n = n + (g.users or 0) end
	end
	return n
end

function Workshop.RollCall()
	if not Workshop.Visible() then return end
	local now = ns.Now()
	if now - lastRoll < Workshop.ROLL_EVERY then
		return ns.Print(L.WORKSHOP_ROLL_WAIT:format(math.ceil((Workshop.ROLL_EVERY - (now - lastRoll)) / 60)))
	end
	lastRoll = now
	local share = Workshop.Share(Workshop.ReportedUsers())
	roll = { id = Workshop.random(1, 99999), t = now, share = share, answers = {}, count = 0 }
	ns.Comm.Send("CHANNEL", ("V1~%d~%d"):format(roll.id, share), "rollcall")
	ns.Print(L.WORKSHOP_ROLL_SENT:format(share))
	Changed()
end

function Workshop.HandleRoll(dist, sender, text)
	if dist ~= "CHANNEL" or not IsAuthorName(sender) or Workshop.IsAuthor() then return end
	local id, share = text:match("^V1~(%d+)~(%d+)$")
	id, share = tonumber(id), tonumber(share)
	if not id or not share then return end
	authorAt, authorName = ns.Now(), ns.FullName(sender)
	local now = ns.Now()
	if now - lastRollAnswer < Workshop.ROLL_GAP then return end
	if Workshop.random(1, 100) > math.max(1, math.min(100, share)) then return end
	lastRollAnswer = now
	-- Spread over ROLL_SPREAD: a thousand answers do not arrive in the same second.
	Workshop.after(1 + Workshop.random() * Workshop.ROLL_SPREAD, "roll call answer", function()
		ns.Comm.Whisper(ns.FullName(sender), Answer(id), "rollanswer")
	end)
end

function Workshop.HandleAnswer(dist, sender, text)
	if dist ~= "WHISPER" or not Workshop.IsAuthor() or not roll then return end
	if ns.Now() - roll.t > Workshop.ROLL_OPEN then return end
	local id, version, guild, client, window, flags, errors, level, class =
		text:match("^V2~(%d+)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~(%d+)~(%d+)~([^~]*)$")
	if tonumber(id) ~= roll.id then return end
	sender = ns.FullName(sender)
	if roll.answers[sender] then return end
	if roll.count >= Workshop.MAX_ANSWERS then return end
	roll.count = roll.count + 1
	roll.answers[sender] = {
		name = sender, version = Clean(version, 12), guild = Clean(guild, 40), client = Clean(client, 12),
		window = Clean(window, 8), flags = Clean(flags, 8), errors = math.min(tonumber(errors) or 0, 999),
		level = math.min(tonumber(level) or 0, 99), class = Clean(class, 2), t = ns.Now(),
	}
	Changed()
end

---------------------------------------------------------------------------
-- Please update
---------------------------------------------------------------------------

function Workshop.AskUpdate(name)
	if not Workshop.Visible() or type(name) ~= "string" then return false end
	local now = ns.Now()
	local key = ns.FullName(name)
	if now - (asked[key] or -math.huge) < Workshop.UPDATE_GAP then return false end
	asked[key] = now
	ns.Comm.Whisper(key, "V3~" .. Workshop.Latest(), "askupdate:" .. key) -- one queued per player
	return true
end

-- Every roll call answer on an old version, MAX_ASK at most per click.
function Workshop.AskOutdated()
	local latest, n = Workshop.Latest(), 0
	for _, a in pairs(roll and roll.answers or {}) do
		if n >= Workshop.MAX_ASK then break end
		if Workshop.Newer(latest, a.version) and Workshop.AskUpdate(a.name) then n = n + 1 end
	end
	ns.Print(L.WORKSHOP_ASKED:format(n, latest))
	Changed()
end

function Workshop.HandleUpdate(dist, sender, text)
	if dist ~= "WHISPER" or not IsAuthorName(sender) then return end
	local latest = text:match("^V3~(%d+%.%d+%.%d+)$")
	if not latest or not Workshop.Newer(latest, ns.VERSION) then return end
	local now = ns.Now()
	if now - lastUpdateShown < Workshop.UPDATE_GAP then return end
	lastUpdateShown = now
	ns.PlayAlert("soft")
	StaticPopup_Show("OLYMPUS_AUTHOR_UPDATE", ns.VERSION, latest)
end

StaticPopupDialogs["OLYMPUS_AUTHOR_UPDATE"] = {
	text = L.WORKSHOP_UPDATE_POPUP,
	button1 = OKAY or "OK",
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

---------------------------------------------------------------------------
-- The author's presence, and bug reports to him
---------------------------------------------------------------------------

function Workshop.SendPresence()
	if not Workshop.IsAuthor() then return end
	ns.Comm.Send("CHANNEL", "V4~" .. Clean(ns.VERSION, 12), "presence")
end

function Workshop.HandlePresence(dist, sender, text)
	if dist ~= "CHANNEL" or not IsAuthorName(sender) or Workshop.IsAuthor() then return end
	if not text:match("^V4~") then return end
	local was = Workshop.AuthorOnline()
	authorAt, authorName = ns.Now(), ns.FullName(sender)
	if not was then ns.Fire("DATA_CHANGED") end
end

-- The bug report as it travels: no newlines or pipes (they are put back as "\n" and "!").
local function Pack(text)
	text = tostring(text or ""):gsub("|", "!"):gsub("\r", ""):gsub("\n", "\\n")
	return text:sub(1, Workshop.BUG_MAX)
end

-- The button the Report a bug window shows while the author is online, or nil.
function Workshop.BugAction(text)
	if not Workshop.AuthorOnline() or not authorName then return nil end
	return {
		label = L.WORKSHOP_SEND_BUG:format(ns.DisplayName(authorName)),
		fn = function() return Workshop.SendBug(text) end,
	}
end

function Workshop.SendBug(text)
	if not Workshop.AuthorOnline() or not authorName then return false end
	local now = ns.Now()
	if now - lastBug < Workshop.BUG_GAP then
		ns.Print(L.WORKSHOP_BUG_WAIT:format(math.ceil((Workshop.BUG_GAP - (now - lastBug)) / 60)))
		return false
	end
	lastBug = now
	local body = Pack(text)
	local n = math.min(Workshop.MAX_PIECES, math.max(1, math.ceil(#body / Workshop.PIECE)))
	local id = Workshop.random(1, 99999)
	for i = 1, n do
		ns.Comm.Whisper(authorName, ("V5~%d~%d~%d~%s"):format(id, i, n, body:sub((i - 1) * Workshop.PIECE + 1, i * Workshop.PIECE)), "bug" .. id .. ":" .. i)
	end
	ns.Print(L.WORKSHOP_BUG_SENT:format(ns.DisplayName(authorName)))
	return true
end

function Workshop.HandleBug(dist, sender, text)
	if dist ~= "WHISPER" or not Workshop.IsAuthor() then return end
	local id, i, n, piece = text:match("^V5~(%d+)~(%d+)~(%d+)~(.*)$")
	i, n = tonumber(i), tonumber(n)
	if not id or not i or not n or n < 1 or n > Workshop.MAX_PIECES or i < 1 or i > n then return end
	sender = ns.FullName(sender)
	local now = ns.Now()
	-- Three reports an hour per player, and a few players at a time.
	local times = bugsFrom[sender] or {}
	for k = #times, 1, -1 do if now - times[k] > 3600 then table.remove(times, k) end end
	if #times >= 3 then return end
	local key = sender .. "#" .. id
	local e = pieces[key]
	if not e then
		local open = 0
		for k, p in pairs(pieces) do
			if now - p.t > 120 then pieces[k] = nil else open = open + 1 end
		end
		if open >= 10 then return end
		e = { n = n, got = 0, parts = {}, t = now }
		pieces[key] = e
	end
	if e.n ~= n or e.parts[i] then return end
	e.parts[i], e.got = piece:sub(1, Workshop.PIECE), e.got + 1
	if e.got < n then return end
	pieces[key] = nil
	times[#times + 1] = now
	bugsFrom[sender] = times
	reports[#reports + 1] = { from = sender, t = now, text = table.concat(e.parts):gsub("\\n", "\n") }
	while #reports > Workshop.MAX_REPORTS do table.remove(reports, 1) end
	ns.PlayAlert("soft")
	ns.Print(L.WORKSHOP_BUG_IN:format(ns.DisplayName(sender)))
	Changed()
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------

local function Grey(s) return "|cff9d9d9d" .. s .. "|r" end
local function Gold(s) return "|cffffd200" .. s .. "|r" end
local function Green(s) return "|cff40ff40" .. s .. "|r" end
local function Red(s) return "|cffff4040" .. s .. "|r" end

-- "0.8.2 12  ·  0.8.1 3", newest first.
local function Versions(map)
	local list = {}
	for v, n in pairs(map or {}) do list[#list + 1] = { v = v, n = n } end
	table.sort(list, function(a, b)
		if a.v ~= b.v then return Workshop.Newer(a.v, b.v) end
		return a.n > b.n
	end)
	local latest, parts = Workshop.Latest(), {}
	for _, e in ipairs(list) do
		local label = e.v .. " " .. e.n
		parts[#parts + 1] = Workshop.Newer(latest, e.v) and Red(label) or Green(label)
	end
	return #parts > 0 and table.concat(parts, "  ·  ") or Grey("?")
end

local function Count(map, key) map[key] = (map[key] or 0) + 1 end

-- The reports' view: every guild's addon users and their versions.
local function InstallLines(lines)
	local now, rows, users, versions = ns.Now(), {}, 0, {}
	for name, g in pairs(ns.rdb and ns.rdb.guilds or {}) do
		if type(g) == "table" and ns.IsFederation(name) and now - (g.t or 0) <= ns.Data.FRESH then
			rows[#rows + 1] = { name = name, g = g }
			users = users + (g.users or 0)
			for v, n in pairs(g.versions or {}) do versions[v] = (versions[v] or 0) + n end
		end
	end
	table.sort(rows, function(a, b)
		if (a.g.users or 0) ~= (b.g.users or 0) then return (a.g.users or 0) > (b.g.users or 0) end
		return a.name < b.name
	end)
	lines[#lines + 1] = { header = true, text = L.WORKSHOP_INSTALLS, right = Gold(L.WORKSHOP_USERS:format(users, #rows)) }
	lines[#lines + 1] = { text = L.WORKSHOP_VERSIONS .. ": " .. Versions(versions), gapAfter = #rows == 0 }
	if #rows == 0 then lines[#lines].text = Grey(L.EMPTY) end
	for i = 1, math.min(Workshop.MAX_SHOWN, #rows) do
		local e = rows[i]
		lines[#lines + 1] = {
			indent = 1, text = Green("<" .. e.name .. ">") .. "  " .. (next(e.g.versions or {}) and Versions(e.g.versions) or Grey(L.WORKSHOP_OLD_REPORTER)),
			right = L.WORKSHOP_OF_ONLINE:format(e.g.users or 0, e.g.online or 0),
		}
	end
	lines[#lines].gapAfter = true
end

local function Problems(a, latest)
	local out = {}
	if Workshop.Newer(latest, a.version) then out[#out + 1] = Red(a.version) end
	if a.errors > 0 then out[#out + 1] = Red(L.WORKSHOP_ERRORS:format(a.errors)) end
	if not a.flags:find("c", 1, true) then out[#out + 1] = Red(L.WORKSHOP_NO_CHANNEL) end
	return out
end

local function RollLines(lines)
	lines[#lines + 1] = { header = true, text = L.WORKSHOP_ROLL, right = roll and Grey(ns.Ago(roll.t)) or nil }
	if not roll then
		lines[#lines + 1] = { text = Grey(L.WORKSHOP_ROLL_NONE), gapAfter = true }
		return
	end
	local versions, clients, windows, noChannel, withErrors = {}, {}, {}, 0, 0
	local latest, list = Workshop.Latest(), {}
	for _, a in pairs(roll.answers) do
		Count(versions, a.version)
		Count(clients, a.client)
		Count(windows, a.window)
		if not a.flags:find("c", 1, true) then noChannel = noChannel + 1 end
		if a.errors > 0 then withErrors = withErrors + 1 end
		if #Problems(a, latest) > 0 then list[#list + 1] = a end
	end
	local function Join(map)
		local parts = {}
		for k, n in pairs(map) do parts[#parts + 1] = k .. " " .. n end
		table.sort(parts)
		return #parts > 0 and table.concat(parts, "  ·  ") or "-"
	end
	lines[#lines + 1] = { text = L.WORKSHOP_ANSWERS:format(roll.count, roll.share) }
	lines[#lines + 1] = { indent = 1, text = L.WORKSHOP_VERSIONS .. ": " .. Versions(versions) }
	lines[#lines + 1] = { indent = 1, text = L.WORKSHOP_CLIENTS .. ": " .. Join(clients) }
	lines[#lines + 1] = { indent = 1, text = L.WORKSHOP_WINDOWS .. ": " .. Join(windows) }
	lines[#lines + 1] = { indent = 1, text = L.WORKSHOP_HEALTH:format(noChannel, withErrors), gapAfter = true }
	table.sort(list, function(a, b)
		if a.errors ~= b.errors then return a.errors > b.errors end
		return a.name < b.name
	end)
	lines[#lines + 1] = { header = true, text = L.WORKSHOP_ATTENTION:format(#list) }
	if #list == 0 then lines[#lines + 1] = { text = Grey(L.WORKSHOP_ALL_GOOD) } end
	for i = 1, math.min(Workshop.MAX_SHOWN, #list) do
		local a = list[i]
		local outdated = Workshop.Newer(latest, a.version)
		lines[#lines + 1] = {
			key = a.name, indent = 1,
			text = ns.DisplayName(a.name) .. "  " .. Grey("<" .. (a.guild ~= "" and a.guild or "?") .. ">"),
			right = table.concat(Problems(a, latest), "  "),
			onClick = function()
				if outdated then
					StaticPopup_Show("OLYMPUS_WORKSHOP_ASK", ns.DisplayName(a.name), nil, a.name)
				else
					ns.UI.ShowPerson({ name = ns.DisplayName(a.name), level = a.level, class = a.class ~= "" and a.class or nil, guild = a.guild })
				end
			end,
			tooltip = function(tt)
				tt:AddLine(ns.DisplayName(a.name), 1, 0.82, 0)
				tt:AddLine(("%s  ·  %s  ·  %s  ·  %s"):format(a.version, a.client, a.window, a.flags ~= "" and a.flags or "-"), 1, 1, 1)
				if outdated then tt:AddLine(L.WORKSHOP_CLICK_ASK, 0.25, 1, 0.25, true) end
			end,
		}
	end
	if #list > Workshop.MAX_SHOWN then lines[#lines + 1] = { indent = 1, text = Grey(L.AND_MORE:format(#list - Workshop.MAX_SHOWN)) } end
	lines[#lines].gapAfter = true
end

StaticPopupDialogs["OLYMPUS_WORKSHOP_ASK"] = {
	text = L.WORKSHOP_ASK_CONFIRM,
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function(self, data)
		ns.SafeCall("workshop ask", function()
			local name = data or (self and self.data)
			if Workshop.AskUpdate(name) then ns.Print(L.WORKSHOP_ASKED:format(1, Workshop.Latest())) end
		end)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function BugLines(lines)
	lines[#lines + 1] = { header = true, text = L.WORKSHOP_BUGS:format(#reports) }
	if #reports == 0 then lines[#lines + 1] = { text = Grey(L.WORKSHOP_BUGS_NONE) } end
	for i = #reports, math.max(1, #reports - Workshop.MAX_SHOWN + 1), -1 do
		local r = reports[i]
		local first = r.text:match("[^\n`]+") or ""
		lines[#lines + 1] = {
			indent = 1, text = ns.DisplayName(r.from) .. "  " .. Grey(first:sub(1, 60)),
			right = Grey(ns.Ago(r.t)),
			onClick = function() ns.UI.ShowCopy(L.WORKSHOP_BUG_FROM:format(ns.DisplayName(r.from)), r.text) end,
		}
	end
end

function Workshop.Build()
	local lines = {}
	if Workshop.Preview() then lines[#lines + 1] = { text = Grey(L.WORKSHOP_PREVIEW), gapAfter = true } end
	InstallLines(lines)
	RollLines(lines)
	BugLines(lines)
	return lines, L.TAB_WORKSHOP, L.WORKSHOP_HINT
end

-- The copyable report for Discord.
function Workshop.ReportText()
	local out = { "```", L.WORKSHOP_REPORT_TITLE:format(ns.VERSION, date and date("%Y-%m-%d %H:%M") or "") }
	for _, line in ipairs((Workshop.Build())) do
		local text = (line.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		local right = (line.right or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		if line.header then out[#out + 1] = "" end
		out[#out + 1] = (" "):rep(2 * (line.indent or 0)) .. text .. (right ~= "" and ("  " .. right) or "")
	end
	out[#out + 1] = "```"
	return table.concat(out, "\n")
end

function Workshop.Reports() return reports end
function Workshop.State() return roll end

-- Tests start from a clean state.
function Workshop.Reset()
	roll, authorAt, authorName = nil, nil, nil
	wipe(reports); wipe(pieces); wipe(bugsFrom); wipe(asked)
	lastRoll, lastRollAnswer, lastUpdateShown, lastBug = -math.huge, -math.huge, -math.huge, -math.huge
	changePending = false
end

ns.Comm.Handle("V1", function(...) Workshop.HandleRoll(...) end)
ns.Comm.Handle("V2", function(...) Workshop.HandleAnswer(...) end)
ns.Comm.Handle("V3", function(...) Workshop.HandleUpdate(...) end)
ns.Comm.Handle("V4", function(...) Workshop.HandlePresence(...) end)
ns.Comm.Handle("V5", function(...) Workshop.HandleBug(...) end)

ns.On("LOGIN", function()
	-- The author says he is online once on the channel, then every PRESENCE_EVERY.
	ns.After(40, "author presence", Workshop.SendPresence)
	ns.Every(Workshop.PRESENCE_EVERY, "author presence", Workshop.SendPresence)
end)
