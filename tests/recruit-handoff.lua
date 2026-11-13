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
		-- (Review of 1.5.8: not opted in, he says no at once, "D", instead of nothing; the test
		-- "a member who takes no names says no to a probe at once" covers it.)
		eq(H.Receive("WHISPER", mate, Probe("1234-ab-1")), true)
		assert(scene.packets[1].word:match("^J4~D~"), "not opted in, a no")
		scene.now = scene.now + 9
		eq(H.Toggle(), true)
		scene.quiet = true
		eq(H.Receive("WHISPER", mate, Probe("1234-ab-1")), false)
		scene.quiet = false
		eq(H.Receive("WHISPER", mate, Probe("1234-ab-1")), true)
		local answer = assert(scene.packets[2]); eq(answer.peer, mate)
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

-- 1.5.9 (the author, 11-12: the member who passed a JOIN or a scanned player on gets a share of that
-- recruit's points once he joins, "tipo os pontos da rede"): the name that arrives keeps who passed it,
-- on the request and for the recruiting ranking (RecruitRanking.HandedIn, its own file's tests).
test("1.5.9 recruit handoff: the name a member passed on keeps who passed it, for the recruiting ranking for everyone", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		local saved, handed = rawget(ns, "RecruitRanking"), {}
		ns.RecruitRanking = { HandedIn = function(name, by) handed[#handed + 1] = { name = name, by = by } return true end }
		local ok, err = pcall(function()
			eq(H.Toggle(), true)
			H.Receive("WHISPER", officer, Packet(scene, "O", sister, own))
			local claim = assert(D.Find(CLAIM))
			claim.def.OnAccept(claim, claim.data)
			claim:Hide()
			eq(#handed, 0, "nothing before the name")
			H.Receive("WHISPER", officer, Packet(scene, "N", sister, own, applicant))
			local req = assert(R.requests[1])
			eq(req.handedBy, officer)
			eq(#handed, 1)
			eq(handed[1].name, applicant); eq(handed[1].by, officer)
			-- The same name again is no second handoff.
			H.Receive("WHISPER", officer, Packet(scene, "N", sister, own, applicant))
			eq(#handed, 1)
		end)
		ns.RecruitRanking = saved
		if not ok then error(err, 0) end
	end)
end)

-- Review of 1.5.9: the inviter's own report alone named who passed him a player (an alt or a friend took
-- 25% of his recruits). The member who passed the name says so himself, once its member took it ("A"):
-- RecruitRanking.HandedOut, whose word the keepers match with the inviter's (its own file's tests).
test("1.5.9 recruit handoff: the member who passed a name on tells the recruiting ranking once its member took it, once", function()
	WithHandoff(function(scene)
		local saved, out = rawget(ns, "RecruitRanking"), {}
		ns.RecruitRanking = { HandedOut = function(name, to) out[#out + 1] = { name = name, to = to } return true end }
		local ok, err = pcall(function()
			R.OnWhisper("JOIN OLYMPUS", applicant)
			local req = R.requests[1]
			eq(H.Offer(req, officer, sister), true)
			local offered = scene.packets[1]
			local claim = offered.word:gsub("^J4~O~", "J4~C~")
			eq(H.Receive("WHISPER", officer, claim), true)
			assert(scene.packets[2].word:match("^J4~N~"), "the name went")
			eq(#out, 0, "nothing while the name is only on its way")
			eq(H.Receive("WHISPER", officer, (offered.word:gsub("^J4~O~", "J4~A~"))), true)
			eq(#out, 1)
			eq(out[1].name, applicant); eq(out[1].to, officer)
			eq(H.Receive("WHISPER", officer, (offered.word:gsub("^J4~O~", "J4~A~"))), false, "a repeated ack")
			eq(#out, 1, "said once")
		end)
		ns.RecruitRanking = saved
		if not ok then error(err, 0) end
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
		-- (Changed on purpose in 1.5.9, the author's report 11-12: "Ele tem que ficar desativado se ele
		-- estava desativado... As configurações não devem mudar entre login": 1.5.8's Pass turned the
		-- automatic offers on for the session, and the next login turned them off again.)
		assert(Find(R.WhisperLines(), ns.L.RECRUIT_OVERFLOW_OFF), "passing leaves the automatic offers off")
		eq(H.AutoOn(), false)
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
		-- (Changed on purpose in 1.5.9, the author's report 11-12: "Ele tem que ficar desativado se ele
		-- estava desativado": the passed player goes, the automatic offers stay as they were.)
		assert(Find(R.WhisperLines(), ns.L.RECRUIT_OVERFLOW_OFF), "passing leaves the automatic offers off")
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
		-- The same player, now whispering JOIN, is never offered a second time, and (review of 1.5.8)
		-- his JOIN does not pop the same /ginvite here: the member has his name.
		R.OnWhisper("JOIN", wolf)
		local again = assert(R.requests[1])
		eq(again.name, wolf)
		eq(H.CanPass(again), false, "no duplicate offer of a name already handed on")
		eq(D.Find(DRAFT), nil, "no second invite of the same player here")
	end)
end)

-- Review of 1.5.8 (P3): a sighting offered to a member, then the same player's JOIN here: the
-- member's later claim must not get his name too, or both invite him.
test("recruit handoff (1.5.8): a sighting's offer claimed after the same player's JOIN gives no name", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		local wolf = "Lone Wolf-" .. home
		local tick = ScanOne(scene, wolf)
		tick()
		local draft = assert(D.Find(DRAFT))
		local row = draft.data.candidate
		draft.def.OnButton2(draft, draft.data)
		draft:Hide()
		scene.tick()
		eq(H.Receive("WHISPER", mate, (assert(scene.packets[1]).word:gsub("^J4~P~", "J4~V~"))), true)
		scene.tick()
		local offer = assert(scene.packets[2])
		eq(H.State(row), "offered")
		R.OnWhisper("JOIN", wolf)
		local join = assert(D.Find(DRAFT), "his JOIN pops up here")
		eq(join.data.req.name, wolf)
		eq(H.Receive("WHISPER", mate, (offer.word:gsub("^J4~O~", "J4~C~"))), false, "the claim is refused")
		eq(#scene.packets, 2, "his name does not go out to the member as well")
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
				-- (1.5.8, the author: the popup closes on the paste in chat, not when chat opens.)
				eq(D.Find(DRAFT), draft, "the popup waits for the paste")
				draft:Hide()
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

-- Review of 1.5.8 (P2): what the limit sent on, when no member claimed it, never came back to his
-- own popups once the minute was over ("lines them up for him up to his 10 a minute"). A player he
-- passed himself stays passed.
test("recruit handoff (1.5.8): what the invite limit sent on comes back to his popups when the minute is over", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		local savedUtil = ChatFrameUtil
		ChatFrameUtil = { OpenChat = function() end }
		local ok, err = pcall(function()
			for i = 1, 10 do R.OnWhisper("JOIN", ("Quick %d-%s"):format(i, home)) end
			for i = 1, 10 do
				local open = D.Find(DRAFT)
				if open then open:Hide() end
				eq(R.Accept(R.requests[i]), true)
				local draft = assert(D.Find(DRAFT))
				draft.def.extra.onClick(draft, draft.data)
				draft:Hide() -- (1.5.8: the paste in chat closes it)
			end
			eq(R.AtInviteLimit(), true)
			-- With the offers off, the popup offers Pass, and his click passes this one for good.
			scene.now = scene.now + 21
			R.OnWhisper("JOIN", "Passed Recruit-" .. home)
			local passed = R.requests[#R.requests]
			local draft = assert(D.Find(DRAFT))
			eq(draft.data.req, passed)
			draft.def.OnButton2(draft, draft.data)
			draft:Hide()
			-- (Changed on purpose in 1.5.9, the author's report 11-12: "Ele tem que ficar desativado se ele
			-- estava desativado": his Pass leaves the automatic offers off; he turns them on himself.)
			eq(H.AutoOn(), false, "his Pass leaves the automatic offers off")
			assert(Find(R.WhisperLines(), ns.L.RECRUIT_OVERFLOW_OFF)).onClick()
			eq(H.AutoOn(), true, "his own click turns them on")
			-- With the offers on, the limit sends the next JOIN and sighting on.
			scene.now = scene.now + 21
			R.OnWhisper("JOIN", "Held Recruit-" .. home)
			local held = R.requests[#R.requests]
			eq(held.passWanted, true, "at the limit the JOIN goes to the other members")
			local tick = ScanOne(scene, "Held Walker-" .. home)
			tick()
			eq(D.Find(DRAFT), nil, "nor does the sighting pop up at the limit")
			scene.tick()
			assert(assert(scene.packets[1]).word:match("^J4~P~"), "the probe goes out, and nobody answers")
			scene.tick()
			eq(D.Find(DRAFT), nil, "still at the limit, nothing comes back")
			-- The minute is over and no member claimed them.
			scene.now = scene.now + 19
			eq(R.AtInviteLimit(), false)
			scene.tick()
			local back = assert(D.Find(DRAFT), "the JOIN the limit sent on pops up here again")
			eq(back.data.req, held)
			eq(held.passWanted, nil)
			assert(back.def.button2Shown(back, back.data), "and can still be passed by hand")
			eq(back.text:find(ns.L.RECRUIT_INVITE_LIMIT_PASS:format(10), 1, true), nil)
			eq(passed.passWanted, true, "the one he passed himself stays with the other members")
			back:Hide()
			tick()
			local walker = assert(D.Find(DRAFT), "the sighting the limit sent on pops up again too")
			eq(walker.data.candidate.full, "Held Walker-" .. home)
			eq(walker.data.candidate.passWanted, nil)
		end)
		ChatFrameUtil = savedUtil
		if not ok then error(err, 0) end
	end)
end)

-- Review of 1.5.8 (P2): with the offers off again, what the limit sent on comes back at once (its
-- popup says the limit and offers Pass), unless a member's claim is under way.
test("recruit handoff (1.5.8): turning the offers off brings back what the limit sent on", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		local savedUtil = ChatFrameUtil
		ChatFrameUtil = { OpenChat = function() end }
		local ok, err = pcall(function()
			for i = 1, 10 do R.OnWhisper("JOIN", ("Rapid %d-%s"):format(i, home)) end
			for i = 1, 10 do
				local open = D.Find(DRAFT)
				if open then open:Hide() end
				eq(R.Accept(R.requests[i]), true)
				local draft = assert(D.Find(DRAFT))
				draft.def.extra.onClick(draft, draft.data)
				draft:Hide() -- (1.5.8: the paste in chat closes it)
			end
			eq(H.ToggleAuto(), true)
			scene.now = scene.now + 21
			R.OnWhisper("JOIN", "Offered Recruit-" .. home)
			local offered = R.requests[#R.requests]
			scene.now = scene.now + 21
			R.OnWhisper("JOIN", "Waiting Recruit-" .. home)
			local waiting = R.requests[#R.requests]
			eq(offered.passWanted, true); eq(waiting.passWanted, true)
			scene.tick()
			eq(H.Receive("WHISPER", mate, (assert(scene.packets[1]).word:gsub("^J4~P~", "J4~V~"))), true)
			scene.tick()
			eq(H.State(offered), "offered", "the first one is offered to a member")
			local queued = #scene.later
			eq(H.ToggleAuto(), false)
			for i = queued + 1, #scene.later do scene.later[i]() end
			local back = assert(D.Find(DRAFT), "the one nobody took pops up here")
			eq(back.data.req, waiting)
			assert(back.text:find(ns.L.RECRUIT_INVITE_LIMIT_PASS:format(10), 1, true), "saying the limit is reached")
			eq(offered.passWanted, true, "an offer under way stays with the member")
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

-- Review of 1.5.8 (P3): the probes rotated only over the members whose hello this client heard, so
-- one who accepts handoffs but was never heard was never asked. After each turn over the known ones,
-- one probe goes to the next of the others.
test("recruit overflow (1.5.8): after a turn over the known members a probe goes to one not heard from", function()
	WithHandoff(function(scene)
		local V = ns.Versions
		local saved = V.HasOlympus
		local second, unheard = "Second Member-" .. home, "Unheard Member-" .. home
		ns.Roster.online = { { name = mate }, { name = second }, { name = unheard } }
		ns.Roster.RankOf = function(name)
			if name == me then return 5 end
			if name == mate or name == second or name == unheard then return 6 end
		end
		local ok, err = pcall(function()
			V.HasOlympus = function(name) return name == mate or name == second end
			for i = 1, 3 do R.OnWhisper("JOIN", ("Turn Queue %d-%s"):format(i, home)) end
			eq(H.ToggleAuto(), true)
			local asked = {}
			for i = 1, 6 do
				scene.tick()
				asked[i] = assert(scene.packets[i], "one probe a step").peer
				scene.now = scene.now + 21
			end
			eq(asked[1], mate); eq(asked[2], second)
			eq(asked[3], unheard, "after the known members, the one not heard from is asked")
			eq(asked[4], mate); eq(asked[5], second); eq(asked[6], unheard)
		end)
		V.HasOlympus = saved
		if not ok then error(err, 0) end
	end)
end)

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

test("recruit log (1.5.8): a JOIN, its popup and command, and a handoff each way are logged, applicants by tag", function()
	WithHandoff(function(scene)
		WithLog(function()
			local D = Dialogs()
			ns.Dialog = D
			local savedUtil = ChatFrameUtil
			ChatFrameUtil = { OpenChat = function() end }
			local ok, err = pcall(function()
				local tag = H.Tag(applicant)
				assert(tag:match("^Ne%x%x%x%x$"), "two letters and four hex digits: " .. tag)
				eq(H.Tag("New Recruit"), tag, "the same player, with or without his realm, has the same tag")
				assert(H.Tag("Other Recruit-" .. home) ~= tag)
				R.OnWhisper("JOIN", applicant)
				assert(LogHas("JOIN " .. tag), "the JOIN whisper")
				local draft = assert(D.Find(DRAFT))
				assert(LogHas("POPUP " .. tag .. " auto"), "its popup, shown on its own")
				eq(R.LastInviteAt(), nil)
				draft.def.extra.onClick(draft, draft.data)
				assert(LogHas("TOCHAT " .. tag .. " 1/10"), "the command taken to chat")
				-- (Review of 1.5.9) When: the recruiting ranking for everyone reads the guild's log a while after
				-- it, for his own report of the join (RecruitRanking.ReadWanted).
				eq(R.LastInviteAt(), scene.now)
				-- (Since the 1.5.8 merge the popup stays until the command is pasted into chat, which
				-- closes it: the player pastes.)
				draft:Hide()
				-- He passes the next JOIN; a member answers the probe, claims and gets the name.
				local second = "Second Recruit-" .. home
				R.OnWhisper("JOIN", second)
				local req = R.requests[#R.requests]
				eq(req.name, second)
				eq(H.Pass(req), true)
				local tag2 = H.Tag(second)
				assert(LogHas("PASS " .. tag2), "his Pass")
				scene.tick()
				local probe = assert(scene.packets[#scene.packets])
				assert(probe.word:match("^J4~P~"))
				assert(LogHas("TX probe > Guild Recruiter"), "the probe sent")
				eq(H.Receive("WHISPER", mate, (probe.word:gsub("^J4~P~", "J4~V~"))), true)
				assert(LogHas("RX available < Guild Recruiter"), "the member's answer")
				scene.tick()
				local offer = assert(scene.packets[#scene.packets])
				assert(offer.word:match("^J4~O~"))
				assert(LogHas("TX offer > Guild Recruiter"), "the offer sent")
				eq(H.Receive("WHISPER", mate, (offer.word:gsub("^J4~O~", "J4~C~"))), true)
				assert(LogHas("RX claim < Guild Recruiter"), "the claim heard")
				assert(LogHas("TX name " .. tag2 .. " > Guild Recruiter"), "the name sent, by tag")
				eq(H.Receive("WHISPER", mate, (offer.word:gsub("^J4~O~", "J4~A~"))), true)
				assert(LogHas("HANDED " .. tag2 .. " > Guild Recruiter"), "handed off to the member")
				eq(H.Receive("WHISPER", mate, (offer.word:gsub("^J4~O~", "J4~A~"))), false)
				assert(LogHas("REFUSED ack < Guild Recruiter"), "a repeated ack is refused, and said")
				-- The other way: this member accepts handoffs and takes one from his guildmate.
				eq(H.Toggle(), true)
				local third = "Third Recruit-" .. home
				eq(H.Receive("WHISPER", mate, Packet(scene, "O", own, own, nil, "77-ab-1")), true)
				assert(LogHas("RX offer < Guild Recruiter"), "the offer heard")
				local ask = assert(D.Find(CLAIM), "the Claim question")
				eq(H.Claim(ask.data), true)
				assert(LogHas("TX claim > Guild Recruiter"), "his claim sent")
				eq(H.Receive("WHISPER", mate, Packet(scene, "N", own, own, third, "77-ab-1")), true)
				local tag3 = H.Tag(third)
				assert(LogHas("RX name " .. tag3 .. " < Guild Recruiter"), "the name received, by tag")
				LogNever("New Recruit")
				LogNever("Second Recruit")
				LogNever("Third Recruit")
				-- /oly bug: a summary line and the newest lines; /oly recruit log: all of it, to copy.
				local bug = H.BugLines(40)
				-- (Changed on purpose in 1.5.9, the author's report 11-12: "Ele tem que ficar desativado se
				-- ele estava desativado": his Pass above left the automatic offers off.)
				assert(bug[1]:find("^Recruiting: recruiting on, can invite on, accepting handoffs on, automatic offers off, scan off, invites this minute 1/10"), bug[1])
				assert(#bug <= 41)
				-- (WithHandoff gives the census an empty realm store; the status line counts its guilds.)
				ns.rdb.guilds = ns.rdb.guilds or {}
				local report = ns.BuildBugReport()
				assert(report:find("Recruiting: recruiting on", 1, true), "the bug report has the recruiting section")
				assert(report:find("HANDED " .. tag2 .. " > Guild Recruiter", 1, true))
				local savedUI, copied = rawget(ns, "UI"), nil
				ns.UI = { ShowCopy = function(title, text, _, opts) copied = { title = title, text = text, opts = opts } end }
				local okSlash, errSlash = pcall(SlashCmdList.OLYMPUS, "recruit log")
				ns.UI = savedUI
				assert(okSlash, errSlash)
				assert(copied, "/oly recruit log opens the copy window")
				eq(copied.opts.key, "recruitlog")
				eq(copied.opts.big, true)
				assert(copied.text:find("TX name " .. tag2 .. " > Guild Recruiter", 1, true))
			end)
			ChatFrameUtil = savedUtil
			if not ok then error(err, 0) end
		end)
	end)
end)

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

test("recruit handoff simulation (1.5.8): forty JOINs at a busy recruiter each end with exactly one inviter", function()
	WithHandoff(function(scene)
		local savedUtil, savedRank, savedOnline = ChatFrameUtil, ns.Roster.RankOf, ns.Roster.online
		ChatFrameUtil = { OpenChat = function() end }
		local world = { scene = scene, queue = {}, byName = {}, clients = {}, sent = {}, taken = {} }
		local ok, err = pcall(function()
			local function Full(short) return short .. "-" .. home end
			local busy = SimClient(world, Full("Busy Recruiter"))
			local ableOne = SimClient(world, Full("Able Inviter"))
			local ableTwo = SimClient(world, Full("Ready Inviter"))
			local full = SimClient(world, Full("Full Inviter"))
			local offA = SimClient(world, Full("Quiet Member"))
			local offB = SimClient(world, Full("Silent Member"))
			local ranks = {}
			ns.Roster.online = {}
			for i, c in ipairs(world.clients) do
				ranks[c.name] = i == 1 and 0 or 2
				ns.Roster.online[#ns.Roster.online + 1] = { name = c.name }
			end
			ns.Roster.RankOf = function(name) return ranks[ns.FullName(name)] end
			for _, c in ipairs(world.clients) do eq(c.R.ToggleWhisperRecruiting(), true, c.name .. " recruits") end
			for _, c in ipairs({ ableOne, ableTwo, full }) do eq(c.H.Toggle(), true, c.name .. " accepts handoffs") end
			-- A member's own JOINs, each taken to chat: his invite limit, reached the real way.
			local own = 0
			local function FillLimit(c)
				while not c.R.AtInviteLimit() do
					own = own + 1
					local walker = ("Own Walker %s-%s"):format(("abcdefghijklmnopqrstuvwxyz"):sub(own % 26 + 1, own % 26 + 1) .. own, home)
					c.R.OnWhisper("JOIN", walker)
					local req = c.R.requests[#c.R.requests]
					assert(req and req.name == walker)
					if not c.D.Find(DRAFT, nil) or c.D.Find(DRAFT).data.req ~= req then c.R.Accept(req) end
					local draft = assert(c.D.Find(DRAFT))
					draft.def.extra.onClick(draft, draft.data)
					while c.D.Find(DRAFT) do c.D.Find(DRAFT):Hide() end
				end
			end
			FillLimit(busy)
			eq(busy.R.AtInviteLimit(), true, "the busy recruiter is at his limit")
			eq(busy.H.ToggleAuto(), true, "with the automatic offers on")
			FillLimit(full)
			-- (A long run fills more than the ring holds: here each copy keeps all of it, to check every handoff.)
			for _, c in ipairs(world.clients) do c.H.LOG_MAX = 100000 end
			local applicants, tags = {}, {}
			for i = 1, 40 do
				applicants[i] = Full(("Applicant %s"):format(("abcdefghijklmnopqrstuvwxyzabcdefghijklmn"):sub(i, i) .. i))
				tags[applicants[i]] = busy.H.Tag(applicants[i])
			end
			local isApplicant = {}
			for _, name in ipairs(applicants) do isApplicant[name] = true end
			local next, start = 1, scene.now
			local function Resolved()
				local count = 0
				for _, name in ipairs(applicants) do
					local n = 0
					for _, p in ipairs(world.sent) do if p.op == "N" and p.name == name then n = n + 1 end end
					for _, t in ipairs(world.taken) do if t.by == busy and t.name == name then n = n + 1 end end
					if n > 0 then count = count + 1 end
				end
				return count
			end
			while scene.now - start < 1200 do
				scene.now = scene.now + 1
				if next <= #applicants and (scene.now - start) % 5 == 0 then
					busy.R.OnWhisper("JOIN", applicants[next])
					next = next + 1
				end
				FillLimit(full)
				for _, c in ipairs(world.clients) do SimStep(world, c) end
				SimDeliver(world)
				-- What each member does with what is on his screen.
				for _, c in ipairs({ ableOne, ableTwo, full }) do
					local ask = c.D.Find(CLAIM)
					if ask then
						ask:Hide()
						ask.def.OnAccept(ask, ask.data)
					end
				end
				SimDeliver(world)
				for _, c in ipairs({ busy, ableOne, ableTwo }) do SimTake(c, world) end
				SimDeliver(world)
				if next > #applicants and Resolved() == #applicants then break end
			end
			-- Every JOIN ended with exactly one inviter: one member who claimed it, or the busy
			-- recruiter himself once his minute cleared, never both and never two members.
			local handedTo, takenBy = {}, {}
			for _, p in ipairs(world.sent) do
				if p.op == "N" then
					assert(isApplicant[p.name], "only the applicants' names are handed on")
					handedTo[p.name] = handedTo[p.name] or {}
					table.insert(handedTo[p.name], p)
				end
			end
			for _, t in ipairs(world.taken) do
				if t.by == busy and isApplicant[t.name] then takenBy[t.name] = (takenBy[t.name] or 0) + 1 end
			end
			local handed, back = 0, 0
			for _, name in ipairs(applicants) do
				local n = handedTo[name] and #handedTo[name] or 0
				local own = takenBy[name] or 0
				eq(n + own, 1, "exactly one inviter for " .. tags[name] .. " (handed " .. n .. ", his own " .. own .. ")")
				if n == 1 then
					handed = handed + 1
					local p = handedTo[name][1]
					assert(p.to == ableOne or p.to == ableTwo, "only a member who accepts and can invite gets a name")
					-- The name went only after that member's claim of that very offer.
					local claimed, offered = false, false
					for _, q in ipairs(world.sent) do
						if q.id == p.id and q.op == "O" and q.to == p.to and q.at <= p.at then offered = true end
						if q.id == p.id and q.op == "C" and q.from == p.to and q.at <= p.at then claimed = true end
					end
					assert(offered and claimed, "the name followed an offer and its claim")
					-- Both sides' logs show it: sent on one, received on the other.
					local short = ns.ShortName(p.to.name)
					local sentLine, gotLine = false, false
					for _, line in ipairs(busy.ns.db.recruitLog) do
						if line:find("TX name " .. tags[name] .. " > " .. short, 1, true) then sentLine = true end
					end
					for _, line in ipairs(p.to.ns.db.recruitLog) do
						if line:find("RX name " .. tags[name] .. " < Busy Recruiter", 1, true) then gotLine = true end
					end
					assert(sentLine, "the busy recruiter's log shows the name sent to " .. short)
					assert(gotLine, short .. "'s log shows the name received")
				else
					back = back + 1
				end
			end
			-- Each command taken to chat says how many the minute holds, never more than the limit.
			for _, c in ipairs({ busy, ableOne, ableTwo, full }) do
				for _, line in ipairs(c.ns.db.recruitLog) do
					local n = line:match(" TOCHAT .- (%d+)/10$")
					assert(not n or tonumber(n) <= 10, "a minute's count past the limit: " .. line)
				end
			end
			assert(handed > 0, "some JOINs were handed on")
			assert(back > 0, "some came back to his own popups once his minute cleared")
			-- Nobody else ever got an offer or a name, and no member got more than ten names a minute.
			for _, p in ipairs(world.sent) do
				if p.op == "O" or p.op == "N" then
					assert(p.to == ableOne or p.to == ableTwo, "no offer or name to " .. p.to.name)
				end
			end
			for _, c in ipairs({ ableOne, ableTwo }) do
				local times = {}
				for _, p in ipairs(world.sent) do if p.op == "N" and p.to == c then times[#times + 1] = p.at end end
				for i = 1, #times do
					local inMinute = 0
					for j = i, #times do if times[j] - times[i] < 60 then inMinute = inMinute + 1 end end
					assert(inMinute <= 10, c.name .. " was given more than ten names in a minute")
				end
			end
			-- The member at his own limit and the two who do not accept were asked and said no.
			local probed = {}
			for _, p in ipairs(world.sent) do if p.op == "P" then probed[p.to] = true end end
			assert(probed[full] or probed[offA] or probed[offB], "the probes also reached the members who said no")
			-- (Review of 1.5.8) Each one asked answered with a no, so the next member was asked at once.
			local declined = {}
			for _, p in ipairs(world.sent) do if p.op == "D" then declined[p.from] = true end end
			for _, c in ipairs({ full, offA, offB }) do
				if probed[c] then assert(declined[c], c.name .. " said no to the probe") end
			end
			for _, line in ipairs(busy.ns.db.recruitLog) do
				for _, name in ipairs(applicants) do assert(not line:find(ns.ShortName(name), 1, true), "no applicant's name in the log") end
			end
		end)
		ChatFrameUtil, ns.Roster.RankOf, ns.Roster.online = savedUtil, savedRank, savedOnline
		if not ok then error(err, 0) end
	end)
end)

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
				assert(out:find("recruiting on, can invite on", 1, true), "with the summary")
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
test("recruit overflow (review of 1.5.8): a member who takes no names says no to a probe at once", function()
	WithHandoff(function(scene)
		WithLog(function()
			local function Probe(id)
				return ("J4~P~%s~%d~ForeverPvE~Alliance~%s~%s~"):format(id, scene.now + 20, own, own)
			end
			eq(H.Accepting(), false)
			eq(H.Receive("WHISPER", mate, Probe("1-a-1")), true, "the probe is answered")
			local no = assert(scene.packets[1], "a no goes back")
			eq(no.peer, mate)
			assert(no.word:match("^J4~D~1%-a%-1~"), no.word)
			eq(no.word:sub(-1), "~", "the no carries no name")
			assert(LogHas("TX declined > Guild Recruiter"), "his no, in his log")
			eq(H.Receive("WHISPER", mate, Probe("1-a-2")), false, "one answer each few seconds at most")
			eq(#scene.packets, 1)
			-- Taking handoffs he is available, as before.
			scene.now = scene.now + 9
			eq(H.Toggle(), true)
			eq(H.Receive("WHISPER", mate, Probe("1-a-3")), true)
			assert(scene.packets[2].word:match("^J4~V~"), "taking handoffs, he says yes")
			-- A member the game does not let invite says no too.
			scene.now = scene.now + 9
			scene.permission = false
			eq(H.Receive("WHISPER", mate, Probe("1-a-4")), true)
			assert(scene.packets[3].word:match("^J4~D~"), "a member who may not invite says no")
			eq(H.Receive("WHISPER", mate, Packet(scene, "O", own, own, nil, "1-a-5")), false, "and takes no offer")
		end)
	end)
end)

test("recruit overflow (review of 1.5.8): a no sends the next probe a second later, not after twenty", function()
	WithHandoff(function(scene)
		for i = 1, 3 do R.OnWhisper("JOIN", ("Waiting %d-%s"):format(i, home)) end
		local nextMember = "Next Member-" .. home
		ns.Roster.online = { { name = mate }, { name = nextMember } }
		local rank = ns.Roster.RankOf
		ns.Roster.RankOf = function(name) if name == nextMember then return 2 end return rank(name) end
		eq(H.ToggleAuto(), true)
		scene.tick()
		local first = assert(scene.packets[1]); assert(first.word:match("^J4~P~"))
		local no = (first.word:gsub("^J4~P~", "J4~D~"))
		eq(H.Receive("WHISPER", nextMember == first.peer and mate or nextMember, no), false, "only the member asked can say no")
		eq(H.Receive("WHISPER", first.peer, no), true, "his no is heard")
		eq(H.Receive("WHISPER", first.peer, no), false, "once")
		eq(H.Receive("WHISPER", first.peer, (first.word:gsub("^J4~P~", "J4~V~"))), false, "nor a yes after his no")
		scene.now = scene.now + 1
		local later = scene.later
		scene.later = {}
		for _, fn in ipairs(later) do fn() end
		local second = assert(scene.packets[2], "the next probe goes a second later, not after the first one's twenty")
		assert(second.word:match("^J4~P~"))
		assert(second.peer ~= first.peer, "to the next member")
		for _, req in ipairs(R.requests) do eq(H.State(req), nil, "no applicant left the local queue") end
	end)
end)

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
test("recruit handoff (1.5.9): a passed JOIN of a player who declined here is taken; a sighting of him is not", function()
	WithHandoff(function(scene)
		WithLog(function()
			WithDecline(function()
				local D = Dialogs()
				ns.Dialog = D
				-- He whispered JOIN here, this member took his invite to chat, and he declined it.
				R.OnWhisper("JOIN", applicant)
				local draft = assert(D.Find(DRAFT), "his JOIN popup")
				draft.def.extra.onClick(draft, draft.data) -- Ctrl+C
				draft:Hide()
				eq(R.OnSystemLine(DECLINE:format("New Recruit")), true, "he declined this member's invite")
				eq(#R.requests, 0)
				scene.now = scene.now + R.REQUEST_EACH + 1 -- (minutes later, he asks another member)
				eq(H.Toggle(), true, "this member accepts handoffs")
				-- A member's sighting of him: refused when the name comes, and said in the log.
				local sighting = "1234-ab-1-0"
				eq(H.Receive("WHISPER", mate, Packet(scene, "O", own, own, nil, sighting)), true)
				local ask = assert(D.Find(CLAIM))
				ask:Hide()
				eq(H.Claim(ask.data), true)
				local sent = #scene.packets
				eq(H.Receive("WHISPER", mate, Packet(scene, "N", own, own, applicant, sighting)), false, "a sighting of him is not taken")
				eq(#R.requests, 0)
				eq(#scene.packets, sent, "no acknowledgement")
				assert(LogHas("DECLINED " .. H.Tag(applicant) .. " handoff not taken"))
				eq(R.Declined(applicant), true)
				-- His JOIN, passed on by a member (three parts, as a 1.5.8 member's offer too): taken.
				local join = "1235-ab-2"
				eq(H.Receive("WHISPER", mate, Packet(scene, "O", own, own, nil, join)), true)
				ask = assert(D.Find(CLAIM))
				ask:Hide()
				eq(H.Claim(ask.data), true)
				eq(H.Receive("WHISPER", mate, Packet(scene, "N", own, own, applicant, join)), true, "his JOIN is taken")
				local req = assert(R.requests[1])
				eq(req.name, applicant)
				assert(scene.packets[#scene.packets].word:match("^J4~A~1235%-ab%-2~"), "and acknowledged")
				eq(R.Declined(applicant), false, "his own JOIN clears the decline here")
				assert(LogHas("UNDECLINED " .. H.Tag(applicant)))
				eq(assert(D.Find(DRAFT), "his popup").data.req, req)
			end)
		end)
	end)
end)

test("recruit handoff (1.5.9): a scanned player's offer says it is a sighting; a JOIN's reads as 1.5.8's", function()
	WithHandoff(function(scene)
		WithDecline(function()
			local D = Dialogs()
			ns.Dialog = D
			R.OnWhisper("JOIN", applicant)
			local req = assert(R.requests[1])
			assert(D.Find(DRAFT)):Hide()
			eq(H.Offer(req, mate, own), true)
			local joinId = assert(scene.packets[#scene.packets].word:match("^J4~O~([^~]+)~"))
			assert(joinId:find("^%d+%-%x+%-%d+$"), "a JOIN's offer id, three parts: " .. joinId)
			local wolf = "Lone Wolf-" .. home
			local tick = ScanOne(scene, wolf)
			tick()
			local draft = assert(D.Find(DRAFT), "his invite popup")
			local row = draft.data.candidate
			draft:Hide()
			eq(H.Offer(row, mate, own), true)
			local scanId = assert(scene.packets[#scene.packets].word:match("^J4~O~([^~]+)~"))
			assert(scanId:find("^%d+%-%x+%-%d+%-0$"), "a sighting's, a fourth part: " .. scanId)
			assert(#scanId <= 40, "short enough for any member's addon")
		end)
	end)
end)

-- The same finding end to end: two members' own copies of the addon. He declined B's invite; his JOIN
-- reaches A, who passes it; B claims, gets the name and takes him; A's request ends handed.
test("recruit handoff simulation (1.5.9): a JOIN passed to the member whose invite he declined ends with that member", function()
	WithHandoff(function(scene)
		WithDecline(function()
			local savedRank, savedOnline = ns.Roster.RankOf, ns.Roster.online
			local world = { scene = scene, queue = {}, byName = {}, clients = {}, sent = {}, taken = {} }
			local ok, err = pcall(function()
				local function Full(short) return short .. "-" .. home end
				local A = SimClient(world, Full("Busy Recruiter"))
				local B = SimClient(world, Full("Able Inviter"))
				ns.Roster.online = { { name = A.name }, { name = B.name } }
				local ranks = { [A.name] = 0, [B.name] = 2 }
				ns.Roster.RankOf = function(name) return ranks[ns.FullName(name)] end
				eq(A.R.ToggleWhisperRecruiting(), true); eq(B.R.ToggleWhisperRecruiting(), true)
				eq(B.H.Toggle(), true, "B accepts handoffs")
				local X = Full("Comeback Kid")
				-- He whispered JOIN to B, B took his invite to chat, and he declined it.
				B.R.OnWhisper("JOIN", X)
				SimTake(B, world)
				eq(#world.taken, 1, "B's invite went to chat")
				eq(B.R.OnSystemLine(DECLINE:format("Comeback Kid")), true, "he declined B's invite")
				eq(B.R.Declined(X), true)
				scene.now = scene.now + 601
				A.R.OnWhisper("JOIN", X) -- minutes later he asks A, on his own
				local req = assert(A.R.requests[1])
				local draft = assert(A.D.Find(DRAFT), "A's popup for him")
				eq(A.H.Pass(req), true, "A passes him on")
				draft:Hide()
				for _ = 1, 120 do
					scene.now = scene.now + 1
					for _, c in ipairs(world.clients) do SimStep(world, c) end
					SimDeliver(world)
					local ask = B.D.Find(CLAIM)
					if ask then ask:Hide(); ask.def.OnAccept(ask, ask.data) end
				end
				local named = 0
				for _, p in ipairs(world.sent) do if p.op == "N" and p.name == X then named = named + 1 end end
				eq(named, 1, "his name went to B once")
				eq(A.H.State(req), "assigned", "A's request ends handed to B")
				local mine = assert(B.D.Find(DRAFT), "B's popup for him")
				eq(mine.data.req.name, X)
				eq(B.R.Declined(X), false, "his JOIN cleared his decline at B")
				eq(A.D.Find(DRAFT), nil, "and A invites nobody twice")
			end)
			ns.Roster.RankOf, ns.Roster.online = savedRank, savedOnline
			if not ok then error(err, 0) end
		end)
	end)
end)

-- Review of 1.5.9 (P2): Pass turned the automatic offers on for the session, and the next login turned
-- them off again, a switch that changed between logins (the author, 11-12: "Ele tem que ficar
-- desativado se ele estava desativado... As configurações não devem mudar entre login"). The passed
-- JOIN still goes; the others waiting stay here, as the switch is off.
test("recruit handoff (1.5.9): Pass sends the passed JOIN on and leaves the automatic offers off", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		scene.locked = true
		for i = 1, 4 do R.OnWhisper("JOIN", ("Waiting %d-%s"):format(i, home)) end
		scene.locked = false
		local first = R.requests[1]
		eq(H.Pass(first), true)
		eq(H.AutoOn(), false, "the switch stays off")
		assert(Find(R.WhisperLines(), ns.L.RECRUIT_OVERFLOW_OFF), "and shows off")
		eq(R.Preference().offerOverflow, nil, "nor is it saved on")
		scene.tick()
		local probe = assert(scene.packets[1])
		assert(probe.word:match("^J4~P~"))
		eq(H.Receive("WHISPER", mate, (probe.word:gsub("^J4~P~", "J4~V~"))), true)
		scene.tick()
		assert(scene.packets[2].word:match("^J4~O~"))
		eq(H.State(first), "offered", "the passed JOIN goes")
		local sent = #scene.packets
		for _ = 1, 3 do
			scene.now = scene.now + 21
			scene.tick()
		end
		eq(#scene.packets, sent, "no probe for the three he did not pass")
		for i = 2, 4 do eq(H.State(R.requests[i]), nil, "a JOIN he did not pass stays here") end
		-- His own click turns the automatic offers on, and the three waiting then go on their own.
		assert(Find(R.WhisperLines(), ns.L.RECRUIT_OVERFLOW_OFF)).onClick()
		eq(H.AutoOn(), true)
		scene.tick()
		assert(scene.packets[sent + 1].word:match("^J4~P~"), "with the switch on, a probe for the waiting")
	end)
end)

-- Review of the 1.5.9 release (A-2): a Pass made while the automatic offers were on kept no timer of its
-- own, so once he turned the offers off before any member answered, what he passed got no probe and no
-- popup until it expired an hour later. What he passed by hand goes whatever the switch.
test("recruit handoff (1.5.9): a Pass made with the automatic offers on still goes after he turns them off", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		scene.locked = true
		for i = 1, 4 do R.OnWhisper("JOIN", ("Waiting %d-%s"):format(i, home)) end
		scene.locked = false
		assert(Id(R.WhisperLines(), "recruit-handoff-overflow"), "the automatic offers switch").onClick()
		eq(H.AutoOn(), true)
		local first = R.requests[1]
		eq(H.Pass(first), true)
		scene.tick = nil
		-- Off again, in Church > Invites, before any member answered.
		assert(Id(R.WhisperLines(), "recruit-handoff-overflow")).onClick()
		eq(H.AutoOn(), false)
		assert(scene.tick, "the probes go on for what he passed")
		scene.now = scene.now + 21
		scene.tick()
		local probe = assert(scene.packets[#scene.packets], "a probe")
		assert(probe.word:match("^J4~P~"), probe.word)
		eq(H.Receive("WHISPER", mate, (probe.word:gsub("^J4~P~", "J4~V~"))), true)
		scene.tick()
		assert(scene.packets[#scene.packets].word:match("^J4~O~"), "the offer")
		eq(H.State(first), "offered", "the JOIN he passed goes")
		eq(H.AutoOn(), false, "the switch stays as he set it")
		eq(R.Preference().offerOverflow, nil, "and is saved so")
	end)
end)

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
test("recruit Invites page (1.5.9): four sections in order under headings of one weight, the JOINs waiting inside Recruiting", function()
	WithHandoff(function(scene)
		UseCandidates()
		local L = ns.L
		eq(R.ToggleWhisperRecruiting(), false, "recruiting off first")
		local off = R.WhisperLines()
		eq(Headings(off), SECTIONS, "off, the four sections all the same")
		eq(off[1].text, L.RECRUIT_SECTION_RECRUITING, "the page opens with Recruiting's heading")
		local recruiting = SectionOf(off, "recruit-section-recruiting")
		eq(recruiting[2].id, "recruit-whisper-toggle", "its switch under it")
		assert(recruiting[2].text:find(L.RECRUIT_WHISPER_OFF, 1, true) and recruiting[2].onClick)
		assert(recruiting[3].text:find(L.RECRUIT_WHISPER_OFF_HINT, 1, true), "and what turning it on does")
		eq(SectionOf(off, "recruit-section-ads")[1].text, L.RECRUIT_ANNOUNCE_OPEN)
		-- (Review of 1.5.9: the ads too. They ask for JOIN whispers, which only Recruiting answers.)
		for _, id in ipairs({ "recruit-section-ads", "recruit-section-scan", "recruit-section-handoffs" }) do
			local section = SectionOf(off, id)
			eq(#section, 2, id .. ": its heading and one line")
			assert(section[2].text:find(L.RECRUIT_SECTION_NEEDS_ON, 1, true), id .. " says recruiting comes first")
		end
		for i = 2, #off do
			if off[i].header then eq(off[i - 1].gapAfter, true, "a gap before " .. off[i].id) end
		end

		eq(R.ToggleWhisperRecruiting(), true)
		R.OnWhisper("JOIN", "First Waiting-" .. home)
		R.OnWhisper("JOIN", "Second Waiting-" .. home)
		local on = R.WhisperLines()
		eq(Headings(on), SECTIONS, "on, with JOINs waiting: the same four headings, none for the JOINs")
		recruiting = SectionOf(on, "recruit-section-recruiting")
		assert(recruiting[2].text:find(L.RECRUIT_WHISPER_ON, 1, true))
		assert(recruiting[3].text:find(L.RECRUIT_WHISPER_HINT, 1, true))
		eq(recruiting[4].id, "recruit-whisper-arrival", "how a JOIN comes in")
		local count = assert(Id(recruiting, "recruit-requests"), "the JOINs waiting are in the Recruiting section")
		eq(count.text, L.JOIN_REQUESTS:format(2)); eq(count.header, nil); eq(count.indent, 1)
		local first = assert(Find(recruiting, "First Waiting"), "each JOIN under it")
		assert((first.indent or 0) >= 1, "one step in")
		assert(Find(recruiting, L.RECRUIT_WHISPER_PREPARE_BUTTON).indent >= 2, "and its actions one more")
		-- (Review of 1.5.9: every section alike, its switch under the heading and the switch's grey line
		-- under it, as Recruiting has them.)
		local scan = SectionOf(on, "recruit-section-scan")
		eq(scan[2].id, "recruit-candidate-toggle", "the scan's switch first in its section")
		assert(scan[3].text:find(L.RECRUIT_SCAN_HINT, 1, true), "then what it does")
		assert(SectionOf(on, "recruit-section-ads")[2].text:find(L.RECRUIT_ADS_HINT, 1, true))
		local handoffs = SectionOf(on, "recruit-section-handoffs")
		eq(handoffs[1].text, L.RECRUIT_SECTION_HANDOFFS .. " " .. L.RECRUIT_EXPERIMENTAL, "Experimental on the heading")
		eq(handoffs[2].id, "recruit-handoff-accept"); eq(handoffs[3].id, "recruit-handoff-overflow")
		assert(handoffs[4].text:find(L.RECRUIT_HANDOFFS_HINT, 1, true), "both handoff switches, then what they do")
		local tagged = 0
		for _, line in ipairs(on) do
			if line.text and line.text:find(L.RECRUIT_EXPERIMENTAL, 1, true) then tagged = tagged + 1 end
		end
		eq(tagged, 1, "said once, on the heading, not cut off the end of each switch")
	end)
end)

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
test("recruit handoff picker (1.5.9, regression): members who take handoffs come first, past the six highest ranks", function()
	WithHandoff(function(scene)
		local online, ranks = {}, { [me] = 5 }
		for i = 1, 7 do
			local name = ("Officer %s-%s"):format(string.char(64 + i), home)
			online[#online + 1] = { name = name }
			ranks[name] = 1
		end
		local plain, refuser = "Plain Taker-" .. home, "Officer B-" .. home
		online[#online + 1] = { name = plain }
		ranks[plain] = 6
		ns.Roster.online = online
		ns.Roster.RankOf = function(name) return ranks[name] end
		WithHellos({ { plain, Hello("1.5.9", true) }, { refuser, Hello("1.5.9", false) }, { "Officer C-" .. home, Hello("1.5.8") } }, function()
			R.OnWhisper("JOIN", applicant)
			assert(Find(R.RequestLines(true), ns.L.RECRUIT_HANDOFF_PICK)).onClick()
			local offers = {}
			for _, line in ipairs(R.RequestLines(true)) do
				if line.indent == 2 and line.onClick then offers[#offers + 1] = line.text end
			end
			eq(#offers, 6, "six members offered")
			assert(offers[1]:find("Plain Taker", 1, true), "the member whose hello says he takes handoffs first: " .. offers[1])
			assert(offers[2]:find("Officer C", 1, true), "then one known to run Olympus (1.5.8): " .. offers[2])
			for _, text in ipairs(offers) do
				eq(text:find("Officer B", 1, true), nil, "never one whose hello says he takes none")
			end
			-- The listed taker's offer goes to him.
			for _, line in ipairs(R.RequestLines(true)) do
				if line.text and line.text:find("Plain Taker", 1, true) and line.onClick then line.onClick(); break end
			end
			local offer = assert(scene.packets[1], "the offer went")
			eq(offer.peer, plain)
			assert(offer.word:match("^J4~O~"))
		end)
	end)
end)

-- 1.5.9, the review of 1.5.8 (throughput): a member without Olympus never answers a probe, and each
-- costs PROBE_TTL (20 s). Clients that take handoffs say so in their hello (Comm.Hello's "J"); the
-- probes ask them first, members known to run Olympus otherwise after a turn over them (a 1.5.8
-- hello has no flag yet), and never a member whose hello says he takes none or names a version
-- before handoffs. The unheard still get one probe after each turn (review of 1.5.8).
test("recruit overflow (1.5.9, regression): the probes ask members whose hello says they take handoffs first", function()
	WithHandoff(function(scene)
		local taker, mate158, old, refuser, quiet = "Taker Member-" .. home, "Older Member-" .. home,
			"Ancient Member-" .. home, "Refusing Member-" .. home, "Quiet Member-" .. home
		-- (Roster order: the unheard and the ones who can't take handoffs ahead of the taker.)
		ns.Roster.online = { { name = quiet }, { name = old }, { name = refuser }, { name = mate158 }, { name = taker } }
		ns.Roster.RankOf = function(name)
			if name == me then return 5 end
			for _, row in ipairs(ns.Roster.online) do if row.name == name then return 6 end end
		end
		WithHellos({ { taker, Hello("1.5.9", true) }, { mate158, Hello("1.5.8") }, { old, Hello("1.5.7") },
			{ refuser, Hello("1.5.9", false) } }, function()
			for i = 1, 3 do R.OnWhisper("JOIN", ("Flag Queue %d-%s"):format(i, home)) end
			eq(H.ToggleAuto(), true)
			local asked = {}
			for i = 1, 6 do
				scene.tick()
				asked[i] = assert(scene.packets[i], "one probe a step").peer
				scene.now = scene.now + 21
			end
			eq(asked[1], taker, "first the member whose hello says he takes handoffs")
			eq(asked[2], mate158, "after a turn over those, one whose 1.5.8 hello could not say")
			eq(asked[3], taker)
			eq(asked[4], quiet, "after a turn over both, one never heard from")
			eq(asked[5], taker); eq(asked[6], mate158)
			for _, peer in ipairs(asked) do
				assert(peer ~= old and peer ~= refuser, "never a client that can't take handoffs or said no: " .. peer)
			end
		end)
	end)
end)

-- Older clients only (no hello carries the flag): the 1.5.8 order, from the hellos themselves.
test("recruit overflow (1.5.9): with 1.5.8 clients only, those heard run Olympus first and the unheard after each turn", function()
	WithHandoff(function(scene)
		local first, second, quiet = "First Older-" .. home, "Second Older-" .. home, "Quiet Member-" .. home
		ns.Roster.online = { { name = quiet }, { name = first }, { name = second } }
		ns.Roster.RankOf = function(name)
			if name == me then return 5 end
			if name == first or name == second or name == quiet then return 6 end
		end
		WithHellos({ { first, Hello("1.5.8") }, { second, "H1~1.5.8~" .. home .. "~p~~~~R" } }, function()
			for i = 1, 3 do R.OnWhisper("JOIN", ("Old Queue %d-%s"):format(i, home)) end
			eq(H.ToggleAuto(), true)
			local asked = {}
			for i = 1, 6 do
				scene.tick()
				asked[i] = assert(scene.packets[i]).peer
				scene.now = scene.now + 21
			end
			eq(table.concat(asked, ","), table.concat({ first, second, quiet, first, second, quiet }, ","))
		end)
	end)
end)

-- 1.5.9: the flag a member's hello carries. "J", its 9th field, only while he takes handoffs; a quiet
-- member (other guildmates sort before him: he says hello every ten minutes) says it at his next tick
-- (HELLO_EVERY) after it turns, either way. A hello without it reads as before, here and on a 0.9.8
-- client (older clients read the fields before it), and the fields before it read the same with it.
test("recruit hello (1.5.9, regression): a member who takes handoffs says so in his hello at the next tick", function()
	WithHandoff(function(scene)
		local savedChat, savedTime = C_ChatInfo, GetTime
		local ok, err = pcall(function()
			local cns, deliver = FreshComm()
			-- Twelve guildmates who sort before this member: he is a quiet one.
			for i = 1, 12 do deliver("GUILD", ("Aa%02d Peer-%s"):format(i, home), Hello("1.5.8")) end
			local sent = {}
			C_ChatInfo.SendAddonMessage = function(_, msg, dist) sent[#sent + 1] = dist .. " " .. msg end
			local function Tick()
				local before, hello = #sent, nil
				cns.Comm.Hello()
				for _ = 1, 4 do cns.Comm.Pump() end
				for i = before + 1, #sent do if sent[i]:find("^GUILD H1~") then hello = sent[i] end end
				return hello
			end
			local first = assert(Tick(), "the first hello")
			-- (Changed on purpose, the review of 1.5.9: "j" says he takes none, so no guildmate reads it
			-- from his version, which a test build of 1.5.9 still names 1.5.8.)
			eq(first:match("^GUILD H1~[^~]*~[^~]*~[^~]*~[^~]*~[^~]*~[^~]*~[^~]*~[^~]*~([^~]*)"), "j", "j: he takes none")
			eq(Tick(), nil, "a quiet member says nothing more within ten minutes")
			eq(H.Toggle(), true, "he takes handoffs now")
			local flagged = assert(Tick(), "the next tick says so")
			eq(flagged:match("^GUILD H1~[^~]*~[^~]*~[^~]*~[^~]*~[^~]*~[^~]*~[^~]*~[^~]*~([^~]*)"), "J", "J, the 9th field")
			eq(flagged:match("^(.*)~J$"), first:match("^(.*)~j$"), "the fields before it as they were")
			eq(Tick(), nil, "once")
			eq(H.Toggle(), false)
			eq(Tick(), first, "turned off: the next tick says it, j again")

			-- A guildmate's client reads it; a hello without it reads as before.
			local reader, hear = FreshComm()
			reader.me = "Reader Member-" .. home -- (a client drops its own words)
			hear("GUILD", me, flagged:sub(7))
			hear("GUILD", mate, first:sub(7))
			local heard = reader.Comm.HandoffPeers()
			eq(heard.full[me].takes, true); eq(heard.full[me].version, ns.VERSION)
			eq(heard.full[mate].takes, false)
			eq(heard.short[ns.Fold(ns.ShortName(me))], heard.full[me], "by the short name too")
			eq(reader.Comm.PeerRealm(me), reader.Comm.PeerRealm(mate), "the realm field reads the same")
			-- A 0.9.8 client (the fixture) counts the flagged hello's version as any other.
			local oldest, hearOld = FreshComm(true)
			oldest.me = "Reader Member-" .. home
			hearOld("GUILD", me, flagged:sub(7))
			eq(oldest.Comm.PeerVersions()[ns.VERSION], 2, "ours and the flagged peer's, its flag ignored")
		end)
		C_ChatInfo, GetTime = savedChat, savedTime
		if not ok then error(err, 0) end
	end)
end)

---------------------------------------------------------------------------
-- The review of 1.5.9: the network fixes and Church > Invites, checked again.
---------------------------------------------------------------------------

-- Review of 1.5.9 (P2): the Offer picker asked Versions.HasOlympus of every member online it heard no
-- hello from, and each ask went through every hello heard: about 150 ms a redraw with 400 online and
-- 150 heard, against 0.1 ms in 1.5.8. The picker reads the hellos once now, in the same order.
test("recruit handoff picker (review of 1.5.9, regression): 400 online are listed from the hellos, none asked about one by one", function()
	WithHandoff(function(scene)
		local online, ranks, hellos = {}, { [me] = 5 }, {}
		local taker, first158, second158
		for i = 1, 400 do
			local name = ("Picker %s-%s"):format(Letters(i), home)
			online[i] = { name = name }
			ranks[name] = 6
			-- The last 150 heard: one takes handoffs, two run 1.5.8, the rest take none.
			if i == 399 then taker = name; hellos[#hellos + 1] = { name, Hello("1.5.9", true) }
			elseif i == 300 or i == 350 then
				if i == 300 then first158 = name else second158 = name end
				hellos[#hellos + 1] = { name, Hello("1.5.8") }
			elseif i > 250 then hellos[#hellos + 1] = { name, Hello("1.5.9", false) } end
		end
		ns.Roster.online = online
		ns.Roster.RankOf = function(name) return ranks[name] end
		local V = ns.Versions
		local saved, asked = V.HasOlympus, 0
		local ok, err = pcall(WithHellos, hellos, function()
			V.HasOlympus = function(...) asked = asked + 1; return saved(...) end
			R.OnWhisper("JOIN", applicant)
			assert(Find(R.RequestLines(true), ns.L.RECRUIT_HANDOFF_PICK)).onClick()
			asked = 0
			local offers = {}
			for _, line in ipairs(R.WhisperLines()) do
				if line.indent == 3 and line.onClick then offers[#offers + 1] = line.text end
			end
			eq(asked, 0, "no member online asked about one by one: the hellos are read once")
			eq(#offers, 6)
			assert(offers[1]:find(ns.ShortName(taker), 1, true), "the one whose hello says he takes them first: " .. offers[1])
			assert(offers[2]:find(ns.ShortName(first158), 1, true), "then the 1.5.8 ones: " .. offers[2])
			assert(offers[3]:find(ns.ShortName(second158), 1, true), offers[3])
			assert(offers[4]:find(ns.ShortName(online[1].name), 1, true), "then the unheard, in the roster's order: " .. offers[4])
		end)
		V.HasOlympus = saved
		if not ok then error(err, 0) end
	end)
end)

-- Review of 1.5.9 (P2): "takes none" was read from the version, a hello naming 1.5.9 or newer without
-- "J". This branch's builds still name 1.5.8, so a member running one with handoffs off was probed every
-- turn and listed; and a release after 1.5.9 would have read every 1.5.9 client, which takes handoffs
-- through the 1.5.8 words, as taking none. The hello says "j" now, and a hello with neither is asked.
test("recruit hello (review of 1.5.9, regression): a client that takes no handoffs says so, whatever version it names", function()
	WithHandoff(function(scene)
		local savedChat = C_ChatInfo
		local hello, oldCount
		local ok, err = pcall(function()
			local cns = FreshComm()
			local sent = {}
			C_ChatInfo.SendAddonMessage = function(_, msg, dist) sent[#sent + 1] = dist .. " " .. msg end
			cns.Comm.Hello(true)
			for _ = 1, 4 do cns.Comm.Pump() end
			for _, line in ipairs(sent) do if line:find("^GUILD H1~") then hello = line:sub(7) end end
			-- An older client reads it as any hello: a 0.9.8 one counts its version.
			local oldest, hearOld = FreshComm(true)
			oldest.me = "Reader Member-" .. home
			if hello then hearOld("GUILD", "Refusing Member-" .. home, hello) end
			oldCount = oldest.Comm.PeerVersions()[ns.VERSION]
		end)
		C_ChatInfo = savedChat
		if not ok then error(err, 0) end
		assert(hello, "this build's own hello went (the real Comm.Hello)")
		eq(H.Accepting(), false, "from a member with handoffs off")
		eq(oldCount, 2, "a 0.9.8 client counts its version as before")
		local refuser, newer, older = "Refusing Member-" .. home, "Newer Member-" .. home, "Older Member-" .. home
		ns.Roster.online = { { name = refuser }, { name = newer }, { name = older } }
		ns.Roster.RankOf = function(name)
			if name == me then return 5 end
			for _, row in ipairs(ns.Roster.online) do if row.name == name then return 6 end end
		end
		-- This build's hello; one naming a later version without the flag (a client from before it: it
		-- takes handoffs as 1.5.8 does); a 1.5.8 one.
		WithHellos({ { refuser, hello }, { newer, "H1~1.6.0~" .. home .. "~p~~~~R~N" }, { older, Hello("1.5.8") } }, function()
			R.OnWhisper("JOIN", applicant)
			assert(Find(R.RequestLines(true), ns.L.RECRUIT_HANDOFF_PICK)).onClick()
			local listed = {}
			for _, line in ipairs(R.RequestLines(true)) do
				if line.indent == 2 and line.onClick then listed[#listed + 1] = line.text end
			end
			local all = table.concat(listed, " | ")
			eq(all:find("Refusing Member", 1, true), nil, "not listed: his hello says he takes none (" .. all .. ")")
			assert(all:find("Newer Member", 1, true), "a hello without the flag is listed, whatever its version: " .. all)
			assert(all:find("Older Member", 1, true), all)
			for i = 1, 3 do R.OnWhisper("JOIN", ("Flag Wait %d-%s"):format(i, home)) end
			eq(H.ToggleAuto(), true)
			local asked = {}
			for i = 1, 4 do
				scene.tick()
				asked[i] = assert(scene.packets[i], "one probe a step").peer
				scene.now = scene.now + 21
			end
			for _, peer in ipairs(asked) do assert(peer ~= refuser, "never probed: his hello says he takes none") end
			eq(table.concat(asked, ","), table.concat({ newer, older, newer, older }, ","))
		end)
	end)
end)

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
test("recruit Invites page (review of 1.5.9, regression): every section its heading, its switches, then one grey line", function()
	WithHandoff(function(scene)
		UseCandidates()
		local function Check(lines, label)
			local i, sections = 1, 0
			while i <= #lines do
				local section = assert(lines[i].header and lines[i].id, label .. ": a heading at " .. i)
				sections = sections + 1
				local j = i + 1
				while lines[j] and not lines[j].header and lines[j].text and (lines[j].indent or 0) == 0 do
					assert(lines[j].onClick, label .. " " .. section .. ": a row at the left is a switch")
					j = j + 1
				end
				local note = assert(lines[j], label .. " " .. section .. ": a line under it")
				eq(note.indent, 1, label .. " " .. section .. ": its grey line one step in")
				eq(note.onClick, nil, label .. " " .. section .. ": a line to read")
				j = j + 1
				while lines[j] and not lines[j].header do
					if lines[j].text then
						assert((lines[j].indent or 0) >= 1, label .. " " .. section .. ": nothing at the left after it: " .. lines[j].text)
					end
					j = j + 1
				end
				i = j
			end
			eq(sections, 4, label .. ": four sections")
		end
		R.OnWhisper("JOIN", applicant)
		Check(R.WhisperLines(), "on")
		assert(Find(R.WhisperLines(), ns.L.RECRUIT_CANDIDATES_OFF)).onClick()
		H.Toggle()
		Check(R.WhisperLines(), "scan and handoffs on")
		eq(R.ToggleWhisperRecruiting(), false)
		Check(R.WhisperLines(), "off")
	end)
end)

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

test("recruit Invites page (review of 1.5.9, regression): no row is cut, in any language, with long names", function()
	WithHandoff(function(scene)
		UseCandidates()
		local L = ns.L
		-- Forever's names are "First Surname"; these (made up) are 18 characters.
		local function Name(first, last) return first .. " " .. last .. "-" .. home end
		local m1, m2, m3, m4 = Name("Sebastian", "Rockwell"), Name("Valentina", "Hawthorn"),
			Name("Christoph", "Lockhart"), Name("Theodora", "Blackwood")
		local joins = { Name("Ernestina", "Wrenford"), Name("Annabelle", "Thornton"), Name("Rosamunde", "Kingsley"),
			Name("Cassandra", "Holloway"), Name("Josephine", "Whitlock"), Name("Ferdinand", "Ashworth") }
		local scanned = { Name("Clementia", "Westbury"), Name("Benedicta", "Harcourt"), Name("Willemina", "Cromwell"),
			Name("Aurelius", "Pendleton") }
		ns.Roster.online = { { name = m1 }, { name = m2 }, { name = m3 }, { name = m4 } }
		local joined = joins[3]
		ns.Roster.RankOf = function(name)
			if name == me then return 0 end
			if name == m1 or name == m2 or name == m3 or name == m4 or (name == joined and scene.joined) then return 6 end
		end
		local savedList, savedChat = GetChannelList, C_ChatInfo
		GetChannelList = function() return 1, "General", false, 4, "LookingForGroup", false end
		C_ChatInfo = setmetatable({ GetChannelInfoFromIdentifier = function(name) return { zoneChannelID = #name } end },
			{ __index = savedChat })
		local ok, err = pcall(function()
			for _, name in ipairs(joins) do R.OnWhisper("JOIN", name) end
			scene.joined = true -- (the roster shows him in the guild since)
			local req = {}
			for _, r in ipairs(R.requests) do req[r.name] = r end
			-- Offered, waiting for the member's claim; handed off; refused by the game.
			eq(H.Offer(req[joins[4]], m1, own), true)
			eq(H.Offer(req[joins[5]], m2, own), true)
			local offer = scene.packets[#scene.packets].word
			eq(H.Receive("WHISPER", m2, (offer:gsub("^J4~O~", "J4~C~"))), true)
			eq(H.Receive("WHISPER", m2, (offer:gsub("^J4~O~", "J4~A~"))), true)
			ns.Dialog = Dialogs()
			eq(R.Accept(req[joins[6]]), true)
			-- The scan: one listed, one passed on, one offered, one handed off.
			assert(Find(R.WhisperLines(), L.RECRUIT_CANDIDATES_OFF)).onClick()
			local rows = {}
			for _, name in ipairs(scanned) do R.Candidates.ObserveWho(name, "", "Human") end
			R.Candidates.EachRow(function(row) rows[row.full] = row end)
			eq(H.Pass(assert(rows[scanned[2]])), true)
			eq(H.Offer(assert(rows[scanned[3]]), m1, own), true)
			eq(H.Offer(assert(rows[scanned[4]]), m2, own), true)
			offer = scene.packets[#scene.packets].word
			eq(H.Receive("WHISPER", m2, (offer:gsub("^J4~O~", "J4~C~"))), true)
			eq(H.Receive("WHISPER", m2, (offer:gsub("^J4~O~", "J4~A~"))), true)
			-- Handoffs taken here: one offer to claim, one claimed and waiting for its name.
			H.Toggle()
			eq(H.Receive("WHISPER", m3, Packet(scene, "O", own, own, nil, "1111-aa-1")), true)
			eq(H.Receive("WHISPER", m4, Packet(scene, "O", own, own, nil, "2222-bb-2")), true)
			assert(Find(R.WhisperLines(), L.RECRUIT_HANDOFF_CLAIM:format("Theodora Blackwood", own))).onClick()
			-- A reminder, for its line; and the picker open on the last JOIN (an offer closes it).
			Id(R.WhisperLines(), "recruit-announcement-reminder").filters[1].options[2].onClick()
			assert(Find(R.RequestLines(true), L.RECRUIT_HANDOFF_PICK)).onClick()

			local page = R.WhisperLines()
			local function Has(text) return Find(page, text) ~= nil end
			-- (Each with the guild too: before the review of 1.5.9 these rows named it, and it is no harm now.)
			for _, text in ipairs({ L.RECRUIT_WHISPER_JOINED, L.RECRUIT_HANDOFF_PENDING:format("Sebastian Rockwell", own),
				L.RECRUIT_HANDOFF_DONE:format("Valentina Hawthorn", own), L.RECRUIT_HANDOFF_BLOCKED, L.RECRUIT_HANDOFF_OFFER:format("Christoph Lockhart", own),
				L.RECRUIT_HANDOFF_CLAIM:format("Christoph Lockhart", own), L.RECRUIT_HANDOFF_WAITING:format("Theodora Blackwood", own),
				L.RECRUIT_CANDIDATE_WHO:format("Clementia Westbury"), L.RECRUIT_CANDIDATE_PASSING:format("Benedicta Harcourt"),
				L.JOIN_MORE:format(1), L.RECRUIT_ANNOUNCE_CHANNEL:format(4, "LookingForGroup"), L.JOIN_DECLINE }) do
				assert(Has(text), "the page shows " .. text)
			end
			local pending = 0
			for _, line in ipairs(page) do
				if line.text and line.text:find(L.RECRUIT_HANDOFF_PENDING:format("Sebastian Rockwell", own), 1, true) then pending = pending + 1 end
			end
			eq(pending, 2, "a JOIN and a scanned player offered to him")

			for _, code in ipairs({ "enUS", "ptBR", "deDE", "esES", "frFR", "itIT", "ruRU" }) do
				InLanguage(code, function()
					for _, line in ipairs(R.WhisperLines()) do
						if line.text then
							local text = Plain(line.text) .. (line.right and line.right ~= "" and ("  " .. Plain(line.right)) or "")
							local room = line.header and HEADING_ROOM or ROOM[line.indent or 0] or ROOM[3]
							assert(Chars(text) <= room, ("%s, indent %d: %d characters, room for %d: %s"):format(code,
								line.indent or 0, Chars(text), room, text))
						end
					end
				end)
			end
		end)
		GetChannelList, C_ChatInfo = savedList, savedChat
		if not ok then error(err, 0) end
	end)
end)

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

test("join screen request (1.5.9): past the minute's ten invites a J3 says so and passes, or goes to the members on its own; its name only after a claim", function()
	WithHandoff(function(scene)
		WithLog(function()
			local D = Dialogs()
			ns.Dialog = D
			local savedUtil = ChatFrameUtil
			ChatFrameUtil = { OpenChat = function() end }
			local ok, err = pcall(function()
				for i = 1, 10 do R.OnWhisper("JOIN", ("Fast %d-%s"):format(i, home)) end
				for i = 1, 10 do
					local open = D.Find(DRAFT)
					if open then open:Hide() end
					eq(R.Accept(R.requests[i]), true)
					local draft = assert(D.Find(DRAFT))
					draft.def.extra.onClick(draft, draft.data)
					draft:Hide()
				end
				eq(R.AtInviteLimit(), true)
				-- The automatic offers off: its popup says the limit and offers Pass, as a JOIN's does.
				scene.now = scene.now + 21
				eq(R.OnJoinRequest("WHISPER", applicant, J3), true)
				local draft = assert(D.Find(DRAFT), "the J3 pops up at the limit")
				local req = draft.data.req
				eq(req.name, applicant)
				assert(draft.text:find(ns.L.RECRUIT_INVITE_LIMIT_PASS:format(10), 1, true), "the popup says the limit")
				assert(draft.def.button2Shown(draft, draft.data), "and offers Pass")
				draft.def.OnButton2(draft, draft.data)
				draft:Hide()
				eq(req.passWanted, true)
				-- The probe and the offer carry no name; the member who claims gets it.
				scene.tick()
				local probe = assert(scene.packets[1])
				assert(probe.word:match("^J4~P~") and probe.word:sub(-1) == "~", "no name with the probe")
				eq(H.Receive("WHISPER", mate, (probe.word:gsub("^J4~P~", "J4~V~"))), true)
				scene.tick()
				local offer = assert(scene.packets[2])
				assert(offer.word:match("^J4~O~") and offer.word:sub(-1) == "~", "no name with the offer")
				eq(H.Receive("WHISPER", mate, (offer.word:gsub("^J4~O~", "J4~C~"))), true)
				local named = assert(scene.packets[3])
				assert(named.word:match("^J4~N~"))
				eq(named.word:sub(-#applicant), applicant, "the Join screen's player, to the member who claimed")
				eq(named.peer, mate)
				eq(H.Receive("WHISPER", mate, (offer.word:gsub("^J4~O~", "J4~A~"))), true)
				eq(H.State(req), "assigned")
				assert(LogHas("HANDED " .. H.Tag(applicant) .. " > Guild Recruiter"))
				-- (Changed on purpose in the 1.5.9 merge: the declined lane's fix of the author's report, 11-12,
				-- "Ele tem que ficar desativado se ele estava desativado": Pass leaves the automatic offers
				-- off; he turns them on himself.) With them on, the next J3 at the limit goes to the members,
				-- no popup.
				eq(H.AutoOn(), false, "his Pass leaves the automatic offers off")
				assert(Find(R.WhisperLines(), ns.L.RECRUIT_OVERFLOW_OFF)).onClick()
				eq(H.AutoOn(), true, "his own click turns them on")
				local second = "Second Recruit-" .. home
				scene.now = scene.now + 21
				eq(R.OnJoinRequest("WHISPER", second, J3), true)
				local queued = R.requests[#R.requests]
				eq(queued.name, second)
				eq(D.Find(DRAFT), nil, "no popup at the limit with the offers on")
				eq(queued.passWanted, true, "it goes to the other members")
				assert(LogHas("OVERFLOW " .. H.Tag(second)))
			end)
			ChatFrameUtil = savedUtil
			if not ok then error(err, 0) end
		end)
	end)
end)

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
			-- One given to a member (passed, claimed), one still on screen: recruiting off.
			local given, back = "Given Recruit-" .. home, "Back Recruit-" .. home
			scene.now = scene.now + 21 -- (one automatic popup every 20 seconds)
			eq(R.OnJoinRequest("WHISPER", given, J3), true)
			local givenReq = R.requests[1]
			local draft = assert(D.Find(DRAFT))
			draft.def.OnButton2(draft, draft.data)
			draft:Hide()
			scene.tick()
			eq(H.Receive("WHISPER", mate, (assert(scene.packets[1]).word:gsub("^J4~P~", "J4~V~"))), true)
			scene.tick()
			eq(H.Receive("WHISPER", mate, (assert(scene.packets[2]).word:gsub("^J4~O~", "J4~C~"))), true)
			eq(H.State(givenReq), "assigning", "its name went to the member")
			scene.now = scene.now + 21
			eq(R.OnJoinRequest("WHISPER", back, J3), true)
			local req = R.requests[#R.requests]
			eq(req.name, back)
			eq(assert(D.Find(DRAFT)).data.req, req)
			eq(R.ToggleWhisperRecruiting(), false, "recruiting off")
			eq(D.Find(DRAFT), nil, "its popup closes with recruiting")
			eq(#R.requests, 1, "the one a member has is gone")
			eq(R.requests[1], req, "the other one stays")
			eq(req.viaWhisper, nil)
			eq(Find(R.RequestLines(true), "Back Recruit"), nil)
			assert(Find(R.RequestLines(false), "Back Recruit"), "back in the Census as it came")
			-- In the Census on Forever: Prepare invite (the command to copy, from the click) and Decline.
			assert(Find(R.RequestLines(false), ns.L.RECRUIT_WHISPER_PREPARE_BUTTON)).onClick()
			local copy = assert(D.Find(DRAFT), "the command to copy")
			eq(copy.data.req, req); eq(copy.data.automatic, nil, "from the officer's click")
			copy:Hide()
			assert(Find(R.RequestLines(false), ns.L.JOIN_DECLINE)).onClick()
			eq(#said, 2); eq(said[2].to, "Back Recruit"); eq(#R.requests, 0)
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
test("join screen request (review of 1.5.9): recruiting off while a J3's offer waits for a claim brings it back to the Census; a late claim gets no name", function()
	WithHandoff(function(scene)
		local D = Dialogs()
		ns.Dialog = D
		eq(R.OnJoinRequest("WHISPER", applicant, J3), true)
		local req = R.requests[1]
		local draft = assert(D.Find(DRAFT))
		draft.def.OnButton2(draft, draft.data) -- Pass
		draft:Hide()
		scene.tick()
		local probe = assert(scene.packets[1])
		eq(H.Receive("WHISPER", mate, (probe.word:gsub("^J4~P~", "J4~V~"))), true)
		scene.tick()
		local offer = assert(scene.packets[2])
		assert(offer.word:match("^J4~O~") and offer.word:sub(-1) == "~", "no name with the offer")
		eq(H.State(req), "offered", "offered, not claimed: no member has its name")
		eq(R.ToggleWhisperRecruiting(), false, "recruiting off")
		eq(#R.requests, 1); eq(R.requests[1], req, "kept")
		eq(req.viaWhisper, nil); eq(H.State(req), nil, "its offer withdrawn")
		eq(Find(R.RequestLines(true), "New Recruit"), nil)
		assert(Find(R.RequestLines(false), "New Recruit"), "back in the Census as it came")
		-- The member's claim comes in late: refused, and no name goes to him.
		local sent = #scene.packets
		eq(H.Receive("WHISPER", mate, (offer.word:gsub("^J4~O~", "J4~C~"))), false)
		eq(#scene.packets, sent, "nothing sent to the member who claimed late")
		for _, p in ipairs(scene.packets) do assert(not p.word:find("New Recruit", 1, true), p.word) end
		eq(R.requests[1], req); eq(req.viaWhisper, nil, "still the Census's")
	end)
end)

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
