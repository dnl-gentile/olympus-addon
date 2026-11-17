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
-- rank (0 Lord, 1 Captain, 3 member) }, in the order /who lists them; spec.guilds[name] = members;
-- spec.gates: the guild of the King's gates, or nil.
-- Each member with Olympus runs his own Recruit.lua, his globals put in place while it runs (As).
local function World(w, spec)
	local world = { members = {}, byTell = {}, guilds = spec.guilds, w = w, invited = nil, popups = {} }
	-- spec.gates: the guild the King opened the gates of, as every member's census holds it (Acts.Gates).
	world.gates = spec.gates and { guild = spec.gates, at = w.clock + 7200 } or nil
	local function Short(key) return key:match("^(.-)%-") or key end
	-- (The review of 1.6.0: m.instance, the member in a dungeon; m.locked, in a chat lockdown.)
	function world.As(m, fn, ...)
		local saved = { GetGuildInfo, IsInGuild, CanGuildInvite, GetNumGuildMembers, IsInInstance }
		GetGuildInfo = function() return m.guild end
		IsInGuild = function() return true end
		CanGuildInvite = function() return m.invite == true end
		GetNumGuildMembers = function() local n = world.guilds[m.guild]; return n, n end
		IsInInstance = function() return m.instance == true end
		local ok, a, b = pcall(fn, ...)
		GetGuildInfo, IsInGuild, CanGuildInvite, GetNumGuildMembers, IsInInstance = saved[1], saved[2], saved[3], saved[4], saved[5]
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
			ChatLocked = function() return m.locked == true end, QuietPresence = function() return false end,
			KeyboardFocus = function() return nil end, Quiet = function() return nil end,
			Roster = { RankOf = function() return nil end, online = world.Online(m.guild), Fresh = function() return nil end },
			Data = setmetatable({ AuthorizedRank = function(name, guild) return world.Rank(name, guild) end }, { __index = ns.Data }),
			Acts = { Gates = function() return world.gates end },
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
		-- (Review of this lane) One who recruits and is a Captain too is named once; the Lord next.
		local dup = World(w, { guilds = { ["Olympus Beta"] = 400 }, members = {
			{ "Ann Hale-Realm", "Olympus Beta", version = "1.6.0" },
			{ "Cal Dunn-Realm", "Olympus Beta", version = "1.6.0", invite = true, recruiting = true, rank = 1 },
			{ "Bea Lark-Realm", "Olympus Beta", version = "1.6.0", invite = true, rank = 0 },
		} })
		eq(table.concat(R.ParseRoute(world.As(dup.members[1], dup.members[1].R.RouteAnswer)).byName["Olympus Beta"].contacts, "/"),
			"Cal Dunn/Bea Lark", "the recruiting Captain once, then the Lord")
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

