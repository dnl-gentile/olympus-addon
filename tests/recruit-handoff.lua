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
	}
	R.ResetForTests()
	local scene = { now = 5000, fresh = true, permission = true, support = 2, packets = {} }
	GetGuildInfo = function() return own end
	CanGuildInvite = function() return scene.permission end
	ns.IsMember = function() return true end
	ns.ChatLocked = function() return false end
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
	ns.Comm.Whisper = function(peer, word, _, _, logged, _, options)
		eq(logged, false, "handoff packets do not go to the chat log")
		assert(options.guard(), "queued handoff is permitted at the point of enqueue")
		scene.packets[#scene.packets + 1] = { peer = peer, word = word, guard = options.guard }
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
	if not ok then error(err, 0) end
end

local function Packet(scene, verb, from, to, name, id)
	return ("J4~%s~%s~%d~ForeverPvE~Alliance~%s~%s~%s"):format(verb, id or "1234-ab-1", scene.now + 90, from, to, name or "")
end

local function Find(rows, text)
	for _, row in ipairs(rows) do if row.text:find(text, 1, true) then return row end end
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
