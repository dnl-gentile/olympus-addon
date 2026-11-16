local ns, test, eq, FreshComm, FIXTURES = ...
local R, H = ns.Recruit, ns.Recruit.Handoff
local home, other = "CAMWOWUS2Realm1PvE", "CAMWOWUS2Realm2PvE"
local me, mate, officer = "Local Recruiter-" .. home, "Guild Recruiter-" .. home, "Sister Recruiter-" .. other
local own, sister = "Olympus Prime", "Olympus II"
local applicant = "New Recruit-" .. home

local function WithHandoff(fn)
	local saved = {
		guild = GetGuildInfo, invite = CanGuildInvite, secret = ns.ChatLocked, dialog = ns.Dialog,
		member = ns.IsMember, now = ns.Now, me = ns.me, faction = ns.faction, group = ns.group,
		realm = ns.realm, splitNames = ns.splitNames, whisper = ns.Comm.Whisper,
		fresh = ns.Roster.Fresh, rank = ns.Roster.RankOf, online = ns.Roster.online,
		canRank = ns.Data.CanRank, authorized = ns.Data.AuthorizedRank,
		every = ns.Every, quiet = ns.QuietPresence, after = ns.After, rdb = ns.rdb, print = ns.Print,
		candidates = R.Candidates, unitExists = UnitExists,
	}
	-- (The scan looks at the target and the nameplates: in these tests nobody stands nearby.)
	UnitExists = function() return false end
	ns.rdb = {}
	R.ResetForTests()
	local scene = { now = 5000, fresh = true, permission = true, support = 2, packets = {}, later = {}, timers = {}, printed = {} }
	ns.Print = function(msg) scene.printed[#scene.printed + 1] = tostring(msg) end
	GetGuildInfo = function() return own end
	CanGuildInvite = function() return scene.permission end
	ns.IsMember = function() return true end
	ns.ChatLocked = function() return scene.locked == true end
	ns.After = function(_, _, fn) scene.later[#scene.later + 1] = fn end
	ns.QuietPresence = function() return scene.quiet == true end
	ns.Every = function(_, name, callback)
		scene.timers[name] = callback
		-- scene.tick stays the automatic offers' step; the unguilded scan keeps its own timer.
		if name ~= "recruit candidates" then scene.tick = callback end
		return { Cancel = function() scene.cancelled = true end }
	end
	ns.Now = function() return scene.now end
	ns.me, ns.faction, ns.group, ns.realm, ns.splitNames = me, "Alliance", "ForeverPvE", home, true
	ns.Dialog = nil
	ns.Roster.online = { { name = mate } }
	ns.Roster.Fresh = function() return scene.fresh and ns.Roster or nil end
	ns.Roster.RankOf = function(name)
		if name == me then return 0 end
		if name == mate then return 1 end
	end
	ns.Data.CanRank = function(guild) return guild == sister end
	ns.Data.AuthorizedRank = function(name, guild)
		if name == officer and guild == sister then return 0, "census", scene.support end
	end
	ns.Comm.Whisper = function(peer, word, _, _, logged, done, options)
		eq(logged, false, "handoff packets do not go to the chat log")
		assert(options.guard(), "queued handoff is permitted at the point of enqueue")
		scene.packets[#scene.packets + 1] = { peer = peer, word = word, guard = options.guard, done = done }
		return true
	end
	R.ToggleWhisperRecruiting()
	ns.Comm.ResetAdmission()
	local ok, err = pcall(fn, scene)
	R.ResetForTests()
	ns.Comm.ResetAdmission()
	GetGuildInfo, CanGuildInvite, ns.ChatLocked, ns.Dialog = saved.guild, saved.invite, saved.secret, saved.dialog
	ns.IsMember, ns.Now, ns.me, ns.faction, ns.group = saved.member, saved.now, saved.me, saved.faction, saved.group
	ns.realm, ns.splitNames, ns.Comm.Whisper = saved.realm, saved.splitNames, saved.whisper
	ns.Roster.Fresh, ns.Roster.RankOf, ns.Roster.online = saved.fresh, saved.rank, saved.online
	ns.Data.CanRank, ns.Data.AuthorizedRank = saved.canRank, saved.authorized
	ns.Every, ns.QuietPresence, ns.After, ns.rdb, ns.Print = saved.every, saved.quiet, saved.after, saved.rdb, saved.print
	R.Candidates, UnitExists = saved.candidates, saved.unitExists
	if not ok then error(err, 0) end
end

local function Packet(scene, verb, from, to, name, id)
	return ("J4~%s~%s~%d~ForeverPvE~Alliance~%s~%s~%s"):format(verb, id or "1234-ab-1", scene.now + 90, from, to, name or "")
end

-- Olympus's dialogs as the officer sees them: shown, found, closed. Each keeps its definition.
local function Dialogs()
	local shown, D = {}, {}
	function D.Find(which, data)
		for i = #shown, 1, -1 do
			local f = shown[i]
			if f.which == which and f.open and (data == nil or f.data == data) then return f end
		end
	end
	function D.Show(which, a, _, data)
		local f = { which = which, text = a, data = data, open = true, def = StaticPopupDialogs[which] }
		f.Hide = function() f.open = false end
		f.IsShown = function() return f.open end
		shown[#shown + 1] = f
		return f
	end
	function D.Hide(which) local f = D.Find(which); if f then f.open = false end end
	function D.CloseOnEscape() end
	return D
end
local DRAFT, CLAIM = "OLYMPUS_RECRUIT_INVITE_DRAFT", "OLYMPUS_RECRUIT_HANDOFF_CLAIM"

local function Find(rows, text)
	for _, row in ipairs(rows) do if row.text and row.text:find(text, 1, true) then return row end end
end
local function Id(rows, id)
	for _, row in ipairs(rows) do if row.id == id then return row end end
end

-- Referral-specific test retired with invite handoffs.


-- Referral-specific test retired with invite handoffs.


-- Referral-specific test retired with invite handoffs.


-- Referral-specific test retired with invite handoffs.


-- Removed referral behavior: replaced by the permanent off regression below.


-- Referral-specific test retired with invite handoffs.


-- Referral-specific test retired with invite handoffs.


-- 1.5.8 (the author, 11-12: "quando um invite aparecer, não tem que clicar em prepare invite").
-- Referral-specific test retired with invite handoffs.


-- 1.5.9 (the author, 11-12: the member who passed a JOIN or a scanned player on gets a share of that
-- recruit's points once he joins, "tipo os pontos da rede"): the name that arrives keeps who passed it,
-- on the request and for the recruiting ranking (RecruitRanking.HandedIn, its own file's tests).
-- Referral-specific test retired with invite handoffs.


-- Review of 1.5.9: the inviter's own report alone named who passed him a player (an alt or a friend took
-- 25% of his recruits). The member who passed the name says so himself, once its member took it ("A"):
-- RecruitRanking.HandedOut, whose word the keepers match with the inviter's (its own file's tests).
-- Referral-specific test retired with invite handoffs.


-- 1.5.8 (the author, 11-12: "ele mostrar tantas pessoas na fila depois dessa. E aí você clica no
-- botão e fala tipo, é repassar os negócios pra outros offices").
-- Removed referral behavior: replaced by the permanent off regression below.


-- Removed referral behavior: replaced by the permanent off regression below.


-- 1.5.8 (the author's, 11-12: "o repasse tem que ir para qualquer pessoa que esteja com a feature
-- ativa. Não precisa ser só para officer, porque, por exemplo, eu não sou officer das minhas guildas
-- e eu consigo convidar"): any member of the guild whose client recruits, accepts handoffs and can
-- invite gives and takes them, whatever his rank; the game's invite permission is the only gate.
-- Referral-specific test retired with invite handoffs.


-- 1.5.8 (the author's: "se ela tentar ativar e ela não puder convidar pessoas, vai avisar, tipo,
-- você não pode convidar mesmo para sua guilda, fale com o seu GM").
test("recruit (1.5.8): turning recruiting on without the game's invite permission says why and stays off", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		eq(R.ToggleWhisperRecruiting(), false, "turned off first")
		scene.permission = false
		-- (Changed on purpose, 1.5.9, the author's ask for a page "muito claro": the Recruiting section's
		-- heading comes first now; the switch is found by its id.)
		local toggle = assert(Id(R.WhisperLines(), "recruit-whisper-toggle"), "Church > Invites shows the switch to every member")
		eq(toggle.onClick(), false)
		eq(R.IsWhisperRecruiting(), false, "recruiting stays off")
		eq(scene.printed[#scene.printed], ns.L.RECRUIT_NO_INVITE_RIGHT)
		local notice = assert(D.Find("OLYMPUS_RECRUIT_NO_INVITE"), "the reason opens in a window too")
		eq(notice.text, ns.L.RECRUIT_NO_INVITE_RIGHT)
		notice:Hide()
		local before = #scene.printed
		eq(R.EnableWhisperRecruiting(), false, "the Census button refuses too")
		eq(#scene.printed, before + 1)
		eq(scene.printed[#scene.printed], ns.L.RECRUIT_NO_INVITE_RIGHT)
		scene.permission = true
		D.Find("OLYMPUS_RECRUIT_NO_INVITE"):Hide()
		before = #scene.printed
		eq(R.ToggleWhisperRecruiting(), true, "a member who can invite turns it on as before")
		eq(D.Find("OLYMPUS_RECRUIT_NO_INVITE"), nil)
		for i = before + 1, #scene.printed do
			assert(scene.printed[i] ~= ns.L.RECRUIT_NO_INVITE_RIGHT, "no warning for a member who can invite")
		end
	end)
end)

-- RecruitCandidates.lua, which the offline harness leaves out, loaded once for the scan's tests and
-- present only inside them (WithHandoff puts the harness's own value back).
local candidates
local function UseCandidates()
	if not candidates then
		local dir = debug.getinfo(1, "S").source:match("^@(.-)tests/[^/]*$") or ""
		local saved = R.Candidates
		assert(loadfile(dir .. "Olympus/RecruitCandidates.lua"))("Olympus", ns)
		candidates, R.Candidates = R.Candidates, saved
	end
	R.Candidates = candidates
end

-- Starts the unguilded scan and lists one player a /who found with no guild.
local function ScanOne(scene, name)
	UseCandidates()
	assert(Find(R.WhisperLines(), ns.L.RECRUIT_CANDIDATES_OFF)).onClick()
	assert(R.Candidates.Enabled(), "the scan is on")
	R.Candidates.ObserveWho(name, "", "Human")
	return assert(scene.timers["recruit candidates"])
end

-- 1.5.8 (the author's: "parada de unguilded players se vc n puder chamar na hora quem vc viu pode
-- repassar pra outro player convidar tbm").
-- Removed referral behavior: replaced by the permanent off regression below.


-- Review of 1.5.8 (P3): a sighting offered to a member, then the same player's JOIN here: the
-- member's later claim must not get his name too, or both invite him.
-- Removed referral behavior: replaced by the permanent off regression below.


-- 1.5.8 (the author's message to the streamer: "it lines them up for him up to his 10 a minute and
-- passes the rest to other members accepting requests").
-- Referral-specific test retired with invite handoffs.


-- Review of 1.5.8 (P2): what the limit sent on, when no member claimed it, never came back to his
-- own popups once the minute was over ("lines them up for him up to his 10 a minute"). A player he
-- passed himself stays passed.
-- Removed referral behavior: replaced by the permanent off regression below.


-- Review of 1.5.8 (P2): with the offers off again, what the limit sent on comes back at once (its
-- popup says the limit and offers Pass), unless a member's claim is under way.
-- Referral-specific test retired with invite handoffs.


-- 1.5.8: with every member a possible taker, a guild of hundreds online must not wait twenty
-- seconds on each member without Olympus: the probe goes to one this client heard run it.
-- Referral-specific test retired with invite handoffs.


-- Review of 1.5.8 (P3): the probes rotated only over the members whose hello this client heard, so
-- one who accepts handoffs but was never heard was never asked. After each turn over the known ones,
-- one probe goes to the next of the others.
-- Referral-specific test retired with invite handoffs.


-- 1.5.8 (the author's ask: a build to hand another member "que vai mostrar pra gente que ele
-- recebeu e no reload você já poder pegar"): the recruiting event log in the saved variables, its
-- /oly bug section and /oly recruit log. Applicants appear as a tag, members by character name.
local function WithLog(fn)
	local saved = ns.db.recruitLog
	ns.db.recruitLog = nil
	H.ResetLogForTests()
	local ok, err = pcall(fn)
	ns.db.recruitLog = saved
	H.ResetLogForTests()
	if not ok then error(err, 0) end
end

local function LogHas(text)
	for _, line in ipairs(H.LogLines()) do if line:find(text, 1, true) then return line end end
end

local function LogNever(text)
	for _, line in ipairs(H.LogLines()) do assert(not line:find(text, 1, true), "the log names an applicant: " .. line) end
end

-- Referral-specific test retired with invite handoffs.


test("recruit log (1.5.8): the ring keeps the newest 200 lines and a crowd's sightings stay few", function()
	WithHandoff(function(scene)
		WithLog(function()
			for i = 1, H.LOG_MAX + 5 do H.Log("TEST", "line " .. i) end
			eq(#ns.db.recruitLog, H.LOG_MAX, "bounded")
			assert(ns.db.recruitLog[1]:find("TEST line 6$"), "the oldest dropped")
			assert(ns.db.recruitLog[H.LOG_MAX]:find("TEST line 205$"))
			H.Log("TEST", "bad|cffff0000\ncolour")
			assert(ns.db.recruitLog[H.LOG_MAX]:find("TEST badcffff0000colour$"), "no escapes or line breaks are kept")
			ns.db.recruitLog = nil
			for i = 1, 10 do H.LogSeen("nameplate", ("Walker %s-%s"):format(("abcdefghij"):sub(i, i), home)) end
			H.LogSeen("who", "Walker a-" .. home)
			eq(#ns.db.recruitLog, H.SEEN_PER_MINUTE, "a few sightings a minute, each player once")
			scene.now = scene.now + 61
			H.LogSeen("who", "Walker a-" .. home)
			H.LogSeen("who", "Walker z-" .. home)
			eq(#ns.db.recruitLog, H.SEEN_PER_MINUTE + 1, "a minute later a new one is logged, not the same again")
			assert(ns.db.recruitLog[#ns.db.recruitLog]:find("SEEN who Wa%x%x%x%x$"))
		end)
	end)
end)

-- The test builds' "/oly recruit testjoin [Name]": the same handler a JOIN whisper reaches, so the
-- popup, the limit, Pass and the automatic offers run for real. A release build says it is not there.
test("recruit log (1.5.8): /oly recruit testjoin feeds a JOIN on a test build only", function()
	WithHandoff(function(scene)
		WithLog(function()
			local D = Dialogs()
			ns.Dialog = D
			local savedBuild = rawget(ns, "TEST_BUILD")
			local ok, err = pcall(function()
				ns.TEST_BUILD = nil
				eq(H.Slash("testjoin"), false)
				eq(#R.requests, 0, "a release build feeds nothing")
				eq(scene.printed[#scene.printed], ns.L.RECRUIT_TESTJOIN_OFF)
				eq(D.Find(DRAFT), nil)
				ns.TEST_BUILD = { n = 1, base = ns.VERSION }
				pcall(SlashCmdList.OLYMPUS, "recruit testjoin")
				local req = assert(R.requests[1], "a test build creates the request")
				assert(req.name:match("^Olytest%d+%-"), "a made-up name with digits: " .. req.name)
				eq(req.viaWhisper, true)
				eq(req.handoffIntent, "guild", "as a plain JOIN whisper")
				local draft = assert(D.Find(DRAFT), "and its popup")
				eq(draft.data.req, req)
				assert(LogHas("TESTJOIN " .. H.Tag(req.name)))
				assert(LogHas("JOIN " .. H.Tag(req.name)))
				draft:Hide()
				eq(H.Slash("testjoin Named Tester"), true)
				eq(R.requests[2].name, "Named Tester-" .. home, "or from the name given")
			end)
			ns.TEST_BUILD = savedBuild
			if not ok then error(err, 0) end
		end)
	end)
end)

-- 1.5.8 (the author's: "roda a simulação, faz teste todos os testes possíveis"): a guild of six,
-- each member his own copy of Recruit.lua and RecruitHandoff.lua (their own queues, limits, offers
-- and logs), whispering each other through one in-memory transport that checks each packet's guard
-- when it leaves. One busy recruiter is at his 10 invites a minute with the automatic offers on;
-- two members accept handoffs and can invite, one accepts but is at his own limit, two do not
-- accept. Forty JOINs reach the busy recruiter over a few minutes.
local addonDir = debug.getinfo(1, "S").source:match("^@(.-)tests/[^/]*$") or ""

local function SimDialogs(defs)
	local shown, D = {}, {}
	function D.Find(which, data)
		for i = #shown, 1, -1 do
			local f = shown[i]
			if f.which == which and f.open and (data == nil or f.data == data) then return f end
		end
	end
	function D.Show(which, a, _, data)
		local f = { which = which, text = a, data = data, open = true, def = defs[which] or StaticPopupDialogs[which] }
		f.Hide = function() f.open = false end
		f.IsShown = function() return f.open end -- (a frame's, as the game's popups have)
		shown[#shown + 1] = f
		return f
	end
	function D.Hide(which) local f = D.Find(which); if f then f.open = false end end
	function D.CloseOnEscape() end
	return D
end

local function SimClient(world, name)
	local c = { name = name, later = {}, timers = {}, printed = {}, defs = {} }
	local cns = setmetatable({}, { __index = ns })
	cns.me, cns.db, cns.rdb = name, { log = {}, errors = {} }, {}
	cns.Comm = setmetatable({
		Handle = function() end, HandleOutside = function() end,
		WhisperOutside = function() return true end,
		Whisper = function(peer, word, _, _, logged, done, options)
			eq(logged, false, "handoff packets do not go to the chat log")
			world.queue[#world.queue + 1] = { from = c, peer = peer, word = word, done = done, guard = options and options.guard }
			return true
		end,
	}, { __index = ns.Comm })
	cns.On, cns.RegisterEvent = function() end, function() end
	cns.Print = function(msg) c.printed[#c.printed + 1] = tostring(msg) end
	cns.After = function(delay, _, fn) c.later[#c.later + 1] = { due = world.scene.now + (tonumber(delay) or 0), fn = fn } end
	cns.Every = function(every, label, fn)
		local timer = { every = every, next = world.scene.now + every, fn = fn }
		timer.Cancel = function() if c.timers[label] == timer then c.timers[label] = nil end end
		c.timers[label] = timer
		return timer
	end
	cns.Dialog = SimDialogs(c.defs)
	c.D = cns.Dialog
	-- The copies define their own popups; the harness's stay as they were.
	local before = {}
	for k, v in pairs(StaticPopupDialogs) do before[k] = v end
	assert(loadfile(addonDir .. "Olympus/Recruit.lua"))("Olympus", cns)
	assert(loadfile(addonDir .. "Olympus/RecruitHandoff.lua"))("Olympus", cns)
	for k, v in pairs(StaticPopupDialogs) do if before[k] ~= v then c.defs[k] = v end end
	for k in pairs(c.defs) do StaticPopupDialogs[k] = before[k] end
	c.ns, c.R, c.H = cns, cns.Recruit, cns.Recruit.Handoff
	world.byName[name] = c
	world.clients[#world.clients + 1] = c
	return c
end

-- One packet at a time, in order; a guard that refuses drops it (as Comm's queue does).
local function SimDeliver(world)
	local n = 0
	while #world.queue > 0 do
		n = n + 1
		assert(n < 5000, "the packets settle")
		local p = table.remove(world.queue, 1)
		local ok, why = true, nil
		if p.guard then ok, why = p.guard() end
		if p.done then p.done(ok and true or false, not ok and why or nil) end
		local to = world.byName[p.peer]
		if ok and to then
			local op, id, applicantName = p.word:match("^J4~(%u)~([^~]+)~.*~([^~]*)$")
			if op ~= "N" then eq(applicantName, "", "only a name packet carries a name") end
			world.sent[#world.sent + 1] = { from = p.from, to = to, op = op, id = id, name = applicantName, at = world.scene.now }
			to.H.Receive("WHISPER", p.from.name, p.word)
		end
	end
end

local function SimTake(c, world)
	local draft = c.D.Find(DRAFT)
	if not draft then return end
	local data = draft.data
	local who = data.req and data.req.name
	draft.def.extra.onClick(draft, data)
	-- (Since the 1.5.8 merge the popup stays until the paste: the command went to chat when it counted.)
	if data.taken and who then
		world.taken[#world.taken + 1] = { by = c, name = who, at = world.scene.now }
	end
	draft:Hide() -- (the player's paste closes it)
end

local function SimStep(world, c)
	local now = world.scene.now
	local due = c.later
	c.later = {}
	for _, item in ipairs(due) do
		if item.due <= now then item.fn() else c.later[#c.later + 1] = item end
	end
	for _, timer in pairs(c.timers) do
		if timer.next <= now then
			timer.next = now + timer.every
			timer.fn()
		end
	end
end

-- Referral-specific test retired with invite handoffs.


-- The log's count of a minute's commands: a popup left open past the minute counted the commands
-- already gone from it ("11/10"), since nothing had looked at the limit while it stayed open.
test("recruit log (1.5.8): a popup left open past the minute logs that minute's own count", function()
	WithHandoff(function(scene)
		WithLog(function()
			local D = Dialogs()
			ns.Dialog = D
			local savedUtil = ChatFrameUtil
			ChatFrameUtil = { OpenChat = function() end }
			local ok, err = pcall(function()
				for i = 1, 10 do R.OnWhisper("JOIN", ("Early %d-%s"):format(i, home)) end
				for i = 1, 10 do
					local open = D.Find(DRAFT)
					if open then open:Hide() end
					eq(R.Accept(R.requests[i]), true)
					local draft = assert(D.Find(DRAFT))
					draft.def.extra.onClick(draft, draft.data)
				end
				assert(LogHas("TOCHAT " .. H.Tag("Early 10-" .. home) .. " 10/10"))
				assert(LogHas("LIMIT 10 invites in a minute"), "the limit reached")
				R.OnWhisper("JOIN", "Late Recruit-" .. home)
				local late = R.requests[#R.requests]
				eq(late.name, "Late Recruit-" .. home)
				eq(R.Accept(late), true)
				local draft = assert(D.Find(DRAFT))
				scene.now = scene.now + 61
				draft.def.extra.onClick(draft, draft.data)
				assert(LogHas("TOCHAT " .. H.Tag(late.name) .. " 1/10"), "the minute holds only this one")
			end)
			ChatFrameUtil = savedUtil
			if not ok then error(err, 0) end
		end)
	end)
end)

-- Review of 1.5.8 (P2): "send bug" stops at Workshop.BUG_MAX bytes and the recruiting section comes
-- last, past the status, debug and log sections, so what another member sent back lost the very
-- lines that show he received a player. /oly recruit send sends the log alone, to fit.
test("recruit log (review of 1.5.8): /oly recruit send sends the newest lines to the author whole", function()
	WithHandoff(function(scene)
		WithLog(function()
			local W = ns.Workshop
			local savedOnline, savedSend = W.AuthorOnline, W.SendBug
			local online, sent = true, {}
			W.AuthorOnline = function() return online end
			W.SendBug = function(text) sent[#sent + 1] = text; return true end
			local ok, err = pcall(function()
				for i = 1, H.LOG_MAX do H.Log("TEST", ("an earlier line %d %s"):format(i, ("x"):rep(40))) end
				local received, walker = "Handed Recruit-" .. home, "Passing Walker-" .. home
				H.LogPacket("RX", "O", mate)
				H.LogPacket("TX", "C", mate)
				H.LogPacket("RX", "N", mate, received)
				H.LogItem("POPUP", { name = received }, "handoff")
				local okSlash, errSlash = pcall(SlashCmdList.OLYMPUS, "recruit send")
				assert(okSlash, errSlash)
				local text = assert(sent[1], "the log goes to the author")
				local out = W.Outgoing(text)
				eq(out:find("[cut]", 1, true), nil, "it fits what a report carries")
				assert(out:find("^Recruiting log of Local Recruiter"), out:sub(1, 80))
				assert(out:find("Invite handoffs removed", 1, true), "with the summary")
				assert(out:find("RX offer < Guild Recruiter", 1, true), "the offer heard")
				assert(out:find("RX name " .. H.Tag(received) .. " < Guild Recruiter", 1, true), "the name received")
				assert(out:find("POPUP " .. H.Tag(received) .. " handoff", 1, true), "and its popup, the newest line")
				eq(out:find("Handed Recruit", 1, true), nil, "the applicant by tag only")
				-- The author offline: nothing sent, and the log to copy is pointed to.
				online = false
				scene.printed = {}
				pcall(SlashCmdList.OLYMPUS, "recruit send")
				eq(#sent, 1)
				eq(scene.printed[#scene.printed], ns.L.RECRUIT_SEND_OFFLINE)
			end)
			W.AuthorOnline, W.SendBug = savedOnline, savedSend
			if not ok then error(err, 0) end
		end)
	end)
end)

-- Review of 1.5.8 (P2): a member who took no names (handoffs off, at his own limit, or not allowed
-- to invite) never answered a probe, and each such probe held the busy recruiter's next one back
-- for its twenty seconds: about one JOIN a minute handed on when few members accept. He now says
-- no at once, and the recruiter asks the next member a second later.
-- Referral-specific test retired with invite handoffs.


-- Referral-specific test retired with invite handoffs.


-- Review of 1.5.8 (P2): a clock of frames for the paste watch. Input lands first in a frame, then
-- the timers due by then run, as the game does (ns.After and GetTime follow this clock).
local function WithFrames(scene, fn)
	local saved = { after = ns.After, time = GetTime, util = rawget(_G, "ChatFrameUtil"), box = rawget(_G, "ACTIVE_CHAT_EDIT_BOX") }
	local clock, pending = 1000, {}
	ns.After = function(seconds, _, callback) pending[#pending + 1] = { at = clock + (tonumber(seconds) or 0), fn = callback } end
	GetTime = function() return clock end
	local box = { text = "" }
	function box.GetText(self) return self.text end
	ChatFrameUtil = { OpenChat = function() box.text = ""; ACTIVE_CHAT_EDIT_BOX = box end }
	local frames = {}
	function frames.Step(input)
		clock = clock + 1 / 60
		if input then input(box) end
		local due = {}
		for i = #pending, 1, -1 do if pending[i].at <= clock then table.insert(due, 1, table.remove(pending, i)) end end
		for _, t in ipairs(due) do t.fn() end
	end
	local ok, err = pcall(fn, frames, box)
	ns.After, GetTime, ChatFrameUtil, ACTIVE_CHAT_EDIT_BOX = saved.after, saved.time, saved.util, saved.box
	if not ok then error(err, 0) end
end

local function Paste(box) box.text = "/ginvite " .. box.command end
local function Enter() ACTIVE_CHAT_EDIT_BOX = nil end

test("recruit invite (review of 1.5.8): a paste and Enter on the next frames still close the popup", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		WithFrames(scene, function(frames, box)
			R.OnWhisper("JOIN", "Quick Hands-" .. home)
			eq(R.Accept(R.requests[1]), true)
			local draft = assert(D.Find(DRAFT))
			box.command = "Quick Hands"
			draft.def.extra.onClick(draft, draft.data) -- Ctrl+C: empty chat opens
			eq(ACTIVE_CHAT_EDIT_BOX, box)
			frames.Step()
			frames.Step(Paste) -- Ctrl+V
			frames.Step(Enter) -- Enter, the next frame: the invite went and chat closed
			for _ = 1, 30 do frames.Step() end
			eq(draft.open, false, "the popup closed on the paste the frame before Enter")
		end)
	end)
end)

test("recruit invite (review of 1.5.8): a paste long after Ctrl+C, chat open all along, still closes the popup", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		WithFrames(scene, function(frames, box)
			R.OnWhisper("JOIN", "Slow Hands-" .. home)
			eq(R.Accept(R.requests[1]), true)
			local draft = assert(D.Find(DRAFT))
			box.command = "Slow Hands"
			draft.def.extra.onClick(draft, draft.data)
			for _ = 1, 40 * 60 do frames.Step() end -- 40 s with chat open and empty
			eq(draft.open, true, "nothing pasted yet: the popup stays")
			frames.Step(Paste)
			frames.Step()
			eq(draft.open, false, "the paste closes it")
		end)
	end)
end)

-- Review of 1.5.8 (P2): the scan's list keeps 24 players. A /who answer that fills it must not drop
-- the player whose popup is on screen, and a player already popped up who is found again (after his
-- row was dropped or went stale) does not pop up a second time.
local function Letters(i) return string.char(97 + (i - 1) % 26) .. string.char(97 + math.floor((i - 1) / 26)) end

test("recruit scan (review of 1.5.8): a full list keeps the player whose invite popup is up", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		local saved = rawget(_G, "ChatFrameUtil")
		ChatFrameUtil = { OpenChat = function() end }
		local ok, err = pcall(function()
			local tick = ScanOne(scene, "Lone Wolf-" .. home)
			tick()
			local draft = assert(D.Find(DRAFT), "his invite popup")
			local row = assert(draft.data.candidate)
			for i = 1, 30 do R.Candidates.ObserveWho(("Wander%s-%s"):format(Letters(i), home), "", "Human") end
			assert(R.Candidates.Check(row), "his row is kept while his popup is up")
			draft.def.extra.onClick(draft, draft.data) -- Ctrl+C
			eq(row.invitePrepared, true, "his command still goes to chat")
		end)
		ChatFrameUtil = saved
		if not ok then error(err, 0) end
	end)
end)

test("recruit scan (review of 1.5.8): a player already popped up, found again later, does not pop up twice", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		local savedTime, clock = GetTime, 2000
		GetTime = function() return clock end
		local ok, err = pcall(function()
			local wolf = "Lone Wolf-" .. home
			local tick = ScanOne(scene, wolf)
			tick()
			local draft = assert(D.Find(DRAFT), "his invite popup")
			draft:Hide()
			clock = clock + 181 -- his /who answer goes stale and his row leaves the list
			tick()
			R.Candidates.ObserveWho(wolf, "", "Human") -- the rotation's next /who finds him again
			tick()
			eq(D.Find(DRAFT), nil, "no second popup for him")
			for i = 1, 30 do R.Candidates.ObserveWho(("Wander%s-%s"):format(Letters(i), home), "", "Human") end
			R.Candidates.ObserveWho(wolf, "", "Human")
			tick()
			local next = D.Find(DRAFT)
			assert(next and next.data.candidate.name ~= "Lone Wolf", "another player pops up, not him")
		end)
		GetTime = savedTime
		if not ok then error(err, 0) end
	end)
end)

-- Review of 1.5.8 (P2): most of the scan's list now comes from its own /who and the mouseover. Such
-- a player's invite popup offers "Whisper them first" too (the author: "um botão com opção, Whisper
-- him first"): the whisper goes to the same name as his /ginvite, then his invite popup comes back.
test("recruit scan (review of 1.5.8): a /who-found player's popup offers Whisper them first, then comes back", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		local savedSay, said = ns.SayTo, {}
		ns.SayTo = function(name, text) said[#said + 1] = { name = name, text = text }; return true end
		local ok, err = pcall(function()
			local tick = ScanOne(scene, "Lone Wolf-" .. home)
			tick()
			local draft = assert(D.Find(DRAFT), "his invite popup")
			local row = draft.data.candidate
			eq(draft.def.button3Shown(draft, draft.data), true, "a /who-found player can be whispered first")
			draft.def.OnAlt(draft, draft.data)
			draft:Hide()
			local review = assert(D.Find("OLYMPUS_RECRUIT_OUTREACH"), "his whisper review opens")
			eq(review.data.candidate, row)
			review.editBox = { GetText = function() return "Hello there" end, SetText = function() end }
			review.def.OnAccept(review, review.data)
			eq(said[1] and said[1].name, row.name, "the whisper goes to the name his /ginvite carries")
			review:Hide(); review.def.OnHide(review, review.data)
			for _, fn in ipairs(scene.later) do fn() end
			local back = assert(D.Find(DRAFT), "his invite popup comes back after the whisper")
			eq(back.data.candidate, row)
		end)
		ns.SayTo = savedSay
		if not ok then error(err, 0) end
	end)
end)

-- 1.5.8 (the author's ask, 11-12: "tem que ter as variações, mas você tem que avaliar... que tem uma
-- vibe da Olympus"; "Come play with" read with a double meaning): five openings in turn, each naming
-- Olympus and keeping the JOIN line other recruiters' clients recognize.
test("recruit ads (1.5.8): five different openings, each with Olympus and the JOIN line, none with a double meaning", function()
	WithHandoff(function()
		eq(R.ANNOUNCE_OPENINGS, 5)
		local seen = {}
		for variant = 0, R.ANNOUNCE_OPENINGS - 1 do
			local text = R.AnnouncementText("Stormguard", variant)
			assert(text:find("Whisper JOIN", 1, true), "the JOIN line: " .. text)
			assert(#text <= 255, "fits a chat line: " .. text)
			assert(text:lower():find("olympus", 1, true), "names Olympus: " .. text)
			assert(not text:lower():find("come play", 1, true), "no double meaning: " .. text)
			assert(not seen[text], "each opening differs: " .. text)
			seen[text] = true
		end
	end)
end)

-- 1.5.8 (the author's test, 11-12: the scan's /who searched z-"Anvilmar", a subzone's name, and found
-- almost nobody): level ranges anywhere first, then the same ranges in the player's zone.
test("recruit scan (1.5.8): the /who rotation searches level ranges anywhere first, then the zone", function()
	WithHandoff(function()
		UseCandidates()
		local Q = R.Candidates
		local savedZone, savedTop = rawget(_G, "GetRealZoneText"), rawget(_G, "GetMaxPlayerLevel")
		GetRealZoneText = function() return "Dun Morogh" end
		GetMaxPlayerLevel = function() return 60 end
		local ok, err = pcall(function()
			eq(Q.SearchQuery(1), "1-10")
			eq(Q.SearchQuery(6), "51-60")
			eq(Q.SearchQuery(7), 'z-"Dun Morogh" 1-10')
			eq(Q.SearchQuery(12), 'z-"Dun Morogh" 51-60')
			eq(Q.SearchQuery(13), "1-10", "and round again")
			GetRealZoneText = function() return "" end
			eq(Q.SearchQuery(7), "1-10", "no zone: the ranges alone")
		end)
		GetRealZoneText, GetMaxPlayerLevel = savedZone, savedTop
		if not ok then error(err, 0) end
	end)
end)

-- 1.5.9 (the author's ask, 11-12: "Ele não está identificando quando a pessoa recusou o convite para
-- a guilda... Só recusou, já não vamos perturbar ela"): the game's decline line (ERR_GUILD_DECLINE_S,
-- or ERR_GUILD_DECLINE_AUTO_S for a player who blocks guild invites) keeps the player from popping up
-- again, after a reload too, for 7 days; his own JOIN later lets him through. (The strings are the
-- client's: these tests set them as the enUS client has them; tests/fixtures/forever-api.lua does not
-- list them yet.)
local DECLINE = "%s declines your guild invitation." -- (the enUS client's ERR_GUILD_DECLINE_S)
local DECLINE_AUTO = "%s has automatically declined your guild invitation." -- (ERR_GUILD_DECLINE_AUTO_S)
local function WithDecline(fn)
	local saved = { err = rawget(_G, "ERR_GUILD_DECLINE_S"), auto = rawget(_G, "ERR_GUILD_DECLINE_AUTO_S"),
		util = rawget(_G, "ChatFrameUtil"), time = GetTime }
	ERR_GUILD_DECLINE_S, ERR_GUILD_DECLINE_AUTO_S = DECLINE, DECLINE_AUTO
	ChatFrameUtil = { OpenChat = function() end }
	local clock = 2000
	GetTime = function() return clock end
	local ok, err = pcall(fn, function(seconds) clock = clock + seconds end)
	ERR_GUILD_DECLINE_S, ERR_GUILD_DECLINE_AUTO_S = saved.err, saved.auto
	ChatFrameUtil, GetTime = saved.util, saved.time
	if not ok then error(err, 0) end
end

local function ScanRows()
	local list = {}
	R.Candidates.EachRow(function(row) list[#list + 1] = row.full end)
	return list
end

-- No string kept in `t` (its keys and values, nested) holds `word`, case folded.
local function SavedNever(t, word)
	for k, v in pairs(t) do
		for _, x in ipairs({ k, v }) do
			if type(x) == "string" then assert(not ns.Fold(x):find(ns.Fold(word), 1, true), "a name kept: " .. x)
			elseif type(x) == "table" then SavedNever(x, word) end
		end
	end
end

test("recruit scan (1.5.9): a player who declines the invite does not pop up again, after a reload too, for 7 days", function()
	WithHandoff(function(scene)
		WithLog(function()
			WithDecline(function(advance)
				local D = Dialogs()
				ns.Dialog = D
				local wolf = "Lone Wolf-" .. home
				local tick = ScanOne(scene, wolf)
				tick()
				local draft = assert(D.Find(DRAFT), "his invite popup")
				draft.def.extra.onClick(draft, draft.data) -- Ctrl+C
				draft:Hide()
				-- (Changed on purpose in review: the author's "Só recusou, já não vamos perturbar ela" is any
				-- decline of his invite, however it went, so the two lines that changed nothing here, before
				-- Ctrl+C and for a name never invited, now count: the next test. Here, other lines; and a
				-- member's handoff of him is refused as a sighting, below.)
				eq(R.OnSystemLine("Lone Wolf is already in a guild."), false, "another system line changes nothing")
				eq(ns.rdb.recruitDeclined, nil, "nothing saved yet")
				eq(R.OnSystemLine(DECLINE:format("Lone Wolf")), true, "his decline")
				eq(R.Declined(wolf), true)
				assert(LogHas("DECLINED " .. H.Tag(wolf)), "logged, by tag")
				LogNever("Lone Wolf")
				eq(scene.printed[#scene.printed], ns.L.RECRUIT_DECLINED:format(ns.DisplayName(wolf)), "the player is told")
				-- (Review of 1.5.9) The saved list keeps a hash of his name and when, never the name.
				local kept = 0
				for _, t in pairs(ns.rdb.recruitDeclined) do kept = kept + 1; eq(t, scene.now) end
				eq(kept, 1, "one player kept")
				SavedNever(ns.rdb.recruitDeclined, "Lone Wolf")
				eq(#ScanRows(), 0, "his row leaves the list")
				advance(181)
				R.Candidates.ObserveWho(wolf, "", "Human") -- the next /who finds him again
				tick()
				eq(D.Find(DRAFT), nil, "no popup for him")
				eq(#ScanRows(), 0, "not listed either")
				eq(R.TakeHandoff(wolf, mate, true), false, "a member's sighting of him is not taken here")
				-- A reload: the session's memory goes, the saved list stays.
				R.ResetForTests()
				R.Candidates.Reset()
				R.ToggleWhisperRecruiting()
				if not R.Candidates.Enabled() then assert(Find(R.WhisperLines(), ns.L.RECRUIT_CANDIDATES_OFF)).onClick() end
				assert(R.Candidates.Enabled(), "the scan is on again")
				tick = assert(scene.timers["recruit candidates"])
				R.Candidates.ObserveWho(wolf, "", "Human")
				tick()
				eq(D.Find(DRAFT), nil, "after a reload, still no popup for him")
				eq(R.Declined(wolf), true, "kept in the saved list")
				-- Seven days later he is like any other player again.
				scene.now = scene.now + 7 * 86400
				advance(181)
				R.Candidates.ObserveWho(wolf, "", "Human")
				tick()
				local back = assert(D.Find(DRAFT), "after 7 days he pops up again")
				eq(back.data.candidate.full, wolf)
				eq(next(ns.rdb.recruitDeclined), nil, "the expired name left the saved list")
			end)
		end)
	end)
end)

-- Review of 1.5.9 (P2): only an invite taken to chat with Ctrl+C or Open game chat counted, so a
-- decline after an invite typed by hand, sent from the game's menu, with the gamepad UI (whose popup
-- opens no chat box) or after a /reload was lost, and he popped up again. The game tells the inviter
-- alone: every decline line counts (the author: "Só recusou, já não vamos perturbar ela").
test("recruit (1.5.9): a decline counts however the invite went: typed by hand, from the game's menu, after a /reload", function()
	WithHandoff(function(scene)
		WithLog(function()
			WithDecline(function()
				local D = Dialogs()
				ns.Dialog = D
				local wolf = "Lone Wolf-" .. home
				local tick = ScanOne(scene, wolf)
				tick()
				local draft = assert(D.Find(DRAFT), "his invite popup")
				-- The officer typed /ginvite himself, or copied it from the gamepad UI's box: no Ctrl+C here.
				eq(R.OnSystemLine(DECLINE:format("Lone Wolf")), true, "his decline")
				eq(R.Declined(wolf), true)
				eq(draft:IsShown(), false, "his popup closes")
				eq(#ScanRows(), 0, "his row leaves the list")
				-- A player Olympus never showed, invited from the game's menu.
				eq(R.OnSystemLine(DECLINE:format("Menu Pick")), true)
				eq(R.Declined("Menu Pick-" .. home), true)
				-- A /reload between an invite and the answer: the session's memory is gone, recruiting
				-- not back yet (nothing said, the decline kept all the same).
				R.ResetForTests()
				local printed = #scene.printed
				eq(R.OnSystemLine(DECLINE:format("Late Answer")), true)
				eq(R.Declined("Late Answer-" .. home), true)
				eq(#scene.printed, printed, "nothing said while not recruiting")
				eq(R.Declined(wolf), true, "the earlier ones are kept")
				eq(R.Declined("Never Asked-" .. home), false, "nobody else")
				SavedNever(ns.rdb.recruitDeclined, "Late Answer")
				LogNever("Menu Pick")
			end)
		end)
	end)
end)

-- Review of 1.5.9 (P2): a player who blocks guild invites declines on his own, in the game's other
-- line (ERR_GUILD_DECLINE_AUTO_S): he never accepts, and was offered again and again. Where the
-- client has neither line, nothing happens.
test("recruit (1.5.9): the game's automatic decline (he blocks guild invites) counts too; without the client's lines nothing", function()
	WithHandoff(function(scene)
		WithLog(function()
			WithDecline(function()
				local wolf = "Lone Wolf-" .. home
				eq(R.OnSystemLine(DECLINE_AUTO:format("Lone Wolf")), true)
				eq(R.Declined(wolf), true)
				assert(LogHas("DECLINED " .. H.Tag(wolf)))
				ERR_GUILD_DECLINE_S, ERR_GUILD_DECLINE_AUTO_S = nil, nil
				R.ResetForTests()
				ns.rdb = {}
				eq(R.OnSystemLine(DECLINE:format("Lone Wolf")), false, "no line known: nothing")
				eq(R.OnSystemLine(DECLINE_AUTO:format("Lone Wolf")), false)
				eq(R.Declined(wolf), false)
				eq(ns.rdb.recruitDeclined, nil, "nothing saved")
			end)
		end)
	end)
end)

-- Review of 1.5.9 (P2): a JOIN whispered right after declining (Escape by mistake) was dropped: his
-- first JOIN, gone at the decline, still held the 10-minute repeat block.
test("recruit (1.5.9): his JOIN right after he declined comes through at once", function()
	WithHandoff(function(scene)
		WithLog(function()
			WithDecline(function()
				local D = Dialogs()
				ns.Dialog = D
				R.OnWhisper("JOIN", applicant)
				local draft = assert(D.Find(DRAFT), "his JOIN popup")
				draft.def.extra.onClick(draft, draft.data) -- Ctrl+C
				draft:Hide()
				eq(R.OnSystemLine(DECLINE:format("New Recruit")), true, "his decline")
				eq(#R.requests, 0)
				scene.now = scene.now + 30
				R.OnWhisper("JOIN", applicant) -- "sorry, a misclick"
				eq(R.Declined(applicant), false, "his JOIN clears the decline")
				eq(#R.requests, 1, "and comes through")
				eq(assert(D.Find(DRAFT), "his popup").data.req.name, applicant)
				eq(LogHas("JOINDROP"), nil, "not dropped")
				R.OnWhisper("JOIN", applicant) -- (the repeat block itself stays)
				eq(#R.requests, 1)
				assert(LogHas("JOINDROP " .. H.Tag(applicant)))
			end)
		end)
	end)
end)

test("recruit (1.5.9): a JOIN whose invite he declined leaves, a sighting of him is not taken from a member, and his own JOIN later lets him through", function()
	WithHandoff(function(scene)
		WithLog(function()
			WithDecline(function()
				local D = Dialogs()
				ns.Dialog = D
				-- (Changed on purpose in review, the author's "Só recusou, já não vamos perturbar ela": a
				-- decline before any invite here counts too, so this test no longer starts with one that
				-- changes nothing; and only a sighting of him is refused from a member, as his JOIN passed
				-- on is his own ask: "recruit handoff (1.5.9): a passed JOIN...".)
				R.OnWhisper("JOIN", applicant)
				local draft = assert(D.Find(DRAFT), "his JOIN popup")
				draft.def.extra.onClick(draft, draft.data) -- Ctrl+C
				draft:Hide()
				eq(R.OnSystemLine(DECLINE:format("New Recruit")), true, "his decline")
				eq(#R.requests, 0, "his JOIN leaves the queue")
				assert(LogHas("DECLINED " .. H.Tag(applicant)))
				scene.now = scene.now + R.REQUEST_EACH + 1
				eq(R.TakeHandoff(applicant, mate, true), false, "a member's sighting of him is not taken here")
				eq(#R.requests, 0)
				eq(D.Find(DRAFT), nil)
				R.OnWhisper("JOIN", applicant) -- he asks again, on his own
				eq(R.Declined(applicant), false, "his own JOIN clears the decline")
				eq(#R.requests, 1, "his JOIN is let through")
				assert(D.Find(DRAFT), "and pops up")
				assert(LogHas("UNDECLINED " .. H.Tag(applicant)))
			end)
		end)
	end)
end)

-- 1.5.9 (the same ask): his invite popup, still up because its paste was not seen (the gamepad UI
-- reads no chat box), closes at his decline, as it would hold the next popups back; a reply of his to
-- the whisper sent first pops up nothing; the recruiting log says why a member's sighting of him was
-- not taken.
test("recruit (1.5.9): a decline closes his popup waiting for the paste, and his reply to our whisper pops up nothing", function()
	WithHandoff(function(scene)
		WithLog(function()
			WithDecline(function()
				local D = Dialogs()
				ns.Dialog = D
				local savedSay = ns.SayTo
				ns.SayTo = function() return true end
				local ok, err = pcall(function()
					local wolf = "Lone Wolf-" .. home
					local tick = ScanOne(scene, wolf)
					tick()
					local draft = assert(D.Find(DRAFT), "his invite popup")
					draft.def.OnAlt(draft, draft.data) -- Whisper them first
					draft:Hide()
					local review = assert(D.Find("OLYMPUS_RECRUIT_OUTREACH"), "his whisper review")
					review.editBox = { GetText = function() return "Hello there" end, SetText = function() end }
					review.def.OnAccept(review, review.data)
					review:Hide(); review.def.OnHide(review, review.data)
					for _, fn in ipairs(scene.later) do fn() end
					local back = assert(D.Find(DRAFT), "his invite popup back after the whisper")
					back.def.extra.onClick(back, back.data) -- Ctrl+C; the paste is not seen
					eq(back:IsShown(), true, "the popup waits for the paste")
					eq(R.OnSystemLine(DECLINE:format("Lone Wolf")), true, "his decline")
					eq(back:IsShown(), false, "his popup closes")
					R.OnWhisper("No thanks", wolf)
					eq(#R.requests, 0, "his reply to the whisper makes no request")
					eq(D.Find("OLYMPUS_RECRUIT_REPLY"), nil, "and pops up nothing")
					eq(D.Find(DRAFT), nil)
					assert(LogHas("JOINDROP " .. H.Tag(wolf) .. " reply"), "the log keeps the reply dropped")
					eq(R.TakeHandoff(wolf, mate, true), false)
					assert(LogHas("DECLINED " .. H.Tag(wolf) .. " handoff not taken"), "and the sighting refused")
					LogNever("Lone Wolf")
					R.OnWhisper("JOIN", wolf) -- his own JOIN still comes in
					eq(#R.requests, 1)
					eq(R.Declined(wolf), false)
				end)
				ns.SayTo = savedSay
				if not ok then error(err, 0) end
			end)
		end)
	end)
end)

-- Review of 1.5.9 (P1): a player who declined this member's invite, then whispered JOIN to another
-- member who passed him on, was refused here when his name came: no acknowledgement went back, and
-- the member who passed him kept him "waiting" an hour with his own popup hidden, so nobody invited
-- him. His JOIN is his own ask: taken, and his decline here forgotten. A sighting of him (the offer's
-- id says which; a 1.5.8 member's offer reads as a JOIN) is still not taken.
-- Referral-specific test retired with invite handoffs.


-- Referral-specific test retired with invite handoffs.


-- The same finding end to end: two members' own copies of the addon. He declined B's invite; his JOIN
-- reaches A, who passes it; B claims, gets the name and takes him; A's request ends handed.
-- Referral-specific test retired with invite handoffs.


-- Review of 1.5.9 (P2): Pass turned the automatic offers on for the session, and the next login turned
-- them off again, a switch that changed between logins (the author, 11-12: "Ele tem que ficar
-- desativado se ele estava desativado... As configurações não devem mudar entre login"). The passed
-- JOIN still goes; the others waiting stay here, as the switch is off.
-- Referral-specific test retired with invite handoffs.


-- Review of the 1.5.9 release (A-2): a Pass made while the automatic offers were on kept no timer of its
-- own, so once he turned the offers off before any member answered, what he passed got no probe and no
-- popup until it expired an hour later. What he passed by hand goes whatever the switch.
-- Referral-specific test retired with invite handoffs.


---------------------------------------------------------------------------
-- 1.5.9: Church > Invites in sections, and the handoffs' network fixes from the 1.5.8 reviews.
---------------------------------------------------------------------------

-- The headings of a page's lines, by id, in order.
local function Headings(lines)
	local out = {}
	for _, line in ipairs(lines) do
		if line.header then
			assert(not line.onClick, "a heading takes no click: " .. tostring(line.text))
			out[#out + 1] = line.id or ("?" .. tostring(line.text))
		end
	end
	return table.concat(out, ",")
end
-- The lines from the heading `id` to the next heading (the heading first).
local function SectionOf(lines, id)
	local out
	for _, line in ipairs(lines) do
		if line.header and out then break end
		if line.id == id then out = {} end
		if out then out[#out + 1] = line end
	end
	return assert(out, "no section " .. id)
end
local SECTIONS = "recruit-section-recruiting,recruit-section-ads,recruit-section-scan,recruit-section-handoffs"

-- 1.5.9 (the author, 11-12: "ainda tô achando meio bagunçado... public recruitment announcement... ele
-- tá maior do que o de cima, aí parece que o de cima não tem tanta importância... talvez precisasse de
-- uma seção aqui com esse título maior... para as pessoas lerem e ser muito claro"): every part of the
-- page under a heading of the same kind, in the order they are used; the JOINs waiting inside the
-- Recruiting section, not under a heading of their own.
-- Referral-specific test retired with invite handoffs.


-- 1.5.9, the review of 1.5.8 (the author's: "se ela tentar ativar e ela não puder convidar pessoas, vai
-- avisar, tipo, você não pode convidar mesmo para sua guilda, fale com o seu GM"): the reason showed
-- only after a click on the switch. Now it is under the switch, and the sections he can't use are gone
-- (an ad asking for JOIN whispers he could not answer helped nobody).
test("recruit Invites page (1.5.9, regression): a member whose rank can't invite reads why under the switch", function()
	WithHandoff(function(scene)
		UseCandidates()
		eq(R.ToggleWhisperRecruiting(), false)
		scene.permission = false
		local lines = R.WhisperLines()
		eq(Headings(lines), "recruit-section-recruiting", "only the Recruiting section")
		eq(lines[2].id, "recruit-whisper-toggle")
		local why = assert(Id(lines, "recruit-no-invite"), "the reason is on the page, no click needed")
		assert(why.text:find(ns.L.RECRUIT_NO_INVITE_SHORT, 1, true))
		local tip = {}
		why.tooltip({ AddLine = function(_, text) tip[#tip + 1] = text end })
		eq(tip[1], ns.L.RECRUIT_NO_INVITE_RIGHT, "the whole sentence in its tooltip")
		eq(Find(lines, ns.L.RECRUIT_ADS_HINT), nil, "no ads to post")
		scene.permission = true
		eq(Id(R.WhisperLines(), "recruit-no-invite"), nil, "a member who can invite reads none")
	end)
end)

-- Hellos as a guildmate's client hears them (the real Comm.lua, FreshComm), lent to the main
-- namespace's Comm for the time of `fn`: what RecruitHandoff and Versions read of the hellos.
local function WithHellos(hellos, fn)
	local savedChat, savedPeers, savedVersion = C_ChatInfo, ns.Comm.HandoffPeers, ns.Comm.PeerVersion
	local ok, err = pcall(function()
		local cns, deliver = FreshComm()
		for _, hello in ipairs(hellos) do deliver("GUILD", hello[1], hello[2]) end
		ns.Comm.HandoffPeers, ns.Comm.PeerVersion = cns.Comm.HandoffPeers, cns.Comm.PeerVersion
		fn(cns, deliver)
	end)
	C_ChatInfo, ns.Comm.HandoffPeers, ns.Comm.PeerVersion = savedChat, savedPeers, savedVersion
	if not ok then error(err, 0) end
end
-- `flag`: true, the hello says "J" (he takes handoffs); false, "j" (he takes none: since the review of
-- 1.5.9 a 1.5.9 hello says it, never the version); nil, neither, as a client before the flag says.
local function Hello(version, flag)
	return ("H1~%s~%s~p~~~~R~N%s"):format(version, home, flag == true and "~J" or flag == false and "~j" or "")
end

-- 1.5.9, the review of 1.5.8: "Offer to another member" listed the first six members online by rank,
-- so a plain member who takes handoffs (any rank may, since 1.5.8) was never there. Those whose hello
-- says they take them come first now; one whose hello says he takes none is not listed.
-- Removed referral behavior: replaced by the permanent off regression below.


-- 1.5.9, the review of 1.5.8 (throughput): a member without Olympus never answers a probe, and each
-- costs PROBE_TTL (20 s). Clients that take handoffs say so in their hello (Comm.Hello's "J"); the
-- probes ask them first, members known to run Olympus otherwise after a turn over them (a 1.5.8
-- hello has no flag yet), and never a member whose hello says he takes none or names a version
-- before handoffs. The unheard still get one probe after each turn (review of 1.5.8).
-- Referral-specific test retired with invite handoffs.


-- Older clients only (no hello carries the flag): the 1.5.8 order, from the hellos themselves.
-- Referral-specific test retired with invite handoffs.


-- 1.5.9: the flag a member's hello carries. "J", its 9th field, only while he takes handoffs; a quiet
-- member (other guildmates sort before him: he says hello every ten minutes) says it at his next tick
-- (HELLO_EVERY) after it turns, either way. A hello without it reads as before, here and on a 0.9.8
-- client (older clients read the fields before it), and the fields before it read the same with it.
-- Referral-specific test retired with invite handoffs.


---------------------------------------------------------------------------
-- The review of 1.5.9: the network fixes and Church > Invites, checked again.
---------------------------------------------------------------------------

-- Review of 1.5.9 (P2): the Offer picker asked Versions.HasOlympus of every member online it heard no
-- hello from, and each ask went through every hello heard: about 150 ms a redraw with 400 online and
-- 150 heard, against 0.1 ms in 1.5.8. The picker reads the hellos once now, in the same order.
-- Removed referral behavior: replaced by the permanent off regression below.


-- Review of 1.5.9 (P2): "takes none" was read from the version, a hello naming 1.5.9 or newer without
-- "J". This branch's builds still name 1.5.8, so a member running one with handoffs off was probed every
-- turn and listed; and a release after 1.5.9 would have read every 1.5.9 client, which takes handoffs
-- through the 1.5.8 words, as taking none. The hello says "j" now, and a hello with neither is asked.
-- Referral-specific test retired with invite handoffs.


-- Review of 1.5.9 (P2): with Recruiting off the page still offered "Send ad to /1 General". An ad asks
-- players to whisper JOIN, which only Recruiting answers: every reply was dropped. (The author, 11-12:
-- "Os botões que façam sentido".) Off, the ads say Recruiting comes first, as the scan and handoffs do.
test("recruit ads (review of 1.5.9, regression): with Recruiting off no ad is offered, opened or posted", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		local savedList, savedChat = GetChannelList, C_ChatInfo
		local posted = 0
		GetChannelList = function() return 1, "General", false end
		C_ChatInfo = setmetatable({
			GetChannelInfoFromIdentifier = function(name) if name == "General" then return { zoneChannelID = 11 } end end,
			SendChatMessage = function() posted = posted + 1 end,
		}, { __index = savedChat })
		local ok, err = pcall(function()
			local L, AD = ns.L, "OLYMPUS_RECRUIT_ANNOUNCEMENT"
			local label = L.RECRUIT_ANNOUNCE_CHANNEL:format(1, "General")
			eq(R.IsWhisperRecruiting(), true)
			local send = assert(Find(R.WhisperLines(), label), "on, the ad for General is offered")
			send.onClick()
			local draft = assert(D.Find(AD), "its draft opens")
			eq(R.ToggleWhisperRecruiting(), false, "recruiting turned off")
			eq(D.Find(AD), nil, "the open draft closes with it")
			local lines = R.WhisperLines()
			eq(Find(lines, label), nil, "off, no ad offered")
			eq(Id(lines, "recruit-announcement-reminder"), nil, "nor its reminder")
			local ads = SectionOf(lines, "recruit-section-ads")
			eq(#ads, 2, "the ads' heading and one line")
			assert(ads[2].text:find(L.RECRUIT_SECTION_NEEDS_ON, 1, true), "saying Recruiting comes first")
			send.onClick()
			eq(D.Find(AD), nil, "a row kept from before opens no draft")
			-- Why: a JOIN whispered while recruiting is off is answered by nobody.
			R.OnWhisper("JOIN", applicant)
			eq(#R.requests, 0)
			-- The game took the rank's invite away with a draft open: Post sends nothing and closes it.
			eq(R.ToggleWhisperRecruiting(), true)
			assert(Find(R.WhisperLines(), label)).onClick()
			draft = assert(D.Find(AD))
			draft.editBox = { GetText = function() return draft.data.command end }
			scene.permission = false
			eq(R.IsWhisperRecruiting(), false)
			draft.def.OnButton2(draft, draft.data, "clicked")
			eq(posted, 0, "nothing posted")
			eq(D.Find(AD), nil, "the draft closed")
		end)
		GetChannelList, C_ChatInfo = savedList, savedChat
		if not ok then error(err, 0) end
	end)
end)

-- Review of 1.5.9 (P2): the sections were not laid out alike. Recruiting showed its switch and then its
-- grey line; the scan and the handoffs their grey line, one step in, above switches further left (the
-- author's ask: "uma coisa que faz sentido depois da outra"). Every section now: its heading, its
-- switches at the left, the one grey line under them, and the rest one step in.
-- Referral-specific test retired with invite handoffs.


-- Review of 1.5.9 (P2): the JOINs moved one step in, and rows already long were cut: "Waiting for
-- confirmation from Local Recruiter <Olympus Prime>", or "joined your guild" in German, Spanish, French,
-- Italian and Russian. The length test listed none of them. The window's rows do not wrap: here is the
-- page as the window gets it, every kind of row on it, in every language, with long names, each row
-- within what its indent leaves (Views.lua: 12 pixels a step in; about 5 pixels a character).
local ROOT = debug.getinfo(1, "S").source:match("^@(.-)tests/[^/]*$") or ""
local function LanguageLines(code)
	local lns, saved = {}, GetLocale
	GetLocale = function() return code end
	local ok, err = pcall(function()
		for line in io.lines(ROOT .. "Olympus/Olympus.toc") do
			local f = line:match("^%s*(Locales%.lua)%s*$") or line:match("^%s*(Locales[\\/].-%.lua)%s*$")
			if f then assert(loadfile(ROOT .. "Olympus/" .. f:gsub("\\", "/")))("Olympus", lns) end
		end
	end)
	GetLocale = saved
	if not ok then error(err, 0) end
	return lns.L
end
-- `fn` with the addon's words in language `code`: each file holds ns.L itself, so they are swapped in place.
local function InLanguage(code, fn)
	local L, saved = ns.L, {}
	for k, v in pairs(L) do saved[k] = v end
	local ok, err = pcall(function()
		for k, v in pairs(LanguageLines(code)) do L[k] = v end
		fn()
	end)
	for k in pairs(saved) do L[k] = saved[k] end
	for k in pairs(L) do if saved[k] == nil then L[k] = nil end end
	if not ok then error(err, 0) end
end
local function Plain(text) return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Chars(s)
	local n = 0
	for _ in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
	return n
end
-- Characters a row has room for at each indent (the window's 296-pixel list), and a heading's larger font.
local ROOM, HEADING_ROOM = { [0] = 54, 54, 51, 48 }, 40

-- Referral-specific test retired with invite handoffs.


---------------------------------------------------------------------------
-- 1.5.9: a request from the Join Olympus screen (J3) at a member recruiting by whisper. (The author,
-- 11-12, about that request: "a pessoa que recebe do outro lado que tem o addon... podia aparecer o
-- pop-up também para dar Ctrl-C, Ctrl-V e Enter, que nem outro fluxo".)
---------------------------------------------------------------------------
local J3 = ("J3~%s~12~MAGE"):format(own)
local WORDS = "Hi! I'd love to join Olympus. Does <Olympus Prime> have room for one more?"
local function ClassName(file) return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file] or "" end

-- The Watch's notice of a join request (Watch.EntryAttempt; its own tests are in tests/watch.lua).
local function WithWatchNotice(fn)
	local saved, noticed = rawget(ns, "Watch"), {}
	ns.Watch = { EntryAttempt = function(name) noticed[#noticed + 1] = name end }
	local ok, err = pcall(fn, noticed)
	ns.Watch = saved
	if not ok then error(err, 0) end
end

-- Fails before 1.5.9: the J3 made a Census row alone (no popup, no handoff, nothing logged).
test("join screen request (1.5.9): at a recruiting member a J3 pops up the JOIN's invite command, counts in the minute and is logged", function()
	WithHandoff(function(scene)
		WithLog(function()
			WithWatchNotice(function(noticed)
				local D = Dialogs()
				ns.Dialog = D
				local savedUtil, savedBox = ChatFrameUtil, rawget(_G, "ACTIVE_CHAT_EDIT_BOX")
				ChatFrameUtil = { OpenChat = function() end }
				local ok, err = pcall(function()
					R.OnWhisper(WORDS, applicant)
					eq(#R.requests, 0, "his whisper alone is no JOIN")
					eq(R.OnJoinRequest("WHISPER", applicant, J3), true)
					local req = assert(R.requests[1])
					eq(req.viaWhisper, true, "in the recruiting queue, as a JOIN")
					eq(req.handoffIntent, "guild", "a JOIN to this guild: passed on inside it only")
					eq(req.level, 12); eq(req.class, "MAGE"); eq(req.text, WORDS, "with his whisper")
					eq(noticed[1], applicant, "The Watch is told, as of every Join screen request")
					eq(scene.printed[#scene.printed], ns.L.JOIN_ASKED_INVITES:format(ns.DisplayName(applicant), 12, ClassName("MAGE"), own))
					local draft = assert(D.Find(DRAFT), "the invite popup opens on its own")
					eq(draft.data.req, req); eq(draft.data.automatic, true)
					assert(draft.text:find(ns.L.RECRUIT_WHISPER_INVITE_COPY:format("New Recruit"), 1, true), draft.text)
					local tag = H.Tag(applicant)
					assert(LogHas("JOIN " .. tag .. " join screen"), "the request in the recruiting log")
					assert(LogHas("POPUP " .. tag .. " auto"), "and its popup")
					local row = assert(Find(R.RequestLines(true), "New Recruit"), "listed in Church > Invites")
					assert(row.text:find(ns.L.LEVEL_N:format(12), 1, true), "with its level, as in the Census")
					assert(Find(R.RequestLines(true), ns.L.RECRUIT_WHISPER_PREPARE_BUTTON), "Prepare invite, as for a JOIN")
					eq(Find(R.RequestLines(false), "New Recruit"), nil, "not in the Census too")
					eq(R.InvitesTaken(), 0)
					draft.def.extra.onClick(draft, draft.data)
					eq(R.InvitesTaken(), 1, "the command taken to chat counts in the minute's ten")
					assert(LogHas("TOCHAT " .. tag .. " 1/10"))
					eq(D.Find(DRAFT), draft, "the popup waits for the paste")
					ACTIVE_CHAT_EDIT_BOX = { GetText = function() return "/ginvite New Recruit" end }
					local later = scene.later
					scene.later = {}
					for _, fn in ipairs(later) do fn() end
					eq(D.Find(DRAFT), nil, "the command pasted in chat closes it")
					LogNever("New Recruit")
				end)
				ChatFrameUtil, ACTIVE_CHAT_EDIT_BOX = savedUtil, savedBox
				if not ok then error(err, 0) end
			end)
		end)
	end)
end)

test("join screen request (1.5.9): with recruiting off a J3 is the Census row it always was", function()
	WithHandoff(function(scene)
		WithLog(function()
			WithWatchNotice(function(noticed)
				local D = Dialogs()
				ns.Dialog = D
				eq(R.ToggleWhisperRecruiting(), false, "recruiting off")
				R.OnWhisper(WORDS, applicant)
				eq(R.OnJoinRequest("WHISPER", applicant, J3), true)
				local req = assert(R.requests[1])
				eq(req.viaWhisper, nil); eq(req.handoffIntent, nil)
				eq(req.text, WORDS)
				eq(D.Find(DRAFT), nil, "no popup")
				eq(noticed[1], applicant)
				eq(scene.printed[#scene.printed], ns.L.JOIN_ASKED:format(ns.DisplayName(applicant), 12, ClassName("MAGE"), own))
				assert(Find(R.RequestLines(false), "New Recruit"), "on top of the Census")
				eq(Find(R.RequestLines(true), "New Recruit"), nil)
				eq(LogHas(H.Tag(applicant)), nil, "not in the recruiting log")
			end)
		end)
	end)
end)

-- Removed referral behavior: replaced by the permanent off regression below.


test("join screen request (1.5.9): Decline still whispers; recruiting off sends a J3 back to the Census unless a member has its name; without the invite right it points to an officer", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		local savedSay, said = SendChatMessage, {}
		SendChatMessage = function(text, kind, _, to) said[#said + 1] = { text = text, kind = kind, to = to } end
		local ok, err = pcall(function()
			ns.Roster.online = { { name = mate, rankIndex = 1 } }
			-- Decline in Church > Invites: one whisper, the Census's.
			eq(R.OnJoinRequest("WHISPER", applicant, J3), true)
			local first = R.requests[1]
			assert(D.Find(DRAFT)):Hide()
			local text = R.DeclineText(first)
			assert(Find(R.RequestLines(true), ns.L.JOIN_DECLINE)).onClick()
			eq(#said, 1); eq(said[1].kind, "WHISPER"); eq(said[1].to, "New Recruit"); eq(said[1].text, text)
			eq(#R.requests, 0, "declined: gone")
			local given, back = "Given Recruit-" .. home, "Back Recruit-" .. home
			scene.now = scene.now + 21 -- (one automatic popup every 20 seconds)
			eq(R.OnJoinRequest("WHISPER", given, J3), true)
			assert(D.Find(DRAFT)):Hide()
			scene.now = scene.now + 21
			eq(R.OnJoinRequest("WHISPER", back, J3), true)
			local req = R.requests[#R.requests]
			eq(req.name, back)
			eq(assert(D.Find(DRAFT)).data.req, req)
			eq(R.ToggleWhisperRecruiting(), false, "recruiting off")
			eq(D.Find(DRAFT), nil, "its popup closes with recruiting")
			eq(#R.requests, 2, "both requests stay local when recruiting stops")
			eq(R.requests[2], req, "the later request stays")
			eq(req.viaWhisper, nil)
			eq(Find(R.RequestLines(true), "Back Recruit"), nil)
			assert(Find(R.RequestLines(false), "Back Recruit"), "back in the Census as it came")
			-- In the Census on Forever: Prepare invite (the command to copy, from the click) and Decline.
			assert(Find(R.RequestLines(false), ns.L.RECRUIT_WHISPER_PREPARE_BUTTON)).onClick()
			local copy = assert(D.Find(DRAFT), "the command to copy")
			eq(copy.data.req, req); eq(copy.data.automatic, nil, "from the officer's click")
			copy:Hide()
			assert(Find(R.RequestLines(false), ns.L.JOIN_DECLINE)).onClick()
			eq(#said, 2); eq(said[2].to, "Back Recruit"); eq(#R.requests, 1)
			R.requests = {}
			-- Without the game's invite right nobody recruits: a J3 is a Census row pointing to an officer.
			scene.permission = false
			local pointed = "Pointed Recruit-" .. home
			eq(R.OnJoinRequest("WHISPER", pointed, J3), true)
			eq(R.requests[1].viaWhisper, nil)
			eq(D.Find(DRAFT), nil)
			assert(Find(R.RequestLines(false), ns.L.JOIN_POINT:format(mate))).onClick()
			eq(#said, 3); eq(said[3].to, "Pointed Recruit"); eq(said[3].text, ns.L.JOIN_POINT_TEXT:format(mate))
		end)
		SendChatMessage = savedSay
		if not ok then error(err, 0) end
	end)
end)

-- Review of 1.5.9: the game's ignore list holds back a player's whispers, not his addon messages, so
-- a JOIN whisper never comes from an ignored player but his J3 still does. Fails before the fix: at
-- a recruiting member it opened the invite popup by itself (and with recruiting off it made a
-- Census row and a chat line), every time the ignored player clicked Send.
test("join screen request (review of 1.5.9): a J3 from a player on the game's ignore list is dropped, recruiting or not", function()
	WithHandoff(function(scene)
		WithLog(function()
			WithWatchNotice(function(noticed)
				local D = Dialogs()
				ns.Dialog = D
				local savedFriends, asked, ignored = C_FriendList, {}, { ["New Recruit"] = true }
				C_FriendList = { IsIgnored = function(name) asked[#asked + 1] = name; return ignored[name] == true end }
				local ok, err = pcall(function()
					-- Recruiting: no request, no popup, no chat line; the recruiting log says why.
					local printed = #scene.printed
					eq(R.OnJoinRequest("WHISPER", applicant, J3), false)
					eq(asked[#asked], "New Recruit", "asked by the name /ignore takes")
					eq(#R.requests, 0, "no request")
					eq(D.Find(DRAFT), nil, "no popup")
					eq(#scene.printed, printed, "no chat line")
					eq(#noticed, 0, "nothing of his reaches this member's screen")
					assert(LogHas("JOINDROP " .. H.Tag(applicant) .. " ignored"), "the recruiting log says why")
					LogNever("New Recruit")
					-- Recruiting off: no Census row and no chat line either.
					eq(R.ToggleWhisperRecruiting(), false, "recruiting off")
					printed = #scene.printed
					eq(R.OnJoinRequest("WHISPER", applicant, J3), false)
					eq(#R.requests, 0, "no Census row")
					eq(#scene.printed, printed, "no chat line")
					-- Off the list, his next request counts at once: the drop held nothing against him.
					ignored["New Recruit"] = nil
					eq(R.OnJoinRequest("WHISPER", applicant, J3), true)
					eq(assert(R.requests[1]).name, applicant)
					assert(Find(R.RequestLines(false), "New Recruit"), "on top of the Census")
				end)
				C_FriendList = savedFriends
				if not ok then error(err, 0) end
			end)
		end)
	end)
end)

-- Review of 1.5.9: a J3 passed on whose offer no member has claimed yet ("offered": nobody has its
-- name) goes back to the Census when recruiting is turned off, and a claim heard after that gets no
-- name. (Before this test, removing "offered" from that rule in StopRecruiting passed every test.)
-- Removed referral behavior: replaced by the permanent off regression below.


-- An unguilded player on the Join Olympus screen: the whispers he sends, his addon whispers outside
-- Olympus and his timers, on a clock the test moves. w.Send() clicks the request window's Send.
local function WithJoinScreen(fn)
	local saved = { guild = GetGuildInfo, inGuild = IsInGuild, level = UnitLevel, class = UnitClass, time = GetTime,
		say = SendChatMessage, outside = ns.Comm.WhisperOutside, dialog = ns.Dialog, after = ns.After, now = ns.Now,
		locked = ns.ChatLocked, quiet = ns.Quiet, reminder = ns.db.joinReminderOff }
	R.ResetForTests()
	local w = { clock = 1000, said = {}, out = {}, timers = {} }
	GetGuildInfo = function() return nil end
	IsInGuild = function() return false end
	UnitLevel = function() return 12 end
	UnitClass = function() return "Mage", "MAGE" end
	GetTime = function() return w.clock end
	ns.Now = function() return w.clock end
	SendChatMessage = function(text, kind, _, to) w.said[#w.said + 1] = { text = text, kind = kind, to = to } end
	ns.Comm.WhisperOutside = function(to, msg) w.out[#w.out + 1] = { to = to, msg = msg } return true end
	ns.Dialog = Dialogs()
	ns.After = function(delay, _, callback) w.timers[#w.timers + 1] = { at = w.clock + (delay or 0), fn = callback } end
	ns.ChatLocked = function() return false end
	ns.Quiet = function() return nil end
	ns.db.joinReminderOff = nil
	function w.Advance(seconds)
		w.clock = w.clock + seconds
		local due = true
		while due do
			due = false
			for i, t in ipairs(w.timers) do
				if t.at <= w.clock then
					table.remove(w.timers, i)
					t.fn()
					due = true
					break
				end
			end
		end
	end
	function w.Send()
		local f = assert(ns.Dialog.Find("OLYMPUS_RECRUIT"), "the request window")
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
	local ok, err = pcall(fn, w)
	R.ResetForTests()
	GetGuildInfo, IsInGuild, UnitLevel, UnitClass, GetTime = saved.guild, saved.inGuild, saved.level, saved.class, saved.time
	SendChatMessage, ns.Comm.WhisperOutside, ns.Dialog, ns.After, ns.Now = saved.say, saved.outside, saved.dialog, saved.after, saved.now
	ns.ChatLocked, ns.Quiet, ns.db.joinReminderOff = saved.locked, saved.quiet, saved.reminder
	if not ok then error(err, 0) end
end

-- 1.5.8's Recruit.lua (tests/fixtures/recruit-1.5.8.lua) as another player's addon: its handlers,
-- listeners and dialogs stay its own, and this build's dialogs are put back.
local function OldRecruit()
	local handlers, dialogs = {}, {}
	for name, d in pairs(StaticPopupDialogs) do dialogs[name] = d end
	local ons = setmetatable({
		Comm = setmetatable({ Handle = function(kind, fn) handlers[kind] = fn end, HandleOutside = function() end }, { __index = ns.Comm }),
		Who = setmetatable({ Listen = function() end }, { __index = ns.Who }),
		On = function() end,
	}, { __index = ns })
	local ok, err = pcall(assert(loadfile(FIXTURES .. "recruit-1.5.8.lua")), "Olympus", ons)
	for name in pairs(StaticPopupDialogs) do StaticPopupDialogs[name] = dialogs[name] end
	if not ok then error(err, 0) end
	return ons.Recruit, handlers
end

test("join screen request (1.5.9): to a member without Olympus the plain whisper goes, and the wait, the timeout and the next member are unchanged", function()
	WithJoinScreen(function(w)
		local L = ns.L
		local function Line(text)
			for _, line in ipairs(ns.Views.JoinLines(400)) do if line.text == text then return line end end
		end
		local function Primary()
			for _, line in ipairs(ns.Views.JoinLines(400)) do if line.primary then return line end end
		end
		R.OnFound({ { name = "Aaa-Realm", guild = own, level = 20, class = "MAGE" }, { name = "Bbb-Realm", guild = own, level = 21, class = "PRIEST" } })
		eq(R.RequestJoin(), true)
		eq(assert(ns.Dialog.Find("OLYMPUS_RECRUIT")).data.name, "Aaa-Realm")
		local text = w.Send()
		eq(#w.said, 1, "one whisper, from Send")
		eq(w.said[1].kind, "WHISPER"); eq(w.said[1].to, "Aaa"); eq(w.said[1].text, text, "the request as the window wrote it")
		local last = w.out[#w.out]
		eq(last.to, "Aaa"); eq(last.msg, J3, "its J3 to the same member, as 1.5.8 sends it")
		for _, o in ipairs(w.out) do assert(o.msg:match("^J[13]~"), "only J1 and J3 leave the Join screen: " .. o.msg) end
		-- A member without Olympus answers neither: the screen waits 45 seconds...
		assert(Line(L.RECRUIT_JOIN_WAITING:format(45)), "waiting for an invite")
		eq(Primary().onClick, nil, "no new request while waiting")
		eq(R.RequestJoin(), false)
		eq(#w.said, 1)
		w.Advance(44)
		assert(Line(L.RECRUIT_JOIN_WAITING:format(1)))
		eq(ns.Dialog.Find("OLYMPUS_RECRUIT_RETRY"), nil)
		-- ...then says no invite came, with its reminder, and Request again asks the next member.
		w.Advance(1)
		assert(Line(L.RECRUIT_JOIN_TIMEOUT), "no invite yet: try another member")
		assert(ns.Dialog.Find("OLYMPUS_RECRUIT_RETRY"), "the reminder")
		local again = Primary()
		eq(again.text, L.RECRUIT_JOIN_AGAIN); eq(again.onClick, R.RequestJoin)
		eq(again.onClick(), true)
		eq(assert(ns.Dialog.Find("OLYMPUS_RECRUIT")).data.name, "Bbb-Realm", "the next member, not the same one")
		w.Send()
		eq(#w.said, 2); eq(w.said[2].to, "Bbb")
		eq(w.out[#w.out].to, "Bbb"); eq(w.out[#w.out].msg, J3)
	end)
end)

test("join screen request (1.5.9): mixed versions: a 1.5.8 member takes this build's J3 as the Census row, a 1.5.9 one pops up a 1.5.8 player's", function()
	local whisper, sent, oldSent
	WithJoinScreen(function(w)
		R.OnFound({ { name = "Aaa-Realm", guild = own, level = 20, class = "MAGE" } })
		eq(R.RequestJoin(), true)
		whisper = w.Send()
		sent = assert(w.out[#w.out]).msg
		-- A 1.5.8 player's request, from 1.5.8's own Send.
		local old = OldRecruit()
		eq(old.Ask({ name = "Ccc-Realm", guild = own }, whisper), true)
		eq(w.said[#w.said].to, "Ccc")
		oldSent = assert(w.out[#w.out]).msg
		eq(oldSent, sent, "1.5.8 and 1.5.9 send the same J3")
	end)
	-- A 1.5.8 member who recruits: the Census row 1.5.8 makes of a J3, never the JOIN's popup.
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		local old, handlers = OldRecruit()
		eq(old.ToggleWhisperRecruiting(), true, "the 1.5.8 member recruits too")
		old.OnWhisper(whisper, applicant)
		eq(assert(handlers.J3)("WHISPER", applicant, sent), true)
		local req = assert(old.requests[1])
		eq(req.viaWhisper, nil, "a Census request")
		eq(D.Find(DRAFT), nil, "no popup")
		eq(req.text, whisper)
		assert(Find(old.RequestLines(false), "New Recruit"), "on top of the Census")
		eq(scene.printed[#scene.printed], ns.L.JOIN_ASKED:format(ns.DisplayName(applicant), 12, ClassName("MAGE"), own))
		-- This build's member, recruiting: the 1.5.8 player's J3 pops up as a JOIN.
		R.OnWhisper(whisper, applicant)
		eq(R.OnJoinRequest("WHISPER", applicant, oldSent), true)
		local draft = assert(D.Find(DRAFT), "the JOIN's popup")
		eq(draft.data.req.name, applicant)
	end)
end)

-- The former opt-in referral tests are replaced by the permanent off contract.
test("recruit referrals removed: saved switches, direct calls and legacy packets cannot send", function()
	WithHandoff(function(scene)
		local saved = { guild = own, acceptHandoffs = true, offerOverflow = true }
		H.Restore(saved)
		eq(saved.acceptHandoffs, nil); eq(saved.offerOverflow, nil)
		eq(H.SetAccepting(true), false); eq(H.SetAuto(true), false)
		eq(H.Accepting(), false); eq(H.AutoOn(), false)
		eq(H.Offer({name=applicant}, mate, own), false)
		for _, op in ipairs({"P", "V", "O", "C", "N", "A"}) do
			eq(H.Receive("WHISPER", mate, "J4~" .. op .. "~1~5090~ForeverPvE~Alliance~Olympus Prime~Olympus Prime~New Recruit"), false)
		end
		local lines = {}; H.Controls(lines, ns.Views); H.RequestLines(lines, ns.Views, {name=applicant})
		eq(#lines, 0); eq(#scene.packets, 0)
		eq(scene.timers["recruit overflow"], nil)
		eq(StaticPopupDialogs["OLYMPUS_RECRUIT_INVITE_DRAFT"].button2, nil)
	end)
end)
