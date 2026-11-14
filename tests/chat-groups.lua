-- 1.5.5 (the dev on an RP character, 2026-11-10: [Olympus] lines from people whose guilds the roster
-- never showed and /who could not find, "tá chegando do PVP, tá chegando do PvE"). Forever's
-- player-made channels are one for every Forever realm, so the Olympus channel's text brings every
-- realm family's [Olympus] lines. They stay (the dev: "Keep it, show the server"), and each character
-- picks in the Chat tab's dropdown which families its [Olympus] shows: All (the default), a line of
-- another family with its tag before the name; or one family alone, without tags. The rank rooms stay
-- our family's. Fails before: no dropdown, no tag, every family's line shown, a [Captains] or [Lords]
-- line of another family taken where a report names its writer, and another family's line taken twice
-- under two stamps of that family.
local ns, test, eq, extra = ...
local WithWindow, ADDON_DIR = extra.WithWindow, extra.ADDON_DIR
local L = ns.L

local RP_REALM = "CAMWOWUS2Realm1RP"
local ME = "Rose Thornwood-" .. RP_REALM
local PVE = "Pve Speaker-CAMWOWUS1Realm2PvE"     -- a player of the PvE realms
local PVP = "Pvp Shouter-CAMWOWUS1Realm4PvP"     -- of the PvP realms
local RP_OTHER = "Rp Friend-CAMWOWUS2Realm5RP"   -- our family, another sub-realm (a guildmate)
local RP_HERE = "Rp Neighbour-" .. RP_REALM       -- our own sub-realm (a guildmate)

local function Tag(kind) return "[" .. L["CHATWIN_GROUP_" .. kind] .. "]" end
local KINDS = { "PVP", "PVE", "RP", "RPPVP" }
local function Untagged(text)
	for _, k in ipairs(KINDS) do
		if tostring(text):find(Tag(k), 1, true) then return false end
	end
	return true
end

-- An RP character of Forever (names split, his sub-realm and family), choosing nothing yet.
local function AsRpCharacter(fn)
	local saved = { realm = ns.realm, group = ns.group, split = ns.splitNames, me = ns.me, groups = ns.db.chatGroups }
	local ok, err = pcall(function()
		ns.splitNames, ns.realm, ns.group, ns.me = true, RP_REALM, "ForeverRP", ME
		ns.db.chatGroups = nil
		fn()
	end)
	ns.realm, ns.group, ns.splitNames, ns.me, ns.db.chatGroups = saved.realm, saved.group, saved.split, saved.me, saved.groups
	if not ok then error(err, 0) end
end

