local ns, test, eq, FreshComm = ...
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

test("recruit handoff: opt-in applicant intent and one trusted claimant gate sharing and acknowledgement", function()
	WithHandoff(function(scene)
		R.OnWhisper("JOIN", "Own Recruit-" .. home)
		local localReq = R.requests[1]
		eq(H.Offer(localReq, officer, sister), false, "bare JOIN does not authorize a referral outside this guild")
		R.OnWhisper("JOIN OLYMPUS", applicant)
		local req = R.requests[2]
		scene.support = 1
		eq(H.Offer(req, officer, sister), false, "a single census claim is insufficient")
		scene.support = 2
		local pick = assert(Find(R.RequestLines(true), ns.L.RECRUIT_HANDOFF_PICK))
		pick.onClick()
		local sameGuild = assert(Find(R.RequestLines(true), "Guild Recruiter"))
		assert(sameGuild.onClick, "eligible native officer is offered through Church queue")
		eq(H.Offer(req, officer, sister), true)
		local offered = scene.packets[1]
		eq(offered.peer, officer)
		eq(H.State(req), "offered")
		eq(offered.word:find(applicant, 1, true), nil, "no candidate name leaves with the offer")
		eq(R.Accept(req), false, "origin cannot open a second invite while the offer is active")
		eq(H.Offer(req, mate, own), false, "only one target can claim")
		local claim = offered.word:gsub("^J4~O~", "J4~C~")
		H.Receive("WHISPER", mate, claim)
		eq(#scene.packets, 1, "another real officer cannot claim the offer addressed to someone else")
		H.Receive("CHANNEL", officer, claim)
		eq(#scene.packets, 1, "a relayed/public claim is never accepted")
		H.Receive("WHISPER", officer, claim)
		eq(#scene.packets, 2)
		eq(scene.packets[2].peer, officer)
		assert(scene.packets[2].word:match("^J4~N~") and scene.packets[2].word:sub(-#applicant) == applicant)
		eq(H.State(req), "assigning", "native send success does not prove receipt")
		H.Receive("WHISPER", officer, claim)
		eq(#scene.packets, 2, "a repeated claim does not share the name again")
		H.Receive("WHISPER", officer, offered.word:gsub("^J4~O~", "J4~A~"))
		eq(H.State(req), "assigned")
		scene.now = scene.now + 91
		eq(H.Offer(req, mate, own), false, "an acknowledged assignment stays single-owner after the offer expires")
		eq(R.Accept(req), false)
	end)
end)

test("recruit overflow: a burst preserves the visible prompt and offers one pending JOIN after availability", function()
	WithHandoff(function(scene)
		R.OnWhisper("JOIN", "First Recruit-" .. home)
		R.OnWhisper("JOIN", "Visible Recruit-" .. home)
		local visible = R.requests[2]
		ns.Dialog = { Find = function(which)
			if which == "OLYMPUS_RECRUIT_INVITE_DRAFT" then
				return { data = { req = visible, automatic = true }, Hide = function() end }
			end
		end }
		for i = 1, 60 do R.OnWhisper("JOIN OLYMPUS", ("Batch %d-%s"):format(i, home)) end
		eq(#R.requests, 30)
		eq(R.requests[1], visible, "overflow retains the applicant already on screen")
		eq(#scene.packets, 0, "automatic offers are off by default")
		eq(H.ToggleAuto(), true)
		scene.tick()
		local probe = assert(scene.packets[1]); eq(probe.peer, mate)
		assert(probe.word:match("^J4~P~") and probe.word:sub(-1) == "~", "probe contains no applicant name")
		scene.tick(); eq(#scene.packets, 1, "only one probe remains in flight")
		local available = probe.word:gsub("^J4~P~", "J4~V~")
		eq(H.Receive("WHISPER", officer, available), false, "sister guild cannot enter automatic handoff")
		eq(H.Receive("WHISPER", mate, available), true)
		eq(H.Receive("WHISPER", mate, available), false, "availability reply is consumed once")
		scene.tick()
		local offer = assert(scene.packets[2]); eq(offer.peer, mate)
		assert(offer.word:match("^J4~O~") and offer.word:sub(-1) == "~", "offer contains no applicant name")
		eq(H.State(visible), nil, "auto never takes over the visible request")
		local candidate = assert(R.requests[2]); eq(H.State(candidate), "offered")
		local claim = offer.word:gsub("^J4~O~", "J4~C~")
		eq(H.Receive("WHISPER", mate, claim), true)
		local assignment = assert(scene.packets[3]); eq(assignment.peer, mate)
		assert(assignment.word:match("^J4~N~") and assignment.word:sub(-#candidate.name) == candidate.name)
		eq(H.Receive("WHISPER", mate, claim), false)
		eq(#scene.packets, 3)
		eq(H.ToggleAuto(), false); eq(scene.cancelled, true)
		local allowed, why = assignment.guard()
		eq(allowed, false, "stopping automatic handoffs cancels the queued name transfer")
		assignment.done(false, why)
		eq(H.State(candidate), nil, "a known unsent assignment returns to the local queue")
	end)
end)

test("recruit overflow: an empty or unresponsive eligible roster keeps JOINs local", function()
	WithHandoff(function(scene)
		for i = 1, 3 do R.OnWhisper("JOIN", ("Pending %d-%s"):format(i, home)) end
		local roster = ns.Roster.online
		ns.Roster.online = {}
		eq(H.ToggleAuto(), true)
		scene.tick()
		eq(#scene.packets, 0, "no eligible officer means no traffic")
		ns.Roster.online = roster
		scene.tick()
		local first = assert(scene.packets[1]); assert(first.word:match("^J4~P~"))
		scene.now = scene.now + 19; scene.tick()
		eq(#scene.packets, 1, "one outstanding probe, no guessed offer")
		scene.now = scene.now + 2; scene.tick()
		eq(#scene.packets, 2); eq(first.guard(), false, "stale probe is invalidated")
		eq(H.Receive("WHISPER", mate, first.word:gsub("^J4~P~", "J4~V~")), false, "late opt-in reply ignored")
		for _, req in ipairs(R.requests) do eq(H.State(req), nil, "no applicant left the local queue") end
	end)
end)

test("recruit overflow: an eligible recipient privately replies only while opted in and available", function()
	WithHandoff(function(scene)
		local function Probe(id)
			return ("J4~P~%s~%d~ForeverPvE~Alliance~%s~%s~"):format(id, scene.now + 20, own, own)
		end
		eq(H.Receive("WHISPER", mate, Probe("1234-ab-1")), false)
		eq(H.Toggle(), true)
		scene.quiet = true
		eq(H.Receive("WHISPER", mate, Probe("1234-ab-1")), false)
		scene.quiet = false
		eq(H.Receive("WHISPER", mate, Probe("1234-ab-1")), true)
		local answer = assert(scene.packets[1]); eq(answer.peer, mate)
		assert(answer.word:match("^J4~V~") and answer.word:sub(-1) == "~")
		eq(H.Receive("WHISPER", mate, Probe("1234-ab-2")), false, "response cadence is bounded")
		eq(H.Toggle(), false)
		eq(answer.guard(), false)
	end)
end)

test("recruit handoff: receiver opts in and claims before seeing a name; wrong scope and duplicate refused", function()
	WithHandoff(function(scene)
		local word = Packet(scene, "O", sister, own)
		local name = Packet(scene, "N", sister, own, applicant)
		local label = ns.L.RECRUIT_HANDOFF_CLAIM:format("Sister Recruiter", sister)
		H.Receive("WHISPER", officer, word)
		eq(Find(R.WhisperLines(), label), nil, "default off")
		local toggle = assert(Find(R.WhisperLines(), ns.L.RECRUIT_HANDOFF_OFF))
		eq(toggle.onClick(), true)
		H.Receive("WHISPER", officer, word:gsub("~Alliance~", "~Horde~"))
		H.Receive("WHISPER", officer, word:gsub("~ForeverPvE~", "~ForeverPvP~"))
		H.Receive("WHISPER", officer, word:gsub("~Olympus Prime~", "~Olympus IV~"))
		H.Receive("WHISPER", "Fake Officer-" .. other, word)
		eq(Find(R.WhisperLines(), label), nil, "no claim action for invalid scope, guild or authority")
		H.Receive("WHISPER", officer, word)
		assert(Find(R.WhisperLines(), label), "offer is visible only after opting in")
		H.Receive("WHISPER", officer, name)
		eq(#R.requests, 0, "name cannot be added before the deliberate claim")
		eq(Find(R.WhisperLines(), label).onClick(), nil)
		eq(#scene.packets, 1)
		assert(scene.packets[1].word:match("^J4~C~") and not scene.packets[1].word:find(applicant, 1, true))
		H.Receive("WHISPER", officer, name)
		eq(#R.requests, 1)
		eq(R.requests[1].name, applicant)
		eq(R.requests[1].guild, own)
		eq(R.requests[1].handoffIntent, nil, "an imported request is not offered onward")
		eq(#scene.packets, 2)
		assert(scene.packets[2].word:match("^J4~A~"))
		H.Receive("WHISPER", officer, name)
		eq(#scene.packets, 2)
		eq(#R.requests, 1, "no duplicate queue entry")
	end)
end)

test("recruit handoff: expired offer can be offered again, and changed permissions cancel queued packets", function()
	WithHandoff(function(scene)
		R.OnWhisper("JOIN OLYMPUS", applicant)
		local req = R.requests[1]
		eq(H.Offer(req, officer, sister), true)
		local packet = scene.packets[1]
		scene.fresh = false
		eq(packet.guard(), false, "stale native roster before actual send")
		scene.fresh = true
		scene.now = scene.now + 91
		eq(H.State(req), nil)
		H.Receive("WHISPER", officer, packet.word:gsub("^J4~O~", "J4~C~"))
		eq(#scene.packets, 1, "late claim cannot release the candidate name")
		eq(H.Offer(req, mate, own), true)
		scene.permission = false
		eq(scene.packets[2].guard(), false, "loss of native invite permission cancels the queued offer")
	end)
end)

test("recruit handoff: real addon transport rejects public offers and duplicate applicant sub-realm stamps", function()
	WithHandoff(function(scene)
		local savedChat = C_ChatInfo
		local cns, deliver = FreshComm()
		C_ChatInfo = savedChat
		cns.clock = scene.now
		cns.Comm.Handle("J4", H.Receive)
		local label = ns.L.RECRUIT_HANDOFF_CLAIM:format("Sister Recruiter", sister)
		eq(H.Toggle(), true)
		deliver("GUILD", officer, Packet(scene, "O", sister, own))
		eq(Find(R.WhisperLines(), label), nil, "no offers arrive through public channels or GUILD")
		deliver("WHISPER", officer, Packet(scene, "O", sister, own))
		assert(Find(R.WhisperLines(), label)).onClick()
		eq(#scene.packets, 1)
		R.OnWhisper("JOIN", "New Recruit-" .. other)
		deliver("WHISPER", officer, Packet(scene, "N", sister, own, applicant))
		eq(#R.requests, 1, "an existing direct request wins even if another sub-realm stamped the same character")
		eq(#scene.packets, 1, "the origin is not told the handoff was accepted")
	end)
end)

-- 1.5.8 (the author, 11-12: "quando um invite aparecer, não tem que clicar em prepare invite").
test("recruit handoff: a claimed request opens the copy command at once, after a Claim question", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		eq(H.Toggle(), true)
		H.Receive("WHISPER", officer, Packet(scene, "O", sister, own))
		local claim = assert(D.Find(CLAIM), "an offer asks the opted-in officer to claim it")
		eq(claim.text:find("New Recruit", 1, true), nil, "the question carries no applicant name")
		eq(#scene.packets, 0, "showing the question claims nothing")
		claim.def.OnAccept(claim, claim.data)
		claim:Hide()
		eq(#scene.packets, 1)
		assert(scene.packets[1].word:match("^J4~C~"))
		H.Receive("WHISPER", officer, Packet(scene, "N", sister, own, applicant))
		local req = assert(R.requests[1])
		eq(req.name, applicant)
		eq(D.Find("OLYMPUS_RECRUIT_REPLY"), nil, "no Prepare step for a handed-over request")
		local draft = assert(D.Find(DRAFT), "the copy command opens as soon as the name arrives")
		eq(draft.data.req, req)
		eq(draft.def.button2Shown(draft, draft.data), false, "a handed-over request is not passed on again")
		eq(Find(R.RequestLines(true), ns.L.RECRUIT_WHISPER_REVIEW:format(own)), nil, "its queue line skips the review step too")
	end)
end)

-- 1.5.8 (the author, 11-12: "ele mostrar tantas pessoas na fila depois dessa. E aí você clica no
-- botão e fala tipo, é repassar os negócios pra outros offices").
test("recruit handoff: the JOIN popup counts the requests behind it and passes them to opted-in officers", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		scene.locked = true
		for i = 1, 3 do R.OnWhisper("JOIN", ("Waiting %d-%s"):format(i, home)) end
		eq(D.Find(DRAFT), nil, "no popup while game chat is locked")
		scene.locked = false
		R.OnWhisper("JOIN", "Fourth Recruit-" .. home)
		local first = R.requests[1]
		local draft = assert(D.Find(DRAFT))
		eq(draft.data.req, first, "the earliest JOIN is shown first")
		assert(draft.text:find(ns.L.RECRUIT_HANDOFF_MORE:format(3), 1, true), "the popup counts the JOINs behind it")
		assert(draft.def.button2Shown(draft, draft.data), "a JOIN on screen can be passed on")
		eq(draft.def.OnCancel, nil, "Escape or a replaced popup never passes a request")
		eq(#scene.packets, 0)
		draft.def.OnButton2(draft, draft.data)
		draft:Hide()
		for _, req in ipairs(R.requests) do eq(req.passWanted, true, "the waiting JOINs go with it") end
		assert(Find(R.WhisperLines(), ns.L.RECRUIT_OVERFLOW_ON), "passing turns on the automatic offers")
		scene.tick()
		local probe = assert(scene.packets[1])
		eq(probe.peer, mate)
		assert(probe.word:match("^J4~P~") and probe.word:sub(-1) == "~", "the probe carries no applicant name")
		eq(H.Receive("WHISPER", mate, (probe.word:gsub("^J4~P~", "J4~V~"))), true)
		scene.tick()
		local offer = assert(scene.packets[2])
		assert(offer.word:match("^J4~O~"))
		eq(H.State(first), "offered", "the request that was on screen goes first")
		scene.now = scene.now + 21
		R.OnWhisper("JOIN", "Fifth Recruit-" .. home)
		eq(assert(D.Find(DRAFT)).data.req.name, "Fifth Recruit-" .. home, "passed requests do not pop up here again")
	end)
end)

test("recruit handoff: an invite the game blocked is passed on only by the officer's word", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		R.OnWhisper("JOIN", applicant)
		local req = R.requests[1]
		assert(D.Find(DRAFT)):Hide()
		eq(Find(R.RequestLines(true), ns.L.RECRUIT_HANDOFF_BLOCKED), nil, "nothing to report before the command went to chat")
		eq(R.Accept(req), true)
		eq(req.invitePrepared, true)
		assert(D.Find(DRAFT)):Hide()
		eq(H.CanPass(req), false, "a prepared invite is never passed on silently")
		assert(Find(R.RequestLines(true), ns.L.RECRUIT_HANDOFF_BLOCKED)).onClick()
		eq(req.invitePrepared, nil)
		eq(req.passWanted, true)
		scene.tick()
		eq(H.Receive("WHISPER", mate, (assert(scene.packets[1]).word:gsub("^J4~P~", "J4~V~"))), true)
		scene.tick()
		eq(H.State(req), "offered")
	end)
end)

-- 1.5.8 (the author's, 11-12: "o repasse tem que ir para qualquer pessoa que esteja com a feature
-- ativa. Não precisa ser só para officer, porque, por exemplo, eu não sou officer das minhas guildas
-- e eu consigo convidar"): any member of the guild whose client recruits, accepts handoffs and can
-- invite gives and takes them, whatever his rank; the game's invite permission is the only gate.
test("recruit handoff (1.5.8): members of any rank who can invite give and take handoffs", function()
	WithHandoff(function(scene)
		ns.Roster.RankOf = function(name)
			if name == me then return 5 end
			if name == mate then return 6 end
		end
		local accept = assert(Find(R.WhisperLines(), ns.L.RECRUIT_HANDOFF_OFF), "a member sees the handoff switch")
		eq(accept.onClick(), true, "a member who can invite accepts handoffs")
		for i = 1, 3 do R.OnWhisper("JOIN", ("Member Queue %d-%s"):format(i, home)) end
		eq(H.ToggleAuto(), true, "a member offers his waiting JOINs")
		scene.tick()
		local probe = assert(scene.packets[1], "the probe goes to a member, not only an officer")
		eq(probe.peer, mate)
		eq(H.Receive("WHISPER", mate, (probe.word:gsub("^J4~P~", "J4~V~"))), true)
		scene.tick()
		local offer = assert(scene.packets[2]); assert(offer.word:match("^J4~O~"))
		eq(H.Receive("WHISPER", mate, (offer.word:gsub("^J4~O~", "J4~C~"))), true, "a member's claim is taken")
		assert(scene.packets[3].word:match("^J4~N~"), "the name goes to the member who claimed")
		-- The receiving side: a member's offer reaches this member, who claims it.
		local D = Dialogs()
		ns.Dialog = D
		H.Receive("WHISPER", mate, Packet(scene, "O", own, own, nil, "5555-cd-1"))
		local claim = assert(D.Find(CLAIM), "a member's offer asks this member to claim it")
		claim.def.OnAccept(claim, claim.data)
		assert(scene.packets[4].word:match("^J4~C~"))
		-- Someone outside the roster is never a party, whatever he claims.
		eq(H.Receive("WHISPER", "Stranger-" .. home, Packet(scene, "O", own, own, nil, "6666-ef-1")), false)
		-- A member whose rank cannot invite takes no handoff.
		scene.permission = false
		eq(H.Receive("WHISPER", mate, Packet(scene, "O", own, own, nil, "7777-ab-1")), false,
			"without the game's invite permission no offer is taken")
		eq(Find(R.WhisperLines(), ns.L.RECRUIT_HANDOFF_ON), nil, "nor are the handoff switches shown")
	end)
end)

-- 1.5.8 (the author's: "se ela tentar ativar e ela não puder convidar pessoas, vai avisar, tipo,
-- você não pode convidar mesmo para sua guilda, fale com o seu GM").
test("recruit (1.5.8): turning recruiting on without the game's invite permission says why and stays off", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		eq(R.ToggleWhisperRecruiting(), false, "turned off first")
		scene.permission = false
		local toggle = assert(R.WhisperLines()[1], "Church > Invites shows the switch to every member")
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
test("recruit handoff (1.5.8): a scanned unguilded player is passed from his popup and goes out only after a claim", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		local wolf = "Lone Wolf-" .. home
		local tick = ScanOne(scene, wolf)
		tick()
		local draft = assert(D.Find(DRAFT), "the scan pops the copy command")
		local row = assert(draft.data.candidate)
		assert(draft.def.button2Shown(draft, draft.data), "a scanned player can be passed from his popup")
		draft.def.OnButton2(draft, draft.data)
		draft:Hide()
		eq(row.passWanted, true)
		assert(Find(R.WhisperLines(), ns.L.RECRUIT_OVERFLOW_ON), "passing turns on the automatic offers")
		assert(Find(R.WhisperLines(), ns.L.RECRUIT_CANDIDATE_PASSING:format("Lone Wolf")), "the scan list says so")
		tick()
		eq(D.Find(DRAFT), nil, "a passed player does not pop up here again")
		scene.tick()
		local probe = assert(scene.packets[1]); eq(probe.peer, mate)
		eq(H.Receive("WHISPER", mate, (probe.word:gsub("^J4~P~", "J4~V~"))), true)
		scene.tick()
		local offer = assert(scene.packets[2])
		assert(offer.word:match("^J4~O~") and not offer.word:find("Lone Wolf", 1, true), "the offer carries no name")
		eq(H.State(row), "offered")
		eq(R.CopyCandidateInvite(row), false, "no second copy here while the offer is out")
		eq(H.Receive("WHISPER", mate, (offer.word:gsub("^J4~O~", "J4~C~"))), true)
		local named = assert(scene.packets[3])
		assert(named.word:match("^J4~N~") and named.word:sub(-#wolf) == wolf, "the name goes after the claim")
		eq(H.Receive("WHISPER", mate, (offer.word:gsub("^J4~O~", "J4~A~"))), true)
		eq(H.State(row), "assigned")
		-- The same player, now whispering JOIN, is never offered a second time.
		R.OnWhisper("JOIN", wolf)
		local again = assert(R.requests[1])
		eq(again.name, wolf)
		eq(H.CanPass(again), false, "no duplicate offer of a name already handed on")
	end)
end)

-- 1.5.8 (the author's message to the streamer: "it lines them up for him up to his 10 a minute and
-- passes the rest to other members accepting requests").
test("recruit handoff (1.5.8): at ten invites a minute new JOINs and sightings go to other members or say the limit", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		local savedUtil = ChatFrameUtil
		ChatFrameUtil = { OpenChat = function() end }
		local ok, err = pcall(function()
			eq(R.INVITES_PER_MINUTE, 10)
			for i = 1, 10 do R.OnWhisper("JOIN", ("Fast %d-%s"):format(i, home)) end
			for i = 1, 10 do
				local open = D.Find(DRAFT)
				if open then open:Hide() end
				eq(R.Accept(R.requests[i]), true)
				local draft = assert(D.Find(DRAFT))
				eq(R.AtInviteLimit(), false, "under the limit until the tenth command goes to chat")
				draft.def.extra.onClick(draft, draft.data)
				eq(D.Find(DRAFT), nil, "the command went to chat")
			end
			eq(R.AtInviteLimit(), true, "ten commands taken to chat in a minute reach the limit")
			-- Automatic offers off: the popup says so and offers Pass.
			scene.now = scene.now + 21
			R.OnWhisper("JOIN", "Eleventh Recruit-" .. home)
			local draft = assert(D.Find(DRAFT), "with the offers off the JOIN still pops up")
			eq(draft.data.req.name, "Eleventh Recruit-" .. home)
			assert(draft.text:find(ns.L.RECRUIT_INVITE_LIMIT_PASS:format(10), 1, true), "the popup says the limit is reached")
			assert(draft.def.button2Shown(draft, draft.data), "and offers Pass")
			draft:Hide()
			-- Automatic offers on: the next JOIN and the next sighting go to other members, no popup.
			eq(H.ToggleAuto(), true)
			scene.now = scene.now + 21
			R.OnWhisper("JOIN", "Twelfth Recruit-" .. home)
			local twelfth = R.requests[#R.requests]
			eq(twelfth.name, "Twelfth Recruit-" .. home)
			eq(D.Find(DRAFT), nil, "no popup at the limit with the offers on")
			eq(twelfth.passWanted, true, "the JOIN is offered to the other members")
			local tick = ScanOne(scene, "Far Walker-" .. home)
			tick()
			eq(D.Find(DRAFT), nil, "nor for a new sighting")
			scene.tick()
			eq(H.Receive("WHISPER", mate, (assert(scene.packets[1]).word:gsub("^J4~P~", "J4~V~"))), true)
			scene.tick()
			eq(H.State(twelfth), "offered", "the JOIN goes out first")
			eq(#scene.packets, 2, "one offer at a time")
			-- A minute after the commands, popups come back.
			scene.now = scene.now + 61
			eq(R.AtInviteLimit(), false)
			R.OnWhisper("JOIN", "Later Recruit-" .. home)
			local later = assert(D.Find(DRAFT), "under the limit the JOIN pops up again")
			eq(later.data.req.name, "Later Recruit-" .. home)
			eq(later.text:find(ns.L.RECRUIT_INVITE_LIMIT_PASS:format(10), 1, true), nil)
		end)
		ChatFrameUtil = savedUtil
		if not ok then error(err, 0) end
	end)
end)

-- 1.5.8: with every member a possible taker, a guild of hundreds online must not wait twenty
-- seconds on each member without Olympus: the probe goes to one this client heard run it.
test("recruit overflow (1.5.8): the probe goes first to members known to run Olympus", function()
	WithHandoff(function(scene)
		local V = ns.Versions
		local saved = V.HasOlympus
		local quiet = "Quiet Member-" .. home
		ns.Roster.online = { { name = quiet }, { name = mate } }
		ns.Roster.RankOf = function(name)
			if name == me then return 5 end
			if name == mate or name == quiet then return 6 end
		end
		local ok, err = pcall(function()
			V.HasOlympus = function(name) return name == mate end
			for i = 1, 3 do R.OnWhisper("JOIN", ("Known Queue %d-%s"):format(i, home)) end
			eq(H.ToggleAuto(), true)
			scene.tick()
			eq(assert(scene.packets[1]).peer, mate, "the member without Olympus is skipped")
			V.HasOlympus = function() return false end
			scene.now = scene.now + 21
			scene.tick()
			eq(assert(scene.packets[2]).peer, quiet, "knowing none, every member is tried in turn")
		end)
		V.HasOlympus = saved
		if not ok then error(err, 0) end
	end)
end)
