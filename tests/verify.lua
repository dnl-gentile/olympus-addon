-- Guild verification (Verify.lua): a guild master verified by a verifier (the King, a High
-- Councillor, the author); the guild's 48-hour clock, the same on every client; the notices; the
-- verifiers' page; the hold of an overdue guild master's own powers; the switches.
-- A small world of clients, each with the real Locales/VerifyText.lua and Verify.lua loaded into a
-- namespace of its own over the harness's, talking through a stand-in channel (the server stamps
-- the sender; CHANNEL reaches every other client online). Every name here is invented, but the
-- King's and the author's, which come from Core.lua's own constants. Every test name starts with
-- "verify:", so
--   luajit tests/run.lua "verify:"
-- runs them alone.
local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]verify%.lua$")) or "./"
local ADDON_DIR = ROOT .. "Olympus/"

local T0 = 1800000000 -- the server's clock when each world starts
local H = 3600
local GUILD, OTHER, ROGUES, HEARTH = "Olympus Vanguard", "Olympus Embers", "Olympus Rogues", "Olympus Hearth"
local HC, HC2 = "Vera Stone-Realm", "Odo Marsh-Realm"
local GM, GM2 = "Bram Hollow-Realm", "Corin Ash-Realm"
local MEMBER, FORGER, LATE = "Pip Fennel-Realm", "Mallo Crook-Realm", "Tamsin Reed-Realm"
local KING = ns.KingCharacter() .. "-Realm"
local AUTHOR = ns.AUTHOR .. "-" .. ns.AUTHOR_REALM

local function Find(list, needle)
	for _, s in ipairs(list) do if tostring(s):find(needle, 1, true) then return s end end
	return nil
end

