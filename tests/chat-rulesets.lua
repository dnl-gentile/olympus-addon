-- 1.5.9 (the dev in game on an RP-PvP character, 2026-11-12: "uma pessoa que tá no Regular [PvE] ...
-- mandou uma mensagem que apareceu no chat quando eu boto o RPPVP ... essa pessoa mandou do PVE e a
-- mensagem dela não apareceu no PVE. No all aparece e no RPPVP também aparece"; and "Quando eu mando
-- mensagem que eu tô tipo RPPVP ativo ... não tá mandando uma mensagem só lá"). The [Olympus] picker
-- filed a line by its sender's name, and on Forever the channel's text names him bare: ns.FullName
-- gave him the viewer's own sub-realm, so a PvE line went under RP-PvP. Each line is now filed as it
-- comes (Channels.SenderKind: his GUID's server id, what Olympus knows of him, else unknown and All
-- alone), and a line written under one ruleset goes to that ruleset alone (its id, Codec.EncodeChat),
-- which a client before 1.5.9 reads as the plain line it always was. Invented names throughout.
-- Loaded by tests/run.lua.
local ns, test, eq, extra = ...
local WithWindow, ADDON_DIR, FreshComm, ROOT, KeepSendGap = extra.WithWindow, extra.ADDON_DIR, extra.FreshComm, extra.ROOT, extra.KeepSendGap
local L = ns.L
local C = ns.Channels

local REALM = "CAMWOWUS2Realm1RPPvP"      -- the dev's ruleset that night
local ME = "Rose Thornwood-" .. REALM
local GUILD = "Olympus Thorns"
local OUR_SID, MATE_SID = "5100", "5101"  -- our sub-realm's server id (our GUID), a guildmate's other sub-realm
local PVE_GUILDS = { "Olympus Dawn", "Olympus Dusk", "Olympus Noon" } -- guilds the PvE family's census lists
local OUR_OTHER = "Olympus Elsewhere"     -- another guild of our family, in our own census

local function Guid(sid, n) return ("Player-%s-%08X"):format(sid, n) end
local function Line(guild, id, text, to, tier) return ns.Codec.EncodeChat(tier or "A", guild, id, "WA", text, to) end
local function Tag(kind) return "[" .. L["CHATWIN_GROUP_" .. kind] .. "]" end
local KINDS = { "PVP", "PVE", "RP", "RPPVP" }
local function Untagged(text)
	for _, k in ipairs(KINDS) do
		if tostring(text):find(Tag(k), 1, true) then return false end
	end
	return true
end
-- The kept [Olympus] line with these words, or nil.
local function Kept(text)
	for _, e in ipairs(ns.rdb.chat and ns.rdb.chat.A or {}) do if e.text == text then return e end end
	return nil
end
-- The printed lines with these words.
local function PrintedWith(printed, text)
	local n = 0
	for _, line in ipairs(printed) do if line:find(text, 1, true) then n = n + 1 end end
	return n
end
-- /oly bug's line on the rulesets.
local function BugLine() return ns.StatusText():match("\nchat rulesets: [^\n]*") or "" end
-- (Asked for, not assumed: the first test below also runs against 1.5.8's Channels.lua, which has no
-- ResetRulesets, and fails there on the bug itself, the PvE line printed under RP-PvP.)
local function Reset() if C.ResetRulesets then C.ResetRulesets() end end

-- An RP-PvP character of Forever, master of GUILD: its roster (each row with the GUID the game gives,
-- its 17th value), its own GUID, the PvE family's census rows (the group details an author's capsule
-- leaves), another guild of our family in our own census; [Olympus] on, nothing muted, the game's chat
-- in `printed`. fn(printed, errors, rows): errors caught by the addon (ns.CaptureError), and the roster's
-- rows (a test adds one and scans again). All put back after.
local function AsRpPvpMaster(fn)
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
		ns.db.groupDetails = { ["Alliance|ForeverPvE"] = { group = "ForeverPvE", faction = "Alliance", observed = now, rows = pve, source = "author" } }
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
		-- A PvE player of a guild the PvE census lists, on a server nobody named yet.
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
		local bug = BugLine()
		assert(bug:find("filed to=0 guid=2 known=1 unknown=1", 1, true), "/oly bug: how each was filed: " .. bug)
		assert(bug:find("channel text 4, with GUID 4", 1, true), "/oly bug: the channel's text and its GUIDs: " .. bug)
		assert(bug:find("here=rppvp view=rppvp sends to rppvp", 1, true), bug)
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

