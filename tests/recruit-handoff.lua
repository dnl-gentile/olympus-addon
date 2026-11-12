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
		every = ns.Every, quiet = ns.QuietPresence, after = ns.After, rdb = ns.rdb,
	}
	ns.rdb = {}
	R.ResetForTests()
	local scene = { now = 5000, fresh = true, permission = true, support = 2, packets = {}, later = {} }
	GetGuildInfo = function() return own end
	CanGuildInvite = function() return scene.permission end
	ns.IsMember = function() return true end
	ns.ChatLocked = function() return scene.locked == true end
	ns.After = function(_, _, fn) scene.later[#scene.later + 1] = fn end
	ns.QuietPresence = function() return scene.quiet == true end
	ns.Every = function(_, _, callback)
		scene.tick = callback
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
	ns.Every, ns.QuietPresence, ns.After, ns.rdb = saved.every, saved.quiet, saved.after, saved.rdb
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