-- Fails on this lane's first version (review): the King's own answer could say he recruits, and the screen
-- then asked him first for every recruit whose question reached him, while the answers never name him (the
-- most asked of all). His own word says at most that he can invite. (The King here is a stand-in name.)
test("join reach (1.6.0): the King's own answer never says he recruits, so the screen does not ask him first", function()
	WithRequester(function(w)
		local world = World(w, {
			guilds = { ["Olympus Alpha"] = 500 },
			members = {
				{ "Rex Crown-Realm", "Olympus Alpha", version = "1.6.0", invite = true, recruiting = true, rank = 0 },
				{ "Rae Cole-Realm", "Olympus Alpha", version = "1.6.0", invite = true, recruiting = true },
			},
		})
		local king, rae = world.members[1], world.members[2]
		local function IsKing(name) return type(name) == "string" and ns.ShortName(name) == "Rex Crown" end
		king.ns.IsKingCharacter, rae.ns.IsKingCharacter = IsKing, IsKing
		eq(R.ParseRoute(world.As(king, king.R.RouteAnswer)).self, "i", "he can invite, and says no more")
		eq(R.ParseRoute(world.As(rae, rae.R.RouteAnswer)).self, "r", "another member who recruits says so")
		-- The recruit's screen: the King's answer comes first (/who lists him first); the member he names next.
		R.OnFound({ { name = king.key, guild = "Olympus Alpha" }, { name = rae.key, guild = "Olympus Alpha" } })
		eq(w.out[1].to, "Rex Crown")
		w.Advance(2 * LAT + 0.1)
		eq(R.SaidOf(king.key), "i")
		eq(R.NextContact().name, rae.key, "not the King first")
		-- No invite right: "x", as anyone's.
		king.invite = false
		eq(R.ParseRoute(world.As(king, king.R.RouteAnswer)).self, "x")
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
		-- (Changed in the review of this lane: the click also asks the members the screen would ask next,
		-- together, so its next choice knows who recruits; it no longer asks them one at a time.)
		local function Asked(name)
			for _, o in ipairs(w.out) do if o.to == name and o.msg == "J1~1" then return true end end
			return false
		end
		assert(Asked("Lia Ford") and Asked("Bo Hart"), "the others asked with the click")
		eq(R.OnRoute("Ned Park-Realm", "J2~y~~0~*=x;Olympus Alpha=500=Lia Ford"), true)
		eq(R.SaidOf("Ned Park-Realm"), "x")
		eq(w.printed[1], L.RECRUIT_JOIN_CANT_INVITE:format("Ned Park"))
		eq(Open(), nil, "closed; the screen waits for the answers of those just asked")
		eq(R.JoinStatus(), true, "the screen is still looking")
		R.OnRoute("Lia Ford-Realm", "J2~y~~0~*=i;Olympus Alpha=500=Lia Ford")
		eq(Open(), nil, "the one he names can invite, but Bo's answer may say he recruits: still waiting")
		w.Advance(R.ROUTE_SETTLE)
		eq(Open() and Open().data.name, "Lia Ford-Realm", "no answer from Bo: the one he names, who can invite")
		eq(#w.said, 0, "no whisper went to the member who can't invite")
		eq(R.NextContact("Olympus Alpha").name, "Lia Ford-Realm", "never him again")
		-- A member clicked in the guild list who said he can't: the reason, and no window.
		Open():Hide()
		local before = #ns.Dialog.shown
		eq(R.Prompt({ name = "Ned Park-Realm", guild = "Olympus Alpha" }), nil)
		eq(#ns.Dialog.shown, before); eq(w.printed[#w.printed], L.RECRUIT_JOIN_CANT_INVITE:format("Ned Park"))
		-- One we did not ask says nothing of himself: an answer from him is no answer.
		eq(R.OnRoute("Cy Lane-Realm", "J2~y~~0~*=x"), false)
		eq(R.SaidOf("Cy Lane-Realm"), nil)
		-- Do not contact on a request the screen chose: closed, and the next member asked, as above.
		eq(R.RequestJoin(), true)
		eq(Open().data.name, "Lia Ford-Realm")
		R.OnRoute("Lia Ford-Realm", "J2~n~~0~")
		eq(w.printed[#w.printed], L.RECRUIT_DNC:format("Lia Ford"))
		eq(Open() and Open().data.name, "Bo Hart-Realm", "the next member at once: asked with the first click, he never answered")
		eq(w.out[#w.out].to, "Bo Hart", "and asked again as his window opens")
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
		eq(f.open, false, "closed")
		eq(w.printed[#w.printed], L.RECRUIT_JOIN_FULL:format("Olympus Packed"))
		eq(#w.said, 0)
		-- (Changed in the review of this lane: Hal was asked with the click and never answered, so his
		-- window opens at once, without another ROUTE_SETTLE.)
		eq(Open() and Open().data.name, "Hal Byrne-Realm", "a guild with room")
		-- The Send itself, should a full guild's window still be up: refused, with the reason, nothing sent.
		-- (Review of this lane: the window's closing printed the same line just before, so the Send's own
		-- line is counted.)
		R.lastAsk = -1000
		local printed = #w.printed
		eq(R.Ask({ name = "Gil Rowe-Realm", guild = "Olympus Packed" }, "hi"), false)
		eq(#w.said, 0)
		eq(#w.printed, printed + 1, "said by the Send itself")
		eq(w.printed[#w.printed], L.RECRUIT_JOIN_FULL:format("Olympus Packed"))
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
		-- (Changed in the review of this lane: then the members it would ask next are asked together, in
		-- its order: the officer named first, though another guild has more room.)
		eq(Open(), nil)
		eq(w.out[#w.out - 1].to, "Rae Cole", "the officer named, first"); eq(w.out[#w.out].to, "Bo Hart")
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
	-- (Changed in the review of this lane: the members are asked together, the click's own ask counted, no
	-- longer one at a time.)
	WithRequester(function(w)
		local list = {}
		for i = 1, 7 do list[i] = { name = ("Member %s-Realm"):format(string.char(64 + i)), guild = "Olympus Alpha" } end
		R.OnFound(list)
		local function Asks()
			local n = 0
			for _, o in ipairs(w.out) do if o.msg == "J1~1" then n = n + 1 end end
			return n
		end
		local before = Asks()
		eq(R.RequestJoin(), true)
		eq(Open().data.name, list[1].name, "the click's window at once")
		eq(Asks() - before, R.PROBE_MAX, "its own ask and the next members', PROBE_MAX in all")
		R.OnRoute(list[1].name, "J2~y~~0~*=x;Olympus Alpha=500=")
		eq(Open(), nil, "the answers of the members asked with the click first")
		for i = 2, R.PROBE_MAX do
			eq(Open(), nil, "still waiting before member " .. i .. "'s answer")
			R.OnRoute(list[i].name, "J2~y~~0~*=x;Olympus Alpha=500=")
		end
		eq(Open() and Open().data.name, list[R.PROBE_MAX + 1].name, "each answered: past PROBE_MAX the next window opens without asking first")
		eq(Asks() - before, R.PROBE_MAX + 1, "PROBE_MAX asks, then the window's own")
		-- (Review of this lane) That window is the screen's own too: his late "x" closes it and asks the next.
		R.OnRoute(list[R.PROBE_MAX + 1].name, "J2~y~~0~*=x;Olympus Alpha=500=")
		eq(Open() and Open().data.name, list[R.PROBE_MAX + 2].name, "his late answer: the next member")
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

-- Fails on this lane's first version (review): a member's own "r", which no other answer confirms, put
-- him before the guild of the King's gates, which counts only once two answers agree. Until the author
-- decides otherwise, the gates' guild comes first (one of its own who recruits before its officers),
-- then a member of another guild who recruits.
test("join reach (1.6.0): the King's gates, two answers agreeing, come before a member of another guild who says he recruits; in the gates' guild one who recruits comes first", function()
	WithRequester(function(w)
		R.OnFound({ { name = "Gale One-Realm", guild = "Olympus Gates" }, { name = "Hart Two-Realm", guild = "Olympus Other" },
			{ name = "Gil Three-Realm", guild = "Olympus Gates" } })
		eq(w.out[1].to, "Gale One")
		R.OnRoute("Gale One-Realm", "J2~y~Olympus Gates~3600~*=i;Olympus Gates=700=Gil Three;Olympus Other=100=")
		eq(w.out[#w.out].to, "Hart Two", "gates one answer named: one more member asked")
		R.OnRoute("Hart Two-Realm", "J2~y~Olympus Gates~3600~*=r;Olympus Gates=700=Gil Three;Olympus Other=100=Hart Two")
		eq(R.Route().gates, "Olympus Gates", "two answers agree on the gates")
		eq(R.SaidOf("Hart Two-Realm"), "r")
		local c = R.NextContact()
		eq(c.name, "Gil Three-Realm", "the gates' officer, before another guild's member who says he recruits")
		eq(c.guild, "Olympus Gates")
		-- Asked within REASK, the gates' guild has nobody left: then the member who recruits elsewhere.
		R.asked["Gil Three-Realm"], R.asked["Gale One-Realm"] = ns.Now(), ns.Now()
		eq(R.NextContact().name, "Hart Two-Realm")
	end)
	WithRequester(function(w)
		R.OnFound({ { name = "Ivy Four-Realm", guild = "Olympus Gates" }, { name = "Hart Two-Realm", guild = "Olympus Other" },
			{ name = "Gil Three-Realm", guild = "Olympus Gates" } })
		R.OnRoute("Ivy Four-Realm", "J2~y~Olympus Gates~3600~*=r;Olympus Gates=700=Gil Three;Olympus Other=100=")
		R.OnRoute("Hart Two-Realm", "J2~y~Olympus Gates~3600~*=r;Olympus Gates=700=Gil Three;Olympus Other=100=Hart Two")
		eq(R.Route().gates, "Olympus Gates")
		eq(R.NextContact().name, "Ivy Four-Realm", "in the gates' guild, one who says he recruits before its officer")
		eq(R.NextContact("Olympus Gates").name, "Ivy Four-Realm", "and so for a click beside that guild")
	end)
	-- Gates only one answer names: no gates, and the member who recruits comes first, as the lane has it.
	WithRequester(function(w)
		R.OnFound({ { name = "Gale One-Realm", guild = "Olympus Gates" }, { name = "Hart Two-Realm", guild = "Olympus Other" },
			{ name = "Gil Three-Realm", guild = "Olympus Gates" } })
		R.OnRoute("Gale One-Realm", "J2~y~Olympus Gates~3600~*=i;Olympus Gates=700=Gil Three;Olympus Other=100=")
		R.OnRoute("Hart Two-Realm", "J2~y~~0~*=r;Olympus Gates=700=Gil Three;Olympus Other=100=Hart Two")
		eq(R.Route().gates, nil, "one answer named them: no gates")
		eq(R.NextContact().name, "Hart Two-Realm", "the member who says he recruits")
	end)
end)

-- Fails on this lane's first version (review): the screen learned who recruits only from the one member
-- it asked at a time, so its "r" pass rarely fired: a recruiter of ordinary rank whom no answer names was
-- asked no sooner than before. The members it would ask next are now asked together, and one whose own
-- answer says he recruits is asked first, as soon as that answer comes.
test("join reach (1.6.0): the members the screen would ask next are asked together; one whose own answer says he recruits is asked first, at once", function()
	WithRequester(function(w)
		local list = { { name = "Ann Hale-Realm", guild = "Olympus Alpha" }, { name = "Ben Ives-Realm", guild = "Olympus Alpha" },
			{ name = "Cal Dunn-Realm", guild = "Olympus Beta" } }
		w.OnSearch = function() w.At(1, function() R.OnFound(list) end) end
		eq(R.RequestJoin(), true)
		w.Advance(1)
		eq(w.out[1].to, "Ann Hale", "the search asked one member where to go")
		eq(#w.out, 1, "the others only once her answer says where to go")
		R.OnRoute("Ann Hale-Realm", "J2~y~~0~*=i;Olympus Alpha=500=;Olympus Beta=100=")
		eq(Open(), nil, "the members it would ask next first")
		local asked = {}
		for _, o in ipairs(w.out) do if o.msg == "J1~1" then asked[#asked + 1] = o.to end end
		eq(table.concat(asked, ", "), "Ann Hale, Ben Ives, Cal Dunn", "asked together, in the screen's order")
		eq(R.JoinStatus(), true, "still looking meanwhile")
		-- Cal's guild is not in his own answer (the census does not confirm it), so no answer names him:
		-- only his own word moves him first.
		R.OnRoute("Cal Dunn-Realm", "J2~y~~0~*=r;Olympus Alpha=500=")
		eq(Open() and Open().data.name, "Cal Dunn-Realm", "he recruits: his window at once, before Ben answered")
		eq(#w.said, 0)
	end)
	-- Every answer in: the window opens then, without waiting out ROUTE_SETTLE; nobody recruits, so the
	-- screen's own first choice.
	WithRequester(function(w)
		local list = { { name = "Ann Hale-Realm", guild = "Olympus Alpha" }, { name = "Ben Ives-Realm", guild = "Olympus Alpha" } }
		w.OnSearch = function() w.At(1, function() R.OnFound(list) end) end
		eq(R.RequestJoin(), true)
		w.Advance(1)
		R.OnRoute("Ann Hale-Realm", "J2~y~~0~*=x;Olympus Alpha=500=")
		eq(Open(), nil)
		R.OnRoute("Ben Ives-Realm", "J2~y~~0~*=i;Olympus Alpha=500=")
		eq(Open() and Open().data.name, "Ben Ives-Realm", "each answered: at once")
	end)
	-- Nobody answers (no Olympus): ROUTE_SETTLE in all after the search, however many it asked meanwhile.
	WithRequester(function(w)
		local list = { { name = "Ann Hale-Realm", guild = "Olympus Alpha" }, { name = "Ben Ives-Realm", guild = "Olympus Alpha" } }
		w.OnSearch = function() w.At(1, function() R.OnFound(list) end) end
		eq(R.RequestJoin(), true)
		w.Advance(1 + R.ROUTE_SETTLE - 0.5)
		eq(Open(), nil)
		w.Advance(0.5)
		eq(Open() and Open().data.name, "Ann Hale-Realm", "ROUTE_SETTLE after the search, not one wait per member")
		local ben = false
		for _, o in ipairs(w.out) do if o.to == "Ben Ives" and o.msg == "J1~1" then ben = true end end
		assert(ben, "Ben was asked meanwhile: his answer serves the next choice")
	end)
	-- The member asked by the search answers at once and the one asked next never does: the window still
	-- opens ROUTE_SETTLE after the search, not ROUTE_SETTLE after the second ask.
	WithRequester(function(w)
		local list = { { name = "Ann Hale-Realm", guild = "Olympus Alpha" }, { name = "Ben Ives-Realm", guild = "Olympus Alpha" } }
		w.OnSearch = function() w.At(1, function() R.OnFound(list) end) end
		eq(R.RequestJoin(), true)
		w.Advance(2)
		R.OnRoute("Ann Hale-Realm", "J2~y~~0~*=i;Olympus Alpha=500=")
		eq(Open(), nil, "Ben is asked now")
		w.Advance(R.ROUTE_SETTLE - 1.5)
		eq(Open(), nil)
		w.Advance(0.5)
		eq(Open() and Open().data.name, "Ann Hale-Realm", "ROUTE_SETTLE after the search in all")
	end)
end)

-- Fails on this lane's first version (review): a member's own word lasts ROUTE_FRESH, as long as REASK. One
-- who said "x" was never whispered, so ten minutes later he counted as never asked: his window opened
-- again and his fresh "x" closed it again, with the same line. One whose answer is older than ROUTE_FRESH
-- is now asked again before his window opens.
test("join reach (1.6.0): a member whose answer is older than ROUTE_FRESH is asked again before his window opens; one who still can't invite is passed over without a word", function()
	WithRequester(function(w)
		R.OnFound({ { name = "Ned Park-Realm", guild = "Olympus Alpha" }, { name = "Lia Ford-Realm", guild = "Olympus Alpha" } })
		R.OnRoute("Ned Park-Realm", "J2~y~~0~*=x;Olympus Alpha=500=")
		eq(R.SaidOf("Ned Park-Realm"), "x")
		eq(R.RequestJoin(), true)
		eq(Open().data.name, "Lia Ford-Realm", "he can't invite: passed over")
		Send(Open())
		local function AsksTo(name)
			local n = 0
			for _, o in ipairs(w.out) do if o.to == name and o.msg == "J1~1" then n = n + 1 end end
			return n
		end
		w.Advance(R.ROUTE_FRESH + 60)
		eq(R.SaidOf("Ned Park-Realm"), nil, "his word is old now")
		local printed, asks = #w.printed, AsksTo("Ned Park")
		eq(R.RequestJoin(), true)
		eq(Open(), nil, "no window for him before his answer")
		eq(AsksTo("Ned Park"), asks + 1, "asked again")
		R.OnRoute("Ned Park-Realm", "J2~y~~0~*=x;Olympus Alpha=500=")
		eq(Open(), nil)
		eq(#w.printed, printed, "no window of his to close: nothing said")
		w.Advance(R.ROUTE_SETTLE)
		eq(Open() and Open().data.name, "Lia Ford-Realm", "then the one asked REASK ago")
		eq(#w.said, 1)
	end)
end)

-- Fails on this lane's first version (review): the line saying that the member asked recruits stayed once
-- his wait was over and no invite had come, where "No invite yet? Try another member." belongs.
test("join reach (1.6.0): the line that the member asked recruits shows while his wait runs; after it, the screen says no invite came", function()
	local line = L.RECRUIT_JOIN_RECRUITS:format("Rae Cole", "Olympus Alpha")
	WithRequester(function(w)
		R.OnFound({ { name = "Rae Cole-Realm", guild = "Olympus Alpha" }, { name = "Ned Park-Realm", guild = "Olympus Alpha" } })
		R.OnRoute("Rae Cole-Realm", "J2~y~~0~*=r;Olympus Alpha=500=Rae Cole")
		eq(R.RequestJoin(), true)
		eq(Open().data.name, "Rae Cole-Realm")
		Send(Open())
		assert(Shows(L.RECRUIT_JOIN_WAITING:format(45)) and Shows(line), "while the wait runs: the wait, the line under it")
		w.Advance(44)
		assert(Shows(L.RECRUIT_JOIN_WAITING:format(1)) and Shows(line))
		w.Advance(2)
		assert(Shows(L.RECRUIT_JOIN_TIMEOUT), "no invite yet: try another member")
		assert(not Shows(line), "no longer that an invite should come")
		eq(Notice(), nil)
	end)
	-- His answer came after the request went (JoinRecheck): the same.
	WithRequester(function(w)
		R.OnFound({ { name = "Rae Cole-Realm", guild = "Olympus Alpha" } })
		eq(R.RequestJoin(), true)
		Send(Open())
		w.Advance(1)
		R.OnRoute("Rae Cole-Realm", "J2~y~~0~*=r;Olympus Alpha=500=Rae Cole")
		eq(Notice(), line)
		assert(Shows(line))
		w.Advance(45)
		assert(Shows(L.RECRUIT_JOIN_TIMEOUT) and not Shows(line), "after the wait: no invite yet")
	end)
end)

-- Fails on this lane's first version (review): a wait cut to the 20 seconds between two requests kept its
-- reminder at 45 seconds, 25 seconds after the page already offered Request again. (WithRequester turns
-- reminders off; this one turns them on, as they are by default.)
test("join reach (1.6.0): with reminders on, a wait the member's answer cut short brings its reminder when it ends, once", function()
	WithRequester(function(w)
		ns.db.joinReminderOff = nil
		local function Retries()
			local n = 0
			for _, f in ipairs(ns.Dialog.shown) do if f.which == "OLYMPUS_RECRUIT_RETRY" then n = n + 1 end end
			return n
		end
		R.OnFound({ { name = "Ned Park-Realm", guild = "Olympus Alpha" }, { name = "Rae Cole-Realm", guild = "Olympus Alpha" } })
		eq(R.RequestJoin(), true)
		eq(Open().data.name, "Ned Park-Realm")
		Send(Open())
		w.Advance(2)
		R.OnRoute("Ned Park-Realm", "J2~y~~0~*=x;Olympus Alpha=500=")
		local _, left = R.JoinStatus()
		eq(left, 18, "the wait ends with the 20 seconds between two requests")
		w.Advance(17.5)
		eq(Retries(), 0, "not before the wait ends")
		w.Advance(0.5)
		eq(Retries(), 1, "the reminder when the wait ends")
		w.Advance(30)
		eq(Retries(), 1, "once: not again at 45 seconds")
	end)
end)

-- Fails on this lane's first version (review): the Where to go tooltips still said a click asks one of the
-- guild's Lords or Captains (one of its officers), while since 1.6.0 it asks first the recruiters a 1.6.0
-- member of that guild names, of any rank.
test("join reach (1.6.0): Where to go says a click asks one of the guild's recruiters, Lords or Captains; the click asks the recruiter its member names first", function()
	WithRequester(function(w)
		R.OnFound({ { name = "Ned Park-Realm", guild = "Olympus Alpha" }, { name = "Lia Ford-Realm", guild = "Olympus Alpha" },
			{ name = "Rae Cole-Realm", guild = "Olympus Alpha" } })
		-- Ned (1.6.0) names Rae, who recruits at an ordinary rank, before Lia, the guild's Lord.
		R.OnRoute("Ned Park-Realm", "J2~y~~0~*=x;Olympus Alpha=500=Rae Cole/Lia Ford")
		local texts, click = {}, nil
		local tt = { AddLine = function(_, text) texts[#texts + 1] = text end }
		local inRoute = false
		for _, l in ipairs(ns.Views.RecruitLines()) do
			if l.header and l.text == L.RECRUIT_ROUTE_TITLE then inRoute = true; l.tooltip(tt) end
			if inRoute and not click and l.onClick and l.text and l.text:find("Olympus Alpha", 1, true) then click = l; l.tooltip(tt) end
		end
		local tip = table.concat(texts, "\n")
		assert(tip:find(L.RECRUIT_ROUTE_TIP:format("Ned Park"), 1, true), "the route's tooltip")
		assert(tip:find(L.RECRUIT_ROUTE_ASK_TIP, 1, true), "the guild's tooltip")
		assert(L.RECRUIT_ROUTE_TIP:find("recruiters, Lords or Captains", 1, true), "says the click asks a recruiter, Lord or Captain")
		assert(L.RECRUIT_ROUTE_ASK_TIP:find("recruiters or officers", 1, true), "says the whisper goes to a recruiter or an officer")
		click.onClick()
		eq(Open() and Open().data.name, "Rae Cole-Realm", "the click asks the recruiter he names first, as the tooltips say")
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
	stats.invitedInto = world.invited and world.invited.m.guild or nil
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

-- PvP (review of this lane): a recruiter of ordinary rank on 1.6.0, fourth in /who's order, whom no census
-- names and whose guildmates, on 1.5.9, name nobody.
local function PvPOrdinary()
	return { guilds = { ["Pvp Olympus One"] = 800, ["Pvp Olympus Two"] = 500 }, members = {
		{ "Kai Ford-Realm", "Pvp Olympus Two", version = "1.5.9" },
		{ "Lena Moss-Realm", "Pvp Olympus One", version = "1.5.9" },
		{ "Milo Shaw-Realm", "Pvp Olympus Two" },
		{ "Rex Dorn-Realm", "Pvp Olympus One", version = "1.6.0", invite = true, recruiting = true, rank = 3 },
	} }
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

-- The King's gates (every member's census holds them) and a recruiter in another guild, on 1.6.0: the
-- gates' guild has a member who can't invite and a Captain who recruits.
local function Gates()
	return { gates = "Olympus Gates", guilds = { ["Olympus Gates"] = 300, ["Olympus Other"] = 900 },
		members = {
			{ "Gale One-Realm", "Olympus Gates", version = "1.6.0" },
			{ "Hart Two-Realm", "Olympus Other", version = "1.6.0", invite = true, recruiting = true },
			{ "Gil Three-Realm", "Olympus Gates", version = "1.6.0", invite = true, recruiting = true, rank = 1 },
		} }
end

-- Fails before 1.6.0 (the numbers before and after are in this lane's report): requests went to
-- members who can't invite and to full guilds without a word, the PvP player's screen ran dry and kept
-- saying "No invite yet? Try another member.", and a full army ended the same way.
test("join reach simulation (1.6.0): a fresh character asks from the Join page with recruiters online and offline, on a PvP realm and with every guild full", function()
	local results = {}
	local function Run(name, spec, seconds, lat)
		local saved = LAT
		LAT = lat or saved
		WithRequester(function(w)
			local s = Play(w, World(w, spec), seconds)
			Report(name, s)
			results[name] = s
		end)
		LAT = saved
	end
	Run("PvE, recruiters online", PvE(true), 900)
	Run("PvE, recruiters offline", PvE(false), 900)
	Run("PvP, one recruiter (1.5.9)", PvP(true), 900)
	Run("PvP, no recruiter online", PvP(false), 900)
	Run("PvP, one recruiter (1.6.0, ordinary rank)", PvPOrdinary(), 900)
	Run("every guild full (1.6.0)", AllFull(false), 900)
	Run("every guild full (1.5.9 in one)", AllFull(true), 900)
	Run("the King's gates, a recruiter in another guild", Gates(), 900)
	-- Slow whispers (review of this lane): 2.5 seconds each way, longer than ROUTE_SETTLE for an answer.
	Run("PvE, recruiters online, slow whispers", PvE(true), 900, 2.5)
	Run("PvE, recruiters offline, slow whispers", PvE(false), 900, 2.5)
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
	-- (Review of this lane) A recruiter nobody names, fourth on /who: asked with the first click's members,
	-- he is asked first.
	local ordinary = results["PvP, one recruiter (1.6.0, ordinary rank)"]
	eq(ordinary.invited, 1, "PvP, ordinary recruiter: invited"); eq(ordinary.sent, 1, "PvP, ordinary recruiter: at the first request")
	eq(dry.cannotNew, 0, "PvP without a recruiter: never the 1.6.0 member who can't invite")
	-- Every guild full, said by each guild's own members: no whisper at all, and the screen says why.
	eq(full.sent, 0, "every guild full: nothing sent")
	assert(full.seen[L.RECRUIT_JOIN_ALL_FULL], "every guild full: said so")
	-- One guild's members on 1.5.9 can't say theirs is full: only theirs is asked, never the guild a 1.6.0 member reported full.
	for _, s in ipairs(mixed.sends) do eq(s.m.guild, "Olympus Omega", "only the guild nobody reported full") end
	-- (Review of this lane) The King's gates first: a member's own word that he recruits elsewhere does not
	-- draw the recruit away from the guild two answers confirm.
	-- (Review of this lane) Slow whispers: a member's answer comes after his window opened, and closes it
	-- before the player sends; once known, a member who can't invite gets no request, ten minutes later
	-- too.
	local slowOn, slowOff = results["PvE, recruiters online, slow whispers"], results["PvE, recruiters offline, slow whispers"]
	eq(slowOn.invited, 1, "slow whispers: invited")
	eq(slowOff.cannotNew, 0, "slow whispers, recruiters offline: no request to a 1.6.0 member who can't invite")
	local gates = results["the King's gates, a recruiter in another guild"]
	eq(gates.invited, 1, "gates: invited"); eq(gates.invitedInto, "Olympus Gates", "into the gates' guild")
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

-- The review of 1.6.0. A recruiter in a dungeon said a request pops up for her now ("r", her recruiting on)
-- while her popups wait for the dungeon's end (Recruit.PopupsWait): the screen sent her the first request,
-- and the recruit waited out her 45 s for nothing (the other recruiter's invite after 56 s, 6 s with nobody
-- in a dungeon). In an instance or a chat lockdown her word says it waits in her list ("i"), and her own
-- answer names the guild's other recruiter first. Fails before: "r" in the dungeon, she named herself
-- first, the first request went to her and the invite came after 56 s. (1.6.0, the author's ask of 11-16)
-- So while she paused recruiting from a popup's Pause recruiting (Recruit.Pause): fails before it, no pause.
test("join reach (1.6.0): a recruiter in a dungeon, a chat lockdown or a pause says a request waits in her list: the screen asks the guild's other recruiter first, and the invite comes within the first request's wait", function()
	for _, away in ipairs({ "instance", "locked", "paused" }) do
		WithRequester(function(w)
			local world = World(w, {
				guilds = { ["Olympus Alpha"] = 500 },
				members = {
					{ "Rae Cole-Realm", "Olympus Alpha", version = "1.6.0", invite = true, recruiting = true, rank = 3 },
					{ "Lia Ford-Realm", "Olympus Alpha", version = "1.6.0", invite = true, recruiting = true, rank = 1 },
				},
			})
			local rae, lia = world.members[1], world.members[2]
			if away == "paused" then eq(world.As(rae, rae.R.Pause, 15), true, "she pauses for 15 minutes") else rae[away] = true end
			local route = assert(R.ParseRoute(world.As(rae, rae.R.RouteAnswer)))
			eq(route.self, "i", away .. ": a request waits in her list")
			eq(route.byName["Olympus Alpha"].contacts[1], "Lia Ford", away .. ": her answer names the other recruiter first")
			local s = Play(w, world, 300)
			eq(s.sends[1] and s.sends[1].m, lia, away .. ": the first request to the recruiter whose popups are free")
			assert(s.inviteAfter and s.inviteAfter < 45, away .. ": invited within the first request's wait: " .. tostring(s.inviteAfter))
			if away == "paused" then eq(world.As(rae, rae.R.Resume), true, "she resumes") else rae[away] = nil end
			eq(R.ParseRoute(world.As(rae, rae.R.RouteAnswer)).self, "r", away .. " over: a request pops up for her again")
		end)
	end
end)

-- The review of 1.6.0. docs/CURSEFORGE.md keeps the README's privacy table in step, row for row; the answer's
-- (J2) row was written apart for 1.6.0 and said what the member can do in other words ("whether you
-- recruit"), never that the answer says whether a request pops up for him now. Fails before: the two rows
-- differed.
test("join reach (1.6.0): the README's and the CurseForge page's privacy tables give the answer's (J2) row in the same words", function()
	local root = ADDON:match("^(.*)Olympus/$") or "./"
	local function Row(file)
		local f = assert(io.open(root .. file, "r"))
		local text = f:read("*a")
		f:close()
		local rows = {}
		for row in ("\n" .. text):gmatch("\n(| The answer %(J2%)[^\n]*)") do rows[#rows + 1] = row end
		eq(#rows, 1, file .. ": one J2 row")
		return rows[1]
	end
	local readme = Row("README.md")
	assert(readme:find("whether a request pops up for you now", 1, true), "(the README's row says what the answer says of the member)")
	eq(Row("docs/CURSEFORGE.md"), readme, "the CurseForge page's J2 row is the README's")
end)
