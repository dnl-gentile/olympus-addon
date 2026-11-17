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
	}
	local c = setmetatable({
		realm = "CAMWOWUS2Realm5PvE", group = "ForeverPvE", faction = "Alliance", me = GM, db = db or {}, L = {},
		Data = { ServerTime = function() return t.now end },
		FederationProgram = {
			IsEnrolled = function(guild) return t.enrolled and guild == t.guild end,
			LocalEnrollment = function() return t.enrolled and t.guild or nil end,
			Role = function(name, guild) return name == GM and guild == GUILD and t.role or nil end,
		},
		Alts = { Linked = function(name) return t.links[name] or {} end },
		Roster = { Fresh = function() return t.roster end },
		Dialog = { Show = function(id, text)
			if t.refuseDialog then return nil end
			t.alerts[#t.alerts + 1] = { id = id, text = text }
			return true
		end },
		ChatLocked = function() return t.chatLocked == true end,
		KingsScreen = function() return t.stream == true end,
		RegisterEvent = function(event, fn) t.events[event] = fn end,
		On = function(event, fn) t.listeners[event] = fn end,
		Fire = function(event) if t.listeners[event] then t.listeners[event]() end end,
		After = function(_, _, fn) t.timers[#t.timers + 1] = fn end,
		Print = function(text) t.printed[#t.printed + 1] = text end,
	}, { __index = ns })
	assert(loadfile(ROOT .. "Olympus/Locales/FugitivesText.lua"))("Olympus", c)
	assert(loadfile(ROOT .. "Olympus/FederationFugitives.lua"))("Olympus", c)
	return t, c, c.FederationFugitives
end

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
