-- 1.6.0: recruiting handoffs on both factions, as members play them. A Horde recruiter's report
-- (14 November, on 1.5.9): many handoff lines arrived "and then nothing happens", so the player's name
-- was typed by hand, which fails for names with special letters. On the Alliance the author's own test
-- went through (offer, claim, name, invite command).
--
-- What was found: nothing in the handoffs reads the faction but the packet's own field, and accented
-- Forever names go through whole (the first tests below, both factions). What failed is what a busy
-- member's game does: the member who passed the player was fighting when the claim came (refused); the
-- claimer's screen held another recruiting popup (he still said yes to the probe, and the offer was a
-- chat line and nothing more); an ad's draft or a scan's whisper review was up when the claimed name
-- came (printed, and no command opened: the name typed by hand).
--
-- Each member here is his own copy of Recruit.lua and RecruitHandoff.lua (this build's, or 1.5.9's from
-- tests/fixtures), with his own faction, popups, timers, log and combat, whispering the others through
-- one in-memory transport that checks each packet's guard when it leaves, as Comm's queue does.
-- Names are Forever's: "First Surname-<sub-realm>", accented letters included.
local ns, test, eq = ...
local L = ns.L
local home = "CAMWOWUS2Realm1PvE"
local own = "Olympus Ironhide"
local DRAFT, CLAIM = "OLYMPUS_RECRUIT_INVITE_DRAFT", "OLYMPUS_RECRUIT_HANDOFF_CLAIM"
local AD, SCAN = "OLYMPUS_RECRUIT_ANNOUNCEMENT", "OLYMPUS_RECRUIT_OUTREACH"
local addonDir = debug.getinfo(1, "S").source:match("^@(.-)tests/[^/]*$") or ""
local FIXTURES = addonDir .. "tests/fixtures/"

local function Full(short) return short .. "-" .. home end

