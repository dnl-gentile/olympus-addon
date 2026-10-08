local ns, test, eq, H = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]guild%-charter%.lua$")) or "./"

local function Client()
	local w = { clock = 1800000000, guild = "Olympus Ember", rank = 0, member = true,
		locale = "enUS", class = "MAGE", jobs = {}, outside = {}, timers = {}, chats = {}, ranks = {} }
	local c = setmetatable({ me = "Nova Crown-Realm", realm = "Realm", group = "Realm", faction = "Alliance",
		L = setmetatable({}, { __index = ns.L }), db = {}, rdb = { guilds = {} }, Moderation = {}, RealmPages = {} }, { __index = ns })
	w.c = c
	c.Now = function() return w.clock end
	c.IsMember = function() return w.member end
	c.On, c.Fire, c.Log, c.Print = function() end, function() end, function() end, function() end
	c.After = function(seconds, key, fn) w.timers[key] = { seconds = seconds, fn = fn } end
	c.Every = c.After
	c.Who = { Listen = function(fn) w.whoListener = fn end, Search = function() w.who = true end }
	c.Roster = setmetatable({ RankOf = function(name) return w.ranks[c.FullName(name)] end }, { __index = ns.Roster })
	c.Authority = { Enforced = function() return false end }
	c.Comm = setmetatable({ loginAt = w.clock - 500, Handle = function() end, HandleOutside = function() end,
		DeliveredLogged = function() return w.logged ~= false end,
		Send = function(dist, msg, key, urgent, logged, done, opts)
			w.jobs[#w.jobs + 1] = { dist = dist, msg = msg, logged = logged, opts = opts }; return true
		end,
		Whisper = function(to, msg, key, urgent, logged, done, opts)
			w.jobs[#w.jobs + 1] = { to = to, msg = msg, logged = logged, opts = opts }; return true
		end,
		WhisperOutside = function(to, msg) w.outside[#w.outside + 1] = { to = to, msg = msg }; return true end,
	}, { __index = ns.Comm })
	c.Views = setmetatable({ ShowPage = function(key) w.page = key end }, { __index = ns.Views })
	c.UI = setmetatable({ WhisperText = function(name, text) w.letter = { name = name, text = text }; return true end }, { __index = ns.UI })
	local dialogs = {}; for key, value in pairs(StaticPopupDialogs) do dialogs[key] = value end
	for _, file in ipairs({ "Locales/GuildCharterText", "Data", "GuildCharter", "Recruit" }) do
		assert(loadfile(ROOT .. "Olympus/" .. file .. ".lua"))("Olympus", c)
	end
	w.dialog = StaticPopupDialogs.OLYMPUS_CHARTER_FIELD
	for key in pairs(StaticPopupDialogs) do if not dialogs[key] then StaticPopupDialogs[key] = nil end end
	for key, value in pairs(dialogs) do StaticPopupDialogs[key] = value end
	function w:As(fn, ...)
		local saved = { guild = GetGuildInfo, server = GetServerTime, locale = GetLocale, class = UnitClass, level = UnitLevel,
			info = C_ChatInfo, time = GetTime, say = SendChatMessage, dialog = StaticPopupDialogs.OLYMPUS_CHARTER_FIELD }
		GetGuildInfo = function() return self.guild, "Rank", self.rank end
		GetServerTime, GetTime, GetLocale = function() return self.clock end, function() return self.clock end, function() return self.locale end
		UnitClass = function() return self.class, self.class end
		UnitLevel = function() return 20 end
		C_ChatInfo = setmetatable({ SendAddonMessageLogged = function() end }, { __index = saved.info })
		SendChatMessage = function(text, dist, _, to) self.chats[#self.chats + 1] = { text = text, dist = dist, to = to } end
		StaticPopupDialogs.OLYMPUS_CHARTER_FIELD = self.dialog
		local result = { pcall(fn, ...) }
		GetGuildInfo, GetServerTime, GetLocale, UnitClass, GetTime, SendChatMessage = saved.guild, saved.server, saved.locale, saved.class, saved.time, saved.say
		UnitLevel, C_ChatInfo = saved.level, saved.info
		StaticPopupDialogs.OLYMPUS_CHARTER_FIELD = saved.dialog
		if not result[1] then error(result[2], 0) end
		return unpack(result, 2)
	end
	return w, c
end
local function Card(w, guild, by, language, wanted)
	return { guild = guild or "Olympus Ember", by = by or "Nova Crown-Realm", rev = w.clock,
		faction = w.c.faction == "Horde" and "H" or "A", language = language or "enUS",
		wanted = wanted or "MA", nights = "Fri 20:00", purpose = "Friendly dungeon groups" }
end
local function QuerySources(w, c)
	w.member, w.guild, w.rank = false, nil, nil
	c.Recruit.found = { { name = "Echo Scout-Realm", guild = "Olympus Ember" },
		{ name = "Sage Scout-Realm", guild = "Olympus Willow" }, { name = "Third Scout-Realm", guild = "Olympus Grove" } }
	c.GuildCharter.Ask("Echo Scout-Realm"); c.GuildCharter.Ask("Sage Scout-Realm")
end
local function Names(list)
	local names = {}; for _, g in ipairs(list) do names[#names + 1] = type(g) == "table" and g.name or g end
	return table.concat(names, ",")
end

test("Guild charter: actual editing preserves bounds, canonical classes, logged transport and delivery-time authority", function()
	local w, c = Client()
	w:As(function()
		local G = c.GuildCharter
		eq(G.SetField("purpose", " Friendly\n dungeon |groups~ "), true)
		eq(G.SetField("wanted", "PRIEST,MAGE"), true)
		eq(G.SetField("nights", string.rep("x", 50)), true)
		local card = assert(G.Ours()); eq(card.purpose, "Friendly dungeon groups"); eq(card.wanted, "MA,PR")
		eq(#card.nights, G.NIGHTS_MAX); eq(#w.jobs, 0, "edits coalesce before publishing")
		eq(G.SetField("language", "unknown"), false); eq(G.SetField("wanted", "MAGE,MAGE"), false)
		w.timers["guild charter"].fn()
		eq(#w.jobs, 1); eq(w.jobs[1].dist, "CHANNEL"); eq(w.jobs[1].logged, true); assert(#w.jobs[1].msg <= 250)
		eq(G.Parse(w.jobs[1].msg, c.me).wanted, "MA,PR")
		eq(w.jobs[1].opts.guard(), true)
		w.rank = 1; eq(w.jobs[1].opts.guard(), false); eq(G.SetField("purpose", "Not authorized"), false); eq(G.Send(true), false)
		w.rank = 0; w.guild = "Olympus Willow"; eq(w.jobs[1].opts.guard(), false); eq(G.Ours(), nil)
		w.guild = "Olympus Ember"; w.clock = w.clock + G.LIFE + 61; eq(G.Ours(), nil, "repeating cannot renew an expired edit")
	end)
end)

test("Guild charter: current roster and actual two-report rank verification reject forged, stale, wrong-faction and unlogged cards", function()
	local w, c = Client()
	w:As(function()
		local G, card = c.GuildCharter, Card(w)
		local msg = G.Encode(card)
		w.ranks[card.by] = 0
		eq(G.Handle("CHANNEL", card.by, msg), true); eq(G.Get(card.guild).by, card.by)
		eq(G.Letter(card.guild), false, "a master cannot draft a transfer letter to themself")
		eq(G.Handle("WHISPER", card.by, msg), false)
		eq(G.Handle("CHANNEL", "Pretender-Realm", msg), false)
		w.ranks[card.by] = 1; eq(G.Get(card.guild), nil, "rank loss removes held authority")
		w.guild = "Olympus Willow"; w.ranks = {}; c.me = "Reed Reader-Realm"
		local function Report(source, leader)
			return c.Data.Receive({ guild = card.guild, leader = leader or "Nova Crown", total = 20, online = 2,
				faction = "Alliance", officers = {}, zones = {} }, source)
		end
		eq(Report("Echo Scout-Realm"), true); eq(G.Handle("CHANNEL", card.by, msg), false, "one report cannot prove a master")
		eq(Report("Sage Scout-Realm"), true); eq(G.Handle("CHANNEL", card.by, msg), true)
		w.logged = false; card.rev = card.rev + 1
		eq(G.Handle("CHANNEL", card.by, G.Encode(card)), false)
		w.logged = true
		eq(G.Handle("CHANNEL", card.by, msg:gsub("GC~1~A", "GC~1~H")), false)
		eq(G.Parse(msg:gsub("GC~1", "GC~2"), card.by), nil)
		eq(G.Parse(msg:gsub("enUS", "fake"), card.by), nil)
		eq(G.Parse(msg .. "~injected", card.by), nil)
		eq(G.Letter(card.guild), true); eq(w.letter.name, "Nova Crown"); assert(w.letter.text:find(card.guild, 1, true))
		eq(#w.chats, 0); eq(#w.jobs, 0, "the transfer letter is only a draft")
		c.Filter = { Hides = function() return true end }
		eq(G.CardLines(card.guild)[2].text, c.L.CHARTER_PURPOSE .. ": " .. c.L.FILTER_WORDS_HIDDEN_SHORT)
		eq(G.CardLines(card.guild)[4].text, c.L.CHARTER_NIGHTS .. ": " .. c.L.FILTER_WORDS_HIDDEN_SHORT)
		c.Filter = nil
		local disputed = { guild = card.guild, leader = "Nova Crown", total = 1000, online = 2,
			faction = "Alliance", officers = {}, zones = {} }
		c.Data.Receive(disputed, "Third Scout-Realm")
		eq(G.Get(card.guild), nil, "a disputed census does not authenticate a new public card")
		eq(G.Letter(card.guild), false, "the draft rechecks live master authority")
		w.clock = w.clock + c.Data.FRESH + 1; eq(G.Handle("CHANNEL", card.by, msg), false, "stale census cannot admit a master's card")
	end)
end)

test("Guild charter: queried distinct members corroborate exact cards; conflicting issuer/revision, replay, unknown source and expiry fail closed", function()
	local w, c = Client()
	w:As(function()
		local G, card = c.GuildCharter, Card(w)
		QuerySources(w, c)
		local msg = G.Encode(card, "QD")
		eq(G.OnReported("Unasked-Realm", msg), false)
		eq(c.Recruit.OnRoute("Echo Scout-Realm", msg), true); eq(G.Reported(card.guild), nil)
		eq(G.OnReported("Echo Scout-Realm", msg), true); eq(G.Reported(card.guild), nil, "a repeated source is still one source")
		eq(G.OnReported("Sage Scout-Realm", msg), true); eq(G.Reported(card.guild).purpose, card.purpose)
		eq(#w.chats, 0, "corroboration sends no user chat or invitation")
		card.rev = card.rev + 1
		eq(G.OnReported("Echo Scout-Realm", G.Encode(card, "QD")), true); eq(G.Reported(card.guild), nil)
		eq(G.OnReported("Echo Scout-Realm", msg), false, "old replay cannot replace a newer report from the same source")
		eq(G.OnReported("Sage Scout-Realm", G.Encode(card, "QD")), true); assert(G.Reported(card.guild))
		card.by = "Other Crown-Realm"
		eq(G.OnReported("Sage Scout-Realm", G.Encode(card, "QD")), true); eq(G.Reported(card.guild), nil)
		w.clock = w.clock + G.ASK_WAIT + 1; eq(G.OnReported("Sage Scout-Realm", msg), false)
		w.clock = w.clock + G.REPORT_LIFE; eq(G.Reported(card.guild), nil)
	end)
end)

test("Guild charter: actual /who route asks correlate charter replies and bound independent confirmation", function()
	local w, c = Client()
	w:As(function()
		w.member, w.guild, w.rank = false, nil, nil
		local G, R = c.GuildCharter, c.Recruit
		R.OnFound({ { name = "Echo Scout-Realm", guild = "Olympus Ember" },
			{ name = "Sage Scout-Realm", guild = "Olympus Willow" }, { name = "Third Scout-Realm", guild = "Olympus Grove" },
			{ name = "Fourth Scout-Realm", guild = "Olympus Branch" } })
		eq(#w.outside, 2); eq(w.outside[1].msg, "J1~1"); eq(w.outside[2].msg, "QC~1~A")
		local card = Card(w); local msg = G.Encode(card, "QD")
		eq(R.OnRoute("Echo Scout-Realm", msg), true)
		eq(#w.outside, 4); eq(w.outside[3].to, "Sage Scout"); eq(w.outside[4].msg, "QC~1~A")
		eq(R.OnRoute("Sage Scout-Realm", msg), true); assert(G.Reported(card.guild)); eq(#w.outside, 4)
		card.rev = card.rev + 1
		eq(R.OnRoute("Echo Scout-Realm", G.Encode(card, "QD")), true); eq(G.Reported(card.guild), nil)
		eq(#w.outside, 6); eq(w.outside[5].to, "Third Scout")
		eq(R.OnRoute("Third Scout-Realm", msg), true); eq(#w.outside, 6, "three route/card sources, never a fourth")
		eq(R.OnRoute("Fourth Scout-Realm", msg), false)
		eq(R.OnRoute("Sage Scout-Realm", "J2~y~~0~Olympus Ember=10=Echo Scout"), true)
		eq(R.Route().byName["Olympus Ember"].free, 10, "the original J2 remains independent of the card")
		eq(#w.chats, 0); eq(#w.jobs, 0, "confirmation asks only addons, not player chat")
	end)
end)

test("Guild charter: Join orders gates, language, class, local friend and room; unknown cards retain ordinary routing and contact requires /who", function()
	local w, c = Client()
	w:As(function()
		local G, R = c.GuildCharter, c.Recruit
		QuerySources(w, c)
		R.ConfirmCharters = function() return false end -- transport solicitation is covered separately
		R.found[#R.found + 1] = { name = "Mira Friend-Realm", guild = "Olympus Ember" }
		R.found[#R.found + 1] = { name = "Gate Keeper-Realm", guild = "Olympus Gates" }
		R.route = { t = w.clock, list = { { name = "Olympus Willow", free = 800 }, { name = "Olympus Grove", free = 500 },
			{ name = "Olympus Ember", free = 10 }, { name = "Olympus Gates", free = 5 } }, byName = {
			["Olympus Willow"] = { free = 800 }, ["Olympus Grove"] = { free = 500 },
			["Olympus Ember"] = { free = 10 }, ["Olympus Gates"] = { free = 5 } } }
		eq(Names(R.Guilds()), "Olympus Willow,Olympus Grove,Olympus Ember,Olympus Gates")
		for _, spec in ipairs({ { "Olympus Willow", "ptBR", "MA" }, { "Olympus Grove", "enUS", "PR" },
			{ "Olympus Ember", "enUS", "MA" } }) do
			local msg = G.Encode(Card(w, spec[1], nil, spec[2], spec[3]), "QD")
			G.OnReported("Echo Scout-Realm", msg); G.OnReported("Sage Scout-Realm", msg)
		end
		eq(Names(R.Guilds()), "Olympus Ember,Olympus Grove,Olympus Willow,Olympus Gates")
		eq(Names(R.RouteOrder(R.Route())), Names(R.Guilds()), "both visible routing lists agree")
		local route = R.Route
		R.Route = function() local r = route(); r.gates = "Olympus Gates"; return r end
		eq(Names(R.Guilds()), "Olympus Gates,Olympus Ember,Olympus Grove,Olympus Willow", "open gates beat affinity")
		R.Route = route
		local grove = Card(w, "Olympus Grove"); G.OnReported("Echo Scout-Realm", G.Encode(grove, "QD")); G.OnReported("Sage Scout-Realm", G.Encode(grove, "QD"))
		eq(R.Guilds()[1].name, "Olympus Grove", "equal language/class use room")
		w.class = nil; eq(G.Affinity("Olympus Ember")[2], 0, "an unavailable class cannot imply demand"); w.class = "MAGE"
		eq(G.SetFriend("Mira Friend-Realm"), true); eq(R.Guilds()[1].name, "Olympus Ember", "friend only from /who in that guild")
		local sent = #w.outside; G.SetFriend(""); eq(#w.outside, sent, "friend preference is never sent")
		R.route.byName["Olympus Ember"].contacts = { "Invented Officer-Realm" }
		assert(R.NextContact("Olympus Ember").name ~= "Invented Officer-Realm", "charter/route cannot invent a /who contact")
		local contact = R.NextContact("Olympus Ember")
		eq(R.Ask(contact, "Hi! May I join your dungeon groups?"), true); eq(#w.chats, 1); eq(w.chats[1].dist, "WHISPER")
		eq(R.Ask(contact, "Again"), false); eq(#w.chats, 1, "one edited whisper from the click, with the original cooldown")
	end)
end)

test("Guild charter: actual Join view shows reported cards and local preference without creating chat", function()
	local w, c = Client()
	w:As(function()
		QuerySources(w, c)
		c.Recruit.ConfirmCharters = function() return false end
		local text = c.GuildCharter.Encode(Card(w), "QD")
		c.GuildCharter.OnReported("Echo Scout-Realm", text); c.GuildCharter.OnReported("Sage Scout-Realm", text)
		c.Who.StatusLines, c.Who.Searched = function() return {} end, function() return true end
		assert(loadfile(ROOT .. "Olympus/Views.lua"))("Olympus", c)
		local rows, reported, unknown, preference = c.Views.RecruitLines()
		for _, row in ipairs(rows) do
			if row.text == c.L.CHARTER_REPORTED:format(c.DisplayName("Nova Crown-Realm"), c.Ago(w.clock)) then reported = true end
			if row.text == c.L.CHARTER_UNKNOWN then unknown = true end
			if row.text == c.L.CHARTER_FRIEND_CHOOSE then preference = row end
		end
		assert(reported and unknown and preference and preference.onClick)
		eq(#w.chats, 0); eq(#w.jobs, 0, "rendering the charter never contacts anyone")
	end)
end)

test("Guild charter: private query answers are bounded, throttled and recheck source authority before delivery", function()
	local w, c = Client()
	w:As(function()
		local G = c.GuildCharter
		G.SetField("purpose", "Weekend dungeon groups")
		eq(G.HandleAsk("CHANNEL", "Echo Scout-Realm", "QC~1~A"), false)
		eq(G.HandleAsk("WHISPER", "Echo Scout-Realm", "QC~2~A"), false)
		eq(G.HandleAsk("WHISPER", "Echo Scout-Realm", "QC~1~H"), false)
		eq(G.HandleAsk("WHISPER", "Echo Scout-Realm", "QC~1~A"), true)
		eq(#w.jobs, 1); eq(w.jobs[1].to, "Echo Scout-Realm"); eq(w.jobs[1].logged, true); assert(#w.jobs[1].msg <= 250)
		eq(G.HandleAsk("WHISPER", "Echo Scout-Realm", "QC~1~A"), false)
		eq(w.jobs[1].opts.guard(), true); w.rank = 1; eq(w.jobs[1].opts.guard(), false)
		w.rank = 0
		for i = 1, 4 do
			local card = Card(w, "Olympus Branch " .. i, "Branch Crown " .. i .. "-Realm")
			for _, source in ipairs({ "Branch Scout " .. i .. "a-Realm", "Branch Scout " .. i .. "b-Realm" }) do
				eq(c.Data.Receive({ guild = card.guild, leader = "Branch Crown " .. i, total = 20, online = 2,
					faction = "Alliance", officers = {}, zones = {} }, source), true)
			end
			eq(G.Handle("CHANNEL", card.by, G.Encode(card)), true)
		end
		local before = #w.jobs
		eq(G.HandleAsk("WHISPER", "Second Reader-Realm", "QC~1~A"), true)
		eq(#w.jobs - before, G.ANSWER_MAX, "even a larger held list answers with three cards")
		for i = 3, 10 do eq(G.HandleAsk("WHISPER", "Reader " .. i .. "-Realm", "QC~1~A"), true) end
		eq(G.HandleAsk("WHISPER", "Over Limit-Realm", "QC~1~A"), false, "ten sources per minute bound the answering cache")
		w.clock = w.clock + 61; eq(G.HandleAsk("WHISPER", "Echo Scout-Realm", "QC~1~A"), true)
	end)
end)

test("Guild charter: master UI and local friend dialog use Olympus windows with gamepad and recheck stale edits", function()
	for _, gamepad in ipairs({ false, true }) do
		H.WithUI(function()
			H.WithGamepadUI(gamepad, function(game)
				local w, c = Client()
				w:As(function()
					c.GuildCharter.Prompt("purpose")
					local f = assert(ns.Dialog.Find("OLYMPUS_CHARTER_FIELD"))
					f.editBox:SetText("Weekend groups"); f.buttons[1]:Click()
					eq(c.GuildCharter.Ours().purpose, "Weekend groups")
					c.GuildCharter.Link().onClick(); eq(w.page, "guildcharter")
					local rows, editor = c.GuildCharter.Lines()
					for _, row in ipairs(rows) do if row.text == "> " .. c.L.CHARTER_EDIT_FIELD:format(c.L.CHARTER_NIGHTS) then editor = row end end
					assert(editor and editor.onClick); editor.onClick()
					f = assert(ns.Dialog.Find("OLYMPUS_CHARTER_FIELD")); f.editBox:SetText("Saturday")
					w.rank = 1; f.buttons[1]:Click(); eq(c.GuildCharter.Ours(), nil, "stale prompt cannot publish after rank loss")
					c.GuildCharter.Prompt("friend"); f = assert(ns.Dialog.Find("OLYMPUS_CHARTER_FIELD")); f.editBox:SetText("Mira Friend"); f.buttons[1]:Click()
					eq(c.db.recruitFriend, "Mira Friend-Realm"); eq(#w.jobs, 0); eq(#w.chats, 0)
					if gamepad then eq(#game.shown, 0, "no native game popup in gamepad mode") end
				end)
			end)
		end)
	end
end)

test("Guild charter: real outsider transport admits only charter requests/answers alongside unchanged Join messages", function()
	local saved = { guild = GetGuildInfo, inGuild = IsInGuild, info = C_ChatInfo }
	local ok, err = pcall(function()
		local c, deliver = H.FreshComm()
		GetGuildInfo = function() return nil end; IsInGuild = function() return false end
		local heard, sent = {}, {}
		c.Comm.HandleOutside(function(sender, text) heard[#heard + 1] = text end)
		C_ChatInfo.SendAddonMessage = function(prefix, text, dist, to) sent[#sent + 1] = { text = text, dist = dist, to = to }; return true end
		eq(c.Comm.WhisperOutside("Echo Scout", "QC~1~A"), true); eq(#sent, 1); eq(sent[1].dist, "WHISPER")
		eq(c.Comm.WhisperOutside("Echo Scout", "QD~1~A~x"), false)
		eq(c.Comm.WhisperOutside("Echo Scout", "GC~1~A~x"), false)
		deliver("WHISPER", "Echo Scout-Realm", "QD~1~A~card")
		deliver("CHANNEL", "Echo Scout-Realm", "QD~1~A~card")
		deliver("GUILD", "Echo Scout-Realm", "QD~1~A~card")
		deliver("WHISPER", "Echo Scout-Realm", "GC~1~A~card")
		eq(#heard, 1)
		GetGuildInfo = function() return "Olympus Ember" end; IsInGuild = function() return true end
		eq(c.Comm.WhisperOutside("Echo Scout", "QC~1~A"), false)
	end)
	GetGuildInfo, IsInGuild, C_ChatInfo = saved.guild, saved.inGuild, saved.info
	if not ok then error(err, 0) end
end)

test("Guild charter: Horde cards stay separate and Portuguese wording preserves reported status", function()
	local w, c = Client()
	w:As(function()
		c.faction, w.locale = "Horde", "ptBR"
		assert(loadfile(ROOT .. "Olympus/Locales/GuildCharterText.lua"))("Olympus", c)
		eq(c.GuildCharter.SetField("purpose", "Grupos de masmorra"), true)
		local msg = assert(c.GuildCharter.Encode(c.GuildCharter.Ours(), "QD"))
		assert(msg:find("QD~1~H~", 1, true)); assert(c.L.CHARTER_REPORTED:find("Dois membros", 1, true))
		eq(c.GuildCharter.Parse(msg:gsub("QD~1~H", "QD~1~A")), nil)
	end)
end)
