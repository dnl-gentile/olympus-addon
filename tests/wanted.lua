-- Horde Most Wanted: the real ledger and adapters against a small supported-client boundary.
local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]wanted%.lua$")) or "./"

-- (1.2.3: Add, Send evidence, Review and Withdraw are gone; Sightings to is new. The old names stay
-- here so that a dialog an older build defined is put back as it was.)
local DIALOGS = { "OLYMPUS_WANTED_ADD", "OLYMPUS_WANTED_REMOVE", "OLYMPUS_WANTED_SEND", "OLYMPUS_WANTED_REVIEW",
	"OLYMPUS_WANTED_WITHDRAW", "OLYMPUS_WANTED_PUBLISH", "OLYMPUS_WANTED_REVOKE", "OLYMPUS_WANTED_CORRECT",
	"OLYMPUS_WANTED_REVIEWER", "OLYMPUS_WANTED_AVENGED" }

-- 1.2.4, the notices: Olympus's own windows as stand-ins that keep what they show (ns.Window: the
-- death's toast), Olympus's dialogs (Dialog.Show and Find: the avenged notice and the whisper
-- windows its buttons open), the King's letter (HonorsNet's QueueLetter, LetterToSender and
-- LetterFrame) and the Olympus window's whisper window, profile and state (UI.WhisperText,
-- ShowPerson, IsShown), each kept in `into` (a test world, or a world's client).
local function StandInFrame(kind)
	local o = { kind = kind, shown = false, points = {} }
	function o:Show() self.shown = true end
	function o:Hide() self.shown = false end
	function o:IsShown() return self.shown end
	function o:SetText(text) self.text = text end
	function o:GetText() return self.text end
	function o:ClearAllPoints() self.points = {} end
	function o:SetPoint(...) self.points[#self.points + 1] = { ... } end
	function o:EnableMouse(on) self.mouse = on end
	function o:SetFrameStrata(strata) self.strata = strata end
	function o:CreateTexture() return StandInFrame("texture") end
	function o:CreateFontString() return StandInFrame("font") end
	return setmetatable(o, { __index = function() return function() end end })
end
local function NoticeStandIns(c, into)
	into.windows, into.shownDialogs, into.letters = into.windows or {}, into.shownDialogs or {}, into.letters or {}
	into.whispers, into.people = into.whispers or {}, into.people or {}
	c.Window = function(name, _, opts)
		local f = StandInFrame("window")
		f.name, f.opts = name, opts
		into.windows[name] = f
		return f
	end
	c.Dialog = {
		Show = function(which, a, b, data)
			local f = StandInFrame("dialog")
			f.which, f.a, f.b, f.data, f.def, f.shown = which, a, b, data, StaticPopupDialogs[which], true
			into.shownDialogs[#into.shownDialogs + 1] = f
			return f
		end,
		Find = function(which)
			for _, f in ipairs(into.shownDialogs) do if f.which == which and f.shown then return f end end
			return nil
		end,
	}
	-- (1.2.4 repair: QueueLetter's third argument, "show it now", kept in into.letterNow; the times a
	-- letter waited for the Olympus window, WaitForWindow, in into.windowWaits.)
	into.letterNow, into.windowWaits = into.letterNow or {}, into.windowWaits or 0
	c.HonorsNet = { QueueLetter = function(key, _, now) into.letters[#into.letters + 1] = key into.letterNow[#into.letters] = now end,
		LetterToSender = function() return into.kingLetter == true end, LetterFrame = function() return into.letterFrame end,
		WaitForWindow = function() into.windowWaits = into.windowWaits + 1 end }
	c.UI = c.UI or {}
	c.UI.WhisperText = function(name, text) into.whispers[#into.whispers + 1] = { name = name, text = text } return true end
	c.UI.IsShown = function() return into.windowOpen == true end
	if not c.UI.ShowPerson then c.UI.ShowPerson = function(p) into.people[#into.people + 1] = p return true end end
end

local function WithWanted(fn)
	local globals = { "UnitGUID", "UnitIsPlayer", "UnitFactionGroup", "GetGuildInfo", "GetRealZoneText",
		"UnitCanAttack", "UnitIsPVP", "issecretvalue", "IsInInstance",
		"UnitIsDeadOrGhost", "C_DateAndTime", "C_DeathInfo", "C_DeathRecap", "CombatLogGetCurrentEventInfo", "GetGameTime", "GetFileIDFromPath",
		"ERR_CHAT_PLAYER_NOT_FOUND_S", "GetPlayerInfoByGUID", "UnitTokenFromGUID", "UnitLevel", "GetMaxPlayerLevel", "InCombatLockdown",
		"C_DamageMeter", "C_Map" }
	local saved = {}
	for _, name in ipairs(globals) do saved[name] = _G[name] end
	local dialogs = {}
	for _, which in ipairs(DIALOGS) do dialogs[which] = StaticPopupDialogs[which] end

	local w = { epoch = 1800000000, year = 2026, month = 10, member = true, manager = true, units = {},
		olympians = {}, authorities = {}, handlers = {}, commHandlers = {}, listeners = {}, events = {}, dialogs = {},
		prints = {}, assets = {}, sent = {}, identities = {}, horde = {}, publicKey = string.rep("K", 32), refreshed = 0 }
	local ok, err = pcall(function()
		-- (1.2.3: level 1 unless a test gives another, so a plain member's own death adds 1 point,
		-- as one did before the bounty's weights; the bounty's own tests give the real levels.)
		w.units.player = { name = "Olympian-Realm", guid = "Player-1-AA000001", faction = "Alliance", guild = "Olympus II", level = 1 }
		UnitGUID = function(unit) return w.units[unit] and w.units[unit].guid end
		-- (1.2.3: UnitLevel as the game gives it: -1 for "??", nil for no unit or no level given.)
		UnitLevel = function(unit) return w.units[unit] and w.units[unit].level end
		GetMaxPlayerLevel = function() return w.maxLevel or 60 end
		InCombatLockdown = function() return w.combat == true end
		UnitIsPlayer = function(unit) return w.units[unit] and w.units[unit].player ~= false or false end
		UnitFactionGroup = function(unit) return w.units[unit] and w.units[unit].faction end
		UnitIsDeadOrGhost = function(unit) return unit == "player" and w.dead ~= false end
		-- (The guild, its rank's name and index, as the game gives them: rank 0 is its master.)
		GetGuildInfo = function(unit)
			local u = w.units[unit or "player"]
			if u then return u.guild, u.rank and "Rank" .. u.rank or nil, u.rank end
		end
		GetRealZoneText = function() return "Warsong Gulch" end
		C_Map = { GetBestMapForUnit = function(unit) return unit == "player" and 489 or nil end,
			GetMapInfo = function(mapID) return mapID == 489 and { mapType = 3 } or nil end }
		-- (1.2.3: a battleground or an arena counts no kill nor death: w.inside.)
		IsInInstance = function() return w.inside == true, w.inside and "pvp" or "none" end
		C_DateAndTime = { GetCurrentCalendarTime = function() return { year = w.year, month = w.month } end }
		GetFileIDFromPath = function(path) return w.assets[path] and 1 or nil end
		-- (1.2.4: the game's token for a GUID, as Forever has it, UnitDocumentation.lua: a unit this
		-- client has (w.units), else none. Before, none at all, a client without the call.)
		UnitTokenFromGUID = function(guid)
			for unit, u in pairs(w.units) do if u.guid == guid then return unit end end
			return nil
		end
		-- The game's lookup of a player GUID (PlayerScriptDocumentation.lua: localizedClass,
		-- englishClass, localizedRace, englishRace, sex, name, realmName): w.identities are Olympians
		-- (Human), w.horde Horde players (an Orc unless his race is given; a name only when given).
		GetPlayerInfoByGUID = function(guid)
			local h = w.horde[guid]
			if h then return "Warrior", "WARRIOR", h.race or "Orc", h.race or "Orc", 2, h.name and ns.ShortName(h.name) or nil, "Realm" end
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
			Send = function(dist, text, key, _, _, done, options)
				w.sent[#w.sent + 1] = { dist = dist, text = text, key = key, done = done, options = options }; return true
			end,
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
		-- (1.2.3: the privacy page, as the earlier deaths' notice waits for it: w.consentShown, w.consentWaiting.)
		c.Consent = { Frame = function() return w.consentShown and { IsShown = function() return true end } or nil end,
			Waiting = function() return w.consentWaiting == true end }
		-- (1.2.4: the notices' windows, dialogs, letters and the update letter, w.updateLetter.)
		NoticeStandIns(c, w)
		c.Letters = { Frame = function() return w.updateLetter and { IsShown = function() return true end } or nil end }

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
		-- A Horde player as the game's lookup of his GUID knows him (an Orc unless told).
		function w.hordePlayer(name, guid, race)
			w.horde[guid] = { name = c.FullName(name), race = race }
			return c.FullName(name)
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
			p.RealmPages = {}
			assert(loadfile(ROOT .. "Olympus/RankingRules.lua"))("Olympus", p)
			local mine = {}
			for _, which in ipairs(DIALOGS) do mine[which] = StaticPopupDialogs[which] end
			assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", p)
			for _, which in ipairs(DIALOGS) do StaticPopupDialogs[which] = mine[which] end
			p.Wanted.ResetForTests()
			w.pub = p
			return p
		end
		-- (1.2.3: what a publisher signs is his own Slayers board, SignableRankings.)
		function w.publish(rows, epoch)
			local p = w.publisher()
			p.me = c.me
			local rankings = p.Wanted.SignableRankings
			p.Wanted.SignableRankings = function() return rows end
			if epoch then c.db.wantedPublisher = { epoch = epoch, seq = 0 } end
			local ok, why = p.Wanted.PublishGlobal()
			p.Wanted.SignableRankings = rankings
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
		-- Forever's death recap (C_DeathRecap, no recap ID): rows as the client gives them.
		function w.recap(rows)
			if rows and rows[1] == nil then rows = { rows } end
			C_DeathInfo = nil
			C_DeathRecap = { HasRecapEvents = function() return rows ~= nil end, GetRecapEvents = function() return rows or {} end }
		end
		-- 1.2.3 repair: the game's damage meter (C_DamageMeter, DamageMeterDocumentation.lua): its
		-- Deaths sources, one a death in the group, each its recap ID and whether it is the local
		-- player's (deaths: { { id, mine } }), in its overall session.
		function w.meter(deaths)
			C_DamageMeter = { GetCombatSessionFromType = function(kind, meterType)
				local sources = {}
				if kind == 0 and meterType == 9 then
					for _, d in ipairs(deaths) do sources[#sources + 1] = { deathRecapID = d[1], isLocalPlayer = d[2] == true, deathTimeSeconds = -1 } end
				end
				return { combatSources = sources }
			end }
		end
		function w.die(rows)
			w.recap(rows)
			w.dead = true
			w.handlers.PLAYER_DEAD()
		end
		-- A Forever-shaped recap of a death to a player: the newest row first, and it is the killing
		-- blow (overkill 0 or more; the older ones -1), sourceName "Given-Realm" (no surname),
		-- sourceFlags of a hostile player (0x548), timestamps in the server's seconds (Blizzard_DeathRecap.lua
		-- and HeadHunter's Forever probe; DeathRecapEventInfo documents no fields).
		function w.forever(killerName, killerGuid, o)
			o = o or {}
			local at = o.at or (w.epoch - 0.2)
			return {
				{ event = o.event or "SPELL_DAMAGE", sourceGUID = killerGuid, sourceName = killerName, sourceFlags = o.flags or 0x548,
					overkill = o.overkill or 233, timestamp = at, amount = 900, spellId = 11366, spellName = "Pyroblast", school = 4 },
				{ event = "SWING_DAMAGE", sourceGUID = killerGuid, sourceName = killerName, sourceFlags = o.flags or 0x548,
					overkill = -1, timestamp = at - 2.4, amount = 310 },
			}
		end
		-- The rows this client put on the Olympus channel (WK, WV), in order.
		function w.wire(prefix)
			local out = {}
			for _, m in ipairs(w.sent) do if m.dist == "CHANNEL" and m.text:sub(1, #prefix) == prefix then out[#out + 1] = m.text end end
			return out
		end

		c.RealmPages = {}
		assert(loadfile(ROOT .. "Olympus/RankingRules.lua"))("Olympus", c)
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
		-- (1.2.4, changed on purpose, the author's report: a Horde player with 0 points and 0 kills is
		-- not on the list, one listed by hand neither. Grom's row shows once he has killed a member;
		-- his entry learns his GUID from it.)
		for _, line in ipairs(lines) do assert(line.id ~= "wanted:" .. grom.key, "listed by hand, 0 points and 0 kills: not shown") end
		w.olympian("Victim-Realm")
		assert(w.kill(301, "Grom-Realm", "Player-1-ABCD0001", "Victim-Realm", "Player-1-AC000301"))
		grom = assert(W.Target("Grom-Realm"))
		eq(grom.lifetimeKills, 1)
		lines = W.Build()
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

test("wanted 1.2.4 page: Wanted and both local Slayers boards start at five and expand independently by ten, while zero-zero entries stay hidden", function()
	WithWanted(function(w, W, c)
		w.manager = false
		local never = "Player-1-E1000000"
		assert(w.add("Never Counted-Realm", never), "a legacy zero-zero entry exists behind the page")
		for i = 1, 16 do
			local horde = ("Player-1-E1%06X"):format(i)
			local wanted = w.hordePlayer(("Wanted%02d-Realm"):format(i), horde)
			assert(w.add(wanted, horde), "the combat-log adapter starts from the known Horde side")
			local victim = w.olympian(("PageVictim%02d-Realm"):format(i))
			assert(w.kill(10000 + i, wanted, horde, victim,
				("Player-1-E2%06X"):format(i)))
			w.advance()
		end
		local originalName, originalGuid = c.me, w.units.player.guid
		for i = 1, 16 do
			local slayerGuid = ("Player-1-E3%06X"):format(i)
			local slayer = w.participant(("PageSlayer%02d-Realm"):format(i), slayerGuid)
			local preyGuid = ("Player-1-E4%06X"):format(i)
			local prey = w.hordePlayer(("PagePrey%02d-Realm"):format(i), preyGuid)
			c.me, w.units.player.name, w.units.player.guid = slayer, slayer, slayerGuid
			w.units.target = { name = prey, guid = preyGuid, faction = "Horde", level = i }
			assert(w.handlers.PARTY_KILL(slayerGuid, preyGuid))
			w.units.target = nil
			w.advance()
		end
		c.me, w.units.player.name, w.units.player.guid = originalName, originalName, originalGuid

		local function State(lines)
			local out = { wanted = 0, month = 0, all = 0, more = {} }
			local section
			for _, line in ipairs(lines) do
				if line.header then
					if line.text == c.L.WANTED_TARGETS then section = "wanted"
					elseif line.text == c.L.WANTED_LOCAL_ALL then section = "all"
					elseif type(line.text) == "string" and line.text:find(c.L.WANTED_MONTHLY:match("^[^%%]+"), 1, true) then section = "month"
					else section = nil end
				elseif line.id and line.id:find("%-more$") then out.more[line.id] = line
				elseif section == "wanted" and line.id and line.id:find("^wanted:") then out.wanted = out.wanted + 1
				elseif (section == "month" or section == "all") and line.player then out[section] = out[section] + 1 end
			end
			return out
		end
		local state = State(W.Build())
		eq(state.wanted, 5, "the Slayers boards are reachable after five Wanted rows")
		eq(state.month, 5); eq(state.all, 5)
		assert(state.more["wanted-more"] and state.more["wanted-more"].text:find(c.L.SHOW_MORE:format(10, 5, 16), 1, true))
		assert(state.more["slayers-month-more"] and state.more["slayers-month-more"].text:find(c.L.SHOW_MORE:format(10, 5, 16), 1, true))
		assert(state.more["slayers-all-more"] and state.more["slayers-all-more"].text:find(c.L.SHOW_MORE:format(10, 5, 16), 1, true))
		for _, line in ipairs(W.Build()) do assert(line.id ~= "wanted:g:" .. never, "zero points and zero kills stays hidden") end

		state.more["wanted-more"].onClick()
		state = State(W.Build())
		eq(state.wanted, 15); eq(state.month, 5); eq(state.all, 5, "Wanted expansion does not move either Slayers limit")
		state.more["wanted-more"].onClick()
		state = State(W.Build())
		eq(state.wanted, 16); eq(state.more["wanted-more"], nil)

		state.more["slayers-month-more"].onClick()
		state = State(W.Build())
		eq(state.wanted, 16); eq(state.month, 15); eq(state.all, 5, "monthly expansion is independent")
		state.more["slayers-month-more"].onClick()
		state = State(W.Build())
		eq(state.month, 16); eq(state.more["slayers-month-more"], nil)

		state.more["slayers-all-more"].onClick()
		state = State(W.Build())
		eq(state.all, 15); eq(state.month, 16, "all-time expansion is independent")
		state.more["slayers-all-more"].onClick()
		state = State(W.Build())
		eq(state.all, 16); eq(state.more["slayers-all-more"], nil)
		assert(w.refreshed >= 6, "each click refreshes the visible page")

		assert(w.tab and w.tab.onLeave, "the Most Wanted tab supplies its leave cleanup")
		w.tab.onLeave()
		state = State(W.Build())
		eq(state.wanted, 5, "returning to Most Wanted collapses the Wanted preview")
		eq(state.month, 5, "returning collapses the monthly Slayers preview")
		eq(state.all, 5, "returning collapses the all-time Slayers preview")
	end)
end)

test("wanted 1.2.4 ranking rules: the native link uses live scoring, Back keeps list state and access loss fails closed", function()
	WithWanted(function(w, W, c)
		W.listShown.wanted = 15
		local link
		for _, line in ipairs(W.Build()) do
			if line.id == "ranking-rules:wanted-slayers" then link = line end
		end
		assert(link and link.onClick, "the prominent in-window Wanted rules link")
		assert(link.onClick())
		eq(W.PageId(), "rules")

		local lines = W.Build()
		eq(lines[1].id, "ranking-rules-back")
		local spec = assert(c.RankingRules.Spec("wanted-slayers"))
		local sections = spec.sections()
		eq(sections[1].text[1], c.L.RANK_RULE_WANTED_BOUNTY:format(2000, 10))
		eq(sections[1].text[2], c.L.RANK_RULE_WANTED_SLAYER:format(10, 100, 14))
		eq(sections[2].text, c.L.RANK_RULE_WANTED_LIMITS:format(60, 24))
		assert(sections[1].text[1]:find("one historical kill and up to 1 bounty point below the same cap", 1, true))
		assert(sections[1].text[2]:find("pays only the open bounty", 1, true))
		assert(lines[1].onClick())
		eq(W.PageId(), "list")
		eq(W.listShown.wanted, 15, "Back returns to the exact list pagination state")

		for _, line in ipairs(W.Build()) do
			if line.id == "ranking-rules:wanted-slayers" then assert(line.onClick()) end
		end
		w.member = false
		eq(#W.Build(), 0, "a stale rules page discloses nothing after membership is lost")
		eq(W.PageId(), "list")
		for _, line in ipairs(W.Build()) do
			assert(line.id ~= "ranking-rules:wanted-slayers", "the link is also access-gated")
		end
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

-- (1.2.3: CaptureSelfDeathRecap, the reader of a recap shape no client gives, is gone: the player's own
-- death is read from Forever's C_DeathRecap alone, PLAYER_DEAD, and these checks moved there.)
test("wanted: the own-death recap needs our own death, a recent killing blow, a player killer's GUID and a hostile player's damage", function()
	WithWanted(function(w, W, c)
		local targetGuid = "Player-1-EE000001"
		assert(w.add("Ripper-Realm", targetGuid))
		w.recap(w.forever("Ripper-Realm", targetGuid))
		w.dead = false; w.handlers.PLAYER_DEAD()
		eq(W.Target("Ripper-Realm").current, 0, "alive: no death to attribute")
		w.dead = true
		local rows = w.forever("Ripper-Realm", targetGuid)
		rows[1].overkill = -1
		w.recap(rows); w.handlers.PLAYER_DEAD()
		eq(W.Target("Ripper-Realm").current, 0, "no killing blow in the recap")
		rows = w.forever("Ripper-Realm", nil)
		w.recap(rows); w.handlers.PLAYER_DEAD()
		eq(W.Target("Ripper-Realm").current, 0, "a killer's name alone is never inferred to be the listed player")
		rows = w.forever("Ripper-Realm", targetGuid, { event = "SPELL_HEAL" })
		w.recap(rows); w.handlers.PLAYER_DEAD()
		eq(W.Target("Ripper-Realm").current, 0, "a killing blow that was no damage")
		w.die(w.forever("Ripper-Realm", targetGuid))
		local t = W.Target("Ripper-Realm")
		eq(t.current, 1); eq(t.lastSighting.zone, "Warsong Gulch"); eq(t.lastSighting.mapID, 489, "the stable map ID is kept beside localized text")
		eq(t.lastSighting.precision, "approximate")
		eq(t.victims[1].name, c.me, "the victim is our own player unit")
		w.advance(1)
		local ok, why = w.kill("same-death", "Ripper-Realm", targetGuid, c.me, w.units.player.guid)
		eq(ok, false); eq(why, "replay", "the two adapters cannot count one death twice")
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
		-- (1.2.3: a void is a reviewer's, the King's, a High Councillor's or the author's: the roles
		-- every client checks on his word, WV; no longer a Watch moderator's alone.)
		w.authority(c.me, "king")
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
		eq(ok, true); eq(why, nil); assert(message and message:find("^WY~2~"))
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

-- 1.2.4: the slayers' frame is an honour (Honors' wanted-slayer: the skeletal horse), and a player's
-- pick decides it. Where this client knows his pick (HonorsNet.PickKnown: his own, or his profile
-- heard), GlobalBorder gives nothing and the honours show what that pick shows ("none", another frame
-- he holds, the horse he picked); only a slayer whose pick is unknown here still wears his place's by
-- GUID. (Until 1.2.4 the frame, the orc's wolf then, went over "none" and the cornucopia.)
test("1.2.4 wanted global: a slayer whose pick this client knows gets no frame from Wanted (his pick decides it, HonorsNet.Verified); one whose pick is unknown still gets his place's by GUID; never by a name; the skeletal horse's art", function()
	WithWanted(function(w, W, c)
		local council = w.authority("Council-Realm", "council")
		c.me = council
		local rows = {
			{ guid = "Player-1-DA000001", points = 9, claims = 3, reachedAt = w.epoch },
			{ guid = "Player-1-DA000002", points = 7, claims = 1, reachedAt = w.epoch },
		}
		local ok, _, message = w.publish(rows, 100)
		assert(ok and message)
		assert(W.HandleGlobalSnapshot("CHANNEL", council, message))
		local known = {}
		rawset(c, "HonorsNet", { PickKnown = function(name) return known[name] == true end })
		eq(W.GlobalBorder("Slayer-Realm", "Player-1-DA000001"), "wanted-slayer-1", "his pick unknown here: by his GUID, as before")
		known["Slayer-Realm"] = true
		eq(W.GlobalBorder("Slayer-Realm", "Player-1-DA000001"), nil, "his pick known: the honours show what it shows")
		eq(W.GlobalBorder("Second-Realm", "Player-1-DA000002"), "wanted-slayer-2")
		eq(W.GlobalBorder("Second-Realm"), nil, "never by a name")
		local hs = {}
		assert(loadfile(ROOT .. "Olympus/Honors.lua"))("Olympus", hs)
		eq(hs.Honors.ArtOf("wanted-slayer-1"), "skeletal-horse-gold", "the skeletal horse (the orc's wolf until 1.2.4)")
		eq(hs.Honors.ArtOf("wanted-slayer-3"), "skeletal-horse-bronze")
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
			local signed = table.concat({ "OLYW2", fields[3], fields[4], fields[5], fields[6], fields[7], fields[8], fields[9] }, "|")
			fields[11] = c.Debts.B64(c.Debts.Sign(signed))
			return table.concat(fields, "~")
		end
		local legacy = Fields(first); legacy[2] = "1"
		local legacySigned = table.concat({ "OLYW1", legacy[3], legacy[4], legacy[5], legacy[6], legacy[7], legacy[8], legacy[9] }, "|")
		legacy[11] = c.Debts.B64(c.Debts.Sign(legacySigned))
		eq(select(2, W.HandleGlobalSnapshot("CHANNEL", council, table.concat(legacy, "~"))), "shape",
			"a correctly signed score-v1 total cannot enter the score-v2 board")
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
		-- Our own death to the environment (a fall, lava, drowning: no source), to a creature that carries
		-- the listed name, and to the wolf: Forever's own recap, no player killer.
		for _, source in ipairs({ { "Falling", nil }, { "Grom", creatureGuid }, { "Grom", petGuid } }) do
			w.advance(W.DEATH_WINDOW + 1)
			w.die(w.forever(source[1], source[2], { flags = source[2] == petGuid and 0x1148 or 0xa48 }))
		end
		-- The native kill event's victim a creature or a pet: no Horde player.
		w.advance(); eq(select(2, w.handlers.PARTY_KILL(w.units.player.guid, creatureGuid)), "identities")
		w.advance(); eq(select(2, w.handlers.PARTY_KILL(w.units.player.guid, petGuid)), "identities")
		local t = W.Target("Grom-Realm")
		eq(t.current, 0); eq(t.lifetimeKills, 0); eq(#t.claims, 0); eq(t.guid, nil, "no refused row taught the listing a GUID")
		eq(#W.Targets(), 1, "and none made an entry"); eq(#W.Rankings().all, 0); eq(W.Stats().accepted, 0)
		eq(#w.wire("WK"), 0, "nothing shared")
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
		w.die(w.forever(ripper, ripperGuid))
		eq(W.Target(ripper).current, 1)
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
		-- (1.2.3: a victim nobody listed is no refusal by itself; one whose Horde faction this client
		-- cannot prove is: Player-1-FF000022 is no Horde player the game's lookup knows.)
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
		-- (1.2.3: taking an entry off is a reviewer's: the King here.)
		w.authority(c.me, "king")
		assert(W.RemoveTarget(nil, guid)); w.advance(); eq(select(2, event(mine, guid)), "removed")
		eq(W.Stats().accepted, before, "invalid, secret and removed identities never record a kill")
		-- (1.2.3, changed on purpose, Daniel's "that list should never have existed": each native kill
		-- this client counted went to the Olympus channel at once, for every member's client to count
		-- too; the removal went as the King's word. Before, nothing left this client by itself.)
		-- (1.2.3, changed on purpose, Daniel's bounty: an own row goes as WK~2, what it is worth after the
		-- GUIDs: the member's office and level, the Horde player's level.)
		eq(#w.wire("WK~2~"), 3, "one row for each of the three native kills counted")
		eq(#w.wire("WV~T~1~"), 1, "and the King's removal")
		for _, m in ipairs(w.sent) do eq(m.dist, "CHANNEL"); assert(not m.text:find("Warsong", 1, true), "never where") end
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

test("wanted native autoadd: own fatal recap adds a Horde killer this client proves (a unit, its recent sighting or his GUID's race), with bounds and removal respected", function()
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
		-- (1.2.3: a reviewer takes an abusive entry off, and what it counted stops counting with it:
		-- before, a Watch moderator's removal left his bounty standing.)
		w.authority(c.me, "king"); assert(W.RemoveTarget(nil, guid)); w.authorities[c.Fold(c.me)] = nil
		w.advance(); row.timestamp = w.epoch; w.handlers.PLAYER_DEAD()
		eq(W.Target(nil, guid).active, false); eq(W.Target(nil, guid).current, 0, "removal is never undone by capture, nor counts")
		local function Refused(id, faction)
			w.advance(); row.timestamp, row.sourceGUID = w.epoch, id
			w.units.target = { name = "Unverified-Realm", guid = id, faction = faction }
			w.handlers.PLAYER_DEAD(); eq(W.Target(nil, id), nil)
		end
		Refused("Player-1-EF000010", nil)
		Refused("Player-1-EF000011", "Alliance")
		Refused("Pet-1-00000012", "Horde")
		-- (1.2.3, changed on purpose: a full list never refuses a Horde killer, and the entry taken off
		-- takes no place on it. Before, the one taken off filled a list of one and this killer was
		-- refused, "full", as every new one was once 200 open bounties or removals filled it.)
		W.MAX_TARGETS = 1
		w.advance(); row.timestamp, row.sourceGUID = w.epoch, "Player-1-EF000013"
		w.units.target = { name = "Roomy Horde-Realm", guid = "Player-1-EF000013", faction = "Horde" }
		w.handlers.PLAYER_DEAD()
		eq(assert(W.Target(nil, "Player-1-EF000013"), "on the list of one").current, 1)
		eq(W.Target(nil, guid).active, false, "the one taken off is still kept off, apart")
		W.MAX_TARGETS = 200
		local oldFaction = UnitFactionGroup
		UnitFactionGroup = function() error("unit faction unavailable") end
		Refused("Player-1-EF000014", "Horde")
		UnitFactionGroup = oldFaction
		row.overkill = -1; Refused("Player-1-EF000015", "Horde")
		eq(#W.Targets(), 2, "rejected rows create no targets")
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
		w.handlers.PLAYER_DEAD(); eq(W.Target(nil, row.sourceGUID), nil, "expired faction knowledge, and no race to prove it, cannot auto-add")
		-- (1.2.3) No unit at all: the game's lookup of his GUID, a race only the Horde plays.
		w.hordePlayer("Unseen Horde-Realm", "Player-1-EF000018", "Tauren")
		w.advance(); row.sourceGUID, row.sourceName, row.timestamp = "Player-1-EF000018", "Unseen-Realm", w.epoch
		w.handlers.PLAYER_DEAD()
		eq(assert(W.Target(nil, "Player-1-EF000018")).name, "Unseen Horde-Realm")
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
		-- (1.2.3, changed on purpose: the one death counted went to every member at once, under the
		-- full name the listing learned; nothing else left this client.)
		local wire = w.wire("WK~")
		eq(#wire, 1, "the one death counted, shared"); eq(#w.sent, 1)
		-- (1.2.3, changed on purpose, Daniel's bounty: an own row goes as WK~2, what it is worth after the
		-- GUIDs: the member's office and level, the Horde player's level.)
		assert(wire[1]:find("^WK~2~.*~S~1%.ef000091~1%.aa000001~M~1~0~Named Horde%-Realm$"), wire[1])
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

test("wanted native named listing: a pinned GUID is never replaced by a different observed killer, who enters under his own GUID", function()
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
		eq(W.Target(nil, pinned).guid, pinned, "a matching name cannot replace its pinned identity")
		eq(W.Target(nil, pinned).current, 0, "nor count against it")
		-- (1.2.3, changed on purpose: his GUID is the identity, a name only a label. Before, an entry
		-- whose name was pinned to another GUID (here a typed one) kept this Horde killer off for good
		-- ("identity"), and a forged shared row could pin any name so. He is another character: he
		-- enters by himself, and his name finds the GUID this client saw under it.)
		eq(W.Target(nil, other).current, 1, "the killer this client saw enters under his own GUID")
		eq(W.Target(name).guid, other)
		eq(#W.Targets(), 2)
		eq(#w.ns.rdb.wanted.evidence, 1)
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

-- (1.2.3, changed on purpose: the C_DeathInfo fallback is gone. Forever's C_DeathInfo has no recap
-- reader (its DeathInfoDocumentation.lua), and the shape this test once fed it was no client's: it
-- described a reader the client lacks. C_DeathRecap, as Forever's own death dialog reads it, is
-- the only one.)
test("wanted PLAYER_DEAD: only Forever's C_DeathRecap is read (HasRecapEvents, then GetRecapEvents, no ID); C_DeathInfo never, and a failing reader is contained", function()
	WithWanted(function(w, W, c)
		local targetGuid = "Player-1-EF000001"
		assert(w.add("Reaper-Realm", targetGuid))
		assert(type(w.handlers.PLAYER_DEAD) == "function", "the handler is registered")
		local infoCalls = 0
		local function Counted() infoCalls = infoCalls + 1 return w.forever("Reaper-Realm", targetGuid) end
		C_DeathInfo = { GetCorpseMapPosition = function() end, GetDeathReleasePosition = function() end,
			GetGraveyardsForMap = function() return {} end, GetSelfResurrectOptions = function() return {} end,
			UseSelfResurrectOption = function() end, GetDeathRecapEvents = Counted, GetDeathRecap = Counted }
		local recapCalls = 0
		C_DeathRecap = { GetRecapEvents = function()
			recapCalls = recapCalls + 1
			return w.forever("Reaper-Realm", targetGuid)
		end }
		w.dead = true
		w.handlers.PLAYER_DEAD()
		eq(W.Target("Reaper-Realm").current, 0, "no HasRecapEvents: the recap is not read")
		eq(recapCalls, 0); eq(infoCalls, 0, "C_DeathInfo is never read")
		C_DeathRecap.HasRecapEvents = function() error("recap reader failed") end
		w.handlers.PLAYER_DEAD()
		eq(W.Target("Reaper-Realm").current, 0, "a reader that throws changes nothing")
		C_DeathRecap.HasRecapEvents = function() return true end
		C_DeathRecap.GetRecapEvents = function() error("recap rows failed") end
		w.handlers.PLAYER_DEAD()
		eq(W.Target("Reaper-Realm").current, 0)
		local rows = w.forever("Reaper-Realm", targetGuid)
		C_DeathRecap.GetRecapEvents = function() recapCalls = recapCalls + 1 return rows end
		w.dead = false; w.handlers.PLAYER_DEAD()
		eq(W.Target("Reaper-Realm").current, 0, "alive: nothing")
		w.dead = true; w.handlers.PLAYER_DEAD()
		eq(W.Target("Reaper-Realm").current, 1)
		w.advance(); w.handlers.PLAYER_DEAD()
		eq(W.Target("Reaper-Realm").current, 1, "the same recap read at the next death is no new death")
		eq(infoCalls, 0, "C_DeathInfo never read, whatever it offers")
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

-- (1.2.3: no Add, no Send evidence, no review: rows count as they come. A member's buttons: Sightings
-- to while his sightings are on. A reviewer's: Frames (the top three he signs: Publish, Revoke), and
-- on an entry Take off and Void, whose word goes to every client.)
test("wanted controls: Frames (Publish, Revoke), Take off, Void and Sightings to are buttons and dialogs over the real paths; no Add, Send evidence or review", function()
	WithWanted(function(w, W, c)
		local observer = w.participant("ControlsSlayer-Realm", "Player-1-CF000003")
		c.me, w.units.player.name, w.units.player.guid = observer, observer, "Player-1-CF000003"
		local reviewer = w.authority("Reviewer-Realm", "council")
		local target, targetGuid = "Controls-Realm", "Player-1-CF000001"
		w.manager = false
		eq(Shown(W), "", "a member: nothing to press while his sightings are off")
		w.die(w.forever(target, targetGuid, { at = w.epoch }))
		eq(#w.dialogs, 0)
		w.hordePlayer(target, targetGuid)
		w.advance(W.DEATH_WINDOW + 1)
		w.die(w.forever(target, targetGuid))
		eq(W.Target(target).current, 1, "his own death counted, with no button")
		w.advance()
		assert(w.handlers.PARTY_KILL(w.units.player.guid, targetGuid))
		-- (1.2.3, changed on purpose, Daniel's revenge: he killed the very Horde player who killed
		-- him, so his kill pays his death's point and 100 more.)
		eq(W.Rankings().all[1].points, 1 + W.Bounty.SCORE.REVENGE, "and his own kill paid it, his revenge with it")
		eq(Shown(W), "", "nothing to send, nothing to review")
		-- (1.2.3, changed on purpose, Daniel's bounty: an own row goes as WK~2, what it is worth after the
		-- GUIDs: the member's office and level, the Horde player's level.)
		eq(#w.wire("WK~2~"), 2, "both went to every member by themselves")
		for _, gone in ipairs({ "OLYMPUS_WANTED_ADD", "OLYMPUS_WANTED_SEND", "OLYMPUS_WANTED_REVIEW", "OLYMPUS_WANTED_WITHDRAW" }) do
			eq(StaticPopupDialogs[gone], nil, gone .. " is gone")
		end

		-- Sightings to: the one reviewer his sightings are whispered to.
		c.db.wantedSightings = true
		eq(Shown(W), "WANTED_REVIEWER_BTN")
		Press(W, "WANTED_REVIEWER_BTN")
		eq(w.dialogs[#w.dialogs].which, "OLYMPUS_WANTED_REVIEWER")
		local dialog = StaticPopupDialogs.OLYMPUS_WANTED_REVIEWER
		local box = Box("old text")
		dialog.OnShow({ editBox = box })
		eq(box.text, "", "nobody chosen yet")
		box.text = "Nobody"
		dialog.OnAccept({ editBox = box })
		eq(w.prints[#w.prints], ns.L.WANTED_ACTION_FAILED:format("reviewer"), "only a reviewer")
		box.text = "Reviewer"
		dialog.OnAccept({ editBox = box })
		eq(c.rdb.wanted.reviewer, reviewer); eq(w.prints[#w.prints], ns.L.WANTED_REVIEWER_SET:format("Reviewer"))
		eq(table.concat(W.SightingRecipients(), ","), "", "until his client says he takes them")
		dialog.OnShow({ editBox = box }); eq(box.text, "Reviewer", "prefilled with the one chosen")
		box.text = "  "
		dialog.OnAccept({ editBox = box })
		eq(c.rdb.wanted.reviewer, nil); eq(w.prints[#w.prints], ns.L.WANTED_REVIEWER_NONE)
		c.db.wantedSightings = false

		-- The reviewer's Frames page: the top three of his own board, nothing waiting.
		c.me = reviewer
		eq(Shown(W), "WANTED_REVIEW_BTN")
		Press(W, "WANTED_REVIEW_BTN")
		eq(W.PageId(), "review")
		eq(Shown(W), "WANTED_BACK_BTN,WANTED_PUBLISH_BTN,WANTED_REVOKE_BTN")
		local lines, title, about = W.Build()
		eq(title, ns.L.WANTED_REVIEW_TITLE); eq(about, ns.L.WANTED_REVIEW_ABOUT)
		local all = {}
		for _, line in ipairs(lines) do all[#all + 1] = line.text end
		all = table.concat(all, "\n")
		assert(all:find("ControlsSlayer", 1, true), all)
		Press(W, "WANTED_PUBLISH_BTN")
		local d = w.dialogs[#w.dialogs]
		eq(d.which, "OLYMPUS_WANTED_PUBLISH")
		assert(d.a:find("ControlsSlayer", 1, true), "the dialog names what will be signed")
		StaticPopupDialogs.OLYMPUS_WANTED_PUBLISH.OnAccept({})
		local published = w.sent[#w.sent]
		eq(published.dist, "CHANNEL"); assert(published.text:find("^WY~2~"))
		-- (1.2.3: his 101 points, his revenge's with his death's point: above.)
		assert(published.text:find("1.cf000003:" .. (1 + W.Bounty.SCORE.REVENGE) .. ":1:", 1, true), "his board's slayer, by GUID")
		eq(w.prints[#w.prints], ns.L.WANTED_PUBLISHED)
		eq(W.GlobalBorder(nil, "Player-1-CF000003"), "wanted-slayer-1")
		Press(W, "WANTED_REVOKE_BTN")
		eq(w.dialogs[#w.dialogs].which, "OLYMPUS_WANTED_REVOKE")
		StaticPopupDialogs.OLYMPUS_WANTED_REVOKE.OnAccept({})
		assert(w.sent[#w.sent].text:find("~%-~"), "an empty top three")
		eq(W.GlobalBorder(nil, "Player-1-CF000003"), nil)
		Press(W, "WANTED_BACK_BTN")

		-- On an entry: Void a row, then Take him off; each word to every client.
		assert(W.OpenTarget(target))
		eq(Shown(W), "WANTED_BACK_BTN,WANTED_REMOVE_BTN")
		lines = W.Build()
		local claimRow
		-- (1.2.3: the claim paid his revenge too, above.)
		local claimPoints = ns.L.WANTED_CLAIM_POINTS:format(1 + W.Bounty.SCORE.REVENGE)
		for _, line in ipairs(lines) do if line.text == c.DisplayName(observer) and line.right == claimPoints then claimRow = line end end
		assert(claimRow and claimRow.onClick, "a reviewer can void a live row (the closed cycle's claim)")
		claimRow.onClick()
		d = w.dialogs[#w.dialogs]
		eq(d.which, "OLYMPUS_WANTED_CORRECT")
		StaticPopupDialogs.OLYMPUS_WANTED_CORRECT.OnAccept({ editBox = Box("staged kill") }, d.data)
		eq(W.Stats().corrected, 1)
		eq(#W.Target(target).claims, 0, "the voided claim no longer closes the cycle"); eq(W.Target(target).current, 1)
		eq(#W.Rankings().all, 0)
		local void = w.wire("WV~V~1~")
		eq(#void, 1); assert(void[1]:find("~ControlsSlayer%-Realm~%x+~%d+$"), void[1])
		Press(W, "WANTED_REMOVE_BTN")
		d = w.dialogs[#w.dialogs]
		eq(d.which, "OLYMPUS_WANTED_REMOVE"); eq(d.a, c.DisplayName(target))
		StaticPopupDialogs.OLYMPUS_WANTED_REMOVE.OnAccept({}, d.data)
		eq(W.Target(target).active, false); eq(W.Target(target).current, 0, "nothing of his counts")
		eq(#W.Targets(true), 0)
		local off = w.wire("WV~T~1~")
		eq(#off, 1); assert(off[1]:find("~1%.cf000001~%d+$"), off[1])
		eq(W.PageId(), "list", "his page closed: he is off the list")
		assert(W.OpenTarget(target), "his page still opens, as an audit")
		eq(Shown(W), "WANTED_BACK_BTN", "off already: nothing more to take off")
		-- A member reads only.
		c.me = observer
		lines = W.Build()
		assert(table.concat(Headers(lines), "\n"):find(ns.L.WANTED_REMOVED, 1, true) or lines[2].right:find(ns.L.WANTED_REMOVED, 1, true))
		for _, line in ipairs(lines) do assert(not line.onClick or line.text == ns.L.WANTED_BACK or line.text:find(ns.L.WANTED_BACK, 1, true), "a member only reads") end
		eq(select(2, W.RemoveTarget(target)), "access"); eq(select(2, W.Correct("anything")), "access")
	end)
end)

-- Add target's box took the keyboard itself (eb:SetFocus) where Send and Correct went through
-- ns.Focus: with the gamepad UI, a focus taken from the chat's box runs the game's gamepad code
-- from ours (Dialog.lua). The style and the focused box as Forever's client reports them. (1.2.3:
-- Add target and Send evidence are gone; Sightings to's box is new, and through ns.Focus too.)
test("wanted dialogs: with the gamepad UI, no Most Wanted box takes the keyboard from the chat's, Sightings to's neither", function()
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
				if dialog and dialog.hasEditBox then
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
			eq(table.concat(boxes, ","), "OLYMPUS_WANTED_CORRECT,OLYMPUS_WANTED_REVIEWER")
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
		-- (1.2.3: the review's and Send evidence's lines are gone, with their buttons; every line
		-- Wanted.lua names is checked in both languages by the 1.2.3 locale test below.)
		for _, gone in ipairs({ "WANTED_SEND_BTN", "WANTED_SEND_PROMPT", "WANTED_SENT", "WANTED_SEND_WAIT", "WANTED_REVIEW_BTN_COUNT",
			"WANTED_PENDING", "WANTED_ACCEPTED", "WANTED_CONFLICT", "WANTED_REVIEW_PROMPT", "WANTED_ACCEPT_BTN", "WANTED_REJECT_BTN",
			"WANTED_LATER_BTN", "WANTED_WITHDRAW_PROMPT", "WANTED_BOUNTY_LINE", "WANTED_CLAIM_LINE", "WANTED_OLDER_ACCEPTED",
			"WANTED_ADD_PROMPT", "WANTED_ADD_BTN" }) do
			eq(rawget(ns.L, gone), nil, gone); eq(rawget(pt.L, gone), nil, "pt-BR " .. gone)
		end
		for _, key in ipairs({ "WANTED_LOCAL_ALL", "WANTED_MONTHLY", "WANTED_AUTHORITY_OFF", "WANTED_SIGNED", "WANTED_SIGNED_EMPTY",
			"WANTED_SIGNED_HELD", "WANTED_REVIEW_BTN", "WANTED_REVIEWER_BTN", "WANTED_REVIEWER_PROMPT",
			"WANTED_PUBLISH_BTN", "WANTED_REVOKE_BTN", "WANTED_REVIEW_TITLE", "WANTED_REVIEW_ABOUT",
			"WANTED_TO_PUBLISH", "WANTED_NO_GUID", "WANTED_PUBLISH_PROMPT", "WANTED_REVOKE_PROMPT", "WANTED_CORRECT_PROMPT",
			"WANTED_LAST_PUBLISHED", "WANTED_NOT_PUBLISHED", "WANTED_STATUS_KEY", "HELP_WANTED" }) do
			assert(type(ns.L[key]) == "string" and ns.L[key] ~= "", key)
			assert(ptBlock:find("L." .. key .. " = ", 1, true), key .. " in pt-BR")
			assert(type(pt.L[key]) == "string" and pt.L[key] ~= "", "pt-BR " .. key)
		end
		eq(pt.L.WANTED_LOCAL_ALL, "Slayers vistos por este cliente · histórico total")
	end)
end)

---------------------------------------------------------------------------
-- 1.2.3 (Daniel: "that list should never have existed"): Wanted fills itself. A Horde player who
-- kills a member, or is killed by one, enters from that member's own observed death or killing
-- blow, and the row counts at once on every member's client (WK), with no list, Send or review.
-- These fail on 1.2.2 (e04dd45): the kill was refused as "unlisted", the death needed a Horde unit
-- on screen, and nothing ever left the client by itself.
---------------------------------------------------------------------------

-- The realm group and faction's digest, as Wanted.lua's Scope makes it.
local function ScopeOf(c)
	local raw = c.Sign.SHA256(tostring(c.group or c.realm) .. "|" .. tostring(c.faction))
	return (raw:gsub(".", function(ch) return ("%02x"):format(ch:byte()) end)):sub(1, 16)
end

test("wanted 1.2.3 (no list): an ordinary member's own killing blow on a Horde player nobody listed makes his entry at once, the claim recorded (1.2.4: on the Most Wanted list only once he kills a member), and the row goes to the Olympus channel by itself", function()
	WithWanted(function(w, W, c)
		w.manager = false -- an ordinary member: nobody listed anyone, and there is no store yet
		eq(c.rdb.wanted, nil)
		local horde = "Player-1-0D000001"
		w.hordePlayer("Fresh Horde-Realm", horde) -- the game's lookup of his GUID: an Orc
		-- Forever's payload: the two GUIDs, nothing else; no unit, nameplate or target of his.
		local ok, e = w.handlers.PARTY_KILL(w.units.player.guid, horde)
		assert(ok, tostring(e))
		eq(e.action, "claim"); eq(e.kind, "PARTY_KILL"); eq(e.points, 0, "no bounty was open on him: a claim of nothing")
		local t = assert(W.Target(nil, horde), "his entry, by himself")
		eq(t.active, true); eq(t.name, "Fresh Horde-Realm"); eq(#t.claims, 1); eq(t.cycle, 2); eq(t.source, "PARTY_KILL")
		eq(#W.Targets(true), 1)
		-- (1.2.4, the author's report: 0 points and 0 kills, he killed none of ours: not wanted.)
		eq(#W.Targets("listed"), 0)
		-- The row on the channel at once: no Send, no review.
		eq(#w.sent, 1); eq(w.sent[1].dist, "CHANNEL")
		local wire = w.sent[1].text
		-- (1.2.3, changed on purpose, Daniel's bounty: an own row goes as WK~2, what it is worth after the
		-- GUIDs: the member's office and level, the Horde player's level.)
		assert(wire:find("^WK~2~" .. ScopeOf(c) .. "~Olympus II~%x+~%d+~%d+~P~1%.0d000001~1%.aa000001~M~1~0~Fresh Horde%-Realm$"), wire)
		assert(not wire:find("Warsong", 1, true), "never where it happened")
		-- The same death read again is not counted twice, nor a second entry.
		eq(w.handlers.PARTY_KILL(w.units.player.guid, horde), false)
		eq(#W.Targets(), 1); eq(#w.sent, 1)
		-- A bounty open on him (a member's death) is paid by the next own killing blow.
		w.advance(); assert(w.kill(3001, "Fresh Horde-Realm", horde, w.olympian("Victim-Realm"), "Player-1-AC000001"))
		eq(#W.Targets("listed"), 1, "he killed a member: wanted")
		w.advance(); local paid, claim = w.handlers.PARTY_KILL(w.units.player.guid, horde)
		assert(paid); eq(claim.points, 1)
		eq(W.Rankings().all[1].guid, w.units.player.guid); eq(W.Rankings().all[1].points, 1)
	end)
end)

test("wanted 1.2.3 (no list): an ordinary member's own death to a Horde player he never targeted (nameplates off) puts him on Most Wanted with a bounty, from Forever's recap and his GUID's race", function()
	WithWanted(function(w, W, c)
		w.manager = false
		local horde = "Player-1-0D000002"
		w.hordePlayer("Given Ganker-Realm", horde) -- his full name, as the game's lookup gives it
		local retries = {}
		-- (1.2.4, changed on purpose: the death's toast hides itself on a timer of its own, "wanted
		-- toast"; only the recap's retries are counted here, as before.)
		c.After = function(_, label, fn) if label == "wanted death recap" then retries[#retries + 1] = fn end end
		eq(w.units.target, nil, "no target"); eq(w.units.nameplate1, nil, "no nameplate")
		w.die(w.forever("Given-Realm", horde)) -- (Forever's recap: "Given-Realm", no surname)
		local t = assert(W.Target(nil, horde), "no unit, nameplate, target or listing was needed")
		eq(t.current, 1); eq(t.name, "Given Ganker-Realm", "the game's own name for his GUID")
		eq(t.victims[1].name, c.me); eq(t.source, "SELF_DEATH")
		eq(#retries, 0, "read on PLAYER_DEAD itself: no retry")
		eq(#w.sent, 1)
		-- (1.2.3, changed on purpose, Daniel's bounty: an own row goes as WK~2, what it is worth after the
		-- GUIDs: the member's office and level, the Horde player's level.)
		assert(w.sent[1].text:find("^WK~2~.*~S~1%.0d000002~1%.aa000001~M~1~0~Given Ganker%-Realm$"), w.sent[1].text)
		-- Read again (the next PLAYER_DEAD, a retry): the same death once.
		w.handlers.PLAYER_DEAD(); eq(W.Target(nil, horde).current, 1); eq(#w.sent, 1)
		-- The recap's own name where the game's lookup gives none.
		local other = "Player-1-0D000003"
		w.horde[other] = { race = "Troll" }
		w.advance(W.DEATH_WINDOW + 1)
		w.die(w.forever("Shadow-Realm", other))
		eq(W.Target(nil, other).name, "Shadow-Realm"); eq(W.Target(nil, other).current, 1)
		-- The recap not ready on PLAYER_DEAD: one of the bounded retries reads it.
		local third = "Player-1-0D000004"
		w.hordePlayer("Late Recap-Realm", third)
		w.advance(W.DEATH_WINDOW + 1)
		local rows = w.forever("Late-Realm", third)
		local ready = false
		C_DeathRecap = { HasRecapEvents = function() return ready end, GetRecapEvents = function() return rows end }
		retries = {}
		w.dead = true; w.handlers.PLAYER_DEAD()
		eq(W.Target(nil, third), nil); eq(#retries, 3, "0.3, 1 and 2 seconds later")
		ready = true
		for _, retry in ipairs(retries) do retry() end
		eq(W.Target(nil, third).current, 1, "counted once, by the first retry that read it")
	end)
end)

test("wanted 1.2.3: the Horde faction is proven, never guessed: an Alliance race (a free-for-all zone), a race of both factions, a unit shown as no Horde player, a pet, a creature, an instance, a hidden payload or another player's killing blow records nothing", function()
	WithWanted(function(w, W, c)
		w.manager = false
		local me = w.units.player.guid
		local function Kill(guid) w.advance(); return select(2, w.handlers.PARTY_KILL(me, guid)) end
		local function Death(guid, name) w.advance(W.DEATH_WINDOW + 1); w.die(w.forever(name or "Killer-Realm", guid)); return W.Target(nil, guid) end
		w.horde["Player-1-0E000001"] = { name = "Freeforall-Realm", race = "Human" }
		eq(Kill("Player-1-0E000001"), "faction", "an Alliance player killed in a free-for-all zone")
		eq(Death("Player-1-0E000001"), nil, "nor his killing blow on us")
		w.horde["Player-1-0E000002"] = { name = "Skyborn-Realm", race = "Skyborn" }
		eq(Kill("Player-1-0E000002"), "faction", "a race of both factions proves nothing by itself")
		-- His Horde unit on screen proves it.
		w.units.nameplate3 = { name = "Skyborn-Realm", guid = "Player-1-0E000002", faction = "Horde" }
		w.advance(); assert(w.handlers.PARTY_KILL(me, "Player-1-0E000002"), "a Horde unit of his, now")
		w.units.nameplate3 = nil
		-- A unit of his shown as no Horde player wins over his race.
		w.hordePlayer("Charmed-Realm", "Player-1-0E000003")
		w.units.target = { name = "Charmed-Realm", guid = "Player-1-0E000003", faction = "Alliance" }
		eq(Kill("Player-1-0E000003"), "faction"); eq(Death("Player-1-0E000003"), nil)
		w.units.target = nil
		-- A pet, a creature: no player GUID.
		eq(Kill("Pet-0-4170-1-123-416-0300ABCDEF"), "identities"); eq(Death("Pet-0-4170-1-123-416-0300ABCDEF"), nil)
		eq(Kill("Creature-0-4170-1-123-12345-0000ABCDEF"), "identities")
		-- Another player's killing blow (a party member's, or a pet's GUID as the attacker).
		w.hordePlayer("Partykill-Realm", "Player-1-0E000004")
		w.advance(); eq(select(2, w.handlers.PARTY_KILL("Player-1-AA00FFFF", "Player-1-0E000004")), "attacker")
		w.advance(); eq(select(2, w.handlers.PARTY_KILL("Pet-0-4170-1-123-416-0300ABCDEF", "Player-1-0E000004")), "identities")
		-- A battleground or an arena (an instance): nothing.
		w.inside = true
		eq(Kill("Player-1-0E000004"), "instance"); eq(Death("Player-1-0E000004"), nil)
		w.inside = false
		-- Hidden by the game (an unfinished PvP match).
		local secret = {}
		issecretvalue = function(v) return rawequal(v, secret) end
		eq(Kill(secret), "secret")
		local rows = w.forever("Partykill-Realm", "Player-1-0E000004"); rows[1].sourceGUID = secret
		w.advance(W.DEATH_WINDOW + 1); w.die(rows)
		issecretvalue = nil
		eq(W.Target(nil, "Player-1-0E000004"), nil)
		-- Of the Horde ourselves: no Horde Most Wanted here.
		c.faction = "Horde"
		eq(Kill("Player-1-0E000004"), "faction")
		c.faction = "Alliance"
		eq(#W.Targets(), 1, "only the Skyborn whose Horde unit was seen")
		eq(#w.wire("WK~"), 1)
	end)
end)

test("wanted 1.2.3 intake: a shared row counts only from a verified member, about his own death or kill, of this realm group and faction, fresh, once, within the per-member and per-Horde-player limits; nothing malformed or forged is kept", function()
	WithWanted(function(w, W, c)
		local H = assert(w.commHandlers.WK, "the WK handler")
		local scope = ScopeOf(c)
		local sender = w.participant("Sharer-Realm", "Player-1-CC000041")
		local n = 0
		local function Row(o)
			o = o or {}
			n = n + 1
			return table.concat({ "WK", 1, o.scope or scope, o.guild or "Olympus II", o.digest or ("%016x"):format(0xa000 + n),
				o.at or w.epoch, o.month or W.MonthNow(), o.kind or "S", o.horde or ("1.0f%06x"):format(0x41000 + n),
				o.own or "1.cc000041", o.name or ("Shared" .. n .. "-Realm") }, "~")
		end
		local function Why(from, text, dist) return select(2, H(dist or "CHANNEL", from, text)) end
		-- A verified member's own death, counted at once.
		local ok, e = H("CHANNEL", sender, Row({ horde = "1.0f000041", name = "Shared Horde-Realm" }))
		assert(ok, tostring(e))
		local t = assert(W.Target(nil, "Player-1-0F000041"))
		eq(t.current, 1); eq(t.victims[1].name, sender); eq(t.victims[1].guid, "Player-1-CC000041", "his GUID, proven his here")
		eq(t.source, "shared"); eq(t.addedBy, sender); eq(e.peer, true); eq(e.from, sender)
		local held = #W.Targets()
		-- Kept nowhere:
		eq(Why(sender, Row(), "WHISPER"), "lane", "the channel only")
		eq(Why(sender, Row() .. "~extra"), "shape")
		eq(Why(sender, Row({ kind = "X" })), "shape")
		eq(Why(sender, Row({ horde = "Pet-0-1-2-3-4-5" })), "shape")
		eq(Why(sender, Row({ digest = "00a1" })), "shape")
		eq(Why(sender, Row({ own = "-" })), "shape", "a member's own row names his own GUID")
		eq(Why(sender, Row({ scope = "ffffffffffffffff" })), "scope", "another realm group or faction")
		eq(Why(sender, Row({ at = w.epoch - W.SHARE_AGE - 1 })), "stale")
		eq(Why(sender, Row({ at = w.epoch + W.GLOBAL_SKEW + 60 })), "stale")
		eq(Why(sender, Row({ month = W.MonthNow() - W.MAX_MONTHS })), "shape")
		w.strangers[c.Fold("Outsider-Realm")] = true
		-- (1.2.4: the three refusals "olympus" was have their own reasons: "stranger", "hidden",
		-- "olympian"; tests/wanted-guilds.lua has them with the real Channels, Data and Roster.)
		eq(Why("Outsider-Realm", Row({ own = "1.dd000041" })), "stranger", "a stranger's row")
		c.Moderation.Hides = function(name) return c.Fold(name) == c.Fold(sender) end
		eq(Why(sender, Row()), "hidden", "a sender the moderators hide")
		c.Moderation.Hides = nil
		-- The Olympian side is the sender: a GUID this client knows as someone else's is refused, one
		-- it cannot name is kept off the row (his name alone, as the server stamps it).
		w.participant("Someoneelse-Realm", "Player-1-CC000042")
		eq(Why(sender, Row({ own = "1.cc000042" })), "not-own")
		eq(Why(sender, Row({ own = "1.aa000001" })), "not-own", "our own player's GUID is never another's")
		-- (His next death: DEATH_WINDOW later, or it would be a second killer for the same one.)
		w.advance(W.DEATH_WINDOW + 1)
		ok, e = H("CHANNEL", sender, Row({ own = "1.cc000043", horde = "1.0f000043", name = "Unbound-Realm" }))
		assert(ok, tostring(e))
		eq(e.victimName, sender); eq(e.victimGuid, nil, "a GUID this client cannot prove his is not taken")
		-- The Horde side as the sender proved it, unless this client sees otherwise.
		w.olympian("Olympian Too-Realm")
		eq(Why(sender, Row({ name = "Olympian Too-Realm" })), "olympian", "an Olympian is never a Horde entry")
		w.horde["Player-1-0F000044"] = { name = "Ally-Realm", race = "Human" }
		eq(Why(sender, Row({ horde = "1.0f000044", name = "Ally-Realm" })), "faction", "an Alliance race on this client")
		w.units.target = { name = "Seen-Realm", guid = "Player-1-0F000045", faction = "Alliance" }
		eq(Why(sender, Row({ horde = "1.0f000045", name = "Seen-Realm" })), "faction", "a unit of his shown as no Horde player")
		w.units.target = nil
		eq(#W.Targets(), held + 1, "only the one with his name alone was added")
		-- Once: the same row again, and a copy of the same death a second later (another digest, across
		-- a 3-second bucket) pay one bounty point.
		w.advance(W.DEATH_WINDOW + 1)
		local first = Row({ horde = "1.0f000046", name = "Twice-Realm", digest = "00000000000000f1" })
		assert(H("CHANNEL", sender, first))
		eq(Why(sender, first), "replay")
		w.advance(1)
		eq(Why(sender, Row({ horde = "1.0f000046", name = "Twice-Realm", digest = "00000000000000f2", at = w.epoch })), "replay")
		eq(W.Target(nil, "Player-1-0F000046").current, 1, "one death, one bounty point")
		-- SHARE_RATE_MAX a window from one member; then his next is refused, another member's is not.
		w.advance(W.SHARE_RATE_WINDOW)
		-- (His killing blows on as many Horde players: one death each, no conflict between them.)
		for _ = 1, W.SHARE_RATE_MAX do assert(H("CHANNEL", sender, Row({ kind = "P" }))) end
		eq(Why(sender, Row({ kind = "P" })), "rate")
		local other = w.participant("Othersharer-Realm", "Player-1-CC000047")
		assert(H("CHANNEL", other, Row({ own = "1.cc000047" })), "another member still reaches this client")
		-- And SHARE_DAY_MAX a day from one member, whatever the minute.
		w.advance(W.SHARE_RATE_WINDOW)
		local dayMax = W.SHARE_DAY_MAX
		W.SHARE_DAY_MAX = W.SHARE_RATE_MAX + 1
		eq(Why(sender, Row({ kind = "P" })), "rate", "his day is full")
		W.SHARE_DAY_MAX = dayMax
		-- A death before what this client folded into its base can no longer take its place.
		c.rdb.wanted.foldedAt = w.epoch - 100
		eq(Why(other, Row({ own = "1.cc000047", kind = "P", at = w.epoch - 200 })), "late")
		c.rdb.wanted.foldedAt = nil
		-- SHARE_TARGET_MAX about one Horde player from everyone.
		w.advance(W.SHARE_TARGET_WINDOW)
		W.SHARE_TARGET_MAX = 2
		for i = 1, 2 do
			w.advance(W.DEATH_WINDOW + 1)
			assert(H("CHANNEL", w.participant("Flooded" .. i .. "-Realm", ("Player-1-CC0000%d0"):format(i)),
				Row({ horde = "1.0f000048", name = "Flooded-Realm", own = ("1.cc0000%d0"):format(i) })))
		end
		w.advance(W.DEATH_WINDOW + 1)
		eq(Why(w.participant("Flooded3-Realm", "Player-1-CC000030"), Row({ horde = "1.0f000048", name = "Flooded-Realm", own = "1.cc000030" })), "target")
		eq(W.Target(nil, "Player-1-0F000048").current, 2)
		-- A relay only from a reviewer; our own row coming back in one is ours already.
		local relay = ("WK~R~1~%s~%s~1~%016x~%d~%d~P~1.0f000049~1.cc000041~Relayed-Realm"):format(scope, sender, 0xbeef, w.epoch, W.MonthNow())
		eq(Why(other, relay), "authority")
		local king = w.authority("Kingly-Realm", "king")
		local mine = ("WK~R~1~%s~%s~1~%016x~%d~%d~P~1.0f000049~1.aa000001~Relayed-Realm"):format(scope, c.me, 0xbeef, w.epoch, W.MonthNow())
		eq(Why(king, mine), "own")
		assert(H("CHANNEL", king, relay), "a reviewer's relay of a member's row")
		eq(W.Target(nil, "Player-1-0F000049").claims[1].slayer, sender)
		-- A Horde client keeps none of it.
		c.faction = "Horde"
		eq(Why(sender, Row({ scope = ScopeOf(c) })), "faction")
	end)
end)

test("wanted 1.2.3 marks: a reviewer's removal reaches every client (what the Horde player counted stops counting, and a later row does not bring him back, even where he had no entry), his void too; nobody else's word counts", function()
	WithWanted(function(w, W, c)
		local K, V = w.commHandlers.WK, w.commHandlers.WV
		local scope = ScopeOf(c)
		local sender = w.participant("Victimized-Realm", "Player-1-CC000051")
		local slayer = w.participant("Avenger-Realm", "Player-1-CC000052")
		local function Row(kind, horde, own, digest, at)
			return table.concat({ "WK", 1, scope, "Olympus II", digest, at or w.epoch, W.MonthNow(), kind, horde, own,
				"Abuser" .. horde:sub(-2) .. "-Realm" }, "~")
		end
		assert(K("CHANNEL", sender, Row("S", "1.0f000051", "1.cc000051", "00000000000000c1")))
		w.advance(30)
		assert(K("CHANNEL", slayer, Row("P", "1.0f000051", "1.cc000052", "00000000000000c2")))
		eq(W.Rankings().all[1].points, 1)
		local function Mark(from, body) return V("CHANNEL", from, body) end
		local off = ("WV~T~1~%s~1.0f000051~%d"):format(scope, w.epoch)
		eq(select(2, Mark("Plain-Realm", off)), "authority", "a member's word takes nobody off")
		eq(select(2, V("WHISPER", "Plain-Realm", off)), "lane")
		local king = w.authority("Kingly-Realm", "king")
		eq(select(2, Mark(king, off:gsub(scope, "ffffffffffffffff"))), "scope")
		eq(select(2, Mark(king, ("WV~T~1~%s~1.0f000051~%d"):format(scope, w.epoch - W.SHARE_AGE - 1))), "stale")
		eq(select(2, Mark(king, off .. "~x")), "shape")
		assert(Mark(king, off))
		local t = W.Target(nil, "Player-1-0F000051")
		eq(t.active, false); eq(t.removedBy, king); eq(t.current, 0); eq(#t.claims, 0)
		eq(#W.Rankings().all, 0, "the points paid for him stop counting")
		eq(#W.Targets(true), 0)
		eq(select(2, Mark(king, off)), "held")
		w.advance(60)
		eq(select(2, K("CHANNEL", sender, Row("S", "1.0f000051", "1.cc000051", "00000000000000c3"))), "removed", "he does not come back")
		-- One this client never had: kept off all the same.
		assert(Mark(king, ("WV~T~1~%s~1.0f000052~%d"):format(scope, w.epoch)))
		eq(W.Target(nil, "Player-1-0F000052").active, false)
		w.advance(6)
		eq(select(2, K("CHANNEL", sender, Row("S", "1.0f000052", "1.cc000051", "00000000000000c4"))), "removed")
		-- A void: one member's row, by its sender and digest; a copy heard later is refused.
		w.advance(6)
		assert(K("CHANNEL", sender, Row("S", "1.0f000053", "1.cc000051", "00000000000000c5")))
		eq(W.Target(nil, "Player-1-0F000053").current, 1)
		local void = ("WV~V~1~%s~%s~00000000000000c5~%d"):format(scope, sender, w.epoch)
		eq(select(2, Mark("Plain-Realm", void)), "authority")
		assert(Mark(w.authority("Councillor-Realm", "council"), void))
		eq(W.Target(nil, "Player-1-0F000053").current, 0, "voided")
		eq(select(2, K("CHANNEL", sender, Row("S", "1.0f000053", "1.cc000051", "00000000000000c5"))), "void")
		-- A void heard before its row: the row is refused when it comes.
		assert(Mark(king, ("WV~V~1~%s~%s~00000000000000c6~%d"):format(scope, sender, w.epoch)))
		eq(select(2, K("CHANNEL", sender, Row("S", "1.0f000054", "1.cc000051", "00000000000000c6"))), "void")
		-- Saved: after a reload the removal and the void still hold.
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted; assert(W.Load())
		eq(W.Target(nil, "Player-1-0F000051").active, false); eq(#W.Rankings().all, 0)
		eq(select(2, w.commHandlers.WK("CHANNEL", sender, Row("S", "1.0f000054", "1.cc000051", "00000000000000c6"))), "void")
	end)
end)

-- (1.2.3, changed on purpose: a full Most Wanted never refuses a Horde killer. Before, it dropped
-- only an entry with nothing open and nothing paid, and kept every one taken off in its places: a
-- list of open bounties, claims and removals refused every new one ("no entry left to drop:
-- refused"), so that nothing counted any more.)
test("wanted 1.2.3: a full Most Wanted never refuses a Horde killer: the least active entry makes room (nothing open and nothing paid first, then the oldest), its paid points stay with their Slayer, and an entry taken off takes no place", function()
	WithWanted(function(w, W, c)
		W.MAX_TARGETS = 4
		local me = w.units.player.guid
		local function Horde(i) return w.hordePlayer("Full" .. i .. "-Realm", ("Player-1-0F0001%02d"):format(i)), ("Player-1-0F0001%02d"):format(i) end
		local function Death(i) w.advance(W.DEATH_WINDOW + 1); local name, guid = Horde(i); w.die(w.forever(name, guid)); return guid end
		local _, nothing = Horde(1) -- killed for no bounty: nothing open, nothing paid
		assert(w.handlers.PARTY_KILL(me, nothing))
		local open = Death(2) -- killed us: an open bounty
		local paid = Death(3) -- killed us, then we killed him: a claim that paid
		w.advance(W.DEATH_WINDOW + 1)
		assert(w.handlers.PARTY_KILL(me, paid))
		w.advance(W.DEATH_WINDOW + 1)
		local _, abusive = Horde(4) -- taken off by the King
		assert(w.handlers.PARTY_KILL(me, abusive))
		w.authority(c.me, "king"); assert(W.RemoveTarget(nil, abusive)); w.authorities[c.Fold(c.me)] = nil
		eq(#W.Targets(true), 3); eq(#W.Targets(), 4)
		local fifth = Death(5)
		eq(W.Target(nil, fifth).current, 1)
		assert(W.Target(nil, nothing), "the one taken off holds no place: nobody had to go")
		eq(#W.Targets(true), 4)
		local sixth = Death(6)
		eq(W.Target(nil, sixth).current, 1, "a full list made room")
		eq(W.Target(nil, nothing), nil, "the one with nothing open and nothing paid went first")
		-- (1.2.3 repair, changed on purpose: a kill with no bounty open pays the Horde player's level
		-- now, so "nothing paid" no longer tells a spare entry; one with nothing open and no grudge
		-- goes before an open bounty, whose deaths would be lost. Before, the oldest of all went
		-- first, here the open bounty, older than the claim.)
		local seventh = Death(7)
		eq(W.Target(nil, seventh).current, 1, "a list of bounties and claims alone: still room")
		eq(W.Target(nil, paid), nil, "nothing open and no grudge: the claim that paid went before the older open bounty")
		assert(W.Target(nil, open), "the open bounty stays")
		local eighth = Death(8)
		eq(W.Target(nil, eighth).current, 1)
		eq(W.Target(nil, open), nil, "then the oldest open bounty")
		-- (1.2.3, changed on purpose, Daniel's revenge: "paid" killed us and we killed him: our death's
		-- point and 100 more.)
		eq(W.Rankings().all[1].points, 1 + W.Bounty.SCORE.REVENGE, "what his claim paid still counts")
		eq(#W.Targets(true), 4)
		eq(W.Target(nil, abusive).active, false, "the one taken off is still kept off")
		w.advance(W.DEATH_WINDOW + 1)
		eq(select(2, w.handlers.PARTY_KILL(me, abusive)), "removed")
		-- After a reload, the totals built again from the saved data: the same.
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted; assert(W.Load())
		eq(W.Rankings().all[1].points, 1 + W.Bounty.SCORE.REVENGE, "the revenge too")
		eq(#W.Targets(true), 4); eq(W.Target(nil, abusive).active, false)
		eq(W.ShareState().why.full, nil, "nothing was refused for want of room")
	end)
end)

test("wanted 1.2.3 regression: with the real cap, the 201st Horde killer of 200 unanswered ones still enters and counts, a removal frees a place, and a reviewer's removal of one this client never had is kept", function()
	WithWanted(function(w, W, c)
		eq(W.MAX_TARGETS, 200, "the shipped cap")
		w.manager = false
		local me = w.units.player.guid
		local function Killer(i)
			local guid = ("Player-1-0E%06X"):format(0x100000 + i)
			w.hordePlayer("Ganker" .. i .. "-Realm", guid)
			w.advance(W.DEATH_WINDOW + 1)
			w.die(w.forever("Ganker" .. i .. "-Realm", guid))
			return guid
		end
		local first
		for i = 1, 200 do local guid = Killer(i); first = first or guid end
		eq(#W.Targets(true), 200, "200 open bounties: nobody killed back")
		local new = Killer(201)
		local t = assert(W.Target(nil, new), "the 201st killer enters (was refused: full)")
		eq(t.current, 1); eq(#W.Targets(true), 200)
		eq(W.Target(nil, first), nil, "the least active one made room")
		eq(W.ShareState().log[#W.ShareState().log].ok, true, "counted, and noted so in /oly wanted status")
		-- The King takes ten off: they are kept off apart, and ten places are free.
		w.authority(c.me, "king")
		local off = {}
		for i = 2, 11 do off[#off + 1] = ("Player-1-0E%06X"):format(0x100000 + i); assert(W.RemoveTarget(nil, off[#off])) end
		w.authorities[c.Fold(c.me)] = nil
		eq(#W.Targets(true), 190); eq(#W.Targets(), 200)
		local later = Killer(202)
		eq(W.Target(nil, later).current, 1); eq(#W.Targets(true), 191, "a free place, nobody dropped")
		for _, guid in ipairs(off) do eq(W.Target(nil, guid).active, false) end
		-- A reviewer's removal of a Horde player this client never had: kept off, and no place taken.
		local king = w.authority("Kingly-Realm", "king")
		assert(w.commHandlers.WV("CHANNEL", king, ("WV~T~1~%s~1.0e2fffff~%d"):format(ScopeOf(c), w.epoch)))
		eq(W.Target(nil, "Player-1-0E2FFFFF").active, false); eq(#W.Targets(true), 191)
		eq(W.ShareState().why.full, nil)
	end)
end)

test("wanted 1.2.3 regression: one forged row naming a Horde player under a made-up GUID never keeps the real one off, taken off or not; his name is the game's, and a row naming a GUID the game knows by another name is refused", function()
	WithWanted(function(w, W, c)
		w.manager = false
		local K = w.commHandlers.WK
		local scope = ScopeOf(c)
		local forger = w.participant("Forger-Realm", "Player-1-CC000081")
		local function Row(horde, name, digest)
			return table.concat({ "WK", 1, scope, "Olympus II", digest, w.epoch, W.MonthNow(), "S", horde, "1.cc000081", name }, "~")
		end
		-- One verified member's row (a /run SendAddonMessage will do): his "death" to "Grom-Realm"
		-- under a made-up GUID, which no client's game can check.
		assert(K("CHANNEL", forger, Row("1.0d0000aa", "Grom-Realm", "00000000000000e1")))
		eq(W.Target(nil, "Player-1-0D0000AA").name, "Grom-Realm")
		w.authority(c.me, "king"); assert(W.RemoveTarget(nil, "Player-1-0D0000AA")); w.authorities[c.Fold(c.me)] = nil
		-- The real Grom (an Orc, by the game's lookup of his own GUID) kills our member, then dies to him.
		local real = "Player-1-0D0000BB"
		w.hordePlayer("Grom-Realm", real)
		w.advance(W.DEATH_WINDOW + 1)
		w.die(w.forever("Grom-Realm", real))
		local t = assert(W.Target(nil, real), "his own death counts (was refused: identity)")
		eq(t.current, 1); eq(t.name, "Grom-Realm")
		w.advance(W.DEATH_WINDOW + 1)
		local ok, e = w.handlers.PARTY_KILL(w.units.player.guid, real)
		-- (1.2.3, changed on purpose, Daniel's revenge: he killed us first, so our kill pays 100 more.)
		assert(ok, tostring(e)); eq(e.points, 1 + W.Bounty.SCORE.REVENGE, "and our killing blow on him claims it (was refused: identity)")
		eq(W.Target("Grom-Realm").guid, real, "his name finds him, not the made-up GUID taken off")
		eq(W.Target(nil, "Player-1-0D0000AA").active, false, "which stays off")
		-- Not taken off either: a forged namesake on the list keeps nobody off.
		w.advance(W.DEATH_WINDOW + 1)
		assert(K("CHANNEL", forger, Row("1.0d0000cc", "Thrall-Realm", "00000000000000e2")))
		w.hordePlayer("Thrall-Realm", "Player-1-0D0000DD")
		w.advance(W.DEATH_WINDOW + 1)
		w.die(w.forever("Thrall-Realm", "Player-1-0D0000DD"))
		eq(W.Target(nil, "Player-1-0D0000DD").current, 1)
		eq(W.Target("Thrall-Realm").guid, "Player-1-0D0000DD", "the GUID this client's game proved holds his name")
		-- A row that gives a GUID the game knows another character's name: refused, nothing renamed.
		w.advance(W.DEATH_WINDOW + 1)
		eq(select(2, K("CHANNEL", forger, Row("1.0d0000bb", "Daniel-Realm", "00000000000000e3"))), "identity")
		eq(W.Target(nil, real).name, "Grom-Realm"); eq(W.Target(nil, real).current, 0)
		-- One the game names as the row does (his given name alone, as Forever's recap writes it): his,
		-- under the game's whole name.
		w.hordePlayer("Garrosh Hellscream-Realm", "Player-1-0D0000EE")
		w.advance(W.DEATH_WINDOW + 1)
		assert(K("CHANNEL", forger, Row("1.0d0000ee", "Garrosh-Realm", "00000000000000e4")))
		eq(W.Target(nil, "Player-1-0D0000EE").name, "Garrosh Hellscream-Realm")
		-- A name a row wrote while the game could not check it gives way to the game's, once it can.
		w.advance(W.DEATH_WINDOW + 1)
		assert(K("CHANNEL", forger, Row("1.0d000102", "Wrongname-Realm", "00000000000000e5")))
		w.hordePlayer("Truename-Realm", "Player-1-0D000102")
		w.advance(W.DEATH_WINDOW + 1)
		w.die(w.forever("Truename-Realm", "Player-1-0D000102"))
		local renamed = W.Target(nil, "Player-1-0D000102")
		eq(renamed.name, "Truename-Realm"); eq(renamed.current, 2)
		eq(W.Target("Wrongname-Realm"), nil, "the row's name does not stay")
		-- A forged entry under the name of a member this client knows by his name alone (another
		-- guild's, heard in a reviewer's relay) never stands for him: his own row counts.
		w.advance(W.DEATH_WINDOW + 1)
		assert(K("CHANNEL", forger, Row("1.0d000103", "Faraway-Realm", "00000000000000e6")))
		local king = w.authority("Kingly-Realm", "king")
		w.advance(W.DEATH_WINDOW + 1)
		local relay = ("WK~R~1~%s~Faraway-Realm~0~%016x~%d~%d~S~1.0d000104~-~Victor-Realm"):format(scope, 0xe7, w.epoch, W.MonthNow())
		local relayed, row = K("CHANNEL", king, relay)
		assert(relayed, tostring(row)); eq(row.victimName, "Faraway-Realm")
		eq(W.Target(nil, "Player-1-0D000104").current, 1, "(was refused: ambiguous)")
		-- And after a reload: his name still finds the real one.
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted; assert(W.Load())
		eq(W.Target("Grom-Realm").guid, real); eq(W.Target("Thrall-Realm").guid, "Player-1-0D0000DD")
	end)
end)

test("wanted 1.2.3 regression: a reviewer's Take off cancels the points the entry paid after this client folded them (a checkpoint), as on a client that never folded, and leaves every other Slayer's", function()
	WithWanted(function(w, W, c)
		W.MAX_EVIDENCE = 4
		local scope = ScopeOf(c)
		local victim = w.participant("Victim-Realm", "Player-1-CC000071")
		local forger = w.participant("Forger-Realm", "Player-1-CC000072")
		local honest = w.participant("Honest-Realm", "Player-1-CC000073")
		-- Another member's client, which never folds (MAX_EVIDENCE as shipped), hears every word too.
		local other = w.publisher().Wanted
		local rows, n = {}, 0
		local function Say(from, own, kind, horde, name)
			n = n + 1
			local text = table.concat({ "WK", 1, scope, "Olympus II", ("%016x"):format(0xd000 + n), w.epoch, W.MonthNow(), kind, horde, own, name }, "~")
			rows[#rows + 1] = { from, text }
			local ok, e = w.commHandlers.WK("CHANNEL", from, text)
			assert(ok, tostring(e))
			w.advance(W.DEATH_WINDOW + 1)
		end
		-- Three made-up deaths to a made-up Horde GUID (a bounty of 3), and a claim of it: 3 points.
		for _ = 1, 3 do Say(victim, "1.cc000071", "S", "1.0f0000a1", "Farmed-Realm") end
		Say(forger, "1.cc000072", "P", "1.0f0000a1", "Farmed-Realm")
		eq(W.Rankings().all[1].name, forger); eq(W.Rankings().all[1].points, 3)
		-- An honest bounty and claim on another, and ordinary rows: the ledger folds.
		Say(victim, "1.cc000071", "S", "1.0f0000a2", "Real-Realm")
		Say(honest, "1.cc000073", "P", "1.0f0000a2", "Real-Realm")
		for i = 3, 5 do Say(victim, "1.cc000071", "S", ("1.0f0000a%d"):format(i), "Other" .. i .. "-Realm") end
		assert(W.Stats().checkpointed >= 2, "both claims folded into the base")
		eq(#c.rdb.wanted.evidence, 1)
		for _, r in ipairs(rows) do assert(other.HandleShared("CHANNEL", r[1], r[2])) end
		-- The King's word: the made-up entry off, on both clients.
		local king = w.authority("Kingly-Realm", "king")
		local off = ("WV~T~1~%s~1.0f0000a1~%d"):format(scope, w.epoch)
		assert(w.commHandlers.WV("CHANNEL", king, off)); assert(other.HandleMark("CHANNEL", king, off))
		eq(W.Target(nil, "Player-1-0F0000A1").active, false)
		for _, client in ipairs({ W, other }) do
			local all = client.Rankings().all
			eq(#all, 1, "the forger's 3 points went with the entry (were kept after a checkpoint)")
			eq(all[1].name, honest); eq(all[1].points, 1, "the honest claim stays")
			eq(client.Rankings().month[1].points, 1)
			local signable = client.SignableRankings()
			eq(#signable, 1); eq(signable[1].guid, "Player-1-CC000073", "nor in the top three a reviewer signs")
		end
		-- And after a reload, the totals built again from the base.
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted; assert(W.Load())
		eq(#W.Rankings().all, 1); eq(W.Rankings().all[1].points, 1)
	end)
end)

test("wanted 1.2.3: the targets 1.2.2 saved keep working: a name-only listing learns the GUID from our own killing blow (no second entry), a listed GUID counts our own death, and 1.2.2's review ledger is dropped", function()
	WithWanted(function(w, W, c)
		-- A 1.2.2 store: a moderator's name-only listing, a listing by GUID, a reviewer's ledger and his
		-- evidence's send times (the review is gone).
		local key = "n:" .. c.Fold("Old Horde-Realm")
		c.rdb.wanted = { version = W.VERSION, group = c.group, faction = c.faction, seq = 0,
			targets = { [key] = { key = key, name = "Old Horde-Realm", active = true, addedAt = w.epoch - 86400, addedBy = "Mod-Realm",
				source = "manual", current = 0, lifetimeKills = 0, cycle = 1, victims = {}, claims = {} },
				["g:Player-1-0F000201"] = { key = "g:Player-1-0F000201", name = "Guided-Realm", guid = "Player-1-0F000201", active = true,
				addedAt = w.epoch - 86400, source = "manual", current = 0, lifetimeKills = 0, cycle = 1, victims = {}, claims = {} } },
			aliases = {}, slayers = {}, slayerAliases = {}, baseSlayers = {}, evidence = {}, seen = {}, seenOrder = {}, recent = {}, audit = {},
			ledger = { accepted = {}, base = { targets = {}, slayers = {}, deaths = {} }, folded = 0 }, sentAt = { ["reviewer-realm"] = w.epoch - 10 },
			reviewer = "Reviewer-Realm" }
		assert(W.Load())
		eq(c.rdb.wanted.ledger, nil); eq(c.rdb.wanted.sentAt, nil)
		eq(c.rdb.wanted.reviewer, "Reviewer-Realm", "the sightings reviewer chosen before stays")
		eq(#W.Targets(), 2)
		w.hordePlayer("Old Horde-Realm", "Player-1-0F000202")
		local ok, e = w.handlers.PARTY_KILL(w.units.player.guid, "Player-1-0F000202")
		assert(ok, tostring(e))
		eq(#W.Targets(), 2, "the listing is upgraded, never duplicated")
		eq(W.Target("Old Horde-Realm").guid, "Player-1-0F000202"); eq(#W.Target("Old Horde-Realm").claims, 1)
		eq(W.Target("Old Horde-Realm").source, "manual")
		w.advance(W.DEATH_WINDOW + 1)
		w.die(w.forever("Guided-Realm", "Player-1-0F000201"))
		eq(W.Target(nil, "Player-1-0F000201").current, 1, "a listed GUID is a Horde player already")
	end)
end)

test("wanted 1.2.3: the top three a reviewer signs is his own Slayers board, by verified GUID; a slayer known by his name alone is left out and named on the frames page", function()
	WithWanted(function(w, W, c)
		local scope = ScopeOf(c)
		local K = w.commHandlers.WK
		local bound = w.participant("Bound-Realm", "Player-1-CC000061")
		w.olympian("Unbound-Realm") -- a verified member whose GUID this client cannot name
		local function Pair(victim, own, slayer, slayerOwn, horde, base)
			local prey = "Prey" .. horde:sub(-2) .. "-Realm"
			assert(K("CHANNEL", victim, table.concat({ "WK", 1, scope, "Olympus II", ("%016x"):format(base), w.epoch, W.MonthNow(), "S", horde, own, prey }, "~")))
			w.advance(10)
			assert(K("CHANNEL", slayer, table.concat({ "WK", 1, scope, "Olympus II", ("%016x"):format(base + 1), w.epoch, W.MonthNow(), "P", horde, slayerOwn, prey }, "~")))
			w.advance(10)
		end
		local victim = w.participant("Prey Victim-Realm", "Player-1-CC000063")
		Pair(victim, "1.cc000063", "Unbound-Realm", "1.cc000062", "1.0f000061", 0x100)
		w.advance(W.DEATH_WINDOW + 1)
		Pair(victim, "1.cc000063", "Unbound-Realm", "1.cc000062", "1.0f000061", 0x200)
		w.advance(W.DEATH_WINDOW + 1)
		Pair(victim, "1.cc000063", bound, "1.cc000061", "1.0f000062", 0x300)
		local all = W.Rankings().all
		eq(all[1].name, "Unbound-Realm"); eq(all[1].guid, nil); eq(all[1].points, 2)
		eq(all[2].guid, "Player-1-CC000061")
		local rows = W.SignableRankings()
		eq(#rows, 1); eq(rows[1].guid, "Player-1-CC000061", "a name alone is never signed for a frame")
		c.me = w.authority("Signer-Realm", "council")
		assert(W.OpenReview())
		local text = {}
		for _, line in ipairs(W.Build()) do text[#text + 1] = line.text end
		text = table.concat(text, "\n")
		assert(text:find(ns.L.WANTED_NO_GUID:format("Unbound"), 1, true), text)
		assert(W.PublishGlobal())
		assert(w.sent[#w.sent].text:find("~1.cc000061:1:1:", 1, true), w.sent[#w.sent].text)
	end)
end)

test("wanted 1.2.3: our own row the channel did not take goes again after login, then on its beat, until it is taken", function()
	WithWanted(function(w, W, c)
		local timers = {}
		c.After = function(seconds, label, fn) timers[#timers + 1] = { seconds = seconds, label = label, fn = fn } end
		w.hordePlayer("Resent-Realm", "Player-1-0F000071")
		w.die(w.forever("Resent-Realm", "Player-1-0F000071"))
		-- (1.2.3, changed on purpose, Daniel's bounty: an own row goes as WK~2, what it is worth after the
		-- GUIDs: the member's office and level, the Horde player's level.)
		eq(#w.wire("WK~2~"), 1)
		w.sent[1].done(false, "moved") -- the channel did not take it (changed, or not joined yet)
		local function Fire(label)
			for i, t in ipairs(timers) do if t.label == label then table.remove(timers, i) t.fn() return t.seconds end end
		end
		assert(W.Load())
		eq(Fire("wanted resend"), W.SHARE_RESEND_FIRST)
		eq(#w.wire("WK~2~"), 2, "sent again"); eq(w.sent[#w.sent].text, w.sent[1].text, "the same row")
		w.sent[#w.sent].done(true)
		eq(Fire("wanted resend"), W.SHARE_RESEND_EVERY)
		eq(#w.wire("WK~2~"), 2, "taken: no more")
		eq(c.rdb.wanted.evidence[1].shared, true, "saved as shared")
	end)
end)

test("wanted 1.2.3: /oly wanted status opens a copy window with this session's captures, what was shared and heard, and every refusal's reason; a death read again is one line", function()
	WithWanted(function(w, W, c)
		local shown
		c.UI.ShowCopy = function(title, text, action, opts) shown = { title = title, text = text, action = action, opts = opts } return true end
		local me = w.units.player.guid
		w.hordePlayer("Status Horde-Realm", "Player-1-0F000081")
		w.advance(); w.handlers.PARTY_KILL("Player-1-AA00FFFF", "Player-1-0F000081") -- a party member's killing blow
		w.advance(); w.handlers.PARTY_KILL(me, "Creature-0-1-2-3-4-0000ABCDEF") -- a creature: not noted
		w.advance(W.DEATH_WINDOW + 1); w.die(w.forever("Ally-Realm", "Player-1-0F000082")) -- nobody the game knows: faction
		local retries = {}
		c.After = function(_, _, fn) retries[#retries + 1] = fn end
		w.advance(W.DEATH_WINDOW + 1)
		local rows = w.forever("Status-Realm", "Player-1-0F000081")
		local ready = false
		C_DeathRecap = { HasRecapEvents = function() return ready end, GetRecapEvents = function() return rows end }
		w.dead = true; w.handlers.PLAYER_DEAD()
		ready = true
		for _, retry in ipairs(retries) do retry() end
		local scope = ScopeOf(c)
		local sender = w.participant("Sharer-Realm", "Player-1-CC000081")
		w.commHandlers.WK("CHANNEL", sender, table.concat({ "WK", 1, scope, "Olympus II", "00000000000000d1", w.epoch, W.MonthNow(), "S",
			"1.0f000083", "1.cc000081", "Heard Horde-Realm" }, "~"))
		w.commHandlers.WK("CHANNEL", "Stranger-Realm", "WK~1~garbage")
		assert(W.Slash("status"))
		eq(shown.title, ns.L.WANTED_STATUS_TITLE); eq(shown.opts.key, "wanted"); eq(shown.action.label, ns.L.WANTED_STATUS_REFRESH)
		local text = shown.text
		assert(text:find(ns.L.WANTED_STATUS_REFUSED:format("attacker 1, faction 1, shape 1"), 1, true), text)
		-- (1.2.4, changed on purpose: the store's line also counts the entries off the list, 0 points
		-- and 0 kills: here none, both Horde players killed a member.)
		assert(text:find(ns.L.WANTED_STATUS_STORE:format("RealmGroup", "Alliance", 2, 0, 0, 2, 0, ns.L.WANTED_STATUS_YES), 1, true), text)
		assert(text:find(ns.L.WANTED_STATUS_KILL .. "  Status Horde-Realm  " .. ns.L.WANTED_STATUS_REFUSAL:format("attacker"), 1, true), text)
		-- (1.2.3, changed on purpose: a death's line says the points it added, Daniel's bounty.)
		assert(text:find(ns.L.WANTED_STATUS_DEATH .. "  Status Horde-Realm  " .. ns.L.WANTED_STATUS_BOUNTY:format(1), 1, true), text)
		assert(text:find(ns.L.WANTED_STATUS_DEATH .. "  Ally-Realm  " .. ns.L.WANTED_STATUS_REFUSAL:format("faction"), 1, true), text)
		-- (1.2.4, changed on purpose: a member's row names the guild it speaks for after its sender.)
		assert(text:find(ns.L.WANTED_STATUS_HEARD .. "  Heard Horde-Realm · Sharer-Realm <Olympus II>  " .. ns.L.WANTED_STATUS_BOUNTY:format(1), 1, true), text)
		local _, recaps = text:gsub("  " .. ns.L.WANTED_STATUS_DEATH .. "  ", "")
		eq(recaps, 2, "the death read on PLAYER_DEAD and again by its retry is one line, its last answer")
		assert(not text:find("Creature", 1, true), "a creature killed is no line")
		assert(text:find(ns.L.WANTED_STATUS_KEY, 1, true))
		assert(not text:find("Warsong", 1, true), "never where")
		-- Its Refresh reads it again; without the copy window, the lines go to the chat.
		shown.action.fn(); assert(shown.text:find(ns.L.WANTED_STATUS_LAST, 1, true))
		c.UI.ShowCopy = nil
		W.Slash("")
		local printed = table.concat(w.prints, "\n")
		assert(printed:find(ns.L.WANTED_STATUS_LAST, 1, true), printed)
		eq(W.Slash("nonsense"), false); eq(w.prints[#w.prints], ns.L.WANTED_STATUS_USAGE)
	end)
	-- /oly wanted reaches Wanted.lua (the harness's own namespace runs Core's stand-in: a client
	-- updated without a restart is told to restart), and /oly help lists it.
	local savedPrint, printed = ns.Print, nil
	ns.Print = function(message) printed = message end
	local ok, err = pcall(SlashCmdList.OLYMPUS, "wanted status")
	ns.Print = savedPrint
	if not ok then error(err, 0) end
	eq(ns.Wanted.missing, true); eq(printed, ns.L.RESTART_NEEDED)
	local lines, savedOut = {}, print
	print = function(s) lines[#lines + 1] = tostring(s) end
	SlashCmdList.OLYMPUS("help")
	print = savedOut
	assert(table.concat(lines, "\n"):find(ns.L.HELP_WANTED, 1, true), "in /oly help")
end)

-- L's missing keys show the key itself on screen: every line Wanted.lua names is in English and
-- pt-BR, with the same format arguments, and none holds a character the game's fonts lack.
test("wanted 1.2.3 locales: every line Wanted.lua names, and its buttons' labels and tips, are in English and pt-BR with the same arguments", function()
	local f = assert(io.open(ROOT .. "Olympus/Wanted.lua"))
	local src = f:read("*a")
	f:close()
	local pt, savedLocale = {}, GetLocale
	GetLocale = function() return "ptBR" end
	local ok, err = pcall(function()
		assert(loadfile(ROOT .. "Olympus/Locales.lua"))("Olympus", pt)
		assert(loadfile(ROOT .. "Olympus/Locales/RankingRulesText.lua"))("Olympus", pt)
	end)
	GetLocale = savedLocale
	if not ok then error(err, 0) end
	local keys, n = {}, 0
	for key in src:gmatch("L%.([A-Z][A-Z0-9_]+)") do keys[key] = true end
	for key in src:gmatch('{ "(WANTED_[A-Z_]+_BTN)"') do keys[key] = true end
	for _, key in ipairs({ "TAB_WANTED", "CONSENT_WANTED_SIGHTINGS", "CONSENT_WANTED_SIGHTINGS_TEXT", "HELP_WANTED", "HELP_SIGHTINGS",
		"WANTED_REMOVE_BTN_TIP", "WANTED_REVIEW_BTN_TIP", "WANTED_REVIEWER_BTN_TIP", "WANTED_PUBLISH_BTN_TIP", "WANTED_REVOKE_BTN_TIP" }) do keys[key] = true end
	local function Args(s) local out = {} for a in s:gmatch("%%%a") do out[#out + 1] = a end return table.concat(out) end
	for key in pairs(keys) do
		n = n + 1
		local en, br = rawget(ns.L, key), rawget(pt.L, key)
		assert(type(en) == "string" and en ~= "", "English " .. key)
		assert(type(br) == "string" and br ~= "", "Portuguese " .. key)
		eq(Args(br), Args(en), key .. ": format arguments")
		for _, text in ipairs({ en, br }) do
			assert(not text:find("\226\128[\147\148\166]") and not text:find("\226\134"), key .. ": a dash, an ellipsis or an arrow the fonts lack")
		end
	end
	assert(n > 80, n)
	assert(keys.WANTED_STATUS_KEY and keys.WANTED_REVIEWER_BTN and keys.WANTED_REMOVE_BTN, "the new lines are read")
end)

---------------------------------------------------------------------------
-- A small world: several clients in one Lua state, each with its own namespace, saved data
-- (db, rdb), units and Wanted.lua; real Ed25519 keys and signatures, each check queued as the
-- game's job queue runs it later; a Comm that routes as the game does (a whisper to the client
-- it names, the channel to every other online client, each stamped with its sender's name); and
-- timers on the world's clock. A reload or a login is a fresh namespace over the same saved data
-- (the old one's timers never fire again); an offline client hears nothing. 1.2.3: each client's
-- own death recap (cl.recap, Forever's C_DeathRecap) and its guild (cl.guild: its roster knows its
-- guildmates only; world.verified names the members of other guilds whose rank a client can
-- verify, as the census does officers'); world.horde, the Horde players the game's lookup knows.
---------------------------------------------------------------------------

local function WithWorld(fn)
	local globals = { "UnitGUID", "UnitIsPlayer", "UnitFactionGroup", "GetGuildInfo", "GetRealZoneText",
		"UnitIsDeadOrGhost", "C_DateAndTime", "C_DeathInfo", "C_DeathRecap", "GetFileIDFromPath",
		"C_ChatInfo", "GetTime", "GetChannelName", "GetPlayerInfoByGUID", "UnitTokenFromGUID", "IsInInstance", "UnitLevel",
		"GetMaxPlayerLevel", "InCombatLockdown" }
	local saved = {}
	for _, name in ipairs(globals) do saved[name] = _G[name] end
	local dialogs = {}
	for _, which in ipairs(DIALOGS) do dialogs[which] = StaticPopupDialogs[which] end
	local realEd = ns.Ed25519
	local world = { epoch = 1800000000, year = 2026, month = 10, clients = {}, queue = {}, jobs = {}, timers = {},
		authorities = {}, olympians = {}, log = {}, serial = 0, horde = {}, verified = {}, hidden = {} }
	local current
	local ok, err = pcall(function()
		local function U(unit) return current and current.units[unit] end
		UnitGUID = function(unit) return U(unit) and U(unit).guid end
		UnitIsPlayer = function(unit) return U(unit) ~= nil end
		UnitFactionGroup = function(unit) return U(unit) and U(unit).faction end
		UnitIsDeadOrGhost = function() return current and current.dead == true end
		GetGuildInfo = function(unit)
			local u = U(unit or "player")
			if u then return u.guild, u.rank and "Rank" .. u.rank or nil, u.rank end
		end
		-- (1.2.3: each client's units' levels, -1 for the game's "??"; a client's own player is level 1
		-- unless a test gives another.)
		UnitLevel = function(unit) return U(unit) and U(unit).level end
		GetMaxPlayerLevel = function() return 60 end
		InCombatLockdown = function() return false end
		GetRealZoneText = function() return "Arathi Highlands" end
		C_DateAndTime = { GetCurrentCalendarTime = function() return { year = world.year, month = world.month } end }
		C_DeathInfo = nil
		C_DeathRecap = { HasRecapEvents = function() return current ~= nil and current.recap ~= nil end,
			GetRecapEvents = function() return current and current.recap or {} end }
		IsInInstance = function() return false, "none" end
		-- (1.2.4: as Forever has it, UnitDocumentation.lua: a token only for a unit of the client the
		-- game runs. Before, none at all, a client without the call.)
		UnitTokenFromGUID = function(guid)
			for unit, u in pairs(current and current.units or {}) do if u.guid == guid then return unit end end
			return nil
		end
		GetPlayerInfoByGUID = function(guid)
			for _, cl in ipairs(world.clients) do
				if cl.guid == guid then return "Warrior", "WARRIOR", "Human", "Human", 2, ns.ShortName(cl.name), "Realm" end
			end
			if world.horde[guid] then return "Warrior", "WARRIOR", "Orc", "Orc", 2, ns.ShortName(world.horde[guid]), "Realm" end
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
			c.Moderation = { CanIssue = function() return cl.manager == true end, Blocks = function() return false end,
				Hides = function(sender) return world.hidden[Fold(sender)] end }
			local function Role(name) return (cl.authorities or world.authorities)[Fold(name)] end
			c.Workshop = { IsAuthor = function() return false end, IsAuthorName = function(name) return Role(name) == "author" end }
			c.IsKingCharacter = function(name) return Role(name) == "king" end
			c.IsHighCouncillor = function(name) return Role(name) == "council" end
			c.Ed25519 = { ToB64 = realEd.ToB64, FromB64 = realEd.FromB64, ValidPublicKey = realEd.ValidPublicKey,
				Verify = realEd.Verify, Busy = function() return 0 end,
				Run = function(job, done) world.jobs[#world.jobs + 1] = { cl = cl, owner = c, job = job, done = done } return true end }
			c.Debts = { MyKey = function() return "gk", cl.pk, "fp" end, Sign = function(msg) return realEd.Sign(cl.seed, msg, cl.pk) end,
				B64 = realEd.ToB64, UnB64 = realEd.FromB64,
				-- (The game's lookup of a GUID, as Debts.InfoName wraps it: the clients, and world.horde.)
				InfoName = function(guid)
					for _, o in ipairs(world.clients) do if o.guid == guid then return o.name end end
					return world.horde[guid]
				end }
			c.Comm = { Handle = function(kind, call) cl.handlers[kind] = call end,
				Whisper = function(to, text) world.queue[#world.queue + 1] = { from = cl, to = to, dist = "WHISPER", text = text } return true end,
				Send = function(dist, text, key, _, _, done, options)
					world.queue[#world.queue + 1] = { from = cl, dist = dist, text = text, key = key, done = done, options = options } return true
				end,
				SendChunked = function(text, _, _, done, options)
					world.queue[#world.queue + 1] = { from = cl, dist = "CHANNEL", text = text, done = done, options = options } return true
				end }
			c.UnitFullName = function(unit) return U(unit) and U(unit).name end
			-- (1.2.3: its own guild's roster; a member of another guild is verified only where
			-- world.verified says so, as the census verifies officers.)
			c.Roster = { Fresh = function() return true end,
				RankOf = function(name) return world.olympians[Fold(name)] == (cl.guild or "Olympus II") and 3 or nil end }
			c.Channels = { VerifiedLevel = function(sender, guild)
				local g = world.olympians[Fold(sender)]
				if not g then return 0, false end
				if g == guild and (g == (cl.guild or "Olympus II") or world.verified[Fold(sender)]) then return 1, true end
				return 1, false
			end }
			c.RegisterEvent = function(name, call) cl.events[name] = call end
			c.Fire = function() end
			c.On = function(name, call) cl.listeners[name] = call end
			c.Print = function(message) cl.prints[#cl.prints + 1] = tostring(message) end
			c.Ago = function(at) return tostring(world.epoch - (tonumber(at) or 0)) .. "s" end
			c.ShowDialog = function() return true end
			c.After = function(seconds, _, f) world.timers[#world.timers + 1] = { at = world.epoch + seconds, cl = cl, owner = c, fn = f } end
			c.Every, c.Log = function() end, function() end
			c.SafeCall = function(_, fn, ...) return fn(...) end
			c.UI = { Refresh = function() end, RefreshSoon = function() end,
				ShowCopy = function(title, text, _, opts) cl.copies = cl.copies or {} cl.copies[#cl.copies + 1] = { title = title, text = text, opts = opts } end }
			c.Consent = { Waiting = function() return false end }
			-- (1.2.4: the notices' windows, dialogs and letters, kept on the client across its reloads.)
			NoticeStandIns(c, cl)
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
		function world:Client(name, guid, role, realComm, guild)
			name = ns.FullName(name)
			local seed = ns.Sign.SHA256("test seed " .. name)
			guild = guild or "Olympus II"
			local cl = { name = name, guid = guid, member = true, db = {}, rdb = {}, prints = {}, seed = seed, realComm = realComm, guild = guild,
				pk = realEd.PublicKey(seed), units = { player = { name = name, guid = guid, faction = "Alliance", guild = guild, level = 1 } } }
			world.olympians[Fold(name)] = guild
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
							elseif to.handlers[m.text:sub(1, 2)] then world:As(to, to.handlers[m.text:sub(1, 2)], "WHISPER", m.from.name, m.text) end
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
		-- 1.2.3: the victim's own death to the Horde player (Forever's recap: he was never listed,
		-- never targeted), deaths times, DEATH_WINDOW apart, then the slayer's own killing blow on him
		-- (the native PARTY_KILL); each own row goes to the channel by itself and every client counts
		-- it. No list, no Send, no review. (observer and reviewer: the callers' 1.2.2 arguments, unused.)
		-- (1.2.3: the deaths REPEAT_GAP apart, so that each counts: one member killed by one Horde
		-- player counts once in 10 minutes, Daniel's bounty. Before, DEATH_WINDOW apart.)
		function world:Hunt(_, _, targetName, targetGuid, victim, slayer, deaths)
			world.serial = world.serial + 1
			world.horde[targetGuid] = ns.FullName(targetName)
			for _ = 1, deaths or 1 do
				victim.dead = true
				victim.recap = { { event = "SPELL_DAMAGE", sourceGUID = targetGuid, sourceName = ns.ShortName(targetName) .. "-Realm",
					sourceFlags = 0x548, overkill = 120, timestamp = world.epoch - 0.2 },
					{ event = "SWING_DAMAGE", sourceGUID = targetGuid, sourceName = ns.ShortName(targetName) .. "-Realm",
					sourceFlags = 0x548, overkill = -1, timestamp = world.epoch - 3 } }
				world:As(victim, victim.events.PLAYER_DEAD)
				victim.dead, victim.recap = false, nil
				assert(world:As(victim, victim.W.Target, nil, targetGuid), "the victim's death counted on his client")
				world.epoch = world.epoch + ((deaths or 1) > 1 and victim.W.Bounty.SCORE.REPEAT_GAP or victim.W.DEATH_WINDOW + 1)
			end
			local good, claim = world:As(slayer, slayer.events.PARTY_KILL, slayer.guid, targetGuid)
			assert(good, claim)
			world.epoch = world.epoch + 6
			if victim.realComm or slayer.realComm then world:PumpComm() else world:Deliver() end
			return claim
		end
		fn(world)
	end)
	for _, name in ipairs(globals) do _G[name] = saved[name] end
	for _, which in ipairs(DIALOGS) do StaticPopupDialogs[which] = dialogs[which] end
	if not ok then error(err, 0) end
end

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

test("wanted sanction through real Comm: actual timeout and hold remove councillor publication, removal, relay and queued delivery", function()
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
					-- (1.2.3: no review to deny; a sanctioned councillor takes nothing off and voids nothing.)
					local removed, reason = world:As(council, council.W.RemoveTarget, nil, "Player-1-0B0000AA")
					eq(removed, false); eq(reason, "access", "sanction denies the authority check, not just an unknown entry")
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
		local accepted, why = world:As(late, late.W.HandleGlobalRelay, "CHANNEL", council.name, "W5~2~" .. held)
		eq(accepted, false); eq(why, "replay")
		local fresh = world:Client("Fresh-Realm", "Player-1-0A000004")
		accepted, why = world:As(fresh, fresh.W.HandleGlobalRelay, "CHANNEL", council.name, "W5~2~" .. held)
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
			return world:As(late, late.W.HandleGlobalRelay, "CHANNEL", sender, text or ("W5~2~" .. held))
		end
		local accepted, why = Receive("Ordinary-Realm")
		eq(accepted, false); eq(why, "authority")
		accepted, why = Receive(council.name, "W5~1~" .. held)
		eq(accepted, false); eq(why, "shape")
		accepted, why = world:As(late, late.W.HandleGlobalSnapshot, "CHANNEL", council.name, held)
		eq(accepted, false); eq(why, "authority", "a direct WY does not permit forwarded sender identity")
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

test("wanted world: a published top three (the King's own board, every member's shared kills, no review) reaches every client, outlives the old 30-minute word and survives their reloads", function()
	WithWorld(function(world)
		local king = world:Client("Varrick-Realm", "Player-1-0A000001", "king")
		local alpha = world:Client("Alpha-Realm", "Player-1-0A000002")
		local beta = world:Client("Beta-Realm", "Player-1-0A000003")
		world:Hunt(alpha, king, "Hordeling-Realm", "Player-1-0B000001", beta, alpha)
		-- (1.2.3, changed on purpose: no whisper to a reviewer any more. Each member's own row went to
		-- the channel at once, the Horde player's name with it, never where it happened.)
		local whispers, rows = 0, 0
		for _, m in ipairs(world.log) do
			if m.dist == "WHISPER" then whispers = whispers + 1 end
			if m.text:find("^WK~") then rows = rows + 1 end
			assert(not m.text:find("Arathi", 1, true), "never where it happened")
		end
		eq(whispers, 0); assert(rows >= 2, "the death and the kill, each from its own member")
		local mine = world:As(king, king.W.SignableRankings)
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
		rows = world:As(king, king.W.SignableRankings)
		eq(#rows, 1, "the King's board did not start over"); eq(rows[1].points, 1)
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
		world:Hunt(beta, council, "Raider-Realm", "Player-1-0B000012", alpha, beta, 2)
		assert(world:As(council, council.W.PublishGlobal))
		world:Deliver()
		for _, cl in ipairs({ alpha, beta, king }) do
			eq(world:As(cl, cl.W.GlobalSnapshot).issuer, council.name, cl.name .. " holds the newer word")
			eq(world:Border(cl, beta.guid), "wanted-slayer-1")
			-- (1.2.3, changed on purpose: the councillor's board holds every member's shared kills,
			-- Alpha's too; before, only what was sent to him and he accepted.)
			eq(world:Border(cl, alpha.guid), "wanted-slayer-2", "replaced: the councillor's own board's order")
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
		assert(good and good.text:find("^WY~2~") and goodHeads, "the word Alpha accepted is saved")
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
		local signed = table.concat({ "OLYW2", fields[3], fields[4], fields[5], fields[6], fields[7], fields[8], fields[9] }, "|")
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

-- (1.2.3: no reviewer chooses between two accounts any more. One death has one killer: every client
-- counts the first account of it that it hears, refuses the other as a conflict, and a reviewer can
-- void the one counted when it is the forged one.)
test("wanted world: two members' clients that name themselves the killer of one death: every client counts the first account it hears and refuses the other; a reviewer's void takes the counted one off everywhere", function()
	WithWorld(function(world)
		local king = world:Client("Varrick-Realm", "Player-1-0A000031", "king")
		local alpha = world:Client("Alpha-Realm", "Player-1-0A000032")
		local beta = world:Client("Beta-Realm", "Player-1-0A000033")
		local gamma = world:Client("Gamma-Realm", "Player-1-0A000034")
		local targetName, targetGuid = "Contested-Realm", "Player-1-0B000031"
		world.horde[targetGuid] = targetName
		gamma.dead, gamma.recap = true, { { event = "SPELL_DAMAGE", sourceGUID = targetGuid, sourceName = "Contested-Realm",
			sourceFlags = 0x548, overkill = 40, timestamp = world.epoch } }
		world:As(gamma, gamma.events.PLAYER_DEAD)
		gamma.dead, gamma.recap = false, nil
		world:Deliver()
		world.epoch = world.epoch + 6
		-- The same death of the target, each client naming its own player as the killer (one of
		-- them a modified client: the game names one attacker).
		local claims = {}
		for _, cl in ipairs({ alpha, beta }) do
			local ok, e = world:As(cl, cl.events.PARTY_KILL, cl.guid, targetGuid)
			assert(ok, e)
			claims[#claims + 1] = e
		end
		world:Deliver()
		for _, cl in ipairs({ king, gamma }) do
			local t = world:As(cl, cl.W.Target, nil, targetGuid)
			eq(#t.claims, 1, cl.name .. ": one death, one claim"); eq(t.claims[1].slayer, alpha.name, "the first account heard")
			eq(world:As(cl, cl.W.Rankings).all[1].guid, alpha.guid); eq(#world:As(cl, cl.W.Rankings).all, 1)
		end
		eq(world:As(beta, beta.W.Target, nil, targetGuid).claims[1].slayer, beta.name, "the other client counts its own")
		-- The King voids Alpha's account: on every client.
		local id
		for _, e in ipairs(king.rdb.wanted.evidence) do if e.action == "claim" then id = e.id end end
		assert(world:As(king, king.W.Correct, id, "two killers named"))
		world:Deliver()
		for _, cl in ipairs({ king, gamma, beta }) do
			eq(#world:As(cl, cl.W.Rankings).all, cl == beta and 1 or 0, cl.name)
		end
		eq(world:As(gamma, gamma.W.Target, nil, targetGuid).current, 1, "the bounty is open again")
		eq(#world:As(alpha, alpha.W.Rankings).all, 0, "on Alpha's own client too")
		local copy = { dist = "CHANNEL", text = nil }
		for _, m in ipairs(world.log) do if m.from == alpha and m.text:find("^WK~2~") and m.text:find("~P~") then copy.text = m.text end end
		assert(copy.text, "Alpha's own claim, as it went (1.2.3: WK~2, what it is worth with it)")
		world:As(gamma, gamma.handlers.WK, "CHANNEL", alpha.name, copy.text)
		eq(#world:As(gamma, gamma.W.Rankings).all, 0, "a copy heard later is refused: void")
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
		world:Hunt(beta, council, "Raider-Realm", "Player-1-0B000052", alpha, beta, 2)
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
		world:Hunt(beta, council, "Raider-Realm", "Player-1-0B000062", alpha, beta, 2)
		assert(world:As(council, council.W.PublishGlobal))
		world:Deliver()
		eq(world:As(king, king.W.GlobalSnapshot).issuer, council.name, "the King's client holds the newer word")
		world:Offline(council)

		local function KingSent(from)
			for i = from, #world.log do
				local m = world.log[i]
				-- A catch-up request or an unchanged relay of the newer word is not a repeat
				-- of the old publisher's replaced word.
				if m.from == king and m.dist == "CHANNEL" and (m.text == replacedWord or m.text == "W5~2~" .. replacedWord) then return true end
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

-- 1.2.3: what Daniel's own test will show (two members, the King, a late login): fails on 1.2.2,
-- where the death stayed on the victim's client and the kill was refused as "unlisted".
test("wanted 1.2.3 world: a member's own death to a Horde player nobody listed reaches every member's client at once, another member's killing blow claims it everywhere and scores, and a late login catches up from a reviewer", function()
	WithWorld(function(world)
		local king = world:Client("Varrick-Realm", "Player-1-0A000071", "king")
		local alpha = world:Client("Alpha-Realm", "Player-1-0A000072")
		local beta = world:Client("Beta-Realm", "Player-1-0A000073")
		local late = world:Client("Late-Realm", "Player-1-0A000074")
		world:Offline(late)
		local horde = "Player-1-0B000071"
		world.horde[horde] = "Hordeling-Realm"
		-- Beta dies to him: Forever's recap, no target, no nameplate, no listing anywhere.
		beta.dead, beta.recap = true, { { event = "SPELL_DAMAGE", sourceGUID = horde, sourceName = "Hordeling-Realm", sourceFlags = 0x548,
			overkill = 233, timestamp = world.epoch - 0.2 }, { event = "SWING_DAMAGE", sourceGUID = horde, sourceName = "Hordeling-Realm",
			sourceFlags = 0x548, overkill = -1, timestamp = world.epoch - 2.6 } }
		world:As(beta, beta.events.PLAYER_DEAD)
		beta.dead, beta.recap = false, nil
		world:Deliver()
		for _, cl in ipairs({ king, alpha, beta }) do
			local t = world:As(cl, cl.W.Target, nil, horde)
			assert(t, cl.name .. " has him at once")
			eq(t.current, 1, cl.name); eq(t.victims[1].name, beta.name); eq(t.name, "Hordeling-Realm")
		end
		for _, m in ipairs(world.log) do
			eq(m.dist, "CHANNEL", "nothing whispered to a reviewer")
			assert(not m.text:find("Arathi", 1, true), "never where it happened")
		end
		-- Alpha kills him: his own killing blow claims the bounty on every client.
		world.epoch = world.epoch + 30
		assert(world:As(alpha, alpha.events.PARTY_KILL, alpha.guid, horde))
		world:Deliver()
		for _, cl in ipairs({ king, alpha, beta }) do
			local t = world:As(cl, cl.W.Target, nil, horde)
			eq(t.current, 0, cl.name); eq(t.claims[1].slayer, alpha.name); eq(t.claims[1].points, 1)
			local r = world:As(cl, cl.W.Rankings).all[1]
			eq(r.name, alpha.name, cl.name); eq(r.points, 1); eq(r.guid, alpha.guid, "his GUID, proven his on " .. cl.name)
		end
		-- The King's relays (members of other guilds count on them) change nothing where both are held.
		world:Run(15)
		eq(world:As(beta, beta.W.Rankings).all[1].points, 1)
		-- Late logs in: his catch-up ask (W4, 45 seconds after login) and the King's answer.
		world:Load(late)
		eq(world:As(late, late.W.Target, nil, horde), nil)
		world:Run(late.W.GLOBAL_ASK_FIRST + 30)
		local t = world:As(late, late.W.Target, nil, horde)
		assert(t, "caught up"); eq(t.current, 0); eq(#t.claims, 1); eq(t.claims[1].points, 1)
		eq(world:As(late, late.W.Rankings).all[1].name, alpha.name)
		-- What the King signs is his own board: Alpha, with no review.
		eq(world:As(king, king.W.SignableRankings)[1].guid, alpha.guid)
	end)
end)

-- (1.2.4, changed on purpose, the author's report "nobody on the Most Wanted list": an ordinary
-- member of another guild, whom no client can prove, counts at once on his own word as the
-- [Olympus] chat's member, Share.Member; before, every other client refused him and only a reviewer
-- of his own guild's relay carried his rows. The King still relays both rows, for clients before
-- 1.2.4. tests/wanted-guilds.lua has this with the real Channels, Data and Roster.)
test("wanted 1.2.4 world: a member of another guild whom this client cannot prove counts on his own word at once, the King's relay changes nothing here; a removal reaches a late login in the catch-up", function()
	WithWorld(function(world)
		local king = world:Client("Varrick-Realm", "Player-1-0A000081", "king", nil, "Olympus II")
		local here = world:Client("Here-Realm", "Player-1-0A000082", nil, nil, "Olympus III")
		local far = world:Client("Far-Realm", "Player-1-0A000083", nil, nil, "Olympus II")
		local horde = "Player-1-0B000081"
		world:Hunt(nil, nil, "Distant-Realm", horde, far, far)
		-- (1.2.3, changed on purpose, Daniel's revenge: Far killed the very Horde player who killed him,
		-- so his claim pays his death's point and 100 more, on every client alike.)
		local revenge = 1 + king.W.Bounty.SCORE.REVENGE
		local t = world:As(here, here.W.Target, nil, horde)
		assert(t, "an ordinary member of another guild: his own word counts here")
		eq(#t.victims, 0, "the cycle his own kill closed"); eq(#t.claims, 1)
		eq(t.claims[1].slayer, far.name); eq(t.claims[1].points, revenge, "the same points on his own word")
		eq(world:As(king, king.W.Target, nil, horde).claims[1].points, revenge, "his guild's King verifies him")
		world:Run(15)
		t = world:As(here, here.W.Target, nil, horde)
		eq(#t.claims, 1, "the King's relay: a replay"); eq(t.claims[1].points, revenge)
		eq(world:As(here, here.W.Rankings).all[1].guid, far.guid, "this client's lookup proved the GUID his")
		local relays = 0
		for _, m in ipairs(world.log) do if m.from == king and m.text:find("^WK~R~4~") then relays = relays + 1 end end
		eq(relays, 2, "the death and the kill, once each")
		-- The King takes him off; a member offline then gets it in the catch-up.
		world:Offline(here)
		assert(world:As(king, king.W.RemoveTarget, nil, horde))
		world:Deliver()
		eq(world:As(far, far.W.Target, nil, horde).active, false, "on every client online")
		eq(#world:As(far, far.W.Rankings).all, 0)
		world.epoch = world.epoch + 600
		world:Load(here)
		eq(world:As(here, here.W.Target, nil, horde).active, true)
		world:Run(here.W.GLOBAL_ASK_FIRST + 30)
		eq(world:As(here, here.W.Target, nil, horde).active, false, "the removal came in the King's answer")
		eq(#world:As(here, here.W.Rankings).all, 0)
	end)
end)

---------------------------------------------------------------------------
-- 1.2.3/1.2.4, the bounty: a death adds the victim's office and level
-- to the Horde player's bounty, a kill pays a small level base and his whole bounty, a member who
-- kills his own killer 100 more, corpse camping counts once in 10 minutes and a cycle holds 2000;
-- the same rows give the same points on every client; and the deaths the game's death recaps
-- still hold count once at login, with one notice. Each of these fails on the build before it
-- (v123/integration: every death 1 point, a kill its bounty alone, nothing of the rest).
---------------------------------------------------------------------------

-- A member's own row on the channel with what it is worth (WK~2), as a 1.2.3 client sends it.
local function BountyRow(c, W, o)
	return table.concat({ "WK", 2, ScopeOf(c), o.guild or "Olympus II", o.digest, o.at, o.month or W.MonthNow(), o.kind or "S",
		o.horde, o.own, o.worth or "M~40~0", o.name }, "~")
end

-- The real confirmed-alt and verified-owner readers, isolated from the arena's other actions.
-- All scoring below still enters through the actual shared WK handler, never through a copy of it.
local function BountyOwnerReaders(c)
	assert(loadfile(ROOT .. "Olympus/Alts.lua"))("Olympus", c)
	c.Arena = setmetatable({ Action = function() end }, { __index = ns.Arena })
	c.ArenaMoney = setmetatable({ Subscribe = function() end }, { __index = ns.ArenaMoney })
	c.Backup, c.Wallet = { arenaChecks = {} }, { KnownKey = function() return nil end }
	assert(loadfile(ROOT .. "Olympus/Debts.lua"))("Olympus", c)
end
local function BountyLink(w, c, main, alt, yes)
	c.Alts.Handle("CHANNEL", main, ("AL~%d~M~Olympus II~%s"):format(w.epoch, alt))
	if yes then c.Alts.Handle("CHANNEL", alt, ("AL~%d~A~Olympus II~%s"):format(w.epoch, main)) end
end

test("wanted 1.2.4 owner gaps: reciprocal links join death cooldowns at Rebuild, one-sided offers and independent victims do not", function()
	WithWanted(function(w, W, c)
		w.manager = false
		BountyOwnerReaders(c)
		local main = w.participant("Owner Main-Realm", "Player-1-AA00F001")
		local alt = w.participant("Owner Alt-Realm", "Player-1-AA00F002")
		local other = w.participant("Other Owner-Realm", "Player-1-AA00F003")
		local horde = "Player-1-0D00F001"
		w.hordePlayer("Owner Rogue-Realm", horde)
		local seq = 0
		local function Death(name, own, ml)
			seq = seq + 1; w.advance()
			assert(w.commHandlers.WK("CHANNEL", name, BountyRow(c, W, { digest = ("%016x"):format(0xf0010000 + seq), at = w.epoch,
				horde = "1.0d00f001", own = own, worth = "M~" .. ml .. "~60", name = "Owner Rogue-Realm" })))
		end
		BountyLink(w, c, main, alt, false)
		eq(c.Debts.SameOwner(main, alt), false, "a one-sided main claim proves nothing")
		Death(main, "1.aa00f001", 60); Death(alt, "1.aa00f002", 1)
		eq(W.Target(nil, horde).current, 61)
		BountyLink(w, c, main, alt, true)
		eq(c.Debts.SameOwner(main, alt), true, "both characters confirmed")
		W.Rebuild()
		local t = W.Target(nil, horde)
		eq(t.current, 60, "the retained second row is inside its confirmed owner's gap")
		eq(t.lifetimeKills, 1)
		Death(other, "1.aa00f003", 1)
		t = W.Target(nil, horde)
		eq(t.current, 61); eq(t.lifetimeKills, 2, "an unrelated level-1 victim still counts")
		w.advance(W.Bounty.SCORE.REPEAT_GAP)
		Death(alt, "1.aa00f002", 1)
		t = W.Target(nil, horde)
		eq(t.current, 62); eq(t.lifetimeKills, 3, "the approved 600-second interval is unchanged")
		-- The confirmed-alt fallback also works if the optional verified-key helper is unavailable.
		c.Debts.SameOwner = nil
		Death(main, "1.aa00f001", 60)
		t = W.Target(nil, horde)
		eq(t.current, 62); eq(t.lifetimeKills, 3)
	end)
end)

test("wanted 1.2.4 owner gaps: linked Slayers share level and revenge cooldowns, clear all owner grudges, and keep persisted character gaps", function()
	WithWanted(function(w, W, c)
		w.manager = false
		BountyOwnerReaders(c)
		local main = w.participant("Slayer Main-Realm", "Player-1-CC00F001")
		local alt = w.participant("Slayer Alt-Realm", "Player-1-CC00F002")
		local other = w.participant("Independent Slayer-Realm", "Player-1-CC00F003")
		local horde = "Player-1-0D00F002"
		w.hordePlayer("Slayer Rogue-Realm", horde)
		local seq = 0
		local function Row(name, own, kind)
			seq = seq + 1; w.advance()
			assert(w.commHandlers.WK("CHANNEL", name, BountyRow(c, W, { digest = ("%016x"):format(0xf0020000 + seq), at = w.epoch,
				kind = kind, horde = "1.0d00f002", own = own, worth = "M~1~60", name = "Slayer Rogue-Realm" })))
			local t = W.Target(nil, horde)
			return t, t.claims[#t.claims]
		end
		-- Separate old character grudges, then their reciprocal link becomes known.
		Row(main, "1.cc00f001", "S"); Row(alt, "1.cc00f002", "S")
		BountyLink(w, c, main, alt, true)
		local t, claim = Row(alt, "1.cc00f002", "P")
		eq(claim.points, 108); eq(claim.revenge, true)
		local stored = c.rdb.wanted.targets[t.key]
		eq(stored.bounty.grudge[W.Bounty.Who(main)], nil, "the linked main's old grudge closes too")
		eq(stored.bounty.grudge[W.Bounty.Who(alt)], nil)
		-- Fold to the checkpoint and reload: stored keys remain per character, owner lookup joins them.
		W.MAX_EVIDENCE = 1
		t, claim = Row(main, "1.cc00f001", "P")
		eq(claim.points, 0, "switching to the linked Slayer cannot mint another level base")
		assert(W.Stats().checkpointed > 0)
		eq(stored.base.bounty.kill[W.Bounty.Who(alt)] ~= nil, true, "the original character key is retained")
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c); W = c.Wanted; assert(W.Prune())
		t, claim = Row(main, "1.cc00f001", "P")
		eq(claim.points, 0, "the confirmed-owner gap survives a fold and reload")
		eq(claim.revenge, nil)
		t, claim = Row(other, "1.cc00f003", "P")
		eq(claim.points, 6, "an independent Slayer still has its own approved interval")
		w.advance(W.Bounty.SCORE.KILL_GAP)
		Row(main, "1.cc00f001", "S")
		t, claim = Row(main, "1.cc00f001", "P")
		eq(claim.points, 7, "the level base and open bounty are due again, the owner's same-day revenge is not")
		eq(claim.revenge, nil)
		w.advance(W.Bounty.SCORE.REVENGE_GAP)
		Row(main, "1.cc00f001", "S")
		t, claim = Row(alt, "1.cc00f002", "P")
		eq(claim.points, 107); eq(claim.revenge, true, "the existing daily revenge interval is unchanged")
	end)
end)

test("wanted 1.2.4 owner gaps: actual verified account keys and this account's characters join cooldowns without guessing other accounts", function()
	WithWanted(function(w, W, c)
		w.manager = false
		BountyOwnerReaders(c)
		local names = { w.participant("Key Main-Realm", "Player-1-CC00F011"), w.participant("Key Alt-Realm", "Player-1-CC00F012"),
			w.participant("Different Key-Realm", "Player-1-CC00F013"), w.participant("Local One-Realm", "Player-1-CC00F014"),
			w.participant("Local Two-Realm", "Player-1-CC00F015") }
		c.Wallet.KnownKey = function(name)
			for i = 1, 3 do
				if c.Fold(c.FullName(name)) == c.Fold(names[i]) then
					return { name = names[i], gk = ("1.cc00f01%d"):format(i), pk = string.rep(i < 3 and "A" or "B", 32), fp = i < 3 and "same" or "different" }
				end
			end
		end
		c.db.myCharacters = { [names[4]:lower()] = {}, [names[5]:lower()] = {} }
		eq(c.Debts.SameOwner(names[1], names[2]), true); eq(c.Debts.SameOwner(names[1], names[3]), false)
		eq(c.Debts.SameOwner(names[4], names[5]), true)
		local horde = "Player-1-0D00F003"
		w.hordePlayer("Key Rogue-Realm", horde)
		local points = {}
		for i, name in ipairs(names) do
			w.advance()
			assert(w.commHandlers.WK("CHANNEL", name, BountyRow(c, W, { digest = ("%016x"):format(0xf0030000 + i), at = w.epoch,
				kind = "P", horde = "1.0d00f003", own = ("1.cc00f01%d"):format(i), worth = "M~1~60", name = "Key Rogue-Realm" })))
			local t = W.Target(nil, horde); points[i] = t.claims[#t.claims].points
		end
		eq(points[1], 6); eq(points[2], 0); eq(points[3], 6); eq(points[4], 6); eq(points[5], 0)
		-- Malformed/non-name old keys cannot acquire guessed ownership; lookup itself remains bounded.
		local calls = 0
		c.Debts.SameOwner = function() calls = calls + 1 return false end
		local map = {}
		for i = 1, 100 do map["n:unknown" .. i .. "-realm"] = w.epoch end
		eq(W.Bounty.OwnerAt(map, "n:unrelated-realm"), nil)
		eq(calls, W.Bounty.STATE_MAX)
		eq(W.Bounty.SameWho("?", "n:unknown-realm"), false)
	end)
end)

test("wanted 1.2.4 bounty: the rebalance keeps bounty and revenge weights while a kill pays one base point per ten target levels, rounded up", function()
	WithWanted(function(_, W)
		local B = W.Bounty
		local S = assert(B and B.SCORE, "the constants table")
		eq(S.OFFICE.K, 100); eq(S.OFFICE.H, 50); eq(S.OFFICE.G, 30); eq(S.OFFICE.C, 20); eq(S.OFFICE.O, 10); eq(S.OFFICE.M, 0)
		eq(S.VICTIM_LEVEL, 1); eq(S.KILL_LEVEL_STEP, 10); eq(S.REVENGE, 100); eq(S.GRUDGE_DAYS, 14); eq(S.REPEAT_GAP, 600)
		eq(S.BOUNTY_MAX, 2000); eq(S.HIDDEN_GAP, 10)
		-- (1.2.3 repair, proposed for Daniel's OK: corpse camping and a friend killed in a loop.)
		eq(S.KILL_GAP, 3600); eq(S.REVENGE_GAP, 86400)
		assert(S.KILL_GAP >= S.REPEAT_GAP, "a kill's gap at least a death's")
		eq(S.MAX_POINTS, 100000); eq(S.MAX_POINTS, W.MAX_POINTS, "what WY carries: 1.2.2's receivers refuse a word above it")
		eq(B.DeathPoints("K", 60) + B.DeathPoints("M", 40) + B.DeathPoints("M", 40), 240, "the King (60) and two members (40, 40)")
		eq(B.ClaimPoints(B.ClaimLevel(55, true, 60), 240, false), 246, "a '??' (55 at least) and the King's row's exact 60")
		eq(B.ClaimPoints(B.ClaimLevel(55, true, nil), 240, false), 246, "no exact level seen in the cycle: the rounded-up floor")
		-- (Daniel's revenge is 100, the spec's table's 50 gave 410: one of the level-40 victims, who
		-- sees him as 50 at least, kills him.)
		eq(B.ClaimPoints(B.ClaimLevel(50, true, 60), 240, true), 346, "the revenge")
		eq(B.DeathPoints("H", 58), 108, "a level-58 guild master who is a High Councillor: his highest office alone")
		eq(B.ClaimPoints(B.ClaimLevel(52, false, nil), 0, false), 6, "a level-52 Horde player nobody reported: ceil(52 / 10)")
		eq(B.BasePoints(0), 0); eq(B.BasePoints(1), 1); eq(B.BasePoints(10), 1); eq(B.BasePoints(11), 2); eq(B.BasePoints(60), 6)
		eq(B.LegacyClaimPoints(52, 0, false), 104, "the previous formula remains only as a migration validator")
		eq(B.ClaimLevel(58, false, 60), 58, "a claim's own exact level is its own")
		eq(B.ClaimLevel(0, false, 60), 60, "none seen: the cycle's highest exact one")
		eq(B.ClaimLevel(0, false, nil), 0, "none known: 0")
		eq(B.Lower("K", "M"), "M"); eq(B.Lower("G", "H"), "G"); eq(B.Lower("O", nil), "M")
		eq(B.Wire({ office = "K", ml = 60, hl = 55, hf = true }), "K~60~55+")
		local back = B.Unwire("G~58~60")
		eq(back.office, "G"); eq(back.ml, 58); eq(back.hl, 60); eq(back.hf, nil)
		for _, bad in ipairs({ "X~1~1", "K~1000~1", "K~1~0+", "K~-1~1", "K~1", "k~1~1" }) do eq(B.Unwire(bad), nil, bad) end
	end)
end)

test("wanted 1.2.4 scoring migration: retained live evidence is rebuilt under score v2, while old signed and publisher totals are discarded", function()
	WithWanted(function(w, W, c)
		w.manager = false
		local horde = "Player-1-0D00BA01"
		w.hordePlayer("Migration Prey-Realm", horde)
		w.units.target = { name = "Migration Prey-Realm", guid = horde, faction = "Horde", level = 60 }
		local ok, claim = w.handlers.PARTY_KILL(w.units.player.guid, horde)
		w.units.target = nil
		assert(ok, tostring(claim)); eq(claim.points, 6)

		-- Shape the derived cache exactly as score v1 would have left this same retained fact.
		-- The evidence itself remains the authority and must deterministically rebuild it to six.
		local s = c.rdb.wanted
		local target = assert(s.targets["g:" .. horde])
		local rank = assert(W.Rankings().all[1])
		claim.points, s.evidence[1].points = 120, 120
		target.claims[1].points, target.paid[rank.key].total = 120, 120
		target.paid[rank.key].months[W.MonthNow()] = 120
		s.slayers[rank.key].total, s.slayers[rank.key].months[W.MonthNow()] = 120, 120
		s.scoreVersion = 1
		s.global = { text = "WY~1~legacy", issuer = c.me }
		s.globalHeads = { legacy = { epoch = 1, seq = 1, pk64 = "old" } }
		c.db.wantedPublisher = { last = { body = "WY~1~legacy", expires = w.epoch + 1000, issuer = c.me, scope = "legacy" } }

		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted; assert(W.Load())
		s = c.rdb.wanted
		eq(s.scoreVersion, 2); eq(s.evidence[1].points, 6)
		target = assert(W.Target(nil, horde)); eq(target.claims[1].points, 6)
		eq(W.Rankings().all[1].points, 6, "the old 120-point cache is not mixed with the rebuilt evidence")
		eq(s.global, nil); eq(s.globalHeads, nil); eq(c.db.wantedPublisher.last, nil)
		eq(s.scoreArchive.from, 1); eq(s.scoreArchive.recalculatedClaims, 0)
	end)
end)

test("wanted 1.2.4 scoring migration: the actual retained ten-claim Hobo 534 and Socio 332 deterministically become 30 and 169, with the personal balancing letter once", function()
	WithWanted(function(w, W, c)
		w.manager, w.dead = false, false
		c.CaptureError = function(where, err) error(tostring(where) .. ": " .. tostring(err)) end
		local hobo = w.participant("Hobo Heretics-Realm", "Player-1-CC00BC01")
		local socio = w.participant("Socioeconomic Factors-Realm", "Player-1-CC00BC02")
		local seq = 0
		local function Row(sender, own, horde, level, kind, ml)
			seq = seq + 1
			w.advance(W.SHARE_RATE_WINDOW + 1)
			w.hordePlayer("Snapshot Prey " .. seq .. "-Realm", horde)
			assert(w.commHandlers.WK("CHANNEL", sender, BountyRow(c, W, {
				digest = ("%016x"):format(0xbc010000 + seq), at = w.epoch, kind = kind or "P",
				horde = horde:gsub("^Player%-(%d+)%-(%x+)$", "%1.%2"):lower(),
				own = own:gsub("^Player%-(%d+)%-(%x+)$", "%1.%2"):lower(),
				worth = ("M~%d~%d"):format(ml or 60, level), name = "Snapshot Prey " .. seq .. "-Realm",
			})))
		end

		-- The ten levels in the retained Hobo history: 267 levels were 534 points under the
		-- old 2 x level rule and are exactly 30 under score v2 (3 each).
		for i, level in ipairs({ 23, 26, 22, 30, 26, 30, 27, 30, 26, 27 }) do
			Row(hobo, "Player-1-CC00BC01", ("Player-1-0D00BC%02X"):format(i), level)
		end
		-- Socio's retained rows are an ordinary level-26 claim (52 -> 3) and a level-60
		-- revenge carrying a 60-point bounty (280 -> 166): 332 -> 169 in all.
		Row(socio, "Player-1-CC00BC02", "Player-1-0D00BC10", 26)
		Row(socio, "Player-1-CC00BC02", "Player-1-0D00BC11", 60, "S", 60)
		Row(socio, "Player-1-CC00BC02", "Player-1-0D00BC11", 60)
		local before = W.Rankings().all
		eq(before[1].name, socio); eq(before[1].points, 169)
		eq(before[2].name, hobo); eq(before[2].points, 30); eq(before[2].claims, 10)
		local socioKey, hoboKey = before[1].key, before[2].key

		-- Recreate the derived score-v1 caches around those same retained facts. The rows'
		-- frozen level, bounty and revenge remain the source; no historic event is invented.
		local s, oldById = c.rdb.wanted, {}
		for _, t in pairs(s.targets) do
			for _, claim in ipairs(t.claims or {}) do
				local old = W.Bounty.LegacyClaimPoints(claim.level, claim.bounty, claim.revenge)
				claim.points, claim.scoreVersion = old, nil
				oldById[claim.id] = old
				for _, paid in pairs(t.paid or {}) do
					paid.total, paid.claims = old, 1
					paid.months, paid.monthAt, paid.monthClaims = { [claim.month] = old }, { [claim.month] = claim.at }, { [claim.month] = 1 }
				end
			end
		end
		for _, e in ipairs(s.evidence) do if oldById[e.id] then e.points = oldById[e.id] end end
		s.slayers[hoboKey].total, s.slayers[hoboKey].months[W.MonthNow()] = 534, 534
		s.slayers[socioKey].total, s.slayers[socioKey].months[W.MonthNow()] = 332, 332
		eq(s.slayers[hoboKey].total, 534); eq(s.slayers[hoboKey].claims, 10)
		eq(s.slayers[hoboKey].monthClaims[W.MonthNow()], 10)
		eq(s.slayers[socioKey].total, 332)
		-- This is Hobo's login: only the character whose own displayed total decreases receives
		-- the saved note. Another character cannot consume it.
		c.me, w.units.player.name, w.units.player.guid = hobo, hobo, "Player-1-CC00BC01"
		s.scoreVersion = 1

		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted; assert(W.Load())
		local after = W.Rankings().all
		eq(after[1].name, socio); eq(after[1].points, 169)
		eq(after[2].name, hobo); eq(after[2].points, 30); eq(after[2].claims, 10)
		local month = W.Rankings().month
		eq(month[2].name, hobo); eq(month[2].points, 30); eq(month[2].claims, 10)
		eq(c.rdb.wanted.scoreVersion, 2)
		local pending = assert(c.rdb.wanted.scoreMigrationLetter)
		eq(pending.who, "n:" .. c.Fold(hobo)); eq(pending.old, 534); eq(pending.new, 30)

		-- No usable UI: the letter is not consumed, including across a reload.
		local window = c.Window
		c.Window = false
		w.advance(W.Bounty.NOTICE_LOGIN)
		local shown, why = W.Bounty.Notices()
		eq(shown, 0); eq(why, "ui"); assert(c.rdb.wanted.scoreMigrationLetter)
		c.Window = window
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted; assert(W.Load())
		eq(c.rdb.wanted.scoreMigrationLetter.old, 534, "the undisplayed note survived the reload")
		w.advance(W.Bounty.NOTICE_LOGIN)
		eq(W.Bounty.Notices(), 1)
		local frame = assert(w.windows.OlympusWantedScoreMigration)
		eq(frame.shown, true); eq(frame.title.text, ns.L.WANTED_SCORE_MIGRATION_TITLE)
		eq(frame.body.text, ns.L.WANTED_SCORE_MIGRATION_BODY:format(534, 30), "exact old and new totals, retained-history rule and signature")
		assert(frame.body.text:find("\nFaladoriel Skylance\nThe Royal Dev$"), frame.body.text)
		eq(c.rdb.wanted.scoreMigrationLetter, nil, "cleared only after the frame was shown")

		-- Once shown, a reload cannot create it again.
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted; assert(W.Load())
		w.advance(W.Bounty.NOTICE_LOGIN)
		eq(W.Bounty.Notices(), 0); eq(c.rdb.wanted.scoreMigrationLetter, nil)
		eq(w.windows.OlympusWantedScoreMigration, frame, "no second frame")
	end)
end)

test("wanted 1.2.4 scoring migration: an equal or increased personal total never qualifies for the balancing letter", function()
	WithWanted(function(_, W, c)
		assert(W.Load())
		local s, who = c.rdb.wanted, "n:" .. c.Fold(c.me)
		for _, totals in ipairs({ { 30, 30 }, { 29, 30 } }) do
			s.scoreMigrationLetter = { version = W.SCORE_VERSION, who = who, old = totals[1], new = totals[2] }
			eq(W.Bounty.ScoreMigration(s, who), nil)
			assert(W.Prune())
			eq(s.scoreMigrationLetter, nil, "invalid pending note is removed, not shown")
		end
	end)
end)

test("wanted 1.2.4 scoring migration: proven checkpoint claims are recalculated, while tampered and undecomposable totals stay auditable but unranked", function()
	WithWanted(function(w, W, c)
		w.manager, w.dead = false, false
		local horde = "Player-1-0D00BA02"
		w.hordePlayer("Checkpoint Prey-Realm", horde)
		w.units.target = { name = "Checkpoint Prey-Realm", guid = horde, faction = "Horde", level = 60 }
		assert(w.handlers.PARTY_KILL(w.units.player.guid, horde))
		w.units.target = nil
		-- A second fact forces the first one into its immutable checkpoint.
		W.MAX_EVIDENCE = 1
		w.advance(W.DEATH_WINDOW + 1)
		w.hordePlayer("Checkpoint Filler-Realm", "Player-1-0D00BA03")
		w.die(w.forever("Checkpoint Filler-Realm", "Player-1-0D00BA03")); w.dead = false

		local function Clone(value)
			if type(value) ~= "table" then return value end
			local out = {} for k, v in pairs(value) do out[Clone(k)] = Clone(v) end return out
		end
		local s = c.rdb.wanted
		local validKey = "g:" .. horde
		local valid = assert(s.targets[validKey]); assert(valid.base and valid.base.claims[1], "the claim was checkpointed")
		local slayerKey, paid = next(valid.base.paid); paid = assert(paid)
		local month = W.MonthNow()
		valid.base.claims[1].points, valid.base.claims[1].scoreVersion = 120, nil
		paid.total, paid.claims, paid.months, paid.monthAt, paid.monthClaims = 120, 1,
			{ [month] = 120 }, { [month] = valid.base.claims[1].at }, { [month] = 1 }

		-- The same retained history with a point value that score v1 could never have produced is
		-- kept for audit, but cannot mint score-v2 points.
		local badGuid, badKey = "Player-1-0D00BA04", "g:Player-1-0D00BA04"
		local badBase = Clone(valid.base)
		badBase.claims[1].id, badBase.claims[1].points = "tampered-legacy-claim", 999
		s.targets[badKey] = { key = badKey, name = "Tampered Prey-Realm", guid = badGuid, active = true,
			addedAt = w.epoch, source = "shared", base = badBase }
		s.aliases[badKey] = badKey
		s.baseSlayers["g:Player-1-CC00BA04"] = { key = "g:Player-1-CC00BA04", name = "Folded Slayer-Realm",
			guid = "Player-1-CC00BA04", total = 77, claims = 1, reachedAt = w.epoch, lastAt = w.epoch,
			months = { [month] = 77 }, monthAt = { [month] = w.epoch }, monthClaims = { [month] = 1 } }
		s.scoreVersion = 1

		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted; assert(W.Load())
		s = c.rdb.wanted
		local migrated = assert(W.Target(nil, horde)).claims[1]
		eq(migrated.points, 6); eq(migrated.legacyPoints, 120); eq(migrated.scoreVersion, 2)
		local bad = assert(W.Target(nil, badGuid)).claims[1]
		eq(bad.points, 999, "the historical row is preserved"); eq(bad.unranked, true); eq(bad.scoreVersion, 1)
		eq(#W.Rankings().all, 1); eq(W.Rankings().all[1].points, 6)
		local archive = assert(s.scoreArchive)
		eq(archive.recalculatedClaims, 1); eq(archive.archivedClaims, 1); eq(archive.archivedPoints, 197)
		eq(archive.targets[badKey].paid[slayerKey].total, 120)
		eq(archive.baseSlayers["g:Player-1-CC00BA04"].total, 77)
	end)
end)

test("wanted 1.2.4 scoring migration: a future score version fails closed without changing its saved data", function()
	WithWanted(function(_, W, c)
		assert(W.AddTarget("Future Prey-Realm", "Player-1-0D00BA05"))
		local s = c.rdb.wanted
		s.scoreVersion, s.futureMarker = W.SCORE_VERSION + 1, { keep = true }
		s.scoreMigrationLetter = { keep = true, version = W.SCORE_VERSION + 1 }
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted
		eq(W.Load(), false); eq(s.scoreVersion, 3); eq(s.futureMarker.keep, true)
		eq(s.scoreMigrationLetter.keep, true, "future data is untouched")
		eq(W.MigrateScoring(s), false); eq(#W.Rankings().all, 0)
	end)
end)

test("wanted 1.2.4 bounty: a kill with no bounty open pays the small rounded level base from his corpse, none seen pays 0, and nothing inside an instance", function()
	WithWanted(function(w, W)
		w.manager = false
		local me = w.units.player.guid
		w.units.player.level = 45
		local function Corpse(name, guid, level)
			w.hordePlayer(name, guid)
			w.units.target = level and { name = name, guid = guid, faction = "Horde", level = level } or nil -- his corpse, targeted
		end
		Corpse("Unreported-Realm", "Player-1-0D00B001", 52)
		local ok, e = w.handlers.PARTY_KILL(me, "Player-1-0D00B001")
		assert(ok, tostring(e))
		eq(e.hl, 52); eq(e.hf, nil); eq(e.points, 6, "ceil(52 / 10), not the former 104")
		eq(W.Rankings().all[1].points, 6)
		w.advance(W.DEATH_WINDOW + 1)
		Corpse("Skull-Realm", "Player-1-0D00B002", -1)
		ok, e = w.handlers.PARTY_KILL(me, "Player-1-0D00B002")
		assert(ok, tostring(e)); eq(e.hl, 55); eq(e.hf, true); eq(e.points, 6, "'??' to a level 45: 55 at least")
		assert(w.sent[#w.sent].text:find("^WK~2~.*~P~1%.0d00b002~1%.aa000001~M~45~55%+~Skull%-Realm$"), w.sent[#w.sent].text)
		w.advance(W.DEATH_WINDOW + 1)
		w.units.player.level = 58
		Corpse("Top-Realm", "Player-1-0D00B003", -1)
		ok, e = w.handlers.PARTY_KILL(me, "Player-1-0D00B003")
		assert(ok, tostring(e)); eq(e.hl, 60, "58 + 10 is past the game's highest level, 60"); eq(e.points, 6)
		w.advance(W.DEATH_WINDOW + 1)
		Corpse("Unseen-Realm", "Player-1-0D00B004", nil)
		ok, e = w.handlers.PARTY_KILL(me, "Player-1-0D00B004")
		assert(ok, tostring(e)); eq(e.hl, 0); eq(e.points, 0, "no unit of his: no level to pay")
		-- A battleground, an arena, a dungeon, a raid: nothing, his corpse in view or not.
		w.advance(W.DEATH_WINDOW + 1)
		Corpse("Battleground-Realm", "Player-1-0D00B005", 60)
		w.inside = true
		eq(select(2, w.handlers.PARTY_KILL(me, "Player-1-0D00B005")), "instance")
		w.die(w.forever("Battleground-Realm", "Player-1-0D00B005"))
		w.inside, w.dead = false, false
		eq(W.Target(nil, "Player-1-0D00B005"), nil, "neither the kill nor the death")
		eq(W.Rankings().all[1].points, 18, "only the kills outside")
		w.advance(W.DEATH_WINDOW + 1)
		ok, e = w.handlers.PARTY_KILL(me, "Player-1-0D00B005")
		assert(ok, tostring(e)); eq(e.points, 6, "outside again, he counts")
	end)
end)

test("wanted 1.2.4 bounty world: a 240 bounty dominates the level-60 base on every client, including hidden-level claims", function()
	WithWorld(function(world)
		local king = world:Client("Varrick-Realm", "Player-1-0A0000C1", "king")
		local first = world:Client("First-Realm", "Player-1-0A0000C2")
		local second = world:Client("Second-Realm", "Player-1-0A0000C3")
		local slayer = world:Client("Slayer-Realm", "Player-1-0A0000C4")
		local watcher = world:Client("Watcher-Realm", "Player-1-0A0000C5")
		king.units.player.level, first.units.player.level, second.units.player.level = 60, 40, 40
		slayer.units.player.level, watcher.units.player.level = 45, 30
		local everyone = { king, first, second, slayer, watcher }
		local function Die(cl, horde, name, seen)
			cl.units.target = seen and { name = name, guid = horde, faction = "Horde", level = seen } or nil
			cl.dead, cl.recap = true, { { event = "SPELL_DAMAGE", sourceGUID = horde, sourceName = name, sourceFlags = 0x548,
				overkill = 90, timestamp = world.epoch - 0.2 } }
			world:As(cl, cl.events.PLAYER_DEAD)
			cl.dead, cl.recap, cl.units.target = false, nil, nil
			world:Deliver()
			world.epoch = world.epoch + 60
		end
		local function Kill(cl, horde, name, seen)
			cl.units.target = { name = name, guid = horde, faction = "Horde", level = seen }
			local ok, claim = world:As(cl, cl.events.PARTY_KILL, cl.guid, horde)
			cl.units.target = nil
			assert(ok, tostring(claim))
			world:Deliver()
			world:Run(15) -- (the King relays what he took from members: held already everywhere)
			return claim
		end
		local horde = "Player-1-0B0000C1"
		world.horde[horde] = "Ganker-Realm"
		Die(king, horde, "Ganker-Realm", 60) -- he had him targeted: level 60, exactly
		Die(first, horde, "Ganker-Realm") -- nothing of his in view
		Die(second, horde, "Ganker-Realm")
		for _, cl in ipairs(everyone) do
			local t = world:As(cl, cl.W.Target, nil, horde)
			eq(t.current, 240, cl.name .. ": the same bounty on every client"); eq(t.lifetimeKills, 3, cl.name)
		end
		-- The tab's row says it in points.
		local row
		for _, line in ipairs(world:As(watcher, watcher.W.Build)) do if line.id == "wanted:g:" .. horde then row = line end end
		eq(row and row.right, ns.L.WANTED_ROW_COUNTS:format(240, 3))
		local claim = Kill(slayer, horde, "Ganker-Realm", -1) -- 15 levels above him: "??"
		eq(claim.hl, 55); eq(claim.hf, true); eq(claim.level, 60, "the King's row's exact 60"); eq(claim.points, 246)
		for _, cl in ipairs(everyone) do
			local t = world:As(cl, cl.W.Target, nil, horde)
			eq(t.current, 0, cl.name .. ": a new cycle"); eq(t.claims[#t.claims].points, 246, cl.name)
			local r = world:As(cl, cl.W.Rankings).all[1]
			eq(r.guid, slayer.guid, cl.name); eq(r.points, 246, cl.name .. ": the same Slayers' points on every client")
		end
		-- /oly wanted status, on a client that only heard it all: his bounty, the Slayer's points.
		local status = world:As(watcher, watcher.W.StatusText)
		assert(status:find(ns.L.WANTED_STATUS_SLAYER_ROW:format(1, ns.DisplayName(slayer.name), 246, 1), 1, true), status)
		-- No exact level in the cycle (the King saw him as "??" too, a floor): the claim's own floor.
		local other = "Player-1-0B0000C2"
		world.horde[other] = "Hidden-Realm"
		Die(king, other, "Hidden-Realm", -1)
		Die(first, other, "Hidden-Realm")
		Die(second, other, "Hidden-Realm")
		status = world:As(watcher, watcher.W.StatusText)
		assert(status:find(ns.L.WANTED_STATUS_BOUNTY_ROW:format(ns.DisplayName("Hidden-Realm"), 240, 3), 1, true), status)
		claim = Kill(slayer, other, "Hidden-Realm", -1)
		eq(claim.points, 246)
		for _, cl in ipairs(everyone) do eq(world:As(cl, cl.W.Rankings).all[1].points, 492, cl.name) end
	end)
end)

test("wanted 1.2.4 bounty: the revenge remains 100 once a claim while the kill level base is rebalanced", function()
	WithWanted(function(w, W, c)
		w.manager = false
		local me = w.units.player.guid
		w.units.player.level = 40
		local function DieTo(guid, name)
			w.advance(W.Bounty.SCORE.REPEAT_GAP + 1)
			w.die(w.forever(name, guid))
			w.dead = false
		end
		local function Kill(guid, name, level)
			w.advance(W.DEATH_WINDOW + 1)
			w.units.target = { name = name, guid = guid, faction = "Horde", level = level }
			local ok, e = w.handlers.PARTY_KILL(me, guid)
			w.units.target = nil
			assert(ok, tostring(e))
			return e
		end
		local grom = "Player-1-0D00C001"
		w.hordePlayer("Grom-Realm", grom)
		DieTo(grom, "Grom-Realm")
		w.advance(2 * 3600)
		local e = Kill(grom, "Grom-Realm", 50)
		eq(e.revenge, true); eq(e.points, 5 + 40 + 100, "his small level base, our death's bounty and the revenge")
		-- (1.2.3 repair, changed on purpose: our kills of one Horde player pay his level once in
		-- KILL_GAP; before, 100 again a few seconds later.)
		e = Kill(grom, "Grom-Realm", 50)
		eq(e.revenge, nil, "once a claim: no new death of ours"); eq(e.points, 0, "his level paid already, within KILL_GAP")
		w.advance(W.Bounty.SCORE.KILL_GAP)
		e = Kill(grom, "Grom-Realm", 50)
		eq(e.revenge, nil); eq(e.points, 5, "past KILL_GAP his level base again")
		-- Another member's kill of him leaves our grudge open; then ours pays it, after a reload too.
		local thrall = "Player-1-0D00C002"
		w.hordePlayer("Thrall-Realm", thrall)
		DieTo(thrall, "Thrall-Realm")
		local other = w.participant("Other-Realm", "Player-1-CC00C001")
		w.advance(60)
		assert(w.commHandlers.WK("CHANNEL", other, BountyRow(c, W, { digest = "00000000000c0001", at = w.epoch, kind = "P",
			horde = "1.0d00c002", own = "1.cc00c001", worth = "M~40~0", name = "Thrall-Realm" })))
		local paid = W.Target(nil, thrall).claims[1]
		eq(paid.slayer, other); eq(paid.revenge, nil, "his claim: our grudge is not his"); eq(paid.points, 40)
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted
		assert(W.Prune())
		e = Kill(thrall, "Thrall-Realm", 40)
		eq(e.revenge, true, "still ours after his claim and a reload"); eq(e.points, 4 + 100)
		-- A death to one Horde player avenges nothing on another (another GUID).
		local rexxar, zuljin = "Player-1-0D00C003", "Player-1-0D00C004"
		w.hordePlayer("Rexxar-Realm", rexxar); w.hordePlayer("Zuljin-Realm", zuljin)
		DieTo(rexxar, "Rexxar-Realm")
		e = Kill(zuljin, "Zuljin-Realm", 40)
		eq(e.revenge, nil); eq(e.points, 4)
		-- A grudge over 14 days old is over; his bounty still pays.
		w.advance(14 * 86400 + 1)
		e = Kill(rexxar, "Rexxar-Realm", 40)
		eq(e.revenge, nil, "expired"); eq(e.points, 4 + 40)
		-- A kill before the death: nothing to avenge yet; the death after it opens the grudge.
		local voljin = "Player-1-0D00C005"
		w.hordePlayer("Voljin-Realm", voljin)
		e = Kill(voljin, "Voljin-Realm", 40)
		eq(e.revenge, nil); eq(e.points, 4)
		-- (1.2.3 repair: past our kill's KILL_GAP, so that the revenge on him pays.)
		w.advance(W.Bounty.SCORE.KILL_GAP)
		DieTo(voljin, "Voljin-Realm")
		eq(W.Target(nil, voljin).current, 40)
		e = Kill(voljin, "Voljin-Realm", 40)
		eq(e.revenge, true); eq(e.points, 4 + 40 + 100)
	end)
end)

test("wanted 1.2.3 bounty: an office comes only from what the client trusts (the pinned King, the signed council, the game's or the authorized rank for a guild master, his master's list, the signed titles, the author), his highest alone; a row's word never raises the office or the levels", function()
	WithWanted(function(w, W, c)
		local B = W.Bounty
		-- (1.2.3: these are the offices with LOCAL_OFFICES, Daniel's option (b), the shipped default, which this
		-- client verifies from what it alone holds; the default counts only those every client
		-- verifies the same way: the test after this one.)
		B.LOCAL_OFFICES = true
		local function Office(name, guild) return B.OfficeOf(name, guild or "Olympus II") end
		local function Named(...)
			local set = {}
			for _, name in ipairs({ ... }) do set[c.Fold(c.FullName(name))] = true end
			return function(name) return set[c.Fold(c.FullName(name))] == true end
		end
		eq(Office("Plain-Realm"), "M")
		w.authority("Crowned-Realm", "king"); eq(Office("Crowned-Realm"), "K")
		w.authority("Councillor-Realm", "council"); eq(Office("Councillor-Realm"), "H")
		w.authority("Author-Realm", "author"); eq(Office("Author-Realm"), "O", "the author's characters: another office")
		-- A guild master: on his own client the game's own rank; elsewhere Data.AuthorizedRank, never a
		-- census report alone (it gives no rank then) nor an officer's rank.
		eq(Office(c.me), "M")
		w.units.player.rank = 0; eq(Office(c.me), "G", "rank 0 in an Olympus guild, as the game says")
		eq(Office(c.me, "Not A Guild"), "M", "no Olympus guild, no guild master")
		w.units.player.rank = 1; eq(Office(c.me), "M", "a guild officer's rank is no office")
		local ranks = {}
		c.Data.AuthorizedRank = function(name, guild) return ranks[c.Fold(c.FullName(name)) .. "@" .. guild] end
		eq(Office("Master-Realm"), "M", "no authorized rank (one census report)")
		ranks[c.Fold(c.FullName("Master-Realm")) .. "@Olympus II"] = 0
		eq(Office("Master-Realm"), "G")
		w.authority("Master-Realm", "council"); eq(Office("Master-Realm"), "H", "a guild master who is a councillor: the highest")
		eq(B.DeathPoints(Office("Master-Realm"), 58), 108)
		-- Where no King is pinned: the master of the King's guild (Borders' rule).
		c.KingCharacter = function() return nil end
		c.IsKingGuild = function(guild) return guild == "Olympus" end
		ranks[c.Fold(c.FullName("Founder-Realm")) .. "@Olympus"] = 0
		eq(Office("Founder-Realm", "Olympus"), "K")
		c.KingCharacter = function() return "Someone" end
		eq(Office("Founder-Realm", "Olympus"), "G", "a King pinned: the master is a guild master")
		-- A centurion or a correspondent from his master's own list (a stale list gives nobody).
		local roles = {}
		c.Nominees = { RoleOf = function(name) return roles[c.Fold(c.FullName(name))] end }
		roles[c.Fold(c.FullName("Centurion-Realm"))] = "centurion"; eq(Office("Centurion-Realm"), "C")
		roles[c.Fold(c.FullName("Writer-Realm"))] = "correspondent"; eq(Office("Writer-Realm"), "O")
		roles[c.Fold(c.FullName("Centurion-Realm"))] = nil; eq(Office("Centurion-Realm"), "M")
		-- The signed titles, the King's Hands, the Treasurer's characters.
		c.IsSteward, c.IsSignedArbiter = Named("Steward-Realm"), Named("Arbiter-Realm")
		c.IsTreasurerCharacter, c.King = Named("Treasurer-Realm"), { IsHandName = Named("Hand-Realm") }
		for _, who in ipairs({ "Steward-Realm", "Arbiter-Realm", "Treasurer-Realm", "Hand-Realm" }) do eq(Office(who), "O", who) end
		-- What a shared row says, taken no higher than this client verifies and sees.
		local K = w.commHandlers.WK
		local boaster = w.participant("Boaster-Realm", "Player-1-CC00D001")
		local n = 0
		local function Row(from, own, worth, kind)
			n = n + 1
			w.advance(W.Bounty.SCORE.REPEAT_GAP + 1)
			local horde = ("Player-1-0D00D0%02d"):format(n)
			local ok, e = K("CHANNEL", from, BountyRow(c, W, { digest = ("%016x"):format(0xd000 + n), at = w.epoch, kind = kind,
				horde = ("1.0d00d0%02d"):format(n), own = own, worth = worth, name = "Horde" .. n .. "-Realm" }))
			assert(ok, tostring(e))
			return W.Target(nil, horde), e
		end
		eq(Row(boaster, "1.cc00d001", "K~40~0").current, 40, "a member who says he is the King: his level alone")
		c.Roster.Fresh = function() return { members = { { full = boaster, level = 40 } } } end
		-- (1.2.3 repair, changed on purpose: the roster is up to Roster.AUTHORITY_FRESH old, so a
		-- member who levelled since counts his level, as on every client without the roster: 41.)
		eq(Row(boaster, "1.cc00d001", "M~60~0").current, 40 + B.ROSTER_SLACK, "60 said, 40 on this client's own guild's fresh roster: 41 at most")
		local crowned = w.participant("Crowned-Realm", "Player-1-CC00D002")
		eq(Row(crowned, "1.cc00d002", "M~60~0").current, 60, "the King who says less counts less: never above the row")
		eq(Row(crowned, "1.cc00d002", "K~60~0").current, 160)
		-- The Horde player's level no higher than this client sees of him now (a nameplate).
		w.hordePlayer("Horde5-Realm", "Player-1-0D00D005")
		w.units.nameplate2 = { name = "Horde5-Realm", guid = "Player-1-0D00D005", faction = "Horde", level = 50 }
		local t, e = Row(crowned, "1.cc00d002", "K~60~60", "P")
		eq(e.hl, 50); eq(t.claims[1].points, 5, "60 said, 50 seen: ceil(50 / 10)")
	end)
end)

test("wanted 1.2.3 bounty: corpse camping counts once in 10 minutes (the deaths in between stay, worth nothing), a bounty cycle holds BOUNTY_MAX and a Slayer MAX_POINTS", function()
	WithWanted(function(w, W, c)
		w.manager = false
		w.units.player.level = 40
		local camper = "Player-1-0D00E001"
		w.hordePlayer("Camper-Realm", camper)
		for i = 1, 3 do
			if i > 1 then w.advance(240) end
			w.die(w.forever("Camper-Realm", camper))
		end
		local t = W.Target(nil, camper)
		-- (1.2.4, changed on purpose, the author's report "3 kills, 18 points": the kills count as the
		-- points do, one. Before: 3.)
		eq(t.current, 40, "a plain level-40 member, three times in 8 minutes: 40 (before: 3)"); eq(t.lifetimeKills, 1)
		eq(#t.victims, 3, "the two others stay, as provenance"); eq(t.victims[1].points, 40); eq(t.victims[2].points, 0); eq(t.victims[3].points, 0)
		w.advance(W.Bounty.SCORE.REPEAT_GAP - 480)
		w.die(w.forever("Camper-Realm", camper))
		eq(W.Target(nil, camper).current, 80, "10 minutes after the one that counted, once more")
		-- Another member killed by him meanwhile has a gap of his own.
		local mate = w.participant("Mate-Realm", "Player-1-CC00E001")
		assert(w.commHandlers.WK("CHANNEL", mate, BountyRow(c, W, { digest = "00000000000e0001", at = w.epoch + W.DEATH_WINDOW + 1,
			horde = "1.0d00e001", own = "1.cc00e001", worth = "M~30~0", name = "Camper-Realm" })))
		eq(W.Target(nil, camper).current, 110)
		-- One cycle holds BOUNTY_MAX (here 120: the cap itself, not its 2000).
		W.Bounty.SCORE.BOUNTY_MAX = 120
		w.advance(W.Bounty.SCORE.REPEAT_GAP)
		w.die(w.forever("Camper-Realm", camper))
		t = W.Target(nil, camper)
		eq(t.current, 120); eq(t.victims[#t.victims].points, 10, "what it could still add")
		-- A Slayer holds MAX_POINTS (here 200).
		W.MAX_POINTS = 200
		w.advance(W.DEATH_WINDOW + 1)
		w.units.target = { name = "Camper-Realm", guid = camper, faction = "Horde", level = 60 }
		local ok, e = w.handlers.PARTY_KILL(w.units.player.guid, camper)
		assert(ok, tostring(e)); eq(e.points, 6 + 120 + 100, "his level base, the bounty, the revenge")
		eq(W.Rankings().all[1].points, 200, "his Slayer's row holds 200")
	end)
end)

-- 1.2.4, the author's report on the preview: "3 kills that seem to be of the same person, and only
-- 18 points", and "many with 0 points, 0 kills: with 0 points and 0 kills he should not be on the
-- Most Wanted list". The tab's row, its tooltip, his page, the API's rows and /oly wanted status.
local function WantedRow(W, guid)
	for _, line in ipairs((W.Build())) do if line.id == "wanted:g:" .. guid then return line end end
	return nil
end
local function TipText(line)
	local tip = Tooltip()
	line.tooltip(tip)
	return table.concat(tip.lines, "\n")
end

test("wanted 1.2.4 (the author's report: 3 kills of the same member, 18 points): the kills count as the points do: the same member killed again by the same Horde player within 10 minutes is one kill on the tab's row, its tooltip, his page and /oly wanted status, after a reload too; the deaths in between stay on his page, marked as not counted", function()
	WithWanted(function(w, W, c)
		w.manager = false
		w.units.player.level = 18
		local camper = "Player-1-0D00E101"
		w.hordePlayer("Camper-Realm", camper)
		for i = 1, 3 do
			if i > 1 then w.advance(240) end
			w.die(w.forever("Camper-Realm", camper))
		end
		local t = W.Target(nil, camper)
		eq(t.current, 18, "a plain level-18 member, three times in 8 minutes: 18")
		eq(t.lifetimeKills, 1, "one kill, as the points count it (before: 3)")
		local row = assert(WantedRow(W, camper), "on Most Wanted")
		eq(row.right, ns.L.WANTED_ROW_COUNTS:format(18, 1))
		local tip = TipText(row)
		assert(tip:find(ns.L.WANTED_LIFETIME:format(1), 1, true), tip)
		assert(tip:find(ns.L.WANTED_REPEATS:format(3, 1, 10), 1, true), tip)
		local _, marked = tip:gsub(ns.L.WANTED_AGAIN_SHORT:gsub("%p", "%%%0"), "")
		eq(marked, 2, "the two deaths in between, marked in the tooltip")
		-- His page: his one kill, and the three deaths, the two in between said so.
		assert(W.OpenTarget(nil, camper))
		local page = W.Build()
		local kills, counted, again = nil, 0, 0
		for _, line in ipairs(page) do
			if line.right == ns.L.WANTED_LIFETIME:format(1) then kills = line end
			if line.text == c.DisplayName(c.me) and type(line.right) == "string" then
				if line.right:find(ns.L.WANTED_VICTIM_POINTS:format(18, ""), 1, true) then counted = counted + 1 end
				if line.right:find(ns.L.WANTED_VICTIM_AGAIN:format(""), 1, true) then
					again = again + 1
					local vt = Tooltip(); line.tooltip(vt)
					assert(table.concat(vt.lines, "\n"):find(ns.L.WANTED_VICTIM_AGAIN_TIP:format(10), 1, true), "why it did not count")
				end
			end
		end
		assert(kills, "his page: one kill")
		eq(counted, 1, "the death that counted, +18"); eq(again, 2, "the two in between: again, not counted")
		W.Back()
		-- /oly wanted status: his bounty row, and each death in between said so.
		local status = W.StatusText()
		assert(status:find(ns.L.WANTED_STATUS_BOUNTY_ROW:format(c.DisplayName("Camper-Realm"), 18, 1), 1, true), status)
		local _, told = status:gsub(ns.L.WANTED_STATUS_AGAIN:format(10):gsub("%p", "%%%0"), "")
		eq(told, 2, status)
		-- After a reload: the same (the totals are built again from the saved rows).
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted; assert(W.Load())
		t = W.Target(nil, camper)
		eq(t.current, 18); eq(t.lifetimeKills, 1)
		eq(WantedRow(W, camper).right, ns.L.WANTED_ROW_COUNTS:format(18, 1))
		-- Ten minutes after the one that counted: a second kill, and its points.
		w.advance(W.Bounty.SCORE.REPEAT_GAP - 480)
		w.die(w.forever("Camper-Realm", camper))
		eq(WantedRow(W, camper).right, ns.L.WANTED_ROW_COUNTS:format(36, 2))
		-- Another member's deaths to him, heard: his own gap, the same rule.
		local mate = w.participant("Mate-Realm", "Player-1-CC00E101")
		for i, digest in ipairs({ "00000000000e1001", "00000000000e1002" }) do
			w.advance(i == 1 and W.DEATH_WINDOW + 1 or 120)
			assert(w.commHandlers.WK("CHANNEL", mate, BountyRow(c, W, { digest = digest, at = w.epoch,
				horde = "1.0d00e101", own = "1.cc00e101", worth = "M~30~0", name = "Camper-Realm" })))
		end
		t = W.Target(nil, camper)
		eq(t.current, 66, "his first death adds 30, the one two minutes later nothing")
		eq(t.lifetimeKills, 3, "and one kill")
		eq(WantedRow(W, camper).right, ns.L.WANTED_ROW_COUNTS:format(66, 3))
		-- A bounty at its cap still counts the kill (the death counted; only the points stop).
		W.Bounty.SCORE.BOUNTY_MAX = 66
		w.advance(W.Bounty.SCORE.REPEAT_GAP)
		w.die(w.forever("Camper-Realm", camper))
		t = W.Target(nil, camper)
		eq(t.current, 66); eq(t.lifetimeKills, 4, "a fourth kill, at the cap")
	end)
end)

test("wanted 1.2.4 (the author's report: many on Most Wanted with 0 points and 0 kills): a Horde player a member killed who killed none of ours is not wanted: off the tab's list and /oly wanted status's count, while his entry keeps the claim and its Slayer's points; he is listed the moment he kills a member, and stays listed for his kill once his bounty is claimed", function()
	WithWanted(function(w, W, c)
		w.manager = false
		w.units.player.level = 40
		local me = w.units.player.guid
		local prey = "Player-1-0D00E201"
		w.hordePlayer("Prey-Realm", prey)
		w.units.target = { name = "Prey-Realm", guid = prey, faction = "Horde", level = 30 }
		local ok, e = w.handlers.PARTY_KILL(me, prey)
		w.units.target = nil
		assert(ok, tostring(e)); eq(e.action, "claim"); eq(e.points, 3, "one rounded base point per ten levels, for the Slayer")
		local t = assert(W.Target(nil, prey), "his entry holds the claim")
		eq(t.active, true); eq(#t.claims, 1); eq(t.current, 0); eq(t.lifetimeKills, 0)
		eq(W.Rankings().all[1].points, 3, "the kill counts on the Slayers board")
		eq(#w.wire("WK~2~"), 1, "and goes to every member")
		-- Another member's killing blow on another Horde player, heard: the same.
		local other = w.participant("Hunter-Realm", "Player-1-CC00E201")
		w.hordePlayer("Other Prey-Realm", "Player-1-0D00E202")
		assert(w.commHandlers.WK("CHANNEL", other, BountyRow(c, W, { digest = "00000000000e2001",
			at = w.epoch, kind = "P", horde = "1.0d00e202", own = "1.cc00e201", worth = "M~50~25", name = "Other Prey-Realm" })))
		eq(W.Target(nil, "Player-1-0D00E202").claims[1].points, 3)
		eq(#W.Rankings().all, 2, "both Slayers")
		-- Neither is on Most Wanted: 0 points and 0 kills.
		eq(WantedRow(W, prey), nil, "not wanted: he killed none of ours")
		eq(WantedRow(W, "Player-1-0D00E202"), nil)
		local empty = false
		for _, line in ipairs((W.Build())) do if line.text and line.text:find(ns.L.WANTED_EMPTY, 1, true) then empty = true end end
		assert(empty, "the list says nobody is wanted yet")
		local status = W.StatusText()
		assert(status:find(ns.L.WANTED_STATUS_STORE:format("RealmGroup", "Alliance", 0, 2, 0, 2, 2, ns.L.WANTED_STATUS_YES), 1, true), status)
		assert(status:find(ns.L.WANTED_STATUS_NONE, 1, true), "no bounty")
		-- He kills a member (this client's player): wanted at once, for his bounty and his kill.
		w.advance(W.DEATH_WINDOW + 1)
		w.die(w.forever("Prey-Realm", prey))
		eq(WantedRow(W, prey).right, ns.L.WANTED_ROW_COUNTS:format(40, 1))
		status = W.StatusText()
		assert(status:find(ns.L.WANTED_STATUS_STORE:format("RealmGroup", "Alliance", 1, 1, 0, 3, 2, ns.L.WANTED_STATUS_YES), 1, true), status)
		-- Killed for his bounty: a new cycle at 0 points, and still wanted for the member he killed.
		w.advance(W.DEATH_WINDOW + 1)
		w.units.target = { name = "Prey-Realm", guid = prey, faction = "Horde", level = 30 }
		ok, e = w.handlers.PARTY_KILL(me, prey)
		w.units.target = nil
		assert(ok, tostring(e)); eq(e.points, 40, "his bounty alone: this member was paid his level within the hour")
		eq(W.Target(nil, prey).current, 0)
		eq(WantedRow(W, prey).right, ns.L.WANTED_ROW_COUNTS:format(0, 1), "0 points and 1 kill: listed")
		-- After a reload: the same list.
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted; assert(W.Load())
		assert(WantedRow(W, prey), "still listed")
		eq(WantedRow(W, "Player-1-0D00E202"), nil, "still not")
		eq(#W.Rankings().all, 2)
	end)
end)

-- (1.2.4, changed on purpose: an entry a reviewer's void left with nothing, and one listed by hand
-- before 1.2.3 that never counted anything, are 0 points and 0 kills: not on the list either.)
test("wanted 1.2.4: an entry with nothing counted is not on Most Wanted: one listed by hand that never counted anything, or one whose only death a reviewer voided", function()
	WithWanted(function(w, W, c)
		assert(w.add("Hand-Realm", "Player-1-0D00E301"))
		eq(W.Target(nil, "Player-1-0D00E301").active, true)
		eq(WantedRow(W, "Player-1-0D00E301"), nil, "listed by hand, nothing counted: not wanted")
		local sender = w.participant("Voided-Realm", "Player-1-CC00E301")
		assert(w.commHandlers.WK("CHANNEL", sender, BountyRow(c, W, { digest = "00000000000e3001", at = w.epoch,
			horde = "1.0d00e302", own = "1.cc00e301", worth = "M~20~0", name = "Voided Horde-Realm" })))
		eq(WantedRow(W, "Player-1-0D00E302").right, ns.L.WANTED_ROW_COUNTS:format(20, 1))
		local king = w.authority("Kingly-Realm", "king")
		assert(w.commHandlers.WV("CHANNEL", king, ("WV~V~1~%s~%s~00000000000e3001~%d"):format(ScopeOf(c), sender, w.epoch)))
		eq(W.Target(nil, "Player-1-0D00E302").current, 0, "voided")
		eq(WantedRow(W, "Player-1-0D00E302"), nil, "nothing counted any more: off the list")
	end)
end)

test("wanted 1.2.3 bounty: old rows count as they always did (a WK~1 row: 1 a death, a kill its bounty alone, no level, no revenge); a WK~1 and a WK~2 copy of one row are one; a malformed worth is refused; a saved row without it counts so after a reload", function()
	WithWanted(function(w, W, c)
		local K = w.commHandlers.WK
		local scope = ScopeOf(c)
		local old = w.participant("Oldclient-Realm", "Player-1-CC00F001")
		local function V1(o)
			return table.concat({ "WK", 1, scope, "Olympus II", o.digest, o.at or w.epoch, W.MonthNow(), o.kind or "S", o.horde, "1.cc00f001", o.name }, "~")
		end
		assert(K("CHANNEL", old, V1({ digest = "00000000000f0001", horde = "1.0d00f001", name = "Legacy-Realm" })))
		eq(W.Target(nil, "Player-1-0D00F001").current, 1, "1 a death")
		eq(select(2, K("CHANNEL", old, BountyRow(c, W, { digest = "00000000000f0001", at = w.epoch, horde = "1.0d00f001",
			own = "1.cc00f001", worth = "K~60~60", name = "Legacy-Realm" }))), "replay", "its WK~2 copy: the same row")
		w.advance(W.DEATH_WINDOW + 1)
		assert(K("CHANNEL", old, V1({ digest = "00000000000f0002", kind = "P", horde = "1.0d00f001", name = "Legacy-Realm" })))
		local claim = W.Target(nil, "Player-1-0D00F001").claims[1]
		eq(claim.points, 1, "his bounty alone, though he killed his own killer"); eq(claim.revenge, nil)
		for _, bad in ipairs({ "X~40~0", "M~4000~0", "M~40~0+", "M~40", "M~40~0~1" }) do
			eq(select(2, K("CHANNEL", old, BountyRow(c, W, { digest = "00000000000f0003", at = w.epoch, horde = "1.0d00f003",
				own = "1.cc00f001", worth = bad, name = "Bad-Realm" }))), "shape", bad)
		end
		-- A row an older build saved, without what it is worth: 1 a death after a reload, as then; a
		-- saved worth that is malformed is not trusted either.
		w.units.player.level = 50
		local saved, broken = "Player-1-0D00F004", "Player-1-0D00F005"
		w.hordePlayer("Saved-Realm", saved); w.hordePlayer("Broken-Realm", broken)
		w.advance(W.DEATH_WINDOW + 1); w.die(w.forever("Saved-Realm", saved))
		w.advance(W.DEATH_WINDOW + 1); w.die(w.forever("Broken-Realm", broken))
		eq(W.Target(nil, saved).current, 50); eq(W.Target(nil, broken).current, 50)
		for _, e in ipairs(c.rdb.wanted.evidence) do
			if e.targetKey == "g:" .. saved then e.office, e.ml, e.hl, e.hf = nil, nil, nil, nil end
			if e.targetKey == "g:" .. broken then e.office = "Z" end
		end
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted
		assert(W.Prune())
		eq(W.Target(nil, saved).current, 1, "a saved row without what it is worth: 1")
		eq(W.Target(nil, broken).current, 1, "a malformed one: the same")
	end)
end)

test("wanted 1.2.3 earlier deaths: at login the death recaps the game still holds count once each, through the live death's own gate (a creature's, one inside an instance, one counted already: none), shared like a live death, and the member is told once in an Olympus copy window, never the game's popups", function()
	WithWanted(function(w, W, c)
		w.manager = false
		w.units.player.level = 40
		local timers = {}
		c.After = function(seconds, label, fn) timers[#timers + 1] = { seconds = seconds, label = label, fn = fn } end
		local function Fire(label)
			for i, t in ipairs(timers) do if t.label == label then table.remove(timers, i) t.fn() return t.seconds end end
		end
		local shown = {}
		c.UI.ShowCopy = function(title, text, action, opts) shown[#shown + 1] = { title = title, text = text, action = action, opts = opts } return true end
		local live, early, battle, later = "Player-1-0D00A001", "Player-1-0D00A002", "Player-1-0D00A003", "Player-1-0D00A004"
		w.hordePlayer("Live Ganker-Realm", live); w.hordePlayer("Early Ganker-Realm", early)
		w.hordePlayer("Battle Ganker-Realm", battle); w.hordePlayer("Later Ganker-Realm", later)
		-- (1.2.3 repair: this client has noted its instances since this game session began, so it
		-- knows where its player was at each death: Bounty.Tracked, the test after the next ones.)
		W.Bounty.Spans()
		-- A death counted when it happened.
		local liveRows = w.forever("Live-Realm", live)
		w.die(liveRows)
		w.dead = false
		eq(W.Target(nil, live).current, 40)
		-- Deaths the client did not count then (this session's, before 1.2.3 ran, say), and a time
		-- in a battleground, as this client noted it at its changes of zone.
		local recaps = {}
		w.advance(600); recaps[3] = w.forever("Early-Realm", early)
		w.advance(300); recaps[4] = { { event = "SWING_DAMAGE", sourceGUID = "Creature-0-1-2-3-4-0000ABCDEF", sourceName = "Wolf",
			overkill = 5, timestamp = w.epoch - 0.2 } }
		w.advance(100); w.inside = true; W.Bounty.Zone()
		w.advance(100); recaps[5] = w.forever("Battle-Realm", battle)
		w.advance(100); w.inside = false; W.Bounty.Zone()
		recaps[6] = liveRows
		w.advance(600); recaps[7] = w.forever("Later-Realm", later)
		assert(w.handlers.ZONE_CHANGED_NEW_AREA and w.handlers.PLAYER_ENTERING_WORLD, "the zone's events reach it")
		-- The game holds IDs 3 to 7 (the oldest went); the latest is also the one without an ID.
		-- (1.2.3 repair: its damage meter shows them as this player's own deaths; an ID alone proves
		-- no death is his, the test after the next ones.)
		C_DeathInfo = nil
		C_DeathRecap = {
			HasRecapEvents = function(id) return id == nil or recaps[id] ~= nil end,
			GetRecapEvents = function(id) return recaps[id or 7] or {} end,
		}
		w.meter({ { 3, true }, { 4, true }, { 5, true }, { 6, true }, { 7, true } })
		w.advance(3600)
		local before = #w.wire("WK~2~")
		assert(W.Load())
		eq(Fire("wanted earlier deaths"), W.Bounty.EARLIER_WAIT, "read a moment after login")
		local first, second = W.Target(nil, early), W.Target(nil, later)
		assert(first and second, "both earlier deaths count")
		eq(first.current, 40); eq(second.current, 40, "his office and level, frozen at the reading")
		eq(first.victims[1].at, math.floor(recaps[3][1].timestamp), "at the time of the death")
		eq(W.Target(nil, battle), nil, "inside a battleground then: never")
		eq(W.Target(nil, live).current, 40, "the one counted when it happened, once")
		eq(#w.wire("WK~2~") - before, 2, "each shared like a live death")
		for _, n in ipairs({ 3, 4, 5, 6, 7 }) do
			local kb = W.Bounty.KillingBlow(recaps[n])
			assert(c.rdb.wanted.recapsRead[kb.key], "recap " .. n .. " marked read")
		end
		-- One notice: an Olympus copy window, opened by itself (it takes no keyboard), never the
		-- game's popups; the deaths in their order, each its killer, his level, the time, the points.
		eq(#shown, 1); eq(#w.dialogs, 0, "no popup")
		eq(shown[1].title, ns.L.WANTED_EARLIER_TITLE); eq(shown[1].opts.auto, true); eq(shown[1].opts.key, "wanted-earlier")
		local text = shown[1].text
		local rowEarly = ns.L.WANTED_EARLIER_ROW:format(c.DisplayName("Early Ganker-Realm"), ns.L.WANTED_LEVEL_UNKNOWN,
			os.date("%H:%M", math.floor(recaps[3][1].timestamp)), 40)
		local rowLater = ns.L.WANTED_EARLIER_ROW:format(c.DisplayName("Later Ganker-Realm"), ns.L.WANTED_LEVEL_UNKNOWN,
			os.date("%H:%M", math.floor(recaps[7][1].timestamp)), 40)
		eq(text, table.concat({ ns.L.WANTED_EARLIER_INTRO, "", rowEarly, rowLater, "", ns.L.WANTED_EARLIER_END }, "\n"))
		eq(c.rdb.wanted.earlierNotice, nil, "shown: gone")
		-- /oly wanted status says what was read: the three by a player (the creature's is no line).
		local status = W.StatusText()
		assert(status:find(ns.L.WANTED_STATUS_EARLIER_LINE:format(3, 2), 1, true), status)
		assert(status:find("  " .. ns.L.WANTED_STATUS_EARLIER .. "  Later Ganker-Realm  " .. ns.L.WANTED_STATUS_BOUNTY:format(40), 1, true), status)
		assert(status:find("  " .. ns.L.WANTED_STATUS_EARLIER .. "  Battle-Realm  " .. ns.L.WANTED_STATUS_REFUSAL:format("instance"), 1, true), status)
		-- The next login, and after a reload: nothing more, no notice.
		assert(W.Load()); Fire("wanted earlier deaths")
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted
		assert(W.Load()); Fire("wanted earlier deaths")
		eq(#shown, 1); eq(#w.wire("WK~2~") - before, 2); eq(W.Target(nil, early).current, 40)
	end)
end)

test("wanted 1.2.3 earlier deaths: their notice waits out combat, an instance, a death and the privacy page (shown or waiting), then shows once; a /reload before it never loses it", function()
	WithWanted(function(w, W, c)
		w.manager = false
		w.units.player.level = 40
		local timers = {}
		c.After = function(seconds, label, fn) timers[#timers + 1] = { seconds = seconds, label = label, fn = fn } end
		local function Fire(label)
			for i, t in ipairs(timers) do if t.label == label then table.remove(timers, i) t.fn() return t.seconds end end
		end
		local shown = 0
		c.UI.ShowCopy = function(title) if title == ns.L.WANTED_EARLIER_TITLE then shown = shown + 1 end return true end
		local ganker = "Player-1-0D00A101"
		w.hordePlayer("Waiting Ganker-Realm", ganker)
		W.Bounty.Spans() -- (1.2.3 repair: its instances noted since the game session began)
		w.advance(60)
		local rows = w.forever("Waiting-Realm", ganker)
		C_DeathInfo = nil
		C_DeathRecap = { HasRecapEvents = function(id) return id == nil or id == 1 end, GetRecapEvents = function() return rows end }
		w.dead = false
		w.advance(1200)
		w.combat = true
		assert(W.Load())
		-- (1.2.3 repair, changed on purpose: in combat the reading waits too, as the damage meter's
		-- sessions, its own deaths' recap IDs, are secret then; it is tried again NOTICE_TICK later.
		-- Before, it read at once in combat.)
		eq(Fire("wanted earlier deaths"), W.Bounty.EARLIER_WAIT)
		eq(W.Target(nil, ganker), nil, "in combat: the reading waits")
		w.combat, w.consentWaiting = false, true
		eq(Fire("wanted earlier deaths"), W.Bounty.NOTICE_TICK)
		eq(W.Target(nil, ganker).current, 40, "out of combat: counted at once")
		eq(shown, 0, "the privacy page to ask: it waits")
		eq(Fire("wanted earlier notice"), W.Bounty.NOTICE_TICK); eq(shown, 0)
		-- A /reload meanwhile: it is saved, and still waits.
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted
		timers = {}
		assert(W.Load())
		Fire("wanted earlier deaths")
		eq(shown, 0)
		for _, case in ipairs({ { "combat", true }, { "inside", true }, { "dead", true }, { "consentWaiting", true }, { "consentShown", true } }) do
			w.combat, w.inside, w.dead, w.consentWaiting, w.consentShown = false, false, false, false, false
			w[case[1]] = case[2]
			assert(Fire("wanted earlier notice"), case[1] .. ": tried again later")
			eq(shown, 0, case[1])
		end
		w.consentShown = false
		Fire("wanted earlier notice")
		eq(shown, 1, "nothing in the way: shown")
		eq(Fire("wanted earlier notice"), nil, "and done")
		assert(W.Load()); Fire("wanted earlier deaths"); Fire("wanted earlier notice")
		eq(shown, 1, "once")
	end)
end)

test("wanted 1.2.3 earlier deaths: the newest EARLIER_MAX at a reading, so every member's client takes them within its limit for one member; the rest at another reading EARLIER_AGAIN later in the same session (a logout empties the game's recaps), each once, and one notice for them all", function()
	WithWanted(function(w, W, c)
		w.manager, w.dead = false, false
		w.units.player.level = 20
		local timers = {}
		c.After = function(seconds, label, fn) timers[#timers + 1] = { seconds = seconds, label = label, fn = fn } end
		local function Fire(label)
			for i, t in ipairs(timers) do if t.label == label then table.remove(timers, i) t.fn() return t.seconds end end
		end
		local shown = {}
		c.UI.ShowCopy = function(title, text) if title == ns.L.WANTED_EARLIER_TITLE then shown[#shown + 1] = text end return true end
		W.Bounty.Spans() -- (its instances noted since the game session began)
		local recaps = {}
		for i = 1, 9 do
			local guid = ("Player-1-0D00A3%02d"):format(i)
			w.hordePlayer("Many" .. i .. "-Realm", guid)
			w.advance(60)
			recaps[i] = w.forever("Many" .. i .. "-Realm", guid)
			-- (Rows of the combat log's shape, where the game's rows carry it: they name their victim,
			-- this player, so a recap ID the game answers for is his.)
			for _, row in ipairs(recaps[i]) do row.destGUID = w.units.player.guid end
		end
		assert(W.Bounty.EARLIER_MAX < W.SHARE_RATE_MAX, "within a receiver's limit for one member")
		C_DeathInfo = nil
		C_DeathRecap = { HasRecapEvents = function(id) return id == nil or recaps[id] ~= nil end,
			GetRecapEvents = function(id) return recaps[id or 9] or {} end }
		w.advance(600)
		assert(W.Load())
		eq(Fire("wanted earlier deaths"), W.Bounty.EARLIER_WAIT)
		eq(#w.wire("WK~2~"), W.Bounty.EARLIER_MAX)
		eq(W.Target(nil, "Player-1-0D00A309").current, 20); eq(W.Target(nil, "Player-1-0D00A304").current, 20)
		eq(W.Target(nil, "Player-1-0D00A303"), nil, "the oldest wait"); eq(W.Target(nil, "Player-1-0D00A301"), nil)
		eq(#shown, 0, "the notice waits for the session's reading to end: one notice")
		-- (1.2.3 repair: before, the rest waited for the next login, but a logout empties the game's
		-- death recaps: without a /reload first they were lost.)
		eq(Fire("wanted earlier deaths"), W.Bounty.EARLIER_AGAIN, "read again in the same session, past every receiver's window for one member")
		assert(W.Bounty.EARLIER_AGAIN >= W.SHARE_RATE_WINDOW)
		eq(#w.wire("WK~2~"), 9); eq(W.Target(nil, "Player-1-0D00A301").current, 20); eq(W.Target(nil, "Player-1-0D00A303").current, 20)
		eq(#shown, 1, "told once, every death added")
		local lines = 0
		for line in shown[1]:gmatch("[^\n]+") do if line:find("+20", 1, true) then lines = lines + 1 end end
		eq(lines, 9)
		assert(shown[1]:find("Many1", 1, true) < shown[1]:find("Many9", 1, true), "the oldest death first")
		eq(Fire("wanted earlier deaths"), nil, "no reading more")
		assert(W.Load()); Fire("wanted earlier deaths")
		eq(#w.wire("WK~2~"), 9, "none twice"); eq(#shown, 1)
	end)
end)

test("wanted 1.2.3 earlier deaths world: a member back with this session's deaths in the game's recaps counts them on every client at once, the same points everywhere", function()
	WithWorld(function(world)
		local king = world:Client("Varrick-Realm", "Player-1-0A0000D1", "king")
		local back = world:Client("Back-Realm", "Player-1-0A0000D2")
		local horde = "Player-1-0B0000D1"
		world.horde[horde] = "Recapped-Realm"
		back.units.player.level = 35
		-- (1.2.3 repair: a death 900 s ago, after his client began noting its instances: Bounty.Tracked.)
		world.epoch = world.epoch + 1000
		back.recap = { { event = "SPELL_DAMAGE", sourceGUID = horde, sourceName = "Recapped-Realm", sourceFlags = 0x548,
			overkill = 12, timestamp = world.epoch - 900 } }
		world:Load(back) -- (a /reload: the recaps are the game's, still there)
		world:Run(back.W.Bounty.EARLIER_WAIT + 1)
		for _, cl in ipairs({ king, back }) do
			local t = world:As(cl, cl.W.Target, nil, horde)
			assert(t, cl.name); eq(t.current, 35, cl.name); eq(t.victims[1].name, back.name)
		end
		eq(#(back.copies or {}), 1, "told once"); eq(back.copies[1].title, ns.L.WANTED_EARLIER_TITLE); eq(back.copies[1].opts.auto, true)
		eq(king.copies, nil, "nobody else is told")
	end)
end)

-- 1.2.3 repair (the bounty branch's review): each test below fails on the branch before it.
local function Timers(c)
	local timers = {}
	c.After = function(seconds, label, fn) timers[#timers + 1] = { seconds = seconds, label = label, fn = fn } end
	return function(label)
		for i, t in ipairs(timers) do if t.label == label then table.remove(timers, i) t.fn() return t.seconds end end
	end
end

test("wanted 1.2.3 repair: a death recap that is not this player's own (a party member's: Forever's damage meter keeps a recap ID for every death in the group) is never counted, shared, told or marked read, and opens no grudge; the latest recap, an ID the damage meter shows as his and one whose rows name him count", function()
	WithWanted(function(w, W, c)
		w.manager, w.dead = false, false
		w.units.player.level = 40
		local Fire = Timers(c)
		local shown = {}
		c.UI.ShowCopy = function(title, text) if title == ns.L.WANTED_EARLIER_TITLE then shown[#shown + 1] = text end return true end
		W.Bounty.Spans() -- (its instances noted since the game session began)
		local mate = "Player-1-CC00B001" -- a party member, killed while this player lived
		local function Horde(i)
			local guid = ("Player-1-0D00B1%02d"):format(i)
			w.hordePlayer("Partykiller" .. i .. "-Realm", guid)
			return guid
		end
		local named, meterOther, bare, meterMine, latest = Horde(1), Horde(2), Horde(3), Horde(4), Horde(5)
		local recaps = {}
		w.advance(60); recaps[1] = w.forever("Partykiller1-Realm", named)
		for _, row in ipairs(recaps[1]) do row.destGUID = mate end -- (rows that name their victim: the mate)
		w.advance(60); recaps[2] = w.forever("Partykiller2-Realm", meterOther) -- (the mate's death in the damage meter)
		w.advance(60); recaps[3] = w.forever("Partykiller3-Realm", bare) -- (no row names a victim, the meter has it not)
		w.advance(60); recaps[4] = w.forever("Partykiller4-Realm", meterMine) -- (our own death in the damage meter)
		w.advance(60); recaps[5] = w.forever("Partykiller5-Realm", latest) -- (our latest death: the recap without an ID)
		C_DeathInfo = nil
		C_DeathRecap = { HasRecapEvents = function(id) return id == nil or recaps[id] ~= nil end,
			GetRecapEvents = function(id) return recaps[id or 5] or {} end }
		w.meter({ { 2, false }, { 4, true }, { 5, true } })
		w.advance(600)
		assert(W.Load())
		Fire("wanted earlier deaths")
		eq(W.Target(nil, named), nil, "a recap whose rows name another victim (before: counted as this player's death)")
		eq(W.Target(nil, meterOther), nil, "another's death in the damage meter")
		eq(W.Target(nil, bare), nil, "an ID the game answers for, nothing showing it is ours")
		eq(W.Target(nil, meterMine).current, 40, "the damage meter's death of the local player")
		eq(W.Target(nil, latest).current, 40, "the latest recap")
		eq(#w.wire("WK~"), 2, "only ours shared")
		for _, n in ipairs({ 1, 2, 3 }) do eq(c.rdb.wanted.recapsRead[W.Bounty.KillingBlow(recaps[n]).key], nil, "recap " .. n .. ": not ours, not marked read") end
		eq(#shown, 1)
		for i = 1, 3 do eq(shown[1]:find("Partykiller" .. i, 1, true), nil, "not in the window: " .. i) end
		local why = W.ShareState().why
		eq(why.victim, 1); eq(why.unproven, 2)
		-- Nor a grudge: killing one of them pays his level alone.
		w.advance(W.DEATH_WINDOW + 1)
		w.units.target = { name = "Partykiller1-Realm", guid = named, faction = "Horde", level = 50 }
		local ok, e = w.handlers.PARTY_KILL(w.units.player.guid, named)
		w.units.target = nil
		assert(ok, tostring(e)); eq(e.revenge, nil); eq(e.points, 5)
		-- A later reading in the session: still nothing of the mate's, and no second window.
		assert(W.Load()); Fire("wanted earlier deaths")
		eq(W.Target(nil, bare), nil); eq(#w.wire("WK~"), 3); eq(#shown, 1)
		-- The live death reads the latest recap: rows that name another victim are refused there too.
		w.advance(W.Bounty.SCORE.REPEAT_GAP + 1)
		local rows = w.forever("Partykiller3-Realm", bare)
		for _, row in ipairs(rows) do row.destGUID = mate end
		w.die(rows)
		w.dead = false
		eq(W.Target(nil, bare), nil, "the live death's recap names the mate: not ours")
		eq(W.ShareState().log[#W.ShareState().log].why, "victim")
	end)
end)

test("wanted 1.2.3 repair: an earlier death from before this client noted its instances (the first /reload after the update, with battleground deaths earlier that session) is refused, never counted as a world death; one in a time it let go is refused too; Daniel's EARLIER_UNTRACKED takes them", function()
	local function Gulch(w, W, c)
		w.manager, w.dead = false, false
		w.units.player.level = 40
		-- On 1.2.2, two Warsong Gulch matches: five deaths to Horde players. Nothing noted where.
		local recaps = {}
		for i = 1, 5 do
			local guid = ("Player-1-0D00B2%02d"):format(i)
			w.hordePlayer("Gulch" .. i .. "-Realm", guid)
			w.advance(120)
			recaps[i] = w.forever("Gulch" .. i .. "-Realm", guid)
			for _, row in ipairs(recaps[i]) do row.destGUID = w.units.player.guid end
		end
		C_DeathInfo = nil
		C_DeathRecap = { HasRecapEvents = function(id) return id == nil or recaps[id] ~= nil end,
			GetRecapEvents = function(id) return recaps[id or 5] or {} end }
		w.advance(300) -- (he left the match, updated and typed /reload outside)
		local Fire = Timers(c)
		local shown = 0
		c.UI.ShowCopy = function(title) if title == ns.L.WANTED_EARLIER_TITLE then shown = shown + 1 end return true end
		assert(W.Load())
		Fire("wanted earlier deaths")
		local counted = 0
		for i = 1, 5 do if W.Target(nil, ("Player-1-0D00B2%02d"):format(i)) then counted = counted + 1 end end
		return counted, shown
	end
	WithWanted(function(w, W, c)
		local counted, shown = Gulch(w, W, c)
		eq(counted, 0, "no proof they were outside an instance (before: all five counted as world deaths)")
		eq(#w.wire("WK~"), 0, "none shared"); eq(shown, 0, "nothing added: no window")
		eq(W.ShareState().why.untracked, 5)
		assert(c.rdb.wanted.insideSince, "noted from now on")
	end)
	WithWanted(function(w, W, c)
		W.Bounty.EARLIER_UNTRACKED = true
		local counted, shown = Gulch(w, W, c)
		eq(counted, 5, "Daniel's other choice: taken"); eq(shown, 1)
	end)
	-- More instances than this client keeps: the oldest time let go is not known any more.
	WithWanted(function(w, W, c)
		w.manager, w.dead = false, false
		w.units.player.level = 40
		W.Bounty.Spans()
		local guid = "Player-1-0D00B2F1"
		w.hordePlayer("Dungeon-Realm", guid)
		w.advance(60); w.inside = true; W.Bounty.Zone()
		w.advance(60)
		local rows = w.forever("Dungeon-Realm", guid)
		w.advance(60); w.inside = false; W.Bounty.Zone()
		for _ = 1, W.Bounty.INSIDE_MAX do
			w.advance(60); w.inside = true; W.Bounty.Zone()
			w.advance(60); w.inside = false; W.Bounty.Zone()
		end
		eq(#c.rdb.wanted.inside, W.Bounty.INSIDE_MAX)
		C_DeathInfo = nil
		C_DeathRecap = { HasRecapEvents = function(id) return id == nil end, GetRecapEvents = function() return rows end }
		local Fire = Timers(c)
		c.UI.ShowCopy = function() return true end
		assert(W.Load()); Fire("wanted earlier deaths")
		eq(W.Target(nil, guid), nil, "in the first dungeon, a time let go (before: counted)")
		eq(W.ShareState().why.untracked, 1)
	end)
end)

test("wanted 1.2.3 repair world: a death and a kill of one Horde player in the same second count in the same order on every client (the death's bounty in that claim), whichever a client hears first", function()
	WithWorld(function(world)
		local a = world:Client("Fallen-Realm", "Player-1-0A0000E1")
		local b = world:Client("Avenger-Realm", "Player-1-0A0000E2")
		local third = world:Client("Third-Realm", "Player-1-0A0000E3")
		a.units.player.level, b.units.player.level, third.units.player.level = 40, 45, 30
		local everyone = { a, b, third }
		world.epoch = world.epoch + 100
		local function Death(horde)
			a.dead, a.recap = true, { { event = "SPELL_DAMAGE", sourceGUID = horde, sourceName = world.horde[horde], sourceFlags = 0x548,
				overkill = 30, timestamp = world.epoch + 0.4 } }
			world:As(a, a.events.PLAYER_DEAD)
			a.dead, a.recap = false, nil
		end
		local function Kill(horde)
			b.units.target = { name = world.horde[horde], guid = horde, faction = "Horde", level = 50 }
			assert(world:As(b, b.events.PARTY_KILL, b.guid, horde))
			b.units.target = nil
		end
		local function Same(horde, what)
			for _, cl in ipairs(everyone) do
				local t = world:As(cl, cl.W.Target, nil, horde)
				eq(t.current, 0, cl.name .. ", " .. what .. ": no bounty left open")
				eq(t.claims[#t.claims].points, 5 + 40, cl.name .. ", " .. what .. ": the death's bounty in the claim")
			end
		end
		-- A (level 40) dies to him, and in the same second B kills him (level 50 on his corpse):
		-- B's own client holds its claim before A's death reaches it.
		local first = "Player-1-0B0000E1"
		world.horde[first] = "Sametime-Realm"
		Death(first); Kill(first)
		world:Deliver()
		Same(first, "the death heard first")
		-- The kill first, then the death, in one second: every receiver hears the claim first.
		world.epoch = world.epoch + 60
		local second = "Player-1-0B0000E2"
		world.horde[second] = "Othertime-Realm"
		Kill(second); Death(second)
		world:Deliver()
		Same(second, "the claim heard first")
		for _, cl in ipairs(everyone) do eq(world:As(cl, cl.W.Rankings).all[1].points, 90, cl.name .. ": the same Slayers' points") end
	end)
end)

test("wanted 1.2.3 repair: a live death read a moment after it (the recap came late, a retry) is dated by its recap's killing blow, as an earlier death is", function()
	WithWanted(function(w, W)
		w.manager = false
		local guid = "Player-1-0D00B501"
		w.hordePlayer("Late-Realm", guid)
		w.advance(60)
		local rows = w.forever("Late-Realm", guid, { at = w.epoch - 3 }) -- (the recap read three seconds after the death)
		w.die(rows)
		eq(W.Target(nil, guid).victims[1].at, w.epoch - 3, "dated by its killing blow (before: when it was read)")
	end)
end)

test("wanted office provenance: deterministic mode counts the same on every client; the old local-office option demonstrates why it must not feed shared scores", function()
	WithWorld(function(world)
		local master = world:Client("Master-Realm", "Player-1-0A0000F1", nil, nil, "Olympus II")
		local mate = world:Client("Mate-Realm", "Player-1-0A0000F2", nil, nil, "Olympus II")
		local other = world:Client("Faraway-Realm", "Player-1-0A0000F3", nil, nil, "Olympus III")
		master.units.player.level, master.units.player.rank = 40, 0
		world.verified[ns.Fold(master.name)] = true -- (the other guild's client verifies him as a member)
		local everyone = { master, mate, other }
		local function Manifest(signed)
			for _, cl in ipairs(everyone) do
				cl.ns.Authority = { Role = function(name)
					if signed and ns.Fold(ns.FullName(name)) == ns.Fold(master.name) then return "Olympus II", 0, "signed" end
				end }
				-- (His guild's roster, as Data.AuthorizedRank reads it, ranks him on his guildmates' clients
				-- alone; the census ranks nobody for the other guild's.)
				cl.ns.Data.AuthorizedRank = function(name, guild)
					if cl.guild == "Olympus II" and guild == "Olympus II" and ns.Fold(ns.FullName(name)) == ns.Fold(master.name) then return 0, "roster" end
				end
			end
		end
		local n = 0
		local function Die()
			n = n + 1
			local horde = ("Player-1-0B0000F%d"):format(n)
			world.horde[horde] = "Office" .. n .. "-Realm"
			master.dead, master.recap = true, { { event = "SPELL_DAMAGE", sourceGUID = horde, sourceName = world.horde[horde], sourceFlags = 0x548,
				overkill = 30, timestamp = world.epoch - 0.2 } }
			world:As(master, master.events.PLAYER_DEAD)
			master.dead, master.recap = false, nil
			world:Deliver()
			local out = {}
			for i, cl in ipairs(everyone) do
				local t = world:As(cl, cl.W.Target, nil, horde)
				out[i] = t and t.current or -1
			end
			world.epoch = world.epoch + 60
			return out
		end
		-- 1.2.4 ships strict deterministic offices; the old local option remains exercised below to
		-- prove the divergent outcome that must never feed a shared score.
		eq(master.W.Bounty.LOCAL_OFFICES, false, "1.2.4: deterministic shared offices by default")
		for _, cl in ipairs(everyone) do cl.W.Bounty.LOCAL_OFFICES = false end
		Manifest(false)
		local got = Die()
		for i, cl in ipairs(everyone) do eq(got[i], 40, cl.name .. ": a member's 0 and his level (before: 70 on his own client, 40 elsewhere)") end
		Manifest(true)
		got = Die()
		for i, cl in ipairs(everyone) do eq(got[i], 70, cl.name .. ": the signed manifest's guild master, 30 and his level, everywhere") end
		-- Option (b): each client what it verifies; the other guild's cannot.
		Manifest(false)
		for _, cl in ipairs(everyone) do cl.W.Bounty.LOCAL_OFFICES = true end
		got = Die()
		eq(got[1], 70, "his own client: the game's rank"); eq(got[2], 70, "his guild's roster")
		eq(got[3], 40, "a client of another guild that cannot verify him: the clients differ, option b's price")
	end)
end)

test("wanted 1.2.3 repair: corpse camping and a Horde friend killed in a loop no longer mint points: one member's kills of one Horde player pay his level once in KILL_GAP (the open bounty always) and the revenge on him once in REVENGE_GAP; another member's kill has its own gap, and a reload keeps them", function()
	WithWanted(function(w, W, c)
		w.manager = false
		local me = w.units.player.guid
		w.units.player.level = 60
		local S = W.Bounty.SCORE
		local function Kill(guid, name, level)
			w.units.target = { name = name, guid = guid, faction = "Horde", level = level }
			local ok, e = w.handlers.PARTY_KILL(me, guid)
			w.units.target = nil
			assert(ok, tostring(e))
			return e
		end
		local function Mine()
			for _, r in ipairs(W.Rankings().all) do if r.guid == me then return r.points end end
			return 0
		end
		-- (a) A real level-60 Horde player's corpse camped in the open world: eight kills in five minutes.
		local camped = "Player-1-0D00B301"
		w.hordePlayer("Camped-Realm", camped)
		local total = 0
		for i = 1, 8 do
			w.advance(i > 1 and 37 or 1)
			total = total + Kill(camped, "Camped-Realm", 60).points
		end
		eq(total, 6, "one fair kill's base points (before: 8 x 120 = 960)")
		eq(Mine(), 6)
		-- (b) A friend's level-60 Horde alt and this member, every 10 minutes: the alt kills him (60
		-- on the alt's bounty, a grudge), he kills the alt.
		local alt = "Player-1-0D00B302"
		w.hordePlayer("Friendly-Realm", alt)
		local function Loop(wait)
			w.advance(wait or S.REPEAT_GAP)
			w.die(w.forever("Friendly-Realm", alt)); w.dead = false
			w.advance(W.DEATH_WINDOW + 1)
			return Kill(alt, "Friendly-Realm", 60)
		end
		local e = Loop()
		eq(e.points, 6 + 60 + 100, "the first: his level base, the bounty of our death, the revenge"); eq(e.revenge, true)
		for i = 2, 6 do
			e = Loop()
			eq(e.points, 60, "loop " .. i .. ": the bounty our death put on him alone, no level, no revenge (before: 280)"); eq(e.revenge, nil)
		end
		e = Loop(S.KILL_GAP)
		eq(e.points, 6 + 60, "past KILL_GAP his level base again; the revenge waits REVENGE_GAP"); eq(e.revenge, nil)
		e = Loop(S.REVENGE_GAP)
		eq(e.points, 6 + 60 + 100, "a day on, the revenge again"); eq(e.revenge, true)
		-- Another member's kill of him has its own gap: his level.
		local other = w.participant("Other-Realm", "Player-1-CC00B301")
		w.advance(W.DEATH_WINDOW + 1)
		assert(w.commHandlers.WK("CHANNEL", other, BountyRow(c, W, { digest = "00000000000b3001", at = w.epoch, kind = "P",
			horde = "1.0d00b302", own = "1.cc00b301", worth = "M~60~60", name = "Friendly-Realm" })))
		eq(W.Target(nil, alt).claims[#W.Target(nil, alt).claims].points, 6)
		-- After a reload, built again from the rows: our gap holds.
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted
		assert(W.Prune())
		w.advance(W.DEATH_WINDOW + 1)
		eq(Kill(alt, "Friendly-Realm", 60).points, 0, "within our KILL_GAP after a reload")
	end)
end)

test("wanted 1.2.3 repair: a full Most Wanted keeps an open bounty, and a member's open grudge, over a Horde player who was only killed (a kill with no bounty pays his level now, so nothing paid no longer tells the entry that holds least); what his kill paid stays with its Slayer", function()
	WithWanted(function(w, W, c)
		W.MAX_TARGETS = 3
		w.manager, w.dead = false, false
		w.units.player.level = 40
		local me = w.units.player.guid
		local function Horde(i)
			local guid = ("Player-1-0D00B4%02d"):format(i)
			w.hordePlayer("Full" .. i .. "-Realm", guid)
			return guid
		end
		local function Die(guid, i) w.advance(W.DEATH_WINDOW + 1) w.die(w.forever("Full" .. i .. "-Realm", guid)) w.dead = false end
		local function Mine()
			for _, r in ipairs(W.Rankings().all) do if r.guid == me then return r.points end end
			return 0
		end
		-- The oldest: he killed us, his bounty open.
		local open = Horde(1); Die(open, 1)
		-- Then one we killed (level 50 on his corpse: 5 points), nothing open.
		local killed = Horde(2)
		w.advance(W.DEATH_WINDOW + 1)
		w.units.target = { name = "Full2-Realm", guid = killed, faction = "Horde", level = 50 }
		assert(w.handlers.PARTY_KILL(me, killed))
		w.units.target = nil
		eq(Mine(), 5)
		-- Then one who killed us and whom another member killed: nothing open, our grudge open.
		local grudged = Horde(3); Die(grudged, 3)
		local other = w.participant("Other-Realm", "Player-1-CC00B401")
		w.advance(W.DEATH_WINDOW + 1)
		assert(w.commHandlers.WK("CHANNEL", other, BountyRow(c, W, { digest = "00000000000b4001", at = w.epoch, kind = "P",
			horde = "1.0d00b403", own = "1.cc00b401", worth = "M~40~50", name = "Full3-Realm" })))
		eq(W.Target(nil, grudged).current, 0)
		-- A fourth Horde player kills us: room is made.
		local fourth = Horde(4); Die(fourth, 4)
		assert(W.Target(nil, fourth))
		eq(W.Target(nil, killed), nil, "the one only killed went (before: the open bounty, the oldest)")
		eq(W.Target(nil, open).current, 40, "the open bounty stays"); assert(W.Target(nil, grudged), "and the grudge")
		eq(Mine(), 5, "what our kill paid stays with us")
		-- A fifth: the grudge goes before any open bounty.
		local fifth = Horde(5); Die(fifth, 5)
		eq(W.Target(nil, grudged), nil); eq(W.Target(nil, open).current, 40); assert(W.Target(nil, fourth))
	end)
end)

---------------------------------------------------------------------------
-- 1.2.4, the notices (Daniel: a message at every death to a Horde player; one, when that player
-- is killed, saying who avenged it, with See, Whisper and Thank; the Slayer letter to the killer,
-- in the King's letter's model). Each of these fails on the build before it (release/1.2.3: no
-- toast, no avenged notice, no letter).
---------------------------------------------------------------------------

-- A test's own timers (ns.After): Fire(label) runs the first one of that label, and says its wait.
local function Timers(c)
	local list = {}
	c.After = function(seconds, label, fn) list[#list + 1] = { seconds = seconds, label = label, fn = fn } end
	return function(label)
		for i, t in ipairs(list) do if t.label == label then table.remove(list, i) t.fn() return t.seconds end end
		return nil
	end, function() list = {} end
end
-- The avenged notices a client was shown (Dialog.Show's), in order.
local function AvengedShown(into)
	local out = {}
	for _, f in ipairs(into.shownDialogs) do if f.which == "OLYMPUS_WANTED_AVENGED" then out[#out + 1] = f end end
	return out
end

test("wanted 1.2.4 notices: at each own death to a Horde player, a toast at the death: Olympus's own window at the bottom of the screen (the release popup is at its top), no button, no mouse, off the escape list, his name and the points his bounty grew by; once a death (the recap's retries, a second reading); 'again' inside the corpse-camping gap; nothing for a death that does not count; in both input modes, never a game popup", function()
	WithWanted(function(w, W, c)
		w.manager = false
		w.units.player.level = 40
		local savedPopup = StaticPopup_Show
		StaticPopup_Show = function(which) error("the game's popup: " .. tostring(which)) end
		local ok, err = pcall(function()
			local Fire = Timers(c)
			local ganker = "Player-1-0D00E001"
			w.hordePlayer("Toast Ganker-Realm", ganker)
			local name = c.DisplayName("Toast Ganker-Realm")
			-- The recap a moment after PLAYER_DEAD: its retry reads it.
			local rows, ready = w.forever("Toast-Realm", ganker), false
			C_DeathInfo = nil
			C_DeathRecap = { HasRecapEvents = function() return ready end, GetRecapEvents = function() return rows end }
			w.dead = true
			w.handlers.PLAYER_DEAD()
			eq(w.windows.OlympusWantedToast, nil, "nothing before the recap")
			ready = true
			Fire("wanted death recap")
			local f = assert(w.windows.OlympusWantedToast, "the toast")
			eq(f.shown, true, "at the death, the player still dead: no wait for the release")
			eq(f.text.text, ns.L.WANTED_DEATH_TOAST:format(name, 40), "his name and what this death added (a member of level 40)")
			eq(W.Target(nil, ganker).current, 40)
			eq(f.opts.title, ns.L.TAB_WANTED); eq(f.opts.close, false, "no button")
			eq(f.opts.escape, false, "off the escape list: the game's sweep at a death leaves it")
			eq(f.mouse, false, "no mouse: nothing under it is blocked")
			local at = f.points[#f.points]
			eq(at[1], "BOTTOM"); eq(at[3], "BOTTOM"); eq(at[5], W.Bounty.TOAST_Y, "the bottom centre: the release popup is at the top")
			eq(#w.shownDialogs, 0); eq(#w.dialogs, 0, "no dialog")
			-- Its other retries, and the same death read again: no second toast.
			Fire("wanted death recap"); Fire("wanted death recap")
			w.handlers.PLAYER_DEAD()
			Fire("wanted death recap")
			eq(W.Bounty.session.toasts, 1, "once a death")
			eq(Fire("wanted toast"), W.Bounty.TOAST_SECONDS); eq(f.shown, false, "gone after its seconds")
			-- Killed again inside the corpse-camping gap: "again", no points.
			w.advance(60)
			rows = w.forever("Toast-Realm", ganker)
			w.handlers.PLAYER_DEAD()
			eq(f.shown, true); eq(f.text.text, ns.L.WANTED_DEATH_TOAST_AGAIN:format(name)); eq(W.Target(nil, ganker).current, 40)
			-- Past it, his bounty grows again.
			w.advance(W.Bounty.SCORE.REPEAT_GAP + 1)
			rows = w.forever("Toast-Realm", ganker)
			w.handlers.PLAYER_DEAD()
			eq(f.text.text, ns.L.WANTED_DEATH_TOAST:format(name, 40)); eq(W.Target(nil, ganker).current, 80)
			eq(W.Bounty.session.toasts, 3)
			-- A death that does not count shows nothing: a killer the game knows as no Horde player,
			-- a death in a battleground.
			w.advance(W.DEATH_WINDOW + 1)
			rows = w.forever("Unproven-Realm", "Player-1-0D00E002")
			w.handlers.PLAYER_DEAD()
			w.advance(W.Bounty.SCORE.REPEAT_GAP + 1)
			w.inside, rows = true, w.forever("Toast-Realm", ganker)
			w.handlers.PLAYER_DEAD()
			w.inside = false
			eq(W.Bounty.session.toasts, 3, "nothing for a death that does not count")
			eq(W.Target(nil, ganker).current, 80)
			-- With the gamepad UI the same toast: it takes no focus and has no button.
			GamepadStyle(true)
			w.advance(W.Bounty.SCORE.REPEAT_GAP + 1)
			rows = w.forever("Toast-Realm", ganker)
			w.handlers.PLAYER_DEAD()
			eq(W.Bounty.session.toasts, 4); eq(f.shown, true); eq(f.text.text, ns.L.WANTED_DEATH_TOAST:format(name, 40))
			eq(#w.shownDialogs, 0); eq(#w.dialogs, 0)
			GamepadStyle(false)
		end)
		StaticPopup_Show = savedPopup
		if not ok then error(err, 0) end
	end)
end)

test("wanted 1.2.4 notices: a death avenged: another member's own kill of that Horde player, reaching this client, brings one notice in Olympus's own dialog (who slew him, his guild, the Horde player, how many times he had killed this member); Thank writes the thanks in Olympus's whisper window and sends nothing, Whisper opens that window empty, See his profile and keeps the dialog; nothing for a kill before the death, a stranger's or a hidden sender's row, a second avenger, the member's own kill, or after a reload", function()
	WithWanted(function(w, W, c)
		w.manager, w.dead = false, false
		w.units.player.level = 40
		local saved = { popup = StaticPopup_Show, chat = SendChatMessage }
		StaticPopup_Show = function(which) error("the game's popup: " .. tostring(which)) end
		SendChatMessage = function() error("a message sent") end
		local ok, err = pcall(function()
			local H = assert(w.commHandlers.WK)
			local me = w.units.player.guid
			local ganker = "Player-1-0D00E101"
			w.hordePlayer("Avenged Ganker-Realm", ganker)
			local avenger = w.participant("Avenger Hand-Realm", "Player-1-CC00E101")
			local second = w.participant("Second Hand-Realm", "Player-1-CC00E102")
			local n = 0
			local function Kill(from, own, at)
				n = n + 1
				return H("CHANNEL", from, BountyRow(c, W, { kind = "P", digest = ("%016x"):format(0xe100 + n), at = at or w.epoch,
					horde = "1.0d00e101", own = own, worth = "M~50~60", name = "Avenged Ganker-Realm" }))
			end
			local function Die()
				w.die(w.forever("Avenged-Realm", ganker))
				w.dead = false
				w.advance(W.Bounty.SCORE.REPEAT_GAP + 1)
			end
			local firstAt = w.epoch
			Die(); Die()
			eq(W.Target(nil, ganker).current, 80, "his two deaths")
			-- A kill dated before those deaths (a late row): it avenges none of them.
			assert(Kill(avenger, "1.cc00e101", firstAt - 30))
			eq(#AvengedShown(w), 0, "a kill before the deaths")
			-- Rows refused before they count: a stranger's, a sender the moderators hide.
			w.strangers[c.Fold("Outsider-Realm")] = true
			eq(select(2, Kill("Outsider-Realm", "1.dd00e101")), "stranger")
			c.Moderation.Hides = function(name) return c.Fold(name) == c.Fold(second) end
			eq(select(2, Kill(second, "1.cc00e102")), "hidden")
			c.Moderation.Hides = nil
			eq(#AvengedShown(w), 0)
			-- The avenger's own kill, now: one notice, at once.
			local sentBefore = #w.sent
			assert(Kill(avenger, "1.cc00e101"))
			local shown = AvengedShown(w)
			eq(#shown, 1, "one notice")
			local d = shown[1]
			eq(d.a, ns.L.WANTED_AVENGED:format(c.DisplayName(avenger), "Olympus II", c.DisplayName("Avenged Ganker-Realm"),
				ns.L.WANTED_AVENGED_TIMES:format(2)), "who, his guild, the Horde player, twice")
			eq(d.def.button1, ns.L.WANTED_AVENGED_THANK); eq(d.def.button2, ns.L.WANTED_AVENGED_CLOSE)
			eq(d.def.button3, ns.L.WANTED_AVENGED_WHISPER); eq(d.def.extra.label, ns.L.WANTED_AVENGED_SEE)
			eq(d.def.hasEditBox, nil, "no edit box")
			eq(#w.dialogs, 0, "never through the game's popups (ns.ShowDialog)")
			eq(c.rdb.wanted.mine[ganker], nil, "his deaths closed")
			-- Thank: Olympus's whisper window with the words in it; nothing sent until the player's own Send.
			d.def.OnAccept(d, d.data)
			eq(#w.whispers, 1); eq(w.whispers[1].name, c.TellName(avenger)); eq(w.whispers[1].text, ns.L.WANTED_THANK_TEXT)
			eq(#w.sent, sentBefore, "nothing sent")
			-- Whisper: that window, empty (Olympus's own dialog in both input modes).
			d.def.OnAlt(d, d.data)
			local box = w.shownDialogs[#w.shownDialogs]
			eq(box.which, "OLYMPUS_WHISPER"); eq(box.a, c.TellName(avenger)); eq(box.data, c.TellName(avenger))
			-- See: his Olympus profile; the dialog stays (Dialog.lua's extra button answers nothing).
			d.def.extra.onClick(d, d.data)
			eq(w.profile.name, "Avenger Hand"); eq(w.profile.realm, "Realm"); eq(w.profile.guild, "Olympus II"); eq(w.profile.source, "addon")
			eq(#w.sent, sentBefore, "still nothing sent")
			d.shown, box.shown = false, false
			-- A second avenger finds nothing open.
			w.advance(60)
			assert(Kill(second, "1.cc00e102"))
			eq(#AvengedShown(w), 1, "a second avenger: nothing")
			-- He kills this member again, and this member kills him: no notice (his own revenge), his letter.
			w.advance(W.Bounty.SCORE.REPEAT_GAP + 1)
			Die()
			w.units.target = { name = "Avenged Ganker-Realm", guid = ganker, faction = "Horde", level = 60 }
			assert(w.handlers.PARTY_KILL(me, ganker))
			w.units.target = nil
			eq(#AvengedShown(w), 1, "the member's own kill: no notice")
			-- (1.2.4 repair, changed on purpose: the letter goes once its numbers settled, LETTER_SETTLE
			-- after the kill; here the fight ends after that. Before, it went at the kill.)
			w.advance(W.Bounty.LETTER_SETTLE)
			w.handlers.PLAYER_REGEN_ENABLED()
			eq(#w.letters, 1, "his letter instead")
			eq(c.rdb.wanted.mine[ganker], nil)
			-- A reload: nothing again.
			assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
			W = c.Wanted
			assert(W.Load())
			eq(#AvengedShown(w), 1); eq(#w.letters, 1)
		end)
		StaticPopup_Show, SendChatMessage = saved.popup, saved.chat
		if not ok then error(err, 0) end
	end)
end)

test("wanted 1.2.4 notices: the avenged notice waits out combat, an instance, a death, the privacy page (shown or waiting), the update letter and the King's letter, saved across a reload, then shows once, one at a time; with the gamepad UI it waits for the Olympus window and chat says so once; five at most wait, the oldest go", function()
	WithWanted(function(w, W, c)
		w.manager, w.dead = false, false
		w.units.player.level = 40
		local Fire, Clear = Timers(c)
		local avenger = w.participant("Waiting Hand-Realm", "Player-1-CC00E201")
		local function Hunt(i)
			local guid = ("Player-1-0D00E2%02d"):format(i)
			local name = "Waiting Ganker" .. i .. "-Realm"
			w.hordePlayer(name, guid)
			w.die(w.forever("Waiting-Realm", guid))
			w.dead = false
			w.advance(60)
			local ok, e = w.commHandlers.WK("CHANNEL", avenger, BountyRow(c, W, { kind = "P", digest = ("%016x"):format(0xe200 + i), at = w.epoch,
				horde = ("1.0d00e2%02d"):format(i), own = "1.cc00e201", name = name }))
			assert(ok, tostring(e))
			return name
		end
		local function Waits() local k = 0 for _ in ipairs(c.rdb.wanted.avenged) do k = k + 1 end return k end
		w.combat = true
		local first = Hunt(1)
		eq(#AvengedShown(w), 0, "in combat: it waits"); eq(Waits(), 1, "saved")
		-- A reload meanwhile: still waiting, tried again NOTICE_LOGIN after the login.
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted
		Clear()
		assert(W.Load())
		w.advance(W.Bounty.NOTICE_LOGIN)
		eq(Fire("wanted notices"), W.Bounty.NOTICE_LOGIN)
		eq(#AvengedShown(w), 0)
		for _, case in ipairs({ "combat", "inside", "dead", "consentWaiting", "consentShown", "updateLetter", "letterFrame" }) do
			w.combat, w.inside, w.dead, w.consentWaiting, w.consentShown, w.updateLetter, w.letterFrame = false, false, false, false, false, nil, nil
			if case == "letterFrame" then w.letterFrame = { IsShown = function() return true end } else w[case] = true end
			assert(Fire("wanted notices"), case .. ": tried again later")
			eq(#AvengedShown(w), 0, case)
		end
		w.letterFrame = nil
		Fire("wanted notices")
		local shown = AvengedShown(w)
		eq(#shown, 1, "nothing in the way: shown")
		assert(shown[1].a:find(c.DisplayName(first), 1, true))
		eq(Fire("wanted notices"), nil, "and done"); eq(Waits(), 0)
		shown[1].shown = false
		-- With the gamepad UI nothing of Olympus opens by itself: it waits for the Olympus window.
		GamepadStyle(true)
		local function Said() local k = 0 for _, p in ipairs(w.prints) do if p == ns.L.WANTED_AVENGED_WAITING then k = k + 1 end end return k end
		Hunt(2)
		eq(#AvengedShown(w), 1, "it waits for the window"); eq(Said(), 1, "chat says so")
		eq(Fire("wanted notices"), W.Bounty.WINDOW_TICK)
		eq(Said(), 1, "once")
		w.windowOpen = true
		Fire("wanted notices")
		eq(#AvengedShown(w), 2, "the Olympus window open: shown")
		AvengedShown(w)[2].shown = false
		GamepadStyle(false)
		w.windowOpen = nil
		-- Seven while it waits: the newest five stay, shown one at a time, oldest first.
		w.combat = true
		local names = {}
		for i = 3, 9 do names[i] = Hunt(i) end
		eq(Waits(), W.Bounty.AVENGED_MAX)
		-- The fight's end: at once, one at a time, the oldest first.
		w.combat = false
		w.handlers.PLAYER_REGEN_ENABLED()
		shown = AvengedShown(w)
		eq(#shown, 3, "one at a time")
		assert(shown[3].a:find(c.DisplayName(names[5]), 1, true), "the oldest two went: " .. shown[3].a)
		assert(Fire("wanted notices"), "(the beat that waited out the fight)")
		eq(#AvengedShown(w), 3, "the next waits for this one")
		eq(Fire("wanted notices"), W.Bounty.WINDOW_TICK, "looking for it to close")
		eq(#AvengedShown(w), 3)
		-- Closed: the next one.
		shown[3].shown = false
		shown[3].def.OnHide(shown[3], shown[3].data)
		assert(Fire("wanted notices"))
		shown = AvengedShown(w)
		eq(#shown, 4); assert(shown[4].a:find(c.DisplayName(names[6]), 1, true), shown[4].a)
	end)
end)

test("wanted 1.2.4 notices: the Slayer letter, the King's letter at this member's own kill that paid points: whom he slew, how many of ours that one had slain, his bounty, his level's points, the revenge and the total, as this client counted them with every member's rows; never in combat, an instance, a death, over the privacy page or the update letter (it waits, saved); once; a '??' as its floor; none for a kill that paid nothing; the King a toast instead", function()
	WithWanted(function(w, W, c)
		w.manager, w.dead = false, false
		w.units.player.level = 45
		local me = w.units.player.guid
		local Fire = Timers(c)
		local function Corpse(name, guid, level)
			w.hordePlayer(name, guid)
			w.units.target = level and { name = name, guid = guid, faction = "Horde", level = level } or nil
		end
		local function Name(n) return c.DisplayName(n) end
		-- (1.2.4 repair, changed on purpose: a letter goes once its numbers settled, LETTER_SETTLE
		-- after the kill, its numbers the claim's then: Bounty.SettledKey. Before, at the kill.)
		local function Settle()
			w.advance(W.Bounty.LETTER_SETTLE)
			Fire("wanted notices")
		end
		-- Two members' deaths to him, as the channel brings them: 40 and 50 on his bounty.
		local ganker = "Player-1-0D00E301"
		w.hordePlayer("Letter Ganker-Realm", ganker)
		local first = w.participant("First Fallen-Realm", "Player-1-CC00E301")
		local second = w.participant("Second Fallen-Realm", "Player-1-CC00E302")
		assert(w.commHandlers.WK("CHANNEL", first, BountyRow(c, W, { digest = "00000000000e3001", at = w.epoch, horde = "1.0d00e301",
			own = "1.cc00e301", worth = "M~40~0", name = "Letter Ganker-Realm" })))
		w.advance(60)
		assert(w.commHandlers.WK("CHANNEL", second, BountyRow(c, W, { digest = "00000000000e3002", at = w.epoch, horde = "1.0d00e301",
			own = "1.cc00e302", worth = "M~50~0", name = "Letter Ganker-Realm" })))
		eq(W.Target(nil, ganker).current, 90, "every member's own deaths reached this client")
		-- This member kills him in the fight: his corpse at level 60.
		w.advance(60)
		w.combat = true
		Corpse("Letter Ganker-Realm", ganker, 60)
		local ok, e = w.handlers.PARTY_KILL(me, ganker)
		assert(ok, tostring(e))
		eq(e.points, 96)
		eq(#w.letters, 0, "in combat: it waits"); eq(#c.rdb.wanted.slayerLetters, 1, "saved")
		-- Then an instance, a death, the privacy page, the update letter: still waiting.
		for _, case in ipairs({ "inside", "dead", "consentWaiting", "consentShown", "updateLetter" }) do
			w.combat, w.inside, w.dead, w.consentWaiting, w.consentShown, w.updateLetter = false, false, false, false, false, nil
			w[case] = true
			assert(Fire("wanted notices"), case .. ": tried again later")
			eq(#w.letters, 0, case)
		end
		-- The fight's end, or the next beat, with nothing in the way: the letter, once its numbers
		-- settled (1.2.4 repair: LETTER_SETTLE after the kill).
		w.combat, w.inside, w.dead, w.consentWaiting, w.consentShown, w.updateLetter = true, false, false, false, false, nil
		Fire("wanted notices")
		w.combat = false
		w.handlers.PLAYER_REGEN_ENABLED()
		eq(#w.letters, 0, "its numbers still settling"); eq(#c.rdb.wanted.slayerLetters, 1)
		Settle()
		eq(#w.letters, 1)
		eq(#c.rdb.wanted.slayerLetters, 0, "handed to the King's letter")
		local key = w.letters[1]
		eq(key:sub(1, 7), "wanted@")
		local text, title = W.LetterText(key)
		eq(text, ns.L.WANTED_LETTER:format(Name("Letter Ganker-Realm"), "60", 2, 90, ns.L.WANTED_LETTER_LEVEL:format(6), 96))
		eq(title, ns.L.WANTED_LETTER_TITLE:format(Name("Letter Ganker-Realm"))); eq(W.LetterTitle(key), title)
		-- His own revenge: the Horde player who killed him, killed by him.
		w.advance(W.Bounty.SCORE.REPEAT_GAP + 1)
		local avenger = "Player-1-0D00E302"
		w.hordePlayer("Revenge Ganker-Realm", avenger)
		w.die(w.forever("Revenge-Realm", avenger))
		w.dead = false
		w.advance(60)
		Corpse("Revenge Ganker-Realm", avenger, 60)
		ok, e = w.handlers.PARTY_KILL(me, avenger)
		assert(ok, tostring(e)); eq(e.points, 6 + 45 + W.Bounty.SCORE.REVENGE)
		Settle()
		eq(#w.letters, 2)
		eq(W.LetterText(w.letters[2]), ns.L.WANTED_LETTER:format(Name("Revenge Ganker-Realm"), "60", 1, 45,
			ns.L.WANTED_LETTER_LEVEL:format(6) .. ns.L.WANTED_LETTER_REVENGE:format(W.Bounty.SCORE.REVENGE), 151))
		-- Nobody's killer: his level alone; a "??" as its floor.
		w.advance(W.DEATH_WINDOW + 1)
		Corpse("Fresh Ganker-Realm", "Player-1-0D00E303", 52)
		assert(w.handlers.PARTY_KILL(me, "Player-1-0D00E303"))
		Settle()
		eq(W.LetterText(w.letters[3]), ns.L.WANTED_LETTER_FIRST:format(Name("Fresh Ganker-Realm"), "52", ns.L.WANTED_LETTER_LEVEL:format(6), 6))
		w.advance(W.DEATH_WINDOW + 1)
		Corpse("Skull Ganker-Realm", "Player-1-0D00E304", -1)
		assert(w.handlers.PARTY_KILL(me, "Player-1-0D00E304"))
		Settle()
		eq(W.LetterText(w.letters[4]), ns.L.WANTED_LETTER_FIRST:format(Name("Skull Ganker-Realm"), ns.L.WANTED_LEVEL_FLOOR:format(55),
			ns.L.WANTED_LETTER_LEVEL:format(6), 6), "'??' to a level 45: 55 at least")
		-- A kill that paid nothing (no level seen, no bounty): no letter.
		w.advance(W.DEATH_WINDOW + 1)
		Corpse("Unseen Ganker-Realm", "Player-1-0D00E305", nil)
		ok, e = w.handlers.PARTY_KILL(me, "Player-1-0D00E305")
		assert(ok, tostring(e)); eq(e.points, 0)
		Settle()
		eq(#w.letters, 4, "nothing paid, no letter"); eq(#c.rdb.wanted.slayerLetters, 0, "and none waits")
		-- The King: no letter from himself, a toast.
		w.kingLetter = true
		w.advance(W.DEATH_WINDOW + 1)
		Corpse("Royal Ganker-Realm", "Player-1-0D00E306", 50)
		assert(w.handlers.PARTY_KILL(me, "Player-1-0D00E306"))
		Settle()
		eq(#w.letters, 4, "the King: no letter")
		eq(w.windows.OlympusWantedToast.text.text, ns.L.WANTED_LETTER_TOAST:format(Name("Royal Ganker-Realm"), 5))
		w.kingLetter = nil
		-- Once: a reload sends none again; the words still read from the key alone.
		w.units.target = nil
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted
		assert(W.Load())
		eq(#w.letters, 4); eq(W.LetterText(key), text)
		-- A key that is no Slayer letter's has no words.
		for _, bad in ipairs({ "wanted@", "wanted@zz~1~1~1~1~1~1~X-Realm", "wanted@0000000000000001~1~1~1~1~1~1", "donor-top-1" }) do
			eq(W.LetterText(bad), nil, bad); eq(W.LetterTitle(bad), nil, bad)
		end
	end)
end)

test("wanted 1.2.4 notices world: the killer's client knows the whole bounty at the kill (every member's own deaths reached it) and its letter says so; each member he had killed who is online is told at once who avenged him; one offline then is told at his next login (the King's catch-up answer), once", function()
	WithWorld(function(world)
		local king = world:Client("Varrick-Realm", "Player-1-0A0000F1", "king")
		local online = world:Client("Online-Realm", "Player-1-0A0000F2")
		local away = world:Client("Away-Realm", "Player-1-0A0000F3")
		local slayer = world:Client("Slayer-Realm", "Player-1-0A0000F4")
		online.units.player.level, away.units.player.level, slayer.units.player.level = 40, 30, 50
		local horde = "Player-1-0B0000F1"
		world.horde[horde] = "Ganker-Realm"
		local name = ns.DisplayName("Ganker-Realm")
		local function Die(cl)
			cl.dead, cl.recap = true, { { event = "SPELL_DAMAGE", sourceGUID = horde, sourceName = "Ganker-Realm", sourceFlags = 0x548,
				overkill = 90, timestamp = world.epoch - 0.2 } }
			world:As(cl, cl.events.PLAYER_DEAD)
			cl.dead, cl.recap = false, nil
			world:Deliver()
			world.epoch = world.epoch + 60
		end
		Die(online); Die(away)
		eq(online.windows.OlympusWantedToast.text.text, ns.L.WANTED_DEATH_TOAST:format(name, 40), "the toast on his own client")
		eq(king.windows.OlympusWantedToast, nil, "on nobody else's")
		world:Offline(away)
		-- The slayer kills him: the whole bounty (40 + 30) on his client at the kill.
		slayer.units.target = { name = "Ganker-Realm", guid = horde, faction = "Horde", level = 60 }
		local ok, claim = world:As(slayer, slayer.events.PARTY_KILL, slayer.guid, horde)
		slayer.units.target = nil
		assert(ok, tostring(claim)); eq(claim.points, 76)
		world:Deliver()
		-- (1.2.4 repair, changed on purpose: the letter goes LETTER_SETTLE after the kill, its
		-- numbers settled; it is read below, once the world's clock ran past it. Before, at the kill.)
		eq(slayer.letters[1], nil, "its numbers settling")
		-- The member online is told at once; the King and the slayer are not.
		local told = AvengedShown(online)
		eq(#told, 1)
		local words = ns.L.WANTED_AVENGED:format(ns.DisplayName(slayer.name), "Olympus II", name, "")
		eq(told[1].a, words)
		eq(#AvengedShown(king), 0); eq(#AvengedShown(slayer), 0)
		-- The one offline logs in: the King's catch-up answer brings the kill, and his notice. (A
		-- reviewer's relay names no guild, WK~C: the words name the avenger's where this client heard
		-- it, Moderation.GuildOf, and leave it out here.)
		world:Load(away)
		world:Run(away.W.GLOBAL_ASK_FIRST + 30)
		eq(#world:As(away, away.W.Target, nil, horde).claims, 1, "the kill caught up")
		eq(#AvengedShown(away), 0, "nothing in the first NOTICE_LOGIN after login (the privacy page's, the update letter's)")
		world:Run(away.W.Bounty.NOTICE_LOGIN)
		told = AvengedShown(away)
		eq(#told, 1, "told at his next login")
		eq(told[1].a, ns.L.WANTED_AVENGED_NOGUILD:format(ns.DisplayName(slayer.name), name, ""))
		told[1].shown = false
		-- The slayer's letter, its numbers settled: the whole bounty.
		local key = assert(slayer.letters[1], "the slayer's letter")
		eq(world:As(slayer, slayer.W.LetterText, key), ns.L.WANTED_LETTER:format(name, "60", 2, 70, ns.L.WANTED_LETTER_LEVEL:format(6), 76))
		-- Another login: nothing again.
		world:Load(away)
		world:Run(away.W.GLOBAL_ASK_FIRST + 30 + away.W.Bounty.NOTICE_LOGIN)
		eq(#AvengedShown(away), 1, "once")
		eq(#AvengedShown(online), 1)
	end)
end)

---------------------------------------------------------------------------
-- 1.2.4 repair, the notices' review: the rows come in any order (a member's own death heard after
-- the kill that avenged it, a death before the kill heard after it), a member offline at the kill
-- asks for it at his next login (W7), and with the gamepad UI the Slayer letter waits, saved, for
-- the Olympus window. Each of these fails on v124/notices.
---------------------------------------------------------------------------

test("wanted 1.2.4 repair: a death heard after the kill that avenged it (its recap ready only at a retry): the toast says he was slain already, never 'we will avenge you'; the avenged notice names that kill's slayer, with this member's earlier death to him counted, once; nothing stays open, so a kill on him days later tells nobody", function()
	WithWanted(function(w, W, c)
		w.manager, w.dead = false, false
		w.units.player.level = 40
		local Fire = Timers(c)
		local K = assert(w.commHandlers.WK)
		local ganker = "Player-1-0D00E401"
		w.hordePlayer("Late Ganker-Realm", ganker)
		local name = c.DisplayName("Late Ganker-Realm")
		local avenger = w.participant("Late Avenger-Realm", "Player-1-CC00E401")
		local later = w.participant("Later Hand-Realm", "Player-1-CC00E402")
		local n = 0
		local function Kill(from, own)
			n = n + 1
			return K("CHANNEL", from, BountyRow(c, W, { kind = "P", digest = ("%016x"):format(0xe400 + n), at = w.epoch,
				horde = "1.0d00e401", own = own, worth = "M~50~60", name = "Late Ganker-Realm" }))
		end
		-- A death to him read at once: kept open.
		w.die(w.forever("Late-Realm", ganker))
		w.dead = false
		assert(c.rdb.wanted.mine[ganker], "open")
		w.advance(W.Bounty.SCORE.REPEAT_GAP + 1)
		-- Killed by him again, the recap not ready at PLAYER_DEAD (the game's own delay).
		local rows, ready = w.forever("Late-Realm", ganker), false
		C_DeathInfo = nil
		C_DeathRecap = { HasRecapEvents = function() return ready end, GetRecapEvents = function() return rows end }
		w.dead = true
		w.handlers.PLAYER_DEAD()
		-- A second later the avenger's own kill row: it avenges the death held (this member is dead: it waits).
		w.advance(1)
		assert(Kill(avenger, "1.cc00e401"))
		eq(#AvengedShown(w), 0, "dead: it waits"); eq(#c.rdb.wanted.avenged, 1)
		-- The recap at the retry: his second death, before that kill.
		ready = true
		eq(Fire("wanted death recap"), 0.3)
		local toast = assert(w.windows.OlympusWantedToast)
		eq(toast.text.text, ns.L.WANTED_DEATH_TOAST_SLAIN:format(name), "slain already: never 'we will avenge you'")
		local t = W.Target(nil, ganker)
		eq(#t.claims, 1); eq(t.claims[1].bounty, 80, "both deaths in the claim that paid them"); eq(t.claims[1].points, 86)
		eq(c.rdb.wanted.mine[ganker], nil, "nothing left open")
		eq(#c.rdb.wanted.avenged, 1, "one notice"); eq(c.rdb.wanted.avenged[1].times, 2, "for both deaths")
		-- Alive: the notice, the avenger his slayer.
		w.dead = false
		Fire("wanted notices")
		local shown = AvengedShown(w)
		eq(#shown, 1)
		eq(shown[1].a, ns.L.WANTED_AVENGED:format(c.DisplayName(avenger), "Olympus II", name, ns.L.WANTED_AVENGED_TIMES:format(2)))
		shown[1].shown = false
		-- Three days later another member kills him: nothing was left open, nobody is told.
		w.advance(3 * 86400)
		assert(Kill(later, "1.cc00e402"))
		Fire("wanted notices")
		eq(#AvengedShown(w), 1, "a later kill tells nobody"); eq(#c.rdb.wanted.avenged, 0)
		-- His own kill heard before his death's row: avenged, no notice (his letter says it).
		local own = "Player-1-0D00E402"
		w.hordePlayer("Self Ganker-Realm", own)
		w.advance(W.DEATH_WINDOW + 1)
		rows, ready = w.forever("Self-Realm", own), false
		w.dead = true
		w.handlers.PLAYER_DEAD()
		w.dead = false
		w.units.target = { name = "Self Ganker-Realm", guid = own, faction = "Horde", level = 60 }
		assert(w.handlers.PARTY_KILL(w.units.player.guid, own))
		w.units.target = nil
		ready, w.dead = true, true
		while Fire("wanted death recap") do end -- (the first death's retries left too: theirs do nothing now)
		w.dead = false
		eq(c.rdb.wanted.mine[own], nil); eq(#c.rdb.wanted.avenged, 0, "his own kill: no notice")
		eq(w.windows.OlympusWantedToast.text.text, ns.L.WANTED_DEATH_TOAST_SLAIN:format(c.DisplayName("Self Ganker-Realm")))
	end)
end)

test("wanted 1.2.4 repair: a death the earlier deaths' reader adds at the next login, after the kill that avenged it was heard: its notice names that kill's slayer (after NOTICE_LOGIN), never a later avenger; another death a claim's told notice avenged brings none again", function()
	WithWanted(function(w, W, c)
		w.manager, w.dead = false, false
		w.units.player.level = 40
		local Fire, Clear = Timers(c)
		local K = assert(w.commHandlers.WK)
		W.Bounty.Spans() -- (its instances noted since the game session began)
		local avenger = w.participant("Reader Avenger-Realm", "Player-1-CC00E501")
		local later = w.participant("Reader Later-Realm", "Player-1-CC00E502")
		local n = 0
		local function Kill(from, own, horde, hordeName)
			n = n + 1
			return K("CHANNEL", from, BountyRow(c, W, { kind = "P", digest = ("%016x"):format(0xe500 + n), at = w.epoch,
				horde = horde, own = own, worth = "M~50~60", name = hordeName }))
		end
		local rows
		local function Login()
			C_DeathInfo = nil
			C_DeathRecap = { HasRecapEvents = function(id) return id == nil or id == 1 end, GetRecapEvents = function() return rows end }
			assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
			W = c.Wanted
			Clear()
			assert(W.Load())
			w.advance(W.Bounty.EARLIER_WAIT)
			Fire("wanted earlier deaths")
		end
		-- His death not read at the time (the game gave no recap then), the avenger's kill heard live.
		local ganker = "Player-1-0D00E501"
		w.hordePlayer("Unread Ganker-Realm", ganker)
		w.advance(60)
		rows = w.forever("Unread-Realm", ganker)
		w.advance(1)
		assert(Kill(avenger, "1.cc00e501", "1.0d00e501", "Unread Ganker-Realm"))
		eq(#c.rdb.wanted.avenged, 0, "no death of his held yet")
		-- The next login: the reader adds it, avenged already by that kill.
		w.advance(600)
		Login()
		eq(W.Target(nil, ganker).claims[1].bounty, 40, "the death in the claim that paid it")
		eq(c.rdb.wanted.mine[ganker], nil, "nothing left open"); eq(#c.rdb.wanted.avenged, 1)
		eq(#AvengedShown(w), 0, "not in the first NOTICE_LOGIN")
		w.advance(W.Bounty.NOTICE_LOGIN)
		Fire("wanted notices")
		local shown = AvengedShown(w)
		eq(#shown, 1, "told at the next login")
		eq(shown[1].a, ns.L.WANTED_AVENGED:format(c.DisplayName(avenger), "Olympus II", c.DisplayName("Unread Ganker-Realm"), ""))
		shown[1].shown = false
		w.advance(3 * 86400)
		assert(Kill(later, "1.cc00e502", "1.0d00e501", "Unread Ganker-Realm"))
		Fire("wanted notices")
		eq(#AvengedShown(w), 1, "a later kill tells nobody")
		-- A claim's notice told already (a death read at the time), then another death it avenged
		-- that the reader adds at the next login: nothing again.
		local second = "Player-1-0D00E502"
		w.hordePlayer("Twice Ganker-Realm", second)
		w.die(w.forever("Twice-Realm", second))
		w.dead = false
		w.advance(W.Bounty.SCORE.REPEAT_GAP + 1)
		rows = w.forever("Twice-Realm", second)
		w.advance(1)
		assert(Kill(avenger, "1.cc00e501", "1.0d00e502", "Twice Ganker-Realm"))
		Fire("wanted notices")
		shown = AvengedShown(w)
		eq(#shown, 2, "its notice, at once"); shown[2].shown = false
		w.advance(600)
		Login()
		eq(W.Target(nil, second).claims[1].bounty, 80, "the second death in the claim too")
		w.advance(W.Bounty.NOTICE_LOGIN)
		Fire("wanted notices")
		eq(#AvengedShown(w), 2, "told once"); eq(#c.rdb.wanted.avenged, 0); eq(c.rdb.wanted.mine[second], nil)
	end)
end)

test("wanted 1.2.4 repair: the Slayer letter says what the claim pays once its numbers settled: a member's death before the kill heard after it (his recap at a retry, then the channel) is in its bounty and in its total, as on the Slayers ranking; its key is made once, as it goes", function()
	WithWanted(function(w, W, c)
		w.manager, w.dead = false, false
		w.units.player.level = 45
		local me = w.units.player.guid
		local Fire = Timers(c)
		local ganker = "Player-1-0D00E601"
		w.hordePlayer("Quick Ganker-Realm", ganker)
		local name = c.DisplayName("Quick Ganker-Realm")
		local fallen = w.participant("Quick Fallen-Realm", "Player-1-CC00E601")
		-- The member dies to him; two seconds later this member kills him (level 60).
		local diedAt = w.epoch
		w.advance(2)
		w.units.target = { name = "Quick Ganker-Realm", guid = ganker, faction = "Horde", level = 60 }
		local ok, e = w.handlers.PARTY_KILL(me, ganker)
		w.units.target = nil
		assert(ok, tostring(e)); eq(e.points, 6, "at the kill: his level base alone")
		-- The fallen member's row a second after the kill, dated at his death.
		w.advance(1)
		assert(w.commHandlers.WK("CHANNEL", fallen, BountyRow(c, W, { digest = "00000000000e6001", at = diedAt, horde = "1.0d00e601",
			own = "1.cc00e601", worth = "M~40~0", name = "Quick Ganker-Realm" })))
		local claim = W.Target(nil, ganker).claims[1]
		eq(claim.bounty, 40); eq(claim.points, 46, "the claim rebuilt with his death")
		eq(#w.letters, 0, "settling")
		w.advance(W.Bounty.LETTER_SETTLE)
		Fire("wanted notices")
		eq(#w.letters, 1)
		local key = w.letters[1]
		eq(W.LetterText(key), ns.L.WANTED_LETTER:format(name, "60", 1, 40, ns.L.WANTED_LETTER_LEVEL:format(6), 46), "the whole bounty")
		local ranked = W.Rankings().all
		eq(ranked[1].name, c.me); eq(ranked[1].points, 46, "as the Slayers ranking says")
		eq(W.Bounty.LetterOf(key).points, ranked[1].points)
		eq(#c.rdb.wanted.slayerLetters, 0, "made once, gone")
	end)
end)

-- (1.2.4, the author's report "3 kills, 18 points": the letter named every death of the cycle as a
-- kill, the corpse-camping gap's too.)
test("wanted 1.2.4 (the author's report: 3 kills, 18 points): the Slayer letter's kills count as the bounty does: a Horde player who killed one member three times in 8 minutes had killed 1 of ours, his bounty 18", function()
	WithWanted(function(w, W, c)
		w.manager = false
		w.units.player.level = 18
		local me = w.units.player.guid
		local Fire = Timers(c)
		local camper = "Player-1-0D00E401"
		w.hordePlayer("Letter Camper-Realm", camper)
		for i = 1, 3 do
			if i > 1 then w.advance(240) end
			w.die(w.forever("Letter Camper-Realm", camper))
		end
		w.dead = false
		eq(W.Target(nil, camper).current, 18); eq(W.Target(nil, camper).lifetimeKills, 1)
		w.advance(60)
		w.units.target = { name = "Letter Camper-Realm", guid = camper, faction = "Horde", level = 20 }
		local ok, e = w.handlers.PARTY_KILL(me, camper)
		w.units.target = nil
		assert(ok, tostring(e)); eq(e.points, 2 + 18 + W.Bounty.SCORE.REVENGE, "his level base, his bounty, the revenge")
		w.advance(W.Bounty.LETTER_SETTLE)
		while Fire("wanted notices") do end
		eq(#w.letters, 1)
		eq(W.LetterText(w.letters[1]), ns.L.WANTED_LETTER:format(c.DisplayName("Letter Camper-Realm"), "20", 1, 18,
			ns.L.WANTED_LETTER_LEVEL:format(2) .. ns.L.WANTED_LETTER_REVENGE:format(W.Bounty.SCORE.REVENGE), 120), "1 of ours (before: 3)")
	end)
end)

test("wanted 1.2.4 counted kills: repeated deaths trimmed from the victim history remain uncounted in the cycle summary and Slayer letter, across a checkpoint and reload", function()
	WithWanted(function(w, W, c)
		w.manager = false
		w.units.player.level = 18
		W.MAX_VICTIMS, W.MAX_EVIDENCE = 2, 3
		local camper = "Player-1-0D00E402"
		w.hordePlayer("Overflow Camper-Realm", camper)
		for i = 1, 4 do
			if i > 1 then w.advance(120) end
			w.die(w.forever("Overflow Camper-Realm", camper))
		end
		local t = W.Target(nil, camper)
		eq(t.current, 18); eq(t.lifetimeKills, 1)
		eq(t.victimOverflow, 2); eq(t.victimKillOverflow, 1, "one counted and one repeat trimmed")
		eq(W.Stats().checkpointed, 1, "the earlier deaths folded")
		assert(TipText(assert(WantedRow(W, camper))):find(ns.L.WANTED_REPEATS:format(4, 1, 10), 1, true), "the whole cycle, including its overflow")
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		W = c.Wanted; W.MAX_VICTIMS = 2; assert(W.Load())
		t = W.Target(nil, camper)
		eq(t.victimOverflow, 2); eq(t.victimKillOverflow, 1)
		w.advance(W.DEATH_WINDOW + 1)
		w.units.target = { name = "Overflow Camper-Realm", guid = camper, faction = "Horde", level = 20 }
		local ok, e = w.handlers.PARTY_KILL(w.units.player.guid, camper)
		assert(ok, tostring(e)); eq(e.points, 120)
		local claim = W.Target(nil, camper).claims[1]
		eq(claim.overflow, 2); eq(claim.killOverflow, 1)
		local letter = W.Bounty.LetterOf(W.Bounty.LetterKey(e, claim, "Overflow Camper-Realm"))
		eq(letter.kills, 1, "overflow repeats must not become kills in the letter")
		eq(W.Target(nil, camper).victimKillOverflow, 0, "the next cycle starts empty")
	end)
end)

test("wanted 1.2.4 repair: with the gamepad UI the Slayer letter stays saved in Wanted until the Olympus window is open and nothing is in the way (a /reload keeps it; an instance with the window open, it waits), then shows at once; chat is told it waits; with the mouse it shows as it goes", function()
	WithWanted(function(w, W, c)
		w.manager, w.dead = false, false
		w.units.player.level = 45
		local me = w.units.player.guid
		local Fire, Clear = Timers(c)
		local ganker = "Player-1-0D00E701"
		w.hordePlayer("Pad Ganker-Realm", ganker)
		GamepadStyle(true)
		local ok, err = pcall(function()
			w.units.target = { name = "Pad Ganker-Realm", guid = ganker, faction = "Horde", level = 50 }
			assert(w.handlers.PARTY_KILL(me, ganker))
			w.units.target = nil
			w.advance(W.Bounty.LETTER_SETTLE)
			Fire("wanted notices")
			eq(#w.letters, 0, "the window closed: it waits"); eq(#c.rdb.wanted.slayerLetters, 1, "saved in Wanted")
			assert(w.windowWaits >= 1, "chat told (HonorsNet.WaitForWindow)")
			-- A /reload before the window opened: still there.
			assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
			W = c.Wanted
			Clear()
			assert(W.Load())
			eq(#c.rdb.wanted.slayerLetters, 1, "kept across the reload")
			-- The window open in an instance: it waits.
			w.windowOpen, w.inside = true, true
			w.advance(W.Bounty.NOTICE_LOGIN)
			assert(Fire("wanted notices"))
			eq(#w.letters, 0, "in an instance"); eq(#c.rdb.wanted.slayerLetters, 1)
			-- Outside, the window open: at once.
			w.inside = false
			Fire("wanted notices")
			eq(#w.letters, 1, "the window open: shown"); eq(w.letterNow[1], true, "now, as the window's opening shows one")
			eq(#c.rdb.wanted.slayerLetters, 0)
		end)
		GamepadStyle(false)
		w.windowOpen = nil
		if not ok then error(err, 0) end
		-- With the mouse: it goes as it settles, the window closed.
		w.advance(W.DEATH_WINDOW + 1)
		w.hordePlayer("Mouse Ganker-Realm", "Player-1-0D00E702")
		w.units.target = { name = "Mouse Ganker-Realm", guid = "Player-1-0D00E702", faction = "Horde", level = 50 }
		assert(w.handlers.PARTY_KILL(me, "Player-1-0D00E702"))
		w.units.target = nil
		w.advance(W.Bounty.LETTER_SETTLE)
		Fire("wanted notices")
		eq(#w.letters, 2)
	end)
end)

test("wanted 1.2.4 repair, the avenged ask (W7): at login, while this character keeps deaths open, ASK_AFTER after it and ASK_EVERY apart, ASK_TRIES at most, until none is open; ASK_MAX digests, no GUID or name on the wire; none without an open death; the README says what it sends", function()
	WithWanted(function(w, W, c)
		w.manager, w.dead = false, false
		w.units.player.level = 40
		local Fire, Clear = Timers(c)
		local guids = {}
		for i = 1, 5 do
			guids[i] = ("Player-1-0D00E8%02d"):format(i)
			w.hordePlayer("Asked Ganker" .. i .. "-Realm", guids[i])
			w.die(w.forever("Asked-Realm", guids[i]))
			w.dead = false
			w.advance(W.DEATH_WINDOW + 1)
		end
		local function Asks() return w.wire("W7") end
		Clear()
		assert(W.Load())
		eq(#Asks(), 0, "not at login")
		w.advance(W.Bounty.ASK_AFTER)
		eq(Fire("wanted avenged ask"), W.Bounty.ASK_AFTER)
		local asks = Asks()
		eq(#asks, 1)
		local scope = ScopeOf(c)
		local list = asks[1]:match("^W7~1~" .. scope .. "~([%x,]+)$")
		assert(list, asks[1])
		local digests = {}
		for d in list:gmatch("[^,]+") do digests[#digests + 1] = d end
		eq(#digests, W.Bounty.ASK_MAX, "ASK_MAX of the five")
		for i = 1, W.Bounty.ASK_MAX do eq(digests[i], W.Bounty.AskDigest(guids[6 - i], scope), "the newest deaths' first") end
		for _, g in ipairs(guids) do
			assert(not asks[1]:find(g:match("%-(%x+)$"), 1, true) and not asks[1]:lower():find(g:match("%-(%x+)$"):lower(), 1, true), "no GUID")
		end
		assert(not asks[1]:find("Ganker", 1, true), "no name")
		eq(#asks[1] <= 255, true)
		-- Again ASK_EVERY later, ASK_TRIES in all.
		eq(Fire("wanted avenged ask"), W.Bounty.ASK_EVERY); eq(#Asks(), 2)
		eq(Fire("wanted avenged ask"), W.Bounty.ASK_EVERY); eq(#Asks(), 3)
		eq(Fire("wanted avenged ask"), nil, "ASK_TRIES at most")
		-- Every death avenged meanwhile: the next login asks nothing, and starts no timer.
		local avenger = w.participant("Asked Avenger-Realm", "Player-1-CC00E801")
		for i = 1, 5 do
			assert(w.commHandlers.WK("CHANNEL", avenger, BountyRow(c, W, { kind = "P", digest = ("%016x"):format(0xe800 + i), at = w.epoch,
				horde = ("1.0d00e8%02d"):format(i), own = "1.cc00e801", worth = "M~50~60", name = "Asked Ganker" .. i .. "-Realm" })))
		end
		eq(next(c.rdb.wanted.mine), nil)
		Clear()
		assert(W.Load())
		w.advance(W.Bounty.ASK_AFTER)
		eq(Fire("wanted avenged ask"), nil, "no death open: no ask"); eq(#Asks(), 3)
		-- The README's privacy table names it.
		local f = assert(io.open(ROOT .. "README.md", "rb"))
		local readme = f:read("*a")
		f:close()
		assert(readme:find("| Most Wanted, your avenged ask (W7, 1.2.4)", 1, true), "the README's privacy table")
	end)
end)

test("wanted 1.2.4 repair, the avenged ask (W7): its answers come from several clients in any order; the deaths wait ASK_SETTLE after the ask and each is avenged by the first kill after it, never by a later one heard first", function()
	WithWanted(function(w, W, c)
		w.manager, w.dead = false, false
		w.units.player.level = 40
		local Fire = Timers(c)
		local K = assert(w.commHandlers.WK)
		local ganker = "Player-1-0D00EA01"
		w.hordePlayer("Raced Ganker-Realm", ganker)
		local first = w.participant("First Slayer-Realm", "Player-1-CC00EA01")
		local second = w.participant("Second Slayer-Realm", "Player-1-CC00EA02")
		local diedAt = w.epoch
		w.die(w.forever("Raced-Realm", ganker))
		w.dead = false
		w.advance(6 * 3600)
		-- The ask goes (the channel took it).
		assert(W.Bounty.Ask())
		local ask = w.sent[#w.sent]
		eq(ask.text:sub(1, 3), "W7~")
		if ask.done then ask.done(true) end
		-- The later kill's answer first, then the earlier one's.
		assert(K("CHANNEL", second, BountyRow(c, W, { kind = "P", digest = "00000000000ea002", at = diedAt + 7200, horde = "1.0d00ea01",
			own = "1.cc00ea02", worth = "M~50~60", name = "Raced Ganker-Realm" })))
		eq(#AvengedShown(w), 0, "it waits for the other answers"); assert(c.rdb.wanted.mine[ganker], "still open")
		assert(K("CHANNEL", first, BountyRow(c, W, { kind = "P", digest = "00000000000ea001", at = diedAt + 3600, horde = "1.0d00ea01",
			own = "1.cc00ea01", worth = "M~50~60", name = "Raced Ganker-Realm" })))
		w.advance(W.Bounty.ASK_SETTLE)
		eq(Fire("wanted avenged settle"), W.Bounty.ASK_SETTLE)
		local shown = AvengedShown(w)
		eq(#shown, 1, "one notice")
		eq(shown[1].a, ns.L.WANTED_AVENGED:format(c.DisplayName(first), "Olympus II", c.DisplayName("Raced Ganker-Realm"), ""), "the first kill after his death")
		eq(c.rdb.wanted.mine[ganker], nil)
		-- Past the settle, a claim avenges at once again.
		local other = "Player-1-0D00EA02"
		w.hordePlayer("Prompt Ganker-Realm", other)
		w.die(w.forever("Prompt-Realm", other))
		w.dead = false
		shown[1].shown = false
		w.advance(60)
		assert(K("CHANNEL", first, BountyRow(c, W, { kind = "P", digest = "00000000000ea003", at = w.epoch, horde = "1.0d00ea02",
			own = "1.cc00ea01", worth = "M~50~60", name = "Prompt Ganker-Realm" })))
		eq(#AvengedShown(w), 2, "at once")
	end)
end)

test("wanted 1.2.4 repair, the avenged ask (W7) answered: a member's client answers with its own kills of a Horde player a digest names (its own row again), a reviewer's with the other members' too (his relay), oldest first, a moment later; a plain member never with another's row; nothing for its own echo, another realm group, a malformed ask, a hidden asker or past ASK_PER", function()
	WithWanted(function(w, W, c)
		w.manager, w.dead = false, false
		w.units.player.level = 45
		local me = w.units.player.guid
		local Fire = Timers(c)
		local A = assert(w.commHandlers.W7, "the W7 handler")
		local scope = ScopeOf(c)
		local ganker = "Player-1-0D00E901"
		w.hordePlayer("Answer Ganker-Realm", ganker)
		local other = "Player-1-0D00E902"
		w.hordePlayer("Other Ganker-Realm", other)
		-- This member's own kill of him, and another member's kill of another, both held here.
		w.units.target = { name = "Answer Ganker-Realm", guid = ganker, faction = "Horde", level = 50 }
		local ok, mine = w.handlers.PARTY_KILL(me, ganker)
		assert(ok, tostring(mine))
		w.units.target = nil
		local hand = w.participant("Answer Hand-Realm", "Player-1-CC00E901")
		w.advance(60)
		assert(w.commHandlers.WK("CHANNEL", hand, BountyRow(c, W, { kind = "P", digest = "00000000000e9001", at = w.epoch, horde = "1.0d00e902",
			own = "1.cc00e901", worth = "M~50~60", name = "Other Ganker-Realm" })))
		local asker = w.participant("Answer Asker-Realm", "Player-1-CC00E902")
		local function Ask(...)
			local d = {}
			for i, g in ipairs({ ... }) do d[i] = W.Bounty.AskDigest(g, scope) end
			return "W7~1~" .. scope .. "~" .. table.concat(d, ",")
		end
		local function Sent() return #w.sent end
		-- A plain member: his own kill, again; never the other member's.
		local before = Sent()
		eq(select(2, A("CHANNEL", asker, Ask(other))), "none", "another member's row: not his to send")
		eq(A("CHANNEL", asker, Ask(ganker, other)), true)
		eq(Sent(), before, "a moment later")
		Fire("wanted avenged answer")
		eq(Sent(), before + 1)
		local row = w.sent[#w.sent].text
		eq(row:sub(1, 5), "WK~2~"); assert(row:find(mine.digest, 1, true), "his own row again")
		-- Refused: his own echo, another realm group, malformed, past ASK_PER for one asker.
		eq(select(2, A("CHANNEL", c.me, Ask(ganker))), "own")
		eq(select(2, A("CHANNEL", asker, "W7~1~00000000000000ff~" .. W.Bounty.AskDigest(ganker, scope))), "scope")
		for _, bad in ipairs({ "W7~1~" .. scope .. "~", "W7~1~" .. scope .. "~abc", "W7~1~" .. scope .. "~" .. W.Bounty.AskDigest(ganker, scope) .. ",",
			"W7~1~" .. scope .. "~" .. string.rep(W.Bounty.AskDigest(ganker, scope) .. ",", 5):sub(1, -2), "W7~2~" .. scope .. "~00000000" }) do
			eq(select(2, A("CHANNEL", asker, bad)), "shape", bad)
		end
		eq(select(2, A("WHISPER", asker, Ask(ganker))), "lane")
		eq(A("CHANNEL", asker, Ask(ganker)), true, "the second answer to him")
		eq(select(2, A("CHANNEL", asker, Ask(ganker))), "rate", "ASK_PER")
		w.advance(W.Bounty.ASK_WINDOW)
		c.Moderation.Hides = function(name) return c.Fold(name) == c.Fold(asker) end
		eq(select(2, A("CHANNEL", asker, Ask(ganker))), "olympus", "a hidden asker")
		c.Moderation.Hides = nil
		-- A reviewer's client: the other member's row too, as his relay.
		w.authority(c.me, "council")
		local second = w.participant("Answer Second-Realm", "Player-1-CC00E903")
		w.sent = {}
		eq(A("CHANNEL", second, Ask(other)), true)
		Fire("wanted avenged answer"); Fire("wanted avenged answer")
		local relays = w.wire("WK~R~")
		eq(#relays, 1, "his relay of it"); assert(relays[1]:find("00000000000e9001", 1, true))
	end)
end)

test("wanted 1.2.4 repair, the avenged ask (W7) world: a member offline when his killer was slain, with no reviewer online at his next login, asks; the slayer's client answers with its own kill, and he is told who avenged him, once", function()
	WithWorld(function(world)
		local away = world:Client("Asleep-Realm", "Player-1-0A0000E1")
		local slayer = world:Client("Waker-Realm", "Player-1-0A0000E2")
		local third = world:Client("Bystander-Realm", "Player-1-0A0000E3")
		away.units.player.level, slayer.units.player.level = 30, 50
		local horde = "Player-1-0B0000E1"
		world.horde[horde] = "Sleeper Ganker-Realm"
		local name = ns.DisplayName("Sleeper Ganker-Realm")
		away.dead, away.recap = true, { { event = "SPELL_DAMAGE", sourceGUID = horde, sourceName = "Sleeper Ganker-Realm", sourceFlags = 0x548,
			overkill = 90, timestamp = world.epoch - 0.2 } }
		world:As(away, away.events.PLAYER_DEAD)
		away.dead, away.recap = false, nil
		world:Deliver()
		world:Offline(away)
		world.epoch = world.epoch + 3600
		-- Slain while he is away; then an evening of other rows (no reviewer online at all).
		slayer.units.target = { name = "Sleeper Ganker-Realm", guid = horde, faction = "Horde", level = 60 }
		assert(world:As(slayer, slayer.events.PARTY_KILL, slayer.guid, horde))
		slayer.units.target = nil
		world:Deliver()
		world.epoch = world.epoch + 6 * 3600
		-- His next login: the ask, ASK_AFTER after it; the slayer's answer; his notice once the
		-- answers settled (ASK_SETTLE after the ask).
		world:Load(away)
		world:Run(away.W.Bounty.ASK_AFTER - 1)
		eq(#AvengedShown(away), 0)
		local before = #world.log
		world:Run(10)
		eq(#AvengedShown(away), 0, "the answers settling")
		world:Run(away.W.Bounty.ASK_SETTLE)
		local asked
		for i = before + 1, #world.log do if world.log[i].text:sub(1, 3) == "W7~" then asked = world.log[i] end end
		assert(asked and asked.from == away and asked.dist == "CHANNEL", "his ask on the channel")
		eq(#world:As(away, away.W.Target, nil, horde).claims, 1, "the kill, from the slayer's own client")
		local told = AvengedShown(away)
		eq(#told, 1, "told who avenged him")
		eq(told[1].a, ns.L.WANTED_AVENGED:format(ns.DisplayName(slayer.name), "Olympus II", name, ""))
		eq(#AvengedShown(third), 0); eq(#AvengedShown(slayer), 0)
		told[1].shown = false
		-- Another login: nothing open, no ask, nothing again.
		before = #world.log
		world:Load(away)
		world:Run(away.W.Bounty.ASK_AFTER + away.W.Bounty.ASK_EVERY + 30)
		for i = before + 1, #world.log do assert(world.log[i].text:sub(1, 3) ~= "W7~", "no ask") end
		eq(#AvengedShown(away), 1, "once")
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