-- Olympus's dialogs as one member sees them: shown, found, closed. The invite popup runs its OnShow,
-- and its edit box keeps the command written there (box.text).
local function Dialogs(defs)
	local shown, D = {}, {}
	function D.Find(which, data)
		for i = #shown, 1, -1 do
			local f = shown[i]
			if f.which == which and f.open and (data == nil or f.data == data) then return f end
		end
	end
	function D.Show(which, a, _, data)
		local old = D.Find(which)
		if old then old.open = false end -- (Dialog.Show: the same one up already gives its place)
		local def = defs[which] or StaticPopupDialogs[which]
		local f = { which = which, text = a, data = data, open = true, def = def }
		f.Hide = function() f.open = false end
		f.IsShown = function() return f.open end
		local box = { text = "" }
		function box.SetText(self, t) self.text = t end
		function box.GetText(self) return self.text end
		function box.SetScript() end
		function box.HighlightText() end
		function box.SetFocus() end
		function box.HasFocus() return false end
		f.editBox = box
		shown[#shown + 1] = f
		if which == DRAFT and def and def.OnShow then def.OnShow(f, data) end
		return f
	end
	function D.Hide(which) local f = D.Find(which); if f then f.open = false end end
	function D.CloseOnEscape() end
	return D
end

-- The world: one guild, its roster, the clock, and each member's own combat, dungeon and keyboard
-- focus (the game's functions answer for the member whose code runs: world.current).
local function WithWorld(fn)
	local saved = {
		guild = GetGuildInfo, invite = CanGuildInvite, member = ns.IsMember, now = ns.Now,
		faction = ns.faction, group = ns.group, realm = ns.realm, splitNames = ns.splitNames, me = ns.me,
		fresh = ns.Roster.Fresh, rank = ns.Roster.RankOf, online = ns.Roster.online, count = GetNumGuildMembers,
		unitExists = UnitExists, util = ChatFrameUtil, combat = rawget(_G, "InCombatLockdown"), instance = IsInInstance,
		focus = rawget(_G, "GetCurrentKeyBoardFocus"), locked = ns.ChatLocked, quiet = ns.QuietPresence,
		random = math.random,
	}
	local world = { now = 50000, queue = {}, byName = {}, clients = {}, sent = {}, ranks = {} }
	GetGuildInfo = function() return own end
	CanGuildInvite = function() return true end
	GetNumGuildMembers = function() return 400, 120 end
	ns.IsMember = function() return true end
	ns.Now = function() return world.now end
	ns.group, ns.realm, ns.splitNames = "ForeverPvE", home, true
	ns.Roster.Fresh = function() return ns.Roster end
	ns.Roster.RankOf = function(name) return world.ranks[ns.FullName(name)] end
	ns.Roster.online = {}
	UnitExists = function() return false end
	ChatFrameUtil = { OpenChat = function() end }
	InCombatLockdown = function() local c = world.current; return c ~= nil and c.combat == true end
	IsInInstance = function() local c = world.current; return c ~= nil and c.instance == true end
	GetCurrentKeyBoardFocus = function() local c = world.current; return c and c.focus or nil end
	ns.ChatLocked = function() return false end
	ns.QuietPresence = function() return false end
	-- (Offer ids draw a random part: the same run each time.)
	local seed = 7
	math.random = function(a, b)
		seed = (seed * 1103515245 + 12345) % 2147483648
		if not a then return seed / 2147483648 end
		return a + seed % ((b or a) - a + 1)
	end
	local ok, err = pcall(fn, world)
	GetGuildInfo, CanGuildInvite, ns.IsMember, ns.Now = saved.guild, saved.invite, saved.member, saved.now
	ns.faction, ns.group, ns.realm, ns.splitNames, ns.me = saved.faction, saved.group, saved.realm, saved.splitNames, saved.me
	ns.Roster.Fresh, ns.Roster.RankOf, ns.Roster.online, GetNumGuildMembers = saved.fresh, saved.rank, saved.online, saved.count
	UnitExists, ChatFrameUtil, InCombatLockdown, IsInInstance = saved.unitExists, saved.util, saved.combat, saved.instance
	GetCurrentKeyBoardFocus, ns.ChatLocked, ns.QuietPresence, math.random = saved.focus, saved.locked, saved.quiet, saved.random
	if not ok then error(err, 0) end
end

-- Runs fn as member c: the game's functions answer for him.
local function As(world, c, fn, ...)
	local before = world.current
	world.current = c
	local r = { pcall(fn, ...) }
	world.current = before
	if not r[1] then error(r[2], 0) end
	return unpack(r, 2)
end

-- A member: this build's files, or 1.5.9's (`version` "1.5.9"), on `faction`, in the guild's roster,
-- recruiting; `scan`: with this build's scan of unguilded players too (RecruitCandidates.lua).
local function Member(world, short, faction, version, rank, scan)
	local c = { name = Full(short), short = short, faction = faction, version = version or "1.6.0",
		later = {}, timers = {}, printed = {}, defs = {} }
	local cns = setmetatable({}, { __index = ns })
	cns.me, cns.faction, cns.db, cns.rdb = c.name, faction, { log = {}, errors = {} }, {}
	cns.Comm = setmetatable({
		Handle = function() end, HandleOutside = function() end, WhisperOutside = function() return true end,
		Whisper = function(peer, word, _, urgent, logged, done, options)
			eq(logged, false, "handoff packets do not go to the chat log")
			world.queue[#world.queue + 1] = { from = c, peer = peer, word = word, done = done,
				guard = options and options.guard, urgent = urgent, at = world.now }
			return true
		end,
	}, { __index = ns.Comm })
	cns.On, cns.RegisterEvent = function() end, function() end
	cns.Print = function(msg) c.printed[#c.printed + 1] = tostring(msg) end
	cns.After = function(delay, _, f) c.later[#c.later + 1] = { due = world.now + (tonumber(delay) or 0), fn = f } end
	cns.Every = function(every, label, f)
		local timer = { every = every, next = world.now + every, fn = f }
		timer.Cancel = function() if c.timers[label] == timer then c.timers[label] = nil end end
		c.timers[label] = timer
		return timer
	end
	cns.Dialog = Dialogs(c.defs)
	c.D = cns.Dialog
	local before = {}
	for k, v in pairs(StaticPopupDialogs) do before[k] = v end
	if c.version == "1.5.9" then
		assert(loadfile(FIXTURES .. "recruit-1.5.9.lua"))("Olympus", cns)
		assert(loadfile(FIXTURES .. "recruit-handoff-1.5.9.lua"))("Olympus", cns)
	else
		assert(loadfile(addonDir .. "Olympus/Recruit.lua"))("Olympus", cns)
		assert(loadfile(addonDir .. "Olympus/RecruitHandoff.lua"))("Olympus", cns)
		if scan then assert(loadfile(addonDir .. "Olympus/RecruitCandidates.lua"))("Olympus", cns) end
	end
	for k, v in pairs(StaticPopupDialogs) do if before[k] ~= v then c.defs[k] = v end end
	for k in pairs(c.defs) do StaticPopupDialogs[k] = before[k] end
	c.ns, c.R, c.H = cns, cns.Recruit, cns.Recruit.Handoff
	world.byName[c.name] = c
	world.clients[#world.clients + 1] = c
	world.ranks[c.name] = rank or 3
	ns.Roster.online[#ns.Roster.online + 1] = { name = c.name }
	As(world, c, function() eq(c.R.ToggleWhisperRecruiting(), true, short .. " recruits") end)
	return c
end

local function Accepting(world, c)
	As(world, c, function() eq(c.H.Toggle(), true, c.short .. " accepts handoffs") end)
end

-- One packet at a time, in order. world.beforeSend(p) runs first (a test changes the sender's game
-- there); a guard that refuses at the send drops the packet, as Comm's queue does.
local function Deliver(world)
	local n = 0
	while #world.queue > 0 do
		n = n + 1
		assert(n < 5000, "the packets settle")
		local p = table.remove(world.queue, 1)
		p.op = p.word:match("^J4~(%u)~")
		if world.beforeSend then world.beforeSend(p) end
		local ok, why = true, nil
		if p.guard then ok, why = As(world, p.from, p.guard) end
		if p.done then As(world, p.from, p.done, ok and true or false, not ok and why or nil) end
		local to = world.byName[p.peer]
		world.sent[#world.sent + 1] = { from = p.from, to = to, op = p.op, word = p.word, at = world.now, dropped = not ok }
		if ok and to then As(world, to, to.H.Receive, "WHISPER", p.from.name, p.word) end
	end
end

-- A second of the world: each member's due callbacks and timers, then the packets.
local function Tick(world)
	world.now = world.now + 1
	for _, c in ipairs(world.clients) do
		As(world, c, function()
			local due = c.later
			c.later = {}
			for _, item in ipairs(due) do
				if item.due <= world.now then item.fn() else c.later[#c.later + 1] = item end
			end
			local timers = {}
			for _, timer in pairs(c.timers) do timers[#timers + 1] = timer end
			for _, timer in ipairs(timers) do
				if timer.next <= world.now then
					timer.next = world.now + timer.every
					timer.fn()
				end
			end
		end)
	end
	Deliver(world)
end
local function Run(world, seconds, each)
	for _ = 1, seconds do
		Tick(world)
		if each and each() then return true end
	end
	return false
end

-- A JOIN whispered to `c`: his invite popup opens, and he passes it to the members who take handoffs.
local function JoinAndPass(world, c, applicant)
	As(world, c, function()
		c.R.OnWhisper("JOIN", applicant)
		local draft = assert(c.D.Find(DRAFT), c.short .. ": the JOIN's popup")
		eq(draft.data.req.name, applicant)
		draft.def.OnButton2(draft, draft.data)
		draft:Hide()
	end)
end

-- The member answers the claim question on his screen: Claim. Returns whether there was one.
local function ClaimShown(world, c)
	local ask = c.D.Find(CLAIM)
	if not ask then return false end
	As(world, c, function()
		ask:Hide()
		ask.def.OnAccept(ask, ask.data)
	end)
	return true
end

-- The invite popup for `applicant` on c's screen, and the command its edit box holds.
local function InviteFor(c, applicant)
	local draft = c.D.Find(DRAFT)
	if draft and draft.data and draft.data.req and draft.data.req.name == applicant then
		return draft, draft.editBox.text
	end
end

-- The J4 packets that went (not dropped at the send), by op, to `to`, from `from`.
local function Count(world, op, to, from)
	local n = 0
	for _, p in ipairs(world.sent) do
		if p.op == op and not p.dropped and (to == nil or p.to == to) and (from == nil or p.from == from) then n = n + 1 end
	end
	return n
end

local function Printed(c, text)
	for _, line in ipairs(c.printed) do if line:find(text, 1, true) then return line end end
end

local function Arrived(origin)
	return L.RECRUIT_HANDOFF_ARRIVED:format(origin.short, own)
end

-------------------------------------------------------------------------------------------------
-- The flow on each faction, accented names included: the claim question, the name, and the invite
-- command naming the player as the server finds him. (This passed before 1.6.0's fixes too: the
-- faction is in every packet, and each member reads his own.)
-------------------------------------------------------------------------------------------------
for _, faction in ipairs({ "Alliance", "Horde" }) do
	test("recruit handoff sides (1.6.0): on the " .. faction .. " a passed JOIN reaches the member who claims it, accented name and all", function()
		WithWorld(function(world)
			local origin = Member(world, "Ashen Vale", faction)
			local master = Member(world, "Brann Holt", faction, nil, 0)
			Accepting(world, master)
			-- (The third plays on another sub-realm of the family: the command names him plainly, ns.TellName.)
			for i, applicant in ipairs({ Full("Zoë Fírè"), Full("Plain Walker"), "Ærin Ødegård-CAMWOWUS1Realm5PvE" }) do
				JoinAndPass(world, origin, applicant)
				local asked = Run(world, 40, function() return ClaimShown(world, master) end)
				assert(asked, faction .. ": the claim question for " .. applicant)
				Run(world, 2)
				local draft, command = InviteFor(master, applicant)
				assert(draft, faction .. ": the invite popup for " .. applicant)
				eq(command, "/ginvite " .. ns.ShortName(applicant), "the command names him as the server finds him")
				eq(Count(world, "N", master), i)
				As(world, master, function() draft.def.extra.onClick(draft, draft.data) end)
				draft:Hide()
				Run(world, 25) -- (the next popup after the cooldown between automatic popups)
			end
			-- An Alliance packet never reaches into a Horde member's handoffs, nor the other way round.
			local stranger = Member(world, "Cael Stone", faction == "Horde" and "Alliance" or "Horde")
			Accepting(world, stranger)
			local word = ("J4~O~%d-1a2b-1~%d~ForeverPvE~%s~%s~%s~"):format(world.now, world.now + 90, faction, own, own)
			eq(As(world, stranger, stranger.H.Receive, "WHISPER", origin.name, word), false, "an offer from the other faction is refused")
			eq(stranger.D.Find(CLAIM), nil)
		end)
	end)
end

-------------------------------------------------------------------------------------------------
-- The member who passed the player is fighting.
-------------------------------------------------------------------------------------------------
test("recruit handoff sides (1.6.0, regression): a claim that comes while the member who passed the player fights still gets the name", function()
	WithWorld(function(world)
		local origin = Member(world, "Ashen Vale", "Horde")
		local master = Member(world, "Brann Holt", "Horde", nil, 0)
		Accepting(world, master)
		local applicant = Full("Zoë Fírè")
		JoinAndPass(world, origin, applicant)
		assert(Run(world, 30, function() return master.D.Find(CLAIM) ~= nil end), "the claim question")
		origin.combat = true
		assert(ClaimShown(world, master))
		Run(world, 3)
		eq(Count(world, "N", master), 1, "the name goes in combat: one addon whisper, which a fight does not stop")
		local draft, command = InviteFor(master, applicant)
		assert(draft, "and the claimer's invite command opens")
		eq(command, "/ginvite Zoë Fírè")
		eq(origin.H.State(origin.R.requests[1]), "assigned", "the member who passed him knows it was taken")
	end)
end)

test("recruit handoff sides (1.6.0, regression): a name waiting to leave when its sender starts a fight still goes", function()
	WithWorld(function(world)
		local origin = Member(world, "Ashen Vale", "Horde")
		local master = Member(world, "Brann Holt", "Horde", nil, 0)
		Accepting(world, master)
		local applicant = Full("Plain Walker")
		JoinAndPass(world, origin, applicant)
		world.beforeSend = function(p) if p.op == "N" then origin.combat = true end end
		assert(Run(world, 30, function() return ClaimShown(world, master) end))
		Run(world, 3)
		eq(Count(world, "N", master), 1, "the name was not dropped at the send")
		assert(InviteFor(master, applicant), "the invite command")
	end)
end)

test("recruit handoff sides (1.6.0, regression): a scanned player passed by hand reaches the member who claims him while the passer fights", function()
	WithWorld(function(world)
		local origin = Member(world, "Ashen Vale", "Horde", nil, nil, true)
		local master = Member(world, "Brann Holt", "Horde", nil, 0)
		Accepting(world, master)
		local found = Full("Zoë Fírè")
		As(world, origin, function()
			local switch
			for _, line in ipairs(origin.R.WhisperLines()) do
				if line.text and line.text:find(L.RECRUIT_CANDIDATES_OFF, 1, true) then switch = line end
			end
			assert(switch, "the scan's switch").onClick()
			assert(origin.R.Candidates.Enabled(), "the scan is on")
			origin.R.Candidates.ObserveWho(found, "", "Orc")
			origin.timers["recruit candidates"].fn()
			local draft = assert(origin.D.Find(DRAFT), "the scan pops his invite command")
			assert(draft.data.candidate, "a scanned player's")
			draft.def.OnButton2(draft, draft.data)
			draft:Hide()
		end)
		assert(Run(world, 30, function() return master.D.Find(CLAIM) ~= nil end), "the claim question")
		eq(master.D.Find(CLAIM).text, L.RECRUIT_HANDOFF_CLAIM_PROMPT_SCAN:format(origin.short, own), "a sighting's")
		origin.combat = true
		assert(ClaimShown(world, master))
		Run(world, 3)
		eq(Count(world, "N", master), 1, "the name goes while he fights")
		local draft, command = InviteFor(master, found)
		assert(draft, "the claimer's command")
		eq(command, "/ginvite Zoë Fírè")
		-- (Failure case) Quiet presence still holds a sighting's name too.
		As(world, master, function() draft.def.extra.onClick(draft, draft.data) end)
		draft:Hide()
		origin.combat = false
		local quiet = Full("Quiet Find")
		As(world, origin, function() origin.R.Candidates.ObserveWho(quiet, "", "Orc") end)
		assert(Run(world, 30, function()
			local f = origin.D.Find(DRAFT)
			return f ~= nil and f.data.candidate ~= nil and f.data.candidate.full == quiet
		end), "the next one's command")
		As(world, origin, function()
			local f = origin.D.Find(DRAFT)
			f.def.OnButton2(f, f.data)
			f:Hide()
		end)
		assert(Run(world, 40, function() return master.D.Find(CLAIM) ~= nil end), "the next claim question")
		origin.ns.QuietPresence = function() return true end
		assert(ClaimShown(world, master))
		Run(world, 3)
		eq(Count(world, "N", master), 1, "no name in quiet presence")
	end)
end)

-- (Failure cases: what still holds the claim.)
test("recruit handoff sides (1.6.0): a chat lockdown or quiet presence at the member who passed the player still holds the name, and the claimer is told when the offer ends", function()
	for _, hold in ipairs({ "ChatLocked", "QuietPresence" }) do
		WithWorld(function(world)
			local origin = Member(world, "Ashen Vale", "Horde")
			local master = Member(world, "Brann Holt", "Horde", nil, 0)
			Accepting(world, master)
			JoinAndPass(world, origin, Full("Plain Walker"))
			assert(Run(world, 30, function() return master.D.Find(CLAIM) ~= nil end))
			origin.ns[hold] = function() return true end
			assert(ClaimShown(world, master))
			Run(world, 3)
			eq(Count(world, "N", master), 0, hold .. ": no name")
			eq(Printed(master, L.RECRUIT_HANDOFF_NO_NAME:format(origin.short)), nil, "not before the offer ends")
			Run(world, 95)
			assert(Printed(master, L.RECRUIT_HANDOFF_NO_NAME:format(origin.short)), hold .. ": the claimer reads that no name came")
		end)
	end
end)

-------------------------------------------------------------------------------------------------
-- The claimer's screen cannot show the claim question.
-------------------------------------------------------------------------------------------------
local BLOCKERS = {
	{ "with his own JOIN's invite popup waiting for its paste", function(world, c)
		As(world, c, function() c.R.OnWhisper("JOIN", Full("Own Walker")) end)
		assert(c.D.Find(DRAFT))
	end },
	{ "with an ad's draft up", function(_, c) c.D.Show(AD, "General", nil, { reminder = true }) end },
	{ "with a scanned player's whisper review up", function(_, c) c.D.Show(SCAN, "Whisper", nil, {}) end },
	{ "typing in chat", function(_, c) c.focus = { name = "ChatFrame1EditBox" } end },
	{ "in a dungeon", function(_, c) c.instance = true end },
}
for _, blocker in ipairs(BLOCKERS) do
	test("recruit handoff sides (1.6.0, regression): a member " .. blocker[1] .. " says no to the probe, and the player goes to one who can claim", function()
		WithWorld(function(world)
			local origin = Member(world, "Ashen Vale", "Horde")
			local master = Member(world, "Brann Holt", "Horde", nil, 0)
			local free = Member(world, "Cora Wynd", "Horde")
			Accepting(world, master)
			Accepting(world, free)
			blocker[2](world, master)
			local applicant = Full("Zoë Fírè")
			local start = world.now
			JoinAndPass(world, origin, applicant)
			local reached = Run(world, 150, function()
				ClaimShown(world, master)
				ClaimShown(world, free)
				return InviteFor(free, applicant) ~= nil
			end)
			assert(reached, "the player reached a member who could claim him")
			assert(world.now - start <= 20, "within seconds, not after an offer's 90: " .. (world.now - start))
			eq(Count(world, "V", origin, master), 0, "the busy member did not say he was available")
			assert(Count(world, "D", origin, master) >= 1, "he said no at once")
			eq(Count(world, "O", master), 0, "no offer he could not answer")
			eq(Printed(master, Arrived(origin)), nil, "and no chat line about one")
		end)
	end)
end

test("recruit handoff sides (1.6.0, regression): an offer that came while the claimer typed is asked once he stops; its question closes when the offer ends", function()
	WithWorld(function(world)
		local origin = Member(world, "Ashen Vale", "Horde")
		local master = Member(world, "Brann Holt", "Horde", nil, 0)
		Accepting(world, master)
		local applicant = Full("Zoë Fírè")
		JoinAndPass(world, origin, applicant)
		-- Free when the probe came; typing when the offer comes.
		assert(Run(world, 20, function() return Count(world, "V", origin, master) > 0 end), "available at the probe")
		master.focus = { name = "ChatFrame1EditBox" }
		assert(Run(world, 20, function() return Count(world, "O", master) > 0 end), "the offer")
		assert(Printed(master, Arrived(origin)), "its chat line")
		Run(world, 10)
		eq(master.D.Find(CLAIM), nil, "no question while he types")
		master.focus = nil
		assert(Run(world, (master.H.ASK_RETRY or 2) + 1, function() return master.D.Find(CLAIM) ~= nil end), "asked once he stopped")
		assert(ClaimShown(world, master))
		Run(world, 3)
		local draft = InviteFor(master, applicant)
		assert(draft, "his claim brought the name and the command")
		As(world, master, function() draft.def.extra.onClick(draft, draft.data) end)
		draft:Hide()

		-- A question he leaves unanswered closes with its offer: a Claim after it would do nothing.
		JoinAndPass(world, origin, Full("Late Walker"))
		assert(Run(world, 40, function() return master.D.Find(CLAIM) ~= nil end), "the next question")
		local ask = master.D.Find(CLAIM)
		local ends = ask.data.expires
		Run(world, ends - world.now - 1)
		assert(ask:IsShown(), "up while the offer lasts")
		Run(world, 2)
		eq(ask:IsShown(), false, "closed when the offer ended")
	end)
end)

-------------------------------------------------------------------------------------------------
-- The claimed name came: the command opens.
-------------------------------------------------------------------------------------------------
test("recruit handoff sides (1.6.0, regression): a claimed player's command opens even if an ad's draft came up before his name", function()
	WithWorld(function(world)
		local origin = Member(world, "Ashen Vale", "Horde")
		local master = Member(world, "Brann Holt", "Horde", nil, 0)
		Accepting(world, master)
		local applicant = Full("Zoë Fírè")
		JoinAndPass(world, origin, applicant)
		world.beforeSend = function(p) if p.op == "N" and not master.D.Find(AD) then master.D.Show(AD, "General", nil, { reminder = true }) end end
		assert(Run(world, 30, function() return ClaimShown(world, master) end))
		Run(world, 3)
		assert(master.D.Find(AD), "the ad's draft is up")
		local draft, command = InviteFor(master, applicant)
		assert(draft, "the claimed player's command opened over it")
		eq(command, "/ginvite Zoë Fírè")
		assert(Printed(master, "Zoë Fírè: " .. L.RECRUIT_HANDOFF_RECEIVED:format(origin.short)), "the line names the handoff")
		eq(Printed(master, L.RECRUIT_WHISPER_ASKED:format("Zoë Fírè", own)), nil, "not a recruiting reply to open in Invites")
		-- (Failure case) His own JOIN still waits for the ad's draft.
		As(world, master, function() draft.def.extra.onClick(draft, draft.data) end)
		draft:Hide()
		As(world, master, function() master.R.OnWhisper("JOIN", Full("Own Walker")) end)
		Run(world, 30)
		eq(InviteFor(master, Full("Own Walker")), nil, "a JOIN of his own does not open over the ad's draft")
		master.D.Hide(AD)
		assert(Run(world, 3, function() return InviteFor(master, Full("Own Walker")) ~= nil end), "it opens once the ad's draft closes")
	end)
end)

test("recruit handoff sides (1.6.0): his own JOINs still open after an ad's draft closes when the claimed player they waited behind joined meanwhile", function()
	WithWorld(function(world)
		local origin = Member(world, "Ashen Vale", "Horde")
		local master = Member(world, "Brann Holt", "Horde", nil, 0)
		Accepting(world, master)
		-- His own JOIN pops up and goes to chat; the next one waits for the pause between popups.
		As(world, master, function()
			master.R.OnWhisper("JOIN", Full("First Walker"))
			local first = assert(master.D.Find(DRAFT))
			first.def.extra.onClick(first, first.data)
			first:Hide()
			master.R.OnWhisper("JOIN", Full("Second Walker"))
		end)
		local applicant = Full("Zoë Fírè")
		JoinAndPass(world, origin, applicant)
		assert(Run(world, 15, function() return ClaimShown(world, master) end))
		Run(world, 2)
		eq(master.D.Find(DRAFT), nil, "the pause holds both")
		master.D.Show(AD, "General", nil, { reminder = true })
		world.ranks[applicant] = 3 -- (another member invited him meanwhile)
		Run(world, 25)
		eq(master.D.Find(DRAFT), nil, "nothing over the ad's draft")
		master.D.Hide(AD)
		assert(Run(world, 3, function() return InviteFor(master, Full("Second Walker")) ~= nil end), "his own JOIN once it closed")
	end)
end)

test("recruit handoff sides (1.6.0, regression): a claimed player's command comes before older JOINs still waiting", function()
	WithWorld(function(world)
		local origin = Member(world, "Ashen Vale", "Horde")
		local master = Member(world, "Brann Holt", "Horde", nil, 0)
		Accepting(world, master)
		-- His own JOIN pops up and goes to chat; two more arrive during the pause between popups.
		As(world, master, function()
			master.R.OnWhisper("JOIN", Full("First Walker"))
			local first = assert(master.D.Find(DRAFT))
			first.def.extra.onClick(first, first.data)
			first:Hide()
			master.R.OnWhisper("JOIN", Full("Second Walker"))
			master.R.OnWhisper("JOIN", Full("Third Walker"))
		end)
		eq(master.D.Find(DRAFT), nil, "the two wait for the pause")
		local applicant = Full("Zoë Fírè")
		JoinAndPass(world, origin, applicant)
		assert(Run(world, 15, function() return ClaimShown(world, master) end), "he claims meanwhile")
		assert(Run(world, 30, function() return master.D.Find(DRAFT) ~= nil end))
		assert(InviteFor(master, applicant), "the player he claimed first: " .. tostring(master.D.Find(DRAFT).data.req.name))
	end)
end)

-------------------------------------------------------------------------------------------------
-- Mixed versions: 1.5.9 members next to 1.6.0 ones.
-------------------------------------------------------------------------------------------------
test("recruit handoff sides (1.6.0, mixed versions): a 1.5.9 member's offers skip a busy 1.6.0 member at once", function()
	WithWorld(function(world)
		local origin = Member(world, "Ashen Vale", "Horde", "1.5.9")
		local master = Member(world, "Brann Holt", "Horde", nil, 0)
		local free = Member(world, "Cora Wynd", "Horde")
		Accepting(world, master)
		Accepting(world, free)
		BLOCKERS[1][2](world, master)
		local applicant = Full("Zoë Fírè")
		local start = world.now
		JoinAndPass(world, origin, applicant)
		assert(Run(world, 150, function()
			ClaimShown(world, master)
			ClaimShown(world, free)
			return InviteFor(free, applicant) ~= nil
		end), "the player reached the free member")
		assert(world.now - start <= 20, "a 1.5.9 member reads the no and asks the next one: " .. (world.now - start))
		eq(Count(world, "O", master), 0)
	end)
end)

test("recruit handoff sides (1.6.0, mixed versions): a 1.6.0 member in combat answers a 1.5.9 member's claim; a 1.5.9 one in combat still does not, and the 1.6.0 claimer is told", function()
	WithWorld(function(world)
		local origin = Member(world, "Ashen Vale", "Horde")
		local oldMaster = Member(world, "Brann Holt", "Horde", "1.5.9", 0)
		Accepting(world, oldMaster)
		JoinAndPass(world, origin, Full("Plain Walker"))
		assert(Run(world, 30, function() return oldMaster.D.Find(CLAIM) ~= nil end))
		origin.combat = true
		assert(ClaimShown(world, oldMaster))
		Run(world, 25)
		eq(Count(world, "N", oldMaster), 1, "the 1.6.0 member sends the name in combat")
		assert(InviteFor(oldMaster, Full("Plain Walker")), "the 1.5.9 claimer's command opens")
	end)
	WithWorld(function(world)
		local oldOrigin = Member(world, "Ashen Vale", "Horde", "1.5.9")
		local master = Member(world, "Brann Holt", "Horde", nil, 0)
		Accepting(world, master)
		JoinAndPass(world, oldOrigin, Full("Plain Walker"))
		assert(Run(world, 30, function() return master.D.Find(CLAIM) ~= nil end))
		oldOrigin.combat = true
		assert(ClaimShown(world, master))
		Run(world, 95)
		eq(Count(world, "N", master), 0, "a 1.5.9 member in combat still refuses the claim")
		assert(Printed(master, L.RECRUIT_HANDOFF_NO_NAME:format(oldOrigin.short)), "the 1.6.0 claimer reads that no name came")
	end)
end)

-------------------------------------------------------------------------------------------------
-- A guild's half hour, as the report describes it: four members pass the JOINs they cannot take in
-- time (two on 1.5.9, two on this build), each fighting 25 seconds of every minute; three members take
-- handoffs: the guild master (this build), whose ad's draft is up 90 seconds of every five minutes before
-- he closes it, a member who types 10 seconds of every 45 (this build) and one with nothing on screen
-- (1.5.9). Each answers a claim question after 3 seconds and takes an invite command to chat 3 seconds
-- after it opens. 24 JOINs over 20 minutes, the same run on each faction. Counted: the JOINs whose
-- command opened at a member and how long after the Pass; offers a member never got the question for
-- (a chat line, then nothing); claims that got no name, by the passer's version; names whose command did
-- not open within 20 seconds (the longest pause between automatic popups): the name typed by hand.
-------------------------------------------------------------------------------------------------
local function HalfHour(faction)
	local result
	WithWorld(function(world)
		local passers = {
			Member(world, "Ashen Vale", faction), Member(world, "Dorn Ridge", faction),
			Member(world, "Elda Moss", faction, "1.5.9"), Member(world, "Fenn Hollow", faction, "1.5.9"),
		}
		local master = Member(world, "Brann Holt", faction, nil, 0)
		local typist = Member(world, "Cora Wynd", faction)
		local steady = Member(world, "Gale Thorn", faction, "1.5.9")
		local takers = { master, typist, steady }
		for _, c in ipairs(takers) do Accepting(world, c) end
		local start = world.now
		local joins, opened, askedAt, takeAt, asked = {}, {}, {}, {}, 0
		local function Game()
			local t = world.now - start
			for i, p in ipairs(passers) do p.combat = (t + i * 15) % 60 < 25 end
			if t % 300 == 10 then master.D.Show(AD, "General", nil, { reminder = true }) end
			if t % 300 == 100 then master.D.Hide(AD) end
			typist.focus = (t % 45) < 10 and { name = "ChatFrame1EditBox" } or nil
		end
		for second = 1, 1800 do
			Game()
			if second % 50 == 0 and #joins < 24 then
				local applicant = Full(("Recruit %s"):format(("abcdefghijklmnopqrstuvwx"):sub(#joins + 1, #joins + 1)))
				local p = passers[#joins % #passers + 1]
				local fighting = p.combat
				p.combat = false -- (his click on Pass, out of a fight)
				JoinAndPass(world, p, applicant)
				p.combat = fighting
				joins[#joins + 1] = { name = applicant, at = world.now }
			end
			Tick(world)
			for _, c in ipairs(takers) do
				local ask = c.D.Find(CLAIM)
				if ask and not askedAt[ask] then askedAt[ask], asked = world.now, asked + 1 end
				if ask and world.now - askedAt[ask] >= 3 then ClaimShown(world, c) end
				local draft = c.D.Find(DRAFT)
				if draft and draft.data and draft.data.req then
					opened[draft.data.req.name] = opened[draft.data.req.name] or world.now
					takeAt[draft] = takeAt[draft] or world.now
					if world.now - takeAt[draft] >= 3 then
						As(world, c, function() draft.def.extra.onClick(draft, draft.data) end)
						draft:Hide()
					end
				end
			end
		end
		local r = { joins = #joins, opened = 0, waits = {}, late = 0, noName = { ["1.6.0"] = 0, ["1.5.9"] = 0 } }
		for _, j in ipairs(joins) do
			if opened[j.name] then
				r.opened = r.opened + 1
				r.waits[#r.waits + 1] = opened[j.name] - j.at
			end
		end
		table.sort(r.waits)
		r.median, r.worst = r.waits[math.ceil(#r.waits / 2)] or -1, r.waits[#r.waits] or -1
		local offers = 0
		for _, c in ipairs(takers) do offers = offers + Count(world, "O", c) end
		r.unasked = offers - asked
		for _, p in ipairs(passers) do
			r.noName[p.version] = r.noName[p.version] + Count(world, "C", p) - Count(world, "N", nil, p)
		end
		for _, sent in ipairs(world.sent) do
			if sent.op == "N" and not sent.dropped then
				local who = sent.word:match("~([^~]*)$")
				if not opened[who] or opened[who] - sent.at > 20 then r.late = r.late + 1 end
			end
		end
		result = r
	end)
	return result
end

test("recruit handoff sides (1.6.0, simulation): a guild's half hour of passed JOINs, Horde and Alliance alike", function()
	local results = {}
	for _, faction in ipairs({ "Horde", "Alliance" }) do
		local r = HalfHour(faction)
		results[faction] = r
		print(("  %s: %d JOINs passed, commands opened %d (median %ds, worst %ds after the Pass); offers never asked %d;"
			.. " claims with no name %d from 1.6.0 passers, %d from 1.5.9 ones; names with no command within 20s %d"):format(
			faction, r.joins, r.opened, r.median, r.worst, r.unasked, r.noName["1.6.0"], r.noName["1.5.9"], r.late))
	end
	for faction, r in pairs(results) do
		eq(r.opened, r.joins, faction .. ": every passed JOIN's command opened at a member")
		eq(r.unasked, 0, faction .. ": every offer a member got was asked about while it lasted")
		eq(r.noName["1.6.0"], 0, faction .. ": a claim of a 1.6.0 member's player always got the name")
		eq(r.late, 0, faction .. ": every name that came opened its command")
	end
	for _, k in ipairs({ "opened", "median", "worst", "unasked", "late" }) do
		eq(results.Horde[k], results.Alliance[k], "the factions alike: " .. k)
	end
end)

-- 1.6.0's new line (a claim no name answered) in every language the addon has, each its own words, its
-- one %s the member who passed the player.
test("recruit handoff sides (1.6.0): the no-name line in every language", function()
	local english
	for _, code in ipairs({ "enUS", "ptBR", "deDE", "esES", "esMX", "frFR", "itIT", "ruRU" }) do
		local lns, saved = {}, GetLocale
		GetLocale = function() return code end
		local ok, err = pcall(function()
			assert(loadfile(addonDir .. "Olympus/Locales.lua"))("Olympus", lns)
			assert(loadfile(addonDir .. "Olympus/Locales/RecruitHandoffText.lua"))("Olympus", lns)
			for _, file in ipairs({ "deDE", "esES", "frFR", "itIT", "ruRU" }) do
				assert(loadfile(addonDir .. "Olympus/Locales/" .. file .. ".lua"))("Olympus", lns)
			end
		end)
		GetLocale = saved
		if not ok then error(err, 0) end
		local line = rawget(lns.L, "RECRUIT_HANDOFF_NO_NAME")
		assert(type(line) == "string" and line ~= "", code .. ": the line")
		eq(select(2, line:gsub("%%s", "")), 1, code .. ": its one %s")
		eq(lns.LocaleCodes(line), lns.LocaleCodes(english or line), code .. ": the English line's codes")
		if code == "enUS" then english = line else assert(line ~= english, code .. ": its own words") end
	end
end)
