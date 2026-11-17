local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]federation%-fugitives%.lua$") or "./"
local proofs = assert(loadfile(ROOT .. "tests/fixtures/federation-fugitives.lua"))()
local ON = "Arden Frost-CAMWOWUS2Realm5PvE"
local ALT = "Quill Dawn-CAMWOWUS2Realm7PvE"
local GM = "Rook Ash-CAMWOWUS2Realm5PvE"
local GUILD = "Olympus Willow"
local NOW = 1800010000

local function Client(db)
	local t = {
		now = NOW, enrolled = true, role = "official", events = {}, listeners = {}, alerts = {},
		links = {}, printed = {}, timers = {}, guild = GUILD, roster = { guild = GUILD, byName = { [ON] = 3, [GM] = 2 } },
		requests = {}, replies = {}, handlers = {}, peers = {}, caretakers = {}, roles = {},
	}
	local c = setmetatable({
		realm = "CAMWOWUS2Realm5PvE", group = "ForeverPvE", faction = "Alliance", me = GM, db = db or {},
		L = setmetatable({}, { __index = ns.L }), RealmPages = {},
		Data = { ServerTime = function() return t.now end },
		FederationProgram = {
			IsEnrolled = function(guild) return t.enrolled and guild == t.guild end,
			LocalEnrollment = function() return t.enrolled and t.guild or nil end,
			Role = function(name, guild) return t.roles[name] == guild and "caretaker" or name == GM and guild == GUILD and t.role or nil end,
			Caretakers = function() return t.caretakers end,
		},
		Comm = {
			Handle = function(kind, handler) t.handlers[kind] = handler end,
			Peers = function() return t.peers end,
			Whisper = function(target, word, _, _, _, _, options)
				t.requests[#t.requests + 1] = { target = target, word = word, guard = options.guard }
				return true
			end,
			SendBatch = function(dist, pieces, _, target, _, _, options)
				t.replies[#t.replies + 1] = { dist = dist, pieces = pieces, target = target, guard = options.guard }
				return true
			end,
		},
		Alts = { Linked = function(name) return t.links[name] or {} end },
		Groups = { GroupMembers = function() return t.members or {} end },
		Roster = { Fresh = function() return t.roster end, RankOf = function(name) return t.roster and t.roster.byName[name] end },
		Dialog = { Show = function(id, text)
			if t.refuseDialog then return nil end
			t.alerts[#t.alerts + 1] = { id = id, text = text }
			return true
		end },
		ChatLocked = function() return t.chatLocked == true end,
		QuietPresence = function() return t.quiet == true end,
		IsMember = function() return t.member ~= false end,
		KingsScreen = function() return t.stream == true end,
		RegisterEvent = function(event, fn) t.events[event] = fn end,
		On = function(event, fn) t.listeners[event] = fn end,
		Fire = function(event, ...) if t.listeners[event] then t.listeners[event](...) end end,
		After = function(_, _, fn) t.timers[#t.timers + 1] = fn end,
		Print = function(text) t.printed[#t.printed + 1] = text end,
	}, { __index = ns })
	assert(loadfile(ROOT .. "Olympus/Locales/FugitivesText.lua"))("Olympus", c)
	assert(loadfile(ROOT .. "Olympus/FederationFugitives.lua"))("Olympus", c)
	return t, c, c.FederationFugitives
end

test("federation fugitives: leader roster review rechecks the signed decision before a native removal", function()
	ns.Sign.WithKey(proofs.N, proofs.MU, proofs.K, function()
		local t, c, f = Client()
		c.Members = {
			CanRemove = function() return t.canRemove end,
			Removable = function(m) return m.rankIndex > 1 end,
			AskRemove = function(m) t.removal = m end,
		}
		local page = assert(c.RealmPages[1])
		assert(f.Import(proofs.INITIAL))
		t.roster.members = { { full = ON, raw = "Arden Frost", name = "Arden Frost", rankIndex = 3 } }
		t.role = "member"
		eq(page.Link(), nil)
		t.role = "official"
		assert(page.Link())
		eq(page.Lines()[2].onClick, nil, "the existing native permission controls the action")
		t.canRemove = true
		page.Lines()[2].onClick()
		assert(t.removal and f.RemovalAllowed(t.removal))
		t.roster.members[1].rankIndex = 1
		eq(f.RemovalAllowed(t.removal), false, "changing the role while the prompt is open denies")
		t.roster.members[1].rankIndex = 3
		assert(f.Import(proofs.CLEARED))
		eq(f.RemovalAllowed(t.removal), false, "an appeal overturned this decision while the prompt was open")
		eq(page.Lines()[2].text, c.L.FUGITIVES_ROSTER_EMPTY)
	end)
end)

test("federation fugitives: native removals are reviewed locally with no inferred realm or signed decision", function()
	ns.Sign.WithKey(proofs.N, proofs.MU, proofs.K, function()
		local t, c, f = Client()
		local page = c.RealmPages[1]
		local hour = math.floor(t.now / 3600)
		c.ChurchCount = { Read = function() return true end }
		c.UI = { ShowCopy = function(_, text) t.copied = text end }
		local events = {
			{ kind = "remove", p1 = GM, p2 = ALT, hour = hour - 50, removerExact = true, removedExact = true },
			{ kind = "remove", p1 = ALT, p2 = ON, hour = hour, removerExact = true, removedExact = true },
			{ kind = "quit", p1 = ON, p2 = ALT, hour = hour, removerExact = true, removedExact = true },
			{ kind = "remove", p1 = GM, p2 = ON, hour = hour, removerExact = true, removedExact = false },
		}
		local function Find(text)
			for _, row in ipairs(page.Lines()) do if row.text:find(text, 1, true) then return row end end
		end
		c.Fire("CHURCH_NATIVE_GUILD_LOG", events)
		eq(Find("Arden Frost"), nil, "the request must be attended")
		assert(Find(c.L.FUGITIVES_READ_REMOVALS).onClick())
		c.Fire("CHURCH_NATIVE_GUILD_LOG", events)
		local row = assert(Find("Arden Frost"))
		assert(row.right:find(c.L.FUGITIVES_CHECK_REALM, 1, true))
		eq(Find("Quill Dawn"), nil)
		row.onClick()
		assert(t.copied:find(c.L.FUGITIVES_REVIEW_ONLY, 1, true))
		eq(t.copied:find(ON, 1, true), nil, "we never present an inferred realm as the native realm")
		eq(f.IsListed(ON, GUILD), false, "a removal is evidence for review, never a decision")
		t.now = t.now + 301
		eq(Find("Arden Frost"), nil)
	end)
end)

test("federation fugitives: signed decisions sync privately between scoped enrolled clients and survive a clearing revision", function()
	ns.Sign.WithKey(proofs.N, proofs.MU, proofs.K, function()
		local sender, s, source = Client()
		local receiver, c, incoming = Client()
		local keeper, G2 = "Alder Fall-CAMWOWUS2Realm7PvE", "Olympus Azure"
		s.me, sender.guild, sender.roster.guild = keeper, G2, G2
		sender.roles[keeper], sender.roles[c.me] = G2, GUILD
		receiver.roles[keeper], receiver.caretakers[G2] = G2, keeper
		local function Request()
			assert(incoming.Sync(), "eligible client requests the next revision")
			local request = receiver.requests[#receiver.requests]
			eq(request.target, keeper)
			return request
		end
		local function Assemble(reply)
			local asm, body = ns.Codec.NewAssembler(), nil
			for _, piece in ipairs(reply.pieces) do body = ns.Codec.Feed(asm, s.me, piece, sender.now) end
			return assert(body)
		end
		assert(source.Import(proofs.INITIAL))
		local request = Request()
		eq(incoming.Sync(), false, "only one outstanding request")
		eq(sender.handlers.FZ("CHANNEL", c.me, request.word), false)
		eq(sender.handlers.FZ("WHISPER", ALT, request.word), false, "another guild's unproven member gets no list")
		eq(sender.handlers.FZ("WHISPER", c.me, request.word), true)
		local reply = sender.replies[1]
		eq(reply.dist, "WHISPER"); eq(reply.target, c.me); eq(reply.guard(), true)
		local body = Assemble(reply)
		eq(receiver.handlers.FZ("WHISPER", ALT, body), false, "only the requested peer may answer")
		eq(receiver.handlers.FZ("WHISPER", s.me, (body:gsub("Arden", "Alden"))), false)
		eq(receiver.handlers.FZ("WHISPER", s.me, body), true)
		eq(incoming.IsListed(ON, GUILD), true)
		eq(receiver.handlers.FZ("WHISPER", s.me, body), false, "unsolicited repeat")
		assert(source.Import(proofs.CLEARED))
		eq(reply.guard(), false, "never sends an older list from the queue after a clearing decision")
		sender.now, receiver.now = NOW + 120, NOW + 120
		request = Request()
		assert(sender.handlers.FZ("WHISPER", c.me, request.word))
		local cleared = Assemble(sender.replies[2])
		receiver.enrolled = false
		eq(request.guard(), false)
		eq(receiver.handlers.FZ("WHISPER", s.me, cleared), false)
		receiver.enrolled = true
		assert(receiver.handlers.FZ("WHISPER", s.me, cleared))
		eq(incoming.IsListed(ON, GUILD), false)
		eq(incoming.Import(proofs.INITIAL), false)
	end)
end)

test("federation fugitives: signed scope, expiration and clearing are checked after reload", function()
	ns.Sign.WithKey(proofs.N, proofs.MU, proofs.K, function()
		local t, c, f = Client()
		eq(f.IsListed(ON, GUILD), false, "no policy is empty")
		eq(f.Import((proofs.INITIAL:gsub("Arden", "Other"))), false, "edited name doesn't have a valid signature")
		eq(f.Import(proofs.FUTURE), false, "future policy")
		eq(f.Import(proofs.DUPLICATE), false, "duplicate identity")
		c.realm = "CAMWOWEU2Realm5PvE"
		eq(f.Import(proofs.INITIAL), false, "other region")
		c.realm, c.group = "CAMWOWUS2Realm5PvP", "ForeverPvP"
		eq(f.Import(proofs.INITIAL), false, "other ruleset")
		c.realm, c.group, c.faction = "CAMWOWUS2Realm5PvE", "ForeverPvE", "Horde"
		eq(f.Import(proofs.INITIAL), false, "other faction")
		c.faction = "Alliance"
		eq(f.Import(proofs.INITIAL), true)
		eq(f.IsListed(ON, GUILD), true)
		eq(f.IsListed("Arden Frost", GUILD), false, "a bare name cannot confer an enforcement match")
		eq(f.IsListed(ON, "Olympus Fen"), false, "destination is not opted in")
		eq(f.IsListed(ALT, GUILD), false)
		t.links[ALT] = { ON }
		eq(f.IsListed(ALT, GUILD), true, "two-sided in-game link from Alts.Linked")
		t.now = 1802000000
		eq(f.IsListed(ON, GUILD), false, "exclusive expiry")
		t.now = NOW
		eq(f.Import(proofs.CLEARED), true, "signed clearing")
		eq(f.IsListed(ON, GUILD), false)
		local _, reload, restored = Client(c.db)
		eq(restored.Import(proofs.INITIAL), false, "previous signed list rejected after reload")
		eq(restored.IsListed(ON, GUILD), false)
		reload.db.federationFugitives["US:ForeverPvE:Alliance"] = proofs.INITIAL:gsub("Arden", "Other")
		eq(restored.IsListed("Other Frost-CAMWOWUS2Realm5PvE", GUILD), false, "saved data is authenticated on use")
	end)
end)

test("federation fugitives: group joins and tooltip visibility follow local enrollment and signed identities", function()
	ns.Sign.WithKey(proofs.N, proofs.MU, proofs.K, function()
		local t, c, f = Client()
		t.members = { { name = ON }, { name = "Arden Frost" } }
		t.listeners.GROUPS_ROSTER()
		eq(#t.printed, 0, "no signed list")
		eq(f.Import(proofs.INITIAL), true)
		t.enrolled = false
		t.listeners.GROUPS_ROSTER()
		eq(#t.printed, 0, "no enrollment")
		eq(f.Visible(ON), false)
		t.enrolled, t.stream = true, true
		t.listeners.GROUPS_ROSTER()
		eq(#t.printed, 0, "stream privacy")
		eq(f.Visible(ON), false)
		t.stream = false
		eq(f.Visible(ON), true)
		eq(f.Visible("Arden Frost"), false)
		t.listeners.GROUPS_ROSTER()
		t.listeners.GROUPS_ROSTER()
		eq(#t.printed, 1, "one warning for this join")
		eq(t.printed[1], c.L.FUGITIVES_PARTY)
		local joined = t.members
		t.members = {}
		t.listeners.GROUPS_ROSTER()
		t.members = joined
		t.listeners.GROUPS_ROSTER()
		eq(#t.printed, 2, "warns when they rejoin")
	end)
end)

test("federation fugitives: native roster notices require enrollment, a designated role and a fresh roster", function()
	ns.Sign.WithKey(proofs.N, proofs.MU, proofs.K, function()
		local t, c, f = Client()
		eq(f.Import(proofs.INITIAL), true)
		t.enrolled = false
		eq(f.Audit(), false)
		t.enrolled, t.role = true, "member"
		eq(f.Audit(), false)
		local roster = t.roster
		t.role, t.roster = "caretaker", nil
		eq(f.Audit(), false, "an uncorroborated roster is not evidence")
		t.roster, t.chatLocked = roster, true
		eq(f.Audit(), false, "the modal waits out protected chat scenes")
		t.chatLocked, t.refuseDialog = false, true
		eq(f.Audit(), false, "an unshown alert does not start daily suppression")
		t.refuseDialog = false
		t.events.GUILD_ROSTER_UPDATE()
		eq(#t.timers, 1, "roster bursts coalesce")
		table.remove(t.timers, 1)()
		eq(#t.alerts, 1)
		eq(t.alerts[1].id, "OLYMPUS_FUGITIVES_AUDIT")
		eq(t.alerts[1].text, c.L.FUGITIVES_AUDIT:format(ON))
		eq(f.Audit(), false, "notice sent today")
		local next, _, other = Client(c.db)
		eq(other.Audit(), false, "persists across reload")
		next.now = NOW + 86400
		eq(other.Audit(), true, "next server day")
	end)
end)

test("federation fugitives: whispers in either direction warn once per character and only for opted-in viewers", function()
	ns.Sign.WithKey(proofs.N, proofs.MU, proofs.K, function()
		local t, c, f = Client()
		eq(f.Import(proofs.INITIAL), true)
		t.enrolled = false
		t.events.CHAT_MSG_WHISPER("hello", ON)
		eq(#t.printed, 0)
		t.enrolled, t.stream = true, true
		t.events.CHAT_MSG_WHISPER("hello", ON)
		eq(#t.printed, 0, "the King's stream emits no warning")
		t.stream = false
		t.events.CHAT_MSG_WHISPER("hello", ON)
		t.events.CHAT_MSG_WHISPER_INFORM("hello back", ON)
		eq(#t.printed, 1)
		eq(t.printed[1], c.L.FUGITIVES_WHISPER)
		t.links[ALT] = { ON }
		t.events.CHAT_MSG_WHISPER_INFORM("hello", ALT)
		t.events.CHAT_MSG_WHISPER("hello back", ALT)
		eq(#t.printed, 2)
	end)
end)
