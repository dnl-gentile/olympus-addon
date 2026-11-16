-- 1.6.0 (a report in the Olympus Discord, 14 Nov: the addon chat should say PvP or PvE; players left
-- their PvP guilds for a PvE guild and only then found it was on other servers). Forever's player-made
-- channels are one for every ruleset, so [Olympus] brings every ruleset's lines. Since 1.5.9 a line of
-- another ruleset shows its ruleset under All ("[PvE] "), but a line nobody can place (its writer on a
-- version before 1.5.9, his server not named yet, his guild in no one ruleset's census) showed bare,
-- exactly as a line of the reader's own ruleset: a PvE recruiter read as one of ours. Now such a line
-- carries "[?] " under All (Channels.GroupTag), and in the Chat tab a writer's name says on hover when
-- he plays another ruleset or nobody can place him, and that whispers and guild invites stay within
-- one ruleset (Channels.RulesetNote). Everything else a player meets of a guild keeps to his own
-- ruleset already (whispers, the Join page, guild cards, handoffs, the census). A line of the reader's
-- own ruleset that nobody can place carries [?] too (1.6.0's review: a writer before 1.5.9, not a
-- guildmate, on a server the roster does not span, his guild in no census), until its server is
-- learned. Invented names throughout. Loaded by tests/run.lua.
local ns, test, eq, extra = ...
local WithWindow, ADDON_DIR, FreshComm, ROOT = extra.WithWindow, extra.ADDON_DIR, extra.FreshComm, extra.ROOT
local L = ns.L
local C = ns.Channels

local REALM = "CAMWOWUS1Realm4PvP"         -- a PvP character's sub-realm
local FAMILY = "ForeverPvP"
local ME = "Iron Wallward-" .. REALM
local GUILD = "Olympus Ironwall"
local OUR_SIDS = { "6101", "6102", "6103", "6104", "6105", "6106" } -- the PvP sub-realms his roster spans
local OUR_GUILDS = { GUILD, "Olympus Spearline", "Olympus Hilltop" } -- guilds our own census lists
local PVE_SIDS = { "4401", "4402", "4403", "4404", "4405", "4406", "4407", "4408", "4409" }
local PVE_LISTED = { "Olympus Meadowgate", "Olympus Harvestmoon" }  -- in the PvE family's look (the author's)
local PVE_UNLISTED = { "Olympus Lanternfall", "Olympus Orchardine" } -- PvE guilds no look here lists yet
local PVP_OUTSIDE = { "6107", "6108", "6109" }                   -- PvP sub-realms none of his guild plays on
local PVP_UNLISTED = { "Olympus Flintmoor", "Olympus Thornwatch" } -- PvP guilds our census does not list

