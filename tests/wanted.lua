-- Horde Most Wanted: the real ledger and adapters against a small supported-client boundary.
local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]wanted%.lua$")) or "./"

local DIALOGS = { "OLYMPUS_WANTED_ADD", "OLYMPUS_WANTED_REMOVE", "OLYMPUS_WANTED_SEND", "OLYMPUS_WANTED_REVIEW",
	"OLYMPUS_WANTED_WITHDRAW", "OLYMPUS_WANTED_PUBLISH", "OLYMPUS_WANTED_REVOKE", "OLYMPUS_WANTED_CORRECT" }

local function WithWanted(fn)
	local globals = { "UnitGUID", "UnitIsPlayer", "UnitFactionGroup", "GetGuildInfo", "GetRealZoneText",
		"UnitCanAttack", "UnitIsPVP", "issecretvalue",
		"UnitIsDeadOrGhost", "C_DateAndTime", "C_DeathInfo", "C_DeathRecap", "CombatLogGetCurrentEventInfo", "GetGameTime", "GetFileIDFromPath",
		"ERR_CHAT_PLAYER_NOT_FOUND_S", "GetPlayerInfoByGUID", "UnitTokenFromGUID" }
	local saved = {}
	for _, name in ipairs(globals) do saved[name] = _G[name] end
	local dialogs = {}
	for _, which in ipairs(DIALOGS) do dialogs[which] = StaticPopupDialogs[which] end

	local w = { epoch = 1800000000, year = 2026, month = 10, member = true, manager = true, units = {},
		olympians = {}, authorities = {}, handlers = {}, commHandlers = {}, listeners = {}, events = {}, dialogs = {},
		prints = {}, assets = {}, sent = {}, identities = {}, publicKey = string.rep("K", 32), refreshed = 0 }
	local ok, err = pcall(function()
		w.units.player = { name = "Olympian-Realm", guid = "Player-1-AA000001", faction = "Alliance", guild = "Olympus II" }
		UnitGUID = function(unit) return w.units[unit] and w.units[unit].guid end
		UnitIsPlayer = function(unit) return w.units[unit] and w.units[unit].player ~= false or false end
		UnitFactionGroup = function(unit) return w.units[unit] and w.units[unit].faction end
		UnitIsDeadOrGhost = function(unit) return unit == "player" and w.dead ~= false end
		GetGuildInfo = function(unit) return w.units[unit or "player"] and w.units[unit or "player"].guild end
		GetRealZoneText = function() return "Warsong Gulch" end
		C_DateAndTime = { GetCurrentCalendarTime = function() return { year = w.year, month = w.month } end }
		GetFileIDFromPath = function(path) return w.assets[path] and 1 or nil end
		UnitTokenFromGUID = nil
		GetPlayerInfoByGUID = function(guid)
			local name = w.identities[guid]
			if name then return "Warrior", "WARRIOR", "Human", "Human", 2, ns.ShortName(name), "Realm" end
		end

		local c = setmetatable({ L = ns.L, db = {}, rdb = {}, me = w.units.player.name, realm = "Realm",
			group = "RealmGroup", faction = "Alliance" }, { __index = ns })
		c.Now = function() return w.epoch end
		c.Data = { ServerTime = function() return w.epoch end }
		c.IsMember = function() return w.member end
		c.Moderation = { CanIssue = function() return w.manager end }
		c.Workshop = { IsAuthor = function() return false end,
			IsAuthorName = function(name) return w.authorities[c.Fold(c.FullName(name))] == "author" end }
		c.IsKingCharacter = function(name) return w.authorities[c.Fold(c.FullName(name))] == "king" end
		c.IsHighCouncillor = function(name) return w.authorities[c.Fold(c.FullName(name))] == "council" end
		local realEd = ns.Ed25519
		local function Signature(text) return c.Sign.SHA256(text) .. c.Sign.SHA256("wanted:" .. text) end
		c.Ed25519 = {
			ToB64 = realEd.ToB64, FromB64 = realEd.FromB64,
			ValidPublicKey = function(pk) return type(pk) == "string" and #pk == 32 end,
			Busy = function() return 0 end,
			Verify = function(_, text, sig) return sig == Signature(text) end,
			Run = function(job, done) local good, value = pcall(job); done(good, value); return true end,
		}
		c.Debts = {
			MyKey = function() return "1.aa000001", w.publicKey, "fp" end,
			Sign = Signature, B64 = realEd.ToB64, UnB64 = realEd.FromB64,
		}
		c.Comm = {
			Handle = function(kind, call) w.commHandlers[kind] = call end,
			Send = function(dist, text) w.sent[#w.sent + 1] = { dist = dist, text = text }; return true end,
			Whisper = function(to, text) w.sent[#w.sent + 1] = { dist = "WHISPER", to = to, text = text }; return true end,
			SendChunked = function(text) w.sent[#w.sent + 1] = { dist = "CHANNEL", text = text }; return true end,
		}
		c.UnitFullName = function(unit) return w.units[unit] and w.units[unit].name end
		c.Roster = { Fresh = function() return w.rosterStale ~= true end,
			RankOf = function(name) return w.olympians[c.Fold(c.FullName(name))] and 3 or nil end }
		-- (1.2.0: evidence comes only from members: whoever whispers here claims a federation guild
		-- the channel takes, unless named in w.strangers.)
		w.strangers = {}
		c.Moderation.GuildOf = function(name) if not w.strangers[c.Fold(c.FullName(name))] then return "Olympus II" end end
		c.Channels = setmetatable({ VerifiedLevel = function(name)
			if w.strangers[c.Fold(c.FullName(name))] then return 0, false end
			return 1, false
		end }, { __index = c.Channels })
		c.RegisterEvent = function(name, call) w.handlers[name] = call end
		c.On = function(name, call) w.listeners[name] = call end
		c.Fire = function(name, ...) w.events[#w.events + 1] = { name, ... } end
		c.Print = function(message) w.prints[#w.prints + 1] = tostring(message) end
		c.Ago = function(at) return tostring(w.epoch - (tonumber(at) or 0)) .. "s" end
		c.ShowDialog = function(which, a, b, data)
			w.dialogs[#w.dialogs + 1] = { which = which, a = a, b = b, data = data }
			return true
		end
		c.UI = {}
		c.UI.FirstTexture = function(paths)
			for _, path in ipairs(paths) do if GetFileIDFromPath(path) then return path end end
			return paths[#paths]
		end
		c.UI.AddTab = function(spec) w.tab = spec return true end
		c.UI.Refresh = function() w.refreshed = w.refreshed + 1 end
		c.UI.RefreshSoon = c.UI.Refresh
		c.UI.ShowPerson = function(person) w.profile = person return true end

		w.olympians[c.Fold(c.me)] = true
		function w.olympian(name)
			name = c.FullName(name)
			w.olympians[c.Fold(name)] = true
			return name
		end
		function w.participant(name, guid)
			name = w.olympian(name)
			w.identities[guid] = name
			return name
		end
		function w.advance(seconds) w.epoch = w.epoch + (seconds or 6) end
		function w.authority(name, role)
			name = c.FullName(name)
			w.authorities[c.Fold(name)] = role
			return name
		end
		-- w.publish signs on another client, the publisher's (as c.me at the time), so that its word
		-- reaches c as it reaches any other client: a publisher's own client holds the word it sends
		-- (as heard from himself), and c, publishing itself, would hold it already. That client has
		-- c's mocks and account data (db: its key's epoch and sequence), its own realm data (rdb),
		-- and none of c's handlers, tab or dialogs.
		function w.publisher()
			if w.pub then return w.pub end
			local quiet = function() end
			local p = setmetatable({ rdb = {} }, { __index = c })
			p.Comm = { Handle = quiet, Whisper = c.Comm.Whisper, SendChunked = c.Comm.SendChunked }
			p.On, p.RegisterEvent, p.Fire = quiet, quiet, quiet
			p.UI = { AddTab = quiet, Refresh = quiet, RefreshSoon = quiet, FirstTexture = c.UI.FirstTexture, ShowPerson = quiet }
			local mine = {}
			for _, which in ipairs(DIALOGS) do mine[which] = StaticPopupDialogs[which] end
			assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", p)
			for _, which in ipairs(DIALOGS) do StaticPopupDialogs[which] = mine[which] end
			p.Wanted.ResetForTests()
			w.pub = p
			return p
		end
		function w.publish(rows, epoch)
			local p = w.publisher()
			p.me = c.me
			local rankings = p.Wanted.ReviewedRankings
			p.Wanted.ReviewedRankings = function() return rows end
			if epoch then c.db.wantedPublisher = { epoch = epoch, seq = 0 } end
			local ok, why = p.Wanted.PublishGlobal()
			p.Wanted.ReviewedRankings = rankings
			return ok, why, w.sent[#w.sent] and w.sent[#w.sent].text
		end
		function w.kill(id, killerName, killerGuid, victimName, victimGuid)
			return c.Wanted.CaptureCombatLog(id, "PARTY_KILL", false, killerGuid, killerName, 0, 0, victimGuid, victimName)
		end
		function w.add(name, guid)
			local was = w.manager
			w.manager = true
			local added, why = c.Wanted.AddTarget(name, guid)
			w.manager = was
			return added, why
		end

		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		w.ns, w.Wanted = c, c.Wanted
		c.Wanted.ResetForTests()
		fn(w, c.Wanted, c)
	end)

	for _, name in ipairs(globals) do _G[name] = saved[name] end
	for _, which in ipairs(DIALOGS) do StaticPopupDialogs[which] = dialogs[which] end
	if not ok then error(err, 0) end
end

local function Tooltip()
	return { lines = {}, AddLine = function(self, text) self.lines[#self.lines + 1] = tostring(text) end }
end

test("wanted: top-level page, stock Orc icon, authority gate, normalized identity and internal target profile", function()
	WithWanted(function(w, W)
		eq(w.tab.key, "wanted"); eq(w.tab.after, "realm"); eq(w.tab.label, "TAB_WANTED")
		eq(w.tab.visible(), true)
		w.assets[W.ICON_PATHS[1]] = true
		eq(W.Icon(), "Interface\\Icons\\INV_Misc_Tournaments_banner_Orc")

		w.manager = false
		local added, why = W.AddTarget("Grom-Realm")
		eq(added, false); eq(why, "access")
		w.manager = true
		assert(W.AddTarget("  Grom-Realm  "))
		local grom = assert(W.Target("Grom-Realm"))
		eq(grom.current, 0); eq(grom.lifetimeKills, 0); eq(grom.guid, nil)
		assert(W.AddTarget(nil, "Player-1-ABCD0002"), "a GUID-only target stays unnamed")
		local unknown = assert(W.Target(nil, "Player-1-ABCD0002"))
		eq(unknown.name, nil)

		w.units.target = { name = "Wrong-Realm", guid = "Player-1-ABCD0003", faction = "Alliance" }
		eq(select(2, W.AddTargetUnit("target")), "faction")
		w.units.target = { name = "Thrall-Realm", guid = "Player-1-ABCD0004", faction = "Horde" }
		assert(W.AddTargetUnit("target"))

		w.manager = false
		local lines = W.Build()
		local row
		for _, line in ipairs(lines) do if line.id == "wanted:" .. grom.key then row = line end end
		assert(row and row.onClick and row.tooltip, "the responsive Views row")
		local tip = Tooltip(); row.tooltip(tip)
		assert(table.concat(tip.lines, "\n"):find("Current bounty", 1, true))
		assert(row.onClick())
		eq(W.PageId(), "target:" .. grom.key)
		local profile = W.Build()
		assert(profile[1].text:find(ns.L.WANTED_BACK, 1, true))
		assert(profile[1].onClick())
		eq(W.PageId(), "list")
		eq(w.profile, nil, "a Wanted target opens the bounty profile, not an Olympus person card")
		eq(W.RemoveTarget("Grom-Realm"), false, "an ordinary member only reads")
	end)
end)

test("wanted: rejected combat rows cannot learn identity; distinct verified kills accrue and one claim pays atomically", function()
	WithWanted(function(w, W, c)
		assert(w.add("Grom-Realm"))
		local targetGuid = "Player-1-BB000001"
		local ok, why = W.CaptureCombatLog(1, "UNIT_DIED", false, targetGuid, "Grom-Realm", 0, 0,
			"Player-1-CC000001", c.me)
		eq(ok, false); eq(why, "event")
		ok, why = W.CaptureCombatLog(2, "PARTY_KILL", false, targetGuid, "Grom-Realm", 0, 0,
			"Player-1-CC000001", nil)
		eq(ok, false); eq(why, "identities")
		ok, why = w.kill(3, "Grom-Realm", targetGuid, "Outsider-Realm", "Player-1-CC000002")
		eq(ok, false); eq(why, "olympus")
		eq(W.Target("Grom-Realm").guid, nil, "a refused row did not pin its asserted GUID")

		assert(w.kill(4, "Grom-Realm", targetGuid, c.me, w.units.player.guid))
		local t = W.Target("Grom-Realm")
		eq(t.guid, targetGuid); eq(t.current, 1); eq(t.lifetimeKills, 1)
		w.advance()
		ok, why = w.kill("namesake", "Grom-Realm", "Player-1-BB00FFFF", c.me, w.units.player.guid)
		eq(ok, false); eq(why, "unlisted", "once known, a GUID cannot fall back to a namesake")
		eq(W.Target("Grom-Realm").current, 1); eq(W.Target("Grom-Realm").guid, targetGuid)
		ok, why = w.kill(4, "Grom-Realm", targetGuid, c.me, w.units.player.guid)
		eq(ok, false); eq(why, "replay"); eq(W.Target("Grom-Realm").current, 1)

		w.advance(); local ally = w.olympian("Ally-Realm")
		assert(w.kill(5, "Grom-Realm", targetGuid, ally, "Player-1-CC000003"))
		eq(W.Target("Grom-Realm").current, 2)
		w.manager = true; assert(W.AddTarget("OtherHorde-Realm", "Player-1-BB000002")); w.manager = false
		w.advance()
		ok, why = w.kill(6, "Grom-Realm", targetGuid, "OtherHorde-Realm", "Player-1-BB000002")
		eq(ok, false); eq(why, "ambiguous")

		w.advance(); local slayer = w.olympian("Slayer-Realm")
		local slayerGuid = "Player-1-DD000001"
		assert(w.kill(7, slayer, slayerGuid, "Grom-Realm", targetGuid))
		t = W.Target("Grom-Realm")
		eq(t.current, 0); eq(t.lifetimeKills, 2); eq(#t.claims, 1); eq(t.claims[1].points, 2)
		local ranks = W.Rankings()
		eq(ranks.all[1].name, slayer); eq(ranks.all[1].points, 2); eq(ranks.all[1].claims, 1)
		ok, why = w.kill(7, slayer, slayerGuid, "Grom-Realm", targetGuid)
		eq(ok, false); eq(why, "replay"); eq(#W.Target("Grom-Realm").claims, 1)

		w.advance()
		assert(w.kill(8, slayer, slayerGuid, "Grom-Realm", targetGuid), "a verified death closes an empty cycle")
		eq(W.Rankings().all[1].points, 2, "a zero bounty cannot mint points")
		eq(W.Rankings().all[1].claims, 1, "nor a paid claim")
		eq(#W.Target("Grom-Realm").claims, 2, "the verified zero-point death remains auditable")
	end)
end)

test("wanted: guarded self-death recap requires a fatal row, both identities and the local victim", function()
	WithWanted(function(w, W, c)
		local targetGuid = "Player-1-EE000001"
		assert(w.add("Ripper-Realm", targetGuid))
		w.dead = false
		local ok, why = W.CaptureSelfDeathRecap({ fatal = true, killerName = "Ripper-Realm", killerGUID = targetGuid,
			victimName = c.me, victimGUID = w.units.player.guid })
		eq(ok, false); eq(why, "alive")
		w.dead = true
		ok, why = W.CaptureSelfDeathRecap({ { sourceName = "Ripper-Realm", sourceGUID = targetGuid,
			destName = c.me, destGUID = w.units.player.guid } })
		eq(ok, false); eq(why, "fatal")
		ok, why = W.CaptureSelfDeathRecap({ fatal = true, targetName = "Ripper-Realm",
			victimName = c.me, victimGUID = w.units.player.guid })
		eq(ok, false); eq(why, "identities", "a target alone is never inferred to be the killer")
		ok, why = W.CaptureSelfDeathRecap({ fatal = true, killerName = "Ripper-Realm", killerGUID = targetGuid,
			victimName = "SomeoneElse-Realm", victimGUID = "Player-1-EE000002" })
		eq(ok, false); eq(why, "victim")
		assert(W.CaptureSelfDeathRecap({ fatal = true, id = "death-1", killerName = "Ripper-Realm", killerGUID = targetGuid,
			victimName = c.me, victimGUID = w.units.player.guid }))
		local t = W.Target("Ripper-Realm")
		eq(t.current, 1); eq(t.lastSighting.zone, "Warsong Gulch"); eq(t.lastSighting.precision, "approximate")
		w.advance(1)
		ok, why = w.kill("same-death", "Ripper-Realm", targetGuid, c.me, w.units.player.guid)
		eq(ok, false); eq(why, "replay", "the two supported adapters cannot count one death twice")
	end)
end)

test("wanted: bounded history, correction and reload preserve the checkpoint without replay", function()
	WithWanted(function(w, W, c)
		W.MAX_VICTIMS, W.MAX_EVIDENCE = 2, 2
		local targetGuid = "Player-1-AE000001"
		assert(w.add("Collector-Realm", targetGuid))
		local firstId, lastId
		for i = 1, 3 do
			local victim = w.olympian("Victim" .. i .. "-Realm")
			local ok, e = w.kill(100 + i, "Collector-Realm", targetGuid, victim, ("Player-1-AC00000%d"):format(i))
			assert(ok); firstId, lastId = firstId or e.id, e.id
			w.advance()
		end
		local t = W.Target("Collector-Realm")
		eq(t.current, 3); eq(t.lifetimeKills, 3); eq(#t.victims, 2); eq(t.victimOverflow, 1)
		assert(#c.rdb.wanted.evidence <= W.MAX_EVIDENCE); eq(W.Stats().checkpointed, 1)
		w.manager = true
		eq(select(2, W.Correct(firstId, "too old")), "expired", "checkpointed evidence is intentionally immutable")
		assert(W.Correct(lastId, "duplicate server row"))
		t = W.Target("Collector-Realm")
		eq(t.current, 2); eq(t.lifetimeKills, 2); eq(#t.victims, 2); eq(t.victimOverflow, 0)

		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted
		assert(W.Prune())
		t = W.Target("Collector-Realm")
		eq(t.current, 2); eq(t.lifetimeKills, 2); eq(#t.victims, 2)
		local ok, why = w.kill(103, "Collector-Realm", targetGuid, "Victim3-Realm", "Player-1-AC000003")
		eq(ok, false); eq(why, "replay", "seen IDs survive reload even after a correction")
	end)
end)

test("wanted: evidence intake is rate limited independently of semantic replay", function()
	WithWanted(function(w, W)
		W.RATE_MAX = 2
		local targetGuid = "Player-1-AF000001"
		assert(w.add("Burst-Realm", targetGuid))
		for i = 1, 3 do w.olympian("BurstVictim" .. i .. "-Realm") end
		assert(w.kill(201, "Burst-Realm", targetGuid, "BurstVictim1-Realm", "Player-1-AD000001"))
		assert(w.kill(202, "Burst-Realm", targetGuid, "BurstVictim2-Realm", "Player-1-AD000002"))
		local ok, why = w.kill(203, "Burst-Realm", targetGuid, "BurstVictim3-Realm", "Player-1-AD000003")
		eq(ok, false); eq(why, "rate"); eq(W.Target("Burst-Realm").current, 2)
	end)
end)

test("wanted: server-month rollover, deterministic ties and current all-time top-three reassignment", function()
	WithWanted(function(w, W)
		local target, targetGuid = "RankTarget-Realm", "Player-1-BA000001"
		assert(w.add(target, targetGuid))
		local serial = 0
		local function cycle(points, slayer, slayerGuid)
			for _ = 1, points do
				serial = serial + 1
				local victim = w.olympian("RankVictim" .. serial .. "-Realm")
				assert(w.kill(300 + serial, target, targetGuid, victim, ("Player-1-CA%06X"):format(serial)))
				w.advance()
			end
			w.olympian(slayer)
			serial = serial + 1
			assert(w.kill(300 + serial, slayer, slayerGuid, target, targetGuid))
			w.advance()
		end

		cycle(2, "SlayerOne-Realm", "Player-1-DA000001")
		cycle(2, "SlayerTwo-Realm", "Player-1-DA000002")
		cycle(1, "SlayerThree-Realm", "Player-1-DA000003")
		local rank = W.Rankings()
		eq(rank.all[1].name, "SlayerOne-Realm", "the earlier equal total wins the deterministic tie")
		eq(rank.all[2].name, "SlayerTwo-Realm")
		local before = W.BorderAssignments(rank.all)
		eq(before["g:Player-1-DA000001"], "wanted-slayer-1")
		eq(before["g:Player-1-DA000002"], "wanted-slayer-2")
		eq(before["g:Player-1-DA000003"], "wanted-slayer-3")

		w.month = 11
		cycle(4, "SlayerFour-Realm", "Player-1-DA000004")
		rank = W.Rankings()
		eq(#rank.month, 1); eq(rank.month[1].name, "SlayerFour-Realm"); eq(rank.month[1].points, 4)
		eq(rank.all[1].name, "SlayerFour-Realm")
		local after = W.BorderAssignments(rank.all)
		eq(after["g:Player-1-DA000004"], "wanted-slayer-1")
		eq(after["g:Player-1-DA000001"], "wanted-slayer-2")
		eq(after["g:Player-1-DA000002"], "wanted-slayer-3")
		eq(after["g:Player-1-DA000003"], nil, "falling to fourth revokes the frame")

		eq(W.GlobalBorder("SlayerFour-Realm", "Player-1-DA000004"), nil, "local data never self-awards")
		W.GLOBAL_BORDERS_ACTIVE = true
		w.ns.rdb.wanted.authority = { verified = true }
		eq(W.GlobalBorder("SlayerFour-Realm", "Player-1-DA000004"), nil,
			"neither the switch nor forged SavedVariables can replace an authenticated snapshot")
	end)
end)

test("wanted publication through real Comm: publish and repeat enter the guarded queue and revoked publishers send nothing", function()
	WithWanted(function(w, W, c)
		local names = { "C_ChatInfo", "GetTime", "GetChannelName" }
		local saved = {}
		for _, name in ipairs(names) do saved[name] = _G[name] end
		local ok, err = pcall(function()
			local sent = {}
			C_ChatInfo = { RegisterAddonMessagePrefix = function() end,
				SendAddonMessage = function(_, text, dist) sent[#sent + 1] = { text = text, dist = dist }; return true end }
			GetTime = function() return w.epoch end
			GetChannelName = function() return 7, c.CHANNEL end
			c.db.blocked = {}
			c.Moderation.Blocks = function() return false end
			c.Log, c.Every, c.After = function() end, function() end, function() end
			c.SafeCall = function(_, fn, ...) return fn(...) end
			assert(loadfile(ROOT .. "Olympus/Comm.lua"))("Olympus", c)
			w.listeners.LOGIN()
			c.Comm.JoinChannel()
			w.authority(c.me, "king")
			local published, why = W.PublishGlobal()
			assert(published, "actual queue rejected publication: " .. tostring(why))
			assert(c.Comm.QueueSize() > 0)
			local function Drain()
				for _ = 1, 20 do
					if c.Comm.QueueSize() == 0 then break end
					w.advance(2); c.Comm.Pump()
				end
				eq(c.Comm.QueueSize(), 0)
			end
			Drain()
			local asm, full = c.Codec.NewAssembler()
			for _, message in ipairs(sent) do
				eq(message.dist, "CHANNEL")
				full = c.Codec.Feed(asm, c.me, message.text, w.epoch) or full
			end
			eq(full, c.db.wantedPublisher.last.body)
			assert(W.RepeatGlobal()); Drain()
			local before = #sent
			assert(W.RepeatGlobal())
			w.authorities[c.Fold(c.me)] = nil
			Drain(); eq(#sent, before, "revocation after admission blocks every delayed repeat part")
			w.authority(c.me, "king")
			assert(W.PublishGlobal())
			w.authorities[c.Fold(c.me)] = nil
			Drain(); eq(#sent, before, "revocation after admission blocks publication too")
		end)
		for _, name in ipairs(names) do _G[name] = saved[name] end
		if not ok then error(err, 0) end
	end)
end)

test("wanted global: only a fresh directly signed authority snapshot awards GUID-bound top-three borders", function()
	WithWanted(function(w, W, c)
		local council = w.authority("Council-Realm", "council")
		c.me = council
		local rows = {
			{ guid = "Player-1-DA000003", points = 7, claims = 2, reachedAt = w.epoch },
			{ guid = "Player-1-DA000001", points = 9, claims = 3, reachedAt = w.epoch },
			{ guid = "Player-1-DA000002", points = 7, claims = 1, reachedAt = w.epoch },
		}
		local ok, why, message = w.publish(rows, 100)
		eq(ok, true); eq(why, nil); assert(message and message:find("^WY~1~"))
		eq(W.GlobalBorder("Anybody-Realm", "Player-1-DA000001"), nil, "another client's publishing shows nothing here before its word comes")
		eq(w.pub.Wanted.GlobalBorder(nil, "Player-1-DA000001"), "wanted-slayer-1",
			"the publisher's own client holds the word it sent, checked as everyone checks it (the channel never echoes it)")
		eq(select(2, W.HandleGlobalSnapshot("WHISPER", council, message)), "lane", "the public snapshot has one direct lane")
		assert(W.HandleGlobalSnapshot("CHANNEL", council, message))
		eq(W.GlobalBorder("WrongName-Realm", "Player-1-DA000001"), "wanted-slayer-1")
		eq(W.GlobalBorder("Council-Realm"), nil, "a name alone is never global authority")
		eq(W.GlobalBorder("Third-Realm", "Player-1-DA000002"), "wanted-slayer-2", "equal points use reached time then GUID")
		eq(W.GlobalBorder("Third-Realm", "Player-1-DA000003"), "wanted-slayer-3")
		eq(W.GlobalBorder("Fourth-Realm", "Player-1-DA000004"), nil)

		local accepted = assert(W.GlobalSnapshot())
		eq(accepted.issuer, council); eq(accepted.epoch, 100); eq(#accepted.rows, 3)
		c.rdb.wanted = c.rdb.wanted or {}
		c.rdb.wanted.authority = { verified = true, rows = rows }
		eq(W.GlobalBorder("Fake-Realm", "Player-1-DA000004"), nil, "SavedVariables cannot add a holder")

		w.authorities[c.Fold(council)] = nil
		eq(W.GlobalBorder("WrongName-Realm", "Player-1-DA000001"), nil, "signed-role revocation removes the frame")
		eq(W.GlobalSnapshot(), nil)

		local king = w.authority("King-Realm", "king")
		c.me, c.db.wantedPublisher = king, nil
		local _, _, replacement = w.publish(rows, 99)
		assert(W.HandleGlobalSnapshot("CHANNEL", king, replacement),
			"revocation releases the old issuer's floor so another authority can recover without /reload")
		eq(W.GlobalSnapshot().issuer, king)
		-- This client is the King's: his revocation takes effect here as he sends it.
		assert(W.RevokeGlobal())
		eq(W.GlobalBorder(nil, "Player-1-DA000001"), nil, "an authority can explicitly revoke every frame")
		eq(W.GlobalSnapshot().issuer, king); eq(#W.GlobalSnapshot().rows, 0)
		eq(select(2, W.HandleGlobalSnapshot("CHANNEL", king, w.sent[#w.sent].text)), "replay", "the word it holds already")
	end)
end)

test("wanted global: forgery, replay, rollback, stale words, key conflicts and row bounds fail closed", function()
	WithWanted(function(w, W, c)
		local council = w.authority("Council-Realm", "council")
		c.me = council
		local one = { { guid = "Player-1-AA000011", points = 5, claims = 1, reachedAt = w.epoch } }
		local ok, _, first = w.publish(one, 300)
		assert(ok and first)
		local forged = first:gsub(":5:1:", ":9:1:", 1)
		assert(W.HandleGlobalSnapshot("CHANNEL", council, forged), "well-shaped forgery reaches verification")
		eq(W.GlobalSnapshot(), nil, "bad signature changes nothing")
		assert(W.HandleGlobalSnapshot("CHANNEL", council, first))
		eq(W.GlobalBorder(nil, "Player-1-AA000011"), "wanted-slayer-1")
		eq(select(2, W.HandleGlobalSnapshot("CHANNEL", council, first)), "replay")

		local function Fields(text)
			local out = {} for part in (text .. "~"):gmatch("([^~]*)~") do out[#out + 1] = part end return out
		end
		local function Resign(fields)
			local signed = table.concat({ "OLYW1", fields[3], fields[4], fields[5], fields[6], fields[7], fields[8], fields[9] }, "|")
			fields[11] = c.Debts.B64(c.Debts.Sign(signed))
			return table.concat(fields, "~")
		end
		local rollback = Fields(first); rollback[5], rollback[6] = "299", "99"; rollback = Resign(rollback)
		eq(select(2, W.HandleGlobalSnapshot("CHANNEL", council, rollback)), "rollback")
		local duplicate = Fields(first); duplicate[5], duplicate[6] = "301", "1"
		duplicate[9] = "1.aa000011:5:1:" .. w.epoch .. ",1.aa000011:4:1:" .. w.epoch
		duplicate = Resign(duplicate)
		eq(select(2, W.HandleGlobalSnapshot("CHANNEL", council, duplicate)), "rows")

		c.db.wantedPublisher = nil
		local four = {
			{ guid = "Player-1-AA000011", points = 5, claims = 1, reachedAt = w.epoch },
			{ guid = "Player-1-AA000012", points = 4, claims = 1, reachedAt = w.epoch },
			{ guid = "Player-1-AA000013", points = 3, claims = 1, reachedAt = w.epoch },
			{ guid = "Player-1-AA000014", points = 2, claims = 1, reachedAt = w.epoch },
		}
		eq(select(2, w.publish(four, 302)), "rows")

		local keyConflict = Fields(first); keyConflict[5], keyConflict[6] = "300", "2"
		keyConflict[10] = c.Debts.B64(string.rep("Q", 32)); keyConflict = Resign(keyConflict)
		eq(select(2, W.HandleGlobalSnapshot("CHANNEL", council, keyConflict)), "key")
		c.db.wantedPublisher = { epoch = w.epoch + W.GLOBAL_SKEW + 1, seq = 0 }
		eq(select(2, W.PublishGlobal()), "epoch",
			"a local clock-shaped epoch cannot be pushed arbitrarily into the future")

		c.db.wantedPublisher = nil
		local _, _, stale = w.publish(one, 400)
		w.advance(W.GLOBAL_LIFE + 1)
		eq(select(2, W.HandleGlobalSnapshot("CHANNEL", council, stale)), "stale")
		eq(W.GlobalBorder(nil, "Player-1-AA000011"), nil, "the previously held snapshot expires too")

		local outsider = "Outsider-Realm"
		local unauthorized = Fields(stale); unauthorized[4], unauthorized[5], unauthorized[6], unauthorized[7], unauthorized[8] =
			outsider, "401", "1", tostring(w.epoch), tostring(w.epoch + W.GLOBAL_LIFE)
		unauthorized = Resign(unauthorized)
		eq(select(2, W.HandleGlobalSnapshot("CHANNEL", outsider, unauthorized)), "authority")
	end)
end)

test("wanted global: an async verification rechecks realm scope before installing its result", function()
	WithWanted(function(w, W, c)
		local council = w.authority("Council-Realm", "council")
		c.me = council
		local rows = { { guid = "Player-1-AB000011", points = 3, claims = 1, reachedAt = w.epoch } }
		local _, _, message = w.publish(rows, 600)
		local queued
		c.Ed25519.Run = function(job, done) queued = { job = job, done = done }; return true end
		assert(W.HandleGlobalSnapshot("CHANNEL", council, message))
		assert(queued, "verification was queued")
		c.group = "AnotherRealmGroup"
		local ok, valid = pcall(queued.job)
		queued.done(ok, valid)
		eq(W.GlobalSnapshot(), nil, "a word parsed for the previous realm group is never installed")
	end)
end)

test("wanted global: an account-key rotation automatically starts a newer pinned epoch", function()
	WithWanted(function(w, W, c)
		local council = w.authority("Council-Realm", "council")
		c.me = council
		local rows = { { guid = "Player-1-AC000011", points = 4, claims = 1, reachedAt = w.epoch } }
		local _, _, first = w.publish(rows)
		assert(W.HandleGlobalSnapshot("CHANNEL", council, first))
		local epoch = W.GlobalSnapshot().epoch
		w.publicKey = string.rep("Q", 32)
		local _, _, rotated = w.publish(rows)
		assert(W.HandleGlobalSnapshot("CHANNEL", council, rotated), "the new key has a new epoch, not a same-epoch conflict")
		eq(W.GlobalSnapshot().epoch, epoch + 1)
		eq(w.pub.Wanted.GlobalSnapshot().epoch, epoch + 1, "on the publisher's own client too")
	end)
end)

test("wanted global: deterministic issuer conflicts and a newer empty snapshot revoke every border", function()
	WithWanted(function(w, W, c)
		local council = w.authority("Council-Realm", "council")
		local king = w.authority("King-Realm", "king")
		local rows = { { guid = "Player-1-BB000011", points = 2, claims = 1, reachedAt = w.epoch } }
		c.me = council; c.db.wantedPublisher = nil
		local _, _, councilWord = w.publish(rows, 500)
		c.me = king; c.db.wantedPublisher = nil
		local _, _, kingWord = w.publish(rows, 500)
		assert(W.HandleGlobalSnapshot("CHANNEL", council, councilWord))
		assert(W.HandleGlobalSnapshot("CHANNEL", king, kingWord), "the King wins an otherwise equal generation")
		eq(W.GlobalSnapshot().issuer, king)
		eq(select(2, W.HandleGlobalSnapshot("CHANNEL", council, councilWord)), "replay")

		w.advance(1)
		c.db.wantedPublisher = nil
		local _, _, revoke = w.publish({}, 501)
		assert(W.HandleGlobalSnapshot("CHANNEL", king, revoke))
		eq(W.GlobalBorder(nil, "Player-1-BB000011"), nil)
		eq(#W.GlobalSnapshot().rows, 0)
	end)
end)

test("wanted review: private bounded provenance stays pending until a human accepts and semantic duplicates score once", function()
	WithWanted(function(w, W, c)
		local reviewer = w.authority("Reviewer-Realm", "council")
		local submitter = w.participant("ReviewSlayer-Realm", "Player-1-EE000011")
		c.me, w.units.player.name, w.units.player.guid = submitter, submitter, "Player-1-EE000011"
		local target, targetGuid = "ReviewTarget-Realm", "Player-1-CC000011"
		assert(w.add(target, targetGuid))
		local ok, bounty = W.CaptureSelfDeathRecap({ fatal = true, id = "death-701", killerName = target,
			killerGUID = targetGuid, victimName = submitter, victimGUID = w.units.player.guid })
		assert(ok)
		w.advance()
		local claim
		ok, claim = w.kill(702, submitter, w.units.player.guid, target, targetGuid)
		assert(ok)
		assert(W.SubmitEvidence(reviewer, bounty.id)); local bountyWire = w.sent[#w.sent].text
		assert(W.SubmitEvidence(reviewer, claim.id)); local claimWire = w.sent[#w.sent].text
		assert(not bountyWire:find("Review", 1, true) and not bountyWire:find("Warsong", 1, true), "no names or locations leave privately")

		c.me = reviewer
		w.commHandlers.WX("WHISPER", submitter, bountyWire)
		w.commHandlers.WX("WHISPER", submitter, claimWire)
		w.commHandlers.WX("WHISPER", submitter, bountyWire)
		eq(#W.ReviewInbox(), 2, "the same submitter cannot replay a row")
		w.commHandlers.WX("CHANNEL", "Other-Realm", bountyWire)
		eq(#W.ReviewInbox(), 2, "raw evidence never uses the public lane")
		local inbox = W.ReviewInbox()
		assert(W.Review(inbox[1].key, true)); assert(W.Review(inbox[2].key, true))
		local ranked = W.ReviewedRankings()
		eq(#ranked, 1); eq(ranked[1].guid, "Player-1-EE000011"); eq(ranked[1].points, 1)
		assert(W.PublishGlobal({ { guid = "Player-1-FFFFFFFF", points = 999, claims = 9, reachedAt = w.epoch } }))
		local publication = w.sent[#w.sent].text
		assert(publication:find("1.ee000011", 1, true) and not publication:find("1.ffffffff", 1, true),
			"the public API publishes the reviewed ranking, never caller-supplied rows")

		w.commHandlers.WX("WHISPER", submitter, bountyWire:gsub("WX~1~%x+~", "WX~1~ffffffffffffff00~", 1))
		-- (The two accepted rows are in the ledger now, out of the inbox: the copy waits alone.)
		local third = W.ReviewInbox(); eq(#third, 1); assert(W.Review(third[1].key, true))
		ranked = W.ReviewedRankings()
		eq(ranked[1].points, 1, "a participant's duplicate account remains provenance, not extra points")
		W.REVIEW_MAX = 3
		for _, digest in ipairs({ "ffffffffffffff01", "ffffffffffffff02", "ffffffffffffff03", "ffffffffffffff04" }) do
			w.commHandlers.WX("WHISPER", submitter, (bountyWire:gsub("(%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x)", digest, 1)))
		end
		eq(#W.ReviewInbox(), 3, "the review inbox (what waits) is bounded")
	end)
end)

test("wanted monthly review: bounty pays in the claim month and month totals survive folding and reload", function()
	WithWanted(function(w, W, c)
		c.me = w.authority("MonthlyReviewer-Realm", "council")
		W.LEDGER_MAX = 2
		local firstMonth = W.MonthNow()
		local victim1 = w.participant("MonthlyVictim1-Realm", "Player-1-DD000001")
		local victim2 = w.participant("MonthlyVictim2-Realm", "Player-1-DD000002")
		local slayer = w.participant("MonthlySlayer-Realm", "Player-1-EE000001")
		local function Accept(digest, action, killer, victim, month)
			w.advance(10)
			local wire = ("WX~1~%016x~%d~%d~%s~%s~%s~%s"):format(digest, w.epoch, month, action == "B" and "S" or "P", action, killer, victim)
			w.commHandlers.WX("WHISPER", action == "C" and slayer or (victim == "1.dd000001" and victim1 or victim2), wire)
			local inbox = W.ReviewInbox()
			assert(#inbox == 1, "one authenticated-sender evidence row awaits review")
			assert(W.Review(inbox[1].key, true))
		end
		Accept(1, "B", "1.cc000001", "1.dd000001", firstMonth)
		eq(#W.ReviewedRankings(firstMonth), 0, "an open bounty awards no slayer")
		w.month = w.month + 1
		local claimMonth = W.MonthNow()
		Accept(2, "C", "1.ee000001", "1.cc000001", claimMonth)
		eq(#W.ReviewedRankings(firstMonth), 0, "points belong to the death that closed the bounty")
		eq(W.ReviewedRankings(claimMonth)[1].points, 1)
		Accept(3, "B", "1.cc000001", "1.dd000002", claimMonth)
		Accept(4, "C", "1.ee000001", "1.cc000001", claimMonth)
		eq(W.ReviewedRankings()[1].points, 2)
		eq(W.ReviewedRankings(claimMonth)[1].points, 2)
		eq(W.ReviewedRankings(claimMonth)[1].claims, 2)
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted; assert(W.Load())
		eq(W.ReviewedRankings(claimMonth)[1].points, 2, "the folded claim's monthly points persist")
		w.month = w.month + 1
		eq(#W.ReviewedRankings(W.MonthNow()), 0, "a new month starts empty")
		eq(W.ReviewedRankings()[1].points, 2, "all-time totals survive rollover")
	end)
end)

test("wanted review: per-sender flood limits and rejection preserve room for another participant", function()
	WithWanted(function(w, W, c)
		local reviewer = w.authority("Reviewer-Realm", "council")
		c.me = reviewer
		W.REVIEW_MAX, W.REVIEW_PER_SENDER, W.REVIEW_RATE_MAX = 2, 2, 2
		local flood = w.participant("Flood-Realm", "Player-1-BB000011")
		local other = w.participant("OtherVictim-Realm", "Player-1-BB000012")
		local base = ("WX~1~0000000000000001~%d~24000~S~B~1.aa000011~1.bb000011"):format(w.epoch)
		local second = base:gsub("0000000000000001", "0000000000000002", 1)
		local third = base:gsub("0000000000000001", "0000000000000003", 1)
		w.commHandlers.WX("WHISPER", "Flood-Realm", base)
		w.commHandlers.WX("WHISPER", "Flood-Realm", second)
		w.commHandlers.WX("WHISPER", "Flood-Realm", third)
		eq(#W.ReviewInbox(), 2, "one sender cannot exceed its bounded burst")
		local rejected = W.ReviewInbox()[1]
		assert(W.Review(rejected.key, false))
		eq(#W.ReviewInbox(), 1, "rejecting untrusted evidence frees its slot")
		w.commHandlers.WX("WHISPER", other, third:gsub("1.bb000011", "1.bb000012", 1))
		eq(#W.ReviewInbox(), 2, "another participant can still reach the reviewer")
	end)
end)

test("wanted: slayer rows alone open the normal Olympus person profile", function()
	WithWanted(function(w, W)
		local target, targetGuid = "ProfileTarget-Realm", "Player-1-BC000001"
		assert(w.add(target, targetGuid))
		w.olympian("ProfileVictim-Realm")
		assert(w.kill(401, target, targetGuid, "ProfileVictim-Realm", "Player-1-CD000001"))
		w.advance()
		w.olympian("ProfileSlayer-Realm")
		assert(w.kill(402, "ProfileSlayer-Realm", "Player-1-DE000001", target, targetGuid))
		local lines = W.Build()
		local targetRow, slayerRow
		for _, line in ipairs(lines) do
			if line.id and line.id:find("wanted:", 1, true) then targetRow = line end
			if line.player == "ProfileSlayer-Realm" then slayerRow = line end
		end
		assert(targetRow and slayerRow and slayerRow.onClick)
		targetRow.onClick(); eq(w.profile, nil)
		W.Back(); assert(slayerRow.onClick())
		eq(w.profile.name, "ProfileSlayer"); eq(w.profile.realm, "Realm")
	end)
end)

---------------------------------------------------------------------------
-- Adversarial evidence, the reviewer's controls and ledger, honest labels
---------------------------------------------------------------------------

-- An edit box as the dialogs read it.
local function Box(text)
	return { text = text or "", GetText = function(self) return self.text end, SetText = function(self, t) self.text = t end,
		SetFocus = function(self) self.focused = true end }
end

local function Shown(W)
	local out = {}
	for _, def in ipairs(W.buttons) do if not def.shown or def.shown() then out[#out + 1] = def[1] end end
	return table.concat(out, ",")
end

local function Press(W, key)
	for _, def in ipairs(W.buttons) do
		if def[1] == key then assert(not def.shown or def.shown(), key .. " is shown") return def[2]() end
	end
	error("no button " .. key)
end

local function Headers(lines)
	local out = {}
	for _, line in ipairs(lines) do if line.header then out[#out + 1] = line.text end end
	return out
end

test("wanted adversarial: a pet, a creature or the environment never credits a kill nor matches a listed name", function()
	WithWanted(function(w, W, c)
		assert(w.add("Grom-Realm"), "a name-only listing, no GUID yet")
		local petGuid = "Pet-0-4170-1-123-416-0300ABCDEF"
		local creatureGuid = "Creature-0-4170-1-123-12345-0000ABCDEF"
		-- A hunter can call his wolf by the listed name; its killing blow on an Olympian:
		local ok, why = w.kill(901, "Grom", petGuid, c.me, w.units.player.guid)
		eq(ok, false); eq(why, "identities", "a pet carrying the listed name is not the listed player")
		-- An Olympian killing an NPC that carries the listed name:
		w.advance(); local slayer = w.olympian("PetSlayer-Realm")
		ok, why = w.kill(902, slayer, "Player-1-DF000001", "Grom", creatureGuid)
		eq(ok, false); eq(why, "identities", "an NPC carrying the listed name pays nobody")
		-- An Olympian's pet lands the killing blow on the listed player: the row names the pet, not its owner.
		w.advance()
		ok, why = w.kill(903, "Wolf", petGuid, "Grom-Realm", "Player-1-BB000009")
		eq(ok, false); eq(why, "identities", "pet credit is never guessed for its owner")
		-- The environment (a fall, lava, drowning) in the guarded self-death recap: no player killer.
		w.advance()
		ok, why = W.CaptureSelfDeathRecap({ fatal = true, killerName = "Falling", victimName = c.me, victimGUID = w.units.player.guid })
		eq(ok, false); eq(why, "identities")
		ok, why = W.CaptureSelfDeathRecap({ fatal = true, killerName = "Grom", killerGUID = creatureGuid,
			victimName = c.me, victimGUID = w.units.player.guid })
		eq(ok, false); eq(why, "identities")
		local t = W.Target("Grom-Realm")
		eq(t.current, 0); eq(t.lifetimeKills, 0); eq(#t.claims, 0); eq(t.guid, nil, "no refused row taught the listing a GUID")
		eq(#W.Rankings().all, 0); eq(W.Stats().accepted, 0)
	end)
end)

test("wanted adversarial: one death has one killer: a second claimant in the same moment is refused, and one death read twice across a 3-second bucket counts once", function()
	WithWanted(function(w, W)
		local target, targetGuid = "Twice-Realm", "Player-1-BD000001"
		assert(w.add(target, targetGuid))
		assert(w.kill(911, target, targetGuid, w.olympian("TwiceVictim-Realm"), "Player-1-CE000001"))
		w.advance()
		local first, second = w.olympian("FirstBlade-Realm"), w.olympian("SecondBlade-Realm")
		assert(w.kill(912, first, "Player-1-DF000011", target, targetGuid))
		local ok, why = w.kill(913, second, "Player-1-DF000012", target, targetGuid)
		eq(ok, false); eq(why, "conflict", "two killers named for one death in the same moment")
		local t = W.Target(target)
		eq(#t.claims, 1, "no second, empty closed cycle for the same death"); eq(t.claims[1].points, 1); eq(t.cycle, 2)
		local ranks = W.Rankings().all
		eq(#ranks, 1); eq(ranks[1].name, first); eq(W.Stats().conflict, 1)

		-- The last second of one 3-second bucket, then the first of the next: the victim's own recap
		-- and the party's combat log name the same death a second apart.
		local ripper, ripperGuid = "Ripper-Realm", "Player-1-BD000002"
		assert(w.add(ripper, ripperGuid))
		w.epoch = 1800000302
		eq(math.floor(w.epoch / 3) ~= math.floor((w.epoch + 1) / 3), true, "the two reads straddle a bucket edge")
		assert(W.CaptureSelfDeathRecap({ fatal = true, id = "edge-1", killerName = ripper, killerGUID = ripperGuid,
			victimName = w.ns.me, victimGUID = w.units.player.guid }))
		w.advance(1)
		ok, why = w.kill("edge-2", ripper, ripperGuid, w.ns.me, w.units.player.guid)
		eq(ok, false); eq(why, "replay")
		eq(W.Target(ripper).current, 1, "one death, one bounty point")
		w.advance(W.DEATH_WINDOW + 1)
		assert(w.kill("later", ripper, ripperGuid, w.ns.me, w.units.player.guid), "a later death counts")
		eq(W.Target(ripper).current, 2)
	end)
end)

test("wanted adversarial: cross-realm names stay apart, and an Olympian of a connected realm still claims", function()
	WithWanted(function(w, W, c)
		assert(w.add("Grom-Other Realm"), "a realm typed with its space")
		local t = assert(W.Target("Grom-OtherRealm"), "one spelling of that realm")
		eq(t.name, "Grom-OtherRealm")
		eq(W.Target("Grom-Realm"), nil, "a namesake on our realm is another character")
		assert(w.add("Thrall"), "typed without a realm: ours")
		eq(W.Target("Thrall-Realm").name, "Thrall-Realm")
		local ok, why = w.kill(921, "Grom-Realm", "Player-2-AA000001", c.me, w.units.player.guid)
		eq(ok, false); eq(why, "unlisted", "our realm's Grom is not the listed one")
		w.advance()
		ok, why = w.kill(922, "Thrall-OtherRealm", "Player-2-AA000002", c.me, w.units.player.guid)
		eq(ok, false); eq(why, "unlisted", "another realm's Thrall is not ours")
		eq(W.Target("Thrall-Realm").guid, nil); eq(W.Target("Grom-OtherRealm").guid, nil)
		w.advance()
		local ally = w.olympian("Ally-OtherRealm")
		assert(w.kill(923, "Grom-OtherRealm", "Player-2-AA000003", ally, "Player-2-CC000001"))
		t = W.Target("Grom-OtherRealm"); eq(t.current, 1); eq(t.guid, "Player-2-AA000003")
		w.advance()
		local slayer = w.olympian("Slayer-OtherRealm")
		assert(w.kill(924, slayer, "Player-2-DD000001", "Grom-OtherRealm", "Player-2-AA000003"))
		eq(W.Rankings().all[1].name, "Slayer-OtherRealm"); eq(W.Rankings().all[1].points, 1)
	end)
end)

test("wanted: native PARTY_KILL credits only our verified killing blow and closes each bounty cycle once", function()
	WithWanted(function(w, W, c)
		local event = assert(w.handlers.PARTY_KILL, "the documented two-GUID native event is connected")
		local name, guid, mine = "Native Horde-Realm", "Player-1-CF000021", w.units.player.guid
		assert(w.add(name, guid))
		local function Bounty(id, victimGuid)
			w.advance()
			assert(w.kill(id, name, guid, w.olympian("NativeVictim" .. id .. "-Realm"), victimGuid))
		end
		Bounty(2101, "Player-1-DF000021"); Bounty(2102, "Player-1-DF000022")
		eq(W.Target(nil, guid).current, 2)
		w.advance(); assert(event(mine, guid))
		local rank = W.Rankings()
		eq(rank.all[1].guid, mine); eq(rank.all[1].points, 2); eq(rank.month[1].points, 2)
		eq(W.Target(nil, guid).current, 0); eq(W.Target(nil, guid).cycle, 2)
		eq(event(mine, guid), false, "the same native death cannot claim again")
		w.advance(); assert(event(mine, guid))
		eq(W.Rankings().all[1].points, 2, "a later empty bounty awards no additional points")
		Bounty(2103, "Player-1-DF000023")
		w.month = w.month + 1; w.advance(); assert(event(mine, guid))
		eq(W.Target(nil, guid).current, 0); eq(W.Rankings().all[1].points, 3)
		eq(W.Rankings().month[1].points, 1, "the fresh bounty pays in the claim month")
		local before = W.Stats().accepted
		for _, pair in ipairs({
			{ "Player-1-FF000021", guid }, { "Pet-1-00000021", guid },
			{ "Creature-1-00000021", guid }, { mine, "Player-1-FF000022" },
			{ mine, "Native Horde-Realm" }, { mine, "Creature-1-00000021" },
		}) do eq(event(pair[1], pair[2]), false) end
		w.member = false; w.advance(); eq(event(mine, guid), false); w.member = true
		w.advance(61); W.RATE_MAX = 0; eq(event(mine, guid), false); W.RATE_MAX = 20
		local secret = setmetatable({}, { __tostring = function() error("secret was converted") end })
		issecretvalue = function(value) return rawequal(value, secret) end
		eq(event(secret, guid), false); eq(event(mine, secret), false)
		issecretvalue = nil
		assert(W.RemoveTarget(nil, guid)); w.advance(); eq(event(mine, guid), false)
		eq(W.Stats().accepted, before, "invalid, secret and removed identities never record a kill")
		eq(#w.sent, 0, "native capture publishes nothing automatically")
	end)
end)

test("wanted: native PARTY_KILL unavailable registration cannot abort addon loading", function()
	WithWanted(function(w, W, c)
		local register = c.RegisterEvent
		c.RegisterEvent = function(name, call)
			if name == "PARTY_KILL" then error("native event unavailable") end
			return register(name, call)
		end
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		assert(type(c.Wanted.CapturePartyKill) == "function")
		assert(type(w.handlers.PLAYER_DEAD) == "function", "other supported capture remains registered")
	end)
end)

test("wanted native autoadd: own fatal recap adds only a unit-verified Horde killer, with bounds and removal respected", function()
	WithWanted(function(w, W, c)
		w.manager = false
		local guid = "Player-1-EF000009"
		w.units.target = { name = "New Horde-Realm", guid = guid, faction = "Horde" }
		local row = { sourceGUID = guid, sourceName = "New-Realm", sourceFlags = 0x440,
			event = "SPELL_DAMAGE", overkill = 0, timestamp = w.epoch }
		C_DeathInfo = nil
		C_DeathRecap = { HasRecapEvents = function() return true end, GetRecapEvents = function() return { row } end }
		w.dead = true; w.handlers.PLAYER_DEAD()
		local target = assert(W.Target(nil, guid), "a non-moderator's verified own death discovers a Horde offender")
		eq(target.current, 1); eq(target.name, "New Horde-Realm")
		w.handlers.PLAYER_DEAD(); eq(W.Target(nil, guid).current, 1, "repeated recap cannot add a second bounty")
		w.manager = true; assert(W.RemoveTarget(nil, guid)); w.manager = false
		w.advance(); row.timestamp = w.epoch; w.handlers.PLAYER_DEAD()
		eq(W.Target(nil, guid).active, false); eq(W.Target(nil, guid).current, 1, "manual removal is never undone by capture")
		local function Refused(id, faction)
			w.advance(); row.timestamp, row.sourceGUID = w.epoch, id
			w.units.target = { name = "Unverified-Realm", guid = id, faction = faction }
			w.handlers.PLAYER_DEAD(); eq(W.Target(nil, id), nil)
		end
		Refused("Player-1-EF000010", nil)
		Refused("Player-1-EF000011", "Alliance")
		Refused("Pet-1-00000012", "Horde")
		W.MAX_TARGETS = 1; Refused("Player-1-EF000013", "Horde")
		W.MAX_TARGETS = 200
		local oldFaction = UnitFactionGroup
		UnitFactionGroup = function() error("unit faction unavailable") end
		Refused("Player-1-EF000014", "Horde")
		UnitFactionGroup = oldFaction
		row.overkill = -1; Refused("Player-1-EF000015", "Horde")
		eq(#W.Targets(), 1, "rejected rows create no targets")
		-- A nameplate may vanish on the fatal event. Cache only the actual Horde unit observation.
		UnitCanAttack, UnitIsPVP = function() return true end, function() return true end
		w.units.target = { name = "Cached Horde-Realm", guid = "Player-1-EF000016", faction = "Horde" }
		W.ObserveUnit("target")
		w.units.target = nil
		w.advance(); row.sourceGUID, row.sourceName, row.overkill, row.timestamp = "Player-1-EF000016", "Cached-Realm", 0, w.epoch
		w.handlers.PLAYER_DEAD()
		eq(assert(W.Target(nil, row.sourceGUID)).current, 1)
		w.units.target = { name = "Expired Horde-Realm", guid = "Player-1-EF000017", faction = "Horde" }
		W.ObserveUnit("target"); w.units.target = nil
		w.advance(61); row.sourceGUID, row.timestamp = "Player-1-EF000017", w.epoch
		w.handlers.PLAYER_DEAD(); eq(W.Target(nil, row.sourceGUID), nil, "expired faction knowledge cannot auto-add")
	end)
end)

test("wanted native recap: a fresh explicit player killing blow counts once; damage, old recaps and pets never count", function()
	WithWanted(function(w, W, c)
		local targetGuid = "Player-1-EF000002"
		assert(w.add("Reaper Full-Realm", targetGuid))
		local row = { sourceGUID = targetGuid, sourceName = "Reaper-Realm", sourceFlags = 0x440,
			event = "SPELL_DAMAGE", overkill = 0, timestamp = w.epoch + 0.1 }
		local ready, retries = false, {}
		c.After = function(_, _, fn) retries[#retries + 1] = fn end
		C_DeathInfo = nil
		C_DeathRecap = { HasRecapEvents = function() return ready end, GetRecapEvents = function() return { row } end }
		w.dead = true; w.handlers.PLAYER_DEAD()
		eq(W.Target(nil, targetGuid).current, 0, "the native recap may not be ready on the death event")
		eq(#retries, 3); ready = true
		for _, retry in ipairs(retries) do retry() end
		eq(W.Target(nil, targetGuid).current, 1)
		eq(W.Target(nil, targetGuid).name, "Reaper Full-Realm", "recap's abbreviated name never overwrites known full identity")
		w.handlers.PLAYER_DEAD(); eq(W.Target(nil, targetGuid).current, 1, "one fatal row pays once")
		w.advance(10); w.handlers.PLAYER_DEAD(); eq(W.Target(nil, targetGuid).current, 1, "last death's stale recap is not a new death")
		row.timestamp, row.overkill = w.epoch, -1
		w.handlers.PLAYER_DEAD(); eq(W.Target(nil, targetGuid).current, 1, "ordinary damage is not a killing blow")
		row.overkill, row.sourceGUID = 0, "Pet-1-00000002"
		w.handlers.PLAYER_DEAD(); eq(W.Target(nil, targetGuid).current, 1)
		row.sourceGUID, row.sourceFlags = targetGuid, 0x410
		w.handlers.PLAYER_DEAD(); eq(W.Target(nil, targetGuid).current, 1, "friendly source does not count")
		row.sourceFlags = 0x440; w.dead = false
		w.handlers.PLAYER_DEAD(); eq(W.Target(nil, targetGuid).current, 1, "living player has no death to attribute")
	end)
end)

test("wanted native named listing: a locally verified Horde fatal own death learns its GUID and counts once", function()
	WithWanted(function(w, W)
		local name, guid = "Named Horde-Realm", "Player-1-EF000091"
		assert(w.add(name))
		w.manager = false
		w.units.target = { name = name, guid = guid, faction = "Horde" }
		local row = { sourceGUID = guid, sourceName = name, sourceFlags = 0x440,
			event = "SPELL_DAMAGE", overkill = -1, timestamp = w.epoch }
		C_DeathInfo = nil
		C_DeathRecap = { HasRecapEvents = function() return true end, GetRecapEvents = function() return { row } end }
		w.dead = true
		w.handlers.PLAYER_DEAD()
		eq(W.Target(name).guid, nil, "nonfatal damage never pins a name-only listing")
		eq(W.Target(name).current, 0)
		row.overkill, row.timestamp = 0, w.epoch - W.DEATH_WINDOW - 1
		w.handlers.PLAYER_DEAD()
		eq(W.Target(name).guid, nil, "a stale fatal recap never pins a name-only listing")
		row.timestamp = w.epoch
		w.handlers.PLAYER_DEAD()
		local target = W.Target(name)
		eq(target.current, 1, "a prior name-only listing must not suppress a verified own death")
		eq(target.guid, guid, "only the actual locally observed Horde GUID is learned")
		eq(#W.Targets(), 1, "the existing listing is upgraded, never duplicated")
		eq(#w.ns.rdb.wanted.evidence, 1)
		w.handlers.PLAYER_DEAD()
		eq(W.Target(nil, guid).current, 1, "reading the same native death again never counts twice")
		w.advance(W.DEATH_WINDOW + 1)
		w.handlers.PLAYER_DEAD()
		eq(W.Target(nil, guid).current, 1, "last death's stale recap is not a new death")
		row.timestamp, row.overkill = w.epoch, -1
		w.handlers.PLAYER_DEAD()
		eq(W.Target(nil, guid).current, 1, "fresh nonfatal damage still cannot add a bounty")
		eq(#w.sent, 0, "learning an observed identity publishes nothing automatically")
	end)
end)

test("wanted native named listing: an unobserved recap identity cannot teach the listing a Horde GUID", function()
	WithWanted(function(w, W)
		local name, guid = "Unobserved Horde-Realm", "Player-1-EF000092"
		assert(w.add(name))
		local row = { sourceGUID = guid, sourceName = name, sourceFlags = 0x440,
			event = "SPELL_DAMAGE", overkill = 0, timestamp = w.epoch }
		C_DeathInfo = nil
		C_DeathRecap = { HasRecapEvents = function() return true end, GetRecapEvents = function() return { row } end }
		w.dead = true; w.handlers.PLAYER_DEAD()
		eq(W.Target(name).guid, nil, "the recap's hostile flag alone is not Horde faction proof")
		eq(W.Target(name).current, 0)
		eq(W.Target(nil, guid), nil)
		eq(#W.Targets(), 1)
		eq(#w.ns.rdb.wanted.evidence, 0)
	end)
end)

test("wanted native named listing: a conflicting pinned GUID cannot be replaced by a different observed killer", function()
	WithWanted(function(w, W)
		local name = "Pinned Horde-Realm"
		local pinned, other = "Player-1-EF000093", "Player-1-EF000094"
		assert(w.add(name, pinned))
		w.units.target = { name = name, guid = other, faction = "Horde" }
		local row = { sourceGUID = other, sourceName = name, sourceFlags = 0x440,
			event = "SPELL_DAMAGE", overkill = 0, timestamp = w.epoch }
		C_DeathInfo = nil
		C_DeathRecap = { HasRecapEvents = function() return true end, GetRecapEvents = function() return { row } end }
		w.dead = true; w.handlers.PLAYER_DEAD()
		eq(W.Target(name).guid, pinned, "a matching name cannot replace its pinned identity")
		eq(W.Target(nil, pinned).current, 0)
		eq(W.Target(nil, other), nil, "the conflict cannot create a second listing with the same name")
		eq(#W.Targets(), 1)
		eq(#w.ns.rdb.wanted.evidence, 0)
	end)
end)

test("wanted native named listing: a current contradictory faction overrides earlier Horde knowledge", function()
	WithWanted(function(w, W)
		local name, guid = "Contradictory Horde-Realm", "Player-1-EF000095"
		UnitCanAttack, UnitIsPVP = function() return true end, function() return true end
		w.units.target = { name = name, guid = guid, faction = "Horde" }
		W.ObserveUnit("target")
		assert(w.add(name))
		w.units.target.faction = "Alliance"
		local row = { sourceGUID = guid, sourceName = name, sourceFlags = 0x440,
			event = "SPELL_DAMAGE", overkill = 0, timestamp = w.epoch }
		C_DeathInfo = nil
		C_DeathRecap = { HasRecapEvents = function() return true end, GetRecapEvents = function() return { row } end }
		w.dead = true; w.handlers.PLAYER_DEAD()
		eq(W.Target(name).guid, nil, "current Alliance identity cannot become a Horde listing's GUID")
		eq(W.Target(name).current, 0)
		eq(W.Target(nil, guid), nil)
		eq(#W.Targets(), 1)
		eq(#w.ns.rdb.wanted.evidence, 0)
	end)
end)

test("wanted PLAYER_DEAD: Forever's C_DeathInfo has no recap reader, so a death records nothing; a failing reader is contained", function()
	WithWanted(function(w, W, c)
		local targetGuid = "Player-1-EF000001"
		assert(w.add("Reaper-Realm", targetGuid))
		assert(type(w.handlers.PLAYER_DEAD) == "function", "the handler is registered")
		-- Forever's C_DeathInfo as its API documentation lists it (DeathInfoDocumentation.lua): no
		-- death recap. C_DeathRecap.GetRecapEvents exists there but takes a recap ID; until the
		-- in-game API check it is not guessed at.
		C_DeathInfo = { GetCorpseMapPosition = function() end, GetDeathReleasePosition = function() end,
			GetGraveyardsForMap = function() return {} end, GetSelfResurrectOptions = function() return {} end,
			UseSelfResurrectOption = function() end }
		local recapCalls = 0
		C_DeathRecap = { GetRecapEvents = function()
			recapCalls = recapCalls + 1
			return { { fatal = true, killerName = "Reaper-Realm", killerGUID = targetGuid, victimName = c.me, victimGUID = w.units.player.guid } }
		end }
		w.dead = true
		w.handlers.PLAYER_DEAD()
		eq(W.Target("Reaper-Realm").current, 0, "no supported fatal source: no automatic count")
		eq(recapCalls, 0, "the unverified recap API is not read")
		C_DeathInfo = { GetDeathRecapEvents = function() error("recap reader failed") end }
		w.handlers.PLAYER_DEAD()
		eq(W.Target("Reaper-Realm").current, 0, "a reader that throws changes nothing")
		-- The present reader's shape (a stand-in: it proves nothing about the client) goes through
		-- the same gates as CaptureSelfDeathRecap.
		C_DeathInfo = { GetDeathRecapEvents = function()
			return { { fatal = true, id = "pd-1", killerName = "Reaper-Realm", killerGUID = targetGuid,
				victimName = c.me, victimGUID = w.units.player.guid } }
		end }
		w.dead = false; w.handlers.PLAYER_DEAD()
		eq(W.Target("Reaper-Realm").current, 0, "alive: nothing")
		w.dead = true; w.handlers.PLAYER_DEAD()
		eq(W.Target("Reaper-Realm").current, 1)
		w.advance(); w.handlers.PLAYER_DEAD()
		eq(W.Target("Reaper-Realm").current, 1, "the same recap row read at the next death is a replay")
	end)
end)

test("wanted review adversarial: a modified client's WX (future, stale, malformed, another version, or to a non-reviewer) is kept nowhere", function()
	WithWanted(function(w, W, c)
		local reviewer = w.authority("Reviewer-Realm", "council")
		w.participant("Modded-Realm", "Player-1-DD000011")
		c.me = reviewer
		local H = w.commHandlers.WX
		local good = "WX~1~00000000000000a1~%d~24000~P~C~1.dd000011~1.cc000011"
		H("WHISPER", "Modded-Realm", good:format(w.epoch + W.GLOBAL_SKEW + 60))
		H("WHISPER", "Modded-Realm", good:format(w.epoch - W.EVIDENCE_AGE - 1))
		H("WHISPER", "Modded-Realm", ("WX~1~00000000000000a2~%d~24000~P~C~1.DD000011~1.cc000011"):format(w.epoch))
		H("WHISPER", "Modded-Realm", ("WX~1~00000000000000a3~%d~24000~P~C~Pet-0-1-2-3-4-5~1.cc000011"):format(w.epoch))
		H("WHISPER", "Modded-Realm", ("WX~2~00000000000000a4~%d~24000~P~C~1.dd000011~1.cc000011"):format(w.epoch))
		H("WHISPER", "Modded-Realm", ("WX~1~00a5~%d~24000~P~C~1.dd000011~1.cc000011"):format(w.epoch))
		H("WHISPER", "Modded-Realm", ("WX~1~00000000000000a6~%d~24000~P~C~1.dd000011~1.cc000011~extra"):format(w.epoch))
		H("WHISPER", "Modded-Realm", ("WX~1~00000000000000a7~%d~24000~X~C~1.dd000011~1.cc000011"):format(w.epoch))
		eq(#W.ReviewInbox(), 0, "none of them is kept")
		c.me = "Member-Realm"
		H("WHISPER", "Modded-Realm", good:format(w.epoch))
		eq(#W.ReviewInbox(), 0, "a member who is no reviewer keeps nothing")
		c.me = reviewer
		H("WHISPER", "Modded-Realm", good:format(w.epoch))
		eq(#W.ReviewInbox(), 1, "the well-formed row to a reviewer waits for him")
		eq(W.ReviewInbox()[1].state, "pending")
		eq(W.Stats().reviewed, 0, "and nothing was accepted by itself")
	end)
end)

test("wanted review: a victim's copies of one death a second apart, across a 3-second bucket, pay one bounty point", function()
	WithWanted(function(w, W, c)
		c.me = w.authority("Reviewer-Realm", "council")
		local at = 1800000302
		eq(math.floor(at / 3) ~= math.floor((at + 1) / 3), true, "the copies straddle a bucket edge")
		w.epoch = at + 10
		local victimName = w.participant("Victim-Realm", "Player-1-CD000101")
		local slayerName = w.participant("Slayer-Realm", "Player-1-EF000101")
		local function Wire(digest, t, action, killer, victim)
			return ("WX~1~%s~%d~24000~%s~%s~%s~%s"):format(digest, t, action == "B" and "S" or "P", action, killer, victim)
		end
		w.commHandlers.WX("WHISPER", victimName, Wire("00000000000000f1", at, "B", "1.ab000101", "1.cd000101"))
		w.commHandlers.WX("WHISPER", victimName, Wire("00000000000000f2", at + 1, "B", "1.ab000101", "1.cd000101"))
		w.commHandlers.WX("WHISPER", slayerName, Wire("00000000000000f3", at + 8, "C", "1.ef000101", "1.ab000101"))
		for _, e in ipairs(W.ReviewInbox()) do assert(W.Review(e.key, true)) end
		local rows = W.ReviewedRankings()
		eq(#rows, 1); eq(rows[1].guid, "Player-1-EF000101"); eq(rows[1].points, 1, "one death, one bounty point")
	end)
end)

test("wanted global: the King's newer word replaces a councillor's whose key epoch began later (the epoch orders one publisher's own words only)", function()
	WithWanted(function(w, W, c)
		local council = w.authority("Council-Realm", "council")
		local king = w.authority("King-Realm", "king")
		local rows = { { guid = "Player-1-BB000021", points = 3, claims = 1, reachedAt = w.epoch } }
		c.me = king; c.db.wantedPublisher = nil
		local _, _, kingFirst = w.publish(rows, 1000)
		local kingState = c.db.wantedPublisher
		assert(W.HandleGlobalSnapshot("CHANNEL", king, kingFirst))
		eq(W.GlobalSnapshot().issuer, king)
		w.advance(60)
		c.me = council; c.db.wantedPublisher = nil
		local _, _, councilWord = w.publish({ { guid = "Player-1-BB000022", points = 5, claims = 2, reachedAt = w.epoch } }, 2000)
		assert(W.HandleGlobalSnapshot("CHANNEL", council, councilWord))
		eq(W.GlobalSnapshot().issuer, council, "the newer word replaces the King's")
		w.advance(60)
		c.me, c.db.wantedPublisher = king, kingState
		local _, _, revoke = w.publish({})
		local ok, why = W.HandleGlobalSnapshot("CHANNEL", king, revoke)
		eq(ok, true, tostring(why))
		eq(W.GlobalSnapshot().issuer, king, "the King's later revocation wins, whatever his key's epoch")
		eq(#W.GlobalSnapshot().rows, 0)
		eq(W.GlobalBorder(nil, "Player-1-BB000022"), nil)
		eq(select(2, W.HandleGlobalSnapshot("CHANNEL", council, councilWord)), "replay", "the councillor's word, heard again, changes nothing")
	end)
end)

test("wanted ledger: accepted rows survive a reload, fold past the bound without changing the totals, and a row sent again or another copy of a death counts once", function()
	WithWanted(function(w, W, c)
		local reviewer = w.authority("Reviewer-Realm", "council")
		c.me = reviewer
		local function Wire(digest, at, action, killer, victim)
			return ("WX~1~%s~%d~24000~%s~%s~%s~%s"):format(digest, at, action == "B" and "S" or "P", action, killer, victim)
		end
		local T, S = "1.ab000001", "1.ef000001"
		local victim1 = w.participant("LedgerVictim1-Realm", "Player-1-CD000001")
		local victim2 = w.participant("LedgerVictim2-Realm", "Player-1-CD000002")
		local victim3 = w.participant("LedgerVictim3-Realm", "Player-1-CD000003")
		local slayer = w.participant("LedgerSlayer-Realm", "Player-1-EF000001")
		local senders = { victim1, victim2, slayer }
		local rowsSent = {
			Wire("00000000000000b1", w.epoch - 60, "B", T, "1.cd000001"),
			Wire("00000000000000b2", w.epoch - 50, "B", T, "1.cd000002"),
			Wire("00000000000000c1", w.epoch - 40, "C", S, T),
		}
		for i, wire in ipairs(rowsSent) do w.commHandlers.WX("WHISPER", senders[i], wire) end
		for _, e in ipairs(W.ReviewInbox()) do assert(W.Review(e.key, true)) end
		local before = W.ReviewedRankings()
		eq(#before, 1); eq(before[1].guid, "Player-1-EF000001"); eq(before[1].points, 2); eq(before[1].claims, 1)
		eq(#c.rdb.wanted.ledger.accepted, 3, "kept in the reviewer's saved data")

		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted
		assert(W.Load())
		eq(#W.ReviewInbox(), 0, "the session inbox starts empty")
		local after = W.ReviewedRankings()
		eq(after[1].points, 2, "the all-time top three did not start over")
		w.commHandlers.WX("WHISPER", slayer, rowsSent[3])
		eq(#W.ReviewInbox(), 0, "a row accepted before the reload is not taken again")

		W.LEDGER_MAX = 2
		w.commHandlers.WX("WHISPER", victim3, Wire("00000000000000b3", w.epoch - 30, "B", T, "1.cd000003"))
		assert(W.Review(W.ReviewInbox()[1].key, true))
		local rows, folded = W.Ledger()
		eq(#rows, 2); eq(folded, 2, "the two oldest folded into the base")
		eq(W.ReviewedRankings()[1].points, 2, "folding changes no total")
		-- The slayer's second account of the folded claim (same death, two seconds apart):
		-- provenance, never a second payout.
		w.commHandlers.WX("WHISPER", slayer, Wire("00000000000000d1", w.epoch - 38, "C", S, T))
		local copy = W.ReviewInbox()
		assert(W.Review(copy[#copy].key, true))
		eq(W.ReviewedRankings()[1].points, 2)
		eq(W.ReviewedRankings()[1].claims, 1)

		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted
		W.LEDGER_MAX = 2
		assert(W.Load())
		eq(W.ReviewedRankings()[1].points, 2, "the folded base survives a reload too")
		local open = 0
		for _, n in pairs(c.rdb.wanted.ledger.base.targets) do open = open + n end
		eq(open, 0, "the claim closed the folded bounties")
	end)
end)

test("wanted controls: Send evidence, Review (accept, reject, withdraw), Publish, Revoke and Void are buttons and dialogs over the real paths", function()
	WithWanted(function(w, W, c)
		local observer = w.participant("ControlsSlayer-Realm", "Player-1-CF000003")
		local slayer = observer
		c.me, w.units.player.name, w.units.player.guid = observer, observer, "Player-1-CF000003"
		local reviewer = w.authority("Reviewer-Realm", "council")
		local target, targetGuid = "Controls-Realm", "Player-1-CF000001"
		assert(w.add(target, targetGuid))
		w.manager = false
		eq(Shown(W), "", "nothing to send yet; not a reviewer, not a moderator")
		assert(W.CaptureSelfDeathRecap({ fatal = true, id = "death-951", killerName = target,
			killerGUID = targetGuid, victimName = observer, victimGUID = w.units.player.guid }))
		w.advance()
		assert(w.kill(952, observer, w.units.player.guid, target, targetGuid))
		eq(Shown(W), "WANTED_SEND_BTN")

		Press(W, "WANTED_SEND_BTN")
		local d = w.dialogs[#w.dialogs]
		eq(d.which, "OLYMPUS_WANTED_SEND"); eq(d.data, nil, "the list sends every target's rows")
		local dialog = StaticPopupDialogs.OLYMPUS_WANTED_SEND
		local box = Box("old text")
		local self = { editBox = box }
		dialog.OnShow(self)
		eq(box.text, "", "no reviewer used yet")
		box.text = "Reviewer"
		local whispers = #w.sent
		dialog.OnAccept(self, d.data)
		eq(#w.sent - whispers, 2)
		for i = whispers + 1, #w.sent do eq(w.sent[i].dist, "WHISPER"); eq(w.sent[i].to, "Reviewer"); assert(w.sent[i].text:find("^WX~1~")) end
		eq(w.prints[#w.prints], ns.L.WANTED_SENT:format(2, "Reviewer"))
		dialog.OnAccept(self, d.data)
		eq(#w.sent - whispers, 2, "nothing new to send to that reviewer")
		eq(w.prints[#w.prints], ns.L.WANTED_ACTION_FAILED:format("sent"))
		dialog.OnShow(self)
		eq(box.text, "Reviewer", "the next Send offers the last reviewer")
		box.text = "Nobody"
		dialog.OnAccept(self, d.data)
		eq(w.prints[#w.prints], ns.L.WANTED_ACTION_FAILED:format("reviewer"), "only a reviewer can be sent evidence")
		local wires = { w.sent[whispers + 1].text, w.sent[whispers + 2].text }

		c.me = reviewer
		for _, wire in ipairs(wires) do w.commHandlers.WX("WHISPER", observer, wire) end
		w.participant("Doubtful-Realm", "Player-1-CF000009")
		w.commHandlers.WX("WHISPER", "Doubtful-Realm", ("WX~1~00000000000000e1~%d~24000~P~C~1.cf000009~1.cf000001"):format(w.epoch))
		eq(Shown(W), "WANTED_REVIEW_BTN,WANTED_SEND_BTN", "this test's reviewer also holds the observer's rows")
		for _, def in ipairs(W.buttons) do
			if def[1] == "WANTED_REVIEW_BTN" then eq(def.label(), ns.L.WANTED_REVIEW_BTN_COUNT:format(3)) end
		end
		Press(W, "WANTED_REVIEW_BTN")
		eq(W.PageId(), "review")
		eq(Shown(W), "WANTED_BACK_BTN,WANTED_PUBLISH_BTN,WANTED_REVOKE_BTN")
		local lines, title = W.Build()
		eq(title, ns.L.WANTED_REVIEW_TITLE)
		local pending = {}
		for _, line in ipairs(lines) do if line.id and line.id:find("^wanted%-review:") then pending[#pending + 1] = line end end
		eq(#pending, 3)
		assert(pending[3].text:find("! ", 1, true), "the doubtful claim names another killer for the same death")
		local tip = Tooltip(); pending[3].tooltip(tip)
		assert(table.concat(tip.lines, "\n"):find(ns.L.WANTED_CONFLICT, 1, true))
		local review = StaticPopupDialogs.OLYMPUS_WANTED_REVIEW
		eq(review.button3, ns.L.WANTED_REJECT_BTN)
		pending[3].onClick()
		d = w.dialogs[#w.dialogs]
		eq(d.which, "OLYMPUS_WANTED_REVIEW")
		review.OnAlt({}, d.data)
		eq(#W.ReviewInbox(), 2, "rejected: gone")
		for i = 1, 2 do
			pending[i].onClick()
			review.OnAccept({}, w.dialogs[#w.dialogs].data)
		end
		eq(#W.Ledger(), 2)
		eq(W.ReviewedRankings()[1].guid, "Player-1-CF000003")

		lines = W.Build()
		local ledgerRow
		for _, line in ipairs(lines) do if line.id and line.id:find("^wanted%-ledger:") and line.text:find(ns.L.WANTED_CLAIM_LINE:sub(1, 5), 1, true) then ledgerRow = line end end
		assert(ledgerRow, "the accepted claim is listed")
		ledgerRow.onClick()
		d = w.dialogs[#w.dialogs]
		eq(d.which, "OLYMPUS_WANTED_WITHDRAW")
		StaticPopupDialogs.OLYMPUS_WANTED_WITHDRAW.OnAccept({}, d.data)
		eq(#W.Ledger(), 1); eq(#W.ReviewedRankings(), 0, "withdrawn: the claim no longer pays")
		local claimWire
		for _, wire in ipairs(wires) do if wire:find("~C~", 1, true) then claimWire = wire end end
		w.commHandlers.WX("WHISPER", observer, claimWire)
		local again = W.ReviewInbox()
		assert(W.Review(again[#again].key, true), "the same row can be taken again after a withdrawal")

		Press(W, "WANTED_PUBLISH_BTN")
		d = w.dialogs[#w.dialogs]
		eq(d.which, "OLYMPUS_WANTED_PUBLISH")
		assert(d.a:find("ControlsSlayer", 1, true), "the dialog names what will be signed")
		StaticPopupDialogs.OLYMPUS_WANTED_PUBLISH.OnAccept({})
		local published = w.sent[#w.sent]
		eq(published.dist, "CHANNEL"); assert(published.text:find("^WY~1~"))
		assert(published.text:find("1.cf000003:1:1:", 1, true))
		eq(w.prints[#w.prints], ns.L.WANTED_PUBLISHED)
		-- His own client holds the word he published, without hearing it back (the channel never
		-- echoes a client's own message), and shows its signed top three.
		eq(W.GlobalBorder(nil, "Player-1-CF000003"), "wanted-slayer-1")
		eq(W.GlobalSnapshot().issuer, reviewer)
		eq(select(2, W.HandleGlobalSnapshot("CHANNEL", reviewer, published.text)), "replay", "the word it holds already")
		Press(W, "WANTED_BACK_BTN")
		assert(table.concat(Headers(W.Build()), "\n"):find(ns.L.WANTED_SIGNED, 1, true), "the signed section on his own list")
		Press(W, "WANTED_REVIEW_BTN")
		Press(W, "WANTED_REVOKE_BTN")
		eq(w.dialogs[#w.dialogs].which, "OLYMPUS_WANTED_REVOKE")
		StaticPopupDialogs.OLYMPUS_WANTED_REVOKE.OnAccept({})
		assert(w.sent[#w.sent].text:find("~%-~"), "an empty top three")
		eq(w.prints[#w.prints], ns.L.WANTED_REVOKED)
		eq(W.GlobalBorder(nil, "Player-1-CF000003"), nil, "his revocation drops the frame on his own client as he sends it")
		eq(#W.GlobalSnapshot().rows, 0)

		Press(W, "WANTED_BACK_BTN")
		eq(W.PageId(), "list")
		c.me = observer
		w.manager = true
		assert(W.OpenTarget(target))
		lines = W.Build()
		local claimRow
		for _, line in ipairs(lines) do if line.text == c.DisplayName(slayer) then claimRow = line end end
		assert(claimRow and claimRow.onClick, "a moderator can void a live row (the closed cycle's claim)")
		claimRow.onClick()
		d = w.dialogs[#w.dialogs]
		eq(d.which, "OLYMPUS_WANTED_CORRECT")
		StaticPopupDialogs.OLYMPUS_WANTED_CORRECT.OnAccept({ editBox = Box("wrong target") }, d.data)
		eq(W.Stats().corrected, 1)
		w.manager = false
		lines = W.Build()
		eq(#W.Target(target).claims, 0, "the voided claim no longer closes the cycle")
		eq(W.Target(target).current, 1, "its bounty is open again")
		eq(#W.Rankings().all, 0)
		local victimLine
		for _, line in ipairs(lines) do if line.text == c.DisplayName(observer) then victimLine = line end end
		assert(victimLine and not victimLine.onClick, "the reopened cycle's victim: read only for a member")
		for _, line in ipairs(lines) do assert(not (line.text == c.DisplayName(observer) and line.onClick), "a member only reads") end
	end)
end)

-- Add target's box took the keyboard itself (eb:SetFocus) where Send and Correct went through
-- ns.Focus: with the gamepad UI, a focus taken from the chat's box runs the game's gamepad code
-- from ours (Dialog.lua). The style and the focused box as Forever's client reports them.
test("wanted dialogs: with the gamepad UI, no Most Wanted box takes the keyboard from the chat's, Add target's neither", function()
	WithWanted(function()
		local saved = { style = C_InputInterfaceStyle, kind = Enum.InputDeviceInterfaceType, focus = GetCurrentKeyBoardFocus }
		local chat, focus, pad = { name = "ChatFrame1EditBox" }, nil, true
		Enum.InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 }
		C_InputInterfaceStyle = { GetCurrentStyle = function() return pad and 1 or 0 end }
		GetCurrentKeyBoardFocus = function() return focus end
		local ok, err = pcall(function()
			local boxes = {}
			for _, which in ipairs(DIALOGS) do
				local dialog = StaticPopupDialogs[which]
				if dialog.hasEditBox then
					boxes[#boxes + 1] = which
					local box = Box("old")
					pad, focus = true, chat
					dialog.OnShow({ editBox = box })
					eq(box.focused, nil, which .. ": the chat's box keeps the keyboard")
					focus = nil
					dialog.OnShow({ editBox = box })
					eq(box.focused, true, which .. ": no other box typing, ours takes it")
					box.focused, pad, focus = nil, false, chat
					dialog.OnShow({ editBox = box })
					eq(box.focused, true, which .. ": mouse and keyboard, as always")
				end
			end
			eq(table.concat(boxes, ","), "OLYMPUS_WANTED_ADD,OLYMPUS_WANTED_SEND,OLYMPUS_WANTED_CORRECT")
		end)
		C_InputInterfaceStyle, Enum.InputDeviceInterfaceType, GetCurrentKeyBoardFocus = saved.style, saved.kind, saved.focus
		if not ok then error(err, 0) end
	end)
end)

test("wanted labels: this client's boards say so, only a verified signed word shows the signed top three, and both languages have the words", function()
	WithWanted(function(w, W, c)
		local target, targetGuid = "Label-Realm", "Player-1-DA000041"
		assert(w.add(target, targetGuid))
		assert(w.kill(961, target, targetGuid, w.olympian("LabelVictim-Realm"), "Player-1-DA000042"))
		w.advance()
		local slayer = w.olympian("LabelSlayer-Realm")
		assert(w.kill(962, slayer, "Player-1-DA000043", target, targetGuid))
		local lines, _, detail = W.Build()
		local headers = table.concat(Headers(lines), "\n")
		assert(headers:find(ns.L.WANTED_LOCAL_ALL, 1, true))
		assert(ns.L.WANTED_LOCAL_ALL:find("this client", 1, true) and ns.L.WANTED_MONTHLY:find("this client", 1, true))
		assert(not headers:find("Global", 1, true), "no local board calls itself global")
		assert(not headers:find(ns.L.WANTED_SIGNED, 1, true), "no signed section without a verified word")
		assert(detail:find(ns.L.WANTED_AUTHORITY_OFF, 1, true))
		eq(rawget(ns.L, "WANTED_GLOBAL"), nil, "the old header's key is gone")

		local council = w.authority("Council-Realm", "council")
		local me = c.me
		c.me = council
		local _, _, word = w.publish({ { guid = "Player-1-DA000043", points = 1, claims = 1, reachedAt = w.epoch } }, 700)
		c.me = me
		assert(W.HandleGlobalSnapshot("CHANNEL", council, word))
		lines, _, detail = W.Build()
		headers = table.concat(Headers(lines), "\n")
		assert(headers:find(ns.L.WANTED_SIGNED, 1, true))
		local signedRow
		for _, line in ipairs(lines) do if line.key == "g:Player-1-DA000043" and line.text:find("LabelSlayer", 1, true) and not line.player then signedRow = line end end
		assert(signedRow, "the signed row is named from what this client knows of the GUID")
		assert(detail:find(ns.L.WANTED_SIGNED_HELD:format(c.DisplayName(council), 31), 1, true), detail)

		local pt, savedLocale = {}, GetLocale
		GetLocale = function() return "ptBR" end
		local okPt, errPt = pcall(function() assert(loadfile(ROOT .. "Olympus/Locales.lua"))("Olympus", pt) end)
		GetLocale = savedLocale
		assert(okPt, errPt)
		eq(rawget(pt.L, "WANTED_GLOBAL"), nil)
		local src = assert(io.open(ROOT .. "Olympus/Locales.lua")):read("*a")
		local ptBlock = assert(src:match('%-%- 1%.2: Horde Most Wanted.-GetLocale%(%) == "ptBR" then(.-)\nend'), "the Most Wanted pt-BR block")
		for _, key in ipairs({ "WANTED_LOCAL_ALL", "WANTED_MONTHLY", "WANTED_AUTHORITY_OFF", "WANTED_SIGNED", "WANTED_SIGNED_EMPTY",
			"WANTED_SIGNED_HELD", "WANTED_SEND_BTN", "WANTED_SEND_PROMPT", "WANTED_SENT", "WANTED_REVIEW_BTN", "WANTED_REVIEW_BTN_COUNT",
			"WANTED_PUBLISH_BTN", "WANTED_REVOKE_BTN", "WANTED_REVIEW_TITLE", "WANTED_REVIEW_ABOUT", "WANTED_PENDING", "WANTED_ACCEPTED",
			"WANTED_TO_PUBLISH", "WANTED_CONFLICT", "WANTED_REVIEW_PROMPT", "WANTED_ACCEPT_BTN", "WANTED_REJECT_BTN", "WANTED_LATER_BTN",
			"WANTED_WITHDRAW_PROMPT", "WANTED_PUBLISH_PROMPT", "WANTED_REVOKE_PROMPT", "WANTED_CORRECT_PROMPT", "WANTED_BOUNTY_LINE",
			"WANTED_CLAIM_LINE", "WANTED_LAST_PUBLISHED", "WANTED_NOT_PUBLISHED", "WANTED_OLDER_ACCEPTED", "WANTED_SEND_WAIT" }) do
			assert(type(ns.L[key]) == "string" and ns.L[key] ~= "", key)
			assert(ptBlock:find("L." .. key .. " = ", 1, true), key .. " in pt-BR")
			assert(type(pt.L[key]) == "string" and pt.L[key] ~= "", "pt-BR " .. key)
		end
		eq(pt.L.WANTED_LOCAL_ALL, "Slayers vistos por este cliente · histórico total")
	end)
end)

test("wanted send: one batch per reviewer window, so his side drops none; rows too old for him stay home; a whisper that never reached him can go again", function()
	WithWanted(function(w, W, c)
		local observer, reviewer = c.me, w.authority("Reviewer-Realm", "council")
		local target, targetGuid = "Batch-Realm", "Player-1-AF000001"
		assert(w.add(target, targetGuid))
		w.manager = false
		local function Kill(n)
			w.advance(6)
			assert(W.CaptureSelfDeathRecap({ fatal = true, id = "death-" .. (1000 + n), killerName = target,
				killerGUID = targetGuid, victimName = observer, victimGUID = w.units.player.guid }))
		end
		Kill(0) -- by the time it could go, the reviewer would refuse it as too old
		w.advance(W.EVIDENCE_AGE)
		local freshFrom = w.epoch
		for n = 1, 16 do Kill(n) end
		-- The reviewer's client hears the whispers sent since `from`, as the server delivers them.
		local function Deliver(from)
			c.me = reviewer
			w.participant(observer, w.units.player.guid)
			for i = from, #w.sent do if w.sent[i].dist == "WHISPER" then w.commHandlers.WX("WHISPER", observer, w.sent[i].text) end end
			c.me = observer
		end
		local from = #w.sent + 1
		eq(W.SendEvidence(reviewer), 8); Deliver(from)
		-- A second click inside his window: nothing goes (his side would drop it, yet it would count
		-- as sent here), and the player is told when the next batch can go.
		w.advance(1); from = #w.sent + 1
		StaticPopupDialogs.OLYMPUS_WANTED_SEND.OnAccept({ editBox = Box("Reviewer") })
		eq(#w.sent, from - 1, "nothing whispered")
		eq(w.prints[#w.prints], ns.L.WANTED_SEND_WAIT:format(W.SEND_WAIT - 1))
		Deliver(from)
		w.advance(W.SEND_WAIT - 1); from = #w.sent + 1
		eq(W.SendEvidence(reviewer), 8); Deliver(from)
		w.advance(W.SEND_WAIT)
		eq(select(2, W.SendEvidence(reviewer)), "sent", "the row too old for him is never sent")
		local inbox = W.ReviewInbox()
		eq(#inbox, 16, "all sixteen reached the reviewer")
		for _, e in ipairs(inbox) do assert(e.at > freshFrom, "none too old") end

		-- The server's line that he is offline: that batch never reached him, so it can go again,
		-- at once (his window counted none of it).
		Kill(17); Kill(18)
		ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
		w.advance(W.SEND_WAIT)
		eq(W.SendEvidence(reviewer), 2)
		assert(type(w.handlers.CHAT_MSG_SYSTEM) == "function", "the server's lines are read once evidence went")
		w.handlers.CHAT_MSG_SYSTEM("No player named 'Someone' is currently playing.")
		eq(select(2, W.SendEvidence(reviewer)), "sent", "another player's line changes nothing")
		w.handlers.CHAT_MSG_SYSTEM(ERR_CHAT_PLAYER_NOT_FOUND_S:format("Reviewer"))
		from = #w.sent + 1
		eq(W.SendEvidence(reviewer), 2, "not delivered: sendable again, without the wait")
		Deliver(from)
		eq(#W.ReviewInbox(), 18)

		-- A whisper the game did not send (Comm's done says so): that row can go again.
		Kill(19)
		local whisper = c.Comm.Whisper
		c.Comm.Whisper = function(to, text, _, _, _, done)
			local ok = whisper(to, text)
			if done then done(false, "lockdown") end
			return ok
		end
		w.advance(W.SEND_WAIT)
		eq(W.SendEvidence(reviewer), 1)
		c.Comm.Whisper = whisper
		w.advance(W.SEND_WAIT); from = #w.sent + 1
		eq(W.SendEvidence(reviewer), 1, "the row whose whisper failed"); Deliver(from)
		eq(#W.ReviewInbox(), 19)

		-- When the last batch went is saved: a reload does not cut the wait short.
		Kill(20)
		w.advance(W.SEND_WAIT)
		eq(W.SendEvidence(reviewer), 1)
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted
		assert(W.Load())
		Kill(21)
		eq(select(2, W.SendEvidence(reviewer)), "wait", "after the reload too")
		w.advance(W.SEND_WAIT)
		local sent = W.SendEvidence(reviewer)
		assert(sent and sent >= 1, "then the rows go, the newest first")
		assert(w.sent[#w.sent - sent + 1].text:find(("~%d~"):format(w.epoch - W.SEND_WAIT), 1, true), "the newest row went first")
	end)
end)

test("wanted review: rows a reviewer holds already cost the sender's rate nothing, and accepted rows leave the inbox and its bounds", function()
	WithWanted(function(w, W, c)
		c.me = w.authority("Reviewer-Realm", "council")
		local H = w.commHandlers.WX
		w.participant("Steady-Realm", "Player-1-CD000201")
		local function Wire(i)
			return ("WX~1~%016x~%d~24000~S~B~1.ab0002%02d~1.cd000201"):format(i, w.epoch - 200 + i * 6, i)
		end
		local function Pending()
			local n = 0
			for _, e in ipairs(W.ReviewInbox()) do if e.state == "pending" then n = n + 1 end end
			return n
		end
		for i = 1, 7 do H("WHISPER", "Steady-Realm", Wire(i)) end
		-- His client sends the same rows again (he reloaded), then a new one, inside one window.
		for i = 1, 7 do H("WHISPER", "Steady-Realm", Wire(i)) end
		H("WHISPER", "Steady-Realm", Wire(8))
		eq(Pending(), 8, "the copies of rows held cost nothing: the new row still fits his rate")
		eq(#W.ReviewInbox(), 8)

		W.REVIEW_PER_SENDER, W.REVIEW_MAX = 8, 2
		for _, e in ipairs(W.ReviewInbox()) do assert(W.Review(e.key, true)) end
		eq(#W.Ledger(), 8)
		eq(#W.ReviewInbox(), 0, "accepted rows are in the ledger, not the session inbox")
		w.advance(W.REVIEW_RATE_WINDOW)
		H("WHISPER", "Steady-Realm", Wire(9))
		eq(Pending(), 1, "the rows he took do not fill the sender's share, nor the inbox")
		H("WHISPER", "Steady-Realm", Wire(3))
		eq(Pending(), 1, "an accepted row sent again is not taken again")
		eq(#W.Ledger(), 8)
	end)
end)

test("wanted ledger: past its bound, a row about a death the base already holds is refused, sent again or arriving late; no bounty pays twice or in another cycle", function()
	WithWanted(function(w, W, c)
		c.me = w.authority("Reviewer-Realm", "council")
		W.LEDGER_MAX = 2
		local H = w.commHandlers.WX
		local function Wire(digest, at, action, killer, victim)
			return ("WX~1~%s~%d~24000~%s~%s~%s~%s"):format(digest, at, action == "B" and "S" or "P", action, killer, victim)
		end
		local T, S, S2, V = "1.ab000301", "1.ef000301", "1.ef000302", "1.cd000301"
		local victims = {}
		for i = 1, 6 do victims[i] = w.participant("FolderVictim" .. i .. "-Realm", "Player-1-CD00030" .. i) end
		local slayer1 = w.participant("FolderSlayer1-Realm", "Player-1-EF000301")
		local slayer2 = w.participant("FolderSlayer2-Realm", "Player-1-EF000302")
		local senders = { victims[1], victims[1], slayer1, victims[2], victims[3], slayer2 }
		-- The target kills V twice, a minute apart; S claims him; he kills twice more; S2 claims him.
		local rows = {
			Wire("00000000000003a1", w.epoch - 300, "B", T, V),
			Wire("00000000000003a2", w.epoch - 240, "B", T, V),
			Wire("00000000000003a3", w.epoch - 180, "C", S, T),
			Wire("00000000000003a4", w.epoch - 120, "B", T, "1.cd000302"),
			Wire("00000000000003a5", w.epoch - 60, "B", T, "1.cd000303"),
			Wire("00000000000003a6", w.epoch - 30, "C", S2, T),
		}
		for i, wire in ipairs(rows) do H("WHISPER", senders[i], wire) end
		-- An account of a death in the first cycle, still waiting when the ledger folds past it.
		H("WHISPER", victims[4], Wire("00000000000003c1", w.epoch - 200, "B", T, "1.cd000304"))
		local slow
		for _, e in ipairs(W.ReviewInbox()) do
			if e.digest == "00000000000003c1" then slow = e.key else assert(W.Review(e.key, true)) end
		end
		local _, folded = W.Ledger()
		eq(folded, 4, "the four oldest folded")
		local function Points()
			local out = {}
			for _, r in ipairs(W.ReviewedRankings()) do out[#out + 1] = r.guid .. "=" .. r.points end
			table.sort(out)
			return table.concat(out, ",")
		end
		eq(Points(), "Player-1-EF000301=2,Player-1-EF000302=2")
		local ok, why = W.Review(slow, true)
		eq(ok, false); eq(why, "late", "it can no longer take its place among the deaths")
		-- The first death, sent again (the sender reloaded), and another observer's late account.
		H("WHISPER", victims[1], rows[1])
		H("WHISPER", victims[5], Wire("00000000000003b1", w.epoch - 270, "B", T, "1.cd000305"))
		local waiting = 0
		for _, e in ipairs(W.ReviewInbox()) do if e.key ~= slow then waiting = waiting + 1 W.Review(e.key, true) end end
		eq(waiting, 0, "neither is taken")
		eq(Points(), "Player-1-EF000301=2,Player-1-EF000302=2", "one death never pays twice, nor in another cycle")
		-- Rows after the base still come in as before.
		H("WHISPER", victims[6], Wire("00000000000003a7", w.epoch - 10, "B", T, "1.cd000306"))
		eq(#W.ReviewInbox(), 2)
	end)
end)

---------------------------------------------------------------------------
-- A small world: several clients in one Lua state, each with its own namespace, saved data
-- (db, rdb), units and Wanted.lua; real Ed25519 keys and signatures, each check queued as the
-- game's job queue runs it later; a Comm that routes as the game does (a whisper to the client
-- it names, the channel to every other online client, each stamped with its sender's name); and
-- timers on the world's clock. A reload or a login is a fresh namespace over the same saved data
-- (the old one's timers never fire again); an offline client hears nothing.
---------------------------------------------------------------------------

local function WithWorld(fn)
	local globals = { "UnitGUID", "UnitIsPlayer", "UnitFactionGroup", "GetGuildInfo", "GetRealZoneText",
		"UnitIsDeadOrGhost", "C_DateAndTime", "C_DeathInfo", "C_DeathRecap", "GetFileIDFromPath",
		"C_ChatInfo", "GetTime", "GetChannelName", "GetPlayerInfoByGUID", "UnitTokenFromGUID" }
	local saved = {}
	for _, name in ipairs(globals) do saved[name] = _G[name] end
	local dialogs = {}
	for _, which in ipairs(DIALOGS) do dialogs[which] = StaticPopupDialogs[which] end
	local realEd = ns.Ed25519
	local world = { epoch = 1800000000, year = 2026, month = 10, clients = {}, queue = {}, jobs = {}, timers = {},
		authorities = {}, olympians = {}, log = {}, serial = 0 }
	local current
	local ok, err = pcall(function()
		local function U(unit) return current and current.units[unit] end
		UnitGUID = function(unit) return U(unit) and U(unit).guid end
		UnitIsPlayer = function(unit) return U(unit) ~= nil end
		UnitFactionGroup = function(unit) return U(unit) and U(unit).faction end
		UnitIsDeadOrGhost = function() return current and current.dead == true end
		GetGuildInfo = function(unit) return U(unit or "player") and U(unit or "player").guild end
		GetRealZoneText = function() return "Arathi Highlands" end
		C_DateAndTime = { GetCurrentCalendarTime = function() return { year = world.year, month = world.month } end }
		C_DeathInfo, C_DeathRecap = nil, nil
		UnitTokenFromGUID = nil
		GetPlayerInfoByGUID = function(guid)
			for _, cl in ipairs(world.clients) do
				if cl.guid == guid then return "Warrior", "WARRIOR", "Human", "Human", 2, ns.ShortName(cl.name), "Realm" end
			end
		end
		GetFileIDFromPath = function() return nil end
		GetTime = function() return world.epoch end
		GetChannelName = function() return 7, "OlympusNet" end
		C_ChatInfo = { RegisterAddonMessagePrefix = function() end,
			SendAddonMessage = function(_, text, dist, target)
				world.queue[#world.queue + 1] = { from = current, text = text, dist = dist, to = target, raw = true }
				return true
			end }
		local function Fold(name) return ns.Fold(ns.FullName(name)) end

		function world:As(cl, f, ...)
			local was = current
			current = cl
			local res = { pcall(f, ...) }
			current = was
			if not res[1] then error(res[2], 0) end
			return unpack(res, 2)
		end
		function world:Load(cl)
			-- (No name before LOGIN, not even the test namespace's.)
			local c = setmetatable({ L = ns.L, db = cl.db, rdb = cl.rdb, realm = "Realm", group = "RealmGroup",
				faction = "Alliance" }, { __index = function(_, key) if key ~= "me" then return ns[key] end end })
			c.Now = function() return world.epoch end
			c.Data = { ServerTime = function() return world.epoch end }
			c.IsMember = function() return cl.member end
			c.Moderation = { CanIssue = function() return cl.manager == true end, Blocks = function() return false end }
			local function Role(name) return (cl.authorities or world.authorities)[Fold(name)] end
			c.Workshop = { IsAuthor = function() return false end, IsAuthorName = function(name) return Role(name) == "author" end }
			c.IsKingCharacter = function(name) return Role(name) == "king" end
			c.IsHighCouncillor = function(name) return Role(name) == "council" end
			c.Ed25519 = { ToB64 = realEd.ToB64, FromB64 = realEd.FromB64, ValidPublicKey = realEd.ValidPublicKey,
				Verify = realEd.Verify, Busy = function() return 0 end,
				Run = function(job, done) world.jobs[#world.jobs + 1] = { cl = cl, owner = c, job = job, done = done } return true end }
			c.Debts = { MyKey = function() return "gk", cl.pk, "fp" end, Sign = function(msg) return realEd.Sign(cl.seed, msg, cl.pk) end,
				B64 = realEd.ToB64, UnB64 = realEd.FromB64,
				InfoName = function(guid) for _, o in ipairs(world.clients) do if o.guid == guid then return o.name end end return nil end }
			c.Comm = { Handle = function(kind, call) cl.handlers[kind] = call end,
				Whisper = function(to, text) world.queue[#world.queue + 1] = { from = cl, to = to, dist = "WHISPER", text = text } return true end,
				Send = function(dist, text, _, _, _, done, options)
					world.queue[#world.queue + 1] = { from = cl, dist = dist, text = text, done = done, options = options } return true
				end,
				SendChunked = function(text, _, _, done, options)
					world.queue[#world.queue + 1] = { from = cl, dist = "CHANNEL", text = text, done = done, options = options } return true
				end }
			c.UnitFullName = function(unit) return U(unit) and U(unit).name end
			c.Roster = { Fresh = function() return true end,
				RankOf = function(name) return world.olympians[Fold(name)] and 3 or nil end }
			c.RegisterEvent = function(name, call) cl.events[name] = call end
			c.Fire = function() end
			c.On = function(name, call) cl.listeners[name] = call end
			c.Print = function(message) cl.prints[#cl.prints + 1] = tostring(message) end
			c.Ago = function(at) return tostring(world.epoch - (tonumber(at) or 0)) .. "s" end
			c.ShowDialog = function() return true end
			c.After = function(seconds, _, f) world.timers[#world.timers + 1] = { at = world.epoch + seconds, cl = cl, owner = c, fn = f } end
			c.Every, c.Log = function() end, function() end
			c.SafeCall = function(_, fn, ...) return fn(...) end
			c.UI = { Refresh = function() end, RefreshSoon = function() end }
			cl.handlers, cl.listeners, cl.events, cl.ns, cl.online = {}, {}, {}, c, true
			local commLogin
			if cl.realComm then
				c.db.blocked = {}
				world:As(cl, function() assert(loadfile(ROOT .. "Olympus/Comm.lua"))("Olympus", c) end)
				commLogin = cl.listeners.LOGIN
			end
			world:As(cl, function() assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c) end)
			cl.W = c.Wanted
			-- As the game loads an addon: INIT (ADDON_LOADED) before the client knows the character's
			-- name, LOGIN (PLAYER_LOGIN) once it does (Core.lua sets ns.me there).
			if cl.listeners.INIT then world:As(cl, cl.listeners.INIT) end
			c.me = cl.name
			if commLogin then
				-- Only Wanted's recovery timers are part of this focused wire scene.
				local after = c.After
				c.After = function() end
				world:As(cl, commLogin)
				c.After = after
				world:As(cl, c.Comm.JoinChannel)
			end
			if cl.listeners.LOGIN then world:As(cl, cl.listeners.LOGIN) end
			return cl
		end
		function world:Client(name, guid, role, realComm)
			name = ns.FullName(name)
			local seed = ns.Sign.SHA256("test seed " .. name)
			local cl = { name = name, guid = guid, member = true, db = {}, rdb = {}, prints = {}, seed = seed, realComm = realComm,
				pk = realEd.PublicKey(seed), units = { player = { name = name, guid = guid, faction = "Alliance", guild = "Olympus II" } } }
			world.olympians[Fold(name)] = true
			if role then world.authorities[Fold(name)] = role end
			world.clients[#world.clients + 1] = cl
			return world:Load(cl)
		end
		function world:Find(to)
			local key = Fold(to)
			for _, o in ipairs(world.clients) do if ns.Fold(o.name) == key then return o end end
			return nil
		end
		function world:Deliver()
			local guard = 0
			while #world.queue > 0 or #world.jobs > 0 do
				guard = guard + 1
				assert(guard < 5000, "the world settles")
				local m = table.remove(world.queue, 1)
				if m then
					local permitted = not m.options or not m.options.guard or world:As(m.from, m.options.guard)
					if permitted then
					world.log[#world.log + 1] = m
					if m.done then world:As(m.from, m.done, true) end
					if m.dist == "WHISPER" then
						local to = world:Find(m.to)
						if to and to.online then
							if m.raw and to.realComm then
								world:As(to, to.events.CHAT_MSG_ADDON, to.ns.PREFIX, m.text, "WHISPER", m.from.name, m.to)
							else world:As(to, to.handlers.WX, "WHISPER", m.from.name, m.text) end
						end
						else
							for _, o in ipairs(world.clients) do
								local handler = o.handlers[m.text:sub(1, 2)]
								if o ~= m.from and o.online then
									if m.raw and o.realComm then
										world:As(o, o.events.CHAT_MSG_ADDON, o.ns.PREFIX, m.text, m.dist, m.from.name, m.to, nil, 7, o.ns.Comm.ChannelName())
									elseif handler then world:As(o, handler, "CHANNEL", m.from.name, m.text) end
								end
						end
					end
					elseif m.done then world:As(m.from, m.done, false, "guard") end
				else
					local j = table.remove(world.jobs, 1)
					if j.cl.online and j.cl.ns == j.owner then
						world:As(j.cl, function() local good, valid = pcall(j.job) j.done(good, valid) end)
					end
				end
			end
		end
		function world:Run(seconds)
			local stop = world.epoch + seconds
			world:Deliver()
			while true do
				table.sort(world.timers, function(a, b) return a.at < b.at end)
				local t = world.timers[1]
				if not t or t.at > stop then break end
				table.remove(world.timers, 1)
				world.epoch = math.max(world.epoch, t.at)
				if t.cl.online and t.cl.ns == t.owner then world:As(t.cl, t.fn) end
				world:Deliver()
			end
			world.epoch = stop
		end
		function world:Offline(cl) cl.online = false end
		function world:PumpComm()
			for _ = 1, 100 do
				local busy = false
				world.epoch = world.epoch + 1.2
				for _, cl in ipairs(world.clients) do
					if cl.online and cl.realComm and cl.ns.Comm.QueueSize() > 0 then
						busy = true; world:As(cl, cl.ns.Comm.Pump)
					end
				end
				world:Deliver()
				if not busy then return end
			end
			error("actual Comm queues settle")
		end
		function world:Border(cl, guid) return world:As(cl, cl.W.GlobalBorder, nil, guid) end
		-- The victim reports its own death; the slayer reports its own party kill. The observer's
		-- third-party observations remain local and never stand in for either participant.
		function world:Hunt(observer, reviewer, targetName, targetGuid, victim, slayer)
			world.serial = world.serial + 1
			local id = world.serial * 10
			local death, claim
			observer.manager = true
			world:As(observer, function()
				local W = observer.W
				W.AddTarget(targetName, targetGuid)
				assert(W.CaptureCombatLog(id, "PARTY_KILL", false, targetGuid, targetName, 0, 0, victim.guid, victim.name))
			end)
			victim.manager = true
			victim.dead = true
			world:As(victim, function()
				victim.W.AddTarget(targetName, targetGuid)
				local good
				good, death = victim.W.CaptureSelfDeathRecap({ fatal = true, id = "death-" .. id, killerName = targetName,
					killerGUID = targetGuid, victimName = victim.name, victimGUID = victim.guid })
				assert(good, death)
			end)
			victim.dead = false
			world.epoch = world.epoch + 6
			slayer.manager = true
			world:As(slayer, function()
				slayer.W.AddTarget(targetName, targetGuid)
				local good
				good, claim = slayer.W.CaptureCombatLog(id + 1, "PARTY_KILL", false, slayer.guid, slayer.name, 0, 0, targetGuid, targetName)
				assert(good, claim)
			end)
			world.epoch = world.epoch + 6
			assert(world:As(victim, victim.W.SubmitEvidence, reviewer.name, death.id))
			assert(world:As(slayer, slayer.W.SubmitEvidence, reviewer.name, claim.id))
			if victim.realComm or slayer.realComm then world:PumpComm() else world:Deliver() end
			for _, e in ipairs(world:As(reviewer, reviewer.W.ReviewInbox)) do
				if e.state == "pending" then assert(world:As(reviewer, reviewer.W.Review, e.key, true)) end
			end
		end
		fn(world)
	end)
	for _, name in ipairs(globals) do _G[name] = saved[name] end
	for _, which in ipairs(DIALOGS) do StaticPopupDialogs[which] = dialogs[which] end
	if not ok then error(err, 0) end
end

test("wanted own-proof recovery: refused unknown evidence remains local and can reach review unchanged after resolution and sender reload", function()
	WithWorld(function(world)
		local king = world:Client("Varrick-Realm", "Player-1-0A000001", "king")
		local victim = world:Client("Victim-Realm", "Player-1-0A000002")
		victim.manager, victim.dead = true, true
		local death
		world:As(victim, function()
			assert(victim.W.AddTarget("Hordeling-Realm", "Player-1-0B000001"))
			local good
			good, death = victim.W.CaptureSelfDeathRecap({ fatal = true, id = "unknown-own-death", killerName = "Hordeling-Realm",
				killerGUID = "Player-1-0B000001", victimName = victim.name, victimGUID = victim.guid })
			assert(good, death)
		end)
		local serverLookup = GetPlayerInfoByGUID
		king.ns.Debts.InfoName, GetPlayerInfoByGUID = nil, nil
		assert(world:As(victim, victim.W.SendEvidence, king.name)); world:Deliver()
		eq(#world:As(king, king.W.ReviewInbox), 0, "unknown own-side identity waits nowhere on the reviewer")
		eq(#victim.rdb.wanted.evidence, 1, "its original local record is retained")
		eq(select(2, world:As(victim, victim.W.SendEvidence, king.name)), "sent", "queue success is not a remote acceptance acknowledgement")
		GetPlayerInfoByGUID = serverLookup
		world.epoch = world.epoch + victim.W.SEND_WAIT
		world:Load(victim)
		assert(world:As(victim, victim.W.SendEvidence, king.name)); world:Deliver()
		local inbox = world:As(king, king.W.ReviewInbox)
		eq(#inbox, 1); eq(inbox[1].at, death.at); eq(inbox[1].victimGuid, victim.guid)
		eq(inbox[1].kind, "SELF_DEATH"); eq(inbox[1].state, "pending")
		assert(world:As(king, king.W.Review, inbox[1].key, true))
		eq(#world:As(king, king.W.Ledger), 1)
	end)
end)

local function WithChatSanctions(world, clients, fn)
	local dialogs = {}
	for key, value in pairs(StaticPopupDialogs) do dialogs[key] = value end
	local ok, err = pcall(function()
		for _, cl in ipairs(clients) do
			-- The Wanted world owns role facts; reuse the real existing name parser, not a
			-- permissive sanction stub or a fabricated PowersBarred result.
			cl.ns.Moderation.CharName = ns.Moderation.CharName
			world:As(cl, function() assert(loadfile(ROOT .. "Olympus/WatchChat.lua"))("Olympus", cl.ns) end)
		end
		fn()
	end)
	for key in pairs(StaticPopupDialogs) do if dialogs[key] == nil then StaticPopupDialogs[key] = nil end end
	for key, value in pairs(dialogs) do StaticPopupDialogs[key] = value end
	if not ok then error(err, 0) end
end

test("wanted sanction through real Comm: actual timeout and hold remove councillor publication, review, relay and queued delivery", function()
	for _, seconds in ipairs({ 300, 0 }) do
		WithWorld(function(world)
			local author = world:Client("Merrin-Realm", "Player-1-0A000001", "author", true)
			local council = world:Client("Council-Realm", "Player-1-0A000002", "council", true)
			local peer = world:Client("Late-Realm", "Player-1-0A000003", nil, true)
			WithChatSanctions(world, { author, council, peer }, function()
				eq(world:As(council, council.W.CanPublish, council.name), true)
				assert(world:As(council, council.W.PublishGlobal))
				local accepted, why = world:As(author, author.ns.WatchChat.Timeout, council.name, seconds, "real author sanction")
				eq(accepted, true, why)
				-- The sanction arrives before the council's admitted native publication starts.
				world.epoch = world.epoch + 2
				world:As(author, author.ns.Comm.Pump); world:Deliver()
				eq(world:As(council, council.ns.WatchChat.PowersBarred, council.name) ~= nil, true)
				eq(world:As(council, council.W.CanPublish, council.name), false)
				eq(world:As(council, council.W.PublishGlobal), false)
					local reviewed, reason = world:As(council, council.W.Review, "invented", true)
					eq(reviewed, false); eq(reason, "access", "sanction denies the authority check, not just an unknown row")
				eq(world:As(council, council.W.AnswerGlobal, "CHANNEL", peer.name, "W4~1"), false)
				world:PumpComm()
				local native = 0
				for _, msg in ipairs(world.log) do if msg.from == council and msg.raw then native = native + 1 end end
				eq(native, 0, "real guarded queue cancels every sanctioned publisher chunk")
			end)
		end)
	end
end)

for _, repeatWord in ipairs({ false, true }) do
	test("wanted publication lease through real Comm: queued " .. (repeatWord and "repeat" or "initial") .. " word rechecks replacement, issuer, scope and signed expiry", function()
		for _, change in ipairs({ "replace", "issuer", "scope", "expiry" }) do
			WithWorld(function(world)
				local council = world:Client("Council-Realm", "Player-1-0A000001", "council", true)
				world:Client("OtherCouncil-Realm", "Player-1-0A000002", "council", true)
				assert(world:As(council, council.W.PublishGlobal))
				if repeatWord then world:PumpComm(); world.log = {}; assert(world:As(council, council.W.RepeatGlobal)) end
				local original = council.db.wantedPublisher.last.body
				if change == "replace" then assert(world:As(council, council.W.PublishGlobal))
				elseif change == "issuer" then council.ns.me = "OtherCouncil-Realm"
				elseif change == "scope" then council.ns.group = "OtherRealmGroup"
				else
					-- A server-clock change expires the signed word without expiring the separate
					-- monotonic Comm queue. Otherwise its generic queue TTL would mask the bug.
					council.ns.Data.ServerTime = function() return world.epoch + council.W.GLOBAL_LIFE + 1 end
				end
				world:PumpComm()
				local asm, originalParts, completed = ns.Codec.NewAssembler(), 0, {}
				for _, msg in ipairs(world.log) do
					if msg.from == council and msg.raw then
						local whole = ns.Codec.Feed(asm, council.name, msg.text, world.epoch)
						if whole then completed[#completed + 1] = whole end
						originalParts = originalParts + 1
					end
				end
				for _, whole in ipairs(completed) do eq(whole == original, false, change .. "/" .. tostring(repeatWord)) end
				if change == "replace" then eq(#completed, 1, "only the replacement reaches the real native wire")
				else eq(originalParts, 0, change .. "/" .. tostring(repeatWord) .. " cancels every chunk") end
			end)
		end
	end)
end

test("wanted relay: a late independently anchored peer recovers an unchanged word with its publisher offline", function()
	WithWorld(function(world)
		local king = world:Client("Varrick-Realm", "Player-1-0A000001", "king")
		local council = world:Client("Council-Realm", "Player-1-0A000002", "council")
		local late = world:Client("Late-Realm", "Player-1-0A000003")
		assert(world:As(king, king.W.PublishGlobal)); world:Deliver()
		local old = world:As(late, late.W.GlobalSnapshot)
		world:Offline(late)
		world.epoch = world.epoch + 10
		assert(world:As(king, king.W.PublishGlobal)); world:Deliver()
		local held = council.rdb.wanted.global.text
		world:Offline(king)
		world:Load(late); world:Deliver()
		eq(world:As(late, late.W.GlobalSnapshot).seq, old.seq)
		world:Run(45)
		eq(late.rdb.wanted.global.text, held, "original signature, issuer, timestamps and sequence are unchanged")
		eq(late.rdb.wanted.global.relay, council.name)
		eq(world:As(late, late.W.GlobalSnapshot).seq, old.seq + 1)
		local accepted, why = world:As(late, late.W.HandleGlobalRelay, "CHANNEL", council.name, "W5~1~" .. held)
		eq(accepted, false); eq(why, "replay")
		local fresh = world:Client("Fresh-Realm", "Player-1-0A000004")
		accepted, why = world:As(fresh, fresh.W.HandleGlobalRelay, "CHANNEL", council.name, "W5~1~" .. held)
		eq(accepted, false); eq(why, "unanchored", "a relay cannot introduce the original key")
		eq(fresh.rdb.wanted and fresh.rdb.wanted.globalDirectPins, nil)
		world:Load(late); world:Deliver()
		eq(late.rdb.wanted.global.text, held, "persisted relayed word verifies again after reload")
		eq(late.rdb.wanted.global.relay, council.name)
		late.rdb.wanted.globalDirectPins = nil
		world:Load(late); world:Deliver()
		eq(world:As(late, late.W.GlobalSnapshot), nil, "a relayed saved word cannot reconstruct a missing independent pin")
	end)
end)

test("wanted relay: authority, expiry, pin rotation and mixed versions fail closed before and after queued verification", function()
	WithWorld(function(world)
		local king = world:Client("Varrick-Realm", "Player-1-0A000001", "king")
		local council = world:Client("Council-Realm", "Player-1-0A000002", "council")
		local late = world:Client("Late-Realm", "Player-1-0A000003")
		assert(world:As(king, king.W.PublishGlobal)); world:Deliver()
		world:Offline(late); world.epoch = world.epoch + 10
		assert(world:As(king, king.W.PublishGlobal)); world:Deliver()
		local held = council.rdb.wanted.global.text
		world:Offline(king); world:Load(late); world:Deliver()
		local before = world:As(late, late.W.GlobalSnapshot).seq
		local function Receive(sender, text)
			return world:As(late, late.W.HandleGlobalRelay, "CHANNEL", sender, text or ("W5~1~" .. held))
		end
		local accepted, why = Receive("Ordinary-Realm")
		eq(accepted, false); eq(why, "authority")
		accepted, why = Receive(council.name, "W5~2~" .. held)
		eq(accepted, false); eq(why, "shape")
		accepted, why = world:As(late, late.W.HandleGlobalSnapshot, "CHANNEL", council.name, held)
		eq(accepted, false); eq(why, "authority", "old WY does not permit forwarded sender identity")
		assert(Receive(council.name))
		world.authorities[ns.Fold(council.name)] = nil
		world:Deliver()
		eq(world:As(late, late.W.GlobalSnapshot).seq, before, "revocation while Ed25519 yields cancels admission")
		world.authorities[ns.Fold(council.name)] = "council"
		assert(world:As(council, council.W.AnswerGlobal, "CHANNEL", late.name, "W4~1"))
		world.authorities[ns.Fold(council.name)] = nil
		world:Deliver()
		eq(world:As(late, late.W.GlobalSnapshot).seq, before, "delayed send checks the relay's real authority")
		world.authorities[ns.Fold(council.name)] = "council"
		world.authorities[ns.Fold(king.name)] = nil
		accepted, why = Receive(council.name); eq(accepted, false); eq(why, "authority")
		world.authorities[ns.Fold(king.name)] = "king"
		king.online = true
		king.seed = ns.Sign.SHA256("rotated issuer seed")
		king.pk = ns.Ed25519.PublicKey(king.seed)
		world:Offline(late)
		world.epoch = world.epoch + 10
		assert(world:As(king, king.W.PublishGlobal)); world:Deliver()
		held = council.rdb.wanted.global.text
		world:Load(late); world:Deliver()
		accepted, why = Receive(council.name); eq(accepted, false); eq(why, "unanchored", "relay cannot rotate a directly anchored key")
		assert(world:As(king, king.W.RepeatGlobal)); world:Deliver()
		-- The direct word reaches this peer, so it can now accept a later relay under the new key.
		world:Offline(late); world.epoch = world.epoch + 10
		assert(world:As(king, king.W.PublishGlobal)); world:Deliver()
		held = council.rdb.wanted.global.text
		world:Offline(king); world:Load(late); world:Deliver()
		assert(Receive(council.name)); world:Deliver()
		eq(late.rdb.wanted.global.text, held)
		world.epoch = world.epoch + late.W.GLOBAL_LIFE + 1
		accepted, why = Receive(council.name); eq(accepted, false); eq(why, "stale")
	end)
end)

test("wanted relay through real Comm: late recovery reassembles sender-bound chunks and rechecks authority on their unsent tail", function()
	WithWorld(function(world)
		local king = world:Client("Varrick-Realm", "Player-1-0A000001", "king")
		local council = world:Client("Council-Realm", "Player-1-0A000002", "council", true)
		local late = world:Client("Late-Realm", "Player-1-0A000003", nil, true)
		-- Populate the real reviewed ledger before switching its publisher to the native wire.
		for i = 1, 3 do
			local slayer = world:Client("Slayer" .. i .. "-Realm", "Player-1-0A00001" .. i)
			world:Hunt(slayer, king, "Hordeling" .. i .. "-Realm", "Player-1-0B00001" .. i, late, slayer)
		end
		king.realComm = true; world:Load(king); world:Deliver()
		assert(world:As(king, king.W.PublishGlobal)); world:PumpComm()
		local initial = world:As(late, late.W.GlobalSnapshot)
		assert(initial, "direct original native messages anchor the publisher key")
		world:Offline(late); world.epoch = world.epoch + 10
		assert(world:As(king, king.W.PublishGlobal)); world:PumpComm()
		local body = council.rdb.wanted.global.text
		world:Offline(king); world:Load(late); world:Deliver()
		assert(world:As(council, council.W.AnswerGlobal, "CHANNEL", late.name, "W4~1"))
		assert(council.ns.Comm.QueueSize() > 1, "an actual native-size chunk transfer")
		world.epoch = world.epoch + 2
		world:As(council, council.ns.Comm.Pump); world:Deliver()
		world.authorities[ns.Fold(council.name)] = nil
		world:PumpComm()
		eq(world:As(late, late.W.GlobalSnapshot).seq, initial.seq, "one authenticated sender's partial word cannot install")
		world.authorities[ns.Fold(council.name)] = "council"
		world.epoch = world.epoch + 300
		-- Use the recipient's real CHANNEL request, not a direct handler shortcut.
		assert(world:As(late, late.W.AskGlobal)); world:PumpComm()
		eq(late.rdb.wanted.global.text, body)
		eq(late.rdb.wanted.global.relay, council.name)
		eq(world:As(late, late.W.GlobalSnapshot).seq, initial.seq + 1)
		local replies = 0
		for _, m in ipairs(world.log) do if m.from == council and m.raw then replies = replies + 1 end end
		assert(replies >= 3, "actual game API emitted the canceled prefix plus the complete retry")
	end)
end)

test("wanted relay: queue refusal remains retryable and login requests stop at their bounded budget", function()
	WithWorld(function(world)
		local peer = world:Client("Peer-Realm", "Player-1-0A000003")
		local send = peer.ns.Comm.Send
		peer.ns.Comm.Send = function() return false, "full" end
		local accepted, why = world:As(peer, peer.W.AskGlobal)
		eq(accepted, false); eq(why, "full")
		peer.ns.Comm.Send = send
		assert(world:As(peer, peer.W.AskGlobal)); world:Deliver()
		accepted, why = world:As(peer, peer.W.AskGlobal)
		eq(accepted, false); eq(why, "rate")
		world:Run(1000)
		local count = 0
		for _, m in ipairs(world.log) do if m.from == peer and m.text == "W4~1" then count = count + 1 end end
		eq(count, 3, "one manual ask and only the two subsequent eligible login attempts")
		peer.member = false; world.epoch = world.epoch + 300
		accepted, why = world:As(peer, peer.W.AskGlobal)
		eq(accepted, false); eq(why, "member")
	end)
end)

test("wanted world: a reviewed, published top three reaches every client, outlives the old 30-minute word and survives their reloads", function()
	WithWorld(function(world)
		local king = world:Client("Varrick-Realm", "Player-1-0A000001", "king")
		local alpha = world:Client("Alpha-Realm", "Player-1-0A000002")
		local beta = world:Client("Beta-Realm", "Player-1-0A000003")
		world:Hunt(alpha, king, "Hordeling-Realm", "Player-1-0B000001", beta, alpha)
		local whispers = 0
		for _, m in ipairs(world.log) do
			if m.dist == "WHISPER" then
				whispers = whispers + 1
				assert(not m.text:find("Hordeling", 1, true) and not m.text:find("Arathi", 1, true), "no names or places leave privately")
			end
		end
		eq(whispers, 2)
		local mine = world:As(king, king.W.ReviewedRankings)
		eq(#mine, 1); eq(mine[1].guid, alpha.guid); eq(mine[1].points, 1)
		assert(world:As(king, king.W.PublishGlobal))
		world:Deliver()
		eq(world:Border(alpha, alpha.guid), "wanted-slayer-1")
		eq(world:Border(beta, alpha.guid), "wanted-slayer-1")
		eq(world:Border(beta, beta.guid), nil)

		world:Run(31 * 60)
		eq(world:Border(beta, alpha.guid), "wanted-slayer-1", "past the old word's whole 30-minute life")

		beta = world:Load(beta)
		eq(world:Border(beta, alpha.guid), nil, "after a reload, nothing before the signature holds again")
		world:Deliver()
		eq(world:Border(beta, alpha.guid), "wanted-slayer-1", "the saved word, checked again")
		eq(beta.W.Stats().globalRestored, 1)

		local body = king.db.wantedPublisher.last.body
		king = world:Load(king)
		local rows = world:As(king, king.W.ReviewedRankings)
		eq(#rows, 1, "the King's ledger did not start over"); eq(rows[1].points, 1)
		local before = #world.log
		world:Run(king.W.GLOBAL_LOGIN_REPEAT + 1)
		local repeated
		for i = before + 1, #world.log do if world.log[i].from == king and world.log[i].dist == "CHANNEL" then repeated = world.log[i].text end end
		eq(repeated, body, "after his login the King repeats the same word, its expiry unchanged")
		eq(world:Border(alpha, alpha.guid), "wanted-slayer-1")
	end)
end)

test("wanted world: replace and revoke reach every client; a client that missed the revocation takes it from the repeat, and a reload keeps it", function()
	WithWorld(function(world)
		local king = world:Client("Varrick-Realm", "Player-1-0A000011", "king")
		local council = world:Client("Seraphel-Realm", "Player-1-0A000012", "council")
		local alpha = world:Client("Alpha-Realm", "Player-1-0A000013")
		local beta = world:Client("Beta-Realm", "Player-1-0A000014")
		world:Hunt(alpha, king, "Hordeling-Realm", "Player-1-0B000011", beta, alpha)
		assert(world:As(king, king.W.PublishGlobal))
		world:Deliver()
		eq(world:Border(beta, alpha.guid), "wanted-slayer-1")

		world:Run(60)
		world:Hunt(beta, council, "Raider-Realm", "Player-1-0B000012", alpha, beta)
		assert(world:As(council, council.W.PublishGlobal))
		world:Deliver()
		for _, cl in ipairs({ alpha, beta, king }) do
			eq(world:As(cl, cl.W.GlobalSnapshot).issuer, council.name, cl.name .. " holds the newer word")
			eq(world:Border(cl, beta.guid), "wanted-slayer-1")
			eq(world:Border(cl, alpha.guid), nil, "replaced: the councillor's ledger does not hold Alpha")
		end

		world:Offline(beta)
		world:Run(60)
		assert(world:As(king, king.W.RevokeGlobal))
		world:Deliver()
		eq(world:Border(alpha, beta.guid), nil, "revoked: the King's newer empty word wins, whatever his key's epoch")
		eq(#world:As(alpha, alpha.W.GlobalSnapshot).rows, 0)

		beta = world:Load(beta)
		world:Deliver()
		eq(world:Border(beta, beta.guid), "wanted-slayer-1", "back online, Beta still holds the word it heard last")
		world:Run(king.W.GLOBAL_BURST_GAP + 1)
		eq(world:Border(beta, beta.guid), nil, "the King's repeat brings the revocation")
		beta = world:Load(beta)
		world:Deliver()
		eq(world:Border(beta, beta.guid), nil, "and a reload keeps it")
		eq(world:As(beta, beta.W.GlobalSnapshot).issuer, king.name)
	end)
end)

test("wanted world: a saved word shows again only while it holds: edited rows, another key, a lost role and its end", function()
	WithWorld(function(world)
		local king = world:Client("Varrick-Realm", "Player-1-0A000021", "king")
		local alpha = world:Client("Alpha-Realm", "Player-1-0A000022")
		local beta = world:Client("Beta-Realm", "Player-1-0A000023")
		world:Hunt(alpha, king, "Hordeling-Realm", "Player-1-0B000021", beta, alpha)
		assert(world:As(king, king.W.PublishGlobal))
		world:Deliver()
		local good = alpha.rdb.wanted.global
		local goodHeads = alpha.rdb.wanted.globalHeads
		assert(good and good.text:find("^WY~1~") and goodHeads, "the word Alpha accepted is saved")
		local function Saved(text, heads)
			alpha.rdb.wanted.global = { text = text, issuer = good.issuer, at = good.at }
			alpha.rdb.wanted.globalHeads = heads or goodHeads
		end

		Saved((good.text:gsub(":1:1:", ":9:1:", 1)))
		alpha = world:Load(alpha); world:Deliver()
		eq(world:Border(alpha, alpha.guid), nil, "an edited row breaks the signature")
		eq(alpha.rdb.wanted.global, nil, "and the saved word is dropped")

		-- Alpha's own key signs a word in the King's name: the King's pin refuses it.
		local fields = {}
		for part in (good.text .. "~"):gmatch("([^~]*)~") do fields[#fields + 1] = part end
		fields[9] = alpha.guid:gsub("^Player%-(%d+)%-(%x+)$", function(server, id) return server .. "." .. id:lower() end) .. ":99:9:" .. world.epoch
		local signed = table.concat({ "OLYW1", fields[3], fields[4], fields[5], fields[6], fields[7], fields[8], fields[9] }, "|")
		fields[10] = ns.Ed25519.ToB64(alpha.pk)
		fields[11] = ns.Ed25519.ToB64(ns.Ed25519.Sign(alpha.seed, signed, alpha.pk))
		Saved(table.concat(fields, "~"))
		alpha = world:Load(alpha); world:Deliver()
		eq(world:Border(alpha, alpha.guid), nil, "another key than the one pinned for its issuer")
		eq(alpha.rdb.wanted.global, nil)

		-- On a client where the issuer does not hold the role (its council list not yet in), the
		-- word waits, kept; it shows once the role is known.
		Saved(good.text)
		alpha.authorities = {}
		alpha = world:Load(alpha); world:Deliver()
		eq(world:Border(alpha, alpha.guid), nil)
		assert(alpha.rdb.wanted.global, "kept for a later look")
		alpha.authorities = nil
		world:As(alpha, alpha.listeners.DATA_CHANGED)
		world:Deliver()
		eq(world:Border(alpha, alpha.guid), "wanted-slayer-1", "the role is known again")

		world:Offline(king)
		world:Run(king.W.GLOBAL_LIFE + 1)
		eq(world:Border(alpha, alpha.guid), nil, "a month later, unrepublished: gone")
		eq(alpha.rdb.wanted.global, nil, "and dropped from the saved data")
		alpha = world:Load(alpha); world:Deliver()
		eq(world:Border(alpha, alpha.guid), nil)
	end)
end)

test("wanted world: own-claim submitters who disagree about one death: the reviewer sees the conflict and can keep only one killer", function()
	WithWorld(function(world)
		local king = world:Client("Varrick-Realm", "Player-1-0A000031", "king")
		local alpha = world:Client("Alpha-Realm", "Player-1-0A000032")
		local beta = world:Client("Beta-Realm", "Player-1-0A000033")
		local gamma = world:Client("Gamma-Realm", "Player-1-0A000034")
		local targetName, targetGuid = "Contested-Realm", "Player-1-0B000031"
		for i, cl in ipairs({ alpha, beta }) do
			cl.manager = true
			world:As(cl, function()
				assert(cl.W.AddTarget(targetName, targetGuid))
				assert(cl.W.CaptureCombatLog(500 + i, "PARTY_KILL", false, targetGuid, targetName, 0, 0, gamma.guid, gamma.name))
			end)
		end
		gamma.manager, gamma.dead = true, true
		world:As(gamma, function()
			assert(gamma.W.AddTarget(targetName, targetGuid))
			assert(gamma.W.CaptureSelfDeathRecap({ fatal = true, id = "contested-death", killerName = targetName,
				killerGUID = targetGuid, victimName = gamma.name, victimGUID = gamma.guid }))
		end)
		gamma.dead = false
		world.epoch = world.epoch + 6
		-- The same death of the target, each client naming its own player as the killer.
		for i, cl in ipairs({ alpha, beta }) do
			world:As(cl, function()
				assert(cl.W.CaptureCombatLog(600 + i, "PARTY_KILL", false, cl.guid, cl.name, 0, 0, targetGuid, targetName))
			end)
		end
		world.epoch = world.epoch + 6
		eq(world:As(alpha, alpha.W.SendEvidence, king.name), 2)
		eq(world:As(beta, beta.W.SendEvidence, king.name), 2)
		eq(world:As(gamma, gamma.W.SendEvidence, king.name), 1)
		world:Deliver()
		local inbox = world:As(king, king.W.ReviewInbox)
		eq(#inbox, 3, "only the actual victim and the two own-claim submitters reach review")
		local claims, bounties = {}, {}
		for _, e in ipairs(inbox) do
			if e.action == "claim" then claims[#claims + 1] = e else bounties[#bounties + 1] = e end
		end
		eq(claims[1].conflict, false); eq(claims[2].conflict, true, "the second account is flagged on arrival")
		for _, e in ipairs(bounties) do assert(world:As(king, king.W.Review, e.key, true), "the victim's own death") end
		assert(world:As(king, king.W.Review, claims[1].key, true))
		local ok, why = world:As(king, king.W.Review, claims[2].key, true)
		eq(ok, false); eq(why, "conflict")
		local rows = world:As(king, king.W.ReviewedRankings)
		eq(#rows, 1); eq(rows[1].guid, claims[1].killerGuid); eq(rows[1].points, 1, "the victim's death paid one point")

		assert(world:As(king, king.W.Withdraw, claims[1].key))
		assert(world:As(king, king.W.Review, claims[2].key, true), "the reviewer keeps the other killer instead")
		rows = world:As(king, king.W.ReviewedRankings)
		eq(#rows, 1); eq(rows[1].guid, claims[2].killerGuid); eq(rows[1].points, 1)
		king = world:Load(king)
		rows = world:As(king, king.W.ReviewedRankings)
		eq(rows[1].guid, claims[2].killerGuid, "the choice survives the reviewer's reload")
		assert(world:As(king, king.W.PublishGlobal))
		world:Deliver()
		eq(world:Border(gamma, claims[2].killerGuid), "wanted-slayer-1")
		eq(world:Border(gamma, claims[1].killerGuid), nil)
	end)
end)

test("wanted world: the publisher's repeat starts at his login, once his client knows his name: a client that never had the word gets it 90 seconds later, and from every 30-minute repeat", function()
	WithWorld(function(world)
		local king = world:Client("Varrick-Realm", "Player-1-0A000041", "king")
		local alpha = world:Client("Alpha-Realm", "Player-1-0A000042")
		local beta = world:Client("Beta-Realm", "Player-1-0A000043")
		world:Hunt(alpha, king, "Hordeling-Realm", "Player-1-0B000041", beta, alpha)
		assert(world:As(king, king.W.PublishGlobal))
		world:Deliver()
		world:Run(king.W.GLOBAL_BURST * king.W.GLOBAL_BURST_GAP + 60) -- past the first burst
		king = world:Load(king) -- he logs out and in again: INIT, then LOGIN
		local gamma = world:Client("Gamma-Realm", "Player-1-0A000044")
		eq(world:Border(gamma, alpha.guid), nil, "a client that never had the word")
		world:Run(king.W.GLOBAL_LOGIN_REPEAT + 1)
		eq(world:Border(gamma, alpha.guid), "wanted-slayer-1", "90 seconds after the King's login")
		local delta = world:Client("Delta-Realm", "Player-1-0A000045")
		world:Run(king.W.GLOBAL_REPEAT_EVERY + 1)
		eq(world:Border(delta, alpha.guid), "wanted-slayer-1", "and from his 30-minute repeat")
	end)
end)

test("wanted world: a publisher's own client holds the word he publishes and drops the frames as he revokes, though the channel never echoes his own words", function()
	WithWorld(function(world)
		local king = world:Client("Varrick-Realm", "Player-1-0A000051", "king")
		local council = world:Client("Seraphel-Realm", "Player-1-0A000052", "council")
		local alpha = world:Client("Alpha-Realm", "Player-1-0A000053")
		local beta = world:Client("Beta-Realm", "Player-1-0A000054")
		world:Hunt(alpha, king, "Hordeling-Realm", "Player-1-0B000051", beta, alpha)
		-- His client's checks are busy as he publishes: everyone else holds the word, then his own
		-- client from his first repeat.
		king.ns.Ed25519.Busy = function() return 40 end
		assert(world:As(king, king.W.PublishGlobal))
		world:Deliver()
		eq(world:Border(alpha, alpha.guid), "wanted-slayer-1")
		eq(world:Border(king, alpha.guid), nil)
		king.ns.Ed25519.Busy = function() return 0 end
		world:Run(king.W.GLOBAL_BURST_GAP + 1)
		eq(world:Border(king, alpha.guid), "wanted-slayer-1", "the King's own client shows the frame he signed")
		local lines, _, detail = world:As(king, king.W.Build)
		assert(table.concat(Headers(lines), "\n"):find(ns.L.WANTED_SIGNED, 1, true), "and the signed top three on his own list")
		assert(not detail:find(ns.L.WANTED_AUTHORITY_OFF, 1, true), detail)

		world:Run(60)
		world:Hunt(beta, council, "Raider-Realm", "Player-1-0B000052", alpha, beta)
		assert(world:As(council, council.W.PublishGlobal))
		world:Deliver()
		eq(world:Border(council, beta.guid), "wanted-slayer-1", "the councillor's own client too")
		eq(world:Border(king, beta.guid), "wanted-slayer-1", "the King heard the newer word")
		local councilWord = council.db.wantedPublisher.last.body

		world:Run(60)
		assert(world:As(king, king.W.RevokeGlobal))
		world:Deliver()
		for _, cl in ipairs({ king, council, alpha, beta }) do
			eq(world:Border(cl, beta.guid), nil, cl.name .. " drops the councillor's frame")
		end
		eq(world:As(king, king.W.GlobalSnapshot).issuer, king.name)
		-- On his client his revocation is the word held, with its order: the older word heard again
		-- changes nothing there, and after his reload neither.
		world:As(king, king.handlers.WY, "CHANNEL", council.name, councilWord)
		world:Deliver()
		eq(world:Border(king, beta.guid), nil)
		king = world:Load(king)
		world:Deliver()
		eq(world:Border(king, beta.guid), nil)
		eq(world:As(king, king.W.GlobalSnapshot).issuer, king.name, "his saved word is his revocation")
	end)
end)

test("wanted world: a word replaced by a newer one is not repeated by its publisher any more, so a client that logs in later never takes the older word", function()
	WithWorld(function(world)
		local king = world:Client("Varrick-Realm", "Player-1-0A000061", "king")
		local council = world:Client("Seraphel-Realm", "Player-1-0A000062", "council")
		local alpha = world:Client("Alpha-Realm", "Player-1-0A000063")
		local beta = world:Client("Beta-Realm", "Player-1-0A000064")
		world:Hunt(alpha, king, "Hordeling-Realm", "Player-1-0B000061", beta, alpha)
		assert(world:As(king, king.W.PublishGlobal))
		world:Deliver()
		local replacedWord = king.db.wantedPublisher.last.body
		world:Run(60)
		world:Hunt(beta, council, "Raider-Realm", "Player-1-0B000062", alpha, beta)
		assert(world:As(council, council.W.PublishGlobal))
		world:Deliver()
		eq(world:As(king, king.W.GlobalSnapshot).issuer, council.name, "the King's client holds the newer word")
		world:Offline(council)

		local function KingSent(from)
			for i = from, #world.log do
				local m = world.log[i]
				-- A catch-up request or an unchanged relay of the newer word is not a repeat
				-- of the old publisher's replaced word.
				if m.from == king and m.dist == "CHANNEL" and (m.text == replacedWord or m.text == "W5~1~" .. replacedWord) then return true end
			end
			return false
		end
		local gamma = world:Client("Gamma-Realm", "Player-1-0A000065")
		local before = #world.log + 1
		world:Run(king.W.GLOBAL_BURST * king.W.GLOBAL_BURST_GAP + king.W.GLOBAL_REPEAT_EVERY + 1)
		eq(KingSent(before), false, "the King repeats no replaced word")
		eq(world:As(gamma, gamma.W.GlobalSnapshot), nil, "a later client never takes the older word")
		eq(world:Border(gamma, alpha.guid), nil)
		eq(world:Border(beta, beta.guid), "wanted-slayer-1", "the newer word holds where it was heard")

		king = world:Load(king)
		world:Deliver()
		local delta = world:Client("Delta-Realm", "Player-1-0A000066")
		before = #world.log + 1
		world:Run(king.W.GLOBAL_LOGIN_REPEAT + king.W.GLOBAL_REPEAT_EVERY + 1)
		eq(KingSent(before), false, "nor after his login")
		eq(world:As(delta, delta.W.GlobalSnapshot), nil)

		-- A word of his own published later is repeated as before.
		assert(world:As(king, king.W.RevokeGlobal))
		world:Deliver()
		local epsilon = world:Client("Epsilon-Realm", "Player-1-0A000067")
		world:Run(king.W.GLOBAL_BURST_GAP + 1)
		eq(world:As(epsilon, epsilon.W.GlobalSnapshot).issuer, king.name)
	end)
end)

-- Daniel's test build: the game's "blocked from an action" pop-up at every login came from
-- Frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") (taint.log, Wanted.lua). On Forever the
-- combat log events are restricted: no Olympus file may register them, however it is written.
test("Most Wanted: no Olympus file registers a restricted combat log event (Forever blocks the addon at login)", function()
	local RESTRICTED = { "COMBAT_LOG_EVENT_UNFILTERED", "COMBAT_LOG_EVENT" }
	local found = {}
	for _, dir in ipairs({ "Olympus", "Olympus_Arena" }) do
		local p = io.popen('find "' .. ROOT .. dir .. '" -name "*.lua"')
		for path in p:lines() do
			local f = io.open(path, "rb")
			local src = f and f:read("*a") or ""
			if f then f:close() end
			for line in src:gmatch("[^\n]+") do
				local code = line:gsub("%-%-.*$", "")
				for _, ev in ipairs(RESTRICTED) do
					if code:find('RegisterEvent[^\n]-"' .. ev .. '"') or code:find("RegisterEvent[^\n]-'" .. ev .. "'") then
						found[#found + 1] = path:sub(#ROOT + 1) .. ": " .. line
					end
				end
			end
		end
		p:close()
	end
	eq(#found, 0, table.concat(found, "\n"))
end)

test("wanted own-proof: claimed or revoked membership and unknown identity cannot consume review; real self and server-named members still work", function()
	WithWanted(function(w, W, c)
		local reviewer = w.authority("OwnReviewer-Realm", "council")
		c.me = reviewer
		local sender = w.participant("ForeignVictim-Realm", "Player-1-CC000031")
		local H = w.commHandlers.WX
		local function Wire(digest, victim)
			return ("WX~1~%016x~%d~24000~S~B~1.dd000031~%s"):format(digest, w.epoch, victim or "1.cc000031")
		end
		w.rosterStale = true
		H("WHISPER", sender, Wire(1))
		eq(#W.ReviewInbox(), 0, "a stale own roster and numeric-only guild claim grant no review authority")
		c.Channels.VerifiedLevel = function() return 1, true end
		local admitted, why = H("WHISPER", sender, Wire(2, "1.cc000032"))
		eq(admitted, false); eq(why, "identity")
		eq(#W.ReviewInbox(), 0, "verified membership cannot invent an unknown own GUID")
		assert(H("WHISPER", sender, Wire(3)), "independently verified membership plus server GUID proof")
		c.Channels.VerifiedLevel = function() return 0, false end
		admitted, why = H("WHISPER", sender, Wire(4))
		eq(admitted, false); eq(why, "olympus", "revoked source cannot submit more rows")
		eq(#W.ReviewInbox(), 1)
		w.rosterStale = false
		assert(H("WHISPER", sender, Wire(5)), "fresh own roster remains a legitimate fallback")
		w.units.player.name = reviewer
		w.olympian(reviewer)
		GetPlayerInfoByGUID = nil
		assert(H("WHISPER", reviewer, Wire(6, "1.aa000001")), "real own player GUID/name works without a GUID cache API")
		admitted, why = H("WHISPER", sender, Wire(7, "1.aa000001"))
		eq(admitted, false); eq(why, "not-own", "another name cannot appropriate the known self GUID")
		eq(#W.ReviewInbox(), 3)
		eq(#W.Ledger(), 0, "positive identity is still testimony until a human accepts")
	end)
end)

test("wanted review adversarial (1.2.0): WX only from a member, about his own kill or death: a stranger's row, or a member's row whose Olympian side names someone else, waits nowhere", function()
	WithWanted(function(w, W, c)
		c.me = w.authority("OwnReviewer-Realm", "council")
		local H = w.commHandlers.WX
		w.participant("Ownvictim-Realm", "Player-1-CC000022")
		w.strangers[c.Fold("Outsider-Realm")] = true
		H("WHISPER", "Outsider-Realm", ("WX~1~00000000000000b1~%d~24000~S~B~1.dd000021~1.cc000021"):format(w.epoch))
		eq(#W.ReviewInbox(), 0, "a stranger's evidence")
		local saved = GetPlayerInfoByGUID
		GetPlayerInfoByGUID = function(guid)
			if guid == "Player-1-CC000021" then return "Warrior", "WARRIOR", "Human", "Human", 2, "Someoneelse", "Realm" end
			if guid == "Player-1-CC000022" then return "Warrior", "WARRIOR", "Human", "Human", 2, "Ownvictim", "Realm" end
		end
		local ok, err = pcall(function()
			H("WHISPER", "Ownvictim-Realm", ("WX~1~00000000000000b2~%d~24000~S~B~1.dd000021~1.cc000021"):format(w.epoch))
			eq(#W.ReviewInbox(), 0, "a death that names another victim than the sender")
			H("WHISPER", "Ownvictim-Realm", ("WX~1~00000000000000b3~%d~24000~S~B~1.dd000022~1.cc000022"):format(w.epoch))
			eq(#W.ReviewInbox(), 1, "his own death waits for the reviewer")
		end)
		GetPlayerInfoByGUID = saved
		if not ok then error(err, 0) end
	end)
end)
