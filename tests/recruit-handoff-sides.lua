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
-- and its edit box keeps the command written there (box.text). (The review of 1.6.0) Each time its box
-- takes the keyboard (SetFocus), f.tookFocus notes the box that held it then (the world's
-- GetCurrentKeyBoardFocus; false: none).
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
		f.tookFocus = {}
		function box.SetFocus() f.tookFocus[#f.tookFocus + 1] = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() or false end
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
	GetGuildInfo = function() return world.current and world.current.guild or own end
	CanGuildInvite = function() return true end
	GetNumGuildMembers = function() return world.current and world.current.capacity or 400, 120 end
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
local function Member(world, short, faction, version, rank, scan, guild)
	local c = { guild = guild or own, name = Full(short), short = short, faction = faction, version = version or "1.6.0",
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
		assert(loadfile(addonDir .. "Olympus/RecruitOverflow.lua"))("Olympus", cns)
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
		p.op = p.word:match("^J[467]~(%u)~")
		if world.beforeSend then world.beforeSend(p) end
		local ok, why = true, nil
		if p.guard then ok, why = As(world, p.from, p.guard) end
		if p.done then As(world, p.from, p.done, ok and true or false, not ok and why or nil) end
		local to = world.byName[p.peer]
		world.sent[#world.sent + 1] = { from = p.from, to = to, op = p.op, word = p.word, at = world.now, dropped = not ok }
		if ok and to then
			local overflow = to.R.VerifiedOverflow
			local receiver = p.word:sub(1, 3) == "J7~" and overflow and overflow.Receive or to.H.Receive
			As(world, to, receiver, "WHISPER", p.from.name, p.word)
		end
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

-- Church > Invites' line `id` as member c sees it.
local function PageLine(world, c, id)
	return As(world, c, function()
		for _, line in ipairs(c.R.WhisperLines()) do if line.id == id then return line end end
	end)
end

-- c's click on Prepare invite under `applicant`'s row in Church > Invites.
local function PrepareFromInvites(world, c, applicant)
	As(world, c, function()
		local row -- (the indent of his row: its actions are the lines below it, further in)
		for _, line in ipairs(c.R.WhisperLines()) do
			local text, indent = type(line.text) == "string" and line.text or "", line.indent or 0
			if row and indent <= row then row = nil end
			if row and line.onClick and text:find(L.RECRUIT_WHISPER_PREPARE_BUTTON, 1, true) then return line.onClick() end
			if not row and text:find(ns.ShortName(applicant), 1, true) then row = indent end
		end
		error("no Prepare invite under " .. applicant .. "'s row", 0)
	end)
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

-- The offer's end, as its packet says it.
local function OfferEnds(world, to)
	for _, p in ipairs(world.sent) do
		if p.op == "O" and p.to == to and not p.dropped then return tonumber(p.word:match("^J4~O~[^~]+~(%d+)~")) end
	end
end

-- (Review of the lane) A claim made on Church > Invites' Claim line, its question never shown (he typed
-- the whole time it could be asked), is told too that no name came: the claim's own timer says it, as
-- no question's runs.
test("recruit handoff sides (1.6.0): a claim made on Church > Invites, its question never shown, is told when no name came", function()
	WithWorld(function(world)
		local origin = Member(world, "Ashen Vale", "Horde")
		local master = Member(world, "Brann Holt", "Horde", nil, 0)
		Accepting(world, master)
		JoinAndPass(world, origin, Full("Plain Walker"))
		assert(Run(world, 20, function() return Count(world, "V", origin, master) > 0 end), "available at the probe")
		master.focus = { name = "ChatFrame1EditBox" } -- (typing from then on: the question cannot show)
		assert(Run(world, 20, function() return Count(world, "O", master) > 0 end), "the offer")
		origin.ns.QuietPresence = function() return true end -- (the member who passed him holds the name)
		local claim
		As(world, master, function()
			local lines = {}
			master.H.Controls(lines, { Green = tostring, Grey = tostring, Gold = tostring }, nil)
			for _, line in ipairs(lines) do
				if line.onClick and line.text and line.text:find(L.RECRUIT_HANDOFF_CLAIM:format(origin.short), 1, true) then claim = line end
			end
		end)
		As(world, master, assert(claim, "the Claim line in Church > Invites").onClick)
		Run(world, 3)
		eq(master.D.Find(CLAIM), nil, "no question was shown")
		eq(Count(world, "N", master), 0, "no name")
		local ends, line = assert(OfferEnds(world, master), "the offer's end"), L.RECRUIT_HANDOFF_NO_NAME:format(origin.short)
		Run(world, ends - world.now - 1)
		eq(Printed(master, line), nil, "not while the offer lasts")
		Run(world, 3)
		assert(Printed(master, line), "the claimer reads that no name came")
	end)
end)

-- (Review of the lane) A name that came is no "no name", even one this client turns down: here the same
-- player whispered this member JOIN himself meanwhile, and his own entry stays the one.
test("recruit handoff sides (1.6.0): a claimed name that comes for a player already in the claimer's queue is no no-name line", function()
	WithWorld(function(world)
		local origin = Member(world, "Ashen Vale", "Horde")
		local master = Member(world, "Brann Holt", "Horde", nil, 0)
		Accepting(world, master)
		local applicant = Full("Plain Walker")
		JoinAndPass(world, origin, applicant)
		-- After his claim, before the name arrives, the same player whispers him JOIN.
		world.beforeSend = function(p)
			if p.op == "N" and #master.R.requests == 0 then As(world, master, function() master.R.OnWhisper("JOIN", applicant) end) end
		end
		assert(Run(world, 30, function() return ClaimShown(world, master) end), "the claim")
		Run(world, 3)
		eq(Count(world, "N", master), 1, "the name came")
		eq(#master.R.requests, 1, "one entry for him")
		eq(master.R.requests[1].handedIn, nil, "his own JOIN's")
		Run(world, 100)
		eq(Printed(master, L.RECRUIT_HANDOFF_NO_NAME:format(origin.short)), nil, "a name came: no no-name line")
	end)
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
	-- (Review of the lane) Church > Invites' interval between automatic popups, set to 5 minutes, and a
	-- popup that just showed.
	{ "inside his interval between automatic popups", function(world, c)
		local gap = assert(PageLine(world, c, "recruit-popup-gap"), "the interval's choice").filters[1]
		local five
		for _, option in ipairs(gap.options) do
			if option.text == L.RECRUIT_ANNOUNCE_REMINDER_ON:format(5) then five = option end
		end
		As(world, c, assert(five, "5 minutes").onClick)
		As(world, c, c.R.PopupShown)
		assert(As(world, c, c.R.PopupWait) > 0, "inside the interval")
	end },
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

-- (Review of the lane) Incoming JOIN set to Queue only opens no command by itself, a claimed player's
-- either: his line names the handoff and where to invite him (1.5.9's line said to open Invites).
test("recruit handoff sides (1.6.0, regression): a claimer whose Incoming JOIN is Queue only reads where to invite the claimed player", function()
	WithWorld(function(world)
		local origin = Member(world, "Ashen Vale", "Horde")
		local master = Member(world, "Brann Holt", "Horde", nil, 0)
		Accepting(world, master)
		local switch = assert(PageLine(world, master, "recruit-whisper-arrival"), "the Incoming JOIN switch")
		assert(switch.text:find(L.RECRUIT_WHISPER_POPUP_ON, 1, true), "Pop-up first")
		As(world, master, switch.onClick)
		assert(PageLine(world, master, "recruit-whisper-arrival").text:find(L.RECRUIT_WHISPER_QUEUE_ONLY, 1, true), "now Queue only")
		local applicant = Full("Zoë Fírè")
		JoinAndPass(world, origin, applicant)
		assert(Run(world, 40, function() return ClaimShown(world, master) end), "he is asked, and claims")
		Run(world, 30)
		eq(Count(world, "N", master), 1, "the name came")
		eq(InviteFor(master, applicant), nil, "Queue only: no command opens by itself")
		local line = assert(Printed(master, "Zoë Fírè: " .. L.RECRUIT_HANDOFF_RECEIVED:format(origin.short)), "the handoff's line")
		assert(L.RECRUIT_HANDOFF_IN_QUEUE, "a line saying where to invite him")
		assert(line:find(L.RECRUIT_HANDOFF_IN_QUEUE, 1, true), "the line says where to invite him: " .. line)
		-- There, his row's Prepare invite opens the command.
		PrepareFromInvites(world, master, applicant)
		local draft, command = InviteFor(master, applicant)
		assert(draft, "Church > Invites opens his command")
		eq(command, "/ginvite Zoë Fírè")
		As(world, master, function() draft.def.extra.onClick(draft, draft.data) end)
		draft:Hide()

		-- (Failure case) Back on Pop-up, the command opens by itself and the line says nothing more.
		As(world, master, PageLine(world, master, "recruit-whisper-arrival").onClick)
		local second = Full("Plain Walker")
		JoinAndPass(world, origin, second)
		assert(Run(world, 40, function() return ClaimShown(world, master) end), "the next claim")
		assert(Run(world, 5, function() return InviteFor(master, second) ~= nil end), "Pop-up: his command opens")
		local plain = assert(Printed(master, "Plain Walker: " .. L.RECRUIT_HANDOFF_RECEIVED:format(origin.short)), "his line")
		eq(plain:find(L.RECRUIT_HANDOFF_IN_QUEUE, 1, true), nil, "no pointer when the command opens: " .. plain)
	end)
end)

-- (Review of the lane) A claimed player's command opens over a scanned player's whisper review; when
-- that review was asked from his invite popup ("Whisper them first"), his popup still comes back.
test("recruit handoff sides (1.6.0, regression): a scanned player's popup still comes back after Whisper them first when a claimed player's command came during the whisper", function()
	WithWorld(function(world)
		local origin = Member(world, "Ashen Vale", "Horde")
		local master = Member(world, "Brann Holt", "Horde", nil, 0, true)
		Accepting(world, master)
		local found = Full("Scan Find")
		As(world, master, function()
			local switch
			for _, line in ipairs(master.R.WhisperLines()) do
				if line.text and line.text:find(L.RECRUIT_CANDIDATES_OFF, 1, true) then switch = line end
			end
			assert(switch, "the scan's switch").onClick()
			master.R.Candidates.ObserveWho(found, "", "Orc")
		end)
		local applicant = Full("Zoë Fírè")
		JoinAndPass(world, origin, applicant)
		assert(Run(world, 40, function() return master.D.Find(CLAIM) ~= nil end), "the claim question")
		-- He claims; while the name is on its way the scan pops its player, and he clicks Whisper them first.
		local review
		world.beforeSend = function(p)
			if p.op ~= "N" or review then return end
			As(world, master, function()
				master.timers["recruit candidates"].fn()
				local draft = assert(master.D.Find(DRAFT), "the scanned player's popup")
				assert(draft.data.candidate, "a scanned player's")
				draft.def.OnAlt(draft, draft.data)
				draft:Hide()
				review = assert(master.D.Find(SCAN), "his whisper review")
			end)
		end
		assert(ClaimShown(world, master))
		Run(world, 3)
		eq(Count(world, "N", master), 1, "the name came during the review")
		-- He closes the review, sent or not (its OnHide), then takes each invite popup that comes to chat.
		As(world, master, function() review:Hide(); review.def.OnHide(review, review.data) end)
		local came = {}
		Run(world, 60, function()
			local f = master.D.Find(DRAFT)
			if f then
				came[f.data.candidate and f.data.candidate.full or f.data.req.name] = true
				As(world, master, function() f.def.extra.onClick(f, f.data) end)
				f:Hide()
			end
			return came[applicant] and came[found]
		end)
		assert(came[applicant], "the claimed player's command opened")
		assert(came[found], "and the scanned player's popup came back after his whisper")
		Run(world, 30)
		eq(master.D.Find(DRAFT), nil, "once each: neither comes back again")
	end)
end)

-- The same without a handoff: his own JOIN waited behind the whisper review, and its next look comes
-- just before the popup is asked back, so the JOIN's popup takes the place first. 76c0c57e and 1.5.9
-- lost the scanned player's popup then (in the game, when the review closed in the frame before that
-- look); it comes back once the JOIN's closes.
test("recruit handoff sides (1.6.0, regression): a scanned player's popup still comes back after Whisper them first when his own JOIN's popup opens as the whisper closes", function()
	WithWorld(function(world)
		local master = Member(world, "Brann Holt", "Horde", nil, 0, true)
		local found, own = Full("Scan Find"), Full("Own Walker")
		As(world, master, function()
			assert(PageLine(world, master, "recruit-candidate-toggle"), "the scan's switch").onClick()
			master.R.Candidates.ObserveWho(found, "", "Orc")
			master.timers["recruit candidates"].fn()
			local draft = assert(master.D.Find(DRAFT), "the scanned player's popup")
			draft.def.OnAlt(draft, draft.data)
			draft:Hide()
		end)
		local review = assert(master.D.Find(SCAN), "his whisper review")
		-- His own JOIN waits behind the review, looked at again every 2 seconds; he closes the review
		-- in the second before the next look.
		As(world, master, function() master.R.OnWhisper("JOIN", own) end)
		Run(world, 3)
		eq(master.D.Find(DRAFT), nil, "the JOIN waits for the review")
		As(world, master, function() review:Hide(); review.def.OnHide(review, review.data) end)
		Run(world, 1)
		local draft = assert(InviteFor(master, own), "the JOIN's popup came first")
		As(world, master, function() draft.def.extra.onClick(draft, draft.data) end)
		draft:Hide()
		assert(Run(world, 5, function()
			local f = master.D.Find(DRAFT)
			return f ~= nil and f.data.candidate ~= nil and f.data.candidate.full == found
		end), "the scanned player's popup came back after the JOIN's")
	end)
end)

-- The review of 1.6.0. While another invite popup was up, the scanned player's popup "Whisper them
-- first" asks back looked again every 2 seconds and then opened as if clicked: it took the keyboard. The
-- claimed player's command (or his own JOIN's) closes as soon as it is pasted in the game's chat box
-- (WatchPaste), Enter not pressed yet: the scanned player's popup took the keyboard from the chat box within
-- 2 seconds, Enter went to it, and the pasted /ginvite was never sent (the claimed player counted as taken
-- to chat: his command never opened again). It waits while the player types (Recruit.PopupsWait), and
-- takes the keyboard from no other box. Fails before: back within 2 seconds, its box focused while the chat
-- box held the keyboard.
local function BackFor(master, found)
	local f = master.D.Find(DRAFT)
	return f ~= nil and f.data.candidate ~= nil and f.data.candidate.full == found and f or nil
end
local function TookFrom(f, box)
	for _, from in ipairs(f.tookFocus) do if from == box then return true end end
	return false
end
test("recruit handoff sides (1.6.0, regression): the scanned player's popup Whisper them first asks back waits while the chat box holds the claimed player's pasted invite, and never takes the keyboard from it", function()
	WithWorld(function(world)
		local origin = Member(world, "Ashen Vale", "Horde")
		local master = Member(world, "Brann Holt", "Horde", nil, 0, true)
		Accepting(world, master)
		local found = Full("Scan Find")
		As(world, master, function()
			assert(PageLine(world, master, "recruit-candidate-toggle"), "the scan's switch").onClick()
			master.R.Candidates.ObserveWho(found, "", "Orc")
		end)
		local applicant = Full("Zoë Fírè")
		JoinAndPass(world, origin, applicant)
		assert(Run(world, 40, function() return master.D.Find(CLAIM) ~= nil end), "the claim question")
		local review
		world.beforeSend = function(p)
			if p.op ~= "N" or review then return end
			As(world, master, function()
				master.timers["recruit candidates"].fn()
				local draft = assert(master.D.Find(DRAFT), "the scanned player's popup")
				draft.def.OnAlt(draft, draft.data)
				draft:Hide()
				review = assert(master.D.Find(SCAN), "his whisper review")
			end)
		end
		assert(ClaimShown(world, master))
		Run(world, 3)
		As(world, master, function() review:Hide(); review.def.OnHide(review, review.data) end)
		Run(world, 5)
		local cmd = assert(InviteFor(master, applicant), "the claimed player's command is up")
		-- Ctrl+C: the game's chat box opens with the keyboard; Ctrl+V: the command is in it, and its popup
		-- closes on the paste, before Enter.
		local chatBox = { name = "ChatFrame1EditBox" }
		As(world, master, function() cmd.def.extra.onClick(cmd, cmd.data) end)
		master.focus = chatBox
		cmd:Hide()
		eq(Run(world, 10, function() return BackFor(master, found) ~= nil end), false, "not back while the chat box holds the pasted invite")
		master.focus = nil -- (Enter: the invite goes, the chat box closes)
		assert(Run(world, 5, function() return BackFor(master, found) ~= nil end), "back once the chat box closed")
		eq(TookFrom(BackFor(master, found), chatBox), false, "never took the keyboard from the chat box")
	end)
end)

test("recruit handoff sides (1.6.0, regression): the scanned player's popup Whisper them first asks back waits while the chat box holds his own JOIN's pasted invite, and never takes the keyboard from it", function()
	WithWorld(function(world)
		local master = Member(world, "Brann Holt", "Horde", nil, 0, true)
		local found, own = Full("Scan Find"), Full("Own Walker")
		As(world, master, function()
			assert(PageLine(world, master, "recruit-candidate-toggle"), "the scan's switch").onClick()
			master.R.Candidates.ObserveWho(found, "", "Orc")
			master.timers["recruit candidates"].fn()
			local draft = assert(master.D.Find(DRAFT), "the scanned player's popup")
			draft.def.OnAlt(draft, draft.data)
			draft:Hide()
		end)
		local review = assert(master.D.Find(SCAN), "his whisper review")
		As(world, master, function() master.R.OnWhisper("JOIN", own) end)
		Run(world, 3)
		As(world, master, function() review:Hide(); review.def.OnHide(review, review.data) end)
		Run(world, 1)
		local draft = assert(InviteFor(master, own), "the JOIN's popup came first")
		local chatBox = { name = "ChatFrame1EditBox" }
		As(world, master, function() draft.def.extra.onClick(draft, draft.data) end)
		master.focus = chatBox
		draft:Hide() -- (pasted: WatchPaste closes it; Enter not pressed yet)
		eq(Run(world, 10, function() return BackFor(master, found) ~= nil end), false, "not back while the chat box holds the pasted invite")
		master.focus = nil
		assert(Run(world, 5, function() return BackFor(master, found) ~= nil end), "back once the chat box closed")
		eq(TookFrom(BackFor(master, found), chatBox), false, "never took the keyboard from the chat box")
	end)
end)

-- The review of 1.6.0. While it waited, it gave up at the first look that found the scanned player not
-- current (Candidates.Check), which a fight, an instance or Busy makes so for a moment: three seconds of a
-- fight, and his popup never came back, though he stayed on the scan's list (his row popped once, so the
-- scan never pops him again: Church > Invites alone). It waits while he is on the list. Fails before:
-- after the fight (or the instance), no popup within a minute.
for _, busy in ipairs({ "combat", "instance" }) do
	test("recruit handoff sides (1.6.0, regression): the scanned player's popup Whisper them first asks back still comes back after " .. (busy == "combat" and "a fight" or "an instance") .. " during its wait", function()
		WithWorld(function(world)
			local origin = Member(world, "Ashen Vale", "Horde")
			local master = Member(world, "Brann Holt", "Horde", nil, 0, true)
			Accepting(world, master)
			local found = Full("Scan Find")
			As(world, master, function()
				assert(PageLine(world, master, "recruit-candidate-toggle"), "the scan's switch").onClick()
				master.R.Candidates.ObserveWho(found, "", "Orc")
			end)
			local applicant = Full("Zoë Fírè")
			JoinAndPass(world, origin, applicant)
			assert(Run(world, 40, function() return master.D.Find(CLAIM) ~= nil end), "the claim question")
			local review
			world.beforeSend = function(p)
				if p.op ~= "N" or review then return end
				As(world, master, function()
					master.timers["recruit candidates"].fn()
					local draft = assert(master.D.Find(DRAFT), "the scanned player's popup")
					draft.def.OnAlt(draft, draft.data)
					draft:Hide()
					review = assert(master.D.Find(SCAN), "his whisper review")
				end)
			end
			assert(ClaimShown(world, master))
			Run(world, 3)
			As(world, master, function() review:Hide(); review.def.OnHide(review, review.data) end)
			Run(world, 1)
			assert(InviteFor(master, applicant), "the claimed player's command is up")
			-- Three seconds of it while that command is up; then he takes the command to chat.
			master[busy] = true
			Run(world, 3)
			master[busy] = nil
			local cmd = assert(InviteFor(master, applicant))
			As(world, master, function() cmd.def.extra.onClick(cmd, cmd.data) end)
			cmd:Hide()
			assert(Run(world, 60, function() return BackFor(master, found) ~= nil end), "the scanned player's popup came back")
		end)
	end)
end

-- (Failure case) A scanned player who is no longer current by then does not come back.
test("recruit handoff sides (1.6.0): a scanned player's popup asked back by Whisper them first does not come back once the scan is off", function()
	WithWorld(function(world)
		local origin = Member(world, "Ashen Vale", "Horde")
		local master = Member(world, "Brann Holt", "Horde", nil, 0, true)
		Accepting(world, master)
		local found = Full("Scan Find")
		local switch
		As(world, master, function()
			for _, line in ipairs(master.R.WhisperLines()) do
				if line.text and line.text:find(L.RECRUIT_CANDIDATES_OFF, 1, true) then switch = line end
			end
			assert(switch, "the scan's switch").onClick()
			master.R.Candidates.ObserveWho(found, "", "Orc")
		end)
		local applicant = Full("Zoë Fírè")
		JoinAndPass(world, origin, applicant)
		assert(Run(world, 40, function() return master.D.Find(CLAIM) ~= nil end), "the claim question")
		local review
		world.beforeSend = function(p)
			if p.op ~= "N" or review then return end
			As(world, master, function()
				master.timers["recruit candidates"].fn()
				local draft = assert(master.D.Find(DRAFT), "the scanned player's popup")
				draft.def.OnAlt(draft, draft.data)
				draft:Hide()
				review = assert(master.D.Find(SCAN), "his whisper review")
			end)
		end
		assert(ClaimShown(world, master))
		Run(world, 3)
		As(world, master, function() review:Hide(); review.def.OnHide(review, review.data) end)
		Run(world, 5)
		assert(InviteFor(master, applicant), "the claimed player's command is up")
		-- He turns the scan off while it is up, then takes it to chat.
		local on = assert(PageLine(world, master, "recruit-candidate-toggle"), "the scan's switch")
		assert(on.text:find(L.RECRUIT_CANDIDATES_ON, 1, true), "on")
		As(world, master, on.onClick)
		assert(not master.R.Candidates.Enabled(), "the scan is off")
		local draft = InviteFor(master, applicant)
		As(world, master, function() draft.def.extra.onClick(draft, draft.data) end)
		draft:Hide()
		Run(world, 30)
		eq(master.D.Find(DRAFT), nil, "no scanned player's popup comes back")
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

-- 1.6.0's new lines in every language the addon has, each its own words: a claim no name answered (its
-- one %s the member who passed the player), and where to invite a claimed player when Incoming JOIN is
-- Queue only (no slot).
local NEW_LINES = { RECRUIT_HANDOFF_NO_NAME = 1, RECRUIT_HANDOFF_IN_QUEUE = 0 }
-- (Review of the lane) The no-name line says whose queue the player stays in: the member's who passed
-- him, by the word each language's handoff lines use for a member. "Their queue" ("seiner", "sa", "sua",
-- "su") read as the player's own.
local MEMBER_WORD = { enUS = "member", ptBR = "membro", deDE = "Mitglied", esES = "miembro", esMX = "miembro",
	frFR = "membre", itIT = "membro", ruRU = "участник" }
local function HandoffText(code)
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
	return lns
end
test("recruit handoff sides (1.6.0): the no-name line and the Queue only pointer in every language", function()
	local english = {}
	for _, code in ipairs({ "enUS", "ptBR", "deDE", "esES", "esMX", "frFR", "itIT", "ruRU" }) do
		local lns = HandoffText(code)
		for key, slots in pairs(NEW_LINES) do
			local line = rawget(lns.L, key)
			assert(type(line) == "string" and line ~= "", code .. " " .. key)
			eq(select(2, line:gsub("%%s", "")), slots, code .. " " .. key .. ": its %s")
			eq(lns.LocaleCodes(line), lns.LocaleCodes(english[key] or line), code .. " " .. key .. ": the English line's codes")
			if code == "enUS" then english[key] = line else assert(line ~= english[key], code .. " " .. key .. ": its own words") end
		end
		local noName = lns.L.RECRUIT_HANDOFF_NO_NAME
		assert(noName:find(MEMBER_WORD[code], 1, true), code .. ": the queue is the member's: " .. noName)
	end
end)


local function OverflowMembers(w)
	local cap = ns.Codec.GUILD_CAP
	local first = Member(w, "Gold Gale", "Alliance", nil, 1, nil, "Olympus Sun")
	local second = Member(w, "Copper Rock", "Alliance", nil, 1, nil, "Olympus Copper")
	local side = Member(w, "Sea Ash", "Alliance", nil, 1, nil, "Olympus Wave")
	local enrolled, primary, actors = {}, { [first.guild] = true, [second.guild] = true }, {}
	local revision = 1
	for _, c in ipairs({ first, second, side }) do
		enrolled[c.guild] = true
		c.capacity, c.captured = primary[c.guild] and cap or 400, w.now
		actors[c.guild] = { Full(c.short .. " Keeper"), c.name }
		c.ns.SharedToolsActive = function() return true end
		c.ns.SharedToolsHere = function() return enrolled[c.guild] == true end
		c.ns.SharedGuildAllowed = function(guild) return enrolled[guild] == true end
		c.ns.FederationProgram = {
			EnrollmentRevision = function() return revision end,
			LocalEnrollment = function() return enrolled[c.guild] and c.guild or nil end,
			PrimaryGuilds = function() return primary end,
			IsEnrolled = function(guild) return enrolled[guild] == true end,
			Roleholders = function(guild) return unpack(actors[guild] or {}) end,
			Role = function(name, guild)
				local roles = enrolled[guild] and actors[guild]
				return roles and (roles[2] == name and "official" or roles[1] == name and "caretaker") or nil
			end,
		}
		c.ns.Data = setmetatable({ ServerTime = function() return w.now end }, { __index = ns.Data })
		c.ns.Roster = setmetatable({
			Fresh = function()
				return { guild = c.guild, complete = true, serverAt = c.captured,
					lastStats = { numTotal = c.capacity, seen = c.capacity } }
			end,
			RankOf = function(name) return name == c.name and 1 or nil end,
		}, { __index = ns.Roster })
	end
	Accepting(w, side)
	return first, second, side, enrolled
end

test("verified overflow: only a federation JOIN goes from full primaries to an enrolled side with room", function()
	WithWorld(function(w)
		local first, second, side = OverflowMembers(w)
		local applicant = Full("Aster Vale")
		local function Offer(req)
			return As(w, first, first.H.Offer, req, side.name, side.guild)
		end
		As(w, first, first.R.OnWhisper, "JOIN", Full("Holly Vale"))
		eq(Offer(first.R.requests[1]), false, "a guild-only JOIN is private to the guild")
		eq(#w.queue, 0, "a guild-only JOIN starts no cross-guild lookup")
		As(w, first, first.R.OnWhisper, "JOIN OLYMPUS", applicant)
		local req = first.R.requests[2]
		second.capacity = ns.Codec.GUILD_CAP - 1
		eq(Offer(req), false, "seats must be confirmed")
		Deliver(w)
		eq(Offer(req), false, "one primary still has room")
		eq(Count(w, "O"), 0)
		w.now = w.now + 91
		first.captured, second.captured, side.captured = w.now, w.now, w.now
		second.capacity = ns.Codec.GUILD_CAP
		eq(Offer(req), false, "expired observations carry no authority")
		Deliver(w)
		eq(Offer(req), false, "side guild must confirm room too")
		Deliver(w)
		eq(Offer(req), true)
		Deliver(w)
		eq(Count(w, "N"), 0)
		for _, message in ipairs(w.sent) do
			eq(message.word:find(applicant, 1, true), nil, "all preliminary packets omit the name")
		end
		eq(Run(w, 15, function() return side.D.Find(CLAIM) ~= nil end), true)
		eq(ClaimShown(w, side), true)
		Deliver(w)
		eq(Count(w, "N", side, first), 1)
		eq(side.R.requests[1].name, applicant)
		eq(side.R.requests[1].overflowFrom, first.guild)
		eq(first.H.State(req), "assigned")
		side.capacity = ns.Codec.GUILD_CAP
		eq(As(w, side, side.R.Accept, side.R.requests[1]), false, "native full destination blocks another draft")
	end)
end)

test("verified overflow: capacity or enrollment changes drop a queued name before it can leave", function()
	WithWorld(function(w)
		local first, _, side, enrolled = OverflowMembers(w)
		As(w, first, first.R.OnWhisper, "JOIN OLYMPUS", Full("Clover Vale"))
		local req = first.R.requests[1]
		As(w, first, first.H.Offer, req, side.name, side.guild)
		Deliver(w)
		As(w, first, first.H.Offer, req, side.name, side.guild)
		Deliver(w)
		eq(As(w, first, first.H.Offer, req, side.name, side.guild), true)
		Deliver(w)
		eq(Run(w, 15, function() return side.D.Find(CLAIM) ~= nil end), true)
		eq(ClaimShown(w, side), true)
		w.beforeSend = function(packet)
			if packet.op == "N" then first.capacity = ns.Codec.GUILD_CAP - 1 end
		end
		Deliver(w)
		eq(Count(w, "N", side, first), 0)
		eq(#side.R.requests, 0)
		eq(first.H.State(req), nil, "a provably unsent name clears the local lock")
		enrolled[side.guild] = nil
		eq(As(w, first, first.H.Offer, req, side.name, side.guild), false, "a revoked side guild cannot receive an offer")
	end)
end)


test("verified overflow: the legacy wire and another realm cannot bypass the offered route", function()
	WithWorld(function(w)
		local first, _, side = OverflowMembers(w)
		local word = ("J4~O~1-a-1~%d~ForeverPvE~Alliance~%s~%s~"):format(w.now + 30, first.guild, side.guild)
		eq(As(w, side, side.H.Receive, "WHISPER", first.name, word), false, "legacy cross-guild packet")
		local verified = word:gsub("J4", "J6", 1)
		eq(As(w, side, side.H.Receive, "WHISPER", first.name:gsub("CAMWOWUS", "CAMWOWEU"), verified), false,
			"a namesake in another region is no roleholder")
		local reverse = ("J6~O~1-a-2~%d~ForeverPvE~Alliance~%s~%s~"):format(w.now + 30, side.guild, first.guild)
		Accepting(w, first)
		eq(As(w, first, first.H.Receive, "WHISPER", side.name, reverse), false, "side to primary is not overflow")
		eq(Count(w, "N"), 0)
	end)
end)
