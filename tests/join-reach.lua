-- 1.6.0, the join reach (players' reports, 11-14 and 11-15: new characters asked members to join and
-- got no invite; one "requested invites to a dozen people and no one has responded" and fell back to
-- /who, sure the addon was broken; a PvP player "haven't seen anyone"). A Join Olympus request end to
-- end: the requester's Join screen (Recruit.lua, the main namespace) and the members it asks, each a
-- client of his own (this build's Recruit.lua, 1.5.9's from tests/fixtures/recruit-1.5.9.lua, or no
-- Olympus at all), joined by whispers that take LAT seconds. Loaded by tests/run.lua.
local ns, test, eq, FIXTURES, ADDON = ...
local R, L = ns.Recruit, ns.L

local LAT = 0.5                    -- seconds an addon or chat whisper takes to arrive
local REQUESTER = "Fresh Recruit-Realm"
local RECRUIT_NOW = ADDON .. "Recruit.lua"
local RECRUIT_159 = FIXTURES .. "recruit-1.5.9.lua"
local DRAFT = "OLYMPUS_RECRUIT_INVITE_DRAFT"

-- Olympus's dialogs as one client sees them: shown, found, closed; a second of one kind replaces the
-- first, as Dialog.Show does. Each keeps its definition.
local function Dialogs(clock)
	local shown, D = {}, {}
	function D.Find(which, data)
		for i = #shown, 1, -1 do
			local f = shown[i]
			if f.which == which and f.open and (data == nil or f.data == data) then return f end
		end
	end
	function D.Show(which, a, _, data)
		local old = D.Find(which)
		if old then old.open = false end
		local f = { which = which, text = a, data = data, open = true, def = StaticPopupDialogs[which], at = clock and clock() }
		f.Hide = function() f.open = false end
		f.IsShown = function() return f.open end
		shown[#shown + 1] = f
		return f
	end
	function D.Hide(which, data) local f = D.Find(which, data); if f then f.open = false end end
	function D.CloseOnEscape() end
	D.shown = shown
	return D
end

-- The request window's Send, clicked: its text as the window wrote it.
local function Send(f)
	local box = { text = "" }
	function box.SetText(self, t) self.text = t end
	function box.GetText(self) return self.text end
	function box.HighlightText() end
	function box.SetFocus() end
	f.editBox = box
	f.def.OnShow(f, f.data)
	f.def.OnAccept(f, f.data)
	f:Hide()
	return box.text
end

-- The main namespace as an unguilded player with the Join Olympus page open, on a clock the test moves:
-- w.At(delay, fn) runs fn then, w.Advance(seconds) runs what falls due in order. w.said: his chat
-- whispers; w.out: his addon whispers; w.printed: his chat lines. w.OnSay, w.OnOutside and w.OnSearch
-- hand them to the world (below).
local function WithRequester(fn)
	local saved = { guild = GetGuildInfo, inGuild = IsInGuild, invite = CanGuildInvite, count = GetNumGuildMembers,
		level = UnitLevel, class = UnitClass, time = GetTime, say = SendChatMessage, outside = ns.Comm.WhisperOutside,
		dialog = ns.Dialog, after = ns.After, now = ns.Now, locked = ns.ChatLocked, quiet = ns.Quiet, ui = rawget(ns, "UI"),
		search = ns.Who.Search, searched = ns.Who.Searched, print = ns.Print, reminder = ns.db.joinReminderOff,
		member = ns.IsMember, charter = rawget(ns, "GuildCharter") }
	R.ResetForTests()
	local w = { clock = 1000, timers = {}, said = {}, out = {}, printed = {}, seq = 0, searches = 0 }
	function w.At(delay, f)
		w.seq = w.seq + 1
		w.timers[#w.timers + 1] = { at = w.clock + (delay or 0), seq = w.seq, fn = f }
	end
	function w.Advance(seconds)
		local stop = w.clock + seconds
		while true do
			local best, at
			for i, t in ipairs(w.timers) do
				if t.at <= stop and (not best or t.at < best.at or (t.at == best.at and t.seq < best.seq)) then best, at = t, i end
			end
			if not best then break end
			table.remove(w.timers, at)
			if best.at > w.clock then w.clock = best.at end
			best.fn()
		end
		w.clock = stop
	end
	GetGuildInfo = function() return nil end
	IsInGuild = function() return false end
	UnitLevel = function() return 8 end
	UnitClass = function() return "Priest", "PRIEST" end
	GetTime = function() return w.clock end
	ns.Now = function() return w.clock end
	ns.After = function(delay, _, f) w.At(delay, f) end
	ns.ChatLocked = function() return false end
	ns.Quiet = function() return nil end
	ns.IsMember = function() return false end
	ns.GuildCharter = nil
	ns.Dialog = Dialogs(function() return w.clock end)
	ns.UI = setmetatable({ IsShown = function() return true end, PageId = function() return "join" end }, { __index = saved.ui })
	ns.Print = function(msg) w.printed[#w.printed + 1] = tostring(msg) end
	ns.db.joinReminderOff = true
	SendChatMessage = function(text, kind, _, to)
		w.said[#w.said + 1] = { text = text, kind = kind, to = to, at = w.clock }
		if w.OnSay then w.OnSay(text, kind, to) end
	end
	ns.Comm.WhisperOutside = function(to, msg)
		w.out[#w.out + 1] = { to = to, msg = msg, at = w.clock }
		if w.OnOutside then w.OnOutside(to, msg) end
		return true
	end
	ns.Who.Search = function()
		w.searches = w.searches + 1
		if w.OnSearch then w.OnSearch() end
		return true
	end
	ns.Who.Searched = function() return w.searches > 0 end
	local ok, err = pcall(fn, w)
	R.ResetForTests()
	GetGuildInfo, IsInGuild, CanGuildInvite, GetNumGuildMembers = saved.guild, saved.inGuild, saved.invite, saved.count
	UnitLevel, UnitClass, GetTime, SendChatMessage = saved.level, saved.class, saved.time, saved.say
	ns.Comm.WhisperOutside, ns.Dialog, ns.After, ns.Now = saved.outside, saved.dialog, saved.after, saved.now
	ns.ChatLocked, ns.Quiet, ns.UI, ns.Who.Search, ns.Who.Searched = saved.locked, saved.quiet, saved.ui, saved.search, saved.searched
	ns.Print, ns.db.joinReminderOff, ns.IsMember, ns.GuildCharter = saved.print, saved.reminder, saved.member, saved.charter
	if not ok then error(err, 0) end
end

-- The members online, as a spec gives them: { key, guild, version ("1.6.0": this build, "1.5.9", or
-- nil: no Olympus), invite (the game lets him invite), recruiting (his recruiting by whisper is on),
-- rank (0 Lord, 1 Captain, 3 member) }, in the order /who lists them; spec.guilds[name] = members.
-- Each member with Olympus runs his own Recruit.lua, his globals put in place while it runs (As).
local function World(w, spec)
	local world = { members = {}, byTell = {}, guilds = spec.guilds, w = w, invited = nil, popups = {} }
	local function Short(key) return key:match("^(.-)%-") or key end
	function world.As(m, fn, ...)
		local saved = { GetGuildInfo, IsInGuild, CanGuildInvite, GetNumGuildMembers }
		GetGuildInfo = function() return m.guild end
		IsInGuild = function() return true end
		CanGuildInvite = function() return m.invite == true end
		GetNumGuildMembers = function() local n = world.guilds[m.guild]; return n, n end
		local ok, a, b = pcall(fn, ...)
		GetGuildInfo, IsInGuild, CanGuildInvite, GetNumGuildMembers = saved[1], saved[2], saved[3], saved[4]
		if not ok then error(a, 0) end
		return a, b
	end
	function world.Online(guild)
		local out = {}
		for _, m in ipairs(world.members) do
			if m.guild == guild then out[#out + 1] = { name = m.key, rankIndex = m.rank or 3 } end
		end
		return out
	end
	-- The census as every member's holds it: the guilds with room, the most first, their Lord and
	-- Captains online as two reports name them.
	function world.OpenGuilds()
		local out = {}
		for name, size in pairs(world.guilds) do
			if size < ns.Codec.GUILD_CAP then
				local g = { total = size, realm = "Realm", officers = {} }
				for _, m in ipairs(world.members) do
					if m.guild == name and m.rank == 0 then g.leader, g.leaderOnline = Short(m.key), true end
					if m.guild == name and m.rank == 1 then g.officers[#g.officers + 1] = { name = Short(m.key), online = true } end
				end
				out[#out + 1] = { name = name, free = ns.Codec.GUILD_CAP - size, e = { g = g } }
			end
		end
		table.sort(out, function(a, b) if a.free ~= b.free then return a.free > b.free end return a.name < b.name end)
		return out
	end
	function world.Rank(name, guild)
		for _, m in ipairs(world.members) do
			if m.key == name and m.guild == guild and (m.rank or 3) <= 1 then return m.rank, "census", 2 end
		end
	end
	-- What this member's guildmates' hellos say of handoffs: "J" from each one recruiting (1.5.9 and later).
	function world.HandoffPeers(m)
		local full = {}
		for _, o in ipairs(world.members) do
			if o ~= m and o.guild == m.guild and o.version and o.recruiting and o.invite then
				full[o.key] = { takes = true, version = o.version, at = w.clock }
			end
		end
		return { full = full, short = {} }
	end
	-- A member's addon whisper to the requester: his answer (J2), heard as Comm hands it on.
	function world.FromMember(m, to, msg)
		if type(msg) == "string" and msg:sub(1, 3) == "J2~" then
			w.At(LAT, function() R.OnRoute(m.key, msg) end)
		end
	end
	local function Load(m)
		local handlers, dialogs = {}, {}
		for name, d in pairs(StaticPopupDialogs) do dialogs[name] = d end
		local mns = setmetatable({
			Comm = setmetatable({
				Handle = function(kind, f) handlers[kind] = f end,
				HandleOutside = function() end,
				Whisper = function(to, msg) world.FromMember(m, to, msg) return true end,
				Send = function() return true end,
				HandoffPeers = function() return world.HandoffPeers(m) end,
			}, { __index = ns.Comm }),
			Who = setmetatable({ Listen = function() end }, { __index = ns.Who }),
			On = function() end, RegisterEvent = function() end, Fire = function() end, Log = function() end,
			IsMember = function() return true end,
			me = m.key, db = { blocked = {} }, rdb = {},
			Now = function() return w.clock end,
			After = function(delay, _, f) w.At(delay, function() world.As(m, f) end) end,
			Every = function() return { Cancel = function() end } end,
			Print = function(msg) m.printed[#m.printed + 1] = tostring(msg) end,
			Dialog = Dialogs(function() return w.clock end),
			ChatLocked = function() return false end, QuietPresence = function() return false end,
			KeyboardFocus = function() return nil end, Quiet = function() return nil end,
			Roster = { RankOf = function() return nil end, online = world.Online(m.guild), Fresh = function() return nil end },
			Data = setmetatable({ AuthorizedRank = function(name, guild) return world.Rank(name, guild) end }, { __index = ns.Data }),
			Acts = { Gates = function() return nil end },
			Watch = {}, Moderation = {}, RecruitRanking = {},
		}, { __index = ns })
		local ok, err = pcall(assert(loadfile(m.version == "1.5.9" and RECRUIT_159 or RECRUIT_NOW)), "Olympus", mns)
		for name in pairs(StaticPopupDialogs) do StaticPopupDialogs[name] = dialogs[name] end
		assert(ok, err)
		m.ns, m.R, m.handlers = mns, mns.Recruit, handlers
		m.R.OpenGuilds = function() return world.OpenGuilds() end
	end
	for _, s in ipairs(spec.members) do
		local m = { key = s[1], guild = s[2], version = s.version, invite = s.invite == true, recruiting = s.recruiting == true,
			rank = s.rank or 3, printed = {}, got = {} }
		world.members[#world.members + 1] = m
		world.byTell[Short(m.key)] = m
	end
	for _, m in ipairs(world.members) do
		if m.version then
			Load(m)
			m.ns.Roster.online = world.Online(m.guild)
			if m.recruiting then eq(world.As(m, m.R.ToggleWhisperRecruiting), true, m.key .. " recruits") end
		end
	end
	-- The requester's whispers reach the member they name, when he is online; his addon reads them.
	w.OnSay = function(text, kind, to)
		local m = kind == "WHISPER" and world.byTell[to]
		if not m then return end
		m.got[#m.got + 1] = { chat = text, at = w.clock }
		world.sends = world.sends or {}
		world.sends[#world.sends + 1] = { m = m, at = w.clock }
		if m.R then w.At(LAT - 0.1, function() world.As(m, m.R.OnWhisper, text, REQUESTER) end) end
	end
	w.OnOutside = function(to, msg)
		local m = world.byTell[to]
		if not m or not m.R then return end
		local kind = msg:sub(1, 2)
		local handler = m.handlers[kind]
		if handler and (kind == "J1" or kind == "J3") then
			w.At(LAT, function() world.As(m, handler, "WHISPER", REQUESTER, msg) end)
		end
	end
	-- /who answers a second after the click, at most 50 of the members, in the spec's order.
	w.OnSearch = function()
		w.At(1, function()
			local list = {}
			for i, m in ipairs(world.members) do
				if i > 50 then break end
				list[#list + 1] = { name = m.key, guild = m.guild, level = 20, class = "WARRIOR" }
			end
			R.OnFound(list)
		end)
	end
	-- An invite popup that opened for the requester at a member whose guild has room: he invites.
	function world.Check()
		for _, m in ipairs(world.members) do
			local f = m.ns and m.ns.Dialog.Find(DRAFT)
			if f and f.data and f.data.req and f.data.req.name == REQUESTER and not world.popups[m] then
				world.popups[m] = w.clock
				if world.guilds[m.guild] < ns.Codec.GUILD_CAP and not world.invited then world.invited = { m = m, at = w.clock } end
			end
		end
	end
	return world
end

---------------------------------------------------------------------------
-- The member's side: his answer says what he can do with a request, and names his guild's recruiters.
---------------------------------------------------------------------------

-- Fails before 1.6.0: an answer said nothing of the member who gave it, and named his guild's Lords and
-- Captains alone, never a member recruiting by whisper.
test("join reach (1.6.0): a member's answer says whether he recruits, can invite or can't, and names his guild's recruiters first", function()
	WithRequester(function(w)
		local world = World(w, {
			guilds = { ["Olympus Alpha"] = 500, ["Olympus Full"] = ns.Codec.GUILD_CAP },
			members = {
				{ "Rae Cole-Realm", "Olympus Alpha", version = "1.6.0", invite = true, recruiting = true },
				{ "Lia Ford-Realm", "Olympus Alpha", version = "1.6.0", invite = true, rank = 0 },
				{ "Ned Park-Realm", "Olympus Alpha", version = "1.6.0" },
				{ "Ora Lund-Realm", "Olympus Alpha", version = "1.6.0", invite = true, recruiting = true, rank = 1 },
				{ "Fay Moor-Realm", "Olympus Full", version = "1.6.0", invite = true, recruiting = true },
			},
		})
		local function Answer(m) return world.As(m, m.R.RouteAnswer) end
		local rae, lia, ned, ora, fay = unpack(world.members)
		local said = {}
		for _, m in ipairs(world.members) do said[#said + 1] = (R.ParseRoute(Answer(m)) or {}).self or "-" end
		eq(table.concat(said, " "), "r i x r x", "recruits, can invite, can't, recruits, a full guild's recruiter can't")
		-- Queue only, or the pop-up interval still running: no pop-up now, the request waits in his list.
		local function Choice(m) for _, v in pairs(m.ns.rdb.recruitmentPreference) do return v end end
		Choice(rae).queueOnly = true
		eq(R.ParseRoute(Answer(rae)).self, "i", "Queue only: it waits in his list")
		Choice(rae).queueOnly = nil
		rae.ns.rdb.recruitAds = { [rae.key] = { guild = "Olympus Alpha", popupGap = 3600, popupAt = w.clock } }
		eq(R.ParseRoute(Answer(rae)).self, "i", "the pop-up interval holds it")
		w.Advance(3600)
		eq(R.ParseRoute(Answer(rae)).self, "r", "the interval past: it pops up again")
		rae.ns.rdb.recruitAds = nil
		-- The guild's recruiters first: himself while he recruits, the others whose hello says so, then its Lord.
		local route = assert(R.ParseRoute(Answer(ned)))
		eq(table.concat(route.byName["Olympus Alpha"].contacts, "/"), "Rae Cole/Ora Lund", "the two recruiting, not the Lord first")
		route = assert(R.ParseRoute(Answer(ora)))
		eq(table.concat(route.byName["Olympus Alpha"].contacts, "/"), "Ora Lund/Rae Cole", "himself first while he recruits")
		route = assert(R.ParseRoute(Answer(lia)))
		eq(route.self, "i"); eq(route.byName["Olympus Alpha"].contacts[1], "Rae Cole")
		-- Recruiting off: the Lord again comes first among the officers, as before 1.6.0.
		world.As(rae, rae.R.ToggleWhisperRecruiting); rae.recruiting = false
		world.As(ora, ora.R.ToggleWhisperRecruiting); ora.recruiting = false
		eq(R.ParseRoute(Answer(rae)).self, "i", "his recruiting off: he can invite")
		eq(table.concat(R.ParseRoute(Answer(ned)).byName["Olympus Alpha"].contacts, "/"), "Lia Ford/Ora Lund", "Lord and Captain, as before")
		-- Do not contact: never named, by himself or (his hello saying nothing of it) through the check his own answer closes.
		ora.ns.db.recruitsOff = true
		world.As(ora, ora.R.ToggleWhisperRecruiting); ora.recruiting = true
		local own = R.ParseRoute(Answer(ora))
		eq(own.dnc, true); eq(own.byName["Olympus Alpha"].contacts[1], "Lia Ford", "never himself while he asks not to be contacted")
		-- A full guild's answer: "x", its guild at 0 and no contacts in it.
		route = assert(R.ParseRoute(Answer(fay)))
		eq(route.self, "x"); eq(route.byName["Olympus Full"].free, 0); eq(#route.byName["Olympus Full"].contacts, 0)
		for _, m in ipairs(world.members) do assert(#Answer(m) <= 250, "one addon message") end
	end)
end)

-- Clients before 1.6.0 read an answer the same way with its new entry as without it, and this build
-- reads theirs (no word of their own) as before.
test("join reach (1.6.0): mixed versions: a 1.5.9 requester reads a 1.6.0 answer's guilds and contacts unchanged; a 1.5.9 answer leaves its member unknown", function()
	WithRequester(function(w)
		local world = World(w, {
			guilds = { ["Olympus Alpha"] = 500, ["Olympus Beta"] = 900 },
			members = {
				{ "Rae Cole-Realm", "Olympus Alpha", version = "1.6.0", invite = true, recruiting = true },
				{ "Old Hand-Realm", "Olympus Beta", version = "1.5.9", invite = true, recruiting = true, rank = 0 },
			},
		})
		local new, old = world.members[1], world.members[2]
		local answer = world.As(new, new.R.RouteAnswer)
		assert(answer:find(";Olympus Alpha=500=", 1, true) or answer:find(";Olympus Beta=100=", 1, true), answer)
		local mine, theirs = R.ParseRoute(answer), old.R.ParseRoute(answer)
		eq(theirs.self, nil, "1.5.9 reads no word of the member's")
		eq(#theirs.list, #mine.list, "the same guilds")
		for i, e in ipairs(mine.list) do
			eq(theirs.list[i].name, e.name); eq(theirs.list[i].free, e.free)
			eq(table.concat(theirs.list[i].contacts, "/"), table.concat(e.contacts, "/"))
		end
		local oldAnswer = world.As(old, old.R.RouteAnswer)
		eq(oldAnswer:find("*=", 1, true), nil, "a 1.5.9 member says nothing of himself")
		eq(R.ParseRoute(oldAnswer).self, nil)
		-- Odd words name nobody and say nothing: only "*=r", "*=i" or "*=x", the first one.
		eq(R.ParseRoute("J2~y~~0~*=z;Olympus Alpha=500=").self, nil)
		eq(R.ParseRoute("J2~y~~0~*=rr;Olympus Alpha=500=").self, nil)
		eq(R.ParseRoute("J2~y~~0~*=x;*=r;Olympus Alpha=500=").self, "x")
		eq(#R.ParseRoute("J2~y~~0~*=x;*=r;Olympus Alpha=500=").list, 1)
	end)
end)

---------------------------------------------------------------------------
-- The requester's side.
---------------------------------------------------------------------------

local function Notice() return select(6, R.JoinStatus()) end
local function Open() return ns.Dialog.Find("OLYMPUS_RECRUIT") end
local function Shows(text)
	for _, l in ipairs(ns.Views.JoinLines(400)) do if l.text == text then return true end end
	return false
end

-- Fails before 1.6.0: the request went to whoever the screen chose; the member's answer could only
-- close it for do not contact, so a member who can't invite got the whisper and the player waited 45 s.
test("join reach (1.6.0): the Join screen passes over a member who can't invite: the window about to go to him closes with the reason and the next member is asked", function()
	WithRequester(function(w)
		R.OnFound({ { name = "Ned Park-Realm", guild = "Olympus Alpha" }, { name = "Lia Ford-Realm", guild = "Olympus Alpha" },
			{ name = "Bo Hart-Realm", guild = "Olympus Beta" } })
		eq(w.out[1].to, "Ned Park"); eq(w.out[1].msg, "J1~1", "the search asked one member where to go")
		eq(R.RequestJoin(), true)
		eq(Open().data.name, "Ned Park-Realm", "his window opens: nothing said of him yet")
		eq(R.OnRoute("Ned Park-Realm", "J2~y~~0~*=x;Olympus Alpha=500=Lia Ford"), true)
		eq(R.SaidOf("Ned Park-Realm"), "x")
		eq(w.printed[1], L.RECRUIT_JOIN_CANT_INVITE:format("Ned Park"))
		eq(Open(), nil, "closed; the one he names is asked first")
		eq(w.out[#w.out].to, "Lia Ford"); eq(w.out[#w.out].msg, "J1~1")
		eq(R.JoinStatus(), true, "the screen is still looking")
		R.OnRoute("Lia Ford-Realm", "J2~y~~0~*=i;Olympus Alpha=500=Lia Ford")
		eq(Open() and Open().data.name, "Lia Ford-Realm", "she can invite: her window")
		eq(#w.said, 0, "no whisper went to the member who can't invite")
		eq(R.NextContact("Olympus Alpha").name, "Lia Ford-Realm", "never him again")
		-- A member clicked in the guild list who said he can't: the reason, and no window.
		Open():Hide()
		local before = #ns.Dialog.shown
		eq(R.Prompt({ name = "Ned Park-Realm", guild = "Olympus Alpha" }), nil)
		eq(#ns.Dialog.shown, before); eq(w.printed[#w.printed], L.RECRUIT_JOIN_CANT_INVITE:format("Ned Park"))
		-- One we did not ask says nothing of himself: an answer from him is no answer.
		eq(R.OnRoute("Bo Hart-Realm", "J2~y~~0~*=x"), false)
		eq(R.SaidOf("Bo Hart-Realm"), nil)
		-- Do not contact on a request the screen chose: closed, and the next member asked, as above.
		eq(R.RequestJoin(), true)
		eq(Open().data.name, "Lia Ford-Realm")
		R.OnRoute("Lia Ford-Realm", "J2~n~~0~")
		eq(w.printed[#w.printed], L.RECRUIT_DNC:format("Lia Ford"))
		eq(Open(), nil)
		eq(w.out[#w.out].to, "Bo Hart", "the next member, asked first")
		w.Advance(R.ROUTE_SETTLE)
		eq(Open() and Open().data.name, "Bo Hart-Realm", "no answer from him: his window after ROUTE_SETTLE")
		eq(#w.said, 0)
	end)
end)

-- Fails before 1.6.0: once the whisper went, nothing the member's answer said shortened the 45 s wait,
-- and the screen said only "No invite yet? Try another member."
test("join reach (1.6.0): a request already sent to one who can't take it stops its wait when the player may send again, with the reason; one to a recruiter says so", function()
	WithRequester(function(w)
		R.OnFound({ { name = "Ned Park-Realm", guild = "Olympus Alpha" }, { name = "Rae Cole-Realm", guild = "Olympus Alpha" } })
		eq(R.RequestJoin(), true)
		Send(Open())
		eq(#w.said, 1); eq(w.said[1].to, "Ned Park")
		local _, left = R.JoinStatus()
		eq(left, 45)
		w.Advance(2)
		R.OnRoute("Ned Park-Realm", "J2~y~~0~*=x;Olympus Alpha=500=")
		_, left = R.JoinStatus()
		eq(left, 18, "the wait ends with the 20 seconds between two requests")
		eq(Notice(), L.RECRUIT_JOIN_CANT_INVITE:format("Ned Park"))
		assert(Shows(L.RECRUIT_JOIN_WAITING:format(18)) and Shows(L.RECRUIT_JOIN_CANT_INVITE:format("Ned Park")), "the wait and the reason under it")
		w.Advance(18)
		assert(Shows(L.RECRUIT_JOIN_CANT_INVITE:format("Ned Park")) and not Shows(L.RECRUIT_JOIN_TIMEOUT), "the reason, then, in the wait's place")
		eq(R.RequestJoin(), true)
		eq(Open().data.name, "Rae Cole-Realm")
		R.OnRoute("Rae Cole-Realm", "J2~y~~0~*=r;Olympus Alpha=500=Rae Cole")
		eq(Open() and Open().data.name, "Rae Cole-Realm", "a recruiter's window stays")
		Send(Open())
		eq(#w.said, 2); eq(w.said[2].to, "Rae Cole")
		eq(Notice(), L.RECRUIT_JOIN_RECRUITS:format("Rae Cole", "Olympus Alpha"), "a recruiter: the screen says so")
		_, left = R.JoinStatus()
		eq(left, 45, "his wait runs its course")
		assert(Shows(L.RECRUIT_JOIN_RECRUITS:format("Rae Cole", "Olympus Alpha")))
	end)
end)

-- Fails before 1.6.0: with everyone found asked, Request again searched, found the same members and
-- did nothing, the screen saying "No invite yet? Try another member." for good (a few members online,
-- as on a PvP realm, made it a dead end); every guild full ended the same way.
test("join reach (1.6.0): nobody left to ask, or every guild full: the screen says why; a member asked REASK ago may be asked again", function()
	WithRequester(function(w)
		w.OnSearch = function() w.At(1, function() R.OnFound(R.found) end) end
		R.OnFound({ { name = "Kai Ford-Realm", guild = "Olympus Pvp" } })
		eq(R.RequestJoin(), true)
		Send(Open())
		w.Advance(45)
		eq(R.RequestJoin(), true, "a new search")
		w.Advance(1)
		eq(Open(), nil, "nobody new")
		eq(Notice(), L.RECRUIT_JOIN_NOBODY, "said why")
		assert(Shows(L.RECRUIT_JOIN_NOBODY) and not Shows(L.RECRUIT_JOIN_TIMEOUT), "on the Join page, in place of 'try another member'")
		w.Advance(R.REASK - 46)
		-- (Review of this lane: the click asked him again without a search, so one who logged in since
		-- was never found. A search runs first; its answer, nobody new, asks him again.)
		local searches = w.searches
		eq(R.RequestJoin(), true)
		eq(w.searches, searches + 1, "a new search before anyone is asked again")
		eq(Open(), nil)
		w.Advance(1 + R.ROUTE_SETTLE)
		eq(Open() and Open().data.name, "Kai Ford-Realm", "asked again REASK after the first time, once the search found nobody new")
	end)
	WithRequester(function(w)
		R.OnFound({ { name = "Fay Moor-Realm", guild = "Olympus Full" }, { name = "Gil Rowe-Realm", guild = "Olympus Packed" } })
		eq(R.RequestJoin(), true)
		eq(Open().data.name, "Fay Moor-Realm")
		R.OnRoute("Fay Moor-Realm", "J2~y~~0~*=x;Olympus Full=0=")
		eq(w.printed[1], L.RECRUIT_JOIN_FULL:format("Olympus Full"), "her guild is full")
		eq(Open(), nil); eq(w.out[#w.out].to, "Gil Rowe", "another guild's member asked first")
		R.OnRoute("Gil Rowe-Realm", "J2~y~~0~*=x;Olympus Packed=0=")
		eq(Open(), nil)
		eq(Notice(), L.RECRUIT_JOIN_ALL_FULL, "every guild found is full")
		assert(Shows(L.RECRUIT_JOIN_ALL_FULL))
		eq(#w.said, 0, "nothing whispered to a full guild")
	end)
end)

-- Fails on this lane's first version (review: a click re-asked a member asked REASK ago instead of
-- searching, so a recruiter who logged in later was never found, and the old members were whispered
-- again and again): with everyone found asked, a click searches; one asked REASK ago is asked again only
-- once the search found nobody new.
test("join reach (1.6.0): with everyone found asked, a click searches first: a member who logged in since is asked before anyone is asked again", function()
	WithRequester(function(w)
		local online = { { name = "Kai Ford-Realm", guild = "Olympus Pvp" } }
		w.OnSearch = function()
			w.At(1, function()
				local list = {}
				for i, p in ipairs(online) do list[i] = p end
				R.OnFound(list)
			end)
		end
		eq(R.RequestJoin(), true)
		w.Advance(1 + R.ROUTE_SETTLE)
		eq(Open() and Open().data.name, "Kai Ford-Realm")
		Send(Open())
		w.Advance(45)
		-- Eleven minutes later another member logs in: /who lists him now, not before.
		w.Advance(R.REASK + 60)
		online[2] = { name = "Nora Wade-Realm", guild = "Olympus Pvp" }
		local searches = w.searches
		eq(R.RequestJoin(), true)
		eq(w.searches, searches + 1, "the click searches: nobody found was never asked")
		eq(Open(), nil, "Kai is not asked again before the search")
		w.Advance(1 + R.ROUTE_SETTLE)
		eq(Open() and Open().data.name, "Nora Wade-Realm", "the member who logged in since")
		Send(Open())
		eq(#w.said, 2); eq(w.said[2].to, "Nora Wade")
		-- Nobody new at the next search: then the one asked REASK ago.
		w.Advance(45)
		eq(R.RequestJoin(), true)
		eq(w.searches, searches + 2)
		w.Advance(1 + R.ROUTE_SETTLE)
		eq(Open() and Open().data.name, "Kai Ford-Realm", "asked again once the search found nobody new")
		eq(#w.said, 2, "nothing whispered without the player's Send")
	end)
end)

-- Fails before 1.6.0: a window open when its guild's answer said full stayed open, and its Send was
-- swallowed without a word (Ask refused it silently).
test("join reach (1.6.0): a guild that fills up while its window is open closes it with the reason and the screen asks a guild with room; a Send to it is refused aloud", function()
	WithRequester(function(w)
		R.OnFound({ { name = "Gil Rowe-Realm", guild = "Olympus Packed" }, { name = "Hal Byrne-Realm", guild = "Olympus Alpha" } })
		eq(R.RequestJoin(), true)
		local f = Open()
		eq(f.data.name, "Gil Rowe-Realm")
		R.OnRoute("Gil Rowe-Realm", "J2~y~~0~*=r;Olympus Packed=12=Gil Rowe")
		eq(Open(), f, "room then: his window stays")
		w.Advance(5)
		R.OnRoute("Gil Rowe-Realm", "J2~y~~0~*=x;Olympus Packed=0=")
		eq(Open(), nil, "closed")
		eq(w.printed[#w.printed], L.RECRUIT_JOIN_FULL:format("Olympus Packed"))
		eq(#w.said, 0)
		w.Advance(R.ROUTE_SETTLE)
		eq(Open() and Open().data.name, "Hal Byrne-Realm", "a guild with room")
		-- The Send itself, should a full guild's window still be up: refused, with the reason, nothing sent.
		R.lastAsk = -1000
		eq(R.Ask({ name = "Gil Rowe-Realm", guild = "Olympus Packed" }, "hi"), false)
		eq(#w.said, 0); eq(w.printed[#w.printed], L.RECRUIT_JOIN_FULL:format("Olympus Packed"))
	end)
end)

-- Fails before 1.6.0: the search's window opened at once on the first member /who listed, before the
-- answer of the member it asked where to go came; that answer chose nothing for the first request.
test("join reach (1.6.0): after a search the first request waits for the asked member's answer and goes to the officer it names", function()
	WithRequester(function(w)
		local list = { { name = "Ned Park-Realm", guild = "Olympus Alpha" }, { name = "Bo Hart-Realm", guild = "Olympus Beta" },
			{ name = "Rae Cole-Realm", guild = "Olympus Alpha" } }
		w.OnSearch = function() w.At(1, function() R.OnFound(list) end) end
		eq(R.RequestJoin(), true)
		w.Advance(1)
		eq(w.out[1].to, "Ned Park"); eq(w.out[1].msg, "J1~1")
		eq(Open(), nil, "his answer first")
		eq(R.JoinStatus(), true, "the screen says it is still looking")
		assert(Shows(L.RECRUIT_SEARCHING))
		R.OnRoute("Ned Park-Realm", "J2~y~~0~*=x;Olympus Beta=700=;Olympus Alpha=500=Rae Cole")
		eq(Open(), nil); eq(w.out[#w.out].to, "Rae Cole", "the officer named, though another guild has more room")
		w.Advance(R.ROUTE_SETTLE)
		eq(Open() and Open().data.name, "Rae Cole-Realm")
		eq(#w.said, 0)
	end)
	WithRequester(function(w)
		w.OnSearch = function() w.At(1, function() R.OnFound({ { name = "Zed Quill-Realm", guild = "Olympus Alpha" } }) end) end
		eq(R.RequestJoin(), true)
		w.Advance(1)
		eq(Open(), nil)
		w.Advance(R.ROUTE_SETTLE)
		eq(Open() and Open().data.name, "Zed Quill-Realm", "no answer at all (no Olympus): his window after ROUTE_SETTLE")
	end)
end)

-- Failure cases of the above, each held since 1.6.0.
test("join reach (1.6.0): failure cases: a window the player closed brings no new one; PROBE_MAX asks a click at most; a recruiter in a full guild is not asked first", function()
	WithRequester(function(w)
		R.OnFound({ { name = "Ned Park-Realm", guild = "Olympus Alpha" }, { name = "Lia Ford-Realm", guild = "Olympus Alpha" } })
		eq(R.RequestJoin(), true)
		Open():Hide() -- the player closes it
		R.OnRoute("Ned Park-Realm", "J2~y~~0~*=x;Olympus Alpha=500=")
		eq(Open(), nil, "no window of the screen's own after the player closed his")
		eq(#w.printed, 0, "nothing said: no window was open")
		eq(R.JoinStatus(), false, "and not looking")
		eq(R.RequestJoin(), true, "his own click asks the next member")
		eq(Open().data.name, "Lia Ford-Realm")
		Open():Hide()
		R.OnRoute("Lia Ford-Realm", "J2~n~~0~")
		eq(Open(), nil, "a do-not-contact answer for a closed window opens none either")
		eq(R.JoinStatus(), false)
	end)
	WithRequester(function(w)
		local list = {}
		for i = 1, 7 do list[i] = { name = ("Member %s-Realm"):format(string.char(64 + i)), guild = "Olympus Alpha" } end
		R.OnFound(list)
		eq(R.RequestJoin(), true)
		eq(Open().data.name, list[1].name)
		local asks = 0
		for _, o in ipairs(w.out) do if o.msg == "J1~1" then asks = asks + 1 end end
		R.OnRoute(list[1].name, "J2~y~~0~*=x;Olympus Alpha=500=")
		for i = 2, 1 + R.PROBE_MAX do
			eq(Open(), nil, "member " .. i .. " asked first")
			eq(w.out[#w.out].to, list[i].name:match("^(.-)%-"))
			R.OnRoute(list[i].name, "J2~y~~0~*=x;Olympus Alpha=500=")
		end
		eq(Open() and Open().data.name, list[2 + R.PROBE_MAX].name, "past PROBE_MAX the next window opens without waiting")
		local now = 0
		for _, o in ipairs(w.out) do if o.msg == "J1~1" then now = now + 1 end end
		eq(now - asks, R.PROBE_MAX + 1, "PROBE_MAX asks, then the window's own")
		eq(#w.said, 0)
	end)
	WithRequester(function(w)
		R.OnFound({ { name = "Fay Moor-Realm", guild = "Olympus Full" }, { name = "Gil Rowe-Realm", guild = "Olympus Alpha" } })
		eq(R.OnRoute("Fay Moor-Realm", "J2~y~~0~*=r;Olympus Full=0="), true)
		eq(R.SaidOf("Fay Moor-Realm"), "r")
		eq(R.NextContact().name, "Gil Rowe-Realm", "her word that she recruits, her guild full: not first")
		eq(R.NextContact("Olympus Full"), nil)
	end)
end)

---------------------------------------------------------------------------
-- The simulation: a fresh unguilded character on the Join page asks the members /who lists, as a
-- player does: Request to join, reads the request four seconds, Send, waits; Request again when the
-- screen lets him (once every 15 seconds at most when nothing came of a click). A recruiter's invite
-- popup in a guild with room is his invite.
---------------------------------------------------------------------------

local function Classify(m)
	if not m.version then return "noaddon" end
	if m.invite and m.recruiting then return "recruiter" end
	if m.invite then return "officer" end
	return "cannot"
end

local function Pattern(text)
	return "^" .. text:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%%%s", ".+") .. "$"
end

local function Play(w, world, seconds)
	local start, readAt, nextClick = w.clock, nil, w.clock
	local stats = { sent = 0, recruiter = 0, officer = 0, cannot = 0, noaddon = 0, full = 0, cannotNew = 0, answered = 0,
		skipped = 0, clicks = 0, swallowed = 0, seen = {}, order = {} }
	local told = { Pattern(L.RECRUIT_DNC) }
	for _, key in ipairs({ "RECRUIT_JOIN_CANT_INVITE", "RECRUIT_JOIN_FULL" }) do
		if L[key] then told[#told + 1] = Pattern(L[key]) end
	end
	local function Reason(text)
		if type(text) ~= "string" then return false end
		for _, p in ipairs(told) do if text:find(p) then return true end end
		return false
	end
	local printed, lastNotice = #w.printed, nil
	while w.clock < start + seconds and not world.invited do
		local f = Open()
		if f then
			readAt = readAt or w.clock
			if w.clock - readAt >= 4 and GetTime() - R.lastAsk >= 20 then
				local said, lines = #w.said, #w.printed
				Send(f)
				-- A Send that whispered nothing and said nothing: swallowed.
				if #w.said == said and #w.printed == lines then stats.swallowed = stats.swallowed + 1 end
				readAt = nil
			end
		else
			readAt = nil
			local searching, left = R.JoinStatus()
			if not searching and left == 0 and w.clock >= nextClick then
				stats.clicks = stats.clicks + 1
				R.RequestJoin()
				nextClick = w.clock + 15
			end
		end
		w.Advance(0.5)
		world.Check()
		-- What the screen told him: a window closed with the reason before any whisper, and of the last one sent.
		for i = printed + 1, #w.printed do if Reason(w.printed[i]) then stats.skipped = stats.skipped + 1 end end
		printed = #w.printed
		local notice = select(6, R.JoinStatus())
		if notice then stats.seen[notice] = true end
		local last = world.sends and world.sends[#world.sends]
		if notice ~= lastNotice and last and not last.answered and Reason(notice) then last.answered = true end
		lastNotice = notice
	end
	for _, s in ipairs(world.sends or {}) do
		stats.sent = stats.sent + 1
		local kind = Classify(s.m)
		stats[kind] = stats[kind] + 1
		stats.order[#stats.order + 1] = ("%s (%s%s)"):format(s.m.key:match("^(%S+)"), kind, s.m.version and (" " .. s.m.version) or "")
		if kind == "cannot" and s.m.version == "1.6.0" then stats.cannotNew = stats.cannotNew + 1 end
		if world.guilds[s.m.guild] >= ns.Codec.GUILD_CAP then stats.full = stats.full + 1 end
		if s.answered or (world.invited and world.invited.m == s.m) then stats.answered = stats.answered + 1 end
	end
	stats.sends = world.sends or {}
	stats.invited = world.invited and 1 or 0
	stats.inviteAfter = world.invited and math.floor(world.invited.at - start) or nil
	-- The Join page's line at the end.
	local after, line = false, nil
	for _, l in ipairs(ns.Views.JoinLines(400)) do
		if after and l.center and not l.onClick and l.text then line = l.text break end
		if l.primary then after = true end
	end
	stats.line = line or "-"
	return stats
end

local function Report(name, s)
	print(("       sim %s: sent %d (recruiter %d, officer not recruiting %d, can't invite %d [1.6.0: %d], no Olympus %d, full guild %d); invited %d%s; answered %d of %d; passed over with a reason %d; Sends swallowed %d; clicks %d")
		:format(name, s.sent, s.recruiter, s.officer, s.cannot, s.cannotNew, s.noaddon, s.full, s.invited,
		s.inviteAfter and (" after " .. s.inviteAfter .. " s") or "", s.answered, s.sent, s.skipped, s.swallowed, s.clicks))
	print(("           asked: %s; last line: %s"):format(#s.order > 0 and table.concat(s.order, ", ") or "nobody", s.line))
end

-- PvE: four guilds, one full; ordinary members first in /who's order (most members can't invite),
-- 1.5.9 and 1.6.0 clients mixed, one member without Olympus; recruiters (a 1.6.0 Captain in the full
-- guild, a 1.6.0 member with the invite right, a 1.5.9 Captain) further down the list, or offline.
local function PvE(recruitersOnline)
	local members = {
		{ "Ann Nolan-Realm", "Olympus Gamma", version = "1.6.0" },
		{ "Bert Ives-Realm", "Olympus Alpha", version = "1.5.9" },
		{ "Cora Vance-Realm", "Olympus Beta", version = "1.6.0" },
		{ "Dale Rowe-Realm", "Olympus Alpha" },
		{ "Edna Pike-Realm", "Olympus Gamma", version = "1.6.0", invite = true, recruiting = true, rank = 1 },
		{ "Finn Hale-Realm", "Olympus Delta", version = "1.5.9" },
		{ "Gwen Lacy-Realm", "Olympus Alpha", version = "1.6.0", invite = true, rank = 0 },
		{ "Hugo Marsh-Realm", "Olympus Beta", version = "1.6.0", invite = true, recruiting = true },
		{ "Iris Dunn-Realm", "Olympus Alpha", version = "1.5.9", invite = true, recruiting = true, rank = 1 },
		{ "Jude Kerr-Realm", "Olympus Beta", version = "1.5.9" },
		{ "Kim Sloan-Realm", "Olympus Delta", version = "1.6.0" },
		{ "Lou Grant-Realm", "Olympus Beta", version = "1.6.0" },
	}
	if not recruitersOnline then
		for i = #members, 1, -1 do
			local k = members[i][1]
			if k == "Edna Pike-Realm" or k == "Hugo Marsh-Realm" or k == "Iris Dunn-Realm" then table.remove(members, i) end
		end
	end
	return { guilds = { ["Olympus Alpha"] = 700, ["Olympus Beta"] = 880, ["Olympus Gamma"] = ns.Codec.GUILD_CAP, ["Olympus Delta"] = 960 },
		members = members }
end

-- PvP: few members online, two guilds; one recruiter (a 1.5.9 Captain) fourth in /who's order, in the
-- guild with less room, or none online.
local function PvP(recruiter)
	local members = {
		{ "Kai Ford-Realm", "Pvp Olympus Two", version = "1.6.0" },
		{ "Lena Moss-Realm", "Pvp Olympus One", version = "1.5.9" },
		{ "Milo Shaw-Realm", "Pvp Olympus Two" },
		{ "Otto Reed-Realm", "Pvp Olympus Two", version = "1.5.9" },
	}
	if recruiter then table.insert(members, 4, { "Nora Wade-Realm", "Pvp Olympus One", version = "1.5.9", invite = true, recruiting = true, rank = 1 }) end
	return { guilds = { ["Pvp Olympus One"] = 800, ["Pvp Olympus Two"] = 500 }, members = members }
end

-- Every guild full: a recruiter in each and ordinary members, all on 1.6.0 (each guild's own members
-- say it is full), or one guild's on 1.5.9 (whose answers can't say it: theirs is asked as before).
local function AllFull(mixed)
	local old = mixed and "1.5.9" or "1.6.0"
	return { guilds = { ["Olympus Gamma"] = ns.Codec.GUILD_CAP, ["Olympus Omega"] = ns.Codec.GUILD_CAP },
		members = {
			{ "Ann Nolan-Realm", "Olympus Gamma", version = "1.6.0" },
			{ "Pia Stone-Realm", "Olympus Omega", version = old },
			{ "Edna Pike-Realm", "Olympus Gamma", version = "1.6.0", invite = true, recruiting = true, rank = 1 },
			{ "Quin Holt-Realm", "Olympus Omega", version = old, invite = true, recruiting = true, rank = 0 },
		} }
end

-- Fails before 1.6.0 (the numbers before and after are in this lane's report): requests went to
-- members who can't invite and to full guilds without a word, the PvP player's screen ran dry and kept
-- saying "No invite yet? Try another member.", and a full army ended the same way.
test("join reach simulation (1.6.0): a fresh character asks from the Join page with recruiters online and offline, on a PvP realm and with every guild full", function()
	local results = {}
	local function Run(name, spec, seconds)
		WithRequester(function(w)
			local s = Play(w, World(w, spec), seconds)
			Report(name, s)
			results[name] = s
		end)
	end
	Run("PvE, recruiters online", PvE(true), 900)
	Run("PvE, recruiters offline", PvE(false), 900)
	Run("PvP, one recruiter (1.5.9)", PvP(true), 900)
	Run("PvP, no recruiter online", PvP(false), 900)
	Run("every guild full (1.6.0)", AllFull(false), 900)
	Run("every guild full (1.5.9 in one)", AllFull(true), 900)
	local on, off, pvp, dry = results["PvE, recruiters online"], results["PvE, recruiters offline"],
		results["PvP, one recruiter (1.5.9)"], results["PvP, no recruiter online"]
	local full, mixed = results["every guild full (1.6.0)"], results["every guild full (1.5.9 in one)"]
	-- Recruiters online: invited at his first request, by a recruiter in a guild with room.
	eq(on.invited, 1, "recruiters online: invited"); eq(on.sent, 1, "at the first request"); eq(on.recruiter, 1)
	-- Recruiters offline: never a 1.6.0 member who can't invite nor a full guild; the screen says why it stops.
	eq(off.cannotNew, 0, "recruiters offline: no request to a 1.6.0 member who can't invite")
	eq(off.full, 0, "recruiters offline: none to a full guild")
	assert(off.seen[L.RECRUIT_JOIN_NOBODY], "recruiters offline: said why once nobody was left")
	-- PvP: the one recruiter reached at the first request; with none online, said why and asked again later.
	eq(pvp.invited, 1, "PvP: invited"); eq(pvp.sent, 1, "PvP: at the first request")
	assert(dry.seen[L.RECRUIT_JOIN_NOBODY], "PvP without a recruiter: said why")
	eq(dry.cannotNew, 0, "PvP without a recruiter: never the 1.6.0 member who can't invite")
	-- Every guild full, said by each guild's own members: no whisper at all, and the screen says why.
	eq(full.sent, 0, "every guild full: nothing sent")
	assert(full.seen[L.RECRUIT_JOIN_ALL_FULL], "every guild full: said so")
	-- One guild's members on 1.5.9 can't say theirs is full: only theirs is asked, never the guild a 1.6.0 member reported full.
	for _, s in ipairs(mixed.sends) do eq(s.m.guild, "Olympus Omega", "only the guild nobody reported full") end
	for _, name in ipairs({ "PvE, recruiters online", "PvE, recruiters offline", "PvP, one recruiter (1.5.9)", "PvP, no recruiter online" }) do
		eq(results[name].full, 0, name .. ": no request to a full guild")
	end
end)

-- Fails on this lane's first version (review): on a realm with more members online than one request
-- every 45 seconds reaches within REASK (about 14), a click never searched again once everyone found
-- had been asked, so a member who logged in later was never asked while the others were whispered
-- three or four times each.
test("join reach simulation (1.6.0): a member who logs in after everyone found was asked is found by the next search and asked", function()
	local function Populous(n)
		local members = {}
		for i = 1, n do
			members[i] = { ("Member%02d Test-Realm"):format(i), i % 2 == 0 and "Olympus Alpha" or "Olympus Beta", version = "1.5.9" }
		end
		return { guilds = { ["Olympus Alpha"] = 600, ["Olympus Beta"] = 700 }, members = members }
	end
	for _, lateAt in ipairs({ 300, 720, 1500 }) do
		WithRequester(function(w)
			local world = World(w, Populous(15))
			local late = { key = "Late Comer-Realm", guild = "Olympus Alpha", printed = {}, got = {}, rank = 3 }
			local searchesAt
			w.At(lateAt, function()
				world.members[#world.members + 1] = late
				world.byTell["Late Comer"] = late
				searchesAt = w.searches
			end)
			local s = Play(w, world, 2400)
			local askedAt, count, most = nil, {}, 0
			for _, x in ipairs(s.sends) do
				count[x.m] = (count[x.m] or 0) + 1
				most = math.max(most, count[x.m])
				if x.m == late and not askedAt then askedAt = math.floor(x.at - 1000) end
			end
			Report(("15 members on 1.5.9, one more online at %d s"):format(lateAt), s)
			print(("           searches after he logged in %d; he was asked %s; most requests to one member %d")
				:format(w.searches - (searchesAt or w.searches), askedAt and ("at " .. askedAt .. " s") or "never", most))
			assert(askedAt, "the member online at " .. lateAt .. " s is asked")
			assert(askedAt <= lateAt + 900, "by the first search once everyone found before him was asked")
		end)
	end
end)