test("chat rulesets (1.5.9): a server id is learned from two PvE guilds of the census (one name proves nothing), then files a PvE player of any guild; a line kept unknown with that server is filed once it is learned; a server our roster names too is mixed and never used", function()
	AsRpPvpMaster(function(_, errors, rows)
		local Hear = HallWorld()
		local function Room(text) return (C.LineRoom(assert(Kept(text), text))) end
		-- An unknown guild from server 4402 first: unknown, kept with its server.
		Hear("Early-Rulebird", Guid("4402", 1), Line("Olympus Unlisted", 21, "before anyone knew"))
		eq(Room("before anyone knew"), nil, "unknown")
		-- One PvE guild of the census from that server: that line is PvE, the server not learned yet.
		Hear("Dawn-Rulespeaker", Guid("4402", 2), Line(PVE_GUILDS[1], 22, "first PvE guild"))
		eq(Room("first PvE guild"), "pve")
		Hear("Late-Rulecomer", Guid("4402", 3), Line("Olympus Unlisted", 23, "still unknown"))
		eq(Room("still unknown"), nil, "one guild's name is not enough")
		-- A second PvE guild from it: learned. A PvE player of a guild no census lists is PvE now.
		Hear("Dusk-Ruletalker", Guid("4402", 4), Line(PVE_GUILDS[2], 24, "second PvE guild"))
		Hear("New-Rulecomer", Guid("4402", 5), Line("Olympus Unlisted", 25, "known by the server"))
		eq(Room("known by the server"), "pve", "by the server's id")
		eq(Room("before anyone knew"), "pve", "a line kept unknown, filed once its server was learned")
		eq(Room("still unknown"), "pve")
		local bug = BugLine()
		assert(bug:find("filed to=0 guid=1 known=2 unknown=2", 1, true), bug)
		assert(bug:find("ids pve=1 rppvp=2, mixed 0", 1, true), "the servers known: " .. bug)
		-- Server 4403: learned PvE from two census guilds, then our roster names it (a guildmate plays
		-- there): two rulesets for one server, never used again; nothing it carries is filed by it.
		Hear("Noon-Rulevoice", Guid("4403", 1), Line(PVE_GUILDS[1], 31, "pve one"))
		Hear("Noon-Ruleother", Guid("4403", 2), Line(PVE_GUILDS[3], 32, "pve two"))
		Hear("Noon-Rulethird", Guid("4403", 3), Line("Olympus Unlisted", 33, "pve by server"))
		eq(Room("pve by server"), "pve")
		rows[#rows + 1] = { "Noon Rulemate", "Member", 3, Guid("4403", 9) }
		ns.Roster.Scan()
		Hear("Odd-Ruleone", Guid("4403", 4), Line("Olympus Unlisted", 34, "mixed server"))
		eq(Room("mixed server"), nil, "a server named for two rulesets files nothing")
		eq(Room("pve by server"), "pve", "(a line filed as it came stays so)")
		assert(BugLine():find("mixed 1", 1, true), BugLine())
		eq(#errors, 0, table.concat(errors, " | "))
	end)
end)

test("chat rulesets (1.5.9): a line by the relay is filed by its stamp (a client of its writer's family); our family's guildmate by the roster; a census name of two families says nothing", function()
	AsRpPvpMaster(function()
		local function Room(text) return (C.LineRoom(assert(Kept(text), text))) end
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
		assert(BugLine():find("filed to=0 guid=0 known=2 unknown=1", 1, true), BugLine())
	end)
end)

test("chat rulesets (1.5.9): under PvE a line written in [Olympus] goes to PvE alone: its id names PvE, a 1.5.8 client reads the same line and id; the box says where it goes; under All, and in [Captains], a line for everyone", function()
	AsRpPvpMaster(function()
		local Comm = ns.Comm
		local savedReady, savedSend = Comm.ChannelReady, Comm.SendChat
		local sent = {}
		Comm.ChannelReady = function() return true end
		Comm.SendChat = function(msg, done) sent[#sent + 1] = msg; done(true); return true end
		local old = {}
		assert(loadfile(ROOT .. "tests/fixtures/codec-1.5.8.lua"))("Olympus", old)
		-- (Channels' send gap fresh for these lines, and as it was after: KeepSendGap.)
		local ok, err = pcall(KeepSendGap, function()
			local t = 100
			eq(C.SetGroupView("pve"), true)
			eq(C.SendTo(), "pve")
			eq((C.Send("A", "only for the PvE realms", t)), true)
			local msg = sent[#sent]
			local field = msg:match("^M1~A~" .. GUILD .. "~(%d+)~PA~only for the PvE realms$")
			assert(field and field:match("^02%d%d$"), "a PvE line's id, 0 2 nn: " .. msg)
			local m = ns.Codec.DecodeChat(msg)
			eq(m.to, "pve"); eq(m.id, tonumber(field)); eq(m.text, "only for the PvE realms")
			-- A client before 1.5.9 (1.5.8's Codec): the same line, the same id, no ruleset.
			local o = old.Codec.DecodeChat(msg)
			eq(o.tier, "A"); eq(o.guild, GUILD); eq(o.id, m.id); eq(o.class, "PA"); eq(o.text, "only for the PvE realms"); eq(o.to, nil)
			-- Our echo: kept as ours, sent to PvE, with the id the others read.
			local e = Kept("only for the PvE realms")
			eq(e.mine, true); eq(e.to, "pve"); eq(e.id, m.id)
			assert(BugLine():find("view=pve sends to pve", 1, true), BugLine())
			-- [Captains] has no rulesets.
			eq((C.Send("C", "captains, all of us", t + 2)), true)
			local cm = ns.Codec.DecodeChat(sent[#sent])
			eq(cm.to, nil); assert(not sent[#sent]:find("^M1~C~[^~]+~0%d%d%d~"), sent[#sent])
			-- Under All: a line for everyone, as before.
			eq(C.SetGroupView("all"), true)
			eq(C.SendTo(), nil)
			eq((C.Send("A", "for everyone", t + 4)), true)
			local am = ns.Codec.DecodeChat(sent[#sent])
			eq(am.to, nil); assert(not sent[#sent]:find("^M1~A~[^~]+~0%d%d%d~"), sent[#sent])
			eq(Kept("for everyone").to, nil)
			-- The box says where a line goes.
			local kept = ns.rdb.chat
			WithWindow(function(w)
				ns.me, ns.rdb.chat = ME, kept
				GetGuildInfo = function() return GUILD, "Master", 0 end
				local f = w.CW.Open("A")
				local all = f.input.hint:GetText()
				eq(all:find(L.CHATWIN_PLACEHOLDER:format(L.CHAN_ALL), 1, true), 1, "under All: " .. all)
				Pick(f, L.CHATWIN_GROUP_PVE)
				local pve = f.input.hint:GetText()
				eq(pve:find(L.CHATWIN_PLACEHOLDER_TO:format(L.CHAN_ALL, L.CHATWIN_GROUP_PVE), 1, true), 1, "under PvE: " .. pve)
				-- Our own line shows under every ruleset.
				assert(Bubbles(f)["only for the PvE realms"] and Bubbles(f)["for everyone"], Words(f))
			end)
		end)
		Comm.ChannelReady, Comm.SendChat = savedReady, savedSend
		if not ok then error(err, 0) end
	end)
end)

test("chat rulesets (1.5.9): a line sent to PvE shows under PvE, whoever wrote it, and not under RP-PvP nor in an RP-PvP character's All; a line sent to RP-PvP shows in its All untagged; a [Captains] id with a leading zero is a plain one", function()
	AsRpPvpMaster(function(printed, errors)
		local Hear = HallWorld()
		local function Visible(view, text)
			C.SetGroupView(view)
			return C.GroupVisible("A", assert(Kept(text), text), false)
		end
		eq(C.SetGroupView("all"), true)
		-- A guildmate of ours writes to PvE; a PvE player writes to RP-PvP (by the relay this time).
		Hear("Thorn-Rulemate", Guid(MATE_SID, 2), Line(GUILD, 51, "for PvE eyes", "pve"))
		eq((C.Receive("CHANNEL", "Dawn Rulespeaker-CAMWOWUS1Realm2PvE", Line(PVE_GUILDS[1], 52, "for RP-PvP eyes", "rppvp"))), true)
		eq(PrintedWith(printed, "for PvE eyes"), 0, "not in our All: it was sent to PvE")
		eq(PrintedWith(printed, "for RP-PvP eyes"), 1, "sent to our ruleset: in our All")
		assert(Untagged(printed[#printed]), "our ruleset's line: no tag: " .. printed[#printed])
		eq(Kept("for PvE eyes").to, "pve"); eq(Kept("for RP-PvP eyes").to, "rppvp")
		eq(Visible("pve", "for PvE eyes"), true); eq(Visible("rppvp", "for PvE eyes"), false); eq(Visible("all", "for PvE eyes"), false)
		eq(Visible("rppvp", "for RP-PvP eyes"), true); eq(Visible("pve", "for RP-PvP eyes"), false); eq(Visible("all", "for RP-PvP eyes"), true)
		C.SetGroupView("all")
		eq(C.GroupTag("A", Kept("for RP-PvP eyes")), "", "no tag in our All")
		-- [Captains]: no rulesets, whatever its id (an officer of ours).
		local captains = "M1~C~" .. GUILD .. "~0212~WA~captains, gather"
		eq(ns.Codec.DecodeChat(captains).to, nil)
		eq(ns.Codec.DecodeChat(captains).id, 212)
		assert(BugLine():find("filed to=2 ", 1, true), BugLine())
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

test("chat rulesets (1.5.9): a line for one ruleset leaves as a four-digit id with a leading zero, the ruleset's digit and two of its id; read back as that number; never on [Captains] or [Lords]; another leading-zero id is a line for everyone", function()
	local Codec = ns.Codec
	for kind, digit in pairs({ pvp = 1, pve = 2, rp = 3, rppvp = 4 }) do
		local msg = Codec.EncodeChat("A", GUILD, 9876, "WA", "hi", kind)
		eq(msg, ("M1~A~%s~0%d76~WA~hi"):format(GUILD, digit))
		local m = Codec.DecodeChat(msg)
		eq(m.to, kind); eq(m.id, digit * 100 + 76); eq(m.id, Codec.ChatWireId(9876, "A", kind))
	end
	eq(Codec.EncodeChat("A", GUILD, 9876, "WA", "hi"), "M1~A~" .. GUILD .. "~9876~WA~hi", "for everyone: as before")
	eq(Codec.ChatWireId(9876, "A", nil), 9876)
	eq(Codec.EncodeChat("A", GUILD, 7, "", "hi", "pve"), "M1~A~" .. GUILD .. "~0207~~hi")
	for _, tier in ipairs({ "C", "L" }) do
		eq(Codec.EncodeChat(tier, GUILD, 9876, "WA", "hi", "pve"), ("M1~%s~%s~9876~WA~hi"):format(tier, GUILD), tier .. ": no ruleset")
		eq(Codec.ChatWireId(9876, tier, "pve"), 9876)
	end
	eq(Codec.EncodeChat("A", GUILD, 5, "", "hi", "all"), "M1~A~" .. GUILD .. "~5~~hi", "All is no ruleset")
	for _, field in ipairs({ "0012", "0512", "0912", "012", "02", "0" }) do
		local m = Codec.DecodeChat("M1~A~" .. GUILD .. "~" .. field .. "~~hi")
		eq(m.to, nil, field); eq(m.id, tonumber(field), field)
	end
	-- 0.9.8's decoder too (tests/fixtures/codec-0.9.8.lua): the same line, its id a number.
	local old = {}
	assert(loadfile(ROOT .. "tests/fixtures/codec-0.9.8.lua"))("Olympus", old)
	local o = old.Codec.DecodeChat(Codec.EncodeChat("A", GUILD, 7, "WA", "hi", "rppvp"))
	eq(o.id, 407); eq(o.text, "hi"); eq(o.tier, "A")
end)

test("chat rulesets (1.5.9): the picker's tooltip and the box's words in every language", function()
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
	local en = Load("enUS")
	eq(en.CHATWIN_PLACEHOLDER_TO:format("Olympus", "PvE"), "Write in [Olympus] to PvE...")
	for code, file in pairs({ ptBR = false, deDE = "deDE", esES = "esES", frFR = "frFR", itIT = "itIT", ruRU = "ruRU" }) do
		local l = Load(code, file or nil)
		for _, k in ipairs({ "CHATWIN_GROUP_SEND", "CHATWIN_PLACEHOLDER_TO" }) do
			assert(type(l[k]) == "string" and l[k] ~= "" and l[k] ~= en[k], code .. " translates " .. k)
			eq(l[k]:find("\226\128\148", 1, true), nil, code .. " " .. k .. ": no em dash")
		end
		eq(select(2, l.CHATWIN_PLACEHOLDER_TO:gsub("%%s", "")), 2, code .. ": the channel and the ruleset")
		-- One line in the box (it never wraps): with each ruleset's name and the public channel's words.
		for _, kind in ipairs(KINDS) do
			local hint = l.CHATWIN_PLACEHOLDER_TO:format("Olympus", l["CHATWIN_GROUP_" .. kind]) .. l.CHATWIN_PUBLIC
			local letters = select(2, hint:gsub("[^\128-\191]", ""))
			assert(letters <= 64, code .. " " .. kind .. ": " .. letters .. " letters: " .. hint)
		end
	end
end)
