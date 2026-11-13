-- 1.5.9 (the dev in game on an RP-PvP character, 2026-11-12: "uma pessoa que tá no Regular [PvE] ...
-- mandou uma mensagem que apareceu no chat quando eu boto o RPPVP ... essa pessoa mandou do PVE e a
-- mensagem dela não apareceu no PVE. No all aparece e no RPPVP também aparece"; and "Quando eu mando
-- mensagem que eu tô tipo RPPVP ativo ... não tá mandando uma mensagem só lá"). The [Olympus] picker
-- filed a line by its sender's name, and on Forever the channel's text names him bare: ns.FullName
-- gave him the viewer's own sub-realm, so a PvE line went under RP-PvP. Each line is now filed as it
-- comes (Channels.SenderKind): by its own word (a 1.5.9 line's id names its writer's ruleset), else
-- his GUID's server id, else what Olympus knows of him, else unknown and All alone. A line written in
-- the Chat tab's box under the writer's own ruleset goes to that ruleset alone (its id); any other
-- line to everyone. A client before 1.5.9 reads every such id as the plain line it always was.
-- Invented names throughout. Loaded by tests/run.lua.
local ns, test, eq, extra = ...
local WithWindow, ADDON_DIR, FreshComm, ROOT, KeepSendGap = extra.WithWindow, extra.ADDON_DIR, extra.FreshComm, extra.ROOT, extra.KeepSendGap
local L = ns.L
local C = ns.Channels

local REALM = "CAMWOWUS2Realm1RPPvP"      -- the dev's ruleset that night
local ME = "Rose Thornwood-" .. REALM
local GUILD = "Olympus Thorns"
local OUR_SID, MATE_SID = "5100", "5101"  -- our sub-realm's server id (our GUID), a guildmate's other sub-realm
local PVE_GUILDS = { "Olympus Dawn", "Olympus Dusk", "Olympus Noon" } -- guilds the PvE family's census lists
local PVP_GUILD = "Olympus Iron"          -- a guild the PvP family's census lists
local OUR_OTHER = "Olympus Elsewhere"     -- another guild of our family, in our own census

local function Guid(sid, n) return ("Player-%s-%08X"):format(sid, n) end
-- A line as a client before 1.5.9 writes it: a plain id.
local function Line(guild, id, text, tier) return ns.Codec.EncodeChat(tier or "A", guild, id, "WA", text) end
-- A line as a 1.5.9 client of ruleset `kind` writes it, by hand as it goes on the wire: for everyone,
-- its id "0" .. 5-9 .. two digits (its writer's ruleset); with `to`, for that ruleset alone, "0" ..
-- 1-4 .. two digits (1.5.9 writes one only for its writer's own).
local FROM_DIGIT = { pvp = 5, pve = 6, rp = 7, rppvp = 8, hardcore = 9 }
local TO_DIGIT = { pvp = 1, pve = 2, rp = 3, rppvp = 4 }
local function Said(guild, n, text, kind, to)
	return ("M1~A~%s~0%d%02d~WA~%s"):format(guild, to and TO_DIGIT[kind] or FROM_DIGIT[kind], n % 100, text)
end
local function Tag(kind) return "[" .. L["CHATWIN_GROUP_" .. kind] .. "]" end
local KINDS = { "PVP", "PVE", "RP", "RPPVP" }
local function Untagged(text)
	for _, k in ipairs(KINDS) do
		if tostring(text):find(Tag(k), 1, true) then return false end
	end
	return not tostring(text):find(Tag("HARDCORE"), 1, true)
end
-- The kept [Olympus] line with these words, or nil.
local function Kept(text)
	for _, e in ipairs(ns.rdb.chat and ns.rdb.chat.A or {}) do if e.text == text then return e end end
	return nil
end
-- The ruleset whose [Olympus] shows a kept line (nil: All alone).
local function Room(text) return (C.LineRoom(assert(Kept(text), text))) end
-- The printed lines with these words.
local function PrintedWith(printed, text)
	local n = 0
	for _, line in ipairs(printed) do if line:find(text, 1, true) then n = n + 1 end end
	return n
end
-- /oly bug's line on the rulesets.
local function BugLine() return ns.StatusText():match("\nchat rulesets: [^\n]*") or "" end
local function BugHas(text) local bug = BugLine(); assert(bug:find(text, 1, true), "/oly bug: " .. text .. " in: " .. bug) end
-- (Asked for, not assumed: the first tests below also run against 1.5.8's Channels.lua, which has no
-- ResetRulesets, and fail there on the bug itself, the PvE line printed under RP-PvP.)
local function Reset() if C.ResetRulesets then C.ResetRulesets() end end

-- An RP-PvP character of Forever, master of GUILD: its roster (each row with the GUID the game gives,
-- its 17th value), its own GUID, the PvE family's census rows (the group details an author's capsule
-- leaves) unless `noCensus`, another guild of our family in our own census; [Olympus] on, nothing muted,
-- the game's chat in `printed`. fn(printed, errors, rows): errors caught by the addon
-- (ns.CaptureError), and the roster's rows (a test adds one and scans again). All put back after.
local function AsRpPvpMaster(fn, noCensus)
	local saved = { realm = ns.realm, group = ns.group, split = ns.splitNames, me = ns.me, faction = ns.faction,
		groups = ns.db.chatGroups, chat = ns.db.addonChat, mute = ns.db.chatMute, windows = ns.db.chatWindows,
		details = ns.db.groupDetails, history = ns.rdb.chat, guilds = ns.rdb.guilds, hall = ns.ChatHall,
		total = GetNumGuildMembers, info = GetGuildRosterInfo, guild = GetGuildInfo, member = ns.IsMember,
		guid = rawget(_G, "UnitGUID"), frame = DEFAULT_CHAT_FRAME, capture = ns.CaptureError }
	local errors = {}
	local ok, err = pcall(function()
		ns.splitNames, ns.realm, ns.group, ns.me, ns.faction = true, REALM, "ForeverRPPvP", ME, "Alliance"
		ns.IsMember = function() return true end
		GetGuildInfo = function() return GUILD, "Master", 0 end
		local rows = {
			{ "Rose Thornwood", "Master", 0, Guid(OUR_SID, 1) },
			{ "Thorn Rulemate", "Member", 3, Guid(MATE_SID, 2) },
		}
		GetNumGuildMembers = function() return #rows, #rows end
		GetGuildRosterInfo = function(i)
			local r = rows[i]
			if r then return r[1], r[2], r[3], 60, "Warrior", "Stormwind City", "", "", true, 0, "WARRIOR", 0, 0, false, false, 0, r[4] end
		end
		UnitGUID = function(unit) if unit == "player" then return Guid(OUR_SID, 1) end end
		ns.Roster.Scan()
		ns.db.addonChat, ns.db.chatMute, ns.db.chatWindows, ns.db.chatGroups = true, {}, nil, nil
		local now = ns.Now()
		ns.rdb.chat = {}
		ns.rdb.guilds = { [OUR_OTHER] = { guild = OUR_OTHER, total = 30, online = 5, zones = {}, t = now } }
		local pve = {}
		for _, name in ipairs(PVE_GUILDS) do pve[name:lower()] = { name = name, total = 40, online = 9, avg10 = 500, observed = now } end
		ns.db.groupDetails = noCensus and {} or { ["Alliance|ForeverPvE"] = { group = "ForeverPvE", faction = "Alliance", observed = now, rows = pve, source = "author" } }
		Reset()
		local printed = {}
		DEFAULT_CHAT_FRAME = { AddMessage = function(_, line) printed[#printed + 1] = line end }
		ns.CaptureError = function(where, e) errors[#errors + 1] = tostring(where) .. ": " .. tostring(e) end
		fn(printed, errors, rows)
	end)
	ns.realm, ns.group, ns.splitNames, ns.me, ns.faction = saved.realm, saved.group, saved.split, saved.me, saved.faction
	ns.db.chatGroups, ns.db.addonChat, ns.db.chatMute, ns.db.chatWindows = saved.groups, saved.chat, saved.mute, saved.windows
	ns.db.groupDetails, ns.rdb.chat, ns.rdb.guilds, ns.ChatHall = saved.details, saved.history, saved.guilds, saved.hall
	GetNumGuildMembers, GetGuildRosterInfo, GetGuildInfo, ns.IsMember = saved.total, saved.info, saved.guild, saved.member
	UnitGUID, DEFAULT_CHAT_FRAME, ns.CaptureError = saved.guid, saved.frame, saved.capture
	C_ChatInfo = nil -- (FreshComm's)
	Reset()
	ns.Roster.Scan() -- (the harness's own roster for the tests after this one)
	if not ok then error(err, 0) end
end

-- The channel's text as Forever's client hands it to Olympus (CHAT_MSG_CHANNEL: the line, its sender
-- as "First-Surname", the channel's base name ninth, the sender's GUID twelfth) through the real
-- ChatHall.lua and Comm.lua (a client of their own, FreshComm) to Channels.Receive, as Channels.lua's
-- M1 handler hands it on. Hear(sender, guid, msg) returns what ChatHall.OnChannel returned.
local function HallWorld()
	local cns = FreshComm()
	cns.Comm.ChannelName = function() return "OlympusNet1" end
	cns.Comm.ChannelIndex = function() return 6 end
	cns.Comm.Handle("M1", function(dist, sender, text) C.Receive(dist, sender, text) end)
	assert(loadfile(ADDON_DIR .. "ChatHall.lua"))("Olympus", cns)
	ns.ChatHall = cns.ChatHall
	local lineID = 0
	return function(sender, guid, msg)
		lineID = lineID + 1
		return cns.ChatHall.OnChannel(msg, sender, "", "6. OlympusNet1", "", "", 0, 6, "OlympusNet1", 0, lineID, guid)
	end
end

-- The Chat tab's bubbles shown, by their line's words, and the picker's rows (WithWindow's window).
local function Bubbles(f)
	local out = {}
	for _, b in ipairs(f.bubbles) do
		if b:IsShown() and b.entry then out[b.entry.text] = b end
	end
	return out
end
local function Pick(f, label)
	assert(f.groups:IsShown(), "the rulesets' dropdown")
	f.groups:Click()
	for _, r in ipairs(f.subMenu.rows) do
		if r:IsShown() and r.text:GetText() == label then return r:Click() end
	end
	error("no row " .. tostring(label))
end
local function Words(f)
	local out = {}
	for text in pairs(Bubbles(f)) do out[#out + 1] = text end
	table.sort(out)
	return table.concat(out, " / ")
end

test("chat rulesets (1.5.9): on an RP-PvP character a PvE player's [Olympus] line from the channel's text, his name bare, goes under PvE and All (tagged), never under RP-PvP; a guildmate's and our sub-realm's under RP-PvP by their GUID's server; one nobody knows in All alone; /oly bug counts each", function()
	AsRpPvpMaster(function(printed, errors)
		local Hear = HallWorld()
		-- The dev's picker on RP-PvP, as that night.
		eq(C.SetGroupView("rppvp"), true)
		-- A PvE player of a guild the PvE census lists, on a server nobody named yet (a client before 1.5.9).
		eq(Hear("Dawn-Rulespeaker", Guid("4401", 1), Line(PVE_GUILDS[1], 11, "hello from the PvE realms")), true)
		-- A guildmate, on another sub-realm of ours (his roster row's GUID).
		Hear("Thorn-Rulemate", Guid(MATE_SID, 2), Line(GUILD, 12, "a guildmate speaks"))
		-- Someone of another guild of ours, on our own sub-realm's server.
		Hear("Rule-Neighbour", Guid(OUR_SID, 3), Line(OUR_OTHER, 13, "a neighbour of our family"))
		-- Someone nobody knows: a guild in no census, a server nobody named.
		Hear("Lone-Rulestranger", Guid("4999", 4), Line("Olympus Nowhere", 14, "who am I"))
		eq(#errors, 0, table.concat(errors, " | "))
		for _, text in ipairs({ "hello from the PvE realms", "a guildmate speaks", "a neighbour of our family", "who am I" }) do
			assert(Kept(text), "kept for the Chat tab: " .. text)
		end
		eq(Kept("hello from the PvE realms").sender, "Dawn Rulespeaker-" .. REALM, "(his name came bare: ns.FullName gave him our sub-realm)")
		-- The game's chat under RP-PvP: our ruleset's lines alone, the PvE line and the unknown one kept unprinted.
		eq(PrintedWith(printed, "hello from the PvE realms"), 0, "the PvE line is not RP-PvP's")
		eq(PrintedWith(printed, "who am I"), 0, "a line of no known ruleset is no ruleset's")
		eq(PrintedWith(printed, "a guildmate speaks"), 1)
		eq(PrintedWith(printed, "a neighbour of our family"), 1)
		BugHas("filed said=0 guid=2 known=1 unknown=1 to=0 conflict=0")
		BugHas("channel text 4, with GUID 4")
		BugHas("here=rppvp server " .. OUR_SID .. " view=rppvp box to rppvp")
		local kept = ns.rdb.chat
		-- The Chat tab: each ruleset's lines under it, every one under All, the PvE line tagged there.
		WithWindow(function(w)
			ns.me, ns.rdb.chat = ME, kept
			GetGuildInfo = function() return GUILD, "Master", 0 end
			local f = w.CW.Open("A")
			eq(Words(f), "a guildmate speaks / a neighbour of our family", "RP-PvP: its own lines")
			Pick(f, L.CHATWIN_GROUP_PVE)
			eq(Words(f), "hello from the PvE realms", "PvE: the PvE line alone")
			assert(Untagged(Bubbles(f)["hello from the PvE realms"].who:GetText()), "one ruleset shown: no tag")
			Pick(f, L.CHATWIN_GROUP_PVP)
			eq(Words(f), "", "PvP: none")
			Pick(f, L.CHATWIN_GROUP_ALL)
			eq(Words(f), "a guildmate speaks / a neighbour of our family / hello from the PvE realms / who am I", "All: every line")
			local b = Bubbles(f)
			local who = b["hello from the PvE realms"].who:GetText()
			local at, name = who:find(Tag("PVE"), 1, true), who:find("Dawn Rulespeaker", 1, true)
			assert(at and name and at < name, "[PvE] before his name: " .. tostring(who))
			for _, text in ipairs({ "a guildmate speaks", "a neighbour of our family", "who am I" }) do
				assert(Untagged(b[text].who:GetText()), "no tag: " .. text)
			end
		end)
	end)
end)

-- The review of 1.5.9's first build: a line of another family could be filed by its server id or the
-- census alone, and another family's census comes only with the author's capsules (kept 7 days): most
-- players never saw a PvE line under PvE. A 1.5.9 line names its writer's ruleset.
test("chat rulesets (1.5.9): a 1.5.9 line names its writer's ruleset: with no census of another family, a PvE player's line goes under PvE and All (tagged), never under RP-PvP; a PvP one under PvP, a Hardcore one in All tagged; a line before 1.5.9 nobody can place stays in All alone", function()
	AsRpPvpMaster(function(printed, errors)
		local Hear = HallWorld()
		eq(C.SetGroupView("rppvp"), true)
		Hear("Dawn-Rulespeaker", Guid("4401", 1), Said(PVE_GUILDS[1], 11, "a PvE player of 1.5.9", "pve"))
		Hear("Iron-Rulefighter", Guid("4402", 2), Said(PVP_GUILD, 12, "a PvP player of 1.5.9", "pvp"))
		Hear("Last-Rulebreath", Guid("4403", 3), Said("Olympus Ember", 13, "a Hardcore player of 1.5.9", "hardcore"))
		Hear("Rule-Neighbour", Guid("4404", 4), Said(OUR_OTHER, 14, "one of ours on 1.5.9", "rppvp"))
		Hear("Dusk-Ruleolder", Guid("4405", 5), Line(PVE_GUILDS[2], 15, "a PvE player before 1.5.9"))
		eq(#errors, 0, table.concat(errors, " | "))
		eq(Room("a PvE player of 1.5.9"), "pve"); eq(Room("a PvP player of 1.5.9"), "pvp")
		eq(Room("a Hardcore player of 1.5.9"), "hardcore", "(no picker row: All alone, tagged)")
		eq(Room("one of ours on 1.5.9"), "rppvp")
		eq(Room("a PvE player before 1.5.9"), nil, "no census of the PvE family here: unknown, All alone")
		eq(Kept("a PvE player of 1.5.9").kind, "pve", "kept so")
		eq(PrintedWith(printed, "a PvE player of 1.5.9"), 0, "not under RP-PvP")
		eq(PrintedWith(printed, "one of ours on 1.5.9"), 1)
		BugHas("filed said=4 guid=0 known=0 unknown=1 to=0 conflict=0")
		local kept = ns.rdb.chat
		WithWindow(function(w)
			ns.me, ns.rdb.chat = ME, kept
			GetGuildInfo = function() return GUILD, "Master", 0 end
			local f = w.CW.Open("A")
			eq(Words(f), "one of ours on 1.5.9")
			Pick(f, L.CHATWIN_GROUP_PVE)
			eq(Words(f), "a PvE player of 1.5.9", "PvE: the PvE player's line, the dev's ask")
			Pick(f, L.CHATWIN_GROUP_PVP)
			eq(Words(f), "a PvP player of 1.5.9")
			Pick(f, L.CHATWIN_GROUP_ALL)
			local b = Bubbles(f)
			eq(Words(f), "a Hardcore player of 1.5.9 / a PvE player before 1.5.9 / a PvE player of 1.5.9 / a PvP player of 1.5.9 / one of ours on 1.5.9")
			assert(b["a PvE player of 1.5.9"].who:GetText():find(Tag("PVE"), 1, true), b["a PvE player of 1.5.9"].who:GetText())
			assert(b["a PvP player of 1.5.9"].who:GetText():find(Tag("PVP"), 1, true))
			assert(b["a Hardcore player of 1.5.9"].who:GetText():find(Tag("HARDCORE"), 1, true))
			assert(Untagged(b["one of ours on 1.5.9"].who:GetText()))
			assert(Untagged(b["a PvE player before 1.5.9"].who:GetText()), "unknown: no tag")
		end)
	end, true)
end)

-- The review of 1.5.9's first build (P1): the guild a line names is its writer's own word, and two
-- characters naming two guilds of the PvE census from one server taught every 1.5.9 client that server
-- as PvE's; a PvP player's line from it went under PvE from then on, kept so, and /oly bug said nothing.
test("chat rulesets (1.5.9): the census files a line alone, never its server: two characters naming PvE guilds from a PvP server teach nothing, and a PvP guild's line from it goes under PvP; a server is learned from two 1.5.9 writers' own word, one writer twice is not enough, two rulesets there and it names none", function()
	AsRpPvpMaster(function(_, errors)
		local now = ns.Now()
		ns.db.groupDetails["Alliance|ForeverPvP"] = { group = "ForeverPvP", faction = "Alliance", observed = now,
			rows = { [PVP_GUILD:lower()] = { name = PVP_GUILD, total = 40, online = 9, avg10 = 500, observed = now } }, source = "author" }
		local Hear = HallWorld()
		-- Server 4500 is a PvP one. Two characters there name two guilds of the PvE census (their word).
		Hear("Fake-Onealt", Guid("4500", 1), Line(PVE_GUILDS[1], 21, "first claim"))
		Hear("Fake-Twoalt", Guid("4500", 2), Line(PVE_GUILDS[2], 22, "second claim"))
		eq(Room("first claim"), "pve", "each line by its census, that line alone"); eq(Room("second claim"), "pve")
		Hear("Real-Pvper", Guid("4500", 3), Line(PVP_GUILD, 23, "a real PvP line"))
		eq(Room("a real PvP line"), "pvp", "by its own census, not by a server the claims taught")
		Hear("Real-Pvpother", Guid("4500", 4), Line("Olympus Unlisted", 24, "a guild in no census"))
		eq(Room("a guild in no census"), nil, "the server named no ruleset: unknown")
		BugHas("filed said=0 guid=0 known=3 unknown=1 to=0 conflict=0")
		BugHas("ids rppvp=2, mixed 0")
		-- Server 4600: a 1.5.9 PvE writer's word, twice: one writer is not enough.
		Hear("Sun-Ruleone", Guid("4600", 1), Said(PVE_GUILDS[1], 31, "one writer's word", "pve"))
		Hear("Sun-Ruleone", Guid("4600", 1), Said(PVE_GUILDS[1], 32, "the same writer again", "pve"))
		Hear("Old-Rulepve", Guid("4600", 3), Line("Olympus Unlisted", 33, "before 1.5.9 from 4600"))
		eq(Room("before 1.5.9 from 4600"), nil, "not learned yet: unknown, kept with its server")
		-- A second writer's word: learned. The line kept unknown is PvE's now, and so is the next one.
		Hear("Sun-Ruletwo", Guid("4600", 2), Said(PVE_GUILDS[2], 34, "a second writer's word", "pve"))
		eq(Room("before 1.5.9 from 4600"), "pve", "filed once its server was learned")
		Hear("Old-Rulepve", Guid("4600", 3), Line("Olympus Unlisted", 35, "after, by its server"))
		eq(Room("after, by its server"), "pve")
		BugHas("ids pve=1 rppvp=2, mixed 0")
		-- Server 4700: one writer says PvE, another PvP: it names no ruleset.
		Hear("Two-Ruleone", Guid("4700", 1), Said(PVE_GUILDS[3], 41, "says PvE", "pve"))
		Hear("Two-Ruletwo", Guid("4700", 2), Said(PVP_GUILD, 42, "says PvP", "pvp"))
		Hear("Two-Rulethree", Guid("4700", 3), Said(PVP_GUILD, 43, "says PvP too", "pvp"))
		Hear("Two-Ruleold", Guid("4700", 4), Line("Olympus Unlisted", 44, "before 1.5.9 from 4700"))
		eq(Room("before 1.5.9 from 4700"), nil, "a server named for two rulesets files nothing")
		eq(Room("says PvP too"), "pvp", "(each 1.5.9 line by its own word)")
		BugHas("ids pve=1 rppvp=2, mixed 1")
		eq(#errors, 0, table.concat(errors, " | "))
	end)
end)

-- The review of 1.5.9's first build (P1, and its probe of shared ids): nothing has shown that Forever's
-- sub-realms of two rulesets have server ids of their own. If PvE's and RP-PvP's shared ours, every PvE
-- line came "by guid" under RP-PvP while /oly bug read as all well.
test("chat rulesets (1.5.9): a known server contradicted: a line whose census or own word names another ruleset goes by it and is counted a conflict; after two writers the server names no ruleset (mixed), and a line filed by it alone goes back to All alone", function()
	AsRpPvpMaster(function(printed, errors)
		local Hear = HallWorld()
		eq(C.SetGroupView("rppvp"), true)
		-- From our own server (our GUID's): a guild in no census, filed by the server alone.
		Hear("Plain-Rulefolk", Guid(OUR_SID, 5), Line("Olympus Unlisted", 51, "by our server alone"))
		eq(Room("by our server alone"), "rppvp")
		-- A PvE census guild's line from our server: its census says PvE.
		Hear("Dawn-Rulespeaker", Guid(OUR_SID, 6), Line(PVE_GUILDS[1], 52, "a PvE guild from our server"))
		eq(Room("a PvE guild from our server"), "pve", "by its census")
		eq(PrintedWith(printed, "a PvE guild from our server"), 0, "not under RP-PvP")
		BugHas("conflict=1"); BugHas("mixed 0")
		-- Another writer's own word, PvE, from our server: the second conflict.
		Hear("Dusk-Ruletalker", Guid(OUR_SID, 7), Said(PVE_GUILDS[2], 53, "a 1.5.9 PvE line from our server", "pve"))
		eq(Room("a 1.5.9 PvE line from our server"), "pve")
		BugHas("conflict=2"); BugHas("ids rppvp=1, mixed 1")
		eq(Room("by our server alone"), nil, "filed by that server alone: unknown now")
		Hear("Plain-Rulefolk", Guid(OUR_SID, 5), Line("Olympus Unlisted", 54, "after, from our server"))
		eq(Room("after, from our server"), nil)
		-- A guildmate's line still goes under ours: the roster says so, whatever the server.
		Hear("Thorn-Rulemate", Guid(OUR_SID, 2), Line(GUILD, 55, "a guildmate from our server"))
		eq(Room("a guildmate from our server"), "rppvp")
		eq(#errors, 0, table.concat(errors, " | "))
	end)
end)

test("chat rulesets (1.5.9): a line by the relay is filed by its stamp (a client of its writer's family); our family's guildmate by the roster; a census name of two families says nothing", function()
	AsRpPvpMaster(function()
		-- The relay's copy (no channel's text): its origin stamped by a relay client of his family.
		eq((C.Receive("CHANNEL", "Relay Rulespeaker-CAMWOWUS2Realm5RPPvP", Line(OUR_OTHER, 41, "by the relay"))), true)
		eq(Room("by the relay"), "rppvp")
		-- A PvE guild's name that our own census lists too: no family is told by it.
		ns.rdb.guilds[PVE_GUILDS[1]] = { guild = PVE_GUILDS[1], total = 12, online = 2, zones = {}, t = ns.Now() }
		local Hear = HallWorld()
		Hear("Twin-Rulename", Guid("4404", 1), Line(PVE_GUILDS[1], 42, "a name in two families"))
		eq(Room("a name in two families"), nil, "unknown: All alone")
		-- Our census alone lists it: ours.
		Hear("Other-Ruleguild", Guid("4405", 1), Line(OUR_OTHER, 43, "our census"))
		eq(Room("our census"), "rppvp")
		BugHas("filed said=0 guid=0 known=2 unknown=1 to=0 conflict=0")
	end)
end)

-- A world for the lines this character writes: each line as it leaves for the chat lane (`sent`), the
-- 1.5.8 codec (`old`), and Field(msg, text): the id of [Olympus] line `msg` with these words. fn(sent,
-- old, Field) runs as AsRpPvpMaster's character with Channels' send gap fresh (KeepSendGap).
local function Writing(fn)
	AsRpPvpMaster(function()
		local Comm = ns.Comm
		local savedReady, savedSend = Comm.ChannelReady, Comm.SendChat
		local sent = {}
		Comm.ChannelReady = function() return true end
		Comm.SendChat = function(msg, done) sent[#sent + 1] = msg; done(true); return true end
		local old = {}
		assert(loadfile(ROOT .. "tests/fixtures/codec-1.5.8.lua"))("Olympus", old)
		local function Field(msg, text) return tostring(msg):match("^M1~A~" .. GUILD .. "~(%d+)~PA~" .. text:gsub("%p", "%%%0") .. "$") end
		local ok, err = pcall(KeepSendGap, function() fn(sent, old, Field) end)
		Comm.ChannelReady, Comm.SendChat = savedReady, savedSend
		if not ok then error(err, 0) end
	end)
end

-- The review of 1.5.9's first build: a line written under another family's ruleset went for that
-- ruleset alone and reached none of its players with the gamepad UI (the hidden way keeps to its own
-- family; only the channel's text crosses families), while our own family's clients hid it.
test("chat rulesets (1.5.9): in the Chat tab's box under the character's own ruleset a line goes to it alone; under another ruleset or All to everyone, naming its writer's ruleset; the box says which; a 1.5.8 client reads the same line and id", function()
	Writing(function(sent, old, Field)
		local kept = ns.rdb.chat
		WithWindow(function(w)
			ns.me, ns.rdb.chat = ME, kept
			GetGuildInfo = function() return GUILD, "Master", 0 end
			local clock = 5000
			GetTime = function() return clock end
			local f = w.CW.Open("A")
			local function Write(text)
				clock = clock + 2
				local before = #sent
				f.input:SetText(text); f.input:Fire("OnEnterPressed")
				eq(#sent, before + 1, "one line sent: " .. text .. " " .. table.concat(w.printed, " | "))
				return sent[#sent]
			end
			local hint = function() return f.input.hint:GetText() end
			-- Under another ruleset (PvE): for everyone.
			Pick(f, L.CHATWIN_GROUP_PVE)
			eq(ns.Codec.DecodeChat(Write("written under PvE")).to, nil, "under PvE: not for PvE alone")
			eq(C.SendTo(), nil)
			eq(hint(), L.CHATWIN_PLACEHOLDER_EVERY .. L.CHATWIN_PUBLIC, "the box says it goes to every ruleset")
			local field = Field(sent[#sent], "written under PvE")
			assert(field and field:match("^08%d%d$"), "for everyone, by an RP-PvP player: " .. tostring(sent[#sent]))
			eq(ns.Codec.DecodeChat(sent[#sent]).from, "rppvp")
			eq(Kept("written under PvE").to, nil); eq(Kept("written under PvE").kind, "rppvp", "our echo: ours")
			-- A client before 1.5.9 (1.5.8's Codec): the same line, the same id, no ruleset.
			local o, m = old.Codec.DecodeChat(sent[#sent]), ns.Codec.DecodeChat(sent[#sent])
			eq(o.tier, "A"); eq(o.guild, GUILD); eq(o.id, m.id); eq(o.id, tonumber(field)); eq(o.class, "PA"); eq(o.text, "written under PvE")
			-- Under our own ruleset: for it alone, and the box says so.
			Pick(f, L.CHATWIN_GROUP_RPPVP)
			eq(C.SendTo(), "rppvp")
			eq(hint(), L.CHATWIN_PLACEHOLDER_TO:format(L.CHATWIN_GROUP_RPPVP) .. L.CHATWIN_PUBLIC, "the box says where it goes")
			field = Field(Write("only for RP-PvP"), "only for RP-PvP")
			assert(field and field:match("^04%d%d$"), "a line for RP-PvP alone: " .. tostring(sent[#sent]))
			eq(ns.Codec.DecodeChat(sent[#sent]).to, "rppvp")
			o, m = old.Codec.DecodeChat(sent[#sent]), ns.Codec.DecodeChat(sent[#sent])
			eq(o.id, m.id); eq(o.text, "only for RP-PvP"); eq(o.to, nil)
			local e = Kept("only for RP-PvP")
			eq(e.mine, true); eq(e.to, "rppvp"); eq(e.id, m.id)
			BugHas("view=rppvp box to rppvp")
			-- Under All: for everyone, the box as before.
			Pick(f, L.CHATWIN_GROUP_ALL)
			eq(hint(), L.CHATWIN_PLACEHOLDER:format(L.CHAN_ALL) .. L.CHATWIN_PUBLIC, "under All, the box as before")
			field = Field(Write("for everyone"), "for everyone")
			assert(field and field:match("^08%d%d$"), "an RP-PvP player's line for everyone: " .. tostring(sent[#sent]))
			eq(Kept("for everyone").to, nil)
			-- Our own lines show under every ruleset.
			Pick(f, L.CHATWIN_GROUP_PVE)
			f:Fire("OnUpdate", 0.3) -- (the tab's next redraw)
			for _, text in ipairs({ "for everyone", "only for RP-PvP", "written under PvE" }) do
				assert(Bubbles(f)[text], "ours, under PvE: " .. text .. " in " .. Words(f))
			end
		end)
	end)
end)

-- The review of 1.5.9's first build: the picker, kept per character since 1.5.5, also sent /ol typed in
-- the game's chat to its ruleset alone, and nothing in the game's chat said so.
test("chat rulesets (1.5.9): /ol typed in the game's chat goes to everyone whatever the picker shows; a line is never for another ruleset than its writer's, whoever asks; [Captains] has none", function()
	Writing(function(sent, _, Field)
		eq(C.SetGroupView("rppvp"), true)
		eq(C.SendTo(), "rppvp", "(the Chat tab's box would write to RP-PvP alone)")
		SlashCmdList.OLYMPUSALL("typed in the game's chat box")
		eq(ns.Codec.DecodeChat(assert(sent[#sent], "sent")).to, nil, "/ol: for everyone")
		local field = Field(sent[#sent], "typed in the game's chat box")
		assert(field and field:match("^08%d%d$"), "naming its writer's ruleset: " .. tostring(sent[#sent]))
		eq(Kept("typed in the game's chat box").to, nil)
		-- A line for another ruleset is never sent, whoever asks: everyone, naming ours.
		eq((C.Send("A", "asked for PvE", 6000, nil, "pve")), true)
		field = Field(sent[#sent], "asked for PvE")
		assert(field and field:match("^08%d%d$"), sent[#sent])
		-- [Captains] has no rulesets.
		eq((C.Send("C", "captains, all of us", 6002, nil, "rppvp")), true)
		local cm = ns.Codec.DecodeChat(sent[#sent])
		eq(cm.to, nil); eq(cm.from, nil); assert(not sent[#sent]:find("^M1~C~[^~]+~0%d%d%d~"), sent[#sent])
	end)
end)

-- The review of 1.5.9's first build: under All, a PvE player's line sent to RP-PvP showed with no
-- [PvE] before his name, against the picker's tooltip (All labels other rulesets' lines).
test("chat rulesets (1.5.9): a line for one ruleset shows under it, not under another nor in another ruleset's All; under All a line's tag is its writer's ruleset, whomever it was sent to; a [Captains] id with a leading zero is a plain one", function()
	AsRpPvpMaster(function(printed, errors)
		local Hear = HallWorld()
		local function Visible(view, text)
			C.SetGroupView(view)
			return C.GroupVisible("A", assert(Kept(text), text), false)
		end
		eq(C.SetGroupView("all"), true)
		-- A line kept by 1.5.9's first build: a PvE player's, sent to RP-PvP. In our All: tagged [PvE].
		local first = { t = 1000, sender = "Noon Ruleguest-" .. REALM, guild = PVE_GUILDS[3], text = "a PvE player to RP-PvP",
			kind = "pve", to = "rppvp" }
		eq(C.GroupVisible("A", first, false), true, "sent to our ruleset: in our All")
		eq(C.GroupTag("A", first), Tag("PVE") .. " ", "tagged by its writer's ruleset")
		-- A neighbour of ours writes for RP-PvP; a PvE player for PvE (its channel's text reaches us too).
		Hear("Rule-Neighbour", Guid(OUR_SID, 3), Said(OUR_OTHER, 51, "for RP-PvP eyes", "rppvp", true))
		Hear("Dawn-Rulespeaker", Guid("4401", 1), Said(PVE_GUILDS[1], 52, "for PvE eyes", "pve", true))
		eq(PrintedWith(printed, "for PvE eyes"), 0, "not in our All: it was sent to PvE")
		eq(PrintedWith(printed, "for RP-PvP eyes"), 1, "sent to our ruleset: in our All")
		assert(Untagged(printed[#printed]), "our ruleset's line: no tag: " .. printed[#printed])
		eq(Kept("for PvE eyes").to, "pve"); eq(Kept("for RP-PvP eyes").to, "rppvp")
		eq(Kept("for PvE eyes").kind, "pve", "(1.5.9 writes for its writer's own ruleset alone)")
		eq(Visible("pve", "for PvE eyes"), true); eq(Visible("rppvp", "for PvE eyes"), false); eq(Visible("all", "for PvE eyes"), false)
		eq(Visible("rppvp", "for RP-PvP eyes"), true); eq(Visible("pve", "for RP-PvP eyes"), false); eq(Visible("all", "for RP-PvP eyes"), true)
		C.SetGroupView("all")
		eq(C.GroupTag("A", Kept("for RP-PvP eyes")), "", "no tag in our All")
		BugHas("filed said=2 guid=0 known=0 unknown=0 to=2 conflict=0")
		-- [Captains]: no rulesets, whatever its id (an officer of ours).
		local captains = "M1~C~" .. GUILD .. "~0212~WA~captains, gather"
		eq(ns.Codec.DecodeChat(captains).to, nil); eq(ns.Codec.DecodeChat(captains).from, nil)
		eq(ns.Codec.DecodeChat(captains).id, 212)
		eq(#errors, 0, table.concat(errors, " | "))
	end)
end)

test("chat rulesets (1.5.9): a line kept before 1.5.9 (no ruleset kept with it) goes under another family's ruleset by its stamp, under ours if a guildmate wrote it, and in All alone if its stamp is ours (a bare name took it)", function()
	AsRpPvpMaster(function()
		local function Old(sender, text, mine) return { t = 1000, sender = sender, guild = GUILD, text = text, mine = mine } end
		local list = {
			Old("Pve Rulespeaker-CAMWOWUS1Realm2PvE", "another family's stamp"),
			Old("Thorn Rulemate-" .. REALM, "a guildmate"),
			Old("Pve Rulebare-" .. REALM, "a bare name, our stamp"),
			Old("Rp Rulecousin-CAMWOWUS1Realm5RPPvP", "our family, another sub-realm"),
			Old(ME, "our own words", true),
		}
		local function Shown(view)
			C.SetGroupView(view)
			local out = {}
			for _, e in ipairs(C.GroupFilter("A", list, function(e) return e.mine == true and C.IsMe(e.sender) end)) do out[#out + 1] = e.text end
			return table.concat(out, " / ")
		end
		eq(Shown("pve"), "another family's stamp / our own words")
		eq(Shown("rppvp"), "a guildmate / our own words")
		eq(Shown("all"), "another family's stamp / a guildmate / a bare name, our stamp / our family, another sub-realm / our own words")
		eq(C.GroupTag("A", list[1]), Tag("PVE") .. " "); eq(C.GroupTag("A", list[3]), "")
		-- Under All nothing is made: the list itself.
		eq(C.GroupFilter("A", list, nil), list)
		-- A saved file may hold anything: a ruleset of ours, or none (no tag made of it).
		local odd = { t = 1000, sender = "Pve Rulespeaker-CAMWOWUS1Realm2PvE", guild = GUILD, text = "odd", kind = "|TInterface\\x:16|t", to = "everyone", sid = {} }
		eq(C.LineRoom(odd), nil, "an odd kind is no ruleset: unknown, All alone")
		eq(C.GroupTag("A", odd), "", "and no tag made of it")
		odd.kind = false
		eq(C.LineRoom(odd), nil, "unknown, its odd server id read as none")
	end)
end)

test("chat rulesets (1.5.9): a line's ruleset in its id: four digits with a leading zero, 1-4 for one ruleset alone, 5-9 its writer's, then two of its id; read back as that number; never on [Captains] or [Lords]; another leading-zero id is a plain one", function()
	local Codec = ns.Codec
	for kind, digit in pairs(TO_DIGIT) do
		local msg = Codec.EncodeChat("A", GUILD, 9876, "WA", "hi", kind)
		eq(msg, ("M1~A~%s~0%d76~WA~hi"):format(GUILD, digit))
		local m = Codec.DecodeChat(msg)
		eq(m.to, kind); eq(m.from, nil); eq(m.id, digit * 100 + 76); eq(m.id, Codec.ChatWireId(9876, "A", kind))
	end
	for kind, digit in pairs(FROM_DIGIT) do
		local msg = Codec.EncodeChat("A", GUILD, 9876, "WA", "hi", nil, kind)
		eq(msg, ("M1~A~%s~0%d76~WA~hi"):format(GUILD, digit))
		local m = Codec.DecodeChat(msg)
		eq(m.from, kind); eq(m.to, nil); eq(m.id, digit * 100 + 76); eq(m.id, Codec.ChatWireId(9876, "A", nil, kind))
	end
	eq(Codec.EncodeChat("A", GUILD, 9876, "WA", "hi", "pve", "rppvp"), "M1~A~" .. GUILD .. "~0276~WA~hi", "for one ruleset: that one's digit")
	eq(Codec.EncodeChat("A", GUILD, 9876, "WA", "hi"), "M1~A~" .. GUILD .. "~9876~WA~hi", "neither: as before")
	eq(Codec.ChatWireId(9876, "A", nil), 9876)
	eq(Codec.EncodeChat("A", GUILD, 7, "", "hi", "pve"), "M1~A~" .. GUILD .. "~0207~~hi")
	for _, tier in ipairs({ "C", "L" }) do
		eq(Codec.EncodeChat(tier, GUILD, 9876, "WA", "hi", "pve", "pve"), ("M1~%s~%s~9876~WA~hi"):format(tier, GUILD), tier .. ": no ruleset")
		eq(Codec.ChatWireId(9876, tier, "pve", "pve"), 9876)
	end
	eq(Codec.EncodeChat("A", GUILD, 5, "", "hi", "all", "all"), "M1~A~" .. GUILD .. "~5~~hi", "All is no ruleset")
	for _, field in ipairs({ "0012", "0099", "012", "02", "0" }) do
		local m = Codec.DecodeChat("M1~A~" .. GUILD .. "~" .. field .. "~~hi")
		eq(m.to, nil, field); eq(m.from, nil, field); eq(m.id, tonumber(field), field)
	end
	-- 0.9.8's decoder too (tests/fixtures/codec-0.9.8.lua): the same line, its id a number.
	local old = {}
	assert(loadfile(ROOT .. "tests/fixtures/codec-0.9.8.lua"))("Olympus", old)
	local o = old.Codec.DecodeChat(Codec.EncodeChat("A", GUILD, 7, "WA", "hi", "rppvp"))
	eq(o.id, 407); eq(o.text, "hi"); eq(o.tier, "A")
	o = old.Codec.DecodeChat(Codec.EncodeChat("A", GUILD, 7, "WA", "hi", nil, "hardcore"))
	eq(o.id, 907); eq(o.text, "hi")
end)

-- The review of 1.5.9's first build: the box's words ("Write in [Olympus] to Roleplay... (public
-- channel)") were wider than the box leaves them in the default window, and the test counted 64
-- letters, not the box. The label already says [Olympus]: the words name the ruleset alone.
test("chat rulesets (1.5.9): the box's words fit beside its label in the default window, in every language: under the character's own ruleset (each one's name) and under another, the public channel's words with them", function()
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
	local function Letters(s) return select(2, s:gsub("[^\128-\191]", "")) end
	AsRpPvpMaster(function()
		local kept = ns.rdb.chat
		WithWindow(function(w)
			ns.me, ns.rdb.chat = ME, kept
			GetGuildInfo = function() return GUILD, "Master", 0 end
			local f = w.CW.Open("A")
			local eb = f.input
			-- The hint's room: the box less its label and the insets DrawInput gives it.
			local room = eb:GetWidth() - (math.ceil(eb.label:GetUnboundedStringWidth()) + 6) - 6
			assert(room > 100, "the box's room: " .. room)
			local perLetter = eb.hint:GetUnboundedStringWidth() / math.max(1, Letters(eb.hint:GetText() or "x"))
			Pick(f, L.CHATWIN_GROUP_RPPVP)
			assert(eb.hint:GetUnboundedStringWidth() <= room, ("under RP-PvP: %d px in %d: %s"):format(eb.hint:GetUnboundedStringWidth(), room, eb.hint:GetText()))
			eq(eb.hint:GetText(), L.CHATWIN_PLACEHOLDER_TO:format(L.CHATWIN_GROUP_RPPVP) .. L.CHATWIN_PUBLIC)
			Pick(f, L.CHATWIN_GROUP_PVE)
			assert(eb.hint:GetUnboundedStringWidth() <= room, ("under PvE: %d px in %d: %s"):format(eb.hint:GetUnboundedStringWidth(), room, eb.hint:GetText()))
			eq(eb.hint:GetText(), L.CHATWIN_PLACEHOLDER_EVERY .. L.CHATWIN_PUBLIC)
			-- Every language, each letter as wide as the box's font draws one here (6 px).
			local en = Load("enUS")
			for code, file in pairs({ enUS = false, ptBR = false, deDE = "deDE", esES = "esES", frFR = "frFR", itIT = "itIT", ruRU = "ruRU" }) do
				local l = Load(code, file or nil)
				if code ~= "enUS" then
					for _, k in ipairs({ "CHATWIN_GROUP_SEND", "CHATWIN_PLACEHOLDER_TO", "CHATWIN_PLACEHOLDER_EVERY" }) do
						assert(type(l[k]) == "string" and l[k] ~= "" and l[k] ~= en[k], code .. " translates " .. k)
					end
				end
				for _, k in ipairs({ "CHATWIN_GROUP_SEND", "CHATWIN_PLACEHOLDER_TO", "CHATWIN_PLACEHOLDER_EVERY" }) do
					eq(l[k]:find("\226\128\148", 1, true), nil, code .. " " .. k .. ": no em dash")
				end
				eq(select(2, l.CHATWIN_PLACEHOLDER_TO:gsub("%%s", "")), 1, code .. ": the ruleset alone")
				local hints = { l.CHATWIN_PLACEHOLDER_EVERY .. l.CHATWIN_PUBLIC }
				for _, kind in ipairs(KINDS) do hints[#hints + 1] = l.CHATWIN_PLACEHOLDER_TO:format(l["CHATWIN_GROUP_" .. kind]) .. l.CHATWIN_PUBLIC end
				for _, hint in ipairs(hints) do
					assert(Letters(hint) * perLetter <= room, ("%s: %d letters, %d px in %d: %s"):format(code, Letters(hint), Letters(hint) * perLetter, room, hint))
				end
			end
		end)
	end)
end)