local function Guid(sid, n) return ("Player-%s-%08X"):format(sid, n) end
-- A line as a client before 1.5.9 writes it (1.5.8's own Codec: a plain id, no ruleset).
local old = {}
assert(loadfile(ROOT .. "tests/fixtures/codec-1.5.8.lua"))("Olympus", old)
local function Old(guild, id, text) return old.Codec.EncodeChat("A", guild, id, "WA", text) end
-- A line as a 1.5.9 or later client of ruleset `kind` writes it for everyone (its id names his ruleset).
local function New(guild, id, text, kind) return ns.Codec.EncodeChat("A", guild, id, "WA", text, nil, kind) end

local LABELS = { "PVP", "PVE", "RP", "RPPVP", "HARDCORE", "UNKNOWN" }
local function Tag(kind) return "[" .. L["CHATWIN_GROUP_" .. kind] .. "] " end
-- The ruleset tag before a writer's name ("PVE", "UNKNOWN"...), nil for none: in a printed line, what
-- comes before the name's link; in a bubble's header, all of it.
local function TagOf(text)
	text = tostring(text or "")
	local head = text:match("^(.-)|Hplayer:") or text
	for _, k in ipairs(LABELS) do
		if head:find(Tag(k), 1, true) then return k end
	end
	return nil
end
-- The printed line with these words.
local function Printed(printed, text)
	for _, line in ipairs(printed) do if line:find(text, 1, true) then return line end end
	error("not printed: " .. text)
end
-- The Chat tab's bubbles shown, by their line's words; the rulesets' dropdown.
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
-- What a bubble's name says on hover (its tooltip's lines).
local function Hover(b)
	assert(b.header:IsShown(), "the bubble starts its writer's group")
	b.header:Fire("OnEnter")
	local out = {}
	for _, l in ipairs(GameTooltip.lines or {}) do out[#out + 1] = tostring(l) end
	b.header:Fire("OnLeave")
	return table.concat(out, "\n")
end
local function Has(text, part) return text:find(part, 1, true) ~= nil end
-- The game's clock (GetTime) for the lines heard: far past any earlier test's, two seconds a line, so the
-- flood guard's minute (60 lines in [Olympus]) counts these lines alone, whatever ran before.
local clock = { t = 0 }
-- Channels.lua's flood guard's minute (Flooded's `recent`, reached as KeepSendGap reaches lastSend), put back
-- as it was after each test: lines timed on that clock would otherwise count for every later test's minute.
local function FloodMinute()
	for i = 1, 200 do
		local name, fn = debug.getupvalue(C.Receive, i)
		if name == nil then break end
		if name == "Flooded" then
			for j = 1, 50 do
				local inner, value = debug.getupvalue(fn, j)
				if inner == nil then break end
				if inner == "recent" then return value end
			end
		end
	end
	error("(Channels.lua's flood guard: Flooded's recent)")
end

-- A PvP character of Forever, master of GUILD: a roster of 40 spread over the PvP sub-realms (each row with
-- the GUID the game gives, its 17th value), his own GUID, our census, the PvE family's look (two of its
-- guilds); [Olympus] on, nothing muted, All shown (the default), the game's chat in `printed`, the game's
-- clock on `clock`. fn(printed, errors). All put back after, the flood guard's minute too.
local function AsPvpMember(fn)
	local saved = { realm = ns.realm, group = ns.group, split = ns.splitNames, me = ns.me, faction = ns.faction, getTime = GetTime,
		groups = ns.db.chatGroups, chat = ns.db.addonChat, mute = ns.db.chatMute, windows = ns.db.chatWindows,
		details = ns.db.groupDetails, history = ns.rdb.chat, guilds = ns.rdb.guilds, hall = ns.ChatHall,
		total = GetNumGuildMembers, info = GetGuildRosterInfo, guild = GetGuildInfo, member = ns.IsMember,
		guid = rawget(_G, "UnitGUID"), frame = DEFAULT_CHAT_FRAME, capture = ns.CaptureError }
	local errors = {}
	local minute, minuteWas = FloodMinute(), {}
	for tier, list in pairs(minute) do minuteWas[tier] = { unpack(list) } end
	local ok, err = pcall(function()
		ns.splitNames, ns.realm, ns.group, ns.me, ns.faction = true, REALM, FAMILY, ME, "Alliance"
		clock.t = 4e8
		GetTime = function() return clock.t end
		ns.IsMember = function() return true end
		GetGuildInfo = function() return GUILD, "Master", 0 end
		local rows = { { "Iron Wallward", "Master", 0, Guid(OUR_SIDS[1], 1) } }
		for i = 2, 40 do
			rows[#rows + 1] = { ("Iron Shieldmate%d"):format(i), "Member", 3, Guid(OUR_SIDS[(i - 1) % #OUR_SIDS + 1], i) }
		end
		GetNumGuildMembers = function() return #rows, #rows end
		GetGuildRosterInfo = function(i)
			local r = rows[i]
			if r then return r[1], r[2], r[3], 60, "Warrior", "Stormwind City", "", "", true, 0, "WARRIOR", 0, 0, false, false, 0, r[4] end
		end
		UnitGUID = function(unit) if unit == "player" then return Guid(OUR_SIDS[1], 1) end end
		ns.Roster.Scan()
		ns.db.addonChat, ns.db.chatMute, ns.db.chatWindows, ns.db.chatGroups = true, {}, nil, nil
		local now = ns.Now()
		ns.rdb.chat = {}
		ns.rdb.guilds = {}
		for _, name in ipairs(OUR_GUILDS) do ns.rdb.guilds[name] = { guild = name, total = 30, online = 5, zones = {}, t = now } end
		local pve = {}
		for _, name in ipairs(PVE_LISTED) do pve[name:lower()] = { name = name, total = 40, online = 9, avg10 = 500, observed = now } end
		ns.db.groupDetails = { ["Alliance|ForeverPvE"] = { group = "ForeverPvE", faction = "Alliance", observed = now, rows = pve,
			source = "author" } }
		C.ResetRulesets()
		local printed = {}
		DEFAULT_CHAT_FRAME = { AddMessage = function(_, line) printed[#printed + 1] = line end }
		ns.CaptureError = function(where, e) errors[#errors + 1] = tostring(where) .. ": " .. tostring(e) end
		fn(printed, errors)
	end)
	ns.realm, ns.group, ns.splitNames, ns.me, ns.faction = saved.realm, saved.group, saved.split, saved.me, saved.faction
	ns.db.chatGroups, ns.db.addonChat, ns.db.chatMute, ns.db.chatWindows = saved.groups, saved.chat, saved.mute, saved.windows
	ns.db.groupDetails, ns.rdb.chat, ns.rdb.guilds, ns.ChatHall = saved.details, saved.history, saved.guilds, saved.hall
	GetNumGuildMembers, GetGuildRosterInfo, GetGuildInfo, ns.IsMember = saved.total, saved.info, saved.guild, saved.member
	UnitGUID, DEFAULT_CHAT_FRAME, ns.CaptureError, GetTime = saved.guid, saved.frame, saved.capture, saved.getTime
	for tier in pairs(minute) do minute[tier] = nil end
	for tier, list in pairs(minuteWas) do minute[tier] = list end
	C_ChatInfo = nil -- (FreshComm's)
	C.ResetRulesets()
	ns.Roster.Scan() -- (the harness's own roster for the tests after this one)
	if not ok then error(err, 0) end
end

-- The channel's text as Forever's client hands it to Olympus (CHAT_MSG_CHANNEL: the line, its sender as
-- "First-Surname", the channel's base name ninth, the sender's GUID twelfth) through the real ChatHall.lua
-- and Comm.lua (a client of their own, FreshComm) to Channels.Receive, as on a live client.
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
		clock.t = clock.t + 2
		return cns.ChatHall.OnChannel(msg, sender, "", "6. OlympusNet1", "", "", 0, 6, "OlympusNet1", 0, lineID, guid)
	end
end

-- The Chat tab on [Olympus] with the lines heard, as this character. fn(w, f).
local function InTab(fn)
	local kept = ns.rdb.chat
	WithWindow(function(w)
		ns.me, ns.rdb.chat = ME, kept
		GetGuildInfo = function() return GUILD, "Master", 0 end
		fn(w, w.CW.Open("A"))
	end)
end

local LANTERN = "Olympus Lanternfall is recruiting! Whisper JOIN"
local MEADOW = "Olympus Meadowgate wants you, whisper me"
local SPEAR = "Spearline has room tonight"
local HILL = "Hilltop raids at nine"

test("ruleset labels (1.6.0): on a PvP character under All, the default, a PvE recruiter's [Olympus] line from a version before 1.5.9 that nobody can place carries [?] before his name, in the game's chat and the Chat tab, never bare as our lines are; a 1.5.9 PvE line [PvE]; our ruleset's lines none; his name's tooltip says which and that whispers and guild invites stay within one ruleset", function()
	AsPvpMember(function(printed, errors)
		local Hear = HallWorld()
		eq(C.GroupView(), "all", "(All, the default)")
		-- A PvE recruiter on 1.5.8: a PvE server nobody named here, a guild no census here lists.
		eq(Hear("Lantern-Callwright", Guid(PVE_SIDS[5], 1), Old(PVE_UNLISTED[1], 11, LANTERN)), true)
		-- A PvE recruiter on 1.5.9 or later: his line says PvE.
		eq(Hear("Meadow-Bellward", Guid(PVE_SIDS[6], 2), New(PVE_LISTED[1], 12, MEADOW, "pve")), true)
		-- Ours: a 1.5.8 member of a guild our census lists, on one of our servers; a 1.6.0 member.
		eq(Hear("Spear-Holdfast", Guid(OUR_SIDS[3], 3), Old(OUR_GUILDS[2], 13, SPEAR)), true)
		eq(Hear("Hill-Warden", Guid(OUR_SIDS[4], 4), New(OUR_GUILDS[3], 14, HILL, "pvp")), true)
		eq(#errors, 0, table.concat(errors, " | "))
		eq(C.LineRoom(ns.rdb.chat.A[1]), nil, "(the 1.5.8 PvE line: nobody can place it, All alone)")
		-- The game's chat (no dropdown there).
		eq(TagOf(Printed(printed, LANTERN)), "UNKNOWN", "a line nobody can place: [?], not bare like ours: " .. Printed(printed, LANTERN))
		eq(TagOf(Printed(printed, MEADOW)), "PVE")
		eq(TagOf(Printed(printed, SPEAR)), nil, "ours: no tag")
		eq(TagOf(Printed(printed, HILL)), nil, "ours: no tag")
		local line = Printed(printed, LANTERN)
		local at, name = line:find(Tag("UNKNOWN"), 1, true), line:find("|Hplayer:", 1, true)
		assert(at and name and at < name, "[?] before his name: " .. line)
		-- The Chat tab under All, and its names' tooltips.
		InTab(function(_, f)
			local b = Bubbles(f)
			eq(TagOf(b[LANTERN].who:GetText()), "UNKNOWN", b[LANTERN].who:GetText())
			eq(TagOf(b[MEADOW].who:GetText()), "PVE")
			eq(TagOf(b[SPEAR].who:GetText()), nil); eq(TagOf(b[HILL].who:GetText()), nil)
			local tip = Hover(b[LANTERN])
			assert(Has(tip, L.CHATWIN_RULESET_UNKNOWN), "nobody can place him: " .. tip)
			assert(Has(tip, L.CHATWIN_WHISPER_TIP:format("Lantern Callwright")), "the whisper's line still: " .. tip)
			tip = Hover(b[MEADOW])
			assert(Has(tip, L.CHATWIN_RULESET_OTHER:format(L.CHATWIN_GROUP_PVE)), "PvE servers: " .. tip)
			for _, text in ipairs({ SPEAR, HILL }) do
				tip = Hover(b[text])
				assert(not Has(tip, L.CHATWIN_RULESET_UNKNOWN) and not Has(tip, L.CHATWIN_RULESET_OTHER:sub(1, 8)), "ours: no note: " .. tip)
			end
			-- PvE chosen: one ruleset alone, no tag in the tab (1.5.5, the dropdown names it); the name still says PvE.
			Pick(f, L.CHATWIN_GROUP_PVE)
			b = Bubbles(f)
			eq(b[LANTERN], nil, "nobody can place it: All alone")
			eq(TagOf(b[MEADOW].who:GetText()), nil, "one ruleset shown: no tag")
			assert(Has(Hover(b[MEADOW]), L.CHATWIN_RULESET_OTHER:format(L.CHATWIN_GROUP_PVE)), "his name still says PvE")
			Pick(f, L.CHATWIN_GROUP_PVP)
			b = Bubbles(f)
			eq(TagOf(b[SPEAR].who:GetText()), nil); eq(b[MEADOW], nil); eq(b[LANTERN], nil)
			Pick(f, L.CHATWIN_GROUP_ALL)
		end)
	end)
end)

test("ruleset labels (1.6.0): a line marked [?] takes its ruleset's tag once two 1.5.9 writers name its server; a guild of the PvE family's look files a 1.5.8 PvE line as PvE with no server known", function()
	AsPvpMember(function(printed, errors)
		local Hear = HallWorld()
		Hear("Orchard-Keeper", Guid(PVE_SIDS[7], 1), Old(PVE_UNLISTED[2], 21, "Orchardine recruits"))
		eq(C.GroupTag("A", ns.rdb.chat.A[1]), Tag("UNKNOWN"))
		Hear("Harvest-Caller", Guid(PVE_SIDS[8], 2), Old(PVE_LISTED[2], 22, "Harvestmoon recruits"))
		eq(TagOf(Printed(printed, "Harvestmoon recruits")), "PVE", "its guild in the PvE look alone")
		-- Two writers of 1.5.9 or later on the first one's server: it is PvE's now.
		Hear("Orchard-Second", Guid(PVE_SIDS[7], 3), New(PVE_UNLISTED[2], 23, "first word", "pve"))
		Hear("Orchard-Third", Guid(PVE_SIDS[7], 4), New(PVE_UNLISTED[2], 24, "second word", "pve"))
		eq(C.GroupTag("A", ns.rdb.chat.A[1]), Tag("PVE"), "learned: [PvE]")
		eq(C.RulesetNote("A", ns.rdb.chat.A[1]), L.CHATWIN_RULESET_OTHER:format(L.CHATWIN_GROUP_PVE))
		Hear("Orchard-Keeper", Guid(PVE_SIDS[7], 1), Old(PVE_UNLISTED[2], 25, "Orchardine again"))
		eq(TagOf(Printed(printed, "Orchardine again")), "PVE")
		eq(#errors, 0, table.concat(errors, " | "))
	end)
end)

-- 1.6.0's review: a line of the reader's own ruleset can be one nobody can place too. A PvP player on 1.5.8,
-- not of the reader's guild, on a PvP server none of his guild plays on, his guild in no census here, reads
-- exactly as an older PvE recruiter does: [?], and his name says only that he may be on other servers. His
-- server learned (two later writers' word), his lines are ours, the kept ones too (Channels.LineKind reads
-- the server again); his guild in our census, his next lines are, but a kept one stays [?] until its server
-- is named (it was kept unknown, Channels.SenderKind's census is read as a line comes).
local FLINT = "Flintmoor raids tonight"
local THORN = "Thornwatch needs a healer"
test("ruleset labels (1.6.0): a line of our own ruleset from a version before 1.5.9 that nobody can place carries [?] too (not of our guild, on a server our roster does not span, his guild in no census), and his name says only that he may be on other servers; once two writers of 1.5.9 or later name his server, his lines show bare, the Chat tab's kept ones too; once our census lists his guild, his next lines do", function()
	AsPvpMember(function(printed, errors)
		local Hear = HallWorld()
		eq(Hear("Flint-Moorward", Guid(PVP_OUTSIDE[1], 1), Old(PVP_UNLISTED[1], 31, FLINT)), true)
		eq(Hear("Thorn-Keepwell", Guid(PVP_OUTSIDE[2], 2), Old(PVP_UNLISTED[2], 32, THORN)), true)
		eq(#errors, 0, table.concat(errors, " | "))
		local flint, thorn = ns.rdb.chat.A[1], ns.rdb.chat.A[2]
		eq(flint.text, FLINT); eq(thorn.text, THORN)
		eq(C.LineRoom(flint), nil, "(nobody can place him: All alone)")
		eq(TagOf(Printed(printed, FLINT)), "UNKNOWN", "a PvP player nobody can place: [?], as any other: " .. Printed(printed, FLINT))
		eq(TagOf(Printed(printed, THORN)), "UNKNOWN")
		eq(C.RulesetNote("A", flint), L.CHATWIN_RULESET_UNKNOWN, "his name: nobody can place him, never another ruleset's servers")
		InTab(function(_, f)
			local b = Bubbles(f)
			eq(TagOf(b[FLINT].who:GetText()), "UNKNOWN", b[FLINT].who:GetText())
			local tip = Hover(b[FLINT])
			assert(Has(tip, L.CHATWIN_RULESET_UNKNOWN), "nobody can place him: " .. tip)
			-- Under PvP, his own ruleset's view, a line nobody can place shows in none (1.5.9: All alone).
			Pick(f, L.CHATWIN_GROUP_PVP)
			eq(Bubbles(f)[FLINT], nil, "All alone")
			Pick(f, L.CHATWIN_GROUP_ALL)
		end)
		-- Two writers of 1.5.9 or later on his server: it is PvP's now, and so are his lines.
		Hear("Flint-Second", Guid(PVP_OUTSIDE[1], 3), New(PVP_UNLISTED[1], 33, "Flintmoor word one", "pvp"))
		Hear("Flint-Third", Guid(PVP_OUTSIDE[1], 4), New(PVP_UNLISTED[1], 34, "Flintmoor word two", "pvp"))
		eq(TagOf(Printed(printed, "Flintmoor word one")), nil, "a later writer of ours: no tag")
		eq(C.GroupTag("A", flint), "", "his kept line: ours now, no tag")
		eq(C.RulesetNote("A", flint), nil, "and no note")
		eq(TagOf(Printed(printed, FLINT)), "UNKNOWN", "(what the game's chat printed stays as it was)")
		Hear("Flint-Moorward", Guid(PVP_OUTSIDE[1], 1), Old(PVP_UNLISTED[1], 35, "Flintmoor again"))
		eq(TagOf(Printed(printed, "Flintmoor again")), nil, "his next line: no tag")
		-- Our census lists the other one's guild: his next line is ours; his kept line, its server named by
		-- nobody yet, keeps [?].
		ns.rdb.guilds[PVP_UNLISTED[2]] = { guild = PVP_UNLISTED[2], total = 20, online = 4, zones = {}, t = ns.Now() }
		Hear("Thorn-Keepwell", Guid(PVP_OUTSIDE[2], 2), Old(PVP_UNLISTED[2], 36, "Thornwatch again"))
		eq(TagOf(Printed(printed, "Thornwatch again")), nil, "his guild in our census: no tag")
		eq(C.GroupTag("A", thorn), Tag("UNKNOWN"), "his kept line: [?] still")
		InTab(function(_, f)
			local b = Bubbles(f)
			eq(TagOf(b[FLINT].who:GetText()), nil, "the Chat tab: his kept line without a tag now")
			assert(not Has(Hover(b[FLINT]), L.CHATWIN_RULESET_UNKNOWN), "no note once placed")
			eq(TagOf(b[THORN].who:GetText()), "UNKNOWN")
			Pick(f, L.CHATWIN_GROUP_PVP)
			assert(Bubbles(f)[FLINT], "his kept line under PvP now")
			Pick(f, L.CHATWIN_GROUP_ALL)
		end)
		eq(#errors, 0, table.concat(errors, " | "))
	end)
end)

test("ruleset labels (1.6.0): no [?] and no note where nothing is compared: off Forever, on a realm of no Forever ruleset, on [Captains] and [Lords], without the line, on our own line or one sent to our ruleset; nor on another room's bubble drawn while the tab shows [Olympus]", function()
	AsPvpMember(function()
		local unknown = { t = 1000, sender = "Nobody Placed-" .. REALM, guild = "Olympus Nowhere", text = "who knows", kind = false }
		local pve = { t = 1001, sender = "Pve Speaker-" .. REALM, guild = PVE_LISTED[1], text = "from PvE", kind = "pve" }
		local ours = { t = 1002, sender = "Spear Holdfast-" .. REALM, guild = OUR_GUILDS[2], text = "from ours", kind = "pvp" }
		local mine = { t = 1003, sender = ME, guild = GUILD, text = "my own", mine = true, kind = "pvp" }
		local toUs = { t = 1004, sender = "Hill Warden-" .. REALM, guild = OUR_GUILDS[3], text = "for PvP", kind = "pvp", to = "pvp" }
		eq(C.GroupTag("A", unknown), Tag("UNKNOWN")); eq(C.RulesetNote("A", unknown), L.CHATWIN_RULESET_UNKNOWN)
		eq(C.GroupTag("A", pve), Tag("PVE"))
		for _, e in ipairs({ ours, mine, toUs }) do
			eq(C.GroupTag("A", e), "", e.text); eq(C.RulesetNote("A", e), nil, e.text)
		end
		for _, tier in ipairs({ "C", "L" }) do
			eq(C.GroupTag(tier, unknown), "", tier); eq(C.RulesetNote(tier, unknown), nil, tier)
			eq(C.GroupTag(tier, pve), "", tier); eq(C.RulesetNote(tier, pve), nil, tier)
		end
		eq(C.GroupTag("A", nil), "", "no line"); eq(C.RulesetNote("A", nil), nil)
		-- Another ruleset's view: the game's chat as 1.5.5 shows it, its lines without a tag.
		eq(C.SetGroupView("pve"), true)
		eq(C.GroupTag("A", pve), ""); eq(C.GroupTag("A", unknown), "")
		eq(C.RulesetNote("A", pve), L.CHATWIN_RULESET_OTHER:format(L.CHATWIN_GROUP_PVE), "the tab's name tooltip, whatever the view")
		C.SetGroupView("all")
		-- A realm of no Forever ruleset (the beta's, where names split too): nothing to compare a line with.
		ns.realm, ns.group = "ClassicBetaPvP", "ClassicBetaPvP+ClassicBetaPvP2"
		eq(C.MyKind(), nil)
		eq(C.GroupTag("A", unknown), "", "no [?] where our own ruleset is unknown"); eq(C.RulesetNote("A", unknown), nil)
		eq(C.RulesetNote("A", pve), nil)
		ns.realm, ns.group = REALM, FAMILY
		-- Off Forever: names do not split, no rulesets at all.
		ns.splitNames = nil
		eq(C.GroupTag("A", unknown), ""); eq(C.GroupTag("A", pve), ""); eq(C.RulesetNote("A", pve), nil)
		ns.splitNames = true
		-- A bubble of another room (an embedded pane's) drawn while the tab shows [Olympus]: tagged by its own room.
		InTab(function(w)
			local CW = w.CW
			local e = { t = 2000, sender = "Room Talker-" .. REALM, guild = GUILD, text = "a room's line" }
			eq(C.GroupTag("A", e), Tag("UNKNOWN"), "(as an [Olympus] line, nobody could place it)")
			local v = CW.ViewOf(e, nil)
			local who = CW.HeaderOf(v, e, false, "bones:fixture")
			eq(TagOf(who), nil, "another room's bubble: no ruleset tag: " .. tostring(who))
			eq(v.note, nil)
			v.headed = false
			who = CW.HeaderOf(v, e, false, "A")
			eq(TagOf(who), "UNKNOWN", "the same line as [Olympus]'s: [?]")
			eq(v.note, L.CHATWIN_RULESET_UNKNOWN)
		end)
	end)
end)

-- The report's situation on several clients: a PvP reader of this build under All (the default) hears,
-- through the channel's text, PvE recruiters, members of our other PvP guilds, and PvP players of guilds no
-- census here lists on PvP servers his roster does not span, on 1.5.8 (1.5.8's own Codec) and on 1.5.9 or
-- later, in three waves (1.5.8, then the later writers, two of them on each of two PvE servers and two on
-- one of those PvP servers, then 1.5.8 again). Counted in the game's chat and the Chat tab: each PvE line
-- labelled with its ruleset, marked [?], or bare (read as ours); each PvP line bare, marked [?], or under
-- another ruleset's tag. (1.6.0's review: the first version of this test put every PvP writer on one of the
-- roster's servers or in a guild of our census, so every PvP line showed bare; a PvP line nobody can place
-- is marked [?] as any other, until its server is learned: the game's chat keeps what it printed, the Chat
-- tab reads the server again.) A 1.5.9 reader shows what the candidate did (Channels.lua and ChatWindow.lua
-- unchanged since 1.5.9); a reader before 1.5.9 knows no ruleset and shows every line bare, which no later
-- version can change.
test("ruleset labels (1.6.0), simulated: a PvP reader under All hears 18 PvE recruiters (12 on 1.5.8, 6 on 1.5.9 or later), 15 PvP members of guilds our census lists on our servers (10 on 1.5.8, 5 later) and 9 PvP players of guilds no census lists on servers our roster does not span (7 on 1.5.8, 2 later on one server); no PvE line shows bare, in the game's chat or the Chat tab; every line of the 15 does; of the 9, a line of 1.5.8 shows [?] until two later writers name its server, and none another ruleset's tag", function()
	local minuteBefore = #(FloodMinute().A or {})
	AsPvpMember(function(printed, errors)
		local Hear = HallWorld()
		local lines, n = {}, 0
		local function Say(writer, sid, guild, ruleset, kindWord)
			n = n + 1
			local text = ("%s recruiting, line %d"):format(guild, n)
			lines[#lines + 1] = { text = text, ruleset = ruleset }
			Hear(writer .. "-Sim" .. n, Guid(sid, n), kindWord and New(guild, n, text, kindWord) or Old(guild, n, text))
		end
		local pveGuilds = { PVE_LISTED[1], PVE_LISTED[2], PVE_UNLISTED[1], PVE_UNLISTED[2] }
		-- Wave 1: 6 PvE recruiters, 5 PvP members and 4 PvP players of guilds no census lists (two on server
		-- 6107, one each on 6108 and 6109) on 1.5.8.
		for i = 1, 6 do Say("Pve", PVE_SIDS[i], pveGuilds[(i - 1) % 4 + 1], "pve") end
		for i = 1, 5 do Say("Pvp", OUR_SIDS[(i - 1) % #OUR_SIDS + 1], OUR_GUILDS[i % 2 + 2], "pvp") end
		for i, sid in ipairs({ PVP_OUTSIDE[1], PVP_OUTSIDE[1], PVP_OUTSIDE[2], PVP_OUTSIDE[3] }) do
			Say("Pvpout", sid, PVP_UNLISTED[(i - 1) % 2 + 1], "out")
		end
		-- Wave 2: 6 PvE recruiters on 1.5.9 or later (two on server 4401, two on 4402, one each on 4403, 4404),
		-- 5 PvP members on 1.6.0, and two PvP players of a guild no census lists on 1.5.9 or later, on 6107.
		for _, sid in ipairs({ PVE_SIDS[1], PVE_SIDS[1], PVE_SIDS[2], PVE_SIDS[2], PVE_SIDS[3], PVE_SIDS[4] }) do
			Say("Pvenew", sid, PVE_UNLISTED[1], "pve", "pve")
		end
		for i = 1, 5 do Say("Pvpnew", OUR_SIDS[i], OUR_GUILDS[i % 2 + 2], "pvp", "pvp") end
		for _ = 1, 2 do Say("Pvpoutnew", PVP_OUTSIDE[1], PVP_UNLISTED[1], "out", "pvp") end
		-- Wave 3: 6 more PvE recruiters on 1.5.8 (servers 4401 and 4402, learned; 4403 and 4404, one word
		-- each; 4407 and 4408, none), 5 more PvP members on 1.5.8, and 3 more PvP players of guilds no census
		-- lists on 1.5.8 (6107, learned; 6108 and 6109, none).
		for i, sid in ipairs({ PVE_SIDS[1], PVE_SIDS[2], PVE_SIDS[3], PVE_SIDS[4], PVE_SIDS[7], PVE_SIDS[8] }) do
			Say("Pveold", sid, pveGuilds[i % 4 + 1], "pve")
		end
		for i = 1, 5 do Say("Pvpold", OUR_SIDS[(i + 1) % #OUR_SIDS + 1], OUR_GUILDS[(i + 1) % 2 + 2], "pvp") end
		for i, sid in ipairs({ PVP_OUTSIDE[1], PVP_OUTSIDE[2], PVP_OUTSIDE[3] }) do
			Say("Pvpoutold", sid, PVP_UNLISTED[i % 2 + 1], "out")
		end
		eq(#errors, 0, table.concat(errors, " | "))
		eq(#lines, 42)
		local function Count(tagOf)
			local c = { pve = { labelled = 0, unknown = 0, bare = 0, other = 0 }, pvp = { bare = 0, unknown = 0, other = 0 },
				out = { bare = 0, unknown = 0, other = 0 } }
			for _, l in ipairs(lines) do
				local tag = tagOf(l.text)
				local row = c[l.ruleset]
				if l.ruleset == "pve" then
					if tag == "PVE" then row.labelled = row.labelled + 1
					elseif tag == "UNKNOWN" then row.unknown = row.unknown + 1
					elseif tag == nil then row.bare = row.bare + 1
					else row.other = row.other + 1 end
				else
					if tag == nil then row.bare = row.bare + 1
					elseif tag == "UNKNOWN" then row.unknown = row.unknown + 1
					else row.other = row.other + 1 end
				end
			end
			return c
		end
		local chat = Count(function(text) return TagOf(Printed(printed, text)) end)
		local tab
		InTab(function(_, f)
			local b = Bubbles(f)
			tab = Count(function(text) return TagOf(assert(b[text], "in the Chat tab: " .. text).who:GetText()) end)
		end)
		local function Say2(where, c)
			return ("%s: PvE lines %d: [PvE] %d, [?] %d, bare %d, other %d; PvP lines %d: bare %d, [?] %d, other %d; "
				.. "PvP lines of unlisted guilds off our servers %d: bare %d, [?] %d, other %d"):format(where,
				18, c.pve.labelled, c.pve.unknown, c.pve.bare, c.pve.other, 15, c.pvp.bare, c.pvp.unknown, c.pvp.other,
				9, c.out.bare, c.out.unknown, c.out.other)
		end
		print("    simulated, a PvP reader under All: " .. Say2("the game's chat", chat))
		print("    simulated, a PvP reader under All: " .. Say2("the Chat tab", tab))
		for where, c in pairs({ ["the game's chat"] = chat, ["the Chat tab"] = tab }) do
			eq(c.pve.bare, 0, where .. ": no PvE line bare, read as ours")
			eq(c.pve.other, 0, where .. ": no PvE line under another ruleset's tag")
			-- (The 6 later writers' lines say PvE, as do 8 lines of 1.5.8 placed by the PvE look's guilds or by the
			-- two servers the later writers named; the other 4 nobody can place.)
			eq(c.pve.labelled, 14, where .. ": [PvE]"); eq(c.pve.unknown, 4, where .. ": [?]")
			eq(c.pvp.bare, 15, where .. ": our lines bare")
			eq(c.out.other, 0, where .. ": a PvP line under another ruleset's tag")
		end
		-- (Of the 9: the 2 later writers' lines say PvP; wave 3's line on 6107, learned by then, is placed by its
		-- server; the other 6 of 1.5.8 nobody could place when they came, and the game's chat printed them so.
		-- The Chat tab reads the server again: wave 1's two lines on 6107 are ours there now, and only the 4 on
		-- 6108 and 6109, servers nobody named, keep [?].)
		eq(chat.out.unknown, 6, "the game's chat: [?]"); eq(chat.out.bare, 3, "the game's chat: bare")
		eq(tab.out.unknown, 4, "the Chat tab: [?]"); eq(tab.out.bare, 5, "the Chat tab: bare")
	end)
	eq(#(FloodMinute().A or {}), minuteBefore, "the flood guard's minute as it was, for the tests after")
end)

test("ruleset labels (1.6.0): the [?] tag and the name's notes in every language: translated, one ruleset in the other servers' note, no em dash; the rulesets' tooltip names [?]", function()
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
	for _, k in ipairs({ "CHATWIN_GROUP_UNKNOWN", "CHATWIN_RULESET_OTHER", "CHATWIN_RULESET_UNKNOWN" }) do
		assert(type(rawget(en, k)) == "string" and rawget(en, k) ~= "", "English " .. k)
	end
	for code, file in pairs({ enUS = false, ptBR = false, deDE = "deDE", esES = "esES", frFR = "frFR", itIT = "itIT", ruRU = "ruRU" }) do
		local l = Load(code, file or nil)
		eq(l.CHATWIN_GROUP_UNKNOWN, "?", code .. ": the [?] tag")
		assert(Has(l.CHATWIN_GROUP_TIP, "[?]"), code .. ": the rulesets' tooltip names [?]: " .. l.CHATWIN_GROUP_TIP)
		eq(select(2, l.CHATWIN_RULESET_OTHER:gsub("%%s", "")), 1, code .. ": one ruleset in the other servers' note")
		eq(select(2, l.CHATWIN_RULESET_OTHER:gsub("%%", "")), 1, code .. ": no other format code")
		eq(l.CHATWIN_RULESET_UNKNOWN:find("%", 1, true), nil, code .. ": no format code")
		for _, k in ipairs({ "CHATWIN_GROUP_TIP", "CHATWIN_RULESET_OTHER", "CHATWIN_RULESET_UNKNOWN" }) do
			eq(l[k]:find("\226\128\148", 1, true), nil, code .. " " .. k .. ": no em dash")
			if code ~= "enUS" then assert(l[k] ~= en[k], code .. " translates " .. k) end
		end
		assert(Has(l.CHATWIN_RULESET_UNKNOWN, "1.5.9"), code .. ": the version that started saying it")
	end
end)

-- The README and the CurseForge page tell of the [?] in the same words (the store page cuts the Chat tab's
-- section, scripts/curseforge-page.lua). 1.6.0's review: "there only a line of your own ruleset shows without
-- a tag" read as if every line of one's own ruleset did; a line of it that nobody can place is marked too.
local function Page(path)
	local f = assert(io.open(ROOT .. path))
	local s = f:read("*a")
	f:close()
	return (s:gsub("%s+", " "))
end
local function RulesetBullet(path)
	return assert(Page(path):match("On Forever, %[Olympus%] has a ruleset dropdown(.-)`chat rulesets:` line"), path .. ": the ruleset dropdown's bullet")
end
test("ruleset labels (1.6.0): the README and the CurseForge page say, in the same words, that a line nobody can place is marked [?] even when its writer plays the reader's own ruleset, and that a line shows without a tag only when Olympus places it on his own", function()
	local bullets = {}
	for _, path in ipairs({ "README.md", "docs/CURSEFORGE.md" }) do
		local bullet = RulesetBullet(path)
		for _, phrase in ipairs({ "one nobody can place shows under **All** alone, marked **[?]** (1.6.0), even when its writer plays your own ruleset",
			"there a line shows without a tag only when Olympus places it on your own ruleset" }) do
			assert(bullet:find(phrase, 1, true), path .. ": " .. phrase)
		end
		bullets[#bullets + 1] = bullet
	end
	eq(bullets[1], bullets[2], "the same words on both pages")
end)

-- 1.6.0's review: the pages gave "his guild cannot invite your character" to a writer nobody can place too,
-- who may play the reader's own ruleset; his name's note says only that he may be on other servers
-- (CHATWIN_RULESET_UNKNOWN), the other servers' note that this character cannot join his guild.
test("ruleset labels (1.6.0): the README and the CurseForge page give the guild invite that cannot reach your character to another ruleset's writer alone, as the name's notes do; of a writer nobody can place they say only that", function()
	assert(Has(L.CHATWIN_RULESET_OTHER, "cannot join this player's guild"), L.CHATWIN_RULESET_OTHER)
	assert(Has(L.CHATWIN_RULESET_UNKNOWN, "may be on other servers") and not Has(L.CHATWIN_RULESET_UNKNOWN, "cannot"), L.CHATWIN_RULESET_UNKNOWN)
	for _, path in ipairs({ "README.md", "docs/CURSEFORGE.md" }) do
		local bullet = RulesetBullet(path)
		assert(bullet:find("Hovering a writer's name says when he plays another ruleset (whispers and guild invites stay within one ruleset, so his guild cannot invite your character) or that nobody can place him.", 1, true),
			path .. ": the hover's sentence")
		eq(select(2, bullet:gsub("cannot invite your character", "")), 1, path .. ": said once, of another ruleset's writer")
		assert(not bullet:find("nobody can place him: whispers and guild invites", 1, true), path .. ": said of one nobody can place")
	end
end)