-- A world: w.Client(name, guild, rank) makes a client; w.As(c, fn, ...) runs fn as that client (the
-- game's guild functions answer for it); w.Census(guild, leader, total) puts a census row on every
-- client; w.Run() runs the timers due. Everything put back after.
local function World(fn)
	local saved = { council = ns.rdb.council, gi = GetGuildInfo, ig = IsInGuild }
	local dialogs = {}
	for k, v in pairs(StaticPopupDialogs) do dialogs[k] = v end
	ns.rdb.council = { at = 1, names = { ["vera stone"] = "Vera Stone", ["odo marsh"] = "Odo Marsh" } }
	local w = { now = T0, clients = {}, sent = {}, timers = {}, available = {} }
	function w.As(c, f, ...)
		local sg, si = GetGuildInfo, IsInGuild
		GetGuildInfo = function() return c.guild, c.rank == 0 and "Guild Master" or "Member", c.rank end
		IsInGuild = function() return c.guild ~= nil end
		local res = { pcall(f, ...) }
		GetGuildInfo, IsInGuild = sg, si
		if not res[1] then error(res[2], 0) end
		return unpack(res, 2, table.maxn(res))
	end
	function w.Deliver(from, dist, msg, logged)
		w.sent[#w.sent + 1] = { from = from.me, dist = dist, msg = msg, logged = logged }
		if dist ~= "CHANNEL" then return end
		for _, c in ipairs(w.clients) do
			if c ~= from and c.online and c.handler then w.As(c, c.handler, "CHANNEL", from.me, msg) end
		end
	end
	function w.Run()
		local list = w.timers
		w.timers = {}
		for _, t in ipairs(list) do
			if t.at <= w.now then w.As(t.c, t.fn) else w.timers[#w.timers + 1] = t end
		end
	end
	function w.Client(name, guild, rank)
		local c = setmetatable({ me = name, realm = "Realm", rdb = { guilds = {} }, L = setmetatable({}, { __index = ns.L }),
			guild = guild, rank = rank, online = true, printed = {}, copies = {}, whispers = {}, dialogs = {}, RealmPages = {} }, { __index = ns })
		c.Print = function(m) c.printed[#c.printed + 1] = tostring(m) end
		c.Fire, c.On, c.RegisterEvent = function() end, function() end, function() end
		c.After = function(sec, _, f) w.timers[#w.timers + 1] = { at = w.now + sec, fn = f, c = c } end
		c.Every = function() return { Cancel = function() end } end
		c.Now = function() return w.now end
		c.UI = { Refresh = function() end, SelectTab = function(tab) c.tab = tab end,
			ShowCopy = function(title, text, action, opts) c.copies[#c.copies + 1] = { title = title, text = text, action = action, opts = opts } return {} end,
			WhisperText = function(to, text) c.whispers[#c.whispers + 1] = { to = to, text = text } return {} end }
		c.ShowDialog = function(which, text, _, data) c.dialogs[#c.dialogs + 1] = { which = which, text = text, data = data } return {} end
		c.Comm = { Handle = function(kind, f) if kind == "GV" then c.handler = f end end,
			Send = function(dist, msg, _, _, logged) w.Deliver(c, dist, msg, logged) return true end,
			SendChunked = function(payload, _, dist, _, options)
				if options and options.permit and not options.permit(options.owner, options.key, dist, nil, payload) then return false end
				w.Deliver(c, dist, payload)
				return true
			end }
		c.Workshop = setmetatable({ Available = function() return w.available end, AskCouncil = function(text)
			c.asked, c.askCalls = text, (c.askCalls or 0) + 1
			return c.helpQueued ~= false -- Workshop's result means queued, not remotely acknowledged.
		end,
			AuthorOnline = function() return false end }, { __index = ns.Workshop })
		assert(loadfile(ADDON_DIR .. "Locales/VerifyText.lua"))("Olympus", c)
		assert(loadfile(ADDON_DIR .. "Verify.lua"))("Olympus", c)
		c.Verify.Clock = function() return w.now end
		c.Verify.random = function(a) return a end
		w.clients[#w.clients + 1] = c
		return c
	end
	-- A census row on every client (and on those made later: w.rows).
	w.rows = {}
	function w.Census(guild, leader, total)
		w.rows[guild] = { leader = leader, total = total or 100 }
		for _, c in ipairs(w.clients) do
			c.rdb.guilds[guild] = { leader = leader, realm = "Realm", total = total or 100, online = 10, t = w.now }
		end
	end
	function w.Status(c, guild) return w.As(c, c.Verify.Status, guild) end
	local ok, err = pcall(fn, w)
	ns.rdb.council, GetGuildInfo, IsInGuild = saved.council, saved.gi, saved.ig
	for k in pairs(StaticPopupDialogs) do StaticPopupDialogs[k] = dialogs[k] end
	if not ok then error(err, 0) end
end

test("verify: verification recovery distinguishes different words with the same counts and clock", function()
	World(function(w)
		local hc = w.Client(HC, HEARTH, 3)
		local member = w.Client(MEMBER, GUILD, 3)
		w.Census(GUILD, "Bram Hollow", 120)
		w.Census(OTHER, "Corin Ash", 80)
		-- Each holds a genuine but different approval, made on the same second.
		member.online = false
		w.As(hc, hc.Verify.Approve, GUILD, GM)
		hc.online, member.online = false, true
		w.As(member, member.Verify.Handle, "CHANNEL", HC, ("GV~1~A~%d~%s~%s"):format(w.now, OTHER, GM2))
		hc.online = true
		local n, newest, starts = w.As(hc, hc.Verify.Digest)
		local n2, newest2, starts2 = w.As(member, member.Verify.Digest)
		eq(n, n2); eq(newest, newest2); eq(starts, starts2)
		w.As(member, member.Verify.Ask)
		w.now = w.now + 9; w.Run()
		eq(w.Status(member, GUILD), "verified", "equal counts do not prove equal approvals")
		local _, info = w.Status(member, GUILD)
		eq(info.entry.at, T0); eq(info.entry.by, HC, "recovered, not approved again")
	end)
end)

---------------------------------------------------------------------------
-- Who approves
---------------------------------------------------------------------------

-- Competing legitimate verifiers may hold different parts of the saved decisions.
-- A smaller, faster answer must not silence the holder of the missing original words.
local function RecoveryCoverage(kind, fullExpected)
	World(function(w)
		local full = w.Client(HC, HEARTH, 3)
		local fast = w.Client(HC2, ROGUES, 3)
		local member = w.Client(MEMBER, GUILD, 3)
		full.Verify.random = function(_, b) return b end
		w.Census(GUILD, "Bram Hollow", 120)
		w.Census(OTHER, "Corin Ash", 80)
		local function Word(c, k, guild, gm, at)
			eq(w.As(c, c.Verify.Handle, "CHANNEL", HC, ("GV~1~%s~%d~%s~%s"):format(k, at, guild, gm)), true)
		end
		local function Start(c, at)
			eq(w.As(c, c.Verify.Handle, "CHANNEL", HC,
				("GV~1~S~%d~T,%d,%s,%s"):format(w.now, at, OTHER, HC)), true)
		end
		Word(full, "A", GUILD, GM, T0 - 100)
		Word(fast, "A", GUILD, GM, T0 - 100)
		if kind == "start" then
			Start(full, T0 - 90); Start(fast, T0 - 50)
		else
			Word(full, kind == "revocation" and "R" or "A", OTHER, GM2, T0 - 80)
			if kind ~= "subset" then
				Word(fast, "A", OTHER, GM2, kind == "revocation" and T0 - 95 or T0 - 80)
			end
			if kind == "superset" then Word(fast, "A", ROGUES, FORGER, T0 - 70) end
		end
		w.As(member, member.Verify.Ask)
		w.now = T0 + 2; w.Run() -- the smaller/equal/larger fast answer reaches everyone
		eq(fast.Verify.Stats().answered, 1)
		w.now = T0 + 9; w.Run()
		eq(full.Verify.Stats().answered, fullExpected, "only a covering snapshot suppresses the pending answer")
		if kind == "start" then
			eq(w.As(member, member.Verify.Start, OTHER), T0 - 90, "the earliest original start reaches the requester")
			eq(w.As(full, full.Verify.Start, OTHER), T0 - 90, "the newer snapshot never resets the clock")
		elseif kind == "revocation" then
			local _, info = w.Status(member, OTHER)
			eq(info.revoked.at, T0 - 80, "a newer original revocation reaches the requester")
			eq(info.revoked.by, HC)
		else
			local status, info = w.Status(member, OTHER)
			eq(status, "verified"); eq(info.entry.at, T0 - 80); eq(info.entry.by, HC)
			if kind == "superset" then eq(w.Status(member, ROGUES), "verified") end
		end
		for _, p in ipairs(w.sent) do
			if p.msg:match("^GV~1~S~") then assert(#p.msg <= full.Verify.MAX_BYTES, "existing byte budget retained") end
		end
		if kind == "subset" then
			for _ = 1, 5 do w.As(full, full.Verify.Handle, "CHANNEL", MEMBER, "GV~1~Q~0~0~0") end
			w.now = T0 + 20; w.Run()
			eq(full.Verify.Stats().answered, 1, "duplicate asks retain the 180-second answer budget")
			w.now = T0 + 9 + full.Verify.ANSWER_GAP
			for _ = 1, 5 do w.As(full, full.Verify.Handle, "CHANNEL", MEMBER, "GV~1~Q~0~0~0") end
			w.now = w.now + 9; w.Run()
			eq(full.Verify.Stats().answered, 2, "later repeated asks coalesce to one answer")
		end
	end)
end

test("verify: recovery coverage retains a richer answer after a smaller snapshot and keeps its send budget", function()
	RecoveryCoverage("subset", 1)
end)
test("verify: recovery coverage suppresses an answer already delivered by an equal snapshot", function()
	RecoveryCoverage("equal", 0)
end)
test("verify: recovery coverage suppresses an answer already delivered by a superset snapshot", function()
	RecoveryCoverage("superset", 0)
end)
test("verify: recovery coverage delivers the latest revocation after an older approval snapshot", function()
	RecoveryCoverage("revocation", 1)
end)
test("verify: recovery coverage delivers the earliest start without resetting its original clock", function()
	RecoveryCoverage("start", 1)
end)

test("verify: an approval is taken only from the King, a High Councillor or the author; a member's forged word or relay is refused", function()
	World(function(w)
		local hc = w.Client(HC, HEARTH, 3)
		local king = w.Client(KING, "Olympus", 0)
		local author = w.Client(AUTHOR, HEARTH, 3)
		local forger = w.Client(FORGER, ROGUES, 3)
		local member = w.Client(MEMBER, GUILD, 3)
		w.Census(GUILD, "Bram Hollow", 120)
		w.Census(OTHER, "Corin Ash", 40)
		w.Census(ROGUES, "Mallo Crook", 12)
		-- A member's word, as a modified client would send it: refused on every client.
		w.Deliver(forger, "CHANNEL", ("GV~1~A~%d~%s~%s"):format(w.now, GUILD, GM))
		eq(w.Status(member, GUILD), "pending", "a member's word verifies nothing")
		eq(w.Status(hc, GUILD), "pending")
		-- His own client refuses to say it at all.
		local ok, why = w.As(forger, forger.Verify.Approve, ROGUES, FORGER)
		eq(ok, false); eq(why, "trust")
		w.As(forger, forger.Verify.Slash, "approve " .. ROGUES)
		assert(Find(forger.printed, forger.L.VERIFY_ONLY), "told he can't")
		-- A forged relay: refused too.
		w.Deliver(forger, "CHANNEL", ("GV~1~S~%d~A,%d,%s,Bram Hollow,Vera Stone"):format(w.now, w.now, GUILD))
		eq(w.Status(member, GUILD), "pending", "a member's relay verifies nothing")
		assert(member.Verify.Stats().refused >= 2, "both counted refused")
		-- A High Councillor's approval: every client online takes it, logged on the channel.
		w.now = w.now + 60
		ok = w.As(hc, hc.Verify.Approve, GUILD)
		eq(ok, true)
		local last = w.sent[#w.sent]
		eq(last.msg, ("GV~1~A~%d~%s~%s"):format(w.now, GUILD, GM)); eq(last.logged, true, "logged: the server keeps who approved")
		eq(w.Status(member, GUILD), "verified")
		eq(w.Status(forger, GUILD), "verified")
		assert(Find(member.printed, "now verified"), "its members are told")
		-- The King's and the author's approvals count too.
		w.now = w.now + 60
		eq((w.As(king, king.Verify.Approve, OTHER)), true)
		eq(w.Status(member, OTHER), "verified", "the King")
		w.now = w.now + 60
		eq((w.As(author, author.Verify.Approve, ROGUES)), true)
		eq(w.Status(member, ROGUES), "verified", "the author")
		local _, info = w.Status(member, ROGUES)
		eq(info.entry.by, AUTHOR, "by the server's sender, never a name in the message")
	end)
end)

test("verify: a verification belongs to the guild and its guild master: a new guild master needs a fresh check, on the guild's same clock", function()
	World(function(w)
		local hc = w.Client(HC, HEARTH, 3)
		local member = w.Client(MEMBER, GUILD, 3)
		w.Census(GUILD, "Bram Hollow", 120)
		w.As(hc, hc.Verify.Observe)
		w.As(member, member.Verify.Observe)
		w.now = T0 + H
		w.As(hc, hc.Verify.Approve, GUILD)
		eq(w.Status(member, GUILD), "verified")
		-- Another guild master, 10 hours in: the approval lapses, the clock does not restart.
		w.now = T0 + 10 * H
		w.Census(GUILD, "Corin Ash", 120)
		local status, info = w.Status(member, GUILD)
		eq(status, "pending"); eq(info.lapsed, true); eq(info.since, T0, "the guild's start kept")
		eq(info.left, 38 * H)
		w.now = T0 + 49 * H
		eq(w.Status(member, GUILD), "overdue", "48 hours from the guild's start, not from the new guild master")
		eq(w.As(member, member.MasterHeld, GUILD), true, "the new guild master's own powers wait")
		-- The new guild master verified: it stands again.
		w.As(hc, hc.Verify.Approve, GUILD)
		eq(w.Status(member, GUILD), "verified")
		eq(w.As(member, member.MasterHeld, GUILD), false)
		-- The old one back: that approval was the new one's.
		w.Census(GUILD, "Bram Hollow", 120)
		status, info = w.Status(member, GUILD)
		eq(status, "overdue"); eq(info.lapsed, true)
	end)
end)

---------------------------------------------------------------------------
-- The clock
---------------------------------------------------------------------------

test("verify: the earliest start a verifier gave wins, in any order, and a reinstall never restarts the clock", function()
	World(function(w)
		local hc = w.Client(HC, HEARTH, 3)
		local hc2 = w.Client(HC2, HEARTH, 3)
		local late = w.Client(LATE, GUILD, 3)
		local member = w.Client(MEMBER, GUILD, 3)
		late.online, member.online = false, false
		w.Census(GUILD, "Bram Hollow", 120)
		-- The first verifier sees the guild at T0, the second two hours later.
		w.As(hc, hc.Verify.Observe)
		w.now = T0 + 2 * H
		hc.online = false
		w.As(hc2, hc2.Verify.Observe)
		eq(hc2.rdb.verify.start[ns.Fold(GUILD)].at, T0 + 2 * H, "each verifier's client records its own first sight")
		-- The later start first, then the earlier: the earlier wins.
		late.online, hc.online = true, true
		w.As(hc2, hc2.Verify.SendSnapshot)
		eq(late.rdb.verify.start[ns.Fold(GUILD)].at, T0 + 2 * H)
		w.As(hc, hc.Verify.SendSnapshot)
		eq(late.rdb.verify.start[ns.Fold(GUILD)].at, T0, "the earliest wins")
		eq(hc2.rdb.verify.start[ns.Fold(GUILD)].at, T0, "on the other verifier's client too")
		w.As(hc2, hc2.Verify.SendSnapshot)
		eq(late.rdb.verify.start[ns.Fold(GUILD)].at, T0, "a later one heard again changes nothing")
		local _, info = w.Status(late, GUILD)
		eq(info.since, T0); eq(info.shared, true)
		-- A reinstall, 40 hours in: the saved data gone, the guild seen again.
		w.now = T0 + 40 * H
		member.online = true
		member.rdb = { guilds = { [GUILD] = { leader = "Bram Hollow", realm = "Realm", total = 120, t = w.now } } }
		w.As(member, member.Verify.Observe)
		_, info = w.Status(member, GUILD)
		eq(info.since, T0 + 40 * H, "its own first sighting, until a verifier's start reaches it"); eq(info.shared, false)
		-- Its ask (it holds less): a verifier's client answers after a few seconds.
		w.As(member, member.Verify.Ask)
		local ask = w.sent[#w.sent].msg
		local digest = ask:match("^GV~1~Q~0~0~0~(%x+)$")
		assert(digest and #digest == 64, ask) -- content digest supplements the legacy counts
		w.now = w.now + 9
		w.Run()
		_, info = w.Status(member, GUILD)
		eq(info.since, T0, "the guild's own clock again"); eq(info.shared, true)
		eq(info.left, 8 * H - 9)
		w.now = T0 + 48 * H + 1
		eq(w.Status(member, GUILD), "overdue", "48 hours from the guild's start, not from the reinstall")
	end)
end)

test("verify: a late client gets the approvals from a verifier's client with their original times; a member's client never answers; a revocation stands over an older approval relayed", function()
	World(function(w)
		local hc = w.Client(HC, HEARTH, 3)
		local hc2 = w.Client(HC2, HEARTH, 3)
		local member = w.Client(MEMBER, OTHER, 3)
		local late = w.Client(LATE, GUILD, 3)
		late.online = false
		w.Census(GUILD, "Bram Hollow", 120)
		w.As(hc, hc.Verify.Observe)
		w.As(hc2, hc2.Verify.Observe)
		w.now = T0 + H
		w.As(hc, hc.Verify.Approve, GUILD)
		eq(w.Status(hc2, GUILD), "verified")
		-- Five hours later the late client logs in and asks.
		w.now = T0 + 5 * H
		late.online, hc2.online = true, false
		local before = #w.sent
		w.As(late, late.Verify.Ask)
		w.now = w.now + 9
		w.Run()
		local relays = 0
		for i = before + 1, #w.sent do
			if w.sent[i].msg:find("^GV~1~S~") then
				relays = relays + 1
				eq(w.sent[i].from, HC, "a verifier's client answers, never a member's")
			end
		end
		eq(relays, 1, "one answer")
		local status, info = w.Status(late, GUILD)
		eq(status, "verified")
		eq(info.entry.at, T0 + H, "the original approval's time"); eq(info.entry.by, HC)
		eq(info.entry.heard, T0 + 5 * H + 9, "heard now")
		-- A client that holds as much asks (past the answers' gap): nobody answers.
		w.now = w.now + 600
		before = #w.sent
		w.As(member, member.Verify.Ask)
		w.As(late, late.Verify.Ask)
		w.now = w.now + 600
		w.Run()
		for i = before + 1, #w.sent do assert(not w.sent[i].msg:find("^GV~1~S~"), "no answer to a client that holds as much") end
		-- Revoked while the second verifier is away; his old approval relayed after it changes nothing.
		w.now = T0 + 6 * H
		w.As(hc, hc.Verify.Revoke, GUILD)
		eq(w.Status(late, GUILD), "pending")
		hc2.online = true
		w.As(hc2, hc2.Verify.SendSnapshot)
		eq(w.Status(late, GUILD), "pending", "an older approval never brings it back")
		eq(w.Status(hc2, GUILD), "verified", "(the absent verifier's client still held it)")
		w.As(hc, hc.Verify.SendSnapshot)
		eq(w.Status(hc2, GUILD), "pending", "until it hears the revocation")
		-- A word on the same second: a revocation stands over an approval.
		local key = ns.Fold(GUILD)
		local at = late.rdb.verify.list[key].at
		w.Deliver(hc, "CHANNEL", ("GV~1~A~%d~%s~%s"):format(at, GUILD, GM))
		eq(w.Status(late, GUILD), "pending")
	end)
end)

---------------------------------------------------------------------------
-- The notices
---------------------------------------------------------------------------

test("verify: paused member notices leave overdue state and GM follow-up intact", function()
	World(function(w)
		local gm = w.Client(GM, GUILD, 0)
		local member = w.Client(MEMBER, GUILD, 3)
		w.Census(GUILD, "Bram Hollow", 120)
		w.As(gm, gm.Verify.Observe)
		w.As(member, member.Verify.Observe)
		w.now = T0 + 48 * H + 1
		w.As(member, member.Verify.Login)
		w.now = w.now + member.Verify.NOTICE_AFTER
		eq(w.Status(member, GUILD), "overdue", "the original deadline stays")
		eq(w.As(member, member.Verify.Tick), false, "no automatic warning")
		eq(#member.copies, 0, "no member popup")
		assert(not Find(member.printed, "find another Olympus guild"), "no instruction to leave")
		eq(#w.As(member, member.Verify.Lines), 0, "no member warning banner")
		eq(w.As(member, member.Verify.ShowNotice), false, "no manual warning popup either")
		eq(w.As(member, member.GuildSanctioned, GUILD), true, "members keep access")
		w.As(gm, gm.Verify.Login)
		w.now = w.now + gm.Verify.NOTICE_AFTER
		eq(w.As(gm, gm.Verify.Tick), true, "GM still gets follow-up")
		assert(Find(gm.printed, "GM verification overdue"))
		eq(w.As(gm, gm.MasterHeld, GUILD), true, "GM rules stay intact")
	end)
end)

test("verify: within 48 hours only the guild master sees \"GM verification pending\", once a session; overdue notices stay with the guild master", function()
	World(function(w)
		local gm = w.Client(GM, GUILD, 0)
		local member = w.Client(MEMBER, GUILD, 3)
		w.Census(GUILD, "Bram Hollow", 120)
		for _, c in ipairs({ gm, member }) do w.As(c, c.Verify.Login) end
		eq(w.As(gm, gm.Verify.Tick), false, "not right after login")
		w.now = w.now + gm.Verify.NOTICE_AFTER
		eq(w.As(gm, gm.Verify.Tick), true)
		eq(w.As(member, member.Verify.Tick), false, "a member sees nothing while it is pending")
		eq(#member.copies, 0); eq(#w.As(member, member.Verify.Lines), 0)
		assert(Find(gm.printed, "GM verification pending for <" .. GUILD .. ">"), "the chat line")
		local notice = gm.copies[1]
		eq(notice.title, gm.L.VERIFY_TITLE); eq(notice.opts.auto, true, "opened by itself: no keyboard taken")
		assert(notice.text:find("GM verification pending", 1, true) and notice.text:find("1 d 23 h", 1, true), notice.text)
		assert(notice.text:find(gm.L.VERIFY_CONTACT, 1, true), "whom to contact, from the locale")
		local code = w.As(gm, gm.Verify.Code, GUILD, GM)
		assert(code and notice.text:find(code, 1, true), "the code to paste")
		eq(notice.action.label, gm.L.VERIFY_WHISPER_BTN); eq(notice.opts.second.label, gm.L.VERIFY_ASK_BTN)
		local line = w.As(gm, gm.Verify.Lines)[1]
		assert(line and line.text:find("GM verification pending", 1, true), "the line on top of the Census")
		-- Once a session; reopened by the line or /oly verify.
		w.now = w.now + 60
		eq(w.As(gm, gm.Verify.Tick), false)
		eq(#gm.copies, 1)
		w.As(gm, line.onClick)
		w.As(gm, gm.Verify.Slash, "")
		eq(#gm.copies, 3, "reopened twice")
		eq(gm.copies[3].opts.auto, nil, "a click's: the keyboard may follow")
		-- 48 hours on, a new session each: members stay quiet; the guild master's powers wait.
		w.now = T0 + 48 * H + 1
		for _, c in ipairs({ gm, member }) do w.As(c, c.Verify.Login) end
		w.now = w.now + member.Verify.NOTICE_AFTER
		eq(w.As(member, member.Verify.Tick), false)
		eq(w.As(gm, gm.Verify.Tick), true)
		eq(#member.copies, 0, "member notices are paused after the deadline too")
		assert(not Find(member.printed, "find another Olympus guild"))
		eq(#w.As(member, member.Verify.Lines), 0)
		assert(gm.copies[#gm.copies].text:find(gm.L.VERIFY_NOTICE_HOLD, 1, true), "the guild master learns his powers wait")
		assert(Find(gm.printed, "GM verification overdue for <" .. GUILD .. ">"))
		-- Verified: nobody is told any more.
		local hc = w.Client(HC, HEARTH, 3)
		w.Census(GUILD, "Bram Hollow", 120)
		w.As(hc, hc.Verify.Approve, GUILD)
		eq(#w.As(member, member.Verify.Lines), 0); eq(#w.As(gm, gm.Verify.Lines), 0)
		eq(w.As(gm, gm.Verify.Mine), nil)
	end)
end)

test("verify: the verifiers are told once of each pending guild (and of each new guild master), reminded 12 hours before its deadline, and members never are", function()
	World(function(w)
		local hc = w.Client(HC, HEARTH, 3)
		local member = w.Client(MEMBER, HEARTH, 3)
		w.Census(GUILD, "Bram Hollow", 120)
		w.As(hc, hc.Verify.Login)
		w.As(member, member.Verify.Login)
		w.now = w.now + hc.Verify.NOTICE_AFTER
		w.As(hc, hc.Verify.Tick)
		w.As(member, member.Verify.Tick)
		local new = Find(hc.printed, "GM verification pending for")
		assert(new and new:find("<" .. GUILD .. "> (Bram Hollow)", 1, true), tostring(new))
		eq(#member.printed, 0, "a member hears nothing of it")
		local n = #hc.printed
		w.now = w.now + 60
		w.As(hc, hc.Verify.Tick)
		eq(#hc.printed, n, "once")
		-- Another guild appears: told of it alone.
		w.now = T0 + 2 * H
		w.Census(OTHER, "Corin Ash", 40)
		w.As(hc, hc.Verify.Tick)
		eq(#hc.printed, n + 1)
		assert(hc.printed[n + 1]:find("<" .. OTHER .. ">", 1, true) and not hc.printed[n + 1]:find(GUILD, 1, true), hc.printed[n + 1])
		-- 36 hours in: reminded of the first, once (the second has 14 hours left).
		w.now = T0 + 36 * H + 60
		w.As(hc, hc.Verify.Tick)
		local remind = hc.printed[#hc.printed]
		assert(remind:find("less than 12 h", 1, true) and remind:find(GUILD, 1, true) and not remind:find(OTHER, 1, true), remind)
		n = #hc.printed
		w.As(hc, hc.Verify.Tick)
		eq(#hc.printed, n, "reminded once")
		-- A new guild master: a fresh check, told again.
		w.Census(GUILD, "Edda Vale", 120)
		w.As(hc, hc.Verify.Tick)
		assert(hc.printed[#hc.printed]:find("<" .. GUILD .. "> (Edda Vale)", 1, true), hc.printed[#hc.printed])
		-- Kept across a session: a new login tells nothing again.
		n = #hc.printed
		w.As(hc, hc.Verify.Login)
		w.now = w.now + hc.Verify.NOTICE_AFTER
		w.As(hc, hc.Verify.Tick)
		eq(#hc.printed, n)
	end)
end)

---------------------------------------------------------------------------
-- The hold, the switches, what nobody gets
---------------------------------------------------------------------------

test("verify: past 48 hours an unverified guild master's own powers are held (rank, card, Legates, guild decrees); verification releases them; members keep everything", function()
	World(function(w)
		local gm = w.Client(GM, GUILD, 0)
		local hc = w.Client(HC, HEARTH, 3)
		w.Census(GUILD, "Bram Hollow", 120)
		w.As(gm, gm.Verify.Observe)
		w.As(hc, hc.Verify.Observe)
		w.As(gm, function() assert(loadfile(ADDON_DIR .. "GuildCharter.lua"))("Olympus", gm) end)
		-- The harness's own modules ask the harness's predicate: this guild master's here.
		local saved = { held = ns.MasterHeld, known = ns.Data.KnownRank }
		ns.MasterHeld = function(guild) return gm.MasterHeld(guild) end
		ns.Data.KnownRank = function(sender, guild) if sender == GM and guild == GUILD then return 0, 2 end return nil end
		local ok, err = pcall(function()
			local function Check(held, what)
				w.As(gm, function()
					eq(gm.MasterHeld(GUILD), held, what .. ": held")
					eq((ns.Data.AuthorizedRank(GM, GUILD)), held and ns.CAPTAIN_RANK or 0, what .. ": his rank for every power that asks it")
					eq((gm.GuildCharter.IsMaster()), not held, what .. ": his public card")
					eq((ns.Nominees.IsMaster()), not held, what .. ": his Legates and correspondents")
					eq(select(2, ns.Decree.Scope("ROYAL")), not held and "lord" or nil, what .. ": his guild decree")
				end)
			end
			Check(false, "pending")
			w.now = T0 + 48 * H - 1
			Check(false, "a second before the deadline")
			w.now = T0 + 48 * H + 1
			Check(true, "overdue")
			-- The members keep their own standing: an officer's rank is never touched.
			ns.Data.KnownRank = function(sender, guild) if guild == GUILD then return sender == GM and 0 or 1, 2 end return nil end
			w.As(gm, function() eq((ns.Data.AuthorizedRank(MEMBER, GUILD)), 1, "an officer stays an officer") end)
			-- Verified: released at once.
			w.As(hc, hc.Verify.Approve, GUILD)
			Check(false, "verified")
			-- The hold's switch off: never held.
			w.As(hc, hc.Verify.Revoke, GUILD)
			Check(true, "revoked, overdue")
			gm.VERIFY_HOLD = false
			eq(w.As(gm, gm.MasterHeld, GUILD), false, "the switch off")
		end)
		ns.MasterHeld, ns.Data.KnownRank = saved.held, saved.known
		if not ok then error(err, 0) end
	end)
end)

test("verify: the King's guild needs no verification; the gate switch off changes nothing; Core's stand-ins say yes", function()
	World(function(w)
		local king = w.Client(KING, "Olympus", 0)
		local hc = w.Client(HC, HEARTH, 3)
		local member = w.Client(MEMBER, GUILD, 3)
		w.Census("Olympus", ns.KingCharacter(), 900)
		w.Census(GUILD, "Bram Hollow", 120)
		for _, c in ipairs({ king, hc, member }) do w.As(c, c.Verify.Login) end
		w.now = T0 + 60 * H
		eq(w.Status(member, "Olympus"), "exempt")
		eq(w.As(king, king.Verify.Mine), nil, "the King is told nothing")
		eq(w.As(king, king.Verify.Tick), false)
		eq(#king.copies, 0)
		eq(w.As(member, member.MasterHeld, "Olympus"), false)
		for _, r in ipairs((w.As(hc, hc.Verify.Pending))) do assert(r.guild ~= "Olympus", "not on the verifiers' list") end
		-- The gate: off as it ships, every guild sanctioned; on, the overdue one is not.
		eq(w.Status(member, GUILD), "overdue")
		eq(member.VERIFY_GATE, false, "Core.lua ships it off")
		eq(w.As(member, member.GuildSanctioned, GUILD), true, "off: nothing gated")
		member.VERIFY_GATE = true
		eq(w.As(member, member.GuildSanctioned, GUILD), false, "on: the overdue guild is not sanctioned")
		eq(w.As(member, member.GuildSanctioned, "Olympus"), true)
		member.VERIFY_GATE = nil
		eq(w.Status(member, GUILD), "overdue", "the switch changes no status")
		-- Core.lua's stand-ins (Verify.lua not loaded: a client updated without a restart).
		eq(ns.VERIFY_GATE, false); eq(ns.VERIFY_HOLD, true)
		eq(ns.GuildSanctioned(GUILD), true); eq(ns.MasterHeld(GUILD), false)
	end)
end)

test("verify: being pending or verified grants no council status, role or verifier's power", function()
	World(function(w)
		local gm = w.Client(GM, GUILD, 0)
		local hc = w.Client(HC, HEARTH, 3)
		w.Census(GUILD, "Bram Hollow", 120)
		local function Nothing(what)
			w.As(gm, function()
				eq(gm.Verify.Trusted(GM), false, what .. ": no verifier")
				eq(ns.IsHighCouncillor(GM), false, what .. ": no councillor")
				eq(gm.Verify.CouncilShown(), false, what .. ": no verifiers' page")
				eq(#gm.Verify.CouncilLines(), 0)
				local ok, why = gm.Verify.Approve(GUILD, GM)
				eq(ok, false, what .. ": he can't approve himself"); eq(why, "trust")
			end)
		end
		Nothing("pending")
		w.As(hc, hc.Verify.Approve, GUILD)
		eq(w.Status(gm, GUILD), "verified")
		Nothing("verified")
	end)
end)

---------------------------------------------------------------------------
-- The pages and the commands
---------------------------------------------------------------------------

test("verify: the verifiers' page lists pending and overdue guilds with guild master, members and time; a click approves or whispers; Copy opens a pop-up; a verified one revokes", function()
	World(function(w)
		local member = w.Client(MEMBER, GUILD, 3)
		local hc = w.Client(HC, "Olympus", 3) -- (a councillor in the King's guild: his own guild asks nothing of him)
		w.Census(GUILD, "Bram Hollow", 120)
		w.As(hc, hc.Verify.Observe)
		w.As(member, member.Verify.Observe)
		w.now = T0 + 40 * H
		w.Census(OTHER, "Corin Ash", 40)
		w.As(hc, hc.Verify.Observe)
		w.now = T0 + 49 * H
		eq(#w.As(member, member.Verify.CouncilLines), 0, "a member sees no page")
		local lines = w.As(hc, hc.Verify.CouncilLines)
		eq(lines[1].text, hc.L.VERIFY_COUNCIL_TITLE)
		local first, second
		for _, l in ipairs(lines) do
			if l.text and l.text:find("<" .. GUILD .. ">  Bram Hollow", 1, true) then first = first or l end
			if l.text and l.text:find("<" .. OTHER .. ">  Corin Ash", 1, true) then second = second or l end
		end
		assert(first and second, "both guilds")
		assert(first.right:find("overdue", 1, true), first.right)
		assert(second.right:find("pending, 1 d 15 h left", 1, true), second.right)
		local order = {}
		for i, l in ipairs(lines) do if l == first or l == second then order[#order + 1] = i end end
		assert(order[1] < order[2] and lines[order[1]] == first, "the overdue first")
		local tip = {}
		first.tooltip({ AddLine = function(_, s) tip[#tip + 1] = s end })
		assert(Find(tip, "Members: 120") and Find(tip, "First seen here: 2 d 1 h ago") and Find(tip, "Code: "), table.concat(tip, " / "))
		-- A click: the question, with approve and whisper.
		w.As(hc, first.onClick)
		local d = hc.dialogs[#hc.dialogs]
		eq(d.which, "OLYMPUS_VERIFY_GUILD"); eq(d.data.guild, GUILD); eq(d.data.gm, GM)
		local def = StaticPopupDialogs.OLYMPUS_VERIFY_GUILD
		eq(def.button1, hc.L.VERIFY_APPROVE_BTN); eq(def.button3, hc.L.VERIFY_WHISPER_GM_BTN)
		w.As(hc, hc.Verify.Nudge, d.data)
		eq(hc.whispers[1].to, "Bram Hollow"); assert(hc.whispers[1].text:find("/oly verify", 1, true), "install it and verify")
		w.As(hc, hc.Verify.ApproveClick, d.data)
		eq(w.Status(member, GUILD), "verified")
		-- The verified section: a click asks to revoke.
		lines = w.As(hc, hc.Verify.CouncilLines)
		local done
		for _, l in ipairs(lines) do if l.text and l.text:find(hc.Verify.MARK_OK .. "<" .. GUILD .. ">", 1, true) then done = l end end
		assert(done and done.right:find("by Vera Stone", 1, true), "verified, and by whom")
		w.As(hc, done.onClick)
		eq(hc.dialogs[#hc.dialogs].which, "OLYMPUS_VERIFY_REVOKE")
		w.As(hc, hc.Verify.RevokeInput, hc.dialogs[#hc.dialogs].data.guild)
		eq(w.Status(member, GUILD), "overdue")
		-- Copy: a pop-up the list can be copied from.
		w.As(hc, lines[3].onClick)
		local copy = hc.copies[#hc.copies]
		eq(copy.opts.key, "verify-list")
		assert(copy.text:find("<" .. GUILD .. ">  guild master: Bram Hollow  members: 120", 1, true), copy.text)
		assert(copy.text:find("<" .. OTHER .. ">", 1, true) and copy.text:find("code ", 1, true), copy.text)
		-- /oly verify alone opens The Watch on its Guilds for a verifier.
		w.As(hc, hc.Verify.Slash, "")
		eq(hc.tab, "watch")
		-- The Census's marks: verified for everyone, overdue for the verifiers alone.
		w.As(hc, hc.Verify.Approve, OTHER)
		eq(w.As(member, member.Verify.Mark, OTHER), member.Verify.MARK_OK)
		eq(w.As(member, member.Verify.Mark, GUILD), "", "a member sees no overdue mark")
		eq(w.As(hc, hc.Verify.Mark, GUILD), hc.Verify.MARK_LATE)
	end)
end)

test("verify: resend button preserves the original guild clock and its cooldown across reloads", function()
	World(function(w)
		local gm, hc = w.Client(GM, GUILD, 0), w.Client(HC, HEARTH, 3)
		w.Census(GUILD, "Bram Hollow", 120)
		w.As(hc, hc.Verify.Observe)
		w.now = T0 + H
		w.As(gm, gm.Verify.Observe)
		w.As(hc, hc.Verify.SendSnapshot)
		local key = gm.Fold(GUILD)
		eq(w.As(gm, gm.Verify.Start, GUILD), T0, "earliest verifier start")
		eq(gm.rdb.verify.seen[key].at, T0 + H, "different local sighting")
		w.now = T0 + 2 * H
		assert(w.As(gm, gm.Verify.ShowNotice))
		local button = gm.copies[#gm.copies].opts.second
		eq(button.label, gm.L.VERIFY_ASK_BTN)
		w.As(gm, button.fn); eq(gm.askCalls, 1)
		w.As(gm, button.fn); eq(gm.askCalls, 1, "a repeated click does not submit another request")
		eq(w.As(gm, gm.Verify.Start, GUILD), T0)
		eq(gm.rdb.verify.seen[key].at, T0 + H)
		local since = gm.rdb.verify.start[key].at
		local attempt = gm.rdb.verify.requests[key].at
		-- Reload the actual module over the same saved data; no session-only timer may reset it.
		assert(loadfile(ADDON_DIR .. "Verify.lua"))("Olympus", gm)
		gm.Verify.Clock = function() return w.now end
		w.As(gm, gm.Verify.Login)
		local ok, why = w.As(gm, gm.Verify.AskCouncil, GUILD)
		eq(ok, false); eq(why, "cooldown"); eq(gm.askCalls, 1)
		eq(gm.rdb.verify.start[key].at, since); eq(gm.rdb.verify.requests[key].at, attempt)
		w.now = w.now + gm.Verify.REQUEST_GAP + 1
		eq(w.As(gm, gm.Verify.AskCouncil, GUILD), true); eq(gm.askCalls, 2)
		eq(gm.rdb.verify.start[key].at, since); eq(gm.rdb.verify.seen[key].at, T0 + H)
		local status, info = w.Status(gm, GUILD)
		eq(status, "pending"); eq(info.left, T0 + gm.Verify.GRACE - w.now, "resending never renews grace")
	end)
end)

test("verify: resend failure, stale buttons and non-masters never change the guild deadline or claim a queued request", function()
	World(function(w)
		local gm, hc = w.Client(GM, GUILD, 0), w.Client(HC, HEARTH, 3)
		w.Census(GUILD, "Bram Hollow", 120)
		w.As(gm, gm.Verify.Observe); w.As(hc, hc.Verify.Observe)
		w.As(hc, hc.Verify.SendSnapshot)
		w.now = T0 + gm.Verify.GRACE + H
		local key = gm.Fold(GUILD)
		gm.helpQueued = false
		eq(w.As(gm, gm.Verify.AskCouncil, GUILD), false, "the actual request helper refused the queue")
		eq(gm.rdb.verify.start[key].at, T0); eq(gm.rdb.verify.seen[key].at, T0)
		eq(gm.rdb.verify.requests[key], nil, "a refused send consumes no successful-request cooldown")
		gm.helpQueued = true
		eq(w.As(gm, gm.Verify.AskCouncil, GUILD), true)
		eq(w.Status(gm, GUILD), "overdue", "resend is not approval and never restores grace")
		local calls = gm.askCalls
		gm.rank = 3
		eq(w.As(gm, gm.Verify.AskCouncil, GUILD), false, "only the native guild master can resend")
		gm.rank, gm.guild = 0, OTHER
		eq(w.As(gm, gm.Verify.AskCouncil, GUILD), false, "a button retained after changing guild cannot request for the old one")
		eq(gm.askCalls, calls); eq(gm.rdb.verify.start[key].at, T0)
		gm.guild = GUILD
		eq(w.As(hc, hc.Verify.Approve, GUILD, GM), true)
		eq(w.As(gm, gm.Verify.AskCouncil, GUILD), false, "approval makes an already-open resend button inert")
		eq(gm.askCalls, calls); eq(gm.rdb.verify.start[key].at, T0)
	end)
end)

test("verify: resend cooldown records are bounded, expire and never get younger when read", function()
	World(function(w)
		local gm = w.Client(GM, GUILD, 0)
		w.As(gm, gm.Verify.Observe)
		local requests, V = gm.rdb.verify.requests, gm.Verify
		w.now = T0 + V.MAX_STARTS + 2
		for i = 1, V.MAX_STARTS + 1 do requests["guild" .. i] = { at = T0 + i } end
		requests.expired = { at = w.now - V.SEEN_KEEP - 1 }
		requests.future = { at = w.now + V.AHEAD + 1 }
		requests.malformed = "invalid"
		local original = requests["guild" .. (V.MAX_STARTS + 1)].at
		w.As(gm, V.Prune)
		local n = 0
		for _ in pairs(requests) do n = n + 1 end
		eq(n, V.MAX_STARTS)
		eq(requests.guild1, nil); eq(requests.expired, nil); eq(requests.future, nil); eq(requests.malformed, nil)
		local key = "guild" .. (V.MAX_STARTS + 1)
		eq(w.As(gm, V.RequestWait, key), V.REQUEST_GAP - 1)
		w.now = w.now + 10
		eq(w.As(gm, V.RequestWait, key), V.REQUEST_GAP - 11)
		eq(requests[key].at, original, "reading does not renew cooldown")
	end)
end)

test("verify: the guild master's buttons whisper a verifier online with his code, or say where to send it; the code and a typed name approve", function()
	World(function(w)
		local gm = w.Client(GM, GUILD, 0)
		local hc = w.Client(HC, HEARTH, 3)
		w.Census(GUILD, "Bram Hollow", 120)
		local code = w.As(gm, gm.Verify.Code, GUILD, GM)
		assert(code:match("^%x%x%x%x%x%x$"), code)
		eq(w.As(gm, gm.Verify.WhisperVerifier, GUILD), false)
		assert(Find(gm.printed, "No verifier is online now"), "nobody online: where to send it")
		eq(#gm.whispers, 0)
		w.available = { HC }
		eq(w.As(gm, gm.Verify.WhisperVerifier, GUILD), true)
		eq(gm.whispers[1].to, "Vera Stone"); assert(gm.whispers[1].text:find(code, 1, true), gm.whispers[1].text)
		w.As(gm, gm.Verify.AskCouncil, GUILD)
		assert(gm.asked:find(GUILD, 1, true) and gm.asked:find(code, 1, true), gm.asked)
		-- The verifier: the code finds the guild and its guild master.
		local guild, master = w.As(hc, hc.Verify.FromCode, code:lower())
		eq(guild, GUILD); eq(master, GM)
		w.As(hc, hc.Verify.Slash, "approve " .. code)
		eq(w.Status(gm, GUILD), "verified")
		-- A guild's name with spaces and a guild master's name after it.
		w.now = w.now + 60
		w.As(hc, hc.Verify.Slash, "approve olympus vanguard Corin Ash")
		local _, info = w.Status(hc, GUILD)
		eq(info.entry.gm, GM2, "the name typed")
		assert(Find(hc.printed, "the census names Bram Hollow"), "warned: the census names another")
		w.As(hc, hc.Verify.Slash, "approve Olympus Nowhere")
		assert(Find(hc.printed, hc.L.VERIFY_BAD_GUILD), "an unknown guild")
		w.As(hc, hc.Verify.Slash, "revoke " .. GUILD)
		eq(w.Status(gm, GUILD), "pending")
	end)
end)

test("verify: The Watch shows the verifiers its Guilds, and nobody else", function()
	local savedGuild, savedInGuild = GetGuildInfo, IsInGuild
	local dialogs = {}
	for key, value in pairs(StaticPopupDialogs) do dialogs[key] = value end
	local w = { shown = true }
	local c = setmetatable({ L = setmetatable({}, { __index = ns.L }), me = "Vera Stone-Realm", group = "RealmGroup", faction = "Alliance",
		db = {}, rdb = {}, CAPTAIN_RANK = 1, UI = {}, PlayerMenu = { Add = function() end },
		On = function() end, Fire = function() end, RegisterEvent = function() end,
		After = function() end, Every = function() end, Print = function() end,
		Workshop = { IsAuthor = function() return false end, Preview = function() return false end, IsAuthorName = function() return false end },
		Authority = { Enforced = function() return false end }, Alts = { Linked = function() return {} end },
		Filter = { SharedOn = function() return true end }, KingArrow = { ControlLines = function() return {} end },
		TabardsV2 = { SurfaceVisible = function() return false end, Collector = function() return nil end },
		Verify = { CouncilShown = function() return w.shown end, Count = function() return 2 end,
			CouncilLines = function() return { { id = "verify-council", text = "the guilds" } } end },
	}, { __index = ns })
	c.Now = function() return T0 end
	c.Data = { ServerTime = c.Now }
	c.IsMember = function() return true end
	c.IsHighCouncillor = function(name) return name == c.me end
	c.IsKingCharacter = function() return false end
	c.Moderation = { IsKing = c.IsKingCharacter, SelfOff = function() return false end, Hides = function() return false end,
		Hidden = function() return false end, CharName = function(n) return n end, Lines = function() return {} end }
	c.Roster = { complete = true, byName = {}, online = {}, guild = HEARTH, group = c.group, faction = c.faction, snapshotAt = T0, generation = 1,
		RankOf = function() return nil end, MyRank = function() return 3 end }
	c.Comm = { Handle = function() end, Send = function() end, Whisper = function() end }
	c.King = { IsKing = function() return false end, Preview = function() return false end, Register = function() end }
	GetGuildInfo = function() return HEARTH, "Member", 3 end
	IsInGuild = function() return true end
	local ok, err = pcall(function()
		assert(loadfile(ADDON_DIR .. "Locales/VerifyText.lua"))("Olympus", c)
		for _, file in ipairs({ "ViewAs", "Court", "Watch", "Judgment", "WatchChat" }) do
			assert(loadfile(ADDON_DIR .. file .. ".lua"))("Olympus", c)
		end
		local W = c.Watch
		local function Nav()
			local out = {}
			for _, item in ipairs(W.Build()[1].nav or {}) do out[#out + 1] = item.text end
			return table.concat(out, "|")
		end
		eq(W.TabVisible(), true)
		assert(Nav():find(c.L.VERIFY_NAV:format(2), 1, true), Nav())
		W.Show("verify")
		eq(W.PageId(), "verify"); eq(W.ViewKey(), "judgments", "no desk buttons")
		local lines, _, detail = W.Build()
		eq(lines[2].text, "the guilds"); eq(detail, c.L.VERIFY_COUNCIL_DETAIL)
		w.shown = false
		assert(not Nav():find(c.L.VERIFY_NAV:format(2), 1, true), "nobody else")
		eq(W.PageId() ~= "verify", true, "the section falls back")
	end)
	GetGuildInfo, IsInGuild = savedGuild, savedInGuild
	for key in pairs(StaticPopupDialogs) do StaticPopupDialogs[key] = dialogs[key] end
	if not ok then error(err, 0) end
end)

---------------------------------------------------------------------------
-- Structure and words
---------------------------------------------------------------------------

test("verify: GV in Comm.lua's list; the TOC loads its words with the locales and Verify.lua after Cover.lua; Core's stand-in, login list, command and help name it", function()
	local function Read(path)
		local f = assert(io.open(ROOT .. path, "rb"))
		local s = f:read("*a")
		f:close()
		return s
	end
	local at, n = {}, 0
	for line in Read("Olympus/Olympus.toc"):gmatch("[^\n]+") do n = n + 1; at[line:gsub("%s+$", "")] = n end
	assert(at["Locales\\VerifyText.lua"] and at["Locales\\VerifyText.lua"] < at["Core.lua"], "with the locales")
	for _, f in ipairs({ "Comm.lua", "Data.lua", "Workshop.lua", "Watch.lua", "Cover.lua" }) do assert(at[f] < at["Verify.lua"], f .. " first") end
	assert(Read("Olympus/Comm.lua"):find("--   Verify GV (guild verification", 1, true), "Comm.lua's list")
	local core = Read("Olympus/Core.lua")
	assert(core:find('StandIn("Verify", { "Slash" })', 1, true), "the stand-in")
	local loginList = core:match('for _, key in ipairs%(({ "Who", [^}]*})%) do')
	assert(loginList and loginList:find('"Verify"', 1, true), "PLAYER_LOGIN checks it")
	assert(core:find('cmd == "verify" or cmd == "verificar"', 1, true), "/oly verify")
	assert(core:find('rawget(L, "HELP_VERIFY")', 1, true), "the help line")
	assert(Read("Olympus/Views.lua"):find("Views.DisputeMark(g) .. VerifyMark(e.name) .. Plain(e.name)", 1, true), "the Census's mark")
	-- No real player's name in the module or its words (the verifier to whisper is a locale line, empty).
	eq(rawget(ns.L, "VERIFY_WHISPER_TO") == nil or ns.L.VERIFY_WHISPER_TO == "", true)
	assert(Read("Olympus/Locales/VerifyText.lua"):find('L.VERIFY_WHISPER_TO = ""', 1, true))
end)

test("verify: Brazilian Portuguese has every line, with the same codes as the English", function()
	local function Load(locale)
		local saved = GetLocale
		GetLocale = function() return locale end
		local L = {}
		local ok, err = pcall(function() assert(loadfile(ADDON_DIR .. "Locales/VerifyText.lua"))("Olympus", { L = L }) end)
		GetLocale = saved
		if not ok then error(err, 0) end
		return L
	end
	local en, pt = Load("enUS"), Load("ptBR")
	local same = { VERIFY_WHISPER_TO = true, VERIFY_HOURS = true, VERIFY_DAYS = true }
	local n = 0
	for k, v in pairs(en) do
		n = n + 1
		if not same[k] then assert(pt[k] ~= v, k .. " translated") end
		eq(ns.LocaleCodes(pt[k]), ns.LocaleCodes(v), k .. "'s codes")
	end
	assert(n >= 60, "the lines")
end)
