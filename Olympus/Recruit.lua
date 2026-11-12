local ADDON, ns = ...
local L = ns.L

-- "Join Olympus", for players who are NOT in an Olympus guild yet (the only thing the addon
-- does for them). It uses the game's own /who (Who.lua), which anyone can run: find Olympus
-- members online, group them by guild, and whisper one of them a ready-made request. No answer?
-- Try someone else. Rate limited so nobody gets spammed.
--
-- Routing (1.1, Fern's #20): recruits whispered whoever /who returned, so the guild the King
-- opened stayed empty while full ones got spammed. Now the Join screen asks one member's addon
-- (J1, an addon whisper, one per search) where recruits should go: that member's census answers
-- (J2) with the King's gates, the guilds with the most free slots and a couple of their Lords
-- and Captains online. The screen lists the gates' guild first, then the most room, and asks
-- those officers. A member may flag himself do-not-contact (/oly nocontact on): his addon says so
-- when asked (J2), and the screen never offers him. The request itself stays one whisper per
-- click, the player's own words (no dues line), and goes with a J3 to the same member, whose
-- addon shows it with Invite and Decline (an officer's yes or no, one click each) instead of a
-- raw whisper. These three are the only messages the addon exchanges outside an Olympus guild
-- (Comm.WhisperOutside); versions before 1.1 ignore all three.
--
-- Whom a recruit whispers stays the server's word, as before 1.1: a J2 only orders. A member's
-- census names a guild only when the census does not mark it (Data.Dispute: two senders or more
-- agree on it, or it is ours), and a Lord or Captain only when two senders name them
-- (Data.KnownRank). The screen asks an officer the answer names only once its own /who found him
-- in that guild, lists a guild only once /who found one of its members, and shows the gates only
-- when two members' answers agree on them. One forged report, or one modified member's J2,
-- names nobody to whisper.
--   J1~1                                  which guild should I ask?
--   J2~<y|n>~<gates guild>~<seconds>~<guild>=<free>=<name>/<name>;...   the answer (n: do not contact me)
--   J3~<guild asked>~<level>~<CLASS>      my request (sent with the player's whisper)

local Recruit = {}
ns.Recruit = Recruit

local ASK_COOLDOWN = 20
local JOIN_WAIT, JOIN_REMINDER_DEFER = 45, 3
local join = {}

Recruit.ROUTE_GAP = 15      -- seconds between two J1 of the searches (an Ask click checks its own member)
Recruit.ROUTE_WAIT = 60     -- a J2 counts from a member asked this recently
Recruit.ROUTE_FRESH = 600   -- a route this recent: no new J1 at a search
Recruit.ROUTE_KEEP = 1800   -- a route is shown this long
Recruit.ROUTE_ASKS = 3      -- gates one answer named: more members asked, up to this many within ROUTE_FRESH
Recruit.ROUTE_GUILDS = 8    -- guilds in one answer, at most
Recruit.ROUTE_CONTACTS = 2  -- officers named per guild, at most
Recruit.ANSWER_EACH = 60    -- a member answers one asker at most this often...
Recruit.ANSWER_MAX = 10     -- ...and this many askers a minute in all (do not contact: a bare "no" past it)
Recruit.REQUEST_EACH = 600  -- a request from one player counts once this often
Recruit.REQUEST_TTL = 3600  -- a request is shown this long
Recruit.REQUESTS_MAX = 30   -- requests kept
Recruit.REQUESTS_SHOWN = 5  -- requests shown in the Census, the rest counted
Recruit.REQUEST_LINES = 6   -- chat lines about requests a minute, at most

Recruit.found = {}      -- list of { name, guild, level, class, zone }
Recruit.asked = {}      -- [name] = time we whispered them
Recruit.replied = {}    -- [name] = their answer
Recruit.lastAsk = 0

local routeAsked = {}   -- [Name-Realm] = when we sent them a J1
local routeAnswered = {} -- [Name-Realm] = when their J2 came
local gatesSaid = {}    -- [Name-Realm] = { guild, at, t }: the gates their J2 named (guild nil: none)
local askedKey = {}     -- [Name-Realm] = when we whispered them (Recruit.asked by the whole name)
local dnc = {}          -- [Name-Realm] = true: their addon said do not contact
local lastRoute = -math.huge

-- A name as the server stamps a sender: "Name-Realm".
local function Key(name) return name and ns.FullName(ns.Normal and ns.Normal(name) or name) or nil end
-- A value for the wire: none of the separators.
local function Field(s) return (tostring(s or ""):gsub("[~;=/|%c]", "")) end

-- Must be called from a click (the game requires a hardware event for /who). Each click
-- searches further once the game's 50 per search are not enough (see Who.lua).
function Recruit.Search()
	return ns.Who.Search()
end

---------------------------------------------------------------------------
-- The Join screen's side (not in an Olympus guild)
---------------------------------------------------------------------------

-- The gates two members' answers agree on, while open, and the seconds left; nil while no two
-- agree (one member's word is no proof: a modified addon could name any guild).
local function ConfirmedGates(now)
	local count, left, best = {}, {}, nil
	for _, s in pairs(gatesSaid) do
		if s.guild and s.at > now and now - s.t <= Recruit.ROUTE_KEEP then
			count[s.guild] = (count[s.guild] or 0) + 1
			left[s.guild] = math.max(left[s.guild] or 0, s.at - now)
		end
	end
	for guild, n in pairs(count) do
		if n >= 2 and (not best or n > count[best] or (n == count[best] and guild < best)) then best = guild end
	end
	if best then return best, math.floor(left[best]) end
	return nil, nil
end

-- A member named gates no other answer agrees on yet.
local function GatesUnconfirmed(now)
	if ConfirmedGates(now) then return false end
	for _, s in pairs(gatesSaid) do
		if s.guild and s.at > now and now - s.t <= Recruit.ROUTE_KEEP then return true end
	end
	return false
end

-- The route the members' census gave (J2), while it is recent: { gates, gatesLeft, list =
-- { { name, free, contacts } }, byName, from, t }, or nil. Its list is the last answer's, its
-- gates the ones two answers agree on.
function Recruit.Route()
	local r, now = Recruit.route, ns.Now()
	if not r or now - (r.t or 0) > Recruit.ROUTE_KEEP then return nil end
	r.gates, r.gatesLeft = ConfirmedGates(now)
	return r
end
function Recruit.NoContact(name) return dnc[Key(name)] == true end

-- Members a J1 went to within ROUTE_FRESH.
local function AskedLately(now)
	local n = 0
	for _, t in pairs(routeAsked) do
		if now - t < Recruit.ROUTE_FRESH then n = n + 1 end
	end
	return n
end

-- Asks `name`'s addon where recruits should go (J1). A search asks one member at most every
-- ROUTE_GAP, and none twice within ROUTE_FRESH; `confirm`: a second member at once, for gates
-- only one answer named. An Ask click (`check`) asks the member it is about to whisper, and
-- again whenever he did not answer our last J1 (lost, or held back while his addon was busy),
-- so a do-not-contact flag closes the question before the player sends.
local function AskRoute(name, check, confirm)
	-- (1.2.5.1: in an Olympus guild, Olympus Accord accepted or not, nobody is asked where to go.)
	if ns.InOlympusGuild() or not name then return false end
	local key, now = Key(name), ns.Now()
	local asked = routeAsked[key]
	local answered = asked and (routeAnswered[key] or -math.huge) >= asked
	if asked and now - asked < Recruit.ROUTE_FRESH and (answered or not check) then return false end
	if not check and not confirm and now - lastRoute < Recruit.ROUTE_GAP then return false end
	if not ns.Comm.WhisperOutside(ns.TellName(name), "J1~1") then return false end
	routeAsked[key] = now
	if ns.GuildCharter then ns.GuildCharter.Ask(name) end
	if not check then lastRoute = now end
	return true
end

-- One member /who found and we never asked (nor told us do not contact), asked for a route.
local function AskAnother(confirm)
	for _, p in ipairs(Recruit.found) do
		local key = Key(p.name)
		if not routeAsked[key] and not dnc[key] then return AskRoute(p.name, false, confirm) end
	end
	return false
end

-- A round of /who answered (Who.lua): every Olympus member found. Without a fresh route, one of
-- them (never asked yet) is asked for one; so is one more while only one answer named the gates
-- (ROUTE_ASKS members within ROUTE_FRESH at most).
function Recruit.OnFound(list)
	Recruit.found = list
	ns.Log("recruit: /who lists %d Olympus members", #list)
	if not ns.InOlympusGuild() then
		local r, now = Recruit.Route(), ns.Now()
		if not r or now - (r.t or 0) > Recruit.ROUTE_FRESH or (GatesUnconfirmed(now) and AskedLately(now) < Recruit.ROUTE_ASKS) then
			AskAnother()
		end
	end
	Recruit.JoinFound()
	ns.Fire("RECRUIT_CHANGED")
end
ns.Who.Listen(function(list) Recruit.OnFound(list) end)

-- J2 read: nil when it is not one. Only Olympus guilds, sizes a guild can have, a few names.
function Recruit.ParseRoute(text)
	local flag, gates, secs, list = tostring(text):match("^J2~([yn])~([^~]*)~(%d*)~([^~]*)$")
	if not flag then return nil end
	local route = { dnc = flag == "n", list = {}, byName = {} }
	if gates ~= "" and ns.IsFederation(gates) then
		route.gates, route.gatesLeft = gates, math.min(tonumber(secs) or 0, ns.Acts and ns.Acts.GATES_TIME or 7200)
	end
	for entry in list:gmatch("[^;]+") do
		local name, free, contacts = entry:match("^([^=]+)=(%d+)=?(.*)$")
		free = tonumber(free)
		if name and ns.IsFederation(name) and free and free <= ns.Codec.GUILD_CAP and not route.byName[name] and #route.list < Recruit.ROUTE_GUILDS then
			local e = { name = name, free = free, contacts = {} }
			for c in contacts:gmatch("[^/]+") do
				if #e.contacts < Recruit.ROUTE_CONTACTS + 1 and #c <= 60 then e.contacts[#e.contacts + 1] = c end
			end
			route.list[#route.list + 1] = e
			route.byName[name] = e
		end
	end
	return route
end

-- A member's answer, heard outside an Olympus guild (Comm.HandleOutside): only from one we asked.
function Recruit.OnRoute(sender, text)
	if text:sub(1, 3) == "QD~" and ns.GuildCharter then return ns.GuildCharter.OnReported(sender, text) end
	local key, now = Key(sender), ns.Now()
	if not routeAsked[key] or now - routeAsked[key] > Recruit.ROUTE_WAIT then return false end
	local route = Recruit.ParseRoute(text)
	if not route then return false end
	routeAnswered[key] = now
	-- The gates as this member says them (none, too): shown once another answer agrees (Route).
	gatesSaid[key] = { guild = route.gates, at = now + (route.gatesLeft or 0), t = now }
	local claimed = route.gates
	route.gates, route.gatesLeft = nil, nil
	if route.dnc then
		dnc[key] = true
		-- The request about to go to them: closed before the player sends it.
		local pending = Recruit.pending
		if pending and Key(pending.name) == key then
			Recruit.pending = nil
			ns.HideDialog("OLYMPUS_RECRUIT")
			ns.Print(L.RECRUIT_DNC:format(ns.DisplayName(key) or sender))
		end
	end
	-- An answer naming no guild (a do-not-contact member's bare "no") keeps what an earlier one
	-- said; its gates count all the same.
	if #route.list > 0 or not Recruit.Route() then
		route.from, route.t = key, now
		Recruit.route = route
	end
	-- Gates only one answer named: one more member asked at once, whose answer agrees or not.
	if GatesUnconfirmed(now) and AskedLately(now) < Recruit.ROUTE_ASKS then AskAnother(true) end
	ns.Log("recruit: route from %s (gates %s, %d guilds%s)", key, tostring(claimed), #route.list, route.dnc and ", do not contact" or "")
	ns.Fire("RECRUIT_CHANGED")
	return true
end
ns.Comm.HandleOutside(Recruit.OnRoute)

-- The first reported card needs an independent source. This is another bounded route ask,
-- not a chat whisper or a contact chosen by the card.
function Recruit.ConfirmCharters()
	if ns.InOlympusGuild() or AskedLately(ns.Now()) >= Recruit.ROUTE_ASKS then return false end
	return AskAnother(true)
end

-- Whom this round of /who found in `guild` by that name, or nil: the server's word that he is
-- there. A name without its realm (a member names those of his own realm so) matches by name.
local function FoundIn(name, guild)
	if type(name) ~= "string" or name == "" then return nil end
	local key, bare = Key(name), not ns.RealmOf(name)
	local short = ns.ShortName(key)
	for _, p in ipairs(Recruit.found) do
		local pk = Key(p.name)
		if p.guild == guild and (pk == key or (bare and ns.ShortName(pk) == short)) then return p end
	end
	return nil
end
local function Found(guild)
	for _, p in ipairs(Recruit.found) do
		if p.guild == guild then return true end
	end
	return false
end

-- Confirmed gates first, then corroborated charter affinity, room and /who presence.
-- A public card never supplies a new contact or invitation authority.
local function GuildLess(a, b)
	if a.gates ~= b.gates then return a.gates end
	local aa, ba = a.affinity or {}, b.affinity or {}
	for i = 1, 3 do if (aa[i] or 0) ~= (ba[i] or 0) then return (aa[i] or 0) > (ba[i] or 0) end end
	local fa, fb = a.free or -1, b.free or -1
	if fa ~= fb then return fa > fb end
	if #(a.members or {}) ~= #(b.members or {}) then return #(a.members or {}) > #(b.members or {}) end
	return a.name < b.name
end
local function RouteOrder(route)
	local out, rows, by = {}, {}, {}
	for _, g in ipairs(Recruit.Guilds()) do by[g.name] = g end
	if route.gates then
		local g = by[route.gates] or { name = route.gates, gates = true }
		rows[#rows + 1] = g
	end
	for _, e in ipairs(route.list) do
		if e.name ~= route.gates and Found(e.name) then rows[#rows + 1] = by[e.name] end
	end
	table.sort(rows, GuildLess)
	for _, g in ipairs(rows) do out[#out + 1] = g.name end
	return out
end
Recruit.RouteOrder = RouteOrder

-- Guilds seen online in the same order as the clickable route, with optional local affinity.
function Recruit.Guilds()
	local by, out = {}, {}
	for _, p in ipairs(Recruit.found) do
		local g = by[p.guild]
		if not g then
			g = { name = p.guild, members = {} }
			by[p.guild] = g
			out[#out + 1] = g
		end
		g.members[#g.members + 1] = p
	end
	local route = Recruit.Route()
	for _, g in ipairs(out) do
		local e = route and route.byName[g.name]
		g.free = e and e.free or nil
		g.gates = route and route.gates == g.name or false
		if ns.GuildCharter then g.affinity, g.charter = ns.GuildCharter.Affinity(g.name, Recruit.found) end
	end
	table.sort(out, GuildLess)
	return out
end

local function Asked(name) return Recruit.asked[name] or askedKey[Key(name)] end

-- The next member of that guild we have not asked yet (any guild if nil): its officers the
-- route named first, once /who found them in it (whispered by the server's name), then anyone
-- /who found; never one who asked not to be contacted. No guild: the visible route's order,
-- then anyone found.
function Recruit.NextContact(guild)
	local route = Recruit.Route()
	if guild then
		local e = route and route.byName[guild]
		for _, c in ipairs(e and e.contacts or {}) do
			local p = FoundIn(c, guild)
			if p and not Asked(c) and not Asked(p.name) and not dnc[Key(c)] and not dnc[Key(p.name)] then
				return { name = p.name, guild = guild, officer = true }
			end
		end
	elseif route then
		for _, name in ipairs(RouteOrder(route)) do
			local c = Recruit.NextContact(name)
			if c then return c end
		end
	end
	for _, p in ipairs(Recruit.found) do
		if (not guild or p.guild == guild) and not Asked(p.name) and not dnc[Key(p.name)] then return p end
	end
	return nil
end

-- The short Join flow uses the same discovered contacts and the same editable request as the guild list.
function Recruit.SimpleJoin()
	local guild = GetGuildInfo("player")
	return not ns.IsSecret(guild) and not ns.InOlympusGuild() and (guild == nil or guild == "")
end

local function JoinVisible()
	local U = ns.UI
	return U and U.IsShown and U.IsShown() and U.PageId and U.PageId() == "join"
end

-- The retry reminder is on unless the player turned it off; that choice is saved, so a
-- /reload or a new login keeps it.
local function JoinReminderOn()
	return not (type(ns.db) == "table" and ns.db.joinReminderOff == true)
end

function Recruit.JoinStatus()
	local left = join.request and math.max(0, math.ceil(join.request.untilAt - GetTime())) or 0
	return join.search ~= nil, left, join.request and join.request.contact, JoinReminderOn(), join.guilds == true
end

function Recruit.ToggleJoinGuilds()
	if not Recruit.SimpleJoin() then return end
	join.guilds = not join.guilds
	ns.Fire("RECRUIT_CHANGED")
end

local function JoinBusy()
	return ns.ChatLocked() or ns.QuietPresence() or ns.Quiet() or (InCombatLockdown and InCombatLockdown())
end

local function ScheduleJoinReminder(request, reminder)
	local function Remind()
		if join.reminder ~= reminder or join.request ~= request or request.reminded
			or not Recruit.SimpleJoin() or ns.Dialog.missing then return end
		if JoinBusy() or join.search or ns.Dialog.Find("OLYMPUS_RECRUIT") then
			ns.After(JOIN_REMINDER_DEFER, "join reminder", Remind)
			return
		end
		local popup = ns.Dialog.Show("OLYMPUS_RECRUIT_RETRY", nil, nil, request)
		if popup then
			request.reminded = true
			ns.Dialog.CloseOnEscape(popup)
		end
	end
	ns.After(math.max(0, request.untilAt - GetTime()), "join reminder", Remind)
end

local function JoinWait(contact)
	if not Recruit.SimpleJoin() then return end
	if not ns.Dialog.missing then ns.Dialog.Hide("OLYMPUS_RECRUIT_RETRY") end
	local request = { contact = contact, untilAt = GetTime() + JOIN_WAIT }
	join.request = request
	if JoinReminderOn() then
		join.reminder = join.reminder or {}
		ScheduleJoinReminder(request, join.reminder)
	end
	local function Tick()
		if join.request ~= request or not Recruit.SimpleJoin() then return end
		if JoinVisible() then ns.Fire("RECRUIT_CHANGED") end
		if request.untilAt > GetTime() then ns.After(1, "join countdown", Tick) end
	end
	ns.After(1, "join countdown", Tick)
end

function Recruit.JoinFound()
	if not join.search then return end
	join.search = nil
	if Recruit.SimpleJoin() and JoinVisible() and not ns.ChatLocked() then
		local contact = Recruit.NextContact()
		if contact then Recruit.Prompt(contact) end
	end
end

function Recruit.RequestJoin()
	if not Recruit.SimpleJoin() or join.search or ns.ChatLocked() then return false end
	if join.request and join.request.untilAt > GetTime() then return false end
	local contact = Recruit.NextContact()
	if contact then return Recruit.Prompt(contact) ~= nil end
	local search = {}
	join.search = search
	if not Recruit.Search() then join.search = nil; return false end
	ns.After(ns.Who.TIMEOUT + 0.25, "join search", function()
		if join.search ~= search then return end
		join.search = nil
		ns.Fire("RECRUIT_CHANGED")
	end)
	ns.Fire("RECRUIT_CHANGED")
	return true
end

function Recruit.ToggleJoinReminder()
	if not Recruit.SimpleJoin() then return end
	if JoinReminderOn() then
		if type(ns.db) == "table" then ns.db.joinReminderOff = true end
		join.reminder = nil
		if not ns.Dialog.missing then ns.Dialog.Hide("OLYMPUS_RECRUIT_RETRY") end
	else
		if type(ns.db) == "table" then ns.db.joinReminderOff = nil end
		join.reminder = {}
		if join.request then ScheduleJoinReminder(join.request, join.reminder) end
	end
	ns.Fire("RECRUIT_CHANGED")
end

function Recruit.Message(contact)
	local level = UnitLevel("player")
	local className = UnitClass("player") or ""
	return L.RECRUIT_MESSAGE:format(contact.guild, level, className)
end

-- Sends the (edited) request: one whisper, from the popup's Send button, i.e. by the player; its
-- J3 goes with it to the same member, so an officer's addon shows it with Invite and Decline.
function Recruit.Ask(contact, message)
	local now = GetTime()
	if now - Recruit.lastAsk < ASK_COOLDOWN then
		ns.Print(L.RECRUIT_WAIT:format(math.ceil(ASK_COOLDOWN - (now - Recruit.lastAsk))))
		return false
	end
	if not contact or not message or message == "" then return false end
	if dnc[Key(contact.name)] then
		ns.Print(L.RECRUIT_DNC:format(ns.DisplayName(Key(contact.name)) or contact.name))
		return false
	end
	Recruit.lastAsk = now
	Recruit.asked[contact.name] = ns.Now()
	askedKey[Key(contact.name)] = ns.Now()
	Recruit.lastContact = contact
	Recruit.pending = nil
	local to = ns.TellName(contact.name)
	SendChatMessage(message:sub(1, 250), "WHISPER", nil, to) -- gp:roster-actions
	local _, classFile = UnitClass("player")
	ns.Comm.WhisperOutside(to, ("J3~%s~%d~%s"):format(Field(contact.guild), tonumber(UnitLevel("player")) or 0, Field(classFile)))
	ns.Log("recruit: asked %s <%s>", contact.name, contact.guild)
	JoinWait(contact)
	ns.Fire("RECRUIT_CHANGED")
	return true
end

-- The request to `contact`, written in a box the player can edit (Send is the click), and that
-- member's addon asked first whether they take recruit whispers.
function Recruit.Prompt(contact)
	if not contact then return nil end
	if ns.Dialog.missing then ns.Print(L.RESTART_NEEDED) return nil end
	Recruit.pending = contact
	AskRoute(contact.name, true)
	-- Forever's guild-rank update walks StaticPopup_Hide even with its guild window
	-- closed, then calls Blizzard-only Discord functions. A native recruit popup
	-- taints that shared state before the player's invitation arrives (70790).
	-- Keep the editable request in our own window in both input modes.
	local f = ns.Dialog.Show("OLYMPUS_RECRUIT", contact.name, contact.guild, contact)
	ns.Dialog.CloseOnEscape(f)
	return f
end

function Recruit.PromptNext(guild)
	local contact = Recruit.NextContact(guild)
	if not contact then
		ns.Print(#Recruit.found == 0 and L.RECRUIT_SEARCH_FIRST or L.RECRUIT_NOBODY_LEFT)
		return
	end
	return Recruit.Prompt(contact)
end

-- The tone of the Join screen, in the spirit of Olympus: other guilds should not exist.
function Recruit.Roast()
	local guild = GetGuildInfo("player")
	if guild and guild ~= "" then
		return L.ROAST_GUILD:format(guild), L.ROAST_GUILD_SUB
	end
	return L.ROAST_NOGUILD, L.ROAST_NOGUILD_SUB
end

-- Once a day, a reminder in chat for players outside Olympus (1.2.5.1: never for a member of an
-- Olympus guild who has not accepted the Olympus Accord yet: the Accord asks him, Accord.lua).
local function DailyNag()
	if ns.InOlympusGuild() then return end
	local today = date("%Y-%m-%d")
	if ns.db.lastNag == today then return end
	ns.db.lastNag = today
	local header, sub = Recruit.Roast()
	ns.Print("|cffff4040" .. header .. "|r " .. sub .. " |cffffd200/oly|r")
end

---------------------------------------------------------------------------
-- The members' side (in an Olympus guild)
---------------------------------------------------------------------------

-- Do not contact (Fern's #20): recruits' addons are told, and never offer us.
function Recruit.NoContactMe() return ns.db and ns.db.recruitsOff == true end
function Recruit.SetNoContact(on)
	ns.db.recruitsOff = on and true or nil
	ns.Print(on and L.NOCONTACT_ON or L.NOCONTACT_OFF)
	ns.Fire("DATA_CHANGED")
end

-- The guilds with room we name to recruits, the most free slots first: those the census does
-- not mark (Data.Dispute: two senders or more agree on them; ours, our roster, never is). A
-- guild one sender alone stands behind, or whose senders disagree, is nobody's advice.
function Recruit.OpenGuilds()
	local out = {}
	for _, o in ipairs(ns.Views.OpenGuilds(ns.Data.Summary())) do
		if ns.Data.Dispute(o.e.g) == nil then out[#out + 1] = o end
	end
	return out
end

-- Up to ROUTE_CONTACTS Lords and Captains online of a guild with room, to name to a recruit:
-- our own guild's from our roster. Another keeps the old two-report census rule until signed
-- enforcement is explicitly activated, then comes only from that manifest. Never the King
-- (the most asked of all), and never ourselves while
-- we ask not to be contacted.
local function Contacts(o, own)
	local g, out = o.e.g, {}
	local function Add(name, realm)
		if #out >= Recruit.ROUTE_CONTACTS or type(name) ~= "string" or name == "" then return end
		local full = ns.FullName(name, realm)
		if ns.IsKingCharacter and ns.IsKingCharacter(name) then return end
		if full == ns.me and Recruit.NoContactMe() then return end
		out[#out + 1] = Field(ns.DisplayName(full))
	end
	if own and o.name == own then
		for _, m in ipairs(ns.Roster.online or {}) do
			if (m.rankIndex or 9) <= ns.CAPTAIN_RANK then Add(m.name) end
		end
	else
		local function Named(name, rank)
			if type(name) ~= "string" or name == "" then return false end
			local k, source, senders = ns.Data.AuthorizedRank(ns.FullName(name, g.realm), o.name)
			return k == rank and (source ~= "census" or (senders or 0) >= 2)
		end
		if g.leaderOnline and Named(g.leader, 0) then Add(g.leader, g.realm) end
		for _, of in ipairs(g.officers or {}) do
			if of.online and Named(of.name, 1) then Add(of.name, g.realm) end
		end
	end
	return out
end

-- Our answer to a J1: our flag, the gates, and the guilds with the most room (the gates' first),
-- as many as fit one addon message.
function Recruit.RouteAnswer()
	local gates = ns.Acts and ns.Acts.Gates and ns.Acts.Gates()
	local msg = ("J2~%s~%s~%d~"):format(Recruit.NoContactMe() and "n" or "y", gates and Field(gates.guild) or "",
		gates and math.max(0, math.floor(gates.at - ns.Now())) or 0)
	local open = Recruit.OpenGuilds()
	for i, o in ipairs(open) do
		if gates and o.name == gates.guild then
			table.insert(open, 1, table.remove(open, i))
			break
		end
	end
	local own, n = GetGuildInfo("player"), 0
	for _, o in ipairs(open) do
		local entry = Field(o.name) .. "=" .. o.free .. "=" .. table.concat(Contacts(o, own), "/")
		local add = (n > 0 and ";" or "") .. entry
		if #msg + #add <= 250 then
			msg, n = msg .. add, n + 1
			if n >= Recruit.ROUTE_GUILDS then break end
		end
	end
	return msg
end

-- Our answer to a J1, ANSWER_MAX a minute in all. Do not contact holds whatever the load: past
-- ANSWER_MAX we still answer each asker once a minute, a bare "no" (outside the count), or the
-- recruit's screen, left without an answer, would offer us.
Recruit.DNC_ANSWER = "J2~n~~0~"
local answeredAt, answers = {}, {} -- [asker] = when; times of our answers this last minute
function Recruit.OnRouteAsk(dist, sender, text)
	if dist ~= "WHISPER" or not ns.IsMember() then return false end
	local now = ns.Now()
	if answeredAt[sender] and now - answeredAt[sender] < Recruit.ANSWER_EACH then return false end
	for i = #answers, 1, -1 do
		if now - answers[i] >= 60 then table.remove(answers, i) end
	end
	local room = #answers < Recruit.ANSWER_MAX
	if not room and not Recruit.NoContactMe() then return false end
	for name, t in pairs(answeredAt) do
		if now - t >= Recruit.ANSWER_EACH then answeredAt[name] = nil end
	end
	answeredAt[sender] = now
	if room then answers[#answers + 1] = now end
	ns.Comm.Whisper(sender, room and Recruit.RouteAnswer() or Recruit.DNC_ANSWER, nil, true)
	ns.Log("recruit: told %s %s", sender, room and "where to go" or "do not contact")
	return true
end
ns.Comm.Handle("J1", Recruit.OnRouteAsk)

-- Join requests (J3) to us: newest last. { name, guild, level, class, t, text }
Recruit.requests = {}
local requestAt, lineTimes, whispers = {}, {}, {}
local recruitingGuild, lastOutreach, lastReplyPrompt
local PromptReply, replyTimer
local contacted = {}

local function WhisperGuild()
	if ns.IsMember() then return GetGuildInfo("player") end
end

function Recruit.WhisperAvailable()
	return WhisperGuild() ~= nil
end

local function EligibleRecruitingGuild()
	local guild = WhisperGuild()
	if type(guild) == "string" and not ns.IsSecret(guild) and guild ~= ""
		and Recruit.CanInvite and Recruit.CanInvite() then return guild end
end

local function Recruiting()
	return recruitingGuild ~= nil and recruitingGuild == EligibleRecruitingGuild()
end

Recruit.IsWhisperRecruiting = Recruiting

-- Realm-group and faction storage already comes from rdb. Within it, retain one
-- exact guild choice for this character. Requests, drafts and handoffs stay in memory.
local function RecruitmentPreference(guild, create)
	if type(ns.rdb) ~= "table" or type(ns.me) ~= "string" or ns.me == "" or ns.me == "?" then return end
	local choices = ns.rdb.recruitmentPreference
	if type(choices) ~= "table" then
		if not create then return end
		choices = {}
		ns.rdb.recruitmentPreference = choices
	end
	local saved = choices[ns.me]
	if type(saved) == "table" and (not guild or saved.guild == guild) then return saved end
	if not create then return end
	saved = { guild = guild }
	choices[ns.me] = saved
	return saved
end

-- This character's saved choices for the guild it recruits for now (the scan and handoff
-- switches keep theirs here too), or nil while it does not recruit.
function Recruit.Preference(create)
	if not recruitingGuild then return nil end
	return RecruitmentPreference(recruitingGuild, create)
end

local function QueueOnly()
	local saved = recruitingGuild and RecruitmentPreference(recruitingGuild)
	return saved ~= nil and saved.queueOnly == true
end

local function ToggleQueueOnly()
	if not Recruiting() then return end
	local saved = RecruitmentPreference(recruitingGuild, true)
	if not saved then return end
	saved.queueOnly = not (saved.queueOnly == true)
	if saved.queueOnly then replyTimer = nil else PromptReply() end
	ns.Fire("RECRUIT_CHANGED")
end

local function CloseReminderDraft()
	local draft = ns.Dialog and ns.Dialog.Find and ns.Dialog.Find("OLYMPUS_RECRUIT_ANNOUNCEMENT")
	if draft and draft.data and draft.data.reminder then draft:Hide() end
end

local function StopRecruiting()
	recruitingGuild = nil
	replyTimer = nil
	CloseReminderDraft()
	if Recruit.Handoff then Recruit.Handoff.Reset() end
	if Recruit.Candidates then Recruit.Candidates.Reset() end
	for i = #Recruit.requests, 1, -1 do
		if Recruit.requests[i].viaWhisper then table.remove(Recruit.requests, i) end
	end
	if ns.Dialog and ns.Dialog.Find then
		for _, id in ipairs({ "OLYMPUS_RECRUIT_OUTREACH", "OLYMPUS_RECRUIT_REPLY", "OLYMPUS_RECRUIT_INVITE_DRAFT" }) do
			local draft = ns.Dialog.Find(id)
			if draft then draft:Hide() end
		end
		local warning = ns.Dialog.Find("OLYMPUS_RECRUIT_NETOFF")
		if warning and warning.data and warning.data.req and warning.data.req.viaWhisper then warning:Hide() end
	end
end

local function RestoreRecruiting()
	local saved = RecruitmentPreference()
	if not recruitingGuild and (not saved or saved.enabled ~= true) then return end
	local guild = EligibleRecruitingGuild()
	local restore = saved and saved.enabled == true and saved.guild == guild and guild or nil
	if restore ~= recruitingGuild then
		if recruitingGuild then StopRecruiting() end
		recruitingGuild = restore
		ns.Fire("DATA_CHANGED")
	end
	-- The scan and handoff switches come back with recruiting, after a /reload or a login.
	if recruitingGuild and saved then
		if Recruit.Handoff and Recruit.Handoff.Restore then Recruit.Handoff.Restore(saved) end
		if Recruit.Candidates and Recruit.Candidates.Restore then Recruit.Candidates.Restore(saved) end
	end
end

function Recruit.ToggleWhisperRecruiting()
	local guild = EligibleRecruitingGuild()
	if not guild then return false end
	local on = recruitingGuild ~= guild
	StopRecruiting()
	local saved = RecruitmentPreference(guild, true)
	if saved then saved.enabled = on end
	if on then recruitingGuild = guild end
	ns.Fire("DATA_CHANGED")
	return on
end

function Recruit.CanEnableWhisperRecruiting()
	local guild = EligibleRecruitingGuild()
	return guild ~= nil and recruitingGuild ~= guild
end

function Recruit.ShouldOfferWhisperRecruiting()
	local guild = EligibleRecruitingGuild()
	return guild ~= nil and recruitingGuild ~= guild and RecruitmentPreference(guild) == nil
end

function Recruit.EnableWhisperRecruiting()
	if not Recruit.CanEnableWhisperRecruiting() or not Recruit.ToggleWhisperRecruiting() then return false end
	ns.Print(L.RECRUIT_CENSUS_ENABLED)
	return true
end

local function NameForCommand(name)
	local to = ns.TellName(name)
	if type(to) ~= "string" or #to > 120 or not to:find("[%a\128-\255]")
		or to:find("[^%a%d\128-\255 %-]") then return nil end
	return to
end

-- A native unit token the client currently sees. A nil guild is only "no guild shown".
-- No /who, position cache, addon transport or native frame is involved.
Recruit.CandidateCommandName = NameForCommand

local function NearbyPlayer(unit)
	local exists = UnitExists(unit)
	if issecretvalue and issecretvalue(exists) then return nil, nil, "unknown" end
	if not exists then return nil, nil, "absent" end
	local player, visible, friendly = UnitIsPlayer(unit), UnitIsVisible(unit), UnitIsFriend("player", unit)
	if issecretvalue and (issecretvalue(player) or issecretvalue(visible) or issecretvalue(friendly)) then
		return nil, nil, "unknown"
	end
	if not player then return nil, nil, "other" end
	if not visible or not friendly then return nil, nil, "unfriendly" end
	local guidOK, guid = pcall(UnitGUID, unit)
	local self = UnitGUID("player")
	local guildOK, guild = pcall(GetGuildInfo, unit)
	local faction, mine = UnitFactionGroup(unit), UnitFactionGroup("player")
	if not guidOK or not guildOK or (issecretvalue and (issecretvalue(guid) or issecretvalue(self)
		or issecretvalue(guild) or issecretvalue(faction) or issecretvalue(mine))) then
		return nil, nil, "unknown"
	end
	if guild and guild ~= "" then return nil, nil, "guild" end
	if type(guid) ~= "string" or guid:sub(1, 7) ~= "Player-" or not faction or not mine or guild == "" then
		return nil, nil, "unknown"
	end
	if guid == self then return nil, nil, "other" end
	if faction ~= mine then return nil, nil, "unfriendly" end
	local nameOK, fullName = pcall(ns.UnitFullName, unit)
	local name = nameOK and NameForCommand(fullName)
	if not name then return nil, nil, "unknown" end
	return name, guid, nil, fullName
end
Recruit.ReadCandidateUnit = NearbyPlayer

local function RecentlyContacted(name, now)
	local at = contacted[name:lower()]
	return at and now - at < Recruit.REQUEST_EACH
end

local function OutreachQueue()
	local queue, seen, now = { index = 1 }, {}, ns.Now()
	local counts = { target = 0, mouseover = 0, plates = 0, other = 0, guild = 0, unfriendly = 0,
		unknown = 0, contacted = 0, duplicate = 0 }
	for who, at in pairs(contacted) do
		if now - at >= Recruit.REQUEST_EACH then contacted[who] = nil end
	end
	local function Add(unit, source)
		local name, guid, why = NearbyPlayer(unit)
		if why == "absent" then return end
		counts[source] = counts[source] + 1
		if why then counts[why] = counts[why] + 1; return end
		if seen[guid] then counts.duplicate = counts.duplicate + 1; return end
		seen[guid] = true
		if RecentlyContacted(name, now) then counts.contacted = counts.contacted + 1; return end
		queue[#queue + 1] = { name = name, guid = guid, unit = unit }
	end
	Add("target", "target")
	Add("mouseover", "mouseover")
	-- The game hands out numbered tokens, including indices over 40 in a busy area.
	for i = 1, ns.API and ns.API.NAMEPLATE_MAX or 200 do Add("nameplate" .. i, "plates") end
	return queue, counts
end

local function SameOutreachPlayer(recipient)
	local name, guid = NearbyPlayer(recipient.unit)
	return name == recipient.name and guid == recipient.guid
end

local function OutreachTitle(queue)
	return L.RECRUIT_WHISPER_CONFIRM:format(queue[queue.index].name)
end

function Recruit.PromptOutreach()
	if not Recruiting() then return false end
	if ns.ChatLocked() then ns.Print(L.WHISPER_LOCKDOWN) return false end
	local queue, seen = OutreachQueue()
	ns.Print(L.RECRUIT_WHISPER_SCAN:format(seen.target, seen.mouseover, seen.plates, #queue))
	if seen.other + seen.guild + seen.unfriendly + seen.unknown + seen.contacted + seen.duplicate > 0 then
		ns.Print(L.RECRUIT_WHISPER_FILTERS:format(seen.guild, seen.unfriendly, seen.other, seen.unknown, seen.contacted, seen.duplicate))
	end
	if #queue == 0 then ns.Print(L.RECRUIT_WHISPER_EMPTY) return false end
	if not ns.Dialog or ns.Dialog.missing then ns.Print(L.RESTART_NEEDED) return false end
	local f = ns.Dialog.Show("OLYMPUS_RECRUIT_OUTREACH", OutreachTitle(queue), nil, { queue = queue, guild = recruitingGuild })
	return f ~= nil
end

function Recruit.PromptCandidateWhisper(candidate)
	local unit = Recruit.Candidates.Check(candidate, true)
	if not unit or RecentlyContacted(candidate.name, ns.Now()) or not ns.Dialog or ns.Dialog.missing then return false end
	if ns.Dialog.Find("OLYMPUS_RECRUIT_OUTREACH") then return false end
	local queue = { index = 1, { name = candidate.name, guid = candidate.guid, unit = unit } }
	return ns.Dialog.Show("OLYMPUS_RECRUIT_OUTREACH", OutreachTitle(queue), nil,
		{ queue = queue, guild = recruitingGuild, candidate = candidate }) ~= nil
end

local function SendOutreach(f, data)
	if not ns.Gate.Allowed("roster-actions") then return false end
	local queue = type(data) == "table" and data.queue
	local recipient = type(queue) == "table" and queue[queue.index]
	if not recipient or data.guild ~= recruitingGuild or not Recruiting() or ns.ChatLocked()
		or (data.candidate and not Recruit.Candidates.Check(data.candidate, true))
		or not SameOutreachPlayer(recipient) then
		ns.Print(L.RECRUIT_WHISPER_TARGET_REQUIRED)
		return false
	end
	local now, text = ns.Now(), f.editBox:GetText():match("^%s*(.-)%s*$")
	if text == "" then return false end
	if (lastOutreach and now - lastOutreach < ASK_COOLDOWN) or RecentlyContacted(recipient.name, now) then
		ns.Print(L.RECRUIT_WHISPER_WAIT)
		return false
	end
	local ok, sent = pcall(ns.SayTo, recipient.name, text)
	if not ok or not sent then ns.Print(L.RECRUIT_WHISPER_SEND_FAILED) return false end
	contacted[recipient.name:lower()], lastOutreach = now, now
	return true
end

local function AdvanceOutreach(f, queue)
	if type(queue) ~= "table" or type(queue.index) ~= "number" or ns.ChatLocked() then return false end
	for i = queue.index + 1, #queue do
		local nextPlayer = queue[i]
		if not RecentlyContacted(nextPlayer.name, ns.Now()) and SameOutreachPlayer(nextPlayer) then
			queue.index = i
			f.text:SetText(OutreachTitle(queue))
			f.editBox:SetText(L.RECRUIT_WHISPER_MESSAGE)
			return true
		end
	end
	return false
end

local function ConfirmOutreach(f, data)
	if not SendOutreach(f, data) then return true end
	return AdvanceOutreach(f, data.queue)
end

StaticPopupDialogs["OLYMPUS_RECRUIT_OUTREACH"] = {
	text = "%s",
	button1 = SEND_LABEL or "Send",
	button2 = L.RECRUIT_WHISPER_NEXT,
	button3 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 380,
	maxLetters = 250,
	maxBytes = 251,
	OnShow = function(f) f.editBox:SetText(L.RECRUIT_WHISPER_MESSAGE) end,
	OnAccept = ConfirmOutreach,
	EditBoxOnEnterPressed = function(editBox, data)
		local f = editBox:GetParent()
		if not ConfirmOutreach(f, data) then f:Hide() end
	end,
	OnCancel = function(f, data, reason)
		if reason == "clicked" and type(data) == "table" then return AdvanceOutreach(f, data.queue) end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- Check the joined channel when preparing the draft and again on an explicit Post click.
local reminderIndex, reminderTimer, announcementVariant = 1, nil, 0
local REMINDER_MINUTES = { 0, 2, 5, 10, 15, 30 }
local ANNOUNCEMENT_GAP = 120
local publicRecruitmentAt = {}
local lastAnnouncement
local rotateReminder, lastReminderChannel = true, nil

local function PruneAnnouncements(now)
	for name, entry in pairs(publicRecruitmentAt) do
		if now - entry.at >= ANNOUNCEMENT_GAP then publicRecruitmentAt[name] = nil end
	end
end

local function AnnouncementReady(name, silent)
	local now = ns.Now()
	PruneAnnouncements(now)
	local entry = publicRecruitmentAt[name]
	if not entry then return true end
	if not silent then
		local tip = entry.observed and L.RECRUIT_ANNOUNCE_WAIT or L.RECRUIT_ANNOUNCE_POST_WAIT
		ns.Print(tip:format(math.ceil(ANNOUNCEMENT_GAP - (now - entry.at))))
	end
	return false
end

local function PublicChannels()
	local infoOf = C_ChatInfo and C_ChatInfo.GetChannelInfoFromIdentifier
	if type(GetChannelList) ~= "function" or type(infoOf) ~= "function" then return {} end
	local ok, list = pcall(function() return { GetChannelList() } end)
	if not ok or ns.IsSecret(list[3]) then return {} end
	local rows, stride = {}, type(list[3]) == "boolean" and 3 or 2
	for i = 1, #list, stride do
		local id, name, disabled = list[i], list[i + 1], stride == 3 and list[i + 2]
		if not ns.IsSecret(id, name, disabled) and type(id) == "number" and id > 0 and id == math.floor(id)
			and type(name) == "string" and name ~= "" and not name:lower():match("^olympus") and not disabled then
			local got, info = pcall(infoOf, name)
			local zoneID = got and not ns.IsSecret(info) and type(info) == "table" and info.zoneChannelID
			if not ns.IsSecret(zoneID) and type(zoneID) == "number" and zoneID > 0 then
				rows[#rows + 1] = { id = id, name = name, zoneID = zoneID }
			end
		end
	end
	table.sort(rows, function(a, b) return a.id < b.id end)
	return rows
end

local function CurrentPublicChannel(channel)
	for _, current in ipairs(PublicChannels()) do
		if current.id == channel.id and current.name == channel.name and current.zoneID == channel.zoneID then
			return current
		end
	end
end

local function AnnouncementCount()
	local total, groups = 0, 0
	-- The same census rows the All Servers page uses. Only the fresh, accepted subset can
	-- support a public lower bound, and the unit is characters rather than estimated people.
	for _, row in ipairs(ns.Data.Groups().rows) do
		if row.counted and row.fresh and row.validation == "accepted" and row.src ~= "heard" and row.era ~= "beta" then
			local n = tonumber(row.characters)
			if n and n > 0 then total, groups = total + n, groups + 1 end
		end
	end
	local step = total > 1000 and 1000 or 100
	local lower = math.floor((total - 1) / step) * step
	if lower <= 0 then return nil end
	local number = tostring(lower):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return (groups > 1 and L.RECRUIT_ANNOUNCE_COUNT_GROUPS or L.RECRUIT_ANNOUNCE_COUNT_LOCAL):format(number)
end

local function AnnouncementText(guild)
	local name = NameForCommand(ns.me)
	local destination = ns.Codec.SanitizeChat(guild)
	local opening = L.RECRUIT_ANNOUNCE_OPENING:format(destination)
	local line = opening
	if name and announcementVariant == 1 then line = L.RECRUIT_ANNOUNCE_OPENING_NAMED:format(name, destination)
	elseif name and announcementVariant == 2 then line = L.RECRUIT_ANNOUNCE_OPENING_PLAY:format(destination, name) end
	local count = AnnouncementCount()
	local suffix = destination:lower():match("%f[%a]olympus%f[%A]") and "" or " Part of Olympus."
	suffix = suffix .. (count and " " .. count or "") .. " " .. L.RECRUIT_ANNOUNCE_JOIN
	if #line + #suffix > 255 then line = opening end
	return line .. suffix
end

-- The native channel index and zone ID must both agree with a channel WoW exposes as joined.
-- Keep only a timestamp per local channel. Neither the text nor the speaker is retained.
local function ObserveAnnouncement(text, _, _, _, _, _, zoneID, index)
	if ns.IsSecret(text, zoneID, index) or type(text) ~= "string" or #text > 255
		or type(zoneID) ~= "number" or zoneID <= 0 or type(index) ~= "number" or index <= 0 then return end
	local lower = text:lower()
	if not lower:match("%f[%a]olympus%f[%A]") then return end
	local reply = lower:match("%f[%a]whisper%f[%A]") or lower:match("%f[%a]reply%f[%A]")
	local keyword = reply and lower:match("%f[%a]join%f[%A]")
	local recruiting = (reply or lower:match("%f[%a]pst%f[%A]")) and lower:match("%f[%a]recruiting%f[%A]")
	if not keyword and not recruiting then return end
	if not WhisperGuild() then return end
	local now = ns.Now()
	PruneAnnouncements(now)
	for _, current in ipairs(PublicChannels()) do
		if current.id == index and current.zoneID == zoneID then
			local channel = current.name:lower()
			publicRecruitmentAt[channel] = { at = now, observed = true }
			local draft = ns.Dialog and ns.Dialog.Find("OLYMPUS_RECRUIT_ANNOUNCEMENT")
			if draft and type(draft.data) == "table" and draft.data.channel == channel then
				draft:Hide()
				ns.Print(L.RECRUIT_ANNOUNCE_WAIT:format(ANNOUNCEMENT_GAP))
			end
			return
		end
	end
end

local function CopyAnnouncement(channel, reminder)
	local guild = WhisperGuild()
	if not guild or not ns.Dialog or ns.Dialog.missing then return false end
	local current = CurrentPublicChannel(channel)
	if not current then
		if not reminder then
			ns.Print(L.RECRUIT_ANNOUNCE_CHANNEL_CHANGED)
			ns.Fire("DATA_CHANGED")
		end
		return false
	end
	local name = current.name:lower()
	if not AnnouncementReady(name, reminder) then return false end
	local message = AnnouncementText(guild)
	local draft = ns.Dialog.Show("OLYMPUS_RECRUIT_ANNOUNCEMENT", ns.Codec.SanitizeChat(current.name), nil,
		{ channel = name, public = current, guild = guild, message = message, command = ("/%d %s"):format(current.id, message), reminder = reminder })
	if not draft then return false end
	if not reminder then lastAnnouncement = { public = current, guild = guild } end
	announcementVariant = (announcementVariant + 1) % 3
	return true
end

local function ReminderAllowed()
	return Recruiting() and not ns.QuietPresence() and not ns.Quiet() and not ns.ChatLocked()
		and not (InCombatLockdown and InCombatLockdown()) and not (IsInInstance and IsInInstance())
end

local function PostAnnouncement(f, draft, reason) -- gp:recruit-public-post
	if reason ~= "clicked" and reason ~= "enter" then return end
	if not ns.Gate.Allowed("recruit-public-post") then return true end
	if type(draft) ~= "table" or not draft.public or draft.guild ~= WhisperGuild() or not CurrentPublicChannel(draft.public) then
		ns.Print(L.RECRUIT_ANNOUNCE_CHANNEL_CHANGED)
		return true
	end
	if draft.reminder and not ReminderAllowed() then return end
	if not AnnouncementReady(draft.channel) then return true end
	local send = C_ChatInfo and C_ChatInfo.SendChatMessage
	if type(send) ~= "function" or ns.ChatLocked() then
		ns.Print(L.RECRUIT_ANNOUNCE_POST_FALLBACK)
		return true
	end
	if f.editBox:GetText() ~= draft.command then
		ns.Print(L.RECRUIT_ANNOUNCE_POST_EDITED)
		return true
	end
	-- The API returns no delivery result. Reserve this channel before the call in case
	-- the game supplies its chat echo immediately. A successful call keeps the draft copyable.
	local attempt = { at = ns.Now() }
	publicRecruitmentAt[draft.channel] = attempt
	local ok = pcall(send, draft.message, "CHANNEL", nil, tostring(draft.public.id))
	if not ok and publicRecruitmentAt[draft.channel] == attempt then
		publicRecruitmentAt[draft.channel] = nil
		ns.Print(L.RECRUIT_ANNOUNCE_POST_FALLBACK)
	elseif publicRecruitmentAt[draft.channel] == attempt then
		ns.Print(L.RECRUIT_ANNOUNCE_POST_CHECK)
	end
	if ok and draft.reminder and f.data == draft then f:Hide() end
	return true
end

StaticPopupDialogs["OLYMPUS_RECRUIT_ANNOUNCEMENT"] = {
	text = L.RECRUIT_ANNOUNCE_COPY,
	button1 = L.RECRUIT_WHISPER_CLOSE,
	button2 = L.RECRUIT_ANNOUNCE_POST,
	OnButton2 = PostAnnouncement,
	EditBoxOnEnterPressed = function(box, draft)
		if box:HasFocus() then PostAnnouncement(box:GetParent(), draft, "enter") end
	end,
	hasEditBox = true,
	editBoxWidth = 470,
	OnShow = function(f, draft)
		f.editBox:SetText(draft.command)
		if not draft.reminder then
			ns.Focus(f.editBox)
			f.editBox:HighlightText()
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function RemindAnnouncement()
	if not ReminderAllowed() or not ns.Dialog or ns.Dialog.missing then return end
	if ns.Dialog.Find("OLYMPUS_RECRUIT_ANNOUNCEMENT") then return end
	if rotateReminder then
		local channels = PublicChannels()
		local last = 0
		for i, row in ipairs(channels) do
			if row.name == lastReminderChannel then last = i; break end
		end
		for offset = 1, #channels do
			local row = channels[(last + offset - 1) % #channels + 1]
			if CopyAnnouncement(row, true) then
				lastReminderChannel = row.name
				return
			end
		end
		return
	end
	if lastAnnouncement and lastAnnouncement.guild == recruitingGuild then
		CopyAnnouncement(lastAnnouncement.public, true)
	else
		ns.Print(L.RECRUIT_ANNOUNCE_REMIND)
	end
end

local function SetReminder(index)
	if reminderIndex == index then return end
	if reminderTimer then reminderTimer.Cancel(); reminderTimer = nil end
	CloseReminderDraft()
	reminderIndex = index
	local minutes = REMINDER_MINUTES[index]
	if minutes > 0 then
		reminderTimer = ns.Every(minutes * 60, "recruiting reminder", RemindAnnouncement)
	end
	ns.Fire("DATA_CHANGED")
end

local function AnnouncementLines(lines, V)
	lines[#lines + 1] = { text = L.RECRUIT_ANNOUNCE_OPEN, header = true }
	local rows = PublicChannels()
	if #rows == 0 then lines[#lines + 1] = { indent = 1, text = V.Grey(L.RECRUIT_ANNOUNCE_NO_CHANNELS) } end
	for _, row in ipairs(rows) do
		lines[#lines + 1] = { indent = 1, text = V.Gold(L.RECRUIT_ANNOUNCE_CHANNEL:format(row.id, ns.Codec.SanitizeChat(row.name))),
			onClick = function() CopyAnnouncement(row) end }
	end
	local intervals = {}
	for index, minutes in ipairs(REMINDER_MINUTES) do
		intervals[index] = {
			text = minutes == 0 and L.RECRUIT_ANNOUNCE_REMINDER_OFF or L.RECRUIT_ANNOUNCE_REMINDER_ON:format(minutes),
			selected = reminderIndex == index, onClick = function() SetReminder(index) end,
		}
	end
	lines[#lines + 1] = { id = "recruit-announcement-reminder", spaceBefore = 6,
		filters = { { label = L.RECRUIT_ANNOUNCE_REMINDER_TITLE, value = intervals[reminderIndex].text, options = intervals } } }
	local minutes = REMINDER_MINUTES[reminderIndex]
	if minutes > 0 then
		lines[#lines + 1] = { indent = 1, text = V.Grey(L.RECRUIT_ANNOUNCE_REMINDER_PREVIEW:format(minutes)) }
	end
	lines[#lines + 1] = { indent = 1, gapAfter = true,
		text = V.Grey(rotateReminder and L.RECRUIT_ANNOUNCE_REMINDER_ROTATE or L.RECRUIT_ANNOUNCE_REMINDER_SELECTED),
		tooltip = function(tt) tt:AddLine(L.RECRUIT_ANNOUNCE_REMINDER_TIP, 1, 1, 1, true) end,
		onClick = function()
			rotateReminder, lastReminderChannel = not rotateReminder, nil
			CloseReminderDraft()
			ns.Fire("DATA_CHANGED")
		end }
end

function Recruit.WhisperLines()
	if not WhisperGuild() then return {} end
	local V, on = ns.Views, Recruiting()
	local lines = { { text = on and V.Green(L.RECRUIT_WHISPER_ON) or V.Grey(L.RECRUIT_WHISPER_OFF),
		onClick = Recruit.ToggleWhisperRecruiting, gapAfter = true } }
	AnnouncementLines(lines, V)
	if on then
		lines[#lines + 1] = { indent = 1, text = L.RECRUIT_WHISPER_HINT }
		lines[#lines + 1] = { id = "recruit-whisper-arrival", indent = 1,
			text = V.Gold(QueueOnly() and L.RECRUIT_WHISPER_QUEUE_ONLY or L.RECRUIT_WHISPER_POPUP_ON),
			onClick = ToggleQueueOnly }
		if Recruit.Handoff then Recruit.Handoff.Controls(lines, V) end
		if Recruit.Candidates then
			Recruit.Candidates.Lines(lines, V)
		else
			lines[#lines + 1] = { indent = 1, text = V.Gold(L.RECRUIT_WHISPER_TARGET), onClick = Recruit.PromptOutreach, gapAfter = true }
		end
	end
	return lines
end

local function Prune(now)
	for i = #Recruit.requests, 1, -1 do
		if now - Recruit.requests[i].t > Recruit.REQUEST_TTL then table.remove(Recruit.requests, i) end
	end
	for name, t in pairs(requestAt) do
		if now - t > Recruit.REQUEST_EACH then requestAt[name] = nil end
	end
end
local function Drop(req)
	for i, r in ipairs(Recruit.requests) do
		if r == req then table.remove(Recruit.requests, i) break end
	end
	ns.Fire("DATA_CHANGED")
end

local function AddRequest(sender, own, level, class, text, viaWhisper)
	if ns.Roster.RankOf(sender) then return false end -- one of us already
	local now = ns.Now()
	Prune(now)
	if requestAt[sender] then return false end
	requestAt[sender] = now
	for i, r in ipairs(Recruit.requests) do
		if r.name == sender then table.remove(Recruit.requests, i) break end
	end
	if #Recruit.requests >= Recruit.REQUESTS_MAX then
		for i, older in ipairs(Recruit.requests) do
			local state = Recruit.Handoff and Recruit.Handoff.State(older)
			if state ~= "offered" and state ~= "assigning" and not Recruit.HandoffPromptOpen(older) then
				table.remove(Recruit.requests, i)
				break
			end
		end
		if #Recruit.requests >= Recruit.REQUESTS_MAX then return false end
	end
	level = tonumber(level)
	local req = { name = sender, guild = own, level = level and level >= 1 and level <= 100 and level or nil,
		class = class and class ~= "" and #class <= 12 and class or nil, t = now, text = text, viaWhisper = viaWhisper }
	Recruit.requests[#Recruit.requests + 1] = req
	-- Officers using The Watch are notified, but the request is never rejected automatically.
	-- A related character counts only when Alts.lua already holds its two-sided confirmation.
	if not viaWhisper and ns.Watch and ns.Watch.EntryAttempt then
		ns.SafeCall("watch entry attempt", ns.Watch.EntryAttempt, sender)
	end
	-- One chat line, REQUEST_LINES a minute at most (the rest wait in the Census).
	for i = #lineTimes, 1, -1 do
		if now - lineTimes[i] >= 60 then table.remove(lineTimes, i) end
	end
	if #lineTimes < Recruit.REQUEST_LINES then
		lineTimes[#lineTimes + 1] = now
		local className = req.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[req.class] or ""
		local who = ns.DisplayName(sender) or sender
		ns.Print(viaWhisper and L.RECRUIT_WHISPER_ASKED:format(who, own) or L.JOIN_ASKED:format(who, req.level or 0, className, own))
	end
	if not viaWhisper then ns.Log("recruit: %s asks to join %s", sender, own) end
	ns.Fire("DATA_CHANGED")
	return true, req
end
function Recruit.OnJoinRequest(dist, sender, text)
	if dist ~= "WHISPER" or not ns.IsMember() then return false end
	local guild, level, class = tostring(text):match("^J3~([^~]+)~(%d+)~(%u*)$")
	local own = GetGuildInfo("player")
	if not guild or not own or guild:lower() ~= own:lower() then return false end
	local w = whispers[sender]
	local accepted = AddRequest(sender, own, level, class, w and ns.Now() - w.t <= 120 and w.text or nil)
	return accepted
end
ns.Comm.Handle("J3", Recruit.OnJoinRequest)

local function CanInvite()
	local allowed = type(CanGuildInvite) == "function" and CanGuildInvite()
	return not ns.IsSecret(allowed) and allowed and true or false
end
Recruit.CanInvite = CanInvite

-- A warning may wait while ranks, guild membership or the request change. Only a current
-- request for this guild can reach the native invitation, and only from the officer's click.
local function CurrentRequest(req, allowHandoff)
	if type(req) ~= "table" or type(req.name) ~= "string" or req.name == "" or not CanInvite() or not ns.IsMember() then return false end
	if req.guild ~= GetGuildInfo("player") or ns.Roster.RankOf(req.name) ~= nil then return false end
	if req.viaWhisper and (not Recruiting() or ns.ChatLocked()) then return false end
	if not allowHandoff and Recruit.Handoff and Recruit.Handoff.State(req) then return false end
	Prune(ns.Now())
	for _, pending in ipairs(Recruit.requests) do if pending == req then return true end end
	return false
end

-- `blocked`: the officer said the game refused the invite he pasted, so a prepared one counts.
function Recruit.HandoffSource(req, blocked)
	return type(req) == "table" and req.viaWhisper and req.handoffIntent ~= nil and (blocked or not req.invitePrepared)
		and CurrentRequest(req, true)
end

function Recruit.HandoffPromptOpen(req)
	local D = ns.Dialog
	if not D or D.missing or not D.Find then return false end
	if D.Find("OLYMPUS_RECRUIT_REPLY", req) then return true end
	local copy = D.Find("OLYMPUS_RECRUIT_INVITE_DRAFT")
	if copy and copy.data and copy.data.req == req then return true end
	local warning = D.Find("OLYMPUS_RECRUIT_NETOFF")
	return (warning and warning.data and warning.data.req == req) or false
end

function Recruit.OverflowRequest()
	Prune(ns.Now())
	local waiting, candidate = 0, nil
	for _, req in ipairs(Recruit.requests) do
		if not Recruit.Handoff.State(req) and Recruit.HandoffSource(req) then
			-- The officer asked to pass this one on: it goes first, once its own popup is closed.
			if req.passWanted and not Recruit.HandoffPromptOpen(req) then return req end
			waiting = waiting + 1
			if waiting > 1 and not candidate and not Recruit.HandoffPromptOpen(req) then candidate = req end
		end
	end
	if waiting >= 3 then return candidate end
end

-- The applicant's JOIN reached another officer first. Here it opens the same copy command a
-- JOIN whispered to us opens (no Prepare step), and it is never offered onward (no intent).
function Recruit.TakeHandoff(name, officer)
	if not Recruiting() or not CanInvite() or not NameForCommand(name) then return false end
	local shown = L.RECRUIT_HANDOFF_RECEIVED:format(ns.DisplayName(officer) or officer)
	local accepted, req = AddRequest(name, recruitingGuild, nil, nil, shown, true)
	if not accepted then return false end
	req.handedIn = true
	PromptReply()
	return true
end

local function SameWarning(data, req, word)
	return type(data) == "table" and data.req == req and data.name == req.name and data.guild == req.guild
		and data.on == word.name and data.at == word.at and data.by == word.by and data.reason == word.reason
end

-- Whisper requests still waiting for this officer besides `req` (the count on its popup).
local function WaitingAfter(req)
	local n = 0
	for _, pending in ipairs(Recruit.requests) do
		if pending ~= req and pending.viaWhisper and not pending.invitePrepared and not pending.passWanted
			and not (Recruit.Handoff and Recruit.Handoff.State(pending)) and CurrentRequest(pending) then n = n + 1 end
	end
	return n
end

local function InviteDraftText(name, req)
	local text = L.RECRUIT_WHISPER_INVITE_COPY:format(name)
	local waiting = req and WaitingAfter(req) or 0
	if waiting > 0 then text = text .. "\n\n" .. L.RECRUIT_HANDOFF_MORE:format(waiting) end
	return text
end

local function AcceptRequest(req, confirmed, automatic)
	if not CurrentRequest(req) then return false end
	if confirmed and (confirmed.name ~= req.name or confirmed.guild ~= req.guild) then return false end
	local prepare = req.viaWhisper or ns.OnForever()
	local invite
	if not prepare then
		invite = (C_GuildInfo and C_GuildInfo.Invite) or GuildInvite -- gp:roster-actions
		if type(invite) ~= "function" then return false end
	end
	local M = ns.Moderation
	local word = M and M.Hidden and M.Hidden(req.name)
	if word and not SameWarning(confirmed, req, word) then
		if not ns.Dialog or ns.Dialog.missing then ns.Print(L.RESTART_NEEDED) return false end
		local data = { req = req, name = req.name, guild = req.guild,
			on = word.name, at = word.at, by = word.by, reason = word.reason }
		-- Keep this contextual choice in Olympus's own window in either input mode. The existing
		-- moderation formatter also preserves the King's stream privacy for free-text reasons.
		ns.Dialog.Show("OLYMPUS_RECRUIT_NETOFF", L.JOIN_NETOFF_PROMPT:format(ns.DisplayName(req.name) or req.name,
			M.When(word), M.ReasonShown(word)), nil, data)
		return "warning"
	end
	if prepare then
		local to = NameForCommand(req.name)
		if not to then return false end
		if not ns.Dialog or ns.Dialog.missing then ns.Print(L.RESTART_NEEDED) return false end
		-- The officer copies and pastes the command. Forever blocks addon-prefilled invites.
		local draft = ns.Dialog.Show("OLYMPUS_RECRUIT_INVITE_DRAFT", InviteDraftText(to, req), nil,
			{ req = req, automatic = automatic })
		if draft and not automatic then req.invitePrepared = true end
		return draft ~= nil
	end
	invite(ns.TellName(req.name))
	ns.Print(L.JOIN_INVITED:format(ns.DisplayName(req.name) or req.name, req.guild))
	Drop(req)
	return true
end

-- An officer's yes: a current individual net-off word first asks for an explicit choice. It
-- never declines a guild request, changes a block/ignore list or takes a native invite back.
function Recruit.Accept(req) return AcceptRequest(req) == true end

StaticPopupDialogs["OLYMPUS_RECRUIT_NETOFF"] = {
	text = "%s",
	button1 = L.JOIN_NETOFF_INVITE,
	button2 = L.JOIN_NETOFF_CANCEL,
	OnAccept = function(_, data)
		if type(data) ~= "table" then return end
		-- A changed word presents its new context and keeps the question open for another click.
		return AcceptRequest(data.req, data) == "warning"
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function Recruit.CopyCandidateInvite(candidate, automatic)
	if not Recruit.Candidates.Check(candidate) or not ns.Dialog or ns.Dialog.missing then return false end
	if ns.Dialog.Find("OLYMPUS_RECRUIT_INVITE_DRAFT") then return false end
	return ns.Dialog.Show("OLYMPUS_RECRUIT_INVITE_DRAFT", InviteDraftText(candidate.name), nil,
		{ candidate = candidate, automatic = automatic }) ~= nil
end

local function OpenInviteChat(draft, data) -- gp:chat-box
	if not ns.Gate.Allowed("chat-box") then return end
	if ns.ChatLocked() or (InCombatLockdown and InCombatLockdown()) then return end
	local req = data.req
	if data.candidate then
		if not Recruit.Candidates.Check(data.candidate) then return end
	elseif not CurrentRequest(req) then return end
	local util = ChatFrameUtil
	local open = type(util) == "table" and type(util.OpenChat) == "function" and util.OpenChat or ChatFrame_OpenChat
	if type(open) ~= "function" then return end
	ns.Gate.Used("chat-box")
	if pcall(open, "", DEFAULT_CHAT_FRAME) then
		if req then req.invitePrepared = true end
		draft:Hide()
	end
end

StaticPopupDialogs["OLYMPUS_RECRUIT_INVITE_DRAFT"] = {
	text = "%s",
	button1 = L.RECRUIT_WHISPER_CLOSE,
	-- Before the command reaches chat, a JOIN (and the ones waiting behind it) can go to the
	-- other officers who accept handoffs. Not OnCancel: Escape and replacement pass nothing.
	button2 = L.RECRUIT_HANDOFF_PASS,
	button2Shown = function(_, data)
		return type(data) == "table" and data.req ~= nil and Recruit.Handoff ~= nil and Recruit.Handoff.CanPass(data.req)
	end,
	OnButton2 = function(_, data)
		if type(data) == "table" and data.req and Recruit.Handoff then Recruit.Handoff.Pass(data.req, true) end
	end,
	extra = { label = L.RECRUIT_WHISPER_INVITE_CHAT, onClick = OpenInviteChat },
	hasEditBox = true,
	editBoxWidth = 360,
	OnShow = function(f, data)
		local box = f.editBox
		local name = data.candidate and data.candidate.name or NameForCommand(data.req.name)
		box:SetText("/ginvite " .. name)
		box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
		if ns.Focus(box, nil, data.automatic) then box:HighlightText() end
		-- Let the game's edit box copy first. Remember Ctrl at key-down because the
		-- player can release it before C. The only handoff is opening empty chat.
		local copying
		box:SetScript("OnKeyDown", function(self, key)
			if key == "C" then copying = self:HasFocus() and IsControlKeyDown() end
		end)
		box:SetScript("OnKeyUp", function(self, key)
			if key ~= "C" then return end
			local handoff = copying
			copying = nil
			if handoff and self:HasFocus() then OpenInviteChat(f, data) end
		end)
		box:SetScript("OnEditFocusLost", function() copying = nil end)
	end,
	OnHide = function(f)
		f.editBox:SetScript("OnKeyDown", nil)
		f.editBox:SetScript("OnKeyUp", nil)
		f.editBox:SetScript("OnEditFocusGained", nil)
		f.editBox:SetScript("OnEditFocusLost", nil)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function ReviewReply(req)
	if not req.viaWhisper or not CurrentRequest(req) or not ns.Dialog or ns.Dialog.missing then return false end
	local caption = L.RECRUIT_WHISPER_REPLY:format(ns.DisplayName(req.name) or req.name, req.guild, req.text)
	return ns.Dialog.Show("OLYMPUS_RECRUIT_REPLY", caption, nil, req) ~= nil
end

local function RetryReply(delay)
	if replyTimer then return end
	local timer = {}
	replyTimer = timer
	ns.After(delay, "next recruitment reply", function()
		if replyTimer ~= timer then return end
		replyTimer = nil
		PromptReply()
	end)
end

-- Offer each valid queued reply once, in order. When the player is busy, only one retry
-- waits, and only while there is a reply left to show.
PromptReply = function()
	if not Recruiting() or QueueOnly() or not ns.Dialog or ns.Dialog.missing then return end
	local now, req = ns.Now(), nil
	Prune(now)
	for _, pending in ipairs(Recruit.requests) do
		if pending.viaWhisper and not pending.popupShown and not pending.invitePrepared and not pending.passWanted
			and (not Recruit.Handoff or not Recruit.Handoff.State(pending)) then
			req = pending
			break
		end
	end
	if not req then return end
	if lastReplyPrompt and now - lastReplyPrompt < ASK_COOLDOWN then
		return RetryReply(ASK_COOLDOWN - (now - lastReplyPrompt))
	end
	if (InCombatLockdown and InCombatLockdown()) or ns.ChatLocked() or ns.KeyboardFocus() then return RetryReply(2) end
	for _, id in ipairs({ "OLYMPUS_RECRUIT_OUTREACH", "OLYMPUS_RECRUIT_ANNOUNCEMENT", "OLYMPUS_RECRUIT_REPLY", "OLYMPUS_RECRUIT_INVITE_DRAFT", "OLYMPUS_RECRUIT_NETOFF" }) do
		if ns.Dialog.Find(id) then return RetryReply(2) end
	end
	for _, pending in ipairs(Recruit.requests) do
		if pending.viaWhisper and not pending.popupShown and not pending.invitePrepared and not pending.passWanted
			and CurrentRequest(pending) then
			local shown
			if pending.handoffIntent or pending.handedIn then shown = AcceptRequest(pending, nil, true)
			else shown = ReviewReply(pending) end
			if shown then
				pending.popupShown, lastReplyPrompt = true, now
				return RetryReply(ASK_COOLDOWN)
			end
		end
	end
end

StaticPopupDialogs["OLYMPUS_RECRUIT_REPLY"] = {
	text = "%s",
	button1 = L.RECRUIT_WHISPER_PREPARE_BUTTON,
	button2 = L.RECRUIT_WHISPER_QUEUE,
	OnAccept = function(_, req) Recruit.Accept(req) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- Where to send one we can't take: the gates' guild while the King's gates are open, else only
-- ours (the Join screen shows who has room). Never a guild named for its free slots (Konig's
-- review of 1.1: the top "most room" guild is one two characters can fake, and this whisper goes
-- from the officer's own chat).
function Recruit.DeclineText(req)
	local own = GetGuildInfo("player")
	local gates = ns.Acts and ns.Acts.Gates and ns.Acts.Gates()
	local other = gates and gates.guild ~= own and gates.guild or nil
	if other then return L.JOIN_DECLINE_TEXT:format(own or "?", other) end
	return L.JOIN_DECLINE_TEXT_PLAIN:format(own or "?")
end

-- An officer's no: one whisper, from the click, pointing where there is room.
function Recruit.Decline(req)
	if not CanInvite() or type(req) ~= "table" then return false end
	if Recruit.Handoff and Recruit.Handoff.State(req) then return false end
	SendChatMessage(Recruit.DeclineText(req), "WHISPER", nil, ns.TellName(req.name)) -- gp:roster-actions
	Drop(req)
	return true
end

-- Someone who can't invite: an officer of ours online to point to (never ourselves).
function Recruit.Officer()
	for _, m in ipairs(ns.Roster.online or {}) do
		if (m.rankIndex or 9) <= ns.CAPTAIN_RANK and ns.FullName(m.name) ~= ns.me then return m.name end
	end
	return nil
end
function Recruit.Point(req)
	local officer = Recruit.Officer()
	if not officer or type(req) ~= "table" then return false end
	SendChatMessage(L.JOIN_POINT_TEXT:format(officer), "WHISPER", nil, ns.TellName(req.name)) -- gp:roster-actions
	Drop(req)
	return true
end
function Recruit.Dismiss(req)
	if Recruit.Handoff and Recruit.Handoff.State(req) then return end
	Drop(req)
end

-- An officer reviews or declines requests. Other members can point to an officer online.
-- viaWhisper separates manual recruitment replies from the usual Join Olympus requests.
function Recruit.RequestLines(viaWhisper)
	if not ns.IsMember() then return {} end
	Prune(ns.Now())
	local reqs = Recruit.requests
	if viaWhisper ~= nil then
		reqs = {}
		for _, req in ipairs(Recruit.requests) do
			if (req.viaWhisper == true) == viaWhisper then reqs[#reqs + 1] = req end
		end
	end
	if #reqs == 0 then return {} end
	local V = ns.Views
	local lines = { {
		header = true, text = L.JOIN_REQUESTS:format(#reqs),
		tooltip = function(tt)
			tt:AddLine(L.JOIN_REQUESTS:format(#reqs), 1, 0.82, 0)
			tt:AddLine(viaWhisper and L.RECRUIT_WHISPER_HINT or L.JOIN_REQUESTS_TIP, 1, 1, 1, true)
		end,
	} }
	local canInvite, officer = CanInvite(), Recruit.Officer()
	for i = #reqs, math.max(1, #reqs - Recruit.REQUESTS_SHOWN + 1), -1 do
		local req = reqs[i]
		local who = ns.DisplayName(req.name) or req.name
		local className = req.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[req.class] or ""
		lines[#lines + 1] = {
			text = V.ClassColored(who, req.class) .. (req.viaWhisper and "" or "  " .. V.Grey(L.LEVEL_N:format(req.level or 0) .. " " .. className)),
			right = V.Grey(ns.Ago(req.t)),
			tooltip = function(tt)
				tt:AddLine((req.viaWhisper and L.RECRUIT_WHISPER_ASKED_TIP or L.JOIN_ASKED_TIP):format(who, req.guild), 1, 0.82, 0, true)
				if req.text then tt:AddLine('"' .. ns.Codec.SanitizeChat(req.text) .. '"', 1, 1, 1, true) end
			end,
		}
		local handoff = req.viaWhisper and Recruit.Handoff
		local joined = (req.viaWhisper or req.invitePrepared) and req.guild == GetGuildInfo("player") and ns.Roster.Fresh()
			and ns.Roster.RankOf(req.name) ~= nil
		if joined then
			lines[#lines + 1] = { indent = 1, text = V.Green(L.RECRUIT_WHISPER_JOINED) }
		elseif handoff and handoff.State(req) then
			handoff.RequestLines(lines, V, req)
		elseif canInvite then
			local reply = req.viaWhisper and not req.handoffIntent and not req.handedIn
			local label = reply and L.RECRUIT_WHISPER_REVIEW:format(req.guild)
				or ((req.viaWhisper or ns.OnForever()) and L.RECRUIT_WHISPER_PREPARE_BUTTON or L.JOIN_INVITE:format(req.guild))
			local action = reply and ReviewReply or Recruit.Accept
			lines[#lines + 1] = { indent = 1, text = V.Green(label), onClick = function() action(req) end }
			lines[#lines + 1] = {
				indent = 1, text = V.Gold(L.JOIN_DECLINE), onClick = function() Recruit.Decline(req) end,
				tooltip = function(tt)
					tt:AddLine(L.JOIN_DECLINE_TIP, 1, 0.82, 0, true)
					tt:AddLine('"' .. Recruit.DeclineText(req) .. '"', 1, 1, 1, true)
				end,
			}
			if handoff then
				handoff.RequestLines(lines, V, req)
				-- The command went to chat, but the game refused it (too many invites): the officer's
				-- click says so, and only then may another officer invite the same player.
				if req.invitePrepared and req.handoffIntent and handoff.CanPass(req, true) then
					lines[#lines + 1] = { indent = 1, text = V.Gold(L.RECRUIT_HANDOFF_BLOCKED),
						onClick = function() handoff.PassBlocked(req) end }
				end
			end
		elseif officer then
			lines[#lines + 1] = {
				indent = 1, text = V.Gold(L.JOIN_POINT:format(officer)), onClick = function() Recruit.Point(req) end,
				tooltip = function(tt) tt:AddLine('"' .. L.JOIN_POINT_TEXT:format(officer) .. '"', 1, 1, 1, true) end,
			}
		end
		if not handoff or not handoff.State(req) then
			lines[#lines + 1] = { indent = 1, text = V.Grey(L.JOIN_DISMISS), onClick = function() Recruit.Dismiss(req) end }
		end
	end
	if #reqs > Recruit.REQUESTS_SHOWN then lines[#lines + 1] = { indent = 1, text = V.Grey(L.JOIN_MORE:format(#reqs - Recruit.REQUESTS_SHOWN)) } end
	lines[#lines].gapAfter = true
	return lines
end

function Recruit.ResetForTests()
	join = {}
	StopRecruiting()
	if reminderTimer then reminderTimer.Cancel(); reminderTimer = nil end
	reminderIndex, announcementVariant, lastAnnouncement = 1, 0, nil
	rotateReminder, lastReminderChannel = true, nil
	wipe(publicRecruitmentAt)
	wipe(contacted)
	lastOutreach, lastReplyPrompt = nil, nil
	wipe(routeAsked); wipe(routeAnswered); wipe(gatesSaid); wipe(askedKey); wipe(dnc); wipe(answeredAt); wipe(answers); wipe(requestAt)
	wipe(lineTimes); wipe(whispers)
	lastRoute = -math.huge
	Recruit.route, Recruit.pending, Recruit.lastAsk, Recruit.lastContact = nil, nil, 0, nil
	Recruit.found, Recruit.asked, Recruit.replied, Recruit.requests = {}, {}, {}, {}
	if ns.GuildCharter then ns.GuildCharter.ResetForTests() end
end

-- A whisper came in. Outside Olympus: a member we asked answered. In it: kept a moment for the
-- join request (J3) that follows a recruit's whisper, shown with it.
function Recruit.OnWhisper(text, sender)
	-- 1.1.5: CHAT_MSG_WHISPER is SecretInChatMessagingLockdown on Forever: in a dungeon, a raid or
	-- an encounter its text and sender can be secret, and even a comparison raises in our code.
	-- Nothing can be read from such a whisper: left alone before any string or table operation.
	if type(issecretvalue) == "function" and (issecretvalue(text) or issecretvalue(sender)) then return end
	if type(sender) ~= "string" or sender == "" then return end
	if ns.IsMember() then
		local now = ns.Now()
		local key = Key(sender)
		if Recruiting() and type(text) == "string" then
			local reply = text:match("^%s*(.-)%s*$")
			local keyword = reply:upper()
			local to = NameForCommand(key)
			local recent = to and RecentlyContacted(to, now)
			if to and key ~= ns.me and (keyword == "JOIN" or keyword == "JOIN OLYMPUS" or (recent and reply ~= "")) then
				local shown = ns.Codec.SanitizeChat(ns.Cut(reply, 180))
				if shown ~= "" then
					local accepted, req = AddRequest(key, recruitingGuild, nil, nil, shown, true)
					if accepted then
						req.handoffIntent = keyword == "JOIN OLYMPUS" and "federation" or keyword == "JOIN" and "guild" or nil
						PromptReply()
					end
				end
			end
		end
		if key and not whispers[key] then
			local n = 0
			for name, w in pairs(whispers) do
				if now - w.t > 120 then whispers[name] = nil else n = n + 1 end
			end
			if n >= 30 then return end
		end
		if key then whispers[key] = { text = text, t = now } end
		return
	end
	-- (1.2.5.1) In an Olympus guild before the Olympus Accord: neither part (he asked nobody).
	if ns.InOlympusGuild() then return end
	local who = ns.ShortName(sender)
	for name in pairs(Recruit.asked) do
		if ns.ShortName(name) == who then
			Recruit.replied[name] = text
			ns.Print(L.RECRUIT_REPLIED:format(who))
			ns.Fire("RECRUIT_CHANGED")
			return
		end
	end
end

ns.On("LOGIN", function()
	RestoreRecruiting()
	ns.RegisterEvent("PLAYER_ENTERING_WORLD", RestoreRecruiting)
	ns.RegisterEvent("GUILD_ROSTER_UPDATE", RestoreRecruiting)
	ns.After(12, "daily nag", DailyNag)
	ns.RegisterEvent("CHAT_MSG_WHISPER", function(text, sender) Recruit.OnWhisper(text, sender) end)
	ns.RegisterEvent("CHAT_MSG_CHANNEL", ObserveAnnouncement)
	ns.RegisterEvent("PLAYER_GUILD_UPDATE", function(unit)
		if unit and unit ~= "player" then return end
		RestoreRecruiting()
		if not Recruit.SimpleJoin() then
			join = {}
			if not ns.Dialog.missing then ns.Dialog.Hide("OLYMPUS_RECRUIT_RETRY") end
		end
	end)
end)
ns.On("ACCORD_CHANGED", RestoreRecruiting)

StaticPopupDialogs["OLYMPUS_RECRUIT_RETRY"] = {
	text = L.RECRUIT_JOIN_REMINDER_PROMPT,
	button1 = L.RECRUIT_JOIN_AGAIN,
	button2 = CANCEL or "Cancel",
	OnAccept = function(_, request)
		if join.request ~= request or not JoinReminderOn() or not Recruit.SimpleJoin() then return end
		if JoinBusy() then return true end
		if not JoinVisible() and (not ns.UI or not ns.UI.SelectTab("census")) then return true end
		return not Recruit.RequestJoin()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_RECRUIT"] = {
	text = "%s  <%s>",
	button1 = SEND_LABEL or "Send",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 320,
	maxLetters = 250,
	OnShow = function(self, contact)
		local eb = self.editBox or self.EditBox
		if eb and contact then
			eb:SetText(Recruit.Message(contact))
			eb:HighlightText(0, 0)
			eb:SetFocus()
		end
	end,
	OnAccept = function(self, contact)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("recruit ask", Recruit.Ask, contact, eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		ns.SafeCall("recruit ask", Recruit.Ask, parent.data, self:GetText())
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}