-- (Changed on purpose in 1.5.9.) Each line as 1.5.9 keeps it: with the ruleset it was filed under as
-- it came (kind, Channels.LineRoom). 1.5.5 worked it out of the sender's stamp at each view, and on
-- Forever the channel's text names its sender bare, so another ruleset's line went under the viewer's
-- own (the dev on RP-PvP, 2026-11-12: "essa pessoa mandou do PVE e a mensagem dela não apareceu no PVE.
-- No all aparece e no RPPVP também aparece"). What these views show of such lines is unchanged; lines
-- kept before 1.5.9, with no kind, have a test of their own (tests/chat-rulesets.lua).
local function Entry(t, sender, text, mine, kind)
	return { t = t, sender = sender, guild = "Olympus Thorns", text = text, mine = mine, kind = kind }
end
local HISTORY = {
	{ 1000, RP_HERE, "from my own sub-realm", nil, "rp" },
	{ 1010, PVE, "from the PvE realms", nil, "pve" },
	{ 1020, RP_OTHER, "from another RP sub-realm", nil, "rp" },
	{ 1030, PVP, "from the PvP realms", nil, "pvp" },
	{ 1040, ME, "my own words", true, "rp" },
}
local function History()
	local list = {}
	for _, h in ipairs(HISTORY) do list[#list + 1] = Entry(h[1], h[2], h[3], h[4], h[5]) end
	return list
end
-- The tab's bubbles shown, by their line's words.
local function Bubbles(f)
	local out = {}
	for _, b in ipairs(f.bubbles) do
		if b:IsShown() and b.entry then out[b.entry.text] = b end
	end
	return out
end
local function Shown(f)
	local n = 0
	for _ in pairs(Bubbles(f)) do n = n + 1 end
	return n
end
-- The dropdown's list as it shows: its rows' words, and the one lit.
local function MenuRows(f)
	local rows, lit = {}, nil
	for _, r in ipairs(f.subMenu.rows) do
		if r:IsShown() then
			rows[#rows + 1] = r
			if r.mark:IsShown() then lit = r.text:GetText() end
		end
	end
	return rows, lit
end
local function Pick(f, label)
	assert(f.groups:IsShown(), "the realm types' dropdown on the top row")
	f.groups:Click()
	assert(f.subMenu:IsShown(), "its list")
	for _, r in ipairs((MenuRows(f))) do
		if r.text:GetText() == label then return r:Click() end
	end
	error("no row " .. tostring(label))
end

test("chat groups (1.5.5): under All, the default, the RP character's [Olympus] shows a PvE line with [PvE] before the name and a PvP line with [PvP]; our family's lines, from our sub-realm or another, and our own, without a tag", function()
	AsRpCharacter(function()
		WithWindow(function(w)
			ns.me = ME
			ns.rdb.chat = { A = History() }
			local f = w.CW.Open("A")
			eq(Shown(f), 5, "every line")
			local b = Bubbles(f)
			local who = b["from the PvE realms"].who:GetText()
			local at, name = who:find(Tag("PVE"), 1, true), who:find("Pve Speaker", 1, true)
			assert(at and name and at < name, "the PvE tag before the name: " .. tostring(who))
			who = b["from the PvP realms"].who:GetText()
			at, name = who:find(Tag("PVP"), 1, true), who:find("Pvp Shouter", 1, true)
			assert(at and name and at < name, "the PvP tag before the name: " .. tostring(who))
			for _, text in ipairs({ "from my own sub-realm", "from another RP sub-realm", "my own words" }) do
				assert(Untagged(b[text].who:GetText()), "no tag: " .. tostring(b[text].who:GetText()))
			end
			assert(f.groups:IsShown(), "the dropdown, with its arrow, on the top row")
			eq(f.groups.text:GetText(), L.CHATWIN_GROUP_ALL)
			assert(f.groups.arrow:IsShown())
			-- Its list: the dev's choices, All lit.
			f.groups:Click()
			local rows, lit = MenuRows(f)
			local words = {}
			for _, r in ipairs(rows) do words[#words + 1] = r.text:GetText() end
			eq(table.concat(words, ","), table.concat({ L.CHATWIN_GROUP_ALL, L.CHATWIN_GROUP_PVP, L.CHATWIN_GROUP_PVE,
				L.CHATWIN_GROUP_RP, L.CHATWIN_GROUP_RPPVP }, ","))
			eq(lit, L.CHATWIN_GROUP_ALL)
			f.subCatcher:Click()
			-- Not on another channel, nor off Forever.
			ns.splitNames = nil
			w.CW.Render()
			eq(f.groups:IsShown(), false, "off Forever: one family, no dropdown")
			assert(Untagged(Bubbles(f)["from the PvE realms"].who:GetText()))
		end)
	end)
end)

test("chat groups (1.5.5): under PvE, the RP character's [Olympus] shows the PvE lines alone, without a tag (his own lines still); RP shows his own family's alone; a line hidden so adds to no count", function()
	AsRpCharacter(function()
		WithWindow(function(w)
			ns.me = ME
			ns.rdb.chat = { A = History() }
			local f = w.CW.Open("A")
			Pick(f, L.CHATWIN_GROUP_PVE)
			eq(f.subMenu:IsShown(), false, "the list closes")
			eq(f.groups.text:GetText(), L.CHATWIN_GROUP_PVE)
			local b = Bubbles(f)
			assert(b["from the PvE realms"], "the PvE line")
			assert(Untagged(b["from the PvE realms"].who:GetText()), "without its tag: " .. tostring(b["from the PvE realms"].who:GetText()))
			assert(b["my own words"], "our own line always shows")
			eq(b["from my own sub-realm"], nil); eq(b["from another RP sub-realm"], nil); eq(b["from the PvP realms"], nil)
			eq(Shown(f), 2)
			-- Its list lights the choice.
			f.groups:Click()
			local _, lit = MenuRows(f)
			eq(lit, L.CHATWIN_GROUP_PVE)
			f.subCatcher:Click()
			-- Our own family's lines alone: as before the channel mixed them.
			Pick(f, L.CHATWIN_GROUP_RP)
			b = Bubbles(f)
			assert(b["from my own sub-realm"] and b["from another RP sub-realm"] and b["my own words"])
			eq(b["from the PvE realms"], nil); eq(b["from the PvP realms"], nil)
			for _, bubble in pairs(b) do assert(Untagged(bubble.who:GetText())) end
			-- RP-PvP: none kept; the empty view says so.
			Pick(f, L.CHATWIN_GROUP_RPPVP)
			eq(Shown(f), 1, "our own line alone")
			-- Lines that come while another room shows: a line of the family chosen counts, another doesn't.
			Pick(f, L.CHATWIN_GROUP_PVE)
			eq(w.CW.SelectLogical("guild"), true)
			-- (1.5.9: CHAT_LINE carries the line kept, filed under its ruleset as it came.)
			w.fire("CHAT_LINE", "A", RP_OTHER, "unseen", Entry(1050, RP_OTHER, "unseen", nil, "rp"))
			eq(w.CW.Unread("A"), 0, "a line the choice hides counts for nothing")
			w.fire("CHAT_LINE", "A", PVE, "seen", Entry(1060, PVE, "seen", nil, "pve"))
			eq(w.CW.Unread("A"), 1)
		end)
	end)
end)

test("chat groups: a census update leaves the ruleset menu open while the player chooses PvE", function()
	AsRpCharacter(function()
		WithWindow(function(w)
			ns.me = ME
			ns.rdb.chat = { A = History() }
			local f = w.CW.Open("A")
			f.groups:Click()
			assert(f.subMenu:IsShown(), "the menu opens from All")
			f.groups:GetScript("OnLeave")(f.groups)
			w.fire("DATA_CHANGED")
			assert(f.subMenu:IsShown(), "an incoming census report must not close the menu")
			local rows = MenuRows(f)
			local pve = rows[3]
			eq(pve.text:GetText(), L.CHATWIN_GROUP_PVE)
			pve:GetScript("OnEnter")(pve)
			w.fire("DATA_CHANGED")
			assert(f.subMenu:IsShown(), "an incoming report must not cancel the hovered option")
			pve:Click()
			eq(f.subMenu:IsShown(), false)
			eq(f.groups.text:GetText(), L.CHATWIN_GROUP_PVE)
			assert(Bubbles(f)["from the PvE realms"])
			eq(Bubbles(f)["from the PvP realms"], nil)
		end)
	end)
end)

test("chat groups (1.5.5): the choice is this character's and survives a /reload: the Chat tab made anew shows PvE and its lines alone; another character of the account shows All", function()
	AsRpCharacter(function()
		WithWindow(function(w)
			ns.me = ME
			ns.rdb.chat = { A = History() }
			Pick(w.CW.Open("A"), L.CHATWIN_GROUP_PVE)
		end)
		-- A /reload: ChatWindow.lua and the Olympus window loaded anew, the saved variables as they were.
		WithWindow(function(w)
			ns.me = ME
			ns.rdb.chat = { A = History() }
			local f = w.CW.Open("A")
			eq(f.groups.text:GetText(), L.CHATWIN_GROUP_PVE, "the choice kept")
			eq(ns.Channels.GroupView(), "pve")
			local b = Bubbles(f)
			assert(b["from the PvE realms"] and b["my own words"]); eq(Shown(f), 2)
		end)
		WithWindow(function(w)
			ns.me = "Other Alt-" .. RP_REALM
			ns.rdb.chat = { A = History() }
			local f = w.CW.Open("A")
			eq(f.groups.text:GetText(), L.CHATWIN_GROUP_ALL, "another character: his own choice, All")
			eq(Shown(f), 5)
		end)
		-- A saved value no version wrote: All.
		ns.db.chatGroups = { [ME] = "somewhere" }
		eq(ns.Channels.GroupView(), "all")
		eq(ns.Channels.SetGroupView("somewhere"), false)
	end)
end)

-- Our guild on an RP realm of Forever, its master on our client (he reads every channel); each line
-- printed in the game's chat (none muted there) kept in `printed`.
local function RpGuild(fn)
	local saved = { total = GetNumGuildMembers, info = GetGuildRosterInfo, guild = GetGuildInfo, member = ns.IsMember,
		chat = ns.db.addonChat, mute = ns.db.chatMute, windows = ns.db.chatWindows, history = ns.rdb.chat, guilds = ns.rdb.guilds,
		frame = DEFAULT_CHAT_FRAME, hides = ns.Moderation.Hides }
	local ok, err = pcall(function()
		AsRpCharacter(function()
			ns.IsMember = function() return true end
			GetGuildInfo = function() return "Olympus Thorns", "Master", 0 end
			local rows = { { "Rose Thornwood", "Master", 0 }, { "Rp Friend", "Member", 3 }, { "Rp Neighbour", "Member", 3 } }
			GetNumGuildMembers = function() return #rows, #rows end
			GetGuildRosterInfo = function(i)
				local r = rows[i]
				if r then return r[1], r[2], r[3], 60, "Warrior", "Stormwind City", "", "", true, 0, "WARRIOR" end
			end
			ns.Roster.Scan()
			ns.db.addonChat, ns.db.chatMute, ns.db.chatWindows, ns.rdb.chat, ns.rdb.guilds = true, {}, nil, {}, {}
			local printed = {}
			DEFAULT_CHAT_FRAME = { AddMessage = function(_, line) printed[#printed + 1] = line end }
			fn(printed)
		end)
	end)
	GetNumGuildMembers, GetGuildRosterInfo, GetGuildInfo, ns.IsMember = saved.total, saved.info, saved.guild, saved.member
	ns.db.addonChat, ns.db.chatMute, ns.db.chatWindows, ns.rdb.chat, ns.rdb.guilds = saved.chat, saved.mute, saved.windows, saved.history, saved.guilds
	DEFAULT_CHAT_FRAME, ns.Moderation.Hides = saved.frame, saved.hides
	ns.Roster.Scan()
	if not ok then error(err, 0) end
end
local function Line(tier, guild, id, text) return ns.Codec.EncodeChat(tier, guild, id, "WA", text) end
local function Kept(tier, text)
	local n = 0
	for _, e in ipairs(ns.rdb.chat and ns.rdb.chat[tier] or {}) do if e.text == text then n = n + 1 end end
	return n
end

test("chat groups (1.5.5): in the game's chat too, under All a PvE line comes with [PvE] before the name and a guildmate's without; under PvE our family's lines are kept unprinted; the moderators' word still drops a line of any family", function()
	RpGuild(function(printed)
		local C = ns.Channels
		local shown, why = C.Receive("CHANNEL", PVE, Line("A", "Olympus Dawn", 5101, "hello from the PvE realms"), 9100)
		eq(shown, true, why)
		local line = printed[#printed] or ""
		local at, name = line:find(Tag("PVE"), 1, true), line:find("|Hplayer:", 1, true)
		assert(at and name and at < name, "the tag before the name: " .. line)
		shown, why = C.Receive("CHANNEL", RP_OTHER, Line("A", "Olympus Thorns", 5102, "hello from RP"), 9110)
		eq(shown, true, why)
		assert(Untagged(printed[#printed]), "a guildmate on another RP sub-realm, as before: " .. printed[#printed])
		eq(Kept("A", "hello from the PvE realms"), 1); eq(Kept("A", "hello from RP"), 1)
		-- PvE alone: our family's line is kept (the Chat tab, a companion), not printed; a PvE one, untagged.
		eq(C.SetGroupView("pve"), true)
		local before = #printed
		shown, why = C.Receive("CHANNEL", RP_HERE, Line("A", "Olympus Thorns", 5103, "our own family"), 9120)
		eq(shown, false); eq(why, "group")
		eq(#printed, before, "not printed"); eq(Kept("A", "our own family"), 1, "kept")
		shown, why = C.Receive("CHANNEL", "Pve Second-CAMWOWUS1Realm3PvE", Line("A", "Olympus Dawn", 5104, "more PvE"), 9130)
		eq(shown, true, why)
		assert(Untagged(printed[#printed]), "no tag where one family shows: " .. printed[#printed])
		-- Moderation as before, on every family's lines.
		ns.Moderation.Hides = function(who) if ns.ShortName(who) == "Pve Hidden" then return { kind = "c" } end end
		shown, why = C.Receive("CHANNEL", "Pve Hidden-CAMWOWUS1Realm2PvE", Line("A", "Olympus Dawn", 5105, "hidden by the moderators"), 9140)
		eq(why, "netoff"); eq(Kept("A", "hidden by the moderators"), 0)
		C.SetGroupView("all")
	end)
end)

test("chat groups (1.5.5): a [Captains] or [Lords] line of another realm family is never verified nor shown, even where a report names its writer, and /oly bug's chat line counts it; our own family's officers speak there as before", function()
	RpGuild(function(printed)
		local C = ns.Channels
		-- Two reports of an RP guild of our family; its officers' list names one of them with a PvE stamp.
		local function Rep() return { guild = "Olympus Dawn", total = 40, online = 9, zones = {}, leader = "Dawn Master-CAMWOWUS1Realm7PvE",
			officers = { { name = "Dawn Captain", online = true, days = 0 }, { name = "Dawn Officer-CAMWOWUS1Realm5PvE", online = true, days = 0 } } } end
		ns.Data.Receive(Rep(), "Dawn Reporter-CAMWOWUS2Realm3RP")
		ns.Data.Receive(Rep(), "Dawn Witness-CAMWOWUS2Realm6RP")
		eq(ns.Data.KnownRank("Dawn Officer-CAMWOWUS1Realm5PvE", "Olympus Dawn"), 1, "(the reports name him an officer)")
		local counts = C.Stats()
		local ordinaryRank, before = counts.rank or 0, counts.otherRank or 0
		local shown, why = C.Receive("CHANNEL", "Dawn Officer-CAMWOWUS1Realm5PvE", Line("C", "Olympus Dawn", 5201, "captains, to me"), 9200)
		eq(shown, false); eq(why, "unverified", "never verified: another family's")
		eq(Kept("C", "captains, to me"), 0, "not kept: not shown in [Captains]")
		shown, why = C.Receive("CHANNEL", "Dawn Master-CAMWOWUS1Realm7PvE", Line("L", "Olympus Dawn", 5202, "lords, to me"), 9210)
		eq(shown, false); eq(why, "unverified")
		eq(Kept("L", "lords, to me"), 0)
		eq((C.Stats().otherRank or 0) - before, 2, "counted")
		eq(C.Stats().rank or 0, ordinaryRank, "foreign-family rejections do not change ordinary rank counts")
		local bug = ns.StatusText():match("\nchat: [^\n]*") or ""
		assert(bug:find("rank=" .. (ordinaryRank + before + 2) .. " ", 1, true), "ordinary and foreign-family rejections in /oly bug's chat line: " .. bug)
		-- Our family's officer, as before.
		shown, why = C.Receive("CHANNEL", "Dawn Captain-CAMWOWUS2Realm7RP", Line("C", "Olympus Dawn", 5203, "our family's captain"), 9220)
		eq(shown, true, why)
		eq(Kept("C", "our family's captain"), 1)
		assert(Untagged(printed[#printed]))
	end)
end)

test("chat groups (1.5.5): another family's line is taken once, under the same stamp or another sub-realm of that family; another family's namesake is someone else", function()
	RpGuild(function()
		local C = ns.Channels
		local text = Line("A", "Olympus Dawn", 5301, "once only")
		local shown, why = C.Receive("CHANNEL", "Pve Twice-CAMWOWUS1Realm2PvE", text, 9300)
		eq(shown, true, why)
		shown, why = C.Receive("CHANNEL", "Pve Twice-CAMWOWUS1Realm2PvE", text, 9301)
		eq(why, "dup", "the same copy again")
		shown, why = C.Receive("CHANNEL", "Pve Twice-CAMWOWUS2Realm8PvE", text, 9302)
		eq(why, "dup", "the relay's copy, stamped with another PvE sub-realm")
		eq(Kept("A", "once only"), 1)
		shown, why = C.Receive("CHANNEL", "Pve Twice-CAMWOWUS1Realm4PvP", text, 9303)
		eq(shown, true, "the PvP realms' namesake is another player: " .. tostring(why))
		eq(Kept("A", "once only"), 2)
	end)
end)

-- The addon's own event dispatcher (Core.lua), found by a probe: no other frame's.
local function Dispatcher(probeEvent)
	local hit = false
	ns.RegisterEvent(probeEvent, function() hit = true end)
	for _, f in ipairs(EVENT_SCRIPTS) do
		hit = false
		pcall(f, nil, probeEvent, "probe", "Probe-Realm")
		if hit then return f end
	end
	error("no dispatcher")
end

test("chat groups (1.5.5): a channel line whose sender is secret is skipped unread, before any family is read; a plain one from another family is taken", function()
	local savedSecret, savedCapture = rawget(_G, "issecretvalue"), ns.CaptureError
	local probing, injected, errors = true, {}, {}
	local ok, err = pcall(function()
		local dispatch = Dispatcher("CHAT_MSG_OLYMPUS_GROUPS_PROBE")
		local secret = setmetatable({}, { __index = function() error("a secret value was read") end,
			__len = function() error("a secret value was measured") end, __eq = function() error("a secret value was compared") end })
		issecretvalue = function(v) return rawequal(v, secret) end
		ns.CaptureError = function(where, e) errors[#errors + 1] = where .. ": " .. tostring(e) end
		-- The chat hall as a Forever login installs it: its handler with the addon's own dispatcher.
		local login
		local cns = setmetatable({
			splitNames = true,
			Comm = { ChannelIndex = function() return 6 end, ChannelName = function() return "OlympusNet1" end,
				Inject = function(dist, sender, text) if probing then injected[#injected + 1] = { sender = sender, text = text } end end },
			Gate = { Allowed = function() return true end },
			On = function(name, fn) if name == "LOGIN" then login = fn end end,
			SafeCall = function(_, fn, ...) return fn(...) end,
		}, { __index = ns })
		assert(loadfile(ADDON_DIR .. "ChatHall.lua"))("Olympus", cns)
		login()
		local before = ns.secretChatSkipped
		dispatch(nil, "CHAT_MSG_CHANNEL", "M1~A~Olympus Dawn~7~WA~hello", secret, "", "6. OlympusNet1", "", "", 0, 6, "OlympusNet1")
		eq(#injected, 0, "the secret sender's line reaches nothing")
		eq(ns.secretChatSkipped - before, 1, "counted for /oly status")
		-- The hall's own handler, called with one, reads nothing of it either.
		eq(cns.ChatHall.OnChannel("M1~A~Olympus Dawn~7~WA~hello", secret, "", "6. OlympusNet1", "", "", 0, 6, "OlympusNet1"), false)
		eq(#injected, 0)
		eq(ns.Channels.OtherFamily(secret), nil, "no family read from a secret")
		dispatch(nil, "CHAT_MSG_CHANNEL", "M1~A~Olympus Dawn~8~WA~plain", PVE, "", "6. OlympusNet1", "", "", 0, 6, "OlympusNet1")
		eq(#injected, 1); eq(injected[1].sender, PVE)
		eq(#errors, 0, table.concat(errors, "; "))
	end)
	probing = false
	issecretvalue, ns.CaptureError = savedSecret, savedCapture
	if not ok then error(err, 0) end
end)

test("chat groups (1.5.5): the dropdown's words in every language", function()
	local function Load(code, file)
		local lns, saved = {}, GetLocale
		GetLocale = function() return code end
		local okLoad, errLoad = pcall(function()
			assert(loadfile(ADDON_DIR .. "Locales.lua"))("Olympus", lns)
			if file then assert(loadfile(ADDON_DIR .. "Locales/" .. file .. ".lua"))("Olympus", lns) end
		end)
		GetLocale = saved
		assert(okLoad, errLoad)
		return lns.L
	end
	local keys = { "CHATWIN_GROUP_ALL", "CHATWIN_GROUP_PVP", "CHATWIN_GROUP_PVE", "CHATWIN_GROUP_RP", "CHATWIN_GROUP_RPPVP",
		"CHATWIN_GROUP_TITLE", "CHATWIN_GROUP_TIP", "CHATWIN_GROUP_EMPTY" }
	local en = Load("enUS")
	for _, k in ipairs(keys) do assert(type(rawget(en, k)) == "string", "English " .. k) end
	for code, file in pairs({ ptBR = false, deDE = "deDE", esES = "esES", frFR = "frFR", itIT = "itIT", ruRU = "ruRU" }) do
		local l = Load(code, file or nil)
		for _, k in ipairs({ "CHATWIN_GROUP_ALL", "CHATWIN_GROUP_TITLE", "CHATWIN_GROUP_TIP", "CHATWIN_GROUP_EMPTY" }) do
			assert(l[k] ~= en[k], code .. " translates " .. k)
		end
		for _, k in ipairs(keys) do assert(type(l[k]) == "string" and l[k] ~= "", code .. " " .. k) end
	end
end)
